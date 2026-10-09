//+------------------------------------------------------------------+
//| FastScalpPendingOrders.mqh                                       |
//| Decomposition extraction from CFastScalpEngine (behaviour        |
//| preserving).                                                     |
//|                                                                  |
//| Owns the pending limit-order book that used to be three loose    |
//| members on CFastScalpEngine:                                     |
//|   SPendingScalpOrder m_pendingOrders[10];                        |
//|   int                m_pendingOrderCount;                        |
//|   CTrade             m_tradeObj;                                 |
//|                                                                  |
//| Moved methods (bodies verbatim):                                 |
//|   PlaceScalpPendingOrder()  -> Place()                           |
//|   CheckPendingScalpOrders() -> CheckExpired()                    |
//|   RemovePendingOrder()      -> RemovePendingOrder()              |
//|   ~CFastScalpEngine() cancel loop -> CancelAllOnShutdown()       |
//|                                                                  |
//| m_config / m_magicNumber / m_lastScalpTime are passed in so the  |
//| engine stays the single owner of configuration and cooldown.     |
//| All stop-distance math, retcodes and log tags are unchanged.     |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_SCALP_FAST_SCALP_PENDING_ORDERS_MQH
#define CORE_SCALP_FAST_SCALP_PENDING_ORDERS_MQH

#include <Trade\Trade.mqh>
#include "../Utils/Enums.mqh"
#include "../Trading/TradeMgrPricing.mqh"
#include "FastScalpTypes.mqh"
#include "FastScalpFilters.mqh"

//+------------------------------------------------------------------+
//| CFastScalpPendingOrders — stateful scalp pending order book       |
//+------------------------------------------------------------------+
class CFastScalpPendingOrders
{
private:
   // Pending order tracking (moved verbatim from CFastScalpEngine)
   SPendingScalpOrder        m_pendingOrders[10];
   int                       m_pendingOrderCount;
   CTrade                    m_tradeObj;   // For pending order operations (OrderDelete)

public:
   CFastScalpPendingOrders() : m_pendingOrderCount(0)
   {
      // Batch 152 (S-M-04): field-wise reset (string member, see SPendingScalpOrder::Reset)
      for(int i = 0; i < ArraySize(m_pendingOrders); i++)
         m_pendingOrders[i].Reset();
   }

   //--- Was CFastScalpEngine::GetPendingOrderCount()
   int Count() const { return m_pendingOrderCount; }

   //+------------------------------------------------------------------+
   //| Cancel any remaining pending orders (was the engine destructor)   |
   //+------------------------------------------------------------------+
   void CancelAllOnShutdown()
   {
      // Cancel any remaining pending orders
      for(int i = 0; i < m_pendingOrderCount; i++)
      {
         if(m_pendingOrders[i].isActive && m_pendingOrders[i].ticket > 0)
         {
            if(OrderSelect(m_pendingOrders[i].ticket))
               m_tradeObj.OrderDelete(m_pendingOrders[i].ticket);
         }
      }
      m_pendingOrderCount = 0;
   }

   //+------------------------------------------------------------------+
   //| Place a scalp pending order (BUY_LIMIT/SELL_LIMIT)               |
   //+------------------------------------------------------------------+
   bool Place(const string symbol, ENUM_TRADE_SIGNAL signal, double lotSize,
              const SScalpConfig &config, long magicNumber, datetime &lastScalpTime)
   {
      if(!config.usePendingOrders)
         return false;
      if(m_pendingOrderCount >= ArraySize(m_pendingOrders))
         return false;

      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return false;

      // Refresh prices immediately before order submission to prevent retcode=10015
      double bid = 0.0, ask = 0.0;
      if(!CFastScalpFilters::RefreshScalpPrice(symbol, ask, bid))
         return false;

      // Calculate minimum offset from current price for pending orders
      // Must respect broker's SYMBOL_TRADE_STOPS_LEVEL
      long stopsLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      long freezeLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      long minDistPoints = MathMax(stopsLevel, freezeLevel);
      double minOffset = minDistPoints * point;

      // For synthetic CFDs, SYMBOL_TRADE_STOPS_LEVEL often returns 0.
      // Use a percentage-based minimum as fallback: 0.1% of mid-price.
      // This ensures stops are far enough from entry for high-priced instruments.
      double midPrice = (ask + bid) / 2.0;
      double pctMinDistance = midPrice * 0.001;  // 0.1% of price
      double absMinOffset = 10 * point;           // absolute minimum: 10 points
      minOffset = MathMax(minOffset, MathMax(absMinOffset, pctMinDistance));

      // SL/TP must also be at least the same minimum distance away from entry price
      // Enforce minimum SL and TP distances to prevent "Invalid stops"
      double slDistance = config.scalpSLPips * point;
      double tpDistance = config.scalpTPPips * point;
      double minStopDistance = minOffset;  // Use same minimum as entry offset
      if(slDistance < minStopDistance)
      {
         PrintFormat("[SCALP-STOPS] %s | SL distance %.2f < min stop distance %.2f (pct-based), adjusting", symbol, slDistance, minStopDistance);
         slDistance = minStopDistance;
      }
      if(tpDistance < minStopDistance)
      {
         PrintFormat("[SCALP-STOPS] %s | TP distance %.2f < min stop distance %.2f (pct-based), adjusting", symbol, tpDistance, minStopDistance);
         tpDistance = minStopDistance;
      }

      // Place limit order at broker-minimum distance from current price
      double entryPrice = 0.0;
      double sl = 0.0, tp = 0.0;
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      ENUM_ORDER_TYPE pendingType;

      if(signal == TRADE_SIGNAL_BUY)
      {
         // BUY_LIMIT must be below current ask by at least stops_level
         entryPrice = NormalizeDouble(ask - minOffset, digits);
         sl = NormalizeDouble(entryPrice - slDistance, digits);
         tp = NormalizeDouble(entryPrice + tpDistance, digits);
         pendingType = ORDER_TYPE_BUY_LIMIT;
      }
      else
      {
         // SELL_LIMIT must be above current bid by at least stops_level
         entryPrice = NormalizeDouble(bid + minOffset, digits);
         sl = NormalizeDouble(entryPrice + slDistance, digits);
         tp = NormalizeDouble(entryPrice - tpDistance, digits);
         pendingType = ORDER_TYPE_SELL_LIMIT;
      }

      // Batch 170: shared stop-feasibility and expectancy gate. The validator keys
      // its adjustment direction on ORDER_TYPE_BUY, so the pending type is mapped
      // to its market equivalent here rather than passed through.
      string scalpStopError = "";
      if(!CTradeMgrPricing::NormalizeAndValidateStops(symbol,
                                                     (pendingType == ORDER_TYPE_BUY_LIMIT) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                                                     entryPrice, tp, sl, tp, scalpStopError))
      {
         PrintFormat("[SCALP-PENDING] STOPS REJECTED | %s | %s", symbol, scalpStopError);
         return false;
      }

      // Use CTradeManager's underlying CTrade object via OpenPosition is not suitable
      // for pending orders — use MQL5 trade API directly
      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      request.action    = TRADE_ACTION_PENDING;
      request.symbol    = symbol;
      request.volume    = lotSize;
      request.type      = pendingType;
      request.price     = entryPrice;
      request.sl        = sl;
      request.tp        = tp;
      request.deviation = 50;
      request.magic     = magicNumber;
      request.comment   = "SCALP|PEND";
      // L7-015: honor the symbol's supported fill mode; fall back to RETURN (correct for pending orders) when IOC/FOK unavailable
      long symFillMode = SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
      request.type_filling = ((symFillMode & SYMBOL_FILLING_IOC) != 0) ? ORDER_FILLING_IOC :
                            (((symFillMode & SYMBOL_FILLING_FOK) != 0) ? ORDER_FILLING_FOK : ORDER_FILLING_RETURN);

      if(!OrderSend(request, result))
      {
         PrintFormat("[SCALP-PENDING-FAILED] %s | retcode=%u | comment=%s",
                     symbol, result.retcode, result.comment);
         return false;
      }

      // Track the pending order
      m_pendingOrders[m_pendingOrderCount].ticket     = result.order;
      m_pendingOrders[m_pendingOrderCount].symbol     = symbol;
      m_pendingOrders[m_pendingOrderCount].orderType  = pendingType;
      m_pendingOrders[m_pendingOrderCount].lotSize    = lotSize;
      m_pendingOrders[m_pendingOrderCount].entryPrice = entryPrice;
      m_pendingOrders[m_pendingOrderCount].stopLoss   = sl;
      m_pendingOrders[m_pendingOrderCount].takeProfit = tp;
      m_pendingOrders[m_pendingOrderCount].placedAt   = TimeCurrent();
      m_pendingOrders[m_pendingOrderCount].isActive   = true;
      m_pendingOrderCount++;

      lastScalpTime = TimeCurrent();

      PrintFormat("[SCALP-PENDING] %s | %s | price=%.5f | lot=%.2f | ticket=%I64u | TTL=%ds",
                  symbol,
                  signal == TRADE_SIGNAL_BUY ? "BUY_LIMIT" : "SELL_LIMIT",
                  entryPrice,
                  lotSize,
                  result.order,
                  config.pendingOrderTTL);

      return true;
   }

   //+------------------------------------------------------------------+
   //| Check and manage pending scalp orders (cancel expired)            |
   //+------------------------------------------------------------------+
   void CheckExpired(const SScalpConfig &config)
   {
      if(m_pendingOrderCount <= 0)
         return;

      datetime now = TimeCurrent();

      for(int i = m_pendingOrderCount - 1; i >= 0; i--)
      {
         if(!m_pendingOrders[i].isActive)
            continue;

         // Check if order still exists
         if(!OrderSelect(m_pendingOrders[i].ticket))
         {
            // Order no longer exists — either filled or cancelled
            // If filled, it becomes a position that ManageScalpPositions will pick up
            RemovePendingOrder(i);
            continue;
         }

         // Check TTL
         int elapsedSec = (int)(now - m_pendingOrders[i].placedAt);
         if(elapsedSec >= config.pendingOrderTTL)
         {
            // Cancel expired pending order
            if(m_tradeObj.OrderDelete(m_pendingOrders[i].ticket))
            {
               PrintFormat("[SCALP-PENDING-EXPIRED] %s | ticket=%I64u | elapsed=%ds",
                           m_pendingOrders[i].symbol,
                           m_pendingOrders[i].ticket,
                           elapsedSec);
            }
            RemovePendingOrder(i);
            continue;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Remove pending order from tracking array by index                 |
   //+------------------------------------------------------------------+
   void RemovePendingOrder(int index)
   {
      if(index < 0 || index >= m_pendingOrderCount)
         return;

      for(int j = index; j < m_pendingOrderCount - 1; j++)
         m_pendingOrders[j] = m_pendingOrders[j + 1];

      // Clear tail slot (field-wise - Batch 152 S-M-04)
      m_pendingOrders[m_pendingOrderCount - 1].Reset();
      m_pendingOrderCount--;
   }
};

#endif // CORE_SCALP_FAST_SCALP_PENDING_ORDERS_MQH
