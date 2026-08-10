//+------------------------------------------------------------------+
//| GridRecoveryMetrics.mqh                                          |
//| Recovery statistics / accounting: lifetime grid + level counters  |
//| and live grid position census.                                    |
//| Extracted verbatim from GridRecoveryEngine.mqh (structural only). |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_GRID_RECOVERY_METRICS_MQH
#define CORE_SCALP_GRID_RECOVERY_METRICS_MQH

//+------------------------------------------------------------------+
//| CGridRecoveryMetrics — owns the grid recovery statistics counters |
//+------------------------------------------------------------------+
class CGridRecoveryMetrics
{
private:
   int   m_totalGridsOpened;
   int   m_totalGridsClosed;
   int   m_totalLevelsPlaced;

public:
   //+------------------------------------------------------------------+
   //| Constructor — counters start at zero                              |
   //+------------------------------------------------------------------+
   CGridRecoveryMetrics() :
      m_totalGridsOpened(0),
      m_totalGridsClosed(0),
      m_totalLevelsPlaced(0)
   {
   }

   //+------------------------------------------------------------------+
   //| Counter mutators                                                  |
   //+------------------------------------------------------------------+
   void RecordGridOpened()  { m_totalGridsOpened++;  }
   void RecordGridClosed()  { m_totalGridsClosed++;  }
   void RecordLevelPlaced() { m_totalLevelsPlaced++; }

   //+------------------------------------------------------------------+
   //| Counter accessors                                                 |
   //+------------------------------------------------------------------+
   int  TotalGridsOpened()  const { return m_totalGridsOpened;  }
   int  TotalGridsClosed()  const { return m_totalGridsClosed;  }
   int  TotalLevelsPlaced() const { return m_totalLevelsPlaced; }

   //+------------------------------------------------------------------+
   //| Count positions with "GRID-RECOVERY" in comment                   |
   //+------------------------------------------------------------------+
   static int GetActiveGridPositions()
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
            if(StringFind(comment, "GRID-RECOVERY") >= 0)
               count++;
         }
      }
      return count;
   }
};

#endif // CORE_SCALP_GRID_RECOVERY_METRICS_MQH
