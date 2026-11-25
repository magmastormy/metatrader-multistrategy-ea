# Remaining Work

Status key: **Open** = not started or only partly addressed. **Verify** = code was changed but broker/runtime evidence is incomplete. The findings below are a historical audit register, not a verified snapshot of the current tree. The clean eight-target compile cited in Batch 298 is historical; this dirty working tree has not been compiled, and no current-tree paired cold-window backtest is available.

Measured results for completed batches live in [RUNS_AND_GAINS.md](RUNS_AND_GAINS.md). Dated change history lives in [changelogs.md](changelogs.md). Current architectural truth lives in [SYSTEM_STRUCTURE.md](SYSTEM_STRUCTURE.md).

---

## Data and Model Validity

### 1. Notebook split label leakage — SOURCE FIXED; REGRESSION TESTS PASSED (2026-11-20)
- **Resolution:** The notebook carries actual barrier-resolution indices into sequence preparation and purges train/validation/test samples whose label interval crosses a split boundary.
- **Verification:** `test_notebook_data_alignment.test_ratio_split_purges_actual_label_end_across_boundaries` passes. The notebook functions are tested on synthetic fixtures; no real-data training run is claimed.

### 2. CPCV approximate-horizon purge — SOURCE FIXED; REGRESSION TESTS PASSED (2026-11-20)
- **Resolution:** The pipeline and validator pass actual label-end timestamps into CPCV; overlap purging uses each event's real start/end interval, not median bar spacing.
- **Verification:** `test_validate_model_cpcv` and `test_data_pipeline_integrity` pass irregular-interval, timestamp-order, and label-end checks. No historical performance claim is implied.

### 3. Standalone CPCV in mql5_v2.py — SOURCE REVIEWED; REGRESSION TESTS PASSED (2026-11-20)
- **Resolution:** The standalone helper groups equal timestamps together and purges training samples by actual interval overlap with test events.
- **Verification:** `test_mql5_v2_data_alignment.test_cpcv_groups_equal_timestamps_and_purges_overlap` passes. The duplicate implementation remains separate to keep the Colab script self-contained.

### 4. Triple-barrier edge cases and index alignment — SOURCE FIXED; REGRESSION TESTS PASSED (2026-11-20)
- **Resolution:** Incomplete end-of-series horizons are excluded, actual barrier-hit ends are retained, stop-first ties are deterministic, and sequence features/labels/returns/timestamps are aligned by event index.
- **Verification:** `test_data_pipeline_integrity`, `test_notebook_data_alignment`, and `test_mql5_v2_data_alignment` pass their synthetic edge cases. Real-market data execution remains unverified.

### 5. ONNX feature and scaler parity — PARTIALLY RESOLVED; FEATURE PARITY OPEN (2026-11-20)
- **Resolution:** Standard and robust-scaler trainers now emit the same feature-count-prefixed binary format as the MQL loader. The runtime rejects missing, malformed, non-finite, or wrong-width scaler data instead of applying a partial scaler or passing raw features. Duplicate scaler loading and an unused hot-reload path were removed; model and scaler artifacts must be deployed together and reinitialized.
- **Remaining:** Exact feature semantics are not aligned or terminal-verified. Python's base pipeline defines 57 features while the MQL ONNX builder expects 70; the current cross-check compares only shared columns. Do not treat this as production parity until all positions are mapped and a terminal-exported vector matches Python on representative bars.
- **Verification:** `test_scaler_binary_contract` validates both Python serialization paths and source-level fail-closed checks. MetaEditor and terminal inference checks remain unavailable.

### 6. Walk-forward and holdout realism — PARTIALLY RESOLVED (2026-11-20)
- **Fixed:** Standard and standalone neural trainers select and gate on validation plus development-only CPCV; CPCV folds use raw training rows only. The selected checkpoint's holdout score is report-only. The standalone LightGBM baseline now reports validation IC, not test IC.
- **Fixed:** Multi_Mt5_Colab_Notebook candidates and LightGBM use validation only, and its CPCV inputs are raw training rows only. The generated Colab tree reports use validation; stacker cells no longer read test rows or publish test metrics.
- **Fixed:** The Kaggle notebook no longer evaluates or stores test classification metrics during selection/export. Its gate remains fail-closed because fold-local CPCV retraining is unavailable; Sharpe annualization uses train+validation timestamps. The final zero-cost forward-return test proxy is report-only after artifact export and is not executable-performance evidence.
- **Removed:** `Python/train_all_models.ipynb` was a clean, unreferenced, out-of-sync duplicate whose helper signatures and CPCV call no longer matched the current code. `Python/write_colab.py` is the source for `Python/train_all_models_colab.ipynb`.
- **Regression coverage:** `test_train_model_selection` and `test_cpcv_raw_scaling_flow` cover validation-only gates, candidate holdout isolation, train-only CPCV, and the Kaggle notebook boundary.
- **Still open:** No real-data walk-forward run or broker/terminal-backed performance evidence has been produced. A report-only holdout can still be manually misused to tune later runs; source checks cannot establish whether that happened.
- **Files:** `Python/train_model.py`, `Python/mql5_v2.py`, `Python/write_colab.py`, `Python/Multi_Mt5_Colab_Notebook.ipynb`, `Python/train_all_models_colab.ipynb`, `Python/EA_Model_Training_Kaggle.ipynb`, `Python/validate_model.py`

---

## AI and Consensus

### 7. H11 in-terminal label scan chronology — OPEN
- **What:** Expired-label resolution scans forward from entry. Bar shift order and the hard 500-bar cap are unverified. A label that hits neither barrier within the cap may be resolved incorrectly.
- **Where:** Expired-label resolution in `CNeuralTrainingDataManager.mqh`.
- **Files:** `AIModules/CNeuralTrainingDataManager.mqh`
- **Fix idea:** Convert shifts to absolute bar times and iterate from the entry shift down to 1 (oldest to newest). Replace the hard cap with `vertical_bars`. Mark labels that cannot be resolved as unresolved instead of guessing.

### 8. H12: consensus weight baseline needs decay and safer keys — OPEN
- **What:** `LoadAIBaseWeight()` persists a baseline, but there is no time-based decay. Keys are truncated to 63 characters, so long symbol and strategy names can collide. A changed strategy count or order is not handled.
- **Where:** `LoadAIBaseWeight()` in `ConsensusWeightingConfig.mqh`, and the weight target update.
- **Files:** `Core/Management/ConsensusWeightingConfig.mqh`, `Core/Management/StrategyPerformanceHealth.mqh`
- **Fix idea:** Build the key from a short hash (for example CRC32 of symbol + strategy name) plus a readable prefix. Store the strategy name inside the global, or store a version key, so a mismatch resets the baseline. Add decay: `target = base + (evidence - base) * exp(-dt / tau)` with `dt` since last update. Keep the minimum-sample gate.

---

## Execution and Broker

### 9. Standard async partial fills and no-history path — SOURCE FIXED; TERMINAL VERIFICATION OPEN (2026-11-20)
- **What:** Timeout reconciliation now retains unresolved orders in quarantine, rechecks broker history, and records lifecycle changes in the append-only async journal. Cancellation and fill reconciliation require matching order ticket, symbol, and magic. Shutdown no longer truncates the journal.
- **Where:** `Core/Trading/TradeMgrAsyncExecutor.mqh` and its `CTradeManager` forwarding path.
- **Evidence boundary:** Source paths were corrected; MetaEditor compilation and broker-backed partial-fill, late-fill, cancellation, and restart tests remain outstanding.

### 10. Fast-scalp risk reservation recovery — SOURCE FIXED; TERMINAL VERIFICATION OPEN (2026-11-20)
- **What:** Async admission now requires a positive reserved-risk percentage and writes a `PREPARED` event before `OrderSendAsync`. The journal persists exact risk, ticket, fills, magic, and lifecycle state; replay consolidates by request ID, scopes to the EA magic range, and never resends. `FastScalpEngine` restores matching requests before risk-budget rebuild; missing tickets or incomplete replay saturate the budget closed. Legacy rows estimate risk from entry/stop data or fail closed.
- **Where:** `Core/Trading/TradeMgrAsyncExecutor.mqh`, `Core/Trading/TradeManager.mqh`, `Core/Trading/TradeTypes.mqh`, `Core/Scalp/FastScalpAsyncTracker.mqh`, and `Core/Scalp/FastScalpEngine.mqh`.
- **Evidence boundary:** Source correction is in place. MetaEditor compilation and terminal restart/late-fill verification are still required before operational closure.

### 11. Spike Hunter may bypass the shared risk path — SOURCE FIXED; TERMINAL VERIFICATION OPEN (2026-11-20)
- **Resolution:** SpikeHunterExecutor refuses entry unless the initialized UnifiedRiskManager and TradeManager are present. Its only send path validates through unified risk and executes through TradeManager; no raw CTrade send remains. The orchestrator does not currently dispatch Spike Hunter, so it is dormant as well as fail-closed.
- **Verification boundary:** MetaEditor compilation and broker-backed execution remain outstanding.

### 12. ATR scalp partial close latch is not tied to broker outcome — SOURCE FIXED; TERMINAL VERIFICATION OPEN (2026-11-20)
- **Resolution:** The latch is written before sending to prevent duplicate requests, retained only after the broker-visible position volume decreases, and removed when no reduction is observed. The code checks fill retcodes and logs a retcode/volume mismatch instead of treating request acceptance as proof of fill.
- **Verification boundary:** The live broker partial-fill and restart cases remain untested.

### 13. Margin projection on hedging and netting accounts — SOURCE FIXED; TERMINAL VERIFICATION OPEN (2026-11-20)
- **Resolution:** Manual current-margin addition and account-mode-specific volume approximations are removed. The risk pipeline submits the candidate market request to OrderCheck and gates on broker-projected post-trade free margin and margin level, including netting offsets. It rejects missing or invalid quotes, unsupported fill policies, malformed requests, and failed checks.
- **Verification boundary:** MetaEditor compilation plus hedging/netting terminal checks remain outstanding.

### 14. Python bridge blocks the terminal event loop — OPEN
- **What:** Cache freshness, failure backoff, and timer-only prediction calls reduce request frequency, but `WebRequest` is still synchronous inside `OnTimer()` and can block the EA event loop for its configured timeout. A same-EA asynchronous socket rewrite has not been proven nonblocking for DNS, TLS, send, and receive.
- **Where:** `Core/Utils/PyBridgeTransport.mqh` and `Core/Strategy/PythonBridgeAIStrategyAdapter.mqh`.
- **Fix direction:** Move network I/O behind a separate worker EA/process with explicit IPC, health, request IDs, and stale-response handling; this needs a deployment design and terminal-backed tests. Do not call this resolved until the EA event loop stays responsive under delayed/unavailable bridge tests.

---

## Risk and Exposure

### 15. Exposure caps cover every reachable entry path — RESOLVED (2026-11-19)
- **Resolution:** `ValidateExposure()` runs inside the unified risk pipeline. Per-symbol and total count caps now include open EA-owned positions plus other in-flight risk reservations, excluding the candidate's own provisional reservation; total-risk checks already use the same exclusion.
- **Entry-path audit:** Main candidates and the fast-scalp market route are the currently dispatched entry paths. ATR, grid, and spike modules contain unified-risk gates but have no orchestrator `ProcessTick` dispatch and are dormant. The raw fast-scalp pending sender had no repo call site and is removed. The async tracker's raw `OrderSend` only cancels an existing order.
- **Dormant lifecycle path:** Pyramiding defaults disabled and `ConfigurePyramiding()` has no repo caller. Its current zero-stop add is rejected by `CTradeManager`; do not enable it without a nonzero-stop unified-risk gate.
- **Files:** `Core/Risk/VirtualPosition.mqh`, `Core/Risk/RiskValidationPipeline.mqh`, `Core/Scalp/FastScalpEngine.mqh`, `Core/Scalp/FastScalpTypes.mqh`, `Core/Orchestration/EAOrchestrator.mqh`

### 16. Opposing strategy votes need arbitration and tests — PARTIALLY RESOLVED; REGRESSION TESTS OPEN (2026-11-20)
- **Source behavior:** Equal aggregate scores return no trade and log both sides' votes, weights, and scores. A configured conflict deadband rejects larger dissent but intentionally permits dissent below the effective threshold; it is not a strict no-conflict rule.
- **Remaining:** Add executable regression coverage for ties, below-deadband dissent, and vetoed conflicts, then verify in MetaEditor/terminal.
- **Where:** Vote aggregation in `EAOrchestrator.mqh` and the consensus code.
- **Files:** `Core/Orchestration/EAOrchestrator.mqh`, `Core/Management/ConsensusEngine.mqh`, `Core/Management/ConsensusWeightingConfig.mqh`

### 17. Local stop, RR, and spread guards per strategy — SOURCE AUDIT PASSED; TERMINAL VERIFICATION OPEN (2026-11-20)
- **Resolution:** The 23 current `CStrategyBase`-derived strategy files were source-scanned. All signal-producing strategies use `CSignalGuards`; Statistical Arbitrage is the sole exception and returns `TRADE_SIGNAL_NONE` after detecting a pair signal because its second leg is not executed. Support/resistance sub-strategies are gated by their parent strategy before emission.
- **Verification boundary:** This is source-reference evidence, not a compiled or broker-backed test.
- **Where:** Strategy signal functions under `Strategies/`; shared guard in `Core/Utils/SignalGuards.mqh`.

### 18. NY open gap DST and session boundaries — PARTIALLY RESOLVED; BROKER OFFSET VERIFICATION OPEN (2026-11-20)
- **Resolution:** US DST transition instants are represented in UTC (07:00 UTC on the second Sunday in March; 06:00 UTC on the first Sunday in November), and the helper evaluates each target GMT instant. Historical M30 bars require exact broker-time matches, so an offset mismatch abstains instead of selecting a nearby bar.
- **Remaining:** Broker standard offset is inferred from the current server/GMT offset. Brokers with independent DST schedules can cause a safe false abstention around offset-change periods; resolving that needs explicit broker offset policy or terminal history evidence.

### 19. Crisis limits and hardcoded thresholds — OPEN
- **What:** The ATR crisis ratio thresholds are already EA inputs (`InpAtrCrisisRatioThreshold*`), so they are done. Remaining fixed literals still need to be found and moved to inputs.
- **Where:** Search for numeric literals in risk and crisis code.
- **Files:** `Core/Config/OrchestratorConfig.mqh`, `Core/Risk/*.mqh`, `MultiStrategyAutonomousEA.mq5`, `MultiStrategyTestingEA.mq5`, and matching `.set` files
- **Fix idea:** Add inputs with the current values as defaults. Update the `.set` files. Note that removing the unused profit-floor key already changed `.set` mapping.

---

## Configuration

### 20. Live config parser — SOURCE FIXED; COMPILE/EDGE-CASE VERIFICATION OPEN (2026-11-20)
- **Resolution:** Parser prototypes precede their use; the whole document is tokenized and recursively grammar-checked, duplicate keys at any nesting depth and trailing data are rejected, and supported risk values receive type/range checks.
- **Verification boundary:** MetaEditor compile and executable malformed-document cases remain outstanding.
- **Where:** `Core/Config/LiveConfigReloader.mqh`; supported risk application remains in `Core/Orchestration/EAOrchestrator.mqh`.

---

## Verification and Housekeeping

### 21. MQL5 compile of all modified files — OPEN
- **What:** No MQL5 file has been compiled since the changes. Compile errors are likely in the new parser, async reconciliation, and NY gap code.
- **Where:** All `.mq5` and `.mqh` files changed in this work.
- **Files:** `Core/Trading/TradeMgrAsyncExecutor.mqh`, `Core/Trading/TradeMgrPreflight.mqh`, `Core/Trading/TradeManager.mqh`, `Core/Trading/TradeTypes.mqh`, `Core/Scalp/FastScalpAsyncTracker.mqh`, `Core/Scalp/ATRScalpExit.mqh`, `Core/Scalp/ATRScalpEntry.mqh`, `Core/Scalp/SpikeHunterExecutor.mqh`, `Core/Risk/PositionSizer.mqh`, `Core/Risk/RiskMarginHealth.mqh`, `Core/Risk/RiskValidationPipeline.mqh`, `Core/Risk/PortfolioRiskManager.mqh`, `Core/Risk/CorrelationEngine.mqh`, `Core/Management/ConsensusWeightingConfig.mqh`, `Core/Management/StrategyPerformanceHealth.mqh`, `Core/Config/LiveConfigReloader.mqh`, `Core/Config/OrchestratorConfig.mqh`, `Core/Orchestration/EAOrchestrator.mqh`, `Core/Strategy/PythonBridgeAIStrategyAdapter.mqh`, `Strategies/NYOpenGapStrategy.mqh`, `Strategies/MeanReversionStrategy.mqh`, `Strategies/RangeCompressionBreakout.mqh`, `Strategies/FVGScalperStrategy.mqh`, `Strategies/BreakerBlockStrategy.mqh`, `Strategies/UnifiedICTFiles/MarketStructureAnalyzer.mqh`, `Core/Engines/MarketAnalysisMetrics.mqh`, `AIModules/CNeuralTrainingDataManager.mqh`, `crash_recovery_helpers.mqh`, `MultiStrategyAutonomousEA.mq5`, `MultiStrategyTestingEA.mq5`
- **Fix idea:** Compile each EA in MetaEditor and fix errors. Treat the compile as the gate before any live deployment.

### 22. Crash recovery replacement — OPEN
- **What:** The replacement write no longer deletes the last good file first, but the runtime behavior of the move call is not verified.
- **Where:** `crash_recovery_helpers.mqh`.
- **Files:** `crash_recovery_helpers.mqh`
- **Fix idea:** Confirm `FileMove` return value and fall back to keeping the old file on failure.

### 23. Git state — OPEN
- **What:** Changes are meant to stay uncommitted. Recent status notices were inconsistent, so commit state has not been confirmed.
- **Where:** Repository root.
- **Files:** None
- **Fix idea:** Git commands are blocked by the environment's ACL, so confirm the state through the UI History tab. A push notice showed commit `9bfe6fe` on branch `ai_main_3ae626c74d1641fb8261`; this was not triggered by a push request in this session, so check whether those commits contain the intended changes.

---

## Additional Findings (Second Pass)

### 24. mql5_v2.py CPCV purge is sample-count based and misses gaps between test groups — SOURCE FIXED (2026-11-20)
- **Resolution:** `purge_embargo`/`cpcv_folds` are now timestamp span-overlap ports of the reviewed `validate_model` logic.
- **Status:** Fixed in batch 299b remaining-work.

### 25. Duplicate label logic in mql5_v2.py — OPEN
- **What:** `triple_barrier_labels` (line 206) is a second implementation next to `data_pipeline.triple_barrier_labels` (line 102). Any fix to one can silently miss the other.
- **Where:** `Python/mql5_v2.py` line 206; `Python/data_pipeline.py` line 102.
- **Fix idea:** Keep one implementation in `data_pipeline.py` and import it. Check that the two versions currently agree on tie-breaks and horizon before deleting the copy.

### 26. Stacker meta-features are left as zeros for the first block — SOURCE FIXED (2026-11-20)
- **Resolution:** `meta_X` is now filled for EVERY row from the already-computed base predictions; shape + no-all-zero-row assertions added.
- **Status:** Fixed in batch 299b remaining-work.

### 27. Stacker base-model predictions may be in-sample — OPEN
- **What:** The LightGBM, CatBoost and XGBoost pickles are loaded and then used to predict rows in `X_all`, which is the same train and validation data used to fit the stacker. The base models' training spans are not recorded, so the meta-learner may over-trust base models.
- **Where:** `train_stacker.py` lines 52-75; `train_deriv_stacker.py` lines 70-95.
- **Fix idea:** Save each base model's training date range with its pickle. Generate stacker features only from out-of-fold or post-training data, and apply the same label-horizon purge used elsewhere.

### 28. Pickle loads of model files — SOURCE FIXED (2026-11-20)
- **Resolution:** `safe_pickle.py` (new) provides whitelisted-globals `SafeUnpickler`; all executable `pickle.load` sites now use `safe_pickle_load`.
- **Status:** Fixed in batch 299b remaining-work.

### 29. ZMQ prediction server has no authentication — SOURCE FIXED (2026-11-20)
- **Resolution:** `ZMQ_AUTH_TOKEN` env var — when set, non-heartbeat requests must carry a matching `token` field or get `{"error": "Unauthorized"}`.
- **Status:** Fixed in batch 299b remaining-work.

### 30. External LLM endpoint defaults and influence on weights — SOURCE FIXED (2026-11-20)
- **Resolution:** External LLM endpoint defaults removed everywhere; enabling the LLM with no endpoint now fails closed instead of targeting localhost:11434.
- **Status:** Fixed in batch 299b remaining-work.

### 31. Grid recovery execution and close ownership — SOURCE FIXED; TERMINAL VERIFICATION OPEN (2026-11-20)
- **Resolution:** Entry refuses to proceed without initialized risk and trade managers, validates through unified risk, sends via `CTradeManager::OpenPosition`, and reconciles the reservation with the execution receipt. An unresolved position ticket is never replaced with an order ticket; the grid retains ownership and blocks additional levels until it resolves.
- **Status:** Source fix only; Grid Recovery remains dormant in the orchestrator.

### 32. Market structure ISP breakout was comparing its bar to a range containing itself — SOURCE FIXED; TERMINAL VERIFICATION OPEN (2026-11-20)
- **Resolution:** ISP requires 22 available bars, builds the consolidation range from completed shifts 2-21, then compares the last completed bar at shift 1 against that prior range. Missing or invalid bars fail closed.
- **Status:** Source fix only; terminal verification outstanding.

### 33. Support and resistance touch counts include the forming bar — SOURCE FIXED; TERMINAL VERIFICATION OPEN (2026-11-20)
- **Resolution:** `UpdateTouches` copies 100 rates from shift 1, so only closed-bar highs and lows contribute to touch counts.
- **Status:** Source fix only; terminal verification outstanding.

### 34. Model file copy and promotion are not verified — OPEN
- **What:** `NNModelStorage_CopyBinaryFile` does not compare byte counts or hashes after copying. `PromoteTempToPrimary` truncates the primary before writing, and the restore after a failed copy ignores its return value. `ArchiveOldCheckpoint` deletes the source without checking the result.
- **Where:** `NNModelStorage.mqh` lines 88-121 (copy), 123-145 (promote), 147-157 (archive).
- **Files:** `Core/AI/NNModelStorage.mqh`
- **Fix idea:** Write to a temp file, compare size and a checksum against the source, then replace the primary. Check the return value of `FileDelete` and of the restore copy.

### 35. Two near-identical EA entry points — OPEN
- **What:** `MultiStrategyAutonomousEA.mq5` and `MultiStrategyTestingEA.mq5` repeat the same inputs (for example `InpMaxPositionsTotal`, lines 55 and 128) and the same config-mapping blocks. Drift between them can change behavior between the test and live builds.
- **Where:** Input blocks and config assignment sections in both files.
- **Files:** `MultiStrategyAutonomousEA.mq5`, `MultiStrategyTestingEA.mq5`
- **Fix idea:** Move shared inputs and the config builder into one `.mqh` include, with only the mode-specific inputs left in each EA.

### 36. Many near-identical Python training scripts — OPEN
- **What:** The repo has separate scripts for each asset class and model (for example `train_xgboost.py`, `train_deriv_xgboost.py`, `train_energies_xgboost.py`, `train_indices_xgboost.py`, `train_metals_catboost.py`, `train_forex_lgbm.py`, `train_deriv_lgbm.py`). Each one repeats the split and labeling logic, so the H11 fix has to be applied to each.
- **Where:** `Python/train_*.py`.
- **Fix idea:** Make one parameterized trainer that takes asset class and model type. Keep the split and labeling in one place.

### 37. Malformed UTF-8 in support/resistance comments — FIXED (2026-11-20)
- **Resolution:** Replaced only comment bytes with ASCII `-` and `~`; strict UTF-8 decoding now passes. The closed-bar regression test reads this header with strict UTF-8, so recurrence fails the test.
- **Files:** `Strategies/SupportResistanceFiles/SupportResistanceDetector.mqh`, `Python/test_closed_bar_signal_contracts.py`

### 38. Comment references to batch and issue IDs — OPEN
- **What:** Comments such as `Batch 156`, `Batch104-C1`, `L10-014` and `L7-015` reference past work and will rot as the code changes.
- **Where:** Many files, for example `SupportResistanceDetector.mqh`, `LiquidityDetector.mqh` (line 789), `GridRecoveryExecution.mqh` (line 28), `SpikeHunterExecutor.mqh`.
- **Fix idea:** Remove the IDs and keep only the reason the code is written that way.

---

## Additional Findings (Third Pass)

### 39. Open: Dashboard trusts localhost but has no API token — PARTIALLY RESOLVED (2026-11-19)
- **Current state:** Dashboard binds to `127.0.0.1`. Credentialed CORS is off; `/state` writes and WebSocket connections reject non-allowlisted browser origins. The command endpoints and queue have been removed.
- **Remaining risk:** Local processes can still push forged state or read the WebSocket because the API has no authentication. Keep the service loopback-only; add authentication before any remote/network exposure.
- **Files:** `Dashboard/server/config.py`, `Dashboard/server/dashboard_server.py`

### 40. RESOLVED: The inert Dashboard command channel was removed (2026-11-19)
- **Resolution:** Removed the fake emergency-stop/mode/parameter controls, WebSocket/REST command queue, EA polling/acknowledgement path, and the unused control input. The Dashboard now explicitly reports telemetry-only status; operators must act in MetaTrader.

### 41. ZMQ heartbeat branch is unreachable and the server can shut itself down while idle — OPEN
- **What:** The EA's heartbeat is an HTTP `GET /heartbeat` (`PyBridgeHealth.mqh` line 127). The ZMQ `type == "heartbeat"` branch comes after the `features` check, so a heartbeat without `features` is rejected. `_run_zmq` also calls `shutdown()` when no request has arrived for `heartbeat_timeout` seconds, and with `--disable-http` nothing refreshes the timestamp during quiet periods.
- **Where:** `zmq_server.py` lines 545-582 and 600-605 (`shutdown` call at 549); the HTTP heartbeat at line 271.
- **Fix idea:** Move the heartbeat check above the `features` check. Have the heartbeat be a real client message, or drop the idle shutdown and rely on the HTTP heartbeat. Confirm which transport the EA uses before changing the timeout.

### 42. RESOLVED: Indicator and cache retry paths no longer sleep (2026-11-19)
- **Resolution:** None of the four named paths contains `Sleep()`; indicator reads return not-ready for a later call, and the cache load is non-blocking.

### 43. RESOLVED: ATR scalp entry used a raw CTrade (2026-11-19)
- **Resolution:** ATR entries now require an initialized `CUnifiedRiskManager` and a configured `CTradeManager`, validate the normalized stop distance, reserve risk before execution, and send through the shared execution receipt path. A definite send failure releases its reservation; the engine's CTrade remains only for position exits.

---

## Additional Findings (Fourth Pass)

### 44. RESOLVED IN SOURCE; BROKER VERIFICATION PENDING: Missing risk data now vetoes entries (2026-11-19)
- **Resolution:** `CPositionSizer` returns no size for missing tick metadata; the shared risk validator rejects non-positive candidate risk; `CPortfolioRiskManager::CalculatePotentialTradeRisk` now returns an invalid sentinel for missing tick/denominator/stop data, and `IsTradeAllowed` rejects it. Unpriceable or unprotected open positions now consume more than the configured portfolio cap in both portfolio and symbol-budget accounting.
- **Verification limit:** Compile/static verification cannot prove broker-specific tick-value behavior; keep live exposure checks disabled until representative tester/runtime logs confirm them.

### 45. Dependency installation shell parsing — SOURCE FIXED; TEST PASSED (2026-11-20)
- **Resolution:** `Python/mql5_v2.py` passes version specifiers as subprocess argument-list items and only installs when explicitly run as a script with `MQL5_V2_INSTALL_DEPENDENCIES=1`; importing the module no longer installs packages.

### 46. Position-count caps may count positions this EA does not own — SOURCE FIXED; TERMINAL VERIFICATION OPEN (2026-11-20)
- **Resolution:** PositionSizer and per-symbol, total, and family caps use the configured `IsMagicOwned` rule. The cold-start symbol-budget bypass now counts the same EA-owned set instead of raw `PositionsTotal`. Correlation analytics may still inspect account-wide positions; those are not EA position-count caps.
- **Verification boundary:** Manual/other-EA position scenarios remain untested in the terminal.

### 47. Retraining request persistence — SOURCE FIXED; RESTART/CONSUMER VERIFICATION OPEN (2026-11-20)
- **Resolution:** Failed reads preserve the canonical file; a staged snapshot is validated and recovered before another append; failed promotions preserve both files; cooldown and attempt count advance only after promotion succeeds.
- **Remaining:** The cooldown is in-memory and is not restored from the request log on restart. The CSV has no in-repo reader or trainer invocation, so persisted requests do not prove a retraining run.
- **Files:** `Core/AI/AIPerformanceFeedback.mqh`

---

## Suggested Order

1. Items 1 to 6 and 24 to 27 (model validity; these affect every reported metric).
2. Items 7 and 8 (AI label and weight logic).
3. Items 9 to 14, 31, 43 (execution safety, including the raw `CTrade` paths).
4. Items 15 to 19, 32, 44 and 46 (risk, exposure and bar-state reads; fail-open sizing).
5. Items 39 and 40 (dashboard exposure and unexecuted commands), then items 20, 28 to 30 and 41 (config parser, model loading, endpoints and ZMQ lifecycle).
6. Items 42, 45, 47, 21 to 23 and 33 to 38 (blocking sleeps, install script, retraining log, compile, recovery, duplication, cleanup).

---

## Status Updates (Historical)

Status updates for Batches 282 through 300f are recorded in [changelogs.md](changelogs.md) and [RUNS_AND_GAINS.md](RUNS_AND_GAINS.md). They are not repeated here to avoid duplication.

Key open structural items carried forward from Batch 288–300f:
- **Per-symbol risk cap that binds on lot size** — `GetSymbolRiskAllocation` is lifted off its budget by the min-lot floor, so it never binds; this is the untested mechanism for controlling the payer itself.
- **Demo attach** — the EA has still never been attached to a chart; sync + compile only.
- **`backtest_report.htm`** — never written by this terminal, so no MT5 profit factor / drawdown / Sharpe anywhere in the repository.
- **`[ENGINE-CLOSE]`** — compiles but has never printed in a run; the scalp-on window (`Tools\backtest_b290_scalp2.ini`) is still unrun.
- **`.set` parks not restored** — `.parked_b291`, `.parked_b291b`, `.parked_b292`, `.parked_b297`, `.parked_b299`, `.parked_b300`, `.parked_b300b`, `.parked_b300d`.
