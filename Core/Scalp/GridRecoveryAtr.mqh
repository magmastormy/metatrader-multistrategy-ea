//+------------------------------------------------------------------+
//| GridRecoveryAtr.mqh                                              |
//| ATR indicator handle lifecycle per symbol plus the L10-017        |
//| incremental ATR/EMA refresh used by the grid recovery engine.     |
//| Extracted verbatim from GridRecoveryEngine.mqh (structural only). |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_GRID_RECOVERY_ATR_MQH
#define CORE_SCALP_GRID_RECOVERY_ATR_MQH

#include "GridRecoveryTypes.mqh"

//+------------------------------------------------------------------+
//| CGridRecoveryAtr — owns the per-symbol ATR indicator handles      |
//+------------------------------------------------------------------+
class CGridRecoveryAtr
{
private:
   int   m_atrHandles[];

public:
   //+------------------------------------------------------------------+
   //| Create an ATR indicator handle for a symbol                       |
   //+------------------------------------------------------------------+
   static int CreateHandle(const string symbol, int atrPeriod)
   {
      return iATR(symbol, PERIOD_M1, atrPeriod);
   }

   //+------------------------------------------------------------------+
   //| Grow the handle storage to hold newSize entries                   |
   //+------------------------------------------------------------------+
   void Resize(int newSize)
   {
      ArrayResize(m_atrHandles, newSize);
   }

   //+------------------------------------------------------------------+
   //| Store / read a handle for a symbol slot                           |
   //+------------------------------------------------------------------+
   void SetHandle(int idx, int handle)
   {
      m_atrHandles[idx] = handle;
   }

   int GetHandle(int idx) const
   {
      return m_atrHandles[idx];
   }

   //+------------------------------------------------------------------+
   //| Release all indicator handles for the first count slots           |
   //+------------------------------------------------------------------+
   void ReleaseAll(int count)
   {
      for(int i = 0; i < count; i++)
      {
         if(m_atrHandles[i] != INVALID_HANDLE)
         {
            IndicatorRelease(m_atrHandles[i]);
            m_atrHandles[i] = INVALID_HANDLE;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Update ATR value for a symbol                                     |
   //+------------------------------------------------------------------+
   void UpdateATR(int idx, SGridSymbolState &state)
   {
      if(m_atrHandles[idx] == INVALID_HANDLE)
         return;

      // Read current ATR value
      double atrBuf[];
      ArraySetAsSeries(atrBuf, true);
      if(CopyBuffer(m_atrHandles[idx], 0, 0, 1, atrBuf) <= 0)
         return;

      state.currentATR = atrBuf[0];

      // L10-017: Use incremental EMA instead of full CopyBuffer loop for efficiency
      // EMA formula: EMA_today = alpha * value_today + (1 - alpha) * EMA_yesterday
      // alpha = 2 / (period + 1)
      const int atrEmaPeriod = 50;
      double alpha = 2.0 / (atrEmaPeriod + 1.0);

      if(state.atrSMA <= 0.0)
      {
         // First initialization - use simple average from available history
         double atrHistory[];
         ArraySetAsSeries(atrHistory, true);
         int copied = CopyBuffer(m_atrHandles[idx], 0, 0, atrEmaPeriod, atrHistory);
         if(copied > 0)
         {
            double sum = 0.0;
            for(int i = 0; i < copied; i++)
               sum += atrHistory[i];
            state.atrSMA = sum / (double)copied;
         }
         else
         {
            state.atrSMA = atrBuf[0];
         }
      }
      else
      {
         // Incremental EMA update - O(1) instead of O(n)
         state.atrSMA = alpha * atrBuf[0] + (1.0 - alpha) * state.atrSMA;
      }
   }
};

#endif // CORE_SCALP_GRID_RECOVERY_ATR_MQH
