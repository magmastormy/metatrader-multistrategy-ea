# System Audit Trace

## Document Metadata
- Last Updated: 2026-04-08
- Scope: Runtime lifecycle and ownership trace

## Scope
- Entry point: `MultiStrategyAutonomousEA.mq5`
- Symbol decision manager: `Core/Management/EnterpriseStrategyManager.mqh`
- Filter pipeline: `Core/Pipeline/UnifiedSignalPipeline.mqh`
- AI orchestrator: `Core/AI/AIStrategyOrchestrator.mqh`
- AI adapters:
  - `Core/Strategy/AIStrategyAdapter.mqh`
  - `Core/Strategy/TransformerAIStrategyAdapter.mqh`
  - `Core/Strategy/EnsembleAIStrategyAdapter.mqh`
- Risk authority: `Core/Risk/UnifiedRiskManager.mqh`
- Execution authority: `Core/Trading/TradeManager.mqh`
- Position authority: `Core/Trading/AdvancedPositionManager.mqh`

## Runtime Lifecycle

### 1. OnInit
- Validate terminal and trading permissions.
- Initialize mandatory execution/risk/runtime systems.
- Emit explicit `[EXECUTION-MODE]` startup telemetry for shadow vs live posture.
- Reject unsupported non-hedging account models before runtime ownership is established.
- Apply execution safety controls (fill mode, slippage, protective modify cooldown) before trade-manager bootstrap.
- Initialize optional AI subsystems conditionally by flags and convert failures into readiness-state degradation instead of fatal startup aborts.
- Initialize performance analytics before unified-risk bootstrap.
- Validate active symbols and emit `[ACCOUNT-CAPACITY]` affordability diagnostics before the first scan.
- Build the active-only strategy registry, then create per-symbol managers and register only enabled strategies and enabled AI adapters.
- Rebuild scheduler state only after manager bootstrap so symbol-bar times, intrabar timers, pending new-bar work, and scan-state backoff remain a single aligned authority.
- Treat curated mode as a baseline/default profile only; explicit strategy enables remain authoritative instead of being rewritten away at runtime.
- Reconstruct `[TRADE-STATE]` / cooldown timing from EA-owned history and open positions.
- Register orchestrator strategy identities.
- Prime one pending new-bar scan per validated symbol so startup cannot produce a fully idle manager fleet with zero first-pass evaluations.

### 2. Tick/Timer cycle
- Run `ProcessTradingLogic`.
- Maintain NN learning cycle.
- Enforce terminal connectivity gate before signal evaluation.
- Enforce deterministic second-level signal evaluation separation between tick/timer events.
- Run deterministic unprotected-position remediation sweep before entry evaluation.
- Keep symbol evaluation active during cooldown/capacity veto windows so blocked-entry behavior remains observable.
- Rotate symbol evaluation start index each cycle to reduce fixed-order concentration.
- Self-reconcile cadence scheduler state if any scheduler array drifts away from the active symbol set before new-bar detection.
- Detect new-bar events per symbol.
- Carry pending new-bar work across cycles and spend the per-cycle heavy-evaluation budget on those symbols before any intrabar work.
- Run intrabar scans when eligible.
- Honor the global cadence override: `InpSignalScanOnNewBarOnly=true` disables timed intrabar scheduling even if strategy-level intrabar governance is `LIVE`, and startup emits `[CADENCE-WARNING]` when that override is active.
- Budget intrabar scans by symbol yield and apply per-symbol backoff after repeated low-yield or readiness-faulted intrabar passes.
- Emit heartbeat funnel and conversion-rate telemetry at configured diagnostics interval.

### 3. Signal path
- Manager consensus + confluence.
- Strategy `OnNewBar(...)` prepares per-bar state only; consensus owns the single authoritative `GetSignal(...)` invocation so bar-scoped signal state is not consumed twice.
- Manager applies role/cluster governance and evaluates quorum via normalized weighted conviction pooling.
- **Dynamic weight decay** (Batch 41): strategies filtering ≥ 3 consecutive cycles have live weight decayed to reduce denominator bloat; weight recovers when strategy votes again.
- Manager classifies intrabar strategies as `OFF`, `PROBE`, or `LIVE` before pipeline work is spent.
- Explicit intrabar eligibility now maps enabled strategies into real `LIVE` intrabar voting, so operator-facing `intrabar=true` settings match the runtime voter pool.
- Governance startup logs now mark disabled strategies as `INACTIVE` in the intrabar summary instead of implying they are live because a different profile left the raw input toggles enabled.
- **Adaptive quorum thresholds** (Batch 41): manager calculates `effectiveQualityThreshold` and `supportFloor` based on actual active voter count:
  - 1 active voter: directional quality ≥ 0.40, support ≥ 0.15
  - 2 active voters: directional quality ≥ 0.48, support ≥ 0.30
  - 3+ active voters: directional quality ≥ standard threshold, support ≥ scan-mode floor
  - Prevents impossible quorum math where inactive strategies inflated weight pool and rejected legitimate votes.
  - Adaptive one-/two-voter quality thresholds now respect the current base quorum so user-lowered quorum profiles are not silently re-hardened by stale fixed fallback thresholds.
- Manager quorum requires directional quality, support-ratio floors, effective min voters, minimum ready-live-weight participation, and conflict-deadband separation.
- Manager can emit a separate `SPARSE_INTRABAR` decision class for tightly gated one-sided single-voter intrabar packets.
- **Detailed veto diagnostics** (Batch 41): manager emits specific veto codes with numeric evidence instead of generic `zero_voter` / `single_voter_confidence` placeholders.
- Manager vote admission now uses the pipeline's effective confidence floor for the current evaluation, avoiding pipeline/quorum drift when regime-aware relaxation is active.
- Manager live vote influence is modulated by rolling strategy `healthScore` rather than treating every enabled strategy as equally trusted at all times.
- Manager emits consensus root-cause attribution snapshots for no-signal diagnostics.
- Manager emits strategy-level none-reason attribution for core curated contributors.
- Pipeline now includes deterministic regime/cost viability gate before validator.
- Pipeline caches structural engine state once per symbol/timeframe/bar and carries a shared evidence snapshot (`readiness`, `context`, `cost`, readiness class, reuse/staleness`) forward through consensus and validation.
- Pipeline and validator both support bounded soft-pass behavior for near-threshold candidates when the broader evidence profile is strong.
- Pipeline preserves admitted confidence after threshold passage instead of attenuating surviving packets a second time before quorum and validator.
- `CRegimeEngine` may reuse a recent valid same-context snapshot on transient warmup / copy / handle-init faults and performs bounded handle reset after repeated data faults.
- `CTrendEngine` now fails closed on partial-readiness states instead of pushing half-ready MA/ATR data downstream; it may still reuse a bounded last-good trend snapshot on transient MA/ATR copy faults and emits `[READINESS-STATE]` reuse telemetry.
- Pipeline threshold adaptation now uses `CRegimeEngine` snapshot state and dedicated non-AI confidence floors instead of AI-threshold coupling.
- Validation is now split by ownership:
  - manager owns structural admission (`confidence`, `confluence`, directional `quality`, support, effective minimum voters)
  - validator owns only exogenous market sanity (`spread`, `time`, `session`, `volatility`, cost viability) when manager-owned admission mode is enabled
- Validator profile inputs still exist by scan mode (new-bar vs intrabar), but in normal runtime they are telemetry/fallback surfaces rather than a second structural veto layer.
- Validator still consumes manager quorum facts (`effectiveMinVoters`, `directionalQuality`, `supportRatio`) together with conviction/readiness/context/cost evidence so exogenous validation telemetry stays aligned with the already-authoritative manager decision.
- Strategy overrides that bypass base-class `GetSignal(...)` now emit explicit decision tags, and manager defensively downgrades any remaining placeholder abstentions so they cannot silently dilute ready-live quorum math.
- Entry gates (cooldown, total-position cap, unprotected-position veto, per-symbol capacity) now apply after validation and before unified risk so approved-but-blocked signals are still logged.
- AI vote generation is same-bar cached:
  - neural votes reuse `GetNeuralSignalCached(...)`
  - transformer and ensemble adapters reuse cached inference results until the bar changes
  - failed feature-build/inference results are cached as `NONE` for the rest of the bar
- `CNextGenStrategyBrain` now follows a single local-transformer path with ring-buffered market data history and no dead Python/cloud bridge branch.
- Duplicate component-local `SignalDiagnostics` sinks have been removed from Elliott, pipeline, and orchestrator paths so manager/runtime telemetry stays authoritative.
- Risk gating (pre-size then post-size).
- Risk gate now evaluates cluster governance (mutex + caps) using request context and open-position cluster tags.
- Pipeline confidence gate emits threshold-source metadata and uses bounded weak-regime intrabar uplift.
- Trend ADX failures degrade to neutral/ranging context with bounded ADX-handle self-heal.
- ATR stop-distance fallback when indicator read fails.
- Risk-approved opportunities are staged as ranked candidates across the full symbol scan before shadow or live execution.
- Live execution captures broker receipt state, price/slippage/latency telemetry, and risk registration scales consumed entry budget by actual fill ratio.
- Per-symbol capacity checks include explicit external-position block telemetry.

### 4. Post-trade path
- Transaction callback updates manager/orchestrator performance.
- Transaction callback records confirmed close results into `PerformanceAnalytics`.
- NN attribution maps prediction IDs and labels closes (online-training gate controlled).

### 5. Housekeeping
- Position manager lifecycle actions.
- Periodic telemetry logs.
- Indicator cache release policy.
- Shutdown now emits `[TERMINATION-SNAPSHOT]` with final heartbeat counters before deinit cleanup.

### 6. OnDeinit
- Release managers and dynamic strategy allocations.
- Managers explicitly deinitialize owned strategies before deleting them to avoid teardown drift at shutdown.
- Deinitialize subsystems.
- Explicit `CIndicatorManager::DestroyInstance()`.
- Orchestrator report emission is single-source (destructor-owned) to avoid duplicate shutdown reports.
- **Memory Safety**: AI adapters now properly clean up transformer models in destructors.
- **Error Handling**: Enhanced validation in feature vector construction and attribution systems.

## Observability Surface
- Decision: `[SIGNAL]`, `[SIGNAL-REJECTED]`, `[SIGNAL-VALIDATED]` (`exogenous_quality` logged separately from consensus confidence)
- System telemetry: `[EXECUTION-MODE]`, `[ACCOUNT-CAPACITY]`, `[TRADE-STATE]`, `[HEARTBEAT]`, `[HEARTBEAT-FUNNEL]`, `[CONVERSION-RATES]`, `[RISK-BUDGET]`, `[CONSENSUS-QUORUM]`, `[CONSENSUS-VETO]`, `[CONSENSUS-ACTIVE]`, `[CONSENSUS-DIAG]`, `[CONSENSUS-ROOT]`, `[CONSENSUS-SNAPSHOT]`, `[CONSENSUS-STRATEGY]`, `[CONSENSUS-ROLE]`, `[CONSENSUS-CLUSTER]`, `[ROLE-CLUSTER]`, `[STRATEGY-REJECTS]`, `[PIPELINE-THRESHOLD]`, `[REGIME-STATE]`, `[TrendEngine][READINESS-FAULT]`, `[COST-GATE]`, `[ENTRY-VETO]`, `[ENTERPRISE-BLOCKED]`, `[QUIET-REASONS]`, `[NO-SIGNAL-ALERT]`, `[SCAN-BUDGET]`, `[SCAN-PRIME]`, `[SCHEDULER-STATE]`, `[CADENCE-WARNING]`, `[SCAN-CANDIDATE]`, `[SCAN-DECISION]`, `[TRADE-CONFIRMED]`
- Risk remediation: `[RISK-UNPROTECTED]`, `[CAPACITY-EXTERNAL]`, `[RISK-CLUSTER]`, `[RISK-MUTEX-BLOCK]`
- AI: `[AI-VOTE]`, `[NN-HEALTH]`
- Trade: `[SHADOW-TRADE]`, `[TRADE-SUCCESS]`, `[TRADE-ERROR]`, `[TRADE-EXECUTION]`, `[EXECUTION-RECEIPT]`, `[EXECUTION-TELEMETRY]`, `[FILL-DIFF]`

## 2026-03-31 AXIOM Refactor Trace
- Removed dead AI/control-flow weight:
  - `CNextGenStrategyBrain` no longer carries the dormant Python/cloud branch or cloud-status labeling
  - stale no-op lifecycle methods were removed from the transformer/ensemble/brain surface
- Stabilized AI hot paths:
  - `CMarketDataProcessor` now uses a ring buffer instead of shifting arrays on every update
  - `CUncertaintyQuantifier` and `CNeuralNetworkStrategy` now use ring-buffered histories instead of `Delete(0)` or heap-per-sample patterns
  - AI adapters now gate inference to one pass per bar
- Tightened AI ownership/failure boundaries:
  - optional AI brain/orchestrator/engine failures no longer kill the EA
  - adaptation sync and dashboard AI state are now gated by explicit readiness flags
- Tightened indicator lifecycle in clean detector paths:
  - `CSupportResistanceDetector` now caches its ATR handle across repeated detection/touch passes instead of recreating it inside hot methods

## Current Operational Constraints
- Persistent terminal sessions are preferred.
- Start tester on stable history symbol (`EURUSD.0`) when synthetic history is uncertain.
- Emergency drawdown flattening can run account-wide when configured (`InpEmergencyFlattenAllAccountPositions=true`).

## Build Note
- Compile helper: `sync_and_compile.ps1`
- Compile artifacts should be auto-cleaned after runs unless explicitly retained.
- **Code Quality**: Recent fixes address memory leaks, null pointer safety, bounds checking, and standardized constants across AI components.
- **Compilation**: Verified 0 errors, 0 warnings with all improvements integrated.

## 2026-03-30 Support/Resistance & Trendline System Overhaul Trace
- `CTrendlineDetector` and `CSupportResistanceDetector` rewritten to map points cleanly off normalized ATR levels instead of hardcoded minimum pip parameters.
- Look-ahead bias safely removed. All logic checks intersecting S/R lines and Trendlines now query `bar[1]` to ascertain completed chart realities and ignore active-wick repainting.
- Indicator MT5 Chart memory heavily hardened via dynamic array bubble sorting in `StrategySupportResistance`, drawing only the top 6/8 power tiers instead of saturating the frontend with stale ghost levels.
- Lot computations (`CADXPositionSizing`) explicitly refactored to consume Tick Size and Tick Value for hyper-accurate price distance conversion against the active risk profile.
- Obsolete fast-decay and price-averaging node cluster bugs isolated and resolved in S/R memory structures.

## 2026-03-25 Efficiency + Conviction Trace
- `Core/Pipeline/UnifiedSignalPipeline.mqh` now caches structural engine context per symbol/timeframe/bar and emits a reusable evidence snapshot carrying `readinessScore`, `contextScore`, `costScore`, effective confidence floor, and bounded soft-threshold state.
- `Core/Signals/TimeframeConsistency.mqh` no longer neutralizes directional consensus through hot-path hedging prevention; timeframe conflict resolution remains authoritative without pre-emptively zeroing otherwise valid mixed-strategy output.
- `Core/Management/EnterpriseStrategyManager.mqh` now computes directional conviction from adjusted live weight (`base weight x role multiplier x rolling healthScore`) and requires minimum ready-live-weight participation before a direction can pass quorum.
- `Core/Signals/AdvancedSignalValidator.mqh` now consumes upstream decision-path evidence (`conviction`, `readiness`, `context`, `cost`, `diversity`, `freshness`) and allows bounded soft passes near confidence/confluence floors when the setup quality is strong.
- `MultiStrategyAutonomousEA.mq5` now stages all risk-approved opportunities as ranked candidates, emits `[SCAN-CANDIDATE]` / `[SCAN-DECISION]`, and executes the best candidate per cycle instead of the first acceptable symbol.
- `Core/Trading/TradeManager.mqh` now exposes execution receipts and `Core/Risk/UnifiedRiskManager.mqh` scales executed-risk registration by fill ratio, so partial fills do not overstate daily entry-budget consumption.
- `Core/Signals/SignalDiagnostics.mqh` now batches flushes so diagnostic file output no longer forces a disk flush on every event.

## 2026-02-24 Cleanup Trace
- Removed dead commented strategy stubs from `MultiStrategyAutonomousEA.mq5`.
- Removed orphan harmonic strategy component files under `Strategies/HarmonicFiles/`.
- Removed dead wrapper files carrying legacy `StrategySwing` naming:
  - `Core/Utils/File.mqh`
  - `Core/Trading/DealInfo.mqh`
  - `Core/Trading/HistoryOrderInfo.mqh`
  - `Core/Trading/PositionInfo.mqh`
- Pruned retired strategy enum references from `Core/Utils/Enums.mqh`.
- Removed unused legacy strategy configuration module `Config/StrategyConfig.mqh`.
- Normalized Unified ICT helper comments/diagnostics to remove legacy SMC-era naming.

## 2026-02-24 Throughput-Recovery Trace
- Added intrabar dynamic quorum controls and single-voter confidence floor controls in `EnterpriseStrategyManager`.
- Added explicit strategy-level intrabar eligibility assignment path for curated core contributors.
- Added manager-level consensus funnel snapshots and dominant-cause diagnostics (`[CONSENSUS-ROOT]`).
- Added per-strategy reject attribution counters and heartbeat aggregation (`[CONSENSUS-STRATEGY]`, `[STRATEGY-REJECTS]`).
- Hardened `TrendEngine` ADX handling with readiness checks, value-domain sanitation, neutral degrade, and bounded ADX handle reinit.
- Extended pipeline confidence filtering with bounded weak-regime intrabar threshold cap plus source-tag logging.
- Extended heartbeat with conversion funnel counters/rates and no-signal dominance alerting tied to consensus diagnostics.

## 2026-03-07 No-Trade Recovery Trace
- Refined `EnterpriseStrategyManager` intrabar dynamic quorum so it now keys off actual live contributors in the current cycle rather than the entire eligible live pool.
- Added explicit `[EXECUTION-MODE]` startup telemetry in `MultiStrategyAutonomousEA.mq5` to prevent shadow-mode sessions from being mistaken for execution failures.
- Initialized `PerformanceAnalytics` explicitly before `CUnifiedRiskManager` bootstrap to remove cold-start ambiguity in adaptive-risk wiring.
- Split non-AI signal confidence policy away from `InpAIConfidenceThreshold` by introducing dedicated pipeline and validator confidence floors in `MultiStrategyAutonomousEA.mq5`.
- Rewired `CUnifiedSignalPipeline` threshold adaptation to use `CRegimeEngine` snapshot state rather than `TrendEngine` neutral/warmup output.
- Added explicit `Trend` reject telemetry so primary-live starvation can be diagnosed from runtime logs instead of remaining silent.

## 2026-03-07 Execution-Safety Trace
- Switched `CTradeManager` market sends to synchronous execution by default.
- Reworked market send path so execution price and protective SL/TP are recalculated from current market data at submit time.
- Moved confirmed close analytics updates into `OnTradeTransaction` and strengthened `PerformanceAnalytics::RecordClosedTrade(...)`.
- Reconstructed `AdvancedPositionManager` partial-close and breakeven state for already-open positions using `POSITION_IDENTIFIER` plus history-derived entry volume.
- Rejected unsupported non-hedging account modes at startup and tightened symbol validation for close-only symbols and invalid volume-step specs.

## 2026-03-16 Timeframe + AI Feedback Trace
- Manager consensus now resolves mixed-timeframe conflicts using `CTimeframeConsistency`.
- Strategy `OnNewBar` dispatch uses each strategy's registered timeframe to prevent cross-timeframe misalignment.
- AI performance feedback now records prediction/outcome pairs using request-to-position mapping on live trades.

## 2026-03-24 Quorum Admission Alignment + Smoke Controls Trace
- Aligned `EnterpriseStrategyManager` vote admission with `UnifiedSignalPipeline`'s effective confidence floor so pipeline-approved relaxed-threshold signals remain eligible for timeframe consistency and quorum.
- Added opt-in intrabar eligibility controls for `Fibonacci` and `Support/Resistance` to support smoke tests that need the chain to reach validator/risk/execution without broadening production defaults.

## 2026-03-24 Startup State Recovery + Capacity Diagnostics + Regime Fault Resilience Trace
- Added startup reconstruction of `g_lastTradeTime` in `MultiStrategyAutonomousEA.mq5` using EA-owned history and open positions so inherited positions preserve cooldown state after restart/re-attach.
- Added `[ACCOUNT-CAPACITY]` startup diagnostics that compare free margin with estimated minimum-lot margin for each active symbol and warn when live mode cannot afford any configured symbol.
- Hardened `Core/Engines/RegimeEngine.mqh` to reuse recent valid snapshots on transient warmup / buffer-copy / handle-init faults and to emit bounded `[REGIME-STATE] HANDLE_RESET` self-heal telemetry after repeated data faults.

## 2026-03-24 Entry Gate Decoupling Trace
- Moved cooldown/position/protection/capacity enforcement to the post-validation pre-risk stage in `MultiStrategyAutonomousEA.mq5` so signal generation keeps running during blocked-entry windows.
- Added explicit `[ENTERPRISE-BLOCKED]` logs for approved signals that are suppressed before risk/execution.

## 2026-03-24 Consensus Veto + Validator Spread-State + Trend Readiness Trace
- Added explicit `[CONSENSUS-VETO]` telemetry so post-quorum timeframe-conflict and single-voter nullification is visible without reconstructing it from downstream absence.
- Changed `Core/Signals/AdvancedSignalValidator.mqh` spread-shock state from shared global runtime state to symbol-scoped runtime state, preventing cross-symbol spread contamination in validator decisions.
- Hardened `Core/Engines/TrendEngine.mqh` against mature-series negative `BarsCalculated(...)` states by emitting `[TrendEngine][READINESS-FAULT]` and performing bounded full-indicator-set reinitialization after repeated readiness faults.
- Preserved exact `PortfolioRiskManager` veto reasons through `RiskValidationGate` so `[RISK-CONTRACT]` reports concrete correlation / position-cap style causes instead of flattening them to generic manager-blocked text.

## 2026-03-16 Weighted Quorum + Live Strategy Promotion Trace
- Promoted all retained strategies to live primary voters by default (per-strategy inputs gate registration).
- Replaced binary count-based quorum with normalized weighted confidence quorum (`InpQuorumThreshold`, `InpMinLiveVoters`, per-strategy `InpWeight*`).
- Added per-evaluation quorum telemetry via `[CONSENSUS-QUORUM]`.

## 2026-03-25 Runtime Integrity + Lifecycle Trace
- Corrected same-bar structural cache replay in `Core/Pipeline/UnifiedSignalPipeline.mqh` so cached evaluations preserve the original engine-ready flags and neutral defaults when engines are not ready.
- Hardened pipeline bootstrap so missing diagnostics/protection/core engines now fail startup rather than silently degrading to a hollow filter path.
- Localized symbol-specific engine state:
  - `Core/Engines/LiquidityEngine.mqh` now uses the requested symbol for point/tolerance math
  - `Core/Engines/RegimeEngine.mqh` now clears spread-shock cooldown state on symbol/timeframe switches
- Aligned sizing lifecycle with shared indicators by routing `Core/Risk/PositionSizer.mqh` ATR reads through `IndicatorManager` when available.
- Extended the scan lifecycle with cycle-scoped attribution:
  - `[SCAN-NO-TRADE]`
  - `[RISK-CAP]`
  - expanded `[QUIET-REASONS]`
- Tightened execution lifecycle in `Core/Trading/TradeManager.mqh`:
  - preflight viability check before send
  - confirmed-fill classification instead of raw submit success
  - explicit `[EXECUTION-BLOCKED]` / `[EXECUTION-UNCONFIRMED]` telemetry when safe execution cannot be proven
- Verification:
  - compile passed with `0 errors, 0 warnings`
  - bounded MT5 shadow-launch attempt completed, but no fresh EA-level tester artifacts were emitted in this environment

## 2026-02-24 Strategy Betterment Trace
- Note: the soft-quarantine defaults recorded in this batch are historical; current default voting behavior is defined by the 2026-03-16 weighted quorum + live strategy promotion update.
- Added institutional strategy governance metadata (role, cluster, live-vote eligibility, shadow mode) to `EnterpriseStrategyManager` and exposed setter APIs by strategy name.
- Added soft-quarantine defaults in EA initialization:
  - primary live voters: `Momentum`, `Trend`, `Unified ICT`
  - feature/shadow-only by default: `Candlestick`, `Fibonacci`, `Elliott Wave`, `Support/Resistance`
- Added deterministic `Core/Engines/RegimeEngine.mqh` and integrated it into `UnifiedSignalPipeline` as a pre-validator regime/cost viability gate.
- Extended `SignalFilterSettings` with regime/cost controls (`enableRegimeCostGate`, `maxSpreadToAtrRatio`, `spreadShockCooldownSeconds`, `maxEntryRangeZScore`).
- Refactored momentum strategy to state+trigger gating (EMA state alignment + compression-to-break trigger) to reduce crossover spam.
- Simplified Unified ICT live decision path to falsifiable event tuple checks (structure break, displacement, mitigation/retest) with bounded event-quality scoring.
- Extended `STradeValidationRequest` with role/cluster/contributor context and compact cluster code.
- Added cluster-aware risk governance in `RiskValidationGate`:
  - same-symbol opposing-cluster mutex
  - per-cluster concurrent position cap
  - per-cluster projected risk cap
- Added runtime cluster-tagged trade comments (`K:T/R/S/N`) for deterministic cluster attribution on open positions.

## 2026-04-01 Default Runtime Efficiency Trace
- `default.log` carried two valid runtime signals:
  - repeated `TrendEngine` ATR readiness faults
  - repeated idle scan-budget passes
- The same log also diverged from current code defaults, so the remediation batch split into two tracks:
  - real hot-path fixes
  - explicit operator guidance that saved runtime state must be verified from startup logs
- Trend trace:
  - mature-series ATR faults no longer hard-pin the engine in false warmup
  - bounded ATR fallback now runs before reuse/neutral degradation
  - readiness degradation remains explicit in logs
- Scan trace:
  - `[SCAN-BUDGET]` now includes `active_work`
  - fully idle cycles skip the per-symbol loop
  - quiet-cycle attribution remains visible in heartbeat counters
- Governance/build trace:
  - corrected `Support/Resistance` intrabar probe mapping
  - repaired `StrategyElliottWaveEnhanced` line-style enum usage
  - removed local min-confidence shadowing in Elliott Wave strategy
  - compile verification finished cleanly with `0 errors, 0 warnings`

## 2026-04-07 Scan Budget + Registry + Diagnostics Debloat Trace
- `MultiStrategyAutonomousEA.mq5` now caps heavy evaluations with `InpMaxSignalEvaluationsPerCycle`, persists pending new-bar symbols across cycles, and spends the cycle budget on deferred new-bar work before intrabar scans.
- The legacy `InpUseOrchestrator` surface has been removed; runtime registration now follows the active strategy registry only, so disabled curated strategies and disabled AI adapters do not enter manager pools, orchestrator identity maps, or weight summaries.
- `Core/Engines/TrendEngine.mqh` now treats partial readiness as a fail-closed fault instead of a soft continue path, while preserving bounded last-good reuse for transient copy-fault cases.
- `Strategies/StrategyElliottWaveEnhanced.mqh`, `Core/Pipeline/UnifiedSignalPipeline.mqh`, and `Core/AI/AIStrategyOrchestrator.mqh` no longer allocate component-local `SignalDiagnostics` sinks; runtime observability is now concentrated in manager/runtime telemetry rather than duplicate per-component logs.

## 2026-04-01 Strategy Registry + AI Runtime Audit
- Added `ENUM_EA_MODE` and registry-backed activation via `CStrategyRegistry`.
- Startup now records the requested mode, resolved effective mode, and active indicator/AI family counts under `[STRATEGY-REGISTRY]`.
- Per-symbol manager construction is now registry-driven for:
  - retained indicator strategies
  - transformer adapter
  - ensemble adapter
  - neural adapter registration once the per-symbol NN exists
- Post-consensus audit trail now includes mode-specific admission:
  - candidate can be rejected for `hybrid_mode_alignment_missing`
  - candidate can be rejected for `indicator_confirmation_missing`
  - candidate can receive `[AI-MODE-BONUS]`
- Scheduler audit trail now includes bounded intrabar keepalive recovery so default hybrid cadence cannot permanently collapse to `intrabar_selected=0`.
- `CTrendEngine` audit trail now includes bounded MA fallback in addition to ATR fallback, keeping readiness degradation explicit without forcing repetitive full reinitialization.

### Batch 14: Synthetic Asset 24/7 Hardening (2026-04-08)
- Event: Expanded intrinsic synthetic filtering to PainX, SFX Vol, GainX, FX Vol, and FlipX.
- Implication: Core systems (AdvancedSignalValidator, TradeManager, MarketAnalysis) bypass native off-hours blocks to sustain execution on decentralized index regimes without false validation drops.

