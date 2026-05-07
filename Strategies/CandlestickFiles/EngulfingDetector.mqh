//+------------------------------------------------------------------+
//|                                          EngulfingDetector.mqh   |
//|                                   Engulfing Pattern Detection    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

#include "CandleAnalyzer.mqh"

struct SEngulfingPattern
{
    bool isBullish;
    datetime time;
    double engulfingOpen;
    double engulfingClose;
    double engulfedOpen;
    double engulfedClose;
    double strength;
    int barsEngulfed;
};

class CEngulfingDetector
{
private:
    CCandleAnalyzer* m_analyzer;
    
public:
    CEngulfingDetector() : m_analyzer(NULL) {}
    
    void SetAnalyzer(CCandleAnalyzer* analyzer) { m_analyzer = analyzer; }
    
    bool DetectEngulfing(int barIndex, SEngulfingPattern &pattern)
    {
        if(m_analyzer == NULL) return false;
        
        SCandleProperties current = m_analyzer.AnalyzeCandle(barIndex);
        SCandleProperties previous = m_analyzer.AnalyzeCandle(barIndex + 1);
        
        double atr = m_analyzer.GetATR(14);
        if(current.isDoji || previous.isDoji)
            return false;

        if(atr <= 0.0)
            return false;

        if(current.body < atr * 0.35 || previous.body < atr * 0.20)
            return false;

        if(current.bodyRatio < 0.55 || previous.bodyRatio < 0.35)
            return false;

        double bodyRatio = current.body / MathMax(previous.body, 0.000001);
        if(bodyRatio < 1.10)
            return false;

        double tolerance = MathMax(_Point * 2.0, atr * 0.02);
        
        // BULLISH ENGULFING
        if(current.isBullish && previous.isBearish)
        {
            if(current.open <= (previous.close + tolerance) &&
               current.close >= (previous.open - tolerance) &&
               current.close > previous.open &&
               current.body > previous.body &&
               current.lowerWickRatio <= 0.35 &&
               previous.upperWickRatio <= 0.55)
            {
                pattern.isBullish = true;
                pattern.time = current.time;
                pattern.engulfingOpen = current.open;
                pattern.engulfingClose = current.close;
                pattern.engulfedOpen = previous.open;
                pattern.engulfedClose = previous.close;
                pattern.barsEngulfed = CountBarsEngulfed(barIndex, true);
                pattern.strength = CalculateEngulfingStrength(current, previous, pattern.barsEngulfed);
                
                return true;
            }
        }
        
        // BEARISH ENGULFING
        else if(current.isBearish && previous.isBullish)
        {
            if(current.open >= (previous.close - tolerance) &&
               current.close <= (previous.open + tolerance) &&
               current.close < previous.open &&
               current.body > previous.body &&
               current.upperWickRatio <= 0.35 &&
               previous.lowerWickRatio <= 0.55)
            {
                pattern.isBullish = false;
                pattern.time = current.time;
                pattern.engulfingOpen = current.open;
                pattern.engulfingClose = current.close;
                pattern.engulfedOpen = previous.open;
                pattern.engulfedClose = previous.close;
                pattern.barsEngulfed = CountBarsEngulfed(barIndex, false);
                pattern.strength = CalculateEngulfingStrength(current, previous, pattern.barsEngulfed);
                
                return true;
            }
        }
        
        return false;
    }
    
private:
    int CountBarsEngulfed(int barIndex, bool isBullish)
    {
        SCandleProperties current = m_analyzer.AnalyzeCandle(barIndex);
        int count = 1;
        
        for(int i = barIndex + 2; i <= barIndex + 3; i++)
        {
            SCandleProperties prev = m_analyzer.AnalyzeCandle(i);
            
            if(isBullish)
            {
                if(current.close > prev.open && current.open < prev.close)
                    count++;
                else
                    break;
            }
            else
            {
                if(current.close < prev.open && current.open > prev.close)
                    count++;
                else
                    break;
            }
        }
        
        return count;
    }
    
    double CalculateEngulfingStrength(SCandleProperties &current, SCandleProperties &previous, int engulfed)
    {
        double strength = 0.60;
        
        double bodyRatio = current.body / (previous.body + 0.000001);
        if(bodyRatio >= 2.0)
            strength += 0.15;
        else if(bodyRatio >= 1.5)
            strength += 0.10;
        
        if(engulfed >= 3)
            strength += 0.15;
        else if(engulfed == 2)
            strength += 0.10;
        
        if(current.upperWickRatio < 0.15 && current.lowerWickRatio < 0.15)
            strength += 0.10;

        if(current.bodyRatio >= 0.70)
            strength += 0.05;
        
        return MathMin(1.0, strength);
    }
};
