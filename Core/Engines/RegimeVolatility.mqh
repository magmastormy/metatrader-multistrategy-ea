//+------------------------------------------------------------------+
//| RegimeVolatility.mqh                                             |
//| Volatility / dispersion measurement helpers (stateless)          |
//| Extracted verbatim from RegimeEngine.mqh (no behavior change)    |
//+------------------------------------------------------------------+
#ifndef REGIME_VOLATILITY_MQH
#define REGIME_VOLATILITY_MQH

#include "RegimeTypes.mqh"

//+------------------------------------------------------------------+
//| Rate-derived ATR / Bollinger fallback, range z-score and the     |
//| sanitised ADX read. All pure functions of (symbol, tf, config).  |
//+------------------------------------------------------------------+
class CRegimeVolatility
{
public:
    //--- Rebuild ATR + Bollinger bands straight from raw rates
    static bool BuildFallbackIndicators(const string symbol,
                                        const ENUM_TIMEFRAMES timeframe,
                                        const SRegimeConfig &config,
                                        double &atrValue,
                                        double &bbUpperValue,
                                        double &bbLowerValue);

    //--- Rolling close z-score over the configured window
    static bool ComputeRangeZScore(const string symbol,
                                   const ENUM_TIMEFRAMES timeframe,
                                   const int zScoreWindow,
                                   double &zScoreOut);

    //--- Batch104-C2: domain-validated ADX read (0.0 when unavailable)
    static double ReadAdxValue(const int adxHandle,
                               const string symbol,
                               const ENUM_TIMEFRAMES timeframe);
};

//+------------------------------------------------------------------+
//| Build ATR / Bollinger values from raw rates                      |
//+------------------------------------------------------------------+
bool CRegimeVolatility::BuildFallbackIndicators(const string symbol,
                                                const ENUM_TIMEFRAMES timeframe,
                                                const SRegimeConfig &config,
                                                double &atrValue,
                                                double &bbUpperValue,
                                                double &bbLowerValue)
{
    atrValue = 0.0;
    bbUpperValue = 0.0;
    bbLowerValue = 0.0;

    int requiredBars = MathMax(config.bbPeriod + 3, config.atrPeriod + 3);
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(symbol, timeframe, 0, requiredBars, rates);
    if(copied < requiredBars)
        return false;

    int atrWindow = MathMin(config.atrPeriod, copied - 2);
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

    int bbWindow = MathMin(config.bbPeriod, copied);
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
    bbUpperValue = mean + (config.bbDeviation * stdDev);
    bbLowerValue = mean - (config.bbDeviation * stdDev);

    return (MathIsValidNumber(atrValue) && atrValue > 0.0 &&
            MathIsValidNumber(bbUpperValue) &&
            MathIsValidNumber(bbLowerValue));
}

//+------------------------------------------------------------------+
//| Rolling close z-score                                            |
//+------------------------------------------------------------------+
bool CRegimeVolatility::ComputeRangeZScore(const string symbol,
                                           const ENUM_TIMEFRAMES timeframe,
                                           const int zScoreWindow,
                                           double &zScoreOut)
{
    zScoreOut = 0.0;
    int window = MathMax(10, zScoreWindow);
    double closes[];
    ArraySetAsSeries(closes, true);
    int copied = CopyClose(symbol, timeframe, 0, window, closes);
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

//+------------------------------------------------------------------+
//| ENHANCEMENT: sanitised ADX read (Batch 93 - Week 5)              |
//+------------------------------------------------------------------+
double CRegimeVolatility::ReadAdxValue(const int adxHandle,
                                       const string symbol,
                                       const ENUM_TIMEFRAMES timeframe)
{
    double adxBuffer[1];
    double adxValue = 0.0;
    if(adxHandle != INVALID_HANDLE && CopyBuffer(adxHandle, 0, 0, 1, adxBuffer) == 1)
    {
        adxValue = adxBuffer[0];
        // Batch104-C2: ADX domain validation — corrupted multi-symbol indicator handles
        // can return values like 115185.3 (valid ADX range is 0-100)
        if(adxValue < 0.0 || adxValue > 100.0 || !MathIsValidNumber(adxValue))
        {
            PrintFormat("[REGIME-ADX-SANITY] ADX_OUT_OF_RANGE | symbol=%s | timeframe=%s | raw_adx=%.1f | clamped=100.0",
                        symbol, EnumToString(timeframe), adxValue);
            adxValue = MathMin(100.0, MathMax(0.0, MathIsValidNumber(adxValue) ? adxValue : 0.0));
        }
    }

    return adxValue;
}

#endif // REGIME_VOLATILITY_MQH
