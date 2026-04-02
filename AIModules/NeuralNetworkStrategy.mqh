//+------------------------------------------------------------------+
//| NeuralNetworkStrategy.mqh                                        |
//| Complete 3-Layer Feedforward Neural Network for Trading         |
//| Implementation based on neural_networks.md specification        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

#ifndef __NEURAL_NETWORK_STRATEGY_MQH__
#define __NEURAL_NETWORK_STRATEGY_MQH__

// Network architecture: 25→15→10→3 (Input→Hidden1→Hidden2→Output)
//TODO: - Increase architecture, indicators and more to make it bigger and more smart

#include "../Core/Utils/Enums.mqh"
#include "../Core/AI/NNModelStorage.mqh"
#include "../Core/AI/AIFeatureVectorBuilder.mqh"
#include "../IndicatorManager.mqh"
#include "TransformerBrain.mqh"

#define NN_CHECKPOINT_MAGIC 1313758027
#define NN_CHECKPOINT_VERSION 2
#define NN_MAX_PERSISTED_SAMPLES 300
#define NN_MAX_TRAINING_EXAMPLES 2000

//+------------------------------------------------------------------+
//| Training Example Structure                                       |
//+------------------------------------------------------------------+
struct STrainingExample
{
    double inputs[25];
    int expectedOutput;     // 0=None, 1=Buy, 2=Sell
    double actualResult;    // Profit/loss from this trade
    datetime time;
    bool hasResult;
    bool linkedToTrade;
    string predictionId;
    bool pseudoLabeled;
    datetime labelDueTime;
    double entryPriceSnapshot;
    int barsAhead;
    bool isTradeLinked;
    
    void Reset()
    {
        ArrayInitialize(inputs, 0.0);
        expectedOutput = 0;
        actualResult = 0.0;
        time = 0;
        hasResult = false;
        linkedToTrade = false;
        predictionId = "";
        pseudoLabeled = false;
        labelDueTime = 0;
        entryPriceSnapshot = 0.0;
        barsAhead = 1;
        isTradeLinked = false;
    }

    STrainingExample()
    {
        Reset();
    }
};

//+------------------------------------------------------------------+
//| Neural Network Strategy Class                                    |
//+------------------------------------------------------------------+

class CNeuralNetworkStrategy
{
private:
    // Network weights
    double W1[25][15];       // Input → Hidden1
    double W2[15][10];       // Hidden1 → Hidden2
    double W3[10][3];        // Hidden2 → Output
    
    // Biases
    double B1[15];
    double B2[10];
    double B3[3];
    
    // Training configuration
    double m_learningRate;
    int m_epoch;
    double m_lastLoss;
    
    // Training data
    STrainingExample m_trainingBuffer[NN_MAX_TRAINING_EXAMPLES];
    int m_trainHead;
    int m_trainCount;
    int m_minTrainingExamples;
    int m_maxTrainingExamples;
    int m_resultMatchWindowSec;
    int m_predictionCounter;
    
    // Symbol and timeframe
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    bool m_initialized;
    bool m_enableOnlineTraining;
    bool m_allowWeightMutation;
    bool m_enablePseudoLabeling;
    int m_pseudoLabelBarsAhead;
    int m_sampleIntervalSec;
    int m_checkpointEveryLabeled;
    int m_labeledSinceCheckpoint;
    datetime m_lastObservationTime;
    datetime m_lastPseudoLabelProcessTime;
    datetime m_lastSignalLogTime;
    datetime m_lastExplorationLogTime;
    datetime m_lastIndicatorWarningTime;
    datetime m_lastCheckpointTimestamp;
    string m_lastLoadStatus;
    int m_totalObservations;
    int m_tradeLinkedLabels;
    int m_pseudoLabels;
    int m_trainingSteps;
    int m_checkpointWrites;
    ENUM_TRADE_SIGNAL m_cachedSignal;
    double m_cachedConfidence;
    datetime m_cacheBarTime;
    bool m_hasCachedSignal;
    CTransformerBrain* m_transformerRef;
    bool m_ownsTransformerRef;
    double m_lastTransformerInput[];
    int m_lastTransformerSeqLen;
    datetime m_lastFeatureValidationLogTime;
    
public:
    CNeuralNetworkStrategy() : 
        m_learningRate(0.001),
        m_epoch(0),
        m_lastLoss(0.0),
        m_minTrainingExamples(20),  // Reduced from 100 for faster startup
        m_maxTrainingExamples(2000),
        m_resultMatchWindowSec(86400),
        m_predictionCounter(0),
        m_symbol(""),
        m_timeframe(PERIOD_CURRENT),
        m_initialized(false),
        m_enableOnlineTraining(false),
        m_allowWeightMutation(false),
        m_enablePseudoLabeling(false),
        m_pseudoLabelBarsAhead(1),
        m_sampleIntervalSec(30),
        m_checkpointEveryLabeled(10),
        m_labeledSinceCheckpoint(0),
        m_lastObservationTime(0),
        m_lastPseudoLabelProcessTime(0),
        m_lastSignalLogTime(0),
        m_lastExplorationLogTime(0),
        m_lastIndicatorWarningTime(0),
        m_lastCheckpointTimestamp(0),
        m_lastLoadStatus("UNINITIALIZED"),
        m_totalObservations(0),
        m_tradeLinkedLabels(0),
        m_pseudoLabels(0),
        m_trainingSteps(0),
        m_checkpointWrites(0),
        m_cachedSignal(TRADE_SIGNAL_NONE),
        m_cachedConfidence(0.0),
        m_cacheBarTime(0),
        m_hasCachedSignal(false),
        m_transformerRef(NULL),
        m_ownsTransformerRef(false),
        m_lastTransformerSeqLen(0),
        m_lastFeatureValidationLogTime(0)
    {
        m_trainHead = 0;
        m_trainCount = 0;
        for(int i = 0; i < NN_MAX_TRAINING_EXAMPLES; i++)
            m_trainingBuffer[i].Reset();
    }

private:
    int GetTrainingCapacity() const
    {
        return MathMax(1, MathMin(m_maxTrainingExamples, NN_MAX_TRAINING_EXAMPLES));
    }

    int TrainingPhysicalIndex(const int logicalIndex) const
    {
        if(logicalIndex < 0 || logicalIndex >= m_trainCount)
            return -1;

        int capacity = GetTrainingCapacity();
        if(capacity <= 0)
            return -1;

        return (m_trainHead - m_trainCount + logicalIndex + capacity) % capacity;
    }

    void ClearTrainingData()
    {
        int capacity = GetTrainingCapacity();
        for(int i = 0; i < capacity; i++)
            m_trainingBuffer[i].Reset();
        m_trainHead = 0;
        m_trainCount = 0;
    }

    bool EnsureTransformerFeatureExtractor()
    {
        if(m_transformerRef != NULL)
            return true;

        m_transformerRef = new CTransformerBrain(TRANSFORMER_D_MODEL_DEFAULT,
                                                 TRANSFORMER_NUM_HEADS_DEFAULT,
                                                 TRANSFORMER_NUM_LAYERS_A_DEFAULT,
                                                 TRANSFORMER_D_FF_DEFAULT,
                                                 TRANSFORMER_MAX_SEQ_LEN_DEFAULT,
                                                 TRANSFORMER_LR_A_DEFAULT);
        if(m_transformerRef == NULL)
            return false;

        m_ownsTransformerRef = true;
        return true;
    }

    void LogFeatureValidationFailure(const int zeroCount,
                                     const int nanCount,
                                     const int criticalZeroCount)
    {
        datetime now = TimeCurrent();
        if(m_lastFeatureValidationLogTime == 0 || (now - m_lastFeatureValidationLogTime) >= 60)
        {
            PrintFormat("[NN] Feature validation failed: zeros=%d | nan=%d | critical_zeros=%d | Symbol=%s | TF=%s",
                        zeroCount,
                        nanCount,
                        criticalZeroCount,
                        m_symbol,
                        EnumToString(m_timeframe));
            m_lastFeatureValidationLogTime = now;
        }
    }

    bool ValidateFeatures(const double &features[])
    {
        if(ArraySize(features) < 25)
            return false;

        int zeroCount = 0;
        int nanCount = 0;
        int criticalZeroCount = 0;
        int criticalIndices[6] = {1, 2, 3, 4, 13, 23};

        for(int i = 0; i < 25; i++)
        {
            if(!MathIsValidNumber(features[i]))
                nanCount++;
            if(MathAbs(features[i]) <= 1e-9)
                zeroCount++;
        }

        for(int c = 0; c < 6; c++)
        {
            int idx = criticalIndices[c];
            if(idx >= 0 && idx < 25 && MathAbs(features[idx]) <= 1e-9)
                criticalZeroCount++;
        }

        if(nanCount > 0)
        {
            LogFeatureValidationFailure(zeroCount, nanCount, criticalZeroCount);
            return false;
        }

        if(criticalZeroCount >= 4 || zeroCount > 14)
        {
            LogFeatureValidationFailure(zeroCount, nanCount, criticalZeroCount);
            return false;
        }

        return true;
    }

    bool ApplyTransformerFeatureBridge(double &features[])
    {
        if(ArraySize(features) < 25)
            return false;
        if(!EnsureTransformerFeatureExtractor() || m_transformerRef == NULL)
            return false;

        int sequenceLength = MathMin(8, TRANSFORMER_SHORT_SEQ_LEN_DEFAULT);
        if(sequenceLength <= 0)
            sequenceLength = 4;
        if(!CAIFeatureVectorBuilder::BuildTransformerInput(m_symbol, m_timeframe, m_lastTransformerInput, TRANSFORMER_D_MODEL_DEFAULT, sequenceLength))
            return false;

        m_lastTransformerSeqLen = sequenceLength;
        double encodedFeatures[];
        if(!m_transformerRef.GetEncodedFeatures(m_lastTransformerInput, m_lastTransformerSeqLen, encodedFeatures))
            return false;

        int encodedSize = ArraySize(encodedFeatures);
        if(encodedSize <= 0)
            return false;

        int step = MathMax(1, encodedSize / 10);
        for(int i = 0; i < 10; i++)
        {
            int idx = MathMin(encodedSize - 1, i * step);
            features[15 + i] = MathMax(-3.0, MathMin(3.0, encodedFeatures[idx]));
        }

        return true;
    }

    void PushTrainingExample(STrainingExample &example)
    {
        int capacity = GetTrainingCapacity();
        if(capacity <= 0)
            return;

        m_trainingBuffer[m_trainHead] = example;
        m_trainHead = (m_trainHead + 1) % capacity;
        if(m_trainCount < capacity)
            m_trainCount++;
    }

    datetime GetCurrentBarTime() const
    {
        if(m_symbol == "")
            return 0;
        return iTime(m_symbol, m_timeframe, 0);
    }

    bool NeedsNewInference(const datetime currentBarTime) const
    {
        return (!m_hasCachedSignal || currentBarTime <= 0 || currentBarTime != m_cacheBarTime);
    }

    void UpdateSignalCache(const datetime currentBarTime, const ENUM_TRADE_SIGNAL signal, const double confidence)
    {
        m_cachedSignal = signal;
        m_cachedConfidence = confidence;
        m_cacheBarTime = currentBarTime;
        m_hasCachedSignal = true;
    }

public:

    bool ReservePredictionForSignal(const ENUM_TRADE_SIGNAL signal, string &predictionId, const int maxAgeSec = 600)
    {
        predictionId = "";
        if(!m_enableOnlineTraining)
            return false;

        int expectedOutput = 0;
        if(signal == TRADE_SIGNAL_BUY)
            expectedOutput = 1;
        else if(signal == TRADE_SIGNAL_SELL)
            expectedOutput = 2;
        else
            return false;

        datetime now = TimeCurrent();
        for(int i = m_trainCount - 1; i >= 0; i--)
        {
            int physicalIndex = TrainingPhysicalIndex(i);
            if(physicalIndex < 0)
                continue;
            if(m_trainingBuffer[physicalIndex].expectedOutput != expectedOutput ||
               m_trainingBuffer[physicalIndex].hasResult ||
               m_trainingBuffer[physicalIndex].linkedToTrade)
                continue;

            int ageSec = (int)(now - m_trainingBuffer[physicalIndex].time);
            if(ageSec < 0 || ageSec > maxAgeSec)
                continue;

            m_trainingBuffer[physicalIndex].linkedToTrade = true;
            m_trainingBuffer[physicalIndex].isTradeLinked = true;
            predictionId = m_trainingBuffer[physicalIndex].predictionId;
            return (predictionId != "");
        }

        // Force-create a trade-linked observation when no recent sample exists.
        string forcedPredictionId = "";
        if(CollectObservationInternal(true, expectedOutput, forcedPredictionId))
        {
            predictionId = forcedPredictionId;
            return (predictionId != "");
        }

        return false;
    }

    void ReleasePredictionReservation(const string predictionId)
    {
        if(predictionId == "")
            return;

        for(int i = m_trainCount - 1; i >= 0; i--)
        {
            int physicalIndex = TrainingPhysicalIndex(i);
            if(physicalIndex < 0)
                continue;
            if(m_trainingBuffer[physicalIndex].predictionId == predictionId &&
               !m_trainingBuffer[physicalIndex].hasResult)
            {
                m_trainingBuffer[physicalIndex].linkedToTrade = false;
                m_trainingBuffer[physicalIndex].isTradeLinked = false;
                return;
            }
        }
    }

    bool UpdateTradeResultByPredictionId(const string predictionId, const double profitLoss)
    {
        if(!m_enableOnlineTraining || predictionId == "")
            return false;

        for(int i = m_trainCount - 1; i >= 0; i--)
        {
            int physicalIndex = TrainingPhysicalIndex(i);
            if(physicalIndex < 0)
                continue;
            if(m_trainingBuffer[physicalIndex].predictionId == predictionId)
            {
                bool wasLabeled = m_trainingBuffer[physicalIndex].hasResult;
                bool wasPseudo = m_trainingBuffer[physicalIndex].pseudoLabeled;

                m_trainingBuffer[physicalIndex].actualResult = profitLoss;
                m_trainingBuffer[physicalIndex].hasResult = true;
                m_trainingBuffer[physicalIndex].linkedToTrade = true;
                m_trainingBuffer[physicalIndex].isTradeLinked = true;
                m_trainingBuffer[physicalIndex].pseudoLabeled = false;

                if(!wasLabeled)
                {
                    m_tradeLinkedLabels++;
                    m_labeledSinceCheckpoint++;
                }
                else if(wasPseudo)
                {
                    if(m_pseudoLabels > 0)
                        m_pseudoLabels--;
                    m_tradeLinkedLabels++;
                    m_labeledSinceCheckpoint++;
                }

                PrintFormat("[NEURAL-NET] Updated trade result by prediction ID %s: %.2f",
                            predictionId, profitLoss);

                if(!wasLabeled || wasPseudo)
                    HandleNewLabeledData();

                return true;
            }
        }

        return false;
    }
    
    ~CNeuralNetworkStrategy()
    {
        if(m_initialized && m_enableOnlineTraining)
            SaveCheckpointAtomic(true);
        if(m_ownsTransformerRef && CheckPointer(m_transformerRef) == POINTER_DYNAMIC)
            delete m_transformerRef;
        m_transformerRef = NULL;
        m_ownsTransformerRef = false;
        ClearTrainingData();
    }
    
    bool Initialize(string symbol, ENUM_TIMEFRAMES timeframe)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_initialized = true;
        m_cachedSignal = TRADE_SIGNAL_NONE;
        m_cachedConfidence = 0.0;
        m_cacheBarTime = 0;
        m_hasCachedSignal = false;

        // Online training + persistence enabled in live runtime.
        bool loaded = false;
        if(m_enableOnlineTraining)
            loaded = LoadCheckpoint();

        if(!loaded)
        {
            InitializeNetwork();
            m_lastLoadStatus = "COLD_START";
            m_lastCheckpointTimestamp = TimeCurrent();
            SaveCheckpointAtomic(true);
            PrintFormat("[NEURAL-NET] Model checkpoint COLD_START | Symbol=%s | TF=%s",
                        m_symbol, EnumToString(m_timeframe));
        }
        
        PrintFormat("[NEURAL-NET] Initialized for %s on %s | LoadState=%s",
                    symbol, EnumToString(timeframe), m_lastLoadStatus);
        return true;
    }

    void SetTransformerRef(CTransformerBrain* transformerRef, const bool takeOwnership = false)
    {
        if(m_ownsTransformerRef && CheckPointer(m_transformerRef) == POINTER_DYNAMIC && m_transformerRef != transformerRef)
            delete m_transformerRef;

        m_transformerRef = transformerRef;
        m_ownsTransformerRef = takeOwnership;
    }

    void SetOnlineTrainingEnabled(const bool enabled)
    {
        m_enableOnlineTraining = enabled;
        if(!enabled)
        {
            m_enablePseudoLabeling = false;
            m_allowWeightMutation = false;
        }
    }

    void SetWeightMutationEnabled(const bool enabled)
    {
        // Weight mutation is intentionally opt-in and must never bypass runtime risk controls.
        m_allowWeightMutation = (enabled && m_enableOnlineTraining);
    }

    void ConfigureOnlineLearning(const bool enablePseudoLabeling,
                                 const int pseudoLabelBarsAhead,
                                 const int sampleIntervalSeconds,
                                 const int checkpointEveryLabeled)
    {
        m_enablePseudoLabeling = (m_enableOnlineTraining && enablePseudoLabeling);
        m_pseudoLabelBarsAhead = MathMax(1, pseudoLabelBarsAhead);
        m_sampleIntervalSec = MathMax(1, sampleIntervalSeconds);
        m_checkpointEveryLabeled = MathMax(1, checkpointEveryLabeled);

        PrintFormat("[NEURAL-NET] Online config | Symbol=%s | Online=%s | WeightMutation=%s | Pseudo=%s | BarsAhead=%d | SampleSec=%d | CkptEvery=%d",
                    m_symbol,
                    m_enableOnlineTraining ? "ON" : "OFF",
                    m_allowWeightMutation ? "ON" : "OFF",
                    m_enablePseudoLabeling ? "ON" : "OFF",
                    m_pseudoLabelBarsAhead,
                    m_sampleIntervalSec,
                    m_checkpointEveryLabeled);
    }

    void TickOnlineLearning()
    {
        if(!m_initialized || !m_enableOnlineTraining)
            return;

        CollectObservation();
        ProcessPseudoLabels();
    }
    
    void InitializeNetwork()
    {
        // Xavier initialization for better convergence
        double xavier_input = MathSqrt(2.0 / 25);
        double xavier_hidden1 = MathSqrt(2.0 / 15);
        double xavier_hidden2 = MathSqrt(2.0 / 10);
        
        // Local deterministic seeding for reproducibility
        m_randomState = 12345; // Fixed seed

        // Initialize W1
        for(int i = 0; i < 25; i++)
        {
            for(int j = 0; j < 15; j++)
            {
                W1[i][j] = (GetDeterministicRandom() - 0.5) * 2 * xavier_input;
            }
        }
        
        // Initialize W2
        for(int i = 0; i < 15; i++)
        {
            for(int j = 0; j < 10; j++)
            {
                W2[i][j] = (GetDeterministicRandom() - 0.5) * 2 * xavier_hidden1;
            }
        }
        
        // Initialize W3
        for(int i = 0; i < 10; i++)
        {
            for(int j = 0; j < 3; j++)
            {
                W3[i][j] = (GetDeterministicRandom() - 0.5) * 2 * xavier_hidden2;
            }
        }
        
        // Initialize biases to small values
        for(int i = 0; i < 15; i++)
            B1[i] = 0.01;
        
        for(int i = 0; i < 10; i++)
            B2[i] = 0.01;
        
        for(int i = 0; i < 3; i++)
            B3[i] = 0.01;
        
        Print("[NEURAL-NET] Network weights initialized with Deterministic Xavier method");
    }

    // Simple LCG for deterministic behavior
    uint m_randomState;
    double GetDeterministicRandom()
    {
        m_randomState = m_randomState * 1664525 + 1013904223;
        return (double)m_randomState / 4294967296.0;
    }
    
    // Helper to get indicator value from buffer
    double GetIndicatorValue(int handle, int buffer, int shift)
    {
        if(handle == INVALID_HANDLE)
            return 0.0;

        double val[1];
        if(CopyBuffer(handle, buffer, shift, 1, val) > 0)
            return val[0];
        return 0.0;
    }

    void WarnIndicatorIssue(const string indicatorName)
    {
        datetime now = TimeCurrent();
        if(m_lastIndicatorWarningTime == 0 || (now - m_lastIndicatorWarningTime) >= 60)
        {
            PrintFormat("[NEURAL-NET] Indicator handle unavailable: %s | Symbol=%s | TF=%s",
                        indicatorName, m_symbol, EnumToString(m_timeframe));
            m_lastIndicatorWarningTime = now;
        }
    }

    // Helper for MA value
    double GetMAValue(int period, int shift, ENUM_MA_METHOD method, ENUM_APPLIED_PRICE price, int bar)
    {
        CIndicatorManager* ind = CIndicatorManager::Instance();
        if(ind == NULL)
            return 0.0;

        int handle = ind.GetMAHandle(m_symbol, m_timeframe, period, shift, method, price);
        if(handle == INVALID_HANDLE)
        {
            WarnIndicatorIssue("MA");
            return 0.0;
        }

        return GetIndicatorValue(handle, 0, bar);
    }

    // Helper for RSI value
    double GetRSIValue(int period, ENUM_APPLIED_PRICE price, int bar)
    {
        CIndicatorManager* ind = CIndicatorManager::Instance();
        if(ind == NULL)
            return 0.0;

        int handle = ind.GetRSIHandle(m_symbol, m_timeframe, period, price);
        if(handle == INVALID_HANDLE)
        {
            WarnIndicatorIssue("RSI");
            return 0.0;
        }

        return GetIndicatorValue(handle, 0, bar);
    }

    // Helper for ATR value
    double GetATRValue(int period, int bar)
    {
        CIndicatorManager* ind = CIndicatorManager::Instance();
        if(ind == NULL)
            return 0.0;

        int handle = ind.GetATRHandle(m_symbol, m_timeframe, period);
        if(handle == INVALID_HANDLE)
        {
            WarnIndicatorIssue("ATR");
            return 0.0;
        }

        return GetIndicatorValue(handle, 0, bar);
    }

    // Helper for ADX value
    double GetADXValue(int period, int bar)
    {
        CIndicatorManager* ind = CIndicatorManager::Instance();
        if(ind == NULL)
            return 0.0;

        int handle = ind.GetADXHandle(m_symbol, m_timeframe, period);
        if(handle == INVALID_HANDLE)
        {
            WarnIndicatorIssue("ADX");
            return 0.0;
        }

        return GetIndicatorValue(handle, 0, bar);
    }

    // Helper for Bollinger Bands value
    double GetBBValue(int period, double dev, int shift, ENUM_APPLIED_PRICE price, int buffer, int bar)
    {
        CIndicatorManager* ind = CIndicatorManager::Instance();
        if(ind == NULL)
            return 0.0;

        int handle = ind.GetBandsHandle(m_symbol, m_timeframe, period, shift, dev, price);
        if(handle == INVALID_HANDLE)
        {
            WarnIndicatorIssue("BOLLINGER");
            return 0.0;
        }

        return GetIndicatorValue(handle, buffer, bar);
    }

    // Helper for MACD value
    double GetMACDValue(int fast, int slow, int signal, ENUM_APPLIED_PRICE price, int buffer, int bar)
    {
        CIndicatorManager* ind = CIndicatorManager::Instance();
        if(ind == NULL)
            return 0.0;

        int handle = ind.GetMACDHandle(m_symbol, m_timeframe, fast, slow, signal, price);
        if(handle == INVALID_HANDLE)
        {
            WarnIndicatorIssue("MACD");
            return 0.0;
        }

        return GetIndicatorValue(handle, buffer, bar);
    }

    // Helper for CCI value
    double GetCCIValue(int period, ENUM_APPLIED_PRICE price, int bar)
    {
        CIndicatorManager* ind = CIndicatorManager::Instance();
        if(ind == NULL)
            return 0.0;

        int handle = ind.GetCCIHandle(m_symbol, m_timeframe, period, price);
        if(handle == INVALID_HANDLE)
        {
            WarnIndicatorIssue("CCI");
            return 0.0;
        }

        return GetIndicatorValue(handle, 0, bar);
    }

    // Extract 25 features from current market state
    bool ExtractFeatures(double &features[])
    {
        if(!m_initialized || ArraySize(features) < 25)
        {
            ArrayResize(features, 25);
        }
        
        // Initialize all features to 0
        ArrayInitialize(features, 0.0);
        
        // --- Market Structure (Features 0-4) ---
        // Feature 0: Trend Direction based on MA Cross (Fast vs Slow)
        double maFast = GetMAValue(9, 0, MODE_EMA, PRICE_CLOSE, 1);
        double maSlow = GetMAValue(21, 0, MODE_EMA, PRICE_CLOSE, 1);
        features[0] = (maFast > maSlow) ? 1.0 : (maFast < maSlow) ? -1.0 : 0.0;
        
        // Feature 1: Trend Strength (ADX)
        double adx = GetADXValue(14, 1);
        features[1] = GetNormalizedValue(0, 100, adx);

        // Feature 2: Momentum (RSI)
        double rsi = GetRSIValue(14, PRICE_CLOSE, 1);
        features[2] = GetNormalizedValue(0, 100, rsi);
        
        // Feature 3: Price vs EMA200 (Long term trend)
        double ema200 = GetMAValue(200, 0, MODE_EMA, PRICE_CLOSE, 1);
        double close = iClose(m_symbol, m_timeframe, 1);
        features[3] = (close > ema200) ? 1.0 : -1.0;
        
        // Feature 4: Volatility (ATR Normalized)
        double atr = GetATRValue(14, 1);
        double atrPercent = (close > 0.0) ? (atr / close) * 100.0 : 0.0;
        features[4] = GetNormalizedValue(0.0, 5.0, atrPercent);
        
        // --- Oscillator / Reversion (Features 5-9) ---
        // Feature 5: Stochastic Lookalike (RSI based: Overbought/Oversold)
        features[5] = (rsi > 70) ? 1.0 : (rsi < 30) ? -1.0 : 0.0;
        
        // Feature 6: Bollinger Band Position
        double bbUpper = GetBBValue(20, 2, 0, PRICE_CLOSE, 1, 1); // Buffer 1 = Upper
        double bbLower = GetBBValue(20, 2, 0, PRICE_CLOSE, 2, 1); // Buffer 2 = Lower
        double bbBasis = (bbUpper - bbLower > 0) ? (close - bbLower) / (bbUpper - bbLower) : 0.5;
        features[6] = MathMin(1.0, MathMax(0.0, bbBasis)); // 0 = Lower Band, 1 = Upper Band
        
        // Feature 7: MACD Histogram
        double macdMain = GetMACDValue(12, 26, 9, PRICE_CLOSE, 0, 1); // Buffer 0 = Main
        double macdSignal = GetMACDValue(12, 26, 9, PRICE_CLOSE, 1, 1); // Buffer 1 = Signal
        double macdHist = macdMain - macdSignal;
        features[7] = (macdHist > 0) ? 1.0 : -1.0;
        
        // Feature 8: Williams %R or similar (using RSI delta)
        double rsiPrev = GetRSIValue(14, PRICE_CLOSE, 2);
        features[8] = (rsi - rsiPrev) / 100.0; // Momentum change
        
        // Feature 9: CCI
        double cci = GetCCIValue(14, PRICE_CLOSE, 1);
        features[9] = GetNormalizedValue(-200, 200, cci); // Limit to range usually -1 to 1
        
        // --- Volume / Liquidity Proxy (Features 10-14) ---
        // Feature 10: Volume Trend
        long vol = iVolume(m_symbol, m_timeframe, 1);
        long volPrev = iVolume(m_symbol, m_timeframe, 2);
        features[10] = (vol > volPrev) ? 1.0 : 0.0;
        
        // Feature 11: MFI (Money Flow Index) - approximated via RSI/Vol mix
        features[11] = (rsi > 50 && vol > volPrev) ? 1.0 : 0.0;

        // Feature 12: High/Low Breakout (Donchian-ish)
        double high20 = iHigh(m_symbol, m_timeframe, iHighest(m_symbol, m_timeframe, MODE_HIGH, 20, 1));
        double low20 = iLow(m_symbol, m_timeframe, iLowest(m_symbol, m_timeframe, MODE_LOW, 20, 1));
        features[12] = (close >= high20) ? 1.0 : (close <= low20) ? -1.0 : 0.0;
        
        // Feature 13: Candle Range Quality
        double open = iOpen(m_symbol, m_timeframe, 1);
        double high = iHigh(m_symbol, m_timeframe, 1);
        double low = iLow(m_symbol, m_timeframe, 1);
        double candleRangePct = (close > 0.0) ? ((high - low) / close) * 100.0 : 0.0;
        features[13] = GetNormalizedValue(0.0, 2.0, candleRangePct);
        
        // Feature 14: Gap (Open vs Prev Close)
        double closePrev = iClose(m_symbol, m_timeframe, 2);
        features[14] = (open > closePrev) ? 1.0 : (open < closePrev) ? -1.0 : 0.0;
        
        // --- Price Action (Features 15-19) ---
        double body = MathAbs(close - open);
        double range = high - low;
        double bodyRatio = (range > 0) ? body / range : 0;
        
        features[15] = bodyRatio; // 1 = Marubozu, 0 = Doji
        features[16] = (close > open) ? 1.0 : -1.0; // Bullish/Bearish
        
        // Feature 17: Upper Wick Ratio
        double upperWick = (close > open) ? (high - close) : (high - open);
        features[17] = (range > 0) ? upperWick / range : 0;
        
        // Feature 18: Lower Wick Ratio
        double lowerWick = (close > open) ? (open - low) : (close - low);
        features[18] = (range > 0) ? lowerWick / range : 0;
        
        // Feature 19: Inside Bar check
        double highPrev = iHigh(m_symbol, m_timeframe, 2);
        double lowPrev = iLow(m_symbol, m_timeframe, 2);
        bool insideBar = (high < highPrev) && (low > lowPrev);
        features[19] = insideBar ? 1.0 : 0.0;
        
        // --- Time & Context (Features 20-22) ---
        // Features 20-22: Time/Session
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        features[20] = dt.hour / 24.0;                          // Hour normalized
        features[21] = dt.day_of_week / 7.0;                    // Day normalized
        features[22] = IsKillZoneTime(dt.hour) ? 1.0 : 0.0;   // Kill zone binary
        
        // --- Context Tail Features (23-24) ---
        // Feature 23: Volatility regime ratio (fast ATR / slow ATR proxy)
        double atrFast = GetATRValue(14, 1);
        double atrSlow = GetATRValue(50, 1);
        features[23] = (atrSlow > 0.0) ? MathMin(2.0, atrFast / atrSlow) : 1.0;

        // Feature 24: Bias Unit
        features[24] = 1.0;

        ApplyTransformerFeatureBridge(features);
        return ValidateFeatures(features);
    }
    
    // Forward propagation
    void ForwardPropagate(const double &inputs[], double &outputs[])
    {
        double hidden1[15];
        double hidden2[10];
        
        ArrayResize(outputs, 3);
        
        // Input → Hidden1
        for(int j = 0; j < 15; j++)
        {
            hidden1[j] = B1[j];
            for(int i = 0; i < 25; i++)
            {
                hidden1[j] += inputs[i] * W1[i][j];
            }
            hidden1[j] = ReLU(hidden1[j]);  // Activation
        }
        
        // Hidden1 → Hidden2
        for(int j = 0; j < 10; j++)
        {
            hidden2[j] = B2[j];
            for(int i = 0; i < 15; i++)
            {
                hidden2[j] += hidden1[i] * W2[i][j];
            }
            hidden2[j] = ReLU(hidden2[j]);
        }
        
        // Hidden2 → Output
        for(int j = 0; j < 3; j++)
        {
            outputs[j] = B3[j];
            for(int i = 0; i < 10; i++)
            {
                outputs[j] += hidden2[i] * W3[i][j];
            }
        }
        
        // Softmax activation for output layer
        Softmax(outputs, 3);
    }
    
    bool CollectObservation()
    {
        string ignoredPredictionId = "";
        return CollectObservationInternal(false, 0, ignoredPredictionId);
    }

    void ProcessPseudoLabels()
    {
        if(!m_initialized || !m_enableOnlineTraining || !m_enablePseudoLabeling)
            return;

        datetime now = TimeCurrent();
        if(m_lastPseudoLabelProcessTime > 0 && (now - m_lastPseudoLabelProcessTime) < 5)
            return;
        m_lastPseudoLabelProcessTime = now;

        double currentClose = iClose(m_symbol, m_timeframe, 0);
        if(currentClose <= 0.0)
            currentClose = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        if(currentClose <= 0.0)
            return;

        int pseudoLabeledNow = 0;
        for(int i = 0; i < m_trainCount; i++)
        {
            int physicalIndex = TrainingPhysicalIndex(i);
            if(physicalIndex < 0)
                continue;
            if(m_trainingBuffer[physicalIndex].hasResult ||
               m_trainingBuffer[physicalIndex].linkedToTrade ||
               m_trainingBuffer[physicalIndex].isTradeLinked)
                continue;

            if(m_trainingBuffer[physicalIndex].labelDueTime <= 0 || now < m_trainingBuffer[physicalIndex].labelDueTime)
                continue;

            if(m_trainingBuffer[physicalIndex].expectedOutput != 1 && m_trainingBuffer[physicalIndex].expectedOutput != 2)
                continue;

            if(m_trainingBuffer[physicalIndex].expectedOutput == 1)
                m_trainingBuffer[physicalIndex].actualResult = currentClose - m_trainingBuffer[physicalIndex].entryPriceSnapshot;
            else
                m_trainingBuffer[physicalIndex].actualResult = m_trainingBuffer[physicalIndex].entryPriceSnapshot - currentClose;

            m_trainingBuffer[physicalIndex].hasResult = true;
            m_trainingBuffer[physicalIndex].pseudoLabeled = true;
            m_trainingBuffer[physicalIndex].isTradeLinked = false;
            pseudoLabeledNow++;
        }

        if(pseudoLabeledNow > 0)
        {
            m_pseudoLabels += pseudoLabeledNow;
            m_labeledSinceCheckpoint += pseudoLabeledNow;
            PrintFormat("[NEURAL-NET] Pseudo labels processed: %d | Total pseudo: %d",
                        pseudoLabeledNow, m_pseudoLabels);
            HandleNewLabeledData();
        }
    }

    // Get trading signal from neural network
    ENUM_TRADE_SIGNAL ComputeNeuralSignal(double &confidence)
    {
        confidence = 0.0;
        if(!m_initialized)
            return TRADE_SIGNAL_NONE;

        if(m_enableOnlineTraining)
            CollectObservation();

        double inputs[25];
        if(!ExtractFeatures(inputs))
            return TRADE_SIGNAL_NONE;

        double outputs[3];
        ForwardPropagate(inputs, outputs);

        int labeledCount = GetCompletedTradesCount();
        if(m_enableOnlineTraining && labeledCount < m_minTrainingExamples)
        {
            datetime now = TimeCurrent();
            if(m_lastExplorationLogTime == 0 || (now - m_lastExplorationLogTime) >= 30)
            {
                PrintFormat("[NEURAL-NET] Exploration mode: labeled %d/%d | observations=%d",
                            labeledCount, m_minTrainingExamples, m_totalObservations);
                m_lastExplorationLogTime = now;
            }
        }

        int directionIndex = (outputs[1] >= outputs[2]) ? 1 : 2;
        double directionProb = outputs[directionIndex];
        double noneProb = outputs[0];

        double minDirectionalConfidence = 0.60;
        if(m_enableOnlineTraining && labeledCount < m_minTrainingExamples)
            minDirectionalConfidence = 0.45;

        if(directionProb < minDirectionalConfidence || directionProb <= noneProb)
        {
            datetime now = TimeCurrent();
            if(m_lastSignalLogTime == 0 || (now - m_lastSignalLogTime) >= 15)
            {
                PrintFormat("[NEURAL-NET] HOLD | None: %.2f%% | Buy: %.2f%% | Sell: %.2f%%",
                            noneProb * 100.0, outputs[1] * 100.0, outputs[2] * 100.0);
                m_lastSignalLogTime = now;
            }
            return TRADE_SIGNAL_NONE;
        }

        confidence = directionProb;
        datetime now = TimeCurrent();
        if(m_lastSignalLogTime == 0 || (now - m_lastSignalLogTime) >= 5)
        {
            PrintFormat("[NEURAL-NET] Signal: %s | Confidence: %.2f%% | None: %.2f%% | Buy: %.2f%% | Sell: %.2f%%",
                        (directionIndex == 1 ? "BUY" : "SELL"),
                        directionProb * 100.0, noneProb * 100.0, outputs[1] * 100.0, outputs[2] * 100.0);
            m_lastSignalLogTime = now;
        }

        return (directionIndex == 1) ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;
    }

public:
    ENUM_TRADE_SIGNAL GetNeuralSignalCached(double &confidence)
    {
        confidence = 0.0;
        if(!m_initialized)
            return TRADE_SIGNAL_NONE;

        if(m_enableOnlineTraining)
            CollectObservation();

        datetime currentBarTime = GetCurrentBarTime();
        if(!NeedsNewInference(currentBarTime))
        {
            confidence = m_cachedConfidence;
            return m_cachedSignal;
        }

        ENUM_TRADE_SIGNAL signal = ComputeNeuralSignal(confidence);
        UpdateSignalCache(currentBarTime, signal, confidence);
        return signal;
    }

    ENUM_TRADE_SIGNAL GetNeuralSignal(double &confidence)
    {
        return GetNeuralSignalCached(confidence);
    }
    
    // Update trade result for training
    bool UpdateTradeResult(datetime tradeTime, double profitLoss)
    {
        if(!m_enableOnlineTraining)
            return false;

        int matchedIndex = -1;
        int bestDelta = 2147483647;

        // Match the nearest pending sample generated before the trade close
        for(int i = m_trainCount - 1; i >= 0; i--)
        {
            int physicalIndex = TrainingPhysicalIndex(i);
            if(physicalIndex < 0)
                continue;
            if(m_trainingBuffer[physicalIndex].hasResult)
                continue;

            long delta = (long)(tradeTime - m_trainingBuffer[physicalIndex].time);
            if(delta < 0 || delta > m_resultMatchWindowSec)
                continue;

            if((int)delta < bestDelta)
            {
                bestDelta = (int)delta;
                matchedIndex = i;
            }
        }

        if(matchedIndex < 0)
            return false;

        int matchedPhysicalIndex = TrainingPhysicalIndex(matchedIndex);
        if(matchedPhysicalIndex < 0)
            return false;

        m_trainingBuffer[matchedPhysicalIndex].actualResult = profitLoss;
        m_trainingBuffer[matchedPhysicalIndex].hasResult = true;
        m_trainingBuffer[matchedPhysicalIndex].linkedToTrade = true;
        m_trainingBuffer[matchedPhysicalIndex].isTradeLinked = true;
        m_trainingBuffer[matchedPhysicalIndex].pseudoLabeled = false;
        m_tradeLinkedLabels++;
        m_labeledSinceCheckpoint++;

        PrintFormat("[NEURAL-NET] Updated trade result: %.2f | sample-age: %ds", profitLoss, bestDelta);

        HandleNewLabeledData();
        return true;
    }
    
    // Train network with incremental backprop updates
    void TrainNetwork()
    {
        if(!m_enableOnlineTraining)
            return;

        int labeledIndices[];
        BuildLabeledIndices(labeledIndices);
        int labeledCount = ArraySize(labeledIndices);
        if(labeledCount < m_minTrainingExamples)
            return;

        const int maxSamplesPerCycle = 256;
        const int epochsPerCycle = 2;

        int start = 0;
        if(labeledCount > maxSamplesPerCycle)
            start = labeledCount - maxSamplesPerCycle;

        int processedTotal = 0;
        double aggregatedLoss = 0.0;

        for(int epochIter = 0; epochIter < epochsPerCycle; epochIter++)
        {
            double epochLoss = 0.0;
            int processed = 0;

            for(int i = start; i < labeledCount; i++)
            {
                int physicalIndex = TrainingPhysicalIndex(labeledIndices[i]);
                if(physicalIndex < 0)
                    continue;
                if(!m_trainingBuffer[physicalIndex].hasResult)
                    continue;

                double outputs[3];
                ForwardPropagate(m_trainingBuffer[physicalIndex].inputs, outputs);

                double target[3];
                ArrayInitialize(target, 0.0);
                if(m_trainingBuffer[physicalIndex].actualResult > 0.0)
                    target[m_trainingBuffer[physicalIndex].expectedOutput] = 1.0;
                else
                    target[0] = 1.0;

                double sampleWeight = m_trainingBuffer[physicalIndex].pseudoLabeled ? 0.60 : 1.00;
                double loss = CalculateLoss(outputs, target);
                epochLoss += (loss * sampleWeight);
                processed++;
                if(m_allowWeightMutation)
                    UpdateWeights(m_trainingBuffer[physicalIndex].inputs, outputs, target, sampleWeight);
            }

            if(processed > 0)
            {
                aggregatedLoss += (epochLoss / processed);
                processedTotal += processed;
            }

            m_epoch++;
        }

        if(processedTotal > 0)
        {
            m_lastLoss = aggregatedLoss / epochsPerCycle;
            if(m_allowWeightMutation)
            {
                m_trainingSteps++;
                PrintFormat("[NEURAL-NET] Training step complete | Epoch=%d | Loss=%.6f | Labeled=%d | TrainedSamples=%d",
                            m_epoch, m_lastLoss, labeledCount, processedTotal);
                SaveCheckpointAtomic(false);
            }
            else
            {
                static datetime s_lastMutationDisabledLog = 0;
                datetime now = TimeCurrent();
                if(s_lastMutationDisabledLog == 0 || (now - s_lastMutationDisabledLog) >= 300)
                {
                    PrintFormat("[NEURAL-NET] Weight mutation disabled | Symbol=%s | Labeled=%d | LastLoss=%.6f",
                                m_symbol, labeledCount, m_lastLoss);
                    s_lastMutationDisabledLog = now;
                }
            }
        }
    }
    
    int GetTrainingExampleCount() { return m_trainCount; }
    int GetCompletedTradesCount()
    {
        int count = 0;
        for(int i = 0; i < m_trainCount; i++)
        {
            int physicalIndex = TrainingPhysicalIndex(i);
            if(physicalIndex < 0)
                continue;
            if(m_trainingBuffer[physicalIndex].hasResult)
                count++;
        }
        return count;
    }

    bool SaveNetwork() { return SaveCheckpointAtomic(true); }
    bool LoadNetwork() { return LoadCheckpoint(); }

    bool SaveCheckpointAtomic(const bool forceWrite = false)
    {
        if(!m_enableOnlineTraining || !m_initialized)
            return false;

        if(!forceWrite && m_labeledSinceCheckpoint <= 0)
            return false;

        NNModelStorage_EnsureFolders();

        string primaryFile = NNModelStorage_GetPrimaryPath(m_symbol, m_timeframe);
        string backupFile = NNModelStorage_GetBackupPath(m_symbol, m_timeframe);
        string tempFile = NNModelStorage_GetTempPath(m_symbol, m_timeframe);

        int sampleIndices[];
        BuildPersistedSampleIndices(sampleIndices);
        uint checksum = ComputeCheckpointChecksum(sampleIndices);

        int fileHandle = FileOpen(tempFile, FILE_WRITE | FILE_BIN | FILE_COMMON);
        if(fileHandle == INVALID_HANDLE)
            return false;

        datetime checkpointTime = TimeCurrent();

        FileWriteInteger(fileHandle, NN_CHECKPOINT_MAGIC);
        FileWriteInteger(fileHandle, NN_CHECKPOINT_VERSION);
        FileWriteString(fileHandle, m_symbol);
        FileWriteInteger(fileHandle, (int)m_timeframe);
        FileWriteLong(fileHandle, (long)checkpointTime);
        FileWriteDouble(fileHandle, m_learningRate);
        FileWriteInteger(fileHandle, m_epoch);
        FileWriteDouble(fileHandle, m_lastLoss);
        FileWriteInteger(fileHandle, m_minTrainingExamples);
        FileWriteInteger(fileHandle, m_maxTrainingExamples);
        FileWriteInteger(fileHandle, m_resultMatchWindowSec);
        FileWriteInteger(fileHandle, m_predictionCounter);
        FileWriteInteger(fileHandle, m_enableOnlineTraining ? 1 : 0);
        FileWriteInteger(fileHandle, m_enablePseudoLabeling ? 1 : 0);
        FileWriteInteger(fileHandle, m_pseudoLabelBarsAhead);
        FileWriteInteger(fileHandle, m_sampleIntervalSec);
        FileWriteInteger(fileHandle, m_checkpointEveryLabeled);
        FileWriteInteger(fileHandle, m_totalObservations);
        FileWriteInteger(fileHandle, m_tradeLinkedLabels);
        FileWriteInteger(fileHandle, m_pseudoLabels);
        FileWriteInteger(fileHandle, m_trainingSteps);
        FileWriteInteger(fileHandle, m_checkpointWrites);

        for(int i = 0; i < 25; i++)
            for(int j = 0; j < 15; j++)
                FileWriteDouble(fileHandle, W1[i][j]);
        for(int i = 0; i < 15; i++)
            for(int j = 0; j < 10; j++)
                FileWriteDouble(fileHandle, W2[i][j]);
        for(int i = 0; i < 10; i++)
            for(int j = 0; j < 3; j++)
                FileWriteDouble(fileHandle, W3[i][j]);
        for(int i = 0; i < 15; i++) FileWriteDouble(fileHandle, B1[i]);
        for(int i = 0; i < 10; i++) FileWriteDouble(fileHandle, B2[i]);
        for(int i = 0; i < 3; i++) FileWriteDouble(fileHandle, B3[i]);

        int sampleCount = ArraySize(sampleIndices);
        FileWriteInteger(fileHandle, sampleCount);
        for(int i = 0; i < sampleCount; i++)
        {
            int physicalIndex = TrainingPhysicalIndex(sampleIndices[i]);
            if(physicalIndex < 0)
                continue;
            FileWriteInteger(fileHandle, m_trainingBuffer[physicalIndex].expectedOutput);
            FileWriteDouble(fileHandle, m_trainingBuffer[physicalIndex].actualResult);
            FileWriteLong(fileHandle, (long)m_trainingBuffer[physicalIndex].time);
            FileWriteInteger(fileHandle, m_trainingBuffer[physicalIndex].hasResult ? 1 : 0);
            FileWriteInteger(fileHandle, m_trainingBuffer[physicalIndex].linkedToTrade ? 1 : 0);
            FileWriteString(fileHandle, m_trainingBuffer[physicalIndex].predictionId);
            FileWriteInteger(fileHandle, m_trainingBuffer[physicalIndex].pseudoLabeled ? 1 : 0);
            FileWriteLong(fileHandle, (long)m_trainingBuffer[physicalIndex].labelDueTime);
            FileWriteDouble(fileHandle, m_trainingBuffer[physicalIndex].entryPriceSnapshot);
            FileWriteInteger(fileHandle, m_trainingBuffer[physicalIndex].barsAhead);
            FileWriteInteger(fileHandle, m_trainingBuffer[physicalIndex].isTradeLinked ? 1 : 0);
            for(int k = 0; k < 25; k++)
                FileWriteDouble(fileHandle, m_trainingBuffer[physicalIndex].inputs[k]);
        }

        FileWriteInteger(fileHandle, (int)checksum);
        FileClose(fileHandle);

        if(!NNModelStorage_PromoteTempToPrimary(tempFile, primaryFile, backupFile))
            return false;

        m_checkpointWrites++;
        m_lastCheckpointTimestamp = checkpointTime;
        return true;
    }

    bool LoadCheckpoint()
    {
        if(!m_enableOnlineTraining)
            return false;

        NNModelStorage_EnsureFolders();
        string primaryFile = NNModelStorage_GetPrimaryPath(m_symbol, m_timeframe);
        string backupFile = NNModelStorage_GetBackupPath(m_symbol, m_timeframe);

        if(LoadCheckpointFromPath(primaryFile, "LOADED"))
            return true;
        if(LoadCheckpointFromPath(backupFile, "RESTORED_FROM_BACKUP"))
            return true;
        return false;
    }

    void GetModelHealthStats(int &totalObservations,
                             int &tradeLinkedLabels,
                             int &pseudoLabels,
                             int &pendingLabels,
                             int &trainingSteps,
                             int &checkpointWrites,
                             int &epoch,
                             double &lastLoss)
    {
        totalObservations = m_totalObservations;
        tradeLinkedLabels = m_tradeLinkedLabels;
        pseudoLabels = m_pseudoLabels;
        pendingLabels = GetPendingLabelsCount();
        trainingSteps = m_trainingSteps;
        checkpointWrites = m_checkpointWrites;
        epoch = m_epoch;
        lastLoss = m_lastLoss;
    }
    
private:
    string GeneratePredictionId()
    {
        m_predictionCounter++;
        ulong timePart = (ulong)(GetMicrosecondCount() % 1000000000);
        int seq = m_predictionCounter % 100000;
        return StringFormat("%09I64u%05d", timePart, seq);
    }

    bool CollectObservationInternal(const bool forceSample, const int forcedOutput, string &generatedPredictionId)
    {
        generatedPredictionId = "";
        if(!m_initialized || !m_enableOnlineTraining)
            return false;

        datetime now = TimeCurrent();
        if(!forceSample && m_lastObservationTime > 0 && (now - m_lastObservationTime) < m_sampleIntervalSec)
            return false;

        double inputs[25];
        if(!ExtractFeatures(inputs))
            return false;

        double outputs[3];
        ForwardPropagate(inputs, outputs);

        int expectedOutput = forcedOutput;
        if(expectedOutput <= 0)
            expectedOutput = (outputs[1] >= outputs[2]) ? 1 : 2;

        STrainingExample example;
        for(int i = 0; i < 25; i++)
            example.inputs[i] = inputs[i];

        example.expectedOutput = expectedOutput;
        example.time = now;
        example.predictionId = GeneratePredictionId();
        example.linkedToTrade = (forcedOutput > 0);
        example.isTradeLinked = (forcedOutput > 0);
        example.pseudoLabeled = false;

        int periodSec = PeriodSeconds(m_timeframe);
        if(periodSec <= 0)
            periodSec = 60;

        example.barsAhead = MathMax(1, m_pseudoLabelBarsAhead);
        example.labelDueTime = now + (datetime)(periodSec * example.barsAhead);
        example.entryPriceSnapshot = iClose(m_symbol, m_timeframe, 0);
        if(example.entryPriceSnapshot <= 0.0)
            example.entryPriceSnapshot = SymbolInfoDouble(m_symbol, SYMBOL_BID);

        PushTrainingExample(example);
        generatedPredictionId = example.predictionId;
        m_totalObservations++;
        m_lastObservationTime = now;
        return true;
    }

    int GetPendingLabelsCount()
    {
        int pending = 0;
        for(int i = 0; i < m_trainCount; i++)
        {
            int physicalIndex = TrainingPhysicalIndex(i);
            if(physicalIndex < 0)
                continue;
            if(!m_trainingBuffer[physicalIndex].hasResult)
                pending++;
        }
        return pending;
    }

    void HandleNewLabeledData()
    {
        int checkpointInterval = MathMax(1, m_checkpointEveryLabeled);
        if(m_labeledSinceCheckpoint < checkpointInterval)
            return;

        if(m_allowWeightMutation && GetCompletedTradesCount() >= m_minTrainingExamples)
            TrainNetwork();

        SaveCheckpointAtomic(true);
        m_labeledSinceCheckpoint = 0;
    }

    void BuildLabeledIndices(int &indices[])
    {
        ArrayResize(indices, 0);
        for(int i = 0; i < m_trainCount; i++)
        {
            int physicalIndex = TrainingPhysicalIndex(i);
            if(physicalIndex < 0)
                continue;
            if(!m_trainingBuffer[physicalIndex].hasResult)
                continue;

            int newSize = ArraySize(indices) + 1;
            ArrayResize(indices, newSize);
            indices[newSize - 1] = i;
        }
    }

    void BuildPersistedSampleIndices(int &indices[])
    {
        ArrayResize(indices, 0);
        int total = m_trainCount;

        for(int i = total - 1; i >= 0; i--)
        {
            int physicalIndex = TrainingPhysicalIndex(i);
            if(physicalIndex < 0)
                continue;
            if(!m_trainingBuffer[physicalIndex].hasResult &&
               !m_trainingBuffer[physicalIndex].linkedToTrade &&
               !m_trainingBuffer[physicalIndex].isTradeLinked)
                continue;

            int newSize = ArraySize(indices) + 1;
            ArrayResize(indices, newSize);
            indices[newSize - 1] = i;
            if(newSize >= NN_MAX_PERSISTED_SAMPLES)
                break;
        }

        if(ArraySize(indices) == 0)
        {
            for(int i = total - 1; i >= 0; i--)
            {
                int physicalIndex = TrainingPhysicalIndex(i);
                if(physicalIndex < 0)
                    continue;
                int newSize = ArraySize(indices) + 1;
                ArrayResize(indices, newSize);
                indices[newSize - 1] = i;
                if(newSize >= 50)
                    break;
            }
        }

        int left = 0;
        int right = ArraySize(indices) - 1;
        while(left < right)
        {
            int tmp = indices[left];
            indices[left] = indices[right];
            indices[right] = tmp;
            left++;
            right--;
        }
    }

    void BuildAllSampleIndices(int &indices[])
    {
        int total = m_trainCount;
        ArrayResize(indices, total);
        for(int i = 0; i < total; i++)
            indices[i] = i;
    }

    uint HashCombine(const uint seed, const uint value)
    {
        return (seed ^ value) * 16777619;
    }

    uint HashLong(const uint seed, const long value)
    {
        ulong uValue = (ulong)value;
        uint low = (uint)(uValue & 0xFFFFFFFF);
        uint high = (uint)((uValue >> 32) & 0xFFFFFFFF);
        uint hash = HashCombine(seed, low);
        return HashCombine(hash, high);
    }

    uint HashDouble(const uint seed, const double value)
    {
        long scaled = (long)MathRound(value * 1000000.0);
        return HashLong(seed, scaled);
    }

    uint HashString(const uint seed, const string value)
    {
        uint hash = seed;
        int len = StringLen(value);
        for(int i = 0; i < len; i++)
            hash = HashCombine(hash, (uint)StringGetCharacter(value, i));
        hash = HashCombine(hash, (uint)len);
        return hash;
    }

    uint ComputeCheckpointChecksum(const int &sampleIndices[])
    {
        uint hash = 2166136261;

        hash = HashCombine(hash, NN_CHECKPOINT_MAGIC);
        hash = HashCombine(hash, NN_CHECKPOINT_VERSION);
        hash = HashString(hash, m_symbol);
        hash = HashCombine(hash, (uint)m_timeframe);
        hash = HashDouble(hash, m_learningRate);
        hash = HashCombine(hash, (uint)m_epoch);
        hash = HashDouble(hash, m_lastLoss);
        hash = HashCombine(hash, (uint)m_minTrainingExamples);
        hash = HashCombine(hash, (uint)m_maxTrainingExamples);
        hash = HashCombine(hash, (uint)m_resultMatchWindowSec);
        hash = HashCombine(hash, (uint)m_predictionCounter);
        hash = HashCombine(hash, m_enableOnlineTraining ? 1 : 0);
        hash = HashCombine(hash, m_enablePseudoLabeling ? 1 : 0);
        hash = HashCombine(hash, (uint)m_pseudoLabelBarsAhead);
        hash = HashCombine(hash, (uint)m_sampleIntervalSec);
        hash = HashCombine(hash, (uint)m_checkpointEveryLabeled);
        hash = HashCombine(hash, (uint)m_totalObservations);
        hash = HashCombine(hash, (uint)m_tradeLinkedLabels);
        hash = HashCombine(hash, (uint)m_pseudoLabels);
        hash = HashCombine(hash, (uint)m_trainingSteps);
        hash = HashCombine(hash, (uint)m_checkpointWrites);

        for(int i = 0; i < 25; i++)
            for(int j = 0; j < 15; j++)
                hash = HashDouble(hash, W1[i][j]);
        for(int i = 0; i < 15; i++)
            for(int j = 0; j < 10; j++)
                hash = HashDouble(hash, W2[i][j]);
        for(int i = 0; i < 10; i++)
            for(int j = 0; j < 3; j++)
                hash = HashDouble(hash, W3[i][j]);
        for(int i = 0; i < 15; i++) hash = HashDouble(hash, B1[i]);
        for(int i = 0; i < 10; i++) hash = HashDouble(hash, B2[i]);
        for(int i = 0; i < 3; i++) hash = HashDouble(hash, B3[i]);

        int sampleCount = ArraySize(sampleIndices);
        hash = HashCombine(hash, (uint)sampleCount);
        for(int s = 0; s < sampleCount; s++)
        {
            int physicalIndex = TrainingPhysicalIndex(sampleIndices[s]);
            if(physicalIndex < 0)
                continue;
            hash = HashCombine(hash, (uint)m_trainingBuffer[physicalIndex].expectedOutput);
            hash = HashDouble(hash, m_trainingBuffer[physicalIndex].actualResult);
            hash = HashLong(hash, (long)m_trainingBuffer[physicalIndex].time);
            hash = HashCombine(hash, m_trainingBuffer[physicalIndex].hasResult ? 1 : 0);
            hash = HashCombine(hash, m_trainingBuffer[physicalIndex].linkedToTrade ? 1 : 0);
            hash = HashString(hash, m_trainingBuffer[physicalIndex].predictionId);
            hash = HashCombine(hash, m_trainingBuffer[physicalIndex].pseudoLabeled ? 1 : 0);
            hash = HashLong(hash, (long)m_trainingBuffer[physicalIndex].labelDueTime);
            hash = HashDouble(hash, m_trainingBuffer[physicalIndex].entryPriceSnapshot);
            hash = HashCombine(hash, (uint)m_trainingBuffer[physicalIndex].barsAhead);
            hash = HashCombine(hash, m_trainingBuffer[physicalIndex].isTradeLinked ? 1 : 0);
            for(int k = 0; k < 25; k++)
                hash = HashDouble(hash, m_trainingBuffer[physicalIndex].inputs[k]);
        }

        return hash;
    }

    bool LoadCheckpointFromPath(const string filePath, const string loadStatus)
    {
        if(!FileIsExist(filePath, FILE_COMMON))
            return false;

        int fileHandle = FileOpen(filePath, FILE_READ | FILE_BIN | FILE_COMMON);
        if(fileHandle == INVALID_HANDLE)
            return false;

        int magic = FileReadInteger(fileHandle);
        int version = FileReadInteger(fileHandle);
        if(magic != NN_CHECKPOINT_MAGIC || version != NN_CHECKPOINT_VERSION)
        {
            FileClose(fileHandle);
            return false;
        }

        string checkpointSymbol = FileReadString(fileHandle);
        int checkpointTf = FileReadInteger(fileHandle);
        datetime checkpointTime = (datetime)FileReadLong(fileHandle);
        if(checkpointSymbol != m_symbol || checkpointTf != (int)m_timeframe)
        {
            FileClose(fileHandle);
            return false;
        }

        m_learningRate = FileReadDouble(fileHandle);
        m_epoch = FileReadInteger(fileHandle);
        m_lastLoss = FileReadDouble(fileHandle);
        m_minTrainingExamples = FileReadInteger(fileHandle);
        m_maxTrainingExamples = FileReadInteger(fileHandle);
        m_resultMatchWindowSec = FileReadInteger(fileHandle);
        m_predictionCounter = FileReadInteger(fileHandle);
        bool persistedOnlineTraining = (FileReadInteger(fileHandle) != 0);
        bool persistedPseudoLabeling = (FileReadInteger(fileHandle) != 0);
        m_pseudoLabelBarsAhead = FileReadInteger(fileHandle);
        m_sampleIntervalSec = FileReadInteger(fileHandle);
        m_checkpointEveryLabeled = FileReadInteger(fileHandle);
        m_totalObservations = FileReadInteger(fileHandle);
        m_tradeLinkedLabels = FileReadInteger(fileHandle);
        m_pseudoLabels = FileReadInteger(fileHandle);
        m_trainingSteps = FileReadInteger(fileHandle);
        m_checkpointWrites = FileReadInteger(fileHandle);

        for(int i = 0; i < 25; i++)
            for(int j = 0; j < 15; j++)
                W1[i][j] = FileReadDouble(fileHandle);
        for(int i = 0; i < 15; i++)
            for(int j = 0; j < 10; j++)
                W2[i][j] = FileReadDouble(fileHandle);
        for(int i = 0; i < 10; i++)
            for(int j = 0; j < 3; j++)
                W3[i][j] = FileReadDouble(fileHandle);
        for(int i = 0; i < 15; i++) B1[i] = FileReadDouble(fileHandle);
        for(int i = 0; i < 10; i++) B2[i] = FileReadDouble(fileHandle);
        for(int i = 0; i < 3; i++) B3[i] = FileReadDouble(fileHandle);

        int sampleCount = FileReadInteger(fileHandle);
        ClearTrainingData();
        for(int s = 0; s < sampleCount; s++)
        {
            STrainingExample ex;
            ex.expectedOutput = FileReadInteger(fileHandle);
            ex.actualResult = FileReadDouble(fileHandle);
            ex.time = (datetime)FileReadLong(fileHandle);
            ex.hasResult = (FileReadInteger(fileHandle) != 0);
            ex.linkedToTrade = (FileReadInteger(fileHandle) != 0);
            ex.predictionId = FileReadString(fileHandle);
            ex.pseudoLabeled = (FileReadInteger(fileHandle) != 0);
            ex.labelDueTime = (datetime)FileReadLong(fileHandle);
            ex.entryPriceSnapshot = FileReadDouble(fileHandle);
            ex.barsAhead = FileReadInteger(fileHandle);
            ex.isTradeLinked = (FileReadInteger(fileHandle) != 0);
            for(int i = 0; i < 25; i++)
                ex.inputs[i] = FileReadDouble(fileHandle);

            PushTrainingExample(ex);
        }

        uint storedChecksum = (uint)FileReadInteger(fileHandle);
        FileClose(fileHandle);

        int allIndices[];
        BuildAllSampleIndices(allIndices);
        uint computedChecksum = ComputeCheckpointChecksum(allIndices);
        if(storedChecksum != computedChecksum)
        {
            ClearTrainingData();
            return false;
        }

        // Runtime governance stays authoritative over persisted online flags.
        if(!m_enableOnlineTraining)
        {
            m_enablePseudoLabeling = false;
            m_allowWeightMutation = false;
        }
        else
        {
            m_enablePseudoLabeling = persistedPseudoLabeling;
            if(!persistedOnlineTraining)
                m_allowWeightMutation = false;
        }

        m_lastLoadStatus = loadStatus;
        m_lastCheckpointTimestamp = checkpointTime;
        PrintFormat("[NEURAL-NET] Model checkpoint %s | Symbol=%s | TF=%s | Epoch=%d | Obs=%d | Labeled=%d | Saved=%s",
                    loadStatus, m_symbol, EnumToString(m_timeframe), m_epoch,
                    m_totalObservations, GetCompletedTradesCount(),
                    TimeToString(m_lastCheckpointTimestamp, TIME_DATE | TIME_SECONDS));
        return true;
    }

    double ReLU(double x)
    {
        return MathMax(0.0, x);
    }
    
    void Softmax(double &arr[], int size)
    {
        double maxVal = arr[0];
        for(int i = 1; i < size; i++)
            maxVal = MathMax(maxVal, arr[i]);
        
        double sum = 0.0;
        for(int i = 0; i < size; i++)
        {
            arr[i] = MathExp(arr[i] - maxVal);
            sum += arr[i];
        }
        
        if(sum > 0)
        {
            for(int i = 0; i < size; i++)
                arr[i] /= sum;
        }
    }
    
    double CalculateLoss(const double &outputs[], const double &target[])
    {
        // Cross-entropy loss
        double loss = 0.0;
        for(int i = 0; i < 3; i++)
        {
            if(target[i] > 0)
                loss -= target[i] * MathLog(outputs[i] + 1e-10);
        }
        return loss;
    }
    
    void UpdateWeights(const double &inputs[], const double &outputs[], const double &target[], const double sampleWeight)
    {
        // Simplified weight update (gradient descent on output layer)
        //TODO: Full implementation would require proper backpropagation through all layers
        
        double outputError[3];  // OUTPUT_SIZE
        for(int i = 0; i < 3; i++)  // OUTPUT_SIZE
        {
            outputError[i] = outputs[i] - target[i];
        }
        
        double scaledRate = m_learningRate * MathMax(0.1, sampleWeight);

        // Update output layer weights (W3) and biases (B3)
        //TODO: This is a simplified version - proper backprop would compute gradients through all layers
        for(int i = 0; i < 10; i++)
        {
            for(int j = 0; j < 3; j++)
            {
                double gradient = outputError[j];
                W3[i][j] -= scaledRate * gradient * 0.1; // Scaled down
            }
        }
        
        // Update biases
        for(int i = 0; i < 3; i++)
        {
            B3[i] -= scaledRate * outputError[i];
        }
    }
    
    double GetNormalizedValue(double min, double max, double value)
    {
        if(max - min == 0) return 0;
        return (value - min) / (max - min);
    }
    
    bool IsKillZoneTime(int hour)
    {
        // London Kill Zone: 02:00-05:00 (server time)
        // New York Kill Zone: 07:00-10:00 (server time)
        // Asian Kill Zone: 20:00-23:00 (server time)
        return (hour >= 2 && hour <= 5) || (hour >= 7 && hour <= 10) || (hour >= 20 && hour <= 23);
    }
};

#endif // __NEURAL_NETWORK_STRATEGY_MQH__
