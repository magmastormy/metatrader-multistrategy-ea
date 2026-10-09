// Consensus decision core: the entry funnel, quorum computation, evaluation body, two-tier / probe
// fast paths and the solo fallback are one load-bearing unit and must not be split.
// Registry reconciliation lives here, but the manager's one-line SyncEnabledWithRegistry() forwarder
// has live external call sites. Do not remove that forwarder.
// Field ownership:
// - m_lastDecisionContext: one writer (EvaluateConsensusInternal), read via GetLastDecisionContextValue.
// - m_lastVPINMultiplier is owned by CPostConsensusValidator, not here.
// - enabled / liveVotingEnabled / intrabarPolicy are READ through m_src accessors, never written here.
// This module mutates the manager, so m_src is non-const and writes go through its narrow per-field
// accessors. It mirrors no injected pointer (pipeline / registry / diagnostics are re-read per call),
// so it needs no re-sync on Deinit.
// Included only from EnterpriseStrategyManager.mqh, after the shared free helpers and before the
// manager class; not usable standalone.
#ifndef CONSENSUS_ENGINE_MQH
#define CONSENSUS_ENGINE_MQH

#include "../Utils/Enums.mqh"                     // signal / role / cluster / intrabar enums + SConsensusDecisionContext
#include "../../Interfaces/IStrategy.mqh"         // IStrategy::GetSignal / GetType / SetEnabled
#include "../Pipeline/UnifiedSignalPipeline.mqh"  // CUnifiedSignalPipeline::ProcessSignal
#include "../Engines/RegimeEngine.mqh"             // CRegimeEngine::GetSnapshot (regime vote weighting)
#include "../Strategy/StrategyRegistry.mqh"       // CStrategyRegistry::IsStrategyActive / GetMode
#include "../Utils/JsonLogger.mqh"                // CJsonLogger, CCorrelationIdGenerator
#include "DiagnosticsManager.mqh"                 // CDiagnosticsManager

// Minimum independent voters for a consensus entry: a lone voter is 100% consensus.
// Decision-point floor - no quorum profile can lower it, and few eligible voters cannot degrade it.
#ifndef MIN_CONSENSUS_VOTERS
#define MIN_CONSENSUS_VOTERS 2
#endif

class CEnterpriseStrategyManager;   // forward: held as a mutable pointer

class CConsensusEngine
{
private:
    CEnterpriseStrategyManager* m_src;

    // Owned by this module (single writer: EvaluateConsensusInternal).
    SConsensusDecisionContext m_lastDecisionContext;

public:
    CConsensusEngine() : m_src(NULL) {}

    void SetSource(CEnterpriseStrategyManager* src) { m_src = src; }

    //--- entry funnel (mirrored by the manager's public forwarders)
    ENUM_TRADE_SIGNAL GetConsensusSignal(double &confidence);
    ENUM_TRADE_SIGNAL GetConsensusSignalWithConfluence(double &confidence, int &confluence);
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbol(const string symbol, double &confidence);
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbolWithConfluence(const string symbol, double &confidence,
                                                                int &confluence);
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbolWithConfluenceMode(const string symbol, double &confidence,
                                                                    int &confluence,
                                                                    ENUM_SIGNAL_EVAL_MODE evalMode);
    ENUM_TRADE_SIGNAL EvaluateConsensusTwoTier(const string symbol, double &confidence, int &confluence,
                                               ENUM_SIGNAL_EVAL_MODE evalMode);
    ENUM_TRADE_SIGNAL TryFallbackSoloSignal(const string symbol, ENUM_SIGNAL_EVAL_MODE evalMode,
                                            double &outConfidence, int &outConfluence, string &outReason);

    //--- Registry reconciliation; do not remove the manager's forwarder
    void SyncEnabledWithRegistry();

    void GetLastDecisionContextValue(SConsensusDecisionContext &out) const { out = m_lastDecisionContext; }

    bool   IsStrategyLiveVoter(const int strategyIndex) const;
    double GetRegimeCategoryMultiplier(const string symbol, ENUM_STRATEGY_TYPE strategyType) const;
    double GetStrategyReliabilityMultiplier(const int strategyIndex) const;
    double GetStrategyParticipationMultiplier(const int strategyIndex) const;
    double GetStrategyRoleVoteMultiplier(const int strategyIndex) const;
    double CalculateDirectionDiversityScore(const int &strategyIndices[]) const;
    double CalculateAverageStrategyMetric(const int &strategyIndices[], const double &metrics[]) const;
    double ClampUnitValue(const double value) const;
    ENUM_INTRABAR_POLICY GetStrategyIntrabarPolicy(const int strategyIndex) const;
    bool   IsStrategyIntrabarLiveEligible(const int strategyIndex) const;
    bool   IsStrategyIntrabarProbeEligible(const int strategyIndex) const;
    bool   IsTrendingRegime();
    ENUM_STRATEGY_ROLE    ResolveDominantRole(const int &strategyIndices[]) const;
    ENUM_STRATEGY_CLUSTER ResolveDominantCluster(const int &strategyIndices[]) const;
    string JoinContributorsWithContext(const int &strategyIndices[]) const;
    void   MaybeLogConsensusDiagnostics(const string symbol);

private:
    ENUM_TRADE_SIGNAL EvaluateConsensusInternal(const string symbol, double &confidence, int &confluence,
                                                ENUM_SIGNAL_EVAL_MODE evalMode);
    ENUM_TRADE_SIGNAL EvaluateConsensusTwoTierInternal(const string symbol, double &confidence, int &confluence,
                                                       ENUM_SIGNAL_EVAL_MODE evalMode);
    ENUM_TRADE_SIGNAL EvaluateConsensusProbeOnlyInternal(const string symbol, double &confidence, int &confluence,
                                                         ENUM_SIGNAL_EVAL_MODE evalMode);
    ENUM_TRADE_SIGNAL TryFallbackSoloSignalInternal(const string symbol, ENUM_SIGNAL_EVAL_MODE evalMode,
                                                    double &outConfidence, int &outConfluence, string &outReason);
    void CalculateEffectiveQuorumParamsInternal(
        const string symbol,
        const int activeLiveStrategies,
        const int buyVotes,
        const int sellVotes,
        const int eligibleLiveVoterCount,
        const double buyDirectionalQuality,
        const double sellDirectionalQuality,
        const double buyScore,
        const double sellScore,
        const bool readyWeightMet,
        const ENUM_SIGNAL_EVAL_MODE evalMode,
        CUnifiedSignalPipeline* pipeline,
        int &buyContributorIndices[],
        int &sellContributorIndices[],
        double &effectiveQualityThreshold,
        double &supportFloor,
        int &effectiveMinVoters,
        double &buyQuorum,
        double &sellQuorum
    ) const;
};

ENUM_TRADE_SIGNAL CConsensusEngine::GetConsensusSignal(double &confidence)
{
    int confluence = 0;
    return GetConsensusSignalWithConfluence(confidence, confluence);
}

ENUM_TRADE_SIGNAL CConsensusEngine::GetConsensusSignalWithConfluence(double &confidence, int &confluence)
{
    if(m_src == NULL)
    {
        confidence = 0;
        confluence = 0;
        return TRADE_SIGNAL_NONE;
    }
    return GetConsensusSignalForSymbolWithConfluence(m_src.GetManagedSymbol(), confidence, confluence);
}

ENUM_TRADE_SIGNAL CConsensusEngine::GetConsensusSignalForSymbolWithConfluence(const string symbol,
                                                                             double &confidence,
                                                                             int &confluence)
{
    return GetConsensusSignalForSymbolWithConfluenceMode(symbol, confidence, confluence, EVAL_MODE_NEW_BAR);
}

ENUM_TRADE_SIGNAL CConsensusEngine::GetConsensusSignalForSymbol(const string symbol, double &confidence)
{
    int confluence = 0;
    return GetConsensusSignalForSymbolWithConfluence(symbol, confidence, confluence);
}

ENUM_TRADE_SIGNAL CConsensusEngine::GetConsensusSignalForSymbolWithConfluenceMode(const string symbol,
                                                                                  double &confidence,
                                                                                  int &confluence,
                                                                                  ENUM_SIGNAL_EVAL_MODE evalMode)
{
    if(m_src == NULL)
    {
        confidence = 0;
        confluence = 0;
        return TRADE_SIGNAL_NONE;
    }

    ulong startTime = GetMicrosecondCount();

    ENUM_TRADE_SIGNAL result;
    if(m_src.GetPipelineConst() != NULL && m_src.GetTFConsistencyConst() != NULL)
    {
        result = EvaluateConsensusInternal(symbol, confidence, confluence, evalMode);
    }
    else
    {
        // Fail closed when the pipeline or TF consistency is unavailable
        confluence = 0;
        confidence = 0;
        result = TRADE_SIGNAL_NONE;
    }

            ulong elapsed = GetMicrosecondCount() - startTime;
            CJsonLogger::LogPerformance("EnterpriseStrategyManager", "GetConsensusSignalForSymbolWithConfluenceMode_us", (double)elapsed, CCorrelationIdGenerator::Generate());

    return result;
}

ENUM_TRADE_SIGNAL CConsensusEngine::EvaluateConsensusTwoTier(const string symbol, double &confidence, int &confluence,
                                                             ENUM_SIGNAL_EVAL_MODE evalMode)
{
    if(m_src != NULL && m_src.GetPipelineConst() != NULL && m_src.GetTFConsistencyConst() != NULL)
    {
        return EvaluateConsensusTwoTierInternal(symbol, confidence, confluence, evalMode);
    }
    confluence = 0;
    confidence = 0;
    return TRADE_SIGNAL_NONE;
}

// Strategies are auto-registered before BuildStrategyRegistry populates CStrategyRegistry, so at that
// point IsStrategyActive() is false and the override at RegisterStrategy() locks every strategy disabled.
// This re-applies the registry's active state so the live strategy objects participate in consensus.
void CConsensusEngine::SyncEnabledWithRegistry()
{
    if(m_src == NULL)
        return;

    CStrategyRegistry* strategyRegistry = m_src.GetStrategyRegistryConst();
    if(strategyRegistry == NULL)
        return;
    int synced = 0;
    int strategyCount = m_src.GetStrategyCount();
    for(int i = 0; i < strategyCount; i++)
    {
        string entryName = m_src.GetStrategyName(i);
        bool registryActive = strategyRegistry.IsStrategyActive(entryName);
        bool shouldEnable = registryActive && !m_src.IsStrategyTemporarilyDisabled(i);
        if(shouldEnable != m_src.IsStrategyEnabled(i))
        {
            m_src.SetStrategyEnabledFlag(i, shouldEnable);
            IStrategy* strategy = m_src.GetStrategyPtr(i);
            if(strategy != NULL)
                strategy.SetEnabled(shouldEnable);
            PrintFormat("[EnterpriseStrategyManager] Synced strategy %s -> enabled=%s (registry active=%s)",
                        entryName, shouldEnable ? "true" : "false", registryActive ? "true" : "false");
            synced++;
        }
    }
    if(synced > 0)
        PrintFormat("[EnterpriseStrategyManager] %s: reconciled %d strategy enable-flags with registry",
                    m_src.GetManagedSymbol(), synced);
}

// Member-form unit clamp; shadows the free helper
double CConsensusEngine::ClampUnitValue(const double value) const
{
    if(!MathIsValidNumber(value))
        return 0.0;
    return MathMax(0.0, MathMin(1.0, value));
}

ENUM_INTRABAR_POLICY CConsensusEngine::GetStrategyIntrabarPolicy(const int strategyIndex) const
{
    if(m_src == NULL)
        return INTRABAR_POLICY_OFF;

    if(strategyIndex < 0 || strategyIndex >= m_src.GetStrategyCount())
        return INTRABAR_POLICY_OFF;

    int rawPolicy = m_src.GetStrategyIntrabarPolicyRaw(strategyIndex);
    if(rawPolicy < (int)INTRABAR_POLICY_OFF || rawPolicy > (int)INTRABAR_POLICY_LIVE)
        return m_src.GetStrategyIntrabarEligible(strategyIndex) ? INTRABAR_POLICY_LIVE : INTRABAR_POLICY_OFF;

    return (ENUM_INTRABAR_POLICY)rawPolicy;
}

bool CConsensusEngine::IsStrategyIntrabarLiveEligible(const int strategyIndex) const
{
    return (GetStrategyIntrabarPolicy(strategyIndex) == INTRABAR_POLICY_LIVE);
}

bool CConsensusEngine::IsStrategyIntrabarProbeEligible(const int strategyIndex) const
{
    return (GetStrategyIntrabarPolicy(strategyIndex) == INTRABAR_POLICY_PROBE);
}

double CConsensusEngine::CalculateAverageStrategyMetric(const int &strategyIndices[], const double &metrics[]) const
{
    if(m_src == NULL)
        return 0.0;

    int samples = MathMin(ArraySize(strategyIndices), ArraySize(metrics));
    if(samples <= 0)
        return 0.0;

    int strategyCount = m_src.GetStrategyCount();
    double weightedSum = 0.0;
    double totalWeight = 0.0;
    for(int i = 0; i < samples; i++)
    {
        int idx = strategyIndices[i];
        if(idx < 0 || idx >= strategyCount)
            continue;

        double metric = ClampUnitValue(metrics[i]);
        double weight = MathMax(0.0, m_src.GetStrategyWeight(idx));
        if(weight <= 0.0)
            continue;

        weightedSum += (metric * weight);
        totalWeight += weight;
    }

    if(totalWeight <= 0.0)
        return 0.0;

    return ClampUnitValue(weightedSum / totalWeight);
}

// Determine if current regime is trending for cross-cluster conflict
bool CConsensusEngine::IsTrendingRegime()
{
    if(m_src == NULL)
        return false;

    // Simple ADX check for forex/metals: ADX > 25 = trending, otherwise ranging.
    // The handle is cached here because creating and destroying it per call is expensive.
    int adxHandleCached = m_src.GetAdxHandleCached();
    if(adxHandleCached == INVALID_HANDLE)
    {
        adxHandleCached = iADX(m_src.GetManagedSymbol(), m_src.GetBaseTimeframe(), 14);
        m_src.SetAdxHandleCached(adxHandleCached);
    }

    if(adxHandleCached != INVALID_HANDLE)
    {
        double adxBuffer[];
        ArraySetAsSeries(adxBuffer, true);
        if(CopyBuffer(adxHandleCached, 0, 0, 1, adxBuffer) > 0)
        {
            return (adxBuffer[0] > 25.0);
        }
    }

    // Default: assume ranging (conservative)
    return false;
}

//--- When all strategies abstain, pick the best single strategy: prevents trading
//--- paralysis during low-signal periods.
ENUM_TRADE_SIGNAL CConsensusEngine::TryFallbackSoloSignal(const string symbol,
                                                          ENUM_SIGNAL_EVAL_MODE evalMode,
                                                          double &outConfidence,
                                                          int &outConfluence,
                                                          string &outReason)
{
    if(m_src == NULL)
    {
        outReason = "no_solo_candidates";
        return TRADE_SIGNAL_NONE;
    }

    if(m_src.GetPipelineConst() != NULL)
    {
        return TryFallbackSoloSignalInternal(symbol, evalMode, outConfidence, outConfluence, outReason);
    }

    // No pipeline: scan the raw strategy signals directly
    ENUM_TRADE_SIGNAL bestSignal = TRADE_SIGNAL_NONE;
    double bestScore = -1.0;
    string bestStrategy = "";

    int strategyCount = m_src.GetStrategyCount();
    CStrategyRegistry* strategyRegistry = m_src.GetStrategyRegistryConst();

    for(int i = 0; i < strategyCount; i++)
    {
        IStrategy* entryStrategy = m_src.GetStrategyPtr(i);
        if(!m_src.IsStrategyEnabled(i) || entryStrategy == NULL)
            continue;

        // Skip AI strategies in indicator-only mode
        ENUM_STRATEGY_TYPE stratType = entryStrategy.GetType();
        bool isAI = (stratType == STRATEGY_BRAIN || stratType == STRATEGY_AI_ENHANCED);

        if(isAI && strategyRegistry != NULL && strategyRegistry.GetMode() == EA_MODE_INDICATOR_ONLY)
            continue;

        double stratConf = 0.0;
        ENUM_TRADE_SIGNAL signal = entryStrategy.GetSignal(stratConf);

        if(signal == TRADE_SIGNAL_NONE)
            continue;

        double weight = m_src.GetStrategyWeight(i);
        double participation = GetStrategyParticipationMultiplier(i);

        // Scores are pinned neutral on this path: only confidence * weight * participation decides.
        double readinessScore = 0.5;
        double contextScore = 0.5;
        double costScore = 0.5;
        double qualityMultiplier = (readinessScore * 0.4 + contextScore * 0.4 + costScore * 0.2);
        double score = stratConf * weight * participation * qualityMultiplier;

        double minSoloConfidence = (evalMode == EVAL_MODE_INTRABAR) ? 0.70 : 0.65;
        if(stratConf < minSoloConfidence)
        {
            PrintFormat("[CONSENSUS-SOLO-SKIP] %s | %s conf=%.2f < min=%.2f",
                        symbol, m_src.GetStrategyName(i), stratConf, minSoloConfidence);
            continue;
        }

        if(score > bestScore)
        {
            bestScore = score;
            bestSignal = signal;
            bestStrategy = m_src.GetStrategyName(i);
            outConfidence = MathMin(0.85, stratConf * 0.9); // Slight penalty for solo
            outConfluence = 1;
            outReason = "solo_" + m_src.GetStrategyName(i);
        }
    }

    if(bestSignal != TRADE_SIGNAL_NONE)
    {
        PrintFormat("[CONSENSUS-SOLO-SELECT] %s | Selected %s signal=%s score=%.3f conf=%.2f",
                    symbol, bestStrategy, EnumToString(bestSignal), bestScore, outConfidence);
        return bestSignal;
    }

    outReason = "no_solo_candidates";
    return TRADE_SIGNAL_NONE;
}

// Hard regime gate: 0.0 when a strategy category has no edge in the current regime (vote hard-disabled),
// 1.0 when allowed, 0.25-0.40 to strongly deweight in ambiguous regimes.
double RegimeStateHardGate(ENUM_REGIME_STATE state, ENUM_STRATEGY_TYPE t)
{
    bool isTrendLike     = (t == STRATEGY_TREND || t == STRATEGY_MOMENTUM);
    bool isReversionLike = (t == STRATEGY_MEAN_REVERSION || t == STRATEGY_RANGE_COMPRESSION);

    switch(state)
    {
        case REGIME_TREND:
            // Confirmed trend: fading it (mean reversion) is the fastest way to blow an account.
            if(isReversionLike) return 0.0;
            return 1.0;
        case REGIME_RANGE:
            // Range-bound chop: trend/momentum systems whipsaw and bleed. Reversion is king here.
            if(isTrendLike) return 0.0;
            return 1.0;
        case REGIME_BREAKOUT:
            // Breakout: momentum/breakout thrive; reversion still dangerous -> strongly deweight (not hard-kill).
            if(isReversionLike) return 0.25;
            return 1.0;
        case REGIME_CHAOS:
            return 0.40;   // deweight everything, never hard-kill (avoid whipsaw death)
        default:
            return 1.0;
    }
}

double CConsensusEngine::GetRegimeCategoryMultiplier(const string symbol, ENUM_STRATEGY_TYPE strategyType) const
{
    // The regime multiplier is NOT floored: the old 0.4 floor could never zero a vote, which forced
    // trend systems to vote inside ranges and reversion systems inside trends.
    if(m_src == NULL)
        return 1.0;

    CUnifiedSignalPipeline* pipeline = m_src.GetPipelineConst();
    if(pipeline == NULL)
        return 1.0;

    CRegimeEngine* regime = pipeline.GetRegimeEngine(symbol);
    if(regime == NULL)
        return 1.0;

    SRegimeSnapshot snap = regime.GetSnapshot();

    // UNCLASSIFIED / warmup: never full-weight. Deliberate stand-aside bias.
    if(!snap.valid)
        return 0.30;

    double gate = RegimeStateHardGate(snap.state, strategyType);
    if(gate <= 0.0)
        return 0.0;   // vote disabled entirely

    // Per-category weight from the live regime composite (Hurst-blended).
    double catMult = 1.0;
    switch(strategyType)
    {
        case STRATEGY_TREND:              catMult = snap.trendWeightMult;     break;
        case STRATEGY_MOMENTUM:           catMult = snap.momentumWeightMult;  break;
        case STRATEGY_MEAN_REVERSION:     catMult = snap.meanRevWeightMult;    break;
        case STRATEGY_VOLATILITY_BREAKOUT:
        case STRATEGY_RANGE_COMPRESSION:  catMult = snap.breakoutWeightMult;   break;
        case STRATEGY_UNIFIED_ICT:
        case STRATEGY_UNICORN_MODEL:
        case STRATEGY_POWER_OF_THREE:
        case STRATEGY_FVG_SCALPER:
        case STRATEGY_BREAKER_BLOCK:
        case STRATEGY_LIQUIDITY_SWEEP:
        case STRATEGY_TURTLE_SOUP:        catMult = snap.ictWeightMult;        break;
        // AI / ONNX / CUSTOM / Statistical Arbitrage / Support-Resistance / Candlestick / Exit-Optimizer:
        // regime-neutral by design (1.0) - their edge is not a single regime category.
        default:                          catMult = 1.0;                       break;
    }

    // Low-confidence / transition regime: deweight but don't hard-kill (prevents whipsaw death).
    double confMult = 1.0;
    if(snap.state == REGIME_CHAOS)
        confMult = 0.30;
    else if(snap.regimeConfidence < 0.35)
        confMult = 0.55;

    if(!MathIsValidNumber(catMult) || catMult < 0.0)
        return 1.0;

    double mult = catMult * gate * confMult;
    return MathMax(0.0, MathMin(2.5, mult));
}

bool CConsensusEngine::IsStrategyLiveVoter(const int strategyIndex) const
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

double CConsensusEngine::GetStrategyReliabilityMultiplier(const int strategyIndex) const
{
    if(m_src == NULL)
        return 0.75;
    if(strategyIndex < 0 || strategyIndex >= m_src.GetStrategyCount())
        return 0.75;

    double healthScore = m_src.GetStrategyHealthScore(strategyIndex);
    if(healthScore <= 0.0)
        healthScore = 0.75;

    return MathMax(0.55, MathMin(1.15, 0.65 + (0.50 * healthScore)));
}

double CConsensusEngine::GetStrategyParticipationMultiplier(const int strategyIndex) const
{
    if(m_src == NULL)
        return 0.80;
    if(strategyIndex < 0 || strategyIndex >= m_src.GetStrategyCount())
        return 0.80;

    double participationScore = m_src.GetStrategyParticipationScore(strategyIndex);
    if(participationScore <= 0.0)
        participationScore = 0.90;

    double base = m_src.GetParticipationFormulaBase();
    double coeff = m_src.GetParticipationFormulaCoeff();
    double minVal = m_src.GetParticipationFormulaMin();
    double maxVal = m_src.GetParticipationFormulaMax();

    if(base == 0.0 && coeff == 0.0 && minVal == 0.0 && maxVal == 0.0)
    {
        base = 0.40;
        coeff = 0.65;
        minVal = 0.55;
        maxVal = 1.05;
    }

    return MathMax(minVal, MathMin(maxVal, base + (coeff * participationScore)));
}

double CConsensusEngine::GetStrategyRoleVoteMultiplier(const int strategyIndex) const
{
    if(m_src == NULL)
        return 1.0;
    if(strategyIndex < 0 || strategyIndex >= m_src.GetStrategyCount())
        return 1.0;

    ENUM_STRATEGY_ROLE role = (ENUM_STRATEGY_ROLE)m_src.GetStrategyRole(strategyIndex);
    if(role == CONTEXT_FEATURE)
        return 0.85;
    return 1.0;
}

double CConsensusEngine::CalculateDirectionDiversityScore(const int &strategyIndices[]) const
{
    if(m_src == NULL)
        return 0.0;
    if(ArraySize(strategyIndices) <= 0)
        return 0.0;

    int strategyCount = m_src.GetStrategyCount();

    bool roleSeen[2];
    bool clusterSeen[4];
    roleSeen[0] = false;
    roleSeen[1] = false;
    clusterSeen[0] = false;
    clusterSeen[1] = false;
    clusterSeen[2] = false;
    clusterSeen[3] = false;

    int roleCount = 0;
    int clusterCount = 0;
    for(int i = 0; i < ArraySize(strategyIndices); i++)
    {
        int idx = strategyIndices[i];
        if(idx < 0 || idx >= strategyCount)
            continue;

        int role = m_src.GetStrategyRole(idx);
        if(role < 0 || role > 1)
            role = 0;
        if(!roleSeen[role])
        {
            roleSeen[role] = true;
            roleCount++;
        }

        int cluster = m_src.GetStrategyCluster(idx);
        if(cluster < 0 || cluster > 3)
            cluster = 0;
        if(!clusterSeen[cluster])
        {
            clusterSeen[cluster] = true;
            clusterCount++;
        }
    }

    double roleScore = MathMax(0.0, MathMin(1.0, (double)roleCount / 3.0));
    double clusterScore = MathMax(0.0, MathMin(1.0, (double)clusterCount / 4.0));
    return MathMax(0.0, MathMin(1.0, (roleScore * 0.55) + (clusterScore * 0.45)));
}

ENUM_STRATEGY_ROLE CConsensusEngine::ResolveDominantRole(const int &strategyIndices[]) const
{
    double roleWeights[3];
    roleWeights[0] = 0.0;
    roleWeights[1] = 0.0;
    roleWeights[2] = 0.0;

    if(m_src == NULL)
        return (ENUM_STRATEGY_ROLE)0;

    int strategyCount = m_src.GetStrategyCount();

    for(int i = 0; i < ArraySize(strategyIndices); i++)
    {
        int idx = strategyIndices[i];
        if(idx < 0 || idx >= strategyCount)
            continue;

        int role = m_src.GetStrategyRole(idx);
        if(role < 0 || role > 2)
            role = 0;

        double weight = MathMax(0.0, m_src.GetStrategyWeight(idx));
        if(weight <= 0.0)
            continue;
        roleWeights[role] += weight;
    }

    int dominant = 0;
    if(roleWeights[1] > roleWeights[dominant])
        dominant = 1;
    if(roleWeights[2] > roleWeights[dominant])
        dominant = 2;

    return (ENUM_STRATEGY_ROLE)dominant;
}

ENUM_STRATEGY_CLUSTER CConsensusEngine::ResolveDominantCluster(const int &strategyIndices[]) const
{
    double clusterWeights[4];
    clusterWeights[0] = 0.0;
    clusterWeights[1] = 0.0;
    clusterWeights[2] = 0.0;
    clusterWeights[3] = 0.0;

    if(m_src == NULL)
        return (ENUM_STRATEGY_CLUSTER)0;

    int strategyCount = m_src.GetStrategyCount();

    for(int i = 0; i < ArraySize(strategyIndices); i++)
    {
        int idx = strategyIndices[i];
        if(idx < 0 || idx >= strategyCount)
            continue;

        int cluster = m_src.GetStrategyCluster(idx);
        if(cluster < 0 || cluster > 3)
            cluster = 0;

        double weight = MathMax(0.0, m_src.GetStrategyWeight(idx));
        if(weight <= 0.0)
            continue;
        clusterWeights[cluster] += weight;
    }

    int dominant = 0;
    if(clusterWeights[1] > clusterWeights[dominant])
        dominant = 1;
    if(clusterWeights[2] > clusterWeights[dominant])
        dominant = 2;
    if(clusterWeights[3] > clusterWeights[dominant])
        dominant = 3;

    return (ENUM_STRATEGY_CLUSTER)dominant;
}

string CConsensusEngine::JoinContributorsWithContext(const int &strategyIndices[]) const
{
    if(m_src == NULL)
        return "";

    int strategyCount = m_src.GetStrategyCount();

    string summary = "";
    for(int i = 0; i < ArraySize(strategyIndices); i++)
    {
        int idx = strategyIndices[i];
        if(idx < 0 || idx >= strategyCount)
            continue;

        if(StringLen(summary) > 0)
            summary += ",";

        string name = m_src.GetStrategyName(idx);
        ENUM_STRATEGY_ROLE role = (ENUM_STRATEGY_ROLE)m_src.GetStrategyRole(idx);
        ENUM_STRATEGY_CLUSTER cluster = (ENUM_STRATEGY_CLUSTER)m_src.GetStrategyCluster(idx);
        summary += name + "[" + StrategyRoleToString(role) + "|" + StrategyClusterToString(cluster) + "]";
    }
    return summary;
}

void CConsensusEngine::MaybeLogConsensusDiagnostics(const string symbol)
{
    if(m_src == NULL)
        return;

    CDiagnosticsManager* diagnostics = m_src.GetDiagnosticsConst();
    if(diagnostics != NULL)
    {
        diagnostics.MaybeLogDiagnostics(symbol);
    }
}

void CConsensusEngine::CalculateEffectiveQuorumParamsInternal(
    const string symbol,
    const int activeLiveStrategies,
    const int buyVotes,
    const int sellVotes,
    const int eligibleLiveVoterCount,
    const double buyDirectionalQuality,
    const double sellDirectionalQuality,
    const double buyScore,
    const double sellScore,
    const bool readyWeightMet,
    const ENUM_SIGNAL_EVAL_MODE evalMode,
    CUnifiedSignalPipeline* pipeline,
    int &buyContributorIndices[],
    int &sellContributorIndices[],
    double &effectiveQualityThreshold,
    double &supportFloor,
    int &effectiveMinVoters,
    double &buyQuorum,
    double &sellQuorum
) const
{
    if(m_src == NULL)
        return;

    int baseMinQuorum = (evalMode == EVAL_MODE_INTRABAR) ? m_src.GetIntrabarMinQuorum() : m_src.GetMinQuorum();
    double baseQuorumThreshold = m_src.GetQuorumThreshold();

    // Policy floor no quorum profile can lower. Capping the requirement at the
    // voters actually eligible made one lone voter 100% consensus.
    effectiveMinVoters = MathMax(baseMinQuorum, MIN_CONSENSUS_VOTERS);

    supportFloor = (evalMode == EVAL_MODE_INTRABAR) ? m_src.GetSupportFloorIntrabar() : m_src.GetSupportFloorNewBar();

    double pipelineConfFloor = 0.0;
    if(pipeline != NULL)
    {
        pipelineConfFloor = pipeline.GetLastEffectiveMinConfidence();
    }
    effectiveQualityThreshold = MathMax(m_src.GetPipelineMinConfidence(), pipelineConfFloor);

    // Higher directional quality (> 0.7) buys a slightly lower quorum threshold
    double qualityAdjustmentBuy = (buyDirectionalQuality > 0.7) ? -0.05 : 0.0;
    double qualityAdjustmentSell = (sellDirectionalQuality > 0.7) ? -0.05 : 0.0;

    if(evalMode == EVAL_MODE_INTRABAR && m_src.IsIntrabarDynamicQuorumEnabled())
    {
        if(eligibleLiveVoterCount < 3)
        {
            // For very sparse voting, require higher quality
            qualityAdjustmentBuy += 0.10;
            qualityAdjustmentSell += 0.10;
        }
    }

    buyQuorum = MathMax(0.30, MathMin(0.80, baseQuorumThreshold + qualityAdjustmentBuy));
    sellQuorum = MathMax(0.30, MathMin(0.80, baseQuorumThreshold + qualityAdjustmentSell));

    PrintFormat("[CONSENSUS-QUORUM] %s | mode=%s | minVoters=%d | supportFloor=%.2f | qualityThresh=%.2f | buyQuorum=%.2f | sellQuorum=%.2f",
                symbol,
                (evalMode == EVAL_MODE_INTRABAR ? "INTRABAR" : "NEW_BAR"),
                effectiveMinVoters, supportFloor, effectiveQualityThreshold, buyQuorum, sellQuorum);
}

ENUM_TRADE_SIGNAL CConsensusEngine::EvaluateConsensusInternal(const string symbol, double &confidence, int &confluence,
                                                              ENUM_SIGNAL_EVAL_MODE evalMode)
{
    ulong startTime = GetMicrosecondCount();

    confidence = 0.0;
    confluence = 0;

    // Reset the decision context first: a rejected or abstained cycle must not leak a stale
    // context (signal, quality, class) into the validator.
    SConsensusDecisionContext emptyDecisionContext;
    m_lastDecisionContext = emptyDecisionContext;

    if(m_src == NULL)
        return TRADE_SIGNAL_NONE;

    int strategyCount = m_src.GetStrategyCount();
    CUnifiedSignalPipeline* pipeline = m_src.GetPipelineConst();

    int activeLiveStrategies = 0;
    for(int i = 0; i < strategyCount; i++)
    {
        if(IsStrategyLiveVoter(i))
        {
            activeLiveStrategies++;
        }
    }

    if(activeLiveStrategies == 0)
    {
        PrintFormat("[CONSENSUS-ABSTAIN] %s | No live voting strategies", symbol);
        return TRADE_SIGNAL_NONE;
    }

    int buyVotes = 0;
    int sellVotes = 0;
    int eligibleLiveVoterCount = 0;
    double buyScore = 0.0;
    double sellScore = 0.0;
    double buyDirectionalQuality = 0.0;
    double sellDirectionalQuality = 0.0;

    int buyContributorIndices[];
    int sellContributorIndices[];
    ArrayResize(buyContributorIndices, 0);
    ArrayResize(sellContributorIndices, 0);

    for(int i = 0; i < strategyCount; i++)
    {
        if(!IsStrategyLiveVoter(i))
            continue;

        eligibleLiveVoterCount++;

        // MQL5 has no local references to array elements, hence the direct pointer fetch
        double stratConf = 0.0;
        IStrategy* entryStrategy = m_src.GetStrategyPtr(i);
        ENUM_TRADE_SIGNAL signal = entryStrategy.GetSignal(stratConf);

        if(signal == TRADE_SIGNAL_NONE)
        {
            continue;
        }

        bool passedPipeline = true;
        if(pipeline != NULL)
        {
            double filteredConf = stratConf;
            ENUM_TRADE_SIGNAL filteredSignal = pipeline.ProcessSignal(entryStrategy, symbol, m_src.GetStrategyTimeframe(i), filteredConf);

            if(filteredSignal == TRADE_SIGNAL_NONE)
            {
                passedPipeline = false;
                PrintFormat("[CONSENSUS-FILTERED] %s | %s | raw=%s conf=%.2f | filtered by %s",
                            symbol, m_src.GetStrategyName(i), EnumToString(signal), stratConf,
                            pipeline.GetLastFilterName());
            }
            else
            {
                signal = filteredSignal;
                stratConf = filteredConf;
            }
        }

        if(!passedPipeline)
            continue;

        double participation = GetStrategyParticipationMultiplier(i);
        double reliability = GetStrategyReliabilityMultiplier(i);

        double weight = m_src.GetStrategyWeight(i);
        double score = stratConf * weight * participation * reliability * GetRegimeCategoryMultiplier(symbol, entryStrategy.GetType());

        if(signal == TRADE_SIGNAL_BUY)
        {
            buyVotes++;
            buyScore += score;
            buyDirectionalQuality += stratConf * weight;
            int idx = ArraySize(buyContributorIndices);
            ArrayResize(buyContributorIndices, idx + 1);
            buyContributorIndices[idx] = i;
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            sellVotes++;
            sellScore += score;
            sellDirectionalQuality += stratConf * weight;
            int idx = ArraySize(sellContributorIndices);
            ArrayResize(sellContributorIndices, idx + 1);
            sellContributorIndices[idx] = i;
        }
    }

    if(buyVotes > 0) buyDirectionalQuality /= buyVotes;
    if(sellVotes > 0) sellDirectionalQuality /= sellVotes;

    if(buyVotes == 0 && sellVotes == 0)
    {
        PrintFormat("[CONSENSUS-ABSTAIN] %s | All strategies abstained or filtered out", symbol);
        return TRADE_SIGNAL_NONE;
    }

    // Ready weight ratio: the denominator is the weight of strategies that ACTUALLY voted (from the
    // contributor index arrays), not the whole roster, so abstainers cannot make the gate harder.
    double votedWeight = 0.0;
    for(int k = 0; k < ArraySize(buyContributorIndices); k++)
        votedWeight += m_src.GetStrategyWeight(buyContributorIndices[k]);
    for(int k = 0; k < ArraySize(sellContributorIndices); k++)
        votedWeight += m_src.GetStrategyWeight(sellContributorIndices[k]);

    double readyWeightRatio = (votedWeight > 0) ? (buyScore + sellScore) / votedWeight : 0.0;
    bool readyWeightMet = (readyWeightRatio >= m_src.GetMinReadyWeightRatio());

    if(!readyWeightMet)
    {
        PrintFormat("[CONSENSUS-REJECT] %s | Ready weight ratio %.2f < min %.2f",
                    symbol, readyWeightRatio, m_src.GetMinReadyWeightRatio());
        return TRADE_SIGNAL_NONE;
    }

    double effectiveQualityThreshold = 0.0;
    double supportFloor = 0.0;
    int effectiveMinVoters = 0;
    double buyQuorum = 0.0;
    double sellQuorum = 0.0;

    CalculateEffectiveQuorumParamsInternal(symbol, activeLiveStrategies, buyVotes, sellVotes,
                                           eligibleLiveVoterCount, buyDirectionalQuality, sellDirectionalQuality,
                                           buyScore, sellScore, readyWeightMet, evalMode,
                                           pipeline, buyContributorIndices, sellContributorIndices,
                                           effectiveQualityThreshold, supportFloor, effectiveMinVoters, buyQuorum, sellQuorum);

    ENUM_TRADE_SIGNAL consensusSignal = TRADE_SIGNAL_NONE;
    double winningScore = 0.0;
    double losingScore = 0.0;
    int winningVotes = 0;
    int losingVotes = 0;

    if(buyScore > sellScore)
    {
        consensusSignal = TRADE_SIGNAL_BUY;
        winningScore = buyScore;
        losingScore = sellScore;
        winningVotes = buyVotes;
        losingVotes = sellVotes;
    }
    else if(sellScore > buyScore)
    {
        consensusSignal = TRADE_SIGNAL_SELL;
        winningScore = sellScore;
        losingScore = buyScore;
        winningVotes = sellVotes;
        losingVotes = buyVotes;
    }
    else
    {
        PrintFormat("[CONSENSUS-TIE] %s | buyScore=%.3f sellScore=%.3f", symbol, buyScore, sellScore);
        return TRADE_SIGNAL_NONE;
    }

    if(winningVotes < effectiveMinVoters)
    {
        PrintFormat("[CONSENSUS-REJECT] %s | Winning votes %d < minVoters %d",
                    symbol, winningVotes, effectiveMinVoters);
        return TRADE_SIGNAL_NONE;
    }

    // Support floor: the winning share of the total score
    double totalScore = winningScore + losingScore;
    double supportRatio = (totalScore > 0) ? winningScore / totalScore : 0.0;

    if(supportRatio < supportFloor)
    {
        PrintFormat("[CONSENSUS-REJECT] %s | Support ratio %.2f < floor %.2f",
                    symbol, supportRatio, supportFloor);
        return TRADE_SIGNAL_NONE;
    }

    // Quorum ratio is measured against votes CAST, not the full assigned roster: a clear 1/1 or 2/2
    // winner scores 1.0 instead of being diluted by non-voting strategies (2/8 = 0.25).
    double winningQuorum = (consensusSignal == TRADE_SIGNAL_BUY) ? buyQuorum : sellQuorum;
    int totalVotesCast = buyVotes + sellVotes;
    double quorumRatio = (totalVotesCast > 0) ? (double)winningVotes / totalVotesCast : 0.0;

    if(quorumRatio < winningQuorum)
    {
        PrintFormat("[CONSENSUS-REJECT] %s | Quorum ratio %.2f < threshold %.2f",
                    symbol, quorumRatio, winningQuorum);
        return TRADE_SIGNAL_NONE;
    }

    if(losingVotes > 0)
    {
        // Conflict is measured against votes CAST, not the whole roster
        double conflictRatio = (double)losingVotes / (winningVotes + losingVotes);
        if(conflictRatio > m_src.GetConflictDeadband())
        {
            PrintFormat("[CONSENSUS-VETOED] %s | Conflict ratio %.2f > deadband %.2f",
                        symbol, conflictRatio, m_src.GetConflictDeadband());
            return TRADE_SIGNAL_NONE;
        }
    }

    double winningQuality = (consensusSignal == TRADE_SIGNAL_BUY) ? buyDirectionalQuality : sellDirectionalQuality;
    if(winningQuality < effectiveQualityThreshold)
    {
        PrintFormat("[CONSENSUS-REJECT] %s | Quality %.2f < threshold %.2f",
                    symbol, winningQuality, effectiveQualityThreshold);
        return TRADE_SIGNAL_NONE;
    }

    confluence = winningVotes;
    confidence = MathMin(0.95, winningQuality * 0.8 + supportRatio * 0.2);

    string decisionClass = "FULL_QUORUM";
    if(evalMode == EVAL_MODE_INTRABAR && eligibleLiveVoterCount < 3)
    {
        decisionClass = "SPARSE_INTRABAR";
    }

    PrintFormat("[CONSENSUS-DECISION] %s | %s | class=%s | conf=%.2f | confluence=%d | votes=%d/%d | support=%.2f | quorum=%.2f/%.2f",
                symbol, EnumToString(consensusSignal), decisionClass, confidence, confluence,
                buyVotes, sellVotes, supportRatio, quorumRatio, winningQuorum);

    // m_lastDecisionContext must be written from the values just computed: a default struct would
    // zero the validator's quality gate. directionalQuality stays at the real winning quality.
    double totalDirScore = buyScore + sellScore;
    m_lastDecisionContext.symbol                 = symbol;
    m_lastDecisionContext.signal                 = consensusSignal;
    m_lastDecisionContext.decisionClass          = (decisionClass == "SPARSE_INTRABAR")
                                                   ? (int)CONSENSUS_DECISION_SPARSE_INTRABAR
                                                   : (int)CONSENSUS_DECISION_FULL_QUORUM;
    m_lastDecisionContext.confidence             = confidence;
    // Clamped to [0,1]: the weighted sum can exceed 1.0, but the quality gate expects a normalized score.
    m_lastDecisionContext.directionalQuality     = MathMax(0.0, MathMin(1.0, winningQuality));
    m_lastDecisionContext.buyScore               = buyScore;
    m_lastDecisionContext.sellScore              = sellScore;
    m_lastDecisionContext.buySupport             = (totalDirScore > 0.0) ? buyScore / totalDirScore : 0.0;
    m_lastDecisionContext.sellSupport            = (totalDirScore > 0.0) ? sellScore / totalDirScore : 0.0;
    m_lastDecisionContext.supportRatio           = supportRatio;
    m_lastDecisionContext.quorumGap              = winningScore - losingScore;
    m_lastDecisionContext.confluence             = confluence;
    m_lastDecisionContext.eligibleLiveVoterCount = eligibleLiveVoterCount;
    m_lastDecisionContext.effectiveMinVoters     = effectiveMinVoters;
    m_lastDecisionContext.quorumMode             = decisionClass;
    m_lastDecisionContext.vetoCode               = "";
    m_lastDecisionContext.reason                 = "consensus_reached";

    ulong elapsed = GetMicrosecondCount() - startTime;
    CJsonLogger::LogPerformance("EnterpriseStrategyManager", "EvaluateConsensusInternal_us", (double)elapsed, CCorrelationIdGenerator::Generate());

    return consensusSignal;
}

ENUM_TRADE_SIGNAL CConsensusEngine::EvaluateConsensusTwoTierInternal(const string symbol, double &confidence, int &confluence,
                                                                     ENUM_SIGNAL_EVAL_MODE evalMode)
{
    // Tier 1: probe-only fast path, checks whether there is enough probe support

    ulong startTime = GetMicrosecondCount();

    int probeBuyVotes = 0;
    int probeSellVotes = 0;
    int probeEligibleCount = 0;

    if(m_src == NULL)
    {
        confidence = 0.0;
        confluence = 0;
        return TRADE_SIGNAL_NONE;
    }

    int strategyCount = m_src.GetStrategyCount();

    for(int i = 0; i < strategyCount; i++)
    {
        if(!IsStrategyLiveVoter(i))
            continue;

        if(!m_src.IsStrategyProbeEligible(i))
            continue;

        probeEligibleCount++;

        // Probe reads the raw signal, no pipeline filtering
        double stratConf = 0.0;
        ENUM_TRADE_SIGNAL signal = m_src.GetStrategyPtr(i).GetSignal(stratConf);

        if(signal == TRADE_SIGNAL_BUY && stratConf >= 0.5)
            probeBuyVotes++;
        else if(signal == TRADE_SIGNAL_SELL && stratConf >= 0.5)
            probeSellVotes++;
    }

    if(probeBuyVotes == 0 && probeSellVotes == 0)
    {
        PrintFormat("[CONSENSUS-PROBE] %s | No probe support (buy=%d sell=%d)", symbol, probeBuyVotes, probeSellVotes);
        confidence = 0.0;
        confluence = 0;
        return TRADE_SIGNAL_NONE;
    }

    // Tier 2: full consensus evaluation
    ENUM_TRADE_SIGNAL result = EvaluateConsensusInternal(symbol, confidence, confluence, evalMode);

    ulong elapsed = GetMicrosecondCount() - startTime;
    CJsonLogger::LogPerformance("EnterpriseStrategyManager", "EvaluateConsensusTwoTierInternal_us", (double)elapsed, CCorrelationIdGenerator::Generate());

    return result;
}

ENUM_TRADE_SIGNAL CConsensusEngine::EvaluateConsensusProbeOnlyInternal(const string symbol, double &confidence, int &confluence,
                                                                       ENUM_SIGNAL_EVAL_MODE evalMode)
{
    // Probe-only path: no pipeline filtering and no full quorum, used for intrabar direction probing.

    ulong startTime = GetMicrosecondCount();

    int probeBuyVotes = 0;
    int probeSellVotes = 0;
    double probeBuyScore = 0.0;
    double probeSellScore = 0.0;
    int probeEligibleCount = 0;

    if(m_src == NULL)
    {
        confidence = 0.0;
        confluence = 0;
        return TRADE_SIGNAL_NONE;
    }

    int strategyCount = m_src.GetStrategyCount();
    double sparseIntrabarMinQuality = m_src.GetSparseIntrabarMinQuality();

    for(int i = 0; i < strategyCount; i++)
    {
        if(!IsStrategyLiveVoter(i))
            continue;

        if(!m_src.IsStrategyProbeEligible(i))
            continue;

        probeEligibleCount++;

        double stratConf = 0.0;
        ENUM_TRADE_SIGNAL signal = m_src.GetStrategyPtr(i).GetSignal(stratConf);

        if(signal == TRADE_SIGNAL_NONE || stratConf < sparseIntrabarMinQuality)
            continue;

        double weight = m_src.GetStrategyWeight(i);
        double participation = GetStrategyParticipationMultiplier(i);
        double reliability = GetStrategyReliabilityMultiplier(i);
        double score = stratConf * weight * participation * reliability * GetRegimeCategoryMultiplier(symbol, m_src.GetStrategyPtr(i).GetType());

        if(signal == TRADE_SIGNAL_BUY)
        {
            probeBuyVotes++;
            probeBuyScore += score;
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            probeSellVotes++;
            probeSellScore += score;
        }
    }

    if(probeBuyVotes == 0 && probeSellVotes == 0)
    {
        confidence = 0.0;
        confluence = 0;
        return TRADE_SIGNAL_NONE;
    }

    ENUM_TRADE_SIGNAL probeSignal = TRADE_SIGNAL_NONE;
    double winningScore = 0.0;
    int winningVotes = 0;

    if(probeBuyScore > probeSellScore)
    {
        probeSignal = TRADE_SIGNAL_BUY;
        winningScore = probeBuyScore;
        winningVotes = probeBuyVotes;
    }
    else if(probeSellScore > probeBuyScore)
    {
        probeSignal = TRADE_SIGNAL_SELL;
        winningScore = probeSellScore;
        winningVotes = probeSellVotes;
    }

    double supportRatio = (probeEligibleCount > 0) ? (double)winningVotes / probeEligibleCount : 0.0;
    if(supportRatio < m_src.GetSparseIntrabarMinSupportRatio())
    {
        PrintFormat("[CONSENSUS-PROBE-REJECT] %s | Support ratio %.2f < min %.2f",
                    symbol, supportRatio, m_src.GetSparseIntrabarMinSupportRatio());
        confidence = 0.0;
        confluence = 0;
        return TRADE_SIGNAL_NONE;
    }

    confluence = winningVotes;
    confidence = MathMin(0.8, winningScore / MathMax(1.0, probeBuyScore + probeSellScore));

    PrintFormat("[CONSENSUS-PROBE-DECISION] %s | %s | conf=%.2f | confluence=%d | support=%.2f",
                symbol, EnumToString(probeSignal), confidence, confluence, supportRatio);

    ulong elapsed = GetMicrosecondCount() - startTime;
    CJsonLogger::LogPerformance("EnterpriseStrategyManager", "EvaluateConsensusProbeOnlyInternal_us", (double)elapsed, CCorrelationIdGenerator::Generate());

    return probeSignal;
}

ENUM_TRADE_SIGNAL CConsensusEngine::TryFallbackSoloSignalInternal(const string symbol,
                                                                  ENUM_SIGNAL_EVAL_MODE evalMode,
                                                                  double &outConfidence,
                                                                  int &outConfluence,
                                                                  string &outReason)
{
    // Called when all strategies abstain but the pipeline is available: best solo signal, relaxed thresholds

    ulong startTime = GetMicrosecondCount();

    ENUM_TRADE_SIGNAL bestSignal = TRADE_SIGNAL_NONE;
    double bestScore = -1.0;
    string bestStrategy = "";
    double bestConfidence = 0.0;

    if(m_src == NULL)
    {
        outReason = "no_solo_candidates";
        return TRADE_SIGNAL_NONE;
    }

    int strategyCount = m_src.GetStrategyCount();
    CUnifiedSignalPipeline* pipeline = m_src.GetPipelineConst();
    CStrategyRegistry* strategyRegistry = m_src.GetStrategyRegistryConst();

    for(int i = 0; i < strategyCount; i++)
    {
        IStrategy* entryStrategy = m_src.GetStrategyPtr(i);
        if(!m_src.IsStrategyEnabled(i) || entryStrategy == NULL)
            continue;

        // Skip AI strategies in indicator-only mode
        ENUM_STRATEGY_TYPE stratType = entryStrategy.GetType();
        bool isAI = (stratType == STRATEGY_BRAIN || stratType == STRATEGY_AI_ENHANCED);

        if(isAI && strategyRegistry != NULL && strategyRegistry.GetMode() == EA_MODE_INDICATOR_ONLY)
            continue;

        double stratConf = 0.0;
        ENUM_TRADE_SIGNAL signal = entryStrategy.GetSignal(stratConf);

        if(signal == TRADE_SIGNAL_NONE)
            continue;

        bool passedPipeline = true;
        double filteredConf = stratConf;
        ENUM_TRADE_SIGNAL filteredSignal = signal;

        if(pipeline != NULL)
        {
            filteredSignal = pipeline.ProcessSignal(entryStrategy, symbol, m_src.GetStrategyTimeframe(i), filteredConf);
            if(filteredSignal == TRADE_SIGNAL_NONE)
            {
                // Solo fallback keeps pipeline-filtered signals; the flag only gates the boost below
                passedPipeline = false;
            }
            else
            {
                signal = filteredSignal;
                stratConf = filteredConf;
            }
        }

        double weight = m_src.GetStrategyWeight(i);
        double participation = GetStrategyParticipationMultiplier(i);
        double reliability = GetStrategyReliabilityMultiplier(i);

        double readinessScore = m_src.GetStrategyReadinessScore(i);
        double contextScore = m_src.GetStrategyContextScore(i);
        double costScore = m_src.GetStrategyCostScore(i);
        double qualityMultiplier = (readinessScore * 0.4 + contextScore * 0.4 + costScore * 0.2);
        double score = stratConf * weight * participation * reliability * qualityMultiplier * GetRegimeCategoryMultiplier(symbol, entryStrategy.GetType());

        double minSoloConfidence = (evalMode == EVAL_MODE_INTRABAR) ? 0.70 : 0.65;
        if(stratConf < minSoloConfidence)
        {
            PrintFormat("[CONSENSUS-SOLO-SKIP] %s | %s conf=%.2f < min=%.2f",
                        symbol, m_src.GetStrategyName(i), stratConf, minSoloConfidence);
            continue;
        }

        if(passedPipeline)
        {
            score *= 1.1; // 10% boost for pipeline-validated signals
        }

        if(score > bestScore)
        {
            bestScore = score;
            bestSignal = signal;
            bestStrategy = m_src.GetStrategyName(i);
            bestConfidence = stratConf;
        }
    }

    if(bestSignal != TRADE_SIGNAL_NONE)
    {
        outConfidence = MathMin(0.85, bestConfidence * 0.9); // Slight penalty for solo
        outConfluence = 1;
        outReason = "solo_" + bestStrategy;

        PrintFormat("[CONSENSUS-SOLO-SELECT] %s | Selected %s signal=%s score=%.3f conf=%.2f | pipeline=%s",
                    symbol, bestStrategy, EnumToString(bestSignal), bestScore, outConfidence,
                    (pipeline != NULL ? "yes" : "no"));

        ulong elapsed = GetMicrosecondCount() - startTime;
        CJsonLogger::LogPerformance("EnterpriseStrategyManager", "TryFallbackSoloSignalInternal_us", (double)elapsed, CCorrelationIdGenerator::Generate());

        return bestSignal;
    }

    outReason = "no_solo_candidates";

    ulong elapsed = GetMicrosecondCount() - startTime;
    CJsonLogger::LogPerformance("EnterpriseStrategyManager", "TryFallbackSoloSignalInternal_us", (double)elapsed, CCorrelationIdGenerator::Generate());

    return TRADE_SIGNAL_NONE;
}

#endif // CONSENSUS_ENGINE_MQH
