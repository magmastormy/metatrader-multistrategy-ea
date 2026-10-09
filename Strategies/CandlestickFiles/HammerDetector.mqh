#property copyright "Copyright 2026"
#property strict

#include "CandleAnalyzer.mqh"

enum ENUM_HAMMER_TYPE
{
    HAMMER_NONE = 0,
    HAMMER_BULLISH,         // bullish, at the bottom
    HAMMER_INVERTED,        // also bullish, at the bottom
    HAMMER_SHOOTING_STAR    // bearish, at the top
};

struct SHammerPattern
{
    ENUM_HAMMER_TYPE type;
    datetime time;
    double patternPrice;
    double strength;
    bool isBullish;
};

class CHammerDetector
{
private:
    CCandleAnalyzer* m_analyzer;
    double m_minWickRatio;      // Min wick/body ratio (default 2.0)
    double m_maxUpperWickRatio; // Max upper wick for hammer (default 0.25 of range)

public:
    CHammerDetector() : m_analyzer(NULL), m_minWickRatio(2.0), m_maxUpperWickRatio(0.25) {}

    void SetAnalyzer(CCandleAnalyzer* analyzer) { m_analyzer = analyzer; }

    bool DetectHammer(int barIndex, SHammerPattern &hammer)
    {
        if(m_analyzer == NULL) return false;

        SCandleProperties candle = m_analyzer.AnalyzeCandle(barIndex);

        double atr = m_analyzer.GetATR(14);
        // Fail CLOSED during ATR warmup, like the other detectors: an unnormalized
        // gate lets warmup noise vote into consensus.
        if(atr <= 0 || candle.totalRange < atr * 0.5)
            return false;

        if(candle.lowerWick >= candle.body * m_minWickRatio &&
           candle.upperWick <= candle.totalRange * m_maxUpperWickRatio &&
           candle.bodyRatio < 0.40)
        {
            hammer.type = HAMMER_BULLISH;
            hammer.isBullish = true;
            hammer.strength = CalculateHammerStrength(candle, true);
            hammer.time = candle.time;
            hammer.patternPrice = candle.low;
            return true;
        }

        // Identical geometry: only prior trend separates them - rising closes into the pattern
        // => Shooting Star (bearish), otherwise Inverted Hammer (bullish). Without that trend
        // check the Shooting Star path is unreachable and tops get voted as BUYs.
        if(candle.upperWick >= candle.body * m_minWickRatio &&
           candle.lowerWick <= candle.totalRange * m_maxUpperWickRatio &&
           candle.bodyRatio < 0.40)
        {
            double cPrev   = iClose(m_analyzer.GetSymbol(), m_analyzer.GetTimeframe(), barIndex + 1);
            double cBefore = iClose(m_analyzer.GetSymbol(), m_analyzer.GetTimeframe(), barIndex + 4);
            bool risingIntoPattern = (cPrev > 0 && cBefore > 0 && cPrev > cBefore);

            hammer.time = candle.time;
            // Score the dominant (upper) wick for both shapes: scoring the tiny lower wick
            // deflates inverted-hammer strength below tradeable floors.
            hammer.strength = CalculateHammerStrength(candle, false);
            if(risingIntoPattern)
            {
                hammer.type = HAMMER_SHOOTING_STAR;
                hammer.isBullish = false;
                hammer.patternPrice = candle.high;
            }
            else
            {
                hammer.type = HAMMER_INVERTED;
                hammer.isBullish = true;
                hammer.strength *= 0.85; // inverted hammer is the weaker counter-shape
                hammer.patternPrice = candle.low;
            }
            return true;
        }

        return false;
    }

private:
    double CalculateHammerStrength(SCandleProperties &candle, bool isBullish)
    {
        double strength = 0.50;

        double wickRatio = isBullish ?
            (candle.lowerWick / (candle.body + 0.000001)) :
            (candle.upperWick / (candle.body + 0.000001));

        if(wickRatio >= 4.0)
            strength += 0.20;
        else if(wickRatio >= 3.0)
            strength += 0.15;
        else if(wickRatio >= 2.0)
            strength += 0.10;

        if(candle.bodyRatio < 0.15)
            strength += 0.15;
        else if(candle.bodyRatio < 0.25)
            strength += 0.10;

        // Bonus when the close sits in the top 30% (hammer) or bottom 30% (shooting star)
        double closePosition = (candle.close - candle.low) / (candle.totalRange + 0.000001);
        if(isBullish && closePosition > 0.70)
            strength += 0.10;
        else if(!isBullish && closePosition < 0.30)
            strength += 0.10;

        return MathMin(1.0, strength);
    }
};
