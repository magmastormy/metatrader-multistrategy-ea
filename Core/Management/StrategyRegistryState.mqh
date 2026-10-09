// Registry bookkeeping and per-strategy enable state: the registration sequence
// (registry gate, capacity gate, strategy Init / AI init / risk-injection validation,
// entry append, health-monitor enrolment, registration log), the name -> index lookups
// and the live-voter query.
// This module MUTATES the manager, so the back-pointer is non-const and every write
// goes through the manager's narrow per-field accessors. It mirrors no injected pointer
// (registry / trade manager / position sizer / risk manager are re-read from the manager
// on every call), so it needs no re-sync on Deinit or after the injection setters.
// Deliberately NOT moved - they stay in EnterpriseStrategyManager.mqh:
// - SyncEnabledWithRegistry(): reconciles the enable flags against the shared
//   CStrategyRegistry (consensus-core reconciliation step); its only call site is
//   Core/Orchestration/EAOrchestrator.mqh:768.
// - The weight / confidence-threshold setters, and the 35-field StrategyEntry
//   initialiser block behind the logic-free AppendRegisteredStrategyEntry(): relocating
//   either would need a write accessor for every struct field.
// - The consensus core calls IsStrategyLiveVoter() by name, so the manager keeps a
//   private same-signature forwarder for it.
// NOTE: implementation detail of EnterpriseStrategyManager.mqh, included from there
// (after the shared free helpers, before the manager class). Not for standalone include.
#ifndef STRATEGY_REGISTRY_STATE_MQH
#define STRATEGY_REGISTRY_STATE_MQH

#include "../Utils/Enums.mqh"                       // ENUM_STRATEGY_TIER / ROLE / CLUSTER, ENUM_INTRABAR_POLICY
#include "../../Interfaces/IStrategy.mqh"           // IStrategy::Init / InitializeAI / ValidateRiskManagerInjection
#include "../Strategy/StrategyRegistry.mqh"         // CStrategyRegistry::IsStrategyActive
#include "StrategyHealthMonitor.mqh"                // CStrategyHealthMonitor::RegisterStrategy

//--- Registration data lives in Core/Strategy/StrategyCatalog.mqh.

class CEnterpriseStrategyManager;   // forward: held as a mutable pointer

// Registry / enable-state facade over CEnterpriseStrategyManager
class CStrategyRegistryState
{
private:
    CEnterpriseStrategyManager* m_src;

public:
    CStrategyRegistryState() : m_src(NULL) {}

    void SetSource(CEnterpriseStrategyManager* src) { m_src = src; }

    bool RegisterStrategy(IStrategy* strategy, const string name,
                          bool enabled, double weight,
                          ENUM_STRATEGY_TIER tier,
                          ENUM_TIMEFRAMES tf,
                          ENUM_INTRABAR_POLICY intrabarPolicy,
                          ENUM_STRATEGY_ROLE role,
                          ENUM_STRATEGY_CLUSTER cluster,
                          bool liveVotingEnabled);

    int        FindStrategyIndexByName(const string name) const;
    IStrategy* GetStrategyByName(const string name) const;

    bool IsStrategyLiveVoter(const int strategyIndex) const;

    bool SetStrategyRoleByName(const string name, ENUM_STRATEGY_ROLE role);
    bool SetStrategyClusterByName(const string name, ENUM_STRATEGY_CLUSTER cluster);
    bool SetStrategyLiveVotingEligibilityByName(const string name, const bool enabled);
    bool SetStrategyGovernanceByName(const string name,
                                     ENUM_STRATEGY_ROLE role,
                                     ENUM_STRATEGY_CLUSTER cluster,
                                     const bool liveVotingEnabled);
};

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

    // L1-010: the registry decides whether this strategy is active in the current
    // mode; the caller's 'enabled' argument is only advisory.
        CStrategyRegistry* strategyRegistry = m_src.GetStrategyRegistryConst();
        if(strategyRegistry != NULL)
        {
            if(!strategyRegistry.IsStrategyActive(name))
            {
                PrintFormat("[ENTERPRISE] Strategy %s disabled by registry (mode filter or not registered)", name);
                enabled = false;
            }
        }

    // Prevent unbounded strategy growth
    if(m_src.GetStrategyCount() >= m_src.GetMaxStrategies())
    {
        Print("[EnterpriseStrategyManager] ERROR: Max strategy limit reached (", m_src.GetMaxStrategies(), ")");
        delete strategy;
        return false;
    }

    // Init must receive the unified risk manager, never a legacy one
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

    // L6-010: AI init after factory creation so adapters see symbol/timeframe/risk context
    if(!strategy.InitializeAI(m_src.GetManagedSymbol(), resolvedTf, m_src.GetUnifiedRiskManagerConst()))
    {
        Print("[EnterpriseStrategyManager] WARNING: Strategy ", name, " AI initialization failed. Continuing with base initialization.");
        // Non-fatal: some adapters degrade to non-AI behaviour
    }

    // L6-001: a strategy that did not take the risk manager injection would bypass risk gating
        if(!strategy.ValidateRiskManagerInjection())
        {
            Print("[EnterpriseStrategyManager] CRITICAL: Strategy ", name, " failed risk manager injection validation. Strategy will bypass risk validation - rejecting registration.");
            delete strategy;
            return false;
        }

    strategy.SetEnabled(enabled);
    strategy.SetWeight(weight);

    // Entry append, health-monitor enrolment and count bump stay in the manager
    // behind AppendRegisteredStrategyEntry (see header note).
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

// Name -> index lookup (-1 when absent)
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

IStrategy* CStrategyRegistryState::GetStrategyByName(const string name) const
{
    if(m_src == NULL)
        return NULL;

    int idx = FindStrategyIndexByName(name);
    if(idx < 0 || idx >= m_src.GetStrategyCount())
        return NULL;
    return m_src.GetStrategyPtr(idx);
}

// Enable-state query: registered, enabled, live-voting strategy
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
