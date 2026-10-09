// Unified Signal Pipeline - Enterprise Grade
// Central hub for all strategy signals with filtering
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

// Decomposed modules (extracted God-Object groups — coordinator retains public API)
#include "SignalPipelineTypes.mqh"
#include "SignalPipelineNormalizer.mqh"
#include "SignalPipelineWeighter.mqh"
#include "SignalPipelineCollector.mqh"
#include "SignalPipelineFilter.mqh"
#include "SignalPipelineAggregator.mqh"

class CUnifiedSignalPipeline
{
private:
    // Registry references (engines obtained from registry)
    CMathematicalEngineRegistry* m_mathRegistry;
    
    // Protection / consistency
    CTimeframeConsistency* m_tfConsistency;

    // I3: Session weight manager (injected from EA)
    CSessionWeightManager* m_sessionWeightManager;
    
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

// Constructor
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

// Destructor
CUnifiedSignalPipeline::~CUnifiedSignalPipeline()
{
    // Engines are owned by the registry, not by this pipeline
    if(m_tfConsistency != NULL) { delete m_tfConsistency; m_tfConsistency = NULL; }
}

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

// Build filter order map from settings
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

// Check and auto-clear budget exhaustion (L4-007)
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

// Evidence + scoring forwarders (extracted to SignalPipeline*)
// Thin delegators — original signatures preserved 1:1.
void CUnifiedSignalPipeline::ResetEvidenceSnapshot(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    CSignalPipelineCollector::ResetEvidenceSnapshot(m_filters, m_lastEvidence, symbol, timeframe);
}

bool CUnifiedSignalPipeline::RefreshStructuralContext(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    return CSignalPipelineCollector::RefreshStructuralContext(m_mathRegistry, m_filters, m_intrabarContext,
                                                              m_lastEvidence, m_cachedStructuralEvidence,
                                                              m_cachedContextSymbol, m_cachedContextTimeframe,
                                                              m_cachedContextBarTime, m_cachedContextPrepared,
                                                              m_cachedContextIntrabar, symbol, timeframe);
}

void CUnifiedSignalPipeline::RefreshEvidenceFromEngines(const string symbol)
{
    CSignalPipelineCollector::RefreshEvidenceFromEngines(m_mathRegistry, m_filters, m_lastEvidence, symbol);
}

double CUnifiedSignalPipeline::ComputeReadinessScore() const
{
    return CSignalPipelineWeighter::ComputeReadinessScore(m_filters, m_lastEvidence);
}

double CUnifiedSignalPipeline::ComputeContextScore(const ENUM_TRADE_SIGNAL signal) const
{
    return CSignalPipelineWeighter::ComputeContextScore(m_lastEvidence, signal);
}

// Process Single Strategy Signal
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

// Process Multiple Timeframe Signals
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
    
    // Calculate consensus if no conflicts (extracted to SignalPipelineAggregator)
    finalConfidence = 0;
    return CSignalPipelineAggregator::TallyConsensus(signals, confidences, count, finalConfidence);
}
// Filter + quality + logging forwarders (extracted)
// Thin delegators — original signatures preserved 1:1.
bool CUnifiedSignalPipeline::ApplyRegimeAndCostGate(const string symbol,
                                                    ENUM_TIMEFRAMES timeframe,
                                                    ENUM_TRADE_SIGNAL &signal,
                                                    double &confidence,
                                                    string &vetoReasonTag)
{
    return CSignalPipelineFilter::ApplyRegimeAndCostGate(m_mathRegistry, m_filters, m_lastEvidence,
                                                         m_lastRegimeSnapshotValid, m_lastRegimeState,
                                                         m_regimeGateLogCounter, m_regimeGateLogInterval,
                                                         symbol, timeframe, signal, confidence, vetoReasonTag);
}

bool CUnifiedSignalPipeline::ApplyTrendFilter(ENUM_TRADE_SIGNAL &signal, double &confidence)
{
    return CSignalPipelineFilter::ApplyTrendFilter(m_mathRegistry, m_lastEvaluatedSymbol,
                                                   m_lastFilterName, m_lastFilterReason, signal, confidence);
}

bool CUnifiedSignalPipeline::ApplyVolatilityFilter(ENUM_TRADE_SIGNAL &signal, double &confidence)
{
    return CSignalPipelineFilter::ApplyVolatilityFilter(m_mathRegistry, m_lastEvaluatedSymbol, m_filters,
                                                        m_lastFilterName, m_lastFilterReason, signal, confidence);
}

bool CUnifiedSignalPipeline::ApplyLiquidityFilter(ENUM_TRADE_SIGNAL &signal, double &confidence, const string symbol)
{
    return CSignalPipelineFilter::ApplyLiquidityFilter(m_mathRegistry, m_lastFilterName, m_lastFilterReason,
                                                       signal, confidence, symbol);
}

bool CUnifiedSignalPipeline::ApplyStructureFilter(ENUM_TRADE_SIGNAL &signal, double &confidence)
{
    return CSignalPipelineFilter::ApplyStructureFilter(m_mathRegistry, m_lastEvaluatedSymbol,
                                                       m_lastFilterName, m_lastFilterReason, signal, confidence);
}

bool CUnifiedSignalPipeline::IsSyntheticSymbol(const string symbol)
{
    return CSignalPipelineNormalizer::IsSyntheticSymbol(symbol);
}

bool CUnifiedSignalPipeline::ApplyTimeFilter(ENUM_TRADE_SIGNAL &signal, const string symbol)
{
    return CSignalPipelineFilter::ApplyTimeFilter(m_filters, m_lastFilterName, m_lastFilterReason, signal, symbol);
}

bool CUnifiedSignalPipeline::ApplySessionFilter(const string symbol)
{
    return CSignalPipelineFilter::ApplySessionFilter(m_filters, m_lastFilterName, m_lastFilterReason, symbol);
}

bool CUnifiedSignalPipeline::ApplySpreadFilter(const string symbol, double &spreadScore, double overrideThreshold, double atrValue)
{
    return CSignalPipelineFilter::ApplySpreadFilter(m_mathRegistry, m_filters, m_lastEvidence,
                                                    m_lastFilterName, m_lastFilterReason,
                                                    symbol, spreadScore, overrideThreshold, atrValue);
}

double CUnifiedSignalPipeline::CalculateQualityScore(double confidence, int confluence, bool passedFilters,
                                                      double convictionScore, double readinessScore, double contextScore,
                                                      double diversityScore, double costScore, double directionalQuality,
                                                      double supportRatio)
{
    return CSignalPipelineWeighter::CalculateQualityScore(confidence, confluence, passedFilters,
                                                          convictionScore, readinessScore, contextScore,
                                                          diversityScore, costScore, directionalQuality,
                                                          supportRatio);
}

void CUnifiedSignalPipeline::LogFilterResult(const string filter, bool passed, const string reason)
{
    CSignalPipelineFilter::LogResult(m_lastFilterName, m_lastFilterReason, filter, passed, reason);
}

// Check Engine Health (private)
void CUnifiedSignalPipeline::CheckEngineHealth(const string symbol)
{
    // Health is now checked on-demand via registry
    // This method just updates the last check time
    m_lastHealthCheckTime = TimeCurrent();
}

// Is Engine Healthy (private)
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

// Perform Health Check (public)
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

// Is Pipeline Healthy (public)
bool CUnifiedSignalPipeline::IsPipelineHealthy()
{
    return IsEngineHealthy();
}

// Get Engine Health Status (public)
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

// Apply Filter Preset (public)
void CUnifiedSignalPipeline::ApplyFilterPreset(ENUM_FILTER_PRESET preset)
{
    m_filters.ApplyPreset(preset);
    BuildFilterOrderMap();
}

#endif // UNIFIED_SIGNAL_PIPELINE_MQH
