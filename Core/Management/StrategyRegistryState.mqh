//+------------------------------------------------------------------+
//| Strategy Registry State (Phase C, Slice 4 - C8)                  |
//| Registry bookkeeping and per-strategy enable-state extracted from |
//| CEnterpriseStrategyManager:                                       |
//|   - RegisterStrategy        (registration bookkeeping: registry   |
//|                              gate, capacity gate, strategy Init / |
//|                              AI init / risk-injection validation, |
//|                              entry append, health-monitor         |
//|                              enrolment, registration log)         |
//|   - AutoRegisterStrategies  (the built-in strategy inventory)     |
//|   - FindStrategyIndexByName (name -> index lookup)                |
//|   - GetStrategyByName       (name -> IStrategy* lookup)           |
//|   - IsStrategyLiveVoter     ("is strategy X an enabled live       |
//|                              voter?" enable-state query)          |
//|   - SetStrategyRoleByName / SetStrategyClusterByName /            |
//|     SetStrategyLiveVotingEligibilityByName /                      |
//|     SetStrategyGovernanceByName (registry-entry metadata          |
//|                              bookkeeping)                         |
//|                                                                   |
//| This module MUTATES the manager, so it holds a NON-const back-    |
//| pointer and writes through the manager's narrow per-field         |
//| accessors. It mirrors no injected manager pointer (the registry / |
//| trade manager / position sizer / risk manager are re-read from    |
//| the manager on every call), so - like Slice 2/3 - it needs no     |
//| re-sync on Deinit or on the manager's injection setters.          |
//|                                                                   |
//| HARD GUARD - DELIBERATELY NOT MOVED:                              |
//|   - SyncEnabledWithRegistry(). It reconciles the enable flags     |
//|     against the shared CStrategyRegistry and therefore belongs to |
//|     the C9 consensus-core reconciliation step. Its body must stay |
//|     verbatim in the manager and its only call site is             |
//|     Core/Orchestration/EAOrchestrator.mqh:768. Slice 3 already    |
//|     recorded the same guard for C7.                               |
//|   - EvaluateConsensusInternal and the rest of the C9 core, which  |
//|     call IsStrategyLiveVoter(). The manager therefore keeps a     |
//|     private same-signature forwarder so those bodies are byte-    |
//|     stable.                                                       |
//|   - UpdateStrategyWeightByName / SetStrategyConfidenceThresholdByName.|
//|     Both are name lookups, but what they write is WEIGHT and      |
//|     CONFIDENCE THRESHOLD - C4 weighting/config territory, which   |
//|     Slice 2 deliberately left in the manager. Only the registry   |
//|     metadata setters (role / cluster / live-voting) move here.    |
//|   - The 35-field StrategyEntry initialiser block. It stays in the |
//|     manager behind the narrow, logic-free mutator                 |
//|     AppendRegisteredStrategyEntry(), exactly like C4's            |
//|     ApplyRawStrategyWeight(): relocating it would otherwise need  |
//|     a write accessor for every field of the struct.               |
//|                                                                   |
//| NOTE: this header is an implementation detail of                  |
//| EnterpriseStrategyManager.mqh and is included from there (after   |
//| the shared free helpers, before the manager class). It is not     |
//| intended to be included standalone.                               |
//+------------------------------------------------------------------+
#ifndef STRATEGY_REGISTRY_STATE_MQH
#define STRATEGY_REGISTRY_STATE_MQH

#include "../Utils/Enums.mqh"                       // ENUM_STRATEGY_TIER / ROLE / CLUSTER, ENUM_INTRABAR_POLICY
#include "../../Interfaces/IStrategy.mqh"           // IStrategy::Init / InitializeAI / ValidateRiskManagerInjection
#include "../Strategy/StrategyRegistry.mqh"         // CStrategyRegistry::IsStrategyActive
#include "StrategyHealthMonitor.mqh"                // CStrategyHealthMonitor::RegisterStrategy

// Retained production strategy inventory (7 kept in codebase)
#include "../../Strategies/SimpleMomentumStrategy.mqh"
#include "../../Strategies/StrategyTrend.mqh"
#include "../../Strategies/StrategySupportResistance.mqh"
#include "../../Strategies/StrategyCandlestick.mqh"
#include "../../Strategies/MeanReversionStrategy.mqh"
#include "../../Strategies/VolatilityBreakoutStrategy.mqh"
#include "../../Strategies/StatisticalArbitrageStrategy.mqh"

// Batch 103: New ICT/SMC strategies
#include "../../Strategies/FVGScalperStrategy.mqh"
#include "../../Strategies/TurtleSoupStrategy.mqh"
#include "../../Strategies/BreakerBlockStrategy.mqh"
#include "../../Strategies/NYOpenGapStrategy.mqh"
#include "../../Strategies/AsianRangeBreakStrategy.mqh"

class CEnterpriseStrategyManager;   // forward: held as a mutable pointer

//+------------------------------------------------------------------+
//| Registry / enable-state facade over CEnterpriseStrategyManager    |
//+------------------------------------------------------------------+
class CStrategyRegistryState
{
private:
    CEnterpriseStrategyManager* m_src;

public:
    CStrategyRegistryState() : m_src(NULL) {}

    void SetSource(CEnterpriseStrategyManager* src) { m_src = src; }

    //--- registration bookkeeping
    bool RegisterStrategy(IStrategy* strategy, const string name,
                          bool enabled, double weight,
                          ENUM_STRATEGY_TIER tier,
                          ENUM_TIMEFRAMES tf,
                          ENUM_INTRABAR_POLICY intrabarPolicy,
                          ENUM_STRATEGY_ROLE role,
                          ENUM_STRATEGY_CLUSTER cluster,
                          bool liveVotingEnabled);
    void AutoRegisterStrategies(bool &flags[]);

    //--- lookups
    int        FindStrategyIndexByName(const string name) const;
    IStrategy* GetStrategyByName(const string name) const;

    //--- enable-state query
    bool IsStrategyLiveVoter(const int strategyIndex) const;

    //--- registry-entry metadata bookkeeping
    bool SetStrategyRoleByName(const string name, ENUM_STRATEGY_ROLE role);
    bool SetStrategyClusterByName(const string name, ENUM_STRATEGY_CLUSTER cluster);
    bool SetStrategyLiveVotingEligibilityByName(const string name, const bool enabled);
    bool SetStrategyGovernanceByName(const string name,
                                     ENUM_STRATEGY_ROLE role,
                                     ENUM_STRATEGY_CLUSTER cluster,
                                     const bool liveVotingEnabled);
};

//+------------------------------------------------------------------+
//| Register Strategy                                                |
//+------------------------------------------------------------------+
bool CStrategyRegistryState::RegisterStrategy(IStrategy* strategy, const string name,
                                              bool enabled, double weight,
                                              ENUM_STRATEGY_TIER tier,
                                              ENUM_TIMEFRAMES tf,
                                              ENUM_INTRABAR_POLICY intrabarPolicy,
                                              ENUM_STRATEGY_ROLE role,
                                              ENUM_STRATEGY_CLUSTER cluster,
                                              bool liveVotingEnabled)
{
    if(m_src == NULL)
        return false;

    if(strategy == NULL || !m_src.IsManagerInitialized())
        return false;

    // L1-010: Check with StrategyRegistry if this strategy should be active in current mode
        // The 'enabled' parameter is advisory; registry is the single source of truth
        CStrategyRegistry* strategyRegistry = m_src.GetStrategyRegistryConst();
        if(strategyRegistry != NULL)
        {
            // Check if strategy is registered and mode-permissive
            if(!strategyRegistry.IsStrategyActive(name))
            {
                PrintFormat("[ENTERPRISE] Strategy %s disabled by registry (mode filter or not registered)", name);
                enabled = false;  // Override: registry says this strategy is not active
            }
        }

    // Prevent unbounded strategy growth
    if(m_src.GetStrategyCount() >= m_src.GetMaxStrategies())
    {
        Print("[EnterpriseStrategyManager] ERROR: Max strategy limit reached (", m_src.GetMaxStrategies(), ")");
        delete strategy;
        return false;
    }

    // Initialize strategy with VALID pointers (ARCHITECTURAL FIX: inject unified risk manager)
    ENUM_TIMEFRAMES resolvedTf = (tf == PERIOD_CURRENT ? m_src.GetBaseTimeframe() : tf);
    bool initSuccess = strategy.Init(m_src.GetManagedSymbol(), resolvedTf,
                                     m_src.GetTradeManagerConst(), m_src.GetPositionSizerConst(),
                                     m_src.GetUnifiedRiskManagerConst());

    if(!initSuccess)
        {
            Print("[EnterpriseStrategyManager] ERROR: Strategy ", name, " initialization failed. Skipping registration.");
            delete strategy;
            return false;
        }

    // L6-010: Initialize AI model after factory creation
    // This ensures AI adapters have proper symbol/timeframe/risk context
    if(!strategy.InitializeAI(m_src.GetManagedSymbol(), resolvedTf, m_src.GetUnifiedRiskManagerConst()))
    {
        Print("[EnterpriseStrategyManager] WARNING: Strategy ", name, " AI initialization failed. Continuing with base initialization.");
        // Don't fail registration - AI initialization failure is non-fatal for some adapters
    }

    // L6-001 CRITICAL FIX: Validate risk manager injection after initialization
        if(!strategy.ValidateRiskManagerInjection())
        {
            Print("[EnterpriseStrategyManager] CRITICAL: Strategy ", name, " failed risk manager injection validation. Strategy will bypass risk validation - rejecting registration.");
            delete strategy;
            return false;
        }

        // CRITICAL FIX: Synchronize enabled state with strategy object
    strategy.SetEnabled(enabled);
    strategy.SetWeight(weight);

    // Append the fully-initialised StrategyEntry, enrol it with the health
    // monitor and bump the strategy count. The manager owns this step behind a
    // narrow, logic-free mutator (see AppendRegisteredStrategyEntry) so the
    // 35-field initialiser block stays byte-for-byte identical.
    m_src.AppendRegisteredStrategyEntry(strategy, name, enabled, weight, tier, resolvedTf,
                                        intrabarPolicy, role, cluster, liveVotingEnabled);

    Print("[EnterpriseStrategyManager] Registered strategy: ", name,
          " | Enabled: ", enabled, " | Tier: ", (int)tier, " | Weight: ", weight,
          " | TF: ", EnumToString(resolvedTf),
          " | Intrabar: ", IntrabarPolicyToString((ENUM_INTRABAR_POLICY)m_src.GetStrategyIntrabarPolicyRaw(m_src.GetStrategyCount() - 1)),
          " | Role: ", StrategyRoleToString(role),
          " | Cluster: ", StrategyClusterToString(cluster),
          " | LiveVote: ", liveVotingEnabled ? "YES" : "NO");

    return true;
}

//+------------------------------------------------------------------+
//| Auto-register Strategies                                        |
//+------------------------------------------------------------------+
void CStrategyRegistryState::AutoRegisterStrategies(bool &flags[])
{
    if(m_src == NULL)
        return;

    int size = ArraySize(flags);

    // 0: Momentum (live primary voter) - Tier 3
        if(size > 0 && flags[0]) RegisterStrategy(new CSimpleMomentumStrategy(), "Momentum", true, 1.0, STRATEGY_TIER_3, PERIOD_CURRENT, m_src.GetIntrabarPolicyHelper(0),
                                                         PRIMARY_ALPHA, TREND_CLUSTER, true);

                // 1: Trend (live primary voter) - Tier 2
                if(size > 1 && flags[1]) RegisterStrategy(new CStrategyTrend(), "Trend", true, 1.2, STRATEGY_TIER_2, PERIOD_CURRENT, m_src.GetIntrabarPolicyHelper(1),
                                                         PRIMARY_ALPHA, TREND_CLUSTER, true);

                // 2: Support/Resistance (live primary voter) - Tier 2
                        if(size > 4 && flags[4]) RegisterStrategy(new CStrategySupportResistance(), "Support/Resistance", true, 1.5, STRATEGY_TIER_2, PERIOD_CURRENT, m_src.GetIntrabarPolicyHelper(4),
                                                                 PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true);

                        // 5: Unified ICT - REMOVED (over-engineered, 14+ modules, 1850 lines)

                        // 6: Candlestick (live primary voter) - Tier 2
                if(size > 6 && flags[6]) RegisterStrategy(new CStrategyCandlestick(), "Candlestick", true, 1.5, STRATEGY_TIER_2, PERIOD_CURRENT, m_src.GetIntrabarPolicyHelper(6),
                                                         PRIMARY_ALPHA, STRUCTURE_CLUSTER, true);

        // 9: Mean Reversion (live primary voter) - Tier 2 - MEAN_REVERSION_CLUSTER
        if(size > 9 && flags[9]) RegisterStrategy(new CMeanReversionStrategy(), "Mean Reversion", true, 1.8, STRATEGY_TIER_2, PERIOD_CURRENT, m_src.GetIntrabarPolicyHelper(9),
                                                 PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true);

        // 10: Volatility Breakout (live primary voter) - Tier 1 - TREND_CLUSTER
        if(size > 10 && flags[10]) RegisterStrategy(new CVolatilityBreakoutStrategy(), "Volatility Breakout", true, 2.0, STRATEGY_TIER_1, PERIOD_CURRENT, m_src.GetIntrabarPolicyHelper(10),
                                                   PRIMARY_ALPHA, TREND_CLUSTER, true);

    // 11: Statistical Arbitrage - Requires Python Bridge for real-time correlation matrix
        // Conditionally registered only when Python bridge is available
        if(m_src.IsPythonBridgeConnected())
        {
            if(size > 11 && flags[11]) RegisterStrategy(new CStatisticalArbitrageStrategy(), "Statistical Arbitrage", true, 1.8, STRATEGY_TIER_2, PERIOD_CURRENT, m_src.GetIntrabarPolicyHelper(11),
                                                        PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true);
            Print("[EnterpriseStrategyManager] Python Bridge available - Statistical Arbitrage strategy registered");
        }
        else
        {
            Print("[EnterpriseStrategyManager] Python Bridge not available - Skipping Statistical Arbitrage registration");
        }

        // Batch 103: New ICT/SMC strategies
        // 12: FVG Scalper - Tier 2 - STRUCTURE_CLUSTER
        if(size > 12 && flags[12]) RegisterStrategy(new CFVGScalperStrategy(), "FVG Scalper", true, 1.8, STRATEGY_TIER_2, PERIOD_CURRENT, m_src.GetIntrabarPolicyHelper(12),
                                                    PRIMARY_ALPHA, STRUCTURE_CLUSTER, true);

        // 13: Turtle Soup - Tier 2 - STRUCTURE_CLUSTER
        if(size > 13 && flags[13]) RegisterStrategy(new CTurtleSoupStrategy(), "Turtle Soup", true, 1.6, STRATEGY_TIER_2, PERIOD_CURRENT, m_src.GetIntrabarPolicyHelper(13),
                                                    PRIMARY_ALPHA, STRUCTURE_CLUSTER, true);

        // 14: Breaker Block - Tier 2 - STRUCTURE_CLUSTER
        if(size > 14 && flags[14]) RegisterStrategy(new CBreakerBlockStrategy(), "Breaker Block", true, 1.7, STRATEGY_TIER_2, PERIOD_CURRENT, m_src.GetIntrabarPolicyHelper(14),
                                                    PRIMARY_ALPHA, STRUCTURE_CLUSTER, true);

        // 15: NY Open Gap - Tier 3 - STRUCTURE_CLUSTER (session-limited)
                if(size > 15 && flags[15]) RegisterStrategy(new CNYOpenGapStrategy(), "NY Open Gap", true, 1.3, STRATEGY_TIER_3, PERIOD_CURRENT, m_src.GetIntrabarPolicyHelper(15),
                                                            PRIMARY_ALPHA, STRUCTURE_CLUSTER, true);

                // 16: Asian Range Break - Tier 3 - STRUCTURE_CLUSTER (session-limited)
                if(size > 16 && flags[16]) RegisterStrategy(new CAsianRangeBreakStrategy(), "Asian Range Break", true, 1.3, STRATEGY_TIER_3, PERIOD_CURRENT, m_src.GetIntrabarPolicyHelper(16),
                                                            PRIMARY_ALPHA, STRUCTURE_CLUSTER, true);

    Print("[EnterpriseStrategyManager] Auto-registration complete. Active strategies: ",
          m_src.GetActiveStrategyCount());
}

//+------------------------------------------------------------------+
//| Name -> index lookup (-1 when absent)                             |
//+------------------------------------------------------------------+
int CStrategyRegistryState::FindStrategyIndexByName(const string name) const
{
    if(m_src == NULL)
        return -1;

    const int strategyCount = m_src.GetStrategyCount();
    for(int i = 0; i < strategyCount; i++)
    {
        if(m_src.GetStrategyName(i) == name)
            return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Get Strategy By Name - Batch 103: returns strategy pointer        |
//+------------------------------------------------------------------+
IStrategy* CStrategyRegistryState::GetStrategyByName(const string name) const
{
    if(m_src == NULL)
        return NULL;

    int idx = FindStrategyIndexByName(name);
    if(idx < 0 || idx >= m_src.GetStrategyCount())
        return NULL;
    return m_src.GetStrategyPtr(idx);
}

//+------------------------------------------------------------------+
//| Enable-state query: registered, enabled, live-voting strategy     |
//+------------------------------------------------------------------+
bool CStrategyRegistryState::IsStrategyLiveVoter(const int strategyIndex) const
{
    if(m_src == NULL)
        return false;

    if(strategyIndex < 0 || strategyIndex >= m_src.GetStrategyCount())
        return false;
    if(!m_src.IsStrategyEnabled(strategyIndex) || m_src.GetStrategyPtr(strategyIndex) == NULL)
        return false;
    if(!m_src.IsStrategyLiveVotingEnabled(strategyIndex))
        return false;
    return true;
}

//+------------------------------------------------------------------+
//| Registry metadata: role                                           |
//+------------------------------------------------------------------+
bool CStrategyRegistryState::SetStrategyRoleByName(const string name, ENUM_STRATEGY_ROLE role)
{
    if(m_src == NULL)
        return false;

    int index = FindStrategyIndexByName(name);
    if(index < 0)
        return false;

    m_src.SetStrategyRole(index, (int)role);
    PrintFormat("[EnterpriseStrategyManager] Role updated: %s => %s",
                name, StrategyRoleToString(role));
    return true;
}

//+------------------------------------------------------------------+
//| Registry metadata: cluster                                        |
//+------------------------------------------------------------------+
bool CStrategyRegistryState::SetStrategyClusterByName(const string name, ENUM_STRATEGY_CLUSTER cluster)
{
    if(m_src == NULL)
        return false;

    int index = FindStrategyIndexByName(name);
    if(index < 0)
        return false;

    m_src.SetStrategyCluster(index, (int)cluster);
    PrintFormat("[EnterpriseStrategyManager] Cluster updated: %s => %s",
                name, StrategyClusterToString(cluster));
    return true;
}

//+------------------------------------------------------------------+
//| Enable-state: live-voting eligibility                             |
//+------------------------------------------------------------------+
bool CStrategyRegistryState::SetStrategyLiveVotingEligibilityByName(const string name, const bool enabled)
{
    if(m_src == NULL)
        return false;

    int index = FindStrategyIndexByName(name);
    if(index < 0)
        return false;

    m_src.SetStrategyLiveVotingEnabled(index, enabled);
    PrintFormat("[EnterpriseStrategyManager] Live voting updated: %s => %s",
                name, enabled ? "ENABLED" : "DISABLED");
    return true;
}

//+------------------------------------------------------------------+
//| Registry metadata: role + cluster + live-voting in one shot       |
//+------------------------------------------------------------------+
bool CStrategyRegistryState::SetStrategyGovernanceByName(const string name,
                                                         ENUM_STRATEGY_ROLE role,
                                                         ENUM_STRATEGY_CLUSTER cluster,
                                                         const bool liveVotingEnabled)
{
    if(m_src == NULL)
        return false;

    int index = FindStrategyIndexByName(name);
    if(index < 0)
        return false;

    m_src.SetStrategyRole(index, (int)role);
    m_src.SetStrategyCluster(index, (int)cluster);
    m_src.SetStrategyLiveVotingEnabled(index, liveVotingEnabled);

    PrintFormat("[EnterpriseStrategyManager] Governance updated: %s | role=%s | cluster=%s | live_vote=%s",
                name,
                StrategyRoleToString(role),
                StrategyClusterToString(cluster),
                liveVotingEnabled ? "ENABLED" : "DISABLED");
    return true;
}

#endif // STRATEGY_REGISTRY_STATE_MQH
