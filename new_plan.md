# Multi-Strategy EA: Critical Issue Analysis & Fix Plan

## Executive Summary

Your EA generates signals but they are **blocked at the pipeline stage**, not execution. Root cause: **Pipeline confidence filter rejects all signals** because:
1. Base confidence threshold = 0.60 (effective = 0.65-0.69 with regime cap)
2. All generated signals are 0.37-0.54 confidence (too low)
3. REGIME_NONE blocks signals further

Additionally:
- **AI modules have functional bugs** preventing them from contributing to confidence
- **Timeframe coordination issues** prevent proper multi-timeframe consensus
- Once you fix the pipeline/confidence threshold and AI bugs, trades should execute

---

## Evidence from Logs (2026.03.07)

```
[CONSENSUS-DIAG] ...| generated=1 | after_pipeline=0 | after_quorum=0
[Pipeline] ConfidenceFilter: FAILED - REGIME_NONE | Confidence 0.54 below minimum 0.60 (effective: 0.69)
[CONSENSUS-ROOT] dominant=raw_none=100.0% (all 7 strategies produce NONE)
```

**Key observation**: No `[TRADE-*]`, `[SIGNAL-*]`, or `[RISK-*]` logs = trades never reach execution layer. They die at pipeline stage.

---

## Root Causes (3 Areas)

### 1. Pipeline Confidence Threshold Too Aggressive (IMMEDIATE BLOCKER)
- **Location**: `Core/Pipeline/UnifiedSignalPipeline.mqh` ~ line 800-850 (ConfidenceFilter)
- **Issue**: 
  - Base threshold 0.60 + regime cap applied = effective 0.65-0.69
  - Strategies generating signals with 37-54% confidence
  - Pipeline rejects all as "below minimum"
- **Impact**: Zero trades execute because signals are filtered before risk gate
- **Fix approach**: 
  - Lower base confidence threshold to 0.45-0.50 OR
  - Reduce regime cap penalty OR
  - Make regime handling non-blocking (warn but allow)

### 2. AI Modules Don't Work (Prevents Confidence Boost)
AI modules could increase signal confidence but have critical bugs:

**Bug A: Transformer output mismatch** (CRITICAL)
- Location: `AIModules/TransformerBrain.mqh:642-681` and `Core/Strategy/TransformerAIStrategyAdapter.mqh:122-136`
- Problem: TransformerBrain.Forward() returns feature vector (size m_dModel), but adapters expect 3-class logits
- Impact: Adapters read random first 3 elements of feature vector, apply softmax to garbage → incorrect AI signals
- Fix: Add proper classification head to Transformer OR change adapters to extract features correctly

**Bug B: Ensemble double-delete** (CRITICAL - causes crashes)
- Location: `AIModules/EnsembleMetaLearner.mqh:59-66` (destructor) and `Core/Strategy/EnsembleAIStrategyAdapter.mqh:125-139`
- Problem: Both ensemble and adapter delete same model pointers → double-free corruption
- Impact: Memory corruption, potential EA crash during deinit
- Fix: Single ownership - ensemble owns models, adapter doesn't delete them

**Bug C: AIPerformanceFeedback unwired**
- Location: `Core/AI/AIPerformanceFeedback.mqh` (implemented but unused)
- Problem: Prediction recording system defined but never called
- Impact: AI feedback loop doesn't capture prediction-outcome pairs → no learning
- Fix: Wire aiFeedback.RecordPrediction/RecordOutcome in trading flow

**Bug D: Regime detection stuck in REGIME_NONE**
- Location: `Core/Engines/RegimeEngine.mqh` + pipeline usage
- Problem: Regime is always REGIME_NONE in logs, which caps confidence and blocks signals
- Impact: Adds 0.05-0.10 penalty to threshold, making already-marginal signals fail
- Fix: Debug regime engine detection, may need calibration

### 3. Timeframe Coordination Broken
- **Issue 1**: OnNewBar called with EA chart timeframe, but strategies expect their registered timeframe
  - Location: `MultiStrategyAutonomousEA.mq5:2000+` calls `barManager.OnNewBar(symbol, Period())` 
  - But strategies registered with different timeframes don't get their expected timeframe in OnNewBar
  - Result: Indicators warming up incorrectly, TrendEngine initializes with wrong timeframe
- **Issue 2**: Pipeline doesn't use TimeframeConsistency for multi-TF conflict resolution
  - Location: `UnifiedSignalPipeline.mqh` has ProcessMTFSignals but it's not called by EnterpriseManager
  - Result: No HTF prioritization, no TF-aware consensus
- **Issue 3**: Duplicate indicator handles for same TF/symbol combos
  - Impact: Memory waste, possible handle exhaustion

---

## Fix Priority & Sequence

### Phase 1: Unblock Pipeline (Gets trades executing) [Done]
1. **Lower pipeline confidence threshold** [Done]
   - File: `Core/Pipeline/UnifiedSignalPipeline.mqh`
   - Change base threshold from 0.60 → 0.45
   - Change regime cap from 0.05-0.10 → 0.02 OR make regime non-blocking
   - Test: Re-run with same log output, confirm signals pass confidence filter

2. **Debug & fix Regime detection** [Done]
   - File: `Core/Engines/RegimeEngine.mqh`
   - Understand why REGIME_NONE for all symbols at all times
   - Calibrate or disable regime penalty if broken
   - Test: Confirm regime detection produces meaningful values

### Phase 2: Fix AI (Boosts confidence when working) [Done]
1. **Fix Transformer → Adapter contract** (TransformerBrain output classification) [Done]
   - File: `AIModules/TransformerBrain.mqh`
   - Add classification head that outputs 3-class probabilities (NONE, BUY, SELL)
   - OR modify adapters to apply correct transformation
   - Test: Verify AI votes are semantically correct, check logs for [AI-VOTE] entries

2. **Fix Ensemble ownership (prevent crashes)** [Done]
   - File: `Core/Strategy/EnsembleAIStrategyAdapter.mqh` + `AIModules/EnsembleMetaLearner.mqh`
   - Make ensemble responsible for model lifecycle (owns deletes)
   - Adapter only references, doesn't delete
   - Test: Deinit EA and verify no memory corruption or crashes

3. **Wire AIPerformanceFeedback** [Done]
   - File: `MultiStrategyAutonomousEA.mq5` (OnTradeTransaction + signal generation)
   - Add calls to aiFeedback.RecordPrediction when AI adapters vote
   - Add calls to aiFeedback.RecordOutcome when trades close
   - Test: Verify aiFeedback logs show prediction-outcome pairs recorded

### Phase 3: Fix Timeframe Coordination (Proper multi-TF decisions) [Done]
1. **Fix OnNewBar timeframe dispatch** [Done]
   - File: `Core/Management/EnterpriseStrategyManager.mqh`
   - Modify OnNewBar to call strategy.OnNewBar with strategy's registered timeframe, not manager timeframe
   - Test: Verify indicators initialize with correct timeframes, bar counts correct

2. **Integrate TimeframeConsistency into manager consensus** [Done]
   - File: `Core/Management/EnterpriseStrategyManager.mqh`
   - When aggregating strategy votes, use TimeframeConsistency to resolve TF conflicts
   - Test: Verify HTF-priority or majority-weighted consensus applied

3. **Deduplicate indicator handles** [Done]
   - File: `IndicatorManager.mqh` (verify reuse logic)
   - Confirm IndicatorManager deduplicates same TF+symbol combos
   - Test: Monitor handle count growth in heartbeat logs

---

## Testing & Validation

### After Phase 1 (Pipeline unblocked):
- Confirm signals pass confidence filter in logs
- Verify [SIGNAL-VALIDATED] and [TRADE-*] entries appear
- Check that trades reach execution layer
- Run shadow mode first to confirm entry logic works

### After Phase 2 (AI fixed):
- Confirm [AI-VOTE] entries in logs with meaningful confidences
- Verify AI adapters contribute to consensus (buyVotes/sellVotes from AI)
- Check AIPerformanceFeedback logs show predictions recorded
- Verify no crashes on deinit (ensemble ownership fixed)

### After Phase 3 (Timeframe coordination):
- Confirm indicator initialization uses correct timeframes
- Verify [CONSENSUS-DIAG] shows proper vote aggregation across timeframes
- Check for duplicate indicator handles in logs

---

## Key Files to Modify (Summary)

1. `Core/Pipeline/UnifiedSignalPipeline.mqh` - threshold adjustment
2. `Core/Engines/RegimeEngine.mqh` - regime detection debug/fix
3. `AIModules/TransformerBrain.mqh` - classification output
4. `Core/Strategy/TransformerAIStrategyAdapter.mqh` - adapter logic adjustment
5. `Core/Strategy/EnsembleAIStrategyAdapter.mqh` - ownership cleanup
6. `AIModules/EnsembleMetaLearner.mqh` - destructor fix
7. `MultiStrategyAutonomousEA.mq5` - wire AIPerformanceFeedback
8. `Core/Management/EnterpriseStrategyManager.mqh` - OnNewBar TF + consensus integration
9. `Core/Signals/TimeframeConsistency.mqh` - may need integration points added

---

## Expected Outcome

**After all fixes:**
- Signals consistently pass pipeline threshold
- AI modules contribute meaningful confidence boosts (when configured)
- Multi-timeframe decisions properly coordinated
- Trades flow from signal → validation → risk gate → execution
- Shadow trades work, live trades execute
- Logs show [SIGNAL-VALIDATED], [TRADE-SUCCESS], [AI-VOTE] entries
- No memory corruption on shutdown
