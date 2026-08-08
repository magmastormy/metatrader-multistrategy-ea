//+------------------------------------------------------------------+
//| Consensus Engine (Phase C, Slice 5 - C9)                          |
//| The consensus decision core extracted WHOLESALE from              |
//| CEnterpriseStrategyManager. Unlike C1-C8 this slice is            |
//| deliberately NOT piecemeal: the entry funnel, the quorum          |
//| computation, the evaluation body, the two-tier / probe fast paths |
//| and the solo fallback are one load-bearing unit and are moved     |
//| together so no half of a decision path can drift from the other.  |
//|                                                                   |
//| ENTRY FUNNEL (public overloads kept verbatim - EAOrchestrator,    |
//| SignalGenerator, PositionLifecycleManager and TrainingDataExporter|
//| call them through the manager's forwarders):                      |
//|   - GetConsensusSignal                                            |
//|   - GetConsensusSignalWithConfluence                              |
//|   - GetConsensusSignalForSymbol                                   |
//|   - GetConsensusSignalForSymbolWithConfluence                     |
//|   - GetConsensusSignalForSymbolWithConfluenceMode  (the funnel)   |
//|   - EvaluateConsensusTwoTier                                      |
//|   - TryFallbackSoloSignal                                         |
//|                                                                   |
//| EVALUATION CORE:                                                  |
//|   - EvaluateConsensusInternal          (the decision body)        |
//|   - EvaluateConsensusTwoTierInternal   (probe gate + full eval)   |
//|   - EvaluateConsensusProbeOnlyInternal (intrabar fast path)       |
//|   - TryFallbackSoloSignalInternal      (all-abstain fallback)     |
//|   - CalculateEffectiveQuorumParamsInternal                        |
//|                                                                   |
//| VOTE / WEIGHTING HELPERS (consensus-only callers):                |
//|   - IsStrategyLiveVoter, GetStrategyReliabilityMultiplier,        |
//|     GetStrategyParticipationMultiplier, GetStrategyRoleVoteMultiplier,|
//|     GetRegimeCategoryMultiplier, CalculateDirectionDiversityScore,|
//|     CalculateAverageStrategyMetric, ClampUnitValue,               |
//|     GetStrategyIntrabarPolicy, IsStrategyIntrabarLiveEligible,    |
//|     IsStrategyIntrabarProbeEligible, IsTrendingRegime,            |
//|     ResolveDominantRole, ResolveDominantCluster,                  |
//|     JoinContributorsWithContext,                                  |
//|     AccumulateRoleClusterSignalDiagnostics,                       |
//|     MaybeLogConsensusDiagnostics                                  |
//|                                                                   |
//| REGISTRY RECONCILIATION - HARD GUARD:                             |
//|   - SyncEnabledWithRegistry(). The IMPLEMENTATION lives here, but |
//|     CEnterpriseStrategyManager::SyncEnabledWithRegistry() is      |
//|     retained as a one-line forwarder because its only call site,  |
//|     Core/Orchestration/EAOrchestrator.mqh:768, must stay          |
//|     byte-stable. Do not remove that forwarder.                    |
//|                                                                   |
//| FIELD OWNERSHIP:                                                  |
//|   - m_lastDecisionContext MOVES here. It has exactly one writer   |
//|     (EvaluateConsensusInternal) and one reader path               |
//|     (manager GetLastDecisionContextValue -> CStrategyStateReporter|
//|     -> GetLastDecisionContext). The manager's accessor now        |
//|     forwards to this module, preserving the 1-writer/1-reader     |
//|     relationship exactly.                                         |
//|   - m_lastVPINMultiplier is NOT here: Phase C / Slice 2 already   |
//|     moved it into CPostConsensusValidator, which owns it.         |
//|   - enabled / liveVotingEnabled / intrabarPolicy are READ through |
//|     m_src accessors and are NOT owned here - they are written by  |
//|     manager methods that stay in the manager (registration,       |
//|     lifecycle, governance setters).                               |
//|                                                                   |
//| This module MUTATES the manager (SyncEnabledWithRegistry writes   |
//| enable flags, IsTrendingRegime caches the ADX handle), so it      |
//| holds a NON-const back-pointer and writes through the manager's   |
//| narrow per-field accessors. It mirrors no injected pointer (the   |
//| pipeline / registry / diagnostics are re-read from the manager on |
//| every call), so - like Slice 2/3 - it needs no re-sync on Deinit. |
//|                                                                   |
//| NOTE: this header is an implementation detail of                  |
//| EnterpriseStrategyManager.mqh and is included from there (after   |
//| the shared free helpers, before the manager class). It is not     |
//| intended to be included standalone.                               |
//+------------------------------------------------------------------+
#ifndef CONSENSUS_ENGINE_MQH
#define CONSENSUS_ENGINE_MQH

#include "../Utils/Enums.mqh"                     // ENUM_TRADE_SIGNAL, ENUM_SIGNAL_EVAL_MODE,
                                                  // ENUM_STRATEGY_ROLE/CLUSTER/TYPE,
                                                  // ENUM_INTRABAR_POLICY, SConsensusDecisionContext
#include "../../Interfaces/IStrategy.mqh"         // IStrategy::GetSignal / GetType / SetEnabled
#include "../Pipeline/UnifiedSignalPipeline.mqh"  // CUnifiedSignalPipeline::ProcessSignal
#include "../Strategy/StrategyRegistry.mqh"       // CStrategyRegistry::IsStrategyActive / GetMode
#include "../Utils/JsonLogger.mqh"                // CJsonLogger, CCorrelationIdGenerator
#include "DiagnosticsManager.mqh"                 // CDiagnosticsManager

class CEnterpriseStrategyManager;   // forward: held as a mutable pointer

//+------------------------------------------------------------------+
//| Consensus decision core over CEnterpriseStrategyManager           |
//+------------------------------------------------------------------+
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

    //--- registry reconciliation (HARD GUARD: manager keeps a forwarder)
    void SyncEnabledWithRegistry();

    //--- decision context ownership
    void GetLastDecisionContextValue(SConsensusDecisionContext &out) const { out = m_lastDecisionContext; }

    //--- vote / weighting helpers
    bool   IsStrategyLiveVoter(const int strategyIndex) const;
    double GetRegimeCategoryMultiplier(ENUM_STRATEGY_TYPE strategyType) const;
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
    void   AccumulateRoleClusterSignalDiagnostics(const int strategyIndex, const bool signalGenerated);
    void   MaybeLogConsensusDiagnostics(const string symbol);

private:
    //--- evaluation core
    ENUM_TRADE_SIGNAL EvaluateConsensusInternal(const string symbol, double &confidence, int &confluence,
                                                ENUM_SIGNAL_EVAL_MODE evalMode);
    ENUM_TRADE_SIGNAL EvaluateConsensusTwoTierInternal(const string symbol, double &confidence, int &confluence,
                                                       ENUM_SIGNAL_EVAL_MODE evalMode);
    ENUM_TRADE_SIGNAL EvaluateConsensusProbeOnlyInternal(const string symbol, double &confidence, int &confluence,
                                                         ENUM_SIGNAL_EVAL_MODE evalMode);
    ENUM_TRADE_SIGNAL TryFallbackSoloSignalInternal(const string symbol, ENUM_SIGNAL_EVAL_MODE evalMode,
                                                    double &outConfidence, int &outConfluence, string &outReason);
    //--- NOTE ON SIGNATURE: the original manager-side declaration also took
    //--- `StrategyEntry &strategies[]`. That parameter was never read in the
    //--- body (verified against the pre-extraction source) and the strategy
    //--- array is not reachable from this module, so it is the single dropped
    //--- parameter. Every other parameter - including the ones the body does
    //--- not read (activeLiveStrategies, buyVotes, sellVotes, buyScore,
    //--- sellScore, readyWeightMet, the contributor index arrays) - is kept so
    //--- the call shape stays recognisable. This method is private with exactly
    //--- one caller, so the change is not observable.
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

//+------------------------------------------------------------------+
//| Get Consensus Signal (backward compatible)                      |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CConsensusEngine::GetConsensusSignal(double &confidence)
{
    int confluence = 0;
    return GetConsensusSignalWithConfluence(confidence, confluence);
}

//+------------------------------------------------------------------+
//| Get Consensus Signal With Confluence                            |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Get Consensus Signal For Specific Symbol With Confluence        |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CConsensusEngine::GetConsensusSignalForSymbolWithConfluence(const string symbol,
                                                                             double &confidence,
                                                                             int &confluence)
{
    return GetConsensusSignalForSymbolWithConfluenceMode(symbol, confidence, confluence, EVAL_MODE_NEW_BAR);
}

//+------------------------------------------------------------------+
//| Get Consensus Signal For Specific Symbol                        |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CConsensusEngine::GetConsensusSignalForSymbol(const string symbol, double &confidence)
{
    int confluence = 0;
    return GetConsensusSignalForSymbolWithConfluence(symbol, confidence, confluence);
}

//+------------------------------------------------------------------+
//| Consensus entry funnel                                           |
//+------------------------------------------------------------------+
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

    // L1-007: Use internal consensus evaluation (consensus logic moved into EnterpriseStrategyManager)
    ENUM_TRADE_SIGNAL result;
    if(m_src.GetPipelineConst() != NULL && m_src.GetTFConsistencyConst() != NULL)
    {
        result = EvaluateConsensusInternal(symbol, confidence, confluence, evalMode);
    }
    else
    {
        // Fallback if consensus engine not initialized
        confluence = 0;
        confidence = 0;
        result = TRADE_SIGNAL_NONE;
    }

    // Performance timing log
            ulong elapsed = GetMicrosecondCount() - startTime;
            CJsonLogger::LogPerformance("EnterpriseStrategyManager", "GetConsensusSignalForSymbolWithConfluenceMode_us", (double)elapsed, CCorrelationIdGenerator::Generate());

    return result;
}

//+------------------------------------------------------------------+
//| Two-tier consensus evaluation - uses internal consensus logic   |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Reconcile enabled flags with the finalized registry            |
//| Strategies are auto-registered (AutoRegisterStrategies) BEFORE |
//| the orchestrator's BuildStrategyRegistry populates the shared  |
//| CStrategyRegistry with definitions. At that early point         |
//| IsStrategyActive() returns false (definition not found), so the|
//| override at RegisterStrategy() locks every strategy disabled.   |
//| After BuildStrategyRegistry finalizes the mode, this method     |
//| re-applies the registry's active state so the live strategy     |
//| objects actually participate in consensus.                      |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Unit clamp (member form; shadows the free helper, as before)     |
//+------------------------------------------------------------------+
double CConsensusEngine::ClampUnitValue(const double value) const
{
    if(!MathIsValidNumber(value))
        return 0.0;
    return MathMax(0.0, MathMin(1.0, value));
}

//+------------------------------------------------------------------+
//| Per-strategy intrabar policy resolution                          |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Weighted average of a per-strategy metric                        |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Determine if current regime is trending for cross-cluster conflict |
//+------------------------------------------------------------------+
bool CConsensusEngine::IsTrendingRegime()
{
    if(m_src == NULL)
        return false;

    // Fallback: simple ADX-based check (for forex/metals)
    // ADX > 25 = trending, otherwise ranging
    // Batch 116: use cached handle instead of creating/destroying per call
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

//+------------------------------------------------------------------+
//| FALLBACK SOLO SIGNAL: When all strategies abstain, pick best     |
//| single strategy based on confidence and context quality          |
//| Prevents trading paralysis during low-signal periods             |
//+------------------------------------------------------------------+
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

    // Fallback implementation if consensus engine not available
    ENUM_TRADE_SIGNAL bestSignal = TRADE_SIGNAL_NONE;
    double bestScore = -1.0;
    string bestStrategy = "";

    int strategyCount = m_src.GetStrategyCount();
    CStrategyRegistry* strategyRegistry = m_src.GetStrategyRegistryConst();

    // Iterate all strategies and get their raw signals (without pipeline filtering)
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

        // Get raw signal from strategy
        double stratConf = 0.0;
        ENUM_TRADE_SIGNAL signal = entryStrategy.GetSignal(stratConf);

        if(signal == TRADE_SIGNAL_NONE)
            continue;

        // Apply basic quality filters
        double weight = m_src.GetStrategyWeight(i);
        double participation = GetStrategyParticipationMultiplier(i);

        // Score = confidence * weight * participation * qualityMultiplier
        double readinessScore = 0.5; // Default neutral
        double contextScore = 0.5;   // Default neutral
        double costScore = 0.5;      // Default neutral
        double qualityMultiplier = (readinessScore * 0.4 + contextScore * 0.4 + costScore * 0.2);
        double score = stratConf * weight * participation * qualityMultiplier;

        // Apply minimum threshold
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

//+------------------------------------------------------------------+
//| Consensus fallback multipliers (hardcoded defaults preserved)    |
//+------------------------------------------------------------------+
double CConsensusEngine::GetRegimeCategoryMultiplier(ENUM_STRATEGY_TYPE strategyType) const
{
    // Regime-based weighting unavailable - return default
    return 1.0;
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

    // Use defaults if not configured
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

void CConsensusEngine::AccumulateRoleClusterSignalDiagnostics(const int strategyIndex, const bool signalGenerated)
{
    if(m_src == NULL)
        return;

    CDiagnosticsManager* diagnostics = m_src.GetDiagnosticsConst();
    if(diagnostics != NULL)
    {
        diagnostics.AccumulateRoleClusterSignalDiagnostics(strategyIndex, signalGenerated);
    }
    // Note: The strategy role/cluster info needs to be passed to diagnostics collector
    // For now, the diagnostics collector has a placeholder implementation
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
    // Note: The detailed logging with strategy participation analysis is now handled by DiagnosticsCollector
    // The dormant strategy warning logic would need to be ported to DiagnosticsCollector or kept here
    // For now, we delegate the basic logging to DiagnosticsCollector
}

//+------------------------------------------------------------------+
//| Calculate Effective Quorum Parameters (Internal)                |
//+------------------------------------------------------------------+
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

    // Base quorum thresholds from configuration
    int baseMinQuorum = (evalMode == EVAL_MODE_INTRABAR) ? m_src.GetIntrabarMinQuorum() : m_src.GetMinQuorum();
    double baseQuorumThreshold = m_src.GetQuorumThreshold();

    // Effective minimum voters - ensure at least baseMinQuorum
    // [PROFIT-01] Cap quorum at the voters actually available; never require unanimity.
    effectiveMinVoters = MathMax(1, MathMin(baseMinQuorum, eligibleLiveVoterCount));

    // Support floor based on evaluation mode
    supportFloor = (evalMode == EVAL_MODE_INTRABAR) ? m_src.GetSupportFloorIntrabar() : m_src.GetSupportFloorNewBar();

    // Quality threshold based on pipeline confidence floor and regime
    double pipelineConfFloor = 0.0;
    if(pipeline != NULL)
    {
        pipelineConfFloor = pipeline.GetLastEffectiveMinConfidence();
    }
    effectiveQualityThreshold = MathMax(m_src.GetPipelineMinConfidence(), pipelineConfFloor);

    // Adjust quorum thresholds based on directional quality and voter count
    // Higher directional quality allows slightly lower quorum
    double qualityAdjustmentBuy = (buyDirectionalQuality > 0.7) ? -0.05 : 0.0;
    double qualityAdjustmentSell = (sellDirectionalQuality > 0.7) ? -0.05 : 0.0;

    // Sparse intrabar adjustment
    if(evalMode == EVAL_MODE_INTRABAR && m_src.IsIntrabarDynamicQuorumEnabled())
    {
        if(eligibleLiveVoterCount < 3)
        {
            // For very sparse voting, require higher quality
            qualityAdjustmentBuy += 0.10;
            qualityAdjustmentSell += 0.10;
        }
    }

    buyQuorum = MathMax(0.35, MathMin(0.85, baseQuorumThreshold + qualityAdjustmentBuy));
    sellQuorum = MathMax(0.35, MathMin(0.85, baseQuorumThreshold + qualityAdjustmentSell));

    // Log quorum parameters for diagnostics
    PrintFormat("[CONSENSUS-QUORUM] %s | mode=%s | minVoters=%d | supportFloor=%.2f | qualityThresh=%.2f | buyQuorum=%.2f | sellQuorum=%.2f",
                symbol,
                (evalMode == EVAL_MODE_INTRABAR ? "INTRABAR" : "NEW_BAR"),
                effectiveMinVoters, supportFloor, effectiveQualityThreshold, buyQuorum, sellQuorum);
}

//+------------------------------------------------------------------+
//| Evaluate Consensus Internal (Main Consensus Logic)              |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CConsensusEngine::EvaluateConsensusInternal(const string symbol, double &confidence, int &confluence,
                                                              ENUM_SIGNAL_EVAL_MODE evalMode)
{
    ulong startTime = GetMicrosecondCount();

    // Reset outputs
    confidence = 0.0;
    confluence = 0;

    // [BUGFIX] Clear the previous decision context so a rejected/abstained evaluation can never
    // leak a stale context (signal, quality, class) from an earlier cycle into the validator.
    SConsensusDecisionContext emptyDecisionContext;
    m_lastDecisionContext = emptyDecisionContext;

    if(m_src == NULL)
        return TRADE_SIGNAL_NONE;

    int strategyCount = m_src.GetStrategyCount();
    CUnifiedSignalPipeline* pipeline = m_src.GetPipelineConst();

    // Check if we have live voting strategies
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

    // Collect votes from each strategy
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

        // Get signal from strategy (direct array access - MQL5 doesn't support local references to array elements)
        double stratConf = 0.0;
        IStrategy* entryStrategy = m_src.GetStrategyPtr(i);
        ENUM_TRADE_SIGNAL signal = entryStrategy.GetSignal(stratConf);

        if(signal == TRADE_SIGNAL_NONE)
        {
            // Strategy abstains
            continue;
        }

        // Apply pipeline filtering if available
        bool passedPipeline = true;
        if(pipeline != NULL)
        {
            double filteredConf = stratConf;
            ENUM_TRADE_SIGNAL filteredSignal = pipeline.ProcessSignal(entryStrategy, symbol, m_src.GetStrategyTimeframe(i), filteredConf);

            if(filteredSignal == TRADE_SIGNAL_NONE)
            {
                passedPipeline = false;
                // Log filtered signal
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

        // Calculate participation multiplier from health monitor
        double participation = GetStrategyParticipationMultiplier(i);
        double reliability = GetStrategyReliabilityMultiplier(i);

        // Weighted score = confidence * weight * participation * reliability
        double weight = m_src.GetStrategyWeight(i);
        double score = stratConf * weight * participation * reliability;

        // Track directional quality
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

    // Normalize directional quality
    if(buyVotes > 0) buyDirectionalQuality /= buyVotes;
    if(sellVotes > 0) sellDirectionalQuality /= sellVotes;

    // Check if any votes exist
    if(buyVotes == 0 && sellVotes == 0)
    {
        PrintFormat("[CONSENSUS-ABSTAIN] %s | All strategies abstained or filtered out", symbol);
        return TRADE_SIGNAL_NONE;
    }

    // Check ready weight ratio (minimum combined weight of voting strategies)
    // [PROFIT-09] Denominator = weight of strategies that ACTUALLY voted (via contributor index
    // arrays), not the whole roster. Adding/abstaining strategies no longer makes the gate harder.
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

    // Calculate effective quorum parameters
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

    // Determine winning side
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
        // Tie - no consensus
        PrintFormat("[CONSENSUS-TIE] %s | buyScore=%.3f sellScore=%.3f", symbol, buyScore, sellScore);
        return TRADE_SIGNAL_NONE;
    }

    // Check minimum voters
    if(winningVotes < effectiveMinVoters)
    {
        PrintFormat("[CONSENSUS-REJECT] %s | Winning votes %d < minVoters %d",
                    symbol, winningVotes, effectiveMinVoters);
        return TRADE_SIGNAL_NONE;
    }

    // Check support floor (minimum winning score relative to total)
    double totalScore = winningScore + losingScore;
    double supportRatio = (totalScore > 0) ? winningScore / totalScore : 0.0;

    if(supportRatio < supportFloor)
    {
        PrintFormat("[CONSENSUS-REJECT] %s | Support ratio %.2f < floor %.2f",
                    symbol, supportRatio, supportFloor);
        return TRADE_SIGNAL_NONE;
    }

    // Check quorum threshold
    // [PROFIT-XX] Measure quorum ratio against votes CAST, not the full assigned roster.
    // A clear single-direction winner (e.g. 1/1 or 2/2) scores 1.0 and passes, instead of
    // being diluted by silent/non-voting strategies in the per-symbol roster (e.g. 2/8 = 0.25).
    double winningQuorum = (consensusSignal == TRADE_SIGNAL_BUY) ? buyQuorum : sellQuorum;
    int totalVotesCast = buyVotes + sellVotes;
    double quorumRatio = (totalVotesCast > 0) ? (double)winningVotes / totalVotesCast : 0.0;

    if(quorumRatio < winningQuorum)
    {
        PrintFormat("[CONSENSUS-REJECT] %s | Quorum ratio %.2f < threshold %.2f",
                    symbol, quorumRatio, winningQuorum);
        return TRADE_SIGNAL_NONE;
    }

    // Check conflict deadband
    if(losingVotes > 0)
    {
        // [PROFIT-02] Measure conflict against votes CAST, not the whole roster.
        double conflictRatio = (double)losingVotes / (winningVotes + losingVotes);
        if(conflictRatio > m_src.GetConflictDeadband())
        {
            PrintFormat("[CONSENSUS-VETOED] %s | Conflict ratio %.2f > deadband %.2f",
                        symbol, conflictRatio, m_src.GetConflictDeadband());
            return TRADE_SIGNAL_NONE;
        }
    }

    // Check quality threshold
    double winningQuality = (consensusSignal == TRADE_SIGNAL_BUY) ? buyDirectionalQuality : sellDirectionalQuality;
    if(winningQuality < effectiveQualityThreshold)
    {
        PrintFormat("[CONSENSUS-REJECT] %s | Quality %.2f < threshold %.2f",
                    symbol, winningQuality, effectiveQualityThreshold);
        return TRADE_SIGNAL_NONE;
    }

    // Consensus reached!
    confluence = winningVotes;
    confidence = MathMin(0.95, winningQuality * 0.8 + supportRatio * 0.2);

    // Log consensus decision
    string decisionClass = "FULL_QUORUM";
    if(evalMode == EVAL_MODE_INTRABAR && eligibleLiveVoterCount < 3)
    {
        decisionClass = "SPARSE_INTRABAR";
    }

    PrintFormat("[CONSENSUS-DECISION] %s | %s | class=%s | conf=%.2f | confluence=%d | votes=%d/%d | support=%.2f | quorum=%.2f/%.2f",
                symbol, EnumToString(consensusSignal), decisionClass, confidence, confluence,
                buyVotes, sellVotes, supportRatio, quorumRatio, winningQuorum);

    // [BUGFIX] Populate m_lastDecisionContext for the post-consensus path.
    // Root cause: this context was NEVER written, so GetLastDecisionContext() always returned a
    // default-constructed struct (directionalQuality=0.0, decisionClass=NONE). That zeroed the
    // quality gate in ValidateSignal (0.000 < threshold -> reject) and mislabeled every decision
    // as class=NONE. We now populate it from the values just computed for this decision.
    // directionalQuality is set from the real winning directional quality (not left at struct
    // default 0.0), which keeps the adaptive quality gate meaningful.
    double totalDirScore = buyScore + sellScore;
    m_lastDecisionContext.symbol                 = symbol;
    m_lastDecisionContext.signal                 = consensusSignal;
    m_lastDecisionContext.decisionClass          = (decisionClass == "SPARSE_INTRABAR")
                                                   ? (int)CONSENSUS_DECISION_SPARSE_INTRABAR
                                                   : (int)CONSENSUS_DECISION_FULL_QUORUM;
    m_lastDecisionContext.confidence             = confidence;
    // Clamp to [0,1]: weighted directional-quality sum can exceed 1.0 for high-weight strategies,
    // but the quality gate and downstream consumers expect a normalized [0,1] score.
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

    // Performance timing log
    ulong elapsed = GetMicrosecondCount() - startTime;
    CJsonLogger::LogPerformance("EnterpriseStrategyManager", "EvaluateConsensusInternal_us", (double)elapsed, CCorrelationIdGenerator::Generate());

    return consensusSignal;
}

//+------------------------------------------------------------------+
//| Evaluate Consensus Two-Tier Internal (Probe + Full)             |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CConsensusEngine::EvaluateConsensusTwoTierInternal(const string symbol, double &confidence, int &confluence,
                                                                     ENUM_SIGNAL_EVAL_MODE evalMode)
{
    // Phase 1: Probe-only evaluation with eligible probe strategies
    // This is a fast path to check if there's enough probe support

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

        // Get raw signal without full pipeline filtering for probe
        double stratConf = 0.0;
        ENUM_TRADE_SIGNAL signal = m_src.GetStrategyPtr(i).GetSignal(stratConf);

        if(signal == TRADE_SIGNAL_BUY && stratConf >= 0.5)
            probeBuyVotes++;
        else if(signal == TRADE_SIGNAL_SELL && stratConf >= 0.5)
            probeSellVotes++;
    }

    // Quick probe check - if no probe support, don't proceed to full evaluation
    if(probeBuyVotes == 0 && probeSellVotes == 0)
    {
        PrintFormat("[CONSENSUS-PROBE] %s | No probe support (buy=%d sell=%d)", symbol, probeBuyVotes, probeSellVotes);
        confidence = 0.0;
        confluence = 0;
        return TRADE_SIGNAL_NONE;
    }

    // Phase 2: Full consensus evaluation
    ENUM_TRADE_SIGNAL result = EvaluateConsensusInternal(symbol, confidence, confluence, evalMode);

    ulong elapsed = GetMicrosecondCount() - startTime;
    CJsonLogger::LogPerformance("EnterpriseStrategyManager", "EvaluateConsensusTwoTierInternal_us", (double)elapsed, CCorrelationIdGenerator::Generate());

    return result;
}

//+------------------------------------------------------------------+
//| Evaluate Consensus Probe Only Internal (Fast Path)              |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CConsensusEngine::EvaluateConsensusProbeOnlyInternal(const string symbol, double &confidence, int &confluence,
                                                                       ENUM_SIGNAL_EVAL_MODE evalMode)
{
    // Fast probe-only evaluation - no pipeline filtering, no full quorum
    // Used for intrabar probe voting to quickly check signal direction

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

        // Get raw signal
        double stratConf = 0.0;
        ENUM_TRADE_SIGNAL signal = m_src.GetStrategyPtr(i).GetSignal(stratConf);

        if(signal == TRADE_SIGNAL_NONE || stratConf < sparseIntrabarMinQuality)
            continue;

        double weight = m_src.GetStrategyWeight(i);
        double participation = GetStrategyParticipationMultiplier(i);
        double reliability = GetStrategyReliabilityMultiplier(i);
        double score = stratConf * weight * participation * reliability;

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

    // Determine winning side
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

    // Check minimum probe support ratio
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

//+------------------------------------------------------------------+
//| Try Fallback Solo Signal Internal (When All Strategies Abstain) |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CConsensusEngine::TryFallbackSoloSignalInternal(const string symbol,
                                                                  ENUM_SIGNAL_EVAL_MODE evalMode,
                                                                  double &outConfidence,
                                                                  int &outConfluence,
                                                                  string &outReason)
{
    // This is called when all strategies abstain but pipeline is available
    // Try to find the single best strategy signal with relaxed thresholds

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

        // Get raw signal from strategy
        double stratConf = 0.0;
        ENUM_TRADE_SIGNAL signal = entryStrategy.GetSignal(stratConf);

        if(signal == TRADE_SIGNAL_NONE)
            continue;

        // Apply pipeline filtering if available (but with relaxed threshold)
        bool passedPipeline = true;
        double filteredConf = stratConf;
        ENUM_TRADE_SIGNAL filteredSignal = signal;

        if(pipeline != NULL)
        {
            filteredSignal = pipeline.ProcessSignal(entryStrategy, symbol, m_src.GetStrategyTimeframe(i), filteredConf);
            if(filteredSignal == TRADE_SIGNAL_NONE)
            {
                // For solo fallback, we allow signals that were filtered
                // but track that they were filtered
                passedPipeline = false;
            }
            else
            {
                signal = filteredSignal;
                stratConf = filteredConf;
            }
        }

        // Apply basic quality filters
        double weight = m_src.GetStrategyWeight(i);
        double participation = GetStrategyParticipationMultiplier(i);
        double reliability = GetStrategyReliabilityMultiplier(i);

        // Score = confidence * weight * participation * reliability
        double readinessScore = m_src.GetStrategyReadinessScore(i);
        double contextScore = m_src.GetStrategyContextScore(i);
        double costScore = m_src.GetStrategyCostScore(i);
        double qualityMultiplier = (readinessScore * 0.4 + contextScore * 0.4 + costScore * 0.2);
        double score = stratConf * weight * participation * reliability * qualityMultiplier;

        // Apply minimum threshold (relaxed for solo fallback)
        double minSoloConfidence = (evalMode == EVAL_MODE_INTRABAR) ? 0.70 : 0.65;
        if(stratConf < minSoloConfidence)
        {
            PrintFormat("[CONSENSUS-SOLO-SKIP] %s | %s conf=%.2f < min=%.2f",
                        symbol, m_src.GetStrategyName(i), stratConf, minSoloConfidence);
            continue;
        }

        // Boost score if signal passed pipeline
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
