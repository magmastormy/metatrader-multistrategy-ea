# Python Debug Triage

Use when Python behavior is failing and root cause is unknown.

## Objectives
- Move from symptom to root cause quickly.
- Produce a verified fix with regression protection.

## Triage flow
1. Capture failure signature:
   - traceback
   - failing command/test
   - environment details
2. Reproduce reliably in the same environment.
3. Classify issue type:
   - runtime exception
   - logic/output mismatch
   - flaky timing/concurrency
   - dependency/version conflict
4. Instrument minimally:
   - targeted logs/assertions
   - no noisy permanent logging
5. Patch root cause (not symptoms).
6. Validate:
   - rerun failing case
   - run nearest test module(s)
   - run full suite if feasible
7. Add regression test for discovered bug.

## Common root-cause checklist
- Incorrect assumptions about `None`, empty data, or default values.
- Mutable shared state across requests/tasks.
- Timezone and datetime parsing inconsistencies.
- Silent exception swallowing.
- Version drift in dependencies.

## Output contract
- `Failure signature`
- `Root cause`
- `Fix`
- `Regression test added`
