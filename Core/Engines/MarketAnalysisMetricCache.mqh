//+------------------------------------------------------------------+
//| MarketAnalysisMetricCache.mqh - Last-valid metric reuse cache    |
//| Extracted verbatim from MarketAnalysis.mqh (no behavior change)  |
//+------------------------------------------------------------------+
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef MARKET_ANALYSIS_METRIC_CACHE_MQH
#define MARKET_ANALYSIS_METRIC_CACHE_MQH

//+------------------------------------------------------------------+
//| Owns the "last valid" metric snapshots used to survive transient |
//| history-sync failures (errors 4806 / 4807) plus the throttled    |
//| reuse logging state.                                             |
//+------------------------------------------------------------------+
class CMarketAnalysisMetricCache
{
private:
    double   m_lastValidTrendStrength;
    double   m_lastValidVolatility;
    double   m_lastValidMomentum;
    double   m_lastValidAtrValue;
    datetime m_lastValidTrendTime;
    datetime m_lastValidVolatilityTime;
    datetime m_lastValidMomentumTime;
    datetime m_lastValidAtrTime;
    datetime m_lastMetricReuseLogTime;

public:
    CMarketAnalysisMetricCache() :
        m_lastValidTrendStrength(0.0),
        m_lastValidVolatility(0.0),
        m_lastValidMomentum(0.0),
        m_lastValidAtrValue(0.0),
        m_lastValidTrendTime(0),
        m_lastValidVolatilityTime(0),
        m_lastValidMomentumTime(0),
        m_lastValidAtrTime(0),
        m_lastMetricReuseLogTime(0)
    {
    }

    //--- Drop every cached metric (symbol/timeframe switch)
    void ResetMetricCaches();

    //--- Reuse window derived from the active timeframe
    int GetMetricReuseWindowSeconds(const ENUM_TIMEFRAMES period) const;

    //--- True while a cached metric is still young enough to be reused
    bool CanReuseMetric(const datetime metricTime, const ENUM_TIMEFRAMES period) const;

    //--- Throttled diagnostic emitted when a cached metric is reused
    void MaybeLogMetricReuse(const string symbol,
                             const ENUM_TIMEFRAMES period,
                             const string metricName,
                             const string reasonTag,
                             const int errorCode,
                             const datetime metricTime);

    //--- Accessors
    double   LastValidTrendStrength()  const { return m_lastValidTrendStrength; }
    datetime LastValidTrendTime()      const { return m_lastValidTrendTime; }
    double   LastValidVolatility()     const { return m_lastValidVolatility; }
    datetime LastValidVolatilityTime() const { return m_lastValidVolatilityTime; }
    double   LastValidMomentum()       const { return m_lastValidMomentum; }
    datetime LastValidMomentumTime()   const { return m_lastValidMomentumTime; }
    double   LastValidAtrValue()       const { return m_lastValidAtrValue; }
    datetime LastValidAtrTime()        const { return m_lastValidAtrTime; }

    //--- Mutators
    void StoreValidTrend(const double value, const datetime when)
    {
        m_lastValidTrendStrength = value;
        m_lastValidTrendTime = when;
    }

    void StoreValidVolatility(const double value, const datetime when)
    {
        m_lastValidVolatility = value;
        m_lastValidVolatilityTime = when;
    }

    void StoreValidMomentum(const double value, const datetime when)
    {
        m_lastValidMomentum = value;
        m_lastValidMomentumTime = when;
    }

    void StoreValidAtr(const double value, const datetime when)
    {
        m_lastValidAtrValue = value;
        m_lastValidAtrTime = when;
    }
};

//+------------------------------------------------------------------+
//| Drop every cached metric                                         |
//+------------------------------------------------------------------+
void CMarketAnalysisMetricCache::ResetMetricCaches()
{
    m_lastValidTrendStrength = 0.0;
    m_lastValidVolatility = 0.0;
    m_lastValidMomentum = 0.0;
    m_lastValidAtrValue = 0.0;
    m_lastValidTrendTime = 0;
    m_lastValidVolatilityTime = 0;
    m_lastValidMomentumTime = 0;
    m_lastValidAtrTime = 0;
    m_lastMetricReuseLogTime = 0;
}

//+------------------------------------------------------------------+
//| Reuse window derived from the active timeframe                   |
//+------------------------------------------------------------------+
int CMarketAnalysisMetricCache::GetMetricReuseWindowSeconds(const ENUM_TIMEFRAMES period) const
{
    int barSeconds = PeriodSeconds(period);
    if(barSeconds <= 0)
        barSeconds = 60;
    // Allow reuse for up to 3 bars, with minimum 60 seconds and maximum 1 hour
    return MathMax(60, MathMin(3600, barSeconds * 3));
}

//+------------------------------------------------------------------+
//| True while a cached metric is still young enough to be reused    |
//+------------------------------------------------------------------+
bool CMarketAnalysisMetricCache::CanReuseMetric(const datetime metricTime, const ENUM_TIMEFRAMES period) const
{
    return (metricTime > 0 && (TimeCurrent() - metricTime) <= GetMetricReuseWindowSeconds(period));
}

//+------------------------------------------------------------------+
//| Throttled diagnostic emitted when a cached metric is reused      |
//+------------------------------------------------------------------+
void CMarketAnalysisMetricCache::MaybeLogMetricReuse(const string symbol,
                                                     const ENUM_TIMEFRAMES period,
                                                     const string metricName,
                                                     const string reasonTag,
                                                     const int errorCode,
                                                     const datetime metricTime)
{
    if(metricTime <= 0)
        return;

    datetime nowTime = TimeCurrent();
    if(m_lastMetricReuseLogTime != 0 && (nowTime - m_lastMetricReuseLogTime) < 30)
        return;

    int ageSeconds = (int)MathMax(0, nowTime - metricTime);
    PrintFormat("[MARKET-ANALYSIS] REUSE_LAST_VALID | symbol=%s | timeframe=%s | metric=%s | reason=%s | age=%ds | err=%d",
                symbol,
                EnumToString(period),
                metricName,
                reasonTag,
                ageSeconds,
                errorCode);
    m_lastMetricReuseLogTime = nowTime;
}

#endif // MARKET_ANALYSIS_METRIC_CACHE_MQH
