//+------------------------------------------------------------------+
//| StructureScore.mqh - Swing strength + structure state scoring    |
//| Extracted verbatim from StructureEngine.mqh (no behavior change) |
//|                                                                  |
//| Stateless: the engine state is injected by reference so the      |
//| scorer stays free of engine ownership.                           |
//+------------------------------------------------------------------+
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef STRUCTURE_SCORE_MQH
#define STRUCTURE_SCORE_MQH

#include "StructureTypes.mqh"

//+------------------------------------------------------------------+
//| Stateless structure scoring helpers                              |
//+------------------------------------------------------------------+
class CStructureScore
{
public:
    //--- 0-100 strength score for a single swing point
    static double CalculateSwingStrength(const MqlRates &rates[], int index, bool isHigh);

    //--- Classify HH/HL/LH/LL/EQH/EQL and maintain BOS/CHOCH counters
    static void UpdateStructureState(MarketStructureState &state,
                                     const SwingPoint &newPoint,
                                     bool isHigh);

    //--- Overall directional bias + structure strength from swing sequences
    static void UpdateBiasAndStrength(MarketStructureState &state,
                                      const SwingPoint &swingHighs[],
                                      const SwingPoint &swingLows[],
                                      double minSwingSize);
};

//+------------------------------------------------------------------+
//| Calculate swing point strength                                  |
//+------------------------------------------------------------------+
double CStructureScore::CalculateSwingStrength(const MqlRates &rates[], int index, bool isHigh)
{
    double strength = 50.0; // Base strength
    
    // Factor 1: Volume (if available)
    if(rates[index].tick_volume > 0)
    {
        double avgVolume = 0;
        int validBars = 0;  // Batch 117: count actual valid bars
        for(int i = index - 5; i <= index + 5; i++)
        {
            if(i >= 0 && i < ArraySize(rates))
            {
                avgVolume += (double)rates[i].tick_volume;
                validBars++;
            }
        }
        avgVolume = (validBars > 0) ? avgVolume / (double)validBars : 0;
        
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
void CStructureScore::UpdateStructureState(MarketStructureState &state,
                                           const SwingPoint &newPoint,
                                           bool isHigh)
{
    if(isHigh)
    {
        state.prevHigh = state.lastHigh;
        state.lastHigh = newPoint.price;
        
        // Determine structure type
        if(state.prevHigh > 0)
        {
            if(newPoint.price > state.prevHigh)
            {
                state.currentStructure = STRUCT_TYPE_HH;
                state.bosCount++;
            }
            else if(newPoint.price < state.prevHigh)
            {
                state.currentStructure = STRUCT_TYPE_LH;
                if(state.isBullish)
                {
                    state.chochCount++;
                }
            }
            else
            {
                state.currentStructure = STRUCT_TYPE_EQH;
            }
        }
    }
    else
    {
        state.prevLow = state.lastLow;
        state.lastLow = newPoint.price;
        
        // Determine structure type
        if(state.prevLow > 0)
        {
            if(newPoint.price < state.prevLow)
            {
                state.currentStructure = STRUCT_TYPE_LL;
                state.bosCount++;
            }
            else if(newPoint.price > state.prevLow)
            {
                state.currentStructure = STRUCT_TYPE_HL;
                if(state.isBearish)
                {
                    state.chochCount++;
                }
            }
            else
            {
                state.currentStructure = STRUCT_TYPE_EQL;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate overall structure strength / directional bias         |
//+------------------------------------------------------------------+
void CStructureScore::UpdateBiasAndStrength(MarketStructureState &state,
                                            const SwingPoint &swingHighs[],
                                            const SwingPoint &swingLows[],
                                            double minSwingSize)
{
    if(ArraySize(swingHighs) > 1 && ArraySize(swingLows) > 1)
    {
        double highDiff = swingHighs[ArraySize(swingHighs)-1].price - 
                         swingHighs[ArraySize(swingHighs)-2].price;
        double lowDiff = swingLows[ArraySize(swingLows)-1].price - 
                        swingLows[ArraySize(swingLows)-2].price;
        
        if(highDiff > 0 && lowDiff > 0)
        {
            state.isBullish = true;
            state.isBearish = false;
            state.structureStrength = MathMin(100, (highDiff / minSwingSize) * 50);
        }
        else if(highDiff < 0 && lowDiff < 0)
        {
            state.isBullish = false;
            state.isBearish = true;
            state.structureStrength = MathMin(100, (MathAbs(lowDiff) / minSwingSize) * 50);
        }
    }
}

#endif // STRUCTURE_SCORE_MQH
