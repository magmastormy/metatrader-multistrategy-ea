//+------------------------------------------------------------------+
//| LiveAuthorityResolver.mqh                                        |
//| Resolves AI vs indicator authority for live trading              |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_ORCHESTRATION_LIVE_AUTHORITY_RESOLVER_MQH
#define CORE_ORCHESTRATION_LIVE_AUTHORITY_RESOLVER_MQH

#include "../../Core/Utils/Enums.mqh"
#include "../../Core/Management/EnterpriseStrategyManager.mqh"
#include "../../Core/Utils/JsonLogger.mqh"

class CLiveAuthorityResolver
{
private:
    // Configuration
    ENUM_EA_MODE m_effectiveEAMode;
    double m_aiStandaloneMinConfidence;
    double m_aiBootstrapRiskMultiplier;
    int m_authorityMinConfluence;
    double m_authorityMinExpectancyR;
    
    // Strategy manager reference for type checking
    CEnterpriseStrategyManager* m_strategyManager;
    
    // Performance tracking per strategy
    struct SStrategyPerf
    {
        string name;
        int totalTrades;
        int winningTrades;
        double expectancyR;
        double profitFactor;
        double maxDrawdownR;
        int consecutiveLosses;
        
        SStrategyPerf() : name(""), totalTrades(0), winningTrades(0), expectancyR(0),
                         profitFactor(0), maxDrawdownR(0), consecutiveLosses(0) {}
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
    
    CLiveAuthorityResolver() : m_effectiveEAMode(EA_MODE_HYBRID), m_aiStandaloneMinConfidence(0.65),
                               m_aiBootstrapRiskMultiplier(0.5), m_authorityMinConfluence(2),
                               m_authorityMinExpectancyR(0.3), m_perfCount(0),
                               m_strategyManager(NULL)
    {
        ArrayResize(m_strategyPerf, 0);
    }
    
    ~CLiveAuthorityResolver() {}
    
    void SetStrategyManager(CEnterpriseStrategyManager* manager)
    {
        m_strategyManager = manager;
    }
    
    void Configure(ENUM_EA_MODE eaMode,
                   double aiStandaloneConf, double aiBootstrapMult, int minConfluence, double minExpectancyR)
    {
        m_effectiveEAMode = eaMode;
        m_aiStandaloneMinConfidence = aiStandaloneConf;
        m_aiBootstrapRiskMultiplier = aiBootstrapMult;
        m_authorityMinConfluence = minConfluence;
        m_authorityMinExpectancyR = minExpectancyR;
    }
    
    // Main authority resolution
            void Resolve(const string symbol, bool hasAIContributor, bool hasONNXContributor,
                         bool hasIndicatorContributor, int indicatorContributorCount,
                         int confluence, double confidence, double qualityScore,
                         double convictionScore, double readinessScore, double contextScore,
                         double costScore, const string contributorSummary,
                         const int &strategyIndices[],
                         SAuthorityResult &result,
                         const string corrId = "")
        {
            // Set correlation ID for structured logging
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
        
            // Authority scoring
            double authorityScore = 0.0;
            string reasons = "";
        
            // AI contributor scoring
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
        
            // Indicator contributor scoring
            if(hasIndicatorContributor)
            {
                authorityScore += 0.20 * MathMin(1.0, indicatorContributorCount / 2.0);
                reasons += "INDICATOR ";
            }
        
            // Confluence bonus
            if(confluence >= m_authorityMinConfluence)
            {
                authorityScore += 0.15;
                reasons += "CONFLUENCE ";
            }
        
            // Quality metrics
            if(qualityScore >= 0.7) authorityScore += 0.10;
            if(convictionScore >= 0.65) authorityScore += 0.08;
            if(readinessScore >= 0.6) authorityScore += 0.07;
            if(contextScore >= 0.55) authorityScore += 0.05;
            if(costScore <= 0.3) authorityScore += 0.05; // Low cost
        
            // Confidence threshold
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
        
            // Determine risk multiplier based on authority score
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
        
            // Bootstrap logic for new strategies
            if(hasAIContributor && !hasIndicatorContributor)
            {
                // Check if AI strategy has proven track record
                string aiStrategyName = ExtractAIName(contributorSummary, strategyIndices);
                if(aiStrategyName != "")
                {
                    int perfIdx = FindPerfIndex(aiStrategyName);
                    if(perfIdx >= 0 && m_strategyPerf[perfIdx].totalTrades >= 30)
                    {
                        if(m_strategyPerf[perfIdx].expectancyR >= m_authorityMinExpectancyR &&
                           m_strategyPerf[perfIdx].profitFactor >= 1.2 &&
                           m_strategyPerf[perfIdx].consecutiveLosses < 4)
                        {
                            // Proven AI strategy - allow full risk
                            riskMult = MathMax(riskMult, 0.75);
                            reasons += "PROVEN_AI ";
                            CJsonLogger::LogInfo("AuthorityDecision", StringFormat("PROVEN_AI strategy=%s riskMult=%.2f", aiStrategyName, riskMult), corrId);
                        }
                        else
                        {
                            // Unproven or struggling - limit risk
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
    
    // Record trade outcome for authority learning
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
        
        // Update expectancy (simplified)
        double oldExp = perf.expectancyR;
        perf.expectancyR = (oldExp * (perf.totalTrades - 1) + profitR) / perf.totalTrades;
        
        if(isWin)
            perf.consecutiveLosses = 0;
        else
            perf.consecutiveLosses++;
        
        // Write back
        m_strategyPerf[idx] = perf;
        
        // Update profit factor and drawdown
        // Simplified for brevity
    }
    
    string ExtractAIName(const string contributorSummary, const int &strategyIndices[])
    {
        // Extract AI strategy name from contributor summary using strategy type enum
        // AI Strategy types: STRATEGY_BRAIN, STRATEGY_AI_ENHANCED, STRATEGY_ONNX
        
        if(m_strategyManager == NULL || ArraySize(strategyIndices) == 0)
        {
            // Manager not available - cannot reliably identify AI strategies
            return "";
        }
        
        // Check strategy types from the manager using indices
        for(int i = 0; i < ArraySize(strategyIndices); i++)
        {
            int idx = strategyIndices[i];
            if(idx < 0 || idx >= m_strategyManager.GetRegisteredStrategyCount())
                continue;
            
            // Get strategy type via GetType() method
            string strategyName = m_strategyManager.GetRegisteredStrategyName(idx);
            if(strategyName == "") continue;
            
            // Check if this is an AI strategy by checking the type enum
            ENUM_STRATEGY_TYPE stratType = GetStrategyTypeByName(strategyName);
            if(stratType == STRATEGY_BRAIN || stratType == STRATEGY_AI_ENHANCED || stratType == STRATEGY_ONNX)
            {
                return strategyName; // Return the actual strategy name for perf tracking
            }
        }
        
        return "";
    }
    
    // Helper: Get strategy type by name using the manager
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
    
    // Diagnostics
    string GetStatusReport() const
    {
        string report = "[LiveAuthorityResolver] ";
        report += "EA_Mode=" + EnumToString(m_effectiveEAMode);
        report += " | AI_Conf=" + DoubleToString(m_aiStandaloneMinConfidence, 2);
        report += " | TrackedStrategies=" + IntegerToString(m_perfCount) + "\n";
        
        for(int i = 0; i < m_perfCount; i++)
        {
            report += "  " + m_strategyPerf[i].name + ": ";
            report += "trades=" + IntegerToString(m_strategyPerf[i].totalTrades);
            report += " winrate=" + DoubleToString(m_strategyPerf[i].totalTrades > 0 ? 
                                                   (double)m_strategyPerf[i].winningTrades / m_strategyPerf[i].totalTrades * 100 : 0, 1) + "%";
            report += " expR=" + DoubleToString(m_strategyPerf[i].expectancyR, 3);
            report += " consecLoss=" + IntegerToString(m_strategyPerf[i].consecutiveLosses) + "\n";
        }
        
        return report;
    }
};

#endif // CORE_ORCHESTRATION_LIVE_AUTHORITY_RESOLVER_MQH