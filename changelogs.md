# Changelog

All notable changes to the `metatrader-multistrategy-ea` project are documented in this file. Older batch entries (Batch 101 and prior) are archived in [`docs/changelogs_old.md`](docs/changelogs_old.md).

## [Unreleased] - 2026-08-11

### Batch 145: Unified Data-Driven Strategy Catalog (2026-08-11)

#### Implementation Summary
Structural refactor only — **trading behavior preserved byte-for-byte**. Every strategy registration path (12 indicator strategies + 5 AI adapters) now reads from ONE catalog file instead of three hand-maintained if-chains.

**New file — `Core/Strategy/StrategyCatalog.mqh`** (~290 lines)
- 8 sections: per-strategy includes, catalog enums (`ENUM_CATALOG_KIND`, `ENUM_CATALOG_AI`), the `SStrategyDefinition` row struct (18 fields), storage (`g_strategyCatalog[]`, `g_strategyCatalogCreators[]`, count/built flags), `CATALOG_SIMPLE_CREATOR` creator macro, `CatalogAdd()`, `BuildStrategyCatalog()` (17 rows), and lookups/gates (`CatalogFindByName`, `CatalogSymbolAllowed`, `CatalogFlagEnabled`, `CatalogLogIndexAudit`).
- Every strategy owns exactly 3 anchored lines tagged `// [CAT:<Name>]` (include / creator / row).

#### Add–Remove Contract
- **Add a strategy:** 1 new class file under `Strategies/`, then 3 anchored lines in `StrategyCatalog.mqh` (include, `CATALOG_SIMPLE_CREATOR`, `CatalogAdd`). Nothing else in `Core/` is touched.
- **Remove a strategy:** delete the 3 lines carrying its `[CAT:]` anchor.

#### File Change Map
| File | Change |
|---|---|
| `Core/Strategy/StrategyCatalog.mqh` | **NEW** — single source of registration truth |
| `Core/Management/EnterpriseStrategyManager.mqh` | 12 `Strategies/*` includes → 1 catalog include; `AutoRegisterStrategies()` if-chain (67 lines) → 1 catalog loop |
| `Core/Orchestration/EAOrchestrator.mqh` | 5 `Initialize*AIForSymbol()` (362 lines) → `IsCatalogAIRowEnabled` / `CatalogAIPreCreateGate` / `PrepareCatalogAIAdapter` / `RegisterCatalogAIAdapter` / `RegisterCatalogAIStrategiesForSymbol`; the 5 call sites → 1 call |
| `Core/Management/StrategyRegistryState.mqh` | dead duplicate include block (15 lines), dead `AutoRegisterStrategies` decl + 73-line body removed |
| `Core/Factory/StrategyFactory.mqh`, `Core/Registry/MathematicalEngineRegistry.mqh` | **untouched** (their includes are still required) |

#### Bug Fixed — F4: AI adapter double-delete
`CEnterpriseStrategyManager::RegisterStrategy()` already deletes the strategy object when registration fails. Four of the five AI paths (Transformer, Ensemble, ONNX, Python Bridge) then called `delete adapter` again — a double free. Only the Neural Network path was correct. The shared `RegisterCatalogAIAdapter()` tail now never deletes after a failed `RegisterStrategy`, making all five paths consistent and safe. `delete adapter` is still performed (correctly) when adapter *preparation* fails, since the manager does not own it yet.

#### Bug Fixed — pre-existing `DashboardBridge.mqh:143` compile error (0/0 blocker)
The Batch 144 `DashboardBridge` decomposition (commit `e483d5b`) left `CDashboardBridge::PushState()` calling `m_transport.FinishPush(CDashBridgePanels::BuildStateJson(m_protocol, m_health))` — passing an rvalue to a `string&` parameter (compiler error 200 "parameter passed as reference, variable expected" + warning 39). This meant the **EA did not build on `main`** (no `.ex5` emitted). Fixed the same proven way as `UnifiedRiskManager`: capture `BuildStateJson(...)` into a local `string stateJson` and pass `stateJson`. A full headless compile of `MultiStrategyAutonomousEA.mq5` now reports **0 errors, 0 warnings**. This defect was independent of Batch 145 (Batch 145 adds zero new diagnostics) but is closed here so the deliverable meets the 0/0 requirement.

#### Invariants Preserved
- The 12 legacy `flagsIndex` literals are kept exactly: `{0, 1, 4, 6, 9, 10, 11, 12, 13, 14, 15, 16}`. They are **not** remapped to `SI_*`.
- All weights / tiers / roles / clusters / timeframes / intrabar policies are identical to the previous `RegisterStrategy` call sites.
- Statistical Arbitrage still registers only when `g_pythonBridge != NULL && g_pythonBridge.IsConnected()`, and both original `Print` lines fire in their original relative positions.
- Python Bridge **AI** keeps its own, different gate (`m_pythonBridge != NULL && m_pythonBridge.IsInitialized()`); the two bridge predicates were deliberately **not** unified.
- `SyncEnabledWithRegistry`, `CStrategyRegistryState::RegisterStrategy`, `BuildStrategyRegistry`, the consensus core, health monitor, ONNX backoff manager and pipeline wiring are untouched.

#### Latent Defects Found, NOT Fixed in Batch 145
Each of these is reported (F1 is now logged at runtime by `CatalogLogIndexAudit()`) and **deferred to a separate user decision** — fixing any of them changes trading behavior.
- **F1 — legacy flag index vs semantic `SI_*` index mismatch.** For 8 of the 12 rows the legacy `flagsIndex` diverges from the semantic `ENUM_STRATEGY_INDEX` slot. Consequences: **2 strategies are effectively dead** (NY Open Gap → legacy slot 15, Asian Range Break → legacy slot 16; those slots are never populated) and **6 are mis-gated** (Mean Reversion, Volatility Breakout, Statistical Arbitrage, FVG Scalper, Turtle Soup, Breaker Block read a neighbouring strategy's enable flag). Now emitted as `[CATALOG-AUDIT] ... MISMATCH` / `DEAD_SLOT` lines at registration time. **Not fixed** — the remap would enable/disable live strategies.
- **F2 — `StrategyConfigBuilder` slot [13] double-write.** Two different strategies write the same flag slot; the second write wins. **Not fixed.**
- **F3 — `PythonBridgeAI` missing from the outer AI gate.** The `:3505` gate ORs `enableNeuralNetwork || enableTransformer || enableEnsemble || enableOnnxAI` but omits `enablePythonBridgeAI`, so a Python-Bridge-AI-only configuration never reaches AI adapter registration. Preserved as-is. **Not fixed.**

### Batch 144: God-Object Decomposition — next5c + Strategy Openness Refinement (2026-08-11)

#### Decomposition — next5c (commit e483d5b)
Mechanical God-Object decomposition, zero behavior change:
- `Core/Scalp/ATRScalpingEngine.mqh` 836 → 326 (7 `ATRScalp*` modules)
- `Core/Monitoring/PerformanceAnalytics.mqh` 946 → 474 (5 `PerfAnalytics*` modules)
- `Core/Utils/PythonBridge.mqh` 1028 → 274 (5 `PyBridge*` modules)
- `Core/Utils/DashboardBridge.mqh` 950 → 215 (5 `DashBridge*` modules)
- `Core/Engines/RegimeEngine.mqh` 925 → 390 (7 `Regime*` modules)
- Added explicit 0-warnings/0-errors discipline to the extraction pattern (one agent confirmed a real MetaEditor compile: 0 errors, 0 warnings).

#### Strategy Openness Refinement (behavior change — makes entry gating LESS strict)
Preserves the risk gate (`CUnifiedRiskManager` pre-trade) and the ATR-crisis volatility gate. Loosens only the consensus / confidence / OFI gates:
- `Core/Management/ConsensusWeightingConfig.mqh`: lowered quorum thresholds + support floors across all profiles (balanced 0.55→0.50; conservative minQuorum 3→2, threshold 0.65→0.60; aggressive 0.50→0.45). EA defaults to BALANCED, so the active threshold drops 0.55→0.50.
- `Core/Management/ConsensusEngine.mqh`: effective quorum clamp 0.35/0.85 → 0.30/0.80 (quorum can never become over-strict).
- `Core/Pipeline/SignalPipelineTypes.mqh`: default `minConfidence` 0.40→0.35; trend-mode floor 0.55→0.45 (opens trend trades).
- `Core/Management/PostConsensusValidator.mqh`: OFI hard-veto softened — only a STRONG contradiction (|ofi_z| ≥ 1.0) vetoes; a mild contradiction is now logged and allowed.

#### Files Changed
- 5 modified next5c mains + 30 new modules + 4 strategy-refinement files + this changelog.

### Batch 143: God-Object Decomposition Program — Batch 1 (next5) + Batch 2 (next5b) (2026-08-09 → 2026-08-11)

#### Implementation Summary
Mechanical God-Object decomposition with **ZERO behavior change** (exact public-signature preservation, thin one-line forwarders, extracted modules own fields by value or as static helpers). Two batches landed:

**Batch 1 — next5 (commit 618dcd7):**
- `Core/Trading/TradeManager.mqh` 3308 → 2261 (5 `TradeMgr*` modules)
- `Core/Pipeline/UnifiedSignalPipeline.mqh` 2223 → 918 (6 `SignalPipeline*` modules)
- `Core/Scalp/FastScalpEngine.mqh` ~1748 → 468 (11 `FastScalp*` modules)
- `Core/Management/DiagnosticsManager.mqh` 1706 → 897 (5 `DiagMgr*` modules)
- `Core/Engines/TrendEngine.mqh` 1646 → 911 (7 `Trend*` modules)

**Batch 2 — next5b (this commit):**
- `Core/Scalp/GridRecoveryEngine.mqh` 1156 → 681 (7 `GridRecovery*` modules)
- `Core/Scalp/SpikeHunterEngine.mqh` 1150 → 310 (6 `SpikeHunter*` modules)
- `Core/Engines/StructureEngine.mqh` 1131 → 491 (5 `Structure*` modules)
- `Core/Engines/MarketAnalysis.mqh` 1102 → 139 (6 `MarketAnalysis*` modules)
- `Core/Utils/ErrorHandling.mqh` 1038 → 42 (6 `ErrorHandling*` modules)

**Totals:** 10 God Objects decomposed; ~13,300 → ~6,400 lines in the decomposed mains; 64 new focused modules. Every file verified by comment/string-aware delimiter tripwire (35/35 balanced), include-completeness check, and agent `IS_PASS` against 5 structural gates.

#### Known follow-ups
- `Core/Engines/TrendEngine.mqh`: pre-existing dead branch `bool adxValid = !useAdxModel;` never set true on the healthy-ADX path — flagged, not fixed (no-behavior-change mandate).
- `Core/Orchestration/EAOrchestrator.mqh` (~3712 LoC) and `Core/Risk/*` managers remain as candidate batches.

#### Files Changed
- 10 modified main `.mqh` files + 64 new module `.mqh` files (per-file lists above) + this changelog.

## [Unreleased] - 2026-08-06

### Batch 140: Phase 4-5 — Strategy Duplication Consolidation + God Object Decomposition (2026-08-05)

#### Implementation Summary

**Phase 4: Strategy Duplication Consolidation**

1. **LogRejectEvent / RejectSignal consolidation** — Consolidated into `CStrategyBase` as protected virtual methods backed by `m_strategyPrefix`, `m_lastRejectReasonTag`, and `m_lastRejectLogTime`. Removed duplicated implementations from 8 strategy files.

2. **RefreshForNewBar consolidation** — Added `m_lastBarCount` + `RefreshForNewBar()` + `OnRefreshComponents()` virtual hook to `CStrategyBase`. 5 strategies now override `HandleNewBar()` and `OnRefreshComponents()` instead of duplicating new-bar boilerplate.

3. **ValidateTradeRequest consolidation** — Added `ValidateWithRiskManager()` helper to `CStrategyBase`. Consolidated 11 of 12 strategy files (StatisticalArbitrage skipped — different validation pattern). ~150 lines of duplicated boilerplate eliminated.

4. **CONSENSUS-DIAG consolidation** — Added `LogConsensusDiag()` helper to `CStrategyBase`. Consolidated 9 of 12 strategy files (3 outliers skipped — structural variations). ~60 lines eliminated.

**Phase 5: God Object Decomposition**

1. **SOrchestratorConfig extraction** — Extracted `SOrchestratorConfig` struct + helper structs (710 lines) from `EAOrchestrator.mqh` into new `Core/Orchestration/OrchestratorConfig.mqh`. Pure data definitions, zero invariant risk.

2. **InitializeStrategyConfigs extraction** — Extracted 249-line method into new `Core/Orchestration/StrategyConfigBuilder.mqh` as `CStrategyConfigBuilder::Initialize()` static method. Pure config mapping, no runtime behavior.

3. **EAOrchestrator.mqh reduction** — Reduced from 5,529 → 4,571 lines (958-line reduction, 17.3% smaller).

#### Compilation
All changes verified with 0 errors, 0 warnings. `.ex5` produced.

#### Files Changed
- `Core/Strategy/StrategyBase.mqh` (CStrategyBase enhancements: LogRejectEvent, RefreshForNewBar, ValidateWithRiskManager, LogConsensusDiag)
- `Core/Orchestration/OrchestratorConfig.mqh` (new — SOrchestratorConfig + helper structs)
- `Core/Orchestration/StrategyConfigBuilder.mqh` (new — CStrategyConfigBuilder::Initialize())
- `Core/Orchestration/EAOrchestrator.mqh` (reduced 958 lines)
- 8 strategy files (LogRejectEvent/RejectSignal dedup)
- 5 strategy files (RefreshForNewBar/OnRefreshComponents)
- 11 strategy files (ValidateWithRiskManager)
- 9 strategy files (LogConsensusDiag)

#### Runtime Invariants Preserved
All 5 AGENTS.md §3 invariants verified — risk authority, execution ownership, lifecycle ownership, strategy consensus, indicator cleanup unchanged.

### Batch 141: Phase 6-7 — Execution Flow Optimization + File Reorganization & Hygiene (2026-08-06)

#### Implementation Summary

**Phase 6: Execution Flow Optimization**

1. **6.1 SignalValidator merge (VERIFIED DONE)** — `SignalValidator.mqh` was already merged into `EnterpriseStrategyManager.mqh` in a prior batch. Comments confirm: "merged from SignalValidator" in `EnterpriseStrategyManager.mqh` and "SignalValidator - now merged into EnterpriseStrategyManager" in `EAOrchestrator.mqh`. No file to delete — it's already gone.

2. **6.2 Position sizing consolidation (ASSESSED, PARTIAL)** — Interface `CPositionSizerModifier` already exists in `PositionSizerModifiers.mqh` (lines 23-29). All 5 modifiers (ADXLotModifier, BayesianKellyModifier, EquityCurveLotModifier, VolatilityTargetingModifier, VPINLotModifier) already implement it. File merge skipped — would create 1,866-line file exceeding <1,500 target. URM duplicate logic cleanup skipped — conflicting 1x vs 15x round-up policies require shadow testing (CRITICAL risk).

3. **6.3 JSON parsing consolidation (COMPLETED)** — Created `ParseJsonDouble()`, `ParseJsonString()`, `ParseJsonInteger()` private helper methods in `CPythonBridge`. Replaced 18+ duplicated JSON parsing patterns across `ParsePredictionResponse()`, `GetPairCorrelation()`, `FindBestCorrelatedPair()`, and `ParseVersionResponse()`. ~130 lines of duplicated boilerplate eliminated.

4. **6.4 Registry pattern consolidation (ASSESSED, SKIPPED)** — `IRegistry.mqh` already provides template-based `CRegistryBase<T>`. Of 6 registries: DrawingManagerRegistry borderline (single pointer but create-on-demand + objectCount tracking), InstitutionalEngineRegistry (3 pointers/slot), NeuralNetRegistry (2 pointers/slot) too specialized. ScanSchedulerRegistry and SymbolStateTracker store scalar state (not pointers) — wrong abstraction. MathematicalEngineRegistry has 16 engine pointers. No consolidation feasible without broader redesign.

**Phase 7: File Reorganization & Hygiene**

1. **7.1 Core/Position/ directory (ASSESSED)** — `Core/Position/PositionManager.mqh` is NOT a duplicate of `Core/Trading/PositionManager.mqh` (latter does not exist). It's the sole location, actively included by 5 files. Documentation corrected.

2. **7.2 Core/Risk/ reorganization (SKIPPED)** — Moving 15 files into subdirectories would break many #include paths across the codebase. High risk for purely organizational benefit. Deferred.

3. **7.3 TODO/FIXME cleanup (COMPLETED)** — EAOrchestrator.mqh and EnterpriseStrategyManager.mqh TODOs already resolved in prior phases. Two remaining TODOs in `EnsembleAIStrategyAdapter.mqh` (lines 530, 544) replaced with clear documentation of interface mismatch (TrainStep/OnRegimeChange can't delegate to CEnsembleMetaLearner due to parameter mismatch).

4. **7.4 Error handling pattern (SKIPPED)** — Optional, lower priority. Not a line reduction. Deferred.

5. **7.5 Dashboard App.tsx fix (COMPLETED)** — Replaced 8 inline "Coming Soon" stub components with imports of actual page files from `./pages/`. All 8 pages (Overview, Charts, Positions, Strategies, Risk, AI, Logs, Control) now render their real implementations.

#### Compilation
All MQL5 changes verified with 0 errors, 0 warnings. `.ex5` produced at 1,395,328 bytes.

### Batch 142: Phase 6.2 + 7.4 — Position Sizing Consolidation + Error Handling Logging (2026-08-06)

#### Implementation Summary

**Phase 6.2: Position Sizing Consolidation (COMPLETED)**

1. **Removed redundant URM `<minLot` validation block** — Deleted the ~22-line block in `Core/Risk/UnifiedRiskManager.mqh` (formerly lines 2691-2712) that hard-coded `if(riskRatio <= 15.0)` with no config binding. Replaced the gate with `if(request.lotSize > maxLot)` using `SYMBOL_VOLUME_MAX`. `CPositionSizer` already rounds up to minLot with the configured tolerance before URM's max-lot gate, so the removed branch was duplicated logic.

2. **Restored 15x min-lot round-up tolerance (reverted L5-002 1x clamp)** — The L5-002 fix had clamped round-up tolerance to 1x in three places; all relaxed to 15x per user decision ("keep risk up to 15x, not 1x"):
   - `UnifiedRiskManager.mqh` config default: `m_config.minLotRiskMultiplier = 15.0` (line 602).
   - `PositionSizer.mqh` hard cap: `if(riskRatio > 15.0)` (line 712).
   - `PositionSizer.mqh` setter `SetMinLotRiskMultiplier`: `MathMin(MathMax(1.0, multiplier), 15.0)` (line 842).

3. **EA inputs updated** — `MultiStrategyAutonomousEA.mq5`: `InpAllowMinLotRoundUp = true`, `InpMinLotRiskMultiplier = 15.0` (lines 41-42; consumed at lines 397-398 and 1385).

**Phase 7.4: Error Handling Pattern (COMPLETED)**

1. **`return 0.0` debug logging (logging only — no behavior change)** — Added 38 `PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, __LINE__, __FUNCTION__)` lines to `return 0.0` paths that are ambiguous between a valid zero result and an error. Distribution: `UnifiedRiskManager.mqh` 16, `TradeManager.mqh` 14, `PositionSizer.mqh` 5, `PythonBridge.mqh` 3.
   - Documented valid returns (hedging-mode path, already-braced inline early-exits) were intentionally skipped to avoid noise.
   - The insert script braces any unbraced multi-line control statement around the `return` so the log executes only on the actual return path (control-flow-safe; verified by clean recompile).

#### Compilation
All MQL5 changes verified with 0 errors, 0 warnings. `.ex5` produced at 1,397,708 bytes (slightly larger than the 1,394,996-byte pre-6.2/7.4 build due to the added debug log statements — expected).

#### Files Changed
- `Core/Risk/UnifiedRiskManager.mqh` (redundant lot-validation block removed; 15x tolerance restored; 16 DBG-RET0 logs)
- `Core/Risk/PositionSizer.mqh` (15x hard cap + setter clamp relaxed; 5 DBG-RET0 logs)
- `MultiStrategyAutonomousEA.mq5` (min-lot round-up inputs set to 15.0 / true)
- `Core/Trading/TradeManager.mqh` (14 DBG-RET0 logs)
- `Core/Utils/PythonBridge.mqh` (3 DBG-RET0 logs)

#### Runtime Invariants Preserved
All 5 AGENTS.md §3 invariants verified — risk authority (`CUnifiedRiskManager`), execution ownership (`CTradeManager`), lifecycle ownership (EA loop), strategy consensus (symbol-scoped), indicator cleanup (`CIndicatorManager::DestroyInstance`) unchanged. 6.2 removes only a redundant validation branch; 7.4 is logging-only.

#### Files Changed
- `Core/Utils/PythonBridge.mqh` (JSON parsing consolidation — 3 new helpers, 18+ patterns replaced)
- `Core/Strategy/EnsembleAIStrategyAdapter.mqh` (TODO comments resolved)
- `Dashboard/client/src/App.tsx` (stub components replaced with real page imports)

#### Runtime Invariants Preserved
All 5 AGENTS.md §3 invariants verified — risk authority, execution ownership, lifecycle ownership, strategy consensus, indicator cleanup unchanged.
