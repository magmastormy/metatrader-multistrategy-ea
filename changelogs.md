# Changelog

All notable changes to the `metatrader-multistrategy-ea` project are documented in this file.

This file starts at **Batch 170**. The previous history is preserved unchanged:
- Batches 102–169 (2026-08 → 2026-10): [`docs/changelogs_batch102-169.md`](docs/changelogs_batch102-169.md)
- Batch 101 and earlier: [`docs/changelogs_old.md`](docs/changelogs_old.md)

## [Unreleased] - 2026-10-14

### Batch 196: fill confirmation accepted any EA-owned position, because magic cannot tell these senders apart

#### The matcher (`Core/Trading/TradeMgrPreflight.mqh`)
`FindFreshPositionForSend(symbol, orderType, requestedVolume, ticketOut, volumeOut)` is the fallback that answers "did my send actually fill when the broker said it failed?". It tested four things: same symbol, same side, `IsMagicOwned`, opened within 30 s. Not the sender. Its `requestedVolume` parameter was never read. Any position another owner opened on that symbol inside the window was a valid answer.

Magic could not have been the discriminator, which is why the gap survived: a fast-scalp market order goes through `CTradeManager::OpenPosition`, and `TradeManager.mqh:1267` composes `base + per-symbol offset` for market orders - the same magic a consensus entry on that symbol carries. So on one symbol, a scalp send and a consensus send are indistinguishable by magic, and `IsMagicOwned` is true for both.

#### What a wrong "yes" cost
Six call sites consumed this answer, and each one turns it into state. `GridRecoveryExecution` sets `result = true` and stores the ticket as the level's, then closes levels through `PositionSelectByTicket`/`PositionClose` on exactly that ticket - a level bound to a foreign position is a level that closes a position it does not own. `FastScalpEntry` registers its tracker slot under the adopted ticket, so the slot's risk release and the tick-level management path act on the wrong position while the engine's own fill, if there was one, goes untracked. `SpikeHunterExecutor` and `ATRScalpEntry` mark the spike/scalp opened and suppress the re-fire. On the consensus side (`TradeMgrPreflight.mqh:254`, `TradeManager.mqh:1335`) the receipt gets `accepted = true`, `filledVolume` and a `partialFill` ratio computed from the foreign volume, so the EA books a trade it did not get and attribution and health metrics are fed a fill that never happened. Two of the four engines are parked (no tick-loop caller since Batch 178), so today the live surface is fast-scalp plus both consensus sites.

#### The rule now
`FindFreshPositionForSend` takes an optional `expectedCommentPrefix`. A caller that names one matches only positions whose comment starts with it; a caller that names none matches only positions no engine claims (`HasEngineComment` over the four prefixes the codebase already uses for ownership decisions: `SCALP`, `ATR-SCALP`, `GRID-RECOVERY`, `SPIKE-HUNT`). The five engine sites pass their own prefix; the two consensus sites keep the empty default and therefore can no longer adopt an engine fill. The order comment is the field the exit paths already trust - `FastScalpExit.mqh:63` closes on `StringFind(comment,"SCALP")==0` and `ATRScalpExit.mqh:70` on its own prefix - so this adds a dependency the account is already carrying rather than a new one.

Checked before writing this: the live fast-scalp send is the **synchronous** branch (`InpScalpAsyncMode = false`), which sends with `comment = "SCALP|EMA<fast>/<slow>|C:<conf>"`; the async branch composes `"AsyncTrade"` and returns before reaching the confirm block, so the prefix is present on every position the `"SCALP"` matcher is asked to find. `"ATR-SCALP|"` does not match the `"SCALP"` prefix (it starts at offset 4), which is the same asymmetry Batch 170 relied on when it made the scalp exit a prefix test. One behaviour the change removes in the other direction: `TradeManager.mqh:1335` is the transient-retcode dedup guard, and an engine position on the same symbol inside 30 s could previously make it conclude "this send already filled" and refuse a legitimate consensus entry. Consensus sends carry the caller's comment (empty by default), so they are still matched by the empty-prefix rule and the dedup keeps working for its own fills.

#### Risk direction
Strictly fewer false confirmations. A false "yes" used to bind tracking state, risk release and close operations to a position the sender did not open; a false "no" re-fires only the engine's own retry path, which every site already bounds with its own cooldown and counter. No magic, comment, ownership range or lot on any send changed, so positions already open keep the identity that manages them.

#### Recorded, not changed
- `requestedVolume` is still not read by the matcher. Making it a filter would break partial-fill confirmation (the fill is legitimately smaller than the request), which is the case Batch 177 added this helper for, and a volume *ceiling* would not catch the common case of a smaller foreign position. The owner prefix is the correct key.
- The underlying magic overlap (scalp and consensus sharing `base + symbol offset`, and `ATRScalpEntry` composing `base + 7000 + symbolIndex` where 7000 is also the FOREX asset offset) stays open as task #37. Re-numbering it would orphan positions already open on this account, which §9 forbids without the operator's decision.
- `FastScalpPendingOrders::FindRecentScalpEntry`'s pending-order loop already filtered by magic correctly; only its position fallback needed the prefix.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, `OVERALL SUCCESS`, 0 errors / 0 total warnings.
- No runtime evidence yet (newest journal 2026-09-23). Expected change: `[SCALP-ENTRY] ... ticket=0 | position not visible yet` becomes the honest answer when only a foreign position is in the window, and `[EXECUTION-CONFIRMED-BY-POSITION]` lines can no longer appear for a symbol whose fresh position belongs to an engine.


### Batch 195: two strategies never overrode `GetType()`, so a regime veto never fired

#### Context
`IStrategy::GetType()` is pure virtual and `CStrategyBase::GetType()` returns `STRATEGY_TYPE_CUSTOM`. Twelve indicator strategies override it. Two do not: `CLiquiditySweepStrategy` and `CRangeCompressionBreakout` declare `GetStrategyType()` instead - a different name, no `override`, and no call site anywhere in the repository - so both have reported CUSTOM to the consensus engine for their whole life. The catalog row's `registryType` (Batch 193) and the registry name match never consult `GetType()`, so nothing else looked wrong: registration, weights, magic and the `[ENTERPRISE]` reports all named them correctly.

#### The veto that did not fire (`Core/Management/ConsensusEngine.mqh`)
`RegimeStateHardGate` classifies `STRATEGY_RANGE_COMPRESSION` as reversion-like alongside Mean Reversion and returns 0.0 in `REGIME_TREND`, above the comment "fading it is the fastest way to blow an account". With the type arriving as CUSTOM the classification was false, so a compression-fade vote kept full score inside a confirmed trend regime. `GetRegimeCategoryMultiplier` also groups `STRATEGY_RANGE_COMPRESSION` with Volatility Breakout under `breakoutWeightMult` and `STRATEGY_LIQUIDITY_SWEEP` with the ICT family under `ictWeightMult`; both were taking the `default: 1.0` branch instead of their regime weight.

Both classes now override `GetType()` and return the same `STRATEGY_*` value their catalog row declares, so the two identities cannot drift. The dead `GetStrategyName()` accessors went with them - `CStrategyBase::GetName()` already returns the name each class passes to the base constructor ("LiquiditySweep", "RangeCompressionBreakout").

Checked before assuming: every other `GetType()` consumer compares against `STRATEGY_BRAIN` / `STRATEGY_AI_ENHANCED` (`ConsensusEngine.mqh:338`, `:1225`, `ConsensusWeightingConfig.mqh:77`, `StrategyPerformanceHealth.mqh:299`, `StrategyStateReporter.mqh:97`) or resolves a type for the live-authority report (`LiveAuthorityResolver.mqh:368`), so CUSTOM vs their real type changed nothing there. `CMagicNumberAllocator::GetStrategyOffset` does switch on strategy type and would have moved these two positions to another magic bucket - but the allocator is declared as `m_magicNumberAllocator` in the orchestrator and **no method of it is called anywhere**, so it is not the live magic scheme and this fix cannot renumber an open position.

#### One comment corrected, and the gap it was hiding
`GetRegimeCategoryMultiplier` returned `0.0` under the comment "vote disabled entirely". It is not: a zeroed multiplier removes the vote's score and puts its weight in the `votedWeight` denominator (so it does dilute `readyWeightRatio`, which is where the veto has teeth), but the vote still increments `buyVotes`/`sellVotes` and joins `buyContributorIndices`, so it can still satisfy the minimum-voter floor. Making it drop the vote outright was rejected for this batch: that tightens `winningVotes >= effectiveMinVoters` while loosening the ready-weight ratio by removing the vetoed weight from the denominator, and a mixed change to quorum arithmetic on a live book needs runtime evidence this repository does not have (newest journal 2026-09-23). The comment now says what the code does, and the remaining hole is on the open list.

#### Also recorded, not changed
`IStrategy::GetWeight()` is pure virtual and implemented by every strategy class, and it has **no caller anywhere**: `RegisterStrategy` writes the value into the object with `SetWeight` and also into the roster, and consensus reads the roster copy (`GetStrategyWeight(i)`). So the object-level weight is a write-only mirror - harmless since Batch 193 made the roster copy correct, and removing fourteen implementations of an interface accessor is a different kind of change than this batch is.

#### Risk direction
Strictly fewer or equal entries: Range Compression's vote regains its regime veto, and both strategies' scores are multiplied by their category weight instead of a neutral 1.0. No gate, lot, magic, comment or ownership range changed, so positions already open on the account are still matched by the same identity.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, `OVERALL SUCCESS`, 0 errors / 0 total warnings.
- No runtime evidence yet. Expected log change: `[CONSENSUS-REJECT] ... Ready weight ratio` lines appearing for trend-regime candidates that include a compression or liquidity-sweep voter, where previously the two voted un-diluted.


### Batch 194: three strategy inputs had no consumer, and one strategy never got its own symbol type

#### Context
Batch 193 made the catalog the registration authority. Reading what the catalog does *not* do exposed the mirror of that: `CStrategyFactory` still carries a per-strategy configuration path (`CreateMomentum` -> `SetScalpingMode`, `CreateCandlestick` -> `SetRequireTrendAlignment`, `CreateMeanReversion` -> `SetSyntheticMode`), and its only live call site is `EAOrchestrator.mqh:2488`, which passes `g_strategyCatalog[i].factoryName` - empty on every indicator row. Indicator strategies are built by `CatCreate_*`, which constructs them bare. So every input whose value travelled only through the factory config struct was inert, and the classes kept their constructor defaults instead.

#### 1. Momentum's scalping mode never turned on (`Core/Management/EnterpriseStrategyManager.mqh`, `EAOrchestrator.mqh`, `Strategies/SimpleMomentumStrategy.mqh`)
`InpEnableMomentumScalping` defaults to **true** and reaches `config.enableMomentumScalping`, which had no reader; `InpMomentumScalpCooldownSeconds` (20) likewise. The strategy has run trend-following on every symbol for its whole life. `ConfigureBeforeInit` now applies both before `Init`, because the mode is read inside `ValidateTimeframeSuitability`, which `Init` calls.
The mode bypasses the one-signal-per-bar guard and enters on sustained momentum (`|fast-slow| > 1.5 x threshold`), so it is bounded rather than merely enabled: the strategy's own declared scalp band is M1-M15, and `ValidateTimeframeSuitability`'s result was discarded there. An out-of-band timeframe now refuses the mode and prints `[MOMENTUM] Scalping input ON but H1 is outside the M1-M15 band - trend-following mode, one signal per bar`. On charts above M15 this batch changes nothing for Momentum.

#### 2. Candlestick was requiring a trend the operator switched off (`EnterpriseStrategyManager.mqh`)
`InpCandlestickRequireTrend = false` -> `config.candlestickRequireTrend = false` -> never read, while `m_requireTrendAlignment` constructs to **true**. The flag is read in `Init` to decide whether to create the EMA50/EMA200 handles at all, so the post-registration dependency pass could not have applied it; `ConfigureBeforeInit` does, before `Init`. Counter-trend candlestick patterns become eligible on every symbol, which is what the input asked for since it was written.

#### 3. Mean Reversion ran the FX path on synthetic indices (`Strategies/MeanReversionStrategy.mqh`)
`SetSyntheticMode` had one caller (the dead factory creator), and its source field `meanReversionSyntheticMode` exists in no `SOrchestratorConfig` and no root `.mq5` - so `m_isSynthetic` was false everywhere and `GetSignal()` never reached `GetSignalSynthetic()`, the 1.5-sigma-band + spike branch that Batch 155 had already repaired bar-by-bar. Synthetic indices were being read with Bollinger(20, 2.0) + RSI + tick-volume filters designed for FX liquidity. This is a property of the symbol, not an operator preference, so `Init` now derives it: `m_isSynthetic = IsSyntheticIndexSymbolName(symbol)`, and `[MEANREV] Initialized ... path=synthetic(1.5sigma+spike)|fx(bands+rsi+volume)` states per symbol which branch it took. The synthetic branch creates its own BB handle lazily and fails closed on every data gap, so it needed no other wiring.

#### 4. Recorded, deliberately not wired: `InpTrendADXNoTrendThreshold`
The factory would have called `SetADXThresholds(12.0, 20, 25, 35)` on every symbol. `CStrategyTrend::Init` treats `m_adxNoTrendThreshold <= 0` as "use `m_adxSizing.InitForAssetClass(...)`", which tunes the four thresholds per asset class - the file's own comment says they are "lowered for synthetic CFDs". Passing the constant would replace per-symbol tuning with one number everywhere, which is a downgrade dressed as a wire-up. It is also unobservable-as-broken: `Init` prints `[TREND v2.1] ADX thresholds applied | Symbol=... | Source=ASSET_CLASS`, so the inert input is already visible in every session log. Left as is.

#### Also recorded, not changed
`CStrategyCandlestick`/`CSimpleMomentumStrategy`-style `GetStrategyType()` accessors exist on exactly two classes - `LiquiditySweepStrategy.mqh:470` returns `STRATEGY_UNIFIED_ICT` and `RangeCompressionBreakout.mqh:411` returns `STRATEGY_MOMENTUM` - and nothing in the repository calls the method: it is on no interface and has no call site. That made it look like a second strategy identity feeding magic allocation and cluster weighting alongside the catalog's `registryType`. It does not; both are dead accessors, and `STRATEGY_UNIFIED_ICT`'s enum value is genuinely load-bearing only in `ConsensusEngine.mqh:450` and `MagicNumberAllocator.mqh:295`. Left alone.

#### Risk direction
Items 2 and 3 change which signals strategies submit, not how much any signal is allowed to trade: consensus still needs two independent voters, the post-consensus validator arms are unchanged, and every entry still passes `CUnifiedRiskManager` on its final lot (Batch 190). Item 1 can raise Momentum's re-signalling rate inside M1-M15 only, and only while its own cooldown is the binding limit.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, `OVERALL SUCCESS`, 0 errors / 0 total warnings.
- No runtime evidence yet (newest journal 2026-09-23). What the first attached session should show: `[MEANREV] Initialized ... path=synthetic` on each synthetic index and `path=fx` on forex; `[MOMENTUM] Effective mode=scalping ... sameBarGuard=bypassed` on M1-M15 charts and `mode=trend-following` with the band-refusal line above that everywhere else; Candlestick registrations that no longer create EMA50/EMA200 handles.


### Batch 193: Five defects that were suppressing valid entries, including one strategy that could never register

#### Context
The operator asked for more trades without giving up safety. A research pass over the signal and entry paths produced a defect list; each item below was re-read in the file before being changed, and each one is a control that did not work as designed rather than a limit that was too strict. No risk ceiling was loosened in this batch.

#### 1. The dormancy cooldown re-armed itself forever (`Core/Orchestration/SignalGenerator.mqh`)
`RecordDormancyWarning` fires on any `TRADE_SIGNAL_NONE` (`:357`), the strike test is `>=` (`:225`), and only a *signal* clears the counter (`:361`). A symbol with no signal for three evaluations was parked for 30 minutes, and because the counter still read 3 when the cooldown expired, its first quiet bar after expiry re-armed another 30 minutes. On the new-bar cadence that is roughly one evaluated bar per half hour per quiet symbol - the largest single loss of trade evaluation in the EA. Expiry now resets the strikes and prints `[DORMANT-COOLDOWN] ... cooldown expired, strikes reset`.

#### 2. Strategy registration is now driven by the catalog row (`EAOrchestrator.mqh`, `Core/Strategy/StrategyCatalog.mqh`)
Statistical Arbitrage had a catalog row, an `SI_STATISTICAL_ARBITRAGE` flag slot and an `InpEnableStatisticalArbitrage` input, and `flags[SI_STATISTICAL_ARBITRAGE] = config.enableStatisticalArbitrage` is wired - but no `RegisterDefinition` line existed for its name. `IsStrategyActive()` returns false for unknown names, so `RegisterStrategy` disabled it with `[ENTERPRISE] Strategy ... disabled by registry` however the operator configured it. It was the only row missing from fourteen hand-written pairs.

`SStrategyDefinition` gained a `registryType` field, all 14 indicator rows declare theirs, and the block of 14 `enabled = flags[SI_X]; if(enabled) RegisterDefinition("X", ...)` pairs is now one loop over the catalog: a new strategy needs a row and its input, nothing else, and a row without a `registryType` prints `[STRATEGY-REGISTRY] <name> has no registryType in its catalog row - it cannot pass the registry filter` at init instead of disappearing. The AI rows keep their own definitions because their `enabled` flag comes from adapter availability, not from a strategy input.

Same change makes `InpWeight*` actually decide voting weight. Before this batch those fourteen inputs reached only the registry descriptor, and for indicator rows nothing reads the descriptor weight (`GetWeightByName` has exactly one caller, inside the AI adapter registration; `ApplyStrategyWeights` is an explicit no-op), while `AutoRegisterStrategies` fed the catalog literal into `RegisterStrategy` -> `SetWeight` -> the roster that `ConsensusEngine` and `ConsensusWeightingConfig` read with `GetStrategyWeight()`. So the operator's weight inputs did nothing and the code default was the only authority. `ApplyCatalogWeightOverrides()` now runs after the registry aggregator is up and before the first manager registers, resolving each row through `StrategyConfigWeight(flagSlot, rowDefault)` and writing it into the row, so the descriptor and the roster carry one value from one source; a row whose input differs from its literal prints `[CATALOG] <name> | registration weight A -> B from operator input`, and an input with no matching row prints `[CATALOG] weight input for siIndex N has no indicator row - the value reaches nothing`.

#### 3. A 0% scalp tier latched the engine off for the session (`Core/Scalp/FastScalpEngine.mqh`)
`m_config.scalpRiskPct` was read from the risk tier exactly once, in `Initialize`, and a 0% budget set `maxScalpPositions = 0` - the default is 3 (`FastScalpTypes.mqh:34`) and nothing else ever wrote it back. Once the tier raised the budget the engine still refused every entry, because `PassesEntryGates` compares `scalpCount >= maxScalpPositions`. The budget is now re-read in `ShouldEnterScalp`, the cap is no longer zeroed at init, and a refusal prints `[SCALP-GATE]` with the used risk, the budget, the cap and the remaining cooldown, throttled to one line per minute. Those three gates previously refused in silence, which is shape (7) in the known-issues list.

#### 4. Momentum lost the next bar's crossover (`Strategies/SimpleMomentumStrategy.mqh`)
Non-scalping mode carried both a same-bar guard (`currentBar == m_lastSignalBar`) and a wall-clock cooldown of exactly one bar, measured from the moment the signal fired. A signal at 10:37 inside an M5 bar therefore blocked the crossover at 10:40's bar open, and by 10:45 the EMA edge had decayed. The cooldown is now half a bar; the same-bar guard still limits the strategy to one signal per bar, so entries per unit time are unchanged for anything but the bar immediately after a signal.

#### 5. The stop ceiling made the cost gate arithmetic, not a market reading (`Core/Orchestration/CandidateBuilder.mqh`)
`maxSlPips` was `0.3%` of price (`1%` synthetic), and `takeProfitPips` was capped by `maxSlPips * minRR`. When the *floor* `spread * 3` exceeded that ceiling, `maxSlPips` was raised to the floor, so TP became `3 * spread * minRR` and `CheckExecutionCost` computed `spread / TP = 1 / (3 * minRR) = 0.1667` against a `0.15` limit - a certain veto whose number came only from the constants. Two changes: the ceiling is now `max(price cap, 3 * ATR)`, so a volatile symbol's stop follows volatility instead of being pinned at 1% of price (the lot shrinks to keep the same currency risk, and the per-trade cap and the final gate still bind), and TP is an R-multiple of the stop actually taken. When the floor still binds the designed stop, `[CANDIDATE-BUILDER] ... stop pinned to floor | designed= floor= spread= tp= costRatio= limit=` states the reason at the point it becomes known instead of leaving it to look like a market measurement.

#### Risk direction, stated plainly
Items 1, 3-5 raise entry frequency by restoring behavior the design already intended: risk per trade, the per-trade cap, the daily and portfolio budgets, correlation gates and the final lot gate are untouched. Item 5 allows wider stops on high-volatility symbols, which lowers the lot for the same currency risk; where the broker minimum cannot fit inside the cap the candidate is refused with `[RISK-GATE-REJECT] ... reason=compliant_lot_below_min` rather than oversized. Item 2 changes two things beyond Stat Arbitrage: consensus vote weights now follow the operator's `InpWeight*` inputs rather than the catalog literals. Nine of the fourteen rows already agreed; five differ at their defaults - Candlestick 1.5 -> 0.8, Support/Resistance 1.5 -> 1.8, Statistical Arbitrage 1.8 -> 1.5, Liquidity Sweep 1.5 -> 1.9, Range Compression 1.6 -> 1.7 - so relative influence between voters shifts on the first session. Each move prints `[CATALOG] <name> | registration weight A -> B from operator input` at init, and the same number appears in the per-strategy `Registered strategy: ... | Weight:` line and the `[STRATEGY-REGISTRY]` status report.

#### Recorded, deliberately not changed
- Unicorn Model, Power of Three and Unified ICT have `SI_*` slots, `InpIntrabarEligibility*` inputs and `STRATEGY_UNIFIED_ICT` in the enum, but no strategy class and no catalog row. Wiring them would invent alpha that does not exist; the inputs are vestigial and Batch 194's plug-and-play table is where they should be removed.
- Solo-fallback consensus admission (`TryFallbackSoloSignal`) is unreachable, so `CONSENSUS_DECISION_SOLO_FALLBACK` and `MARGINAL_ADMIT` floors never fire. Enabling it would bypass the two-voter rule the audit established earlier; left off.
- The scalp engine's `[AI-VOTE]` block stays unreachable (no adapter exists for that path) - see Batch 192.

#### Verification
- `sync_and_compile.ps1 -All` twice: once for the catalog loop and the five fixes, once after the weight-authority step was added. Both `OVERALL SUCCESS`, 8 root programs, 0 errors / 0 warnings.
- The weight claim was checked before it was written down. The first draft of this entry said the inputs would reach consensus because `RegisterDefinition` was given `StrategyConfigWeight(...)`; re-reading showed descriptor weight is read only by `GetWeightByName` (AI path) and the `[STRATEGY-REGISTRY]` report string, while `ConsensusEngine` reads the roster value that comes from the catalog row - so that version of the change moved nothing. `ApplyCatalogWeightOverrides()` is what makes the sentence true.
- No runtime evidence yet (newest journal 2026-09-23). Predicted observable changes: far fewer `[DORMANT-COOLDOWN]` re-arms per symbol, `[SCALP-GATE]` lines where the scalp previously refused in silence, five `[CATALOG] ... registration weight A -> B from operator input` lines at init, `[EnterpriseStrategyManager] Synced strategy Statistical Arbitrage -> enabled=true (registry active=true)` on every symbol where its input is on (that sync is the second half of the same mechanism: `AutoRegisterStrategies` runs before the registry is populated, so `SyncEnabledWithRegistry` is what re-reads `IsStrategyActive` after `BuildStrategyRegistry`), and consensus entries on the synthetics carrying an ATR-sized stop instead of exactly 1% of price.



### Batch 192: The scalp traded with two risk reservations, and a tier could size above the envelope

#### Context
The five items Batch 191 queued after its comment pass, narrowed to the three that change money or observability. Files: `Core/Scalp/FastScalpEntry.mqh`, `Core/Scalp/FastScalpEngine.mqh`, `Core/Risk/UnifiedRiskManager.mqh`, `Core/Risk/CompoundingTierManager.mqh`, `Core/Orchestration/EAOrchestrator.mqh`.

#### 1. One pre-trade gate per scalp instead of two (`FastScalpEntry.mqh`)
`ShouldEnterScalp` called `ValidateTradeRequest(request, "scalp")` at `:77`, then `Execute` called it again at `:175` with tag `"scalp-pretrade"` on the same symbol, side, lot, stops and confidence. Each approval reserves a virtual position under a microsecond-unique owner tag and is pruned only by TTL, so every fast-scalp entry booked its risk **twice** against the portfolio and daily-budget gates for up to 60 seconds, and `CRiskValidationStats::RecordApproval` counted one trade as two.

The pre-send call went, not the entry-stage one. The entry-stage request carries `strategyRole`, `strategyCluster` and `clusterCode = "T"`, which the pre-send request left unset, so the surviving gate is the one that gives cluster governance a code to group by; and everything between the two (`FinalizeLotSize` -> `CapLotToMargin`) can only shrink the lot or refuse it, so the second approval could not have caught anything the first missed. `riskReq.lotSize` at the pre-send site was the already-adjusted lot either way.

The adopt branch that came with the removed gate had its own bug: `if(result.adjustedLotSize > 0.0) lotSize = result.adjustedLotSize;` adopted unconditionally, and the pipeline does raise `adjustedLotSize` to `SYMBOL_VOLUME_MIN` on some paths (`RiskValidationPipeline.mqh:507`). It is shrink-only now, and prints `[SCALP-RISK-ADJUSTED] symbol | lot A -> B | reason=...` where the old silent assignment left no trace of a lot the risk manager changed. `slPips`/`tpPips`, computed only to feed the deleted request, went with it.

#### 2. The compounding tier can no longer size above the envelope (`CompoundingTierManager.mqh`)
`ApplyTierToPositionSizer` wrote `tier.riskPerTradeOverride` straight into `CPositionSizer::SetParameters`, which does no clamping, while the operator-envelope clamp lives only on the `CUnifiedRiskManager` path (`ApplyTierOverrides`). A tier asking for more than the configured ceiling therefore sized at the tier number and got refused downstream by the per-trade cap check - the tier traded nothing, and the refusal looked like a signal problem. It now clamps to `riskManager.GetActiveRiskPerTradePercent()`, which `UnifiedRiskManager.mqh:371` sets from the envelope-clamped base risk, and both call sites (`:343`, `EAOrchestrator.mqh:973`) already apply the risk manager first. When the clamp binds the log says so: `[COMPOUNDING-TIER] Applied to PositionSizer | riskPercent=X (tier Y% | clamped to approved envelope)`.

#### 3. A clamp that only lowered the drawdown warning is no longer silent (`UnifiedRiskManager.mqh`)
`ApplyTierOverrides` prints `[RISK-ENVELOPE]` if any clamped value dropped below the tier's, but the condition tested `clampedDdCritical` and not `clampedDdWarning`, so an envelope that cut only the warning threshold applied it with no line anywhere. The term is in the condition and `ddWarn A->B` is in the message.

#### Checked and left alone
- `FastScalpEntry.mqh:167`'s `[AI-VOTE]` block is unreachable: the only `m_scalpEngine.Initialize` call site (`EAOrchestrator.mqh:1162`) passes four of five arguments and `aiAdapter` defaults to NULL (`FastScalpEngine.mqh:127`). An adapter was never built for the scalp path, so wiring one would be inventing an AI vote to log - the comment now states the branch does not run rather than implying it does.
- `CountScalpPositions` (`FastScalpPositionTracker.mqh:113`) counts any position whose comment *starts with* `SCALP`, terminal-wide, with no magic or symbol filter. Batch 170 already fixed the substring version that let this engine claim ATR-SCALP positions. What remains over-counts rather than under-counts, so `maxScalpPositions` refuses earlier than the operator set - the safe direction, and part of task #37's magic-collision territory.
- `CUnifiedRiskManager::ResetCircuitBreaker` still has no caller. The halt it would clear resets itself at the trading-day roll (`UnifiedRiskManager.mqh:1304`), so this is unused manual surface, not a trapped account.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, **0 errors / 0 warnings**.
- No runtime evidence: the newest journal on this machine is still 2026-09-23. The observable predictions are one `[RISK-VIRTUAL] reserve` per scalp instead of two, a `[SCALP-RISK-ADJUSTED]` line whenever the gate shrinks a lot, and a `ddWarn` field on `[RISK-ENVELOPE]`.



### Batch 191: Comment reduction in the risk tree, the scalp engine and the registry - 136 lines, and two agent claims that did not survive checking

#### Context
Seventh round of the comment workstream, on the six densest files Batches 189-190 did not already occupy. Whole-line comments, HEAD -> now:

| File | Before | After |
|---|---|---|
| `Core/Risk/UnifiedRiskManager.mqh` | 128 | 83 |
| `Core/Registry/RegistryAggregator.mqh` | 48 | 22 |
| `Core/Risk/CompoundingTierManager.mqh` | 53 | 33 |
| `Core/Engines/KalmanMeanReversion.mqh` | 50 | 32 |
| `Core/Risk/PortfolioRiskManager.mqh` | 50 | 36 |
| `Core/Scalp/FastScalpEngine.mqh` | 54 | 41 |

Repo-wide **7,076 -> 6,940 (-136)**. For all six files the non-comment line stream is byte-identical to `HEAD`, so no executable line, blank line or CRLF moved.

#### Two reported defects that were wrong, and what the code actually does
- **"Nothing in the runtime can clear a halt."** `CUnifiedRiskManager::ResetCircuitBreaker` (`:1142`) genuinely has no caller - declared at `:231`, defined, forwards to the breaker, never invoked. But the daily-loss halt is not permanent: `RiskCircuitBreaker::ResetDailyLossHalt()` (`:339`) clears it and prints `[RISK-DAILY-LOSS] Daily loss halt RESET - new trading day`, and it is called from `UnifiedRiskManager.mqh:1304` on the new-trading-day path. The dead method is an unused manual reset, not a trapped account.
- **"The CVaR gate has no data."** `m_tradeReturns` / `m_returnCount` are indeed never written (declared `:56`/`:58`, resized and zeroed at `:158-159`, read at `:735`/`:742`), but the gate does not depend on them: `RecordEquityCurveReturn` (`:690`) fills `m_equityCurveReturns`, driven by `CPortfolioRiskManager::UpdateEquityCurve()` (`:710`), which `UnifiedRiskManager.mqh:655` calls. The retained comment is accurate - the source is picked by sample count, `m_useEquityCurveForCVaR` is never read, and below 20 equity samples the gate fails open.

Both were checked against the file before being written into this entry. A subagent report is a hypothesis.

#### Dead surface confirmed
- `GetKalman(symbol)` (`MathematicalEngineRegistry.mqh:149`) has no caller anywhere, and no code outside the hub touches `m_kalmanEngines[]`. The engine is constructed when the Kalman input is on, updated, and logged - advisory only, never reaching a sizing or veto decision. `TradeExecutor`'s contributor-name mapping for "Kalman" is therefore a branch that cannot be taken.
- `SetThrottlePressure` writes a value `GetThrottlePressure` has no consumer for; `SetBaseRiskPerTrade` ("used by dual-mode auto-switching") and `SetTradingDayStartHour` have no caller, so the trading day rolls at server midnight regardless.
- `CPortfolioRiskManager::OnPositionOpened` / `OnPositionClosed` / `InvalidateRiskCache` / `SetCacheRefreshInterval` have no caller, so every portfolio-risk read is a full position scan at the constructor's 60s interval, not the event-driven refresh the comments described.

#### False comments rewritten (claim -> truth)
`FastScalpEngine.mqh:3` said every public method is a signature-identical forwarder with no behaviour changed; `Initialize`/`ShouldEnterScalp`/`EvaluateScalpSignal` keep guards, read the scalp budget and cap at 0%. `:233` described a "slow path / timer path" with no timer caller. `RegistryAggregator.mqh:73` claimed `EAOrchestrator` holds only a forward declaration of `CNeuralNetRegistry` when it includes the file at `:15`. `:108` described a count "across all registries" that sums six of seven and omits `m_strategyRegistry`. `KalmanMeanReversion.mqh:264` claimed a Kalman gain for kappa; `m_P_mu_kappa` starts at 0 and is only decayed, so the gain is identically 0 and kappa stays at its OLS bootstrap. `CompoundingTierManager.mqh:2` cited a `problems.md` that does not exist in the repository, and `:203`/`:219` described tier selection by "balance" and by "highest tier" when it reads equity and an unmatched bracket returns the last, most conservative tier.

#### Queued for Batch 192 (verified by me, not touched here)
1. `CFastScalpEngine` runs the pre-trade gate **twice per trade**: `ValidateTradeRequest(request, "scalp")` at `FastScalpEntry.mqh:77` inside the entry decision, then `ValidateTradeRequest(riskReq, "scalp-pretrade")` at `:175` before the send. Each approval reserves a virtual position pruned only by TTL, so one scalp counts its risk twice against the portfolio and daily-budget gates, and `RecordApproval` fires twice. This is the double-count Batch 190 reasoned its way around.
2. `UnifiedRiskManager::ApplyTierOverrides` prints `[RISK-ENVELOPE]` when any clamped value dropped, but the condition omits `clampedDdWarning`, so a clamp that only lowers the drawdown-warning threshold is silent.
3. `CompoundingTierManager::ApplyTierToPositionSizer` (`:391`, called from `EAOrchestrator.mqh:973` and `:343`) hands the sizer the tier's raw risk percent while the envelope clamp exists only on the `UnifiedRiskManager` path, so a tier can size above the configured ceiling and be refused downstream instead of clamped.
4. `EAOrchestrator.mqh:1162` is the only `m_scalpEngine.Initialize` call site; if its trailing `aiAdapter` argument is left defaulted, the engine's `[AI-VOTE]` block at `FastScalpEntry.mqh:194` never runs, which AGENTS.md §4.2 asks to see evidence of. The signature was not read before this line was written - verify before fixing.
5. `CountScalpPositions` matches the `SCALP` comment prefix without a magic filter, so the `maxScalpPositions` cap counts positions belonging to other engines or instances - task #37's territory.

#### Verification
- This round changes comment lines only, proven per file by byte-identical non-comment streams; Batch 190's compile (8 programs, 0 errors / 0 warnings) is the build this tree sits on.
- Every claim in this entry was re-derived by me from the files: `ResetDailyLossHalt` called at `UnifiedRiskManager.mqh:1304`, `UpdateEquityCurve` called at `:655`, the `GetKalman` reference count, the two `ValidateTradeRequest` call sites in `FastScalpEntry.mqh`, and the `[RISK-ENVELOPE]` condition at `UnifiedRiskManager.mqh:348-351`.

### Batch 190: The risk gate was validating a lot the EA never traded

#### Context
Batch 189's comment pass over the candidate builder and the risk pipeline surfaced seven defects, all of the same family: a gate that cannot reject, a value tested against itself, or a decision made about a lot that is not the one shipped. This batch fixes them. The three files it touches also carry their Batch 189 comment reductions (108 -> 40 in `CandidateBuilder.mqh`, 87 -> 62 in `RiskValidationPipeline.mqh`, 53 -> 42 in `MeanReversionStrategy.mqh`), which is why they were held back from the hygiene commit.

#### 1. The gate now sees the real lot (`Core/Orchestration/CandidateBuilder.mqh`)
`BuildCandidate` filled `tradeReq.lotSize` with `SYMBOL_VOLUME_MIN` and called `ValidateTradeRequest` before `CalculatePositionSizeWithRisk` ran, so the portfolio, correlation, daily-budget and margin decisions inside the gate were all evaluated for a 0.01-lot trade while the candidate shipped whatever the sizer and modifiers produced. The file's own comment admitted the shipped lot "can carry several times the proposed risk with no gate behind it"; the post-size clamp only checked `GetEffectiveRiskPerTrade`, one of about twenty gates.

The single `ValidateTradeRequest` call now runs at the end, against `candidate.lotSize` after the per-trade cap clamp. It moved rather than being added because each approval keeps a virtual reservation until its TTL and the reservation tag carries a microsecond, so a second call would have double-counted this candidate's risk in the portfolio and daily-budget gates. Refusals print `[RISK-GATE-REJECT] ... reason=final_lot_validation`. When the gate approves but returns a smaller `adjustedLotSize`, that lot is floored to the volume step and adopted with `[RISK-GATE-ADJUST]`; if it cannot be expressed above the broker minimum the candidate is refused rather than rounded up. Adoption is shrink-only: the pipeline can raise `adjustedLotSize` to the broker minimum, and taking that back would ship more than the sizing decided.

Consequence to watch on the first live session: consensus entries that previously passed on a 0.01-lot evaluation may now be refused at their true size. Every such refusal is logged.

#### 2. ATR actually reaches stop distance (`CandidateBuilder.CalculateStops`)
`atrValue` was hard-wired to 0 next to a comment saying it "would be passed in real implementation", so the ATR branch never ran and every candidate without strategy-proposed stops took its stop from `max(30 points, 0.3% of price)` - volatility-blind. It now reads ATR(14) on the current timeframe through `CTradeMgrPricing::CalculateATR`, which uses the shared `CIndicatorManager` handle cache and creates no handle per call; a 0.0 return (no cache, no data) leaves the fixed band in charge exactly as before. The unused `CUnifiedSignalPipeline* pipeline = NULL` declaration went with it.

#### 3. The minimum-stop floor is compared in one unit (`CandidateBuilder.CalculateStops`)
`GetMinimumStopDistance()` answers in price units (`TradeMgrPricing.mqh:209` returns `requiredPoints * point`) but was MathMaxed against raw `SYMBOL_TRADE_STOPS_LEVEL` points, so it was about 100,000 times too small on a 5-digit FX symbol and the broker's spread-folded minimum never bound. It is divided by `point` now.

#### 4. Correlation REDUCE can no longer approve a zero lot (`Core/Risk/RiskValidationPipeline.mqh`)
`MathFloor(lot * reduceFactor / step)` lands on 0 steps for a min-lot position at factor 0.25. The result stayed approved with `adjustedLotSize = 0.0`, and both consumers adopt it only when `> 0.0` (`FastScalpEntry.mqh:86`, `:186`) - so the trade went out at the full lot with the correlation discount silently gone, and the risk recompute at `:703` was skipped because it too tests `> 0.0`. The branch now refuses with `[RISK-GATE-REJECT] ... reason=correlation_reduce_below_min_lot`, releases the virtual reservation and logs the JSON event.

#### 5. The over-max-volume check can reject (`RiskValidationPipeline.ValidateBasicParameters`)
A lot above `SYMBOL_VOLUME_MAX` printed "caller must cap" and fell through to approval. It now returns false with both values in the message; the guard is `maxLot > 0.0` so a symbol that reports no maximum is not vetoed by an absent limit.

#### 6. The validator quality floor is no longer derived from the value it tests (`Core/Management/PostConsensusValidator.mqh`)
`GetAdaptiveQualityThreshold` returned `max(0.40, ctx.directionalQuality * 0.9)` for FULL_QUORUM and `max(0.45, ctx.directionalQuality * 0.85)` for SPARSE_INTRABAR, and the caller compared that to the same `ctx.directionalQuality`. Since `0.9 * q < q` always, those two arms could only ever reject below the hard-coded constants, so `InpValidatorNewBarMinQuality = 0.68` and `InpValidatorIntrabarMinQuality = 0.70` were inert for the two classes that carry most entries. The class discount now applies to the configured floor: the effective floors become 0.612 (new bar) and 0.63 / 0.595 (intrabar) instead of 0.40 / 0.45. This tightens entries; the veto already prints `[POST-CONSENSUS-FILTER] ... filter=quality_gate | class=... | quality=... threshold=...`, so the change is countable from the journal.

#### 7. The mean-reversion strategy stopped releasing a handle it does not own (`Strategies/MeanReversionStrategy.mqh`)
`Cleanup()` called `IndicatorRelease` on `m_stochHandle`, which `Init` takes from `CIndicatorManager::GetStochasticHandle` - the line above it said the manager owns these and never to release them here. `CIndicatorManager::DestroyInstance()` releases the same handle on deinit (AGENTS.md 3.5), so it was released twice and the shared handle died for every other holder of that symbol/timeframe Stochastic. Now only the field is cleared. The same pattern was checked repo-wide: `LiquiditySweepStrategy`, `RangeCompressionBreakout` and `TrendEntryTypes` also release handles, but they create them with `iATR`/`iBands`/`iMA` directly, so those are correct and were left alone.

#### Deliberately not changed
- `ResolveLiveAuthority` in the builder stays a stub that always authorizes; the orchestrator overwrites the three fields from `CLiveAuthorityResolver`, so deleting the call would be churn with no risk effect.
- `ApplyDrawdownScaling`'s `floorMult <= m_minLotRiskMultiplier` guard is a tautology (`floorMult < 1.0` by construction), but the resulting lot is still below the lot the caller sized, so the round-up to broker minimum cannot exceed the pre-scaling risk. `[RISK-ADAPT]` logs it.
- The double approval bookkeeping inside one `Run()` (`:513-516` and `:774-777`), the BID-for-BUY netting re-price, and the unused `GetLastBlockReason()` are recorded, not touched: none changes a lot size or a veto.

#### Verification
- Compile: 8 root programs, 0 errors / 0 warnings.
- No runtime evidence yet: the newest terminal journal on this machine is 2026-09-23, so nothing after Batch 172 has been observed live. The new `[RISK-GATE-ADJUST]`, `reason=final_lot_validation`, `reason=correlation_reduce_below_min_lot` and the tightened `filter=quality_gate` line are the first things to look for when the EA is next attached.
- Expected direction of change: fewer and smaller consensus entries, never larger.

### Batch 189: Comment reduction in the consensus engine, correlation engine and momentum strategy - 76 lines net, and the reading found dead paths

#### Context
Sixth round of the comment workstream. The round also covered `Core/Orchestration/CandidateBuilder.mqh` (108 -> 35), `Core/Risk/RiskValidationPipeline.mqh` (87 -> 59) and `Strategies/MeanReversionStrategy.mqh` (53 -> 41), but those three files carry the fixes Batch 189's reading surfaced, so their comment reductions commit with Batch 190 rather than ride in a hygiene commit.

#### Changed here (whole-line comments, HEAD -> now)
| File | Before | After |
|---|---|---|
| `Core/Management/ConsensusEngine.mqh` | 67 | 40 |
| `Core/Risk/CorrelationEngine.mqh` | 58 | 22 |
| `Strategies/SimpleMomentumStrategy.mqh` | 55 | 41 |
| `Core/Strategy/StrategyBase.mqh` | 16 | 17 |

For each file the non-comment line stream is byte-identical to `HEAD`: `diff <(git show HEAD:f | grep -v '^\s*//') <(grep -v '^\s*//' f)` prints nothing, so no executable line, blank line or CRLF moved.

#### Kept because the code cannot show it
- The strategy-level gate fails open on a NULL risk-manager injection, but `CStrategyRegistryState::RegisterStrategy` (`:122`) refuses registration when `ValidateRiskManagerInjection()` is false. AGENTS.md 3.1 holds because of that registration gate, not because of `ValidateWithRiskManager` - so the invariant note on `StrategyBase.mqh:116` and on both strategy headers now names the registration gate.
- `candidate.liveAuthority*` is written by a stub in `CandidateBuilder.ResolveLiveAuthority` that always authorizes at 1.0; `EAOrchestrator` overwrites all three fields from `CLiveAuthorityResolver` after `BuildCandidate` returns, so the stub gates nothing.
- `stopLossPips` are in `SYMBOL_POINT` units, not pip*10 units, and the risk recompute reads them as such.
- Auto-registration runs before the orchestrator fills the shared `CStrategyRegistry`, so `IsStrategyActive()` is false at that moment and a re-apply step follows.

#### Dead surface and false notes found
- `ConsensusEngine.mqh:1096` documented the probe-only evaluator as "used for intrabar direction probing"; `EvaluateConsensusProbeOnlyInternal` has no caller anywhere. `:1201` documented a path "called when all strategies abstain" that is reachable only through `TryFallbackSoloSignal`, whose manager forwarder is never called.
- The correlation engine claimed upper-triangular flat storage while `ComputeMatrix` writes both triangles, claimed "Compute log returns" over simple returns, and annotated `Refresh`/`ForceRefresh`/`SetSymbolsChanged`/`IsCorrelatedCluster`/`CountCorrelatedPositions`/`Reset`/`GetConfig` with "call from the main loop" and "call on deinit" - none has a caller outside the file. Its asset-class and cross-asset thresholds are stored, logged and never compared.
- `SimpleMomentumStrategy.mqh:390` claimed "1 closed bar of confirmation" while the hysteresis validation is skipped at the default `m_minConfirmationBars = 1`.
- `MeanReversionStrategy.mqh` called the Stochastic handle "self-managed" when `:118` takes it from the shared `CIndicatorManager` cache, claimed BB-only entries need a Stochastic extreme when the tier only multiplies confidence by 0.90, and called the BB middle line a 20-EMA.

#### Defects this round queued for Batch 190
1. `CandidateBuilder.mqh` hard-wired `atrValue = 0`, so the ATR stop branch never ran and every non-strategy stop came from a fixed `max(30 pts, 0.3% of price)` band.
2. `CandidateBuilder.mqh` MathMaxed a **price-unit** `GetMinimumStopDistance()` against raw **point** counts, so the broker's spread-folded minimum stop was never honored.
3. `CandidateBuilder.mqh` sent `SYMBOL_VOLUME_MIN` into `ValidateTradeRequest` and sized the real lot afterwards, so correlation, portfolio and budget decisions were all made about a 0.01-lot trade and `adjustedLotSize` had no consumer on the consensus path at all.
4. `RiskValidationPipeline.mqh` floored the correlation REDUCE step to 0.0 and still approved; both consumers adopt `adjustedLotSize` only when `> 0.0`, so the risk reduction silently vanished.
5. `RiskValidationPipeline.mqh` printed "caller must cap" for a lot above `SYMBOL_VOLUME_MAX` and returned approval - a gate that cannot reject.
6. `PostConsensusValidator.mqh` derived the quality floor from `ctx.directionalQuality` itself (x0.9 / x0.85) and compared it to that same value, so for FULL_QUORUM and SPARSE_INTRABAR the gate collapsed to a hard-coded 0.40/0.45 and `InpValidatorNewBarMinQuality=0.68` / `InpValidatorIntrabarMinQuality=0.70` were inert.
7. `MeanReversionStrategy.mqh` called `IndicatorRelease` on the manager-owned shared Stochastic handle, contradicting the line above it; the double release happens at `DestroyInstance` and the handle dies for every other holder.

Also recorded, not fixed: reservation bookkeeping runs twice in one approval (`RiskValidationPipeline.mqh:513-516` and `:774-777`); `ApplyDrawdownScaling`'s `floorMult` guard is a tautology because `floorMult < 1.0` by construction; the netting re-price uses BID for a BUY where the pre-loop used ASK; `GetLastBlockReason()` exists and is unused; `MIN_ACCOUNT_BALANCE` is 1.0, not 100.0, at two sites that label it so; `ClearVirtualPositions()` has no caller, so approved-but-abandoned virtual reservations live only until their TTL prunes them.

## [Unreleased] - 2026-10-12

### Batch 188: Comment reduction in the manager and money-arithmetic paths — 181 lines removed, ten false notes, two dead API chains

#### Context
Fifth round of the comment workstream, on the five largest remaining concentrations: the symbol-scoped manager, the Deriv asset profiler, the exit optimizer, and the pricing and attribution halves of the trading layer.

#### Changed (whole-line comments, before -> after)
| File | Before | After |
|---|---|---|
| `Core/Management/EnterpriseStrategyManager.mqh` | 105 | 60 |
| `Core/Processing/DerivAssetProfiler.mqh` | 55 | 6 |
| `Core/Processing/ExitOptimizer.mqh` | 50 | 14 |
| `Core/Trading/TradeAttributionManager.mqh` | 45 | 18 |
| `Core/Trading/TradeMgrPricing.mqh` | 44 | 20 |

Repo-wide **7,431 -> 7,250 (-181)**; non-comment lines byte-identical to `HEAD` in all five files.

#### Kept because the code cannot show it
- The two volume-normalisation twins, stated together so nobody picks the wrong one: `CTradeMgrPricing::NormalizeVolume` floors to `SYMBOL_VOLUME_STEP` and returns 0.0 under `SYMBOL_VOLUME_MIN` so the caller can refuse, while `CPositionSizer::NormalizeVolume` clamps **up** to that minimum and hands back a larger lot than the caller sized.
- Why the spread-anomaly preflight needs a broker-only stop term: `GetMinimumStopDistance` already folds in 1.5 * spread, so a multiple of it can never be exceeded by the spread it wraps — the comparison would be circular.
- Round-trip cost is defined once, in price units, and read by both the money model and the take-profit expectancy gate; a second copy would drift.
- Magic composition `base + offset + symbol index` with family offsets 9000-9999 required to stay distinct, because a shared offset leaves two books indistinguishable to close, attribution and risk — and magic cannot separate the strategy books, which is why send comments do.
- The 1R baseline: `m_initialRisk = |entry - initialSL|`, and while it is 0 the R-multiple partial-close stage returns no partial.
- The registry-order fact that explains a whole class of "everything is disabled" reports: auto-registration runs *before* the orchestrator fills the shared `CStrategyRegistry`, so `IsStrategyActive()` is false at that moment and `RegisterStrategy()`'s mode filter locks every strategy out; the re-apply step is what fixes it.

#### Nine pre-existing comments described things that are not there
Deleted after verification: two claiming delegation to `CPositionStateManager`, a class that does not exist in the repository; "Diagnostics enable flags (set from EA inputs)" for `SetNNDiagnosticsEnabled` / `SetRunSelfTest`, which have zero call sites; "brokers charging per-lot commission go through `CTradeSpreadCostModel`", a class that only converts spread to money; "OU context (injected from the Kalman engine)", since `SetOUContext` is never called; a "must check BEFORE Volatility, VolSwitch symbols contain VOL" ordering rule for a predicate that does not match bare `VOL`; `idx 9/10 LIVE defaults` for literals removed in favour of 7/8; a "delegates to CStrategyHealthMonitor" note on a block that forwards to roster/weighting/lifecycle; and a two-phase-init header claiming the manager creates and destroys OFI/VPIN/family-matrix objects that are in fact injected pointers neither path releases.

#### Two dead API chains, confirmed rather than assumed
- **`PopClosedTradeAttribution` can never return true and has no consumer.** `m_hasClosedTradeAttribution` is initialized `false` and written `false` at three sites, never `true`; and grepping the whole repository finds only the declaration, the two forwarders (`AttributionDelegator`, `EnterpriseStrategyManager`) and the implementation. Closed-deal attribution reaches strategy performance a different way — `StrategyMgrTradeFeedback.mqh:150` pops *per-position* attribution and calls `UpdatePerformance` and `RecordTradeResult` directly — so this is dead surface, not a starved live control. Recorded; not deleted, because removing three coordinated forwarders is a code change with no safety value.
- **`AccumulatePendingCloseProfit` has no caller**, so the `m_pendingClose*` arrays stay empty and `GetPendingCloseProfits` returns 0.

#### A fourth parked component, and why `[ENGINE-STATUS]` does not name it
`CExitOptimizer` is constructed at `OrchestratorMathEngineHub.mqh:274`/`:442` and `MathematicalEngineRegistry.mqh:390`, and `GetExitOptimizer` has no caller outside the registry — nothing anywhere invokes `Evaluate()`. Unlike Batch 178's three engines it has **no enable input**, so the startup report cannot list it. It costs an allocation per symbol and computes nothing; wiring it would create a second exit authority that AGENTS.md §3.3 forbids, so the correct action is to record it, which this entry does.

#### One false comment rewritten rather than deleted
`StrategyMgrTradeFeedback.mqh:151-152` said "Store in closed trade attribution for PopClosedTradeAttribution / The TradeAttributionManager handles this internally" over a loop that does neither — it calls `UpdatePerformance` and the health monitor directly, and no code on that path writes the fields `PopClosedTradeAttribution` reads. Left alone it would keep a future session chasing the dead chain as though it were the live one. Rewritten to name the loop as the whole closed-trade attribution path. Comment lines only, executable lines untouched.

#### Worth noting about the process
One agent declined to write a comment this batch's brief invited ("attribution is reporting-only and must not feed a risk decision") because the code contradicts it — closed-deal attribution really does feed `UpdatePerformance` and NN online training. Refusing to write a false constraint is better than writing the tidy one, and is the failure mode the last three rounds kept hitting.

My own error, recorded: I told that round's brief the manager file was 1,980 lines when it is 1,367 — I had conflated it with `TradeManager.mqh` from a later measurement. The agent worked from the real file and flagged the discrepancy.

#### Verification
- Assertions checked by grep before being kept: `SetAdxHandleCached` has one call site (`ConsensusEngine.mqh:301`); family offsets consumed at `EAOrchestrator.mqh:1265` with composition at `ATRScalpEntry.mqh:147` / `SpikeHunterExecutor.mqh:212`; default values confirmed at `EntStrategyQuorumConfig.mqh:141/148/150-151`, `StrategyMgrRoster.mqh:204`, `PostConsensusValidator.mqh:77`.
- Non-comment lines byte-identical to `HEAD` for all 6 touched files: **0 differences** (verified per file with a `git diff -U0` filter that keeps only lines not starting with `//`).
- `sync_and_compile.ps1 -All`: 8 root programs, **0 errors / 0 warnings**.

### Batch 187: The hedging gate could not refuse, and the send path computed a price it never used

#### Context
The second defect Batch 185's verification queued. `CTradeManager::IsHedgingAllowed` read:

```
if(m_accountMarginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
    return true;
return true; // Allow for now, netting handled by broker
```

Both branches returned `true`, so the guard at the top of `OpenPosition` could never fire and its `[TRADE-MGR] OpenPosition blocked` line was unreachable. The comment asserted a broker-side resolution that nothing in the EA accounts for.

#### Why this is a real hazard and not decoration
The EA keeps a separate book per strategy: per-symbol position caps, magic-scoped accounting, `RegisterExecutedTradeRisk` per trade, and per-position SL/TP written through the position state registry. On a netting account a second signal on the same symbol does not open a second position — it **nets against the first**, so the merged position carries whichever stop the last writer set, the daily budget is charged for two trades while the broker holds one, and attribution describes a position no single strategy opened. There is no code path that reconciles that; the assumption is hedging.

#### Changed
- `Core/Trading/TradeManager.mqh:157-161`: `IsHedgingAllowed` returns `m_accountMarginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING`. Refusal now reaches its log, which names the symbol, the actual margin mode, and the reason: *entries are refused because per-strategy books cannot be kept on a netted position*. `ACCOUNT_MARGIN_MODE` is already printed once at init (`:152`), so the mode is visible before the first refusal too.
- `:1836-1838` deleted: `validationPrice` was assigned from `price`, refreshed from `GetCurrentExecutionPrice` when non-positive, and then **never read** — the send ships `price`. A comment claiming the order executed "using the freshest price available at send time" was describing this dead value; Batch 185 removed that comment, this removes the value.

#### Consequence for the operator
On the current account, nothing changes: the September journals show a BUY and a SELL on XAUUSD seconds apart receiving distinct position tickets, which netting would not produce, so the account is retail hedging. If the EA is ever attached to a netting or exchange-netting account, **every entry is refused** with the message above. That is deliberate — a loud refusal is recoverable, an unexplained netted book is not.

#### Verification
- `IsHedgingAllowed` has exactly one caller (`:1826`), so the change cannot affect a path that expected `true`.
- `validationPrice` had no read site anywhere in the repository before deletion.
- `sync_and_compile.ps1 -All`: 8 root programs, **0 errors / 0 warnings**.

### Batch 186: The exogenous spread gate was reading the wrong values, and refusing trades with no log

#### Context
Batch 185 deleted a comment at `TradeManager.mqh` that described a netting check which does not exist; checking the *other* files that round surfaced `PostConsensusValidator.mqh:292`. One call, four arguments, three of them in the wrong slots.

#### Found, with the arithmetic
`CUnifiedSignalPipeline::ApplySpreadFilter` is declared `(const string symbol, double &spreadScore, double overrideThreshold = -1.0, double atrValue = -1.0)`. The only call site passed `(symbol, atrValue, spreadScore, effectiveSpreadATRRatio)`:

- **`atrValue` was bound to the by-reference `spreadScore` out-param.** The callee writes its result there (`SignalPipelineFilter.mqh:460`), so the ATR the rest of the function still uses was overwritten with a ratio.
- **`spreadScore` (initialized `0.0` nine lines earlier) arrived as `overrideThreshold`.** The callee's `(overrideThreshold > 0.0)` test therefore failed and it fell back to `m_filters.regimeCostGate.maxSpreadToAtrRatio`, whose default is **0.25** (`RegimeTypes.mqh:122`). The per-class ratios Batch 175 introduced for this gate — 0.30 base, 0.50 synthetic — were never used.
- **`effectiveSpreadATRRatio` arrived as `atrValue`.** So the filter computed `ratio = spread / 0.30` (or `0.50`) — a price-denominated spread divided by a dimensionless constant.

On FX that quotient is tiny (`EURUSD` at a 15-point spread: `0.00015 / 0.30 = 0.0005`) so the gate never fired. On the rest of the book it is enormous: `XAUUSD` at a 25-point spread gives `0.25 / 0.30 = 0.83` against a 0.25 threshold, and a Volatility-25 spread of 1,727 points gives `17.27 / 0.50 = 34.5`. In other words the gate was **inert on FX and rejecting essentially every gold and synthetic consensus entry** — and `result.spreadScore` was recorded as 0 for all of them.

#### Also fixed: this was the last silent veto
`EAOrchestrator.mqh:3467-3471` handles a failed validation with `m_heartbeat.IncValidatorRejects(); continue;` and prints nothing. Every other arm prints its own `[POST-CONSENSUS-FILTER]` line, so the spread veto was invisible — that is why the September journals show 71 `atr_ratio` lines and not one spread line, which reads as "the spread gate never triggered" rather than "it triggered and said nothing". Both branches of the gate now print `filter=spread_vs_atr` with the ratio, the threshold in force and the ATR, and the reason string says `spread/ATR=` instead of `ratio=`.

#### Changed
- `Core/Management/PostConsensusValidator.mqh:292`: arguments passed in the declared order — `(symbol, spreadScore, effectiveSpreadATRRatio, atrValue)`.
- `:295-300` and `:312-315`: veto is logged in both the pipeline branch and the no-pipeline fallback.

#### What the operator will see
Gold and synthetic candidates reach the candidate builder for the first time from this gate, so entry counts on those symbols should rise; FX behavior is unchanged in practice (the gate was not firing there either way, and now fires only when a spread genuinely exceeds 30% of ATR). Expect a new `[POST-CONSENSUS-FILTER] ... filter=spread_vs_atr` line wherever it does refuse — if that appears often, the lever is `m_baseSpreadATRRatio` / `m_syntheticSpreadATRRatio`, which are constructor constants with no input, not a misbehaving strategy.

#### Verification
- Traced every parameter through `SignalPipelineFilter::ApplySpreadFilter` (`:429-472`) rather than trusting the declaration, and confirmed the default threshold value and the out-param write.
- Confirmed this is the only silent veto arm by checking each `result.passed = false` path in `ValidateSignal` for a print: `hard_spread_cutoff` (`:224`), quality (`:164`), OFI (`:349`), VPIN (`:383`) all print; only the exogenous spread arm did not.
- `sync_and_compile.ps1 -All`: 8 root programs, **0 errors / 0 warnings**.
- **Owed:** the count of `filter=spread_vs_atr` lines in the first attached session, and whether gold/synthetic candidate volume rises as expected. Newest journal is still 23 September.

### Batch 185: Comment reduction in the three densest files — and a spread gate called with transposed arguments

#### Context
Fourth round of the comment workstream, aimed at the three files carrying the most whole-line comments in the repository: the execution authority, the pre-trade pipeline, and the chart layer.

#### Changed (whole-line comments, before -> after)
| File | Before | After |
|---|---|---|
| `Core/Trading/TradeManager.mqh` | 153 | 69 |
| `Core/Pipeline/UnifiedSignalPipeline.mqh` | 76 | 16 |
| `Core/Visualization/ChartDrawingManager.mqh` | 94 | 22 |

Repo-wide **7,645 -> 7,429 (-216)**, measured at the commit before and after (Batch 182's "repo at 7,643" was correct then; 183 and 184 each added two constraint lines). Non-comment lines byte-identical to `HEAD` in all three files; no code, blank line, trailing comment or block comment touched.

#### Kept because losing it would cost money
- `TradeManager`: a transient retcode (`REQUOTE` / `PRICE_CHANGED` / `CONNECTION_LOSS`) can follow a fill the server already executed, so resending opened a **second full-risk position** — if this send's position exists, accept it. The position cache must hold position tickets, not deal tickets, or `PositionSelectByTicket` always fails and breakeven/trailing go dead. Deviation is set on the symbol's pooled `CTrade` instance because one shared `m_slippage` meant a send carried whichever symbol was evaluated last, and a point's value differs between symbols. `LOCKED`/`FROZEN` allows exactly one bounded retry to avoid a stall loop.
- `UnifiedSignalPipeline`: gate order *is* the semantics — the first veto short-circuits every later gate; the intrabar effective confidence is `min(base + intrabarConfidenceCap, regime threshold)`, so the cap binds in `RANGE` too; engines are owned by the registry, not the pipeline.
- `ChartDrawingManager`: the object cap compares **every** object on the chart (`ObjectsTotal`) while cleanup deletes only this manager's prefixed ones; every draw method ignores `PrepareSnapshotDraw()`'s return, so hitting the limit triggers cleanup but never blocks the draw; redraw is debounced to once per second.

#### Nine pre-existing comments described code that does not exist
Deleted after verification rather than softened: a netting "check if there's already an opposite position" that returns `true` unconditionally; *"the freshest price available at send time"* above a `validationPrice` that is computed and then never passed; "all required engines are available AND healthy" and "availability AND readiness" when only the trend engine has any state check; "weekend = +0.05" for a weight boost that is `0.0` on FX and `0.05` only on synthetic weekends; an "immutable snapshot lifecycle that deduplicates by bar time and removes stale objects" with no such logic in the function; "Enforces global MT5 1000-object limit" for a comparison against `m_maxObjects`, which is 450; `// Delete Object` above `CheckObjectLimitAndCleanup`. One was corrected in place instead of deleted: the ticket fallback comment said "retcode" where the code falls back to the sending instance's **order ticket**.

#### Two live defects found by checking, queued as their own batches
A risk change never rides in a hygiene commit, so neither is fixed here:
1. **`PostConsensusValidator.mqh:292` calls `ApplySpreadFilter` with transposed arguments.** Signature (`UnifiedSignalPipeline.mqh:129`): `(symbol, double &spreadScore, overrideThreshold, atrValue)`. Call site passes `(symbol, atrValue, spreadScore, effectiveSpreadATRRatio)`. So `atrValue` is bound to the by-reference out-param and is **overwritten with the computed ratio**; `spreadScore` (0.0 there) lands in `overrideThreshold`, failing the `> 0.0` test so the symbol-appropriate 0.30/0.50 ratio configured in Batch 175 is discarded for the generic default; and `effectiveSpreadATRRatio` is used *as* the ATR, making `ratio = spread / 0.3` dimensionally wrong. Net: the exogenous spread gate vetoes wide-price synthetic entries, is inert on tight-spread FX, reports `result.spreadScore = 0`, and prints a fabricated ATR in its own reason string. This is the only call site. -> Batch 187.
2. **`TradeManager.mqh:157-163` `IsHedgingAllowed` returns `true` on both branches**, so the pre-send gate at `:1827` can never block and its `[TRADE-MGR] OpenPosition blocked: hedging not allowed` line is unreachable. The design assumes independent per-strategy positions; on a netting account a second signal nets against the first and breaks SL/TP ownership, risk accounting and attribution. The operator's account is hedging — the 2026-09-23 journal shows a BUY and a SELL on XAUUSD seconds apart with distinct position tickets, which netting would not produce — so this is latent. `validationPrice` (`:1837-1839`) is dead in the same function. -> Batch 186.

#### Verification
- Assertions written by this round were each grep-checked: `ApplySpreadFilter` has exactly one caller; `ConfigureCostLimits` has one definition (`RegimeEngine.mqh:129`) and one call site; `m_lastHealthCheckTime` is declared, initialized and stamped but read nowhere; the object cap and prefix filter were read directly at `:732`/`:754`; no `OrderSend`/`CTrade`/`PositionOpen` exists in the pipeline file.
- Non-comment lines byte-identical to `HEAD`: 3 files, **0 differences**.
- `sync_and_compile.ps1 -All`: 8 root programs, **0 errors / 0 warnings**.

### Batch 184: The AI retrain effectiveness check could never pass

#### Context
Also found while verifying a comment Batch 182 deleted. `AIPerformanceFeedback::TriggerRetraining` judges whether the *previous* retrain improved anything, and pauses retraining for an hour after three consecutive failures. It could not have found an improvement:

```
m_preRetrainAccuracy = m_currentMetrics.accuracy;      // top of every call
...
metricsImproved = (m_currentMetrics.accuracy > m_preRetrainAccuracy + 0.001 || ...)   // same call
```

The baseline was overwritten from `m_currentMetrics` a few lines before the comparison read it, so every test was `x > x + epsilon` — always false. Once the `timeSinceLastRetrain > m_metricsUpdateInterval * 2` gate was satisfied, `m_consecutiveFailedRetrains` incremented unconditionally and the **third** retrain armed `[AI-RETRAIN-PAUSED]` for one hour, whether or not retraining had helped at all.

#### Changed
- `Core/AI/AIPerformanceFeedback.mqh`: the four `m_preRetrain*` assignments moved from the top of the function to its commit point (`m_lastRetrainingTime` / `m_retrainingCount++`), after the effectiveness check has read the previous baseline. Placed after the pause branch's early `return` deliberately: when a retrain is aborted, no retrain happened, so the baseline must not be refreshed.
- First qualifying call still skips the comparison (`m_retrainingCount > 0`), so the first judgement is made on the second qualifying retrain against a baseline that now genuinely predates it.

#### What the operator will see
Retraining can now be recorded as effective, so the hourly pause fires only after three genuinely ineffective retrains instead of after any three. Retraining places no orders — it persists a request and exports a labelled CSV — but the ONNX/ensemble voters feed weighted consensus, so vote behavior can shift as retraining cadence changes. That is the designed behavior returning, not a new risk path.

#### AGENTS.md 4.1/4.2 evidence
Adapter registration, `[AI-VOTE]` call sites, orchestrator qualified-name registration, weight-adaptation sync, and the AI-disabled path are all untouched: the change reorders bookkeeping inside the feedback class and moves no call across a boundary. Compile is the mechanical evidence; runtime evidence is `[AI-RETRAIN] Triggered #N` followed by the absence of `[AI-RETRAIN-PAUSED]` after an improved cycle, which cannot be produced from this machine — the newest EA journal is 23 September (Batch 179).

#### Recorded, not changed
- `m_preRetrainTimestamp` is written here and read nowhere — the dead-state shape Batch 176 removed for VPIN's classification field. Left in place because nothing prints it, so unlike that one it misleads no reader; removing it is a separate cleanup.
- `m_consecutiveFailedRetrains` is not reset when the pause lapses, so a fourth consecutive ineffective retrain re-arms the hour immediately. That reads as intended ("three consecutive"), so it was not touched.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, **0 errors / 0 warnings**.
- Re-read of the reordered function confirms: comparison reads the previous baseline, both early returns (`:511` pause-active, `:537` third-failure) leave the baseline unrefreshed, and no other site writes `m_preRetrain*`.

### Batch 183: The async trade journal could index past a short record and stop the EA at load

#### Context
Found while verifying a comment Batch 182 deleted. `TradeMgrAsyncExecutor` persists its pending async trade requests to a CSV-like common file and, on load, compacts that file: it rewrites only the records that are neither confirmed nor expired. The compaction reader guarded the field count at `if(count < 11) continue;` and then read `fields[11]` — so any record with exactly 11 comma-separated fields passed the guard and indexed one element past the array.

#### Why it matters
The journal is 17 columns (`ticket,symbol,orderType,lot,price,sl,tp,magic,submitTime,timeoutMs,confirmed,expired,idempotencyKey,retryCount,persisted,persistedTime,comment`, header written at `:284` and `:451`), so `confirmed` is index 10 and `expired` is index 11. A short line is exactly what a crash mid-write leaves behind: the last record is truncated, not absent. MQL5 raises a runtime error on out-of-range array access, so the failure mode was **the EA stopping during initialization**, in the routine that decides which unconfirmed async requests to re-adopt — the one moment where losing track of an in-flight order costs real money. The main loader at `:338` guards `count < 17` and was never at risk; only the compaction path was.

#### Changed
- `Core/Trading/TradeMgrAsyncExecutor.mqh:431-442`: the guard is now `count < 12`, and a record that fails it is **kept** rather than skipped, with `[ASYNC-TRADE-JOURNAL] Malformed record kept for inspection | fields=%d | line=%s`. Dropping it would have been the quieter wrong answer: the loader would ignore that line anyway, so deletion only destroys the evidence an operator would need to explain a missing re-adoption. Keeping it preserves the record and makes the anomaly visible, which is the same rule Batch 173 applied to refusals.

#### Verification
- Confirmed no other site reads past the guard: `fields[11]` appears twice, at `:351` (under `count < 17`, indices used up to 16) and at the fixed site.
- `sync_and_compile.ps1 -All`: 8 root programs, **0 errors / 0 warnings**.
- Behavior for well-formed 17-column files is unchanged; only short lines take the new branch.

### Batch 182: Comment reduction, Core/Strategy, Core/Trading and Core/AI — 280 lines and two live defects found

#### Context
Third round of the comment workstream (Batches 180-181 covered `Core/Risk`, `Core/Management` and `Strategies`). Prose only; mechanical slop was exhausted in Batch 180.

#### Changed (whole-line comments, before -> after)
| File | Before | After |
|---|---|---|
| `Core/Strategy/StrategyCatalog.mqh` | 81 | 21 |
| `Core/Strategy/StrategyBase.mqh` | 50 | 16 |
| `Core/Trading/PositionStateTracker.mqh` | 59 | 11 |
| `Core/Trading/TradeMgrPreflight.mqh` | 50 | 26 |
| `Core/Trading/TradeMgrAsyncExecutor.mqh` | 50 | 20 |
| `Core/AI/ONNXInitManager.mqh` | 56 | 16 |
| `Core/AI/AIPerformanceFeedback.mqh` | 71 | 27 |

Repo-wide **7,923 -> 7,643 (-280)**. Only whole-line `//` lines changed; non-comment lines byte-identical to `HEAD` across all 7 files.

#### Kept because it is the constraint, not the prose
The execution-domain notes are the reason this round was worth doing: the filling-mode fallback ignores the caller's `orderFillMode` because sending an IOC/FOK the symbol disallows is rejected with `INVALID_FILL (10030)`, and RETURN is preferred where no fill constraint applies because SL/TP travel in the same request, so RETURN leaves no unprotected-fill window; `FindFreshPositionForSend` is limited to positions opened in the last 30 s so another strategy's or an earlier grid layer's position cannot be mistaken for this send; async tickets are matched by **order** ticket because `SubmitAsync` stored `result.order` and `trans.order` carries it; the ONNX init behaviour contract gates the voter that feeds weighted consensus; AI outcome attribution matches on same symbol within 5 seconds and drops the outcome when nothing matches.

#### Five pre-existing comments were asserting things the code does not do
Deleted after verification rather than reworded:
- `PositionStateTracker.mqh` header named the conflicting top-level `SPositionState` as living in `PositionManager.mqh:21`, reached via `TradeManager.mqh:11`. It is `Core/Position/PositionMgrStateStore.mqh:19`, included at `Core/Position/PositionManager.mqh:25`; the tracker's own struct is nested at `PositionStateTracker.mqh:18` inside the class at `:15`.
- `StrategyCatalog.mqh` claimed "12 indicator strategies" and "17 rows: 12 indicator + 5 AI". The catalog registers **19** rows: 14 `CAT_KIND_INDICATOR` + 5 `CAT_KIND_AI` (counted on `CatalogAdd` call sites).
- The same header claimed the catalog feeds `CStrategyRegistry` via `RegisterStrategy`. It feeds the manager roster; the registry is populated elsewhere. Replaced with the verified rule from `StrategyRegistryState.mqh:86-90`: a row whose name the registry does not know is forced `enabled = false`.
- `ONNXInitManager.mqh` labelled `GetDisableThreshold` / `GetBackoffCapMinutes` as "diagnostics / tests". Both have zero callers repo-wide.
- `AIPerformanceFeedback.mqh` described the pre-retrain snapshot as comparing against metrics "from BEFORE the previous retrain". The code does not do that — see below.

#### Two live defects found by reading, deliberately NOT fixed here
Both are behavior changes in execution and AI self-governance paths; per this project's rule a risk change never rides in a hygiene commit, so they are queued as their own batches.
1. **`TradeMgrAsyncExecutor.mqh:433` reads out of bounds.** Guard is `if(count < 11) continue;`, then `fields[11]` is read at `:436`. The journal is 17 columns (`confirmed`=10, `expired`=11; header written at `:284`/`:451`), and the main loader correctly guards `count < 17` at `:338` — only the compaction path is wrong. A short line (a partially written final record after a crash) passes the guard, and MQL5 raises a runtime error on out-of-range array access, stopping the EA during load in the path that decides which async trade requests to re-adopt.
2. **`AIPerformanceFeedback::TriggerRetraining` can never judge a retrain effective.** `:521-523` overwrite `m_preRetrainAccuracy/Profitability/Sharpe` from `m_currentMetrics` at the top of *every* call, then `:531-533` test `m_currentMetrics.accuracy > m_preRetrainAccuracy + 0.001` (and the two siblings). A value is compared against itself plus an epsilon, so once the 2-interval time gate at `:530` passes, `metricsImproved` is always false, `m_consecutiveFailedRetrains` always increments, and the **third** retrain arms a one-hour `[AI-RETRAIN-PAUSED]` regardless of whether retraining worked. The pre-retrain baseline needs to be captured at the end of the previous retrain, not at the start of this one.

#### Verification
- Every assertion written by this round was grep-checked before being kept, including: `orderFillMode` appears only in the signature; `GetMinimumStopDistance` folds in 1.5x spread (`TradeMgrPricing.mqh:17,213`); `ReplayAsyncTradeRequests` contains no `OrderSendAsync` (re-adopts, never re-sends); `RegisterAttempt` has exactly one caller (`ONNXInitManager.mqh:81`); `m_calibrationErrorThreshold` is set once in the constructor at `:199` and read once at `:720`; 19 catalog rows by kind.
- Non-comment lines byte-identical to `HEAD` for all 7 files: **0 differences**.
- `sync_and_compile.ps1 -All`: 8 root programs, **0 errors / 0 warnings**.

### Batch 181: Comment reduction, Core/Management and Strategies — 248 lines, three false notes deleted

#### Context
Continuation of Batch 180 into the two trees left. Mechanical slop is gone from this repository (Batch 180 found only 16 hits repo-wide), so this round is prose only: the "extracted from / phase code / byte-identical" header genre and declaration echoes in the six densest remaining files.

#### Changed (whole-line comments, before -> after)
| File | Before | After |
|---|---|---|
| `Core/Management/StrategyLifecycle.mqh` | 45 | 7 |
| `Core/Management/StrategyMgrInfrastructure.mqh` | 51 | 13 |
| `Strategies/SupportResistanceFiles/TrendlineDetector.mqh` | 71 | 20 |
| `Strategies/StrategySupportResistance.mqh` | 58 | 20 |
| `Strategies/LiquiditySweepStrategy.mqh` | 62 | 14 |
| `Strategies/UnifiedICTFiles/ImbalanceDetector.mqh` | 57 | 22 |

Repo-wide: **8,171 -> 7,923 (-248)**, the first time this workstream has been under 8,000. Nothing but whole-line `//` comments changed.

#### What survived, and why
The keeps are the facts a reader cannot recover from the code: `ReleaseOnDeinit()`/`FinishDeinit()` must stay separate because the manager re-binds its attribution delegator between them (`EnterpriseStrategyManager.mqh:1025-1030`); `m_diagnostics`/`m_attribution` are injected from `EAOrchestrator` and only `Deinit()` may delete them; `GetStrategyPtr(i)` is dereferenced without a NULL guard and that is deliberate; a cached ATR handle and the Hurst/VPIN engines are shared-ownership and must not be released by the strategy; liquidity pools scan **closed bars only** (`CopyRates(..., 1, ...)`), because the live bar's own high would otherwise count as one of the equal highs being swept; ATR is read at shift 1 so the sweep cap does not move with the tick being judged; the risk manager is fail-open when none is injected (`StrategyBase.mqh:479` returns true); a bullish FVG is filled on a *close* below its bottom, with a 100% wick fill as the stated exception.

#### Three stale comments deleted rather than repeated
Each of these asserted something the code does not do, and was removed instead of being polished:
- `LEAK-FIX: the constructor already allocated m_healthMonitor` — the constructor's init list sets it to **NULL** (`StrategyMgrInfrastructure.mqh:129`); allocation happens in the init path.
- A DO-NOT-TOUCH note on `SyncEnabledWithRegistry` citing `EAOrchestrator.mqh:768` — the caller is `:755`, the forwarder is `:798`, and the body moved to `ConsensusEngine.mqh:192`.
- `Pass price as string tag label` in the trendline drawing path — the label is `StringFormat("%s %.0f%% (T:%d)", ...)` at `StrategySupportResistance.mqh:350` and `:407`: a level-type name, a strength percentage and a touch count. No price is formatted into it.

#### Verification
- Every comment rewritten into an assertion was grep-checked against the code before it was kept — the lesson from Batch 180, where two such claims turned out false. All six files' assertions are confirmed above.
- Non-comment lines compared byte-for-byte against `HEAD` for all 6 files: **0 differences**.
- `sync_and_compile.ps1 -All`: 8 root programs, **0 errors / 0 warnings**.

### Batch 180: Comment reduction, Core/Risk — and two false assertions a sweep introduced

#### Context
Resuming the antislop-code workstream. Repo-wide whole-line comments were **8,372** at the start of this batch (Batch 171 closed at 8,295; Batches 172-179 legitimately added 77 constraint notes). `Core/Risk` at 990 was the largest untouched tree — the earlier rounds covered Management, Engines, Scalp, Orchestration, Strategies and Utils.

#### Two tiers of work
- **Mechanical pass**, scripted rather than by hand, restricted to lines whose first non-space characters are `//`: **16 removals across 14 files repo-wide** — `// Constructor` above `CSubsystemLogger::CSubsystemLogger()`, `// Initialization` above `bool Initialize();`, `// Implementation:`, two blank `//` lines, two dash-run separators. The first draft of the detector also flagged `// --- Compute variance of lagged differences ---`, `// --- OLS linear regression: y = slope * x + intercept ---` and `// Closed/closing positions can still pass PositionSelectByTicket yet report zero volume`, because a "decorative separator" pattern matched any `// --- text ---` and an "end marker" pattern matched the *word* "Closed". Both rules were dropped, not tuned: numbered lists like `// 1. Spread gate (stricter: 20% ATR)` and `// 2. Margin level must be above 200%` carry the threshold values, so the narration rule went too. **The mechanical tier is now effectively exhausted in this repository** — 16 hits across ~330 files.
- **Prose pass over ten `Core/Risk` files**: 115 whole-line comments removed (RiskClusterBudget 25->7, RiskClusterCodec 15->6, RiskOpposingConflictGuard 23->8, RiskAdaptiveTuner 36->9, RiskTieredCorrelation 38->15, RiskSymbolStats 31->11, RiskValidationStats 40->9, RiskMarginHealth 35->15, BasketEquityStop 20->11, EquityCurveManager 20->6). The target was the "extracted verbatim from `CUnifiedRiskManager` (Phase E1/E2/E3)" header genre: old member-name inventories, byte-identical claims, thin-forwarder descriptions, Batch 118/119/152 numbers. What survived is the constraint each file actually depends on — the ownership split (config is passed per call because it changes at runtime; only the state fields are owned here), the MQL5 rule that static methods cannot be `const`, units and scales (0-100 risk percent, 1.0 = no throttle pressure), the pinned 80%/200% margin ceiling with its no-caller setters, and the fail-open-on-data-gap notes.

#### Verification that mattered more than the reduction
Every comment an agent *rewrote into an assertion about code* was checked against the code, the same way a bug report is checked. **Two of them were wrong**, and both were fixed rather than shipped:
- `RiskAdaptiveTuner.mqh:84` came back as *"analytics may only raise this flag, never lower it"*. The tuner lowers `m_conservativeMode` itself at `:125`, deliberately, when the circuit breaker is not holding it — the line below already said so. Now: *"this path may clear it only when the breaker is not holding it."*
- `RiskTieredCorrelation.mqh:10` came back as *"reduce/block are enforced in `CRiskValidationPipeline`"*. They are not enforced anywhere: `RiskValidationPipeline.mqh:1052` forwards straight back into this same class, and `m_correlationReduceThreshold` / `m_correlationBlockThreshold` are written by the config setter and read by nothing (consistent with Batch 38, which left one enforced pair in the pre-trade gate). Now it says the fields are written and never read, which is the fact worth keeping.

A wrong assertion is worse than the slop it replaced, because the next session reads it as documentation.

#### Proofs run
- Non-comment lines compared byte-for-byte against `HEAD` for all 24 modified files: **0 differences**. The harness reads and writes `latin-1` so CP1252/mojibake bytes and CRLF round-trip unchanged — a UTF-8 read of this tree raises `UnicodeDecodeError` on several files.
- Zero unterminated block comments introduced (every edit was a whole-line `//`).
- `sync_and_compile.ps1 -All`: 8 root programs, **0 errors / 0 warnings**. The sync step copied exactly the 24 edited files (18 under `Core/`, 6 under `Strategies/`).

#### Result
**8,372 -> 8,171 whole-line comments (-201)**: 16 mechanical, 186 prose, +1 from the corrected correlation note. No code, blank line, trailing comment, or `/* */` block was touched anywhere in this batch.

### Batch 179: Runtime evidence from the last live session, and the two logs that were lying

#### Context
Batches 168-178 each ended with "runtime evidence owed". The evidence exists: the terminal's own EA journals in `MQL5/Logs/` for 17, 18, 19 and 23 September. They are UTF-16LE, so they must be `iconv`-converted before grepping. The newest is 23 September — the terminal has not attached this EA since the October batches, so nothing below can confirm tonight's new tags; it confirms what the old sessions were actually doing, and that is what the audit needed.

#### What the journals show
Read against the code, from `20260923.log` (the last live session) unless stated:

| Signature | Count | What it settles |
|---|---|---|
| `[POST-CONSENSUS-FILTER] ... filter=atr_ratio` | 71 | The only post-consensus arm that ever fired. |
| `filter=quality_gate` / `hard_spread_cutoff` / `ofi_*` / `vpin_*` | 0 | Empirically confirms Batch 175: those arms had no configuration call site, so they were never on the path. |
| `[GRID-RECOVERY]` / `[ATR-SCALP]` / `[SPIKE-HUNTER]` | 4 / 1 / 1 | All of them `Initialized` / `PARKED: not wired` / `Deinitialized`. `gridsOpened=0`. Confirms Batch 178 from the log side. |
| `[SCALP-ENTRY]` | 6 | All XAUUSD, 0.01 lots. The fast-scalp market path is the only engine that trades. |
| `[SCALP-PENDING]` | 0 | Batch 177's pending-recovery fix is on a path that has never run here. |
| `[SIGNAL-REJECTED]` | 0 | Rejects are not being logged as rejections on this account. |
| `AUTHORITY` | 1 | Only the "single risk authority" init text. Batch 173's ladder has produced no log on a live session yet. |
| `ATR ratio crisis gate: 10.000` | 46 of 71 | See below — the cap was hiding the real ratio. |

One grep artifact is worth recording so nobody re-chases it: `filter=true` appears 12 times, but it is `trend_filter=true` inside `[ENTERPRISE-CONFIG]`, not a filter event.

#### Found and fixed: the fast-scalp budget was released while the position stayed open
The same order-ticket/position-ticket mistake Batch 177 fixed for the grid is live on the one engine that trades. `FastScalpEntry.mqh:281` registered the new scalp under `CTradeManager::GetLastTicket()`, which returns `m_lastTradeResult.order` / `m_trade.ResultOrder()` — the **order** ticket. `CFastScalpPositionTracker` is keyed by **position** ticket. So on the next `ManageScalpPositions` call, `SyncScalpPositionTracking` did:

1. `PositionSelectByTicket(orderTicket)` fails → `FreeScalpRiskBudget` finds the tracker slot, but `FreeForTicket` cannot select the ticket either, so `lotSize` stays 0.0, it falls through to `ReleaseFallback()` and subtracts a full `riskPerTrade` from `m_usedScalpRiskPct`;
2. the same pass re-adds the position under its real ticket — with **no** `riskBudget.Add`, because that only happens at entry.

Net effect: every scalp entry's budget contribution evaporated one tick after the fill, while the position was open. `PassesEntryGates` blocks on `usedScalpRiskPct >= config.scalpRiskPct` (tier `scalpBudgetPct`, default 3.0), so the aggregate scalp risk cap could only ever bind inside the entry tick itself. The `maxScalpPositions` cap still held because it counts live positions by comment, not the accumulator. No over-trading is evidenced on 23 September (6 × 0.01 XAUUSD would not have reached a 3% cap), so this is a defeated control, not a demonstrated loss.

- **Fix**: the entry resolves the position ticket with `CTradeMgrPreflight::FindFreshPositionForSend` (symbol + direction + opened within 30 s + EA-owned magic) and registers *that*. If the position is not visible yet, nothing is registered — `SyncScalpPositionTracking` adopts it by position ticket on the next pass, and the budget the entry already consumed stays consumed. `[SCALP-ENTRY]` prints `ticket=0 | position not visible yet, sync will adopt it` in that case instead of a ticket that would be dropped.

#### Fixed: `[AUTHORITY-GATE]` — the input that gated only a log line
`InpEnableLiveAuthorityGate` defaults to **false** in both `MultiStrategyAutonomousEA.mq5:216` and `MultiStrategyTestingEA.mq5:228`, and its only consumer anywhere was `if(m_config.enableLiveAuthorityGate) Print("[INIT] LiveAuthorityResolver initialized")`. `m_liveAuthority.Resolve(...)` (`EAOrchestrator.mqh:3485`) and Batch 173's `ScaleLotByLiveAuthority` are called unconditionally, so the gate has run on every candidate for the life of the codebase while a default-configured session logged nothing about it. The init print is now unconditional and says what is wired: `[AUTHORITY-GATE] live authority resolver ACTIVE on every risk-approved candidate | InpEnableLiveAuthorityGate=%s is not consulted by the sizing path`.

**Not done, deliberately**: the flag is not being made to gate the sizing path. Turning "the input says off" into "the ladder stops shrinking lots" would let a chart with the saved default silently trade at full size, which is the opposite direction of every other fix here. If the operator wants a real kill switch for the authority gate, it should be built as one — with a loud log and a status report entry — not inherited from a line that never had an effect.

#### Fixed: the ATR crisis gate logged a number it had already clamped
`result.atrRatio = MathMin(atrValue / atrLongValue, 10.0)` ran *before* the veto message, so 46 of the 71 vetoes in the last session all printed `ATR ratio crisis gate: 10.000`. Those lines covered at least two different events: `ATR14 54.34286 / ATR50 5.13826` (10.58×, a real volatility spike) and `ATR14 3419.82571 / ATR50 7.93232` (**431×**, which is not a volatility reading — that is a data fault being treated as a crisis). The cap still governs the decision; the message now carries `raw %.3f` alongside it so the two are distinguishable. **Recorded, not fixed**: whether a 431× ATR14/ATR50 read can be rejected as bad data instead of vetoed as a crisis is a separate question, and fail-safe (no trade) is the correct side to be on until it is answered.

#### Docs corrected
- `RUNTIME_DECISION_GRAPH.md` claimed the validator "operates in `EXOGENOUS_ONLY` mode during normal runtime, limiting post-consensus checks" and that it "no longer re-judges … directional quality". Neither is true of the code: the arms run `spread_cutoff → exogenous_atr → quality → ofi → vpin`. The `EXOGENOUS_ONLY` text in a pre-Batch-175 journal is a stale log string, not a mode. The quality gate is documented as what it is: for a `FULL_QUORUM` packet its threshold is `max(0.40, directionalQuality * 0.9)`, self-satisfying above 0.40, so it only ever rejects below that absolute floor.
- The Batch 78 bullet's `InpEnableLiveAuthorityGate=true` claim is annotated with the correction above.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, **0 errors / 0 warnings** (once with the log-only edits, once again after the scalp ticket fix).
- Owed from the next attached session: `[AUTHORITY-GATE]`, `[ENGINE-STATUS]`, `[VALIDATOR-CONFIG]`, and the first `[SCALP-ENTRY] ... ticket=` carrying a position ticket.

### Batch 178: Three trading engines are enabled by their inputs and wired to nothing

#### Context
Correcting Batch 177's live-versus-dormant scope forced the question, and the answer is the largest expectation gap found in this audit. `InpGridRecoveryEnabled`, `InpATRScalpingEnabled` and `InpSpikeHunterEnabled` all default to **true**. Each engine is `Initialize`d, has symbols `AddSymbol`ed against its Deriv profile, prints an `[INIT]`/`Print` line saying it is enabled, and is `Deinit`d on shutdown. Those are the *only* calls they receive anywhere in `EAOrchestrator` apart from `SetFamilyOverrides` / `SetFamilyConfig`, which configure a loop that never asks them for anything — no `ProcessTick`, no entry evaluation, no send. Each init line does carry `PARKED: not wired into the tick loop (documented-dormant; ProcessTick has no caller)`, and the classes are listed as dormant in the docs, but an operator reading `[DERIV-PROFILER] VIX30 family=... -> GridRecovery enabled` and then a log with no grid trades concludes the strategies are not firing, when the engines were never going to fire.

#### Changed
- **`[ENGINE-STATUS]` printed once at init**, naming the tick-loop driver (fast-scalp, if `enableScalpEngine`) and every engine that is enabled-by-input but parked, each with the input responsible for it. The per-engine `PARKED` notes stay where they are; this is the line that makes the whole set legible in one place instead of scattered across three init messages.
- **Batch 177's changelog and README corrected** for which paths run: of its four send-path fixes, only `FastScalpPendingOrders` is live today, and the live fast-scalp *market* path already handled partial fills through the manager's receipt. The other three fixes are precautionary correctness on dormant code.

#### Deliberately not done — this one is the operator's call, not a wiring detail
- **The three engines are not being wired into the tick loop.** Doing so would start sending real orders from three strategies that have never placed a trade on this account, at lots computed by sizing paths that have never been exercised, on symbols whose Deriv profiles enable them. Every other fix in Batches 172-178 reduces risk; this one would create exposure that does not exist today. That is a strategy activation decision — it needs the operator's intent, a symbol-by-symbol choice, and probably a small-book trial — so it is reported rather than assumed. The inputs saying `true` is not consent to trade: those inputs have been `true` while nothing traded, for the life of the codebase.
- Consequently, two recorded items are **latent, not live**, and are re-prioritized behind that decision: the grid-restart state loss (nothing to reconcile while the grid never trades) and the ATR-scalp / multi-asset magic-offset collision (07000 band shared with `ASSET_FOREX`, unreachable while both engines are parked, and the comment-based lifecycle exclusion is what actually separates the books today).

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, **0 errors / 0 warnings**.
- `[ENGINE-STATUS]` should appear once in the next session's log; with the current input defaults it lists all three parked engines and names FAST-SCALP as the only tick-loop driver.

### Batch 177: Engine send paths given fill confirmation, and the grid's ticket identity corrected

#### Context
AGENTS.md §3.2 says runtime execution is `CTradeManager`-owned. The four engine paths (ATR-scalp, grid recovery, spike hunter, fast-scalp pending) build their own `CTrade`/`MqlTradeRequest` and send directly, so they bypass the confirmation Batch 169 built for the main path. Batch 170 put stop validation on them; this batch gives them confirmation and duplicate protection.

**Which of this is live today matters, and the first draft of this entry did not say it.** `EAOrchestrator` initializes, configures and registers symbols for the spike-hunter (`:1211`), grid-recovery (`:1313`) and ATR-scalp (`:1360`) engines and calls `Deinit()` on them, and each prints `PARKED: not wired into the tick loop (documented-dormant; ProcessTick has no caller)` — verified: the only calls on those three objects are `Init`/`AddSymbol`/`Deinit`. So their send paths do not execute on this account, and everything below about them is precautionary: it is correct behavior waiting for a tick-loop wiring that has not happened. The one live engine is `CFastScalpEngine` (`:2598` entry, `:3315-3327` management). Its **market** path already sends through `CTradeManager` and consumes the execution receipt, including `[SCALP-PARTIAL-FILL]` risk scaling (`FastScalpEntry.mqh:263-276`) — so the partial-fill bug this batch fixes never applied to the live scalp entries. What is live-and-exposed here is `FastScalpPendingOrders::Place`, which calls `OrderSend` directly and whose tracker is polled by `CheckPendingScalpOrders` every cycle.

#### Found, with the line that shows it
- **The grid tracked the wrong kind of ticket** (dormant path, but the defect is real and would bite the moment the engine is wired). `GridRecoveryExecution.ExecuteEntry` stored `m_trade.ResultOrder()` into `levels[level].ticket`, and that value is consumed by `PositionSelectByTicket(...)` and `CTrade::PositionClose(ticket)` — both of which take a **position** ticket. On a hedging account they are different numbers, so a grid level could never be selected or closed. Because Batch 170 excluded engine-tagged comments from lifecycle management, such a position would have **no exit owner at all**: the exit loops skip it (`PositionSelectByTicket` fails), `ticket` is reset to 0 at `GridRecoveryEngine.mqh:503`, and the grid would place another layer on a symbol that already holds one.
- **A partial fill read as a failure** on the three engines that send market orders themselves. `CTrade::Buy/Sell` return false unless the retcode is DONE or PLACED, so `DONE_PARTIAL` — a real, smaller position — reaches the engine as "nothing happened", the cooldown never arms, and the next scan re-fires: duplicate exposure from the fill it already had. Those three engines are the dormant ones (above); the live fast-scalp market path already handled partials through the manager's receipt.
- **A dropped response was a dropped order.** `FastScalpPendingOrders` returned false on any `OrderSend` failure. On `TIMEOUT` or `CONNECTION` the server may still have placed the order, which then triggers later as an untracked position while the engine places a second one.

#### Changed
- **Grid resolves a position ticket**: new `FindLevelPositionTicket(symbol, magic)` (the grid's magic is unique per symbol and level — `base + offset + symbolIndex*100 + level`, `GridRecoveryEngine.mqh:362`), used for `ticketOut`. If nothing matches yet, the order ticket is kept as a fallback and `[GRID-RECOVERY] TICKET UNRESOLVED` says plainly that the level cannot be closed until it resolves, rather than letting the level silently become untrackable. The opened log now prints the ticket it stored.
- **Position-based confirmation on all three market paths** using the existing `CTradeMgrPreflight::FindFreshPositionForSend` (symbol + direction + opened within 30 s + EA-owned magic): `[ATR-SCALP] / [SPIKE-HUNT] / [GRID-RECOVERY] FILL CONFIRMED BY POSITION`, after which the send is treated as successful — the cooldown arms, the counters advance, and the engine does not re-fire. Grid confirmation additionally resolves the ticket.
- **Pending placement recovery** in `FastScalpPendingOrders`: on `TIMEOUT` / `CONNECTION`, or whenever the broker returned a nonzero order, the tracker recovers the ticket (`FindRecentScalpEntry` scans live orders by symbol+magic, then positions) and tracks it instead of returning false. `[SCALP-PENDING] PLACEMENT RECOVERED` names the retcode it overrode.
- Retcodes used are the ones this build is known to define (`TIMEOUT`, `CONNECTION`, verified against `TradeDescriptor.mqh`); the first draft of this fix named `TRADE_RETCODE_INVALID`, `..._ERROR` and `..._SERVER_CLOSE`, which are not in that set.

#### Deliberately not touched
- **The sends still originate in the engines.** Routing them through `CTradeManager`'s open path would recompute magic and comment composition, which is how positions are identified on a live account — a re-numbering orphans every position already open. These paths now have confirmation and duplicate protection at the engine, and §3.2 remains formally unmet for them; that is the recorded state, not a claim that it is fixed.
- **Found and not fixed: the grid has no restart reconciliation.** `levels[].ticket` is in-memory only, so after a terminal restart the engine holds no tickets for positions it still owns, and lifecycle management excludes `GRID-RECOVERY` comments. The positions run naked until their own SL/TP. Needs a rescan-by-magic at init; that is a behavior change on a live book and is queued rather than folded into this batch.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, **0 errors / 0 warnings**.
- Runtime evidence owed: `[ATR-SCALP] FILL CONFIRMED BY POSITION` / `[GRID-RECOVERY] TICKET UNRESOLVED` only appear when the broker actually returns a partial or ambiguous response, so their absence is not evidence of breakage — but `[GRID-RECOVERY] Level opened: ... ticket=` now prints the stored ticket, and that line should show a position ticket on the first grid layer.

### Batch 176: Dead configuration surface found by diffing declarations against call sites

#### Context
Batch 175's defect class — a method declared, defined and forwarded, with no caller — was searched for across `Core/Risk`, `Core/Management`, `Core/Orchestration`, `Core/Trading`, `Core/Position`, `Core/Scalp`, `Core/Engines` and `Core/Pipeline` by collecting every `Set*`/`Configure*` declaration and counting its references repo-wide, including the root `.mq5` programs. Every surviving name was then re-checked by hand against its own file, which mattered: one reported disagreement between the risk gate's and the sizer's correlation thresholds turned out to be wrong (both default to 0.4 reduce / 0.7 block).

#### Changed
- **`CVPINFilter`'s shadow classification field deleted** (`m_classificationMode`, `SetClassificationMode`). `ClassifyTick` reads `m_classifyMode`, which the constructor sets; the twin was written only by a setter nobody called, yet the `[VPIN] Constructed | ... mode=%d` line printed *the twin*. The init log therefore reported a classification mode that had never influenced a classification, and Batch 174/175 had just made VPIN a live veto. The log now prints the field that is actually used.
- **`CRiskMarginHealth`'s false comment corrected**: `// Use configurable max free margin usage` on a value that is fixed at construction. `SetMaxFreeMarginUsage` / `SetMinMarginLevel` have no caller and no operator input feeds either knob, so the pre-trade margin gate runs at 80% free-margin usage and 200% margin level permanently. Left as-is: the rejection message prints the threshold in force, so a trader who hits the ceiling can read it. Recorded in SYSTEM_STRUCTURE.md.
- **`README.md` no longer advertises `InpCorrelationBlockThreshold`.** That input exists in no `.mq5` file — it was documentation of a knob that was never added. The row now states what is true: correlation is enforced once, in the pre-trade gate (`EAOrchestrator.mqh:853-854`), and the sizer's correlation path is explicitly switched off at `:886`, so `CPositionSizer::SetCorrelationThresholds` is dead API rather than a missing control.
- **`[ENTERPRISE-CONFIG]`'s validator description made accurate.** It printed `validator_mode=EXOGENOUS_ONLY` (stale before Batch 175, wrong after it) and listed the confidence and confluence floors among "validator_profile_inputs" as if they gated anything. The line now names the arms that actually run (`spread_cutoff+exogenous_atr+quality+ofi+vpin`) and marks the two floors that are printed but enforce nothing.

#### Deliberately not touched
- `CUnifiedRiskManager::SetTradingDayStartHour` (no caller; the daily risk window rolls at server midnight), `CPositionLifecycleManager::ConfigurePyramiding` / `ConfigureDynamicSL` / `ConfigureLossMinimization` and their `CPositionManager` twins (pyramiding and adverse-momentum exit stay off; the loss guard's *daily budget* was separately wired in Batch 170), and `SetRegimeEngine` (stays NULL, so the regime branch it guards is unreachable). None has an input behind it, so wiring any of them would be inventing policy or adding a feature, not repairing a broken promise — each is listed with its live consequence in SYSTEM_STRUCTURE.md's register instead.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, **0 errors / 0 warnings**. `grep` confirms zero remaining references to the deleted field or setter.
- No behavior change intended in this batch except the corrected `[VPIN]` mode value. Everything else is comment, log and documentation truthfulness.

### Batch 175: The post-consensus validator had no configuration call site, so two operator-enabled filters never ran

#### Context
Batch 174 armed VPIN's EXTREME veto and this batch found why it would not have reached a live session: `CPostConsensusValidator::SetValidatorConfig` is declared, defined, and forwarded by `CEnterpriseStrategyManager` — and nothing in the repository calls it. Every validator arm has been running on the class's constructor defaults since the validator was extracted. This is the same failure shape as Batch 172's `InpAuthority*` inputs and Batch 173's multiplier, one level up: not a dead value, a dead configuration surface.

#### Changed
- **`manager.SetValidatorConfig(...)` is called from `InitializeEnterpriseManagerForSymbol`,** after `ApplyQuorumProfile`. Effective now: `InpEnableOFIProxy` (default **true**, previously OFF) turns on order-flow confirmation; `InpEnableVPINFilter` (default **true**, previously OFF) turns on the VPIN arm including Batch 174's veto; `InpValidatorNewBarMinQuality` (0.68) and `InpValidatorIntrabarMinQuality` (0.70) replace the constructor's 0.75/0.72.
- **The hard spread cutoff is deliberately not taken straight from config.** `InpHardSpreadCutoffPoints` defaults to 200 points while the live roster's synthetic indices run 1,727-11,140 points of spread, and the setter's own 1000-point floor is still below them — wiring the input naively would have vetoed every synthetic at once, which is the bug the validator's constructor comment records having already been fixed by parking at 15,000. The call passes `MathMax(hardSpreadCutoffPoints, maxEntrySpreadPoints)`, so the input can raise the backstop above the admitted entry spread but cannot re-create that veto.
- **Conservative-tier safe mode now tightens the gates it claims to,** each through the authority that already owns the domain: `minVoters` (3) onto `SetMinQuorum`/`SetIntrabarMinQuorum`, `minQuorumThreshold` (0.65) onto `SetQuorumThreshold`, `maxSpreadATRRatio` (0.15) onto the pipeline's `regimeCostGate.maxSpreadToAtrRatio`, and `noStacking` through the per-symbol position cap already enforced by `CheckSymbolPositionLimit`. All are `MathMax`/`MathMin` clamps applied after `ApplyQuorumProfile`, so safe mode may only tighten, never loosen, and no second counting or spread gate was created.
- **Two safe-mode fields stay unenforced, said at init rather than left implied:** `tradeOnlyKillZones` (London 07-10 / NY 12-15 UTC) is FX-session semantics applied to a roster that is mostly 24/7 synthetics the session filter deliberately exempts, and `avoidNewsEvents` has no economic-calendar feed behind it (`IsNearNewsEvent()` is a stub returning false). `[INIT] Conservative safe mode ENABLED` now prints which gates are enforced and which are not. `minConfluence` has no consensus knob to tighten and is likewise not enforced.
- **`VALIDATOR_BASE_SPREAD_ATR_RATIO` / `VALIDATOR_SYNTHETIC_SPREAD_ATR_RATIO`** (0.30 / 0.50) became named constants because the call site must pass them; there is no config field for either, and passing a literal from the orchestrator would have re-tuned the exogenous gate by accident.

#### Deliberately not touched
- The validator's spike-hunter arm: `m_spikeHunterEnabled` is now set from config, but the branch it guards is an empty no-op (`PostConsensusValidator.mqh:178-181`), so nothing changes. Recorded, not papered over.
- `InpMaxPositionsPerSymbolMin` is still read by nothing; safe mode uses the literal 1, because "no stacking" means one, not whatever a differently-named floor input says.
- `validatorNewBarMinConfidence` / `MinConfluence` and their intrabar twins are still read only by the `[ENTERPRISE-CONFIG]` log line. Turning them into vetoes is enforcement the account has never run; they are next in line after this wiring is observed live.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, **0 errors / 0 warnings**.
- Live tier today is `RISK_TIER_MODERATE`, so the safe-mode clamps are inert on this account until an operator selects conservative. The validator wiring is not inert: OFI and VPIN arms switch on at next attach.

#### Risk Flag — this batch turns filters ON
- **Order-flow confirmation and VPIN toxicity now veto entries** on every symbol whose inputs are enabled (both default true). These arms existed in code and in the inputs dialog but have never executed, so no session has ever been filtered by them. Expect `[SIGNAL-REJECTED] ... reason=ofi_contradiction` / `vpin_toxicity` lines that have never appeared in this account's logs, and a lower entry count as a result.
- **The quality floor drops from 0.75 to 0.68 (new bar) and 0.72 to 0.70 (intrabar)** — the configured values, which are looser than the accidental ones. That admits some signals the unplugged validator would have refused. The direction is the operator's stated config, so it is honored, but it is the one change in this batch that increases trade count.
- **Engaging conservative tier now removes stacking and demands 3 voters.** On an account that switched to conservative during a drawdown expecting throttled trading, that is the point; on one that switched expecting nothing to change, it is a large difference. `[SAFE-MODE]` and `[INIT] Conservative safe mode ENABLED | enforced: ...` print the exact list at startup.
- **Runtime evidence owed:** `[VALIDATOR-CONFIG]` once per symbol at init, then `filter=vpin_extreme | VETO` / `ofi_contradiction` on the first toxic or contradictory candidate.

### Batch 174: Risk-clamp truthfulness, VPIN veto wired, four no-op gates deleted

#### Context
Batch 173's method — follow a control from its computation to its consumer — found three more of the same shape in the sizing and veto path. All three were fixed rather than recorded, on the operator's instruction to go ahead with the decisions.

#### Changed
- **The post-size clamp no longer books a risk it did not achieve.** `CCandidateBuilder::BuildCandidate` clamps the lot to the per-trade cap when the sizing modifiers push it over, and that clamp path rounded the result back UP to `SYMBOL_VOLUME_MIN` and then set `candidate.riskPercent = riskCap` unconditionally. Where the minimum lot carries more than the cap, the trade shipped over-risk while the daily entry budget and every log reported it at the cap. The clamp now floors to `SYMBOL_VOLUME_STEP` (so the lot is sendable), and a result under the broker minimum is refused with `[RISK-GATE-REJECT] ... reason=compliant_lot_below_min` plus a `RiskGateReject` JSON event. After the step floor the real risk is at or under the cap, so booking the cap is conservative instead of false. `[RISK-GATE-CLAMP]` now prints 4dp lots — at 2dp a 0.01-step symbol printed both sides of the clamp as the same number.
- **VPIN's EXTREME veto is wired.** `CVPINFilter::ShouldBlockNewPositions()` was called only by the filter's own status line, and `CPostConsensusValidator::CheckVPINFilter` returned true on every path, so the `!CheckVPINFilter(...)` reject beside it could never fire. It now returns false at the veto, logging VPIN, the configured extreme threshold and the size multiplier. The reject plumbing (`vetoReason="vpin_toxicity"`) already existed.
- **The validator's VPIN thresholds came from the filter, not literals.** `CheckVPINFilter` compared VPIN against hardcoded 0.95 and 0.85 while the filter classifies EXTREME at `InpVPINExtremeThreshold` (default **0.70**, clamped 0.30-0.95) and HIGH at 0.5. On default config the literals sat above the veto line, so the "extreme" log could not be reached and everything below 0.85 was reported as unfiltered. Regime is now read through `GetToxicityRegime()`, and the size reduction is logged at MEDIUM and above as what it is — a `CVPINLotModifier` action, not a validator one.
- **Four no-op gates deleted.** `ApplySkewStepScaling`, `ApplyFullMarginStacking` and `ApplySafeModeRestrictions` were `return lotSize;` stubs under names claiming a sizing step; `EvaluateEAModeAdmission` returned `true` with a zero confidence bonus for every candidate, so its rejection branch and its bonus were both unreachable. The stub definitions and the admission call site are gone. Mode admission belongs to `CLiveAuthorityResolver` (`INDICATOR_ONLY` / `AI_ONLY_MODE_NO_AI`), which runs after this point — one authority per domain.
- **`m_lastVPINMultiplier` labelled honestly.** Its comment claimed "position-size multiplier, consumed by sizing"; nothing reads it. It is a diagnostic mirror of what `CVPINLotModifier` applies, and is now written on every branch and documented as such.
- `GetExtremeThreshold()` added to `CVPINFilter` so the veto log can name the line it crossed.

#### Deliberately not touched
- **Conservative-tier safe mode** still enforces only `minConfidence`. `IsSignalEvaluationAllowed` (kill-zone + spread), `noStacking`, `minVoters` and `minConfluence` are read by the diagnostics printer alone. The live tier is `RISK_TIER_MODERATE`, so wiring them changes nothing today and would change a great deal the moment an operator engages conservative mode — that is Batch 175, decided on its own merits rather than folded in here.
- The `ApplyDrawdownScaling` / `ApplyMomentumScaling` round-ups to broker minimum stay: unlike the clamp path, their result is measured by the post-size re-gate at `:600`, so any risk they add is now caught (and refused) there rather than mis-booked.
- Engine magics, and engines sending outside `CTradeManager`, unchanged.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, **0 errors / 0 warnings**.

#### Risk Flag — two behavior changes on live money
- **VPIN now blocks entries, not just shrinks them.** On FX and metals, a symbol whose VPIN reaches its configured extreme threshold (0.70 on defaults) now produces zero new positions until toxicity drops, where before it produced a 0.1x trade. This is the filter's documented purpose ("EXTREME — kill new positions") and the reason `InpVPINExtremeThreshold` exists, but it is a real reduction in trade count during toxic conditions, and toxic conditions are exactly when the strategies signal most. **Correction, same session (Batch 175):** the veto was wired to an arm that nothing configured — `SetValidatorConfig` has no call site, so `m_enableVPINFilter` stayed false and Batch 174's veto could not fire. It became live in Batch 175, and the claim above describes the behavior after that wiring.
- **Some over-cap trades that used to ship are now refused.** Where the compliant lot lands under the broker minimum, the candidate is dropped. The alternative was shipping a position that could lose more than the per-trade cap while the budget recorded it at the cap.
- **Runtime evidence owed:** `[POST-CONSENSUS-FILTER] ... filter=vpin_extreme | VETO`, `[RISK-GATE-REJECT] ... reason=compliant_lot_below_min`, and `[RISK-GATE-CLAMP]` at 4dp on the first clamped trade.

### Batch 173: Live-authority ladder applied to position size, with refusals made loud

#### Context
Batch 172 left the resolved `riskMultiplier` unconsumed and put three options to the operator. The decision was "apply the full ladder, but don't make things fall silently" — so every gated candidate is now scaled by its authority multiplier, and every consequence of that scaling is required to announce itself.

#### Changed
- **`CCandidateBuilder::ScaleLotByLiveAuthority(candidate, riskMult, corrId)`** is called from `EAOrchestrator` immediately after `m_liveAuthority.Resolve(...)` and the `allowed` test, and before the send. It multiplies the shipped lot by the ladder value, floors it to `SYMBOL_VOLUME_STEP`, and rewrites `candidate.lotSize`.
- **Shrink-only by construction, verified rather than assumed.** `Resolve()` assigns the multiplier from a ladder whose top rung is 1.0 (`LiveAuthorityResolver.mqh:229-239`), `MathMin(riskMult, m_aiBootstrapRiskMultiplier)` pulls unproven AI down (`:261, :269`), and `MathMax(0.10, riskMult)` floors it (`:277`). The one branch that *raises* is `PROVEN_AI`'s `MathMax(riskMult, m_aiPromotedRiskMultiplier)` (`:254`), and Batch 172 clamps that promoted floor to `AUTHORITY_PROMOTED_MULT_CAP = 0.75`, so no path can produce a multiplier above 1.0. Nothing is sized larger than what `CUnifiedRiskManager` approved, and the Batch 152 post-size re-gate (an upper bound) cannot be broken by this step.
- **Broker-minimum refusals are loud and counted, never rounded up.** `CPositionSizer::NormalizeVolume` clamps UP to `SYMBOL_VOLUME_MIN` (`PositionSizer.mqh:659`), so using it here would hand the entire reduction straight back while logging that a shrink happened. The method floors by hand instead, and a lot landing under the minimum produces `[AUTHORITY-REJECT]` twice — the arithmetic, then a plain statement that the symbol is dark at this authority level until the stop widens, equity grows, or the floors/rungs are revisited — plus an `AuthorityReject` JSON event and a running per-symbol and session total.
- **Booked risk follows the lot.** `candidate.riskPercent` is scaled by the same ratio, because `EAOrchestrator` feeds it to `RegisterExecutedTradeRisk`; leaving it at the pre-shrink value would charge the daily entry budget for risk the position never took.
- **Aggregate visibility.** `[CandidateBuilder]` status now prints `authorityLotRefusals total=N` and a per-symbol breakdown, so a symbol the ladder has sized out of existence cannot be mistaken for a symbol that simply has no signals. A multiplier arriving `<= 0` is also refused rather than sent unscaled.
- **AGENTS.md §6 signatures became real.** `FMT_AUTHORITY_REJECT` and `FMT_AUTHORITY_REDUCED` are defined in `Core/Utils/LogMacros.mqh:41-42` and were used by nothing — §6 had listed `[AUTHORITY-REJECT]` / `[AUTHORITY-REDUCED]` as verification evidence for every batch since. Both tags are now emitted (as literal tags, matching how every other log in this file is written), so the section is checkable for the first time.
- A stale Batch 170 comment in this file claiming "VPIN still vetoes signals; it never sized" was corrected; both halves were wrong (see Batch 172).

#### Deliberately not touched
`BuildCandidate` still ends its own scaling chain with "Floor at broker minimum" (`lotSize < brokerMinLot → brokerMinLot`), which silently rounds the *other* scalers (drawdown, momentum) back up to the minimum after shrinking them. That is the same over-risk shape this batch refuses to reproduce, but it is pre-existing behavior on paths the operator did not ask about, so it is recorded rather than changed here.

#### Verification
- `sync_and_compile.ps1 -All`: all 8 root programs at **0 errors, 0 warnings** (`MultiStrategyAutonomousEA.mq5` 69,267 ms, `MultiStrategyTestingEA.mq5` 72,484 ms, the four MQH* tools, `TrainingDataExporter.mq5`, `WalkForwardTesterEA.mq5`). An earlier `-All` run failed with 18 errors because this method was first written against a type named `SCandidate`, which does not exist in this codebase — the candidate struct is `STradeCandidate`. Fixed, together with a `const` violation (`GetStatusReport()` cannot call `ArraySize()`, which binds by reference — the array length is now tracked in `m_authorityBlockSymbolsCount`).
- Refusal math re-read at the cited lines: step floor uses `MathFloor(volume/step + 1e-9)` and 8-digit normalization, the same convention that Batch 16x established after `NormalizeDouble(...,2)` pushed a 0.001-step lot off-step and the broker rejected it as invalid volume.

#### Risk Flag — this is a live-sizing change
- **Every low-authority trade is now materially smaller.** Candidates below the 0.35 score rung take `bootstrapMult * 0.5` = 0.25× of approved risk; unproven AI-only candidates are capped at 0.5×; a fully-scored hybrid candidate is still 1.0×. Expect total exposure and per-symbol lot counts to drop, and expect the equity curve per trade to shrink accordingly. This is the intended effect of the ladder, not a side effect.
- **Some symbols may stop trading entirely.** Where the approved lot times the multiplier lands under `SYMBOL_VOLUME_MIN`, the candidate is refused — most likely on coarse-tick synthetic indices and on small accounts. Each such loss is logged as `[AUTHORITY-REJECT]` with the arithmetic and counted in the status report; if one appears and is not wanted, the levers are the `AUTHORITY_MIN_*` floors, the ladder rungs, or a wider stop at the same risk.
- **Do not read the first session as a strategy regression.** Fewer and smaller AI trades is this change working. Judge it against `[AUTHORITY-REDUCED]` counts and the per-symbol refusal breakdown, not against last month's trade count.
- **Runtime evidence owed (AGENTS.md §6):** `[AUTHORITY-CONFIG] effective:` once at init, `[AUTHORITY-REDUCED]` on the first scaled candidate, `[AUTHORITY-REJECT]` only where a symbol is genuinely sized out, and `authorityLotRefusals` visible in the `[CandidateBuilder]` block.

### Batch 172: Live-authority thresholds wired, profit factor computed, and two dead outputs recorded

#### Context
Batch 171's comment sweep surfaced the `PROVEN_AI` defect while verifying a subagent's rewrite; following it turned out to be a wiring problem across the whole live-authority layer rather than one missing assignment. Everything below was verified at the cited line before editing, and two claims from my own earlier batches were disproved in the process.

#### Fixed — the promotion gate could never fire
- **`profitFactor` was never written.** `Resolve()` gated `PROVEN_AI` on `m_strategyPerf[i].profitFactor >= 1.2` (`LiveAuthorityResolver.mqh:182`), while `RecordOutcome` updated only `totalTrades`, `winningTrades`, `expectancyR` and `consecutiveLosses`. The field kept its constructor 0 for the life of the process, so the condition was permanently false and every AI-only contributor was pinned at the bootstrap cap however well it traded. It is now accumulated from the R-multiple stream `RecordOutcome` already receives: `grossWinR / grossLossR`, summed by the sign of `profitR` so a breakeven close enters neither side, with a no-losing-trade record reading as perfect (`999.0`) rather than dividing by zero. A ratio of sums was chosen deliberately — averaging per-trade ratios is not a profit factor.
- **`maxDrawdownR` deleted.** Declared, constructor-initialized, never written, never read. No serialization references it.

#### Fixed — the resolver ignored its own configuration
`EAOrchestrator` called `Configure(effectiveMode, m_config.aiStandaloneMinConfidence, 0.5, 2, 0.3)`. Three of those are literals, and `0.3` overrode `config.authorityMinExpectancyR`, which the config sets to `0.03`. Six inputs — `authorityMinSamples`, `authorityMinProfitFactor`, `authorityMinCostScore`, `authorityMinReadinessScore`, `authorityMinContextScore`, `aiPromotedRiskMultiplier` — reached `config` and were read by nothing. `Configure` now takes all eleven thresholds and has **no default arguments**, so a new call site cannot reintroduce a literal without failing to compile.
- **Config may tighten, never loosen.** `README.md:43` and `SYSTEM_STRUCTURE.md:439` document promotion as 30 samples / expectancyR ≥0.3 / PF ≥1.2 / promoted 0.75x — the literals were the stated design, and the config defaults are merely untuned values nobody could have chosen knowingly because nothing read them. Wiring them naively would have silently loosened a gate that had never executed and raised the promoted floor 0.75 → 1.00. The floors are now `AUTHORITY_MIN_*` defines and each configured value is clamped to them, the same policy Batch 169/170 apply to compounding tiers. At stock defaults six inputs clamp (`samples 12→30`, `expectancyR 0.03→0.3`, `profitFactor 1.10→1.2`, `promotedMult 1.00→0.75`, `readiness 0.52→0.60`, `context 0.48→0.55`); the last two land on the values the code already used, so only the first four were live policy decisions, and they are now visible at init as `[AUTHORITY-CONFIG] clamped:` / `[AUTHORITY-CONFIG] effective:` rather than silent.

#### Fixed — inverted cost bonus
`if(costScore <= 0.3) authorityScore += 0.05; // Low cost` paid authority points to the *most expensive* trades. `costScore` is quality-shaped: `SignalPipelineWeighter.mqh:279` adds it into the weighted signal score as `costScore * 0.0543`, so higher means cheaper. Now `>= m_authorityMinCostScore`.

#### Finding — two dead outputs found by following values to their consumers
- **The authority risk multiplier reaches no lot.** `authority.riskMultiplier` is copied to `candidate.liveAuthorityRiskMult` (`EAOrchestrator.mq5:3418`) and read by no code in the repository, and `result.allowed` is assigned `true` unconditionally at the end of `Resolve()`. So the entire `authorityScore` ladder (1.0/0.85/0.70/0.50), the bootstrap cap, `PROVEN_AI` and every bonus are observational: they decide the logged reason string, not the position size. The only live authority effects are the `INDICATOR_ONLY` / `AI_ONLY_MODE_NO_AI` mode vetoes and `LOW_CONFIDENCE`. **This batch therefore makes the promotion branch reachable and its log honest about which branch was taken; it does not change any position size.** Closing the gap means multiplying the multiplier into `CPositionSizer`, where `CVPINLotModifier` / `CADXLotModifier` / `CVolatilityTargetingModifier` already scale the same base size. Three options were put to the operator — AI-only path only, the full ladder, or delete the field and make the logs honest — and none was chosen, so no sizing behavior was changed unilaterally. It is the first item queued for Batch 173.
- **VPIN's veto is dead the same way.** `CVPINFilter::ShouldBlockNewPositions()` is called only by the filter's own status line; `CPostConsensusValidator::CheckVPINFilter` returns `true` on every path, so its `!CheckVPINFilter(...)` reject at `:171` can never fire. VPIN does affect live trading, but solely through the shrink-only lot multiplier `CVPINLotModifier` applies in the sizer chain. The filter's header comment asserting `ShouldBlockNewPositions()` was "the gating authority" was corrected in place.

#### Corrections to my own earlier claims
- Batch 170's changelog said "VPIN still vetoes signals; nothing now pretends it sizes." Both halves are wrong: VPIN never vetoes, and `CVPINLotModifier` does size for real. Deleting the `ApplyVPINScaling` / `ApplyVolTargetScaling` stubs was still correct — they were no-ops duplicating a path that already works elsewhere — but the recorded reasoning is fixed in place above.
- The claim in my Batch 172 report that the fix makes AI promotion affect money was corrected the same session, on finding the multiplier unconsumed.

#### Verification
- `sync_and_compile.ps1 -All`: **all 8 root programs 0 errors / 0 warnings** (`MultiStrategyAutonomousEA.mq5` and `MultiStrategyTestingEA.mq5` both compile `LiveAuthorityResolver.mqh` through the orchestrator, so both exercise the eleven-argument `Configure`, the `AUTHORITY_MIN_*` floors and the new status output). An earlier single-EA pass also returned 0/0 and is what caught the integer-clamp warning risk described below.
- Integer clamp written as a ternary rather than `MathMax`, whose integer overload returns a double and would warn on assignment into `int`; the project holds a 0-warning bar.
- Comment-only rounds of Batch 171 are proven separately; this batch is the only code change and touches `LiveAuthorityResolver.mqh`, its `Configure` call site in `EAOrchestrator.mqh`, and one comment in `VPINFilter.mqh`.

#### Risk Flag
- **No live sizing change ships in this batch.** `riskMult` remains unconsumed, so AI-only trades keep taking full configured risk exactly as before. What changes is that the branch decision and the `[AUTHORITY-CONFIG]` thresholds become observable and truthful, and that an inverted cost bonus no longer inflates expensive candidates' logged authority score.
- **If the multiplier is wired later without care it is a large change.** Applying the full ladder would shrink trades across the book, including indicator-backed ones, and at the 0.5 rung some candidates would fall toward the broker minimum lot and hit the Batch 170 `[PositionSizer] Min lot round-up refused` path, silently switching those symbols off.
- Runtime log evidence for Batches 168–172 is still owed (AGENTS.md §5.2 is compile + static review). On the next session confirm `[AUTHORITY-CONFIG] effective:` appears once at init, `[AUTHORITY-LEARN]` still fires per closed AI trade, and `[VPIN-MODIFIER]` shrink-only behavior matches `[VOLUME-PROXY]` gating on synthetics.

### Batch 171: Comment hygiene — 11,201 comment lines removed, no code touched


#### Context
Whole-line comments had grown to 19,496 across 340 MQL files - roughly one comment line for every six code lines. Most of it was decoration and restatement rather than information: MetaEditor's `//+---+ / //| Name | / //+---+` banners around declarations that name themselves, and long multi-line "why this fix exists" narratives that bury one constraint under a paragraph of history.

#### Changed
- **Mechanical pass (325 files).** Banner rule lines removed; `//| Label |` blocks unpadded to plain comments; labels that only restate the declaration below them (or the file's own name) removed; standalone one-line echoes of the next declaration removed. Echo detection requires the comment phrase to be contained in a single identifier, or every content word of the comment to be covered by that identifier's camel-case parts - so `// Calculate Accuracy Metrics` over `CalculateAccuracyMetrics()` goes, while `// Track per-regime performance` over an unrelated line stays. Legal/copyright lines and unterminated banner fragments were left alone.
- **Prose collapse (10 blocks, the loudest ones).** Multi-line fix-narratives in `TradeMgrPricing`, `TradeMgrPreflight`, `TradeManager`, `UnifiedRiskManager`, `ConsensusEngine`, `EAOrchestrator`, `MagicRange`, `StatisticalArbitrageStrategy` cut to the constraint alone: the unit bug keeps "SYMBOL_SPREAD is already points", loses the four-line post-mortem; the tier envelope keeps "tiers may lower authorised risk, never raise it"; the voter floor keeps why one lone voter was 100% consensus, in two lines.
- **Rounds 3-11: 12,760 -> 8,295 whole-line comments, -4,465 (-35%).** Batch 171 end to end is 19,496 -> 8,295 (-57%). Committed per round so a regression stays scoped: `7d783c6` -2,430 (Core/Engines, Core/Scalp, Core/Management, Core/Risk, Core/Trading), `6554174` -183, `6c3703a` -693 (Core/Utils, Core/Orchestration satellites), `e3efa7e` -136 (Strategies), `febaecd` -7, `fb830a5` -414 (`EAOrchestrator.mqh` alone, 668 -> 254), `07e56a0` -104 (risk and consensus cores), `3cdfdd6` -160 (Core/Risk mid), `30657ff` -210 (MeanReversion 106->53, VolatilityBreakout 86->50, StrategyTrend 86->49, StatisticalArbitrage 75->39), and round 11 -129 in this commit (PostConsensusValidator 67->33, DiagnosticsManager 65->32, StrategyMgrRoster 54->32, StrategyRegistryState 53->32, StrategyPerformanceHealth 48->29). The 8,295 figure includes the ~20 explanatory lines Batch 172 added.
- **Second banner sweep.** Round 1's detector missed 28 files; the remaining 129 box-rule lines and 78 padded `//| Label |` lines are now gone, plus 54 short labels that only restated the declaration under them (`// Destructor` over `X::~X()`, `// Initialize` over `::Initialize()`). Repo-wide count of leftover banner rules and `//|`-padded lines is now **zero**.
- **The echo rule refuses value.** A comment is dropped only when every content word is covered by an identifier on the next code line, and any comment containing a digit, an expression operator or a constraint word is exempt - so `// Lot = baseLot * (progressionFactor ^ level)` and `// Track per-regime performance` both survive.
- **Two comments were restated rather than deleted because the code contradicted them** (see Finding below): `LiveAuthorityResolver`'s proven-AI gate reads a `profitFactor` that is never written, and curated strategy mode force-enables every flag regardless of the `enableX` input the old comment said it honoured.
- **Kept deliberately.** `Core/Utils/MagicRange.mqh`'s engine-tag rationale collapsed 6 lines to 4 with all four facts intact. Four blocks in `EAOrchestrator.mqh` (5-10 lines each) were left as they are: dependency-wiring order, the intentional-stub justification that stops someone re-routing a second flatten authority next to `CRiskCircuitBreaker`, the closed-trade feedback contract, and the AI ownership hierarchy. Each carries several distinct prevention facts - value is not length, but neither is it deleted.
- **Not swept:** the Dashboard tree, `MQHModelTrainer/`, and files already under 12 comment lines.

#### Verification
- **Cumulative executable-content proof:** a string-aware projection that strips `//` and `/* */` outside string and character literals, run over all **244 files changed between `e0c2ebc` and the working tree: 242 are comment-only with zero executable-line differences, and the only two carrying code changes are `Core/Orchestration/LiveAuthorityResolver.mqh` and `Core/Orchestration/EAOrchestrator.mqh` — the Batch 172 fix.** The same projection treats a stray `/*` or `*/` deletion as a code change, so this also proves no block comment was left unterminated. Per-round checks additionally confirm no file gained comments and CRLF (plus one UTF-8 BOM in `CandleConfluenceScorer.mqh`) were preserved. Two subagents self-reported transient code edits (a merged constructor line, a stray `double cappedLot`); both were proven fully reverted rather than taken on their word.
- **All 8 root programs recompiled 0 errors / 0 warnings** after the sweep (`sync_and_compile.ps1 -All`; `MultiStrategyAutonomousEA.mq5` 75.2 s, `MultiStrategyTestingEA.mq5` 70.9 s).
- Whole-line comments 19,496 -> 12,760 in rounds 1-2, -> 8,897 in rounds 3-7. The commit message for `f768c0d` quotes 12,384, which was the after-count over the 325 scanned files only, not the full tree - corrected in `7a2cc50`.

#### Finding recorded, not fixed
`Core/Orchestration/LiveAuthorityResolver.mqh:182` gates the `PROVEN_AI` promotion on `m_strategyPerf[perfIdx].profitFactor >= 1.2`. `RecordOutcome` (`:220-247`) updates `totalTrades`, `winningTrades`, `expectancyR` and `consecutiveLosses` only; `profitFactor` is set to 0 by the struct constructor at `:34` and never written anywhere in the repo, and `maxDrawdownR` is likewise never written. The condition is therefore permanently false, the `riskMult = MathMax(riskMult, 0.75)` floor at `:186` is unreachable, and every AI-only contributor stays pinned at `m_aiBootstrapRiskMultiplier` however well it trades - so the §4.1 AI authority-escalation path has never executed. The failure is conservative (it under-risks, so it costs nothing today) and fixing it means choosing a source for `profitFactor` when `StrategyHealthMonitor` and `RiskSymbolStats` already compute one each. That is a risk-behavior change and does not belong in a comment batch; it is queued as Batch 172.

#### Risk Flag
No behavior change by construction (comment-only). The risk is informational: a fix-narrative that was cut may still have been carrying a "don't do this again" note for someone reading the file cold. The full reasoning for every batch remains in this file and in the batch-numbered commit messages.

### Batch 170: Engine send governance, min-lot risk ceiling, real-volume honesty, one exit authority per book

#### Context
Batches 168–169 closed the reachability defects (magic ownership, live exits, continuous breakers) and the execution defects inside `CTradeManager`. This batch handles what that work exposed: four send paths and one position-management rule that sit *outside* `CTradeManager`, a configured risk allowance that could multiply the approved risk by 15, volume-derived filters running on data that is not volume, and two exit authorities acting on the same ticket.

Findings were re-verified against source before editing, and two earlier claims were corrected on the way:
- `SetDailyRiskBudget` is not "uncalled config plumbing" — the live gap was `CPosLifecycleLossGuard::m_dailyRiskBudgetPercent`, which had **no writer at all**, so the guard's daily-loss breaker could never arm. `CPositionManager::SetDailyRiskBudget` belongs to the manager that Batch 168 deactivated.
- The ATR-scalp, grid-recovery and spike-hunter engines are **dormant** (initialized, symbols added, no `ProcessTick` caller anywhere), so their ungoverned sends were latent hazards rather than live losses. The live bypass was the fast-scalp *pending* order path.

#### Fixed — send governance outside `CTradeManager`
- **Stop feasibility and expectancy now gate every engine send.** `CTradeMgrPricing::NormalizeAndValidateStops` is applied before the send in `Core/Scalp/ATRScalpEntry.mqh`, `Core/Scalp/GridRecoveryExecution.mqh`, `Core/Scalp/SpikeHunterExecutor.mqh` and `Core/Scalp/FastScalpPendingOrders.mqh`. Those paths build their own `CTrade`/`MqlTradeRequest`, so none of Batch 169's work reached them: scalp entries could still place a stop inside the broker minimum, or a target that cannot clear the round-trip spread. Pending orders map `ORDER_TYPE_BUY_LIMIT`/`SELL_LIMIT` to the market type the validator keys its adjustment direction on.
- **Rejected sends log and abstain** (`[ATR-SCALP] STOPS REJECTED`, `[GRID-RECOVERY] STOPS REJECTED`, `[SPIKE-HUNT] STOPS REJECTED`, `[SCALP-PENDING] STOPS REJECTED`) instead of sending and letting the server return `INVALID_STOPS`.
- Remaining structural gap, unchanged deliberately: these engines still send outside `CTradeManager`, so AGENTS.md §3.2 ("runtime execution must remain CTradeManager-owned") is still not literally true for them, and they do not get fill verification, retry dedup or journal entries. Migrating them is a separate batch; the protective gates that matter for money are now applied in place.

#### Fixed — risk
- **Min-lot round-up is capped in code.** `CPositionSizer::SetMinLotRiskMultiplier` clamps to `MAX_MIN_LOT_RISK_MULTIPLIER` (3.0) and logs `[RISK-MINLOT]` when it does, and the struct default dropped from 15.0 to the ceiling. `Config/live_overrides.json` asks for 15.0 with `allowMinLotRoundUp: true`: the round-up happens in the sizer, *after* the pre-trade gate approved the sized lot, so one position could risk 15% of equity against a 1% setting. The unreachable `riskRatio > 15.0` pre-check (it could never bind while the configured ceiling was also 15) was removed and the refusal message now says what to do about it.
- **The live daily-loss breaker can arm.** `CPosLifecycleLossGuard` takes a `SetDailyRiskBudgetPercent`, exposed through `CPositionLifecycleManager::SetDailyRiskBudgetPercent` and wired from `m_config.maxDailyRisk` at init (`[INIT] ... dailyRiskBudget=%.2f%% of equity`). The budget is held as a percent and converted against `min(balance, equity)` at the check, so it tracks drawdown instead of freezing at start-of-day equity.

#### Fixed — one exit authority per book
- **Engine-managed positions are excluded from lifecycle exits.** New `IsEngineManagedPosition()` in `Core/Utils/MagicRange.mqh` recognises the comment tags the engines stamp (`ATR-SCALP`, `GRID-RECOVERY`, `SPIKE-HUNT`, `SCALP|`), and `CPosLifecycleMagicFilter::IsLifecycleManaged()` plus `CPositionLifecycleManager::IsPositionLifecycleManaged()` apply ownership *and* that exclusion at the seven exit/modify sites (`CTradeManager::ManageAllPositions` breakeven + trailing, `PosLifecycleExit` partial-close and max-hold, `PosLifecycleLossGuard`, `PosLifecyclePyramid`, `PosLifecycleVolatility` dynamic SL/TP, and the manager's signal-reversal and ranging-regime loops). Batch 168 turned lifecycle exits on for *every* owned position, which put breakeven and trailing on top of positions the fast-scalp engine was already closing at its own 1R/partial targets. The positions stay EA-**owned** — risk, exposure and daily-loss accounting still see them — they are only excluded from lifecycle exits.
- Magic cannot separate the two books: the scalp/grid/spike offsets are composed from the same asset-offset space as the strategy book (the ATR scalp default offset 7000 **is** `ASSET_FOREX`'s offset, and grid's family config is fed `profile.magicOffset` from the Deriv profiler), so moving them into a reserved band is not safe while the per-symbol slot is added on top of every offset. The send comment is the one field each engine stamps uniquely and that survives a restart.
- **Substring matching fixed.** `FastScalpExit` and `FastScalpPositionTracker` selected positions with `StringFind(comment, "SCALP") >= 0`, which also matches `ATR-SCALP` — the fast-scalp engine registered and closed another engine's positions. Both now require the tag at index 0.

#### Fixed — volume-derived data honesty
- **Synthetic indices no longer run order-flow engines.** `COrchestratorMathEngineHub::CreateEnginesForSymbol` gates OFI and VPIN on the same synthetic-index exclusion Batch 107 already applied to VWAP, Volume Profile and CVD. On those symbols "volume" is a price-update count, so an order-flow-toxicity veto was being computed from nothing.
- **Tick-volume-as-real-volume is now labelled.** New `HasOnlyTickVolume()` reads `MqlRates.real_volume`; when a broker publishes no traded volume the EA logs `[VOLUME-PROXY] <symbol> | no traded volume ...` at init instead of letting every volume-derived filter silently use the proxy.
- **Two fake sizing steps removed.** `CandidateBuilder::ApplyVPINScaling` and `ApplyVolTargetScaling` were `return lotSize;` stubs ("Would use m_mathRegistry if available") under comments claiming they resized the lot, while the validator status report printed a `LastVPINMultiplier` no caller consumed. Removing them was still correct — they were no-ops duplicating a path that already exists elsewhere — but **this entry's closing claim was wrong on review and is corrected here**: VPIN does *not* veto anything (`CPostConsensusValidator::CheckVPINFilter` returns true on every path, so the `if(m_enableVPINFilter && !CheckVPINFilter(...))` reject at `:171` can never fire), and something *does* size: `CVPINLotModifier` and `CVolatilityTargetingModifier` are registered into the `CPositionSizer` modifier chain (`PositionSizer.mqh:271`, applied at `:366`) and scale the lot for real. So VPIN's toxicity acts on position size through the sizer, not through the consensus validator; the validator's own stored multiplier is a second, unread copy of a value the sizer computes independently.

#### Verification
- `sync_and_compile.ps1` → **0 errors, 0 warnings** for `MultiStrategyAutonomousEA.mq5`; sibling root programs compiled with `-All`. One real compile error was found and fixed on the way: `CopyRealTickVolume` is not available in this MQL5 build (8 cascading parse errors), replaced with `MqlRates.real_volume` via `CopyRates`.
- Engine send sites, comment tags and offset composition were each re-read at the cited lines before editing; the two stale claims recorded under Context came from that re-read, not from assumption.

#### Risk Flag (intentional behavior change)
- **Min-lot refusals will block trades on small accounts.** Anything that would have rounded up more than 3x is now refused with `[PositionSizer] Min lot round-up refused`. On a coarse `SYMBOL_VOLUME_MIN` (synthetic indices especially) a symbol may stop trading entirely at 1% risk. The fix is a wider stop at the same risk, not a raised ceiling.
- **Fast-scalp positions no longer get breakeven or trailing from the lifecycle manager** — that authority returned to the scalp engine. If the scalp engine's own exit logic is too lax somewhere, nothing else will now catch it; watch `[SCALP-*]` exits against `[LIFECYCLE]` ones after deploy.
- **The exclusion is comment-based.** If a broker rewrites or truncates an order comment so the tag is no longer at index 0, that position falls back to lifecycle management (today's behavior) rather than losing protection — a silent re-merge of the two authorities, visible only by reading `[CONSENSUS-*]`/exit logs.
- **OFI/VPIN are off for synthetic-index symbols**, so those symbols lose two veto layers they were exercising on fabricated input; entry counts on synthetics may rise.
- **Runtime log evidence is still outstanding** for Batches 168–170 (AGENTS.md §5.2 is compile + static review). First live session should confirm: `[MAGIC-AUTHORITY]` coverage lines, `[RISK-MINLOT]` clamped-to-3.0 line once at init, `[INIT] ... dailyRiskBudget=`, `[VOLUME-PROXY]` per symbol, `[STOPS REJECTED]` rare rather than constant, and no scalp position being closed by both authorities.
- Left open deliberately, by size of risk: engines still send outside `CTradeManager` (no fill verification / dedup / journal there); the ATR-scalp offset 7000 collides with `ASSET_FOREX` and grid's family config inherits profiler offsets, which corrupts cluster and per-symbol attribution *if* those dormant engines are ever wired; walk-forward validation (Batch 167) is not wired into live gating, so no strategy in the live roster has an out-of-sample edge proof; `CSymbolHealthMonitor::IsHealthy`, `MonitorMarginHealth` and `CEquityCurveManager` are still written but unread; `IsHedgingAllowed` returns true without checking the account's margin mode.
