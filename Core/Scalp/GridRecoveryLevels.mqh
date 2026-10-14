// Grid level management: symbol slot lookup/initialization, lot
// progression (Fibonacci / Martingale), lot normalization and
// margin capping. Stateless static helpers.
// Extracted verbatim from GridRecoveryEngine.mqh (structural only).
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_GRID_RECOVERY_LEVELS_MQH
#define CORE_SCALP_GRID_RECOVERY_LEVELS_MQH

#include "GridRecoveryTypes.mqh"

class CGridRecoveryLevels
{
public:
   static int FindSymbolIndex(const SGridSymbolState &states[], int count, const string symbol)
   {
      for(int i = 0; i < count; i++)
      {
         if(states[i].symbol == symbol)
            return i;
      }
      return -1;
   }

   static void InitializeSymbolState(SGridSymbolState &state, const string symbol, int maxGridLevels)
   {
      state.symbol                = symbol;
      state.isActive              = true;
      state.activeLevelCount      = 0;
      state.totalGridRisk         = 0.0;
      state.baseLotSize           = 0.0;
      state.direction             = 0;
      state.lastGridEntryTime     = 0;
      state.currentATR            = 0.0;
      state.atrSMA                = 0.0;
      state.hurstRegimeConfirmed  = false;
      state.initialEquity         = 0.0;

      ArrayResize(state.levels, maxGridLevels);
      for(int l = 0; l < maxGridLevels; l++)
      {
         state.levels[l].level       = l;
         state.levels[l].lotSize     = 0.0;
         state.levels[l].entryPrice  = 0.0;
         state.levels[l].sl          = 0.0;
         state.levels[l].tp          = 0.0;
         state.levels[l].ticket      = 0;
         state.levels[l].isActive    = false;
      }
   }

   // A restart wipes level tickets: the positions the grid still owns would run to their own stops
   // unmanaged while the engine lays a fresh level 0 on top of them. Magic carries the level.
   static int RebuildLevelsFromPositions(SGridSymbolState &state, const long baseMagic)
   {
      int recovered = 0;
      int maxLevel = ArraySize(state.levels);

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != state.symbol)
            continue;
         if(StringFind(PositionGetString(POSITION_COMMENT), "GRID-RECOVERY") != 0)
            continue;

         long delta = PositionGetInteger(POSITION_MAGIC) - baseMagic;
         int level = -1;
         if(delta >= MAGIC_ENGINE_GRID && delta < MAGIC_ENGINE_GRID + MAGIC_CLUSTER_SPAN)
            level = (int)(delta - MAGIC_ENGINE_GRID);
         else if(delta >= 8000 && delta < 8000 + 10000)
            level = (int)(delta % MAGIC_SYMBOL_MULTIPLIER);

         if(level < 0 || level >= maxLevel)
         {
            PrintFormat("[GRID-RESTART] %s | ticket=%I64u | magic offset %I64d is not a level slot in 0..%d, left untracked",
                        state.symbol, ticket, delta, maxLevel - 1);
            continue;
         }
         if(state.levels[level].isActive)
         {
            PrintFormat("[GRID-RESTART] %s | L%d already held by ticket=%I64u, ignoring ticket=%I64u",
                        state.symbol, level, state.levels[level].ticket, ticket);
            continue;
         }

         state.levels[level].level      = level;
         state.levels[level].ticket     = ticket;
         state.levels[level].lotSize    = PositionGetDouble(POSITION_VOLUME);
         state.levels[level].entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         state.levels[level].sl         = PositionGetDouble(POSITION_SL);
         state.levels[level].tp         = PositionGetDouble(POSITION_TP);
         state.levels[level].isActive   = true;

         state.direction = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
         if(level == 0)
            state.baseLotSize = PositionGetDouble(POSITION_VOLUME);
         recovered++;
      }

      state.activeLevelCount = recovered;
      if(recovered > 0)
         PrintFormat("[GRID-RESTART] %s | %d level(s) rebuilt from open positions | direction=%s | baseLot=%.2f",
                     state.symbol, recovered, state.direction == 1 ? "BUY" : "SELL", state.baseLotSize);
      return recovered;
   }

   static int FibonacciNumber(int level)
   {
      if(level <= 1)
         return 1;

      int a = 1, b = 1;
      for(int i = 2; i <= level; i++)
      {
         int temp = a + b;
         a = b;
         b = temp;
      }
      return b;
   }

// Calculate lot size for a grid level based on progression type
   static double CalculateGridLot(const SGridRecoveryConfig &config, int level, double baseLot)
   {
      if(level == 0)
         return baseLot;

      if(config.progressionType == GRID_PROGRESSION_MARTINGALE)
      {
         // Lot = baseLot * (progressionFactor ^ level)
         return baseLot * MathPow(config.progressionFactor, level);
      }
      else // GRID_PROGRESSION_FIBONACCI
      {
         // Lot = baseLot * fib(level)
         return baseLot * (double)FibonacciNumber(level);
      }
   }

// L10-003: Cap cumulative lot multiplier to prevent unbounded
// martingale risk. Returns false when the cap is exceeded and
// reports the accumulated ratio through cumulativeLotRatio.
   static bool PassesCumulativeLotCap(const SGridRecoveryConfig &config, int level, double baseLot,
                                      double &cumulativeLotRatio)
   {
      cumulativeLotRatio = 0.0;
      for(int l = 0; l <= level; l++)
      {
         cumulativeLotRatio += CalculateGridLot(config, l, baseLot) / baseLot;
      }
      if(cumulativeLotRatio > config.maxCumulativeLotMultiplier)
      {
         PrintFormat("[GRID-RECOVERY] REJECTED L%d: Cumulative lot ratio %.2f exceeds max %.2f (baseLot=%.2f)",
                     level, cumulativeLotRatio, config.maxCumulativeLotMultiplier, baseLot);
         return false;
      }
      return true;
   }

// Calculate SL and TP for a grid level entry
   static void CalculateStops(int direction, double entryPrice, double slDistance, double tpDistance,
                              int digits, double &sl, double &tp)
   {
      sl = 0.0;
      tp = 0.0;
      if(direction == 1) // BUY
      {
         sl = NormalizeDouble(entryPrice - slDistance, digits);
         tp = NormalizeDouble(entryPrice + tpDistance, digits);
      }
      else // SELL
      {
         sl = NormalizeDouble(entryPrice + slDistance, digits);
         tp = NormalizeDouble(entryPrice - tpDistance, digits);
      }
   }

// Normalize lot size to symbol volume constraints
   static double NormalizeLot(const string symbol, double lotSize)
   {
      double stepVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minVol  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxVol  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

      if(stepVol <= 0.0) stepVol = 0.01;
      if(minVol <= 0.0)  minVol  = 0.01;

      lotSize = MathFloor((lotSize + 1e-12) / stepVol) * stepVol;

      // FIX: Reject lots below minimum instead of rounding up (prevents 15x risk multiplier)
      if(lotSize < minVol)
         return 0.0;  // Signal invalid - caller should skip this grid level
      if(lotSize > maxVol)
         lotSize = maxVol;

      return NormalizeDouble(lotSize, 2);
   }

// Cap lot size to available margin
   static double CapLotToMargin(double lotSize, const string symbol, ENUM_ORDER_TYPE orderType)
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double marginPerLot = 0.0;
      double priceForMargin = (orderType == ORDER_TYPE_BUY)
                              ? SymbolInfoDouble(symbol, SYMBOL_ASK)
                              : SymbolInfoDouble(symbol, SYMBOL_BID);

      bool marginCalcOk = OrderCalcMargin(orderType, symbol, 1.0, priceForMargin, marginPerLot);

      // Fallback: estimate margin from contract size and leverage if OrderCalcMargin fails
      if(!marginCalcOk || marginPerLot <= 0.0)
      {
         double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);

         // For Deriv synthetics: use ACCOUNT_LEVERAGE (1:1000 = 1000)
         long leverageLong = AccountInfoInteger(ACCOUNT_LEVERAGE);
         double leverage = (double)leverageLong;
         if(leverage <= 0) leverage = 1000.0; // Default for Deriv

         if(contractSize > 0 && leverage > 0 && priceForMargin > 0)
         {
            // Rough margin estimate: 1 lot * contractSize * price / leverage
            marginPerLot = priceForMargin * contractSize / leverage;

            PrintFormat("[GRID-RECOVERY-MARGIN] %s OrderCalcMargin failed/zero, fallback: leverage=%d contract=%.2f price=%.5f -> marginPerLot=%.2f",
                        symbol, (int)leverage, contractSize, priceForMargin, marginPerLot);
         }
         else
         {
            PrintFormat("[GRID-RECOVERY-MARGIN] %s margin calc FAILED - missing data, using symbol max volume cap only", symbol);
            // Just cap to symbol max volume
            double symbolMaxVolumeOnly = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
            double cappedLotOnly = MathMin(lotSize, symbolMaxVolumeOnly);
            if(cappedLotOnly < lotSize)
            {
               PrintFormat("[GRID-RECOVERY-MARGIN] %s lot capped from %.2f to %.2f (symbol max volume)",
                           symbol, lotSize, cappedLotOnly);
            }
            return cappedLotOnly;
         }
      }

      double maxLotByMargin = freeMargin / (marginPerLot * 1.5); // 1.5x safety buffer
      double symbolMaxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double cappedLot = MathMin(lotSize, MathMin(maxLotByMargin, symbolMaxVolume));

      // Additional safety: ensure lot is valid for symbol
      double stepVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minVol  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      if(stepVol > 0.0)
      {
         cappedLot = MathFloor((cappedLot + 1e-12) / stepVol) * stepVol;
      }
      if(cappedLot < minVol) cappedLot = 0.0; // Signal invalid

      if(cappedLot < lotSize)
      {
         PrintFormat("[GRID-RECOVERY-MARGIN] %s lot capped from %.2f to %.2f (margin_max=%.2f vol_max=%.2f marginPerLot=%.2f freeMargin=%.2f leverage=%d)",
                     symbol, lotSize, cappedLot, maxLotByMargin, symbolMaxVolume, marginPerLot, freeMargin, (int)AccountInfoInteger(ACCOUNT_LEVERAGE));
      }

      return cappedLot;
   }
};

#endif // CORE_SCALP_GRID_RECOVERY_LEVELS_MQH
