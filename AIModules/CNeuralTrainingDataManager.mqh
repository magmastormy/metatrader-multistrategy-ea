//+------------------------------------------------------------------+
//| CTrainingDataManager.mqh                                          |
//| Manages training examples and barrier buffer for neural network   |
//+------------------------------------------------------------------+
#ifndef __NEURAL_TRAINING_DATA_MANAGER_MQH__
#define __NEURAL_TRAINING_DATA_MANAGER_MQH__

// ENHANCEMENT: Neural network buffer size constants (Batch 93)
#ifndef NN_MAX_TRAINING_EXAMPLES
#define NN_MAX_TRAINING_EXAMPLES 2000
#endif

#ifndef NN_MAX_PERSISTED_SAMPLES
#define NN_MAX_PERSISTED_SAMPLES 300
#endif

struct STrainingExample
{
    double   inputs[FEATURE_VECTOR_SIZE];
    int      labelClass;
    datetime time;
    bool     linkedToTrade;
    string   predictionId;
    double   signalConfidence;
    double   metaInput[ML_INPUT];

    void Reset()
    {
        ArrayInitialize(inputs, 0.0);
        labelClass = 1;
        time = 0;
        linkedToTrade = false;
        predictionId = "";
        signalConfidence = 0.0;
        ArrayInitialize(metaInput, 0.0);
    }

    STrainingExample()
    {
        Reset();
    }
};

struct SBarrierEntry
{
    int      signalClass;
    double   entryPrice;
    double   upperBarrier;
    double   lowerBarrier;
    datetime expiryTime;
    double   featureSnapshot[FEATURE_VECTOR_SIZE];
    int      featureSize;
    int      label;
    bool     resolved;
    string   predictionId;
    bool     linkedToTrade;
    double   signalConfidence;
    double   metaInput[ML_INPUT];
    datetime entryBarTime;

    void Reset()
    {
        signalClass = 0;
        entryPrice = 0.0;
        upperBarrier = 0.0;
        lowerBarrier = 0.0;
        expiryTime = 0;
        ArrayInitialize(featureSnapshot, 0.0);
        featureSize = 0;
        label = 0;
        resolved = false;
        predictionId = "";
        linkedToTrade = false;
        signalConfidence = 0.0;
        ArrayInitialize(metaInput, 0.0);
        entryBarTime = 0;
    }

    SBarrierEntry()
    {
        Reset();
    }
};

class CTrainingDataManager
{
private:
    STrainingExample m_trainingBuffer[NN_MAX_TRAINING_EXAMPLES];
    int              m_trainHead;
    int              m_trainCount;
    SBarrierEntry   m_barrierBuffer[NN_MAX_PERSISTED_SAMPLES];
    int              m_barrierHead;
    int              m_barrierCount;
    double           m_barrierK;
    int              m_barrierVertBars;
    long             m_resolvedLabelCount;

public:
    CTrainingDataManager()
    {
        Reset();
    }

    void Reset()
    {
        m_trainHead = 0;
        m_trainCount = 0;
        for(int i = 0; i < NN_MAX_TRAINING_EXAMPLES; i++)
            m_trainingBuffer[i].Reset();
        m_barrierHead = 0;
        m_barrierCount = 0;
        for(int i = 0; i < NN_MAX_PERSISTED_SAMPLES; i++)
            m_barrierBuffer[i].Reset();
        m_barrierK = 1.5;
        m_barrierVertBars = 20;
        m_resolvedLabelCount = 0;
    }

    void SetBarrierParams(const double k, const int vertBars)
    {
        m_barrierK = MathMax(0.5, MathMin(5.0, k));
        m_barrierVertBars = MathMax(5, MathMin(200, vertBars));
    }

    int AddTrainingExample(const double &inputs[], const int labelClass, const datetime time,
                          const double confidence, const string &predictionId, const double &metaInput[])
    {
        int idx = m_trainHead % NN_MAX_TRAINING_EXAMPLES;
        for(int i = 0; i < FEATURE_VECTOR_SIZE && i < ArraySize(inputs); i++)
            m_trainingBuffer[idx].inputs[i] = inputs[i];
        m_trainingBuffer[idx].labelClass = labelClass;
        m_trainingBuffer[idx].time = time;
        m_trainingBuffer[idx].linkedToTrade = false;
        m_trainingBuffer[idx].predictionId = predictionId;
        m_trainingBuffer[idx].signalConfidence = confidence;
        if(ArraySize(metaInput) >= ML_INPUT)
            for(int i = 0; i < ML_INPUT; i++)
                m_trainingBuffer[idx].metaInput[i] = metaInput[i];
        
        m_trainHead++;
        if(m_trainCount < NN_MAX_TRAINING_EXAMPLES)
            m_trainCount++;
        
        return idx;
    }

    bool GetTrainingBatch(double &inputs[][], int &labels[], const int batchSize, const int maxFeatures)
    {
        if(m_trainCount < batchSize)
            return false;
        
        // Resize both dimensions upfront
        ArrayResize(inputs, batchSize, maxFeatures);
        ArrayResize(labels, batchSize);
        
        for(int b = 0; b < batchSize; b++)
        {
            int idx = (m_trainHead - batchSize + b) % NN_MAX_TRAINING_EXAMPLES;
            if(idx < 0) idx += NN_MAX_TRAINING_EXAMPLES;
            
            // Copy features to pre-sized row
            for(int i = 0; i < maxFeatures && i < FEATURE_VECTOR_SIZE; i++)
                inputs[b][i] = m_trainingBuffer[idx].inputs[i];
            labels[b] = m_trainingBuffer[idx].labelClass;
        }
        
        return true;
    }

    int AddBarrierEntry(const int signalClass, const double entryPrice,
                        const double upperBarrier, const double lowerBarrier,
                        const datetime expiryTime, const double &features[],
                        const datetime entryBarTime, const string &predictionId,
                        const double confidence, const double &metaInput[])
    {
        int idx = m_barrierHead % NN_MAX_PERSISTED_SAMPLES;
        m_barrierBuffer[idx].signalClass = signalClass;
        m_barrierBuffer[idx].entryPrice = entryPrice;
        m_barrierBuffer[idx].upperBarrier = upperBarrier;
        m_barrierBuffer[idx].lowerBarrier = lowerBarrier;
        m_barrierBuffer[idx].expiryTime = expiryTime;
        for(int i = 0; i < FEATURE_VECTOR_SIZE && i < ArraySize(features); i++)
            m_barrierBuffer[idx].featureSnapshot[i] = features[i];
        m_barrierBuffer[idx].featureSize = MathMin(FEATURE_VECTOR_SIZE, ArraySize(features));
        m_barrierBuffer[idx].label = 0;
        m_barrierBuffer[idx].resolved = false;
        m_barrierBuffer[idx].predictionId = predictionId;
        m_barrierBuffer[idx].linkedToTrade = false;
        m_barrierBuffer[idx].signalConfidence = confidence;
        m_barrierBuffer[idx].entryBarTime = entryBarTime;
        if(ArraySize(metaInput) >= ML_INPUT)
            for(int i = 0; i < ML_INPUT; i++)
                m_barrierBuffer[idx].metaInput[i] = metaInput[i];
        
        m_barrierHead++;
        if(m_barrierCount < NN_MAX_PERSISTED_SAMPLES)
            m_barrierCount++;
        
        return idx;
    }

    int ResolveExpiredBarriers(const datetime timeNow, const double currentPrice,
                               const string symbol = "", const ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT)
    {
        int resolved = 0;
        for(int i = 0; i < m_barrierCount && i < NN_MAX_PERSISTED_SAMPLES; i++)
        {
            if(m_barrierBuffer[i].resolved)
                continue;
            if(timeNow < m_barrierBuffer[i].expiryTime)
                continue;

            double exitPrice = currentPrice;

            if(symbol != "" && m_barrierBuffer[i].entryBarTime > 0)
            {
                datetime barTime = iTime(symbol, timeframe, 0);
                if(barTime > m_barrierBuffer[i].entryBarTime)
                {
                    double high = iHigh(symbol, timeframe, 1);
                    double low = iLow(symbol, timeframe, 1);
                    if(high > 0 && low > 0)
                    {
                        if(high >= m_barrierBuffer[i].upperBarrier)
                        {
                            m_barrierBuffer[i].label = 2;
                            m_barrierBuffer[i].resolved = true;
                            m_resolvedLabelCount++;
                            resolved++;
                            continue;
                        }
                        if(low <= m_barrierBuffer[i].lowerBarrier)
                        {
                            m_barrierBuffer[i].label = 1;
                            m_barrierBuffer[i].resolved = true;
                            m_resolvedLabelCount++;
                            resolved++;
                            continue;
                        }
                    }
                }
            }

            int label = CBarrierLabelResolver::ResolveLabel(
                m_barrierBuffer[i].upperBarrier,
                m_barrierBuffer[i].lowerBarrier,
                exitPrice,
                m_barrierBuffer[i].entryPrice,
                m_barrierBuffer[i].expiryTime,
                timeNow
            );

            m_barrierBuffer[i].label = label;
            m_barrierBuffer[i].resolved = true;
            m_resolvedLabelCount++;
            resolved++;
        }
        return resolved;
    }

    int GetBarrierCount() const { return m_barrierCount; }
    int GetBarrierResolvedCount() const { return (int)m_resolvedLabelCount; }
    int GetTrainingCount() const { return m_trainCount; }

    bool GetBarrierAt(const int idx, SBarrierEntry &entry) const
    {
        if(idx < 0 || idx >= m_barrierCount || idx >= NN_MAX_PERSISTED_SAMPLES)
            return false;
        entry = m_barrierBuffer[idx];
        return true;
    }

    STrainingExample GetTrainingExample(const int idx) const
    {
        if(idx < 0 || idx >= m_trainCount || idx >= NN_MAX_TRAINING_EXAMPLES)
            return STrainingExample();
        return m_trainingBuffer[idx];
    }

    int GetPersistedSampleCount() const { return MathMin(m_barrierCount, NN_MAX_PERSISTED_SAMPLES); }
    int GetPersistedTrainingCount() const { return MathMin(m_trainCount, NN_MAX_TRAINING_EXAMPLES); }

    void GetBarrierAtIndex(const int idx, SBarrierEntry &entry) const
    {
        if(idx < 0 || idx >= NN_MAX_PERSISTED_SAMPLES)
        {
            entry.Reset();
            return;
        }
        entry = m_barrierBuffer[idx];
    }

    void GetTrainingAtIndex(const int idx, STrainingExample &example) const
    {
        if(idx < 0 || idx >= NN_MAX_TRAINING_EXAMPLES)
        {
            example.Reset();
            return;
        }
        example = m_trainingBuffer[idx];
    }
};

#endif // __NEURAL_TRAINING_DATA_MANAGER_MQH__
