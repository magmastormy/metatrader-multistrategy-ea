# Remaining Work

Status key: **Open** = not started or only partly addressed. **Verify** = code was changed but broker/runtime evidence is incomplete. The findings below are a historical audit register, not a verified snapshot of the current tree. The clean eight-target compile cited in Batch 298 is historical; this dirty working tree has not been compiled, and no current-tree paired cold-window backtest is available.

---

## Data and model validity

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
- **Fixed:** standard and standalone neural trainers select and gate on validation plus development-only CPCV; CPCV folds use raw training rows only. The selected checkpoint's holdout score is report-only. The standalone LightGBM baseline now reports validation IC, not test IC.
- **Fixed:** Multi_Mt5_Colab_Notebook candidates and LightGBM use validation only, and its CPCV inputs are raw training rows only. The generated Colab tree reports use validation; stacker cells no longer read test rows or publish test metrics.
- **Fixed:** the Kaggle notebook no longer evaluates or stores test classification metrics during selection/export. Its gate remains fail-closed because fold-local CPCV retraining is unavailable; Sharpe annualization uses train+validation timestamps. The final zero-cost forward-return test proxy is report-only after artifact export and is not executable-performance evidence.
- **Removed:** Python/train_all_models.ipynb was a clean, unreferenced, out-of-sync duplicate whose helper signatures and CPCV call no longer matched the current code. Python/write_colab.py is the source for Python/train_all_models_colab.ipynb.
- **Regression coverage:** test_train_model_selection and test_cpcv_raw_scaling_flow cover validation-only gates, candidate holdout isolation, and train-only CPCV for the supported paths.
- **Regression coverage:** `test_train_model_selection` and `test_cpcv_raw_scaling_flow` cover validation-only gates, candidate holdout isolation, train-only CPCV, and the Kaggle notebook boundary.
- **Still open:** no real-data walk-forward run or broker/terminal-backed performance evidence has been produced. A report-only holdout can still be manually misused to tune later runs; source checks cannot establish whether that happened.
- **Files:** Python/train_model.py, Python/mql5_v2.py, Python/write_colab.py, Python/Multi_Mt5_Colab_Notebook.ipynb, Python/train_all_models_colab.ipynb, Python/EA_Model_Training_Kaggle.ipynb, Python/validate_model.py

---

## AI and consensus

### 7. H11 in-terminal label scan chronology
- **What:** Expired-label resolution scans forward from entry. Bar shift order and the hard 500-bar cap are unverified. A label that hits neither barrier within the cap may be resolved incorrectly.
- **Where:** Expired-label resolution in `CNeuralTrainingDataManager.mqh`.
- **Files:** `AIModules/CNeuralTrainingDataManager.mqh`
- **Fix idea:** Convert shifts to absolute bar times and iterate from the entry shift down to 1 (oldest to newest). Replace the hard cap with `vertical_bars`. Mark labels that cannot be resolved as unresolved instead of guessing.

### 8. H12: consensus weight baseline needs decay and safer keys
- **What:** `LoadAIBaseWeight()` persists a baseline, but there is no time-based decay. Keys are truncated to 63 characters, so long symbol and strategy names can collide. A changed strategy count or order is not handled.
- **Where:** `LoadAIBaseWeight()` in `ConsensusWeightingConfig.mqh`, and the weight target update.
- **Files:** `Core/Management/ConsensusWeightingConfig.mqh`, `Core/Management/StrategyPerformanceHealth.mqh`
- **Fix idea:** Build the key from a short hash (for example CRC32 of symbol + strategy name) plus a readable prefix. Store the strategy name inside the global, or store a version key, so a mismatch resets the baseline. Add decay: `target = base + (evidence - base) * exp(-dt / tau)` with `dt` since last update. Keep the minimum-sample gate.

---

## Execution and broker

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

## Risk and exposure

### 15. Exposure caps cover every reachable entry path — RESOLVED (2026-11-19)
- **Resolution:** `ValidateExposure()` runs inside the unified risk pipeline. Per-symbol and total count caps now include open EA-owned positions plus other in-flight risk reservations, excluding the candidate's own provisional reservation; total-risk checks already use the same exclusion.
- **Entry-path audit:** Main candidates and the fast-scalp market route are the currently dispatched entry paths. ATR, grid, and spike modules contain unified-risk gates but have no orchestrator `ProcessTick` dispatch and are dormant. The raw fast-scalp pending sender had no repo call site and is removed. The async tracker's raw `OrderSend` only cancels an existing order.
- **Dormant lifecycle path:** Pyramiding defaults disabled and `ConfigurePyramiding()` has no repo caller. Its current zero-stop add is rejected by `CTradeManager`; do not enable it without a nonzero-stop unified-risk gate.
- **Files:** `Core/Risk/VirtualPosition.mqh`, `Core/Risk/RiskValidationPipeline.mqh`, `Core/Scalp/FastScalpEngine.mqh`, `Core/Scalp/FastScalpTypes.mqh`, `Core/Orchestration/EAOrchestrator.mqh`

### 16. Opposing strategy votes need arbitration and tests — PARTIALLY RESOLVED; REGRESSION TESTS OPEN (2026-11-20)
- **Source behavior:** Equal aggregate scores return no trade and log both sides' votes, weights, and scores. A configured conflict deadband rejects larger dissent but intentionally permits dissent below the effective threshold; it is not a strict no-conflict rule.
- **Remaining:** Add executable regression coverage for ties, below-deadband dissent, and vetoed conflicts, then verify in MetaEditor/terminal.
- **Where:** Vote aggregation in EAOrchestrator.mqh and the consensus code.
- **Files:** Core/Orchestration/EAOrchestrator.mqh, Core/Management/ConsensusEngine.mqh, Core/Management/ConsensusWeightingConfig.mqh

### 17. Local stop, RR, and spread guards per strategy — SOURCE AUDIT PASSED; TERMINAL VERIFICATION OPEN (2026-11-20)
- **Resolution:** The 23 current CStrategyBase-derived strategy files were source-scanned. All signal-producing strategies use CSignalGuards; Statistical Arbitrage is the sole exception and returns TRADE_SIGNAL_NONE after detecting a pair signal because its second leg is not executed. Support/resistance sub-strategies are gated by their parent strategy before emission.
- **Verification boundary:** This is source-reference evidence, not a compiled or broker-backed test.
- **Where:** Strategy signal functions under Strategies/; shared guard in Core/Utils/SignalGuards.mqh.

### 18. NY open gap DST and session boundaries — PARTIALLY RESOLVED; BROKER OFFSET VERIFICATION OPEN (2026-11-20)
- **Resolution:** US DST transition instants are represented in UTC (07:00 UTC on the second Sunday in March; 06:00 UTC on the first Sunday in November), and the helper evaluates each target GMT instant. Historical M30 bars require exact broker-time matches, so an offset mismatch abstains instead of selecting a nearby bar.
- **Remaining:** Broker standard offset is inferred from the current server/GMT offset. Brokers with independent DST schedules can cause a safe false abstention around offset-change periods; resolving that needs explicit broker offset policy or terminal history evidence.

### 19. Crisis limits and hardcoded thresholds
- **What:** The ATR crisis ratio thresholds are already EA inputs (`InpAtrCrisisRatioThreshold*`), so they are done. Remaining fixed literals still need to be found and moved to inputs.
- **Where:** Search for numeric literals in risk and crisis code.
- **Files:** `Core/Config/OrchestratorConfig.mqh`, `Core/Risk/*.mqh`, `MultiStrategyAutonomousEA.mq5`, `MultiStrategyTestingEA.mq5`, and matching `.set` files
- **Fix idea:** Add inputs with the current values as defaults. Update the `.set` files. Note that removing the unused profit-floor key already changed `.set` mapping.

---

## Configuration

### 20. Live config parser — SOURCE FIXED; COMPILE/EDGE-CASE VERIFICATION OPEN (2026-11-20)
- **Resolution:** Parser prototypes precede their use; the whole document is tokenized and recursively grammar-checked, duplicate keys at any nesting depth and trailing data are rejected, and supported risk values receive type/range checks.
- **Verification boundary:** MetaEditor compile and executable malformed-document cases remain outstanding.
- **Where:** Core/Config/LiveConfigReloader.mqh; supported risk application remains in Core/Orchestration/EAOrchestrator.mqh.

---

## Verification and housekeeping

### 21. MQL5 compile of all modified files
- **What:** No MQL5 file has been compiled since the changes. Compile errors are likely in the new parser, async reconciliation, and NY gap code.
- **Where:** All `.mq5` and `.mqh` files changed in this work.
- **Files:** `Core/Trading/TradeMgrAsyncExecutor.mqh`, `Core/Trading/TradeMgrPreflight.mqh`, `Core/Trading/TradeManager.mqh`, `Core/Trading/TradeTypes.mqh`, `Core/Scalp/FastScalpAsyncTracker.mqh`, `Core/Scalp/ATRScalpExit.mqh`, `Core/Scalp/ATRScalpEntry.mqh`, `Core/Scalp/SpikeHunterExecutor.mqh`, `Core/Risk/PositionSizer.mqh`, `Core/Risk/RiskMarginHealth.mqh`, `Core/Risk/RiskValidationPipeline.mqh`, `Core/Risk/PortfolioRiskManager.mqh`, `Core/Risk/CorrelationEngine.mqh`, `Core/Management/ConsensusWeightingConfig.mqh`, `Core/Management/StrategyPerformanceHealth.mqh`, `Core/Config/LiveConfigReloader.mqh`, `Core/Config/OrchestratorConfig.mqh`, `Core/Orchestration/EAOrchestrator.mqh`, `Core/Strategy/PythonBridgeAIStrategyAdapter.mqh`, `Strategies/NYOpenGapStrategy.mqh`, `Strategies/MeanReversionStrategy.mqh`, `Strategies/RangeCompressionBreakout.mqh`, `Strategies/FVGScalperStrategy.mqh`, `Strategies/BreakerBlockStrategy.mqh`, `Strategies/UnifiedICTFiles/MarketStructureAnalyzer.mqh`, `Core/Engines/MarketAnalysisMetrics.mqh`, `AIModules/CNeuralTrainingDataManager.mqh`, `crash_recovery_helpers.mqh`, `MultiStrategyAutonomousEA.mq5`, `MultiStrategyTestingEA.mq5`
- **Fix idea:** Compile each EA in MetaEditor and fix errors. Treat the compile as the gate before any live deployment.

### 22. Crash recovery replacement
- **What:** The replacement write no longer deletes the last good file first, but the runtime behavior of the move call is not verified.
- **Where:** `crash_recovery_helpers.mqh`.
- **Files:** `crash_recovery_helpers.mqh`
- **Fix idea:** Confirm `FileMove` return value and fall back to keeping the old file on failure.

### 23. Git state
- **What:** Changes are meant to stay uncommitted. Recent status notices were inconsistent, so commit state has not been confirmed.
- **Where:** Repository root.
- **Files:** None
- **Fix idea:** Git commands are blocked by the environment's ACL, so confirm the state through the UI History tab. A push notice showed commit `9bfe6fe` on branch `ai_main_3ae626c74d1641fb8261`; this was not triggered by a push request in this session, so check whether those commits contain the intended changes.

---

## Additional findings (second pass)

### 24. mql5_v2.py CPCV purge is sample-count based and misses gaps between test groups
- **What:** `purge_embargo` builds its mask only from `test_idx.min()` and `test_idx.max()`, and it purges by a fixed 5 samples. CPCV test sets are two non-contiguous groups, so training samples that sit between those groups are kept even though they overlap the test labels.
- **Where:** `purge_embargo` (lines 826-829) and `cpcv_folds` (lines 831-839) in `mql5_v2.py`.
- **Files:** `Python/mql5_v2.py`
- **Fix idea:** Delete the local copy and import `purge_embargo` and `cpcv_folds` from `Python/validate_model.py`, which checks each training sample against every test start within the label horizon. This also closes the sample-count part of item 3.

### 25. Duplicate label logic in mql5_v2.py
- **What:** `triple_barrier_labels` (line 206) is a second implementation next to `data_pipeline.triple_barrier_labels` (line 102). Any fix to one can silently miss the other.
- **Where:** `Python/mql5_v2.py` line 206; `Python/data_pipeline.py` line 102.
- **Files:** `Python/mql5_v2.py`, `Python/data_pipeline.py`
- **Fix idea:** Keep one implementation in `data_pipeline.py` and import it. Check that the two versions currently agree on tie-breaks and horizon before deleting the copy.

### 26. Stacker meta-features are left as zeros for the first block
- **What:** `TimeSeriesSplit` only puts the last `n_splits` blocks into validation folds. The first block of rows is only ever training data, so `meta_X` stays all zeros there, and the ridge meta-learner is fitted on those zero rows.
- **Where:** `train_stacker.py` lines 77-92; `train_deriv_stacker.py` lines 95-110; `write_colab.py` lines 731-745 and 832-842 (generated Colab code).
- **Files:** `Python/train_stacker.py`, `Python/train_deriv_stacker.py`, `Python/write_colab.py`
- **Fix idea:** Build out-of-fold predictions that cover every row, for example by training each base model per fold as CPCV now does. Add an assertion that no `meta_X` row is all zeros.

### 27. Stacker base-model predictions may be in-sample
- **What:** The LightGBM, CatBoost and XGBoost pickles are loaded and then used to predict rows in `X_all`, which is the same train and validation data used to fit the stacker. The base models' training spans are not recorded, so the meta-learner may over-trust base models.
- **Where:** `train_stacker.py` lines 52-75; `train_deriv_stacker.py` lines 70-95.
- **Files:** `Python/train_stacker.py`, `Python/train_deriv_stacker.py`, `Python/write_colab.py`
- **Fix idea:** Save each base model's training date range with its pickle. Generate stacker features only from out-of-fold or post-training data, and apply the same label-horizon purge used elsewhere.

### 28. Pickle loads of model files
- **What:** Models are loaded with `pickle.load`, which executes code embedded in the file. Files are local, so the risk is low, but a swapped or corrupted model file runs arbitrary code at startup.
- **Where:** `zmq_server.py` lines 109-112 and 191-222; `train_stacker.py` lines 52-63; `train_deriv_stacker.py` lines 70-81; `write_colab.py` lines 720-729 and 818-819.
- **Files:** `Python/zmq_server.py`, `Python/train_stacker.py`, `Python/train_deriv_stacker.py`, `Python/write_colab.py`
- **Fix idea:** Use `joblib` with a SHA-256 manifest checked before load, or export the GBDT models to ONNX so the server does not unpickle at all.

### 29. ZMQ prediction server has no authentication
- **What:** The server binds to `127.0.0.1`, which is good, but any local process can request predictions or state.
- **Where:** `zmq_server.py` line 138.
- **Files:** `Python/zmq_server.py`
- **Fix idea:** Require a shared secret in each request, loaded from the environment. Keep the loopback bind.

### 30. External LLM endpoint defaults and influence on weights
- **What:** When no endpoint is set, `CAIEngine` falls back to `http://localhost:11434` when `useExternalLLM` is on. `QueryExternalLLM` sends a market prompt over `WebRequest` on the adaptation path. It is not yet verified whether the LLM response can change strategy weights without bounds.
- **Where:** `AIEngine.mqh` lines 171-175 and 181-205. Adaptation is called from `EAOrchestrator.mqh` lines 3044 and 3452.
- **Files:** `Core/Engines/AIEngine.mqh`, `Core/Orchestration/EAOrchestrator.mqh`
- **Fix idea:** Make the endpoint explicit with no default. Treat any LLM output as advisory, clamp it to the same bounds as item 8, and log the query without the full prompt.

### 31. Grid recovery execution and close ownership - SOURCE FIXED; TERMINAL VERIFICATION OPEN (2026-11-20)
- **Resolution:** Entry refuses to proceed without initialized risk and trade managers, validates through unified risk, sends via `CTradeManager::OpenPosition`, and reconciles the reservation with the execution receipt. An unresolved position ticket is never replaced with an order ticket; the grid retains ownership and blocks additional levels until it resolves.
- **Resolution:** `CTradeManager::ClosePosition` applies per-symbol dynamic deviation and returns success only after the position ticket is absent. `CloseAllGrids` retains failed, partial, or unresolved levels and aggregate risk rather than clearing state.
- **Regression coverage:** `test_grid_recovery_uses_shared_execution_for_entry_and_close`, `test_close_requires_position_reconciliation_before_release`, and `test_grid_close_failure_retains_ownership_and_blocks_new_levels` cover these contracts.
- **Runtime status:** The grid engine has no `ProcessTick` caller in the orchestrator and is currently dormant; source changes do not imply live behavior.
- **Verification boundary:** MetaEditor compilation and broker-backed fill/partial-close/restart checks remain outstanding.
- **Files:** `Core/Scalp/GridRecoveryExecution.mqh`, `Core/Trading/TradeManager.mqh`

### 32. Market structure ISP breakout was comparing its bar to a range containing itself - SOURCE FIXED; TERMINAL VERIFICATION OPEN (2026-11-20)
- **Resolution:** ISP requires 22 available bars, builds the consolidation range from completed shifts 2-21, then compares the last completed bar at shift 1 against that prior range. Missing or invalid bars fail closed. This fixes both forming-bar instability and the prior self-inclusion that made a breakout comparison impossible.
- **Regression coverage:** `test_isp_compares_last_closed_bar_with_prior_consolidation` checks the exclusion and closed-bar shifts.
- **Verification boundary:** MetaEditor compile and market-data signal verification remain outstanding.
- **Files:** `Strategies/UnifiedICTFiles/MarketStructureAnalyzer.mqh`

### 33. Support and resistance touch counts include the forming bar - SOURCE FIXED; TERMINAL VERIFICATION OPEN (2026-11-20)
- **Resolution:** `UpdateTouches` copies 100 rates from shift 1, so only closed-bar highs and lows contribute to touch counts.
- **Regression coverage:** `test_support_resistance_touch_count_excludes_forming_bar` checks the rates start shift.
- **Verification boundary:** MetaEditor compile and strategy runtime checks remain outstanding. Recomputing only on a new bar is an optional performance optimization, not required for closed-bar count stability.
- **Files:** `Strategies/SupportResistanceFiles/SupportResistanceDetector.mqh`

### 34. Model file copy and promotion are not verified
- **What:** `NNModelStorage_CopyBinaryFile` does not compare byte counts or hashes after copying. `PromoteTempToPrimary` truncates the primary before writing, and the restore after a failed copy ignores its return value. `ArchiveOldCheckpoint` deletes the source without checking the result.
- **Where:** `NNModelStorage.mqh` lines 88-121 (copy), 123-145 (promote), 147-157 (archive).
- **Files:** `Core/AI/NNModelStorage.mqh`
- **Fix idea:** Write to a temp file, compare size and a checksum against the source, then replace the primary. Check the return value of `FileDelete` and of the restore copy.

### 35. Two near-identical EA entry points
- **What:** `MultiStrategyAutonomousEA.mq5` and `MultiStrategyTestingEA.mq5` repeat the same inputs (for example `InpMaxPositionsTotal`, lines 55 and 128) and the same config-mapping blocks. Drift between them can change behavior between the test and live builds.
- **Where:** Input blocks and config assignment sections in both files.
- **Files:** `MultiStrategyAutonomousEA.mq5`, `MultiStrategyTestingEA.mq5`
- **Fix idea:** Move shared inputs and the config builder into one `.mqh` include, with only the mode-specific inputs left in each EA.

### 36. Many near-identical Python training scripts
- **What:** The repo has separate scripts for each asset class and model (for example `train_xgboost.py`, `train_deriv_xgboost.py`, `train_energies_xgboost.py`, `train_indices_xgboost.py`, `train_metals_catboost.py`, `train_forex_lgbm.py`, `train_deriv_lgbm.py`). Each one repeats the split and labeling logic, so the H11 fix has to be applied to each.
- **Where:** `Python/train_*.py`.
- **Files:** All `Python/train_*.py` scripts
- **Fix idea:** Make one parameterized trainer that takes asset class and model type. Keep the split and labeling in one place.

### 37. Malformed UTF-8 in support/resistance comments — FIXED (2026-11-20)
- **Finding corrected:** The original audit named `ATRScalpEntry.mqh`, `SpikeHunterExecutor.mqh` and `VolatilityEngine.mqh`, but their committed and working-tree versions are valid UTF-8 and contain no replacement or malformed-byte markers. Those paths were false positives and were not changed for encoding.
- **Root cause:** `SupportResistanceDetector.mqh` contained three truncated UTF-8 byte sequences in comments (two em-dash sequences and one approximation sign), making strict UTF-8 decoding fail.
- **Resolution:** Replaced only those comment bytes with ASCII `-` and `~`; strict UTF-8 decoding now passes. The closed-bar regression test reads this header with strict UTF-8, so recurrence fails the test.
- **Verification boundary:** Source encoding and regression contract verified; MetaEditor compilation remains outstanding.
- **Files:** `Strategies/SupportResistanceFiles/SupportResistanceDetector.mqh`, `Python/test_closed_bar_signal_contracts.py`

### 38. Comment references to batch and issue IDs
- **What:** Comments such as `Batch 156`, `Batch104-C1`, `L10-014` and `L7-015` reference past work and will rot as the code changes.
- **Where:** Many files, for example `SupportResistanceDetector.mqh`, `LiquidityDetector.mqh` (line 789), `GridRecoveryExecution.mqh` (line 28), `SpikeHunterExecutor.mqh`.
- **Files:** Search with `Batch\s*\d+|L\d+-\d+`
- **Fix idea:** Remove the IDs and keep only the reason the code is written that way.

---

## Additional findings (third pass)

### 39. Open: Dashboard trusts localhost but has no API token
- **Current state (2026-11-19):** Dashboard binds to `127.0.0.1`. Credentialed CORS is off; `/state` writes and WebSocket connections reject non-allowlisted browser origins. The command endpoints and queue have been removed.
- **Remaining risk:** Local processes can still push forged state or read the WebSocket because the API has no authentication. Keep the service loopback-only; add authentication before any remote/network exposure.
- **Files:** `Dashboard/server/config.py`, `Dashboard/server/dashboard_server.py`

### 40. RESOLVED: The inert Dashboard command channel was removed
- **Resolution (2026-11-19):** Removed the fake emergency-stop/mode/parameter controls, WebSocket/REST command queue, EA polling/acknowledgement path, and the unused control input. The Dashboard now explicitly reports telemetry-only status; operators must act in MetaTrader.
- **Files:** `Dashboard/client/src/Dashboard.tsx`, `Dashboard/server/dashboard_server.py`, `Dashboard/server/state_manager.py`, `Core/Utils/DashBridgeTransport.mqh`, `Core/Utils/DashboardBridge.mqh`, `Core/Orchestration/EAOrchestrator.mqh`, `Core/Config/SharedEAInputs.mqh`

### 41. ZMQ heartbeat branch is unreachable and the server can shut itself down while idle
- **What:** The EA's heartbeat is an HTTP `GET /heartbeat` (`PyBridgeHealth.mqh` line 127). The ZMQ `type == "heartbeat"` branch comes after the `features` check, so a heartbeat without `features` is rejected. `_run_zmq` also calls `shutdown()` when no request has arrived for `heartbeat_timeout` seconds, and with `--disable-http` nothing refreshes the timestamp during quiet periods.
- **Where:** `zmq_server.py` lines 545-582 and 600-605 (`shutdown` call at 549); the HTTP heartbeat at line 271.
- **Files:** `Python/zmq_server.py`, and the ZMQ client if one exists in MQL5 (no ZMQ client was found in this repo)
- **Fix idea:** Move the heartbeat check above the `features` check. Have the heartbeat be a real client message, or drop the idle shutdown and rely on the HTTP heartbeat. Confirm which transport the EA uses before changing the timeout.

### 42. RESOLVED: Indicator and cache retry paths no longer sleep
- **Resolution (2026-11-19 source check):** None of the four named paths contains `Sleep()`; indicator reads return not-ready for a later call, and the cache load is non-blocking.
- **Files:** `Core/Engines/TrendADX.mqh`, `Core/Engines/MarketAnalysisIndicators.mqh`, `Core/Engines/MarketAnalysisMetrics.mqh`, `Core/Scalp/ScalpSignalCache.mqh`

### 43. RESOLVED: ATR scalp entry used a raw CTrade
- **Resolution (2026-11-19):** ATR entries now require an initialized CUnifiedRiskManager and a configured CTradeManager, validate the normalized stop distance, reserve risk before execution, and send through the shared execution receipt path. A definite send failure releases its reservation; the engine's CTrade remains only for position exits.
- **Files:** Core/Scalp/ATRScalpEntry.mqh, Core/Scalp/ATRScalpingEngine.mqh, Core/Orchestration/EAOrchestrator.mqh

---

## Additional findings (fourth pass)

### 44. RESOLVED IN SOURCE; BROKER VERIFICATION PENDING: Missing risk data now vetoes entries
- **Resolution (2026-11-19):** `CPositionSizer` returns no size for missing tick metadata; the shared risk validator rejects non-positive candidate risk; `CPortfolioRiskManager::CalculatePotentialTradeRisk` now returns an invalid sentinel for missing tick/denominator/stop data, and `IsTradeAllowed` rejects it. Unpriceable or unprotected open positions now consume more than the configured portfolio cap in both portfolio and symbol-budget accounting.
- **Verification limit:** Compile/static verification cannot prove broker-specific tick-value behavior; keep live exposure checks disabled until representative tester/runtime logs confirm them.
- **Files:** `Core/Risk/PortfolioRiskManager.mqh`, `Core/Risk/UnifiedRiskManager.mqh`, `Core/Risk/PositionSizer.mqh`, `Core/Risk/RiskValidationPipeline.mqh`

### 45. Dependency installation shell parsing — SOURCE FIXED; TEST PASSED (2026-11-20)
- **Resolution:** Python/mql5_v2.py passes version specifiers as subprocess argument-list items and only installs when explicitly run as a script with MQL5_V2_INSTALL_DEPENDENCIES=1; importing the module no longer installs packages.
- **Verification:** python -m unittest Python.test_mql5_v2_setup_safety passed (1 test). This checks the installer call stays inside the explicit opt-in function/main guard and uses an argument list.
- **Scope note:** Python/write_colab.py generates a separate Colab notebook setup cell; it does not copy this script's import-time installer.

### 46. Position-count caps may count positions this EA does not own — SOURCE FIXED; TERMINAL VERIFICATION OPEN (2026-11-20)
- **Resolution:** PositionSizer and per-symbol, total, and family caps use the configured IsMagicOwned rule. The cold-start symbol-budget bypass now counts the same EA-owned set instead of raw PositionsTotal. Correlation analytics may still inspect account-wide positions; those are not EA position-count caps.
- **Verification boundary:** Manual/other-EA position scenarios remain untested in the terminal.

### 47. Retraining request persistence — SOURCE FIXED; RESTART/CONSUMER VERIFICATION OPEN (2026-11-20)
- **Resolution:** Failed reads preserve the canonical file; a staged snapshot is validated and recovered before another append; failed promotions preserve both files; cooldown and attempt count advance only after promotion succeeds.
- **Remaining:** The cooldown is in-memory and is not restored from the request log on restart. The CSV has no in-repo reader or trainer invocation, so persisted requests do not prove a retraining run.
- **Files:** Core/AI/AIPerformanceFeedback.mqh

## Suggested order
1. Items 1 to 6 and 24 to 27 (model validity; these affect every reported metric).
2. Items 7 and 8 (AI label and weight logic).
3. Items 9 to 14, 31, 43 (execution safety, including the raw `CTrade` paths).
4. Items 15 to 19, 32, 44 and 46 (risk, exposure and bar-state reads; fail-open sizing).
5. Items 39 and 40 (dashboard exposure and unexecuted commands), then items 20, 28 to 30 and 41 (config parser, model loading, endpoints and ZMQ lifecycle).
6. Items 42, 45, 47, 21 to 23 and 33 to 38 (blocking sleeps, install script, retraining log, compile, recovery, duplication, cleanup).

---

## Status update - Batch 288 (2026-11-13)

The run-by-run record now lives in `RUNS_AND_GAINS.md`; this list stays as the open-item backlog.

- **Closed by measurement, not by opinion:** the "thresholds" are not a tuning surface. `InpSingleVoterFloor`, `InpQuorumProfile`, the support floors and the quorum threshold are inert on the tested windows; `ApplyQuorumProfile` never writes `intrabarMinQuorum`, and every reject in the window was an intrabar evaluation.
- **The one lever with evidence is shipped:** `InpMinLiveVoters` default 2 -> 1 (six windows, mean +0.46%, stdev 0.92 pp, paired +1.80 pp, t 2.6, p ~ 0.08). Rejects 2,054-2,819 -> 139-227 per window.
- **Item 50 (per-symbol loss streak):** measured in both forms - blocking entries (Batch 286, -4.75 pp) and scaling position size (Batch 287, mean -2.14 pp). Both are off factory-default (`InpSymbolLossStreakLimit=0`, `InpSymbolStreakRiskScale=1.0`) because a skipped or shrunk entry reallocates the risk instead of removing it, and the trades after a losing run are the largest winners.
- **Reproducibility is fixed (Batch 282):** `Core/Utils/EAClock.mqh` gives `EAClockMs()`, simulated time under `MQL_TESTER` and `GetTickCount()` live. Two cold runs are bit-identical now; before the fix the same build and window differed by 10 pp.
- **Still open here:** items 15, 43, 19, 20, 8, 41, 47; `backtest_report.htm` is never produced by this terminal, so there is no MT5 profit factor / max drawdown / Sharpe and every figure is rebuilt from `[COMPOUNDING-TIER-HEARTBEAT]` equity samples.
- **Not yet done:** the EA now trades a Deriv-Demo chart (V75 M15, shipped defaults) - behaviour under real tick timing has never been observed, and the six-window +0.46% mean is break-even inside noise, not a proven profit.
---

## Status update - Batch 290 (2026-11-13)

The run-by-run record lives in `RUNS_AND_GAINS.md`; this list stays the open-item backlog.

- **The Batch 289 build was measured, and the repairs alone were not a gain.** Cold, same window and inputs as the Batch 288 baseline (2026.09.01->09.08, V75 M15, Model=1, deposit 10,000, InpQuorumProfile=1, InpMinLiveVoters=1): **-258.77 (-2.588%) on 2,265 fills**, against **+98.29 (+0.983%) on 849 fills** for the previous build. -3.57 pp and +167% fills, far outside the 0.92 pp cross-window noise.
- **The single-variable A/B names the engine that loses.** Same build, same window, one input changed (InpEnableScalpEngine=0, no recompile): **+381.07 (+3.811%) on 270 fills**, min 9,891.96, max 10,381.42. A **+6.40 pp** swing. The fast-scalp engine is negative-expectancy once its cost gate stops refusing ten of the twelve symbols; the consensus book alone pays on this build.
- **Not shipped yet, deliberately.** InpEnableScalpEngine stays at its factory default of `true` until the scalp-off arm reproduces on the neighbouring windows (Batch 288 set the precedent: ship only what has a multi-window distribution).
- **New code, compiled and unmeasured:** InpScalpSymbolsCsv (`""` = every symbol) -> SOrchestratorConfig.scalpSymbolsCsv -> IsScalpSymbolAllowed() in ProcessScalpFastPath. Tools\backtest_b290_scalp2.ini (XAUUSD,Step Index) is the staged arm that separates "which symbols" from "which geometry". sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 900 -> 0 errors, 0 warnings on both root EAs.
- **New measurement prerequisite (do this before the next attribution run):** print realised P&L on the fast-scalp exit path. `Core\Scalp\FastScalpExit.mqh` closes positions without a `Trade Closed ... Net Profit` record: 260 close records against 2,265 fills, and the 260 recorded closes sum to +11.03 against a -258.77 account delta, so about 270 USD of the loss is invisible.
- **Operational hazard:** `ShutdownTerminal=1` does not terminate `terminal64`; a leftover terminal silently swallows the next `Start-Process ... /config:` launch. Check `Get-Process terminal64,metatester64` before every launch.
- **Still open here:** items 15, 43, 19, 20, 8, 41, 47 unchanged; `backtest_report.htm` still never produced, so still no MT5 profit factor / drawdown / Sharpe.
## Status update - Batch 291 (2026-11-13)

The run-by-run record lives in `RUNS_AND_GAINS.md`; this list stays the open-item backlog.

- **The scalp-off arm is now a distribution, and it is the default.** Five consecutive cold 7-day windows on the same instrument and harness (`Volatility 75 Index` M15, Model=1, deposit 10,000, `InpQuorumProfile=1`, `InpMinLiveVoters=1`): **+3.811 / +0.635 / +1.489 / +2.640 / +1.009 %** (260-279 fills each) -> mean **+1.917%**, sd **1.30 pp**, **t 3.30**, **5 wins of 5**. The scalper-on control on the first window is **-2.588% on 2,265 fills**. `InpEnableScalpEngine` is therefore now `false` in `Core\Config\SharedEAInputs.mqh`, with the numbers and the paired-window rule written beside it.
- **The factory default was proved, not assumed.** The fifth arm's ini omits `InpEnableScalpEngine` and `MQL5\Profiles\Tester\MultiStrategyAutonomousEA.set` was parked aside before launch (MT5 reuses that file as the next run's inputs and rewrites it afterwards). The run printed **0** `[SCALP-SIGNAL-REJECT]` lines, i.e. the compiled default executed.
- **The invisible-close gap is now instrumented.** `StrategyMgrTradeFeedback.mqh` prints `[ENGINE-CLOSE] ... net=...` for engine-managed closes instead of returning silently; compiled, but not yet observed because the engine is off by default.
- **Next measurement, in order:** (1) one cold window on the post-logging build to confirm the default reproduces the distribution; (2) `Tools\backtest_b290_scalp2.ini` (scalper limited to `XAUUSD,Step Index`) paired against the same window with the engine off, which decides whether the scalper is wrong or merely wrong on eleven of thirteen symbols; (3) only then consider a wider symbol whitelist.
- **Operational note:** the tester journal rotates mid-run (it reset to 66 MB and reached 881 MB within this batch), so byte offsets are useless - read the tail (`python read_run.py <journal> 320-340`) and treat "last 10,080 heartbeats = last run" as the reliable window read.
- **Still open here:** items 15, 43, 19, 20, 8, 41, 47 unchanged; `backtest_report.htm` still never produced, so still no MT5 profit factor / drawdown / Sharpe; the five-window distribution is one instrument and one contiguous 2026-09/10 slice - out-of-window, not out-of-regime.
## Status update - Batch 292 (2026-11-13)

The run-by-run record lives in `RUNS_AND_GAINS.md`; this list stays the open-item backlog.

- **The shipped default lost its first window.** Factory default (scalper off, `.set` parked, `InpEnableScalpEngine` omitted), `2026.10.06`->`10.13`: **-269.61 (-2.696%)**, 307 fills, min 9,713.44. Six-window distribution is now **mean +1.148%, sd 2.213 pp, t 1.27, 5 wins of 6** - the five-window t of 3.30 does not survive one bad week.
- **The loss is one instrument.** `Volatility 75 Index` **-116.53 on 5 closes** carried a -269.61 window; `Volatility 25` -52.93 on 27 closes; `Crash 1000` only -36.64 on 33. Worst drawdown -188.22 inside the first three hours.
- **Universe trim (existing `InpSymbolsToTrade`, no code change) improves every paired window:** +2.10 pp, +5.97 pp, +15.54 pp; trimmed arm mean **+8.345%**, sd 9.50 pp, 3/3 up. But `Crash 1000` alone delivered +719.52 (87 closes) and +1,848.83 (85 closes) in the two winning arms - the trim is a single-instrument bet.
- **Not shipped** because the older record contradicts it: Batch 285 measured `Crash 1000` -123.06 and `Volatility 75` +261.22 in the one-voter arm, swapped in the committee arm. It needs 5-6 paired windows first. This is the single highest-value open experiment.
- **Method fix:** the last 10,080-heartbeat slice can start inside the previous run (the aborted window-3 launch left four heartbeats at 9,948.23 at the head). The base for a delta is the sample whose balance is exactly 10,000.00 within the first ten samples - otherwise both window 3 and window 4 read high by 60-190 USD.
- **Concentration is now the open structural question:** a week is decided by 5-13 closes of one index. A per-symbol risk cap (rather than symbol exclusion) is the untested lever that would make the book independent of which index trends - Batch 286/287 showed that blocking entries reallocates risk, so the cap has to be enforced at sizing, not at the entry gate.
- **Still open here:** items 15, 43, 19, 20, 8, 41, 47 unchanged; `[ENGINE-CLOSE]` never fired; `Tools\backtest_b290_scalp2.ini` unrun; `backtest_report.htm` still never produced, so still no MT5 profit factor / drawdown / Sharpe; no live attach.
## Status update - Batch 293 (2026-11-13)

- **SHIPPED:** `InpSymbolsToTrade` factory default no longer contains `Volatility 25 Index` / `Volatility 75 Index`. Five paired cold windows, paired deltas **+2.13 / +7.05 / +5.97 / +15.54 / +2.10 pp** (mean +6.558 pp, sd 5.39, t 2.72, 5/5), trimmed arm mean **+7.734%**, sd 6.74 pp, worst **-0.599%**. Verified by omitting the input with `.set` parked: **+18.176%** vs the arm's +18.176% (six cents), 314 receipts, `[SCALP-SIGNAL-REJECT]` 0.
- **Open, highest value:** a per-symbol risk cap enforced at sizing. Every winning window above is `Crash 1000` (+763.58 / +499.05 / +719.52 / +1,848.83 / +1,756.56); no window yet shows it trending against the book, so the trim's true downside is unmeasured. Batch 286/287 proved entry-gate blocks only reallocate risk, so the cap must bind on the lot, not on the entry.
- **Historical deviation (Batch 293):** the then-current `InpAutoAddChartSymbol` setting re-injected the chart symbol and produced 2-4 `Volatility 75` closes. The input and reinjection path have since been removed; this source change still needs a cold run with a chart symbol excluded from `InpSymbolsToTrade`.
- **Measurement:** the tester/terminal logs are date-stamped; a run started after midnight writes a new file, so any poller must re-resolve the path. Delta base is the heartbeat whose balance is exactly 10,000.00 within the first ten samples.
- **Still open:** `[ENGINE-CLOSE]` never fired (scalper off); `Tools\backtest_b290_scalp2.ini` unrun; `backtest_report.htm` never written so still no MT5 profit factor / drawdown / Sharpe; no live attach; items 15/43/19/20/8/41/47 unchanged.

## Status update - Batch 294 (2026-11-14)

- **Done, measured, nothing shipped:** the risk dial was tested as a profit multiplier on two windows of the shipped trimmed universe, same Batch 293 binary, no code change. 09.22->09.29: factory **+18.176%**, 2% per trade with 8% daily / 24% portfolio **-1.217%**, 4% per trade only **+7.625%**. 10.06->10.13: factory **-0.599%**, **-3.614%**, **+2.097%**. Means **+8.79% / -2.42% / +4.86%**, cross-window sd 13.28 / 1.70 / 3.91 pp. Conclusion: the risk percentage re-selects the book instead of scaling it, and the factory setting is the best measured configuration, so `InpMaxRiskPerTrade=1.0`, `InpMaxDailyRisk=4.0`, `InpMaxPortfolioRisk=12.0` are unchanged.
- **Why:** at 4% the EA warns `InpMaxRiskPerTrade * InpMaxPositionsTotal (60.00) > InpMaxPortfolioRisk * 1.5 (18.00)`, and `reason=daily_risk_would_exceed` rises from ~2,884 per window at 1% to 27,471 at 2% and 17,631 at 4%. A 1.00-2.00% candidate lets the 4.00% daily budget admit two positions where the 1% book ran fifteen. Fills move from `Crash 1000`-led to `Jump 75`-led (122 of 293 receipts at 4%, 172 of 450 at 2%) - the cap refuses first the instrument that pays.
- **Diagnosis worth keeping:** `InpMaxRiskPerTrade = 1.0` implies 100 USD risk on a 10,000 deposit, but realised closes average about +/-23 USD, so sizing lands on the broker minimum lot and the book risks ~0.2% per trade. Absolute size is set by the lot floor; the percentage ceiling is never reached. This is the mechanical answer to "why is this slow".
- **Still open, and now the highest-value lever:** the daily-ceiling-only arm - `InpMaxRiskPerTrade=1.0` with `InpMaxDailyRisk=8.0` and `InpMaxPortfolioRisk=24.0`. It is the one configuration that could raise concurrent throughput without touching per-trade risk, and it is unrun.
- **Open from before:** the per-symbol risk cap at sizing (untested, and Batch 294 shows the budget layer rejects rather than trims, so a cap would need to bind on the lot); `InpAutoAddChartSymbol=false` paired run; `[ENGINE-CLOSE]` never fired; `Toolsacktest_b290_scalp2.ini` unrun; `backtest_report.htm` never written so still no MT5 profit factor / drawdown / Sharpe; no live attach; items 15/43/19/20/8/41/47 unchanged.
- **Measurement hazard:** the tester journal is recreated per run, so a finished window's equity is destroyed by the next launch unless the journal is snapshotted at `last test passed`. A heartbeat slice can also start inside the previous run, so the base is the sample with balance exactly 10,000.00 within the first ten of the last 10,080.

## Status update - Batch 295 (2026-11-14)

- **Done, measured, rejected:** the daily-ceiling-only lever Batch 294 named as unrun was run on five paired windows: 1% per trade with `InpMaxDailyRisk=8.0` and `InpMaxPortfolioRisk=24.0`, same Batch 293 binary, cold each run. Against factory on the same windows: **+6.126 / -5.519 / +2.315 / +8.279 / +5.061 %** vs **+5.945 / +7.689 / +7.459 / +18.176 / -0.599 %**. Arm mean **+3.340%**, sd 5.36 pp, worst **-5.519%**, 4/5; paired deltas mean **-5.26 pp**, sd 7.32 pp, **t -1.61**, 4/5 negative.
- **What it bought / cost:** receipts 328-468 vs 282-307, and the losing window repairs (-0.599 -> +5.061), but the two best windows dilute: `09.22` 18.176 -> 8.279 and `09.08` 7.689 -> -5.519 (deepest loss in the record for a shipped configuration).
- **Structural finding to carry forward:** the +18.176% window is partly an artifact of the 4% ceiling holding concurrency near four positions where four concurrent `Crash 1000` trades were the right four. Widening the budget spreads the same signals into `Jump 75` (183 of 468 receipts on 10.06, 162 of 455 on 09.08). The cap is protective; not a throttle.
- **No input changed:** `InpMaxRiskPerTrade=1.0`, `InpMaxDailyRisk=4.0`, `InpMaxPortfolioRisk=12.0` stand, now with both Batch 294 and Batch 295 behind them.
- **Open, next in line:** a 4% -> 6% daily step (the 4 -> 8 jump may be too coarse to reveal a real optimum); a per-symbol cap that binds on the lot rather than the entry (Batch 286/287 proof still points there); chart-symbol exclusion verification on the new source; `[ENGINE-CLOSE]` never fired; `Tools\backtest_b290_scalp2.ini` unrun; `backtest_report.htm` never written so still no MT5 profit factor / drawdown / Sharpe; no live attach; items 15/43/19/20/8/41/47 unchanged.
- **Boundary on all of this:** every window in the record is 2026-09/10 on one instrument, under one harness, with no live attach. The advertised mean is +7.734% per 7 days for the shipped universe, t 2.57, worst -0.599% - out-of-window but not out-of-regime.

## Status update - Batch 296 (2026-11-14)

Survival outside the 2026-09/10 slice was the highest-value untested question, and it now has two answers.

Factory configuration (1% / 4% / 12%, eleven symbols, scalper off), cold, Batch 293 binary:

- `2026.08.01` -> `08.08`: 10,000.00 -> **9,641.67**, **-3.583%**, 381 receipts, min 9,597.41, max 10,000.00.
- `2026.08.08` -> `08.15`: 10,000.00 -> **10,717.72**, **+7.177%**, 336 receipts, min 9,997.05, max 10,924.92.

The losing window never rises above its own start. Attribution says why: `08.08` is `Crash 1000` **+850.02 / 88**
(every other row together slightly negative), and `08.01` is `Crash 1000` **+54.39 / 92** with `Step` -167.07,
USDJPY -106.01, `Jump 25` -59.35, `Jump 75` -34.13, XAUUSD -22.05 covering the rest.

Seven-window record: mean **+6.038%**, sd **6.96 pp**, **t 2.30**, 6 of 7 positive, worst -3.583%.

Open items this batch moved:

- [x] Does the shipped default survive outside 2026-09/10? Yes in one week, no in the next - the edge is a single-
      instrument edge, not a portfolio edge.
- [ ] Drop the rows that are negative in every measured window (USDJPY, XAUUSD, EURUSD, `Jump 25`) and measure on
      four paired windows. This is the queued next lever; Batch 293 already showed a trim can pay when the evidence
      is paired.
- [ ] `InpMaxDailyRisk` 4% -> 6% step (the 4 -> 8 jump may be too coarse to see an optimum).
- [ ] Per-symbol risk cap that binds on lot size rather than on entry - 286/287 proved entry gates only
      redistribute risk.
- [ ] Cold-run verification that a chart symbol excluded from `InpSymbolsToTrade` produces no trades on the new source; all cited `Volatility 75` closes predate removal of chart-symbol reinjection.
- [ ] Still no live attach; `[ENGINE-CLOSE]` still never observed; `backtest_report.htm` still never written, so no
      MT5 profit factor / drawdown / Sharpe anywhere in the repository.

## Status update - Batch 297 (2026-11-14)

Shipped: `EURUSD`, `USDJPY` and `XAUUSD` are out of the factory universe. `InpSymbolsToTrade` now reads
`"Boom 1000 Index,Crash 1000 Index,Jump 25 Index,Jump 75 Index,Step Index,GBPUSD,AUDUSD,BTCUSD"`.

Five paired cold windows, same Batch 293 binary, 1% per trade / 4% daily / 12% portfolio, `InpQuorumProfile=1`,
`InpMinLiveVoters=1`, scalper off, deposit 10,000, four state files cleared each run:

| window | eleven symbols | eight symbols | delta |
|---|---|---|---|
| 08.01 -> 08.08 | -3.583% | **+1.630%** | +5.21 pp |
| 08.08 -> 08.15 | +7.177% | **+7.276%** | +0.10 pp |
| 09.01 -> 09.08 | +5.945% | **+5.681%** | -0.26 pp |
| 09.15 -> 09.22 | +7.459% | **+7.444%** | -0.02 pp |
| 10.06 -> 10.13 | -0.599% | **+4.692%** | +5.29 pp |

Eight-symbol arm: mean **+5.345%**, sd **2.37 pp**, **t 5.04**, **5 of 5 positive**, worst **+1.630%** - the first
distribution in this repository with no losing window. Eleven-symbol arm on the same windows: mean +3.280%, sd 5.05,
t 1.45, 3 of 5.

Default verified by omission with the `.set` parked (`...set.parked_b297`): 10,000.00 -> 10,469.22, +4.692%, ending
equity identical to the cent to the arm.

Open items this batch moved:

- [x] Remove the rows that are negative in every measured window - shipped on five paired windows.
- [ ] A week where `Crash 1000` does not pay is still a losing week; `Step` (-81.27, -110.44) and `Jump 25`
      (-119.71, -15.23) still bleed inside the winning windows.
- [ ] Per-symbol risk cap that binds on lot size. `GetSymbolRiskAllocation` is lifted off its budget by the min-lot
      floor, so it never binds; that is the untested mechanism for controlling the payer itself.
- [ ] `InpMaxDailyRisk` 4% -> 6% step (the 4 -> 8 jump may be too coarse to reveal an optimum).
- [ ] Cold-run verification of chart-symbol exclusion on the new source; the cited 10.06 `Volatility 75` closes came from the pre-fix binary.
- [ ] Still no live attach; `[ENGINE-CLOSE]` never observed; `backtest_report.htm` never written, so no MT5 profit
      factor / drawdown / Sharpe anywhere.
- [ ] 4% daily ceiling, 1% per trade and the eight-symbol universe are validated only on 2026-08..10 windows.

## Status update - Batch 298 (2026-11-14)

The follow-up trim was run and rejected. Removing `Step Index` and `Jump 25 Index` from the eight-symbol universe
(`InpSymbolsToTrade=Boom 1000 Index,Crash 1000 Index,Jump 75 Index,GBPUSD,AUDUSD,BTCUSD`) across the same five cold
windows lowers the mean and raises the variance: six-symbol mean **+4.740%**, sd **3.21 pp**, t **3.31** against
eight-symbol mean **+5.345%**, sd **2.37 pp**, t **5.04**; paired **-0.605 pp**, sd 2.01 pp, t 0.67, 2 of 5 positive.
The two rows do lose 383 USD across those windows (Step -151.42, Jump 25 -231.60 over 150 closes) yet removing them
concentrates the book further into `Crash 1000` (`08.01`: 114 closes -> 94, displacement into `Jump 75` 108 -> 125).
Conclusion: portfolio-level contribution is not the sum of per-symbol nets; the eight-symbol universe stands and no
input changed.

- [x] Finish the trim: the last two negative rows measured against the eight-symbol baseline (Batch 298, rejected).
- [ ] Next lever: per-symbol risk cap that binds on **lot size**, not at the entry gate. `GetSymbolRiskAllocation`
      (`Core\Risk\UnifiedRiskManager.mqh:1359`) = `maxDailyRiskPercent / activeSymbolCount * perfWeight` and is then
      lifted by the min-lot floor, so it never binds. This is the only remaining way to stop `Crash 1000` from taking
      every paying window while `Step`/`Jump 25` bleed inside it - and Batch 298 shows the alternative (deleting the
      small rows) is worse, so the cap must bind on size, not on admission.
- [ ] Cold-run verification that excluded chart symbols cannot trade on the new source; the old `InpAutoAddChartSymbol=false` experiment is obsolete because the input no longer exists.
- [ ] Daily ceiling 4% -> 6% (the 4 -> 8 step in Batch 295 was too coarse and lost 5.26 pp paired).
- [ ] Validity rule added this batch: a window counts only when the terminal log says `successfully finished` and the
      journal slice is exactly 10,080 samples starting at the ini `FromDate`. A network-cut run left 13,406 heartbeats
      and read -5.303% on an inherited base; the rerun gave +2.616%.
- [ ] Still never run: `Tools\backtest_b290_scalp2.ini`, `Tools\backtest_hal_w3/w4.ini`; `[ENGINE-CLOSE]` has never
      printed in a run; `backtest_report.htm` is never written, so the repository still has no MT5 profit factor,
      max drawdown or Sharpe; no live attach.

## Source follow-up - 2026-11-20

This section supersedes historical source-status wording above; it does not imply a successful MQL compile or broker test.

- **Fast-scalp async validation:** Fixed `OnAsyncOrderSent()` to validate its actual `sl`/`tp` parameters rather than undeclared names. This was a source-level compile blocker. MetaEditor verification remains outstanding.
- **Item 9:** The standard async executor now keeps unresolved requests quarantined and reconciles fill volume from broker deal history. Source path inspected; terminal/broker late-fill scenarios remain untested.
- **Item 10:** Fast-scalp admission now rebuilds exposure from current positions and active orders matching its magic, pricing downside to each live stop with OrderCalcProfit. Unresolved order reservations are added only when the broker book does not already represent that order or its live position; closes and zero-fill outcomes leave the budget through broker-state reconciliation rather than a guessed tier subtraction. Normal broker-visible exposure therefore reconstructs after restart. The brokerless timeout ledger and untracked-send fail-closed sentinel are still in-memory; MetaEditor and restart/late-fill runtime checks remain outstanding.
- **Items 11, 12 and 31:** Source now requires/injects `CTradeManager` for Spike Hunter and Grid Recovery execution; the ATR partial-close latch checks resulting broker volume. These are source fixes only. Grid Recovery and Spike Hunter remain dormant in the orchestrator.
- **Item 14:** Python prediction no longer performs a separate /health request before /predict; successful responses update bridge health, and cache freshness plus attempt backoff use monotonic GetTickCount(). Failed refreshes are throttled too, and stale/cold cache still fails closed. Refresh remains a synchronous WebRequest inside OnTimer() (configured default timeout 2 seconds), so terminal event-loop stalls are reduced but not resolved; this item stays open pending a genuinely nonblocking transport and runtime proof.
- **Item 15:** Exposure-cap exclusion of the candidate's own reservation is present for the reachable main and fast-scalp routes. The ATR/grid/spike gates are not evidence of active dispatch. Lifecycle pyramiding stays disabled.
- **Attribution:** Multi-contributor trades remain explicitly non-causal and excluded from strategy-dollar conclusions. Runtime attribution persistence/recovery and single-contributor attribution completeness are not proven by this source review.
- **Verification boundary:** Source reference checks and `git diff --check` are run for this follow-up. MetaEditor is unavailable, and the repository's header-test/sync scripts write outside this workspace; neither is run. No broker runtime, restart-recovery, responsiveness, or performance claim is made.

## Build follow-up - 2026-11-21

- **Sync source:** `sync_and_compile.ps1` now anchors `ProjectRoot` to `$PSScriptRoot`, so it syncs and compiles the active Tempo checkout instead of the clean `D:\TraeProjects\...` main checkout.
- **Compile fixes:** Replaced the C++-style pointer call in `FastScalpEngine.mqh` with MQL5 dot-call syntax and restored the missing `CDashBridgeTransport::LogState` implementation left declared and called after the transport split.
- **Verification:** Full sync plus `-All -KeepLog -MaxCompileWaitSec 900` completed; all eight root programs report 0 errors and 0 warnings. Edited headers match the MT5 mirror by SHA-256.
- **Still open:** No live/demo attach, broker runtime, or backtest was performed; compile success is not trading-performance evidence.

## Status update - Batch 299 (2026-11-23)

**Context.** This batch is the first cold distribution on the refactor. The measured binary was compiled from
**`09e18b0`** (committed 12:42:50) at ~12:35; the `origin/main` merge **`f0c1bea`** (13:39:26) landed mid-sweep and
brought `995cb3b` / `0c7260c` / `7c712fe` plus 153 files with MQL5 strategy changes, so HEAD is a **different
build** from the one the five windows describe. HEAD must be compiled and swept before any number is attributed
to it.

**Done:**
- [x] `.\sync_files.ps1` + `.\sync_and_compile.ps1 -All -KeepLog -MaxCompileWaitSec 900` -> `OVERALL SUCCESS`,
      0 errors / 0 warnings on all eight programs (root EA 285,687 ms).
- [x] `MultiStrategyAutonomousEA.set` parked as `.set.parked_b299`; compiled defaults verified in force.
- [x] Five cold windows on factory defaults, `Tools/backtest_b299_cold_w1..w5.ini`: **+3.728 / +9.178 / +1.988 /
      +6.724 / +3.970 %**, mean **+5.118%**, sd 2.83 pp, t 4.04, 5/5 positive, worst +1.988%.
- [x] Paired against Batch 297: mean **-0.227 pp**, sd 2.37, t -0.21, 2/5 positive -> the rebuild is P&L-neutral,
      not an improvement. No input changed, nothing shipped.
- [x] `RUNS_AND_GAINS.md` Batch 299, `changelogs.md` batch-299 entry, this status block.

**Open, in priority order:**
1. **Per-symbol risk cap that binds on lot size** - still the only untested lever. `GetSymbolRiskAllocation`
   never binds because the min-lot floor sets absolute size; Batch 298 proved deleting the small rows is worse
   than keeping them, so the cap must bind on size, not admission.
2. ~~**Restore per-trade logging.**~~ **Closed same day - nothing was broken.** Full-file counts: 472
   `[EXECUTION-RECEIPT]` / 472 `Trade Closed` in the merged `w1` journal, 404 / 403 in the `09e18b0` one. The
   prints are unconditional (`TradeManager.mqh:1428`, `StrategyMgrTradeFeedback.mqh:217`) and async sending is off
   by default (`TradeManager.mqh:293`). The earlier "dropped" claim was a tail-read error; attribution reconciles
   to the cent in both arms.
3. **Port-3000 guard in the harness.** `Tools\run_window.ps1` / `run_windows.ps1` should assert that
   `127.0.0.1:3000` is owned by `metatester64` before launching, and fail loudly otherwise - this batch lost two
   windows and three control runs to an unrelated Node dev server.
4. **Decide on the 3 remote commits.** Merging `995cb3b` (trace trade intents, harden execution gates) and
   `0c7260c` (risk governance) may conflict with the 242-file local refactor; if merged, the five windows must be
   re-run cold, because the measured baseline would no longer exist.
5. **`InpAutoAddChartSymbol=false` paired window** - still unmeasured; it is what re-injects `Volatility 75`
   closes into trimmed runs.
6. **4% -> 6% daily-ceiling step** - still unrun.
7. **`[ENGINE-CLOSE]` / `[SCALP-SIGNAL-REJECT]`** - compiled, never observed firing; the scalp-on window
   (`Tools\backtest_b290_scalp2.ini`, `XAUUSD,Step Index`) is still unrun.
8. **Demo attach** - the EA has still never been attached to a chart; sync + compile only.
9. **`.set` parks not restored**: `.parked_b291`, `.parked_b291b`, `.parked_b292`, `.parked_b297`,
   `.parked_b299`.
### Follow-up same day - Batch 299b: HEAD measured
- HEAD `f0c1bea` recompiled (`OVERALL SUCCESS`, 0 errors / 0 warnings, root EA 70,390 ms) and swept on the same
  five cold windows: **+0.317 / +9.178 / +1.988 / +6.724 / +3.970 %**, mean **+4.435%**, sd 3.57 pp, t 2.78,
  5/5 positive, worst +0.317%.
- Paired vs `09e18b0`: **-0.682 pp** (sd 1.53, t -1.00); four windows bit-identical, the delta concentrated in
  `08.01→08.08`. Mechanism: the merge added `[RISK-LOT-FLOOR]` (min-lot uplift, 1.10x, cap 3.00x) and
  `[INTENT-STAGE]`, and removed `[RISK-GATE-REJECT]`.
- Consequence for item 1 below: the "bind on lot size" idea now exists in code as an **uplift with a 3x cap**,
  not as a per-symbol risk cap. Whether a per-symbol cap is still worth building depends on measuring the
  uplift's behaviour first (`[RISK-LOT-FLOOR]` counts per window), which the current engine does log.
## Status update - Batch 300 (2026-11-23)

**Context.** The previous batch's "observability regression" was wrong, and the check that produced it (a 2 MB tail
read) was the bug. Full-file counts settle it, and the same full-file read is what made per-symbol attribution
reliable enough to name the August loss.

**Done:**
- [x] **Logging was never broken.** `472` `[EXECUTION-RECEIPT]` and `472` `Trade Closed ... Net Profit:` in the merged
      w1 journal (`404 / 403` in the `09e18b0` one). Prints are unconditional (`TradeManager.mqh:1428`,
      `StrategyMgrTradeFeedback.mqh:217`); the only path that skips a receipt is async sending, off by default
      (`TradeManager.mqh:293`). No source change, three docs corrected.
- [x] **Per-symbol attribution reconciles to the cent** in every window (each window's close-net equals its heartbeat
      delta). `08.01` pre-merge 256 fills / Crash +489.07 / 106 closes vs merged 215 / +222.44 / 74 closes - the
      three-point drop is payer throughput, not size, because the losing rows are identical (-190.36 vs -190.87).
- [x] **`[RISK-LOT-FLOOR]` measured, and it is inert as a lever.** 1,484 firing lines in merged w1 (Jump25 502,
      Jump75 490, Crash 273, GBPUSD 127, AUDUSD 66, Step 26); effective uplift 1.10x against a 3.00x cap that never
      binds. `InpMinLotRiskMultiplier=1.0` (uplift becomes a reject) on two cold windows: +0.740% vs +0.317%, and
      +1.425% vs +1.988% -> paired **-0.070 pp, t -0.14**. Default stays 3.0.
- [x] **The gate substitution is the real change:** `[RISK-GATE-REJECT]` 894/142/13 -> 5/0/99, with
      `[INTENT-STAGE] scaled_lot_not_tradeable` 1,637 replacing it. "Scaled lot untradeable" became "trade the broker
      minimum", so small rows now spend the 4% daily budget.
- [x] **The book, per symbol, five windows:** `Crash 1000` **+2,984.79 / 366 closes**, all other rows together
      **-767.07 / 755 closes** (Jump75 -146.82/452, Jump25 -290.02/191, Step -305.98/63, GBPUSD -3.85/35,
      AUDUSD -20.55/14).
- [x] **SHIPPED: `InpSymbolsToTrade = "Crash 1000 Index"`.** Five paired cold windows: **+10.837 / +15.786 / +2.614
      / +17.682 / +5.134 %** vs **+0.317 / +9.178 / +1.988 / +6.724 / +3.970 %**. Arm mean **+10.41%**, sd 6.53,
      t 3.56, 5/5; paired **+5.98 pp**, sd 4.94, **t 2.70**, 5/5; worst window +2.614%, worst drawdown 2.9%.
      Compile `OVERALL SUCCESS`, 0 errors / 0 warnings on eight programs.
- [x] **Default verified by omission**, `.set` parked as `.parked_b300b`, ini without `InpSymbolsToTrade`,
      `2026.08.01`->`08.07`: **10,000.00 -> 11,083.66, +10.837%**, 168 fills, min 9,997.40 / max 11,107.95 - identical
      to the arm to the cent, 171 `[RISK-LOT-FLOOR]` lines, all on `Crash 1000`.
- [x] **`InpAutoAddChartSymbol` no longer exists** in the merged tree, so universe authority is structural; the old
      chart-symbol exclusion item closes without a measurement.

**Open, in priority order (reordered by what the measurements say):**
1. **Out-of-regime for the single instrument - partly done.** Two windows outside the slice ran: July `07.01->07.08`
   **+4.075%** and June `06.04->06.08` **+4.208%** (truncated - `Crash 1000` history starts `06.04 01:57`, and the
   run's first heartbeat was already 10,470.48, so the "+9.110%" a naive 10,000 base gives is an artifact). Seven
   windows now: mean **+8.619%**, sd 6.15 pp, t 3.71, 7/7 positive. Month-length window `07.01->08.01` finished:
   **+50.565%** (10,000 -> 15,056.49), 836 closes, max drawdown **9.51%**, 22/31 positive days, mean +1.348%/day.
   Earlier history than `2026.06.04` is not available in this terminal.
2. **Does a second payer exist? - ANSWERED (Batch 300d): yes, `Boom 1000`, and it is now the factory book.**
   `Crash + Jump 75` was measured first and rejected (-6.28 / -4.17 / -4.88 pp on three cold windows; it dragged
   `Crash` itself net-negative in two). `Crash + Boom 1000` only fills once the send-time spread backstop is widened
   (`InpMaxEntrySpreadPoints` 15000 -> 25000; Boom quotes ~17,185 constantly and was vetoed 1,077 times/window),
   and with that amendment it ran **+14.714 / +20.169 / +6.871 / +19.809 / +16.135 %** against `Crash`-only
   **+10.837 / +15.786 / +2.614 / +17.682 / +5.134 %** - paired mean **+5.13 pp**, sd 3.41, **t 3.37**, **5/5**.
   Out of slice, July is **-2.00 pp**, so the row is 5-of-5 in-slice and 1-of-1 negative outside it. Control arm
   (`Crash`-only at 25000) reproduced the 15000 arm **to the cent** on two windows, so the wider gate is inert for
   the payer. Open here: a per-symbol spread override would let `Boom` fill without loosening the disaster-quote
   backstop for the whole book, and it is not built.
3. **Per-symbol cap at sizing** - status unchanged in *form* but now better understood: the code path is an uplift
   with a 3x cap, and the uplift is inert. Building a real cap means changing the formula, not the input.
4. **Port-3000 guard** - `Tools\run_window.ps1` already refuses to launch when anything owns `:3000` (it enumerates
   the owning process and throws), so the guard exists; what it does not do is clear an unrelated Node dev server.
   That is deliberate - a harness that kills processes is worse than one that stops. The `b300_*.ps1` drivers kill
   only `node` holders, and one was killed again at 23:04:25 this batch. Remaining work, if any, is the standing
   question of whether that dev server should move off 3000.
5. **`InpMaxDailyRisk` 4% -> 6%** - unrun; now interacts with a single-symbol book, so re-measure before trusting.
6. **`[ENGINE-CLOSE]` / scalp-on window** (`Tools\backtest_b290_scalp2.ini`) - still unrun.
7. **Demo attach** - the EA has still never been attached to a chart.
8. **`.set` parks not restored**: `.parked_b291`, `.parked_b291b`, `.parked_b292`, `.parked_b297`, `.parked_b299`,
   `.parked_b300`, `.parked_b300b`.
## Status update - Batch 300d (2026-11-24)

**Context.** Batch 300 closed the book to one payer and left the diversifier question open. This batch measured
both candidate rows rather than guessing, and shipped the one that pays.

**Done:**
- [x] **`Crash + Jump 75` measured and rejected.** Three cold windows against `Crash`-only on the same binary:
      +4.553 / -1.559 / -0.805 % vs +10.837 / +2.614 / +4.075 % -> paired **-6.28 / -4.17 / -4.88 pp**. The
      mechanism is throughput, not the row's own P&L: payer closes fell from 168/164/183 to 92/94/96, and `Crash`
      went net-negative in two of the three windows.
- [x] **The first `Crash + Boom` arms were dead on a gate, not on signal.** Three windows reproduced `Crash`-only
      **to the cent** with zero Boom closes; the row was scanned (~50,000 journal lines) and vetoed every entry by
      `hard_spread_cutoff` (`spread_points=17185.0 > 15000.0`, 1,077 vetoes/window). `InpSymbolMaxSpreadPoints`
      (universe filter) was the wrong knob; the gate is `MathMax(hardSpreadCutoffPoints, maxEntrySpreadPoints)`
      (`EAOrchestrator.mqh:1956`), i.e. `InpMaxEntrySpreadPoints`.
- [x] **`InpMaxEntrySpreadPoints=25000` with `Crash` only (control)** reproduced the 15,000 arm to the cent on
      `08.01` (+10.837% / 168 fills / min 9,997.40 / max 11,107.95) and `09.01` (+2.614% / 164 / 9,755.57 /
      10,261.75). The loosening is inert for the payer, so the paired deltas belong to Boom.
- [x] **`Crash + Boom` @25000, five windows:** **+14.714 / +20.169 / +6.871 / +19.809 / +16.135 %**; Boom's own net
      +705.38 / +376.54 / +623.66 / +764.13 / +909.36 on 31-44 closes. Paired **+3.88 / +4.38 / +4.26 / +2.13 /
      +11.00 pp**, mean **+5.13 pp**, sd 3.41, **t 3.37**, **5/5**. Out of slice `07.01` is **-2.00 pp** (Boom
      -104.62 / 35 closes).
- [x] **SHIPPED:** `InpSymbolsToTrade = "Crash 1000 Index,Boom 1000 Index"` and `InpMaxEntrySpreadPoints = 25000.0`
      in `Core\Config\SharedEAInputs.mqh`, both with the measured block above them. Compile `OVERALL SUCCESS`,
      0 errors / 0 warnings on all eight programs.
- [x] **Default verified by omission:** `.set` parked as `.parked_b300d`, ini carrying neither input, cold
      `08.01->08.07`: **+14.714%** (10,000 -> 11,471.44), 165 fills, Boom 31 closes +705.38, Crash 134 closes
      +766.06, min 9,966.75 / max 11,485.28 - the arm to the cent.

**Open, in priority order:**
1. **Per-symbol spread override.** The shipped 25,000 cap admits Boom by loosening the send-time disaster-quote
   backstop ~67% for the whole book. A per-symbol limit (`Boom` ~17,185 allowed, everything else unchanged) would
   buy the same fills with no global loosening. Not built; no code change measured.
2. **Boom outside the slice.** Only July disagrees (-2.00 pp). Boom's history starts `2026.06.04`, so more
   out-of-slice windows are possible but few; `06.x` and `10.13->10.20` are the candidates.
3. **Crash + Boom on the month-length window** (`07.01->08.01`, where the July week loses) - unrun, and it is the
   one window that would show whether Boom's July loss compounds or averages out.
4. **`InpMaxDailyRisk` 4% -> 6%** - still unrun, now on a two-row book.
5. **`[ENGINE-CLOSE]` / scalp-on window** (`Tools\backtest_b290_scalp2.ini`) - still unrun.
6. **Demo attach** - the EA has still never been attached to a chart.
7. **`.set` parks not restored**: `.parked_b291`, `.parked_b291b`, `.parked_b292`, `.parked_b297`, `.parked_b299`,
   `.parked_b300`, `.parked_b300b`, `.parked_b300ab`, `.parked_b300ab2`, `.parked_b300be`, `.parked_b300c`,
   `.parked_b300m`, `.parked_b300d`.
- **Harness note:** this batch lost the machine three times (~13:35, ~16:41, ~21:35) and one window with it; a
  killed run leaves its journal truncated mid-window, so a window counts only when the terminal log says
  `successfully finished` and the heartbeat slice is 10,080 samples starting at the ini `FromDate`. `booment_w2`
  also showed the pacing is not linear - `processing` went 0->48 % over 71 minutes and finished at 95, because
  history synchronisation (11 min) precedes the clock.

## Status update - Batch 300e (2026-11-25)

**Context.** Batch 300d left a priority list of seven items behind after shipping the two-row book. Six were
measurable in code and backtests; item 6 (demo attach) is not this batch's work. This batch ran the six.

**Done:**
- [x] **1. Per-symbol spread override built and shipped.** New `InpSymbolHardSpreadOverridesCsv`
      (`"Boom 1000 Index=25000"`), global `InpMaxEntrySpreadPoints` back to 15000. Reproduced the 300d 25,000 arm
      **to the cent** on `08.01`: +14.714% / 11,471.44 / 165 fills / Boom +705.38 on 31 closes. Two gates had to
      learn it — the pre-consensus cutoff in `EAOrchestrator.mqh` *and* the send-time `TradeMgrPreflight.mqh:127`
      path via `TradeManager::EffectiveEntrySpreadLimit`; opening only the first still produced 0 Boom closes.
      The duplicated input->config block in `MultiStrategyAutonomousEA.mq5` also needed the field (audit item 35).
- [x] **2. Boom outside the slice, two fresh windows with fresh controls.** `09.22->09.29`: +36.017% (171 fills,
      Boom +1,407.71 / 42) vs `Crash`-only +15.353% (165) -> **+20.66 pp**. `10.13->10.20`: +9.171% (169, Boom
      +178.87 / 28) vs +8.368% (175) -> **+0.80 pp**. July week remains **-2.00 pp**. Out-of-slice mean **+6.49 pp**,
      sd 12.36, 2/3 — direction holds, size does not.
- [x] **3. Month-length window `07.01->08.01` run.** **+66.520%** (10,000 -> 16,652.05), 834 fills, Boom
      +2,758.92 / 153 closes, Crash +3,876.80 / 680, min 9,986.33 / max 17,226.43, 99 min wall. No 31-day
      `Crash`-only control, so this is not attribution; it does show the losing July week does not compound.
- [x] **4. `InpMaxDailyRisk` 4.0 -> 6.0 and `InpMaxPortfolioRisk` 12.0 -> 18.0 shipped.** Four cold paired windows
      vs 4/12: **+6.386 / +2.899 / +3.249 / +11.622 pp**, mean **+6.04 pp**, sd 4.04, **t 2.99**, **4/4**. The 4% arm
      was refusing entries (`[RISK-DAILY-LIMIT] ... effective=3.97% + new=1.00% >= limit=4.00%`); at 6% they became
      Boom closes. Contradicts Batch 294's **-5.26 pp** on the eight-symbol book — the lever changed meaning with
      the book.
- [x] **5. Scalp-on window run and answered.** `InpEnableScalpEngine=true` on the two-row book: **+14.714%**,
      165 fills, identical to scalp-off to the cent. 0 `[SCALP-CLOSE]`; 19,897 `[SCALP-SIGNAL-REJECT]`, all
      `gate=spread_vs_atr`. Dead on synthetic spreads; no input changed.
- [x] **7. Parked `.set` files restored.** All 15 `MultiStrategyAutonomousEA.set.parked_*` backups (`b291` through
      `b300e`) deleted; the Tester profile carries one `.set`.
- [x] **Compile and default witness.** `OVERALL SUCCESS`, 0 errors / 0 warnings, eight programs. Omission ini
      (`InpQuorumProfile` / `InpMinLiveVoters` / `InpMaxRiskPerTrade` only) cold `08.01`: **+21.100%**,
      12,110.05, 193 fills, Boom 42 closes +1,131.48, Crash 151 +978.57 — the 6/18 arm to the cent.
- **Harness note:** a duplicate key in a MT5 `.ini` takes the **first** value. One `risk6_w1` window was a null
  arm (4.0 listed before 6.0, journal printed `limit=4.00%`) and had to be de-duplicated and re-run.

**Open, in priority order:**
1. **Demo attach** — unchanged, and by agreement this one is not mine this batch: the EA has still never been
   attached to a chart.
2. **Boom's out-of-slice variance** — 2/3 positive with sd 12.36 pp. The remaining candidates are `06.x` (Boom's
   history starts `2026.06.04`) and more October sub-windows; a 31-day `Crash`-only control for July is still
   missing, so the month window stays unattributed.
3. **Risk ceiling beyond 6%** — 8/24 was never run on the two-row book; the 6/18 arm has four windows and a
   t of 2.99, so a 7.5/22.5 or 8/24 arm is the next natural single-variable step, with the same paired protocol.
4. **Scalp** — needs a `spread_vs_atr` gate change (or a non-synthetic universe) before it is a lever at all;
   `Tools\backtest_b290_scalp2.ini` as written (`XAUUSD,Step Index`) is still unrun.
5. **Process hygiene** — every `.ini` in `Tools\` should be duplicate-key checked before a run; the chain scripts
   cannot detect a null arm by design (a neutral result looks like a neutral result).
6. **`[ENGINE-CLOSE]`** still compiles but has never printed in a run; `Tools\backtest_hal_w3/w4.ini` remain
   unfinished; `test_headers.ps1 -AllInOne` has not been re-run since Batch 282.

