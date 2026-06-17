//+------------------------------------------------------------------+
//|                                            HammerDetector.mqh    |
//|                            Hammer / Shooting Star Detection       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property strict

#include "CandleAnalyzer.mqh"

enum ENUM_HAMMER_TYPE
{
    HAMMER_NONE = 0,
    HAMMER_BULLISH,         // Hammer (bullish reversal at bottom)
    HAMMER_INVERTED,        // Inverted Hammer (bullish reversal at bottom)
    HAMMER_SHOOTING_STAR    // Shooting Star (bearish reversal at top)
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
        if(candle.totalRange < atr * 0.5)
            return false;

        // Hammer: small body at top, long lower wick
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

        // Inverted Hammer: small body at bottom, long upper wick
        if(candle.upperWick >= candle.body * m_minWickRatio &&
           candle.lowerWick <= candle.totalRange * m_maxUpperWickRatio &&
           candle.bodyRatio < 0.40)
        {
            hammer.type = HAMMER_INVERTED;
            hammer.isBullish = true;
            hammer.strength = CalculateHammerStrength(candle, true) * 0.85; // Slightly weaker
            hammer.time = candle.time;
            hammer.patternPrice = candle.low;
            return true;
        }

        // Shooting Star: small body at bottom, long upper wick (at top of trend)
        if(candle.upperWick >= candle.body * m_minWickRatio &&
           candle.lowerWick <= candle.totalRange * m_maxUpperWickRatio &&
           candle.bodyRatio < 0.40)
        {
            hammer.type = HAMMER_SHOOTING_STAR;
            hammer.isBullish = false;
            hammer.strength = CalculateHammerStrength(candle, false);
            hammer.time = candle.time;
            hammer.patternPrice = candle.high;
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

        // Small body = stronger
        if(candle.bodyRatio < 0.15)
            strength += 0.15;
        else if(candle.bodyRatio < 0.25)
            strength += 0.10;

        // Close near the body (top for hammer, bottom for shooting star)
        double closePosition = (candle.close - candle.low) / (candle.totalRange + 0.000001);
        if(isBullish && closePosition > 0.70)
            strength += 0.10;
        else if(!isBullish && closePosition < 0.30)
            strength += 0.10;

        return MathMin(1.0, strength);
    }
};
