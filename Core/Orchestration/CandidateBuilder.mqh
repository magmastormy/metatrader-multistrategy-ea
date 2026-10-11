// Builds trade candidates from validated signals
#property strict

#ifndef CORE_ORCHESTRATION_CANDIDATE_BUILDER_MQH
#define CORE_ORCHESTRATION_CANDIDATE_BUILDER_MQH

#include "../../Core/Management/EnterpriseStrategyManager.mqh"
#include "../../Core/Risk/UnifiedRiskManager.mqh"
#include "../../Core/Risk/PositionSizer.mqh"
#include "../Risk/RiskTierManager.mqh"
#include "../Risk/CompoundingTierManager.mqh"
#include "../../Core/Engines/FamilyStrategyWeightMatrix.mqh"
#include "../../Core/Engines/SessionWeightManager.mqh"
#include "../../Core/Engines/SkewStepAnalyzer.mqh"
#include "../../Core/Utils/Enums.mqh"
#include "../../Core/Utils/JsonLogger.mqh"
#include "../../Core/Utils/Instruments.mqh"

// Trade candidate structure - global for cross-class usage
struct STradeCandidate
{
    string symbol;
    ENUM_ORDER_TYPE orderType;
    double entryPrice;
    double stopLossPips;
    double takeProfitPips;
    double lotSize;
    double riskPercent;
    double confidence;
    int confluence;  // Added for authority resolution
    string strategy;
    string reasoning;
    string strategyRole;
    string strategyCluster;
    string contributorSummary;
    string clusterCode;
    datetime requestTime;
    double qualityScore;
    double convictionScore;
    double readinessScore;
    double contextScore;
    double costScore;
    double liveAuthorityRiskMult;
    string liveAuthorityReason;
    bool liveAuthorityAllowed;
    bool hasAIContributor;
    bool hasONNXContributor;
    bool hasIndicatorContributor;
    int indicatorContributorCount;
    string predictionId;  // For linking trade outcome to NN training (L11-014)
    
    STradeCandidate() : symbol(""), orderType(ORDER_TYPE_BUY), entryPrice(0), stopLossPips(0),
                       takeProfitPips(0), lotSize(0), riskPercent(0), confidence(0),
                       confluence(0), qualityScore(0), convictionScore(0), readinessScore(0), contextScore(0),
                       costScore(0), liveAuthorityRiskMult(1.0),
                       liveAuthorityAllowed(false), hasAIContributor(false), hasONNXContributor(false),
                       hasIndicatorContributor(false), indicatorContributorCount(0),
                       predictionId("") {}
};

class CCandidateBuilder
{
private:
    CUnifiedRiskManager*        m_riskManager;
    CPositionSizer*             m_positionSizer;
    CTradeManager*              m_tradeManager;
    CPerformanceAnalytics*      m_performanceAnalytics;
    CDerivAssetProfiler*        m_derivProfiler;
    
    // Additional managers from EAOrchestrator Initialize call
    CRiskTierManager*           m_riskTierManager;
    CCompoundingTierManager*    m_compoundingTierManager;
    CFamilyStrategyWeightMatrix* m_familyWeightMatrix;
    CSessionWeightManager*      m_sessionWeightManager;
    CSkewStepAnalyzer*          m_skewStepAnalyzer;
    
    // Config
    double                      m_minRRDefault;
    double                      m_minRRMeanReversion;
    double                      m_maxRiskPerTrade;
    double                      m_maxSpreadToTpRatio;
    double                      m_minLotRiskMultiplier;
    double                      m_aiDrawdownSizingLimit;
    bool                        m_antiMartingaleEnabled;
    int                         m_maxPositionsPerSymbol;
    int                         m_portfolioMaxPositionsPerSymbol;
    
    // Cluster-specific minRR
    double                      m_minRRByCluster[];
    
        int                         m_hybridGateRelaxAfterCycles;
        double                      m_aiStandaloneMinConfidence;
        double                      m_aiStandaloneRelaxedConfidence;
        // Per-symbol cycle tracking for hybrid gate relaxation
        string                      m_symbolCyclesSinceIndicator[];
        int                         m_symbolCyclesSinceIndicatorValues[];
        int                         m_symbolCycleCount;
        // Per-symbol hybrid gate relaxed state (L3-014 fix)
        string                      m_symbolHybridGateRelaxedKeys[];
        bool                        m_symbolHybridGateRelaxedValues[];
        int                         m_symbolHybridGateRelaxedCount;
    
    // Helper: check if contributors include indicator strategies
    bool ContributorsIncludeIndicator(const string &contributors[])
    {
        for(int i = 0; i < ArraySize(contributors); i++)
        {
            string c = contributors[i];
            if(StringFind(c, "Momentum") >= 0 || StringFind(c, "Trend") >= 0 ||
               StringFind(c, "Support") >= 0 || StringFind(c, "Resistance") >= 0 ||
               StringFind(c, "ICT") >= 0 || StringFind(c, "Candlestick") >= 0 ||
               StringFind(c, "Unicorn") >= 0 || StringFind(c, "PowerOfThree") >= 0 ||
               StringFind(c, "MeanReversion") >= 0 || StringFind(c, "Volatility") >= 0 ||
               StringFind(c, "StatArb") >= 0 || StringFind(c, "FVG") >= 0 ||
               StringFind(c, "Turtle") >= 0 || StringFind(c, "Breaker") >= 0 ||
               StringFind(c, "NYOpen") >= 0 || StringFind(c, "AsianRange") >= 0)
                return true;
        }
        return false;
    }
    
    // Helper: count indicator contributors
    int CountIndicatorContributors(const string &contributors[])
    {
        int count = 0;
        for(int i = 0; i < ArraySize(contributors); i++)
        {
            string c = contributors[i];
            if(StringFind(c, "Momentum") >= 0 || StringFind(c, "Trend") >= 0 ||
               StringFind(c, "Support") >= 0 || StringFind(c, "Resistance") >= 0 ||
               StringFind(c, "ICT") >= 0 || StringFind(c, "Candlestick") >= 0 ||
               StringFind(c, "Unicorn") >= 0 || StringFind(c, "PowerOfThree") >= 0 ||
               StringFind(c, "MeanReversion") >= 0 || StringFind(c, "Volatility") >= 0 ||
               StringFind(c, "StatArb") >= 0 || StringFind(c, "FVG") >= 0 ||
               StringFind(c, "Turtle") >= 0 || StringFind(c, "Breaker") >= 0 ||
               StringFind(c, "NYOpen") >= 0 || StringFind(c, "AsianRange") >= 0)
                count++;
        }
        return count;
    }

    // Helper: Get cycles since indicator signal for a specific symbol
    int GetCyclesSinceIndicatorSignal(const string &symbol)
    {
        for(int i = 0; i < m_symbolCycleCount; i++)
        {
            if(m_symbolCyclesSinceIndicator[i] == symbol)
                return m_symbolCyclesSinceIndicatorValues[i];
        }
        return 0; // Not found, return 0
    }

    // Helper: Set cycles since indicator signal for a specific symbol
    void SetCyclesSinceIndicatorSignal(const string &symbol, int cycles)
    {
        // Find existing entry
        for(int i = 0; i < m_symbolCycleCount; i++)
        {
            if(m_symbolCyclesSinceIndicator[i] == symbol)
            {
                m_symbolCyclesSinceIndicatorValues[i] = cycles;
                return;
            }
        }
        // Add new entry if space available
        if(m_symbolCycleCount < ArraySize(m_symbolCyclesSinceIndicator))
        {
            m_symbolCyclesSinceIndicator[m_symbolCycleCount] = symbol;
            m_symbolCyclesSinceIndicatorValues[m_symbolCycleCount] = cycles;
            m_symbolCycleCount++;
        }
        // If array is full, we could implement LRU eviction, but for now just skip
    }

    // Helper: Increment cycles since indicator signal for a specific symbol
    void IncrementCyclesSinceIndicatorSignal(const string &symbol)
    {
        int currentCycles = GetCyclesSinceIndicatorSignal(symbol);
        SetCyclesSinceIndicatorSignal(symbol, currentCycles + 1);
    }

    // Helper: Get hybrid gate relaxed state for a specific symbol
    bool GetHybridGateRelaxed(const string &symbol)
    {
        for(int i = 0; i < m_symbolHybridGateRelaxedCount; i++)
        {
            if(m_symbolHybridGateRelaxedKeys[i] == symbol)
                return m_symbolHybridGateRelaxedValues[i];
        }
        return false; // Not found, default to false
    }

    // Helper: Set hybrid gate relaxed state for a specific symbol
    void SetHybridGateRelaxed(const string &symbol, bool relaxed)
    {
        // Find existing entry
        for(int i = 0; i < m_symbolHybridGateRelaxedCount; i++)
        {
            if(m_symbolHybridGateRelaxedKeys[i] == symbol)
            {
                m_symbolHybridGateRelaxedValues[i] = relaxed;
                return;
            }
        }
        // Add new entry if space available
        if(m_symbolHybridGateRelaxedCount < ArraySize(m_symbolHybridGateRelaxedKeys))
        {
            m_symbolHybridGateRelaxedKeys[m_symbolHybridGateRelaxedCount] = symbol;
            m_symbolHybridGateRelaxedValues[m_symbolHybridGateRelaxedCount] = relaxed;
            m_symbolHybridGateRelaxedCount++;
        }
    }

    // Batch 173: a symbol that repeatedly lands under SYMBOL_VOLUME_MIN after a shrink looks merely
    // quiet in the log. These counters carry it into the periodic status report as a refusal count.
    string m_authorityBlockSymbols[];
    int    m_authorityBlockCounts[];
    int    m_authorityBlockedTotal;
    // Kept separately because GetStatusReport() is const and ArraySize() binds its argument by
    // reference, so the const path cannot ask the array how long it is.
    int    m_authorityBlockSymbolsCount;

    int NoteAuthorityBlock(const string symbol)
    {
        for(int i = 0; i < m_authorityBlockSymbolsCount; i++)
        {
            if(m_authorityBlockSymbols[i] == symbol)
            {
                m_authorityBlockCounts[i]++;
                return m_authorityBlockCounts[i];
            }
        }
        int n = m_authorityBlockSymbolsCount;
        ArrayResize(m_authorityBlockSymbols, n + 1);
        ArrayResize(m_authorityBlockCounts, n + 1);
        m_authorityBlockSymbols[n] = symbol;
        m_authorityBlockCounts[n] = 1;
        m_authorityBlockSymbolsCount = n + 1;
        return 1;
    }

public:
    CCandidateBuilder() : 
            m_riskManager(NULL), m_positionSizer(NULL), m_tradeManager(NULL),
            m_performanceAnalytics(NULL), m_derivProfiler(NULL),
            m_minRRDefault(2.0), m_minRRMeanReversion(1.5), m_maxRiskPerTrade(5.0),
            m_maxSpreadToTpRatio(0.15), m_minLotRiskMultiplier(1.5),
            m_aiDrawdownSizingLimit(0.2), m_antiMartingaleEnabled(true),
            m_maxPositionsPerSymbol(0), m_portfolioMaxPositionsPerSymbol(0),
            m_hybridGateRelaxAfterCycles(5), m_aiStandaloneMinConfidence(0.65),
                m_aiStandaloneRelaxedConfidence(0.65), m_symbolCycleCount(0),
                m_symbolHybridGateRelaxedCount(0),
                m_riskTierManager(NULL), m_compoundingTierManager(NULL),
                m_familyWeightMatrix(NULL), m_sessionWeightManager(NULL),
                m_skewStepAnalyzer(NULL), m_authorityBlockedTotal(0), m_authorityBlockSymbolsCount(0)
            {
            ArrayResize(m_minRRByCluster, 10);
            ArrayInitialize(m_minRRByCluster, 2.0);
            // Cluster-specific overrides
            m_minRRByCluster[MEAN_REVERSION_CLUSTER] = 1.5;
        
            // Initialize per-symbol cycle tracking arrays
            ArrayResize(m_symbolCyclesSinceIndicator, 50);
            ArrayResize(m_symbolCyclesSinceIndicatorValues, 50);
            for(int _i = 0; _i < 50; _i++)
            {
                m_symbolCyclesSinceIndicator[_i] = "";
                m_symbolCyclesSinceIndicatorValues[_i] = 0;
            }

            // Initialize per-symbol hybrid gate relaxed state arrays (L3-014 fix)
            ArrayResize(m_symbolHybridGateRelaxedKeys, 50);
            ArrayResize(m_symbolHybridGateRelaxedValues, 50);
            for(int _j = 0; _j < 50; _j++)
            {
                m_symbolHybridGateRelaxedKeys[_j] = "";
                m_symbolHybridGateRelaxedValues[_j] = false;
            }
        }
    
    
    // Batch 173: the live-authority ladder now sets the shipped lot. It is shrink-only by
    // construction - the score ladder tops out at 1.0 and both the bootstrap cap and the
    // PROVEN_AI floor can only pull it down - so no candidate can be sized larger than the risk
    // manager approved.
    //
    // Floor to SYMBOL_VOLUME_STEP by hand rather than calling CPositionSizer::NormalizeVolume:
    // that helper clamps UP to SYMBOL_VOLUME_MIN, which would return the entire reduction and
    // leave the gate logging a shrink that never happened. A lot that lands under the broker
    // minimum is therefore refused, and the refusal is loud and counted.
    //
    // Returns false when the candidate must not be sent.
    bool ScaleLotByLiveAuthority(STradeCandidate &candidate, const double riskMult, const string corrId)
    {
        string symbol = candidate.symbol;
        double baseLot = candidate.lotSize;
        if(baseLot <= 0.0)
            return false;

        if(riskMult >= 1.0)
            return true;

        if(riskMult <= 0.0)
        {
            NoteAuthorityBlock(symbol);
            m_authorityBlockedTotal++;
            PrintFormat("[AUTHORITY-REJECT] %s | live-authority multiplier arrived as %.4f, which is not a valid scale | trade refused rather than sent unscaled | reason=%s",
                        symbol, riskMult, candidate.liveAuthorityReason);
            CJsonLogger::LogRiskEvent("AuthorityReject", symbol, "AUTHORITY_MULT_INVALID",
                                      "Live authority multiplier <= 0; candidate not sent", baseLot, riskMult, corrId);
            return false;
        }

        double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double scaled = baseLot * riskMult;
        if(step > 0.0)
            scaled = NormalizeDouble((long)MathFloor(scaled / step + 1e-9) * step, 8);

        if(scaled < minLot)
        {
            int symbolBlocks = NoteAuthorityBlock(symbol);
            m_authorityBlockedTotal++;
            PrintFormat("[AUTHORITY-REJECT] %s | authority mult=%.2f sizes the trade %.4f below broker min %.4f | REFUSED, not rounded up | reason=%s | symbol_refusals=%d session_total=%d",
                        symbol, riskMult, scaled, minLot, candidate.liveAuthorityReason,
                        symbolBlocks, m_authorityBlockedTotal);
            PrintFormat("[AUTHORITY-REJECT] %s | this symbol is dark at the current authority level; it returns only when the stop widens, equity grows, or the AUTHORITY_MIN_* floors / ladder rungs are revisited",
                        symbol);
            CJsonLogger::LogRiskEvent("AuthorityReject", symbol, "AUTHORITY_LOT_BELOW_MIN",
                                      StringFormat("scaled %.4f < broker min %.4f at mult %.2f", scaled, minLot, riskMult),
                                      baseLot, scaled, corrId);
            return false;
        }

        if(scaled < baseLot)
        {
            double newRiskPct = candidate.riskPercent * (scaled / baseLot);
            PrintFormat("[AUTHORITY-REDUCED] %s | mult=%.2f | lot %.4f->%.4f | risk %.3f%%->%.3f%% | reason=%s",
                        symbol, riskMult, baseLot, scaled, candidate.riskPercent, newRiskPct,
                        candidate.liveAuthorityReason);
            CJsonLogger::LogInfo("AuthorityDecision",
                                 StringFormat("AUTHORITY_REDUCED symbol=%s mult=%.2f lot=%.4f->%.4f", symbol, riskMult, baseLot, scaled),
                                 corrId);
            // Booked risk has to follow the lot: EAOrchestrator feeds candidate.riskPercent into
            // RegisterExecutedTradeRisk, so leaving it at the pre-shrink value would charge the
            // daily entry budget for risk the position never took.
            candidate.riskPercent = newRiskPct;
            candidate.lotSize = scaled;
        }
        return true;
    }

    int GetAuthorityBlockedTotal() const { return m_authorityBlockedTotal; }

    void SetDependencies(CUnifiedRiskManager* risk, CPositionSizer* sizer, CTradeManager* trade,
                         CPerformanceAnalytics* perf, CDerivAssetProfiler* derivProf)
    {
        m_riskManager = risk;
        m_positionSizer = sizer;
        m_tradeManager = trade;
        m_performanceAnalytics = perf;
        m_derivProfiler = derivProf;
    }
    
    // Initialize with all dependencies from EAOrchestrator (7 parameters)
    bool Initialize(CPositionSizer* sizer, CUnifiedRiskManager* risk,
                    CRiskTierManager* riskTierMgr, CCompoundingTierManager* compoundingTierMgr,
                    CFamilyStrategyWeightMatrix* familyWeightMatrix,
                    CSessionWeightManager* sessionWeightMgr,
                    CSkewStepAnalyzer* skewStepAnalyzer)
    {
        m_positionSizer = sizer;
        m_riskManager = risk;
        m_riskTierManager = riskTierMgr;
        m_compoundingTierManager = compoundingTierMgr;
        m_familyWeightMatrix = familyWeightMatrix;
        m_sessionWeightManager = sessionWeightMgr;
        m_skewStepAnalyzer = skewStepAnalyzer;
        return true;
    }
    
    void Configure(double minRRDefault, double minRRMeanRev, double maxRiskPerTrade,
                   double maxSpreadTpRatio, double minLotRiskMult, double aiDDSizingLimit,
                   bool antiMartingale, int maxPosPerSymbol, int portfolioMaxPosPerSymbol,
                   int hybridRelaxCycles, double aiStandaloneConf, double aiRelaxedConf)
    {
        m_minRRDefault = minRRDefault;
        m_minRRMeanReversion = minRRMeanRev;
        m_maxRiskPerTrade = maxRiskPerTrade;
        m_maxSpreadToTpRatio = maxSpreadTpRatio;
        m_minLotRiskMultiplier = minLotRiskMult;
        m_aiDrawdownSizingLimit = aiDDSizingLimit;
        m_antiMartingaleEnabled = antiMartingale;
        m_maxPositionsPerSymbol = maxPosPerSymbol;
        m_portfolioMaxPositionsPerSymbol = portfolioMaxPosPerSymbol;
        m_hybridGateRelaxAfterCycles = hybridRelaxCycles;
        m_aiStandaloneMinConfidence = aiStandaloneConf;
        m_aiStandaloneRelaxedConfidence = aiRelaxedConf;
    }
    
    // Build candidate from validated signal
        bool BuildCandidate(const string symbol, ENUM_TRADE_SIGNAL signal, double confidence,
                            int confluence, const SConsensusDecisionContext& ctx,
                            CEnterpriseStrategyManager* manager, ulong scanCycleId,
                            STradeCandidate &candidate, const string corrId = "")
    {
        if(signal == TRADE_SIGNAL_NONE) return false;
        
        candidate.symbol = symbol;
        candidate.orderType = (signal == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        candidate.confidence = confidence;
        candidate.qualityScore = ctx.directionalQuality;
        candidate.convictionScore = ctx.convictionScore;
        candidate.readinessScore = ctx.readinessScore;
        candidate.contextScore = ctx.contextScore;
        candidate.costScore = ctx.costScore;
        candidate.requestTime = TimeCurrent();
        
        // Get execution context from manager
        string roleTag = "PRIMARY_ALPHA", clusterTag = "NONE", clusterCode = "N", contribSummary = "";
        string contributorsList[];
        manager.GetLastSignalExecutionContext(roleTag, clusterTag, clusterCode, contribSummary);
        manager.GetLastSignalContributors(contributorsList);
        
        candidate.strategyRole = roleTag;
        candidate.strategyCluster = clusterTag;
        candidate.clusterCode = clusterCode;
        candidate.contributorSummary = contribSummary;
        
        candidate.hasAIContributor = ContributorsIncludeAI(contributorsList);
        candidate.hasONNXContributor = ContributorsIncludeONNX(contributorsList);
        candidate.hasIndicatorContributor = ContributorsIncludeIndicator(contributorsList);
        candidate.indicatorContributorCount = CountIndicatorContributors(contributorsList);
        
        // Handle hybrid gate relaxation (L3-014: per-symbol tracking)
                        int cyclesSinceIndicator = GetCyclesSinceIndicatorSignal(symbol);
                        bool hybridGateRelaxed = GetHybridGateRelaxed(symbol);

                        if(candidate.hasIndicatorContributor)
                                                {
                                                    if(hybridGateRelaxed)
                                                    {
                                                        // Log with correlation ID
                                                        if(corrId != "")
                                                        {
                                                            CJsonLogger::LogInfo("CANDIDATE_BUILDER", "Hybrid gate restored - indicator signal detected", "HYBRID_GATE_RESTORED", symbol, corrId, 
                                                                "{\"threshold\":" + DoubleToString(m_aiStandaloneMinConfidence, 3) + "}");
                                                        }
                                                        PrintFormat("[HYBRID-GATE-RESTORED] %s | Indicator signal detected, AI threshold restored to %.3f",
                                                                    symbol, m_aiStandaloneMinConfidence);
                                                    }
                                                    SetCyclesSinceIndicatorSignal(symbol, 0);
                                                    SetHybridGateRelaxed(symbol, false);
                                                }
                                                else if(cyclesSinceIndicator > m_hybridGateRelaxAfterCycles && !hybridGateRelaxed)
                                                {
                                                    SetHybridGateRelaxed(symbol, true);
                                                    // Log with correlation ID
                                                    if(corrId != "")
                                                    {
                                                        CJsonLogger::LogInfo("CANDIDATE_BUILDER", "Hybrid gate relaxed - no indicator signals", "HYBRID_GATE_RELAXED", symbol, corrId, 
                                                            "{\"cycles\":" + IntegerToString(cyclesSinceIndicator) + ",\"threshold_from\":" + DoubleToString(m_aiStandaloneMinConfidence, 3) + ",\"threshold_to\":" + DoubleToString(m_aiStandaloneRelaxedConfidence, 3) + "}");
                                                    }
                                                    PrintFormat("[HYBRID-GATE-RELAXED] %s | No indicator signals for %d cycles, AI threshold %.3f -> %.3f",
                                                                symbol, cyclesSinceIndicator, m_aiStandaloneMinConfidence, m_aiStandaloneRelaxedConfidence);
                                                }
        
                // Increment cycle counter for this symbol if no indicator signal
                if(!candidate.hasIndicatorContributor)
                {
                    IncrementCyclesSinceIndicatorSignal(symbol);
                }

        // Batch 174: the EA-mode admission stub here was deleted. It returned true with a zero
        // confidence bonus for every candidate, so the rejection branch and the bonus were both
        // unreachable. CLiveAuthorityResolver owns mode admission (INDICATOR_ONLY / AI_ONLY
        // vetoes) and runs after this point.
        
        candidate.entryPrice = (signal == TRADE_SIGNAL_BUY) 
            ? SymbolInfoDouble(symbol, SYMBOL_ASK) 
            : SymbolInfoDouble(symbol, SYMBOL_BID);
        
        if(candidate.entryPrice <= 0)
            return false;
        
        // Calculate SL/TP
        // FINDING 0 (STRATEGY_AUDIT_2026-08-14): when InpUseStrategyStops is
        // enabled, prefer the consensus strategy's designed SL/TP (pips) over the
        // generic fallback. Now ENABLED for LIVE (shadow mode removed 2026-08-14);
        // the generic fallback only applies when no consensus proposal exists.
        double propSL = 0.0, propTP = 0.0;
        bool useStratStops = (::InpUseStrategyStops) && manager.GetConsensusProposedStops(signal, propSL, propTP);
        if(!CalculateStops(symbol, signal, candidate, ctx, useStratStops, propSL, propTP))
            return false;
        
        if(!CheckExecutionCost(symbol, candidate))
            return false;
        
        if(!CheckAccountCapacity(symbol, candidate))
            return false;
        
        // Determine risk
        double requestedRisk = m_riskManager.GetActiveRiskPerTradePercent();
        if(requestedRisk <= 0) requestedRisk = m_maxRiskPerTrade;
        
        double proposedRisk = m_riskManager.GetRecommendedRiskPerTradePercent(requestedRisk);
        if(proposedRisk <= 0)
        {
            PrintFormat("[CANDIDATE-BUILDER] %s | risk capped to 0", symbol);
            return false;
        }
        
        if(!ResolveLiveAuthority(symbol, candidate, proposedRisk))
            return false;
        
        if(!CheckSymbolPositionLimit(symbol, candidate))
            return false;
        
        // Final risk validation with minimum lot
        STradeValidationRequest tradeReq;
        tradeReq.symbol = symbol;
        tradeReq.orderType = candidate.orderType;
        tradeReq.lotSize = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        tradeReq.stopLossPips = candidate.stopLossPips;
        tradeReq.takeProfitPips = candidate.takeProfitPips;
        tradeReq.confidence = candidate.confidence;
        tradeReq.strategy = "EnterpriseConsensus";
        tradeReq.reasoning = candidate.reasoning;
        tradeReq.strategyRole = roleTag;
        tradeReq.strategyCluster = clusterTag;
        tradeReq.contributorContext = contribSummary;
        tradeReq.clusterCode = clusterCode;
        tradeReq.requestTime = TimeCurrent();
        
        SValidationResult riskResult;
        riskResult = m_riskManager.ValidateTradeRequest(tradeReq, "pre-size", corrId);
        if(!riskResult.approved)
            return false;
        
        // Calculate final lot size
                double lotSize = m_positionSizer.CalculatePositionSizeWithRisk(symbol, 
                                                                                candidate.stopLossPips, 
                                                                                proposedRisk, 
                                                                                candidate.confidence);
        
                // Cap for daily budget
                double remainingDailyRisk = m_riskManager.GetRemainingDailyRiskPercent();
                if(lotSize > 0 && remainingDailyRisk > 0 && proposedRisk > 0)
                {
                    lotSize = m_positionSizer.CapLotForDailyBudget(symbol, candidate.orderType, lotSize,
                                                                    candidate.stopLossPips, proposedRisk,
                                                                    remainingDailyRisk, 0.30);
                }
        
        if(lotSize <= 0)
        {
            PrintFormat("[CANDIDATE-BUILDER] %s | position sizer returned 0 lot", symbol);
            return false;
        }
        
        // Batch 170 and 174 removed five `return lotSize;` stubs from this chain
        // (VPIN scaling, volatility targeting, skew step, full margin, safe mode). Each sat under a
        // comment claiming it resized the lot while returning its input untouched. VPIN acts on size
        // through CVPINLotModifier in the sizer chain and vetoes through CPostConsensusValidator;
        // skew step, full margin and safe mode have no size hook and are tracked as open work.
        lotSize = ApplyDrawdownScaling(symbol, lotSize, proposedRisk);
        lotSize = ApplyMomentumScaling(symbol, lotSize);
        // Floor at broker minimum. The post-size re-gate below measures the risk this round-up
        // creates and refuses the candidate when it crosses the per-trade cap.
        double brokerMinLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        if(lotSize < brokerMinLot)
            lotSize = brokerMinLot;
        
        candidate.lotSize = lotSize;

        // Batch 152: post-size re-gate. The pre-size validation ran at broker-minimum
        // lot; the shipped lot is the product of the sizing modifiers below and can
        // carry several times the proposed risk with no gate behind it.
        double finalTradeRisk = m_riskManager.CalculateTradeRisk(symbol, candidate.lotSize, candidate.stopLossPips);
        double riskDenom = CRiskMath::GetRiskDenominator();
        double finalRiskPct = (finalTradeRisk > 0.0 && riskDenom > 0.0) ? (finalTradeRisk / riskDenom) * 100.0 : proposedRisk;
        double riskCap = m_riskManager.GetEffectiveRiskPerTrade(symbol);
        if(riskCap <= 0.0)
        {
            // Kill-switch: risk is disabled for this symbol — do not trade.
            PrintFormat("[RISK-GATE-REJECT] %s | reason=risk_disabled | cap=%.2f%%", symbol, riskCap);
            return false;
        }
        if(finalRiskPct > riskCap)
        {
            // Post-size re-gate (Batch 152): the sizing modifiers below can push the
            // shipped lot above the per-trade risk cap. Rejecting the whole candidate
            // discards a valid signal and starves the basket (defeats the multi-strategy
            // mandate). Instead CLAMP the lot so the realized risk equals the cap and let
            // the trade proceed — risk compliance is preserved, trade frequency is not.
            double compliantLot = candidate.lotSize * (riskCap / finalRiskPct);
            double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
            if(stepLot > 0.0)
                compliantLot = NormalizeDouble((long)MathFloor(compliantLot / stepLot + 1e-9) * stepLot, 8);
            double brokerMinLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
            if(compliantLot < brokerMinLot)
            {
                // No compliant size exists: the smallest lot the broker accepts already carries
                // more than the cap. Rounding up here used to ship the over-risk trade while
                // booking riskPercent at the cap, so the daily budget charged less than the
                // position could lose. Refuse instead, same rule as the authority shrink below.
                PrintFormat("[RISK-GATE-REJECT] %s | reason=compliant_lot_below_min | needed=%.4f | broker_min=%.4f | risk=%.3f%% | cap=%.3f%%",
                            symbol, compliantLot, brokerMinLot, finalRiskPct, riskCap);
                CJsonLogger::LogRiskEvent("RiskGateReject", symbol, "COMPLIANT_LOT_BELOW_MIN",
                    StringFormat("Lot needed to meet cap %.4f < broker min %.4f at risk %.3f%% vs cap %.3f%%",
                                 compliantLot, brokerMinLot, finalRiskPct, riskCap),
                    compliantLot, brokerMinLot, corrId);
                return false;
            }
            PrintFormat("[RISK-GATE-CLAMP] %s | final_lot=%.4f -> %.4f | risk=%.3f%% -> cap=%.3f%%",
                        symbol, lotSize, compliantLot, finalRiskPct, riskCap);
            candidate.lotSize = compliantLot;
            // Floor-to-step makes the real risk equal to or under the cap, so booking the cap is
            // conservative rather than false.
            finalRiskPct = riskCap;
        }
        candidate.riskPercent = finalRiskPct;
        
        // Build reasoning
        candidate.reasoning = StringFormat("role=%s | cluster=%s | contributors=%s | conviction=%.2f | readiness=%.2f | context=%.2f | cost=%.2f",
                                           roleTag, clusterTag, contribSummary,
                                           ctx.convictionScore, ctx.readinessScore, ctx.contextScore, ctx.costScore);
        
        // Batch 151: removed the second IncrementCyclesSinceIndicatorSignal() here -
        // it double-counted every successful build (the increment at the hybrid-gate
        // block above already ran), relaxing the AI threshold at 2x speed.

        return true;
    }
    
    // === Helper methods ===
    
    bool CalculateStops(const string symbol, ENUM_TRADE_SIGNAL signal, STradeCandidate &candidate,
                        const SConsensusDecisionContext& ctx,
                        bool useStrategyStops = false, double proposedSL = 0.0, double proposedTP = 0.0)
    {
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(point <= 0) point = 0.00001;
        
        bool isSynthetic = IsSyntheticIndexSymbolName(symbol);

        // Determine minRR based on cluster (needed before any stop branch)
        double minRR = m_minRRDefault;
        if(ctx.dominantCluster == MEAN_REVERSION_CLUSTER)
            minRR = m_minRRMeanReversion;
        
        // Get ATR from pipeline (currently wired to NULL/0 in this build)
        CUnifiedSignalPipeline* pipeline = NULL; // Would be passed in real implementation
        double atrValue = 0;
        
        double stopLossPips = 0;
        double takeProfitPips = 0;

        // FINDING 0 (STRATEGY_AUDIT_2026-08-14): use the consensus strategy's
        // designed SL/TP when the flag is enabled and a real proposal exists.
        if(useStrategyStops && proposedSL > 0)
        {
            stopLossPips = proposedSL;
            takeProfitPips = (proposedTP > 0) ? proposedTP : proposedSL * minRR;
            // Enforce the cluster minimum R:R on the proposed target
            if(takeProfitPips < stopLossPips * minRR)
                takeProfitPips = stopLossPips * minRR;
            PrintFormat("[CANDIDATE-BUILDER] %s | FINDING0 strategy-proposed stops | SL=%.1f TP=%.1f minRR=%.2f",
                        symbol, stopLossPips, takeProfitPips, minRR);
        }
        else if(atrValue > 0)
        {
            if(isSynthetic)
                stopLossPips = (atrValue * 1.5) / point;
            else
                stopLossPips = (atrValue / point) * 2.0;
            takeProfitPips = stopLossPips * minRR;
        }
        else
        {
            // Fallback when no consensus strategy proposed stops (or flag disabled)
            int stopLevelPts = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
            double fallbackByStopLevel = MathMax(30.0, (double)stopLevelPts * 2.0);
            double fallbackByPrice = (candidate.entryPrice * (isSynthetic ? 0.010 : 0.003)) / point;
            stopLossPips = MathMax(fallbackByStopLevel, fallbackByPrice);
            takeProfitPips = stopLossPips * minRR;
        }
        
        // Bound by broker constraints
        // NULL-guard: m_tradeManager is wired via SetDependencies(); if that wiring is ever
        // missing, fall back to SYMBOL_TRADE_STOPS_LEVEL (GetMinimumStopDistance() is itself
        // essentially max(STOPS_LEVEL, FREEZE_LEVEL)*point, so STOPS_LEVEL is a safe floor).
        int stopLevelPts = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
        double brokerMinPoints = (m_tradeManager != NULL)
                                     ? m_tradeManager.GetMinimumStopDistance(symbol)
                                     : (double)stopLevelPts;
        
        double spreadPoints = 0;
        MqlTick tick;
        if(SymbolInfoTick(symbol, tick) && tick.ask > tick.bid && point > 0)
            spreadPoints = (tick.ask - tick.bid) / point;
        
        double minSlPips = MathMax((double)MathMax(brokerMinPoints, stopLevelPts) * 1.50,
                                   MathMax(spreadPoints * 3.0, 8.0));
        double maxSlPips = (candidate.entryPrice * (isSynthetic ? 0.010 : 0.003)) / point;
        if(maxSlPips < minSlPips) maxSlPips = minSlPips;
        
        stopLossPips = MathMax(minSlPips, MathMin(maxSlPips, stopLossPips));
        takeProfitPips = MathMin(takeProfitPips, maxSlPips * minRR);
        
        candidate.stopLossPips = stopLossPips;
        candidate.takeProfitPips = takeProfitPips;
        
        return true;
    }
    
    bool CheckExecutionCost(const string symbol, const STradeCandidate &candidate)
    {
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(point <= 0) return true;
        
        MqlTick tick;
        if(!SymbolInfoTick(symbol, tick) || tick.ask <= tick.bid) return true;
        
        double spreadPoints = (tick.ask - tick.bid) / point;
        if(spreadPoints > 0 && candidate.takeProfitPips > 0)
        {
            double costRatio = spreadPoints / candidate.takeProfitPips;
            if(costRatio > m_maxSpreadToTpRatio)
            {
                PrintFormat("[CANDIDATE-BUILDER] %s | execution cost too high: spread=%.1f tp=%.1f ratio=%.3f > %.3f",
                            symbol, spreadPoints, candidate.takeProfitPips, costRatio, m_maxSpreadToTpRatio);
                return false;
            }
        }
        return true;
    }
    
    bool CheckAccountCapacity(const string symbol, const STradeCandidate &candidate)
    {
        double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double marginRequired = 0;
        
        if(!OrderCalcMargin(candidate.orderType, symbol, minLot, candidate.entryPrice, marginRequired))
            marginRequired = candidate.entryPrice * minLot / 100.0;
        
        double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        if(freeMargin < marginRequired)
        {
            PrintFormat("[CANDIDATE-BUILDER] %s | insufficient margin: free=%.2f req=%.2f",
                        symbol, freeMargin, marginRequired);
            return false;
        }
        return true;
    }
    
    bool ResolveLiveAuthority(const string symbol, STradeCandidate &candidate, double &proposedRisk)
    {
        // This would call the EA's ResolveLiveAuthority function
        // For now, simplified
        candidate.liveAuthorityAllowed = true;
        candidate.liveAuthorityRiskMult = 1.0;
        candidate.liveAuthorityReason = "AUTHORIZED";
        return true;
    }
    
    bool CheckSymbolPositionLimit(const string symbol, const STradeCandidate &candidate)
    {
        if(m_maxPositionsPerSymbol <= 0) return true;
        
        int existingCount = 0;
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            // NULL-guard: a NULL trade manager simply yields no owned-position match rather than crashing.
            if(PositionGetString(POSITION_SYMBOL) == symbol && (m_tradeManager != NULL && m_tradeManager.IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC))))
                existingCount++;
        }
        
        if(existingCount >= m_maxPositionsPerSymbol)
        {
            PrintFormat("[CANDIDATE-BUILDER] %s | per-symbol limit reached: %d >= %d",
                        symbol, existingCount, m_maxPositionsPerSymbol);
            return false;
        }
        return true;
    }
    
    double ApplyDrawdownScaling(const string symbol, double lotSize, double proposedRisk)
    {
        if(!m_antiMartingaleEnabled) return lotSize;

        // Batch 151: the old code read ACCOUNT_EQUITY into BOTH peak and current,
        // so drawdown was always 0 and this scaler was a no-op. Peak equity comes
        // from the risk circuit breaker's tracked high-water mark.
        double peakEquity = (m_riskManager != NULL) ? m_riskManager.GetPeakEquity() : 0.0;
        double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        
        if(peakEquity > 0 && m_aiDrawdownSizingLimit > 0)
        {
            double dd = (peakEquity - currentEquity) / peakEquity;
            if(dd > 0)
            {
                double mult = MathMax(0.10, MathMin(1.0, 1.0 - (dd / MathMax(0.01, m_aiDrawdownSizingLimit))));
                double newLot = lotSize * mult;
                
                // Floor at broker min
                double brokerMinLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
                if(newLot < brokerMinLot && lotSize > brokerMinLot)
                {
                    double floorMult = brokerMinLot / lotSize;
                    if(floorMult <= m_minLotRiskMultiplier)
                    {
                        mult = MathMax(mult, floorMult);
                        newLot = lotSize * mult;
                    }
                }
                
                PrintFormat("[RISK-ADAPT] %s | dd=%.3f mult=%.3f lot=%.2f->%.2f",
                            symbol, dd, mult, lotSize, newLot);
                return newLot;
            }
        }
        return lotSize;
    }
    
    double ApplyMomentumScaling(const string symbol, double lotSize)
    {
        if(m_performanceAnalytics == NULL) return lotSize;
        
        double momentumScale = m_performanceAnalytics.CalculateMomentumScale();
        if(MathAbs(momentumScale - 1.0) > 0.001)
        {
            double newLot = MathMax(SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN), lotSize * momentumScale);
            PrintFormat("[MOMENTUM-SCALE] %s | scale=%.2f | lot=%.2f->%.2f",
                        symbol, momentumScale, lotSize, newLot);
            return newLot;
        }
        return lotSize;
    }
    
    bool ContributorsIncludeAI(const string &contributors[])
    {
        for(int i = 0; i < ArraySize(contributors); i++)
        {
            string c = contributors[i];
            if(StringFind(c, "Neural") >= 0 || StringFind(c, "Transformer") >= 0 ||
               StringFind(c, "Ensemble") >= 0 || StringFind(c, "ONNX") >= 0)
                return true;
        }
        return false;
    }
    
    bool ContributorsIncludeONNX(const string &contributors[])
    {
        for(int i = 0; i < ArraySize(contributors); i++)
            if(StringFind(contributors[i], "ONNX") >= 0) return true;
        return false;
    }
    
    // Diagnostics
        string GetStatusReport() const
        {
            string report = "[CandidateBuilder] Config:\n";
            report += "  MinRRDefault=" + DoubleToString(m_minRRDefault, 1);
            report += " | MinRRMeanRev=" + DoubleToString(m_minRRMeanReversion, 1) + "\n";
            report += "  MaxRiskPerTrade=" + DoubleToString(m_maxRiskPerTrade, 1) + "%\n";
            report += "  HybridGateRelaxCycles=" + IntegerToString(m_hybridGateRelaxAfterCycles);
            report += " | AIStandaloneConf=" + DoubleToString(m_aiStandaloneMinConfidence, 2);
            report += " | AIRelaxedConf=" + DoubleToString(m_aiStandaloneRelaxedConfidence, 2) + "\n";
            // L3-014: Show per-symbol hybrid gate state
            for(int i = 0; i < m_symbolCycleCount; i++)
            {
                string symbol = m_symbolCyclesSinceIndicator[i];
                if(symbol == "") continue;
                int cycles = m_symbolCyclesSinceIndicatorValues[i];
                bool relaxed = false;
                // Find hybrid gate relaxed state for this symbol
                for(int j = 0; j < m_symbolHybridGateRelaxedCount; j++)
                {
                    if(m_symbolHybridGateRelaxedKeys[j] == symbol)
                    {
                        relaxed = m_symbolHybridGateRelaxedValues[j];
                        break;
                    }
                }
                report += "  " + symbol + ": cycles=" + IntegerToString(cycles) + " relaxed=" + (relaxed ? "YES" : "NO") + "\n";
            }
            // Batch 173: symbols the live-authority ladder has sized out of existence. Without
            // this the only trace is a per-candidate log line, and a permanently dark symbol
            // looks the same as a symbol that simply has no signals.
            report += "  authorityLotRefusals total=" + IntegerToString(m_authorityBlockedTotal);
            if(m_authorityBlockedTotal > 0)
            {
                report += "\n";
                for(int k = 0; k < m_authorityBlockSymbolsCount; k++)
                {
                    if(m_authorityBlockCounts[k] <= 0) continue;
                    report += "    " + m_authorityBlockSymbols[k] + " refused=" + IntegerToString(m_authorityBlockCounts[k]) +
                              " (authority lot < SYMBOL_VOLUME_MIN)\n";
                }
            }
            else
                report += "\n";
            return report;
        }
};

#endif // CORE_ORCHESTRATION_CANDIDATE_BUILDER_MQH