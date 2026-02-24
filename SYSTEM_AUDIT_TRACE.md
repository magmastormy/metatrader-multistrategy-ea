# System Audit Trace

## Document Metadata
- Last Updated: 2026-02-23
- Scope: Runtime lifecycle and ownership trace

## Scope
- Entry point: `MultiStrategyAutonomousEA.mq5`
- Symbol decision manager: `Core/Management/EnterpriseStrategyManager.mqh`
- Filter pipeline: `Core/Pipeline/UnifiedSignalPipeline.mqh`
- AI orchestrator: `Core/AI/AIStrategyOrchestrator.mqh`
- AI adapters:
  - `Core/Strategy/AIStrategyAdapter.mqh`
  - `Core/Strategy/TransformerAIStrategyAdapter.mqh`
  - `Core/Strategy/EnsembleAIStrategyAdapter.mqh`
- Risk authority: `Core/Risk/UnifiedRiskManager.mqh`
- Execution authority: `Core/Trading/TradeManager.mqh`
- Position authority: `Core/Trading/AdvancedPositionManager.mqh`

## Runtime Lifecycle

### 1. OnInit
- Validate terminal and trading permissions.
- Initialize execution/risk systems.
- Apply execution safety controls (fill mode, slippage, protective modify cooldown) before trade-manager bootstrap.
- Initialize AI subsystems conditionally by flags.
- Build per-symbol managers and strategy registrations.
- Register orchestrator strategy identities.

### 2. Tick/Timer cycle
- Run `ProcessTradingLogic`.
- Maintain NN learning cycle.
- Enforce terminal connectivity gate before signal evaluation.
- Enforce deterministic second-level signal evaluation separation between tick/timer events.
- Run deterministic unprotected-position remediation sweep before entry evaluation.
- Rotate symbol evaluation start index each cycle to reduce fixed-order concentration.
- Detect new-bar events per symbol.
- Run intrabar scans when eligible.

### 3. Signal path
- Manager consensus + confluence.
- Validation profile checks.
- Risk gating (pre-size then post-size).
- ATR stop-distance fallback when indicator read fails.
- Shadow or live execution branch.
- Per-symbol capacity checks include explicit external-position block telemetry.

### 4. Post-trade path
- Transaction callback updates manager/orchestrator performance.
- NN attribution maps prediction IDs and labels closes (online-training gate controlled).

### 5. Housekeeping
- Position manager lifecycle actions.
- Periodic telemetry logs.
- Indicator cache release policy.

### 6. OnDeinit
- Release managers and dynamic strategy allocations.
- Deinitialize subsystems.
- Explicit `CIndicatorManager::DestroyInstance()`.
- Orchestrator report emission is single-source (destructor-owned) to avoid duplicate shutdown reports.
- **Memory Safety**: AI adapters now properly clean up transformer models in destructors.
- **Error Handling**: Enhanced validation in feature vector construction and attribution systems.

## Observability Surface
- Decision: `[SIGNAL]`, `[SIGNAL-REJECTED]`, `[SIGNAL-VALIDATED]`
- System telemetry: `[HEARTBEAT]`, `[RISK-BUDGET]`, `[CONSENSUS-DIAG]`, `[QUIET-REASONS]`
- Risk remediation: `[RISK-UNPROTECTED]`, `[CAPACITY-EXTERNAL]`
- AI: `[AI-VOTE]`, `[NN-HEALTH]`
- Trade: `[SHADOW-TRADE]`, `[TRADE-SUCCESS]`, `[TRADE-ERROR]`

## Current Operational Constraints
- Persistent terminal sessions are preferred.
- Start tester on stable history symbol (`EURUSD.0`) when synthetic history is uncertain.
- Emergency drawdown flattening can run account-wide when configured (`InpEmergencyFlattenAllAccountPositions=true`).

## Build Note
- Compile helper: `sync_and_compile.ps1`
- Compile artifacts should be auto-cleaned after runs unless explicitly retained.
- **Code Quality**: Recent fixes address memory leaks, null pointer safety, bounds checking, and standardized constants across AI components.
- **Compilation**: Verified 0 errors, 0 warnings with all improvements integrated.
