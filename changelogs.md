# Changelog

All notable changes to the `metatrader-multistrategy-ea` project are documented in this file.

This file starts at **Batch 170**. The previous history is preserved unchanged:
- Batches 102–169 (2026-08 → 2026-10): [`docs/changelogs_batch102-169.md`](docs/changelogs_batch102-169.md)
- Batch 101 and earlier: [`docs/changelogs_old.md`](docs/changelogs_old.md)

## [Unreleased] - 2026-10-23

### Batch 252: the win-rate weight scaler sat behind a gate that was always open, on a mirror nobody read

**Type:** dead-code sweep; one unreachable behaviour path found and deleted rather than revived.

`CConsensusWeightingConfig::UpdateStrategyWeights()` began with `if(healthMonitor != NULL) { ...; return; }`, and
`CEnterpriseStrategyManager`'s constructor calls `m_infra.AllocateHealthMonitor()` unconditionally, so the monitor exists
for every manager from the moment it is constructed. The branch was therefore always taken and the loop written underneath
it - "Performance-adaptive weight scaling using recent win rate ... intentionally conservative and bounded" - has never
run for any strategy in any build. What that loop would have done to live money is the reason it is deleted instead of
wired:

- it scaled from `GetStrategyOriginalWeight(i)`, and every row registers at `weight`, so the base was right;
- but `recentWinRate` is registered as `0.0` (`StrategyMgrRoster.mqh:239`) and only rewritten when a trade closes, so
  `scale = 0.75 + (0.0 - 0.50)` clamps to the **0.50 floor** - every registered row on every
  symbol would have been voted at half weight until its first closed trade;
- and for the five AI rows `recentWinRate` does not hold a win rate at all (`UpdateAIPerformanceMetrics` reuses it for
  model accuracy), so the same loop would have scaled AI votes by an accuracy number it mislabels a win rate.

A correct version needs a sample-count guard and a decision about who may halve a strategy's vote; that is trading
arithmetic, not cleanup, so it is not shipped here. Ask and it is a small, safe batch: gate on `recentTradeCount`, keep
AI rows out of it, and give it an input that defaults off.

Deleted with the unreachable loop: `SStrategyHealthEntry::currentWeight` and `::originalWeight` (written by
`UpdateAllStrategyWeights` and by the roster's `SetStrategyWeight` push, read by nothing outside the class),
`UpdateAllStrategyWeights` itself, `GetStrategyWeight` / `SetStrategyWeight` / `GetStrategyOriginalWeight` on the monitor,
the `weight` parameter of its `RegisterStrategy()`, and the roster's push into that mirror. The same mirror existed a
second time in the roster - `StrategyEntry::originalWeight`, written at registration and read only by that dead loop - so
it went too, with `CStrategyMgrRoster::GetStrategyOriginalWeight` and the manager forwarder above it.

Unchanged, deliberately: the AI profitability multiplier still runs with the same arithmetic and still prints
`[AI-WEIGHT-ADJUST]`; `StrategyEntry::weight` remains the one weight consensus reads, written by
`ApplyRawStrategyWeight` and `UpdateStrategyWeightByName`; and the health monitor keeps its real jobs - win rate, health
score, the automatic disable/re-enable behind `[Enterprise-Adaptation]`. The honest summary of what AI adaptation does now
is: it re-weights the five AI rows by their model profitability. Indicator rows are only ever parked or restored, never
re-weighted.

19 added / 87 deleted across five files. **Verification:** `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 600` read un-piped; eight programs, each with its own `Result:` line; 0 errors / 0 warnings (11.5 / 7.4 / 14.2 / 9.3 / 209.3 / 288.2 / 67.2 / 4.4 s); `OVERALL SUCCESS`; all eight `.ex5` newer than the sources and every synced copy byte-identical to the tree it compiled (`cmp` on all six edited headers); artifacts removed. The EA program measured 209.3 s against 169.8 s for the Batch 251 tree on a quieter machine, so these remain load-dominated numbers, not a compile-cost result. Not runtime-observed: newest journal 2026-09-23.

### Batch 251: the AI engine's query island had no entry point, and the weight mirrors below it had no reader

**Type:** dead-code sweep, behaviour-preserving by construction.

`CAIEngine` is owned by `CEAOrchestrator`, and only three of its methods are reachable from a program entry point:
`Initialize`, `ProcessAdaptation` (called at `EAOrchestrator.mqh:3043` and `:3451`) and `SetExternalAIEndpoint`.
`OnAIQuery` has no call in any `.mq5` or `.mqh`, and neither do the free `InitializeAIEngine` / `CleanupAIEngine` pair or
the `g_AIEngine` global that were the module's other way in - so everything below that entry point was a second copy of
the Batch 246/247 shape, in the AI domain this time.

- **Query island (24 unreachable methods; 26 deleted).** `OnAIQuery`, `ProcessPredictionQuery`, `ProcessSignalQuery`, `ProcessWeightsQuery`,
  `ProcessStateQuery`, `ProcessExplanationQuery`, `AI_ModifyWeights`, `AI_ExplainDecision`, `AI_AdaptiveMode`,
  `SynthesizeSignals`, `GenerateTradeExplanation`, `AssessRisk`, `ProvideFeedback`, `SetExternalLLMEnabled`,
  `IsExternalLLMEnabled`, `IsInitialized`, `IsAdaptiveModeActive`, `GetPredictionAccuracy`, `GetQueryCount`,
  `GetAdaptiveConfig`, `BuildQualifiedName`, `UpdatePredictionAccuracy`, `ApplyWeightModification`, and the
  single-manager `Initialize` overload. With them: `SAIQueryRequest`, `SAIQueryResponse`, `SAIWeightModification`,
  `SAIDecisionExplanation`, the eight unused forward declarations at the top of the file, and the `g_AIEngine` singleton.
- **Write-only state deleted with its last reader:** `m_queryCount`, `m_successfulQueries`, `m_pendingMods[20]`,
  `m_pendingModCount`, `m_recentDecisions[50]`, `m_decisionIndex`, `m_decisionCount`, `m_predictionAccuracy`,
  `m_totalPredictions`, `m_correctPredictions`, and `ProcessExpiredModifications`, whose counter had no writer.
- **Four `SAIAdaptiveConfig` fields the orchestrator kept assigning:** `learningRate`, `minConfidenceThreshold`,
  `useMarketRegimeAdaptation`, `useSentimentAdaptation`. The first two had readers only in the island; the last two had
  no reader in any build. What `EAOrchestrator.mqh:3748-3750` assigns is now exactly `enabled = true`,
  `adaptationInterval = 1` and `useExternalLLM = m_config.enableExternalLLM`; `usePerformanceAdaptation` is still the struct
  default `true` that `ProcessAdaptation` reads, so it is an unsettable constant like the margin ladder thresholds.
- **Two log lines retired, both of which could only ever have printed a constant.** The deinit summary `AIEngine shutdown
  - Queries: %d, Accuracy: %.2f%%` read `m_queryCount` (no writer outside `OnAIQuery`) and `m_predictionAccuracy`
  (constructed at 0.5, written only by `UpdatePredictionAccuracy` behind `ProvideFeedback`), so it was `Queries: 0,
  Accuracy: 50.00%` in every build. `[AI-ENGINE] Clearing accumulated modifications` is gone with the counter it tested.
  `[EXT-LLM] FEEDBACK` also has no printer; INIT, CONFIG, QUERY-*, REASONING*, STRATEGY-WEIGHTS, WEIGHT-APPLIED and
  SHUTDOWN remain, all fed by the live external-LLM path.
- **Dead adaptation, deleted rather than wired.** `AdaptToRegime` scaled the configured confidence threshold by the
  regime factor (0.9 trend / 1.1 range / 1.2 volatile), stored it in a local, iterated the managers with an empty body
  and returned - so the factors never applied to any strategy, including after Batch 201 published the regime value.
  `AdaptToPerformance`'s `< 0.4` disable / `> 0.6` re-enable pair tested the constant accuracy, and the live governance
  sweep (`EAOrchestrator.mqh:3106-3119`) is what actually parks and restores strategies. Both are deleted; wiring a
  regime-scaled AI threshold would be a new entry gate, which is an operator decision, not a cleanup.
- **Ensemble-confidence chain closed (task #107).** `StrategyEntry::avgConfidence` had one writer - registration setting
  it to `0` - and its only readers were `CStrategyStateReporter::GetEnsembleConfidence`, which the island called three
  times. Field, `CStrategyMgrRoster::GetStrategyAvgConfidence`, the manager forwarder and the reporter method are gone,
  so Batch 250's "recorded, not fixed" note resolves by removal instead of by inventing a running mean that would change
  a reported number.
- **Second weight mirror removed:** `CStrategyHealthMonitor`'s participation ladder. `UpdateParticipationScore` had no
  caller, the seven `m_participation*` thresholds were read only inside it, the seven `SetParticipation*` setters had no
  caller, `GetStrategyParticipationScore` had no caller, and `SStrategyHealthEntry::participationScore` therefore held
  the `1.0` it was registered with. The live `UpdateAllStrategyWeights` product went from
  `originalWeight * healthScore * participationScore` to `originalWeight * healthScore` - the same number, because the
  deleted factor was 1.0 and could not have become anything else.
- **Kept, with the reason:** `GetStrategyWeightsJSON` (manager, reporter) - `MaybeCaptureExternalReasoning` feeds it into
  the LLM prompt on a live path when `InpEnableExternalLLM` is on. `UpdateStrategyWeight` / `UpdateStrategyWeightByName`
  - `ApplyLLMReasoningToWeights` writes through them. `GetActiveStrategyCount` - the `[ENTERPRISE]` init line reads it.
- **Recorded here, closed by Batch 252:** `SStrategyHealthEntry::currentWeight` was written by two live paths
  (`UpdateAllStrategyWeights`, and `StrategyMgrRoster.mqh:275` through `SetStrategyWeight`) and read by
  `GetStrategyWeight`, which has no caller outside the class; `originalWeight` is seeded from the health monitor's own
  `RegisterStrategy(weight)` and read only by those same two. So the monitor keeps a weight store that feeds no vote -
  consensus weights live in the roster. Also unexamined here: `CConsensusWeightingConfig::UpdateStrategyWeights` returns
  inside the `healthMonitor != NULL` branch, so the win-rate scaling loop below it may never have run for indicator
  strategies. Either resolution touches how a weight is chosen, so it gets its own batch.
- **Doc surface:** `AdaptToRegime` was cited as live behaviour in four places. README's Batch 201 entry, the
  `SYSTEM_STRUCTURE.md` regime bullet, `RUNTIME_DECISION_GRAPH.md`'s Batch 201 edge and `SYSTEM_AUDIT_TRACE.md`'s Batch
  201 trace all said the regime made AI entries more permissive in a trend; §6's `[MARKET-REGIME]` bullet said
  "adaptation stays off" when `valid=false`. Those claims are corrected in place, the two impossible `AIEngine.mqh:NNN`
  pointers in the Batch 201 trace are re-anchored by name, and 12 further pointers moved with the per-file line deltas.

- **File sizes:** `AIEngine.mqh` 1095 -> 404, `StrategyHealthMonitor.mqh` 454 -> 383,
  `StrategyStateReporter.mqh` 254 -> 230, `EnterpriseStrategyManager.mqh` 1173 -> 1165,
  `StrategyMgrRoster.mqh` 302 -> 299, `EntStrategyTypes.mqh` 142 -> 141. 9 added / 810 deleted across seven files.

**Verification:** `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 600` read un-piped; eight programs, each with its own `Result:` line; 0 errors / 0 warnings (26.8 / 8.9 / 21.4 / 28.7 / 308.3 / 316.1 / 80.7 / 5.7 s); harness exit 0; all eight `.ex5` newer than the sources (14:43-14:56 against a 14:36 source edit); artifacts removed. Load caveat: the same tree measured 169.8 s for the EA program eleven minutes earlier, and every program roughly doubled on this pass, so these are machine-load numbers, not a compile-cost result for this batch. Not runtime-observed: newest journal 2026-09-23.

### Batch 250: the manager stopped reporting to nobody, and the state only its reports read went too

**Type:** dead-code sweep, behaviour-preserving by construction.

Batch 247 deleted the orchestrator status chain. `CEnterpriseStrategyManager` / `CStrategyStateReporter` kept the surface
that chain was fed from, and a level of write-only state below that.

- **Reporting chains (9).** `GetStrategyReport`, `GetStrategyListJSON`, `GetConsensusContextJSON`,
  `GetActiveBrainStrategyCount`, `GetRegisteredStrategyWeight`, `GetRegisteredStrategyRole`,
  `GetRegisteredStrategyCluster`, `IsRegisteredStrategyLiveVotingEnabled`, and the manager's
  `ConsensusDecisionClassToString` forwarder. Each was declared in the manager, defined as a one-line forward into the
  reporter, and had no occurrence outside those two files. The reporter's static is kept: `PostConsensusValidator.mqh:150`
  and `:156` call `CStrategyStateReporter::ConsensusDecisionClassToString` directly.
- **By-name governance chains (5).** `SetStrategyRoleByName`, `SetStrategyClusterByName`,
  `SetStrategyLiveVotingEligibilityByName`, `SetStrategyGovernanceByName`, `SetStrategyConfidenceThresholdByName` -
  forwarded by the manager, implemented in `CStrategyRegistryState` / `CStrategyMgrRoster`, never called. The live write
  path is positional, exactly as Batch 232 recorded for the intrabar pair.
- **By-name enable/disable (2).** `EnableStrategy` / `DisableStrategy` and their `CStrategyLifecycle` bodies. Those two
  bodies were the only printers of `[EnterpriseStrategyManager] Strategy ENABLED:` / `... DISABLED:`, so neither line has
  ever existed in a journal. The automatic path is untouched: `CStrategyHealthMonitor` disables and re-enables through
  `CheckStrategyDisabling` / `CheckStrategyReEnabling`, driven from `EAOrchestrator.mqh:3115-3116`, printing
  `[Enterprise-Adaptation]`.
- **Participation-formula setters (4 x 2 owners).** The four values are read live by `ConsensusEngine.mqh:276-279` and
  have never had a writer, so they are constructor constants: base 0.40, coeff 0.65, min 0.55, max 1.05.
- **Funnel counters.** `m_totalSignals` (written at the attribution site, read only by the deleted report),
  `m_successfulSignals` (written on every profitable close, same reader), `m_avgConfidence` (no writer). Deleted with
  their getters, their increments, both manager forwarders and the two write sites.
- **Also:** `IsStrategyLiveVoter` / `GetStrategyIsLiveVoter` on both owners (the consensus engine's own copy is live), and
  six manager forwarders whose only reader was a deleted report - `ApplyFamilyEngineWeights`, `CalculateRecentWinRate`,
  `CalculateSharpeRatio`, `CalculateStrategyMetrics`, `UpdateRecentPerformance`, `IsPositionIdStillOpen`. Each shadows a
  live method the owning satellite calls by name, which is why a name-level grep reported them as used.
- **Recorded, not fixed:** `StrategyEntry::avgConfidence` has no writer, so
  `CStrategyStateReporter::GetEnsembleConfidence()` has returned 0.0 for its whole life. Its readers sit behind
  `CAIEngine::OnAIQuery`, which has no caller - that query island (`ProcessPredictionQuery` / `ProcessSignalQuery` /
  `ProcessWeightsQuery` / `ProcessStateQuery` / `ProcessExplanationQuery`) is the next batch, and a real running mean for
  the field is a behaviour change that gets its own.
- **Doc surface:** 26 pointers re-pointed by the per-file line deltas, then 2 re-anchored by content - a
  `StrategyMgrRoster.mqh` citation that was already ~20 lines off, and a Batch 236 range that straddled
  `GetStrategyReport`'s forwarder and `SetPipelineFilters`' comment while claiming to verify the flag builder; it now
  cites `OrchestratorStrategyFlagBuilder.mqh:62-66`, which is what it described.
- **File sizes:** `EnterpriseStrategyManager.mqh` 1356 -> 1173, `StrategyStateReporter.mqh` 412 -> 254,
  `StrategyRegistryState.mqh` 246 -> 152, `StrategyLifecycle.mqh` 206 -> 164, `EntStrategyQuorumConfig.mqh` 207 -> 186,
  `StrategyMgrRoster.mqh` 320 -> 302, `EntStrategySignalContext.mqh` 152 -> 140. 560 deleted / 29 added across twelve files.

**Verification:** `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 600` read un-piped; eight programs, each with its
own `Result:` line; 0 errors / 0 warnings (4.6 / 2.0 / 4.1 / 3.8 / 90.0 / 146.5 / 66.4 / 3.6 s); harness exit 0; all eight
`.ex5` newer than the sources; artifacts removed. Not runtime-observed: newest journal 2026-09-23.

### Batch 249: the two timeframe inputs now choose the timeframe a strategy reads

**Type:** wiring + dead-field removal, with one deliberate behaviour change.

Batch 234 recorded that `InpMomentumScalpTimeframe` and `InpCandlestickIntrabarTimeframe` land only in a per-strategy
timeframe table whose getter chain has no caller, so every strategy registered on `PERIOD_CURRENT` -> the manager's
`m_baseTimeframe` and the two inputs priced nothing. This batch binds that table and deletes what could never be part of
the decision.

- **The road was already built.** `CStrategyRegistryState::RegisterStrategy` resolves `resolvedTf` at `:90` and passes it
  to `strategy.Init(...)` and `InitializeAI(...)`; `StrategyEntry::timeframe` is read by `ConsensusEngine.mqh:524`
  (pipeline signal processing), `StrategyLifecycle.mqh:196` (`OnNewBar`) and `EnterpriseStrategyManager.mqh:1264`
  (regime update). So the fix is one argument at `AutoRegisterStrategies` plus the per-slot push, not a new mechanism.
- **Precedence:** a row overrides the catalog `timeframe` only when it names one. Slots 0 (Momentum) and 4 (Candlestick)
  are the only rows that name a timeframe, so those two strategies are the entire delta; 19 rows keep `PERIOD_CURRENT`.
- **What that unlocks:** `SimpleMomentumStrategy.mqh:513` clears `m_enableScalping` when its timeframe leaves M1-M15, so
  with the chart above M15 the shipped `InpEnableMomentumScalping = true` had never applied. Registering on `PERIOD_M5`
  keeps scalping, which lets Momentum re-signal every `InpMomentumScalpCooldownSeconds` (20 s) rather than once per chart
  bar. Cadence, not exposure: two-voter quorum, quality/support floors, `CUnifiedRiskManager`,
  `InpMaxTradeSendsPerCycle`, `InpMaxPositionsTotal` and `InpMaxRiskPerTrade = 1.0` are untouched, and the reversal-exit
  check reads the same manager so exits see the faster bar too.
- **Deleted:** `SStrategyTimeframeConfig` as a type; its `name`, `intrabarTF` and `forceHigherOnM1Synthetic` fields
  (21 writers, zero readers each). `forceHigherOnM1Synthetic` restated the band rule Momentum already enforces - wiring it
  would have made two holders of one rule. `COrchestratorIntrabarPolicy::GetStrategyTimeframeConfig`, its
  `EAOrchestrator.mqh` wrapper, and `SStrategyIntrabarConfig::name` (20 writes, no reader).
- **Added:** `ENUM_TIMEFRAMES strategyTimeframes[MAX_STRATEGY_CONFIGS]` in config, `CIntrabarPolicy`'s
  `m_timeframeConfig` + setter/getter, `CEnterpriseStrategyManager::SetStrategyTimeframeConfig`, and the push in the
  loop that already sets the intrabar policy.
- **Log surface:** `[ENTERPRISE]` loses `(stored,unconsulted)` and prints
  `baseTF=chart(<TF>) | tfOverride Momentum=<TF|inherit> Candlestick=<TF|inherit>`. `AGENTS.md` section 6 rewritten to
  match. `[CONFIG] Initialized 23 strategy timeframe/intrabar configs` is unchanged (`strategyConfigCount` still counts
  the array).
- **Docs:** 39 pointers re-pointed by the +3/+6/+1 region deltas, then 2 re-anchored by content (`:1987` had drifted onto
  a blank line; the setter call is `:1947`); a Batch 234 citation to the now-deleted wrapper is number-free.
  `StrategyConfigBuilder.mqh` 199 -> 53 lines.
- **Reversibility:** setting `InpMomentumScalpTimeframe` to the chart timeframe prints `inherit` and moves nothing.

**Verification:** `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 600` read un-piped; eight programs, each with its
own `Result:` line; 0 errors / 0 warnings (6.6 / 3.3 / 5.1 / 7.0 / 143.0 / 149.3 / 79.7 / 3.4 s); harness exit 0; all
eight `.ex5` newer than the sources; artifacts removed. Not runtime-observed: newest journal 2026-09-23.

### Batch 248: the audit trace's "Current Runtime Evidence" was a dated archive, and four of its scope rows named files that are not in the tree

No code changed in this batch, so no compile was run. Verification is an existence scan: every `*.mqh`/`*.mq5` path and
every `Inp*` name cited in the five current-state documents was tested against the tree and the root EAs' input lists.
Findings and fixes:
- `SYSTEM_AUDIT_TRACE.md`'s section titled **"Current Runtime Evidence"** contained dated Batch 102-158 records, nothing
  else. Renamed to **"Dated Audit Records (Batches 102-158)"** with a line saying current-state truth lives in
  `SYSTEM_STRUCTURE.md`, `RUNTIME_DECISION_GRAPH.md` and AGENTS.md §6. The stale names inside those records are left as
  written - that is what §8 means by a dated record - but a reader who trusted the heading had no way to know.
- Its **Scope** rows named three paths that cannot resolve: `Core/Processing/SymbolScanScheduler.mqh` (deleted Batch 215,
  never instantiated), `Core/Registry/SymbolStateTracker.mqh` (deleted Batch 215), and
  `Core/Registry/StrategyRegistry.mqh` - the roster file is `Core/Strategy/StrategyRegistry.mqh` and the Registry path has
  never existed. `Core/Orchestration/SignalValidator.mqh` was already a merged-away name; the row now points at
  `Core/Management/PostConsensusValidator.mqh`. Deleted rows use the file's existing strikethrough-plus-reason convention.
- Ten duplicate bullet lines in the same list (`TradeExecutor`, `LiveAuthorityResolver`, five registries,
  `SymbolStateTracker` repeated) collapsed to the single unique entry they duplicated.
- `RUNTIME_DECISION_GRAPH.md`'s Ownership Map had the same `SignalValidator.mqh` claim; corrected to the live owner.
- `README.md` Quick Start told the operator to copy `IndicatorManager.mq5`. The file is `IndicatorManager.mqh`; the EA
  would have compiled with a missing include on a fresh install.
- Document metadata bumped in `SYSTEM_AUDIT_TRACE.md`, `RUNTIME_DECISION_GRAPH.md` and `SYSTEM_STRUCTURE.md`
  (Last Updated / Last Architecture Sync 2026-10-21, Current Batch 247 - all three still said 170 and 2026-10-09).

### Batch 247: the status-report chain had no entry point, so the whole of it goes

Batch 246 found the entry point dead - `CEAOrchestrator::GetStatusReport()` has no call in any `.mq5` or `.mqh` - and
deleted the position side of the chain. This one deletes the rest: `Core/Orchestration/OrchestratorStatusReporter.mqh`
(114 lines) with its orchestrator member, `SetManagers` call and the `ClearEnterpriseManager()` call that existed only to
keep that class's borrowed enterprise-manager pointer from outliving the object, plus eight collaborator reports that
answered to it: `CLiveAuthorityResolver`, `CTradeExecutor`, `CCandidateBuilder`, `CPostConsensusValidator` (and the
`CEnterpriseStrategyManager` forwarder that only delegated to it), and the five engine registries.

Two of those deletions correct a documented falsehood rather than just removing code:
- `README.md`'s Batch 172 bullet and `SYSTEM_STRUCTURE.md`'s LiveAuthorityResolver row both say the
  `[LiveAuthorityResolver]` status block *prints* `pf=` / `eligible=` per tracked AI strategy, and that this makes the
  promotion gate's arming observable. It could never print. The observable surfaces are `[AUTHORITY-CONFIG]` at init and
  `[AUTHORITY-REJECT]` / `[AUTHORITY-REDUCED]` per decision, and both rows now name those.
- `CHeartbeatTelemetry`'s eighteen getters had zero callers each - `Emit()` hands the counters to
  `CDiagnosticsManager::UpdateCounters` positionally and that is what builds `[HEARTBEAT]`. Three of the eighteen were
  read by the reporter, so §8's chain test was already being met through a dead link.

Write-only state this uncovered, deleted with its last reader: `CTradeExecutor`'s `m_totalSubmitted` / `m_totalConfirmed`
/ `m_totalRejected` / `m_totalTimeout` and their four `++` sites (the events still print individually via
`[EXECUTION-TIMEOUT]` / `[EXECUTION-CONFIRMED-BY-POSITION]`, and `[CANDIDATE-BUILDER]` authority refusals read the ledger
that stays); `CCandidateBuilder::GetAuthorityBlockedTotal`; `CNeuralNetRegistry::GetActiveCount`;
`CDrawingManagerRegistry::GetTotalObjectCount`; and `CPostConsensusValidator::m_lastVPINMultiplier`, a field its own
comment labelled "diagnostic mirror", written in three branches and read by the deleted validator report alone.

Engine presence per symbol remains visible through `[WIRE-STATUS]`, which is on a live init path - that is why the
registry reports were duplicates rather than the only evidence.

Measurable effect beyond line count: 6 added / 378 deleted across fifteen files, and the compile stops parsing eight heavy
headers through an aggregator nobody calls. `MultiStrategyAutonomousEA.mq5` measured 48.0 s against 129.3 s (Batch 246)
and 247.7 s (Batch 245); `MultiStrategyTestingEA.mq5` 60.3 s; `TrainingDataExporter.mq5` 20.2 s.

Deliberately not shipped as a replacement: a re-wired status line. Printing one is a feature choice (which numbers, init
or deinit, journal or chart comment), and the deleted chain answers no such ask. Asked and it is a dozen lines.

Docs: `README.md`, `SYSTEM_STRUCTURE.md` (the ScanSchedulerRegistry row, the LiveAuthorityResolver responsibility row),
`RUNTIME_DECISION_GRAPH.md`, AGENTS metadata. Pointer hygiene: 99 `EAOrchestrator.mqh`/
`ConsensusEngine.mqh`/`EnterpriseStrategyManager.mqh`/`PostConsensusValidator.mqh`/`TradeExecutor.mqh` citations moved by
these deletions and re-pointed across the five current-state docs, then two `PostConsensusValidator.mqh` ATR rows
re-anchored by content (`:258` crisis comparison, `:270` the 1.5 band) because they had drifted to a comment line and a
neighbouring branch, and `PositionManager.mqh`'s header pointer to `TradeExecutor.mqh:301`.

### Batch 246: four satellites and a status report nobody has ever printed

Batch 245 kept four small classes alive for one reason - `CPositionManager::GetStatusReport()` read them. Following that
reason to its end is what deleted them: the report's only reader is `COrchestratorStatusReporter::GetStatusReport()`, whose
only reader is `CEAOrchestrator::GetStatusReport()` (`EAOrchestrator.mqh:3682`), and **that method has no call anywhere in
the `.mq5` or `.mqh` tree**. So `[PositionManager] Enabled=Y | Pyramid=N | DynamicSL=N | LossMin=N | SRE=N | ConsecLoss=0 |
DailyLoss=0.00 | PyramidStates=0 | VolRegimes=0` could never reach a journal, a `Comment()` or a file, in any build. The
same is true of the seven other sections that reporter assembles (`CLiveAuthorityResolver`, the enterprise manager's
validator block, five engine registries) and of `CTradeExecutor::GetStatusReport()`, which has no reader at all. §8's
"a 'this is live' claim needs a caller chain to an entry point, not a reader" is exactly this mistake one level up, and
Batch 245's own note named `OrchestratorStatusReporter.mqh:119` as a live consumer because it is a call site.

Deleted: `PositionMgrSRE.mqh`, `PositionMgrPyramid.mqh`, `PositionMgrDynamicSL.mqh` (488 lines - after 245 their behaviour
was gone and only `IsEnabled()`/`GetStateCount()`/`GetRegimeCount()` remained, answering a string nobody printed);
`PositionMgrLossGuard.mqh` (170 lines, and with it `ManageLossMinimization()`, which carried a second
`ClosePosition(ticket, "Position Loss Limit")` beside the lifecycle guard's live one - a latent third exit authority,
unreachable rather than harmless); `CPositionManager::GetStatusReport()`, `RecordClosedTrade()` and `m_enabled`;
`CPositionManager`'s four now-unneeded includes (SRE/Pyramid/DynamicSL/LossGuard plus MagicFilter, whose one remaining
caller, `BasketEquityStop.mqh:103`, includes it directly); `CPositionMgrStateStore::GetPositionStateByIndex()` and the
private forwarder that no caller could reach; the reporter's `Init`/`IsWired` pair, its borrowed `CPositionManager*` and
the `SetManagers` argument that filled it; and `EAOrchestrator.mqh`'s `m_positionManager.RecordClosedTrade(netProfit)`.

Kept, with the reason: `CPerformanceAnalytics::RecordClosedTrade` is the closed-trade feed that
actually has consumers - win rate, profit factor, momentum lot scaling, the `[AUTHORITY-LEARN]` outcome path - so the
duplicate consecutive-loss tally in the position class went and the real one stayed. `PositionMgrMagicFilter.mqh` stays for
the same reason as in 245. Nothing about an entry, exit, stop, lot or risk ceiling moved.

Refactor while here: `PositionMgrStateStore.mqh` held three copies of "evict the oldest slot when the registry is full,
then append" (in `UpsertPositionPredictionId`, `UpsertPositionAIPrediction`, `RegisterPositionState`) and two identical
copies of "shift down and shrink" (in the two `Remove...` methods). Those are `AcquireSlot()` and `EraseAt()` now, and the
new slot is default-constructed rather than `ZeroMemory`-cleared plus a struct copy, so an added field with a non-zero
default can no longer be quietly zeroed on append. `TRADE_SIGNAL_NONE` is `0` and `ORDER_TYPE_BUY` is `0`, so the shipped
arithmetic is unchanged; the registry is 202 lines instead of 262 and `PositionManager.mqh` is 119 instead of 186.

Docs corrected against this finding: `RUNTIME_DECISION_GRAPH.md`'s "Documented unwired (product decision pending)" bullet
claimed `CEnterpriseStrategyManager::OnTradeTransaction` and `CPerformanceAnalytics::RecordClosedTrade` had no call sites -
Batch 154 wired the fan-out (`EAOrchestrator.mqh:3359`) and 199 the attribution, so the bullet now says what runs - and
`SYSTEM_AUDIT_TRACE.md`'s component row for PositionManager named the deleted tally. Three stale pointers found by
re-anchoring rather than shifting: the candidate-builder config call is `:1488` not `:1522`, the indicator-count test is
`:1601` not `:1594`, and safe-mode `minConfidence` reaches an entry decision at `:1827` not `:1751`. 44 `EAOrchestrator.mqh`
pointers moved by the two deletions and were re-pointed across the five current-state docs.

Next step, stated rather than left implicit: the rest of that report chain is unreachable for the same reason and gets
deleted in Batch 247, which will also decide whether the operator wants a status line at all - printing one is a feature
choice, not a cleanup.

### Batch 245: `CPositionManager` stops claiming to be the exit authority, and 229 lines of it go

Batch 243 proved by caller chain that this class's exit surface had no caller; this batch deletes it. Seventeen methods went:
`ManagePositions`, `CheckSignalReversalExit`, `ManageBreakevenAndTrailing`, `ManagePyramiding`, `ManageDynamicSLTP`,
`ManageLossMinimization`, `ManagePartialProfitTaking`, the six `Configure*` (SRE, Lifecycle, Pyramiding, DynamicSL,
LossMinimization, PartialProfitTaking), `SetDailyRiskBudget`, the `IsEAOwnedMagic` forwarder and the `SafeDelete` template
helper. Every one of those names exists on `CPositionLifecycleManager` too, which is why a name-level grep says "live": the
only calls on *this owner* are `RegisterPositionState` (`TradeExecutor.mqh:312`), `RecordClosedTrade`
(`EAOrchestrator.mqh`), `GetStatusReport` (`OrchestratorStatusReporter.mqh:119`), `GetPositionStateCount`
(`TradeAttributionManager.mqh:606`) and the nine prediction-map accessors (`:276-324`). Those are what the class is now.

**`Initialize` went with them, because keeping it would have re-created the defect this file just reported.** Once the exit
methods were gone, `m_tradeManager`, `m_regimeEngine`, `m_riskTierManager`, `m_safeMode` and `m_magicNumber` were written by
`Initialize` and read by nothing - Batch 243's write-only-collaborator shape again, this time produced by my own deletion. So
the parameters went too, the constructor collapsed to `m_enabled(true)`, and the fourteen config fields (`m_breakevenBufferPts`,
`m_trailingDistancePts`, `m_trailingStepPoints`, `m_useATRTrailing`, `m_atrMultiplier`, `m_lastManageTimeMs`,
`m_partialProfitTakingEnabled`, `m_partialProfitATRMultiplier`, `m_partialProfitPercent` and the four pointers plus
`m_magicNumber`) left with their readers. `m_enabled` stays on purpose: `GetStatusReport` prints it, and the comment now says
the one setter that could write it (`ConfigureLifecycle`) never had a caller, so it has read `true` for the whole life of the
class. `[INIT] PositionManager initialized` became `[INIT] PositionManager registry ready | position-state + prediction maps,
no exit authority`, and `[CRITICAL] PositionManager initialization FAILED` has no printer now: nothing cited it, and its
branch was unreachable because the call passed `&m_tradeManager` and `&m_riskTierManager` - both never `NULL`.

**The trap that nearly cost a live file.** `PositionMgrMagicFilter.mqh` looked like residue of the deleted magic-number
forwarder, but `BasketEquityStop.mqh:103` calls `CPositionMgrMagicFilter::IsEAOwnedMagic` on a live path, so that file stays.
The four satellites `GetStatusReport` still reads (`CPositionMgrSRE/Pyramid/DynamicSL/LossGuard`) are held back for the same
reason in reverse: deleting them means rewriting a report an operator can see, and five of its nine fields are constants
today (`Pyramid=N | DynamicSL=N | LossMin=N | SRE=N | PyramidStates=0 | VolRegimes=0` - their writers were in the block this
batch deleted). That is the next step, with the report change stated when it happens.

The file's own header said "SINGLE AUTHORITY for all position lifecycle management / Replaces:
TradeManager::ManageAllPositions + PositionLifecycleManager ... The public API of CPositionManager is UNCHANGED". All three
clauses were false before this batch and the third became false in 2022's decomposition; it now names what the class
actually holds.

13 added / 237 deleted across two files (`Core/Position/PositionManager.mqh` 405 -> 186 lines,
`Core/Orchestration/EAOrchestrator.mqh`).

Verification: the first run came back **6 errors** - one line of my replacement comment lost its `//` prefix and MQL5 parsed
prose as code (`error 154: 'the' - semicolon expected`), which is what the eight-program harness is for; fixed and re-run.
`sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 600` read un-piped, eight programs each with its own `Result:` line,
0 errors / 0 warnings (18.5 / 5.6 / 9.9 / 18.1 / 247.7 / 154.5 / 57.3 / 3.8 s), harness exit 0, all eight `.ex5` newer than the sources. Not runtime-observed: newest journal
2026-09-23.


### Batch 244: the loss guard has been closing positions on its constructor's numbers, and now the dialog owns them

`[LOSS-MIN] Position loss limit exit` has been a live line since the first build, and nothing in the program could set the
threshold behind it. `CPositionLifecycleManager::ManagePositions()` gates the guard on
`m_lossGuard.IsAdverseMomentumExitEnabled() || m_lossGuard.GetConsecutiveLossLimit() > 0`; the left term has no writer, the
right term comes from `CPosLifecycleLossGuard()`'s `m_consecutiveLossLimit(3)` (`PosLifecycleLossGuard.mqh:40`), so the guard
ran every lifecycle pass while `ConfigureLossMinimization` (`PositionLifecycleManager.mqh:163`) had zero callers and no input
in either root EA named any of it. What that did with money, on numbers nobody chose: any lifecycle-managed position whose
price moved **75% of its own SL distance** against it while in loss was closed early; three such closes set
`m_consecutiveLossCooldownSec = 1800` and paused the whole guard; the daily breaker was armed because
`EAOrchestrator.mqh:1019` already feeds `SetDailyRiskBudgetPercent(m_config.maxDailyRisk)`, so 50% of the daily budget in
guard-realized losses stopped this path for the day. `m_adverseMomentumATRMultiplier = 0.5` sat behind a flag that could not
turn on, so `[LOSS-MIN] Adverse momentum exit` remained unprintable.

**What ships.** Six inputs in both root EAs -> six `SOrchestratorConfig` fields -> `ConfigureLossMinimization` called at init,
and `[LOSS-GUARD] adverseMomentum= | atrMult= | consecutiveLossLimit= | cooldown=s | dailyBreaker=% of the % budget |
positionLossLimit=% of own SL | armed=yes|no` printed once beside the existing `[INIT] ... dailyRiskBudget=` line. The six
defaults ARE the constructor's values (`false / 0.5 / 3 / 1800 / 50.0 / 75.0`), so a normal start closes exactly what it
closed before - what changed is that the numbers are answerable to the operator, that `armed=no` is reachable for the first
time (`limit 0` with the flag off puts the path to sleep), and that the init journal states the guard's real settings instead
of leaving them implicit in a class constructor. No threshold was retuned: 75/3/1800/50/0.5 stay, because moving a live exit
is a trading decision, and Batch 243's rule is that a limit may become settable without becoming different.

**The two messages that claimed more than the code did.** `[LOSS-MIN] Daily loss circuit breaker triggered ... | stopping
trading` follows a plain `return` from `ManageLossMinimization`, and entries are gated by `CRiskCircuitBreaker` and the risk
pipeline, not here - the line now reads `| action=guard-exits-skipped-for-day(entries are gated by CRiskCircuitBreaker and
the risk pipeline, not here)`. The cooldown line gained `| action=guard-exits-skipped`, and the comment above the `return`
said "Skip trading during cooldown", naming an action this path does not take. `m_dailyLossAmount` grows only inside the two
exit branches, so the "daily loss" this breaker measures is the guard's own closes; the message field is now `guardLoss=`
for exactly that reason.

**Left off deliberately, with the reason.** Pyramiding, volatility-scaled SL/TP and partial profit taking keep their
constructor `false` and their uncalled setters. Giving them inputs would add position layers, moved stops and partial closes
that no operator has asked for, which is a feature launch rather than a wiring fix; the gate expression, the setter line and
the fact that they are off are now written down in `SYSTEM_STRUCTURE.md` §4 and `README.md`, so nobody has to re-derive it.
The never-called exit half of `CPositionManager` and the satellites only it holds stay queued too.

62 added / 3 deleted across five files (`Core/Orchestration/OrchestratorConfig.mqh`, `Core/Orchestration/EAOrchestrator.mqh`,
`Core/Management/PosLifecycleLossGuard.mqh`, `MultiStrategyAutonomousEA.mq5`, `MultiStrategyTestingEA.mq5`).

Verification: `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 600` read un-piped, eight programs each with its own
`Result:` line, 0 errors / 0 warnings (8.4 / 3.9 / 7.4 / 7.3 / 110.7 / 113.9 / 37.3 / 3.2 s), harness exit 0, all eight `.ex5` newer than the sources. Not runtime-observed: newest
journal 2026-09-23, so `[LOSS-GUARD]` has not been seen in a journal yet; on the first live start it must appear, and its
`armed=` field is the answer to whether this path is running.


### Batch 243: two collaborators `CPositionManager` was handed but never consulted, and three getters no caller could reach

`CPositionManager` stored a `CFullMarginMode*` and a `CIntelligentSLGuard*` (`PositionManager.mqh:38/39`), initialised both
to `NULL`, wrote them from `Initialize`'s sixth and seventh parameters, and read them nowhere in the tree. The single call
site passed `&m_fullMarginMode` and a literal `NULL`, so the SL-guard field could only ever have held `NULL` while the margin
object it did receive was never asked for anything. The live `CFullMarginMode` is the orchestrator's own member: initialized
at `EAOrchestrator.mqh:970`, handed to `CDiagnosticsManager::SetFullMarginMode` at `:1027`, and read there at
`DiagnosticsManager.mqh:353`. One holder, one reader - what went was a second pointer that could not speak. `Initialize`
takes five parameters now, and `#include "../Risk/FullMarginMode.mqh"` went with the members: no file under `Core/Position/`
names `CFullMarginMode` or `SFullMargin*` after this, `DiagnosticsManager.mqh:17` and `EAOrchestrator.mqh:26` include it
themselves, and `OrchestratorFwd.mqh` only forward-declares. The eight-program compile is the proof.

`CRiskCircuitBreaker::GetTriggeredAt`, `GetRecoveryAttempts` and `GetRecoveryLevel` were declared, defined, and had zero call
sites repo-wide. The state they exposed is not gone: `m_cbTriggeredAt`, `m_cbRecoveryAttempts` and `m_cbRecoveryLevel` are
written and tested inside the breaker's own recovery ladder (the daily roll at `:86-89`, the stable-window release at
`:176-184`, the level-2/level-1 ramps at `:289-317`), which is what the `[RISK-CIRCUIT-BREAKER]` prints read. Their three
neighbours - `GetPeakEquity`, `GetMaxDrawdownFromPeak`, `GetDrawdownBreachCount` - have 12, 13 and 4 external callers and
stay; `GetMaxDrawdownFromPeak` is the quantity Batch 226 made the asset-class ceiling name in its own message.

**The caller-chain test, applied to this class.** Every external occurrence of `ManagePositions`, `CheckSignalReversalExit`,
the five `Manage*` and the five `Configure*` resolves to `CPositionLifecycleManager` or its own satellites - the live
authority, configured at `EAOrchestrator.mqh:991/995/1000` and driven at `:3094`. On `CPositionManager` itself those methods
have no caller, as the file's own comment at `:3092` already said ("never configured ... it still owns the position-state
registry"). Registry stays: `TradeExecutor.mqh:312` registers position state through it and `TradeAttributionManager.mqh`
makes nine prediction-map calls on it. Deleting the dead exit half, with the four `PositionMgr*` satellites that only it holds,
is the next batch and is recorded as task #100 rather than folded into a hygiene pass.

**Doc defect found by the same sweep, and the live exit it under-describes.** `SYSTEM_STRUCTURE.md` §4's unsettable-arms row
listed three setters and cited `PositionLifecycleManager.mqh:158/163/168`. There are four (`:153/158/163/172`), `168` was the
loss-guard satellite's own line, and no input in either root EA names any of the four features. Three of the four gates then
read their satellite's constructor `false` and never run - pyramiding, volatility-scaled SL/TP, partial profit taking. The
fourth does not, and the row's phrasing hid that: its gate is
`IsAdverseMomentumExitEnabled() || GetConsecutiveLossLimit() > 0`, and `CPosLifecycleLossGuard()` initializes
`m_consecutiveLossLimit(3)` (`PosLifecycleLossGuard.mqh:40`), so the right-hand term is true from startup and
`ManageLossMinimization()` runs every lifecycle pass. What that means in money, with nobody able to set it:
`m_positionLossLimitPercent = 75.0` closes any managed position whose price has moved 75% of its own SL distance against it
while in loss (`[LOSS-MIN] Position loss limit exit`), three such closes set a 1800 s cooldown on the whole path, and
`m_dailyLossCircuitBreakerPercent = 50.0` is armed because `EAOrchestrator.mqh:1006` feeds
`SetDailyRiskBudgetPercent(m_config.maxDailyRisk)`. Only `m_adverseMomentumExitEnabled` is genuinely off, so
`[LOSS-MIN] Adverse momentum exit` cannot print. Two further truths the same reading exposes: `m_dailyLossAmount` grows only
inside those two exit branches, so the "daily loss" the breaker measures is this path's closes and not the account's; and its
message ends `| stopping trading` while the code only `return`s from `ManageLossMinimization` - entries are gated elsewhere,
by `CRiskCircuitBreaker` and the risk pipeline, not here. That is a live unconfigured exit plus a message that overstates
itself, both of which change outcomes if touched, so they are recorded as the next batch's decision rather than adjusted
beside a set of deletions. The row now says what the four gates actually do.

4 added / 25 deleted across three files (`Core/Position/PositionManager.mqh`, `Core/Risk/RiskCircuitBreaker.mqh`,
`Core/Orchestration/EAOrchestrator.mqh`). No lot, stop, gate or exit moved: the deleted members had no reader and the deleted
getters had no caller.

Verification: `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 600`, eight programs each with its own `Result:` line,
0 errors / 0 warnings, harness exit 0 read un-piped, all eight `.ex5` newer than the sources. Not runtime-observed: newest
journal 2026-09-23.


### Batch 242: `live_overrides.json` was read, announced and applied by nobody

`Config/live_overrides.json` is documented in this repository as the canonical runtime risk source - "loaded live every
30 s", and Phase-0's recalibration was mirrored into it precisely so a running EA would pick it up. It has never applied
a value, in three independent ways, each of which alone was enough:

1. **The file could not be opened.** `Init` built `TerminalInfoString(TERMINAL_DATA_PATH) + "\MQL5\Files\" + path` and
   passed that absolute path to `FileOpen`, which does not accept one: paths resolve inside the sandbox, and only
   `FILE_COMMON` relaxes that. So `GetFileWriteTime` returned 0 and `ReadFileToString` returned "".
2. **Nothing could even try.** `CheckAndReload` compared `currentModified <= m_lastModified`, and with both at 0 that is
   `0 <= 0` - true. It returned before the read, so no `[LIVE-CONFIG] ERROR: Failed to read config file` ever printed
   either. The channel was not failing loudly; it was silent, which reads as "the file has not changed".
3. **The callbacks had nothing to apply.** The four registered `IConfigCallback`s - `CRiskConfigCallback`,
   `CWeightsConfigCallback`, `CThresholdsConfigCallback`, `CSymbolsConfigCallback`, declared inside
   `InitializeSubsystems` - printed `[LIVE-CONFIG] <section> section reloaded` and discarded the JSON they were handed.
   A class declared inside a method cannot reach the enclosing object in MQL5, so no callback at that seam could ever
   have applied a value: the stubs were not a half-finished wiring, they were an impossible one. The `ai` and `engines`
   sections had no callback at all.

**What ships instead.** The reloader now detects the change and hands it to its owner: the path passed to `FileOpen` is
the relative form the operator wrote (absolute kept only for the log line), the 30 s throttle runs on
`GetTickCount()` because `TimeCurrent()` advances only with ticks and a quiet market is exactly when someone reaches for
this file, and an unreadable file says so once - `[LIVE-CONFIG] file not readable | path= | live overrides inactive`.
`ConsumeReloaded()` returns true once per detected content change and `CEAOrchestrator::ApplyLiveConfigOverrides` applies
the `risk` section through `UpdateRiskParametersFromInputs`, the route Batch 241 made real. Every key is read with the
*running value* as its default, so a file that omits a key cannot zero a ceiling it never mentions. The applied pairs
print as `[LIVE-CONFIG-RISK] perTrade=a->b | daily=a->b | portfolio=a->b | maxDD=a->b | dailyLoss=a->b | roundUp=a->b |
cap=a->b | compounding=a->b | tier=a->b`, and the sections with no consumer announce themselves on every reload rather
than implying one: `[LIVE-CONFIG] weights/thresholds/symbols/ai/engines | applied=no(report-only sections, no consumer
reads them)`. An operator who just edited a weight has to be told it did not land, or the reload reads as a success.

**The manual reset the breaker keeps asking for.** `[RISK-CIRCUIT-BREAKER] Max recovery attempts reached (3/3) | Manual
reset required` prints every five minutes, and `ResetCircuitBreaker()` - declared, defined, forwarded - had zero callers,
so the promised action did not exist anywhere in the runtime. `risk.resetCircuitBreaker` in the override file is now that
action: it re-arms trading, clears conservative mode and re-baselines the peak exactly as the method says, and prints
`[RISK-CIRCUIT-BREAKER] manual reset via live config | equity= re-baselined as peak | trading re-armed`. It is
edge-triggered on a false->true transition, so a file left at `true` cannot re-arm trading when the operator edits
something else. Two automatic releases of the attempt counter stay the normal route (`UnifiedRiskManager.mqh:709` on the
trading-day roll, and 60 stable minutes under half the warning drawdown), which is why this is an escape hatch, not a
loosening.

**Proof that a nested read cannot grab the wrong section's number.** `JsonExtractValue` finds a key by plain string search,
which is only safe if it descends into the parent object first. `ReadFileToString` uses `FILE_TXT`, and `FileReadString`
drops the line terminators, so the parser runs on text with no newlines at all. Ported to Python and run against the real
`Config/live_overrides.json` in that stripped form: all nine `risk.*` keys return their own scalars (`1.0 / 4.0 / 12.0 /
15.0 / 4.0 / true / 3.0 / true / 1`), the absent `risk.resetCircuitBreaker` returns "" so every ceiling starts from the
*running* value, and `weights.EURUSD.Momentum` descends two levels correctly. The nine numbers equal what Batch 241 shipped,
so a reload on the first timer tick is a no-op rather than a surprise change to live risk. An out-of-range `riskTier`
(only reachable through this file - the dialog input is an enum) cannot widen risk: `SetTier`'s `default:` branch installs
the Moderate preset, and `m_tier` is read afterwards only by `GetTierName()` and the `[RISK-TIER]` print, never by a
threshold. Left as is, with the reason: the value that lands is the conservative middle, and the print shows the number.

**Sweep in the same files.** `IConfigCallback`, `CConfigCallbackBase`, `RegisterCallback`, `NotifyCallbacks`,
`GetSection`/`JsonGetSection`, `SetEnabled`/`IsEnabled` and `ForceReload` are gone: with the four stubs deleted, nothing
registered a callback, nothing read `IsEnabled`, and the `m_enabled` field could only ever be true. In the orchestrator,
`UpdateRiskParametersFromInputs` now writes all six risk fields it applies into `m_config` (it wrote three), so a live
change no longer leaves the config disagreeing with the gate that consumes it. Left in place, inherited: when
`FileGetInteger(handle, FILE_MODIFY_DATE)` returns nothing, `GetFileWriteTime` answers `TimeCurrent()`, so the 30 s poll
would see a "new" mtime every time and print `File changed, reloading...` plus `Config unchanged (same content)` forever.
That is noise, not exposure - the content comparison still refuses to apply anything - and inventing a second failure
message for an API that has never failed here is not this batch's call.

Docs: 54 `EAOrchestrator.mqh:NNN` pointers moved by the -38/-36/+15 region shifts were re-pointed by delta and then
re-anchored by content, which found six more that had been stale for batches - the `ScaleLotByLiveAuthority` call, the
second `EVAL_MODE_NEW_BAR` site, the ADX `AddModifier` registration, the `SScalpConfig` period literals, the
`RegisterCatalogAIAdapter` name read and the live microstructure feed. The Batch 226 table row that pointed at the
deleted correlation branch now names the method instead of a line number that cannot exist. Adding the report-only print
shifted every pointer below it by three again; a full pass over all 223 citations in the five current-state docs found
four that landed on a plausible neighbour instead of their claim, and they are re-anchored by content here: the
`AttributeExecutedPosition` call (`:3625`), the `IncValidatorRejects` arm (`:3556`), and both copies of the second entry
`EVAL_MODE_NEW_BAR` site (`:3551`, which two docs had as `:3536`). Every tag the three live-config doc sections quote
now has a `Print` call site, and the three deleted callback lines have none.

121 added / 200 deleted across two files (`Core/Config/LiveConfigReloader.mqh`, `Core/Orchestration/EAOrchestrator.mqh`).

Verification: `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 600`, eight programs each with its own `Result:`
line, 0 errors / 0 warnings (6.1 / 3.7 / 6.1 / 6.7 / 108.8 / 129.7 / 37.1 / 3.4 s), harness exit 0 read un-piped, all
eight `.ex5` newer than the
sources. Note for the next session: `exit 0` is only
meaningful if the harness output is not piped - a pipe reports the exit code of `tail`, and this batch's first run
printed `OVERALL FAILED` through a `| tail` while the shell still reported success. Not runtime-observed: newest journal
2026-09-23, so `[LIVE-CONFIG] live overrides armed` has not been seen in a journal, and neither has a reload.


### Batch 241: the min-lot round-up had two ceilings, and the looser one was the gate that decides the lot

`MAX_MIN_LOT_RISK_MULTIPLIER` (3.0) existed to bound a specific danger: rounding a sub-`SYMBOL_VOLUME_MIN` lot up to
the broker minimum multiplies the risk the pre-trade gate approved, because sizing runs after it. The clamp was applied
in one place - `CPositionSizer::SetMinLotRiskMultiplier` - and the two consumers that actually decide the shipped lot
never saw it. `CRiskValidationPipeline` raised the lot while `riskRatio <= m_config.minLotRiskMultiplier`, and
`CCandidateBuilder::ApplyDrawdownScaling` refused a round-up only above its own `m_minLotRiskMultiplier`. Both were fed
`InpMinLotRiskMultiplier`, whose shipped default in `MultiStrategyAutonomousEA.mq5` was **15.0**. So the sizer refused a
5x round-up while the gate approved it, and at the configured 1%/trade the gate could ship a position risking 15% of
equity on one symbol - the exact exposure Batch 223 recorded as clamped away, one layer up.

- **One ceiling, read by all three consumers.** The `#define` moved to `Core/Utils/Enums.mqh`, where `MAX_RISK_PER_TRADE`
already lives, keeping `CPositionSizer`'s `#ifndef` as a fallback. `SOrchestratorConfig::EffectiveMinLotRiskMultiplier()`
clamps to `[1.0, 3.0]` and now feeds the risk config, the sizer and the candidate builder; `CUnifiedRiskManager::Initialize`
clamps its own copy and prints `[RISK-ROUNDUP-CEILING] asked= | enforced= | ceiling=MAX_MIN_LOT_RISK_MULTIPLIER` when an
ask exceeds it. `InpMinLotRiskMultiplier` default `15.0 -> 3.0` because 15.0 could never be the running value again, and
`Config/live_overrides.json` from `15.0 -> 3.0` with it (that file is documented as the canonical VPS source).
- **The gate now obeys `InpAllowMinLotRoundUp`.** `allowMinLotRoundUp` reached only the sizer; the gate widened a
sub-minimum lot whatever the operator set, so "false" meant nothing on the path that prices the trade. The refusal prints
`[RISK-GATE-REJECT] <symbol> | reason=lot_below_min_roundup_disabled | lot= | min_lot= | uplift=` and releases the virtual
reservation like any other reject.
- **`UpdateRiskParametersFromInputs` applied nine parameters and printed a tenth.** `maxRiskPerTrade` appeared only in the
`[RISK-INPUT-UPDATE]` line: neither the gate's `baseRiskPerTradePercent` nor the sizer's `riskPercent` was updated, and
`m_config.maxRiskPerTrade` kept the old value, so every later reader of it saw the previous session's number. The method
now writes `m_config` and re-runs the init sequence in init order - `SetBaseRiskPerTrade`, `SetTier`,
`ApplyToRiskManager`, `ApplyToPositionSizer` - so the compounding tier can still scale risk down after the operator's
figure is set, and the print reads `roundupCap=X enforced`. New `CUnifiedRiskManager::SetMinLotRoundupPolicy` carries the
round-up pair into the gate's copy, which previously only `Initialize` could write.
- **`CCandidateBuilder::Configure` was handed a literal `5.0` for max risk per trade** while the dialog shipped 1.0, and
that field is the fallback when a signal asks for no risk (`if(requestedRisk <= 0) requestedRisk = m_maxRiskPerTrade`), so
a quiet request was sized at five times the configured ceiling. It takes `m_config.maxRiskPerTrade` now.

Behaviour: with the new defaults nothing moves for a correctly configured account; what changes is that a 15x ask cannot
be honoured by any consumer, an entry needing a round-up between 3x and 15x is refused rather than traded over-risk, and
`InpAllowMinLotRoundUp = false` and `InpMaxRiskPerTrade` now mean what they say. Restricting direction, never widening.

**This reverses a recorded operator decision, and that is the reason it is written here rather than left as a cleanup.**
Batch 142 (2026-08-06, `docs/changelogs_batch102-169.md:823`) restored a 15x round-up tolerance in three places on the
instruction "keep risk up to 15x, not 1x". A later audit batch replaced that with `MAX_MIN_LOT_RISK_MULTIPLIER = 3.0`
because "the round-up happens in the sizer, *after* the pre-trade gate approved the sized lot, so one position could risk
15% of equity against a 1% setting". The two decisions were never reconciled: the newest clamp landed only in the sizer,
while the gate and the builder kept the 15x ask, so the account has been running the older answer on the path that
decides the lot and the newer answer on the path that refuses. This batch sides with the newer clamp because it is the
one written after the money audit and because the exposure it bounds is the one this repository exists to remove; the
number is a `#define` in `Core/Utils/Enums.mqh`, so restoring 15x is one deliberate edit rather than a silent drift, and
`[RISK-ROUNDUP-CEILING]` prints which is in force. A symbol whose sized lot needs more than a 3x uplift now prints
`[RISK-LOT-FLOOR] ... REJECTED: ... risk X.Xx > 3.0x cap` instead of shipping over-risk - if a book goes quiet after
this batch, that line is the difference between a dark symbol and a strategy that stopped voting.

Not fixed, with the reason: `SOrchestratorConfig`'s own constructor still carries the pre-Phase-0 numbers
(`maxDailyRisk = 40.0`, `maxPortfolioRisk = 60.0`, `maxRiskPerTrade = 5.0`); every root EA overwrites all three before
anything reads them, so they are inert today, but a new caller that forgets one gets 40% daily risk - left for the
config-ownership pass rather than silently rewriting defaults nobody reads. Also found and left for the next batch:
`Config/live_overrides.json` is documented as "loaded live every 30 s", but all four `CLiveConfigReloader` callbacks
(`Risk`, `Weights`, `Thresholds`, `Symbols`) receive their section JSON and print "`<section>` section reloaded" without
reading it, so the hot-reload channel has never applied a single value - which is why this batch corrected the file by
hand instead of relying on it.

Docs: 69 `file.mqh:NNN` pointers in the five docs moved by the insertions and were re-pointed by delta, then 24 were
re-anchored by content because they were already stale - three of them naming `CPositionSizer::NormalizeVolume` at
`PositionSizer.mqh:659`, which is `SetMinLotRiskMultiplier`, the actual definition being `:572`. 71 added / 15 deleted
across eight files (`Enums.mqh`, `OrchestratorConfig.mqh`, `EAOrchestrator.mqh`, `PositionSizer.mqh`,
`RiskValidationPipeline.mqh`, `UnifiedRiskManager.mqh`, `MultiStrategyAutonomousEA.mq5`, `Config/live_overrides.json`).
Verification: `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 600`, eight programs each with its own `Result:`
line, 0 errors / 0 warnings (9.3 / 5.5 / 9.7 / 9.7 / 152.3 / 125.9 / 45.5 / 2.7 s), harness exit 0, all eight `.ex5`
newer than the sources. Not runtime-observed: newest
journal 2026-09-23, so neither `[RISK-ROUNDUP-CEILING]` nor `reason=lot_below_min_roundup_disabled` has been seen firing.


### Batch 240: margin was priced on a lot the trade never shipped, and the margin ladder had no driver

**1. The margin gate tested a different lot than the one it approved.** `ValidateMarginRequirements` runs on
`request.lotSize` (`RiskValidationPipeline.mqh:480`), and the lot floor raises `result.adjustedLotSize` to the broker
minimum *after* that (`:522`). Both numbers then travel in one result: the builders and the four engine books adopt
`adjustedLotSize`, so a sub-minimum lot was approved on margin calculated for the smaller size. The file's own comment at
`:1124` had recorded half of this ("Margin is checked on request.lotSize, not the adjustedLotSize the lot floor may still
raise below") and left the consequence unowned. Now the lot is re-priced where it is final: a raise triggers
`ValidateMarginRequirements` again on a request copy carrying `adjustedLotSize`, and failure refuses with
`[RISK-GATE-REJECT] <symbol> | reason=lot_floor_margin | lot=A -> B` plus a `LOT_FLOOR_MARGIN` record, releasing the
virtual reservation like every other refusal. Shrink-only adjustments do not re-run the check - a smaller lot cannot
need more margin.

**2. `CRiskMarginHealth::MonitorMarginHealth` had no caller, so the account had no margin protection.** Its only entry
point, `CUnifiedRiskManager::MonitorMarginHealth()`, was declared, defined and never called - which means the tiers that
flatten under 150%, cut the worst position under 200% and de-risk under 300% have never once run, and no `[RISK-MARGIN]`
line exists in any journal on this machine. `ACCOUNT_MARGIN_LEVEL` was read in two places in the whole tree: this dead
monitor, and a dashboard JSON field. The drawdown and daily-loss breakers arm from `RefreshRuntimeState()`; the margin
ladder now joins them there, on its own wall-clock throttle (`MARGIN_HEALTH_POLL_MS` 30000, `GetTickCount()` because
`TimeCurrent()` only advances with ticks and a quiet symbol is exactly when a leveraged account needs the check).
`[RISK-MARGIN] monitor armed | poll_ms=30000 | hold_entries_below=200% | request_flatten_below=150% |
free_margin_use_limit=80% | min_post_trade_level=200%` prints at init, because three batches of unwired protectors have
taught that a silent latch is indistinguishable from an absent one.

**Wiring it required changing what it does, not only calling it.** The old monitor closed positions itself: a
`CTrade::PositionClose()` loop over every position at the emergency tier and a second one picking the worst ticket at the
critical tier, each with its own journal write. That is a second flatten authority beside `CRiskCircuitBreaker`, the exact
shape Batch 237 deleted from the spike monitor, and AGENTS section 3 names `CTradeManager`/the EA loop as execution
owner. It now *requests*: `CRiskCircuitBreaker::RequestEmergencyClose()` raises the flag that the orchestrator's three
existing `IsEmergencyCloseRequested()` consumers already act on. Second, it wrote the shared `conservativeMode` flag at
both tiers, and that flag latches: `CRiskAdaptiveTuner::UpdateAdaptiveRiskLevel` captures it first and clears it only
`else if(!conservativeHeld)`, so one margin write would have kept the account in conservative sizing until a drawdown
recovery happened to clear it - a sizing authority hostage to a margin reading. Sizing is left to the tuner, and with it
goes the ladder's third tier: below 300% the monitor now prints `[RISK-MARGIN] WARNING | ... | advisory only` at most once
a minute and changes nothing, because the only action that tier had was the latching write. What the margin tier does own
is an entries hold: `m_marginEntriesHeld` in the manager, set while the poll reads CRITICAL or
EMERGENCY, cleared by the next poll that reads better, and consulted by the pipeline as a refusal of its own
(`[RISK-MARGIN] <symbol> | entry refused | marginLevel=... | margin=... equity=...`, `:342`). It is deliberately
in-memory: the persisted circuit-breaker halt can be restored without a releasable owner (`ResetCircuitBreaker()` has no
caller), and a margin hold must not outlive the measurement that made it.

**Sweep in the same files.** Seven `Validate...` forwarders on `CUnifiedRiskManager` (`ValidateBasicParameters`,
`ValidateRiskLimits`, `ValidatePortfolioRisk`, `ValidateCorrelationLimits`, `ValidateMarginRequirements`,
`ValidateAccountHealth`, `ValidateClusterGovernance`) were declared, defined, forwarded to the pipeline's own method of
the same name, and had no caller - every pre-trade gate calls its own copy inside `CRiskValidationPipeline`, and none of
them is in `IRiskPipelineHost`. `CRiskMarginHealth`'s four threshold accessors went with them (`Get/SetMaxFreeMarginUsage`,
`Get/SetMinMarginLevel`: zero readers, and Batch 223 already recorded the two constants as operator policy that stays
literal). `HaltForMarginEmergency()` is replaced by `RequestEmergencyClose()`, so `m_tradingEnabled` is no longer written
from outside the breaker's own drawdown logic - the only path that can strand a halt the recovery ladder cannot lift.

**Recorded, not wired:** `CFullMarginMode` is initialized at `EAOrchestrator.mqh:1007`, holds a config of its own
(`maxStackedPositions`, `stackLotScale`, `minMarginLevelPct` 200, `dailyLossLimitPct` 25, a session lockout after two
breaches) and `PrintDiagnostics()` is the only method anything calls. `CanStackPosition`, `GetStackedLotSize`,
`GetStackLevel`, `CheckSafeguards`, `CheckFullMarginCircuitBreaker`, `IsInCooldown` and `IsSessionLocked` have no caller,
so the full-margin tier trades with none of its stated rules. That is a trading-mode decision - which tier activates it,
what stacking may cost - not a dead-code cleanup, and it is the same judgement the intrabar policy got in Batch 233.

Docs corrected: README's new operational section, `SYSTEM_STRUCTURE.md` (authority table rows for breaker evaluation and
a new margin-protection row), `RUNTIME_DECISION_GRAPH.md` (ownership map line, two dated sections), `SYSTEM_AUDIT_TRACE.md`
and AGENTS section 6, which listed `[RISK-MARGIN]` nowhere because the code could never print it. Verification:
`sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 600`, eight programs each with its own `Result:` line, 0 errors /
0 warnings (7.0 / 4.8 / 9.4 / 7.0 / 168.5 / 146.0 / 38.1 / 2.6 s), every `.ex5` newer than every source; the one source
edit after that run is a line number inside a comment this batch wrote, so it changes no binary. Not runtime-observed:
newest journal 2026-09-23, so no `[RISK-MARGIN]` line has ever been seen firing - which is the point of the init
announcement.

### Batch 239: an open position was charged to the risk caps twice for a minute after every fill

`ValidateTradeRequest` reserves portfolio budget before the gates (`RiskValidationPipeline.mqh:385-393`), releases it on
every rejection branch, and **keeps it on approval** - which is right, because the reservation bridges approval and the
moment the position becomes visible. It was never ended any other way. The tag it is keyed on (`"%s_%s_%lld"`, built at
`:391`) is not returned to the caller, so after a fill no code could release it, and the only thing that removed it was
its 60-second TTL. Meanwhile `CPortfolioRiskManager::GetPortfolioRisk()` had been counting that same position as open
exposure since the fill. So every projection built on `reservedRisk + openExposureRisk` saw one trade as two:

- the pre-gate daily budget test (`:359-362`) and its post-adjustment twin (`:738`), against `InpMaxDailyRisk = 4.0`;
- the portfolio projection `CalculatePortfolioRiskAfterTrade` (`:919-922`), against `InpMaxPortfolioRisk = 12.0`;
- `CUnifiedRiskManager::GetRemainingPortfolioRiskPercent()` (`:929`), `GetRemainingDailyRiskPercent()` (`:834`), and
  `snapshot.virtualReservedRiskPercent` / `virtualReservationCount` (`:962`/`:966`).

At roughly 1% risk per trade a four-fill minute read as 8% of a 4% daily budget, and eight fills as 16% of a 12%
portfolio cap - the caps refused live entries on money already counted as exposure. With the Batch 237 send cap of 3
per cycle this is reachable inside one scan pass.

**Fix.** `PruneExpired()` becomes `PruneStale()`: the TTL pass, then `PruneCoveredByPositions()`, which discharges a
reservation once a real position covers it. Matching is oldest-reservation-first and **one position covers one
reservation** (`posUsed[]`), on symbol, direction (`POSITION_TYPE` vs `IsBuyOrderType`), `POSITION_TIME >= reservedAt`
(so a position that predates the reservation cannot discharge it), `POSITION_VOLUME >= lotSize`, and
`POSITION_MAGIC != 0` (a manual trade does not discharge our pending risk). Oldest-first is an explicit selection pass
over `reservedAt`, not the array order: both prune branches compact by swap-remove, so the book is not chronological, and
without the selection the same set of fills could discharge different reservations depending on which earlier prune had
run. The position list is snapshotted into parallel arrays once per call, not re-walked per reservation: `PruneStale` runs
from five entry points, each validation request calls it about four times, and a cycle validates up to thirteen symbol
slots.

`UpdateVirtualPositionRisk` now takes the lot as well as the risk percent and is fed `result.adjustedLotSize` at `:776`.
Without that the fix would have missed exactly the trades that needed it: a correlation REDUCE or a min-lot floor changes
the lot *after* `Reserve()`, so the reservation would still have carried the pre-adjustment lot, no fill could ever match
the volume test, and the double count would have stayed for those books.

Sweep deletions in the same two files: `CVirtualPositionBook::GetReservation` (declared and defined, zero callers) and
`CUnifiedRiskManager::ClearVirtualPositions` (same) - the latter's `[RISK-VIRTUAL] clear | remaining=0` line therefore
no longer exists, and `Print("[RISK-VIRTUAL] clear...")` was never in any journal. `HasOpposingReservation` lost a
three-line comment describing a `const_cast` pattern that is not in the file; it keeps the true reason it can skip
pruning (it is const, and `:359` prunes this same book a few statements earlier).

What is deliberately not fixed: a candidate the gate approves and the orchestrator never sends still holds its
reservation until the TTL, because nothing covers it. That is the conservative direction - it charges risk that may not
exist for up to a minute - and releasing it would need the send path to report back, which is a larger change than a
double count this clean to close.

`[RISK-VIRTUAL] pruned` now prints `expired= | covered_by_position= | remaining=`; the old
`Pruned %d expired reservation(s) | remaining=%d` form reported only the clock. 135 added / 49 deleted across three
files. Verification: `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 600`, eight programs each with its own
`Result:` line in its own kept log, all 0 errors / 0 warnings, every `.ex5` newer than every source. The batch was
compiled twice because the prune matcher was rewritten between runs; the run that stands is 5.0 / 2.7 / 6.1 / 6.3 /
123.7 / 112.1 / 36.9 / 2.9 s, script exit 0. No journal newer than 2026-09-23, so this is not runtime-observed yet.

### Batch 238: twelve inputs that wrote a config field and bound nothing, and the dead class one of them served

The Batch-237 audit swept every `SOrchestratorConfig` field for a reader. Fourteen had a writer in both root EAs and
no consumer; each was then decided individually rather than by list, because two of them were worth wiring.
12 added / 286 deleted across six files, including one whole class file.

**Deleted - no consumer, and no single authority to attach them to.**
`allowAIWarmStartLive` (`CLiveAuthorityResolver` has no warm-start concept: its AI path is the bootstrap-then-promoted
ladder at `LiveAuthorityResolver.mqh:116`/`:265`), `authorityTrialHorizonSeconds` and `authorityMaxTrackedTrials` (the
resolver's `Configure(...)` takes eleven arguments and none of them is a trial window or a tracked-trials cap - there
is no trial store to size), `nonAIPromotedRiskMultiplier` (one promotion branch exists, it is AI-only, and its value
comes from `aiPromotedRiskMultiplier`; a second promoted multiplier would be a second authority over one lot),
`enableHybridCadence` and `intrabarChartSymbolOnly` (the cadence authority is the bar gate plus `evalBudget`, printed as
`[SCAN-POLICY]`; Batch 215 deleted the scheduler these described), `closeUnprotectedOnRemediationFailure` (the tracker
closes at escalation 3 - `UnprotectedPositionTracker.mqh:327-349` - under the comment "no position should exist without
SL", which is an invariant, not a preference; the input's off direction had no code).

**Deleted - a feature that was never written.** `enableAutoModeSwitch` gated `UpdateAutoModeSwitch()`, a two-line stub
whose body was the comment "Auto mode switching is not implemented: no mode or risk parameters are applied here."
Along with it: `conservativeBaseRiskPct`, `aggressiveBaseRiskPct`, `modeSwitchDrawdownPct`, `modeSwitchWinStreak`, the
`ENUM_AUTO_SWITCH_MODE` enum, `m_currentTradingMode`, and the `[VALIDATION]` block at `MultiStrategyAutonomousEA.mq5:919`
that policed them - which had been *failing OnInit* on relationships between four values that reached nothing. The live
mode authority is elsewhere and is not this shape: `CRiskAdaptiveTuner` scales the active per-trade risk down from
`baseRiskPerTradePercent`, whose only writer is `InpMaxRiskPerTrade` through `EAOrchestrator.mqh:838`, and the
conservative flag is set by a two-of-five trigger vote (`PerfAnalyticsRiskTriggers.mqh:124-138`: win rate < 40, Sharpe
< 0.5, drawdown > warning, 3 consecutive losses, PF < 1.2). Wiring the deleted fields would have replaced that with a
single drawdown switch and added a second base risk - loosening a risk gate on inputs nobody had been applying, which is
operator policy, not cleanup.

**Wired, not deleted - the two NN attribution inputs.** `enableNNAttributionDiagnostics` and `runNNAttributionSelfTest`
do have consumers (`TradeAttributionManager.mqh:592`/`:598`/`:616`); what was missing was the call.
`SetNNDiagnosticsEnabled`/`SetRunSelfTest` had zero call sites, so the struct defaults ran (`true`/`true`), and
`RunNNAttributionSelfTest` - a real round-trip test of the prediction-comment id and the position map Batch 203 made
load-bearing - had no caller either. The orchestrator now feeds both at the attribution init site and calls the test.
`InpEnableNNAttributionDiagnostics` default flips `false -> true` because that is what every build has printed: leaving
it `false` would have silently deleted the `[NN-DIAG] Summary (deinit)` line, the same "made invisible by a wiring fix"
shape Batch 233 warns about. `InpRunNNAttributionSelfTest` stays `false`, so behaviour is identical and the switch is
real in both directions.

**Deleted: `Core/Processing/TickSafetyMonitor.mqh` (164 lines).** Batch 237 removed its last reference - the spike
monitor's `m_tickSafetyMonitor`, which was the only caller of `ValidateTick`, `IsTradingAllowed`, `IsSpreadAcceptable`
and `HasTickGap`. What remained was a member, three setters called with literals at init (`SetMinFreeMarginPercent(20.0)`,
`SetMinMarginLevel(150.0)`, `SetEmergencyStop(false)`) and a forward declaration: a class configured and never consulted.
`Emergency stop` in that class never halted anything because `IsEmergencyActive()` had no reader either. Margin and
drawdown protection live in `CRiskMarginHealth`, `CRiskCircuitBreaker` and `CUnifiedRiskManager`, which are called.
No transitive include broke: `EAOrchestrator.mqh:79` includes `<Trade\AccountInfo.mqh>` itself, and
`TradeManager.mqh:12`/`SessionManager.mqh:6` include `<Trade\SymbolInfo.mqh>`.

Verification: `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 600`, eight programs each with its own `Result:` line, 0 errors / 0 warnings (5.3 / 2.7 / 4.2 / 6.4 / 181.8 / 393.9 / 100.1 / 5.1 s), harness exit 0, every `.ex5` newer than the sources and the synced copies byte-identical to the tree. The first run of this batch failed - `error 214: cannot access private member function` at the new `RunNNAttributionSelfTest` call, because the declaration sat in the class's private block - and the harness reported `OVERALL FAILED` with exit 1 rather than a green, which is the Batch 228 behaviour doing its job. Not runtime-observed: newest journal 2026-09-23.

### Batch 237: the entry loop's own send budget, and a spike monitor that had no driver

Two controls in the path that puts money on were declared, wired into `SOrchestratorConfig`, printed in the dialog and
bound nothing. 154 added / 275 deleted across three files.

**The cycle's position count was measured once, so one cycle could order every slot.** `GetEAPositionCount()` feeds
`positionLimitBlocked` at `EAOrchestrator.mqh:3459`, that flag folds into `canOpenNewTrades` at `:3464`, and the send
loop tests the single bool at every iteration - so with the default 13-symbol roster a book read at 14/15 could take
13 orders in one pass, nearly double `InpMaxPositionsTotal`, and `InpMinSecondsBetweenTrades = 10` was likewise
armed only after the cycle returned (`m_lastTradeTime` updates per fill at `:3590` but `cooldownBlocked` had already
been computed). Third input in the same group, `InpMaxTradeSendsPerCycle = 3`, wrote `spikeConfirmWindows`'s
neighbour `maxTradeSendsPerCycle` in the config and had no reader anywhere in the tree: no send counter exists in
`CTradeExecutor` or the builder. Both counting bounds are now measured per slot - `sendsThisCycle >= cycleSendCap`
and `eaPositions + sendsThisCycle >= maxPositionsTotal` - tested before `ValidateSignal`, because a candidate that
reaches `BuildCandidate` keeps a virtual portfolio reservation (`RiskValidationPipeline.mqh:391-394`, TTL 60 s, and
`ReleaseVirtualPosition` cannot be called by the orchestrator since the tag embeds `GetMicrosecondCount()`) and held
slots would otherwise spend the budget of a minute's cycles. The tally, not a fresh count, is the right measure:
async fills reach the position list after the send. `spike_events=` and the pause were already per-cycle-stable;
`minSecondsBetweenTrades` is still measured at cycle start and now says so in `[ENTRY-BOUNDS]`.

**`CSyntheticSpikeMonitor` could not detect anything, and what it detected was a second flatten authority.**
`ProcessTickSafety` had no call site, so `EvaluateSpike` (its only caller), `TriggerSpikeAlarm`, `HandleEmergencyDrawdown`
and `ActivatePause` were unreachable: `[SPIKE-PAUSE]`, `[SYNTHETIC-SPIKE]` and `[SPIKE-ALARM]` had printers no path
could enter, `IsPaused()` - the `spike_pause` term of `[ENTRY-GATE]` and `pause_active=` of `[HEARTBEAT]` - was
constant false, `[HEARTBEAT] spike_events=` constant zero, and `InpSyntheticSpikeVelocityMultiplier`,
`InpSyntheticSpikePauseSeconds` and `InpSpikeConfirmWindows` bound nothing. The dead `ProcessTickSafetyLoop` stub said
wiring `HandleEmergencyDrawdown` would add a second flatten authority, and reading the code that authority would have
been right twice over: both `HandleEmergencyDrawdown` and `TriggerSpikeAlarm` close positions, and `CTradeManager`
already has three emergency-close call sites driven by `CRiskCircuitBreaker`. So detection was rebuilt and flatten
deleted. `CRiskCircuitBreaker` is the sole flatten authority; this path only holds new entries.

**The rebuilt measurement is per symbol and works without a tick callback.** The old code counted its own calls
(`m_tickRateWindowCount++` per `EvaluateSpike`) and tested `IsSyntheticIndexSymbolName(_Symbol)`, so it measured how
often the chart symbol delivered `OnTick` - which for a 13-symbol universe attached to one chart is not the market's
tick rate, and for a chart on EURUSD is nothing at all. Each watched synthetic now keeps a 1-second window over
`iVolume(symbol, PERIOD_M1, 0)`: the delta is the terminal's own tick count for that symbol, so a 1 s timer poll
(`EventSetTimer(1)`) measures a real flood. Windows that rolled the M1 bar (negative delta) or that spanned more than
5 s (weekend gap, restart) re-anchor without measuring, because seeding the EWMA with an hours-long window would put
the baseline near zero and read the next live second as a spike. Confirmation arithmetic is unchanged
(`MathMax(1.5, velMult)` against `MathMax(1.0, baseline)`, `confirmWindows` consecutive windows), the pause policy is
unchanged (`MathMax(5, pauseSeconds)`, entries only), and the EMA is unchanged (0.85/0.15). Registration filters to
`IsSyntheticIndexSymbolName`, so the six FX/crypto slots of the default universe cost nothing and cannot alarm on a
busy session. `[SPIKE-MONITOR] N synthetic symbol(s) watched | velMult= | confirmWindows= | pauseSeconds= |
action=pause_entries` names the watched count and the three values at init.

**Deleted with the flatten loops:** `GetSpikeEventCount`/`ResetSpikeEventCount` and `m_spikeEventCount` (no caller;
`[HEARTBEAT] spike_events=` is fed from `CHeartbeatTelemetry`, whose `IncSyntheticSpikeEvents` had *no* caller at all
until this batch and now takes the count), `GetPauseUntilTime` (no reader), `IsEAOwnedMagic` (its only callers were the
two flatten loops), `Initialize` and its three collaborator pointers. Of those, `m_riskManager` existed to call
`RefreshRuntimeState`, which has its own live caller at `EAOrchestrator.mqh:3088`, and `m_tickSafetyMonitor` was the
only caller of `CTickSafetyMonitor`'s checks (`ValidateTick`, `IsTradingAllowed`, `IsSpreadAcceptable`, `HasTickGap`),
so that class is now read by nothing and Batch 238 deletes it. `[EMERGENCY] Flatten completed` and
`[EMERGENCY-WARNING]` printed nowhere and are gone with their code; no doc cited them.

Verification: `sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 600`, eight programs each with its own `Result:`
line, 0 errors / 0 warnings (7.8 / 3.8 / 7.6 / 9.1 / 104.0 / 118.8 / 37.5 / 2.5 s), harness exit 0, synced sources byte
identical to the tree. The first run reported one warning per EA - `possible loss of data due to type conversion from
'long' to 'double'` at the `iVolume` read - fixed by taking the tick volume as the `long` it is and converting once, at
the rate, rather than by suppressing it. Not runtime-observed: the newest journal is still 2026-09-23, so no
`[SPIKE-PAUSE]`, `[ENTRY-BOUNDS]` or held-mid-cycle line has ever been seen firing.

### Batch 236: thirty stale line pointers in the five docs, and one more write-only candidate field

AGENTS.md section 8 says a citation must be re-pointed in the batch that moves the code. Batches 215-231 moved a lot of
code and re-pointed only what their own edits broke, so the current-state docs had accumulated pointers that land on
blank lines, on braces, past end-of-file, or on a file that does not exist. A mechanical pass over every
`File.mqh:NNN` citation in `README.md`, `SYSTEM_STRUCTURE.md`, `RUNTIME_DECISION_GRAPH.md`, `SYSTEM_AUDIT_TRACE.md` and
`AGENTS.md` found 20 provably-bad pointers; resolving each claim against the tree turned up 10 more that landed on a
plausible neighbouring line. 26 doc lines rewritten.

**Pointer corrections (claim re-read, then re-anchored):** `RiskMarginHealth.mqh:199/209` -> `179/189` (the two margin
setters, this file has 196 lines so 199 was past EOF); `UnifiedRiskManager.mqh:225` -> `217`
(`SetTradingDayStartHour`); `PositionSizer.mqh:489` -> `483` (the equity-curve reader) and `:257` -> the surviving
registration in the orchestrator at `:939` (Batch 213 deleted the sizer's copy and its comment);
`SignalGenerator.mqh:352-357` -> `350-356` (the new-bar gate); `EnterpriseStrategyManager.mqh:844` -> `768` and
`EAOrchestrator.mqh:2409` -> `2425` (the two registration paths that pass the catalog row name);
`RiskValidationPipeline.mqh:949` -> `958` (`ValidateClusterGovernance`'s early `return true` at cluster `"N"`);
`EAOrchestrator.mqh:1791` -> `1820` + `EnterpriseStrategyManager.mqh:580` (where `managedMagic` actually comes from);
`:3483-3487` -> `3501` (`IncValidatorRejects`); `:3500` -> `3517` (`Resolve`); `:3517` -> `3531`
(`ScaleLotByLiveAuthority`); `:3544` -> `3568` (`AttributeExecutedPosition`); `:3445` -> `3441` (the spike-pause gate);
`:2607` -> `2593` (`FeedMicrostructure`); `CandidateBuilder.mqh:433-436` -> `373-386` (the contributor flags), `:494` ->
`:497` (the VPIN-sizing comment), `:767` -> `:768` (`ApplyDrawdownScaling`); `EnterpriseStrategyManager.mqh:1080-1086`
-> `134-135` (the delegator re-bind); `Core/Utils/LogMacros.mqh:41-42` dropped - those macros no longer exist (Batch 218
deleted them) and the two tags print literally from `CandidateBuilder.mqh:257`/`:274`/`:288`.

**Two claims, not just pointers, were false.** `EAOrchestrator.mq5:3418` names a file that does not exist, in two
sentences saying the live-authority multiplier "reaches nothing" and that the mode vetoes and `LOW_CONFIDENCE` are the
only effects. Batch 205 ended that: the multiplier is applied by `ScaleLotByLiveAuthority`. Both bullets now say what
was true at the time and what closed it. The README's correlation row still described the sizer path as "explicitly
disabled at `:886`"; Batch 226 deleted it, and the truth is the comment at `EAOrchestrator.mqh:891-892` plus the
pipeline's REDUCE shrink at `RiskValidationPipeline.mqh:694`.

**Deleted with that reading:** `STradeCandidate::liveAuthorityRiskMult` - field, constructor initialiser and both writes
(`CandidateBuilder.mqh` stub, `EAOrchestrator.mqh` post-`Resolve` copy). Two writers, zero readers: the value that
sizes the trade is `authority.riskMultiplier`, passed as a parameter to `ScaleLotByLiveAuthority`, and the reason the
refusal prints is `candidate.liveAuthorityReason`, which has three readers. Same treatment and same reasoning as
`liveAuthorityAllowed` in Batch 225. The stub comment that promised the copy was corrected to name the field that is
actually overwritten. 8 lines deleted / 4 added across `CandidateBuilder.mqh` and `EAOrchestrator.mqh`; no lot, gate or
threshold moved.

**Scope left honestly open:** the sweep only concludes on pointers that are mechanically provable wrong (blank, brace,
past EOF, wrong filename) plus the ones whose claim it could re-anchor by symbol. A citation landing on a plausible
neighbouring line is not detectable that way, so this is not "the docs are now correct" - it is "the docs no longer
contain pointers that cannot point anywhere". The `changelogs.md` entries are dated records and were left alone.

**Verification:** `sync_and_compile.ps1 -All` - eight programs, each with its own `Result:` line, 0 errors / 0 warnings
(11.2 / 6.7 / 9.9 / 10.6 / 118.8 / 109.1 / 40.4 / 1.9 s), script exit 0, every `.ex5` newer than the last source edit.
The detector that found them checks each cited line for blank, lone brace, past-EOF or missing-file and reported zero
suspects over the five docs afterwards; that is not a proof every pointer is right, only that none points where nothing
can be.

### Batch 235: the training session scored a second, untrained network and reported it as the model's metrics

`CTrainingSession` held **two** neural networks. `m_model_ptr` is the caller's model - the one `Train(model, ...)`
trains. `m_model` was a by-value `CFeedForwardNN` member that nothing ever trained, and the whole first family of the
class worked on it: `Initialize()`, `Train()` (the no-arg twin of the live overload), `TrainEpoch()` and `Evaluate()`.
None of those four has a caller - the three consumers (`MQHModelTrainer.mq5`, `MQHModelVisualizer.mq5`,
`HyperparameterOptimizer.mqh`) all go through `SetConfig` + `Train(model, ...)` - so the family looked like an unused
alternative API. It was not unused. `Finalize()` is called by the live `Train(model, ...)` at the end of every run,
and its last act was `Evaluate(m_valFeatures, m_valLabels, m_valCount)`: a pass over the validation set through the
**untrained** `m_model`, whose result is written into `m_metrics` by that same method. Every consequence below follows
from one line:

- `GetValMetrics()` returned the untrained network's accuracy, F1, loss and confusion matrix - the numbers printed
  under `--- Validation Metrics ---` and shown in `[MQH-VIZ]`'s metrics table.
- `GetTrainMetrics()` returned the *same object*, so `--- Training Metrics ---` printed that same untrained result a
  second time. The train/validation gap an operator reads to judge overfitting was structurally invisible.
- `HyperparameterOptimizer::EvaluateCandidate` filled `valAccuracy`/`valLoss`/`f1Score` from those metrics and
  `RankResults()` sorts every candidate by `f1Score`. Since `m_model` is the same default-constructed network for all
  candidates, the tuner ranked architecture candidates on identical noise: `[MQH-TUNER] ... Train: x | Val: x` printed
  one number twice, and the `rank` column was not evidence about any candidate.
- `GetModel()`, `SetLearningRate()`, `SetTemperature()` and `SetL2Regularization()` configured or returned `m_model` -
  the wrong object. All four have zero call sites (the three `SetTemperature` hits in the tree are the live NN/ONNX/
  Transformer adapters on their own nets), so they were a trap rather than a bug.
- `MQHTrainingLog_*.txt` could never exist: its only `FileOpen` was inside the uncalled `Initialize()`, so
  `LogMessage`'s `if(m_logHandle != INVALID_HANDLE)` file branch and `Finalize`'s `FileClose` were both unreachable,
  and the trainer's only training-run record was the terminal journal.

**Fixed.** The by-value family is deleted with `m_model` and the four wrong-object accessors, and `Finalize()` now
scores the model that was trained: `EvaluateWithModel(..., CTrainingMetrics &target)` writes into the holder the caller
names, validation into `m_metrics` and one real pass over the training set into a new `m_trainMetrics`, so
`GetTrainMetrics()` and `GetValMetrics()` answer two different measurements. The log file is opened by the live
`Train(model, ...)` and its path is printed as `[MQH-TRAIN] Training log: <file>` (the `[MQH-TRAIN] Warning: Failed to
open log file:` line that names the same file is now reachable), and `Finalize`'s closing line states which condition
ended the run: `stop=early-stopping` or `stop=epoch-budget`.

**A second defect the first one exposed.** `CHyperparameterOptimizer` holds one `CTrainingSession` as a member and
calls `Train(model, ...)` once per candidate - a fresh network each time, the same session. Early-stopping state lived
on the session and nothing reset it: `m_bestValLoss` starts at `1e10` only in the constructor, so candidate two's
improvement test compared against candidate one's best validation loss (a harder bar, and an unrelated model's
number), `m_earlyStopCounter` carried over, and `m_earlyStopTriggered` stayed `true` for every candidate after the
first one that stopped early. `Train()` now resets `m_bestValLoss`/`m_bestEpoch`/`m_earlyStopCounter`/
`m_earlyStopTriggered` at the top of each run, so `bestEpoch` and `stop=` describe the model that produced them.
Same root, different symptom: `m_logHandle` was not in the constructor's initialiser list at all, and a zero-filled
handle is `0`, not `INVALID_HANDLE` (`-1`), so the newly-reachable `if(m_logHandle != INVALID_HANDLE)` write branch
would have been reading an uninitialised member on the first run - it is now initialised, and the log file name is set
once per program run with each candidate appending (`FILE_READ | FILE_WRITE` + `FileSeek(SEEK_END)`) instead of a
timestamped file per candidate.

**Also in this batch - the two write-only config fields and one inert input.**
- `STrainingConfig::earlyStoppingMinDelta` was set to `0.0001` at all three call sites and read by nobody, while
  `CheckEarlyStopping` compared against a hard-coded `1e-6`: the classic "threshold written, never read" with a
  constant standing in for it. It is now a real member (`m_earlyStopMinDelta`) set from the config and used by the
  test, and the value that binds is the one that has always bound - `1e-6` as `STrainingConfig`'s constructor default,
  three dead writes deleted. Raising it stops training sooner, which is a model-quality choice, not a cleanup.
- `STrainingConfig::enableVisualization` (field + two writes) and `CTrainingSession::SetVisualizer` - a method whose
  body was a comment and which discarded its argument, called once - are deleted, with the `CTrainingVisualizer`
  member that only that method referenced, its include in `TrainingSession.mqh`, the unused `CTrainingVisualizer
  visualizer` local and include in `MQHModelTrainer.mq5`, and `input bool enableVisualization = true` - an
  operator-visible switch in the inputs dialog that did nothing. `MQHModelVisualizer.mq5` still draws its charts; that
  program drives the visualizer itself.
- `MQHModelVisualizer.mq5`'s `CTrainingMetrics trainMetrics` local was written and never read; deleted.

`MQHModelTrainer/README.md` documented `earlyStoppingMinDelta: 0.0001` as a working setting (the Batch 215
phantom-evidence shape in a subfolder doc) - it now states the effective `1e-6`, what raising it would do, and adds the
`MQHTrainingLog_*` row to the Output Files table, which is true only from this batch.

**Scope note:** no EA binary includes `TrainingSession.mqh`, so nothing here changes a live decision, a lot or an exit.
What it changes is the evidence the operator uses to choose the model the EA loads.

**Verification:** `sync_and_compile.ps1 -All` - eight programs, each with its own `Result:` line, 0 errors / 0 warnings
(7.6 / 3.3 / 6.8 / 6.7 / 105.4 / 103.8 / 26.0 / 1.7 s), script exit 0, every `.ex5` newer than the last source edit.
`TrainingSession.mqh` went 380 -> 257 lines.

### Batch 234: the write-only timeframe table's residue, and the two timeframe inputs the EA never consults

Batch 233 left the per-strategy timeframe table standing because it is the natural carrier for task #65 (give each
symbol an explicit operating timeframe). This batch removes only what cannot be part of that future and announces
what can.

**Deleted.**
- `SStrategyTimeframeConfig::intrabarEnabled` - field, constructor initialiser and 20 assignment lines in
  `StrategyConfigBuilder.mqh`. It was a boolean restatement of the same `InpIntrabarEligibility* != OFF` fact the
  policy enum already carries, with no reader since Batch 231. Two authorities for one quantity, one of them inert -
  the Batch 38/215 shape.
- `CEnterpriseStrategyManager::GetStrategyIntrabarPolicyConfig` and the `CIntrabarPolicy` original. Declared,
  defined, forwarded, never called: the live per-slot reader is `GetIntrabarPolicyHelper`, used at registration.
- Config slot 20, name `"Exit Optimizer"`, in both the timeframe and intrabar tables. Batch 207 deleted that
  strategy's catalog slot; no `CatalogPolicySlot` index names 20, so the row described nothing and defaulted to the
  same values (`INTRABAR_POLICY_OFF`) its deletion leaves. The table is 23 slots (`MAX_STRATEGY_CONFIGS`) and 19 are
  written after this; slots 3, 5, 6 and 20 keep struct defaults. Of the 19, only 14 are ever read: the sole reader is
  `GetIntrabarPolicyHelper(CatalogPolicySlot(i))` at registration, and the catalog names 0,1,2,4,7,8,14,15,16,17,18,
  19,21,22. Rows 9-13 - the five AI adapters - are written and never read because those rows carry `siPolicyIndex = -1`
  and register a `fixedPolicy` instead. Kept: those five strategies exist, and the table is task #65's carrier, so
  deleting them is a timeframe decision, not a cleanup.

**Announced rather than wired.** `InpMomentumScalpTimeframe` (M5) and `InpCandlestickIntrabarTimeframe` (M5) flow
only into `strategyTimeframeConfigs[].defaultTF/intrabarTF`, and the sole getter chain -
`COrchestratorIntrabarPolicy::GetStrategyTimeframeConfig` plus the `EAOrchestrator.mqh:2056` wrapper - has no
caller. So every strategy runs the chart timeframe (catalog `timeframe = PERIOD_CURRENT`), and what a strategy
reports is that: `[MOMENTUM] ... TF=` prints `m_timeframe`, the registered one. Making the table binding would move
Momentum's scalp indicator reads from the chart timeframe to M5 and Candlestick's likewise - a change in which bars
the strategies see, i.e. task #65's operator decision, not a cleanup. `[ENTERPRISE]` now says so at every symbol
init:

```
[ENTERPRISE] Manager initialized for EURUSD with 12 active strategies | profile=... |
  strategyTF=chart(PERIOD_M1) | momentumScalpTF=PERIOD_M5(stored,unconsulted) candlestickTF=PERIOD_M5(stored,unconsulted)
```

Also corrected in this batch's reading: Batch 233 said `intrabarEnabled` was written 22 times; it is 20 assignment
sites plus the field and its constructor initialiser.

**Verification:** `sync_and_compile.ps1 -All` after the deletions - eight programs, each with its own `Result:` line,
all 0 errors / 0 warnings (7.9 / 4.3 / 8.4 / 8.9 / 134.0 / 142.1 / 38.3 / 2.9 s), script exit 0, and every `.ex5`
newer than the last source edit. 5 added / 56 deleted lines across five files. Behavior is unchanged by construction:
every deleted line was a write to storage no code read, or a getter nothing called.

### Batch 233: the intrabar policy is a report field, and now it says so

Batch 232 left the question open: eleven `InpIntrabarEligibility*` inputs still write a per-strategy policy, and
Batch 231 had deleted the only code that ever tested it. This batch checks what actually gates a sub-bar vote and
prints the answer instead of guessing at it.

**What was verified, in order:**
- The stored policy (`StrategyEntry::intrabarPolicy`) has exactly one reader: the per-row registration print's
  `Intrabar:` field (`StrategyRegistryState.mqh:128`). `GetStrategyIntrabarPolicyConfig` (manager and
  `CIntrabarPolicy` copies) has no caller.
- The *entry* path never asks for intrabar evaluation: `EAOrchestrator.mqh:3467`/`:3496` pass
  `EVAL_MODE_NEW_BAR`, and `SignalGenerator.mqh:109` says so in a comment ("Only EVAL_MODE_NEW_BAR is ever passed
  on this path") - Batch 212 declined to change that, with the admission arithmetic on record.
- The one live `EVAL_MODE_INTRABAR` caller is `PositionLifecycleManager.mqh:263`, the signal-reversal exit check.
  There, the voter set is `IsStrategyLiveVoter(i)` (enabled + `liveVotingEnabled`) and the regime veto; the intrabar
  policy is not consulted.

So the honest statement is: a row's policy is `LIVE` or not in a field nobody branches on, and every enabled live
voter participates in the intrabar path whatever it says.

**Not wired, deliberately.** Gating the vote loop on `policy == INTRABAR_POLICY_LIVE` is one line, and it is the
restrictive direction: eight of the fourteen indicator rows carry `defaultPolicy = INTRABAR_POLICY_OFF` hardcoded in
`StrategyConfigBuilder.mqh` slots 14-22 - Statistical Arbitrage, FVG Scalper, Turtle Soup, Breaker Block, NY Open
Gap, Asian Range Break, Liquidity Sweep, Range Compression - and none of them has an operator input. Turning the
control on would strip those eight from the reversal-exit vote, i.e. it would make the EA *slower* to reverse a
position, on a setting the operator never chose. That is risk policy, and the Batch 217/220/222 rule says the
operator picks it, not a constant.

**Shipped: two lines of truth.**
- `[INTRABAR-POLICY] <symbol> | stored LIVE=n other=m | applied=no(report-only field; intrabar mode runs only in
  the reversal-exit check, and every enabled live voter votes there) | rows_not_LIVE=<names>` once per symbol at
  registration, built from the roster itself, so it reports what was actually stored rather than what the dialog
  shows.
- The per-row field is now `Intrabar(report-only): OFF`, because a line reading `Intrabar: OFF` in a journal is
  evidence that the strategy does not vote intrabar - and it is not.

**Verification:** `sync_and_compile.ps1 -All` after the change - eight programs, each with its own `Result:` line,
all 0 errors / 0 warnings (11.6 / 4.3 / 9.1 / 8.8 / 136.4 / 137.4 / 45.3 / 3.8 s), script exit 0, binaries newer
than sources. No gate, threshold, lot or voter set moved: 22 lines of output added, one label changed.

### Batch 232: the intrabar-eligibility mirror, and the by-name policy API no input reaches

Batch 231 deleted the two functions that read `SStrategyEntry.intrabarEligible`, which left the field on the exact
shape this repository keeps finding: **written by everything, read by nothing**. Two writers remain and both are
correct in themselves - registration at `StrategyMgrRoster.mqh` sets it to `intrabarPolicy == INTRABAR_POLICY_LIVE`
and `SetStrategyIntrabarPolicyByName` writes it beside the policy - while the only getter chain
(`CStrategyMgrRoster::GetStrategyIntrabarEligible` and the manager forwarder) had no caller once the fallback and
the policy-resolution copies were gone. Deleted: field, getter, forwarder, setter (`SetStrategyIntrabarEligible`,
manager + roster), the registration write and the by-name write. The policy is `intrabarPolicy`, one authority - the
bool was a second copy of a derived value that nothing consulted.

The same sweep found the by-name API itself unreachable: `SetStrategyIntrabarPolicyByName` and its eligibility shim
`SetStrategyIntrabarEligibilityByName` are declared, defined, and forwarded by the manager, and nothing calls the
manager. The live path is positional - `EAOrchestrator.mqh:1975` `SetStrategyIntrabarPolicyConfig(si, defaultPolicy)`
from `StrategyConfigBuilder`'s catalog rows. Both pairs (manager + `CIntrabarPolicy`) are gone, with the
`[EnterpriseStrategyManager] Intrabar policy updated:` print inside them - a line that could never have appeared in
a journal, because nothing could reach it.

Also corrected: `TrainingDataExporter.mq5:302` passed `false` under the comment `// intrabarEligible` for a parameter
that is `ENUM_INTRABAR_POLICY intrabarPolicy`. The value was right (`false` == `INTRABAR_POLICY_OFF`) and the comment
named a field that no longer existed; it now says `// intrabarPolicy = OFF`. And the append comment that called
`StrategyEntry` a "35-field" struct - it holds 40 members, and held 44 before Batch 230 - loses the number, keeping
the ordering fact that matters.

**Verification:** `sync_and_compile.ps1 -All` - eight programs, each with its own `Result:` line, all
0 errors / 0 warnings (13.4 / 6.5 / 11.0 / 9.0 / 193.4 / 163.6 / 49.0 / 3.1 s), script exit 0, binaries newer than
sources. 52 lines deleted / 2 added across five files. No policy value, threshold or eligibility decision changed:
the deleted getter had no reader, so what a symbol may do intrabar is exactly what it did before.

### Batch 231: two more consensus evaluators no caller could reach, the four sibling entry points beside them, and the seven inputs that configured all of it

#### The Batch 230 note that was wrong
Batch 230 recorded the sparse-intrabar probe path as "live" and queued three quorum fields. Both halves were
incorrect: `EvaluateConsensusProbeOnlyInternal` has no caller anywhere - its own comment at the top of the body
said "Dead path: no caller in the repo" - and the number of queued fields was wrong. The claim went into four
documents because I checked who *reads* the getters and not who can *reach* the function holding them. Corrected
here, in `README.md`, `RUNTIME_DECISION_GRAPH.md`, `SYSTEM_AUDIT_TRACE.md` and `AGENTS.md`.

#### The dead set, proved by call sites rather than by reach
- `EvaluateConsensusTwoTier` (engine decl+def, manager forwarder decl+def) and `EvaluateConsensusTwoTierInternal`:
  the manager forwarder's only occurrence outside its own definition is the engine's internal call, and nothing
  calls the manager. Tier 1 counted probe-eligible votes, Tier 2 was `EvaluateConsensusInternal` - so the
  unreachable path was a slower wrapper around the live one.
- `EvaluateConsensusProbeOnlyInternal`: no declaration outside the engine, no caller, and its
  `probeEligibleCount` gate could never have found a voter anyway.
- Four sibling entry points `GetConsensusSignal`, `GetConsensusSignalWithConfluence`,
  `GetConsensusSignalForSymbol`, `GetConsensusSignalForSymbolWithConfluence` on both the engine and the manager.
  Each forwards to the next and the last forwards to `GetConsensusSignalForSymbolWithConfluenceMode`, which is
  the one `CSignalGenerator`, `CPositionLifecycleManager` and `TrainingDataExporter` call. The surviving entry
  point is unchanged.
- Eight engine helpers whose only two occurrences are their declaration and their definition:
  `GetStrategyIntrabarPolicy`, `IsStrategyIntrabarLiveEligible`, `IsStrategyIntrabarProbeEligible`,
  `CalculateAverageStrategyMetric`, `ClampUnitValue` (the member form; the free
  `EntStrategyTypes.mqh:ClampUnitValue` stays), `GetStrategyRoleVoteMultiplier`,
  `CalculateDirectionDiversityScore`, `IsTrendingRegime`, `JoinContributorsWithContext`,
  `MaybeLogConsensusDiagnostics`. `[CONSENSUS-DIAG]` is unaffected: it prints from
  `DiagMgrCounters.mqh:649`/`:659` and from the strategy classes, not from the deleted engine method.
- The same three `CIntrabarPolicy` methods (`GetStrategyIntrabarPolicy` and the two eligibility tests) - a second
  copy under a different owner, also uncalled. Counting a method *name* is not counting a call on its *owner*
  (the Batch 215 lesson applied in reverse: here both copies were dead).

#### What died with them, which is the part an operator can see
- **`SStrategyEntry.isProbeEligible` had no writer in any build.** Grepping `isProbeEligible =` returns nothing:
  registration sets `intrabarEligible` and `intrabarPolicy`, never this. So the probe gate's
  `probeEligibleCount` was structurally zero - even wired, the probe path would have printed
  `[CONSENSUS-PROBE] No probe support (buy=0 sell=0)` on every intrabar scan and returned NONE. Field, roster
  getter and manager forwarder deleted.
- **The ADX handle cache was never populated.** `CConsensusEngine::IsTrendingRegime` was the only caller of
  `SetAdxHandleCached`, so `m_adxHandleCached` sat at `INVALID_HANDLE` for the life of every manager, and the two
  `IndicatorRelease` blocks in `AllocateHealthMonitor`'s neighbours released a handle that never existed. Field,
  both accessors, the constructor initialiser and both release blocks deleted.
- **Seven operator inputs reached no decision at all**: `InpAllowSparseIntrabarSingleVoter`,
  `InpSparseIntrabarMinQuality`, `InpSparseIntrabarMinSupportRatio`, `InpSparseIntrabarMinReadyCoverage`,
  `InpIntrabarSingleVoterMinConfidence`, `InpSyntheticLeanSparseIntrabarMinQuality`,
  `InpSyntheticLeanIntrabarSingleVoterMinConfidence`, in both root EAs. Their whole chain went with them: seven
  `SOrchestratorConfig` fields and defaults, the two per-symbol resolvers
  (`COrchestratorIntrabarPolicy::ResolveSparseIntrabarMinQualityForSymbol` and
  `ResolveIntrabarSingleVoterMinConfidenceForSymbol`) plus the orchestrator wrappers, `ClampConsensusInput`
  (wrapper and classifier static - its only two callers were the deleted lines), three manager setters, two
  manager getters, and six `CEntStrategyQuorumConfig` fields with their getters and setters
  (`m_sparseIntrabarConfidencePenalty` included: no reader *and* no writer).
- `[ENTERPRISE-CONFIG]` loses `sparse_single_voter=`, `sparse_quality=`, `sparse_support=`, `sparse_ready=` and
  `single_voter_min_conf=`; `[SYMBOL-PROFILE]` loses its trailing `sparse_quality=` / `single_voter_min_conf=`.
  Both were print-only consumers of values that gate nothing - the Batch 225 shape, where an init line makes an
  unreachable control look configured.

`INTRABAR_POLICY_PROBE` itself stays: an operator can still select it in the dialog, and it keeps exactly one
live meaning - `COrchestratorIntrabarPolicy::GetIntrabarPolicy` upgrades a PROBE policy to LIVE for a
synthetic-lean primary strategy. What is gone is the second, unreachable consumer of that same enum value.

**706 lines deleted and 10 added (net 696) across thirteen files** - `ConsensusEngine.mqh` 1216 → 800,
`EnterpriseStrategyManager.mqh` -79, `EntStrategyQuorumConfig.mqh` -42, `EAOrchestrator.mqh` -33,
`IntrabarPolicy.mqh` -34, `StrategyMgrInfrastructure.mqh` -17, and nine smaller. No threshold, veto, weight, lot
or gate moved: every deleted path was unreachable, and the live consensus entry point, its quorum arithmetic and
its logs are behaviourally identical.

### Batch 230: the solo-voter fallback was unreachable, and four controls configured it

#### The chain had no entry
`CEnterpriseStrategyManager::TryFallbackSoloSignal` has no caller anywhere; the engine's
`TryFallbackSoloSignal` is reached only through it, and `TryFallbackSoloSignalInternal` only through that. Its
own comment said "Dead path" - the repository knew, and left 242 lines of it in the binary anyway. Deleted: both
engine methods, the manager forwarder and its declaration, and the three roster getters plus the three manager
forwarders behind it.

The detail that proves it was never live rather than merely disconnected: the internal ranked every candidate by
`readinessScore x 0.4 + contextScore x 0.4 + costScore x 0.2`, read through those getters from `SStrategyEntry`
fields **no line in the tree ever wrote** - so every solo candidate scored 0.0 and would have been refused by its
own thresholds. Wiring it as written would have shipped a fallback that cannot fire, which is the Batch 213/217
lesson: revive a dead control and it silently does nothing, or worse. The four unread fields - `participation`,
`readinessScore`, `contextScore`, `costScore`, under a comment claiming they are "populated by
pipeline/consensus engine" - went with it.

The live measurement path is untouched: Batch 205's authority bonuses read `SPipelineEvidence.readinessScore /
contextScore / costScore` and average them into `SConsensusDecisionContext` (`ConsensusEngine.mqh:574-576`/`587-589` accumulate, `:772-774` publish), which is what the candidate and the lot ladder consume.

#### What still runs, and what is now queued
**Corrected by Batch 231:** the paragraph below is wrong in both halves. The probe path was not live -
`EvaluateConsensusProbeOnlyInternal` has no caller - and three fields was an undercount: seven operator inputs fed
a chain that reached no decision.
The sparse-intrabar **probe** path (`EvaluateConsensusProbeOnlyInternal`) is live and reads
`GetSparseIntrabarMinQuality` (per-voter confidence floor) and `GetSparseIntrabarMinSupportRatio` (winner share
of probe-eligible strategies). Three quorum fields fed from operator inputs have zero readers and are the next
batch: `m_sparseIntrabarMinReadyCoverage`, `m_allowSparseIntrabarSingleVoter`, `m_intrabarSingleVoterMinConfidence`.
The first two are printed by `[ENTERPRISE-CONFIG]` as `sparse_ready=` and `sparse_single_voter=`, so the init log
names controls that gate nothing - and `InpAllowSparseIntrabarSingleVoter = false` reads as "no single-voter
entries" while the probe gate admits a lone winner whenever `1 / probeEligibleCount >= 0.30`, i.e. whenever at
most three strategies are probe-eligible. Deleting or wiring those is an admission decision, not a cleanup, so it
is recorded rather than bundled here.

**Verification:** `sync_and_compile.ps1 -All` after the deletion - eight programs, each with its own `Result:`
line, 0 errors / 0 warnings, script exit 0. No input, threshold or gate moved; the deleted path had no caller, so
no candidate that used to reach the executor reaches it differently.

### Batch 229: a risk pipeline holding a collaborator it never read, and 90 comment lines that restated what the code lists

#### The eleventh pointer
`CRiskValidationPipeline::Initialize` takes eleven pointers and stores all eleven; `m_adaptiveTuner` is read by
no line in the class. The field, its constructor initialiser, the parameter, the assignment, the argument at the
single call site (`UnifiedRiskManager.mqh:518`) and the `#include` of the header that defines only that class all
went (6 executable lines). The file had recorded its own dead weight - "The 10 collaborators this class actually
reads. m_adaptiveTuner is stored but never used, so it is not gated" - and `IsWired()` obliged, health-checking
the ten and skipping the eleventh, so the class's only liveness probe agreed with the unmaintained member
instead of noticing it.

Not wired, with the reason: the tuner itself is live and well. `CUnifiedRiskManager` reads
`GetActiveRiskPerTradePercent()` at five sites, `IsConservativeMode()`, `GetThrottlePressure()` and
`GetRiskReductionFactor()`, and that last feeds `ApplyPnlRiskAdjustment`, called from two budget paths (§5.1 of
this file's history: Batch 213 declined to touch the field itself). A second handle in the pipeline would be a
second reader with no second decision to inform (§2).

#### Comment surface
Fifteen files still carried 8-13 line blocks inventorying the members, includes and parameters declared a few
lines below - the shape Batch 221 cleared from the manager files, in the files that batch did not open. 90
comment lines removed, and runs of 8+ consecutive comment lines across 335 MQL files went **17 -> 1**. Kept
because each is unrecoverable from the code: `EntStrategyTypes.mqh`'s include-position constraint, the
`m_sparseIntrabar*`-is-quorum-not-policy naming trap, the by-value config copy and by-reference engine state in
the four scalp modules, the walk-forward methodology, the exporter's permissive-risk-manager workaround (why the
exported `*_signal` columns were once all zero), and `MetaLabeler.mqh`'s 26-slot input layout - the only run left,
and the one whose header line was wrong: it said "24 features" while listing `[0]` through `[25]` into an array
`AI_MLP_INPUT` sizes at 26. Two claims corrected rather than reworded: `WalkForwardValidator.mqh` named a
`.mqh` consumer that does not include it (`WalkForwardTesterEA.mq5` is the only one), and
`FastScalpEntry.mqh`'s note read as if the L10-015 partial-fill scaling were the mechanism of AGENTS §3.1.

**Verification:** non-comment lines proved byte-identical in all fifteen comment-only files (the two risk files
are the only executable change). `sync_and_compile.ps1 -All` on the fixed harness: eight programs, each with its
own `Result:` line, **0 errors / 0 warnings**, script exit 0 - which after Batch 228 means the compiler
finished rather than that it was abandoned.

### Batch 228: the compile harness reported green for builds that never finished

#### The green came from a log with nothing in it yet
`sync_and_compile.ps1` polled each per-file log for its `Result:` line for 180 s. `MultiStrategyAutonomousEA.mq5`
takes **251.9 s** (measured this batch), so the poll always gave up, and the fallback then counted
`NN: error NN:` lines in the *partial* log - a compile still running has no error lines - printed
`File: 0 errors, 0 warnings`, and the summary concluded `OVERALL SUCCESS`. The next iteration's
`Stop-Process metaeditor64` (meant to clear a lingering worker) then killed the previous compile mid-write, so
no `.ex5` was ever produced. Both EA binaries sat at **2026-10-17 17:22 / 17:24** - the compile just before the
Batch 225 commit at 17:25 - so Batch 226 and Batch 227 were each reported "compile 8 root programs, 0 errors /
0 warnings" and had never produced a binary, while a terminal attaching the EA loaded the 225 build. How far
back the same mechanism hid earlier batches cannot be recovered: a partial log keeps no trace of the compile it
interrupted. The four fast programs (5.6-40.4 s) were genuinely verified throughout; only the two that ship
money decisions exceeded the deadline.

AGENTS.md §10.1 makes "compile passes" the first condition of Done. A verifier that cannot fail is not a gate -
this is the same shape the repository keeps hunting elsewhere: a check whose answer is produced by something
that cannot distinguish pass from never-ran.

#### Fix
`-MaxCompileWaitSec` (default 420, ~1.7x the measured slowest compile) replaces the hard-coded 180. A log that
never finalizes is now a failure - red line `no Result: line within 420 s … unverified is not clean`,
`Errors = 1` for that file - and so is a missing log. The partial-log error count only runs when the `Result:`
line exists. The script now `exit 1` on any failure, so a caller cannot read success off the exit code alone.

**Verification:** the run that proves the fix - all eight programs emitted their own `Result:` line
(18.0 / 7.2 / 12.8 / 12.1 / **257.6** / 112.0 / 40.4 / 5.6 s), every one at 0 errors / 0 warnings, and all eight
`.ex5` files were rewritten. The autonomous EA's 257.6 s is the number the old 180 s deadline could never
cover, which is why its binary had not moved in two days. Exit code is now 1 on any unfinalized or failed
compile, so `EXIT=0` from this script means the compiler finished rather than that it was abandoned.

### Batch 227: the config line echoed the inputs the quorum profile had already replaced

#### Four stored values were printed as four input values
`InitializeEnterpriseManagerForSymbol` sets min quorum, quorum threshold and both support floors from
`InpMinLiveVoters` / `InpQuorumThreshold` / `InpConsensusSupportFloor*`, then calls
`ApplyQuorumProfile(m_config.quorumProfile)` - and the profile writes those four again
(`ConsensusWeightingConfig.mqh:115-132`). `[ENTERPRISE-CONFIG]` printed the step-1 locals, so with the default
`QUORUM_BALANCED` every session logged `min_live_voters=2 | quorum_threshold=0.60 |
support_floor_newbar=0.20 | support_floor_intrabar=0.15` while the manager held **1 / 0.50 / 0.25 / 0.20**.
The error ran both directions at once: two gates looser than the journal claimed, two tighter, and an operator
who tightened one of those four inputs saw the number they typed echoed back whether or not it reached voting.
That is the §4.4 failure shape - an input that looks wired while another authority owns the quantity.

#### What the profile holds is not the whole way to the decision
Reading the fields back is still not the enforced voter count. `CalculateEffectiveQuorumParamsInternal` applies
`MIN_CONSENSUS_VOTERS = 2` on top of whatever the config holds (`ConsensusEngine.mqh:742`), so BALANCED's and
AGGRESSIVE's `minQuorum = 1` never produce a one-voter committee and no value of `InpMinLiveVoters` can. That
is deliberate - Batch 13 closed the "one lone voter is 100% consensus" path - but it means the profile's voter
floor is inert for two of its three presets, and nothing in the journal said so.
`CConsensusEngine::EnforcedMinVoters(intrabar)` (`:41`)
is now the single definition of that `MathMax`, called by the decision and by the init print instead of being
restated at either.

#### Precedence kept, made readable
The profile stays applied last. `InpQuorumProfile` is the policy the operator selects and each preset moves the
set together; letting an individual input win would silently overrule `QUORUM_AGGRESSIVE`'s 0.45 threshold and
0.15/0.10 floors, which is the relaxation that preset exists to provide. What shipped:

- `[ENTERPRISE-CONFIG]` reads those four back from the manager (`GetQuorumThreshold()`, `GetMinQuorum()`,
  `GetSupportFloorNewBar()`, `GetSupportFloorIntrabar()`).
- `[QUORUM-PRECEDENCE] <symbol> | profile=BALANCED | minQuorum input=2 stored=1 enforced=2 |
  intrabarMinQuorum input=2 stored=2 enforced=2 | quorumThreshold input=0.60 -> manager=0.50 | …` prints once
  per symbol at init, after the conservative safe-mode clamp. Not behind a `static`: changing an input re-inits
  the EA, and a once-per-load line would go stale at exactly the moment `InpQuorumProfile` changed. The clamped
  support-floor inputs became locals so the setter and the log read one expression.
- `intrabarMinQuorum` is in the line because the profile does **not** own it - it writes `minQuorum` only - so
  it is the one quorum field that genuinely comes from `InpMinLiveVoters`, and the only one AGGRESSIVE leaves
  alone.

**Verification:** No threshold, comparison or admission decision moved - the profile was already the last writer
and `EnforcedMinVoters` is the `MathMax` the decision already applied, so no committee that used to reach a
decision reaches a different one. Expect `[QUORUM-PRECEDENCE]` once per symbol at init, and different
`quorum_threshold` / `min_live_voters` / `support_floor_*` numbers in `[ENTERPRISE-CONFIG]` on identical inputs.
This batch's compile is only countable because Batch 228 fixed the harness first: the file's 257.6 s exceeded
the old 180 s window, so the run that "reported 0 errors / 0 warnings" for it had in fact never finished. Eight
programs, eight `Result:` lines, 0 errors / 0 warnings, both EA binaries rewritten.

### Batch 226: a second correlation shrink that could never run, and a drawdown halt that never said what it measured

#### The sizer's correlation path was unreachable by its own switch
`CPositionSizer::CalculateCorrelationAdjustedSize` averaged the measured positive correlation between the
request symbol and every other open position and scaled the lot by `max(0.25, 1 - avgCorr)`, with a
count-based fallback when the engine returned no reading. Only the branch at `PositionSizer.mqh:377` called it,
gated by `m_params.useCorrelationAdjustment` - which the constructor sets `false` and
`EAOrchestrator.mqh:876` also sets `false`, with no other writer anywhere. The shrink never applied to a lot,
while the `[PositionSizer] Correlation adjustment` line and `[PositionSizer] Correlation engine linked`
existed to describe it.

Deleted with the branch: both methods (72 lines), `m_correlationEngine` and its setter,
`SetCorrelationThresholds` (zero call sites) and the three params it wrote
(`useCorrelationAdjustment`, `correlationBlockThreshold`, `correlationReduceThreshold`).

Not wired, deliberately: correlation already has one sizing authority - the pipeline's REDUCE tier
(`RiskValidationPipeline.mqh:678-694`), whose `adjustedLotSize` every book now adopts (Batch 224). Switching
the sizer's own shrink on would multiply two reductions against one lot, which is the Batch 213 defect
(`CADXLotModifier` registered twice, 1.3 -> 1.69 lots) one layer down. One authority, one shrink.

`useVolatilityAdjustment` went with it: a struct field with no constructor initialiser, written `true` by the
orchestrator once and read by nothing. The volatility knob that actually exists is `useVolatilityTargeting`,
and Batch 217 already recorded both of its implementations as inert.

#### The asset-class drawdown ceiling said "family", measured the account
`ValidateTradeRequest` compared `m_circuitBreaker.GetMaxDrawdownFromPeak()` - peak-equity drawdown of the
whole account - against `GetEffectiveMaxDrawdown(symbol)`, which is that symbol's asset-class ceiling
(`SAssetProfile.maxDrawdownPercent`: Forex 10, Metals 12, Deriv volatility 10, Step 8) clamped against
`InpMaxDrawdown`. So a loss on XAUUSD can halt an EURUSD entry at 10% while the configured critical limit is
15%, and until now the refusal had no journal line of its own: it surfaced only as `result.message` and a
`FAMILY_DRAWDOWN_LIMIT` record in `MQL5/Files`.

The message now names both quantities and the new line prints them -
`[RISK-ASSET-DD] <symbol> | accountDD= | ceiling= | criticalLimit= | entry refused`. The ceiling itself is
left where the profiles put it: loosening or tightening a halt threshold is operator policy, and the rule
Batches 222 and 223 set is that a limit may stay strict but must not stay silent.

**Verification:** compile 8 root programs, 0 errors / 0 total warnings. No lot, threshold or gate moved - the
removed path was unreachable, so no trade that used to be sized one way is sized another.

> **Corrected by Batch 228:** the "0 errors / 0 total warnings" above was reported by a harness that had already
> abandoned the compile of `MultiStrategyAutonomousEA.mq5` (257.6 s against a 180 s window) and counted error
> lines in a partial log. This batch produced no binary; the EA running since then is the 2026-10-17 17:22
> build, which does not contain the `[RISK-ASSET-DD]` line this entry says it prints. The deletion itself is
> verified in the source and in the eight-program rebuild of 2026-10-19.

### Batch 225: a threshold that only ever reached the log, and four fields with no reader

#### `InpAIStandaloneRelaxedConfidence` moved a printed number, not the gate
`CCandidateBuilder` tracks the hybrid gate per symbol: after `InpHybridGateRelaxAfterCycles` (5) scans with no
indicator contributor it opens the gate and prints `[HYBRID-GATE-RELAXED] <symbol> | ... AI threshold A -> B`.
The value it tests was never B: the bar that binds is `CLiveAuthorityResolver::Resolve`'s own
`m_aiStandaloneMinConfidence` (`LiveAuthorityResolver.mqh:215`, with a hardcoded 0.55 when an indicator
contributed), and the orchestrator passed only `m_config.aiStandaloneMinConfidence` to `Configure` - the
relaxed field's only readers were a `StringFormat` and a JSON literal. Batch 141-era notes in
`docs/changelogs_batch102-169.md` record it as wired; the wiring stopped at the print.
The builder now exposes `EffectiveStandaloneConfidenceFloor(symbol)` and the orchestrator hands that floor to
the resolver through `SetStandaloneConfidenceFloor` before each `Resolve`, so the AI-standalone bar is 0.60
while the gate is open and 0.65 when it is restored, and `[AUTHORITY-REJECT] ... LOW_CONFIDENCE_x<y` reports
the number actually applied. `[AUTHORITY-CONFIG] effective:` now ends in `standaloneConf=`, so a session can
confirm the input reached the gate instead of the log.

#### The dead state removed with it
- `InpPortfolioMaxPositionsPerSymbol` (default 3) reached `m_portfolioMaxPositionsPerSymbol`, which no code
  read: `CheckSymbolPositionLimit` bounds the same quantity with `InpMaxPositionsPerSymbol` (5). Two inputs,
  one limit, the tighter one inert - the Batch 38 shape again. The input, the config field, the `Configure`
  argument and the field are deleted; 5 is the real number and now the only one.
- `CRiskTieredCorrelation` held `m_correlationReduceThreshold` / `m_correlationBlockThreshold` pushed from
  config and never read - the pipeline enforces both tiers from its own copy. Its own header comment said so.
  `SetThresholds` takes the entry threshold alone now, and both URM call sites changed with it.
- `SValidationResult::confidenceMultiplier` had one writer, `= 1.0`, restored after `ZeroMemory` precisely
  because `StrategyBase` multiplied confidence by it. No gate ever set anything else, so the multiply was a
  no-op with a footgun attached (a forgotten restore would zero every signal's confidence). Field, write and
  multiply are gone.
- `SPositionSizingParams::correlationAdjustment` (written `1.0` once, zero reads) and
  `STradeCandidate::liveAuthorityAllowed` (written twice, zero reads - the orchestrator branches on the local
  `authority.allowed`) are deleted. `ResolveLiveAuthority` stays: it has a live caller and its comment already
  says it is a stub that gates nothing.

**Verification:** compile 8 root programs, 0 errors / 0 total warnings. Behaviour change is the intended one:
AI-standalone candidates on indicator-quiet symbols are now admitted between 0.60 and 0.65 confidence where
they were refused, and no other threshold moved. Not runtime-observed - no journal newer than 2026-09-23.

### Batch 224: one non-family capped six symbols, and three books that threw away the risk gate's answer

#### The family position cap treated "not a Deriv synthetic" as a family
`CDerivAssetProfiler::DetectFamily` tests 18 Deriv name predicates and answers `DERIV_UNKNOWN` for everything
else, and the per-family position cap in `RiskValidationPipeline.mqh:597-648` counted that as a family. On the
default universe EURUSD, GBPUSD, USDJPY, AUDUSD, XAUUSD and BTCUSD therefore shared one bucket capped at 3
positions *together* - tighter than `InpMaxPositionsPerSymbol = 5` and `InpMaxPositionsTotal = 15`, and not
visible anywhere as a policy. The block's own comment already said "all unclassified symbols share one bucket
and the -1 test is dead" and enforced it anyway. The gate now runs only when the request resolves to a real
family, so those six symbols are bounded by the caps that name them.

Left as it was, with the reason: the position scan still counts *every* owner's positions toward a real
family's cap. This file has no ownership test for that loop (the correlation scan in the same function uses
`posMagic == 0 || posMagic == eaMagicNumber`, which since Batch 197 excludes the scalp/grid/spike magic
bands), and magic-band ownership belongs to `CPositionLifecycleManager::IsEAOwnedMagic` - copying it here
would create a second authority over who a position belongs to.

#### Three engine books read the gate's verdict and ignored its arithmetic
`[ATR-SCALP] REJECTED`, `[GRID-RECOVERY] REJECTED` and `[SPIKE-HUNT-TRADE] REJECTED` all printed
`reason=` from `SValidationResult.reason`, which `ZeroMemory` clears at `RiskValidationPipeline.mqh:295` and
which **no line in `Core/Risk/` ever assigns** - the populated field is `.message`, which is what the
consensus path (`CandidateBuilder.mqh:555`), `StrategyBase` and Statistical Arbitrage already print. So every
refusal on those three books said nothing about why. All three also tested only `.approved` and then shipped
the lot their own sizing had produced, so the correlation REDUCE shrink, the lot-floor adjustment and the
recomputed `riskPercent` were discarded there while the fast scalp has adopted the shrink-only version since
Batch 192.

They now print `.message` and adopt `adjustedLotSize` shrink-only, logged as `[ATR-SCALP-RISK-ADJUSTED]`,
`[GRID-RISK-ADJUSTED]` and `[SPIKE-RISK-ADJUSTED]` in the shape `[SCALP-RISK-ADJUSTED]` already uses. For the
grid this is safe in the direction that matters: `CGridRecoveryEngine` records the level's `lotSize` *after*
the send, so the level table and the position agree, and later levels still derive from `baseLot` - only the
level the gate shrank changes.

#### Documented rather than wired: the cluster marker
`ParseClusterCodeFromComment` looks for a `K:<code>` marker that no producer writes
(`CTradeAttributionManager::BuildClusterTaggedTradeComment` has no call site), so every existing position
decodes to `"N"`: `[RISK-CLUSTER] open_positions=` is a same-symbol count, and `[RISK-CLUSTER-SYNC]` at init
reconciles nothing. Batch 200 recorded this and declined to wire it - the position comment is the ownership
discriminator Batches 196 and 197 rely on, and decoding the cluster out of it would also hand the
opposing-position mutex the same-cluster case it currently exempts, which is a loosening dressed as a
completion. `AGENTS.md` section 6 claimed `[RISK-CLUSTER-SYNC]` "now counts clusters that can actually be
entered"; that sentence was false and is corrected here.

**Verification:** compile 8 root programs, 0 errors / 0 total warnings. Not runtime-observed (no journal newer
than 2026-09-23; the EA stays unattached). Expect `family=DERIV_UNKNOWN` to disappear from `[RISK-FAMILY-POS]`
and from refusals on the six non-Deriv symbols, more `[ATR-SCALP]`/`[GRID-RECOVERY]`/`[SPIKE-HUNT-TRADE]`
lots arriving smaller than the engine's own sizing, and those three refusals finally carrying a reason.

### Batch 223: three risk ceilings that could not bind, each of them letting more through than configured

All three were verified against the working tree. Each one is a limit written so that its own arithmetic
made refusal unreachable, and in every case the unreachable direction was the protective one.

#### The drawdown shrink was undone by a ceiling that could never fail
`ApplyDrawdownScaling` (`CandidateBuilder.mqh:767`) rounds a shrunken lot up to the broker
minimum only while that round-up stays inside `InpMinLotRiskMultiplier`. It measured the round-up as
`floorMult = brokerMinLot / lotSize` - and the enclosing branch requires `lotSize > brokerMinLot`, so that
ratio is below 1.0 by construction, against a ceiling of 15.0. The test could never fail, so every
anti-martingale shrink that under-shot the minimum was silently replaced by a full minimum-size lot, and
`[RISK-ADAPT] ... lot=A->B` printed the widened result as the adaptation. Now measured the way
`RiskValidationPipeline.mqh:502` measures the same thing (`brokerMinLot / newLot`, the factor the shipped lot
exceeds the intended one); above the ceiling the candidate is refused with
`[RISK-GATE-REJECT] ... reason=drawdown_lot_below_min`, and the caller stops before the momentum scaler and
the unconditional round-up at `:502-504` can reinstate a lot.

#### The post-adjustment daily-risk projection could never exceed the limit it was compared with
`GetEffectiveDailyRiskUsedPercent` ends by clamping its answer to `maxDailyRiskPercent` (so mark-to-market
loss plus entry exposure cannot read 2x the limit in *reporting*), and `RiskValidationPipeline.mqh:738`
tested `projectedDailyRisk > m_config.maxDailyRiskPercent` on that clamped value: arithmetically impossible.
The gate that is supposed to stop the lot the candidate actually ships from breaking the daily budget has
never refused anything, and `DAILY_RISK_WOULD_EXCEED` exists only as a JSON event that cannot be emitted. Now
`>=`, the same operator the pre-approval budget gate at `:365` uses against the same clamped value, with a
journal line (`[RISK-DAILY-LIMIT] ... phase= effective= + new= >= limit= | lot=`) because until now this
refusal was only ever a `result.message` and a file record.

#### Per-cluster risk caps were absolute percentages, so the operator's ceiling bound only the clusters with no row
`CRiskClusterBudget` stored `"T" -> 10.0` and `"R" -> 5.0` as percents, and `GetClusterRiskCap` returned the
stored value instead of the configured one. `InpRiskMaxClusterExposurePct` (default 5.0, and the only writer
of `m_maxClusterRiskPercent` through `ConfigureClusterGovernance`) therefore reached clusters "S" and "N" -
the ones with no row - while trend entries ran at twice the configured cluster exposure whatever the operator
set. The rows are now factors (2.0x trend, 1.0x reversion) of the configured cap: identical at the default
5.0% and bounded by the number in the inputs dialog at any other value. `[RISK-CLUSTER-CAP-PER]` prints the
factor and the base it multiplied. `SetClusterRiskCap` - the budget method and the `CUnifiedRiskManager`
forwarder - had zero call sites and no input feeding it, so both are deleted rather than wired.

#### Checked and left alone, with the reason
`CRiskMarginHealth`'s 200% margin floor and 0.8 free-margin ceiling, and `CPortfolioRiskManager`'s
`m_cvarMaxRisk = 0.10`, are constants with no setter call site and no operator input; their own comments say
so, and giving them inputs is a policy decision rather than a fix. `IsCVaRLimitExceeded` also fails open
below 20 equity-curve samples, which is 20 minutes of live ticking.

**Verification:** compile 8 root programs, 0 errors / 0 total warnings. Not runtime-observed: no journal is
newer than 2026-09-23 and the EA stays unattached this round. Expect fewer `[RISK-ADAPT]` lines whose `lot=B`
exceeds `A`, and `[RISK-DAILY-LIMIT]` / `reason=drawdown_lot_below_min` refusals that did not exist before.

### Batch 222: three consensus gates that could never pass, and one veto whose answer was thrown away

Four refusals in the entry path were structurally permanent rather than market-dependent. All four were
verified against the working tree, and the first two are the unshipped half of findings already recorded in
`.workbuddy/audit/03-engineer-profitability.md`.

#### Conflict deadband 0.05 demanded unanimity ([PROFIT-02], half-fixed since)
`conflictRatio = losingVotes / (winningVotes + losingVotes)` under `if(losingVotes > 0)`
(`ConsensusEngine.mqh:1047-1056`) cannot be smaller than one dissenter over the votes cast: on the default
roster of 14 indicator and 5 AI rows that floor is `1/19 = 0.0526`, which exceeds `0.05`. Every decision with
a single dissenting strategy was therefore vetoed and only a unanimous committee could trade - from a
portfolio deliberately partitioned into `TREND_CLUSTER` and `MEAN_REVERSION_CLUSTER`, which exist to disagree.
The audit's own remedy was applied to the numerator in an earlier batch and the class default was raised to
`0.35` under the marker `[PROFIT-02]` (`EntStrategyQuorumConfig.mqh:134`), but `InpConsensusConflictDeadband`
and `OrchestratorConfig` both still carried `0.05`, which overwrites the class at init, and `[VALIDATION]`
rejected anything above `0.20` so an operator could not even set the audited value.
- `InpConsensusConflictDeadband` default `0.05 -> 0.35` in both root EAs, and `OrchestratorConfig` with it.
- The accepted range is `[0.05, 0.50]` - the interval `SetConflictDeadband`'s clamp can actually honour, and
  the value below which the gate is arithmetically a unanimity requirement.
- `[CONSENSUS-VETOED]` now prints `votes=W-L`; `[CONSENSUS-QUORUM]` now prints `conflictDeadband=` and
  `finestDissent=1/eligibleVoters`, so a deadband below one vote is visible instead of inferred.

#### The ready-weight floor was unreachable whenever the regime snapshot was unconfirmed
`GetRegimeCategoryMultiplier` returns a flat `0.30` stand-aside for `!snap.valid`
(`ConsensusEngine.mqh:435-436`), and the ratio it feeds is a weighted mean of
`confidence x participation x reliability x regimeMult` (`:896, :966`). With `confidence <= 1.0`,
`participation <= 1.05` and `reliability <= 1.15` that product tops out at `0.36225`, under the operator's
`InpConsensusMinReadyWeightRatio = 0.40`: such a symbol abstains on every scan and the refusal blames an
unready committee. Worse, `CRegimeEngine::Update` - the only writer of `snap.valid` - had exactly one live
call site, inside the pipeline's *optional* RegimeCostGate (`SignalPipelineFilter.mqh:44`, reached only when
`m_filters.regimeCostGate.enabled`, `UnifiedSignalPipeline.mqh:388/406`). Switch `InpPipelineEnableRegimeCostGate`
off, or get every voter filtered before that gate, and no snapshot ever turns valid anywhere: zero consensus
trades, universe-wide.
- `CEnterpriseStrategyManager::RefreshMarketRegime`, already called at the top of every consensus scan, now
  calls `Update()` on the first live voter's timeframe when the snapshot is invalid. It cannot disagree with
  the gate's own reading, and it is a no-op the moment the gate is supplying snapshots.
- The refusal prints `regime=confirmed` or `regime=UNCONFIRMED(stand-aside 0.30 caps ratio at 0.36)`.

#### The ATR crisis veto answered itself
`CheckExogenousFilters` set `exogenousPass = false`, printed `[POST-CONSENSUS-FILTER] filter=atr_ratio`, then
`return true` (`PostConsensusValidator.mqh:276`). The caller vetoes only on a false return and never reads
`exogenousPass`, so the configured ATR14/ATR50 crisis ceiling (2.0 FX, 2.5 synthetic) has never refused a
trade, while `AGENTS.md` section 6 cites that tag as evidence of filtering. It returns `false` now. The sibling
spread-vs-ATR branch was always correct; only this one was inverted.

#### atrRiskScale: a halving no lot ever received, deleted rather than wired
`result.atrRiskScale = 0.5` in the `atrRatio > 1.5` band had zero readers - `validation.passed` is the only field
`EAOrchestrator.mqh:3527` consumes - while `[RISK-VOL-GATE] ... action=halve_risk` announced it every time.
Not wired: `CCandidateBuilder::CalculateStops` sets the stop to `ATR14 x 2.0` (FX) or `x 1.5` (synthetic) at
`CandidateBuilder.mqh:629-635` and the lot is fixed-fractional over that distance, so a ratio of 1.6 already
shrinks the lot to about `0.62x`. Multiplying by 0.5 on top would double-count one measurement at `0.31x`.
The field and its constructor initialiser are gone, the log says `action=none(atr-scaled stop already shrinks
the lot)`, and the file header no longer claims the validator reduces risk.

#### Recorded, not rewired
`supportFloor` compares against `winningScore / (winningScore + losingScore)`, which is above 0.50 by
construction (an exact tie returns earlier as `[CONSENSUS-TIE]`), so no configured floor can refuse anything
and `InpConsensusSupportFloor*` binds nothing. The `[CONSENSUS-QUORUM]` line now marks it `inert`. Measuring
support against the whole eligible roster would make it live and would refuse thin-support decisions -
operator policy, in the same family as the Batch 220 quality-scale and Batch 217 vol-target refusals.

**Verification:** compile 8 root programs, 0 errors / 0 total warnings. Consequences to expect in a fresh
journal, none of which has been observed yet because no journal is newer than 2026-09-23 and the EA is not
attached this round: fewer `[CONSENSUS-VETOED] Conflict ratio` lines and more `[CONSENSUS-DECISION]`;
`[CONSENSUS-REJECT] Ready weight ratio` disappearing on symbols whose regime now fills in; and
`filter=atr_ratio` lines that are no longer followed by a position.

### Batch 221: fourteen module headers that ran to 9-18 lines now run to 3-7

The tree held 208 comment runs of four or more lines (1,200 lines), and the longest were file headers that
enumerated the members or includes declared a few lines below, listed a function's parameters one per line
after the signature already named them, or repeated the same four-line include caveat verbatim across seven
`EnterpriseStrategyManager` satellites. Mandate: keep what a reader cannot recover from the code.

#### Compressed, with the constraint kept
Sixteen files. What survives in each is the ownership fact and the exception, not the inventory: that
`CTradeStatsTracker` is held by value with no back-pointer while `CTradeManager` keeps its own legacy mirrors
and re-reads them after every `RecordTrade`; that `CConsensusWeightingConfig` mutates the manager through
public mutators and why the atomic quorum setters could not move with it (the consensus core reads the mirrored
fields directly); that a roster index stays valid only until `ClearRoster()`/`Deinit`; that `SPositionState`
must remain a top-level struct declared after `TradeManager.mqh` because include order is what makes it
visible; that the status reporter's per-cycle counters are arguments because MQL5 cannot capture a volatile
local by pointer. Dropped: member lists, the `PyBridge*`/`Trend*`/`SpikeHunter*` module maps (they are the
`#include` lines), the parameter glossary above `AssembleHeartbeatStatus`, the `*** BEHAVIOUR CONTRACT ***
banner`, and the include caveat collapsed to one line in all seven files.

**Verification:** 120 comment lines removed (runs of 8+ lines: 31 -> 17), executable lines proved
byte-identical per file against a pre-edit snapshot, and compile 8 root programs at 0 errors / 0 total
warnings. No code, no behaviour, no log text changed.

### Batch 220: the consensus quality floor measures registration weight as well as confidence

`buyDirectionalQuality += stratConf * weight` (`ConsensusEngine.mqh:890`) divided by `buyVotes` (:916) is not
a weighted mean - the denominator is a headcount. With the default roster's registration weights (1.0
Momentum, 1.2 Trend, 1.5 Support/Resistance, 1.8 Mean Reversion, 2.0 Volatility Breakout) the metric runs
about 1.5x the committee's mean confidence, so `InpValidatorNewBarMinQuality = 0.68` - discounted to 0.612 for
a full quorum by `GetAdaptiveQualityThreshold` - admits a mean confidence near 0.41. The same inflation
carries into `confidence = MathMin(0.95, winningQuality * 0.8 + supportRatio * 0.2)` (:1048), which is why that
number sits at its ceiling for high-weight committees and why every downstream confidence gate looks slack.

#### Measured and reported, not rescaled
Changing the divisor to the summed weight makes both quantities dimensionally honest - and raises the admission
bar on every symbol at once, because a 0.612 threshold would then mean 0.612 *confidence* instead of roughly
0.41. That is a decision about how strict consensus should be, which the operator owns, so it is recorded in
`SYSTEM_STRUCTURE.md` section 4 with the arithmetic rather than guessed at here. Precedents: Batch 217 left
volatility targeting unwired for the same reason, Batch 213 the Kelly re-arming, Batch 201 the participation
score.

#### What shipped
A `filter=quality_gate` refusal now prints `conviction=` next to `quality=`, so the gap - the part of the score
the weights supplied - is readable in the journal. One added format argument and its value; no threshold,
no comparison, no admission decision changed. Compile 8 root programs, 0 errors / 0 total warnings.

### Batch 219: `dominantCluster` had six readers and no writer, so two designed branches never ran

`ConsensusEngine` resolves the winning side's cluster on every decision that reaches consensus
(`ResolveDominantCluster(winningContributors)`, line 1069) and publishes it as a **string** for the contributor
record. The enum field on the decision context - `SConsensusDecisionContext.dominantCluster` - was assigned by
nothing, so every reader saw the struct default `STRATEGY_CLUSTER_NONE` forever. Two of those readers are
behaviour, not reporting:

- `CandidateBuilder::CalculateStops` selects the minimum R:R floor from the cluster: 2.0 generally,
  `1.5` for `MEAN_REVERSION_CLUSTER` (`Configure(2.0, 1.5, ...)` at `EAOrchestrator.mq5:1509`). Mean-reversion-
  dominant entries have therefore had their take-profit stretched to the general floor since the branch was
  written, instead of keeping the strategy's own target when it sits between 1.5R and 2R. Stop distance, lot
  and per-trade risk are untouched - the floor only ever raises TP, so this shortens forced TP extension.
  One consequence to expect: `costRatio = spread / takeProfitPips` is now measured against a shorter TP, so a
  mean-reversion entry whose spread cannot be covered at 1.5R refuses as an execution-cost veto. That refusal
  is the arithmetic working, not a new bug.
- `PositionLifecycleManager`'s structural-invalidation exit fires on `dominantCluster == STRUCTURE_CLUSTER`
  with confidence >= 0.45 - and could never fire. `InpEnableStructuralInvalidation` defaults to true, so the
  operator has had a switch connected to nothing.

#### The exit is reachable, but it may not overrule the abstains above it
Wiring the field alone would have made the structural branch a way to bypass two deliberate decisions in the
same function: `[SRE-LAST-STAND]` leaves a deeply-lost position to the hard SL, and a position younger than
`InpSignalReversalMinTimeSec` is not reversed out of. The branch now requires neither to have abstained. The
profit guard is deliberately **not** in that list - its own comment says a blocked SRE hands the decision to
structural invalidation, and that handoff is what this batch finally delivers.

#### Also corrected: three documents claimed the mean-reversion floor was 1:5
It is 1.5 (`m_minRRMeanReversion`), and 1:5 would have been a 3.3x longer target. The Batch 97 summary,
`SYSTEM_STRUCTURE.md` and `RUNTIME_DECISION_GRAPH.md` all carried the misread. `changelogs.md` Batch 206 had
it right.

**Verification:** compile 8 root programs, 0 errors / 0 total warnings. `[STRUCTURAL-EXIT] <symbol> | trend
invalidated | conf= | lossR=` becomes reachable for structure-cluster positions, and `[CANDIDATE-BUILDER]`
reports `MinRRMeanRev=1.5` as the value that can now apply. No risk gate, stop distance, lot calculation or
magic ownership changed.

### Batch 218: the heartbeat block had no printer, and every log tag in the five documents got checked against the tree

AGENTS.md section 6 opens with "verify `[HEARTBEAT]`". No `Print` call site in this repository produced that
line, or `[HEARTBEAT-FUNNEL]`, `[CONVERSION-RATES]`, `[NO-SIGNAL-ALERT]`, `[RISK-BUDGET]`,
`[HEARTBEAT-POSITIONS]`, `[HEARTBEAT-ASSET-CLASS]` or `[HEARTBEAT-FAMILY]`. `CDiagMgrHeartbeat` computed
every field of all eight - scans, intrabar, no_signal, validator_reject, risk_reject, trades_opened,
spike_events, `pause_active` - and passed them to `CJsonLogger::LogInfo`, which appends to a file under
`MQL5/Files`. The format strings sat in `Core/Utils/LogMacros.mqh` unused: 42 macros declared, 37 with no
call site. The heartbeat is the only aggregate the operator has for "is the scan loop running and producing
nothing", so a session could sit at 100% no-signal and the journal would show steady `[SCAN-BUDGET]` lines
and no stall evidence.

#### Emitted from the same values the JSON record already uses
All eight now `PrintFormat` the existing macro at the same call site as the JSON write, so no field is
measured twice, no value can diverge between the two sinks, and no decision path changed. The verbose
per-symbol lines stay behind the existing `ShouldLogVerbose()` gate. `[RISK-FAMILY-POS]` also prints now: the
per-family position cap (`RiskValidationPipeline.mqh:629`) was the only gate return that refused through
JSON alone, so a family capped at 2 of 2 open positions looked identical to a strategy that had stopped
voting.

#### The remaining 29 macros are deleted
Ten duplicated tags the code already prints as literals (`[SIGNAL-REJECTED]`, `[AI-VOTE]`, `[CONSENSUS-DIAG]`,
`[AUTHORITY-REJECT]`, `[AUTHORITY-REDUCED]`, `[CANDIDATE-BUILDER]`, `[COMPOUNDING-TIER-MILESTONE]`,
`[ADX-MODIFIER]`, `[RISK-ADAPT]`, `[MOMENTUM-SCALE]`) - the tag is live, the macro was a second copy of it.
Eleven were `LOG_JSON_*` / `LOG_PERFORMANCE` / `GENERATE_CORR_ID` wrappers around direct calls nobody routed
through them. Seven named a tag with no emitter and nothing computing a payload: `[CONSENSUS-ROOT]`,
`[CONSENSUS-STRATEGY]`, `[CONSENSUS-ROLE]`, `[CONSENSUS-CLUSTER]`, `[FAMILY-WEIGHT-VOL]`, `[NN-HEALTH]`, and
`[AI-VOTE-MISSING]`. The last of those was the only judgment call: the staleness test is per symbol per
adapter type, so wiring it would print up to 52 lines a minute on a fully-stale AI configuration. The JSON
`AIVoteMissing` record stays, and `[AI-VOTE]` absence for a symbol is itself the journal signal.

#### The document sweep
Batch 215 swept the tags and corrected the two sections it was editing. This batch swept all five documents
against a corrected evidence rule - a tag counts as printed when a `Print`, `PrintFormat`, `Alert`, `LOG_IF*`,
`CJsonLogger::Log*` or `CSubsystemLogger::Log` call reaches it, searched over a three-line window because the
format string often sits below its `PrintFormat(`. Roughly 250 lines corrected. Four findings are worth
keeping:

- Two whole design sections named classes and files that do not exist: `CPartialCloseManager` +
  `Strategies/UnifiedICTFiles/PartialCloseManager.mqh` and `CTimeframeConfluence` +
  `Strategies/UnifiedICTFiles/TimeframeConfluence.mqh`. A reader would have opened a nonexistent path. The
  live owners are `[PARTIAL-PROFIT]` / `[SAFE-MODE-PARTIAL]` / `[SCALP-PARTIAL]` / `[ATR-SCALP-PARTIAL]` and
  `CTimeframeConsistency` (`Core/Signals/TimeframeConsistency.mqh`, prints `[TimeframeConsistency]`).
- OFI never adjusted a strategy weight. `COrderFlowImbalanceEngine::GetImbalanceDirection()` has no consumer;
  the 1.2x boost / 0.7x penalty recorded in three documents was designed and never built. OFI acts
  post-consensus as a directional veto (`[POST-CONSENSUS-FILTER] filter=ofi_contradiction` at `|ofi_z| >= 1.0`,
  `filter=ofi_mild_contradiction_allowed` below it).
- VPIN never reduced strategy weights either. EXTREME refuses after consensus and HIGH/MEDIUM shrink the lot
  through `[VPIN-MODIFIER]` (Batch 213); the `[VPIN-HIGH]`/`[VPIN-MEDIUM]`/`[VPIN-BLOCK]` lines cited as
  evidence print nowhere.
- `[EXECUTION-MODE]`, `[ACCOUNT-CAPACITY]`, `[AI-TOPOLOGY]`, `[SIGNAL-VALIDATED]`, `[CAPACITY-EXTERNAL]`,
  `[RISK-CAP]`, `[SCAN-NO-TRADE]`, `[AI-MODE-BONUS]`, `[TERMINATION-SNAPSHOT]`, `[SPREAD-COST]`,
  `[SMART-ROUTING]`, `[AUTO-MODE]`, `[DAILY-LOSS-HALT]`, `[RR-REJECTED]`, `[BATCH103]`, `[SIGNAL]`,
  `[DBG-RET0]`, `[DRAWING-STATS]`, `[DRAW-COORD]`, `[SCALP-COST-VETO]`, `[SCALP-SIGNAL]`, `[SCALP-EXEC]`,
  `[TRADE-SUCCESS]`, `[TRADE-STATE]`, `[TRADE-CONFIRMED]`, `[TRADE-EXECUTION]`, `[FILL-DIFF]`,
  `[SHADOW-TRADE]`, `[PROFILER-DETECT]`, `[HURST-ENGINE]`, `[OU-ENGINE]`, `[OFI-ENGINE]`, `[VPIN-FILTER]`,
  `[SPIKE-HUNT-DETECTED]`, `[SPIKE-COOLDOWN]`, `[SPIKE-HUNTER-STATS]`, the four `[GRID-RECOVERY-ENTRY|
  LEVEL|CLOSE|DRAWDOWN]` names, the four `[ATR-SCALP-ENTRY|EXIT|COOLDOWN|SPIKE-WINDOW]` names and the dotted
  `[MR-*]`/`[TTM_SQUEEZE]`/`[BREAKOUT_RETEST]`/`[CANDLE_CONFLUENCE]` rejection names all print nowhere; each
  document line now names the tag that exists instead, or says plainly that none does.

#### Method note for the next audit
`git log -S"[TAG]"` is not usable evidence in this repository: git-lfs is configured as the content filter, so
pickaxe hits come back for strings that never existed in a checkout and a "this tag was removed" story can be
built out of filter noise. Every claim in this batch rests on the current tree - `Print`/`LOG_IF`/logger call
sites over all `.mq5`/`.mqh` files - and the documents say "prints nowhere" rather than "never existed" where
only the tree can be proved.

**Verification:** compile 8 root programs, 0 errors / 0 total warnings. No input, no threshold, no lot, no
gate and no exit changed; the diff is eight new `PrintFormat` calls, one new refusal print, 29 deleted macro
declarations, and document corrections.

### Batch 217: volatility targeting measures a scalar every bar that no lot ever reads

`InpEnableVolTargeting` (true on the live EA), `InpTargetVol` (0.15), `InpVolMinScale` (0.2) and `InpVolMaxScale`
(3.0) build a real, working volatility model: the math hub creates one `CVolatilityTargeting` per symbol,
configures it with those three numbers, and calls `Update()` on it every cycle
(`OrchestratorMathEngineHub.mqh:649`) - ATR-annualised vol, a 100-bar realised vol, an EWMA blend, a rolling
percentile, and a scalar `target / ewmaVol` clamped to the operator's own `[0.2, 3.0]`. It then prints that
scalar into the journal once a minute per symbol.

**Nothing reads it.** `GetVolScalar()`, `GetScaledSize()`, `GetRealizedVol()`, `GetEwmaVol()` and
`GetVolPercentile()` have zero call sites in the repository - the only same-named getters belong to
`CFourStateRegimeDetector`. So a journal can show `[VOL-TARGET] EURUSD | ... | scalar=1.480 | highVol=false`
while every lot that symbol trades is sized as if the number did not exist.

There is a second, independent implementation of the same idea, also inert: `CVolatilityTargetingModifier` inside
`CPositionSizer`, registered only `if(m_params.useVolatilityTargeting)`. That field is set in
`SPositionSizingParams`' own constructor to `false` and assigned from nothing else in the tree, so the guard has
never been true, `CalculateVolatilityTargetSize` has always fallen through to `CalculateFixedRiskSize`, and the
modifier class - which does its own D1 ATR annualisation - has never multiplied a lot. The two implementations
also disagree on the ceiling: the modifier clamps to 0.25-2.0 with a hard-coded 0.15 target, the engine to the
operator's 0.2-3.0.

#### Measured, then reported - not wired
Wiring either one as currently configured is a **risk widening**, which is why this batch changes the reporting
and not the sizing. An annual target of 0.15 against typical FX daily ATR/price of 0.5-0.8% (annualised ~8-13%)
gives `scalar = 0.15 / 0.10 = 1.5`, so the first trade the wired path sizes would be half again the lot the risk
math chose, in calm conditions by design, and up to `3.0x` because `InpVolMaxScale` defaults to 3.0. That is the
opposite of the direction every earlier sizing batch has moved in (Batch 213's ADX de-duplication and VPIN
re-arming both reduced lots; Batch 190's clamp caps what ships). Turning a protection into a lever by picking
constants nobody chose is how a sizing path changes character without anyone deciding it should.

So: `[SIZING-CHAIN] ... | vol_targeting=inert(InpEnableVolTargeting feeds a measured scalar no lot reads)` at
every start, and `[VOL-TARGET] ... | applied=no(no sizing consumer)` on the snapshot line, so a reader of the
journal is not left to infer that the number they are watching moves nothing. What the operator wants - target
vol, and whether the scale should be allowed above 1.0 at all - is recorded in `SYSTEM_STRUCTURE.md` §4 with both
candidate routes, because choosing the ceiling is a risk-policy decision and the EA now says plainly which way it
is currently set.

`sync_and_compile.ps1 -All`: 8 root programs, 0 errors / 0 total warnings.

### Batch 216: the scalp signal cache did 78 buffer reads a minute for numbers nobody reads

`CScalpSignalCache` is the fast path's per-symbol indicator store, and it has exactly one consumer:
`CFastScalpSignal::EvaluateFromCache`, reached through `GetCache`. That consumer reads eight fields -
`emaFast/emaSlow` and their previous-bar values, `atrValue`, `rsiValue`, `spreadPoints`, `lastBarTime` - plus
`isValid`. The struct carried twenty-one.

#### 1. Six indicator series computed on every new bar for no reader
`UpdateOnNewBar` per symbol read a 6-bar ATR series (for `atrPrev`, "ATR 5 bars ago for direction"), three
Bollinger buffers (`bbUpper/bbLower/bbMiddle`), ADX (`adxValue`) and a 21-bar volume series summed in a loop
(`volumeCurrent/volumeAvg`). None of those six fields is read anywhere in the repository. On the default
13-symbol universe at M1 that is 78 `CopyBuffer` calls and 13 summation loops a minute, executed inside the tick
path, to maintain numbers no decision consumes - plus three shared indicator handles per symbol acquired at
init (`GetBandsHandle`, `GetADXHandle`, `GetVolumesHandle`) for the same reason.

Deleted: the six fields, the four handle slots, the reads, the `CopyBufferN` helper that only they used, and the
period fields feeding those handles (`m_bbPeriod`, `m_bbDeviation`, `m_adxPeriod`, `m_volumePeriod`).
`bidPrice`/`askPrice` also go: `UpdateTickValues` wrote them every tick and only its own next lines read them,
so the spread is now computed into `spreadPoints` from locals.

#### 2. `SetPeriods` was the only way the two paths could disagree, and nothing called it
`SScalpIndicatorCache`'s periods and `SScalpConfig`'s drive the same crossover from two places, so a divergence
would mean the fast path and the slow path evaluate different EMAs on the same symbol. They match today because
`SScalpConfig.fastEMA/slowEMA/rsiPeriod` are literals (5/13/7, `EAOrchestrator.mqh:1303`) and the cache's own
defaults are the same numbers - and `SetPeriods`, the only route to changing the cache's copy, had no caller. It
is deleted rather than wired: wiring it would create the divergence it was written to allow, with no operator
input on the config side to keep them paired. If the periods ever become inputs, both paths must read one place.

Also deleted as uncalled: `HasNewBar`, `EnsureInitialized`, `GetCacheCount`, `IsInitialized`, and `SetScalpSetup`
- whose single call site wrote `active=true, setupType=1` for every symbol at init into two fields no reader
existed for. `setupType` (`0=none, 1=momentum, 2=spread, 3=breakout`) was the last trace of the three-scalp-
strategy design the documents still describe, below.

#### 3. Documentation: two scalp strategies have no file, the third is not in the build
`SYSTEM_STRUCTURE.md` §2.17 and `RUNTIME_DECISION_GRAPH.md` both listed three scalp strategy classes as what the
engine runs. `CScalpMomentumStrategy` and `CScalpSpreadStrategy` have **no file in the repository** - the paths
cited do not exist. `CScalpVolatilityBreakout` is a real, complete 233-line `CStrategyBase` subclass, but nothing
`#include`s it: no catalog row, no `SI_*` slot, no `InpEnable*` input, no `factoryName`, so it is not compiled
into any program. The live entry rule is `CFastScalpSignal` - EMA 5/13 crossover + RSI(7) + spread-vs-ATR - with
no strategy object involved.

`ScalpVolatilityBreakout.mqh` is kept, unlike Batch 210's unreachable factory paths: those were half-built
construction routes to classes built elsewhere, while this is a whole strategy that could be activated. Turning
it on means a catalog row, an enable input and a `RegisterStrategy` call, and it would open a path that has never
traded - a strategy-activation decision, so it goes on §4's *unwired but wireable* list instead of being deleted
or switched on blind.

`sync_and_compile.ps1 -All`: 8 root programs, 0 errors / 0 total warnings.

### Batch 215: two symbol-state classes nothing wrote to, three inputs nothing read, and 92 log tags no code prints

A deletion batch, plus the documentation sweep that found it. No decision path changed shape: every removal is
state or surface that a reader could not exist for.

#### 1. `CSymbolStateTracker` and `CSymbolScanScheduler`: held, initialised, never written
`CSymbolStateTracker` was allocated by `CRegistryAggregator`, `Initialize`-d by the orchestrator with the symbol
list, and its `GetStatusReport()` appended to the shutdown report. Nothing else: `RecordScalpCostFailure`,
`RecordDormantWarning`, `ClearDormantCooldownOnNewBar`, `IsScalpBlacklisted`, `IsInDormantCooldown`,
`UpdateLastActivity` and `GetLastActivity` had no caller in the repository. So its `[SCALP-BLACKLIST]` and
`[DORMANT-COOLDOWN]` printers could never run, and the report it contributed asserted
`scalpBlacklisted=false, dormant=none` for all thirteen symbols, forever, from a class that had no way to learn
otherwise. The dormancy state that actually gates evaluation is `CSignalGenerator`'s own (Batch 212 made that
one configurable).

`CSymbolScanScheduler` was never instantiated at all: `new CSymbolScanScheduler` appears nowhere, and the only
route to it, `CRegistryAggregator::GetScanScheduler`, was a function that returns `NULL` and had no caller - the
code said so in its own comment. Its whole file is deleted, along with the dead `pendingNewBarScan`,
`lastIntrabarScanTime`, `intrabarBackoffSeconds`, `dormancyWarningCount`, `dormantCooldownUntil`,
`scalpBlacklist*` and `externalCapacityLogThrottle` fields of `CScanSchedulerRegistry`, whose accessor methods
likewise had no caller. `CScanSchedulerRegistry` now keeps what `ProcessNewBars` uses: one
`symbol + lastBarTime` slot per symbol, and `pendingNewBarScan` is gone with them - it was set `true` by
`CheckNewBar` and cleared by nothing, so the status report said `pending=Y` for every symbol after its first
bar.

`GetTotalRegisteredCount` (uncalled, and it summed six of seven registries while its comment claimed seven) and
the six `Is*Ready()` probes go too, along with the nine per-symbol `Get*(symbol)` conveniences the class's own
comment had already named dead. That comment was right and I nearly overruled it: grepping each bare method name
returned call sites, but every one was on a different owner (`pipeline.GetRegimeEngine`,
`m_mathEngineHub.GetVPINFilter`, `m_infra.GetDrawingManager`). Counting the receivers actually used
(`m_registryAggregator.<name>`) gives nine names, none of them a `Get*Engine`. A reference count on a method name
is not a call-site count on a method owner - the same error as counting a field's mentions instead of its writers.

#### 2. Three operator inputs bound nothing
`InpIntrabarScanSeconds`, `InpMaxIntrabarSymbolsPerCycle` and `InpIntrabarBackoffMaxSeconds` each wrote a
`SOrchestratorConfig` field that no code read - the only consumer was the dead scheduler's `SetInputParams`,
which itself had no caller. They are removed from both `.mq5` files and from the config struct, rather than
wired: their values fed a scheduler that was never built, and building it now would be a new cadence authority
(Batch 212 already established that consensus runs once per chart bar and left sub-bar evaluation to the
operator).

#### 3. The log-tag sweep: 92 bracketed names in the docs, no code prints them
Extracting every backticked `[TAG]` from the five root documents and diffing it against the set of bracketed
tokens that appear anywhere in the `.mqh`/`.mq5` tree left **92 names with no printer**, and about two thirds of
them sit in sentences saying the runtime emits or prints them. A sample of what the documents promise a journal
contains: `[SCHEDULER-STATE]`, `[CADENCE-WARNING]`, `[MODE-MASK]`, `[AI-TOPOLOGY]`, `[ACCOUNT-CAPACITY]`,
`[TRADE-STATE]`, `[LIVE-AUTHORITY]`, `[AUTHORITY-TRIAL]`, `[AUTHORITY-RESULT]`, `[CONSENSUS-VETO]`,
`[CONSENSUS-ACTIVE]`, `[CONSENSUS-SPARSE]`, `[CONSENSUS-NEARMISS]`, `[INTRABAR-BACKOFF]`, `[SCAN-PRIME]`,
`[SCAN-CANDIDATE]`, `[SCAN-DECISION]`, `[TRADE-CONFIRMED]`, `[ATR-FALLBACK]`, `[ENTERPRISE-BLOCKED]`,
`[CAPACITY-EXTERNAL]`, `[NN-MUTATION]`, `[SCALP-BLACKLIST]`, `[SPIKE-HUNT-DETECTED]`, `[VPIN-HIGH]`,
`[HURST-ENGINE]`, `[OU-ENGINE]`, `[SHADOW-TRADE]`, `[EXECUTION-MODE]`, `[SIGNAL-VALIDATED]`, `[TIERED-VOTE]`,
`[SETUP-QUALITY]` - plus two misnames of real tags (`[CONSENSUS-VETO]` for `[CONSENSUS-VETOED]`,
`[TRADE-CONFIRMED]` for `[ASYNC-TRADE-CONFIRMED]`).

This is not cosmetic. AGENTS.md section 6 is the checklist a session works from, and a tag list is a search
index: a reader who greps a journal for `[SCHEDULER-STATE]` gets silence and concludes the cadence repair ran
quietly, when there is no cadence repair. `RUNTIME_DECISION_GRAPH.md`'s Diagnostics section and
`SYSTEM_AUDIT_TRACE.md`'s Observability Surface are now restricted to tags verified present in the tree, each
annotated with what it prints, and the phantom names are kept in one dated sentence so a later reader does not
re-add them. The remaining mentions elsewhere in the four documents are recorded as an open task rather than
deleted blind: some of those 92 are pattern or enum identifiers quoted in prose (`[TTM_SQUEEZE]`,
`[BREAKOUT_RETEST]`, `[MR-STOCH-NOT-EXTREME]`) and need reading, not removal.

`sync_and_compile.ps1 -All`: 8 root programs, 0 errors / 0 total warnings. Net -740 lines.

### Batch 214: the fast-scalp indicator cache commits per symbol, and every scalp refusal names its gate

One money defect and one observability defect in the same three lines of code, found together because the
first was unloggable without the second.

#### 1. A failed indicator refresh left symbol B's numbers tagged as symbol A
`CFastScalpIndicators::RefreshIndicators` read ATR, fast EMA, slow EMA and RSI in sequence and wrote each
**member** as its own read succeeded, restamping `m_cachedSymbol` / `m_cachedBarTime` only at the end. So an
`INVALID_HANDLE` or a short `CopyBuffer` partway through returned `false` with the *new* symbol's ATR (and
possibly its EMAs) already in the cache while the cache still *named the previous symbol*.

That is reachable on every tick, because one `CFastScalpEngine` instance is held by value in the orchestrator
and driven through the whole symbol universe in one pass (`EAOrchestrator.mqh` `ProcessScalpFastPath` loops
`m_managerCount`). The next call for the old symbol hit the new-bar test
(`barTime == m_cachedBarTime && symbol == m_cachedSymbol && m_cachedATR > 0.0`) - now true with a foreign
ATR in it - and was served **another instrument's M1 ATR for the rest of its bar**. Four decisions read it:

- `IsSpreadAcceptable` compares this symbol's spread against `0.30 * that ATR`. XAUUSD's M1 ATR is several
  times EURUSD's in price terms, so an FX scalp's cost gate saw a cheap spread and passed. The EA then took
  trades whose spread is a real share of a 5-pip TP - the exact cost the gate exists to refuse.
- `IsMomentumBurst` divides the M1 body by the same foreign ATR, so bursts appeared and vanished by the luck
  of which refresh had failed last.
- `CalculateConfidence` adds 0.10 when `spread/ATR < 0.15`, so the lot was scored against the wrong scale.
- `IsRSIConfirmed` read `m_cachedRSI` with **no symbol argument at all**: the overbought/oversold gate could
  be answered by a different instrument's RSI.

And none of it was visible: the `false` return was never printed, and `EvaluateSlowPath` turned it into
`TRADE_SIGNAL_NONE`, which is the same output as "no crossover this bar".

Fix: the four reads land in locals and the members (including the tag) are written only after the last one
succeeds, so a failure leaves the cache exactly as it was - stale but truthful, and the new-bar test cannot
pass for a symbol the cache does not name.

#### 2. An unread RSI in the signal cache confirmed BUYs and refused SELLs
`CScalpSignalCache::UpdateOnNewBar` zeroes every field whose `CopyBuffer` fails, and only
`emaFast / emaSlow / atrValue` gate `isValid` (`ScalpSignalCache.mqh:431`) - a failed RSI read is explicitly
"non-critical". `EvaluateFromCache` then tested that zero as a reading: `rsiValue >= 70` is false, so a BUY
crossover passed its confirmation with no RSI behind it, while `rsiValue <= 30` is true, so the same missing
value refused every SELL. One unread number therefore opened one direction and closed the other. The slow
path already failed closed on it (`IsRSIConfirmed` returns false at `m_cachedRSI <= 0.0`), so the two paths
disagreed about the same missing data. Fix: `EvaluateFromCache` refuses at `rsiValue <= 0.0` with
`gate=rsi_unavailable`, so both paths now answer a missing RSI the same way - no trade.

#### 3. The refusals now say which gate refused
`CFastScalpSignal::EvaluateFromCache` and `EvaluateSlowPath` take `string &gateReject`, and
`ShouldEnterScalp` prints it under a per-symbol throttle:
`[SCALP-SIGNAL-REJECT] <symbol> | gate=spread_vs_atr | rsi_overbought | rsi_oversold | rsi_unavailable |
indicator_refresh_failed | ema_handles_failed | no_atr_or_point`, plus
`[SCALP-SIZING] <symbol> | sizer returned lot 0.0000 | signal refused before the risk gate` for the lot that
`CPositionSizer` refused to produce. **An absent crossover leaves the reason empty and prints nothing** - that
is the normal state of the market on a given tick, not a refusal, and 13 symbols per second of it would bury
the journal.

The `[SCALP-GATE]` line itself was throttled by one EA-wide `static datetime`, so the first symbol refused
inside a 60 s window muted the other twelve. It is now `RefusalLogDue(symbol, 60)`, keyed by a per-symbol
array bounded by the symbol universe. The three lines share one slot per symbol, so a symbol yields at most
one refusal per minute - whichever gate refused first - which keeps the journal bounded at 13 lines.

#### 4. Dead state the fix made visible
Six `GetCached*` accessors had no caller anywhere in the repository, and the two fields they exposed
(`m_cachedFastEMA`, `m_cachedSlowEMA`) had no reader either: a crossover needs *two* bars, which a one-slot
cache cannot supply, so `GetEMACrossover` reads its own pair statelessly. Both fields, both ctor initialisers
and the two matching `SetCachedValues` parameters are deleted, which also takes two `CopyBuffer` calls out of
every refresh. The `StringFind(symbol, "Vol")` condition written twice in `IsSyntheticSymbol` is now once.

#### Deliberately not changed
`m_lastScalpTime` and `CFastScalpRiskBudget` are also single slots shared by every symbol, so a scalp on one
symbol cools down all thirteen and the budget is account-wide. That is a design choice - one fast-scalp
position stream for the whole EA - not a bug, so it stands; the refusal line names the symbol it is refusing
and its `usedRisk` / `cooldownLeftMs` are honestly engine-wide numbers. `IsSyntheticSymbol` still carries
`"SFX Vol"` / `"FX Vol"` conditions that the earlier `"Vol"` test already covers - harmless, and trimming an
asset-classifier name list is a strategy decision rather than dead-code removal.

`sync_and_compile.ps1 -All`: 8 root programs, 0 errors / 0 total warnings.

### Batch 213: ADX tiering was multiplied twice, and VPIN toxicity never reached a lot

Two sizing defects found by a read-only sweep of the modifier chain, each verified at its own lines before
being touched.

#### 1. Two `CADXLotModifier` instances in one chain
`CPositionSizer::Initialize` registered an ADX modifier **unconditionally** ("ADX modifier is registered
unconditionally", `PositionSizer.mqh:257`) and `CEAOrchestrator` then added its own configured instance to the
same chain (`EAOrchestrator.mqh:939-944`). Each instance holds its own iADX handle and applies its tier as a
multiplier, so the chain multiplied ADX **twice**: `m_strongMultiplier 1.3` shipped 1.69× and
`m_veryStrongMultiplier 1.5` shipped 2.25× of the lot the risk math had computed, and every `[ADX-MODIFIER]`
line printed twice per sizing.

Where that landed depended on the caller, and both callers were live: the consensus path
(`CandidateBuilder.mqh:475`) follows the lot with the per-trade cap clamp at `:506-530`, so the doubled boost
mostly showed up as `[RISK-GATE-ADJUST] lot A -> B` churn and a ladder permanently saturated at the cap -
the tier nuance bought nothing and the operator saw adjustment noise. The four engine paths that call the sizer
directly - `ATRScalpEntry.mqh:89`, `FastScalpSizing.mqh:68`, `GridRecoveryEngine.mqh:320`,
`SpikeHunterExecutor.mqh:155` - and `SimpleMomentumStrategy.mqh:749` do not run that clamp, so those shipped the
doubled lot. Fix: the sizer no longer registers ADX at all; the orchestrator's configured instance is the one
in the chain.

Not the same shape, and left alone: the sizer's `m_equityCurveModifier` is registered only
`if(m_params.useEquityCurveScaling)` and has its own reader at `PositionSizer.mqh:489`, so it is a conditional
feature rather than an unconditional duplicate.

#### 2. The VPIN lot modifier read a filter nobody fed
`CVPINLotModifier` created its **own** `CVPINFilter` lazily (`EnsureFilterCreated`), and nothing ever called
that filter's tick method: the only live VPIN feed is the math hub's per-symbol filters, throttled inside
`COrchestratorMathEngineHub` and driven from the orchestrator's tick path (`EAOrchestrator.mqh:2607`).
`IsWarmedUp()` is `m_completedBuckets >= m_numBuckets`, so it was false forever and `AdjustLotSize` returned
`baseLot` at the `!IsWarmedUp()` branch with no log. Its injection API `SetVPINFilter` had **zero call sites on
this class**, and the parameterized `Initialize(symbol, ...)` that would have configured its private filter had
zero call sites too - only the parameterless contract `Initialize()` was ever called.

Consequence: the designed toxicity protection - a lot shrink of 0.10×-1.00× blended by confidence - has never
applied. A book with informed-flow toxicity shipped at **full size**, up to ten times the intended risk, and
three documents said otherwise (`PostConsensusValidator.mqh:396` "CVPINLotModifier applies it",
`CandidateBuilder.mqh:494`, `VPINFilter.mqh:54`). `[VPIN-MODIFIER]` has never printed in this repository's
history.

Fix: the modifier now holds a per-symbol table of the hub's filters (`RegisterFilter(symbol, filter)`, references
only - the hub keeps ownership and the tick feed), `CPositionSizer::RegisterVPINFilter` forwards to it, and the
orchestrator registers each symbol's filter in the same engine-injection loop that wires the strategies
(`EAOrchestrator.mqh:1723`). A symbol with no filter returns `baseLot` and says so once. The never-fed private
filter, `m_ownsFilter`, the five unused `m_default*` fields, `EnsureFilterCreated` and the dead parameterized
`Initialize` are deleted, and `[SIZING-CHAIN] modifiers=<names in the chain> | vpin_filters=N | kelly=inert(no UpdateTradeResult caller)`
prints once at init, so a sizing input that reaches no multiplier is visible rather than assumed.

Direction: both fixes **reduce** lots - one by removing a doubled boost, one by re-arming a protection that was
supposed to shrink toxic trades. Neither widens risk.

#### Checked and deliberately not wired
- `CRiskAdaptiveTuner::m_riskReductionFactor` is a field with a reader and no writer (`UnifiedRiskManager.mqh:1544`
  uses it to credit open P/L back against the used-risk budget; the value is the constructor's 0.5 forever).
  `UpdateAdaptiveRiskLevel` does compute a `reductionFactor` and tightens it to 0.35 in critical drawdown - but
  that number means "fraction of base risk to trade at", while this field means "fraction of unrealized profit
  that frees budget". Storing one into the other would put two different quantities in one variable, so the
  credit stays at its current, constant 0.5 and the naming collision is recorded instead.
- `CBayesianKellyModifier` is registered from `InpKellyFraction` and returns `baseLot` unchanged because its only
  input, `UpdateTradeResult`, has no caller. Wiring it naively would be a trap, not a fix: it multiplies a lot
  that is **already** fixed-risk sized by a fraction of bankroll (`K * 0.25` ≈ 0.02-0.075), which would drop
  every subsequent trade to roughly 1/13-1/40 of intended size, armed by a single closed trade. The correct form
  is Kelly setting `riskPercent` before sizing, not scaling the result - a redesign, not a wiring, and
  `[SIZING-CHAIN]` now says plainly that it is inert.
- The compounding tier ladder is not monotone: tier 4 ($500-1,000) is 1.5% per trade and tier 5
  ($1,000-5,000) is **5.0%**, with an inline comment on tier 5 saying "5% risk per trade for <$1K equity" - a
  3.3x jump at $1,000 that reads like tier 1's numbers copied into the wrong band. Batch 192's clamp caps it at
  the operator's approved per-trade risk, so the live effect is "full ceiling from $1,000 up" rather than 5%,
  but which number that band should hold is an operator decision, not a bug to guess at.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, 0 errors / 0 total warnings.
- Both instances of the ADX double registration read at their creation sites, and the sizer's remaining
  `m_equityCurveModifier` path checked before concluding it is a different shape.
- `grep` for `SetVPINFilter`, `EnsureFilterCreated`, the parameterized `Initialize` and `UpdateTradeResult` call
  sites before deleting anything.
- No journal evidence exists (newest 2026-09-23), which is why the absence of every `[VPIN-MODIFIER]` line - a
  tag three documents describe as live - is recorded as reasoning from the code rather than as a log finding.
  First-run signs: `[SIZING-CHAIN] vpin_filters=N` with N equal to the number of initialized symbols carrying
  `InpEnableVPINFilter`, at most one `[ADX-MODIFIER]` line per sizing, and `[VPIN-MODIFIER] ... lot A->B`
  whenever a warmed filter says the flow is toxic.


### Batch 212: the scan cadence controls bind, a parked symbol stops costing other symbols their scan, and the fused entry gate names itself

#### Three controls that reached nothing
- `InpMaxSignalEvaluationsPerCycle` (default 8) wrote `config.maxSignalEvaluationsPerCycle`, which had **no
  reader anywhere**. The number that actually bounded each scan cycle was `CSignalGenerator`'s private
  `m_evalBudgetPerCycle(8)`, next to a comment claiming "Eval budget is config-driven only; there is no runtime
  setter". Setting the input to 3 or 20 changed nothing; `SYSTEM_STRUCTURE.md` states the opposite.
- `InpSignalScanOnNewBarOnly` (default false) wrote `config.signalScanOnNewBarOnly`, also with no reader. Its
  documented behaviour - "setting it back to true still acts as a hard global override that disables timed
  intrabar scheduling" - describes machinery no entry path runs: `EvaluateSymbol` gates every symbol to one
  evaluation per bar **unconditionally**, and `EVAL_MODE_INTRABAR` is never passed on the scan path at all.
  Both states of the input produced the same EA. Deleted, per the Batch 207 rule for inputs that bind nothing.
- The dormancy park itself: `DORMANT_THRESHOLD = 3` and `DORMANT_COOLDOWN_MIN = 30` were anonymous enum
  constants inside the generator. Three consecutive no-signal **bars of the chart's timeframe** earn a
  **30-minute** evaluation blackout. On an H1 chart that is a mild backoff; on an M1 chart it is 3 minutes of
  quiet buying 30 minutes of not being looked at - ten times the entry chances lost, on a book where most
  symbols are quiet most of the time. A strike count in bars and a cooldown in minutes are two units that never
  belonged together, and neither number was settable.

#### What changed
- `CSignalGenerator::SetScanPolicy(evalBudgetPerCycle, dormancyStrikeBars, dormancyCooldownMinutes)` is called
  right after its `Initialize`, fed from `config.maxSignalEvaluationsPerCycle` and two new inputs
  `InpDormancyStrikeBars` (3) / `InpDormancyCooldownMinutes` (30). Every default equals the number that was
  already in the code, so today's behaviour is unchanged - the difference is that the operator can now move
  them, and `[SCAN-POLICY] evalBudget=… | dormancy: … no-signal bars -> … min park` prints once so the posture
  is in the journal instead of in a source file.
- `SelectSymbolsForEval` no longer spends selection slots on parked symbols, and the rotation advances by the
  number of symbols examined rather than by the budget. The old `m_evalStartIndex += budget` could step past
  symbols whenever fewer than `budget` were selectable, so a symbol could wait longer than one rotation to be
  looked at; and a parked symbol held a slot that the scan loop then skipped, which cost the cycle scans it
  never performed. A cycle now evaluates up to `budget` **scannable** symbols. Strictly more scanning, same
  thresholds.
- `m_intrabarBudgetPerCycle` and the byte-identical `EVAL_MODE_NEW_BAR` / else branches in
  `SelectSymbolsForEval` are gone: they were the same code twice, and only one mode is ever passed.
- `[ENTRY-GATE] entries held this cycle | refused by=trade_cooldown position_limit unprotected_positions
  spike_pause profit_guard_halt basket_equity_halt | eaPositions=n/m | secondsSinceLastTrade=n` when the fused
  `canOpenNewTrades` flag is false - the six individual refusals were computed three lines earlier and then
  collapsed into one silent `continue` at the send. Throttled to one line per 15s so a held book cannot flood
  the journal.

#### Behaviour direction
Neutral at defaults for the three controls; strictly non-worse for scan coverage (a parked symbol can no longer
consume another symbol's slot, and the rotation cannot skip); the only new output is two log lines. No
threshold, veto, weight, lot or exit path moved.

#### Deliberately not done, with the reason
`EVAL_MODE_INTRABAR` does bind - on the **exit** side, where `CPositionLifecycleManager.mqh:261-264` reads
consensus in that mode, so the intrabar quorum/solo-confidence/quality values decide whether a trend
invalidation fires. Making the **entry** scan use it would let between-bar entries be judged by the intrabar
threshold set (`minSoloConfidence` 0.70 instead of 0.65, quality floor 0.68 instead of 0.70, plus the
`eligibleLiveVoterCount < 3` gate at `ConsensusEngine.mqh:1051`). That is a real change in admission on a live
book, in both directions at once, and there is no journal newer than 2026-09-23 to measure it against. It is
recorded in `SYSTEM_STRUCTURE.md` as the next candidate, not guessed at here. Sub-bar evaluation also has a
trap attached: `RecordDormancyWarning` counts evaluations, so allowing several evaluations per bar would let a
quiet symbol earn three strikes in seconds and park for 30 minutes - which is the reason the once-per-bar gate
is written the way it is.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, 0 errors / 0 total warnings.
- Each dead field confirmed by repo-wide grep for the identifier (readers outside `OrchestratorConfig.mqh` and
  the two root `.mq5` assignments: none) before anything was wired or deleted.
- Defaults compared value by value: `InpMaxSignalEvaluationsPerCycle = 8` vs `m_evalBudgetPerCycle(8)`,
  `InpDormancyStrikeBars = 3` vs `DORMANT_THRESHOLD`, `InpDormancyCooldownMinutes = 30` vs
  `DORMANT_COOLDOWN_MIN`.
- No journal evidence exists (newest 2026-09-23). First-run signs: one `[SCAN-POLICY]` line, `[DORMANT-COOLDOWN]`
  parks with the configured minute value, `[DORMANCY-COOLDOWN] ... cooldown expired, strikes reset` recoveries,
  and `[ENTRY-GATE]` lines whenever the book is held - a session with no `[ENTRY-GATE]` line and no trades means
  the strategies found nothing, which is now a distinguishable answer.


### Batch 211: engine injection says out loud which strategy actually got its engine

#### The gap
Four strategies take their statistical engines by injection after registration, in
`InitializeEnterpriseManagers`: Hurst (+VPIN) into `Trend`, Hurst (+VPIN) into `Support/Resistance`, Hurst into
`Mean Reversion` (its regime lockout) and OU (+Python bridge) into `Statistical Arbitrage`, plus VPIN/OFI onto
the manager itself. Every one of those five prints was behind `m_config.logLevel >= 3`, and `InpLogLevel`
defaults to **1** (`MultiStrategyAutonomousEA.mq5:386`). No live journal this repository has ever produced says
whether a single engine landed.

The second silence was worse: a failed `dynamic_cast` was treated the same as "strategy not on this roster". If a
catalog row names a class its creator did not build, the strategy registers, votes and trades - without its
engine - and nothing distinguishes that from a clean wire. Batch 194 gave the *construction* path a
`[STRATEGY-CONFIG] <row> did not yield a CStrategy...` line for exactly this shape; the injection path kept the
silence.

#### What that silence hides, in money terms
`CMeanReversionStrategy::MeanRevertingRegime()` returns **true** when `m_hurstEngine == NULL`
(`MeanReversionStrategy.mqh:492`): no engine means no regime lockout, so band re-entries stay eligible in a
confirmed trend. With `InpEnableHurstEngine = false` - or a cast failure - that is what runs, and the operator
reading the journal cannot tell it apart from a filtered strategy. Trend and S/R lose their Hurst/VPIN filters
the same way, and `InpEnableOUProcess = false` leaves Statistical Arbitrage without the half-life filter its
signals are supposed to clear.

#### The change
- One `[WIRE-STATUS] <symbol> | Trend=… S/R=… MeanRev=… StatArb=… | hurst=… ou=… vpin=… ofi=…` line per symbol at
  init, printed unconditionally. Each strategy reads `wired`, `NO-ENGINE`, `not-registered` or `CAST-FAILED`;
  each engine reads `on` or `OFF`, so an input switched off and a roster without the strategy are two different
  answers.
- `[WIRE-CAST-FAIL] <symbol> | a registered strategy is not the class its catalog row names, so its engine was
  not injected` when a cast fails - the case that used to look like success.
- Each engine pointer is now fetched once per symbol instead of once per strategy block (four redundant
  `GetHurstEngine` / `GetVPINFilter` calls).

#### Behaviour direction
None. The same setters run with the same pointers, in the same order, and the wire states are computed from what
actually happened rather than asserted. Only output is added.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, 0 errors / 0 total warnings.
- `InpLogLevel = 1` default and the five `logLevel >= 3` guards read before removing them; the `NULL -> true`
  Hurst behaviour confirmed at `MeanReversionStrategy.mqh:490-498` rather than assumed.
- No journal evidence exists (newest 2026-09-23). First-run sign: one `[WIRE-STATUS]` line per initialized
  symbol. Expected states on the live defaults are `wired` for Trend / S/R / Mean Reversion, `not-registered`
  for Statistical Arbitrage (its input defaults to false and it needs the Python bridge), and no
  `[WIRE-CAST-FAIL]` line at all.


### Batch 210: the strategy factory builds AI adapters and nothing else

#### What was there
`CStrategyFactory` registered **twelve indicator creators** (`CreateMomentum` .. `CreateAsianRangeBreak`)
alongside the five AI adapters, and carried a `SStrategyConfig` of seventeen fields - symbol, timeframe, weight,
tier, role, cluster, plus `momentumScalpingEnabled`, `candlestickRequireTrend`, `meanReversionSyntheticMode`,
`statArbUsePythonBridge` and three engine pointers (`pythonBridge`, `ouEngine`, `hurstEngine`) - which those
creators applied with `SetScalpingMode` / `SetADXThresholds` / `SetRequireTrendAlignment` / `SetSyntheticMode` /
`SetHurstEngine` / `SetPythonBridge` / `SetOUEngine`.

#### Why none of it ran
`Create` has exactly one call site, `EAOrchestrator.mqh:2475`, inside the loop that starts with
`if(g_strategyCatalog[i].kind != CAT_KIND_AI) continue;` and passes `g_strategyCatalog[i].factoryName` - a field
that is `""` for every indicator row. So no indicator name could ever reach a creator, and the configuration
calls were unreachable. That is the state `SYSTEM_STRUCTURE.md` §2.2.3 records as "two construction authorities,
and only one of them runs", and the Batch 194 audit entry deferred removing it as "a larger, separate decision".
This batch is that decision.

The struct was decoration too: **none of the five AI creators reads a single `cfg` field.** The adapter's real
per-symbol setup is the very next call, `PrepareCatalogAIAdapter(k, adapter, symbol, timeframe)`, which sets the
neural net's online-training / weight-mutation / confidence-threshold and calls `nn.Initialize(symbol, tf)`; the
ONNX and Python Bridge adapters take the globals `g_onnxModel` / `g_pythonBridge`. So the eight `cfg.*`
assignments at the call site (`cfg.symbol = symbol;` and friends) set values that were then ignored - the same
"configuration applied on an abandoned construction path" defect class as Batches 193 and 194.

#### The removal
- Twelve indicator creators and their twelve `RegisterInternal` lines.
- `SStrategyConfig` and the `CreatorFunc` parameter: `Create(const string name)`, `IStrategy* (*CreatorFunc)()`.
- The eight-line `cfg` setup at the call site.
- Four public helpers with zero call sites anywhere: `IsRegistered`, `GetRegisteredNames`, `GetCount`, and
  `BuildConfigFromEA` - a stub whose own comments said "These would be filled from EA inputs in actual usage /
  For now, return base config - caller should override".
- Fourteen includes the deleted code was the only reason for: the twelve indicator strategy classes plus
  `OrnsteinUhlenbeckEngine.mqh` and `HurstEngine.mqh`.

#### Behaviour direction
Identical at runtime: the same five adapters are created, configured by the same `PrepareCatalogAIAdapter`, and
registered under the same names. `[StrategyFactory] Initialized with N strategy creators` now reports **5**
where it reported 17 - the fourteen it never used. If a future row ever points `factoryName` at an indicator,
`Create` prints `[StrategyFactory] ERROR: Unknown strategy '<name>'` instead of quietly building a second,
unconfigured copy of a strategy the catalog already owns.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, 0 errors / 0 total warnings.
- Call-site census before deleting: `grep -rn "CStrategyFactory::"` across every `.mqh`/`.mq5` returned two
  lines (the `SStrategyConfig` declaration and `Create`) plus the include; `BuildConfigFromEA`, `IsRegistered`,
  `GetRegisteredNames` and `GetCount` returned zero outside the file.
- Registration parity checked name by name against the catalog's five `CAT_KIND_AI` rows' `factoryName` values.
- No journal evidence exists (newest 2026-09-23). First-run sign: `[StrategyFactory] Initialized with 5 strategy
  creators`, and no `[StrategyFactory] ERROR: Unknown strategy` line.


### Batch 209: the enable roster is written from the catalog, and the two paths that report it stop lying

#### The defect
`COrchestratorStrategyFlagBuilder::BuildStrategyFlags` hand-wrote fifteen `flags[SI_*] = config.enableX`
assignments plus twelve curated force-enables, and both consumers of that array reported it wrongly:

- `COrchestratorSymbolClassifier::BuildEnabledStrategyList` printed
  `EnumToString((ENUM_STRATEGY_TYPE)i)` for every set flag index `i`. `ENUM_STRATEGY_INDEX` (the flag slots)
  and `ENUM_STRATEGY_TYPE` (the registry types) share no numbering, so the `[CURATION] Effective strategy set`
  line - one of the validation logs in `AGENTS.md` §6 - named the wrong strategy for nearly every row:

  | Set flag slot | True owner | What `[CURATION]` printed |
  |---|---|---|
  | 0 | Momentum | `0` (no such enum member) |
  | 1 | Trend | `STRATEGY_MOMENTUM` |
  | 4 | Support/Resistance | `4` (gap) |
  | 6 | Candlestick | `6` (gap) |
  | 7 | Mean Reversion | `STRATEGY_CANDLESTICK` |
  | 8 | Volatility Breakout | `STRATEGY_MEAN_REVERSION` |
  | 14 | Asian Range Break | `STRATEGY_NY_OPEN_GAP` |
  | 17 | Liquidity Sweep | `17` (gap) |
  | 18 | Range Compression | `STRATEGY_LIQUIDITY_SWEEP` |

- `CountEffectiveIndicatorStrategiesForSymbol` summed every set flag and then subtracted four `#define`d "AI
  slots" `17/18/19/20`. No AI adapter owns a flag slot (all five rows carry `siIndex = -1`), while those four
  numbers are Liquidity Sweep, Range Compression, Exit Optimizer and `SI_MAX`. On the default live roster that
  is 14 set flags minus 3 = **11**, where the true indicator count is **13**: the Exit Optimizer's `+1` in the
  sum cancelled its own `-1`, so the two curated structure rows were charged against themselves. 11 is the
  number the `[ENTERPRISE] Skipping <symbol>` guard at `EAOrchestrator.mqh:1624` tests against zero.

- `flags[SI_EXIT_OPTIMIZER] = config.enableExitOptimizer` wrote a slot nothing read as a strategy. The Exit
  Optimizer is a math engine, gated live at `OrchestratorMathEngineHub.mqh:272,440` through the same config
  field, and never a consensus voter.

#### Why it matters for plug-and-play
Batch 208 moved vote classification onto the catalog row. Enablement was the last place a new strategy still
had to be written by hand a second time - and the `[CURATION]` line is how an operator confirms which roster a
symbol actually got, so a log that misnames it makes a correct deployment look unverified.

#### The fix
- `SStrategyDefinition` gained `curatedEnable`; the twelve curated rows say `true` and Candlestick, Statistical
  Arbitrage and all five AI rows say `false`, which is exactly the set the old `if(!config.enableX)` ladder
  force-enabled.
- `BuildStrategyFlags` loops the catalog's indicator rows: `CatalogEnableSlot(i)` is the slot,
  `ConfigEnableForSlot(config, si, hasInput)` is the single slot -> operator-input switch, and a row whose slot
  has no case prints `[CATALOG] <name> | enable slot N has no operator input - it stays off unless curated`
  instead of being silently off.
- `BuildEnabledStrategyList` and `CountEffectiveIndicatorStrategiesForSymbol` walk the rows, so the roster is
  named and counted by the same data registration uses.
- Deleted: the `SI_EXIT_OPTIMIZER` slot, the eight `STRATEGY_*_AI 17..20` literals (five in
  `EAOrchestrator.mqh`, four guarded copies in the classifier), and the `ENUM_STRATEGY_TYPE` cast.
- Docs contract: `README.md`'s roster table still carried Unified ICT / Unicorn Model / Power of Three (deleted
  in Batch 207) and omitted Liquidity Sweep, Range Compression and `InpEnableStatisticalArbitrage`'s real
  default of `false`. Both tables are now the fourteen rows, with a Curated column.

#### Behaviour direction
Nothing moves a vote, a weight, a policy or a risk gate: the flag array holds the same fourteen values it did
before for every existing row. `[CURATION]` output changes text (real names, no Exit Optimizer), and the
effective-indicator count rises by two on any roster where Liquidity Sweep and Range Compression are enabled (the curated mode guarantees both), which only makes the skip guard harder to trip -
no symbol that traded before stops trading. A strategy added without an `enable` input now announces itself
instead of being unreachable.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, 0 errors / 0 total warnings.
- Curated set parity checked row by row against the deleted ladder (12 true, Candlestick + StatArb false).
- `grep` confirmed `SI_EXIT_OPTIMIZER` had exactly two references (its declaration and the deleted write) and
  the `STRATEGY_*_AI` literals had no reader outside the deleted decrements before either was removed.
- No journal evidence exists (newest 2026-09-23). First-run signs to look for: `[CURATION] Effective strategy
  set for X: Momentum, Trend, ...` naming rows rather than enum numbers, and no
  `[CATALOG] ... has no operator input` line for the fourteen current rows.


### Batch 208: contributor kinds are read from the catalog row, not from a copy of its names

#### The defect
Five predicates in `CandidateBuilder` classified who voted a trade by substring-matching the contributor
names against hand-written token lists. The names are the catalog row names (`RegisterStrategy` is called with
`g_strategyCatalog[i].name` for indicator rows at `EnterpriseStrategyManager.mqh:844` and
`RegisterCatalogAIAdapter` does the same for AI rows at `EAOrchestrator.mqh:2409`), but the tokens had drifted
away from them:

| Contributor | Token tested | Row name | Result |
|---|---|---|---|
| Mean Reversion | `MeanReversion` | `Mean Reversion` | never matched |
| Statistical Arbitrage | `StatArb` | `Statistical Arbitrage` | never matched |
| NY Open Gap | `NYOpen` | `NY Open Gap` | never matched |
| Asian Range Break | `AsianRange` | `Asian Range Break` | never matched |
| Liquidity Sweep | absent | `Liquidity Sweep` | never matched |
| Range Compression | absent | `Range Compression` | never matched |
| Python Bridge AI | absent | `Python Bridge AI` | never matched |

Six of the fourteen indicator rows, and one of the five AI adapters, were invisible to
`ContributorsIncludeIndicator` / `CountIndicatorContributors` / `ContributorsIncludeAI`.

#### Why that is a sizing and admission bug, not cosmetics
`CLiveAuthorityResolver::Resolve` branches on exactly those three flags:
- `authorityScore += 0.20 * min(1, indicatorContributorCount / 2)`, the `INDICATOR` term of the ladder that
  Batch 205 just made measurable. A trade voted only by Mean Reversion and NY Open Gap earned **none** of it and
  therefore sat a rung lower on the `riskMult` scale.
- `minConfidence = 0.55` **only** when `hasIndicatorContributor`; otherwise the AI-standalone floor
  (`InpAIStandaloneMinConfidence`, 0.65) applies. So a purely indicator-driven decision from those six
  strategies was judged by the standard for an unproven neural net, and `[AUTHORITY-REJECT] LOW_CONFIDENCE`
  refused trades that met the indicator bar.
- `hasAIContributor && !hasIndicatorContributor` selects the BOOTSTRAP / PROVEN_AI path. Python Bridge AI -
  absent from the AI tokens - never entered it, so an unproven adapter escaped the bootstrap cap while also
  never earning its AI bonus. It now does both correctly.
- `candidate.hasNeuralNetContributor` (Batch 203's label gate) used the `Neural` substring; same set today,
  one row-name drift away from breaking tomorrow.

#### The fix
`StrategyCatalog.mqh` gained `CatalogRowOfContributor` plus `CatalogContributorIsIndicator`,
`CatalogContributorIsAI` and `CatalogContributorIsAIKind`, and the five predicates became loops over them. Kind
and AI subtype are row fields (`kind`, `aiKind`), so the classification now follows the catalog: a strategy
added correctly is classified correctly, with no fifth place to remember. Dead tokens (`ICT`, `Unicorn`,
`PowerOfThree`) went with the phantom slots in Batch 207.

Matching is `StringFind(contributor, row.name)`, which tolerates a qualified `symbol::name` string. No row name
is a substring of another row name, so first-match-wins cannot misattribute a contributor.

#### Behaviour direction
Indicator-only consensus trades from Mean Reversion, Statistical Arbitrage, NY Open Gap, Asian Range Break,
Liquidity Sweep and Range Compression now earn the `INDICATOR` authority term and face the 0.55 confidence bar
instead of 0.65 - more entries, and larger ones, where the voters genuinely are indicators. Python Bridge AI
trades gain the `AI` bonus but are now correctly bootstrap-capped until they prove out. Mixed AI + indicator
decisions stop being treated as AI-standalone. Nothing else about the ladder moved: the vetoes, the
`LOW_CONFIDENCE` refusal shape, the bootstrap and promotion thresholds, the risk gates and the lot math are
unchanged.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, 0 errors / 0 total warnings.
- Name source verified at both registration sites above before replacing the tokens, because a containment
  test on the wrong spelling would have silently *reduced* classification rather than fixed it.
- No journal evidence exists (newest 2026-09-23). Expected first-run signs: `[AUTHORITY-...]` reason strings
  containing `INDICATOR` for trades the six strategies voted, fewer `[AUTHORITY-REJECT] ... LOW_CONFIDENCE` on
  those symbols, and `[TRADE-ATTRIBUTION] contributors=` naming Mean Reversion / Liquidity Sweep rows the old
  tokens could not see.


### Batch 207: the three strategy slots that never had a class are gone

#### What they were
`SI_UNIFIED_ICT`, `SI_UNICORN_MODEL` and `SI_POWER_OF_THREE` are strategy slots this repository inherited with
no implementation behind them. The census that justified deleting rather than wiring them:

- no `CatalogAdd` row names them, so nothing ever registers, votes or trades;
- the `SI_*` constants appear in `Core/Utils/Enums.mqh` and nowhere else;
- `STRATEGY_UNIFIED_ICT` / `STRATEGY_UNICORN_MODEL` / `STRATEGY_POWER_OF_THREE` are referenced only as three
  fall-through `case` labels in `GetRegimeCategoryMultiplier`'s ICT group - a branch no object can reach,
  because no `GetType()` returns those values;
- their three operator inputs (`InpIntrabarEligibilityUnifiedICT` / `UnicornModel` / `PowerOfThree`, in both
  EAs) flowed to `strategyTimeframeConfigs[3]`, `[5]` and `[6]`, and **no catalog row declares `siPolicyIndex`
  3, 5 or 6**. `CatalogPolicySlot(i)` only ever returns a row's own slot, so those config entries were written
  at init and read by nobody - three dead controls in the inputs dialog under names that suggest live
  per-strategy policy.

#### What was removed (51 lines, each verified against the census)
The `SI_*` slots and `STRATEGY_*` type values in `Enums.mqh`; the three dead `case` labels; the three config
fields and their init defaults in `OrchestratorConfig.mqh`; the `StrategyConfigBuilder` rows at indices 3/5/6
(their `.name` strings included); three inputs plus their config assignments in each of
`MultiStrategyAutonomousEA.mq5` and `MultiStrategyTestingEA.mq5`. Both enums keep their explicit numeric
values, so the surviving slots' numbers - and the slot pairs the catalog rows carry - did not move.

#### Deliberately kept
- **`SI_EXIT_OPTIMIZER` / `STRATEGY_EXIT_OPTIMIZER`.** `CExitOptimizer` exists, is constructed per symbol, and is
  parked because wiring `Evaluate()` would create a second exit authority against AGENTS.md §3.3. That is a
  decision about a real component, not a phantom identity, so its input stays with the reason already on
  record in `SYSTEM_STRUCTURE.md` §4.8.
- **`AIEngine`'s `"unicorn"` / `"powerofthree"` name normalisation.** Dead after this batch, but Batch 208
  replaces the whole string-token classification mechanism with the catalog row, which removes such branches
  by construction rather than by hunting names.
- **`MultiStrategyTestingEA`'s `TEST_PROFILE_SINGLE_UNICORN` / `_POT` and its `STestFlags` fields.** That is the
  testing EA's own profile vocabulary; those profiles now select nothing, which is honest, and editing the
  positional name arrays beside them is how a reporting misalignment gets introduced.

#### Behaviour direction
None. Nothing read any of these values, so no entry, exit, lot or risk path changed. What changed is the
operator-facing surface: the inputs dialog no longer offers three controls that reach nothing, and the regime
category switch no longer implies an ICT family of strategies the catalog does not have (`Liquidity Sweep`,
`FVG Scalper`, `Breaker Block`, `Turtle Soup` remain and still weight off `ictWeightMult`).

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, 0 errors / 0 total warnings.
- Diff review confirmed every removed line against the census; no other line in the six files changed.
- A live run should still show identical `[CATALOG-AUDIT]` slot pairs for the surviving rows, since the
  deleted slots left gaps rather than renumbering anything.


### Batch 206: the minimum R:R stopped being a maximum take-profit

#### The defect
`CalculateStops` clamps the stop into `[minSlPips, maxSlPips]` and then set
`takeProfitPips = MathMin(takeProfitPips, stopLossPips * minRR)`. `minRR` is a **minimum** reward-to-risk
requirement (`InpMinRRDefault` 2.0, 1.5 for the mean-reversion class), so this line turned it into a ceiling on
the target: a strategy whose designed TP was 5R had it chopped to 1.5R or 2R on every entry. Two damages from
one token:
- every winner's target was cut to the floor, which is the profit side of the same trade the stop was sized for;
- `CheckExecutionCost` tests `spread / takeProfitPips` against `InpMaxSpreadToTpRatio` (0.15), so *lowering* TP
  raises the ratio the gate refuses on. The line was vetoing entries that its own TP widening would have passed.

It also broke the invariant in the other direction: when the spread floor widened the stop, `MathMin` left TP
at the older, narrower figure, so the shipped trade's realised R:R fell **below** the configured minimum.
`MathMax(takeProfitPips, stopLossPips * minRR)` satisfies both readings: the target is never below minRR of the
stop actually taken, and a strategy's wider proposal survives.

#### Investigated and ruled out, with the reason
This batch came out of a two-front sweep for bug-shaped over-restrictions. These candidates were checked to the
line and are **not** defects:
- **`minSlPips` counts the spread three times** (`brokerMinPoints * 1.5` where `GetMinimumStopDistance` already
  folds `1.5 * spread`, plus a `spread * 3` term). The three-way maximum means the explicit `spread * 3.0` term
  dominates, so the double count changes nothing; 3x-spread minimum stop is the stated policy, and the
  resulting fixed cost ratio is what `[CANDIDATE-BUILDER] ... stop pinned to floor` exists to name.
- **`m_maxPositionsPerSymbol` latched at init** from safe mode's `noStacking`, with `Configure` having one call
  site. MT5 inputs cannot change during a run, and `OnChartEvent` only re-pushes the same `InpRiskTier`, so the
  tier this session can ever hold is the tier it booted with: the latch has no reachable stale case.
- **`GetAdaptiveQualityThreshold`'s fixed `0.65` / `0.70`** arms for `MARGINAL_ADMIT` and `SOLO_FALLBACK`: the
  live consensus publishes only `FULL_QUORUM` and `SPARSE_INTRABAR`, so neither arm is reachable and neither
  overrides a configured floor.
- **Correlation reduction refusing a min-lot candidate** (`adjustedLotSize < SYMBOL_VOLUME_MIN`) is the
  documented anti-round-up rule: floor to the step and refuse, rather than hand a reduction back as a bigger
  trade.
- **`PortfolioRiskManager` forcing risk to `cap + 0.01`** when a position has no stop is deliberate fail-closed
  behaviour, recomputed from zero on every pass rather than latched.
- **`[RISK-VOL-GATE] atr_ratio > 1.5 -> halve_risk`** sitting below the 2.0/2.5 crisis veto is a policy number
  with its own log line. Moving it is tuning a risk control without journals, which this round does not do.

#### Deferred, and why it is not a one-line fix
Every ATR this EA measures is taken on **the chart window's timeframe**: `CPostConsensusValidator::GetATRDirect`
uses `Period()`, `CalculateStops` passes `PERIOD_CURRENT` to `CalculateATR`, and the reason both resolve to the
same thing is that `EAOrchestrator.mqh:1790` initializes every per-symbol manager with
`manager.Initialize(symbol, (ENUM_TIMEFRAMES)Period(), ...)`. So the ATR crisis veto, the `>1.5` lot halving,
the spread/ATR veto and the volatility-sized stop for all thirteen symbols are keyed to whichever chart the
operator opened, while the strategies that voted each carry their own catalog timeframe. The correction is a
per-symbol operating timeframe, which is a policy decision about which of a symbol's timeframes *is* its trading
timeframe - not an arithmetic fix, and not blind-shippable on a live book. Recorded in `SYSTEM_STRUCTURE.md` §4.8.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, 0 errors / 0 total warnings.
- No journal evidence exists (newest 2026-09-23). Expected signs of this fix: `[CANDIDATE-BUILDER] ... FINDING0
  strategy-proposed stops | TP=` values that stay at the strategy's own target instead of collapsing to
  `SL x minRR`, fewer `[CANDIDATE-BUILDER] ... execution cost too high` refusals on the same symbol, and the
  `[CONSENSUS-...]`-following `[ENTERPRISE-CONFIG]`-era behaviour otherwise unchanged. Risk is unchanged: lot
  size is derived from the stop distance, which this batch does not touch.


### Batch 205: the live-authority lot ladder receives the four measurements it was written to read

#### The broken feed
`CLiveAuthorityResolver::Resolve` builds `authorityScore` from contributor kinds and four measured inputs,
and `authorityScore` selects the lot multiplier (`>= 0.80 -> 1.0`, `>= 0.65 -> 0.85`, `>= 0.50 -> 0.70`,
`>= 0.35 -> 0.50`). The four measured inputs arrived as **`0.0` on every consensus trade, always**:

| Bonus | Condition | Default threshold |
|---|---|---|
| `+0.08` | `convictionScore >= 0.65` | hard-coded |
| `+0.07` | `readinessScore >= InpAuthorityMinReadinessScore` | 0.52 |
| `0.05` | `contextScore >= InpAuthorityMinContextScore` | 0.48 |
| `+0.05` | `costScore >= InpAuthorityMinCostScore` | 0.50 |

They are read from `STradeCandidate`, which `CandidateBuilder.mqh:383-386` fills from
`SConsensusDecisionContext`, which `ConsensusEngine` never wrote. So no trade in the repository's history
earned any of those `0.25`, every consensus position was sized one to two rungs below the ladder the operator
configured, and three operator inputs bound nothing. `qualityScore` was the one live measurement in the list
(it comes from `directionalQuality`), which is why the ladder looked functional at all.

The values do exist elsewhere: `CUnifiedSignalPipeline::ProcessSignal` resets and fills a
`SPipelineEvidenceSnapshot` with real `readinessScore` / `contextScore` / `costScore` per signal. The dead
middle ground was the *roster's* twins (`SStrategyRuntimeEntry.readinessScore/contextScore/costScore`, read
by `GetStrategyReadinessScore()` and friends), which also have no writer - so neither obvious source was
usable, and Batch 204 found the §4.2 prose describing a design that had long been replaced.

#### What is wired
- The consensus loop captures each voter's own evidence snapshot immediately after its `ProcessSignal`
  succeeds, and accumulates it per direction alongside the existing quality sums.
- After the direction wins, the decision context publishes the winning side's mean `convictionScore`,
  `readinessScore`, `contextScore` and `costScore`, plus `readyLiveWeight = buyScore + sellScore` and
  `totalLiveWeight = votedWeight` - the two numbers the ready-ratio gate already divides, so the ratio is
  reconstructible from the context instead of printed as `0.00`.
- `convictionScore` is the mean raw `stratConf` of the winning side. It is deliberately not the same quantity
  as `directionalQuality` (mean of `stratConf x weight`), which feeds the other bonus: conviction is what the
  strategy stated, quality is what it stated after its weight. Both bonuses existed; both now read their own
  measurement rather than one real value and three zeros.
- Averaging is unweighted over the winning side's voters, the same shape as the existing quality average, so
  no new weighting authority is introduced into a sizing path.
- `reasons` now names each earned measurement bonus (`QUALITY CONVICTION READINESS CONTEXT COST`). The four
  measurement bonuses used to change the score without appearing in the reason string that
  `[AUTHORITY-REDUCED] ... reason=` prints, so a lot that grew after this batch is traceable to which
  measurement earned it.

#### Behaviour direction
**Lots on consensus entries get larger wherever the pipeline genuinely measures a ready, in-context, cheap
signal - and stay exactly as small as they are where it does not.** This is not a blanket raise: every bonus
is conditional on a threshold, two of which are operator inputs that now bind for the first time. Nothing in
the veto structure changed; `result.allowed`, the `LOW_CONFIDENCE` refusal, the bootstrap/proven-AI caps and
every risk gate behave as before, and the ladder's *reduction* direction is untouched. Worst case per trade
moves from `0.50`-of-scale to the configured size, so per-trade risk rises toward - not above - the operator's
own `maxRiskPercent` ceiling, which still clamps it.

#### Deliberately not changed
- `pipeline == NULL` leaves the four values at `0.0`, which pays no bonus. No measurement, no points; the
  alternative was inventing a neutral value on a sizing path.
- The roster's per-strategy `readinessScore/contextScore/costScore` remain unwritten. Nothing on the live
  consensus path needs them now, and feeding them would be a second, per-strategy copy of the same
  measurement with no defined update cadence.
- `SConsensusDecisionContext.diversityScore`, `directionalWeight`, `readyCoverage` and `stalenessPenalty` are
  referenced by nothing outside the struct's own copy operations. They are deleted in a separate hygiene
  commit in this batch, not folded into the sizing change.
- The four engine send paths never consult live authority, so their lots are unchanged by this batch.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, 0 errors / 0 total warnings.
- No journal evidence exists (newest 2026-09-23), and this batch moves position size, so it needs the first
  attach. Expected: `[AUTHORITY-CONFIG] effective: ... costScore=0.50 readiness=0.52 context=0.48` unchanged
  at init, and on trades `AUTHORIZED | score=` values that vary per candidate instead of clustering at the
  kind-only sum, with `QUALITY/CONVICTION/READINESS/CONTEXT/COST` tokens in `[AUTHORITY-REDUCED] ... reason=`.
  A candidate log printing `conviction=0.00 readiness=0.00` after this batch means the pipeline is not
  filling its evidence snapshot.


### Batch 204: a regime veto now vetoes the vote, not just the score

#### The defect
`RegimeStateHardGate` returns `0.0` for a strategy category the live regime forbids - mean reversion in
`REGIME_TREND`, trend/momentum in `REGIME_RANGE` - and the comment at the zero return said what the code
did: "zero score only: the vote still counts toward the minimum-voter floor". A vetoed strategy therefore
passed every other test, incremented `buyVotes`/`sellVotes` and landed in `buyContributorIndices`, with
only its score zeroed. One veto moved five gates in two opposite directions:

- `winningVotes >= effectiveMinVoters` - **loosened**. One real supporter plus one forbidden one reached the
  two-independent-voter quorum (Batch 13).
- `quorumRatio` against `totalVotesCast`, and the `[CONSENSUS-VETOED]` `conflictRatio` - **loosened**. A
  vetoed losing vote should not have been able to oppose, and a vetoed winning one inflated the ratio.
- `readyWeightRatio = (buyScore + sellScore) / votedWeight` - **tightened**. `votedWeight` sums the weight of
  everyone in the contributor arrays, so a vetoed strategy fed the denominator and nothing to the numerator.
  The line above it claims "abstainers cannot tighten this"; a vetoed voter is worse than an abstainer,
  because an abstainer is skipped before it reaches the array.
- `winningContributors` -> `SetLastSignalContributors` -> `[TRADE-ATTRIBUTION]`, `CStrategyMgrTradeFeedback`,
  the per-strategy health score and `[AUTHORITY-LEARN]` - **polluted**. Since Batch 199 charges contributors
  with the closed trade's outcome, a strategy the regime forbade was credited or blamed for a position it
  could not open, and `m_strategyHealthScore` feeds the reliability multiplier of its *future* permitted
  votes. The learning loop wired in 199 and 203 was training on trades its own gate had vetoed.
- `buyDirectionalQuality` / `sellDirectionalQuality` - diluted by participants whose contribution was zero.

#### The fix
`EvaluateConsensusInternal` reads the category multiplier into a variable and, at `<= 0.0`, skips the
strategy entirely: no vote, no contributor slot, no weight in the denominator. Zero is provably the hard gate
and nothing else - `RegimeComposite.mqh:246-250` clamps every category weight to `>= 0.01`, the chaos and
low-confidence factors are `0.30`/`0.55`, and `RegimeStateHardGate` is the only path to zero - so a deweight
(Breakout reversion at `0.25`, Chaos at `0.40`) still votes with a smaller score, as intended.

#### Behaviour direction
Entries both appear and disappear, and neither is accidental:
- **More** where a trend regime killed several reversion voters while a couple of trend voters genuinely
  agree: the ratio is now `score / (those two weights)` rather than `score / (five weights)`, and the vetoed
  opposition can no longer trip the conflict deadband.
- **Fewer** where the only support was vetoed: one permitted voter can no longer reach `effectiveMinVoters`
  on the strength of a forbidden colleague, and a fully vetoed field prints `[CONSENSUS-ABSTAIN]` where it
  used to print `[CONSENSUS-TIE] buyScore=0.000 sellScore=0.000`.
Both directions serve the reason the hard gate exists: fading a confirmed trend is the fastest way to blow an
account, and that judgement should not depend on which way the surrounding arithmetic happens to fall.

#### Deliberately not changed
- The dead paths. `EvaluateConsensusProbeOnlyInternal` and `EvaluateConsensusTwoTierInternal` carry the same
  zero-score shape, and `TryFallbackSoloSignalInternal` a third copy, but each says in its own header that it
  has no caller; editing them would be an unverifiable claim about behaviour that never runs. They stay in
  `SYSTEM_STRUCTURE.md` §4 as wireable, not wired.
- `eligibleLiveVoterCount` still counts every live voter, vetoed or not. It answers "how large is the field",
  which drives the `SPARSE_INTRABAR` class and the thin-field quality bump; a veto changes who is speaking,
  not who exists.
- No new operator input, no threshold moved. This corrects an accounting error, so there is nothing to tune.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, 0 errors / 0 total warnings.
- `SYSTEM_STRUCTURE.md` §4.2 was rewritten to the algorithm that actually runs. The Batch 82 vocabulary it
  carried - role multiplier, dynamic weight decay, contribution-class denominators, four veto-code names -
  matches no code in the repository, and `SConsensusDecisionContext`'s `convictionScore`, `readinessScore`,
  `contextScore`, `costScore`, `readyLiveWeight` and `totalLiveWeight` have no writer while
  `CandidateBuilder.mqh:383-386` copies four of them into every candidate and two log lines print them as
  `0.00`. Filed as Batch 205 rather than half-fixed here.
- No runtime evidence: the EA is not attached and the newest journal is 2026-09-23. Expected new signs:
  `[CONSENSUS-REGIME-VETO] <symbol> | N vote(s) hard-gated by regime | excluded weight | counted votes` at
  most once per consensus scan, and `[TRADE-ATTRIBUTION] contributors=` that never names a category the
  regime forbids. A `[CONSENSUS-REJECT] ... Ready weight ratio` line in a confirmed trend regime should now
  be rarer, and `[CONSENSUS-REJECT] ... Winning votes` more common for the same scan - if the *first* does
  not drop while the second does not rise, the skip is not being reached.


### Batch 203: the neural net can now see which of its trades made money

#### The broken chain
The net's online training has never been fed a realized trade result. Five links were missing, each verified at its own call site: `ReservePredictionForSignal` had no caller, so no observation was ever marked as belonging to a trade; `candidate.predictionId` was never assigned, so `TradeExecutor.mqh:416`'s branch that appends `|N:<id>` to the order comment never ran; nothing called `UpsertPredictionPositionMap` outside the class self-test, so the position-to-prediction map stayed empty; `AccumulatePendingCloseProfit` had no caller, so the pending-close arrays stayed empty and `GetPendingCloseProfits` returned 0; and `ProcessClosedPositionsForNNTraining` therefore returned at its first guard every cycle for the whole life of the repo. `[NEURAL-NET] TRAIN-BOOTSTRAP` said as much at runtime - it trains on self-labelled barrier outcomes because no traded label ever arrives.

A sixth flaw meant wiring the writer alone would have accomplished nothing: `GetPendingCloseProfits` resolved the prediction id by selecting the **live position** and reading its comment. A closed position is not selectable, so every row would have come back with an empty id and been skipped. It reads the persistent map now, with the comment only as a fallback while a position still exists.

#### What is wired
- `Send site` (`EAOrchestrator`): the observation is reserved **immediately before** `m_tradeExecutor.Execute`, not at candidate build, so no validator/risk/authority refusal can leave a trade-tagged barrier entry for a trade that never happened. If the send does not resolve to a position, `ReleaseNeuralNetPrediction` un-tags it; the release also fires on a send that executed but whose deal could not be read back.
- `ContributorsIncludeNeuralNet` is a new candidate flag: only a decision the net actually advocated may take a label. Reserving for an indicator-only trade would credit the net with a direction it never proposed - the pollution this batch was at risk of introducing, and the reason the wiring was not done blind in 201.
- `Execution`: `UpsertPredictionPositionMap(positionId, predictionId)` binds the fill to the prediction and prints `[NN-LABEL] <symbol> | position= | prediction= | bound at send`.
- `Close`: `AccumulatePendingCloseProfit(positionId, netProfit)` joins the existing account-level feeds, where profit, swap and commission are already summed.
- `Drain`: `ProcessClosedPositionsForNNTraining` now consumes every row it reads, linked or not - a row left behind is re-read on every cycle forever. The `IsTraining()` precondition is gone, so a net that has not reached its first training run still accrues the trade-linked count that its own bootstrap guard reads.
- `ClearPendingCloseProfit` deleted: an uncalled duplicate of `ConsumePendingCloseProfit` minus the return value.

#### Deliberately not changed
`UpdateTradeResultByPredictionId` sets `linkedToTrade` and counts a win; the realized number is **not** turned into a training target, and the meta-labeler keeps the barrier's directional outcome as its sample. Making profitability the meta target is the textbook move, but the existing dataset would then mix two label semantics - old samples "direction was right", new ones "trade paid" - and that mixed window is invisible in a live account and unverifiable without a run. It is recorded in `SYSTEM_STRUCTURE.md` §4 as a decision for the operator with journals in hand.

Also noted, not fixed: `m_tradeLinkedLabels` can double-count one winning trade (once here when the result lands on an unresolved barrier entry, once in `AddTrainingExample` when that entry resolves). The counter's only consumers are a `>= 5` readiness guard and checkpoint stats.

#### Behaviour direction
No entry, exit, lot or risk path changed. A net-advantaged trade's comment now carries `|N:<id>` **when it fits**: `BuildTradeCommentWithPrediction` used to return a truncated `|N:` fragment whenever the base plus id passed the broker's 31-character cap, which would both wipe the readable base and produce a marker `ExtractPredictionIdFromComment` cannot parse; it leaves the comment alone in that case, because the position map is the binding the close path actually reads. Engine send comments (ATR-SCALP / GRID-RECOVERY / SPIKE-HUNT / SCALP|) are untouched - they never set `predictionId` - so Batch 197's exit discrimination is unaffected. What changes is what the net learns from.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, 0 errors / 0 total warnings.
- No runtime evidence - the EA is still not attached and the newest journal is 2026-09-23. Expected first-run signs: `[NN-LABEL]` per net-advantaged fill, `[NN-TRAINING] Updated trade result for prediction ...` per close of one, `[NEURAL-NET] TRAIN-BOOTSTRAP` disappearing once five such labels exist, and `tradeLinked=` rising in the checkpoint summary. If `[NN-LABEL]` appears but `[NN-TRAINING]` never does on closes, the map lookup is failing and the labels are being dropped.


### Batch 202: the heartbeat's `paused` field now reports a real pause

`CDiagnosticsManager::m_tradingPaused` prints in every `[HEARTBEAT]` line, and its only two writers had no callers, so the field printed `false` for the life of the repository - including in the windows when `CSyntheticSpikeMonitor` had genuinely paused new positions. Batch 200 recorded it as log-only; this closes it.

`CHeartbeatTelemetry::Emit` takes the state as a second parameter and pushes it through `SetTradingPaused` immediately before `UpdateCounters`, and the orchestrator passes `m_spikeMonitor.IsPaused()` (`EAOrchestrator.mqh:2902`), the same accessor the cycle gate already consults. The field's comment said "updated each tick by main EA", which was the design that never got wired; it now says what feeds it and how often.

No decision reads this field, so entry, risk, execution and exit behaviour are unchanged; `IsPaused()` also expires the pause, which the cycle gate already did, so no state advances twice per cycle in practice. The duplicate writer `UpdateTradingPaused` was deleted in Batch 200; `SetTradingPaused` is now the single writer.

Verification: 8 root programs compile at 0 errors / 0 warnings. On the next attach, a synthetic-spike pause should show `paused=true` in the heartbeat lines between the pause and its expiry - the first time that combination has been possible to see in a journal.


### Batch 201: the AI's market-regime adaptation had no input, so it adapted to nothing

#### What was missing (`Core/Management/EntStrategySignalContext.mqh`)
`m_currentMarketRegime` had four readers and no writer - its own header even said the field "still keeps its construction value". The construction value is `MARKET_REGIME_UNKNOWN`, and `CAIEngine::AdaptToRegime` (`AIEngine.mqh:1025`) answers UNKNOWN with its `default:` branch: the adjusted confidence threshold equals the configured one. So the per-regime factors that operator reads about - 0.9 in a trend, 1.1 in a range, 1.2 in volatility - have never been applied to any AI strategy, on any cycle, since the day the code was written. `AIEngine.mqh:495` runs that loop for every manager every cycle; `:424` builds trade explanations from the same dead value, and `:739` / `:912` print it, which is why the journals show a regime string that was really always the same word. Eighth instance of the readers-without-writer shape in this repository, and the first one whose reader is a *threshold*.

#### The writer
`CEnterpriseStrategyManager::RefreshMarketRegime` reads the same `CRegimeEngine` snapshot the consensus regime gate reads (`pipeline.GetRegimeEngine(symbol).GetSnapshot()`, the source behind `GetRegimeCategoryMultiplier`) and maps it: `REGIME_TREND -> MARKET_REGIME_TRENDING`, `REGIME_RANGE -> MARKET_REGIME_RANGING`, `REGIME_BREAKOUT` and `REGIME_CHAOS -> MARKET_REGIME_VOLATILE`, and an invalid or warming-up snapshot -> `MARKET_REGIME_UNKNOWN`, which is the honest "no adaptation" rather than a guess. It is called at the top of `EvaluateConsensusInternal`, once per symbol per scan, and prints `[MARKET-REGIME] <symbol> | old -> new | valid=` only on a change. One source for both decisions means a vote and an AI threshold cannot disagree about what market they are in.

#### Two nearby findings deliberately not acted on
- **Consensus participation stays frozen, and wiring it would have been a new suppression.** `UpdateParticipationScore` has no caller, so every strategy's vote carries the constant `0.40 + 0.65 * 0.90 = 0.985`. Its configured targets are 1.0 for a signal, 0.65 for a filtered signal and **0.35 for none**, with decay 0.85 applied per call. Called per scan, a strategy that simply does not fire often - `NYOpenGapStrategy`, `CStatisticalArbitrageStrategy`, anything event-driven - would sit at the 0.35 floor permanently and its vote would be scaled to 0.6275 while a high-frequency strategy's was not. That is a bias invented by the wiring, not a control restored, and it is the same class as the over-restrictions Batches 186-190 had to undo. It needs a frequency-normalised metric or per-strategy targets first, which is a design decision with a journal behind it, not a 4 a.m. refactor.
- **The lifecycle's ranging-regime trailing pause is still unwired.** `CPositionLifecycleManager::m_regimeEngine` is NULL (Batch 200 recorded it). Making it per-symbol is not a one-line change: `CTradeManager::ManageAllPositions` walks the whole book and has no symbol filter, so the ranging branch and the trailing branch cannot be routed per symbol without changing the exit authority's API. This batch did not touch the exit path - that is the one place where a mistake silently stops protecting open positions.

#### Behaviour direction
AI confidence thresholds now move with the regime: more permissive in a confirmed trend, more selective in ranges and volatile expansions, unchanged while the regime engine is warming up. Indicator strategies, the consensus gate, cluster governance, the risk ceilings, the lot math, the stops and every send are untouched; no magic or comment changed, so open positions keep their identity.

#### Recorded
`m_lastCycleSignalsGenerated` / `...AfterPipeline` / `...AfterQuorum` in the same context class remain unwritten - their readers are the funnel report, which is fed by `CExecutionHeartbeatMonitor` instead.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, `OVERALL SUCCESS`, 0 errors / 0 total warnings.
- No runtime evidence yet - the newest journal is still 2026-09-23 and the EA is not attached. What to look for on the first run after this batch: at least one `[MARKET-REGIME] <symbol> | MARKET_REGIME_UNKNOWN -> ...` per symbol, then AI `[AI-VOTE]` activity differing between trending and ranging periods for the first time. If `[MARKET-REGIME]` never appears while consensus scans run, the regime engine has no validated snapshot for those symbols (`valid=false` is printed on the transition attempt), which is a data question, not a wiring one.


### Batch 200: dead code the audit had already named was deleted, and what is merely unwired is now written down

281 lines removed, 6 added, across 13 files. Every deletion was checked symbol by symbol - the scanner in this batch was only a candidate generator, and it also produced hundreds of false positives (class names, one-line accessors whose backing field is live, methods called through the delegator chain) which were all left alone. Compile is the proof that nothing still referenced them: 8 programs, 0 errors / 0 warnings.

#### Deleted

- **`CTradeAttributionManager`'s closed-trade attribution subsystem** - `m_closedTradeContributors`, `m_closedTradeNetProfit`, `m_hasClosedTradeAttribution`, `PopClosedTradeAttribution`, `ClearClosedTradeAttribution`, `GetClosedTradeNetProfit`, `HasClosedTradeAttribution`, and the two forwarders in `CAttributionDelegator` and `CEnterpriseStrategyManager`. Nothing ever set the flag, so the pop returned false for the entire life of the repo; the real path is the per-position pop in `CStrategyMgrTradeFeedback` that Batch 199 gave a writer. A second, parallel "attribution" API that always answers "no results" is the kind of thing a future reader trusts.
- **The `UpdateRegimePerformance` chain** (`CEnterpriseStrategyManager` + `CStrategyPerformanceHealth`). Its body called `RecordTradeResult` with a regime argument it discarded. `CStrategyHealthMonitor`'s same-named overload is a different method and is live from `RecordTradeResult` - it stays.
- **`CPortfolioRiskManager`'s event-driven cache hooks** - `OnPositionOpened`, `OnPositionClosed`, `InvalidateRiskCache`, `SetCacheRefreshInterval`, plus the private `AddPositionToCache`/`RemovePositionFromCache` that only they called. Portfolio risk has always been a full position scan on the constructor's 60-second interval; the comments describing incremental refresh described code no path entered.
- **`FeedMicrostructureEngines`** (`EAOrchestrator`) - a never-called copy of the VPIN/OFI and Skew Step feed that runs live in `OnTick`, differing only in its loop bound (`m_managerCount` vs `ArraySize(m_enterpriseManagerSymbols)`). Anyone editing the copy would have changed nothing, which is how a data feed for the VPIN veto the operator switched on in Batch 175 would silently stop being fed.
- **`CTradeExecutor::ExecuteBatch`** - an uncalled batch-send loop with its own `[EXECUTION]` print line. The live path sends candidates one at a time from the orchestrator's per-symbol loop, under `maxSends` there. Two `[EXECUTION]` emitters, one of them dead, is a log-reading trap.
- **`CDiagnosticsManager`** - `EmitNNHealthCheck` (its only effect was to advance its own throttle stamp), `GetNoSignalRate` with the two window getters only it read, `UpdateTradingPaused` (a verbatim duplicate of `SetTradingPaused`), and `m_lastNNHealthLogTime`.
- **`CEAOrchestrator::ReenableONNXAI`** and `CONNXInitManager::Reset` - the manual re-enable path, with no caller, no input and no chart event behind it. `ShouldAttemptInit` already grants a retry after backoff and clears the disabled flag when it does, so ONNX recovers on its own.
- **`CGridRecoveryEngine::GetTotalGridRisk`** and **`m_preRetrainTimestamp`**. The grid field `totalGridRisk` stays: `PrintDiagnostics` prints it. The retrain timestamp duplicated `m_lastRetrainingTime`, set in the same statement block, and nothing read it.
- **`ApplyStrategyWeights`** (`EAOrchestrator`) and its call - an empty body whose comment said a real step there would change behaviour. That is true: which is why the no-op went rather than being filled in.

#### Recorded, not deleted - each one is a behaviour change and needs its own batch

- **Consensus participation is a constant.** The roster registers `participationScore = 0.90` at `StrategyMgrRoster.mqh:256` and nothing ever calls `UpdateParticipationScore` / `RecordSignalGenerated` / `RecordSignalFiltered`, so `GetStrategyParticipationMultiplier` returns `0.40 + 0.65 * 0.90 = 0.985` for every strategy on every vote. The score formula's adaptive term has never adapted. Wiring it changes relative vote weight - which is what "catch more trades" would need, but on evidence, not on a guess about the target constants.
- **The neural net has never seen a realized P&L.** `ReservePredictionForSignal` has no caller, `candidate.predictionId` is never assigned (only read at `TradeExecutor.mqh:416`), so no order comment carries `|N:<id>`, `AccumulatePendingCloseProfit` is never called, and `ProcessClosedPositionsForNNTraining` returns at zero every cycle. `[NEURAL-NET] TRAIN-BOOTSTRAP` says this out loud at runtime. It is not a one-line fix: `GetPendingCloseProfits` reads the prediction id from the **live** position comment, which no longer exists by the time a closed position is read, so the wiring has to route through the persistent position-to-prediction map that `UpsertPredictionPositionMap` maintains but nobody writes outside the self-test.
- **`CPositionLifecycleManager::SetRegimeEngine` has no caller**, so `m_regimeEngine` is NULL and the ranging-regime branch at `PositionLifecycleManager.mqh:372` never runs - trailing stops apply in ranging markets exactly as they do in trend, while the code says they should not. One global engine pointer is the wrong shape for thirteen symbols anyway; the correct source is `GetManagerForSymbol(symbol)`, which that class already has.
- **The heartbeat's paused field always prints false.** `m_tradingPaused` is written only by two uncalled setters, while `CSyntheticSpikeMonitor` holds the real pause state. Log-truthfulness only, no gate depends on it.
- **Wireable feature surfaces left intact:** `EntStrategyQuorumConfig`'s 13 adaptive-quorum and sparse-intrabar getters, `CorrelationEngine`'s documented dead surface (`Refresh`, `ForceRefresh`, `IsCorrelatedCluster`, `CountCorrelatedPositions`, `Reset`, `GetConfig`), `CTradeAttributionManager::BuildClusterTaggedTradeComment` (Batch 199's reasoning stands: the comment field is the ownership discriminator), and the read-only accessors `GetLastVPINMultiplier` / `GetAuthorityBlockedTotal`, whose deletion would leave their live counters write-only.
- `StrategyMgrTradeFeedback.mqh`'s comment about the closed-trade fields was rewritten because it named a method that no longer exists.

#### Comment hygiene

Seven file headers written as decomposition reports (16-25 lines each: batch IDs, "byte-for-byte relocation" assurances, per-method inventories restating the code below them) were cut to what a reader cannot recover from the file - what the module owns, whether it holds a back-pointer or is kept by value behind forwarders, the do-not-include-standalone rule, and the items deliberately left in the parent class with the reason: `IntrabarPolicy.mqh`, `ExecutionQualityTracker.mqh`, `EntStrategyQuorumConfig.mqh`, `TradeMgrSymbolTradeRegistry.mqh`, `TradeMgrConfirmationQueue.mqh`, `StrategyRegistryState.mqh`, `DiagMgrHeartbeat.mqh`. The `*** CONSENSUS-GATE INTEGRITY NOTICE ***` banner went first. Each file's non-comment lines were compared against `HEAD` by script: all seven byte-identical, so no code moved in these edits.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, `OVERALL SUCCESS`, 0 errors / 0 total warnings - MQL5 resolves every remaining reference, so no deleted symbol is still called anywhere in the two EA programs or the five tool programs.
- No executable line outside the deleted blocks changed: the only edits that touch live code are the call-site removal of `ApplyStrategyWeights` (empty body) and comment rewording. No magic, comment, lot, stop, gate or send changed, so open positions keep their identity.
- Doc line references into the 13 touched files were re-derived from the diff hunks (16 shifted, 2 corrected for staleness that predated this batch: `EnterpriseStrategyManager.mqh:1080-1086` is the delegator re-bind, `GridRecoveryEngine.mqh:499-511` is the level-ticket loop).


### Batch 199: the strategy-outcome learning loop had no writer, so nothing the EA traded ever taught it anything

#### The missing setter (`Core/Management/EntStrategySignalContext.mqh`)
`m_lastSignalContributors`, `m_lastSignalContributorIndices` and `m_lastContributorCount` are read in four places and written in none. The class documented itself honestly - "every one of these fields is WRITE-ONCE-AT-CONSTRUCTION" - and every consumer downstream of that empty array behaved as advertised on an empty input. The same file's `m_lastSignalRole` / `m_lastSignalCluster` / `m_lastSignalClusterCode` had the same problem, so `GetLastSignalExecutionContext()` returned empty tags forever and `GetTotalSignals()` stayed 0.

What that switched off, verified consumer by consumer:

- **The EA never knew which strategies made money.** `CStrategyMgrTradeFeedback` pops per-position contributors at close and calls `UpdatePerformance(contributor, netProfit)`; that is the only writer of the roster's `successCount`/`failCount`/`totalTrades`/`healthScore`. With attribution never recorded, the pop never happened. `GetStrategyReliabilityMultiplier` therefore read the registration default (0.75) for every indicator strategy on every vote, permanently: `score = conf * weight * participation * 1.025 * regimeMult`. AI rows were the exception - `UpdateAIPerformanceMetrics` (called at `EAOrchestrator.mqh:3018-3024`) writes their health directly - so the indicator book kept a fixed neutral multiplier whatever it earned, while the AI book was held to its results.
- **Performance auto-disable never ran.** `ShouldDisableStrategy` needs `recentTradeCount >= 5` or `consecutiveLosses >= limit`, and both only move through that same chain. `[Enterprise-Adaptation] ... Strategy DISABLED` was unreachable.
- **Cluster governance was bypassed.** `ValidateClusterGovernance` returns true at `requestClusterCode == "N"` (`RiskValidationPipeline.mqh:949`), and an unset context normalizes to exactly that. Every cap per cluster (5 positions, 5% risk by default) and the opposing-cluster mutex was skipped for every consensus candidate, on every tick.
- **PROVEN_AI promotion never saw an outcome.** `RecordExecutedTradeProvenance` is called under `if(candidate.hasAIContributor)`, and `hasAIContributor` comes from `ContributorsIncludeAI(GetLastSignalContributors(...))` - an empty list - so it was always false, no provenance was ever recorded, `FeedAuthorityOutcome` always returned at `found < 0`, and `[AUTHORITY-LEARN]` never printed. The gate Batch 32 made live had no input.
- **The manager report's funnel was arithmetic on zeros.** `Total Signals: 0 | Success Rate: 0%`, and per-strategy `Trades: 0 | Win Rate: 0%` for every strategy on every symbol.

#### The writer
`EvaluateConsensusInternal` publishes at the one point where the winning side is known and every gate has passed: `SetLastSignalContributors(winningContributors, dominantRole, dominantCluster, normalizedClusterCode)` (`ConsensusEngine.mqh:1007-1021`), with names resolved from the roster so they match `GetStrategyIndexByName`, and the cluster code normalized through `CRiskClusterCodec` because risk compares it letter-for-letter.

Attribution is recorded **at execution against the fill's own `positionId`** (`EAOrchestrator.mqh:3544-3563` -> `AttributeExecutedPosition`), not at `DEAL_ENTRY_IN` from the cached context. The cache holds whichever decision ran last; the send knows exactly which voters produced this trade. The old `DEAL_ENTRY_IN` upsert is removed for that reason, and provenance now records every executed trade rather than only AI ones. Each attribution prints `[TRADE-ATTRIBUTION] <symbol> | position= | contributors=` so the loop's first live output is visible.

Engine books are now filtered out of the feedback path before anything is recorded (`StrategyMgrTradeFeedback.mqh:111-118`, by comment tag *or* by Batch 197's magic band). This is the gap Batch 197 recorded: an engine deal on a symbol with a live contributor context would otherwise be tagged with strategies that never signalled it, and its P/L would move their weight.

#### One gate that had to be tightened before the codes could flow
`CVirtualPositionBook::HasOpposingReservation` returned "no conflict" when the two reservations shared a cluster code, and "conflict" when they differed or either was empty. While every code was empty it always conflicted - correct, by accident. Populating codes would have flipped that branch into a live loosening: two opposing reservations on one symbol in the same cluster would both be accepted. The cluster test is gone; an opposing reservation on the same symbol is a conflict, and the `clusterCode` parameter went with it (one caller).

#### Also wired
`RiskTieredCorrelation.mqh:103` had `string correlationReason = "";  // GetLastBlockReason would need to be added`. `CPortfolioRiskManager::CheckCorrelationLimits` already records the exact pair and thresholds it compared (`Correlation 0.83 > Max 0.70 (X vs Y)`); the refusal just never read it back, so `[SIGNAL-REJECTED]` said "Correlation limit exceeded" while the real reason sat in the object. It is read now. This is the one dead accessor in the batch that could be wired; the ones that could not are Batch 200's list.

#### Behaviour direction
Strictly more governance and real learning. On the next attach: cluster caps and the opposing-cluster mutex start evaluating (new `[RISK-CLUSTER]` lines, and refusals where none occurred), per-strategy health starts moving off 0.75 so reliability multipliers diverge for the first time, losing indicator strategies become disableable, and `[AUTHORITY-LEARN]` appears for AI trades. Entry count can only go down from this change; entry *quality* weighting is what goes up. Nothing here touches the risk ceilings, the lot math, the stops, or any send - no magic, comment or lot changed - so open positions keep their identity.

#### Recorded, not changed
- `m_lastSignalSymbol` and `m_lastSignalTime` now carry real values and still have no reader. They are the pair a staleness guard on the context would need; adding the guard without evidence of the race is speculation.
- `CTradeAttributionManager::BuildClusterTaggedTradeComment` has no caller, so no position comment carries `K:<code>`. Consequence: `ParseClusterCodeFromComment` reads "N" for existing positions, and `ValidateClusterGovernance`'s same-symbol substitution (`:972`) means the mutex currently fires on direction, not cluster. Wiring the marker into live comments would change the field Batch 196 and Batch 197 use as the ownership discriminator, and would hand the mutex the same-cluster case it currently exempts - a loosening dressed as a completion. Left for the operator to decide with logs in hand.
- The two-tier and solo-fallback consensus paths are still uncalled (documented dead since Batch 17x), so only the main decision publishes contributors. If either is ever wired, it must publish too or its trades score nothing.
- `m_lastCycleSignalsGenerated` / `...AfterPipeline` / `...AfterQuorum` remain unwritten; the heartbeat's funnel stages come from `CExecutionHeartbeatMonitor`, not from these.

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, `OVERALL SUCCESS`, 0 errors / 0 total warnings. Two compile rounds failed first (a `const string &` parameter that cannot bind a function's return value, and the stale 3-argument `HasOpposingReservation` call) and are fixed, not suppressed.
- No runtime evidence - newest journal still 2026-09-23, the EA is not attached. Expected first-run evidence: `[TRADE-ATTRIBUTION]` per executed consensus fill, `[RISK-CLUSTER] cluster=T|R|S ...` per candidate instead of the early return, `[AUTHORITY-LEARN]` on the first AI-contributed close, non-zero `Trades:` in the strategy report, and possibly the first `[Enterprise-Adaptation] ... DISABLED` line. If `[TRADE-ATTRIBUTION]` never appears while trades execute, the context writer did not reach the decision path.


### Batch 197: engines got their own magic bands, the lifecycle manager stopped disowning its own positions, and a restart no longer forgets the grid

#### The layout (`Core/Utils/MagicRange.mqh`)
One number names one owner. The symbol is read from the position, so no engine has to encode it:

| owner | magic |
|---|---|
| consensus | `base + assetClassOffset + symbolIndex * 100` |
| fast scalp | `base + 6000` |
| ATR scalp | `base + 6100` |
| grid recovery | `base + 6200 + level` |
| spike hunter | `base + 6300` |

Asset-class offsets start at 7000 (ASSET_FOREX) and run to 9999 (DERIV_UNKNOWN), so the four engine bands live in a range no consensus magic can reach, and `[MAGIC-LAYOUT]` asserts exactly that at init for every symbol slot in the universe: a composed consensus offset that lands in 6000..6399 is a `[CRITICAL]` and a refused start, not a silent merge. Only `ASSET_UNIVERSAL` (offset 0) can reach the band, at symbol slot 60 or above.

#### The consensus magic was one number per asset class
`EAOrchestrator` registered the per-symbol table with `SetMagicOffsetForSymbol(sym, profile.magicOffset)` - the asset offset alone, no symbol slot - so `TradeManager.mqh:1267` stamped **every** forex pair with `base + 7000` and every Deriv volatility index with `base + 9100`. Two symbols in one class were the same book to any magic-keyed reader, and the `[MULTI-ASSET-PROFILER] ... magic=+%d` line printed the same number for all of them. The slot term is added now, which is also what makes the bands meaningful: an engine offset of 6000-6399 can no longer be reached by a consensus composition.

Verified before shipping: no risk gate, exposure cap or exit reads an exact consensus magic. `POSITION_MAGIC` is read in nine places; seven feed a window test (`IsEAOwnedMagic` / `IsOwned` / `IsLifecycleManaged`), one is the grid's own symbol+level lookup at `GridRecoveryExecution.mqh:210` (filtered by symbol first), and one is the deal-attribution filter. So the new number changes what a fresh position is *labelled*, not what any decision counts.

That filter is where the ambiguity was, and it is not the exact match it looks like: `EAOrchestrator.mqh:1791` seeds every per-symbol manager with the **bare base** as its `managedMagic`, so `CStrategyMgrTradeFeedback::IsEAOwnedMagic`'s `magic == m_managedMagic` arm matches nothing real and the `(base, rangeMax]` arm matches every EA position - the test never filtered by owner, only by "is this ours", and the next line filters by symbol. A fast scalp deal on a symbol therefore reached the same branch as a strategy deal with both gates open. It stopped there: the attribution that branch performs reads a contributor list that nothing wrote (Batch 199 found that writer missing), so through Batch 196 a scalp was never actually scored as a strategy's trade. What the shared magic did cost was ownership ambiguity for every magic-scoped consumer - `UnprotectedPositionTracker`, `BasketEquityStop`, the dedup guard at `TradeManager.mqh:1335`, the `[SCALP-PENDING]` recovery scan, and Batch 196's fill matcher, which had to fall back to position comments precisely because magic could not resolve an owner.

#### The collisions this removed
- **Fast scalp, both branches.** `FastScalpEntry` sent through `CTradeManager::OpenPosition` with magic 0, and `TradeManager.mqh:1267` then composed `base + GetMagicOffsetForSymbol(symbol)` for market orders - which, with the asset-offset-only table above, was the consensus magic of *every symbol in that asset class*. The async branch composed it by hand to the same number, and `FastScalpPendingOrders` shipped the bare `base`. Every fast scalp on the live book was indistinguishable by magic from a strategy entry on its own symbol and on its siblings.
- **ATR scalp** composed `base + 7000 + symbolIndex`, and pre-197 consensus forex entries carried exactly `base + 7000` - so at slot 0 the two were the same number, and at any other slot the scalp sat one register away from every forex symbol's magic.
- **Grid** composed `base + 8000 + symbolIndex*100 + level` and **spike** `base + 9150 + symbolIndex` - not a direct collision, but both lived inside the range consensus magics are built from, so any new asset-class offset or profile change could claim a grid level's number with no code change anywhere.

Why it mattered, stated precisely this time. A fast scalp deal did reach the strategy feedback branch on its own symbol - `IsEAOwnedMagic` is a window test and the next filter is the symbol - but the attribution that branch performs had nothing to attribute, because the contributor list it reads was never written (Batch 199 found and fixed that missing writer). So through this batch the shared magic's real cost was ownership ambiguity, not mis-scoring: `UnprotectedPositionTracker`, `BasketEquityStop`, the transient-retcode dedup guard at `TradeManager.mqh:1335`, the `[SCALP-PENDING]` recovery scan and Batch 196's fill matcher all key on magic, and a scalp and a strategy entry on one symbol were the same number to every one of them - which is exactly why Batch 196 had to use position comments as the discriminator. With the bands in place, Batch 199 could wire the attribution loop without opening the scalp-contamination path, and the engine filter added there keeps it closed for positions opened before this build. Fast scalp is the only engine with a tick-loop driver (`[ENGINE-STATUS]`, Batch 178), so its band is the live half of the renumber; ATR scalp, grid and spike are parked, and any level they opened before Batch 178 parked them still sits on the account with a consensus-band magic.

Positions opened before this batch keep their old magics, so the comment tags (`ATR-SCALP`, `GRID-RECOVERY`, `SPIKE-HUNT`, `SCALP|`) stay the exit discriminator - a legacy scalp still carries a consensus-band magic and only its comment tells it apart. The renumber changes what new sends ship; nothing that reads an existing position changed.

#### Grid restart reconciliation (`Core/Scalp/GridRecoveryLevels.mqh`, `GridRecoveryEngine.mqh`)
Level tickets lived only in `m_symbolStates[].levels[]`, so every restart, recompile or chart change wiped them while the positions stayed open: the grid believed it held nothing, laid a fresh level 0, and the orphaned levels ran to their own stops with no manager and no drawdown gate - `CalculateGridDrawdownPercent` and `CloseAllGrids` both walk the level table. `RecoverOpenGridLevels()` now runs at init before `[GRID-RECOVERY] Initialized`, scanning open positions whose comment starts with `GRID-RECOVERY` and rebuilding each slot from the position's own magic, symbol, volume, entry, SL and TP. Post-Batch-197 levels decode as `magic - base - 6200`; pre-Batch-197 levels decode through `% 100` off the legacy 8000 band, so positions opened before the renumber are still recovered. A slot already held, or a number that is not a level slot, prints `[GRID-RESTART]` and is left alone rather than double-bound. `OpenGridLevel` also now refuses a level outside `0..MAGIC_CLUSTER_SPAN` instead of shipping a magic that would decode onto another band.

The engine is parked (`InpGridRecoveryEnabled` has no tick-loop caller since Batch 178), so this closes a latent hole rather than a live leak: it is the reason wiring the grid back in does not immediately re-open it on the next recompile, and it recovers any level a pre-178 build left open on the account.

#### The lifecycle manager was disowning the book (`Core/Management/PositionLifecycleManager.mqh`)
`IsEAOwnedMagic()` still computed `base + symbolCount*100 + maxClusterCode` - the shape Batch 168 removed from `CPositionMgrMagicFilter`, `SyntheticSpikeMonitor` and `UnprotectedPositionTracker` one at a time, and this was the last one left. With the default 13-symbol universe the ceiling was `base + 1399`, while the shipped consensus magics sit at `base + 7000..9400` plus slot: **every position on twelve of the thirteen symbols was "not ours"**. `ManageSignalReversalExit` and the ranging-regime breakeven loop both gate on `IsPositionLifecycleManaged()`, so `InpEnableSignalReversalExit = true` bought nothing: a reversal against an open position never closed it, and a ranging position that reached profit never moved to breakeven. Only ASSET_UNIVERSAL symbols (offset 0, BTCUSD on the default list) fell inside the window. It now delegates to `CMagicRange::IsOwned(magic, base, MagicMax())`, the same call every other owner makes.

This one turns behaviour *on*: on the next attach, signal reversal exit and ranging breakeven start acting on consensus positions for the first time. Both are bounded by their inputs (`InpSignalReversalMinLossR`/`MaxLossR`/`MinTimeSec`, the profit guard) and both were already configured by the operator.

#### Recorded, not changed
- **This entry's attribution claim was wrong and Batch 199 corrected it.** As written on 2026-10-14 this batch asserted that a scalp fill "arrived as that symbol's strategy deal" and scored against those strategies' performance. Checking the writer while building Batch 199 showed the contributor context that path reads had none, so nothing was ever attributed - to a scalp or to a strategy entry. The paragraph above now says what was actually cost (ownership ambiguity for magic-scoped scans) and what the real defect was. Recorded here because an overclaimed money consequence is the mistake this repository's process exists to catch.
- **The attribution context still bound by symbol, not by owner.** `CStrategyMgrTradeFeedback::OnTradeTransaction` accepted any deal inside the window on the manager's symbol and tagged it with the manager's cached contributors. Batch 199 replaced both halves of that: the context is written by the decision, and attribution is keyed to the fill's own `positionId` at execution.
- **`managedMagic` is the bare base for every manager** (`EAOrchestrator.mqh:1791` passes `m_config.magicNumber`), so `CStrategyMgrTradeFeedback::IsEAOwnedMagic`'s equality arm matches nothing real and the predicate is a window test in practice. Left alone: nothing breaks on it, and `CMagicRange` is the ownership authority.
- **Legacy positions are still discriminated by comment.** The bands give a new send an owner in its magic, but a pre-197 scalp carries a consensus magic, so `IsEngineManagedPosition` remains the exit filter for both generations - for as long as any position opened before this build is on the account.
- **`InpSpikeHunterEnabled` / `InpGridRecoveryEnabled` / `InpATRScalpingEnabled` still default ON with no tick-loop caller** (Batch 178). This batch does not wire them; `[ENGINE-STATUS]` still reports them parked, and the grid recovery is what makes wiring one safe rather than leaking its positions on the first restart.

#### Dead code removed with it
`CMagicNumberAllocator` (395 lines, `Core/Risk/MagicNumberAllocator.mqh`) is deleted. It is not a parked authority but a parallel one: its `AddFamilyOffset` table (VOLATILITY 1000, BOOM_CRASH 2000, FOREX_MAJORS 5000, CRYPTO 8000...) does not match the offsets orders actually ship with (`MultiAssetProfiler`'s asset-class table, 7000-9999), so wiring it in would renumber every open position. Its only live call was `GetMaxClusterCode()` feeding the narrow window above; with that gone the object had no reader left. `m_maxClusterCode`, the `Initialize` parameter that took it, the `AddFamilyOffset` block and `[MAGIC-ALLOC]` init logs go with the class. `ComputeGridMagic` (added earlier in this batch, then unused) also went.

Also repaired: seven `GridRecoveryEngine.mqh` log strings whose em dash had degraded to a U+FFFD/`?` byte pair in an earlier edit round now read `->`, and `FindLevelPositionTicket`'s header no longer claims the grid magic is unique per symbol (it is unique per level; the scan filters the symbol).

#### Verification
- `sync_and_compile.ps1 -All`: 8 root programs, `OVERALL SUCCESS`, 0 errors / 0 total warnings.
- No runtime evidence (newest journal still 2026-09-23; the EA is not attached this batch). Expected new lines: `[MAGIC-LAYOUT] consensus=... | fastScalp=+6000 | atrScalp=+6100 | grid=+6200+level | spike=+6300` once per start, `[GRID-RESTART] <symbol> | N level(s) rebuilt from open positions` on a restart with an open grid, `[GRID-RECOVERY] ... LEVEL REJECTED` only for a level count beyond the band, and the first `[SCALP-EXIT] Reversal detected` / `[STRUCTURAL-EXIT]` lines on consensus positions since this EA existed - note that first tag belongs to the lifecycle reversal path, not the scalp engine. `[MAGIC-ALLOC]` lines are gone and mean nothing if seen.


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

Checked before assuming: every other `GetType()` consumer compares against `STRATEGY_BRAIN` / `STRATEGY_AI_ENHANCED` (`ConsensusEngine.mqh:338`, `:1225`, `ConsensusWeightingConfig.mqh:77`, `StrategyPerformanceHealth.mqh:281`, `StrategyStateReporter.mqh:97`) or resolves a type for the live-authority report (`LiveAuthorityResolver.mqh:368`), so CUSTOM vs their real type changed nothing there. `CMagicNumberAllocator::GetStrategyOffset` does switch on strategy type and would have moved these two positions to another magic bucket - but the allocator is declared as `m_magicNumberAllocator` in the orchestrator and **no method of it is called anywhere**, so it is not the live magic scheme and this fix cannot renumber an open position.

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
Batch 193 made the catalog the registration authority. Reading what the catalog does *not* do exposed the mirror of that: `CStrategyFactory` still carries a per-strategy configuration path (`CreateMomentum` -> `SetScalpingMode`, `CreateCandlestick` -> `SetRequireTrendAlignment`, `CreateMeanReversion` -> `SetSyntheticMode`), and its only live call site is `EAOrchestrator.mqh:2482`, which passes `g_strategyCatalog[i].factoryName` - empty on every indicator row. Indicator strategies are built by `CatCreate_*`, which constructs them bare. So every input whose value travelled only through the factory config struct was inert, and the classes kept their constructor defaults instead.

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
`EAOrchestrator.mqh:3483-3487` handles a failed validation with `m_heartbeat.IncValidatorRejects(); continue;` and prints nothing. Every other arm prints its own `[POST-CONSENSUS-FILTER]` line, so the spread veto was invisible — that is why the September journals show 71 `atr_ratio` lines and not one spread line, which reads as "the spread gate never triggered" rather than "it triggered and said nothing". Both branches of the gate now print `filter=spread_vs_atr` with the ratio, the threshold in force and the ATR, and the reason string says `spread/ATR=` instead of `ratio=`.

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
The keeps are the facts a reader cannot recover from the code: `ReleaseOnDeinit()`/`FinishDeinit()` must stay separate because the manager re-binds its attribution delegator between them (`EnterpriseStrategyManager.mqh:1080-1086`); `m_diagnostics`/`m_attribution` are injected from `EAOrchestrator` and only `Deinit()` may delete them; `GetStrategyPtr(i)` is dereferenced without a NULL guard and that is deliberate; a cached ATR handle and the Hurst/VPIN engines are shared-ownership and must not be released by the strategy; liquidity pools scan **closed bars only** (`CopyRates(..., 1, ...)`), because the live bar's own high would otherwise count as one of the equal highs being swept; ATR is read at shift 1 so the sweep cap does not move with the tick being judged; the risk manager is fail-open when none is injected (`StrategyBase.mqh:479` returns true); a bullish FVG is filled on a *close* below its bottom, with a 100% wick fill as the stated exception.

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
`InpEnableLiveAuthorityGate` defaults to **false** in both `MultiStrategyAutonomousEA.mq5:216` and `MultiStrategyTestingEA.mq5:228`, and its only consumer anywhere was `if(m_config.enableLiveAuthorityGate) Print("[INIT] LiveAuthorityResolver initialized")`. `m_liveAuthority.Resolve(...)` (`EAOrchestrator.mqh:3500`) and Batch 173's `ScaleLotByLiveAuthority` are called unconditionally, so the gate has run on every candidate for the life of the codebase while a default-configured session logged nothing about it. The init print is now unconditional and says what is wired: `[AUTHORITY-GATE] live authority resolver ACTIVE on every risk-approved candidate | InpEnableLiveAuthorityGate=%s is not consulted by the sizing path`.

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
- **The grid tracked the wrong kind of ticket** (dormant path, but the defect is real and would bite the moment the engine is wired). `GridRecoveryExecution.ExecuteEntry` stored `m_trade.ResultOrder()` into `levels[level].ticket`, and that value is consumed by `PositionSelectByTicket(...)` and `CTrade::PositionClose(ticket)` — both of which take a **position** ticket. On a hedging account they are different numbers, so a grid level could never be selected or closed. Because Batch 170 excluded engine-tagged comments from lifecycle management, such a position would have **no exit owner at all**: the exit loops skip it (`PositionSelectByTicket` fails), `ticket` is reset to 0 at `GridRecoveryEngine.mqh:499-511`, and the grid would place another layer on a symbol that already holds one.
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
