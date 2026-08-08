//+------------------------------------------------------------------+
//| Consensus Weighting & Quorum Profiles (Phase C, Slice 2 - C4)    |
//| Composite weight computation and quorum preset profiles extracted |
//| from CEnterpriseStrategyManager:                                  |
//|   - UpdateStrategyWeights        (performance/AI weight refresh)  |
//|   - ApplyQuorumProfile           (conservative/balanced/aggressive)|
//|   - ApplyFamilyEngineWeights     (Deriv family cluster multipliers)|
//|   - ApplyAssetClassEngineWeights (multi-asset class multipliers)  |
//|                                                                   |
//| Unlike the Slice 1 collaborators this module MUTATES the manager, |
//| so it holds a NON-const back-pointer. It writes exclusively       |
//| through the manager's existing public mutators                    |
//| (UpdateStrategyWeightByName / SetMinQuorum / SetQuorumThreshold / |
//| SetSupportFloors / SetIntrabarDynamicQuorumEnabled) plus one      |
//| narrow raw setter, so the resulting state is identical.           |
//|                                                                   |
//| DELIBERATELY NOT MOVED: the atomic consensus config setters       |
//| (SetMinQuorum, SetConflictDeadband, SetMinReadyWeightRatio, ...)  |
//| stay in the manager because they own mirrored fields that the     |
//| DO-NOT-PIECEMEAL C9 consensus core (EvaluateConsensusInternal)    |
//| reads directly (m_conflictDeadband, m_minReadyWeightRatio).       |
//| Relocating those fields would require editing a C9 body.          |
//|                                                                   |
//| NOTE: this header is an implementation detail of                  |
//| EnterpriseStrategyManager.mqh and is included from there (after   |
//| the shared free helpers, before the manager class). It is not     |
//| intended to be included standalone.                               |
//+------------------------------------------------------------------+
#ifndef CONSENSUS_WEIGHTING_CONFIG_MQH
#define CONSENSUS_WEIGHTING_CONFIG_MQH

#include "../Utils/Enums.mqh"                        // ENUM_STRATEGY_TYPE / CLUSTER, ENUM_ASSET_CLASS
#include "../../Interfaces/IStrategy.mqh"            // IStrategy::GetType / SetWeight
#include "../Processing/DerivAssetProfiler.mqh"      // CDerivAssetProfiler, SDerivProfile
#include "../Processing/MultiAssetProfiler.mqh"      // CMultiAssetProfiler, ENUM_ASSET_CLASS
#include "../Engines/FamilyStrategyWeightMatrix.mqh" // CFamilyStrategyWeightMatrix
#include "StrategyHealthMonitor.mqh"                 // CStrategyHealthMonitor

class CEnterpriseStrategyManager;   // forward: held as a mutable pointer

//+------------------------------------------------------------------+
//| Quorum profile ids.                                               |
//|                                                                   |
//| Mirrors CEnterpriseStrategyManager::ENUM_QUORUM_PROFILE 1:1 by    |
//| ordinal. The nested enum is intentionally LEFT IN PLACE because   |
//| it is a user-facing MT5 `input` type in MultiStrategyAutonomousEA |
//| .mq5 / MultiStrategyTestingEA.mq5 and in OrchestratorConfig; a    |
//| class declared before the manager cannot name a type nested in    |
//| it, so the manager forwards the profile as a plain int.           |
//+------------------------------------------------------------------+
#define QUORUM_PROFILE_CONSERVATIVE 0
#define QUORUM_PROFILE_BALANCED     1
#define QUORUM_PROFILE_AGGRESSIVE   2

//+------------------------------------------------------------------+
//| Weighting / quorum-profile facade over CEnterpriseStrategyManager |
//+------------------------------------------------------------------+
class CConsensusWeightingConfig
{
private:
    CEnterpriseStrategyManager* m_src;

public:
    CConsensusWeightingConfig() : m_src(NULL) {}

    void SetSource(CEnterpriseStrategyManager* src) { m_src = src; }

    void UpdateStrategyWeights();
    void ApplyQuorumProfile(const int profile);
    void ApplyFamilyEngineWeights(const string symbol);
    void ApplyAssetClassEngineWeights(const string symbol);
};

//+------------------------------------------------------------------+
//| Refresh all strategy weights                                      |
//+------------------------------------------------------------------+
void CConsensusWeightingConfig::UpdateStrategyWeights()
{
    if(m_src == NULL)
        return;

    const int strategyCount = m_src.GetStrategyCount();

    // L1-007: Delegate to CStrategyHealthMonitor
    CStrategyHealthMonitor* healthMonitor = m_src.GetHealthMonitor();
    if(healthMonitor != NULL)
    {
        healthMonitor.UpdateAllStrategyWeights();

        // L6-016: Apply AI profitability multiplier for AI strategies
        for(int i = 0; i < strategyCount; i++)
        {
            IStrategy* strategy = m_src.GetStrategyPtr(i);
            if(strategy == NULL)
                continue;

            ENUM_STRATEGY_TYPE stratType = strategy.GetType();
            bool isAI = (stratType == STRATEGY_BRAIN || stratType == STRATEGY_AI_ENHANCED);
            double avgProfit = m_src.GetStrategyAvgProfit(i);
            if(isAI && avgProfit != 0.0)
            {
                // avgProfit stores AI profitability (set by UpdateAIPerformanceMetrics)
                double aiProfitability = avgProfit;
                // Apply profitability multiplier: 0.8x to 1.2x based on profitability (-0.2 to +0.2)
                double profitMult = 1.0 + MathMax(-0.2, MathMin(0.2, aiProfitability));
                double newWeight = m_src.GetStrategyWeight(i) * profitMult;
                newWeight = MathMax(0.0, MathMin(10.0, newWeight));
                m_src.ApplyRawStrategyWeight(i, newWeight);

                PrintFormat("[AI-WEIGHT-ADJUST] %s | %s | AI profitability=%.3f | mult=%.3f | newWeight=%.3f",
                            m_src.GetManagedSymbol(), m_src.GetStrategyName(i), aiProfitability, profitMult, newWeight);
            }
        }
        return;
    }

    // Fallback if health monitor not initialized
    for(int i = 0; i < strategyCount; i++)
    {
        if(m_src.GetStrategyPtr(i) == NULL)
            continue;

        // Performance-adaptive weight scaling using recent win rate.
        // This is intentionally conservative and bounded to prevent destabilizing consensus.
        double originalWeight = m_src.GetStrategyOriginalWeight(i);
        double base = originalWeight > 0.0 ? originalWeight : m_src.GetStrategyWeight(i);
        double wr = MathMax(0.0, MathMin(1.0, m_src.GetStrategyRecentWinRate(i)));
        double scale = 0.75 + (wr - 0.50); // 0.25..1.25 around 50% win rate
        scale = MathMax(0.50, MathMin(1.50, scale));
        double newWeight = MathMax(0.0, MathMin(10.0, base * scale));

        m_src.ApplyRawStrategyWeight(i, newWeight);
    }
}

//+------------------------------------------------------------------+
//| Apply Quorum Profile                                             |
//|                                                                  |
//| Routed through the manager's public setters instead of raw field |
//| assignment. Verified behaviour-identical: every literal below is |
//| already inside the setters' clamp ranges, so the clamps are      |
//| no-ops (minQuorum >= 1; thresholds and support floors in [0,1]). |
//+------------------------------------------------------------------+
void CConsensusWeightingConfig::ApplyQuorumProfile(const int profile)
{
    if(m_src == NULL)
        return;

    switch(profile)
    {
        case QUORUM_PROFILE_CONSERVATIVE:
            m_src.SetMinQuorum(3);
            m_src.SetQuorumThreshold(0.65);
            m_src.SetSupportFloors(0.40, 0.35);
            m_src.SetIntrabarDynamicQuorumEnabled(true);
            break;
        case QUORUM_PROFILE_BALANCED:
            m_src.SetMinQuorum(1);
            m_src.SetQuorumThreshold(0.55);
            m_src.SetSupportFloors(0.30, 0.25);
            m_src.SetIntrabarDynamicQuorumEnabled(true);
            break;
        case QUORUM_PROFILE_AGGRESSIVE:
            m_src.SetMinQuorum(1);
            m_src.SetQuorumThreshold(0.50);
            m_src.SetSupportFloors(0.20, 0.15);
            m_src.SetIntrabarDynamicQuorumEnabled(false);
            break;
    }
}

//+------------------------------------------------------------------+
//| Apply family-based engine weights for Deriv synthetic indices    |
//+------------------------------------------------------------------+
void CConsensusWeightingConfig::ApplyFamilyEngineWeights(const string symbol)
{
    if(m_src == NULL)
        return;

    CDerivAssetProfiler* derivProfiler = m_src.GetDerivProfilerConst();
    CFamilyStrategyWeightMatrix* familyWeightMatrix = m_src.GetFamilyWeightMatrixConst();

    if(derivProfiler == NULL || familyWeightMatrix == NULL)
        return;

    SDerivProfile profile = derivProfiler.GetProfile(symbol);
    ENUM_DERIV_FAMILY family = profile.family;

    if(family == DERIV_UNKNOWN)
        return;

    // Iterate through all strategies and apply family cluster weight multipliers
    const int strategyCount = m_src.GetStrategyCount();
    for(int i = 0; i < strategyCount; i++)
    {
        if(!m_src.IsStrategyEnabled(i))
            continue;

        ENUM_STRATEGY_CLUSTER cluster = (ENUM_STRATEGY_CLUSTER)m_src.GetStrategyCluster(i);
        if(cluster == STRATEGY_CLUSTER_NONE)
            continue;

        double clusterMult = familyWeightMatrix.GetClusterWeight(family, cluster);
        if(MathAbs(clusterMult - 1.0) > 0.01)
        {
            string strategyName = m_src.GetStrategyName(i);
            double newWeight = m_src.GetStrategyWeight(i) * clusterMult;
            m_src.UpdateStrategyWeightByName(strategyName, newWeight);
            PrintFormat("[FAMILY-WEIGHT] %s | %s | family=%s | cluster=%s | mult=%.3f => %.3f",
                        symbol, strategyName, EnumToString(family), EnumToString(cluster), clusterMult, newWeight);
        }
    }
}

//+------------------------------------------------------------------+
//| Apply asset-class-based engine weights using multi-asset profiler|
//+------------------------------------------------------------------+
void CConsensusWeightingConfig::ApplyAssetClassEngineWeights(const string symbol)
{
    if(m_src == NULL)
        return;

    // Fallback to family-based weighting if profiler not set
    CMultiAssetProfiler* multiAssetProfiler = m_src.GetMultiAssetProfilerConst();
    if(multiAssetProfiler == NULL)
    {
        ApplyFamilyEngineWeights(symbol);
        return;
    }

    ENUM_ASSET_CLASS assetClass = multiAssetProfiler.GetAssetClassForSymbol(symbol);

    // Strategy name constants matching AutoRegisterStrategies registration names
    const string VOL_BREAKOUT = "Volatility Breakout";
    const string MEAN_REVERT  = "Mean Reversion";
    const string TREND        = "Trend";

    // Deriv asset classes (4-8) delegate to existing family-based logic
    if(assetClass >= ASSET_DERIV_CRASHBOOM && assetClass <= ASSET_DERIV_DEX)
    {
        ApplyFamilyEngineWeights(symbol);
        return;
    }

    double volBreakoutMult = 1.0;
    double meanRevertMult  = 1.0;
    double trendMult       = 1.0;

    switch(assetClass)
    {
        case ASSET_FOREX:
            trendMult       = 1.3;
            volBreakoutMult = 1.2;
            meanRevertMult  = 0.7;
            break;
        case ASSET_METALS:
            volBreakoutMult = 1.5;
            meanRevertMult  = 0.5;
            break;
        case ASSET_INDICES:
            meanRevertMult  = 1.5;
            volBreakoutMult = 0.5;
            trendMult       = 0.8;
            break;
        case ASSET_ENERGIES:
            volBreakoutMult = 1.4;
            trendMult       = 1.2;
            break;
        case ASSET_UNIVERSAL:
        default:
            // No adjustment for universal/unknown
            return;
    }

    // Apply multipliers to current weights
    int idx;

    if(volBreakoutMult != 1.0)
    {
        idx = m_src.GetStrategyIndexByName(VOL_BREAKOUT);
        if(idx >= 0)
        {
            double newWeight = m_src.GetStrategyWeight(idx) * volBreakoutMult;
            m_src.UpdateStrategyWeightByName(VOL_BREAKOUT, newWeight);
            PrintFormat("[ASSET-CLASS-WEIGHT] %s | %s x%.1f => %.3f", symbol, VOL_BREAKOUT, volBreakoutMult, newWeight);
        }
    }

    if(meanRevertMult != 1.0)
    {
        idx = m_src.GetStrategyIndexByName(MEAN_REVERT);
        if(idx >= 0)
        {
            double newWeight = m_src.GetStrategyWeight(idx) * meanRevertMult;
            m_src.UpdateStrategyWeightByName(MEAN_REVERT, newWeight);
            PrintFormat("[ASSET-CLASS-WEIGHT] %s | %s x%.1f => %.3f", symbol, MEAN_REVERT, meanRevertMult, newWeight);
        }
    }

    if(trendMult != 1.0)
    {
        idx = m_src.GetStrategyIndexByName(TREND);
        if(idx >= 0)
        {
            double newWeight = m_src.GetStrategyWeight(idx) * trendMult;
            m_src.UpdateStrategyWeightByName(TREND, newWeight);
            PrintFormat("[ASSET-CLASS-WEIGHT] %s | %s x%.1f => %.3f", symbol, TREND, trendMult, newWeight);
        }
    }
}

#endif // CONSENSUS_WEIGHTING_CONFIG_MQH
