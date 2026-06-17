//+------------------------------------------------------------------+
//|                                     ThreeSoldiersDetector.mqh    |
//|               Three White Soldiers / Three Black Crows Detection  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property strict

#include "CandleAnalyzer.mqh"

enum ENUM_THREE_SOLDIERS_TYPE
{
    THREE_SOLDIERS_NONE = 0,
    THREE_WHITE_SOLDIERS,      // Three White Soldiers (bullish)
    THREE_BLACK_CROWS          // Three Black Crows (bearish)
};

struct SThreeSoldiersPattern
{
    ENUM_THREE_SOLDIERS_TYPE type;
    datetime time;
    double patternPrice;
    double strength;
    bool isBullish;
};

class CThreeSoldiersDetector
{
private:
    CCandleAnalyzer* m_analyzer;
    double m_minBodyRatio;     // Min body/range for each candle (default 0.50)

public:
    CThreeSoldiersDetector() : m_analyzer(NULL), m_minBodyRatio(0.50) {}

    void SetAnalyzer(CCandleAnalyzer* analyzer) { m_analyzer = analyzer; }

    bool DetectThreeSoldiers(int barIndex, SThreeSoldiersPattern &soldiers)
    {
        if(m_analyzer == NULL) return false;

        SCandleProperties c1 = m_analyzer.AnalyzeCandle(barIndex + 2);
        SCandleProperties c2 = m_analyzer.AnalyzeCandle(barIndex + 1);
        SCandleProperties c3 = m_analyzer.AnalyzeCandle(barIndex);

        double atr = m_analyzer.GetATR(14);
        if(atr <= 0) return false;

        // Three White Soldiers: 3 consecutive bullish candles
        if(c1.isBullish && c2.isBullish && c3.isBullish &&
           c1.bodyRatio >= m_minBodyRatio && c2.bodyRatio >= m_minBodyRatio && c3.bodyRatio >= m_minBodyRatio &&
           c2.close > c1.close && c3.close > c2.close &&
           c2.open >= c1.open && c3.open >= c2.open)  // Each opens within previous body
        {
            soldiers.type = THREE_WHITE_SOLDIERS;
            soldiers.isBullish = true;
            soldiers.strength = CalculateThreeSoldiersStrength(c1, c2, c3, true);
            soldiers.time = c3.time;
            soldiers.patternPrice = c3.close;
            return true;
        }

        // Three Black Crows: 3 consecutive bearish candles
        if(c1.isBearish && c2.isBearish && c3.isBearish &&
           c1.bodyRatio >= m_minBodyRatio && c2.bodyRatio >= m_minBodyRatio && c3.bodyRatio >= m_minBodyRatio &&
           c2.close < c1.close && c3.close < c2.close &&
           c2.open <= c1.open && c3.open <= c2.open)
        {
            soldiers.type = THREE_BLACK_CROWS;
            soldiers.isBullish = false;
            soldiers.strength = CalculateThreeSoldiersStrength(c1, c2, c3, false);
            soldiers.time = c3.time;
            soldiers.patternPrice = c3.close;
            return true;
        }

        return false;
    }

private:
    double CalculateThreeSoldiersStrength(SCandleProperties &c1, SCandleProperties &c2, SCandleProperties &c3, bool isBullish)
    {
        double strength = 0.55;

        // Progressive closes = stronger
        double totalMove = MathAbs(c3.close - c1.open);
        double avgBody = (c1.body + c2.body + c3.body) / 3.0;
        if(totalMove > avgBody * 2.5)
            strength += 0.15;
        else if(totalMove > avgBody * 2.0)
            strength += 0.10;

        // Consistent body sizes = stronger
        double maxBody = MathMax(MathMax(c1.body, c2.body), c3.body);
        double minBody = MathMin(MathMin(c1.body, c2.body), c3.body);
        if(maxBody > 0 && minBody / maxBody > 0.70)
            strength += 0.15;
        else if(maxBody > 0 && minBody / maxBody > 0.50)
            strength += 0.10;

        // Small wicks = stronger conviction
        double avgWickRatio = (c1.upperWickRatio + c2.upperWickRatio + c3.upperWickRatio) / 3.0;
        if(avgWickRatio < 0.15)
            strength += 0.10;

        return MathMin(1.0, strength);
    }
};
