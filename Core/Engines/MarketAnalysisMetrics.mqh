//+------------------------------------------------------------------+
//| MarketAnalysisMetrics.mqh - Trend / volatility / momentum / ATR  |
//| Extracted verbatim from MarketAnalysis.mqh (no behavior change)  |
//+------------------------------------------------------------------+
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef MARKET_ANALYSIS_METRICS_MQH
#define MARKET_ANALYSIS_METRICS_MQH

#include "MarketAnalysisTypes.mqh"
#include "MarketAnalysisSymbolProfile.mqh"
#include "MarketAnalysisMetricCache.mqh"
#include "MarketAnalysisIndicators.mqh"

//+------------------------------------------------------------------+
//| Computes the market metrics from the indicator context and keeps |
//| the most recently published values. Owns the indicator context   |
//| and the last-valid metric cache by value.                        |
//+------------------------------------------------------------------+
class CMarketAnalysisMetrics
{
private:
    CMarketAnalysisIndicators  m_indicators;
    CMarketAnalysisMetricCache m_cache;

    // Market metrics tracking
    double m_trendStrength;
    double m_volatility;
    double m_momentum;
    double m_volumeProfile;

    // Calculate trend strength using multiple indicators
    double CalculateTrendStrength();

    // Calculate market volatility using multiple metrics
    double CalculateVolatility();

    // Calculate market momentum
    double CalculateMomentum();

public:
    CMarketAnalysisMetrics() :
        m_trendStrength(0.0),
        m_volatility(0.0),
        m_momentum(0.0),
        m_volumeProfile(0.0)
    {
    }

    //--- Indicator lifecycle (delegated to the indicator context)
    void ReleaseAllHandles() { m_indicators.ReleaseAllHandles(); }

    bool InitializeIndicator(int &handle, const string symbolName, const ENUM_TIMEFRAMES period, const string indicatorName,
                             const int param1 = 0, const int param2 = 0, const double param3 = 0, const int param4 = 0)
    {
        return m_indicators.InitializeIndicator(handle, symbolName, period, indicatorName, param1, param2, param3, param4);
    }

    bool InitializeIndicators(const string symbolName, const ENUM_TIMEFRAMES period)
    {
        return m_indicators.InitializeIndicators(symbolName, period, m_cache);
    }

    //--- Indicator context accessors
    string Symbol() const { return m_indicators.Symbol(); }

    //--- Pre-flight validation for regime detection (verbatim guards)
    bool IsRegimeInputReady() const;

    //--- Recompute and publish the three tracked metrics, in order
    void RefreshCurrentMetrics();

    //--- Raw (unguarded) snapshots of the published metrics
    double TrendStrengthValue() const { return m_trendStrength; }
    double VolatilityValue()    const { return m_volatility; }
    double VolumeProfileValue() const { return m_volumeProfile; }

    //--- Guarded public readers
    double GetCurrentVolatility() const;
    double GetCurrentTrendStrength() const;
    double GetMomentum() const { return m_momentum; }

    //--- Current ATR value
    double GetATRValue();
};

//+------------------------------------------------------------------+
//| Calculate trend strength using multiple indicators               |
//+------------------------------------------------------------------+
double CMarketAnalysisMetrics::CalculateTrendStrength()
{
    double trendStrength = 0.0;
    int adxPeriod = 14;
    int ma20Period = 20;
    int ma50Period = 50;
    int ma200Period = 200;
    int priceActionBars = 10;
    bool reuseFallback = false;
    string reuseReason = "";
    int reuseErrorCode = 0;

    // Attempt re-init if handles invalid
    if(!m_indicators.EnsureIndicatorsReady(m_cache))
    {
        if(!m_indicators.IsInWarmup())
            PrintFormat("[WARN] CMarketAnalysis::CalculateTrendStrength - indicators not initialized for %s.", m_indicators.Symbol());
        return 0.0;
    }

    // Use ADX for trend strength (if available - may be skipped for Jump indices)
    if(m_indicators.AdxHandle() != INVALID_HANDLE && BarsCalculated(m_indicators.AdxHandle()) > adxPeriod) {
        double adxValues[];
        ArraySetAsSeries(adxValues, true);
        // Wait for ADX indicator to initialize
        int attempts = 0;
        bool dataReady = false;
        while(attempts < 5 && !dataReady)
        {
            Sleep(10); // Reduced from 50ms to 10ms to minimize blocking
            if(CopyBuffer(m_indicators.AdxHandle(), 0, 0, 3, adxValues) > 0) {
                dataReady = true;
            }
            attempts++;
        }
        if(dataReady) {
            // ADX above 25 indicates trend, above 50 is strong trend
            trendStrength += (adxValues[0] / 50.0) * 0.4; // 40% weight to ADX
        } else {
            int errorCode = GetLastError();
            if(errorCode == 4807 || errorCode == 4806) {
                // [4807 STALE TOLERANCE] Use default if first run, otherwise continue evaluation
                reuseFallback = true;
                reuseReason = "ADX_BUFFER_COPY_FAILED";
                reuseErrorCode = errorCode;
                if(!m_indicators.IsInWarmup()) PrintFormat("[INFO] CMarketAnalysis::CalculateTrendStrength - 4807 stale data bypass for ADX on %s", m_indicators.Symbol());
            } else if(!m_indicators.IsInWarmup()) {
                PrintFormat("[WARN] CMarketAnalysis::CalculateTrendStrength - ADX data not ready for %s. Error: %d", m_indicators.Symbol(), errorCode);
            }
        }
    } else if(m_indicators.AdxHandle() == INVALID_HANDLE && CMarketAnalysisSymbolProfile::RequiresSpecialHandling(m_indicators.Symbol())) {
        // For Jump/Volatility indices without ADX, use increased weight on other indicators
        // This is expected and not an error
    } else {
        // Only warn if ADX should be available but isn't ready (and not in warmup)
        if(!m_indicators.IsInWarmup()) PrintFormat("[WARN] CMarketAnalysis::CalculateTrendStrength - ADX data not ready for %s.", m_indicators.Symbol());
    }

    // Use Moving Average alignment for trend confirmation
    if(m_indicators.Ma20Handle() != INVALID_HANDLE && BarsCalculated(m_indicators.Ma20Handle()) > ma20Period &&
       m_indicators.Ma50Handle() != INVALID_HANDLE && BarsCalculated(m_indicators.Ma50Handle()) > ma50Period &&
       m_indicators.Ma200Handle() != INVALID_HANDLE && BarsCalculated(m_indicators.Ma200Handle()) > ma200Period) {
        double ma20Values[], ma50Values[], ma200Values[];
        ArraySetAsSeries(ma20Values, true);
        ArraySetAsSeries(ma50Values, true);
        ArraySetAsSeries(ma200Values, true);

        if(CopyBuffer(m_indicators.Ma20Handle(), 0, 0, 3, ma20Values) > 0 &&
           CopyBuffer(m_indicators.Ma50Handle(), 0, 0, 3, ma50Values) > 0 &&
           CopyBuffer(m_indicators.Ma200Handle(), 0, 0, 3, ma200Values) > 0) {

            bool uptrend = ma20Values[0] > ma50Values[0] && ma50Values[0] > ma200Values[0];
            bool downtrend = ma20Values[0] < ma50Values[0] && ma50Values[0] < ma200Values[0];

            if(uptrend || downtrend) {
                trendStrength += 0.3; // 30% weight to MA alignment
            }
        } else {
            int errorCode = GetLastError();
            if(errorCode == 4807 || errorCode == 4806) {
                // [4807 STALE TOLERANCE] Maintain last valid trend contribution if sync fails
                reuseFallback = true;
                if(reuseReason == "")
                    reuseReason = "MA_ALIGNMENT_COPY_FAILED";
                reuseErrorCode = errorCode;
                if(!m_indicators.IsInWarmup()) PrintFormat("[INFO] CMarketAnalysis::CalculateTrendStrength - 4807 stale data bypass for MA alignment on %s", m_indicators.Symbol());
            } else if(!m_indicators.IsInWarmup()) {
               PrintFormat("[WARN] CMarketAnalysis::CalculateTrendStrength - MA buffer copy failed for %s. Error: %d", m_indicators.Symbol(), errorCode);
            }
        }
    } else {
        if(!m_indicators.IsInWarmup()) PrintFormat("[WARN] CMarketAnalysis::CalculateTrendStrength - MA data not ready or handles invalid for %s.", m_indicators.Symbol());
    }

    // Use price action analysis (higher highs/lows or lower highs/lows)
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);

    if(CopyHigh(m_indicators.Symbol(), m_indicators.Timeframe(), 0, priceActionBars, high) >= priceActionBars &&
       CopyLow(m_indicators.Symbol(), m_indicators.Timeframe(), 0, priceActionBars, low) >= priceActionBars) {

        // Check for higher highs and higher lows (uptrend)
        bool higherHighs = high[0] > high[2] && high[2] > high[4];
        bool higherLows = low[0] > low[2] && low[2] > low[4];

        // Check for lower highs and lower lows (downtrend)
        bool lowerHighs = high[0] < high[2] && high[2] < high[4];
        bool lowerLows = low[0] < low[2] && low[2] < low[4];

        if((higherHighs && higherLows) || (lowerHighs && lowerLows)) {
            trendStrength += 0.3; // 30% weight to price action
        }
    } else {
        int errorCode = GetLastError();
        if(errorCode == 4807 || errorCode == 4806)
        {
            reuseFallback = true;
            if(reuseReason == "")
                reuseReason = "PRICE_ACTION_COPY_FAILED";
            reuseErrorCode = errorCode;
        }
    }

    // Cap trend strength at 1.0
    trendStrength = MathMin(trendStrength, 1.0);
    if(reuseFallback && m_cache.CanReuseMetric(m_cache.LastValidTrendTime(), m_indicators.Timeframe()) && m_cache.LastValidTrendStrength() > 0.0)
    {
        m_cache.MaybeLogMetricReuse(m_indicators.Symbol(), m_indicators.Timeframe(), "TREND_STRENGTH", reuseReason, reuseErrorCode, m_cache.LastValidTrendTime());
        trendStrength = MathMax(trendStrength, m_cache.LastValidTrendStrength());
    }
    if(MathIsValidNumber(trendStrength) && trendStrength > 0.0)
    {
        m_cache.StoreValidTrend(trendStrength, TimeCurrent());
    }
    return trendStrength;
}

//+------------------------------------------------------------------+
//| Calculate market volatility using multiple metrics               |
//+------------------------------------------------------------------+
double CMarketAnalysisMetrics::CalculateVolatility()
{
    double volatility = 0.0;
    int atrPeriod = 14;
    int bbPeriod = 20;
    bool reuseFallback = false;
    string reuseReason = "";
    int reuseErrorCode = 0;

    // Attempt re-init if handles invalid
    if(!m_indicators.EnsureIndicatorsReady(m_cache))
    {
        if(!m_indicators.IsInWarmup())
            PrintFormat("[WARN] CMarketAnalysis::CalculateVolatility - indicators not initialized for %s.", m_indicators.Symbol());
        return 0.0;
    }

    // Use ATR for base volatility measurement
    if(m_indicators.AtrHandle() != INVALID_HANDLE && BarsCalculated(m_indicators.AtrHandle()) > atrPeriod) {
        double atrValues[];
        ArraySetAsSeries(atrValues, true);
        if(CopyBuffer(m_indicators.AtrHandle(), 0, 0, 3, atrValues) > 0) {
            // Convert ATR to percentage of price
            double currentPriceValue = SymbolInfoDouble(m_indicators.Symbol(), SYMBOL_BID);
            if(currentPriceValue > 0) { // Avoid division by zero
                double atrPercent = atrValues[0] / currentPriceValue * 100.0;
                volatility += (atrPercent / 1.0) * 0.5; // 50% weight to ATR, normalized to 1% as high volatility
                m_cache.StoreValidAtr(atrValues[0], TimeCurrent());
            }
        } else {
            int errorCode = GetLastError();
            if(errorCode == 4807 || errorCode == 4806) {
                // [4807 STALE TOLERANCE] Maintain last valid volatility if sync fails
                reuseFallback = true;
                reuseReason = "ATR_BUFFER_COPY_FAILED";
                reuseErrorCode = errorCode;
                if(!m_indicators.IsInWarmup()) PrintFormat("[INFO] CMarketAnalysis::CalculateVolatility - 4807 stale data bypass for ATR on %s", m_indicators.Symbol());
            } else if(!m_indicators.IsInWarmup()) {
               PrintFormat("[WARN] CMarketAnalysis::CalculateVolatility - ATR buffer copy failed for %s. Error: %d", m_indicators.Symbol(), errorCode);
            }
        }
    } else {
        if(!m_indicators.IsInWarmup()) PrintFormat("[WARN] CMarketAnalysis::CalculateVolatility - ATR data not ready or handle invalid for %s.", m_indicators.Symbol());
    }

    // Use Bollinger Bands width for volatility confirmation
    if(m_indicators.BbHandle() != INVALID_HANDLE && BarsCalculated(m_indicators.BbHandle()) > bbPeriod) {
        double upperValues[], middleValues[], lowerValues[];
        ArraySetAsSeries(upperValues, true);
        ArraySetAsSeries(middleValues, true);
        ArraySetAsSeries(lowerValues, true);

        // BB: 0=main (middle), 1=upper, 2=lower
        if(CopyBuffer(m_indicators.BbHandle(), 1, 0, 3, upperValues) > 0 &&
           CopyBuffer(m_indicators.BbHandle(), 0, 0, 3, middleValues) > 0 &&
           CopyBuffer(m_indicators.BbHandle(), 2, 0, 3, lowerValues) > 0) {

            if(middleValues[0] > 0) { // Avoid division by zero
                double bbWidth = (upperValues[0] - lowerValues[0]) / middleValues[0] * 100.0;
                volatility += (bbWidth / 4.0) * 0.3; // 30% weight to BB width, normalized to 4% as high
            }
        } else {
            int errorCode = GetLastError();
            if(errorCode == 4807 || errorCode == 4806) {
                // [4807 STALE TOLERANCE] Maintain last valid volatility if sync fails
                reuseFallback = true;
                if(reuseReason == "")
                    reuseReason = "BB_BUFFER_COPY_FAILED";
                reuseErrorCode = errorCode;
                if(!m_indicators.IsInWarmup()) PrintFormat("[INFO] CMarketAnalysis::CalculateVolatility - 4807 stale data bypass for BB on %s", m_indicators.Symbol());
            } else if(!m_indicators.IsInWarmup()) {
               PrintFormat("[WARN] CMarketAnalysis::CalculateVolatility - BB buffer copy failed for %s. Error: %d", m_indicators.Symbol(), errorCode);
            }
        }
    } else {
        if(!m_indicators.IsInWarmup()) PrintFormat("[WARN] CMarketAnalysis::CalculateVolatility - Bollinger Bands data not ready or handle invalid for %s.", m_indicators.Symbol());
    }

    // Use recent price range as additional volatility metric
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    int priceRangeBars = 10;

    if(CopyHigh(m_indicators.Symbol(), m_indicators.Timeframe(), 0, priceRangeBars, high) >= priceRangeBars &&
       CopyLow(m_indicators.Symbol(), m_indicators.Timeframe(), 0, priceRangeBars, low) >= priceRangeBars) {

        // Calculate max range over last 10 bars
        double maxHigh = high[ArrayMaximum(high, 0, priceRangeBars)];
        double minLow = low[ArrayMinimum(low, 0, priceRangeBars)];
        if(minLow > 0) { // Avoid division by zero
            double rangePercent = (maxHigh - minLow) / minLow * 100.0;
            volatility += (rangePercent / 2.0) * 0.2; // 20% weight to price range, normalized to 2% as high
        }
    } else {
        int errorCode = GetLastError();
        if(errorCode == 4807 || errorCode == 4806)
        {
            reuseFallback = true;
            if(reuseReason == "")
                reuseReason = "PRICE_RANGE_COPY_FAILED";
            reuseErrorCode = errorCode;
        }
        else if(!m_indicators.IsInWarmup()) PrintFormat("[WARN] CMarketAnalysis::CalculateVolatility - Price range data not available for %s.", m_indicators.Symbol());
    }

    // Cap volatility at 1.0
    volatility = MathMin(volatility, 1.0);
    if(reuseFallback && m_cache.CanReuseMetric(m_cache.LastValidVolatilityTime(), m_indicators.Timeframe()) && m_cache.LastValidVolatility() > 0.0)
    {
        m_cache.MaybeLogMetricReuse(m_indicators.Symbol(), m_indicators.Timeframe(), "VOLATILITY", reuseReason, reuseErrorCode, m_cache.LastValidVolatilityTime());
        volatility = MathMax(volatility, m_cache.LastValidVolatility());
    }
    if(MathIsValidNumber(volatility) && volatility > 0.0)
    {
        m_cache.StoreValidVolatility(volatility, TimeCurrent());
    }
    return volatility;
}

//+------------------------------------------------------------------+
//| Calculate market momentum                                        |
//+------------------------------------------------------------------+
double CMarketAnalysisMetrics::CalculateMomentum()
{
    double momentum = 0.0;
    int rsiPeriod = 14;
    int macdSlowPeriod = 26; // Longest period component of MACD
    int rocPeriod = 5;
    int rocBarsNeeded = rocPeriod + 1; // Need at least rocPeriod + 1 bars for ROC calculation
    bool reuseFallback = false;
    string reuseReason = "";
    int reuseErrorCode = 0;

    // Use RSI for momentum measurement
    int rsiCalculated = BarsCalculated(m_indicators.RsiHandle());
    if(m_indicators.RsiHandle() != INVALID_HANDLE && rsiCalculated >= rsiPeriod) {
        double rsiValues[];
        ArraySetAsSeries(rsiValues, true);
        if(CopyBuffer(m_indicators.RsiHandle(), 0, 0, 1, rsiValues) > 0) { // Only need current RSI value
            // RSI deviation from neutral (50)
            momentum += MathAbs(rsiValues[0] - 50.0) / 50.0 * 0.4; // 40% weight to RSI
        } else {
            int errorCode = GetLastError();
            if(errorCode == 4807 || errorCode == 4806)
            {
                reuseFallback = true;
                reuseReason = "RSI_BUFFER_COPY_FAILED";
                reuseErrorCode = errorCode;
            }
        }
    } else if(m_indicators.RsiHandle() != INVALID_HANDLE) {
        // RSI handle exists but data not ready yet - this is normal during startup
        // Don't spam warnings during initialization
    } else {
        if(!m_indicators.IsInWarmup()) PrintFormat("[WARN] CMarketAnalysis::CalculateMomentum - RSI handle invalid for %s.", m_indicators.Symbol());
    }

    // Use MACD for momentum confirmation
    // MACD Buffers: 0 = Main line, 1 = Signal line
    if(m_indicators.MacdHandle() != INVALID_HANDLE && BarsCalculated(m_indicators.MacdHandle()) >= macdSlowPeriod) {
        double macdValues[], signalValues[];
        ArraySetAsSeries(macdValues, true);
        ArraySetAsSeries(signalValues, true);
        if(CopyBuffer(m_indicators.MacdHandle(), 0, 0, 1, macdValues) > 0 && // Current MACD value
           CopyBuffer(m_indicators.MacdHandle(), 1, 0, 1, signalValues) > 0) { // Current Signal value

            // MACD histogram strength
            double histogram = MathAbs(macdValues[0] - signalValues[0]);
            double price = SymbolInfoDouble(m_indicators.Symbol(), SYMBOL_BID);
            if(price > 0) { // Avoid division by zero
                double histogramPercent = histogram / price * 1000.0; // Scaled for small values
                momentum += MathMin(histogramPercent / 0.5, 1.0) * 0.3; // 30% weight to MACD
            } else {
                 PrintFormat("[WARN] CMarketAnalysis::CalculateMomentum - Could not get SYMBOL_BID for %s to calculate MACD momentum.", m_indicators.Symbol());
            }
        } else {
            int errorCode = GetLastError();
            if(errorCode == 4807 || errorCode == 4806)
            {
                reuseFallback = true;
                if(reuseReason == "")
                    reuseReason = "MACD_BUFFER_COPY_FAILED";
                reuseErrorCode = errorCode;
            }
        }
    } else {
        if(!m_indicators.IsInWarmup()) PrintFormat("[WARN] CMarketAnalysis::CalculateMomentum - MACD data not ready or handle invalid for %s.", m_indicators.Symbol());
    }

    // Use price momentum (rate of change)
    double close[];
    ArraySetAsSeries(close, true);
    if(SeriesInfoInteger(m_indicators.Symbol(), m_indicators.Timeframe(), SERIES_BARS_COUNT) >= rocBarsNeeded) { // Check if enough bars exist on chart
        if(CopyClose(m_indicators.Symbol(), m_indicators.Timeframe(), 0, rocBarsNeeded, close) >= rocBarsNeeded) {
            if(close[rocPeriod] != 0) { // Avoid division by zero for ROC calculation
                double roc = (close[0] - close[rocPeriod]) / close[rocPeriod] * 100.0;
                momentum += MathMin(MathAbs(roc) / 1.0, 1.0) * 0.3; // 30% weight to ROC
            } else {
                PrintFormat("[WARN] CMarketAnalysis::CalculateMomentum - ROC calculation for %s failed due to zero historical price.", m_indicators.Symbol());
            }
        } else {
            int errorCode = GetLastError();
            if(errorCode == 4807 || errorCode == 4806)
            {
                reuseFallback = true;
                if(reuseReason == "")
                    reuseReason = "ROC_COPY_FAILED";
                reuseErrorCode = errorCode;
            }
        }
    } else {
         PrintFormat("[WARN] CMarketAnalysis::CalculateMomentum - Not enough bars for ROC calculation on %s, Period %s. Needed: %d, Available: %d", m_indicators.Symbol(), EnumToString(m_indicators.Timeframe()), rocBarsNeeded, SeriesInfoInteger(m_indicators.Symbol(), m_indicators.Timeframe(), SERIES_BARS_COUNT));
    }

    // Cap momentum at 1.0
    momentum = MathMin(momentum, 1.0);
    if(reuseFallback && m_cache.CanReuseMetric(m_cache.LastValidMomentumTime(), m_indicators.Timeframe()) && m_cache.LastValidMomentum() > 0.0)
    {
        m_cache.MaybeLogMetricReuse(m_indicators.Symbol(), m_indicators.Timeframe(), "MOMENTUM", reuseReason, reuseErrorCode, m_cache.LastValidMomentumTime());
        momentum = MathMax(momentum, m_cache.LastValidMomentum());
    }
    if(MathIsValidNumber(momentum) && momentum > 0.0)
    {
        m_cache.StoreValidMomentum(momentum, TimeCurrent());
    }
    return momentum;
}

//+------------------------------------------------------------------+
//| Pre-flight validation for regime detection                       |
//+------------------------------------------------------------------+
bool CMarketAnalysisMetrics::IsRegimeInputReady() const
{
    // Ensure indicators are initialized for the analysed symbol/period
    // Note: ADX can be INVALID_HANDLE for Jump indices (incompatible symbol type)
    if (m_indicators.Symbol() == "") {
        PrintFormat("[ERROR] CMarketAnalysis::DetectMarketRegime - Symbol not set. Call InitializeIndicators first.");
        return false;
    }

    // Check if at least some core indicators are available
    if (m_indicators.AtrHandle() == INVALID_HANDLE && m_indicators.RsiHandle() == INVALID_HANDLE && m_indicators.Ma20Handle() == INVALID_HANDLE) {
        PrintFormat("[ERROR] CMarketAnalysis::DetectMarketRegime - No indicators initialized for %s. Call InitializeIndicators first.", m_indicators.Symbol());
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Recompute and publish the three tracked metrics, in order        |
//+------------------------------------------------------------------+
void CMarketAnalysisMetrics::RefreshCurrentMetrics()
{
    // Calculate current market metrics
    m_trendStrength = CalculateTrendStrength();
    m_volatility = CalculateVolatility();
    m_momentum = CalculateMomentum();
}

//+------------------------------------------------------------------+
//| Get current market volatility                                    |
//+------------------------------------------------------------------+
double CMarketAnalysisMetrics::GetCurrentVolatility() const
{
    if (m_indicators.Symbol() == "" || m_indicators.AtrHandle() == INVALID_HANDLE) { // Check if indicators were initialized
         PrintFormat("[WARNING] CMarketAnalysis::GetCurrentVolatility - Volatility not available or indicators not initialized for %s. Call InitializeIndicators and DetectMarketRegime first.", m_indicators.Symbol());
         return 0.0; // Default or error value
    }
    return m_volatility; // m_volatility is updated by DetectMarketRegime via CalculateVolatility
}

//+------------------------------------------------------------------+
//| Get current market trend strength                                |
//+------------------------------------------------------------------+
double CMarketAnalysisMetrics::GetCurrentTrendStrength() const
{
    if (m_indicators.Symbol() == "") {
         PrintFormat("[WARNING] CMarketAnalysis::GetCurrentTrendStrength - Symbol not set. Call InitializeIndicators and DetectMarketRegime first.");
         return 0.0; // Default or error value
    }
    return m_trendStrength; // m_trendStrength is updated by DetectMarketRegime via CalculateTrendStrength
}

//+------------------------------------------------------------------+
//| Get current ATR value                                            |
//+------------------------------------------------------------------+
double CMarketAnalysisMetrics::GetATRValue()
{
    if(m_indicators.AtrHandle() == INVALID_HANDLE) return 0.0;

    double atrValues[];
    ArraySetAsSeries(atrValues, true);
    ResetLastError();
    if(CopyBuffer(m_indicators.AtrHandle(), 0, 0, 1, atrValues) > 0 && atrValues[0] > 0.0) {
        m_cache.StoreValidAtr(atrValues[0], TimeCurrent());
        return atrValues[0];
    }
    int errorCode = GetLastError();
    if((errorCode == 4807 || errorCode == 4806) && m_cache.CanReuseMetric(m_cache.LastValidAtrTime(), m_indicators.Timeframe()) && m_cache.LastValidAtrValue() > 0.0)
    {
        m_cache.MaybeLogMetricReuse(m_indicators.Symbol(), m_indicators.Timeframe(), "ATR_VALUE", "ATR_VALUE_COPY_FAILED", errorCode, m_cache.LastValidAtrTime());
        return m_cache.LastValidAtrValue();
    }
    return 0.0;
}

#endif // MARKET_ANALYSIS_METRICS_MQH
