//+------------------------------------------------------------------+
//| GridRecoverySequence.mqh                                         |
//| Recovery sequencing: grid direction selection, active-level scan  |
//| and pruning, profit census and next-level trigger evaluation.     |
//| Extracted verbatim from GridRecoveryEngine.mqh (structural only). |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_GRID_RECOVERY_SEQUENCE_MQH
#define CORE_SCALP_GRID_RECOVERY_SEQUENCE_MQH

#include "GridRecoveryTypes.mqh"

//+------------------------------------------------------------------+
//| CGridRecoverySequence — stateless grid sequencing helpers         |
//+------------------------------------------------------------------+
class CGridRecoverySequence
{
public:
   //+------------------------------------------------------------------+
   //| Batch 117: Use price SMA (not ATR SMA) for direction determination|
   //| Compute 50-bar price SMA to determine mean-reversion direction    |
   //+------------------------------------------------------------------+
   static int DetermineGridDirection(const string symbol, double bid, double ask)
   {
      double midPrice = (bid + ask) / 2.0;
      double priceSMA = 0;
      double closes[];
      ArraySetAsSeries(closes, true);
      int copied = CopyClose(symbol, PERIOD_CURRENT, 0, 50, closes);
      if(copied >= 50)
      {
         for(int j = 0; j < 50; j++)
            priceSMA += closes[j];
         priceSMA /= 50.0;
      }
      else
         priceSMA = midPrice; // fallback: no direction bias

      if(midPrice < priceSMA)
         return 1;    // BUY grid — price below SMA, expect reversion up
      else
         return -1;   // SELL grid — price above SMA, expect reversion down
   }

   //+------------------------------------------------------------------+
   //| Check if all levels are in profit (caller closes the entire grid).|
   //| Levels whose position no longer exists are marked inactive.       |
   //+------------------------------------------------------------------+
   static bool AllLevelsInProfit(SGridSymbolState &state)
   {
      bool allInProfit = true;
      for(int l = 0; l < state.activeLevelCount; l++)
      {
         if(!state.levels[l].isActive || state.levels[l].ticket == 0)
            continue;

         if(PositionSelectByTicket(state.levels[l].ticket))
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit <= 0.0)
            {
               allInProfit = false;
               break;
            }
         }
         else
         {
            // Position no longer exists — mark as inactive
            state.levels[l].isActive = false;
            state.levels[l].ticket = 0;
         }
      }
      return allInProfit;
   }

   //+------------------------------------------------------------------+
   //| Scan active levels, pruning ones whose position has closed.       |
   //| Returns the live level count and reports the highest live level.  |
   //+------------------------------------------------------------------+
   static int ScanActiveLevels(SGridSymbolState &state, int &lastActiveLevel)
   {
      int currentActiveCount = 0;
      lastActiveLevel = -1;

      for(int l = 0; l < state.activeLevelCount; l++)
      {
         if(state.levels[l].isActive)
         {
            // Verify position still exists
            if(state.levels[l].ticket > 0)
            {
               if(!PositionSelectByTicket(state.levels[l].ticket))
               {
                  // Position closed — mark inactive
                  state.levels[l].isActive = false;
                  state.levels[l].ticket = 0;
                  continue;
               }
            }
            currentActiveCount++;
            lastActiveLevel = l;
         }
      }
      return currentActiveCount;
   }

   //+------------------------------------------------------------------+
   //| Check if price has moved against us enough to warrant next level  |
   //+------------------------------------------------------------------+
   static bool HasPriceMovedForNextLevel(const string symbol, int direction, double lastEntry, double gridSpacing)
   {
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      double currentPrice = (direction == 1) ? bid : ask;

      bool priceMovedEnough = false;
      if(direction == 1)
         priceMovedEnough = (lastEntry - currentPrice >= gridSpacing * 0.8);
      else
         priceMovedEnough = (currentPrice - lastEntry >= gridSpacing * 0.8);

      return priceMovedEnough;
   }
};

#endif // CORE_SCALP_GRID_RECOVERY_SEQUENCE_MQH
