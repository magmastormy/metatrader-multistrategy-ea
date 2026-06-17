//+------------------------------------------------------------------+
//|                                          HaramiDetector.mqh      |
//|                      Bullish / Bearish Harami Detection           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property strict

#include "CandleAnalyzer.mqh"

enum ENUM_HARAMI_TYPE
{
    HARAMI_NONE = 0,
    HARAMI_BULLISH,     // Bullish Harami (reversal up)
    HARAMI_BEARISH      // Bearish Harami (reversal down)
};

struct SHaramiPattern
{
    ENUM_HARAMI_TYPE type;
    datetime time;
    double patternPrice;
    double strength;
    bool isBullish;
};

class CHaramiDetector
{
private:
    CCandleAnalyzer* m_analyzer;
    double m_minFirstBodyRatio;     // Min body/range for mother candle (default 0.40)
    double m_maxSecondBodyRatio;    // Max body/range relative to first (default 0.60 of first body)

public:
    CHaramiDetector() : m_analyzer(NULL), m_minFirstBodyRatio(0.40), m_maxSecondBodyRatio(0.60) {}

    void SetAnalyzer(CCandleAnalyzer* analyzer) { m_analyzer = analyzer; }

    bool DetectHarami(int barIndex, SHaramiPattern &harami)
    {
        if(m_analyzer == NULL) return false;

        // 2-candle pattern: barIndex+1 (mother), barIndex (child)
        SCandleProperties mother = m_analyzer.AnalyzeCandle(barIndex + 1);
        SCandleProperties child = m_analyzer.AnalyzeCandle(barIndex);

        double atr = m_analyzer.GetATR(14);
        if(atr <= 0) return false;
        if(mother.totalRange < atr * 0.5) return false;

        // Mother candle must have substantial body
        if(mother.bodyRatio < m_minFirstBodyRatio)
            return false;

        // Bullish Harami: bearish mother + bullish child inside mother's body
        if(mother.isBearish && child.isBullish)
        {
            if(child.open >= mother.close && child.close <= mother.open &&
               child.body <= mother.body * m_maxSecondBodyRatio)
            {
                harami.type = HARAMI_BULLISH;
                harami.isBullish = true;
                harami.strength = CalculateHaramiStrength(mother, child, true);
                harami.time = child.time;
                harami.patternPrice = child.close;
                return true;
            }
        }

        // Bearish Harami: bullish mother + bearish child inside mother's body
        if(mother.isBullish && child.isBearish)
        {
            if(child.close >= mother.open && child.open <= mother.close &&
               child.body <= mother.body * m_maxSecondBodyRatio)
            {
                harami.type = HARAMI_BEARISH;
                harami.isBullish = false;
                harami.strength = CalculateHaramiStrength(mother, child, false);
                harami.time = child.time;
                harami.patternPrice = child.close;
                return true;
            }
        }

        return false;
    }

private:
    double CalculateHaramiStrength(SCandleProperties &mother, SCandleProperties &child, bool isBullish)
    {
        double strength = 0.50;

        // Smaller child relative to mother = stronger signal
        double childRatio = child.body / (mother.body + 0.000001);
        if(childRatio < 0.30)
            strength += 0.20;
        else if(childRatio < 0.50)
            strength += 0.10;

        // Larger mother candle = stronger signal
        if(mother.bodyRatio >= 0.70)
            strength += 0.15;
        else if(mother.bodyRatio >= 0.50)
            strength += 0.10;

        // Child centered within mother's body
        double motherMid = (mother.open + mother.close) / 2.0;
        double childMid = (child.open + child.close) / 2.0;
        double motherBodySize = MathAbs(mother.open - mother.close);
        if(motherBodySize > 0 && MathAbs(childMid - motherMid) / motherBodySize < 0.30)
            strength += 0.10;

        return MathMin(1.0, strength);
    }
};
