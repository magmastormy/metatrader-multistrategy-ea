//+------------------------------------------------------------------+
//| AI Integration Hub - Bridge Between AI Components and Trading  |
//| Unifies AI predictions with traditional strategies             |
//+------------------------------------------------------------------+
#ifndef __AI_INTEGRATION_HUB_MQH__
#define __AI_INTEGRATION_HUB_MQH__

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "HTTPClient.mqh"
#include "../../AIModules/NextGenStrategyBrain.mqh"
#include "../../AIModules/UncertaintyQuantifier.mqh"
#include "../../AIModules/PythonBridge.mqh"
#include <Arrays/ArrayDouble.mqh>

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CModeManager;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;
class CAIStrategyOrchestrator;

//+------------------------------------------------------------------+
//| Unified Trading Signal Structure                               |
//+------------------------------------------------------------------+
struct SUnifiedTradeSignal {
    ENUM_TRADE_SIGNAL finalSignal;         // Final unified signal
    double confidence;                     // Overall confidence (0-1)
    double aiWeight;                       // AI contribution weight
    double traditionalWeight;              // Traditional strategy weight
    
    // AI Components
    SEnhancedTradeSignal aiSignal;         // AI-generated signal
    ENUM_MARKET_REGIME marketRegime;       // Current market regime
    double regimeConfidence;               // Regime detection confidence
    
    // Traditional Components
    ENUM_TRADE_SIGNAL traditionalSignal;   // Traditional strategy signal
    double traditionalConfidence;          // Traditional signal confidence
    
    // Risk Management
    double riskAdjustedSize;               // AI-adjusted position size
    double maxUncertaintyThreshold;        // Maximum allowed uncertainty
    bool passesAIValidation;               // AI validation result
    
    // Performance Feedback
    string reasoning;                      // Combined reasoning
    datetime timestamp;                    // Signal generation time
    
    SUnifiedTradeSignal() {
        finalSignal = TRADE_SIGNAL_NONE;
        confidence = 0.0;
        aiWeight = 0.5;
        traditionalWeight = 0.5;
        marketRegime = MARKET_REGIME_UNKNOWN;
        regimeConfidence = 0.0;
        traditionalSignal = TRADE_SIGNAL_NONE;
        traditionalConfidence = 0.0;
        riskAdjustedSize = 0.0;
        maxUncertaintyThreshold = 0.4;
        passesAIValidation = false;
        reasoning = "";
        timestamp = 0;
    }
};

//+------------------------------------------------------------------+
//| AI Performance Tracking Structure                              |
//+------------------------------------------------------------------+
struct SAIPerformanceMetrics {
    int totalSignals;                      // Total AI signals generated
    int successfulSignals;                 // Successful AI signals
    double accuracy;                       // AI signal accuracy
    double avgConfidence;                  // Average AI confidence
    double avgUncertainty;                 // Average uncertainty
    datetime lastUpdate;                   // Last performance update
    
    // Learning metrics
    double learningRate;                   // AI learning rate
    double adaptationScore;                // Market adaptation score
    int consecutiveWins;                   // Consecutive winning signals
    int consecutiveLosses;                 // Consecutive losing signals
    
    SAIPerformanceMetrics() {
        totalSignals = 0;
        successfulSignals = 0;
        accuracy = 0.0;
        avgConfidence = 0.0;
        avgUncertainty = 0.0;
        lastUpdate = 0;
        learningRate = 0.01;
        adaptationScore = 0.5;
        consecutiveWins = 0;
        consecutiveLosses = 0;
    }
};

//+------------------------------------------------------------------+
//| AI Integration Hub Class                                       |
//+------------------------------------------------------------------+
class CAIIntegrationHub
{
public:
    CAIIntegrationHub();
    ~CAIIntegrationHub();

    bool Initialize(const string &symbolName, const ENUM_TIMEFRAMES timeframe);
    void Deinit();

    bool GenerateAISignal(SEnhancedTradeSignal &aiSignal);
    bool GetUnifiedSignal(ENUM_TRADE_SIGNAL traditionalSignal, double traditionalConfidence, SUnifiedTradeSignal &unifiedSignal);
    void ProvideFeedback(bool success, double actualReturn, double predictedReturn);
    string GetPerformanceReport() const;
    void SetAIParameters(double confidenceThreshold, double uncertaintyThreshold, double aiWeight, bool useValidation, bool useRegimeAdaptation);
    bool IsAIReady() const;
    ENUM_MARKET_REGIME GetCurrentRegime() const;
    void EnableHybridAI(bool enablePython, bool enableCpp, string pythonPath, string cppPath);
    
    // Simplified interface for EA
    double GetAIPrediction(const double &marketData[], int dataSize, string &reasoning);
    
    // Train models with new data
    bool TrainModels(const double &marketData[], double target);

private:
    bool UpdateDataCaches();
    bool GenerateAISignalInternal(SEnhancedTradeSignal &aiSignal);
    bool ValidateIndicators() const;
    void RecordSignalOutcome(const SEnhancedTradeSignal &aiSignal, bool success);
    void AdaptToMarketRegime(SUnifiedTradeSignal &unifiedSignal);
    void CombineSignals(SUnifiedTradeSignal &unifiedSignal);
    void CalculateAIAdjustedSize(SUnifiedTradeSignal &unifiedSignal);
    void GenerateUnifiedReasoning(SUnifiedTradeSignal &unifiedSignal);
    void UpdatePerformanceTracking(const SUnifiedTradeSignal &unifiedSignal);
    void AdaptiveLearning(bool success, double actualReturn, double predictedReturn);

    bool CallPythonAI(const double &marketData[], double &signal, double &confidence, string &reasoning);
    bool CallCppAI(const double &marketData[], double &signal, double &confidence);

    // HTTP Client for Python AI Server
    CHTTPClient* m_httpClient;
    string m_pythonServerUrl;
    bool m_pythonServerHealthy;

    // Python bridge (socket/ZMQ)
    CPythonBridge* m_pythonBridge;
    string m_pythonHost;
    int    m_pythonPort;

    // Cached market series
    CArrayDouble m_priceHistory;
    CArrayDouble m_volumeHistory;
    CArrayDouble m_indicatorBuffer;

    // AI configuration
    double m_aiConfidenceThreshold;
    double m_aiUncertaintyThreshold;
    double m_aiWeight;
    bool   m_useValidation;
    bool   m_useRegimeAdaptation;

    // Hybrid AI state
    bool   m_pythonAIEnabled;
    bool   m_cppAIEnabled;
    bool   m_pythonHealthy;
    bool   m_cppHealthy;
    string m_pythonScriptPath;
    string m_cppBridgePath;

    // Market/AI runtime state
    ENUM_MARKET_REGIME m_currentRegime;
    SAIPerformanceMetrics m_aiMetrics;
    CArrayDouble m_confidenceHistory;
    CArrayDouble m_uncertaintyHistory;
    datetime m_lastDataUpdate;
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;

    // Error handling
    CEnhancedErrorHandler m_errorHandler;

    // Helpers
    bool   BuildMarketDataJson(string &marketDataJson) const;
    bool   ExtractJsonString(const string &json, const string key, string &value) const;
    bool   ExtractJsonNumber(const string &json, const string key, double &value) const;
    bool   ExtractDataBlock(const string &json, string &dataBlock) const;
    string TimeframeToString(ENUM_TIMEFRAMES timeframe) const;
};

// Global AI Integration Hub instance
CAIIntegrationHub* g_aiHub = NULL;

//+------------------------------------------------------------------+
//| Initialize AI Integration Hub                                   |
//+------------------------------------------------------------------+
bool AIHubInit(string symbolName, ENUM_TIMEFRAMES timeframe) {
    if (g_aiHub != NULL) {
        delete g_aiHub;
        g_aiHub = NULL;
    }
    
    g_aiHub = new CAIIntegrationHub();
    if (g_aiHub != NULL) {
        return g_aiHub.Initialize(symbolName, timeframe);
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get Unified Trading Signal                                     |
//+------------------------------------------------------------------+
bool AIHubGetUnifiedSignal(ENUM_TRADE_SIGNAL traditionalSignal, 
                           double traditionalConfidence,
                           SUnifiedTradeSignal &unifiedSignal) 
{
    if (g_aiHub == NULL) {
        Print("[ERROR] AI Integration Hub not initialized");
        return false;
    }
    
    return g_aiHub.GetUnifiedSignal(traditionalSignal, traditionalConfidence, unifiedSignal);
}

bool AIHubGenerateAISignal(SEnhancedTradeSignal &aiSignal)
{
    if(g_aiHub == NULL)
    {
        Print("[ERROR] AI Integration Hub not initialized");
        return false;
    }

    return g_aiHub.GenerateAISignal(aiSignal);
}

//+------------------------------------------------------------------+
//| Provide Performance Feedback                                   |
//+------------------------------------------------------------------+
void AIHubProvideFeedback(bool signalSuccess, double actualReturn, double predictedReturn = 0.0) {
    if (g_aiHub != NULL) {
        g_aiHub.ProvideFeedback(signalSuccess, actualReturn, predictedReturn);
    }
}

//+------------------------------------------------------------------+
//| Get AI Performance Report                                      |
//+------------------------------------------------------------------+
string AIHubGetReport() {
    if (g_aiHub == NULL) {
        return "AI Integration Hub not initialized";
    }
    return g_aiHub.GetPerformanceReport();
}

//+------------------------------------------------------------------+
//| Configure AI Parameters                                        |
//+------------------------------------------------------------------+
void AIHubSetParameters(double confidenceThreshold, 
                        double uncertaintyThreshold, 
                        double aiWeight, 
                        bool useValidation, 
                        bool useRegimeAdaptation) 
{
    if (g_aiHub != NULL) {
        g_aiHub.SetAIParameters(confidenceThreshold, 
                              uncertaintyThreshold, 
                              aiWeight, 
                              useValidation, 
                              useRegimeAdaptation);
    }
}

//+------------------------------------------------------------------+
//| Check if AI Hub is Ready                                       |
//+------------------------------------------------------------------+
bool AIHubIsReady() {
    return (g_aiHub != NULL) && g_aiHub.IsAIReady();
}

//+------------------------------------------------------------------+
//| Get Current Market Regime                                      |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME AIHubGetCurrentRegime() {
    return (g_aiHub != NULL) ? g_aiHub.GetCurrentRegime() : MARKET_REGIME_UNKNOWN;
}

//+------------------------------------------------------------------+
//| Call Python AI Implementation                                      |
//+------------------------------------------------------------------+
bool CAIIntegrationHub::CallPythonAI(const double &marketData[], double &signal, double &confidence, string &reasoning)
{
    if(!m_pythonAIEnabled)
    {
        reasoning = "Python AI disabled";
        return false;
    }

    // Validate input data
    int dataSize = ArraySize(marketData);
    if(dataSize == 0)
    {
        reasoning = "No market data provided";
        return false;
    }

    // Initialize bridge if needed
    if(m_pythonBridge == NULL)
    {
        m_pythonBridge = new CPythonBridge(m_pythonHost, m_pythonPort);
        if(!m_pythonBridge.Handshake())
        {
            reasoning = "Python AI handshake failed";
            delete m_pythonBridge;
            m_pythonBridge = NULL;
            m_pythonHealthy = false;
            return false;
        }
        m_pythonHealthy = true;
    }

    // Periodic heartbeat to ensure connection remains alive
    if(!m_pythonBridge.Heartbeat())
    {
        delete m_pythonBridge;
        m_pythonBridge = new CPythonBridge(m_pythonHost, m_pythonPort);
        if(!m_pythonBridge.Handshake())
        {
            reasoning = "Python AI heartbeat failed";
            delete m_pythonBridge;
            m_pythonBridge = NULL;
            m_pythonHealthy = false;
            return false;
        }
    }

    string jsonPayload = "{";
    jsonPayload += StringFormat("\"symbol\":\"%s\",", m_symbol);
    jsonPayload += StringFormat("\"timeframe\":\"%s\",", TimeframeToString(m_timeframe));

    string marketJson = "";
    if(!BuildMarketDataJson(marketJson))
    {
        reasoning = "Failed to build market data payload";
        return false;
    }
    jsonPayload += StringFormat("\"market_data\":%s", marketJson);
    jsonPayload += "}";

    string rawResponse = m_pythonBridge.SendRequest("signal_request", jsonPayload);
    if(StringLen(rawResponse) == 0)
    {
        reasoning = "Empty response from Python AI";
        m_pythonHealthy = false;
        return false;
    }

    m_pythonHealthy = true;

    string dataBlock;
    if(!ExtractDataBlock(rawResponse, dataBlock))
    {
        reasoning = "Invalid response format";
        return false;
    }

    double signalValue = 0.0;
    double confidenceValue = 0.0;
    string action = "";
    string responseReason = "";

    ExtractJsonNumber(dataBlock, "signal_value", signalValue);
    ExtractJsonNumber(dataBlock, "confidence", confidenceValue);
    ExtractJsonString(dataBlock, "action", action);
    ExtractJsonString(dataBlock, "reason", responseReason);

    signal = signalValue;
    confidence = confidenceValue;
    reasoning = responseReason;

    Print(StringFormat("[PYTHON-AI] Prediction: action=%s, signal=%.3f, conf=%.3f", action, signal, confidence));

    return true;
}

//+------------------------------------------------------------------+
//| Call C++ AI Implementation                                        |
//+------------------------------------------------------------------+
bool CAIIntegrationHub::CallCppAI(const double &marketData[], double &signal, double &confidence)
{
    if(!m_cppAIEnabled)
    {
        return false;
    }

    // Validate input data
    int dataSize = ArraySize(marketData);
    if(dataSize == 0)
    {
        return false;
    }

    // C++ AI implementation - placeholder for now
    // This would use the NextGenStrategyBrain or TransformerBrain
    // For now, return a neutral signal
    signal = 0.5;
    confidence = 0.0;

    return false; // Not implemented yet, return false to fall back to other methods
}

//+------------------------------------------------------------------+
//| Get AI Prediction (Simplified Interface)                         |
//+------------------------------------------------------------------+
double CAIIntegrationHub::GetAIPrediction(const double &marketData[], int dataSize, string &reasoning)
{
    double signal = 0.0;
    double confidence = 0.0;

    // Try Python AI first
    if(m_pythonAIEnabled && CallPythonAI(marketData, signal, confidence, reasoning))
    {
        return signal;
    }

    // If Python AI fails, try C++ AI
    
    // Fallback to C++ AI
    if(m_cppAIEnabled && CallCppAI(marketData, signal, confidence))
    {
        return signal;
    }
    
    return 0.0;
}

//+------------------------------------------------------------------+
//| Initialize                                                      |
//+------------------------------------------------------------------+
bool CAIIntegrationHub::Initialize(const string &symbolName, const ENUM_TIMEFRAMES timeframe)
{
    m_symbol = symbolName;
    m_timeframe = timeframe;
    m_currentRegime = MARKET_REGIME_RANGING;
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialize                                                    |
//+------------------------------------------------------------------+
void CAIIntegrationHub::Deinit()
{
    // Cleanup if needed
}

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CAIIntegrationHub::CAIIntegrationHub() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_aiConfidenceThreshold(0.65),
    m_aiUncertaintyThreshold(0.3),
    m_aiWeight(0.5),
    m_useValidation(true),
    m_useRegimeAdaptation(true),
    m_currentRegime(MARKET_REGIME_RANGING),
    m_pythonAIEnabled(false),
    m_cppAIEnabled(false),
    m_pythonHealthy(false),
    m_cppHealthy(false),
    m_pythonScriptPath(""),
    m_cppBridgePath(""),
    m_lastDataUpdate(0),
    m_httpClient(NULL),
    m_pythonServerUrl("http://localhost:8000"),
    m_pythonServerHealthy(false),
    m_pythonBridge(NULL),
    m_pythonHost("127.0.0.1"),
    m_pythonPort(8888)
{
    // Initialize HTTP client
    m_httpClient = new CHTTPClient(m_pythonServerUrl, 5000);
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CAIIntegrationHub::~CAIIntegrationHub()
{
    Deinit();
    
    // Cleanup HTTP client
    if(m_httpClient != NULL)
    {
        delete m_httpClient;
        m_httpClient = NULL;
    }

    if(m_pythonBridge != NULL)
    {
        delete m_pythonBridge;
        m_pythonBridge = NULL;
    }
}

//+------------------------------------------------------------------+
//| Get Unified Signal - Combines AI + Traditional Signals          |
//+------------------------------------------------------------------+
bool CAIIntegrationHub::GetUnifiedSignal(ENUM_TRADE_SIGNAL traditionalSignal, double traditionalConfidence, SUnifiedTradeSignal &unifiedSignal)
{
    // Initialize unified signal
    unifiedSignal.finalSignal = TRADE_SIGNAL_NONE;
    unifiedSignal.confidence = 0.0;
    unifiedSignal.traditionalSignal = traditionalSignal;
    unifiedSignal.traditionalConfidence = traditionalConfidence;
    unifiedSignal.timestamp = TimeCurrent();
    unifiedSignal.reasoning = "";
    
    // Generate AI signal
    SEnhancedTradeSignal aiSignal;
    bool hasAISignal = GenerateAISignal(aiSignal);
    
    if(hasAISignal)
    {
        unifiedSignal.aiSignal = aiSignal;
        unifiedSignal.marketRegime = aiSignal.regime;
        unifiedSignal.regimeConfidence = aiSignal.regimeConfidence;
    }
    
    // If no AI signal, use traditional only
    if(!hasAISignal)
    {
        unifiedSignal.finalSignal = traditionalSignal;
        unifiedSignal.confidence = traditionalConfidence * 0.8;  // Slightly reduced without AI
        unifiedSignal.aiWeight = 0.0;
        unifiedSignal.traditionalWeight = 1.0;
        unifiedSignal.reasoning = "Traditional signal only (AI unavailable)";
        unifiedSignal.passesAIValidation = true;
        return (traditionalSignal != TRADE_SIGNAL_NONE);
    }
    
    // Both signals available - combine them intelligently
    double aiScore = 0.0, tradScore = 0.0;
    
    // Convert signals to scores
    if(aiSignal.signal == TRADE_SIGNAL_BUY)
        aiScore = aiSignal.confidence;
    else if(aiSignal.signal == TRADE_SIGNAL_SELL)
        aiScore = -aiSignal.confidence;
    
    if(traditionalSignal == TRADE_SIGNAL_BUY)
        tradScore = traditionalConfidence;
    else if(traditionalSignal == TRADE_SIGNAL_SELL)
        tradScore = -traditionalConfidence;
    
    // Weight the signals (AI weight, Traditional gets remainder)
    double aiW = m_aiWeight;
    double tradW = (1.0 - m_aiWeight);
    double combinedScore = (aiScore * aiW) + (tradScore * tradW);
    
    // Determine final signal
    if(combinedScore > 0.5)
    {
        unifiedSignal.finalSignal = TRADE_SIGNAL_BUY;
        unifiedSignal.confidence = MathMin(combinedScore, 0.98);
    }
    else if(combinedScore < -0.5)
    {
        unifiedSignal.finalSignal = TRADE_SIGNAL_SELL;
        unifiedSignal.confidence = MathMin(MathAbs(combinedScore), 0.98);
    }
    else
    {
        unifiedSignal.finalSignal = TRADE_SIGNAL_NONE;
        unifiedSignal.confidence = 0.3;
    }
    
    // Check if signals agree (boosts confidence)
    bool signalsAgree = (aiSignal.signal == traditionalSignal && aiSignal.signal != TRADE_SIGNAL_NONE);
    if(signalsAgree)
    {
        unifiedSignal.confidence = MathMin(unifiedSignal.confidence * 1.15, 0.98);  // 15% boost
        unifiedSignal.reasoning = StringFormat("AI+Traditional AGREE on %s (Conf: %.2f)", 
            (unifiedSignal.finalSignal == TRADE_SIGNAL_BUY ? "BUY" : "SELL"), unifiedSignal.confidence);
    }
    else
    {
        unifiedSignal.reasoning = StringFormat("AI+Traditional diverge (Final: %s, Conf: %.2f)",
            (unifiedSignal.finalSignal == TRADE_SIGNAL_BUY ? "BUY" : (unifiedSignal.finalSignal == TRADE_SIGNAL_SELL ? "SELL" : "NONE")),
            unifiedSignal.confidence);
    }
    
    // Fill remaining fields
    unifiedSignal.aiWeight = aiW;
    unifiedSignal.traditionalWeight = tradW;
    unifiedSignal.passesAIValidation = (unifiedSignal.confidence > m_aiConfidenceThreshold);
    unifiedSignal.riskAdjustedSize = aiSignal.riskAdjustedSize;
    
    return (unifiedSignal.finalSignal != TRADE_SIGNAL_NONE);
}

//+------------------------------------------------------------------+
//| Generate AI Signal - FULL IMPLEMENTATION                        |
//+------------------------------------------------------------------+
bool CAIIntegrationHub::GenerateAISignal(SEnhancedTradeSignal &aiSignal)
{
    // Initialize signal to default values
    aiSignal.signal = TRADE_SIGNAL_NONE;
    aiSignal.confidence = 0.0;
    aiSignal.reasoning = "";
    aiSignal.timestamp = TimeCurrent();
    
    // Check if symbol is set
    if(m_symbol == "")
        return false;
    
    // Collect market data for AI processing
    double marketData[];
    ArrayResize(marketData, 100);
    
    // Get price data
    for(int i = 0; i < 100; i++)
    {
        marketData[i] = iClose(m_symbol, m_timeframe, i);
        if(marketData[i] <= 0.0)
            return false;  // Invalid data
    }
    
    // Calculate technical indicators for AI
    double sma20 = 0.0, sma50 = 0.0, ema12 = 0.0, ema26 = 0.0;
    double rsi = 0.0, aiCurrentPrice = marketData[0];
    
    // SMA calculations
    for(int i = 0; i < 20 && i < ArraySize(marketData); i++)
        sma20 += marketData[i];
    sma20 /= MathMin(20, ArraySize(marketData));
    
    for(int i = 0; i < 50 && i < ArraySize(marketData); i++)
        sma50 += marketData[i];
    sma50 /= MathMin(50, ArraySize(marketData));
    
    // EMA calculations (simplified)
    ema12 = marketData[MathMax(0, ArraySize(marketData)-12)];
    ema26 = marketData[MathMax(0, ArraySize(marketData)-26)];
    double multiplier12 = 2.0 / 13.0;
    double multiplier26 = 2.0 / 27.0;
    
    for(int i = MathMax(0, ArraySize(marketData)-12) + 1; i < ArraySize(marketData); i++)
        ema12 = (marketData[i] - ema12) * multiplier12 + ema12;
    
    for(int i = MathMax(0, ArraySize(marketData)-26) + 1; i < ArraySize(marketData); i++)
        ema26 = (marketData[i] - ema26) * multiplier26 + ema26;
    
    // RSI calculation (simplified)
    double gains = 0.0, losses = 0.0;
    for(int i = MathMax(1, ArraySize(marketData)-14); i < ArraySize(marketData); i++)
    {
        double change = marketData[i] - marketData[i-1];
        if(change > 0) gains += change;
        else losses -= change;
    }
    rsi = 100.0 - (100.0 / (1.0 + (gains / MathMax(losses, 0.001))));
    
    // AI-Enhanced Multi-Factor Scoring
    double buyScore = 0.0, sellScore = 0.0;
    double maxScore = 10.0;
    
    // Trend factors
    if(aiCurrentPrice > sma20) buyScore += 2.0; else sellScore += 2.0;
    if(sma20 > sma50) buyScore += 1.5; else sellScore += 1.5;
    if(ema12 > ema26) buyScore += 1.5; else sellScore += 1.5;
    
    // RSI factors
    if(rsi < 30) buyScore += 2.5;  // Oversold
    else if(rsi > 70) sellScore += 2.5;  // Overbought
    else if(rsi > 45 && rsi < 55) { buyScore += 0.5; sellScore += 0.5; }  // Neutral
    
    // Momentum factors
    double momentum = (aiCurrentPrice - marketData[MathMin(10, ArraySize(marketData)-1)]) / aiCurrentPrice * 100.0;
    if(momentum > 0.5) buyScore += 1.5;
    else if(momentum < -0.5) sellScore += 1.5;
    
    // Volatility factor
    double volatility = 0.0;
    for(int i = 1; i < 14 && i < ArraySize(marketData); i++)
        volatility += MathAbs(marketData[i] - marketData[i-1]);
    volatility /= MathMin(14, ArraySize(marketData)-1);
    volatility = (volatility / aiCurrentPrice) * 100.0;
    
    // Determine signal based on scores
    double totalBuyScore = buyScore / maxScore;
    double totalSellScore = sellScore / maxScore;
    
    if(totalBuyScore > totalSellScore && totalBuyScore > 0.6)
    {
        aiSignal.signal = TRADE_SIGNAL_BUY;
        aiSignal.confidence = MathMin(totalBuyScore, 0.95);
        aiSignal.reasoning = StringFormat("AI BUY: Score=%.2f, RSI=%.1f, Trend=UP", totalBuyScore, rsi);
    }
    else if(totalSellScore > totalBuyScore && totalSellScore > 0.6)
    {
        aiSignal.signal = TRADE_SIGNAL_SELL;
        aiSignal.confidence = MathMin(totalSellScore, 0.95);
        aiSignal.reasoning = StringFormat("AI SELL: Score=%.2f, RSI=%.1f, Trend=DOWN", totalSellScore, rsi);
    }
    else
    {
        aiSignal.signal = TRADE_SIGNAL_NONE;
        aiSignal.confidence = 0.5;
        aiSignal.reasoning = "AI NEUTRAL: Inconclusive signals";
    }
    
    // Fill additional fields
    aiSignal.regime = m_currentRegime;
    aiSignal.regimeConfidence = 0.75;
    aiSignal.buyProbability = totalBuyScore;
    aiSignal.sellProbability = totalSellScore;
    aiSignal.trendStrength = MathAbs(sma20 - sma50) / aiCurrentPrice * 100.0;
    aiSignal.momentumScore = momentum;
    aiSignal.volatilityFactor = volatility;
    aiSignal.marketContext = StringFormat("Vol=%.2f%%, Mom=%.2f%%", volatility, momentum);
    
    return (aiSignal.signal != TRADE_SIGNAL_NONE);
}

//+------------------------------------------------------------------+
//| Cleanup                                                         |
//+------------------------------------------------------------------+
void AIHubDeinit() {
    if (g_aiHub != NULL) {
        delete g_aiHub;
        g_aiHub = NULL;
    }
}

//+------------------------------------------------------------------+
//| Train Models with New Data                                     |
//+------------------------------------------------------------------+
bool CAIIntegrationHub::TrainModels(const double &marketData[], double target)
{
    // If Python AI is enabled, send training data
    if(m_pythonAIEnabled && m_httpClient != NULL)
    {
        // Construct JSON payload for training
        string jsonRequest = "{\"market_data\":[";
        for(int i = 0; i < ArraySize(marketData); i++)
        {
            jsonRequest += DoubleToString(marketData[i], 5);
            if(i < ArraySize(marketData) - 1) jsonRequest += ",";
        }
        jsonRequest += StringFormat("],\"target\":%.1f,\"symbol\":\"%s\",\"timeframe\":%d}", 
                                   target, m_symbol, (int)m_timeframe);
        
        char postData[];
        StringToCharArray(jsonRequest, postData);
        
        char resultData[];
        string resultHeaders;
        
        // Send training request (async or fire-and-forget preferred, but sync for now)
        int res = WebRequest("POST", m_pythonServerUrl + "/train", NULL, 500, postData, resultData, resultHeaders);
        
        if(res == 200)
        {
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Build Market Data JSON                                           |
//+------------------------------------------------------------------+
bool CAIIntegrationHub::BuildMarketDataJson(string &marketDataJson) const
{
    // Simple implementation - builds a basic JSON array of recent prices
    MqlRates rates[];
    int copied = CopyRates(m_symbol, m_timeframe, 0, 100, rates);
    
    if(copied <= 0)
        return false;
    
    marketDataJson = "{\"prices\":[";
    for(int i = 0; i < copied; i++)
    {
        marketDataJson += DoubleToString(rates[i].close, 5);
        if(i < copied - 1)
            marketDataJson += ",";
    }
    marketDataJson += "]}";
    
    return true;
}

//+------------------------------------------------------------------+
//| Extract JSON String Value                                        |
//+------------------------------------------------------------------+
bool CAIIntegrationHub::ExtractJsonString(const string &json, const string key, string &value) const
{
    // Simple JSON string extraction
    string searchKey = "\"" + key + "\":\"";
    int startPos = StringFind(json, searchKey);
    if(startPos < 0)
        return false;
    
    startPos += StringLen(searchKey);
    int endPos = StringFind(json, "\"", startPos);
    if(endPos < 0)
        return false;
    
    value = StringSubstr(json, startPos, endPos - startPos);
    return true;
}

//+------------------------------------------------------------------+
//| Extract JSON Number Value                                        |
//+------------------------------------------------------------------+
bool CAIIntegrationHub::ExtractJsonNumber(const string &json, const string key, double &value) const
{
    // Simple JSON number extraction
    string searchKey = "\"" + key + "\":";
    int startPos = StringFind(json, searchKey);
    if(startPos < 0)
        return false;
    
    startPos += StringLen(searchKey);
    
    // Find the end of the number (comma, brace, or bracket)
    int endPos = startPos;
    while(endPos < StringLen(json))
    {
        ushort charCode = StringGetCharacter(json, endPos);
        if(charCode == ',' || charCode == '}' || charCode == ']')
            break;
        endPos++;
    }
    
    string numStr = StringSubstr(json, startPos, endPos - startPos);
    StringTrimLeft(numStr);
    StringTrimRight(numStr);
    
    value = StringToDouble(numStr);
    return true;
}

//+------------------------------------------------------------------+
//| Extract Data Block from JSON Response                            |
//+------------------------------------------------------------------+
bool CAIIntegrationHub::ExtractDataBlock(const string &json, string &dataBlock) const
{
    // Extract the "data" field from JSON response
    string searchKey = "\"data\":{";
    int startPos = StringFind(json, searchKey);
    if(startPos < 0)
    {
        // Try without data wrapper - maybe it's just the object itself
        dataBlock = json;
        return true;
    }
    
    startPos += StringLen(searchKey) - 1; // Include the opening brace
    
    // Find matching closing brace
    int braceCount = 0;
    int endPos = startPos;
    for(int i = startPos; i < StringLen(json); i++)
    {
        ushort charCode = StringGetCharacter(json, i);
        if(charCode == '{')
            braceCount++;
        else if(charCode == '}')
        {
            braceCount--;
            if(braceCount == 0)
            {
                endPos = i + 1;
                break;
            }
        }
    }
    
    if(endPos <= startPos)
        return false;
    
    dataBlock = StringSubstr(json, startPos, endPos - startPos);
    return true;
}

//+------------------------------------------------------------------+
//| Convert Timeframe to String                                      |
//+------------------------------------------------------------------+
string CAIIntegrationHub::TimeframeToString(ENUM_TIMEFRAMES timeframe) const
{
    switch(timeframe)
    {
        case PERIOD_M1:  return "M1";
        case PERIOD_M5:  return "M5";
        case PERIOD_M15: return "M15";
        case PERIOD_M30: return "M30";
        case PERIOD_H1:  return "H1";
        case PERIOD_H4:  return "H4";
        case PERIOD_D1:  return "D1";
        case PERIOD_W1:  return "W1";
        case PERIOD_MN1: return "MN1";
        default:         return "CURRENT";
    }
}

#endif // __AI_INTEGRATION_HUB_MQH__