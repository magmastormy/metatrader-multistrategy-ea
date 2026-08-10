//+------------------------------------------------------------------+
//| Signal Pipeline Collector - structural evidence collection       |
//| Owns cache + engine evidence refresh (extracted, stateless).     |
//+------------------------------------------------------------------+
#ifndef SIGNAL_PIPELINE_COLLECTOR_MQH
#define SIGNAL_PIPELINE_COLLECTOR_MQH

#include "../Utils/Enums.mqh"
#include "../../Core/Registry/MathematicalEngineRegistry.mqh"
#include "SignalPipelineTypes.mqh"
#include "SignalPipelineWeighter.mqh"

class CSignalPipelineCollector
{
public:
static void ResetEvidenceSnapshot(const SignalFilterSettings &m_filters, SPipelineEvidenceSnapshot &m_lastEvidence, const string symbol, ENUM_TIMEFRAMES timeframe)
{
    m_lastEvidence = SPipelineEvidenceSnapshot();
    m_lastEvidence.symbol = symbol;
    m_lastEvidence.timeframe = timeframe;
    m_lastEvidence.effectiveMinConfidence = MathMax(0.0, MathMin(1.0, m_filters.confidence.minConfidence));
}

static void RefreshEvidenceFromEngines(CMathematicalEngineRegistry* m_mathRegistry, const SignalFilterSettings &m_filters, SPipelineEvidenceSnapshot &m_lastEvidence, const string symbol)
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

static bool RefreshStructuralContext(CMathematicalEngineRegistry* m_mathRegistry, const SignalFilterSettings &m_filters, const bool m_intrabarContext, SPipelineEvidenceSnapshot &m_lastEvidence, SPipelineEvidenceSnapshot &m_cachedStructuralEvidence, string &m_cachedContextSymbol, ENUM_TIMEFRAMES &m_cachedContextTimeframe, datetime &m_cachedContextBarTime, bool &m_cachedContextPrepared, bool &m_cachedContextIntrabar, const string symbol, ENUM_TIMEFRAMES timeframe)
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
        RefreshEvidenceFromEngines(m_mathRegistry, m_filters, m_lastEvidence, symbol);
        m_lastEvidence.contextPrepared = true;
        m_lastEvidence.readinessScore = CSignalPipelineWeighter::ComputeReadinessScore(m_filters, m_lastEvidence);
        
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
            return RefreshStructuralContext(m_mathRegistry, m_filters, m_intrabarContext,
                                            m_lastEvidence, m_cachedStructuralEvidence,
                                            m_cachedContextSymbol, m_cachedContextTimeframe,
                                            m_cachedContextBarTime, m_cachedContextPrepared,
                                            m_cachedContextIntrabar, symbol, timeframe);
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
        m_lastEvidence.readinessScore = CSignalPipelineWeighter::ComputeReadinessScore(m_filters, m_lastEvidence);
        
        // Note: We do NOT call RefreshEvidenceFromEngines on cache hit to preserve the cached snapshot
        // The regime engine is updated separately in ApplyRegimeAndCostGate if needed
    }

    return true;
}
};

#endif // SIGNAL_PIPELINE_COLLECTOR_MQH
