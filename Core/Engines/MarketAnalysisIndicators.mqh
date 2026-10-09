// MarketAnalysisIndicators.mqh - Indicator handle lifecycle
// Extracted verbatim from MarketAnalysis.mqh (no behavior change)
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef MARKET_ANALYSIS_INDICATORS_MQH
#define MARKET_ANALYSIS_INDICATORS_MQH

#include "MarketAnalysisTypes.mqh"
#include "MarketAnalysisSymbolProfile.mqh"
#include "MarketAnalysisMetricCache.mqh"

// Owns the analysed symbol/timeframe, every indicator handle, the
// indicator parameters and the warmup / retry bookkeeping.
// NOTE: the timeframe accessor is named Timeframe() on purpose -
// a member named Period() would shadow the built-in Period().
class CMarketAnalysisIndicators
{
private:
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

    // Warmup tracking
    datetime m_initTime;              // Time when indicators were initialized
    bool m_indicatorsReady;           // Flag indicating if indicators are fully initialized
    int m_initAttempts;               // Count of initialization attempts
    datetime m_lastInitAttempt;       // Last time initialization was attempted
    static const int WARMUP_SECONDS;  // Suppress warnings for this many seconds
    static const int INIT_RETRY_SECONDS; // Wait this long between init retries

public:
    CMarketAnalysisIndicators() :
        m_symbol(""),
        m_period(PERIOD_CURRENT),
        m_adxHandle(INVALID_HANDLE),
        m_atrHandle(INVALID_HANDLE),
        m_bbHandle(INVALID_HANDLE),
        m_macdHandle(INVALID_HANDLE),
        m_rsiHandle(INVALID_HANDLE),
        m_ma20Handle(INVALID_HANDLE),
        m_ma50Handle(INVALID_HANDLE),
        m_ma200Handle(INVALID_HANDLE),
        m_initTime(0),
        m_indicatorsReady(false),
        m_initAttempts(0),
        m_lastInitAttempt(0)
    {
        // NOTE: m_maFastHandle / m_maSlowHandle are deliberately left out of
        // the initializer list to mirror the original CMarketAnalysis ctor.
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
        m_initTime = 0;             // Will be set on successful indicator initialization
    }

    //--- Context accessors
    string          Symbol()          const { return m_symbol; }
    ENUM_TIMEFRAMES Timeframe()       const { return m_period; }
    bool            IndicatorsReady() const { return m_indicatorsReady; }

    //--- Handle accessors
    int AdxHandle()   const { return m_adxHandle; }
    int AtrHandle()   const { return m_atrHandle; }
    int BbHandle()    const { return m_bbHandle; }
    int MacdHandle()  const { return m_macdHandle; }
    int RsiHandle()   const { return m_rsiHandle; }
    int Ma20Handle()  const { return m_ma20Handle; }
    int Ma50Handle()  const { return m_ma50Handle; }
    int Ma200Handle() const { return m_ma200Handle; }

    //--- Helper to release all indicator handles
    void ReleaseAllHandles();

    //--- Check if we're still in warmup period (suppress warnings)
    bool IsInWarmup() const;

    //--- Ensure indicator handles exist for current symbol/period
    bool EnsureIndicatorsReady(CMarketAnalysisMetricCache &cache);

    //--- Initialize a single indicator and handle errors
    bool InitializeIndicator(int &handle, const string symbolName, const ENUM_TIMEFRAMES period, const string indicatorName,
                             const int param1 = 0, const int param2 = 0, const double param3 = 0, const int param4 = 0);

    //--- Initialize all required indicators for the given symbol and period
    bool InitializeIndicators(const string symbolName, const ENUM_TIMEFRAMES period, CMarketAnalysisMetricCache &cache);
};

// Helper to release all indicator handles
void CMarketAnalysisIndicators::ReleaseAllHandles()
{
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

// Check if we're still in warmup period (suppress warnings)
bool CMarketAnalysisIndicators::IsInWarmup() const
{
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
bool CMarketAnalysisIndicators::EnsureIndicatorsReady(CMarketAnalysisMetricCache &cache)
{
    if(m_symbol == "")
        return false;

    // Resolve PERIOD_CURRENT to actual chart timeframe
    ENUM_TIMEFRAMES actualPeriod = m_period;
    if(actualPeriod == PERIOD_CURRENT || actualPeriod == 0)
        actualPeriod = Period();

    // If any core handle is invalid, attempt re-init
    if(m_atrHandle == INVALID_HANDLE || m_ma20Handle == INVALID_HANDLE || m_ma50Handle == INVALID_HANDLE || m_ma200Handle == INVALID_HANDLE)
    {
        if(!InitializeIndicators(m_symbol, actualPeriod, cache))
            return false;
    }
    return true;
}

// Initialize a single indicator and handle errors
bool CMarketAnalysisIndicators::InitializeIndicator(int &handle, const string symbolName, const ENUM_TIMEFRAMES period, const string indicatorName,
                                                    const int param1, const int param2, const double param3, const int param4)
{
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

// Initialize all required indicators for the symbol and period
bool CMarketAnalysisIndicators::InitializeIndicators(const string symbolName, const ENUM_TIMEFRAMES period, CMarketAnalysisMetricCache &cache)
{
    // Track initialization attempt
    m_initAttempts++;
    m_lastInitAttempt = TimeCurrent();
    if(m_symbol != symbolName || m_period != period)
        cache.ResetMetricCaches();

    // Skip Boom/Crash indices - completely incompatible
    // Use global multi-asset profiler for proper asset classification
    if(g_multiAssetProfiler != NULL)
    {
        SAssetProfile profile = g_multiAssetProfiler.GetProfile(symbolName);
        if(IsSyntheticAssetClass(profile.assetClass))
        {
            CDerivAssetProfiler* derivProfiler = g_multiAssetProfiler.GetDerivProfiler();
            if(derivProfiler != NULL)
            {
                ENUM_DERIV_FAMILY family = derivProfiler.DetectFamily(symbolName);
                if(family == DERIV_CRASH_BOOM)
                {
                    PrintFormat("[INFO] Skipping indicator initialization for incompatible symbol: %s", symbolName);
                    m_indicatorsReady = false;
                    return false;
                }
            }
        }
    }
    else
    {
        // Fallback to string matching if profiler not available
        if(StringFind(symbolName, "Boom") >= 0 || StringFind(symbolName, "Crash") >= 0) {
            PrintFormat("[INFO] Skipping indicator initialization for incompatible symbol: %s", symbolName);
            m_indicatorsReady = false;
            return false;
        }
    }

    // Check if symbol is available
    if(!CMarketAnalysisSymbolProfile::IsSymbolAvailable(symbolName)) {
        if(m_initAttempts == 1) {
            PrintFormat("[INFO] Symbol %s not available in Market Watch or has no price data", symbolName);
        }
        m_indicatorsReady = false;
        return false;
    }

    // Store symbol and period for later use
    m_symbol = symbolName;
    // Resolve PERIOD_CURRENT to actual chart timeframe
    ENUM_TIMEFRAMES resolvedPeriod = period;
    if(resolvedPeriod == PERIOD_CURRENT || resolvedPeriod == 0)
        resolvedPeriod = Period();
    m_period = resolvedPeriod;

    bool useADX = CMarketAnalysisSymbolProfile::IsADXCompatible(symbolName);

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

const int CMarketAnalysisIndicators::WARMUP_SECONDS = 60;
const int CMarketAnalysisIndicators::INIT_RETRY_SECONDS = 300;

#endif // MARKET_ANALYSIS_INDICATORS_MQH
