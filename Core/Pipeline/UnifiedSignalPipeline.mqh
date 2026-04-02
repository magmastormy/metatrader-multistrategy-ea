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
#include "../Engines/RegimeEngine.mqh"
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
    double intrabarConfidenceCap;
    bool enableRegimeCostGate;
    double maxSpreadToAtrRatio;
    int spreadShockCooldownSeconds;
    double maxEntryRangeZScore;
    double maxVolatility;
    int minTrendStrength;
    
    SignalFilterSettings() : 
        enableTrendFilter(true),
        enableVolatilityFilter(true),
        enableLiquidityFilter(true),
        enableStructureFilter(true),
        enableTimeFilter(false),
        minConfidence(0.40),
        intrabarConfidenceCap(0.05),
        enableRegimeCostGate(true),
        maxSpreadToAtrRatio(0.25),
        spreadShockCooldownSeconds(30),
        maxEntryRangeZScore(2.50),
        maxVolatility(3.0),
        minTrendStrength(50) {}
};

//+------------------------------------------------------------------+
//| Pipeline evidence snapshot                                       |
//+------------------------------------------------------------------+
struct SPipelineEvidenceSnapshot
{
    string symbol;
    ENUM_TIMEFRAMES timeframe;
    bool contextPrepared;
    bool trendReady;
    bool structureReady;
    bool liquidityReady;
    bool volatilityReady;
    bool regimeValid;
    ENUM_TREND_TYPE trend;
    double trendStrength;
    ENUM_VOLATILITY_STATE volatilityState;
    double atrValue;
    double atrPercent;
    double structureStrength;
    bool bullishStructure;
    bool bearishStructure;
    bool liquiditySweep;
    bool priceNearLiquidity;
    ENUM_REGIME_STATE regimeState;
    double spreadToAtrRatio;
    double rangeZScore;
    string readinessClass;
    bool reuseActive;
    int stalenessSeconds;
    double stalenessPenalty;
    double readinessScore;
    double contextScore;
    double costScore;
    double effectiveMinConfidence;
    bool softThresholdPass;
    string vetoReasonTag;

    SPipelineEvidenceSnapshot()
    {
        symbol = "";
        timeframe = PERIOD_CURRENT;
        contextPrepared = false;
        trendReady = false;
        structureReady = false;
        liquidityReady = false;
        volatilityReady = false;
        regimeValid = false;
        trend = TREND_NONE;
        trendStrength = 0.0;
        volatilityState = VOLATILITY_LOW;
        atrValue = 0.0;
        atrPercent = 0.0;
        structureStrength = 0.0;
        bullishStructure = false;
        bearishStructure = false;
        liquiditySweep = false;
        priceNearLiquidity = false;
        regimeState = REGIME_RANGE;
        spreadToAtrRatio = 0.0;
        rangeZScore = 0.0;
        readinessClass = "WARMUP";
        reuseActive = false;
        stalenessSeconds = 0;
        stalenessPenalty = 0.0;
        readinessScore = 0.5;
        contextScore = 0.5;
        costScore = 0.5;
        effectiveMinConfidence = 0.4;
        softThresholdPass = false;
        vetoReasonTag = "";
    }
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
    CRegimeEngine* m_regimeEngine;
    
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
    bool m_intrabarContext;
    bool m_lastRegimeSnapshotValid;
    ENUM_REGIME_STATE m_lastRegimeState;
    double m_lastEffectiveMinConfidence;
    SPipelineEvidenceSnapshot m_lastEvidence;
    SPipelineEvidenceSnapshot m_cachedStructuralEvidence;
    string m_cachedContextSymbol;
    ENUM_TIMEFRAMES m_cachedContextTimeframe;
    datetime m_cachedContextBarTime;
    bool m_cachedContextPrepared;
    
    // Internal methods
    void ResetEvidenceSnapshot(const string symbol, ENUM_TIMEFRAMES timeframe);
    bool RefreshStructuralContext(const string symbol, ENUM_TIMEFRAMES timeframe);
    void RefreshEvidenceFromEngines(const string symbol);
    double ComputeReadinessScore() const;
    double ComputeContextScore(const ENUM_TRADE_SIGNAL signal) const;
    bool ApplyTrendFilter(ENUM_TRADE_SIGNAL &signal, double &confidence);
    bool ApplyVolatilityFilter(ENUM_TRADE_SIGNAL &signal, double &confidence);
    bool ApplyLiquidityFilter(ENUM_TRADE_SIGNAL &signal, double &confidence, const string symbol);
    bool ApplyStructureFilter(ENUM_TRADE_SIGNAL &signal, double &confidence);
    bool ApplyTimeFilter(ENUM_TRADE_SIGNAL &signal);
    bool ApplyRegimeAndCostGate(const string symbol,
                                ENUM_TIMEFRAMES timeframe,
                                ENUM_TRADE_SIGNAL &signal,
                                double &confidence,
                                string &vetoReasonTag);
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
    void SetFilters(SignalFilterSettings &settings);
    SignalFilterSettings GetFilters() const { return m_filters; }
    void SetIntrabarContext(const bool intrabarContext) { m_intrabarContext = intrabarContext; }
    
    // Statistics
    int GetSignalsProcessed() const { return m_signalsProcessed; }
    int GetSignalsFiltered() const { return m_signalsFiltered; }
    int GetSignalsPassed() const { return m_signalsPassed; }
    bool WasLastSignalRawNone() const { return m_lastRawSignalNone; }
    bool WasLastSignalFilteredByPipeline() const { return m_lastFilteredByPipeline; }
    string GetLastEvaluatedSymbol() const { return m_lastEvaluatedSymbol; }
    double GetLastEffectiveMinConfidence() const { return m_lastEffectiveMinConfidence; }
    void GetLastEvidenceSnapshot(SPipelineEvidenceSnapshot &snapshot) const { snapshot = m_lastEvidence; }
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
    CRegimeEngine* GetRegimeEngine() { return m_regimeEngine; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CUnifiedSignalPipeline::CUnifiedSignalPipeline() :
    m_trendEngine(NULL),
    m_structureEngine(NULL),
    m_liquidityEngine(NULL),
    m_volatilityEngine(NULL),
    m_regimeEngine(NULL),
    m_diagnostics(NULL),
    m_tfConsistency(NULL),
    m_hedgingProtection(NULL),
    m_signalsProcessed(0),
    m_signalsFiltered(0),
    m_signalsPassed(0),
    m_lastEvaluatedSymbol(""),
    m_lastRawSignalNone(false),
    m_lastFilteredByPipeline(false),
    m_intrabarContext(false),
    m_lastRegimeSnapshotValid(false),
    m_lastRegimeState(REGIME_RANGE),
    m_lastEffectiveMinConfidence(0.40),
    m_cachedContextSymbol(""),
    m_cachedContextTimeframe(PERIOD_CURRENT),
    m_cachedContextBarTime(0),
    m_cachedContextPrepared(false)
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
    if(m_regimeEngine != NULL) { delete m_regimeEngine; m_regimeEngine = NULL; }
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
    bool initializationOk = true;
    
    // Initialize diagnostics
    m_diagnostics = new CSignalDiagnostics();
    if(m_diagnostics != NULL)
        m_diagnostics.Initialize(1000, 3);
    else
        initializationOk = false;
    
    // Initialize consistency checker
    m_tfConsistency = new CTimeframeConsistency();
    if(m_tfConsistency != NULL)
        m_tfConsistency.Initialize(CONFLICT_RES_WEIGHTED, 0.6, false);
    else
        initializationOk = false;
    
    // Initialize hedging protection
    m_hedgingProtection = new CHedgingProtection();
    if(m_hedgingProtection != NULL)
        m_hedgingProtection.Initialize(HEDGING_MODE_PREVENT, false);
    else
        initializationOk = false;
    
    // Initialize engines
    m_trendEngine = new CTrendEngine();
    if(m_trendEngine != NULL)
        m_trendEngine.Initialize(20, 50, 200, 14, m_diagnostics);
    else
        initializationOk = false;
    
    m_structureEngine = new CStructureEngine();
    if(m_structureEngine != NULL)
        m_structureEngine.Initialize(10, 10.0, true, m_diagnostics);
    else
        initializationOk = false;
    
    m_liquidityEngine = new CLiquidityEngine();
    if(m_liquidityEngine != NULL)
        m_liquidityEngine.Initialize(10.0, 2, m_diagnostics);
    else
        initializationOk = false;
    
    m_volatilityEngine = new CVolatilityEngine();
    if(m_volatilityEngine != NULL)
        m_volatilityEngine.Initialize(14, 20, m_diagnostics);
    else
        initializationOk = false;

    m_regimeEngine = new CRegimeEngine();
    if(m_regimeEngine != NULL)
    {
        m_regimeEngine.Initialize(14, 20, 2.0, 30, 120);
        m_regimeEngine.ConfigureCostLimits(m_filters.maxSpreadToAtrRatio,
                                           m_filters.spreadShockCooldownSeconds,
                                           m_filters.maxEntryRangeZScore);
    }
    else
        initializationOk = false;
    
    Print("[UnifiedSignalPipeline] Initialized with filters: Trend=", m_filters.enableTrendFilter,
          " Volatility=", m_filters.enableVolatilityFilter,
          " Liquidity=", m_filters.enableLiquidityFilter,
          " Structure=", m_filters.enableStructureFilter,
          " RegimeCostGate=", m_filters.enableRegimeCostGate,
          " MaxSpreadATR=", DoubleToString(m_filters.maxSpreadToAtrRatio, 3),
          " SpreadShockCooldown=", m_filters.spreadShockCooldownSeconds,
          " MaxEntryZ=", DoubleToString(m_filters.maxEntryRangeZScore, 2));

    if(!initializationOk)
        Print("[UnifiedSignalPipeline] ERROR: component initialization incomplete; fail-closed startup");
    
    return initializationOk;
}

void CUnifiedSignalPipeline::SetFilters(SignalFilterSettings &settings)
{
    m_filters = settings;
    if(m_regimeEngine != NULL)
    {
        m_regimeEngine.ConfigureCostLimits(m_filters.maxSpreadToAtrRatio,
                                           m_filters.spreadShockCooldownSeconds,
                                           m_filters.maxEntryRangeZScore);
    }
}

void CUnifiedSignalPipeline::ResetEvidenceSnapshot(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_lastEvidence = SPipelineEvidenceSnapshot();
    m_lastEvidence.symbol = symbol;
    m_lastEvidence.timeframe = timeframe;
    m_lastEvidence.effectiveMinConfidence = MathMax(0.0, MathMin(1.0, m_filters.minConfidence));
}

bool CUnifiedSignalPipeline::RefreshStructuralContext(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    datetime barTime = iTime(symbol, timeframe, 0);
    if(barTime <= 0)
        barTime = TimeCurrent();

    bool cacheHit = (m_cachedContextPrepared &&
                     m_cachedContextSymbol == symbol &&
                     m_cachedContextTimeframe == timeframe &&
                     m_cachedContextBarTime == barTime);

    if(!cacheHit)
    {
        m_lastEvidence.trendReady = (m_trendEngine != NULL) && m_trendEngine.UpdateTrend(symbol, timeframe);
        m_lastEvidence.structureReady = (m_structureEngine != NULL) && m_structureEngine.DetectSwingPoints(symbol, timeframe);
        m_lastEvidence.liquidityReady = (m_liquidityEngine != NULL) && m_liquidityEngine.DetectLiquidityZones(symbol, timeframe);
        m_lastEvidence.volatilityReady = (m_volatilityEngine != NULL) && m_volatilityEngine.UpdateVolatility(symbol, timeframe);

        RefreshEvidenceFromEngines(symbol);
        m_lastEvidence.contextPrepared = true;
        m_lastEvidence.readinessScore = ComputeReadinessScore();
        m_cachedStructuralEvidence = m_lastEvidence;

        m_cachedContextSymbol = symbol;
        m_cachedContextTimeframe = timeframe;
        m_cachedContextBarTime = barTime;
        m_cachedContextPrepared = true;
    }
    else
    {
        m_lastEvidence.trendReady = m_cachedStructuralEvidence.trendReady;
        m_lastEvidence.structureReady = m_cachedStructuralEvidence.structureReady;
        m_lastEvidence.liquidityReady = m_cachedStructuralEvidence.liquidityReady;
        m_lastEvidence.volatilityReady = m_cachedStructuralEvidence.volatilityReady;
        m_lastEvidence.trend = m_cachedStructuralEvidence.trend;
        m_lastEvidence.trendStrength = m_cachedStructuralEvidence.trendStrength;
        m_lastEvidence.volatilityState = m_cachedStructuralEvidence.volatilityState;
        m_lastEvidence.atrValue = m_cachedStructuralEvidence.atrValue;
        m_lastEvidence.atrPercent = m_cachedStructuralEvidence.atrPercent;
        m_lastEvidence.structureStrength = m_cachedStructuralEvidence.structureStrength;
        m_lastEvidence.bullishStructure = m_cachedStructuralEvidence.bullishStructure;
        m_lastEvidence.bearishStructure = m_cachedStructuralEvidence.bearishStructure;
        m_lastEvidence.liquiditySweep = m_cachedStructuralEvidence.liquiditySweep;
        m_lastEvidence.priceNearLiquidity = m_cachedStructuralEvidence.priceNearLiquidity;
        m_lastEvidence.contextPrepared = m_cachedStructuralEvidence.contextPrepared;
        RefreshEvidenceFromEngines(symbol);
        m_lastEvidence.readinessScore = ComputeReadinessScore();
    }

    return true;
}

void CUnifiedSignalPipeline::RefreshEvidenceFromEngines(const string symbol)
{
    m_lastEvidence.readinessClass = "WARMUP";
    m_lastEvidence.reuseActive = false;
    m_lastEvidence.stalenessSeconds = 0;
    m_lastEvidence.stalenessPenalty = 0.0;

    if(m_trendEngine != NULL && m_lastEvidence.trendReady)
    {
        m_lastEvidence.trend = m_trendEngine.GetCurrentTrend();
        m_lastEvidence.trendStrength = m_trendEngine.GetTrendStrength();
        STrendReadinessSnapshot trendReadiness = m_trendEngine.GetReadinessSnapshot();
        if(trendReadiness.state == TREND_READINESS_HEALTHY)
            m_lastEvidence.readinessClass = "HEALTHY";
        else if(trendReadiness.state == TREND_READINESS_REUSED_SNAPSHOT)
            m_lastEvidence.readinessClass = "REUSED_SNAPSHOT";
        else if(trendReadiness.state == TREND_READINESS_TRANSIENT_COPY_FAULT)
            m_lastEvidence.readinessClass = "TRANSIENT_COPY_FAULT";
        else if(trendReadiness.state == TREND_READINESS_HANDLE_FAULT)
            m_lastEvidence.readinessClass = "HANDLE_FAULT";
        else
            m_lastEvidence.readinessClass = "WARMUP";
        m_lastEvidence.reuseActive = trendReadiness.reuseActive;
        m_lastEvidence.stalenessSeconds = trendReadiness.stalenessSeconds;
        m_lastEvidence.stalenessPenalty = MathMin(0.30, (double)trendReadiness.stalenessSeconds / (double)MathMax(10, 2 * 60) * 0.30);
    }
    else
    {
        m_lastEvidence.trend = TREND_NONE;
        m_lastEvidence.trendStrength = 0.0;
        if(m_trendEngine != NULL)
        {
            STrendReadinessSnapshot trendReadiness = m_trendEngine.GetReadinessSnapshot();
            if(trendReadiness.state == TREND_READINESS_HEALTHY)
                m_lastEvidence.readinessClass = "HEALTHY";
            else if(trendReadiness.state == TREND_READINESS_REUSED_SNAPSHOT)
                m_lastEvidence.readinessClass = "REUSED_SNAPSHOT";
            else if(trendReadiness.state == TREND_READINESS_TRANSIENT_COPY_FAULT)
                m_lastEvidence.readinessClass = "TRANSIENT_COPY_FAULT";
            else if(trendReadiness.state == TREND_READINESS_HANDLE_FAULT)
                m_lastEvidence.readinessClass = "HANDLE_FAULT";
            else
                m_lastEvidence.readinessClass = "WARMUP";
            m_lastEvidence.reuseActive = trendReadiness.reuseActive;
            m_lastEvidence.stalenessSeconds = trendReadiness.stalenessSeconds;
            m_lastEvidence.stalenessPenalty = MathMin(0.30, (double)trendReadiness.stalenessSeconds / (double)MathMax(10, 2 * 60) * 0.30);
        }
    }

    if(m_structureEngine != NULL && m_lastEvidence.structureReady)
    {
        m_lastEvidence.structureStrength = m_structureEngine.GetStructureStrength();
        m_lastEvidence.bullishStructure = (m_structureEngine.HasBullishBOS(5) || m_structureEngine.HasBullishCHOCH(5));
        m_lastEvidence.bearishStructure = (m_structureEngine.HasBearishBOS(5) || m_structureEngine.HasBearishCHOCH(5));
    }
    else
    {
        m_lastEvidence.structureStrength = 0.0;
        m_lastEvidence.bullishStructure = false;
        m_lastEvidence.bearishStructure = false;
    }

    if(m_liquidityEngine != NULL && m_lastEvidence.liquidityReady)
    {
        double probePrice = SymbolInfoDouble(symbol, SYMBOL_BID);
        if(probePrice <= 0.0)
            probePrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
        m_lastEvidence.liquiditySweep = m_liquidityEngine.HasLiquiditySweep(5);
        m_lastEvidence.priceNearLiquidity = (probePrice > 0.0) ? m_liquidityEngine.IsPriceNearLiquidity(probePrice, 30) : false;
    }
    else
    {
        m_lastEvidence.liquiditySweep = false;
        m_lastEvidence.priceNearLiquidity = false;
    }

    if(m_volatilityEngine != NULL && m_lastEvidence.volatilityReady)
    {
        m_lastEvidence.volatilityState = m_volatilityEngine.GetVolatilityState();
        m_lastEvidence.atrValue = m_volatilityEngine.GetATR();
        m_lastEvidence.atrPercent = m_volatilityEngine.GetATRPercent();
    }
    else
    {
        m_lastEvidence.volatilityState = VOLATILITY_LOW;
        m_lastEvidence.atrValue = 0.0;
        m_lastEvidence.atrPercent = 0.0;
    }
}

double CUnifiedSignalPipeline::ComputeReadinessScore() const
{
    double total = 0.0;
    int components = 0;
    double trendReadinessScore = 0.55;
    if(m_lastEvidence.readinessClass == "HEALTHY")
        trendReadinessScore = 1.00;
    else if(m_lastEvidence.readinessClass == "REUSED_SNAPSHOT")
        trendReadinessScore = MathMax(0.45, 0.82 - m_lastEvidence.stalenessPenalty);
    else if(m_lastEvidence.readinessClass == "TRANSIENT_COPY_FAULT")
        trendReadinessScore = 0.60;
    else if(m_lastEvidence.readinessClass == "HANDLE_FAULT")
        trendReadinessScore = 0.35;
    else if(m_lastEvidence.readinessClass == "WARMUP")
        trendReadinessScore = 0.55;

    if(m_filters.enableTrendFilter)
    {
        total += m_lastEvidence.trendReady ? trendReadinessScore : MathMin(trendReadinessScore, 0.65);
        components++;
    }

    if(m_filters.enableStructureFilter)
    {
        total += m_lastEvidence.structureReady ? 1.0 : 0.65;
        components++;
    }

    if(m_filters.enableLiquidityFilter)
    {
        total += m_lastEvidence.liquidityReady ? 1.0 : 0.70;
        components++;
    }

    if(m_filters.enableVolatilityFilter)
    {
        total += m_lastEvidence.volatilityReady ? 1.0 : 0.55;
        components++;
    }

    if(m_filters.enableRegimeCostGate)
    {
        total += m_lastEvidence.regimeValid ? MathMax(0.70, 1.0 - m_lastEvidence.stalenessPenalty) : 0.70;
        components++;
    }

    if(components <= 0)
        return 1.0;

    return MathMax(0.0, MathMin(1.0, total / components));
}

double CUnifiedSignalPipeline::ComputeContextScore(const ENUM_TRADE_SIGNAL signal) const
{
    double trendScore = 0.75;
    if(signal == TRADE_SIGNAL_BUY)
    {
        if(m_lastEvidence.trend == TREND_BULLISH_STRONG || m_lastEvidence.trend == TREND_BULLISH_WEAK)
            trendScore = (m_lastEvidence.trendStrength >= 70.0) ? 1.0 : 0.88;
        else if(m_lastEvidence.trend == TREND_BEARISH_STRONG || m_lastEvidence.trend == TREND_BEARISH_WEAK)
            trendScore = (m_lastEvidence.trendStrength >= 70.0) ? 0.45 : 0.65;
    }
    else if(signal == TRADE_SIGNAL_SELL)
    {
        if(m_lastEvidence.trend == TREND_BEARISH_STRONG || m_lastEvidence.trend == TREND_BEARISH_WEAK)
            trendScore = (m_lastEvidence.trendStrength >= 70.0) ? 1.0 : 0.88;
        else if(m_lastEvidence.trend == TREND_BULLISH_STRONG || m_lastEvidence.trend == TREND_BULLISH_WEAK)
            trendScore = (m_lastEvidence.trendStrength >= 70.0) ? 0.45 : 0.65;
    }

    double structureScore = 0.72;
    if(signal == TRADE_SIGNAL_BUY && m_lastEvidence.bullishStructure)
        structureScore = 1.0;
    else if(signal == TRADE_SIGNAL_SELL && m_lastEvidence.bearishStructure)
        structureScore = 1.0;
    else if(m_lastEvidence.structureStrength > 0.0)
        structureScore = MathMax(0.55, MathMin(0.95, 0.60 + (m_lastEvidence.structureStrength / 250.0)));

    double liquidityScore = 0.72;
    if(m_lastEvidence.liquiditySweep)
        liquidityScore = 0.95;
    if(m_lastEvidence.priceNearLiquidity)
        liquidityScore = MathMin(liquidityScore, 0.78);

    double volatilityScore = 0.80;
    if(m_lastEvidence.volatilityState == VOLATILITY_NORMAL)
        volatilityScore = 1.0;
    else if(m_lastEvidence.volatilityState == VOLATILITY_LOW)
        volatilityScore = 0.88;
    else if(m_lastEvidence.volatilityState == VOLATILITY_HIGH)
        volatilityScore = 0.74;
    else if(m_lastEvidence.volatilityState == VOLATILITY_EXTREME)
        volatilityScore = 0.45;

    double regimeScore = m_lastEvidence.costScore;
    if(!m_lastEvidence.regimeValid)
        regimeScore = MathMin(regimeScore, 0.72);
    else if(m_lastEvidence.regimeState == REGIME_BREAKOUT || m_lastEvidence.regimeState == REGIME_TREND)
        regimeScore = MathMax(regimeScore, 0.92);
    else if(m_lastEvidence.regimeState == REGIME_RANGE)
        regimeScore = MathMin(MathMax(regimeScore, 0.75), 0.88);
    else if(m_lastEvidence.regimeState == REGIME_CHAOS)
        regimeScore = MathMin(regimeScore, 0.68);

    double total = trendScore + structureScore + liquidityScore + volatilityScore + regimeScore;
    return MathMax(0.0, MathMin(1.0, total / 5.0));
}

//+------------------------------------------------------------------+
//| Process Single Strategy Signal                                  |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CUnifiedSignalPipeline::ProcessSignal(IStrategy* strategy, 
                                                       const string symbol,
                                                       ENUM_TIMEFRAMES timeframe, 
                                                       double &confidence)
{
    ResetEvidenceSnapshot(symbol, timeframe);
    m_lastEvaluatedSymbol = symbol;
    m_lastRawSignalNone = false;
    m_lastFilteredByPipeline = false;
    m_lastRegimeSnapshotValid = false;
    m_lastRegimeState = REGIME_RANGE;
    m_lastEffectiveMinConfidence = MathMax(0.0, MathMin(1.0, m_filters.minConfidence));

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
    
    RefreshStructuralContext(symbol, timeframe);
    
    // Apply filters
    bool passed = true;

    if(m_filters.enableRegimeCostGate)
    {
        string regimeVetoReason = "";
        bool regimePassed = ApplyRegimeAndCostGate(symbol, timeframe, signal, confidence, regimeVetoReason);
        if(!regimePassed)
        {
            passed = false;
            LogFilterResult("RegimeCostGate", false, regimeVetoReason);
        }
    }
    
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

    m_lastEvidence.contextScore = ComputeContextScore(signal);
    m_lastEvidence.readinessScore = ComputeReadinessScore();
    
    // Dynamic confidence threshold with bounded intrabar uplift in weak regimes.
    double baseMinConfidence = m_filters.minConfidence;
    double effectiveMinConfidence = baseMinConfidence;
    double appliedCap = 0.0;
    string thresholdReasonTag = "BASE_THRESHOLD";

    if(m_lastRegimeSnapshotValid)
    {
        if(m_lastRegimeState == REGIME_RANGE)
        {
            thresholdReasonTag = "REGIME_RANGE";
            double multiplierThreshold = MathMax(baseMinConfidence, baseMinConfidence * 1.03);
            if(m_intrabarContext)
            {
                appliedCap = MathMax(0.0, m_filters.intrabarConfidenceCap);
                double cappedThreshold = baseMinConfidence + appliedCap;
                effectiveMinConfidence = MathMin(1.0, MathMin(cappedThreshold, multiplierThreshold));
            }
            else
            {
                effectiveMinConfidence = MathMin(1.0, multiplierThreshold);
            }
        }
        else if(m_lastRegimeState == REGIME_TREND)
        {
            thresholdReasonTag = "REGIME_TREND_RELAX";
            effectiveMinConfidence = MathMax(0.0, baseMinConfidence * 0.92);
        }
        else if(m_lastRegimeState == REGIME_BREAKOUT)
        {
            thresholdReasonTag = "REGIME_BREAKOUT_RELAX";
            effectiveMinConfidence = MathMax(0.0, baseMinConfidence * 0.90);
        }
        else if(m_lastRegimeState == REGIME_CHAOS)
        {
            thresholdReasonTag = "REGIME_CHAOS";
            double multiplierThreshold = MathMax(baseMinConfidence, baseMinConfidence * 1.05);
            if(m_intrabarContext)
            {
                appliedCap = MathMax(0.0, m_filters.intrabarConfidenceCap);
                double cappedThreshold = baseMinConfidence + appliedCap;
                effectiveMinConfidence = MathMin(1.0, MathMin(cappedThreshold, multiplierThreshold));
            }
            else
            {
                effectiveMinConfidence = MathMin(1.0, multiplierThreshold);
            }
        }
    }
    else if(m_trendEngine != NULL)
    {
        if(m_trendEngine.IsStrongTrend())
        {
            thresholdReasonTag = "TREND_ENGINE_STRONG_RELAX";
            effectiveMinConfidence = MathMax(0.0, baseMinConfidence * 0.95);
        }
        else
        {
            thresholdReasonTag = "REGIME_ENGINE_WARMUP";
        }
    }

    PrintFormat("[PIPELINE-THRESHOLD] base=%.2f | effective=%.2f | regime=%s | cap=%.2f | intrabar=%s",
                baseMinConfidence,
                effectiveMinConfidence,
                thresholdReasonTag,
                appliedCap,
                m_intrabarContext ? "true" : "false");
    m_lastEffectiveMinConfidence = MathMax(0.0, MathMin(1.0, effectiveMinConfidence));
    m_lastEvidence.effectiveMinConfidence = m_lastEffectiveMinConfidence;
    
    // Check confidence threshold
    if(confidence < effectiveMinConfidence)
    {
        double thresholdGap = effectiveMinConfidence - confidence;
        double softBand = 0.06;
        bool softPass = (thresholdGap <= softBand &&
                         m_lastEvidence.contextScore >= 0.62 &&
                         m_lastEvidence.readinessScore >= 0.65);
        if(softPass)
        {
            double attenuation = 1.0 - MathMin(0.35, (thresholdGap / softBand) * 0.35);
            confidence = MathMax(0.0, MathMin(1.0, confidence * attenuation));
            m_lastEvidence.softThresholdPass = true;
            LogFilterResult("ConfidenceFilter", true,
                           StringFormat("%s | soft-admit gap=%.3f | adjusted_conf=%.2f | effective=%.2f",
                                        thresholdReasonTag, thresholdGap, confidence, effectiveMinConfidence));
        }
        else
        {
            LogFilterResult("ConfidenceFilter", false, 
                           StringFormat("%s | Confidence %.2f below minimum %.2f (effective: %.2f)",
                                        thresholdReasonTag, confidence, baseMinConfidence, effectiveMinConfidence));
            passed = false;
        }
    }
    else if(confidence >= effectiveMinConfidence && confidence < baseMinConfidence)
    {
        LogFilterResult("ConfidenceFilter", true, 
                       StringFormat("%s | PASSED with adjusted threshold - Confidence: %.2f (min: %.2f, effective: %.2f)",
                                    thresholdReasonTag, confidence, baseMinConfidence, effectiveMinConfidence));
    }

    // Blend market context and readiness into the surviving confidence rather than using
    // a second binary gate. This preserves marginal but still-credible votes for consensus.
    if(passed)
    {
        double contextBlend = 0.80 + (0.20 * m_lastEvidence.contextScore);
        double readinessBlend = 0.85 + (0.15 * m_lastEvidence.readinessScore);
        double stalenessBlend = MathMax(0.70, 1.0 - m_lastEvidence.stalenessPenalty);
        confidence = MathMax(0.0, MathMin(1.0, confidence * contextBlend * readinessBlend * stalenessBlend));
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
//| Apply Regime + Cost Viability Gate                              |
//+------------------------------------------------------------------+
bool CUnifiedSignalPipeline::ApplyRegimeAndCostGate(const string symbol,
                                                    ENUM_TIMEFRAMES timeframe,
                                                    ENUM_TRADE_SIGNAL &signal,
                                                    double &confidence,
                                                    string &vetoReasonTag)
{
    vetoReasonTag = "";
    m_lastRegimeSnapshotValid = false;
    m_lastEvidence.costScore = 0.72;
    m_lastEvidence.regimeValid = false;
    if(m_regimeEngine == NULL)
        return true;

    if(!m_regimeEngine.Update(symbol, timeframe))
    {
        // Neutral degrade when regime engine data is warming/faulted.
        confidence = MathMax(0.0, confidence * 0.98);
        return true;
    }

    SRegimeSnapshot snapshot = m_regimeEngine.GetSnapshot();
    if(!snapshot.valid)
        return true;

    m_lastRegimeSnapshotValid = true;
    m_lastRegimeState = snapshot.state;
    m_lastEvidence.regimeValid = true;
    m_lastEvidence.regimeState = snapshot.state;
    m_lastEvidence.spreadToAtrRatio = snapshot.spreadToAtrRatio;
    m_lastEvidence.rangeZScore = snapshot.rangeZScore;
    if(snapshot.readinessClass != "")
        m_lastEvidence.readinessClass = snapshot.readinessClass;
    m_lastEvidence.reuseActive = (m_lastEvidence.reuseActive || snapshot.reuseActive);
    m_lastEvidence.stalenessSeconds = MathMax(m_lastEvidence.stalenessSeconds, snapshot.stalenessSeconds);
    m_lastEvidence.stalenessPenalty = MathMax(m_lastEvidence.stalenessPenalty,
                                              MathMin(0.30, (double)snapshot.stalenessSeconds / (double)MathMax(10, 2 * 60) * 0.30));

    string regimeTag = m_regimeEngine.GetStateTag();
    PrintFormat("[COST-GATE] %s | regime=%s | spread_atr=%.4f/%.4f | cooldown=%s | z=%.3f/%.3f",
                symbol,
                regimeTag,
                snapshot.spreadToAtrRatio,
                m_filters.maxSpreadToAtrRatio,
                snapshot.spreadShockCooldownActive ? "true" : "false",
                snapshot.rangeZScore,
                m_filters.maxEntryRangeZScore);

    // Regime-aware confidence attenuation while preserving deterministic output.
    // REDUCED PENALTIES: was 0.97 RANGE, 0.92 CHAOS - now much lighter to avoid blocking marginal signals
    if(snapshot.state == REGIME_RANGE)
        confidence = MathMax(0.0, confidence * 0.99);  // Minimal penalty for ranging
    else if(snapshot.state == REGIME_CHAOS)
        confidence = MathMax(0.0, confidence * 0.97);  // Reduced from 0.92 for chaos

    double spreadPenalty = 0.0;
    if(m_filters.maxSpreadToAtrRatio > 0.0)
        spreadPenalty = MathMin(0.30, (snapshot.spreadToAtrRatio / m_filters.maxSpreadToAtrRatio) * 0.15);
    double zPenalty = 0.0;
    if(m_filters.maxEntryRangeZScore > 0.0)
        zPenalty = MathMin(0.20, (MathAbs(snapshot.rangeZScore) / m_filters.maxEntryRangeZScore) * 0.10);
    double regimeBaseScore = 0.85;
    if(snapshot.state == REGIME_TREND || snapshot.state == REGIME_BREAKOUT)
        regimeBaseScore = 1.0;
    else if(snapshot.state == REGIME_RANGE)
        regimeBaseScore = 0.84;
    else if(snapshot.state == REGIME_CHAOS)
        regimeBaseScore = 0.62;
    if(snapshot.reuseActive)
        regimeBaseScore = MathMin(regimeBaseScore, 0.82);
    m_lastEvidence.costScore = MathMax(0.10, MathMin(1.0, regimeBaseScore - spreadPenalty - zPenalty));

    if(snapshot.spreadShockCooldownActive)
    {
        vetoReasonTag = StringFormat("REGIME_%s | spread shock cooldown active", regimeTag);
        m_lastEvidence.vetoReasonTag = vetoReasonTag;
        PrintFormat("[ENTRY-VETO] %s | reason=%s", symbol, vetoReasonTag);
        signal = TRADE_SIGNAL_NONE;
        confidence = 0.0;
        return false;
    }

    if(snapshot.spreadToAtrRatio > m_filters.maxSpreadToAtrRatio)
    {
        vetoReasonTag = StringFormat("REGIME_%s | spread/ATR ratio %.4f exceeds %.4f",
                                     regimeTag, snapshot.spreadToAtrRatio, m_filters.maxSpreadToAtrRatio);
        m_lastEvidence.vetoReasonTag = vetoReasonTag;
        PrintFormat("[ENTRY-VETO] %s | reason=%s", symbol, vetoReasonTag);
        signal = TRADE_SIGNAL_NONE;
        confidence = 0.0;
        return false;
    }

    if(MathAbs(snapshot.rangeZScore) > m_filters.maxEntryRangeZScore)
    {
        vetoReasonTag = StringFormat("REGIME_%s | late-entry z-score %.3f exceeds %.3f",
                                     regimeTag, snapshot.rangeZScore, m_filters.maxEntryRangeZScore);
        m_lastEvidence.vetoReasonTag = vetoReasonTag;
        PrintFormat("[ENTRY-VETO] %s | reason=%s", symbol, vetoReasonTag);
        signal = TRADE_SIGNAL_NONE;
        confidence = 0.0;
        return false;
    }

    return true;
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
        if(trendStrength >= 85.0)
        {
            LogFilterResult("TrendFilter", false, 
                           StringFormat("Hard opposing trend veto: %s (%.1f)", 
                                      EnumToString(trend), trendStrength));
            return false;
        }

        confidence *= 0.72;
        confidence = MathMin(1.0, MathMax(0.0, confidence));
        LogFilterResult("TrendFilter", true,
                       StringFormat("Opposing trend attenuated: %s (%.1f)", EnumToString(trend), trendStrength));
        return true;
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
        if(trendStrength < 60)
        {
            confidence *= 0.93;
            LogFilterResult("TrendFilter", true, 
                           StringFormat("Weak trend misalignment (%.1f) - ALLOWING signal", trendStrength));
            return true;
        }

        confidence *= 0.80;
        confidence = MathMin(1.0, MathMax(0.0, confidence));
        LogFilterResult("TrendFilter", true, 
                       StringFormat("Managed trend misalignment: %s (%.1f) | confidence attenuated", 
                                  EnumToString(trend), trendStrength));
        return true;
    }
    
    // Boost confidence for strong aligned trends
    if(m_trendEngine.IsStrongTrend())
        confidence *= 1.10;
    
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
    double hardVolatilityLimit = m_filters.maxVolatility * 1.35;
    if(atrPercent > hardVolatilityLimit)
    {
        LogFilterResult("VolatilityFilter", false, 
                       StringFormat("Volatility %.2f%% exceeds hard maximum %.2f%%", 
                                  atrPercent, hardVolatilityLimit));
        return false;
    }
    else if(atrPercent > m_filters.maxVolatility)
    {
        confidence *= 0.82;
        confidence = MathMin(1.0, MathMax(0.0, confidence));
        LogFilterResult("VolatilityFilter", true,
                       StringFormat("Volatility %.2f%% above soft maximum %.2f%% | confidence attenuated",
                                    atrPercent, m_filters.maxVolatility));
        return true;
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
