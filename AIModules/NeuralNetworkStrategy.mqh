//+------------------------------------------------------------------+
//| NeuralNetworkStrategy.mqh                                        |
//| Complete 3-Layer Feedforward Neural Network for Trading         |
//| Implementation based on neural_networks.md specification        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024"
#property strict

#ifndef __NEURAL_NETWORK_STRATEGY_MQH__
#define __NEURAL_NETWORK_STRATEGY_MQH__

// Network architecture: 25→32→16→8→3 (Input→Hidden1→Hidden2→Hidden3→Output)
// Increased architecture for improved model capacity and learning

#include "../Core/Utils/Enums.mqh"
#include "../Core/AI/NNModelStorage.mqh"
#include "../Core/AI/AIFeatureVectorBuilder.mqh"
#include "../IndicatorManager.mqh"
#include "TransformerBrain.mqh"
#include "UniversalTransformerService.mqh"

#define NN_CHECKPOINT_MAGIC 1313758027
#define NN_CHECKPOINT_VERSION 5
#define RAND_MAX 2147483647
#define NN_MAX_PERSISTED_SAMPLES 300
#define NN_MAX_TRAINING_EXAMPLES 2000

//+------------------------------------------------------------------+
//| Training Example Structure                                       |
//+------------------------------------------------------------------+
struct STrainingExample
{
    double inputs[FEATURE_VECTOR_SIZE];  // Synced with shared builder
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
    bool m_usesSharedTransformer;  // Whether to use shared transformer service
    
    bool WriteCheckpointString(const int fileHandle, const string value)
    {
        int len = (int)StringLen(value);
        FileWriteInteger(fileHandle, len);
        for(int i = 0; i < len; i++)
        {
            ushort ch = (ushort)StringGetCharacter(value, i);
            FileWriteInteger(fileHandle, (int)ch);
        }
        return true;
    }

    bool ReadCheckpointString(const int fileHandle, string &value)
    {
        value = "";
        int len = FileReadInteger(fileHandle);
        if(len < 0 || len > 4096)
            return false;

        StringInit(value, 0, (ushort)len);
        for(int i = 0; i < len; i++)
        {
            ushort ch = (ushort)FileReadInteger(fileHandle);
            StringSetCharacter(value, i, (ushort)ch);
        }
        return true;
    }

    // Network weights
    double W1[FEATURE_VECTOR_SIZE][32];       // Input → Hidden1 (synced with shared builder)
    double W2[32][16];       // Hidden1 → Hidden2
    double W3[16][8];        // Hidden2 → Hidden3
    double W4[8][3];         // Hidden3 → Output
    
    // Biases
    double B1[32];
    double B2[16];
    double B3[8];
    double B4[3];
    
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
    double m_minConfidence;
    datetime m_lastCheckpointDiagLogTime;

    
public:
    CNeuralNetworkStrategy() : 
        m_learningRate(0.002),
        m_epoch(0),
        m_lastLoss(0.0),
        m_minTrainingExamples(3),  // Dramatically reduced from 10 to allow almost immediate training startup
        m_maxTrainingExamples(5000),
        m_resultMatchWindowSec(86400),
        m_predictionCounter(0),
        m_symbol(""),
        m_timeframe(PERIOD_CURRENT),
        m_initialized(false),
        m_enableOnlineTraining(true),
        m_allowWeightMutation(true),
        m_enablePseudoLabeling(true),
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
        m_lastFeatureValidationLogTime(0),
        m_minConfidence(0.35),
        m_lastCheckpointDiagLogTime(0),
        m_usesSharedTransformer(true)  // Use shared transformer by default

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
        if(m_usesSharedTransformer) {
            // With shared transformer service, we don't need to create our own
            // Just ensure the symbol is registered with the service
            if(!g_universalTransformerService.IsSymbolRegistered(m_symbol)) {
                return g_universalTransformerService.RegisterSymbol(m_symbol);
            }
            return true;
        } else {
            // Fallback to local transformer (backward compatibility)
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
        // AUDIT FIX: Add error handling for empty or insufficient feature vectors
        if(ArraySize(features) < FEATURE_VECTOR_SIZE)
        {
            static datetime s_lastEmptyLog = 0;
            datetime now = TimeCurrent();
            if(s_lastEmptyLog == 0 || (now - s_lastEmptyLog) >= 60)
            {
                PrintFormat("[NN-STRATEGY] ERROR: Empty or insufficient feature vector for %s %s | size=%d | required=%d",
                            m_symbol, EnumToString(m_timeframe), ArraySize(features), FEATURE_VECTOR_SIZE);
                s_lastEmptyLog = now;
            }
            return false;
        }

        int zeroCount = 0;
        int nanCount = 0;
        int criticalZeroCount = 0;
        int criticalIndices[6] = {1, 2, 3, 4, 13, 23};

        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
        {
            if(!MathIsValidNumber(features[i]))
                nanCount++;
            if(MathAbs(features[i]) <= 1e-9)
                zeroCount++;
        }

        for(int c = 0; c < 6; c++)
        {
            int idx = criticalIndices[c];
            if(idx >= 0 && idx < FEATURE_VECTOR_SIZE && MathAbs(features[idx]) <= 1e-9)
                criticalZeroCount++;
        }

        if(nanCount > 0)
        {
            LogFeatureValidationFailure(zeroCount, nanCount, criticalZeroCount);
            return false;
        }

        // Allow slightly more zeros for 50 features, but critical zeros remain strict.
        if(criticalZeroCount >= 4 || zeroCount > 20)
        {
            LogFeatureValidationFailure(zeroCount, nanCount, criticalZeroCount);
            return false;
        }

        return true;
    }

    bool ApplyTransformerFeatureBridge(double &features[])
    {
        if(ArraySize(features) < FEATURE_VECTOR_SIZE)
            return false;
        
        if(m_usesSharedTransformer) {
            // Use shared universal transformer service
            if(!g_universalTransformerService.IsSymbolRegistered(m_symbol)) {
                // Register symbol if not already registered
                if(!g_universalTransformerService.RegisterSymbol(m_symbol)) {
                    PrintFormat("[NN-TRANSFORMER] ERROR: Failed to register symbol %s with universal service", m_symbol);
                    return false;
                }
            }
            
            int sequenceLength = MathMin(8, TRANSFORMER_SHORT_SEQ_LEN_DEFAULT);
            if(sequenceLength <= 0)
                sequenceLength = 4;
                
            if(!CAIFeatureVectorBuilder::BuildTransformerInput(m_symbol, m_timeframe, m_lastTransformerInput, 64, sequenceLength))
                return false;

            m_lastTransformerSeqLen = sequenceLength;
            double encodedFeatures[];
            
            // Try to get features with retry mechanism for warmup periods
            bool featuresRetrieved = false;
            for(int retry = 0; retry < 2; retry++)
            {
                if(g_universalTransformerService.GetSymbolFeatures(m_symbol, m_lastTransformerInput, m_lastTransformerSeqLen, encodedFeatures))
                {
                    featuresRetrieved = true;
                    break;
                }
                // Small delay before retry
                if(retry == 0)
                    Sleep(10);
            }
            
            if(!featuresRetrieved)
            {
                // Reduce severity during warmup - this is expected for new symbols
                static datetime lastWarningTime = 0;
                datetime nowTime = TimeCurrent();
                if(nowTime - lastWarningTime > 30) // Limit warning frequency
                {
                    PrintFormat("[NN-TRANSFORMER] WARNING: Features not ready for %s (warmup period)", m_symbol);
                    lastWarningTime = nowTime;
                }
                return false;
            }

            int encodedSize = ArraySize(encodedFeatures);
            if(encodedSize <= 0)
                return false;

            // Use transformer features (positions 15-24)
            int featuresToUse = MathMin(10, encodedSize);
            for(int i = 0; i < featuresToUse; i++) {
                features[15 + i] = MathMax(-3.0, MathMin(3.0, encodedFeatures[i]));
            }
            
            // Fill remaining with zeros if needed
            for(int i = featuresToUse; i < 10; i++) {
                features[15 + i] = 0.0;
            }
            
            return true;
        } else {
            // Fallback to local transformer (backward compatibility)
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

    void SetConfidenceThreshold(double threshold)
    {
        m_minConfidence = threshold;
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
        double xavier_input = MathSqrt(2.0 / FEATURE_VECTOR_SIZE);
        double xavier_hidden1 = MathSqrt(2.0 / 32);
        double xavier_hidden2 = MathSqrt(2.0 / 16);
        double xavier_hidden3 = MathSqrt(2.0 / 8);
        
        // Local deterministic seeding for reproducibility
        m_randomState = 12345; // Fixed seed

        // Initialize W1
        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
        {
            for(int j = 0; j < 32; j++)
            {
                W1[i][j] = (GetDeterministicRandom() - 0.5) * 2 * xavier_input;
            }
        }
        
        // Initialize W2
        for(int i = 0; i < 32; i++)
        {
            for(int j = 0; j < 16; j++)
            {
                W2[i][j] = (GetDeterministicRandom() - 0.5) * 2 * xavier_hidden1;
            }
        }
        
        // Initialize W3
        for(int i = 0; i < 16; i++)
        {
            for(int j = 0; j < 8; j++)
            {
                W3[i][j] = (GetDeterministicRandom() - 0.5) * 2 * xavier_hidden2;
            }
        }
        
        // Initialize W4
        for(int i = 0; i < 8; i++)
        {
            for(int j = 0; j < 3; j++)
            {
                W4[i][j] = (GetDeterministicRandom() - 0.5) * 2 * xavier_hidden3;
            }
        }
        
        // Initialize biases to small values
        for(int i = 0; i < 32; i++)
            B1[i] = 0.01;
        
        for(int i = 0; i < 16; i++)
            B2[i] = 0.01;
        
        for(int i = 0; i < 8; i++)
            B3[i] = 0.01;
        
        for(int i = 0; i < 3; i++)
            B4[i] = 0.01;
        
        PrintFormat("[NEURAL-NET] Network weights initialized with Deterministic Xavier method (%d→32→16→8→3)", FEATURE_VECTOR_SIZE);
    }

    // Simple LCG for deterministic behavior
    uint m_randomState;
    double GetDeterministicRandom()
    {
        m_randomState = m_randomState * 1664525 + 1013904223;
        return (double)m_randomState / 4294967296.0;
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

    // Normalize features to [-1, 1] range for gradient stability
    void NormalizeFeatures(double &features[])
    {
        if(ArraySize(features) < FEATURE_VECTOR_SIZE)
            return;

        // Define expected ranges per feature type based on typical indicator values
        // These ranges are conservative estimates for normalization
        static const double featureMin[FEATURE_VECTOR_SIZE] = {
            0,      // RSI: 0-100
            -5,     // MACD signal (pips): -5 to +5
            -10,    // ATR (pips): 0-10
            -500,   // Price differences (pips): -500 to +500
            -500,   // Price differences (pips): -500 to +500
            -500,   // Price differences (pips): -500 to +500
            -500,   // Price differences (pips): -500 to +500
            -500,   // Price differences (pips): -500 to +500
            -10,    // Volatility measures: -10 to +10
            -10,    // Volatility measures: -10 to +10
            -5,     // Momentum indicators: -5 to +5
            -5,     // Momentum indicators: -5 to +5
            -5,     // Momentum indicators: -5 to +5
            -5,     // Momentum indicators: -5 to +5
            -5,     // Momentum indicators: -5 to +5
            -3,     // Transformer features (if enabled): -3 to +3
            -3,     // Transformer features (if enabled): -3 to +3
            -3,     // Transformer features (if enabled): -3 to +3
            -3,     // Transformer features (if enabled): -3 to +3
            -3,     // Transformer features (if enabled): -3 to +3
            -3,     // Transformer features (if enabled): -3 to +3
            -3,     // Transformer features (if enabled): -3 to +3
            -3,     // Transformer features (if enabled): -3 to +3
            -3,     // Transformer features (if enabled): -3 to +3
            -3      // Transformer features (if enabled): -3 to +3
        };
        
        static const double featureMax[FEATURE_VECTOR_SIZE] = {
            100,    // RSI: 0-100
            5,      // MACD signal (pips): -5 to +5
            10,     // ATR (pips): 0-10
            500,    // Price differences (pips): -500 to +500
            500,    // Price differences (pips): -500 to +500
            500,    // Price differences (pips): -500 to +500
            500,    // Price differences (pips): -500 to +500
            500,    // Price differences (pips): -500 to +500
            10,     // Volatility measures: -10 to +10
            10,     // Volatility measures: -10 to +10
            5,      // Momentum indicators: -5 to +5
            5,      // Momentum indicators: -5 to +5
            5,      // Momentum indicators: -5 to +5
            5,      // Momentum indicators: -5 to +5
            5,      // Momentum indicators: -5 to +5
            3,      // Transformer features (if enabled): -3 to +3
            3,      // Transformer features (if enabled): -3 to +3
            3,      // Transformer features (if enabled): -3 to +3
            3,      // Transformer features (if enabled): -3 to +3
            3,      // Transformer features (if enabled): -3 to +3
            3,      // Transformer features (if enabled): -3 to +3
            3,      // Transformer features (if enabled): -3 to +3
            3,      // Transformer features (if enabled): -3 to +3
            3,      // Transformer features (if enabled): -3 to +3
            3       // Transformer features (if enabled): -3 to +3
        };

        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
        {
            double range = featureMax[i] - featureMin[i];
            if(range < 1e-9) 
            {
                features[i] = 0.0;
                continue;
            }
            
            // Clamp to expected range first
            double clamped = MathMax(featureMin[i], MathMin(featureMax[i], features[i]));
            
            // Normalize to [-1, 1]
            features[i] = ((clamped - featureMin[i]) / range) * 2.0 - 1.0;
            
            // Ensure bounds
            features[i] = MathMax(-1.0, MathMin(1.0, features[i]));
        }
    }

    // Extract features from current market state using shared builder
    bool ExtractFeatures(double &features[])
    {
        if(!m_initialized) return false;

        // MEDIUM FIX: Extended retry logic with exponential backoff for warmup periods
        datetime initAge = TimeCurrent() - m_lastCheckpointTimestamp;
        bool isWarmup = (initAge < 300); // Consider first 5 minutes as warmup
        
        int maxRetries = isWarmup ? 5 : 2;
        int retryDelay = isWarmup ? 50 : 10;
        
        for(int attempt = 0; attempt < maxRetries; attempt++)
        {
            // Use shared builder for consistent 50-feature vector
            if(CAIFeatureVectorBuilder::BuildNNFeatureVector(m_symbol, m_timeframe, features, 1))
            {
                break; // Success
            }
            
            // If not the last attempt, wait and retry
            if(attempt < maxRetries - 1)
            {
                Sleep(retryDelay);
                retryDelay *= 2; // Exponential backoff
            }
            else
            {
                // All retries failed
                static datetime s_lastBuilderLog = 0;
                datetime now = TimeCurrent();
                if(m_lastIndicatorWarningTime == 0 || (now - m_lastIndicatorWarningTime) >= 60)
                {
                    PrintFormat("[NN-FEATURE] Builder warming up for %s %s | initialized=%s | attempts=%d",
                                m_symbol, EnumToString(m_timeframe), m_initialized ? "YES" : "NO", maxRetries);
                    m_lastIndicatorWarningTime = now;
                }
                return false;
            }
        }

        // RECOVERY FIX: Graceful degradation when transformer bridge unavailable.
        // NN can still produce signals from the 15 base indicators (RSI, MACD, ATR,
        // price diffs, etc.) with transformer feature slots zero-padded.
        bool transformerSuccess = ApplyTransformerFeatureBridge(features);
        if(!transformerSuccess)
        {
            // Fill transformer feature slots (15-24) with zeros as fallback
            for(int i = 15; i < 25; i++)
            {
                if(i < ArraySize(features))
                    features[i] = 0.0;
            }
            static datetime s_lastTransformerLog = 0;
            datetime now = TimeCurrent();
            if(m_lastIndicatorWarningTime == 0 || (now - m_lastIndicatorWarningTime) >= 300)
            {
                // [DIAGNOSTIC] Log bridge failure details to help root-cause investigating in logs
                PrintFormat("[NN-FEATURE] Transformer bridge unavailable for %s %s - using base features only (check UniversalTransformerService connection)",
                            m_symbol, EnumToString(m_timeframe));
                m_lastIndicatorWarningTime = now;
            }
        }
        
        if(!ValidateFeatures(features))
        {
            static datetime s_lastValidateLog = 0;
            datetime now = TimeCurrent();
            if(m_lastIndicatorWarningTime == 0 || (now - m_lastIndicatorWarningTime) >= 60)
            {
                PrintFormat("[NN-FEATURE] Validation failed for %s %s after bridge",
                            m_symbol, EnumToString(m_timeframe));
                m_lastIndicatorWarningTime = now;
            }
            return false;
        }
        
        // Normalize features to [-1, 1] range for gradient stability
        NormalizeFeatures(features);
        
        return true;
    }
    
    // Forward propagation
    void ForwardPropagate(const double &inputs[], double &outputs[])
    {
        double hidden1[32];
        double hidden2[16];
        double hidden3[8];
        
        ArrayResize(outputs, 3);
        
        // Input → Hidden1
        for(int j = 0; j < 32; j++)
        {
            hidden1[j] = B1[j];
            for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
            {
                hidden1[j] += inputs[i] * W1[i][j];
            }
            hidden1[j] = ReLU(hidden1[j]);  // Activation
        }
        
        // Hidden1 → Hidden2
        for(int j = 0; j < 16; j++)
        {
            hidden2[j] = B2[j];
            for(int i = 0; i < 32; i++)
            {
                hidden2[j] += hidden1[i] * W2[i][j];
            }
            hidden2[j] = ReLU(hidden2[j]);
        }
        
        // Hidden2 → Hidden3
        for(int j = 0; j < 8; j++)
        {
            hidden3[j] = B3[j];
            for(int i = 0; i < 16; i++)
            {
                hidden3[j] += hidden2[i] * W3[i][j];
            }
            hidden3[j] = ReLU(hidden3[j]);
        }
        
        // Hidden3 → Output
        for(int j = 0; j < 3; j++)
        {
            outputs[j] = B4[j];
            for(int i = 0; i < 8; i++)
            {
                outputs[j] += hidden3[i] * W4[i][j];
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

        int pendingCount = 0;
        int notDueCount = 0;
        int invalidOutputCount = 0;
        int alreadyLabeledCount = 0;
        int pseudoLabeledNow = 0;

        for(int i = 0; i < m_trainCount; i++)
        {
            int physicalIndex = TrainingPhysicalIndex(i);
            if(physicalIndex < 0)
                continue;
            if(m_trainingBuffer[physicalIndex].hasResult ||
               m_trainingBuffer[physicalIndex].linkedToTrade ||
               m_trainingBuffer[physicalIndex].isTradeLinked)
            {
                alreadyLabeledCount++;
                continue;
            }

            if(m_trainingBuffer[physicalIndex].labelDueTime <= 0 || now < m_trainingBuffer[physicalIndex].labelDueTime)
            {
                notDueCount++;
                continue;
            }

            if(m_trainingBuffer[physicalIndex].expectedOutput != 1 && m_trainingBuffer[physicalIndex].expectedOutput != 2)
            {
                invalidOutputCount++;
                continue;
            }

            pendingCount++;
            if(m_trainingBuffer[physicalIndex].expectedOutput == 1)
                m_trainingBuffer[physicalIndex].actualResult = currentClose - m_trainingBuffer[physicalIndex].entryPriceSnapshot;
            else
                m_trainingBuffer[physicalIndex].actualResult = m_trainingBuffer[physicalIndex].entryPriceSnapshot - currentClose;

            m_trainingBuffer[physicalIndex].hasResult = true;
            m_trainingBuffer[physicalIndex].pseudoLabeled = true;
            m_trainingBuffer[physicalIndex].isTradeLinked = false;
            pseudoLabeledNow++;
        }

        // Log pseudo-label processing diagnostics periodically
        static datetime s_lastPseudoLog = 0;
        if(s_lastPseudoLog == 0 || (now - s_lastPseudoLog) >= 60)
        {
            PrintFormat("[NN-PSEUDO] %s %s | pending=%d | notDue=%d | invalid=%d | already=%d | labeledNow=%d | totalPseudo=%d",
                        m_symbol, EnumToString(m_timeframe),
                        pendingCount, notDueCount, invalidOutputCount, alreadyLabeledCount,
                        pseudoLabeledNow, m_pseudoLabels);
            s_lastPseudoLog = now;
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

        double inputs[FEATURE_VECTOR_SIZE];  // Synced with shared builder
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

        double minDirectionalConfidence = m_minConfidence;
        // Soften threshold slightly during initial exploration/training if not already low
        if(m_enableOnlineTraining && labeledCount < m_minTrainingExamples && m_minConfidence > 0.45)
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
        WriteCheckpointString(fileHandle, m_symbol);
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

        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
            for(int j = 0; j < 32; j++)
                FileWriteDouble(fileHandle, W1[i][j]);
        for(int i = 0; i < 32; i++)
            for(int j = 0; j < 16; j++)
                FileWriteDouble(fileHandle, W2[i][j]);
        for(int i = 0; i < 16; i++)
            for(int j = 0; j < 8; j++)
                FileWriteDouble(fileHandle, W3[i][j]);
        for(int i = 0; i < 8; i++)
            for(int j = 0; j < 3; j++)
                FileWriteDouble(fileHandle, W4[i][j]);
        for(int i = 0; i < 32; i++) FileWriteDouble(fileHandle, B1[i]);
        for(int i = 0; i < 16; i++) FileWriteDouble(fileHandle, B2[i]);
        for(int i = 0; i < 8; i++) FileWriteDouble(fileHandle, B3[i]);
        for(int i = 0; i < 3; i++) FileWriteDouble(fileHandle, B4[i]);

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
            WriteCheckpointString(fileHandle, m_trainingBuffer[physicalIndex].predictionId);
            FileWriteInteger(fileHandle, m_trainingBuffer[physicalIndex].pseudoLabeled ? 1 : 0);
            FileWriteLong(fileHandle, (long)m_trainingBuffer[physicalIndex].labelDueTime);
            FileWriteDouble(fileHandle, m_trainingBuffer[physicalIndex].entryPriceSnapshot);
            FileWriteInteger(fileHandle, m_trainingBuffer[physicalIndex].barsAhead);
            FileWriteInteger(fileHandle, m_trainingBuffer[physicalIndex].isTradeLinked ? 1 : 0);
            for(int k = 0; k < FEATURE_VECTOR_SIZE; k++)
                FileWriteDouble(fileHandle, m_trainingBuffer[physicalIndex].inputs[k]);
        }

        FileWriteInteger(fileHandle, (int)checksum);
        FileClose(fileHandle);

        if(!NNModelStorage_PromoteTempToPrimary(tempFile, primaryFile, backupFile))
        {
            datetime now = TimeCurrent();
            if(m_lastCheckpointDiagLogTime == 0 || (now - m_lastCheckpointDiagLogTime) >= 30)
            {
                PrintFormat("[NEURAL-NET] Checkpoint promote failed | Symbol=%s | TF=%s | Temp=%s | Primary=%s | Backup=%s | err=%d",
                            m_symbol, EnumToString(m_timeframe), tempFile, primaryFile, backupFile, GetLastError());
                m_lastCheckpointDiagLogTime = now;
            }
            return false;
        }

        m_checkpointWrites++;
        m_lastCheckpointTimestamp = checkpointTime;
        return true;
    }

    bool LoadCheckpoint()
    {
        if(!m_enableOnlineTraining)
            return false;

        NNModelStorage_EnsureFolders();
        string primaryFile = NNModelStorage_GetPrimaryPath(m_symbol, m_timeframe, NN_CHECKPOINT_VERSION);
        string backupFile = NNModelStorage_GetBackupPath(m_symbol, m_timeframe, NN_CHECKPOINT_VERSION);

        // Try loading v3 checkpoint first
        if(LoadCheckpointFromPath(primaryFile, "LOADED"))
            return true;
        if(LoadCheckpointFromPath(backupFile, "RESTORED_FROM_BACKUP"))
            return true;

        // If v3 fails, try migrating from legacy v2 checkpoint
        if(NNModelStorage_LegacyCheckpointExists(m_symbol, m_timeframe))
        {
            PrintFormat("[NEURAL-NET] Legacy v2 checkpoint found, attempting migration to v%d | Symbol=%s | TF=%s",
                        NN_CHECKPOINT_VERSION,
                        m_symbol, EnumToString(m_timeframe));
            if(MigrateLegacyCheckpoint())
            {
                // Try loading again after migration
                if(LoadCheckpointFromPath(primaryFile, "MIGRATED_V2_TO_V4"))
                    return true;
                if(LoadCheckpointFromPath(backupFile, "MIGRATED_V2_TO_V4_RESTORED"))
                    return true;
            }
        }

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

        double inputs[FEATURE_VECTOR_SIZE];  // Synced with shared builder
        if(!ExtractFeatures(inputs))
        {
            static datetime s_lastFeatureLog = 0;
            if(s_lastFeatureLog == 0 || (now - s_lastFeatureLog) >= 60)
            {
                PrintFormat("[NN-OBS] Feature extraction failed for %s %s | force=%d | lastObsTime=%s | interval=%d",
                            m_symbol, EnumToString(m_timeframe), forceSample,
                            TimeToString(m_lastObservationTime, TIME_SECONDS), m_sampleIntervalSec);
                s_lastFeatureLog = now;
            }
            return false;
        }

        double outputs[3];
        ForwardPropagate(inputs, outputs);

        int expectedOutput = forcedOutput;
        if(expectedOutput <= 0)
            expectedOutput = (outputs[1] >= outputs[2]) ? 1 : 2;

        STrainingExample example;
        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
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

        int completedTrades = GetCompletedTradesCount();
        bool willTrain = (m_allowWeightMutation && completedTrades >= m_minTrainingExamples);

        PrintFormat("[NN-LABEL] Checkpoint trigger for %s %s | labeledSince=%d | interval=%d | allowMutation=%s | completed=%d | minRequired=%d | willTrain=%s",
                    m_symbol, EnumToString(m_timeframe),
                    m_labeledSinceCheckpoint, checkpointInterval,
                    m_allowWeightMutation ? "YES" : "NO",
                    completedTrades, m_minTrainingExamples,
                    willTrain ? "YES" : "NO");

        if(willTrain)
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

        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
            for(int j = 0; j < 32; j++)
                hash = HashDouble(hash, W1[i][j]);
        for(int i = 0; i < 32; i++)
            for(int j = 0; j < 16; j++)
                hash = HashDouble(hash, W2[i][j]);
        for(int i = 0; i < 16; i++)
            for(int j = 0; j < 8; j++)
                hash = HashDouble(hash, W3[i][j]);
        for(int i = 0; i < 8; i++)
            for(int j = 0; j < 3; j++)
                hash = HashDouble(hash, W4[i][j]);
        
        for(int i = 0; i < 32; i++) hash = HashDouble(hash, B1[i]);
        for(int i = 0; i < 16; i++) hash = HashDouble(hash, B2[i]);
        for(int i = 0; i < 8; i++) hash = HashDouble(hash, B3[i]);
        for(int i = 0; i < 3; i++) hash = HashDouble(hash, B4[i]);

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
            for(int k = 0; k < FEATURE_VECTOR_SIZE; k++)
                hash = HashDouble(hash, m_trainingBuffer[physicalIndex].inputs[k]);
        }

        return hash;
    }

    bool LoadCheckpointFromPath(const string filePath, const string loadStatus)
    {
        if(!FileIsExist(filePath, FILE_COMMON))
        {
            datetime now = TimeCurrent();
            if(m_lastCheckpointDiagLogTime == 0 || (now - m_lastCheckpointDiagLogTime) >= 30)
            {
                PrintFormat("[NEURAL-NET] Checkpoint missing | Symbol=%s | TF=%s | Path=%s",
                            m_symbol, EnumToString(m_timeframe), filePath);
                m_lastCheckpointDiagLogTime = now;
            }
            return false;
        }

        int fileHandle = FileOpen(filePath, FILE_READ | FILE_BIN | FILE_COMMON);
        if(fileHandle == INVALID_HANDLE)
        {
            datetime now = TimeCurrent();
            if(m_lastCheckpointDiagLogTime == 0 || (now - m_lastCheckpointDiagLogTime) >= 30)
            {
                PrintFormat("[NEURAL-NET] Checkpoint open failed | Symbol=%s | TF=%s | Path=%s | err=%d",
                            m_symbol, EnumToString(m_timeframe), filePath, GetLastError());
                m_lastCheckpointDiagLogTime = now;
            }
            return false;
        }

        int magic = FileReadInteger(fileHandle);
        int version = FileReadInteger(fileHandle);
        if(magic != NN_CHECKPOINT_MAGIC || version != NN_CHECKPOINT_VERSION)
        {
            FileClose(fileHandle);
            datetime now = TimeCurrent();
            if(m_lastCheckpointDiagLogTime == 0 || (now - m_lastCheckpointDiagLogTime) >= 30)
            {
                PrintFormat("[NEURAL-NET] Checkpoint header mismatch | Symbol=%s | TF=%s | Path=%s | magic=%d/%d | version=%d/%d",
                            m_symbol, EnumToString(m_timeframe), filePath,
                            magic, NN_CHECKPOINT_MAGIC, version, NN_CHECKPOINT_VERSION);
                m_lastCheckpointDiagLogTime = now;
            }
            return false;
        }

        string checkpointSymbol;
        if(!ReadCheckpointString(fileHandle, checkpointSymbol))
        {
            datetime now = TimeCurrent();
            if(m_lastCheckpointDiagLogTime == 0 || (now - m_lastCheckpointDiagLogTime) >= 10)
            {
                PrintFormat("[NEURAL-NET] Checkpoint symbol read failed | Symbol=%s | TF=%s | Path=%s",
                            m_symbol, EnumToString(m_timeframe), filePath);
                m_lastCheckpointDiagLogTime = now;
            }
            FileClose(fileHandle);
            return false;
        }
        int checkpointTf = FileReadInteger(fileHandle);
        datetime checkpointTime = (datetime)FileReadLong(fileHandle);
        if(checkpointSymbol != m_symbol || checkpointTf != (int)m_timeframe)
        {
            FileClose(fileHandle);
            datetime now = TimeCurrent();
            if(m_lastCheckpointDiagLogTime == 0 || (now - m_lastCheckpointDiagLogTime) >= 10)
            {
                PrintFormat("[NEURAL-NET] Checkpoint symbol/tf mismatch | Expected=%s/%s | Got=%s/%s | Path=%s",
                            m_symbol, EnumToString(m_timeframe), checkpointSymbol, EnumToString((ENUM_TIMEFRAMES)checkpointTf), filePath);
                m_lastCheckpointDiagLogTime = now;
            }
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

        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
            for(int j = 0; j < 32; j++)
                W1[i][j] = FileReadDouble(fileHandle);
        for(int i = 0; i < 32; i++)
            for(int j = 0; j < 16; j++)
                W2[i][j] = FileReadDouble(fileHandle);
        for(int i = 0; i < 16; i++)
            for(int j = 0; j < 8; j++)
                W3[i][j] = FileReadDouble(fileHandle);
        for(int i = 0; i < 8; i++)
            for(int j = 0; j < 3; j++)
                W4[i][j] = FileReadDouble(fileHandle);
        for(int i = 0; i < 32; i++) B1[i] = FileReadDouble(fileHandle);
        for(int i = 0; i < 16; i++) B2[i] = FileReadDouble(fileHandle);
        for(int i = 0; i < 8; i++) B3[i] = FileReadDouble(fileHandle);
        for(int i = 0; i < 3; i++) B4[i] = FileReadDouble(fileHandle);

        int sampleCount = FileReadInteger(fileHandle);
        if(sampleCount < 0 || sampleCount > NN_MAX_PERSISTED_SAMPLES)
        {
            datetime now = TimeCurrent();
            if(m_lastCheckpointDiagLogTime == 0 || (now - m_lastCheckpointDiagLogTime) >= 10)
            {
                PrintFormat("[NEURAL-NET] Checkpoint sample count invalid | Symbol=%s | TF=%s | Path=%s | sampleCount=%d | max=%d",
                            m_symbol, EnumToString(m_timeframe), filePath, sampleCount, NN_MAX_PERSISTED_SAMPLES);
                m_lastCheckpointDiagLogTime = now;
            }
            FileClose(fileHandle);
            return false;
        }
        ClearTrainingData();
        for(int s = 0; s < sampleCount; s++)
        {
            STrainingExample ex;
            ex.expectedOutput = FileReadInteger(fileHandle);
            ex.actualResult = FileReadDouble(fileHandle);
            ex.time = (datetime)FileReadLong(fileHandle);
            ex.hasResult = (FileReadInteger(fileHandle) != 0);
            ex.linkedToTrade = (FileReadInteger(fileHandle) != 0);
            if(!ReadCheckpointString(fileHandle, ex.predictionId))
            {
                datetime now = TimeCurrent();
                if(m_lastCheckpointDiagLogTime == 0 || (now - m_lastCheckpointDiagLogTime) >= 10)
                {
                    PrintFormat("[NEURAL-NET] Checkpoint sample predictionId read failed | Symbol=%s | TF=%s | Path=%s | SampleIndex=%d/%d",
                                m_symbol, EnumToString(m_timeframe), filePath, s, sampleCount);
                    m_lastCheckpointDiagLogTime = now;
                }
                FileClose(fileHandle);
                ClearTrainingData();
                return false;
            }
            ex.pseudoLabeled = (FileReadInteger(fileHandle) != 0);
            ex.labelDueTime = (datetime)FileReadLong(fileHandle);
            ex.entryPriceSnapshot = FileReadDouble(fileHandle);
            ex.barsAhead = FileReadInteger(fileHandle);
            ex.isTradeLinked = (FileReadInteger(fileHandle) != 0);
            for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
                ex.inputs[i] = FileReadDouble(fileHandle);

            PushTrainingExample(ex);
        }

        uint storedChecksum = (uint)FileReadInteger(fileHandle);
        FileClose(fileHandle);

        // TODO: Re-enable checksum validation after all checkpoints are re-saved with v5 encoding
        // Temporarily disabled to accept existing v5 files written with old string encoding
        /*
        int allIndices[];
        BuildAllSampleIndices(allIndices);
        uint computedChecksum = ComputeCheckpointChecksum(allIndices);
        if(storedChecksum != computedChecksum)
        {
            ClearTrainingData();
            datetime now = TimeCurrent();
            if(m_lastCheckpointDiagLogTime == 0 || (now - m_lastCheckpointDiagLogTime) >= 30)
            {
                PrintFormat("[NEURAL-NET] Checkpoint checksum mismatch | Symbol=%s | TF=%s | Path=%s | stored=%u | computed=%u",
                            m_symbol, EnumToString(m_timeframe), filePath, storedChecksum, computedChecksum);
                m_lastCheckpointDiagLogTime = now;
            }
            return false;
        }
        */

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

    bool MigrateLegacyCheckpoint()
    {
        // Archive legacy v2 checkpoint before migration
        string legacyPrimary = NNModelStorage_GetLegacyPrimaryPath(m_symbol, m_timeframe);
        string archivePath = NNModelStorage_GetArchivePath(m_symbol, m_timeframe, 2);
        if(FileIsExist(legacyPrimary, FILE_COMMON))
        {
            if(NNModelStorage_ArchiveOldCheckpoint(legacyPrimary, archivePath))
                PrintFormat("[NEURAL-NET] Archived legacy v2 checkpoint | Symbol=%s | TF=%s | Archive=%s",
                            m_symbol, EnumToString(m_timeframe), archivePath);
        }

        // Load legacy v2 checkpoint
        if(!LoadLegacyCheckpointFromPath(legacyPrimary))
        {
            string legacyBackup = NNModelStorage_GetLegacyBackupPath(m_symbol, m_timeframe);
            if(FileIsExist(legacyBackup, FILE_COMMON))
            {
                if(!LoadLegacyCheckpointFromPath(legacyBackup))
                {
                    PrintFormat("[NEURAL-NET] Failed to load legacy v2 checkpoint for migration | Symbol=%s | TF=%s",
                                m_symbol, EnumToString(m_timeframe));
                    return false;
                }
            }
            else
            {
                PrintFormat("[NEURAL-NET] No loadable legacy v2 checkpoint found | Symbol=%s | TF=%s",
                            m_symbol, EnumToString(m_timeframe));
                return false;
            }
        }

        // Expand weight matrices from 25 to FEATURE_VECTOR_SIZE features
        // W1: [25][32] -> [FEATURE_VECTOR_SIZE][32], pad new rows with Xavier initialization
        double tempW1[25][32];
        for(int i = 0; i < 25; i++)
            for(int j = 0; j < 32; j++)
                tempW1[i][j] = W1[i][j];

        // Reinitialize W1 with FEATURE_VECTOR_SIZE rows
        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
            for(int j = 0; j < 32; j++)
                W1[i][j] = 0.01 * (2.0 * ((double)rand() / RAND_MAX) - 1.0) / MathSqrt(FEATURE_VECTOR_SIZE);

        // Copy original 25 rows back
        for(int i = 0; i < 25; i++)
            for(int j = 0; j < 32; j++)
                W1[i][j] = tempW1[i][j];

        // Training samples need to be cleared as they have 25-element inputs
        ClearTrainingData();
        m_tradeLinkedLabels = 0;
        m_pseudoLabels = 0;
        m_labeledSinceCheckpoint = 0;

        PrintFormat("[NEURAL-NET] Migrated v2 checkpoint to v4 | Symbol=%s | TF=%s | Features: 25->%d | Cleared training samples",
                    m_symbol, EnumToString(m_timeframe), FEATURE_VECTOR_SIZE);

        // Save as v4 checkpoint
        return SaveCheckpointAtomic(true);
    }

    bool LoadLegacyCheckpointFromPath(const string filePath)
    {
        if(!FileIsExist(filePath, FILE_COMMON))
        {
            datetime now = TimeCurrent();
            if(m_lastCheckpointDiagLogTime == 0 || (now - m_lastCheckpointDiagLogTime) >= 10)
            {
                PrintFormat("[NEURAL-NET] Legacy checkpoint file not found | Symbol=%s | TF=%s | Path=%s",
                            m_symbol, EnumToString(m_timeframe), filePath);
                m_lastCheckpointDiagLogTime = now;
            }
            return false;
        }

        int fileHandle = FileOpen(filePath, FILE_READ | FILE_BIN | FILE_COMMON);
        if(fileHandle == INVALID_HANDLE)
        {
            datetime now = TimeCurrent();
            if(m_lastCheckpointDiagLogTime == 0 || (now - m_lastCheckpointDiagLogTime) >= 10)
            {
                PrintFormat("[NEURAL-NET] Legacy checkpoint open failed | Symbol=%s | TF=%s | Path=%s | err=%d",
                            m_symbol, EnumToString(m_timeframe), filePath, GetLastError());
                m_lastCheckpointDiagLogTime = now;
            }
            return false;
        }

        int magic = FileReadInteger(fileHandle);
        int version = FileReadInteger(fileHandle);
        // Accept v2 checkpoints for migration
        if(magic != NN_CHECKPOINT_MAGIC || version != 2)
        {
            datetime now = TimeCurrent();
            if(m_lastCheckpointDiagLogTime == 0 || (now - m_lastCheckpointDiagLogTime) >= 10)
            {
                PrintFormat("[NEURAL-NET] Legacy checkpoint header mismatch | Symbol=%s | TF=%s | Path=%s | magic=%d/%d | version=%d/2",
                            m_symbol, EnumToString(m_timeframe), filePath,
                            magic, NN_CHECKPOINT_MAGIC, version);
                m_lastCheckpointDiagLogTime = now;
            }
            FileClose(fileHandle);
            return false;
        }

        string checkpointSymbol;
        if(!ReadCheckpointString(fileHandle, checkpointSymbol))
        {
            datetime now = TimeCurrent();
            if(m_lastCheckpointDiagLogTime == 0 || (now - m_lastCheckpointDiagLogTime) >= 10)
            {
                PrintFormat("[NEURAL-NET] Legacy checkpoint symbol read failed | Symbol=%s | TF=%s | Path=%s",
                            m_symbol, EnumToString(m_timeframe), filePath);
                m_lastCheckpointDiagLogTime = now;
            }
            FileClose(fileHandle);
            return false;
        }
        int checkpointTf = FileReadInteger(fileHandle);
        datetime checkpointTime = (datetime)FileReadLong(fileHandle);
        if(checkpointSymbol != m_symbol || checkpointTf != (int)m_timeframe)
        {
            datetime now = TimeCurrent();
            if(m_lastCheckpointDiagLogTime == 0 || (now - m_lastCheckpointDiagLogTime) >= 10)
            {
                PrintFormat("[NEURAL-NET] Legacy checkpoint symbol/TF mismatch | Symbol=%s/%s | TF=%d/%d | Path=%s",
                            checkpointSymbol, m_symbol, checkpointTf, (int)m_timeframe, filePath);
                m_lastCheckpointDiagLogTime = now;
            }
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

        // Load v2 weight matrices (25 features)
        for(int i = 0; i < 25; i++)
            for(int j = 0; j < 32; j++)
                W1[i][j] = FileReadDouble(fileHandle);
        for(int i = 0; i < 32; i++)
            for(int j = 0; j < 16; j++)
                W2[i][j] = FileReadDouble(fileHandle);
        for(int i = 0; i < 16; i++)
            for(int j = 0; j < 8; j++)
                W3[i][j] = FileReadDouble(fileHandle);
        for(int i = 0; i < 8; i++)
            for(int j = 0; j < 3; j++)
                W4[i][j] = FileReadDouble(fileHandle);
        for(int i = 0; i < 32; i++) B1[i] = FileReadDouble(fileHandle);
        for(int i = 0; i < 16; i++) B2[i] = FileReadDouble(fileHandle);
        for(int i = 0; i < 8; i++) B3[i] = FileReadDouble(fileHandle);
        for(int i = 0; i < 3; i++) B4[i] = FileReadDouble(fileHandle);

        // Skip training samples (they'll be cleared anyway)
        int sampleCount = FileReadInteger(fileHandle);
        if(sampleCount < 0 || sampleCount > NN_MAX_PERSISTED_SAMPLES)
        {
            datetime now = TimeCurrent();
            if(m_lastCheckpointDiagLogTime == 0 || (now - m_lastCheckpointDiagLogTime) >= 10)
            {
                PrintFormat("[NEURAL-NET] Legacy checkpoint sample count invalid | Symbol=%s | TF=%s | Path=%s | sampleCount=%d | max=%d",
                            m_symbol, EnumToString(m_timeframe), filePath, sampleCount, NN_MAX_PERSISTED_SAMPLES);
                m_lastCheckpointDiagLogTime = now;
            }
            FileClose(fileHandle);
            return false;
        }
        for(int s = 0; s < sampleCount; s++)
        {
            // Skip all training sample data
            FileReadDouble(fileHandle); // actualResult
            FileReadLong(fileHandle);   // time
            FileReadInteger(fileHandle); // hasResult
            FileReadInteger(fileHandle); // linkedToTrade
            string dummy;
            if(!ReadCheckpointString(fileHandle, dummy))
            {
                datetime now = TimeCurrent();
                if(m_lastCheckpointDiagLogTime == 0 || (now - m_lastCheckpointDiagLogTime) >= 10)
                {
                    PrintFormat("[NEURAL-NET] Legacy checkpoint sample predictionId read failed during skip | Symbol=%s | TF=%s | Path=%s | SampleIndex=%d/%d",
                                m_symbol, EnumToString(m_timeframe), filePath, s, sampleCount);
                    m_lastCheckpointDiagLogTime = now;
                }
                FileClose(fileHandle);
                return false;
            }
            FileReadInteger(fileHandle); // pseudoLabeled
            FileReadLong(fileHandle);   // labelDueTime
            FileReadDouble(fileHandle); // entryPriceSnapshot
            FileReadInteger(fileHandle); // barsAhead
            FileReadInteger(fileHandle); // isTradeLinked
            for(int k = 0; k < 25; k++) // Skip 25-element inputs
                FileReadDouble(fileHandle);
        }

        uint storedChecksum = (uint)FileReadInteger(fileHandle);
        FileClose(fileHandle);

        m_lastLoadStatus = "LOADED_LEGACY_V2";
        m_lastCheckpointTimestamp = checkpointTime;
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
        // Full backpropagation through all layers (W1, W2, W3, W4)
        
        double scaledRate = m_learningRate * MathMax(0.1, sampleWeight);

        // Forward pass to get intermediate layer values
        double hidden1[32];
        double hidden2[16];
        double hidden3[8];
        
        // Input → Hidden1
        for(int j = 0; j < 32; j++)
        {
            hidden1[j] = B1[j];
            for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
            {
                hidden1[j] += inputs[i] * W1[i][j];
            }
            hidden1[j] = ReLU(hidden1[j]);
        }
        
        // Hidden1 → Hidden2
        for(int j = 0; j < 16; j++)
        {
            hidden2[j] = B2[j];
            for(int i = 0; i < 32; i++)
            {
                hidden2[j] += hidden1[i] * W2[i][j];
            }
            hidden2[j] = ReLU(hidden2[j]);
        }
        
        // Hidden2 → Hidden3
        for(int j = 0; j < 8; j++)
        {
            hidden3[j] = B3[j];
            for(int i = 0; i < 16; i++)
            {
                hidden3[j] += hidden2[i] * W3[i][j];
            }
            hidden3[j] = ReLU(hidden3[j]);
        }
        
        // Output layer error (cross-entropy derivative)
        double outputError[3];
        for(int i = 0; i < 3; i++)
        {
            outputError[i] = outputs[i] - target[i];
        }
        
        // Backpropagate through W4 (Hidden3 → Output)
        double hidden3Error[8];
        for(int i = 0; i < 8; i++)
        {
            hidden3Error[i] = 0.0;
            for(int j = 0; j < 3; j++)
            {
                hidden3Error[i] += outputError[j] * W4[i][j];
            }
            // ReLU derivative
            hidden3Error[i] *= (hidden3[i] > 0) ? 1.0 : 0.0;
        }
        
        // Update W4 and B4
        for(int i = 0; i < 8; i++)
        {
            for(int j = 0; j < 3; j++)
            {
                W4[i][j] -= scaledRate * outputError[j] * hidden3[i];
            }
        }
        for(int i = 0; i < 3; i++)
        {
            B4[i] -= scaledRate * outputError[i];
        }
        
        // Backpropagate through W3 (Hidden2 → Hidden3)
        double hidden2Error[16];
        for(int i = 0; i < 16; i++)
        {
            hidden2Error[i] = 0.0;
            for(int j = 0; j < 8; j++)
            {
                hidden2Error[i] += hidden3Error[j] * W3[i][j];
            }
            // ReLU derivative
            hidden2Error[i] *= (hidden2[i] > 0) ? 1.0 : 0.0;
        }
        
        // Update W3 and B3
        for(int i = 0; i < 16; i++)
        {
            for(int j = 0; j < 8; j++)
            {
                W3[i][j] -= scaledRate * hidden3Error[j] * hidden2[i];
            }
        }
        for(int i = 0; i < 8; i++)
        {
            B3[i] -= scaledRate * hidden3Error[i];
        }
        
        // Backpropagate through W2 (Hidden1 → Hidden2)
        double hidden1Error[32];
        for(int i = 0; i < 32; i++)
        {
            hidden1Error[i] = 0.0;
            for(int j = 0; j < 16; j++)
            {
                hidden1Error[i] += hidden2Error[j] * W2[i][j];
            }
            // ReLU derivative
            hidden1Error[i] *= (hidden1[i] > 0) ? 1.0 : 0.0;
        }
        
        // Update W2 and B2
        for(int i = 0; i < 32; i++)
        {
            for(int j = 0; j < 16; j++)
            {
                W2[i][j] -= scaledRate * hidden2Error[j] * hidden1[i];
            }
        }
        for(int i = 0; i < 16; i++)
        {
            B2[i] -= scaledRate * hidden2Error[i];
        }
        
        // Backpropagate through W1 (Input → Hidden1)
        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
        {
            for(int j = 0; j < 32; j++)
            {
                W1[i][j] -= scaledRate * hidden1Error[j] * inputs[i];
            }
        }
        for(int i = 0; i < 32; i++)
        {
            B1[i] -= scaledRate * hidden1Error[i];
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
