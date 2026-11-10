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
- **What:** Some thresholds are fixed in code. They should be inputs so they can be tuned per account.
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
- **Fix idea:** Check `git status` before any further work and confirm that only the intended files differ.

---

## Suggested order
1. Items 1 to 6 (model validity; these affect every reported metric).
2. Items 7 and 8 (AI label and weight logic).
3. Items 9 to 14 (execution safety).
4. Items 15 to 19 (risk and exposure).
5. Item 20 (config parser).
6. Items 21 to 23 (compile, recovery, git state).
