//+------------------------------------------------------------------+
//| TrendMTF.mqh - Multi-timeframe alignment / consensus             |
//| Extracted verbatim from TrendEngine.mqh (no behavior change)     |
//+------------------------------------------------------------------+
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef TREND_MTF_MQH
#define TREND_MTF_MQH

#include "TrendTypes.mqh"

//+------------------------------------------------------------------+
//| Stateless multi-timeframe aggregator. Consumes the three         |
//| per-timeframe TrendState members of MTFTrendState and fills in   |
//| alignment / isAligned / consensus.                               |
//+------------------------------------------------------------------+
class CTrendMTF
{
public:
    //--- Weighted vote: HTF 40 / MTF 35 / LTF 25.
    static void ComputeAlignment(MTFTrendState &state);
};

//+------------------------------------------------------------------+
//| Compute MTF Alignment and Consensus                             |
//+------------------------------------------------------------------+
void CTrendMTF::ComputeAlignment(MTFTrendState &state)
{
    // Calculate alignment
    int alignmentScore = 0;
    int totalWeight = 0;
    
    // HTF has highest weight (40%)
    if(state.htf.type == TREND_BULLISH_STRONG || state.htf.type == TREND_BULLISH_WEAK)
    {
        alignmentScore += 40;
    }
    else if(state.htf.type == TREND_BEARISH_STRONG || state.htf.type == TREND_BEARISH_WEAK)
    {
        alignmentScore -= 40;
    }
    
    // MTF has medium weight (35%)
    if(state.mtf.type == TREND_BULLISH_STRONG || state.mtf.type == TREND_BULLISH_WEAK)
    {
        alignmentScore += 35;
    }
    else if(state.mtf.type == TREND_BEARISH_STRONG || state.mtf.type == TREND_BEARISH_WEAK)
    {
        alignmentScore -= 35;
    }
    
    // LTF has lowest weight (25%)
    if(state.ltf.type == TREND_BULLISH_STRONG || state.ltf.type == TREND_BULLISH_WEAK)
    {
        alignmentScore += 25;
    }
    else if(state.ltf.type == TREND_BEARISH_STRONG || state.ltf.type == TREND_BEARISH_WEAK)
    {
        alignmentScore -= 25;
    }
    
    // Calculate alignment percentage
    state.alignment = MathAbs(alignmentScore);
    
    // Determine if aligned
    state.isAligned = state.alignment >= 75;
    
    // Determine consensus
    if(alignmentScore > 50)
    {
        state.consensus = state.htf.strength > 50 ? 
                          TREND_BULLISH_STRONG : TREND_BULLISH_WEAK;
    }
    else if(alignmentScore < -50)
    {
        state.consensus = state.htf.strength > 50 ? 
                          TREND_BEARISH_STRONG : TREND_BEARISH_WEAK;
    }
    else
    {
        state.consensus = TREND_RANGING;
    }
}

#endif // TREND_MTF_MQH
