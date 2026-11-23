// Owns unresolved scalp-order confirmation state and reservations.
// OnDealConfirmed() registers the filled position through the position tracker
// and checks the reserved-budget ledger first so a late fill on a timed-out
// order is still registered. CheckPendingAsyncOrders() moves timed-out orders
// into the reserved-budget ledger (keyed by order ticket) instead of dropping
// them, so the risk budget stays reserved until a final zero-fill outcome;
// the ledger is re-checked on each timer pass and releases budget only then.
#property strict

#ifndef CORE_SCALP_FAST_SCALP_ASYNC_TRACKER_MQH
#define CORE_SCALP_FAST_SCALP_ASYNC_TRACKER_MQH

#include "FastScalpTypes.mqh"
#include "FastScalpPositionTracker.mqh"

class CFastScalpAsyncTracker
{
private:
   SScalpPendingAsync          m_pendingAsync[20];
   int                         m_pendingAsyncCount;
   SScalpReservedBudgetLedger  m_reservedLedger[20];   // timed-out orders awaiting a final broker state
   int                         m_reservedLedgerCount;
   bool                        m_asyncMode;            // Whether async mode is enabled
   uint                        m_maxLatencyMs;         // Max acceptable latency
   double                      m_untrackedReservationPct;
   ulong                       m_expectedMagic;

   ulong ResolvePositionIdFromOrderHistory(const ulong orderTicket, const string &symbol) const
   {
      for(int d = HistoryDealsTotal() - 1; d >= 0; d--)
      {
         ulong dealTicket = HistoryDealGetTicket(d);
         if(dealTicket == 0 ||
            (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER) != orderTicket ||
            (ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != m_expectedMagic ||
            HistoryDealGetString(dealTicket, DEAL_SYMBOL) != symbol)
            continue;
         return (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      }
      return 0;
   }

   ulong ResolvePositionTicket(const ulong positionId, const string &symbol) const
   {
      if(positionId == 0)
         return 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
          if((ulong)PositionGetInteger(POSITION_MAGIC) == m_expectedMagic &&
             PositionGetString(POSITION_SYMBOL) == symbol &&
            (ulong)PositionGetInteger(POSITION_IDENTIFIER) == positionId)
            return ticket;
      }
      return 0;
   }

   bool HasLivePositionForOrder(const ulong orderTicket,
                                const string &symbol,
                                const datetime submitTime) const
   {
      datetime historyFrom = (submitTime > 3600) ? submitTime - 3600 : 0;
      if(!HistorySelect(historyFrom, TimeCurrent() + 60))
         return false;
      if(!HistoryOrderSelect(orderTicket) ||
         (ulong)HistoryOrderGetInteger(orderTicket, ORDER_MAGIC) != m_expectedMagic ||
         HistoryOrderGetString(orderTicket, ORDER_SYMBOL) != symbol)
         return false;
      ulong positionId = ResolvePositionIdFromOrderHistory(orderTicket, symbol);
      return ResolvePositionTicket(positionId, symbol) > 0;
   }

public:
   CFastScalpAsyncTracker() :
      m_pendingAsyncCount(0),
      m_reservedLedgerCount(0),
      m_asyncMode(false),
      m_maxLatencyMs(500),
      m_untrackedReservationPct(0.0),
      m_expectedMagic(0)
   {
      // (S-M-04): field-wise reset (string member, see SScalpPendingAsync::Reset)
      for(int i = 0; i < ArraySize(m_pendingAsync); i++)
         m_pendingAsync[i].Reset();
      for(int i = 0; i < ArraySize(m_reservedLedger); i++)
         m_reservedLedger[i].Reset();
   }

   int  Count() const { return m_pendingAsyncCount; }

   bool CanTrackNewOrder() const { return m_pendingAsyncCount < ArraySize(m_pendingAsync); }

   int  GetReservedLedgerCount() const { return m_reservedLedgerCount; }

   void SetExpectedMagic(const ulong magic) { m_expectedMagic = magic; }

   void MarkUntrackedRiskReservation(const double riskPct,
                                    const ulong orderTicket,
                                    const string &symbol,
                                    const datetime submitTime)
   {
      if(m_expectedMagic == 0)
      {
         m_untrackedReservationPct = 1e100;
         return;
      }
      if(orderTicket > 0)
      {
         if(OrderSelect(orderTicket) &&
            (ulong)OrderGetInteger(ORDER_MAGIC) == m_expectedMagic &&
            OrderGetString(ORDER_SYMBOL) == symbol)
            return;
         if(HasLivePositionForOrder(orderTicket, symbol, submitTime))
            return;
         datetime historyFrom = (submitTime > 3600) ? submitTime - 3600 : 0;
         if(HistorySelect(historyFrom, TimeCurrent() + 60) && HistoryOrderSelect(orderTicket))
         {
            if((ulong)HistoryOrderGetInteger(orderTicket, ORDER_MAGIC) == m_expectedMagic &&
               HistoryOrderGetString(orderTicket, ORDER_SYMBOL) == symbol)
            {
               ENUM_ORDER_STATE state = (ENUM_ORDER_STATE)HistoryOrderGetInteger(orderTicket, ORDER_STATE);
               if(state == ORDER_STATE_CANCELED || state == ORDER_STATE_FILLED ||
                  state == ORDER_STATE_REJECTED || state == ORDER_STATE_EXPIRED)
                  return;
            }
         }
      }
      if(!(riskPct > 0.0) || riskPct != riskPct || riskPct >= 1e308 ||
         m_untrackedReservationPct >= 1e100)
      {
         m_untrackedReservationPct = 1e100;
         return;
      }
      m_untrackedReservationPct += riskPct;
      if(m_untrackedReservationPct >= 1e100 || m_untrackedReservationPct != m_untrackedReservationPct)
         m_untrackedReservationPct = 1e100;
   }

   double GetUnrepresentedRiskPct() const
   {
      if(m_expectedMagic == 0 || m_untrackedReservationPct >= 1e100 ||
         m_untrackedReservationPct != m_untrackedReservationPct)
         return 1e100;

      double riskPct = m_untrackedReservationPct;
      for(int i = 0; i < m_pendingAsyncCount; i++)
      {
         if(!(m_pendingAsync[i].riskReservedPct > 0.0) ||
            m_pendingAsync[i].riskReservedPct != m_pendingAsync[i].riskReservedPct ||
            m_pendingAsync[i].riskReservedPct >= 1e308)
            return 1e100;
          if(OrderSelect(m_pendingAsync[i].orderTicket) &&
             (ulong)OrderGetInteger(ORDER_MAGIC) == m_expectedMagic &&
             OrderGetString(ORDER_SYMBOL) == m_pendingAsync[i].symbol)
            continue;
         ulong positionTicket = m_pendingAsync[i].representedPositionTicket;
         bool representedPosition = positionTicket > 0 && PositionSelectByTicket(positionTicket) &&
                                    (ulong)PositionGetInteger(POSITION_MAGIC) == m_expectedMagic &&
                                    PositionGetString(POSITION_SYMBOL) == m_pendingAsync[i].symbol;
         if(representedPosition ||
            HasLivePositionForOrder(m_pendingAsync[i].orderTicket,
                                    m_pendingAsync[i].symbol,
                                    m_pendingAsync[i].submitTime))
            continue;
         riskPct += m_pendingAsync[i].riskReservedPct;
         if(riskPct >= 1e100 || riskPct != riskPct)
            return 1e100;
      }

      for(int i = 0; i < m_reservedLedgerCount; i++)
      {
         if(m_reservedLedger[i].released)
            continue;
         if(!(m_reservedLedger[i].riskReservedPct > 0.0) ||
            m_reservedLedger[i].riskReservedPct != m_reservedLedger[i].riskReservedPct ||
            m_reservedLedger[i].riskReservedPct >= 1e308)
            return 1e100;
          if(OrderSelect(m_reservedLedger[i].orderTicket) &&
             (ulong)OrderGetInteger(ORDER_MAGIC) == m_expectedMagic &&
             OrderGetString(ORDER_SYMBOL) == m_reservedLedger[i].symbol)
            continue;
         ulong positionTicket = m_reservedLedger[i].representedPositionTicket;
         bool representedPosition = positionTicket > 0 && PositionSelectByTicket(positionTicket) &&
                                    (ulong)PositionGetInteger(POSITION_MAGIC) == m_expectedMagic &&
                                    PositionGetString(POSITION_SYMBOL) == m_reservedLedger[i].symbol;
         if(representedPosition ||
            HasLivePositionForOrder(m_reservedLedger[i].orderTicket,
                                    m_reservedLedger[i].symbol,
                                    m_reservedLedger[i].submitTime))
            continue;
         riskPct += m_reservedLedger[i].riskReservedPct;
         if(riskPct >= 1e100 || riskPct != riskPct)
            return 1e100;
      }
      return riskPct;
   }

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
   bool OnAsyncOrderSent(ulong orderTicket, string symbol, int direction,
                         double lotSize, double entryPrice, double sl, double tp,
                         double riskReservedPct, const datetime requestSubmitTime = 0)
   {
      if(m_expectedMagic == 0 || orderTicket == 0 || symbol == "" || (direction != 1 && direction != -1) ||
         !(lotSize > 0.0) || lotSize != lotSize || lotSize >= 1e308 ||
         !(entryPrice > 0.0) || entryPrice != entryPrice || entryPrice >= 1e308 ||
         !(sl > 0.0) || !(tp > 0.0) ||
         !(riskReservedPct > 0.0) ||
         riskReservedPct != riskReservedPct || riskReservedPct >= 1e308 ||
         m_pendingAsyncCount >= ArraySize(m_pendingAsync))
      {
         PrintFormat("[SCALP-ASYNC-OVERFLOW] Cannot track order %I64u - pending array full (%d)",
                     orderTicket, m_pendingAsyncCount);
         return false;
      }

      for(int i = 0; i < m_pendingAsyncCount; i++)
         if(m_pendingAsync[i].orderTicket == orderTicket)
            return true;
      for(int i = 0; i < m_reservedLedgerCount; i++)
         if(m_reservedLedger[i].orderTicket == orderTicket)
            return true;

      m_pendingAsync[m_pendingAsyncCount].orderTicket     = orderTicket;
      m_pendingAsync[m_pendingAsyncCount].symbol          = symbol;
      m_pendingAsync[m_pendingAsyncCount].direction       = direction;
      m_pendingAsync[m_pendingAsyncCount].lotSize         = lotSize;
      m_pendingAsync[m_pendingAsyncCount].entryPrice      = entryPrice;
      m_pendingAsync[m_pendingAsyncCount].stopLoss        = sl;
      m_pendingAsync[m_pendingAsyncCount].takeProfit      = tp;
      m_pendingAsync[m_pendingAsyncCount].submitTime      = (requestSubmitTime > 0) ? requestSubmitTime : TimeCurrent();
      m_pendingAsync[m_pendingAsyncCount].sendTimestampMs = GetTickCount();
      m_pendingAsync[m_pendingAsyncCount].riskReservedPct = riskReservedPct;
      m_pendingAsync[m_pendingAsyncCount].confirmed       = false;
      m_pendingAsync[m_pendingAsyncCount].expired         = false;
      m_pendingAsync[m_pendingAsyncCount].representedPositionTicket = 0;
      m_pendingAsyncCount++;
      return true;
   }

// Resolve the position id linked to an order ticket by scanning broker deals
// filtered on DEAL_ORDER (mirrors TradeMgrAsyncExecutor::FillVolumeFromDeals).
// Register a late-filled async order into the position tracker without releasing
// the reserved budget - the fill is real, so the budget stays consumed.
// `dealTicket` may be 0 when resolving from the timer; in that case the position
// id is found by scanning broker deals filtered on DEAL_ORDER.
   bool RegisterLateFillPosition(ulong orderTicket, ulong dealTicket,
                                 const string symbol, int direction,
                                 CFastScalpPositionTracker &positionTracker,
                                 ulong &representedPositionTicket)
   {
      representedPositionTicket = 0;
      ulong positionId = 0;
       if(dealTicket > 0)
       {
          if(!HistoryDealSelect(dealTicket) ||
             (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER) != orderTicket ||
             (ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != m_expectedMagic ||
             HistoryDealGetString(dealTicket, DEAL_SYMBOL) != symbol)
             return false;
          positionId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
       }
      if(positionId == 0)
          positionId = ResolvePositionIdFromOrderHistory(orderTicket, symbol);

      ulong positionTicket = ResolvePositionTicket(positionId, symbol);
      if(positionTicket > 0 && PositionSelectByTicket(positionTicket))
      {
         representedPositionTicket = positionTicket;
         double oneRPrice = 0.0;
         // Guard: config.scalpSLPips must be > 0 here, else oneRPrice collapses onto the entry price and fires the 50% partial close on the first tick after the fill.
         // 1R is this order's own stop distance: the engine-wide config no longer carries a
         // per-symbol stop (CFastScalpEngine::BuildSymbolConfig prices each symbol separately).
         double currentEntry  = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentStop   = PositionGetDouble(POSITION_SL);
         double currentTarget = PositionGetDouble(POSITION_TP);
         double slDistance = (currentStop > 0.0 && currentEntry > 0.0) ? MathAbs(currentEntry - currentStop) : 0.0;
         if(slDistance > 0.0)
         {
            if(direction == 1)  // BUY
               oneRPrice = currentEntry + slDistance;
            else  // SELL
               oneRPrice = currentEntry - slDistance;
         }

         return positionTracker.RegisterScalpPosition(positionTicket, symbol, currentEntry,
                                                       currentStop, currentTarget, oneRPrice);
      }
      return false;
   }

// Handle deal confirmation for async scalp orders
// Called from OnTradeTransaction when a deal matches a pending order
// Looks up the reserved-budget ledger first so a late fill on a quarantined
// order is still registered (budget stays reserved - the position is real).
   void OnDealConfirmed(ulong dealTicket, ulong orderTicket,
                        CFastScalpPositionTracker &positionTracker)
   {
      if(m_expectedMagic == 0 || dealTicket == 0 || !HistoryDealSelect(dealTicket) ||
         (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER) != orderTicket ||
         (ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != m_expectedMagic)
         return;

      // 1. Ledger first: a late fill for an order that already timed out and was
      // quarantined. Register the position and keep the budget reserved.
      for(int i = 0; i < m_reservedLedgerCount; i++)
      {
         if(m_reservedLedger[i].orderTicket == orderTicket && !m_reservedLedger[i].released)
         {
            ulong representedPositionTicket = 0;
            bool registered = RegisterLateFillPosition(orderTicket, dealTicket,
                                                       m_reservedLedger[i].symbol, m_reservedLedger[i].direction,
                                                       positionTracker, representedPositionTicket);
            if(representedPositionTicket > 0)
               m_reservedLedger[i].representedPositionTicket = representedPositionTicket;
             if(registered)
                m_reservedLedger[i].confirmed = true;
             PrintFormat("[SCALP-ASYNC-LEDGER-CONFIRMED] %s | %s | order=%I64u | deal=%I64u | position=%s | lot=%.2f - late fill registered, budget stays reserved",
                        m_reservedLedger[i].symbol,
                        m_reservedLedger[i].direction == 1 ? "BUY" : "SELL",
                        orderTicket,
                        dealTicket,
                        registered ? "registered" : "unresolved",
                        m_reservedLedger[i].lotSize);
            return;
         }
      }

      // 2. Normal confirmation path for an order still in the pending array.
      if(m_pendingAsyncCount <= 0)
         return;

      for(int i = 0; i < m_pendingAsyncCount; i++)
      {
         if(m_pendingAsync[i].orderTicket == orderTicket)
         {
            uint latencyMs = GetTickCount() - m_pendingAsync[i].sendTimestampMs;

            if(latencyMs > m_maxLatencyMs)
            {
               PrintFormat("[SCALP-ASYNC-LATENCY] %s: Execution latency %u ms exceeds max %u ms. Stale fill detected.",
                           m_pendingAsync[i].symbol, latencyMs, m_maxLatencyMs);
               // Don't reject the fill (it's already executed), but flag it for monitoring
               // Consider tighter SL for stale fills
            }

            ulong representedPositionTicket = 0;
            bool registered = RegisterLateFillPosition(orderTicket, dealTicket,
                                                       m_pendingAsync[i].symbol, m_pendingAsync[i].direction,
                                                       positionTracker, representedPositionTicket);
            if(representedPositionTicket > 0)
               m_pendingAsync[i].representedPositionTicket = representedPositionTicket;
            if(!registered)
            {
               PrintFormat("[SCALP-ASYNC-UNRESOLVED] order=%I64u | deal=%I64u | position tracking will retry",
                           orderTicket, dealTicket);
               return;
            }
            m_pendingAsync[i].confirmed = true;

            PrintFormat("[SCALP-ASYNC-CONFIRMED] %s | %s | order=%I64u | deal=%I64u | position=tracked | lot=%.2f | latency=%u ms",
                        m_pendingAsync[i].symbol,
                        m_pendingAsync[i].direction == 1 ? "BUY" : "SELL",
                        orderTicket,
                        dealTicket,
                        m_pendingAsync[i].lotSize,
                        latencyMs);

            return;
         }
      }
   }

// Check pending async orders for expiration
// Called from OnTick to detect stale unconfirmed orders. Timed-out orders that
// disappear from both the live book and broker history are moved into the
// reserved-budget ledger (not dropped), so the budget stays reserved until a
// final zero-fill outcome is observed.
   void CheckPendingAsyncOrders(CFastScalpPositionTracker &positionTracker)
   {
      if(m_expectedMagic == 0)
         return;

      if(m_pendingAsyncCount <= 0 && m_reservedLedgerCount <= 0)
         return;

      uint nowMs = GetTickCount();
      uint expireThresholdMs = m_maxLatencyMs * 3;
      uint abandonThresholdMs = expireThresholdMs * 10;

      //--- 1. Pending async orders: expire, cancel, resolve against broker history
      for(int i = m_pendingAsyncCount - 1; i >= 0; i--)
      {
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
             if((ulong)OrderGetInteger(ORDER_MAGIC) != m_expectedMagic ||
                OrderGetString(ORDER_SYMBOL) != m_pendingAsync[i].symbol)
                continue;
             CancelLiveOrder(ticket, m_pendingAsync[i].symbol);
            if(OrderSelect(ticket))
               continue;
         }

          datetime historyFrom = (m_pendingAsync[i].submitTime > 3600) ?
                                 m_pendingAsync[i].submitTime - 3600 : 0;
          if(!HistorySelect(historyFrom, TimeCurrent() + 60))
             continue;

          bool inHistory = HistoryOrderSelect(ticket);
          if(!inHistory)
         {
             if(elapsedMs <= abandonThresholdMs)
                continue;

             if(!MoveToReservedLedger(m_pendingAsync[i]))
                continue;

             PrintFormat("[SCALP-ASYNC-QUARANTINED] %s | order=%I64u | no broker state after %u ms - budget kept reserved",
                         m_pendingAsync[i].symbol, ticket, elapsedMs);
             RemovePendingAsync(i);
            continue;
         }

          if((ulong)HistoryOrderGetInteger(ticket, ORDER_MAGIC) != m_expectedMagic ||
             HistoryOrderGetString(ticket, ORDER_SYMBOL) != m_pendingAsync[i].symbol)
             continue;
          ENUM_ORDER_STATE orderState = (ENUM_ORDER_STATE)HistoryOrderGetInteger(ticket, ORDER_STATE);
          if(!IsTerminalOrderState(orderState))
             continue;

          double filledVolume = 0.0;
         bool fillsRegistered = RegisterOrderFillPositions(ticket, m_pendingAsync[i].symbol,
                                                            m_pendingAsync[i].direction,
                                                            positionTracker, filledVolume);
          if(filledVolume > 0.0)
          {
             if(!fillsRegistered && HasLivePositionForOrder(ticket, m_pendingAsync[i].symbol,
                                                            m_pendingAsync[i].submitTime))
                continue;
             if(fillsRegistered)
                PrintFormat("[SCALP-ASYNC-LATE-FILL-REGISTERED] %s | order=%I64u | filled=%.4f - current broker exposure is counted",
                            m_pendingAsync[i].symbol, ticket, filledVolume);
             else
                PrintFormat("[SCALP-ASYNC-RECONCILED] %s | order=%I64u | historical fill is no longer an open position",
                            m_pendingAsync[i].symbol, ticket);
          }
          else if(m_pendingAsync[i].confirmed)
          {
             continue;
          }
          else
          {
             PrintFormat("[SCALP-ASYNC-RELEASED] %s | order=%I64u | terminal zero fill - reservation reconciled",
                         m_pendingAsync[i].symbol, ticket);
          }

         RemovePendingAsync(i);
      }

      //--- 2. Reserved-budget ledger: re-check quarantined orders against broker history
      RecheckReservedLedger(positionTracker);
   }

   void CancelLiveOrder(const ulong ticket, const string &symbol)
   {
      if(ticket == 0 || !OrderSelect(ticket) ||
         (ulong)OrderGetInteger(ORDER_MAGIC) != m_expectedMagic ||
         OrderGetString(ORDER_SYMBOL) != symbol)
         return;

      MqlTradeRequest request = {};
      MqlTradeResult result = {};
      request.action = TRADE_ACTION_REMOVE;
      request.order = ticket;
      request.symbol = symbol;
      request.magic = m_expectedMagic;
      if(!OrderSend(request, result) || result.retcode != TRADE_RETCODE_DONE)
         PrintFormat("[SCALP-ASYNC-CANCEL] Ticket=%I64u cancel retcode=%u comment=%s",
                     ticket, result.retcode, result.comment);
   }

   static bool IsTerminalOrderState(const ENUM_ORDER_STATE state)
   {
      return (state == ORDER_STATE_CANCELED || state == ORDER_STATE_FILLED ||
              state == ORDER_STATE_REJECTED || state == ORDER_STATE_EXPIRED);
   }

   bool RegisterOrderFillPositions(const ulong orderTicket,
                                   const string symbol,
                                   const int direction,
                                   CFastScalpPositionTracker &positionTracker,
                                   double &filledVolume)
   {
      filledVolume = 0.0;
      bool allRegistered = true;
      int total = HistoryDealsTotal();

      for(int i = 0; i < total; i++)
      {
         ulong dealTicket = HistoryDealGetTicket(i);
          if(dealTicket == 0 ||
             (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER) != orderTicket ||
             (ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != m_expectedMagic)
            continue;
          if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != symbol)
            continue;

         ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
         if(dealEntry != DEAL_ENTRY_IN && dealEntry != DEAL_ENTRY_INOUT)
            continue;

         double dealVolume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
         if(dealVolume <= 0.0)
            continue;
         filledVolume += dealVolume;

         ulong positionId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
         ulong positionTicket = ResolvePositionTicket(positionId, symbol);
         if(positionTicket == 0 || !PositionSelectByTicket(positionTicket))
         {
            allRegistered = false;
            continue;
         }

         double entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl = PositionGetDouble(POSITION_SL);
         double tp = PositionGetDouble(POSITION_TP);
         double oneR = 0.0;
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double slDistance = (entry > 0.0 && sl > 0.0) ? MathAbs(entry - sl) : 0.0;
         if(point > 0.0 && slDistance > 0.0)
            oneR = (direction == 1) ? entry + slDistance : entry - slDistance;

         if(!positionTracker.RegisterScalpPosition(positionTicket, symbol, entry, sl, tp, oneR))
            allRegistered = false;
      }

      return (filledVolume > 0.0 && allRegistered);
   }

   void RemovePendingAsync(int index)
   {
      if(index < 0 || index >= m_pendingAsyncCount)
         return;

      for(int j = index; j < m_pendingAsyncCount - 1; j++)
         m_pendingAsync[j] = m_pendingAsync[j + 1];

      // Clear tail slot (field-wise - S-M-04)
      m_pendingAsync[m_pendingAsyncCount - 1].Reset();
      m_pendingAsyncCount--;
   }

// Move a timed-out pending order into the reserved-budget ledger instead of
// dropping it. The budget stays reserved - release only happens on a final
// zero-fill outcome (RecheckReservedLedger) or the position is registered on a
// late fill (OnDealConfirmed).
   bool MoveToReservedLedger(const SScalpPendingAsync &pending)
   {
      for(int i = 0; i < m_reservedLedgerCount; i++)
         if(m_reservedLedger[i].orderTicket == pending.orderTicket)
            return true;   // already quarantined

      if(m_reservedLedgerCount >= ArraySize(m_reservedLedger))
      {
         PrintFormat("[SCALP-ASYNC-LEDGER-FULL] Cannot quarantine order %I64u - ledger full", pending.orderTicket);
          return false;
      }

      int idx = m_reservedLedgerCount;
      m_reservedLedger[idx].orderTicket     = pending.orderTicket;
      m_reservedLedger[idx].symbol          = pending.symbol;
      m_reservedLedger[idx].direction       = pending.direction;
      m_reservedLedger[idx].lotSize         = pending.lotSize;
      m_reservedLedger[idx].entryPrice      = pending.entryPrice;
      m_reservedLedger[idx].stopLoss        = pending.stopLoss;
      m_reservedLedger[idx].takeProfit      = pending.takeProfit;
      m_reservedLedger[idx].submitTime      = pending.submitTime;
      m_reservedLedger[idx].sendTimestampMs = pending.sendTimestampMs;
      m_reservedLedger[idx].quarantinedAtMs = GetTickCount();
      m_reservedLedger[idx].riskReservedPct = pending.riskReservedPct;
      m_reservedLedger[idx].confirmed       = pending.confirmed;
      m_reservedLedger[idx].released        = false;
      m_reservedLedger[idx].representedPositionTicket = pending.representedPositionTicket;
      m_reservedLedgerCount++;
      return true;
   }

   void RemoveFromReservedLedger(int index)
   {
      if(index < 0 || index >= m_reservedLedgerCount)
         return;

      for(int j = index; j < m_reservedLedgerCount - 1; j++)
         m_reservedLedger[j] = m_reservedLedger[j + 1];

      // Clear tail slot (field-wise - S-M-04)
      m_reservedLedger[m_reservedLedgerCount - 1].Reset();
      m_reservedLedgerCount--;
   }

// Re-check quarantined orders against broker history on each timer pass.
// Releases the reserved budget only when broker history confirms a terminal
// zero-fill outcome. Missing broker state remains quarantined.
   void RecheckReservedLedger(CFastScalpPositionTracker &positionTracker)
   {
      if(m_reservedLedgerCount <= 0)
         return;

      for(int i = m_reservedLedgerCount - 1; i >= 0; i--)
      {
         if(m_reservedLedger[i].released)
            continue;

         ulong ticket = m_reservedLedger[i].orderTicket;
         datetime historyFrom = (m_reservedLedger[i].submitTime > 3600) ?
                                m_reservedLedger[i].submitTime - 3600 : 0;
         if(!HistorySelect(historyFrom, TimeCurrent() + 60) || !HistoryOrderSelect(ticket))
            continue;

         if((ulong)HistoryOrderGetInteger(ticket, ORDER_MAGIC) != m_expectedMagic ||
            HistoryOrderGetString(ticket, ORDER_SYMBOL) != m_reservedLedger[i].symbol)
            continue;

         ENUM_ORDER_STATE orderState = (ENUM_ORDER_STATE)HistoryOrderGetInteger(ticket, ORDER_STATE);
         if(!IsTerminalOrderState(orderState))
            continue;

         double filledVolume = 0.0;
         bool fillsRegistered = RegisterOrderFillPositions(ticket, m_reservedLedger[i].symbol,
                                                            m_reservedLedger[i].direction,
                                                            positionTracker, filledVolume);
         if(filledVolume > 0.0)
         {
            if(!fillsRegistered && HasLivePositionForOrder(ticket, m_reservedLedger[i].symbol,
                                                           m_reservedLedger[i].submitTime))
               continue;
            if(fillsRegistered)
               PrintFormat("[SCALP-ASYNC-LEDGER-LATE-FILL] %s | order=%I64u | filled=%.4f - current broker exposure is counted",
                           m_reservedLedger[i].symbol, ticket, filledVolume);
            else
               PrintFormat("[SCALP-ASYNC-LEDGER-RECONCILED] %s | order=%I64u | historical fill is no longer an open position",
                           m_reservedLedger[i].symbol, ticket);
            RemoveFromReservedLedger(i);
            continue;
         }

         if(m_reservedLedger[i].confirmed)
            continue;

         PrintFormat("[SCALP-ASYNC-LEDGER-RELEASED] %s | order=%I64u | terminal zero fill - reservation reconciled",
                     m_reservedLedger[i].symbol, ticket);
         RemoveFromReservedLedger(i);
      }
   }
};

#endif // CORE_SCALP_FAST_SCALP_ASYNC_TRACKER_MQH

