# Release Doc Sync

Use this workflow after implementation to keep project documentation internally consistent.

## Required updates
1. `README.md`
2. `SYSTEM_STRUCTURE.md`
3. `RUNTIME_DECISION_GRAPH.md`
4. `SYSTEM_AUDIT_TRACE.md`
5. `changelogs.md`

## Method
1. Diff actual code changes first.
2. Update architecture docs only where behavior/ownership changed.
3. Update runtime graph with new decision branches and gates.
4. Add dated changelog entry with:
  - root cause
  - implementation summary
  - validation evidence
  - rollback notes (if applicable)
5. Verify `AUDIT_REPORT.md` remains intentionally empty unless a new formal audit is requested.

## Output contract
- concise change summary
- exact files touched
- explicit confirmation that docs match runtime behavior
