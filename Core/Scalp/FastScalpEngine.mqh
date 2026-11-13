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

// Seconds one symbol waits before it may be scalped again. The EMA 5/13 state on M1 stays crossed for
// minutes, so without this the same crossover re-fired every engine cooldown (5 s): the 2026-11-13
// demo journal shows ten XAUUSD SELLs between 14:21:00 and 14:23:32 off two crossovers.
#define SCALP_SYMBOL_REENTRY_SECONDS 180

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
   long                      m_magicNumber;          // EA magic number for pending orders �?Batch 125: changed from uint to long
   bool                      m_initialized;

   string                    m_refusalLogSymbols[];   // per-symbol refusal-log throttle
   datetime                  m_refusalLogTimes[];

   string                    m_entrySymbols[];        // per-symbol time of the last scalp entry
   datetime                  m_entryTimes[];
   SScalpConfig              m_entryConfig;           // geometry ShouldEnterScalp priced the candidate on
   string                    m_entryConfigSymbol;     // symbol that geometry belongs to

   datetime LastEntryTime(const string symbol)
   {
      for(int i = 0; i < ArraySize(m_entrySymbols); i++)
         if(m_entrySymbols[i] == symbol)
            return m_entryTimes[i];
      return 0;
   }

   void StampEntry(const string symbol)
   {
      datetime now = TimeCurrent();
      for(int i = 0; i < ArraySize(m_entrySymbols); i++)
      {
         if(m_entrySymbols[i] == symbol)
         {
            m_entryTimes[i] = now;
            return;
         }
      }
      int n = ArraySize(m_entrySymbols);
      if(ArrayResize(m_entrySymbols, n + 1) != n + 1 || ArrayResize(m_entryTimes, n + 1) != n + 1)
         return;
      m_entrySymbols[n] = symbol;
      m_entryTimes[n] = now;
   }

// Open positions on `symbol` whose comment starts with "SCALP" (same ownership test as CountScalpPositions).
   int CountScalpPositionsOnSymbol(const string symbol)
   {
      int count = 0;
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0 || !PositionSelectByTicket(ticket))
            continue;
         if(PositionGetString(POSITION_SYMBOL) != symbol)
            continue;
         if(StringFind(PositionGetString(POSITION_COMMENT), "SCALP") == 0)
            count++;
      }
      return count;
   }

// Per-symbol stop and target, in points. The configured scalpSLPips/scalpTPPips (60/90) were applied
// as raw points to every symbol, and a point is not a unit of risk: 60 points is 6.0 on Step Index,
// 0.60 on XAUUSD (inside three spreads) and 4% of one spread on Volatility 75 Index. That is why the
// cost gate refused every symbol but two ("spread=1431.0 ... tp=90.0 breakevenWR=0.941") and why the
// engine only ever traded Step Index and XAUUSD. The stop is now the largest of 1.5 x ATR(14, M1),
// 4 x spread and 1.5 x the broker stop level; the target keeps the configured TP:SL ratio; the
// breakeven and trailing distances are fractions of that stop instead of 10/5/15 raw points.
// Returns false when the symbol has no ATR or point yet - the caller refuses the entry.
   bool BuildSymbolConfig(const string symbol, const double atr, SScalpConfig &cfg)
   {
      cfg = m_config;
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0 || atr <= 0.0)
         return false;

      double spreadPts = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      double stopLevelPts = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double rr = (m_config.scalpSLPips > 0) ? ((double)m_config.scalpTPPips / (double)m_config.scalpSLPips) : 1.5;
      if(rr < 1.0)
         rr = 1.0;

      double slPts = MathMax(1.5 * atr / point, MathMax(4.0 * spreadPts, 1.5 * stopLevelPts));
      slPts = MathCeil(slPts);
      if(slPts < 1.0 || slPts > 2000000000.0 / (rr + 1.0))
         return false;

      cfg.scalpSLPips            = (int)slPts;
      cfg.scalpTPPips            = (int)MathCeil(slPts * rr);
      cfg.breakevenProfitPoints  = (int)MathMax(1.0, MathRound(0.60 * slPts));
      cfg.breakevenBufferPoints  = (int)MathMax(1.0, MathRound(0.10 * slPts));
      cfg.trailingDistancePoints = (int)MathMax(1.0, MathRound(0.60 * slPts));
      return true;
   }

// True once per `seconds` per symbol. A single static slot would let the first symbol refused in the
// window mute the other twelve and print a cooldown that belongs to whoever spoke first.
   bool RefusalLogDue(const string symbol, const int seconds)
   {
      datetime now = TimeCurrent();
      for(int i = 0; i < ArraySize(m_refusalLogSymbols); i++)
      {
         if(m_refusalLogSymbols[i] != symbol)
            continue;
         if(now - m_refusalLogTimes[i] < seconds)
            return false;
         m_refusalLogTimes[i] = now;
         return true;
      }
      int n = ArraySize(m_refusalLogSymbols);
      if(ArrayResize(m_refusalLogSymbols, n + 1) != n + 1 || ArrayResize(m_refusalLogTimes, n + 1) != n + 1)
         return false;
      m_refusalLogSymbols[n] = symbol;
      m_refusalLogTimes[n] = now;
      return true;
   }

   CFastScalpIndicators      m_indicators;      // one slot: symbol tag + bar time + ATR + RSI
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
      m_initialized(false),
      m_entryConfigSymbol("")
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
      // pending/async paths. The tier budget is re-read in ShouldEnterScalp, so a 0% tier at init is not a latch.

      m_config.scalpRiskPct = m_riskTierManager.GetScalpBudgetPct();
      if(m_config.scalpRiskPct <= 0.0)
         Print("[SCALP-ENGINE] Scalp budget is 0% at init - entries refused until the tier raises it (re-read every cycle)");

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
   ENUM_TRADE_SIGNAL EvaluateScalpSignal(string symbol, string &gateReject)
   {
      gateReject = "";
      if(!m_initialized)
         return TRADE_SIGNAL_NONE;

      if(m_signalCache != NULL)
      {
         SScalpIndicatorCache cache;
         if(m_signalCache.GetCache(symbol, cache) && cache.isValid)
         {
            ENUM_TRADE_SIGNAL cachedSignal =
               CFastScalpSignal::EvaluateFromCache(symbol, m_config, cache, gateReject);

            if(cachedSignal == TRADE_SIGNAL_NONE)
               return TRADE_SIGNAL_NONE;

            // Cache the indicator values for ShouldEnterScalp's confidence calculation
            m_indicators.SetCachedValues(symbol, cache.lastBarTime, cache.atrValue, cache.rsiValue);

            return cachedSignal;
         }
      }

      // Slow path: RefreshIndicators does its own CopyBuffer reads. Reached from the same 1 s-throttled
      // tick driver (EAOrchestrator::ProcessScalpFastPath) whenever the cache has no valid entry �?there
      // is no timer caller for this engine.
      return CFastScalpSignal::EvaluateSlowPath(symbol, m_config, m_indicators, gateReject);
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

      // The tier can move the scalp budget after init, so it is re-read here rather than latched there.
      if(m_riskTierManager != NULL)
         m_config.scalpRiskPct = m_riskTierManager.GetScalpBudgetPct();

      if(!CFastScalpEntry::PassesEntryGates(m_config, m_lastScalpTime, m_riskBudget.Get()))
      {
         if(RefusalLogDue(symbol, 60))
            PrintFormat("[SCALP-GATE] %s | entry refused | usedRisk=%.2f%% of budget=%.2f%% | maxPos=%d | cooldownLeftMs=%d",
                        symbol, m_riskBudget.Get(), m_config.scalpRiskPct, m_config.maxScalpPositions,
                        m_lastScalpTime > 0 ? (m_config.scalpCooldownMs - (int)((TimeCurrent() - m_lastScalpTime) * 1000)) : 0);
         return false;
      }

      // One scalp per symbol at a time, and a symbol rests after an entry. Both are entry holds only.
      datetime lastSymbolEntry = LastEntryTime(symbol);
      if(lastSymbolEntry > 0 && (TimeCurrent() - lastSymbolEntry) < SCALP_SYMBOL_REENTRY_SECONDS)
         return false;
      if(CountScalpPositionsOnSymbol(symbol) > 0)
         return false;

      string gateReject = "";
      signal = EvaluateScalpSignal(symbol, gateReject);
      if(signal == TRADE_SIGNAL_NONE)
      {
         if(gateReject != "" && RefusalLogDue(symbol, 60))
            PrintFormat("[SCALP-SIGNAL-REJECT] %s | gate=%s", symbol, gateReject);
         return false;
      }

      bool momentumBurst = IsMomentumBurst(symbol);
      double atr = GetATRCached(symbol);
      confidence = CFastScalpSizing::CalculateConfidence(symbol, atr, momentumBurst);

      // Stop/target for THIS symbol; everything below (sizing, cost, risk gate, send) prices on it.
      SScalpConfig cfg;
      if(!BuildSymbolConfig(symbol, atr, cfg))
      {
         if(RefusalLogDue(symbol, 60))
            PrintFormat("[SCALP-SIGNAL-REJECT] %s | gate=no_atr_or_point", symbol);
         return false;
      }
      m_entryConfig = cfg;
      m_entryConfigSymbol = symbol;

      // Lot from CPositionSizer::CalculatePositionSize when it is initialised; otherwise the sizer is
      // bypassed and the lot falls back to SYMBOL_VOLUME_MIN.
      lotSize = CFastScalpSizing::ResolveBaseLotSize(symbol, cfg, confidence, m_positionSizer);

      if(lotSize <= 0.0)
      {
         if(RefusalLogDue(symbol, 60))
            PrintFormat("[SCALP-SIZING] %s | sizer returned lot %.4f | signal refused before the risk gate",
                        symbol, lotSize);
         return false;
      }

      // Cost gate: spread + estimated round-trip commission (points) rejects when breakeven WR > 70% or cost >
      // 25% of TP; synthetics get 85% / 60%. Commission comes from the TICK_VALUE_PROFIT/_LOSS asymmetry.
      if(!IsScalpCostViable(symbol, (double)cfg.scalpSLPips, (double)cfg.scalpTPPips))
         return false;

      // The scalp path's only pre-trade gate; Execute validates the same lot it would have a second
      // time, and each approval reserves a virtual position until its TTL prunes it.
      if(!CFastScalpEntry::ValidateRiskAndAdjust(symbol, signal, confidence, lotSize,
                                                 cfg, m_riskManager))
         return false;

      return CFastScalpEntry::FinalizeLotSize(symbol, lotSize);
   }

   bool ExecuteScalpTrade(string symbol, ENUM_TRADE_SIGNAL signal,
                           double lotSize, double confidence)
   {
      // The geometry the risk gate approved. A caller that skipped ShouldEnterScalp for this symbol
      // has no priced geometry, and a scalp must not ship on the engine-wide raw-point default.
      if(m_entryConfigSymbol != symbol || m_entryConfig.scalpSLPips <= 0)
      {
         PrintFormat("[SCALP-REJECTED] %s | reason=no priced stop for this symbol (ShouldEnterScalp did not approve it)", symbol);
         return false;
      }

      bool sent = CFastScalpEntry::Execute(symbol, signal, lotSize, confidence,
                                           m_entryConfig, m_magicNumber,
                                           m_tradeManager, m_riskManager, m_aiAdapter,
                                           m_asyncTracker, m_posTracker, m_riskBudget,
                                           m_lastScalpTime);
      if(sent)
         StampEntry(symbol);
      m_entryConfigSymbol = "";
      return sent;
   }

// No caller in this repo: the tick driver only sends market orders, so the BUY_LIMIT/SELL_LIMIT book
// stays empty even though usePendingOrders defaults to true and the init log prints pending=ON.
   bool PlaceScalpPendingOrder(string symbol, ENUM_TRADE_SIGNAL signal, double lotSize)
   {
      return m_pendingBook.Place(symbol, signal, lotSize, m_config, m_magicNumber, m_lastScalpTime);
   }

   void CheckPendingScalpOrders() { m_pendingBook.CheckExpired(m_config); }

   void RemovePendingOrder(int index) { m_pendingBook.RemovePendingOrder(index); }

// 1R partial close / breakeven / trailing. No throttle of its own �?it runs once per ProcessScalpFastPath
// pass, and that driver is the thing limited to one call per second.
   void ManageScalpPositions()
   {
      if(!m_initialized || m_tradeManager == NULL)
         return;

      CFastScalpExit::ManageScalpPositions(m_posTracker, m_riskBudget,
                                           m_tradeManager, m_riskManager, m_config);
   }

// Counts every open position whose comment STARTS with "SCALP" (StringFind==0), terminal-wide and without
// a magic-number or symbol filter �?this is the number the maxScalpPositions gate is compared against.
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
// > 3x scalpMaxLatencyMs. Timed-out orders with no broker state are quarantined in the
// reserved-budget ledger (budget stays reserved); budget is released only on a final
// zero-fill outcome by the ledger re-check.
   void CheckPendingAsyncOrders()
   {
      m_asyncTracker.CheckPendingAsyncOrders(m_riskBudget, m_riskManager, m_config, m_posTracker);
   }

   void RemovePendingAsync(int index) { m_asyncTracker.RemovePendingAsync(index); }

   void PrintDiagnostics()
   {
      PrintFormat("[SCALP-DIAG] initialized=%s | maxPos=%d | currentPos=%d | riskUsed=%.1f/%.1f%% | pending=%d | tracked=%d | async=%s | pendingAsync=%d | reservedLedger=%d",
                  m_initialized ? "true" : "false",
                  m_config.maxScalpPositions,
                  CountScalpPositions(),
                  m_riskBudget.Get(),
                  m_config.scalpRiskPct,
                  m_pendingBook.Count(),
                  m_posTracker.Count(),
                  m_asyncTracker.IsAsyncMode() ? "ON" : "OFF",
                  m_asyncTracker.Count(),
                  m_asyncTracker.GetReservedLedgerCount());
   }

   double GetUsedScalpRiskPct() const { return m_riskBudget.Get(); }

   int GetPendingOrderCount() const { return m_pendingBook.Count(); }
};

#endif // CORE_SCALP_FAST_SCALP_ENGINE_MQH

