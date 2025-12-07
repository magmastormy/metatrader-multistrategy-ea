// #import  // Removed unnecessary or erroneous import
//+------------------------------------------------------------------+
//| Fibonacci Strategy Module                                       |
//| Copyright 2025, Your Company Name                                |
//| https://www.yoursite.com                                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Company Name"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#ifndef __STRATEGY_FIBONACCI_MQH__
#define __STRATEGY_FIBONACCI_MQH__

// Include standard MQL5 libraries
#include <Object.mqh>
#include <Arrays\ArrayObj.mqh>
#include <Charts\Chart.mqh>
#include <Trade\Trade.mqh>
#include <ChartObjects\ChartObjectsShapes.mqh>
#include <ChartObjects\ChartObjectsTxtControls.mqh>
#include <Math\Stat\Math.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include "../Include/Indicators/Oscillators.mqh"
#include "RSI.mqh"  // Local RSI implementation

// Include project headers
#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Utils/Enums.mqh"
#include "../Interfaces/IStrategy.mqh"
#include "../Utilities/Utilities.mqh"

// Fibonacci level types
enum ENUM_FIB_LEVEL_TYPE
{
    FIB_LEVEL_RETRACEMENT = 0,
    FIB_LEVEL_EXTENSION,
    FIB_LEVEL_PROJECTION,
    FIB_LEVEL_EXPANSION
};

// Fibonacci level values
enum ENUM_FIB_LEVEL
{
    FIB_236 = 0,
    FIB_382 = 1,
    FIB_500 = 2,
    FIB_618 = 3,
    FIB_786 = 4,
    FIB_1000 = 5,
    FIB_1618 = 6,
    FIB_2618 = 7,
    FIB_4236 = 8
};

class SFibonacciLevel : public CObject
{
public:
    double            price;
    ENUM_FIB_LEVEL    level;
    ENUM_FIB_LEVEL_TYPE type;
    datetime          time;
    int               strength;
    bool              isActive;
    ENUM_TIMEFRAMES   timeframe;

    SFibonacciLevel() : price(0.0), level(FIB_236), type(FIB_LEVEL_RETRACEMENT), 
                       time(0), strength(0), isActive(false), timeframe(PERIOD_CURRENT) {}

    SFibonacciLevel(double p, ENUM_TIMEFRAMES tf, ENUM_FIB_LEVEL lvl, 
                   ENUM_FIB_LEVEL_TYPE t = FIB_LEVEL_RETRACEMENT, 
                   int str = 0, bool active = true) :
        price(p), level(lvl), type(t), time(TimeCurrent()), 
        strength(str), isActive(active), timeframe(tf) {}
};

class CStrategyFibonacci : public CStrategyBase
{
private:
    CArrayObj*       m_fibLevels;
    int              m_lookback;
    double           m_activationPips;
    bool             m_usePinBars;
    double           m_pinBarRatio;

    bool FindSwingPoints(const string symbol, const ENUM_TIMEFRAMES timeframe);
    void DrawFibLevel(double price, ENUM_TIMEFRAMES timeframe, ENUM_FIB_LEVEL level, color clr);
    bool IsPinBar(const MqlRates &curr, const MqlRates &prev, bool &isBullish);
    double NormalizeSignal(double value, double min_val, double max_val);
    double GetFibLevelValue(ENUM_FIB_LEVEL level) const;
    
public:
    CStrategyFibonacci(const string name, int magic);
    virtual ~CStrategyFibonacci();
    
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer);
    virtual void Deinit();
    virtual void OnTick();
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe);
    
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        if(!IsEnabled() || !m_is_initialized) {
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }

        // Calculate signal logic directly here or call a helper
        // Using the existing logic from GetSignalValue but adapted
        
        if (!POINTER_VALID(m_fibLevels) || m_fibLevels.Total() == 0)
        {
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }
        
        double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
        double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        if(point == 0) point = 0.0001;
        
        double activationDistance = m_activationPips * point;
        
        for(int i = 0; i < m_fibLevels.Total(); i++) {
            SFibonacciLevel *level = (SFibonacciLevel*)m_fibLevels.At(i);
            if(!level || level.timeframe != m_timeframe) continue;
            
            if(m_symbol == _Symbol && m_timeframe == _Period) {
                color clr = clrGray;
                switch(level.level) {  
                    case FIB_618: clr = clrGold; break;
                    case FIB_500: clr = clrGoldenrod; break;
                    case FIB_382: clr = clrDarkGoldenrod; break;
                }
                DrawFibLevel(level.price, level.timeframe, level.level, clr);
            }
            
            double distance = MathAbs(bid - level.price);
            
            if(distance < activationDistance) {
                MqlRates recentRates[3];
                if(CopyRates(m_symbol, m_timeframe, 0, 3, recentRates) != 3) continue;
                
                bool isBullishPin = false;
                bool isPinBar = IsPinBar(recentRates[1], recentRates[2], isBullishPin);
                
                if((level.level == FIB_618 || level.level == FIB_500) && bid > level.price) {
                    if((m_usePinBars && isPinBar && isBullishPin)) {
                        confidence = NormalizeSignal(1.0 - (distance / activationDistance), 0.5, 0.9);
                        return TRADE_SIGNAL_BUY;
                    }
                }
                else if((level.level == FIB_618 || level.level == FIB_500) && ask < level.price) {
                    if((m_usePinBars && isPinBar && !isBullishPin)) {
                        confidence = NormalizeSignal(1.0 - (distance / activationDistance), 0.5, 0.9);
                        return TRADE_SIGNAL_SELL;
                    }
                }
            }
        }
        
        confidence = 0.0;
        return TRADE_SIGNAL_NONE;
    }
    
    virtual double GetSignalValue(const string symbol, const ENUM_TIMEFRAMES timeframe, double &confidence)
    {
        // Deprecated
        return 0.0;
    }
    
    void SetLookback(int bars) { m_lookback = bars; }
    void SetActivationPips(double pips) { m_activationPips = pips; }
    void SetUsePinBars(bool use) { m_usePinBars = use; }
    void SetPinBarRatio(double ratio) { m_pinBarRatio = ratio; }
    
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_FIBONACCI; }
};

CStrategyFibonacci::CStrategyFibonacci(const string name, int magic) :
    CStrategyBase(name, magic),
    m_lookback(100),
    m_activationPips(10.0),
    m_usePinBars(true),
    m_pinBarRatio(2.5)
{
    m_fibLevels = new CArrayObj();
    // CArrayObj defaults to owning objects (FreeMode = true)
}

CStrategyFibonacci::~CStrategyFibonacci()
{
    if (CheckPointer(m_fibLevels) == POINTER_DYNAMIC)
    {
        delete m_fibLevels;
        m_fibLevels = NULL;
    }
}

bool CStrategyFibonacci::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer)
{
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
        return false;
        
    return true;
}

void CStrategyFibonacci::Deinit()
{
    if (m_fibLevels != NULL)
    { 
        for (int i = 0; i < m_fibLevels.Total(); i++)
        {
            SFibonacciLevel *level = (SFibonacciLevel*)m_fibLevels.At(i);
            if (level != NULL)
            {
                string name = "Fib_" + EnumToString(level.level) + "_" + TimeToString(level.time);
                ObjectDelete(0, name);
            }
        }
        m_fibLevels.Clear();
    }
    
    CStrategyBase::Deinit();
}

bool CStrategyFibonacci::IsPinBar(const MqlRates &curr, const MqlRates &prev, bool &isBullish)
{
    double bodySize = MathAbs(curr.close - curr.open);
    double upperWick = curr.high - MathMax(curr.open, curr.close);
    double lowerWick = MathMin(curr.open, curr.close) - curr.low;
    double totalSize = curr.high - curr.low;

    if (totalSize < _Point * 10) return false;

    isBullish = (lowerWick > bodySize * m_pinBarRatio && upperWick < bodySize);
    bool isBearish = (upperWick > bodySize * m_pinBarRatio && lowerWick < bodySize);

    return isBullish || isBearish;
}

double CStrategyFibonacci::NormalizeSignal(double value, double min_val, double max_val)
{
    if (value <= min_val) return 0.0;
    if (value >= max_val) return 1.0;
    return (value - min_val) / (max_val - min_val);
}

double CStrategyFibonacci::GetFibLevelValue(ENUM_FIB_LEVEL level) const
{
    switch (level)
    {
        case FIB_236: return 0.236;
        case FIB_382: return 0.382;
        case FIB_500: return 0.500;
        case FIB_618: return 0.618;
        case FIB_786: return 0.786;
        case FIB_1000: return 1.000;
        case FIB_1618: return 1.618;
        case FIB_2618: return 2.618;
        case FIB_4236: return 4.236;
        default: return 0.0;
    }
}

bool CStrategyFibonacci::FindSwingPoints(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if (!CheckPointer(m_fibLevels)) return false;

    for (int i = m_fibLevels.Total() - 1; i >= 0; i--)
    {
        SFibonacciLevel *level = (SFibonacciLevel*)m_fibLevels.At(i);
        if(level != NULL && level.timeframe == timeframe)
        {
            m_fibLevels.Delete(i);
        }
    }

    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(symbol, timeframe, 0, m_lookback, rates);
    if (copied <= 5) // Need at least 5 bars for swing detection
    {
        return false;
    }
    
    // Optimize: only check for major swings
    for (int i = copied - 3; i > 2; i--)
    {
        // Swing High
        if (rates[i].high > rates[i-1].high && rates[i].high > rates[i+1].high &&
            rates[i].high > rates[i-2].high && rates[i].high > rates[i+2].high)
        {
            for (int j = i - 1; j > 2; j--)
            {
                // Swing Low
                if (rates[j].low < rates[j-1].low && rates[j].low < rates[j+1].low &&
                    rates[j].low < rates[j-2].low && rates[j].low < rates[j+2].low)
                {
                    double high = rates[i].high;
                    double low = rates[j].low;
                    
                    for (int k = 0; k <= FIB_786; k++)
                    {
                        double levelValue = GetFibLevelValue((ENUM_FIB_LEVEL)k);
                        double price = high - (high - low) * levelValue;
                        m_fibLevels.Add(new SFibonacciLevel(price, timeframe, (ENUM_FIB_LEVEL)k));
                    }
                    i = j; // Skip processed bars
                    break;
                }
            }
        }
    }
    
    return true;
}

void CStrategyFibonacci::DrawFibLevel(double price, ENUM_TIMEFRAMES timeframe, ENUM_FIB_LEVEL level, color clr)
{
    string name = "Fib_" + EnumToString(level) + "_" + EnumToString(timeframe);
    if (ObjectFind(0, name) >= 0)
    {
        ObjectDelete(0, name);
    }

    if (!ObjectCreate(0, name, OBJ_HLINE, 0, 0, price))
    {
        return;
    }

    ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
    ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
    
    string label = EnumToString(level) + " (" + DoubleToString(price, _Digits) + ")";
    ObjectSetString(0, name, OBJPROP_TEXT, label);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT);
    ObjectSetDouble(0, name, OBJPROP_ANGLE, 0);
}

void CStrategyFibonacci::OnTick()
{
}

void CStrategyFibonacci::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if (!IsEnabled())
        return;
    FindSwingPoints(symbol, timeframe);
}

#endif
