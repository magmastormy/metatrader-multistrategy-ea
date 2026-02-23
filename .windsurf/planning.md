# Current Planning

## Active Track (2026-02-22)
- [x] Research Windsurf workflow patterns and map them into repository-ready markdown workflows.
- [x] Create baseline workflow pack in `.windsurf/workflows`:
  - [x] `audit_runtime_ai.md`
  - [x] `implement_safe_fix.md`
  - [x] `shadow_run_triage.md`
  - [x] `release_doc_sync.md`
  - [x] `compile_clean.md`
  - [x] workflow index `README.md`
- [x] Create general-purpose workflows for broader coding usage:
  - [x] global any-task loop
  - [x] web build/adjust/debug
  - [x] web hotfix debug
  - [x] python feature+bugfix
  - [x] python debug triage
- [x] Place general-purpose workflows under `.windsurf/workflows/global` for reusable/global organization.
- [x] Harden `.windsurf/rules/rule-pro.md` for stricter autonomous execution and quality gates.
- [x] Enforce explicit no-placeholder policy in rules (no TODO/FIXME/stub completion outputs).
- [x] Add repository state-file maintenance policy (`context.md`, `history.md`, `planning.md`) into rules.

## Immediate Follow-up
- [ ] Remove duplicated general workflow copies in `.windsurf/workflows` root when Windows file lock/ACL allows deletion.
- [ ] Optionally mirror `.windsurf/workflows/global` into your external/global Windsurf profile location if you want cross-project reuse.
- [ ] Keep session state files updated at close of each major implementation batch.

## System Recovery Track (2026-02-22 Snapshot)
- [x] Wire Transformer/Ensemble into runtime vote path via adapters.
- [x] Add shared AI feature builder for adapter input parity.
- [x] Register symbol-qualified strategies with orchestrator (`symbol::strategy`).
- [x] Synchronize adapted orchestrator weights back into enterprise managers.
- [x] Feed closed-trade contributor performance into orchestrator updates.
- [x] Add adaptive intrabar quorum logic with confidence safety floor.
- [x] Add first-class consensus diagnostics (`raw_none`, `filtered_out`, `quorum_failed`, `intrabar_not_eligible`).
- [x] Align Momentum intrabar eligibility to non-intrabar.
- [x] Enable all-symbol intrabar default (`InpIntrabarChartSymbolOnly=false`).
- [x] Add shadow-mode runtime path (`InpShadowMode=true`) with `[SHADOW-TRADE]` outputs.
- [x] Fix indicator singleton teardown path on deinit.
- [x] Fix liquidity filter symbol context in unified pipeline.

## Recovery Validation To Continue
- [ ] Run a clean shadow session and capture 24h-equivalent telemetry window.
- [ ] Confirm `no_signal_ratio < 97%` on intrabar-enabled symbols.
- [ ] Confirm non-zero Transformer and Ensemble vote counts per active symbol.
- [ ] Confirm orchestrator report shows non-zero registered strategies and active adaptation.
- [ ] Confirm deinit has no indicator-manager leak warnings.

## ✅ CRITICAL FIXES COMPLETED (2025-12-25) - ALL ISSUES RESOLVED
- [x] Remove BEAST MODE override (ProcessIntelligentTrading.mqh:147-156)
  - [x] Delete lines forcing 0.01 lot size
  - [x] Implement proper risk-based position sizing with 5-lot cap
- [x] Fix AI exit thresholds (Core/Engines/TradingEngine.mqh:1335-1360)
  - [x] Change exit threshold from 0.45 to 0.20
  - [x] Remove "take profit on weakness" logic
  - [x] Only exit on strong reversal signals (0.20/0.80)
- [x] Resolve exit system conflicts
  - [x] Disable Progressive TP Manager
  - [x] Verify no conflicts with unified exit system
  - [x] Successful compilation (0 errors, 0 warnings)
- [x] Fix function signature mismatches (IntegrationHub.mqh)
  - [x] GetAIPrediction now includes reasoning parameter
  - [x] All function calls updated
- [x] Implement missing functions (IntegrationHub.mqh)
  - [x] CallCppAI function body added
  - [x] BuildMarketDataJson implemented
  - [x] ExtractJsonString implemented
  - [x] ExtractJsonNumber implemented
  - [x] ExtractDataBlock implemented
  - [x] TimeframeToString implemented
- [x] Final compilation verification (0 errors, 0 warnings)

## IMMEDIATE PRIORITY - Demo Testing Required
- [ ] Run demo test for 100+ trades (minimum 1 week)
  - [ ] Verify position sizing scales correctly (not fixed at 0.01)
  - [ ] Verify average R:R achieved > 1.5:1
  - [ ] Verify no premature exits at 0.45 threshold
  - [ ] Monitor for exit system conflicts
- [ ] Track key metrics
  - [ ] Lot size variation by account size
  - [ ] Average winner/loser ratio
  - [ ] Win rate (target 40%+)
  - [ ] Expectancy (must be positive)
  - [ ] Max drawdown (should not exceed 15%)

## Future Enhancements (After Demo Validation)
- [ ] Implement strategy weighting system
  - [ ] Weight proven strategies higher (SMC, Elliott Wave)
- [ ] Add exit priority hierarchy
  - [ ] Stop Loss > Take Profit > AI Signal > Trailing > Time
- [ ] Performance monitoring dashboard
  - [ ] Track actual vs target R:R
  - [ ] Strategy-level performance breakdown
- [ ] Clean up unused files
  - [ ] Delete DynamicExitManager.mqh (not used)

## Completed Objectives
- [x] Initialize session tracking files (2025-12-23)
- [x] Fix compilation errors (2025-12-23)
- [x] Fix extreme SL/TP values on synthetic indices (2025-12-24)
- [x] Forensic analysis of EA profitability issues (2025-12-25)
- [x] Implement all critical fixes (2025-12-25)
- [x] Clean trailing whitespace in MultiStrategyAutonomousEA.mq5 to satisfy git diff checks (2025-12-26)
- [x] Refine `OnNewBar(symbol,timeframe)` dispatch + indicator refresh (RSI/Trend/Swing) (2025-12-27)
- [x] Fix Elliott Wave pattern detection - relaxed validation for more signals (2025-12-28)
- [x] Fix SMC strategy - complete rewrite with proper SMC rules (price direction, rejection confirmation, mitigation tracking) (2025-12-28)

## Deferred/Blocked
- None
