//+------------------------------------------------------------------+
//| CandidateBuilder.mqh                                             |
//| Builds trade candidates from validated signals                   |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_ORCHESTRATION_CANDIDATE_BUILDER_MQH
#define CORE_ORCHESTRATION_CANDIDATE_BUILDER_MQH

#include "../../Core/Management/EnterpriseStrategyManager.mqh"
#include "../../Core/Risk/UnifiedRiskManager.mqh"
#include "../../Core/Risk/PositionSizer.mqh"
#include "../../Core/Utils/Enums.mqh"
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
    bool liveAuthorityAllowed;
    double liveAuthorityRiskMult;
    string liveAuthorityReason;
    bool hasAIContributor;
    bool hasONNXContributor;
    bool hasIndicatorContributor;
    int indicatorContributorCount;
    
    STradeCandidate() : symbol(""), orderType(ORDER_TYPE_BUY), entryPrice(0), stopLossPips(0),
                       takeProfitPips(0), lotSize(0), riskPercent(0), confidence(0),
                       confluence(0), qualityScore(0), convictionScore(0), readinessScore(0), contextScore(0),
                       costScore(0), liveAuthorityAllowed(false), liveAuthorityRiskMult(1.0),
                       hasAIContributor(false), hasONNXContributor(false),
                       hasIndicatorContributor(false), indicatorContributorCount(0) {}
};

class CCandidateBuilder
{
private:
    CUnifiedRiskManager*        m_riskManager;
    CPositionSizer*             m_positionSizer;
    CTradeManager*              m_tradeManager;
    CPerformanceAnalytics*      m_performanceAnalytics;
    CDerivAssetProfiler*        m_derivProfiler;
    
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
    
    // Hybrid gate relaxation
    int                         m_hybridGateRelaxAfterCycles;
    double                      m_aiStandaloneMinConfidence;
    double                      m_aiStandaloneRelaxedConfidence;
    int                         m_cyclesSinceIndicatorSignal;
    bool                        m_hybridGateRelaxed;
    
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

public:
    CCandidateBuilder() : 
        m_riskManager(NULL), m_positionSizer(NULL), m_tradeManager(NULL),
        m_performanceAnalytics(NULL), m_derivProfiler(NULL),
        m_minRRDefault(2.0), m_minRRMeanReversion(1.5), m_maxRiskPerTrade(5.0),
        m_maxSpreadToTpRatio(0.15), m_minLotRiskMultiplier(1.5),
        m_aiDrawdownSizingLimit(0.2), m_antiMartingaleEnabled(true),
        m_maxPositionsPerSymbol(0), m_portfolioMaxPositionsPerSymbol(0),
        m_hybridGateRelaxAfterCycles(5), m_aiStandaloneMinConfidence(0.65),
        m_aiStandaloneRelaxedConfidence(0.65), m_cyclesSinceIndicatorSignal(0),
        m_hybridGateRelaxed(false)
    {
        ArrayResize(m_minRRByCluster, 10);
        ArrayInitialize(m_minRRByCluster, 2.0);
        // Cluster-specific overrides
        m_minRRByCluster[MEAN_REVERSION_CLUSTER] = 1.5;
    }
    
    void SetDependencies(CUnifiedRiskManager* risk, CPositionSizer* sizer, CTradeManager* trade,
                         CPerformanceAnalytics* perf, CDerivAssetProfiler* derivProf)
    {
        m_riskManager = risk;
        m_positionSizer = sizer;
        m_tradeManager = trade;
        m_performanceAnalytics = perf;
        m_derivProfiler = derivProf;
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
                        STradeCandidate &candidate)
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
        
        // Check contributors
        candidate.hasAIContributor = ContributorsIncludeAI(contributorsList);
        candidate.hasONNXContributor = ContributorsIncludeONNX(contributorsList);
        candidate.hasIndicatorContributor = ContributorsIncludeIndicator(contributorsList);
        candidate.indicatorContributorCount = CountIndicatorContributors(contributorsList);
        
        // Handle hybrid gate relaxation
        if(candidate.hasIndicatorContributor)
        {
            if(m_hybridGateRelaxed)
                PrintFormat("[HYBRID-GATE-RESTORED] Indicator signal detected, AI threshold restored to %.3f",
                            m_aiStandaloneMinConfidence);
            m_cyclesSinceIndicatorSignal = 0;
            m_hybridGateRelaxed = false;
        }
        else if(m_cyclesSinceIndicatorSignal > m_hybridGateRelaxAfterCycles && !m_hybridGateRelaxed)
        {
            m_hybridGateRelaxed = true;
            PrintFormat("[HYBRID-GATE-RELAXED] No indicator signals for %d cycles, AI threshold %.3f -> %.3f",
                        m_cyclesSinceIndicatorSignal, m_aiStandaloneMinConfidence, m_aiStandaloneRelaxedConfidence);
        }
        
        // Resolve EA mode admission
        string modeRejectReason = "";
        double modeConfidenceBonus = 0.0;
        if(!EvaluateEAModeAdmission(contributorsList, confidence, modeRejectReason, modeConfidenceBonus))
        {
            PrintFormat("[CANDIDATE-BUILDER] %s | EA mode admission rejected: %s", symbol, modeRejectReason);
            return false;
        }
        if(modeConfidenceBonus > 0)
        {
            confidence = MathMin(1.0, confidence + modeConfidenceBonus);
            candidate.confidence = confidence;
        }
        
        // Get entry price
        candidate.entryPrice = (signal == TRADE_SIGNAL_BUY) 
            ? SymbolInfoDouble(symbol, SYMBOL_ASK) 
            : SymbolInfoDouble(symbol, SYMBOL_BID);
        
        if(candidate.entryPrice <= 0)
            return false;
        
        // Calculate SL/TP
        if(!CalculateStops(symbol, signal, candidate, ctx))
            return false;
        
        // Check execution cost
        if(!CheckExecutionCost(symbol, candidate))
            return false;
        
        // Check account capacity
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
        
        // Resolve live authority
        if(!ResolveLiveAuthority(symbol, candidate, proposedRisk))
            return false;
        
        // Check per-symbol position limit
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
        if(!ApproveTradeByUnifiedRisk(tradeReq, "pre-size", riskResult, scanCycleId))
            return false;
        
        // Calculate final lot size
        double lotSize = m_positionSizer.CalculateSize(symbol, candidate.orderType, 
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
        
        // Apply drawdown scaling
        lotSize = ApplyDrawdownScaling(symbol, lotSize, proposedRisk);
        
        // Apply momentum scaling
        lotSize = ApplyMomentumScaling(symbol, lotSize);
        
        // Apply VPIN toxicity scaling
        lotSize = ApplyVPINScaling(symbol, lotSize);
        
        // Apply volatility targeting scaling
        lotSize = ApplyVolTargetScaling(symbol, lotSize);
        
        // Apply Skew Step scaling
        lotSize = ApplySkewStepScaling(symbol, lotSize);
        
        // Apply full-margin stacking
        lotSize = ApplyFullMarginStacking(symbol, signal, lotSize);
        
        // Apply safe mode restrictions
        lotSize = ApplySafeModeRestrictions(symbol, lotSize);
        
        // Floor at broker minimum
        double brokerMinLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        if(lotSize < brokerMinLot)
            lotSize = brokerMinLot;
        
        candidate.lotSize = lotSize;
        candidate.riskPercent = proposedRisk;
        
        // Build reasoning
        candidate.reasoning = StringFormat("role=%s | cluster=%s | contributors=%s | conviction=%.2f | readiness=%.2f | context=%.2f | cost=%.2f",
                                           roleTag, clusterTag, contribSummary,
                                           ctx.convictionScore, ctx.readinessScore, ctx.contextScore, ctx.costScore);
        
        // Increment cycles since indicator signal
        if(!candidate.hasIndicatorContributor)
            m_cyclesSinceIndicatorSignal++;
        
        return true;
    }
    
    // === Helper methods ===
    
    bool CalculateStops(const string symbol, ENUM_TRADE_SIGNAL signal, STradeCandidate &candidate,
                        const SConsensusDecisionContext& ctx)
    {
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(point <= 0) point = 0.00001;
        
        bool isSynthetic = IsSyntheticIndexSymbolName(symbol);
        
        // Get ATR from pipeline
        CUnifiedSignalPipeline* pipeline = NULL; // Would be passed in real implementation
        double atrValue = 0;
        
        // Simplified ATR-based stop calculation
        double stopLossPips = 0;
        if(atrValue > 0)
        {
            if(isSynthetic)
                stopLossPips = (atrValue * 1.5) / point;
            else
                stopLossPips = (atrValue / point) * 2.0;
        }
        else
        {
            // Fallback
            int stopLevelPts = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
            double fallbackByStopLevel = MathMax(30.0, (double)stopLevelPts * 2.0);
            double fallbackByPrice = (candidate.entryPrice * (isSynthetic ? 0.010 : 0.003)) / point;
            stopLossPips = MathMax(fallbackByStopLevel, fallbackByPrice);
        }
        
        // Bound by broker constraints
        int brokerMinPoints = m_tradeManager.GetMinimumStopPoints(symbol);
        int stopLevelPts = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
        
        double spreadPoints = 0;
        MqlTick tick;
        if(SymbolInfoTick(symbol, tick) && tick.ask > tick.bid && point > 0)
            spreadPoints = (tick.ask - tick.bid) / point;
        
        double minSlPips = MathMax((double)MathMax(brokerMinPoints, stopLevelPts) * 1.50,
                                   MathMax(spreadPoints * 3.0, 8.0));
        double maxSlPips = (candidate.entryPrice * (isSynthetic ? 0.010 : 0.003)) / point;
        if(maxSlPips < minSlPips) maxSlPips = minSlPips;
        
        stopLossPips = MathMax(minSlPips, MathMin(maxSlPips, stopLossPips));
        
        // Determine minRR based on cluster
        double minRR = m_minRRDefault;
        if(ctx.dominantCluster == MEAN_REVERSION_CLUSTER)
            minRR = m_minRRMeanReversion;
        
        double takeProfitPips = stopLossPips * minRR;
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
            if(PositionGetString(POSITION_SYMBOL) == symbol && IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC)))
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
        
        double peakEquity = AccountInfoDouble(ACCOUNT_EQUITY); // Would track peak
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
    
    double ApplyVPINScaling(const string symbol, double lotSize)
    {
        // Would use m_mathRegistry if available
        return lotSize;
    }
    
    double ApplyVolTargetScaling(const string symbol, double lotSize)
    {
        // Would use m_mathRegistry if available
        return lotSize;
    }
    
    double ApplySkewStepScaling(const string symbol, double lotSize)
    {
        // Would use skew step analyzer if available
        return lotSize;
    }
    
    double ApplyFullMarginStacking(const string symbol, ENUM_TRADE_SIGNAL signal, double lotSize)
    {
        // Would use m_fullMarginMode if available
        return lotSize;
    }
    
    double ApplySafeModeRestrictions(const string symbol, double lotSize)
    {
        // Would use m_safeMode if available
        return lotSize;
    }
    
    // === EA mode admission ===
    bool EvaluateEAModeAdmission(const string &contributors[], double confidence,
                                 string &rejectReason, double &confidenceBonus)
    {
        // Simplified - would use actual EA mode logic
        rejectReason = "";
        confidenceBonus = 0.0;
        return true;
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
        report += "  CyclesSinceIndicator=" + IntegerToString(m_cyclesSinceIndicatorSignal);
        report += " | GateRelaxed=" + (m_hybridGateRelaxed ? "YES" : "NO");
        return report;
    }
};

#endif // CORE_ORCHESTRATION_CANDIDATE_BUILDER_MQH