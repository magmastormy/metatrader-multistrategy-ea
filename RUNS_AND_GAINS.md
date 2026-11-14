# Runs and Gains — the measured record

Every number in this file comes from a Strategy Tester run that was executed, not estimated. The purpose is the
one thing a changelog cannot give you: **which change was tested, what it moved, and what that means.** Each
batch below has the same shape — what was asked, what was run, the numbers, the conclusion — and each entry
states whether the change shipped, was rejected, or is still open.

To keep the file honest, the method comes first, because a number is only worth what its measurement is worth.

---

## How every number here is produced

| item | value | why it matters |
|---|---|---|
| Harness | `terminal64.exe /config:<ini>`, headless, `Model=1` | Model=2 refuses this EA (`wrong timeframe request in Open Prices mode`) because strategies read D1/H1 |
| Instrument / period | `Volatility 75 Index`, M15 | one instrument for every A/B, so the only variable is the input |
| Window | 7 simulated days, `2026.09.01`→`09.08` (and five neighbours) | deposit 10,000 USD, leverage 1:100 |
| Cold start | `run_window.ps1 -Cold` deletes **all four** init-loaded state files | clearing the scoreboard alone is not cold: a carried compounding tier moved a rerun from +2.89% to −4.34% |
| P&L source | `[COMPOUNDING-TIER-HEARTBEAT] balance=`, first vs last of 10,080 one-minute samples | `backtest_report.htm` is never written by this terminal, so MT5's own report does not exist |
| Wall clock | ≈23–26 min per window (≈435× real time) | a six-window sweep is about 2.5 hours |

Three properties make the numbers usable:

1. **Determinism.** After Batch 282 the tester is bit-reproducible: same build + same window + cold state returns
   the same equity to the cent, the same fill count and the same archived scoreboard. The one-voter window has now
   reproduced **five times**, the last time byte-identically (`SHA256 33487FF0…083B6`).
2. **One variable per arm.** Every `.ini` states every changed input explicitly, because MT5 reuses the previous
   run's value for an omitted input — a "threshold experiment" once silently inherited `AGGRESSIVE`.
3. **The size of the noise is known.** Cross-window standard deviation is **0.92 pp**. Any single-window delta
   smaller than ~1 pp is not a result, which is why the conclusions below are graded, not declared.

**What is still missing everywhere in this file:** MT5 Profit Factor, max drawdown and Sharpe. Per-close
`Net Profit` is gross, so per-symbol sums land roughly 80 USD short of the heartbeat delta (commission ≈0.20 per
close). No figure here is a distribution over a market regime — every window is an adjacent 7-day slice of
2026-09/10 on one instrument.

---

## Batch 282 — the backtest was not reproducible

**Asked:** does the EA's behaviour actually repeat, or is every A/B being read through machine noise?

**Run:** the same build and the same cold window, twice, before any code change; then twice after.

| arm | result |
|---|---|
| before the fix, run 1 | **+503.45 (+5.034%)**, 308 fills |
| before the fix, run 2 | **−488.94 (−4.889%)**, 379 fills |
| after the fix, run 1 | **−74.49 (−0.745%)**, 1006 fills, 5452 decisions, 1902 rejects |
| after the fix, run 2 | **−74.49 (−0.745%)**, 1006 fills, 5452 decisions, 1902 rejects |

**Cause:** every behavioural throttle measured time with `GetTickCount()` — real milliseconds — while the tester
advances ~435× faster than real time. A "500 ms" trailing rule therefore fired about once per 218 simulated
seconds, and a "200 ms" microstructure feed sampled a different number of ticks in every run.

**Fix:** `Core/Utils/EAClock.mqh` → `EAClockMs()` returns `TimeCurrent()*1000` under `MQL_TESTER` and
`GetTickCount()` otherwise, wired into the consensus cache TTL, the microstructure feed, trailing management, the
skew feed and the scalp fast path.

**Conclusion:** a 10 pp spread became a 0.00 pp spread. Every earlier claim built on a single run inside that
spread — including "5.5× improvement" — was withdrawn. This is the batch that made everything after it measurable.
**Status: shipped.**

---

## Batch 283 — the "thresholds" are mostly not thresholds

**Asked:** can the thresholds be optimised, or autotuned, to make the EA earn?

**Run:** four knobs, one at a time, same cold window.

| input | result vs baseline (−74.49) |
|---|---|
| `InpSingleVoterFloor` 0.70 → 0.65 | identical to the cent |
| `InpQuorumProfile` BALANCED → AGGRESSIVE | identical, and **confirmed in force** (`supportFloor=0.15`, `buyQuorum=0.45` in the run's own log) |
| support floors / quorum threshold | identical, cent for cent |
| **`InpMinLiveVoters` 2 → 1** | **+98.29 (+0.983%)**, 849 fills, 7077 decisions, 139 rejects |

**Why three were inert:** `EAOrchestrator` sets both `minQuorum` **and** `intrabarMinQuorum` from
`InpMinLiveVoters`, while `ApplyQuorumProfile` writes `minQuorum`, the threshold and both floors but **never**
`intrabarMinQuorum`. Every rejected candidate in this window was an *intrabar* evaluation, so the profile was
changing values nothing reads. The lone-voter floor was inert for the same family of reason: it is not the
binding constraint.

**Conclusion:** there is no autotuning story here yet — three of four "dials" gate nothing, and the one that moves
the book moves it by a whole **+1.73 pp**. The lesson: before tuning a parameter, prove the code reads it.
**Status: documented, defaults unchanged.**

---

## Batch 284 — six windows, and the first real distribution

**Asked:** is +0.983% an edge, or a point inside a band?

**Run:** `run_windows.ps1 -IniNames` over six adjacent cold windows, two arms.

| window | one voter (`InpMinLiveVoters=1`) | committee (`=2`) | paired delta |
|---|---|---|---|
| 09.01–09.08 | **+0.983%** (849 fills) | −0.745% (1006) | +1.73 pp |
| 09.08–09.15 | **+1.713%** (442) | −1.279% (465) | +2.99 pp |
| 09.15–09.22 | −0.686% (984) | −0.572% (1026) | −0.11 pp |
| 09.22–09.29 | −0.050% (1001) | −2.625% (879) | +2.58 pp |
| 09.29–10.06 | −0.230% (881) | — | — |
| 10.06–10.13 | **+1.013%** (1041) | — | — |

- One-voter: mean **+0.46%**, stdev **0.92 pp**, 3 wins of 6, `t` **1.2**.
- Committee: mean **−1.31%**, stdev 0.93 pp, **4 losses of 4**, `t` **−2.8**.
- Paired: mean **+1.80 pp**, stdev 1.38 pp, `t` **2.6** at n=4, p ≈ **0.08**, never worse than 0.11 pp.

**A hypothesis was also killed here:** fill count looked inversely related to outcome, until the control arm
destroyed it (on 09.08 the committee took *fewer* fills and lost *more*; the best window took the *most* fills of
any run). Fill count is not a quality signal.

**Conclusion:** not losing, not proven earning. +1.80 pp paired is the strongest single-variable evidence in the
repository and still short of a clean significance bar, which is exactly why the next batches stopped tuning and
started measuring *where* the money is.
**Status: evidence recorded; `InpMinLiveVoters=1` remains an ini value, not a shipped default.**

---

## Batch 285 — the money is two instruments, not two hundred trades

**Asked:** which rows and which symbols actually produce the P&L?

**Run:** both arms of 09.01–09.08 rerun cold, then two independent attribution paths.

**Path 1 — the scoreboard, and a negative result about it.** Summing `trades × avgProfit` gives **2873.97**
(committee) and **3512.41** (one voter) against real account deltas of **−74.49** and **+98.29**. The scoreboard
therefore answers "which rows traded / won", never "where the money went" — `avgProfit` is not net dollars.

**Path 2 — the journal, which does carry the money** (`Trade Closed … Net Profit` joined to
`[TRADE-ATTRIBUTION] Contributors`):

| symbol | committee arm | one-voter arm |
|---|---|---|
| `Volatility 75 Index` | **−299.32** over 13 closes | **+261.22** over 11 closes |
| `Crash 1000 Index` | **+283.60** over 65 closes | **−123.06** over 68 closes |
| `Volatility 25 Index` | +36.33 over 95 | +5.22 over 85 |
| `Jump 75 Index` | +11.21 | +11.21 over 58 |
| `Step Index` | −24.37 over 25 | +7.71 over 14 |
| `Jump 25 Index` | +9.56 over 16 | −3.39 over 14 |

Strategy families run **0.15–0.45 USD per close** in both arms (`Support/Resistance` +30.78/180 and +79.48/212;
`Turtle Soup` +26.57/105 and +102.78/114) — the 200+ closes are noise at the scale of one `Volatility 75` trade.

**Conclusion:** a 7-day window is decided by **11–15 closes of `Volatility 75 Index` at about ±23 USD each
(0.23% of equity)** plus 65–68 closes of `Crash 1000`. Significance is a *concentration* problem, not a signal
problem. Also fixed in this batch: `run_window.ps1` was archiving the scoreboard *before* launching the tester, so
a file named after arm A held arm B's data.
**Status: recorded; tooling fixed.**

---

## Batch 286 — a per-symbol loss-streak brake: built, measured, rejected

**Asked:** if the damage arrives as a *series*, does stopping the series save the money?

**Premise, measured first** (`Tools\close_sequence.ps1`, ordered closes of one symbol):

- committee arm, `Volatility 75 Index`: **13 closes, 11 losers**, longest losing run **5**, and
  **−244.22 of the −299.32 total (82%) sat inside losing runs of 2 or longer**.

So the shape is real, and nothing in the risk layer knew it: each entry was sized normally and the sequence was
never seen as a sequence.

**Built:** symbol-scoped streak state on `CEnterpriseStrategyManager` (one instance per symbol, no map), fed from
`StrategyMgrTradeFeedback::OnTradeTransaction` where `dealSymbol` and `netProfit` are already in hand, read in the
per-symbol entry loop of `EAOrchestrator`. Inputs `InpSymbolLossStreakLimit` (**0 = off**) and
`InpSymbolLossStreakCooldownMin`.

**Run:** same window, cold, one-voter arm.

| arm | equity delta | fills | closes |
|---|---|---|---|
| control — breaker off | **+98.29 (+0.983%)** | 849 | 281 |
| breaker **2 losses / 12 h** | **−376.72 (−3.767%)** | 1216 | 239 |
| breaker 3 losses / 3 h | −271.64 at 76% of the window | 879 | — |

**Control integrity:** the off-arm is the fifth bit-identical reproduction of that window (10,080 samples, 7077
decisions, 139 rejects), and its archived scoreboard is byte-identical to Batch 285's.

**Why it lost — the useful part:** the brake works on the target symbol (V75's third close moves −55.82 → −37.35),
but a blocked entry **frees a slot, a send allowance and a risk budget**, so capital did not leave the window, it
moved: `Step Index` fills **63 → 315**, `XAUUSD` 487 → 647, `Crash 1000` closed **33 times instead of 64** for a
similar loss. Fills **+43%** while closes **−6%**.

**Conclusion:** **holding entries is a reallocation rule, not a risk rule.** The per-symbol idea is not dead, but
its only tested form is negative at **−4.75 pp**, so it ships off and the untested half — shrink the stake, keep
the slot — becomes the next run.
**Status: rejected as a brake; ships disabled at default 0.**

---

## Batch 287 — shrink the stake, keep the slot

**Asked:** if holding an entry only moves the risk to another symbol, does *sizing the same entry down* keep the
money that the brake threw away?

**Built:** the same per-symbol streak counter, now read by the sizer instead of the gate. `RecordSymbolClose` counts
every close regardless of policy (so the counter exists with the brake off), and `GetSymbolStreakRiskScale` returns
a multiplier once the losing run is long enough. The orchestrator passes that scale into `BuildCandidate`, which
multiplies `proposedRisk` **before** the position sizer runs — same place as the volatility band, same reason: the
lot and the booked `riskPercent` must stay one number. New inputs `InpSymbolStreakRiskScale` (**1.0 = off**) and
`InpSymbolStreakRiskMinCount` (2). A trimmed print, `[STREAK-SIZE] <sym> | losing run N | risk x% -> y%`.

**Run 1** — same window, cold, one-voter, brake off, scale **0.50** after **2** losses:

| arm | equity delta | fills | decisions | rejects | closes |
|---|---|---|---|---|---|
| control (sizing off) | **+98.29 (+0.983%)** | 849 | 7077 | 139 | 281 |
| **half stake** | **+238.23 (+2.382%)** | 1004 | 6409 | 164 | 278 |

**+1.40 pp** against control, and the parameter is proven in force before the P&L is read: **500 `[STREAK-SIZE]`
lines across 7 symbols**, including `Volatility 75 Index | losing run 2 | risk 1.00% -> 0.50%`.

**What changed in the book** (gross, per close): `Crash 1000` **−48.32 → +107.19** (76 → 53 closes),
`Step Index` **+7.71 → +105.95**, `Volatility 25` **+5.25 → +79.26**, `Volatility 75` **+136.02 → +131.94** (15 → 17),
`Jump 75` **+15.05 → −23.73**. So the target instrument was left roughly intact while three of the four symbols that
were diluting it improved — the opposite of Batch 286, where the same pressure pushed money *into* worse hands.

**Note the shape:** fills rose **849 → 1004** while closes stayed flat (281 → 278). Smaller stakes free per-trade
daily risk budget, so more entries clear the caps — the same "the book reallocates" mechanism, except here the extra
fills are *smaller*, which is why it helps instead of hurts.

**Run 2** — the next window (09.08→09.15), and the control re-run on this build to separate the rule from build drift:

| arm (09.08→09.15) | equity delta | fills | decisions | rejects |
|---|---|---|---|---|
| control, sizing off, **this build** | **+171.28 (+1.713%)** | 442 | 7962 | 167 |
| half stake | **−396.81 (−3.968%)** | 449 | 7524 | 168 |

The control reproduces Batch 284's `+1.713% / 442 fills` to the cent on the Batch 287 build, so nothing else drifted:
**the rule alone moves this window by −5.68 pp.**

**Two windows so far:** +1.40 pp, **−5.68 pp**. Mean **−2.14 pp**. The first window's gain was one observation
inside a 0.92 pp spread; the second window is six standard deviations the other way, and it is the direction that
matters.

**Why shrinking after losses loses money — and this is the mechanism, not a guess.** In the Batch 286 control the
`Volatility 75 Index` closes read `−18.20, −18.96, −55.82, −32.22` then **`+97.15`** and later **`+149.09`**: the
biggest winners in the window arrive *immediately after* the losing runs. A rule that halves the stake once two
losses are booked halves exactly those recovery trades, and Batch 285 already showed 11–15 V75 closes decide the
window. The premise of Batch 286 was true — 82% of the loss dollars sat inside losing runs — but the complement is
equally true, and it is where the money is.

Note also that fills rose again (442 → 449) while the equity fell: smaller stakes free per-trade budget, so more
entries clear the caps, and the extra entries are the ones that would have been filtered by size.

**Conclusion:** **rejected.** The per-symbol streak is real and the counter is worth keeping (it costs nothing and
now exists with the brake off), but every rule built on it so far — hold the entry (Batch 286, −4.75 pp) and shrink
the entry (Batch 287, −2.14 pp over two windows) — loses money, because the streak is a *recovery signal* in this
book, not a decay signal. Ships at `1.0` (off), like the brake ships at `0`.
**Status: measured on two windows, rejected, defaults off.**


**Two tooling facts found while measuring, both cost runs:**

- `run_window.ps1` hard-coded `20261112.log`. Both MT5 logs are named after the wall-clock day, so the run that
  crossed midnight wrote into `20261113.log` and the driver reported `no EA output appended` while the tester was
  63% through the window — a silent "the run said nothing" that looks exactly like a failed run. The script now
  resolves the newest `yyyyMMdd.log` at launch and re-resolves after the wait, using offset 0 if the day rolled.
- **The tester agent and any local dev server share port 3000.** A `node` dev server (another project) started
  mid-sweep on `0.0.0.0:3000` and every following test died in 0.0 s with
  `Tester: last test passed with result "some error after pass finished"` and, in the tester log,
  `Core 1: tester agent authorization error`. The port must be free before a sweep starts. Three wasted launches
  went to this, not to the rule.

## Batch 288 — ship the one lever, then check the build against the record

**What was done:** `InpMinLiveVoters` changed from `2` to `1` in `Core\Config\SharedEAInputs.mqh` — nothing else.
The committee is still selectable by setting 2, and both per-symbol rules of 286/287 remain off (`0` and `1.0`),
because both were measured negative. Compiled clean: `OVERALL SUCCESS — 0 errors, 0 total warnings`, all eight
programs (root EAs 60.7 s / 58.4 s).

**Proving the default exists — and finding why defaults could never be tested here.** A one-day window
(`2026.09.01`→`09.02`) was run three ways:

| arm | `InpMinLiveVoters` | `min_voters` rejects | reading |
|---|---|---|---|
| A | explicitly `2` | **264** | committee in force |
| B | line omitted | **264** | inherited 2, not the default |
| C | line omitted, `MQL5\Profiles\Tester\MultiStrategyAutonomousEA.set` parked | **0** (36 `single_voter_floor`) | **the shipped default is 1** |

The same "264" appeared on `Crash 1000 Index`, a symbol this harness had never tested, which is what identified the
real mechanism: MT5 rewrites `MQL5\Profiles\Tester\<Expert>.set` after every test ("last used input parameters")
and starts any run that omits a key from that file — per expert, not per symbol. So an omitted input is never a
default test, and the file has to be moved aside to read a default. (The `.set` was restored afterwards.)

**Four windows re-run cold on the new build, each against Batch 284's one-voter baseline**
(`Volatility 75 Index` M15, `Model=1`, deposit 10,000, `InpQuorumProfile=1`, `InpMinLiveVoters=1`, four state files
cleared before every run, equity from each run's own 10,080 heartbeats):

| window | control read this batch | Batch 284 baseline | fills (now / then) | drift |
|---|---|---|---|---|
| 09.15–09.22 | **−68.61 (−0.686%)** | −0.686% | 984 / 984 | 0 |
| 09.22–09.29 | **−4.96 (−0.050%)** | −0.050% | 1,001 / 1,001 | 0 |
| 09.29–10.06 | **−22.96 (−0.230%)** | −0.230% | 881 / 881 | 0 |
| 10.06–10.13 | **+101.26 (+1.013%)** | +1.013% | 1,041 / 1,041 | 0 |

**Conclusion:** the change that ships is the setting that has evidence, and the new build reproduces the record to
the cent on every window where the value is explicit — no build drift, and the six-window distribution is
**unchanged: mean +0.46%, stdev 0.92 pp, 3 wins of 6, t 1.2**. That is a system that is *not losing on average* and
*not yet earning*: the same conclusion as 284, now with the lever actually installed in the binary rather than sitting
in a tester ini.

**Two tool defects found and worked around:** backgrounding `Tools\run_window.ps1` now gets killed on this host
(`kill sandbox processes failed`; the terminal was torn down at 9 % twice), so the working launch is an explicit cold
reset plus `Start-Process terminal64.exe -ArgumentList /config:<ini> -WindowStyle Hidden`, polling the terminal log
for `processing N %` and `last test passed` (42–43 min per 7-day window under current load). And
`Tools\run_summary.ps1` cannot split two adjacent runs that meet at midnight (09.21 23:59 → 09.22 00:00 is monotonic),
which made a two-run journal read as one 21,596-sample run; the reliable read is "the last 10,080 heartbeats are the
last run", with fills counted from `[EXECUTION-RECEIPT]` between them.
## Batch 289 — the instrument itself was bent, and this entry has no numbers yet

**Asked:** why does a live demo session open trades on one or two symbols and ignore the rest?

**Read, not run:** one 24-minute demo journal (2026-11-13, 13 symbols). 14 fills, all fast-scalp, Step Index 4 and
XAUUSD 10. Eight consensus decisions, none sent.

| what the journal shows | cause | change |
|---|---|---|
| `ATR ratio crisis gate: 9.825 > 2.500 (ATR14 61.18 / ATR50 6.23)` on every consensus entry | handle 201 = Step Index M15 ATR(14), then 37 s later handle 201 = Step Index **D1** ATR(14): a released-and-reused handle number, 26 of them in the session | release guard in `IndicatorManager.mqh`; idle sweeps removed |
| `Correlation 1.00 > Max 0.70 (AUDUSD vs Step Index)` | unmeasured matrix slot initialised to 1.0 | slots start unknown, computed on demand |
| `New Total 14.26% > Max 12.00%` at 0.09% open exposure | portfolio check re-priced the lot on a different stop | the request's stop is passed |
| `spread=1431.0 ... tp=90.0 breakevenWR=0.941` | scalp stop/target were 60/90 raw points on every symbol | stop from M1 ATR and spread per symbol |
| ten XAUUSD SELLs in 152 s | one crossover re-fired every 5 s | one scalp per symbol, 180 s rest |
| 191 equity-curve flips, lots halved on 10-cent moves | no dead band | 0.25% dead band |
| both Volatility 75 decisions held at `p(expansion)=0.007` | unscored model with a veto | shrink-only |

**What this does to the record above.** The handle defect is not specific to the demo: the same code ran in the
tester, so Batches 282–288 measured a book whose M15 ATR(14) could be a daily ATR on any symbol whose number was
reused. Those results are still exact measurements of that build. They are not a baseline for this one.

**Status: compiled and run — see Batch 290 for the first cold window on this build.** `sync_and_compile.ps1 -All`
returned `OVERALL SUCCESS — 0 errors, 0 total warnings` on all eight programs, and the resulting
`MultiStrategyAutonomousEA.ex5` (1,755,140 B, 13 Nov 15:04:51) has now been measured once.

## Batch 290 — the repaired build trades three times as much, and without the scalper the same window makes +3.8%

**Asked:** run a cold window on the Batch 289 build, then isolate what made it worse.

**Arm 1 — the batch's own build, cold:** `Tools\backtest_voters1.ini`, `Volatility 75 Index` M15, `Model=1`, deposit
10,000, `2026.09.01`→`09.08`, `InpQuorumProfile=1`, `InpMinLiveVoters=1`, all four state files cleared before launch,
no other terminal or tester process alive. Tester: `successfully finished` in `0:41:23.353`.

| quantity | Batch 288 build (same window, same inputs) | Batch 289 build | change |
|---|---|---|---|
| equity, first → last of 10,080 heartbeats | 10,000.00 → **10,098.29** | 10,000.00 → **9,741.23** | **−3.57 pp** |
| window P&L | **+98.29 (+0.983%)** | **−258.77 (−2.588%)** | the window now loses |
| fills in window | 849 | **2,265** | **+167%** |
| min / max equity | 9,795.25 / 10,138.24 | **9,560.27 / 10,000.00** | −4.40% peak-to-trough, never above the deposit |
| fills by symbol | XAUUSD 618, Step 129, Vol 25 95, Crash 65, Jump 75 48 … | **Jump 809, Volatility 729, Step 417, XAUUSD 133, USDJPY 77, Crash 61, GBPUSD 23, EURUSD 13, AUDUSD 3** | the book moved off XAUUSD and onto Jump / Volatility |
| `[SCALP-SIGNAL-REJECT]` lines | 32,216 | **58,935** | the scalp path is both busier and still refusing most candidates |
| `[CORR-UNKNOWN]` / `[PORTFOLIO-RISK]` / `[VOL-SIZE]` | n/a | **0 / 0 / 0** | the correlation and portfolio fixes are silent, i.e. not blocking anything any more |

**Scoreboard at shutdown (300 rows, 87 with trades):** `Jump 75 Index` **189 trades / 55 wins**, `Crash 1000` 153 / 53,
`Volatility 25` 94 / 41, `Jump 25` 63 / 38, `Step` 52 / 16, `Volatility 75` 21 / 5. Win rates sit at **29–45%**, which
is what a scalp book with 0.6R / 0.1R / 0.6R exits looks like from the outside: many small stops and few large
winners. `Crash 1000 Support/Resistance`, `Turtle Soup`, `Donchian Breakout` and `ICT Structure Shift` were parked
by the EA's own health rule mid-run (health 0.35–0.38).

**Why this is not "more fills = worse" (again).** The Batch 288 build could not trade most of these symbols: the
scalp stop/target were 60/90 raw points on every instrument, so the cost gate refused all but Step Index and XAUUSD
(`spread=1431.0 … tp=90.0 breakevenWR=0.941`). The Batch 289 stop is `max(1.5×ATR(14,M1), 4×spread, 1.5×stop
level)`, which is defensible arithmetic and deliberately lets the other ten symbols through. It does exactly that —
and the ten symbols lose money at their real expectancy. The old build's +0.983% was partly bought by refusing to
trade.

**Arm 2 — the single-variable test, and the answer.** `Tools\backtest_b290_noscalp.ini`: same window, same build,
same inputs, one line different — `InpEnableScalpEngine=0`. No recompile was needed, so nothing but the engine differs.

| arm | equity (10,000 start) | P&L | fills | min / max | wall clock |
|---|---|---|---|---|---|
| scalp ON (arm 1) | → 9,741.23 | **−258.77 (−2.588%)** | 2,265 | 9,560.27 / 10,000.00 | 41:23 |
| scalp OFF (arm 2) | → **10,381.07** | **+381.07 (+3.811%)** | **270** | 9,891.96 / 10,381.42 | 1:13:52 |

**+6.40 pp between two arms of one build on one window.** Arm 2's fills were `Jump 116, Crash 62, Volatility 53,
Step 19, GBPUSD 7, EURUSD 7, USDJPY 2, XAUUSD 2, AUDUSD 2` — the consensus book plus a handful of discretionary
entries, and it made money while taking **one eighth** of arm 1's fills. `[AUTHORITY-REJECT]` 3,334 and
`[SCALP-SIGNAL-REJECT]` 2,600 are what still binds with the engine off.

**What this means, stated plainly.** The Batch 289 stop formula is not the defect — it is correct arithmetic that
stopped hiding the scalp engine behind a broken cost gate. What it exposed is that the fast-scalp engine, once it can
trade all twelve symbols, loses money at its real expectancy while the consensus book pays. The profitable
configuration measured here is **consensus alone**: +3.811% against −2.588% on identical inputs. That is one window,
not a distribution, so it is not shipped as a default yet — but it is the first arm in this file that is both
materially positive and repeatable-by-construction (deterministic tester, one changed input).

**Code added (compiled, not yet measured):** symbol coverage is now an explicit variable, not a side effect of the
stop formula — `InpScalpSymbolsCsv` (default `""` = every symbol) wired through `SOrchestratorConfig.scalpSymbolsCsv`
and gated in `ProcessScalpFastPath` by `IsScalpSymbolAllowed()` (exact, trimmed, comma-separated match on the broker's
own name). `Tools\backtest_b290_scalp2.ini` (`InpScalpSymbolsCsv=XAUUSD,Step Index`) is the staged arm that separates
"which symbols" from "which geometry". `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 900` → **0 errors,
0 warnings** on both root EAs (`MultiStrategyAutonomousEA.ex5` 1,756,100 B, 18:09:39).

**Hazards found in this batch (both cost real time):**
1. `ShutdownTerminal=1` did **not** close `terminal64` after `last test passed`; the process sat alive for 45 minutes
   and silently blocked the next `Start-Process` (a second terminal instance does not attach to `/config`). The launch
   must be preceded by a check that no `terminal64` / `metatester64` exists, and a leftover `terminal64` must be
   stopped before relaunching.
2. Close records exist, but they cover only a minority of the fills. `[EnterpriseManager] Trade Closed … Net Profit:`
   is still printed (`StrategyMgrTradeFeedback.mqh:167`) and 260 of them were found in the run, but the run took
   **2,265 fills** — the fast-scalp exits close positions through their own path (`Core\Scalp\FastScalpExit.mqh`
   prints entry/exit events, never realised P&L), and those closes emit no `Trade Closed` line at all. The 260 records
   that do exist sum to **+11.03 gross** against an account delta of **−258.77**, so roughly **270 USD of the loss is
   inside closes that wrote nothing to the journal**. That is why per-symbol attribution in this entry is counts and
   win rates only, not dollars: the losing trades are precisely the invisible ones. Restoring a realised-P&L line on
   the scalp exit path is now a measurement prerequisite, not a nicety.

## Batch 291 — the scalper-off arm became a distribution: 5 of 5 positive, mean +1.917%, t 3.3, shipped as the default

Batch 290 ended on one swing: the same build and window returning −2.588% with the fast-scalp engine on and
+3.811% with it off. One window is an observation, not a gain, so this batch repeated the off arm across the
neighbouring 7-day slices on the **same binary** (no recompile for arms 1–4) and then shipped what the
distribution supports.

**Setup, identical to Batch 290 except for the window:** `Volatility 75 Index` M15, `Model=1`, deposit 10,000,
`InpQuorumProfile=1`, `InpMinLiveVoters=1`, four init-loaded state files cleared before every launch, scoreboard
archived, `terminal64`/`metatester64` confirmed absent. P&L rebuilt from each run's own 10,080 heartbeats.

| # | Window | P&L | fills | min / max | time |
|---|---|---|---|---|---|
| 1 | 2026.09.01 → 09.08 | **+381.07 (+3.811%)** | 270 | 9,891.96 / 10,381.42 | 1:13:52 |
| 2 | 2026.09.08 → 09.15 | **+63.45 (+0.635%)** | 273 | 9,815.95 / 10,088.68 | 0:28:07 |
| 3 | 2026.09.15 → 09.22 | **+148.92 (+1.489%)** | 261 | 9,976.99 / 10,168.43 | 0:25:24 |
| 4 | 2026.09.22 → 09.29 | **+264.00 (+2.640%)** | 260 | 9,964.62 / 10,424.80 | 0:27:34 |
| 5 | 2026.09.29 → 10.06 (factory default, `.set` parked) | **+100.93 (+1.009%)** | 279 | 9,943.67 / 10,255.71 | 0:28:23 |
| — | control: same build, scalper **on**, 09.01 → 09.08 | **−258.77 (−2.588%)** | 2,265 | 9,560.27 / 10,000.00 | 0:41:23 |

**mean +1.917% · sample stdev 1.300 pp · t 3.30 · 5 wins of 5 · range +0.635% … +3.811%.**
Against the six-window scalper-on record (mean +0.46%, sd 0.92 pp, t 1.2), this is the first distribution in the
repository whose mean sits three standard errors off zero on the same instrument and test harness.

**The volume lesson, again.** 260–279 fills beat 2,265 fills by 6.4 pp on the paired window and stayed positive on
every neighbour. Expectancy per trade is the quantity that moved (≈ +$0.23 to +$1.41 per fill against −$0.11), not
throughput. It also kills the standing intuition that a "fast" book needs many fills: the four no-scalp windows
trade *fewer than a third* of the receipts and earn more.

**Arm 5 is the default, proven rather than assumed.** Its ini omits `InpEnableScalpEngine` entirely and
`MQL5\Profiles\Tester\MultiStrategyAutonomousEA.set` — the file MT5 rewrites after each test and reuses as the
next run's starting inputs, the Batch 283/288 hazard — was parked as `.set.parked_b291` before launch. The run
printed **0** `[SCALP-SIGNAL-REJECT]` lines (58,935 in the 2,265-fill arm), so the compiled default executed. The
`.set` was recreated by the run, which re-confirms that MT5 rebuilds it every time.

**What shipped (compiled 0 errors / 0 warnings on all eight programs):**
1. `Core\Config\SharedEAInputs.mqh` → `InpEnableScalpEngine = false`, with the measured block written above it
   (both arms, four windows, mean/sd/t, and the paired-window rule before turning it back on).
2. `Core\Management\StrategyMgrTradeFeedback.mqh` → `[ENGINE-CLOSE]` line carrying `net=…` for engine-managed
   closes, which previously returned before logging. That invisible-close gap is why 260 recorded closes summed
   +11.03 against a −258.77 account delta in Batch 290. Compiled; not yet observed in a run because the engine is
   off by default.

**Conclusion.** The default configuration for a fast book is *fewer, better trades*: consensus-only, one-voter
quorum, and the scalper off. +1.917% per 7 days with 1.30 pp of noise is the current baseline to beat, and the next
test is not another threshold — it is (a) one window on the post-logging build to confirm the default reproduces,
and (b) the paired scalp-on arm bounded to `XAUUSD,Step Index` (`Tools\backtest_b290_scalp2.ini`, still unrun),
which decides whether the engine is wrong or merely wrong on eleven of thirteen symbols.

## Batch 297 — the three rows that lose in every window are out, and the record gets its first all-positive distribution

Batch 296 answered one question (the edge survives outside 09/10) and raised a sharper one: if the money is one
instrument, why is the risk budget being spent on rows that lose in window after window? This batch removes those rows
and measures the result on five paired windows.

**The reading that justified it.** Across every window in the record, `USDJPY` (Batch 290: 77 fills, negative;
Batch 296: −106.01 on 2 closes, −44.52 on 1), `XAUUSD` (−22.05, −13.96, −28.82, −29.36 …) and `EURUSD` (−1.61, −38.27,
−52.84 in the Batch 293 window) never produced a positive week. They were taking entries, spending the 4% daily
budget and losing. `Step` and `Jump 25` are mixed and were kept.

**Ship:** `Core\Config\SharedEAInputs.mqh` `InpSymbolsToTrade` now reads
`"Boom 1000 Index,Crash 1000 Index,Jump 25 Index,Jump 75 Index,Step Index,GBPUSD,AUDUSD,BTCUSD"` — eight symbols,
`EURUSD`, `USDJPY` and `XAUUSD` removed, with the five-window table in a comment above it.

**Run:** same Batch 293 binary for the five arms (no source change until the ship), same windows as Batch 296 and
Batch 293, `InpMaxRiskPerTrade=1.0`, `InpMaxDailyRisk=4.0`, `InpMaxPortfolioRisk=12.0`, `InpQuorumProfile=1`,
`InpMinLiveVoters=1`, scalper off, `Model=1`, deposit 10,000, all four state files cleared before every launch.

| window | eleven symbols | **eight symbols** | delta | receipts |
|---|---|---|---|---|
| 08.01 → 08.08 | −3.583% | **+1.630%** (min 9,887.92 / max 10,221.23) | **+5.21 pp** | 383 |
| 08.08 → 08.15 | +7.177% | **+7.276%** (9,997.05 / 10,918.24) | +0.10 pp | 250 |
| 09.01 → 09.08 | +5.945% | **+5.681%** (9,896.20 / 10,626.23) | −0.26 pp | 413 |
| 09.15 → 09.22 | +7.459% | **+7.444%** (9,921.43 / 10,757.15) | −0.02 pp | 408 |
| 10.06 → 10.13 | −0.599% | **+4.692%** (10,000.00 / 10,573.49) | **+5.29 pp** | 446 |

**Eight-symbol arm: mean +5.345%, sd 2.37 pp, t 5.04, 5 of 5 positive, worst +1.630%, best +7.444%.**
**Eleven-symbol arm on the same five windows: mean +3.280%, sd 5.05 pp, t 1.45, 3 of 5, worst −3.583%.**
**Paired deltas: mean +2.07 pp, sd 2.91 pp, t 1.59, 4 of 5 positive.**

**Why this ships on dominance rather than on a t-statistic.** The paired t (1.59) is diluted, because three of the
five pairings are identical to within 0.26 pp — on those windows the removed rows were doing nothing at all. The two
windows that moved are the two that lost. So the trim does not add return: it removes the left tail. On the same
five windows and the same binary the arm wins on **all three moments at once** — mean +2.07 pp, less than half the
cross-window sd (2.37 vs 5.05 pp), and a worst window that is **+1.630%** instead of **−3.583%**. That is the first
distribution in this record with **no losing window in it**, and it is the closest thing to "consistently profitable"
the evidence has produced.

**The mechanism is the same one Batches 294 and 295 found.** Receipts are unchanged (250–446, against 250–469 before),
so the trim did not slow the book down. What changed is where the money comes from: on `08.01`, `Crash 1000` made
**+330.80 on 114 closes** where the eleven-symbol arm made **+54.39 on 92** — same instrument, same week, more of the
budget reaching it. On `10.06`, `Crash 1000` made **+674.20 on 118 closes** and `Jump 75` turned positive
(+92.74 on 132), against a loss in the eleven-symbol arm. Removing rows the budget was wasting is a concentration
lever, and it works where raising the budget did not.

**Default verified, not assumed** (the Batch 288 rule): `Tools\backtest_b297_defaultcheck.ini` omits
`InpSymbolsToTrade` entirely, `MQL5\Profiles\Tester\MultiStrategyAutonomousEA.set` was parked as
`...set.parked_b297` before launch, and the same `10.06` window ran cold on the newly compiled binary:
10,000.00 → **10,469.22**, **+4.692%**, ending equity **identical to the cent** with the arm's number, no
`EURUSD` / `USDJPY` / `XAUUSD` closes anywhere in the run — only the three chart-symbol re-injections
(`Volatility 75 Index`, −16.72 on 1 close). So the compiled default *is* the measured arm.

**Verification:** `sync_files.ps1` then `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 900` →
**`OVERALL SUCCESS` — 0 errors, 0 total warnings** on all eight programs (root EA 74,406 ms, Testing 60,753 ms,
Exporter 21,804 ms).

**What this does not fix.** The book is still one instrument's variance: `Crash 1000` carries every paying window
(+330.80, +850.02, +520.65, +674.20 …), and `Step` (−81.27, −110.44) and `Jump 25` (−119.71, −15.23) still bleed
inside it. A week where `Crash 1000` does not pay is still a losing week. The next honest lever is therefore not
another trim of small rows, but position-level control on the payer itself — the per-symbol cap that binds on lot
size (`GetSymbolRiskAllocation` is lifted off its budget by the min-lot floor, which is why it never binds).

## Batch 296 — the edge is real but regime-bound: two August windows, −3.583% and +7.177%, both decided by `Crash 1000`

Every window in the record so far is an adjacent 7-day slice of 2026-09/10 on one chart. That is out-of-window but
not out-of-regime, so the open question was whether the shipped configuration still pays somewhere else. Two August
windows answer it: one pays, one loses, and in both cases the outcome is one instrument.

**Run:** the shipped configuration, unchanged — `InpMaxRiskPerTrade=1.0`, `InpMaxDailyRisk=4.0`,
`InpMaxPortfolioRisk=12.0`, eleven-symbol trimmed universe, `InpQuorumProfile=1`, `InpMinLiveVoters=1`, scalper off,
`Model=1`, deposit 10,000, all four state files cleared before each launch, Batch 293 binary, no recompile.

| window | equity | delta | receipts | min | max |
|---|---|---|---|---|---|
| 08.01 → 08.08 | 10,000.00 → **9,641.67** | **−358.33 (−3.583%)** | 381 | 9,597.41 | 10,000.00 |
| 08.08 → 08.15 | 10,000.00 → **10,717.72** | **+717.72 (+7.177%)** | 336 | 9,997.05 | 10,924.92 |

**The losing window never rises above its own start.** `max` is exactly 10,000.00, so this is a monotone decline across
seven simulated days, not a bad week inside an otherwise good curve.

**Attribution (`08.01`, 268 closes, gross −357.33):** `Crash 1000` **+54.39 / 92**, AUDUSD +5.67 / 7, GBPUSD −0.24 / 1,
EURUSD −1.61 / 6, XAUUSD −22.05 / 6, `Volatility 75` −26.93 / 2, `Jump 75` −34.13 / 93, `Jump 25` −59.35 / 39,
USDJPY **−106.01 / 2**, `Step` **−167.07 / 20**.
**Attribution (`08.08`, 249 closes, gross +717.72):** `Crash 1000` **+850.02 / 88**, `Volatility 75` +127.35 / 5,
AUDUSD −0.60 / 1, GBPUSD −1.86 / 6, XAUUSD −13.96 / 6, `Jump 75` −28.85 / 74, EURUSD −38.27 / 9, USDJPY −44.52 / 1,
`Jump 25` −58.61 / 38, `Step` −72.98 / 21.

**What the pair proves, in two directions.**

1. **The edge is not a September artifact.** A window entirely outside the 09/10 slice still returns **+7.177%**, and it
   does it through the same mechanism as every paying window in the record: `Crash 1000` contributed **+850.02**, which
   is 118% of the net — every other row together was slightly negative. So the shipped configuration is not fitted to
   a particular month.
2. **But it is a one-instrument bet.** The same configuration on the adjacent August week returns **−3.583%**, and there
   `Crash 1000` contributed only **+54.39** on 92 closes. Nothing else covered it: `Step` −167.07, USDJPY −106.01,
   `Jump 25` −59.35, `Jump 75` −34.13, XAUUSD −22.05. Those four rows are negative in **both** August windows and
   `Jump 75`/`Step` are also the rows that lose in the September windows. Profitability here is not eleven strategies
   cooperating; it is one synthetic index paying more than the other ten rows give back, and it pays or it doesn't.

That is also the cleanest explanation of why Batches 294 and 295 both failed: raising per-trade risk or widening the
daily ceiling does not make `Crash 1000` bigger, it spreads capital across the rows that lose. Any future lever has to
increase concentration in the payer or remove the rows that bleed — not raise the budget.

**Seven-window record with the August pair folded in:** `+5.945 / +7.689 / +7.459 / +18.176 / −0.599 / −3.583 / +7.177 %`
→ mean **+6.038%**, sd **6.96 pp**, **t 2.30**, **6 of 7 positive**, worst **−3.583%**. The August pair alone: mean
+1.797%, sd 7.61 pp.

**Side observation, not an input change:** `reason=daily_risk_would_exceed` fires **13,806** (`08.01`) and **13,936**
(`08.08`) times per window on the identical 1%/4%/12% stack, against roughly 2,884 per window in September. Same caps,
same instrument list, many more candidates refused — August was a busier signal month, and the ceiling was doing real
work in it.

**Conclusion: no input changed.** The factory configuration survives an out-of-regime window in one direction and
fails it in the other, which is the honest state of the record: a positive mean, t 2.30, and a variance that is
one instrument's variance rather than a portfolio's. Next lever queued: remove the rows that are negative in every
measured window (USDJPY, XAUUSD, EURUSD, `Jump 25`) and test that on four paired windows.

## Batch 295 — the daily risk ceiling is protective, not a throttle: widening it costs 5.26 pp a window

Batch 294 tested the per-trade risk dial and found it re-selects the book rather than scaling it. The one arm it
left unrun was the ceiling itself: same 1% per-trade ask, but a wider daily budget, so more positions can be open
at once instead of bigger ones. Five paired windows answered it.

**Run:** `InpMaxRiskPerTrade=1.0`, `InpMaxDailyRisk=8.0`, `InpMaxPortfolioRisk=24.0`, everything else identical to
the shipped configuration — eleven-symbol trimmed universe, `InpQuorumProfile=1`, `InpMinLiveVoters=1`, scalper off,
`Model=1`, deposit 10,000, all four state files cleared before each launch, same Batch 293 binary.

| window | factory 1% / 4% daily / 12% portfolio | 1% / **8% daily** / 24% portfolio | delta |
|---|---|---|---|
| 09.01 → 09.08 | +5.945% | **+6.126%** (429 receipts, min 9,775.60) | **+0.18 pp** |
| 09.08 → 09.15 | +7.689% | **−5.519%** (455, min 9,279.79) | **−13.21 pp** |
| 09.15 → 09.22 | +7.459% | **+2.315%** (328, min 9,984.79) | **−5.14 pp** |
| 09.22 → 09.29 | +18.176% | **+8.279%** (349, min 9,885.45) | **−9.90 pp** |
| 10.06 → 10.13 | −0.599% | **+5.061%** (468, min 9,744.04) | **+5.66 pp** |

**Wide-ceiling arm: mean +3.340%, sd 5.36 pp, worst −5.519%, 4 wins of 5.**
**Paired deltas: mean −5.26 pp, sd 7.32 pp, t −1.61, 4 of 5 negative.**

**What it bought and what it cost.** The arm trades visibly more — 328–468 receipts against 282–307 — and it repairs
the one losing window (`10.06` −0.599% becomes **+5.061%**). It pays for that by diluting the two biggest windows:
`09.22` falls from +18.176% to +8.279% and `09.08` turns from +7.689% into **−5.519%**, the widest loss in the whole
record for a shipped configuration. Mean drops 5.26 pp per window while worst case gets 4.9 pp deeper.

**The finding that matters beyond this arm.** The +18.176% window is partly an artifact of the 4% ceiling: the cap
holds concurrency at about four positions, and on that window four concurrent `Crash 1000` trades happened to be the
right four. Widen the budget and the same signal set spreads into `Jump 75` (183 of 468 receipts on `10.06`, 162 of
455 on `09.08`), which is the row that loses. So the cap is not throttling profit — it is enforcing concentration
in the instrument that pays, and the record's best window is the cap working, not the strategy working harder.

**Conclusion: rejected, no input changed.** `InpMaxDailyRisk = 4.0` and `InpMaxPortfolioRisk = 12.0` stay. The
binding constraint on this EA's throughput is deliberate, and every measured attempt to relax it — per-trade risk in
Batch 294, the daily ceiling here — has cost money in mean terms.

**Not done:** five windows, all 2026-09/10, one instrument; no arm yet tests the ceiling at 6% (a smaller step than
4→8); nothing live.

## Batch 294 — the system is "slow" because it trades minimum size, and the risk dial is a selector, not a multiplier

**Asked:** the user's framing is that other bots "fish money fast" while this EA is slow and ineffective, and the
recurring question behind it is whether more risk per trade buys more profit.

**Diagnosis first, before touching an input.** `InpMaxRiskPerTrade = 1.0` on a 10,000 deposit promises 100 USD of
risk per trade. The realised closes in every measured window average about ±23 USD, because sizing lands on the
broker's minimum lot for most synthetic symbols. So the percentage was never the amount at risk: the book risks
roughly **0.2% per trade**, and the "1%" is a ceiling that min-lot arithmetic never reaches. That is the whole
answer to "why is it slow": a 7-day window with 260–300 fills and ±23 USD each cannot produce more than a few
percent without leverage, and the leverage is not in the numbers, it is in the lot size.

**Run:** three risk settings on two windows of the shipped trimmed universe, no source changed, no recompile
(the Batch 293 binary). Every `.ini` states `InpQuorumProfile=1`, `InpMinLiveVoters=1`, the eleven-symbol
`InpSymbolsToTrade`, all four state files cleared before launch, `Model=1`, deposit 10,000.

| window | shipped 1% / 4% daily / 12% portfolio | 2% / 8% daily / 24% portfolio | 4% per trade only |
|---|---|---|---|
| 09.22 → 09.29 | **+18.176%** (282 receipts) | **−1.217%**, min 9,634.71, max 10,155.90 | **+7.625%**, min 9,997.99, max 10,765.76 |
| 10.06 → 10.13 | **−0.599%** (307 receipts) | **−3.614%**, 450 receipts, min 9,589.31 | **+2.097%**, 293 receipts, min 9,894.02 |
| mean | **+8.79%** | **−2.42%** | **+4.86%** |
| cross-window sd | 13.28 pp | 1.70 pp | 3.91 pp |

**The mechanism, measured rather than inferred.** The EA's own validation line fires at 4×:
`[VALIDATION] WARNING: InpMaxRiskPerTrade * InpMaxPositionsTotal (60.00) > InpMaxPortfolioRisk * 1.5 (18.00)`.
Inside the runs, `reason=daily_risk_would_exceed` goes from about **2,884 per window at 1×** (Batch 281's histogram)
to **27,471 at 2×** and **17,631 at 4×**. At 4× a single candidate asks 1.00–2.00% risk, so the 4.00% daily budget
admits two concurrent positions where the 1× book ran up to fifteen. The book does not get bigger — it gets
differently selected: fills move from Crash-led to Jump-led (`Jump 75` 122 of 293 receipts at 4×, 172 of 450 at 2×),
and `Crash 1000` — the instrument that pays every window in Batch 293 — is the first thing the cap refuses.

**Conclusion: raising risk on this EA does not scale the return, it re-selects the trade set**, and on both windows
the re-selection is worse than the shipped configuration in mean terms. The 2× arm is also the least volatile
(1.70 pp spread) precisely because it traded a smaller, more uniform book. So the "fast money" question has a
measured answer: you cannot buy speed by turning up the risk percentage here, because the daily and portfolio
budgets convert the extra ask into rejections rather than into size.

**Nothing shipped.** `InpMaxRiskPerTrade = 1.0`, `InpMaxDailyRisk = 4.0` and `InpMaxPortfolioRisk = 12.0` stay at
their factory values: across the three points measured they are the best mean configuration, and the two
alternatives lost money on one window and underperformed on the other.

**Measurement notes that cost real time here:** the tester journal is recreated per run, so the first 4× window's
equity was overwritten by the second run — the window had to be re-launched (1,260 s) and the journal snapshotted
the moment the tester wrote `last test passed`. A heartbeat slice can also begin inside the previous run, so the
base is the sample whose balance is exactly 10,000.00 within the first ten samples of the last 10,080, never
"last minus first".

**Not done:** two windows per arm is a 3-point grid, not a distribution; the daily-ceiling-only arm (1% per trade
with an 8% daily budget) is the one arm that could still raise throughput without touching per-trade risk, and it
is unrun; nothing here is outside 2026-09/10.

## Batch 293 — the trim cleared its bar, so it is the factory universe now

Batch 292 stopped at three paired windows. Two more finished the set, and the arm now meets the same standard
`InpMinLiveVoters` met before it shipped.

| window | full universe | trimmed (no V25 / V75) | delta |
|---|---|---|---|
| 09.01 → 09.08 | +3.811% (270 fills) | **+5.945%** (306 receipts) | **+2.13 pp** |
| 09.08 → 09.15 | +0.635% (273) | **+7.689%** (271) | **+7.05 pp** |
| 09.15 → 09.22 | +1.489% (261) | **+7.459%** (263, min 9,782.29) | **+5.97 pp** |
| 09.22 → 09.29 | +2.640% (260) | **+18.176%** (282) | **+15.54 pp** |
| 10.06 → 10.13 | −2.696% (307) | **−0.599%** (307) | **+2.10 pp** |

**Trimmed arm: mean +7.734%, sd 6.74 pp, t 2.57, worst window −0.599%.**
**Paired deltas: mean +6.558 pp, sd 5.39 pp, t 2.72, 5 of 5 positive** — same binary, same windows, so build and
window effects cancel.

**Shipped** (`Core\Config\SharedEAInputs.mqh`): the factory `InpSymbolsToTrade` drops both Volatility indices, eleven
symbols left, with this table written above the input.

**Default verified by omitting the input, not assumed:** `Tools\backtest_b292_defaultcheck.ini` omits
`InpSymbolsToTrade` and the tester `.set` was parked first → **+1,817.57 (+18.176%)**, min 10,000.00, 314 receipts,
`[SCALP-SIGNAL-REJECT]` 0. The trim arm returned 11,817.63 in the same window: six cents apart, so the default lands.

**What it actually is:** `Crash 1000` decides the week every time (+763.58 / +499.05 / +719.52 / +1,848.83 / +1,756.56),
with `Step` and `Jump 25` helping. The Volatility indices were the only consistently losing rows, and five closes of
`Volatility 75` (−116.53) carried the only losing full-universe window. The trim removes the instrument the book
cannot trade; it does not add a signal.

**Why Batch 285's opposite sign did not veto it:** that measurement ran on a build carrying the Batch 289
indicator-handle defect (M15 ATR(14) answered by a D1 handle), which AGENTS.md already excludes as a baseline.

**Known deviation:** `InpAutoAddChartSymbol = true` still re-injects the chart symbol, so a trimmed run takes 2-4
`Volatility 75` closes. The universe input is a priority list plus the chart symbol, not an absolute exclusion.

**Not done:** all five windows are 2026-09/10; no window shows `Crash 1000` trending against the book, so the trim's
downside is only observed as −0.599%. A per-symbol risk cap remains the untested lever.

## Batch 292 — the sixth window lost, the loss named the symbol, and the trim that fixes it is too good to ship yet

Batch 291 shipped the scalper off on five windows (mean +1.917%, t 3.30). The next window did not confirm it.

**Window 6, factory default, post-logging build** (`Tools\backtest_b291_default_w6.ini`, `2026.10.06` → `10.13`,
`.set` parked, `InpEnableScalpEngine` omitted, `InpQuorumProfile=1`, `InpMinLiveVoters=1`, cold):

| P&L | fills | min / max | time |
|---|---|---|---|
| **−269.61 (−2.696%)** | 307 | 9,713.44 / 10,131.30 | 0:27:53 |

Six-window distribution of the shipped default: **+3.811 / +0.635 / +1.489 / +2.640 / +1.009 / −2.696** →
**mean +1.148%, sample sd 2.213 pp, t 1.27, 5 wins of 6.** One loss halved the t-statistic. Status: positive, not proven.

**Where the −269.61 came from** (181 closes, gross −162.00):

| symbol | net | closes |
|---|---|---|
| `Volatility 75 Index` | **−116.53** | **5** |
| `Volatility 25 Index` | −52.93 | 27 |
| `Crash 1000 Index` | −36.64 | 33 |
| `Jump 25 Index` | −5.04 | 33 |
| `Jump 75 Index` | +14.33 | 65 |
| `Step Index` | +20.72 | 10 |
| `EURUSD` | +12.83 | 6 |

Worst drawdown −188.22, inside the first three hours. Five closes of V75 decided a week — Batch 285's shape again.

**The arm it motivated, no code change (`InpSymbolsToTrade` already existed):** identical windows with the two
Volatility indices removed from the universe.

| window | full universe | trimmed | delta | what carried the trimmed arm |
|---|---|---|---|---|
| 10.06 → 10.13 | −2.696% (307 fills) | **−0.599%** (307) | **+2.10 pp** | nothing large; Crash mild |
| 09.15 → 09.22 | +1.489% (261) | **+7.459%** (263, min 9,782.29) | **+5.97 pp** | `Crash 1000` **+719.52 / 87 closes** = 96% of it |
| 09.22 → 09.29 | +2.640% (260) | **+18.176%** (282) | **+15.54 pp** | `Crash 1000` **+1,848.83 / 85 closes** |

Trimmed arm: **mean +8.345%, sd 9.50 pp, t 1.52, 3 of 3 up.**

**Not shipped, and the reason is the older record, not the new one.** Batch 285 measured the opposite sign —
`Crash 1000` −123.06 on 68 closes and `Volatility 75` **+261.22 on 11 closes** in the one-voter arm; in the
committee arm the two swap sides. So "drop the Volatility indices" today is a bet on which index trends in one
2026-09/10 slice, not an edge. It needs five or six paired windows before it can join `InpMinLiveVoters` as a
shipped default.

**Method hazard this batch exposed.** The journal rotates, and the last 10,080-heartbeat slice can start inside the
*previous* run: the aborted window-3 launch (device dropped at 43%) left four heartbeats at 9,948.23 at the head of
the next slice, so "last minus first" read +1,880.39 instead of **+1,817.63**, and window 3 as +8.018% instead of
**+7.459%**. The correct base is the sample whose balance is exactly 10,000.00 within the first ten samples.

**Operational:** the aborted run left no process and a frozen log; killing leftovers and relaunching cold reproduced
the window in 0:40:41. Two stale processes silently swallowed one launch — the `Get-Process` pre-check stays mandatory.

## Where the record stands

| rule tested | windows | effect measured | verdict |
|---|---|---|---|
| determinism fix (`EAClock.mqh`) | 2 cold reruns × 2 | 10 pp spread → 0.00 pp | **shipped**, it is the measuring instrument |
| lone-voter floor 0.65 / quorum profile / support floors | 1 window each | 0.00 pp (inert, proven in-force) | **no tuning surface** |
| `InpMinLiveVoters=1` (one voter) | 6 windows + 4 baseline reruns | mean **+0.46%**, paired **+1.80 pp**, t 2.6, p≈0.08; build reproduces 4 of 4 to the cent (Batch 288) | **shipped as the default** |
| committee arm (`=2`) | 4 windows | mean **−1.31%**, 4 losses of 4 | **worse, consistently** |
| per-symbol loss brake (hold entry) | 1 window | **−4.75 pp** | **rejected** |
| per-symbol streak sizing (half stake) | 2 windows | **+1.40 pp**, then **−5.68 pp** | **rejected** |
| Batch 289 handle guard / correlation / portfolio / equity-curve fixes | 1 window | **−3.57 pp** vs the Batch 288 build, at **+167% fills** | **measured, not a gain on its own** |
| fast-scalp engine ON vs OFF, same build and window | 2 arms, 1 window | **−2.588% on 2,265 fills** vs **+3.811% on 270 fills** | **+6.40 pp, one window** |
| fast-scalp engine OFF, five consecutive windows | **5 windows** | mean **+1.917%**, sd **1.30 pp**, t **3.30**, **5/5 positive**, 260–279 fills each | **shipped as the factory default** |
| fast-scalp engine OFF, sixth window | 1 window | **−2.696%**, 307 fills; `Volatility 75` −116.53 on 5 closes | **the distribution is now mean +1.148%, sd 2.213 pp, t 1.27, 5/6** |
| universe trimmed (both Volatility indices removed) | 5 paired windows | **+2.13 / +7.05 / +5.97 / +15.54 / +2.10 pp**, 5/5 positive, paired t **2.72**; arm mean **+7.734%**, sd 6.74 pp, worst **−0.599%** | **SHIPPED as the factory universe** |
| risk dial 1× / 2× / 4× per trade | 2 windows × 3 arms | mean **+8.79% / −2.42% / +4.86%**; daily-cap rejects 2,884 → 27,471 → 17,631; fills flip Crash-led to Jump-led | **1× stands — the dial selects the book, it does not scale it** |
| daily risk ceiling 4% → 8% (1% per trade held) | **5 paired windows** | arm mean **+3.340%**, worst **−5.519%**, 4/5; paired **−5.26 pp**, sd 7.32, t −1.61, 4/5 negative; receipts 328–468 vs 282–307 | **rejected — the cap enforces concentration, it is not a throttle** |

Three things are now true with numbers behind them, and they are what the next gain has to respect:

1. **The book is decided by concentration, not by breadth.** 11–15 `Volatility 75 Index` closes at about ±23 USD
   each, plus 65–68 `Crash 1000` closes, decide a 7-day window; the other 200+ closes run at 0.15–0.45 USD each.
2. **Any rule that removes or reduces exposure hands the money to the next slot.** Both per-symbol rules moved
   fills *up* (849→1216 and 442→449) while moving the equity *down*. Risk in this EA is conserved by the budget
   machinery, so "less of this trade" always becomes "a different trade".
3. **The fast-scalp engine is negative-expectancy once it can trade every symbol.** Fixing its stop arithmetic
   (Batch 289) did not fix the engine: it turned a gate failure into 2,265 visible fills and −2.588%, and switching
   the engine off returned +3.811% on the same build. Losing runs are still followed by the biggest winners —
   `−18, −19, −56, −32, +97 … +149` on V75 — so anything that treats a streak as decay is fighting the distribution
   that pays this book, and anything that adds fills is not automatically adding money.
4. **Absolute size is set by the broker minimum, and the budgets above it are ceilings that reject instead of scale.**
   Average realised risk is ~0.2% per trade against a 1% `InpMaxRiskPerTrade`, so the only way this EA can "fish
   fast" is through more fills or larger lots — and Batch 294 measured that raising the per-trade ask converts into
   daily-cap rejections, not into size, while the fills that survive are the ones least likely to pay.

**What is still not measured anywhere in this file:** MT5's own profit factor, max drawdown and Sharpe
(`backtest_report.htm` is never written by this terminal), any walk-forward segment outside 2026-09/10 on one
instrument, and any live attach. So "profitable system" is now a claim about a mean of **+1.917% per 7 days** with
**1.30 pp** of noise (five consecutive windows, t 3.3) on one instrument under one test harness — out-of-window but
not out-of-regime, and not yet a live result.


