//+------------------------------------------------------------------+
//| ATRScalpingEngine.mqh                                            |
//| ATR-based scalping engine for between-spike/between-jump trading |
//| on Deriv synthetic indices. Trades in calm periods, avoids spikes|
//|                                                                  |
//| Thin coordinator: shared types, symbol registry, entry gates,    |
//| indicator/signal evaluation, entry execution, position exit      |
//| management and statistics live in the ATRScalp* modules included |
//| below. Behaviour is unchanged.                                   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_ATR_SCALPING_ENGINE_MQH
#define CORE_SCALP_ATR_SCALPING_ENGINE_MQH

#include "../Utils/Instruments.mqh"
#include "../Risk/PositionSizer.mqh"
#include "../Risk/UnifiedRiskManager.mqh"
#include "../../IndicatorManager.mqh"
#include <Trade\Trade.mqh>

class CUnifiedRiskManager;

// Extracted modules (structural debloat â€?no behaviour change)
#include "ATRScalpTypes.mqh"
#include "ATRScalpRegistry.mqh"
#include "ATRScalpFilter.mqh"
#include "ATRScalpSignal.mqh"
#include "ATRScalpEntry.mqh"
#include "ATRScalpExit.mqh"
#include "ATRScalpMetrics.mqh"

//+------------------------------------------------------------------+
//| CATRScalpingEngine â€?ATR-based between-spike scalping engine      |
//+------------------------------------------------------------------+
class CATRScalpingEngine
{
private:
   SATRScalpingConfig       m_config;
   SATRScalpSymbolState     m_symbolStates[];
   int                      m_symbolCount;
   CTrade                   m_trade;

   // Extracted collaborators (owned by value)
   CATRScalpSignal          m_signal;    // Indicator handles + signal evaluation
   CATRScalpEntry           m_entry;     // Sizing, risk gate, order execution
   CATRScalpMetrics         m_metrics;   // Skipped counter, census, diagnostics

   //+------------------------------------------------------------------+
   //| Find symbol index in the states array                             |
   //+------------------------------------------------------------------+
   int FindSymbolIndex(const string symbol) const
   {
      return CATRScalpRegistry::FindSymbolIndex(m_symbolStates, m_symbolCount, symbol);
   }

   //+------------------------------------------------------------------+
   //| Initialize a symbol state slot with defaults                      |
   //+------------------------------------------------------------------+
   void InitializeSymbolState(int idx, const string symbol, int spikeIntervalSec)
   {
      CATRScalpRegistry::InitializeSymbolState(m_symbolStates, idx, symbol, spikeIntervalSec);
   }

   //+------------------------------------------------------------------+
   //| Update indicator values for a symbol                              |
   //+------------------------------------------------------------------+
   bool UpdateIndicators(int idx)
   {
      return m_signal.UpdateIndicators(idx, m_symbolStates[idx]);
   }

   //+------------------------------------------------------------------+
   //| Check if within spikeWindowAvoidMinutes of expected spike         |
   //+------------------------------------------------------------------+
   bool IsInSpikeWindow(int idx)
   {
      return CATRScalpFilter::IsInSpikeWindow(m_symbolStates[idx], m_config.spikeWindowAvoidMinutes);
   }

   //+------------------------------------------------------------------+
   //| Evaluate scalp signal: EMA crossover + RSI + spread + spike gate  |
   //| Returns 0=none, 1=BUY, -1=SELL                                   |
   //+------------------------------------------------------------------+
   int EvaluateScalpSignal(int idx)
   {
      return m_signal.EvaluateScalpSignal(m_symbolStates[idx], m_config);
   }

   //+------------------------------------------------------------------+
   //| Open a scalp trade in the given direction                         |
   //+------------------------------------------------------------------+
   bool OpenScalpTrade(int idx, int direction)
   {
      return m_entry.OpenScalpTrade(idx, direction, m_symbolStates[idx], m_config, m_trade);
   }

   //+------------------------------------------------------------------+
   //| Manage open scalp positions: partial close, breakeven, trailing   |
   //+------------------------------------------------------------------+
   void ManageScalpPositions(int idx)
   {
      CATRScalpExit::ManageScalpPositions(m_symbolStates[idx].symbol, m_trade);
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CATRScalpingEngine() :
      m_symbolCount(0)
   {
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CATRScalpingEngine()
   {
      Deinit();
   }

   //+------------------------------------------------------------------+
   //| Initialize the engine with config and dependencies               |
   //+------------------------------------------------------------------+
   bool Init(const SATRScalpingConfig &config, int baseMagic, CPositionSizer *pSizer, CUnifiedRiskManager *pRiskManager = NULL)
   {
      m_config         = config;
      m_symbolCount    = 0;
      m_entry.Configure(baseMagic, pSizer, pRiskManager);

      PrintFormat("[ATR-SCALP-ENGINE] Initialized | atrPeriod=%d | emaFast=%d | emaSlow=%d | rsi=%d | slATR=%.1f | tpATR=%.1f | maxPos=%d | cooldown=%dms | spikeAvoid=%dmin | magicOffset=%d",
                  m_config.atrPeriod,
                  m_config.emaFastPeriod,
                  m_config.emaSlowPeriod,
                  m_config.rsiPeriod,
                  m_config.slAtrMultiplier,
                  m_config.tpAtrMultiplier,
                  m_config.maxPositions,
                  m_config.cooldownMs,
                  m_config.spikeWindowAvoidMinutes,
                  m_config.magicOffset);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Add a symbol to monitor for ATR scalping                         |
   //| spikeIntervalSec: expected spike interval (0 = no spike tracking) |
   //+------------------------------------------------------------------+
   bool AddSymbol(const string symbol, int spikeIntervalSec = 0)
   {
      // Check for duplicate
      if(FindSymbolIndex(symbol) >= 0)
      {
         PrintFormat("[ATR-SCALP-ENGINE] Symbol %s already registered", symbol);
         return false;
      }

      // Create indicator handles via CIndicatorManager (owned by singleton)
      int atrHandle = CIndicatorManager::Instance().GetATRHandle(symbol, PERIOD_M1, m_config.atrPeriod);
      if(atrHandle == INVALID_HANDLE)
      {
         PrintFormat("[ATR-SCALP-ENGINE] Failed to create ATR handle for %s", symbol);
         return false;
      }

      int emaFastHandle = CIndicatorManager::Instance().GetMAHandle(symbol, PERIOD_M1, m_config.emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(emaFastHandle == INVALID_HANDLE)
      {
         PrintFormat("[ATR-SCALP-ENGINE] Failed to create EMA fast handle for %s", symbol);
         return false;
      }

      int emaSlowHandle = CIndicatorManager::Instance().GetMAHandle(symbol, PERIOD_M1, m_config.emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(emaSlowHandle == INVALID_HANDLE)
      {
         PrintFormat("[ATR-SCALP-ENGINE] Failed to create EMA slow handle for %s", symbol);
         return false;
      }

      int rsiHandle = CIndicatorManager::Instance().GetRSIHandle(symbol, PERIOD_M1, m_config.rsiPeriod, PRICE_CLOSE);
      if(rsiHandle == INVALID_HANDLE)
      {
         PrintFormat("[ATR-SCALP-ENGINE] Failed to create RSI handle for %s", symbol);
         return false;
      }

      // Resize arrays â€?use temp struct pattern for string members
      int newSize = m_symbolCount + 1;

      CATRScalpRegistry::GrowStates(m_symbolStates, m_symbolCount, newSize);
      m_signal.ResizeHandles(newSize);

      // Initialize new slot
      InitializeSymbolState(m_symbolCount, symbol, spikeIntervalSec);
      m_signal.SetHandles(m_symbolCount, atrHandle, emaFastHandle, emaSlowHandle, rsiHandle);
      m_symbolCount++;

      PrintFormat("[ATR-SCALP-ENGINE] Symbol added: %s (index=%d atrHandle=%d emaFast=%d emaSlow=%d rsi=%d spikeInterval=%ds)",
                  symbol, m_symbolCount - 1, atrHandle, emaFastHandle, emaSlowHandle, rsiHandle, spikeIntervalSec);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Release all indicator handles and clean up                       |
   //+------------------------------------------------------------------+
   void Deinit()
   {
      // Batch 117: Handles are owned by CIndicatorManager â€?do NOT release them
      // Just invalidate our references to prevent stale handle usage
      m_signal.InvalidateHandles(m_symbolCount);
      m_symbolCount = 0;

      PrintFormat("[ATR-SCALP-ENGINE] Deinitialized | trades=%d | skipped=%d | spikeBlocks=%d",
                  m_entry.TotalTradesOpened(), m_metrics.TotalTradesSkipped(), m_signal.TotalSpikeWindowBlocks());
   }

   //+------------------------------------------------------------------+
   //| Process a tick for a given symbol â€?call every tick               |
   //+------------------------------------------------------------------+
   void ProcessTick(const string symbol, double bid, double ask)
   {
      // 1. Find symbol index
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
         return;

      if(!m_symbolStates[idx].isActive)
         return;

      // 2. Update indicator values
      if(!UpdateIndicators(idx))
         return;

      // 3. Check spike window
      bool inSpikeWindow = IsInSpikeWindow(idx);

      // 4. Evaluate scalp signal
      int signal = EvaluateScalpSignal(idx);

      // 5. If signal and not in spike window, open trade
      if(signal != 0 && !inSpikeWindow)
      {
         // Check cooldown
         datetime now = TimeCurrent();
         if(m_symbolStates[idx].lastTradeTime > 0)
         {
            ulong elapsedMs = (ulong)((now - m_symbolStates[idx].lastTradeTime) * 1000);
            if(elapsedMs < (ulong)m_config.cooldownMs)
            {
               m_metrics.RecordTradeSkipped();
               // Still manage existing positions even if cooldown blocks new entry
               ManageScalpPositions(idx);
               return;
            }
         }

         // Check max positions
         if(GetActiveScalpPositions() >= m_config.maxPositions)
         {
            m_metrics.RecordTradeSkipped();
            ManageScalpPositions(idx);
            return;
         }

         OpenScalpTrade(idx, signal);
      }

      // 6. Manage existing scalp positions
      ManageScalpPositions(idx);
   }

   //+------------------------------------------------------------------+
   //| Called by SpikeHunter when a spike is detected                    |
   //| Updates lastSpikeTime for spike window calculation                |
   //+------------------------------------------------------------------+
   void NotifySpikeDetected(const string symbol)
   {
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
         return;

      m_symbolStates[idx].lastSpikeTime = TimeCurrent();
      PrintFormat("[ATR-SCALP] Spike detected for %s â€?updated lastSpikeTime", symbol);
   }

   //+------------------------------------------------------------------+
   //| Set expected spike interval for a symbol                          |
   //+------------------------------------------------------------------+
   void SetSpikeInterval(const string symbol, int intervalSec)
   {
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
      {
         PrintFormat("[ATR-SCALP] Cannot set spike interval â€?symbol %s not registered", symbol);
         return;
      }

      m_symbolStates[idx].expectedSpikeIntervalSec = intervalSec;
      PrintFormat("[ATR-SCALP] Spike interval set for %s: %ds", symbol, intervalSec);
   }

   //+------------------------------------------------------------------+
   //| Count positions with "ATR-SCALP" in comment                       |
   //+------------------------------------------------------------------+
   int GetActiveScalpPositions() const
   {
      return CATRScalpMetrics::GetActiveScalpPositions();
   }

   //+------------------------------------------------------------------+
   //| Print diagnostics                                                 |
   //+------------------------------------------------------------------+
   void PrintDiagnostics()
   {
      CATRScalpMetrics::PrintDiagnostics(m_symbolStates, m_symbolCount,
                                         m_entry.TotalTradesOpened(),
                                         m_metrics.TotalTradesSkipped(),
                                         m_signal.TotalSpikeWindowBlocks());
   }
};

#endif // CORE_SCALP_ATR_SCALPING_ENGINE_MQH
