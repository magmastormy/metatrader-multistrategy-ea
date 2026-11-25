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

## Batch 300f — currencies were never in the universe; now they were, and they lose

**Question.** Every measured window since Batch 273 has been synthetic. Is the shipped mechanism book-dependent,
or was the currency case simply never tested? Seven majors were put in the input universe and run cold on the
shipped 6/18 defaults: `InpSymbolsToTrade = "EURUSD,GBPUSD,USDJPY,USDCHF,AUDUSD,USDCAD,NZDUSD"`, nothing else
changed, tester chart `EURUSD M15`, `Model=1`, deposit 10,000, four state files cleared per launch.

**Universe gate passed cleanly** — this is not a data problem:
`[SYMBOL-VALIDATION] Accepted: 7 | Rejected: 0`; `[SYMBOL-UNIVERSE] chart=EURUSD | configured_list_authoritative=true
| resolved=EURUSD,GBPUSD,USDJPY,USDCHF,AUDUSD,USDCAD,NZDUSD`; per-symbol `avg tick volume` 66,963–130,805 (min
1000). All seven rows traded.

| window | currencies (7 majors) | synthetics (`Crash+Boom`, same defaults) | gap |
|---|---|---|---|
| 08.01 to 08.08 | **-4.632%** (10,000 -> 9,536.78), 203 fills, 7,182 hb | +21.100% (12,110.05), 193 fills | **-25.73 pp** |
| 09.22 to 09.29 | **-5.615%** (10,000 -> 9,438.49), 209 fills, 7,179 hb | +39.266% (13,926.57), 194 fills | **-44.88 pp** |

Per-row net, 08.01: USDJPY -246.55 / 26 closes, GBPUSD -144.46 / 31, EURUSD -43.19 / 31, USDCAD -41.85 / 43,
USDCHF -33.92 / 44, NZDUSD -0.66 / 3, AUDUSD +47.41 / 25. 09.22: USDJPY -302.68 / 25, USDCHF -121.48 / 48,
AUDUSD -67.36 / 17, NZDUSD -65.49 / 8, USDCAD -33.72 / 27, EURUSD -26.63 / 58, GBPUSD +55.85 / 26. Six of seven
rows negative in both windows; the two positive rows are 1-2 orders of magnitude below the synthetic Boom row.

**Why it loses, in the journal's own terms.** Fill count is healthy (203 / 209, comparable to 193 / 194 on the
synthetic book), so this is not a signal-starvation problem and not the spread gate. The damage is per trade:
average net per close **-2.28** and **-2.69** USD across 203-209 closes. The book still trades at the **lot
floor** - 371 `[RISK-LOT-FLOOR]` lines on 08.01, 536 on 09.22, i.e. the 1%-risk ask and the 3x minimum-lot
multiplier cannot be satisfied at 0.01 lots on a 10k account with FX-sized stops, so every position is
minimum-size and the per-trade edge is a couple of dollars against a 1-minute-OHLC modelled spread. On Crash/Boom
the same floor is a *feature*: the synthetic rows move in large point increments, so a minimum lot captures a
large per-trade move. On majors the same lot captures a few dollars.

**Wall clock and shape.** 26 and 29 minutes; heartbeats stop at Friday 20:54 instead of 23:59 because the FX
market closes - so the heartbeat slice is 7,179-7,182 samples, not 10,079. Any future FX comparison has to be
made on heartbeat-length-normalised numbers, not on raw totals.

**Conclusion: nothing shipped, and currencies stay out of the universe.** The measured edge is
synthetic-spike-specific, as the prior said. The honest open candidate is not "add currencies to the book" but
"can the FX book be made to pay at a different size" - i.e. per-trade risk above 1% or lot-floor disabled, run as
its own universe - which is a separate experiment and was not run here.

## Batch 300e — the loosening became per-symbol, the ceiling moved up, and the scalp engine was measured dead

**Question.** Batch 300d shipped `Crash + Boom 1000` by raising the global send-time disaster-quote backstop
`InpMaxEntrySpreadPoints` from 15000 to 25000 — a ~67% loosening for the whole book to admit one instrument whose
quote is a constant ~17,185 points. Six open items were left behind: a per-symbol override instead of the global
loosening, Boom outside the slice, the month-length window, the daily risk ceiling on the two-row book, the
scalp-on window, and the parked `.set` files. This batch ran them.

### 1. Per-symbol override replaced the global loosening, and reproduced it to the cent

New input `InpSymbolHardSpreadOverridesCsv` (`Symbol=Points` pairs, default `"Boom 1000 Index=25000"`) with the
global `InpMaxEntrySpreadPoints` restored to 15000. There are **two** live gates, not one, and the second one is
the lesson:

- pre-consensus: `validatorHardSpreadCutoff = MathMax(m_config.hardSpreadCutoffPoints, <per-symbol limit>)`
  (`EAOrchestrator.mqh`), logged as `[VALIDATOR-CONFIG] ... hard_spread_cutoff=25000.0pts (... symbol_limit=25000.0)`;
- send-time: `TradeMgrPreflight.mqh:127` `spread_points > maxEntrySpreadPoints` fed by
  `TradeManager::ValidateExecutionPreflight`. Opening the validator alone still produced **0 Boom closes** (202
  `[INTENT-STAGE] Boom ... outcome=REJECTED reason=Success` inside 17 ms); the send-time path had to learn the
  override too (`TradeManager::EffectiveEntrySpreadLimit`).

| arm (08.01 to 08.08, cold) | return | balance | fills | Boom own net | Crash own net |
|---|---|---|---|---|---|
| 300d: global `InpMaxEntrySpreadPoints=25000` | +14.714% | 11,471.44 | 165 | +705.38 / 31 closes | +766.06 / 134 |
| 300e: override `Boom=25000`, global back to 15000 | **+14.714%** | **11,471.44** | **165** | **+705.38 / 31** | **+766.06 / 134** |

Same min 9,966.75 / max 11,485.28, same 268 `[RISK-LOT-FLOOR]` lines (Crash 160 / Boom 108). The override buys the
Boom fills without loosening the backstop for anything else.

### 2. Boom outside the slice: 2 of 3 windows add, one loses, mean positive but noisy

Two windows never used in the Boom search, each paired with a fresh `Crash`-only control on the same cold binary:

| window | `Crash+Boom` | `Crash` only | paired | Boom own net |
|---|---|---|---|---|
| 09.22 to 09.29 | +36.017% (171 fills) | +15.353% (165) | **+20.66 pp** | +1,407.71 / 42 closes |
| 10.13 to 10.20 | +9.171% (169) | +8.368% (175) | **+0.80 pp** | +178.87 / 28 closes |
| 07.01 to 07.08 (300d) | +2.075% | +4.075% | **-2.00 pp** | -104.62 / 35 closes |

Out-of-slice mean **+6.49 pp**, sd 12.36, 2/3. The direction holds; the size does not. `09.22` says Boom is a
second payer, `10.13` says it is nearly inert, July says it can cost. All nine paired windows counted so far
(5 in-slice from 300d, these two, July, plus 08.01) are positive except July.

### 3. The month-length window: the July week's loss does not compound

`07.01 to 08.01`, 31 days, 44,629 heartbeats, 99 minutes wall:

| metric | value |
|---|---|
| return | **+66.520%** (10,000 to 16,652.05) |
| fills / closes | 834 / 833 |
| Boom own net | **+2,758.92** / 153 closes |
| Crash own net | +3,876.80 / 680 closes |
| min / max balance | 9,986.33 / 17,226.43 |

No 31-day `Crash`-only control exists, so this is not an attribution — it is a shape check: the window whose week
lost 2 pp still paid, and Boom's own line is the largest single-row contribution the book has produced. Caveat
that matters: this is a 31-day run of a compounding book, so +66.5% is not a per-week rate to multiply.

### 4. `InpMaxDailyRisk` 4% to 6% (with `InpMaxPortfolioRisk` 12% to 18%) on the two-row book: 4/4, t 2.99

Same 1% per-trade ask; only the concurrency ceiling moved. Four cold paired windows against the 4/12 arm:

| window | 6/18 | 4/12 | paired | fills 6/18 vs 4/12 |
|---|---|---|---|---|
| 08.01 to 08.08 | +21.100% (12,110.05) | +14.714% | **+6.386 pp** | 193 vs 165 |
| 09.01 to 09.08 | +9.770% (10,976.98) | +6.871% | **+2.899 pp** | 194 vs 164 |
| 09.22 to 09.29 | +39.266% (13,926.57) | +36.017% | **+3.249 pp** | 194 vs 171 |
| 10.13 to 10.20 | +20.793% (12,079.30) | +9.171% | **+11.622 pp** | 201 vs 169 |

Paired mean **+6.04 pp**, sd 4.04, **t 2.99**, **4/4**. The mechanism is visible in the journal: the 4% arm was
refusing entries with `[RISK-DAILY-LIMIT] reason=daily_risk_would_exceed effective=3.97% + new=1.00% >= limit=4.00%`,
i.e. the ceiling, not the signal, was the constraint; at 6% those entries became Boom closes (Boom 31 to 42, 42 to
50, 28 to 38 across the windows).

This contradicts Batch 294, where the same lever at 8/24 on the **eight-symbol** book measured **-5.26 pp**
(t -1.61). The book changed, so the lever changed meaning: on eight rows the ceiling re-selected a worse book, on
two rows it just lets the second payer trade more.

### 5. Scalp engine on: structurally dead on synthetic spreads, zero effect on P&L

`InpEnableScalpEngine=true`, same `Crash+Boom` book, cold 08.01 to 08.08:

| metric | result |
|---|---|
| return | **+14.714%** — identical to scalp-off, to the cent |
| fills | 165 — identical |
| `[SCALP-CLOSE]` | 0 |
| `[SCALP-SIGNAL-REJECT]` | 19,897 — **all** `gate=spread_vs_atr` (Boom 10,008 / Crash 9,887) |

The engine initialises (`[SCALP-DIAG] initialized=true`, 10,079 lines) and produces no fillable signal because
Crash/Boom quotes are far too wide relative to their ATR. Scalp is not a lever for this book; it needs either a
`spread_vs_atr` gate change or a non-synthetic universe, and neither was run here. The old
`Tools\backtest_b290_scalp2.ini` (`XAUUSD,Step Index`) still has not been run as written.

### What shipped

- `InpSymbolHardSpreadOverridesCsv = "Boom 1000 Index=25000"` (new input, `SharedEAInputs.mqh`) and
  `InpMaxEntrySpreadPoints` back to **15000.0**.
- `InpMaxDailyRisk = 6.0`, `InpMaxPortfolioRisk = 18.0` in `MultiStrategyAutonomousEA.mq5`.
- Override plumbed through both gates: `OrchestratorConfig` field + reset, `EAOrchestrator` CSV parse and
  `TradeManager::SetSymbolSpreadOverrides` / `EffectiveEntrySpreadLimit` (`TradeManager.mqh`, used by
  `TradeMgrPreflight.mqh:127`), plus the duplicate mapping block in `MultiStrategyAutonomousEA.mq5` that the
  shared populate does not cover.
- Compile: `OVERALL SUCCESS`, 0 errors / 0 warnings, all eight programs (root EA 75,688 ms).
- **Defaults verified by omission:** `.set` parked, ini carrying only `InpQuorumProfile` / `InpMinLiveVoters` /
  `InpMaxRiskPerTrade` — no universe, no spread, no override, no risk ceiling — cold 08.01 to 08.08:
  **+21.100%** (10,000 to 12,110.05), 193 fills, Boom 42 closes +1,131.48, Crash 151 closes +978.57, min 9,966.75 /
  max 12,171.48 — the 6/18 arm to the cent.

### Harness note that cost a window

MT5 reads a `.ini` duplicate key **first occurrence wins**. The first `risk6_w1` arm carried both
`InpMaxDailyRisk=4.0` and `InpMaxDailyRisk=6.0`; the run came back +14.714%, identical to the 4% baseline, and the
journal proved it: `limit=4.00%` in `[RISK-DAILY-LIMIT]`. The arm was null, not inert. Both files were de-duplicated
and re-run (+21.100%). Every `.ini` in `Tools\b300e_*` was then scanned key-by-key for duplicates.

## Batch 300d — the second payer was measured, not guessed: `Jump 75` rejected, `Boom 1000` shipped

**Question.** Batch 300 left the book at one instrument and one payer. The open question was whether a second
instrument can add, given that every other row on the eight-symbol book summed negative. Two candidate arms, both
measured against the same shipped `Crash 1000` binary on the same cold windows.

**Arm B — `Crash + Jump 75`, rejected on three windows.**

| window | `Crash+Jump 75` | `Crash` only | paired | `Jump 75` own net | `Crash` own net |
|---|---|---|---|---|---|
| 08.01→08.08 | +4.553% (201 fills) | +10.837% | **−6.28 pp** | −72.35 / 109 closes | +527.66 / 92 |
| 09.01→09.08 | −1.559% (214) | +2.614% | **−4.17 pp** | −28.61 / 120 | **−127.29** / 94 |
| 07.01→07.08 | −0.805% (225) | +4.075% | **−4.88 pp** | +11.41 / 129 | **−91.86** / 96 |

The mechanism is not the losers' own P&L, it is throughput: a small row eats the lot floor and the daily budget,
and the payer's closes fall from 168/164/183 to 92/94/96. `Crash` itself went net-negative in two of the three
windows. Rejected — `InpSymbolsToTrade` stays as it was.

**Arm A — `Crash + Boom 1000`: the row was never alive, and the knob was not the one assumed.**
Three windows of `Crash+Boom` reproduced the `Crash`-only arm **to the cent** (+10.837 / +2.614 / +4.075), with
zero Boom closes. The journal was not empty — `Boom 1000 Index` appears ~50,000 lines per window, scanned and
scored — it was vetoed:
`[SIGNAL-REJECTED] Boom 1000 Index | reason=hard_spread_cutoff | spread_points=17185.0 > 15000.0` (1,077 vetoes
per window). The gate is `validatorHardSpreadCutoff = MathMax(hardSpreadCutoffPoints, maxEntrySpreadPoints)`
(`EAOrchestrator.mqh:1956`), so the knob is **`InpMaxEntrySpreadPoints`** (15000), not `InpSymbolMaxSpreadPoints`
— raising the latter to 20,000 changed nothing, the log still printed 15000.0.

**Control arm, because a wider gate is not free.** `Crash`-only with `InpMaxEntrySpreadPoints=25000`, cold, same
windows: `08.01` **+10.837%** (168 fills, min 9,997.40 / max 11,107.95) and `09.01` **+2.614%** (164 fills, min
9,755.57 / max 10,261.75) — identical to the 15,000 arm to the cent. The loosening is inert for `Crash` (its
quotes never approach even 15,000), so every delta below belongs to Boom.

**Arm A with the right knob, five windows plus one out of slice.**

| window | `Crash+Boom` @25000 | `Boom 1000` own net | `Crash` only | paired |
|---|---|---|---|---|
| 08.01→08.08 | **+14.714%** (11,471.44 / 165 fills) | +705.38 / 31 closes | +10.837% | **+3.88 pp** |
| 08.08→08.15 | **+20.169%** (12,016.89 / 170) | +376.54 / 34 | +15.786% | **+4.38 pp** |
| 09.01→09.08 | **+6.871%** (10,687.08 / 167) | +623.66 / 44 | +2.614% | **+4.26 pp** |
| 09.15→09.22 | **+19.809%** (11,980.91 / 162) | +764.13 / 39 | +17.682% | **+2.13 pp** |
| 10.06→10.13 | **+16.135%** (11,613.45 / 175) | +909.36 / 38 | +5.134% | **+11.00 pp** |
| 07.01→07.08 (out of slice) | +2.075% (10,207.47 / 181) | −104.62 / 35 | +4.075% | **−2.00 pp** |

Paired distribution over the five in-slice windows: mean **+5.13 pp**, sd 3.41, **t 3.37**, **5 of 5 positive**.
Boom's own average close is ≈ +22–24 USD — a real second payer, not a rounding effect — and it costs 31–44 closes
per window, so the payer's own throughput is unharmed (134–146 `Crash` closes, versus 157–186 alone).

**The one honest caveat.** July, outside the slice, is negative: Boom lost 104.62 over 35 closes while `Crash`
kept paying. So this is a 5-of-5 in-slice distribution with one out-of-slice window that disagrees, at a t of 3.37
rather than the 3.56 the shipped single-symbol arm holds. And the price of admission is a real risk change: the
send-time disaster-quote backstop moves 15,000 → 25,000 points, about +67%. With only two symbols in the universe,
Boom is the sole beneficiary, but that is an argument about exposure, not about safety — a per-symbol spread
override would be strictly better and is not built.

**What shipped (compiled 0 errors / 0 warnings on all eight programs):**
1. `Core\Config\SharedEAInputs.mqh` → `InpSymbolsToTrade = "Crash 1000 Index,Boom 1000 Index"`, with the measured
   five-window block above it.
2. `Core\Config\SharedEAInputs.mqh` → `InpMaxEntrySpreadPoints = 25000.0`, with the reason (Boom quotes ~17,185
   constantly) and the inert-for-Crash control result written above it.

**Default-by-omission witness.** `.set` parked to `.parked_b300d`, ini carrying neither `InpSymbolsToTrade` nor
`InpMaxEntrySpreadPoints`, cold, `08.01→08.08`: **+14.714%** (10,000 → 11,471.44), 165 fills, `Boom` 31 closes
+705.38, `Crash` 134 closes +766.06, min 9,966.75 / max 11,485.28 — the arm's number to the cent.

## Batch 300 — the logs were never missing, and the August loss has a name: `Crash 1000` throughput

**Question.** The previous batch recorded an "observability regression" — receipts and close P&L gone from the
rebuilt engine — which would make every "which symbol pays" question unanswerable. Restore them, re-record the
results, and then act on what they say.

**Answer to the logging question: nothing was broken.** A full-file tag scan (not a tail slice, which is what
produced the wrong claim) counts, in each `w1` journal:

| journal | `[EXECUTION-RECEIPT]` | `Trade Closed ... Net Profit:` | `[RISK-LOT-FLOOR]` | `[INTENT-STAGE]` |
|---|---|---|---|---|
| merged `f0c1bea` | **472** | **472** | 2,820 | 21,166 |
| pre-merge `09e18b0` | **404** | **403** | 0 | 0 |

The prints are unconditional on the live path: `Core\Trading\TradeManager.mqh:1428` (receipt, inside
`CTradeManager::ExecuteMarketOrder`, reached through `OpenPosition`) and
`Core\Management\StrategyMgrTradeFeedback.mqh:217` (close, in `OnTradeTransaction`). Async sending, the only path
that would bypass the receipt, defaults off (`TradeManager.mqh:293` `m_useAsyncMode(false)`). No source change was
needed or made for this.

**The attribution, and it reconciles to the cent.** `08.01 -> 08.08`, identical inputs, cold both arms:

| arm | fills / closes | close net | `Crash 1000` | `Jump 75` | `Jump 25` | `Step` | `Volatility 75` |
|---|---|---|---|---|---|---|---|
| `09e18b0` | 256 | **+372.81** | **+489.07 / 106** | -70.76 / 96 | -91.12 / 41 | -25.96 / 6 | **+72.77 / 3** |
| `f0c1bea` (HEAD) | 215 | **+31.72** | **+222.44 / 74** | -88.26 / 89 | -62.19 / 35 | -38.92 / 9 | **0 / 0** |

`close net` equals the 10,080-heartbeat delta exactly in both arms, so this is reconciliation, not a lower bound.
The loser rows are flat (-190.36 vs -190.87). **The 3.4 pp difference between the two builds is one row's
throughput**: `Crash 1000` closed 106 times for +489 and now closes 74 times for +222, and `Volatility 75`
disappeared from the book entirely.

**What the lot floor actually does.** `[RISK-LOT-FLOOR]` fires 1,484 times in the merged window — `Jump 25` 502,
`Jump 75` 490, `Crash 1000` 273, `GBPUSD` 127, `AUDUSD` 66, `Step` 26 — at `uplift=1.10x <= cap=3.00x`, with mean
sizes `0.0097 -> 0.0100` (min-lot rows), `0.1935 -> 0.2000` (`Crash`), `0.0959 -> 0.1000` (`Step`). It is min-lot
rounding with a ceiling, not a size lever: the average uplift is 1.10x and the cap never binds.

**The gate that moved instead.** Pre-merge `[RISK-GATE-REJECT]`: **894 `final_lot_validation`, 142
`symbol_budget_lot_cap`, 13 `correlation_reduce_below_min_lot`**. Merged: **5, 0, 99**, with
`[INTENT-STAGE] scaled_lot_not_tradeable` **1,637** taking their place. So the merged build does not resize — it
converts "the scaled lot is untradeable, refuse" into "trade it at the broker minimum", 1,637 candidates becoming
1,484 min-lot fills. Those small rows consume the 4% daily budget, and the tickets that pay are the large ones.

**Consequence for the queue.** The "per-symbol cap that binds on lot size" is now answerable in two parts: the lot
floor already exists and is capped at 1.10x effective, so a cap on it buys nothing; the binding constraint is the
*daily budget being spent on min-lot rows*. The experiment that decides it is `InpMinLotRiskMultiplier=1.0`
(any sub-min-lot scale is refused rather than lifted), run on `08.01` and `09.01`.
### The decisive test: give the book only the row that pays (Crash-only arm), and it ships

`InpSymbolsToTrade="Crash 1000 Index"`, everything else factory, same binary, same five cold windows:

| window | eight-symbol arm (HEAD) | **Crash-only** | delta | fills | closes | min / max |
|---|---|---|---|---|---|---|
| 08.01 -> 08.08 | +0.317% (10,031.72) | **+10.837%** (11,083.66) | **+10.52 pp** | 168 | 168 | 9,997.40 / 11,107.95 |
| 08.08 -> 08.15 | +9.178% (10,917.78) | **+15.786%** (11,578.65) | **+6.61 pp** | 166 | 166 | 9,997.71 / 11,680.49 |
| 09.01 -> 09.08 | +1.988% (10,198.79) | **+2.614%** (10,261.40) | **+0.63 pp** | 164 | 164 | 9,755.57 / 10,261.75 |
| 09.15 -> 09.22 | +6.724% (10,672.39) | **+17.682%** (11,768.17) | **+10.96 pp** | 157 | 157 | 9,877.35 / 11,823.56 |
| 10.06 -> 10.13 | +3.970% (10,397.04) | **+5.134%** (10,513.41) | **+1.16 pp** | 186 | 186 | 9,709.67 / 10,513.62 |

**Arm mean +10.41%, sd 6.53 pp, t 3.56, 5/5 positive, worst +2.614%.** Paired deltas mean **+5.98 pp**, sd
4.94, **t 2.70**, 5/5 positive. Every window's closes reconcile to its heartbeat delta; the worst drawdown of
the whole arm is 2.9% (09.15's 9,877.35), and the best window gained 17.7%.

**The mechanism is throughput, not a better entry.** The same signals produce roughly twice the closes -
74 in each eight-symbol window, 157-186 here - because the daily budget is no longer spent on rows that lose.
Dollars per close move both ways against the book (`08.01` +3.0 -> +6.4, `08.08` +14.8 -> +9.5), so the size of a
single close is not the effect; the count is.

**What it costs.** Concentration. There is no second instrument to absorb a Crash regime change, and this is the
same failure mode every previous trim argument had - except this one is measured on five paired windows instead
of one. **Shipped:** `Core\Config\SharedEAInputs.mqh` now reads `InpSymbolsToTrade = "Crash 1000 Index"` with the
five-window table and the restore instructions above it. `InpAutoAddChartSymbol` no longer exists in the merged
tree, so the universe is authoritative and no chart symbol is injected.

**Default proved by omission, not by reading code:** `Tools\backtest_b300_default_w1.ini` omits `InpSymbolsToTrade`
and the tester `.set` was parked as `.set.parked_b300b`. Cold run: **10,000.00 -> 11,083.66, +10.837%**, 168 fills,
min 9,997.40 / max 11,107.95, 171 `[RISK-LOT-FLOOR]` lines all on `Crash 1000` - identical to the arm to the cent.
### Out of the 2026-08..10 slice: the single row holds up in July and survives June's truncated window

Two cold windows outside the shipped distribution, `Tools\backtest_b300_crash_x1.ini` / `_x2.ini`, same binary,
only dates changed:

| window | result | fills / closes | min / max | note |
|---|---|---|---|---|
| 07.01 -> 07.08 | **+4.075%** (10,407.45) | 183 / 183 | 9,995.60 / 10,628.27 | seven full days, reconciles to the cent |
| 06.01 -> 06.08 | **+4.208%** (10,470.48 -> 10,910.99) | 81 / 81 | 10,448.85 / 11,045.66 | history for `Crash 1000` starts **06.04 01:57**, so this is 3.9 days, and the run's equity was already 10,470.48 at its first heartbeat |

**The June window's "+9.110%" is an artifact, not a result.** My delta base is the heartbeat whose balance is
exactly 10,000.00 within the first ten samples; this run had no such sample because the tester's tick history for
`Crash 1000` begins at `2026.06.04 01:57` and the pre-rotation part of the journal was already 470 USD up. Using
10,470.48 as the base gives **+440.51, exactly the sum of the 81 `Trade Closed` nets** - the same reconciliation
standard as every other window. Recorded so the next reader does not quote +9.110%.

**Seven-window Crash-only record:** +10.837 / +15.786 / +2.614 / +17.682 / +5.134 / +4.075 / +4.208 -> mean
**+8.619%**, sd **6.15 pp**, **t 3.71**, **7/7 positive**, worst **+2.614%**, worst drawdown 2.9%. The two
out-of-slice weeks are the weakest of the seven, which is the honest read: the edge is smaller outside August-October
but it does not invert.

**Data boundary found:** `Crash 1000` tick history in this terminal is not guaranteed before `2026.06.04`, so any
"out-of-regime" test earlier than June silently produces a shorter run. Check the first heartbeat timestamp against
the ini `FromDate` before believing any window.
### Month-length window: 31 days, 836 closes, +50.565% - and the gain scales with equity

`Tools\backtest_b300_crash_m1.ini`, `2026.07.01` -> `2026.08.01`, cold, same binary, Crash-only:

- 10,000.00 -> **15,056.49**, **+50.565%**, **836 fills / 836 closes**, close-net **+5,056.49** = the heartbeat delta
  to the cent. Opening balance is exactly 10,000.00 (verified at `07.01 00:00:01`), so no base artifact here.
- Lowest balance inside the month **9,995.60**, highest **15,732.36**; **max drawdown from running peak 9.51%**.
- Day-by-day: **22 of 31 days positive**, mean **+1.348%** per day, sd 1.994 pp, best **+6.32%**, worst **-1.85%**.
- 98 minutes of wall clock for 31 days (vs 21 for 7), i.e. the harness cost is linear in simulated days.

**Why the month prints far more than 4.4 weekly windows would imply** (weekly arm = +4.075% on 07.01->07.08; four
weeks compounded at that rate is ~+17%): the book is not flat-bet. Lot floor, compounding tiers and the daily budget
all scale with balance, so the same edge is applied to a growing equity - 10,000 -> 10,247 -> 11,041 -> 12,254 ->
13,799 -> 15,539 across the month. That is compounding on top of the edge, and it cuts both ways: the 9.51% peak-to-
trough drawdown happens at month-end when the lots are 50% larger, not in week one.

**Read this as one sample, not a distribution.** It is one month, one instrument, tester ticks, no live attach. The
seven-window weekly record (mean +8.619%, sd 6.15, t 3.71) is the distribution; the month is the persistence check
that says the edge survives 31 consecutive days and does not die after the first week.

**Harness note:** the month run's journal is 849 MB and shares its first slice with the previous June run, so the
"last run" reader must key on the `07.01 00:00:01` boundary, not on the file's first heartbeat. Balance parsing also
produced a spurious `min=1460.00` from a non-heartbeat field once; report min/max drawdown only from lines that carry
`[COMPOUNDING-TIER-HEARTBEAT]` and a numeric `balance`.
## Batch 299b — the merged build (HEAD `f0c1bea`): mean +4.435%, and four of five windows are bit-identical to the pre-merge build

**Question.** Batch 299 measured `09e18b0` because that was the tree when the binary was compiled. HEAD also
contains the `origin/main` merge (`f0c1bea`: `995cb3b` intent tracing + hardened execution gates, `0c7260c` risk
governance). Does the merged build still produce the same book?

**Setup.** Identical to Batch 299 — factory defaults, same five windows, same `Volatility 75 Index` M15 /
`Model=1` / deposit 10,000, four state files cleared, `.set` still parked, cold each run. Recompiled from HEAD:
`sync_files.ps1` (57 Python files) then `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 900` ->
**`OVERALL SUCCESS`, 0 errors / 0 warnings on all eight programs** — root EA **70,390 ms**, Testing 80,666 ms
(against 285,687 / 307,721 ms for the pre-merge build: the merge is ~4x cheaper to compile, which is the "debloat").

| window | balance | delta | % | min | max | tester |
|---|---|---|---|---|---|---|
| 08.01→08.08 | 10,000.00 → 10,031.72 | **+31.72** | **+0.317%** | 9,945.86 | 10,220.14 | 0:45:05 |
| 08.08→08.15 | → 10,917.78 | **+917.78** | **+9.178%** | 9,999.19 | 10,985.39 | 0:25:28 |
| 09.01→09.08 | → 10,198.79 | **+198.79** | **+1.988%** | 9,926.04 | 10,260.29 | 0:25:33 |
| 09.15→09.22 | → 10,672.39 | **+672.39** | **+6.724%** | 9,756.30 | 10,706.30 | 0:22:15 |
| 10.06→10.13 | → 10,397.04 | **+397.04** | **+3.970%** | 9,897.91 | 10,482.03 | 0:32:11 |

**Arm:** mean **+4.435%**, sd **3.57 pp**, **t 2.78**, **5/5 positive**, worst **+0.317%**, best **+9.178%**.
All five terminal lines read `successfully finished`, all five slices are exactly 10,080 samples starting at the
ini `FromDate`.

**Paired against `09e18b0` (Batch 299):** `−3.411 / 0 / 0 / 0 / 0` pp -> mean **−0.682 pp**, sd 1.53, **t −1.00**,
0/5 positive. **Four of the five windows reproduce the pre-merge build to the cent** — not approximately, exactly,
down to min and max equity — and the whole difference sits in `08.01→08.08`.

| | `09e18b0` (Batch 299) | **`f0c1bea` (Batch 299b, HEAD)** |
|---|---|---|
| mean | +5.118% | **+4.435%** |
| sd | 2.83 pp | **3.57 pp** |
| t | 4.04 | **2.78** |
| worst | +1.988% | **+0.317%** |
| best | +9.178% | **+9.178%** |
| negative windows | 0/5 | **0/5** |

**Why only one window moved — mechanism.** Tag-level diff of the two w1 journals: the merged build emits
**`[RISK-LOT-FLOOR]`** (`Crash 1000 Index | lot 0.1815 -> 0.2000 | uplift=1.10x <= cap=3.00x`) and
**`[INTENT-STAGE]`**, and **no longer emits `[RISK-GATE-REJECT]`** (it emitted neither of the first two before).
So the remote risk-governance work replaced the hard reject with a *capped size uplift* to the broker minimum,
and added intent tracing, which is exactly the binding-on-lot-size lever `REMAINING_WORK.md` has been asking for —
but as an uplift with a 3.00x ceiling, not as a per-symbol cap. Where the uplift does nothing different from the
old rounding the windows are identical; the August open is the one window where the changed gate altered the
trade path, and it cost 3.411 pp there.

**Verdict.** No input changed, nothing shipped. On the current HEAD the factory configuration still has **5/5
positive windows**, mean **+4.435%**, worst **+0.317%**, and remains statistically above zero (t 2.78) but below
the pre-refactor arm (+5.345% across Batch 297) by 0.91 pp. The honest summary of the whole refactor + merge, on
identical windows: **no distribution has been lost, none has been gained, and the compile cost fell by ~4x.**
## Batch 299 — the post-refactor baseline: five cold windows, mean +5.118%, and the rebuild is neutral, not an improvement

**Question.** The working tree carries a 242-file refactor that has never been measured. Does the rebuilt engine
still produce the Batch 297 factory distribution, or did the refactor move the book?

**Baseline note (read before the numbers).** These five windows were measured on the refactor commit **`09e18b0`**
("Deep audit: fix correctness defects ... dedupe and harden Python training pipeline", committed 12:42:50). That
commit was still the working tree when the binary was compiled at ~12:35, so the `.ex5` under test is `09e18b0`.
While the sweep was running, `origin/main` was merged into the tree as **`f0c1bea`** (13:39:26), which brought in
`995cb3b` / `0c7260c` / `7c712fe` and **153 changed files including MQL5 strategy sources**
(`Strategies/NYOpenGapStrategy.mqh`, `SupportResistanceDetector.mqh`, `TrendlineDetector.mqh`,
`MarketStructureAnalyzer.mqh`, `TrainingDataExporter.mq5`, `crash_recovery_helpers.mqh`). Those are **not** in the
measured binary. This table therefore describes `09e18b0`, not HEAD; the merged build needs its own sweep before
any number can be attributed to it.

**Setup.** Factory defaults, no input changed: `InpMaxRiskPerTrade=1.0`, `InpMaxDailyRisk=4.0`,
`InpMaxPortfolioRisk=12.0`, `InpSymbolsToTrade` = the eight Batch 297 symbols, `InpQuorumProfile=1`,
`InpMinLiveVoters=1`, scalper off. `Volatility 75 Index` M15, `Model=1`, deposit 10,000, leverage 1:100, all four
state files deleted before every launch, `MultiStrategyAutonomousEA.set` parked as `.set.parked_b299` so the
compiled defaults execute, `Get-Process terminal64,metatester64` confirmed empty before every launch.

| window | balance | delta | % | min | max | tester |
|---|---|---|---|---|---|---|
| 08.01→08.08 | 10,000.00 → 10,372.81 | **+372.81** | **+3.728%** | 9,962.81 | 10,454.29 | 1:22:46 |
| 08.08→08.15 | → 10,917.78 | **+917.78** | **+9.178%** | 9,999.19 | 10,985.39 | 0:34:58 |
| 09.01→09.08 | → 10,198.79 | **+198.79** | **+1.988%** | 9,926.04 | 10,260.29 | 0:32:30 |
| 09.15→09.22 | → 10,672.39 | **+672.39** | **+6.724%** | 9,756.30 | 10,706.30 | 0:28:51 |
| 10.06→10.13 | → 10,397.04 | **+397.04** | **+3.970%** | 9,897.91 | 10,482.03 | 0:34:25 |

**Arm:** mean **+5.118%**, sd **2.83 pp**, **t 4.04**, **5/5 positive**, worst **+1.988%**, best **+9.178%**.
Every window is 10,080 heartbeat samples starting exactly at the ini `FromDate` and every terminal log line reads
`last test passed with result "successfully finished"` — the Batch 298 validity rule is satisfied five times.

**Paired against Batch 297** (pre-refactor binary, same five windows, same inputs): `+2.098 / +1.902 / −3.693 /
−0.720 / −0.722` pp → mean **−0.227 pp**, sd **2.37**, **t −0.21**, **2/5 positive**. Batch 297 arm on the same
windows: mean +5.345%, sd 2.37, worst +1.630% (dominance over mean, sd and worst is the ship criterion there,
and here not even the mean moves).

| | Batch 297 (pre-refactor) | **Batch 299 (rebuild)** |
|---|---|---|
| mean | +5.345% | **+5.118%** |
| sd | 2.37 pp | 2.83 pp |
| t | 5.04 | **4.04** |
| worst | +1.630% | **+1.988%** |
| best | +7.444% | **+9.178%** |
| negative windows | 0/5 | **0/5** |

**What it means.** The refactor is P&L-neutral inside the noise this repository already knows: it does not destroy
the edge, and it does not add one. It changes the *shape* rather than the level — both August windows gain
(+2.10, +1.90 pp) while the three September/October windows lose (−3.69, −0.72, −0.72 pp) — so the trim-induced
worst-case of Batch 297 (+1.630%) becomes +1.988% while the spread widens from 2.37 to 2.83 pp. The paired t of
−0.21 is the honest number: this is a wash, and the correct claim is "the rebuild still pays, within noise", not
"the rebuild pays more".

**Cost of the rebuild.** Wall clock per 7-day window is now **28–83 minutes** against ~23–26 minutes before
(variance is machine load, not the EA): a five-window sweep is an afternoon, not two hours. Compile is also much
heavier — root EA **285,687 ms** against Batch 297's 74,406 ms, Testing EA 307,721 ms.

**Observability: corrected same day - nothing was missing.** A full-file scan (not a tail slice) counts
`[EXECUTION-RECEIPT]` **472** and `Trade Closed ... Net Profit:` **472** in the merged `w1` journal and
**404 / 403** in the `09e18b0` one. The lines are printed unconditionally at
`Core\Trading\TradeManager.mqh:1428` and `Core\Management\StrategyMgrTradeFeedback.mqh:217`, on the
`OpenPosition -> ExecuteMarketOrder` path, which is the live path because async sending defaults off
(`TradeManager.mqh:293`). No code change was required; the earlier claim was a measurement error, and per-symbol
dollars are available again - see Batch 300 below, where the close sums reconcile to the heartbeat delta to the
cent.

**New hazard, cost two windows and three control runs — port 3000.** An unrelated Node dev server on this machine
(`D:\MoneyBuildersProject\...`, `next start`) bound `127.0.0.1:3000`, which is the local MetaTester agent port. The
terminal logged `automatic testing started` and then, 32 s later, `last test passed with result "some error after
pass finished" in 0:00:00.000`; the agent log showed `login` → `tester forced to close` with no EA lines at all.
Two independently different inis failed identically, **and re-running the already-proven w1 also failed** — which
is what excluded the ini and pointed at the farm. Fix: `netstat -ano | findstr :3000`, kill any non-`metatester64`
holder, confirm the port is owned by `metatester64`, *then* launch. The Node server is supervised and respawned at
least once, so the port must be re-checked before every launch, not once per batch.

**Verdict.** Nothing shipped, no input changed, factory config stands: 8 symbols, 1% / 4% / 12%, quorum profile 1,
one live voter, scalper off. The rebuild passes the "does not destroy the edge" test and fails the "improves it"
test, so the next lever is still the one `REMAINING_WORK.md` names — a per-symbol risk cap that binds on **lot
size**. The daily ceiling is visibly binding in this build as well: `[RISK-DAILY-CAP]` reports
`effective=4.13% capped to limit=4.00%` with 1,312–1,936 occurrences per window, and `[RISK-BUDGET]` closes each
window at `effective=3.99/4.00`.
## Batch 298 — the last two bleeders inside the winning windows: measured, and they are not bleeders

Batch 297 removed the three rows that never paid and the distribution turned all-positive. The obvious next move is to
finish the job: `Step` and `Jump 25` still lose inside windows that make money, so remove them too and see whether the
record gets better. It does not. This batch is the cleanest negative result in the file, and it is useful precisely
because it was predictable.

**The reading that justified the arm.** In the eight-symbol windows (from the Batch 297 journals, per-symbol net after
commission, `attr2.py`):

| window | `Crash 1000` | `Jump 75` | `Step` | `Jump 25` |
|---|---|---|---|---|
| 08.01 → 08.08 | +330.80 / 114 closes | −72.66 / 108 | −81.27 / 15 | −119.71 / 47 |
| 08.08 → 08.15 | +813.19 / 104 | +18.64 / 75 | −51.70 / 19 | −95.20 / 45 |
| 09.01 → 09.08 | +520.65 / 118 | −0.13 / 110 | −28.32 / 15 | +32.67 / 49 |
| 09.15 → 09.22 | +688.92 / 104 | −48.16 / 107 | +78.07 / 14 | −55.81 / 59 |
| 10.06 → 10.13 | +674.20 / 118 | +92.74 / 132 | −68.20 / 16 | +6.45 / 60 |
| **sum** | **+2,706.76** | **−43.71** | **−151.42** | **−231.60** |

Across the five windows `Step` loses 4 of 5 and `Jump 25` loses 4 of 5 — together **−383.02 USD**, which is about
0.77% of the deposit per window spent on 150 closes. Every argument says removing them should lift the mean.

**Run.** `Tools\backtest_b298_six_w1..w5.ini`, `InpSymbolsToTrade=Boom 1000 Index,Crash 1000 Index,Jump 75 Index,`
`GBPUSD,AUDUSD,BTCUSD` (six symbols), everything else identical to the shipped arm: same Batch 293 binary (no source
change), `1%` per trade / `4%` daily / `12%` portfolio, `InpQuorumProfile=1`, `InpMinLiveVoters=1`, scalper off,
`Model=1`, deposit 10,000, all four state files cleared before every launch, scoreboard archived per window.

| window | eight symbols (shipped) | **six symbols** | delta | ending equity | min / max | receipts |
|---|---|---|---|---|---|---|
| 08.01 → 08.08 | +1.630% | **+1.803%** | +0.17 pp | 10,180.32 | 9,995.98 / 10,230.13 | 247 |
| 08.08 → 08.15 | +7.276% | **+9.609%** | **+2.33 pp** | 10,960.92 | 9,988.92 / 11,171.36 | 413 |
| 09.01 → 09.08 | +5.681% | **+2.616%** | **−3.07 pp** | 10,261.59 | 9,827.24 / 10,437.90 | 440 |
| 09.15 → 09.22 | +7.444% | **+6.293%** | −1.15 pp | 10,629.33 | 9,896.22 / 10,647.03 | 411 |
| 10.06 → 10.13 | +4.692% | **+3.377%** | −1.32 pp | 10,337.66 | 9,924.53 / 10,343.31 | 438 |

**Arm statistics.** Six symbols: mean **+4.740%**, sd **3.21 pp**, t **3.31**, 5 of 5 positive, worst **+1.803%**,
best **+9.609%**. Eight symbols on the same windows: mean **+5.345%**, sd **2.37 pp**, t **5.04**, worst **+1.630%**,
best **+7.444%**. Paired deltas: mean **−0.605 pp**, sd **2.01 pp**, t **0.67**, **2 of 5 positive**.

**Conclusion — rejected, nothing shipped, the eight-symbol universe stands.** Removing two rows that lose 383 USD
across the set *lowered* the mean by 0.61 pp and *raised* the standard deviation by 0.84 pp (2.37 → 3.21), which is the
opposite of what the per-symbol sums predict. The mechanism is the one Batch 297 already described, running in reverse:
the budget is not additive. With `Step` and `Jump 25` present, `08.01` took 114 `Crash 1000` closes; without them it
took **94** and moved the difference into `Jump 75` (108 → 125). The two "bleeders" were 30–60 closes of small,
low-correlation noise that kept the book from over-concentrating in the same synthetic index, and the windows where
`Crash 1000` has a bad week (09.01: +2.616% vs +5.681%) are exactly the ones where that ballast was doing work.
A row can be negative in dollars and still positive in portfolio terms; the only measurement that can tell the
difference is a paired distribution, which is why this arm was run instead of argued.

**Hazard paid for in this batch — a partial run that looks like a finished one.** w3's first launch was interrupted by
the device dropping offline and the broker link failing at 16:21:50; the terminal logged
`last test passed with result "some error after pass finished"` and exited cleanly. The snapshot held 13,406
heartbeats ending `2026.09.02 13:56` — 38 simulated hours of a 168-hour window — and a naive "last 10,080 heartbeats"
read returned **−5.303%** on a base inherited from the previous run. The window was rerun cold and gave +2.616%.
Rule added: a window is valid only when the terminal log says `successfully finished` **and** the journal slice holds
exactly 10,080 samples that begin at the ini's `FromDate`.

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

**Historical deviation in this batch's binary:** chart-symbol reinjection added 2-4 `Volatility 75` closes, so the universe acted as a priority list. The input and reinjection path have since been removed; the new source still needs a cold run proving an excluded chart symbol cannot trade.

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


