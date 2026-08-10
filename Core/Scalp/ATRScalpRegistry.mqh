//+------------------------------------------------------------------+
//| ATRScalpRegistry.mqh                                             |
//| Symbol slot registry for the ATR scalping engine: index lookup,  |
//| state-slot defaults and the string-safe array growth pattern.    |
//| Extracted verbatim from ATRScalpingEngine.mqh (structural only). |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_ATR_SCALP_REGISTRY_MQH
#define CORE_SCALP_ATR_SCALP_REGISTRY_MQH

#include "ATRScalpTypes.mqh"

//+------------------------------------------------------------------+
//| CATRScalpRegistry — stateless helpers over the symbol state array |
//+------------------------------------------------------------------+
class CATRScalpRegistry
{
public:
   //+------------------------------------------------------------------+
   //| Find symbol index in the states array                             |
   //+------------------------------------------------------------------+
   static int FindSymbolIndex(const SATRScalpSymbolState &states[], int symbolCount, const string symbol)
   {
      for(int i = 0; i < symbolCount; i++)
      {
         if(states[i].symbol == symbol)
            return i;
      }
      return -1;
   }

   //+------------------------------------------------------------------+
   //| Initialize a symbol state slot with defaults                      |
   //+------------------------------------------------------------------+
   static void InitializeSymbolState(SATRScalpSymbolState &states[], int idx, const string symbol, int spikeIntervalSec)
   {
      states[idx].symbol                   = symbol;
      states[idx].isActive                 = true;
      states[idx].lastTradeTime            = 0;
      states[idx].activePositions          = 0;
      states[idx].currentATR               = 0.0;
      states[idx].emaFastValue             = 0.0;
      states[idx].emaSlowValue             = 0.0;
      states[idx].rsiValue                 = 0.0;
      states[idx].lastEmaCrossDirection    = 0;
      states[idx].lastSpikeTime            = 0;
      states[idx].expectedSpikeIntervalSec = spikeIntervalSec;
      states[idx].inSpikeWindow            = false;
   }

   //+------------------------------------------------------------------+
   //| Grow the state array — temp struct pattern for string members     |
   //+------------------------------------------------------------------+
   static void GrowStates(SATRScalpSymbolState &states[], int symbolCount, int newSize)
   {
      SATRScalpSymbolState tempStates[];
      ArrayResize(tempStates, newSize);
      for(int i = 0; i < symbolCount; i++)
         tempStates[i] = states[i];
      ArrayResize(states, newSize);
      for(int i = 0; i < symbolCount; i++)
         states[i] = tempStates[i];
   }
};

#endif // CORE_SCALP_ATR_SCALP_REGISTRY_MQH
