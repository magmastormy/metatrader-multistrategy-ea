# Shadow Run Triage (MT5)

Execute a shadow-first validation pass and triage blocking tester issues.

## Objectives
- Confirm runtime decisions are being generated.
- Confirm AI voters (NN/Transformer/Ensemble) show non-zero activity.
- Detect broker/symbol history blockers before live rollout.

## Runbook
1. Ensure tester config enables shadow mode and intrabar settings for managed symbols.
2. Start terminal/tester in a persistent session (avoid repeated login loop launches).
3. Monitor logs during run for:
  - history sync errors (`[Not found]`)
  - symbol availability mismatches
  - repeated `no_signal` saturation
4. If a symbol fails history sync:
  - switch primary test symbol to a known available symbol (for this setup: `EURUSD.0` first)
  - keep synthetic indices as optional additional symbols only when data exists.
5. Collect a compact report:
  - scans
  - no_signal ratio
  - AI vote counts by symbol
  - trades opened (or shadow trade intents)

## Acceptance gate
- `no_signal_ratio < 97%` on intrabar-enabled symbols.
- Transformer and Ensemble both emit vote activity.
- Orchestrator shows non-zero registered strategy count.
- No lifecycle leak warnings at deinit.
