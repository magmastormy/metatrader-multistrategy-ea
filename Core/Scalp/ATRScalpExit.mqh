// Open position management for the ATR scalping engine: partial
// close at 1R, breakeven shift and tight trailing stop.
// Extracted verbatim from ATRScalpingEngine.mqh (structural only).
// The CTrade instance is passed in by reference so the engine keeps
// using one shared trade object exactly as before.
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_ATR_SCALP_EXIT_MQH
#define CORE_SCALP_ATR_SCALP_EXIT_MQH

#include <Trade\Trade.mqh>

class CATRScalpExit
{
private:
   // Batch 152 (S-H-04): tickets that already took their 1R partial. Without
   // this latch every tick re-closed half of the remaining volume - a geometric
   // decay into repeated deal fees.
   static ulong s_partialedTickets[];
   static int   s_partialedCount;

   static void PrunePartialedLatches()
   {
      for(int i = s_partialedCount - 1; i >= 0; i--)
      {
         if(!PositionSelectByTicket(s_partialedTickets[i]))
         {
            for(int j = i; j < s_partialedCount - 1; j++)
               s_partialedTickets[j] = s_partialedTickets[j + 1];
            s_partialedCount--;
         }
      }
   }

   static bool HasTakenPartial(const ulong ticket)
   {
      for(int p = 0; p < s_partialedCount; p++)
      {
         if(s_partialedTickets[p] == ticket)
            return true;
      }
      return false;
   }

public:
   static void ManageScalpPositions(const string symbol, CTrade &trade)
   {
      PrunePartialedLatches();

      int total = PositionsTotal();
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return;

      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;

         // Only manage ATR-SCALP positions for this symbol
         string posSymbol = PositionGetString(POSITION_SYMBOL);
         if(posSymbol != symbol) continue;

         string comment = PositionGetString(POSITION_COMMENT);
         if(StringFind(comment, "ATR-SCALP") < 0) continue;

         double openPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL    = PositionGetDouble(POSITION_SL);
         double currentTP    = PositionGetDouble(POSITION_TP);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double volume       = PositionGetDouble(POSITION_VOLUME);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         double profitPoints = 0.0;
         if(posType == POSITION_TYPE_BUY)
            profitPoints = (currentPrice - openPrice) / point;
         else
            profitPoints = (openPrice - currentPrice) / point;

         // SL distance in points (1R)
         double slDistancePoints = 0.0;
         if(posType == POSITION_TYPE_BUY)
            slDistancePoints = MathAbs(openPrice - currentSL) / point;
         else
            slDistancePoints = MathAbs(currentSL - openPrice) / point;

         // 1. Partial close at 1R profit (50% of position) - once per ticket
         if(profitPoints >= slDistancePoints && slDistancePoints > 0.0)
         {
            double minVol  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
            double stepVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
            if(stepVol <= 0.0) stepVol = 0.01;

            double halfVol = NormalizeDouble(volume * 0.5, 2);
            halfVol = MathFloor((halfVol + 1e-12) / stepVol) * stepVol;
            halfVol = NormalizeDouble(halfVol, 2);

            if(!HasTakenPartial(ticket) && halfVol >= minVol && halfVol < volume)
            {
               if(trade.PositionClosePartial(ticket, halfVol))
               {
                  if(s_partialedCount >= ArraySize(s_partialedTickets))
                     ArrayResize(s_partialedTickets, s_partialedCount + 16);
                  s_partialedTickets[s_partialedCount++] = ticket;

                  PrintFormat("[ATR-SCALP-PARTIAL] %s | ticket=%I64u | closed=%.2f | profit_pts=%.1f | 1R=%.1f",
                              symbol, ticket, halfVol, profitPoints, slDistancePoints);
               }
            }
         }

         // 2. Move SL to breakeven after breakevenProfitPoints (10 points)
         int breakevenProfitPoints = 10;
         if(profitPoints >= breakevenProfitPoints)
         {
            double beSL = 0.0;
            if(posType == POSITION_TYPE_BUY)
               beSL = NormalizeDouble(openPrice + 1 * point, digits);  // Entry + 1 point buffer
            else
               beSL = NormalizeDouble(openPrice - 1 * point, digits);

            // Only move SL if it improves the position
            bool shouldMove = false;
            if(posType == POSITION_TYPE_BUY && (currentSL < beSL || currentSL == 0.0))
               shouldMove = true;
            else if(posType == POSITION_TYPE_SELL && (currentSL > beSL || currentSL == 0.0))
               shouldMove = true;

            if(shouldMove)
            {
               if(trade.PositionModify(ticket, beSL, currentTP))
               {
                  PrintFormat("[ATR-SCALP-BREAKEVEN] %s | ticket=%I64u | SL=%.5f | profit_pts=%.1f",
                              symbol, ticket, beSL, profitPoints);
               }
            }
         }

         // 3. Tight trailing after breakeven (15 points)
         int trailingDistancePoints = 15;
         // Only trail if SL is already at breakeven or better
         bool isBreakevenOrBetter = false;
         if(posType == POSITION_TYPE_BUY && currentSL >= openPrice)
            isBreakevenOrBetter = true;
         else if(posType == POSITION_TYPE_SELL && (currentSL <= openPrice && currentSL > 0.0))
            isBreakevenOrBetter = true;

         if(isBreakevenOrBetter)
         {
            double newSL = 0.0;
            if(posType == POSITION_TYPE_BUY)
            {
               newSL = NormalizeDouble(currentPrice - trailingDistancePoints * point, digits);
               if(newSL > currentSL)
               {
                  trade.PositionModify(ticket, newSL, currentTP);
               }
            }
            else
            {
               newSL = NormalizeDouble(currentPrice + trailingDistancePoints * point, digits);
               if(currentSL == 0.0 || newSL < currentSL)
               {
                  trade.PositionModify(ticket, newSL, currentTP);
               }
            }
         }
      }
   }
};

//--- Batch 152 (S-H-04): static latch storage
ulong CATRScalpExit::s_partialedTickets[];
int   CATRScalpExit::s_partialedCount = 0;

#endif // CORE_SCALP_ATR_SCALP_EXIT_MQH
