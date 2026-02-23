# Maintenance Protocol

## Document Metadata
- Last Updated: 2026-02-22
- Scope: Forward update contract

This document defines mandatory implementation, validation, and documentation steps for future batches.

## 1. Mandatory Update Checklist

### 1.1 Code and config
- Update runtime code.
- Update affected tester/session inputs (`shadow_session*.ini`, `shadow_session.set`) when behavior depends on profile settings.

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
- `[SHADOW-TRADE]` (if shadow mode)

### 1.4 Risk/execution invariants
- Unified risk remains pre-execution veto authority.
- Execution remains `CTradeManager`-owned.
- Deinit keeps explicit `CIndicatorManager::DestroyInstance()`.

### 1.5 Artifact hygiene
- Compile-generated `.log/.txt` artifacts should be removed by default after compile runs.
- Keep artifacts only when explicitly requested.

## 2. Release Gate Template
Use this structure before promoting a batch:
- Build status: `PASS|FAIL`
- Runtime mode: `Shadow|Live`
- Symbols tested:
- Cadence validated (`new-bar`, `intrabar`):
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
