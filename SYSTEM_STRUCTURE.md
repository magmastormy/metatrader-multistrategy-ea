# SYSTEM_STRUCTURE.md

## Document Metadata
- Last Updated: 2026-03-31
- Scope: Full structural description of runtime system
- Source of Truth: Current repository implementation

## 1. System Goal
Provide autonomous, multi-strategy trade decisions with clear ownership boundaries:
- signal generation and consensus
- pre-trade risk veto
- execution
- post-trade feedback and adaptation

The system prioritizes deterministic control flow, explicit diagnostics, and shadow-first rollout capability.

## 2. Top-Level Runtime Topology

### 2.1 Entrypoint and orchestration
- File: `MultiStrategyAutonomousEA.mq5`
- Responsibilities:
  - initialize mandatory runtime subsystems first and isolate optional AI/bootstrap failures behind readiness flags
  - validate active symbols and emit startup account-capacity diagnostics before live execution
  - reconstruct cooldown/trade-timing state from EA-owned open positions and deal history on startup
  - maintain cadence loops (new-bar/intrabar)
  - budget intrabar scans by symbol yield instead of blindly scanning the whole intrabar universe every cycle
  - apply per-symbol intrabar backoff after repeated low-yield or readiness-faulted scans
  - dispatch per-symbol evaluations
  - rank approved candidates across symbols before execution
  - own the non-AI confidence policy inputs for pipeline and validator stages
  - coordinate validator/risk/execution path
  - handle runtime telemetry and deinitialization

### 2.2 Per-symbol strategy domain
- Class: `CEnterpriseStrategyManager`
- One manager per managed symbol.
- Responsibilities:
  - hold registered strategies (core + AI adapters)
  - execute strategy voting and confidence aggregation
  - resolve cross-timeframe vote conflicts via `CTimeframeConsistency`
  - dispatch `OnNewBar` to each strategy using its registered timeframe
  - apply normalized weighted quorum rules by evaluation mode (new-bar vs intrabar eligible pool)
  - classify intrabar strategy participation as `OFF`, `PROBE`, or `LIVE` before pipeline work is spent
  - modulate live vote influence by role multiplier and rolling strategy `healthScore`
  - compute conviction using pipeline evidence (`readiness`, `context`, `cost`) rather than raw confidence alone
  - require both directional quality and support-ratio floors before full quorum can pass
  - allow a separately tagged `SPARSE_INTRABAR` lane for tightly gated one-sided single-voter packets
  - require minimum ready-live-weight participation and conflict deadband before directional selection
  - admit votes using the active pipeline confidence floor for that evaluation (including regime-relaxed thresholds)
  - expose veto codes (`zero_voter`, `single_voter_confidence`, `sparse_support`, `timeframe_conflict`, readiness-related gates) instead of generic quorum-miss text
  - expose per-cycle funnel snapshots and interval consensus diagnostics snapshots
  - emit consensus diagnostics
  - retain last-contributor context for attribution

### 2.3 Pipeline domain
- Class: `CUnifiedSignalPipeline`
- Responsibilities:
  - cache structural/indicator context once per symbol/timeframe/bar for reuse across strategy votes
  - apply trend/volatility/liquidity/structure/confidence filters
  - apply deterministic regime + cost viability pre-gate via `CRegimeEngine`
  - produce reusable evidence snapshot data (`readinessScore`, `contextScore`, `costScore`, effective confidence floor, soft-threshold pass`, readiness class, reuse/staleness flags)
  - allow bounded soft-threshold promotion when near-threshold confidence is supported by strong readiness/context evidence
  - tolerate transient regime data faults by reusing a recent same-context valid snapshot when safe
  - tolerate transient trend MA/ATR copy faults by reusing a bounded last-good trend snapshot instead of forcing full indicator-set churn
  - trigger bounded `CRegimeEngine` handle self-heal after repeated data faults
  - apply bounded weak-regime intrabar confidence threshold uplift (`min(base+cap, base*multiplier)`) using `CRegimeEngine` snapshot state as the authority
  - emit threshold-source telemetry (`[PIPELINE-THRESHOLD]`)
  - emit regime/cost veto telemetry (`[REGIME-STATE]`, `[COST-GATE]`, `[ENTRY-VETO]`)
  - normalize decision hygiene before final consensus acceptance without hot-path hedging neutralization

### 2.4 AI adaptation domain
- Class: `CAIStrategyOrchestrator`
- Responsibilities:
  - register qualified strategy identities (`symbol::name`)
  - maintain performance and weight state
  - adapt weights and feed updates back to managers
  - remain optional at runtime; orchestration/adaptation failure disables AI adaptation without violating trade/risk/execution ownership

### 2.5 Risk domain
- Class: `CUnifiedRiskManager`
- Responsibilities:
  - single pre-trade veto authority
  - two-phase validation (`pre-size`, `post-size`)
  - daily/portfolio risk budgeting and drawdown controls
  - mark-to-market aware daily budget enforcement
  - hard veto on unprotected (no-SL) open positions
  - enforce cluster-aware governance (same-symbol opposing-cluster mutex + per-cluster caps) through `CRiskValidationGate`
  - split budget telemetry (`entry`, `mtm`, `open_exposure`, `effective`) for operator clarity
  - expose unprotected-position state for runtime remediation workflows
  - executed-risk registration after successful synchronous sends, scaled by actual fill ratio

### 2.6 Execution domain
- Class: `CTradeManager`
- Responsibilities:
  - convert approved intent into actual order send
  - run synchronous market execution by default
  - enforce execution-level safety checks
  - configurable broker fill policy (IOC/FOK/RETURN)
  - bounded retries for transient broker retcodes
  - single bounded retry behavior for `LOCKED` / `FROZEN` retcodes
  - reprice market orders at submit time and rebuild protective SL/TP from the current market price
  - emergency-aware protective modification flow
  - expose execution receipt status (`requestId`, retcode, requested/fill volume, retry count, avg fill price) for post-send handling

### 2.7 Position lifecycle domain
- Class: `CAdvancedPositionManager`
- Responsibilities:
  - trailing/BE/partial-close lifecycle handling
  - reconstruct lifecycle milestones for already-open positions after restart
  - managed by EA magic scope

### 2.8 Shared indicator domain
- Class: `CIndicatorManager`
- Responsibilities:
  - indicator handle cache and shared access
  - periodic unused release
  - explicit singleton teardown on deinit

## 3. Managed Strategies

### 3.1 Core retained set
- Momentum
- Trend
- Fibonacci
- Elliott Wave
- Support/Resistance
- Unified ICT
- Candlestick

Retired standalone strategy families (RSI, Mean Reversion, Swing, Volatility, MACD, Bollinger, Ichimoku, Harmonic, legacy SMC wrapper) are removed from active runtime inventory.
The legacy strategy configuration module (`Config/StrategyConfig.mqh`) has also been removed to avoid stale retired-strategy references.

### 3.2 AI strategy adapters
- Neural Network adapter (`CAIStrategyAdapter`)
- Transformer adapter (`CTransformerAIStrategyAdapter`)
- Ensemble adapter (`CEnsembleAIStrategyAdapter`)

**Memory Safety**: All AI adapters implement RAII patterns with proper cleanup of transformer models and comprehensive error handling. Constants are used throughout to eliminate magic numbers.
**Runtime Efficiency**:
- inference is cached per bar in the adapter or backing AI module so repeated same-bar `GetSignal(...)` calls do not rerun transformer/NN forward passes
- feature-build/inference failures are cached as `NONE` for the rest of the bar to avoid hot-loop retries on unchanged data
- `CNextGenStrategyBrain` now runs as a local-only transformer path and exposes dashboard-safe readiness/runtime-mode state instead of legacy cloud/hybrid labels
- `CEnsembleMetaLearner` now aggregates model class probabilities via `GetPredictions(...)` and uses container ownership correctly (`CArrayObj::FreeMode(true)`) to avoid double-delete behavior
- `CNeuralNetworkStrategy`, `CUncertaintyQuantifier`, and `CMarketDataProcessor` now use ring-buffered histories instead of heap churn or `Delete(0)`/array-shift patterns

### 3.3 Curated runtime profile
Curated mode can restrict runtime active set to a smaller operational profile while preserving full retained implementation in code.

### 3.4 Institutional governance roles
- Strategy registration now includes explicit governance metadata:
  - role: `PRIMARY_ALPHA`, `CONTEXT_FEATURE`, `SHADOW_RESEARCH`
  - cluster: `TREND_CLUSTER`, `MEAN_REVERSION_CLUSTER`, `STRUCTURE_CLUSTER`, `NONE`
- Default policy:
  - all enabled retained strategies are registered as `PRIMARY_ALPHA` and vote live
  - per-strategy inputs gate registration (disabled strategies are not registered into the pool)
- Opt-in smoke-test intrabar controls are available for `Fibonacci` and `Support/Resistance`; the default intrabar roster remains conservative.
- Strategy trust is continuous, not purely binary:
  - `healthScore` is updated from realized closed-trade outcomes
  - live vote weight is scaled by reliability instead of only live/shadow membership
- Manager-level controls are exposed by strategy name for role, cluster, live-vote eligibility, and shadow mode.

### 3.5 Unified ICT Architecture
The `StrategyUnifiedICT` module operates as a dedicated institutional-flow container with strict rule adherence:
- **FVG & Order Block Models:** detection is strictly gap-based (no body color/size filters), and mitigation requires a full boundary close, not just midpoint touches. Source order blocks are dynamically anchored to 3-bar displacement impulses.
- **Session Context:** `CSessionGapDetector` tracks NDOG/NWOG opening gaps and fill percentages. `CICTKillZones` enforces Silver Bullet windows. `CAMDDetector` defines Accumulation/Manipulation/Distribution phase sweeps to time structural reversals.
- **Confluence Scoring:** Replaces flat array counting with a weighted 0-130 point scale (`ScoreConfluences(...)`). Highest weights are given to Order Block presence (30pts) and FVG/Sweeps (20pts).
- **Dynamic Confidence:** `ComputeEntryConfidence(...)` generates probabilistic confidence scalars dynamically using Market Structure break types (CHoCH = high, BOS = mid) combined with AMD Distribution phase alignment.
- **Institutional TP Hierarchy:** `CalculateTakeProfits(...)` bypasses fixed Risk:Reward scaling. Targets are structurally anchored (TP1 = Opposing FVG CE, TP2 = Opposing OB CE, TP3 = Unswept Liquidity).
- **Position Scaling:** `CICTPositionSizer` governs trade volume using an equity-aware point distance formula and enforces hard trailing daily/weekly portfolio drawdown guards.

### 3.6 Support/Resistance & Trendline Architecture
The `StrategySupportResistance` and `TrendlineDetector` operate under a rigid, non-repainting framework optimized for look-ahead safety and chart performance:
- **ATR-Driven Clustering:** S/R levels and Trendline swings are normalized using dynamic ATR thresholds. The clustering algorithm merges nodes not by an arithmetic average, but by promoting the highest-strength focal line.
- **Look-Ahead Bias Elimination:** All logic within `CTrendEntryTypes`, `CSRBounceStrategy`, `CSRBreakoutStrategy`, and `CSupportResistanceDetector` strictly evaluates signal breaks and touches against `bar[1]` (completed-bar confirmation), blocking forward-sniffing.
- **Dynamic Chart Optimization:** Instead of emitting unlimited background markers, graphical line rendering passes through a bubble-sort array capping output strictly to the Top 8 highest-strength horizontal zones and Top 6 slope-validated trendlines.
- **ATR Position Scaling:** Fixed pips have been removed entirely. `CADXPositionSizing` dynamically calculates Lot Size exclusively using exact market Tick Sizes/Values relative to physical price distance.
- **Indicator Handle Hygiene:** clean detector paths now cache ATR handles at initialization and reuse them during repeated detection/touch passes instead of creating and releasing indicator handles inside hot methods.

## 3.7 AXIOM Refactor Notes
- The AXIOM refactor batch was a structural efficiency pass, not a strategy-logic rewrite.
- Main outcomes:
  - removed dead AI/control-flow branches and no-op lifecycle surface
  - stabilized AI hot paths around bar-cached inference
  - replaced repeated O(n) history shifts with fixed-size ring buffers in AI data structures
  - separated mandatory runtime bootstrap from optional AI/bootstrap subsystems
  - tightened detector-level indicator lifecycle in clean hot paths

## 4. Decision Pipeline (Signal to Execution)

### 4.1 Cadence selection
- Startup emits per-symbol `[ACCOUNT-CAPACITY]` diagnostics before the first live scan and reconstructs `[TRADE-STATE]` so inherited EA positions carry cooldown forward across restarts.
- Shared validator spread-shock state is symbol-scoped, not portfolio-global, so cross-symbol spread contamination cannot veto otherwise valid candidates.
- New-bar path: conservative scan cadence.
- Intrabar path: timer-driven scans when enabled.
- Symbol evaluation start index rotates each cycle to reduce deterministic first-symbol concentration.
- Intrabar symbol selection is yield-aware: recent near-miss symbols, recent generators, and readiness-healthy symbols are prioritized first.
- Per-symbol intrabar backoff tiers escalate from base cadence to `30s`, then `60s`, then suspension until a new bar resets the symbol.

### 4.2 Consensus
- Manager computes strategy votes and confidence.
- Mixed-timeframe conflicts are resolved with `CTimeframeConsistency` before final consensus acceptance.
- Quorum is evaluated via normalized weighted conviction pooling:
  - adjusted live weight = `base strategy weight x role multiplier x healthScore reliability multiplier`
  - ready live weight = `adjusted live weight x pipeline readinessScore`
  - per-direction conviction = `sum(ready live weight x conviction_i)` for agreeing live voters
  - conviction is confidence shaped by pipeline `contextScore`, `readinessScore`, and `costScore`
  - directional quality = `direction conviction / direction weight`
  - support ratio = `direction weight / total ready live weight`
  - direction passes full quorum if `directional_quality >= InpQuorumThreshold`, support ratio clears the new-bar/intrabar floor, agreeing voters clear the effective minimum, and `readyLiveWeight / totalLiveWeight >= InpConsensusMinReadyWeightRatio`
- if both directions pass, higher score wins unless the spread is inside the configured conflict deadband, in which case consensus is vetoed to `TRADE_SIGNAL_NONE`
- intrabar may instead admit a `SPARSE_INTRABAR` decision when exactly one direction has one voter and readiness/context/cost/support/coverage thresholds all remain high
- Vote admission into quorum reuses the pipeline's effective confidence threshold for that cycle, preventing pipeline-approved relaxed-threshold signals from being dropped before consensus.
- Consensus may fail by:
  - raw no-vote
  - quorum miss (threshold and/or min voters)
  - intrabar ineligibility
  - filter rejection
- Post-quorum nullification is emitted as `[CONSENSUS-VETO]` when timeframe consistency or the intrabar single-voter floor clears an otherwise qualified candidate.

### 4.3 Validation
- `CAdvancedSignalValidator` applies profile-dependent gating.
- Validator profiles are input-configurable by scan mode (new-bar vs intrabar): minimum confidence, minimum strategy confluence, and minimum quality score.
- Validator quality now consumes upstream decision-path evidence (`conviction`, `readiness`, `context`, `cost`, `diversity`, `freshness`) instead of only raw confidence/confluence.
- Near-threshold confidence and confluence can soft-pass within bounded margins when the broader evidence profile is strong.
- Rejected signals emit reasoned logs.
- Entry-governance blocks (cooldown, total-position cap, unresolved unprotected positions, per-symbol capacity) apply after validation so approved signals remain visible in diagnostics even when sends are paused.
- Cost viability parameters are explicit (`spread/ATR`, spread-shock cooldown).

### 4.4 Risk gate
- Pre-size validation to accept/reject candidate conditions.
- Position sizing computes lot.
- Post-size validation with actual lot before execution.
- Unprotected-position remediation runs before new-entry scans; unresolved states pause new entries until resolved.
- Trade requests carry role/cluster/contributor context for cluster-aware risk governance.

### 4.5 Execution branch
- Cooldown and capacity logic are entry-only gates; they do not suppress consensus or validator execution.
- The runtime stages every risk-approved opportunity as a candidate and ranks them across the full symbol scan before sending.
- Shadow mode: logs virtual trade, no send.
- Live mode: send through `CTradeManager`.
- Startup emits `[EXECUTION-MODE]` so shadow/live posture is explicit before the first scan.
- Startup rejects unsupported non-hedging account models before runtime ownership becomes ambiguous.
- Live comment tagging carries compact cluster code (`K:T/R/S/N`) for deterministic open-position cluster attribution.
- Execution receipts and fill deltas are surfaced to the EA so post-send accounting uses actual fill state rather than requested size alone.

### 4.6 Post-trade feedback
- Successful trades register executed risk usage.
- Close transactions feed manager/orchestrator adaptation and `PerformanceAnalytics`.
- NN attribution maps prediction IDs through close labeling.
- AI performance feedback records prediction/outcome pairs using position-mapped prediction times.

### 4.7 Deterministic event separation
- Tick and timer handlers share a second-level signal-evaluation gate.
- This prevents duplicate strategy consensus passes in the same wall-clock second.
- Connectivity gating blocks signal evaluation while terminal connection is down.

## 5. Data and Control Boundaries

### 5.1 What can veto a trade
- Validator failure.
- Unified risk rejection.
- Execution failure after approval.

### 5.2 What cannot bypass risk
- Strategy confidence alone does not bypass unified risk gate.
- AI strategy adapter votes do not bypass validator or risk stages.

### 5.3 Execution centralization
- Runtime decision path executes through `CTradeManager`.

## 6. Runtime Modes

### 6.1 Shadow mode
- Full stack decisioning, no live order send.
- Used for burn-in and diagnostics.

### 6.2 Live mode
- Full stack decisioning with real execution.
- Requires extra monitoring window post-activation.

## 7. Observability Model

### 7.1 Key log families
- Decision heartbeat: `[HEARTBEAT]`
- Startup state: `[ACCOUNT-CAPACITY]`, `[TRADE-STATE]`
- Conversion funnel: `[HEARTBEAT-FUNNEL]`, `[CONVERSION-RATES]`
- Entry suppression telemetry: `[ENTERPRISE-BLOCKED]`
- Risk budget split: `[RISK-BUDGET]`
- Unprotected remediation: `[RISK-UNPROTECTED]`
- External capacity denial: `[CAPACITY-EXTERNAL]`
- Consensus diagnostics: `[CONSENSUS-QUORUM]`, `[CONSENSUS-DIAG]`, `[CONSENSUS-ROOT]`, `[CONSENSUS-SNAPSHOT]`, `[CONSENSUS-STRATEGY]`
- Post-quorum veto diagnostics: `[CONSENSUS-VETO]`
- Governance diagnostics: `[CONSENSUS-ROLE]`, `[CONSENSUS-CLUSTER]`, `[ROLE-CLUSTER]`
- Strategy reject attribution: `[STRATEGY-REJECTS]`
- Signal rejection reasons: `[SIGNAL-REJECTED]`
- Candidate ranking telemetry: `[SCAN-CANDIDATE]`, `[SCAN-DECISION]`
- Threshold source tracing: `[PIPELINE-THRESHOLD]`
- Regime/cost viability tracing: `[REGIME-STATE]`, `[COST-GATE]`, `[ENTRY-VETO]`, `[TrendEngine][READINESS-FAULT]`
- No-signal deadlock alerting: `[NO-SIGNAL-ALERT]`
- Cluster risk governance tracing: `[RISK-CLUSTER]`, `[RISK-MUTEX-BLOCK]`
- AI liveness: `[AI-VOTE]`
- confirmed deals: `[TRADE-CONFIRMED]`
- Shadow actions: `[SHADOW-TRADE]`
- Execution outcomes: `[TRADE-SUCCESS]`, `[TRADE-ERROR]`, `[EXECUTION-RECEIPT]`, `[FILL-DIFF]`

### 7.2 Primary operational KPIs
- no-signal ratio
- validator rejection ratio
- risk rejection ratio
- generated-to-send conversion rate
- quorum pass rate
- validated-to-risk-approved conversion rate
- AI vote activity per symbol per adapter
- shadow/live trade throughput

## 8. Configuration Surface

### 8.1 Runtime controls
- Symbol basket and cadence controls
- Strategy enable flags
- AI feature toggles
- risk limits and drawdown controls
- shadow mode toggle

### 8.2 Tester profiles
- `shadow_session_open.ini`
- `shadow_session.ini`
- `shadow_session_mt5_tester.ini`
- `shadow_session_inputs.ini`
- `shadow_session.set`

## 9. Lifecycle Safety

### 9.1 Init safety
- component initialization order ensures execution/risk dependencies are ready before runtime.

### 9.2 Deinit safety
- dynamic allocations released
- singleton indicator manager explicitly destroyed

### 9.3 Build artifact hygiene
- compile script is expected to clean generated compile `.log/.txt` artifacts after run unless explicitly preserved.

## 10. Future Change Rules (Structure-Level)
Any structural change must update all of:
- `SYSTEM_STRUCTURE.md`
- `RUNTIME_DECISION_GRAPH.md`
- `SYSTEM_AUDIT_TRACE.md`
- `README.md`
- `changelogs.md`

## 11. 2026-03-25 Runtime Integrity Deltas
- `CUnifiedSignalPipeline` now owns two distinct layers of state:
  - current-cycle evidence (`m_lastEvidence`)
  - same-bar structural cache (`m_cachedStructuralEvidence`)
- Structural cache now preserves the original engine readiness contract for the bar; later strategy evaluations cannot silently upgrade a warmup/faulted engine into a ready contributor.
- Pipeline startup is now fail-closed for required diagnostics/protection/engine components; `CEnterpriseStrategyManager` aborts initialization if the pipeline cannot be constructed cleanly.
- `CLiquidityEngine` now tracks symbol-scoped point geometry internally instead of using chart-symbol geometry.
- `CRegimeEngine` now resets spread-shock cooldown state on symbol/timeframe context changes, keeping cost gating symbol-local under multi-symbol scans.
- `CPositionSizer` now prefers shared ATR handles from `CIndicatorManager`, reducing split ownership of sizing-critical indicator lifecycle.
- `CTradeManager` execution ownership remains unchanged, but its market-send contract is now three-stage:
  - preflight viability check
  - broker submit
  - bounded fill confirmation
- The EA scan loop now carries a cycle identifier across no-trade, validation, block, candidate, decision, and execution logs for one-cycle traceability.

## 12. 2026-04-01 Default Runtime Remediation
- `CTrendEngine` still owns trend-readiness state, but ATR mature-series failures are now treated as recoverable data faults:
  - attempt bounded ATR fallback from price series
  - if fallback succeeds, emit degraded readiness-state telemetry and continue with valid evidence
  - if fallback fails, degrade explicitly instead of silently pinning the symbol in false warmup
- `MultiStrategyAutonomousEA` still owns scan scheduling, but now distinguishes idle cycles from active work before entering the per-symbol loop. This reduces wasted throughput and makes quiet-cycle accounting more truthful.
- `CEnterpriseStrategyManager` still owns intrabar governance, and `Support/Resistance` now respects the configured probe toggle instead of being silently forced off.
- `CStrategyElliottWaveEnhanced` ownership is unchanged; this batch only repaired MT5 enum usage and removed local min-confidence shadowing so the inherited base threshold remains authoritative.

## 13. 2026-04-01 Strategy Registry + AI Runtime Extension
- `CStrategyRegistry` is now the activation authority for strategy families and EA mode (`InpEAMode`):
  - indicator strategies and AI adapters are registered from one roster
  - unsupported mixes degrade to a viable effective mode during startup
  - startup telemetry emits `[STRATEGY-REGISTRY]`
- `MultiStrategyAutonomousEA` still owns manager bootstrap, but registration is now registry-driven rather than split across independent boolean branches.
- EA mode affects the post-consensus admission contract:
  - `HYBRID` can require aligned indicator + AI contributors when both families are active
  - `AI_ASSISTED` keeps indicators primary and can add bounded confidence uplift from aligned AI contributors
  - `INDICATOR_FILTERED` requires AI-primary candidates to survive indicator confirmation
- Intrabar scheduling still remains EA-owned:
  - primary budget selection is unchanged
  - a bounded keepalive pick can now revive one symbol when hybrid cadence would otherwise fully starve intrabar work
- `CTrendEngine` now treats mature-series MA fragility similarly to ATR fragility:
  - partial readiness no longer forces immediate hard failure
  - manual EMA fallbacks can reconstruct fast/medium/slow series
  - snapshot reuse remains the final graceful-degradation path
- The AI feature stack is now split more cleanly:
  - transformer adapters use right-sized models and actual sequence lengths
  - `CNeuralNetworkStrategy` validates feature integrity before inference/training
  - NN tail features can be augmented with transformer-encoded context rather than relying on raw handcrafted tail features only
