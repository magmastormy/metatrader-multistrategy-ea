# AXIOM EA — Silent / No-Signal Bug Hunt
## Log Analysis Report + Agent Prompt + Debugging Workflow
> **EA:** MultiStrategyAutonomousEA v2.0  
> **Log date:** 2026-04-07  
> **Symbol:** EURCHF.0 (chart) | Multi-symbol: Step Index, Jump 10, EURUSD, EURCHF, Jump 75  
> **Timeframe:** M30  
> **Issue:** EA loads, draws on chart, initialises all strategies, but produces zero signals, zero scans, zero trades for the entire session.

---

## PART 1 — WHAT THE LOG ACTUALLY SHOWS

### Timeline
| Time | Event |
|---|---|
| 22:27:59 | EA starts, all systems initialize |
| 22:28:03 | `INITIALIZATION COMPLETE — EA IS READY` |
| 22:28:03 | First tick received, system confirmed healthy |
| 22:28:47 | Call #50 — timer firing, no scans |
| 22:29:02 | First heartbeat: `scans=0, signals=0` |
| 22:29:02 | `no_new_bar=215, cadence_hold=46` |
| 22:44:06 | Call #2750 — still no scans |
| 22:44:06 | `no_new_bar=4635, cadence_hold=1824` |
| 22:45:46 | **User removes EA from chart** |
| 22:45:51 | `Abnormal termination` |

The EA ran for exactly **17 minutes and 47 seconds**. It was removed manually.

---

## PART 2 — THE ACTUAL ROOT CAUSE

**The EA is not broken. It is working exactly as configured. The configuration is the problem.**

### Root Cause #1 — CRITICAL: `newbar_only=true` on M30

```
[CADENCE-CONFIG] hybrid=true | newbar_only=true | effective_intrabar=false | 
intrabar_budget=0 | chart_only=false

[CADENCE-WARNING] newbar_only=true disables timed intrabar scans even when 
intrabar strategy policies are LIVE.
```

`newbar_only=true` means the EA **only runs strategy scans when a new M30 bar opens.**  
M30 bars open every **30 minutes**.  
The EA ran for **17 minutes** and was removed before a single M30 bar opened.

**Result:** `no_new_bar` counter hit **4,935** by the time the user removed it. Not one scan ever fired. Not one strategy was ever asked for a signal. This is 100% expected behaviour under this config.

---

### Root Cause #2 — COMPOUNDING: Three layers of intrabar blocking contradict the strategy LIVE policies

The EA simultaneously shows:

```
[EnterpriseStrategyManager] Intrabar policy updated: Trend => LIVE
[EnterpriseStrategyManager] Intrabar policy updated: Fibonacci => LIVE
[EnterpriseStrategyManager] Intrabar policy updated: Elliott Wave => LIVE
... (all 6 strategies set to LIVE intrabar)
```

But all three of these contradict those LIVE policies:

| Blocking layer | Log evidence | Effect |
|---|---|---|
| `newbar_only=true` | `effective_intrabar=false` | Timed intrabar scans disabled entirely |
| `intrabar_budget=0` | `SCAN-BUDGET: intrabar_budget=0` | Zero symbols allocated for intrabar scanning |
| `intrabar_conf_cap=0.05` | `ENTERPRISE-CONFIG: intrabar_conf_cap=0.05` | Intrabar signals capped at 5% confidence — below the pipeline minimum of 40% |

Even if you disabled `newbar_only`, intrabar signals would be capped at 5% confidence and fail the `pipeline_min_conf=0.40` threshold. They could never produce a trade.

**The LIVE intrabar policies are effectively dead letters.** Three separate configuration values each independently prevent intrabar from functioning.

---

### Root Cause #3 — SECONDARY: The validator confluence requirement may be too tight

```
[SIGNAL-VALIDATOR] NewBar(conf>=0.50 confluence>=2 quality>=0.68)
```

For a new-bar signal to pass validation, it needs:
- Confidence ≥ 50%
- At least **2 strategies agreeing** (confluence ≥ 2)
- Signal quality ≥ 68%

On M30 with 6 strategies running, confluence=2 is reasonable. But combined with `quorum_threshold=0.55` and `min_live_voters=1`, the system needs both quorum AND validator to pass. The validator is the stricter gate.

This won't cause total silence (that's Root Cause #1), but it may suppress valid signals once the bar issue is fixed.

---

### What is NOT wrong

- ✅ All 6 strategies initialized successfully on all 5 symbols (30 total)
- ✅ Risk manager, position sizer, portfolio risk all initialized
- ✅ No indicator handle failures
- ✅ No compile errors, no MQL5 runtime errors
- ✅ Cooldown is not blocking (`989358s elapsed vs 120s threshold` — long past)
- ✅ `emergency=false`, `conservative=false`
- ✅ Account has sufficient margin (all 5 symbols show `affordable=true`)
- ✅ Spread is healthy (1 point on all symbols)

---

## PART 3 — FIXES

### Fix #1 — Immediate: Change `newbar_only` setting

**In your EA inputs, find the cadence/scan settings and change:**

```
newbar_only = false          ← was: true
```

This allows the EA to scan on timer events between bars, not just at bar open.

After this change, you should see `intrabar_selected > 0` in SCAN-BUDGET logs and strategies will be polled on each timer cycle.

---

### Fix #2 — Fix the intrabar confidence cap

**In your EA inputs / EnterpriseStrategyManager config:**

```
intrabar_conf_cap = 0.45     ← was: 0.05
```

The current 5% cap means every intrabar signal is automatically below the 40% pipeline minimum. Even with `newbar_only=false`, signals would be capped at 5% and silently rejected. Change to at minimum match `pipeline_min_conf` (0.40), ideally 0.45.

---

### Fix #3 — Align the intrabar budget

**In scan budget config:**

```
intrabar_budget = 2          ← was: 0
```

With `intrabar_budget=0`, zero symbols are allocated for intrabar scanning even if scanning is enabled. Set to at least 1–2 depending on how many symbols you want active intrabar.

---

### Fix #4 — Reduce validator confluence for initial testing (optional)

If after Fix #1–3 you still get no signals, try temporarily:

```
validator_newbar_confluence = 1      ← was: 2
validator_newbar_conf = 0.45         ← was: 0.50
```

This lowers the bar for a signal to pass the final validator gate. Useful for diagnosing whether signals ARE generating but failing the gate vs. not generating at all.

---

### Configuration summary — what to change

| Input | Current value | Fix to |
|---|---|---|
| `newbar_only` | `true` | `false` |
| `intrabar_conf_cap` | `0.05` | `0.45` |
| `intrabar_budget` | `0` | `2` |
| `effective_intrabar` | `false` (auto) | will become `true` automatically |

---

## PART 4 — AGENT BUG HUNT PROMPT

> Copy this prompt verbatim and give it to any AI coding agent (Cursor, Windsurf, GPT, Copilot, etc.) along with your EA source files. The prompt is written to work even with lower-capability models.

---

```
=== AXIOM EA SILENT-MODE BUG HUNT — AGENT TASK ===

You are a senior MQL5 code reviewer. The EA I am giving you initializes successfully, 
draws on the chart, and logs heartbeats — but NEVER generates a signal or opens a trade. 
Your job is to find every place in the code that could cause this silent failure.

DO NOT rewrite or refactor anything. DO NOT suggest architecture changes.
Your ONLY job is: find bugs, describe exactly what is wrong, and provide the one-line fix.

Work through each section below IN ORDER. Do not skip sections.

---

SECTION 1: SCAN CADENCE GATE
Look in the main EA file (*.mq5) and the scan/cadence management code for:

1a. Find the variable or input called `newbar_only` (or similar: `OnlyNewBar`, `newBarMode`, 
    `scanOnNewBarOnly`). What is its default value? 
    → If it is `true`, this means the EA will ONLY scan on bar open events. 
    On M30, that is once every 30 minutes. If the user attaches the EA mid-bar, nothing 
    happens until the next bar. THIS IS LIKELY THE PRIMARY CAUSE.

1b. Find `intrabar_budget` or `m_intrabarBudget`. What is its value?
    → If it is 0, intrabar scanning is disabled regardless of strategy LIVE policies.

1c. Find `intrabar_conf_cap` or `m_intrabarConfCap`. What is its value?
    → If it is below the pipeline minimum confidence (look for `minConfidence` or 
    `pipeline_min_conf`), intrabar signals can never pass the confidence gate.

Report each finding as: [FOUND] File: X | Variable: Y | Value: Z | Problem: <explain>

---

SECTION 2: CONFIDENCE CHAIN
The EA has multiple confidence thresholds. A signal must pass ALL of them in sequence.
Find and list every threshold in this chain:

2a. Strategy `GetSignal()` minimum — find `m_minConfidence` or `MIN_CONFIDENCE` in each 
    strategy file. List each strategy and its minimum.

2b. Pipeline minimum — find `minConfidence` in `UnifiedSignalPipeline.mqh` or wherever 
    `PrepareContext` or `FilterSignal` is called. What is it?

2c. Quorum threshold — find `quorum_threshold` or `m_quorumThreshold` in 
    `EnterpriseStrategyManager.mqh`. What is it? How many strategies need to agree?

2d. Validator minimum — find `validator_newbar_conf` and `validator_newbar_confluence`. 
    What values are they? 

Now check: is there any threshold that is set HIGHER than what any strategy can realistically 
produce? If `validator_newbar_conf = 0.80` but all strategies cap at `0.70`, nothing ever passes.

---

SECTION 3: NEW BAR DETECTION
Find the function that detects a new bar (usually checks if `iTime(symbol, tf, 0) != lastBarTime`).

3a. Is the `lastBarTime` properly initialized? What value is it set to at startup?
    → A common bug: `lastBarTime` is initialized to `TimeCurrent()`. If the EA starts 
    exactly at bar open, `iTime == TimeCurrent()` and the FIRST bar is silently skipped.
    The fix: initialize to 0 so the first bar always triggers.

3b. Is new bar detection per-symbol or global?
    → If it's global (one variable for all 5 symbols), only one symbol gets scanned per bar.
    The other 4 are silently skipped.

3c. Is `OnNewBar()` actually being called from `OnTick()` or `OnTimer()`?
    → Find the call chain. If `OnNewBar()` is only called from `OnTick()` and 
    `newbar_only=true` skips `OnTick()` body, strategies never get asked.

---

SECTION 4: STRATEGY ENABLE CHECK
Each strategy has an `IsEnabled()` or `m_is_enabled` flag.

4a. In each strategy file, find what sets `m_is_enabled = true`. Is it set in `Init()`? 
    Or does it require a separate `Enable()` call after Init?
    → If it requires a separate call and that call is missing or conditional, 
    the strategy silently returns TRADE_SIGNAL_NONE without logging.

4b. Find the `GetSignal()` method in each strategy. Does it check `IsEnabled()` first?
    → If yes, what happens when disabled? Does it log? Does it return 0?
    → A strategy returning TRADE_SIGNAL_NONE because it's disabled looks identical 
    to a strategy returning NONE because it found no setup.

---

SECTION 5: PIPELINE CONTEXT PREPARATION
In `UnifiedSignalPipeline.mqh`, find `PrepareContext()` or `Update()`.

5a. Does `PrepareContext` return `false` under any condition that is NOT logged?
    → If it silently returns false (no Print/Log), the entire pipeline is skipped 
    and no signal is ever requested from any strategy.

5b. Find the engines (TrendEngine, RegimeEngine, VolatilityEngine, StructureEngine, 
    LiquidityEngine). Does each engine return a success/failure from its `Update()` method?
    → If any engine returns `false` and the pipeline treats that as a hard veto 
    without logging WHY, you will see zero signals with no explanation.

5c. Find `readinessClass` or `m_readinessScore`. Is there a minimum readiness score 
    below which the pipeline refuses to generate signals?
    → Check if the engines are in WARMUP state (they need a minimum number of bars 
    to be calculated). On a fresh attach to a new symbol, Bollinger Bands need 20+ bars,
    EMAs need 200+ bars. If the symbol doesn't have enough history, engines stay WARMUP
    and the pipeline stays silent.

---

SECTION 6: STRATEGY REGISTRATION IN ENTERPRISE MANAGER
In `EnterpriseStrategyManager.mqh`, find where strategies are registered and stored.

6a. How are strategies stored — in a fixed array, a dynamic array, or a pointer list?
    → If stored by value (not pointer), `GetSignal()` is called on a COPY, not the 
    original strategy object. Any state the strategy updates internally (cooldowns, 
    last bar time, etc.) is immediately discarded after the call.

6b. Find where `GetSignal()` is called on each strategy. Is it called on 
    `m_strategies[i].GetSignal()` or `m_strategies[i].strategy.GetSignal()`?
    → If the StrategyEntry struct has an `IStrategy* strategy` pointer but the code 
    calls the wrong field, signals are silently lost.

6c. After `GetSignal()` returns, is the result stored AND is a non-NONE signal 
    actually passed to the quorum/voting system?
    → Find where `bestResult` or the winning signal is accumulated. Is there a check 
    that resets the result to NONE somewhere before quorum completes?

---

SECTION 7: ONLINE CHECKLIST — THINGS TO VERIFY IN LOGS
After making any code change, check the logs for these specific strings.
If any are missing after running for at least 2 full bars, the corresponding 
subsystem is broken:

□ `[REGIME-STATE] HEALTHY` — RegimeEngine is running
□ `[VOLATILITY-STATE]` — VolatilityEngine is updating  
□ `[TREND v2.0]` after init — strategy OnNewBar was called
□ `[ENTERPRISE-STATUS] scans=N` where N > 0 — at least one scan completed
□ `[HEARTBEAT] scans=N` where N > 0 — scans happening
□ `[CONSENSUS-SNAPSHOT] generated=N` where N > 0 — strategy signals were collected
□ `[QUIET-REASONS] no_new_bar=0` — new bars ARE being detected

If you see `no_new_bar` counting up indefinitely (215 → 440 → 740 → ...) and it never 
resets to 0, the new bar detection is broken or `newbar_only=true` and no bar has opened yet.

---

REPORT FORMAT
For every issue you find, report it like this:

ISSUE #N
  File:     <filename.mqh>
  Line:     <line number if you can find it>
  Variable: <variable or function name>
  Current:  <current value or logic>
  Problem:  <exactly what this causes>
  Fix:      <exact one-line change>
  Severity: CRITICAL / HIGH / MEDIUM / LOW

Only report issues that directly cause the silence bug (no signals, no trades).
Do NOT report style issues, naming conventions, or performance suggestions.
=== END OF PROMPT ===
```

---

## PART 5 — STEP-BY-STEP DEBUGGING WORKFLOW

Use this workflow yourself or give it to someone helping you debug. Work top to bottom. Stop at the first fix that resolves the issue.

---

### STEP 1 — Confirm new bar detection is the cause *(5 minutes)*

Attach the EA. Watch the `[QUIET-REASONS]` heartbeat line:

```
[QUIET-REASONS] no_new_bar=XXX | cadence_hold=YYY
```

- If `no_new_bar` is counting up: **the EA is waiting for a new bar. This is Root Cause #1.**
- If `no_new_bar=0` but `no_signal` is counting up: strategies are being asked but returning nothing. Skip to Step 3.
- If `no_signal=0` but `validator_reject` is counting up: signals ARE generating but failing validation. Skip to Step 4.

---

### STEP 2 — Fix the cadence config *(2 minutes)*

In EA inputs, find and change these three settings:

```
newbar_only      → false
intrabar_budget  → 2   (or higher, one per symbol pair you want active)
intrabar_conf_cap → 0.45
```

Reattach the EA. Watch the next heartbeat. You should now see `scans > 0`.

If `scans > 0` after the fix: you're done with Step 2. Check if trades start occurring.  
If `scans > 0` but `signals_generated=0`: go to Step 3.

---

### STEP 3 — Diagnose zero signal generation *(10 minutes)*

If scans are happening (`scans > 0`) but `signals_generated=0`, the strategies are being polled but all returning TRADE_SIGNAL_NONE.

**3a. Add a temporary diagnostic Print to each strategy's `GetSignal()` at the very top:**
```mql5
PrintFormat("[DEBUG-%s] GetSignal called | enabled=%s | initialized=%s",
            GetName(), IsEnabled() ? "Y" : "N", m_is_initialized ? "Y" : "N");
```

Reattach and check if this line prints. If it doesn't: the strategy is registered but never being called. The issue is in `EnterpriseStrategyManager` — the strategy pointer is NULL or the loop is broken.

**3b. If it prints but always returns NONE:**  
Add a Print right before each `return TRADE_SIGNAL_NONE` in the strategy with a reason tag:
```mql5
Print("[DEBUG-TREND] Returning NONE: reason=ADX_FILTERED");
```

This shows you exactly which filter is catching every signal.

---

### STEP 4 — Diagnose signal pipeline rejection *(10 minutes)*

If `signals_generated > 0` but `signals_after_pipeline=0`, the pipeline is killing every signal.

Look for `[PIPELINE-VETO]` or `[REGIME-GATE]` log lines. If none appear, add a Print to `UnifiedSignalPipeline::FilterSignal()` or wherever the pipeline decides to reject:

```mql5
PrintFormat("[PIPELINE-DEBUG] Signal rejected | reason=%s | confidence=%.2f | 
             trend_ready=%s | regime=%s | readiness=%.2f",
             vetoCode, confidence, 
             m_trendReady ? "Y" : "N",
             EnumToString(m_regimeState),
             m_readinessScore);
```

Common pipeline killers:
- `REGIME_CHAOS` state (spread spike or high volatility)
- `readinessClass=WARMUP` (engine hasn't had enough bars yet — wait or reduce warm-up periods)
- `spreadToAtrRatio > 0.25` (spread too wide relative to ATR — real on synthetics like Jump indices)

---

### STEP 5 — Diagnose quorum failure *(10 minutes)*

If `signals_after_pipeline > 0` but `signals_after_quorum=0`, the voting system is blocking.

Check `[CONSENSUS-SNAPSHOT]`:
```
quorum_failed=N
```

If `quorum_failed > 0`, strategies are voting but not reaching quorum. This means fewer than `min_live_voters` strategies agree, or the `quorum_threshold` is not met.

**Temporary fix to confirm:**
```
quorum_threshold = 0.40    ← reduce from 0.55
min_live_voters = 1        ← keep at 1
```

If signals start passing quorum: your normal settings are too strict for your current strategy mix. Either lower the threshold permanently or enable more strategies to vote.

---

### STEP 6 — Diagnose validator rejection *(5 minutes)*

If `signals_after_quorum > 0` but `signals_validated=0`, the final signal validator is blocking.

Check for `[SIGNAL-VALIDATOR]` reject logs. The validator checks:
- `conf >= 0.50` (confidence floor)
- `confluence >= 2` (at least 2 strategies agreed)
- `quality >= 0.68` (signal quality score)

**Temporary test — reduce all three:**
```
validator_newbar_conf = 0.40
validator_newbar_confluence = 1
validator_newbar_quality = 0.50
```

If trades start: your signal quality is lower than expected. Either tune your strategies to produce higher-quality signals, or accept the lower thresholds.

---

### STEP 7 — Diagnose risk rejection *(5 minutes)*

If `signals_validated > 0` but `risk_approved=0`, the risk layer is blocking.

Check `[RISK-UNIFIED]` and `[VALIDATION-GATE]` logs. Look for:
- Daily loss limit hit
- Portfolio risk ceiling hit  
- Symbol correlation block
- Missing stop loss

The risk layer will almost always log its veto reason. Read the exact message.

---

### STEP 8 — Confirm with clean run *(30+ minutes)*

After any fix, let the EA run for at least **3 full M30 bars** (90 minutes) before concluding it's not working. The EA is designed to be selective. Even with everything working, M30 + 6 filters is conservative — you may see 1–3 signals per day per symbol, not constant activity.

A healthy running EA should show in logs:
```
[HEARTBEAT] scans=5 | no_signal=3 | validator_reject=1 | trades_opened=1
```
That's normal. `scans > 0` is the baseline requirement.

---

## SUMMARY

| # | Issue | Fix | Impact |
|---|---|---|---|
| 1 | `newbar_only=true` on M30 = 30-min wait per scan | Set `newbar_only=false` | **Unblocks all scanning** |
| 2 | `intrabar_budget=0` | Set `intrabar_budget=2` | Enables intrabar scanning |
| 3 | `intrabar_conf_cap=0.05` below pipeline min 0.40 | Set `intrabar_conf_cap=0.45` | Intrabar signals can actually pass |
| 4 | LIVE intrabar policies on all strategies contradict all 3 above | Fix 1–3 first | Consistency |
| 5 | Validator `confluence=2` requires 2+ agreeing strategies | Reduce to 1 for testing | May be too strict |

**The EA is not broken. It is over-configured for caution. Three independent intrabar blocks + newbar_only mode created a situation where the EA correctly does nothing.**

---

*AXIOM Engineering Studio — Bug Hunt Report*
