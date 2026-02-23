# Project Context Notes
 
 - EA operates across multiple strategies; recent focus on order block improvements, confidence filtering, and indicator warmups.
 - MarketAnalysis engine now enforces symbol availability checks and extended warmup (60s) with retry silence (5 min).
 - StrategyBase enforces minimum signal confidence of 0.30 and tracks low-confidence filters.
 - StrategyOrderBlock throttles scans to 60 seconds and deduplicates logging; continues checking blocks while skipping low-confidence touches.
 - New-bar updates are dispatched via `CEnterpriseStrategyManager::OnNewBar(symbol,timeframe)` which calls `IStrategy::OnNewBar(symbol,timeframe)` polymorphically; strategies should refresh/prime indicator data there (e.g., Swing now uses persistent MA/RSI handles).

## 2026-02-22 Session Context Updates

- A Windsurf workflow library is now present under `.windsurf/workflows` for repeatable task execution.
- EA-specific workflows include runtime audit, safe fix implementation, shadow triage, release doc sync, and compile hygiene.
- General-purpose workflows were added under `.windsurf/workflows/global` for broad use:
  - `global_task_loop`
  - `web_build_adjust_debug`
  - `web_debug_hotfix`
  - `python_feature_bugfix`
  - `python_debug_triage`
- Canonical path for reusable workflows is `.windsurf/workflows/global`.
- `rule-pro.md` is now a stricter autonomous operator contract:
  - execution-first behavior
  - no placeholders/TODO/FIXME stubs unless explicitly requested
  - evidence-based completion claims
  - repository state files maintenance requirement
- Repository state files are now explicit operating memory:
  - `.windsurf/context.md`
  - `.windsurf/history.md`
  - `.windsurf/planning.md`
- Compile artifact hygiene remains enforced by script behavior and policy: temporary compile logs/txt are removed unless explicitly retained via `-KeepCompileArtifacts`.

## 2026-02-22 Implementation Baseline (Recovered)

- Enterprise managers are now symbol-scoped and register core + AI adapters per symbol during initialization (`MultiStrategyAutonomousEA.mq5`).
- Transformer and Ensemble are integrated as runtime voters through `IStrategy` adapters, not init-only globals:
  - `Core/Strategy/TransformerAIStrategyAdapter.mqh`
  - `Core/Strategy/EnsembleAIStrategyAdapter.mqh`
- Shared AI feature construction exists for NN/Transformer/Ensemble consistency:
  - `Core/AI/AIFeatureVectorBuilder.mqh`
- Consensus behavior is mode-aware in `CEnterpriseStrategyManager`:
  - new-bar quorum remains manager minimum
  - intrabar quorum uses adaptive single-voter policy with confidence floor `0.65`
  - diagnostic reason counters emit `[CONSENSUS-DIAG]` every 60 seconds
- Momentum is explicitly non-intrabar in auto-registration to align with bar-cadence behavior.
- Intrabar scan scope defaults to all managed symbols (`InpIntrabarChartSymbolOnly=false`).
- Shadow-first execution mode exists (`InpShadowMode=true`) and logs `[SHADOW-TRADE]` without order sends.
- Orchestrator integration is bidirectional:
  - manager strategies registered as `symbol::strategy`
  - adapted weights synchronized back into manager weights
  - closed-trade contributor feedback updates orchestrator performance
- Liquidity filter now evaluates the target symbol context instead of relying on chart `_Symbol` fallback behavior in normal path.
- Indicator singleton lifecycle has explicit teardown:
  - `CIndicatorManager::DestroyInstance()` in `IndicatorManager.mqh`
  - invoked in `OnDeinit` of `MultiStrategyAutonomousEA.mq5`

## Known Operational Note
- Windows file lock/ACL currently blocks deleting some copied workflow files in `.windsurf/workflows` root; canonical reusable set is `.windsurf/workflows/global`.
