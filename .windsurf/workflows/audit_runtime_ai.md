# Runtime AI Audit (EA)

Perform a full audit focused on runtime execution, not initialization-only logs.

## Objectives
- Find why strategies/AI modules initialize but do not vote or execute.
- Quantify decision starvation (`no_signal`, quorum failures, filters).
- Produce file-level root causes and a fix plan with acceptance gates.

## Inputs to inspect first
- `new.log`
- `neuralnet.log`
- `MultiStrategyAutonomousEA.mq5`
- `Core/Management/EnterpriseStrategyManager.mqh`
- `Core/Pipeline/UnifiedSignalPipeline.mqh`
- `Core/AI/AIStrategyOrchestrator.mqh`

## Required method
1. Build a runtime call graph: init path vs decision loop path.
2. Verify each AI module has real runtime call sites.
3. Check orchestrator registration count and strategy naming format (`symbol::strategy`).
4. Measure suppression points: raw none, filtered, quorum miss, cadence gating.
5. Validate symbol correctness in all filters (never rely on accidental `_Symbol`).
6. Verify lifecycle cleanup (singleton destroy paths).

## Output contract
- `Findings` section ordered by severity with `file:line`.
- `Evidence` section with exact log signatures/counters.
- `Resolution plan` in phases:
  - restore execution flow
  - wire AI as voters
  - shadow burn-in and live gates
- `Regression tests` list with deterministic checks.
