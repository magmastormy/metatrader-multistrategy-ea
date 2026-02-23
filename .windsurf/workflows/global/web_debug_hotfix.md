# Web Debug Hotfix

Use for urgent web regressions where you need rapid but production-safe fixes.

## Objectives
- Isolate the regression quickly.
- Patch with the least risky change.
- Validate impacted critical paths before closing.

## Procedure
1. Triage severity:
   - user-facing broken flow?
   - data loss/security concern?
   - isolated UI issue?
2. Reproduce from logs and steps.
3. Locate offending commit/path and narrow to specific component/module.
4. Apply hotfix:
   - minimal code delta
   - explicit guards for edge cases
5. Validate critical paths:
   - login/session (if applicable)
   - primary conversion flow
   - API failure behavior
6. Add a regression test when feasible.
7. Document:
   - incident cause
   - fix rationale
   - rollback trigger

## Safety rules
- Never mask errors silently; log actionable context.
- Prefer deterministic fixes over timing hacks.
- Keep performance overhead low in hotfix code paths.
