//+------------------------------------------------------------------+
//| RegimeComposite.mqh                                              |
//| Composite regime scoring / labelling (stateless)                 |
//| Extracted verbatim from RegimeEngine.mqh (no behavior change)    |
//+------------------------------------------------------------------+
#ifndef REGIME_COMPOSITE_MQH
#define REGIME_COMPOSITE_MQH

#include "RegimeTypes.mqh"

//+------------------------------------------------------------------+
//| Pure functions mapping raw metrics onto regime labels, strategy  |
//| weight multipliers and human readable tags. No state is held.    |
//+------------------------------------------------------------------+
class CRegimeComposite
{
public:
    //--- Coarse regime tags
    static string RegimeToString(const ENUM_REGIME_STATE state);
    static string DetailedRegimeToString(const ENUM_DETAILED_REGIME regime);

    //--- Primary state machine used by CRegimeEngine::Update()
    static ENUM_REGIME_STATE ClassifyState(const bool cooldownActive,
                                           const double spreadToAtr,
                                           const double zScore,
                                           const bool compression,
                                           const double bbWidthAtrRatio,
                                           const SRegimeConfig &config,
                                           double &regimeConfidence);

    //--- Degraded-data estimate used when only fallback rates exist
    static ENUM_REGIME_STATE EstimateRegimeStateFromFallback(const string symbol,
                                                             const double atrValue,
                                                             const double bbUpperValue,
                                                             const double bbLowerValue,
                                                             const SRegimeConfig &config);

    //--- Multi-dimensional classification (Batch 93 - Week 5)
    static ENUM_DETAILED_REGIME CalculateDetailedRegime(double adxValue,
                                                        double zScore,
                                                        double bbWidthAtrRatio,
                                                        bool compression);

    static void CalculateStrategyWeightMultipliers(ENUM_DETAILED_REGIME regime,
                                                   double &momentumMult,
                                                   double &trendMult,
                                                   double &meanRevMult,
                                                   double &breakoutMult,
                                                   double &ictMult);

    //--- Batch 100: Hurst persistence overlay applied onto a snapshot
    static void ApplyHurstWeightModifiers(SRegimeSnapshot &snapshot,
                                          double hurstMeanRevMult,
                                          double hurstMomentumMult,
                                          double hurstTrendMult,
                                          double hurstBreakoutMult);
};

//+------------------------------------------------------------------+
//| Coarse regime tag                                                |
//+------------------------------------------------------------------+
string CRegimeComposite::RegimeToString(const ENUM_REGIME_STATE state)
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

//+------------------------------------------------------------------+
//| ENHANCEMENT: Convert detailed regime to string (Batch 93 - Wk 5) |
//+------------------------------------------------------------------+
string CRegimeComposite::DetailedRegimeToString(const ENUM_DETAILED_REGIME regime)
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

//+------------------------------------------------------------------+
//| Primary regime state + confidence scoring                        |
//+------------------------------------------------------------------+
ENUM_REGIME_STATE CRegimeComposite::ClassifyState(const bool cooldownActive,
                                                  const double spreadToAtr,
                                                  const double zScore,
                                                  const bool compression,
                                                  const double bbWidthAtrRatio,
                                                  const SRegimeConfig &config,
                                                  double &regimeConfidence)
{
    ENUM_REGIME_STATE state = REGIME_TREND;
    regimeConfidence = 0.5;

    if(cooldownActive || spreadToAtr > (config.maxSpreadToAtrRatio * 1.5))
    {
        state = REGIME_CHAOS;
        regimeConfidence = 0.9;
    }
    else if(MathAbs(zScore) >= config.breakoutZScoreThreshold && !compression)
    {
        state = REGIME_BREAKOUT;
        regimeConfidence = 0.7 + MathMin(0.3, (MathAbs(zScore) - config.breakoutZScoreThreshold) * 0.2);
    }
    else if(compression)
    {
        state = REGIME_RANGE;
        regimeConfidence = 0.6 + MathMin(0.3, (config.compressionRatioThreshold - bbWidthAtrRatio) * 0.1);
    }
    else
    {
        state = REGIME_TREND;
        regimeConfidence = 0.5 + MathMin(0.3, bbWidthAtrRatio * 0.1);
    }

    return state;
}

//+------------------------------------------------------------------+
//| L4-011 Fix: Estimate regime state from fallback indicators       |
//+------------------------------------------------------------------+
ENUM_REGIME_STATE CRegimeComposite::EstimateRegimeStateFromFallback(const string symbol,
                                                                    const double atrValue,
                                                                    const double bbUpperValue,
                                                                    const double bbLowerValue,
                                                                    const SRegimeConfig &config)
{
    // Get current spread
    double spreadPrice = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);

    double spreadToAtr = (atrValue > 0.0) ? (spreadPrice / atrValue) : 0.0;
    double bbWidth = bbUpperValue - bbLowerValue;
    double bbWidthAtrRatio = (atrValue > 0.0) ? (bbWidth / atrValue) : 0.0;

    // Simple regime estimation based on fallback data
    // Check for CHAOS (high spread)
    if(spreadToAtr > (config.maxSpreadToAtrRatio * 1.5))
        return REGIME_CHAOS;

    // Check for RANGE (compression)
    if(bbWidthAtrRatio < config.compressionRatioThreshold)
        return REGIME_RANGE;

    // Default to TREND
    return REGIME_TREND;
}

//+------------------------------------------------------------------+
//| ENHANCEMENT: Calculate Detailed Regime Classification            |
//+------------------------------------------------------------------+
ENUM_DETAILED_REGIME CRegimeComposite::CalculateDetailedRegime(double adxValue,
                                                               double zScore,
                                                               double bbWidthAtrRatio,
                                                               bool compression)
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

//+------------------------------------------------------------------+
//| ENHANCEMENT: Calculate Strategy-Specific Weight Multipliers      |
//+------------------------------------------------------------------+
void CRegimeComposite::CalculateStrategyWeightMultipliers(ENUM_DETAILED_REGIME regime,
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

//+------------------------------------------------------------------+
//| Batch 100: Apply Hurst exponent weight multipliers on top of     |
//| regime multipliers, in-place on the supplied snapshot.           |
//+------------------------------------------------------------------+
void CRegimeComposite::ApplyHurstWeightModifiers(SRegimeSnapshot &snapshot,
                                                 double hurstMeanRevMult,
                                                 double hurstMomentumMult,
                                                 double hurstTrendMult,
                                                 double hurstBreakoutMult)
{
    // Validate Hurst inputs — corrupted indicator handles can produce inf/NaN
    if(!MathIsValidNumber(hurstMeanRevMult) || hurstMeanRevMult < 0.01 || hurstMeanRevMult > 10.0)
        hurstMeanRevMult = 1.0;
    if(!MathIsValidNumber(hurstMomentumMult) || hurstMomentumMult < 0.01 || hurstMomentumMult > 10.0)
        hurstMomentumMult = 1.0;
    if(!MathIsValidNumber(hurstTrendMult) || hurstTrendMult < 0.01 || hurstTrendMult > 10.0)
        hurstTrendMult = 1.0;
    if(!MathIsValidNumber(hurstBreakoutMult) || hurstBreakoutMult < 0.01 || hurstBreakoutMult > 10.0)
        hurstBreakoutMult = 1.0;

    snapshot.meanRevWeightMult *= hurstMeanRevMult;
    snapshot.momentumWeightMult *= hurstMomentumMult;
    snapshot.trendWeightMult *= hurstTrendMult;
    snapshot.breakoutWeightMult *= hurstBreakoutMult;

    // Clamp all weight multipliers to sane bounds [0.01, 10.0]
    snapshot.meanRevWeightMult = MathMax(0.01, MathMin(10.0, snapshot.meanRevWeightMult));
    snapshot.momentumWeightMult = MathMax(0.01, MathMin(10.0, snapshot.momentumWeightMult));
    snapshot.trendWeightMult = MathMax(0.01, MathMin(10.0, snapshot.trendWeightMult));
    snapshot.breakoutWeightMult = MathMax(0.01, MathMin(10.0, snapshot.breakoutWeightMult));
    snapshot.ictWeightMult = MathMax(0.01, MathMin(10.0, snapshot.ictWeightMult));
}

#endif // REGIME_COMPOSITE_MQH
