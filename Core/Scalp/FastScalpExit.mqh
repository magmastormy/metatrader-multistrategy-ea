// Owns the tick-level scalp exit management: 1R partial close, breakeven, tight trailing, tracker reconciliation and risk-budget release.
// All methods are `static`; every piece of mutable state lives in
// the tracker / budget objects passed in by reference.
// IMPORTANT — original in-place semantics preserved:
// Section 3 (trailing) reads `breakevenSet` after section 2 may have just set it, so the local snapshot is mirrored (state.breakevenSet = true) at the same moment the tracker slot is marked - reproducing the original read-after-write exactly.
#property strict

#ifndef CORE_SCALP_FAST_SCALP_EXIT_MQH
#define CORE_SCALP_FAST_SCALP_EXIT_MQH

#include "../Trading/TradeManager.mqh"
#include "../Risk/UnifiedRiskManager.mqh"
#include "FastScalpTypes.mqh"
#include "FastScalpPositionTracker.mqh"
#include "FastScalpRiskBudget.mqh"

class CFastScalpExit
{
public:
// Was CFastScalpEngine::FreeScalpRiskBudget() — the tracker scan is
// done here, the arithmetic lives in CFastScalpRiskBudget.
   static void FreeScalpRiskBudget(ulong ticket,
                                   CFastScalpPositionTracker &tracker,
                                   CFastScalpRiskBudget &budget,
                                   CUnifiedRiskManager* riskManager)
   {
      int idx = tracker.FindScalpPositionState(ticket);
      bool found = (idx >= 0);
      SScalpPositionState state;
      if(found)
         tracker.GetState(idx, state);
      budget.FreeForTicket(ticket, found, state, riskManager);
   }

// Sync tracked scalp positions with actual open positions
   static void SyncScalpPositionTracking(CFastScalpPositionTracker &tracker,
                                         CFastScalpRiskBudget &budget,
                                         CUnifiedRiskManager* riskManager)
   {
      // Remove tracked positions that no longer exist or are no longer scalp
      for(int i = tracker.Count() - 1; i >= 0; i--)
      {
         ulong ticket = tracker.TicketAt(i);
         if(!PositionSelectByTicket(ticket) || !CFastScalpPositionTracker::IsScalpPosition(ticket))
         {
            FreeScalpRiskBudget(ticket, tracker, budget, riskManager);
            tracker.RemoveScalpPosition(ticket);
         }
      }

      // Add new scalp positions not yet tracked
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;

         string comment = PositionGetString(POSITION_COMMENT);
         // Prefix test: as a substring, "SCALP" also matched "ATR-SCALP",
         // so this engine registered the ATR scalp engine's positions and closed them
         // on its own 1R/partial rules. See FastScalpPositionTracker.
         if(StringFind(comment, "SCALP") != 0) continue;

         if(tracker.FindScalpPositionState(ticket) >= 0) continue;

         string posSymbol = PositionGetString(POSITION_SYMBOL);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl        = PositionGetDouble(POSITION_SL);
         double tp        = PositionGetDouble(POSITION_TP);
         double point     = SymbolInfoDouble(posSymbol, SYMBOL_POINT);

         double oneRPrice = 0.0;
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         // With SL==0 the old math produced a garbage 1R
         // (2x open price on buys, 0 on sells) - leave it unset so the partial
         // stage stays disabled for naked positions.
         if(point > 0.0 && sl > 0.0)
         {
            double slDistance = MathAbs(openPrice - sl) / point;
            if(posType == POSITION_TYPE_BUY)
               oneRPrice = openPrice + slDistance * point;
            else
               oneRPrice = openPrice - slDistance * point;
         }

         tracker.RegisterScalpPosition(ticket, posSymbol, openPrice, sl, tp, oneRPrice);
      }
   }

// Quick profit lock, tight trailing, partial close
// NOT throttled to 1 second like swing trailing
   static void ManageScalpPositions(CFastScalpPositionTracker &tracker,
                                    CFastScalpRiskBudget &budget,
                                    CTradeManager* tradeManager,
                                    CUnifiedRiskManager* riskManager,
                                    const SScalpConfig &config)
   {
      SyncScalpPositionTracking(tracker, budget, riskManager);

      for(int i = tracker.Count() - 1; i >= 0; i--)
      {
         SScalpPositionState state;
         if(!tracker.GetState(i, state))
            continue;

         ulong ticket = state.ticket;

         if(!PositionSelectByTicket(ticket))
         {
            // Position closed — remove from tracking and free risk budget
            FreeScalpRiskBudget(state.ticket, tracker, budget, riskManager);
            tracker.RemoveScalpPosition(ticket);
            continue;
         }

         string posSymbol   = PositionGetString(POSITION_SYMBOL);
         double openPrice   = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL   = PositionGetDouble(POSITION_SL);
         double currentTP   = PositionGetDouble(POSITION_TP);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double volume      = PositionGetDouble(POSITION_VOLUME);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double point       = SymbolInfoDouble(posSymbol, SYMBOL_POINT);
         if(point <= 0.0) continue;

         double profitPoints = 0.0;
         if(posType == POSITION_TYPE_BUY)
            profitPoints = (currentPrice - openPrice) / point;
         else
            profitPoints = (openPrice - currentPrice) / point;

         // 1. Partial close at 1R profit (50% of position)
         if(config.partialCloseEnabled && !state.partialClosed && state.oneRProfitPrice > 0.0)
         {
            bool reachedOneR = false;
            if(posType == POSITION_TYPE_BUY && currentPrice >= state.oneRProfitPrice)
               reachedOneR = true;
            else if(posType == POSITION_TYPE_SELL && currentPrice <= state.oneRProfitPrice)
               reachedOneR = true;

            if(reachedOneR && volume > SymbolInfoDouble(posSymbol, SYMBOL_VOLUME_MIN))
            {
               double halfVol = NormalizeDouble(volume * 0.5, 2);
               double minVol  = SymbolInfoDouble(posSymbol, SYMBOL_VOLUME_MIN);
               double stepVol = SymbolInfoDouble(posSymbol, SYMBOL_VOLUME_STEP);
               if(stepVol <= 0.0) stepVol = 0.01;
               halfVol = MathFloor((halfVol + 1e-12) / stepVol) * stepVol;
               halfVol = NormalizeDouble(halfVol, 2);

               if(halfVol >= minVol && halfVol < volume)
               {
                  if(tradeManager.ClosePositionPartial(ticket, halfVol, "SCALP|1R-PARTIAL"))
                  {
                     tracker.MarkPartialClosed(i);
                     state.partialClosed = true;
                     PrintFormat("[SCALP-PARTIAL] %s | ticket=%I64u | closed=%.2f | profit_pts=%.1f",
                                 posSymbol, ticket, halfVol, profitPoints);
                  }
               }
            }
         }

         // Management distances come from THIS position's own stop distance (1R), not from one
         // engine-wide point count: 10 points of profit is 1.0 on Step Index and 0.10 on XAUUSD,
         // which is less than XAUUSD's spread, so breakeven and the 15-point trail fired on noise.
         // Breakeven arms at 0.6R with a 0.1R buffer; the trail follows at 0.6R. A position with no
         // recorded 1R (adopted with SL=0) keeps the configured point values.
         double beTriggerPts = (double)config.breakevenProfitPoints;
         double beBufferPts  = (double)config.breakevenBufferPoints;
         double trailPts     = (double)config.trailingDistancePoints;
         if(state.oneRProfitPrice > 0.0 && state.entryPrice > 0.0)
         {
            double rPts = MathAbs(state.oneRProfitPrice - state.entryPrice) / point;
            if(rPts >= 1.0)
            {
               beTriggerPts = 0.60 * rPts;
               beBufferPts  = 0.10 * rPts;
               trailPts     = 0.60 * rPts;
            }
         }

         // 2. Move to breakeven after the breakeven trigger
         if(!state.breakevenSet && profitPoints >= beTriggerPts)
         {
            double beSL = 0.0;
            if(posType == POSITION_TYPE_BUY)
               beSL = NormalizeDouble(openPrice + beBufferPts * point,
                                      (int)SymbolInfoInteger(posSymbol, SYMBOL_DIGITS));
            else
               beSL = NormalizeDouble(openPrice - beBufferPts * point,
                                      (int)SymbolInfoInteger(posSymbol, SYMBOL_DIGITS));

            // Only move SL if it improves the position
            bool shouldMove = false;
            if(posType == POSITION_TYPE_BUY && (currentSL < beSL || currentSL == 0.0))
               shouldMove = true;
            else if(posType == POSITION_TYPE_SELL && (currentSL > beSL || currentSL == 0.0))
               shouldMove = true;

            if(shouldMove)
            {
               if(tradeManager.ModifyPosition(ticket, beSL, currentTP))
               {
                  tracker.MarkBreakevenSet(i);
                  state.breakevenSet = true;
                  PrintFormat("[SCALP-BREAKEVEN] %s | ticket=%I64u | SL=%.5f | profit_pts=%.1f",
                              posSymbol, ticket, beSL, profitPoints);
               }
            }
         }

         // 3. Tight trailing after breakeven is set
         if(state.breakevenSet && trailPts > 0.0)
         {
            double newSL = 0.0;
            int digits = (int)SymbolInfoInteger(posSymbol, SYMBOL_DIGITS);

            if(posType == POSITION_TYPE_BUY)
            {
               newSL = NormalizeDouble(currentPrice - trailPts * point, digits);
               if(newSL > currentSL)
               {
                  tradeManager.ModifyPosition(ticket, newSL, currentTP);
               }
            }
            else
            {
               newSL = NormalizeDouble(currentPrice + trailPts * point, digits);
               if(currentSL == 0.0 || newSL < currentSL)
               {
                  tradeManager.ModifyPosition(ticket, newSL, currentTP);
               }
            }
         }
      }
   }
};

#endif // CORE_SCALP_FAST_SCALP_EXIT_MQH
