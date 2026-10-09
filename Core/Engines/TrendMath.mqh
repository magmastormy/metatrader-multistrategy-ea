// TrendMath.mqh - Stateless trend math primitives
// Extracted verbatim from TrendEngine.mqh (no behavior change)
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef TREND_MATH_MQH
#define TREND_MATH_MQH

// Stateless numeric helpers used by the trend engine.
// All methods are static: they depend only on their arguments and
// on terminal price series, never on engine instance state.
class CTrendMath
{
public:
    //--- Manual ATR replacement used when the ATR handle cannot be read.
    static double CalculateAtrFallback(const string symbol,
                                       ENUM_TIMEFRAMES timeframe,
                                       const int period);

    //--- Manual EMA series replacement used when an MA handle cannot be read.
    static bool CalculateEmaFallbackSeries(const string symbol,
                                           ENUM_TIMEFRAMES timeframe,
                                           const int period,
                                           const int count,
                                           double &output[]);

    //--- Rate-of-change momentum over 'period' bars, expressed in percent.
    static double CalculateMomentum(const string symbol,
                                    ENUM_TIMEFRAMES timeframe,
                                    int period);

    //--- Normalized MA slope converted to an angle in degrees.
    static double CalculateTrendAngle(double &ma[], int period);
};

double CTrendMath::CalculateAtrFallback(const string symbol,
                                        ENUM_TIMEFRAMES timeframe,
                                        const int period)
{
    int requiredBars = MathMax(period + 1, 5);
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(symbol, timeframe, 0, requiredBars, rates);
    if(copied <= period)
        return 0.0;

    double trueRangeSum = 0.0;
    int usable = MathMin(period, copied - 1);
    for(int i = 0; i < usable; i++)
    {
        double rangeHighLow = rates[i].high - rates[i].low;
        double rangeHighClose = MathAbs(rates[i].high - rates[i + 1].close);
        double rangeLowClose = MathAbs(rates[i].low - rates[i + 1].close);
        trueRangeSum += MathMax(rangeHighLow, MathMax(rangeHighClose, rangeLowClose));
    }

    if(usable <= 0)
        return 0.0;

    return trueRangeSum / (double)usable;
}

bool CTrendMath::CalculateEmaFallbackSeries(const string symbol,
                                            ENUM_TIMEFRAMES timeframe,
                                            const int period,
                                            const int count,
                                            double &output[])
{
    if(period <= 0 || count <= 0)
        return false;

    // Need sufficient bars for SMA initialization + EMA stabilization
    int requiredBars = MathMax(period * 3, period + count + 10);
    double closes[];
    ArraySetAsSeries(closes, true);
    int copied = CopyClose(symbol, timeframe, 0, requiredBars, closes);
    if(copied < period + count)
        return false;

    // Allocate output array
    if(ArraySize(output) != count)
    {
        if(ArrayResize(output, count) < 0)
            return false;
    }

    // Correct EMA alpha: 2 / (period + 1)
    double alpha = 2.0 / ((double)period + 1.0);
    double invAlpha = 1.0 - alpha;

    // Initialize with SMA for first 'period' bars (stable starting point)
    double smaSum = 0.0;
    for(int i = 0; i < period; i++)
        smaSum += closes[i];
    double ema = smaSum / (double)period;

    // Calculate EMA forward through the series
    // closes[0] = most recent, closes[copied-1] = oldest
    for(int i = 0; i < copied; i++)
    {
        ema = (alpha * closes[i]) + (invAlpha * ema);

        // Store results where output[0] = most recent EMA
        // output index maps: output[0] = EMA at closes[0] (most recent)
        int outputIdx = i;  // Will be offset from end when we collect output
    }

    // Now collect the 'count' most recent EMA values into output array
    // We need to recalculate to get the last 'count' values properly
    // Reset EMA to SMA and recalculate
    smaSum = 0.0;
    for(int i = 0; i < period; i++)
        smaSum += closes[i];
    ema = smaSum / (double)period;

    // Calculate all EMAs, storing the last 'count' values
    double emaBuffer[];
    ArrayResize(emaBuffer, copied);
    for(int i = 0; i < copied; i++)
    {
        ema = (alpha * closes[i]) + (invAlpha * ema);
        emaBuffer[i] = ema;
    }

    // Copy the 'count' most recent EMAs to output
    // emaBuffer[0] = EMA at closes[0] (most recent)
    // emaBuffer[copied-1] = EMA at closes[copied-1] (oldest)
    for(int i = 0; i < count; i++)
    {
        if(i < copied)
            output[i] = emaBuffer[i];
        else
            output[i] = 0.0;
    }

    return true;
}

double CTrendMath::CalculateMomentum(const string symbol, ENUM_TIMEFRAMES timeframe, int period)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    
    if(CopyRates(symbol, timeframe, 0, period + 1, rates) < period + 1)
        return 0;
    
    // Calculate rate of change
    if(rates[period].close <= 0.0)
        return 0.0;
    double roc = ((rates[0].close - rates[period].close) / rates[period].close) * 100;
    
    return roc;
}

double CTrendMath::CalculateTrendAngle(double &ma[], int period)
{
    // Validate inputs
    if(ArraySize(ma) < 2 || period < 2)
        return 0;
    
    // Ensure period doesn't exceed array bounds
    int effectivePeriod = MathMin(period, ArraySize(ma) - 1);
    if(effectivePeriod < 2)
        return 0;
    
    // Calculate average price for normalization
    double avgPrice = 0.0;
    double oldestValue = ma[effectivePeriod];
    double newestValue = ma[0];
    
    if(!MathIsValidNumber(oldestValue) || !MathIsValidNumber(newestValue))
        return 0;
    
    avgPrice = (newestValue + oldestValue) / 2.0;
    if(avgPrice <= 0 || !MathIsValidNumber(avgPrice))
        return 0;
    
    // Calculate slope as percentage change per bar
    double pctChange = ((newestValue - oldestValue) / avgPrice) * 100.0;
    double slopePerBar = pctChange / effectivePeriod;
    
    // Scale factor to get meaningful angles (0.1% per bar = ~45 degrees)
    double scaledSlope = slopePerBar * 10.0;
    
    // Clamp to prevent extreme values
    scaledSlope = MathMax(-10.0, MathMin(10.0, scaledSlope));
    
    // Convert to angle in degrees
    double angle = MathArctan(scaledSlope) * 180.0 / M_PI;
    
    // Final validation
    if(!MathIsValidNumber(angle))
        return 0;
    
    return angle;
}

#endif // TREND_MATH_MQH
