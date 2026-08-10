//+------------------------------------------------------------------+
//| Structure Detection Engine - Enterprise Grade                    |
//| Unified ICT structure detection for all strategies               |
//|                                                                  |
//| Coordinator only. The heavy lifting lives in focused modules:    |
//|   StructureTypes.mqh     - shared value types                    |
//|   StructureSwing.mqh     - swing high/low + potential tracking   |
//|   StructureScore.mqh     - swing strength + structure scoring    |
//|   StructureBOSCHoCH.mqh  - break of structure / change of char.  |
//|   StructureLiquidity.mqh - liquidity sweep detection             |
//+------------------------------------------------------------------+
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef STRUCTURE_ENGINE_MQH
#define STRUCTURE_ENGINE_MQH

#include "../Utils/Enums.mqh"
#include "../Signals/SignalDiagnostics.mqh"
#include <Arrays/ArrayObj.mqh>

#include "StructureTypes.mqh"
#include "StructureSwing.mqh"
#include "StructureScore.mqh"
#include "StructureBOSCHoCH.mqh"
#include "StructureLiquidity.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CMarketAnalysis;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CTradeManager;
class CPerformanceAnalytics;

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
    
        // Extracted modules (by value)
        CStructureSwingDetector m_swing;  // Swing detection + potential swing slots
    
    // Diagnostics
    CSignalDiagnostics* m_diagnostics;
    
    // Internal methods - thin forwarders into the extracted modules
        bool IsSwingHigh(const MqlRates &rates[], int index, int period) { return m_swing.IsSwingHigh(rates, index, period); }
        bool IsSwingLow(const MqlRates &rates[], int index, int period) { return m_swing.IsSwingLow(rates, index, period); }
    
        // Real-time swing detection methods (L4-009 fix)
        bool IsPotentialSwingHigh(const MqlRates &rates[], int index, int period) { return m_swing.IsPotentialSwingHigh(rates, index, period); }
        bool IsPotentialSwingLow(const MqlRates &rates[], int index, int period) { return m_swing.IsPotentialSwingLow(rates, index, period); }
        bool IsConfirmedSwingHigh(const MqlRates &rates[], int index, int period) { return m_swing.IsConfirmedSwingHigh(rates, index, period); }
        bool IsConfirmedSwingLow(const MqlRates &rates[], int index, int period) { return m_swing.IsConfirmedSwingLow(rates, index, period); }
        void ConfirmPotentialSwings(const MqlRates &rates[], int currentBarIndex);
        void ScanPotentialSwings(const MqlRates &rates[], int copied);
    double CalculateSwingStrength(const MqlRates &rates[], int index, bool isHigh) { return CStructureScore::CalculateSwingStrength(rates, index, isHigh); }
    void UpdateStructureState(const SwingPoint &newPoint, bool isHigh) { CStructureScore::UpdateStructureState(m_state, newPoint, isHigh); }
    bool DetectBOS(const SwingPoint &current, const SwingPoint &previous) { return CStructureBOSCHoCH::DetectBOS(current, previous); }
    bool DetectCHOCH(const SwingPoint &current, const SwingPoint &previous) { return CStructureBOSCHoCH::DetectCHOCH(m_state, current, previous); }
    bool DetectLiquiditySweep(const MqlRates &rates[], int index) { return CStructureLiquidity::DetectLiquiditySweep(rates, index, m_swingHighs, m_swingLows); }
    
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
    m_swing.Configure(m_minSwingSize, m_useATR);
    m_swing.ResetPotentials();
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
    m_swing.Configure(m_minSwingSize, m_useATR);
    
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
    
    // L4-009 Fix: First, confirm potential swings from previous calls
    // (right side data may now be available)
    ConfirmPotentialSwings(rates, copied - 1);
    
    // L4-009 Fix: Check for NEW potential swings at recent bars (indices < m_swingPeriod)
    // These bars don't have enough future data for full confirmation yet
    ScanPotentialSwings(rates, copied);
    
    // Detect CONFIRMED swing points for historical bars (both sides available)
    // Only process bars that have enough left AND right context
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
                                                 point.price, m_swingLows[size-1].price,
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
    
    // L4-009 Fix: Check for potential swing high/low at current bar (index 0) and recent bars
    // These bars don't have enough future data for full confirmation yet
    ScanPotentialSwings(rates, copied);
    
    // L4-009 Fix: Confirm potential swings when right side data becomes available
    ConfirmPotentialSwings(rates, copied - 1);
    
    // Calculate overall structure strength
    CStructureScore::UpdateBiasAndStrength(m_state, m_swingHighs, m_swingLows, m_minSwingSize);
    
    m_state.lastUpdate = TimeCurrent();
    return true;
}

//+------------------------------------------------------------------+
//| Scan recent bars for NEW potential swings (left side only)      |
//+------------------------------------------------------------------+
void CStructureEngine::ScanPotentialSwings(const MqlRates &rates[], int copied)
{
    for(int i = 0; i < m_swingPeriod && i < copied; i++)
    {
        // Check for potential swing high (left side only)
        if(IsPotentialSwingHigh(rates, i, m_swingPeriod))
        {
            // Store as potential swing high for confirmation on next bars
            m_swing.MarkPotentialHigh(i, rates[i].high);
            
            if(m_diagnostics != NULL)
            {
                m_diagnostics.LogSMCDetection("POTENTIAL_SWING_HIGH", m_symbol, rates[i].high,
                                             rates[i].high, 0, true, 0);
            }
        }
        
        // Check for potential swing low (left side only)
        if(IsPotentialSwingLow(rates, i, m_swingPeriod))
        {
            // Store as potential swing low for confirmation on next bars
            m_swing.MarkPotentialLow(i, rates[i].low);
            
            if(m_diagnostics != NULL)
            {
                m_diagnostics.LogSMCDetection("POTENTIAL_SWING_LOW", m_symbol, rates[i].low,
                                             rates[i].low, 0, true, 0);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Confirm potential swings when right side becomes available
//+------------------------------------------------------------------+
void CStructureEngine::ConfirmPotentialSwings(const MqlRates &rates[], int currentBarIndex)
{
    // Check if potential swing high can now be confirmed (right side available)
    if(m_swing.PotentialHighValid() && m_swing.PotentialHighIndex() >= 0)
    {
        // The potential swing was at index PotentialHighIndex()
        // Now we need to check if the right side (currentBarIndex - potentialIndex bars)
        // satisfies the swing condition
        int potentialIndex = m_swing.PotentialHighIndex();
        int barsSincePotential = currentBarIndex - potentialIndex;
        
        if(barsSincePotential >= m_swingPeriod)
        {
            // Enough bars have passed, check if right side is confirmed
            if(IsConfirmedSwingHigh(rates, potentialIndex, m_swingPeriod))
            {
                // Confirmed! Add to swing highs array
                SwingPoint point;
                point.price = m_swing.PotentialHighPrice();
                point.time = rates[potentialIndex].time;
                point.bar = potentialIndex;
                point.type = STRUCT_TYPE_HH; // Will be updated by UpdateStructureState
                point.strength = CalculateSwingStrength(rates, potentialIndex, true);
                point.isValid = true;
                
                int size = ArraySize(m_swingHighs);
                ArrayResize(m_swingHighs, size + 1);
                m_swingHighs[size] = point;
                
                UpdateStructureState(point, true);
                
                if(m_diagnostics != NULL)
                {
                    m_diagnostics.LogSMCDetection("CONFIRMED_SWING_HIGH", m_symbol, point.price, 
                                                 point.price, 0, true, point.strength);
                }
            }
            // Whether confirmed or not, clear the potential swing
            m_swing.ClearPotentialHigh();
        }
    }
    
    // Check if potential swing low can now be confirmed
    if(m_swing.PotentialLowValid() && m_swing.PotentialLowIndex() >= 0)
    {
        int potentialIndex = m_swing.PotentialLowIndex();
        int barsSincePotential = currentBarIndex - potentialIndex;
        
        if(barsSincePotential >= m_swingPeriod)
        {
            if(IsConfirmedSwingLow(rates, potentialIndex, m_swingPeriod))
            {
                // Confirmed! Add to swing lows array
                SwingPoint point;
                point.price = m_swing.PotentialLowPrice();
                point.time = rates[potentialIndex].time;
                point.bar = potentialIndex;
                point.type = STRUCT_TYPE_LL; // Will be updated by UpdateStructureState
                point.strength = CalculateSwingStrength(rates, potentialIndex, false);
                point.isValid = true;
                
                int size = ArraySize(m_swingLows);
                ArrayResize(m_swingLows, size + 1);
                m_swingLows[size] = point;
                
                UpdateStructureState(point, false);
                
                if(m_diagnostics != NULL)
                {
                    m_diagnostics.LogSMCDetection("CONFIRMED_SWING_LOW", m_symbol, point.price,
                                                 point.price, 0, true, point.strength);
                }
            }
            // Whether confirmed or not, clear the potential swing
            m_swing.ClearPotentialLow();
        }
    }
}

//+------------------------------------------------------------------+
//| Check for recent bullish BOS                                    |
//+------------------------------------------------------------------+
bool CStructureEngine::HasBullishBOS(int lookback)
{
    return CStructureBOSCHoCH::HasBullishBOS(m_swingHighs, m_swingLows, lookback);
}

//+------------------------------------------------------------------+
//| Check for recent bearish BOS                                    |
//+------------------------------------------------------------------+
bool CStructureEngine::HasBearishBOS(int lookback)
{
    return CStructureBOSCHoCH::HasBearishBOS(m_swingHighs, m_swingLows, lookback);
}

//+------------------------------------------------------------------+
//| Check for recent bullish CHOCH                                  |
//+------------------------------------------------------------------+
bool CStructureEngine::HasBullishCHOCH(int lookback)
{
    return CStructureBOSCHoCH::HasBullishCHOCH(m_state, m_swingLows, lookback);
}

//+------------------------------------------------------------------+
//| Check for recent bearish CHOCH                                  |
//+------------------------------------------------------------------+
bool CStructureEngine::HasBearishCHOCH(int lookback)
{
    return CStructureBOSCHoCH::HasBearishCHOCH(m_state, m_swingHighs, lookback);
}

//+------------------------------------------------------------------+
//| Check for recent liquidity sweep                                |
//+------------------------------------------------------------------+
bool CStructureEngine::HasLiquiditySweep(int lookback)
{
    return CStructureLiquidity::HasLiquiditySweep(m_state, lookback);
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
    
    // L4-009 Fix: Reset potential swing tracking variables
    m_swing.ResetPotentials();
}

#endif // STRUCTURE_ENGINE_MQH