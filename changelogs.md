### FX sizing arms: per-trade risk 2% and floor off - both neutral-to-negative
| window | 1% shipped | 2% per trade | floor off (InpMinLotRiskMultiplier=1.0) |
|---|---|---|---|
| 08.01 to 08.08 | -4.632% (203 fills) | **-5.830%** (211) | **-4.632%** (203), identical to the cent |
| 09.22 to 09.29 | -5.615% (209 fills) | **-5.487%** (208) | **-5.615%** (209), identical to the cent |

The lot floor is inert on FX - it logged 371 / 522 [RISK-LOT-FLOOR] lines and disabling it changed nothing (same
fills, closes, net, balance). Doubling per-trade risk moves the two windows in opposite directions (-1.20 / +0.13 pp)
and both stay negative, because the 6/18 ceilings clamp concurrent size. Wall-clock oddity: the floor-off 09.22 arm
took 68 min / 464 MB journal versus 29 min on the baseline arm of the same window; cause not established, trades
identical. Conclusion: the FX loss is signal quality plus modelled 1-minute spread, not position size; currencies
stay out of the universe.
# Changelog

All notable changes to the `metatrader-multistrategy-ea` project are documented in this file.

This file starts at **Batch 282**. The previous history is preserved unchanged:
- Batches 170–281: [`docs/changelogs_batch170-281.md`](docs/changelogs_batch170-281.md)
- Batches 102–169 (2026-08 → 2026-10): [`docs/changelogs_batch102-169.md`](docs/changelogs_batch102-169.md)
- Batch 101 and earlier: [`docs/changelogs_old.md`](docs/changelogs_old.md)

Architectural descriptions of batch changes live in [SYSTEM_STRUCTURE.md](SYSTEM_STRUCTURE.md); runtime decision paths live in [RUNTIME_DECISION_GRAPH.md](RUNTIME_DECISION_GRAPH.md); measured backtest results live in [RUNS_AND_GAINS.md](RUNS_AND_GAINS.md).

---

## [Unreleased] - 2026-11-25 (batch 300f - currencies measured for the first time: rejected)

**Change:** Seven majors (EURUSD, GBPUSD, USDJPY, USDCHF, AUDUSD, USDCAD, NZDUSD) put in the input universe and run cold on shipped 6/18 defaults.

**Result:** All seven rows traded; universe gate passed cleanly. Average net per close: -2.28 / -2.69 USD. Six of seven rows negative in both windows. FX heartbeats stop at Friday 20:54 (7,179-7,182 samples vs 10,079 on synthetics).

**Status:** Nothing shipped. Universe stays `Crash 1000 Index,Boom 1000 Index`. The FX question remains a separate experiment (per-trade risk above 1% or lot-floor disabled, run as its own universe).

---

## [Unreleased] - 2026-11-25 (batch 300e - per-symbol override, risk ceiling on the two-row book, scalp verdict)

**Changes:**
- New input `InpSymbolHardSpreadOverridesCsv = "Boom 1000 Index=25000"`; global `InpMaxEntrySpreadPoints` restored **25000 → 15000**.
- `InpMaxDailyRisk` 4.0 → 6.0, `InpMaxPortfolioRisk` 12.0 → 18.0 (`MultiStrategyAutonomousEA.mq5`).
- Scalp engine measured on `Crash+Boom`: **+14.714%** (identical to scalp-off to the cent; 0 `[SCALP-CLOSE]`, 19,897 `[SCALP-SIGNAL-REJECT]` all `gate=spread_vs_atr`). Structurally dead on synthetic spreads.
- Parked `.set` history cleared (15 files, `b291` through `b300e` removed).

**Files:** `Core/Config/SharedEAInputs.mqh` (spread override + symbols), `MultiStrategyAutonomousEA.mq5` (risk ceiling), `Core/Orchestration/EAOrchestrator.mqh` (pre-consensus cutoff), `Core/Trading/TradeMgrPreflight.mqh:127` (send-time spread override), `TradeManager::ValidateExecutionPreflight` (effective spread limit).

**Status:** Shipped. Compile `OVERALL SUCCESS`, 0 errors / 0 warnings, eight programs. Defaults verified by omission: cold 08.01→08.08 **+21.100%**, 193 fills — the 6/18 arm to the cent.

---

## [Unreleased] - 2026-11-24 (batch 300d - second-payer search: `Jump 75` rejected, `Boom 1000` shipped)

**Changes:**
- `Crash + Jump 75` measured and rejected on three windows (-6.28 / -4.17 / -4.88 pp vs Crash-only).
- `Crash + Boom 1000` measured: Boom was vetoed on every entry by `hard_spread_cutoff` (spread 17,185 > 15,000). The knob is `InpMaxEntrySpreadPoints`, not `InpSymbolMaxSpreadPoints`.
- Control: `Crash`-only with `InpMaxEntrySpreadPoints=25000` reproduced the 15,000 arm to the cent (loosening inert for Crash).
- `Crash + Boom @25000`, five windows: **+14.714 / +20.169 / +6.871 / +19.809 / +16.135%** vs Crash-only **+10.837 / +15.786 / +2.614 / +17.682 / +5.134%**. Paired mean **+5.13 pp**, sd 3.41, **t 3.37, 5/5**. Out-of-slice July is **-2.00 pp**.

**Files:** `Core/Config/SharedEAInputs.mqh` (`InpSymbolsToTrade` = `"Crash 1000 Index,Boom 1000 Index"`, `InpMaxEntrySpreadPoints = 25000.0`).

**Status:** Shipped. Compile `OVERALL SUCCESS`, 0 errors / 0 warnings, eight programs.

---

## [Unreleased] - 2026-11-23 (batch 300 - per-symbol attribution back, lot-floor uplift measured, uplift-off A/B)

**Changes:**
- Attribution confirmed working on both builds (no code change).
- Lot floor measured: `[RISK-LOT-FLOOR]` fires 1,484 times in merged window; mean uplift trivial (min-lot symbols 0.0097 → 0.0100, Crash 0.1935 → 0.2000). The gate that moved instead: pre-merge `[RISK-GATE-REJECT]` 894/142/13 → merged 5/0/99, with `[INTENT-STAGE] scaled_lot_not_tradeable` 1,637 replacing them.
- A/B in flight: `InpMinLotRiskMultiplier=1.0` (rejects sub-min-lot scale instead of lifting it).

**Files:** `CandidateBuilder.mqh:593`, `RiskValidationPipeline.mqh:575`.

**Status:** A/B in flight, not yet decided.

---

## [Unreleased] - 2026-11-23 (batch 299b - merged build sweep)

**Changes:**
- HEAD `f0c1bea` recompiled: `OVERALL SUCCESS`, 0 errors / 0 warnings on all eight programs, root EA 70,390 ms (vs 285,687 ms pre-merge).
- Five cold windows on HEAD: **+0.317 / +9.178 / +1.988 / +6.724 / +3.970%**. Arm mean **+4.435%**, sd 3.57 pp, t 2.78, 5/5 positive.
- Paired vs `09e18b0`: mean **-0.682 pp**, sd 1.53, t -1.00. Four windows reproduce pre-merge build to the cent; only 08.01→08.08 moved.
- Mechanism: merged build adds `[RISK-LOT-FLOOR]` and `[INTENT-STAGE]`, drops `[RISK-GATE-REJECT]`.

**Status:** Measured, not shipped. No input changed.

---

## [Unreleased] - 2026-11-23 (batch 299 - post-refactor cold baseline)

**Changes:**
- 242-file refactor measured on commit `09e18b0`. Five cold windows: **+3.728 / +9.178 / +1.988 / +6.724 / +3.970%**. Arm mean **+5.118%**, sd 2.83 pp, t 4.04, 5/5 positive.
- Paired vs Batch 297: mean **-0.227 pp**, sd 2.37, t -0.21, 2/5 positive. The refactor is P&L-neutral within noise.
- Observability corrected same day: nothing was missing (full-file counts show 472 `[EXECUTION-RECEIPT]` / 472 `Trade Closed`).
- Port 3000 hazard: unrelated Node dev server bound the MetaTester agent port, killing two windows and three control runs.

**Status:** Measured, not shipped. Nothing changed.

---

## [Unreleased] - 2026-11-23 (batch 3)

**Changes:**
- MQL5: policy literals named (`#define` constants `RISK_THROTTLE_*`, `PERF_WEIGHT_*`) in `UnifiedRiskManager.mqh`, `PostConsensusValidator.mqh`, `VPINFilter.mqh`; values unchanged.
- Python: `train_common.py` new `report_trained_model` helper; all ten `train_*.py` scripts share predict → IC → pickle → `trained=` tail. `train_oof_stacker` fits ridge meta-learner on validation rows only (removes in-sample base-prediction contamination).

**Status:** Compile-verified (0 errors / 0 warnings, all 8 programs). Not performance-measured.

---

## [Unreleased] - 2026-11-23 (batch 6 - third audit pass)

**Changes (MQL5 correctness fixes):**
- Scratch-close accounting (four sites): `netProfit == 0` now treated as neutral activity (counted as a trade, never as win or loss).
- `ConsensusCache.mqh` + `PositionLifecycleManager.mqh`: cache entry now carries `dominantCluster` (was reading live decision context after cache hit).
- `PosLifecycleVolatility.mqh`: `ManageDynamicSLTP` now tighten-only per leg with side-of-price validity checks.
- `PosLifecycleExit.mqh`: partial profit gate on `POSITION_TP != 0` removed.
- `EnsembleMetaLearner.mqh`: only new slots initialized; heads now per (model, regime); `RemoveModel` shifts parallel stat arrays.
- `NeuralNetworkStrategy.mqh`: deterministic per-instance sequence seed (was seeded from `TimeCurrent()`).

**Status:** Compile-verified. Correctness fixes only, not performance-measured.

---

## [Unreleased] - 2026-11-23 (batch 5 - second audit pass)

**Changes (MQL5 correctness fixes):**
- `TrendEngine.mqh`: `CopyOrFallbackMA` now reverses to newest-first consumer convention.
- `TrendMath.mqh`: `CalculateEmaFallbackSeries` now seeds from SMA of oldest `period` bars and recurses newest-first.
- `AIFeatureVectorBuilder.mqh`: `ComputeRollingZScoreIndicator` now uses `values[period-1]` instead of `values[0]`.
- `OnnxBrain.mqh` + `TransformerBrain.mqh`: `m_temperature` now applied in softmax (logits divided by clamped temperature).
- `MetaLabeler.mqh`: weight init now deterministic per instance (`1000003 + s_initSeq * 7919`).
- `TradeExecutor.mqh`: `RemovePendingAt` now clears `m_pendingCount - 1` instead of one slot past last valid element.

**Status:** Compile-verified. Correctness fixes only.

---

## [Unreleased] - 2026-11-19 (risk correctness and evidence-based cleanup)

**Changes:**
- Specialized fast-scalp, spike-hunter, and grid-recovery entries fail closed when risk authority unavailable; grid risk validation at send boundary.
- Removed unconsumed per-strategy intrabar-eligibility inputs, policy enum/registry metadata, and two helper headers.
- Removed always-allow `CandidateBuilder` authority stub; `CLiveAuthorityResolver` remains sole live authority gate.
- Removed unimplemented safe-mode news/session fields and partial-position tracker with no registration callers.
- Removed three dashboard panels that invented transformer attention, HMM transition probabilities, or pipeline-gate outcomes.
- Removed no-op uncertainty deinitializer, ten orphaned MQL headers, unused root Node manifest/empty lockfile.
- Removed chart-symbol auto-injection; removed validator confidence/confluence inputs that had no gate; removed unreachable spike-validator stub.
- Removed no-op institutional-governance hook, duplicate health monitor, heuristic auto-parking/re-enable path, and its periodic sweep.
- Live risk overrides now update risk manager's operator envelope before tier application.
- Lifecycle loss guard now receives tier-effective daily-risk budget at startup and after live risk changes.
- Live risk-file edits recalculate only when effective operator envelope or supported sizing policy changes.
- Removed dead candidate-builder risk fallback; dynamic risk-tier changes explicitly startup-only.
- Removed EA chart-event callbacks that mistook graphical-object edits for input changes.
- Per-strategy attribution unions contributors across every fill for a position.
- Portfolio and exposure checks exclude candidate's own provisional reservation before adding final trade risk.
- Reservation exclusion uses candidate owner tag; other pending reservations bind per-symbol budget.
- CandidateBuilder enforces minimum-lot permission and uplift ceiling after drawdown and momentum scaling.
- Portfolio position-risk scans fail closed for unpriceable positions.
- Pipeline math engines and indicator handles initialize only when explicit registry flag enabled.

**Status:** Compile-verified (0 errors / 0 warnings on all eight targets). Not performance-measured.

---

## [Unreleased] - 2026-11-23 (remaining-work second batch)

**Changes:**
- `Python/mql5_v2.py`: `prepare_sequences` emits label-end timestamps; `purge_embargo`/`cpcv_folds`/`run_cpcv` are timestamp span-overlap ports.
- `Python/train_common.py` + `write_colab.py`: stacker `meta_X` filled for EVERY row; shape + no-all-zero-row assertions added.
- `Python/safe_pickle.py` (new): whitelisted-globals `SafeUnpickler`; all executable `pickle.load` sites use `safe_pickle_load`.
- `Python/zmq_server.py`: `ZMQ_AUTH_TOKEN` env var — non-heartbeat requests require matching `token` field.
- Dashboard commands actually execute: `IDashCommandHandler` interface; `pause`/`resume` drive `SetEmergencyMode`; `emergency_stop` flattens via `CloseAllPositions`.
- `Core/Scalp/ATRScalpEntry.mqh` + `ATRScalpingEngine.mqh`: scalp entries now go through `CTradeManager.OpenPosition` instead of raw `CTrade::Buy/Sell`.
- `Core/Risk/RiskMarginHealth.mqh` + `RiskValidationPipeline.mqh`: margin check computes true margin DELTA on netting accounts.
- `Python/check_scaler_parity.py` (new): round-trips `save_scaler_to_bin` through `PipelineScaler.mqh` layout.
- Comment hygiene: `Batch NNN`/`Lx-yyy`/`Issue #N` tokens stripped from comments in ~99 .mqh/.mq5 files.

**Status:** Compile-verified. Still open: item 19 literal sweep, item 25 true dedupe, item 27 in-sample base predictions, item 36 per-asset `train_*.py` duplication.

---

## [Unreleased] - 2026-11-22 (remaining-work partial items closed)

**Changes:**
- `Python/data_pipeline.py`: test split purges labels lacking full `vertical_bars` horizon; scaler fits per feature across bars.
- `Python/train_model.py`: CPCV fold models scale per fold on that fold's fit indices only.
- `AIModules/CNeuralTrainingDataManager.mqh`: expired-barrier scan covers exactly vertical-bars horizon after entry.
- `Core/Scalp/ATRScalpExit.mqh`: partial-close latch verifies retcode DONE/DONE_PARTIAL and post-send `POSITION_VOLUME`.
- `Strategies/NYOpenGapStrategy.mqh`: session bars located via `NYOpenFindSessionBar` using each candidate bar's own timestamp.
- `Core/Management/PostConsensusValidator.mqh` + config: ATR crisis ceilings now inputs `InpAtrCrisisCeilingSynthetic`/`InpAtrCrisisCeilingForex`.
- `Core/Engines/AIEngine.mqh` + inputs: external LLM endpoint defaults removed; enabling LLM with no endpoint fails closed.
- Mojibake: all 57 `�?` sequences across 11 .mqh/.mq5 files replaced with `- `.
- Dashboard auth: `EA_DASHBOARD_TOKEN` env var gates write routes via `X-Api-Key`; EA sends it from new `InpDashboardApiKey` input.

**Status:** Compile-verified. Not yet backtest-measured.

---

## [Unreleased] - 2026-11-21 (strategy signal audit fixes)

**Changes (9 files in `Strategies/`):**
- `VolatilityBreakoutStrategy.mqh`: confidence passed to `ValidateWithRiskManager` as 0.0 fixed; `BreakoutWithRetest` now requires retest wick inside ±0.2% band.
- `FVGScalperStrategy.mqh`, `BreakerBlockStrategy.mqh`: stop distances priced off ASK for buys / BID for sells.
- `MarketStructureAnalyzer.mqh`: `HasStructureBreak()` now edge-triggered; `GetATR()` reads shift 1 (closed bar).
- `FVGScalperStrategy.mqh`, `AsianRangeBreakStrategy.mqh`: fast-CHOCH confidence bonus only counts break in trade's own direction.
- `SessionGapDetector.mqh`: NDOG fill state now scans M15 bars (was D1).
- `ICTSessionGapStrategy.mqh`: gap size filters now use dedicated D1 ATR handle.
- DST evaluated on wrong clock in three places (`NYOpenGapStrategy.mqh`, `LiquidityDetector.mqh`, `KillZones.mqh`); now evaluates on GMT with correct UTC transitions.
- `StatisticalArbitrageStrategy.mqh`: now abstains before risk gate (leg2 never sent); spread is log-price difference.
- `MeanReversionStrategy.mqh`: entry reference moved from stale closed-bar close to live ASK/BID; invented TP fallbacks removed.
- `RangeCompressionBreakout.mqh`: dead `m_volumeHandle` removed.
- `SimpleMomentumStrategy.mqh`: `volFloor` now uses `MathMax` instead of `MathMin`.
- `LiquiditySweepStrategy.mqh`, `TurtleSoupStrategy.mqh`: refuse `stopDistance > 3 * ATR`; round-number pip size follows `SYMBOL_DIGITS` parity.

**Status:** Compile-verified (0 errors / 0 warnings). Correctness fixes, not yet backtest-measured.

---

## [Unreleased] - 2026-11-23 (batch 298 - six-symbol trim rejected)

**Change:** Removed `Step Index` and `Jump 25 Index` from eight-symbol universe (six-symbol arm).

**Result:** Six-symbol mean **+4.740%**, sd 3.21 pp vs eight-symbol mean **+5.345%**, sd 2.37 pp. Paired **-0.605 pp**, sd 2.01 pp, t 0.67, 2/5 positive.

**Status:** Rejected. Eight-symbol universe stands. No input changed.

---

## [Unreleased] - 2026-11-23 (batch 297 - three losing rows removed)

**Change:** Removed `EURUSD`, `USDJPY`, `XAUUSD` from factory universe (eleven → eight symbols).

**Result:** Eight-symbol mean **+5.345%**, sd 2.37 pp, t 5.04, 5/5 positive, worst +1.630%. Eleven-symbol mean +3.280%, sd 5.05 pp, 3 of 5, worst -3.583%. Paired mean +2.07 pp, sd 2.91 pp, t 1.59, 4 of 5 positive.

**Status:** Shipped. `Core/Config/SharedEAInputs.mqh` `InpSymbolsToTrade` = `"Boom 1000 Index,Crash 1000 Index,Jump 25 Index,Jump 75 Index,Step Index,GBPUSD,AUDUSD,BTCUSD"`.

---

## [Unreleased] - 2026-11-23 (batch 296 - out-of-regime test)

**Change:** Ran shipped configuration on two August windows (outside 2026-09/10 slice).

**Result:** 08.01→08.08 **-3.583%**, 08.08→08.15 **+7.177%**. Both decided by `Crash 1000` (+54.39 vs +850.02). Seven-window record: mean +6.038%, sd 6.96 pp, t 2.30, 6 of 7 positive, worst -3.583%.

**Status:** No input changed. Edge is real but regime-bound; single-instrument concentration.

---

## [Unreleased] - 2026-11-24 (batch 295 - daily risk ceiling widened and rejected)

**Change:** `InpMaxDailyRisk=8.0`, `InpMaxPortfolioRisk=24.0` (1% per trade held).

**Result:** Wide-ceiling arm mean **+3.340%**, sd 5.36 pp, worst -5.519%, 4/5. Paired deltas mean **-5.26 pp**, sd 7.32 pp, t -1.61, 4/5 negative.

**Status:** Rejected. `InpMaxDailyRisk=4.0`, `InpMaxPortfolioRisk=12.0` stay.

---

## [Unreleased] - 2026-11-24 (batch 294 - risk dial tested)

**Change:** Three risk settings on two windows: 1%/4%/12% (factory), 2%/8%/24%, 4% per trade only.

**Result:** Factory mean **+8.79%**, 2× mean **-2.42%**, 4× per trade mean **+4.86%**. Raising risk re-selects the trade set instead of scaling it.

**Status:** Rejected. `InpMaxRiskPerTrade=1.0`, `InpMaxDailyRisk=4.0`, `InpMaxPortfolioRisk=12.0` stay.

---

## [Unreleased] - 2026-11-23 (batch 293 - trim cleared its bar)

**Change:** Removed both Volatility indices from factory universe (full → trimmed, eleven symbols).

**Result:** Trimmed arm mean **+7.734%**, sd 6.74 pp, t 2.57, worst -0.599%. Paired deltas mean **+6.558 pp**, sd 5.39 pp, t 2.72, 5/5 positive.

**Status:** Shipped. `InpSymbolsToTrade` drops `Volatility 25 Index` and `Volatility 75 Index`.

---

## [Unreleased] - 2026-11-23 (batch 292 - sixth window lost)

**Change:** Sixth window (10.06→10.13) lost **-269.61 (-2.696%)**, halving the t-statistic. Trim motivated by this loss but not yet shipped.

**Status:** Measured, not shipped. Trim has 3 paired windows, not the 5-6 needed.

---

## [Unreleased] - 2026-11-23 (batch 291 - scalper off, five windows, shipped as default)

**Change:** `InpEnableScalpEngine = false` in `Core/Config/SharedEAInputs.mqh`. Added `[ENGINE-CLOSE]` line for engine-managed closes.

**Result:** Five consecutive cold windows: **+3.811 / +0.635 / +1.489 / +2.640 / +1.009%**. Mean **+1.917%**, sd 1.30 pp, t 3.30, 5/5 positive.

**Status:** Shipped as factory default.

---

## [Unreleased] - 2026-11-23 (batch 290 - repaired build measured)

**Change:** Batch 289 build run cold: **-258.77 (-2.588%)** on 2,265 fills vs Batch 288 build **+98.29 (+0.983%)** on 849 fills. Single-variable A/B with scalper off: **+381.07 (+3.811%)** on 270 fills.

**Status:** Measured. Scalper-on build is negative expectancy; scalper-off arm is positive but single window only.

---

## [Unreleased] - 2026-11-23 (batch 289 - indicator-handle defect fixed)

**Changes:**
- `IndicatorManager.mqh`: `IndicatorManagerGuardedRelease()` prevents handle number reuse; idle sweeps removed.
- Correlation slots now start `CORR_ENGINE_UNKNOWN` instead of 1.0.
- Portfolio risk: request's stop now passed to `ValidatePortfolioRisk`.
- Fast scalp geometry: per-symbol stop = max(1.5×ATR(14,M1), 4×spread, 1.5×stop level); breakeven/trailing 0.6R/0.1R/0.6R of position's own stop.
- Equity-curve modifier now arms 0.25% under EMA, clears at EMA.
- Volatility model no longer returns veto band.
- Shutdown: `PersistStrategyScoreboard()` and `PersistRiskRuntimeState(true)` now run first.

**Status:** Source-level changes; needs MetaEditor verification and cold window before counting as result.

---

## [Unreleased] - 2026-11-23 (batch 288 - one measured lever shipped)

**Change:** `InpMinLiveVoters` changed from 2 to 1 in `Core/Config/SharedEAInputs.mqh`.

**Result:** Six cold windows, one-voter mean +0.46% (sd 0.92 pp, 3 wins of 6) vs committee mean -1.31% (4 losses of 4). Paired delta +1.80 pp, t 2.6, p ≈ 0.08. Rejects down from 2,054-2,819 per window to 139-227.

**Status:** Shipped. Committee remains selectable at 2.

---

## [Unreleased] - 2026-11-23 (batch 287 - streak sizing rejected)

**Change:** Per-symbol streak counter applied to size instead of entry (`InpSymbolStreakRiskScale` default 1.0 = off).

**Result:** Two windows: +1.40 pp, then -5.68 pp. Mean -2.14 pp.

**Status:** Rejected. Ships at default 1.0 (off).

---

## [Unreleased] - 2026-11-23 (batch 286 - loss-streak brake rejected)

**Change:** Per-symbol loss-streak brake (`InpSymbolLossStreakLimit` default 0 = off).

**Result:** One window: breaker 2 losses / 12 h = **-376.72 (-3.767%)** vs control **+98.29 (+0.983%)**. -4.75 pp.

**Status:** Rejected. Ships at default 0 (off).

---

## [Unreleased] - 2026-11-23 (batch 285 - money is two instruments)

**Finding:** P&L of a 7-day window is set by 11-13 closes of `Volatility 75 Index` at ~±23 USD each plus 65-68 closes of `Crash 1000 Index`. The 200+ closes of the two big strategy families are noise (~0.15-0.45 USD per close).

**Status:** Attribution finding, no input changed.

---

## [Unreleased] - 2026-11-23 (batch 284 - six windows, first real distribution)

**Change:** Six adjacent cold windows, two arms (one voter vs committee).

**Result:** One-voter mean +0.46%, sd 0.92 pp, 3 wins of 6, t 1.2. Committee mean -1.31%, 4 losses of 4, t -2.8. Paired mean +1.80 pp, sd 1.38 pp, t 2.6, p ≈ 0.08.

**Status:** Evidence recorded; `InpMinLiveVoters=1` remains an ini value, not a shipped default.

---

## [Unreleased] - 2026-11-23 (batch 283 - thresholds mostly inert)

**Change:** Four knobs tested one at a time: `InpSingleVoterFloor` 0.70→0.65 (identical), `InpQuorumProfile` BALANCED→AGGRESSIVE (identical, confirmed in force), support floors/quorum threshold (identical), `InpMinLiveVoters` 2→1 (**+98.29 (+0.983%)**).

**Finding:** `EAOrchestrator` sets both `minQuorum` and `intrabarMinQuorum` from `InpMinLiveVoters`, but `ApplyQuorumProfile` never writes `intrabarMinQuorum`. Every reject was intrabar, so the profile was changing values nothing reads.

**Status:** Documented; defaults unchanged.

---

## [Unreleased] - 2026-11-23 (batch 282 - determinism fix)

**Change:** `Core/Utils/EAClock.mqh` → `EAClockMs()` returns `TimeCurrent()*1000` under `MQL_TESTER` and `GetTickCount()` otherwise.

**Result:** Before fix: run 1 +5.034%, run 2 -4.889% (10 pp spread). After fix: both runs -0.745% (0.00 pp spread).

**Status:** Shipped. This is the measuring instrument that made everything after it measurable.

---

## Historical Batches (102–281)

Dated entries for Batches 102–281 are archived in [`docs/changelogs_batch102-169.md`](docs/changelogs_batch102-169.md) and [`docs/changelogs_old.md`](docs/changelogs_old.md). These contain architecture-level descriptions of batch changes; current architectural truth is in [SYSTEM_STRUCTURE.md](SYSTEM_STRUCTURE.md).
