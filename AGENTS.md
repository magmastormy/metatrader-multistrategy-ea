# AGENTS.md

## Document Metadata
- Last Updated: 2026-07-01
- Scope: Agent workflow contract for this repository
- Latest Batch: Batch 109 - Enterprise Coding Standards + Codebase Compliance

## 1. Mission
Maintain and evolve `metatrader-multistrategy-ea` with production-safe discipline:
- preserve runtime invariants
- keep decisions explainable from logs
- prevent regression in risk ownership and execution flow
- maintain synchronized documentation

## 2. Core Operating Principles
1. Determinism over convenience.
2. One authority per domain (consensus, risk, execution, lifecycle).
3. Log-driven verification before claims.
4. Shadow-first rollout for meaningful behavior changes.
5. Documentation updates are part of completion, not optional follow-up.

## 3. Non-Negotiable Technical Invariants
1. All trade entries must pass `CUnifiedRiskManager` pre-trade gating.
2. Runtime execution must remain `CTradeManager`-owned.
3. Position lifecycle must remain EA-loop-owned via `MultiStrategyAutonomousEA.mq5` calling `CTradeManager::ManageAllPositions(...)`.
4. Strategy decisioning must remain symbol-scoped manager consensus.
5. `CIndicatorManager::DestroyInstance()` must be called on deinit.

## 4. Strong Workflow for Better AI Usage

### 4.1 AI feature change protocol
When touching AI modules/adapters/orchestrator:
1. Verify adapter registration exists for each enabled AI mode.
2. Verify runtime call-sites produce vote logs (`[AI-VOTE]`).
3. Verify orchestrator registration with qualified names (`symbol::strategy`).
4. Verify weight adaptation sync path back into managers.
5. Verify failure mode (AI disabled) still produces clean non-AI behavior.

### 4.2 AI diagnostics minimum evidence
A valid AI-related change must include evidence of:
- non-zero AI vote activity
- no hard runtime errors in adapter paths
- consensus behavior with and without AI flags
- unchanged risk veto behavior

### 4.3 Prompting/analysis discipline for future agent sessions
- Do not infer runtime health from init logs alone.
- Distinguish initialization evidence from runtime participation.
- Always map issue claims to file path + log signature.
- If behavior is time-sensitive, gather fresh logs from the active session.

## 5. Execution Workflow

### 5.1 Standard task sequence
1. Gather context from code + active logs.
2. Identify root cause with explicit evidence.
3. Implement minimal complete fix.
4. Run compile/sanity checks.
5. Validate with runtime logs.
6. Update docs/changelog.

### 5.2 Runtime test mode policy
- Prefer persistent terminal sessions (normal or `/portable`).
- Avoid repeated `/config` launch loops for manual workflows.
- Use shadow mode for major changes before live send.

## 6. Logging and Validation Checklist
After any strategy/risk/execution change, verify:
- `[HEARTBEAT]`
- `[CONSENSUS-DIAG]`
- `[SIGNAL-REJECTED]`
- `[AI-VOTE]` (if AI enabled)
- `[SHADOW-TRADE]` or live trade result logs
- `[PYTHON-BRIDGE-DASHBOARD]` (if Python bridge enabled)
- `[COMPOUNDING-TIER-HEARTBEAT]` (if compounding tiers enabled)
- `[COMPOUNDING-TIER-MILESTONE]` (on account milestone crosses)
- `[FAMILY-WEIGHT-MATRIX]` (per-family cluster weighting active)
- `[FAMILY-WEIGHT-VOL]` (volatility family weight deviation log)
- `[SESSION-WEIGHT-HEARTBEAT]` (session-aware adjustments)
- `[SKEW-STEP-HEARTBEAT]` (Skew Step phase analysis)
- `[RISK-FAMILY-POS]` (family position limit blocked trade)
- `[ADX-MODIFIER]` (ADX-based lot scaling applied)

## 7. Compile and Artifact Hygiene
- Compilation helpers may create temporary `.log/.txt` artifacts.
- Default behavior should remove compile artifacts after run.
- Keep artifacts only when explicitly needed for debugging (`-KeepCompileArtifacts` style control).

## 8. Documentation Contract
Every meaningful implementation batch must update:
- `README.md` (operational impact)
- `SYSTEM_STRUCTURE.md` (architecture/ownership changes)
- `RUNTIME_DECISION_GRAPH.md` (decision path changes)
- `SYSTEM_AUDIT_TRACE.md` (lifecycle changes)
- `changelogs.md` (dated batch entry)

## 9. Safety and Change Control
- Never use destructive git reset/revert operations unless explicitly requested.
- Never silently remove unrelated user changes.
- If unexpected external modifications appear during work, stop and ask user how to proceed.

## 10. Definition of Done
1. Compile passes.
2. Runtime invariants preserved.
3. Required log evidence captured.
4. Docs/changelog updated.
5. No unwanted compile artifacts left behind.
