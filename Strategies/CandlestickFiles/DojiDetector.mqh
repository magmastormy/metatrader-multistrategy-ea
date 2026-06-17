//+------------------------------------------------------------------+
//|                                             DojiDetector.mqh     |
//|                                  Doji Pattern Detection           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property strict

#include "CandleAnalyzer.mqh"

enum ENUM_DOJI_TYPE
{
    DOJI_NONE = 0,
    DOJI_STANDARD,      // Standard doji (very small body)
    DOJI_DRAGONFLY,     // Dragonfly doji (long lower wick, no upper wick)
    DOJI_GRAVESTONE     // Gravestone doji (long upper wick, no lower wick)
};

struct SDojiPattern
{
    ENUM_DOJI_TYPE type;
    datetime time;
    double patternPrice;
    double strength;
    bool isBullish;     // Dragonfly=bullish, Gravestone=bearish, Standard=neutral
};

class CDojiDetector
{
private:
    CCandleAnalyzer* m_analyzer;
    double m_maxBodyRatio;      // Max body/range ratio for doji (default 0.10)
    double m_minWickRatio;      // Min wick/body ratio for dragonfly/gravestone (default 2.0)

public:
    CDojiDetector() : m_analyzer(NULL), m_maxBodyRatio(0.10), m_minWickRatio(2.0) {}

    void SetAnalyzer(CCandleAnalyzer* analyzer) { m_analyzer = analyzer; }

    bool DetectDoji(int barIndex, SDojiPattern &doji)
    {
        if(m_analyzer == NULL) return false;

        SCandleProperties candle = m_analyzer.AnalyzeCandle(barIndex);

        // Must be a doji (very small body relative to range)
        if(candle.bodyRatio > m_maxBodyRatio)
            return false;

        double atr = m_analyzer.GetATR(14);
        if(candle.totalRange < atr * 0.3)  // Doji must have some range
            return false;

        // Dragonfly Doji: long lower wick, minimal upper wick
        if(candle.lowerWick >= candle.body * m_minWickRatio &&
           candle.upperWick < candle.totalRange * 0.10)
        {
            doji.type = DOJI_DRAGONFLY;
            doji.isBullish = true;
            doji.strength = CalculateDojiStrength(candle, true);
            doji.time = candle.time;
            doji.patternPrice = candle.low;
            return true;
        }

        // Gravestone Doji: long upper wick, minimal lower wick
        if(candle.upperWick >= candle.body * m_minWickRatio &&
           candle.lowerWick < candle.totalRange * 0.10)
        {
            doji.type = DOJI_GRAVESTONE;
            doji.isBullish = false;
            doji.strength = CalculateDojiStrength(candle, false);
            doji.time = candle.time;
            doji.patternPrice = candle.high;
            return true;
        }

        // Standard Doji: small body in the middle
        if(candle.bodyRatio <= m_maxBodyRatio)
        {
            doji.type = DOJI_STANDARD;
            // Direction based on context: if lower wick > upper wick, slightly bullish
            doji.isBullish = (candle.lowerWick > candle.upperWick);
            doji.strength = CalculateDojiStrength(candle, doji.isBullish);
            doji.time = candle.time;
            doji.patternPrice = candle.close;
            return true;
        }

        return false;
    }

private:
    double CalculateDojiStrength(SCandleProperties &candle, bool isBullish)
    {
        double strength = 0.50;

        // Smaller body = stronger doji signal
        if(candle.bodyRatio < 0.05)
            strength += 0.20;
        else if(candle.bodyRatio < 0.08)
            strength += 0.15;
        else
            strength += 0.05;

        // Longer wick in reversal direction = stronger
        double wickRatio = isBullish ? candle.lowerWickRatio : candle.upperWickRatio;
        if(wickRatio > 0.60)
            strength += 0.15;
        else if(wickRatio > 0.40)
            strength += 0.10;

        // Close near the wick end = stronger
        double closePosition = (candle.close - candle.low) / (candle.totalRange + 0.000001);
        if(isBullish && closePosition > 0.80)
            strength += 0.10;
        else if(!isBullish && closePosition < 0.20)
            strength += 0.10;

        return MathMin(1.0, strength);
    }
};
