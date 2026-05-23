//+------------------------------------------------------------------+
//| Enhanced Market Analysis Module                                  |
//+------------------------------------------------------------------+

#ifndef __MARKET_ANALYSIS_MQH__
#define __MARKET_ANALYSIS_MQH__

// Include Enums first to ensure all enums are defined
#include "../Utils/Enums.mqh"

// Include required MQL5 headers
#include <Indicators/Indicator.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Arrays/ArrayDouble.mqh>
#include <Object.mqh>
#include <Arrays/ArrayObj.mqh>

// Forward declarations

class CMarketAnalysis {
private:
    // Market regime detection variables
    ENUM_MARKET_REGIME m_currentRegime;
    ENUM_MARKET_REGIME m_previousRegime;
    datetime m_lastRegimeChange;
    int m_regimeStability; // Counter for regime stability
    
	    // Market metrics tracking
	    double m_trendStrength;
	    double m_volatility;
	    double m_momentum;
	    double m_volumeProfile;
	    double m_lastValidTrendStrength;
	    double m_lastValidVolatility;
	    double m_lastValidMomentum;
	    double m_lastValidAtrValue;
	    datetime m_lastValidTrendTime;
	    datetime m_lastValidVolatilityTime;
	    datetime m_lastValidMomentumTime;
	    datetime m_lastValidAtrTime;
	    datetime m_lastMetricReuseLogTime;
    
    // Historical regime data
    ENUM_MARKET_REGIME m_regimeHistory[20];
    datetime m_regimeChangeTime[20];
    int m_regimeHistoryCount;
    
    // Regime detection thresholds
    double m_trendThreshold;
    double m_volatilityThreshold;
    
    // Warmup tracking
    datetime m_initTime;              // Time when indicators were initialized
    bool m_indicatorsReady;           // Flag indicating if indicators are fully initialized
    int m_initAttempts;               // Count of initialization attempts
    datetime m_lastInitAttempt;       // Last time initialization was attempted
    static const int WARMUP_SECONDS;  // Suppress warnings for this many seconds
    static const int INIT_RETRY_SECONDS; // Wait this long between init retries

    // Initialize indicator handles and settings
    string m_symbol;
    ENUM_TIMEFRAMES m_period;
    // Indicator handles
    int m_adxHandle;
    int m_atrHandle;
    int m_bbHandle;
    int m_macdHandle;
    int m_rsiHandle;
    int m_ma20Handle;
    int m_ma50Handle;
    int m_ma200Handle;
    
    // Indicator parameters
    int m_adxPeriod;
    int m_atrPeriod;
    int m_bbPeriod;
    int m_bbDeviation;
    int m_macdFastPeriod;
    int m_macdSlowPeriod;
    int m_macdSignalPeriod;
    int m_rsiPeriod;
    ENUM_APPLIED_PRICE m_appliedPrice;
    int m_maFastHandle;
    int m_maSlowHandle;
    
    // Constants for indicator periods
    #define ADX_PERIOD 14
    #define ATR_PERIOD 14
    #define BB_PERIOD 20
    #define BB_DEVIATION 2.0
    #define MACD_FAST 12
    #define MACD_SLOW 26
    #define MACD_SIGNAL 9
    #define RSI_PERIOD 14
    #define MA_FAST 50
    #define MA_SLOW 200
    
    // Calculate trend strength using multiple indicators

	    // Helper to release all indicator handles
	    void ReleaseAllHandles() {
        // Array of all indicator handles for easier management
        int handles[] = {
            m_maFastHandle, m_maSlowHandle, m_adxHandle, m_atrHandle, m_bbHandle,
            m_macdHandle, m_rsiHandle, m_ma20Handle, m_ma50Handle, m_ma200Handle
        };
        
        // Release each handle if valid
        for(int i = 0; i < ArraySize(handles); i++) {
            if(handles[i] != INVALID_HANDLE) {
                IndicatorRelease(handles[i]);
                handles[i] = INVALID_HANDLE;
            }
        }
        
        // Update all handle variables
        m_maFastHandle = handles[0];
        m_maSlowHandle = handles[1];
        m_adxHandle = handles[2];
        m_atrHandle = handles[3];
        m_bbHandle = handles[4];
        m_macdHandle = handles[5];
        m_rsiHandle = handles[6];
        m_ma20Handle = handles[7];
        m_ma50Handle = handles[8];
	        m_ma200Handle = handles[9];
	    }

	    void ResetMetricCaches()
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
    
    // Check if we're still in warmup period (suppress warnings)
    bool IsInWarmup() const {
        // If indicators not ready and we haven't exhausted retries, stay in warmup
        if(!m_indicatorsReady && m_initAttempts < 3) return true;
        
        // If initialization failed recently, stay quiet
        if(m_lastInitAttempt > 0 && (TimeCurrent() - m_lastInitAttempt) < INIT_RETRY_SECONDS) {
            return true;
        }
        
        // Normal warmup period after successful init
        if(m_initTime == 0) return true; // Not yet initialized
        return (TimeCurrent() - m_initTime) < WARMUP_SECONDS;
    }

    // Ensure indicator handles exist for current symbol/period
	    bool EnsureIndicatorsReady() {
	        if(m_symbol == "" || m_period == PERIOD_CURRENT)
	            return false;
        // If any core handle is invalid, attempt re-init
        if(m_atrHandle == INVALID_HANDLE || m_ma20Handle == INVALID_HANDLE || m_ma50Handle == INVALID_HANDLE || m_ma200Handle == INVALID_HANDLE)
        {
            if(!InitializeIndicators(m_symbol, m_period))
                return false;
	        }
	        return true;
	    }

	    int GetMetricReuseWindowSeconds() const
    {
        int barSeconds = PeriodSeconds(m_period);
        if(barSeconds <= 0)
            barSeconds = 60;
        // Allow reuse for up to 3 bars, with minimum 60 seconds and maximum 1 hour
        return MathMax(60, MathMin(3600, barSeconds * 3));
    }

	    bool CanReuseMetric(const datetime metricTime) const
	    {
	        return (metricTime > 0 && (TimeCurrent() - metricTime) <= GetMetricReuseWindowSeconds());
	    }

	    void MaybeLogMetricReuse(const string metricName,
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
	                    m_symbol,
	                    EnumToString(m_period),
	                    metricName,
	                    reasonTag,
	                    ageSeconds,
	                    errorCode);
	        m_lastMetricReuseLogTime = nowTime;
	    }

	    double CalculateTrendStrength() {
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
	        if(!EnsureIndicatorsReady())
	        {
            if(!IsInWarmup())
                PrintFormat("[WARN] CMarketAnalysis::CalculateTrendStrength - indicators not initialized for %s.", m_symbol);
            return 0.0;
        }

        // Use ADX for trend strength (if available - may be skipped for Jump indices)
        if(m_adxHandle != INVALID_HANDLE && BarsCalculated(m_adxHandle) > adxPeriod) {
            double adxValues[];
            ArraySetAsSeries(adxValues, true);
            // Wait for ADX indicator to initialize
            int attempts = 0;
            bool dataReady = false;
            while(attempts < 5 && !dataReady)
            {
                Sleep(10); // Reduced from 50ms to 10ms to minimize blocking
                if(CopyBuffer(m_adxHandle, 0, 0, 3, adxValues) > 0) {
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
	                    if(!IsInWarmup()) PrintFormat("[INFO] CMarketAnalysis::CalculateTrendStrength - 4807 stale data bypass for ADX on %s", m_symbol);
	                } else if(!IsInWarmup()) {
	                    PrintFormat("[WARN] CMarketAnalysis::CalculateTrendStrength - ADX data not ready for %s. Error: %d", m_symbol, errorCode);
	                }
            }
        } else if(m_adxHandle == INVALID_HANDLE && RequiresSpecialHandling(m_symbol)) {
            // For Jump/Volatility indices without ADX, use increased weight on other indicators
            // This is expected and not an error
        } else {
            // Only warn if ADX should be available but isn't ready (and not in warmup)
            if(!IsInWarmup()) PrintFormat("[WARN] CMarketAnalysis::CalculateTrendStrength - ADX data not ready for %s.", m_symbol);
        }
        
        // Use Moving Average alignment for trend confirmation
        if(m_ma20Handle != INVALID_HANDLE && BarsCalculated(m_ma20Handle) > ma20Period &&
           m_ma50Handle != INVALID_HANDLE && BarsCalculated(m_ma50Handle) > ma50Period &&
           m_ma200Handle != INVALID_HANDLE && BarsCalculated(m_ma200Handle) > ma200Period) {
            double ma20Values[], ma50Values[], ma200Values[];
            ArraySetAsSeries(ma20Values, true);
            ArraySetAsSeries(ma50Values, true);
            ArraySetAsSeries(ma200Values, true);
            
            if(CopyBuffer(m_ma20Handle, 0, 0, 3, ma20Values) > 0 &&
               CopyBuffer(m_ma50Handle, 0, 0, 3, ma50Values) > 0 &&
               CopyBuffer(m_ma200Handle, 0, 0, 3, ma200Values) > 0) {
                
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
	                    if(!IsInWarmup()) PrintFormat("[INFO] CMarketAnalysis::CalculateTrendStrength - 4807 stale data bypass for MA alignment on %s", m_symbol);
	                } else if(!IsInWarmup()) {
	                   PrintFormat("[WARN] CMarketAnalysis::CalculateTrendStrength - MA buffer copy failed for %s. Error: %d", m_symbol, errorCode);
	                }
            }
        } else {
            if(!IsInWarmup()) PrintFormat("[WARN] CMarketAnalysis::CalculateTrendStrength - MA data not ready or handles invalid for %s.", m_symbol);
        }
        
        // Use price action analysis (higher highs/lows or lower highs/lows)
        double high[], low[];
        ArraySetAsSeries(high, true);
        ArraySetAsSeries(low, true);
        
	        if(CopyHigh(m_symbol, m_period, 0, priceActionBars, high) >= priceActionBars &&
	           CopyLow(m_symbol, m_period, 0, priceActionBars, low) >= priceActionBars) {
            
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
	        if(reuseFallback && CanReuseMetric(m_lastValidTrendTime) && m_lastValidTrendStrength > 0.0)
	        {
	            MaybeLogMetricReuse("TREND_STRENGTH", reuseReason, reuseErrorCode, m_lastValidTrendTime);
	            trendStrength = MathMax(trendStrength, m_lastValidTrendStrength);
	        }
	        if(MathIsValidNumber(trendStrength) && trendStrength > 0.0)
	        {
	            m_lastValidTrendStrength = trendStrength;
	            m_lastValidTrendTime = TimeCurrent();
	        }
	        return trendStrength;
	    }
    
    // Calculate market volatility using multiple metrics
	    double CalculateVolatility() {
	        double volatility = 0.0;
	        int atrPeriod = 14;
	        int bbPeriod = 20;
	        bool reuseFallback = false;
	        string reuseReason = "";
	        int reuseErrorCode = 0;

	        // Attempt re-init if handles invalid
	        if(!EnsureIndicatorsReady())
	        {
            if(!IsInWarmup())
                PrintFormat("[WARN] CMarketAnalysis::CalculateVolatility - indicators not initialized for %s.", m_symbol);
            return 0.0;
        }

        // Use ATR for base volatility measurement
        if(m_atrHandle != INVALID_HANDLE && BarsCalculated(m_atrHandle) > atrPeriod) {
            double atrValues[];
            ArraySetAsSeries(atrValues, true);
	            if(CopyBuffer(m_atrHandle, 0, 0, 3, atrValues) > 0) {
	                // Convert ATR to percentage of price
	                double currentPriceValue = SymbolInfoDouble(m_symbol, SYMBOL_BID);
	                if(currentPriceValue > 0) { // Avoid division by zero
	                    double atrPercent = atrValues[0] / currentPriceValue * 100.0;
	                    volatility += (atrPercent / 1.0) * 0.5; // 50% weight to ATR, normalized to 1% as high volatility
	                    m_lastValidAtrValue = atrValues[0];
	                    m_lastValidAtrTime = TimeCurrent();
	                }
	            } else {
	                int errorCode = GetLastError();
	                if(errorCode == 4807 || errorCode == 4806) {
	                    // [4807 STALE TOLERANCE] Maintain last valid volatility if sync fails
	                    reuseFallback = true;
	                    reuseReason = "ATR_BUFFER_COPY_FAILED";
	                    reuseErrorCode = errorCode;
	                    if(!IsInWarmup()) PrintFormat("[INFO] CMarketAnalysis::CalculateVolatility - 4807 stale data bypass for ATR on %s", m_symbol);
	                } else if(!IsInWarmup()) {
	                   PrintFormat("[WARN] CMarketAnalysis::CalculateVolatility - ATR buffer copy failed for %s. Error: %d", m_symbol, errorCode);
	                }
            }
        } else {
            if(!IsInWarmup()) PrintFormat("[WARN] CMarketAnalysis::CalculateVolatility - ATR data not ready or handle invalid for %s.", m_symbol);
        }
        
        // Use Bollinger Bands width for volatility confirmation
        if(m_bbHandle != INVALID_HANDLE && BarsCalculated(m_bbHandle) > bbPeriod) {
            double upperValues[], middleValues[], lowerValues[];
            ArraySetAsSeries(upperValues, true);
            ArraySetAsSeries(middleValues, true);
            ArraySetAsSeries(lowerValues, true);
            
            // BB: 0=main (middle), 1=upper, 2=lower
	            if(CopyBuffer(m_bbHandle, 1, 0, 3, upperValues) > 0 &&
	               CopyBuffer(m_bbHandle, 0, 0, 3, middleValues) > 0 &&
	               CopyBuffer(m_bbHandle, 2, 0, 3, lowerValues) > 0) {
                
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
	                    if(!IsInWarmup()) PrintFormat("[INFO] CMarketAnalysis::CalculateVolatility - 4807 stale data bypass for BB on %s", m_symbol);
	                } else if(!IsInWarmup()) {
	                   PrintFormat("[WARN] CMarketAnalysis::CalculateVolatility - BB buffer copy failed for %s. Error: %d", m_symbol, errorCode);
	                }
            }
        } else {
            if(!IsInWarmup()) PrintFormat("[WARN] CMarketAnalysis::CalculateVolatility - Bollinger Bands data not ready or handle invalid for %s.", m_symbol);
        }
        
        // Use recent price range as additional volatility metric
        double high[], low[];
        ArraySetAsSeries(high, true);
        ArraySetAsSeries(low, true);
        int priceRangeBars = 10;

	        if(CopyHigh(m_symbol, m_period, 0, priceRangeBars, high) >= priceRangeBars &&
	           CopyLow(m_symbol, m_period, 0, priceRangeBars, low) >= priceRangeBars) {
            
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
	            else if(!IsInWarmup()) PrintFormat("[WARN] CMarketAnalysis::CalculateVolatility - Price range data not available for %s.", m_symbol);
	        }
	        
	        // Cap volatility at 1.0
	        volatility = MathMin(volatility, 1.0);
	        if(reuseFallback && CanReuseMetric(m_lastValidVolatilityTime) && m_lastValidVolatility > 0.0)
	        {
	            MaybeLogMetricReuse("VOLATILITY", reuseReason, reuseErrorCode, m_lastValidVolatilityTime);
	            volatility = MathMax(volatility, m_lastValidVolatility);
	        }
	        if(MathIsValidNumber(volatility) && volatility > 0.0)
	        {
	            m_lastValidVolatility = volatility;
	            m_lastValidVolatilityTime = TimeCurrent();
	        }
	        return volatility;
	    }
    
    // Calculate market momentum
	    double CalculateMomentum() {
	        double momentum = 0.0;
	        int rsiPeriod = 14;
	        int macdSlowPeriod = 26; // Longest period component of MACD
	        int rocPeriod = 5;
	        int rocBarsNeeded = rocPeriod + 1; // Need at least rocPeriod + 1 bars for ROC calculation
	        bool reuseFallback = false;
	        string reuseReason = "";
	        int reuseErrorCode = 0;

	        // Use RSI for momentum measurement
	        int rsiCalculated = BarsCalculated(m_rsiHandle);
	        if(m_rsiHandle != INVALID_HANDLE && rsiCalculated >= rsiPeriod) {
	            double rsiValues[];
	            ArraySetAsSeries(rsiValues, true);
	            if(CopyBuffer(m_rsiHandle, 0, 0, 1, rsiValues) > 0) { // Only need current RSI value
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
	        } else if(m_rsiHandle != INVALID_HANDLE) {
	            // RSI handle exists but data not ready yet - this is normal during startup
	            // Don't spam warnings during initialization
        } else {
            if(!IsInWarmup()) PrintFormat("[WARN] CMarketAnalysis::CalculateMomentum - RSI handle invalid for %s.", m_symbol);
        }
        
        // Use MACD for momentum confirmation
        // MACD Buffers: 0 = Main line, 1 = Signal line
	        if(m_macdHandle != INVALID_HANDLE && BarsCalculated(m_macdHandle) >= macdSlowPeriod) {
	            double macdValues[], signalValues[];
	            ArraySetAsSeries(macdValues, true);
	            ArraySetAsSeries(signalValues, true);
	            if(CopyBuffer(m_macdHandle, 0, 0, 1, macdValues) > 0 && // Current MACD value
               CopyBuffer(m_macdHandle, 1, 0, 1, signalValues) > 0) { // Current Signal value
                
                // MACD histogram strength
                double histogram = MathAbs(macdValues[0] - signalValues[0]);
                double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
                if(price > 0) { // Avoid division by zero
	                    double histogramPercent = histogram / price * 1000.0; // Scaled for small values
	                    momentum += MathMin(histogramPercent / 0.5, 1.0) * 0.3; // 30% weight to MACD
	                } else {
	                     PrintFormat("[WARN] CMarketAnalysis::CalculateMomentum - Could not get SYMBOL_BID for %s to calculate MACD momentum.", m_symbol);
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
	            if(!IsInWarmup()) PrintFormat("[WARN] CMarketAnalysis::CalculateMomentum - MACD data not ready or handle invalid for %s.", m_symbol);
	        }
        
        // Use price momentum (rate of change)
        double close[];
        ArraySetAsSeries(close, true);
	        if(SeriesInfoInteger(m_symbol, m_period, SERIES_BARS_COUNT) >= rocBarsNeeded) { // Check if enough bars exist on chart
	            if(CopyClose(m_symbol, m_period, 0, rocBarsNeeded, close) >= rocBarsNeeded) {
	                if(close[rocPeriod] != 0) { // Avoid division by zero for ROC calculation
	                    double roc = (close[0] - close[rocPeriod]) / close[rocPeriod] * 100.0;
	                    momentum += MathMin(MathAbs(roc) / 1.0, 1.0) * 0.3; // 30% weight to ROC
	                } else {
	                    PrintFormat("[WARN] CMarketAnalysis::CalculateMomentum - ROC calculation for %s failed due to zero historical price.", m_symbol);
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
	             PrintFormat("[WARN] CMarketAnalysis::CalculateMomentum - Not enough bars for ROC calculation on %s, Period %s. Needed: %d, Available: %d", m_symbol, EnumToString(m_period), rocBarsNeeded, SeriesInfoInteger(m_symbol, m_period, SERIES_BARS_COUNT));
	        }
	        
	        // Cap momentum at 1.0
	        momentum = MathMin(momentum, 1.0);
	        if(reuseFallback && CanReuseMetric(m_lastValidMomentumTime) && m_lastValidMomentum > 0.0)
	        {
	            MaybeLogMetricReuse("MOMENTUM", reuseReason, reuseErrorCode, m_lastValidMomentumTime);
	            momentum = MathMax(momentum, m_lastValidMomentum);
	        }
	        if(MathIsValidNumber(momentum) && momentum > 0.0)
	        {
	            m_lastValidMomentum = momentum;
	            m_lastValidMomentumTime = TimeCurrent();
	        }
	        return momentum;
	    }
    
public:
    
    // Check if symbol is available for trading/analysis
    bool IsSymbolAvailable(const string symbolName) const {
        // Check if symbol exists in Market Watch
        if(!SymbolInfoInteger(symbolName, SYMBOL_SELECT)) {
            return false;
        }
        
        // Check if we have price data
        double bid = SymbolInfoDouble(symbolName, SYMBOL_BID);
        double ask = SymbolInfoDouble(symbolName, SYMBOL_ASK);
        if(bid <= 0 || ask <= 0) {
            return false;
        }
        
        return true;
    }
    
    CMarketAnalysis() :
        m_currentRegime(MARKET_REGIME_RANGING),
        m_previousRegime(MARKET_REGIME_RANGING),
        m_lastRegimeChange(0),
        m_regimeStability(0),
	        m_trendStrength(0.0),
	        m_volatility(0.0),
	        m_momentum(0.0),
	        m_volumeProfile(0.0),
	        m_lastValidTrendStrength(0.0),
	        m_lastValidVolatility(0.0),
	        m_lastValidMomentum(0.0),
	        m_lastValidAtrValue(0.0),
	        m_lastValidTrendTime(0),
	        m_lastValidVolatilityTime(0),
	        m_lastValidMomentumTime(0),
	        m_lastValidAtrTime(0),
	        m_lastMetricReuseLogTime(0),
	        m_regimeHistoryCount(0),
	        m_symbol(""),
        m_period(PERIOD_CURRENT),
        m_initTime(0),
        m_indicatorsReady(false),
        m_initAttempts(0),
        m_lastInitAttempt(0),
        m_adxHandle(INVALID_HANDLE),
        m_atrHandle(INVALID_HANDLE),
        m_bbHandle(INVALID_HANDLE),
        m_macdHandle(INVALID_HANDLE),
        m_rsiHandle(INVALID_HANDLE),
        m_ma20Handle(INVALID_HANDLE),
        m_ma50Handle(INVALID_HANDLE),
        m_ma200Handle(INVALID_HANDLE)
    {
        
        // Initialize indicator parameters
        m_adxPeriod = 14;
        m_atrPeriod = 14;
        m_bbPeriod = 20;
        m_bbDeviation = 2;
        m_macdFastPeriod = 12;
        m_macdSlowPeriod = 26;
        m_macdSignalPeriod = 9;
        m_rsiPeriod = 14;
        m_appliedPrice = PRICE_CLOSE;
        
        // Initialize thresholds based on typical values
        m_trendThreshold = 0.6;     // 60% trend strength needed to confirm trend regime
        m_volatilityThreshold = 0.7; // 70% volatility needed to confirm volatile regime
        m_initTime = 0;             // Will be set on successful indicator initialization
    }

    // Destructor to release indicator handles
    ~CMarketAnalysis() {
        ReleaseAllHandles();
    }

    // Initialize a single indicator and handle errors
    bool InitializeIndicator(int &handle, const string symbolName, const ENUM_TIMEFRAMES period, const string indicatorName,
                            const int param1 = 0, const int param2 = 0, const double param3 = 0, const int param4 = 0) {
        // Skip if already initialized
        if(handle != INVALID_HANDLE) {
            return true;
        }
        
        // Create the appropriate indicator based on name
        if(indicatorName == "ADX") {
            handle = iADX(symbolName, period, param1 > 0 ? param1 : ADX_PERIOD);
        }
        else if(indicatorName == "ATR") {
            handle = iATR(symbolName, period, param1 > 0 ? param1 : ATR_PERIOD);
        }
        else if(indicatorName == "BB") {
            handle = iBands(symbolName, period,
                          param1 > 0 ? param1 : BB_PERIOD,
                          0, // shift
                          param3 > 0 ? param3 : BB_DEVIATION,
                          param4 > 0 ? param4 : PRICE_CLOSE);
        }
        else if(indicatorName == "MACD") {
            handle = iMACD(symbolName, period,
                         param1 > 0 ? param1 : MACD_FAST,
                         param2 > 0 ? param2 : MACD_SLOW,
                         param3 > 0 ? (int)param3 : MACD_SIGNAL,
                         param4 > 0 ? param4 : PRICE_CLOSE);
        }
        else if(indicatorName == "RSI") {
            handle = iRSI(symbolName, period,
                        param1 > 0 ? param1 : RSI_PERIOD,
                        param4 > 0 ? param4 : PRICE_CLOSE);
        }
        else if(indicatorName == "MA") {
            handle = iMA(symbolName, period,
                       param1 > 0 ? param1 : MA_FAST, // Default to fast MA period
                       0, // shift
                       param2 > 0 ? (ENUM_MA_METHOD)param2 : MODE_EMA,
                       param4 > 0 ? param4 : PRICE_CLOSE);
        }
        
        // Check for errors
        if(handle == INVALID_HANDLE) {
            int error = GetLastError();
            // Custom error message since ErrorDescription is not available in MQL5
            string errorMsg = "Unknown error";
            if(error == 4001) errorMsg = "Invalid function parameters";
            else if(error == 4002) errorMsg = "Array error";
            else if(error == 4003) errorMsg = "No memory";
            else if(error == 4004) errorMsg = "Null pointer";
            else if(error == 4005) errorMsg = "Divide by zero";
            else if(error == 4006) errorMsg = "Array out of range";
            else if(error == 4007) errorMsg = "Invalid handle";
            else if(error == 4008) errorMsg = "Wrong handle type";
            else if(error == 4009) errorMsg = "End of file";
            else if(error == 4010) errorMsg = "Some file error";
            else if(error == 4011) errorMsg = "Wrong file name";
            else if(error == 4012) errorMsg = "Too many opened files";
            else if(error == 4013) errorMsg = "Cannot open file";
            else if(error == 4014) errorMsg = "Incompatible access to a file";
            else if(error == 4015) errorMsg = "No order selected";
            else if(error == 4016) errorMsg = "Unknown symbol";
            else if(error == 4017) errorMsg = "Invalid price";
            else if(error == 4018) errorMsg = "Invalid ticket";
            else if(error == 4019) errorMsg = "Trade is not allowed";
            else if(error == 4020) errorMsg = "Longs are not allowed";
            else if(error == 4021) errorMsg = "Shorts are not allowed";
            else if(error == 4022) errorMsg = "Automated trading disabled";
            
            PrintFormat("[WARN] Failed to create %s handle for %s, Period: %s. Error: %d (%s)",
                       indicatorName, symbolName, EnumToString(period), error, errorMsg);
            return false;
        }
        
        return true;
    }

    // Check if symbol is compatible with ADX indicator
    bool IsADXCompatible(const string symbolName) {
        // Boom/Crash indices are incompatible
        if(StringFind(symbolName, "Boom") >= 0 || StringFind(symbolName, "Crash") >= 0)
            return false;

        // Jump indices have issues with ADX (error 4805)
        if(StringFind(symbolName, "Jump") >= 0)
            return false;

        return true;
    }

    // Check if symbol needs special indicator handling
    bool RequiresSpecialHandling(const string symbolName) {
        // Volatility indices
        if(StringFind(symbolName, "Vol") >= 0)
            return true;

        // Jump indices
        if(StringFind(symbolName, "Jump") >= 0)
            return true;

        // Step indices
        if(StringFind(symbolName, "Step") >= 0)
            return true;

        // Weltrade / Other Synthetic indices
        if(StringFind(symbolName, "Boom") >= 0 ||
           StringFind(symbolName, "Crash") >= 0 ||
           StringFind(symbolName, "PainX") >= 0 ||
           StringFind(symbolName, "SFX Vol") >= 0 ||
           StringFind(symbolName, "GainX") >= 0 ||
           StringFind(symbolName, "FX Vol") >= 0 ||
           StringFind(symbolName, "FlipX") >= 0)
            return true;

        return false;
    }

    // Initialize all required indicators for the given symbol and period
	    bool InitializeIndicators(const string symbolName, const ENUM_TIMEFRAMES period) {
	        // Track initialization attempt
	        m_initAttempts++;
	        m_lastInitAttempt = TimeCurrent();
	        if(m_symbol != symbolName || m_period != period)
	            ResetMetricCaches();
	        
	        // Skip Boom/Crash indices - completely incompatible
	        if(StringFind(symbolName, "Boom") >= 0 || StringFind(symbolName, "Crash") >= 0) {
            PrintFormat("[INFO] Skipping indicator initialization for incompatible symbol: %s", symbolName);
            m_indicatorsReady = false;
            return false;
        }
        
        // Check if symbol is available
        if(!IsSymbolAvailable(symbolName)) {
            if(m_initAttempts == 1) {
                PrintFormat("[INFO] Symbol %s not available in Market Watch or has no price data", symbolName);
            }
            m_indicatorsReady = false;
            return false;
        }
        
        // Store symbol and period for later use
        m_symbol = symbolName;
        m_period = period;
        
        bool useADX = IsADXCompatible(symbolName);
        
        // Initialize ADX (skip for incompatible symbols like Jump indices)
        if(useADX) {
            m_adxHandle = iADX(symbolName, period, m_adxPeriod);
            if(m_adxHandle == INVALID_HANDLE) {
                PrintFormat("[WARN] Failed to create ADX handle for %s, error: %d - continuing without ADX", 
                           symbolName, GetLastError());
                // Don't fail completely - continue with other indicators
            }
        } else {
            PrintFormat("[INFO] Skipping ADX initialization for %s (incompatible symbol type)", symbolName);
            m_adxHandle = INVALID_HANDLE;
        }
        
        // Initialize ATR
        m_atrHandle = iATR(symbolName, period, m_atrPeriod);
        if(m_atrHandle == INVALID_HANDLE) {
            PrintFormat("Failed to create ATR handle for %s, error: %d", symbolName, GetLastError());
            return false;
        }
        
        // Initialize Bollinger Bands
        m_bbHandle = iBands(symbolName, period, m_bbPeriod, 0, m_bbDeviation, m_appliedPrice);
        if(m_bbHandle == INVALID_HANDLE) {
            PrintFormat("Failed to create Bollinger Bands handle for %s, error: %d", symbolName, GetLastError());
            return false;
        }
        
        // Initialize MACD
        m_macdHandle = iMACD(symbolName, period, m_macdFastPeriod, m_macdSlowPeriod, m_macdSignalPeriod, m_appliedPrice);
        if(m_macdHandle == INVALID_HANDLE) {
            PrintFormat("Failed to create MACD handle for %s, error: %d", symbolName, GetLastError());
            return false;
        }
        
        // Initialize RSI
        m_rsiHandle = iRSI(symbolName, period, m_rsiPeriod, m_appliedPrice);
        if(m_rsiHandle == INVALID_HANDLE) {
            PrintFormat("Failed to create RSI handle for %s, error: %d", symbolName, GetLastError());
            return false;
        }
        
        // Initialize Moving Averages
        m_ma20Handle = iMA(symbolName, period, 20, 0, MODE_EMA, m_appliedPrice);
        if(m_ma20Handle == INVALID_HANDLE) {
            PrintFormat("Failed to create MA(20) handle for %s, error: %d", symbolName, GetLastError());
            return false;
        }
        
        m_ma50Handle = iMA(symbolName, period, 50, 0, MODE_EMA, m_appliedPrice);
        if(m_ma50Handle == INVALID_HANDLE) {
            PrintFormat("Failed to create MA(50) handle for %s, error: %d", symbolName, GetLastError());
            return false;
        }
        
        m_ma200Handle = iMA(symbolName, period, 200, 0, MODE_EMA, m_appliedPrice);
        if(m_ma200Handle == INVALID_HANDLE) {
            PrintFormat("Failed to create MA(200) handle for %s, error: %d", symbolName, GetLastError());
            return false;
        }
        
        // Wait for indicators to calculate with retry logic
        int maxRetries = 20;  // Maximum retries for history sync
        int retryCount = 0;
        bool indicatorsReady = false;
        
        while(retryCount < maxRetries && !indicatorsReady) {
            // Check if indicators have enough calculated bars
            bool adxReady = (m_adxHandle == INVALID_HANDLE) || BarsCalculated(m_adxHandle) >= m_adxPeriod;
            bool atrReady = BarsCalculated(m_atrHandle) >= m_atrPeriod;
            bool bbReady = BarsCalculated(m_bbHandle) >= m_bbPeriod;
            bool macdReady = BarsCalculated(m_macdHandle) >= m_macdSlowPeriod;
            bool rsiReady = BarsCalculated(m_rsiHandle) >= m_rsiPeriod;
            bool ma20Ready = BarsCalculated(m_ma20Handle) >= 20;
            bool ma50Ready = BarsCalculated(m_ma50Handle) >= 50;
            bool ma200Ready = BarsCalculated(m_ma200Handle) >= 200;
            
            indicatorsReady = adxReady && atrReady && bbReady && macdReady && 
                             rsiReady && ma20Ready && ma50Ready && ma200Ready;
            
            if(!indicatorsReady) {
                retryCount++;
                if(retryCount < maxRetries) {
                    Sleep(50); // Reduced from 200ms to 50ms to minimize blocking
                }
            }
        }
        
        if(!indicatorsReady) {
            PrintFormat("[WARN] Indicators not ready after %d attempts for %s - will retry on next call", 
                       maxRetries, symbolName);
            return false;
        }
        
        string adxStatus = (m_adxHandle == INVALID_HANDLE) ? " (ADX skipped)" : "";
        PrintFormat("[SUCCESS] Initialized indicators for %s on %s%s", 
                   symbolName, EnumToString(period), adxStatus);
        m_initTime = TimeCurrent(); // Track warmup start time
        m_indicatorsReady = true;
        return true;
    }
    
    // Detect market regime for a given symbol
    ENUM_MARKET_REGIME DetectMarketRegime() {
        // Ensure indicators are initialized for m_symbol and m_period
        // Note: ADX can be INVALID_HANDLE for Jump indices (incompatible symbol type)
        if (m_symbol == "") {
            PrintFormat("[ERROR] CMarketAnalysis::DetectMarketRegime - Symbol not set. Call InitializeIndicators first.");
            return m_currentRegime;
        }
        
        // Check if at least some core indicators are available
        if (m_atrHandle == INVALID_HANDLE && m_rsiHandle == INVALID_HANDLE && m_ma20Handle == INVALID_HANDLE) {
            PrintFormat("[ERROR] CMarketAnalysis::DetectMarketRegime - No indicators initialized for %s. Call InitializeIndicators first.", m_symbol);
            return m_currentRegime;
        }

        // Calculate current market metrics
        m_trendStrength = CalculateTrendStrength();
        m_volatility = CalculateVolatility();
        m_momentum = CalculateMomentum(); 

        ENUM_MARKET_REGIME detectedRegime = MARKET_REGIME_RANGING; 

        // Determine market regime based on calculated metrics and thresholds
        if (m_trendStrength >= m_trendThreshold) {
            detectedRegime = MARKET_REGIME_TRENDING;
        } else if (m_volatility >= m_volatilityThreshold) {
            detectedRegime = MARKET_REGIME_VOLATILE;
        } else {
            detectedRegime = MARKET_REGIME_RANGING;
        }
        
        // Update regime state and history
        if(detectedRegime != m_currentRegime) {
            m_previousRegime = m_currentRegime;
            m_currentRegime = detectedRegime;
            m_lastRegimeChange = TimeCurrent();
            m_regimeStability = 0;
            
            // Store in history 
            if(m_regimeHistoryCount < ArraySize(m_regimeHistory)) {
                m_regimeHistory[m_regimeHistoryCount] = m_currentRegime;
                m_regimeChangeTime[m_regimeHistoryCount] = m_lastRegimeChange;
                m_regimeHistoryCount++;
            } else {
                for(int i = 0; i < ArraySize(m_regimeHistory) - 1; i++) {
                    m_regimeHistory[i] = m_regimeHistory[i+1];
                    m_regimeChangeTime[i] = m_regimeChangeTime[i+1];
                }
                m_regimeHistory[ArraySize(m_regimeHistory)-1] = m_currentRegime;
                m_regimeChangeTime[ArraySize(m_regimeHistory)-1] = m_lastRegimeChange;
            }
            PrintFormat("[INFO] Market regime for %s changed to %s (Trend: %.2f, Vol: %.2f)", m_symbol, EnumToString(m_currentRegime), m_trendStrength, m_volatility);
        } else {
            m_regimeStability++;
        }
        
        return m_currentRegime;
    }
    
    // Get current market regime
    ENUM_MARKET_REGIME GetCurrentRegime() const {
        return m_currentRegime;
    }
    
    
    // Set market regime (used when loading from session memory)
    void SetMarketRegime(ENUM_MARKET_REGIME regime) {
        m_currentRegime = regime;
    }
    
    // Get current market volatility (calculated for m_symbol and m_period)
    double GetCurrentVolatility() const {
        if (m_symbol == "" || m_atrHandle == INVALID_HANDLE) { // Check if indicators were initialized
             PrintFormat("[WARNING] CMarketAnalysis::GetCurrentVolatility - Volatility not available or indicators not initialized for %s. Call InitializeIndicators and DetectMarketRegime first.", m_symbol);
             return 0.0; // Default or error value
        }
        return m_volatility; // m_volatility is updated by DetectMarketRegime via CalculateVolatility
    }
    
    // Get current market trend strength (calculated for m_symbol and m_period)
    double GetCurrentTrendStrength() const {
        if (m_symbol == "") {
             PrintFormat("[WARNING] CMarketAnalysis::GetCurrentTrendStrength - Symbol not set. Call InitializeIndicators and DetectMarketRegime first.");
             return 0.0; // Default or error value
        }
        return m_trendStrength; // m_trendStrength is updated by DetectMarketRegime via CalculateTrendStrength
    }

    // Get current market momentum
    double GetMomentum() const {
        return m_momentum;
    }

    // Get current ATR value
    double GetATRValue();
    
    // Get ATR value for a specific symbol and period
    double GetATR(const string symbol, int period);
};

//+------------------------------------------------------------------+
//| Get current ATR value                                            |
//+------------------------------------------------------------------+
double CMarketAnalysis::GetATRValue()
{
        if(m_atrHandle == INVALID_HANDLE) return 0.0;
        
        double atrValues[];
	        ArraySetAsSeries(atrValues, true);
	        ResetLastError();
	        if(CopyBuffer(m_atrHandle, 0, 0, 1, atrValues) > 0 && atrValues[0] > 0.0) {
	            m_lastValidAtrValue = atrValues[0];
	            m_lastValidAtrTime = TimeCurrent();
	            return atrValues[0];
	        }
	        int errorCode = GetLastError();
	        if((errorCode == 4807 || errorCode == 4806) && CanReuseMetric(m_lastValidAtrTime) && m_lastValidAtrValue > 0.0)
	        {
	            MaybeLogMetricReuse("ATR_VALUE", "ATR_VALUE_COPY_FAILED", errorCode, m_lastValidAtrTime);
	            return m_lastValidAtrValue;
	        }
	        return 0.0;
	    }

//+------------------------------------------------------------------+
//| Get ATR value for a specific symbol and period                   |
//+------------------------------------------------------------------+
double CMarketAnalysis::GetATR(const string symbol, int period)
{
    // For now, return the current ATR value
    // In a more complete implementation, this could handle multiple symbols
    return GetATRValue();
}

const int CMarketAnalysis::WARMUP_SECONDS = 60;
const int CMarketAnalysis::INIT_RETRY_SECONDS = 300;

#endif
