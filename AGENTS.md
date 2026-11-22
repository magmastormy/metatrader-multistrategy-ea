1. Respect the existing code, conventions, architecture, and user changes; inspect before editing.
2. Think systemically: trace data flow, control flow, ownership, and downstream effects.
3. Pursue supremacy in execution quality and autonomous problem-solving; never exceed user intent or safety constraints.
4. Fix root causes with the smallest coherent change; avoid symptom patches.
5. Preserve working behavior; avoid unrelated refactors and speculative features.
6. Verify references, build inputs, and runtime consumers before calling a file or symbol unused.
7. Do not delete user data, generated assets, or external state without explicit approval.
8. Separate source facts, measured evidence, assumptions, and unresolved hypotheses.
9. Keep risk controls fail-closed; never bypass shared validation or silently weaken limits.
10. Never treat missing prices, stops, or tick data as zero risk or permission to trade.
11. Give reservations explicit ownership; release only after confirmed failure or fill reconciliation.
12. Treat mixed or incomplete strategy P&L as inconclusive, not causal attribution.
13. Apply only supported configuration; disclose ignored overrides and preserve input authority.
14. Keep the configured symbol universe authoritative; never inject symbols silently.
15. Route new orders through shared validation, execution, and confirmation paths.
16. Follow the repository’s language, version, style, and dependency constraints.
17. Add focused regression tests for behavior changes when the project supports them.
18. Run narrow checks first, then relevant builds; report toolchain or environment limits.
19. Make no performance claim without reproducible, completed, correctly reset test evidence.
20. Keep documentation aligned with current code; mark historical findings as historical.
21. Update architecture notes when runtime contracts or ownership boundaries change.
22. Preserve unrelated work; review the diff and never overwrite user changes.
23. Keep credentials, secrets, and private environment settings out of code and logs.
24. Do not commit, push, branch, or publish unless the user explicitly requests it.
25. Finish with changed files, verification performed, and remaining risks stated plainly.
