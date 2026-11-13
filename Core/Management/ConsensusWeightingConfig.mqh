// Composite weight computation and quorum presets, extracted from CEnterpriseStrategyManager. Unlike the other
// satellites this module MUTATES the manager, so it holds a non-const back-pointer and writes only through the
// manager's public mutators. The atomic quorum setters (SetMinQuorum, SetConflictDeadband,
// SetMinReadyWeightRatio) stay in the manager: the consensus core reads those mirrored fields directly, so
// moving them would mean editing a hot consensus body.
// Implementation detail of EnterpriseStrategyManager.mqh - included from there, not standalone.
#ifndef CONSENSUS_WEIGHTING_CONFIG_MQH
#define CONSENSUS_WEIGHTING_CONFIG_MQH

#include "../Utils/Enums.mqh"                        // ENUM_STRATEGY_TYPE / CLUSTER, ENUM_ASSET_CLASS
#include "../../Interfaces/IStrategy.mqh"            // IStrategy::GetType / SetWeight
#include "../Processing/DerivAssetProfiler.mqh"      // CDerivAssetProfiler, SDerivProfile
#include "../Processing/MultiAssetProfiler.mqh"      // CMultiAssetProfiler, ENUM_ASSET_CLASS
#include "../Engines/FamilyStrategyWeightMatrix.mqh" // CFamilyStrategyWeightMatrix

class CEnterpriseStrategyManager;   // forward: held as a mutable pointer

#define AI_WEIGHT_SMOOTHING 0.25
#define AI_WEIGHT_TAU 86400.0   // baseline decay time constant: 1 day in seconds

// Quorum profile ids.
// Mirrors CEnterpriseStrategyManager::ENUM_QUORUM_PROFILE 1:1 by
// ordinal. The nested enum is intentionally LEFT IN PLACE because
// it is a user-facing MT5 `input` type in MultiStrategyAutonomousEA
// .mq5 / MultiStrategyTestingEA.mq5 and in OrchestratorConfig; a
// class declared before the manager cannot name a type nested in
// it, so the manager forwards the profile as a plain int.
#define QUORUM_PROFILE_CONSERVATIVE 0
#define QUORUM_PROFILE_BALANCED     1
#define QUORUM_PROFILE_AGGRESSIVE   2

// Weighting / quorum-profile facade over CEnterpriseStrategyManager
class CConsensusWeightingConfig
{
private:
    CEnterpriseStrategyManager* m_src;
    double                      m_aiBaseWeights[];
    datetime                    m_aiBaseWeightTime[];   // last update time per strategy, for decay

public:
    CConsensusWeightingConfig() : m_src(NULL) {}

    void SetSource(CEnterpriseStrategyManager* src) { m_src = src; }

    void UpdateStrategyWeights();
    void ApplyQuorumProfile(const int profile);
    void ApplyFamilyEngineWeights(const string symbol);
    void ApplyAssetClassEngineWeights(const string symbol);

private:
    double LoadAIBaseWeight(const int index);
};

double CConsensusWeightingConfig::LoadAIBaseWeight(const int index)
{
    // Batch 272 fix. `m_aiBaseWeightTime` was never resized with `m_aiBaseWeights`, so the first
    // AI row to reload its baseline indexed a zero-length array - the live journal died with
    // "array out of range in 'ConsensusWeightingConfig.mqh' (69,27)" seconds after attach.
    // Bounds are checked here rather than trusted: an index past the arrays means the caller's
    // roster and this config disagree, and a wrong baseline beats terminating the program.
    if(index < 0 || index >= ArraySize(m_aiBaseWeights) || index >= ArraySize(m_aiBaseWeightTime))
        return (index >= 0 && index < ArraySize(m_aiBaseWeights)) ? m_aiBaseWeights[index] : 0.0;

    if(m_aiBaseWeights[index] >= 0.0)
        return m_aiBaseWeights[index];

    // Hash-based key avoids 63-char truncation collisions: hash of symbol+name.
    string rawKey = m_src.GetManagedSymbol() + "|" + m_src.GetStrategyName(index);
    int hash = 5381;
    for(int ci = 0; ci < StringLen(rawKey); ci++)
        hash = ((hash << 5) + hash) + (int)StringGetCharacter(rawKey, ci);
    string key = StringFormat("AIBW_%d", hash);
    datetime now = TimeCurrent();

    // Decay: baseline drifts toward the current weight over AI_WEIGHT_TAU seconds.
    double baseWeight = GlobalVariableGet(key);
    if(m_aiBaseWeightTime[index] > 0)
    {
        double dt = now - (double)m_aiBaseWeightTime[index];
        if(dt > 0)
        {
            double decay = MathExp(-dt / AI_WEIGHT_TAU);
            baseWeight = baseWeight * decay + m_src.GetStrategyWeight(index) * (1.0 - decay);
        }
    }
    m_aiBaseWeightTime[index] = now;
    m_aiBaseWeights[index] = baseWeight;
    return baseWeight;
}

void CConsensusWeightingConfig::UpdateStrategyWeights()
{
    if(m_src == NULL)
        return;

    const int strategyCount = m_src.GetStrategyCount();
    if(ArraySize(m_aiBaseWeights) != strategyCount)
    {
        ArrayResize(m_aiBaseWeights, strategyCount);
        ArrayInitialize(m_aiBaseWeights, -1.0);
    }
    // The decay timestamps live in their own array and were never sized with the baselines, so
    // LoadAIBaseWeight() wrote through an empty array. Both arrays move together now; a timestamp
    // of 0 means "no decay applied yet", so every row starts from the persisted GlobalVariable.
    // (ArrayInitialize is not used here: it rejects string arrays and this array is datetime, kept
    // as an explicit loop so the intent survives any later type change of the pair.)
    if(ArraySize(m_aiBaseWeightTime) != strategyCount)
    {
        ArrayResize(m_aiBaseWeightTime, strategyCount);
        for(int ti = 0; ti < strategyCount; ti++)
            m_aiBaseWeightTime[ti] = 0;
    }

    // AI rows: the target is always derived from the persisted baseline, so repeated updates cannot
    // compound. Insufficient evidence (below AI_WEIGHT_MIN_PREDICTIONS) yields a zero multiplier, which
    // makes the target the baseline and the weight relaxes back toward it.
    for(int i = 0; i < strategyCount; i++)
    {
        IStrategy* strategy = m_src.GetStrategyPtr(i);
        if(strategy == NULL)
            continue;

        ENUM_STRATEGY_TYPE stratType = strategy.GetType();
        bool isAI = (stratType == STRATEGY_BRAIN || stratType == STRATEGY_AI_ENHANCED);
        if(!isAI)
            continue;

        double baseWeight = LoadAIBaseWeight(i);
        double aiProfitability = MathMax(-0.2, MathMin(0.2, m_src.GetStrategyAvgProfit(i)));
        double target = MathMax(0.0, MathMin(10.0, baseWeight * (1.0 + aiProfitability)));
        double current = m_src.GetStrategyWeight(i);
        double newWeight = MathMax(0.0, MathMin(10.0, current + AI_WEIGHT_SMOOTHING * (target - current)));

        // A baseline of zero is the operator saying "this arm is not allocated", not "start it at some
        // default and let it decay". Smoothing only approaches zero asymptotically, and a measured run
        // left the three AI arms at weight 0.032 - greater than 0.0, so `ConsensusEngine`'s advisory gate
        // (weight <= 0.0) let an untrained net (labels 0/30, accuracy 0.000) count as a real voter on every
        // symbol, adding to vote counts and support while contributing no information. Base 0 must mean
        // exactly 0.
        if(baseWeight <= 0.0)
            newWeight = 0.0;

        m_src.ApplyRawStrategyWeight(i, newWeight);

        PrintFormat("[AI-WEIGHT-ADJUST] %s | %s | AI profitability=%.3f | base=%.3f | target=%.3f | newWeight=%.3f",
                    m_src.GetManagedSymbol(), m_src.GetStrategyName(i), aiProfitability,
                    baseWeight, target, newWeight);
    }
}

// Routed through the manager's public setters instead of raw field
// assignment. Verified behaviour-identical: every literal below is
// already inside the setters' clamp ranges, so the clamps are
// no-ops (minQuorum >= 1; thresholds and support floors in [0,1]).
void CConsensusWeightingConfig::ApplyQuorumProfile(const int profile)
{
    if(m_src == NULL)
        return;

    switch(profile)
    {
        case QUORUM_PROFILE_CONSERVATIVE:
            m_src.SetMinQuorum(2);
            m_src.SetQuorumThreshold(0.60);
            m_src.SetSupportFloors(0.35, 0.30);
            m_src.SetIntrabarDynamicQuorumEnabled(true);
            break;
        case QUORUM_PROFILE_BALANCED:
            m_src.SetMinQuorum(1);
            m_src.SetQuorumThreshold(0.50);
            m_src.SetSupportFloors(0.25, 0.20);
            m_src.SetIntrabarDynamicQuorumEnabled(true);
            break;
        case QUORUM_PROFILE_AGGRESSIVE:
            m_src.SetMinQuorum(1);
            m_src.SetQuorumThreshold(0.45);
            m_src.SetSupportFloors(0.15, 0.10);
            m_src.SetIntrabarDynamicQuorumEnabled(false);
            break;
    }
}

// Apply family-based engine weights for Deriv synthetic indices
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

// Apply asset-class-based engine weights using multi-asset profiler
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
