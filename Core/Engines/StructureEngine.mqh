//+------------------------------------------------------------------+
//| Structure Detection Engine - Enterprise Grade                    |
//| Unified ICT structure detection for all strategies               |
//+------------------------------------------------------------------+
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef STRUCTURE_ENGINE_MQH
#define STRUCTURE_ENGINE_MQH

#include "../Utils/Enums.mqh"
#include "../Signals/SignalDiagnostics.mqh"
#include <Arrays/ArrayObj.mqh>

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CModeManager;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;
class CAIStrategyOrchestrator;

//+------------------------------------------------------------------+
//| Structure Types                                                  |
//+------------------------------------------------------------------+
enum ENUM_STRUCTURE_TYPE
{
    STRUCT_TYPE_NONE = 0,
    STRUCT_TYPE_HH,          // Higher High
    STRUCT_TYPE_HL,          // Higher Low  
    STRUCT_TYPE_LH,          // Lower High
    STRUCT_TYPE_LL,          // Lower Low
    STRUCT_TYPE_EQH,         // Equal High
    STRUCT_TYPE_EQL,         // Equal Low
    STRUCT_TYPE_BOS,         // Break of Structure
    STRUCT_TYPE_CHOCH,       // Change of Character
    STRUCT_TYPE_SWEEP,       // Liquidity Sweep
    STRUCT_TYPE_RAID         // Stop Hunt/Raid
};

//+------------------------------------------------------------------+
//| Swing Point Structure                                           |
//+------------------------------------------------------------------+
struct SwingPoint
{
    double price;
    datetime time;
    int bar;
    ENUM_STRUCTURE_TYPE type;
    double strength;        // 0-100 strength score
    bool isValid;
    bool isMitigated;
    
    SwingPoint() : price(0), time(0), bar(0), type(STRUCT_TYPE_NONE), 
                   strength(0), isValid(false), isMitigated(false) {}
};

//+------------------------------------------------------------------+
//| Market Structure State                                          |
//+------------------------------------------------------------------+
struct MarketStructureState
{
    ENUM_STRUCTURE_TYPE currentStructure;
    bool isBullish;
    bool isBearish;
    double lastHigh;
    double lastLow;
    double prevHigh;
    double prevLow;
    int bosCount;           // Break of Structure count
    int chochCount;         // Change of Character count
    double structureStrength;
    datetime lastUpdate;
    
    MarketStructureState() : currentStructure(STRUCT_TYPE_NONE), isBullish(false),
                            isBearish(false), lastHigh(0), lastLow(0),
                            prevHigh(0), prevLow(0), bosCount(0), chochCount(0),
                            structureStrength(0), lastUpdate(0) {}
};

//+------------------------------------------------------------------+
//| Structure Detection Engine Class                                |
//+------------------------------------------------------------------+
class CStructureEngine
{
private:
    // Configuration
    int m_swingPeriod;             // Bars for swing detection
    double m_minSwingSize;          // Minimum swing size in points
    double m_structureThreshold;    // BOS/CHOCH threshold
    double m_sweepThreshold;        // Liquidity sweep threshold
    bool m_useATR;                  // Use ATR for adaptive thresholds
    string m_symbol;                // Current symbol for logging
    
    // State tracking
    SwingPoint m_swingHighs[];     // Array of swing highs
    SwingPoint m_swingLows[];      // Array of swing lows
    MarketStructureState m_state;   // Current structure state
    
    // Diagnostics
    CSignalDiagnostics* m_diagnostics;
    
    // Internal methods
    bool IsSwingHigh(const MqlRates &rates[], int index, int period);
    bool IsSwingLow(const MqlRates &rates[], int index, int period);
    double CalculateSwingStrength(const MqlRates &rates[], int index, bool isHigh);
    void UpdateStructureState(const SwingPoint &newPoint, bool isHigh);
    bool DetectBOS(const SwingPoint &current, const SwingPoint &previous);
    bool DetectCHOCH(const SwingPoint &current, const SwingPoint &previous);
    bool DetectLiquiditySweep(const MqlRates &rates[], int index);
    
public:
    // Constructor/Destructor
    CStructureEngine();
    ~CStructureEngine();
    
    // Initialization
    bool Initialize(int swingPeriod = 10, double minSwingSize = 10.0, 
                   bool useATR = true, CSignalDiagnostics* diagnostics = NULL);
    
    // Main detection methods
    bool DetectSwingPoints(const string symbol, ENUM_TIMEFRAMES timeframe);
    ENUM_STRUCTURE_TYPE GetCurrentStructure() const { return m_state.currentStructure; }
    MarketStructureState GetStructureState() const { return m_state; }
    
    // Specific structure detection
    bool HasBullishBOS(int lookback = 3);
    bool HasBearishBOS(int lookback = 3);
    bool HasBullishCHOCH(int lookback = 3);
    bool HasBearishCHOCH(int lookback = 3);
    bool HasLiquiditySweep(int lookback = 5);
    
    // Utility methods
    double GetStructureStrength() const { return m_state.structureStrength; }
    bool IsBullishStructure() const { return m_state.isBullish; }
    bool IsBearishStructure() const { return m_state.isBearish; }
    void Reset();
    
    // Getters for swing points
    bool GetLastSwingHigh(SwingPoint &point);
    bool GetLastSwingLow(SwingPoint &point);
    int GetSwingHighCount() const { return ArraySize(m_swingHighs); }
    int GetSwingLowCount() const { return ArraySize(m_swingLows); }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CStructureEngine::CStructureEngine() :
    m_swingPeriod(10),
    m_minSwingSize(10.0),
    m_structureThreshold(0.0),
    m_sweepThreshold(5.0),
    m_useATR(true),
    m_diagnostics(NULL)
{
    ArrayResize(m_swingHighs, 0);
    ArrayResize(m_swingLows, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CStructureEngine::~CStructureEngine()
{
    ArrayFree(m_swingHighs);
    ArrayFree(m_swingLows);
}

//+------------------------------------------------------------------+
//| Initialize Engine                                               |
//+------------------------------------------------------------------+
bool CStructureEngine::Initialize(int swingPeriod, double minSwingSize, 
                                 bool useATR, CSignalDiagnostics* diagnostics)
{
    m_swingPeriod = swingPeriod;
    m_minSwingSize = minSwingSize;
    m_useATR = useATR;
    m_diagnostics = diagnostics;
    
    Reset();
    
    if(m_diagnostics != NULL)
    {
        Print("[StructureEngine] Initialized | Period: ", swingPeriod, 
              " | MinSize: ", minSwingSize, " | ATR: ", useATR);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Detect Swing Points                                             |
//+------------------------------------------------------------------+
bool CStructureEngine::DetectSwingPoints(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    
    int copied = CopyRates(symbol, timeframe, 0, 100 + m_swingPeriod, rates);
    if(copied < m_swingPeriod * 2)
    {
        if(m_diagnostics != NULL)
            m_diagnostics.LogStrategyError("StructureEngine", "INSUFFICIENT_BARS", 
                                          "Not enough bars for swing detection");
        return false;
    }
    
    m_symbol = symbol;
    
    // Clear old swings
    ArrayResize(m_swingHighs, 0);
    ArrayResize(m_swingLows, 0);
    
    // Detect swing points
    for(int i = m_swingPeriod; i < copied - m_swingPeriod; i++)
    {
        // Check for swing high
        if(IsSwingHigh(rates, i, m_swingPeriod))
        {
            SwingPoint point;
            point.price = rates[i].high;
            point.time = rates[i].time;
            point.bar = i;
            point.type = STRUCT_TYPE_HH; // Will be updated based on comparison
            point.strength = CalculateSwingStrength(rates, i, true);
            point.isValid = true;
            
            // Add to array
            int size = ArraySize(m_swingHighs);
            ArrayResize(m_swingHighs, size + 1);
            m_swingHighs[size] = point;
            
            // Update structure state
            UpdateStructureState(point, true);
            
            if(m_diagnostics != NULL && size > 0)
            {
                // Check for BOS/CHOCH
                if(DetectBOS(point, m_swingHighs[size-1]))
                {
                    m_diagnostics.LogSMCDetection("BOS_HIGH", m_symbol, point.price, 
                                                 point.price, m_swingHighs[size-1].price,
                                                 true, point.strength);
                }
                if(DetectCHOCH(point, m_swingHighs[size-1]))
                {
                    m_diagnostics.LogSMCDetection("CHOCH_HIGH", m_symbol, point.price,
                                                 point.price, m_swingHighs[size-1].price,
                                                 false, point.strength);
                }
            }
        }
        
        // Check for swing low
        if(IsSwingLow(rates, i, m_swingPeriod))
        {
            SwingPoint point;
            point.price = rates[i].low;
            point.time = rates[i].time;
            point.bar = i;
            point.type = STRUCT_TYPE_LL; // Will be updated based on comparison
            point.strength = CalculateSwingStrength(rates, i, false);
            point.isValid = true;
            
            // Add to array
            int size = ArraySize(m_swingLows);
            ArrayResize(m_swingLows, size + 1);
            m_swingLows[size] = point;
            
            // Update structure state
            UpdateStructureState(point, false);
            
            if(m_diagnostics != NULL && size > 0)
            {
                // Check for BOS/CHOCH
                if(DetectBOS(point, m_swingLows[size-1]))
                {
                    m_diagnostics.LogSMCDetection("BOS_LOW", m_symbol, point.price,
                                                 m_swingLows[size-1].price, point.price,
                                                 false, point.strength);
                }
                if(DetectCHOCH(point, m_swingLows[size-1]))
                {
                    m_diagnostics.LogSMCDetection("CHOCH_LOW", m_symbol, point.price,
                                                 m_swingLows[size-1].price, point.price,
                                                 true, point.strength);
                }
            }
        }
        
        // Check for liquidity sweep
        if(DetectLiquiditySweep(rates, i))
        {
            if(m_diagnostics != NULL)
            {
                m_diagnostics.LogSMCDetection("LIQUIDITY_SWEEP", m_symbol, rates[i].close,
                                             rates[i].high, rates[i].low,
                                             rates[i].close > rates[i].open, 50.0);
            }
        }
    }
    
    // Calculate overall structure strength
    if(ArraySize(m_swingHighs) > 1 && ArraySize(m_swingLows) > 1)
    {
        double highDiff = m_swingHighs[ArraySize(m_swingHighs)-1].price - 
                         m_swingHighs[ArraySize(m_swingHighs)-2].price;
        double lowDiff = m_swingLows[ArraySize(m_swingLows)-1].price - 
                        m_swingLows[ArraySize(m_swingLows)-2].price;
        
        if(highDiff > 0 && lowDiff > 0)
        {
            m_state.isBullish = true;
            m_state.isBearish = false;
            m_state.structureStrength = MathMin(100, (highDiff / m_minSwingSize) * 50);
        }
        else if(highDiff < 0 && lowDiff < 0)
        {
            m_state.isBullish = false;
            m_state.isBearish = true;
            m_state.structureStrength = MathMin(100, (MathAbs(lowDiff) / m_minSwingSize) * 50);
        }
    }
    
    m_state.lastUpdate = TimeCurrent();
    return true;
}

//+------------------------------------------------------------------+
//| Check if bar is a swing high                                    |
//+------------------------------------------------------------------+
bool CStructureEngine::IsSwingHigh(const MqlRates &rates[], int index, int period)
{
    if(index < period || index >= ArraySize(rates) - period)
        return false;
    
    double high = rates[index].high;
    
    // Check left side
    for(int i = 1; i <= period; i++)
    {
        if(rates[index - i].high >= high)
            return false;
    }
    
    // Check right side
    for(int i = 1; i <= period; i++)
    {
        if(rates[index + i].high > high)
            return false;
    }
    
    // Verify minimum swing size
    double avgBody = 0;
    for(int i = index - period; i <= index + period; i++)
    {
        avgBody += MathAbs(rates[i].close - rates[i].open);
    }
    avgBody /= (period * 2 + 1);
    
    if(m_useATR)
    {
        // Use body size as proxy for ATR
        return avgBody > 0 && (high - rates[index].low) > avgBody * 2;
    }
    else
    {
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        return (high - rates[index].low) > m_minSwingSize * point;
    }
}

//+------------------------------------------------------------------+
//| Check if bar is a swing low                                     |
//+------------------------------------------------------------------+
bool CStructureEngine::IsSwingLow(const MqlRates &rates[], int index, int period)
{
    if(index < period || index >= ArraySize(rates) - period)
        return false;
    
    double low = rates[index].low;
    
    // Check left side
    for(int i = 1; i <= period; i++)
    {
        if(rates[index - i].low <= low)
            return false;
    }
    
    // Check right side  
    for(int i = 1; i <= period; i++)
    {
        if(rates[index + i].low < low)
            return false;
    }
    
    // Verify minimum swing size
    double avgBody = 0;
    for(int i = index - period; i <= index + period; i++)
    {
        avgBody += MathAbs(rates[i].close - rates[i].open);
    }
    avgBody /= (period * 2 + 1);
    
    if(m_useATR)
    {
        return avgBody > 0 && (rates[index].high - low) > avgBody * 2;
    }
    else
    {
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        return (rates[index].high - low) > m_minSwingSize * point;
    }
}

//+------------------------------------------------------------------+
//| Calculate swing point strength                                  |
//+------------------------------------------------------------------+
double CStructureEngine::CalculateSwingStrength(const MqlRates &rates[], int index, bool isHigh)
{
    double strength = 50.0; // Base strength
    
    // Factor 1: Volume (if available)
    if(rates[index].tick_volume > 0)
    {
        double avgVolume = 0;
        for(int i = index - 5; i <= index + 5; i++)
        {
            if(i >= 0 && i < ArraySize(rates))
                avgVolume += (double)rates[i].tick_volume;
        }
        avgVolume /= 11;
        
        if(rates[index].tick_volume > avgVolume * 1.5)
            strength += 15;
        else if(rates[index].tick_volume > avgVolume * 1.2)
            strength += 10;
    }
    
    // Factor 2: Candle body size
    double bodySize = MathAbs(rates[index].close - rates[index].open);
    double range = rates[index].high - rates[index].low;
    if(range > 0)
    {
        double bodyRatio = bodySize / range;
        strength += bodyRatio * 20; // Up to 20 points for body dominance
    }
    
    // Factor 3: Rejection wicks
    if(isHigh)
    {
        double upperWick = rates[index].high - MathMax(rates[index].open, rates[index].close);
        if(upperWick > bodySize * 2)
            strength += 15; // Strong rejection
    }
    else
    {
        double lowerWick = MathMin(rates[index].open, rates[index].close) - rates[index].low;
        if(lowerWick > bodySize * 2)
            strength += 15; // Strong rejection
    }
    
    return MathMin(100.0, strength);
}

//+------------------------------------------------------------------+
//| Update market structure state                                   |
//+------------------------------------------------------------------+
void CStructureEngine::UpdateStructureState(const SwingPoint &newPoint, bool isHigh)
{
    if(isHigh)
    {
        m_state.prevHigh = m_state.lastHigh;
        m_state.lastHigh = newPoint.price;
        
        // Determine structure type
        if(m_state.prevHigh > 0)
        {
            if(newPoint.price > m_state.prevHigh)
            {
                m_state.currentStructure = STRUCT_TYPE_HH;
                m_state.bosCount++;
            }
            else if(newPoint.price < m_state.prevHigh)
            {
                m_state.currentStructure = STRUCT_TYPE_LH;
                if(m_state.isBullish)
                {
                    m_state.chochCount++;
                }
            }
            else
            {
                m_state.currentStructure = STRUCT_TYPE_EQH;
            }
        }
    }
    else
    {
        m_state.prevLow = m_state.lastLow;
        m_state.lastLow = newPoint.price;
        
        // Determine structure type
        if(m_state.prevLow > 0)
        {
            if(newPoint.price < m_state.prevLow)
            {
                m_state.currentStructure = STRUCT_TYPE_LL;
                m_state.bosCount++;
            }
            else if(newPoint.price > m_state.prevLow)
            {
                m_state.currentStructure = STRUCT_TYPE_HL;
                if(m_state.isBearish)
                {
                    m_state.chochCount++;
                }
            }
            else
            {
                m_state.currentStructure = STRUCT_TYPE_EQL;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Detect Break of Structure                                       |
//+------------------------------------------------------------------+
bool CStructureEngine::DetectBOS(const SwingPoint &current, const SwingPoint &previous)
{
    if(!current.isValid || !previous.isValid)
        return false;
    
    // Bullish BOS: Higher high and higher low
    if(current.type == STRUCT_TYPE_HH && current.price > previous.price)
        return true;
    
    // Bearish BOS: Lower low and lower high
    if(current.type == STRUCT_TYPE_LL && current.price < previous.price)
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Detect Change of Character                                      |
//+------------------------------------------------------------------+
bool CStructureEngine::DetectCHOCH(const SwingPoint &current, const SwingPoint &previous)
{
    if(!current.isValid || !previous.isValid)
        return false;
    
    // Bearish CHOCH: Lower high after uptrend
    if(m_state.isBullish && current.type == STRUCT_TYPE_LH)
        return true;
    
    // Bullish CHOCH: Higher low after downtrend
    if(m_state.isBearish && current.type == STRUCT_TYPE_HL)
        return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Detect Liquidity Sweep                                          |
//+------------------------------------------------------------------+
bool CStructureEngine::DetectLiquiditySweep(const MqlRates &rates[], int index)
{
    if(index < 2 || index >= ArraySize(rates) - 1)
        return false;
    
    // Check for sweep above previous high
    if(ArraySize(m_swingHighs) > 0)
    {
        double lastHigh = m_swingHighs[ArraySize(m_swingHighs)-1].price;
        if(rates[index].high > lastHigh && rates[index].close < lastHigh)
        {
            // Wick above but close below = potential sweep
            double wickSize = rates[index].high - MathMax(rates[index].open, rates[index].close);
            double bodySize = MathAbs(rates[index].close - rates[index].open);
            
            if(wickSize > bodySize * 2) // Strong rejection wick
                return true;
        }
    }
    
    // Check for sweep below previous low
    if(ArraySize(m_swingLows) > 0)
    {
        double lastLow = m_swingLows[ArraySize(m_swingLows)-1].price;
        if(rates[index].low < lastLow && rates[index].close > lastLow)
        {
            // Wick below but close above = potential sweep
            double wickSize = MathMin(rates[index].open, rates[index].close) - rates[index].low;
            double bodySize = MathAbs(rates[index].close - rates[index].open);
            
            if(wickSize > bodySize * 2) // Strong rejection wick
                return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check for recent bullish BOS                                    |
//+------------------------------------------------------------------+
bool CStructureEngine::HasBullishBOS(int lookback)
{
    int highCount = ArraySize(m_swingHighs);
    int lowCount = ArraySize(m_swingLows);
    
    if(highCount < 2 || lowCount < 2)
        return false;
    
    for(int i = MathMax(0, highCount - lookback); i < highCount - 1; i++)
    {
        if(m_swingHighs[i+1].price > m_swingHighs[i].price)
        {
            // Also check for higher low
            for(int j = MathMax(0, lowCount - lookback); j < lowCount - 1; j++)
            {
                if(m_swingLows[j+1].price > m_swingLows[j].price &&
                   MathAbs(m_swingHighs[i+1].bar - m_swingLows[j+1].bar) < 10)
                {
                    return true;
                }
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check for recent bearish BOS                                    |
//+------------------------------------------------------------------+
bool CStructureEngine::HasBearishBOS(int lookback)
{
    int highCount = ArraySize(m_swingHighs);
    int lowCount = ArraySize(m_swingLows);
    
    if(highCount < 2 || lowCount < 2)
        return false;
    
    for(int i = MathMax(0, lowCount - lookback); i < lowCount - 1; i++)
    {
        if(m_swingLows[i+1].price < m_swingLows[i].price)
        {
            // Also check for lower high
            for(int j = MathMax(0, highCount - lookback); j < highCount - 1; j++)
            {
                if(m_swingHighs[j+1].price < m_swingHighs[j].price &&
                   MathAbs(m_swingLows[i+1].bar - m_swingHighs[j+1].bar) < 10)
                {
                    return true;
                }
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check for recent bullish CHOCH                                  |
//+------------------------------------------------------------------+
bool CStructureEngine::HasBullishCHOCH(int lookback)
{
    if(!m_state.isBearish || m_state.chochCount == 0)
        return false;
    
    int lowCount = ArraySize(m_swingLows);
    if(lowCount < 2)
        return false;
    
    // Check for higher low after bearish trend
    for(int i = MathMax(0, lowCount - lookback); i < lowCount - 1; i++)
    {
        if(m_swingLows[i+1].price > m_swingLows[i].price)
            return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check for recent bearish CHOCH                                  |
//+------------------------------------------------------------------+
bool CStructureEngine::HasBearishCHOCH(int lookback)
{
    if(!m_state.isBullish || m_state.chochCount == 0)
        return false;
    
    int highCount = ArraySize(m_swingHighs);
    if(highCount < 2)
        return false;
    
    // Check for lower high after bullish trend
    for(int i = MathMax(0, highCount - lookback); i < highCount - 1; i++)
    {
        if(m_swingHighs[i+1].price < m_swingHighs[i].price)
            return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check for recent liquidity sweep                                |
//+------------------------------------------------------------------+
bool CStructureEngine::HasLiquiditySweep(int lookback)
{
    // This would need to track sweep events
    // For now, return based on structure analysis
    return m_state.currentStructure == STRUCT_TYPE_SWEEP;
}

//+------------------------------------------------------------------+
//| Get last swing high                                             |
//+------------------------------------------------------------------+
bool CStructureEngine::GetLastSwingHigh(SwingPoint &point)
{
    int size = ArraySize(m_swingHighs);
    if(size == 0)
        return false;
    
    point = m_swingHighs[size - 1];
    return true;
}

//+------------------------------------------------------------------+
//| Get last swing low                                              |
//+------------------------------------------------------------------+
bool CStructureEngine::GetLastSwingLow(SwingPoint &point)
{
    int size = ArraySize(m_swingLows);
    if(size == 0)
        return false;
    
    point = m_swingLows[size - 1];
    return true;
}

//+------------------------------------------------------------------+
//| Reset engine state                                              |
//+------------------------------------------------------------------+
void CStructureEngine::Reset()
{
    ArrayResize(m_swingHighs, 0);
    ArrayResize(m_swingLows, 0);
    m_state = MarketStructureState();
}

#endif // STRUCTURE_ENGINE_MQH
