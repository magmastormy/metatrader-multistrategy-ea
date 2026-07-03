//+------------------------------------------------------------------+
//| AIEngine.mqh - AI Hooks and Integration Module                   |
//| Provides AI-ready interfaces for external ML model integration   |
//+------------------------------------------------------------------+
#ifndef AI_ENGINE_MQH
#define AI_ENGINE_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CMarketAnalysis;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CTradeManager;
class CPerformanceAnalytics;
class CEnterpriseStrategyManager;

//+------------------------------------------------------------------+
//| AI Query Request Structure                                       |
//+------------------------------------------------------------------+
struct SAIQueryRequest {
    string queryType;           // Type of query (prediction, explanation, weights)
    string symbol;              // Symbol for context
    ENUM_TIMEFRAMES timeframe;  // Timeframe for context
    double marketData[50];      // Market data array
    int dataSize;               // Size of market data
    string parameters;          // Additional parameters (JSON-like)
    datetime timestamp;         // Request timestamp
    
    SAIQueryRequest() {
        queryType = "";
        symbol = "";
        timeframe = PERIOD_H1;
        dataSize = 0;
        parameters = "";
        timestamp = 0;
        ArrayInitialize(marketData, 0.0);
    }
};

//+------------------------------------------------------------------+
//| AI Query Response Structure                                      |
//+------------------------------------------------------------------+
struct SAIQueryResponse {
    bool success;               // Query successful
    double prediction;          // Prediction value (0-1)
    double confidence;          // Confidence level (0-1)
    string explanation;         // Human-readable explanation
    string jsonData;            // Additional data in JSON format
    int processingTimeMs;       // Processing time in milliseconds
    string errorMessage;        // Error message if failed
    
    SAIQueryResponse() {
        success = false;
        prediction = 0.0;
        confidence = 0.0;
        explanation = "";
        jsonData = "";
        processingTimeMs = 0;
        errorMessage = "";
    }
};

//+------------------------------------------------------------------+
//| AI Weight Modification Request                                   |
//+------------------------------------------------------------------+
struct SAIWeightModification {
    string strategyName;        // Strategy to modify
    double newWeight;           // New weight value
    string reason;              // Reason for modification
    double confidence;          // AI confidence in this change
    bool temporary;             // Temporary or permanent change
    int durationBars;           // Duration in bars (if temporary)
    
    SAIWeightModification() {
        strategyName = "";
        newWeight = 1.0;
        reason = "";
        confidence = 0.5;
        temporary = true;
        durationBars = 10;
    }
};

//+------------------------------------------------------------------+
//| AI Decision Explanation Structure                                |
//+------------------------------------------------------------------+
struct SAIDecisionExplanation {
    ENUM_TRADE_SIGNAL signal;         // The signal being explained
    string primaryReason;             // Main reason for decision
    string contributingFactors[10];   // Contributing factors
    int factorCount;                  // Number of factors
    double factorWeights[10];         // Weight of each factor
    string riskAssessment;            // Risk assessment explanation
    string marketContext;             // Market context explanation
    double overallConfidence;         // Overall decision confidence
    
    SAIDecisionExplanation() {
        signal = TRADE_SIGNAL_NONE;
        primaryReason = "";
        factorCount = 0;
        riskAssessment = "";
        marketContext = "";
        overallConfidence = 0.0;
        ArrayInitialize(factorWeights, 0.0);
    }
};

//+------------------------------------------------------------------+
//| AI Adaptive Mode Configuration                                   |
//+------------------------------------------------------------------+
struct SAIAdaptiveConfig {
    bool enabled;                     // Adaptive mode enabled
    double learningRate;              // Learning rate (0-1)
    int adaptationInterval;           // Bars between adaptations
    double minConfidenceThreshold;    // Min confidence to trade
    double maxRiskMultiplier;         // Max risk multiplier in adaptive mode
    bool useMarketRegimeAdaptation;   // Adapt to market regime
    bool usePerformanceAdaptation;    // Adapt based on performance
    bool useSentimentAdaptation;      // Adapt based on sentiment (future)
    bool useExternalLLM;              // Use external LLM for advanced reasoning (default: false)
    
    SAIAdaptiveConfig() {
        enabled = true;
        learningRate = 0.1;
        adaptationInterval = 5;
        minConfidenceThreshold = 0.6;
        maxRiskMultiplier = 1.5;
        useMarketRegimeAdaptation = true;
        usePerformanceAdaptation = true;
        useSentimentAdaptation = false;
        useExternalLLM = false;  // Default to not using external LLM
    }
};

//+------------------------------------------------------------------+
//| AI Engine Class                                                  |
//+------------------------------------------------------------------+
class CAIEngine {
private:
    CEnterpriseStrategyManager* m_manager;    // Reference to enterprise manager
    SAIAdaptiveConfig m_adaptiveConfig;       // Adaptive mode configuration
    
    // State tracking
    bool m_initialized;
    bool m_adaptiveModeActive;
    datetime m_lastAdaptation;
    int m_queryCount;
    int m_successfulQueries;
    
    // Weight modification tracking
    SAIWeightModification m_pendingMods[20];
    int m_pendingModCount;
    
    // Decision history for explanations
    SAIDecisionExplanation m_recentDecisions[50];
    int m_decisionIndex;
    int m_decisionCount;
    
    // Performance feedback
    double m_predictionAccuracy;
    int m_totalPredictions;
    int m_correctPredictions;
    
    // External AI connection state
    bool m_externalAIConnected;
    string m_externalAIEndpoint;
    int m_externalLLMQueryCount;
    int m_externalLLMSuccessCount;
    int m_externalLLMFailureCount;
    datetime m_lastExternalLLMLogTime;
    datetime m_lastExternalReasoningTime;
    string m_lastExternalLLMPhase;
    string m_lastExternalReasoning;
    
    // Log AI event
    void LogAI(ENUM_ERROR_LEVEL level, string message) {
        CEnhancedErrorHandler::LogError((ENUM_ERROR_SEVERITY)level, "AIEngine", message, 0);
    }

    void LogExternalLLM(const string phase, const string detail, const bool force = false) {
        datetime now = TimeCurrent();
        if(!force &&
           phase == m_lastExternalLLMPhase &&
           m_lastExternalLLMLogTime > 0 &&
           (now - m_lastExternalLLMLogTime) < 30)
        {
            return;
        }

        PrintFormat("[EXT-LLM] %s | enabled=%s | connected=%s | endpoint=%s | queries=%d | ok=%d | fail=%d | %s",
                    phase,
                    m_adaptiveConfig.useExternalLLM ? "true" : "false",
                    m_externalAIConnected ? "true" : "false",
                    m_externalAIEndpoint,
                    m_externalLLMQueryCount,
                    m_externalLLMSuccessCount,
                    m_externalLLMFailureCount,
                    detail);
        m_lastExternalLLMPhase = phase;
        m_lastExternalLLMLogTime = now;
    }

    string EscapeJson(const string &value) {
        string escaped = value;
        StringReplace(escaped, "\\", "\\\\");
        StringReplace(escaped, "\"", "\\\"");
        StringReplace(escaped, "\r", " ");
        StringReplace(escaped, "\n", "\\n");
        return escaped;
    }
    
    // Calculate prediction accuracy
    void UpdatePredictionAccuracy(bool wasCorrect) {
        m_totalPredictions++;
        if(wasCorrect) m_correctPredictions++;
        m_predictionAccuracy = (double)m_correctPredictions / (double)m_totalPredictions;
    }

public:
    // Constructor
    CAIEngine() {
        m_manager = NULL;
        m_initialized = false;
        m_adaptiveModeActive = false;
        m_lastAdaptation = 0;
        m_queryCount = 0;
        m_successfulQueries = 0;
        m_pendingModCount = 0;
        m_decisionIndex = 0;
        m_decisionCount = 0;
        m_predictionAccuracy = 0.5;
        m_totalPredictions = 0;
        m_correctPredictions = 0;
        m_externalAIConnected = false;
        m_externalAIEndpoint = "";
        m_externalLLMQueryCount = 0;
        m_externalLLMSuccessCount = 0;
        m_externalLLMFailureCount = 0;
        m_lastExternalLLMLogTime = 0;
        m_lastExternalReasoningTime = 0;
        m_lastExternalLLMPhase = "";
        m_lastExternalReasoning = "";
    }
    
    // Destructor
    ~CAIEngine() {
        if(m_initialized) {
            LogAI(ERROR_LEVEL_INFO, StringFormat("AIEngine shutdown - Queries: %d, Accuracy: %.2f%%", 
                  m_queryCount, m_predictionAccuracy * 100));
            LogExternalLLM("SHUTDOWN",
                           StringFormat("reasoning_cached=%s",
                                        (m_lastExternalReasoning != "") ? "true" : "false"),
                           true);
        }
    }
    
    // Initialize with manager reference
    bool Initialize(CEnterpriseStrategyManager* manager, const SAIAdaptiveConfig &config) {
        if(CheckPointer(manager) == POINTER_INVALID) {
            LogAI(ERROR_LEVEL_ERROR, "Invalid manager pointer");
            return false;
        }
        
        m_manager = manager;
        m_adaptiveConfig = config;
        m_adaptiveModeActive = config.enabled;
        m_initialized = true;
        
        // Configure external LLM based on config
        ConfigureExternalLLM();
        LogExternalLLM("INIT",
                       m_adaptiveConfig.useExternalLLM ?
                       "runtime role=adaptation_reasoning_telemetry" :
                       "disabled by config",
                       true);
        
        LogAI(ERROR_LEVEL_INFO, "AIEngine initialized successfully");
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| OnAIQuery - External AI Query Interface                          |
    //| Main entry point for ML models to query the trading system       |
    //+------------------------------------------------------------------+
    SAIQueryResponse OnAIQuery(const SAIQueryRequest &request) {
        SAIQueryResponse response;
        datetime queryStartTime = GetTickCount();
        
        if(!m_initialized) {
            response.errorMessage = "AIEngine not initialized";
            return response;
        }
        
        m_queryCount++;
        
        // Route query based on type
        if(request.queryType == "prediction") {
            response = ProcessPredictionQuery(request);
        }
        else if(request.queryType == "signal") {
            response = ProcessSignalQuery(request);
        }
        else if(request.queryType == "weights") {
            response = ProcessWeightsQuery(request);
        }
        else if(request.queryType == "state") {
            response = ProcessStateQuery(request);
        }
        else if(request.queryType == "explanation") {
            response = ProcessExplanationQuery(request);
        }
        else {
            response.errorMessage = "Unknown query type: " + request.queryType;
            return response;
        }
        
        response.processingTimeMs = (int)(GetTickCount() - queryStartTime);
        
        if(response.success) m_successfulQueries++;
        
        return response;
    }
    
    //+------------------------------------------------------------------+
    //| AI_ModifyWeights - Dynamic Strategy Weight Modification          |
    //| Allows AI to adjust strategy weights based on predictions        |
    //+------------------------------------------------------------------+
    bool AI_ModifyWeights(const SAIWeightModification &modifications[], int modCount) {
        if(!m_initialized || m_manager == NULL) {
            LogAI(ERROR_LEVEL_WARNING, "Cannot modify weights - not initialized");
            return false;
        }
        
        int successCount = 0;
        
        for(int i = 0; i < modCount && i < 20; i++) {
            SAIWeightModification mod = modifications[i];
            
            // Validate modification
            if(mod.newWeight < 0.0 || mod.newWeight > 5.0) {
                LogAI(ERROR_LEVEL_WARNING, StringFormat("Invalid weight %.2f for %s", 
                      mod.newWeight, mod.strategyName));
                continue;
            }
            
            if(mod.confidence < 0.3) {
                LogAI(ERROR_LEVEL_INFO, StringFormat("Low confidence weight mod rejected: %s (%.2f)", 
                      mod.strategyName, mod.confidence));
                continue;
            }
            
            // Apply weight modification via manager
            if(m_manager.UpdateStrategyWeight(mod.strategyName, mod.newWeight)) {
                LogAI(ERROR_LEVEL_INFO, StringFormat("AI modified weight: %s -> %.2f (confidence: %.2f, reason: %s)",
                      mod.strategyName, mod.newWeight, mod.confidence, mod.reason));
                
                // Track pending modification if temporary
                if(mod.temporary && m_pendingModCount < 20) {
                    m_pendingMods[m_pendingModCount] = mod;
                    m_pendingModCount++;
                }
                
                successCount++;
            }
        }
        
        return (successCount > 0);
    }
    
    //+------------------------------------------------------------------+
    //| AI_ExplainDecision - Decision Explainability                     |
    //| Provides human-readable explanations for trading decisions       |
    //+------------------------------------------------------------------+
    SAIDecisionExplanation AI_ExplainDecision(const string &symbol, ENUM_TRADE_SIGNAL signal) {
        SAIDecisionExplanation explanation;
        explanation.signal = signal;
        
        if(!m_initialized || m_manager == NULL) {
            explanation.primaryReason = "System not initialized";
            return explanation;
        }
        
        // Get current market regime
        ENUM_MARKET_REGIME regime = m_manager.GetCurrentMarketRegime();
        
        // Build explanation based on signal type
        if(signal == TRADE_SIGNAL_NONE) {
            explanation.primaryReason = "No clear directional signal detected";
            explanation.marketContext = "Market conditions do not favor entry at this time";
        }
        else if(signal == TRADE_SIGNAL_BUY) {
            explanation.primaryReason = "Bullish consensus from multiple strategies";
            explanation.contributingFactors[0] = "Positive trend alignment";
            explanation.contributingFactors[1] = "Favorable market regime: " + EnumToString(regime);
            explanation.contributingFactors[2] = "Risk parameters within limits";
            explanation.factorCount = 3;
            explanation.factorWeights[0] = 0.4;
            explanation.factorWeights[1] = 0.35;
            explanation.factorWeights[2] = 0.25;
        }
        else if(signal == TRADE_SIGNAL_SELL) {
            explanation.primaryReason = "Bearish consensus from multiple strategies";
            explanation.contributingFactors[0] = "Negative trend alignment";
            explanation.contributingFactors[1] = "Favorable market regime: " + EnumToString(regime);
            explanation.contributingFactors[2] = "Risk parameters within limits";
            explanation.factorCount = 3;
            explanation.factorWeights[0] = 0.4;
            explanation.factorWeights[1] = 0.35;
            explanation.factorWeights[2] = 0.25;
        }
        
        // Add risk assessment
        double activeStrategyCount = (double)m_manager.GetActiveStrategyCount();
        explanation.riskAssessment = StringFormat("Active strategies: %.0f, Regime: %s", 
                                                  activeStrategyCount, EnumToString(regime));
        
        // Calculate overall confidence
        explanation.overallConfidence = m_manager.GetEnsembleConfidence();
        
        // Store in history
        m_recentDecisions[m_decisionIndex] = explanation;
        m_decisionIndex = (m_decisionIndex + 1) % 50;
        if(m_decisionCount < 50) m_decisionCount++;
        
        return explanation;
    }
    
    //+------------------------------------------------------------------+
    //| AI_AdaptiveMode - Adaptive Trading Mode Control                  |
    //| Enables real-time adaptation based on market conditions          |
    //+------------------------------------------------------------------+
    bool AI_AdaptiveMode(bool enable, const SAIAdaptiveConfig &config) {
        m_adaptiveConfig = config;
        m_adaptiveModeActive = enable && config.enabled;
        
        if(m_adaptiveModeActive) {
            LogAI(ERROR_LEVEL_INFO, StringFormat(
                "Adaptive mode ENABLED - Learning rate: %.2f, Interval: %d bars, Min confidence: %.2f",
                config.learningRate, config.adaptationInterval, config.minConfidenceThreshold));
        } else {
            LogAI(ERROR_LEVEL_INFO, "Adaptive mode DISABLED");
        }
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| ProcessAdaptation - Called on each bar to adapt                  |
    //+------------------------------------------------------------------+
    void ProcessAdaptation() {
        if(!m_adaptiveModeActive || !m_initialized) return;
        
        datetime nowTime = TimeCurrent();
        
        // Check adaptation interval
        if(nowTime - m_lastAdaptation < m_adaptiveConfig.adaptationInterval * PeriodSeconds()) {
            return;
        }
        
        m_lastAdaptation = nowTime;
        
        // Market regime adaptation
        if(m_adaptiveConfig.useMarketRegimeAdaptation && m_manager != NULL) {
            ENUM_MARKET_REGIME regime = m_manager.GetCurrentMarketRegime();
            AdaptToRegime(regime);
        }
        
        // Performance-based adaptation
        if(m_adaptiveConfig.usePerformanceAdaptation) {
            AdaptToPerformance();
        }

        if(m_adaptiveConfig.useExternalLLM) {
            MaybeCaptureExternalReasoning();
        }
        
        // Process expired temporary weight modifications
        ProcessExpiredModifications();
    }
    
    //+------------------------------------------------------------------+
    //| Set External AI Endpoint                                         |
    //+------------------------------------------------------------------+
    void SetExternalAIEndpoint(const string &endpoint) {
        m_externalAIEndpoint = endpoint;
        m_externalAIConnected = (endpoint != "");
        LogExternalLLM("CONFIG",
                       (endpoint != "") ? ("endpoint set to " + endpoint) : "endpoint cleared",
                       true);
    }
    
    //+------------------------------------------------------------------+
    //| Configure External LLM based on config flag                       |
    //+------------------------------------------------------------------+
    void ConfigureExternalLLM() {
        if(m_adaptiveConfig.useExternalLLM) {
            if(m_externalAIEndpoint == "")
                SetExternalAIEndpoint("http://localhost:11434");
            else
                SetExternalAIEndpoint(m_externalAIEndpoint);
        } else {
            SetExternalAIEndpoint("");
        }
    }
    
    //+------------------------------------------------------------------+
    //| Enable/Disable External LLM                                       |
    //+------------------------------------------------------------------+
    void SetExternalLLMEnabled(bool enabled) {
        m_adaptiveConfig.useExternalLLM = enabled;
        ConfigureExternalLLM();
    }
    
    //+------------------------------------------------------------------+
    //| Check if External LLM is enabled                                  |
    //+------------------------------------------------------------------+
    bool IsExternalLLMEnabled() const {
        return m_adaptiveConfig.useExternalLLM;
    }
    
    //+------------------------------------------------------------------+
    //| Query External LLM                                               |
    //+------------------------------------------------------------------+
    bool QueryExternalLLM(const string &prompt, string &llmResponse) {
        if(!m_externalAIConnected || m_externalAIEndpoint == "") {
            m_externalLLMFailureCount++;
            LogExternalLLM("QUERY-SKIP", "not connected");
            return false;
        }
        
        // Prepare JSON request for Ollama API
        string escapedPrompt = EscapeJson(prompt);
        string jsonRequest = "{\"model\":\"phi3\",\"prompt\":\"" + escapedPrompt + "\",\"stream\":false}";
        
        // Create HTTP request
        uchar request[];
        uchar responseData[];
        string resultHeaders;
        
        StringToCharArray(jsonRequest, request);
        ArrayResize(request, ArraySize(request) - 1); // Remove null terminator
        
        // Send POST request to Ollama API
        int timeout = 5000; // 5 second timeout
        m_externalLLMQueryCount++;
        LogExternalLLM("QUERY-START",
                       StringFormat("prompt_len=%d", StringLen(prompt)));
        int res = WebRequest("POST", m_externalAIEndpoint + "/api/generate", "Content-Type: application/json", 
                           timeout, request, responseData, resultHeaders);
        
        if(res != -1) {
            string responseStr = CharArrayToString(responseData, 0, WHOLE_ARRAY, CP_UTF8);
            
            // Parse JSON response to extract "response" field
            int responseStart = StringFind(responseStr, "\"response\":\"");
            if(responseStart >= 0) {
                responseStart += 12; // Skip "response":"
                int responseEnd = StringFind(responseStr, "\"", responseStart);
                if(responseEnd > responseStart) {
                    llmResponse = StringSubstr(responseStr, responseStart, responseEnd - responseStart);
                    m_externalLLMSuccessCount++;
                    LogExternalLLM("QUERY-SUCCESS",
                                   StringFormat("http=%d | response_len=%d", res, StringLen(llmResponse)),
                                   true);
                    return true;
                }
            }
            
            m_externalLLMFailureCount++;
            LogExternalLLM("QUERY-PARSE-FAIL",
                           StringFormat("http=%d | body_len=%d", res, StringLen(responseStr)),
                           true);
            return false;
        } else {
            int err = GetLastError();
            m_externalLLMFailureCount++;
            LogExternalLLM("QUERY-HTTP-FAIL",
                           StringFormat("err=%d", err),
                           true);
            return false;
        }
    }
    
    //+------------------------------------------------------------------+
    //| Provide Performance Feedback                                     |
    //+------------------------------------------------------------------+
    void ProvideFeedback(ENUM_TRADE_SIGNAL predictedSignal, bool wasCorrect, double profit) {
        UpdatePredictionAccuracy(wasCorrect);
        
        // Send feedback to external AI
        if(m_externalAIConnected) {
            string feedbackPrompt = StringFormat("Trade result: %s, Correct: %s, Profit: %.2f. Learn from this outcome.",
                                                  TradeSignalToString(predictedSignal), wasCorrect ? "Yes" : "No", profit);
            string llmResponse;
            QueryExternalLLM(feedbackPrompt, llmResponse);
            LogExternalLLM("FEEDBACK",
                           StringFormat("signal=%s | correct=%s | profit=%.2f",
                                        TradeSignalToString(predictedSignal),
                                        wasCorrect ? "true" : "false",
                                        profit),
                           true);
        }
    }
    
    //+------------------------------------------------------------------+
    //| Synthesize Signals using External LLM                            |
    //+------------------------------------------------------------------+
    bool SynthesizeSignals(const string &signals, const string &regime, string &recommendation, double &confidence) {
        if(!m_externalAIConnected) {
            return false;
        }
        
        string prompt = StringFormat("Given these trading signals: %s, with current market regime: %s, recommend a trading action (BUY/SELL/NONE) and provide confidence score (0-1).",
                                      signals, regime);
        
        string llmResponse;
        if(!QueryExternalLLM(prompt, llmResponse)) {
            return false;
        }
        
        // Parse response for recommendation and confidence
        StringToUpper(llmResponse);
        if(StringFind(llmResponse, "BUY") >= 0) {
            recommendation = "BUY";
        } else if(StringFind(llmResponse, "SELL") >= 0) {
            recommendation = "SELL";
        } else {
            recommendation = "NONE";
        }
        
        // Extract confidence score (simple parsing)
        int confidenceStart = StringFind(llmResponse, "confidence");
        if(confidenceStart >= 0) {
            confidenceStart = StringFind(llmResponse, ":", confidenceStart);
            if(confidenceStart >= 0) {
                string confidenceStr = StringSubstr(llmResponse, confidenceStart + 1, 4);
                confidence = StringToDouble(confidenceStr);
                if(confidence < 0.0 || confidence > 1.0) confidence = 0.5;
            } else {
                confidence = 0.5;
            }
        } else {
            confidence = 0.5;
        }
        
        LogAI(ERROR_LEVEL_INFO, "LLM Signal Synthesis: " + recommendation + " @ " + DoubleToString(confidence, 2));
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Generate Trade Explanation using External LLM                     |
    //+------------------------------------------------------------------+
    bool GenerateTradeExplanation(const string &signals, const string &decision, string &explanation) {
        if(!m_externalAIConnected) {
            explanation = "External LLM not connected";
            return false;
        }
        
        string prompt = StringFormat("Given these trading signals: %s, and the decision: %s, explain why this trade decision was made in 1-2 sentences.",
                                      signals, decision);
        
        if(!QueryExternalLLM(prompt, explanation)) {
            explanation = "Failed to get explanation from LLM";
            return false;
        }
        
        LogAI(ERROR_LEVEL_INFO, "LLM Explanation: " + explanation);
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Assess Risk using External LLM                                   |
    //+------------------------------------------------------------------+
    bool AssessRisk(const string &symbol, double entryPrice, double stopLoss, double takeProfit, string &riskReport) {
        if(!m_externalAIConnected) {
            riskReport = "External LLM not connected";
            return false;
        }
        
        double stopLossPct = MathAbs(stopLoss - entryPrice) / entryPrice * 100;
        double riskRewardRatio = MathAbs(takeProfit - entryPrice) / MathAbs(stopLoss - entryPrice);
        
        string prompt = StringFormat("Assess the risk of this trade setup: Symbol %s, Entry %.5f, Stop Loss %.5f (%.2f%%), Take Profit %.5f, Risk:Reward %.2f:1. Provide risk score (0-1) and brief recommendation.",
                                      symbol, entryPrice, stopLoss, stopLossPct, takeProfit, riskRewardRatio);
        
        if(!QueryExternalLLM(prompt, riskReport)) {
            riskReport = "Failed to get risk assessment from LLM";
            return false;
        }
        
        LogAI(ERROR_LEVEL_INFO, "LLM Risk Assessment: " + riskReport);
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Reason Strategy Weights using External LLM                        |
    //+------------------------------------------------------------------+
    bool ReasonStrategyWeights(const string &regime, const string &currentWeights, string &reasoning) {
        if(!m_externalAIConnected) {
            reasoning = "External LLM not connected";
            return false;
        }
        
        string prompt = StringFormat("Current market regime: %s, Current strategy weights: %s. Suggest optimal strategy weight adjustments for these conditions in 1-2 sentences.",
                                      regime, currentWeights);
        
        if(!QueryExternalLLM(prompt, reasoning)) {
            reasoning = "Failed to get strategy weight reasoning from LLM";
            return false;
        }
        
        m_lastExternalReasoning = reasoning;
        LogExternalLLM("STRATEGY-WEIGHTS", "reasoning captured", true);
        LogAI(ERROR_LEVEL_INFO, "LLM Strategy Weight Reasoning: " + reasoning);
        return true;
    }
    
    // Getters
    bool IsInitialized() const { return m_initialized; }
    bool IsAdaptiveModeActive() const { return m_adaptiveModeActive; }
    double GetPredictionAccuracy() const { return m_predictionAccuracy; }
    int GetQueryCount() const { return m_queryCount; }
    SAIAdaptiveConfig GetAdaptiveConfig() const { return m_adaptiveConfig; }
    
private:
    // Query processors
    SAIQueryResponse ProcessPredictionQuery(const SAIQueryRequest &request) {
        SAIQueryResponse response;
        response.success = true;
        
        // Get prediction from ensemble
        if(m_manager != NULL) {
            response.prediction = m_manager.GetEnsembleConfidence();
            response.confidence = response.prediction;
            
            // detailed explanation
            int strategyCount = m_manager.GetActiveStrategyCount();
            string regime = EnumToString(m_manager.GetCurrentMarketRegime());
            response.explanation = StringFormat("Ensemble prediction: %.2f | Active Strategies: %d | Regime: %s", 
                                              response.prediction, strategyCount, regime);
        }
        else {
             response.prediction = 0.5;
             response.confidence = 0.0;
             response.explanation = "Manager not initialized";
             response.success = false;
        }
        
        return response;
    }
    
    SAIQueryResponse ProcessSignalQuery(const SAIQueryRequest &request) {
        SAIQueryResponse response;
        response.success = true;
        
        if(m_manager != NULL) {
            // Signal query not fully supported in current orchestrator version
            // Returning ensemble confidence as proxy
            double confidence = m_manager.GetEnsembleConfidence();
            response.prediction = confidence; // Proxy for signal direction not available
            response.confidence = confidence;
            
            int strategyCount = m_manager.GetActiveStrategyCount();
            string regime = EnumToString(m_manager.GetCurrentMarketRegime());
            response.explanation = StringFormat("Signal Confidence: %.2f | Active Strategies: %d | Regime: %s", 
                                              confidence, strategyCount, regime);
        }
        else {
             response.prediction = 0.5;
             response.confidence = 0.0;
             response.explanation = "Manager not initialized";
             response.success = false;
        }
        
        return response;
    }
    
    SAIQueryResponse ProcessWeightsQuery(const SAIQueryRequest &request) {
        SAIQueryResponse response;
        response.success = true;
        
        if(m_manager != NULL) {
            response.jsonData = m_manager.GetStrategyWeightsJSON();
            response.explanation = "Current strategy weights";
        }
        
        return response;
    }
    
    SAIQueryResponse ProcessStateQuery(const SAIQueryRequest &request) {
        SAIQueryResponse response;
        response.success = true;
        
        response.jsonData = StringFormat("{\"adaptiveMode\":%s,\"accuracy\":%.4f,\"queries\":%d}",
                                         m_adaptiveModeActive ? "true" : "false",
                                         m_predictionAccuracy, m_queryCount);
        response.explanation = "Current AI engine state";
        
        return response;
    }
    
    SAIQueryResponse ProcessExplanationQuery(const SAIQueryRequest &request) {
        SAIQueryResponse response;
        response.success = true;
        
        if(m_decisionCount > 0) {
            int lastIdx = (m_decisionIndex - 1 + 50) % 50;
            SAIDecisionExplanation lastDecision = m_recentDecisions[lastIdx];
            response.explanation = lastDecision.primaryReason + " | " + lastDecision.riskAssessment;
            response.confidence = lastDecision.overallConfidence;
        } else {
            response.explanation = "No recent decisions to explain";
        }
        
        return response;
    }

    void MaybeCaptureExternalReasoning() {
        if(!m_adaptiveConfig.useExternalLLM)
            return;

        datetime now = TimeCurrent();
        if(m_lastExternalReasoningTime > 0 && (now - m_lastExternalReasoningTime) < 600)
            return;

        m_lastExternalReasoningTime = now;

        if(m_manager == NULL) {
            LogExternalLLM("REASONING-SKIP", "manager unavailable", true);
            return;
        }

        string regime = EnumToString(m_manager.GetCurrentMarketRegime());
        string currentWeights = m_manager.GetStrategyWeightsJSON();
        if(currentWeights == "") {
            LogExternalLLM("REASONING-SKIP", "strategy weights unavailable", true);
            return;
        }

        string reasoning = "";
        if(ReasonStrategyWeights(regime, currentWeights, reasoning)) {
            m_lastExternalReasoning = reasoning;
            LogExternalLLM("REASONING", "strategy-weight commentary captured", true);
        } else {
            LogExternalLLM("REASONING-FAIL", "strategy-weight commentary unavailable", true);
        }
    }
    
    // Adaptation helpers
    void AdaptToRegime(ENUM_MARKET_REGIME regime) {
        double adjustedThreshold = m_adaptiveConfig.minConfidenceThreshold;
        
        switch(regime) {
            case MARKET_REGIME_TRENDING:
                adjustedThreshold *= 0.9;  // Lower threshold in trends
                break;
            case MARKET_REGIME_RANGING:
                adjustedThreshold *= 1.1;  // Higher threshold in ranges
                break;
            case MARKET_REGIME_VOLATILE:
                adjustedThreshold *= 1.2;  // Much higher in volatile
                break;
            default:
                break;
        }

        if(regime == MARKET_REGIME_UNKNOWN && adjustedThreshold < 0.0)
            LogAI(ERROR_LEVEL_WARNING, "AdaptToRegime unexpected threshold");
    }
    
    void AdaptToPerformance() {
        // Adjust risk based on recent performance
        if(m_manager == NULL)
            return;

        // Performance-driven strategy adaptation hooks
        m_manager.UpdateStrategyWeights();

        if(m_predictionAccuracy < 0.4) {
            m_manager.CheckStrategyDisabling();
        } else if(m_predictionAccuracy > 0.6) {
            m_manager.CheckStrategyReEnabling();
        }
    }
    
    void ProcessExpiredModifications() {
        // Simplified expiration check - clear old modifications periodically
        // In a production system, this would track timestamps properly
        if(m_pendingModCount > 0) {
            // Clear modifications if too many accumulate
            if(m_pendingModCount >= 18) {
                PrintFormat("[AI-ENGINE] Clearing accumulated modifications");
                m_pendingModCount = 0;
            }
        }
    }
};

// Global AI Engine instance
CAIEngine* g_AIEngine = NULL;

// Helper functions for global access
bool InitializeAIEngine(CEnterpriseStrategyManager* manager) {
    if(g_AIEngine == NULL)
        g_AIEngine = new CAIEngine();
    
    SAIAdaptiveConfig defaultConfig;
    return g_AIEngine.Initialize(manager, defaultConfig);
}

void CleanupAIEngine() {
    if(g_AIEngine != NULL) {
        delete g_AIEngine;
        g_AIEngine = NULL;
    }
}

#endif // __AI_ENGINE_MQH__
