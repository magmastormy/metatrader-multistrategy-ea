// #import  // Removed unnecessary or erroneous import
//+------------------------------------------------------------------+
//|                                                      StrategyOrderBlockFVG.mqh |
//|                                 Copyright 2024, Your Company Name              |
//|                                             https://www.yourwebsite.com       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Your Company Name"
#property link      "https://www.yourwebsite.com"
#property version   "1.00"
#property strict

#ifndef __STRATEGY_ORDERBLOCK_FVG_MQH__
#define __STRATEGY_ORDERBLOCK_FVG_MQH__

// Include necessary MQL5 standard library headers
#include <Trade\SymbolInfo.mqh>
// #include "../Include/Indicators/Trend.mqh"
#include "../Include/Indicators/Oscillators.mqh"
// #include "../Include/Indicators/Indicators.mqh"
#include <Charts\Chart.mqh>
#include <Object.mqh>
#include <Arrays\ArrayObj.mqh>
#include <ChartObjects\ChartObjectsShapes.mqh>
#include <ChartObjects\ChartObjectsTxtControls.mqh>
#include <Math\Stat\Math.mqh>

// Include project headers
#include "../Core/StrategyBase.mqh"
#include "../Core/Enums.mqh"
#include "../Interfaces/IStrategy.mqh"
#include "../Core/TradeManager.mqh"
#include "../Core/PositionSizer.mqh"
#include "../Core/ErrorHandling.mqh"
#include "../Core/StrategyFactory.mqh"



//+------------------------------------------------------------------+
//| Factory for creating this strategy                               |
//+------------------------------------------------------------------+


// Place this at the top of the file, after includes:
#define MAX_OBFVG 100

//+------------------------------------------------------------------+
//| Order Block & FVG Strategy Class                                 |
//+------------------------------------------------------------------+
class CStrategyOrderBlockFVG : public CStrategyBase
{
private:
    // Order Block/FVG structure
    struct SOrderBlockFVG
    {
        double            price1;        // First price level
        double            price2;        // Second price level
        datetime          time;          // Time of formation
        ENUM_TIMEFRAMES   timeframe;     // Timeframe of formation
        bool              isBullish;     // True for bullish OB/FVG, false for bearish
        double            volume;        // Volume at formation
        int               strength;      // Strength of the OB/FVG
        
        SOrderBlockFVG() : price1(0), price2(0), time(0), timeframe(0), isBullish(true), volume(0), strength(0) {}
    };
    
    // Additional structure for OBFVG zones
    struct SZone {
        double price1;
        double price2;
        datetime created;
        ENUM_TIMEFRAMES timeframe;
        bool isBearish;
    };
    
    // Member variables
    SZone m_obfvgZones[MAX_OBFVG];       // Array of order blocks/FVGs zones
    SOrderBlockFVG m_obfvgArray[MAX_OBFVG];  // Array to store order blocks/FVGs
    int m_obfvgCount;                   // Number of stored order blocks/FVGs
    
    // Signal tracking
    double m_lastSignalValue;            // Last signal value
    double m_lastConfidence;             // Last signal confidence

    // Pointers to core managers are inherited from CStrategyBase
    SPositionSizingParams m_sizing_params; // Strategy-specific sizing parameters
    int m_atrHandle;                     // Handle for ATR indicator
    
    // Configuration parameters
    int m_lookback;                      // Number of bars to look back for order blocks/FVGs
    int m_minOBStrength;                 // Minimum strength for an order block to be considered valid
    int m_maxOBLookback;                 // Maximum number of bars to look back for order blocks
    
    // m_symbol and m_timeframe are inherited from CStrategyBase
    bool m_enabled;                      // Whether the strategy is enabled
    
    // Internal helper methods
    bool FindOrderBlocks(const string symbol, const ENUM_TIMEFRAMES timeframe);
    bool FindFairValueGaps(const string symbol, const ENUM_TIMEFRAMES timeframe);
    bool IsValidOrderBlock(MqlRates &candles[], int index, bool &isBullish);
    bool IsValidFairValueGap(MqlRates &candles[], int index, bool &isBullish);
    double CalculateOBStrength(MqlRates &candles[], int index, bool isBullish);
    void DrawOBFVG(const string &name, double price1, double price2, color clr, ENUM_TIMEFRAMES tf);
    bool CheckOrderBlock(const string symbol, const ENUM_TIMEFRAMES timeframe);
    bool CheckFVG(const string symbol, const ENUM_TIMEFRAMES timeframe);
    
    // Indicator function declarations (already imported via #import directives)
    // These are kept for backward compatibility and documentation

public:
    CStrategyOrderBlockFVG(const string name, int magic) :
        CStrategyBase(name, magic),
        m_lastSignalValue(0.0),
        m_lastConfidence(0.0),
        m_atrHandle(INVALID_HANDLE),
        m_lookback(50),
        m_minOBStrength(50),
        m_maxOBLookback(100),
        m_sizing_params()
    {
        // Configure strategy-specific sizing parameters
        m_sizing_params.sizingMode = POSITION_SIZE_RISK_PERCENT;
        m_sizing_params.riskPercent = 1.0;   // Risk 1.0% of account per trade
        // m_sizing_params.stopLossPips = 30.0; // FIXED: stopLossPips not in structure
    }

    virtual ~CStrategyOrderBlockFVG()
    {
        // Clean up any resources
        Deinit();
    }
    
    // IStrategy implementation
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
            return false;
        
        m_enabled = true;
        m_obfvgCount = 0;
        
        // Initialize ATR indicator
        m_atrHandle = iATR(m_symbol, m_timeframe, 14); // Using a standard 14-period ATR
        if(m_atrHandle == INVALID_HANDLE) {
            Print("Error initializing ATR indicator for ", m_name);
            m_enabled = false;
            return false;
        }
        
        return true;
    }

    virtual void Deinit() override
    {
        // Release ATR handle if it was created
        if(m_atrHandle != INVALID_HANDLE) {
            IndicatorRelease(m_atrHandle);
            m_atrHandle = INVALID_HANDLE;
        }
        
        // Clear any remaining graphical objects
        ObjectsDeleteAll(0, GetName() + "_");
        
        CStrategyBase::Deinit();
    }

    virtual void OnTick() override
    {
        if(!IsEnabled() || m_symbol == "") return;
        
        // Check for new bar
        static datetime lastBarTime = 0;
        datetime localTime = iTime(m_symbol, m_timeframe, 0);
        if(localTime != lastBarTime) {
            lastBarTime = localTime;
            OnNewBar(m_symbol, m_timeframe);
        }
    }

    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override
    {
        if(!IsEnabled() || m_symbol == "")
            return;

        m_obfvgCount = 0;
        FindOrderBlocks(m_symbol, m_timeframe);
        FindFairValueGaps(m_symbol, m_timeframe);
    }
    
    virtual string GetName() const override { return "Order Block & FVG Strategy"; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_ORDERBLOCK_FVG; }
    
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        if(!IsEnabled() || !m_is_initialized) {
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }
        
        double signalValue = GetSignalValue(m_symbol, m_timeframe, confidence);
        
        if(signalValue > 0.5)
            return TRADE_SIGNAL_BUY;
        else if(signalValue < -0.5)
            return TRADE_SIGNAL_SELL;
        else
            return TRADE_SIGNAL_NONE;
    }
    
    // Helper for internal use
    double GetSignalValue(const string symbol, const ENUM_TIMEFRAMES timeframe, double &confidence);
    
    // Configuration methods
    void SetLookback(int bars) { m_lookback = bars; }
    void SetMinOBStrength(int strength) { m_minOBStrength = strength; }
    void SetMaxOBLookback(int bars) { m_maxOBLookback = bars; }
};





double CStrategyOrderBlockFVG::GetSignalValue(const string symbol, const ENUM_TIMEFRAMES timeframe, double &confidence)
{
    if(m_obfvgCount == 0) {
        confidence = 0.0;
        return 0.0;  // No signals if no OB/FVGs found
    }
    
    // Get current price
    MqlRates rates[1];
    if(CopyRates(symbol, timeframe, 0, 1, rates) <= 0) {
        Print("Failed to get current price for ", symbol, " ", EnumToString(timeframe));
        confidence = 0.0;
        return 0.0;
    }
    double localPrice = rates[0].close;
    
    // Check for signals based on the most recent OB/FVG
    SOrderBlockFVG latest = m_obfvgArray[m_obfvgCount-1];
    double signal = 0.0;
    
    if(latest.isBullish) {
        // For bullish OB/FVG, look for price above the zone
        if(localPrice > latest.price1) {
            signal = 1.0;  // Buy signal
            confidence = latest.strength / 100.0;
        }
    } else {
        // For bearish OB/FVG, look for price below the zone
        if(localPrice < latest.price1) {
            signal = -1.0;  // Sell signal
            confidence = latest.strength / 100.0;
        }
    }
    
    return signal;
}

bool CStrategyOrderBlockFVG::FindOrderBlocks(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(m_obfvgCount >= MAX_OBFVG) 
        return false;
        
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(symbol, timeframe, 0, m_lookback, rates);
    if(copied <= 0) {
        Print("Failed to copy rates data for ", symbol, " ", EnumToString(timeframe));
        return false;
    }
    
    bool found = false;
    for(int i = 3; i < copied - 1; i++) {
        bool isBullish = false;
        if(IsValidOrderBlock(rates, i, isBullish)) {
            double strength = CalculateOBStrength(rates, i, isBullish);
            if(strength >= m_minOBStrength) {
                int idx = m_obfvgCount++;
                m_obfvgArray[idx].price1 = isBullish ? rates[i].low : rates[i].high;
                m_obfvgArray[idx].price2 = isBullish ? rates[i].close : rates[i].open;
                m_obfvgArray[idx].time = (datetime)rates[i].time;
                m_obfvgArray[idx].timeframe = timeframe;
                m_obfvgArray[idx].isBullish = isBullish;
                m_obfvgArray[idx].volume = (double)rates[i].real_volume;
                m_obfvgArray[idx].strength = (int)strength;
                found = true;
                
                if(m_obfvgCount >= MAX_OBFVG)
                    break;
            }
        }
    }
    
    return found;
}

bool CStrategyOrderBlockFVG::FindFairValueGaps(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(m_obfvgCount >= MAX_OBFVG) 
        return false;
        
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(symbol, timeframe, 0, m_lookback, rates);
    if(copied <= 0) {
        Print("Failed to copy rates data for ", symbol, " ", EnumToString(timeframe));
        return false;
    }
    
    bool found = false;
    for(int i = 1; i < copied - 1; i++) {
        bool isBullish = false;
        if(IsValidFairValueGap(rates, i, isBullish)) {
            int idx = m_obfvgCount++;
            if(isBullish) {
                m_obfvgArray[idx].price1 = rates[i].low;
                m_obfvgArray[idx].price2 = rates[i].high;
            } else {
                m_obfvgArray[idx].price1 = rates[i].high;
                m_obfvgArray[idx].price2 = rates[i].low;
            }
            m_obfvgArray[idx].time = (datetime)rates[i].time;
            m_obfvgArray[idx].timeframe = timeframe;
            m_obfvgArray[idx].isBullish = isBullish;
            m_obfvgArray[idx].volume = (double)rates[i].real_volume;
            m_obfvgArray[idx].strength = 100; // FVGs are considered strong by default
            found = true;
            
            if(m_obfvgCount >= MAX_OBFVG)
                break;
        }
    }
    
    return found;
}

bool CStrategyOrderBlockFVG::IsValidOrderBlock(MqlRates &candles[], int index, bool &isBullish)
{
    if(index < 3 || index >= ArraySize(candles)-1) 
        return false;
    
    // Check for bullish order block (bearish candle followed by bullish movement)
    if(candles[index].close < candles[index].open && 
       candles[index+1].close > candles[index+1].open &&
       candles[index+1].close > candles[index].high) {
        isBullish = true;
        return true;
    }
    
    // Check for bearish order block (bullish candle followed by bearish movement)
    if(candles[index].close > candles[index].open && 
       candles[index+1].close < candles[index+1].open &&
       candles[index+1].close < candles[index].low) {
        isBullish = false;
        return true;
    }
    
    return false;
}

bool CStrategyOrderBlockFVG::IsValidFairValueGap(MqlRates &candles[], int index, bool &isBullish)
{
    if(index < 1 || index >= ArraySize(candles)-1) 
        return false;
    
    // Check for bullish FVG (gap up)
    if(candles[index].low > candles[index+1].high) {
        isBullish = true;
        return true;
    }
    
    // Check for bearish FVG (gap down)
    if(candles[index].high < candles[index+1].low) {
        isBullish = false;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Calculate Order Block strength                                  |
//+------------------------------------------------------------------
double CStrategyOrderBlockFVG::CalculateOBStrength(MqlRates &candles[], int index, bool isBullish)
{
    if(index < 0 || index >= ArraySize(candles)) 
        return 0.0;
    
    double strength = 0.0;
    
    // Base strength on candle size
    double candleSize = MathAbs(candles[index].close - candles[index].open);
    double avgCandleSize = 0.0;
    
    // Calculate average candle size over the last 20 bars
    int lookback = MathMin(20, index);
    for(int i = 1; i <= lookback; i++) {
        avgCandleSize += MathAbs(candles[index-i].close - candles[index-i].open);
    }
    
    if(lookback > 0) {
        avgCandleSize /= lookback;
        
        // Calculate strength based on how much larger this candle is than average
        if(avgCandleSize > 0) {
            double sizeRatio = candleSize / avgCandleSize;
            strength = MathMin(100.0, sizeRatio * 50.0); // Cap at 100
            
            // Increase strength for high volume
            if(candles[index].real_volume > 0) {
                double localVolumeRatio = (double)candles[index].real_volume / (double)candles[index-1].real_volume;
                strength = MathMin(100.0, strength * (1.0 + localVolumeRatio * 0.5));
            }
        }
        
        // If candle is larger than average, increase strength
        if(avgCandleSize > 0) {
            strength += 30.0 * MathMin(candleSize / avgCandleSize, 2.0);
        }
        
        // Add volume factor (if available)
        if(candles[index].real_volume > 0) {
            double volumeMA = 0.0;
            for(int i = 1; i <= lookback; i++) {
                volumeMA += (double)candles[index-i].real_volume;
            }
            volumeMA /= lookback;
            
            if(volumeMA > 0) {
                strength += 20.0 * MathMin((double)candles[index].real_volume / volumeMA, 2.0);
            }
        }
        
        // Add time factor (recent OB/FVGs are stronger)
        double timeFactor = 100.0 * (1.0 - (double)index / m_lookback);
        strength = strength * 0.7 + timeFactor * 0.3;
        
        // Ensure strength is within bounds
        return MathMin(MathMax(strength, 0.0), 100.0);
    }
    
    return strength;
    
    // Add volume factor (if available)
    if(candles[index].real_volume > 0) {
        double volumeMA = 0.0;
        for(int i = 1; i <= lookback; i++) {
            volumeMA += (double)candles[index-i].real_volume;
        }
        volumeMA /= lookback;
        
        if(volumeMA > 0) {
            strength += 20.0 * MathMin((double)candles[index].real_volume / volumeMA, 2.0);
        }
    }
    
    // Add time factor (recent OB/FVGs are stronger)
    double timeFactor = 100.0 * (1.0 - (double)index / m_lookback);
    strength = strength * 0.7 + timeFactor * 0.3;
    
    // Ensure strength is within bounds
    return MathMin(MathMax(strength, 0.0), 100.0);
}

void CStrategyOrderBlockFVG::DrawOBFVG(const string &name, double price1, double price2, color clr, ENUM_TIMEFRAMES tf)
{
    if(price1 <= 0 || price2 <= 0) return;
    
    long chart_id = ChartID();
    int window = 0;
    double top = MathMax(price1, price2);
    double bottom = MathMin(price1, price2);
    
    // Get time for the rectangle
    datetime times[1];
    if(CopyTime(m_symbol, tf, 0, 1, times) <= 0) {
        Print("Failed to get time for ", m_symbol, " ", EnumToString(tf));
        return;
    }
    
    datetime left = times[0];
    datetime right = TimeCurrent();
    
    // Delete existing object if it exists
    if(ObjectFind(chart_id, name) >= 0) {
        ObjectDelete(chart_id, name);
    }
    
    // Create new rectangle
    if(!ObjectCreate(chart_id, name, OBJ_RECTANGLE, window, left, top, right, bottom)) {
        Print("Failed to create object ", name, ", error: ", GetLastError());
        return;
    }
    
    // Set properties
    ObjectSetInteger(chart_id, name, OBJPROP_COLOR, clr);
    ObjectSetInteger(chart_id, name, OBJPROP_BACK, true);
    ObjectSetInteger(chart_id, name, OBJPROP_WIDTH, 1);
    ObjectSetInteger(chart_id, name, OBJPROP_FILL, true);
    ObjectSetInteger(chart_id, name, OBJPROP_SELECTABLE, false);
    ObjectSetInteger(chart_id, name, OBJPROP_SELECTED, false);
    ObjectSetInteger(chart_id, name, OBJPROP_HIDDEN, true);
    ObjectSetInteger(chart_id, name, OBJPROP_ZORDER, 0);
}

bool CStrategyOrderBlockFVG::CheckOrderBlock(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    return FindOrderBlocks(symbol, timeframe);
}

bool CStrategyOrderBlockFVG::CheckFVG(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    return FindFairValueGaps(symbol, timeframe);
}

#endif // __STRATEGY_ORDERBLOCK_FVG_MQH__
