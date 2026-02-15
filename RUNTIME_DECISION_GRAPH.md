# Runtime Decision Graph

## Purpose
This document defines one operational trade decision path for `MultiStrategyAutonomousEA.mq5` and explicit ownership boundaries for pre-trade, execution, and post-trade handling.

## Ownership Contract
- Authoritative pre-trade veto: `CRiskValidationGate` (`Core/Risk/RiskValidationGate.mqh`)
- Risk context provider (used by gate): `CPortfolioRiskManager` (`Core/Risk/PortfolioRiskManager.mqh`)
- Advisory only (no pre-trade veto):
  - `CAdaptiveRiskManager` -> suggests runtime risk percent
  - `CEnhancedRiskManager` -> telemetry/performance/risk-usage tracking
- Execution owner: `CTradeManager` (`Core/Trading/TradeManager.mqh`)
- Position lifecycle owner: `CAdvancedPositionManager` (`Core/Trading/AdvancedPositionManager.mqh`)

## End-to-End Flow
1. Signal Generation
- Per-symbol `CEnterpriseStrategyManager` instances generate consensus signals.
- Pipeline/orchestrator filtering happens inside manager path.

2. Pre-Trade Preparation
- EA computes ATR-derived SL/TP and candidate risk percent.
- `CAdaptiveRiskManager` may adjust suggested risk percent (advisory).

3. Authoritative Risk Validation
- Phase A (`pre-size`): `CRiskValidationGate::ValidateTradeRequest(...)` with min lot.
- Position size is calculated.
- Phase B (`post-size`): `CRiskValidationGate::ValidateTradeRequest(...)` with final lot.
- Any rejection here is final; no trade is sent.

4. Execution
- `CTradeManager::OpenPosition(...)` sends the order.
- Trade manager performs execution-safety checks (symbol/volume/margin/trading permission), not strategy-governance risk policy.

5. Post-Execution
- On success, EA records advisory usage in `CEnhancedRiskManager`.
- Cooldown timestamp is updated.

6. Open Position Management
- `CAdvancedPositionManager::ManageAllPositions()` handles trailing/breakeven/partial closes.
- Management scope is restricted by EA magic number.

7. Trade Feedback
- `OnTradeTransaction` routes closed-trade feedback to symbol-specific enterprise manager.
- Orchestrator and neural strategy feedback are updated from closed deal outcomes.
- Neural attribution path:
  - Signal prediction reserves an NN prediction ID.
  - Order comment embeds the ID (`|N:<predictionId>`).
  - Entry deals map `POSITION_IDENTIFIER -> predictionId`.
  - Partial close deals are accumulated by `POSITION_IDENTIFIER` and not labeled immediately.
  - Final close labels the NN sample using total net P/L (accumulated partials + final close).
  - Close labeling attempts exact ID first, then fallback time-heuristic only if exact ID is unavailable.
  - Position mapping is cleared only after final close.
  - Enterprise manager feedback is scoped by manager symbol and managed magic number.

## Invariants
- No direct `CTrade.Buy/Sell` calls in EA decision path.
- All entries pass through `CRiskValidationGate` before `CTradeManager::OpenPosition(...)`.
- Advisory risk modules cannot block entries.
- Position manager does not manage non-EA positions (magic-scoped).

## NN Attribution Forward-Test Protocol
1. Enable inputs:
- `InpEnableAIMode=true`
- `InpEnableNeuralNetwork=true`
- `InpEnableNNAttributionDiagnostics=true`
- Optional first run: `InpRunNNAttributionSelfTest=true`

2. Run on demo and trigger trades (including partial closes if enabled).

3. Expected logs:
- Entry mapping: `[NN-DIAG] Entry mapped ... PositionID ... PredictionID ...`
- Exact close attribution: `[NN-DIAG] Close labeled by ID ...`
- Partial close deferral: `[NN-DIAG] Partial close deferred ...`
- Final close cleanup: `[NN-DIAG] Position map cleared ...`
- Periodic summary: `[NN-DIAG] Summary (periodic) ...`

4. Pass criteria:
- `CloseById` grows with real closes.
- `CloseMiss` remains near zero.
- `ActiveMap` does not leak upward over long runtime.
