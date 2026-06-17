//+------------------------------------------------------------------+
//|                                              StarDetector.mqh    |
//|                     Morning Star / Evening Star Detection         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property strict

#include "CandleAnalyzer.mqh"

enum ENUM_STAR_TYPE
{
    STAR_NONE = 0,
    STAR_MORNING,       // Morning Star (bullish reversal)
    STAR_EVENING        // Evening Star (bearish reversal)
};

struct SStarPattern
{
    ENUM_STAR_TYPE type;
    datetime time;
    double patternPrice;
    double strength;
    bool isBullish;
};

class CStarDetector
{
private:
    CCandleAnalyzer* m_analyzer;
    double m_minFirstBodyRatio;    // Min body/range for first candle (default 0.50)
    double m_maxSecondBodyRatio;   // Max body/range for star candle (default 0.15)

public:
    CStarDetector() : m_analyzer(NULL), m_minFirstBodyRatio(0.50), m_maxSecondBodyRatio(0.15) {}

    void SetAnalyzer(CCandleAnalyzer* analyzer) { m_analyzer = analyzer; }

    bool DetectStar(int barIndex, SStarPattern &star)
    {
        if(m_analyzer == NULL) return false;

        // 3-candle pattern: barIndex+2, barIndex+1, barIndex
        SCandleProperties candle1 = m_analyzer.AnalyzeCandle(barIndex + 2); // First candle
        SCandleProperties candle2 = m_analyzer.AnalyzeCandle(barIndex + 1); // Star candle
        SCandleProperties candle3 = m_analyzer.AnalyzeCandle(barIndex);     // Confirmation

        double atr = m_analyzer.GetATR(14);
        if(atr <= 0) return false;

        // Morning Star: bearish candle + small body + bullish candle
        if(candle1.isBearish && candle1.bodyRatio >= m_minFirstBodyRatio &&
           candle2.bodyRatio <= m_maxSecondBodyRatio &&
           candle3.isBullish && candle3.bodyRatio >= 0.30)
        {
            // Star candle should gap down from first candle
            double gapDown = candle1.close - candle2.high;
            // Confirmation candle should close above first candle midpoint
            double midCandle1 = (candle1.open + candle1.close) / 2.0;

            if(candle3.close > midCandle1)
            {
                star.type = STAR_MORNING;
                star.isBullish = true;
                star.strength = CalculateStarStrength(candle1, candle2, candle3, true);
                star.time = candle3.time;
                star.patternPrice = candle3.close;
                return true;
            }
        }

        // Evening Star: bullish candle + small body + bearish candle
        if(candle1.isBullish && candle1.bodyRatio >= m_minFirstBodyRatio &&
           candle2.bodyRatio <= m_maxSecondBodyRatio &&
           candle3.isBearish && candle3.bodyRatio >= 0.30)
        {
            // Confirmation candle should close below first candle midpoint
            double midCandle1 = (candle1.open + candle1.close) / 2.0;

            if(candle3.close < midCandle1)
            {
                star.type = STAR_EVENING;
                star.isBullish = false;
                star.strength = CalculateStarStrength(candle1, candle2, candle3, false);
                star.time = candle3.time;
                star.patternPrice = candle3.close;
                return true;
            }
        }

        return false;
    }

private:
    double CalculateStarStrength(SCandleProperties &c1, SCandleProperties &c2, SCandleProperties &c3, bool isBullish)
    {
        double strength = 0.55;

        // Smaller star candle body = stronger signal
        if(c2.bodyRatio < 0.05)
            strength += 0.15;
        else if(c2.bodyRatio < 0.10)
            strength += 0.10;

        // Stronger confirmation candle = stronger signal
        if(c3.bodyRatio >= 0.60)
            strength += 0.15;
        else if(c3.bodyRatio >= 0.40)
            strength += 0.10;

        // Confirmation closes past first candle midpoint
        double midC1 = (c1.open + c1.close) / 2.0;
        if(isBullish && c3.close > midC1)
            strength += 0.10;
        else if(!isBullish && c3.close < midC1)
            strength += 0.10;

        return MathMin(1.0, strength);
    }
};
