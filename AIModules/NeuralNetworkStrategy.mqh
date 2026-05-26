//+------------------------------------------------------------------+
//| NeuralNetworkStrategy.mqh                                        |
//| Online MLP with adaptive normalization and triple-barrier labels |
//+------------------------------------------------------------------+
#property strict

#ifndef __NEURAL_NETWORK_STRATEGY_MQH__
#define __NEURAL_NETWORK_STRATEGY_MQH__

#include "../Core/Utils/Enums.mqh"
#include "../Core/AI/NNModelStorage.mqh"
#include "../Core/AI/AIFeatureVectorBuilder.mqh"
#include "TransformerBrain.mqh"
#include "MetaLabeler.mqh"
#include "CNeuralCore.mqh"
#include "CNeuralTrainingDataManager.mqh"
#include "CNeuralCheckpointManager.mqh"

#define NN_CHECKPOINT_MAGIC 1313758027
#define NN_CHECKPOINT_VERSION 7
#define NN_MAX_PERSISTED_SAMPLES 300
#define NN_MAX_TRAINING_EXAMPLES 2000
#define NN_MIN_NORMALIZATION_SAMPLES 30

class CConformalPredictor
{
private:
    double m_scores[];
    int    m_head;
    int    m_count;
    double m_alpha;
    double m_alphaACI;
    double m_gammaACI;
    double m_quantile;

    void Recompute()
    {
        if(m_count < 10)
        {
            m_quantile = 1.0;
            return;
        }

        double values[];
        ArrayResize(values, m_count);
        for(int i = 0; i < m_count; i++)
            values[i] = m_scores[i];
        ArraySort(values);

        double quantileLevel = (1.0 - m_alphaACI) * (1.0 + 1.0 / (double)m_count);
        int idx = (int)MathCeil(quantileLevel * (double)m_count) - 1;
        idx = MathMax(0, MathMin(idx, m_count - 1));
        m_quantile = values[idx];
    }

public:
    void Init(const double alpha = 0.05)
    {
        ArrayResize(m_scores, 200);
        ArrayInitialize(m_scores, 1.0);
        m_head = 0;
        m_count = 0;
        m_alpha = alpha;
        m_alphaACI = alpha;
        m_gammaACI = 0.005;
        m_quantile = 1.0;
    }

    void AddScore(const double score)
    {
        m_scores[m_head % ArraySize(m_scores)] = score;
        m_head++;
        if(m_count < ArraySize(m_scores))
            m_count++;
        Recompute();
    }

    void UpdateACI(const bool correct)
    {
        m_alphaACI += m_gammaACI * ((correct ? 0.0 : 1.0) - m_alpha);
        m_alphaACI = MathMax(0.005, MathMin(0.5, m_alphaACI));
        Recompute();
    }

    bool Approve(const double predictedConfidence) const
    {
        return (1.0 - predictedConfidence) <= m_quantile;
    }

    double GetQuantile() const { return m_quantile; }
    double GetAlpha() const { return m_alphaACI; }
    double GetLastUncertainty() const { return m_quantile; }
};

class CNeuralRegimeTracker
{
private:
    double m_probs[4];

public:
    void Init()
    {
        for(int i = 0; i < 4; i++)
            m_probs[i] = 0.25;
    }

    void Update(const double atrRatio, const double trendSignal)
    {
        double target[4] = {0.0, 0.0, 0.0, 0.0};
        if(atrRatio > 1.35)
        {
            target[3] = 1.0;
        }
        else if(trendSignal > 0.02)
        {
            target[0] = 1.0;
        }
        else if(trendSignal < -0.02)
        {
            target[1] = 1.0;
        }
        else
        {
            target[2] = 1.0;
        }

        for(int i = 0; i < 4; i++)
            m_probs[i] = 0.95 * m_probs[i] + 0.05 * target[i];

        double sum = 0.0;
        for(int i = 0; i < 4; i++)
            sum += m_probs[i];
        if(sum <= 1e-9)
            sum = 1.0;
        for(int i = 0; i < 4; i++)
            m_probs[i] /= sum;
    }

    void GetProbabilities(double &out[])
    {
        ArrayResize(out, 4);
        for(int i = 0; i < 4; i++)
            out[i] = m_probs[i];
    }
    
    int GetCurrentRegime() const
    {
        // Return index of highest probability regime
        int bestIdx = 0;
        double maxProb = m_probs[0];
        for(int i = 1; i < 4; i++)
        {
            if(m_probs[i] > maxProb)
            {
                maxProb = m_probs[i];
                bestIdx = i;
            }
        }
        return bestIdx;
    }
};

class CNeuralNetworkStrategy;

class CFeatureImportance
{
private:
    double m_importance[];
    int    m_featureCount;
    int    m_evalCounter;
    int    m_evalInterval;

public:
    void Init(const int featureCount, const int evalInterval = 100)
    {
        m_featureCount = MathMax(1, featureCount);
        m_evalInterval = MathMax(1, evalInterval);
        m_evalCounter = 0;
        ArrayResize(m_importance, m_featureCount);
        ArrayInitialize(m_importance, 0.0);
    }

    void Deinit() {}
    void Update(const double &features[], const int size, const double baseConfidence, CNeuralNetworkStrategy &nn);
    void LogTopFeatures(const int topN = 10);
};

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

class CNeuralOptimizer
{
private:
    double m_adamM[];
    double m_adamV[];
    long   m_adamStep;
    double m_adamBeta1;
    double m_adamBeta2;
    double m_adamEps;
    double m_adamWD;
    double m_adamLR;

public:
    void Init(const int paramCount)
    {
        if(paramCount <= 0) return;
        
        int currentSizeM = ArraySize(m_adamM);
        int currentSizeV = ArraySize(m_adamV);
        
        if(currentSizeM != paramCount)
            ArrayResize(m_adamM, paramCount);
        if(currentSizeV != paramCount)
            ArrayResize(m_adamV, paramCount);
        
        ArrayInitialize(m_adamM, 0.0);
        ArrayInitialize(m_adamV, 0.0);
        m_adamStep = 0;
        m_adamBeta1 = 0.9;
        m_adamBeta2 = 0.999;
        m_adamEps = 1e-8;
        m_adamWD = 1e-4;
        m_adamLR = 3e-4;
    }
    
    double GetCyclicLR() const
    {
        int cycleLen = 1000;
        double progress = (double)(m_adamStep % cycleLen) / (double)cycleLen;
        return m_adamLR * (0.1 + 0.9 * 0.5 * (1.0 + MathCos(M_PI * progress)));
    }
    
    void Update(double &param, const int paramIndex, const double grad)
    {
        m_adamM[paramIndex] = m_adamBeta1 * m_adamM[paramIndex] + (1.0 - m_adamBeta1) * grad;
        m_adamV[paramIndex] = m_adamBeta2 * m_adamV[paramIndex] + (1.0 - m_adamBeta2) * grad * grad;
        double mHat = m_adamM[paramIndex] / (1.0 - MathPow(m_adamBeta1, (double)m_adamStep));
        double vHat = m_adamV[paramIndex] / (1.0 - MathPow(m_adamBeta2, (double)m_adamStep));
        double lr = GetCyclicLR();
        param -= lr * ((mHat / (MathSqrt(vHat) + m_adamEps)) + (m_adamWD * param));
        m_adamStep++;
    }
    
    long GetStep() const { return m_adamStep; }
    void SetStep(const long step) { m_adamStep = step; }
    
    void GetState(double &adamM[], double &adamV[])
    {
        ArrayResize(adamM, ArraySize(m_adamM));
        ArrayResize(adamV, ArraySize(m_adamV));
        ArrayCopy(adamM, m_adamM);
        ArrayCopy(adamV, m_adamV);
    }
    
    void SetState(const double &adamM[], const double &adamV[])
    {
        int size = MathMin(ArraySize(adamM), ArraySize(m_adamM));
        ArrayResize(m_adamM, size);
        ArrayResize(m_adamV, size);
        ArrayCopy(m_adamM, adamM, 0, 0, size);
        ArrayCopy(m_adamV, adamV, 0, 0, size);
    }
};

// NOTE: CNeuralCore is now defined in CNeuralCore.mqh (included above)
// The inline definition has been removed to avoid duplicate class errors

class CBarrierLabelResolver
{
public:
    static int ResolveLabel(const double upperBarrier, const double lowerBarrier, 
                           const double exitPrice, const double entryPrice,
                           const datetime expiryTime, const datetime currentTimestamp)
    {
        if(exitPrice <= 0.0 || entryPrice <= 0.0)
            return 0;
        
        double upperDist = MathAbs(upperBarrier - entryPrice);
        double lowerDist = MathAbs(entryPrice - lowerBarrier);
        
        if(upperDist < lowerDist)
            return 2;
        else if(lowerDist < upperDist)
            return 1;
        else
            return 0;
    }
    
    static double CalculateBarrierRatio(const double upperBarrier, const double lowerBarrier, const double entryPrice)
    {
        if(entryPrice <= 0.0)
            return 1.0;
        
        double upperDist = MathAbs(upperBarrier - entryPrice);
        double lowerDist = MathAbs(entryPrice - lowerBarrier);
        double totalDist = upperDist + lowerDist;
        
        if(totalDist <= 0.0)
            return 1.0;
        
        return upperDist / totalDist;
    }
};

class CNeuralNetworkStrategy
{
private:
    double W1[FEATURE_VECTOR_SIZE][32];
    double W2[32][16];
    double W3[16][8];
    double W4[8][3];
    double B1[32];
    double B2[16];
    double B3[8];
    double B4[3];

    double m_adamM[];
    double m_adamV[];
    long   m_adamStep;
    double m_adamBeta1;
    double m_adamBeta2;
    double m_adamEps;
    double m_adamWD;
    double m_adamLR;

    double m_featureMean[];
    double m_featureM2[];
    long   m_featureCount;
    bool   m_normalizationReady;
    double m_normalizationDecay;  // EMA decay factor for adaptive normalization

    STrainingExample m_trainingBuffer[NN_MAX_TRAINING_EXAMPLES];
    int              m_trainHead;
    int              m_trainCount;
    SBarrierEntry    m_barrierBuffer[NN_MAX_PERSISTED_SAMPLES];
    int              m_barrierHead;
    int              m_barrierCount;
    double           m_barrierK;
    int              m_barrierVertBars;
    long             m_resolvedLabelCount;

    string           m_symbol;
    ENUM_TIMEFRAMES  m_timeframe;
    bool             m_initialized;
    bool             m_enableOnlineTraining;
    bool             m_enableSelfLabeling;
    int              m_sampleIntervalSec;
    int              m_checkpointEveryLabeled;
    int              m_labeledSinceCheckpoint;
    int              m_epoch;
    double           m_lastLoss;
    int              m_trainingSteps;
    int              m_checkpointWrites;
    double           m_temperature;  // Temperature for confidence calibration
    int              m_totalObservations;
    int              m_tradeLinkedLabels;
    double           m_minConfidence;
    datetime         m_lastObservationTime;
    datetime         m_lastSignalLogTime;
    datetime         m_lastCheckpointTimestamp;
    datetime         m_lastNormalizationBarTime;
    datetime         m_lastResolvedBarTime;
    datetime         m_lastSelfRecordBarTime;
    datetime         m_lastFeatureImportanceLogTime;
    datetime         m_cacheBarTime;
    bool             m_hasCachedSignal;
    ENUM_TRADE_SIGNAL m_cachedSignal;
    double           m_cachedConfidence;
    string           m_lastLoadStatus;
    uint             m_randomState;
    CTransformerBrain* m_transformerRef;
    bool             m_ownsTransformerRef;
    CConformalPredictor m_conformal;
    CMetaLabeler       m_metaLabeler;
    CNeuralRegimeTracker m_regimeTracker;
    CFeatureImportance  m_featureImportance;

    int TotalParamCount() const
    {
        return FEATURE_VECTOR_SIZE * 32 + 32 * 16 + 16 * 8 + 8 * 3 + 32 + 16 + 8 + 3;
    }

    int OffsetW1() const { return 0; }
    int OffsetW2() const { return OffsetW1() + FEATURE_VECTOR_SIZE * 32; }
    int OffsetW3() const { return OffsetW2() + 32 * 16; }
    int OffsetW4() const { return OffsetW3() + 16 * 8; }
    int OffsetB1() const { return OffsetW4() + 8 * 3; }
    int OffsetB2() const { return OffsetB1() + 32; }
    int OffsetB3() const { return OffsetB2() + 16; }
    int OffsetB4() const { return OffsetB3() + 8; }

    double NextRand()
    {
        m_randomState = m_randomState * 1664525 + 1013904223;
        return (double)m_randomState / 4294967296.0;
    }

    string GeneratePredictionId()
    {
        ulong timePart = (ulong)(GetMicrosecondCount() % 1000000000);
        return StringFormat("%s_%09I64u_%d", m_symbol, timePart, m_totalObservations + m_trainCount + m_barrierHead);
    }

    bool WriteCheckpointString(const int fileHandle, const string value)
    {
        int len = (int)StringLen(value);
        FileWriteInteger(fileHandle, len);
        for(int i = 0; i < len; i++)
            FileWriteInteger(fileHandle, (int)StringGetCharacter(value, i));
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
            StringSetCharacter(value, i, (ushort)FileReadInteger(fileHandle));
        return true;
    }

    double RandNormal()
    {
        double u1 = (NextRand() + 1.0) / (4294967296.0 + 1.0);
        double u2 = (NextRand() + 1.0) / (4294967296.0 + 1.0);
        return MathSqrt(-2.0 * MathLog(MathMax(u1, 1e-10))) * MathCos(2.0 * M_PI * u2);
    }

    void InitWeights()
    {
        double scale1 = MathSqrt(2.0 / ((double)(FEATURE_VECTOR_SIZE + 32)));
        double scale2 = MathSqrt(2.0 / ((double)(32 + 16)));
        double scale3 = MathSqrt(2.0 / ((double)(16 + 8)));
        double scale4 = MathSqrt(2.0 / ((double)(8 + 3)));

        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
            for(int j = 0; j < 32; j++)
                W1[i][j] = RandNormal() * scale1;
        for(int i = 0; i < 32; i++)
            for(int j = 0; j < 16; j++)
                W2[i][j] = RandNormal() * scale2;
        for(int i = 0; i < 16; i++)
            for(int j = 0; j < 8; j++)
                W3[i][j] = RandNormal() * scale3;
        for(int i = 0; i < 8; i++)
            for(int j = 0; j < 3; j++)
                W4[i][j] = RandNormal() * scale4;

        ArrayInitialize(B1, 0.0);
        ArrayInitialize(B2, 0.0);
        ArrayInitialize(B3, 0.0);
        ArrayInitialize(B4, 0.0);
    }

    void InitOptimizer()
    {
        int total = TotalParamCount();
        if(total <= 0)
        {
            PrintFormat("[NEURAL-NET] ERROR: InitOptimizer called with invalid param count=%d", total);
            return;
        }

        // Only resize if current size doesn't match required size
        int currentSizeM = ArraySize(m_adamM);
        int currentSizeV = ArraySize(m_adamV);
        
        if(currentSizeM != total)
            ArrayResize(m_adamM, total);
        if(currentSizeV != total)
            ArrayResize(m_adamV, total);
        
        ArrayInitialize(m_adamM, 0.0);
        ArrayInitialize(m_adamV, 0.0);
        m_adamStep = 0;
        m_adamBeta1 = 0.9;
        m_adamBeta2 = 0.999;
        m_adamEps = 1e-8;
        m_adamWD = 1e-4;
        m_adamLR = 3e-4;
    }

    double GetCyclicLR() const
    {
        int cycleLen = 1000;
        double progress = (double)(m_adamStep % cycleLen) / (double)cycleLen;
        return m_adamLR * (0.1 + 0.9 * 0.5 * (1.0 + MathCos(M_PI * progress)));
    }

    void AdamWUpdate(double &param, const int paramIndex, const double grad)
    {
        m_adamM[paramIndex] = m_adamBeta1 * m_adamM[paramIndex] + (1.0 - m_adamBeta1) * grad;
        m_adamV[paramIndex] = m_adamBeta2 * m_adamV[paramIndex] + (1.0 - m_adamBeta2) * grad * grad;
        double mHat = m_adamM[paramIndex] / (1.0 - MathPow(m_adamBeta1, (double)m_adamStep));
        double vHat = m_adamV[paramIndex] / (1.0 - MathPow(m_adamBeta2, (double)m_adamStep));
        double lr = GetCyclicLR();
        param -= lr * ((mHat / (MathSqrt(vHat) + m_adamEps)) + (m_adamWD * param));
    }

    void UpdateNormalizationStats(const double &rawFeatures[], const int size)
    {
        m_featureCount++;
        
        // Use EMA decay for adaptive normalization
        // This allows the normalization statistics to adapt to changing market conditions
        double alpha = m_normalizationDecay;
        
        for(int i = 0; i < size; i++)
        {
            double delta = rawFeatures[i] - m_featureMean[i];
            
            // Update mean with EMA
            m_featureMean[i] = (1.0 - alpha) * m_featureMean[i] + alpha * rawFeatures[i];
            
            // Update variance with Welford's algorithm combined with EMA
            double delta2 = rawFeatures[i] - m_featureMean[i];
            m_featureM2[i] = (1.0 - alpha) * m_featureM2[i] + alpha * delta * delta2;
        }
        
        if(m_featureCount >= NN_MIN_NORMALIZATION_SAMPLES)
            m_normalizationReady = true;
    }

    void NormalizeFeatures(double &features[], const int size)
    {
        if(!m_normalizationReady)
        {
            for(int i = 0; i < size; i++)
                features[i] = MathMax(-3.0, MathMin(3.0, features[i]));
            return;
        }

        for(int i = 0; i < size; i++)
        {
            double variance = (m_featureCount > 1) ? (m_featureM2[i] / (double)(m_featureCount - 1)) : 1.0;
            double stddev = MathSqrt(variance + 1e-9);
            features[i] = (features[i] - m_featureMean[i]) / stddev;
            features[i] = MathMax(-3.0, MathMin(3.0, features[i]));
        }
    }

    datetime FeatureBarTime() const
    {
        return (m_symbol == "") ? 0 : iTime(m_symbol, m_timeframe, 1);
    }

    datetime CurrentBarTime() const
    {
        return (m_symbol == "") ? 0 : iTime(m_symbol, m_timeframe, 0);
    }

    bool ExtractFeatures(double &normalizedFeatures[], double &rawFeatures[])
    {
        if(!CAIFeatureVectorBuilder::BuildNNFeatureVector(m_symbol, m_timeframe, rawFeatures, 1))
            return false;

        ArrayResize(normalizedFeatures, FEATURE_VECTOR_SIZE);
        ArrayCopy(normalizedFeatures, rawFeatures, 0, 0, FEATURE_VECTOR_SIZE);

        datetime barTime = FeatureBarTime();
        if(barTime > 0 && barTime != m_lastNormalizationBarTime)
        {
            UpdateNormalizationStats(rawFeatures, FEATURE_VECTOR_SIZE);
            m_lastNormalizationBarTime = barTime;
        }

        NormalizeFeatures(normalizedFeatures, FEATURE_VECTOR_SIZE);
        m_regimeTracker.Update(rawFeatures[15], rawFeatures[8]);
        return true;
    }

    double ReLU(const double value) const
    {
        return MathMax(0.0, value);
    }

    void Softmax(double &values[], const int size, const double temperature = 1.0) const
    {
        double maxVal = values[0];
        for(int i = 1; i < size; i++)
            maxVal = MathMax(maxVal, values[i]);

        double safeTemp = MathMax(1e-6, temperature);
        double sum = 0.0;
        for(int i = 0; i < size; i++)
        {
            values[i] = MathExp((values[i] - maxVal) / safeTemp);
            sum += values[i];
        }
        if(sum <= 1e-12)
            sum = 1.0;
        for(int i = 0; i < size; i++)
            values[i] /= sum;
    }

    void ForwardDetailed(const double &inputs[],
                         double &hidden1[],
                         double &hidden2[],
                         double &hidden3[],
                         double &outputs[])
    {
        ArrayResize(hidden1, 32);
        ArrayResize(hidden2, 16);
        ArrayResize(hidden3, 8);
        ArrayResize(outputs, 3);

        for(int j = 0; j < 32; j++)
        {
            double sum = B1[j];
            for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
                sum += inputs[i] * W1[i][j];
            hidden1[j] = ReLU(sum);
        }

        for(int j = 0; j < 16; j++)
        {
            double sum = B2[j];
            for(int i = 0; i < 32; i++)
                sum += hidden1[i] * W2[i][j];
            hidden2[j] = ReLU(sum);
        }

        for(int j = 0; j < 8; j++)
        {
            double sum = B3[j];
            for(int i = 0; i < 16; i++)
                sum += hidden2[i] * W3[i][j];
            hidden3[j] = ReLU(sum);
        }

        for(int j = 0; j < 3; j++)
        {
            double sum = B4[j];
            for(int i = 0; i < 8; i++)
                sum += hidden3[i] * W4[i][j];
            outputs[j] = sum;
        }
        CNeuralCore::Softmax(outputs, 3, m_temperature);
    }

    void ForwardPropagate(const double &inputs[], double &outputs[])
    {
        double h1[];
        double h2[];
        double h3[];
        ForwardDetailed(inputs, h1, h2, h3, outputs);
    }

    double CalculateLoss(const double &outputs[], const int targetClass) const
    {
        if(targetClass < 0 || targetClass >= 3 || ArraySize(outputs) != 3)
            return 0.0;
        return -MathLog(MathMax(outputs[targetClass], 1e-10));
    }

    void BackpropagateAndUpdate(const double &inputs[], const int targetClass)
    {
        double hidden1[];
        double hidden2[];
        double hidden3[];
        double outputs[];
        ForwardDetailed(inputs, hidden1, hidden2, hidden3, outputs);

        double outputError[3];
        for(int i = 0; i < 3; i++)
            outputError[i] = outputs[i] - ((i == targetClass) ? 1.0 : 0.0);

        double hidden3Error[8];
        for(int i = 0; i < 8; i++)
        {
            double sum = 0.0;
            for(int j = 0; j < 3; j++)
                sum += outputError[j] * W4[i][j];
            hidden3Error[i] = (hidden3[i] > 0.0) ? sum : 0.0;
        }

        double hidden2Error[16];
        for(int i = 0; i < 16; i++)
        {
            double sum = 0.0;
            for(int j = 0; j < 8; j++)
                sum += hidden3Error[j] * W3[i][j];
            hidden2Error[i] = (hidden2[i] > 0.0) ? sum : 0.0;
        }

        double hidden1Error[32];
        for(int i = 0; i < 32; i++)
        {
            double sum = 0.0;
            for(int j = 0; j < 16; j++)
                sum += hidden2Error[j] * W2[i][j];
            hidden1Error[i] = (hidden1[i] > 0.0) ? sum : 0.0;
        }

        m_adamStep++;
        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
        {
            for(int j = 0; j < 32; j++)
            {
                int idx = OffsetW1() + i * 32 + j;
                AdamWUpdate(W1[i][j], idx, hidden1Error[j] * inputs[i]);
            }
        }
        for(int i = 0; i < 32; i++)
            AdamWUpdate(B1[i], OffsetB1() + i, hidden1Error[i]);

        for(int i = 0; i < 32; i++)
        {
            for(int j = 0; j < 16; j++)
            {
                int idx = OffsetW2() + i * 16 + j;
                AdamWUpdate(W2[i][j], idx, hidden2Error[j] * hidden1[i]);
            }
        }
        for(int i = 0; i < 16; i++)
            AdamWUpdate(B2[i], OffsetB2() + i, hidden2Error[i]);

        for(int i = 0; i < 16; i++)
        {
            for(int j = 0; j < 8; j++)
            {
                int idx = OffsetW3() + i * 8 + j;
                AdamWUpdate(W3[i][j], idx, hidden3Error[j] * hidden2[i]);
            }
        }
        for(int i = 0; i < 8; i++)
            AdamWUpdate(B3[i], OffsetB3() + i, hidden3Error[i]);

        for(int i = 0; i < 8; i++)
        {
            for(int j = 0; j < 3; j++)
            {
                int idx = OffsetW4() + i * 3 + j;
                AdamWUpdate(W4[i][j], idx, outputError[j] * hidden3[i]);
            }
        }
        for(int i = 0; i < 3; i++)
            AdamWUpdate(B4[i], OffsetB4() + i, outputError[i]);
    }

    bool ComputeSignalContext(const double &normalizedFeatures[],
                              const double &rawFeatures[],
                              ENUM_TRADE_SIGNAL &signal,
                              double &confidence,
                              double &metaInput[],
                              double &probabilities[])
    {
        ForwardPropagate(normalizedFeatures, probabilities);
        double noneProb = probabilities[0];
        double buyProb = probabilities[1];
        double sellProb = probabilities[2];

        signal = TRADE_SIGNAL_NONE;
        confidence = 0.0;
        if(buyProb > sellProb && buyProb > noneProb)
        {
            signal = TRADE_SIGNAL_BUY;
            confidence = buyProb;
        }
        else if(sellProb > buyProb && sellProb > noneProb)
        {
            signal = TRADE_SIGNAL_SELL;
            confidence = sellProb;
        }

        double regimeProbs[];
        m_regimeTracker.GetProbabilities(regimeProbs);

        double featSubset[];
        ArrayResize(featSubset, 10);
        for(int i = 0; i < 10; i++)
            featSubset[i] = (i < ArraySize(normalizedFeatures)) ? normalizedFeatures[i] : 0.0;

        m_metaLabeler.BuildInput(confidence, regimeProbs, rawFeatures[15], featSubset, metaInput);

        if(signal != TRADE_SIGNAL_NONE)
        {
            if(confidence < m_minConfidence)
                signal = TRADE_SIGNAL_NONE;
            else if(!m_conformal.Approve(confidence))
                signal = TRADE_SIGNAL_NONE;
            else if(!m_metaLabeler.Approve(metaInput))
                signal = TRADE_SIGNAL_NONE;
        }

        if(signal == TRADE_SIGNAL_NONE)
            confidence = 0.0;

        return true;
    }

    bool RecordBarrierEntry(const int signalClass,
                            const double atr,
                            const double &features[],
                            const int featSize,
                            const string predictionId,
                            const bool linkedToTrade,
                            const double signalConfidence,
                            const double &metaInput[])
    {
        // Allow signalClass=0 (HOLD) for pseudo-labeling, but require ATR for directional signals
        if(signalClass < 0 || signalClass > 2)
            return false;
        if(signalClass != 0 && atr <= 0.0)
            return false;

        int idx = m_barrierHead % NN_MAX_PERSISTED_SAMPLES;
        double entryPrice = iClose(m_symbol, m_timeframe, 0);
        if(entryPrice <= 0.0)
            entryPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
        if(entryPrice <= 0.0)
            return false;

        m_barrierBuffer[idx].Reset();
        m_barrierBuffer[idx].signalClass = signalClass;
        m_barrierBuffer[idx].entryPrice = entryPrice;
        m_barrierBuffer[idx].upperBarrier = entryPrice + m_barrierK * atr;
        m_barrierBuffer[idx].lowerBarrier = entryPrice - m_barrierK * atr;
        m_barrierBuffer[idx].expiryTime = TimeCurrent() + (datetime)(m_barrierVertBars * MathMax(1, PeriodSeconds(m_timeframe)));
        m_barrierBuffer[idx].featureSize = MathMin(featSize, FEATURE_VECTOR_SIZE);
        for(int i = 0; i < m_barrierBuffer[idx].featureSize; i++)
            m_barrierBuffer[idx].featureSnapshot[i] = features[i];
        m_barrierBuffer[idx].predictionId = predictionId;
        m_barrierBuffer[idx].linkedToTrade = linkedToTrade;
        m_barrierBuffer[idx].signalConfidence = signalConfidence;
        ArrayCopy(m_barrierBuffer[idx].metaInput, metaInput);
        m_barrierBuffer[idx].entryBarTime = FeatureBarTime();
        m_barrierHead++;
        if(m_barrierCount < NN_MAX_PERSISTED_SAMPLES)
            m_barrierCount++;
        return true;
    }

    void PushTrainingExample(const STrainingExample &example)
    {
        if(NN_MAX_TRAINING_EXAMPLES <= 0)
            return;

        if(m_trainHead < 0 || m_trainHead >= NN_MAX_TRAINING_EXAMPLES)
            m_trainHead = ((m_trainHead % NN_MAX_TRAINING_EXAMPLES) + NN_MAX_TRAINING_EXAMPLES) % NN_MAX_TRAINING_EXAMPLES;
        if(m_trainCount < 0)
            m_trainCount = 0;
        if(m_trainCount > NN_MAX_TRAINING_EXAMPLES)
            m_trainCount = NN_MAX_TRAINING_EXAMPLES;

        int writeIndex = m_trainHead;
        m_trainingBuffer[writeIndex] = example;
        m_trainHead = (writeIndex + 1) % NN_MAX_TRAINING_EXAMPLES;
        if(m_trainCount < NN_MAX_TRAINING_EXAMPLES)
            m_trainCount++;
    }

    void AddTrainingExample(const double &features[],
                            const int featSize,
                            const int classIdx,
                            const bool linkedToTrade,
                            const string predictionId,
                            const double signalConfidence,
                            const double &metaInput[])
    {
        STrainingExample example;
        example.Reset();
        int count = MathMin(featSize, FEATURE_VECTOR_SIZE);
        for(int i = 0; i < count; i++)
            example.inputs[i] = features[i];
        example.labelClass = MathMax(0, MathMin(2, classIdx));
        example.time = TimeCurrent();
        example.linkedToTrade = linkedToTrade;
        example.predictionId = predictionId;
        example.signalConfidence = signalConfidence;
        ArrayCopy(example.metaInput, metaInput);
        PushTrainingExample(example);
        m_resolvedLabelCount++;
        if(linkedToTrade)
            m_tradeLinkedLabels++;
        m_labeledSinceCheckpoint++;
    }

    void ResolveBarriers()
    {
        datetime closedBarTime = FeatureBarTime();
        if(closedBarTime <= 0 || closedBarTime == m_lastResolvedBarTime)
            return;

        double currentHigh = iHigh(m_symbol, m_timeframe, 1);
        double currentLow = iLow(m_symbol, m_timeframe, 1);

        int resolvedThisPass = 0;

        for(int i = 0; i < m_barrierCount; i++)
        {
            if(m_barrierBuffer[i].resolved)
                continue;

            // Handle HOLD observations (signalClass=0): auto-resolve as neutral label
            if(m_barrierBuffer[i].signalClass == 0)
            {
                m_barrierBuffer[i].label = 0;  // HOLD -> label class 0
                m_barrierBuffer[i].resolved = true;
                AddTrainingExample(m_barrierBuffer[i].featureSnapshot,
                                   m_barrierBuffer[i].featureSize,
                                   0,  // label class 0 (HOLD)
                                   m_barrierBuffer[i].linkedToTrade,
                                   m_barrierBuffer[i].predictionId,
                                   m_barrierBuffer[i].signalConfidence,
                                   m_barrierBuffer[i].metaInput);
                m_conformal.AddScore(1.0 - m_barrierBuffer[i].signalConfidence);
                m_conformal.UpdateACI(false);  // HOLD is not a correct directional prediction
                m_metaLabeler.AddSample(m_barrierBuffer[i].metaInput, 0);  // Not profitable
                resolvedThisPass++;
                continue;
            }

            bool upperHit = (currentHigh >= m_barrierBuffer[i].upperBarrier);
            bool lowerHit = (currentLow <= m_barrierBuffer[i].lowerBarrier);
            bool verticalHit = (TimeCurrent() >= m_barrierBuffer[i].expiryTime);

            int label = -99;
            if(upperHit && m_barrierBuffer[i].signalClass == 1) label = 1;
            else if(lowerHit && m_barrierBuffer[i].signalClass == 1) label = -1;
            else if(upperHit && m_barrierBuffer[i].signalClass == 2) label = -1;
            else if(lowerHit && m_barrierBuffer[i].signalClass == 2) label = 1;
            else if(verticalHit) label = 0;

            if(label == -99)
                continue;

            m_barrierBuffer[i].label = label;
            m_barrierBuffer[i].resolved = true;
            AddTrainingExample(m_barrierBuffer[i].featureSnapshot,
                               m_barrierBuffer[i].featureSize,
                               label + 1,
                               m_barrierBuffer[i].linkedToTrade,
                               m_barrierBuffer[i].predictionId,
                               m_barrierBuffer[i].signalConfidence,
                               m_barrierBuffer[i].metaInput);
            m_conformal.AddScore(1.0 - m_barrierBuffer[i].signalConfidence);
            m_conformal.UpdateACI(label > 0);
            m_metaLabeler.AddSample(m_barrierBuffer[i].metaInput, label > 0 ? 1 : 0);
            resolvedThisPass++;
        }

        m_lastResolvedBarTime = closedBarTime;

        if(resolvedThisPass > 0 && m_checkpointEveryLabeled > 0 && m_labeledSinceCheckpoint >= m_checkpointEveryLabeled)
        {
            TrainNetwork();
        }
    }

    bool CollectObservationInternal(const bool linkedToTrade,
                                    const ENUM_TRADE_SIGNAL forcedSignal,
                                    string &predictionId)
    {
        predictionId = "";
        if(!m_enableOnlineTraining)
            return false;

        datetime now = TimeCurrent();
        if(!linkedToTrade && (now - m_lastObservationTime) < m_sampleIntervalSec)
            return false;

        double normalizedFeatures[];
        double rawFeatures[];
        if(!ExtractFeatures(normalizedFeatures, rawFeatures))
            return false;

        ENUM_TRADE_SIGNAL signal;
        double confidence;
        double metaInput[];
        double probabilities[];
        ComputeSignalContext(normalizedFeatures, rawFeatures, signal, confidence, metaInput, probabilities);
        if(forcedSignal != TRADE_SIGNAL_NONE)
            signal = forcedSignal;

        // PSEUDO-LABEL FIX: When signal is NONE but pseudo-labeling is enabled,
        // use random exploration to bootstrap training (cold-start problem)
        if(signal == TRADE_SIGNAL_NONE && m_enableSelfLabeling && !linkedToTrade)
        {
            // Random exploration: assign BUY/SELL/HOLD based on price momentum
            double close0 = iClose(m_symbol, m_timeframe, 0);
            double close5 = iClose(m_symbol, m_timeframe, 5);
            if(close5 > 0.0)
            {
                double momentum = (close0 - close5) / close5;
                if(momentum > 0.001)      // Upward momentum -> BUY
                    signal = TRADE_SIGNAL_BUY;
                else if(momentum < -0.001) // Downward momentum -> SELL
                    signal = TRADE_SIGNAL_SELL;
                else                       // Flat -> HOLD (label class 0)
                {
                    // Record as HOLD observation (no trade direction needed)
                    predictionId = GeneratePredictionId();
                    if(RecordBarrierEntry(0, 0.0, normalizedFeatures, FEATURE_VECTOR_SIZE, predictionId, false, 0.5, metaInput))
                    {
                        m_totalObservations++;
                        m_lastObservationTime = now;
                        return true;
                    }
                    return false;
                }
            }
            else
            {
                // Fallback: default to HOLD if can't compute momentum
                predictionId = GeneratePredictionId();
                if(RecordBarrierEntry(0, 0.0, normalizedFeatures, FEATURE_VECTOR_SIZE, predictionId, false, 0.5, metaInput))
                {
                    m_totalObservations++;
                    m_lastObservationTime = now;
                    return true;
                }
                return false;
            }
        }
        else if(signal == TRADE_SIGNAL_NONE)
        {
            // Non-pseudo-labeling mode: reject NONE signals as before
            return false;
        }

        int signalClass = (signal == TRADE_SIGNAL_BUY) ? 1 : 2;
        double atr = rawFeatures[4] * iClose(m_symbol, m_timeframe, 1);
        if(atr <= 0.0)
            atr = SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 100.0;

        predictionId = GeneratePredictionId();
        if(!RecordBarrierEntry(signalClass, atr, normalizedFeatures, FEATURE_VECTOR_SIZE, predictionId, linkedToTrade, confidence, metaInput))
            return false;

        m_totalObservations++;
        m_lastObservationTime = now;
        return true;
    }

    bool SaveCheckpointAtomic(const bool forceWrite)
    {
        if(!m_initialized)
            return false;
        if(!forceWrite && m_labeledSinceCheckpoint <= 0)
            return false;

        NNModelStorage_EnsureFolders();
        string primaryFile = NNModelStorage_GetPrimaryPath(m_symbol, m_timeframe, NN_CHECKPOINT_VERSION);
        string backupFile = NNModelStorage_GetBackupPath(m_symbol, m_timeframe, NN_CHECKPOINT_VERSION);
        string tempFile = NNModelStorage_GetTempPath(m_symbol, m_timeframe, NN_CHECKPOINT_VERSION);

        int fh = FileOpen(tempFile, FILE_WRITE | FILE_BIN | FILE_COMMON);
        if(fh == INVALID_HANDLE)
            return false;

        FileWriteInteger(fh, NN_CHECKPOINT_MAGIC);
        FileWriteInteger(fh, NN_CHECKPOINT_VERSION);
        WriteCheckpointString(fh, m_symbol);
        FileWriteInteger(fh, (int)m_timeframe);
        FileWriteLong(fh, (long)TimeCurrent());
        FileWriteInteger(fh, m_enableOnlineTraining ? 1 : 0);
        FileWriteInteger(fh, m_enableSelfLabeling ? 1 : 0);
        FileWriteInteger(fh, m_sampleIntervalSec);
        FileWriteInteger(fh, m_checkpointEveryLabeled);
        FileWriteInteger(fh, m_epoch);
        FileWriteDouble(fh, m_lastLoss);
        FileWriteInteger(fh, m_trainingSteps);
        FileWriteInteger(fh, m_checkpointWrites);
        FileWriteInteger(fh, m_totalObservations);
        FileWriteInteger(fh, m_tradeLinkedLabels);
        FileWriteLong(fh, m_resolvedLabelCount);
        FileWriteLong(fh, m_featureCount);
        FileWriteInteger(fh, m_normalizationReady ? 1 : 0);
        FileWriteLong(fh, m_adamStep);

        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
        {
            FileWriteDouble(fh, m_featureMean[i]);
            FileWriteDouble(fh, m_featureM2[i]);
        }
        for(int i = 0; i < ArraySize(m_adamM); i++)
        {
            FileWriteDouble(fh, m_adamM[i]);
            FileWriteDouble(fh, m_adamV[i]);
        }

        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
            for(int j = 0; j < 32; j++)
                FileWriteDouble(fh, W1[i][j]);
        for(int i = 0; i < 32; i++)
            for(int j = 0; j < 16; j++)
                FileWriteDouble(fh, W2[i][j]);
        for(int i = 0; i < 16; i++)
            for(int j = 0; j < 8; j++)
                FileWriteDouble(fh, W3[i][j]);
        for(int i = 0; i < 8; i++)
            for(int j = 0; j < 3; j++)
                FileWriteDouble(fh, W4[i][j]);
        for(int i = 0; i < 32; i++) FileWriteDouble(fh, B1[i]);
        for(int i = 0; i < 16; i++) FileWriteDouble(fh, B2[i]);
        for(int i = 0; i < 8; i++) FileWriteDouble(fh, B3[i]);
        for(int i = 0; i < 3; i++) FileWriteDouble(fh, B4[i]);

        FileWriteInteger(fh, m_trainCount);
        for(int i = 0; i < m_trainCount; i++)
        {
            int idx = (m_trainHead - m_trainCount + i + NN_MAX_TRAINING_EXAMPLES) % NN_MAX_TRAINING_EXAMPLES;
            FileWriteInteger(fh, m_trainingBuffer[idx].labelClass);
            FileWriteLong(fh, (long)m_trainingBuffer[idx].time);
            FileWriteInteger(fh, m_trainingBuffer[idx].linkedToTrade ? 1 : 0);
            WriteCheckpointString(fh, m_trainingBuffer[idx].predictionId);
            FileWriteDouble(fh, m_trainingBuffer[idx].signalConfidence);
            for(int j = 0; j < FEATURE_VECTOR_SIZE; j++)
                FileWriteDouble(fh, m_trainingBuffer[idx].inputs[j]);
            for(int j = 0; j < ML_INPUT; j++)
                FileWriteDouble(fh, m_trainingBuffer[idx].metaInput[j]);
        }

        FileWriteInteger(fh, m_barrierCount);
        for(int i = 0; i < m_barrierCount; i++)
        {
            FileWriteInteger(fh, m_barrierBuffer[i].signalClass);
            FileWriteDouble(fh, m_barrierBuffer[i].entryPrice);
            FileWriteDouble(fh, m_barrierBuffer[i].upperBarrier);
            FileWriteDouble(fh, m_barrierBuffer[i].lowerBarrier);
            FileWriteLong(fh, (long)m_barrierBuffer[i].expiryTime);
            FileWriteInteger(fh, m_barrierBuffer[i].featureSize);
            FileWriteInteger(fh, m_barrierBuffer[i].label);
            FileWriteInteger(fh, m_barrierBuffer[i].resolved ? 1 : 0);
            WriteCheckpointString(fh, m_barrierBuffer[i].predictionId);
            FileWriteInteger(fh, m_barrierBuffer[i].linkedToTrade ? 1 : 0);
            FileWriteDouble(fh, m_barrierBuffer[i].signalConfidence);
            FileWriteLong(fh, (long)m_barrierBuffer[i].entryBarTime);
            for(int j = 0; j < FEATURE_VECTOR_SIZE; j++)
                FileWriteDouble(fh, m_barrierBuffer[i].featureSnapshot[j]);
            for(int j = 0; j < ML_INPUT; j++)
                FileWriteDouble(fh, m_barrierBuffer[i].metaInput[j]);
        }

        ulong checksum = ComputeCheckpointChecksum();
        FileWriteLong(fh, (long)checksum);

        FileClose(fh);
        if(!NNModelStorage_PromoteTempToPrimary(tempFile, primaryFile, backupFile))
            return false;

        m_checkpointWrites++;
        m_lastCheckpointTimestamp = TimeCurrent();
        m_labeledSinceCheckpoint = 0;
        return true;
    }

    ulong ComputeCheckpointChecksum() const
    {
        ulong hash1 = 0x123456789ABCDEF0;
        ulong hash2 = 0xFEDCBA9876543210;
        
        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
            for(int j = 0; j < 32; j++)
            {
                hash1 ^= (ulong)(W1[i][j] * 1000000.0);
                hash2 ^= (ulong)(i * 31 + j);
                hash1 = hash1 * 6364136223846793005ULL + 1442695040888963407ULL;
            }
        
        for(int i = 0; i < 32; i++)
            for(int j = 0; j < 16; j++)
            {
                hash2 ^= (ulong)(W2[i][j] * 1000000.0);
                hash1 ^= (ulong)(i * 17 + j);
                hash2 = hash2 * 6364136223846793005ULL + 1442695040888963407ULL;
            }
        
        for(int i = 0; i < 16; i++)
            for(int j = 0; j < 8; j++)
            {
                hash1 ^= (ulong)(W3[i][j] * 1000000.0);
                hash2 ^= (ulong)(i * 13 + j);
                hash1 = hash1 * 6364136223846793005ULL + 1442695040888963407ULL;
            }
        
        for(int i = 0; i < 8; i++)
            for(int j = 0; j < 3; j++)
            {
                hash2 ^= (ulong)(W4[i][j] * 1000000.0);
                hash1 ^= (ulong)(i * 7 + j);
                hash2 = hash2 * 6364136223846793005ULL + 1442695040888963407ULL;
            }
        
        return hash1 ^ (hash2 << 1);
    }

    bool ValidateWeights() const
    {
        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
            for(int j = 0; j < 32; j++)
                if(!MathIsValidNumber(W1[i][j]))
                    return false;
        for(int i = 0; i < 32; i++)
            for(int j = 0; j < 16; j++)
                if(!MathIsValidNumber(W2[i][j]))
                    return false;
        for(int i = 0; i < 16; i++)
            for(int j = 0; j < 8; j++)
                if(!MathIsValidNumber(W3[i][j]))
                    return false;
        for(int i = 0; i < 8; i++)
            for(int j = 0; j < 3; j++)
                if(!MathIsValidNumber(W4[i][j]))
                    return false;
        for(int i = 0; i < 32; i++)
            if(!MathIsValidNumber(B1[i]))
                return false;
        for(int i = 0; i < 16; i++)
            if(!MathIsValidNumber(B2[i]))
                return false;
        for(int i = 0; i < 8; i++)
            if(!MathIsValidNumber(B3[i]))
                return false;
        for(int i = 0; i < 3; i++)
            if(!MathIsValidNumber(B4[i]))
                return false;
        return true;
    }

    bool LoadCheckpoint()
    {
        NNModelStorage_EnsureFolders();
        string primaryFile = NNModelStorage_GetPrimaryPath(m_symbol, m_timeframe, NN_CHECKPOINT_VERSION);
        if(!FileIsExist(primaryFile, FILE_COMMON))
            return false;

        int fh = FileOpen(primaryFile, FILE_READ | FILE_BIN | FILE_COMMON);
        if(fh == INVALID_HANDLE)
            return false;

        int magic = FileReadInteger(fh);
        int version = FileReadInteger(fh);
        string symbol;
        if(magic != NN_CHECKPOINT_MAGIC || version != NN_CHECKPOINT_VERSION || !ReadCheckpointString(fh, symbol))
        {
            FileClose(fh);
            return false;
        }
        int timeframe = FileReadInteger(fh);
        if(symbol != m_symbol || timeframe != (int)m_timeframe)
        {
            FileClose(fh);
            return false;
        }

        m_lastCheckpointTimestamp = (datetime)FileReadLong(fh);
        bool persistedOnlineTraining = (FileReadInteger(fh) != 0);
        bool persistedSelfLabeling = (FileReadInteger(fh) != 0);
        m_sampleIntervalSec = FileReadInteger(fh);
        m_checkpointEveryLabeled = FileReadInteger(fh);
        m_epoch = FileReadInteger(fh);
        m_lastLoss = FileReadDouble(fh);
        m_trainingSteps = FileReadInteger(fh);
        m_checkpointWrites = FileReadInteger(fh);
        m_totalObservations = FileReadInteger(fh);
        m_tradeLinkedLabels = FileReadInteger(fh);
        m_resolvedLabelCount = FileReadLong(fh);
        m_featureCount = FileReadLong(fh);
        m_normalizationReady = (FileReadInteger(fh) != 0);
        m_adamStep = FileReadLong(fh);

        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
        {
            m_featureMean[i] = FileReadDouble(fh);
            m_featureM2[i] = FileReadDouble(fh);
        }
        for(int i = 0; i < ArraySize(m_adamM); i++)
        {
            m_adamM[i] = FileReadDouble(fh);
            m_adamV[i] = FileReadDouble(fh);
        }

        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
            for(int j = 0; j < 32; j++)
                W1[i][j] = FileReadDouble(fh);
        for(int i = 0; i < 32; i++)
            for(int j = 0; j < 16; j++)
                W2[i][j] = FileReadDouble(fh);
        for(int i = 0; i < 16; i++)
            for(int j = 0; j < 8; j++)
                W3[i][j] = FileReadDouble(fh);
        for(int i = 0; i < 8; i++)
            for(int j = 0; j < 3; j++)
                W4[i][j] = FileReadDouble(fh);
        for(int i = 0; i < 32; i++) B1[i] = FileReadDouble(fh);
        for(int i = 0; i < 16; i++) B2[i] = FileReadDouble(fh);
        for(int i = 0; i < 8; i++) B3[i] = FileReadDouble(fh);
        for(int i = 0; i < 3; i++) B4[i] = FileReadDouble(fh);

        m_trainHead = 0;
        m_trainCount = MathMin(FileReadInteger(fh), NN_MAX_TRAINING_EXAMPLES);
        for(int i = 0; i < NN_MAX_TRAINING_EXAMPLES; i++)
            m_trainingBuffer[i].Reset();
        for(int i = 0; i < m_trainCount; i++)
        {
            m_trainingBuffer[i].labelClass = FileReadInteger(fh);
            m_trainingBuffer[i].time = (datetime)FileReadLong(fh);
            m_trainingBuffer[i].linkedToTrade = (FileReadInteger(fh) != 0);
            ReadCheckpointString(fh, m_trainingBuffer[i].predictionId);
            m_trainingBuffer[i].signalConfidence = FileReadDouble(fh);
            for(int j = 0; j < FEATURE_VECTOR_SIZE; j++)
                m_trainingBuffer[i].inputs[j] = FileReadDouble(fh);
            for(int j = 0; j < ML_INPUT; j++)
                m_trainingBuffer[i].metaInput[j] = FileReadDouble(fh);
        }
        m_trainHead = m_trainCount % NN_MAX_TRAINING_EXAMPLES;

        m_barrierCount = MathMin(FileReadInteger(fh), NN_MAX_PERSISTED_SAMPLES);
        m_barrierHead = m_barrierCount;
        for(int i = 0; i < NN_MAX_PERSISTED_SAMPLES; i++)
            m_barrierBuffer[i].Reset();
        for(int i = 0; i < m_barrierCount; i++)
        {
            m_barrierBuffer[i].signalClass = FileReadInteger(fh);
            m_barrierBuffer[i].entryPrice = FileReadDouble(fh);
            m_barrierBuffer[i].upperBarrier = FileReadDouble(fh);
            m_barrierBuffer[i].lowerBarrier = FileReadDouble(fh);
            m_barrierBuffer[i].expiryTime = (datetime)FileReadLong(fh);
            m_barrierBuffer[i].featureSize = FileReadInteger(fh);
            m_barrierBuffer[i].label = FileReadInteger(fh);
            m_barrierBuffer[i].resolved = (FileReadInteger(fh) != 0);
            ReadCheckpointString(fh, m_barrierBuffer[i].predictionId);
            m_barrierBuffer[i].linkedToTrade = (FileReadInteger(fh) != 0);
            m_barrierBuffer[i].signalConfidence = FileReadDouble(fh);
            m_barrierBuffer[i].entryBarTime = (datetime)FileReadLong(fh);
            for(int j = 0; j < FEATURE_VECTOR_SIZE; j++)
                m_barrierBuffer[i].featureSnapshot[j] = FileReadDouble(fh);
            for(int j = 0; j < ML_INPUT; j++)
                m_barrierBuffer[i].metaInput[j] = FileReadDouble(fh);
        }

        ulong storedChecksum = (ulong)FileReadLong(fh);
        ulong computedChecksum = ComputeCheckpointChecksum();
        
        FileClose(fh);
        
        if(storedChecksum != computedChecksum)
        {
            m_lastLoadStatus = "REJECTED_CHECKSUM_MISMATCH";
            PrintFormat("[NEURAL-NET] %s Checkpoint checksum mismatch: stored=0x%016llX, computed=0x%016llX", 
                       m_symbol, storedChecksum, computedChecksum);
            return false;
        }
        
        if(!m_enableOnlineTraining)
            m_enableSelfLabeling = false;
        else if(!persistedOnlineTraining)
            m_enableSelfLabeling = false;
        else
            m_enableSelfLabeling = m_enableSelfLabeling && persistedSelfLabeling;
        
        if(!ValidateWeights())
        {
            m_lastLoadStatus = "REJECTED_INVALID_WEIGHTS";
            PrintFormat("[NEURAL-NET] %s Checkpoint validation FAILED: NaN/Inf detected in weights", m_symbol);
            return false;
        }
        
        m_lastLoadStatus = "LOADED";
        return true;
    }

public:
    CNeuralNetworkStrategy()
    {
        m_randomState = 20260419;
        m_initialized = false;
        m_enableOnlineTraining = true;
        m_enableSelfLabeling = true;
        m_sampleIntervalSec = 15;
        m_checkpointEveryLabeled = 10;
        m_labeledSinceCheckpoint = 0;
        m_epoch = 0;
        m_lastLoss = 0.0;
        m_trainingSteps = 0;
        m_checkpointWrites = 0;
        m_temperature = 1.0;  // Default temperature for confidence calibration
        m_totalObservations = 0;
        m_tradeLinkedLabels = 0;
        m_resolvedLabelCount = 0;
        m_barrierHead = 0;
        m_barrierCount = 0;
        m_barrierK = 1.5;
        m_barrierVertBars = 20;
        m_minConfidence = 0.70;
        m_lastObservationTime = 0;
        m_lastSignalLogTime = 0;
        m_lastCheckpointTimestamp = 0;
        m_lastNormalizationBarTime = 0;
        m_lastResolvedBarTime = 0;
        m_lastSelfRecordBarTime = 0;
        m_lastFeatureImportanceLogTime = 0;
        m_cacheBarTime = 0;
        m_hasCachedSignal = false;
        m_cachedSignal = TRADE_SIGNAL_NONE;
        m_cachedConfidence = 0.0;
        m_lastLoadStatus = "COLD_START";
        m_transformerRef = NULL;
        m_ownsTransformerRef = false;
        m_symbol = "";
        m_timeframe = PERIOD_CURRENT;
        m_trainHead = 0;
        m_trainCount = 0;
        ArrayResize(m_featureMean, FEATURE_VECTOR_SIZE);
        ArrayResize(m_featureM2, FEATURE_VECTOR_SIZE);
        ArrayInitialize(m_featureMean, 0.0);
        ArrayInitialize(m_featureM2, 0.0);
        m_featureCount = 0;
        m_normalizationReady = false;
        m_normalizationDecay = 0.001;  // EMA decay factor (small value for slow adaptation)
        for(int i = 0; i < NN_MAX_TRAINING_EXAMPLES; i++)
            m_trainingBuffer[i].Reset();
        for(int i = 0; i < NN_MAX_PERSISTED_SAMPLES; i++)
            m_barrierBuffer[i].Reset();
        InitWeights();
        InitOptimizer();
        m_conformal.Init(0.05);
        m_metaLabeler.Init(500);
        m_regimeTracker.Init();
        m_featureImportance.Init(FEATURE_VECTOR_SIZE, 100);
    }

    virtual ~CNeuralNetworkStrategy()
    {
        if(m_initialized)
            SaveCheckpointAtomic(true);
        if(m_ownsTransformerRef && CheckPointer(m_transformerRef) == POINTER_DYNAMIC)
            delete m_transformerRef;
    }

    bool Initialize(string symbol, ENUM_TIMEFRAMES timeframe)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_initialized = true;
        if(!LoadCheckpoint())
        {
            m_lastLoadStatus = "COLD_START";
            SaveCheckpointAtomic(true);
        }
        PrintFormat("[NEURAL-NET] Initialized | Symbol=%s | TF=%s | Load=%s",
                    m_symbol, EnumToString(m_timeframe), m_lastLoadStatus);
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
    }

    void SetWeightMutationEnabled(const bool enabled)
    {
        // Deprecated: retained for backward compatibility only.
        if(!enabled)
            PrintFormat("[NEURAL-NET] Weight mutation gate deprecated; AdamW training remains governed by resolved label readiness | Symbol=%s", m_symbol);
    }

    void ConfigureOnlineLearning(const bool enablePseudoLabeling,
                                 const int pseudoLabelBarsAhead,
                                 const int sampleIntervalSeconds,
                                 const int checkpointEveryLabeled)
    {
        m_enableSelfLabeling = enablePseudoLabeling;
        m_barrierVertBars = MathMax(5, pseudoLabelBarsAhead > 0 ? pseudoLabelBarsAhead : 20);
        m_sampleIntervalSec = MathMax(1, sampleIntervalSeconds);
        m_checkpointEveryLabeled = MathMax(1, checkpointEveryLabeled);
    }

    void SetConfidenceThreshold(double threshold)
    {
        m_minConfidence = threshold;
    }

    void SetTemperature(const double temperature)
    {
        m_temperature = MathMax(0.1, MathMin(10.0, temperature));
    }

    double GetTemperature() const
    {
        return m_temperature;
    }

    double GetLastUncertainty() const
    {
        return m_conformal.GetLastUncertainty();
    }

    bool IsTraining() const
    {
        return (m_enableOnlineTraining && m_initialized);
    }

    int GetTrainingSteps() const
    {
        return m_trainingSteps;
    }

    int GetCurrentRegime() const
    {
        return (int)m_regimeTracker.GetCurrentRegime();
    }

    string GetLastLoadStatus() const
    {
        return m_lastLoadStatus;
    }

    ENUM_TRADE_SIGNAL GetNeuralSignalCached(double &confidence)
    {
        confidence = 0.0;
        if(!m_initialized)
            return TRADE_SIGNAL_NONE;

        datetime currentBar = CurrentBarTime();
        if(m_hasCachedSignal && currentBar == m_cacheBarTime && currentBar > 0)
        {
            confidence = m_cachedConfidence;
            return m_cachedSignal;
        }

        double normalizedFeatures[];
        double rawFeatures[];
        if(!ExtractFeatures(normalizedFeatures, rawFeatures))
            return TRADE_SIGNAL_NONE;

        ENUM_TRADE_SIGNAL signal;
        double metaInput[];
        double probabilities[];
        ComputeSignalContext(normalizedFeatures, rawFeatures, signal, confidence, metaInput, probabilities);
        m_cachedSignal = signal;
        m_cachedConfidence = confidence;
        m_cacheBarTime = currentBar;
        m_hasCachedSignal = true;

        if(signal != TRADE_SIGNAL_NONE)
        {
            m_featureImportance.Update(normalizedFeatures, FEATURE_VECTOR_SIZE, confidence, *this);
            if(m_lastFeatureImportanceLogTime == 0 || (TimeCurrent() - m_lastFeatureImportanceLogTime) >= 500)
            {
                m_featureImportance.LogTopFeatures(10);
                m_lastFeatureImportanceLogTime = TimeCurrent();
            }
        }

        datetime now = TimeCurrent();
        if(m_lastSignalLogTime == 0 || (now - m_lastSignalLogTime) >= 10)
        {
            PrintFormat("[NEURAL-NET] Signal=%s | conf=%.3f | none=%.3f | buy=%.3f | sell=%.3f | conformal_q=%.3f | alpha=%.3f",
                        TradeSignalToString(signal), confidence,
                        probabilities[0], probabilities[1], probabilities[2],
                        m_conformal.GetQuantile(), m_conformal.GetAlpha());
            m_lastSignalLogTime = now;
        }

        return signal;
    }

    ENUM_TRADE_SIGNAL GetNeuralSignal(double &confidence)
    {
        return GetNeuralSignalCached(confidence);
    }

    double GetConfidenceForFeatures(const double &features[], const int size)
    {
        if(size < FEATURE_VECTOR_SIZE)
            return 0.0;
        double outputs[];
        ForwardPropagate(features, outputs);
        return MathMax(outputs[1], outputs[2]);
    }

    void TickOnlineLearning()
    {
        if(!m_enableOnlineTraining)
            return;

        ResolveBarriers();
        if(!m_enableSelfLabeling)
            return;

        datetime featureBarTime = FeatureBarTime();
        if(featureBarTime > 0 && featureBarTime != m_lastSelfRecordBarTime)
        {
            string ignoredPredictionId = "";
            if(CollectObservationInternal(false, TRADE_SIGNAL_NONE, ignoredPredictionId))
                m_lastSelfRecordBarTime = featureBarTime;
        }
    }

    bool ReservePredictionForSignal(const ENUM_TRADE_SIGNAL signal, string &predictionId, const int maxAgeSec = 600)
    {
        predictionId = "";
        if(!m_enableOnlineTraining)
            return false;
        return CollectObservationInternal(true, signal, predictionId);
    }

    void ReleasePredictionReservation(const string predictionId)
    {
        for(int i = 0; i < m_barrierCount; i++)
        {
            if(m_barrierBuffer[i].predictionId == predictionId && !m_barrierBuffer[i].resolved)
            {
                m_barrierBuffer[i].linkedToTrade = false;
                return;
            }
        }
    }

    bool UpdateTradeResultByPredictionId(const string predictionId, const double profitLoss)
    {
        if(predictionId == "")
            return false;

        for(int i = 0; i < m_barrierCount; i++)
        {
            if(m_barrierBuffer[i].predictionId != predictionId)
                continue;
            m_barrierBuffer[i].linkedToTrade = true;
            if(profitLoss > 0.0)
                m_tradeLinkedLabels++;
            return true;
        }
        return false;
    }

    bool UpdateTradeResult(datetime tradeTime, double profitLoss)
    {
        for(int i = m_barrierCount - 1; i >= 0; i--)
        {
            if(m_barrierBuffer[i].entryBarTime <= tradeTime && !m_barrierBuffer[i].resolved)
            {
                m_barrierBuffer[i].linkedToTrade = true;
                if(profitLoss > 0.0)
                    m_tradeLinkedLabels++;
                return true;
            }
        }
        return false;
    }

    void TrainNetwork()
    {
        if(!m_enableOnlineTraining)
            return;
        if(m_resolvedLabelCount < 10 || m_trainCount < 10)
            return;

        int maxSamples = MathMin(m_trainCount, 256);
        int start = MathMax(0, m_trainCount - maxSamples);
        double epochLoss = 0.0;
        int processed = 0;

        for(int epochIter = 0; epochIter < 2; epochIter++)
        {
            for(int logical = start; logical < m_trainCount; logical++)
            {
                int idx = (m_trainHead - m_trainCount + logical + NN_MAX_TRAINING_EXAMPLES) % NN_MAX_TRAINING_EXAMPLES;
                double outputs[];
                ForwardPropagate(m_trainingBuffer[idx].inputs, outputs);
                epochLoss += CalculateLoss(outputs, m_trainingBuffer[idx].labelClass);
                BackpropagateAndUpdate(m_trainingBuffer[idx].inputs, m_trainingBuffer[idx].labelClass);
                processed++;
            }
            m_epoch++;
        }

        if(processed > 0)
        {
            m_lastLoss = epochLoss / (double)processed;
            m_trainingSteps++;
            PrintFormat("[NEURAL-NET] Train step | epoch=%d | loss=%.6f | samples=%d | lr=%.8f | resolved=%I64d",
                        m_epoch, m_lastLoss, processed, GetCyclicLR(), m_resolvedLabelCount);
            SaveCheckpointAtomic(false);
        }
    }

    int GetTrainingExampleCount()
    {
        return m_trainCount;
    }

    int GetCompletedTradesCount()
    {
        return (int)m_resolvedLabelCount;
    }

    bool SaveNetwork()
    {
        return SaveCheckpointAtomic(true);
    }

    bool LoadNetwork()
    {
        return LoadCheckpoint();
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
        pseudoLabels = (int)m_resolvedLabelCount;
        pendingLabels = m_barrierCount;
        trainingSteps = m_trainingSteps;
        checkpointWrites = m_checkpointWrites;
        epoch = m_epoch;
        lastLoss = m_lastLoss;
    }
};

void CFeatureImportance::Update(const double &features[], const int size, const double baseConfidence, CNeuralNetworkStrategy &nn)
{
    m_evalCounter++;
    if(size <= 0 || (m_evalCounter % m_evalInterval) != 0)
        return;

    double permFeatures[];
    ArrayResize(permFeatures, size);
    ArrayCopy(permFeatures, features, 0, 0, size);

    for(int i = 0; i < MathMin(size, m_featureCount); i++)
    {
        double saved = permFeatures[i];
        permFeatures[i] = 0.0;
        double permConf = nn.GetConfidenceForFeatures(permFeatures, size);
        double drop = baseConfidence - permConf;
        m_importance[i] = 0.95 * m_importance[i] + 0.05 * MathAbs(drop);
        permFeatures[i] = saved;
    }
}

void CFeatureImportance::LogTopFeatures(const int topN)
{
    int idx[];
    ArrayResize(idx, m_featureCount);
    for(int i = 0; i < m_featureCount; i++)
        idx[i] = i;

    for(int i = 0; i < m_featureCount - 1; i++)
    {
        for(int j = 0; j < m_featureCount - 1 - i; j++)
        {
            if(m_importance[idx[j]] < m_importance[idx[j + 1]])
            {
                int t = idx[j];
                idx[j] = idx[j + 1];
                idx[j + 1] = t;
            }
        }
    }

    Print("=== Top Feature Importances ===");
    for(int i = 0; i < MathMin(topN, m_featureCount); i++)
        PrintFormat("  [%02d] Feature %d importance=%.5f", i + 1, idx[i], m_importance[idx[i]]);
}

#endif // __NEURAL_NETWORK_STRATEGY_MQH__
