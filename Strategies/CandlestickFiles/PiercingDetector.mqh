//+------------------------------------------------------------------+
//|                                        PiercingDetector.mqh      |
//|               Piercing Line / Dark Cloud Cover Detection          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property strict

#include "CandleAnalyzer.mqh"

enum ENUM_PIERCING_TYPE
{
    PIERCING_NONE = 0,
    PIERCING_LINE,          // Piercing Line (bullish reversal)
    PIERCING_DARK_CLOUD     // Dark Cloud Cover (bearish reversal)
};

struct SPiercingPattern
{
    ENUM_PIERCING_TYPE type;
    datetime time;
    double patternPrice;
    double strength;
    bool isBullish;
};

class CPiercingDetector
{
private:
    CCandleAnalyzer* m_analyzer;
    double m_minBodyRatio;     // Min body/range for both candles (default 0.40)
    double m_piercingDepth;    // Min penetration depth for piercing line (default 0.50 of first body)

public:
    CPiercingDetector() : m_analyzer(NULL), m_minBodyRatio(0.40), m_piercingDepth(0.50) {}

    void SetAnalyzer(CCandleAnalyzer* analyzer) { m_analyzer = analyzer; }

    bool DetectPiercing(int barIndex, SPiercingPattern &piercing)
    {
        if(m_analyzer == NULL) return false;

        SCandleProperties c1 = m_analyzer.AnalyzeCandle(barIndex + 1); // First candle
        SCandleProperties c2 = m_analyzer.AnalyzeCandle(barIndex);     // Second candle

        double atr = m_analyzer.GetATR(14);
        if(atr <= 0) return false;
        if(c1.totalRange < atr * 0.5 || c2.totalRange < atr * 0.5)
            return false;

        // Piercing Line: bearish candle + bullish candle that opens below and closes above midpoint
        if(c1.isBearish && c2.isBullish &&
           c1.bodyRatio >= m_minBodyRatio && c2.bodyRatio >= m_minBodyRatio)
        {
            double c1Midpoint = (c1.open + c1.close) / 2.0;
            // Second candle opens below first candle's close and closes above midpoint
            if(c2.open < c1.close && c2.close > c1Midpoint && c2.close < c1.open)
            {
                piercing.type = PIERCING_LINE;
                piercing.isBullish = true;
                piercing.strength = CalculatePiercingStrength(c1, c2, true);
                piercing.time = c2.time;
                piercing.patternPrice = c2.close;
                return true;
            }
        }

        // Dark Cloud Cover: bullish candle + bearish candle that opens above and closes below midpoint
        if(c1.isBullish && c2.isBearish &&
           c1.bodyRatio >= m_minBodyRatio && c2.bodyRatio >= m_minBodyRatio)
        {
            double c1Midpoint = (c1.open + c1.close) / 2.0;
            // Second candle opens above first candle's close and closes below midpoint
            if(c2.open > c1.close && c2.close < c1Midpoint && c2.close > c1.open)
            {
                piercing.type = PIERCING_DARK_CLOUD;
                piercing.isBullish = false;
                piercing.strength = CalculatePiercingStrength(c1, c2, false);
                piercing.time = c2.time;
                piercing.patternPrice = c2.close;
                return true;
            }
        }

        return false;
    }

private:
    double CalculatePiercingStrength(SCandleProperties &c1, SCandleProperties &c2, bool isBullish)
    {
        double strength = 0.50;

        // Deeper penetration = stronger signal
        double c1Midpoint = (c1.open + c1.close) / 2.0;
        double c1BodySize = MathAbs(c1.open - c1.close);
        if(c1BodySize > 0)
        {
            double penetration = MathAbs(c2.close - c1Midpoint) / c1BodySize;
            if(penetration > 0.60)
                strength += 0.20;
            else if(penetration > 0.40)
                strength += 0.15;
            else
                strength += 0.05;
        }

        // Larger second candle body = stronger
        if(c2.bodyRatio >= 0.70)
            strength += 0.15;
        else if(c2.bodyRatio >= 0.50)
            strength += 0.10;

        // Gap at open = stronger
        double gapSize = isBullish ? (c1.close - c2.open) : (c2.open - c1.close);
        double atr = m_analyzer.GetATR(14);
        if(atr > 0 && gapSize > atr * 0.10)
            strength += 0.10;

        return MathMin(1.0, strength);
    }
};
