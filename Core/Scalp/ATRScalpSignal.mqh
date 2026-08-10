//+------------------------------------------------------------------+
//| ATRScalpSignal.mqh                                               |
//| ATR/EMA/RSI indicator buffers and scalp signal evaluation for    |
//| the ATR scalping engine. Owns the per-symbol indicator handles   |
//| and the spike-window block counter.                              |
//| Extracted verbatim from ATRScalpingEngine.mqh (structural only). |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_ATR_SCALP_SIGNAL_MQH
#define CORE_SCALP_ATR_SCALP_SIGNAL_MQH

#include "ATRScalpTypes.mqh"
#include "ATRScalpFilter.mqh"

//+------------------------------------------------------------------+
//| CATRScalpSignal — indicator handles + signal evaluation           |
//+------------------------------------------------------------------+
class CATRScalpSignal
{
private:
   // Indicator handles per symbol
   int   m_atrHandles[];
   int   m_emaFastHandles[];
   int   m_emaSlowHandles[];
   int   m_rsiHandles[];

   // Statistics
   int   m_totalSpikeWindowBlocks;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CATRScalpSignal() :
      m_totalSpikeWindowBlocks(0)
   {
   }

   //+------------------------------------------------------------------+
   //| Resize every handle array to hold newSize symbols                 |
   //+------------------------------------------------------------------+
   void ResizeHandles(int newSize)
   {
      ArrayResize(m_atrHandles, newSize);
      ArrayResize(m_emaFastHandles, newSize);
      ArrayResize(m_emaSlowHandles, newSize);
      ArrayResize(m_rsiHandles, newSize);
   }

   //+------------------------------------------------------------------+
   //| Store the handles created for one symbol slot                     |
   //+------------------------------------------------------------------+
   void SetHandles(int idx, int atrHandle, int emaFastHandle, int emaSlowHandle, int rsiHandle)
   {
      m_atrHandles[idx]     = atrHandle;
      m_emaFastHandles[idx] = emaFastHandle;
      m_emaSlowHandles[idx] = emaSlowHandle;
      m_rsiHandles[idx]     = rsiHandle;
   }

   //+------------------------------------------------------------------+
   //| Batch 117: Handles are owned by CIndicatorManager — do NOT release |
   //| them. Just invalidate our references to prevent stale handle usage |
   //+------------------------------------------------------------------+
   void InvalidateHandles(int symbolCount)
   {
      for(int i = 0; i < symbolCount; i++)
      {
         m_atrHandles[i] = INVALID_HANDLE;
         m_emaFastHandles[i] = INVALID_HANDLE;
         m_emaSlowHandles[i] = INVALID_HANDLE;
         m_rsiHandles[i] = INVALID_HANDLE;
      }
   }

   //+------------------------------------------------------------------+
   //| Spike-window block counter                                        |
   //+------------------------------------------------------------------+
   int TotalSpikeWindowBlocks() const { return m_totalSpikeWindowBlocks; }

   //+------------------------------------------------------------------+
   //| Update indicator values for a symbol                              |
   //+------------------------------------------------------------------+
   bool UpdateIndicators(int idx, SATRScalpSymbolState &state)
   {
      // ATR
      if(m_atrHandles[idx] != INVALID_HANDLE)
      {
         double atrBuf[];
         ArraySetAsSeries(atrBuf, true);
         if(CopyBuffer(m_atrHandles[idx], 0, 0, 1, atrBuf) > 0)
            state.currentATR = atrBuf[0];
      }

      // EMA Fast — need 2 bars for crossover
      double emaFastBuf[];
      ArraySetAsSeries(emaFastBuf, true);
      bool fastOk = false;
      if(m_emaFastHandles[idx] != INVALID_HANDLE)
      {
         if(CopyBuffer(m_emaFastHandles[idx], 0, 0, 2, emaFastBuf) >= 2)
         {
            state.emaFastValue = emaFastBuf[0];
            fastOk = true;
         }
      }

      // EMA Slow — need 2 bars for crossover
      double emaSlowBuf[];
      ArraySetAsSeries(emaSlowBuf, true);
      bool slowOk = false;
      if(m_emaSlowHandles[idx] != INVALID_HANDLE)
      {
         if(CopyBuffer(m_emaSlowHandles[idx], 0, 0, 2, emaSlowBuf) >= 2)
         {
            state.emaSlowValue = emaSlowBuf[0];
            slowOk = true;
         }
      }

      // Detect EMA crossover direction
      if(fastOk && slowOk)
      {
         double fastCurr = emaFastBuf[0], fastPrev = emaFastBuf[1];
         double slowCurr = emaSlowBuf[0], slowPrev = emaSlowBuf[1];

         if(fastPrev <= slowPrev && fastCurr > slowCurr)
            state.lastEmaCrossDirection = 1;   // Bullish cross
         else if(fastPrev >= slowPrev && fastCurr < slowCurr)
            state.lastEmaCrossDirection = -1;  // Bearish cross
         // Keep previous cross direction if no new cross
      }

      // RSI
      if(m_rsiHandles[idx] != INVALID_HANDLE)
      {
         double rsiBuf[];
         ArraySetAsSeries(rsiBuf, true);
         if(CopyBuffer(m_rsiHandles[idx], 0, 0, 1, rsiBuf) > 0)
            state.rsiValue = rsiBuf[0];
      }

      return (state.currentATR > 0.0);
   }

   //+------------------------------------------------------------------+
   //| Evaluate scalp signal: EMA crossover + RSI + spread + spike gate  |
   //| Returns 0=none, 1=BUY, -1=SELL                                   |
   //+------------------------------------------------------------------+
   int EvaluateScalpSignal(SATRScalpSymbolState &state, const SATRScalpingConfig &config)
   {
      // Must have a fresh EMA crossover
      int crossDir = state.lastEmaCrossDirection;
      if(crossDir == 0)
         return 0;

      // RSI confirmation
      if(!CATRScalpFilter::PassesRsiConfirmation(state, config, crossDir))
         return 0;

      // Spread gate: spread < spreadMaxATRRatio * ATR
      if(!CATRScalpFilter::PassesSpreadGate(state.symbol, state.currentATR, config.spreadMaxATRRatio))
         return 0;

      // Spike window gate
      if(CATRScalpFilter::IsInSpikeWindow(state, config.spikeWindowAvoidMinutes))
      {
         m_totalSpikeWindowBlocks++;
         return 0;
      }

      return crossDir;
   }
};

#endif // CORE_SCALP_ATR_SCALP_SIGNAL_MQH
