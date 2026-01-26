//+------------------------------------------------------------------+
//|                                             PinBarDetector.mqh   |
//|                                  Pin Bar / Hammer Detection      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

#include "CandleAnalyzer.mqh"

enum ENUM_PIN_BAR_TYPE
{
    PIN_BAR_NONE = 0,
    PIN_BAR_BULLISH,
    PIN_BAR_BEARISH
};

struct SPinBar
{
    ENUM_PIN_BAR_TYPE type;
    datetime time;
    double nosePrice;
    double bodyPrice;
    double wickSize;
    double bodySize;
    double strength;
    bool atKeyLevel;
};

class CPinBarDetector
{
private:
    CCandleAnalyzer* m_analyzer;
    double m_minWickRatio;
    double m_maxBodyRatio;
    double m_minRangeATR;
    
public:
    CPinBarDetector() : m_analyzer(NULL), m_minWickRatio(2.5), m_maxBodyRatio(0.33), m_minRangeATR(0.5) {}
    
    void SetAnalyzer(CCandleAnalyzer* analyzer) { m_analyzer = analyzer; }
    
    bool DetectPinBar(int barIndex, SPinBar &pinBar)
    {
        if(m_analyzer == NULL) return false;
        
        SCandleProperties candle = m_analyzer.AnalyzeCandle(barIndex);
        
        double atr = m_analyzer.GetATR(14);
        if(candle.totalRange < atr * m_minRangeATR)
            return false;
        
        if(candle.bodyRatio > m_maxBodyRatio)
            return false;
        
        // BULLISH PIN BAR (Hammer)
        if(candle.lowerWick >= candle.body * m_minWickRatio &&
           candle.upperWick < candle.body * 0.5)
        {
            double closePosition = (candle.close - candle.low) / candle.totalRange;
            if(closePosition < 0.75)
                return false;
            
            pinBar.type = PIN_BAR_BULLISH;
            pinBar.time = candle.time;
            pinBar.nosePrice = candle.low;
            pinBar.bodyPrice = (candle.open + candle.close) / 2.0;
            pinBar.wickSize = candle.lowerWick;
            pinBar.bodySize = candle.body;
            pinBar.strength = CalculatePinBarStrength(candle, true);
            pinBar.atKeyLevel = false;
            
            return true;
        }
        
        // BEARISH PIN BAR (Shooting Star)
        else if(candle.upperWick >= candle.body * m_minWickRatio &&
                candle.lowerWick < candle.body * 0.5)
        {
            double closePosition = (candle.close - candle.low) / candle.totalRange;
            if(closePosition > 0.25)
                return false;
            
            pinBar.type = PIN_BAR_BEARISH;
            pinBar.time = candle.time;
            pinBar.nosePrice = candle.high;
            pinBar.bodyPrice = (candle.open + candle.close) / 2.0;
            pinBar.wickSize = candle.upperWick;
            pinBar.bodySize = candle.body;
            pinBar.strength = CalculatePinBarStrength(candle, false);
            pinBar.atKeyLevel = false;
            
            return true;
        }
        
        return false;
    }
    
private:
    double CalculatePinBarStrength(SCandleProperties &candle, bool isBullish)
    {
        double strength = 0.50;
        
        double wickRatio = isBullish ? 
            (candle.lowerWick / (candle.body + 0.000001)) : 
            (candle.upperWick / (candle.body + 0.000001));
        
        if(wickRatio >= 4.0)
            strength += 0.20;
        else if(wickRatio >= 3.0)
            strength += 0.15;
        else if(wickRatio >= 2.5)
            strength += 0.10;
        
        if(candle.bodyRatio < 0.15)
            strength += 0.15;
        else if(candle.bodyRatio < 0.25)
            strength += 0.10;
        
        double closePosition = (candle.close - candle.low) / candle.totalRange;
        if(isBullish && closePosition > 0.85)
            strength += 0.10;
        else if(!isBullish && closePosition < 0.15)
            strength += 0.10;
        
        return MathMin(1.0, strength);
    }
};
