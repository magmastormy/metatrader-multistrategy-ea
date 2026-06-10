# EA Complete Overhaul: High-Performance Transformation Blueprint

**Document Version**: 1.0  
**Date**: 2026-06-10  
**Scope**: Full-system overhaul — execution speed, money management, risk controls, scalping engine, strategy redesign  
**Status**: Actionable specification for implementation  

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current System Diagnosis](#2-current-system-diagnosis)
3. [Execution Speed Overhaul](#3-execution-speed-overhaul)
4. [Money Management Redesign](#4-money-management-redesign)
5. [Risk Control Fortress](#5-risk-control-fortress)
6. [Fast Scalping Engine](#6-fast-scalping-engine)
7. [Strategy Enhancement Program](#7-strategy-enhancement-program)
8. [Full-Margin Aggressive Mode](#8-full-margin-aggressive-mode)
9. [Safe Trading Mode](#9-safe-trading-mode)
10. [Architecture Refactoring](#10-architecture-refactoring)
11. [Implementation Roadmap](#11-implementation-roadmap)

---

## 1. Executive Summary

This EA is architecturally sophisticated but operationally crippled. The system has **10 strategy implementations** (3 disabled at input level, 3 not even registered), a **7-step risk validation pipeline**, a **weighted consensus voting engine**, and an **AI integration layer** — yet it runs slow, loses money, and cannot scalp effectively.

The root causes are not a lack of features but an **excess of poorly integrated features**:

- **3 independent drawdown monitors** with conflicting thresholds
- **3 different correlation calculators** producing inconsistent results
- **Signal Reversal Exit runs full consensus on every tick per position** — the single most expensive operation in the hot path
- **No pending order support** — market-order-only execution in a scalping context
- **Aggressive default risk parameters** (10% per trade, 30% daily, 50% portfolio) that invite catastrophic drawdown
- **3 sophisticated strategies (ICT, Unicorn, Power of Three) disabled** while the active strategies are the weakest
- **No dedicated scalping pipeline** — all strategies route through a bar-based consensus system designed for swing trading
- **Indicator handle leaks** in ICT strategy and inline handle creation in Momentum/Trend strategies

This document provides a complete transformation blueprint organized into **8 workstreams**, each with specific code-level changes, expected impact, and implementation priority.

---

## 2. Current System Diagnosis

### 2.1 Performance Bottleneck Map

| Bottleneck | Location | Impact | Severity |
|---|---|---|---|
| SRE runs full consensus per position per tick | `ManageOpenPositionsIfNeeded()` → `GetConsensusSignalForSymbolWithConfluenceMode()` | With 3+ positions, 3+ full consensus evaluations per tick. Each consensus iterates all strategies + pipeline + quorum. **Dominant hot-path cost.** | CRITICAL |
| Double ATR fetch per order | `ValidateExecutionPreflight()` + `UpdateDynamicSlippage()` | Two separate `CopyBuffer` calls for the same ATR value per execution attempt | HIGH |
| Blocking Sleep in execution confirmation | `ConfirmExecutionReceipt()` → `Sleep(150ms)` x3 | Up to 300ms blocking sleep in worst case, stalls entire EA thread | HIGH |
| NN online learning in main loop | `TickOnlineLearning()` every `ProcessTradingLogic` call | Neural net training on every cycle, not just new bars | MEDIUM |
| Linear search in indicator/handle lookup | `CIndicatorManager::FindHandle()`, `CStrategyRegistry::FindIndexByName()` | O(n) scans over 500 handles, 150 strategies | MEDIUM |
| ICT strategy volume handle leak | `StrategyUnifiedICT.mqh` line 944 | Creates new `iVolumes` handle every evaluation, never released | MEDIUM |
| Inline indicator handle creation | `SimpleMomentumStrategy.mqh` line 530, `StrategyTrend.mqh` `GetTradeParameters()` | Creates temporary `iATR` handles per call instead of caching | MEDIUM |
| Heartbeat logging volume | 8+ `PrintFormat` calls every 10-60s with complex string formatting | Heap allocation per format, saturates journal on fast synthetics | LOW-MEDIUM |
| Virtual position book rebuilt every cycle | `ClearVirtualPositions()` + reserve + clear | Array resizing per scan cycle | LOW |
| Bubble sort for candidates | `SortApprovedTradeCandidatesByRank()` | O(n²) on typically small arrays — negligible but sloppy | LOW |

### 2.2 Risk Model Failures

| Issue | Detail | Consequence |
|---|---|---|
| Three conflicting drawdown systems | `CUnifiedRiskManager` (6%/12% from peak), `CRiskValidationGate` (10% from balance), `CICTPositionSizer` (3% daily/6% weekly from balance) | ICT sizer blocks at 3% while unified manager allows trading to 12%. No single source of truth. |
| Inconsistent risk denominator | `CPositionSizer` uses `min(balance, equity)`, `CICTPositionSizer` uses `balance` only | ICT sizer calculates larger lots during drawdown than unified risk expects |
| Three correlation implementations | Unified: same-direction count (underestimates), Gate: Pearson 20-period, Portfolio: Pearson 30-period | Unified manager allows correlated positions that other systems would block |
| No margin-level-aware sizing | Sizer uses 80%/90% free margin heuristic; Gate uses 200% margin level check | Position can pass one check and fail the other |
| Virtual position book never expires | Reservations have timestamps but no expiry | Crashed strategy permanently reduces daily risk budget |
| Circuit breaker requires manual reset | Critical DD disables trading forever until operator intervenes | EA can stay permanently disabled unattended |
| Aggressive defaults | 10% per trade, 30% daily, 50% portfolio, 20% hard ceiling | Professional traders use 0.5-2% per trade. Current defaults invite blowup |
| No per-symbol risk budgeting | Single global daily/portfolio budget | One volatile symbol consumes entire risk budget, blocks all others |

### 2.3 Strategy Effectiveness Assessment

| Strategy | Status | Signal Freq | Min Confidence | Verdict |
|---|---|---|---|---|
| Momentum | Active | Low (crossover-dependent) | 0.30 | Weak — simple EMA cross is insufficient for synthetics |
| Trend | Active | Low-Medium | 0.55 | Moderate — 4 entry types but slow (bar-based, HTF confirmation) |
| Support/Resistance | Active | Medium | 0.45 | Moderate — Fibonacci confluence is stubbed (TODO) |
| Candlestick | Active | Low | 0.60 | Weak — pattern-only, no context; doesn't extend CStrategyBase |
| ICT | **Disabled** | Very Low (14+ gates) | ~0.35+ | Over-engineered but highest conviction when it fires |
| Unicorn | **Disabled** | Very Low | 0.62 | Good concept (OB+FVG overlap) but disabled as "subjective" |
| Power of Three | **Disabled** | Very Low | 0.64 | AMD-based, disabled as "subjective" |
| Mean Reversion | **Not registered** | Medium | 0.60 | Complete implementation, never added to ESM |
| Volatility Breakout | **Not registered** | Low | 0.65 | Complete implementation, never added to ESM |
| Statistical Arbitrage | **Not registered** | Low | 0.70 | Requires Python Bridge, not in ESM |

**Critical finding**: The EA is running on its **weakest strategies** while its strongest are disabled or unregistered. The active strategies (Momentum, Trend, S/R, Candlestick) are all trend-following or pattern-matching — there is **no mean-reversion, no volatility breakout, and no statistical edge** in the active set.

### 2.4 Execution Architecture Gaps

| Gap | Detail |
|---|---|
| Market-order-only | No limit orders, no stop orders, no IOC/FOK optimization. All entries pay the spread + slippage. |
| No tick-level signal generation | All strategies are bar-based. No strategy produces intrabar signals by default. |
| No fast-path for scalping | Scalping signals route through the same 7-layer consensus pipeline as swing signals |
| Single magic number | All symbols/strategies share one magic number. Cannot attribute positions to source. |
| No partial close logic for profit locking | `ClosePositionPartial()` exists but is never called from the main loop |
| No spread-arbitrage execution | On synthetic indices with known spread patterns, no execution timing optimization |

---

## 3. Execution Speed Overhaul

### 3.1 SRE Consensus Cache (CRITICAL — Highest Impact)

**Problem**: `ManageOpenPositionsIfNeeded()` calls `GetConsensusSignalForSymbolWithConfluenceMode(EVAL_MODE_INTRABAR)` for every open position on every tick. With 3 positions, this is 3 full consensus evaluations per tick.

**Solution**: Implement a **tick-scoped consensus cache** with 1-second TTL.

```cpp
// New class: CConsensusCache
class CConsensusCache
{
private:
   struct SCacheEntry
   {
      string              symbol;
      ENUM_TRADE_SIGNAL   signal;
      double              confidence;
      double              confluence;
      datetime            computedAt;
      ENUM_EVAL_MODE      evalMode;
   };
   
   SCacheEntry  m_entries[20];  // max symbols
   int          m_count;
   int          m_ttlSeconds;   // default 1
   
public:
   bool TryGet(string symbol, ENUM_EVAL_MODE mode, ENUM_TRADE_SIGNAL &signal, double &confidence, double &confluence);
   void Store(string symbol, ENUM_EVAL_MODE mode, ENUM_TRADE_SIGNAL signal, double confidence, double confluence);
   void Invalidate(string symbol);  // on new bar for this symbol
   void InvalidateAll();            // on major state change
};
```

**Integration**: In `ManageOpenPositionsIfNeeded()`, before calling consensus, check cache. If hit and <1s old, use cached result. On new bar for a symbol, invalidate that symbol's cache entry.

**Expected impact**: Reduces consensus evaluations from N-per-tick to at most 1-per-symbol-per-second. With 5 symbols and 3 positions, this is a **~15x reduction** in consensus computation on the hot path.

### 3.2 ATR Value Cache

**Problem**: `ValidateExecutionPreflight()` and `UpdateDynamicSlippage()` both independently call `GetATR()` / `CalculateATR()` for the same symbol/timeframe.

**Solution**: Cache the last ATR value per symbol with bar-time staleness check.

```cpp
// In CTradeManager or CMarketAnalysis
struct SATRCache
{
   string   symbol;
   double   atrValue;
   datetime barTime;    // invalidate on new bar
};

double GetATRCached(string symbol, ENUM_TIMEFRAMES tf);
```

**Expected impact**: Eliminates redundant `CopyBuffer` calls. ~2x fewer indicator reads per execution attempt.

### 3.3 Non-Blocking Execution Confirmation

**Problem**: `ConfirmExecutionReceipt()` uses `Sleep(150ms)` up to 3 times, blocking the EA thread for up to 300ms.

**Solution**: Replace synchronous confirmation with **deferred async confirmation**.

```cpp
// Instead of blocking sleep loop:
// 1. Send order
// 2. Check deal history once (no sleep)
// 3. If not found, mark position as "pending confirmation"
// 4. On next tick, check pending confirmations and resolve

struct SPendingConfirmation
{
   ulong    orderTicket;
   string   symbol;
   double   expectedPrice;
   datetime sentAt;
   int      checkAttempts;
};
```

**Expected impact**: Eliminates all blocking sleep from the execution path. EA remains responsive during order confirmation.

### 3.4 Indicator Handle Pooling

**Problem**: Each symbol's enterprise manager creates its own indicator handles. With 5 symbols × 8+ indicators, handle count approaches the 500 limit. Additionally, Momentum and Trend strategies create temporary `iATR` handles inline.

**Solution**: 
1. **Enforce `CIndicatorManager` singleton for all handle creation** — remove inline `iATR()` / `iVolumes()` calls from strategies
2. **Implement handle sharing** — same indicator parameters across symbols should reuse handles where possible
3. **Add handle pressure monitoring** — log warning when handle count exceeds 400

```cpp
// In each strategy, replace:
int tempAtr = iATR(m_symbol, m_timeframe, 14);  // LEAK
// With:
int atrHandle = CIndicatorManager::GetInstance().GetATRHandle(m_symbol, m_timeframe, 14);
```

**Expected impact**: Prevents handle leaks, reduces total handle count by ~30%, eliminates the ICT volume handle leak.

### 3.5 Fast-Path Signal Evaluation

**Problem**: Every scan cycle evaluates ALL registered strategies even when most return NONE. No short-circuit when quorum is already mathematically impossible.

**Solution**: Two-tier evaluation:

```cpp
// Tier 1: Quick-probe strategies (fast indicators only)
// - Momentum (EMA cross check — O(1) with cached values)
// - Candlestick (pattern check — O(1))
// - If Tier 1 produces quorum, skip Tier 2

// Tier 2: Full evaluation (slow strategies)
// - Trend (multi-EMA + ADX + HTF)
// - S/R (detector scan)
// - ICT modules (if enabled)
// - AI adapters
```

**Implementation**: Add `GetQuickProbeSignal()` method to `IStrategy` interface with default implementation returning NONE. Strategies that can produce fast signals override it. The consensus engine tries Tier 1 first and only invokes Tier 2 if quorum is not reached.

**Expected impact**: 40-60% reduction in per-cycle strategy evaluation time when Tier 1 reaches quorum.

### 3.6 Logging Throttle

**Problem**: 8+ `PrintFormat` calls every 10-60s with complex string formatting. `GetAggregatedConsensusDiagnostics()` and `GetAggregatedRoleClusterDiagnostics()` aggregate across all managers each time.

**Solution**:
1. Increase heartbeat interval to 60s minimum
2. Replace `PrintFormat` with `FileWrite` to a dedicated log file (off-journal, no UI impact)
3. Cache diagnostic strings — only recompute when state changes
4. Add `InpLogLevel` input: 0=Silent, 1=Critical, 2=Normal, 3=Verbose

**Expected impact**: ~70% reduction in logging overhead during normal operation.

---

## 4. Money Management Redesign

### 4.1 Unified Risk Denominator

**Problem**: `CPositionSizer` uses `min(balance, equity)`, `CICTPositionSizer` uses `balance` only. During drawdown, ICT sizer calculates larger lots than the unified risk manager expects.

**Solution**: Standardize on a single risk denominator formula across all sizers:

```cpp
// New unified formula in CPositionSizer:
double GetRiskDenominator()
{
   // Use equity when it's below balance (floating loss exists)
   // Use balance when equity is above (don't size up on unrealized gains)
   // This is the most conservative and consistent approach
   return MathMin(m_accountInfo.Balance(), m_accountInfo.Equity());
}
```

**Enforcement**: Remove `CICTPositionSizer`'s independent lot calculation. All position sizing must go through `CPositionSizer` which is governed by `CUnifiedRiskManager`. The ICT sizer becomes a **parameter provider** (risk %, SL distance) rather than an independent calculator.

### 4.2 Tiered Position Sizing Model

Replace the single `POSITION_SIZE_RISK_PERCENT` mode with a **3-tier sizing model** tied to trading mode:

```cpp
enum ENUM_POSITION_SIZE_TIER
{
   TIER_CONSERVATIVE,   // 0.5% risk per trade, 2% daily max, 6% portfolio max
   TIER_MODERATE,       // 1.0% risk per trade, 5% daily max, 15% portfolio max
   TIER_AGGRESSIVE,     // 2.0% risk per trade, 10% daily max, 30% portfolio max
   TIER_FULL_MARGIN     // See Section 8 — dedicated full-margin scalping mode
};
```

Each tier automatically configures:
- Base risk per trade %
- Daily risk budget %
- Portfolio risk cap %
- Max positions
- Breakeven buffer
- Trailing distance
- Drawdown warning/critical thresholds

```cpp
struct STierConfig
{
   double riskPerTradePct;
   double dailyRiskPct;
   double portfolioRiskPct;
   int    maxPositions;
   double breakevenBufferPts;
   double trailingDistancePts;
   double ddWarningPct;
   double ddCriticalPct;
};

STierConfig g_tierConfigs[4] =
{
   { 0.5,  2.0,  6.0,  3,  80,  200, 3.0,  6.0  },  // CONSERVATIVE
   { 1.0,  5.0, 15.0,  5, 120,  300, 5.0, 10.0  },  // MODERATE
   { 2.0, 10.0, 30.0,  8, 100,  250, 8.0, 15.0  },  // AGGRESSIVE
   { 5.0, 25.0, 80.0, 12,  60,  150, 5.0, 10.0  },  // FULL_MARGIN
};
```

**Expected impact**: Eliminates the current "10% per trade / 30% daily / 50% portfolio" insanity. Provides structured risk scaling instead of ad-hoc parameter tuning.

### 4.3 Dynamic Lot Scaling Based on Win Streak

**Problem**: Current system uses static risk percentages regardless of recent performance. Winning streaks should compound; losing streaks should contract.

**Solution**: Implement **anti-Martingale scaling** with momentum factor:

```cpp
double CalculateMomentumScale()
{
   int consecutiveWins = performanceAnalytics.GetConsecutiveWins();
   int consecutiveLosses = performanceAnalytics.GetConsecutiveLosses();
   
   double scale = 1.0;
   
   // Win streak: increase size by 10% per win, capped at 1.5x
   if(consecutiveWins > 0)
      scale = MathMin(1.5, 1.0 + consecutiveWins * 0.10);
   
   // Loss streak: decrease size by 15% per loss, floored at 0.5x
   if(consecutiveLosses > 0)
      scale = MathMax(0.5, 1.0 - consecutiveLosses * 0.15);
   
   return scale;
}
```

Apply `momentumScale` as a multiplier to the base lot size from the tier config.

**Expected impact**: Naturally compounds during winning periods and protects capital during losing streaks. This is the opposite of Martingale — it's Kelly-adjacent.

### 4.4 Per-Symbol Risk Budgeting

**Problem**: Global daily/portfolio risk budget allows one volatile symbol to consume the entire allocation.

**Solution**: Allocate risk budget proportionally across symbols:

```cpp
// Each symbol gets an equal share of the daily budget by default
// Symbols with higher recent win rate get a larger share
double GetSymbolRiskAllocation(string symbol)
{
   double baseShare = dailyRiskBudget / activeSymbolCount;
   
   // Performance-weighted adjustment
   double winRate = performanceAnalytics.GetSymbolWinRate(symbol);
   double profitFactor = performanceAnalytics.GetSymbolProfitFactor(symbol);
   
   double perfWeight = 1.0;
   if(winRate > 0.55 && profitFactor > 1.3)
      perfWeight = 1.5;  // Reward performing symbols
   else if(winRate < 0.40 || profitFactor < 0.8)
      perfWeight = 0.5;  // Penalize underperformers
   
   return baseShare * perfWeight;
}
```

**Expected impact**: Prevents single-symbol risk concentration. Dynamically shifts capital toward winning symbols.

### 4.5 Eliminate Redundant Sizers

**Problem**: Three independent position sizers (`CPositionSizer`, `CICTPositionSizer`, `CADXPositionSizing`) with different formulas and risk denominators.

**Solution**: Consolidate to a single `CPositionSizer` with pluggable adjustment modules:

```cpp
// CPositionSizer becomes the sole authority for lot calculation
// Strategy-specific adjustments become "modifiers" that the sizer applies:

class CPositionSizerModifier
{
public:
   virtual double AdjustLotSize(double baseLot, string symbol, double confidence) = 0;
};

class CADXLotModifier : public CPositionSizerModifier
{
   // ADX-tiered multiplier logic from CADXPositionSizing
   double AdjustLotSize(double baseLot, string symbol, double confidence) override;
};

class CKellyLotModifier : public CPositionSizerModifier
{
   // Half-Kelly capping from CICTPositionSizer
   double AdjustLotSize(double baseLot, string symbol, double confidence) override;
};
```

The `CPositionSizer` applies modifiers in sequence: base calculation → volatility adjustment → correlation adjustment → strategy-specific modifier → momentum scale → tier cap.

**Expected impact**: Single source of truth for position sizing. No more conflicting lot calculations.

---

## 5. Risk Control Fortress

### 5.1 Unified Drawdown Authority

**Problem**: Three independent drawdown monitors with different thresholds and behaviors.

**Solution**: **One drawdown monitor to rule them all.** `CUnifiedRiskManager` becomes the sole authority. All other drawdown checks are removed.

```cpp
// CUnifiedRiskManager::CheckDrawdownState() — single source of truth
struct SDrawdownState
{
   double   currentDrawdownPct;     // from peak equity
   double   peakEquity;
   double   currentEquity;
   bool     isWarningActive;
   bool     isCriticalActive;
   bool     isTradingEnabled;
   double   conservativeMultiplier;  // applied to position sizes during warning
};

SDrawdownState GetDrawdownState()
{
   SDrawdownState state;
   state.peakEquity = m_peakEquity;
   state.currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   state.currentDrawdownPct = (state.peakEquity - state.currentEquity) / state.peakEquity * 100.0;
   
   // Tier-based thresholds from current tier config
   state.isWarningActive = (state.currentDrawdownPct >= m_tierConfig.ddWarningPct);
   state.isCriticalActive = (state.currentDrawdownPct >= m_tierConfig.ddCriticalPct);
   state.isTradingEnabled = !state.isCriticalActive;
   state.conservativeMultiplier = state.isWarningActive ? 0.60 : 1.0;
   
   return state;
}
```

**Remove from other locations**:
- Remove drawdown check from `CRiskValidationGate::ValidateAccountHealth()` — delegate to unified manager
- Remove daily/weekly DD guards from `CICTPositionSizer` — unified manager handles this
- Remove `DRAWDOWN_CRITICAL` constant from `Enums.mqh` — replaced by tier config

### 5.2 Unified Correlation Engine

**Problem**: Three different correlation implementations producing inconsistent results.

**Solution**: Single Pearson correlation engine in `CPortfolioRiskManager`, used by all consumers.

```cpp
// CPortfolioRiskManager becomes the sole correlation authority
class CCorrelationEngine
{
private:
   double   m_matrix[][20];     // symbol x symbol correlation matrix
   datetime m_lastComputed;
   int      m_computeInterval;  // recompute every N seconds (default 300)
   int      m_lookback;         // H1 bars for Pearson (default 30)
   
public:
   double   GetCorrelation(string sym1, string sym2);
   void     UpdateMatrix();     // called periodically, not per-trade
   bool     IsCorrelatedCluster(string symbol, double threshold = 0.7);
   int      CountCorrelatedPositions(string symbol, double threshold = 0.7);
};
```

**Remove from other locations**:
- Remove `CUnifiedRiskManager::GetSymbolCorrelation()` (simplified same-direction count)
- Remove `CRiskValidationGate::CalculateSymbolCorrelation()` (20-period Pearson)
- Both replaced by `CCorrelationEngine::GetCorrelation()`

### 5.3 Circuit Breaker Auto-Recovery

**Problem**: Critical drawdown circuit breaker requires manual `ResetCircuitBreaker()`. EA stays permanently disabled if operator is not monitoring.

**Solution**: Time-based auto-recovery with cooling period:

```cpp
// After circuit breaker fires:
// 1. Trading disabled immediately
// 2. After 30 minutes (configurable), if drawdown has recovered below 50% of critical level:
//    - Auto-re-enable trading at CONSERVATIVE tier
//    - Force tier downgrade for 24 hours
// 3. If drawdown has NOT recovered, stay disabled, check again in 30 minutes
// 4. Maximum 3 auto-recovery attempts per session
// 5. After 3 failed attempts, require manual reset

struct SCircuitBreakerState
{
   bool     isActive;
   datetime triggeredAt;
   int      recoveryAttempts;
   int      maxRecoveryAttempts;    // default 3
   int      recoveryCooldownMin;    // default 30
   double   recoveryThresholdPct;   // default 50% of critical level
   bool     forceConservativeTier;  // default true
};
```

### 5.4 Virtual Position Book Expiry

**Problem**: Virtual position reservations never expire. A crashed strategy permanently reduces the daily risk budget.

**Solution**: Add TTL-based expiry:

```cpp
// In CVirtualPositionBook:
struct SVirtualPosition
{
   // ... existing fields ...
   datetime   reservedAt;
   int        ttlSeconds;    // default 60
};

// On any access, prune expired reservations:
void PruneExpired()
{
   datetime now = TimeCurrent();
   for(int i = m_count - 1; i >= 0; i--)
   {
      if((int)(now - m_entries[i].reservedAt) > m_entries[i].ttlSeconds)
         RemoveAt(i);
   }
}
```

### 5.5 Margin Call Prevention

**Problem**: No proactive margin call avoidance. System only checks margin before opening new positions but doesn't monitor margin level deterioration on existing positions.

**Solution**: Continuous margin monitoring with graduated response:

```cpp
// In ProcessTickSafetyLoop():
void MonitorMarginHealth()
{
   double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
   
   if(marginLevel == 0) return;  // no open positions
   
   // Level 1: Warning (below 300%)
   if(marginLevel < 300.0 && marginLevel >= 200.0)
   {
      // Reduce position sizes on next entries
      // Log warning
   }
   
   // Level 2: Stress (below 200%)
   if(marginLevel < 200.0 && marginLevel >= 150.0)
   {
      // Close worst-performing position
      // Block all new entries
   }
   
   // Level 3: Emergency (below 150%)
   if(marginLevel < 150.0)
   {
      // Close all positions immediately
      // Emergency log
   }
}
```

### 5.6 Missing Stop-Loss Auto-Remediation Enhancement

**Problem**: Current `AttemptUnprotectedPositionRemediation()` tries to add SL but may fail silently.

**Solution**: Escalation protocol:

```
Attempt 1: Add SL at 3x ATR from entry (standard)
Attempt 2: If Attempt 1 fails (INVALID_STOPS), add SL at broker minimum distance
Attempt 3: If Attempt 2 fails, close the position immediately
```

No position should ever exist without a stop-loss for more than one evaluation cycle.

---

## 6. Fast Scalping Engine

### 6.1 Dedicated Scalping Pipeline

**Problem**: Scalping signals route through the same 7-layer consensus pipeline as swing signals. The pipeline is designed for high-conviction, low-frequency trading — the opposite of scalping.

**Solution**: Implement a **parallel fast-scalping pipeline** that bypasses the full consensus engine:

```cpp
class CFastScalpEngine
{
private:
   // Scalp-specific parameters
   int      m_maxScalpPositions;       // default 3
   double   m_scalpRiskPct;            // from tier config
   int      m_scalpSLPips;             // tight, default 50-80
   int      m_scalpTPPips;             // 1.5-2x SL
   int      m_scalpCooldownMs;         // default 5000
   datetime m_lastScalpTime;
   
   // Micro-trend detection
   int      m_fastEMA;                 // default 5
   int      m_slowEMA;                // default 13
   int      m_rsiPeriod;              // default 7
   double   m_rsiOverbought;          // default 75
   double   m_rsiOversold;            // default 25
   
   // Speed optimization
   double   m_cachedATR;
   datetime m_atrCacheBarTime;
   
public:
   ENUM_TRADE_SIGNAL EvaluateScalpSignal(string symbol);
   bool              ShouldEnterScalp(string symbol, ENUM_TRADE_SIGNAL &signal, double &confidence);
   void              ManageScalpPositions();  // ultra-fast trailing
};
```

### 6.2 Scalp Signal Generation — Micro-Trend with Momentum Burst

The scalping engine uses a **different signal philosophy** from the swing engine:

**Swing**: High conviction, low frequency, consensus-required  
**Scalp**: Fast conviction, high frequency, single-strategy-allowed

```cpp
ENUM_TRADE_SIGNAL CFastScalpEngine::EvaluateScalpSignal(string symbol)
{
   // 1. Micro-trend detection (EMA5/EMA13 crossover on M1)
   double ema5 = GetEMA(symbol, PERIOD_M1, m_fastEMA, 0);
   double ema13 = GetEMA(symbol, PERIOD_M1, m_slowEMA, 0);
   double ema5_prev = GetEMA(symbol, PERIOD_M1, m_fastEMA, 1);
   double ema13_prev = GetEMA(symbol, PERIOD_M1, m_slowEMA, 1);
   
   bool bullishCross = (ema5_prev <= ema13_prev && ema5 > ema13);
   bool bearishCross = (ema5_prev >= ema13_prev && ema5 < ema13);
   
   // 2. Momentum burst filter (current bar body > 0.8 * ATR)
   double atr = GetATRCached(symbol, PERIOD_M1);
   double bodySize = MathAbs(iClose(symbol, PERIOD_M1, 0) - iOpen(symbol, PERIOD_M1, 0));
   bool momentumBurst = (bodySize > 0.8 * atr);
   
   // 3. RSI confirmation (not overbought/oversold)
   double rsi = GetRSI(symbol, PERIOD_M1, m_rsiPeriod, 0);
   
   // 4. Spread gate (reject if spread > 30% of ATR — too expensive for scalp)
   double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(spread > 0.30 * atr) return TRADE_SIGNAL_NONE;
   
   // 5. Signal generation
   if(bullishCross && momentumBurst && rsi < m_rsiOverbought)
      return TRADE_SIGNAL_BUY;
   
   if(bearishCross && momentumBurst && rsi > m_rsiOversold)
      return TRADE_SIGNAL_SELL;
   
   return TRADE_SIGNAL_NONE;
}
```

### 6.3 Scalp Execution — Speed Over Perfection

```cpp
bool CFastScalpEngine::ShouldEnterScalp(string symbol, ENUM_TRADE_SIGNAL &signal, double &confidence)
{
   // Cooldown check
   if((int)(TimeCurrent() - m_lastScalpTime) < m_scalpCooldownMs / 1000)
      return false;
   
   // Max scalp positions check
   if(CountScalpPositions() >= m_maxScalpPositions)
      return false;
   
   // Risk budget check (uses scalp-specific budget, not shared with swing)
   if(!unifiedRiskManager.IsScalpBudgetAvailable(symbol, m_scalpRiskPct))
      return false;
   
   // Signal evaluation
   signal = EvaluateScalpSignal(symbol);
   if(signal == TRADE_SIGNAL_NONE) return false;
   
   confidence = 0.70;  // Fixed confidence for scalp — we don't need consensus
   return true;
}
```

### 6.4 Ultra-Fast Trailing for Scalps

Scalp positions need **tick-level trailing**, not the 1-second throttled trailing used for swing positions:

```cpp
void CFastScalpEngine::ManageScalpPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!IsScalpPosition(ticket)) continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      // Quick profit lock: move SL to breakeven after 10 points profit
      double profit = (type == POSITION_TYPE_BUY) ? 
                      (currentPrice - openPrice) : (openPrice - currentPrice);
      
      if(profit >= 10 * SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_POINT))
      {
         double newSL = openPrice + (type == POSITION_TYPE_BUY ? 5 : -5) * 
                        SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_POINT);
         
         if((type == POSITION_TYPE_BUY && newSL > currentSL) ||
            (type == POSITION_TYPE_SELL && newSL < currentSL))
         {
            tradeManager.ModifyPosition(ticket, newSL, currentTP);
         }
      }
      
      // Tight trailing: 15-point trail after breakeven
      if(currentSL != 0 && profit > 15 * SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_POINT))
      {
         double trailDistance = 15 * SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_POINT);
         double newSL = (type == POSITION_TYPE_BUY) ? 
                        currentPrice - trailDistance : currentPrice + trailDistance;
         
         if((type == POSITION_TYPE_BUY && newSL > currentSL) ||
            (type == POSITION_TYPE_SELL && newSL < currentSL))
         {
            tradeManager.ModifyPosition(ticket, newSL, currentTP);
         }
      }
   }
}
```

### 6.5 Scalp-Specific Risk Budget

Scalp positions use a **separate risk budget** from swing positions:

```cpp
// In CUnifiedRiskManager:
struct SScalpRiskBudget
{
   double   dailyScalpRiskPct;     // e.g., 5% of daily budget reserved for scalps
   double   usedScalpRiskPct;
   int      maxScalpPositions;     // default 3
   double   scalpRiskPerTradePct;  // from tier config
};

bool IsScalpBudgetAvailable(string symbol, double riskPct)
{
   if(m_scalpBudget.usedScalpRiskPct + riskPct > m_scalpBudget.dailyScalpRiskPct)
      return false;
   if(CountScalpPositions() >= m_scalpBudget.maxScalpPositions)
      return false;
   return true;
}
```

### 6.6 Scalp Entry via Pending Orders

**Problem**: Current system is market-order-only. Scalps on synthetic indices need limit orders for better fills.

**Solution**: Add pending order support for scalp entries:

```cpp
// Instead of immediate market order:
// 1. Detect scalp signal
// 2. Place BUY_LIMIT at current bid - 5 points (better entry)
// 3. Set SL/TP on the pending order
// 4. If not filled within 30 seconds, cancel and re-evaluate

bool PlaceScalpPendingOrder(string symbol, ENUM_TRADE_SIGNAL signal, double lotSize)
{
   double price = (signal == TRADE_SIGNAL_BUY) ? 
                  SymbolInfoDouble(symbol, SYMBOL_BID) - 5 * SymbolInfoDouble(symbol, SYMBOL_POINT) :
                  SymbolInfoDouble(symbol, SYMBOL_ASK) + 5 * SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   double sl = (signal == TRADE_SIGNAL_BUY) ?
               price - m_scalpSLPips * SymbolInfoDouble(symbol, SYMBOL_POINT) :
               price + m_scalpSLPips * SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   double tp = (signal == TRADE_SIGNAL_BUY) ?
               price + m_scalpTPPips * SymbolInfoDouble(symbol, SYMBOL_POINT) :
               price - m_scalpTPPips * SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   ENUM_ORDER_TYPE orderType = (signal == TRADE_SIGNAL_BUY) ? 
                                ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;
   
   return m_trade.OrderOpen(symbol, orderType, lotSize, 0, price, sl, tp, 
                            ORDER_TIME_GTC, 0, "SCALP");
}
```

---

## 7. Strategy Enhancement Program

### 7.1 Activate Dormant Strategies

**Priority: IMMEDIATE**

Three complete strategy implementations are not registered in the Enterprise Strategy Manager:

| Strategy | Action | Rationale |
|---|---|---|
| `CMeanReversionStrategy` | Register in ESM, assign to MEAN_REVERSION_CLUSTER | Provides counter-trend signals that current active set completely lacks |
| `CVolatilityBreakoutStrategy` | Register in ESM, assign to TREND_CLUSTER | Captures explosive moves that Momentum and Trend miss |
| `CStatisticalArbitrageStrategy` | Register conditionally (requires Python Bridge) | Provides market-neutral alpha when bridge is available |

**Implementation**: Add includes and registration calls in `InitializeEnterpriseManagerForSymbol()`:

```cpp
// In EnterpriseStrategyManager.mqh or MultiStrategyAutonomousEA.mq5:
#include <Strategies/MeanReversionStrategy.mqh>
#include <Strategies/VolatilityBreakoutStrategy.mqh>

// During strategy registration:
if(InpEnableMeanReversion)
{
   CMeanReversionStrategy* mrStrat = new CMeanReversionStrategy();
   mrStrat.Init(symbol, timeframe, &tradeManager, &positionSizer, &unifiedRiskManager);
   manager.RegisterStrategy(mrStrat, InpWeightMeanReversion, TIER_2, 
                            INTRABAR_POLICY_PROBE, ROLE_PRIMARY_ALPHA, CLUSTER_MEAN_REVERSION);
}
```

### 7.2 Re-enable ICT Strategies with Simplification

**Priority: HIGH**

The ICT, Unicorn, and Power of Three strategies are the highest-conviction signal generators but are disabled as "over-engineered" or "subjective." The solution is not to discard them but to **simplify their gate structure**:

**ICT Strategy Simplification** (currently 14+ modules, 2050 lines):
- Remove: SMT Divergence Scanner, Anchored VWAP, Cumulative Delta (low-value, high-complexity)
- Keep: Market Structure Analyzer, Order Block Detector, Liquidity Detector, Imbalance Detector, Kill Zones
- Reduce confluence tiers from 3 to 2:
  - **Core** (2x weight): Liquidity sweep, OB, FVG/Imbalance, BMS/CHoCH
  - **Context** (1x weight): Kill Zone, Premium/Discount, OTE
- Lower minimum confluence count from current to 2 (from any tier)
- Remove counter-trend scout logic (too restrictive, misses valid reversals)

**Unicorn Strategy** (OB+FVG overlap — the "unicorn" pattern):
- Re-enable with reduced gating
- Remove HTF alignment requirement for M1/M5 timeframes
- Lower min confidence from 0.62 to 0.55

**Power of Three Strategy** (AMD-based):
- Re-enable with simplified AMD detection
- Remove SMT Divergence requirement
- Lower min confidence from 0.64 to 0.55

### 7.3 Fix CStrategyCandlestick Inheritance

**Problem**: `CStrategyCandlestick` directly implements `IStrategy` instead of extending `CStrategyBase`. This means it lacks the standard `CUnifiedRiskManager` injection path and has a dangerous fallback that casts `CTradeManager` as `CUnifiedRiskManager`.

**Solution**: Refactor to extend `CStrategyBase`:

```cpp
// Change from:
class CStrategyCandlestick : public IStrategy

// To:
class CStrategyCandlestick : public CStrategyBase
```

This provides:
- Proper `GetUnifiedRiskManager()` access
- Standard error rate limiting
- Standard signal recording
- Standard decision reason tagging
- Eliminates the dangerous cast fallback

### 7.4 Momentum Strategy Enhancement

**Problem**: Simple EMA crossover is insufficient for synthetic indices. The strategy produces too few signals and misses momentum shifts.

**Solution**: Add **rate-of-change acceleration** detection:

```cpp
// In CSimpleMomentumStrategy::ExecuteSignal():
// After EMA crossover detection, add:

// Rate of change acceleration
double roc_now = (ema8 - ema8_prev) / ema8_prev * 100;    // current ROC
double roc_prev = (ema8_prev - ema8_prev2) / ema8_prev2 * 100;  // previous ROC
bool accelerating = (MathAbs(roc_now) > MathAbs(roc_prev) * 1.2);  // 20% acceleration

// If crossover + acceleration + RSI confirmation: high-confidence signal
// If crossover only (no acceleration): reduced confidence
if(crossoverDetected && accelerating)
   confidence *= 1.3;  // Boost confidence for accelerating moves
else if(crossoverDetected)
   confidence *= 0.7;  // Reduce confidence for decelerating crosses
```

### 7.5 Trend Strategy — Fix Temporary Handle Leak

**Problem**: `GetTradeParameters()` creates a temporary `iATR` handle every call, uses it once, then releases it.

**Solution**: Cache the ATR handle as a class member:

```cpp
// In CStrategyTrend class declaration:
int m_tradeParamATRHandle;  // cached ATR handle for trade parameters

// In Init():
m_tradeParamATRHandle = INVALID_HANDLE;

// In GetTradeParameters():
if(m_tradeParamATRHandle == INVALID_HANDLE)
   m_tradeParamATRHandle = iATR(m_symbol, m_timeframe, 14);

double atrValues[];
CopyBuffer(m_tradeParamATRHandle, 0, 0, 1, atrValues);
// Use atrValues[0] — no handle creation, no release needed

// In Deinit():
if(m_tradeParamATRHandle != INVALID_HANDLE)
   IndicatorRelease(m_tradeParamATRHandle);
```

### 7.6 S/R Strategy — Implement Fibonacci Confluence

**Problem**: `ApplyFibConfluence()` is completely stubbed (TODO). The Fibonacci module is initialized but never used.

**Solution**: Implement Fibonacci confluence scoring:

```cpp
double CStrategySupportResistance::ApplyFibConfluence(double price, ENUM_TRADE_SIGNAL direction)
{
   if(!m_fibRetracement || !m_fibRetracement.IsInitialized())
      return 0.0;
   
   // Get Fibonacci levels
   double levels[];
   m_fibRetracement.GetLevels(levels);
   
   // Check proximity to key levels (38.2%, 50%, 61.8%)
   double proximityBonus = 0.0;
   double atr = GetATR();
   
   for(int i = 0; i < ArraySize(levels); i++)
   {
      double distance = MathAbs(price - levels[i]);
      if(distance < 0.5 * atr)  // Within half ATR of Fib level
         proximityBonus += 0.10;
      else if(distance < 1.0 * atr)
         proximityBonus += 0.05;
   }
   
   return MathMin(proximityBonus, 0.20);  // Cap at 0.20
}
```

### 7.7 Strategy Cluster Rebalancing

**Problem**: Current cluster assignment is unbalanced — most active strategies are in TREND_CLUSTER, STRUCTURE_CLUSTER has only disabled strategies, and MEAN_REVERSION_CLUSTER has no active strategies.

**Solution**: Rebalance clusters after activating dormant strategies:

| Cluster | Strategies | Purpose |
|---|---|---|
| TREND_CLUSTER | Momentum, Trend, Volatility Breakout | Directional trend-following + breakout |
| MEAN_REVERSION_CLUSTER | Mean Reversion, Candlestick | Counter-trend + pattern reversal |
| STRUCTURE_CLUSTER | S/R, ICT (simplified), Unicorn (simplified) | Market structure + institutional levels |
| SCALP_CLUSTER | Fast Scalp Engine | Dedicated high-frequency scalping |

Each cluster gets its own risk allocation within the portfolio budget:
- TREND: 40% of portfolio risk budget
- MEAN_REVERSION: 25%
- STRUCTURE: 25%
- SCALP: 10% (separate budget, see Section 6.5)

---

## 8. Full-Margin Aggressive Mode

### 8.1 Concept

Full-margin mode is a **dedicated trading mode** that maximizes capital utilization for aggressive profit generation. It is NOT the default mode — it is an opt-in mode for experienced operators who accept high risk for high reward.

### 8.2 Configuration

```cpp
// TIER_FULL_MARGIN from Section 4.2:
{ riskPerTrade: 5.0%, dailyRisk: 25.0%, portfolioRisk: 80.0%, maxPositions: 12,
  breakevenBuffer: 60pts, trailingDistance: 150pts, ddWarning: 5.0%, ddCritical: 10.0% }
```

### 8.3 Full-Margin Scalping Protocol

When `TIER_FULL_MARGIN` is active, the scalping engine operates at maximum capacity:

```cpp
struct SFullMarginScalpConfig
{
   double   riskPerScalpPct;        // 3.0% per scalp trade
   int      maxScalpPositions;      // 5 simultaneous
   int      scalpSLPips;            // 40 (very tight)
   int      scalpTPPips;            // 60 (1.5 R:R)
   int      scalpCooldownMs;        // 3000 (3 seconds between scalps)
   double   scalpDailyBudgetPct;    // 15% of daily budget for scalps
   bool     usePendingOrders;       // true — limit orders for better fills
   int      pendingOrderTTL;        // 20 seconds
   bool     partialCloseEnabled;    // true — close 50% at 1R, trail rest
};
```

### 8.4 Full-Margin Position Stacking

In full-margin mode, the EA can **stack positions** on the same symbol when momentum is confirmed:

```cpp
bool CanStackPosition(string symbol, ENUM_TRADE_SIGNAL direction)
{
   int existingPositions = CountPositionsBySymbolAndDirection(symbol, direction);
   
   if(existingPositions >= 3) return false;  // Max 3 stacked positions
   
   // All existing positions must be in profit
   for(int i = 0; i < PositionsTotal(); i++)
   {
      if(PositionGetString(POSITION_SYMBOL) == symbol &&
         PositionGetInteger(POSITION_TYPE) == direction)
      {
         if(PositionGetDouble(POSITION_PROFIT) < 0)
            return false;  // Don't add to losing positions
      }
   }
   
   // Each stacked position uses 50% of the previous position's lot size
   return true;
}

double GetStackedLotSize(string symbol, int stackLevel)
{
   double baseLot = positionSizer.CalculateOptimalPositionSize(...);
   return baseLot * MathPow(0.5, stackLevel);  // Pyramid: 100%, 50%, 25%
}
```

### 8.5 Full-Margin Circuit Breaker

Full-margin mode has a **faster, stricter circuit breaker**:

```cpp
// Full-margin specific:
// - DD warning at 5% (vs 8% in aggressive, 3% in conservative)
// - DD critical at 10% (vs 15% in aggressive, 6% in conservative)
// - Auto-recovery forces downgrade to CONSERVATIVE tier for 2 hours
// - If second breach within 24 hours, disable full-margin for the session

struct SFullMarginCircuitBreaker
{
   double   warningPct;           // 5.0%
   double   criticalPct;          // 10.0%
   int      cooldownMinutes;      // 120 (2 hours at conservative)
   int      maxBreachesPerDay;    // 2
   bool     sessionLocked;        // true after 2nd breach
};
```

### 8.6 Full-Margin Mandatory Safeguards

Even in full-margin mode, these safeguards are **non-negotiable**:

1. **Every position must have a stop-loss** — no exceptions
2. **Maximum 3 stacked positions per symbol** — prevents over-concentration
3. **Daily loss limit is absolute** — once 25% daily budget is consumed, all trading stops
4. **Margin level must stay above 200%** — automatic position reduction if breached
5. **No trading during major news events** — integrate economic calendar filter
6. **Spread gate is stricter** — reject entries when spread > 20% of ATR (vs 30% normal)

---

## 9. Safe Trading Mode

### 9.1 Conservative Tier Configuration

```cpp
// TIER_CONSERVATIVE from Section 4.2:
{ riskPerTrade: 0.5%, dailyRisk: 2.0%, portfolioRisk: 6.0%, maxPositions: 3,
  breakevenBuffer: 80pts, trailingDistance: 200pts, ddWarning: 3.0%, ddCritical: 6.0% }
```

### 9.2 Safe Mode Additional Protections

```cpp
struct SSafeModeConfig
{
   // Entry restrictions
   double   minConfidence;           // 0.70 (higher than default 0.30)
   int      minVoters;               // 3 (requires broad consensus)
   double   minQuorumThreshold;      // 0.65 (stronger agreement needed)
   double   minConfluence;           // 0.60
   
   // Time restrictions
   bool     tradeOnlyKillZones;      // true — only during London/NY sessions
   bool     avoidNewsEvents;         // true — skip entries around news
   int      newsAvoidanceMinutes;    // 30 before and after
   
   // Position restrictions
   bool     noStacking;              // true — one position per symbol
   bool     requireBreakevenFirst;   // true — must hit breakeven before adding positions
   double   maxSpreadATRRatio;       // 0.15 (tighter spread gate)
   
   // Exit enhancements
   bool     aggressiveBreakeven;     // true — move to BE faster
   double   breakevenTriggerR;       // 0.5R (move to BE at half the risk distance)
   bool     partialProfitTaking;     // true — close 50% at 1R
};
```

### 9.3 Safe Mode Kill Zone Filter

```cpp
bool IsInKillZone()
{
   // London Kill Zone: 07:00-10:00 UTC
   // New York Kill Zone: 12:00-15:00 UTC
   // Asian Session: 00:00-03:00 UTC (optional)
   
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   int hourUTC = dt.hour;
   
   bool londonKZ = (hourUTC >= 7 && hourUTC < 10);
   bool nyKZ = (hourUTC >= 12 && hourUTC < 15);
   
   return londonKZ || nyKZ;
}
```

### 9.4 Safe Mode Partial Profit Taking

```cpp
void ManageSafeModePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!IsEAOwnedPosition(ticket)) continue;
      
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl = PositionGetDouble(POSITION_SL);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double volume = PositionGetDouble(POSITION_VOLUME);
      ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      
      double risk = MathAbs(openPrice - sl);
      double profit = (type == POSITION_TYPE_BUY) ? (currentPrice - openPrice) : (openPrice - currentPrice);
      double profitR = profit / risk;
      
      // Partial close at 1R: close 50% of position
      if(profitR >= 1.0 && !IsPartialClosed(ticket))
      {
         double closeVolume = NormalizeDouble(volume * 0.5, 2);
         tradeManager.ClosePositionPartial(ticket, closeVolume);
         MarkPartialClosed(ticket);
      }
      
      // Move SL to breakeven at 0.5R
      if(profitR >= 0.5 && sl != openPrice)
      {
         double buffer = 5 * SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_POINT);
         double newSL = (type == POSITION_TYPE_BUY) ? openPrice + buffer : openPrice - buffer;
         tradeManager.ModifyPosition(ticket, newSL, PositionGetDouble(POSITION_TP));
      }
   }
}
```

---

## 10. Architecture Refactoring

### 10.1 Decompose the Monolith

**Problem**: `MultiStrategyAutonomousEA.mq5` is 6000+ lines. OnInit alone is ~500 lines. `ProcessTradingLogic()` is ~1200 lines of deeply nested logic.

**Solution**: Extract into focused modules:

| Current Location | Extracted Module | Responsibility |
|---|---|---|
| OnInit (lines 1-500) | `CInitializationManager` | System bootstrap, dependency wiring |
| ProcessTradingLogic (signal eval) | `CSignalEvaluationOrchestrator` | Symbol selection, consensus, candidate ranking |
| ProcessTradingLogic (execution) | `CExecutionOrchestrator` | Risk approval, order send, receipt handling |
| ManageOpenPositionsIfNeeded | `CPositionLifecycleManager` | SRE, breakeven, trailing, structural exit |
| Risk parameter setup | `CRiskTierManager` | Tier selection, parameter application |
| Heartbeat/diagnostics | `CDiagnosticsManager` | All logging, heartbeat, dashboard updates |

### 10.2 Per-Symbol Magic Number

**Problem**: All positions share one magic number. Cannot attribute positions to source.

**Solution**: Encode symbol and strategy cluster in the magic number:

```cpp
// Magic number format: BASE_MAGIC + symbol_index * 100 + cluster_code
// Example: BASE=100000, EURUSD=0, TREND=1 → magic=100001
//          BASE=100000, GBPUSD=1, STRUCTURE=3 → magic=100103

int GenerateMagicNumber(int symbolIndex, int clusterCode)
{
   return InpMagicNumber + symbolIndex * 100 + clusterCode;
}
```

This allows filtering positions by symbol and cluster without parsing comments.

### 10.3 Remove Dead Code

| Item | Location | Action |
|---|---|---|
| `STRATEGY_ELLIOTT_WAVE = 4` | `Enums.mqh` | Remove enum value and all references |
| `STRATEGY_FIBONACCI` | `Enums.mqh` | Remove — merged into S/R |
| `InpWeightElliottWave` | `MultiStrategyAutonomousEA.mq5` | Remove input parameter |
| `InpWeightFibonacci` | `MultiStrategyAutonomousEA.mq5` | Remove input parameter |
| `PendingOrder` struct | `TradeManager.mqh` line 179 | Either implement or remove |
| `ApplyFibConfluence` stub | `StrategySupportResistance.mqh` | Implement (Section 7.6) or remove |

### 10.4 Risk Percent Scale Consistency

**Problem**: Code uses 0-100 scale for risk percentages (e.g., `InpMaxRiskPerTrade = 10.0` meaning 10%), but some internal calculations expect 0-1. `SUnifiedRiskConfig` defaults set `baseRiskPerTradePercent = 10.0` while `m_activeRiskPerTradePercent` starts at `1.0`.

**Solution**: Standardize on 0-100 scale everywhere. Add explicit conversion functions:

```cpp
// All risk parameters use 0-100 scale (e.g., 1.5 = 1.5%)
// Internal calculations divide by 100 when needed:
double riskFraction = riskPercent / 100.0;

// Add validation in setters:
void SetRiskPerTrade(double pct)
{
   if(pct < 0.01 || pct > 50.0)
      Print("WARNING: Risk per trade ", pct, "% is outside safe range [0.01, 50.0]");
   m_activeRiskPerTradePercent = pct;
}
```

### 10.5 Shared Position Sizer State Protection

**Problem**: `CPositionSizer positionSizer` is a single global instance. `SetParameters()` then `CalculateOptimalPositionSize()` in the same loop iteration is error-prone.

**Solution**: Make position sizing **stateless** — pass all parameters directly:

```cpp
// Instead of:
positionSizer.SetParameters(symbol, orderType, slPips, riskPct, ...);
double lot = positionSizer.CalculateOptimalPositionSize();

// Use:
double lot = positionSizer.CalculateSize(symbol, orderType, slPips, riskPct, confidence, tierConfig);
```

This eliminates the shared mutable state problem entirely.

---

## 11. Implementation Roadmap

### Phase 1: Critical Performance Fixes (Immediate)

| # | Task | Section | Impact |
|---|---|---|---|
| 1.1 | Implement consensus cache (SRE optimization) | 3.1 | **~15x reduction** in hot-path consensus evaluations |
| 1.2 | Fix ICT volume handle leak | 3.4 | Prevents handle exhaustion |
| 1.3 | Fix Momentum/Trend inline ATR handle creation | 3.4, 7.5 | Eliminates per-cycle handle leaks |
| 1.4 | Implement ATR value cache | 3.2 | 2x fewer indicator reads per execution |
| 1.5 | Non-blocking execution confirmation | 3.3 | Eliminates up to 300ms blocking sleep |

### Phase 2: Risk Model Unification (High Priority)

| # | Task | Section | Impact |
|---|---|---|---|
| 2.1 | Unify drawdown authority in CUnifiedRiskManager | 5.1 | Single source of truth, no conflicting states |
| 2.2 | Unify correlation engine in CCorrelationEngine | 5.2 | Consistent correlation decisions |
| 2.3 | Standardize risk denominator | 4.1 | No more conflicting lot calculations |
| 2.4 | Implement tiered position sizing | 4.2 | Structured risk scaling, sane defaults |
| 2.5 | Add virtual position book expiry | 5.4 | Prevents permanent budget reduction |
| 2.6 | Add circuit breaker auto-recovery | 5.3 | EA doesn't stay permanently disabled |
| 2.7 | Add margin call prevention | 5.5 | Proactive margin protection |

### Phase 3: Strategy Activation & Enhancement (High Priority)

| # | Task | Section | Impact |
|---|---|---|---|
| 3.1 | Register MeanReversion in ESM | 7.1 | Counter-trend capability |
| 3.2 | Register VolatilityBreakout in ESM | 7.1 | Breakout capture capability |
| 3.3 | Simplify and re-enable ICT strategy | 7.2 | Highest-conviction signals |
| 3.4 | Re-enable Unicorn strategy | 7.2 | OB+FVG overlap detection |
| 3.5 | Fix Candlestick inheritance | 7.3 | Eliminates dangerous cast fallback |
| 3.6 | Enhance Momentum with ROC acceleration | 7.4 | Better momentum detection |
| 3.7 | Implement S/R Fibonacci confluence | 7.6 | Stronger S/R signals |

### Phase 4: Fast Scalping Engine (Medium Priority)

| # | Task | Section | Impact |
|---|---|---|---|
| 4.1 | Implement CFastScalpEngine | 6.1-6.4 | Dedicated scalping pipeline |
| 4.2 | Add scalp-specific risk budget | 6.5 | Isolated scalp risk |
| 4.3 | Add pending order support for scalps | 6.6 | Better fills, lower slippage |
| 4.4 | Ultra-fast trailing for scalp positions | 6.4 | Tick-level profit protection |

### Phase 5: Money Management Enhancement (Medium Priority)

| # | Task | Section | Impact |
|---|---|---|---|
| 5.1 | Implement anti-Martingale momentum scaling | 4.3 | Natural compounding/contraction |
| 5.2 | Implement per-symbol risk budgeting | 4.4 | Prevents single-symbol concentration |
| 5.3 | Consolidate position sizers | 4.5 | Single source of truth for sizing |
| 5.4 | Make position sizer stateless | 10.5 | Eliminates shared mutable state |

### Phase 6: Full-Margin Mode (Lower Priority — Requires Phase 2+3)

| # | Task | Section | Impact |
|---|---|---|---|
| 6.1 | Implement full-margin tier config | 8.2 | Aggressive profit mode |
| 6.2 | Implement full-margin scalping protocol | 8.3 | Maximum capital utilization |
| 6.3 | Implement position stacking | 8.4 | Pyramid into winning positions |
| 6.4 | Implement full-margin circuit breaker | 8.5 | Safety net for aggressive mode |

### Phase 7: Architecture Cleanup (Ongoing)

| # | Task | Section | Impact |
|---|---|---|---|
| 7.1 | Decompose monolith into focused modules | 10.1 | Maintainability |
| 7.2 | Per-symbol magic numbers | 10.2 | Position attribution |
| 7.3 | Remove dead code | 10.3 | Code clarity |
| 7.4 | Fix risk percent scale inconsistency | 10.4 | Bug prevention |
| 7.5 | Logging throttle and level control | 3.6 | Performance |

---

## Appendix A: Key File Reference

| File | Role | Key Issues |
|---|---|---|
| `MultiStrategyAutonomousEA.mq5` | Main EA entry (6000+ lines) | Monolithic, global state, mixed abstraction levels |
| `Core/Risk/UnifiedRiskManager.mqh` | Single risk authority | Conflicting drawdown/correlation with sub-systems |
| `Core/Risk/RiskValidationGate.mqh` | 7-step validation pipeline | Redundant drawdown check, different correlation calc |
| `Core/Risk/PositionSizer.mqh` | Position sizing | Shared mutable state, inconsistent denominator |
| `Core/Risk/PortfolioRiskManager.mqh` | Portfolio risk aggregation | Third correlation implementation |
| `Core/Risk/VirtualPosition.mqh` | Scan-time reservations | No expiry mechanism |
| `Core/Trading/TradeManager.mqh` | Trade execution | Blocking sleep, double ATR fetch, no pending orders |
| `Core/Management/EnterpriseStrategyManager.mqh` | Consensus engine | No consensus cache, no early-exit optimization |
| `Strategies/SimpleMomentumStrategy.mqh` | Momentum strategy | Inline ATR handle leak, weak signal generation |
| `Strategies/StrategyTrend.mqh` | Trend strategy | Temporary ATR handle per call |
| `Strategies/StrategyUnifiedICT.mqh` | ICT strategy (disabled) | Volume handle leak, over-gated, 14+ modules |
| `Strategies/StrategyCandlestick.mqh` | Candlestick patterns | Wrong inheritance, dangerous cast fallback |
| `Strategies/StrategySupportResistance.mqh` | S/R strategy | Fib confluence stubbed |
| `Strategies/MeanReversionStrategy.mqh` | Mean reversion (not registered) | Complete but unused |
| `Strategies/VolatilityBreakoutStrategy.mqh` | Vol breakout (not registered) | Complete but unused |
| `Core/Utils/Enums.mqh` | Enumerations and constants | Dead enum values, risk scale inconsistency |

## Appendix B: Risk Tier Quick Reference

| Parameter | Conservative | Moderate | Aggressive | Full-Margin |
|---|---|---|---|---|
| Risk/Trade | 0.5% | 1.0% | 2.0% | 5.0% |
| Daily Risk | 2.0% | 5.0% | 10.0% | 25.0% |
| Portfolio Risk | 6.0% | 15.0% | 30.0% | 80.0% |
| Max Positions | 3 | 5 | 8 | 12 |
| DD Warning | 3.0% | 5.0% | 8.0% | 5.0% |
| DD Critical | 6.0% | 10.0% | 15.0% | 10.0% |
| Min Confidence | 0.70 | 0.55 | 0.40 | 0.35 |
| Min Voters | 3 | 2 | 2 | 1 |
| Spread Gate | 15% ATR | 20% ATR | 25% ATR | 20% ATR |
| Scalp Budget | 0% | 3% | 8% | 15% |

## Appendix C: Expected Performance Impact Summary

| Change | Latency Impact | Profit Impact | Risk Impact |
|---|---|---|---|
| Consensus cache (3.1) | -90% hot-path time | +10-20% (faster entries) | Neutral |
| ATR cache (3.2) | -50% indicator reads | +5% (faster entries) | Neutral |
| Non-blocking confirmation (3.3) | -300ms max blocking | +5-10% (no missed ticks) | Neutral |
| Tiered sizing (4.2) | Neutral | +20-40% (better sizing) | -50% drawdown risk |
| Unify drawdown (5.1) | Neutral | +5% (fewer false stops) | -30% conflicting states |
| Activate MeanReversion (7.1) | Neutral | +15-25% (counter-trend alpha) | -10% (diversification) |
| Activate VolBreakout (7.1) | Neutral | +10-20% (breakout capture) | -5% (diversification) |
| Re-enable ICT simplified (7.2) | +5% (more strategies) | +20-30% (high conviction) | -15% (better entries) |
| Fast scalping engine (6.x) | -80% scalp latency | +30-50% (scalp alpha) | +20% (more trades = more exposure) |
| Full-margin mode (8.x) | Neutral | +50-100% (when winning) | +200% (when losing) |
| Anti-Martingale scaling (4.3) | Neutral | +10-15% (compounding) | -20% (loss contraction) |
| Per-symbol risk budget (4.4) | Neutral | +5-10% (better allocation) | -15% (concentration risk) |

---

*This document is a living specification. Each section should be reviewed and approved before implementation begins. The Phase ordering reflects dependency chains — Phase 2 (risk unification) must complete before Phase 6 (full-margin mode) is safe to implement.*
