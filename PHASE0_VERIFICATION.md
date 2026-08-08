# Phase 0 Verification — INIT-01 + INIT-07 (make the EA start)

**Date:** 2026-08-06 (re-verified continuation session)
**Status:** ✅ Applied + clean compile confirmed (0 errors, 0 warnings, both EAs)
**File:** `Core/Orchestration/EAOrchestrator.mqh`

---

## What changed

### INIT-01 — strategy registry allocated before first consumer
- **Root cause:** `CEAOrchestrator::Initialize()` called `BuildStrategyRegistry()` (which does
  `m_registryAggregator.GetStrategyRegistry()` → NULL → bare `return false`) ~70 lines *before*
  the only allocator `m_registryAggregator.Initialize()` ran (was inside `InitializeComponents()`,
  reached at `:777`). The EA never completed `OnInit`.
- **Fix:** moved the allocator to the **top** of `Initialize()`.
  - Insert at `EAOrchestrator.mqh:685-689`:
    ```cpp
    // INIT-01 FIX: allocate the strategy registry BEFORE any consumer.
    if(!m_registryAggregator.Initialize())
    {
        Print("[CRITICAL] RegistryAggregator initialization FAILED");
        return false;
    }
    ```
  - Removed the now-duplicate allocator block that was inside `InitializeComponents()`.
- **Why a NULL-guard inside `BuildStrategyRegistry` is wrong:** it would produce a *silent empty-registry*
  init — worse than the loud failure. The allocator must exist first.

### INIT-07 — bridges allocated exactly once
- **Root cause:** `m_pythonBridge` / `m_dashboardBridge` were allocated at two sites:
  Site A in `Initialize()` (`:716/:727`), and Site B in `InitializeAISubsystems()`
  (`:1172/:1183`). `InitializeAISubsystems()` early-returns when `enableAIMode` is off
  (`:4406`), so Site B is skipped in AI-off configs — but the naive "remove Site A" reading is
  **inverted**: the correct fix removes Site B and keeps Site A so AI-off configs still get bridges.
- **Fix:** removed the Site B block (AI-gated duplicate). All bridge allocation now lives in
  `Initialize()` (Site A) only.

---

## Verification evidence (re-checked this session)

Grep counts on the live file (authoritative — MQL5 has no unused-symbol diagnostic, so call counts matter):

| Signature | Occurrences | Lines |
|-----------|-------------|-------|
| `m_registryAggregator.Initialize()` | **1** | `:688` |
| `new CPythonBridge()` | **1** | `:725` |
| `new CDashboardBridge()` | **1** | `:736` |
| `m_dashboardBridge.SetEnabled(...)` | **1** | `:744` |
| `INIT-01 FIX` marker | present | `:685` |

Direct MetaEditor compile (bypassing the `sync_and_compile.ps1` Start-Process PATH bug):
- `compile_MultiStrategyAutonomousEA.log` → **`Result: 0 errors, 0 warnings`**
- `compile_MultiStrategyTestingEA.log` → **`Result: 0 errors, 0 warnings`**

Both EAs compiled cleanly; the synced+compiled terminal copy
(`AppData\Roaming\MetaQuotes\Terminal\...\MQL5\Experts\MultiStrategyAutonomousEA\`) carries the fix.

---

## What to look for in the FRESH logs (user to supply)

- **Primary signal:** `[CONSENSUS-QUORUM]` at `EAOrchestrator.mqh:3229` — reports
  `effectiveMinVoters` directly. Zero-cost proof that the consensus stage is now reachable.
- **NOT a valid signal:** `[HEARTBEAT]` — that probe is a dead orphan and proves nothing.
- Expect `OnInit` to complete for the first time; the 13 ungated `[CONSENSUS-*]` probes
  (`:3229`–`:3484`) will now fire and give visibility into the consensus stage.

---

## Deferred (kept out to keep the init signal clean)
- `INIT-02`, `PERF-01`, `PERF-03`, `BLOAT-03` — intentionally NOT touched this commit.

## Next scheduled phases (after fresh logs confirm init)
1. `EXEC-01` (NULL deref in execution) — **must precede** `PROFIT-01`.
2. Consensus gates shipped together: `PROFIT-09` (`:3374`) → `PROFIT-01` (`:3425`) →
   `PROFIT-11` → `PROFIT-02`. Never `PROFIT-01` alone — `PROFIT-09` fires first and
   short-circuits.

## Cleanup note
- `Core/Orchestration/EAOrchestrator.mqh.bak` backup remains as a safety net; remove after the
  user confirms the fix is good (per AGENTS.md: keep artifacts only when needed).

---

## Fresh log analysis — Tester run `20260806.log` (2026-08-06, 10:29–10:35)

**Source:** `20260806.log` (UTF-16LE, 8124 lines, ~2.5 MB), from `MultiStrategyTestingEA`
("Crash 1000 Index,H1"). User ran the **Tester**, not the main EA.

### ✅ Phase 0 CONFIRMED at runtime
- `OnInit` completed fully — no `[CRITICAL]`, no NULL deref, no `error`, no exception.
- Symbols: 12 accepted (BTCUSD rejected for spread > 15000), risk managers / family-weight
  matrix / session-weight mgr / signal pipelines all initialized, 12 `Momentum` strategies
  registered, indicator handles created.
- Ran stably ~6 min (10:29:08 → 10:35:54); signal-generation perf metrics flow every tick
  (`GenerateSignals_us`, `OnTick_Total_us`, …).
- Deinitialized cleanly (`DEINIT-COMPLETE`, reason=1 = EA removed from chart).

### ⚠️ Trading / consensus path NOT exercised by the Tester
- All 12 strategies registered `Enabled: false` (0 enabled). Zero trades (every engine deinit
  counter = 0: SPIKE-HUNT, GRID-RECOVERY, ATR-SCALP, NN-DIAG all 0).
- No `consensus` / `quorum` / `vote` anywhere; the 13 `[CONSENSUS-*]` probes (`:3229`–`:3484`)
  never fired. `[HEARTBEAT]` correctly absent.
- **Consequence:** `EXEC-01` and `PROFIT-09/01/11/02` are **NOT validated** by this run — that
  code was never reached (no crash, no execution).

### Secondary findings (real, non-blocking)
1. **Dashboard bridge now live (confirms INIT-07):** `[DASHBOARD-BRIDGE] shutting down
   (pushes=403 ok=0 err=403)` — bridge exists post-fix and pushes, but gets 403 (endpoint
   unreachable in this env). Separate config/network issue, not a code bug.
2. **`[DERIV-PROFILER] … DERIV_UNKNOWN`** for EURUSD/GBPUSD/USDJPY/AUDUSD/XAUUSD — forex
   classification gap; minor impact on correlation/risk clustering. Low priority.
3. **Memory leak at deinit:** `12 undeleted dynamic objects of class 'CStrategyHealthMonitor'`
   (3072 bytes); `IndicatorManager` warning "48 active handles". Cleanup/BLOAT-class defect,
   non-growing within a session. Defer with BLOAT-03.

### ➡️ To proceed with the roadmap
Run the **main EA `MultiStrategyAutonomousEA`** with strategies enabled and return those logs.
Only then does the consensus → execution path run and surface `EXEC-01` / `PROFIT-0x`. The Tester
is a profiling harness and does not trade, so it cannot validate the next phases.
