//+------------------------------------------------------------------+
//| Unified Signal Pipeline - Enterprise Grade                       |
//| Central hub for all strategy signals with filtering              |
//+------------------------------------------------------------------+
#ifndef UNIFIED_SIGNAL_PIPELINE_MQH
#define UNIFIED_SIGNAL_PIPELINE_MQH

#include "../Utils/Enums.mqh"
#include "../Signals/SignalDiagnostics.mqh"
#include "../Signals/TimeframeConsistency.mqh"
#include "../Signals/HedgingProtection.mqh"
#include "../Engines/TrendEngine.mqh"
#include "../Engines/StructureEngine.mqh"
#include "../Engines/LiquidityEngine.mqh"
#include "../Engines/VolatilityEngine.mqh"
#include "../../Interfaces/IStrategy.mqh"

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
//| Signal Filter Settings                                          |
//+------------------------------------------------------------------+
struct SignalFilterSettings
{
    bool enableTrendFilter;
    bool enableVolatilityFilter;
    bool enableLiquidityFilter;
    bool enableStructureFilter;
    bool enableTimeFilter;
    double minConfidence;
    double maxVolatility;
    int minTrendStrength;
    
    SignalFilterSettings() : 
        enableTrendFilter(true),
        enableVolatilityFilter(true),
        enableLiquidityFilter(true),
        enableStructureFilter(true),
        enableTimeFilter(false),
        minConfidence(0.40),
        maxVolatility(3.0),
        minTrendStrength(50) {}
};

//+------------------------------------------------------------------+
//| Unified Signal Pipeline Class                                   |
//+------------------------------------------------------------------+
class CUnifiedSignalPipeline
{
private:
    // Engines
    CTrendEngine* m_trendEngine;
    CStructureEngine* m_structureEngine;
    CLiquidityEngine* m_liquidityEngine;
    CVolatilityEngine* m_volatilityEngine;
    
    // Diagnostics & Protection
    CSignalDiagnostics* m_diagnostics;
    CTimeframeConsistency* m_tfConsistency;
    CHedgingProtection* m_hedgingProtection;
    
    // Settings
    SignalFilterSettings m_filters;
    
    // Statistics
    int m_signalsProcessed;
    int m_signalsFiltered;
    int m_signalsPassed;
    string m_lastEvaluatedSymbol;
    bool m_lastRawSignalNone;
    bool m_lastFilteredByPipeline;
    
    // Internal methods
    bool ApplyTrendFilter(ENUM_TRADE_SIGNAL &signal, double &confidence);
    bool ApplyVolatilityFilter(ENUM_TRADE_SIGNAL &signal, double &confidence);
    bool ApplyLiquidityFilter(ENUM_TRADE_SIGNAL &signal, double &confidence, const string symbol);
    bool ApplyStructureFilter(ENUM_TRADE_SIGNAL &signal, double &confidence);
    bool ApplyTimeFilter(ENUM_TRADE_SIGNAL &signal);
    void LogFilterResult(const string filter, bool passed, const string reason);
    
public:
    CUnifiedSignalPipeline();
    ~CUnifiedSignalPipeline();
    
    // Initialization
    bool Initialize(SignalFilterSettings &settings);
    
    // Main processing
    ENUM_TRADE_SIGNAL ProcessSignal(IStrategy* strategy, const string symbol, 
                                   ENUM_TIMEFRAMES timeframe, double &confidence);
    
    // Multi-timeframe processing
    ENUM_TRADE_SIGNAL ProcessMTFSignals(IStrategy* &strategies[], int count,
                                       const string symbol, ENUM_TIMEFRAMES &timeframes[],
                                       double &finalConfidence);
    
    // Configuration
    void SetFilters(SignalFilterSettings &settings) { m_filters = settings; }
    SignalFilterSettings GetFilters() const { return m_filters; }
    
    // Statistics
    int GetSignalsProcessed() const { return m_signalsProcessed; }
    int GetSignalsFiltered() const { return m_signalsFiltered; }
    int GetSignalsPassed() const { return m_signalsPassed; }
    bool WasLastSignalRawNone() const { return m_lastRawSignalNone; }
    bool WasLastSignalFilteredByPipeline() const { return m_lastFilteredByPipeline; }
    string GetLastEvaluatedSymbol() const { return m_lastEvaluatedSymbol; }
    double GetFilterRate() const 
    { 
        return m_signalsProcessed > 0 ? 
               (double)m_signalsFiltered / m_signalsProcessed : 0; 
    }
    
    // Engine access
    CTrendEngine* GetTrendEngine() { return m_trendEngine; }
    CStructureEngine* GetStructureEngine() { return m_structureEngine; }
    CLiquidityEngine* GetLiquidityEngine() { return m_liquidityEngine; }
    CVolatilityEngine* GetVolatilityEngine() { return m_volatilityEngine; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CUnifiedSignalPipeline::CUnifiedSignalPipeline() :
    m_trendEngine(NULL),
    m_structureEngine(NULL),
    m_liquidityEngine(NULL),
    m_volatilityEngine(NULL),
    m_diagnostics(NULL),
    m_tfConsistency(NULL),
    m_hedgingProtection(NULL),
    m_signalsProcessed(0),
    m_signalsFiltered(0),
    m_signalsPassed(0),
    m_lastEvaluatedSymbol(""),
    m_lastRawSignalNone(false),
    m_lastFilteredByPipeline(false)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CUnifiedSignalPipeline::~CUnifiedSignalPipeline()
{
    if(m_trendEngine != NULL) { delete m_trendEngine; m_trendEngine = NULL; }
    if(m_structureEngine != NULL) { delete m_structureEngine; m_structureEngine = NULL; }
    if(m_liquidityEngine != NULL) { delete m_liquidityEngine; m_liquidityEngine = NULL; }
    if(m_volatilityEngine != NULL) { delete m_volatilityEngine; m_volatilityEngine = NULL; }
    if(m_diagnostics != NULL) { delete m_diagnostics; m_diagnostics = NULL; }
    if(m_tfConsistency != NULL) { delete m_tfConsistency; m_tfConsistency = NULL; }
    if(m_hedgingProtection != NULL) { delete m_hedgingProtection; m_hedgingProtection = NULL; }
}

//+------------------------------------------------------------------+
//| Initialize Pipeline                                             |
//+------------------------------------------------------------------+
bool CUnifiedSignalPipeline::Initialize(SignalFilterSettings &settings)
{
    m_filters = settings;
    
    // Initialize diagnostics
    m_diagnostics = new CSignalDiagnostics();
    if(m_diagnostics != NULL)
        m_diagnostics.Initialize(1000, 3);
    
    // Initialize consistency checker
    m_tfConsistency = new CTimeframeConsistency();
    if(m_tfConsistency != NULL)
        m_tfConsistency.Initialize(CONFLICT_RES_WEIGHTED, 0.6, false);
    
    // Initialize hedging protection
    m_hedgingProtection = new CHedgingProtection();
    if(m_hedgingProtection != NULL)
        m_hedgingProtection.Initialize(HEDGING_MODE_PREVENT, false);
    
    // Initialize engines
    m_trendEngine = new CTrendEngine();
    if(m_trendEngine != NULL)
        m_trendEngine.Initialize(20, 50, 200, 14, m_diagnostics);
    
    m_structureEngine = new CStructureEngine();
    if(m_structureEngine != NULL)
        m_structureEngine.Initialize(10, 10.0, true, m_diagnostics);
    
    m_liquidityEngine = new CLiquidityEngine();
    if(m_liquidityEngine != NULL)
        m_liquidityEngine.Initialize(10.0, 2, m_diagnostics);
    
    m_volatilityEngine = new CVolatilityEngine();
    if(m_volatilityEngine != NULL)
        m_volatilityEngine.Initialize(14, 20, m_diagnostics);
    
    Print("[UnifiedSignalPipeline] Initialized with filters: Trend=", m_filters.enableTrendFilter,
          " Volatility=", m_filters.enableVolatilityFilter,
          " Liquidity=", m_filters.enableLiquidityFilter,
          " Structure=", m_filters.enableStructureFilter);
    
    return true;
}

//+------------------------------------------------------------------+
//| Process Single Strategy Signal                                  |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CUnifiedSignalPipeline::ProcessSignal(IStrategy* strategy, 
                                                       const string symbol,
                                                       ENUM_TIMEFRAMES timeframe, 
                                                       double &confidence)
{
    m_lastEvaluatedSymbol = symbol;
    m_lastRawSignalNone = false;
    m_lastFilteredByPipeline = false;

    if(strategy == NULL)
    {
        confidence = 0;
        m_lastRawSignalNone = true;
        return TRADE_SIGNAL_NONE;
    }
    
    m_signalsProcessed++;
    
    // Get raw signal from strategy
    ENUM_TRADE_SIGNAL signal = strategy.GetSignal(confidence);
    
    if(signal == TRADE_SIGNAL_NONE)
    {
        m_lastRawSignalNone = true;
        m_signalsFiltered++;
        return TRADE_SIGNAL_NONE;
    }
    
    // Update all engines
    if(m_trendEngine != NULL)
        m_trendEngine.UpdateTrend(symbol, timeframe);
    
    if(m_structureEngine != NULL)
        m_structureEngine.DetectSwingPoints(symbol, timeframe);
    
    if(m_liquidityEngine != NULL)
        m_liquidityEngine.DetectLiquidityZones(symbol, timeframe);
    
    if(m_volatilityEngine != NULL)
        m_volatilityEngine.UpdateVolatility(symbol, timeframe);
    
    // Apply filters
    bool passed = true;
    
    if(m_filters.enableTrendFilter)
        passed = passed && ApplyTrendFilter(signal, confidence);
    
    if(m_filters.enableVolatilityFilter)
        passed = passed && ApplyVolatilityFilter(signal, confidence);
    
    if(m_filters.enableLiquidityFilter)
        passed = passed && ApplyLiquidityFilter(signal, confidence, symbol);
    
    if(m_filters.enableStructureFilter)
        passed = passed && ApplyStructureFilter(signal, confidence);
    
    if(m_filters.enableTimeFilter)
        passed = passed && ApplyTimeFilter(signal);
    
    // 🔥 FIX: Dynamic confidence threshold based on market conditions
    double effectiveMinConfidence = m_filters.minConfidence;
    
    // Lower threshold for ranging markets (more opportunities needed)
    if(m_trendEngine != NULL)
    {
        ENUM_TREND_TYPE trend = m_trendEngine.GetCurrentTrend();
        if(trend == TREND_RANGING || trend == TREND_NONE)
        {
            effectiveMinConfidence = MathMax(0.20, m_filters.minConfidence * 0.75);  // Up to 25% reduction
        }
        else if(trend == TREND_NONE)
        {
            effectiveMinConfidence = m_filters.minConfidence * 0.90;
        }
        else if(m_trendEngine.IsStrongTrend())
        {
            effectiveMinConfidence = MathMin(1.0, m_filters.minConfidence * 0.95); // Allow slight relaxation
        }
    }
    
    // Check confidence threshold
    if(confidence < effectiveMinConfidence)
    {
        LogFilterResult("ConfidenceFilter", false, 
                       StringFormat("Confidence %.2f below minimum %.2f (effective: %.2f)", 
                                  confidence, m_filters.minConfidence, effectiveMinConfidence));
        passed = false;
    }
    else if(confidence >= effectiveMinConfidence && confidence < m_filters.minConfidence)
    {
        LogFilterResult("ConfidenceFilter", true, 
                       StringFormat("PASSED with adjusted threshold - Confidence: %.2f (min: %.2f, effective: %.2f)", 
                                  confidence, m_filters.minConfidence, effectiveMinConfidence));
    }
    
    // Apply hedging protection
    if(passed && m_hedgingProtection != NULL)
    {
        string hedgeReason = "";
        ENUM_TRADE_SIGNAL filteredSignal = m_hedgingProtection.FilterSignal(symbol, signal, hedgeReason);
        
        if(filteredSignal == TRADE_SIGNAL_NONE)
        {
            LogFilterResult("HedgingProtection", false, hedgeReason);
            passed = false;
            signal = TRADE_SIGNAL_NONE;
        }
    }
    
    if(!passed)
    {
        m_lastFilteredByPipeline = true;
        m_signalsFiltered++;
        signal = TRADE_SIGNAL_NONE;
        confidence = 0;
    }
    else
    {
        m_signalsPassed++;
        
        if(m_diagnostics != NULL)
        {
            string strategyName = strategy.GetName();
            string reason = StringFormat("Signal passed all filters | Confidence: %.2f", confidence);
            m_diagnostics.LogSignalGeneration(strategyName, symbol, timeframe, signal, confidence, reason);
        }
    }
    
    return signal;
}

//+------------------------------------------------------------------+
//| Process Multiple Timeframe Signals                              |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CUnifiedSignalPipeline::ProcessMTFSignals(IStrategy* &strategies[], 
                                                           int count,
                                                           const string symbol, 
                                                           ENUM_TIMEFRAMES &timeframes[],
                                                           double &finalConfidence)
{
    if(count == 0 || ArraySize(strategies) == 0 || ArraySize(timeframes) == 0)
    {
        finalConfidence = 0;
        return TRADE_SIGNAL_NONE;
    }
    
    // Reset TF consistency checker
    if(m_tfConsistency != NULL)
        m_tfConsistency.Reset();
    
    // Process each timeframe
    ENUM_TRADE_SIGNAL signals[];
    double confidences[];
    ArrayResize(signals, count);
    ArrayResize(confidences, count);
    
    for(int i = 0; i < count; i++)
    {
        double conf = 0;
        signals[i] = ProcessSignal(strategies[i], symbol, timeframes[i], conf);
        confidences[i] = conf;
        
        // Add to TF consistency checker
        if(m_tfConsistency != NULL && signals[i] != TRADE_SIGNAL_NONE)
        {
            m_tfConsistency.AddTimeframeSignal(timeframes[i], signals[i], conf, 
                                              strategies[i].GetName());
        }
    }
    
    // Check for conflicts
    if(m_tfConsistency != NULL && m_tfConsistency.HasConflicts())
    {
        // Resolve conflicts based on settings
        double resolvedConf = 0.0;
        string reasoning = "";
        ENUM_TRADE_SIGNAL resolvedSignal = m_tfConsistency.ResolveSignals(resolvedConf, reasoning);
        
        if(m_diagnostics != NULL)
        {
            string conflictDetails = m_tfConsistency.GetConflictDetails();
            Print("[Pipeline] MTF conflict resolved: ", conflictDetails);
        }
        
        finalConfidence = resolvedConf;
        return resolvedSignal;
    }
    
    // Calculate consensus if no conflicts
    int buyCount = 0, sellCount = 0;
    double buyConf = 0, sellConf = 0;
    
    for(int i = 0; i < count; i++)
    {
        if(signals[i] == TRADE_SIGNAL_BUY)
        {
            buyCount++;
            buyConf += confidences[i];
        }
        else if(signals[i] == TRADE_SIGNAL_SELL)
        {
            sellCount++;
            sellConf += confidences[i];
        }
    }
    
    // Determine final signal
    if(buyCount > sellCount)
    {
        finalConfidence = buyConf / buyCount;
        return TRADE_SIGNAL_BUY;
    }
    else if(sellCount > buyCount)
    {
        finalConfidence = sellConf / sellCount;
        return TRADE_SIGNAL_SELL;
    }
    
    finalConfidence = 0;
    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Apply Trend Filter                                              |
//+------------------------------------------------------------------+
bool CUnifiedSignalPipeline::ApplyTrendFilter(ENUM_TRADE_SIGNAL &signal, double &confidence)
{
    if(m_trendEngine == NULL)
        return true;
    
    ENUM_TREND_TYPE trend = m_trendEngine.GetCurrentTrend();
    double trendStrength = m_trendEngine.GetTrendStrength();
    
    // Only bypass trend alignment in neutral/ranging regimes for truly exceptional confidence.
    if(confidence > 0.90 && (trend == TREND_RANGING || trend == TREND_NONE))
    {
        LogFilterResult("TrendFilter", true, 
                       StringFormat("BYPASSED - Exceptional confidence in neutral trend (%.2f) | Trend: %s", 
                                  confidence, EnumToString(trend)));
        return true;
    }
    
    // 🔥 FIX: Allow ranging markets - check if trend is actively AGAINST the signal
    // Only reject if there's a STRONG opposing trend
    bool strongOpposingTrend = false;
    
    if(signal == TRADE_SIGNAL_BUY && m_trendEngine.IsTrendBearish() && trendStrength > 70)
        strongOpposingTrend = true;
    else if(signal == TRADE_SIGNAL_SELL && m_trendEngine.IsTrendBullish() && trendStrength > 70)
        strongOpposingTrend = true;
    
    if(strongOpposingTrend)
    {
        LogFilterResult("TrendFilter", false, 
                       StringFormat("Strong opposing trend: %s (%.1f)", 
                                  EnumToString(trend), trendStrength));
        return false;
    }
    
    // 🔥 FIX: ALLOW signals in ranging markets (TREND_RANGING, TREND_NONE)
    // These are valid trading opportunities
    if(trend == TREND_RANGING || trend == TREND_NONE)
    {
        LogFilterResult("TrendFilter", true, 
                       StringFormat("PASSED - Ranging market | Strength: %.1f", trendStrength));
        return true;
    }
    
    // Check signal alignment with trend (only for trending markets)
    bool aligned = false;
    if(signal == TRADE_SIGNAL_BUY && m_trendEngine.IsTrendBullish())
        aligned = true;
    else if(signal == TRADE_SIGNAL_SELL && m_trendEngine.IsTrendBearish())
        aligned = true;
    
    if(!aligned)
    {
        // 🔥 FIX: Don't reject weak misalignments - only log as warning
        if(trendStrength < 60)
        {
            LogFilterResult("TrendFilter", true, 
                           StringFormat("Weak trend misalignment (%.1f) - ALLOWING signal", trendStrength));
            return true;
        }
        
        LogFilterResult("TrendFilter", false, 
                       StringFormat("Strong trend misalignment: %s (%.1f)", 
                                  EnumToString(trend), trendStrength));
        return false;
    }
    
    // Boost confidence for strong aligned trends
    if(m_trendEngine.IsStrongTrend())
        confidence *= 1.15;
    
    // Cap confidence to valid range [0.0, 1.0]
    confidence = MathMin(1.0, MathMax(0.0, confidence));
    
    LogFilterResult("TrendFilter", true, 
                   StringFormat("Trend: %s, Strength: %.1f", 
                              EnumToString(trend), trendStrength));
    
    return true;
}

//+------------------------------------------------------------------+
//| Apply Volatility Filter                                         |
//+------------------------------------------------------------------+
bool CUnifiedSignalPipeline::ApplyVolatilityFilter(ENUM_TRADE_SIGNAL &signal, double &confidence)
{
    if(m_volatilityEngine == NULL)
        return true;
    
    ENUM_VOLATILITY_STATE volState = m_volatilityEngine.GetVolatilityState();
    double atrPercent = m_volatilityEngine.GetATRPercent();
    
    // Check maximum volatility
    if(atrPercent > m_filters.maxVolatility)
    {
        LogFilterResult("VolatilityFilter", false, 
                       StringFormat("Volatility %.2f%% exceeds maximum %.2f%%", 
                                  atrPercent, m_filters.maxVolatility));
        return false;
    }
    
    // Adjust confidence based on volatility
    if(volState == VOLATILITY_LOW)
        confidence *= 1.1;
    else if(volState == VOLATILITY_HIGH)
        confidence *= 0.9;
    else if(volState == VOLATILITY_EXTREME)
        confidence *= 0.7;
    
    // Cap confidence to valid range [0.0, 1.0]
    confidence = MathMin(1.0, MathMax(0.0, confidence));
    
    LogFilterResult("VolatilityFilter", true, 
                   StringFormat("Volatility: %s (%.2f%%)", 
                              EnumToString(volState), atrPercent));
    
    return true;
}

//+------------------------------------------------------------------+
//| Apply Liquidity Filter                                          |
//+------------------------------------------------------------------+
bool CUnifiedSignalPipeline::ApplyLiquidityFilter(ENUM_TRADE_SIGNAL &signal, double &confidence, const string symbol)
{
    if(m_liquidityEngine == NULL)
        return true;
    
    // Check for recent liquidity sweep
    if(m_liquidityEngine.HasLiquiditySweep(5))
    {
        confidence *= 1.15; // Boost confidence after liquidity grab
        LogFilterResult("LiquidityFilter", true, "Recent liquidity sweep detected");
    }
    
    // Check if price is near liquidity
    string liquiditySymbol = (symbol != "") ? symbol : _Symbol;
    double localCurrentPrice = SymbolInfoDouble(liquiditySymbol, SYMBOL_BID);
    if(m_liquidityEngine.IsPriceNearLiquidity(localCurrentPrice, 30))
    {
        confidence *= 0.95; // Slightly reduce confidence near untested liquidity
        LogFilterResult("LiquidityFilter", true, "Price near liquidity zone");
    }
    
    // Cap confidence to valid range [0.0, 1.0]
    confidence = MathMin(1.0, MathMax(0.0, confidence));
    
    return true;
}

//+------------------------------------------------------------------+
//| Apply Structure Filter                                          |
//+------------------------------------------------------------------+
bool CUnifiedSignalPipeline::ApplyStructureFilter(ENUM_TRADE_SIGNAL &signal, double &confidence)
{
    if(m_structureEngine == NULL)
        return true;
    
    bool structureAligned = false;
    
    // Check for BOS/CHOCH alignment
    if(signal == TRADE_SIGNAL_BUY)
    {
        if(m_structureEngine.HasBullishBOS(5) || m_structureEngine.HasBullishCHOCH(5))
        {
            structureAligned = true;
            confidence *= 1.2;
        }
    }
    else if(signal == TRADE_SIGNAL_SELL)
    {
        if(m_structureEngine.HasBearishBOS(5) || m_structureEngine.HasBearishCHOCH(5))
        {
            structureAligned = true;
            confidence *= 1.2;
        }
    }
    
    if(!structureAligned)
    {
        // Still allow signal but with reduced confidence
        confidence *= 0.85;
        LogFilterResult("StructureFilter", true, "No recent structure break");
    }
    else
    {
        LogFilterResult("StructureFilter", true, "Structure break confirmed");
    }
    
    // Cap confidence to valid range [0.0, 1.0]
    confidence = MathMin(1.0, MathMax(0.0, confidence));
    
    return true;
}

//+------------------------------------------------------------------+
//| Apply Time Filter                                               |
//+------------------------------------------------------------------+
bool CUnifiedSignalPipeline::ApplyTimeFilter(ENUM_TRADE_SIGNAL &signal)
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Skip Asian session (example: 22:00 - 07:00 GMT)
    if(dt.hour >= 22 || dt.hour < 7)
    {
        LogFilterResult("TimeFilter", false, "Asian session - trading disabled");
        return false;
    }
    
    // Skip weekends
    if(dt.day_of_week == 0 || dt.day_of_week == 6)
    {
        LogFilterResult("TimeFilter", false, "Weekend - trading disabled");
        return false;
    }
    
    LogFilterResult("TimeFilter", true, "Active trading session");
    return true;
}

//+------------------------------------------------------------------+
//| Log Filter Result                                               |
//+------------------------------------------------------------------+
void CUnifiedSignalPipeline::LogFilterResult(const string filter, bool passed, const string reason)
{
    if(m_diagnostics == NULL)
        return;
    
    string status = passed ? "PASSED" : "FAILED";
    string msg = StringFormat("[Pipeline] %s: %s - %s", filter, status, reason);
    Print(msg);
}

#endif // UNIFIED_SIGNAL_PIPELINE_MQH
