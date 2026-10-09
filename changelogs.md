# Changelog

All notable changes to the `metatrader-multistrategy-ea` project are documented in this file.

This file starts at **Batch 170**. The previous history is preserved unchanged:
- Batches 102–169 (2026-08 → 2026-10): [`docs/changelogs_batch102-169.md`](docs/changelogs_batch102-169.md)
- Batch 101 and earlier: [`docs/changelogs_old.md`](docs/changelogs_old.md)

## [Unreleased] - 2026-10-09

### Batch 171: Comment hygiene — 7,100 comment lines removed, no code touched

#### Context
Whole-line comments had grown to 19,496 across 340 MQL files - roughly one comment line for every six code lines. Most of it was decoration and restatement rather than information: MetaEditor's `//+---+ / //| Name | / //+---+` banners around declarations that name themselves, and long multi-line "why this fix exists" narratives that bury one constraint under a paragraph of history.

#### Changed
- **Mechanical pass (325 files).** Banner rule lines removed; `//| Label |` blocks unpadded to plain comments; labels that only restate the declaration below them (or the file's own name) removed; standalone one-line echoes of the next declaration removed. Echo detection requires the comment phrase to be contained in a single identifier, or every content word of the comment to be covered by that identifier's camel-case parts - so `// Calculate Accuracy Metrics` over `CalculateAccuracyMetrics()` goes, while `// Track per-regime performance` over an unrelated line stays. Legal/copyright lines and unterminated banner fragments were left alone.
- **Prose collapse (10 blocks, the loudest ones).** Multi-line fix-narratives in `TradeMgrPricing`, `TradeMgrPreflight`, `TradeManager`, `UnifiedRiskManager`, `ConsensusEngine`, `EAOrchestrator`, `MagicRange`, `StatisticalArbitrageStrategy` cut to the constraint alone: the unit bug keeps "SYMBOL_SPREAD is already points", loses the four-line post-mortem; the tier envelope keeps "tiers may lower authorised risk, never raise it"; the voter floor keeps why one lone voter was 100% consensus, in two lines.
- **Not swept:** 13 files carrying the operator's uncommitted work-in-progress (`AIModules/*`, `Core/AI/*`, `Core/Registry/*`, `Core/Strategy/*Adapter`, `TradeExecutor.mqh`, `MQHModelVisualizer.mq5`, `TrainingDataExporter.mq5`, `WalkForwardTesterEA.mq5`) and the Dashboard tree. The remaining ~12,000 comment lines are mostly file-level architecture notes and constraint comments that the rules say to keep; the `/* */` blocks and trailing comments were out of scope for the mechanical pass.

#### Verification
- **Executable content proven unchanged:** for every file in the diff, the sequence of non-comment lines was compared against `HEAD` and must match exactly - 335 MQL files compared, and the only 11 with any executable-line difference are the excluded WIP files, which differ for the operator's own reasons.
- Whole-line comments 19,496 → 12,384 (-36%).
- All 8 root programs recompiled **0 errors / 0 warnings** after the pass.

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
- **Two fake sizing steps removed.** `CandidateBuilder::ApplyVPINScaling` and `ApplyVolTargetScaling` were `return lotSize;` stubs ("Would use m_mathRegistry if available") under comments claiming they resized the lot, while the validator status report printed a `LastVPINMultiplier` no caller consumed. VPIN still vetoes signals; nothing now pretends it sizes.

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
