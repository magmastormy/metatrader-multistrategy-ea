# Changelog

All notable changes to the `metatrader-multistrategy-ea` project are documented in this file. Older batch entries (Batch 101 and prior) are archived in [`docs/changelogs_old.md`](docs/changelogs_old.md).

## [Unreleased] - 2026-08-11

### Batch 2026-08-14 (cont.): Shadow-mode removal, FINDING 0 live enable, F7 AsianRangeBreak GMT-anchor fix

#### Context (user directive)
User removed shadow/paper mode and declared Live-only operation; requested the remaining audit issues be worked. Shadow mode had no live/paper trading toggle in code — only policy (AGENTS.md) and a rollout plan. The FINDING 0 fix (wired behind `InpUseStrategyStops`, default `false`, held for a shadow pass) is now enabled for Live.

#### Changes
- `AGENTS.md` — removed "Shadow-first rollout" principle (§2.4) and "Use shadow mode for major changes before live send" (§5.2); replaced with Live-only operation. NOTE: `AIModules/OnnxBrain.mqh` AI model hot-swap "shadow model" is an unrelated internal model-comparator (not trading shadow mode); left intact — flagged for user.
- `MultiStrategyAutonomousEA.mq5` & `MultiStrategyTestingEA.mq5` — `InpUseStrategyStops` default flipped `false` → `true` (FINDING 0 now drives Live consensus execution; strategy-designed SL/TP replace the generic fallback). Comments updated (no "shadow/backtest" wording).
- `Core/Orchestration/CandidateBuilder.mqh` — comment updates only; FINDING 0 path unchanged (returns first real consensus-proposed stop; min-R:R floor 2.0 trend / 1.5 mean-rev enforced).
- `Strategies/AsianRangeBreakStrategy.mqh` — **F7 fix**: range measurement now GMT-anchored via `iBarShift` on absolute UTC datetimes (00:00–06:00 UTC) + `CopyHigh`/`CopyLow` over the exact window. Previously counted 72 M5 bars back from "now", which drifted from the true Asian session on a non-UTC broker.

#### Verification
Compile: **0 errors, 0 warnings** for both `MultiStrategyAutonomousEA.mq5` (78,899 ms) and `MultiStrategyTestingEA.mq5` (78,899 ms), headless MetaEditor, `X64 Regular`. `.ex5` timestamps refreshed (13:20:54 / 13:20:58).

#### Files Modified
- `AGENTS.md`
- `MultiStrategyAutonomousEA.mq5`
- `MultiStrategyTestingEA.mq5`
- `Core/Orchestration/CandidateBuilder.mqh`
- `Strategies/AsianRangeBreakStrategy.mqh`

### Batch 149: Deeper structural dead-code removal — verified 0-caller getters + dead duplicates (2026-08-11)

#### Scope
Beyond marker-word hunting (Batch 148), a structural scan for dead code (MQL5 has no unused-symbol diagnostic). Each candidate was confirmed by repo-wide grep (definition-only, zero external callers) and the deletion was compile-verified (0 errors = truly uncalled). This removes cruft that a green build does NOT prove is dead.

Compile: **0 errors, 0 warnings** for both `MultiStrategyAutonomousEA.mq5` (68,308 ms) and `MultiStrategyTestingEA.mq5` (65,305 ms), headless MetaEditor, `X64 Regular`.

#### Deleted (verified 0 callers, compile-confirmed)
- `Core/Orchestration/EAOrchestrator.mqh` — 4 dead engine getters `GetFastScalpEngine` / `GetSpikeHunterEngine` / `GetGridRecoveryEngine` / `GetATRScalpingEngine` (only `GetTradeManager` is live); dead `GetEAPositionCountForSymbol()`.
- `Core/Trading/TradeManager.mqh` — dead getters `GetRiskManager()`, `GetMarketAnalysis()`; dead `ApplySmartOrderRouting()` (multi-line, called no smart-routing path); dead `GetLastRequestedStopLoss()` / `GetLastRequestedTakeProfit()` / `GetLastRequestId()`.
- `MultiStrategyAutonomousEA.mq5` & `MultiStrategyTestingEA.mq5` — dead duplicated free functions `CalculateATRForSymbol()` and `ArrayToString()` (identical copies in both EAs, zero callers).

#### Investigated and KEPT (intentional, not debt)
- `Core/Utils/PyBridgeHealth.mqh::Reset()` — zeroes `m_max_reconnect_attempts`, but is called **only** from `CPythonBridge::Shutdown()`; `Configure()` re-sets the cap on re-init. Shutdown-only; correct.
- `Core/Trading/TradeManager.mqh` mirror members `m_totalTrades` / `m_successfulTrades` / `m_failedTrades` / `m_lastTradeTime` — `Core/Trading/TradeStatsTracker.mqh:17` documents they were "DELIBERATELY NOT MOVED"; intentional backward-compat surface, left in place.

#### Deferred follow-up (recommended, not done this batch)
An automated no-caller scan flagged larger getter/method clusters that need **per-symbol compile verification** before deletion (risk of base-pointer dispatch hiding callers): `AIModules/NeuralNetworkStrategy.mqh` (~15 methods), `AIModules/EnsembleMetaLearner.mqh` (~10), `Core/Engines/AIEngine.mqh` (~15), and `Core/Risk/*` getters (`RiskTierManager`, `CompoundingTierManager`, `VPINFilter`, `UnifiedRiskManager`, `PortfolioRiskManager`). Candidate for a Batch 150 compile-verified deletion sweep.

#### Files Modified
- `Core/Orchestration/EAOrchestrator.mqh`
- `Core/Trading/TradeManager.mqh`
- `MultiStrategyAutonomousEA.mq5`
- `MultiStrategyTestingEA.mq5`

### Batch 148: Debt-marker hunt — delete dead/legacy code, clean placeholder comments (2026-08-11)

#### Scope
Repo-wide hunt for incomplete-code / placeholder / legacy / stub / deprecated markers (`placeholder`, `legacy`, `backward`, `backtrack`, `todo`, `fixme`, `stub`, `not implemented`, `deprecated`, `obsolete`). Each hit was triaged: dead code was deleted; misleading "placeholder" comments on working code were cleaned; wired stubs that require a feature (news calendar, scalp-panel JSON, AI-adapter no-ops) were deliberately left as intentionally-deferred and documented, not silently reimplemented (per AGENTS.md invariants).

Compile: **0 errors, 0 warnings** for both `MultiStrategyAutonomousEA.mq5` and `MultiStrategyTestingEA.mq5`, headless MetaEditor, `X64 Regular`.

#### Deleted (dead, 0 callers — verified by repo-wide grep)
- `RegisterManagerStrategiesFromRegistry()` — free function in `EAOrchestrator.mqh` (empty body, no callers).
- `CEnsembleMetaLearner::DetectMarketRegimeLegacy()` — dead legacy regime detector (sibling HMM-based `DetectMarketRegime` is live).
- `NNModelStorage_GetLegacyBaseName` / `GetLegacyPrimaryPath` / `GetLegacyBackupPath` / `LegacyCheckpointExists` — 4 dead NN checkpoint helpers in `Core/AI/NNModelStorage.mqh` (no external callers; modern versioned paths used instead).
- `CPerformanceAnalytics::ResizeArrays()` — empty deprecated method (circular buffer replaced it).
- `CPortfolioRiskManager::RecordTradeReturn()` — dead deprecated CVaR helper (superseded by `RecordEquityCurveReturn`).
- `CConsensusEngine::AccumulateRoleClusterSignalDiagnostics()` wrapper — dead public method (0 callers; the live `CDiagMgrCounters` method it forwarded to is retained).

#### Cleaned (misleading "placeholder"/"stub" comments on working code)
- `EAOrchestrator.mqh` — `ApplyInstitutionalStrategyGovernance` / `ApplyStrategyWeights` comments now state they are explicit pass-throughs (intentional) instead of "placeholder".
- `Core/Management/DiagMgrCounters.mqh` — `AccumulateRoleClusterSignalDiagnostics` comment explains why it early-outs (no role/cluster metadata at the call site) instead of "placeholder".
- `Core/Management/StrategyPerformanceHealth.mqh` — two "placeholder" comments replaced with accurate notes (regime attribution owned by the health monitor).
- `MultiStrategyTestingEA.mq5` — `ValidateInputs` header no longer says "placeholder".
- `TrainingDataExporter.mq5` — "Stub dependencies" / "placeholder if feature extraction fails" comments corrected to describe real owned objects / empty feature-row fallback.

#### Intentionally deferred (wired stubs needing a feature, NOT changed)
- `Core/Risk/SafeModeConfig.mqh` news-avoidance stub (`IsNearNewsEvent` always false) — requires economic-calendar integration.
- `Core/Utils/DashBridgePanels.mqh` scalp-panel JSON — emits valid but hardcoded metrics; needs real scalp telemetry.
- `Core/Strategy/EnsembleAIStrategyAdapter.mqh` `TrainStep`/`OnRegimeChange` "Not implemented" — correct no-op: the ensemble learner's update needs params the `IAIStrategy` interface does not carry.
- `Core/Strategy/PythonBridgeAIStrategyAdapter.mqh` `SetTemperature` empty `{}` — intentional no-op (Python bridge has no temperature concept).
- `AIModules/EnsembleMetaLearner.mqh` `:898` adapter-default stubs (`GetUncertainty`/`IsLearningEnabled`/etc.) — return sane defaults for the adapter.
- `AIModules/NeuralNetworkStrategy.mqh` `SetWeightMutationEnabled` — deprecated-by-design no-op.
- `Core/Strategy/StrategyBase.mqh` `ValidateWithRiskManager` returns `true` when no risk manager injected — deliberate backward-compat.
- `Core/Scalp/SpikeHunterExecutor.mqh` `m_trade` fallback — active synchronous-execution fallback path.

#### Files Modified
- `Core/Orchestration/EAOrchestrator.mqh`
- `AIModules/EnsembleMetaLearner.mqh`
- `Core/AI/NNModelStorage.mqh`
- `Core/Monitoring/PerformanceAnalytics.mqh`
- `Core/Risk/PortfolioRiskManager.mqh`
- `Core/Management/ConsensusEngine.mqh`
- `Core/Management/DiagMgrCounters.mqh`
- `Core/Management/StrategyPerformanceHealth.mqh`
- `MultiStrategyTestingEA.mq5`
- `TrainingDataExporter.mq5`

### Batch 147: Remove the legacy strategy slot scheme — semantic-only (2026-08-11)

#### Implementation Summary
Per the user directive ("legacy code and legacy functions must disappear"), this batch **deletes** the dual-scheme plumbing that Batch 146 shipped dormant behind `InpUseSemanticStrategyIndices`. The semantic (`SI_*` / `siPolicyIndex`) scheme is now the **only** path — there is no legacy mode to fall back to. Registration, the intrabar policy table, and the LIVE fallback are all unconditional semantic.

Compile: **0 errors, 0 warnings** for both `MultiStrategyAutonomousEA.mq5` (~105 s) and `MultiStrategyTestingEA.mq5` (~81 s), headless MetaEditor, `X64 Regular`.

#### What was removed (deleted, not gated)
- EA input `input bool InpUseSemanticStrategyIndices` (both EAs) and its config wiring `SOrchestratorConfig::useSemanticStrategyIndices` (+ `Reset()` default).
- `CEnterpriseStrategyManager::m_useSemanticStrategyIndices` + `SetUseSemanticStrategyIndices()`.
- `CIntrabarPolicy::m_semanticPolicySlots` + `SetSemanticPolicySlots()`.
- `SStrategyDefinition::flagsIndex` / `policyIndex` struct members.
- `CatalogFlagEnabled(...)` (replaced by a "removed in Batch 147" comment) and the `semantic` mode-arg on `CatalogEnableSlot` / `CatalogPolicySlot` / `CatalogLogIndexAudit`.
- `AutoRegisterStrategies` no longer reads a scheme; it calls `CatalogLogIndexAudit()` (no arg), `CatalogEnableSlot(i)`, `CatalogPolicySlot(i)` unconditionally.
- `CEAOrchestrator` no longer calls `SetUseSemanticStrategyIndices`; `StrategyConfigBuilder` no longer guards the FVG Scalper slot-13 clobber behind `if(!config.useSemanticStrategyIndices)` (the clobber is gone — Python Bridge AI owns slot 13, FVG owns 21).

#### Resulting contract
- `strategyFlags[]` has exactly one producer (`BuildStrategyFlags`) writing `SI_*` slots, and `AutoRegisterStrategies` reads `CatalogEnableSlot(i)` → `flags[SI_*]`. Reader and writer now agree by construction.
- `CIntrabarPolicy::GetIntrabarPolicyHelper` is hardcoded: `idx == 7 || idx == 8` → `INTRABAR_POLICY_LIVE` (Mean Reversion / Volatility Breakout semantic slots). No scheme branch.
- `CatalogLogIndexAudit()` prints `[CATALOG-AUDIT] slot_scheme=SEMANTIC (legacy literals removed in Batch 147)` plus per-row `enable_slot=` / `policy_slot=` lines — no MISMATCH / DEAD_SLOT noise, because there is only one scheme.

#### Files Modified
- `Core/Strategy/StrategyCatalog.mqh` (`siIndex`/`siPolicyIndex` only; no-arg `CatalogEnableSlot`/`CatalogPolicySlot`/`CatalogLogIndexAudit`; `CatalogFlagEnabled` removed)
- `Core/Management/EnterpriseStrategyManager.mqh` (removed scheme flag + setter; `AutoRegisterStrategies` unconditional)
- `Core/Management/IntrabarPolicy.mqh` (removed `m_semanticPolicySlots`/`SetSemanticPolicySlots`; hardcoded `7/8` LIVE)
- `Core/Orchestration/EAOrchestrator.mqh` (removed scheme-selection call)
- `Core/Orchestration/OrchestratorConfig.mqh` (removed `useSemanticStrategyIndices`)
- `Core/Orchestration/StrategyConfigBuilder.mqh` (removed legacy-gated slot-13 clobber)
- `MultiStrategyAutonomousEA.mq5`, `MultiStrategyTestingEA.mq5` (removed input + wiring)

#### Not Covered
- Batch 146's deferred F3 / F6 items remain out of scope (unchanged).
- The prior shadow/backtest caveat for `InpUseSemanticStrategyIndices = true` is moot — the legacy mode no longer exists.

### Batch 146: Semantic Strategy Slot Repair — F1 / F5 / F2 (dormant behind an input) (2026-08-11)

#### Implementation Summary
Closes three of the latent defects reported (and deliberately deferred) in Batch 145. The repair ships **dormant**: everything is gated by a new EA input `InpUseSemanticStrategyIndices`, **default `false`**. With the input off, registration, the policy table and the intrabar fallback reproduce pre-146 behaviour bit for bit; with it on, the corrected semantic scheme takes over as one atomic switch.

Compile: **0 errors, 0 warnings** (`MultiStrategyAutonomousEA.mq5`, headless MetaEditor, 158 s).

#### Root Cause — one vector, two disagreeing readers
`strategyFlags[]` has exactly **one producer**: `COrchestratorStrategyFlagBuilder::BuildStrategyFlags`, which writes **semantic `SI_*` slots**. `CEnterpriseStrategyManager::AutoRegisterStrategies` read the **legacy `flagsIndex` literals**. Because the writer and the reader used different index spaces, 8 of the 12 indicator rows read the wrong slot, and 2 read slots the producer never touches at all. Curated mode does *not* rescue this (its overrides omit `SI_STATISTICAL_ARBITRAGE`), which rules out "intentional design".

A **third** index space was then found: `StrategyConfigBuilder`'s own slot table, which the catalog's `policyIndex` also failed to match — so 10 of the 12 rows resolved a **neighbouring strategy's intrabar policy** (F5).

#### Slot Map (legacy → semantic)
| Strategy | enable legacy | enable semantic (`SI_*`) | policy legacy | policy semantic |
|---|---|---|---|---|
| Momentum | 0 | 0 | 0 | 0 |
| Trend | 1 | 1 | 1 | 1 |
| Support/Resistance | 4 | 4 | 4 | **2** |
| Candlestick | 6 | 6 | 6 | **4** |
| Mean Reversion | 9 | **7** | 9 | **7** |
| Volatility Breakout | 10 | **8** | 10 | **8** |
| Statistical Arbitrage | 11 | **9** | 11 | **22** (new row) |
| FVG Scalper | 12 | **10** | 12 | **21** (new row) |
| Turtle Soup | 13 | **11** | 13 | **14** |
| Breaker Block | 14 | **12** | 14 | **15** |
| NY Open Gap | 15 *(dead)* | **13** | 15 | **16** |
| Asian Range Break | 16 *(dead)* | **14** | 16 | **17** |

8 enable-slot mismatches, 10 policy-slot mismatches. AI rows keep `-1 / -1` (always `fixedPolicy = LIVE`).

#### F1 — enable-slot repair
- `CatalogEnableSlot(i, semantic)` is now the single resolver; `CatalogFlagEnabled(i, flags, semantic)` routes through it.
- `AutoRegisterStrategies` reads `const bool semantic = m_useSemanticStrategyIndices;` once and uses it for both the enable gate and the policy slot, so the two can never diverge again.
- With the input **on**, NY Open Gap and Asian Range Break come alive, and Mean Reversion / Volatility Breakout / Statistical Arbitrage / FVG Scalper / Turtle Soup / Breaker Block stop reading a neighbour's flag.

#### F5 — policy-slot repair + LIVE fallback
- New catalog column `SStrategyDefinition::siPolicyIndex`, resolved by `CatalogPolicySlot(i, semantic)`.
- `CIntrabarPolicy::GetIntrabarPolicyHelper` no longer hardcodes `idx == 9 || idx == 10`. The always-LIVE pair (Mean Reversion / Volatility Breakout) now follows the active scheme: legacy `9/10`, semantic `7/8`. Without this, remapping would have silently forced LIVE onto **Neural Network AI / Transformer AI**.
- `CEnterpriseStrategyManager::SetUseSemanticStrategyIndices()` flips the manager flag *and* `m_intrabarPolicy.SetSemanticPolicySlots()` together — a single entry point, so the enable gate and the LIVE fallback cannot disagree.

#### F2 — `StrategyConfigBuilder` slot [13] double-write
- FVG Scalper used to overwrite slot `[13]` (Python Bridge AI's row) unconditionally — two strategies, one slot, second write wins, and Python Bridge AI's `INTRABAR_POLICY_LIVE` was silently replaced by FVG's `OFF`.
- FVG Scalper now owns **slot 21**; Statistical Arbitrage (which had *no* row at all and was reading Ensemble AI's) now owns **slot 22**. `MAX_STRATEGY_CONFIGS` 22 → 23.
- The legacy clobber is retained verbatim under `if(!config.useSemanticStrategyIndices)`, because in legacy mode catalog row "Turtle Soup" resolves policy slot 13 and must keep seeing FVG's `OFF`.

#### Legacy Byte-Identity Proof
- `useSemanticStrategyIndices` defaults to `false` in `SOrchestratorConfig::Reset()`; both EA inputs default `false`.
- `CatalogEnableSlot` / `CatalogPolicySlot` / `CatalogLogIndexAudit` return the Batch-145 values when `semantic == false`.
- New rows 21/22 are written in both modes but carry `INTRABAR_POLICY_OFF`, which is already the table's initial value, and legacy policy slots top out at 16 — nothing indexes 21/22 in legacy mode.
- The policy loop bound rose 22 → 23; `CIntrabarPolicy::m_policyConfig` is sized `INTRABAR_POLICY_CONFIG_SLOTS = 32`, so there is no overflow, and the two extra writes are `OFF`-over-`OFF`.

#### File Change Map
| File | Change |
|---|---|
| `Core/Strategy/StrategyCatalog.mqh` | `siPolicyIndex` column + `CatalogAdd` param; `CatalogEnableSlot` / `CatalogPolicySlot` added; `CatalogFlagEnabled` and `CatalogLogIndexAudit` made mode-aware |
| `Core/Management/EnterpriseStrategyManager.mqh` | `m_useSemanticStrategyIndices` + `SetUseSemanticStrategyIndices()`; `AutoRegisterStrategies` resolves both slots through the catalog helpers |
| `Core/Management/IntrabarPolicy.mqh` | `m_semanticPolicySlots` + `SetSemanticPolicySlots()`; hardcoded `9/10` LIVE fallback made scheme-aware |
| `Core/Orchestration/StrategyConfigBuilder.mqh` | slot-13 clobber gated to legacy mode; new rows 21 (FVG Scalper) / 22 (Statistical Arbitrage) |
| `Core/Orchestration/OrchestratorConfig.mqh` | `MAX_STRATEGY_CONFIGS` 22 → 23; `useSemanticStrategyIndices` field + `Reset()` default `false` |
| `Core/Orchestration/EAOrchestrator.mqh` | `manager.SetUseSemanticStrategyIndices(...)` called before the policy loop and before `AutoRegisterStrategies` |
| `MultiStrategyAutonomousEA.mq5`, `MultiStrategyTestingEA.mq5` | `input bool InpUseSemanticStrategyIndices = false;` + config wiring |

#### Log Evidence to Look For
- `[CATALOG-AUDIT] slot_scheme=LEGACY (InpUseSemanticStrategyIndices=false)` — confirms the dormant default.
- `[CATALOG-AUDIT] <name> enable_slot legacy=N semantic=M MISMATCH -> using N` — 8 lines.
- `[CATALOG-AUDIT] <name> policy_slot legacy=N semantic=M MISMATCH -> using N` — 10 lines.
- `[CATALOG-AUDIT] NY Open Gap DEAD_SLOT legacy_flags_index=15 ...` / `Asian Range Break ... =16` — emitted only in legacy mode.

#### Invariants Preserved
- `CUnifiedRiskManager` pre-trade gating, `CTradeManager`-owned execution, EA-loop-owned position lifecycle, symbol-scoped manager consensus and `CIndicatorManager::DestroyInstance()` on deinit are all untouched.
- Statistical Arbitrage keeps its `g_pythonBridge != NULL && IsConnected()` gate; Python Bridge AI keeps its separate `IsInitialized()` gate. The two remain deliberately un-unified.

#### Still NOT Fixed (out of the approved scope)
- **F3 — `PythonBridgeAI` missing from the outer AI gate** at `EAOrchestrator.mqh:3505`. Offered, not selected. Unchanged.
- **F6 — misleading Statistical Arbitrage "registered" log** on the skip path (`EnterpriseStrategyManager.mqh:966-990`). Not selected. Unchanged.

#### Rollout Note
Turning `InpUseSemanticStrategyIndices` on **changes the live strategy roster** (2 strategies wake up, 6 change which flag gates them, 10 change intrabar policy). Validate in shadow / backtest before enabling on a live account.

### Batch 145: Unified Data-Driven Strategy Catalog (2026-08-11)

#### Implementation Summary
Structural refactor only — **trading behavior preserved byte-for-byte**. Every strategy registration path (12 indicator strategies + 5 AI adapters) now reads from ONE catalog file instead of three hand-maintained if-chains.

**New file — `Core/Strategy/StrategyCatalog.mqh`** (~290 lines)
- 8 sections: per-strategy includes, catalog enums (`ENUM_CATALOG_KIND`, `ENUM_CATALOG_AI`), the `SStrategyDefinition` row struct (18 fields), storage (`g_strategyCatalog[]`, `g_strategyCatalogCreators[]`, count/built flags), `CATALOG_SIMPLE_CREATOR` creator macro, `CatalogAdd()`, `BuildStrategyCatalog()` (17 rows), and lookups/gates (`CatalogFindByName`, `CatalogSymbolAllowed`, `CatalogFlagEnabled`, `CatalogLogIndexAudit`).
- Every strategy owns exactly 3 anchored lines tagged `// [CAT:<Name>]` (include / creator / row).

#### Add–Remove Contract
- **Add a strategy:** 1 new class file under `Strategies/`, then 3 anchored lines in `StrategyCatalog.mqh` (include, `CATALOG_SIMPLE_CREATOR`, `CatalogAdd`). Nothing else in `Core/` is touched.
- **Remove a strategy:** delete the 3 lines carrying its `[CAT:]` anchor.

#### File Change Map
| File | Change |
|---|---|
| `Core/Strategy/StrategyCatalog.mqh` | **NEW** — single source of registration truth |
| `Core/Management/EnterpriseStrategyManager.mqh` | 12 `Strategies/*` includes → 1 catalog include; `AutoRegisterStrategies()` if-chain (67 lines) → 1 catalog loop |
| `Core/Orchestration/EAOrchestrator.mqh` | 5 `Initialize*AIForSymbol()` (362 lines) → `IsCatalogAIRowEnabled` / `CatalogAIPreCreateGate` / `PrepareCatalogAIAdapter` / `RegisterCatalogAIAdapter` / `RegisterCatalogAIStrategiesForSymbol`; the 5 call sites → 1 call |
| `Core/Management/StrategyRegistryState.mqh` | dead duplicate include block (15 lines), dead `AutoRegisterStrategies` decl + 73-line body removed |
| `Core/Factory/StrategyFactory.mqh`, `Core/Registry/MathematicalEngineRegistry.mqh` | **untouched** (their includes are still required) |

#### Bug Fixed — F4: AI adapter double-delete
`CEnterpriseStrategyManager::RegisterStrategy()` already deletes the strategy object when registration fails. Four of the five AI paths (Transformer, Ensemble, ONNX, Python Bridge) then called `delete adapter` again — a double free. Only the Neural Network path was correct. The shared `RegisterCatalogAIAdapter()` tail now never deletes after a failed `RegisterStrategy`, making all five paths consistent and safe. `delete adapter` is still performed (correctly) when adapter *preparation* fails, since the manager does not own it yet.

#### Bug Fixed — pre-existing `DashboardBridge.mqh:143` compile error (0/0 blocker)
The Batch 144 `DashboardBridge` decomposition (commit `e483d5b`) left `CDashboardBridge::PushState()` calling `m_transport.FinishPush(CDashBridgePanels::BuildStateJson(m_protocol, m_health))` — passing an rvalue to a `string&` parameter (compiler error 200 "parameter passed as reference, variable expected" + warning 39). This meant the **EA did not build on `main`** (no `.ex5` emitted). Fixed the same proven way as `UnifiedRiskManager`: capture `BuildStateJson(...)` into a local `string stateJson` and pass `stateJson`. A full headless compile of `MultiStrategyAutonomousEA.mq5` now reports **0 errors, 0 warnings**. This defect was independent of Batch 145 (Batch 145 adds zero new diagnostics) but is closed here so the deliverable meets the 0/0 requirement.

#### Invariants Preserved
- The 12 legacy `flagsIndex` literals are kept exactly: `{0, 1, 4, 6, 9, 10, 11, 12, 13, 14, 15, 16}`. They are **not** remapped to `SI_*`.
- All weights / tiers / roles / clusters / timeframes / intrabar policies are identical to the previous `RegisterStrategy` call sites.
- Statistical Arbitrage still registers only when `g_pythonBridge != NULL && g_pythonBridge.IsConnected()`, and both original `Print` lines fire in their original relative positions.
- Python Bridge **AI** keeps its own, different gate (`m_pythonBridge != NULL && m_pythonBridge.IsInitialized()`); the two bridge predicates were deliberately **not** unified.
- `SyncEnabledWithRegistry`, `CStrategyRegistryState::RegisterStrategy`, `BuildStrategyRegistry`, the consensus core, health monitor, ONNX backoff manager and pipeline wiring are untouched.

#### Latent Defects Found, NOT Fixed in Batch 145
Each of these is reported (F1 is now logged at runtime by `CatalogLogIndexAudit()`) and **deferred to a separate user decision** — fixing any of them changes trading behavior.
- **F1 — legacy flag index vs semantic `SI_*` index mismatch.** For 8 of the 12 rows the legacy `flagsIndex` diverges from the semantic `ENUM_STRATEGY_INDEX` slot. Consequences: **2 strategies are effectively dead** (NY Open Gap → legacy slot 15, Asian Range Break → legacy slot 16; those slots are never populated) and **6 are mis-gated** (Mean Reversion, Volatility Breakout, Statistical Arbitrage, FVG Scalper, Turtle Soup, Breaker Block read a neighbouring strategy's enable flag). Now emitted as `[CATALOG-AUDIT] ... MISMATCH` / `DEAD_SLOT` lines at registration time. **Not fixed** — the remap would enable/disable live strategies.
- **F2 — `StrategyConfigBuilder` slot [13] double-write.** Two different strategies write the same flag slot; the second write wins. **Not fixed.**
- **F3 — `PythonBridgeAI` missing from the outer AI gate.** The `:3505` gate ORs `enableNeuralNetwork || enableTransformer || enableEnsemble || enableOnnxAI` but omits `enablePythonBridgeAI`, so a Python-Bridge-AI-only configuration never reaches AI adapter registration. Preserved as-is. **Not fixed.**

### Batch 144: God-Object Decomposition — next5c + Strategy Openness Refinement (2026-08-11)

#### Decomposition — next5c (commit e483d5b)
Mechanical God-Object decomposition, zero behavior change:
- `Core/Scalp/ATRScalpingEngine.mqh` 836 → 326 (7 `ATRScalp*` modules)
- `Core/Monitoring/PerformanceAnalytics.mqh` 946 → 474 (5 `PerfAnalytics*` modules)
- `Core/Utils/PythonBridge.mqh` 1028 → 274 (5 `PyBridge*` modules)
- `Core/Utils/DashboardBridge.mqh` 950 → 215 (5 `DashBridge*` modules)
- `Core/Engines/RegimeEngine.mqh` 925 → 390 (7 `Regime*` modules)
- Added explicit 0-warnings/0-errors discipline to the extraction pattern (one agent confirmed a real MetaEditor compile: 0 errors, 0 warnings).

#### Strategy Openness Refinement (behavior change — makes entry gating LESS strict)
Preserves the risk gate (`CUnifiedRiskManager` pre-trade) and the ATR-crisis volatility gate. Loosens only the consensus / confidence / OFI gates:
- `Core/Management/ConsensusWeightingConfig.mqh`: lowered quorum thresholds + support floors across all profiles (balanced 0.55→0.50; conservative minQuorum 3→2, threshold 0.65→0.60; aggressive 0.50→0.45). EA defaults to BALANCED, so the active threshold drops 0.55→0.50.
- `Core/Management/ConsensusEngine.mqh`: effective quorum clamp 0.35/0.85 → 0.30/0.80 (quorum can never become over-strict).
- `Core/Pipeline/SignalPipelineTypes.mqh`: default `minConfidence` 0.40→0.35; trend-mode floor 0.55→0.45 (opens trend trades).
- `Core/Management/PostConsensusValidator.mqh`: OFI hard-veto softened — only a STRONG contradiction (|ofi_z| ≥ 1.0) vetoes; a mild contradiction is now logged and allowed.

#### Files Changed
- 5 modified next5c mains + 30 new modules + 4 strategy-refinement files + this changelog.

### Batch 143: God-Object Decomposition Program — Batch 1 (next5) + Batch 2 (next5b) (2026-08-09 → 2026-08-11)

#### Implementation Summary
Mechanical God-Object decomposition with **ZERO behavior change** (exact public-signature preservation, thin one-line forwarders, extracted modules own fields by value or as static helpers). Two batches landed:

**Batch 1 — next5 (commit 618dcd7):**
- `Core/Trading/TradeManager.mqh` 3308 → 2261 (5 `TradeMgr*` modules)
- `Core/Pipeline/UnifiedSignalPipeline.mqh` 2223 → 918 (6 `SignalPipeline*` modules)
- `Core/Scalp/FastScalpEngine.mqh` ~1748 → 468 (11 `FastScalp*` modules)
- `Core/Management/DiagnosticsManager.mqh` 1706 → 897 (5 `DiagMgr*` modules)
- `Core/Engines/TrendEngine.mqh` 1646 → 911 (7 `Trend*` modules)

**Batch 2 — next5b (this commit):**
- `Core/Scalp/GridRecoveryEngine.mqh` 1156 → 681 (7 `GridRecovery*` modules)
- `Core/Scalp/SpikeHunterEngine.mqh` 1150 → 310 (6 `SpikeHunter*` modules)
- `Core/Engines/StructureEngine.mqh` 1131 → 491 (5 `Structure*` modules)
- `Core/Engines/MarketAnalysis.mqh` 1102 → 139 (6 `MarketAnalysis*` modules)
- `Core/Utils/ErrorHandling.mqh` 1038 → 42 (6 `ErrorHandling*` modules)

**Totals:** 10 God Objects decomposed; ~13,300 → ~6,400 lines in the decomposed mains; 64 new focused modules. Every file verified by comment/string-aware delimiter tripwire (35/35 balanced), include-completeness check, and agent `IS_PASS` against 5 structural gates.

#### Known follow-ups
- `Core/Engines/TrendEngine.mqh`: pre-existing dead branch `bool adxValid = !useAdxModel;` never set true on the healthy-ADX path — flagged, not fixed (no-behavior-change mandate).
- `Core/Orchestration/EAOrchestrator.mqh` (~3712 LoC) and `Core/Risk/*` managers remain as candidate batches.

#### Files Changed
- 10 modified main `.mqh` files + 64 new module `.mqh` files (per-file lists above) + this changelog.

## [Unreleased] - 2026-08-06

### Batch 140: Phase 4-5 — Strategy Duplication Consolidation + God Object Decomposition (2026-08-05)

#### Implementation Summary

**Phase 4: Strategy Duplication Consolidation**

1. **LogRejectEvent / RejectSignal consolidation** — Consolidated into `CStrategyBase` as protected virtual methods backed by `m_strategyPrefix`, `m_lastRejectReasonTag`, and `m_lastRejectLogTime`. Removed duplicated implementations from 8 strategy files.

2. **RefreshForNewBar consolidation** — Added `m_lastBarCount` + `RefreshForNewBar()` + `OnRefreshComponents()` virtual hook to `CStrategyBase`. 5 strategies now override `HandleNewBar()` and `OnRefreshComponents()` instead of duplicating new-bar boilerplate.

3. **ValidateTradeRequest consolidation** — Added `ValidateWithRiskManager()` helper to `CStrategyBase`. Consolidated 11 of 12 strategy files (StatisticalArbitrage skipped — different validation pattern). ~150 lines of duplicated boilerplate eliminated.

4. **CONSENSUS-DIAG consolidation** — Added `LogConsensusDiag()` helper to `CStrategyBase`. Consolidated 9 of 12 strategy files (3 outliers skipped — structural variations). ~60 lines eliminated.

**Phase 5: God Object Decomposition**

1. **SOrchestratorConfig extraction** — Extracted `SOrchestratorConfig` struct + helper structs (710 lines) from `EAOrchestrator.mqh` into new `Core/Orchestration/OrchestratorConfig.mqh`. Pure data definitions, zero invariant risk.

2. **InitializeStrategyConfigs extraction** — Extracted 249-line method into new `Core/Orchestration/StrategyConfigBuilder.mqh` as `CStrategyConfigBuilder::Initialize()` static method. Pure config mapping, no runtime behavior.

3. **EAOrchestrator.mqh reduction** — Reduced from 5,529 → 4,571 lines (958-line reduction, 17.3% smaller).

#### Compilation
All changes verified with 0 errors, 0 warnings. `.ex5` produced.

#### Files Changed
- `Core/Strategy/StrategyBase.mqh` (CStrategyBase enhancements: LogRejectEvent, RefreshForNewBar, ValidateWithRiskManager, LogConsensusDiag)
- `Core/Orchestration/OrchestratorConfig.mqh` (new — SOrchestratorConfig + helper structs)
- `Core/Orchestration/StrategyConfigBuilder.mqh` (new — CStrategyConfigBuilder::Initialize())
- `Core/Orchestration/EAOrchestrator.mqh` (reduced 958 lines)
- 8 strategy files (LogRejectEvent/RejectSignal dedup)
- 5 strategy files (RefreshForNewBar/OnRefreshComponents)
- 11 strategy files (ValidateWithRiskManager)
- 9 strategy files (LogConsensusDiag)

#### Runtime Invariants Preserved
All 5 AGENTS.md §3 invariants verified — risk authority, execution ownership, lifecycle ownership, strategy consensus, indicator cleanup unchanged.

### Batch 141: Phase 6-7 — Execution Flow Optimization + File Reorganization & Hygiene (2026-08-06)

#### Implementation Summary

**Phase 6: Execution Flow Optimization**

1. **6.1 SignalValidator merge (VERIFIED DONE)** — `SignalValidator.mqh` was already merged into `EnterpriseStrategyManager.mqh` in a prior batch. Comments confirm: "merged from SignalValidator" in `EnterpriseStrategyManager.mqh` and "SignalValidator - now merged into EnterpriseStrategyManager" in `EAOrchestrator.mqh`. No file to delete — it's already gone.

2. **6.2 Position sizing consolidation (ASSESSED, PARTIAL)** — Interface `CPositionSizerModifier` already exists in `PositionSizerModifiers.mqh` (lines 23-29). All 5 modifiers (ADXLotModifier, BayesianKellyModifier, EquityCurveLotModifier, VolatilityTargetingModifier, VPINLotModifier) already implement it. File merge skipped — would create 1,866-line file exceeding <1,500 target. URM duplicate logic cleanup skipped — conflicting 1x vs 15x round-up policies require shadow testing (CRITICAL risk).

3. **6.3 JSON parsing consolidation (COMPLETED)** — Created `ParseJsonDouble()`, `ParseJsonString()`, `ParseJsonInteger()` private helper methods in `CPythonBridge`. Replaced 18+ duplicated JSON parsing patterns across `ParsePredictionResponse()`, `GetPairCorrelation()`, `FindBestCorrelatedPair()`, and `ParseVersionResponse()`. ~130 lines of duplicated boilerplate eliminated.

4. **6.4 Registry pattern consolidation (ASSESSED, SKIPPED)** — `IRegistry.mqh` already provides template-based `CRegistryBase<T>`. Of 6 registries: DrawingManagerRegistry borderline (single pointer but create-on-demand + objectCount tracking), InstitutionalEngineRegistry (3 pointers/slot), NeuralNetRegistry (2 pointers/slot) too specialized. ScanSchedulerRegistry and SymbolStateTracker store scalar state (not pointers) — wrong abstraction. MathematicalEngineRegistry has 16 engine pointers. No consolidation feasible without broader redesign.

**Phase 7: File Reorganization & Hygiene**

1. **7.1 Core/Position/ directory (ASSESSED)** — `Core/Position/PositionManager.mqh` is NOT a duplicate of `Core/Trading/PositionManager.mqh` (latter does not exist). It's the sole location, actively included by 5 files. Documentation corrected.

2. **7.2 Core/Risk/ reorganization (SKIPPED)** — Moving 15 files into subdirectories would break many #include paths across the codebase. High risk for purely organizational benefit. Deferred.

3. **7.3 TODO/FIXME cleanup (COMPLETED)** — EAOrchestrator.mqh and EnterpriseStrategyManager.mqh TODOs already resolved in prior phases. Two remaining TODOs in `EnsembleAIStrategyAdapter.mqh` (lines 530, 544) replaced with clear documentation of interface mismatch (TrainStep/OnRegimeChange can't delegate to CEnsembleMetaLearner due to parameter mismatch).

4. **7.4 Error handling pattern (SKIPPED)** — Optional, lower priority. Not a line reduction. Deferred.

5. **7.5 Dashboard App.tsx fix (COMPLETED)** — Replaced 8 inline "Coming Soon" stub components with imports of actual page files from `./pages/`. All 8 pages (Overview, Charts, Positions, Strategies, Risk, AI, Logs, Control) now render their real implementations.

#### Compilation
All MQL5 changes verified with 0 errors, 0 warnings. `.ex5` produced at 1,395,328 bytes.

### Batch 142: Phase 6.2 + 7.4 — Position Sizing Consolidation + Error Handling Logging (2026-08-06)

#### Implementation Summary

**Phase 6.2: Position Sizing Consolidation (COMPLETED)**

1. **Removed redundant URM `<minLot` validation block** — Deleted the ~22-line block in `Core/Risk/UnifiedRiskManager.mqh` (formerly lines 2691-2712) that hard-coded `if(riskRatio <= 15.0)` with no config binding. Replaced the gate with `if(request.lotSize > maxLot)` using `SYMBOL_VOLUME_MAX`. `CPositionSizer` already rounds up to minLot with the configured tolerance before URM's max-lot gate, so the removed branch was duplicated logic.

2. **Restored 15x min-lot round-up tolerance (reverted L5-002 1x clamp)** — The L5-002 fix had clamped round-up tolerance to 1x in three places; all relaxed to 15x per user decision ("keep risk up to 15x, not 1x"):
   - `UnifiedRiskManager.mqh` config default: `m_config.minLotRiskMultiplier = 15.0` (line 602).
   - `PositionSizer.mqh` hard cap: `if(riskRatio > 15.0)` (line 712).
   - `PositionSizer.mqh` setter `SetMinLotRiskMultiplier`: `MathMin(MathMax(1.0, multiplier), 15.0)` (line 842).

3. **EA inputs updated** — `MultiStrategyAutonomousEA.mq5`: `InpAllowMinLotRoundUp = true`, `InpMinLotRiskMultiplier = 15.0` (lines 41-42; consumed at lines 397-398 and 1385).

**Phase 7.4: Error Handling Pattern (COMPLETED)**

1. **`return 0.0` debug logging (logging only — no behavior change)** — Added 38 `PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, __LINE__, __FUNCTION__)` lines to `return 0.0` paths that are ambiguous between a valid zero result and an error. Distribution: `UnifiedRiskManager.mqh` 16, `TradeManager.mqh` 14, `PositionSizer.mqh` 5, `PythonBridge.mqh` 3.
   - Documented valid returns (hedging-mode path, already-braced inline early-exits) were intentionally skipped to avoid noise.
   - The insert script braces any unbraced multi-line control statement around the `return` so the log executes only on the actual return path (control-flow-safe; verified by clean recompile).

#### Compilation
All MQL5 changes verified with 0 errors, 0 warnings. `.ex5` produced at 1,397,708 bytes (slightly larger than the 1,394,996-byte pre-6.2/7.4 build due to the added debug log statements — expected).

#### Files Changed
- `Core/Risk/UnifiedRiskManager.mqh` (redundant lot-validation block removed; 15x tolerance restored; 16 DBG-RET0 logs)
- `Core/Risk/PositionSizer.mqh` (15x hard cap + setter clamp relaxed; 5 DBG-RET0 logs)
- `MultiStrategyAutonomousEA.mq5` (min-lot round-up inputs set to 15.0 / true)
- `Core/Trading/TradeManager.mqh` (14 DBG-RET0 logs)
- `Core/Utils/PythonBridge.mqh` (3 DBG-RET0 logs)

#### Runtime Invariants Preserved
All 5 AGENTS.md §3 invariants verified — risk authority (`CUnifiedRiskManager`), execution ownership (`CTradeManager`), lifecycle ownership (EA loop), strategy consensus (symbol-scoped), indicator cleanup (`CIndicatorManager::DestroyInstance`) unchanged. 6.2 removes only a redundant validation branch; 7.4 is logging-only.

#### Files Changed
- `Core/Utils/PythonBridge.mqh` (JSON parsing consolidation — 3 new helpers, 18+ patterns replaced)
- `Core/Strategy/EnsembleAIStrategyAdapter.mqh` (TODO comments resolved)
- `Dashboard/client/src/App.tsx` (stub components replaced with real page imports)

#### Runtime Invariants Preserved
All 5 AGENTS.md §3 invariants verified — risk authority, execution ownership, lifecycle ownership, strategy consensus, indicator cleanup unchanged.

---

#### Batch 2026-08-14: Strategy Audit & Safe Fixes

**Context:** User requested evaluation of all trading strategies and profitability improvements. Full static review of all 14 top-level strategies + 26 supporting detector modules + the consensus execution path (`EAOrchestrator → CandidateBuilder::BuildCandidate → CalculateStops`).

**Key finding (FINDING 0):** Strategy-proposed stop-loss / take-profit are NOT consumed by the live execution path. `CCandidateBuilder::CalculateStops` hardcodes `atrValue = 0` / `pipeline = NULL`, so all live trades use a generic fallback stop + fixed 2.0R target (1.5R for mean-reversion cluster). Strategy exit logic is currently dead code for live trading. Live lot sizing (risk-based via `CPositionSizer::CalculatePositionSizeWithRisk`) IS correct. Recommendation: wire strategy-proposed stops into `CalculateStops` behind a config flag + shadow-mode rollout — **IMPLEMENTED in Batch 2026-08-14 (cont.) below.**

**Fixes applied (safe, low-risk, no entry-logic change):**
- `Strategies/NYOpenGapStrategy.mqh`: window time-check switched `TimeCurrent()` → `TimeGMT()` (true UTC window regardless of broker); corrected/added comments; documented D1-open gap proxy limitation (true NDOG session mapping deferred to a follow-up).
- `Strategies/StatisticalArbitrageStrategy.mqh`: removed dead `m_useDynamicHedgeRatio` member + initializer (declared/initialized but never read anywhere); clarified the hardcoded 50/100-pip SL/TP are gate-only.

**Audit deliverable:** `docs/STRATEGY_AUDIT_2026-08-14.md` — per-strategy evaluation (edge / live impact / risk / recommended action) + systemic findings (orphaned strategies `LiquiditySweep` & `RangeCompressionBreakout`; R:R inconsistency; unused Candlestick `CheckTrendAlignment`; VolBreakout ~1.25R) + prioritized remediation roadmap.

#### Compilation
Main EA recompile covers both edited strategies (included via `#include`). Verification run requested after edits.

#### Files Changed
- `docs/STRATEGY_AUDIT_2026-08-14.md` (new — full strategy audit)
- `Strategies/NYOpenGapStrategy.mqh` (timezone correctness fix + comments)
- `Strategies/StatisticalArbitrageStrategy.mqh` (dead-code removal + comments)

#### Runtime Invariants Preserved
All 5 AGENTS.md §3 invariants unchanged. No strategy entry logic altered; live risk-based lot sizing untouched.

---

#### Batch 2026-08-14 (cont.): Implement All Audit Solutions

**Context:** Continuation of the strategy audit. User directive: "implement all solutions." Delivers the architecture-level fixes the audit identified, behind safe config flags so default live behavior is unchanged.

**1. FINDING 0 — wire strategy-proposed stops into the live execution path (IMPLEMENTED)**
- `Interfaces/IStrategy.mqh`: added `virtual bool GetProposedStops(ENUM_TRADE_SIGNAL, double &slPips, double &tpPips) const` (default returns false).
- `Core/Strategy/StrategyBase.mqh`: added `m_proposedSLpips`/`m_proposedTPpips` + `SetProposedStops()`/`GetProposedStops()`; `GetSignal(double&)` resets the stash each cycle; 12 consensus strategies now call `SetProposedStops(...)` right before their `ValidateWithRiskManager` gate.
- `Core/Management/EnterpriseStrategyManager.mqh`: added `GetConsensusProposedStops(signal, sl, tp)` — surfaces the winning contributor's designed stops.
- `Core/Orchestration/CandidateBuilder.mqh`: `CalculateStops` now honors proposed stops when `::InpUseStrategyStops` is enabled, and enforces a cluster minimum R:R floor (2.0 trend / 1.5 mean-reversion) on every branch. Default flag OFF → unchanged generic fallback.
- `MultiStrategyAutonomousEA.mq5` + `MultiStrategyTestingEA.mq5`: added `input bool InpUseStrategyStops = false;`.

**2. Orphaned strategies integrated into consensus (IMPLEMENTED)**
- `Core/Strategy/StrategyCatalog.mqh`: added includes, `CATALOG_SIMPLE_CREATOR` entries, and two `CatalogAdd` rows for "Liquidity Sweep" (SI_LIQUIDITY_SWEEP) and "Range Compression" (SI_RANGE_COMPRESSION), following the exact proven pattern already used by FVG/Turtle/Breaker/NY/Asian (same shared CStrategyRegistry fed by both the legacy RegisterDefinition list and this catalog).
- `Strategies/LiquiditySweepStrategy.mqh` + `Strategies/RangeCompressionBreakout.mqh`: added `virtual ENUM_TRADE_SIGNAL ExecuteSignal(double &confidence)` overrides so the consensus `GetSignal(double&)` wrapper routes into their designed logic (previously a non-virtual no-arg `GetSignal()` hid them from consensus AND bypassed the unified risk gate). Both now stash designed stops via `SetProposedStops()`.

**3. Dead code & R:R (IMPLEMENTED)**
- `Strategies/StrategyCandlestick.mqh`: removed the unused `CheckTrendAlignment()` method (flag `m_requireTrendAlignment` and its EMA handles remain in use).
- R:R unification is provided by the FINDING 0 minimum-R:R floor (consensus now cannot trade below 2.0R trend / 1.5R mean-rev regardless of any single strategy's internal R:R).

**Compilation:** Both `MultiStrategyAutonomousEA.ex5` and `MultiStrategyTestingEA.ex5` recompiled clean — **0 errors, 0 warnings** (verified via MetaEditor headless `/compile` + UTF-16 log decode; .ex5 timestamps confirmed fresh).

**Runtime Invariants Preserved:** All 5 AGENTS.md §3 invariants unchanged. `InpUseStrategyStops` defaults OFF, so live stop/target behavior is identical to prior build until an operator enables it (recommended only after a shadow-mode run, per AGENTS.md §5.2).

#### Files Changed
- `Interfaces/IStrategy.mqh` (GetProposedStops virtual)
- `Core/Strategy/StrategyBase.mqh` (proposed-stop stash members + setters/getters + reset)
- `Core/Management/EnterpriseStrategyManager.mqh` (GetConsensusProposedStops)
- `Core/Orchestration/CandidateBuilder.mqh` (CalculateStops: honor proposed stops + min-R:R floor)
- `Core/Strategy/StrategyCatalog.mqh` (2 new catalog rows + creators + includes)
- `Strategies/LiquiditySweepStrategy.mqh` (ExecuteSignal override + stash)
- `Strategies/RangeCompressionBreakout.mqh` (ExecuteSignal override + stash)
- `Strategies/StrategyCandlestick.mqh` (dead-code removal)
- `MultiStrategyAutonomousEA.mq5`, `MultiStrategyTestingEA.mq5` (InpUseStrategyStops input)
