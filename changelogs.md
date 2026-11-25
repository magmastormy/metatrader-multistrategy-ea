# Changelog

Batch 300 and later, newest first. Batches 299 and earlier are archived - see the pointer table at the bottom
of this file. `RUNS_AND_GAINS.md` holds the consolidated measured record; `REMAINING_WORK.md` holds what is open.

## [Unreleased] - 2026-11-25 (batch 300g - three stop-geometry arms measured: all three rejected, two were inert)

### The three switches, all default-off
A reader of the repo argued that fixed stops are wrong (2xATR stop, 4xATR target, snap to the last H1 swing
when it is tighter but still 1.5-3 ATR away, min RR 2.0, lot size following the stop) and that our stops/trailing
are too tight for a real account. Instead of rewriting the resolver, the three claims became three arms with
explicit switches, shipped at 0:

| switch | effect when > 0 |
|---|---|
| `InpStopAtrTimeframe` | 1 reads **H1 ATR(14)** for the stop resolver instead of the chart timeframe |
| `InpSwingSnapAtrMin` / `Max` / `BufferPips` / `LookbackBars` | snap the stop just past the last H1 swing when that stop is tighter than the designed one and still 1.5-3 ATR away |
| `InpLifecycleAtrBreakevenMult` / `TrailingMult` / `ActivationMult` | breakeven buffer, trailing distance and trailing activation scale with ATR instead of fixed points (activation replaces the `min(distance,100)` cap) |

### Window and arm results (cold, `Model=1`, 6/18 shipped defaults, `Crash+Boom`)
Window `2026.08.01`->`08.04` (3 simulated days, 4,320 one-minute samples), every switch written explicitly in
every `.ini`:

| arm | balance | delta | fills | closes |
|---|---|---|---|---|
| witness, all eight switches at 0 | 10,351.85 | **+3.519%** | 82 | 82 |
| `InpStopAtrTimeframe=1` (H1 ATR) | 10,351.85 | +3.519% | 82 | 82 |
| swing snap 1.5-3.0 ATR, 5 pips, 15 H1 bars | 10,351.85 | +3.519% | 82 | 82 |
| ATR exits, breakeven 1.0 / trailing 2.0 / activation 1.0 ATR | 9,515.69 | **-4.843%** | 107 | 107 |

**None of the three ships.** Two arms are identical to the witness to the cent, the third is -8.36 pp.

### Why the H1 ATR arm is inert
With `InpUseStrategyStops=true`, every candidate arrives carrying a stop the contributing strategy already
proposed, so `CalculateStops` never enters its own ATR branch - swapping the ATR timeframe there changes
nothing that reaches an order. The "ATR-based stop" the reader described is not our SL logic: the fixed
constants live in the strategy layer (candlestick 2xATR / swing +/-10 points capped at 3xATR, support-resistance
1.0xATR stop with 2.0xATR target, momentum 2xATR with a 1% fallback), and the resolver only clamps them
(`minSlPips = max(brokerMin, STOPS_LEVEL)*1.5, max(spread*3, 8)`, ceiling `3xATR` or %-of-price) and lifts the
target to `SL*minRR`. If fixed stops are the complaint, the change has to happen where the constants are - not
in the resolver.

### Why the swing-snap arm is inert
**0** `[STOP-SWING-SNAP]` events in 82 trades. The designed stop is already at or above the spread floor on this
book (176 `stop pinned to floor` lines in the same run), so the band where a swing stop is *tighter than the
designed stop* and still >= 1.5 ATR is nearly empty. It also produced 0 events when the same switch ran with the
H1 ATR band, so the ATR source is not the only reason. This arm cannot be judged without a probe line that
reports the swing distance and band it rejected; that is open work, not a result.

### Why the looser exits lose
Widening breakeven/trailing to 1.0/2.0/1.0 ATR did not let trades breathe into profit: it produced **25 more
fills** and a net of **-484.31** (Crash -329.46 over 82 closes, Boom -154.85 over 25). Rerunning the combined
arm (H1 ATR + snap + ATR exits) reproduced -4.843% to the cent, so the number is stable, not noise. On this book
the tight trailing is not what costs money - the extra trades are. The reader's commission argument is still
untested: this tester models spread in 1-minute OHLC and has no commission field, which is why a wider-trailing
arm can only be judged on a real-commission account.

### Two harness lessons from this batch
- **MT5 reuses the previous run's input value for any key the `.ini` omits.** A `snap` arm silently inherited
  `InpStopAtrTimeframe=1` from the run before it. Every switch is now written explicitly in every arm file.
- **A `.set` string input must be stored as a plain value.** Writing
  `InpSymbolsToTrade=...||...||0||...||N` (the numeric metadata form) made the terminal parse it as four
  symbols, accept one, and report `Accepted: 1 | Rejected: 3`. The first witness run of this session was lost
  that way and rerun.
- The tester agent log is truncated at the start of each run, so a run's journal must be copied before the next
  run starts.

### Code
`Core/Config/SharedEAInputs.mqh` (8 inputs + mappings), `Core/Orchestration/OrchestratorConfig.mqh` (fields +
reset), `Core/Orchestration/CandidateBuilder.mqh` (`ConfigureStopGeometry`, `ApplySwingSnap`, ATR timeframe),
`Core/Trading/TradeManager.mqh` (ATR breakeven/trailing/activation, `activationPointsOverride`),
`Core/Management/PositionLifecycleManager.mqh` (`ConfigureAtrExits`, range-branch ATR buffer),
`Core/Orchestration/EAOrchestrator.mqh` (wiring + `[STOP-GEOMETRY]` line), `MultiStrategyAutonomousEA.mq5`
(duplicate mapping block). Eight-target compile: **0 errors, 0 warnings**.

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

### The lot-floor uplift A/B: `InpMinLotRiskMultiplier=1.0` measured - neutral, do not ship
- `Tools\backtest_b300_floor1_w1.ini` (`08.01 -> 08.08`) and `_w3.ini` (`09.01 -> 09.08`), otherwise identical to
  `b299_cold` inis. With the cap at 1.0 the pipeline rejects any sub-min-lot scale instead of lifting it
  (`CandidateBuilder.mqh:593`, `RiskValidationPipeline.mqh:575`), which is how to test whether the uplift trades
  are the ones crowding out Crash.
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
| 170–299 | [`docs/changelogs_batch170-299.md`](docs/changelogs_batch170-299.md) | 108 numbered entries (170–281, 282–299) plus four unnumbered audit passes |
| 140–169 | [`docs/changelogs_batch102-169.md`](docs/changelogs_batch102-169.md) | 30 entries; file name says 102, content starts at 140 |
| 1–101 | [`docs/changelogs_old.md`](docs/changelogs_old.md) | 100 entries, complete for the range |

This file carries batch 300 and later only. Gaps are real, not lost content: **102–139 were never written as
numbered entries**, 198, 254, 257 and 280 are also absent, and the 140–169 archive holds a duplicated Batch 158
entry plus Batches 162–165 out of sequence at its end.
