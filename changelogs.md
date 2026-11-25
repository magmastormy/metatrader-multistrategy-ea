# Changelog

Batches 282 and later, newest first. Batches 281 and earlier are archived - see the pointer list at the bottom.
`RUNS_AND_GAINS.md` holds the consolidated measured record; `REMAINING_WORK.md` holds what is still open.

## [Unreleased] - 2026-11-25 (batch 300f - currencies measured for the first time: rejected)

### Seven majors, cold, on the shipped 6/18 defaults
`InpSymbolsToTrade = "EURUSD,GBPUSD,USDJPY,USDCHF,AUDUSD,USDCAD,NZDUSD"`, tester chart `EURUSD M15`, `Model=1`,
nothing else changed. Universe gate passed cleanly: `[SYMBOL-VALIDATION] Accepted: 7 | Rejected: 0`, avg tick
volume 66,963-130,805 per row, so this is a strategy result, not a data result.

| window | currencies | synthetics (`Crash+Boom`, same defaults) | gap |
|---|---|---|---|
| 08.01 to 08.08 | **-4.632%** (9,536.78), 203 fills | +21.100% (12,110.05), 193 fills | -25.73 pp |
| 09.22 to 09.29 | **-5.615%** (9,438.49), 209 fills | +39.266% (13,926.57), 194 fills | -44.88 pp |

Six of seven rows negative in both windows (08.01: USDJPY -246.55, GBPUSD -144.46, EURUSD -43.19, USDCAD -41.85,
USDCHF -33.92, NZDUSD -0.66, AUDUSD +47.41).

### The loss is per trade, not per signal
Fill count is healthy (203 / 209 vs 193 / 194 on the synthetic book) and the spread gate is not the constraint.
Average net per close **-2.28 / -2.69** USD. The book trades at the lot floor throughout - 371 and 536
`[RISK-LOT-FLOOR]` lines - because a 1% risk ask at a 3x minimum-lot multiplier cannot be sized on 0.01 FX lots
with FX-sized stops on a 10k account. On Crash/Boom that floor is a feature (large point increments per minimum
lot); on majors it collects a couple of dollars per trade against a 1-minute-OHLC modelled spread.

### Shape caveat
FX heartbeats stop at Friday 20:54, so the slice is 7,179-7,182 samples versus 10,079 on synthetics. FX numbers
must be compared heartbeat-normalised, never as raw totals.

### FX sizing arms: per-trade risk 2% and floor off - both neutral-to-negative
| window | 1% shipped | 2% per trade | floor off (`InpMinLotRiskMultiplier=1.0`) |
|---|---|---|---|
| 08.01 to 08.08 | -4.632% (203 fills) | **-5.830%** (211) | **-4.632%** (203), identical to the cent |
| 09.22 to 09.29 | -5.615% (209 fills) | **-5.487%** (208) | **-5.615%** (209), identical to the cent |

The lot floor is inert on FX - it logged 371 / 522 `[RISK-LOT-FLOOR]` lines and disabling it changed nothing (same
fills, closes, net, balance). Doubling per-trade risk moves the two windows in opposite directions (-1.20 / +0.13 pp)
and both stay negative, because the 6/18 ceilings clamp concurrent size. Wall-clock oddity: the floor-off 09.22 arm
took 68 min / 464 MB journal versus 29 min on the baseline arm of the same window; cause not established, trades
identical. Conclusion: the FX loss is signal quality plus modelled 1-minute spread, not position size; currencies
stay out of the universe.

### Nothing shipped
Universe stays `Crash 1000 Index,Boom 1000 Index`. The remaining FX question is a different experiment: per-trade
risk above 1% or lot-floor disabled, run as its own universe. Not run here.

## [Unreleased] - 2026-11-25 (batch 300e - per-symbol override, risk ceiling on the two-row book, scalp verdict)

### The 25,000 loosening was replaced by a per-symbol override, and it reproduced the arm to the cent
New input `InpSymbolHardSpreadOverridesCsv = "Boom 1000 Index=25000"` (`Core\Config\SharedEAInputs.mqh`, right
after `InpSymbolsToTrade`); global `InpMaxEntrySpreadPoints` restored **25000 -> 15000**. Cold `08.01->08.08`,
nothing else changed: **+14.714%** (10,000 -> 11,471.44), 165 fills, Boom 31 closes +705.38, Crash 134 closes
+766.06, min 9,966.75 / max 11,485.28 — identical to the 300d 25,000 arm including all 268 `[RISK-LOT-FLOOR]` lines.

Two gates had to learn the override, and only one of them was obvious:
- `EAOrchestrator.mqh` (pre-consensus cutoff, `MathMax(hardSpreadCutoffPoints, symbolEntrySpreadLimit)`, CSV parsed
  case-insensitively with an invalid-entry fallback to the global value; `[VALIDATOR-CONFIG]` now prints
  `symbol_limit=`);
- `TradeMgrPreflight.mqh:127` (send-time). Opening only the first one still gave **0 Boom closes** — 202
  `[INTENT-STAGE] Boom ... outcome=REJECTED reason=Success` 17 ms after submit. The wrapper
  `TradeManager::ValidateExecutionPreflight` now passes `EffectiveEntrySpreadLimit(symbolName)` instead of
  `m_maxEntrySpreadPoints`; new members `m_symbolSpreadOverridesCsv` / `SetSymbolSpreadOverrides(csv)`, wired at
  `EAOrchestrator.mqh` next to `SetExecutionCostLimits`.
- Mapping: `MultiStrategyAutonomousEA.mq5` keeps its own duplicated input->config block (it does not call
  `PopulateSharedOrchestratorConfig`), so the new field had to be assigned there as well. This is audit item 35
  biting for real, a second time.

### `InpMaxDailyRisk` 4.0 -> 6.0, `InpMaxPortfolioRisk` 12.0 -> 18.0 (`MultiStrategyAutonomousEA.mq5`)
1% per trade unchanged, only the concurrency ceiling moved, four cold paired windows vs 4/12:
**+6.386 / +2.899 / +3.249 / +11.622 pp**, mean **+6.04 pp**, sd 4.04, **t 2.99**, **4/4**.
Mechanism from the journal: at 4% the engine refused entries with
`[RISK-DAILY-LIMIT] reason=daily_risk_would_exceed effective=3.97% + new=1.00% >= limit=4.00%`; at 6% the same
signals became Boom closes (31 -> 42, 42 -> 50, 28 -> 38). Batch 294 measured the same lever at 8/24 as **-5.26 pp**
on the eight-symbol book — the book changed, so the lever changed meaning.

### Boom outside the slice: +20.66 / +0.80 / -2.00 pp
`09.22->09.29`: `Crash+Boom` **+36.017%** (171 fills, Boom +1,407.71 / 42) vs fresh `Crash`-only control
**+15.353%** (165). `10.13->10.20`: **+9.171%** (169, Boom +178.87 / 28) vs **+8.368%** (175). July week stays
**-2.00 pp**. Out-of-slice mean +6.49 pp, sd 12.36, 2/3.

### Month-length window `07.01->08.01`: **+66.520%**, Boom +2,758.92 / 153 closes
834 fills, 99 min wall, min 9,986.33 / max 17,226.43. No 31-day `Crash`-only control exists, so this is not
attribution; it is evidence that the July week's loss does not compound, and Boom's own line is the largest
single-row contribution measured so far.

### Scalp engine: structurally dead on `Crash+Boom`, zero effect on P&L
`InpEnableScalpEngine=true`, cold `08.01->08.08`: **+14.714%**, 165 fills — identical to scalp-off to the cent.
0 `[SCALP-CLOSE]`, 19,897 `[SCALP-SIGNAL-REJECT]`, **all** `gate=spread_vs_atr` (Boom 10,008 / Crash 9,887). The
engine initialises and scans, and never produces a fillable signal, because synthetic quotes are far too wide
against ATR. No input changed; scalp needs a gate change or a non-synthetic universe, and `backtest_b290_scalp2.ini`
as written (`XAUUSD,Step Index`) is still unrun.

### Verified, built, and left parked clean
- Compile `OVERALL SUCCESS`, 0 errors / 0 warnings, eight programs (root EA 75,688 ms), after `sync_files.ps1` + `sync_and_compile.ps1 -All`.
- Defaults verified by omission (`b300e_final_w1.ini` carries only `InpQuorumProfile`, `InpMinLiveVoters`,
  `InpMaxRiskPerTrade`): cold `08.01->08.08` **+21.100%** (10,000 -> 12,110.05), 193 fills, Boom 42 closes
  +1,131.48, Crash 151 closes +978.57 — the 6/18 arm to the cent.
- Parked `.set` history cleared: every `MultiStrategyAutonomousEA.set.parked_*` (15 files, `b291` through `b300e`)
  removed; the Tester profile holds one `.set`.

### Harness note: a duplicate `.ini` key is a null arm, not a neutral one
MT5 takes the **first** occurrence of a duplicate key. The first `risk6_w1` ini carried `InpMaxDailyRisk=4.0`
followed by `=6.0`; the window returned +14.714%, exactly the 4% baseline, and the journal showed `limit=4.00%`.
Re-running after de-duplication gave +21.100%. All `Tools\b300e_*.ini` were then scanned key-by-key.

## [Unreleased] - 2026-11-24 (batch 300d - second-payer search: `Jump 75` rejected, `Boom 1000` shipped)
### The first answer was a gate, not a signal
Three cold `Crash + Boom 1000` windows reproduced the `Crash`-only arm **to the cent** (+10.837 / +2.614 / +4.075)
with zero Boom closes. The row was neither missing nor unscanned - `Boom 1000 Index` appears ~50,000 lines per
journal - it was vetoed on every candidate entry:
`[SIGNAL-REJECTED] Boom 1000 Index | reason=hard_spread_cutoff | spread_points=17185.0 > 15000.0` (1,077 vetoes per
window). Boom's quote is a constant ~17,185 points, so it can never pass a 15,000 send-time guard.

### The knob was `InpMaxEntrySpreadPoints`, not `InpSymbolMaxSpreadPoints`
`InpSymbolMaxSpreadPoints` (1500, `SharedEAInputs.mqh:120`) only feeds the universe builder (10x allowance for
synthetic indices). Raising it to 20,000 changed nothing - the log still printed `15000.0`. The gate is
`validatorHardSpreadCutoff = MathMax(m_config.hardSpreadCutoffPoints, m_config.maxEntrySpreadPoints)`
(`EAOrchestrator.mqh:1956`), i.e. `InpMaxEntrySpreadPoints` (default 15000, `SharedEAInputs.mqh:325`). Two
windows of that arm were discarded as invalid data.

### A wider gate had to be proved inert before it could explain anything
`Crash`-only with `InpMaxEntrySpreadPoints=25000`, cold, same windows: `08.01` **+10.837%** (168 fills, min 9,997.40 /
max 11,107.95) and `09.01` **+2.614%** (164 fills, min 9,755.57 / max 10,261.75) - the 15,000 numbers to the cent.
`Crash` never quotes near even 15,000, so the loosening has no effect on the payer and every delta below is Boom's.

### `Crash + Boom 1000` @25000 - five windows, all positive

| window | arm | Boom own net | `Crash` only | paired |
|---|---|---|---|---|
| 08.01 -> 08.08 | **+14.714%** (11,471.44 / 165 fills) | +705.38 / 31 closes | +10.837% | **+3.88 pp** |
| 08.08 -> 08.15 | **+20.169%** (12,016.89 / 170) | +376.54 / 34 | +15.786% | **+4.38 pp** |
| 09.01 -> 09.08 | **+6.871%** (10,687.08 / 167) | +623.66 / 44 | +2.614% | **+4.26 pp** |
| 09.15 -> 09.22 | **+19.809%** (11,980.91 / 162) | +764.13 / 39 | +17.682% | **+2.13 pp** |
| 10.06 -> 10.13 | **+16.135%** (11,613.45 / 175) | +909.36 / 38 | +5.134% | **+11.00 pp** |
| 07.01 -> 07.08 (out of slice) | +2.075% (10,207.47 / 181) | -104.62 / 35 | +4.075% | **-2.00 pp** |

Paired mean **+5.13 pp**, sd 3.41, **t 3.37**, **5 of 5** in slice; one out-of-slice window disagrees. Boom's mean
close is +22-24 USD, and it costs only 31-44 closes per window, so the payer's own throughput is unharmed (134-146
`Crash` closes against 157-186 alone).

### `Crash + Jump 75` was measured first and is dead
+4.553 / -1.559 / -0.805 % against `Crash`-only +10.837 / +2.614 / +4.075 % -> **-6.28 / -4.17 / -4.88 pp**. It is
throughput, not the row's own P&L: the payer's closes drop to 92/94/96 and `Crash` goes net-negative (-127.29, -91.86)
in two of the three windows. `Jump 75` stays out.

### Shipped (compile `OVERALL SUCCESS`, 0 errors / 0 warnings on all eight programs)
- `Core\Config\SharedEAInputs.mqh` -> `InpSymbolsToTrade = "Crash 1000 Index,Boom 1000 Index"`, with the five-window
  block and the rejected arm written above it.
- `Core\Config\SharedEAInputs.mqh` -> `InpMaxEntrySpreadPoints = 25000.0`, with the reason (Boom ~17,185 constant)
  and the inert-for-`Crash` control result written above it.
- Default proved by omission: `.set` parked as `.parked_b300d`, ini carrying neither input, cold `08.01->08.07` ->
  **+14.714%** (10,000 -> 11,471.44), 165 fills, Boom 31 closes +705.38, `Crash` 134 closes +766.06 - identical to
  the arm to the cent.

### Risk this ships with, stated plainly
The send-time disaster-quote backstop moves 15,000 -> 25,000 points (~+67%). Only two symbols are in the universe,
so Boom is the sole beneficiary, but that is an exposure argument, not a safety one. A per-symbol spread override
is strictly better and is not built - it is the first open item.
## [Unreleased] - 2026-11-23 (batch 300 - per-symbol attribution back, lot-floor uplift measured, uplift-off A/B)
### Attribution works on both builds (no code change)
- Full-file tag scan of the two `w1` journals: `[EXECUTION-RECEIPT]` and `Trade Closed ... Net Profit:` are
  present in both (472 / 472 merged, 404 / 403 pre-merge). The print sites are unconditional and async sending is
  off by default, so nothing needed restoring - the earlier claim was a tail-read error and is corrected in the
  Batch 299 entry above.
- Last-run close sums equal the heartbeat delta to the cent in both arms (+372.81 and +31.72), so this is
  reconciliation, not a lower bound.

### Why the August open moved 3.4 pp: Crash exposure, not the lot floor's size
`08.01 -> 08.08`, same window, same inputs, merged vs pre-merge:

| arm | fills | closes | close net | `Crash 1000` | `Jump 75` | `Jump 25` | `Step` | `Volatility 75` |
|---|---|---|---|---|---|---|---|---|
| pre-merge `09e18b0` | 256 | 256 | **+372.81** | **+489.07 / 106 closes** | -70.76 / 96 | -91.12 / 41 | -25.96 / 6 | **+72.77 / 3** |
| merged `f0c1bea` | 215 | 215 | **+31.72** | **+222.44 / 74 closes** | -88.26 / 89 | -62.19 / 35 | -38.92 / 9 | **0 / 0** |

The loser rows are flat across arms (-190.36 vs -190.87). The whole delta is one row: `Crash 1000` took **106**
closes for **+489.07** and now takes **74** for **+222.44**, and `Volatility 75` disappeared entirely.
`08.01`'s gain is Crash throughput, so the merged build's change is a throughput cut on the one instrument that pays.

### The lot floor is real but small; the gate that replaced it is not
- `[RISK-LOT-FLOOR]` fires **1,484** times in the merged window: `Jump 25` 502, `Jump 75` 490, `Crash 1000` 273,
  `GBPUSD` 127, `AUDUSD` 66, `Step` 26. Mean uplift is trivial - min-lot symbols `0.0097 -> 0.0100`,
  `Crash 1000` `0.1935 -> 0.2000` (3.4%), `Step` `0.0959 -> 0.1000`. So the uplift is essentially the old
  min-lot rounding, capped at 1.10x of the resolved size, and it does **not** explain the fill drop.
- What moved is the gate: pre-merge `[RISK-GATE-REJECT]` = **894 `final_lot_validation` + 142
  `symbol_budget_lot_cap` + 13 `correlation_reduce_below_min_lot`**; merged = **5 `final_lot_validation` + 99
  `correlation_reduce_below_min_lot`**, with `[INTENT-STAGE] scaled_lot_not_tradeable` **1,637** instead. The
  merged build converts "reject because the scaled lot is untradeable" into a trade at min lot - 1,637 candidates
  became 1,484 min-lot fills, which consumes daily budget on the small rows and leaves less room for the
  `Crash 1000` tickets that pay.
- `[ENTRY-GATE] cycle_send_cap` is 33 merged vs 34 pre-merge, so this is not a send-rate cap.

### A/B in flight: `InpMinLotRiskMultiplier=1.0`
- `Tools\backtest_b300_floor1_w1.ini` (`08.01 -> 08.08`) and `_w3.ini` (`09.01 -> 09.08`), otherwise identical to
  `b299_cold` inis. With the cap at 1.0 the pipeline rejects any sub-min-lot scale instead of lifting it
  (`CandidateBuilder.mqh:593`, `RiskValidationPipeline.mqh:575`), which is how to test whether the uplift trades
  are the ones crowding out Crash.
# Changelog

All notable changes to the `metatrader-multistrategy-ea` project are documented in this file.

This file starts at **Batch 170**. The previous history is preserved unchanged:
- Batches 140–169 (2026-08 → 2026-10): [`docs/changelogs_batch102-169.md`](docs/changelogs_batch102-169.md) (the file name overstates the range)
- Batch 101 and earlier: [`docs/changelogs_old.md`](docs/changelogs_old.md)

## [Unreleased] - 2026-11-23 (batch 299b - merged build sweep)

### HEAD verification and the current factory distribution
- HEAD `f0c1bea` (refactor `09e18b0` + merge of `995cb3b` / `0c7260c` / `7c712fe`) recompiled:
  `sync_and_compile.ps1 -All` -> `OVERALL SUCCESS`, **0 errors / 0 warnings** on all eight programs,
  root EA **70,390 ms** (vs 285,687 ms pre-merge - the debloat is real), Testing 80,666 ms.
- Five cold windows on HEAD, same setup as Batch 299: `08.01` **+0.317%** (10,031.72),
  `08.08` **+9.178%** (10,917.78), `09.01` **+1.988%** (10,198.79), `09.15` **+6.724%** (10,672.39),
  `10.06` **+3.970%** (10,397.04). Arm: mean **+4.435%**, sd 3.57 pp, t 2.78, 5/5 positive,
  worst +0.317%, best +9.178%.
- Paired vs `09e18b0`: `-3.411 / 0 / 0 / 0 / 0` pp -> mean -0.682 pp, sd 1.53, t -1.00.
  **Four windows reproduce the pre-merge build to the cent**; only `08.01→08.08` moved.
- Mechanism (tag diff of the two w1 journals): the merged build adds `[RISK-LOT-FLOOR]`
  (`lot 0.1815 -> 0.2000 | uplift=1.10x <= cap=3.00x`) and `[INTENT-STAGE]`, and drops
  `[RISK-GATE-REJECT]`. The remote risk work replaced the hard reject with a capped min-lot uplift -
  the "bind on lot size" lever, but as an uplift with a 3x ceiling rather than a per-symbol cap.
- Scoreboards archived as `Tools/artifacts/scoreboards/scoreboard_b299b_w1..w5.csv`; journals as
  `journal_b299b_w1..w5` in the agent temp dir.

### Harness hardening for this sweep
- Per-launch port guard added to the driver: `netstat -ano`, kill only a `node` holder of
  `127.0.0.1:3000`, re-check before every window launch (the dev server respawned at least twice: pids
  7124, 100, 4568). Scoreboards are now archived **after** the run, not before, so the file name matches
  the run that produced it.
## [Unreleased] - 2026-11-23 (batch 299 - post-refactor cold baseline)

### Measurement - the rebuild still pays, within noise (no code change, nothing shipped)
- Five cold windows on the refactor commit **`09e18b0`** (the binary under test was compiled from that
  tree at ~12:35; the `origin/main` merge `f0c1bea` landed at 13:39 **after** the build and brought 153
  files including MQL5 strategy sources, so those are not in the measured binary - see
  RUNS_AND_GAINS.md Batch 299), factory defaults
  unchanged (8 symbols, `InpMaxRiskPerTrade=1.0`, `InpMaxDailyRisk=4.0`, `InpMaxPortfolioRisk=12.0`,
  `InpQuorumProfile=1`, `InpMinLiveVoters=1`, scalper off), `Volatility 75 Index` M15, `Model=1`,
  deposit 10,000, four state files cleared per launch, `MultiStrategyAutonomousEA.set` parked as
  `.set.parked_b299`:
  `08.01` **+3.728%** (10,372.81), `08.08` **+9.178%** (10,917.78), `09.01` **+1.988%** (10,198.79),
  `09.15` **+6.724%** (10,672.39), `10.06` **+3.970%** (10,397.04).
  Arm: mean **+5.118%**, sd 2.83 pp, t 4.04, 5/5 positive, worst +1.988%, best +9.178%.
  Paired vs Batch 297 same windows: `+2.098/+1.902/-3.693/-0.720/-0.722` pp -> mean -0.227 pp,
  sd 2.37, t -0.21, 2/5 positive. Conclusion: neutral, not an improvement.
- `.ini` set added: `Tools/backtest_b299_cold_w1..w5.ini` (Batch 297 trim-8 windows, `Report=backtest_b299`).

### Verification
- `.\sync_files.ps1` -> 44 Python files updated.
- `.\sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 900` -> `OVERALL SUCCESS`, **0 errors /
  0 warnings on all eight programs** (root EA 285,687 ms, Testing 307,721 ms, Exporter 90,029 ms).
  Compile cost is ~4x the Batch 297 build (74,406 ms), consistent with the larger engine.

### Observability: nothing was broken - the earlier "regression" was a bad tail read (corrected same day)
- A full-file scan of the two `w1` journals counts `[EXECUTION-RECEIPT]` **472** and `Trade Closed ...
  Net Profit:` **472** on the merged build, and **404 / 403** on `09e18b0`. Both lines were never
  missing; the earlier claim came from reading a tail slice, not the file. `Core\Trading\TradeManager.mqh:1428`
  prints the receipt and `Core\Management\StrategyMgrTradeFeedback.mqh:217` prints the close, both
  unconditionally on the `OpenPosition` -> `ExecuteMarketOrder` path (async mode is off by default:
  `TradeManager.mqh:293` `m_useAsyncMode(false)`), so no code change is needed.
- Attribution reconciles **exactly**: last-run close net equals the heartbeat delta to the cent in both
  arms (+372.81 and +31.72), so per-symbol dollars are a measurement here, not a lower bound.

### Test-harness hazard (new, cost 2 windows + 3 control runs)
- An unrelated supervised Node dev server bound `127.0.0.1:3000`, the local MetaTester agent port.
  Symptom: `automatic testing started`, then `last test passed with result "some error after pass
  finished" in 0:00:00.000` after ~32 s; agent log shows `login` -> `tester forced to close`, no EA
  lines. A known-good ini also failed, which is how the ini was excluded. Fix: check
  `netstat -ano | findstr :3000`, kill any non-`metatester64` holder, confirm `metatester64` owns the
  port, then launch - **before every launch**, because the server respawns.
## [Unreleased] - 2026-11-23 (batch 3)

### MQL5 - policy literals named, behavior identical
- `Core/Risk/UnifiedRiskManager.mqh` - the daily/portfolio risk-throttle
  utilization ladder and per-symbol performance weights are now named
  `#define` constants (`RISK_THROTTLE_*, PERF_WEIGHT_*`) with audit notes;
  values unchanged.
- `Core/Management/PostConsensusValidator.mqh` - ATR warning band and
  decision-class quality floors are now named constants; values unchanged.
- `Core/Risk/VPINFilter.mqh` - toxicity bands and regime multipliers are
  now named constants; values unchanged.

### Python - stacker/trainer consolidation continued
- `Python/train_common.py` - new `report_trained_model` helper.
- All ten `train_*.py` scripts (generic + per-asset + Deriv family) now
  share the predict -> IC -> pickle -> `trained=` tail via
  `report_trained_model`; asset/family hyperparameters remain local.
- `train_common.train_oof_stacker` (and both generated Colab cells) now
  fit the ridge meta-learner on validation rows only
  (`fit_idx = arange(n_tr, n_total)`), removing the largest in-sample
  base-prediction contamination. Remaining: base models can still score
  rows overlapping their own training ranges (needs training-range
  metadata or true OOF predictions - item 27 stays partial).

Compile-verified (0 errors / 0 warnings, all 8 programs). Not
performance-measured: needs paired cold-window backtests before any
P&L claim.

## [Unreleased] - 2026-11-23 (batch 6 - third audit pass)

### MQL5 - correctness fixes from a deep-dive pass
- **Scratch-close accounting (four sites).** A breakeven close (`netProfit == 0`)
  was counted as a LOSS everywhere outcomes are classified: `RecordSymbolClose`
  fed the per-symbol loss-streak brake, `CStrategyPerformanceHealth::
  UpdatePerformance` incremented failCount/consecutiveLosses and dragged the
  health score, `CStrategyHealthMonitor::UpdateRecentPerformance` decayed the
  rolling win-rate, `CTradeStatsTracker::RecordTrade` bucketed it as failed
  (and derived the outcome from GROSS profit while netting commission/swap -
  a net loser could count as a win), and `CLiveAuthorityResolver::
  RecordOutcome` counted it against win-rate/consecutive-losses for AI
  authority promotion. All five now treat `== 0` as neutral activity:
  counted as a trade, never as a win or a loss.
- `Core/Cache/ConsensusCache.mqh` + `PositionLifecycleManager.mqh` - the SRE
  structural-invalidation check read the manager's LIVE decision context after
  a cache hit, pairing a <=1s-old cached signal with whatever evaluation ran
  most recently (e.g. the new-bar entry scan) - wrong `dominantCluster`,
  wrong structural exits. The cache entry now carries `dominantCluster`.
- `Core/Management/PosLifecycleVolatility.mqh` - `ManageDynamicSLTP`
  rewrote SL/TP anchored to OPEN price on every pass, in BOTH directions:
  it could move a stop AWAY from price (loosening protection the
  breakeven/trailing managers had already tightened) and push TP farther
  out. Now tighten-only per leg, with side-of-price validity checks.
- `Core/Management/PosLifecycleExit.mqh` - partial profit taking was gated
  on `POSITION_TP != 0` although TP is never used in the calculation; any
  position without a TP could never take its partial. Gate removed.
- `AIModules/EnsembleMetaLearner.mqh` - `EnsureModelArrays()` ran on every
  `ProcessMarketData` call and unconditionally zeroed every model's rolling
  results ring and `ArrayInitialize`'d the whole regime-performance buffer
  while leaving the count arrays intact: rolling win-rate/avg-win/avg-loss
  were recomputed over zeroed slots (permanently corrupted -> broken model
  weights and Kelly fractions), and the adaptive regime multiplier could
  only ever read zeros (dead feature pinned at 1.0). Now only NEW slots are
  initialized. Also: the per-regime ring used one head per MODEL shared
  across regimes (scattered writes the linear reader never saw) - heads are
  now per (model, regime); and `RemoveModel` now shifts all parallel stat
  arrays to match `CArrayObj::Delete`'s element shift (stats previously
  attached to the wrong models after any removal).
- `AIModules/NeuralNetworkStrategy.mqh` - constructor seeded the weight-init
  LCG from `TimeCurrent()`, so every cold run initialised different neural
  weights and emitted different early predictions on identical ticks (same
  defect class fixed earlier in MetaLabeler). Now a deterministic
  per-instance sequence seed.

Compile-verified: `sync_and_compile.ps1 -All -KeepLog` -> OVERALL SUCCESS,
0 errors / 0 warnings on all eight programs. Correctness fixes only - not
performance-measured. Note: pyramiding / dynamic-SLTP / partial-profit
taking have no `Configure*` callers and remain dormant; the fixes above
keep them correct for when they are wired.

## [Unreleased] - 2026-11-23 (batch 5 - second audit pass)

### MQL5 - correctness fixes from a fresh audit sweep
- `Core/Engines/TrendEngine.mqh` - `CopyOrFallbackMA` copied 5 bars via
  `CopyBuffer` into non-series arrays, which land OLDEST-first, while
  `CTrendStrength`/`CalculateTrendAngle` and the EMA fallback all expect
  `[0]`=newest. Trend strength/angle ran on a reversed window whenever the
  indicator path succeeded (the common case); the CopyBuffer branch now
  reverses to the consumer convention.
- `Core/Engines/TrendMath.mqh` - `CalculateEmaFallbackSeries` recursed the
  EMA from newest to oldest (a backwards EMA) and contained a dead first
  loop; it now seeds from the SMA of the oldest `period` bars and recurses
  `copied-1 -> 0`, emitting newest-first like the indicator path.
- `Core/AI/AIFeatureVectorBuilder.mqh` - `ComputeRollingZScoreIndicator`
  took `values[0]` as "current" from an oldest-first `CopyBuffer`, so the
  z-score numerator was the OLDEST bar of the window, not the bar at
  `shift`; now `values[period-1]`. Also guarded the history-preload path
  against `availableBars == 0` (negative `iTime` shift).
- `AIModules/OnnxBrain.mqh` + `AIModules/TransformerBrain.mqh` -
  `m_temperature` was stored by `SetTemperature` but never applied in
  either softmax; logits are now divided by the clamped temperature
  (T=1.0 default = identical output).
- `AIModules/MetaLabeler.mqh` - weight init was seeded with
  `MathSrand(TimeLocal())`, so identical ticks produced different
  meta-labeler weights - and different `Approve()` gates - on every run,
  breaking the deterministic-tester property the batch record relies on.
  Now seeded deterministically per instance
  (`1000003 + s_initSeq * 7919`).
- `Core/Orchestration/TradeExecutor.mqh` - `RemovePendingAt` cleared
  `m_pendingConfirmations[m_pendingCount]` after the shift, one slot past
  the last valid element; with a full 50-entry queue that wrote outside
  the array. Now clears `m_pendingCount - 1`.

Swept and found clean: all multi-element `CopyBuffer`/`CopyClose` sites
outside the fixes above either set `ArraySetAsSeries` or consume
order-insensitively; price-side (BID/ASK) usage in Core/ is direction-aware;
pending-order and breakeven/trailing paths verified.

Compile-verified: `sync_and_compile.ps1` -> OVERALL SUCCESS, 0 errors /
0 warnings on `MultiStrategyAutonomousEA.ex5`. Correctness fixes only -
not performance-measured; the NN/meta-labeler changes alter online
learning behaviour and need paired cold-window backtests before any
claim.

## [Unreleased] - 2026-11-23 (batch 4)

### Python - single source of truth for shared training primitives (item 25)
- New `Python/training_core.py` hosts the canonical implementations of
  `compute_atr`, `triple_barrier_labels` (+numba), `compute_uniqueness_weights`
  (+numba), `cusum_filter` (+numba), all feature helpers, `build_base_feature_matrix`,
  `exported_feature_columns`, `add_calendar_features`, `purge_embargo`,
  `cpcv_folds`, `psr`, `label_horizon_ns`.
- `data_pipeline.py` and `validate_model.py` now import/re-export them;
  ~350 lines of duplication removed. `build_feature_matrix` keeps its
  family_id/asset_class extension signature as a thin wrapper.
- `mql5_v2.py` stays self-contained for Colab: its copies are auto-vendored
  blocks spliced by new `Python/sync_mql5_v2.py` (re-run after editing any
  `@@VENDOR-BEGIN` region in training_core.py).
- Functions with genuinely different semantics (`prepare_sequences` label
  indexing, `_split_arrays` embargo handling, `compute_forward_returns`,
  scaler binary formats) intentionally remain per-file.
- Incidental correctness: data_pipeline now uses the safe-lag feature
  builder (no np.roll wrap-around) and backfilled ATR warm-up, matching the
  hardened mql5_v2 reference; only affects bars below the sequence warm-up.

### Python - stacker training-range metadata (item 27)
- `train_common.py`: new `load_split_full` (returns split timestamps),
  `save_train_meta`/`load_train_meta` (`<model>.trainmeta.json` sidecars with
  n_train + train/val time ranges and split params), and
  `stacker_fit_indices` (val-region baseline tightened by each base model's
  recorded `train_end`).
- All ten `train_*.py` scripts, `train_model.py` (ONNX), and generated Colab
  cells 5-7 now write sidecars; `train_oof_stacker` and both generated
  stacker cells fit the ridge via `stacker_fit_indices`.
- Base models trained on different splits (seq_len/family/asset_class) can
  no longer leak training rows into the meta-fit. Models without sidecars
  fall back to the val-only bound with a warning.

All Python files parse; `data_pipeline.build_dataset_splits` smoke-tested
end-to-end; `stacker_fit_indices` verified against synthetic metadata.
No MQL5 changes this batch - no recompile needed. Not performance-measured.

## [Unreleased] - 2026-11-19

### Risk correctness and evidence-based cleanup (not performance-tested)

- Specialized fast-scalp, spike-hunter, and grid-recovery entries fail closed when risk authority is unavailable; grid risk validation now sits at the send boundary. ATR, spike, and grid entries reconcile reservations to accepted fill volume and release them on definite send failure. ATR scalp entries use the initialized unified risk manager and shared CTradeManager execution/receipt path rather than raw CTrade sends.

- Removed the unconsumed per-strategy intrabar-eligibility inputs, policy enum/registry metadata, and two helper headers; retained active Momentum/Candlestick timeframe overrides without changing entry cadence or voting thresholds.

- Removed the always-allow `CandidateBuilder` authority stub; `CLiveAuthorityResolver` remains the sole live authority gate.
- Removed unimplemented safe-mode news/session fields and false-return gate, plus the partial-position tracker with no registration callers; startup now states that session/news filters are unavailable.
- Scalp telemetry now declares itself unavailable, and the dashboard hides fabricated zero metrics. The ensemble adapter reports inference-only status and logs unsupported training/temperature requests.
- Removed three dashboard panels that invented transformer attention, HMM transition probabilities, or pipeline-gate outcomes. Missing telemetry now says unavailable; synthetic demo data is dev-only, and the local architecture selector is labeled as a preview.
- Removed the no-op uncertainty deinitializer, ten orphaned MQL headers across the runtime and training trees (nine runtime headers plus `ModelComparer.mqh`), and the unused root Node manifest/empty lockfile. The dashboard's own package manifest and remaining model-training modules stay.
- Removed chart-symbol auto-injection so `InpSymbolsToTrade` is authoritative even with stale tester presets; removed validator confidence/confluence inputs that had no gate, and removed the unreachable spike-validator stub. The shipped live-overrides sample now contains only fields the risk reloader applies.
- Removed the no-op institutional-governance hook, duplicate health monitor, heuristic auto-parking/re-enable path, and its periodic sweep. Singleton-attributed closes still update bounded health scores that can modify vote weight; mixed/unattributed closes remain excluded. No hard strategy-removal decision or causal dollar-expectancy claim is made.
- Live risk overrides now update the risk manager's operator envelope before tier application; tier values cannot restore a prior, higher live cap. The cold-window harness requires explicit, non-overlapping INIs and excludes failed runs from its distribution; the obsolete repeat-one-window script with an external default path is removed.
- The lifecycle loss guard now receives the tier-effective daily-risk budget at startup and after live risk changes, rather than retaining a stale startup ceiling.
- Live risk-file edits now recalculate only when the effective operator envelope or supported sizing policy changes; strategy-only/no-op edits preserve adaptive risk state. Startup-selected risk tier is no longer parsed as a live override, and compounding restores its current saved tier after a genuine envelope change.
- Removed a dead candidate-builder risk fallback that could not override the risk manager's zero-risk veto; dynamic risk-tier changes are now explicitly startup-only rather than pretending to refresh tier policy.
- Removed the EA chart-event callbacks that mistook graphical-object property edits for input changes and could replay stale input risk values into the live manager.
- Per-strategy attribution unions contributors across every fill for a position, so netting-account add-ons cannot overwrite mixed ownership and become singleton P&L evidence. Multi-contributor and unattributed dollars remain unassigned; the report shows the exact single-contributor dollar subset and its coverage among priced closes, without presenting it as a strategy-removal verdict.
- Portfolio and exposure checks exclude the candidate's own provisional reservation before adding final trade risk. Full-position close attribution now aggregates all position deals, including profit, swap, commission, and fee, before updating a singleton contributor.
- Reservation exclusion now uses the candidate owner tag instead of subtracting a risk amount; other pending reservations also bind the per-symbol budget, whose open-position risk scan no longer holds a 60-second cache.
- The opt-in symbol-budget lot cap uses the same owner-excluded risk view, so open risk and other reservations are counted once without counting its own provisional reservation.
- CandidateBuilder now enforces the minimum-lot permission and uplift ceiling after both drawdown and momentum scaling; removed two position-limit minimum inputs and their unused config copies.
- Portfolio position-risk scans fail closed for unpriceable positions instead of treating them as zero risk; removed the stale exposure cache and unused per-symbol cache fields.
- Runtime configuration output no longer invents confidence/confluence floors; unsupported strategy-setting warnings appear only when such keys are actually present in the live override file.
- The README now states that the default allows one live voter and that registry-backed pipeline filters are opt-in; current architecture notes distinguish those filters from independent confidence and time/session checks.
- Pipeline math engines and indicator handles now initialize only when the explicit registry flag is enabled, avoiding dormant per-symbol engine allocation under the disabled default.
- No trading thresholds or filter defaults were changed by this cleanup. The current working tree still requires paired cold-window backtests.
- Verification: all eight MetaTrader targets compile with 0 errors and 0 warnings. The dashboard production build passes with a Vite advisory that its largest JavaScript chunk is 595 kB (176.97 kB gzip); no trading-performance claim is made.

### Remaining-work second batch (2026-11-23, compile-verified, NOT yet backtest-measured)

Eleven more `REMAINING_WORK.md` items closed; `sync_and_compile.ps1 -All` -> OVERALL SUCCESS,
0 errors / 0 warnings on all eight programs. Python-side changes affect future training runs;
MQL5 changes alter runtime behavior and still need paired cold-window backtests before any
performance claim.

- `Python/mql5_v2.py`: `prepare_sequences` now emits label-end timestamps; `purge_embargo`/`cpcv_folds`/
  `run_cpcv` are timestamp span-overlap ports of the reviewed `validate_model` logic (was fixed
  5-sample count purge that missed gaps between non-contiguous CPCV test groups). Stays
  self-contained for Colab; `triple_barrier_labels` keeps a sync comment (items 1-3, 24, 25-partial).
- `Python/train_common.py` + `write_colab.py` generated notebook: stacker `meta_X` is now filled for
  EVERY row from the already-computed base predictions (was all-zero on the first TimeSeriesSplit
  block); shape + no-all-zero-row assertions added. Regenerated `train_all_models_colab.ipynb`.
- `Python/safe_pickle.py` (new): whitelisted-globals `SafeUnpickler`; all executable `pickle.load`
  sites in `zmq_server.py`, `train_common.py` and the generated notebook now use `safe_pickle_load`
  (item 28).
- `Python/zmq_server.py`: `ZMQ_AUTH_TOKEN` env var - when set, non-heartbeat requests must carry a
  matching `token` field or get `{"error": "Unauthorized"}` (item 29).
- Dashboard commands actually execute (item 40): `IDashCommandHandler` interface on
  `CDashBridgeTransport`; `CEAOrchestrator` implements it - `pause`/`resume` drive
  `PortfolioRiskManager.SetEmergencyMode` (hard entry veto, tracked by `m_dashboardPauseActive`),
  `emergency_stop` also flattens via `CloseAllPositions`. Ack POST now carries
  `{"result":"ok"|"error"}`; unknown/failed commands are acked as errors so they cannot retry-loop.
  Server `/api/control/ack/{id}` accepts the optional result body and logs errors.
- `Core/Scalp/ATRScalpEntry.mqh` + `ATRScalpingEngine.mqh` + orchestrator wiring (item 43): scalp
  entries now go through `CTradeManager.OpenPosition` (confirmation queue, per-symbol trade objects,
  execution metrics, journal) instead of raw `CTrade::Buy/Sell`; SL/TP passed as point distances so
  stops re-derive from the fill price. Pre-send stop validation and the DONE_PARTIAL position
  confirmation are kept.
- `Core/Risk/RiskMarginHealth.mqh` + `RiskValidationPipeline.mqh` (item 13): margin check now
  computes the true margin DELTA - on netting accounts a same-symbol position is re-sized/closed/
  reversed by the order (`OrderCalcMargin` before vs after, fail-closed on error), so orders that
  free margin are no longer rejected and the projected margin level uses `currentMargin + delta`.
  Hedging keeps the conservative full add.
- `Python/check_scaler_parity.py` (new, item 5): round-trips `save_scaler_to_bin` through the exact
  `PipelineScaler.mqh` layout and asserts feature count == `AI_FEATURE_VECTOR_SIZE` (verified 70).
- Comment hygiene (item 38): `Batch NNN`/`Lx-yyy`/`Issue #N`/`Batch104-C1` tokens stripped from
  comments in ~99 .mqh/.mq5 files; measurement-table alignment and prose repaired in
  `SharedEAInputs.mqh`. Eleven legacy non-UTF-8 files were left untouched (IDs remain there).

Still open after this batch: item 19 literal sweep (no `.set` files exist in-repo), item 25 true
dedupe (mql5_v2 must stay Colab-standalone), item 27 in-sample base predictions (needs base-model
training ranges), item 36 per-asset `train_*.py` duplication.


### Remaining-work partial items closed (2026-11-22, compile-verified, NOT yet backtest-measured)

All eleven PARTIAL items in `REMAINING_WORK.md` were worked; eight are now done, three remain partial
with narrowed scope. `sync_and_compile.ps1 -All` -> OVERALL SUCCESS, 0 errors / 0 warnings.

- `Python/data_pipeline.py`: test split now purges labels that lack a full `vertical_bars` horizon;
  `prepare_sequences` asserts output-array alignment; `_scale_splits` fits the scaler per feature across
  bars (was flattened seq_len*n_features, which could never apply via `CPipelineScaler` at inference).
- `Python/train_model.py`: CPCV fold models now scale per fold on that fold's fit indices only, instead of
  reusing the global train scaler.
- `AIModules/CNeuralTrainingDataManager.mqh`: expired-barrier scan now covers exactly the vertical-bars
  horizon after entry (was `min(entryShift-1, vertBars)` - wrong window for old entries, whole history for new).
- `Core/Scalp/ATRScalpExit.mqh`: partial-close latch now verifies retcode DONE/DONE_PARTIAL and post-send
  POSITION_VOLUME; released on rejected retcodes and confirmed no-fills, kept on verified or ambiguous fills.
- `Strategies/NYOpenGapStrategy.mqh`: session bars located via `NYOpenFindSessionBar`, which derives the broker
  offset from each candidate bar's own timestamp (+/-1h standard-offset fallback) instead of reusing the
  current-time offset for all history.
- `Core/Management/PostConsensusValidator.mqh` + config plumbing: ATR crisis ceilings 2.5/2.0 are now inputs
  `InpAtrCrisisCeilingSynthetic`/`InpAtrCrisisCeilingForex` (defaults unchanged).
- `Core/Engines/AIEngine.mqh` + inputs: external LLM endpoint defaults removed everywhere; enabling the LLM
  with no endpoint now fails closed instead of targeting localhost:11434.
- `Python/train_common.py`: new `train_oof_stacker`/`get_onnx_probs`; `train_stacker.py` and
  `train_deriv_stacker.py` are thin wrappers (behavior preserved).
- Mojibake: all 57 `�?` sequences across 11 .mqh/.mq5 files replaced with `- `; zero U+FFFD remains.
- Dashboard auth: `EA_DASHBOARD_TOKEN` env var gates `/state`, `/api/control/command(s)`, `/api/control/ack`
  via `X-Api-Key`; EA sends it from new `InpDashboardApiKey` input (empty = auth off, loopback bind kept).



### Strategy signal audit fixes (code review pass, NOT yet backtest-measured)

A read-through of every file in `Strategies/` found and fixed the following. These are correctness fixes, not
tuning: they change what the strategies emit, so they need paired cold-window runs before any performance claim.
`sync_and_compile.ps1 -All` -> OVERALL SUCCESS, 0 errors / 0 warnings on all eight programs.

- `VolatilityBreakoutStrategy.mqh`: confidence was passed to `ValidateWithRiskManager` as 0.0 (assigned after the
  gate call) - same bug MeanReversion already had fixed. Also `BreakoutWithRetest` now requires the retest wick
  inside a +-0.2% band of the level instead of "anything below level*1.002" (one-sided, scale-dependent).
- `FVGScalperStrategy.mqh`, `BreakerBlockStrategy.mqh`: stop distances were priced off SYMBOL_BID for both
  directions; a buy fills at the ask. Now ASK for buys / BID for sells, matching AsianRangeBreak/TurtleSoup.
- `MarketStructureAnalyzer.mqh`: `HasStructureBreak()` re-fired on every `Update()` while price stayed beyond a
  swing level, so `HasBMS(n)` stayed true for the whole extended move and `bosCount`/`chochCount`/
  `consecutiveBMS` inflated. Breaks are now edge-triggered (previous closed bar must have been inside the level).
  `GetATR()` now reads shift 1 (closed bar) instead of the forming bar. `DetectFastCHOCH` gained a direction-aware
  overload.
- `FVGScalperStrategy.mqh`, `AsianRangeBreakStrategy.mqh`: the fast-CHOCH confidence bonus now only counts a
  break in the trade's own direction.
- `SessionGapDetector.mqh`: `UpdateFillStatus` scanned the detector timeframe (D1 for both consumers), so an NDOG
  - whose `openTime` is today's D1 open - could never see a single bar after it and `isFilled`/`isMitigated` stayed
  frozen at detect-time values. NDOG fill state now scans M15 bars; NWOG keeps D1.
- `ICTSessionGapStrategy.mqh`: `gap.size` (a daily-scale distance) was compared against the chart-timeframe ATR,
  making `m_minGapAtr` toothless on low timeframes. Size filters now use a dedicated D1 ATR handle.
- DST evaluated on the wrong clock in three places: `NYOpenGapStrategy.mqh` (`NYOpenIsUSDaylightTime` stamped the
  transitions at 02:00 UTC instead of 07:00/06:00 UTC, and the broker offset was rounded to 30 minutes),
  `LiquidityDetector.mqh` (`IsUSDSTime`, same transition bug), `KillZones.mqh` (`IsDSTActive` compared broker-time
  fields against a US-local rule - now evaluates on GMT with correct UTC transitions; `GetCurrentESTHour`
  resolves DST per call instead of using the offset cached once in `Initialize()`).
- `StatisticalArbitrageStrategy.mqh`: the strategy can never vote (leg2 is never sent) but still ran the
  correlation lookup, 100 CopyClose bars, OU blending and the risk gate every scan. It now prints its diagnostics
  and abstains before the risk gate. The spread itself is now a log-price difference - the raw `p1 - p2` form was
  dominated by the two instruments' price levels.
- `MeanReversionStrategy.mqh`: entry reference moved from the stale closed-bar close to the live ASK/BID (both the
  main and synthetic paths), invented TP fallbacks (`slPips * 2.0` / `* 1.5`) removed, dead `GetDynamicTP` call
  removed.
- `RangeCompressionBreakout.mqh`: dead `m_volumeHandle` (created, released, never read) removed.
- `SimpleMomentumStrategy.mqh`: `volFloor` used `MathMin`, letting the price-scaled term weaken the absolute
  floor; now `MathMax`.
- `LiquiditySweepStrategy.mqh`, `TurtleSoupStrategy.mqh`: chase cap - a sweep found several bars back could leave
  the stop multiple ATRs away; both now refuse `stopDistance > 3 * ATR`. LiquiditySweep round-number pip size now
  follows SYMBOL_DIGITS parity instead of hardcoded 5-digit FX.

### Batch 298: MEASURED, NOT SHIPPED - removing the last two loss-making rows makes the distribution worse, not better

Batch 297 trimmed the universe to eight symbols and got the first all-positive five-window distribution. The next
obvious trim was the two rows that still lose inside winning windows, `Step` and `Jump 25`. Five paired cold windows
say no: the trim costs mean and adds variance.

Per-symbol nets across the shipped eight-symbol windows (`attr2.py`, gross per close, one file per window):
`Step` **−81.27 / −51.70 / −28.32 / +78.07 / −68.20** (4 of 5 negative, −151.42 total) and `Jump 25`
**−119.71 / −95.20 / +32.67 / −55.81 / +6.45** (4 of 5 negative, −231.60 total) — together −383.02 USD, 0.77% of the
deposit per window.

**Arm:** `Tools\backtest_b298_six_w1..w5.ini`,
`InpSymbolsToTrade=Boom 1000 Index,Crash 1000 Index,Jump 75 Index,GBPUSD,AUDUSD,BTCUSD`; same Batch 293 binary (no
source change), `1%` / `4%` / `12%`, `InpQuorumProfile=1`, `InpMinLiveVoters=1`, scalper off, `Model=1`, deposit
10,000, cold each run.

| window | eight symbols | six symbols | delta | receipts |
|---|---|---|---|---|
| 08.01 -> 08.08 | +1.630% | **+1.803%** (min 9,995.98 / max 10,230.13) | +0.17 pp | 247 |
| 08.08 -> 08.15 | +7.276% | **+9.609%** (9,988.92 / 11,171.36) | **+2.33 pp** | 413 |
| 09.01 -> 09.08 | +5.681% | **+2.616%** (9,827.24 / 10,437.90) | **-3.07 pp** | 440 |
| 09.15 -> 09.22 | +7.444% | **+6.293%** (9,896.22 / 10,647.03) | -1.15 pp | 411 |
| 10.06 -> 10.13 | +4.692% | **+3.377%** (9,924.53 / 10,343.31) | -1.32 pp | 438 |

Six-symbol arm: mean **+4.740%**, sd **3.21 pp**, t **3.31**, 5/5 positive, worst **+1.803%**, best **+9.609%**.
Eight-symbol arm on the same windows: mean **+5.345%**, sd **2.37 pp**, t **5.04**, worst **+1.630%**, best +7.444%.
Paired: mean **-0.605 pp**, sd **2.01 pp**, t **0.67**, 2/5 positive. **Rejected, no input changed:**
`InpSymbolsToTrade` keeps its eight symbols.

**Mechanism.** The risk budget is not additive across symbols. `08.01` without `Step`/`Jump 25` took **94** `Crash 1000`
closes instead of **114** and pushed the difference into `Jump 75` (108 -> 125 closes): the removed rows were 30-60
closes of small low-correlation noise that diluted the single-index bet, and their removal concentrates the book into
exactly the instrument that also loses in some weeks. A symbol negative in dollars can still be positive in portfolio
terms; only a paired distribution distinguishes the two.

**Hazard paid for here.** w3's first launch was cut by the device going offline and `connection to Deriv-Demo lost`
at 16:21:50 - the terminal exited cleanly with `last test passed with result "some error after pass finished"`,
leaving a 13,406-heartbeat journal that ended 38 simulated hours into a 168-hour window and read **-5.303%** on a
base inherited from the previous run. It was rerun cold (+2.616%). Validity rule: a window counts only if the terminal
log says `successfully finished` **and** the journal slice is exactly 10,080 samples starting at the ini's `FromDate`.

**Files:** `Tools\backtest_b298_six_w1..w5.ini`, scoreboards `scoreboard_b298_six_w1..w5.csv`, journal snapshots
`journal_b298_w1..w5.log` plus `journal_b298_w3b.log` (segmented journal: a run's own samples are only the last
10,080 after the previous run's tail). No compile was needed - no source moved, `OVERALL SUCCESS` 0/0 stands from
Batch 297.

### Batch 297: SHIPPED - three rows that never made a positive week are out of the factory universe, and the five-window distribution has no losing window left

Batch 296 showed the profit is one instrument and the losses are the other rows. This batch removes the rows that
never produced a positive week - `EURUSD`, `USDJPY`, `XAUUSD` - and measures five paired windows on the same Batch 293
binary, cold each run, `1%` per trade / `4%` daily / `12%` portfolio, `InpQuorumProfile=1`, `InpMinLiveVoters=1`,
scalper off, deposit 10,000.

| window | eleven symbols | eight symbols | delta | receipts |
|---|---|---|---|---|
| 08.01 -> 08.08 | -3.583% | **+1.630%** (min 9,887.92 / max 10,221.23) | **+5.21 pp** | 383 |
| 08.08 -> 08.15 | +7.177% | **+7.276%** (9,997.05 / 10,918.24) | +0.10 pp | 250 |
| 09.01 -> 09.08 | +5.945% | **+5.681%** (9,896.20 / 10,626.23) | -0.26 pp | 413 |
| 09.15 -> 09.22 | +7.459% | **+7.444%** (9,921.43 / 10,757.15) | -0.02 pp | 408 |
| 10.06 -> 10.13 | -0.599% | **+4.692%** (10,000.00 / 10,573.49) | **+5.29 pp** | 446 |

Arm **mean +5.345%**, sd **2.37 pp**, **t 5.04**, **5 of 5 positive**, worst **+1.630%**. Eleven-symbol arm on the
same windows: mean +3.280%, sd 5.05 pp, t 1.45, 3 of 5. Paired deltas mean **+2.07 pp**, sd 2.91 pp, **t 1.59**,
4 of 5 positive.

**Why ship on t 1.59:** three of the five pairings are identical to within 0.26 pp - on those windows the removed rows
did nothing at all - and the two that moved are exactly the two that lost. The trim adds no return, it removes the
left tail: better mean, less than half the sd, and a worst window of +1.630% instead of -3.583% on the same windows.
First distribution in this record with no losing window in it.

**Mechanism:** receipts unchanged (250-446), so the book is no slower; the concentration moved. `08.01` `Crash 1000`
**+330.80 / 114 closes** where the eleven-symbol arm had **+54.39 / 92**; `10.06` `Crash 1000` **+674.20 / 118** and
`Jump 75` +92.74 / 132 positive against a loss in the wide arm.

**Ship:** `Core\Config\SharedEAInputs.mqh` `InpSymbolsToTrade` = `"Boom 1000 Index,Crash 1000 Index,Jump 25 Index,Jump
75 Index,Step Index,GBPUSD,AUDUSD,BTCUSD"`, with the five-window table in the comment above it. Default verified by
omission with the `.set` parked (`...set.parked_b297`): same window **10,000.00 -> 10,469.22, +4.692%**, ending equity
identical to the cent to the arm, and no `EURUSD` / `USDJPY` / `XAUUSD` closes in the run.

**Compile:** `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 900` -> `OVERALL SUCCESS` 0 errors / 0 total
warnings on all eight programs (root EA 74,406 ms). New inis `backtest_b297_trim8_w1..w5.ini`,
`backtest_b297_defaultcheck.ini`; scoreboards `scoreboard_b297_trim8_w1..w5.csv`, `scoreboard_b297_defaultcheck.csv`;
journals `journal_b297_w1..w5.log`, `journal_b297_defcheck.log`.

**Not fixed:** the book is still one instrument's variance. `Crash 1000` carries every paying window while `Step`
(-81.27, -110.44) and `Jump 25` (-119.71, -15.23) still bleed inside it, so a week where `Crash 1000` does not pay is
still a losing week. Next lever: a per-symbol cap that binds on lot size, since `GetSymbolRiskAllocation` is lifted off
its budget by the min-lot floor and therefore never binds.

### Batch 296: MEASURED, NO SHIP - the shipped default pays outside 2026-09/10 in one August week and loses in the next, and both outcomes are `Crash 1000`

Every prior window sat inside a contiguous 2026-09/10 slice, so regime sensitivity was untested. Two August windows,
factory configuration unchanged (`InpMaxRiskPerTrade=1.0`, `InpMaxDailyRisk=4.0`, `InpMaxPortfolioRisk=12.0`,
eleven-symbol universe, `InpQuorumProfile=1`, `InpMinLiveVoters=1`, scalper off, `Model=1`, deposit 10,000, four state
files cleared, Batch 293 binary):

- `2026.08.01` -> `08.08`: 10,000.00 -> **9,641.67**, **-358.33 (-3.583%)**, 381 receipts, min 9,597.41, **max 10,000.00**.
- `2026.08.08` -> `08.15`: 10,000.00 -> **10,717.72**, **+717.72 (+7.177%)**, 336 receipts, min 9,997.05, max 10,924.92.

Attribution (`08.01`, 268 closes, gross -357.33): `Crash 1000` **+54.39 / 92**, AUDUSD +5.67, GBPUSD -0.24, EURUSD
-1.61, XAUUSD -22.05, `Volatility 75` -26.93, `Jump 75` -34.13 / 93, `Jump 25` -59.35, USDJPY **-106.01**, `Step`
**-167.07**. Attribution (`08.08`, 249 closes, +717.72): `Crash 1000` **+850.02 / 88**, `Volatility 75` +127.35,
AUDUSD -0.60, GBPUSD -1.86, XAUUSD -13.96, `Jump 75` -28.85, EURUSD -38.27, USDJPY -44.52, `Jump 25` -58.61, `Step`
-72.98.

**Reading:** (1) the edge is not a September artifact - a window entirely outside the 09/10 slice still makes +7.177%
by the same mechanism, `Crash 1000` alone exceeding the net; (2) it is a single-instrument edge - the adjacent week
loses 3.583% because `Crash 1000` paid only +54.39 while `Step`, USDJPY, `Jump 25`, `Jump 75` and XAUUSD all bled, and
those are the same rows that bleed in the September windows. This is also why Batches 294 and 295 failed: a larger
budget does not enlarge the payer, it spreads capital over the rows that lose.

**Seven-window record:** `+5.945 / +7.689 / +7.459 / +18.176 / -0.599 / -3.583 / +7.177 %` -> mean **+6.038%**, sd
**6.96 pp**, **t 2.30**, **6 of 7 positive**, worst **-3.583%**.

Side observation: with identical caps, `reason=daily_risk_would_exceed` fires **13,806** and **13,936** times per
August window against roughly 2,884 in September - a busier month, and the ceiling was binding hard.

No input changed. New inis `Tools\backtest_b296_aug_w1.ini`, `backtest_b296_aug_w2.ini`; scoreboards archived as
`scoreboard_b296_aug_w1/w2.csv`; journals snapshotted as `journal_b296_aug_w1.log` / `_aug_w2.log`. Next queued
lever: drop the rows that are negative in every measured window (USDJPY, XAUUSD, EURUSD, `Jump 25`) and measure on
four paired windows.

### Batch 295: MEASURED, REJECTED - the daily risk ceiling is protective, and widening it costs 5.26 pp per window

The last unrun lever from Batch 294 was the ceiling itself: keep the 1% per-trade ask, widen the daily budget, and more positions can be open at once instead of bigger ones. Five paired windows, `InpMaxRiskPerTrade=1.0`, `InpMaxDailyRisk=8.0`, `InpMaxPortfolioRisk=24.0`, everything else identical to the shipped configuration, same Batch 293 binary, all four state files cleared per launch:

| window | factory 1% / 4% daily / 12% portfolio | 1% / 8% daily / 24% portfolio | delta |
|---|---|---|---|
| 09.01 -> 09.08 | +5.945% | **+6.126%** (429 receipts) | **+0.18 pp** |
| 09.08 -> 09.15 | +7.689% | **-5.519%** (455) | **-13.21 pp** |
| 09.15 -> 09.22 | +7.459% | **+2.315%** (328) | **-5.14 pp** |
| 09.22 -> 09.29 | +18.176% | **+8.279%** (349) | **-9.90 pp** |
| 10.06 -> 10.13 | -0.599% | **+5.061%** (468) | **+5.66 pp** |

Wide-ceiling arm: mean **+3.340%**, sd 5.36 pp, worst **-5.519%**, 4 of 5 up. Paired deltas: mean **-5.26 pp**, sd 7.32 pp, **t -1.61**, 4 of 5 negative.

It trades more (328-468 receipts vs 282-307) and it repairs the losing window, but it dilutes the two best ones: `09.22` falls from +18.176% to +8.279%, and `09.08` turns from +7.689% into -5.519%, the deepest loss in the record for a shipped configuration.

Finding beyond this arm: the +18.176% window is partly an artifact of the 4% ceiling holding concurrency near four positions, where four concurrent `Crash 1000` trades happened to be the right four. Widen the budget and the same signals spread into `Jump 75` (183 of 468 receipts on 10.06, 162 of 455 on 09.08), the row that loses. The cap enforces concentration in the instrument that pays; it is not throttling profit.

No input changed. `InpMaxDailyRisk=4.0` and `InpMaxPortfolioRisk=12.0` stay.

New artefacts: `Tools\backtest_b295_daily8_w1..w6.ini` (five windows used), archived scoreboards `scoreboard_b295_daily8_w1/w2/w3/w4/w6.csv`. Not done: 4% -> 6% as a smaller step, any window outside 2026-09/10, and no live attach.

### Batch 294: MEASURED, NOT SHIPPED - the risk dial selects the trade set instead of scaling it

The user's standing question is why the system is slow relative to bots that "fish money fast", and the implicit proposal is more risk per trade. This batch answers it with measurement, and answers it no.

Diagnosis before any run: `InpMaxRiskPerTrade = 1.0` on a 10,000 deposit implies 100 USD of risk per trade, but realised closes across every window average about ±23 USD, because sizing lands on the broker minimum lot for most synthetic symbols. The book's true risk is ~0.2% per trade, so the 1% ceiling is not the constraint and never was.

Three arms on two windows of the shipped trimmed universe, same Batch 293 binary, no source change, no recompile, all four state files cleared per run, `InpQuorumProfile=1`, `InpMinLiveVoters=1`, eleven-symbol universe, `Model=1`, deposit 10,000:

| window | 1% / 4% daily / 12% portfolio (factory) | 2% / 8% daily / 24% portfolio | 4% per trade only |
|---|---|---|---|
| 09.22 -> 09.29 | **+18.176%** (282 receipts) | **-1.217%**, min 9,634.71, max 10,155.90 | **+7.625%**, min 9,997.99, max 10,765.76 |
| 10.06 -> 10.13 | **-0.599%** (307 receipts) | **-3.614%**, 450 receipts, min 9,589.31 | **+2.097%**, 293 receipts, min 9,894.02 |
| mean | **+8.79%** | **-2.42%** | **+4.86%** |
| cross-window sd | 13.28 pp | 1.70 pp | 3.91 pp |

Mechanism: at 4% per trade the EA itself warns `[VALIDATION] WARNING: InpMaxRiskPerTrade * InpMaxPositionsTotal (60.00) > InpMaxPortfolioRisk * 1.5 (18.00)`, and `reason=daily_risk_would_exceed` rises from ~2,884 per window at 1% to 27,471 at 2% and 17,631 at 4%. A single candidate asks 1.00-2.00%, so the 4.00% daily budget admits two concurrent positions where the 1% book ran up to fifteen. The fill mix flips from `Crash 1000`-led (the instrument that pays every window) to `Jump 75`-led: 122 of 293 receipts at 4%, 172 of 450 at 2%.

Conclusion: raising `InpMaxRiskPerTrade` does not enlarge the book, it re-selects it, and both re-selections are worse than the factory setting on mean across the two windows. No input changed. `InpMaxRiskPerTrade=1.0`, `InpMaxDailyRisk=4.0`, `InpMaxPortfolioRisk=12.0` remain the measured best configuration.

Measurement hazards hit and fixed here: the tester journal is recreated per run, so the first 4% window's equity was overwritten by the second and the window had to be re-launched (1,260 s) with the journal snapshotted at `last test passed`; and a heartbeat slice may begin inside the previous run, so the base is the sample with balance exactly 10,000.00 within the first ten samples of the last 10,080.

New artefacts: `Tools\backtest_b294_risk4x_w4.ini`, `Tools\backtest_b294_risk4x_w6.ini`, `Tools\backtest_b294_scale2x_w4.ini`, `Tools\backtest_b294_scale2x_w6.ini`; archived scoreboards `scoreboard_b294_risk4x_20260922-20260929.csv`, `scoreboard_b294_risk4x_20261006-20261013.csv`, `scoreboard_b294_scale2x_w4.csv`, `scoreboard_b294_scale2x_w6.csv`. Not done: two windows per arm is a 3-point grid rather than a distribution, and the daily-ceiling-only arm (1% per trade, 8% daily budget) is still unrun.

### Batch 293: SHIPPED - the two Volatility indices are out of the factory universe, on five paired windows

Batch 292 produced three paired windows for a universe trim and refused to ship it on three. Two more windows finished the set, and the arm now clears the same bar this repository used for `InpMinLiveVoters`.

**The full five-window table** (all cold, `Volatility 75 Index` M15, `Model=1`, deposit 10,000, `InpQuorumProfile=1`, `InpMinLiveVoters=1`, scalper off; the full-universe column is Batch 291's own record for the same windows):

| window | full universe | trimmed (no V25/V75) | delta |
|---|---|---|---|
| 09.01 -> 09.08 | +381.07 (+3.811%), 270 fills | **+594.45 (+5.945%)**, 306 receipts | **+2.13 pp** |
| 09.08 -> 09.15 | +63.45 (+0.635%), 273 | **+768.93 (+7.689%)**, 271 | **+7.05 pp** |
| 09.15 -> 09.22 | +148.92 (+1.489%), 261 | **+745.87 (+7.459%)**, 263 (min 9,782.29) | **+5.97 pp** |
| 09.22 -> 09.29 | +264.00 (+2.640%), 260 | **+1,817.63 (+18.176%)**, 282 | **+15.54 pp** |
| 10.06 -> 10.13 | -269.61 (-2.696%), 307 | **-59.87 (-0.599%)**, 307 | **+2.10 pp** |

Trimmed arm: mean **+7.734%**, sample sd **6.74 pp**, **t 2.57**, worst window **-0.599%**. Paired deltas: mean **+6.558 pp**, sd **5.39 pp**, **t 2.72**, **5 of 5 positive** - a paired design on the same windows and the same binary, so build and window effects cancel. Against the full universe's own six-window distribution (mean +1.148%, sd 2.213 pp, worst -2.696%), the trim returns about twice the mean at double the deviation while cutting the worst week by 2.1 pp.

**Why the Batch 285 counter-evidence does not veto this:** Batch 285 measured `Crash 1000` -123.06 / `Volatility 75` +261.22 in the one-voter arm, and that measurement was taken on a build carrying the Batch 289 indicator-handle defect (M15 ATR(14) served by a D1 handle, `ATR ratio crisis gate: 9.825 > 2.500` on every consensus entry). AGENTS.md already records that Batches 282-288 are not a baseline. The five windows here are on the repaired build.

**What the gain is, stated plainly:** it is still `Crash 1000` deciding the week - +763.58 on 89 closes (09.01), +499.05 on 79 (09.08), +719.52 on 87 (09.15), +1,848.83 on 85 (09.22), +1,756.56 on 84 (11.817 replay). `Step Index` (+136.16, +161.48, +164.83) and `Jump 25` help. The two Volatility indices were the only consistently loss-making rows in the full-universe arm, and five closes of `Volatility 75` (-116.53) carried the only losing full-universe window. So this is "stop buying the instrument the book cannot trade", not a new signal.

**The change** (`Core\Config\SharedEAInputs.mqh:70-84`): `input string InpSymbolsToTrade` drops `Volatility 25 Index` and `Volatility 75 Index`, leaving eleven symbols, with the five-window table written above it in the source. Restoring them is an input edit, not a code change.

**Default verified, not assumed** - the Batch 288 lesson applied: `Tools\backtest_b292_defaultcheck.ini` omits `InpSymbolsToTrade` entirely and the tester `.set` was parked as `MultiStrategyAutonomousEA.set.parked_b292` before the run. Result: 10,000.00 -> **11,817.57**, **+1,817.57 (+18.176%)**, min 10,000.00 / max 11,822.65, 314 receipts, `[SCALP-SIGNAL-REJECT]` **0** (scalper-off default also in force). That is the trim arm's 11,817.63 to within six cents, so the compiled default is exactly the measured arm and no `.set` inheritance is in play. MT5 recreated the `.set` afterwards, as always.

**Historical deviation in this batch's binary (fixed in later source, not yet re-measured):** `InpAutoAddChartSymbol = true` re-injected the chart symbol, so a trimmed run took 2-4 `Volatility 75` closes (the chart is V75 by harness convention). The universe acted as a priority list plus chart symbol; the auto-add input and path have since been removed.

**Verification:** `sync_files.ps1` then `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 900` -> **`OVERALL SUCCESS` - 0 errors, 0 total warnings** on all eight programs (`MultiStrategyAutonomousEA.mq5` 108,509 ms, `MultiStrategyTestingEA.mq5` 101,634 ms, `TrainingDataExporter.mq5` 35,780 ms). New inis: `Tools\backtest_b291_novol_w1.ini`, `_novol_w2.ini`, `Tools\backtest_b292_defaultcheck.ini`. Archived scoreboards: `scoreboard_b291_novol_20260901-20260908.csv`, `_20260908-20260915.csv`, `scoreboard_b292_default_20260901-20260908.csv`.

**Hazard re-confirmed twice:** the tester log path is date-stamped, so a run started after local midnight writes `20261114.log`; a poller watching `20261113.log` reports a healthy process as frozen (this cost one batch script). And 2-4 leftover `terminal64`/`metatester64` processes silently swallow a `/config:` launch - the `Get-Process` pre-check stays mandatory.

**Not done:** five windows is one regime (2026-09/10); no window exists where `Crash 1000` trends against the book, so the trim's downside is only observed as -0.599%. A per-symbol risk cap is the untested lever that would make this independent of which index trends.

### Batch 292: the sixth window lost, and the loss names the symbol — but trimming the universe is not yet a ship

Batch 291 shipped the scalper off on a five-window distribution (mean +1.917%, t 3.30). Its first job was to confirm that on the post-logging build. It did not confirm: the next window lost, and the loss was concentrated enough to name the instrument.

**Window 6, factory default, post-logging build:** `Tools\backtest_b291_default_w6.ini` (`2026.10.06`->`10.13`), `.set` parked, `InpEnableScalpEngine` omitted, `InpQuorumProfile=1`, `InpMinLiveVoters=1`, cold, tester `successfully finished` in 0:27:53. Equity 10,000.00 -> **9,730.39**, **-269.61 (-2.696%)**, **307 fills**, min 9,713.44, max 10,131.30, `[SCALP-SIGNAL-REJECT]` **0** (default in force).

**Six-window distribution for the shipped default:** +3.811 / +0.635 / +1.489 / +2.640 / +1.009 / **-2.696** -> mean **+1.148%**, sample sd **2.213 pp**, **t 1.27**, **5 wins of 6**. One loss halved the t-statistic (3.30 -> 1.27). The honest status of the default is "positive, not proven".

**The loss, attributed at the exact-symbol level:** 181 `[EnterpriseManager] Trade Closed` records, gross **-162.00** - `Volatility 75 Index` **-116.53 on 5 closes** (about -23 each), `Volatility 25 Index` **-52.93 on 27**, `Crash 1000` -36.64 on 33, `Jump 25` -5.04 on 33, against `Jump 75` +14.33 on 65, `Step` +20.72 on 10, `EURUSD` +12.83 on 6. Worst drawdown **-188.22**, reached early (heartbeat sample 143 of 10,080). This is Batch 285's shape repeated: five closes of one volatility index carry a week.

**The arm it motivated (no code change - `InpSymbolsToTrade` already existed).** The same windows with the two Volatility indices removed from the universe (`Boom 1000, Crash 1000, Jump 25, Jump 75, Step, EURUSD, GBPUSD, USDJPY, AUDUSD, XAUUSD, BTCUSD`), everything else identical:

| window | full universe | trimmed universe | delta | dominant contributor in the trimmed arm |
|---|---|---|---|---|
| 10.06 -> 10.13 | **-269.61 (-2.696%)**, 307 fills | **-59.87 (-0.599%)**, 307 fills | **+2.10 pp** | `Crash 1000` -? (small), `Vol 75` still 3 fills via the chart symbol |
| 09.15 -> 09.22 | **+148.92 (+1.489%)**, 261 fills | **+745.87 (+7.459%)**, 301 receipt-lines / 263 fills, min 9,782.29 | **+5.97 pp** | `Crash 1000` **+719.52 on 87 closes** = 96% of the gain |
| 09.22 -> 09.29 | **+264.00 (+2.640%)**, 260 fills | **+1,817.63 (+18.176%)**, 328 receipt-lines / 282 fills | **+15.54 pp** | `Crash 1000` **+1,848.83 on 85 closes** |

Trimmed-arm statistics on those three windows: mean **+8.345%**, sample sd **9.50 pp**, t **1.52**. Every window improved (3 of 3), but the improvement is one instrument: in two windows `Crash 1000` alone produced more than the entire account delta, and the third window is where it went mildly negative.

**Verdict: measured, not shipped.** Three paired windows with a consistent sign is real evidence, but it contradicts the older record - Batch 285 measured `Crash 1000` as the **loser** (-123.06 on 68 closes) and `Volatility 75` as the **winner** (+261.22 on 11 closes) in the one-voter arm, and in the committee arm the two swapped sides entirely. So "drop the Volatility indices" is currently a bet on which index trends during 2026-09/10, not a demonstrated edge. `InpSymbolsToTrade` stays at its factory list until the trimmed arm has five or six paired windows, the standard this repository already applies to `InpMinLiveVoters`.

**A measurement hazard found and fixed in the method:** the tester journal rotates and the last 10,080-heartbeat slice can begin inside the *previous* run. The aborted window-3 launch (killed when the desktop connection dropped at 43%) left four heartbeats at 9,948.23 at the head of the next slice, so a naive "last sample minus first sample" read 1,817.63 as 1,880.39 and window 3 as +8.018% instead of **+7.459%**. The reliable base is the sample whose balance is exactly the deposit (10,000.00), searched within the first ten samples; window 3's true run is index 4 onwards: min 9,782.29, max 10,769.54.

**Operational notes:** the aborted run was caused by the device dropping offline mid-test - `terminal64` was gone, the log frozen at `processing 43 %` for 30 minutes with no process alive; killing leftovers (`Stop-Process -Name terminal64,metatester64`) and relaunching cold reproduced the window in 0:40:41. Two leftover processes (11060, 22900) were alive at one launch and silently swallowed it; the `Get-Process` pre-check from Batch 290 remains mandatory.

**No code changed in this batch**, so no recompile; the binary is the Batch 291 build (`MultiStrategyAutonomousEA` 65,590 ms, `OVERALL SUCCESS`, 0 errors / 0 total warnings). New inis: `Tools\backtest_b291_default_w6.ini`, `Tools\backtest_b291_novol_w6.ini`, `_novol_w4.ini`, `_novol_w3.ini`. Archived scoreboards: `scoreboard_b291_default_20261006-20261013.csv`, `scoreboard_b291_novol_20261006-20261013.csv`, `scoreboard_b291_novol_20260922-20260929.csv`.

**Not done:** the trimmed arm has 3 paired windows, not the 5-6 it needs; `[ENGINE-CLOSE]` still never observed (scalper off); `Tools\backtest_b290_scalp2.ini` still unrun; `backtest_report.htm` still unwritten so still no MT5 profit factor / drawdown / Sharpe.

### Batch 291: five cold windows with the scalper off — 5 of 5 positive, mean +1.917%, t 3.3 — shipped as the factory default

A single A/B on one window is an observation. This batch turned Batch 290's +3.811% into a distribution on the same binary (no recompile for the first four windows: `MultiStrategyAutonomousEA.ex5` 1,756,100 B, 13 Nov 18:09:39), then shipped what the distribution supports.

**The five arms.** `Volatility 75 Index` M15, `Model=1`, deposit 10,000, `InpQuorumProfile=1`, `InpMinLiveVoters=1`, every run cold (all four init-loaded state files deleted, scoreboard archived to `Tools\artifacts\scoreboards\`), `terminal64`/`metatester64` confirmed absent before each launch. P&L rebuilt from each run's own 10,080 `[COMPOUNDING-TIER-HEARTBEAT]` samples; fills counted from `[EXECUTION-RECEIPT]`.

| Window | P&L | fills | min / max balance | tester time | ini |
|---|---|---|---|---|---|
| 2026.09.01->09.08 | **+381.07 (+3.811%)** | 270 | 9,891.96 / 10,381.42 | 1:13:52 | `backtest_b290_noscalp.ini` |
| 2026.09.08->09.15 | **+63.45 (+0.635%)** | 273 | 9,815.95 / 10,088.68 | 0:28:07 | `backtest_b290_noscalp_w2.ini` |
| 2026.09.15->09.22 | **+148.92 (+1.489%)** | 261 | 9,976.99 / 10,168.43 | 0:25:24 | `backtest_b290_noscalp_w3.ini` |
| 2026.09.22->09.29 | **+264.00 (+2.640%)** | 260 | 9,964.62 / 10,424.80 | 0:27:34 | `backtest_b290_noscalp_w4.ini` |
| 2026.09.29->10.06 | **+100.93 (+1.009%)** | 279 | 9,943.67 / 10,255.71 | 0:28:23 | `backtest_b291_default_w5.ini` |
| control: same build, scalper ON, 09.01->09.08 | **-258.77 (-2.588%)** | 2,265 | 9,560.27 / 10,000.00 | 0:41:23 | `backtest_voters1.ini` |

**Distribution:** mean **+1.917%**, sample stdev **1.300 pp**, **t 3.30**, **5 wins of 5**, range +0.635% to +3.811%. Compare the Batch 284 scalp-on build across six windows: mean +0.46%, stdev 0.92 pp, t 1.2, 3 wins of 6. The change moves the book from break-even-within-noise to a distribution whose mean is three standard errors from zero, on one instrument and one adjacent 7-day slice sequence.

**Fill volume, again, is not signal:** the four no-scalp arms took 260-279 fills against 2,265 for the scalp-on arm, yet produced +0.635% to +3.811% where the 2,265-fill arm produced -2.588%. Consistent with Batch 285 (dollars live in a dozen closes, not in hundreds) and Batch 290 (the scalper is the loss). What changed is expectancy per trade, ~+70 to +1,000 USD per 270 fills against -0.11 per fill.

**Arm 5 is the default test, not an explicit-input test.** `Tools\backtest_b291_default_w5.ini` sets only `InpQuorumProfile=1` and `InpMinLiveVoters=1` and **omits `InpEnableScalpEngine`**, and `MQL5\Profiles\Tester\MultiStrategyAutonomousEA.set` (the file MT5 rewrites after every run and reuses as the next run's starting inputs) was moved to `...set.parked_b291` before launch. The run shows **0 `[SCALP-SIGNAL-REJECT]` lines** (2,265-fill arm: 58,935) and no scalp-dominated symbol mix, i.e. the compiled default is what executed. That file now exists again, freshly written by this run - proof MT5 recreated it from the used inputs, and the Batches 283/288 hazard is confirmed again.

**Shipped in this batch (compiled, `OVERALL SUCCESS`):**
1. `Core\Config\SharedEAInputs.mqh`: `input bool InpEnableScalpEngine = false;` (was `true`), with the six-line measurement block above it: the two Batch 290 arms, the four-window spread, the mean/sd/t, and how to turn it back on (`InpEnableScalpEngine=true`, optionally bounded by `InpScalpSymbolsCsv`) with the instruction to measure a paired window before shipping it again.
2. `Core\Management\StrategyMgrTradeFeedback.mqh`: engine-managed closes (scalp/grid, identified by `IsEngineManagedPosition(dealComment) || CMagicRange::IsEngineReservedOffset(...)`) used to `return` before any logging, which is why the 2,265-fill arm recorded 260 `Trade Closed` lines summing +11.03 against an account delta of -258.77 - roughly 270 USD of loss was invisible. The branch now computes `bool engineManaged` first and, for `DEAL_ENTRY_OUT/OUT_BY/INOUT`, prints `[ENGINE-CLOSE] <sym> | ticket=... | position=... | magic=... | net=%.2f | comment=...` before returning. The strategy-scoring path is untouched; this only adds a realised-P&L record. Compiled, **not yet runtime-observed** (the scalper is off by default, so it needs a scalp-on window to fire).

**Verification:** `.\sync_files.ps1` (40 Python files + all MQH), then `.\sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 900` -> **`OVERALL SUCCESS` - 0 errors, 0 total warnings** on all eight programs: `MultiStrategyAutonomousEA` 65,590 ms, `MultiStrategyTestingEA` 69,669 ms, `TrainingDataExporter` 25,786 ms, `WalkForwardTesterEA` 1,837 ms, `MQHHyperparameterTuner` 4,858 ms, `MQHModelEvaluator` 2,289 ms, `MQHModelTrainer` 3,943 ms, `MQHModelVisualizer` 3,491 ms. Doc edits BOM-free UTF-8.

**Not done:** no window has been run on this new build (the five arms above are the pre-logging binary; window 5 is the new binary but not identical-input comparable to the other four, since it also exercises the default path); the distribution is still one instrument, one contiguous 09/10 slice - out-of-window but not out-of-regime; `Tools\backtest_b290_scalp2.ini` (scalper limited to `XAUUSD,Step Index`) remains unrun, so "symbol coverage vs off entirely" is still open; `backtest_report.htm` is still not written by this terminal, so still no MT5 profit factor / drawdown / Sharpe.

### Batch 290: the repaired build was run cold — 2,265 fills, -2.588%, and without the scalper the same window makes +3.811%

First measurement of the Batch 289 build (`MultiStrategyAutonomousEA.ex5` 1,755,140 B, 13 Nov 15:04:51). `Tools\backtest_voters1.ini`, `Volatility 75 Index` M15, `Model=1`, deposit 10,000, `2026.09.01`->`09.08`, `InpQuorumProfile=1`, `InpMinLiveVoters=1`, all four state files cleared before launch, no `terminal64`/`metatester64` alive, port 3000 free. Tester: `last test passed with result "successfully finished" in 0:41:23.353 + history synchronization 0:00:03.613`.

**Result, rebuilt from this run's own 10,080 heartbeats:** first 10,000.00, last **9,741.23**, delta **-258.77 (-2.588%)**, min **9,560.27**, max **10,000.00** (never above deposit), **2,265 fills**. The Batch 288 build on the identical window and inputs returned **+98.29 (+0.983%) on 849 fills**, so the build change is **-3.57 pp and +167% fills**. That gap is far outside the 0.92 pp cross-window noise and the tester is deterministic, so this is a build effect, not a window effect.

**Where the volume went:** fills by symbol `Jump 809, Volatility 729, Step 417, XAUUSD 133, USDJPY 77, Crash 61, GBPUSD 23, EURUSD 13, AUDUSD 3` (Batch 288: XAUUSD 618, Step 129, Vol 25 95, Crash 65, Jump 75 48). Scoreboard at shutdown: 300 rows, **87 with trades** - `Jump 75` 189 trades / 55 wins, `Crash 1000` 153 / 53, `Volatility 25` 94 / 41, `Jump 25` 63 / 38, `Step` 52 / 16, `Volatility 75` 21 / 5; win rates **29-45%**. The EA's own health rule parked `Crash 1000` S/R, Turtle Soup, Donchian and ICT Structure Shift (health 0.35-0.38) during the window.

**Reading it:** the 60/90-point scalp geometry of the old build was the *reason* ten of twelve symbols could not trade (`spread=1431.0 ... tp=90.0 breakevenWR=0.941`); Batch 289 replaced it with `max(1.5xATR(14,M1), 4xspread, 1.5xstop level)`, which is correct arithmetic and deliberately admits the other symbols. It admits them and they lose at their real expectancy. So the old +0.983% was partly bought by refusing to trade, and "more fills is worse" is again the wrong conclusion - the correct one is "the scalp engine now trades, and its expectancy is negative". `[SCALP-SIGNAL-REJECT]` is 58,935 lines in this window (32,216 before), and `[SCALP-GATE]` shows `usedRisk=3.00% of budget=3.00%`, i.e. the engine runs to its risk budget and stops. `[CORR-UNKNOWN]`, `[PORTFOLIO-RISK]` and `[VOL-SIZE]` are **0/0/0** in this run: the correlation and portfolio-risk repairs are silent, not binding.

**Single-variable A/B, and the answer:** `Tools\backtest_b290_noscalp.ini` - the same window and the same inputs with one line changed, `InpEnableScalpEngine=0` (no recompile, the build is identical). Result: `last test passed ... in 1:13:52.339`, first balance 10,000.00, last **10,381.07**, delta **+381.07 (+3.811%)**, min **9,891.96**, max **10,381.42**, **270 fills** (`Jump 116, Crash 62, Volatility 53, Step 19, GBPUSD 7, EURUSD 7, USDJPY 2, XAUUSD 2, AUDUSD 2`). So the swing between the two arms is **+6.40 pp** on one build, one window, one input - and the arm that makes money is the one **without** the fast-scalp engine. `[AUTHORITY-REJECT]` 3,334 and `[SCALP-SIGNAL-REJECT]` 2,600 (with the engine off, the rejections are the consensus/cost path) are what still binds.

**Conclusion for this batch:** the Batch 289 stop geometry is not the defect - it is correct arithmetic that exposes the scalp engine's real expectancy across twelve symbols, and that expectancy is negative. The profitable configuration found here is the consensus book alone: **+3.811%** against **-2.588%**, with a quarter of the fills. `+3.811%` is one window and is not yet a default; it needs the neighbouring windows before it is shipped the way `InpMinLiveVoters=1` was shipped in Batch 288.

**Code written in this batch (compiled, unmeasured):** symbol coverage is now a testable variable instead of a side effect. `Core\Orchestration\OrchestratorConfig.mqh` gained `string scalpSymbolsCsv` (default `""`), `Core\Config\SharedEAInputs.mqh` gained `input string InpScalpSymbolsCsv = ""` in the Scalp Engine group (with the Batch 290 measurement written beside it), and `EAOrchestrator.mqh` gates the scalp scan with `IsScalpSymbolAllowed(symbol)` - exact, trimmed, comma-separated match on the broker's own symbol name, `""` = every symbol, no substring matching. `Tools\backtest_b290_scalp2.ini` (`InpScalpSymbolsCsv=XAUUSD,Step Index`) is the staged arm that separates "which symbols" from "which geometry". Verification: `sync_files.ps1` then `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 900` -> **0 errors, 0 warnings** on `MultiStrategyAutonomousEA` (96.9 s, `MultiStrategyAutonomousEA.ex5` 1,756,100 B 18:09:39) and on `MultiStrategyTestingEA` (418.3 s, 1,753,990 B 18:16:31); the other six programs also rebuilt (18:07:36-18:17:07).

**Two hazards, both measured:**
1. `ShutdownTerminal=1` did **not** terminate `terminal64` after `last test passed`; the process stayed alive and a subsequent `Start-Process ... /config:` silently did nothing (no second terminal instance attaches). The leftover process had to be stopped before the next run could start. Every launch must verify `Get-Process terminal64,metatester64` is empty first.
2. Close records exist but cover only a minority of fills. `[EnterpriseManager] Trade Closed ... Net Profit:` is still printed (`Core\Management\StrategyMgrTradeFeedback.mqh:167`) and 260 of them appear in this run, but the run took **2,265 fills**: fast-scalp exits close positions through `Core\Scalp\FastScalpExit.mqh`, which prints entry/exit events and never realised P&L. The 260 recorded closes sum to **+11.03 gross** against an account delta of **-258.77**, so about **270 USD of the loss sits in closes that wrote no journal line**. Per-symbol attribution is therefore counts and win rates only in this entry; the losing trades are exactly the invisible ones. A realised-P&L line on the scalp exit path is a measurement prerequisite for the next batch.

### Batch 289: the shared ATR handle was being swapped for a daily one, and the scalper priced every symbol in raw points

Source: the 24-minute demo journal of 2026-11-13 (`Volatility 75 Index,M15`, 13 symbols, 14:14:06 -> 14:38:06): 14 fills, all fast-scalp, on two symbols (Step Index 4, XAUUSD 10); 8 consensus decisions, 0 sent. **Not compiled and not run** - this batch was written without access to MetaEditor or a terminal, so every item below is a code-level change that still needs `sync_and_compile.ps1 -All` and a cold window before it counts as a result.

- **Indicator handles (root cause of "consensus never trades").** `Created ATR handle=201 for Step Index PERIOD_M15 period=14` is followed 37 s later by `Created ATR handle=201 for Step Index PERIOD_D1 period=14`; 26 handle numbers were issued twice in the session. A handle the manager tracked was released by a direct `IndicatorRelease()` elsewhere (the terminal hands identical parameters the same number), the number was reused, and the manager's M15 row kept answering with a D1 indicator. Every reader of M15 ATR(14) then got the daily ATR: the post-consensus gate printed `ATR ratio crisis gate: 9.825 > 2.500 (ATR14 61.18 / ATR50 6.23)` and the same 8-14x ratio on Step, Crash 1000 and USDJPY, vetoing every consensus entry it saw. `IndicatorManager.mqh` now defines `IndicatorManagerGuardedRelease()` and `#define IndicatorRelease IndicatorManagerGuardedRelease`, so no code compiled after it can release a number in the shared table; both root EAs include the manager first. The two idle sweeps (`ReleaseUnused(14400)` in `EAOrchestrator` and `DiagMgrHeartbeat`) are removed, because consumers cache handle numbers in members and a swept row leaves them reading a dead, then reused, handle.
- **Correlation.** `[PortfolioRisk] BLOCKED: Correlation 1.00 > Max 0.70 (AUDUSD vs Step Index)` (and XAUUSD): a newly registered symbol read the matrix slot's initial value, which was `1.0`, until the next 300 s refresh. Slots now start `CORR_ENGINE_UNKNOWN` and `RegisterSymbol` flags a rebuild.
- **Portfolio risk.** `New Total 14.26% > Max 12.00%` with `open_exposure=0.09`: `ValidatePortfolioRisk` called `IsTradeAllowed(symbol, lot)` without the stop, so the manager re-priced the lot at 1.5 x chart-timeframe ATR instead of the stop it was sized on. The request's stop is now passed.
- **Fast scalp geometry.** `scalpSLPips=60 / scalpTPPips=90` were raw points on every symbol (6.0 on Step Index, 0.60 on XAUUSD, 4% of one spread on Volatility 75), so the cost gate refused everything but two symbols (`spread=1431.0 ... tp=90.0 breakevenWR=0.941`). `CFastScalpEngine::BuildSymbolConfig` prices each symbol: stop = max(1.5 x ATR(14,M1), 4 x spread, 1.5 x stop level), target keeps the configured TP:SL ratio; sizing, cost gate, risk gate and send all use it. Breakeven/trailing in `CFastScalpExit` are 0.6R / 0.1R / 0.6R of the position's own stop instead of 10/5/15 points. One scalp per symbol, and a symbol rests 180 s after an entry (ten XAUUSD SELLs in 152 s came off two crossovers).
- **Equity-curve modifier.** 191 flips in 24 minutes on 10-30 cent moves (`Equity=14027.02 below EMA=14027.11, position size reduced to 50%`). The cut now arms 0.25% under the EMA and clears at the EMA.
- **Volatility model.** `VolReg_RiskScale` no longer returns the veto band: it held both Volatility 75 decisions of the session at `p=0.007`/`0.017`. Compression trades at half risk until a walk-forward run prices the veto.
- **Shutdown.** `Abnormal termination` 4.5 s after `[DEINIT-START]`, with no scoreboard or `Shutdown complete` line: the terminal killed OnDeinit before the two state writes at its end. `PersistStrategyScoreboard()` and `PersistRiskRuntimeState(true)` now run first. The slow teardown itself is not yet located.

Consequence for the record: Batches 282-288 were measured on builds with the handle defect, so their consensus books ran with a corrupted ATR wherever a number was reused. Those numbers stay valid as measurements of that build; they are not a baseline for this one, and every window must be re-run cold.

### Batch 288: the one measured lever becomes the shipped default, and the build is checked against four baselines

The recommendation from Batches 283-287 was narrow on purpose: of every "threshold" this repository has been asked to autotune, exactly one setting has multi-window evidence, and it is `InpMinLiveVoters`. This batch ships it and nothing else. `Core\Config\SharedEAInputs.mqh` now reads `input int InpMinLiveVoters = 1;` (was 2) with the measurement written beside it — six cold windows, one-voter mean +0.46% (stdev 0.92 pp, 3 wins of 6) against the committee's mean -1.31% (4 losses of 4), paired delta +1.80 pp at t = 2.6 / p about 0.08, rejections down from 2,054-2,819 per window to 139-227. The committee stays selectable at 2; the per-symbol rules of 286 and 287 stay off (0 and 1.0) because both were measured negative. Compiled `sync_files.ps1` then `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 900` -> **`OVERALL SUCCESS` - 0 errors, 0 total warnings** on all eight programs (root EAs 60.7 s / 58.4 s).

**The default had to be proven, not assumed, and the proof found the mechanism behind a hazard this repo has been fighting since Batch 283.** MT5 does not merely "reuse the previous run's inputs" for an omitted `[TesterInputs]` line: after every test it writes the whole input set to `MQL5\Profiles\Tester\MultiStrategyAutonomousEA.set` (`; this file contains last used input parameters for testing/optimizing ...`), and the next run that omits a key is started from that file. Measured: a one-day window with `InpMinLiveVoters=2` explicit gave 264 `min_voters` rejects; the same window with the line omitted also gave 264, on the same expert and also on `Crash 1000 Index` (a symbol the harness had never tested) — the cache is per expert, not per symbol. Parking that `.set` aside and re-running the same omitted-input window gave **0 `min_voters` rejects and 36 `single_voter_floor`** — the shipped default of 1 is what the EA reads (the `.set` was restored afterwards). Two consequences are now recorded: an omitted input is never a default test, and a default can only be verified by removing that file.

**Four windows re-measured cold on the new build, against Batch 284's one-voter baselines** (`Volatility 75 Index` M15, Model=1, deposit 10,000, `InpQuorumProfile=1`, `InpMinLiveVoters=1`, all four state files cleared before each): `2026.09.15`->`09.22` **-68.61 (-0.686%), 984 fills** (baseline -0.686 / 984); `09.22`->`09.29` **-4.96 (-0.050%), 1,001 fills** (baseline -0.050 / 1,001); `09.29`->`10.06` **-22.96 (-0.230%), 881 fills** (baseline -0.230 / 881); `10.06`->`10.13` **+101.26 (+1.013%), 1,041 fills** (baseline +1.013 / 1,041). Equity read off the run's own 10,080 `[COMPOUNDING-TIER-HEARTBEAT]` samples; window 4 and 5 derived `min/max` 9903.65 / 9941.5 and 9995.04 / 9977.04 end points, window 6 `9887.77 -> 10303.78`. So the changed default produces bit-identical books on every window where the value is explicit — no build drift, and the six-window distribution (mean +0.46%, sd 0.92 pp, t 1.2) is unchanged. **What this proves and what it does not:** the setting that ships is the one with evidence and it reproduces; the system is still break-even within noise, not proven profitable.

**Tooling observed, both worth keeping:** (1) `Tools\run_window.ps1` backgrounded through the sandbox is now killed mid-run on this host (`kill sandbox processes failed`, terminal64 torn down at 9%), so the working launch is `Start-Process terminal64.exe -ArgumentList /config:<ini> -WindowStyle Hidden` with the cold reset done explicitly (archive `strategy_scoreboard.csv`, delete `strategy_scoreboard.csv`, `compounding_tier_state.csv`, `CrashRecoveryState.json`, `AI_Health_Dashboard.csv`), then poll the terminal log for `processing N %` and `last test passed`; wall clock 42-43 min per 7-day window under current load. (2) `Tools\run_summary.ps1` segments by simulation-time regression, which cannot split two adjacent runs that meet at midnight (09.21 23:59 -> 09.22 00:00 is monotonic), so a two-run journal reads as one 21,596-sample run; the reliable read is "the last 10,080 heartbeats are the last run", and fills are the `[EXECUTION-RECEIPT]` count between the first and last of those samples.

New test inis: `Tools\backtest_def_w3.ini`, `_w4`, `_w5`, `_w6` (all explicit `InpQuorumProfile=1` + `InpMinLiveVoters=1`); probes `Tools\backtest_probe_ctl.ini` (explicit 2), `backtest_probe_def.ini` (omitted), `backtest_probe_crash.ini` (omitted, fresh symbol). Verification: compile `OVERALL SUCCESS`; four windows reproduce their baselines to the cent; default probe 0 vs 264 `min_voters`. Not done: the default was not tested in six windows by omission (four windows used explicit 1, and one probe proves the default), `backtest_report.htm` is still not written so still no MT5 profit factor / drawdown / Sharpe, and nothing committed.
### Batch 287: the same streak rule, applied to size instead of entry — measured on two windows and rejected

Batch 286 proved that holding a symbol's entry after a losing run moves the risk rather than removing it (-4.75 pp), so this batch took the other half of the idea: keep the entry and the slot, shrink the stake. The streak counter now exists regardless of the brake policy (`RecordSymbolClose` counts every close; the brake still gates on `InpSymbolLossStreakLimit`, default 0 = off), and `GetSymbolStreakRiskScale(minStreak, factor)` returns the multiplier once the run is long enough. `CCandidateBuilder::BuildCandidate` gained a trailing `double symbolStreakScale = 1.0`, applied to `proposedRisk` **before** `CalculatePositionSizeWithRisk` — the same slot and the same reason as the Batch 278 volatility band, because the lot and the booked `riskPercent` have to remain one number — with one throttled `[STREAK-SIZE] <sym> | losing run N | risk x% -> y%` line per five minutes. The orchestrator computes the scale beside the existing entry gate and passes it in. New inputs `InpSymbolStreakRiskScale` (**1.0 = off**) and `InpSymbolStreakRiskMinCount` (2), wired through `SharedEAInputs`, `OrchestratorConfig` (fields plus ctor defaults) and both root `.mq5` config assignments.

**Measured** (same instrument/period/deposit, Model=1, every run cold, one-voter arm, brake off, scale 0.50 after 2 losses). Window 09.01->09.08: control **+98.29 (+0.983%), 849 fills, 281 closes** against the variant's **+238.23 (+2.382%), 1004 fills, 278 closes** — **+1.40 pp**, with the parameter proven in force first: **500 `[STREAK-SIZE]` lines over 7 symbols**, V75 reading `losing run 2 | risk 1.00% -> 0.50%`. Window 09.08->09.15: half stake **-396.81 (-3.968%), 449 fills, 7524 decisions, 168 rejects, 9603.19..10014.63** against a control re-run **on this build** at **+171.28 (+1.713%), 442 fills** — bit-identical to Batch 284's +1.713/442, so no build drift and the rule alone costs **-5.68 pp**. Two windows: **+1.40 pp, -5.68 pp, mean -2.14 pp**.

**Why it loses, from the control's own close sequence:** V75 reads `-18.20, -18.96, -55.82, -32.22` then `+97.15` and later `+149.09` — the biggest winners of the window arrive straight after the losing runs, and halving the stake after two losses halves precisely those recovery trades, while Batch 285 already showed 11-15 V75 closes decide the window. Batch 286's premise (82% of loss dollars inside runs of 2+) is true, and so is its complement. Fills rose again (442 -> 449) as smaller stakes freed per-trade budget, the same "risk is conserved by the budget machinery" shape both per-symbol rules have shown.

**Tooling, both found the hard way.** (1) `Tools\run_window.ps1` hard-coded `Tester\logs\20261112.log` and `logs\20261112.log`; both MT5 logs are named after the wall-clock day, so a run crossing midnight wrote into `20261113.log` and the driver printed `no EA output appended` while the tester was 63% through the window. It now resolves the newest `yyyyMMdd.log` at launch and re-resolves after the wait, using offset 0 when the day rolled. (2) **The tester agent shares port 3000 with anything else on the machine**: a local `node` dev server bound `0.0.0.0:3000` mid-sweep and every later launch died in 0.0 s with `result "some error after pass finished"` plus `Core 1: tester agent authorization error`. Port 3000 must be free before a sweep. Also: `run_window`'s `-TimeoutSec` does not kill the tester, so a timed-out window keeps running and the next `-Cold` launch collides with it — check for `metatester64` before starting the next ini.

**New document:** `RUNS_AND_GAINS.md` at the repository root — every batch's runs, numbers and conclusion in one place, with the method (harness, cold rules, P&L source, determinism, the 0.92 pp noise floor) stated before the numbers.

Verification: `sync_files.ps1` then `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 900` -> **`OVERALL SUCCESS` - 0 errors, 0 total warnings** on all eight programs (root EAs 144.4 s / 131.8 s). Not done: two windows only, no third window for the rule, `backtest_report.htm` still not written so still no MT5 profit factor / drawdown / Sharpe, and the port-3000 dependency is documented rather than removed. Nothing committed.
### Batch 286: a per-symbol loss-streak brake was built, tested and rejected — the losses are a run, but breaking the run does not save the money

Batch 285 established *where* the money is (11-15 closes of `Volatility 75 Index` at ±23 a close). This batch asked the obvious next question: if the damage arrives as a *series*, does stopping the series help? It now has a measured answer instead of an opinion — **no**, not in this form.

**1. The premise is true: the losses are a run.** `Tools\close_sequence.ps1` prints the ordered close P&L for one symbol, per run. On the committee arm's full 7 days, `Volatility 75 Index` closed 13 times, **11 losers**, longest losing run **5**, and **−244.22 of the −299.32** total sat inside losing runs of 2 or longer (82%). Nothing in the risk layer had that shape: each entry was sized normally and the sequence was never treated as a sequence. So the mechanism is real, and the first hypothesis — "brake the symbol after consecutive losses" — looked justified by the data rather than by taste.

**2. The brake as built.** `CEnterpriseStrategyManager` gained symbol-scoped streak state (`m_symbolLossStreak`, `m_symbolStreakBlockedUntil`, policy limit + cooldown), fed from the close path in `StrategyMgrTradeFeedback::OnTradeTransaction` (the same place that prints `[EnterpriseManager] Trade Closed`, where `dealSymbol` and `netProfit` are already in hand) and read in the per-symbol entry loop of `EAOrchestrator::GenerateAndProcessSignals`, immediately beside the existing `symbol_feed` hold. A winner resets the count; a trip prints `[SYMBOL-STREAK] <sym> | N consecutive losing closes -> entries held for M min`; the gate prints a throttled `[ENTRY-GATE] ... reason=symbol_loss_streak`. Inputs: `InpSymbolLossStreakLimit` (**0 = off, the shipped default**) and `InpSymbolLossStreakCooldownMin` (60). Because the manager is already one instance per symbol, the streak needed no map and no allocation.

**3. The measurement.** Same window (`2026.09.01`→`09.08`), same instrument/period/deposit, Model=1, every run cold and on the same new build, one-voter arm throughout (`InpQuorumProfile=1`, `InpMinLiveVoters=1`):

| arm | equity delta | fills | closes | note |
|---|---|---|---|---|
| control, breaker **off** (`limit=0`) | **+98.29 (+0.983%)** | 849 | 281 | bit-identical to Batch 285 — 10080 samples, 7077 decisions, 139 rejects |
| breaker **2 losses / 12 h** | **−376.72 (−3.767%)** | 1216 | 239 | −4.75 pp against control |
| breaker 3 losses / 3 h | −271.64 (−2.716%) at truncation | 879 | — | driver hit its 1800 s cap at 7604/10080 samples, so **not comparable** |

**4. Why it lost, and why that is the useful part.** The brake did what it was asked on the target symbol (V75's first two closes of 09-01 trip it, and its third close moves from −55.82 to −37.35), but the book as a whole got worse. Blocking an entry frees a slot, a send allowance and risk budget, so the capital went somewhere else instead: `Step Index` fills went **63 → 315**, `XAUUSD` 487 → 647, while `Crash 1000` closed **33 times instead of 64** for a similar loss (−110.67 vs −48.32). Fills rose 43% while closes fell 6%. In other words the rule does not remove risk from the window, it *reallocates* it, and on this window it reallocated it into worse hands. That is the same lesson Batch 284 reached from the other direction ("more fills is not a quality signal") arriving at the level of a single symbol.

**5. What this does not settle.** One window, one instrument, one-voter arm. The 3-loss point was cut off and is unproven; a longer cooldown, a cooldown that ends on a win rather than on the clock, or a rule that shrinks the symbol instead of blocking it are all untested. What *is* settled is that the shipped default stays **0** — the feature exists, compiles, and is measured to be negative at the only setting it has been run at, so it ships off rather than as a guess.

**Verification:** `sync_files.ps1` then `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 900` → **`OVERALL SUCCESS` — 0 errors, 0 total warnings** on all eight programs. Determinism held: with the breaker off, the new build reproduces Batch 285's one-voter arm to the sample (`+98.29`, 10080 samples, 849 fills, 7077 decisions, 139 rejects), which is the fifth bit-identical reproduction of that window, and the archived final scoreboard is **byte-identical** to Batch 285's (`SHA256 33487FF0…083B6`, 18,510 B, both files), so the new code changes nothing when the input is 0. New readers: `Tools\close_sequence.ps1` (ordered close P&L per symbol + streak statistics) and `Tools\run_summary.ps1` (one pass giving per-run heartbeat delta, fills/decisions/rejects, per-symbol net and the ordered close list — written because `run_window.ps1`'s own summary is lost when the task returns). Doc edits BOM-free UTF-8. Nothing committed.

**Not done:** the 3-loss/3 h arm never finished (driver cap 1800 s, hit at 76% of the window); only one window was tested; no multi-window distribution exists for any breaker setting; `InpMinLiveVoters=1` is still an ini value rather than a shipped default; `backtest_report.htm` is still not written, so still no MT5 profit factor / drawdown / Sharpe.

### Batch 285: the money is two instruments, not two hundred trades — and the per-window scoreboard archive was mislabelling itself

Attribution was the open item from Batch 284 ("the scoreboard CSVs are archived per cold window and nothing has read them"). Reading them produced two findings, one about the book and one about the tooling.

**1. Why `trades x avgProfit` cannot be dollars.** Both arms of the `2026.09.01 -> 09.08` window were rerun cold and their scoreboards diffed row by row: control (committee, `InpMinLiveVoters=2`) 30 rows with trades / 437 trades / 182 wins / 9 parked; variant (one voter) 24 rows / 463 trades / 177 wins / 10 parked. Summing `trades * avgProfit` gives **2873.97** for the control and **3512.41** for the variant, against account deltas of **-74.49** and **+98.29** — so `avgProfit` is not net dollars per trade and the scoreboard alone can never be reconciled to equity. It answers "which rows traded and which rows won", not "where did the money go".

**2. The journal does carry the money, and it says the book is two bets.** `[EnterpriseManager] Trade Closed | Symbol: X | ... | Net Profit: p` gives per-close gross P&L, and `[TRADE-ATTRIBUTION] Contributors: A,B,` gives the strategy names for that close. Joining them per run (both arms, full 7 days, 09.01-09.07):
- committee arm: **`Crash 1000 Index` +283.60 on 65 closes**, `Volatility 25 Index` +36.33 on 95, `Jump 25` +9.56 on 16, `XAUUSD` +2.00 on 2, `GBPUSD` +0.29 on 1 — against **`Volatility 75 Index` -299.32 on 13 closes** and `Step Index` -24.37 on 25.
- one-voter arm: **`Volatility 75 Index` +261.22 on 11 closes**, `Jump 75` +11.21 on 58, `Step` +7.71 on 14, `Volatility 25` +5.22 on 85 — against **`Crash 1000 Index` -123.06 on 68 closes** and `Jump 25` -3.39 on 14.
- strategy families over both arms: `Support/Resistance` and `Turtle Soup` are **~0.15-0.45 dollars per close** (+30.78/180 and +26.57/105 closes in one arm, +79.48/212 and +102.78/114 in the other), i.e. hundreds of closes producing tens of dollars.

So the P&L of a 7-day window is set by **11-13 closes of `Volatility 75 Index` at ~±23 dollars each (0.23% of a 10,000 deposit per trade)** and 65-68 closes of `Crash 1000 Index`, while the 200+ closes of the two big strategy families are noise. That explains what Batch 284 could not: why fill count had no relationship to outcome, and why the cross-window standard deviation is 0.92 pp on a book averaging +0.46% — the distribution is dominated by two instruments whose per-trade size is ~50x the average row's contribution.

**3. Tooling defects found and fixed in the same batch.** `Tools\run_window.ps1` archived the scoreboard **before** launching the tester, so a file named after arm A contained what arm B had produced, and both arms of a paired window wrote the same filename (second overwrote first). Archiving is now **post-run**, named `scoreboard_<iniBase>_<fromDate>-<toDate>.csv`, and prints `scoreboard archived: <name>`. Two new readers: `Tools\scoreboard_diff.ps1` (base vs variant, rows sorted by change in trades and wins, plus a by-strategy roll-up) and `Tools\attribute_pnl.ps1` (segments the tester journal into runs by **simulation-time regression** — the wall-clock column is not a run identity because MT5 flushes the journal of a finished run with one stamp — and joins closes to contributors). The journal is 5.6 GB, so it reads only a `-TailMB` window; a naive full scan was killed by the harness and a `[math]::Max(0, <int64>)` literal silently selected the Int32 overload until the value grew past 2 GB.

**Verification.** Both arms re-ran cold on the Batch 282 `.ex5` and reproduce point for point — committee `-74.49 (-0.745%) / 1006 fills / 5452 decisions / 1902 rejects`, one-voter `+98.29 (+0.983%) / 849 fills / 7077 decisions / 139 rejects` (the one-voter figure is now its **fourth** bit-identical reproduction). No source changed, so no recompile. Doc edits BOM-free UTF-8. Not done: attribution leaves **53-71 of 252-266 closes per run unattributed** (not every close emits a Contributors line), so per-strategy dollars are a lower bound and the split across multiple contributors is an apportionment rather than a measurement; per-close `Net Profit` is gross, which is why the sums fall ~80 dollars short of the heartbeat delta (commission, ~0.20 per close); `backtest_report.htm` still is not written, so still no MT5 profit factor / drawdown / Sharpe. Nothing committed.

### Batch 284: six cold windows say the one-voter gate is real and the book is still break-even, and the "more fills" theory is dead

Batch 283 answered "which knob moves the book" on one window and reproduced it bit-identically. That made the
harness trustworthy but left the real question open: is `+0.983%` a centre or an accident. `Tools\run_sweep.ps1`
cannot answer that any more - after Batch 282 the tester is deterministic, so N repeats of one window are N
identical numbers - so `Tools\run_windows.ps1` walks **different** 7-day windows instead. Same build (Batch 282
`.ex5`, no recompile), same instrument/period/deposit, every window cold via `run_window.ps1 -Cold`, every ini
naming both varied knobs explicitly (`InpQuorumProfile=1` plus `InpMinLiveVoters`).

**Arm A - one voter (`InpMinLiveVoters=1`), six windows:**

| window | P&L | fills | decisions | rejects |
|---|---|---|---|---|
| `09.01`-`09.08` | **+0.983%** | 849 | 7077 | 139 |
| `09.08`-`09.15` | **+1.713%** | 442 | 7962 | 167 |
| `09.15`-`09.22` | **-0.686%** | 984 | 7440 | 177 |
| `09.22`-`09.29` | **-0.050%** | 1001 | 6833 | 227 |
| `09.29`-`10.06` | **-0.230%** | 881 | 6812 | 151 |
| `10.06`-`10.13` | **+1.013%** | 1041 | 7537 | 143 |

mean **+0.46%**, stdev **0.92 pp**, 3 wins of 6, `t` = **1.2**. Translation: the book no longer loses, and it does
not prove it earns. Batch 283's `+0.983%` is a point inside that band, not an edge.

**Arm B - committee (`InpMinLiveVoters=2`), same binary, four of the same windows:**

| window | P&L | fills | decisions | rejects |
|---|---|---|---|---|
| `09.01`-`09.08` | -0.745% | 1006 | 5452 | 1902 |
| `09.08`-`09.15` | **-1.279%** | 465 | 5786 | 2819 |
| `09.15`-`09.22` | -0.572% | 1026 | 5585 | 2270 |
| `09.22`-`09.29` | **-2.625%** | 879 | 5117 | 2054 |

mean **-1.31%**, stdev 0.93 pp, **4 losses of 4**, `t` = **-2.8**. Note the reject counts: the committee refuses
2,054-2,819 candidates per window where one-voter refuses 139-227. That is the gate, doing exactly what Batch 283
described - and losing more money for it.

**Paired, which is the only fair read:**

| window | one-voter | committee | delta |
|---|---|---|---|
| `09.01` | +0.983% | -0.745% | **+1.73 pp** |
| `09.08` | +1.713% | -1.279% | **+2.99 pp** |
| `09.15` | -0.686% | -0.572% | -0.11 pp |
| `09.22` | -0.050% | -2.625% | **+2.58 pp** |

mean delta **+1.80 pp**, stdev 1.38 pp, `t` = **2.6** at n = 4 (p about 0.08), and the gate has never been worse
than 0.11 pp. That is the strongest single-variable evidence this repository has produced, and it is still short of
a clean significance bar - stated as such, not rounded up.

**A hypothesis formed and killed inside the batch:** the first four windows showed fill count running opposite to
the outcome (442 fills `+1.71%` ... 1001 `-0.05%`), which reads as "the marginal trades are negative-expectancy".
The committee control destroys it - on `09.08` it took **fewer** fills (465) and lost **more** (`-1.279%`), on
`09.22` fewer fills (879) for fifty times the loss - and the final window took the **most** fills of any run (1041)
for `+1.01%`. So fill count is not a quality signal at all. What moves the result is expectancy per
trade, which one-voter changes not by sizing differently but by letting single-strategy entries through
that the committee used to refuse. The theory is withdrawn here rather than left standing in the file.

**What should happen next, in order:** (1) per-window strategy breakdown, because a +1.8 pp paired gain is worth
knowing by row - the scoreboard CSVs are archived per cold window;
(2) walk forward, not sideways - every window here is an adjacent 7-day slice of 2026-09/10 on one instrument,
which is out-of-window but not out-of-regime; (3) leave the other thresholds alone, since Batch 283 showed three
of the four are inert and autotuning them would chase nothing.

**Tooling:** `Tools\run_sweep.ps1` is now the wrong instrument (it repeats one window). `Tools\run_windows.ps1
-IniNames a.ini,b.ini` walks different windows, prints equity/fills/decisions/rejects per window plus
mean/stdev/min/max/win-count. Both ship in `Tools\`.

**Tooling defect found and fixed here:** `run_window.ps1 -Cold` archived `strategy_scoreboard.csv` beside the
agent file, and the tester agent wipes its own `MQL5\Files` between runs - so of seven runs only the last
scoreboard survived and the per-row attribution for six windows was destroyed. The archive now also writes to
`Tools\artifacts\scoreboards\scoreboard_<from>_<to>.csv` inside the repository. The surviving window
(`10.06`-`10.13`, `+1.013%`) was copied there and read: 31 of 300 rows carried trades, concentrated in
`Volatility 25 Index` Support/Resistance (108 trades / 34 wins / health 0.35 / avgProfit 4.40), `Jump 75 Index`
Support/Resistance (100 / 39 / 0.39 / 0.65) and `Volatility 25 Index` Turtle Soup (78 / 26 / 0.35 / 4.65) -
a row winning one trade in three for 0.65 units average is the first cost suspect, and it is recorded as
`REMAINING_WORK.md` item 48 rather than acted on from one window.

**Not done:** per-window per-strategy attribution for the other six windows (their archives are gone; the re-run
with the new archive is the fix); `backtest_report.htm` is still not written by this terminal, so there is still
no MT5 profit factor, max drawdown or Sharpe; no walk-forward segment; nothing committed.
### Batch 283: three "thresholds" were inert and the fourth one is the whole book

Batch 282 made the tester deterministic, so a single cold window became readable. This batch used that to
test the knobs the user wanted autotuned, and found the ladder is one input, not a tuning surface.

**Measured, one build, cold start, `2026.09.01`->`09.08`, Model=1, `Volatility 75 Index` M15, deposit 10,000:**

| variant | P&L | fills | decisions | rejects |
|---|---|---|---|---|
| baseline (BALANCED, floor 0.70, `InpMinLiveVoters=2`) | **−74.49 (−0.745%)** | 1006 | 5452 | 1902 |
| `InpSingleVoterFloor=0.65` | −74.49 (−0.745%) | 1006 | 5452 | 1902 |
| `InpQuorumProfile=2` (AGGRESSIVE) | −74.49 (−0.745%) | 1006 | 5452 | 1902 |
| **`InpMinLiveVoters=1`** | **+98.29 (+0.983%)** | **849** | **7069** | **139** |

- AGGRESSIVE was confirmed in force, not assumed: the run's `[CONSENSUS-QUORUM]` lines read
  `supportFloor=0.15` and `buyQuorum=0.45` where BALANCED reads 0.25 / 0.50, and the fills-by-symbol table,
  the reject buckets (1753 / 145 / 1 / 3) and the scoreboard (`rows 300`, `with trades 30`, `parked 9`) came
  back identical to the baseline. So `InpQuorumProfile`, `InpQuorumThreshold`, `InpConsensusSupportFloor*`
  and `InpSingleVoterFloor` gate nothing on this window; every candidate that fails, fails upstream of them.
- `InpMinLiveVoters=1` is the first input in this repository that changes the trade set. Rejects collapse
  1902 -> 139 (`min_voters` 1753 -> **0**, `single_voter_floor` 145 -> 137), decisions rise 5452 -> 7069,
  fills fall 1006 -> 849, equity samples 10080 (`2026.09.01 00:00:01` -> `09.07 23:59:00`), first 10000,
  last 10098.29, min 9795.25, max 10138.24. The book rearranged rather than merely growing: `XAUUSD` 618 -> 487,
  `Step Index` 129 -> 63, `Volatility 25` 95 -> 91, `Crash 1000` 65 -> 76, `Jump 75` 48 -> 62, `EURUSD` 16 -> 35,
  `USDJPY` 1, `GBPUSD` 0. Scoreboard `with trades` 30 -> 24, `parked` 9 -> 10.

**Why the profile could never move it (the code path, verified by reading it):** `EAOrchestrator.mqh:1869-1872`
does `manager.SetMinQuorum(minLiveVoters)` **and** `manager.SetIntrabarMinQuorum(minLiveVoters)` from
`InpMinLiveVoters`, and `ApplyQuorumProfile` (`ConsensusWeightingConfig.mqh:160-180`) writes `minQuorum`,
the threshold and both support floors but **not** `intrabarMinQuorum`. Every rejected candidate in the window
was an intrabar evaluation. So the preset changes values that no candidate ever reads, and the field it does
not own is the one that binds.

**Documentation defect corrected in the same batch:** `README.md`, `RUNTIME_DECISION_GRAPH.md`,
`SYSTEM_STRUCTURE.md` and `AGENTS.md` all stated `MIN_CONSENSUS_VOTERS = 2` and concluded that "no preset and
no input can form a one-voter committee". The constant is **1** (`ConsensusEngine.mqh:25`, changed by Batch
273); the 2 those documents were really seeing was `InpMinLiveVoters`' default arriving through the setters
above. All four claims now say 1 and name the input. The behaviour they predicted was testable only after
Batch 282, and the table above is the answer.

**Measurement hazard found and fixed in tooling:** a tester `.ini` that omits an input does **not** get the
EA's default — MT5 reuses the previous run's value for the same expert/symbol/period. A run created without
`InpQuorumProfile` inherited the AGGRESSIVE preset from the run before it (log showed `supportFloor=0.15`
on a file that never set a profile). That run was killed mid-flight rather than reported. Every A/B ini in
`Tools\` must now state **every** varied knob explicitly; `backtest_voters1.ini` carries
`InpQuorumProfile=1` alongside `InpMinLiveVoters=1` for exactly that reason.

**Verification:** no code changed, so no recompile was required; the runs used the Batch 282 build
(`MultiStrategyAutonomousEA.ex5` 1,747,648 B) whose eight programs are `OVERALL SUCCESS — 0 errors,
0 total warnings`. Documentation-only edits were written BOM-free UTF-8. **Reproducible, not a fluke:**
a second full cold run of `backtest_voters1.ini` is **bit-identical** — `result: successfully finished after
0:27:37.575`, `samples=10080 first=10000 last=10098.29 min=9795.25 max=10138.24 delta=98.29 (0.983%)`,
`fills 849`, `decisions 7077`, `rejects 139`, same per-symbol table (`XAUUSD 487`, `Volatility 25 Index 91`,
`Crash 1000 Index 76`, `Step Index 63`, `Jump 75 Index 62`, `EURUSD 35`, `Jump 25 Index 19`,
`Volatility 75 Index 15`, `USDJPY 1`) and same scoreboard (`300 / 24 / 10`). Not done: `+0.983%` is still
**one window** — a reproduced observation, not a distribution (`run_sweep.ps1 -Runs 5` remains unrun);
`backtest_report.htm` is still not written by this terminal, so there is still no MT5 profit factor,
drawdown or Sharpe; and nothing was committed.

### Batch 282: the backtest was not reproducible, so every number in Batch 281 was half market and half wall clock

Same binary. Same window (`2026.09.01`->`09.08`, Model=1, M15, Volatility 75 Index, deposit 10,000). Cold state both times. Run one: **+503.45 (+5.034%) on 308 fills**. Run two: **-488.94 (-4.889%) on 379 fills**. That is not a strategy result, it is a machine-load result, and it withdraws the causal claim Batch 281 published: **-436.57 -> -79.90 is not a 5.5x improvement**, it is two single runs whose spread is ten percentage points wide, and the same goes for the "min-lot costs -3.32%" comparison. The defect underneath is mechanical and one line long. Every behavioural throttle in this tree measured time with `GetTickCount()`, which is *real* elapsed milliseconds since the terminal started, while the tester advances roughly 435x faster than real time. So a "500 ms" trailing rule fired about once every 218 simulated seconds in backtest; a "200 ms" microstructure throttle fed a different number of ticks per bar in every run, so VPIN/OFI differed, votes differed and the trade path diverged; and `CConsensusCache`'s TTL expired on load rather than on market time. The same defect also meant the backtest never exercised the trailing path the live EA runs.

**The fix** is one clock for anything that changes a decision: `Core/Utils/EAClock.mqh` defines `uint EAClockMs()`, which returns `(uint)(TimeCurrent() * 1000)` under `MQL_TESTER` and `GetTickCount()` everywhere else. Live behaviour is untouched. Five call sites moved onto it: `CConsensusCache` TTL (`Get`/`Store`), `COrchestratorMathEngineHub::FeedMicrostructure` (200 ms VPIN/OFI feed), `CPositionLifecycleManager::ManageBreakevenAndTrailing` (500 ms breakeven/trailing pass), the skew-step tick feed in `EAOrchestrator::OnTick` (500 ms), and the scalp fast path (1 s). Millisecond TTLs are rounded down to `TimeCurrent()`'s one-second granularity, which is deterministic; a 2^32 ms wrap is 49.7 simulated days, longer than any window used here.

**Proof that it worked, and it is the only kind of proof this repository now accepts:** two more cold runs of the same build after the fix are **bit-identical** - both `-74.49 (-0.745%)`, `fills 1006`, `decisions 5452`, `rejects 1902`, `min 9858.73`, `max 10031.04`, the same per-symbol fill table (`XAUUSD 618`, `Step Index 129`, `Volatility 25 Index 95`, `Crash 1000 Index 65`, `Jump 75 Index 48`, ...) and the same scoreboard (30 rows with trades, 9 parked). Spread is **0.00 pp** where it was 10 pp one build earlier, so an A/B is now a measurement instead of a coin flip.

**The behaviour change this exposes, stated rather than buried:** fills go from 308-379 to **1006** on the same window, because the throttled subsystems now run once per simulated second instead of once per 500 real milliseconds - at 435x speedup the old code sampled trailing roughly once every seven M15 bars, and the tester is now exercising the cadence the live EA actually runs. That is a correct change and a large one: the window now reads **-0.745% on 1006 fills** rather than -4.9% on 379, and the book is dominated by one instrument (`XAUUSD` 618 of 1006 fills). Both facts are consequences of the clock fix, not of a strategy edit, and they are what the next batch has to look at.

**The first A/B that is now readable, and it says the knob is inert:** re-running the same window with `[TesterInputs] InpSingleVoterFloor=0.65` - confirmed live in the run's own log, `[CONSENSUS-VOTER-FLOOR] Volatility 75 Index | singleVoterFloor=0.65` per symbol - produced **exactly the same result as 0.70, to the cent**: `-74.49 (-0.745%)`, `fills 1006`, `decisions 5452`, `rejects 1902` (of which `single_voter_floor` 145 both times), same equity `min 9858.73 / max 10031.04`, same per-symbol fills, same scoreboard. So the lone-voter confidence floor does not gate a single additional trade on this window: every signal it would have admitted in the 0.65-0.70 band is already killed upstream. The Batch 281 reading ("0.65 doubled the loss") was noise; the real finding is stronger and cheaper to act on - **this threshold is not the bottleneck, so it must not be autotuned**. What actually binds is `min_voters` (**1753** of 1902 rejects) and the scalp path (`[SCALP-SIGNAL-REJECT]` 32,216 lines), and the fills that do happen are concentrated: `XAUUSD` 618 of 1006.
**Tooling, so this cannot happen quietly again:** `Tools\run_window.ps1 -Cold` now archives and removes **all four** files the EA reloads at init (`strategy_scoreboard.csv`, `compounding_tier_state.csv`, `CrashRecoveryState.json`, `AI_Health_Dashboard.csv`), because resetting only the scoreboard left the compounding tier ladder carried over and that alone moved a "cold" rerun from +2.89% to -4.34%; it also classifies rejects by text (`single_voter_floor` / `min_voters` / `support_floor` / `quorum_ratio` / `other` - the previous `-split '|'` was a regular-expression alternation and returned nothing) and prints a `--- strategy scoreboard ---` section. `Tools\run_sweep.ps1 -Runs N` chains N cold windows and prints mean / stdev / min / max, which is the only honest way left to answer "is this profitable".

**What is still true from Batch 281:** the attribution fix is real and structurally verified - scoreboard rows carrying trades went 2/300 -> 31/300 -> 33/300 -> 40/300 across runs and the EA parks 8-10 rows on its own (`Volatility 75 Index Support/Resistance` health 0.35 over 18 trades, `Crash 1000 Index Turtle Soup` 0.35 over 34, `Jump 75 Index Support/Resistance` 0.369 over 84). The single-voter floor is now a runtime input and the `.ini` sets it without a recompile (`[CONSENSUS-VOTER-FLOOR] <sym> | singleVoterFloor=0.65` printed per symbol). What is withdrawn is only the P&L attribution that was read off one run each.

Verification: `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 900` -> **`OVERALL SUCCESS` - 0 errors, 0 total warnings** on all eight programs (`MultiStrategyAutonomousEA.mq5` 61.9 s, `MultiStrategyTestingEA.mq5` 59.8 s, `TrainingDataExporter.mq5` 17.8 s, five others 0/0). Not done: the determinism proof is two runs of one window, not a distribution; `backtest_report.htm` still is not written by this terminal, so MT5's own profit factor / drawdown / Sharpe remain unavailable and every figure here is rebuilt from `[COMPOUNDING-TIER-HEARTBEAT] balance=` samples plus receipt/deal lines.

## 2026-11-19 — Exposure Caps Include In-Flight Reservations

- Per-symbol and total position caps now count open EA-owned positions plus outstanding virtual reservations; the current candidate's own reservation is excluded so it is neither double-counted nor lost from concurrent capacity accounting.
- Removed the unreferenced fast-scalp pending-order sender, its stale enabled/TTL settings, and its no-op orchestration polling. The async tracker send is cancellation-only.
- Closed remaining-work item 15 for reachable entry paths. Lifecycle pyramiding is still disabled/unconfigured and remains out of scope until its add path gets unified-risk validation and a valid stop.
- This supersedes the preceding historical note that engine entries still bypass `CTradeManager`: the ATR, grid, spike, and live fast-scalp market senders now route through it. The remaining raw send calls belong to the shared async executor or order cancellation.
- Verification: all eight MetaTrader targets compile with 0 errors and 0 warnings; `git diff --check` passes. No live run or backtest was performed.

## 2026-11-21 — Full Sync and Compile

- Anchored `sync_and_compile.ps1` to `$PSScriptRoot`; the previous hard-coded `D:\TraeProjects\metatrader-multistrategy-ea` path pointed at a separate clean `main` checkout rather than the active Tempo worktree.
- The first full build found and fixed invalid C++ pointer syntax in `FastScalpEngine.mqh` and a missing `CDashBridgeTransport::LogState` definition.
- Final `-All -KeepLog -MaxCompileWaitSec 900` run: all eight root programs compiled with **0 errors / 0 warnings**. SHA-256 checks confirmed the fixed headers match the MT5 mirror.
- No live/demo run or backtest was performed.
## Audit round - execution-side price references and family classification

#### Fixed - bid/ask execution-side measurement
- **S/R consensus path measured stops off BID for buys.** `StrategySupportResistance` converted the sub-strategies' BID-anchored `entryPrice`/`stopLoss`/`takeProfit` into pip distances and fed them to `IsSignalTradable` and `SetProposedStops`. A BUY fills at ASK, so the stop distance was understated by the spread in both the guard and the proposed stops. Distances and the guard now measure off `execPrice` (ASK for BUY, BID for SELL).
- **Same defect in the trend path.** `StrategyTrend` + `CTrendEntryTypes`: every entry type anchors `entryPrice`/`takeProfit` on `SYMBOL_BID` for both directions; the consumer now measures guard and pip distances off the execution side.
- **`TrendTrailingStop::ShouldMoveToBreakeven` priced sells off BID.** The sibling `CalculateTrailingStop` already used the correct side ("sell positions close at ASK"); the breakeven check was missed, so a sell's breakeven triggered ~spread early. Now direction-aware.
- **`NYOpenGapStrategy` measured SL/TP distances off unconditional BID** for both directions (the BID quote is still used for the NDOG midpoint proximity check, which is analysis-only). Distances and the tradability guard now use a direction-aware `distPrice`.
- **`StrategyCandlestick` measured pattern geometry off the pattern bar's price.** `patternPrice` is a historical close, not the fill; a drifted market could pass an inverted or understated stop through the gate. Guard and pip distances now measure off live ASK/BID.
- Verified clean: all eight ATR-stop strategies already use `isBuy ? ASK : BID`; `ICTSessionGapStrategy`, `MeanReversionStrategy` (both paths), `FVGScalper`, `BreakerBlock`, `AsianRangeBreak`, `SimpleMomentum`, `TurtleSoup` already direction-aware; `VolatilityBreakout`/`LiquiditySweep`/`RangeCompression` derive SL/TP from absolute levels so distances are anchor-honest.

#### Fixed - dead family arm
- **`DERIV_SPOT_VOLATILITY` was unreachable.** "Spot Volatility" symbol names also contain `"VOLATILITY "`, and `IsVolatilitySyntheticSymbolName` ran first in three places, so every spot-vol name classified as plain `DERIV_VOLATILITY`: `CDerivAssetProfiler::DetectFamily`, `DetectFamilyId` in `Core/Utils/Instruments.mqh`, and `GetInstrumentExecutionProfileName` (which returned `SYNTHETIC_VOLATILITY` instead of `SYNTHETIC_SPOT_VOLATILITY`). The specific arm now precedes the generic one in all three. Latent today - no shipped symbol carries `SPOT VOL` - but the profile (grid recovery enabled, family weights 1.3/0.7/0.6/1.4) was dead config.

#### Verified clean this pass
- `CTradeManager::MoveToBreakeven`/`SetTrailingStop`/`ModifyPosition` - tighten-only ratchets, correct bid/ask sides, broker min-distance normalization.
- `RiskCircuitBreaker` drawdown math, auto-recovery levels, emergency flatten.
- `CGridRecoveryEngine` - martingale progression bounded by maxDrawdownPercent, cumulative-lot cap (3x) and equity floor (50%); all family profiles currently disable it except SpotVolatility.
- `WalkForwardValidator` IS/OOS attribution arrays sized `cAll+1`, every trade accounted exactly once.
- `CDerivAssetProfiler` profile table - newer Deriv families (Pain, Switch, GainFlip...) intentionally fall through to `DERIV_UNKNOWN` (minimal profile), not a bug.

#### Verification
- `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 900` -> OVERALL SUCCESS, 0 errors / 0 total warnings, all eight programs.
- Caveat: the bid/ask measurement fixes change proposed stop distances by ~spread on BUY signals - correctness fix, needs the paired cold-window batch before any performance claim.

## Remaining-work completion pass

#### Fixed - neural trade-linked labels
- **Double-counted and sign-biased label counter.** `UpdateTradeResultByPredictionId`/`UpdateTradeResult` incremented `m_tradeLinkedLabels` only when `profitLoss > 0`, while `ResolveBarriers` also increments it for every `linkedToTrade` example at label resolution - so wins counted twice and losses never. The counter is now owned solely by label resolution, which counts every linked outcome once regardless of sign; the update paths only set `linkedToTrade`. Stale comment claiming the path was unwired corrected (it is wired: reserve -> order comment/position map -> close-drain -> `UpdateTradeResultByPredictionId`).
- **Same-bar double-touch now resolves adverse-first.** `NeuralNetworkStrategy::ResolveBarriers` took `upperHit` before `lowerHit`, so a bar touching both barriers always labelled BUY-class - the opposite of the Python `triple_barrier` stop-first convention (and of `CNeuralTrainingDataManager`, which already tests the stop first). A both-touch bar now resolves to the barrier adverse to the predicted signal (BUY obs -> lower/SELL label, SELL obs -> upper/BUY label), i.e. an ambiguous bar is a loss, matching training-data semantics.

#### Enabled - the measured lot-size cap lever
- **`InpScaleLotToSymbolBudget` default false -> true** in both EAs. The mechanism (`ApplySymbolBudgetLotCap`) already existed and was correct - shrink the lot to remaining per-symbol budget with broker step/min rounding and a post-round `CalculateTradeRisk` re-check - but was opt-in "experimental". With the default on, a candidate over its symbol allocation is resized instead of dropped whenever the remaining budget can still fund the broker minimum; only genuinely exhausted budgets reject. This is the lever AGENTS.md Batch 298 identified as the only remaining path (deleting symbols measured worse). **Requires the paired cold-window batch before any performance claim** - it changes sizing on every window that does not override the input.

#### Verified already-complete (no change needed)
- Engine sends: `SpikeHunterExecutor` and `GridRecoveryExecution` already route through `CTradeManager::OpenPosition` with `NormalizeAndValidateStops` + retcode diagnostics; `FastScalpPendingOrders` keeps raw `OrderSend` only because pending orders have no `CTradeManager` path, and it has stop validation + ambiguous-send recovery.
- Neural label wiring: reserve/release/bind/drain chain fully wired through `TradeExecutor` comment suffix, `UpsertPredictionPositionMap`, and `ProcessClosedPositionsForNNTraining`.
- Async reconciliation: `OnTradeTransaction` -> `ProcessTradeTransaction`, `OnTimer` -> `CheckAsyncTimeouts` -> quarantine-vs-broker-history reconciliation all wired.
- Dormant lifecycle features (pyramiding, dynamic SL/TP, partial profit taking) default disabled with no config path - cleanly inert opt-in infrastructure, deliberately not wired to new unmeasured behavior.
- `AIPerformanceFeedback` record/outcome path remains inert (no callers); neutral-zero metrics keep AI weight adaptation at baseline - documented dormant infrastructure.

#### Verification
- `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 900` -> OVERALL SUCCESS, 0 errors / 0 total warnings, all eight programs.

### The five-window book on HEAD: one payer, five rows that tax it
Per-symbol net from each window's own `Trade Closed ... Net Profit:` lines (all reconcile to the heartbeat delta):

| window | net | `Crash 1000` | `Jump 75` | `Jump 25` | `Step` | `GBPUSD` | `AUDUSD` |
|---|---|---|---|---|---|---|---|
| 08.01 | +31.72 | **+222.44 / 74** | -88.26 / 89 | -62.19 / 35 | -38.92 / 9 | -1.50 / 6 | +0.15 / 2 |
| 08.08 | +917.78 | **+1,128.57 / 76** | -81.39 / 63 | -148.34 / 39 | +18.48 / 16 | +0.73 / 5 | -0.27 / 2 |
| 09.01 | +198.79 | **+220.74 / 74** | -22.64 / 85 | +27.45 / 35 | -23.61 / 15 | -3.15 / 10 | - |
| 09.15 | +672.39 | **+948.82 / 69** | -36.98 / 92 | -107.23 / 41 | -125.93 / 14 | -5.67 / 8 | -0.62 / 2 |
| 10.06 | +397.04 | **+464.22 / 73** | +82.45 / 123 | +0.29 / 41 | -136.00 / 9 | +5.74 / 6 | -19.66 / 5 |
| **sum** | **+2,217.72** | **+2,984.79 / 366** | -146.82 / 452 | -290.02 / 191 | -305.98 / 63 | -3.85 / 35 | -20.55 / 14 |

`Crash 1000` is positive in every window and carries the whole account; every other row sums negative over the
five windows to the tune of **-767.07 USD across 755 closes**. That is the arithmetic behind "one payer, five taxes".
It is not a removal argument - Batch 298 measured removal at -0.605 pp on the same kind of paired test because
deleting a row concentrates the budget and *lowers* `Crash` closes (114 -> 94 on `08.01`).

### `InpMinLotRiskMultiplier=1.0` (uplift refused instead of lifted): neutral, do not ship
Both arms cold, same build, only that input differs:

| window | factory (cap 3.0) | cap 1.0 | delta | fills f -> 1.0 | `Crash` closes f -> 1.0 |
|---|---|---|---|---|---|
| 08.01 | +31.72 (+0.317%) | **+74.02 (+0.740%)** | **+0.423 pp** | 215 -> 214 | 74 -> 78 |
| 09.01 | +198.79 (+1.988%) | **+142.47 (+1.425%)** | **-0.563 pp** | 218 -> 219 | 74 -> 72 |

Paired mean **-0.070 pp**, sd 0.72, t **-0.14**, 1/2 positive. The gate does fire - 1,209 rejects
`lot_floor_risk_multiplier` on `08.01`, 2,358 on `09.01` (about half of all validated candidates) - but the book
barely moves: fills change by one, and the two windows disagree on sign. **Conclusion: the min-lot uplift is inert
as a lever. It does not explain the August collapse and turning it off is not a gain.** The default stays at 3.0.
### Shipped: the universe is `Crash 1000 Index` only
- Five paired cold windows, same binary, only `InpSymbolsToTrade` changed: `+10.837 / +15.786 / +2.614 /
  +17.682 / +5.134 %` against the eight-symbol arm's `+0.317 / +9.178 / +1.988 / +6.724 / +3.970 %`.
- Arm mean **+10.41%**, sd 6.53 pp, t 3.56, 5/5 positive, worst **+2.614%**, worst drawdown 2.9%.
  Paired mean **+5.98 pp**, sd 4.94, **t 2.70**, 5/5 positive.
- Mechanism is throughput: 74 closes per window in the eight-symbol book, 157-186 with only the payer left, because
  the daily budget stops being spent on rows that net negative (-767.07 across 755 closes over the same five windows).
- `Core\Config\SharedEAInputs.mqh` `InpSymbolsToTrade = "Crash 1000 Index"` with the full table above it.
  Compile `OVERALL SUCCESS`, 0 errors / 0 warnings on all eight programs (root EA 58,463 ms).
- Cost accepted: one instrument, no ballast. Restore any row by naming it in the input.
- `InpAutoAddChartSymbol` is gone from the merged tree, so the universe is authoritative - one open item closes
  without a measurement.

## Earlier batches (archives)

| Range | File | What is actually in it |
|---|---|---|
| 170–281 | [`docs/changelogs_batch170-281.md`](docs/changelogs_batch170-281.md) | 108 entries, complete for the range |
| 140–169 | [`docs/changelogs_batch102-169.md`](docs/changelogs_batch102-169.md) | 30 entries; file name says 102, content starts at 140 |
| 1–101 | [`docs/changelogs_old.md`](docs/changelogs_old.md) | 100 entries, complete for the range |

This file carries batches 282 and later only. Gaps are real, not lost content: **102–139 were never written as
numbered entries**, 198, 254, 257 and 280 are also absent, and the 140–169 archive holds a duplicated Batch 158
entry plus Batches 162–165 out of sequence at its end.
