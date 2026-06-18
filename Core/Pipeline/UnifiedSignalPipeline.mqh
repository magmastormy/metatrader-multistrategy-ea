//+------------------------------------------------------------------+
//| Unified Signal Pipeline - Enterprise Grade                       |
//| Central hub for all strategy signals with filtering              |
//+------------------------------------------------------------------+
#ifndef UNIFIED_SIGNAL_PIPELINE_MQH
#define UNIFIED_SIGNAL_PIPELINE_MQH

#include "../Utils/Enums.mqh"
#include "../Signals/TimeframeConsistency.mqh"
#include "../Engines/TrendEngine.mqh"
#include "../Engines/StructureEngine.mqh"
#include "../Engines/LiquidityEngine.mqh"
#include "../Engines/VolatilityEngine.mqh"
#include "../Engines/RegimeEngine.mqh"
#include "../../Interfaces/IStrategy.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CMarketAnalysis;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;

//+------------------------------------------------------------------+
//| Filter Preset Types                                             |
//+------------------------------------------------------------------+
enum ENUM_FILTER_PRESET
{
    FILTER_PRESET_CONSERVATIVE,
    FILTER_PRESET_BALANCED,
    FILTER_PRESET_AGGRESSIVE,
    FILTER_PRESET_CUSTOM
};

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
    bool enableSessionFilter;
    bool allowSyntheticOffHours;
    bool tradeLondonSession;
    bool tradeNewYorkSession;
    bool tradeTokyoSession;
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
        enableSessionFilter(false),
        allowSyntheticOffHours(true),
        tradeLondonSession(true),
        tradeNewYorkSession(true),
        tradeTokyoSession(true),
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
    
    // Protection / consistency
    CTimeframeConsistency* m_tfConsistency;
    
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
    string m_lastFilterName;
    string m_lastFilterReason;
    SPipelineEvidenceSnapshot m_lastEvidence;
    SPipelineEvidenceSnapshot m_cachedStructuralEvidence;
    string m_cachedContextSymbol;
    ENUM_TIMEFRAMES m_cachedContextTimeframe;
    datetime m_cachedContextBarTime;
    bool m_cachedContextPrepared;
    
    // Engine health tracking
    bool m_trendEngineHealthy;
    bool m_structureEngineHealthy;
    bool m_liquidityEngineHealthy;
    bool m_volatilityEngineHealthy;
    bool m_regimeEngineHealthy;
    datetime m_lastHealthCheckTime;
    int m_healthCheckIntervalBars;
    
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
    bool ApplyTimeFilter(ENUM_TRADE_SIGNAL &signal, const string symbol = "");
    bool ApplySessionFilter(const string symbol = "");
    bool IsSyntheticSymbol(const string symbol);
    double CalculateQualityScore(double confidence, int confluence, bool passedFilters,
                                   double convictionScore, double readinessScore, double contextScore,
                                   double diversityScore, double costScore, double directionalQuality,
                                   double supportRatio);
    bool ApplyRegimeAndCostGate(const string symbol,
                                ENUM_TIMEFRAMES timeframe,
                                ENUM_TRADE_SIGNAL &signal,
                                double &confidence,
                                string &vetoReasonTag);
    void LogFilterResult(const string filter, bool passed, const string reason);
    
    // Health monitoring
    void CheckEngineHealth(const string symbol);
    bool IsEngineHealthy() const;
    
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
    void ApplyFilterPreset(ENUM_FILTER_PRESET preset);
    
    // Statistics
    int GetSignalsProcessed() const { return m_signalsProcessed; }
    int GetSignalsFiltered() const { return m_signalsFiltered; }
    int GetSignalsPassed() const { return m_signalsPassed; }
    bool WasLastSignalRawNone() const { return m_lastRawSignalNone; }
    bool WasLastSignalFilteredByPipeline() const { return m_lastFilteredByPipeline; }
    
    // Health monitoring
    void PerformHealthCheck(const string symbol);
    bool IsPipelineHealthy() const;
    string GetEngineHealthStatus() const;
    string GetLastEvaluatedSymbol() const { return m_lastEvaluatedSymbol; }
    double GetLastEffectiveMinConfidence() const { return m_lastEffectiveMinConfidence; }
    string GetLastFilterName() const { return m_lastFilterName; }
    string GetLastFilterReason() const { return m_lastFilterReason; }
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
    m_tfConsistency(NULL),
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
    m_lastFilterName(""),
    m_lastFilterReason(""),
    m_cachedContextSymbol(""),
    m_cachedContextTimeframe(PERIOD_CURRENT),
    m_cachedContextBarTime(0),
    m_cachedContextPrepared(false),
    m_trendEngineHealthy(false),
    m_structureEngineHealthy(false),
    m_liquidityEngineHealthy(false),
    m_volatilityEngineHealthy(false),
    m_regimeEngineHealthy(false),
    m_lastHealthCheckTime(0),
    m_healthCheckIntervalBars(100)
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
    if(m_tfConsistency != NULL) { delete m_tfConsistency; m_tfConsistency = NULL; }
}

//+------------------------------------------------------------------+
//| Initialize Pipeline                                             |
//+------------------------------------------------------------------+
bool CUnifiedSignalPipeline::Initialize(SignalFilterSettings &settings)
{
    m_filters = settings;
    bool initializationOk = true;
    
    // Initialize consistency checker
    m_tfConsistency = new CTimeframeConsistency();
    if(m_tfConsistency == NULL)
    {
        Print("[UnifiedSignalPipeline] ERROR: TimeframeConsistency allocation failed");
        initializationOk = false;
    }
    else if(!m_tfConsistency.Initialize(CONFLICT_RES_WEIGHTED, 0.6, false))
    {
        Print("[UnifiedSignalPipeline] ERROR: TimeframeConsistency initialization failed");
        delete m_tfConsistency;
        m_tfConsistency = NULL;
        initializationOk = false;
    }
    
    // Initialize engines
    m_trendEngine = new CTrendEngine();
    if(m_trendEngine == NULL)
    {
        Print("[UnifiedSignalPipeline] ERROR: TrendEngine allocation failed");
        initializationOk = false;
    }
    else if(!m_trendEngine.Initialize(20, 50, 200, 14, NULL))
    {
        Print("[UnifiedSignalPipeline] ERROR: TrendEngine initialization failed");
        delete m_trendEngine;
        m_trendEngine = NULL;
        initializationOk = false;
    }

    if(initializationOk)
    {
        m_structureEngine = new CStructureEngine();
        if(m_structureEngine == NULL)
        {
            Print("[UnifiedSignalPipeline] ERROR: StructureEngine allocation failed");
            initializationOk = false;
        }
        else if(!m_structureEngine.Initialize(10, 10.0, true, NULL))
        {
            Print("[UnifiedSignalPipeline] ERROR: StructureEngine initialization failed");
            delete m_structureEngine;
            m_structureEngine = NULL;
            initializationOk = false;
        }
    }

    if(initializationOk)
    {
        m_liquidityEngine = new CLiquidityEngine();
        if(m_liquidityEngine == NULL)
        {
            Print("[UnifiedSignalPipeline] ERROR: LiquidityEngine allocation failed");
            initializationOk = false;
        }
        else if(!m_liquidityEngine.Initialize(10.0, 2, NULL))
        {
            Print("[UnifiedSignalPipeline] ERROR: LiquidityEngine initialization failed");
            delete m_liquidityEngine;
            m_liquidityEngine = NULL;
            initializationOk = false;
        }
    }

    if(initializationOk)
    {
        m_volatilityEngine = new CVolatilityEngine();
        if(m_volatilityEngine == NULL)
        {
            Print("[UnifiedSignalPipeline] ERROR: VolatilityEngine allocation failed");
            initializationOk = false;
        }
        else if(!m_volatilityEngine.Initialize(14, 20, NULL))
        {
            Print("[UnifiedSignalPipeline] ERROR: VolatilityEngine initialization failed");
            delete m_volatilityEngine;
            m_volatilityEngine = NULL;
            initializationOk = false;
        }
    }

    if(initializationOk)
    {
        m_regimeEngine = new CRegimeEngine();
        if(m_regimeEngine == NULL)
        {
            Print("[UnifiedSignalPipeline] ERROR: RegimeEngine allocation failed");
            initializationOk = false;
        }
        else if(!m_regimeEngine.Initialize(14, 20, 2.0, 30, 120))
        {
            Print("[UnifiedSignalPipeline] ERROR: RegimeEngine initialization failed");
            delete m_regimeEngine;
            m_regimeEngine = NULL;
            initializationOk = false;
        }
        else
        {
            m_regimeEngine.ConfigureCostLimits(m_filters.maxSpreadToAtrRatio,
                                               m_filters.spreadShockCooldownSeconds,
                                               m_filters.maxEntryRangeZScore);
        }
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

    const int MAX_CACHE_STALENESS_BARS = 5;
    bool cacheStale = false;
    
    if(m_cachedContextPrepared)
    {
        datetime currentBar = iTime(symbol, timeframe, 0);
        datetime cachedBar = m_cachedContextBarTime;
        int barsDiff = (int)((currentBar - cachedBar) / PeriodSeconds(timeframe));
        cacheStale = (barsDiff >= MAX_CACHE_STALENESS_BARS);
    }

    bool cacheHit = (m_cachedContextPrepared &&
                     !cacheStale &&
                     m_cachedContextSymbol == symbol &&
                     m_cachedContextTimeframe == timeframe &&
                     m_cachedContextBarTime == barTime);
    
    if(cacheStale && m_cachedContextPrepared)
    {
        PrintFormat("[PIPELINE-CACHE] Symbol=%s | Cache stale (%d bars old), invalidating", symbol, 
                    (int)((iTime(symbol, timeframe, 0) - m_cachedContextBarTime) / PeriodSeconds(timeframe)));
        m_cachedContextPrepared = false;
    }

    if(!cacheHit)
    {
        // Cache miss: Update all engines and refresh evidence
        m_lastEvidence.trendReady = (m_trendEngine != NULL) && m_trendEngine.UpdateTrend(symbol, timeframe);
        m_lastEvidence.structureReady = (m_structureEngine != NULL) && m_structureEngine.DetectSwingPoints(symbol, timeframe);
        m_lastEvidence.liquidityReady = (m_liquidityEngine != NULL) && m_liquidityEngine.DetectLiquidityZones(symbol, timeframe);
        m_lastEvidence.volatilityReady = (m_volatilityEngine != NULL) && m_volatilityEngine.UpdateVolatility(symbol, timeframe);

        // Populate evidence snapshot from engines
        RefreshEvidenceFromEngines(symbol);
        m_lastEvidence.contextPrepared = true;
        m_lastEvidence.readinessScore = ComputeReadinessScore();
        
        // Cache the complete evidence snapshot
        m_cachedStructuralEvidence = m_lastEvidence;
        m_cachedContextSymbol = symbol;
        m_cachedContextTimeframe = timeframe;
        m_cachedContextBarTime = barTime;
        m_cachedContextPrepared = true;
    }
    else
    {
        // AUDIT FIX: Validate cached evidence matches current symbol/timeframe context
        if(m_cachedStructuralEvidence.symbol != symbol || m_cachedStructuralEvidence.timeframe != timeframe)
        {
            // Context mismatch - invalidate cache and treat as cache miss
            m_cachedContextPrepared = false;
            return RefreshStructuralContext(symbol, timeframe);
        }
        
        // Cache hit: Restore complete evidence snapshot from cache
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
        m_lastEvidence.readinessClass = m_cachedStructuralEvidence.readinessClass;
        m_lastEvidence.reuseActive = m_cachedStructuralEvidence.reuseActive;
        m_lastEvidence.stalenessSeconds = m_cachedStructuralEvidence.stalenessSeconds;
        m_lastEvidence.stalenessPenalty = m_cachedStructuralEvidence.stalenessPenalty;
        
        // Recompute readiness score based on restored evidence
        m_lastEvidence.readinessScore = ComputeReadinessScore();
        
        // Note: We do NOT call RefreshEvidenceFromEngines on cache hit to preserve the cached snapshot
        // The regime engine is updated separately in ApplyRegimeAndCostGate if needed
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
    
    // Dynamic base readiness score based on readiness class with adaptive staleness handling
    double trendReadinessScore = 0.55;
    if(m_lastEvidence.readinessClass == "HEALTHY")
        trendReadinessScore = 1.00;
    else if(m_lastEvidence.readinessClass == "REUSED_SNAPSHOT")
        trendReadinessScore = MathMax(0.45, 0.88 - m_lastEvidence.stalenessPenalty);
    else if(m_lastEvidence.readinessClass == "TRANSIENT_COPY_FAULT")
        trendReadinessScore = 0.65;
    else if(m_lastEvidence.readinessClass == "HANDLE_FAULT")
        trendReadinessScore = 0.40;
    else if(m_lastEvidence.readinessClass == "WARMUP")
        trendReadinessScore = 0.58;

    // Trend readiness with strength-based adjustment
    if(m_filters.enableTrendFilter)
    {
        double trendComponent = m_lastEvidence.trendReady ? trendReadinessScore : MathMin(trendReadinessScore, 0.62);
        // Boost trend readiness if trend strength is meaningful
        if(m_lastEvidence.trendReady && m_lastEvidence.trendStrength > 50.0)
            trendComponent = MathMin(1.0, trendComponent + 0.08);
        total += trendComponent;
        components++;
    }

    // Structure readiness with strength consideration
    if(m_filters.enableStructureFilter)
    {
        double structureComponent = m_lastEvidence.structureReady ? 1.0 : 0.68;
        // Adjust based on actual structure strength if available
        if(m_lastEvidence.structureReady && m_lastEvidence.structureStrength > 0.0)
            structureComponent = MathMin(1.0, 0.85 + (m_lastEvidence.structureStrength / 500.0));
        total += structureComponent;
        components++;
    }

    // Liquidity readiness with sweep detection bonus
    if(m_filters.enableLiquidityFilter)
    {
        double liquidityComponent = m_lastEvidence.liquidityReady ? 1.0 : 0.72;
        // Slight boost if recent liquidity sweep detected (indicates active liquidity analysis)
        if(m_lastEvidence.liquidityReady && m_lastEvidence.liquiditySweep)
            liquidityComponent = MathMin(1.0, liquidityComponent + 0.05);
        total += liquidityComponent;
        components++;
    }

    // Volatility readiness with state-based adjustment
    if(m_filters.enableVolatilityFilter)
    {
        double volatilityComponent = m_lastEvidence.volatilityReady ? 1.0 : 0.58;
        // Adjust based on volatility state - extreme volatility may indicate less stable readings
        if(m_lastEvidence.volatilityReady)
        {
            if(m_lastEvidence.volatilityState == VOLATILITY_NORMAL)
                volatilityComponent = 1.0;
            else if(m_lastEvidence.volatilityState == VOLATILITY_LOW)
                volatilityComponent = 0.95;
            else if(m_lastEvidence.volatilityState == VOLATILITY_HIGH)
                volatilityComponent = 0.90;
            else if(m_lastEvidence.volatilityState == VOLATILITY_EXTREME)
                volatilityComponent = 0.82;
        }
        total += volatilityComponent;
        components++;
    }

    // Regime readiness with cost score integration
    if(m_filters.enableRegimeCostGate)
    {
        double regimeComponent = m_lastEvidence.regimeValid ? MathMax(0.72, 1.0 - m_lastEvidence.stalenessPenalty) : 0.72;
        // Integrate cost score into regime readiness for more accurate assessment
        if(m_lastEvidence.regimeValid && m_lastEvidence.costScore > 0.0)
            regimeComponent = MathMax(0.65, MathMin(1.0, (regimeComponent + m_lastEvidence.costScore) / 2.0));
        total += regimeComponent;
        components++;
    }

    if(components <= 0)
        return 1.0;

    double readinessScore = total / components;
    return MathMax(0.0, MathMin(1.0, readinessScore));
}

double CUnifiedSignalPipeline::ComputeContextScore(const ENUM_TRADE_SIGNAL signal) const
{
    // Trend context scoring with granular strength considerations
    double trendScore = 0.72;
    if(signal == TRADE_SIGNAL_BUY)
    {
        if(m_lastEvidence.trend == TREND_BULLISH_STRONG || m_lastEvidence.trend == TREND_BULLISH_WEAK)
        {
            // More nuanced scoring based on trend strength tiers
            if(m_lastEvidence.trendStrength >= 85.0)
                trendScore = 1.0;
            else if(m_lastEvidence.trendStrength >= 70.0)
                trendScore = 0.94;
            else if(m_lastEvidence.trendStrength >= 55.0)
                trendScore = 0.88;
            else
                trendScore = 0.82;
        }
        else if(m_lastEvidence.trend == TREND_BEARISH_STRONG || m_lastEvidence.trend == TREND_BEARISH_WEAK)
        {
            // Strong opposing trend penalizes more heavily
            if(m_lastEvidence.trendStrength >= 85.0)
                trendScore = 0.38;
            else if(m_lastEvidence.trendStrength >= 70.0)
                trendScore = 0.45;
            else
                trendScore = 0.58;
        }
        else if(m_lastEvidence.trend == TREND_RANGING || m_lastEvidence.trend == TREND_NONE)
        {
            // Neutral trend - moderate score for ranging markets
            trendScore = 0.78;
        }
    }
    else if(signal == TRADE_SIGNAL_SELL)
    {
        if(m_lastEvidence.trend == TREND_BEARISH_STRONG || m_lastEvidence.trend == TREND_BEARISH_WEAK)
        {
            if(m_lastEvidence.trendStrength >= 85.0)
                trendScore = 1.0;
            else if(m_lastEvidence.trendStrength >= 70.0)
                trendScore = 0.94;
            else if(m_lastEvidence.trendStrength >= 55.0)
                trendScore = 0.88;
            else
                trendScore = 0.82;
        }
        else if(m_lastEvidence.trend == TREND_BULLISH_STRONG || m_lastEvidence.trend == TREND_BULLISH_WEAK)
        {
            if(m_lastEvidence.trendStrength >= 85.0)
                trendScore = 0.38;
            else if(m_lastEvidence.trendStrength >= 70.0)
                trendScore = 0.45;
            else
                trendScore = 0.58;
        }
        else if(m_lastEvidence.trend == TREND_RANGING || m_lastEvidence.trend == TREND_NONE)
        {
            trendScore = 0.78;
        }
    }

    // Structure context scoring with improved strength integration
    double structureScore = 0.70;
    if(signal == TRADE_SIGNAL_BUY && m_lastEvidence.bullishStructure)
    {
        // Boost for aligned structure with strength consideration
        structureScore = MathMin(1.0, 0.92 + (m_lastEvidence.structureStrength / 600.0));
    }
    else if(signal == TRADE_SIGNAL_SELL && m_lastEvidence.bearishStructure)
    {
        structureScore = MathMin(1.0, 0.92 + (m_lastEvidence.structureStrength / 600.0));
    }
    else if(m_lastEvidence.structureStrength > 0.0)
    {
        // Partial credit for structure presence even if not aligned
        structureScore = MathMax(0.52, MathMin(0.88, 0.58 + (m_lastEvidence.structureStrength / 300.0)));
    }

    // Liquidity context scoring with sweep and proximity considerations
    double liquidityScore = 0.75;
    if(m_lastEvidence.liquiditySweep)
        liquidityScore = 0.96; // Strong boost for recent liquidity sweep
    if(m_lastEvidence.priceNearLiquidity)
        liquidityScore = MathMin(liquidityScore, 0.80); // Slight reduction near untested liquidity

    // Volatility context scoring with adaptive weighting based on ATR percentage
    double volatilityScore = 0.78;
    if(m_lastEvidence.volatilityState == VOLATILITY_NORMAL)
        volatilityScore = 1.0;
    else if(m_lastEvidence.volatilityState == VOLATILITY_LOW)
        volatilityScore = 0.92;
    else if(m_lastEvidence.volatilityState == VOLATILITY_HIGH)
        volatilityScore = 0.78;
    else if(m_lastEvidence.volatilityState == VOLATILITY_EXTREME)
        volatilityScore = 0.52;
    
    // Additional adjustment based on ATR percentage for fine-tuning
    if(m_lastEvidence.atrPercent > 0.0)
    {
        if(m_lastEvidence.atrPercent < 0.3) // Very low volatility
            volatilityScore = MathMin(volatilityScore, 0.88);
        else if(m_lastEvidence.atrPercent > 1.5) // Very high volatility
            volatilityScore = MathMax(volatilityScore * 0.85, 0.45);
    }

    // Regime context scoring with enhanced state integration
    double regimeScore = m_lastEvidence.costScore;
    if(!m_lastEvidence.regimeValid)
        regimeScore = MathMin(regimeScore, 0.70);
    else
    {
        if(m_lastEvidence.regimeState == REGIME_BREAKOUT || m_lastEvidence.regimeState == REGIME_TREND)
            regimeScore = MathMax(regimeScore, 0.94);
        else if(m_lastEvidence.regimeState == REGIME_RANGE)
            regimeScore = MathMin(MathMax(regimeScore, 0.78), 0.90);
        else if(m_lastEvidence.regimeState == REGIME_CHAOS)
            regimeScore = MathMin(regimeScore, 0.65);
        
        // Adjust for readiness class
        if(m_lastEvidence.readinessClass == "REUSED_SNAPSHOT")
            regimeScore = MathMax(0.65, regimeScore - m_lastEvidence.stalenessPenalty);
    }

    // Weighted average with trend and structure having higher importance
    double trendWeight = 1.25;
    double structureWeight = 1.15;
    double liquidityWeight = 0.90;
    double volatilityWeight = 1.05;
    double regimeWeight = 1.10;
    
    double totalWeight = trendWeight + structureWeight + liquidityWeight + volatilityWeight + regimeWeight;
    double weightedTotal = (trendScore * trendWeight) + 
                          (structureScore * structureWeight) + 
                          (liquidityScore * liquidityWeight) + 
                          (volatilityScore * volatilityWeight) + 
                          (regimeScore * regimeWeight);
    
    double contextScore = weightedTotal / totalWeight;
    return MathMax(0.0, MathMin(1.0, contextScore));
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
    m_lastFilterName = "";
    m_lastFilterReason = "";

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
    {
        bool trendPassed = ApplyTrendFilter(signal, confidence);
        if(!trendPassed)
        {
            passed = false;
            // Note: TrendFilter logs its own filter result internally
        }
    }

    if(m_filters.enableVolatilityFilter)
    {
        bool volPassed = ApplyVolatilityFilter(signal, confidence);
        if(!volPassed)
        {
            passed = false;
            // Note: VolatilityFilter logs its own filter result internally
        }
    }

    if(m_filters.enableLiquidityFilter)
    {
        bool liqPassed = ApplyLiquidityFilter(signal, confidence, symbol);
        if(!liqPassed)
        {
            passed = false;
            // Note: LiquidityFilter logs its own filter result internally
        }
    }

    if(m_filters.enableStructureFilter)
    {
        bool structPassed = ApplyStructureFilter(signal, confidence);
        if(!structPassed)
        {
            passed = false;
            // Note: StructureFilter logs its own filter result internally
        }
    }

    if(m_filters.enableTimeFilter)
    {
        bool timePassed = ApplyTimeFilter(signal, symbol);
        if(!timePassed)
        {
            passed = false;
            // Note: TimeFilter logs its own filter result internally
        }
    }

    if(m_filters.enableSessionFilter)
    {
        bool sessionPassed = ApplySessionFilter(symbol);
        if(!sessionPassed)
        {
            passed = false;
            // Note: SessionFilter logs its own filter result internally
        }
    }

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

    // Profitability audit fix: context/readiness/staleness must be allowed to
    // reduce confidence. Preserving the pre-adjusted score lets weak evidence
    // pass downstream as fake certainty.
    if(passed)
    {
        double contextBlend = 0.80 + (0.20 * m_lastEvidence.contextScore);
        double readinessBlend = 0.85 + (0.15 * m_lastEvidence.readinessScore);
        double stalenessBlend = MathMax(0.70, 1.0 - m_lastEvidence.stalenessPenalty);
        double adjustedConfidence = MathMax(0.0, MathMin(1.0, confidence * contextBlend * readinessBlend * stalenessBlend));
        confidence = adjustedConfidence;
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
    PrintFormat("[COST-GATE] %s | regime=%s | spread_atr=%.6f/%.6f | spread=%.5f | atr=%.5f | cooldown=%s | z=%.3f/%.3f",
                symbol,
                regimeTag,
                snapshot.spreadToAtrRatio,
                m_filters.maxSpreadToAtrRatio,
                snapshot.spreadPrice,
                snapshot.atrValue,
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
    if(confidence > 0.82 && (trend == TREND_RANGING || trend == TREND_NONE))
    {
        LogFilterResult("TrendFilter", true, 
                       StringFormat("BYPASSED - High confidence in neutral trend (%.2f) | Trend: %s", 
                                  confidence, EnumToString(trend)));
        return true;
    }
    
    // 🔥 FIX: Allow ranging markets - check if trend is actively AGAINST the signal
    // Only reject if there's a STRONG opposing trend
    bool strongOpposingTrend = false;
    
    if(signal == TRADE_SIGNAL_BUY && m_trendEngine.IsTrendBearish() && trendStrength > 75)
        strongOpposingTrend = true;
    else if(signal == TRADE_SIGNAL_SELL && m_trendEngine.IsTrendBullish() && trendStrength > 75)
        strongOpposingTrend = true;
    
    if(strongOpposingTrend)
    {
        if(trendStrength >= 90.0) // Increased from 85.0
        {
            LogFilterResult("TrendFilter", false, 
                           StringFormat("Hard opposing trend veto: %s (%.1f)", 
                                      EnumToString(trend), trendStrength));
            return false;
        }

        confidence *= 0.85; // Relaxed from 0.72
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
//| Check if Symbol is Synthetic Index                               |
//+------------------------------------------------------------------+
bool CUnifiedSignalPipeline::IsSyntheticSymbol(const string symbol)
{
    if(symbol == "") return false;
    
    // Check for broker-specific synthetic products that trade 24/7 or outside regular FX sessions.
    if(StringFind(symbol, "Vol") >= 0  ||      // Vol 10, Vol 25, Vol 50, etc.
       StringFind(symbol, "Step") >= 0 ||      // Step Index variants
       StringFind(symbol, "Boom") >= 0 ||      // Boom 1000, Boom 500
       StringFind(symbol, "Crash") >= 0 ||     // Crash 1000, Crash 500
       StringFind(symbol, "Jump") >= 0 ||      // Jump 10, Jump 25, etc.
       StringFind(symbol, "PainX") >= 0 ||     // Weltrade synthetic family
       StringFind(symbol, "Pain ") >= 0 ||     // Additional naming variant
       StringFind(symbol, "SFX Vol") >= 0 ||
       StringFind(symbol, "FX Vol") >= 0 ||
       StringFind(symbol, "GainX") >= 0 ||
       StringFind(symbol, "FlipX") >= 0 ||
       StringFind(symbol, "SwitchX") >= 0 ||   // SwitchX 1200 and variants
       StringFind(symbol, "Synth") >= 0 ||
       StringFind(symbol, "Index") >= 0)
    {
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Apply Time Filter                                               |
//+------------------------------------------------------------------+
bool CUnifiedSignalPipeline::ApplyTimeFilter(ENUM_TRADE_SIGNAL &signal, const string symbol)
{
    // Synthetic indices trade 24/7 - bypass ALL time restrictions including weekends
    if(IsSyntheticSymbol(symbol))
    {
        LogFilterResult("TimeFilter", true, "Synthetic index - 24/7 trading enabled");
        return true;
    }
    
    // If synthetic indices and off-hours allowed, bypass time filter
    if(m_filters.allowSyntheticOffHours && IsSyntheticSymbol(symbol))
        return true;
    
    MqlDateTime dt;
    TimeToStruct(TimeGMT(), dt);
    int currentHour = dt.hour;
    
    // Check trading hours (0 AM - 10 PM GMT: Allowing Asia session)
    int startHour = 0;
    int endHour = 22;
    
    if(startHour <= endHour)
    {
        if(currentHour < startHour || currentHour >= endHour)
        {
            LogFilterResult("TimeFilter", false, StringFormat("Outside trading hours: %d:00 GMT", currentHour));
            return false;
        }
    }
    else  // Overnight hours (e.g., 22 to 2)
    {
        if(currentHour < startHour && currentHour >= endHour)
        {
            LogFilterResult("TimeFilter", false, StringFormat("Outside trading hours: %d:00 GMT", currentHour));
            return false;
        }
    }
    
    // Skip weekends (only for non-synthetic symbols)
    if(dt.day_of_week == 0 || dt.day_of_week == 6)
    {
        LogFilterResult("TimeFilter", false, "Weekend - trading disabled");
        return false;
    }
    
    LogFilterResult("TimeFilter", true, "Active trading session");
    return true;
}

//+------------------------------------------------------------------+
//| Apply Session Filter                                             |
//+------------------------------------------------------------------+
bool CUnifiedSignalPipeline::ApplySessionFilter(const string symbol)
{
    // If synthetic indices and off-hours allowed, bypass session filter
    if(m_filters.allowSyntheticOffHours && IsSyntheticSymbol(symbol))
        return true;
    
    if(!m_filters.enableSessionFilter)
        return true;
    
    MqlDateTime dt;
    TimeToStruct(TimeGMT(), dt);
    int gmtHour = dt.hour;
    
    // Tokyo session: 00:00-09:00 GMT
    if(m_filters.tradeTokyoSession && gmtHour >= 0 && gmtHour < 9)
        return true;
    
    // London session: 08:00-17:00 GMT
    if(m_filters.tradeLondonSession && gmtHour >= 8 && gmtHour < 17)
        return true;
    
    // New York session: 13:00-22:00 GMT
    if(m_filters.tradeNewYorkSession && gmtHour >= 13 && gmtHour < 22)
        return true;
    
    LogFilterResult("SessionFilter", false, StringFormat("Not in active trading session: %d:00 GMT", gmtHour));
    return false;
}

//+------------------------------------------------------------------+
//| Calculate Quality Score                                          |
//+------------------------------------------------------------------+
double CUnifiedSignalPipeline::CalculateQualityScore(double confidence, int confluence, bool passedFilters,
                                                      double convictionScore, double readinessScore, double contextScore,
                                                      double diversityScore, double costScore, double directionalQuality,
                                                      double supportRatio)
{
    double score = 0.0;
    
    // Validate inputs - handle NaN and extreme values
    if(!MathIsValidNumber(confidence) || confidence < 0.0 || confidence > 1.0)
        confidence = 0.0;
    
    // Confidence component
    score += confidence * 0.20;
    
    // Confluence component (Biased scale to avoid punishing solo high-quality signals)
    double confluenceScore = 0.0;
    if(confluence == 1) confluenceScore = 0.50;      // Solo signal starts with decent baseline
    else if(confluence == 2) confluenceScore = 0.80;
    else if(confluence >= 3) confluenceScore = 1.0;
    score += confluenceScore * 0.10;
    
    // Decision-path components with NaN protection
    convictionScore = MathIsValidNumber(convictionScore) ? convictionScore : 0.0;
    readinessScore = MathIsValidNumber(readinessScore) ? readinessScore : 0.0;
    contextScore = MathIsValidNumber(contextScore) ? contextScore : 0.0;
    diversityScore = MathIsValidNumber(diversityScore) ? diversityScore : 0.0;
    costScore = MathIsValidNumber(costScore) ? costScore : 0.0;
    directionalQuality = MathIsValidNumber(directionalQuality) ? directionalQuality : 0.0;
    supportRatio = MathIsValidNumber(supportRatio) ? supportRatio : 0.0;
    
    score += MathMax(0.0, MathMin(1.0, convictionScore)) * 0.12;
    score += MathMax(0.0, MathMin(1.0, readinessScore)) * 0.08;
    score += MathMax(0.0, MathMin(1.0, contextScore)) * 0.08;
    score += MathMax(0.0, MathMin(1.0, diversityScore)) * 0.07;
    score += MathMax(0.0, MathMin(1.0, costScore)) * 0.05;
    score += MathMax(0.0, MathMin(1.0, directionalQuality)) * 0.15;
    score += MathMax(0.0, MathMin(1.0, supportRatio)) * 0.07;
    
    // Filter component
    if(passedFilters)
        score += 0.05;
    
    // Ensure final score is valid and in range [0, 1]
    if(!MathIsValidNumber(score))
        score = 0.0;
    
    return MathMax(0.0, MathMin(1.0, score));
}

//+------------------------------------------------------------------+
//| Log Filter Result                                               |
//+------------------------------------------------------------------+
void CUnifiedSignalPipeline::LogFilterResult(const string filter, bool passed, const string reason)
{
    if(passed)
        return;

    if(StringLen(m_lastFilterName) > 0)
        m_lastFilterName += "+";
    m_lastFilterName += filter;

    if(StringLen(reason) > 0)
    {
        if(StringLen(m_lastFilterReason) > 0)
            m_lastFilterReason += "; ";
        m_lastFilterReason += reason;
    }

    // Note: Generic per-filter logs are intentionally suppressed here.
    // Note: Authoritative runtime telemetry is emitted by the manager, validator, and regime/cost gates.
}

//+------------------------------------------------------------------+
//| Check Engine Health (private)                                    |
//+------------------------------------------------------------------+
void CUnifiedSignalPipeline::CheckEngineHealth(const string symbol)
{
    m_trendEngineHealthy = (m_trendEngine != NULL);
    m_structureEngineHealthy = (m_structureEngine != NULL);
    m_liquidityEngineHealthy = (m_liquidityEngine != NULL);
    m_volatilityEngineHealthy = (m_volatilityEngine != NULL);
    m_regimeEngineHealthy = (m_regimeEngine != NULL);
    
    m_lastHealthCheckTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Is Engine Healthy (private)                                      |
//+------------------------------------------------------------------+
bool CUnifiedSignalPipeline::IsEngineHealthy() const
{
    return m_trendEngineHealthy && m_structureEngineHealthy && 
           m_liquidityEngineHealthy && m_volatilityEngineHealthy && 
           m_regimeEngineHealthy;
}

//+------------------------------------------------------------------+
//| Perform Health Check (public)                                    |
//+------------------------------------------------------------------+
void CUnifiedSignalPipeline::PerformHealthCheck(const string symbol)
{
    CheckEngineHealth(symbol);
    
    string status = GetEngineHealthStatus();
    PrintFormat("[PIPELINE-HEALTH] Symbol=%s | Status=%s | Trend=%s | Structure=%s | Liquidity=%s | Volatility=%s | Regime=%s",
                symbol,
                IsPipelineHealthy() ? "HEALTHY" : "DEGRADED",
                m_trendEngineHealthy ? "OK" : "FAIL",
                m_structureEngineHealthy ? "OK" : "FAIL",
                m_liquidityEngineHealthy ? "OK" : "FAIL",
                m_volatilityEngineHealthy ? "OK" : "FAIL",
                m_regimeEngineHealthy ? "OK" : "FAIL");
}

//+------------------------------------------------------------------+
//| Is Pipeline Healthy (public)                                     |
//+------------------------------------------------------------------+
bool CUnifiedSignalPipeline::IsPipelineHealthy() const
{
    return IsEngineHealthy();
}

//+------------------------------------------------------------------+
//| Get Engine Health Status (public)                               |
//+------------------------------------------------------------------+
string CUnifiedSignalPipeline::GetEngineHealthStatus() const
{
    if(IsEngineHealthy())
        return "ALL_ENGINES_HEALTHY";
    
    string status = "DEGRADED:";
    if(!m_trendEngineHealthy) status += " TREND";
    if(!m_structureEngineHealthy) status += " STRUCTURE";
    if(!m_liquidityEngineHealthy) status += " LIQUIDITY";
    if(!m_volatilityEngineHealthy) status += " VOLATILITY";
    if(!m_regimeEngineHealthy) status += " REGIME";
    
    return status;
}

//+------------------------------------------------------------------+
//| Apply Filter Preset (public)                                    |
//+------------------------------------------------------------------+
void CUnifiedSignalPipeline::ApplyFilterPreset(ENUM_FILTER_PRESET preset)
{
    switch(preset)
    {
        case FILTER_PRESET_CONSERVATIVE:
            m_filters.enableTrendFilter = true;
            m_filters.enableVolatilityFilter = true;
            m_filters.enableLiquidityFilter = true;
            m_filters.enableStructureFilter = true;
            m_filters.enableTimeFilter = true;
            m_filters.enableSessionFilter = true;
            m_filters.minConfidence = 0.70;
            m_filters.intrabarConfidenceCap = 0.03;
            m_filters.enableRegimeCostGate = true;
            m_filters.maxSpreadToAtrRatio = 0.15;
            m_filters.spreadShockCooldownSeconds = 60;
            m_filters.maxEntryRangeZScore = 1.50;
            m_filters.maxVolatility = 1.5;
            m_filters.minTrendStrength = 70;
            Print("[UnifiedSignalPipeline] Applied CONSERVATIVE filter preset");
            break;
        
        case FILTER_PRESET_BALANCED:
            m_filters.enableTrendFilter = true;
            m_filters.enableVolatilityFilter = true;
            m_filters.enableLiquidityFilter = true;
            m_filters.enableStructureFilter = true;
            m_filters.enableTimeFilter = false;
            m_filters.enableSessionFilter = false;
            m_filters.minConfidence = 0.40;
            m_filters.intrabarConfidenceCap = 0.05;
            m_filters.enableRegimeCostGate = true;
            m_filters.maxSpreadToAtrRatio = 0.25;
            m_filters.spreadShockCooldownSeconds = 30;
            m_filters.maxEntryRangeZScore = 2.50;
            m_filters.maxVolatility = 3.0;
            m_filters.minTrendStrength = 50;
            Print("[UnifiedSignalPipeline] Applied BALANCED filter preset");
            break;
        
        case FILTER_PRESET_AGGRESSIVE:
            m_filters.enableTrendFilter = false;
            m_filters.enableVolatilityFilter = false;
            m_filters.enableLiquidityFilter = false;
            m_filters.enableStructureFilter = false;
            m_filters.enableTimeFilter = false;
            m_filters.enableSessionFilter = false;
            m_filters.minConfidence = 0.20;
            m_filters.intrabarConfidenceCap = 0.10;
            m_filters.enableRegimeCostGate = false;
            m_filters.maxSpreadToAtrRatio = 0.50;
            m_filters.spreadShockCooldownSeconds = 10;
            m_filters.maxEntryRangeZScore = 4.00;
            m_filters.maxVolatility = 5.0;
            m_filters.minTrendStrength = 20;
            Print("[UnifiedSignalPipeline] Applied AGGRESSIVE filter preset");
            break;
        
        default:
            Print("[UnifiedSignalPipeline] Custom preset, using default settings");
            break;
    }
}

#endif // UNIFIED_SIGNAL_PIPELINE_MQH
