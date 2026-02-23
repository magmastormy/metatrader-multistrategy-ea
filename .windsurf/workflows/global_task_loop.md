# Global Task Loop (Any Coding Task)

Use this as the default workflow when the task does not require a specialized flow.

## Goals
- Deliver complete solutions, not partial drafts.
- Keep edits minimal, testable, and reversible.
- Provide clear evidence for behavior changes.

## Universal execution loop
1. Define target outcome in one sentence.
2. Scan relevant files/logs only (keep context tight).
3. Identify root cause or implementation gap.
4. Implement the smallest complete change set.
5. Run project-appropriate validation:
   - compile/build
   - tests
   - smoke run
6. Check for regressions in adjacent areas.
7. Update docs/changelog when behavior or interfaces changed.
8. Provide final report:
   - what changed
   - why
   - proof
   - residual risk

## Guardrails
- No scope creep beyond requested goal.
- No destructive git operations unless explicitly requested.
- No claims without validation evidence.
- Remove temporary artifacts unless intentionally retained for debugging.

## Output format
- `Summary`
- `Changes`
- `Validation`
- `Risks`
- `Next step` (optional)
