// Dedicated scalping pipeline bypassing full consensus engine
// Single-strategy-allowed signals, tight stops, tick-level mgmt
// CFastScalpEngine is a thin coordinator: every public method is a signature-identical forwarder into a focused FastScalp* module — no behaviour, threshold or log tag changed.
// FastScalpTypes.mqh            SScalpConfig + tracking structs
// FastScalpIndicators.mqh       M1 ATR/EMA/RSI cache (stateful)
// FastScalpFilters.mqh          price/spread/burst/cost gates
// FastScalpSizing.mqh           lot sizing + confidence score
// FastScalpSignal.mqh           cached fast path + slow path
// FastScalpRiskBudget.mqh       scalp risk budget (stateful)
// FastScalpPositionTracker.mqh  scalp position registry (stateful)
// FastScalpPendingOrders.mqh    pending limit orders (stateful)
// FastScalpAsyncTracker.mqh     OrderSendAsync tracking (stateful)
// FastScalpEntry.mqh            entry gating + trade execution
// FastScalpExit.mqh             1R partial / breakeven / trailing
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_FAST_SCALP_ENGINE_MQH
#define CORE_SCALP_FAST_SCALP_ENGINE_MQH

#include "../Utils/Enums.mqh"
#include "../Trading/TradeManager.mqh"
#include "../Trading/TradeTypes.mqh"
#include "../Risk/UnifiedRiskManager.mqh"
#include "../Risk/PositionSizer.mqh"
#include "../Risk/RiskTierManager.mqh"
#include "../../IndicatorManager.mqh"

// Forward declaration for global profiler access (initialized in EAOrchestrator)
class CMultiAssetProfiler;
extern CMultiAssetProfiler* g_multiAssetProfiler;

class CAIAdapter;

#include "ScalpSignalCache.mqh"

#include "FastScalpTypes.mqh"
#include "FastScalpIndicators.mqh"
#include "FastScalpFilters.mqh"
#include "FastScalpSizing.mqh"
#include "FastScalpSignal.mqh"
#include "FastScalpRiskBudget.mqh"
#include "FastScalpPositionTracker.mqh"
#include "FastScalpPendingOrders.mqh"
#include "FastScalpAsyncTracker.mqh"
#include "FastScalpExit.mqh"
#include "FastScalpEntry.mqh"

class CFastScalpEngine
{
private:
   SScalpConfig              m_config;
   CTradeManager*            m_tradeManager;
   CUnifiedRiskManager*      m_riskManager;
   CPositionSizer*           m_positionSizer;
   CRiskTierManager*         m_riskTierManager;
   CScalpSignalCache*        m_signalCache;          // External cache reference (optional)
   CAIAdapter*               m_aiAdapter;            // L10-018: AI adapter for AI-VOTE logging

   datetime                  m_lastScalpTime;        // Last scalp entry time
   long                      m_magicNumber;          // EA magic number for pending orders — Batch 125: changed from uint to long
   bool                      m_initialized;

   //--- Extracted state owners (held BY VALUE)
   CFastScalpIndicators      m_indicators;      // was m_cached{Symbol,BarTime,ATR,FastEMA,SlowEMA,RSI}
   CFastScalpRiskBudget      m_riskBudget;      // was m_usedScalpRiskPct
   CFastScalpPositionTracker m_posTracker;      // was m_scalpPositions[20] / m_scalpPositionCount
   CFastScalpPendingOrders   m_pendingBook;     // was m_pendingOrders[10] / m_pendingOrderCount / m_tradeObj
   CFastScalpAsyncTracker    m_asyncTracker;    // was m_pendingAsync[20] / m_pendingAsyncCount / m_asyncMode / m_maxLatencyMs

   //--- Private forwarders (signatures preserved 1:1 from the original)
   bool RefreshIndicators(string symbol)
   { return m_indicators.RefreshIndicators(symbol, m_config); }

   bool RefreshScalpPrice(string symbol, double &ask, double &bid)
   { return CFastScalpFilters::RefreshScalpPrice(symbol, ask, bid); }

   double GetATRCached(string symbol)
   { return m_indicators.GetATRCached(symbol, m_config); }

   bool GetEMACrossover(string symbol, ENUM_TRADE_SIGNAL &signal)
   { return CFastScalpIndicators::GetEMACrossover(symbol, m_config, signal); }

   bool IsMomentumBurst(string symbol)
   { return CFastScalpFilters::IsMomentumBurst(symbol, GetATRCached(symbol), m_config.momentumBurstATRRatio); }

   bool IsSpreadAcceptable(string symbol)
   { return CFastScalpFilters::IsSpreadAcceptable(symbol, GetATRCached(symbol), m_config.maxSpreadATRRatio); }

   bool IsSyntheticSymbol(const string symbol)
   { return CFastScalpFilters::IsSyntheticSymbol(symbol); }

   bool IsScalpCostViable(const string symbol, double slPoints, double tpPoints)
   { return CFastScalpFilters::IsScalpCostViable(symbol, slPoints, tpPoints); }

   bool IsRSIConfirmed(ENUM_TRADE_SIGNAL signal)
   { return m_indicators.IsRSIConfirmed(signal, m_config); }

   double CapLotToMargin(double calculatedLot, string symbol)
   { return CFastScalpSizing::CapLotToMargin(calculatedLot, symbol); }

   void RegisterScalpPosition(ulong ticket, string symbol, double entryPrice,
                               double sl, double tp, double oneRPrice)
   { m_posTracker.RegisterScalpPosition(ticket, symbol, entryPrice, sl, tp, oneRPrice); }

   void RemoveScalpPosition(ulong ticket)
   { m_posTracker.RemoveScalpPosition(ticket); }

   int FindScalpPositionState(ulong ticket)
   { return m_posTracker.FindScalpPositionState(ticket); }

public:
// Scalar members keep their original initialisers; the extracted
// state objects reproduce the rest in their own constructors.
   CFastScalpEngine() :
      m_tradeManager(NULL),
      m_riskManager(NULL),
      m_positionSizer(NULL),
      m_riskTierManager(NULL),
      m_signalCache(NULL),
      m_aiAdapter(NULL),            // L10-018: AI adapter
      m_lastScalpTime(0),
      m_magicNumber(123456),
      m_initialized(false)
   {
   }

   ~CFastScalpEngine()
   {
      // Cancel any remaining pending orders
      m_pendingBook.CancelAllOnShutdown();
      m_posTracker.Reset();
   }

   bool Initialize(CTradeManager* scalpTradeMgr,
                   CUnifiedRiskManager* riskManager,
                   CPositionSizer* scalpPosSizer,
                   CRiskTierManager* riskTierManager,
                   CAIAdapter* aiAdapter = NULL)  // L10-018: AI adapter
   {
      if(scalpTradeMgr == NULL || riskManager == NULL ||
         scalpPosSizer == NULL || riskTierManager == NULL)
      {
         Print("[SCALP-ENGINE] ERROR: NULL dependency passed to Initialize");
         return false;
      }

      m_tradeManager    = scalpTradeMgr;
      m_riskManager     = riskManager;
      m_positionSizer   = scalpPosSizer;
      m_riskTierManager = riskTierManager;
      m_aiAdapter       = aiAdapter;  // L10-018: Store AI adapter

      // Note: CTradeManager doesn't expose GetMagicNumber, so we use the default
      // The market order path goes through CTradeManager which sets magic internally

      m_config.scalpRiskPct = m_riskTierManager.GetScalpBudgetPct();
      if(m_config.scalpRiskPct <= 0.0)
      {
         Print("[SCALP-ENGINE] Scalp budget is 0% — scalp engine will not trade");
         m_config.maxScalpPositions = 0;
      }

      m_initialized = true;
      PrintFormat("[SCALP-ENGINE] Initialized | maxPos=%d | risk=%.1f%% | SL=%d | TP=%d | cooldown=%dms | pending=%s | partial=%s",
                  m_config.maxScalpPositions,
                  m_config.scalpRiskPct,
                  m_config.scalpSLPips,
                  m_config.scalpTPPips,
                  m_config.scalpCooldownMs,
                  m_config.usePendingOrders ? "ON" : "OFF",
                  m_config.partialCloseEnabled ? "ON" : "OFF");
      return true;
   }

   void SetConfig(SScalpConfig &config)
   {
      m_config = config;
      PrintFormat("[SCALP-ENGINE] Config updated | maxPos=%d | risk=%.1f%% | SL=%d | TP=%d",
                  m_config.maxScalpPositions, m_config.scalpRiskPct,
                  m_config.scalpSLPips, m_config.scalpTPPips);
   }

   SScalpConfig GetConfig() const { return m_config; }

// Set magic number for pending orders
   void SetMagicNumber(long magic) { m_magicNumber = magic; }

// When set, EvaluateScalpSignal reads from cache instead of
// calling CopyBuffer — zero indicator computation in fast path
   void SetSignalCache(CScalpSignalCache* cache) { m_signalCache = cache; }

   void SetAsyncMode(bool enabled) { m_asyncTracker.SetAsyncMode(enabled); }

// Set max acceptable latency for async order confirmation
   void SetMaxLatencyMs(uint maxMs) { m_asyncTracker.SetMaxLatencyMs(maxMs); }

   int GetPendingAsyncCount() const { return m_asyncTracker.Count(); }

   bool IsInitialized() const { return m_initialized; }

// Micro-trend: EMA5/EMA13 crossover on M1
// Momentum burst: bar body > 0.8 * ATR
// RSI confirmation: not overbought/oversold
// Spread gate: reject if spread > 30% of ATR
   ENUM_TRADE_SIGNAL EvaluateScalpSignal(string symbol)
   {
      if(!m_initialized)
         return TRADE_SIGNAL_NONE;

      // Try fast-path: read from signal cache (zero CopyBuffer)
      if(m_signalCache != NULL)
      {
         SScalpIndicatorCache cache;
         if(m_signalCache.GetCache(symbol, cache) && cache.isValid)
         {
            ENUM_TRADE_SIGNAL cachedSignal =
               CFastScalpSignal::EvaluateFromCache(symbol, m_config, cache);

            if(cachedSignal == TRADE_SIGNAL_NONE)
               return TRADE_SIGNAL_NONE;

            // Cache the indicator values for ShouldEnterScalp's confidence calculation
            m_indicators.SetCachedValues(symbol, cache.lastBarTime, cache.atrValue,
                                         cache.emaFast, cache.emaSlow, cache.rsiValue);

            return cachedSignal;
         }
      }

      // Fallback: existing RefreshIndicators path (slow path / timer path)
      return CFastScalpSignal::EvaluateSlowPath(symbol, m_config, m_indicators);
   }

// Checks: cooldown, max positions, scalp risk budget, signal, lots
   bool ShouldEnterScalp(string symbol, ENUM_TRADE_SIGNAL &signal,
                          double &confidence, double &lotSize)
   {
      signal     = TRADE_SIGNAL_NONE;
      confidence = 0.0;
      lotSize    = 0.0;

      if(!m_initialized)
         return false;

      if(!CFastScalpEntry::PassesEntryGates(m_config, m_lastScalpTime, m_riskBudget.Get()))
         return false;

      signal = EvaluateScalpSignal(symbol);
      if(signal == TRADE_SIGNAL_NONE)
         return false;

      // Calculate confidence — burst is resolved first, exactly as before,
      // so the indicator refresh sequence is unchanged.
      bool momentumBurst = IsMomentumBurst(symbol);
      double atr = GetATRCached(symbol);
      confidence = CFastScalpSizing::CalculateConfidence(symbol, atr, momentumBurst);

      // Calculate lot size using CPositionSizer (min-lot fallback inside)
      lotSize = CFastScalpSizing::ResolveBaseLotSize(symbol, m_config, confidence, m_positionSizer);

      if(lotSize <= 0.0)
         return false;

      // Commission-aware cost validation: reject if total cost (spread + commission)
      // makes the scalp unviable (breakeven WR > 70% or cost > 25% of TP)
      if(!IsScalpCostViable(symbol, (double)m_config.scalpSLPips, (double)m_config.scalpTPPips))
         return false;

      // Risk validation through CUnifiedRiskManager
      if(!CFastScalpEntry::ValidateRiskAndAdjust(symbol, signal, confidence, lotSize,
                                                 m_config, m_riskManager))
         return false;

      // Margin cap + symbol minimum lot check
      return CFastScalpEntry::FinalizeLotSize(symbol, lotSize);
   }

// Supports both synchronous and async execution modes
   bool ExecuteScalpTrade(string symbol, ENUM_TRADE_SIGNAL signal,
                           double lotSize, double confidence)
   {
      return CFastScalpEntry::Execute(symbol, signal, lotSize, confidence,
                                      m_config, m_magicNumber,
                                      m_tradeManager, m_riskManager, m_aiAdapter,
                                      m_asyncTracker, m_posTracker, m_riskBudget,
                                      m_lastScalpTime);
   }

// Place a scalp pending order (BUY_LIMIT/SELL_LIMIT)
   bool PlaceScalpPendingOrder(string symbol, ENUM_TRADE_SIGNAL signal, double lotSize)
   {
      return m_pendingBook.Place(symbol, signal, lotSize, m_config, m_magicNumber, m_lastScalpTime);
   }

// Check and manage pending scalp orders (cancel expired)
   void CheckPendingScalpOrders() { m_pendingBook.CheckExpired(m_config); }

   void RemovePendingOrder(int index) { m_pendingBook.RemovePendingOrder(index); }

// Quick profit lock, tight trailing, partial close
// NOT throttled to 1 second like swing trailing
   void ManageScalpPositions()
   {
      if(!m_initialized || m_tradeManager == NULL)
         return;

      CFastScalpExit::ManageScalpPositions(m_posTracker, m_riskBudget,
                                           m_tradeManager, m_riskManager, m_config);
   }

// Count positions with "SCALP" in comment
   int CountScalpPositions() { return CFastScalpPositionTracker::CountScalpPositions(); }

   bool IsScalpPosition(ulong ticket) { return CFastScalpPositionTracker::IsScalpPosition(ticket); }

// Sync tracked scalp positions with actual open positions
   void SyncScalpPositionTracking()
   {
      CFastScalpExit::SyncScalpPositionTracking(m_posTracker, m_riskBudget, m_riskManager);
   }

// Free the scalp risk budget consumed by a ticket
   void FreeScalpRiskBudget(ulong ticket)
   {
      CFastScalpExit::FreeScalpRiskBudget(ticket, m_posTracker, m_riskBudget, m_riskManager);
   }

// Track a pending async order after OrderSendAsync
   void OnAsyncOrderSent(ulong orderTicket, string symbol, int direction,
                          double lotSize, double entryPrice, double sl, double tp)
   {
      m_asyncTracker.OnAsyncOrderSent(orderTicket, symbol, direction, lotSize, entryPrice, sl, tp);
   }

// Handle deal confirmation for async scalp orders
// Called from OnTradeTransaction when a deal matches a pending order
   void OnDealConfirmed(ulong dealTicket, ulong orderTicket)
   {
      m_asyncTracker.OnDealConfirmed(dealTicket, orderTicket, m_config, m_posTracker);
   }

// Check pending async orders for expiration
// Called from OnTick to detect stale unconfirmed orders
   void CheckPendingAsyncOrders()
   {
      m_asyncTracker.CheckPendingAsyncOrders(m_riskBudget, m_riskManager);
   }

   void RemovePendingAsync(int index) { m_asyncTracker.RemovePendingAsync(index); }

   void PrintDiagnostics()
   {
      PrintFormat("[SCALP-DIAG] initialized=%s | maxPos=%d | currentPos=%d | riskUsed=%.1f/%.1f%% | pending=%d | tracked=%d | async=%s | pendingAsync=%d",
                  m_initialized ? "true" : "false",
                  m_config.maxScalpPositions,
                  CountScalpPositions(),
                  m_riskBudget.Get(),
                  m_config.scalpRiskPct,
                  m_pendingBook.Count(),
                  m_posTracker.Count(),
                  m_asyncTracker.IsAsyncMode() ? "ON" : "OFF",
                  m_asyncTracker.Count());
   }

   double GetUsedScalpRiskPct() const { return m_riskBudget.Get(); }

   int GetPendingOrderCount() const { return m_pendingBook.Count(); }
};

#endif // CORE_SCALP_FAST_SCALP_ENGINE_MQH
