// StructureBOSCHoCH.mqh - Break of Structure / Change of Character
// Extracted verbatim from StructureEngine.mqh (no behavior change)
// Stateless: swing arrays and the structure state are injected so
// the detector holds no engine state of its own.
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef STRUCTURE_BOS_CHOCH_MQH
#define STRUCTURE_BOS_CHOCH_MQH

#include "StructureTypes.mqh"

class CStructureBOSCHoCH
{
public:
    //--- Pairwise detection between two consecutive swing points
    static bool DetectBOS(const SwingPoint &current, const SwingPoint &previous);
    static bool DetectCHOCH(const MarketStructureState &state,
                            const SwingPoint &current,
                            const SwingPoint &previous);

    //--- Lookback scans over the recorded swing sequences
    static bool HasBullishBOS(const SwingPoint &swingHighs[],
                              const SwingPoint &swingLows[],
                              int lookback);
    static bool HasBearishBOS(const SwingPoint &swingHighs[],
                              const SwingPoint &swingLows[],
                              int lookback);
    static bool HasBullishCHOCH(const MarketStructureState &state,
                                const SwingPoint &swingLows[],
                                int lookback);
    static bool HasBearishCHOCH(const MarketStructureState &state,
                                const SwingPoint &swingHighs[],
                                int lookback);
};

bool CStructureBOSCHoCH::DetectBOS(const SwingPoint &current, const SwingPoint &previous)
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

bool CStructureBOSCHoCH::DetectCHOCH(const MarketStructureState &state,
                                     const SwingPoint &current,
                                     const SwingPoint &previous)
{
    if(!current.isValid || !previous.isValid)
        return false;
    
    // Bearish CHOCH: Lower high after uptrend
    if(state.isBullish && current.type == STRUCT_TYPE_LH)
        return true;
    
    // Bullish CHOCH: Higher low after downtrend
    if(state.isBearish && current.type == STRUCT_TYPE_HL)
        return true;
    
    return false;
}

bool CStructureBOSCHoCH::HasBullishBOS(const SwingPoint &swingHighs[],
                                       const SwingPoint &swingLows[],
                                       int lookback)
{
    int highCount = ArraySize(swingHighs);
    int lowCount = ArraySize(swingLows);
    
    if(highCount < 2 || lowCount < 2)
        return false;
    
    for(int i = MathMax(0, highCount - lookback); i < highCount - 1; i++)
    {
        if(swingHighs[i+1].price > swingHighs[i].price)
        {
            // Also check for higher low
            for(int j = MathMax(0, lowCount - lookback); j < lowCount - 1; j++)
            {
                if(swingLows[j+1].price > swingLows[j].price &&
                   MathAbs(swingHighs[i+1].bar - swingLows[j+1].bar) < 10)
                {
                    return true;
                }
            }
        }
    }
    
    return false;
}

bool CStructureBOSCHoCH::HasBearishBOS(const SwingPoint &swingHighs[],
                                       const SwingPoint &swingLows[],
                                       int lookback)
{
    int highCount = ArraySize(swingHighs);
    int lowCount = ArraySize(swingLows);
    
    if(highCount < 2 || lowCount < 2)
        return false;
    
    for(int i = MathMax(0, lowCount - lookback); i < lowCount - 1; i++)
    {
        if(swingLows[i+1].price < swingLows[i].price)
        {
            // Also check for lower high
            for(int j = MathMax(0, highCount - lookback); j < highCount - 1; j++)
            {
                if(swingHighs[j+1].price < swingHighs[j].price &&
                   MathAbs(swingLows[i+1].bar - swingHighs[j+1].bar) < 10)
                {
                    return true;
                }
            }
        }
    }
    
    return false;
}

bool CStructureBOSCHoCH::HasBullishCHOCH(const MarketStructureState &state,
                                         const SwingPoint &swingLows[],
                                         int lookback)
{
    if(!state.isBearish || state.chochCount == 0)
        return false;
    
    int lowCount = ArraySize(swingLows);
    if(lowCount < 2)
        return false;
    
    // Check for higher low after bearish trend
    for(int i = MathMax(0, lowCount - lookback); i < lowCount - 1; i++)
    {
        if(swingLows[i+1].price > swingLows[i].price)
            return true;
    }
    
    return false;
}

bool CStructureBOSCHoCH::HasBearishCHOCH(const MarketStructureState &state,
                                         const SwingPoint &swingHighs[],
                                         int lookback)
{
    if(!state.isBullish || state.chochCount == 0)
        return false;
    
    int highCount = ArraySize(swingHighs);
    if(highCount < 2)
        return false;
    
    // Check for lower high after bullish trend
    for(int i = MathMax(0, highCount - lookback); i < highCount - 1; i++)
    {
        if(swingHighs[i+1].price < swingHighs[i].price)
            return true;
    }
    
    return false;
}

#endif // STRUCTURE_BOS_CHOCH_MQH
