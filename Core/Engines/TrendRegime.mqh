// TrendRegime.mqh - Trend regime classification
// Extracted verbatim from TrendEngine.mqh (no behavior change)
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef TREND_REGIME_MQH
#define TREND_REGIME_MQH

#include "TrendTypes.mqh"

// Stateless regime classifier: maps (strength, angle, adx) onto an
// ENUM_TREND_TYPE label, plus the label predicates.
class CTrendRegime
{
public:
    //--- adx < 0 selects the synthetic (non-ADX) classification model.
    static ENUM_TREND_TYPE DetermineTrendType(double strength,
                                              double angle,
                                              double adx,
                                              const double trendThreshold,
                                              const double strongTrendThreshold);

    //--- Label predicates (pure functions of the regime label).
    static bool IsBullish(const ENUM_TREND_TYPE type);
    static bool IsBearish(const ENUM_TREND_TYPE type);
    static bool IsStrong(const ENUM_TREND_TYPE type);
    static bool IsRanging(const ENUM_TREND_TYPE type);
};

ENUM_TREND_TYPE CTrendRegime::DetermineTrendType(double strength,
                                                 double angle,
                                                 double adx,
                                                 const double trendThreshold,
                                                 const double strongTrendThreshold)
{
    bool useAdxModel = (adx >= 0.0);
    if(!useAdxModel)
    {
        if(strength >= 70.0 && angle > 10.0)
            return TREND_BULLISH_STRONG;
        if(strength >= 70.0 && angle < -10.0)
            return TREND_BEARISH_STRONG;
        if(strength >= 52.0 && angle > 5.0)
            return TREND_BULLISH_WEAK;
        if(strength >= 52.0 && angle < -5.0)
            return TREND_BEARISH_WEAK;
        if(strength < 35.0 && MathAbs(angle) < 6.0)
            return TREND_RANGING;
        if(strength < 45.0 && MathAbs(angle) > 18.0)
            return TREND_VOLATILE;
        if(strength < 50.0)
            return TREND_TRANSITIONING;
        return TREND_NONE;
    }

    // Strong trending conditions
    if(adx > strongTrendThreshold && strength > 70)
    {
        if(angle > 20)
            return TREND_BULLISH_STRONG;
        else if(angle < -20)
            return TREND_BEARISH_STRONG;
    }
    
    // Moderate trending conditions
    if(adx > trendThreshold && strength > 50)
    {
        if(angle > 10)
            return TREND_BULLISH_WEAK;
        else if(angle < -10)
            return TREND_BEARISH_WEAK;
    }
    
    // Ranging or volatile conditions
    if(adx < 20)
        return TREND_RANGING;
    
    if(strength < 30 && MathAbs(angle) > 30)
        return TREND_VOLATILE;
    
    // Transitioning
    if(strength < 50 && MathAbs(angle) < 10)
        return TREND_TRANSITIONING;
    
    return TREND_NONE;
}

// Check if Trend is Bullish
bool CTrendRegime::IsBullish(const ENUM_TREND_TYPE type)
{
    return type == TREND_BULLISH_STRONG || 
           type == TREND_BULLISH_WEAK;
}

// Check if Trend is Bearish
bool CTrendRegime::IsBearish(const ENUM_TREND_TYPE type)
{
    return type == TREND_BEARISH_STRONG || 
           type == TREND_BEARISH_WEAK;
}

// Check if Strong Trend
bool CTrendRegime::IsStrong(const ENUM_TREND_TYPE type)
{
    return type == TREND_BULLISH_STRONG || 
           type == TREND_BEARISH_STRONG;
}

// Check if Ranging
bool CTrendRegime::IsRanging(const ENUM_TREND_TYPE type)
{
    return type == TREND_RANGING;
}

#endif // TREND_REGIME_MQH
