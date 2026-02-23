# Web Build + Adjust + Debug

Use for websites and web apps where the main workload is iterative adjustments and debugging.

## Ideal use cases
- New page/feature implementation
- UI and UX adjustments
- State/interaction bugs
- Responsive and accessibility fixes

## Workflow
1. Capture baseline:
   - framework/runtime (`Next.js`, `React`, etc.)
   - current issue or requested adjustment
   - expected behavior
2. Reproduce quickly:
   - run dev server
   - confirm bug path in minimal steps
3. Implement targeted changes:
   - preserve design system and project conventions
   - avoid broad rewrites
4. Validate locally:
   - desktop and mobile layout pass
   - key interactions
   - console/network errors
5. Hardening pass:
   - edge states (empty/loading/error)
   - accessibility basics (labels, focus, keyboard)
   - no obvious performance regressions
6. Finalize:
   - summarize changed components/routes
   - note any follow-up cleanup

## Debug checklist
- Broken rendering: props/data flow, conditional rendering, null guards.
- State bugs: stale closures, race conditions, async ordering.
- Routing bugs: param shape, navigation guards, fallback pages.
- Styling regressions: CSS specificity, cascade order, breakpoint overrides.
- API issues: request shape, error handling, retry behavior.

## Output contract
- `Root cause`
- `Patch scope`
- `Validation checklist result`
- `Known follow-ups`
