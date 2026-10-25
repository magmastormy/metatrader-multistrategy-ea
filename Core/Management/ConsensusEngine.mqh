// Included only from EnterpriseStrategyManager.mqh; not usable standalone.
// SyncEnabledWithRegistry() has a live caller in EAOrchestrator.
// m_lastDecisionContext: one writer (EvaluateConsensusInternal); consumers are the post-consensus
// validator quality gate and StrategyStateReporter.
#ifndef CONSENSUS_ENGINE_MQH
#define CONSENSUS_ENGINE_MQH

#include "../Utils/Enums.mqh"                     // signal / role / cluster / intrabar enums + SConsensusDecisionContext
#include "../../Interfaces/IStrategy.mqh"         // IStrategy::GetSignal / GetType / SetEnabled
#include "../Pipeline/UnifiedSignalPipeline.mqh"  // CUnifiedSignalPipeline::ProcessSignal
#include "../Engines/RegimeEngine.mqh"             // CRegimeEngine::GetSnapshot (regime vote weighting)
#include "../Strategy/StrategyRegistry.mqh"       // CStrategyRegistry::IsStrategyActive / GetMode
#include "../Utils/JsonLogger.mqh"                // CJsonLogger, CCorrelationIdGenerator
#include "../Risk/RiskClusterCodec.mqh"           // cluster-code letter for the risk cluster gates
#include "DiagnosticsManager.mqh"                 // CDiagnosticsManager

// Minimum independent voters for an entry: a lone voter would be 100% consensus, and no quorum
// profile may lower this floor.
#ifndef MIN_CONSENSUS_VOTERS
#define MIN_CONSENSUS_VOTERS 2
#endif

class CEnterpriseStrategyManager;   // forward: held as a mutable pointer

class CConsensusEngine
{
private:
    CEnterpriseStrategyManager* m_src;

    SConsensusDecisionContext m_lastDecisionContext;

    // Per-symbol, not a function static: one shared slot would let the first symbol to dissent mute the
    // other twelve (the Batch 214 shape).
    datetime m_lastDeadbandFloorLog;

public:
    CConsensusEngine() : m_src(NULL), m_lastDeadbandFloorLog(0) {}

    void SetSource(CEnterpriseStrategyManager* src) { m_src = src; }

    // One definition of the voter floor: MIN_CONSENSUS_VOTERS binds on top of whatever the quorum config
    // holds, so a profile's 1 can never make a one-voter committee. Used by the decision and by the init
    // print, which is why it is not spelled out a second time at either call site.
    int EnforcedMinVoters(const bool intrabar) const
    {
        if(m_src == NULL)
            return MIN_CONSENSUS_VOTERS;
        return MathMax(intrabar ? m_src.GetIntrabarMinQuorum() : m_src.GetMinQuorum(), MIN_CONSENSUS_VOTERS);
    }

    // The only consensus entry point is the WithConfluenceMode variant below, called by
    // SignalGenerator, PositionLifecycleManager and TrainingDataExporter.
    ENUM_TRADE_SIGNAL GetConsensusSignalForSymbolWithConfluenceMode(const string symbol, double &confidence,
                                                                    int &confluence,
                                                                    ENUM_SIGNAL_EVAL_MODE evalMode);

    void SyncEnabledWithRegistry();

    void GetLastDecisionContextValue(SConsensusDecisionContext &out) const { out = m_lastDecisionContext; }

    bool   IsStrategyLiveVoter(const int strategyIndex) const;
    double GetRegimeCategoryMultiplier(const string symbol, ENUM_STRATEGY_TYPE strategyType) const;
    double GetStrategyReliabilityMultiplier(const int strategyIndex) const;
    double GetStrategyParticipationMultiplier(const int strategyIndex) const;
    ENUM_STRATEGY_ROLE    ResolveDominantRole(const int &strategyIndices[]) const;
    ENUM_STRATEGY_CLUSTER ResolveDominantCluster(const int &strategyIndices[]) const;

private:
    ENUM_TRADE_SIGNAL EvaluateConsensusInternal(const string symbol, double &confidence, int &confluence,
                                                ENUM_SIGNAL_EVAL_MODE evalMode);
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

// Strategies are auto-registered before CStrategyRegistry is populated, so this re-applies the
// registry's active state to the live objects.
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
    int enabledCount = 0;
    int liveVotingCount = 0;
    for(int i = 0; i < strategyCount; i++)
    {
        if(m_src.IsStrategyEnabled(i))
            enabledCount++;
        if(m_src.IsStrategyLiveVotingEnabled(i))
            liveVotingCount++;
    }

    // Prints even when synced == 0: enabled=0/m is the state an operator needs to see, and a line that
    // only appears when flags changed cannot distinguish "already correct" from "nothing is voting".
    PrintFormat("[EnterpriseStrategyManager] %s: reconciled %d strategy enable-flags with registry | enabled=%d/%d | liveVoting=%d",
                m_src.GetManagedSymbol(), synced, enabledCount, strategyCount, liveVotingCount);
}

// Regime gate values: 0.0 = category has no edge here, vote hard-disabled; 1.0 = allowed; 0.25-0.40 = strongly deweighted.
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
    // Deliberately NOT floored: any floor above zero leaves a hard-killed category still voting.
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
        return 0.0;   // EvaluateConsensusInternal reads this zero as "not a voter" and drops the vote

    // Per-category weight from the live regime composite (Hurst-blended).
    double catMult = 1.0;
    switch(strategyType)
    {
        case STRATEGY_TREND:              catMult = snap.trendWeightMult;     break;
        case STRATEGY_MOMENTUM:           catMult = snap.momentumWeightMult;  break;
        case STRATEGY_MEAN_REVERSION:     catMult = snap.meanRevWeightMult;    break;
        case STRATEGY_VOLATILITY_BREAKOUT:
        case STRATEGY_RANGE_COMPRESSION:  catMult = snap.breakoutWeightMult;   break;
        case STRATEGY_FVG_SCALPER:
        case STRATEGY_BREAKER_BLOCK:
        case STRATEGY_LIQUIDITY_SWEEP:
        case STRATEGY_TURTLE_SOUP:        catMult = snap.ictWeightMult;        break;
        // Unlisted types (AI adapters, stat-arb, S/R, candlestick, session-gap) are regime-neutral.
        default:                          catMult = 1.0;                       break;
    }

    // Chaos or regime confidence below 0.35: deweight, never hard-kill.
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

    double baseQuorumThreshold = m_src.GetQuorumThreshold();

    // Never capped by the eligible voter count: capping it made one lone voter 100% consensus.
    effectiveMinVoters = EnforcedMinVoters(evalMode == EVAL_MODE_INTRABAR);
    supportFloor = (evalMode == EVAL_MODE_INTRABAR) ? m_src.GetSupportFloorIntrabar() : m_src.GetSupportFloorNewBar();

    double pipelineConfFloor = 0.0;
    if(pipeline != NULL)
    {
        pipelineConfFloor = pipeline.GetLastEffectiveMinConfidence();
    }
    effectiveQualityThreshold = MathMax(m_src.GetPipelineMinConfidence(), pipelineConfFloor);

    double qualityAdjustmentBuy = (buyDirectionalQuality > 0.7) ? -0.05 : 0.0;
    double qualityAdjustmentSell = (sellDirectionalQuality > 0.7) ? -0.05 : 0.0;

    if(evalMode == EVAL_MODE_INTRABAR && m_src.IsIntrabarDynamicQuorumEnabled())
    {
        if(eligibleLiveVoterCount < 3)
        {
            qualityAdjustmentBuy += 0.10;
            qualityAdjustmentSell += 0.10;
        }
    }

    buyQuorum = MathMax(0.30, MathMin(0.80, baseQuorumThreshold + qualityAdjustmentBuy));
    sellQuorum = MathMax(0.30, MathMin(0.80, baseQuorumThreshold + qualityAdjustmentSell));

    // Votes are integers: the smallest conflict this gate can ever see is one dissenter out of the votes
    // cast, and EvaluateConsensusInternal floors the veto at that figure so a lower deadband cannot demand
    // unanimity. Printed beside it is what shows an operator when the floor is what binds. supportRatio
    // (winner / votes cast) is above 0.50 by construction, so a support floor at or below 0.50 refuses nothing.
    double finestDissent = (eligibleLiveVoterCount > 1) ? (1.0 / eligibleLiveVoterCount) : 1.0;
    string supportFloorNote = (supportFloor > 0.0 && supportFloor <= 0.50) ? " inert" : "";

    PrintFormat("[CONSENSUS-QUORUM] %s | mode=%s | minVoters=%d | supportFloor=%.2f%s | qualityThresh=%.2f | buyQuorum=%.2f | sellQuorum=%.2f | conflictDeadband=%.2f | finestDissent=%.3f",
                symbol,
                (evalMode == EVAL_MODE_INTRABAR ? "INTRABAR" : "NEW_BAR"),
                effectiveMinVoters, supportFloor, supportFloorNote, effectiveQualityThreshold, buyQuorum, sellQuorum,
                m_src.GetConflictDeadband(), finestDissent);
}

ENUM_TRADE_SIGNAL CConsensusEngine::EvaluateConsensusInternal(const string symbol, double &confidence, int &confluence,
                                                              ENUM_SIGNAL_EVAL_MODE evalMode)
{
    ulong startTime = GetMicrosecondCount();

    confidence = 0.0;
    confluence = 0;

    // Reset first: a stale context (signal, quality, class) must not leak into the validator.
    SConsensusDecisionContext emptyDecisionContext;
    m_lastDecisionContext = emptyDecisionContext;

    if(m_src == NULL)
        return TRADE_SIGNAL_NONE;

    m_src.RefreshMarketRegime();

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
    int regimeVetoedVotes = 0;
    double regimeVetoedWeight = 0.0;
    double buyScore = 0.0;
    double sellScore = 0.0;
    double buyDirectionalQuality = 0.0;
    double sellDirectionalQuality = 0.0;
    double buyConviction = 0.0;
    double buyReadiness = 0.0;
    double buyContext = 0.0;
    double buyCost = 0.0;
    double sellConviction = 0.0;
    double sellReadiness = 0.0;
    double sellContext = 0.0;
    double sellCost = 0.0;

    int buyContributorIndices[];
    int sellContributorIndices[];
    ArrayResize(buyContributorIndices, 0);
    ArrayResize(sellContributorIndices, 0);

    // An unconfirmed regime snapshot stands every voter aside at 0.30, which caps the ready-weight
    // ratio below any floor above 0.36. Read it once so the refusal can say which of the two it hit.
    bool regimeSnapshotConfirmed = true;
    if(pipeline != NULL)
    {
        CRegimeEngine* regimeEngine = pipeline.GetRegimeEngine(symbol);
        if(regimeEngine != NULL)
            regimeSnapshotConfirmed = regimeEngine.GetSnapshot().valid;
    }

    for(int i = 0; i < strategyCount; i++)
    {
        if(!IsStrategyLiveVoter(i))
            continue;

        eligibleLiveVoterCount++;

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

        // The composite is clamped to >= 0.01, so zero here is RegimeStateHardGate's veto. A vetoed
        // strategy must not be a voter at all: counting it feeds quorum while its weight only
        // dilutes the ready ratio.
        double regimeMult = GetRegimeCategoryMultiplier(symbol, entryStrategy.GetType());
        if(regimeMult <= 0.0)
        {
            regimeVetoedVotes++;
            regimeVetoedWeight += weight;
            continue;
        }

        double score = stratConf * weight * participation * reliability * regimeMult;

        // ProcessSignal resets then fills this for the voter it just ran, so the read is that voter's
        // own measurement. The live-authority lot ladder below is the consumer.
        SPipelineEvidenceSnapshot evidence;
        if(pipeline != NULL)
            pipeline.GetLastEvidenceSnapshot(evidence);

        if(signal == TRADE_SIGNAL_BUY)
        {
            buyVotes++;
            buyScore += score;
            buyDirectionalQuality += stratConf * weight;
            buyConviction += stratConf;
            buyReadiness += evidence.readinessScore;
            buyContext += evidence.contextScore;
            buyCost += evidence.costScore;
            int idx = ArraySize(buyContributorIndices);
            ArrayResize(buyContributorIndices, idx + 1);
            buyContributorIndices[idx] = i;
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            sellVotes++;
            sellScore += score;
            sellDirectionalQuality += stratConf * weight;
            sellConviction += stratConf;
            sellReadiness += evidence.readinessScore;
            sellContext += evidence.contextScore;
            sellCost += evidence.costScore;
            int idx = ArraySize(sellContributorIndices);
            ArrayResize(sellContributorIndices, idx + 1);
            sellContributorIndices[idx] = i;
        }
    }

    if(buyVotes > 0)
    {
        buyDirectionalQuality /= buyVotes;
        buyConviction /= buyVotes;
        buyReadiness /= buyVotes;
        buyContext /= buyVotes;
        buyCost /= buyVotes;
    }
    if(sellVotes > 0)
    {
        sellDirectionalQuality /= sellVotes;
        sellConviction /= sellVotes;
        sellReadiness /= sellVotes;
        sellContext /= sellVotes;
        sellCost /= sellVotes;
    }

    if(regimeVetoedVotes > 0)
        PrintFormat("[CONSENSUS-REGIME-VETO] %s | %d vote(s) hard-gated by regime | excluded weight %.2f | counted votes %d buy / %d sell",
                    symbol, regimeVetoedVotes, regimeVetoedWeight, buyVotes, sellVotes);

    if(buyVotes == 0 && sellVotes == 0)
    {
        PrintFormat("[CONSENSUS-ABSTAIN] %s | All strategies abstained or filtered out", symbol);
        return TRADE_SIGNAL_NONE;
    }

    // Denominator is the weight of strategies that actually voted, so abstainers cannot tighten this.
    double votedWeight = 0.0;
    for(int k = 0; k < ArraySize(buyContributorIndices); k++)
        votedWeight += m_src.GetStrategyWeight(buyContributorIndices[k]);
    for(int k = 0; k < ArraySize(sellContributorIndices); k++)
        votedWeight += m_src.GetStrategyWeight(sellContributorIndices[k]);

    double readyWeightRatio = (votedWeight > 0) ? (buyScore + sellScore) / votedWeight : 0.0;
    bool readyWeightMet = (readyWeightRatio >= m_src.GetMinReadyWeightRatio());

    if(!readyWeightMet)
    {
        PrintFormat("[CONSENSUS-REJECT] %s | Ready weight ratio %.2f < min %.2f | regime=%s",
                    symbol, readyWeightRatio, m_src.GetMinReadyWeightRatio(),
                    regimeSnapshotConfirmed ? "confirmed" : "UNCONFIRMED(stand-aside 0.30 caps ratio at 0.36)");
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

    // Quorum ratio is measured against votes cast, not the assigned roster, so non-voters cannot dilute it.
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
        double totalVotesCastForConflict = winningVotes + losingVotes;
        double conflictRatio = (totalVotesCastForConflict > 0) ? (double)losingVotes / totalVotesCastForConflict : 0.0;
        // Votes are integers, so the smallest conflict a scan can express is one dissenter out of the votes
        // cast. A deadband under that figure is not a tight tolerance, it is a unanimity requirement: on this
        // roster 1/19 = 0.053 and the live chart input is 0.05, so every single dissent vetoed. The floor
        // removes exactly that - one dissenter can never veto - and leaves 2+ dissenters under the
        // operator's own deadband.
        double finestDissent = (totalVotesCastForConflict > 1) ? (1.0 / totalVotesCastForConflict) : 1.0;
        double askedDeadband = m_src.GetConflictDeadband();
        double effectiveDeadband = MathMax(askedDeadband, finestDissent);
        if(conflictRatio > effectiveDeadband)
        {
            PrintFormat("[CONSENSUS-VETOED] %s | Conflict ratio %.2f > deadband %.2f | votes %d-%d",
                        symbol, conflictRatio, effectiveDeadband, winningVotes, losingVotes);
            return TRADE_SIGNAL_NONE;
        }
        if(effectiveDeadband > askedDeadband && TimeCurrent() - m_lastDeadbandFloorLog >= 300)
        {
            m_lastDeadbandFloorLog = TimeCurrent();
            PrintFormat("[CONSENSUS-DEADBAND-FLOORED] %s | asked=%.3f enforced=%.3f | votes %d-%d | a deadband under 1/votes_cast demands unanimity",
                        symbol, askedDeadband, effectiveDeadband, winningVotes, losingVotes);
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

    // Publish the winning voters. Attribution, AI-authority outcome learning, the candidate's
    // role/cluster tags and per-strategy health all read this context, and until now none of
    // them ever received a contributor.
    int winningContributors[];
    if(consensusSignal == TRADE_SIGNAL_BUY)
        ArrayCopy(winningContributors, buyContributorIndices);
    else
        ArrayCopy(winningContributors, sellContributorIndices);

    ENUM_STRATEGY_CLUSTER dominantCluster = ResolveDominantCluster(winningContributors);
    string dominantClusterTag = StrategyClusterToString(dominantCluster);
    m_src.SetLastSignalContributors(winningContributors,
                                    StrategyRoleToString(ResolveDominantRole(winningContributors)),
                                    dominantClusterTag,
                                    CRiskClusterCodec::NormalizeClusterCode(dominantClusterTag));

    // The validator reads directionalQuality off this context; a default struct would zero it.
    double totalDirScore = buyScore + sellScore;
    m_lastDecisionContext.symbol                 = symbol;
    m_lastDecisionContext.signal                 = consensusSignal;
    m_lastDecisionContext.decisionClass          = (decisionClass == "SPARSE_INTRABAR")
                                                   ? (int)CONSENSUS_DECISION_SPARSE_INTRABAR
                                                   : (int)CONSENSUS_DECISION_FULL_QUORUM;
    m_lastDecisionContext.confidence             = confidence;
    // Clamped to [0,1]: the weighted sum can exceed 1.0, but the quality gate expects a normalized score.
    m_lastDecisionContext.directionalQuality     = MathMax(0.0, MathMin(1.0, winningQuality));
    // Mean over the winning side's voters, from each voter's own pipeline evidence.
    const bool winningWasBuy = (consensusSignal == TRADE_SIGNAL_BUY);
    m_lastDecisionContext.convictionScore        = winningWasBuy ? buyConviction : sellConviction;
    m_lastDecisionContext.readinessScore         = winningWasBuy ? buyReadiness  : sellReadiness;
    m_lastDecisionContext.contextScore           = winningWasBuy ? buyContext    : sellContext;
    m_lastDecisionContext.costScore              = winningWasBuy ? buyCost       : sellCost;
    m_lastDecisionContext.readyLiveWeight        = buyScore + sellScore;
    m_lastDecisionContext.totalLiveWeight        = votedWeight;
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
    // Resolved above for the contributor publish. The mean-reversion R:R floor in the candidate builder and the
    // structural-invalidation exit in the lifecycle manager both read it off this context, so leaving it at
    // STRATEGY_CLUSTER_NONE kept both branches unreachable.
    m_lastDecisionContext.dominantCluster        = dominantCluster;

    ulong elapsed = GetMicrosecondCount() - startTime;
    CJsonLogger::LogPerformance("EnterpriseStrategyManager", "EvaluateConsensusInternal_us", (double)elapsed, CCorrelationIdGenerator::Generate());

    return consensusSignal;
}

#endif // CONSENSUS_ENGINE_MQH
