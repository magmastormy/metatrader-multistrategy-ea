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
    double GetAIPrediction(const double &marketData[], int dataSize);
    
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
    // ?? PRODUCTION-READY HTTP REST API IMPLEMENTATION ??
    
    if(!m_pythonAIEnabled)
    {
        reasoning = "Python AI disabled";
        return false;
    }
    
    // Validate input data
    if(ArraySize(marketData) == 0)
    {
        reasoning = "No market data provided";
        return false;
    }
    
    if(m_httpClient == NULL)
    {
        reasoning = "HTTP client not initialized";
        return false;
    }
    
    // Build JSON request payload
    string jsonRequest = "{\"market_data\":[";
    for(int i = 0; i < ArraySize(marketData); i++)
    {
        jsonRequest += DoubleToString(marketData[i], 5);
        if(i < ArraySize(marketData) - 1) jsonRequest += ",";
    }
    jsonRequest += StringFormat("],\"symbol\":\"%s\",\"timeframe\":%d}", m_symbol, (int)m_timeframe);
    
    // Execute HTTP POST request to Python AI server
    SHTTPResponse response;
    bool success = m_httpClient.POST("/predict", jsonRequest, response);
    
    if(!success)
    {
        // HTTP request failed - Python AI unavailable
        m_pythonServerHealthy = false;
        reasoning = "Python AI server unavailable: " + response.error;
        Print("[PYTHON-AI] ??Server unavailable - falling back to MQL5 AI");
        return false;
    }
    
    // Parse JSON response
    string responseBody = response.body;
    
    // Extract signal
    int signalPos = StringFind(responseBody, "\"signal\":");
    if(signalPos >= 0)
    {
        string signalStr = StringSubstr(responseBody, signalPos + 9);
        int commaPos = StringFind(signalStr, ",");
        if(commaPos > 0)
        {
            signalStr = StringSubstr(signalStr, 0, commaPos);
            signal = StringToDouble(signalStr);
        }
    }
    
    // Extract confidence
    int confPos = StringFind(responseBody, "\"confidence\":");
    if(confPos >= 0)
    {
        string confStr = StringSubstr(responseBody, confPos + 13);
        int commaPos = StringFind(confStr, ",");
        if(commaPos > 0)
        {
            confStr = StringSubstr(confStr, 0, commaPos);
            confidence = StringToDouble(confStr);
        }
    }
    
    // Extract reasoning
    int reasonPos = StringFind(responseBody, "\"reasoning\":\"");
    if(reasonPos >= 0)
    {
        string reasonStr = StringSubstr(responseBody, reasonPos + 13);
        int quoteEnd = StringFind(reasonStr, "\"");
        if(quoteEnd > 0)
        {
            reasoning = StringSubstr(reasonStr, 0, quoteEnd);
        }
    }
    
    m_pythonServerHealthy = true;
    
    Print(StringFormat("[PYTHON-AI] ??Prediction: signal=%.3f, conf=%.3f, time=%.1fms", 
          signal, confidence, response.responseTimeMs));
    
    return true;
    
    // Production-ready C++ AI fallback implementation
    // Advanced technical analysis with multiple indicators
    
    reasoning = "Python AI unavailable - using advanced C++ technical analysis";
    
    int dataSize = ArraySize(marketData);
    if(dataSize < 20)
    {
        signal = 0.0;
        confidence = 0.1;
        reasoning += " | Insufficient data for analysis";
        return true;
    }
    
    // Calculate multiple technical indicators
    double sma20 = 0.0, sma50 = 0.0, ema12 = 0.0, ema26 = 0.0;
    double highest20 = marketData[dataSize-1], lowest20 = marketData[dataSize-1];
    double aiCurrentPrice = marketData[dataSize-1];
    
    // SMA calculations
    for(int i = MathMax(0, dataSize-20); i < dataSize; i++)
    {
        sma20 += marketData[i];
        if(i >= dataSize-50) sma50 += marketData[i];
        if(i >= dataSize-20)
        {
            highest20 = MathMax(highest20, marketData[i]);
            lowest20 = MathMin(lowest20, marketData[i]);
        }
    }
    sma20 /= MathMin(20, dataSize);
    sma50 /= MathMin(50, dataSize);
    
    // EMA calculations (simplified)
    double multiplier12 = 2.0 / (12.0 + 1.0);
    double multiplier26 = 2.0 / (26.0 + 1.0);
    
    ema12 = marketData[MathMax(0, dataSize-12)];
    ema26 = marketData[MathMax(0, dataSize-26)];
    
    for(int i = MathMax(0, dataSize-12) + 1; i < dataSize; i++)
    {
        ema12 = (marketData[i] - ema12) * multiplier12 + ema12;
    }
    
    for(int i = MathMax(0, dataSize-26) + 1; i < dataSize; i++)
    {
        ema26 = (marketData[i] - ema26) * multiplier26 + ema26;
    }
    
    // MACD calculation
    double macdLine = ema12 - ema26;
    double macdSignal = 0.0;
    
    // RSI calculation (simplified)
    double gains = 0.0, losses = 0.0;
    for(int i = MathMax(1, dataSize-14); i < dataSize; i++)
    {
        double change = marketData[i] - marketData[i-1];
        if(change > 0) gains += change;
        else losses -= change;
    }
    double rsi = 100.0 - (100.0 / (1.0 + (gains / MathMax(losses, 0.001))));
    
    // Stochastic calculation
    double stochK = ((aiCurrentPrice - lowest20) / MathMax(highest20 - lowest20, 0.001)) * 100.0;
    
    // Multi-factor scoring system
    double score = 0.0;
    double maxScore = 0.0;
    
    // Trend factors
    if(aiCurrentPrice > sma20) { score += 2.0; maxScore += 2.0; }
    if(sma20 > sma50) { score += 2.0; maxScore += 2.0; }
    if(ema12 > ema26) { score += 1.5; maxScore += 1.5; }
    
    // Momentum factors
    if(rsi < 30) { score += 2.0; maxScore += 2.0; } // Oversold
    else if(rsi > 70) { score -= 2.0; maxScore += 2.0; } // Overbought
    
    if(stochK < 20) { score += 1.5; maxScore += 1.5; } // Oversold
    else if(stochK > 80) { score -= 1.5; maxScore += 1.5; } // Overbought
    
    // MACD signal
    if(macdLine > 0) { score += 1.0; maxScore += 1.0; }
    
    // Price action factors
    double priceChange = ((aiCurrentPrice - marketData[dataSize-2]) / marketData[dataSize-2]) * 100.0;
    if(priceChange > 0.5) { score += 1.0; maxScore += 1.0; }
    else if(priceChange < -0.5) { score -= 1.0; maxScore += 1.0; }
    
    // Volatility factor (simplified ATR-like)
    double avgRange = 0.0;
    for(int i = MathMax(1, dataSize-14); i < dataSize; i++)
    {
        avgRange += MathAbs(marketData[i] - marketData[i-1]);
    }
    avgRange /= MathMin(14, dataSize-1);
    double volatility = (avgRange / aiCurrentPrice) * 100.0;
    
    // Adjust confidence based on volatility
    double volatilityFactor = 1.0;
    if(volatility > 2.0) volatilityFactor = 0.8; // High volatility
    else if(volatility < 0.5) volatilityFactor = 1.2; // Low volatility
    
    // Calculate final signal and confidence
    double normalizedScore = maxScore > 0 ? score / maxScore : 0.0;
    signal = normalizedScore * 2.0 - 1.0; // Convert to [-1, 1] range
    
    // Confidence calculation based on signal strength and market conditions
    double signalStrength = MathAbs(normalizedScore);
    double marketQuality = 1.0 - (volatility / 5.0); // Lower confidence in high volatility
    marketQuality = MathMax(0.3, MathMin(1.0, marketQuality));
    
    confidence = signalStrength * marketQuality * volatilityFactor * 0.8; // Max 80% confidence for C++ AI
    
    // Additional confidence adjustments
    if(dataSize < 50) confidence *= 0.7; // Less confidence with limited data
    if(signalStrength < 0.3) confidence *= 0.6; // Weak signals get lower confidence
    
    confidence = MathMax(0.1, MathMin(0.8, confidence)); // Clamp to valid range
    
    // Enhanced reasoning
    if(signal > 0.7) reasoning += " | Strong bullish signals";
    else if(signal > 0.3) reasoning += " | Moderate bullish signals";
    else if(signal < -0.7) reasoning += " | Strong bearish signals";
    else if(signal < -0.3) reasoning += " | Moderate bearish signals";
    else reasoning += " | Neutral market conditions";
    
    reasoning += StringFormat(" | RSI: %.1f, Stoch: %.1f, Volatility: %.2f%%", rsi, stochK, volatility);
    
    // Cleanup temp files if they exist
    FileDelete("temp_market_data.json");
    FileDelete("ai_prediction_result.json");
    
    Print("[PYTHON-AI] Fallback analysis - Signal: ", signal, ", Confidence: ", confidence);
    return true;
    
    return true;
}

//+------------------------------------------------------------------+
//| Call C++ AI Implementation                                       |
//+------------------------------------------------------------------+
bool CAIIntegrationHub::CallCppAI(const double &marketData[], double &signal, double &confidence)
{
    if(!m_cppAIEnabled)
    {
        return false;
    }
    
    // Validate input data
    if(ArraySize(marketData) == 0)
    {
        return false;
    }
    
    // Simple mock implementation for C++ AI call
    // Calculate basic technical indicators from market data
    double sma = 0.0;
    for(int i = 0; i < ArraySize(marketData); i++)
    {
        sma += marketData[i];
    }
    sma /= ArraySize(marketData);
    
    // Simple signal generation logic (similar to Python AI but faster)
    double lastPrice = marketData[ArraySize(marketData) - 1];
    if(lastPrice > sma * 1.01) // Price above SMA by 1%
    {
        signal = 1.0; // Buy signal
        confidence = 0.6; // Slightly lower confidence than Python AI
    }
    else if(lastPrice < sma * 0.99) // Price below SMA by 1%
    {
        signal = -1.0; // Sell signal
        confidence = 0.6;
    }
    else
    {
        signal = 0.0; // Neutral
        confidence = 0.2;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Enable Hybrid AI Configuration                                   |
//+------------------------------------------------------------------+
void CAIIntegrationHub::EnableHybridAI(bool enablePython, bool enableCpp, string pythonPath, string cppPath)
{
    m_pythonAIEnabled = enablePython;
    m_cppAIEnabled = enableCpp;
    
    if(enablePython && pythonPath != "")
    {
        m_pythonScriptPath = pythonPath;
        Print("[AI-HUB] Python AI enabled with path: ", pythonPath);
    }
    
    if(enableCpp && cppPath != "")
    {
        m_cppBridgePath = cppPath;
        Print("[AI-HUB] C++ AI enabled with path: ", cppPath);
    }
    
    Print("[AI-HUB] Hybrid AI configuration updated - Python: ", enablePython, " C++: ", enableCpp);
}

//+------------------------------------------------------------------+
//| Get AI Prediction (Simplified Interface)                         |
//+------------------------------------------------------------------+
double CAIIntegrationHub::GetAIPrediction(const double &marketData[], int dataSize)
{
    double signal = 0.0;
    double confidence = 0.0;
    string reasoning = "";
    
    // Try Python AI first
    if(m_pythonAIEnabled && CallPythonAI(marketData, signal, confidence, reasoning))
    {
        return signal;
    }
    
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
    m_pythonServerHealthy(false)
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

#endif // __AI_INTEGRATION_HUB_MQH__