# Remaining Work

Status key: **Open** = not started or only partly addressed. **Verify** = code was changed but not compiled or checked against broker/runtime behavior. Nothing in this list has been compiled in MetaTrader 5 yet.

---

## Data and model validity

### 1. H11: notebook split still leaks labels
- **What:** The notebook's base train/validation/test split is a plain ratio split with no purge. Labels look `vertical_bars` bars ahead, so samples near each boundary use prices that belong to the next split.
- **Where:** The base data split in `Multi_Mt5_Colab_Notebook.ipynb`. Its CPCV helper was fixed, but this split was not.
- **Files:** `Python/Multi_Mt5_Colab_Notebook.ipynb`
- **Fix idea:** Split by time index, then drop any training sample whose label end index is at or after the first validation or test index. Reuse the label-end logic from `data_pipeline.py`. Do not hand-edit the JSON. Use a script or `nbformat`, then check that the JSON loads.

### 2. CPCV purge uses an approximate horizon
- **What:** `label_horizon_ns()` estimates the horizon as median bar spacing times `vertical_bars`. It is wrong when timestamps have session gaps, weekends, or irregular spacing.
- **Where:** `label_horizon_ns`, `purge_embargo`, `cpcv_folds`, and `run_cpcv` in `validate_model.py`.
- **Files:** `Python/validate_model.py`, `Python/data_pipeline.py`, `Python/train_model.py`, `Python/write_colab.py`
- **Fix idea:** Have the pipeline return a `label_end_ts` array (timestamp of the bar at `index + vertical_bars`, or the actual barrier-hit bar). Pass it into CPCV and purge where `label_end_ts >= test_start` and `sample_ts <= test_end`. Remove the median-spacing heuristic.

### 3. Standalone CPCV in `mql5_v2.py` is unreviewed
- **What:** The stop-first labels and bar-horizon purge were added here, but this file's own CPCV implementation has not been checked for purge correctness.
- **Where:** The CPCV section of `mql5_v2.py`.
- **Files:** `Python/mql5_v2.py`
- **Fix idea:** Either delete the duplicate CPCV and import the one in `validate_model.py`, or apply the same label-end purge.

### 4. Triple-barrier edge cases and index alignment
- **What:** Labels near the end of the data may lack a full horizon. Prepared sequences must map to label indices exactly.
- **Where:** Label generation and sequence preparation in `data_pipeline.py`.
- **Files:** `Python/data_pipeline.py`
- **Fix idea:** Drop samples with fewer than `vertical_bars` future bars. Add an assertion that `len(X) == len(y) == len(label_index)`. Confirm the stop-first tie-break is used in every label path.

### 5. ONNX feature and scaler parity
- **What:** Features and scalers used at training time must match what the EA computes at inference. This was in the original audit and has not been re-checked.
- **Where:** Feature generation in Python and the MQL5 feature builder that feeds the ONNX model.
- **Files:** `Python/data_pipeline.py`, `Python/train_model.py`, the MQL5 feature code under `AIModules/`
- **Fix idea:** Export the scaler parameters with the model. Load them in MQL5 instead of duplicating constants. Add a parity check script that compares Python and MQL5 feature vectors on a sample bar.

### 6. Walk-forward realism
- **What:** Walk-forward windows must not reuse future data for normalization or hyperparameter choice.
- **Where:** Normalization fit and split logic in `train_model.py` and `validate_model.py`.
- **Files:** `Python/train_model.py`, `Python/validate_model.py`
- **Fix idea:** Fit scalers on the training fold only. Confirm each walk-forward step retrains from scratch on past data only.

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

### 9. Standard async partial fills and no-history path
- **What:** After timeout, if history never shows the order, the tracker logs for manual review and then drops tracking. A later fill can escape reconciliation.
- **Where:** Timeout reconciliation in `TradeMgrAsyncExecutor.mqh` (`ASYNC_RECONCILE_MAX_ATTEMPTS`, `CancelOrderRemainder`, `RemovePendingAt`).
- **Files:** `Core/Trading/TradeMgrAsyncExecutor.mqh`, `Core/Trading/TradeMgrPreflight.mqh`, `Core/Trading/TradeTypes.mqh`
- **Fix idea:** Move unresolved orders into a quarantine list that is rechecked on the timer. Do not remove them until the broker shows a final state. Sum fill volume from `HistoryDealGetDouble(DEAL_VOLUME)` filtered by `DEAL_ORDER`, and compute average price from the deals rather than the request price.

### 10. Fast-scalp risk budget can be orphaned
- **What:** On timeout, the pending record is removed while the budget stays reserved. A late fill after removal is not registered by `OnDealConfirmed()`.
- **Where:** `FastScalpAsyncTracker` timeout and `OnDealConfirmed()`.
- **Files:** `Core/Scalp/FastScalpAsyncTracker.mqh`
- **Fix idea:** Keep a separate reserved-budget ledger keyed by order ticket. `OnDealConfirmed()` looks up the ledger first, registers the position, and releases budget only on a final zero-fill outcome.

### 11. Spike Hunter may bypass the shared risk path
- **What:** The live raw `CTrade` branch can run when `m_tradeManager` is null, which skips the unified risk gate.
- **Where:** The send path and the initialization in `SpikeHunterExecutor.mqh`.
- **Files:** `Core/Scalp/SpikeHunterExecutor.mqh`, `Core/Orchestration/EAOrchestrator.mqh`
- **Fix idea:** Remove the raw `CTrade` send. Route all orders through `TradeManager` and `RiskValidationPipeline`. If the manager is null, refuse to trade and log an error.

### 12. ATR scalp partial close latch is not tied to broker outcome
- **What:** The latch is set when `CTrade` returns true. That only means the request was accepted, not that volume was closed.
- **Where:** Partial-close block in `ATRScalpExit.mqh`.
- **Files:** `Core/Scalp/ATRScalpExit.mqh`
- **Fix idea:** Check `ResultRetcode()` against `TRADE_RETCODE_DONE` (and `TRADE_RETCODE_DONE_PARTIAL`). After the send, read `PositionGetDouble(POSITION_VOLUME)` and set the latch only when the reduced volume matches the request. Clear the latch if the position is gone.

### 13. Margin projection on hedging and netting accounts
- **What:** The projected margin check adds `marginRequired` to current margin. Hedging and netting accounts can differ.
- **Where:** `projectedMargin` in `RiskMarginHealth.mqh`.
- **Files:** `Core/Risk/RiskMarginHealth.mqh`
- **Fix idea:** For netting accounts, subtract margin already held on the same symbol in the opposite direction before adding. Confirm `OrderCalcMargin` is used for `marginRequired`. Add a unit-style check in the code path comment-free by keeping the logic in one helper.

### 14. Python bridge blocks the tick path on cache miss
- **What:** `WebRequest` runs synchronously when the cache expires (new bar or 10 seconds).
- **Where:** `PythonBridgeAIStrategyAdapter.mqh` predict path.
- **Files:** `Core/Strategy/PythonBridgeAIStrategyAdapter.mqh`, `Core/Orchestration/EAOrchestrator.mqh`
- **Fix idea:** Refresh predictions from `OnTimer()` and have the tick path only read the cache. On a cold cache, return no signal. Add a request timeout and a staleness limit.

---

## Risk and exposure

### 15. Exposure caps must cover every entry path
- **What:** Portfolio, per-symbol, and total caps must apply to every entry route, including scalp and spike paths. The cold-start bypass is removed, but cap coverage has not been confirmed across all routes.
- **Where:** `RiskValidationPipeline.mqh` and `PortfolioRiskManager.mqh`.
- **Files:** `Core/Risk/RiskValidationPipeline.mqh`, `Core/Risk/PortfolioRiskManager.mqh`, `Core/Scalp/ATRScalpEntry.mqh`, `Core/Scalp/SpikeHunterExecutor.mqh`, `Core/Scalp/FastScalpAsyncTracker.mqh`
- **Fix idea:** Create one `ValidateExposure()` call used by every entry. It checks per-symbol count, total count, and total risk percent against configured limits.

### 16. Opposing strategy votes need arbitration and tests
- **What:** When strategies vote in opposite directions, the arbitration result is not fully covered.
- **Where:** Vote aggregation in `EAOrchestrator.mqh` and the consensus code.
- **Files:** `Core/Orchestration/EAOrchestrator.mqh`, `Core/Management/ConsensusWeightingConfig.mqh`
- **Fix idea:** Define one rule: a tie or conflict means no trade. Add a log line that records both sides and their weights.

### 17. Local stop, RR, and spread guards per strategy
- **What:** Strategies should reject trades with an invalid stop, poor reward-to-risk, or wide spread before reaching the risk gate. This has not been audited for every strategy.
- **Where:** Each strategy's signal function under `Strategies/`.
- **Files:** Every file in `Strategies/` that emits a signal, starting with `FVGScalperStrategy.mqh`, `BreakerBlockStrategy.mqh`, `RangeCompressionBreakout.mqh`, `MeanReversionStrategy.mqh`, `NYOpenGapStrategy.mqh`
- **Fix idea:** Add a shared helper `IsSignalTradable(entry, stop, target, spread)` in `Core/` and call it from each strategy.

### 18. NY open gap DST and session boundaries
- **What:** The GMT-to-broker offset is taken from the current time and reused for historical bars. DST transition weekends and seasonal broker offsets can shift the session boundary by an hour.
- **Where:** `NYOpenGapStrategy.mqh`, the offset calculation and the prior-close lookup.
- **Files:** `Strategies/NYOpenGapStrategy.mqh`
- **Fix idea:** Compute the US DST state for each candidate date (second Sunday of March to first Sunday of November, 2:00 local), and compute the broker offset per candidate using the bar's own time rather than `TimeCurrent()`.

### 19. Crisis limits and hardcoded thresholds
- **What:** The ATR crisis ratio thresholds are already EA inputs (`InpAtrCrisisRatioThreshold*`), so they are done. Remaining fixed literals still need to be found and moved to inputs.
- **Where:** Search for numeric literals in risk and crisis code.
- **Files:** `Core/Config/OrchestratorConfig.mqh`, `Core/Risk/*.mqh`, `MultiStrategyAutonomousEA.mq5`, `MultiStrategyTestingEA.mq5`, and matching `.set` files
- **Fix idea:** Add inputs with the current values as defaults. Update the `.set` files. Note that removing the unused profit-floor key already changed `.set` mapping.

---

## Configuration

### 20. Live config parser needs compile and edge-case checks
- **What:** `ValidateLiveConfigDocument` and its helpers are declared after use. `JsonExtractValue()` is still a simple parser, so duplicate keys, nested keys, and some value forms are not handled.
- **Where:** `LiveConfigReloader.mqh`.
- **Files:** `Core/Config/LiveConfigReloader.mqh`, `Core/Orchestration/EAOrchestrator.mqh` (`ApplyLiveConfigOverrides`)
- **Fix idea:** Move helper declarations above the class, or make them class methods. Reject duplicate keys. Use a single tokenizer for the whole file. Test with MetaEditor compile, not behavior tests, unless the user says otherwise.

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

### 31. Grid recovery bypasses TradeManager and uses a hardcoded slippage
- **What:** `GridRecoveryExecution` sends orders through its own `CTrade` and falls back to a fixed 50-point deviation when `m_tradeManager` is NULL. Position closes also use the raw `CTrade` with no retry or reconciliation.
- **Where:** `GridRecoveryExecution.mqh` lines 111-131 (send) and 227-231 (close).
- **Files:** `Core/Scalp/GridRecoveryExecution.mqh`, `Core/Orchestration/EAOrchestrator.mqh`
- **Fix idea:** Route sends and closes through `CTradeManager` as the only path. Refuse to trade when it is NULL, and take slippage from `GetDynamicSlippage`.

### 32. Market structure breaks read the forming bar
- **What:** Consolidation breakout checks use `iHigh` and `iLow` at shift 0, which is the forming bar. Other break classification in the same file was moved to shift 1 for this reason, so this check flips tick by tick.
- **Where:** `MarketStructureAnalyzer.mqh` lines 333-348.
- **Files:** `Strategies/UnifiedICTFiles/MarketStructureAnalyzer.mqh`
- **Fix idea:** Use shift 1 for `currentHigh` and `currentLow`, matching the comment at line 428.

### 33. Support and resistance touch counts include the forming bar
- **What:** `touches` is counted over 100 bars from shift 0, so the count changes with every tick.
- **Where:** `SupportResistanceDetector.mqh` lines 474-492.
- **Files:** `Strategies/SupportResistanceFiles/SupportResistanceDetector.mqh`
- **Fix idea:** Start the copy at shift 1. Recompute touches only on a new bar.

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

### 37. Mojibake in source comments and log strings
- **What:** Em dashes and arrows were saved in a different encoding and now appear as `�?`. This is visible in one log string.
- **Where:** `ATRScalpEntry.mqh` line 58; `SpikeHunterExecutor.mqh` lines 51 and 116; `VolatilityEngine.mqh` lines 490, 588 and 611.
- **Files:** Those four files
- **Fix idea:** Replace the characters with ASCII (`-` and `->`) and save the files as UTF-8.

### 38. Comment references to batch and issue IDs
- **What:** Comments such as `Batch 156`, `Batch104-C1`, `L10-014` and `L7-015` reference past work and will rot as the code changes.
- **Where:** Many files, for example `SupportResistanceDetector.mqh`, `LiquidityDetector.mqh` (line 789), `GridRecoveryExecution.mqh` (line 28), `SpikeHunterExecutor.mqh`.
- **Files:** Search with `Batch\s*\d+|L\d+-\d+`
- **Fix idea:** Remove the IDs and keep only the reason the code is written that way.

---

## Additional findings (third pass)

### 39. Dashboard server is exposed on all interfaces without auth
- **What:** `SERVER_HOST` is `0.0.0.0`, and `POST /state`, `POST /api/control/command`, and `POST /api/control/ack/{id}` have no authentication. Anyone on the same network can push fake state into the dashboard or queue commands.
- **Where:** `config.py` line 4; `dashboard_server.py` lines 89-116 and 183-200.
- **Files:** `Dashboard/server/config.py`, `Dashboard/server/dashboard_server.py`, `Core/Utils/DashBridgeTransport.mqh`
- **Fix idea:** Default the host to `127.0.0.1`. Require a shared token from the environment in an `X-Api-Key` header on all write routes, and send it from `CDashBridgeTransport`. Keep `allow_credentials` off unless it is needed.

### 40. Dashboard commands are acknowledged but never executed
- **What:** `CDashBridgeTransport` polls `/api/control/commands`, logs `[DASHBOARD-CMD]`, and POSTs an ack for every command. There is no handler, so a command is reported as handled when nothing happened. The ack also happens before any validation.
- **Where:** `DashBridgeTransport.mqh` lines 263-310.
- **Files:** `Core/Utils/DashBridgeTransport.mqh`, `Dashboard/server/dashboard_server.py`
- **Fix idea:** Either delete the command channel, or add a whitelist of command types (for example pause, resume) that route into existing orchestrator methods. Ack only after the handler returns a result, and send that result with the ack. Reject unknown types with an error ack.

### 41. ZMQ heartbeat branch is unreachable and the server can shut itself down while idle
- **What:** The EA's heartbeat is an HTTP `GET /heartbeat` (`PyBridgeHealth.mqh` line 127). The ZMQ `type == "heartbeat"` branch comes after the `features` check, so a heartbeat without `features` is rejected. `_run_zmq` also calls `shutdown()` when no request has arrived for `heartbeat_timeout` seconds, and with `--disable-http` nothing refreshes the timestamp during quiet periods.
- **Where:** `zmq_server.py` lines 545-582 and 600-605 (`shutdown` call at 549); the HTTP heartbeat at line 271.
- **Files:** `Python/zmq_server.py`, and the ZMQ client if one exists in MQL5 (no ZMQ client was found in this repo)
- **Fix idea:** Move the heartbeat check above the `features` check. Have the heartbeat be a real client message, or drop the idle shutdown and rely on the HTTP heartbeat. Confirm which transport the EA uses before changing the timeout.

### 42. Blocking Sleep calls remain on indicator and cache paths
- **What:** `TrendADX.mqh` sleeps 50 ms on a retry, `MarketAnalysisIndicators.mqh` sleeps 50 ms per retry, and `MarketAnalysisMetrics.mqh` sleeps 10 ms. `ScalpSignalCache.mqh` sleeps 1500 ms and 1000 ms per symbol during load. `SafeCopyBuffer.mqh` already removed its Sleep for the same reason, so the policy is inconsistent.
- **Where:** `TrendADX.mqh` line 265; `MarketAnalysisIndicators.mqh` lines 377-378; `MarketAnalysisMetrics.mqh` line 105; `ScalpSignalCache.mqh` lines 161 and 189.
- **Files:** `Core/Engines/TrendADX.mqh`, `Core/Engines/MarketAnalysisIndicators.mqh`, `Core/Engines/MarketAnalysisMetrics.mqh`, `Core/Scalp/ScalpSignalCache.mqh`
- **Fix idea:** Remove Sleep from any path that can run from `OnTick`. Return "not ready" and retry on the next tick. Move the `ScalpSignalCache` waits into `OnInit` with a bounded total budget, or check whether it is reached only on init.

### 43. ATR scalp entry sends orders through a raw CTrade
- **What:** `ATRScalpEntry.mqh` opens positions with `trade.Buy`/`trade.Sell`, so it does not use the central send path. It is not covered by the spike or grid items.
- **Where:** `ATRScalpEntry.mqh` lines 195-200.
- **Files:** `Core/Scalp/ATRScalpEntry.mqh`, `Core/Trading/TradeManager.mqh`
- **Fix idea:** Route the entry through `CTradeManager` and `RiskValidationPipeline`, the same as item 11, and remove the raw `trade` object from this path.

---

## Additional findings (fourth pass)

### 44. Missing tick data returns zero risk or zero size instead of refusing
- **What:** `CUnifiedRiskManager` falls back to 0.0 risk when `SYMBOL_TRADE_TICK_VALUE` or `SYMBOL_TRADE_TICK_SIZE` is missing, and its own comment says this "charges no risk". `PositionSizer` returns 0.0 for the same missing values. A zero-risk trade passes the risk gate, and a zero size may be handled differently by each caller.
- **Where:** `UnifiedRiskManager.mqh` lines 1642-1646; `PositionSizer.mqh` lines 688-696.
- **Files:** `Core/Risk/UnifiedRiskManager.mqh`, `Core/Risk/PositionSizer.mqh`, and the callers of both
- **Fix idea:** Return a sentinel (for example a negative value or a bool with an error code) and make the risk gate reject the trade. Log the symbol and the missing field. Cache the last valid tick data per symbol for short gaps rather than using zero.

### 45. mql5_v2.py installs dependencies through an unquoted shell string
- **What:** The `pip install` strings contain `torch>=2.1.0` and similar specs and run with `shell=True`. The shell treats `>` as an output redirect, so the version constraints are dropped and files named like `=2.1.0` are created in the working directory. The install also runs as an import-time side effect of the script.
- **Where:** `mql5_v2.py` lines 27-29.
- **Files:** `Python/mql5_v2.py`, and any generated copy in `Python/write_colab.py`
- **Fix idea:** Move the requirements to a pinned `requirements.txt` or a list passed to `subprocess.check_call([sys.executable, "-m", "pip", "install", ...])` without `shell=True`. Keep installs out of module import and check that the requirements file loads.

### 46. Position-count caps may count positions this EA does not own
- **What:** `PositionSizer` counts every open position on the account, and the comment says this is intentional. Other loops that count `PositionsTotal()` do not show a magic-number filter in the lines reviewed. Manual or other-EA positions could consume the EA's caps, or the cap could be enforced on the wrong set.
- **Where:** `PositionSizer.mqh` lines 780-782; the count loops in `PortfolioRiskManager.mqh` (around 277, 350, 468, 510) and `RiskValidationPipeline.mqh` (around 1020). `RiskCircuitBreaker.mqh` line 390 already filters by magic.
- **Files:** `Core/Risk/PositionSizer.mqh`, `Core/Risk/PortfolioRiskManager.mqh`, `Core/Risk/RiskValidationPipeline.mqh`, `Core/Risk/CorrelationEngine.mqh`
- **Fix idea:** Decide one ownership rule. Use `IsMagicOwned()` for EA caps, and keep a separate account-wide check only where it is intended. Document the rule in one helper.

### 47. Retraining request file is truncated before it is rewritten
- **What:** The request log is opened with `FILE_WRITE`, which truncates it, and then the kept rows are written back. A crash or write failure between those steps loses the pending retraining requests.
- **Where:** `AIPerformanceFeedback.mqh` lines 829-830 (rewrite) and 774-776 (append).
- **Files:** `Core/AI/AIPerformanceFeedback.mqh`
- **Fix idea:** Write the trimmed rows to a temp file and replace the original, the same approach as `crash_recovery_helpers.mqh`. Check the `FileMove` result and keep the original on failure.

---

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

- **The Batch 289 build was measured, and the repairs alone were not a gain.** Cold, same window and inputs as the Batch 288 baseline (2026.09.01-> 9.08, V75 M15, Model=1, deposit 10,000, InpQuorumProfile=1, InpMinLiveVoters=1): **-258.77 (-2.588%) on 2,265 fills**, against **+98.29 (+0.983%) on 849 fills** for the previous build. -3.57 pp and +167% fills, far outside the 0.92 pp cross-window noise.
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
- **Known deviation:** `InpAutoAddChartSymbol = true` re-injects the chart symbol, so even a trimmed universe takes 2-4 `Volatility 75` closes. Turn that input off only with a paired run - every measured window had it on.
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
- **Open, next in line:** a 4% -> 6% daily step (the 4 -> 8 jump may be too coarse to reveal a real optimum); a per-symbol cap that binds on the lot rather than the entry (Batch 286/287 proof still points there); `InpAutoAddChartSymbol=false` paired run; `[ENGINE-CLOSE]` never fired; `Tools\backtest_b290_scalp2.ini` unrun; `backtest_report.htm` never written so still no MT5 profit factor / drawdown / Sharpe; no live attach; items 15/43/19/20/8/41/47 unchanged.
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
- [ ] `InpAutoAddChartSymbol = true` re-injects the chart symbol, so a trimmed run still takes 2-6 `Volatility 75`
      closes (5 in `08.08`, 2 in `08.01`); never tested with it off.
- [ ] Still no live attach; `[ENGINE-CLOSE]` still never observed; `backtest_report.htm` still never written, so no
      MT5 profit factor / drawdown / Sharpe anywhere in the repository.
