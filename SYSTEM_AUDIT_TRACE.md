# System Audit Trace

## Document Metadata
- Last Updated: 2026-02-22
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
- Initialize AI subsystems conditionally by flags.
- Build per-symbol managers and strategy registrations.
- Register orchestrator strategy identities.

### 2. Tick/Timer cycle
- Run `ProcessTradingLogic`.
- Maintain NN learning cycle.
- Detect new-bar events per symbol.
- Run intrabar scans when eligible.

### 3. Signal path
- Manager consensus + confluence.
- Validation profile checks.
- Risk gating (pre-size then post-size).
- Shadow or live execution branch.

### 4. Post-trade path
- Transaction callback updates manager/orchestrator performance.
- NN attribution maps prediction IDs and labels closes.

### 5. Housekeeping
- Position manager lifecycle actions.
- Periodic telemetry logs.
- Indicator cache release policy.

### 6. OnDeinit
- Release managers and dynamic strategy allocations.
- Deinitialize subsystems.
- Explicit `CIndicatorManager::DestroyInstance()`.

## Observability Surface
- Decision: `[SIGNAL]`, `[SIGNAL-REJECTED]`, `[SIGNAL-VALIDATED]`
- System telemetry: `[HEARTBEAT]`, `[CONSENSUS-DIAG]`, `[QUIET-REASONS]`
- AI: `[AI-VOTE]`, `[NN-HEALTH]`
- Trade: `[SHADOW-TRADE]`, `[TRADE-SUCCESS]`, `[TRADE-ERROR]`

## Current Operational Constraints
- Persistent terminal sessions are preferred.
- Start tester on stable history symbol (`EURUSD.0`) when synthetic history is uncertain.

## Build Note
- Compile helper: `sync_and_compile.ps1`
- Compile artifacts should be auto-cleaned after runs unless explicitly retained.
