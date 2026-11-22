# Maintenance Protocol

## Document Metadata
- Last Updated: 2026-11-19
- Scope: Forward update contract

This document defines mandatory implementation, validation, and documentation steps for future batches.

## 1. Mandatory Update Checklist

### 1.1 Code and config
- Update runtime code.
- Update the relevant tester `.ini`/`.set` inputs when behavior depends on profile settings. Make test values explicit and verify MT5 has not inherited a prior per-expert `.set` file.

### 1.2 Documentation
- Update `README.md` for operational behavior changes.
- Update `SYSTEM_STRUCTURE.md` for architecture or ownership changes.
- Update `RUNTIME_DECISION_GRAPH.md` for decision-path changes.
- Update `SYSTEM_AUDIT_TRACE.md` for lifecycle changes.
- Append `changelogs.md` with dated batch notes.

### 1.3 Observability checks
Validate relevant log tags:
- `[HEARTBEAT]`
- `[CONSENSUS-DIAG]`
- `[SIGNAL-REJECTED]`
- `[AI-VOTE]`
- `[AUTHORITY-REJECT]` / `[AUTHORITY-REDUCED]` (authority gate replaces shadow mode)

### 1.4 Risk/execution invariants
- Verify every enabled entry path reaches the shared risk veto; raw-order engine paths are not covered until proven otherwise.
- Verify the provisional candidate reservation is excluded by owner identity, other pending risk counts in portfolio and symbol budgets, and the configured symbol list is exact; chart symbols are not implicitly added.
- Verify post-modifier minimum-lot handling honors both InpAllowMinLotRoundUp and InpMinLotRiskMultiplier.
- Treat the EA risk inputs and supported `risk.*` live overrides as explicit risk authorities. Compare effective risk logs with tier requests; a tier label is not the applied risk value.
- For strategy P&L, union contributor identities across all fills of a position; score only singleton positions and report multi-contributor/unattributed coverage separately.
- Deinit keeps explicit `CIndicatorManager::DestroyInstance()`.

### 1.5 Code quality requirements
- Memory safety: AI components must implement proper RAII with safe cleanup
- Input validation: All public methods must validate parameters and bounds
- Constants: Eliminate magic numbers; use defined constants for configuration
- Error handling: Provide meaningful error messages and graceful degradation

### 1.6 Artifact hygiene
- Compile-generated `.log/.txt` artifacts should be removed by default after compile runs.
- Keep artifacts only when explicitly requested.

## 2. Release Gate Template
Use this structure before promoting a batch:
- Build status: `PASS|FAIL`
- Runtime mode: `Tester|Demo|Live`
- Symbols tested:
- Entry/exit cadence and active strategy timeframe overrides verified from runtime logs:
- Effective risk and exact trading universe verified:
- Paired cold-window backtest completed for performance claims:
- Signal rate summary:
- Rejection breakdown:
- AI liveness summary:
- Risk rejection summary:
- Trade/shadow trade summary:
- Regressions:
- Rollback trigger status:

## 3. Operational Notes

### 3.1 Preferred MT5 mode
- Use persistent terminal sessions for manual testing.
- Avoid repeated `/config` relaunch loops when account state persistence is required.

### 3.2 WebView2 login crash contingency
- If `msedgewebview2.exe` login dialog crashes, continue in a persistent logged-in session (`/portable` recommended).

### 3.3 Symbol history contingency
- On tester history `Not found`, start with stable major pair (`EURUSD.0`) and then expand symbol basket.

## 4. Ownership
- Technical owner: maintainers changing `MultiStrategyAutonomousEA.mq5` and `Core/*` runtime modules.
- Documentation owner: implementer shipping the batch.
