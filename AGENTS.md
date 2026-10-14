# AGENTS.md

## Document Metadata
- Last Updated: 2026-10-14
- Scope: Agent workflow contract for this repository
- Latest Batch: Batch 197 - the four engines moved into their own magic bands (fast scalp `base+6000`, ATR scalp `+6100`, grid `+6200+level`, spike `+6300`, all under ASSET_FOREX's 7000), because a fast scalp sent through `CTradeManager` carried its own symbol's consensus magic and the ATR scalp carried `base+7000+symbolIndex`: `CStrategyMgrTradeFeedback::IsEAOwnedMagic` accepted a scalp deal as that strategy's own trade, which feeds the reliability multiplier that sizes the next lot. Same batch: grid level state is rebuilt from open positions at init (`RecoverOpenGridLevels`, decoding the new band and the legacy 8000 band), `[MAGIC-LAYOUT]` refuses the start if a symbol slot composes into a band, `CPositionLifecycleManager::IsEAOwnedMagic` - the last class still on `base + symbolCount*100 + cluster` (ceiling `+1399` against magics shipped at `+7000..9400`, so Signal Reversal Exit and ranging breakeven never ran on twelve of thirteen symbols) - delegates to `CMagicRange`, and `CMagicNumberAllocator` (395 lines, a parallel offset table with no call site whose adoption would renumber live positions) is deleted with `m_maxClusterCode`. Positions opened before the renumber keep their magic, so the send comment is still the exit discriminator.
- Recent context: Batch 196 made fill confirmation resolve an owner from the order comment because magic could not (`FindFreshPositionForSend` accepted any EA-owned position on the symbol inside 30s, `requestedVolume` unread); Batch 195 restored two missing `GetType()` overrides (`GetStrategyType()` lookalikes reporting `STRATEGY_TYPE_CUSTOM`), returning Range Compression's confirmed-trend regime veto; Batch 194 reconnected three inert strategy inputs and gave Mean Reversion its synthetic branch, applying them in `ConfigureBeforeInit` because `Init` reads them; Batch 193 restored five suppressed entry paths and moved strategy registration and consensus voting weight onto the catalog row. Each has its own section in `changelogs.md` and `RUNTIME_DECISION_GRAPH.md`.
- Changelog: `changelogs.md` restarts at Batch 170; Batches 102-169 are archived in `docs/changelogs_batch102-169.md`

## 1. Mission
Maintain and evolve `metatrader-multistrategy-ea` with production-safe discipline:
- preserve runtime invariants
- keep decisions explainable from logs
- prevent regression in risk ownership and execution flow
- maintain synchronized documentation

## 2. Core Operating Principles
1. Determinism over convenience.
2. One authority per domain (consensus, risk, execution, lifecycle).
3. Log-driven verification before claims.
4. Live-only operation: no shadow/paper mode — changes are validated via compile + static review and deployed straight to live.
5. Documentation updates are part of completion, not optional follow-up.

## 3. Non-Negotiable Technical Invariants
1. All trade entries must pass `CUnifiedRiskManager` pre-trade gating.
2. Runtime execution must remain `CTradeManager`-owned.
3. Position lifecycle must remain EA-loop-owned via `MultiStrategyAutonomousEA.mq5` calling `CTradeManager::ManageAllPositions(...)`.
4. Strategy decisioning must remain symbol-scoped manager consensus.
5. `CIndicatorManager::DestroyInstance()` must be called on deinit.

## 4. Strong Workflow for Better AI Usage

### 4.1 AI feature change protocol
When touching AI modules/adapters/orchestrator:
1. Verify adapter registration exists for each enabled AI mode.
2. Verify runtime call-sites produce vote logs (`[AI-VOTE]`).
3. Verify orchestrator registration with qualified names (`symbol::strategy`).
4. Verify weight adaptation sync path back into managers.
5. Verify failure mode (AI disabled) still produces clean non-AI behavior.

### 4.2 AI diagnostics minimum evidence
A valid AI-related change must include evidence of:
- non-zero AI vote activity
- no hard runtime errors in adapter paths
- consensus behavior with and without AI flags
- unchanged risk veto behavior

### 4.3 Prompting/analysis discipline for future agent sessions
- Do not infer runtime health from init logs alone.
- Distinguish initialization evidence from runtime participation.
- Always map issue claims to file path + log signature.
- If behavior is time-sensitive, gather fresh logs from the active session.

### 4.4 Strategy identity contract (Batches 193-195)
A strategy is known by four identities and they must agree; each one has already been broken independently in this repository:
1. Catalog row `name` - `RegisterStrategy`/roster/`GetStrategyByName` key, and what `IsStrategyActive(name)` matches.
2. Catalog row `registryType` - what `BuildStrategyRegistry` registers, so a missing value means the strategy can never pass the mode filter.
3. `GetType()` override - what consensus reads for `RegimeStateHardGate` and the category multiplier. `CStrategyBase::GetType()` answers `STRATEGY_TYPE_CUSTOM`, and a method named `GetStrategyType()` overrides nothing.
4. `InpEnable*` / `InpWeight*` slots - `CatalogEnableSlot(i)` must resolve to the row's own `SI_*`, and the weight reaches consensus only through the row (`ApplyCatalogWeightOverrides`), not through the registry descriptor.
When adding a strategy, verify all four name the same thing. When touching one, grep the other three: the factory path still contains indicator configuration that no longer runs (see `SYSTEM_STRUCTURE.md` §2.2.3), so an input can look wired while reaching nothing.

## 5. Execution Workflow

### 5.1 Standard task sequence
1. Gather context from code + active logs.
2. Identify root cause with explicit evidence.
3. Implement minimal complete fix.
4. Run compile/sanity checks.
5. Validate with runtime logs.
6. Update docs/changelog.

### 5.2 Runtime test mode policy
- Prefer persistent terminal sessions (normal or `/portable`).
- Avoid repeated `/config` launch loops for manual workflows.
- Major changes ship straight to live; validate via compile + static review (AGENTS.md §3 invariants) and log-driven verification (§6) before deploy.

### 5.3 Where runtime evidence actually lives
Past sessions' logs are the terminal's own EA journals: `<terminal data dir>/MQL5/Logs/YYYYMMDD.log`, **UTF-16LE** — `iconv -f UTF-16LE -t UTF-8` before grepping or nothing matches. Check the newest file's date before claiming anything about "current" behavior; as of Batch 179 the latest journal was 2026-09-23, which means the October batches had never run. `[POST-CONSENSUS-FILTER] filter=true` in those files is `trend_filter=true` from `[ENTERPRISE-CONFIG]`, not a filter event.

## 6. Logging and Validation Checklist
After any strategy/risk/execution change, verify:
- `[HEARTBEAT]`
- `[CONSENSUS-DIAG]`
- `[SIGNAL-REJECTED]`
- `[AI-VOTE]` (if AI enabled)
- `[AUTHORITY-REJECT]` / `[AUTHORITY-REDUCED]` or live trade result logs
- `[POST-CONSENSUS-FILTER] filter=vpin_extreme | VETO` (if VPIN enabled; since Batch 174 the EXTREME regime vetoes entries at `InpVPINExtremeThreshold` instead of only shrinking the lot, and since Batch 175 the arm is actually switched on by its input)
- `[VALIDATOR-CONFIG]` once per symbol at init (Batch 175: the validator's only configuration call site; if it is absent from a session log, no symbol has OFI/VPIN screening)
- `[AUTHORITY-GATE]` once at init (Batch 179: the live-authority resolver runs on every risk-approved candidate; `InpEnableLiveAuthorityGate` gates nothing but this line, so do not read `false` as "authority off")
- `[ENGINE-STATUS]` once at init (Batch 178: names the engines whose inputs say ON but that have no tick-loop caller, so they open no trades)
- `[SCALP-ENTRY] ... ticket=` carrying a **position** ticket (Batch 179: an order ticket here means the tracker slot is dropped next pass and its risk budget released while the position is open)
- `[RISK-GATE-REJECT] ... reason=compliant_lot_below_min` (only where a trade cannot be sized inside the per-trade cap at the broker minimum)
- `[RISK-GATE-REJECT] ... reason=final_lot_validation | reason=adjusted_lot_below_min | reason=correlation_reduce_below_min_lot` (Batch 190: the unified risk gate now runs on the lot the candidate actually ships, so entries that once passed on a 0.01-lot evaluation can now be refused)
- `[RISK-GATE-ADJUST] ... lot=A -> B | risk=x% -> y%` (Batch 190: the gate approved but asked for a smaller lot, and the builder adopted it)
- `[POST-CONSENSUS-FILTER] filter=quality_gate ... quality=... threshold=...` (since Batch 190 the threshold derives from the configured floor, not from the quality being tested, so `InpValidatorNewBarMinQuality` / `InpValidatorIntrabarMinQuality` actually bind — expect more of these lines, not fewer)
- `[SCALP-RISK-ADJUSTED] ... lot=A -> B | reason=` (Batch 192: the risk manager shrank a fast-scalp lot; absence of this line with a lot different from `CPositionSizer` output means the shrink was not adopted. The scalp path runs `ValidateTradeRequest` **once** — two `[RISK-VIRTUAL] reserve` lines for one scalp is the regression this batch removed)
- `[COMPOUNDING-TIER] Applied to PositionSizer | riskPercent=X (tier Y% ...)` (Batch 192: the tier value is clamped to the risk manager's approved per-trade risk; `clamped to approved envelope` means the tier asked for more than the operator ceiling)
- `[CATALOG] <name> | registration weight A -> B from operator input` (Batch 193: the catalog row, not the literal, is what `ConsensusEngine` weights votes by. If `InpWeight*` is changed in the inputs dialog and no such line appears, the weight still did not reach voting)
- `[STRATEGY-REGISTRY] <name> has no registryType in its catalog row - it cannot pass the registry filter` (Batch 193: indicator definitions come from the catalog, so a row that omits `registryType` says so at init instead of being silently unregistered — the failure mode that left Statistical Arbitrage untradeable for its whole life in the repo)
- `[DORMANT-COOLDOWN] <symbol> | cooldown expired, strikes reset | evaluating again` (Batch 193: absence of this line, with the park line present repeatedly for one symbol, means dormancy is re-arming and that symbol is only evaluated once per cooldown window)
- `[SCALP-GATE] <symbol> | entry refused | usedRisk=x% of budget=y% | maxPos=n | cooldownLeftMs=n` (Batch 193: the three scalp gates used to refuse with no output; a 0% tier budget no longer zeroes `maxScalpPositions`, so a refusal here is a live limit, not an init latch)
- `[CANDIDATE-BUILDER] <symbol> | stop pinned to floor | designed= floor= spread= tp= costRatio= limit=` (Batch 193: the designed stop was below `max(broker*1.5, spread*3, 8)`, so TP is a multiple of the floor and `costRatio` is arithmetic, not a market reading — read it before treating a following `execution cost` veto as a statement about the symbol)
- `[MEANREV] Initialized ... path=synthetic(1.5sigma+spike)` / `path=fx(bands+rsi+volume)` (Batch 194: which branch the strategy will run. A synthetic index reporting `fx` means `IsSyntheticIndexSymbolName` did not match it, so the symbol is misclassified rather than the flag being unwired)
- `[MOMENTUM] Effective mode=scalping|trend-following | TF=... | scalpCooldown=ns | sameBarGuard=bypassed|active` and, when the input was refused, `[MOMENTUM] Scalping input ON but H1 is outside the M1-M15 band ...` (Batch 194: `InpEnableMomentumScalping` is live, and the strategy's own timeframe band now binds rather than being advisory — read the mode line, not the input, for what a symbol is doing)
- `[STRATEGY-CONFIG] Candlestick row did not yield a CStrategyCandlestick ...` / `... Momentum row did not yield a CSimpleMomentumStrategy ...` (Batch 194: `ConfigureBeforeInit` failing its cast — the catalog row names a class the creator did not build)
- `[CONSENSUS-REJECT] <symbol> | Ready weight ratio X < min Y` (Batch 195: a strategy whose regime multiplier is 0 keeps its weight in this denominator while contributing no score, so this line is where a regime veto shows up. It is *not* evidence the vote was dropped — a zeroed multiplier still counts toward `winningVotes >= effectiveMinVoters`, which is the known gap at `ConsensusEngine.mqh:439`)
- `[EXECUTION-CONFIRMED-BY-POSITION]` / `[EXECUTION-DEDUP]` / `[GRID-RECOVERY] FILL CONFIRMED BY POSITION` / `[SCALP-ENTRY] ... ticket=0 | position not visible yet` (Batch 196: since the matcher resolves an owner from the order comment, a confirm line means the position carries the confirming sender's prefix - it is no longer evidence that *some* EA position existed. `ticket=0` on a scalp is now the correct answer when only another owner's fill is in the window)
- `[MAGIC-LAYOUT] consensus=base+assetOffset+symbolIndex*N (max +M) | fastScalp=+6000 | atrScalp=+6100 | grid=+6200+level | spike=+6300` once per start (Batch 197: the four engines now ship their own bands, under ASSET_FOREX's 7000, so a scalp fill is no longer that symbol's consensus magic and `CStrategyMgrTradeFeedback` can stop attributing it to the strategy. `[CRITICAL] Magic layout collides with an engine band` means a symbol slot composes into 6000..6399 - only an `ASSET_UNIVERSAL` symbol at slot 60+ can - and the EA refuses to trade, which is correct: do not "fix" it by widening the window). Positions opened before Batch 197 keep their old magic, so the send comment is still the exit discriminator; `[SCALP-ENTRY]`/`[GRID-RECOVERY]` receipts on a legacy position are matched by comment, not by band.
- `[GRID-RESTART] <symbol> | N level(s) rebuilt from open positions | direction=... | baseLot=...` at init (Batch 197: the level table used to be memory-only, so a restart left open grid positions with no manager while the engine laid a fresh level 0 on top of them. `is not a level slot in 0..N, left untracked` means a `GRID-RECOVERY`-commented position sits outside both decodable bands - the level band `base+6200 + level` and the legacy `base+8000 + slot*100 + level` - which only a changed `InpMagicNumber` can cause; that position stays unmanaged. `N already held by ticket=` is a duplicate slot claim, not a loss. No such line while a grid position is open = recovery found nothing.)
- `[SCALP-EXIT] Reversal detected on ...` and `[STRUCTURAL-EXIT] ... trend invalidated` on consensus positions (Batch 197: `CPositionLifecycleManager::IsEAOwnedMagic` was the last class still using `base + symbolCount*100 + cluster`, which on the default 13-symbol universe capped at `base+1399` against magics shipped at `base+7000..9400` - twelve of thirteen symbols read as "not ours", so `InpEnableSignalReversalExit = true` had no effect and no ranging position ever moved to breakeven. Their absence now is a real signal, where before it was the only possible output. Note the reversal exit prints under the `[SCALP-EXIT]` tag although it is the lifecycle path, not the scalp engine - read the symbol and reason, not the tag.)
- `[PYTHON-BRIDGE-DASHBOARD]` (if Python bridge enabled)
- `[COMPOUNDING-TIER-HEARTBEAT]` (if compounding tiers enabled)
- `[COMPOUNDING-TIER-MILESTONE]` (on account milestone crosses)
- `[FAMILY-WEIGHT-MATRIX]` (per-family cluster weighting active)
- `[FAMILY-WEIGHT-VOL]` (volatility family weight deviation log)
- `[SESSION-WEIGHT-HEARTBEAT]` (session-aware adjustments)
- `[SKEW-STEP-HEARTBEAT]` (Skew Step phase analysis)
- `[RISK-FAMILY-POS]` (family position limit blocked trade)
- `[ADX-MODIFIER]` (ADX-based lot scaling applied)

## 7. Compile and Artifact Hygiene
- Compilation helpers may create temporary `.log/.txt` artifacts.
- Default behavior should remove compile artifacts after run.
- Keep artifacts only when explicitly needed for debugging (`-KeepCompileArtifacts` style control).

## 8. Documentation Contract
Every meaningful implementation batch must update:
- `README.md` (operational impact)
- `SYSTEM_STRUCTURE.md` (architecture/ownership changes)
- `RUNTIME_DECISION_GRAPH.md` (decision path changes)
- `SYSTEM_AUDIT_TRACE.md` (lifecycle changes)
- `changelogs.md` (dated batch entry)

## 9. Safety and Change Control
- Never use destructive git reset/revert operations unless explicitly requested.
- Never silently remove unrelated user changes.
- If unexpected external modifications appear during work, stop and ask user how to proceed.

## 10. Definition of Done
1. Compile passes.
2. Runtime invariants preserved.
3. Required log evidence captured.
4. Docs/changelog updated.
5. No unwanted compile artifacts left behind.
