// Owns the async (OrderSendAsync) confirmation state for scalp orders.
// OnDealConfirmed() registers the filled position through the
// position tracker; CheckPendingAsyncOrders() releases one
// risk-per-trade unit through the risk budget — both are the same
// operations the original inline code performed.
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
   SScalpPendingAsync        m_pendingAsync[20];
   int                       m_pendingAsyncCount;
   bool                      m_asyncMode;            // Whether async mode is enabled
   uint                      m_maxLatencyMs;         // Max acceptable latency

public:
   CFastScalpAsyncTracker() :
      m_pendingAsyncCount(0),
      m_asyncMode(false),
      m_maxLatencyMs(500)
   {
      // Batch 152 (S-M-04): field-wise reset (string member, see SScalpPendingAsync::Reset)
      for(int i = 0; i < ArraySize(m_pendingAsync); i++)
         m_pendingAsync[i].Reset();
   }

   int  Count() const { return m_pendingAsyncCount; }

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
         PrintFormat("[SCALP-ASYNC-OVERFLOW] Cannot track order %I64u — pending array full (%d)",
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

// Handle deal confirmation for async scalp orders
// Called from OnTradeTransaction when a deal matches a pending order
   void OnDealConfirmed(ulong dealTicket, ulong orderTicket,
                        const SScalpConfig &config,
                        CFastScalpPositionTracker &positionTracker)
   {
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
               if(point > 0.0 && config.scalpSLPips > 0.0)
               {
                  if(m_pendingAsync[i].direction == 1)  // BUY
                     oneRPrice = m_pendingAsync[i].entryPrice + config.scalpSLPips * point;
                  else  // SELL
                     oneRPrice = m_pendingAsync[i].entryPrice - config.scalpSLPips * point;
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
// Called from OnTick to detect stale unconfirmed orders
   void CheckPendingAsyncOrders(CFastScalpRiskBudget &riskBudget,
                                CUnifiedRiskManager* riskManager)
   {
      if(m_pendingAsyncCount <= 0)
         return;

      uint nowMs = GetTickCount();

      for(int i = m_pendingAsyncCount - 1; i >= 0; i--)
      {
         if(m_pendingAsync[i].confirmed || m_pendingAsync[i].expired)
            continue;

         uint elapsedMs = nowMs - m_pendingAsync[i].sendTimestampMs;

         // Expire orders that exceed 3x max latency without confirmation
         uint expireThresholdMs = m_maxLatencyMs * 3;
         if(elapsedMs > expireThresholdMs)
         {
            m_pendingAsync[i].expired = true;

            // Release risk budget for expired order
            riskBudget.ReleaseFallback(riskManager);

            PrintFormat("[SCALP-ASYNC-EXPIRED] %s | order=%I64u | elapsed=%u ms | threshold=%u ms",
                        m_pendingAsync[i].symbol,
                        m_pendingAsync[i].orderTicket,
                        elapsedMs,
                        expireThresholdMs);

            RemovePendingAsync(i);
         }
      }
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
};

#endif // CORE_SCALP_FAST_SCALP_ASYNC_TRACKER_MQH
