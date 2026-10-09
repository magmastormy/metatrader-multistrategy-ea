// Grid recovery engine for mean-reverting synthetic indices
// Places progressive grid levels when Hurst confirms mean-reversion
// Thin coordinator: shared types, grid level math, drawdown guards,
// ATR handles, statistics and order execution live in the
// GridRecovery* modules included below. Behaviour is unchanged.
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_GRID_RECOVERY_ENGINE_MQH
#define CORE_SCALP_GRID_RECOVERY_ENGINE_MQH

#include "../Utils/Instruments.mqh"
#include "../Risk/PositionSizer.mqh"
#include "../Risk/UnifiedRiskManager.mqh"
#include <Trade\Trade.mqh>

class CUnifiedRiskManager;

// Forward declaration for AI adapter (L10-018)
class CAIAdapter;

// Extracted modules (structural debloat â€?no behaviour change)
#include "GridRecoveryTypes.mqh"
#include "GridRecoveryLevels.mqh"
#include "GridRecoverySequence.mqh"
#include "GridRecoveryDrawdown.mqh"
#include "GridRecoveryMetrics.mqh"
#include "GridRecoveryAtr.mqh"
#include "GridRecoveryExecution.mqh"

// CGridRecoveryEngine â€?Grid recovery for mean-reverting synthetics
class CGridRecoveryEngine
{
private:
   SGridRecoveryConfig       m_config;
   SGridSymbolState          m_symbolStates[];
   int                       m_symbolCount;
   int                       m_baseMagic;
   CPositionSizer*           m_positionSizer;

   // Extracted collaborators (owned by value)
   CGridRecoveryAtr          m_atr;         // ATR indicator handles per symbol
   CGridRecoveryMetrics      m_metrics;     // Statistics
   CGridRecoveryExecution    m_execution;   // Risk gate + trade execution

// Find symbol index in the states array
   int FindSymbolIndex(const string symbol) const
   {
      return CGridRecoveryLevels::FindSymbolIndex(m_symbolStates, m_symbolCount, symbol);
   }

// Initialize a symbol state slot with defaults
   void InitializeSymbolState(int idx, const string symbol)
   {
      CGridRecoveryLevels::InitializeSymbolState(m_symbolStates[idx], symbol, m_config.maxGridLevels);
   }

// Update ATR value for a symbol
   void UpdateATR(int idx)
   {
      m_atr.UpdateATR(idx, m_symbolStates[idx]);
   }

// Calculate Fibonacci number for a given level
   int FibonacciNumber(int level) const
   {
      return CGridRecoveryLevels::FibonacciNumber(level);
   }

// Normalize lot size to symbol volume constraints
   double NormalizeLot(const string symbol, double lotSize) const
   {
      return CGridRecoveryLevels::NormalizeLot(symbol, lotSize);
   }

// Cap lot size to available margin
   double CapLotToMargin(double lotSize, const string symbol, ENUM_ORDER_TYPE orderType) const
   {
      return CGridRecoveryLevels::CapLotToMargin(lotSize, symbol, orderType);
   }

// Calculate grid drawdown as percentage of equity
   double CalculateGridDrawdownPercent(int idx) const
   {
      return CGridRecoveryDrawdown::CalculateGridDrawdownPercent(m_symbolStates[idx]);
   }

public:
// Constructor
   CGridRecoveryEngine() :
      m_symbolCount(0),
      m_baseMagic(0),
      m_positionSizer(NULL)
   {
   }

// Destructor
   ~CGridRecoveryEngine()
   {
      Deinit();
   }

// Initialize the engine with config and dependencies
   bool Init(const SGridRecoveryConfig &config, int baseMagic, CPositionSizer *pSizer, CUnifiedRiskManager *pRiskManager = NULL, CTradeManager *pTradeManager = NULL, CAIAdapter *pAIAdapter = NULL)
   {
      m_config         = config;
      m_baseMagic      = baseMagic;
      m_positionSizer  = pSizer;
      m_execution.Configure(pRiskManager, pTradeManager, pAIAdapter);
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

// Add a symbol to monitor for grid recovery
   bool AddSymbol(const string symbol)
   {
      // Check for duplicate
      if(FindSymbolIndex(symbol) >= 0)
      {
         PrintFormat("[GRID-RECOVERY] Symbol %s already registered", symbol);
         return false;
      }

      // Create ATR indicator handle
      int atrHandle = CGridRecoveryAtr::CreateHandle(symbol, m_config.atrPeriod);
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

      m_atr.Resize(newSize);

      // Initialize new slot
      m_symbolStates[m_symbolCount].symbol = symbol;
      InitializeSymbolState(m_symbolCount, symbol);
      m_atr.SetHandle(m_symbolCount, atrHandle);
      m_symbolCount++;

      PrintFormat("[GRID-RECOVERY] Symbol added: %s (index=%d atrHandle=%d)",
                  symbol, m_symbolCount - 1, atrHandle);
      return true;
   }

// Release all indicator handles and clean up
   void Deinit()
   {
      m_atr.ReleaseAll(m_symbolCount);
      m_symbolCount = 0;

      PrintFormat("[GRID-RECOVERY] Deinitialized | gridsOpened=%d | gridsClosed=%d | levelsPlaced=%d",
                  m_metrics.TotalGridsOpened(), m_metrics.TotalGridsClosed(), m_metrics.TotalLevelsPlaced());
   }

// Process a tick for a given symbol â€?call every tick
   void ProcessTick(const string symbol, double bid, double ask)
   {
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
         return;

      if(!m_symbolStates[idx].isActive)
         return;

      UpdateATR(idx);

      double atr = m_symbolStates[idx].currentATR;
      if(atr <= 0.0)
         return;

      // Check if grid should be activated
      if(!IsGridActive(symbol))
      {
         if(ShouldActivateGrid(idx))
         {
            int direction = CGridRecoverySequence::DetermineGridDirection(symbol, bid, ask);

            // Open the first grid level
            if(OpenGridLevel(idx, direction, 0))
            {
               m_symbolStates[idx].direction = direction;
               m_symbolStates[idx].activeLevelCount = 1;
               m_symbolStates[idx].lastGridEntryTime = TimeCurrent();
               m_metrics.RecordGridOpened();

               PrintFormat("[GRID-RECOVERY] Grid activated: %s direction=%s ATR=%.5f atrSMA=%.5f",
                           symbol, direction == 1 ? "BUY" : "SELL", atr, m_symbolStates[idx].atrSMA);
            }
         }
         return;
      }

      // Grid is active â€?manage existing positions
      ManageGridPositions(idx);

      // Check if all levels are in profit (close entire grid)
      bool allInProfit = CGridRecoverySequence::AllLevelsInProfit(m_symbolStates[idx]);

      if(allInProfit && m_symbolStates[idx].activeLevelCount > 0)
      {
         PrintFormat("[GRID-RECOVERY] All levels in profit for %s â€?closing grid", symbol);
         CloseAllGrids(symbol);
      }
   }

// Check if grid should be activated
// Requires: Hurst regime confirmed, no existing grid, cooldown ok
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

      // L10-003: Equity floor check - don't activate grid if equity below floor
      if(!CGridRecoveryDrawdown::PassesActivationEquityFloor(m_config.equityFloorPercent))
         return false;

      return true;
   }

// Open a grid level order
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
         PrintFormat("[GRID-RECOVERY] ATR is zero for %s â€?cannot calculate grid", symbol);
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

         // L10-003: Record initial equity when grid is first activated
         m_symbolStates[idx].initialEquity = AccountInfoDouble(ACCOUNT_EQUITY);
         PrintFormat("[GRID-RECOVERY] Grid activated for %s | initialEquity=%.2f | floor=%.1f%%",
                     symbol, m_symbolStates[idx].initialEquity, m_config.equityFloorPercent);
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

      // L10-003: Equity floor check - stop grid if equity dropped below floor
      if(!CGridRecoveryDrawdown::PassesLevelEquityFloor(m_symbolStates[idx].initialEquity, m_config.equityFloorPercent, level))
         return false;

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
               double slDist = atr * m_config.slAtrMultiplier;
               double slPips = slDist / point;
               baseLot = m_positionSizer.CalculatePositionSize(
                           symbol, slPips, 0.60);
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

      // L10-003: Cap cumulative lot multiplier to prevent unbounded martingale risk
      double cumulativeLotRatio = 0.0;
      if(!CGridRecoveryLevels::PassesCumulativeLotCap(m_config, level, baseLot, cumulativeLotRatio))
         return false;

      // Debug: log lot calculation details
      PrintFormat("[GRID-RECOVERY-DEBUG] %s L%d | baseLot=%.2f progressionType=%s factor=%.2f rawLot=%.2f cumRatio=%.2f/%.2f",
                  symbol, level, baseLot,
                  m_config.progressionType == GRID_PROGRESSION_MARTINGALE ? "MARTINGALE" : "FIBONACCI",
                  m_config.progressionFactor, lotSize, cumulativeLotRatio, m_config.maxCumulativeLotMultiplier);

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
      CGridRecoveryLevels::CalculateStops(direction, entryPrice, slDistance, tpDistance, digits, sl, tp);

      // Calculate magic number: baseMagic + magicOffset + symbolIndex * 100 + level
      // FIX: Include level in magic to prevent collision across 8 grid levels
      int magic = m_baseMagic + m_config.magicOffset + idx * 100 + level;

      // Pre-trade risk validation via UnifiedRiskManager (AGENTS.md invariant #1)
      if(!m_execution.PassesRiskValidation(symbol, orderType, lotSize, slDistance, level))
         return false;

      // L10-018: AI-VOTE logging
      m_execution.LogAIVote(symbol, direction);

      // L10-014: Execute with dynamic slippage from TradeManager if available
      ulong resultTicket = 0;
      bool result = m_execution.ExecuteEntry(symbol, direction, level, lotSize, entryPrice, sl, tp, magic, resultTicket);

      if(result)
      {
         m_symbolStates[idx].levels[level].lotSize     = lotSize;
         m_symbolStates[idx].levels[level].entryPrice  = entryPrice;
         m_symbolStates[idx].levels[level].sl          = sl;
         m_symbolStates[idx].levels[level].tp          = tp;
         m_symbolStates[idx].levels[level].ticket      = resultTicket;
         m_symbolStates[idx].levels[level].isActive    = true;
         m_symbolStates[idx].lastGridEntryTime         = TimeCurrent();
         m_metrics.RecordLevelPlaced();

         // Update total grid risk
         double risk = lotSize * slDistance;
         m_symbolStates[idx].totalGridRisk += risk;
      }

      return result;
   }

// Manage grid positions â€?check filled levels, add next if needed
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
         PrintFormat("[GRID-RECOVERY] Max drawdown reached for %s (%.1f%% >= %d%%) â€?closing grid",
                     symbol, CalculateGridDrawdownPercent(idx), m_config.maxDrawdownPercent);
         CloseAllGrids(symbol);
         return;
      }

      // Check cooldown before adding new levels
      datetime now = TimeCurrent();
      ulong elapsedMs = (ulong)((now - m_symbolStates[idx].lastGridEntryTime) * 1000);

      // Scan active levels and check if we need to add the next one
      int lastActiveLevel = -1;
      int currentActiveCount = CGridRecoverySequence::ScanActiveLevels(m_symbolStates[idx], lastActiveLevel);

      // If no active levels remain, grid has completed
      if(currentActiveCount == 0 && m_symbolStates[idx].activeLevelCount > 0)
      {
         PrintFormat("[GRID-RECOVERY] Grid completed for %s â€?all levels closed", symbol);
         m_symbolStates[idx].activeLevelCount = 0;
         m_symbolStates[idx].direction = 0;
         m_symbolStates[idx].totalGridRisk = 0.0;
         m_metrics.RecordGridClosed();
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

            bool priceMovedEnough = CGridRecoverySequence::HasPriceMovedForNextLevel(
                                       symbol, direction, lastEntry, gridSpacing);

            if(priceMovedEnough)
            {
               if(OpenGridLevel(idx, direction, nextLevel))
               {
                  m_symbolStates[idx].activeLevelCount = nextLevel + 1;
                  PrintFormat("[GRID-RECOVERY] Added level %d for %s â€?price moved against grid",
                              nextLevel, symbol);
               }
            }
         }
      }
   }

// Calculate lot size for a grid level based on progression type
   double CalculateGridLot(int level, double baseLot)
   {
      return CGridRecoveryLevels::CalculateGridLot(m_config, level, baseLot);
   }

// Check if a grid is currently running for a symbol
   bool IsGridActive(const string symbol)
   {
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
         return false;

      return (m_symbolStates[idx].activeLevelCount > 0);
   }

   double GetTotalGridRisk(const string symbol)
   {
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
         return 0.0;

      return m_symbolStates[idx].totalGridRisk;
   }

// Emergency close all grid positions for a symbol
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
            if(!m_execution.ClosePositionTicket(symbol, l, m_symbolStates[idx].levels[l].ticket))
               allClosed = false;
            else
               closedCount++;
         }

         m_symbolStates[idx].levels[l].isActive = false;
         m_symbolStates[idx].levels[l].ticket = 0;
      }

      // Reset grid state
      m_symbolStates[idx].activeLevelCount = 0;
      m_symbolStates[idx].direction = 0;
      m_symbolStates[idx].totalGridRisk = 0.0;
      m_metrics.RecordGridClosed();

      PrintFormat("[GRID-RECOVERY] Closed grid for %s | closed=%d | allClosed=%s",
                  symbol, closedCount, allClosed ? "true" : "false");

      return allClosed;
   }

// Count positions with "GRID-RECOVERY" in comment
   int GetActiveGridPositions()
   {
      return CGridRecoveryMetrics::GetActiveGridPositions();
   }

// Update config parameters for family
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

// Set Hurst regime confirmation for a symbol
// Called externally by Hurst calculator or indicator bridge
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

   void PrintDiagnostics()
   {
      PrintFormat("[GRID-RECOVERY-DIAG] symbols=%d | gridsOpened=%d | gridsClosed=%d | levelsPlaced=%d | activePositions=%d",
                  m_symbolCount,
                  m_metrics.TotalGridsOpened(),
                  m_metrics.TotalGridsClosed(),
                  m_metrics.TotalLevelsPlaced(),
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
