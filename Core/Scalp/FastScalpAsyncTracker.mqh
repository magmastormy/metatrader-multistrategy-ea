// Owns the async (OrderSendAsync) confirmation state for scalp orders.
// OnDealConfirmed() registers the filled position through the position tracker
// and checks the reserved-budget ledger first so a late fill on a timed-out
// order is still registered. CheckPendingAsyncOrders() moves timed-out orders
// into the reserved-budget ledger (keyed by order ticket) instead of dropping
// them, so the risk budget stays reserved until a final zero-fill outcome;
// the ledger is re-checked on each timer pass and releases budget only then.
#property strict

#ifndef CORE_SCALP_FAST_SCALP_ASYNC_TRACKER_MQH
#define CORE_SCALP_FAST_SCALP_ASYNC_TRACKER_MQH

#include "../Risk/UnifiedRiskManager.mqh"
#include "FastScalpTypes.mqh"
#include "FastScalpPositionTracker.mqh"
#include "FastScalpRiskBudget.mqh"

class CFastScalpAsyncTracker
{
private:
   SScalpPendingAsync          m_pendingAsync[20];
   int                         m_pendingAsyncCount;
   SScalpReservedBudgetLedger  m_reservedLedger[20];   // timed-out orders awaiting a final broker state
   int                         m_reservedLedgerCount;
   bool                        m_asyncMode;            // Whether async mode is enabled
   uint                        m_maxLatencyMs;         // Max acceptable latency

public:
   CFastScalpAsyncTracker() :
      m_pendingAsyncCount(0),
      m_reservedLedgerCount(0),
      m_asyncMode(false),
      m_maxLatencyMs(500)
   {
      // Batch 152 (S-M-04): field-wise reset (string member, see SScalpPendingAsync::Reset)
      for(int i = 0; i < ArraySize(m_pendingAsync); i++)
         m_pendingAsync[i].Reset();
      for(int i = 0; i < ArraySize(m_reservedLedger); i++)
         m_reservedLedger[i].Reset();
   }

   int  Count() const { return m_pendingAsyncCount; }

   int  GetReservedLedgerCount() const { return m_reservedLedgerCount; }

   bool IsAsyncMode() const { return m_asyncMode; }
   uint GetMaxLatencyMs() const { return m_maxLatencyMs; }

   void SetAsyncMode(bool enabled)
   {
      m_asyncMode = enabled;
      PrintFormat("[SCALP-ASYNC] Async mode %s", m_asyncMode ? "ENABLED" : "DISABLED");
   }

// Set max acceptable latency for async order confirmation
   void SetMaxLatencyMs(uint maxMs)
   {
      m_maxLatencyMs = (maxMs > 0) ? maxMs : 500;
      PrintFormat("[SCALP-ASYNC] Max latency set to %u ms", m_maxLatencyMs);
   }

// Track a pending async order after OrderSendAsync
   void OnAsyncOrderSent(ulong orderTicket, string symbol, int direction,
                          double lotSize, double entryPrice, double sl, double tp)
   {
      if(m_pendingAsyncCount >= ArraySize(m_pendingAsync))
      {
         PrintFormat("[SCALP-ASYNC-OVERFLOW] Cannot track order %I64u �?pending array full (%d)",
                     orderTicket, m_pendingAsyncCount);
         return;
      }

      m_pendingAsync[m_pendingAsyncCount].orderTicket     = orderTicket;
      m_pendingAsync[m_pendingAsyncCount].symbol          = symbol;
      m_pendingAsync[m_pendingAsyncCount].direction       = direction;
      m_pendingAsync[m_pendingAsyncCount].lotSize         = lotSize;
      m_pendingAsync[m_pendingAsyncCount].entryPrice      = entryPrice;
      m_pendingAsync[m_pendingAsyncCount].stopLoss        = sl;
      m_pendingAsync[m_pendingAsyncCount].takeProfit      = tp;
      m_pendingAsync[m_pendingAsyncCount].sendTimestampMs = GetTickCount();
      m_pendingAsync[m_pendingAsyncCount].confirmed       = false;
      m_pendingAsync[m_pendingAsyncCount].expired         = false;
      m_pendingAsyncCount++;
   }

// Resolve the position id linked to an order ticket by scanning broker deals
// filtered on DEAL_ORDER (mirrors TradeMgrAsyncExecutor::FillVolumeFromDeals).
   ulong ResolvePositionIdFromOrderHistory(ulong orderTicket)
   {
      int total = HistoryDealsTotal();
      for(int d = total - 1; d >= 0; d--)
      {
         ulong dealTicket = HistoryDealGetTicket(d);
         if(dealTicket == 0)
            continue;
         long dealOrder = HistoryDealGetInteger(dealTicket, DEAL_ORDER);
         if((ulong)dealOrder != orderTicket)
            continue;
         return (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      }
      return 0;
   }

// Register a late-filled async order into the position tracker without releasing
// the reserved budget - the fill is real, so the budget stays consumed.
// `dealTicket` may be 0 when resolving from the timer; in that case the position
// id is found by scanning broker deals filtered on DEAL_ORDER.
   bool RegisterLateFillPosition(ulong orderTicket, ulong dealTicket,
                                 const string symbol, int direction,
                                 double entryPrice, double stopLoss, double takeProfit,
                                 const SScalpConfig &config,
                                 CFastScalpPositionTracker &positionTracker)
   {
      ulong positionId = 0;
      if(dealTicket > 0 && HistoryDealSelect(dealTicket))
         positionId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      if(positionId == 0)
         positionId = ResolvePositionIdFromOrderHistory(orderTicket);

      if(positionId > 0)
      {
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double oneRPrice = 0.0;
         // Guard: config.scalpSLPips must be > 0 here, else oneRPrice collapses onto the entry price and fires the 50% partial close on the first tick after the fill.
         // 1R is this order's own stop distance: the engine-wide config no longer carries a
         // per-symbol stop (CFastScalpEngine::BuildSymbolConfig prices each symbol separately).
         double slDistance = (stopLoss > 0.0 && entryPrice > 0.0) ? MathAbs(entryPrice - stopLoss) : 0.0;
         if(point > 0.0 && slDistance > 0.0)
         {
            if(direction == 1)  // BUY
               oneRPrice = entryPrice + slDistance;
            else  // SELL
               oneRPrice = entryPrice - slDistance;
         }

         positionTracker.RegisterScalpPosition(positionId, symbol, entryPrice,
                                        stopLoss, takeProfit, oneRPrice);
         return true;
      }
      return false;
   }

// Handle deal confirmation for async scalp orders
// Called from OnTradeTransaction when a deal matches a pending order
// Looks up the reserved-budget ledger first so a late fill on a quarantined
// order is still registered (budget stays reserved - the position is real).
   void OnDealConfirmed(ulong dealTicket, ulong orderTicket,
                        const SScalpConfig &config,
                        CFastScalpPositionTracker &positionTracker)
   {
      // 1. Ledger first: a late fill for an order that already timed out and was
      //    quarantined. Register the position and keep the budget reserved.
      for(int i = 0; i < m_reservedLedgerCount; i++)
      {
         if(m_reservedLedger[i].orderTicket == orderTicket && !m_reservedLedger[i].released)
         {
            bool registered = RegisterLateFillPosition(orderTicket, dealTicket,
                                                       m_reservedLedger[i].symbol, m_reservedLedger[i].direction,
                                                       m_reservedLedger[i].entryPrice, m_reservedLedger[i].stopLoss, m_reservedLedger[i].takeProfit,
                                                       config, positionTracker);
            PrintFormat("[SCALP-ASYNC-LEDGER-CONFIRMED] %s | %s | order=%I64u | deal=%I64u | position=%s | lot=%.2f - late fill registered, budget stays reserved",
                        m_reservedLedger[i].symbol,
                        m_reservedLedger[i].direction == 1 ? "BUY" : "SELL",
                        orderTicket,
                        dealTicket,
                        registered ? "registered" : "unresolved",
                        m_reservedLedger[i].lotSize);
            RemoveFromReservedLedger(i);
            return;
         }
      }

      // 2. Normal confirmation path for an order still in the pending array.
      if(m_pendingAsyncCount <= 0)
         return;

      for(int i = 0; i < m_pendingAsyncCount; i++)
      {
         if(m_pendingAsync[i].orderTicket == orderTicket && !m_pendingAsync[i].confirmed)
         {
            uint latencyMs = GetTickCount() - m_pendingAsync[i].sendTimestampMs;

            if(latencyMs > m_maxLatencyMs)
            {
               PrintFormat("[SCALP-ASYNC-LATENCY] %s: Execution latency %u ms exceeds max %u ms. Stale fill detected.",
                           m_pendingAsync[i].symbol, latencyMs, m_maxLatencyMs);
               // Don't reject the fill (it's already executed), but flag it for monitoring
               // Consider tighter SL for stale fills
            }

            m_pendingAsync[i].confirmed = true;

            // Use the position ID from the deal as the tracking ticket
            ulong positionId = 0;
            if(HistoryDealSelect(dealTicket))
               positionId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

            if(positionId > 0)
            {
               double point = SymbolInfoDouble(m_pendingAsync[i].symbol, SYMBOL_POINT);
               double oneRPrice = 0.0;
               // Guard: config.scalpSLPips must be > 0 here, else oneRPrice collapses onto the entry price and fires the 50% partial close on the first tick after the fill.
               double slDistance = (m_pendingAsync[i].stopLoss > 0.0 && m_pendingAsync[i].entryPrice > 0.0)
                                   ? MathAbs(m_pendingAsync[i].entryPrice - m_pendingAsync[i].stopLoss) : 0.0;
               if(point > 0.0 && slDistance > 0.0)
               {
                  if(m_pendingAsync[i].direction == 1)  // BUY
                     oneRPrice = m_pendingAsync[i].entryPrice + slDistance;
                  else  // SELL
                     oneRPrice = m_pendingAsync[i].entryPrice - slDistance;
               }

               positionTracker.RegisterScalpPosition(positionId, m_pendingAsync[i].symbol, m_pendingAsync[i].entryPrice,
                                      m_pendingAsync[i].stopLoss, m_pendingAsync[i].takeProfit, oneRPrice);
            }

            PrintFormat("[SCALP-ASYNC-CONFIRMED] %s | %s | order=%I64u | deal=%I64u | position=%I64u | lot=%.2f | latency=%u ms",
                        m_pendingAsync[i].symbol,
                        m_pendingAsync[i].direction == 1 ? "BUY" : "SELL",
                        orderTicket,
                        dealTicket,
                        positionId,
                        m_pendingAsync[i].lotSize,
                        latencyMs);

            RemovePendingAsync(i);
            return;
         }
      }
   }

// Check pending async orders for expiration
// Called from OnTick to detect stale unconfirmed orders. Timed-out orders that
// disappear from both the live book and broker history are moved into the
// reserved-budget ledger (not dropped), so the budget stays reserved until a
// final zero-fill outcome is observed.
   void CheckPendingAsyncOrders(CFastScalpRiskBudget &riskBudget,
                                CUnifiedRiskManager* riskManager,
                                const SScalpConfig &config,
                                CFastScalpPositionTracker &positionTracker)
   {
      if(m_pendingAsyncCount <= 0 && m_reservedLedgerCount <= 0)
         return;

      uint nowMs = GetTickCount();
      uint expireThresholdMs = m_maxLatencyMs * 3;
      uint abandonThresholdMs = expireThresholdMs * 10;

      //--- 1. Pending async orders: expire, cancel, resolve against broker history
      for(int i = m_pendingAsyncCount - 1; i >= 0; i--)
      {
         if(m_pendingAsync[i].confirmed)
            continue;

         uint elapsedMs = nowMs - m_pendingAsync[i].sendTimestampMs;

         if(!m_pendingAsync[i].expired)
         {
            if(elapsedMs <= expireThresholdMs)
               continue;

            m_pendingAsync[i].expired = true;
            PrintFormat("[SCALP-ASYNC-EXPIRED] %s | order=%I64u | elapsed=%u ms | threshold=%u ms - awaiting broker state",
                        m_pendingAsync[i].symbol,
                        m_pendingAsync[i].orderTicket,
                        elapsedMs,
                        expireThresholdMs);
         }

         // A late fill is still possible while the order is live, so the budget stays reserved.
         ulong ticket = m_pendingAsync[i].orderTicket;
         if(OrderSelect(ticket))
         {
            CancelLiveOrder(ticket);
            if(OrderSelect(ticket))
               continue;
         }

         HistorySelect(TimeCurrent() - 86400, TimeCurrent() + 60);
         if(!HistoryOrderSelect(ticket))
         {
            // Not in live orders and not in broker history: quarantine instead of dropping.
            // The budget stays reserved; a late fill can still arrive and is matched in OnDealConfirmed().
            if(elapsedMs > abandonThresholdMs)
            {
               MoveToReservedLedger(m_pendingAsync[i], riskBudget, riskManager);
               PrintFormat("[SCALP-ASYNC-QUARANTINED] %s | order=%I64u | no broker state after %u ms - budget kept reserved",
                           m_pendingAsync[i].symbol, ticket, elapsedMs);
            }
            RemovePendingAsync(i);
            continue;
         }

         double filled = HistoryOrderGetDouble(ticket, ORDER_VOLUME_INITIAL) - HistoryOrderGetDouble(ticket, ORDER_VOLUME_CURRENT);
         if(filled > 0.0)
         {
            // Late fill resolved by the timer: register the position, keep budget reserved.
            RegisterLateFillPosition(ticket, 0,
                                     m_pendingAsync[i].symbol, m_pendingAsync[i].direction,
                                     m_pendingAsync[i].entryPrice, m_pendingAsync[i].stopLoss, m_pendingAsync[i].takeProfit,
                                     config, positionTracker);
            PrintFormat("[SCALP-ASYNC-LATE-FILL-REGISTERED] %s | order=%I64u | filled=%.4f - position registered, budget stays reserved",
                        m_pendingAsync[i].symbol, ticket, filled);
         }
         else
         {
            riskBudget.ReleaseFallback(riskManager);
            PrintFormat("[SCALP-ASYNC-RELEASED] %s | order=%I64u | no fill - risk budget released",
                        m_pendingAsync[i].symbol, ticket);
         }

         RemovePendingAsync(i);
      }

      //--- 2. Reserved-budget ledger: re-check quarantined orders against broker history
      RecheckReservedLedger(riskBudget, riskManager, config, positionTracker);
   }

   static void CancelLiveOrder(const ulong ticket)
   {
      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      request.action = TRADE_ACTION_REMOVE;
      request.order = ticket;
      if(!OrderSend(request, result) || result.retcode != TRADE_RETCODE_DONE)
         PrintFormat("[SCALP-ASYNC-CANCEL] Ticket=%I64u cancel retcode=%u comment=%s",
                     ticket, result.retcode, result.comment);
   }

   void RemovePendingAsync(int index)
   {
      if(index < 0 || index >= m_pendingAsyncCount)
         return;

      for(int j = index; j < m_pendingAsyncCount - 1; j++)
         m_pendingAsync[j] = m_pendingAsync[j + 1];

      // Clear tail slot (field-wise - Batch 152 S-M-04)
      m_pendingAsync[m_pendingAsyncCount - 1].Reset();
      m_pendingAsyncCount--;
   }

// Move a timed-out pending order into the reserved-budget ledger instead of
// dropping it. The budget stays reserved - release only happens on a final
// zero-fill outcome (RecheckReservedLedger) or the position is registered on a
// late fill (OnDealConfirmed).
   void MoveToReservedLedger(const SScalpPendingAsync &pending,
                             CFastScalpRiskBudget &riskBudget,
                             CUnifiedRiskManager* riskManager)
   {
      for(int i = 0; i < m_reservedLedgerCount; i++)
         if(m_reservedLedger[i].orderTicket == pending.orderTicket)
            return;   // already quarantined

      if(m_reservedLedgerCount >= ArraySize(m_reservedLedger))
      {
         PrintFormat("[SCALP-ASYNC-LEDGER-FULL] Cannot quarantine order %I64u - ledger full", pending.orderTicket);
         return;
      }

      int idx = m_reservedLedgerCount;
      m_reservedLedger[idx].orderTicket     = pending.orderTicket;
      m_reservedLedger[idx].symbol          = pending.symbol;
      m_reservedLedger[idx].direction       = pending.direction;
      m_reservedLedger[idx].lotSize         = pending.lotSize;
      m_reservedLedger[idx].entryPrice      = pending.entryPrice;
      m_reservedLedger[idx].stopLoss        = pending.stopLoss;
      m_reservedLedger[idx].takeProfit      = pending.takeProfit;
      m_reservedLedger[idx].sendTimestampMs = pending.sendTimestampMs;
      m_reservedLedger[idx].quarantinedAtMs = GetTickCount();
      m_reservedLedger[idx].riskReservedPct = (riskManager != NULL) ?
                                              riskManager.GetActiveRiskPerTradePercent() : 1.0;
      m_reservedLedger[idx].released        = false;
      m_reservedLedgerCount++;
   }

   void RemoveFromReservedLedger(int index)
   {
      if(index < 0 || index >= m_reservedLedgerCount)
         return;

      for(int j = index; j < m_reservedLedgerCount - 1; j++)
         m_reservedLedger[j] = m_reservedLedger[j + 1];

      // Clear tail slot (field-wise - Batch 152 S-M-04)
      m_reservedLedger[m_reservedLedgerCount - 1].Reset();
      m_reservedLedgerCount--;
   }

// Re-check quarantined orders against broker history on each timer pass.
// Releases the reserved budget only on a final zero-fill outcome (order in
// history with no fill, or no broker state after a final quarantine TTL).
   void RecheckReservedLedger(CFastScalpRiskBudget &riskBudget,
                              CUnifiedRiskManager* riskManager,
                              const SScalpConfig &config,
                              CFastScalpPositionTracker &positionTracker)
   {
      if(m_reservedLedgerCount <= 0)
         return;

      uint nowMs = GetTickCount();
      uint finalTtlMs = m_maxLatencyMs * 3 * 10;

      for(int i = m_reservedLedgerCount - 1; i >= 0; i--)
      {
         if(m_reservedLedger[i].released)
            continue;

         ulong ticket = m_reservedLedger[i].orderTicket;

         HistorySelect(TimeCurrent() - 86400, TimeCurrent() + 60);
         if(HistoryOrderSelect(ticket))
         {
            double filled = HistoryOrderGetDouble(ticket, ORDER_VOLUME_INITIAL) -
                            HistoryOrderGetDouble(ticket, ORDER_VOLUME_CURRENT);
            if(filled > 0.0)
            {
               // Late fill resolved against broker history: register the position,
               // keep the budget reserved - the position is real.
               RegisterLateFillPosition(ticket, 0,
                                        m_reservedLedger[i].symbol, m_reservedLedger[i].direction,
                                        m_reservedLedger[i].entryPrice, m_reservedLedger[i].stopLoss, m_reservedLedger[i].takeProfit,
                                        config, positionTracker);
               PrintFormat("[SCALP-ASYNC-LEDGER-LATE-FILL] %s | order=%I64u | filled=%.4f - position registered, budget stays reserved",
                           m_reservedLedger[i].symbol, ticket, filled);
               RemoveFromReservedLedger(i);
               continue;
            }

            // Zero fill: final outcome - release the reserved budget.
            riskBudget.Release(m_reservedLedger[i].riskReservedPct);
            m_reservedLedger[i].released = true;
            PrintFormat("[SCALP-ASYNC-LEDGER-RELEASED] %s | order=%I64u | zero fill - risk budget released %.2f%%",
                        m_reservedLedger[i].symbol, ticket, m_reservedLedger[i].riskReservedPct);
            RemoveFromReservedLedger(i);
            continue;
         }

         // Still no broker state: release only after the final quarantine TTL.
         uint elapsedSinceQuarantine = nowMs - m_reservedLedger[i].quarantinedAtMs;
         if(elapsedSinceQuarantine > finalTtlMs)
         {
            riskBudget.Release(m_reservedLedger[i].riskReservedPct);
            m_reservedLedger[i].released = true;
            PrintFormat("[SCALP-ASYNC-LEDGER-RELEASED] %s | order=%I64u | no broker state after %u ms - risk budget released %.2f%%",
                        m_reservedLedger[i].symbol, ticket, elapsedSinceQuarantine, m_reservedLedger[i].riskReservedPct);
            RemoveFromReservedLedger(i);
            continue;
         }

         // Still quarantined - keep waiting for a late fill.
      }
   }
};

#endif // CORE_SCALP_FAST_SCALP_ASYNC_TRACKER_MQH

