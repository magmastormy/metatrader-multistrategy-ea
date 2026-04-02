# AXIOM EA — Architecture Refactoring & Debloat Spec
> **Document Type:** Codex Implementation Spec — Doc 1 of 3  
> **Scope:** System-wide refactoring, speed, dead code removal, structural cleanup  
> **Read this entire document before touching any file.**

---

## WHY THIS EXISTS

The EA has accumulated significant technical debt across three layers:

- **Compute waste:** Indicator handles created and released on every tick. Arrays shifted with O(n) `ArrayCopy` on every bar. Full transformer inference running every tick even when the signal hasn't changed.
- **Dead code weight:** A Python bridge (`SendInferenceRequest`, `ParseJSONResponse`) that returns `false` immediately. A `HYBRID CLOUD` label in the codebase with no server. Multiple stub lifecycle methods (`Shutdown()`, `Initialize()`) that do nothing.
- **Structural opacity:** It's impossible to tell from the code which strategies are active. The initialization flow mixes mandatory and optional components in the same `if(!component.Initialize()) return false` chain, meaning one optional module failing kills the whole EA.
- **Memory fragmentation:** `CArrayObj` with per-element `new CTrainingExample()` heap allocation, and `CArrayDouble` with `Delete(0)` (full-array shift) on every history update.

---

## SECTION 1 — Dead Code Removal

### 1.1 Remove Python Bridge from `NextGenStrategyBrain.mqh`

**Delete these entirely:**
- `SendInferenceRequest()` — the body already just returns `false`
- `ParseJSONResponse()` — dead since Python bridge was removed
- `m_serverCircuitOpen` field
- `m_consecutiveFailures` field  
- `m_lastFailureTime` field
- The entire `if(!serverSuccess)` branching block — keep only the local transformer path
- `GetEnsembleStatus()` — returns `"LOCAL ONLY"` or `"HYBRID CLOUD"` but cloud never works, just remove it

**What replaces the branching block:**
```cpp
bool CNextGenStrategyBrain::GetSignal(SEnhancedTradeSignal &signal)
{
    if(!m_initialized) return false;

    // Prepare input from data processor
    double modelInput[];
    int seqLen = 0;
    if(!m_dataProcessor.PrepareModelInput(modelInput, seqLen))
        return false;

    // Single path: local transformer only
    double encodedFeatures[];
    if(!m_transformerBrain.Forward(modelInput, encodedFeatures))
        return false;

    double predictions[];
    if(!m_transformerBrain.GetPredictions(modelInput, predictions))
        return false;

    // [0]=NONE, [1]=BUY, [2]=SELL
    double noneP = predictions[0];
    double buyP  = predictions[1];
    double sellP = predictions[2];

    signal.buyProbability  = buyP;
    signal.sellProbability = sellP;
    signal.timestamp       = TimeCurrent();

    if(buyP  > m_confidenceThreshold && buyP  > sellP && buyP  > noneP)
    { signal.signal = TRADE_SIGNAL_BUY;  signal.confidence = buyP; }
    else if(sellP > m_confidenceThreshold && sellP > buyP && sellP > noneP)
    { signal.signal = TRADE_SIGNAL_SELL; signal.confidence = sellP; }
    else
    { signal.signal = TRADE_SIGNAL_NONE; signal.confidence = noneP; }

    // Entropy-based uncertainty
    double entropy = -(buyP*MathLog(buyP+1e-9) + sellP*MathLog(sellP+1e-9) + noneP*MathLog(noneP+1e-9));
    signal.uncertainty.uncertainty = entropy / 1.0986;

    return true;
}
```

---

### 1.2 Remove No-Op Lifecycle Methods Everywhere

These methods exist across `TransformerBrain.mqh`, `EnsembleMetaLearner.mqh`, and `NextGenStrategyBrain.mqh` and do nothing:

```cpp
// DELETE ALL of these empty stubs:
bool Initialize()  { return true; }
void Shutdown()    { /* Cleanup handled by destructor */ }
void Shutdown()    { /* nothing */ }
bool Initialize()  { return true; }
```

Replace with proper destructor cleanup where needed (already handled via `~CTransformerBrain()` etc.). Remove the methods from all class declarations and any call sites.

---

### 1.3 Remove `m_inputSequence` intermediate copy in `CTransformerBrain`

In `TransformerBrain.mqh`, `Forward()` does:
```cpp
ArrayCopy(m_inputSequence, inputFeatures);  // UNNECESSARY COPY
```

Then `m_inputSequence` is passed into the positional encoding. Remove the member variable entirely. Pass `inputFeatures` directly (make a local copy only if mutation is needed):

```cpp
bool CTransformerBrain::Forward(const double &inputFeatures[], double &output[])
{
    // Work with a local mutable copy only
    double workingData[];
    ArrayCopy(workingData, inputFeatures);

    int seqLen = ArraySize(workingData) / m_dModel;
    if(!m_positionalEncoding.AddPositionalEncoding(workingData, seqLen)) return false;

    // rest of forward pass uses workingData...
}
```

Remove `double m_inputSequence[]` from the class entirely.

---

### 1.4 Remove `m_output[]` cached copy in `CTransformerBrain`

`m_output` is assigned at the end of `Forward()` via `ArrayCopy(m_output, output)` but is never read anywhere. Remove the member variable and the copy operation.

---

## SECTION 2 — O(n) Array Operations — Replace With Ring Buffers

### 2.1 Fix `CMarketDataProcessor::AddDataPoint()` — O(n) ArrayCopy on every bar

**Current (broken) pattern:**
```cpp
// This shifts the ENTIRE price/volume/indicator arrays every time
ArrayCopy(m_priceData, m_priceData, 0, 1, m_maxSequenceLength - 1);
```

On a sequence of 100 bars × 10 indicators = 1000 double shifts, called every tick. Replace with a ring buffer:

**New `CMarketDataProcessor` implementation:**

```cpp
class CMarketDataProcessor
{
private:
    double  m_priceData[];
    double  m_volumeData[];
    double  m_indicatorData[];  // [bar * INDICATOR_COUNT + indicator_index]
    int     m_maxSeqLen;
    int     m_head;             // Write pointer (ring buffer head)
    int     m_count;            // Number of valid entries
    bool    m_isFull;

    static const int INDICATOR_COUNT = 10;

    // Convert logical index [0 = oldest, count-1 = newest] to physical array index
    int PhysicalIndex(int logicalIndex) const
    {
        if(!m_isFull)
            return logicalIndex;
        return (m_head - m_count + logicalIndex + m_maxSeqLen) % m_maxSeqLen;
    }

public:
    CMarketDataProcessor(int maxSeqLen = 100)
    {
        m_maxSeqLen = maxSeqLen;
        m_head      = 0;
        m_count     = 0;
        m_isFull    = false;
        ArrayResize(m_priceData,     maxSeqLen);
        ArrayResize(m_volumeData,    maxSeqLen);
        ArrayResize(m_indicatorData, maxSeqLen * INDICATOR_COUNT);
        ArrayInitialize(m_priceData,     0.0);
        ArrayInitialize(m_volumeData,    0.0);
        ArrayInitialize(m_indicatorData, 0.0);
    }

    bool AddDataPoint(double price, double volume, const double &indicators[])
    {
        int writeIdx = m_head;
        m_priceData[writeIdx]  = price;
        m_volumeData[writeIdx] = volume;

        int indBase = writeIdx * INDICATOR_COUNT;
        int copyCount = MathMin(ArraySize(indicators), INDICATOR_COUNT);
        for(int i = 0; i < copyCount; i++)
            m_indicatorData[indBase + i] = indicators[i];

        m_head = (m_head + 1) % m_maxSeqLen;
        if(m_count < m_maxSeqLen) m_count++;
        if(m_count == m_maxSeqLen) m_isFull = true;

        return true;
    }

    bool PrepareModelInput(double &modelInput[], int &sequenceLength)
    {
        sequenceLength = m_count;
        if(sequenceLength < 10) return false;

        int featuresPerStep = 2 + INDICATOR_COUNT;
        ArrayResize(modelInput, sequenceLength * featuresPerStep);

        // Calculate stats for normalization
        double priceMean = 0, priceStd = 0;
        double volMean = 0, volStd = 0;
        for(int i = 0; i < sequenceLength; i++)
        {
            int phys = PhysicalIndex(i);
            priceMean += m_priceData[phys];
            volMean   += m_volumeData[phys];
        }
        priceMean /= sequenceLength;
        volMean   /= sequenceLength;

        for(int i = 0; i < sequenceLength; i++)
        {
            int phys = PhysicalIndex(i);
            double pd = m_priceData[phys] - priceMean;
            double vd = m_volumeData[phys] - volMean;
            priceStd += pd * pd;
            volStd   += vd * vd;
        }
        priceStd = MathSqrt(priceStd / sequenceLength + 1e-9);
        volStd   = MathSqrt(volStd   / sequenceLength + 1e-9);

        for(int i = 0; i < sequenceLength; i++)
        {
            int phys    = PhysicalIndex(i);
            int base    = i * featuresPerStep;
            modelInput[base]     = (m_priceData[phys] - priceMean) / priceStd;
            modelInput[base + 1] = MathMax(-3.0, MathMin(3.0, (m_volumeData[phys] - volMean) / volStd));
            int indBase = phys * INDICATOR_COUNT;
            for(int j = 0; j < INDICATOR_COUNT; j++)
                modelInput[base + 2 + j] = MathMax(-10.0, MathMin(10.0, m_indicatorData[indBase + j]));
        }

        return true;
    }

    int GetCount() const { return m_count; }
};
```

**What this saves:** Zero `ArrayCopy` calls during data ingestion. The only copy happens during `PrepareModelInput()` which is called once per signal check, not per tick.

---

### 2.2 Fix `CUncertaintyQuantifier` — `Delete(0)` on every update

**Current pattern in `UpdatePredictionHistory()`:**
```cpp
while(m_predictionHistory.Total() > m_historySize)
    m_predictionHistory.Delete(0);  // Shifts entire array every call
```

`CArrayDouble::Delete(0)` shifts all N elements left by one position. With `m_historySize = 1000` this is 1000 operations per update.

**Replace `CArrayDouble m_predictionHistory` with a ring buffer:**

```cpp
class CUncertaintyQuantifier
{
private:
    double  m_predHistory[];
    double  m_errHistory[];
    int     m_histSize;
    int     m_predHead, m_predCount;
    int     m_errHead,  m_errCount;

    void RingPush(double &arr[], int &head, int &count, int maxSize, double val)
    {
        arr[head] = val;
        head = (head + 1) % maxSize;
        if(count < maxSize) count++;
    }

    double RingGet(const double &arr[], int head, int count, int maxSize, int logicalIdx) const
    {
        // logicalIdx 0 = oldest, count-1 = newest
        int phys = (head - count + logicalIdx + maxSize) % maxSize;
        return arr[phys];
    }

public:
    CUncertaintyQuantifier(int historySize = 500)  // Reduced from 1000
    {
        m_histSize  = historySize;
        m_predHead  = 0; m_predCount = 0;
        m_errHead   = 0; m_errCount  = 0;
        ArrayResize(m_predHistory, historySize);
        ArrayResize(m_errHistory,  historySize);
        ArrayInitialize(m_predHistory, 0.0);
        ArrayInitialize(m_errHistory,  0.0);
    }

    bool UpdatePredictionHistory(double prediction, double actualOutcome = 0.0)
    {
        RingPush(m_predHistory, m_predHead, m_predCount, m_histSize, prediction);
        if(actualOutcome != 0.0)
            RingPush(m_errHistory, m_errHead, m_errCount, m_histSize, prediction - actualOutcome);
        return true;
    }
    // ... rest of methods use RingGet() instead of .At()
};
```

---

### 2.3 Fix `CNeuralNetworkStrategy` Training Buffer

The training buffer uses `CArrayObj` with `new CTrainingExample()` per sample — heap fragmentation on every observation.

**Replace with a fixed-size ring buffer of stack-allocated structs:**

Change `CTrainingExample` from a class (heap) to a struct (stack-compatible):
```cpp
// Replace the class with a plain struct
struct STrainingExample
{
    double   inputs[25];
    int      expectedOutput;
    double   actualResult;
    datetime time;
    bool     hasResult;
    bool     linkedToTrade;
    bool     pseudoLabeled;
    datetime labelDueTime;
    double   entryPriceSnapshot;
    int      barsAhead;
    string   predictionId;

    void Reset()
    {
        ArrayInitialize(inputs, 0.0);
        expectedOutput    = 0;
        actualResult      = 0.0;
        time              = 0;
        hasResult         = false;
        linkedToTrade     = false;
        pseudoLabeled     = false;
        labelDueTime      = 0;
        entryPriceSnapshot = 0.0;
        barsAhead         = 1;
        predictionId      = "";
    }
};
```

Replace `CArrayObj m_trainingData` with:
```cpp
static const int MAX_TRAINING_EXAMPLES = 2000;
STrainingExample m_trainingBuffer[MAX_TRAINING_EXAMPLES];
int m_trainHead;     // Ring write pointer
int m_trainCount;    // Number of valid entries (≤ MAX_TRAINING_EXAMPLES)
```

Update all `m_trainingData.Add()`, `m_trainingData.At()`, `m_trainingData.Total()` calls to use the ring buffer. **No more `new` / `delete` on training data.**

---

## SECTION 3 — Indicator Handle Caching

### 3.1 The Problem

Anywhere an indicator is created inside a function that runs per tick (like `GetEMA()` in `SRTradingStrategies.mqh`, `GetATR()` in `TrendEntryTypes.mqh`), the pattern is:
```cpp
int handle = iMA(...);    // Creates handle
CopyBuffer(handle, ...);  // Reads one value
IndicatorRelease(handle); // Destroys handle
```

This runs on every tick / signal check. Handle creation has overhead. Over 10,000 ticks this accumulates significantly.

### 3.2 The Fix — Universal Indicator Cache

Create `Core/Utils/IndicatorCache.mqh`:

```cpp
#ifndef __INDICATOR_CACHE_MQH__
#define __INDICATOR_CACHE_MQH__

// Simple per-class handle caching pattern.
// Each class that needs indicators declares handles as members,
// creates them in Initialize(), releases them in Deinit().
// This file provides naming conventions and a lookup helper.

// Pattern every class MUST follow:
// 
//   private:
//     int m_atrHandle;    // Cached ATR(14) handle
//     int m_emaHandle;    // Cached EMA handle
//
//   bool Initialize(...)
//   {
//     m_atrHandle = iATR(symbol, timeframe, 14);
//     if(m_atrHandle == INVALID_HANDLE) return false;
//     return true;
//   }
//
//   void Deinit()
//   {
//     if(m_atrHandle != INVALID_HANDLE) { IndicatorRelease(m_atrHandle); m_atrHandle = INVALID_HANDLE; }
//   }
//
//   double GetATR()  // Uses cached handle — no handle create/destroy
//   {
//     double buf[1];
//     ArraySetAsSeries(buf, true);
//     if(CopyBuffer(m_atrHandle, 0, 1, 1, buf) > 0) return buf[0];
//     return 0.0;
//   }

#endif // __INDICATOR_CACHE_MQH__
```

**Files that need this fix (handle created inside a function — convert to cached member):**

| File | Function | Handle To Cache |
|---|---|---|
| `SRTradingStrategies.mqh` | `GetEMA()` | `m_emaFastHandle`, `m_emaSlowHandle` |
| `TrendEntryTypes.mqh` | `GetATR()` | `m_atrHandle` |
| `MultiEMASystem.mqh` | `GetEMASlope()` | Already has handles — just use them |
| `NeuralNetworkStrategy.mqh` | Inside `ExtractFeatures()` if any per-tick `iATR()` / `iMA()` calls exist | Audit and cache all |

For each file: move handle creation to `Initialize()`, release in `Deinit()`/destructor, replace per-tick function calls with cached-handle reads.

---

## SECTION 4 — Inference Caching / Signal Staleness

### 4.1 The Problem

Every call to `GetSignal()` on `CNeuralNetworkStrategy` or `CNextGenStrategyBrain` runs the full forward pass. For the Transformer this means full attention computation (O(seqLen²) per layer × numLayers). If the EA calls `GetSignal()` on every tick but new bar data hasn't arrived, this is pure waste.

### 4.2 The Fix — Bar-Stamp Cache

Add to any AI strategy class:

```cpp
private:
    ENUM_TRADE_SIGNAL m_cachedSignal;
    double            m_cachedConfidence;
    datetime          m_cacheBarTime;    // Bar open time of last inference

bool NeedsNewInference()
{
    datetime currentBarTime = iTime(m_symbol, m_timeframe, 0);
    return (currentBarTime != m_cacheBarTime);
}

ENUM_TRADE_SIGNAL GetSignalCached(double &confidence)
{
    if(!NeedsNewInference())
    {
        confidence = m_cachedConfidence;
        return m_cachedSignal;
    }

    // Run actual inference
    SEnhancedTradeSignal signal;
    if(!GetSignal(signal))
    {
        m_cachedSignal     = TRADE_SIGNAL_NONE;
        m_cachedConfidence = 0.0;
    }
    else
    {
        m_cachedSignal     = signal.signal;
        m_cachedConfidence = signal.confidence;
    }

    m_cacheBarTime = iTime(m_symbol, m_timeframe, 0);
    confidence = m_cachedConfidence;
    return m_cachedSignal;
}
```

All external callers (the EA's `OnTick`) should call `GetSignalCached()` instead of `GetSignal()`. **Transformer runs at most once per bar, not once per tick.**

---

## SECTION 5 — Initialization Chain — Decouple Optional from Mandatory

### 5.1 The Problem

The EA's init chain looks like:
```cpp
if(!m_srDetector.Initialize(...)) return false;        // MANDATORY?
if(!m_trendDetector.Initialize(...)) return false;     // MANDATORY?
if(!m_transformerBrain.Initialize(...)) return false;  // OPTIONAL
if(!m_ensembleSystem.Initialize(...)) return false;    // OPTIONAL
```

One optional component failing kills the whole EA. There's no distinction between "the EA can't work without this" vs "this is a nice-to-have that can be disabled."

### 5.2 The Fix — Two-Tier Init

Split initialization into two tiers:

```cpp
bool InitializeMandatory()
{
    // EA cannot function without these
    if(!m_tradeManager.Initialize(...))   { Print("[INIT] FATAL: TradeManager failed"); return false; }
    if(!m_riskManager.Initialize(...))    { Print("[INIT] FATAL: RiskManager failed"); return false; }
    return true;
}

bool InitializeOptional()
{
    // Failures here are logged but don't kill the EA
    bool allOk = true;

    if(m_useAI)
    {
        if(!m_transformerBrain.Initialize())
        {
            Print("[INIT] WARNING: Transformer failed to init — AI disabled");
            m_useAI = false;
            allOk = false;
        }
    }

    if(m_useSRStrategy)
    {
        if(!m_srDetector.Initialize(...))
        {
            Print("[INIT] WARNING: S/R Detector failed — S/R strategy disabled");
            m_useSRStrategy = false;
            allOk = false;
        }
    }

    // ... etc for each optional strategy

    return allOk;  // Returns false but EA continues
}

int OnInit()
{
    if(!InitializeMandatory()) return INIT_FAILED;
    InitializeOptional();      // Failure here is NOT fatal
    return INIT_SUCCEEDED;
}
```

---

## SECTION 6 — Remove Duplicate Softmax / Normalize in `NextGenStrategyBrain`

`NextGenStrategyBrain::GetSignal()` runs softmax manually on top of `m_transformerBrain.Forward()` output:
```cpp
double maxVal = MathMax(buyProb, MathMax(sellProb, holdProb));
double expBuy = MathExp(buyProb - maxVal);
// ...
buyProb = expBuy / sumExp;
```

But `CTransformerBrain::GetPredictions()` already applies softmax internally via `ComputeClassProbabilities()`. The result is softmax being applied **twice** to the same output. Remove the manual softmax from `NextGenStrategyBrain` and use `GetPredictions()` directly (as shown in Section 1.1's replacement block).

---

## SECTION 7 — Files to Audit for Redundant State

These fields exist in multiple classes and appear to track the same thing:

| Field | Found In | Action |
|---|---|---|
| `m_totalTrades` | `NextGenStrategyBrain`, plus individual strategies | Consolidate into one source of truth |
| `m_lastLoss` | `NeuralNetworkStrategy`, `TransformerBrain` separately | Both track loss — one should be authoritative |
| `m_initialized` | Almost every class | Audit — some classes never check it before use |
| `m_symbol`, `m_timeframe` | Every class individually | Consider passing via context struct instead of storing in 10+ places |

---

## SUMMARY OF CHANGES

| Change | Files Affected | Speed Impact |
|---|---|---|
| Remove Python bridge dead code | `NextGenStrategyBrain.mqh` | Minor (removes dead branch per call) |
| Remove no-op lifecycle stubs | Transformer, Ensemble, NextGen | Negligible (code size) |
| Remove `m_inputSequence` copy | `TransformerBrain.mqh` | 1 less array copy per inference |
| Remove `m_output` copy | `TransformerBrain.mqh` | 1 less array copy per inference |
| Ring buffer for `CMarketDataProcessor` | `NextGenStrategyBrain.mqh` | Eliminates O(n) shift every tick |
| Ring buffer for `CUncertaintyQuantifier` | `UncertaintyQuantifier.mqh` | Eliminates O(n) shift per prediction |
| Ring buffer for training data | `NeuralNetworkStrategy.mqh` | Eliminates heap alloc/free per observation |
| Cache indicator handles | SR, Trend, MultiEMA files | Removes handle create/destroy per tick |
| Inference cache (bar stamp) | All AI strategy classes | Transformer runs 1x/bar not 1x/tick |
| Decouple mandatory/optional init | Main EA file | Optional failures no longer kill EA |
| Remove double softmax | `NextGenStrategyBrain.mqh` | Removes incorrect duplicate normalization |

---

*AXIOM Engineering Studio | Codex Spec Doc 1 of 3*
