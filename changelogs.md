# Changelog

All notable changes to the `metatrader-multistrategy-ea` project are documented in this file.

## [Unreleased] - 2026-02-23

### Batch 17: Residual Audit Trace Hardening Execution (2026-02-23)
- **Unprotected Position Response:** Added deterministic remediation loop in `MultiStrategyAutonomousEA.mq5` that attempts SL/TP restoration on EA-owned unprotected positions, tracks bounded retry attempts, and force-closes after configured retry limit when restoration fails.
- **Risk Telemetry Split:** Extended `SUnifiedRiskSnapshot` in `Core/Risk/UnifiedRiskManager.mqh` with explicit `dailyEntryRiskUsedPercent`, `dailyMarkToMarketLossPercent`, and `openExposureRiskPercent`; heartbeat now emits `[RISK-BUDGET]` decomposition.
- **Risk Denominator Consistency:** `RiskValidationGate` per-trade risk-percent normalization now uses equity-aware denominator (`min(balance,equity)` fallback-safe) to align with portfolio-risk stress accounting.
- **Entry Pause on Unprotected State:** Runtime now pauses new entries while unprotected-position state remains active, rather than repeatedly driving expected risk rejections.
- **Execution Retry Policy Refinement:** `Core/Trading/TradeManager.mqh` now treats `LOCKED`/`FROZEN` as limited one-retry conditions (not full transient backoff class) and logs bounded failure outcomes.
- **Symbol Priority Neutralization:** Trading loop now rotates per-cycle symbol start index before scanning, reducing deterministic first-symbol concentration under one-trade-per-cycle behavior.
- **External Capacity Diagnostics:** Added `[CAPACITY-EXTERNAL]` telemetry when per-symbol cap is consumed by non-EA/manual positions.
- **Orchestrator Runtime Hygiene:** Removed duplicate deinit orchestration report emission path and hardened adaptation logging to explicitly report insufficient trade evidence when no strategy qualifies for weight updates.
- **Orchestrator Capacity:** Increased `MAX_STRATEGIES` to `256` to reduce qualified strategy registration saturation.
- **Portfolio Risk Stability (carried in this batch):** Kept equity-aware denominator (`min(balance,equity)`), conservative correlation fallback on data failure, and no release of shared indicator handles in `PortfolioRiskManager`.
- **Compile:** Verified by `sync_and_compile.ps1 -MirrorSync` with `0 errors, 0 warnings`.

### Batch 16: Institutional Remediation Hardening (2026-02-23)
- **Risk Governance:** `PortfolioRiskManager` now treats missing SL as hard-veto state with elevated portfolio risk propagation; zero-risk fallback for unprotected positions removed.
- **Risk Budgeting:** `UnifiedRiskManager` daily budget is now mark-to-market aware (`max(entry-risk-used, daily equity drawdown, open portfolio stop risk)`).
- **Validation Gate:** `RiskValidationGate` now explicitly rejects entries while unprotected positions exist and uses consistent risk-percent flow in portfolio checks.
- **Execution Safety:** `TradeManager` now supports configurable fill mode (IOC default), broader transient-retcode retries with bounded backoff, normalized-volume execution path, and emergency-aware protective stop updates.
- **Deterministic Runtime:** Main loop now enforces second-level signal dedupe across `OnTick`/`OnTimer`, terminal-connectivity gating, and 1s-bounded position-management cadence.
- **AI Safety:** NN online training, pseudo-labeling, and weight mutation are now opt-in and disabled by default; checkpoint load no longer re-enables unsafe runtime mutation.
- **AI Runtime Robustness:** Orchestrator registry capacity expanded (`MAX_STRATEGIES=64`) to prevent symbol-qualified strategy registration failures observed in `testing.log`.
- **Feature Pipeline Stability:** Transformer feature defaults reduced (`dModel 128`), warning spam throttled, and cross-symbol feature normalization corrected to percent-based scaling.
- **Compile:** Verified by `sync_and_compile.ps1 -MirrorSync` with `0 errors, 0 warnings`.

### Batch 15: Code Review Fixes + Memory Safety Improvements (2026-02-23)
- **Fixed:** Critical memory leak in `CEnsembleAIStrategyAdapter` - transformer models now properly deleted in destructor with failure-safe cleanup.
- **Fixed:** Null pointer dereference risk in `CEnterpriseStrategyManager::RegisterStrategy` - removed unsafe pointer assignment after deletion.
- **Enhanced:** Added comprehensive bounds checking and input validation in `CAIFeatureVectorBuilder::BuildTransformerInput` with detailed error messages.
- **Improved:** Added proper error handling and array validation in `CEnterpriseStrategyManager::PopClosedTradeAttribution`.
- **Standardized:** Defined constants for all hardcoded transformer parameters across AI components (`TRANSFORMER_D_MODEL_DEFAULT`, etc.).
- **Verified:** Confirmed proper initialization of new `UnifiedSignalPipeline` member variables.
- **Quality:** Eliminated magic numbers and improved maintainability across AI adapter implementations.
- **Compilation:** Verified 0 errors, 0 warnings with all 2,783 lines of new code integrated successfully.

## [Unreleased] - 2026-02-22

### Batch 14: Documentation Standardization + Compile Artifact Cleanup (2026-02-22)
- **Standardized:** Normalized top-level documentation structure and metadata blocks (`Last Updated`, scope/status) across:
- `README.md`
- `RUNTIME_DECISION_GRAPH.md`
- `SYSTEM_AUDIT_TRACE.md`
- `MAINTENANCE_PROTOCOL.md`
- **Added:** New full architecture specification document:
- `SYSTEM_STRUCTURE.md`
- **Expanded:** `AGENTS.md` with stronger AI-change workflows, validation rules, invariants, and definition-of-done contract.
- **Automated:** `sync_and_compile.ps1` now removes compile-generated `.log/.txt` artifacts by default after runs.
- **Override:** Added `-KeepCompileArtifacts` switch to preserve compile artifacts when explicitly needed.

### Batch 13: Documentation Baseline + Tester Operations Stabilization (2026-02-18)
- **Documented:** Rebuilt project-level documentation baseline with:
- `README.md` (full system overview, architecture, operations, known issues)
- `RUNTIME_DECISION_GRAPH.md` (authoritative runtime flow with intrabar/new-bar branch and shadow/live execution split)
- `MAINTENANCE_PROTOCOL.md` (forward update protocol for future implementations)
- `AGENTS.md` (future collaboration contract and run workflow)
- **Normalized:** Cleared `AUDIT_REPORT.md` to an intentionally empty baseline state for future fresh audits.
- **Tracked:** Updated `.gitignore` to keep markdown/text documentation under version control (removed blanket `*.md` and `*.txt` ignore behavior).
- **Stabilized Ops:** Shadow tester profile files were updated to start on `EURUSD.0` and use a broader stable symbol basket:
- `EURUSD.0,XAUUSD.0,BTCUSD.0,GBPUSD.0,USDJPY.0,AUDUSD.0`
- **Operational Guidance:** Standardized tester workflow to persistent UI sessions (`/portable` or normal open) to avoid account/session resets from repeated `/config` launches.

### Batch 12: Stub/Placeholder Elimination (2026-02-15)
- **Implemented:** `CTransformerBrain::TrainStep` now performs real supervised updates via a 3-class classification head with momentum SGD instead of no-op placeholder behavior.
- **Implemented:** `CAIPerformanceFeedback::TriggerRetraining` now persists retraining requests and exports labeled datasets for downstream retraining workflows.
- **Completed:** `CStrategyFactory` now has concrete construction paths for all declared strategy enum types instead of partial unsupported branches.
- **Hardened:** `CTradeWrapper` utility methods now use real runtime checks (`TERMINAL_CONNECTED`, `TERMINAL_TRADE_ALLOWED`, `PositionSelect`) instead of stub returns.
- **Cleaned:** Removed placeholder/stub comments and no-op placeholder operations in runtime code paths.
- **Compatibility:** `Strategies/StrategyFactory.mqh` is now an explicit compatibility include to `Core/Strategy/StrategyFactory.mqh`.

### Batch 11: Runtime Attribution + Flow Hardening (2026-02-15)
- **Fixed:** Neural attribution now defers labeling on partial closes and labels only on final close using accumulated position net P/L.
- **Hardened:** Added per-position close P/L accumulator keyed by `POSITION_IDENTIFIER` to prevent training-label distortion.
- **Scoped:** Enterprise trade feedback ingestion is now filtered by managed magic number and manager symbol.
- **Stabilized:** Enterprise manager now ignores partial-close feedback until position is fully closed to avoid duplicated performance updates.
- **Corrected:** Trading loop no longer exits early on cooldown/position-limit blocks, ensuring position management and emergency checks still run every cycle.
- **Aligned:** Runtime documentation updated to reflect deferred close-labeling and scoped manager feedback behavior.

### Batch 10: Remaining Audit Hardening (2026-02-14)
- **Unified:** Switched order placement in EA runtime from direct `CTrade.Buy/Sell` calls to `CTradeManager.OpenPosition` as authoritative execution path.
- **Initialized:** Added explicit `TradeManager.Initialize(...)` bootstrap in `OnInit`.
- **Hardened:** AI subsystem init now respects per-feature flags (`InpEnableTransformer`, `InpEnableEnsemble`) instead of unconditional startup in AI mode.
- **Improved:** `AIStrategyOrchestrator` now updates `avgProfit`/`avgLoss` per trade, enabling meaningful `profitFactor` behavior.
- **Corrected:** Orchestrator weight adjustment now uses normalized win-rate units consistently.
- **Wired:** Added best-effort strategy attribution from enterprise orchestrated votes into `UpdateStrategyPerformance(...)` on trade close.
- **Stabilized:** `NeuralNetworkStrategy` online training and weight persistence lifecycle were tightened during this batch; later runtime policy updates supersede tester-only restrictions.
- **Secured:** `IndicatorManager` cache matching now validates parameter count plus values, reducing handle cross-parameter leakage risk.
- **Documented:** Added `SYSTEM_AUDIT_TRACE.md` with full lifecycle and ownership mapping for OnInit/OnTick/OnTimer and build flow.

### Batch 9: Audit Gap Closure (2026-02-14)
- **Fixed:** Removed duplicate `AIEngine` include and duplicate `g_AIEngine` initialization/deinitialization paths to prevent lifecycle drift.
- **Hardened:** Gated `AIEngine` startup strictly behind `InpEnableAIMode`; no AI engine bootstrap now occurs when AI mode is disabled.
- **Wired:** Initialized `PortfolioRiskManager` explicitly and integrated `AdaptiveRiskManager` initialization + per-bar adaptation calls.
- **Unified:** Updated enterprise orchestrator voting path to use the same pipeline filtering flow before ensemble decisions.
- **Secured:** Added strict cross-symbol rejection in `GetConsensusSignalForSymbolWithConfluence` to eliminate strategy cross-talk risk.
- **Corrected:** `SetPipelineFilters` now applies runtime filters without reinitializing pipeline engines.
- **Determinism:** Replaced neural feature random noise with market-derived volatility-regime input.
- **Corrected:** Drawdown/risk UI display no longer double-multiplies percentage values.

### Batch 8: Risk Standardization & Compilation Repair (2026-02-14)
- **Fixed:** All 23 compilation errors identified by `sync_and_compile.ps1`, specifically in `EnhancedRiskManager`, `NeuralNetworkStrategy`, and `AIEngine`.
- **Standardized:** Transitioned all risk Management inputs (`InpMaxRiskPerTrade`, `InpMaxDailyRisk`, `InpMaxDrawdown`) and internal calculations to a consistent 0-100 percentage scale.
- **Implemented:** Dampened Kelly Fraction calculation in `EnhancedRiskManager` with a 25% safety factor for safer position sizing.
- **Refactored:** `NeuralNetworkStrategy` feature extraction to use proper MQL5 indicator handles and `CopyBuffer` instead of legacy MQL4-style calls.
- **Added:** Missing `InpMaxPortfolioRisk` parameter (default 10%) to provide a global risk ceiling for the account.
- **Achieved:** Clean compilation (exit code 0) for `MultiStrategyAutonomousEA.mq5`.

### Batch 7: Execution Stack Unification & AI Cleanup (2026-02-14)
- **Fixed:** Removed broken references to deleted modules (`TradingEngine`, `IntegrationHub`) that caused compilation crashes.
- **Unified:** Consolidated position management (trailing stops, breakeven) into `CAdvancedPositionManager`, removing redundant calls to legacy components.
- **Removed:** Non-functional heuristic "AI Predictions" from the main EA tick loop, ensuring AI signals strictly originate from the ML pipeline.
- **Verified:** Proper injection of the global `aiOrchestrator` into the `EnterpriseStrategyManager`.

### Batch 6: AI Fidelity & Risk System Repair (2026-02-14)
- **Fixed:** Rebuilt the corrupted `PortfolioRiskManager.mqh` from scratch with safe 0-100% risk unit tracking.
- **Enhanced:** Implemented real feature extraction in `NeuralNetworkStrategy`, replacing 25+ placeholders with live technical data (RSI, ADX, ATR, etc.).
- **Verified:** Corrected the AI Adapter registration order to ensure neural network availability.

### Batch 5: Extended Audit Resolution (2026-02-14)
- **Fixed:** Critical multi-symbol strategy cross-talk by restricting the main trade loop to the chart symbol.
- **Fixed:** Non-deterministic AI behavior by replacing `MathRand` with a seeded LCG (Linear Congruential Generator) in AI modules.
- **Feature:** Wired `OnTradeTransaction` to feed trade results (P/L) back to the Orchestrator for adaptive learning.
- **Cleanup:** Removed redundant `EnhancedEnsembleVotingSystem.mqh`.

### Batch 4: Pipeline Verification & Audit Fixes (2026-02-14)
- **Verified:** Confirmed full implementation of `TrendEngine` and `AdvancedSignalValidator` in the unified pipeline.
- **Enhanced:** Improved `AIEngine` query reporting to return detailed market regime and consensus context.
- **Deleted:** Removed heavy legacy files: `IntegrationHub.mqh`, `GeneticOptimizer.mqh`, `TradingEngine.mqh`.

### Batch 3: AI Orchestrator & Adaptation (2026-02-14)
- **Fixed:** Orchestrator instance mismatch by injecting the global `aiOrchestrator` into `EnterpriseStrategyManager`.
- **Corrected:** `EnsembleMetaLearner` now returns real calculated confidence instead of a hardcoded mock value.
- **Wired:** Added `g_AIEngine.ProcessAdaptation()` to the `OnNewBar` event for active weight tuning.
- **Initialized:** Configured `g_AIEngine` in `OnInit` to support Adaptive Mode.

### Batch 2: Dead Code Removal & Risk Wiring (2026-02-14)
- **Initialized:** Fixed the `RiskValidationGate.Initialize` early return bug and correctly initialized it in `OnInit`.
- **Wired:** Integrated `riskGate.ValidateTradeRequest()` into the core trade execution path.
- **Deleted:** Mass-removed obsolete/redundant risk modules including `PreTradeValidator.mqh`, `RiskManager.mqh`, and `DynamicExitManager.mqh`.

### Batch 1: Initial Audit Fixes (2026-02-14)
- **Fixed:** `PositionSizer` initialization failure in `OnInit`.
- **Corrected:** Risk unit convention ambiguity (Fraction vs Percent) resolved in favor of standardized percentages.
- **Implemented:** `SetPipelineFilters` to actually apply EA inputs (Volatility, Trend) to the signal pipeline.
- **Secured:** Fixed `IndicatorManager` double-free and singleton lifecycle bugs.
- **Normalized:** Fixed variable mismatches (`startTime` vs `queryStartTime`) in `AIEngine`.
- **Build:** Fixed exclusion pattern matching in `sync_and_compile.ps1`.
