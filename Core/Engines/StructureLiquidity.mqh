//+------------------------------------------------------------------+
//| StructureLiquidity.mqh - Liquidity sweep / stop-hunt detection   |
//| Extracted verbatim from StructureEngine.mqh (no behavior change) |
//|                                                                  |
//| Stateless: swing arrays and the structure state are injected.    |
//+------------------------------------------------------------------+
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef STRUCTURE_LIQUIDITY_MQH
#define STRUCTURE_LIQUIDITY_MQH

#include "StructureTypes.mqh"

//+------------------------------------------------------------------+
//| Stateless liquidity sweep helpers                                |
//+------------------------------------------------------------------+
class CStructureLiquidity
{
public:
    //--- Wick-through / close-back sweep of the most recent swing level
    static bool DetectLiquiditySweep(const MqlRates &rates[],
                                     int index,
                                     const SwingPoint &swingHighs[],
                                     const SwingPoint &swingLows[]);

    //--- Structure-state based sweep flag
    static bool HasLiquiditySweep(const MarketStructureState &state, int lookback);
};

//+------------------------------------------------------------------+
//| Detect Liquidity Sweep                                          |
//+------------------------------------------------------------------+
bool CStructureLiquidity::DetectLiquiditySweep(const MqlRates &rates[],
                                               int index,
                                               const SwingPoint &swingHighs[],
                                               const SwingPoint &swingLows[])
{
    if(index < 2 || index >= ArraySize(rates) - 1)
        return false;
    
    // Check for sweep above previous high
    if(ArraySize(swingHighs) > 0)
    {
        double lastHigh = swingHighs[ArraySize(swingHighs)-1].price;
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
    if(ArraySize(swingLows) > 0)
    {
        double lastLow = swingLows[ArraySize(swingLows)-1].price;
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
//| Check for recent liquidity sweep                                |
//+------------------------------------------------------------------+
bool CStructureLiquidity::HasLiquiditySweep(const MarketStructureState &state, int lookback)
{
    // This would need to track sweep events
    // For now, return based on structure analysis
    return state.currentStructure == STRUCT_TYPE_SWEEP;
}

#endif // STRUCTURE_LIQUIDITY_MQH
