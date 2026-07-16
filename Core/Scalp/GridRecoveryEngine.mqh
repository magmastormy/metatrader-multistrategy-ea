//+------------------------------------------------------------------+
//| GridRecoveryEngine.mqh                                           |
//| Grid recovery engine for mean-reverting synthetic indices        |
//| Places progressive grid levels when Hurst confirms mean-reversion|
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_GRID_RECOVERY_ENGINE_MQH
#define CORE_SCALP_GRID_RECOVERY_ENGINE_MQH

#include "../Utils/Instruments.mqh"
#include "../Risk/PositionSizer.mqh"
#include "../Risk/RiskValidationGate.mqh"
#include <Trade\Trade.mqh>

class CUnifiedRiskManager;

//+------------------------------------------------------------------+
//| Grid progression type                                             |
//+------------------------------------------------------------------+
enum ENUM_GRID_PROGRESSION
{
   GRID_PROGRESSION_MARTINGALE,    // Lot = baseLot * (factor ^ level)
   GRID_PROGRESSION_FIBONACCI      // Lot = baseLot * fib(level)
};

//+------------------------------------------------------------------+
//| Grid recovery configuration struct                                |
//+------------------------------------------------------------------+
struct SGridRecoveryConfig
{
   double   gridFactorATR;           // Grid spacing as fraction of ATR (0.20)
   int      maxGridLevels;           // Max grid levels (8)
   ENUM_GRID_PROGRESSION progressionType;  // Martingale or Fibonacci
   double   progressionFactor;       // Lot multiplier per level (1.5 for Martingale)
   double   activationHurstThreshold;// Only activate when Hurst < this (0.45)
   int      atrPeriod;               // ATR period (14)
   double   slAtrMultiplier;         // SL = ATR * this per level (1.5)
   double   tpAtrMultiplier;         // TP = 0.5 * grid size per level
   int      magicOffset;             // Magic number offset (8000)
   int      maxDrawdownPercent;      // Max total grid drawdown % (15)
   int      cooldownMs;              // Cooldown between grid entries in ms (30000)

   // Default constructor with production defaults
   SGridRecoveryConfig()
   {
      gridFactorATR            = 0.20;
      maxGridLevels            = 8;
      progressionType          = GRID_PROGRESSION_MARTINGALE;
      progressionFactor        = 1.5;
      activationHurstThreshold = 0.45;
      atrPeriod                = 14;
      slAtrMultiplier          = 1.5;
      tpAtrMultiplier          = 0.5;   // 0.5 * grid spacing
      magicOffset              = 8000;
      maxDrawdownPercent       = 15;
      cooldownMs               = 30000;
   }
};

//+------------------------------------------------------------------+
//| Single grid level tracking                                        |
//+------------------------------------------------------------------+
struct SGridLevel
{
   int      level;          // Grid level number (0-based)
   double   lotSize;        // Lot size for this level
   double   entryPrice;     // Entry price for this level
   double   sl;             // Stop loss price
   double   tp;             // Take profit price
   ulong    ticket;         // Position ticket (0 if not filled)
   bool     isActive;       // Whether this level is active/filled
};

//+------------------------------------------------------------------+
//| Per-symbol grid state tracking                                    |
//+------------------------------------------------------------------+
struct SGridSymbolState
{
   string      symbol;
   bool        isActive;               // Is this symbol being monitored
   SGridLevel  levels[];               // Array of grid levels for this symbol
   int         activeLevelCount;       // Count of active levels
   double      totalGridRisk;          // Sum of risk across all levels
   double      baseLotSize;            // Base lot size for level 0
   int         direction;              // 1=BUY, -1=SELL
   datetime    lastGridEntryTime;      // When last grid entry was placed
   double      currentATR;             // Current ATR value
   double      atrSMA;                 // ATR SMA value
   bool        hurstRegimeConfirmed;   // Hurst < threshold = mean-reversion confirmed
};

//+------------------------------------------------------------------+
//| CGridRecoveryEngine — Grid recovery for mean-reverting synthetics |
//+------------------------------------------------------------------+
class CGridRecoveryEngine
{
private:
   SGridRecoveryConfig       m_config;
   SGridSymbolState          m_symbolStates[];
   int                       m_symbolCount;
   int                       m_baseMagic;
   CPositionSizer*           m_positionSizer;
   CUnifiedRiskManager*      m_riskManager;
   CTrade                    m_trade;

   // ATR indicator handles per symbol
   int                       m_atrHandles[];

   // Statistics
   int                       m_totalGridsOpened;
   int                       m_totalGridsClosed;
   int                       m_totalLevelsPlaced;

   //+------------------------------------------------------------------+
   //| Find symbol index in the states array                             |
   //+------------------------------------------------------------------+
   int FindSymbolIndex(const string symbol) const
   {
      for(int i = 0; i < m_symbolCount; i++)
      {
         if(m_symbolStates[i].symbol == symbol)
            return i;
      }
      return -1;
   }

   //+------------------------------------------------------------------+
   //| Initialize a symbol state slot with defaults                      |
   //+------------------------------------------------------------------+
   void InitializeSymbolState(int idx, const string symbol)
   {
      m_symbolStates[idx].symbol                = symbol;
      m_symbolStates[idx].isActive              = true;
      m_symbolStates[idx].activeLevelCount      = 0;
      m_symbolStates[idx].totalGridRisk         = 0.0;
      m_symbolStates[idx].baseLotSize           = 0.0;
      m_symbolStates[idx].direction             = 0;
      m_symbolStates[idx].lastGridEntryTime     = 0;
      m_symbolStates[idx].currentATR            = 0.0;
      m_symbolStates[idx].atrSMA                = 0.0;
      m_symbolStates[idx].hurstRegimeConfirmed  = false;

      // Initialize levels array
      ArrayResize(m_symbolStates[idx].levels, m_config.maxGridLevels);
      for(int l = 0; l < m_config.maxGridLevels; l++)
      {
         m_symbolStates[idx].levels[l].level       = l;
         m_symbolStates[idx].levels[l].lotSize     = 0.0;
         m_symbolStates[idx].levels[l].entryPrice  = 0.0;
         m_symbolStates[idx].levels[l].sl          = 0.0;
         m_symbolStates[idx].levels[l].tp          = 0.0;
         m_symbolStates[idx].levels[l].ticket      = 0;
         m_symbolStates[idx].levels[l].isActive    = false;
      }
   }

   //+------------------------------------------------------------------+
   //| Update ATR value for a symbol                                     |
   //+------------------------------------------------------------------+
   void UpdateATR(int idx)
   {
      if(m_atrHandles[idx] == INVALID_HANDLE)
         return;

      // Read current ATR value
      double atrBuf[];
      ArraySetAsSeries(atrBuf, true);
      if(CopyBuffer(m_atrHandles[idx], 0, 0, 1, atrBuf) <= 0)
         return;

      m_symbolStates[idx].currentATR = atrBuf[0];

      // Compute ATR SMA manually from last 50 ATR values
      double atrHistory[];
      ArraySetAsSeries(atrHistory, true);
      int atrSmaPeriod = 50;
      int copied = CopyBuffer(m_atrHandles[idx], 0, 0, atrSmaPeriod, atrHistory);
      if(copied < atrSmaPeriod)
         return;

      double atrSma = 0.0;
      for(int i = 0; i < copied; i++)
         atrSma += atrHistory[i];
      atrSma /= (double)copied;

      m_symbolStates[idx].atrSMA = atrSma;
   }

   //+------------------------------------------------------------------+
   //| Calculate Fibonacci number for a given level                      |
   //| fib(0)=1, fib(1)=1, fib(2)=2, fib(3)=3, fib(4)=5, fib(5)=8     |
   //+------------------------------------------------------------------+
   int FibonacciNumber(int level) const
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

   //+------------------------------------------------------------------+
   //| Normalize lot size to symbol volume constraints                   |
   //+------------------------------------------------------------------+
   double NormalizeLot(const string symbol, double lotSize) const
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

//+------------------------------------------------------------------+
//| Cap lot size to available margin                                  |
//+------------------------------------------------------------------+
double CapLotToMargin(double lotSize, const string symbol, ENUM_ORDER_TYPE orderType) const
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
         double symbolMaxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
         double cappedLot = MathMin(lotSize, symbolMaxVolume);
         if(cappedLot < lotSize)
         {
            PrintFormat("[GRID-RECOVERY-MARGIN] %s lot capped from %.2f to %.2f (symbol max volume)",
                        symbol, lotSize, cappedLot);
         }
         return cappedLot;
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

   //+------------------------------------------------------------------+
   //| Calculate grid drawdown as percentage of equity                   |
   //+------------------------------------------------------------------+
   double CalculateGridDrawdownPercent(int idx) const
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0)
         return 0.0;

      double totalDrawdown = 0.0;
      for(int l = 0; l < m_symbolStates[idx].activeLevelCount; l++)
      {
         if(!m_symbolStates[idx].levels[l].isActive || m_symbolStates[idx].levels[l].ticket == 0)
            continue;

         if(PositionSelectByTicket(m_symbolStates[idx].levels[l].ticket))
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit < 0.0)
               totalDrawdown += MathAbs(profit);
         }
      }

      return (totalDrawdown / equity) * 100.0;
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CGridRecoveryEngine() :
      m_symbolCount(0),
      m_baseMagic(0),
       m_positionSizer(NULL),
       m_riskManager(NULL),
       m_totalGridsOpened(0),
      m_totalGridsClosed(0),
      m_totalLevelsPlaced(0)
   {
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CGridRecoveryEngine()
   {
      Deinit();
   }

   //+------------------------------------------------------------------+
   //| Initialize the engine with config and dependencies               |
   //+------------------------------------------------------------------+
   bool Init(const SGridRecoveryConfig &config, int baseMagic, CPositionSizer *pSizer, CUnifiedRiskManager *pRiskManager = NULL)
   {
      m_config         = config;
      m_baseMagic      = baseMagic;
      m_positionSizer  = pSizer;
      m_riskManager    = pRiskManager;
      m_symbolCount    = 0;

      PrintFormat("[GRID-RECOVERY] Initialized | gridATR=%.2f | maxLevels=%d | progression=%s | factor=%.2f | hurst=%.2f | slATR=%.1f | tpATR=%.1f | magicOffset=%d | maxDD=%d%% | cooldown=%dms",
                  m_config.gridFactorATR,
                  m_config.maxGridLevels,
                  m_config.progressionType == GRID_PROGRESSION_MARTINGALE ? "MARTINGALE" : "FIBONACCI",
                  m_config.progressionFactor,
                  m_config.activationHurstThreshold,
                  m_config.slAtrMultiplier,
                  m_config.tpAtrMultiplier,
                  m_config.magicOffset,
                  m_config.maxDrawdownPercent,
                  m_config.cooldownMs);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Add a symbol to monitor for grid recovery                        |
   //+------------------------------------------------------------------+
   bool AddSymbol(const string symbol)
   {
      // Check for duplicate
      if(FindSymbolIndex(symbol) >= 0)
      {
         PrintFormat("[GRID-RECOVERY] Symbol %s already registered", symbol);
         return false;
      }

      // Create ATR indicator handle
      int atrHandle = iATR(symbol, PERIOD_M1, m_config.atrPeriod);
      if(atrHandle == INVALID_HANDLE)
      {
         PrintFormat("[GRID-RECOVERY] Failed to create ATR handle for %s", symbol);
         return false;
      }

      // Resize arrays using temp struct pattern for string members
      int newSize = m_symbolCount + 1;

      SGridSymbolState tempStates[];
      ArrayResize(tempStates, newSize);
      for(int i = 0; i < m_symbolCount; i++)
         tempStates[i] = m_symbolStates[i];
      ArrayResize(m_symbolStates, newSize);
      for(int i = 0; i < m_symbolCount; i++)
         m_symbolStates[i] = tempStates[i];

      ArrayResize(m_atrHandles, newSize);

      // Initialize new slot
      m_symbolStates[m_symbolCount].symbol = symbol;
      InitializeSymbolState(m_symbolCount, symbol);
      m_atrHandles[m_symbolCount] = atrHandle;
      m_symbolCount++;

      PrintFormat("[GRID-RECOVERY] Symbol added: %s (index=%d atrHandle=%d)",
                  symbol, m_symbolCount - 1, atrHandle);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Release all indicator handles and clean up                       |
   //+------------------------------------------------------------------+
   void Deinit()
   {
      for(int i = 0; i < m_symbolCount; i++)
      {
         if(m_atrHandles[i] != INVALID_HANDLE)
         {
            IndicatorRelease(m_atrHandles[i]);
            m_atrHandles[i] = INVALID_HANDLE;
         }
      }
      m_symbolCount = 0;

      PrintFormat("[GRID-RECOVERY] Deinitialized | gridsOpened=%d | gridsClosed=%d | levelsPlaced=%d",
                  m_totalGridsOpened, m_totalGridsClosed, m_totalLevelsPlaced);
   }

   //+------------------------------------------------------------------+
   //| Process a tick for a given symbol — call every tick               |
   //+------------------------------------------------------------------+
   void ProcessTick(const string symbol, double bid, double ask)
   {
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
         return;

      if(!m_symbolStates[idx].isActive)
         return;

      // Update ATR
      UpdateATR(idx);

      double atr = m_symbolStates[idx].currentATR;
      if(atr <= 0.0)
         return;

      // Check if grid should be activated
      if(!IsGridActive(symbol))
      {
         if(ShouldActivateGrid(idx))
         {
            // Batch 117: Use price SMA (not ATR SMA) for direction determination
            // Compute 50-bar price SMA to determine mean-reversion direction
            double midPrice = (bid + ask) / 2.0;
            double priceSMA = 0;
            double closes[];
            ArraySetAsSeries(closes, true);
            int copied = CopyClose(symbol, PERIOD_CURRENT, 0, 50, closes);
            if(copied >= 50)
            {
               for(int j = 0; j < 50; j++)
                  priceSMA += closes[j];
               priceSMA /= 50.0;
            }
            else
               priceSMA = midPrice; // fallback: no direction bias

            int direction = 0;
            if(midPrice < priceSMA)
               direction = 1;   // BUY grid — price below SMA, expect reversion up
            else
               direction = -1;  // SELL grid — price above SMA, expect reversion down

            // Open the first grid level
            if(OpenGridLevel(idx, direction, 0))
            {
               m_symbolStates[idx].direction = direction;
               m_symbolStates[idx].activeLevelCount = 1;
               m_symbolStates[idx].lastGridEntryTime = TimeCurrent();
               m_totalGridsOpened++;

               PrintFormat("[GRID-RECOVERY] Grid activated: %s direction=%s ATR=%.5f atrSMA=%.5f",
                           symbol, direction == 1 ? "BUY" : "SELL", atr, m_symbolStates[idx].atrSMA);
            }
         }
         return;
      }

      // Grid is active — manage existing positions
      ManageGridPositions(idx);

      // Check if all levels are in profit (close entire grid)
      bool allInProfit = true;
      for(int l = 0; l < m_symbolStates[idx].activeLevelCount; l++)
      {
         if(!m_symbolStates[idx].levels[l].isActive || m_symbolStates[idx].levels[l].ticket == 0)
            continue;

         if(PositionSelectByTicket(m_symbolStates[idx].levels[l].ticket))
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit <= 0.0)
            {
               allInProfit = false;
               break;
            }
         }
         else
         {
            // Position no longer exists — mark as inactive
            m_symbolStates[idx].levels[l].isActive = false;
            m_symbolStates[idx].levels[l].ticket = 0;
         }
      }

      if(allInProfit && m_symbolStates[idx].activeLevelCount > 0)
      {
         PrintFormat("[GRID-RECOVERY] All levels in profit for %s — closing grid", symbol);
         CloseAllGrids(symbol);
      }
   }

   //+------------------------------------------------------------------+
   //| Check if grid should be activated                                 |
   //| Requires: Hurst regime confirmed, no existing grid, cooldown ok   |
   //+------------------------------------------------------------------+
   bool ShouldActivateGrid(int idx)
   {
      // Must have Hurst regime confirmed (mean-reversion)
      if(!m_symbolStates[idx].hurstRegimeConfirmed)
         return false;

      // No existing active grid
      if(m_symbolStates[idx].activeLevelCount > 0)
         return false;

      // Check cooldown
      datetime now = TimeCurrent();
      if(m_symbolStates[idx].lastGridEntryTime > 0)
      {
         ulong elapsedMs = (ulong)((now - m_symbolStates[idx].lastGridEntryTime) * 1000);
         if(elapsedMs < (ulong)m_config.cooldownMs)
            return false;
      }

      // Check max drawdown
      if(CalculateGridDrawdownPercent(idx) >= m_config.maxDrawdownPercent)
         return false;

      return true;
   }

   //+------------------------------------------------------------------+
   //| Open a grid level order                                           |
   //+------------------------------------------------------------------+
   bool OpenGridLevel(int idx, int direction, int level)
   {
      if(level < 0 || level >= m_config.maxGridLevels)
      {
         PrintFormat("[GRID-RECOVERY] Invalid level %d for %s (max=%d)",
                     level, m_symbolStates[idx].symbol, m_config.maxGridLevels);
         return false;
      }

      string symbol = m_symbolStates[idx].symbol;
      double atr = m_symbolStates[idx].currentATR;

      if(atr <= 0.0)
      {
         PrintFormat("[GRID-RECOVERY] ATR is zero for %s — cannot calculate grid", symbol);
         return false;
      }

      // Calculate grid spacing
      double gridSpacing = m_config.gridFactorATR * atr;

      // Calculate entry price
      double entryPrice = 0.0;
      if(level == 0)
      {
         // First level: use current market price
         double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
         double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
         entryPrice = (direction == 1) ? ask : bid;
      }
      else
      {
         // Subsequent levels: offset from previous level entry
         double prevEntry = m_symbolStates[idx].levels[level - 1].entryPrice;
         if(prevEntry <= 0.0)
         {
            PrintFormat("[GRID-RECOVERY] Previous level entry is zero for %s level %d", symbol, level);
            return false;
         }

         // Grid moves against the direction: BUY grid adds levels below, SELL grid above
         if(direction == 1)
            entryPrice = prevEntry - gridSpacing;   // BUY grid: lower entries
         else
            entryPrice = prevEntry + gridSpacing;   // SELL grid: higher entries
      }

      // Calculate lot size
      double baseLot = m_symbolStates[idx].baseLotSize;
      if(baseLot <= 0.0)
      {
         // Calculate base lot using position sizer
         if(m_positionSizer != NULL && m_positionSizer.IsInitialized())
         {
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            if(point > 0.0)
            {
               double slDistance = atr * m_config.slAtrMultiplier;
               double slPips = slDistance / point;
               ENUM_ORDER_TYPE orderType = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
               baseLot = m_positionSizer.CalculateOptimalPositionSize(
                           symbol, orderType, slPips, 0.60);
            }
         }

         if(baseLot <= 0.0)
         {
            double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
            baseLot = (minLot > 0.0) ? minLot : 0.01;
         }

         m_symbolStates[idx].baseLotSize = baseLot;
      }

      double lotSize = CalculateGridLot(level, baseLot);

      // Debug: log lot calculation details
      PrintFormat("[GRID-RECOVERY-DEBUG] %s L%d | baseLot=%.2f progressionType=%s factor=%.2f rawLot=%.2f",
                  symbol, level, baseLot,
                  m_config.progressionType == GRID_PROGRESSION_MARTINGALE ? "MARTINGALE" : "FIBONACCI",
                  m_config.progressionFactor, lotSize);

      // Normalize and cap lot
      ENUM_ORDER_TYPE orderType = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      lotSize = NormalizeLot(symbol, lotSize);
      PrintFormat("[GRID-RECOVERY-DEBUG] %s L%d | after NormalizeLot: %.2f (minVol=%.2f maxVol=%.2f step=%.4f)",
                  symbol, level, lotSize,
                  SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN),
                  SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX),
                  SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP));
      lotSize = CapLotToMargin(lotSize, symbol, orderType);
      PrintFormat("[GRID-RECOVERY-DEBUG] %s L%d | after CapLotToMargin: %.2f",
                  symbol, level, lotSize);

      if(lotSize <= 0.0)
      {
         PrintFormat("[GRID-RECOVERY] Invalid lot size for %s level %d: %.2f", symbol, level, lotSize);
         return false;
      }

      // Calculate SL and TP
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double slDistance = atr * m_config.slAtrMultiplier;
      double tpDistance = m_config.tpAtrMultiplier * gridSpacing;

      double sl = 0.0, tp = 0.0;
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

      // Calculate magic number: baseMagic + magicOffset + symbolIndex * 100 + level
      // FIX: Include level in magic to prevent collision across 8 grid levels
      int magic = m_baseMagic + m_config.magicOffset + idx * 100 + level;

      // Pre-trade risk validation via UnifiedRiskManager (AGENTS.md invariant #1)
      if(m_riskManager != NULL)
      {
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double slPips = (point > 0.0) ? (slDistance / point) : 0.0;
         STradeValidationRequest riskReq;
         ZeroMemory(riskReq);
         riskReq.symbol       = symbol;
         riskReq.orderType    = orderType;
         riskReq.lotSize      = lotSize;
         riskReq.stopLossPips = slPips;
         riskReq.confidence   = 0.6;
         riskReq.strategy     = "GRID-RECOVERY";
         riskReq.requestTime  = TimeCurrent();

         SValidationResult riskResult = m_riskManager.ValidateTradeRequest(riskReq, "grid-pretrade");
         if(!riskResult.approved)
         {
            PrintFormat("[GRID-RECOVERY] REJECTED by risk manager | symbol=%s level=%d | reason=%s", symbol, level, riskResult.reason);
            return false;
         }
      }

      // Set up trade object
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(50);
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);

      // Execute trade
      bool result = false;
      string comment = "GRID-RECOVERY|L:" + IntegerToString(level) + "|D:" + IntegerToString(direction);

      if(direction == 1)
         result = m_trade.Buy(lotSize, symbol, entryPrice, sl, tp, comment);
      else
         result = m_trade.Sell(lotSize, symbol, entryPrice, sl, tp, comment);

      if(result)
      {
         m_symbolStates[idx].levels[level].lotSize     = lotSize;
         m_symbolStates[idx].levels[level].entryPrice  = entryPrice;
         m_symbolStates[idx].levels[level].sl          = sl;
         m_symbolStates[idx].levels[level].tp          = tp;
         m_symbolStates[idx].levels[level].ticket      = m_trade.ResultOrder();
         m_symbolStates[idx].levels[level].isActive    = true;
         m_symbolStates[idx].lastGridEntryTime         = TimeCurrent();
         m_totalLevelsPlaced++;

         // Update total grid risk
         double risk = lotSize * slDistance;
         m_symbolStates[idx].totalGridRisk += risk;

         PrintFormat("[GRID-RECOVERY] Level opened: %s L%d %s lot=%.2f entry=%.5f SL=%.5f TP=%.5f magic=%d",
                     symbol, level, direction == 1 ? "BUY" : "SELL",
                     lotSize, entryPrice, sl, tp, magic);
      }
      else
      {
         uint retcode = m_trade.ResultRetcode();
         PrintFormat("[GRID-RECOVERY-FAILED] %s L%d %s lot=%.2f retcode=%u | price=%.5f SL=%.5f TP=%.5f magic=%d",
                     symbol, level, direction == 1 ? "BUY" : "SELL", lotSize, retcode, entryPrice, sl, tp, magic);
         
         // Additional debug info for common errors
         if(retcode == 10016) // ERR_INVALID_VOLUME
         {
            PrintFormat("[GRID-RECOVERY-ERROR] %s ERR_INVALID_VOLUME: lot=%.2f minVol=%.2f maxVol=%.2f step=%.4f | freeMargin=%.2f leverage=%d",
                        symbol, lotSize,
                        SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN),
                        SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX),
                        SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP),
                        AccountInfoDouble(ACCOUNT_MARGIN_FREE),
                        AccountInfoInteger(ACCOUNT_LEVERAGE));
         }
         else if(retcode == 10014) // ERR_INVALID_PRICE
         {
            PrintFormat("[GRID-RECOVERY-ERROR] %s ERR_INVALID_PRICE: entryPrice=%.5f SL=%.5f TP=%.5f digits=%d",
                        symbol, entryPrice, sl, tp, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
         }
         else if(retcode == 10008) // ERR_NOT_ENOUGH_MONEY
         {
            double usedMargin = 0.0;
            // ACCOUNT_MARGIN_USED may not be available in all MT5 builds
            // Fallback: used margin = margin - free margin
            double totalMargin = AccountInfoDouble(ACCOUNT_MARGIN);
            double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
            usedMargin = totalMargin - freeMargin;
            if(usedMargin < 0) usedMargin = 0;
            PrintFormat("[GRID-RECOVERY-ERROR] %s ERR_NOT_ENOUGH_MONEY: lot=%.2f freeMargin=%.2f usedMargin=%.2f totalMargin=%.2f",
                        symbol, lotSize, freeMargin, usedMargin, totalMargin);
         }
      }

      return result;
   }

   //+------------------------------------------------------------------+
   //| Manage grid positions — check filled levels, add next if needed    |
   //+------------------------------------------------------------------+
   void ManageGridPositions(int idx)
   {
      string symbol = m_symbolStates[idx].symbol;
      int direction = m_symbolStates[idx].direction;
      double atr = m_symbolStates[idx].currentATR;

      if(atr <= 0.0 || direction == 0)
         return;

      // Check drawdown limit
      if(CalculateGridDrawdownPercent(idx) >= m_config.maxDrawdownPercent)
      {
         PrintFormat("[GRID-RECOVERY] Max drawdown reached for %s (%.1f%% >= %d%%) — closing grid",
                     symbol, CalculateGridDrawdownPercent(idx), m_config.maxDrawdownPercent);
         CloseAllGrids(symbol);
         return;
      }

      // Check cooldown before adding new levels
      datetime now = TimeCurrent();
      ulong elapsedMs = (ulong)((now - m_symbolStates[idx].lastGridEntryTime) * 1000);

      // Scan active levels and check if we need to add the next one
      int currentActiveCount = 0;
      int lastActiveLevel = -1;

      for(int l = 0; l < m_symbolStates[idx].activeLevelCount; l++)
      {
         if(m_symbolStates[idx].levels[l].isActive)
         {
            // Verify position still exists
            if(m_symbolStates[idx].levels[l].ticket > 0)
            {
               if(!PositionSelectByTicket(m_symbolStates[idx].levels[l].ticket))
               {
                  // Position closed — mark inactive
                  m_symbolStates[idx].levels[l].isActive = false;
                  m_symbolStates[idx].levels[l].ticket = 0;
                  continue;
               }
            }
            currentActiveCount++;
            lastActiveLevel = l;
         }
      }

      // If no active levels remain, grid has completed
      if(currentActiveCount == 0 && m_symbolStates[idx].activeLevelCount > 0)
      {
         PrintFormat("[GRID-RECOVERY] Grid completed for %s — all levels closed", symbol);
         m_symbolStates[idx].activeLevelCount = 0;
         m_symbolStates[idx].direction = 0;
         m_symbolStates[idx].totalGridRisk = 0.0;
         m_totalGridsClosed++;
         return;
      }

      // Check if we should add the next level
      if(lastActiveLevel >= 0 && elapsedMs >= (ulong)m_config.cooldownMs)
      {
         int nextLevel = lastActiveLevel + 1;
         if(nextLevel < m_config.maxGridLevels)
         {
            // Check if price has moved against us enough to warrant next level
            double gridSpacing = m_config.gridFactorATR * atr;
            double lastEntry = m_symbolStates[idx].levels[lastActiveLevel].entryPrice;
            double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
            double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
            double currentPrice = (direction == 1) ? bid : ask;

            bool priceMovedEnough = false;
            if(direction == 1)
               priceMovedEnough = (lastEntry - currentPrice >= gridSpacing * 0.8);
            else
               priceMovedEnough = (currentPrice - lastEntry >= gridSpacing * 0.8);

            if(priceMovedEnough)
            {
               if(OpenGridLevel(idx, direction, nextLevel))
               {
                  m_symbolStates[idx].activeLevelCount = nextLevel + 1;
                  PrintFormat("[GRID-RECOVERY] Added level %d for %s — price moved against grid",
                              nextLevel, symbol);
               }
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Calculate lot size for a grid level based on progression type     |
   //+------------------------------------------------------------------+
   double CalculateGridLot(int level, double baseLot)
   {
      if(level == 0)
         return baseLot;

      if(m_config.progressionType == GRID_PROGRESSION_MARTINGALE)
      {
         // Lot = baseLot * (progressionFactor ^ level)
         return baseLot * MathPow(m_config.progressionFactor, level);
      }
      else // GRID_PROGRESSION_FIBONACCI
      {
         // Lot = baseLot * fib(level)
         return baseLot * (double)FibonacciNumber(level);
      }
   }

   //+------------------------------------------------------------------+
   //| Check if a grid is currently running for a symbol                 |
   //+------------------------------------------------------------------+
   bool IsGridActive(const string symbol)
   {
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
         return false;

      return (m_symbolStates[idx].activeLevelCount > 0);
   }

   //+------------------------------------------------------------------+
   //| Get total grid risk for a symbol                                  |
   //+------------------------------------------------------------------+
   double GetTotalGridRisk(const string symbol)
   {
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
         return 0.0;

      return m_symbolStates[idx].totalGridRisk;
   }

   //+------------------------------------------------------------------+
   //| Emergency close all grid positions for a symbol                   |
   //+------------------------------------------------------------------+
   bool CloseAllGrids(const string symbol)
   {
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
         return false;

      bool allClosed = true;
      int closedCount = 0;

      for(int l = 0; l < m_symbolStates[idx].activeLevelCount; l++)
      {
         if(!m_symbolStates[idx].levels[l].isActive || m_symbolStates[idx].levels[l].ticket == 0)
            continue;

         if(PositionSelectByTicket(m_symbolStates[idx].levels[l].ticket))
         {
            if(!m_trade.PositionClose(m_symbolStates[idx].levels[l].ticket))
            {
               uint retcode = m_trade.ResultRetcode();
               PrintFormat("[GRID-RECOVERY-CLOSE-FAILED] %s L%d ticket=%I64u retcode=%u",
                           symbol, l, m_symbolStates[idx].levels[l].ticket, retcode);
               allClosed = false;
            }
            else
            {
               closedCount++;
            }
         }

         m_symbolStates[idx].levels[l].isActive = false;
         m_symbolStates[idx].levels[l].ticket = 0;
      }

      // Reset grid state
      m_symbolStates[idx].activeLevelCount = 0;
      m_symbolStates[idx].direction = 0;
      m_symbolStates[idx].totalGridRisk = 0.0;
      m_totalGridsClosed++;

      PrintFormat("[GRID-RECOVERY] Closed grid for %s | closed=%d | allClosed=%s",
                  symbol, closedCount, allClosed ? "true" : "false");

      return allClosed;
   }

   //+------------------------------------------------------------------+
   //| Count positions with "GRID-RECOVERY" in comment                   |
   //+------------------------------------------------------------------+
   int GetActiveGridPositions()
   {
      int count = 0;
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(PositionSelectByTicket(ticket))
         {
            string comment = PositionGetString(POSITION_COMMENT);
            if(StringFind(comment, "GRID-RECOVERY") >= 0)
               count++;
         }
      }
      return count;
   }

   //+------------------------------------------------------------------+
   //| Update config parameters for family                               |
   //+------------------------------------------------------------------+
   void SetFamilyConfig(double gridFactorATR, int maxGridLevels, double progressionFactor,
                        double slAtrMult, double tpAtrMult, int magicOffset)
   {
      m_config.gridFactorATR     = gridFactorATR;
      m_config.maxGridLevels     = maxGridLevels;
      m_config.progressionFactor = progressionFactor;
      m_config.slAtrMultiplier   = slAtrMult;
      m_config.tpAtrMultiplier   = tpAtrMult;
      m_config.magicOffset       = magicOffset;

      PrintFormat("[GRID-RECOVERY] Family config updated | gridATR=%.2f | maxLevels=%d | factor=%.2f | slATR=%.1f | tpATR=%.1f | magicOffset=%d",
                  gridFactorATR, maxGridLevels, progressionFactor, slAtrMult, tpAtrMult, magicOffset);
   }

   //+------------------------------------------------------------------+
   //| Set Hurst regime confirmation for a symbol                        |
   //| Called externally by Hurst calculator or indicator bridge          |
   //+------------------------------------------------------------------+
   void SetHurstRegime(const string symbol, double hurstExponent)
   {
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
         return;

      m_symbolStates[idx].hurstRegimeConfirmed = (hurstExponent < m_config.activationHurstThreshold);

      PrintFormat("[GRID-RECOVERY] %s Hurst=%.3f threshold=%.3f regime=%s",
                  symbol, hurstExponent, m_config.activationHurstThreshold,
                  m_symbolStates[idx].hurstRegimeConfirmed ? "MEAN-REVERSION" : "TRENDING");
   }

   //+------------------------------------------------------------------+
   //| Print diagnostics                                                 |
   //+------------------------------------------------------------------+
   void PrintDiagnostics()
   {
      PrintFormat("[GRID-RECOVERY-DIAG] symbols=%d | gridsOpened=%d | gridsClosed=%d | levelsPlaced=%d | activePositions=%d",
                  m_symbolCount,
                  m_totalGridsOpened,
                  m_totalGridsClosed,
                  m_totalLevelsPlaced,
                  GetActiveGridPositions());

      for(int i = 0; i < m_symbolCount; i++)
      {
         PrintFormat("[GRID-RECOVERY-DIAG] %s | active=%s | dir=%d | levels=%d/%d | risk=%.2f | atr=%.5f | atrSMA=%.5f | hurst=%s | dd=%.1f%%",
                     m_symbolStates[i].symbol,
                     m_symbolStates[i].isActive ? "Y" : "N",
                     m_symbolStates[i].direction,
                     m_symbolStates[i].activeLevelCount,
                     m_config.maxGridLevels,
                     m_symbolStates[i].totalGridRisk,
                     m_symbolStates[i].currentATR,
                     m_symbolStates[i].atrSMA,
                     m_symbolStates[i].hurstRegimeConfirmed ? "MR" : "TR",
                     CalculateGridDrawdownPercent(i));

         // Log individual level details
         for(int l = 0; l < m_symbolStates[i].activeLevelCount; l++)
         {
            if(m_symbolStates[i].levels[l].isActive)
            {
               PrintFormat("[GRID-RECOVERY-DIAG]   L%d | lot=%.2f | entry=%.5f | SL=%.5f | TP=%.5f | ticket=%I64u",
                           l,
                           m_symbolStates[i].levels[l].lotSize,
                           m_symbolStates[i].levels[l].entryPrice,
                           m_symbolStates[i].levels[l].sl,
                           m_symbolStates[i].levels[l].tp,
                           m_symbolStates[i].levels[l].ticket);
            }
         }
      }
   }
};

#endif // CORE_SCALP_GRID_RECOVERY_ENGINE_MQH
