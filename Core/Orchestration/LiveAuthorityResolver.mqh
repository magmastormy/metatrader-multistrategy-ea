// Resolves AI vs indicator authority for live trading
#property strict

#ifndef CORE_ORCHESTRATION_LIVE_AUTHORITY_RESOLVER_MQH
#define CORE_ORCHESTRATION_LIVE_AUTHORITY_RESOLVER_MQH

// Promotion floors. These are the values README.md and SYSTEM_STRUCTURE.md document as the
// design intent (30 trades, expectancyR >= 0.3, PF >= 1.2, promoted floor 0.75x). An
// InpAuthority* input may tighten any of them but may not loosen them, so leaving an input at
// its declared default cannot silently relax a live risk gate that has never been exercised.
#define AUTHORITY_MIN_SAMPLES_FLOOR      30
#define AUTHORITY_MIN_EXPECTANCY_R       0.30
#define AUTHORITY_MIN_PROFIT_FACTOR      1.20
#define AUTHORITY_MIN_COST_SCORE         0.50
#define AUTHORITY_MIN_READINESS_SCORE    0.60
#define AUTHORITY_MIN_CONTEXT_SCORE      0.55
#define AUTHORITY_BOOTSTRAP_MULT_CAP     0.50
#define AUTHORITY_PROMOTED_MULT_CAP      0.75

#include "../../Core/Utils/Enums.mqh"
#include "../../Core/Management/EnterpriseStrategyManager.mqh"
#include "../../Core/Utils/JsonLogger.mqh"

class CLiveAuthorityResolver
{
private:
    ENUM_EA_MODE m_effectiveEAMode;
    double m_aiStandaloneMinConfidence;
    double m_aiBootstrapRiskMultiplier;
    double m_aiPromotedRiskMultiplier;
    int m_authorityMinConfluence;
    double m_authorityMinExpectancyR;
    double m_authorityMinProfitFactor;
    int m_authorityMinSamples;
    double m_authorityMinCostScore;
    double m_authorityMinReadinessScore;
    double m_authorityMinContextScore;
    
    // Non-owning manager reference; used only for strategy name/type lookups
    CEnterpriseStrategyManager* m_strategyManager;
    
    struct SStrategyPerf
    {
        string name;
        int totalTrades;
        int winningTrades;
        double expectancyR;
        // Profit factor is the ratio of summed winning R to summed losing R, so both sides
        // have to accumulate; averaging per-trade ratios would not be a profit factor.
        double grossWinR;
        double grossLossR;
        double profitFactor;
        int consecutiveLosses;
        
        SStrategyPerf() : name(""), totalTrades(0), winningTrades(0), expectancyR(0),
                         grossWinR(0), grossLossR(0), profitFactor(1.0), consecutiveLosses(0) {}
    };
    
    SStrategyPerf m_strategyPerf[];
    int m_perfCount;
    
    int FindPerfIndex(const string name)
    {
        for(int i = 0; i < m_perfCount; i++)
            if(m_strategyPerf[i].name == name) return i;
        return -1;
    }

public:
    struct SAuthorityResult
    {
        bool allowed;
        double riskMultiplier;
        string reason;
        
        SAuthorityResult() : allowed(false), riskMultiplier(0.1), reason("") {}
    };
    
    // Defaults are the strictest values this class has ever used, so an un-Configure()d
    // resolver can only under-promote. Configure() below is the real source of truth.
    CLiveAuthorityResolver() : m_effectiveEAMode(EA_MODE_HYBRID), m_aiStandaloneMinConfidence(0.65),
                               m_aiBootstrapRiskMultiplier(0.5), m_aiPromotedRiskMultiplier(0.75),
                               m_authorityMinConfluence(2), m_authorityMinExpectancyR(0.3),
                               m_authorityMinProfitFactor(1.2), m_authorityMinSamples(30),
                               m_authorityMinCostScore(0.50), m_authorityMinReadinessScore(0.60),
                               m_authorityMinContextScore(0.55), m_perfCount(0),
                               m_strategyManager(NULL)
    {
        ArrayResize(m_strategyPerf, 0);
    }
    
    ~CLiveAuthorityResolver() {}
    
    void SetStrategyManager(CEnterpriseStrategyManager* manager)
    {
        m_strategyManager = manager;
    }
    
    // No default arguments: every authority threshold has to be supplied, so a new call
    // site cannot silently reintroduce a literal and leave an input dead.
    void Configure(ENUM_EA_MODE eaMode,
                   double aiStandaloneConf, double aiBootstrapMult, int minConfluence, double minExpectancyR,
                   double minProfitFactor, int minSamples, double minCostScore,
                   double minReadinessScore, double minContextScore, double promotedMult)
    {
        // Ternary, not MathMax: the integer overload returns a double and would warn on the
        // assignment back into int, and this project holds a zero-warning bar.
        int   samples  = (minSamples < AUTHORITY_MIN_SAMPLES_FLOOR) ? AUTHORITY_MIN_SAMPLES_FLOOR : minSamples;
        double expR    = MathMax(minExpectancyR, AUTHORITY_MIN_EXPECTANCY_R);
        double pf      = MathMax(minProfitFactor, AUTHORITY_MIN_PROFIT_FACTOR);
        double cost    = MathMax(minCostScore, AUTHORITY_MIN_COST_SCORE);
        double ready   = MathMax(minReadinessScore, AUTHORITY_MIN_READINESS_SCORE);
        double ctx     = MathMax(minContextScore, AUTHORITY_MIN_CONTEXT_SCORE);
        // Both multipliers scale risk upward, so they are capped rather than floored.
        double boot    = MathMin(aiBootstrapMult, AUTHORITY_BOOTSTRAP_MULT_CAP);
        double promo   = MathMin(promotedMult, AUTHORITY_PROMOTED_MULT_CAP);

        string clamped = "";
        if(samples != minSamples) clamped += "authorityMinSamples ";
        if(expR != minExpectancyR) clamped += "authorityMinExpectancyR ";
        if(pf != minProfitFactor) clamped += "authorityMinProfitFactor ";
        if(cost != minCostScore) clamped += "authorityMinCostScore ";
        if(ready != minReadinessScore) clamped += "authorityMinReadinessScore ";
        if(ctx != minContextScore) clamped += "authorityMinContextScore ";
        if(boot != aiBootstrapMult) clamped += "aiBootstrapRiskMultiplier ";
        if(promo != promotedMult) clamped += "aiPromotedRiskMultiplier ";

        if(clamped != "")
            PrintFormat("[AUTHORITY-CONFIG] clamped to documented floor, promotion may not be loosened by an input that has never been exercised: %s", clamped);
        // Effective values, so a live session can confirm the inputs reached the gate at all.
        PrintFormat("[AUTHORITY-CONFIG] effective: samples=%d expectancyR=%.3f profitFactor=%.2f costScore=%.2f readiness=%.2f context=%.2f bootstrapMult=%.2f promotedMult=%.2f",
                    samples, expR, pf, cost, ready, ctx, boot, promo);

        m_effectiveEAMode = eaMode;
        m_aiStandaloneMinConfidence = aiStandaloneConf;
        m_aiBootstrapRiskMultiplier = boot;
        m_authorityMinConfluence = minConfluence;
        m_authorityMinExpectancyR = expR;
        m_authorityMinProfitFactor = pf;
        m_authorityMinSamples = samples;
        m_authorityMinCostScore = cost;
        m_authorityMinReadinessScore = ready;
        m_authorityMinContextScore = ctx;
        m_aiPromotedRiskMultiplier = promo;
    }
    
            void Resolve(const string symbol, bool hasAIContributor, bool hasONNXContributor,
                         bool hasIndicatorContributor, int indicatorContributorCount,
                         int confluence, double confidence, double qualityScore,
                         double convictionScore, double readinessScore, double contextScore,
                         double costScore, const string contributorSummary,
                         const int &strategyIndices[],
                         SAuthorityResult &result,
                         const string corrId = "")
        {
            if(corrId != "")
                CJsonLogger::SetCorrelationId(corrId);
            
            if(m_effectiveEAMode == EA_MODE_INDICATOR_ONLY && hasAIContributor)
            {
                result.allowed = false;
                result.reason = "INDICATOR_ONLY_MODE";
                CJsonLogger::LogRiskEvent("AuthorityReject", symbol, "INDICATOR_ONLY_MODE", "AI contributor present in INDICATOR_ONLY mode", 0.0, 0.0, corrId);
                CJsonLogger::ClearCorrelationId();
                return;
            }
        
            if(m_effectiveEAMode == EA_MODE_AI_ONLY && !hasAIContributor)
            {
                result.allowed = false;
                result.reason = "AI_ONLY_MODE_NO_AI";
                CJsonLogger::LogRiskEvent("AuthorityReject", symbol, "AI_ONLY_MODE_NO_AI", "No AI contributor in AI_ONLY mode", 0.0, 0.0, corrId);
                CJsonLogger::ClearCorrelationId();
                return;
            }
        
            double authorityScore = 0.0;
            string reasons = "";
        
            if(hasONNXContributor)
            {
                authorityScore += 0.30;
                reasons += "ONNX ";
            }
            if(hasAIContributor && !hasONNXContributor)
            {
                authorityScore += 0.25;
                reasons += "AI ";
            }
        
            if(hasIndicatorContributor)
            {
                authorityScore += 0.20 * MathMin(1.0, indicatorContributorCount / 2.0);
                reasons += "INDICATOR ";
            }
        
            if(confluence >= m_authorityMinConfluence)
            {
                authorityScore += 0.15;
                reasons += "CONFLUENCE ";
            }
        
            if(qualityScore >= 0.7) authorityScore += 0.10;
            if(convictionScore >= 0.65) authorityScore += 0.08;
            if(readinessScore >= m_authorityMinReadinessScore) authorityScore += 0.07;
            if(contextScore >= m_authorityMinContextScore) authorityScore += 0.05;
            // costScore is quality-shaped, not cost-shaped: higher means cheaper. The pipeline
            // adds it into the weighted signal score (SignalPipelineWeighter: score += costScore*0.0543),
            // so the bonus is earned at the TOP of the range. The previous `<= 0.3` test paid
            // authority points to the most expensive trades.
            if(costScore >= m_authorityMinCostScore) authorityScore += 0.05;
        
            double minConfidence = m_aiStandaloneMinConfidence;
            if(hasIndicatorContributor)
                minConfidence = 0.55; // Lower threshold with indicator support
        
            if(confidence < minConfidence)
            {
                result.allowed = false;
                result.riskMultiplier = m_aiBootstrapRiskMultiplier * 0.5;
                result.reason = StringFormat("LOW_CONFIDENCE_%.2f<%.2f", confidence, minConfidence);
                CJsonLogger::LogRiskEvent("AuthorityReject", symbol, "LOW_CONFIDENCE", 
                    StringFormat("Confidence %.2f below threshold %.2f", confidence, minConfidence), 
                    confidence, minConfidence, corrId);
                CJsonLogger::ClearCorrelationId();
                return;
            }
        
            double riskMult;
            if(authorityScore >= 0.80)
                riskMult = 1.0;
            else if(authorityScore >= 0.65)
                riskMult = 0.85;
            else if(authorityScore >= 0.50)
                riskMult = 0.70;
            else if(authorityScore >= 0.35)
                riskMult = 0.50;
            else
                riskMult = m_aiBootstrapRiskMultiplier * 0.5;
        
            // Bootstrap: AI-only contributors need a proven record before full risk
            if(hasAIContributor && !hasIndicatorContributor)
            {
                string aiStrategyName = ExtractAIName(contributorSummary, strategyIndices);
                if(aiStrategyName != "")
                {
                    int perfIdx = FindPerfIndex(aiStrategyName);
                    if(perfIdx >= 0 && m_strategyPerf[perfIdx].totalTrades >= m_authorityMinSamples)
                    {
                        if(m_strategyPerf[perfIdx].expectancyR >= m_authorityMinExpectancyR &&
                           m_strategyPerf[perfIdx].profitFactor >= m_authorityMinProfitFactor &&
                           m_strategyPerf[perfIdx].consecutiveLosses < 4)
                        {
                            riskMult = MathMax(riskMult, m_aiPromotedRiskMultiplier);
                            reasons += "PROVEN_AI ";
                            CJsonLogger::LogInfo("AuthorityDecision", StringFormat("PROVEN_AI strategy=%s riskMult=%.2f", aiStrategyName, riskMult), corrId);
                        }
                        else
                        {
                            // Unproven or struggling: cap riskMult at the bootstrap multiplier
                            riskMult = MathMin(riskMult, m_aiBootstrapRiskMultiplier);
                            reasons += "BOOTSTRAP_AI ";
                            CJsonLogger::LogInfo("AuthorityDecision", StringFormat("BOOTSTRAP_AI strategy=%s riskMult=%.2f", aiStrategyName, riskMult), corrId);
                        }
                    }
                    else
                    {
                        // Not enough data - bootstrap
                        riskMult = MathMin(riskMult, m_aiBootstrapRiskMultiplier);
                        reasons += "BOOTSTRAP ";
                        CJsonLogger::LogInfo("AuthorityDecision", StringFormat("BOOTSTRAP strategy=%s riskMult=%.2f", aiStrategyName, riskMult), corrId);
                    }
                }
            }
        
            // Safety floor
            riskMult = MathMax(0.10, riskMult);
        
            result.allowed = true;
            result.riskMultiplier = riskMult;
            result.reason = "AUTHORIZED | score=" + DoubleToString(authorityScore, 2) + " | " + reasons;
            CJsonLogger::LogRiskEvent("AuthorityAllow", symbol, "AUTHORIZED", 
                StringFormat("authorityScore=%.2f riskMult=%.2f reasons=%s", authorityScore, riskMult, reasons), 
                authorityScore, riskMult, corrId);
            CJsonLogger::ClearCorrelationId();
        }
    
    void RecordOutcome(const string strategyName, double profitR, bool isWin)
    {
        int idx = FindPerfIndex(strategyName);
        if(idx < 0)
        {
            idx = m_perfCount;
            ArrayResize(m_strategyPerf, idx + 1);
            m_strategyPerf[idx].name = strategyName;
            m_perfCount++;
        }
        
        SStrategyPerf perf = m_strategyPerf[idx];
        perf.totalTrades++;
        if(isWin) perf.winningTrades++;
        
        double oldExp = perf.expectancyR;
        perf.expectancyR = (oldExp * (perf.totalTrades - 1) + profitR) / perf.totalTrades;
        
        // Accumulate by the sign of profitR rather than by isWin: a breakeven close (R == 0)
        // belongs to neither side of a profit factor and must not enter the loss denominator.
        if(profitR > 0.0)
            perf.grossWinR += profitR;
        else if(profitR < 0.0)
            perf.grossLossR -= profitR;
        
        // A record with no losing trade is a perfect one, not a divide-by-zero; the cap keeps
        // the sentinel a readable magnitude in the [AUTHORITY-LEARN] log.
        perf.profitFactor = (perf.grossLossR > 0.0)
                          ? perf.grossWinR / perf.grossLossR
                          : (perf.grossWinR > 0.0 ? 999.0 : 1.0);
        
        if(isWin)
            perf.consecutiveLosses = 0;
        else
            perf.consecutiveLosses++;
        
        m_strategyPerf[idx] = perf;
    }
    
    string ExtractAIName(const string contributorSummary, const int &strategyIndices[])
    {
        // AI Strategy types: STRATEGY_BRAIN, STRATEGY_AI_ENHANCED, STRATEGY_ONNX
        
        if(m_strategyManager == NULL || ArraySize(strategyIndices) == 0)
        {
            // Manager not available - cannot reliably identify AI strategies
            return "";
        }
        
        for(int i = 0; i < ArraySize(strategyIndices); i++)
        {
            int idx = strategyIndices[i];
            if(idx < 0 || idx >= m_strategyManager.GetRegisteredStrategyCount())
                continue;
            
            string strategyName = m_strategyManager.GetRegisteredStrategyName(idx);
            if(strategyName == "") continue;
            
            ENUM_STRATEGY_TYPE stratType = GetStrategyTypeByName(strategyName);
            if(stratType == STRATEGY_BRAIN || stratType == STRATEGY_AI_ENHANCED || stratType == STRATEGY_ONNX)
            {
                return strategyName; // Return the actual strategy name for perf tracking
            }
        }
        
        return "";
    }
    
    ENUM_STRATEGY_TYPE GetStrategyTypeByName(const string strategyName)
    {
        if(m_strategyManager == NULL) return STRATEGY_CUSTOM;
        
        int count = m_strategyManager.GetRegisteredStrategyCount();
        for(int i = 0; i < count; i++)
        {
            if(m_strategyManager.GetRegisteredStrategyName(i) == strategyName)
            {
                IStrategy* strategy = m_strategyManager.GetStrategyByName(strategyName);
                if(strategy != NULL)
                {
                    return strategy.GetType();
                }
            }
        }
        return STRATEGY_CUSTOM;
    }
    
    string GetStatusReport() const
    {
        string report = "[LiveAuthorityResolver] ";
        report += "EA_Mode=" + EnumToString(m_effectiveEAMode);
        report += " | AI_Conf=" + DoubleToString(m_aiStandaloneMinConfidence, 2);
        report += " | TrackedStrategies=" + IntegerToString(m_perfCount) + "\n";
        report += "  thresholds: minSamples=" + IntegerToString(m_authorityMinSamples)
                + " minExpectancyR=" + DoubleToString(m_authorityMinExpectancyR, 3)
                + " minProfitFactor=" + DoubleToString(m_authorityMinProfitFactor, 2)
                + " minCostScore=" + DoubleToString(m_authorityMinCostScore, 2)
                + " bootstrapMult=" + DoubleToString(m_aiBootstrapRiskMultiplier, 2)
                + " promotedMult=" + DoubleToString(m_aiPromotedRiskMultiplier, 2) + "\n";
        
        for(int i = 0; i < m_perfCount; i++)
        {
            report += "  " + m_strategyPerf[i].name + ": ";
            report += "trades=" + IntegerToString(m_strategyPerf[i].totalTrades);
            report += " winrate=" + DoubleToString(m_strategyPerf[i].totalTrades > 0 ? 
                                                   (double)m_strategyPerf[i].winningTrades / m_strategyPerf[i].totalTrades * 100 : 0, 1) + "%";
            report += " expR=" + DoubleToString(m_strategyPerf[i].expectancyR, 3);
            report += " pf=" + DoubleToString(m_strategyPerf[i].profitFactor, 2);
            report += " eligible=" + (m_strategyPerf[i].totalTrades >= m_authorityMinSamples &&
                                      m_strategyPerf[i].expectancyR >= m_authorityMinExpectancyR &&
                                      m_strategyPerf[i].profitFactor >= m_authorityMinProfitFactor &&
                                      m_strategyPerf[i].consecutiveLosses < 4 ? "Y" : "N");
            report += " consecLoss=" + IntegerToString(m_strategyPerf[i].consecutiveLosses) + "\n";
        }
        
        return report;
    }
};

#endif // CORE_ORCHESTRATION_LIVE_AUTHORITY_RESOLVER_MQH