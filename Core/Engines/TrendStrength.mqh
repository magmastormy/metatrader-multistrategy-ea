//+------------------------------------------------------------------+
//| TrendStrength.mqh - Trend strength scoring                       |
//| Extracted verbatim from TrendEngine.mqh (no behavior change)     |
//+------------------------------------------------------------------+
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef TREND_STRENGTH_MQH
#define TREND_STRENGTH_MQH

//+------------------------------------------------------------------+
//| Stateless 0-100 trend strength scorer.                           |
//| Thresholds are injected so the scorer stays free of engine state.|
//+------------------------------------------------------------------+
class CTrendStrength
{
public:
    //--- adx < 0 selects the synthetic (non-ADX) scoring model.
    static double Calculate(double &ma_fast[],
                            double &ma_medium[],
                            double &ma_slow[],
                            double adx,
                            const double trendThreshold,
                            const double strongTrendThreshold);
};

//+------------------------------------------------------------------+
//| Calculate Trend Strength                                        |
//+------------------------------------------------------------------+
double CTrendStrength::Calculate(double &ma_fast[], double &ma_medium[],
                                 double &ma_slow[], double adx,
                                 const double trendThreshold,
                                 const double strongTrendThreshold)
{
    double strength = 0;
    bool useAdxModel = (adx >= 0.0);
    
    // Validate MA arrays have sufficient data
    if(ArraySize(ma_fast) < 5 || ArraySize(ma_medium) < 5 || ArraySize(ma_slow) < 5)
    {
        Print("[TrendEngine][WARN] Insufficient MA data for trend strength calculation");
        return 0.0;
    }
    
    // Factor 1: MA alignment (40% weight)
    // Use epsilon to prevent division by zero with small values
    double fastMedDiff = ma_fast[0] - ma_medium[0];
    double medSlowDiff = ma_medium[0] - ma_slow[0];
    double slowValue = MathAbs(ma_slow[0]);
    double smallEpsilon = 0.0000001;
    
    if(fastMedDiff > smallEpsilon && medSlowDiff > smallEpsilon)
    {
        // Perfect bullish alignment
        strength += 40;
        if(slowValue > smallEpsilon)
        {
            double separation = ((ma_fast[0] - ma_slow[0]) / slowValue) * 100.0;
            strength += MathMin(10.0, separation); // Up to 10 additional points for separation
        }
    }
    else if(fastMedDiff < -smallEpsilon && medSlowDiff < -smallEpsilon)
    {
        // Perfect bearish alignment
        strength += 40;
        if(slowValue > smallEpsilon)
        {
            double separation = ((ma_slow[0] - ma_fast[0]) / slowValue) * 100.0;
            strength += MathMin(10.0, separation); // Up to 10 additional points for separation
        }
    }
    else
    {
        // Partial alignment
        strength += 20;
    }
    
    // Factor 2: ADX strength (30% weight) or synthetic slope proxy
    if(useAdxModel && adx > strongTrendThreshold)
    {
        strength += 30;
    }
    else if(useAdxModel && adx > trendThreshold)
    {
        strength += 20;
    }
    else if(useAdxModel)
    {
        strength += 10;
    }
    else
    {
        double mediumSlopePct = 0.0;
        double mediumValue = MathAbs(ma_medium[4]);
        if(mediumValue > smallEpsilon)
            mediumSlopePct = MathAbs((ma_medium[0] - ma_medium[4]) / mediumValue) * 100.0;
        strength += MathMin(25.0, mediumSlopePct * 150.0);
    }
    
    // Factor 3: MA slope consistency (20% weight)
    bool consistentSlope = true;
    for(int i = 1; i < 5; i++)
    {
        double fastDelta = ma_fast[i-1] - ma_fast[i];
        double mediumDelta = ma_medium[i-1] - ma_medium[i];
        // Check if slopes have same direction (both positive or both negative)
        if(fastDelta * mediumDelta < 0)
        {
            consistentSlope = false;
            break;
        }
    }
    if(consistentSlope)
        strength += 20;
    else
        strength += 10;

    // Factor 4: MA spread (additional 15% for non-ADX mode)
    if(!useAdxModel)
    {
        double spreadPct = 0.0;
        if(slowValue > smallEpsilon)
            spreadPct = MathAbs((ma_fast[0] - ma_slow[0]) / slowValue) * 100.0;
        strength += MathMin(15.0, spreadPct * 120.0);
    }
    
    // Clamp to valid range
    return MathMax(0.0, MathMin(100.0, strength));
}

#endif // TREND_STRENGTH_MQH
