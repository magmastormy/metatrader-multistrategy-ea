//+------------------------------------------------------------------+
//|                                              CandleAnalyzer.mqh  |
//|                                 Candlestick Pattern Recognition  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property link      ""
#property strict

#include "../../IndicatorManager.mqh"

//+------------------------------------------------------------------+
//| Candle Properties Structure                                       |
//+------------------------------------------------------------------+
struct SCandleProperties
{
    double open;
    double high;
    double low;
    double close;
    datetime time;
    long volume;
    
    double body;
    double upperWick;
    double lowerWick;
    double totalRange;
    
    double bodyRatio;
    double upperWickRatio;
    double lowerWickRatio;
    
    bool isBullish;
    bool isBearish;
    bool isDoji;
    double strength;
};

//+------------------------------------------------------------------+
//| Candle Analyzer Class                                            |
//+------------------------------------------------------------------+
class CCandleAnalyzer
{
private:
    string            m_symbol;
    ENUM_TIMEFRAMES   m_timeframe;
    int               m_atrHandle;
    
public:
    CCandleAnalyzer() : m_atrHandle(INVALID_HANDLE) {}
    ~CCandleAnalyzer() { /* ATR handle owned by CIndicatorManager — do NOT release here */ }
    
    bool Initialize(string symbol, ENUM_TIMEFRAMES timeframe)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        
        m_atrHandle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, 14);
        if(m_atrHandle == INVALID_HANDLE)
        {
            Print("[CandleAnalyzer] Failed to create ATR indicator");
            return false;
        }
        
        return true;
    }
    
    SCandleProperties AnalyzeCandle(int barIndex)
    {
        SCandleProperties candle;
        ZeroMemory(candle);
        
        candle.open = iOpen(m_symbol, m_timeframe, barIndex);
        candle.high = iHigh(m_symbol, m_timeframe, barIndex);
        candle.low = iLow(m_symbol, m_timeframe, barIndex);
        candle.close = iClose(m_symbol, m_timeframe, barIndex);
        candle.time = iTime(m_symbol, m_timeframe, barIndex);
        candle.volume = iVolume(m_symbol, m_timeframe, barIndex);
        
        candle.body = MathAbs(candle.close - candle.open);
        candle.upperWick = candle.high - MathMax(candle.open, candle.close);
        candle.lowerWick = MathMin(candle.open, candle.close) - candle.low;
        candle.totalRange = candle.high - candle.low;
        
        if(candle.totalRange > 0)
        {
            candle.bodyRatio = candle.body / candle.totalRange;
            candle.upperWickRatio = candle.upperWick / candle.totalRange;
            candle.lowerWickRatio = candle.lowerWick / candle.totalRange;
        }
        
        candle.isBullish = (candle.close > candle.open);
        candle.isBearish = (candle.close < candle.open);
        candle.isDoji = (candle.bodyRatio < 0.10);
        
        double atr = GetATR(14);
        if(atr > 0)
            candle.strength = candle.body / atr;
        
        return candle;
    }
    
    double GetATR(int period)
    {
        double atr[];
        ArraySetAsSeries(atr, true);
        
        if(CopyBuffer(m_atrHandle, 0, 0, 1, atr) <= 0)
            return 0.0;
        
        return atr[0];
    }
};
