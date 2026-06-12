//+------------------------------------------------------------------+
//| HurstEngine.mqh                                                  |
//| Hurst Exponent engine — variance-time method                     |
//| Provides regime classification and strategy weight multipliers   |
//+------------------------------------------------------------------+
#ifndef HURST_ENGINE_MQH
#define HURST_ENGINE_MQH

#include "../Utils/Enums.mqh"

//+------------------------------------------------------------------+
//| Hurst Regime Classification                                      |
//+------------------------------------------------------------------+
enum ENUM_HURST_REGIME
{
    HURST_MEAN_REVERTING = 0,   // H < 0.45
    HURST_RANDOM_WALK = 1,      // 0.45 <= H <= 0.55
    HURST_TRENDING = 2          // H > 0.55
};

//+------------------------------------------------------------------+
//| Hurst Snapshot Structure                                         |
//+------------------------------------------------------------------+
struct SHurstSnapshot
{
    double hurstValue;            // Computed Hurst exponent
    ENUM_HURST_REGIME regime;     // Regime classification
    double confidence;            // R-squared of OLS fit (0-1)
    int barCount;                 // Number of bars used in computation
    datetime timestamp;           // Snapshot timestamp
    double meanRevWeightMult;     // Mean-reversion strategy weight multiplier
    double momentumWeightMult;    // Momentum strategy weight multiplier
    double trendWeightMult;       // Trend strategy weight multiplier
    double breakoutWeightMult;    // Breakout strategy weight multiplier

    SHurstSnapshot() :
        hurstValue(0.5),
        regime(HURST_RANDOM_WALK),
        confidence(0.0),
        barCount(0),
        timestamp(0),
        meanRevWeightMult(0.7),
        momentumWeightMult(0.7),
        trendWeightMult(0.7),
        breakoutWeightMult(0.7)
    {
    }
};

//+------------------------------------------------------------------+
//| CHurstEngine — Variance-Time Hurst Exponent Calculator           |
//+------------------------------------------------------------------+
class CHurstEngine
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    int             m_lookbackPeriod;
    int             m_minLag;
    int             m_maxLag;

    SHurstSnapshot  m_snapshot;
    datetime        m_lastLogTime;
    datetime        m_lastBarTime;

    // --- Throttled logging helper ---
    void ThrottledLog(const string message)
    {
        datetime now = TimeCurrent();
        if(m_lastLogTime == 0 || (now - m_lastLogTime) >= 60)
        {
            PrintFormat("%s", message);
            m_lastLogTime = now;
        }
    }

    // --- Regime to string ---
    string RegimeToString(const ENUM_HURST_REGIME regime) const
    {
        switch(regime)
        {
            case HURST_MEAN_REVERTING: return "MEAN_REVERTING";
            case HURST_RANDOM_WALK:    return "RANDOM_WALK";
            case HURST_TRENDING:       return "TRENDING";
            default:                   return "UNKNOWN";
        }
    }

    // --- Build power-of-2 lag list from minLag to maxLag ---
    int BuildLagList(int &lags[]) const
    {
        ArrayResize(lags, 0);
        int count = 0;
        for(int lag = m_minLag; lag <= m_maxLag; lag *= 2)
        {
            count++;
            ArrayResize(lags, count);
            lags[count - 1] = lag;
        }
        return count;
    }

    // --- Compute variance of lagged differences ---
    // For a given lag k, compute: x[i] = log(close[i]) - log(close[i+k])
    // Then return the variance of x[]
    double ComputeLaggedVariance(const double &logPrices[], const int dataSize,
                                  const int lag) const
    {
        if(dataSize < lag + 2)
            return 0.0;

        int n = dataSize - lag;
        if(n < 2)
            return 0.0;

        // Compute lagged differences
        double sum = 0.0;
        for(int i = 0; i < n; i++)
        {
            double diff = logPrices[i] - logPrices[i + lag];
            sum += diff;
        }
        double mean = sum / (double)n;

        double varSum = 0.0;
        for(int j = 0; j < n; j++)
        {
            double diff = logPrices[j] - logPrices[j + lag];
            double dev = diff - mean;
            varSum += dev * dev;
        }

        return varSum / (double)n;
    }

    // --- OLS linear regression: y = slope * x + intercept ---
    // Returns slope and r-squared. Returns false if degenerate.
    bool OlsRegression(const double &x[], const double &y[], const int n,
                        double &slope, double &rsquared) const
    {
        slope = 0.0;
        rsquared = 0.0;

        if(n < 2)
            return false;

        double sumX = 0.0, sumY = 0.0;
        double sumXX = 0.0, sumXY = 0.0;
        double sumYY = 0.0;

        for(int i = 0; i < n; i++)
        {
            sumX  += x[i];
            sumY  += y[i];
            sumXX += x[i] * x[i];
            sumXY += x[i] * y[i];
            sumYY += y[i] * y[i];
        }

        double denom = (double)n * sumXX - sumX * sumX;
        if(MathAbs(denom) < 1e-15)
            return false;

        slope = ((double)n * sumXY - sumX * sumY) / denom;

        // R-squared
        double meanY = sumY / (double)n;
        double ssTot = 0.0;
        double ssRes = 0.0;
        double intercept = (sumY - slope * sumX) / (double)n;

        for(int j = 0; j < n; j++)
        {
            double yPred = slope * x[j] + intercept;
            double devTot = y[j] - meanY;
            double devRes = y[j] - yPred;
            ssTot += devTot * devTot;
            ssRes += devRes * devRes;
        }

        if(ssTot < 1e-15)
            return false;

        rsquared = 1.0 - (ssRes / ssTot);
        if(rsquared < 0.0)
            rsquared = 0.0;
        if(rsquared > 1.0)
            rsquared = 1.0;

        return true;
    }

public:
    // --- Constructor ---
    CHurstEngine(const string symbol = "",
                 const ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT,
                 const int lookbackPeriod = 300,
                 const int minLag = 2,
                 const int maxLag = 128) :
        m_symbol(symbol),
        m_timeframe(timeframe),
        m_lookbackPeriod(MathMax(50, lookbackPeriod)),
        m_minLag(MathMax(2, minLag)),
        m_maxLag(MathMax(m_minLag * 2, maxLag)),
        m_lastLogTime(0),
        m_lastBarTime(0)
    {
    }

    // --- Calculate Hurst exponent using variance-time method ---
    // Returns the Hurst value, or 0.5 on failure (random walk fallback)
    double CalculateHurst(const double &closePrices[], const int dataSize)
    {
        // Warmup guard: need at least maxLag * 2 bars
        int minRequired = m_maxLag * 2;
        if(dataSize < minRequired)
        {
            ThrottledLog(StringFormat("[HURST] WARMUP | need=%d | have=%d | symbol=%s",
                                       minRequired, dataSize, m_symbol));
            return 0.5;
        }

        // Use the most recent 'usable' bars (up to lookbackPeriod)
        int usableBars = MathMin(dataSize, m_lookbackPeriod);
        if(usableBars < minRequired)
        {
            ThrottledLog(StringFormat("[HURST] INSUFFICIENT_LOOKBACK | usable=%d | need=%d | symbol=%s",
                                       usableBars, minRequired, m_symbol));
            return 0.5;
        }

        // Step 1: Compute log prices (indexed 0=most recent)
        double logPrices[];
        ArrayResize(logPrices, usableBars);
        for(int i = 0; i < usableBars; i++)
        {
            if(closePrices[i] <= 0.0)
            {
                ThrottledLog(StringFormat("[HURST] INVALID_PRICE | idx=%d | symbol=%s", i, m_symbol));
                return 0.5;
            }
            logPrices[i] = MathLog(closePrices[i]);
        }

        // Step 2: Build lag list (power-of-2 from minLag to maxLag)
        int lags[];
        int lagCount = BuildLagList(lags);
        if(lagCount < 2)
        {
            ThrottledLog(StringFormat("[HURST] INSUFFICIENT_LAGS | count=%d | symbol=%s", lagCount, m_symbol));
            return 0.5;
        }

        // Step 3: For each lag, compute variance of lagged log-returns
        double logLags[];
        double logVars[];
        ArrayResize(logLags, lagCount);
        ArrayResize(logVars, lagCount);
        int validCount = 0;

        for(int k = 0; k < lagCount; k++)
        {
            double var = ComputeLaggedVariance(logPrices, usableBars, lags[k]);
            if(var <= 0.0 || !MathIsValidNumber(var))
                continue;

            logLags[validCount] = MathLog((double)lags[k]);
            logVars[validCount] = MathLog(var);
            validCount++;
        }

        if(validCount < 2)
        {
            ThrottledLog(StringFormat("[HURST] INSUFFICIENT_VALID_LAGS | valid=%d | symbol=%s", validCount, m_symbol));
            return 0.5;
        }

        // Step 4: OLS regression of log(variance) vs log(lag)
        // Slope / 2 = Hurst exponent
        double slope = 0.0;
        double rsquared = 0.0;
        if(!OlsRegression(logLags, logVars, validCount, slope, rsquared))
        {
            ThrottledLog(StringFormat("[HURST] OLS_FAILED | symbol=%s", m_symbol));
            return 0.5;
        }

        double hurst = slope / 2.0;

        // Sanity bounds: Hurst should be in [0, 1]
        if(!MathIsValidNumber(hurst) || hurst < 0.0 || hurst > 1.0)
        {
            ThrottledLog(StringFormat("[HURST] INVALID_VALUE | H=%.4f | symbol=%s", hurst, m_symbol));
            return 0.5;
        }

        // Store confidence (R-squared from OLS)
        m_snapshot.confidence = rsquared;
        m_snapshot.barCount = usableBars;

        return hurst;
    }

    // --- Classify regime from Hurst value ---
    ENUM_HURST_REGIME GetRegimeClassification(const double hurstValue) const
    {
        if(hurstValue < 0.45)
            return HURST_MEAN_REVERTING;
        if(hurstValue > 0.55)
            return HURST_TRENDING;
        return HURST_RANDOM_WALK;
    }

    // --- Compute strategy weight multipliers from Hurst regime ---
    void GetStrategyWeightMultipliers(const ENUM_HURST_REGIME regime,
                                       double &meanRevWeight,
                                       double &momentumWeight,
                                       double &trendWeight,
                                       double &breakoutWeight) const
    {
        switch(regime)
        {
            case HURST_MEAN_REVERTING:
                meanRevWeight    = 1.5;
                momentumWeight   = 0.5;
                trendWeight      = 0.5;
                breakoutWeight   = 0.8;
                break;

            case HURST_RANDOM_WALK:
                meanRevWeight    = 0.7;
                momentumWeight   = 0.7;
                trendWeight      = 0.7;
                breakoutWeight   = 0.7;
                break;

            case HURST_TRENDING:
                meanRevWeight    = 0.5;
                momentumWeight   = 1.5;
                trendWeight      = 1.5;
                breakoutWeight   = 1.2;
                break;

            default:
                meanRevWeight    = 0.7;
                momentumWeight   = 0.7;
                trendWeight      = 0.7;
                breakoutWeight   = 0.7;
                break;
        }
    }

    // --- Update: called each bar, computes Hurst from close prices ---
    bool Update()
    {
        // Bar-change detection: skip recalc if bar hasn't changed
        datetime currentBarTime = iTime(m_symbol, m_timeframe, 0);
        if(currentBarTime > 0 && currentBarTime == m_lastBarTime && m_snapshot.timestamp > 0)
            return true;

        // Copy close prices (index 0 = most recent)
        double closePrices[];
        ArraySetAsSeries(closePrices, true);
        int copied = CopyClose(m_symbol, m_timeframe, 0, m_lookbackPeriod, closePrices);
        if(copied <= 0)
        {
            ThrottledLog(StringFormat("[HURST] COPY_CLOSE_FAILED | symbol=%s | tf=%s | err=%d",
                                       m_symbol, EnumToString(m_timeframe), GetLastError()));
            return false;
        }

        // Warmup guard
        int minRequired = m_maxLag * 2;
        if(copied < minRequired)
        {
            ThrottledLog(StringFormat("[HURST] WARMUP | need=%d | have=%d | symbol=%s",
                                       minRequired, copied, m_symbol));
            m_snapshot.hurstValue = 0.5;
            m_snapshot.regime = HURST_RANDOM_WALK;
            m_snapshot.confidence = 0.0;
            m_snapshot.barCount = copied;
            m_snapshot.timestamp = TimeCurrent();
            GetStrategyWeightMultipliers(m_snapshot.regime,
                                          m_snapshot.meanRevWeightMult,
                                          m_snapshot.momentumWeightMult,
                                          m_snapshot.trendWeightMult,
                                          m_snapshot.breakoutWeightMult);
            m_lastBarTime = currentBarTime;
            return false;
        }

        // Calculate Hurst
        double hurst = CalculateHurst(closePrices, copied);
        ENUM_HURST_REGIME regime = GetRegimeClassification(hurst);

        // Update snapshot
        m_snapshot.hurstValue = hurst;
        m_snapshot.regime = regime;
        m_snapshot.timestamp = TimeCurrent();
        m_snapshot.barCount = copied;
        GetStrategyWeightMultipliers(regime,
                                      m_snapshot.meanRevWeightMult,
                                      m_snapshot.momentumWeightMult,
                                      m_snapshot.trendWeightMult,
                                      m_snapshot.breakoutWeightMult);

        m_lastBarTime = currentBarTime;

        // Throttled state logging
        ThrottledLog(StringFormat("[HURST] %s | H=%.4f | regime=%s | R2=%.3f | bars=%d | MeanRev=%.1fx | Momentum=%.1fx | Trend=%.1fx | Breakout=%.1fx",
                                   m_symbol,
                                   hurst,
                                   RegimeToString(regime),
                                   m_snapshot.confidence,
                                   copied,
                                   m_snapshot.meanRevWeightMult,
                                   m_snapshot.momentumWeightMult,
                                   m_snapshot.trendWeightMult,
                                   m_snapshot.breakoutWeightMult));

        return true;
    }

    // --- Snapshot accessor ---
    SHurstSnapshot GetSnapshot() const
    {
        return m_snapshot;
    }

    // --- Direct accessors ---
    double GetHurstValue() const          { return m_snapshot.hurstValue; }
    ENUM_HURST_REGIME GetRegime() const   { return m_snapshot.regime; }
    double GetConfidence() const          { return m_snapshot.confidence; }
    int    GetBarCount() const            { return m_snapshot.barCount; }
    double GetMeanRevWeightMult() const   { return m_snapshot.meanRevWeightMult; }
    double GetMomentumWeightMult() const  { return m_snapshot.momentumWeightMult; }
    double GetTrendWeightMult() const     { return m_snapshot.trendWeightMult; }
    double GetBreakoutWeightMult() const  { return m_snapshot.breakoutWeightMult; }

    // --- Warmup check ---
    bool IsWarmedUp() const
    {
        int minRequired = m_maxLag * 2;
        return m_snapshot.barCount >= minRequired && m_snapshot.timestamp > 0;
    }
};

#endif // HURST_ENGINE_MQH
