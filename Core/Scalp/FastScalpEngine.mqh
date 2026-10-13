// Scalp pipeline that decides and sends outside consensus (no strategy vote), but every entry still passes CUnifiedRiskManager.
// This is the only scalp engine with a live driver: EAOrchestrator calls ProcessScalpFastPath from the tick path, throttled to 1 s;
// the ATR-scalp / spike-hunter / grid engines are parked and named by the init log [ENGINE-STATUS].
// Forwarder to the FastScalp* modules below (Types config, Indicators M1 ATR/EMA/RSI, Filters price/spread/burst/cost, Sizing
// lot+confidence, Signal fast/slow path, RiskBudget, PositionTracker, PendingOrders, AsyncTracker, Entry gates+send, Exit
// 1R partial/breakeven/trailing); Initialize, EvaluateScalpSignal and ShouldEnterScalp keep their own guards.
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

// Not used in this file: FastScalpFilters.mqh:17 declares its own extern and is the only scalp reader of it.
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

   CFastScalpIndicators      m_indicators;      // was m_cached{Symbol,BarTime,ATR,FastEMA,SlowEMA,RSI}
   CFastScalpRiskBudget      m_riskBudget;      // was m_usedScalpRiskPct
   CFastScalpPositionTracker m_posTracker;      // was m_scalpPositions[20] / m_scalpPositionCount
   CFastScalpPendingOrders   m_pendingBook;     // was m_pendingOrders[10] / m_pendingOrderCount / m_tradeObj
   CFastScalpAsyncTracker    m_asyncTracker;    // was m_pendingAsync[20] / m_pendingAsyncCount / m_asyncMode / m_maxLatencyMs

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

      // CTradeManager has no GetMagicNumber accessor: market orders get base magic + per-symbol offset inside it
      // (TradeManager.mqh:1267), while m_magicNumber is set from config by the orchestrator and reaches only the
      // pending/async paths. A 0% tier budget zeroes maxScalpPositions here, so PassesEntryGates refuses all.

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

   void SetMagicNumber(long magic) { m_magicNumber = magic; }

// With a cache attached, EvaluateScalpSignal reads indicator values from it instead of calling
// CopyBuffer, so the fast path does no indicator computation itself.
   void SetSignalCache(CScalpSignalCache* cache) { m_signalCache = cache; }

   void SetAsyncMode(bool enabled) { m_asyncTracker.SetAsyncMode(enabled); }

   void SetMaxLatencyMs(uint maxMs) { m_asyncTracker.SetMaxLatencyMs(maxMs); }

   int GetPendingAsyncCount() const { return m_asyncTracker.Count(); }

   bool IsInitialized() const { return m_initialized; }

// Gates (SScalpConfig defaults, overridable by the orchestrator): EMA 5/13 crossover on M1, M1 bar body
// > 0.80*ATR for a burst, spread > 0.30*ATR rejects, RSI(7) must not be at its OB/OS limits.
   ENUM_TRADE_SIGNAL EvaluateScalpSignal(string symbol)
   {
      if(!m_initialized)
         return TRADE_SIGNAL_NONE;

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

      // Slow path: RefreshIndicators does its own CopyBuffer reads. Reached from the same 1 s-throttled
      // tick driver (EAOrchestrator::ProcessScalpFastPath) whenever the cache has no valid entry — there
      // is no timer caller for this engine.
      return CFastScalpSignal::EvaluateSlowPath(symbol, m_config, m_indicators);
   }

// Gate order (each one is a hard refusal): cooldown since last entry (scalpCooldownMs, default 5000 ms) ->
// CountScalpPositions >= maxScalpPositions (default 3) -> used scalp risk >= scalpRiskPct (tier budget).
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

      bool momentumBurst = IsMomentumBurst(symbol);
      double atr = GetATRCached(symbol);
      confidence = CFastScalpSizing::CalculateConfidence(symbol, atr, momentumBurst);

      // Lot from CPositionSizer::CalculatePositionSize when it is initialised; otherwise the sizer is
      // bypassed and the lot falls back to SYMBOL_VOLUME_MIN (FastScalpSizing.mqh:72).
      lotSize = CFastScalpSizing::ResolveBaseLotSize(symbol, m_config, confidence, m_positionSizer);

      if(lotSize <= 0.0)
         return false;

      // Cost gate: spread + estimated round-trip commission (points) rejects when breakeven WR > 70% or cost >
      // 25% of TP; synthetics get 85% / 60%. Commission comes from the TICK_VALUE_PROFIT/_LOSS asymmetry.
      if(!IsScalpCostViable(symbol, (double)m_config.scalpSLPips, (double)m_config.scalpTPPips))
         return false;

      // Pre-trade gate #1 of two: ValidateTradeRequest(tag "scalp") here, then again inside
      // CFastScalpEntry::Execute (tag "scalp-pretrade") on the lot after any adjustment.
      if(!CFastScalpEntry::ValidateRiskAndAdjust(symbol, signal, confidence, lotSize,
                                                 m_config, m_riskManager))
         return false;

      return CFastScalpEntry::FinalizeLotSize(symbol, lotSize);
   }

   bool ExecuteScalpTrade(string symbol, ENUM_TRADE_SIGNAL signal,
                           double lotSize, double confidence)
   {
      return CFastScalpEntry::Execute(symbol, signal, lotSize, confidence,
                                      m_config, m_magicNumber,
                                      m_tradeManager, m_riskManager, m_aiAdapter,
                                      m_asyncTracker, m_posTracker, m_riskBudget,
                                      m_lastScalpTime);
   }

// No caller in this repo: the tick driver only sends market orders, so the BUY_LIMIT/SELL_LIMIT book
// stays empty even though usePendingOrders defaults to true and the init log prints pending=ON.
   bool PlaceScalpPendingOrder(string symbol, ENUM_TRADE_SIGNAL signal, double lotSize)
   {
      return m_pendingBook.Place(symbol, signal, lotSize, m_config, m_magicNumber, m_lastScalpTime);
   }

   void CheckPendingScalpOrders() { m_pendingBook.CheckExpired(m_config); }

   void RemovePendingOrder(int index) { m_pendingBook.RemovePendingOrder(index); }

// 1R partial close / breakeven / trailing. No throttle of its own — it runs once per ProcessScalpFastPath
// pass, and that driver is the thing limited to one call per second.
   void ManageScalpPositions()
   {
      if(!m_initialized || m_tradeManager == NULL)
         return;

      CFastScalpExit::ManageScalpPositions(m_posTracker, m_riskBudget,
                                           m_tradeManager, m_riskManager, m_config);
   }

// Counts every open position whose comment STARTS with "SCALP" (StringFind==0), terminal-wide and without
// a magic-number or symbol filter — this is the number the maxScalpPositions gate is compared against.
   int CountScalpPositions() { return CFastScalpPositionTracker::CountScalpPositions(); }

   bool IsScalpPosition(ulong ticket) { return CFastScalpPositionTracker::IsScalpPosition(ticket); }

// Adopts open SCALP positions the tracker lost (keyed by position ticket) and frees the risk budget of
// tracked tickets that no longer select a position.
   void SyncScalpPositionTracking()
   {
      CFastScalpExit::SyncScalpPositionTracking(m_posTracker, m_riskBudget, m_riskManager);
   }

// Dead wrappers, no caller in this repo: SetConfig, RemovePendingOrder, FreeScalpRiskBudget,
// RemovePendingAsync, IsScalpPosition, GetUsedScalpRiskPct, GetPendingOrderCount. The send path and the
// exit path use CFastScalpEntry / CFastScalpExit against the trackers directly instead of these.
   void FreeScalpRiskBudget(ulong ticket)
   {
      CFastScalpExit::FreeScalpRiskBudget(ticket, m_posTracker, m_riskBudget, m_riskManager);
   }

   void OnAsyncOrderSent(ulong orderTicket, string symbol, int direction,
                          double lotSize, double entryPrice, double sl, double tp)
   {
      m_asyncTracker.OnAsyncOrderSent(orderTicket, symbol, direction, lotSize, entryPrice, sl, tp);
   }

// Live: MultiStrategyAutonomousEA.mq5:1366 -> EAOrchestrator::ProcessScalpDealConfirmed -> here.
// Confirms an async deal into the position tracker; no-op when nothing is pending.
   void OnDealConfirmed(ulong dealTicket, ulong orderTicket)
   {
      m_asyncTracker.OnDealConfirmed(dealTicket, orderTicket, m_config, m_posTracker);
   }

// Live from ProcessScalpFastPath (tick path, 1 s throttle): expires async entries unconfirmed for
// > 3x scalpMaxLatencyMs and releases budget through ReleaseFallback, which is not keyed to a ticket.
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
