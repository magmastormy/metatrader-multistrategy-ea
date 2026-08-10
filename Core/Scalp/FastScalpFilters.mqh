//+------------------------------------------------------------------+
//| FastScalpFilters.mqh                                             |
//| Decomposition extraction from CFastScalpEngine (behaviour        |
//| preserving).                                                     |
//|                                                                  |
//| Pure stateless entry gates / market-quality filters that used to |
//| live as private methods on CFastScalpEngine:                     |
//|   RefreshScalpPrice(), IsMomentumBurst(), IsSpreadAcceptable(),  |
//|   IsSyntheticSymbol(), IsScalpCostViable()                       |
//|                                                                  |
//| All methods are `static`. The two ATR-dependent gates now take   |
//| the ATR as an argument; the engine forwarder resolves it through |
//| GetATRCached(symbol) exactly as before, so the call sequence and |
//| the resulting behaviour are unchanged.                           |
//|                                                                  |
//| All log tags and thresholds are reproduced verbatim.             |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_SCALP_FAST_SCALP_FILTERS_MQH
#define CORE_SCALP_FAST_SCALP_FILTERS_MQH

#include "../Utils/Enums.mqh"
#include "FastScalpTypes.mqh"

// Forward declaration for global profiler access (initialized in EAOrchestrator)
class CMultiAssetProfiler;
extern CMultiAssetProfiler* g_multiAssetProfiler;

//+------------------------------------------------------------------+
//| CFastScalpFilters — stateless scalp gates                         |
//+------------------------------------------------------------------+
class CFastScalpFilters
{
public:
   //+------------------------------------------------------------------+
   //| Refresh market price with tick-level freshness check              |
   //| Returns true if valid prices obtained, false otherwise            |
   //| Prevents retcode=10015 (Invalid price) by ensuring latest tick   |
   //+------------------------------------------------------------------+
   static bool RefreshScalpPrice(const string symbol, double &ask, double &bid)
   {
      ask = 0.0;
      bid = 0.0;

      // Get the latest tick — most authoritative price source
      MqlTick tick;
      if(!SymbolInfoTick(symbol, tick))
      {
         PrintFormat("[SCALP-PRICE] SymbolInfoTick failed for %s — falling back to SymbolInfoDouble", symbol);
         ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
         bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      }
      else
      {
         ask = tick.ask;
         bid = tick.bid;
      }

      if(ask <= 0.0 || bid <= 0.0)
      {
         PrintFormat("[SCALP-PRICE] Invalid prices for %s: ask=%.5f bid=%.5f", symbol, ask, bid);
         return false;
      }

      // Batch 117: removed debug log — fires on every tick, creates excessive output
      return true;
   }

   //+------------------------------------------------------------------+
   //| Check momentum burst: current bar body > threshold * ATR         |
   //| `atr` is supplied by the caller via GetATRCached(symbol).        |
   //+------------------------------------------------------------------+
   static bool IsMomentumBurst(const string symbol, double atr, double momentumBurstATRRatio)
   {
      if(atr <= 0.0)
         return false;

      double open1  = iOpen(symbol, PERIOD_M1, 0);
      double close1 = iClose(symbol, PERIOD_M1, 0);
      if(open1 <= 0.0 || close1 <= 0.0)
         return false;

      double bodySize = MathAbs(close1 - open1);
      return (bodySize > momentumBurstATRRatio * atr);
   }

   //+------------------------------------------------------------------+
   //| Check spread gate: reject if spread > maxSpreadATRRatio * ATR    |
   //| `atr` is supplied by the caller via GetATRCached(symbol).        |
   //+------------------------------------------------------------------+
   static bool IsSpreadAcceptable(const string symbol, double atr, double maxSpreadATRRatio)
   {
      if(atr <= 0.0)
         return false;

      double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return false;

      double spreadPrice = spread * point;
      return (spreadPrice <= maxSpreadATRRatio * atr);
   }

   //+------------------------------------------------------------------+
   //| Check if Symbol is Synthetic Index                              |
   //+------------------------------------------------------------------+
   static bool IsSyntheticSymbol(const string symbol)
   {
      if(symbol == "") return false;

      // Use global multi-asset profiler for proper asset classification
      if(g_multiAssetProfiler != NULL)
      {
          SAssetProfile profile = g_multiAssetProfiler.GetProfile(symbol);
          return IsSyntheticAssetClass(profile.assetClass);
      }

      // Fallback to string matching if profiler not available
      if(StringFind(symbol, "Vol") >= 0  ||
         StringFind(symbol, "Vol") >= 0  ||      // Vol 10, Vol 25, Vol 50, etc.
         StringFind(symbol, "Step") >= 0 ||      // Step Index variants
         StringFind(symbol, "Boom") >= 0 ||      // Boom 1000, Boom 500
         StringFind(symbol, "Crash") >= 0 ||     // Crash 1000, Crash 500
         StringFind(symbol, "Jump") >= 0 ||      // Jump 10, Jump 25, etc.
         StringFind(symbol, "PainX") >= 0 ||     // Weltrade synthetic family
         StringFind(symbol, "Pain ") >= 0 ||     // Additional naming variant
         StringFind(symbol, "SFX Vol") >= 0 ||
         StringFind(symbol, "FX Vol") >= 0 ||
         StringFind(symbol, "GainX") >= 0 ||
         StringFind(symbol, "FlipX") >= 0 ||
         StringFind(symbol, "SwitchX") >= 0 ||   // SwitchX 1200 and variants
         StringFind(symbol, "Synth") >= 0 ||
         StringFind(symbol, "Index") >= 0)
      {
         return true;
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| Check if scalp is cost-viable given spread + commission           |
   //| Rejects if breakeven WR > 70% or total cost > 25% of TP          |
   //| Returns true if commission data is unavailable (pass-through)    |
   //| SYNTHETIC SYMBOLS: More permissive thresholds (wider spreads)    |
   //+------------------------------------------------------------------+
   static bool IsScalpCostViable(const string symbol, double slPoints, double tpPoints)
   {
      // Get total transaction cost
      double spreadPoints = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);

      // MQL5 does not have SYMBOL_TRADE_COMMISSION — estimate commission from
      // SYMBOL_TRADE_TICK_VALUE_PROFIT and SYMBOL_TRADE_CONTRACT_SIZE
      // For synthetic CFDs, commission is often embedded in the spread.
      // We use a conservative estimate: commission ≈ 0 if not detectable.
      double commissionPerLot = 0.0;

      // Try to detect commission from the difference between tick value profit and loss
      double tickValueProfit = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
      double tickValueLoss   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tickValueProfit > 0.0 && tickValueLoss > 0.0)
      {
         // If tick values differ, the difference is broker commission per tick
         double commissionPerTick = MathAbs(tickValueProfit - tickValueLoss);
         double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
         if(tickSize > 0.0)
            commissionPerLot = commissionPerTick * (1.0 / tickSize); // Convert to per-lot
      }

      // Total cost = spread + estimated commission (round-trip)
      double commissionPoints = 0.0;
      if(commissionPerLot > 0.0)
      {
         double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
         if(tickValue > 0.0 && tickSize > 0.0)
         {
            double pointValue = tickValue / tickSize;
            commissionPoints = commissionPerLot * 2.0 * pointValue; // Round-trip
         }
      }

      double totalCostPoints = spreadPoints + commissionPoints;

      // Breakeven win rate
      double breakevenWR = totalCostPoints / (totalCostPoints + tpPoints);

      // Check if symbol is synthetic - use more permissive thresholds
      bool isSynthetic = IsSyntheticSymbol(symbol);

      // Thresholds: standard vs synthetic
      double maxBreakevenWR = isSynthetic ? 0.85 : 0.70;   // Allow up to 85% breakeven WR for synthetics
      double maxCostRatioTP = isSynthetic ? 0.60 : 0.25;   // Allow up to 60% of TP for synthetics

      // Reject if cost is too high relative to target
      if(breakevenWR > maxBreakevenWR)
      {
         Print("[SCALP-COST-REJECTED] ", symbol, " cost too high: spread=", spreadPoints,
               " comm=", commissionPoints, " total=", totalCostPoints,
               " tp=", tpPoints, " breakevenWR=", DoubleToString(breakevenWR, 3),
               " > ", DoubleToString(maxBreakevenWR, 2), " (", isSynthetic ? "SYNTHETIC" : "STANDARD", ")");
         return false;
      }

      // Also reject if total cost > maxCostRatio of TP
      if(totalCostPoints > tpPoints * maxCostRatioTP)
      {
         Print("[SCALP-COST-REJECTED] ", symbol, " cost ratio too high: ",
               DoubleToString(totalCostPoints / tpPoints * 100.0, 1), "% of TP > ",
               DoubleToString(maxCostRatioTP * 100.0, 0), "% (", isSynthetic ? "SYNTHETIC" : "STANDARD", ")");
         return false;
      }

      Print("[SCALP-COST-OK] ", symbol, " cost viable: totalCost=", totalCostPoints,
            " tp=", tpPoints, " breakevenWR=", DoubleToString(breakevenWR, 3),
            " (", isSynthetic ? "SYNTHETIC" : "STANDARD", ")");
      return true;
   }
};

#endif // CORE_SCALP_FAST_SCALP_FILTERS_MQH
