//+------------------------------------------------------------------+
//| ATRScalpMetrics.mqh                                              |
//| ATR scalping statistics / accounting: skipped-trade counter,     |
//| live scalp position census and the diagnostics dump.             |
//| Extracted verbatim from ATRScalpingEngine.mqh (structural only). |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_ATR_SCALP_METRICS_MQH
#define CORE_SCALP_ATR_SCALP_METRICS_MQH

#include "ATRScalpTypes.mqh"

//+------------------------------------------------------------------+
//| CATRScalpMetrics — owns the skipped counter, census + diagnostics |
//+------------------------------------------------------------------+
class CATRScalpMetrics
{
private:
   int   m_totalTradesSkipped;

public:
   //+------------------------------------------------------------------+
   //| Constructor — counters start at zero                              |
   //+------------------------------------------------------------------+
   CATRScalpMetrics() :
      m_totalTradesSkipped(0)
   {
   }

   //+------------------------------------------------------------------+
   //| Counter mutator / accessor                                        |
   //+------------------------------------------------------------------+
   void RecordTradeSkipped()      { m_totalTradesSkipped++;    }
   int  TotalTradesSkipped() const { return m_totalTradesSkipped; }

   //+------------------------------------------------------------------+
   //| Count positions with "ATR-SCALP" in comment                       |
   //+------------------------------------------------------------------+
   static int GetActiveScalpPositions()
   {
      int count = 0;
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(PositionSelectByTicket(ticket))
         {
            string comment = PositionGetString(POSITION_COMMENT);
            if(StringFind(comment, "ATR-SCALP") >= 0)
               count++;
         }
      }
      return count;
   }

   //+------------------------------------------------------------------+
   //| Print diagnostics                                                 |
   //+------------------------------------------------------------------+
   static void PrintDiagnostics(const SATRScalpSymbolState &states[], int symbolCount,
                                int totalTradesOpened, int totalTradesSkipped, int totalSpikeWindowBlocks)
   {
      PrintFormat("[ATR-SCALP-DIAG] symbols=%d | trades=%d | skipped=%d | spikeBlocks=%d | activePos=%d",
                  symbolCount,
                  totalTradesOpened,
                  totalTradesSkipped,
                  totalSpikeWindowBlocks,
                  GetActiveScalpPositions());

      for(int i = 0; i < symbolCount; i++)
      {
         PrintFormat("[ATR-SCALP-DIAG] %s | atr=%.5f emaFast=%.5f emaSlow=%.5f rsi=%.1f cross=%d spikeWindow=%s spikeInterval=%ds lastSpike=%s",
                     states[i].symbol,
                     states[i].currentATR,
                     states[i].emaFastValue,
                     states[i].emaSlowValue,
                     states[i].rsiValue,
                     states[i].lastEmaCrossDirection,
                     states[i].inSpikeWindow ? "Y" : "N",
                     states[i].expectedSpikeIntervalSec,
                     TimeToString(states[i].lastSpikeTime));
      }
   }
};

#endif // CORE_SCALP_ATR_SCALP_METRICS_MQH
