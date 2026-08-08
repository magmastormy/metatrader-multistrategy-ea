//+------------------------------------------------------------------+
//| Unified Signal Pipeline - Enterprise Grade                       |
//| Central hub for all strategy signals with filtering              |
//+------------------------------------------------------------------+
#ifndef UNIFIED_SIGNAL_PIPELINE_MQH
#define UNIFIED_SIGNAL_PIPELINE_MQH

#include "../Utils/Enums.mqh"
#include "../Signals/TimeframeConsistency.mqh"
#include "../../Core/Registry/MathematicalEngineRegistry.mqh"
#include "../../Core/Engines/SessionWeightManager.mqh"
#include "../Processing/MultiAssetProfiler.mqh"

// Forward declaration for global profiler access (initialized in EAOrchestrator)
class CMultiAssetProfiler;
extern CMultiAssetProfiler* g_multiAssetProfiler;

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
//| Readiness Score Configuration                                   |
//+------------------------------------------------------------------+
struct SReadinessScoreConfig
{
    double healthyScore;
    double reusedSnapshotScore;
    double transientCopyFaultScore;
    double handleFaultScore;
    double warmupScore;
    double stalenessPenaltyMax;
    int stalenessPenaltyDivisor;
    
    SReadinessScoreConfig() :
        healthyScore(1.00),
        reusedSnapshotScore(0.88),
        transientCopyFaultScore(0.65),
        handleFaultScore(0.40),
        warmupScore(0.58),
        stalenessPenaltyMax(0.30),
        stalenessPenaltyDivisor(120) {} // 2 minutes
    
    bool Validate() const
    {
        if(healthyScore < 0.0 || healthyScore > 1.0)
            return false;
        if(reusedSnapshotScore < 0.0 || reusedSnapshotScore > 1.0)
            return false;
        if(transientCopyFaultScore < 0.0 || transientCopyFaultScore > 1.0)
            return false;
        if(handleFaultScore < 0.0 || handleFaultScore > 1.0)
            return false;
        if(warmupScore < 0.0 || warmupScore > 1.0)
            return false;
        if(stalenessPenaltyMax < 0.0 || stalenessPenaltyMax > 1.0)
            return false;
        if(stalenessPenaltyDivisor <= 0)
            return false;
        return true;
    }
};

//+------------------------------------------------------------------+
//| Signal Filter Settings - Grouped Nested Structs (L4-012 Fix)    |
//+------------------------------------------------------------------+

// Trend Filter Settings
struct STrendFilterSettings
{
    bool enabled;
    int minStrength;
    
    STrendFilterSettings() : enabled(true), minStrength(50) {}
    
    bool Validate() const
    {
        return minStrength >= 0 && minStrength <= 100;
    }
};

// Volatility Filter Settings
struct SVolatilityFilterSettings
{
    bool enabled;
    double maxVolatility;
    
    SVolatilityFilterSettings() : enabled(true), maxVolatility(3.0) {}
    
    bool Validate() const
    {
        return maxVolatility >= 0.0 && maxVolatility <= 10.0;
    }
};

// Liquidity Filter Settings
struct SLiquidityFilterSettings
{
    bool enabled;
    
    SLiquidityFilterSettings() : enabled(true) {}
    
    bool Validate() const { return true; }
};

// Structure Filter Settings
struct SStructureFilterSettings
{
    bool enabled;
    
    SStructureFilterSettings() : enabled(true) {}
    
    bool Validate() const { return true; }
};

// Session/Time Filter Settings
struct SSessionFilterSettings
{
    bool enableTimeFilter;
    bool enableSessionFilter;
    bool allowSyntheticOffHours;
    bool tradeLondonSession;
    bool tradeNewYorkSession;
    bool tradeTokyoSession;
    
    SSessionFilterSettings() : 
        enableTimeFilter(false),
        enableSessionFilter(false),
        allowSyntheticOffHours(true),
        tradeLondonSession(true),
        tradeNewYorkSession(true),
        tradeTokyoSession(true) {}
    
    bool Validate() const { return true; }
};

// Regime Cost Gate Settings
struct SRegimeCostGateSettings
{
    bool enabled;
    double maxSpreadToAtrRatio;
    int spreadShockCooldownSeconds;
    double maxEntryRangeZScore;
    
    SRegimeCostGateSettings() : 
        enabled(true),
        maxSpreadToAtrRatio(0.25),
        spreadShockCooldownSeconds(30),
        maxEntryRangeZScore(2.50) {}
    
    bool Validate() const
    {
        if(maxSpreadToAtrRatio < 0.0 || maxSpreadToAtrRatio > 10.0)
            return false;
        if(maxEntryRangeZScore < 0.0 || maxEntryRangeZScore > 10.0)
            return false;
        if(spreadShockCooldownSeconds < 0)
            return false;
        return true;
    }
};

// Confidence Settings
struct SConfidenceSettings
{
    double minConfidence;
    double intrabarConfidenceCap;
    
    SConfidenceSettings() : minConfidence(0.40), intrabarConfidenceCap(0.05) {}
    
    bool Validate() const
    {
        if(minConfidence < 0.0 || minConfidence > 1.0)
            return false;
        if(intrabarConfidenceCap < 0.0 || intrabarConfidenceCap > 1.0)
            return false;
        return true;
    }
};

// Filter Order Settings
struct SFilterOrderSettings
{
    int filterOrder[7];
    int filterOrderCount;
    
    SFilterOrderSettings() : filterOrderCount(7)
    {
        // Default filter order: RegimeCostGate -> Trend -> Volatility -> Liquidity -> Structure -> Time -> Session
        filterOrder[0] = 0; // RegimeCostGate
        filterOrder[1] = 1; // Trend
        filterOrder[2] = 2; // Volatility
        filterOrder[3] = 3; // Liquidity
        filterOrder[4] = 4; // Structure
        filterOrder[5] = 5; // Time
        filterOrder[6] = 6; // Session
    }
    
    bool Validate() const
    {
        if(filterOrderCount < 1 || filterOrderCount > 7)
            return false;
        for(int i = 0; i < filterOrderCount; i++)
        {
            if(filterOrder[i] < 0 || filterOrder[i] > 6)
                return false;
        }
        return true;
    }
};

// Readiness Component Weights (for L4-015 fix)
struct SReadinessComponentWeights
{
    double trendWeight;
    double structureWeight;
    double liquidityWeight;
    double volatilityWeight;
    double regimeWeight;
    
    SReadinessComponentWeights() : 
        trendWeight(1.25),
        structureWeight(1.15),
        liquidityWeight(0.90),
        volatilityWeight(1.05),
        regimeWeight(1.10) {}
    
    bool Validate() const
    {
        double sum = trendWeight + structureWeight + liquidityWeight + volatilityWeight + regimeWeight;
        return sum > 0.0 && MathAbs(sum - 5.45) < 0.001; // Expected sum
    }
};

// Main Signal Filter Settings - Composed of grouped structs
struct SignalFilterSettings
{
    STrendFilterSettings trend;
    SVolatilityFilterSettings volatility;
    SLiquidityFilterSettings liquidity;
    SStructureFilterSettings structure;
    SSessionFilterSettings session;
    SRegimeCostGateSettings regimeCostGate;
    SConfidenceSettings confidence;
    SFilterOrderSettings filterOrder;
    SReadinessScoreConfig readinessConfig;
    SReadinessComponentWeights readinessWeights;
    
    SignalFilterSettings() {}
    
    // Validate all grouped settings
    bool Validate() const
    {
        return trend.Validate() &&
               volatility.Validate() &&
               liquidity.Validate() &&
               structure.Validate() &&
               session.Validate() &&
               regimeCostGate.Validate() &&
               confidence.Validate() &&
               filterOrder.Validate() &&
               readinessConfig.Validate() &&
               readinessWeights.Validate();
    }
    
    // Apply a preset configuration
    void ApplyPreset(ENUM_FILTER_PRESET preset)
    {
        switch(preset)
        {
            case FILTER_PRESET_CONSERVATIVE:
                trend.enabled = true; trend.minStrength = 60;
                volatility.enabled = true; volatility.maxVolatility = 2.0;
                liquidity.enabled = true;
                structure.enabled = true;
                session.enableTimeFilter = true; session.enableSessionFilter = true;
                regimeCostGate.enabled = true; regimeCostGate.maxSpreadToAtrRatio = 0.15; regimeCostGate.maxEntryRangeZScore = 2.0;
                confidence.minConfidence = 0.55; confidence.intrabarConfidenceCap = 0.03;
                break;
                
            case FILTER_PRESET_BALANCED:
                trend.enabled = true; trend.minStrength = 50;
                volatility.enabled = true; volatility.maxVolatility = 3.0;
                liquidity.enabled = true;
                structure.enabled = true;
                session.enableTimeFilter = false; session.enableSessionFilter = false;
                regimeCostGate.enabled = true; regimeCostGate.maxSpreadToAtrRatio = 0.25; regimeCostGate.maxEntryRangeZScore = 2.5;
                confidence.minConfidence = 0.40; confidence.intrabarConfidenceCap = 0.05;
                break;
                
            case FILTER_PRESET_AGGRESSIVE:
                trend.enabled = true; trend.minStrength = 35;
                volatility.enabled = true; volatility.maxVolatility = 4.5;
                liquidity.enabled = true;
                structure.enabled = true;
                session.enableTimeFilter = false; session.enableSessionFilter = false;
                regimeCostGate.enabled = true; regimeCostGate.maxSpreadToAtrRatio = 0.40; regimeCostGate.maxEntryRangeZScore = 3.0;
                confidence.minConfidence = 0.30; confidence.intrabarConfidenceCap = 0.08;
                break;
                
            case FILTER_PRESET_CUSTOM:
            default:
                // Keep current values
                break;
        }
        // Re-validate after preset
        Validate();
    }
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
    // Registry references (engines obtained from registry)
    CMathematicalEngineRegistry* m_mathRegistry;
    
    // Protection / consistency
    CTimeframeConsistency* m_tfConsistency;

    // I3: Session weight manager (injected from EA)
    CSessionWeightManager* m_sessionWeightManager;
    
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
        bool m_cachedContextIntrabar;
    
        // Engine health tracking - now checked on-demand via registry
    datetime m_lastHealthCheckTime;
    int m_healthCheckIntervalBars;
    
    // Issue 14: Budget exhaustion skip
    bool m_budgetExhausted;
    datetime m_budgetExhaustedTime;
    datetime m_budgetExhaustedResetTime; // Daily reset time (midnight)
    
    // Filter order tracking
    int m_filterOrderMap[7]; // Maps filter index to execution order
    
    // Regime gate log throttling
    int m_regimeGateLogCounter;
    int m_regimeGateLogInterval;
    
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
    
    // Filter order management
    void BuildFilterOrderMap();
    
    // Budget exhaustion auto-clear
    void CheckBudgetExhaustedAutoClear();
    
    // Health monitoring
    void CheckEngineHealth(const string symbol);
    bool IsEngineHealthy();
    
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
    void SetSessionWeightManager(CSessionWeightManager* mgr) { m_sessionWeightManager = mgr; }
    void ApplyFilterPreset(ENUM_FILTER_PRESET preset);
    
    // Statistics
    int GetSignalsProcessed() const { return m_signalsProcessed; }
    int GetSignalsFiltered() const { return m_signalsFiltered; }
    int GetSignalsPassed() const { return m_signalsPassed; }
    bool WasLastSignalRawNone() const { return m_lastRawSignalNone; }
    bool WasLastSignalFilteredByPipeline() const { return m_lastFilteredByPipeline; }
    
    // Health monitoring
    void PerformHealthCheck(const string symbol);
    bool IsPipelineHealthy();
    string GetEngineHealthStatus();
    string GetLastEvaluatedSymbol() const { return m_lastEvaluatedSymbol; }
    double GetLastEffectiveMinConfidence() const { return m_lastEffectiveMinConfidence; }
    string GetLastFilterName() const { return m_lastFilterName; }
    string GetLastFilterReason() const { return m_lastFilterReason; }

    // Spread filter (public for EA access)
        bool ApplySpreadFilter(const string symbol, double &spreadScore, double overrideThreshold = -1.0, double atrValue = -1.0);
        void GetLastEvidenceSnapshot(SPipelineEvidenceSnapshot &snapshot) const { snapshot = m_lastEvidence; }
    double GetFilterRate() const 
    { 
        return m_signalsProcessed > 0 ? 
               (double)m_signalsFiltered / m_signalsProcessed : 0; 
    }
    
    // Engine access via registry
        CTrendEngine* GetTrendEngine(const string symbol) { return m_mathRegistry ? m_mathRegistry.GetTrend(symbol) : NULL; }
        CStructureEngine* GetStructureEngine(const string symbol) { return m_mathRegistry ? m_mathRegistry.GetStructure(symbol) : NULL; }
        CLiquidityEngine* GetLiquidityEngine(const string symbol) { return m_mathRegistry ? m_mathRegistry.GetLiquidity(symbol) : NULL; }
        CVolatilityEngine* GetVolatilityEngine(const string symbol) { return m_mathRegistry ? m_mathRegistry.GetVolatility(symbol) : NULL; }
        CRegimeEngine* GetRegimeEngine(const string symbol) { return m_mathRegistry ? m_mathRegistry.GetRegime(symbol) : NULL; }

        void SetMathRegistry(CMathematicalEngineRegistry* registry) { m_mathRegistry = registry; }

        // Issue 14: Budget exhaustion API
                void SetBudgetExhausted(const bool exhausted) { m_budgetExhausted = exhausted; m_budgetExhaustedTime = TimeCurrent(); m_budgetExhaustedResetTime = TimeCurrent() + 86400 - (TimeCurrent() % 86400); }
                void ResetBudgetExhausted() { m_budgetExhausted = false; m_budgetExhaustedTime = 0; m_budgetExhaustedResetTime = 0; }
                bool IsBudgetExhausted() const { return m_budgetExhausted; }
    };

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CUnifiedSignalPipeline::CUnifiedSignalPipeline() :
    m_mathRegistry(NULL),
    m_tfConsistency(NULL),
    m_sessionWeightManager(NULL),
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
        m_cachedContextIntrabar(false),
        m_lastHealthCheckTime(0),
    m_healthCheckIntervalBars(100),
    m_budgetExhausted(false),
    m_budgetExhaustedTime(0),
        m_budgetExhaustedResetTime(0),
        m_regimeGateLogCounter(0),
        m_regimeGateLogInterval(10)
{
    // Initialize filter order map
    for(int i = 0; i < 7; i++)
        m_filterOrderMap[i] = -1;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CUnifiedSignalPipeline::~CUnifiedSignalPipeline()
{
    // Engines are owned by the registry, not by this pipeline
    if(m_tfConsistency != NULL) { delete m_tfConsistency; m_tfConsistency = NULL; }
}

//+------------------------------------------------------------------+
//| Initialize Pipeline                                             |
//+------------------------------------------------------------------+
bool CUnifiedSignalPipeline::Initialize(SignalFilterSettings &settings)
{
    if(!settings.Validate())
    {
        Print("[UnifiedSignalPipeline] ERROR: Invalid filter settings, using defaults");
        return false;
    }
    
    m_filters = settings;
    BuildFilterOrderMap();
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
    
    Print("[UnifiedSignalPipeline] Initialized with filters: Trend=", m_filters.trend.enabled,
          " Volatility=", m_filters.volatility.enabled,
          " Liquidity=", m_filters.liquidity.enabled,
          " Structure=", m_filters.structure.enabled,
          " RegimeCostGate=", m_filters.regimeCostGate.enabled,
          " MaxSpreadATR=", DoubleToString(m_filters.regimeCostGate.maxSpreadToAtrRatio, 3),
          " SpreadShockCooldown=", m_filters.regimeCostGate.spreadShockCooldownSeconds,
          " MaxEntryZ=", DoubleToString(m_filters.regimeCostGate.maxEntryRangeZScore, 2));

    if(!initializationOk)
        Print("[UnifiedSignalPipeline] ERROR: component initialization incomplete; fail-closed startup");
    
    return initializationOk;
}

void CUnifiedSignalPipeline::SetFilters(SignalFilterSettings &settings)
{
    if(!settings.Validate())
    {
        Print("[UnifiedSignalPipeline] WARNING: Invalid filter settings ignored");
        return;
    }
    
    m_filters = settings;
    BuildFilterOrderMap();
    // Configure regime engine via registry for the current symbol if available
    if(m_mathRegistry != NULL && m_lastEvaluatedSymbol != "")
    {
        CRegimeEngine* regimeEngine = m_mathRegistry.GetRegime(m_lastEvaluatedSymbol);
        if(regimeEngine != NULL)
        {
            regimeEngine.ConfigureCostLimits(m_filters.regimeCostGate.maxSpreadToAtrRatio,
                                             m_filters.regimeCostGate.spreadShockCooldownSeconds,
                                             m_filters.regimeCostGate.maxEntryRangeZScore);
        }
    }
}

//+------------------------------------------------------------------+
//| Build filter order map from settings                            |
//+------------------------------------------------------------------+
void CUnifiedSignalPipeline::BuildFilterOrderMap()
{
    // Reset map
    for(int i = 0; i < 7; i++)
        m_filterOrderMap[i] = -1;
    
    // Build map: m_filterOrderMap[filterIndex] = executionOrder
    // where filterIndex: 0=RegimeCostGate, 1=Trend, 2=Volatility, 3=Liquidity, 4=Structure, 5=Time, 6=Session
    for(int i = 0; i < m_filters.filterOrder.filterOrderCount && i < 7; i++)
    {
        int filterIdx = m_filters.filterOrder.filterOrder[i];
        if(filterIdx >= 0 && filterIdx < 7)
            m_filterOrderMap[filterIdx] = i;
    }
}

//+------------------------------------------------------------------+
//| Check and auto-clear budget exhaustion (L4-007)                 |
//+------------------------------------------------------------------+
void CUnifiedSignalPipeline::CheckBudgetExhaustedAutoClear()
{
    if(!m_budgetExhausted)
        return;
    
    // Auto-clear at daily reset (midnight server time)
    datetime currentTime = TimeCurrent();
    datetime currentDate = currentTime - TimeCurrent() % 86400; // Start of current day
    
    if(m_budgetExhaustedResetTime == 0)
    {
        m_budgetExhaustedResetTime = currentDate + 86400; // Next midnight
    }
    
    if(currentTime >= m_budgetExhaustedResetTime)
    {
        m_budgetExhausted = false;
        m_budgetExhaustedTime = 0;
        m_budgetExhaustedResetTime = currentDate + 86400; // Next midnight
        PrintFormat("[UnifiedSignalPipeline] Budget exhaustion auto-cleared at daily reset (%s)", TimeToString(currentTime, TIME_DATE|TIME_MINUTES|TIME_SECONDS));
    }
}

void CUnifiedSignalPipeline::ResetEvidenceSnapshot(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_lastEvidence = SPipelineEvidenceSnapshot();
    m_lastEvidence.symbol = symbol;
    m_lastEvidence.timeframe = timeframe;
    m_lastEvidence.effectiveMinConfidence = MathMax(0.0, MathMin(1.0, m_filters.confidence.minConfidence));
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

    // L4-002: Include intrabar context in cache validation
    bool cacheHit = (m_cachedContextPrepared &&
                     !cacheStale &&
                     m_cachedContextSymbol == symbol &&
                     m_cachedContextTimeframe == timeframe &&
                     m_cachedContextBarTime == barTime &&
                     m_cachedContextIntrabar == m_intrabarContext);
    
    if(cacheStale && m_cachedContextPrepared)
        {
            LOG_IF2(LOG_LEVEL_DEBUG, "[PIPELINE-CACHE] Symbol=%s | Cache stale (%d bars old), invalidating", symbol, 
                        (int)((iTime(symbol, timeframe, 0) - m_cachedContextBarTime) / PeriodSeconds(timeframe)));
            m_cachedContextPrepared = false;
        }

    if(!cacheHit)
    {
        // Cache miss: Update all engines and refresh evidence
        CTrendEngine* trendEngine = m_mathRegistry ? m_mathRegistry.GetTrend(symbol) : NULL;
        CStructureEngine* structureEngine = m_mathRegistry ? m_mathRegistry.GetStructure(symbol) : NULL;
        CLiquidityEngine* liquidityEngine = m_mathRegistry ? m_mathRegistry.GetLiquidity(symbol) : NULL;
        CVolatilityEngine* volatilityEngine = m_mathRegistry ? m_mathRegistry.GetVolatility(symbol) : NULL;
        
        m_lastEvidence.trendReady = (trendEngine != NULL) && trendEngine.UpdateTrend(symbol, timeframe);
        m_lastEvidence.structureReady = (structureEngine != NULL) && structureEngine.DetectSwingPoints(symbol, timeframe);
        m_lastEvidence.liquidityReady = (liquidityEngine != NULL) && liquidityEngine.DetectLiquidityZones(symbol, timeframe);
        m_lastEvidence.volatilityReady = (volatilityEngine != NULL) && volatilityEngine.UpdateVolatility(symbol, timeframe);

        // Populate evidence snapshot from engines
        RefreshEvidenceFromEngines(symbol);
        m_lastEvidence.contextPrepared = true;
        m_lastEvidence.readinessScore = ComputeReadinessScore();
        
        // Cache the complete evidence snapshot
        m_cachedStructuralEvidence = m_lastEvidence;
        m_cachedContextSymbol = symbol;
        m_cachedContextTimeframe = timeframe;
        m_cachedContextBarTime = barTime;
        m_cachedContextIntrabar = m_intrabarContext;
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

    // Get engines from registry
    CTrendEngine* trendEngine = m_mathRegistry ? m_mathRegistry.GetTrend(symbol) : NULL;
    CStructureEngine* structureEngine = m_mathRegistry ? m_mathRegistry.GetStructure(symbol) : NULL;
    CLiquidityEngine* liquidityEngine = m_mathRegistry ? m_mathRegistry.GetLiquidity(symbol) : NULL;
    CVolatilityEngine* volatilityEngine = m_mathRegistry ? m_mathRegistry.GetVolatility(symbol) : NULL;

    if(trendEngine != NULL && m_lastEvidence.trendReady)
    {
        m_lastEvidence.trend = trendEngine.GetCurrentTrend();
        m_lastEvidence.trendStrength = trendEngine.GetTrendStrength();
        STrendReadinessSnapshot trendReadiness = trendEngine.GetReadinessSnapshot();
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
        m_lastEvidence.stalenessPenalty = MathMin(m_filters.readinessConfig.stalenessPenaltyMax, (double)trendReadiness.stalenessSeconds / (double)MathMax(10, m_filters.readinessConfig.stalenessPenaltyDivisor) * m_filters.readinessConfig.stalenessPenaltyMax);
    }
    else
    {
        m_lastEvidence.trend = TREND_NONE;
        m_lastEvidence.trendStrength = 0.0;
        if(trendEngine != NULL)
        {
            STrendReadinessSnapshot trendReadiness = trendEngine.GetReadinessSnapshot();
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
            m_lastEvidence.stalenessPenalty = MathMin(m_filters.readinessConfig.stalenessPenaltyMax, (double)trendReadiness.stalenessSeconds / (double)MathMax(10, m_filters.readinessConfig.stalenessPenaltyDivisor) * m_filters.readinessConfig.stalenessPenaltyMax);
        }
    }

    if(structureEngine != NULL && m_lastEvidence.structureReady)
    {
        m_lastEvidence.structureStrength = structureEngine.GetStructureStrength();
        m_lastEvidence.bullishStructure = (structureEngine.HasBullishBOS(5) || structureEngine.HasBullishCHOCH(5));
        m_lastEvidence.bearishStructure = (structureEngine.HasBearishBOS(5) || structureEngine.HasBearishCHOCH(5));
    }
    else
    {
        m_lastEvidence.structureStrength = 0.0;
        m_lastEvidence.bullishStructure = false;
        m_lastEvidence.bearishStructure = false;
    }

    if(liquidityEngine != NULL && m_lastEvidence.liquidityReady)
    {
        double probePrice = SymbolInfoDouble(symbol, SYMBOL_BID);
        if(probePrice <= 0.0)
            probePrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
        m_lastEvidence.liquiditySweep = liquidityEngine.HasLiquiditySweep(5);
        m_lastEvidence.priceNearLiquidity = (probePrice > 0.0) ? liquidityEngine.IsPriceNearLiquidity(probePrice, 30) : false;
    }
    else
    {
        m_lastEvidence.liquiditySweep = false;
        m_lastEvidence.priceNearLiquidity = false;
    }

    if(volatilityEngine != NULL && m_lastEvidence.volatilityReady)
    {
        m_lastEvidence.volatilityState = volatilityEngine.GetVolatilityState();
        m_lastEvidence.atrValue = volatilityEngine.GetATR();
        m_lastEvidence.atrPercent = volatilityEngine.GetATRPercent();
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
    double components = 0.0;

    // Dynamic base readiness score based on readiness class with adaptive staleness handling
    double trendReadinessScore = m_filters.readinessConfig.warmupScore;
    if(m_lastEvidence.readinessClass == "HEALTHY")
        trendReadinessScore = m_filters.readinessConfig.healthyScore;
    else if(m_lastEvidence.readinessClass == "REUSED_SNAPSHOT")
        trendReadinessScore = MathMax(0.45, m_filters.readinessConfig.reusedSnapshotScore - m_lastEvidence.stalenessPenalty);
    else if(m_lastEvidence.readinessClass == "TRANSIENT_COPY_FAULT")
        trendReadinessScore = m_filters.readinessConfig.transientCopyFaultScore;
    else if(m_lastEvidence.readinessClass == "HANDLE_FAULT")
        trendReadinessScore = m_filters.readinessConfig.handleFaultScore;
    else if(m_lastEvidence.readinessClass == "WARMUP")
        trendReadinessScore = m_filters.readinessConfig.warmupScore;

    // Trend readiness with strength-based adjustment
    if(m_filters.trend.enabled)
    {
        double trendComponent = m_lastEvidence.trendReady ? trendReadinessScore : MathMin(trendReadinessScore, 0.62);
        // Boost trend readiness if trend strength is meaningful
        if(m_lastEvidence.trendReady && m_lastEvidence.trendStrength > 50.0)
            trendComponent = MathMin(1.0, trendComponent + 0.08);
        total += trendComponent * m_filters.readinessWeights.trendWeight;
        components += m_filters.readinessWeights.trendWeight;
    }

    // Structure readiness
    if(m_filters.structure.enabled)
    {
        double structureComponent = m_lastEvidence.structureReady ? 0.88 : 0.65;
        if(m_lastEvidence.structureReady && m_lastEvidence.structureStrength > 0.6)
            structureComponent = MathMin(1.0, structureComponent + 0.07);
        total += structureComponent * m_filters.readinessWeights.structureWeight;
        components += m_filters.readinessWeights.structureWeight;
    }

    // Liquidity readiness
    if(m_filters.liquidity.enabled)
    {
        double liquidityComponent = m_lastEvidence.liquidityReady ? 0.92 : 0.68;
        if(m_lastEvidence.liquidityReady && m_lastEvidence.priceNearLiquidity)
            liquidityComponent = MathMin(1.0, liquidityComponent + 0.05);
        total += liquidityComponent * m_filters.readinessWeights.liquidityWeight;
        components += m_filters.readinessWeights.liquidityWeight;
    }

    // Volatility readiness
    if(m_filters.volatility.enabled)
    {
        double volatilityComponent = 0.75;
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
        total += volatilityComponent * m_filters.readinessWeights.volatilityWeight;
        components += m_filters.readinessWeights.volatilityWeight;
    }

    // Regime readiness with cost score integration
    if(m_filters.regimeCostGate.enabled)
    {
        double regimeComponent = m_lastEvidence.regimeValid ? MathMax(0.72, 1.0 - m_lastEvidence.stalenessPenalty) : 0.72;
        // Integrate cost score into regime readiness for more accurate assessment
        if(m_lastEvidence.regimeValid && m_lastEvidence.costScore > 0.0)
            regimeComponent = MathMax(0.65, MathMin(1.0, (regimeComponent + m_lastEvidence.costScore) / 2.0));
        total += regimeComponent * m_filters.readinessWeights.regimeWeight;
        components += m_filters.readinessWeights.regimeWeight;
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
    m_lastEffectiveMinConfidence = MathMax(0.0, MathMin(1.0, m_filters.confidence.minConfidence));
    m_lastFilterName = "";
    m_lastFilterReason = "";

    if(strategy == NULL)
    {
        confidence = 0;
        m_lastRawSignalNone = true;
        return TRADE_SIGNAL_NONE;
    }
    
    // Check budget exhaustion with auto-clear (L4-007)
    CheckBudgetExhaustedAutoClear();
    
    // Issue 14: Skip pipeline evaluation entirely when daily budget is exhausted
    // Saves CPU during budget halt periods — results would be discarded anyway
    if(m_budgetExhausted)
    {
        m_signalsProcessed++;
        m_signalsFiltered++;
        m_lastRawSignalNone = true;
        m_lastFilteredByPipeline = true;
        confidence = 0;
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
    
    // Apply filters in configured order with early exit on failure (L4-001)
    bool passed = true;
    
    // Filter index mapping: 0=RegimeCostGate, 1=Trend, 2=Volatility, 3=Liquidity, 4=Structure, 5=Time, 6=Session
    // Only run filters that are enabled and have a valid order position
    for(int order = 0; order < m_filters.filterOrder.filterOrderCount && order < 7 && passed; order++)
    {
        // Find which filter has this execution order
        int filterIdx = -1;
        for(int i = 0; i < 7; i++)
        {
            if(m_filterOrderMap[i] == order)
            {
                filterIdx = i;
                break;
            }
        }
        
        if(filterIdx == -1)
            continue;
        
        // Skip disabled filters
        bool filterEnabled = false;
        switch(filterIdx)
        {
            case 0: filterEnabled = m_filters.regimeCostGate.enabled; break;
            case 1: filterEnabled = m_filters.trend.enabled; break;
            case 2: filterEnabled = m_filters.volatility.enabled; break;
            case 3: filterEnabled = m_filters.liquidity.enabled; break;
            case 4: filterEnabled = m_filters.structure.enabled; break;
            case 5: filterEnabled = m_filters.session.enableTimeFilter; break;
            case 6: filterEnabled = m_filters.session.enableSessionFilter; break;
        }
        
        if(!filterEnabled)
            continue;
        
        // Execute the filter
        bool filterPassed = false;
        string vetoReason = "";
        
        switch(filterIdx)
        {
            case 0: // RegimeCostGate
                filterPassed = ApplyRegimeAndCostGate(symbol, timeframe, signal, confidence, vetoReason);
                if(!filterPassed)
                    LogFilterResult("RegimeCostGate", false, vetoReason);
                break;
            case 1: // TrendFilter
                filterPassed = ApplyTrendFilter(signal, confidence);
                break;
            case 2: // VolatilityFilter
                filterPassed = ApplyVolatilityFilter(signal, confidence);
                break;
            case 3: // LiquidityFilter
                filterPassed = ApplyLiquidityFilter(signal, confidence, symbol);
                break;
            case 4: // StructureFilter
                filterPassed = ApplyStructureFilter(signal, confidence);
                break;
            case 5: // TimeFilter
                filterPassed = ApplyTimeFilter(signal, symbol);
                break;
            case 6: // SessionFilter
                filterPassed = ApplySessionFilter(symbol);
                break;
        }
        
        if(!filterPassed)
        {
            passed = false;
            // Early exit - stop processing remaining filters
            break;
        }
    }
    
    m_lastEvidence.contextScore = ComputeContextScore(signal);
    m_lastEvidence.readinessScore = ComputeReadinessScore();

    // I7: Apply session-aware readiness boost (weekend = +0.05, Asian = +0.02, etc.)
    if(m_sessionWeightManager != NULL && m_sessionWeightManager.IsInitialized())
    {
       double sessionBoost = m_sessionWeightManager.GetReadinessBoost();
       if(MathAbs(sessionBoost) > 0.001)
       {
          m_lastEvidence.readinessScore = MathMax(0.0, MathMin(1.0, m_lastEvidence.readinessScore + sessionBoost));
       }
    }

    // Dynamic confidence threshold with bounded intrabar uplift in weak regimes.
    double baseMinConfidence = m_filters.confidence.minConfidence;
    double effectiveMinConfidence = baseMinConfidence;
    double appliedCap = 0.0;
    string thresholdReasonTag = "BASE_THRESHOLD";

    if(m_lastRegimeSnapshotValid)
    {
        if(m_lastRegimeState == REGIME_RANGE)
        {
            thresholdReasonTag = "REGIME_RANGE";
            double regimeAdjustedThreshold = MathMax(baseMinConfidence, baseMinConfidence * 1.03);
            if(m_intrabarContext)
            {
                // Batch 116: cap is always applied in intrabar mode — take the lower of cap and regime threshold
                appliedCap = MathMax(0.0, m_filters.confidence.intrabarConfidenceCap);
                double cappedThreshold = baseMinConfidence + appliedCap;
                effectiveMinConfidence = MathMin(1.0, MathMin(cappedThreshold, regimeAdjustedThreshold));
            }
            else
            {
                effectiveMinConfidence = MathMin(1.0, regimeAdjustedThreshold);
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
            double regimeAdjustedThreshold = MathMax(baseMinConfidence, baseMinConfidence * 1.05);
            if(m_intrabarContext)
            {
                appliedCap = MathMax(0.0, m_filters.confidence.intrabarConfidenceCap);
                double cappedThreshold = baseMinConfidence + appliedCap;
                effectiveMinConfidence = MathMin(1.0, MathMin(cappedThreshold, regimeAdjustedThreshold));
            }
            else
            {
                effectiveMinConfidence = MathMin(1.0, regimeAdjustedThreshold);
            }
        }
    }
    else
    {
        CTrendEngine* trendEngine = m_mathRegistry ? m_mathRegistry.GetTrend(m_lastEvaluatedSymbol) : NULL;
        if(trendEngine != NULL)
        {
            if(trendEngine.IsStrongTrend())
            {
                thresholdReasonTag = "TREND_ENGINE_STRONG_RELAX";
                effectiveMinConfidence = MathMax(0.0, baseMinConfidence * 0.95);
            }
            else
            {
                thresholdReasonTag = "REGIME_ENGINE_WARMUP";
            }
        }
        else
        {
            thresholdReasonTag = "REGIME_ENGINE_WARMUP";
        }
    }

    // I3: Apply session-aware threshold adjustment
    if(m_sessionWeightManager != NULL && m_sessionWeightManager.IsInitialized())
    {
       SSessionWeights sessionWeights = m_sessionWeightManager.GetCurrentSessionWeights();
       effectiveMinConfidence += sessionWeights.convictionThresholdAdj;
       effectiveMinConfidence = MathMax(0.30, MathMin(0.95, effectiveMinConfidence));
       thresholdReasonTag += "|" + sessionWeights.sessionName;
    }

    LOG_IF5(LOG_LEVEL_DEBUG, "[PIPELINE-THRESHOLD] base=%.2f | effective=%.2f | regime=%s | cap=%.2f | intrabar=%s",
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
    CRegimeEngine* regimeEngine = m_mathRegistry ? m_mathRegistry.GetRegime(symbol) : NULL;
    if(regimeEngine == NULL)
        return true;

    if(!regimeEngine.Update(symbol, timeframe))
    {
        // Neutral degrade when regime engine data is warming/faulted.
        confidence = MathMax(0.0, confidence * 0.98);
        return true;
    }

    SRegimeSnapshot snapshot = regimeEngine.GetSnapshot();
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
                                                  MathMin(m_filters.readinessConfig.stalenessPenaltyMax, (double)snapshot.stalenessSeconds / (double)MathMax(10, m_filters.readinessConfig.stalenessPenaltyDivisor) * m_filters.readinessConfig.stalenessPenaltyMax));

        string regimeTag = regimeEngine.GetStateTag();
    
        // L4-013 Fix: Regime gate log throttling
        m_regimeGateLogCounter++;
        if(m_regimeGateLogCounter >= m_regimeGateLogInterval)
        {
            m_regimeGateLogCounter = 0;
            LOG_IF9(LOG_LEVEL_DEBUG, "[COST-GATE] %s | regime=%s | spread_atr=%.6f/%.6f | spread=%.5f | atr=%.5f | cooldown=%s | z=%.3f/%.3f",
                        symbol,
                        regimeTag,
                        snapshot.spreadToAtrRatio,
                        m_filters.regimeCostGate.maxSpreadToAtrRatio,
                        snapshot.spreadPrice,
                        snapshot.atrValue,
                        snapshot.spreadShockCooldownActive ? "true" : "false",
                        snapshot.rangeZScore,
                        m_filters.regimeCostGate.maxEntryRangeZScore);
        }

    // Regime-aware confidence attenuation while preserving deterministic output.
    // REDUCED PENALTIES: was 0.97 RANGE, 0.92 CHAOS - now much lighter to avoid blocking marginal signals
    if(snapshot.state == REGIME_RANGE)
        confidence = MathMax(0.0, confidence * 0.99);  // Minimal penalty for ranging
    else if(snapshot.state == REGIME_CHAOS)
        confidence = MathMax(0.0, confidence * 0.97);  // Reduced from 0.92 for chaos

    double spreadPenalty = 0.0;
    if(m_filters.regimeCostGate.maxSpreadToAtrRatio > 0.0)
        spreadPenalty = MathMin(0.30, (snapshot.spreadToAtrRatio / m_filters.regimeCostGate.maxSpreadToAtrRatio) * 0.15);
    double zPenalty = 0.0;
    if(m_filters.regimeCostGate.maxEntryRangeZScore > 0.0)
        zPenalty = MathMin(0.20, (MathAbs(snapshot.rangeZScore) / m_filters.regimeCostGate.maxEntryRangeZScore) * 0.10);
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
            LOG_IF2(LOG_LEVEL_WARN, "[ENTRY-VETO] %s | reason=%s", symbol, vetoReasonTag);
            signal = TRADE_SIGNAL_NONE;
            confidence = 0.0;
            return false;
        }

    if(snapshot.spreadToAtrRatio > m_filters.regimeCostGate.maxSpreadToAtrRatio)
        {
            vetoReasonTag = StringFormat("REGIME_%s | spread/ATR ratio %.4f exceeds %.4f",
                                         regimeTag, snapshot.spreadToAtrRatio, m_filters.regimeCostGate.maxSpreadToAtrRatio);
            m_lastEvidence.vetoReasonTag = vetoReasonTag;
            LOG_IF2(LOG_LEVEL_WARN, "[ENTRY-VETO] %s | reason=%s", symbol, vetoReasonTag);
            signal = TRADE_SIGNAL_NONE;
            confidence = 0.0;
            return false;
        }

    if(MathAbs(snapshot.rangeZScore) > m_filters.regimeCostGate.maxEntryRangeZScore)
        {
            vetoReasonTag = StringFormat("REGIME_%s | late-entry z-score %.3f exceeds %.3f",
                                         regimeTag, snapshot.rangeZScore, m_filters.regimeCostGate.maxEntryRangeZScore);
            m_lastEvidence.vetoReasonTag = vetoReasonTag;
            LOG_IF2(LOG_LEVEL_WARN, "[ENTRY-VETO] %s | reason=%s", symbol, vetoReasonTag);
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
    CTrendEngine* trendEngine = m_mathRegistry ? m_mathRegistry.GetTrend(m_lastEvaluatedSymbol) : NULL;
    if(trendEngine == NULL)
        return true;
    
    ENUM_TREND_TYPE trend = trendEngine.GetCurrentTrend();
    double trendStrength = trendEngine.GetTrendStrength();
    
    // Only bypass trend alignment in neutral/ranging regimes for truly exceptional confidence.
    if(confidence > 0.82 && (trend == TREND_RANGING || trend == TREND_NONE))
    {
        LogFilterResult("TrendFilter", true, 
                       StringFormat("BYPASSED - High confidence in neutral trend (%.2f) | Trend: %s", 
                                  confidence, EnumToString(trend)));
        return true;
    }
    
    // ✨ FIX: Allow ranging markets - check if trend is actively AGAINST the signal
    // Only reject if there's a STRONG opposing trend
    bool strongOpposingTrend = false;
    
    if(signal == TRADE_SIGNAL_BUY && trendEngine.IsTrendBearish() && trendStrength > 75)
        strongOpposingTrend = true;
    else if(signal == TRADE_SIGNAL_SELL && trendEngine.IsTrendBullish() && trendStrength > 75)
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
    
    // ✨ FIX: ALLOW signals in ranging markets (TREND_RANGING, TREND_NONE)
    // These are valid trading opportunities
    if(trend == TREND_RANGING || trend == TREND_NONE)
    {
        LogFilterResult("TrendFilter", true, 
                       StringFormat("PASSED - Ranging market | Strength: %.1f", trendStrength));
        return true;
    }
    
    // Check signal alignment with trend (only for trending markets)
    bool aligned = false;
    if(signal == TRADE_SIGNAL_BUY && trendEngine.IsTrendBullish())
        aligned = true;
    else if(signal == TRADE_SIGNAL_SELL && trendEngine.IsTrendBearish())
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
    if(trendEngine.IsStrongTrend())
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
    CVolatilityEngine* volatilityEngine = m_mathRegistry ? m_mathRegistry.GetVolatility(m_lastEvaluatedSymbol) : NULL;
    if(volatilityEngine == NULL)
        return true;
    
    ENUM_VOLATILITY_STATE volState = volatilityEngine.GetVolatilityState();
    double atrPercent = volatilityEngine.GetATRPercent();
    
    // Check maximum volatility
    double hardVolatilityLimit = m_filters.volatility.maxVolatility * 1.35;
    if(atrPercent > hardVolatilityLimit)
    {
        LogFilterResult("VolatilityFilter", false,
                       StringFormat("Volatility %.2f%% exceeds hard limit %.2f%%",
                                    atrPercent, hardVolatilityLimit));
        return false;
    }
    else if(atrPercent > m_filters.volatility.maxVolatility)
    {
        confidence *= 0.82;
        confidence = MathMin(1.0, MathMax(0.0, confidence));
        LogFilterResult("VolatilityFilter", true,
                       StringFormat("Volatility %.2f%% above soft maximum %.2f%% | confidence attenuated",
                                    atrPercent, m_filters.volatility.maxVolatility));
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
    CLiquidityEngine* liquidityEngine = m_mathRegistry ? m_mathRegistry.GetLiquidity(symbol) : NULL;
    if(liquidityEngine == NULL)
        return true;
    
    // Check for recent liquidity sweep
    if(liquidityEngine.HasLiquiditySweep(5))
    {
        confidence *= 1.15; // Boost confidence after liquidity grab
        LogFilterResult("LiquidityFilter", true, "Recent liquidity sweep detected");
    }
    
    // Check if price is near liquidity
    string liquiditySymbol = (symbol != "") ? symbol : _Symbol;
    double localCurrentPrice = SymbolInfoDouble(liquiditySymbol, SYMBOL_BID);
    if(liquidityEngine.IsPriceNearLiquidity(localCurrentPrice, 30))
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
    CStructureEngine* structureEngine = m_mathRegistry ? m_mathRegistry.GetStructure(m_lastEvaluatedSymbol) : NULL;
    if(structureEngine == NULL)
        return true;
    
    bool structureAligned = false;
    
    // Check for BOS/CHOCH alignment
    if(signal == TRADE_SIGNAL_BUY)
    {
        if(structureEngine.HasBullishBOS(5) || structureEngine.HasBullishCHOCH(5))
        {
            structureAligned = true;
            confidence *= 1.2;
        }
    }
    else if(signal == TRADE_SIGNAL_SELL)
    {
        if(structureEngine.HasBearishBOS(5) || structureEngine.HasBearishCHOCH(5))
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
    
    // Use global multi-asset profiler for proper asset classification
    if(g_multiAssetProfiler != NULL)
    {
        SAssetProfile profile = g_multiAssetProfiler.GetProfile(symbol);
        return IsSyntheticAssetClass(profile.assetClass);
    }
    
    // Fallback to string matching if profiler not available
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
    if(m_filters.session.allowSyntheticOffHours && IsSyntheticSymbol(symbol))
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
    if(m_filters.session.allowSyntheticOffHours && IsSyntheticSymbol(symbol))
        return true;
    
    if(!m_filters.session.enableSessionFilter)
        return true;
    
    MqlDateTime dt;
    TimeToStruct(TimeGMT(), dt);
    int gmtHour = dt.hour;
    
    // Tokyo session: 00:00-09:00 GMT
    if(m_filters.session.tradeTokyoSession && gmtHour >= 0 && gmtHour < 9)
        return true;
    
    // London session: 08:00-17:00 GMT
    if(m_filters.session.tradeLondonSession && gmtHour >= 8 && gmtHour < 17)
        return true;
    
    // New York session: 13:00-22:00 GMT
    if(m_filters.session.tradeNewYorkSession && gmtHour >= 13 && gmtHour < 22)
        return true;
    
    LogFilterResult("SessionFilter", false, StringFormat("Not in active trading session: %d:00 GMT", gmtHour));
    return false;
}

//+------------------------------------------------------------------+
//| Apply Spread Filter (Unified)                                    |
//+------------------------------------------------------------------+
bool CUnifiedSignalPipeline::ApplySpreadFilter(const string symbol, double &spreadScore, double overrideThreshold = -1.0, double atrValue = -1.0)
{
    if(symbol == "")
        return true;

    double atr = atrValue;
    if(atr <= 0.0)
    {
        atr = m_lastEvidence.atrValue;
        if(atr <= 0.0)
        {
            CVolatilityEngine* volatilityEngine = m_mathRegistry ? m_mathRegistry.GetVolatility(symbol) : NULL;
            if(volatilityEngine != NULL)
                atr = volatilityEngine.GetATR();
        }
    }
    if(atr <= 0.0)
    {
        spreadScore = 0.0;
        return true;
    }

    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    if(point <= 0.0)
        point = 0.00001;

    long spreadRaw = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
    double spread = (double)spreadRaw * point;

    double threshold = (overrideThreshold > 0.0) ? overrideThreshold : m_filters.regimeCostGate.maxSpreadToAtrRatio;
    double ratio = spread / atr;
    spreadScore = ratio;

    if(ratio >= threshold)
    {
        LogFilterResult("SpreadFilter", false,
                        StringFormat("Spread ratio %.4f >= %.4f (spread %.5f, ATR %.5f)",
                                    ratio, threshold, spread, atr));
        return false;
    }

    LogFilterResult("SpreadFilter", true,
                    StringFormat("Spread ratio %.4f < %.4f (spread %.5f, ATR %.5f)",
                                ratio, threshold, spread, atr));
    return true;
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
    
    // Normalized weights summing to 1.0 (was 0.92, scaled by 1/0.92 = 1.0869565...)
    // Original: confidence=0.20, confluence=0.10, conviction=0.12, readiness=0.08,
    //           context=0.08, diversity=0.07, cost=0.05, directionalQuality=0.15, supportRatio=0.07
    // Filter bonus removed as ad-hoc component; its weight redistributed
    
    // Confidence component
    score += confidence * 0.2174;
    
    // Confluence component (Biased scale to avoid punishing solo high-quality signals)
    double confluenceScore = 0.0;
    if(confluence == 1) confluenceScore = 0.50;      // Solo signal starts with decent baseline
    else if(confluence == 2) confluenceScore = 0.80;
    else if(confluence >= 3) confluenceScore = 1.0;
    score += confluenceScore * 0.1087;
    
    // Decision-path components with NaN protection
    convictionScore = MathIsValidNumber(convictionScore) ? convictionScore : 0.0;
    readinessScore = MathIsValidNumber(readinessScore) ? readinessScore : 0.0;
    contextScore = MathIsValidNumber(contextScore) ? contextScore : 0.0;
    diversityScore = MathIsValidNumber(diversityScore) ? diversityScore : 0.0;
    costScore = MathIsValidNumber(costScore) ? costScore : 0.0;
    directionalQuality = MathIsValidNumber(directionalQuality) ? directionalQuality : 0.0;
    supportRatio = MathIsValidNumber(supportRatio) ? supportRatio : 0.0;
    
    score += MathMax(0.0, MathMin(1.0, convictionScore)) * 0.1304;
    score += MathMax(0.0, MathMin(1.0, readinessScore)) * 0.0870;
    score += MathMax(0.0, MathMin(1.0, contextScore)) * 0.0870;
    score += MathMax(0.0, MathMin(1.0, diversityScore)) * 0.0761;
    score += MathMax(0.0, MathMin(1.0, costScore)) * 0.0543;
    score += MathMax(0.0, MathMin(1.0, directionalQuality)) * 0.1630;
    score += MathMax(0.0, MathMin(1.0, supportRatio)) * 0.0761;
    
    // Filter component (properly weighted at 5%)
    if(passedFilters)
        score += 1.0 * 0.0543;
    
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
    // Health is now checked on-demand via registry
    // This method just updates the last check time
    m_lastHealthCheckTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Is Engine Healthy (private)                                      |
//+------------------------------------------------------------------+
bool CUnifiedSignalPipeline::IsEngineHealthy()
{
    if(m_mathRegistry == NULL || m_lastEvaluatedSymbol == "")
        return false;
    
    // Check if all required engines are available AND healthy for the last evaluated symbol
    CTrendEngine* trendEngine = m_mathRegistry.GetTrend(m_lastEvaluatedSymbol);
    CStructureEngine* structureEngine = m_mathRegistry.GetStructure(m_lastEvaluatedSymbol);
    CLiquidityEngine* liquidityEngine = m_mathRegistry.GetLiquidity(m_lastEvaluatedSymbol);
    CVolatilityEngine* volatilityEngine = m_mathRegistry.GetVolatility(m_lastEvaluatedSymbol);
    CRegimeEngine* regimeEngine = m_mathRegistry.GetRegime(m_lastEvaluatedSymbol);
    
    if(trendEngine == NULL || structureEngine == NULL || liquidityEngine == NULL || 
       volatilityEngine == NULL || regimeEngine == NULL)
        return false;
    
    // Check engine readiness states (not just pointer validity)
    STrendReadinessSnapshot trendReadiness = trendEngine.GetReadinessSnapshot();
    if(trendReadiness.state != TREND_READINESS_HEALTHY && trendReadiness.state != TREND_READINESS_REUSED_SNAPSHOT)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Perform Health Check (public)                                    |
//+------------------------------------------------------------------+
void CUnifiedSignalPipeline::PerformHealthCheck(const string symbol)
{
    CheckEngineHealth(symbol);
    
    // Check engine availability AND readiness for this symbol
    CTrendEngine* trendEngine = m_mathRegistry ? m_mathRegistry.GetTrend(symbol) : NULL;
    CStructureEngine* structureEngine = m_mathRegistry ? m_mathRegistry.GetStructure(symbol) : NULL;
    CLiquidityEngine* liquidityEngine = m_mathRegistry ? m_mathRegistry.GetLiquidity(symbol) : NULL;
    CVolatilityEngine* volatilityEngine = m_mathRegistry ? m_mathRegistry.GetVolatility(symbol) : NULL;
    CRegimeEngine* regimeEngine = m_mathRegistry ? m_mathRegistry.GetRegime(symbol) : NULL;
    
    bool trendOk = (trendEngine != NULL);
    bool structureOk = (structureEngine != NULL);
    bool liquidityOk = (liquidityEngine != NULL);
    bool volatilityOk = (volatilityEngine != NULL);
    bool regimeOk = (regimeEngine != NULL);
    
    // Check readiness states if engines exist
    if(trendOk)
    {
        STrendReadinessSnapshot trendReadiness = trendEngine.GetReadinessSnapshot();
        trendOk = (trendReadiness.state == TREND_READINESS_HEALTHY || trendReadiness.state == TREND_READINESS_REUSED_SNAPSHOT);
    }
    
    bool allHealthy = trendOk && structureOk && liquidityOk && volatilityOk && regimeOk;
    
    string status = allHealthy ? "HEALTHY" : "DEGRADED";
    LOG_IF7(LOG_LEVEL_DEBUG, "[PIPELINE-HEALTH] Symbol=%s | Status=%s | Trend=%s | Structure=%s | Liquidity=%s | Volatility=%s | Regime=%s",
                symbol,
                status,
                trendOk ? "OK" : "FAIL",
                structureOk ? "OK" : "FAIL",
                liquidityOk ? "OK" : "FAIL",
                volatilityOk ? "OK" : "FAIL",
                regimeOk ? "OK" : "FAIL");
}

//+------------------------------------------------------------------+
//| Is Pipeline Healthy (public)                                     |
//+------------------------------------------------------------------+
bool CUnifiedSignalPipeline::IsPipelineHealthy()
{
    return IsEngineHealthy();
}

//+------------------------------------------------------------------+
//| Get Engine Health Status (public)                               |
//+------------------------------------------------------------------+
string CUnifiedSignalPipeline::GetEngineHealthStatus()
{
    if(IsEngineHealthy())
        return "ALL_ENGINES_HEALTHY";
    
    if(m_mathRegistry == NULL || m_lastEvaluatedSymbol == "")
        return "DEGRADED: NO_REGISTRY_OR_SYMBOL";
    
    string status = "DEGRADED:";
    CTrendEngine* trendEngine = m_mathRegistry.GetTrend(m_lastEvaluatedSymbol);
    if(trendEngine == NULL)
        status += " TREND";
    else
    {
        STrendReadinessSnapshot trendReadiness = trendEngine.GetReadinessSnapshot();
        if(trendReadiness.state != TREND_READINESS_HEALTHY && trendReadiness.state != TREND_READINESS_REUSED_SNAPSHOT)
            status += " TREND(" + EnumToString(trendReadiness.state) + ")";
    }
    
    if(m_mathRegistry.GetStructure(m_lastEvaluatedSymbol) == NULL) status += " STRUCTURE";
    if(m_mathRegistry.GetLiquidity(m_lastEvaluatedSymbol) == NULL) status += " LIQUIDITY";
    if(m_mathRegistry.GetVolatility(m_lastEvaluatedSymbol) == NULL) status += " VOLATILITY";
    if(m_mathRegistry.GetRegime(m_lastEvaluatedSymbol) == NULL) status += " REGIME";
    
    return status;
}

//+------------------------------------------------------------------+
//| Apply Filter Preset (public)                                    |
//+------------------------------------------------------------------+
void CUnifiedSignalPipeline::ApplyFilterPreset(ENUM_FILTER_PRESET preset)
{
    m_filters.ApplyPreset(preset);
    BuildFilterOrderMap();
}

#endif // UNIFIED_SIGNAL_PIPELINE_MQH
