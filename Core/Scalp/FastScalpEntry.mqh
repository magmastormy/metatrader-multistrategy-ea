// Owns the scalp entry path extracted from CFastScalpEngine: entry gates, risk gating, lot finalization, send.
// Methods are `static` and mutable engine state (cooldown stamp, risk budget, trackers) arrives by reference, so
// side effects and their ordering match the inline original. The pre-trade CUnifiedRiskManager validation here
// is AGENTS.md Invariant #1; the partial-fill risk scaling keeps its L10-015 behaviour.
#property strict

#ifndef CORE_SCALP_FAST_SCALP_ENTRY_MQH
#define CORE_SCALP_FAST_SCALP_ENTRY_MQH

#include "../Utils/Enums.mqh"
#include "../Trading/TradeManager.mqh"
#include "../Trading/TradeTypes.mqh"
#include "../Risk/UnifiedRiskManager.mqh"
#include "FastScalpTypes.mqh"
#include "FastScalpFilters.mqh"
#include "FastScalpSizing.mqh"
#include "FastScalpPositionTracker.mqh"
#include "FastScalpRiskBudget.mqh"
#include "FastScalpAsyncTracker.mqh"

// Forward declaration for AI adapter (L10-018) â€?only ever NULL-checked here
class CAIAdapter;

// CFastScalpEntry â€?stateless scalp entry gating + execution
class CFastScalpEntry
{
public:
// Pre-signal entry gates: cooldown, max positions, risk budget
   static bool PassesEntryGates(const SScalpConfig &config,
                                datetime lastScalpTime,
                                double usedScalpRiskPct)
   {
      datetime now = TimeCurrent();
      ulong elapsedMs = (ulong)((now - lastScalpTime) * 1000);
      if(lastScalpTime > 0 && elapsedMs < (ulong)config.scalpCooldownMs)
         return false;

      int scalpCount = CFastScalpPositionTracker::CountScalpPositions();
      if(scalpCount >= config.maxScalpPositions)
         return false;

      if(usedScalpRiskPct >= config.scalpRiskPct)
         return false;

      return true;
   }

// The scalp path's single CUnifiedRiskManager pre-trade gate (AGENTS.md Â§3.1): refuses the entry, and
// applies a smaller lot when the gate asks for one. Execute does not validate again.
   static bool ValidateRiskAndAdjust(const string symbol,
                                     ENUM_TRADE_SIGNAL signal,
                                     double confidence,
                                     double &lotSize,
                                     const SScalpConfig &config,
                                     CUnifiedRiskManager* riskManager)
   {
      if(riskManager != NULL && riskManager.IsInitialized())
      {
         ENUM_ORDER_TYPE orderType = (signal == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         STradeValidationRequest request;
         request.symbol          = symbol;
         request.orderType       = orderType;
         request.lotSize         = lotSize;
         request.stopLossPips    = (double)config.scalpSLPips;
         request.takeProfitPips  = (double)config.scalpTPPips;
         request.confidence      = confidence;
         request.strategy        = "FastScalp";
         request.reasoning       = "Scalp: EMA crossover + RSI + spread gate";
         request.strategyRole    = "PRIMARY_ALPHA";
         request.strategyCluster = "TREND_CLUSTER";
         request.clusterCode     = "T";
         request.requestTime     = TimeCurrent();

         SValidationResult result = riskManager.ValidateTradeRequest(request, "scalp");
         if(!result.approved)
         {
            PrintFormat("[SCALP-REJECTED] %s | reason=%s | confidence=%.2f",
                        symbol, result.message, confidence);
            return false;
         }

         // Shrink-only and logged: the pipeline can raise adjustedLotSize to SYMBOL_VOLUME_MIN, and
         // adopting that would ship more than CPositionSizer decided.
         if(result.adjustedLotSize > 0.0 && result.adjustedLotSize < lotSize)
         {
            PrintFormat("[SCALP-RISK-ADJUSTED] %s | lot %.2f -> %.2f | reason=%s",
                        symbol, lotSize, result.adjustedLotSize, result.message);
            lotSize = result.adjustedLotSize;
         }
      }

      return true;
   }

// Cap lot size to available margin, then enforce symbol minimum
   static bool FinalizeLotSize(const string symbol, double &lotSize)
   {
      lotSize = CFastScalpSizing::CapLotToMargin(lotSize, symbol);

      // Minimum lot check: skip scalp signal if capped lot is below symbol minimum
      double symbolMinLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      if(lotSize < symbolMinLot)
      {
         PrintFormat("[SCALP-LOT-MIN] %s | capped lot %.2f < min lot %.2f â€?skipping scalp signal",
                     symbol, lotSize, symbolMinLot);
         return false;
      }

      return true;
   }

// Supports both synchronous and async execution modes
   static bool Execute(const string symbol, ENUM_TRADE_SIGNAL signal,
                       double lotSize, double confidence,
                       const SScalpConfig &config,
                       long magicNumber,
                       CTradeManager* tradeManager,
                       CUnifiedRiskManager* riskManager,
                       CAIAdapter* aiAdapter,
                       CFastScalpAsyncTracker &asyncTracker,
                       CFastScalpPositionTracker &positionTracker,
                       CFastScalpRiskBudget &riskBudget,
                       datetime &lastScalpTime)
   {
      if(tradeManager == NULL)
         return false;

      ENUM_ORDER_TYPE orderType = (signal == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      // Build comment with SCALP tag for position identification
      string comment = "SCALP|EMA" + IntegerToString(config.fastEMA) + "/" +
                       IntegerToString(config.slowEMA) + "|C:" +
                       DoubleToString(confidence, 2);

      // Refresh prices immediately before order submission
      double bid = 0.0, ask = 0.0;
      if(!CFastScalpFilters::RefreshScalpPrice(symbol, ask, bid))
         return false;

      double entryPrice = (orderType == ORDER_TYPE_BUY) ? ask : bid;
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return false;

      double sl = 0.0, tp = 0.0;
      if(orderType == ORDER_TYPE_BUY)
      {
         sl = NormalizeDouble(entryPrice - config.scalpSLPips * point, digits);
         tp = NormalizeDouble(entryPrice + config.scalpTPPips * point, digits);
      }
      else
      {
         sl = NormalizeDouble(entryPrice + config.scalpSLPips * point, digits);
         tp = NormalizeDouble(entryPrice - config.scalpTPPips * point, digits);
      }

      // The scalp path's single pre-trade gate ran in ValidateRiskAndAdjust, on this same lot before
      // the margin cap. FinalizeLotSize can only shrink or refuse, so re-validating here approved the
      // same trade a second time and took a second virtual reservation for it.

      // L10-018: AI-VOTE logging. Unreachable today: the only Initialize call site
      // (EAOrchestrator.mqh:1162) leaves the optional aiAdapter defaulted to NULL.
      if(aiAdapter != NULL)
      {
         PrintFormat("[AI-VOTE] symbol=%s strategy=FastScalp vote=%s",
                     symbol, signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL");
      }

      //--- Async mode: use TradeManager's SendTradeAsync (which includes preflight)
      if(asyncTracker.IsAsyncMode())
      {
         int direction = (signal == TRADE_SIGNAL_BUY) ? 1 : -1;

         // base + GetMagicOffsetForSymbol() is this symbol's consensus magic; the band is what separates the books.
         ulong magic = (ulong)((long)magicNumber + MAGIC_ENGINE_FAST_SCALP);
         bool sent = tradeManager.SendTradeAsync(orderType, symbol, lotSize,
                                                  entryPrice, sl, tp,
                                                  magic, 5000);
         if(!sent)
         {
            PrintFormat("[SCALP-ASYNC-FAILED] %s | %s | lot=%.2f",
                        symbol,
                        signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                        lotSize);
            return false;
         }

         // Batch 152 (T-10): the request we just submitted was appended at the END
         // of the pending array - index 0 is the oldest, possibly unrelated entry.
         int lastPendingIdx = tradeManager.GetPendingAsyncCount() - 1;
         asyncTracker.OnAsyncOrderSent(lastPendingIdx >= 0 ?
                          tradeManager.GetPendingAsyncTicket(lastPendingIdx) : 0,
                          symbol, direction, lotSize, entryPrice, sl, tp);

         lastScalpTime = TimeCurrent();

         // Track risk usage optimistically (will adjust on confirmation)
         double riskPerTrade = riskManager != NULL ?
                               riskManager.GetActiveRiskPerTradePercent() : 1.0;
         riskBudget.Add(riskPerTrade);

         PrintFormat("[SCALP-ASYNC-SENT] %s | %s | lot=%.2f | SL=%d | TP=%d | confidence=%.2f",
                     symbol,
                     signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                     lotSize,
                     config.scalpSLPips,
                     config.scalpTPPips,
                     confidence);

         return true;
      }

      //--- Synchronous mode: use CTradeManager.OpenPosition (which calls risk manager internally)
      // Explicit band: leaving magic at 0 lets OpenPosition stamp this symbol's consensus magic.
      bool result = tradeManager.OpenPosition(
                       symbol,
                       orderType,
                       lotSize,
                       0.0,  // price = 0 => market order
                       (double)config.scalpSLPips,
                       (double)config.scalpTPPips,
                       comment,
                       (uint)((long)magicNumber + MAGIC_ENGINE_FAST_SCALP));

      if(result)
      {
         lastScalpTime = TimeCurrent();

         double riskPerTrade = riskManager != NULL ?
                               riskManager.GetActiveRiskPerTradePercent() : 1.0;

         // L10-015: Check for partial fill and scale risk budget
         STradeExecutionReceipt receipt;
         tradeManager.GetLastExecutionReceipt(receipt);
         double fillRatio = 1.0;
         if(receipt.partialFill && receipt.requestedVolume > 0.0)
         {
             fillRatio = receipt.filledVolume / receipt.requestedVolume;
             if(fillRatio < 1.0)
             {
                 riskPerTrade *= fillRatio;
                 PrintFormat("[SCALP-PARTIAL-FILL] %s | requested=%.2f | filled=%.2f | fillRatio=%.2f | risk scaled to %.4f%%",
                             symbol, receipt.requestedVolume, receipt.filledVolume, fillRatio, riskPerTrade);
             }
         }

         riskBudget.Add(riskPerTrade);

         // Register the position for tick-level management
         // Tracker slots are keyed by position ticket; GetLastTicket() is the order ticket, and the
         // sync pass dropped such a slot and freed its risk budget while the position was still open.
         ulong ticket = 0;
         double filledVolume = 0.0;
         bool positionVisible =
             CTradeMgrPreflight::FindFreshPositionForSend(symbol, orderType, lotSize, ticket, filledVolume, "SCALP");

         double filledEntryPrice = tradeManager.GetLastRequestedPrice();
         double filledPoint = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double filledSL = 0.0, filledTP = 0.0;
         if(filledPoint > 0.0)
         {
            if(orderType == ORDER_TYPE_BUY)
            {
               filledSL = filledEntryPrice - config.scalpSLPips * filledPoint;
               filledTP = filledEntryPrice + config.scalpTPPips * filledPoint;
            }
            else
            {
               filledSL = filledEntryPrice + config.scalpSLPips * filledPoint;
               filledTP = filledEntryPrice - config.scalpTPPips * filledPoint;
            }
         }

         // Calculate 1R profit price for partial close
         double oneRPrice = 0.0;
         if(filledPoint > 0.0)
         {
            if(orderType == ORDER_TYPE_BUY)
               oneRPrice = filledEntryPrice + config.scalpSLPips * filledPoint;  // 1R = SL distance
            else
               oneRPrice = filledEntryPrice - config.scalpSLPips * filledPoint;
         }

         if(positionVisible)
            positionTracker.RegisterScalpPosition(ticket, symbol, filledEntryPrice, filledSL, filledTP, oneRPrice);

         PrintFormat("[SCALP-ENTRY] %s | %s | lot=%.2f | SL=%d | TP=%d | confidence=%.2f | ticket=%I64u%s",
                     symbol,
                     signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                     lotSize,
                     config.scalpSLPips,
                     config.scalpTPPips,
                     confidence,
                     ticket,
                     positionVisible ? "" : " | position not visible yet, sync will adopt it");
      }

      return result;
   }
};

#endif // CORE_SCALP_FAST_SCALP_ENTRY_MQH

