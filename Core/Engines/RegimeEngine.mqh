//+------------------------------------------------------------------+
//| RegimeEngine.mqh                                                 |
//| Deterministic regime + microstructure viability engine           |
//+------------------------------------------------------------------+
#ifndef REGIME_ENGINE_MQH
#define REGIME_ENGINE_MQH

#include "../Utils/Enums.mqh"

enum ENUM_REGIME_STATE
{
    REGIME_TREND = 0,
    REGIME_RANGE = 1,
    REGIME_BREAKOUT = 2,
    REGIME_CHAOS = 3
};

// ENHANCEMENT: Multi-Dimensional Regime Classification (Batch 93 - Week 5)
enum ENUM_DETAILED_REGIME
{
    // Trend regimes
    DETAILED_REGIME_STRONG_UPTREND = 0,
    DETAILED_REGIME_WEAK_UPTREND = 1,
    DETAILED_REGIME_STRONG_DOWNTREND = 2,
    DETAILED_REGIME_WEAK_DOWNTREND = 3,
    
    // Range regimes
    DETAILED_REGIME_HIGH_VOL_RANGE = 4,
    DETAILED_REGIME_LOW_VOL_RANGE = 5,
    
    // Transition regimes
    DETAILED_REGIME_TRANSITION_UP = 6,
    DETAILED_REGIME_TRANSITION_DOWN = 7,
    
    // Extreme regimes
    DETAILED_REGIME_CHAOS = 8
};

struct SRegimeSnapshot
{
    bool valid;
    string readinessClass;
    bool reuseActive;
    int stalenessSeconds;
    ENUM_REGIME_STATE state;
    ENUM_REGIME_STATE confirmedState;
    double regimeConfidence;
    int regimeStabilityBars;
    bool compression;
    bool spreadShock;
    bool spreadShockCooldownActive;
    bool lateEntryOutlier;
    double atrValue;
    double bbWidth;
    double bbWidthAtrRatio;
    double spreadPrice;
    double spreadBaseline;
    double spreadToAtrRatio;
    double rangeZScore;
    datetime timestamp;
    
    // ENHANCEMENT: Detailed Regime Classification (Batch 93 - Week 5)
    ENUM_DETAILED_REGIME detailedRegime;
    double trendStrength;           // ADX value or similar metric
    double volatilityPercentile;    // Current vol vs historical (0-1)
    
    // ENHANCEMENT: Strategy-Specific Weight Multipliers (Batch 93 - Week 5)
    double momentumWeightMult;      // Momentum strategy multiplier
    double trendWeightMult;         // Trend strategy multiplier
    double meanRevWeightMult;       // Mean Reversion strategy multiplier
    double breakoutWeightMult;      // Volatility Breakout strategy multiplier
    double ictWeightMult;           // ICT strategy multiplier

    SRegimeSnapshot() :
        valid(false),
        readinessClass("WARMUP"),
        reuseActive(false),
        stalenessSeconds(0),
        state(REGIME_RANGE),
        confirmedState(REGIME_RANGE),
        regimeConfidence(0.0),
        regimeStabilityBars(0),
        compression(false),
        spreadShock(false),
        spreadShockCooldownActive(false),
        lateEntryOutlier(false),
        atrValue(0.0),
        bbWidth(0.0),
        bbWidthAtrRatio(0.0),
        spreadPrice(0.0),
        spreadBaseline(0.0),
        spreadToAtrRatio(0.0),
        rangeZScore(0.0),
        timestamp(0),
        detailedRegime(DETAILED_REGIME_LOW_VOL_RANGE),
        trendStrength(0.0),
        volatilityPercentile(0.0),
        momentumWeightMult(1.0),
        trendWeightMult(1.0),
        meanRevWeightMult(1.0),
        breakoutWeightMult(1.0),
        ictWeightMult(1.0)
    {
    }
};

class CRegimeEngine
{
private:
    int m_atrPeriod;
    int m_bbPeriod;
    double m_bbDeviation;
    int m_zScoreWindow;
    int m_spreadWindow;
    double m_spreadShockMultiplier;
    int m_spreadShockCooldownSeconds;
    double m_maxSpreadToAtrRatio;
    double m_lateEntryZScoreLimit;
    double m_compressionRatioThreshold;
    double m_breakoutZScoreThreshold;

    int m_atrHandle;
    int m_bbHandle;
    int m_adxHandle;  // ENHANCEMENT: ADX for trend strength (Batch 93 - Week 5)
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;

    double m_spreadSamples[];
    int m_spreadSampleCount;
    int m_spreadSampleCursor;

    datetime m_lastSpreadShockTime;
    datetime m_lastFaultLogTime;
    datetime m_lastStateLogTime;
    ENUM_REGIME_STATE m_lastLoggedState;

    SRegimeSnapshot m_lastSnapshot;
    int m_consecutiveDataFaults;
    datetime m_lastReuseLogTime;
    int m_snapshotReuseTtlSeconds;

    void ResetHandles()
    {
        if(m_atrHandle != INVALID_HANDLE)
        {
            IndicatorRelease(m_atrHandle);
            m_atrHandle = INVALID_HANDLE;
        }
        if(m_bbHandle != INVALID_HANDLE)
        {
            IndicatorRelease(m_bbHandle);
            m_bbHandle = INVALID_HANDLE;
        }
        // ENHANCEMENT: Release ADX handle (Batch 93 - Week 5)
        if(m_adxHandle != INVALID_HANDLE)
        {
            IndicatorRelease(m_adxHandle);
            m_adxHandle = INVALID_HANDLE;
        }
    }

    int GetSnapshotReuseWindowSeconds(const ENUM_TIMEFRAMES timeframe) const
    {
        int barSeconds = PeriodSeconds(timeframe);
        if(barSeconds <= 0)
            barSeconds = 60;

        // Allow reuse for up to 3 bars, with minimum 60 seconds and maximum 1 hour
        int boundedBarWindow = MathMax(60, MathMin(3600, barSeconds * 3));
        return MathMin(boundedBarWindow, MathMax(10, m_snapshotReuseTtlSeconds));
    }

    bool TryReuseRecentSnapshot(const string symbol,
                                const ENUM_TIMEFRAMES timeframe,
                                const string reasonTag,
                                const int errorCode)
    {
        if(!m_lastSnapshot.valid || m_symbol != symbol || m_timeframe != timeframe || m_lastSnapshot.timestamp <= 0)
            return false;

        int snapshotAgeSeconds = (int)MathMax(0, TimeCurrent() - m_lastSnapshot.timestamp);
        if(snapshotAgeSeconds > GetSnapshotReuseWindowSeconds(timeframe))
            return false;

        datetime nowTime = TimeCurrent();
        if(m_lastReuseLogTime == 0 || (nowTime - m_lastReuseLogTime) >= 30)
        {
            PrintFormat("[REGIME-STATE] REUSE_LAST_VALID | symbol=%s | timeframe=%s | reason=%s | age=%ds | err=%d",
                        symbol,
                        EnumToString(timeframe),
                        reasonTag,
                        snapshotAgeSeconds,
                        errorCode);
            m_lastReuseLogTime = nowTime;
        }

        m_lastSnapshot.reuseActive = true;
        m_lastSnapshot.stalenessSeconds = snapshotAgeSeconds;
        m_lastSnapshot.readinessClass = "REUSED_SNAPSHOT";

        return true;
    }

    void NoteDataFault(const string symbol,
                       const ENUM_TIMEFRAMES timeframe,
                       const string tag,
                       const int errorCode)
    {
        m_consecutiveDataFaults++;
        LogFault(tag, errorCode);

        if(m_consecutiveDataFaults >= 3)
        {
            ResetHandles();
            PrintFormat("[REGIME-STATE] HANDLE_RESET | symbol=%s | timeframe=%s | reason=%s | faults=%d",
                        symbol,
                        EnumToString(timeframe),
                        tag,
                        m_consecutiveDataFaults);
            m_consecutiveDataFaults = 0;
        }
    }

    bool BuildFallbackIndicators(const string symbol,
                                 const ENUM_TIMEFRAMES timeframe,
                                 double &atrValue,
                                 double &bbUpperValue,
                                 double &bbLowerValue) const
    {
        atrValue = 0.0;
        bbUpperValue = 0.0;
        bbLowerValue = 0.0;

        int requiredBars = MathMax(m_bbPeriod + 3, m_atrPeriod + 3);
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        int copied = CopyRates(symbol, timeframe, 0, requiredBars, rates);
        if(copied < requiredBars)
            return false;

        int atrWindow = MathMin(m_atrPeriod, copied - 2);
        if(atrWindow <= 0)
            return false;

        double atrSum = 0.0;
        for(int i = 0; i < atrWindow; i++)
        {
            double rangeHighLow = rates[i].high - rates[i].low;
            double rangeHighClose = MathAbs(rates[i].high - rates[i + 1].close);
            double rangeLowClose = MathAbs(rates[i].low - rates[i + 1].close);
            atrSum += MathMax(rangeHighLow, MathMax(rangeHighClose, rangeLowClose));
        }
        atrValue = atrSum / (double)atrWindow;

        int bbWindow = MathMin(m_bbPeriod, copied);
        if(bbWindow <= 1)
            return false;

        double mean = 0.0;
        for(int j = 0; j < bbWindow; j++)
            mean += rates[j].close;
        mean /= (double)bbWindow;

        double variance = 0.0;
        for(int k = 0; k < bbWindow; k++)
        {
            double diff = rates[k].close - mean;
            variance += diff * diff;
        }
        variance /= (double)bbWindow;
        double stdDev = MathSqrt(MathMax(0.0, variance));
        bbUpperValue = mean + (m_bbDeviation * stdDev);
        bbLowerValue = mean - (m_bbDeviation * stdDev);

        return (MathIsValidNumber(atrValue) && atrValue > 0.0 &&
                MathIsValidNumber(bbUpperValue) &&
                MathIsValidNumber(bbLowerValue));
    }

    bool EnsureHandles(const string symbol, ENUM_TIMEFRAMES timeframe)
    {
        bool handlesReady = (m_atrHandle != INVALID_HANDLE && m_bbHandle != INVALID_HANDLE && m_adxHandle != INVALID_HANDLE);
        bool contextMatches = (m_symbol == symbol && m_timeframe == timeframe);
        if(handlesReady && contextMatches)
            return true;

        if(!contextMatches)
        {
            m_lastSnapshot.valid = false;
            m_consecutiveDataFaults = 0;
            m_lastReuseLogTime = 0;
            m_lastSpreadShockTime = 0;
            m_lastStateLogTime = 0;
            m_lastLoggedState = REGIME_RANGE;
        }

        ResetHandles();

        m_symbol = symbol;
        m_timeframe = timeframe;
        m_atrHandle = iATR(symbol, timeframe, m_atrPeriod);
        m_bbHandle = iBands(symbol, timeframe, m_bbPeriod, 0, m_bbDeviation, PRICE_CLOSE);
        // ENHANCEMENT: Create ADX handle for trend strength (Batch 93 - Week 5)
        m_adxHandle = iADX(symbol, timeframe, 14);
        m_spreadSampleCount = 0;
        m_spreadSampleCursor = 0;
        ArrayResize(m_spreadSamples, m_spreadWindow);

        return (m_atrHandle != INVALID_HANDLE && m_bbHandle != INVALID_HANDLE && m_adxHandle != INVALID_HANDLE);
    }

    double ComputeSpreadBaseline() const
    {
        if(m_spreadSampleCount <= 0)
            return 0.0;

        double sum = 0.0;
        for(int i = 0; i < m_spreadSampleCount; i++)
            sum += m_spreadSamples[i];

        return sum / (double)m_spreadSampleCount;
    }

    bool ComputeRangeZScore(double &zScoreOut)
    {
        zScoreOut = 0.0;
        int window = MathMax(10, m_zScoreWindow);
        double closes[];
        ArraySetAsSeries(closes, true);
        int copied = CopyClose(m_symbol, m_timeframe, 0, window, closes);
        if(copied < window)
            return false;

        double mean = 0.0;
        for(int i = 0; i < window; i++)
            mean += closes[i];
        mean /= (double)window;

        double variance = 0.0;
        for(int j = 0; j < window; j++)
        {
            double diff = closes[j] - mean;
            variance += (diff * diff);
        }

        variance /= (double)window;
        double stdev = MathSqrt(variance);
        if(stdev <= 0.0)
            return false;

        zScoreOut = (closes[0] - mean) / stdev;
        return MathIsValidNumber(zScoreOut);
    }

    string RegimeToString(const ENUM_REGIME_STATE state) const
    {
        switch(state)
        {
            case REGIME_TREND: return "TREND";
            case REGIME_RANGE: return "RANGE";
            case REGIME_BREAKOUT: return "BREAKOUT";
            case REGIME_CHAOS: return "CHAOS";
            default: return "RANGE";
        }
    }

    void LogFault(const string tag, const int errorCode)
    {
        datetime nowTime = TimeCurrent();
        if((nowTime - m_lastFaultLogTime) < 30)
            return;

        PrintFormat("[REGIME-STATE] %s | symbol=%s | timeframe=%s | err=%d",
                    tag, m_symbol, EnumToString(m_timeframe), errorCode);
        m_lastFaultLogTime = nowTime;
    }

public:
    CRegimeEngine() :
        m_atrPeriod(14),
        m_bbPeriod(20),
        m_bbDeviation(2.0),
        m_zScoreWindow(30),
        m_spreadWindow(120),
        m_spreadShockMultiplier(2.5),
        m_spreadShockCooldownSeconds(30),
        m_maxSpreadToAtrRatio(0.25),
        m_lateEntryZScoreLimit(2.50),
        m_compressionRatioThreshold(3.0),
        m_breakoutZScoreThreshold(1.8),
        m_atrHandle(INVALID_HANDLE),
        m_bbHandle(INVALID_HANDLE),
        m_symbol(""),
        m_timeframe(PERIOD_CURRENT),
        m_spreadSampleCount(0),
        m_spreadSampleCursor(0),
        m_lastSpreadShockTime(0),
        m_lastFaultLogTime(0),
        m_lastStateLogTime(0),
        m_lastLoggedState(REGIME_RANGE),
        m_consecutiveDataFaults(0),
        m_lastReuseLogTime(0),
        m_snapshotReuseTtlSeconds(60)
    {
        ArrayResize(m_spreadSamples, 0);
    }

    ~CRegimeEngine()
    {
        ResetHandles();
    }

    bool Initialize(const int atrPeriod = 14,
                    const int bbPeriod = 20,
                    const double bbDeviation = 2.0,
                    const int zScoreWindow = 30,
                    const int spreadWindow = 120)
    {
        m_atrPeriod = MathMax(5, atrPeriod);
        m_bbPeriod = MathMax(10, bbPeriod);
        m_bbDeviation = MathMax(1.0, bbDeviation);
        m_zScoreWindow = MathMax(10, zScoreWindow);
        m_spreadWindow = MathMax(20, spreadWindow);
        ArrayResize(m_spreadSamples, m_spreadWindow);
        m_spreadSampleCount = 0;
        m_spreadSampleCursor = 0;
        return true;
    }

    void ConfigureCostLimits(const double maxSpreadToAtrRatio,
                             const int spreadShockCooldownSeconds,
                             const double lateEntryZScoreLimit)
    {
        m_maxSpreadToAtrRatio = MathMax(0.01, maxSpreadToAtrRatio);
        m_spreadShockCooldownSeconds = MathMax(5, spreadShockCooldownSeconds);
        m_lateEntryZScoreLimit = MathMax(0.5, lateEntryZScoreLimit);
    }

    void SetSnapshotReuseTtlSeconds(const int seconds)
    {
        m_snapshotReuseTtlSeconds = MathMax(10, seconds);
    }

    bool Update(const string symbol, ENUM_TIMEFRAMES timeframe)
    {
        double atrValue = 0.0;
        double bbUpperValue = 0.0;
        double bbLowerValue = 0.0;
        bool usedFallback = false;

        if(!EnsureHandles(symbol, timeframe))
        {
            int handleErr = GetLastError();
            if(!BuildFallbackIndicators(symbol, timeframe, atrValue, bbUpperValue, bbLowerValue))
            {
                NoteDataFault(symbol, timeframe, "HANDLE_INIT_FAILED", handleErr);
                return TryReuseRecentSnapshot(symbol, timeframe, "HANDLE_INIT_FAILED", handleErr);
            }
            usedFallback = true;
        }

        int minBars = MathMax(m_bbPeriod + 5, m_atrPeriod + 5);
        int availableBars = Bars(symbol, timeframe);
        int calculatedBarsBB = BarsCalculated(m_bbHandle);
        int calculatedBarsATR = BarsCalculated(m_atrHandle);
        
        if(!usedFallback &&
           (availableBars < minBars ||
            calculatedBarsBB < minBars ||
            calculatedBarsATR < minBars))
        {
            m_lastSnapshot.readinessClass = "WARMUP";
            m_lastSnapshot.reuseActive = false;
            m_lastSnapshot.stalenessSeconds = 0;
            if(!BuildFallbackIndicators(symbol, timeframe, atrValue, bbUpperValue, bbLowerValue))
                return TryReuseRecentSnapshot(symbol, timeframe, "WARMUP", 0);
            usedFallback = true;
        }

        if(!usedFallback)
        {
            ResetLastError();

            // HIGH FIX: Validate handles are valid before attempting copy
            if(m_atrHandle == INVALID_HANDLE || m_bbHandle == INVALID_HANDLE)
            {
                if(!BuildFallbackIndicators(symbol, timeframe, atrValue, bbUpperValue, bbLowerValue))
                {
                    NoteDataFault(symbol, timeframe, "INVALID_HANDLE", 0);
                    return TryReuseRecentSnapshot(symbol, timeframe, "INVALID_HANDLE", 0);
                }
                usedFallback = true;
            }

            if(!usedFallback)
            {
                double atr[1];
                double bbUpper[1];
                double bbLower[1];
                int atrRet = CopyBuffer(m_atrHandle, 0, 0, 1, atr);
                int upperRet = CopyBuffer(m_bbHandle, 1, 0, 1, bbUpper);
                int lowerRet = CopyBuffer(m_bbHandle, 2, 0, 1, bbLower);
                int copyErr = GetLastError();

                if(atrRet <= 0)
                {
                    if(!BuildFallbackIndicators(symbol, timeframe, atrValue, bbUpperValue, bbLowerValue))
                    {
                        NoteDataFault(symbol, timeframe, "ATR_BUFFER_COPY_FAILED", copyErr);
                        return TryReuseRecentSnapshot(symbol, timeframe, "ATR_BUFFER_COPY_FAILED", copyErr);
                    }
                    usedFallback = true;
                }
                else if(upperRet <= 0 || lowerRet <= 0)
                {
                    if(!BuildFallbackIndicators(symbol, timeframe, atrValue, bbUpperValue, bbLowerValue))
                    {
                        NoteDataFault(symbol, timeframe, "BB_BUFFER_COPY_FAILED", copyErr);
                        return TryReuseRecentSnapshot(symbol, timeframe, "BB_BUFFER_COPY_FAILED", copyErr);
                    }
                    usedFallback = true;
                }
                else if(atr[0] <= 0.0)
                {
                    if(!BuildFallbackIndicators(symbol, timeframe, atrValue, bbUpperValue, bbLowerValue))
                    {
                        NoteDataFault(symbol, timeframe, "INVALID_ATR_VALUE", 0);
                        return TryReuseRecentSnapshot(symbol, timeframe, "INVALID_ATR_VALUE", 0);
                    }
                    usedFallback = true;
                }
                else
                {
                    atrValue = atr[0];
                    bbUpperValue = bbUpper[0];
                    bbLowerValue = bbLower[0];
                }
            }
        }

        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(point <= 0.0)
            point = 0.00001;

        double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
        double spreadPrice = 0.0;
        if(ask > 0.0 && bid > 0.0 && ask >= bid)
            spreadPrice = ask - bid;
        else
            spreadPrice = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD) * point;

        if(!MathIsValidNumber(spreadPrice) || spreadPrice < 0.0)
            spreadPrice = 0.0;

        if(m_spreadWindow > 0)
        {
            m_spreadSamples[m_spreadSampleCursor] = spreadPrice;
            m_spreadSampleCursor = (m_spreadSampleCursor + 1) % m_spreadWindow;
            if(m_spreadSampleCount < m_spreadWindow)
                m_spreadSampleCount++;
        }

        double spreadBaseline = ComputeSpreadBaseline();
        bool spreadShock = false;
        if(spreadBaseline > 0.0 && spreadPrice > (spreadBaseline * m_spreadShockMultiplier))
        {
            spreadShock = true;
            m_lastSpreadShockTime = TimeCurrent();
        }

        bool cooldownActive = false;
        if(m_lastSpreadShockTime > 0)
            cooldownActive = ((TimeCurrent() - m_lastSpreadShockTime) <= m_spreadShockCooldownSeconds);

        double bbWidth = MathMax(0.0, bbUpperValue - bbLowerValue);
        double bbWidthAtrRatio = (atrValue > 0.0) ? (bbWidth / atrValue) : 0.0;
        bool compression = (bbWidthAtrRatio > 0.0 && bbWidthAtrRatio <= m_compressionRatioThreshold);

        double zScore = 0.0;
        if(!ComputeRangeZScore(zScore))
            zScore = 0.0;

        bool lateEntryOutlier = (MathAbs(zScore) >= m_lateEntryZScoreLimit);
        double spreadToAtr = (atrValue > 0.0) ? (spreadPrice / atrValue) : 0.0;

        ENUM_REGIME_STATE state = REGIME_TREND;
        double regimeConfidence = 0.5;
        if(cooldownActive || spreadToAtr > (m_maxSpreadToAtrRatio * 1.5))
        {
            state = REGIME_CHAOS;
            regimeConfidence = 0.9;
        }
        else if(MathAbs(zScore) >= m_breakoutZScoreThreshold && !compression)
        {
            state = REGIME_BREAKOUT;
            regimeConfidence = 0.7 + MathMin(0.3, (MathAbs(zScore) - m_breakoutZScoreThreshold) * 0.2);
        }
        else if(compression)
        {
            state = REGIME_RANGE;
            regimeConfidence = 0.6 + MathMin(0.3, (m_compressionRatioThreshold - bbWidthAtrRatio) * 0.1);
        }
        else
        {
            state = REGIME_TREND;
            regimeConfidence = 0.5 + MathMin(0.3, bbWidthAtrRatio * 0.1);
        }

        int stabilityBars = 1;
        if(state == m_lastSnapshot.state && m_lastSnapshot.regimeStabilityBars > 0)
            stabilityBars = m_lastSnapshot.regimeStabilityBars + 1;
        m_consecutiveDataFaults = 0;
        m_lastSnapshot.valid = true;
        m_lastSnapshot.readinessClass = usedFallback ? "FALLBACK_RATES" : "HEALTHY";
        m_lastSnapshot.reuseActive = false;
        m_lastSnapshot.stalenessSeconds = 0;
        m_lastSnapshot.state = state;
        m_lastSnapshot.regimeConfidence = regimeConfidence;
        m_lastSnapshot.regimeStabilityBars = stabilityBars;
        if(stabilityBars >= 3)
            m_lastSnapshot.confirmedState = state;
        else
            m_lastSnapshot.confirmedState = m_lastSnapshot.confirmedState;
        m_lastSnapshot.compression = compression;
        m_lastSnapshot.spreadShock = spreadShock;
        m_lastSnapshot.spreadShockCooldownActive = cooldownActive;
        m_lastSnapshot.lateEntryOutlier = lateEntryOutlier;
        m_lastSnapshot.atrValue = atrValue;
        m_lastSnapshot.bbWidth = bbWidth;
        m_lastSnapshot.bbWidthAtrRatio = bbWidthAtrRatio;
        m_lastSnapshot.spreadPrice = spreadPrice;
        m_lastSnapshot.spreadBaseline = spreadBaseline;
        m_lastSnapshot.spreadToAtrRatio = spreadToAtr;
        m_lastSnapshot.rangeZScore = zScore;
        m_lastSnapshot.timestamp = TimeCurrent();
        
        // ENHANCEMENT: Calculate detailed regime and weight multipliers (Batch 93 - Week 5)
        double adxBuffer[1];
        double adxValue = 0.0;
        if(m_adxHandle != INVALID_HANDLE && CopyBuffer(m_adxHandle, 0, 0, 1, adxBuffer) == 1)
            adxValue = adxBuffer[0];
        
        m_lastSnapshot.trendStrength = adxValue;
        m_lastSnapshot.detailedRegime = CalculateDetailedRegime(adxValue, zScore, bbWidthAtrRatio, compression);
        
        CalculateStrategyWeightMultipliers(
            m_lastSnapshot.detailedRegime,
            m_lastSnapshot.momentumWeightMult,
            m_lastSnapshot.trendWeightMult,
            m_lastSnapshot.meanRevWeightMult,
            m_lastSnapshot.breakoutWeightMult,
            m_lastSnapshot.ictWeightMult
        );
        
        datetime now = TimeCurrent();
        
        // Log detailed regime with weight multipliers
        if(m_lastStateLogTime == 0 || (now - m_lastStateLogTime) >= 60)
        {
            PrintFormat("[REGIME-DETAILED] %s | ADX=%.1f | Momentum=%.1fx | Trend=%.1fx | MeanRev=%.1fx | Breakout=%.1fx | ICT=%.1fx",
                       DetailedRegimeToString(m_lastSnapshot.detailedRegime),
                       adxValue,
                       m_lastSnapshot.momentumWeightMult,
                       m_lastSnapshot.trendWeightMult,
                       m_lastSnapshot.meanRevWeightMult,
                       m_lastSnapshot.breakoutWeightMult,
                       m_lastSnapshot.ictWeightMult);
        }

        if(state != m_lastLoggedState || m_lastStateLogTime == 0 || (now - m_lastStateLogTime) >= 60)
        {
            PrintFormat("[REGIME-STATE] %s | tf=%s | state=%s | confirmed=%s | conf=%.2f | stable_bars=%d | compression=%s | spread_shock=%s | cooldown=%s | spread_atr=%.4f | z=%.3f | bb_atr=%.2f",
                        symbol,
                        EnumToString(timeframe),
                        RegimeToString(state),
                        RegimeToString(m_lastSnapshot.confirmedState),
                        regimeConfidence,
                        stabilityBars,
                        compression ? "true" : "false",
                        spreadShock ? "true" : "false",
                        cooldownActive ? "true" : "false",
                        spreadToAtr,
                        zScore,
                        bbWidthAtrRatio);
            m_lastLoggedState = state;
            m_lastStateLogTime = now;
        }

        if(usedFallback && (m_lastFaultLogTime == 0 || (now - m_lastFaultLogTime) >= 30))
        {
            PrintFormat("[REGIME-STATE] FALLBACK_RATES | symbol=%s | timeframe=%s | atr=%.5f | bb_width=%.5f",
                        symbol,
                        EnumToString(timeframe),
                        m_lastSnapshot.atrValue,
                        m_lastSnapshot.bbWidth);
            m_lastFaultLogTime = now;
        }

        return true;
    }
    
    // ENHANCEMENT: Convert detailed regime to string (Batch 93 - Week 5)
    string DetailedRegimeToString(ENUM_DETAILED_REGIME regime)
    {
        switch(regime)
        {
            case DETAILED_REGIME_STRONG_UPTREND: return "STRONG_UPTREND";
            case DETAILED_REGIME_WEAK_UPTREND: return "WEAK_UPTREND";
            case DETAILED_REGIME_STRONG_DOWNTREND: return "STRONG_DOWNTREND";
            case DETAILED_REGIME_WEAK_DOWNTREND: return "WEAK_DOWNTREND";
            case DETAILED_REGIME_HIGH_VOL_RANGE: return "HIGH_VOL_RANGE";
            case DETAILED_REGIME_LOW_VOL_RANGE: return "LOW_VOL_RANGE";
            case DETAILED_REGIME_TRANSITION_UP: return "TRANSITION_UP";
            case DETAILED_REGIME_TRANSITION_DOWN: return "TRANSITION_DOWN";
            case DETAILED_REGIME_CHAOS: return "CHAOS";
            default: return "UNKNOWN";
        }
    }
    
    // ENHANCEMENT: Calculate Detailed Regime Classification (Batch 93 - Week 5)
    ENUM_DETAILED_REGIME CalculateDetailedRegime(double adxValue, double zScore, 
                                                  double bbWidthAtrRatio, bool compression)
    {
        // Strong trend: ADX > 30
        if(adxValue > 30.0)
        {
            if(zScore > 1.0) return DETAILED_REGIME_STRONG_UPTREND;
            if(zScore < -1.0) return DETAILED_REGIME_STRONG_DOWNTREND;
            return DETAILED_REGIME_STRONG_UPTREND; // Default to up if unclear
        }
        
        // Weak trend: ADX 20-30
        if(adxValue > 20.0)
        {
            if(zScore > 0.5) return DETAILED_REGIME_WEAK_UPTREND;
            if(zScore < -0.5) return DETAILED_REGIME_WEAK_DOWNTREND;
            return DETAILED_REGIME_WEAK_UPTREND;
        }
        
        // Range or transition
        if(compression)
        {
            if(bbWidthAtrRatio < 1.5) return DETAILED_REGIME_LOW_VOL_RANGE;
            return DETAILED_REGIME_HIGH_VOL_RANGE;
        }
        
        // Transition detection
        if(MathAbs(zScore) > 1.5 && adxValue < 25.0)
        {
            if(zScore > 0) return DETAILED_REGIME_TRANSITION_UP;
            return DETAILED_REGIME_TRANSITION_DOWN;
        }
        
        return DETAILED_REGIME_CHAOS;
    }
    
    // ENHANCEMENT: Calculate Strategy-Specific Weight Multipliers (Batch 93 - Week 5)
    void CalculateStrategyWeightMultipliers(ENUM_DETAILED_REGIME regime, 
                                             double &momentumMult,
                                             double &trendMult,
                                             double &meanRevMult,
                                             double &breakoutMult,
                                             double &ictMult)
    {
        switch(regime)
        {
            case DETAILED_REGIME_STRONG_UPTREND:
            case DETAILED_REGIME_STRONG_DOWNTREND:
                momentumMult = 1.5; trendMult = 2.0; meanRevMult = 0.3; breakoutMult = 1.2; ictMult = 1.8;
                break;
                
            case DETAILED_REGIME_WEAK_UPTREND:
            case DETAILED_REGIME_WEAK_DOWNTREND:
                momentumMult = 1.2; trendMult = 1.3; meanRevMult = 0.6; breakoutMult = 0.8; ictMult = 1.0;
                break;
                
            case DETAILED_REGIME_HIGH_VOL_RANGE:
                momentumMult = 0.8; trendMult = 0.5; meanRevMult = 1.8; breakoutMult = 1.5; ictMult = 0.7;
                break;
                
            case DETAILED_REGIME_LOW_VOL_RANGE:
                momentumMult = 0.6; trendMult = 0.4; meanRevMult = 2.0; breakoutMult = 0.5; ictMult = 0.6;
                break;
                
            case DETAILED_REGIME_TRANSITION_UP:
            case DETAILED_REGIME_TRANSITION_DOWN:
                momentumMult = 0.9; trendMult = 0.7; meanRevMult = 0.9; breakoutMult = 1.3; ictMult = 0.8;
                break;
                
            case DETAILED_REGIME_CHAOS:
                momentumMult = 0.2; trendMult = 0.2; meanRevMult = 0.2; breakoutMult = 0.2; ictMult = 0.2;
                break;
                
            default:
                momentumMult = 1.0; trendMult = 1.0; meanRevMult = 1.0; breakoutMult = 1.0; ictMult = 1.0;
                break;
        }
    }

    SRegimeSnapshot GetSnapshot() const
    {
        return m_lastSnapshot;
    }

    // Batch 100: Apply Hurst exponent weight multipliers on top of regime multipliers
    // This modifies the snapshot's weight multipliers in-place by multiplying
    // regime-based weights with Hurst-based persistence weights
    void ApplyHurstWeightModifiers(double hurstMeanRevMult,
                                    double hurstMomentumMult,
                                    double hurstTrendMult,
                                    double hurstBreakoutMult)
    {
        m_lastSnapshot.meanRevWeightMult *= hurstMeanRevMult;
        m_lastSnapshot.momentumWeightMult *= hurstMomentumMult;
        m_lastSnapshot.trendWeightMult *= hurstTrendMult;
        m_lastSnapshot.breakoutWeightMult *= hurstBreakoutMult;
        // ICT weight is not modified by Hurst (ICT has its own regime logic)
    }

    string GetStateTag() const
    {
        return RegimeToString(m_lastSnapshot.state);
    }

    double GetMaxSpreadToAtrRatio() const { return m_maxSpreadToAtrRatio; }
    double GetLateEntryZScoreLimit() const { return m_lateEntryZScoreLimit; }
    ENUM_REGIME_STATE GetConfirmedState() const { return m_lastSnapshot.confirmedState; }
    double GetRegimeConfidence() const { return m_lastSnapshot.regimeConfidence; }
    int GetRegimeStabilityBars() const { return m_lastSnapshot.regimeStabilityBars; }
};

#endif // REGIME_ENGINE_MQH
