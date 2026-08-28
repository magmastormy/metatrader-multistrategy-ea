//+------------------------------------------------------------------+
//| FastScalpEntry.mqh                                               |
//| Decomposition extraction from CFastScalpEngine (behaviour        |
//| preserving).                                                     |
//|                                                                  |
//| Owns the scalp entry path that used to live inline in            |
//| CFastScalpEngine:                                                |
//|   PassesEntryGates()     — cooldown / max-positions / budget     |
//|                            pre-checks from ShouldEnterScalp()    |
//|   ValidateRiskAndAdjust()— CUnifiedRiskManager gating +          |
//|                            adjustedLotSize from ShouldEnterScalp |
//|   FinalizeLotSize()      — margin cap + symbol min-lot check     |
//|   Execute()              — the whole ExecuteScalpTrade() body     |
//|                            (async + synchronous paths)           |
//|                                                                  |
//| All methods are `static`; mutable engine state (cooldown stamp,  |
//| risk budget, trackers) is passed in by reference so the observed |
//| side effects and their ordering are identical to the original.   |
//|                                                                  |
//| Every risk gate, retcode branch and log tag is verbatim,         |
//| including the MANDATORY pre-trade CUnifiedRiskManager validation |
//| (AGENTS.md Invariant #1) and the L10-015 partial-fill risk       |
//| scaling.                                                         |
//+------------------------------------------------------------------+
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

// Forward declaration for AI adapter (L10-018) — only ever NULL-checked here
class CAIAdapter;

//+------------------------------------------------------------------+
//| CFastScalpEntry — stateless scalp entry gating + execution        |
//+------------------------------------------------------------------+
class CFastScalpEntry
{
public:
   //+------------------------------------------------------------------+
   //| Pre-signal entry gates: cooldown, max positions, risk budget      |
   //+------------------------------------------------------------------+
   static bool PassesEntryGates(const SScalpConfig &config,
                                datetime lastScalpTime,
                                double usedScalpRiskPct)
   {
      // Check cooldown
      datetime now = TimeCurrent();
      ulong elapsedMs = (ulong)((now - lastScalpTime) * 1000);
      if(lastScalpTime > 0 && elapsedMs < (ulong)config.scalpCooldownMs)
         return false;

      // Check max scalp positions
      int scalpCount = CFastScalpPositionTracker::CountScalpPositions();
      if(scalpCount >= config.maxScalpPositions)
         return false;

      // Check scalp risk budget
      if(usedScalpRiskPct >= config.scalpRiskPct)
         return false;

      return true;
   }

   //+------------------------------------------------------------------+
   //| Risk validation through CUnifiedRiskManager                       |
   //| Applies the risk-adjusted lot size in place when provided.        |
   //+------------------------------------------------------------------+
   static bool ValidateRiskAndAdjust(const string symbol,
                                     ENUM_TRADE_SIGNAL signal,
                                     double confidence,
                                     double &lotSize,
                                     const SScalpConfig &config,
                                     CUnifiedRiskManager* riskManager)
   {
      // Risk validation through CUnifiedRiskManager
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

         // Use risk-adjusted lot size if provided
         if(result.adjustedLotSize > 0.0)
            lotSize = result.adjustedLotSize;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Cap lot size to available margin, then enforce symbol minimum     |
   //+------------------------------------------------------------------+
   static bool FinalizeLotSize(const string symbol, double &lotSize)
   {
      // Cap lot size to available margin and symbol volume limits
      lotSize = CFastScalpSizing::CapLotToMargin(lotSize, symbol);

      // Minimum lot check: skip scalp signal if capped lot is below symbol minimum
      double symbolMinLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      if(lotSize < symbolMinLot)
      {
         PrintFormat("[SCALP-LOT-MIN] %s | capped lot %.2f < min lot %.2f — skipping scalp signal",
                     symbol, lotSize, symbolMinLot);
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Execute a scalp trade (market order)                              |
   //| Supports both synchronous and async execution modes               |
   //+------------------------------------------------------------------+
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

      // Calculate SL/TP in pips for risk validation
      double slPips = (point > 0.0) ? config.scalpSLPips : 0.0;
      double tpPips = (point > 0.0) ? config.scalpTPPips : 0.0;

      // MANDATORY RISK MANAGER VALIDATION (AGENTS.md Invariant #1)
      // All trade entries must pass CUnifiedRiskManager pre-trade gating
      if(riskManager != NULL)
      {
         STradeValidationRequest riskReq;
         ZeroMemory(riskReq);
         riskReq.symbol       = symbol;
         riskReq.orderType    = orderType;
         riskReq.lotSize      = lotSize;
         riskReq.stopLossPips = slPips;
         riskReq.takeProfitPips = tpPips;
         riskReq.confidence   = confidence;
         riskReq.strategy     = "FastScalp";
         riskReq.requestTime  = TimeCurrent();

         SValidationResult riskResult = riskManager.ValidateTradeRequest(riskReq, "scalp-pretrade");
         if(!riskResult.approved)
         {
            PrintFormat("[SCALP-REJECTED] %s | %s | lot=%.2f | reason=%s",
                        symbol,
                        signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                        lotSize,
                        riskResult.reason);
            return false;
         }
         // Apply adjusted lot size from risk manager if provided
         if(riskResult.adjustedLotSize > 0.0 && riskResult.adjustedLotSize < lotSize)
         {
            lotSize = riskResult.adjustedLotSize;
            PrintFormat("[SCALP-RISK-ADJUSTED] %s | lot reduced to %.2f", symbol, lotSize);
         }
      }

      // L10-018: AI-VOTE logging
      if(aiAdapter != NULL)
      {
         PrintFormat("[AI-VOTE] symbol=%s strategy=FastScalp vote=%s",
                     symbol, signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL");
      }

      //--- Async mode: use TradeManager's SendTradeAsync (which includes preflight)
      if(asyncTracker.IsAsyncMode())
      {
         int direction = (signal == TRADE_SIGNAL_BUY) ? 1 : -1;

         // Use TradeManager's async method which includes preflight validation
         // Batch 152 (T-01): carry the per-symbol strategy offset like the sync
         // path does, so async scalp positions land in the EA-owned magic range
         // that ownership scans actually match.
         ulong magic = (ulong)((long)magicNumber + tradeManager.GetMagicOffsetForSymbol(symbol));
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

         // Track the pending async order locally for management
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
      bool result = tradeManager.OpenPosition(
                       symbol,
                       orderType,
                       lotSize,
                       0.0,  // price = 0 => market order
                       (double)config.scalpSLPips,
                       (double)config.scalpTPPips,
                       comment);

      if(result)
      {
         lastScalpTime = TimeCurrent();

         // Track risk usage
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
         ulong ticket = tradeManager.GetLastTicket();
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

         positionTracker.RegisterScalpPosition(ticket, symbol, filledEntryPrice, filledSL, filledTP, oneRPrice);

         PrintFormat("[SCALP-ENTRY] %s | %s | lot=%.2f | SL=%d | TP=%d | confidence=%.2f | ticket=%I64u",
                     symbol,
                     signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                     lotSize,
                     config.scalpSLPips,
                     config.scalpTPPips,
                     confidence,
                     ticket);
      }

      return result;
   }
};

#endif // CORE_SCALP_FAST_SCALP_ENTRY_MQH
