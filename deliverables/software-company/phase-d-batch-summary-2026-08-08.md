# Phase D — TradeManager Decomposition (T0–T3)
**Date:** 2026-08-08 · **Status:** Source complete, awaiting compile · **Compiled:** No (user compiles in MetaEditor GUI)

---

## TL;DR

`Core/Trading/TradeManager.mqh` went from **3,727 → 3,308 LoC** across four batches, six new focused modules were created, and six dead files were purged — with zero functional change and the execution hot path byte-for-byte untouched.

Plus a bonus: the two workers that died on a rate limit yesterday had actually **finished their work before the error fired**. Verified on disk rather than trusted from the failure notice.

---

## Recovered work (confirmed complete, not re-run)

| Item | Evidence |
|---|---|
| C9 consensus extraction | `EnterpriseStrategyManager.mqh` 3,390 → **2,395 LoC**; `ConsensusEngine.mqh` 1,458 LoC; braces 105/105; 0 duplicate definitions |
| 3 one-shot diagnostic probes stripped | `[CONSENSUS-ENTRY]`, `[CONSENSUS-GUARD]`, `[SIGGEN-LOOP]` → 0 hits repo-wide |

---

## Batch results

### T0 — dead-code purge
Deleted 4 orphan skeletons in `Core/Trading/` with **zero `#include` references** (707 LoC of dead code), plus 2 root artifacts.

Two were active landmines: `Core/Trading/TradeExecutor.mqh` declared a `CTradeExecutor` that **collided by name** with the live `Core/Orchestration/TradeExecutor.mqh`, and re-`#define`d four macros with no `#ifndef` guard, clashing with `TradeManager.mqh:57-60`.

```
Core/Trading/TradeExecutor.mqh          254 LoC
Core/Trading/AsyncTradeManager.mqh      108 LoC
Core/Trading/TradeStatistics.mqh        173 LoC
Core/Trading/TradeValidator.mqh         172 LoC
recovered_ConsensusEngine.mqh             1 LoC
nul                                    99 bytes
```

### T1 — stateless helpers (static methods)

| File | LoC | Contents |
|---|---|---|
| `TradeRetcodeClassifier.mqh` | 57 | `IsTransientTradeRetcode`, `IsLimitedRetryRetcode`, `IsSuccessfulFillRetcode` |
| `TradeSpreadCostModel.mqh` | 51 | `CalculateSpreadCost` |
| `TradeDescriptor.mqh` | 80 | `OrderTypeFromString`, `GetTradeErrorDescription` |

`LogSpreadCostAnalytics` was **deleted outright** — zero callers repo-wide. No point relocating dead weight into a fresh file.

### T2 — stateful telemetry (owned by value)

| File | LoC | State moved |
|---|---|---|
| `ExecutionQualityTracker.mqh` | 256 | `ExecutionQualityMetrics` + 53 touch sites |
| `TradeStatsTracker.mqh` | 115 | `TradeStats` + 16 touch sites |

The 4 legacy mirror-writes (`m_totalTrades`, `m_successfulTrades`, `m_failedTrades`, `m_lastTradeTime`) were **preserved intact** — they now read from the module rather than the removed struct.

### T3 — position state registry

| File | LoC | State moved |
|---|---|---|
| `PositionStateTracker.mqh` | 241 | `SPositionState[100]`, `m_stateCount`, and 5 methods |

---

## Scope corrections made during execution

The inherited plan contained three factual errors, each caught and corrected before it caused damage:

| Plan said | Reality |
|---|---|
| T3 = three registries (`PositionStateTracker` / `EAPositionRegistry` / `MagicNumberRegistry`) | Only one exists. `m_magicNumber` is a scalar welded to `m_trade`; the nearest "registry" is the off-limits `m_symbolTrades[]` pool. **T3 scoped down to one module.** |
| T2 includes a `SmartOrderRouter` | No such component exists in this codebase. Dropped. |
| T0 shrinks TradeManager | T0 deletes *separate* files. TradeManager first shrinks at T1. |

---

## Collision hazards caught

1. **`ExecutionQualityMetrics` was already top-level** in `TradeTypes.mqh:103`, field-identical to the nested copy. Promoting the nested one would have been a guaranteed duplicate-definition error. The tracker reuses the existing global struct.

2. **`SPositionState` collides across modules.** A *field-incompatible* 12-field struct of the same name lives at `Core/Position/PositionManager.mqh:21` — and that file `#include`s `TradeManager.mqh` **before** its own declaration. The new struct was kept **nested private** inside `CPositionStateTracker`, preserving its original scoping with zero global-namespace footprint.

3. **`nul` resisted deletion** — a Windows reserved device name. Required `[System.IO.File]::Delete` with the `\\?\` extended-length prefix.

---

## Hot path protection

Every extraction left **thin one-line forwarders** with the original signatures, so call sites inside the execution path stay textually identical. Verified by MD5-hashing the enclosing function before and after:

- `ExecuteMarketOrder` retry loop — 3 retcode call sites unchanged
- `ModifyPosition` — 5 `UpdatePositionState` call sites unchanged (MD5 `a5851ed5…` both sides)

An earlier engineer analysis argued forwarders were unnecessary dead code since all callers are internal. Technically true, but rejected: three of those callers sit in the live order-retry loop of an EA trading real money. Six lines of indirection is a cheap price for a zero-diff loop.

---

## Verification (all green)

| Check | Result |
|---|---|
| Brace balance — all 9 touched/created files | ✅ balanced |
| `m_positionStates` / `m_stateCount` / `m_execMetrics` / `m_stats` in TradeManager | ✅ all 0 |
| Duplicate `CTradeManager::` out-of-line definitions | ✅ none |
| `SPositionState` global uniqueness | ✅ 1 global + 1 nested private |
| External callers broken | ✅ none — all 6 modules' methods had zero external callers |
| Log strings / format specifiers | ✅ verbatim |
| Deleted filenames referenced anywhere | ✅ 0 real hits |

---

## Pre-existing bugs found — deliberately FROZEN

Extraction must be behavior-preserving, so none of these were touched. Each deserves its own scheduled pass.

- `CleanupPositionStates()` has **zero callers** — the 100-slot cache only self-heals lazily via `FindPositionState`.
- `UpdatePositionState` silently drops state past 100 tracked positions; `IsModificationNeeded` then returns `true` forever for the overflow.
- `ticket <= 0` compared on an unsigned `ulong`.
- `removedCount` incremented but never read.
- `SSmartOrderParams` defined twice — nested `CTradeManager` copy shadows the global in `TradeTypes.mqh:92`.
- All 6 exec-quality/stats public methods have zero callers repo-wide — dead public API kept alive by the forwarders.
- `[DBG-RET0]` prints carry stale hardcoded line numbers (1605/1613).

**Accepted cosmetic drift:** `__FILE__`/`__FUNCTION__` inside `CalculateSpreadCost` now expand to the new file/class. Unavoidable when relocating code containing those macros; affects only a `[DBG-RET0]` trace on the zero-return path.

---

## Deployment status

- Synced via `sync_and_compile.ps1 -SkipCompile` — 14 files updated.
- Stale orphan copies manually purged from the deploy target (sync copies but does not delete).
- Deploy target verified to match source.

## Next

1. **Compile in MetaEditor GUI** — this is the one compile for all four batches.
2. Run the EA and capture a log for regression sniffing.
3. **T4** (`ProtectiveStopManager`, `AsyncExecutionManager`) — the two large back-pointer-dependent modules, ~815 LoC. Deliberately held back for its own compile cycle since it's the riskiest slice.
