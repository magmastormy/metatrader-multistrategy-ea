// AIEngine.mqh - the strategy-weight adaptation driver owned by CEAOrchestrator.
// Once per adaptation interval it re-weights each symbol manager and, when an external LLM
// endpoint is configured, asks that endpoint for weight commentary and applies the numbers it names.
#ifndef AI_ENGINE_MQH
#define AI_ENGINE_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "../Management/EnterpriseStrategyManager.mqh"

class CEnhancedErrorHandler;

struct SAIAdaptiveConfig {
    bool enabled;                     // Adaptive mode enabled
    int adaptationInterval;           // Bars between adaptations
    bool usePerformanceAdaptation;    // Adapt based on performance
    bool useExternalLLM;              // Use external LLM for advanced reasoning (default: false)
    
    SAIAdaptiveConfig() {
        enabled = true;
        adaptationInterval = 5;
        usePerformanceAdaptation = true;
        useExternalLLM = false;  // Default to not using external LLM
    }
};

class CAIEngine {
private:
    // Support for multiple managers (one per symbol)
    CEnterpriseStrategyManager* m_managers[];
    string m_managerSymbols[];
    int m_managerCount;
    
    SAIAdaptiveConfig m_adaptiveConfig;       // Adaptive mode configuration
    
    bool m_initialized;
    bool m_adaptiveModeActive;
    datetime m_lastAdaptation;
    bool m_externalAIConnected;
    string m_externalAIEndpoint;
    int m_externalLLMQueryCount;
    int m_externalLLMSuccessCount;
    int m_externalLLMFailureCount;
    datetime m_lastExternalLLMLogTime;
    datetime m_lastExternalReasoningTime;
    string m_lastExternalLLMPhase;
    string m_lastExternalReasoning;
    
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

public:
    CAIEngine() {
        m_initialized = false;
        m_adaptiveModeActive = false;
        m_lastAdaptation = 0;
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
    
    ~CAIEngine() {
        if(m_initialized) {
            LogExternalLLM("SHUTDOWN",
                           StringFormat("reasoning_cached=%s",
                                        (m_lastExternalReasoning != "") ? "true" : "false"),
                           true);
        }
    }
    
    bool Initialize(CEnterpriseStrategyManager* &managers[], const string &symbols[], int count, const SAIAdaptiveConfig &config) {
        if(count <= 0) {
            LogAI(ERROR_LEVEL_ERROR, "No managers provided");
            return false;
        }
        
        m_managerCount = count;
        ArrayResize(m_managers, count);
        ArrayResize(m_managerSymbols, count);
        for(int i = 0; i < count; i++) {
            if(CheckPointer(managers[i]) == POINTER_INVALID) {
                LogAI(ERROR_LEVEL_ERROR, StringFormat("Invalid manager pointer at index %d", i));
                return false;
            }
            m_managers[i] = managers[i];
            m_managerSymbols[i] = symbols[i];
        }
        m_adaptiveConfig = config;
        m_adaptiveModeActive = config.enabled;
        m_initialized = true;
        
        ConfigureExternalLLM();
        LogExternalLLM("INIT",
                       m_adaptiveConfig.useExternalLLM ?
                       "runtime role=adaptation_reasoning_telemetry" :
                       "disabled by config",
                       true);
        
        LogAI(ERROR_LEVEL_INFO, StringFormat("AIEngine initialized successfully with %d managers", count));
        return true;
    }
    
    void ProcessAdaptation() {
        if(!m_adaptiveModeActive || !m_initialized) return;
        
        datetime nowTime = TimeCurrent();
        
        if(nowTime - m_lastAdaptation < m_adaptiveConfig.adaptationInterval * PeriodSeconds()) {
            return;
        }
        
        m_lastAdaptation = nowTime;
        
        if(m_adaptiveConfig.usePerformanceAdaptation) {
            AdaptToPerformance();
        }

        if(m_adaptiveConfig.useExternalLLM) {
            MaybeCaptureExternalReasoning();
        }
    }
    
    void SetExternalAIEndpoint(const string &endpoint) {
        m_externalAIEndpoint = endpoint;
        m_externalAIConnected = (endpoint != "");
        LogExternalLLM("CONFIG",
                       (endpoint != "") ? ("endpoint set to " + endpoint) : "endpoint cleared",
                       true);
    }
    
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
    
    bool QueryExternalLLM(const string &prompt, string &llmResponse) {
        if(!m_externalAIConnected || m_externalAIEndpoint == "") {
            m_externalLLMFailureCount++;
            LogExternalLLM("QUERY-SKIP", "not connected");
            return false;
        }
        
        // Prepare JSON request for Ollama API
        string escapedPrompt = EscapeJson(prompt);
        string jsonRequest = "{\"model\":\"phi3\",\"prompt\":\"" + escapedPrompt + "\",\"stream\":false}";
        
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
    
private:
    void MaybeCaptureExternalReasoning() {
        if(!m_adaptiveConfig.useExternalLLM)
            return;

        datetime now = TimeCurrent();
        if(m_lastExternalReasoningTime > 0 && (now - m_lastExternalReasoningTime) < 600)
            return;

        m_lastExternalReasoningTime = now;

        // Use ALL managers for external LLM reasoning (not just first)
        if(m_managerCount <= 0) {
            LogExternalLLM("REASONING-SKIP", "no managers available", true);
            return;
        }

        for(int m = 0; m < m_managerCount; m++) {
            if(m_managers[m] == NULL) continue;
            
            string regime = EnumToString(m_managers[m].GetCurrentMarketRegime());
            string currentWeights = m_managers[m].GetStrategyWeightsJSON();
            if(currentWeights == "") {
                LogExternalLLM("REASONING-SKIP", "strategy weights unavailable for " + m_managerSymbols[m], true);
                continue;
            }

            string reasoning = "";
            if(ReasonStrategyWeights(regime, currentWeights, reasoning)) {
                m_lastExternalReasoning = reasoning;
                LogExternalLLM("REASONING", "strategy-weight commentary captured for " + m_managerSymbols[m], true);
                
                // ACT ON LLM REASONING: Parse and apply weight adjustments
                ApplyLLMReasoningToWeights(m_managers[m], reasoning);
            } else {
                LogExternalLLM("REASONING-FAIL", "strategy-weight commentary unavailable for " + m_managerSymbols[m], true);
            }
        }
    }

    void ApplyLLMReasoningToWeights(CEnterpriseStrategyManager* manager, const string &reasoning) {
        if(manager == NULL || reasoning == "")
            return;

        // Expected format: "Increase MOMENTUM weight to 1.5, decrease MEAN_REVERSION to 0.8"
        // or JSON-like format: {"MOMENTUM": 1.5, "MEAN_REVERSION": 0.8}
        
        string adjustedReasoning = reasoning;
        StringToLower(adjustedReasoning);
        
        // Simple keyword-based parsing
        string strategies[] = {"momentum", "trend", "supportresistance", "ict", "candlestick", "unicorn", "powerofthree", 
                              "meanreversion", "volatilitybreakout", "fvgscalper", "turtlesoup", "breakerblock",
                              "nyopengap", "asianrangebreak", "statisticalarbitrage", "liquiditysweep",
                              "rangecompression", "exitingoptimizer", "kalmanmr", "changepointdetect",
                              "fourstateregime", "voltargeting", "neuronetwork", "transformer", "ensemble", "onnx"};
        
        for(int s = 0; s < ArraySize(strategies); s++) {
            string strat = strategies[s];
            int pos = StringFind(adjustedReasoning, strat);
            if(pos >= 0) {
                string afterStrat = StringSubstr(adjustedReasoning, pos + StringLen(strat));
                StringTrimLeft(afterStrat);
                
                // Try to find a number pattern (e.g., "1.5", "0.8", "to 1.2")
                int numStart = -1;
                for(int i = 0; i < StringLen(afterStrat); i++) {
                    ushort c = StringGetCharacter(afterStrat, i);
                    if((c >= '0' && c <= '9') || c == '.') {
                        numStart = i;
                        break;
                    }
                }
                
                if(numStart >= 0) {
                    string numStr = StringSubstr(afterStrat, numStart);
                    int numEnd = 0;
                    for(int i = 0; i < StringLen(numStr); i++) {
                        ushort c = StringGetCharacter(numStr, i);
                        if(!((c >= '0' && c <= '9') || c == '.')) {
                            numEnd = i;
                            break;
                        }
                    }
                    if(numEnd == 0) numEnd = StringLen(numStr);
                    numStr = StringSubstr(numStr, 0, numEnd);
                    
                    double newWeight = StringToDouble(numStr);
                    if(newWeight > 0.0 && newWeight <= 5.0) {
                        string properName = GetProperStrategyName(strat);
                        if(properName != "") {
                            bool success = manager.UpdateStrategyWeight(properName, newWeight);
                            if(success) {
                                LogExternalLLM("WEIGHT-APPLIED", StringFormat("Applied LLM weight: %s -> %.2f", properName, newWeight), true);
                                LogAI(ERROR_LEVEL_INFO, StringFormat("LLM weight adjustment: %s -> %.2f", properName, newWeight));
                            }
                        }
                    }
                }
            }
        }
    }

    string GetProperStrategyName(const string &lowerName) {
        if(lowerName == "momentum") return "Momentum";
        if(lowerName == "trend") return "Trend";
        if(lowerName == "supportresistance") return "Support/Resistance";
        if(lowerName == "ict") return "Unified ICT";
        if(lowerName == "candlestick") return "Candlestick";
        if(lowerName == "unicorn") return "Unicorn Model";
        if(lowerName == "powerofthree") return "Power of Three";
        if(lowerName == "meanreversion") return "Mean Reversion";
        if(lowerName == "volatilitybreakout") return "Volatility Breakout";
        if(lowerName == "fvgscalper") return "FVG Scalper";
        if(lowerName == "turtlesoup") return "Turtle Soup";
        if(lowerName == "breakerblock") return "Breaker Block";
        if(lowerName == "nyopengap") return "NY Open Gap";
        if(lowerName == "asianrangebreak") return "Asian Range Break";
        if(lowerName == "statisticalarbitrage") return "Statistical Arbitrage";
        if(lowerName == "liquiditysweep") return "Liquidity Sweep";
        if(lowerName == "rangecompression") return "Range Compression";
        if(lowerName == "exitingoptimizer") return "Exit Optimizer";
        if(lowerName == "kalmanmr") return "Kalman MR";
        if(lowerName == "changepointdetect") return "Changepoint Detect";
        if(lowerName == "fourstateregime") return "Four State Regime";
        if(lowerName == "voltargeting") return "Vol Targeting";
        if(lowerName == "neuronetwork") return "Neural Network AI";
        if(lowerName == "transformer") return "Transformer AI";
        if(lowerName == "ensemble") return "Ensemble AI";
        if(lowerName == "onnx") return "ONNX AI";
        return "";
    }
    
    void AdaptToPerformance() {
        // Parking and re-enabling is the orchestrator's 60 s governance sweep, not this loop: the
        // accuracy reading those gates tested never had a writer here.
        for(int m = 0; m < m_managerCount; m++) {
            if(m_managers[m] == NULL) continue;
            m_managers[m].UpdateStrategyWeights();
        }
    }
};


#endif // __AI_ENGINE_MQH__
