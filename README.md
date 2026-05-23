# metatrader-multistrategy-ea

## Document Metadata
- Last Updated: 2026-05-23
- Status: Batch 90 - Visualization System Audit Fixes
- Primary Runtime: `MultiStrategyAutonomousEA.mq5`

Autonomous multi-strategy MetaTrader 5 EA with enterprise-style signal management, multi-tier validation, unified risk authority, and AI-assisted strategy voters integrated into the runtime consensus path, with explicit separation between MT5-native AI, Python-trained ONNX runtime voting, and optional external reasoning sidecars.

## System Snapshot
- **Visualization System Audit Fixes (Batch 90):** Comprehensive chart object management and visualization safety improvements:
  - Fixed hardcoded chart ID 0 in StrategyUnifiedICT that caused cross-chart contamination
  - Converted StrategyUnifiedICT to use CChartDrawingManager instead of direct MT5 API calls
  - Converted StrategyFibonacci to use CChartDrawingManager for consistent drawing pattern
  - Added global object counter with tiered alert thresholds (800 warning, 900 critical, 950 emergency)
  - Implemented periodic logging of object counts with drawing statistics dashboard
  - Reduced maxObjectAge from 500 to 150 bars to prevent excessive object accumulation
  - Added coordinate validation (valid time/price, no NaN/Infinity, reasonable ranges)
  - Replaced bitwise OR color operations with explicit RGB values for consistent rendering
  - Wrapped debug logging in CChartDrawingManager behind enableDebugMode flag
  - Added SafeObjectsDeleteAll with verification of deletion counts
  - Added per-strategy object limit enforcement and dirty-flag optimization
  - Integrated drawing statistics into VisualDashboard showing global/per-strategy counts

- **Module 6 Consensus & Decision Logic Fixes (Batch 89):** Critical consensus safety improvements:
  - Raised minimum live voters from 1 to 2, preventing single-strategy decisions
  - Increased quorum threshold from 48% to 60% for stronger consensus requirements
  - Rebalanced strategy weights: ICT strategies (UnifiedICT, UnicornModel, PowerOfThree) reduced from 2.2-2.4 to 1.2
  - Disabled Elliott Wave from consensus voting (weight = 0.0) due to unreliability
  - Ensures multi-strategy consensus system functions as intended
- **Module 2 Strategy Engine Fixes (Batch 88):** Comprehensive strategy reliability improvements:
  - Disabled unreliable strategies: Elliott Wave, Unified ICT (2,199 lines), Unicorn Model, Power of Three
  - Simplified Momentum strategy from 7 to 4 indicators (-43% complexity)
  - Fixed EMA calculation bugs in TrendEngine.mqh causing false trend identification
  - Standardized ADX thresholds across all timeframes (20/25/30/40)
  - Implemented symbol-specific Fibonacci precision (JPY: 0.001, Standard: 0.01, 5-digit: 0.00001)
  - Added crossover validation with hysteresis to prevent false signals
  - Reduced ICT strategy weights from 2.2-2.4 → 1.2 (-48% reduction)
  - Added timeframe validation for scalping mode (M1-M15 range)
- **Module 5 Execution & Order Management Fixes (Batch 87):** Comprehensive execution hardening:
  - Reduced maximum spread limit from 1500 to 50 points for safer trading
  - Created unified `CPositionStateManager` replacing multiple unsynchronized arrays
  - Implemented dynamic slippage adjustment based on ATR volatility
  - Added configurable dynamic slippage parameters (ATR %, min/max bounds)
  - Enhanced synthetic spike detection with configurable confirmation window (default: 2 windows)
  - Added execution quality metrics tracking (fill rate, slippage, latency, spread costs)
  - Implemented smart order routing based on execution history
  - Added comprehensive execution quality reporting with `GenerateExecutionQualityReport()`
  - New file: `Core/Trading/PositionStateManager.mqh` (unified position state tracking)
- **Module 7 Market Analysis & Visualization Fixes (Batch 86):** Comprehensive fixes for visualization and market analysis robustness:
  - Added chart object limit enforcement (900 object cap) to prevent MT5 terminal crashes
  - Implemented LRU cleanup strategy for chart objects
  - Enhanced regime detection with confidence tracking and stability requirements (3 bars)
  - Added `confirmedState` to prevent rapid regime flipping on noisy data
  - Added ATR validation test function for runtime verification
  - Updated StrategyUnifiedICT to respect object limits before drawing
- **Module 4 Risk Management Fixes (Batch 85):** Critical risk management hardening:
  - Fixed critical risk constants: `MAX_RISK_PER_TRADE` from 100.0 → 2.0%, `MAX_TOTAL_RISK` from 100.0 → 10.0%
  - Set safe default risk values in `CUnifiedRiskManager`: 2% per trade, 6% daily, 10% portfolio
  - Added currency conversion in `CPositionSizer` for accurate position sizing across non-USD accounts
  - Increased margin safety buffer from 5% to 20% (max 80% of free margin used)
  - Added minimum price threshold to volatility adjustment to prevent exaggerated risk on low-priced symbols
  - Enhanced emergency drawdown stop with volatility checks and warnings
- **Module 8 Python External Integration Fixes (Batch 85):** Comprehensive fixes for Python bridge reliability:
  - Added ZMQ connection timeout handling (5s request timeout) to prevent indefinite hangs
  - Implemented reconnection logic with exponential backoff (2s → max 30s) and configurable max attempts
  - Added heartbeat monitoring with configurable timeout (default 30s)
  - Implemented local AI fallback mode when Python bridge is unavailable
  - Added message serialization validation (JSON structure validation)
  - Added version compatibility check (requires v1.0.0+)
  - Added comprehensive health monitoring dashboard with real-time status logging
  - Added startup validation check for Python bridge connectivity
  - Added HTTP server endpoint (`http://127.0.0.1:8000`) with FastAPI for MQL5 compatibility (MQL5 lacks native ZMQ support)
  - New endpoints: `/predict`, `/health`, `/heartbeat`, `/version`
  - New files: `Core/Utils/PythonBridge.mqh` (MQL5 bridge class)
- **Module 1 Architecture & Core Infrastructure Fixes (Batch 84):** Addresses critical infrastructure issues identified in the Module 1 audit:
  - Added bounds checking to `CPositionStateManager` with `MAX_STATES = 500` constant to prevent memory exhaustion
  - Added comprehensive error checking for `PositionSelectByTicket()` calls in `CTradeManager` with detailed error logging
  - Implemented startup health checks in `OnInit()` to validate AI subsystem, Python bridge, risk manager, and position state manager initialization
- **Strategic Signal Participation, Adaptive Exits & ATR-Based Holding (Batch 82):** `20260521.log` (planned) focuses on removing the "AI-Only" bias by relaxing restrictive strategy and consensus filters. Strategy weight decay was softened (inactivity threshold 3 -> 15 bars, decay 15% -> 5%), tier-based confidence floors were lowered (Tier 3: 0.70 -> 0.62), and the system now permits solo strategy signals to trade live when exceeding a high-quality threshold. A new "Smart SRE" (Signal Reversal Exit) logic was implemented with a `ProfitGuard` (never close winners via reversal), `Structural Invalidation` (bail on true trend flips), and a `Last Stand` zone (disable reversal exits when >82% into SL). Position management was upgraded to include dynamic ATR-based trailing stops, and global risk throttling was softened to allow scaling into winning days.
- **Indicator/Hybrid Signal Transparency, Abstention-Aware Quorum & Scalp Participation (Batch 81):** `20260515.log` and `20260516.log` showed `AI_ONLY` runtime fingerprints rather than indicator/hybrid participation, so startup telemetry now prints both requested and effective EA mode. The new `20260517.log` indicator-only and AI-assisted sessions proved the modes were active, but generation was dying after pipeline/quorum (`INDICATOR_ONLY`: `78 -> 26 -> 0`, `AI_ASSISTED`: `16 -> 8 -> 0`) while dormant strategies and warming AI adapters inflated the denominator. Pipeline-filtered strategies now carry the rejecting filter name/reason into consensus summaries, raw-none / filtered / infrastructure abstentions are discounted before support math, and `Momentum` / `Candlestick` can register on a lower scalp/intrabar timeframe when the chart timeframe is higher.
- **Fix Hardcoded Zero Weights for Experimental AI Families (Batch 80):** Resolves the issue where `Transformer AI` and `Ensemble AI` were generating signals but were excluded from live voting due to 0.0 weights. These strategies now receive non-zero weights from `InpAIWeightMultiplier` during registry bootstrap, ensuring they can participate in consensus voting when enabled.
- **Adaptive Live Authority Gate & AI/ONNX Warm-Start (Batch 78):** Source defaults are live-capable again, with AI/ONNX enabled and `InpShadowMode=false`, but candidate execution is controlled by `InpEnableLiveAuthorityGate`. High-confidence AI/ONNX packets can warm-start live at scaled risk while the EA records forward R evidence through `[AUTHORITY-TRIAL]` and `[AUTHORITY-RESULT]`; mature families are promoted when expectancy/profit-factor thresholds pass and demoted to shadow when they fail. Elliott Wave can contribute to consensus, but Elliott-only packets stay research/shadow unless independent evidence and confluence earn live authority. Intrabar cadence is faster (`5s`) with larger scan budgets, while hard spread/drift and cost/reward gates remain in front of execution.
- **Batch 74 Runtime Hardening + Contract Reconciliation (Batch 74):** Fresh `20260427.log` analysis exposed three concrete runtime hazards: `Power of Three` could fail hard on symbols without a valid SMT companion, AI-only sessions could deadlock before neural registration when no indicator strategies were active, and stale neural checkpoints could still be loaded after the 57-feature contract upgrade and corrupt online-training buffers. The runtime now treats SMT as optional inside `CPowerOfThreeStrategy`, allows neural bootstrap whenever a symbol manager exists, bumps the neural checkpoint schema to `v7`, hardens training-ring bounds before writes, and disables ONNX for the rest of the session after the first hard initialization failure with an explicit `57-feature` retrain/export warning. The symbol-universe parsing and chart-symbol membership checks were also further extracted from `OnInit()` through `Core/Management/SymbolUniverseBuilder.mqh`, continuing the requested debloat of the main EA file.
- **Blueprint Closure + ICT/Feature Expansion (Batch 73):** The remaining `debloat.md`, `ai_upgrade_one.md`, and `ai_upgrade_two.md` implementation gaps are now wired into the codebase: `CUnicornModelStrategy` and `CPowerOfThreeStrategy` are registered as live Tier-1 structure voters, `StrategyUnifiedICT` now consumes CISD confluence and opposing-CISD vetoes, the liquidity/structure stack now detects Turtle Soup and CISD directly, Elliott Wave scoring now carries degree awareness plus an ML-style probability blend, the Python sidecar surface now includes DoubleAdapt/Kronos/MAML bridge scaffolds, and the canonical AI feature contract has been widened from 55 to 57 features by adding OFI and synthetic spike-recovery context. Python training now prefers exported `feature_*` columns when present, so MT5-exported tick-derived features remain training-serving consistent. Any ONNX model intended for live use must now be retrained/exported against the 57-feature contract.
- **Timer/Tick Safety Split + ONNX/Pipeline Upgrade (Batch 72):** Heavy trading evaluation is now timer-owned while `OnTick()` runs a lightweight safety/lifecycle loop, synthetic indices have a tick-velocity spike alarm with flatten-and-pause behavior, ATR-ratio crisis gating can reject or halve risk during volatility shocks, ONNX inference now supports Python-exported scaler parity through `scaler.bin`, `TrainingDataExporter.mq5` can export the live 55-feature vector contract, and the Python stack now includes uniqueness weighting, CPCV validation, IC-gated model promotion, LightGBM/stacker tooling, regime/turbulence helpers, feature cross-checking, and a ZMQ bridge surface.
- **Log Analysis Fixes & Enhanced Observability (Batch 69):** Deep log analysis identified and fixed critical issues including ENTRY-VETO threshold too tight (increased from 2.50 to 2.55), market hours check added to position management (prevents closed-market operations), per-filter logging added to identify pipeline rejections, spread filter added to reject symbols > 1000 points, ONNX inference logging enhanced to distinguish warming vs failure, and dormant strategy logging enhanced to identify specific strategies. Fixed bug where SYMBOL_TRADE_MODE_CLOSEONLY was incorrectly blocked for position modifications.
- **Institutional ICT Completion + Real ONNX Asset (Batch 68):** The repository now ships a real embedded `Resources/model.onnx` trained from MT5 cache-derived data, a repo-owned export/train/validate toolchain under `Python/`, and a `TrainingDataExporter.mq5` tester harness for regenerating datasets. On the strategy side, `StrategyUnifiedICT` now uses institutional liquidity references (monthly/quarterly highs-lows, NY midnight open), anchored VWAP, cumulative-delta pressure, Silver Bullet/Judas/SMT timing, advanced propulsion/rejection/vacuum block variants, and kill-zone-scaled ATR stop placement instead of placeholder or partially wired logic. Elliott Wave confidence now cross-checks harmonic PRZ alignment, and the EA scan loop now reserves best-candidate virtual risk inside `CUnifiedRiskManager` so later candidates cannot silently double-spend the same portfolio budget during ranking.
- **AI Training Guardrails & External LLM Runtime Telemetry (Batch 67):** Re-read runtime logs showed the neural path was training almost entirely on pseudo labels while `trade_labels=0`, the external LLM path was configured but effectively silent beyond init, and the reviewed "indicator weakness" sessions were actually `AI_ONLY` runs with indicators intentionally inactive. The EA now blocks weight mutation until enough real trade-linked labels exist, emits explicit `[NN-MUTATION]`, `[AI-FEEDBACK]`, `[EXT-LLM]`, and `[MODE-MASK]` diagnostics, and exercises a throttled external-LLM reasoning path during adaptation instead of leaving the client dormant.
- **Runtime Readiness Recovery (Batch 66):** Fixed a live AI/runtime gap where the shared transformer service could be referenced before encoder bootstrap, added raw-rate ATR/Bollinger fallbacks in `CVolatilityEngine` and `CRegimeEngine` for transient `4806`-style buffer faults, and hardened the final validator ATR path so approved packets are not re-poisoned by `Invalid ATR: 0.00000`.
- **Logical Error Audit & Defensive Programming (Batch 64):** Comprehensive autonomous audit identified and fixed 34 logical errors across CRITICAL, HIGH, MEDIUM, and LOW priority levels. Enhancements include robust risk validation with negative balance/equity handling, comprehensive parameter validation, NaN handling throughout AI modules, MA handle caching, timeframe-aware history checks, and improved error logging for debugging.
- **Multi-Tier Signal Validation (Batch 60):** Comprehensive validation architecture evaluates signals across Tier 1 (Institutional), Tier 2 (Structure), and Tier 3 (Indicators).
- **AI Feature Robustness:** Improved feature vector stability with proactive history readiness checks and indicator warmup verification, eliminating "Feature validation failed" errors during startup.
- **Directional Conflict Resolution:** Sophisticated logic resolves contradictions between tiers (e.g., T2/T3 vs T1) with configurable weights and consensus overrides.
- **Weighted Decision-Making:** Final voting considers setup quality (signal strength) and tier-based reliability scores rather than simply defaulting to the highest tier.
- **Tier-Specific Performance Metrics:** Historical accuracy is tracked for each tier (T1, T2, T3) to inform reliability-weighted decisions.
- Per-symbol strategy managers generate consensus signals.
- Hybrid cadence supports new-bar and intrabar scanning.
- Heavy evaluation work is cycle-budgeted (`InpMaxSignalEvaluationsPerCycle`), with pending new-bar symbols carried forward ahead of any intrabar work.
- Symbol-class profiles can now adapt runtime behavior by instrument family so synthetic indices no longer inherit the same roster and context assumptions as FX pairs.
- Startup now primes one pending new-bar scan for every validated symbol, so a fresh session cannot idle indefinitely waiting for a later cadence event before the first real evaluation.
- Scheduler state is now rebuilt as one authority after per-symbol manager initialization and runtime-reconciled if it drifts, preventing the silent `pending_newbar=0` starvation mode where managers are live but no symbol ever enters the scan loop.
- Source defaults now seed a broader FX + synthetic live-verification roster so operators do not need to repopulate the common Deriv symbols by hand on every fresh attach.
- `[CADENCE-CONFIG]` now reports `effective_intrabar`, and `[CADENCE-WARNING]` is emitted when `InpSignalScanOnNewBarOnly=true` is globally disabling timed intrabar scans despite strategies being intrabar-eligible.
- Pre-trade decision gate is centralized in `CUnifiedRiskManager`.
- Execution is centralized in `CTradeManager`.
- Position lifecycle is centralized in the EA safety loop via `CTradeManager::ManageAllPositions(...)`, and the generic EA-level breakeven/trailing manager is now opt-in rather than silently active.
- Shadow mode (`InpShadowMode`) remains a global dry-run override. Normal source defaults are live-capable, but the live-authority gate can shadow individual unproven candidates without disabling the whole EA.
- Runtime registry is active-only: disabled strategies and disabled AI adapters are not registered into managers, weight pools, or orchestrator identity sets.
- Retired standalone strategy artifacts and their commented stubs are removed from runtime sources.
- Legacy `Config/StrategyConfig.mqh` (removed-strategy config surface) has been deleted from runtime inventory.
- **Chart Visualization Hardening (Batch 58):** Enhanced chart drawing clarity and accuracy:
  - Elliott Wave strategy now draws comprehensive Fib target levels for all waves (W1-W5) with multiple ratios (0.382, 0.5, 0.618, 1.0, 1.618)
  - Elliott Wave trend lines changed from solid thick to thin dashed (STYLE_DOT, width 1) with muted colors for cleaner appearance
  - SupportResistance strategy trendlines aligned to thin dashed style (STYLE_DOT, width 1) for consistency
  - ICT drawing colors (Order Blocks, FVGs, Liquidity, BOS, CHOCH) reduced in intensity using 0x909090 color mask for better chart visibility
  - All chart drawing elements now use consistent thin dashed styling for improved clarity

## Core Architecture
- Entrypoint: `MultiStrategyAutonomousEA.mq5`
- Strategy consensus: `Core/Management/EnterpriseStrategyManager.mqh`
- Signal filtering pipeline: `Core/Pipeline/UnifiedSignalPipeline.mqh`
- AI runtime control: `Core/Engines/AIEngine.mqh` plus symbol-scoped adapters under `Core/Strategy/`
- Risk authority: `Core/Risk/UnifiedRiskManager.mqh`
- Execution: `Core/Trading/TradeManager.mqh`
- Tick safety loop: `Core/Processing/TickSafetyMonitor.mqh`
- Indicator cache lifecycle: `IndicatorManager.mqh`

## Runtime Behavior

### Decision cadence
- New-bar scans use conservative consensus behavior.
- Intrabar scans now run on timer intervals by default (`InpSignalScanOnNewBarOnly=false`) instead of starting in a globally muted new-bar-only posture.
- `OnTimer()` owns heavy scan/evaluate/rank/send work, while `OnTick()` is reserved for fast tick validation, account-runtime refresh, lifecycle management, synthetic spike detection, and emergency drawdown response.
- Total heavy evaluations are capped per cycle (`InpMaxSignalEvaluationsPerCycle`); pending new-bar symbols are selected first and deferred cleanly when the current cycle budget is exhausted.
- Intrabar scheduling is now budgeted per cycle (`InpMaxIntrabarSymbolsPerCycle`) and prioritized by recent near-miss / recent generation / readiness health instead of uniform round-robin.
- Per-symbol intrabar backoff now escalates after repeated `raw_none` / `zero_voter` outcomes, reducing wasted scans while still resetting on new bars.
- Scheduler ownership is explicit: `g_lastSymbolBarTimes`, `g_lastIntrabarScanTime`, `g_pendingNewBarScans`, and `g_symbolScanStates` are rebuilt together after manager init and self-heal via runtime reconciliation before new-bar detection proceeds.
- Intrabar scope can be chart-only or all managed symbols.
- Startup now reconstructs the last EA trade timestamp from EA-owned history and open positions so cooldown state survives restart/re-attach scenarios.
- Startup emits `[ACCOUNT-CAPACITY]` min-lot affordability diagnostics for each configured symbol before live execution begins.
- Post-trade cooldown, total-position caps, unprotected-position vetoes, and per-symbol capacity now pause entry only; signal generation and validator telemetry continue running while the EA is blocked from sending.
- Validator spread-shock state is symbol-scoped, so one symbol's transient spread event no longer poisons validator spread decisions on the rest of the portfolio.
- Quorum uses normalized weighted conviction pooling (`InpQuorumThreshold`, `InpMinLiveVoters`, per-strategy weights, readiness participation, rolling strategy health) instead of binary voter counts.
- Curated mode now acts as the default baseline profile rather than a runtime suppressor: fresh defaults keep Elliott Wave available as a contributor, but candidate-level live authority blocks Elliott-only execution until evidence/confluence justify it.
- Intrabar eligibility now means real intrabar voting, with symbol-class-aware exceptions: on balanced FX profiles an enabled intrabar strategy votes live, while synthetic lean profiles keep `Fibonacci`/`Elliott Wave`/`Support-Resistance`/`Unified ICT` as `LIVE`, leave `Candlestick` as intrabar `PROBE`, and remove `Momentum`/`Trend` from the local synthetic manager roster when structure-capable strategies are already enabled.
- Startup governance logs now distinguish active vs inactive strategies in the intrabar summary, so disabled strategies no longer appear as intrabar `LIVE` simply because their input toggle is true in a different profile.
- `AI_ONLY` sessions now emit a `[MODE-MASK]` explanation when indicator-profile entries remain configured in inputs but are intentionally absent from the active registry, preventing false conclusions that indicator families were "participating badly" when they were actually mode-filtered out.
- Symbol-class governance is now explicit: when `InpUseSymbolClassProfiles=true`, synthetic symbols use a lean structure-first roster and suppress `Momentum` / `Trend` when structure-capable strategies are already enabled, while FX symbols keep the broader balanced roster.
- Synthetic lean profiles now also keep intrabar cadence intentionally narrower than the FX path: `Candlestick` remains available for new-bar decisions but no longer bloats synthetic intrabar quorum, and the default intrabar symbol budget is raised to `4` so live synthetic tests use the restored timer cadence more fully.
- Synthetic lean profiles now also use their own sparse intrabar admission thresholds (`InpSyntheticLeanSparseIntrabarMinQuality`, `InpSyntheticLeanIntrabarSingleVoterMinConfidence`) so one-voter synthetic structure signals are not forced through the same FX-style quality floor as broader balanced rosters.
- Synthetic profiles also use lighter higher-timeframe structure ladders and bypass ADX-dependent trend modeling inside `CTrendEngine`, which removes repeated synthetic-only readiness churn without changing FX trend behavior.
- Full quorum now requires both directional quality and directional support ratio (`InpConsensusSupportFloorNewBar`, `InpConsensusSupportFloorIntrabar`), not just a single pooled score.
- Intrabar sparse one-voter admission is disabled by default (`InpAllowSparseIntrabarSingleVoter=false`); high-confidence AI-only HYBRID packets instead use the explicit live-authority path (`InpAllowHybridAIStandalone`, `InpAIStandaloneMinConfidence`).
- Non-AI strategy throughput is controlled by dedicated pipeline confidence inputs and manager-owned quorum/admission logic instead of the AI threshold (`InpPipelineMinConfidence`, `InpValidatorNewBarMinConfidence`, `InpValidatorIntrabarMinConfidence`, `InpValidator*MinConfluence`, `InpValidator*MinQuality`).
- Consensus vote admission now reuses the pipeline's effective confidence floor for the current evaluation, so regime-relaxed pipeline passes are not discarded before quorum.
- Pipeline engine work is now cached per symbol/timeframe/bar and converted into a shared evidence snapshot (`readiness`, `context`, `cost`), reducing duplicate hot-path indicator/structure churn across strategies.
- Pipeline-filtered abstentions now report the rejecting filter chain in manager summaries, e.g. `PIPELINE:RegimeCostGate` or `PIPELINE:ConfidenceFilter`, so indicator-only and hybrid runs can be diagnosed from `[CONSENSUS-ACTIVE]` / `[CONSENSUS-DIAG]` evidence instead of guessing which gate swallowed the packet.
- Consensus denominator math is abstention-aware: infrastructure/warmup abstentions, pipeline-filtered packets, and ordinary raw-none strategy cycles now contribute reduced live denominator weight instead of being treated like fully useful neutral voters. This targets the `20260517.log` pattern where Fibonacci, Support/Resistance, Candlestick, and Elliott produced the only meaningful votes while Unified ICT, Unicorn, Power of Three, Neural, and warming ONNX mostly diluted support.
- Pipeline now allows readiness/context/staleness evidence to reduce surviving signal confidence; weak evidence can no longer preserve pre-adjusted confidence as fake certainty.
- `StrategyElliottWaveEnhanced::OnNewBar(...)` now refreshes state only; the manager-owned consensus pass is the single authoritative `GetSignal(...)` call for the bar, preventing pre-consumed Elliott signals from disappearing before quorum.
- Strategy registration now follows the live registry only: disabled curated modules and disabled AI adapters stay compiled in source but do not participate in manager registration, weight accounting, or orchestrator naming.
- Pipeline still supports bounded soft-pass behavior for near-threshold signals when readiness, context, and conviction are strong, so more valid trades survive to manager consensus without widening bad-signal admission.
- Structural signal admission is now manager-owned end-to-end: `CEnterpriseStrategyManager` is the single authority for confidence, confluence, directional quality, support ratio, and final admission after pipeline screening.
- `CAdvancedSignalValidator` now runs in `EXOGENOUS_ONLY` mode during normal runtime, enforcing only spread, time, session, volatility, and cost-viability sanity after manager quorum has already admitted the packet.
- Validator profile inputs (`InpValidator*MinConfidence`, `InpValidator*MinConfluence`, `InpValidator*MinQuality`) remain logged as telemetry/fallback surfaces, but they do not re-veto manager-approved packets while manager-owned admission is enabled.
- Validator still consumes manager quorum evidence (`effectiveMinVoters`, `directionalQuality`, `supportRatio`) so exogenous validation telemetry and any legacy fallback path stay aligned with the already-authoritative manager decision.
- Consensus is now readiness-aware and reliability-aware: live vote weight is adjusted by role, rolling strategy health, ready-live weight share, and a directional deadband before a side is allowed to win.
- Strategy governance is now continuous rather than purely binary: role/cluster metadata still exists, but live vote impact is modulated by rolling `healthScore` and reliability multipliers instead of treating every enabled strategy as equally trusted at all times.
- Strategy overrides that bypass `CStrategyBase::GetSignal(...)` now emit explicit last-decision tags (`FIB_*`, `EW_*`, `SR_*`, `CANDLE_*`), eliminating the misleading repeated `BASE_INITIALIZED` placeholder in consensus diagnostics.
- Infrastructure abstentions such as adapter warmup, unavailable features, invalid handles, initialization failures, and inference/scaler failures are no longer allowed to dilute live quorum as if they were complete decision cycles with real evidence.
- `Momentum` scalping is now an explicit operational control. When enabled, it can emit continuation scalp signals between crossover events on a short wall-clock cooldown, while low-volume continuation admits only during volatility expansion and receives a confidence penalty before quorum.
- `Momentum` and `Candlestick` can now use lower registration timeframes via `InpMomentumScalpTimeframe` and `InpCandlestickIntrabarTimeframe` when the attached chart is higher timeframe, preventing H1 closed-bar logic from pretending to be a timed scalping engine.
- The runtime now scans the full symbol set, stages all risk-approved candidates, ranks them by quality/conviction/context/readiness/cost/diversity, and only then selects the best trade for the cycle.
- The cycle-best candidate is now reserved as a virtual position inside `CUnifiedRiskManager` while the scan is still running, so later candidates are evaluated against remaining daily/portfolio budget instead of ignoring already-claimed scan-time risk.
- Validator time/session checks now use absolute GMT time and recognize Weltrade `PainX` synthetic symbols as off-hours synthetic products alongside Deriv `Vol`/`Step`/`Jump` families.
- Live execution now produces an execution receipt (`requested`, `filled`, `request_price`, `fill_price`, `slippage_points`, `latency_ms`, `retcode`, `requestId`, retries) and daily risk usage is registered against actual fill ratio instead of always charging the requested size.
- `CMarketAnalysis` now reuses bounded last-valid `trend`, `volatility`, `momentum`, and `ATR` snapshots on transient `4806/4807` copy faults instead of collapsing those metrics to zero during short synchronization gaps.
- `CAdvancedPositionManager` now treats configured breakeven, trailing, and partial-close pip values as floors, then scales them against the position's original stop distance so wide-stop synthetic trades are no longer managed with tiny fixed pip milestones.
- `CTradeManager::ModifyPosition(...)` now validates protective stops against the executable quote side (`Bid` for buys, `Ask` for sells), applies an extra freeze/stops cushion, and performs one widened retry on `TRADE_RETCODE_INVALID_STOPS`.
- The shared universal transformer service is now initialized eagerly during AI bootstrap and lazily inside the service itself, preventing symbol registration from succeeding while the encoder is still absent.
- `CVolatilityEngine` and `CRegimeEngine` now synthesize ATR/Bollinger context from raw rates when indicator buffers transiently fail, so pipeline evidence remains populated instead of collapsing to zero ATR during repeated `BB_BUFFER_COPY_FAILED` loops.
- Final validator ATR resolution now falls back to a raw-rate ATR calculation when the direct handle read misses, preventing otherwise-approved packets from being rejected solely because a fresh ATR copy returned zero.
- Post-quorum nullification now emits `[CONSENSUS-VETO]` so timeframe-resolution and single-voter safety drops are visible without inferring them from a `signal=NONE` quorum line.
- `CRegimeEngine` can temporarily reuse its most recent valid same-context snapshot on transient warmup / `CopyBuffer` / handle-init faults, and self-resets handles after repeated data faults.
- `CTrendEngine` now distinguishes warmup, transient copy faults, handle faults, partial-readiness faults, and reused snapshots; partial readiness is allowed to proceed when the underlying series is mature, enabling MA/ATR fallback logic to attempt recovery instead of hard-failing, which reduces persistent readiness vetoes on synthetic indices where `BarsCalculated` may lag behind `Bars()`.
- `CPortfolioRiskManager::CalculateSymbolCorrelation()` now returns a bounded fallback correlation (0.65, capped to `m_maxCorrelation`) when correlation data is unavailable, instead of a conservative 1.0 that causes hard blocks, preserving safety while avoiding unnecessary trade blocking when H1 price data is temporarily missing.
- `CUnifiedRiskManager` now applies progressive pressure throttling before the hard cap is reached, scaling recommended per-trade risk down as daily and portfolio utilization rise and emitting `[RISK-THROTTLE]` instead of waiting until the remaining budget is nearly zero.
- Shutdown report noise is reduced: performance and AI feedback reports only print when they have real trade/prediction data, and manager teardown now explicitly deinitializes strategies before deleting them.

### AI participation
- Runtime AI adapters can vote as strategies when enabled:
  - Neural Network adapter
  - Transformer adapter
  - Ensemble adapter
  - ONNX adapter (Python-trained, executed inside MT5)
- Runtime AI surfaces are now separated operationally:
  - `CNextGenStrategyBrain` / Universal Transformer: local feature brain and dashboard context, not a direct live voter
  - MT5-native live voters: `Neural Network AI`, `Transformer AI`, `Ensemble AI`
  - Python-trained live voter: `ONNX AI`
  - Python bridge sidecars in `Python/`: present for tooling/research, not wired into live consensus
  - External LLM: adaptation/reasoning only, not a direct live voter
- `EA_MODE_HYBRID` is now indicator-led instead of hard dual-confirmation: indicator-backed candidates remain tradable when AI abstains, AI+indicator agreement receives a small confidence bonus, and AI-only packets are still rejected unless the runtime is explicitly operating in an AI-primary mode.
- The runtime now supports the three practical operating postures explicitly:
  - `INDICATOR_ONLY`: only indicator strategies can generate tradable candidates
  - `AI_ONLY`: only AI adapters can generate tradable candidates; indicator strategies are filtered from the registry.
  - `HYBRID`: indicators and AI can both participate, with indicators remaining the admission anchor.
- AI intrabar participation is no longer hard-disabled globally. `Neural Network AI`, `Transformer AI`, `Ensemble AI`, and `ONNX AI` each have explicit intrabar eligibility inputs, so `AI_ONLY` can now run as a full timed intrabar mode instead of being limited to new-bar AI voting.
- AI registration is active-only: disabled adapters are not instantiated into managers or orchestrator identity maps, and the legacy `InpUseOrchestrator` control surface has been removed.
- Transformer, ensemble, and legacy neural defaults are now safety-hardened at a `0.70` confidence floor, and transformer/ensemble source defaults start disabled until retrained weights are intentionally re-enabled.
- Neural online learning is now guarded against pseudo-label-only drift: loss can still be evaluated on labeled samples, but weight mutation remains locked until enough real trade-linked labels exist and represent a meaningful share of the completed labeled set.
- AI bootstrap is now explicitly fail-soft:
  - trade/risk/manager initialization remains mandatory
  - NextGen brain, orchestrator, and AI engine initialize only when enabled
  - failures disable adaptation/dashboard AI features without aborting the EA
- `CNextGenStrategyBrain` now runs as a local-only transformer path (`LOCAL_TRANSFORMER`); the removed Python/cloud bridge is no longer part of runtime control flow.
- ONNX voting is now integrated as a symbol-scoped strategy adapter (`COnnxAIStrategyAdapter`) registered through enterprise managers, preserving manager-owned consensus instead of adding a competing EA-level vote path.
- The repository now includes an aligned offline ONNX surface under `Python/` plus an embedded `Resources/model.onnx` payload for training, export, validation, and runtime deployment.
- The embedded ONNX payload is now a real trained model generated from MT5 cache exports, not a placeholder asset, and the repo includes `Python/export_mt5_cache.py`, `Python/train_model.py`, `Python/validate_model.py`, `TrainingDataExporter.mq5`, and `shadow_session_mt5_tester.ini` to reproduce the offline/runtime flow.
- ONNX runtime normalization is now parity-safe: Python can export `scaler.bin`, `COnnxAIStrategyAdapter` hot-reloads it from Common files, and runtime features are normalized before inference when scaler parameters are available.
- AI vote paths are now bar-cached:
  - Neural adapter calls `GetNeuralSignalCached(...)`
  - Transformer and Ensemble adapters cache per-bar inference results and cache `NONE` on failed feature-build/inference for the rest of the bar
- AI adapters now emit explicit last-decision reason tags on abstain and signal paths (`NNAI_*`, `TRANSFORMER_*`, `ENSEMBLE_*`) so `[CONSENSUS-ACTIVE]` no longer collapses silent AI abstentions into `UNTAGGED_NO_SIGNAL`.
- AI data paths are allocation-stable:
  - `CNextGenStrategyBrain` now builds transformer inputs directly from `CAIFeatureVectorBuilder`; the redundant `CMarketDataProcessor` wrapper has been removed from runtime flow
  - uncertainty history uses ring buffers instead of `Delete(0)` churn
  - NN training samples use a fixed-size struct ring buffer instead of per-sample heap allocation
- Feature engineering is now standardized on a 55-feature contract shared by neural, transformer, ensemble, ONNX, and Python export paths.
- `TrainingDataExporter.mq5` can now emit those same 55 runtime features into CSV, and `Python/feature_crosscheck.py` validates Python-vs-MQL feature parity against a `max_mae` threshold.
- Per-symbol strategy names are registered into orchestrator using `<symbol>::<strategy>` naming.
- Weight adaptation is synchronized back into manager strategy weights.
- Ensemble aggregation now consumes model class probabilities via `GetPredictions(...)`, so BUY/SELL confidence is derived from the classifier outputs rather than reused latent transformer features.
- AI strategy adapters now support a unified `SetConfidenceThreshold(double)` interface, and the EA propagates the `InpAIConfidenceThreshold` authoritative floor directly into the strategy evaluation loop, eliminating legacy hardcoded confidence caps.
- `CAIEngine` now treats external LLM usage as an observable runtime path instead of a dormant helper surface: initialization, endpoint configuration, query start/success/failure, strategy-weight reasoning, feedback, and shutdown all emit explicit `[EXT-LLM]` telemetry, and adaptation now performs a throttled external reasoning capture when the feature is enabled.
- Per-component `SignalDiagnostics` fan-out has been reduced: Elliott, the unified pipeline, and the orchestrator no longer instantiate duplicate diagnostics sinks, leaving manager/runtime telemetry as the authoritative runtime record.
- **AI Feature Engineering Expansion (Batch 58):** Neural network feature vector expanded from 25 to 44 features:
  - Pattern-specific features (features 25-43): Higher Highs/Lower Lows sequences, Support/Resistance touch counts, Fibonacci Retracement proximity, Pivot Point proximity, volume profile features, market structure features
  - Weight matrix dimensions updated to `W1[44][32]` to accommodate 44 input features
  - All array allocations and loop bounds updated consistently to prevent array out of range errors
- **Multi-scale Attention Infrastructure (Batch 58):** Transformer brain now supports head-specific parameters for multi-scale attention:
  - Per-head scaling factors (`m_headScales[]`)
  - Per-head time window sizes (`m_headTimeScales[]`) for short/medium/long horizons
  - Per-head learning rates (`m_headLearningRates[]`) for differential training
- **Pattern Classifier Head (Batch 58):** 10-class pattern classification alongside 3-class BUY/SELL/NONE:
  - New weight matrices: `m_patternWeights[10][m_dModel]` and biases `m_patternBiases[10]`
  - Cross-entropy loss training for pattern recognition
  - Xavier initialization for pattern head weights
- **External LLM Integration (Batch 58):** Optional external LLM (Ollama/Phi-3-mini) support:
  - HTTP client for Ollama API communication (`http://localhost:11434/api/generate`)
  - Signal synthesis via external LLM reasoning
  - Trade explanation generation for human-readable decisions
  - Risk assessment via external LLM analysis
  - Strategy weight reasoning explanations
  - Feedback loop to external LLM for learning
  - Configuration-driven activation via `useExternalLLM` flag (default `false`)
  - Runtime methods: `ConfigureExternalLLM()`, `SetExternalLLMEnabled(bool)`, `IsExternalLLMEnabled()`

### Telemetry
- `[HEARTBEAT]`: global runtime counters.
- `[EXECUTION-MODE]`: startup execution mode (`SHADOW_ONLY` vs `LIVE_SEND`).
- `[ACCOUNT-CAPACITY]`: startup free-margin vs minimum-lot affordability per active symbol.
- `[TRADE-STATE]`: startup recovery of last EA trade/cooldown timing from history and open positions.
- `[CONSENSUS-QUORUM]`: per-evaluation weighted quorum scores and direction result.
- `[CONSENSUS-SPARSE]`: accepted sparse intrabar consensus with quality/support/coverage details.
- `[CONSENSUS-NEARMISS]`: intrabar near-miss packet rejected by sparse/full-quorum gates with explicit veto code.
- `[CONSENSUS-VETO]`: explicit post-quorum veto reason when timeframe resolution or single-voter safety nulls a candidate.
- `[CONSENSUS-SNAPSHOT]`: EA-interval aggregate consensus counters.
- `[CONSENSUS-DIAG]`: per-symbol consensus failure reasons.
- `[CONSENSUS-ROOT]`: dominant deadlock/rejection cause with interval percentages.
- `[CONSENSUS-STRATEGY]`: per-symbol strategy-level none-reason counters (Momentum/Unified ICT buckets).
- `[CONSENSUS-ACTIVE]`: per-evaluation active/voted/raw-none/filtered/suppressed strategy summary so missing contributors are visible without reverse-engineering `raw_none`.
- `[CONSENSUS-ACTIVE]` now downgrades untagged placeholder abstentions (`BASE_INITIALIZED`, empty override tags) so silent strategy overrides do not dilute ready-live quorum as if they had completed a real decision cycle.
- `[STRATEGY-REJECTS]`: heartbeat aggregate strategy-level reject counters.
- `[SIGNAL-REJECTED]`: validator rejection reason.
- `[SIGNAL-VALIDATED]`: manager-admitted packet that passed exogenous validator checks; logs `exogenous_quality` separately from consensus confidence.
- `[MARKET-ANALYSIS]`: bounded last-valid metric reuse when transient `4806/4807` faults hit market-analysis buffers.
- `[SCAN-CANDIDATE]`: risk-approved candidate staged for end-of-cycle ranking.
- `[SCAN-DECISION]`: top-ranked candidate selected for shadow/live execution.
- `[SCAN-BUDGET]`: per-cycle evaluation budget, pending/deferred new-bar count, and effective intrabar scheduler budget.
- `[SCAN-PRIME]`: startup/runtime symbol-state priming that seeds the first pending new-bar evaluations after init or symbol-set resize.
- `[SCHEDULER-STATE]`: scheduler-state rebuild/reconciliation log showing the aligned array sizes used by the cadence engine.
- `[ENTERPRISE-BLOCKED]`: approved signal suppressed by cooldown, capacity, or protection gates before risk/execution.
- `[INTRABAR-BACKOFF]`: per-symbol backoff tier transitions after repeated low-yield intrabar scans.
- `[RISK-CONTRACT]`: authoritative pre-trade risk rejection reason with preserved portfolio veto detail.
- `[RISK-THROTTLE]`: progressive pre-cap risk reduction when daily or portfolio utilization enters elevated pressure bands.
- `[RISK-VIRTUAL]`: reservation/release lifecycle for scan-time virtual positions held inside unified risk before the final cycle winner is executed or discarded.
- `[AI-VOTE]`: adapter liveness and vote counts.
- `[SPIKE-ALARM]`: synthetic tick-rate shock detection and flatten result.
- `[SPIKE-PAUSE]`: temporary post-spike entry pause lifecycle.
- `[AI-FEEDBACK]`: periodic adaptive-training and retraining status summary.
- `[NN-MUTATION]`: neural online-learning mutation gate state (`LOCKED` vs `UNLOCKED`) with trade-label vs pseudo-label evidence.
- `[EXT-LLM]`: external LLM config, runtime query lifecycle, reasoning, feedback, and shutdown telemetry.
- `[MODE-MASK]`: explicit notice that configured indicator families are inactive because the effective runtime mode filtered them from the registry.
- `[SHADOW-TRADE]`: shadow execution events.
- `[TRADE-CONFIRMED]`: confirmed deal lifecycle events from `OnTradeTransaction`.
- `[EXECUTION-RECEIPT]`: broker execution receipt including requested/fill volume, retcode, and retry count.
- `[EXECUTION-TELEMETRY]`: broker request/fill price, slippage points, and round-trip latency.
- `[EXECUTION-BLOCKED]`: hard pre-send market/quote/spread/drift rejection in `CTradeManager`.
- `[TRADE-EXECUTION]`: cycle-level live execution summary including fill ratio, request/fill price, slippage, and latency.
- `[FILL-DIFF]`: partial-fill delta between requested and executed size.
- `[EXECUTION-QUALITY]`: execution quality summary (total orders, fill rate, slippage, latency).
- `[EXECUTION-REPORT]`: detailed execution quality report with comprehensive analytics.
- `[SPREAD-COST]`: per-trade spread cost analysis in account currency.
- `[SMART-ROUTING]`: smart order routing decisions and parameter adjustments.
- `[PIPELINE-THRESHOLD]`: confidence-threshold source (`REGIME_RANGE`, `REGIME_TREND_RELAX`, `REGIME_BREAKOUT_RELAX`, `REGIME_CHAOS`, `REGIME_ENGINE_WARMUP`) with effective values.
- `[COST-GATE]` now prints ratio plus raw spread and ATR, reducing false “all zeros” interpretations when the ratio is simply very small.
- Validator soft-pass now aligns with manager-approved single-voter new-bar packets when supporting evidence is strong, reducing false negatives where consensus passed but validator re-rejected the same packet for near-threshold confidence/confluence.
- No-vote/no-trade telemetry now preserves aggregate readiness/context/cost evidence from the ready live pool instead of zeroing those fields after the manager already computed them.
- `[REGIME-STATE]`: regime state, transient-fault reuse (`REUSE_LAST_VALID`), and repeated-fault handle self-heal (`HANDLE_RESET`).
- `[REGIME-STATE]` and `[VOLATILITY-FAULT]` now also emit `FALLBACK_RATES` when raw-price recovery replaces a failed indicator-buffer read.
- `[ATR-FALLBACK]`: raw-rate ATR recovery when validator-side handle reads are temporarily unavailable.
- `[TrendEngine][READINESS-FAULT]`: mature-series indicator readiness fault with bounded indicator-set reinitialization.
- `[READINESS-STATE]`: bounded trend snapshot reuse event with symbol, timeframe, and reuse age.
- `[HEARTBEAT-FUNNEL]`: conversion funnel counters (`signals_generated` -> `shadow_or_live_sent`).
- `[CONVERSION-RATES]`: window-normalized conversion rates for throughput tracking.
- `[NO-SIGNAL-ALERT]`: dominant no-signal cause when no-signal ratio is elevated.
- `[TERMINATION-SNAPSHOT]`: shutdown-time heartbeat snapshot to localize abnormal exits.

## Operating Workflow

### Preferred terminal mode
- Use persistent terminal sessions (normal or `/portable`).
- Avoid repeated `/config` relaunch loops for manual testing.

### Strategy Tester
1. Open MT5 persistent session.
2. `Ctrl+R` -> Strategy Tester.
3. Expert: `MultiStrategyAutonomousEA`.
4. Start symbol: `EURUSD.0`.
5. Period: `M1`.
6. Load inputs from `shadow_session.set`.
7. Keep `InpEnableLiveAuthorityGate=true`; use `InpShadowMode=true` only for full dry-run sessions.
8. Start and monitor logs.

## Known Issues and Mitigations

### WebView2 login crash
- Symptom: `msedgewebview2.exe - Application Error` during account login dialog.
- Mitigation: use persistent logged-in session (especially `/portable`) and avoid re-login loops during test cycles.

### Synthetic history gaps
- Symptom: history sync `Not found` on some synthetic indices.
- Mitigation: use stable tester start symbol (`EURUSD.0`) and include synthetics only where broker history is available.

## Active Config Files
- `TrainingDataExporter.ini`
- `shadow_session_mt5_tester.ini`
- `shadow_session.set`

## Code Quality & Safety
- **Memory Management**: AI adapters implement proper RAII with safe cleanup of transformer models
- **Error Handling**: Comprehensive input validation and bounds checking across all AI components
- **Constants**: Standardized configuration constants eliminate magic numbers throughout the codebase
- **Hot-path efficiency**: AI inference is bounded to once per bar per adapter, heavy symbol evaluations are cycle-budgeted with clean carry-over, detector ATR reads are cached where safe, and ring-buffered histories remove repeated O(n) shifts from AI paths
- **Telemetry discipline**: duplicate per-component `SignalDiagnostics` sinks have been removed from Elliott, pipeline, and orchestrator paths so operator-visible logs stay concentrated in manager/runtime telemetry
- **Compilation**: Current implementation batch compiles with 0 errors; remaining warnings are legacy repo warnings outside the new ONNX/AI integration surface.
- **Runtime validation harness**: the repo now contains a tester-owned shadow harness (`shadow_session_mt5_tester.ini` + `shadow_session.set`). A fresh CLI tester dispatch was attempted on 2026-04-20, but this environment only started MetaTester services and did not produce a new EA pass with fresh `[HEARTBEAT]` / `[AI-VOTE]` / `[SHADOW-TRADE]` evidence, so live shadow-log confirmation is still pending even though compilation succeeded.

## AXIOM Refactor Update (2026-03-31)
- **Dead-path removal**: removed the obsolete NextGen Python/cloud branch and stale no-op AI lifecycle hooks so runtime behavior is single-path and easier to audit.
- **Inference caching**: transformer-, ensemble-, and neural-backed signals now reuse same-bar results instead of recomputing on every tick.
- **Allocation cleanup**: market data, uncertainty history, and NN training history now use ring buffers to avoid repeated array shifts and heap churn.
- **Optional AI isolation**: optional AI subsystems now degrade cleanly behind readiness flags instead of taking down the whole EA when an auxiliary module fails to initialize.
- **Indicator lifecycle cleanup**: detector-level ATR reads are now cached in clean hot paths rather than recreating and releasing handles inside repeated detection loops.

## Institutional Remediation Status (2026-02-23)
- **Deterministic cadence control**: Signal evaluation is now second-gated to prevent duplicate decision runs when `OnTick` and `OnTimer` overlap.
- **Portfolio hard veto on missing SL**: Any open position without a protective stop is treated as a risk-governance breach that blocks new entries.
- **Mark-to-market daily budgeting**: Daily risk usage now tracks max of entry budget, equity drawdown from daily baseline, and open portfolio stop risk.
- **Execution resilience**: Fill mode is configurable (IOC default), transient broker retcodes are retried with bounded backoff, and protective SL/TP updates support emergency bypass.
- **AI governance lock-down**: NN online training, pseudo-labeling, and weight mutation are disabled by default and cannot bypass unified risk controls.
- **Drawdown-adaptive sizing**: Sized lots are now tapered against peak-equity drawdown before the post-size unified-risk approval, reducing exposure without bypassing the single risk authority.
- **Unprotected position remediation**: Runtime now attempts deterministic SL restoration for EA-owned unprotected positions, with bounded retries and forced-close fallback after configured attempts.
- **Operator risk clarity**: Heartbeat now emits `[RISK-BUDGET]` split telemetry (`entry`, `mtm`, `open_exposure`, `effective`) to distinguish daily budget consumption vs exposure cap pressure.
- **Symbol fairness controls**: Per-cycle symbol evaluation now rotates start index to neutralize deterministic first-symbol bias under one-trade-per-cycle behavior.
- **External-capacity diagnostics**: `[CAPACITY-EXTERNAL]` explicitly reports when non-EA positions consume per-symbol capacity.
- **Execution retry hardening**: `LOCKED`/`FROZEN` retcodes now use single bounded retry instead of full exponential retry path.

## Support/Resistance & Trendline Overhaul (2026-03-30)
- **ATR-Driven Structure Models**: S/R Swing Points and Trendline anchoring now leverage standardized ATR multiples instead of isolated price calculations, eliminating static minimum pip logic.
- **Look-Ahead Bias Elimination**: The `CTrendEntryTypes` logic paths and all S/R intersection detectors now explicitly enforce `bar[1]` completed-bar rules to prevent indicator repainting and forward-sniffing false signals.
- **Dynamic Sizing Integration**: `CADXPositionSizing` and strategy SL/TP mappers compute accurate trade sizing strictly from Tick Size and Value boundaries over physical price distances, rather than abstract percentage points or raw pips.
- **Performance Optimized Drawing**: All MT5 graphical components under S/R and Trendlines now utilize custom dynamic arrays with bubble-sorting logic to drastically reduce node counts, capping drawings to strictly Top 6/8 power tiers.

## Unified ICT Specification Update (2026-03-30)
- **Strict FVG/OB alignment**: Mitigations now require full candle body closes beyond the boundary rather than mid-point touches. FVGs are now pure gap-based models logic, and OBs are dynamically anchored to displacement.
- **Institutional Context**: `CSessionGapDetector` and `CAMDDetector` map structural direction to Accumulation/Manipulation/Distribution phases and NDOG/NWOG opening gaps.
- **Silver Bullet Enforced**: `CICTKillZones` tracks precise institutional AM/PM and London windows.
- **Weighted Confluence**: `StrategyUnifiedICT` scores entries on a 0-130 pt scale rather than treating all setup components equally.
- **Dynamic Probabilities**: `ComputeEntryConfidence(...)` factors in MS Break intensity (CHoCH > BOS) and AMD phase to output confidence scalars dynamically.
- **TP Hierarchy**: TPs are placed dynamically at opposing MS CE levels (FVG CE -> OB CE -> Liquidity Sweep), abandoning fixed-RR targets.

## Institutional Throughput/Integrity Update (2026-02-24)
- **Intrabar deadlock conversion**: `EnterpriseStrategyManager` now computes intrabar effective quorum from actual live contributors in the current cycle (`<=1 => quorum=1`, else bounded by configured intrabar floor).
- **Deadlock attribution visibility**: consensus diagnostics now include `[CONSENSUS-ROOT]`, `[CONSENSUS-STRATEGY]`, and snapshot APIs consumed by runtime `[CONSENSUS-SNAPSHOT]`/`[NO-SIGNAL-ALERT]`.
- **ADX fail-safe hardening**: `TrendEngine` now validates ADX/DI domains, neutral-degrades on copy/value faults, and performs bounded ADX-handle self-heal after consecutive failures.
- **Threshold governance**: pipeline weak-regime intrabar threshold uplift is capped (`InpPipelineIntrabarConfidenceCap`) and logged with source tag via `[PIPELINE-THRESHOLD]`.
- **Threshold decoupling**: non-AI strategy pipeline/validator floors are now configured separately from `InpAIConfidenceThreshold`, preventing AI policy from suppressing curated human strategy flow.
- **Throughput observability**: runtime heartbeat now emits funnel counters/rates (`[HEARTBEAT-FUNNEL]`, `[CONVERSION-RATES]`) to quantify conversion recovery without bypassing validator/risk gates.

## Runtime No-Trade Recovery Update (2026-03-07)
- **Contributor-aware quorum**: silent but eligible live voters no longer keep intrabar quorum artificially at `2` when only one live contributor is actually signaling.
- **Operator mode clarity**: startup now emits `[EXECUTION-MODE]` so shadow sessions are obvious in the log before trade debugging begins.
- **Analytics bootstrap**: `PerformanceAnalytics` is now initialized explicitly before `CUnifiedRiskManager` consumes it.

## Execution Safety Hardening Update (2026-03-07)
- **Synchronous market sends**: `CTradeManager` no longer defaults to async execution, removing the most dangerous mismatch between broker confirmation and EA-side success accounting.
- **Repriced market protection**: market orders now resolve current execution price at send time and recalculate SL/TP from that price on each retry attempt.
- **Sizing consistency**: `PositionSizer` now uses tick-size/tick-value risk math and `min(balance,equity)` denominator alignment with the risk gate.
- **Restart-safe lifecycle reconstruction**: the EA-owned position lifecycle path rebuilds partial-close and breakeven state for already-open positions using trade-manager-managed lifecycle state plus position identifiers and history-derived entry volume.
- **Close-driven analytics**: confirmed close deals now update `PerformanceAnalytics` from `OnTradeTransaction`, and startup rejects unsupported non-hedging account models.

## Timeframe + AI Feedback Update (2026-03-16)
- **Timeframe-consistent consensus**: manager consensus now applies `TimeframeConsistency` to resolve conflicts across mixed strategy timeframes.
- **Correct OnNewBar dispatch**: strategy `OnNewBar` now receives its registered timeframe instead of the manager base timeframe.
- **AI feedback wiring**: AI prediction/outcome tracking now records live-trade predictions and closes with position-mapped outcomes.

## Quorum Admission Alignment + Smoke Controls Update (2026-03-24)
- **Consensus admission alignment**: `EnterpriseStrategyManager` now admits votes using the pipeline's last effective confidence floor, eliminating the mismatch where a signal could pass `[PIPELINE-THRESHOLD]` and still be excluded from quorum.
- **Smoke-test intrabar controls**: added opt-in intrabar eligibility inputs for `Fibonacci` and `Support/Resistance` so productive mean-reversion contributors can be widened for smoke tests without changing production defaults.

## Startup State Recovery + Capacity Diagnostics + Regime Fault Resilience Update (2026-03-24)
- **Restart-safe cooldown state**: startup now reconstructs `g_lastTradeTime` from EA-owned deal history and currently open EA positions, so inherited positions no longer leave the runtime in a false `Last trade: Never` posture.
- **Low-balance visibility**: startup now emits `[ACCOUNT-CAPACITY]` diagnostics showing whether free margin can support the symbol minimum lot, making underfunded smoke environments obvious before forced execution debugging.
- **Transient regime fault resilience**: `CRegimeEngine` can reuse a recent valid snapshot on warmup / buffer-copy / handle-init faults and performs bounded handle reset after repeated data faults, reducing avoidable throughput collapse without bypassing the pipeline.

## Entry Gate Decoupling Update (2026-03-24)
- **Scan-through-cooldown behavior**: cooldown and other entry blocks no longer short-circuit the symbol evaluation loop, so `[CONSENSUS-QUORUM]`, `[SIGNAL-VALIDATED]`, and heartbeat funnel telemetry continue after a live fill.
- **Entry-only suppression**: approved signals that cannot proceed because of cooldown, portfolio caps, unprotected positions, or per-symbol capacity now emit explicit `[ENTERPRISE-BLOCKED]` diagnostics instead of disappearing from the runtime path.

## Efficiency + Conviction Upgrade (2026-03-25)
- **Shared pipeline evidence**: `UnifiedSignalPipeline` now caches structural engine state per symbol/timeframe/bar and emits a reusable evidence snapshot (`readiness`, `context`, `cost`, effective confidence floor, soft-threshold pass) instead of recomputing the same context for every strategy vote.
- **Smarter consensus**: `EnterpriseStrategyManager` now computes directional conviction from adjusted strategy weight (`base weight x role multiplier x rolling healthScore`) and requires both weighted conviction and minimum ready-live-weight participation before a side wins.
- **Conflict handling without false neutralization**: timeframe resolution still owns mixed-timeframe conflict handling, but the old hot-path hedging neutralization no longer wipes out otherwise valid directional consensus before quorum can act.
- **Context-aware validator**: `AdvancedSignalValidator` now grades signals with consensus/path evidence (`conviction`, `readiness`, `context`, `cost`, `diversity`, `freshness`) and allows bounded soft passes near the profile floor when the broader setup is strong.
- **Cycle-level candidate ranking**: the EA no longer fires the first acceptable symbol; it stages all risk-approved opportunities, logs them as `[SCAN-CANDIDATE]`, and executes only the highest-ranked candidate via `[SCAN-DECISION]`.
- **Execution accounting fidelity**: `TradeManager` now emits `[EXECUTION-RECEIPT]`, partial fills emit `[FILL-DIFF]`, and `UnifiedRiskManager` registers consumed daily entry risk against actual fill ratio.
- **Lower telemetry overhead**: `SignalDiagnostics` now batches file flushes instead of forcing an on-disk flush on every write.

## Runtime Integrity + Lifecycle Update (2026-03-25)
- **Readiness cache correctness**: `Core/Pipeline/UnifiedSignalPipeline.mqh` now replays the original structural readiness snapshot on same-bar cache hits instead of force-upgrading cached engines to `ready=true`, and it suppresses stale getter reuse when an engine is not ready.
- **Fail-closed pipeline startup**: `CUnifiedSignalPipeline::Initialize()` now returns failure when required components are not constructed, and `CEnterpriseStrategyManager::Initialize()` propagates that failure instead of running a degraded but silent pipeline.
- **Symbol-scoped engine hygiene**: `Core/Engines/LiquidityEngine.mqh` now uses the requested symbol's point size instead of `_Symbol`, resets on data-copy failure, and `Core/Engines/RegimeEngine.mqh` clears spread-shock cooldown state on symbol/timeframe changes.
- **Shared ATR lifecycle for sizing**: `Core/Risk/PositionSizer.mqh` now prefers `IndicatorManager` ATR handles before falling back to its local handle path, reducing duplicated indicator lifecycle policies between sizing and the rest of the runtime.
- **Risk-budget-aware sizing**: `MultiStrategyAutonomousEA.mq5` now caps requested per-trade risk through `CUnifiedRiskManager::GetRecommendedRiskPerTradePercent(...)` before sizing, emitting `[RISK-CAP]` whenever daily or portfolio headroom forces a tighter budget.
- **Per-scan explainability**: the scan loop now emits `[SCAN-NO-TRADE]` with consensus reason context and expands `[QUIET-REASONS]` to include cadence holds, missing managers, entry blocks, and sizing rejects.
- **Execution preflight + confirmation**: `Core/Trading/TradeManager.mqh` now blocks stale/invalid/stress quotes via `[EXECUTION-BLOCKED]`, treats success as a confirmed fill rather than a raw broker accept, and emits `[EXECUTION-UNCONFIRMED]` when a broker response could not be confirmed safely.
- **Verification status**: `sync_and_compile.ps1 -MirrorSync` passed with `0 errors, 0 warnings`; a bounded MT5 shadow launch was attempted, but this environment still did not emit fresh EA-level tester artifacts for the new logs.

## Weighted Quorum + Live Strategy Promotion Update (2026-03-16)
- **Historical note**: this batch introduced weighted confidence quorum; the current runtime extends it further with readiness/health-based conviction weighting from the 2026-03-25 efficiency upgrade.
- **All retained strategies vote live**: every enabled retained strategy is registered as a live primary voter (no feature/shadow suppression).
- **Weighted quorum**: consensus now passes when normalized weighted confidence crosses `InpQuorumThreshold` and `InpMinLiveVoters` is satisfied; per-evaluation scores are emitted as `[CONSENSUS-QUORUM]`.
- **Operator tuning**: per-strategy weights are configurable via inputs (`InpWeight*`) without code changes.

## Institutional Strategy Betterment Update (2026-02-24)
- **Note:** This batch is historical; current default voting behavior is defined by the 2026-03-16 weighted quorum + live strategy promotion update above.
- **Soft quarantine strategy governance**: all retained strategy modules stay loaded for diagnostics, but default live-voting authority is constrained to `Momentum`, `Trend`, and `Unified ICT`; weaker legacy modules are feature/shadow by default.
- **Role/cluster metadata**: strategy registration now carries `PRIMARY_ALPHA`, `CONTEXT_FEATURE`, `SHADOW_RESEARCH` roles and cluster tags (`TREND_CLUSTER`, `MEAN_REVERSION_CLUSTER`, `STRUCTURE_CLUSTER`).
- **Regime + cost gate**: `UnifiedSignalPipeline` now runs deterministic regime/microstructure viability checks (`[REGIME-STATE]`, `[COST-GATE]`, `[ENTRY-VETO]`) before validator/risk.
- **Momentum anti-spam refactor**: momentum now requires state alignment + compression-to-break trigger, reducing crossover-only churn.
- **Unified ICT event tuple**: live signal path is constrained by falsifiable tuple checks (structure break + displacement + mitigation/retest) with bounded quality scoring and range-only counter-trend allowance.
- **Cluster-aware risk governance**: risk request now includes role/cluster/contributor context; risk gate enforces same-symbol opposing-cluster mutex and per-cluster position/risk caps (`[RISK-CLUSTER]`, `[RISK-MUTEX-BLOCK]`).
- **Role/cluster telemetry**: heartbeat now reports `[ROLE-CLUSTER]` counters and manager diagnostics report `[CONSENSUS-ROLE]` / `[CONSENSUS-CLUSTER]`.

## Default Runtime Remediation Update (2026-04-01)
- **False trend warmup removed**: `Core/Engines/TrendEngine.mqh` no longer hard-blocks mature-series ATR `BarsCalculated == -1` states before attempting an ATR read. The engine now tries a bounded ATR fallback first, then degrades explicitly if needed.
- **Idle-cycle suppression**: `MultiStrategyAutonomousEA.mq5` now emits `[SCAN-BUDGET]` with `hybrid`, `newbar_only`, and `active_work`, and it skips the full symbol loop on cycles that have neither a new bar nor an intrabar selection.
- **Governance alignment**: `Support/Resistance` intrabar governance now maps to `PROBE` when enabled instead of being silently forced to `OFF`.
- **Compile hygiene**: `Strategies/StrategyElliottWaveEnhanced.mqh` now uses valid MT5 line-style enums and relies on the inherited min-confidence contract, restoring clean compilation with `0 errors, 0 warnings`.
- **Operator note**: the analyzed `default.log` did not match current source defaults, so baseline validation should always confirm startup telemetry such as `[EXECUTION-MODE]` and `[CADENCE-CONFIG]`.

## Strategy Registry + AI Runtime Update (2026-04-01)
- **Registry-backed activation**: startup now builds a single `CStrategyRegistry`, logs `[STRATEGY-REGISTRY]`, and exposes `InpEAMode` so indicator-only, AI-only, hybrid, AI-assisted, and indicator-filtered operating modes are explicit instead of implicit.
- **Effective-mode safety**: impossible mode mixes now degrade cleanly to a viable effective mode at startup instead of leaving the runtime with an empty strategy family.
- **Mode-aware post-consensus gating**: the EA can now reject candidates that violate the active mode contract and emits `[AI-MODE-BONUS]` when `AI_ASSISTED` receives aligned AI confirmation.
- **Intrabar keepalive**: hybrid cadence now has a bounded keepalive pick when backoff/scheduling would otherwise leave `intrabar_selected=0` for a whole cycle, and `[SCAN-BUDGET]` includes `intrabar_keepalive`.
- **Trend MA recovery**: `CTrendEngine` now treats mature-series MA copy failures as recoverable and attempts manual EMA reconstruction before reusing stale trend state.
- **Lighter AI path**: transformer defaults are now right-sized for MT5 (`64/4/2/128/50`), transformer adapters consume short real bar sequences, and the NN validates its feature vector before inference/training while optionally enriching its tail with transformer-encoded context.

## Documentation Index
- Full structure specification: `SYSTEM_STRUCTURE.md`
- Runtime decision path: `RUNTIME_DECISION_GRAPH.md`
- Lifecycle trace: `SYSTEM_AUDIT_TRACE.md`
- Forward maintenance protocol: `MAINTENANCE_PROTOCOL.md`
- Agent workflow contract: `AGENTS.md`
- Changelog: `changelogs.md`
- Audit scratchpad: `AUDIT_REPORT.md`

## Documentation Policy
- Any runtime behavior change must update:
  - `RUNTIME_DECISION_GRAPH.md` (decision path changes)
  - `SYSTEM_STRUCTURE.md` (component/ownership changes)
  - `changelogs.md` (dated batch)
  - `README.md` (operational impact)

## Synthetic Assets Expansion (v2.0 Update)
- Native 24/7 continuous trading execution is inherently supported across modern synthetics: Step Index, Jump 10, PainX, SFX Vol, GainX, FX Vol, and FlipX.
## Batch 76 Highlights
- AI controls are now explicit in the EA inputs:
  - MT5-native live voters: `InpEnableNeuralNetwork`, `InpEnableTransformer`, `InpEnableEnsemble`
  - Python-trained but MT5-served live voter: `InpEnableOnnxAI`
  - Python sidecar expectation/telemetry: `InpPythonBridgeMode`, `InpPythonBridgeEndpoint`
  - External reasoning sidecar: `InpEnableExternalLLM`, `InpExternalLLMEndpoint`
- Startup now emits `[AI-TOPOLOGY]` so operators can see which AI families are truly live voters, which are dashboard/context-only, and which Python/LLM surfaces are only sidecars.
- The EA-level breakeven/trailing manager is now explicit and opt-in through `InpEnablePositionLifecycleManager`; the old hidden tiny-point lifecycle behavior that caused early scalp-style exits is no longer applied by default.
- Candlestick rendering no longer duplicates engulfing labels, and engulfing detection now rejects weak/doji-style candidates more aggressively.
