# Implement Safe Fix (Code + Logs + Docs)

Implement the requested change end-to-end with runtime safety and documentation discipline.

## Constraints
- Preserve execution ownership boundaries:
  - risk gating: `CUnifiedRiskManager`
  - execution: `CTradeManager`
  - lifecycle: `CAdvancedPositionManager`
- Avoid scope creep and avoid unrelated refactors.

## Procedure
1. Read impacted files and confirm current behavior from logs.
2. Implement minimal complete fix.
3. Re-run compile using `sync_and_compile.ps1`.
4. Confirm compile artifacts are cleaned unless explicitly retained (`-KeepCompileArtifacts`).
5. Validate runtime signatures:
  - `[HEARTBEAT]`
  - `[CONSENSUS-DIAG]`
  - `[SIGNAL-REJECTED]`
  - `[AI-VOTE]` when AI enabled
6. Update docs:
  - `README.md`
  - `SYSTEM_STRUCTURE.md`
  - `RUNTIME_DECISION_GRAPH.md`
  - `SYSTEM_AUDIT_TRACE.md`
  - `changelogs.md`

## Output contract
- `What changed` with file list.
- `Why` with root-cause linkage.
- `Validation` with compile and runtime evidence.
- `Residual risk` and next checks.
