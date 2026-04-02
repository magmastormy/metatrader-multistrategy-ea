# AXIOM EA — AI Architecture Improvement Spec
> **Document Type:** Codex Implementation Spec — Doc 3 of 3  
> **Scope:** AI architecture analysis, performance problems, upgrade path  
> **Files analyzed:** `NeuralNetworkStrategy.mqh`, `TransformerBrain.mqh`, `NextGenStrategyBrain.mqh`, `EnsembleMetaLearner.mqh`, `UncertaintyQuantifier.mqh`  
> **Read this entire document before touching any AI file.**

---

## AI ARCHITECTURE ANALYSIS — WHAT'S ACTUALLY THERE

### What exists and its real cost

| Component | Architecture | Param Count | Per-Inference Cost |
|---|---|---|---|
| `CNeuralNetworkStrategy` | 25→15→10→3 feedforward | ~600 params | ~800 multiplications — fast |
| `CTransformerBrain` | 8 heads, 6 layers, dModel=256, dFF=1024, maxSeqLen=512 | ~6M params | ~O(seqLen² × dModel × numLayers) — **extremely slow** |
| `CEnsembleMetaLearner` | Holds N `CTransformerBrain` instances | N × 6M | N× the above |
| `CUncertaintyQuantifier` | History-based, no model | Tiny | O(historySize) per update |

The `CTransformerBrain` with these defaults is not appropriate for MQL5. A sequence of 100 steps × 256 dimensions means the Q, K, V projections are 100×256 matrices. The attention matrix is 100×100 = 10,000 values per head, per layer. With 8 heads × 6 layers = 480,000 attention values computed per inference. On a CPU in a live EA this takes seconds, not milliseconds.

---

## PROBLEM LIST — SPECIFIC TO AI FILES

### P1 — Transformer is catastrophically oversized for MQL5

Default constructor: `CTransformerBrain(dModel=256, numHeads=8, numLayers=6, dFF=1024, maxSeqLen=512)`

- Weight matrix allocation: `WQ = dModel × dModel = 256×256 = 65,536 doubles` × 4 matrices (WQ, WK, WV, WO) × 8 heads × 6 layers = **~12.5 million doubles = 100 MB RAM** just for attention weights.
- Forward pass: O(seqLen² × dModel) per layer = O(512² × 256 × 6) ≈ 400 million ops per inference.
- This will freeze the EA during forward pass for any significant sequence length.

### P2 — Ensemble multiplies the already-oversized model

`CEnsembleMetaLearner` holds a dynamic array of `CTransformerBrain*`. Even with 2 models, the RAM and compute double. There's no warmup guard — models are queried immediately even with 0 training steps. `EvaluateModelPerformance()` is declared but its body isn't implemented in the attached file.

### P3 — `CTransformerBrain::Forward()` always runs full seqLen

Even when only 10 new data points have arrived, the sequence passed may be padded to `maxSeqLen=512`, running attention over 512 positions of mostly zeros. No variable-length attention masking exists.

### P4 — Training only updates the classification head, not the transformer blocks

`CTransformerBrain::TrainStep()` calls `UpdateClassificationHead()` which updates `m_classificationWeights` and `m_classificationBiases`. The transformer blocks themselves (`CTransformerBlock`, `CMultiHeadAttention`, `CFeedForwardNetwork`) have **no backpropagation implemented**. The 6M+ parameters in the transformer are initialized randomly and never change. Only the 3×256 = 768-param classification head learns. This means the transformer is acting as a fixed random-feature extractor — which actually works to some degree (random projections have theoretical basis) but is not what the architecture claims to do.

### P5 — `CNeuralNetworkStrategy` trains only the last 256 samples max per cycle

```cpp
const int maxSamplesPerCycle = 256;
```
The ring starts at `labeledCount - 256` so old data is ignored. This is fine. But there's also a minimum of 20 samples required before any training (`m_minTrainingExamples = 20`). With pseudo-labeling enabled, the model trains on synthetic labels — if pseudo-label accuracy is poor, the model learns noise.

### P6 — `CNextGenStrategyBrain` has dead server code and double-softmax

Covered in Doc 1 but repeated here for completeness: `SendInferenceRequest()` returns `false` immediately. The code then runs softmax on the transformer output, but `GetPredictions()` already applied softmax internally. The output is doubly-normalized.

### P7 — No feature importance / input validation

`CNeuralNetworkStrategy::ExtractFeatures()` fills a 25-element input array. If any indicator returns 0 (handle not ready, insufficient bars), those zeros propagate silently into training. The network learns from corrupted feature vectors. No feature validation gate exists.

### P8 — `CUncertaintyQuantifier` history uses `Delete(0)` — O(n) per update

Covered in Doc 1. Additionally: `CalculateHistoricalVolatility()` and `CalculatePredictionError()` loop backwards through `m_predictionHistory.At(i)` — this is fine logically but slow with CArrayDouble's indexed access vs a native array.

---

## SECTION 1 — Right-Size the Transformer

### 1.1 New default constructor parameters

The transformer should run comfortably within 10–20ms per inference on a modern CPU. Target architecture:

| Parameter | Current (broken) | New (correct) | Why |
|---|---|---|---|
| `dModel` | 256 | 64 | 16× fewer attention weights |
| `numHeads` | 8 | 4 | Keep head dimension = 16 |
| `numLayers` | 6 | 2 | 3× fewer block passes |
| `dFF` | 1024 | 128 | 8× smaller feedforward |
| `maxSeqLen` | 512 | 50 | Only need ~50 bars of context |

**New weight count:** WQ, WK, WV, WO = 64×64 each = 4,096 per matrix × 4 = 16,384 per head × 4 heads = 65,536 per layer × 2 layers = **131,072 doubles ≈ 1 MB**. This is 100× smaller than current.

**New attention cost per inference:** 50² × 64 × 4 heads × 2 layers ≈ 1.28M ops. Fast enough for real-time use.

Change the constructor default parameters:

```cpp
// OLD:
CTransformerBrain(int dModel = 256, int numHeads = 16, int numLayers = 6,
                  int dFF = 1024, int maxSeqLen = 512, double learningRate = 0.001)

// NEW:
CTransformerBrain(int dModel = 64, int numHeads = 4, int numLayers = 2,
                  int dFF = 128, int maxSeqLen = 50, double learningRate = 0.001)
```

**Also update `NextGenStrategyBrain` initialization** to pass these smaller values explicitly:
```cpp
m_transformerBrain = new CTransformerBrain(64, 4, 2, 128, 50, 0.001);
```

---

### 1.2 Add variable-length sequence masking

Currently the transformer processes `seqLen` from `PrepareModelInput()`. But the positional encoding and attention still run over the full allocated space if the array is over-sized.

In `CTransformerBrain::Forward()`, pass `seqLen` as a parameter and add attention masking:

```cpp
// Update signature:
bool Forward(const double &inputFeatures[], int actualSeqLen, double &output[])
{
    // Only process actualSeqLen positions, not the full allocated array
    int seqLen = MathMin(actualSeqLen, m_maxSeqLen);
    // ... rest uses seqLen, not ArraySize(inputFeatures) / m_dModel
}
```

In `CMultiHeadAttention::ScaledDotProductAttention()`, add a `seqLen` parameter so it doesn't compute attention for padding positions.

---

## SECTION 2 — Fix the Training Reality Gap

### 2.1 Document what actually trains

Add a comment block at the top of `TransformerBrain.mqh` that clearly states:

```cpp
// TRAINING NOTE:
// Only the classification head (3 × dModel weights) receives gradient updates.
// The transformer encoder weights (WQ, WK, WV, WO, FF layers) are fixed at
// Xavier-initialized random values. This is "linear probing" on random features —
// a valid approach but different from full fine-tuning.
// Full transformer backprop is not implemented in MQL5 due to complexity.
// To improve: use the SimpleNN (CNeuralNetworkStrategy) for actual online learning,
// and use the transformer as a fixed feature extractor only.
```

### 2.2 Separate roles: Transformer as feature extractor, NN as learner

The best architecture given MQL5 constraints is a two-stage pipeline:

```
Raw market data → [Transformer: fixed feature extraction] → 25 features → [SimpleNN: learns] → signal
```

Implement this by:

**Stage 1 — Feature extraction from `CTransformerBrain`:**

Add a method `GetEncodedFeatures()` that returns the global-average-pooled transformer output (already exists as `Forward()` output) as a fixed-size feature vector:

```cpp
// Already works — the Forward() output IS the feature vector
// We just need to expose it cleanly:
bool GetEncodedFeatures(const double &inputData[], int seqLen, double &features[])
{
    return Forward(inputData, seqLen, features);  // features = dModel-dimensional vector
}
```

**Stage 2 — Connect transformer features to SimpleNN:**

In `CNeuralNetworkStrategy::ExtractFeatures()`, instead of only using raw indicator values, optionally also include the transformer's encoded representation:

```cpp
bool ExtractFeatures(double (&inputs)[25])
{
    // Features 0–14: traditional indicators (RSI, MACD, ATR, EMAs, etc.)
    // This part stays the same
    if(!ExtractIndicatorFeatures(inputs, 15)) return false;

    // Features 15–24: transformer-encoded market context (optional)
    // Only if transformer is available and warmed up
    if(m_transformerRef != NULL && m_transformerRef.IsWarmedUp(50))
    {
        double tfFeatures[];
        if(m_transformerRef.GetEncodedFeatures(m_lastModelInput, m_lastSeqLen, tfFeatures))
        {
            // PCA reduce dModel→10 features using first 10 principal components
            // (simple approximation: just take every nth element)
            int dModel = ArraySize(tfFeatures);
            int step   = MathMax(1, dModel / 10);
            for(int i = 0; i < 10; i++)
            {
                int idx = (int)(i * step);
                if(idx < dModel)
                    inputs[15 + i] = MathMax(-3.0, MathMin(3.0, tfFeatures[idx]));
                else
                    inputs[15 + i] = 0.0;
            }
        }
    }

    return true;
}
```

Add a `SetTransformerRef(CTransformerBrain* t)` method to `CNeuralNetworkStrategy` so it can optionally receive the transformer's output.

---

## SECTION 3 — Feature Validation Gate

### 3.1 Add to `ExtractFeatures()` in `CNeuralNetworkStrategy`

Before returning from `ExtractFeatures()`, validate that the feature vector is sensible:

```cpp
bool ValidateFeatures(const double (&features)[25])
{
    int zeroCount = 0;
    int nanCount  = 0;

    for(int i = 0; i < 25; i++)
    {
        if(!MathIsValidNumber(features[i])) nanCount++;
        if(features[i] == 0.0)             zeroCount++;
    }

    // Reject if more than 30% of features are zero (indicator not ready)
    if(zeroCount > 7)
    {
        static datetime s_lastWarn = 0;
        if(TimeCurrent() - s_lastWarn > 60)
        {
            PrintFormat("[NN] Feature validation failed: %d/25 zeros, %d NaN", zeroCount, nanCount);
            s_lastWarn = TimeCurrent();
        }
        return false;
    }

    if(nanCount > 0)
    {
        Print("[NN] Feature validation failed: NaN detected in inputs");
        return false;
    }

    return true;
}
```

Call this before creating a training example:
```cpp
if(!ValidateFeatures(inputs))
    return false;  // Don't create training example with bad features
```

---

## SECTION 4 — Streamline the Ensemble

### 4.1 What the ensemble currently does

`CEnsembleMetaLearner` holds N `CTransformerBrain*` instances and does weighted voting. The weights are updated by `UpdateModelWeights()` based on market regime. The problem: with the transformer being a fixed random-feature extractor (no backprop), all transformer instances in the ensemble converge to the same wrong answer weighted differently. Multiple random projections of the same data with different random seeds doesn't create meaningful diversity.

### 4.2 The fix — True ensemble diversity via input perturbation

If we're keeping the ensemble, give each model a genuinely different view of the market:

```cpp
// Model 1: Full sequence (all 50 bars)
// Model 2: Short-term only (last 10 bars)
// Model 3: Volume-weighted features only
// Model 4: Multi-timeframe (H1 data instead of M15)
```

This creates actual diversity. Implement by giving each `CTransformerBrain` in the ensemble a different data slice from `CMarketDataProcessor`:

```cpp
// In CNextGenStrategyBrain, replace:
m_ensembleSystem.AddModel(new CTransformerBrain());
m_ensembleSystem.AddModel(new CTransformerBrain());

// With differentiated models:
CTransformerBrain* longTermModel  = new CTransformerBrain(64, 4, 2, 128, 50);  // Full history
CTransformerBrain* shortTermModel = new CTransformerBrain(64, 4, 2, 128, 10);  // Recent only
m_ensembleSystem.AddModel(longTermModel,  1.0);
m_ensembleSystem.AddModel(shortTermModel, 0.8);
```

### 4.3 Implement `EvaluateModelPerformance()` properly

The method is declared but not meaningfully implemented. Implement as win-rate on most recent N completed trades:

```cpp
double CEnsembleMetaLearner::EvaluateModelPerformance(CTransformerBrain* model, const double &testData[])
{
    if(model == NULL || !model.IsWarmedUp(10)) return 0.5;  // 50% = chance level baseline

    // Simple evaluation: compare model prediction direction with test outcome
    // testData format: [features..., actual_outcome] where outcome > 0 = win
    int testLen = ArraySize(testData);
    if(testLen < 2) return 0.5;

    double predictions[];
    if(!model.GetPredictions(testData, predictions)) return 0.5;
    if(ArraySize(predictions) < 2) return 0.5;

    // Check if model predicted direction matches
    double actualOutcome = testData[testLen - 1];  // Last element = outcome
    bool modelSaysBuy  = (predictions[1] > predictions[2] && predictions[1] > predictions[0]);
    bool modelSaysSell = (predictions[2] > predictions[1] && predictions[2] > predictions[0]);
    bool outcomeWasBuy  = (actualOutcome > 0);
    bool outcomeWasSell = (actualOutcome < 0);

    bool correct = (modelSaysBuy  && outcomeWasBuy) ||
                   (modelSaysSell && outcomeWasSell);

    return correct ? 1.0 : 0.0;
    // Over many calls, m_ensembleSystem will average these into a win-rate per model
}
```

### 4.4 Implement `DeactivateUnderperformingModels()` 

```cpp
void CEnsembleMetaLearner::DeactivateUnderperformingModels(double threshold)
{
    // threshold = win rate below which a model gets deactivated
    for(int i = m_models.Total() - 1; i >= 0; i--)
    {
        CTransformerBrain* model = dynamic_cast<CTransformerBrain*>(m_models.At(i));
        if(model == NULL) continue;

        // Only evaluate warmed-up models
        if(!model.IsWarmedUp(50)) continue;

        // Use the training steps as a proxy for recent performance
        // (proper evaluation would require a holdout set)
        // For now, deactivate if average loss > threshold proxy
        // This is a placeholder — integrate with actual performance tracking
        double dummyTestData[];  // Would be populated from actual trade results
        double perf = EvaluateModelPerformance(model, dummyTestData);

        if(perf < threshold)
        {
            Print("[ENSEMBLE] Deactivating model ", i, " (perf=", perf, " < threshold=", threshold, ")");
            RemoveModel(i);
        }
    }
}
```

---

## SECTION 5 — AI Mode Toggle Wiring

### 5.1 How AI mode interacts with the strategy registry (cross-ref with Doc 2)

From Doc 2, the `ENUM_EA_MODE` controls whether AI strategies are active. In the AI files, add a clean interface point:

In `CNextGenStrategyBrain`, expose:

```cpp
bool IsReady() const
{
    return m_initialized &&
           m_transformerBrain != NULL &&
           m_transformerBrain.IsWarmedUp(50);
}

string GetReadinessStatus() const
{
    if(!m_initialized)           return "Not initialized";
    if(m_transformerBrain == NULL) return "Transformer missing";
    if(!m_transformerBrain.IsWarmedUp(50))
        return StringFormat("Warming up (%d/50 steps)", m_transformerBrain.GetTrainingSteps());
    return "Ready";
}
```

In `CNeuralNetworkStrategy`, expose:

```cpp
bool IsReady() const
{
    return m_initialized &&
           GetCompletedTradesCount() >= m_minTrainingExamples;
}

string GetReadinessStatus() const
{
    int completed = GetCompletedTradesCount();
    if(!m_initialized)               return "Not initialized";
    if(completed < m_minTrainingExamples)
        return StringFormat("Collecting data (%d/%d labeled)", completed, m_minTrainingExamples);
    return StringFormat("Ready | Epoch=%d | Loss=%.4f", m_epoch, m_lastLoss);
}
```

The strategy registry can call `IsReady()` before calling `GetSignal()`. If not ready, skip the strategy and log the status.

---

## SECTION 6 — Practical Feature Engineering Upgrade

### 6.1 Current 25 features in `CNeuralNetworkStrategy`

The 25 inputs likely include RSI, MACD, ATR, EMA values, etc. Regardless of what they are, add these improvements:

**Normalize all inputs to [-1, 1] range before feeding the network.** The current inputs are raw indicator values (RSI in 0–100 range, price in thousands, ATR in instrument units). These different scales cause gradient issues during training.

Add a normalization step in `ExtractFeatures()`:

```cpp
// After extracting all 25 raw features, normalize each:
void NormalizeFeatures(double (&features)[25])
{
    // Define expected ranges per feature type
    // Adjust these based on what your 25 features actually are
    static const double featureMin[25] = {
        0,    // RSI: 0–100 → normalize to -1 to +1
        -5,   // MACD signal (pips): -5 to +5
        // ... etc
    };
    static const double featureMax[25] = {
        100, 5, /* ... */
    };

    for(int i = 0; i < 25; i++)
    {
        double range = featureMax[i] - featureMin[i];
        if(range < 1e-9) { features[i] = 0.0; continue; }
        features[i] = ((features[i] - featureMin[i]) / range) * 2.0 - 1.0;
        features[i] = MathMax(-1.0, MathMin(1.0, features[i]));
    }
}
```

If the min/max ranges are unknown, use Z-score normalization using a running mean/std tracked over the last 200 samples.

### 6.2 Add price momentum features

The current features likely include price levels but not rate-of-change. Add:
- Return over last 1, 3, 5, 10, 20 bars (price change %)
- These are bounded and instrument-agnostic
- Replace any raw price level features with these

```cpp
// Price returns (normalized, instrument-agnostic):
double close0 = iClose(m_symbol, m_timeframe, 0);
inputs[FEAT_RET_1]  = (close0 / iClose(m_symbol, m_timeframe, 1)  - 1.0) * 100.0;
inputs[FEAT_RET_3]  = (close0 / iClose(m_symbol, m_timeframe, 3)  - 1.0) * 100.0;
inputs[FEAT_RET_5]  = (close0 / iClose(m_symbol, m_timeframe, 5)  - 1.0) * 100.0;
inputs[FEAT_RET_10] = (close0 / iClose(m_symbol, m_timeframe, 10) - 1.0) * 100.0;
inputs[FEAT_RET_20] = (close0 / iClose(m_symbol, m_timeframe, 20) - 1.0) * 100.0;
```

---

## SECTION 7 — AI Health Dashboard

Add a unified AI health report that surfaces in the chart dashboard:

```cpp
// In CNextGenStrategyBrain or a new CAIDashboard class:
string GetAIDashboardLine() const
{
    string line = "";

    // Transformer status
    if(m_transformerBrain != NULL)
    {
        int steps = m_transformerBrain.GetTrainingSteps();
        line += StringFormat("TF:%s(%d) ", IsReady() ? "RDY" : "WARM", steps);
    }

    // Uncertainty
    double avgUnc = GetCurrentUncertainty();
    line += StringFormat("UNC:%.2f ", avgUnc);

    // Ensemble
    if(m_ensembleSystem != NULL)
        line += StringFormat("ENS:%d ", m_ensembleSystem.GetActiveModelCount());

    return line;
}
```

Displayed on chart as:
```
AI: TF:RDY(238) | UNC:0.31 | ENS:2/2 active
NN: Epoch=45 | Loss=0.0821 | Labeled=127/2000
```

---

## SECTION 8 — Upgrade Summary and Build Order

### 8.1 What to build, in order

1. **Right-size the Transformer** (Section 1) — reduces RAM from ~100MB to ~1MB, inference from seconds to milliseconds. Do this first or nothing else matters.

2. **Add inference cache** (Doc 1, Section 4) — ensures the right-sized transformer still only runs once per bar.

3. **Fix the ring buffers** (Doc 1, Sections 2.1, 2.2, 2.3) — eliminates O(n) shifts per tick.

4. **Add feature validation gate** (Section 3) — stops the NN learning from corrupted inputs.

5. **Add normalized features** (Section 6) — improves convergence of the NN.

6. **Two-stage pipeline** (Section 2) — connect transformer features to NN. Optional but high value.

7. **Implement ensemble diversity** (Section 4.2) — only worth doing after steps 1–6.

8. **AI health dashboard** (Section 7) — visibility, not performance.

9. **Wire AI mode toggle** (Section 5 + Doc 2) — connects AI readiness to the registry.

### 8.2 What NOT to build right now

- Full transformer backpropagation — too complex for MQL5, and the fixed-feature-extractor approach works
- Attention visualization — deferred unless debugging attention patterns is a priority
- Server-side inference — the Python bridge is gone and should stay gone

---

*AXIOM Engineering Studio | Codex Spec Doc 3 of 3*
