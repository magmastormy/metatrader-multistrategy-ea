//+------------------------------------------------------------------+
//| EnsembleMetaLearner.mqh                                          |
//| HMM regime-aware transformer ensemble with Kelly reweighting      |
//+------------------------------------------------------------------+
#property strict

#ifndef __ENSEMBLE_META_LEARNER_MQH__
#define __ENSEMBLE_META_LEARNER_MQH__

#include <Arrays/ArrayObj.mqh>
#include "TransformerBrain.mqh"
#include "UniversalTransformerService.mqh"
#include "AIConfig.mqh"

#define HMM_STATES 4
#define HMM_OBS 3
#define ENSEMBLE_ROLLING_WINDOW 60
#define REGIME_NAMES_COUNT 4

class CMarkovRegimeDetector
{
private:
    double m_A[HMM_STATES][HMM_STATES];
    double m_B[HMM_STATES][HMM_OBS];
    double m_pi[HMM_STATES];
    int    m_lastRegime;
    int    m_transitionCount[HMM_STATES][HMM_STATES];
    int    m_stateVisitCount[HMM_STATES];
    bool   m_learningEnabled;
    double m_learningRate;
    int    m_updateCounter;

public:
    void Init()
    {
        double A[HMM_STATES][HMM_STATES] = {
            {0.70, 0.05, 0.20, 0.05},
            {0.05, 0.70, 0.20, 0.05},
            {0.10, 0.10, 0.75, 0.05},
            {0.10, 0.10, 0.20, 0.60}
        };
        double B[HMM_STATES][HMM_OBS] = {
            {0.50, 0.40, 0.10},
            {0.50, 0.40, 0.10},
            {0.65, 0.30, 0.05},
            {0.10, 0.30, 0.60}
        };
        for(int i = 0; i < HMM_STATES; i++)
        {
            for(int j = 0; j < HMM_STATES; j++)
                m_A[i][j] = A[i][j];
            for(int j = 0; j < HMM_OBS; j++)
                m_B[i][j] = B[i][j];
        }
        for(int i = 0; i < HMM_STATES; i++)
            m_pi[i] = 1.0 / (double)HMM_STATES;
        m_lastRegime = 2;
        
        // Initialize transition learning
        for(int i = 0; i < HMM_STATES; i++)
        {
            for(int j = 0; j < HMM_STATES; j++)
                m_transitionCount[i][j] = 0;
            m_stateVisitCount[i] = 0;
        }
        m_learningEnabled = true;
        m_learningRate = 0.01;
        m_updateCounter = 0;
    }
    
    void SetLearningEnabled(const bool enabled)
    {
        m_learningEnabled = enabled;
    }
    
    void SetLearningRate(const double rate)
    {
        m_learningRate = MathMax(0.001, MathMin(0.1, rate));
    }
    
    void UpdateTransitionMatrix()
    {
        if(!m_learningEnabled)
            return;
        
        for(int i = 0; i < HMM_STATES; i++)
        {
            if(m_stateVisitCount[i] == 0)
                continue;
            
            for(int j = 0; j < HMM_STATES; j++)
            {
                double observed = (double)m_transitionCount[i][j] / (double)m_stateVisitCount[i];
                m_A[i][j] = (1.0 - m_learningRate) * m_A[i][j] + m_learningRate * observed;
            }
            
            // Normalize row to ensure valid probability distribution
            double rowSum = 0.0;
            for(int j = 0; j < HMM_STATES; j++)
                rowSum += m_A[i][j];
            
            if(rowSum > 1e-12)
            {
                for(int j = 0; j < HMM_STATES; j++)
                    m_A[i][j] /= rowSum;
            }
        }
    }

    void Update(const double atrRatio, const double trendStrength)
    {
        int obs = 1;
        if(atrRatio < 0.85)
            obs = 0;
        else if(atrRatio >= 1.35 || MathAbs(trendStrength) > 0.005)
            obs = 2;

        double newPi[HMM_STATES];
        double scale = 0.0;
        for(int j = 0; j < HMM_STATES; j++)
        {
            double sum = 0.0;
            for(int i = 0; i < HMM_STATES; i++)
                sum += m_pi[i] * m_A[i][j];
            newPi[j] = sum * m_B[j][obs];
            scale += newPi[j];
        }

        if(scale > 0.0)
        {
            for(int j = 0; j < HMM_STATES; j++)
                m_pi[j] = newPi[j] / scale;
        }
        
        // Track state transitions for learning
        if(m_learningEnabled)
        {
            int detectedRegime = MostLikely();
            m_transitionCount[m_lastRegime][detectedRegime]++;
            m_stateVisitCount[m_lastRegime]++;
            bool regimeChanged = (detectedRegime != m_lastRegime);
            m_lastRegime = detectedRegime;
            
            // Update transition matrix periodically
            m_updateCounter++;
            if(m_updateCounter >= 100)
            {
                UpdateTransitionMatrix();
                m_updateCounter = 0;
            }
            
            if(regimeChanged)
            {
                int newRegime = m_lastRegime;
                PrintFormat("[AI-REGIME] Changed from %d to %d", m_lastRegime, newRegime);
            }
        }
    }

    int MostLikely() const
    {
        int best = 0;
        for(int i = 1; i < HMM_STATES; i++)
        {
            if(m_pi[i] > m_pi[best])
                best = i;
        }
        return best;
    }

    double Prob(const int state) const
    {
        if(state < 0 || state >= HMM_STATES)
            return 0.0;
        return m_pi[state];
    }

    bool Changed()
    {
        int current = MostLikely();
        bool changed = (current != m_lastRegime);
        m_lastRegime = current;
        return changed;
    }

    int LastRegime() const
    {
        return m_lastRegime;
    }

    ENUM_MARKET_REGIME ToEnum() const
    {
        int current = MostLikely();
        if(current == 0)
            return MARKET_REGIME_TRENDING;
        if(current == 1)
            return MARKET_REGIME_RANGING;
        if(current == 2)
            return MARKET_REGIME_VOLATILE;
        return MARKET_REGIME_RANGING;
    }

    void GetProbabilities(double &out[])
    {
        ArrayResize(out, HMM_STATES);
        for(int i = 0; i < HMM_STATES; i++)
            out[i] = m_pi[i];
    }
};

class CRegimeRepository
{
private:
    bool   m_hasSaved[REGIME_NAMES_COUNT];
    string m_names[REGIME_NAMES_COUNT];

    string PathFor(const int regime, const int modelIndex)
    {
        return StringFormat("RegimeCheckpoints\\%s_model_%d.bin", m_names[regime], modelIndex);
    }

public:
    void Init()
    {
        m_names[0] = "TrendUp";
        m_names[1] = "TrendDown";
        m_names[2] = "Ranging";
        m_names[3] = "Volatile";
        for(int i = 0; i < REGIME_NAMES_COUNT; i++)
            m_hasSaved[i] = false;
    }

    void Deinit() {}

    void OnRegimeChange(const int oldR, const int newR, CArrayObj &models)
    {
        if(oldR >= 0 && oldR < REGIME_NAMES_COUNT)
        {
            bool savedAny = false;
            for(int i = 0; i < models.Total(); i++)
            {
                CTransformerBrain* model = (CTransformerBrain*)models.At(i);
                if(model != NULL && model.SaveHeadState(PathFor(oldR, i)))
                    savedAny = true;
            }
            if(savedAny)
                m_hasSaved[oldR] = true;
        }

        if(newR >= 0 && newR < REGIME_NAMES_COUNT && m_hasSaved[newR])
        {
            for(int i = 0; i < models.Total(); i++)
            {
                CTransformerBrain* model = (CTransformerBrain*)models.At(i);
                if(model != NULL)
                    model.LoadHeadState(PathFor(newR, i));
            }
        }
    }
};

class CEnsembleMetaLearner
{
private:
    CArrayObj            m_models;
    bool                 m_usesSharedTransformer;
    string               m_symbol;
    double               m_lastConfidence;
    double               m_atrShort;
    double               m_atrLong;
    double               m_trendStrength;
    double               m_momentum;
    datetime             m_lastRegimeUpdate;
    ENUM_MARKET_REGIME   m_lastDetectedRegime;
    CMarkovRegimeDetector m_hmm;
    CRegimeRepository     m_regimeRepo;
    double               m_modelWeights[];
    double               m_modelPerformanceHistory[];
    double               m_modelRecentAccuracy[];
    double               m_modelWinRate[];
    double               m_modelAvgWin[];
    double               m_modelAvgLoss[];
    int                  m_modelRollHead[];
    int                  m_modelRollCount[];
    double               m_modelRollResults[][ENSEMBLE_ROLLING_WINDOW];
    int                  m_lastModelSignal[];
    double               m_lastModelConfidence[];
    int                  m_resolvedTradeCount;
    double               m_minConfidence;

    // Per-model per-regime performance tracking for adaptive regime multipliers
    #define REGIME_PERF_WINDOW 30
    #define REGIME_PERF_MODELS 8
    #define REGIME_PERF_REGS   4
    double m_regimePerfBuf[REGIME_PERF_MODELS * REGIME_PERF_REGS * REGIME_PERF_WINDOW];
    int    m_regimePerfHead[REGIME_PERF_MODELS];
    int    m_regimePerfCount[REGIME_PERF_MODELS * REGIME_PERF_REGS];

    double ClampValue(const double value, const double minValue, const double maxValue)
    {
        return MathMax(minValue, MathMin(maxValue, value));
    }

    void EnsureModelArrays()
    {
        int total = m_models.Total();
        int oldSize = ArraySize(m_modelWeights);
        ArrayResize(m_modelWeights, total);
        ArrayResize(m_modelPerformanceHistory, total);
        ArrayResize(m_modelRecentAccuracy, total);
        ArrayResize(m_modelWinRate, total);
        ArrayResize(m_modelAvgWin, total);
        ArrayResize(m_modelAvgLoss, total);
        ArrayResize(m_modelRollHead, total);
        ArrayResize(m_modelRollCount, total);
        ArrayResize(m_modelRollResults, total);
        ArrayResize(m_lastModelSignal, total);
        ArrayResize(m_lastModelConfidence, total);

        // Per-regime performance tracking
        for(int i = oldSize; i < total && i < REGIME_PERF_MODELS; i++)
        {
            m_regimePerfHead[i] = 0;
            for(int r = 0; r < REGIME_PERF_REGS; r++)
                m_regimePerfCount[i * REGIME_PERF_REGS + r] = 0;
        }
        ArrayInitialize(m_regimePerfBuf, 0.0);

        for(int i = 0; i < total; i++)
        {
            if(i >= ArraySize(m_modelPerformanceHistory) || m_modelPerformanceHistory[i] == 0.0)
                m_modelPerformanceHistory[i] = 0.5;
            if(m_modelRecentAccuracy[i] <= 0.0)
                m_modelRecentAccuracy[i] = 0.5;
            if(m_modelWinRate[i] <= 0.0)
                m_modelWinRate[i] = 0.5;
            if(m_modelAvgWin[i] <= 0.0)
                m_modelAvgWin[i] = 1.0;
            if(m_modelAvgLoss[i] <= 0.0)
                m_modelAvgLoss[i] = 1.0;
            if(m_modelWeights[i] <= 0.0)
                m_modelWeights[i] = (total > 0) ? (1.0 / (double)total) : 0.0;
            for(int j = 0; j < ENSEMBLE_ROLLING_WINDOW; j++)
                m_modelRollResults[i][j] = 0.0;
        }
    }

    double CalculateATR(const double &data[], const int period)
    {
        if(ArraySize(data) < period + 2)
            return 0.0;

        double sum = 0.0;
        for(int i = 1; i <= period; i++)
        {
            double current = data[i - 1];
            double previous = data[i];
            sum += MathAbs(current - previous);
        }
        return sum / (double)period;
    }

    double CalculateTrendStrength(const double &data[])
    {
        if(ArraySize(data) < 20)
            return 0.0;

        int period = MathMin(20, ArraySize(data) - 1);
        double sumX = 0.0;
        double sumY = 0.0;
        double sumXY = 0.0;
        double sumX2 = 0.0;
        for(int i = 0; i < period; i++)
        {
            sumX += i;
            sumY += data[i];
            sumXY += (double)i * data[i];
            sumX2 += (double)i * (double)i;
        }
        double denom = (period * sumX2) - (sumX * sumX);
        if(MathAbs(denom) <= 1e-9)
            return 0.0;
        double slope = ((period * sumXY) - (sumX * sumY)) / denom;
        double avgPrice = sumY / (double)period;
        return (avgPrice > 1e-9) ? (slope / avgPrice) : 0.0;
    }

    double CalculateMomentum(const double &data[], const int period)
    {
        if(ArraySize(data) < period + 1 || data[period] == 0.0)
            return 0.0;
        return (data[0] - data[period]) / data[period];
    }

    void RecomputeRollingStats(const int modelIndex)
    {
        if(modelIndex < 0 || modelIndex >= ArraySize(m_modelRollResults))
            return;

        int count = m_modelRollCount[modelIndex];
        if(count <= 0)
        {
            m_modelWinRate[modelIndex] = 0.5;
            m_modelAvgWin[modelIndex] = 1.0;
            m_modelAvgLoss[modelIndex] = 1.0;
            return;
        }

        int wins = 0;
        double sumWin = 0.0;
        double sumLoss = 0.0;
        int lossCount = 0;

        for(int i = 0; i < count; i++)
        {
            double value = m_modelRollResults[modelIndex][i];
            if(value > 0.0)
            {
                wins++;
                sumWin += value;
            }
            else if(value < 0.0)
            {
                sumLoss += MathAbs(value);
                lossCount++;
            }
        }

        m_modelWinRate[modelIndex] = (double)wins / (double)count;
        m_modelAvgWin[modelIndex] = (wins > 0) ? (sumWin / (double)wins) : 1.0;
        m_modelAvgLoss[modelIndex] = (lossCount > 0) ? (sumLoss / (double)lossCount) : 1.0;
    }

public:
    CEnsembleMetaLearner()
    {
        m_models.FreeMode(true);
        m_usesSharedTransformer = true;
        m_symbol = "";
        m_lastConfidence = 0.0;
        m_atrShort = 0.0;
        m_atrLong = 0.0;
        m_trendStrength = 0.0;
        m_momentum = 0.0;
        m_lastRegimeUpdate = 0;
        m_lastDetectedRegime = MARKET_REGIME_RANGING;
        m_resolvedTradeCount = 0;
        m_minConfidence = AI_MIN_CONFIDENCE;
        m_hmm.Init();
        m_regimeRepo.Init();
    }

    virtual ~CEnsembleMetaLearner()
    {
        m_models.Clear();
    }

    bool AddModel(CTransformerBrain* model, const double initialWeight = 1.0)
    {
        if(model == NULL)
            return false;
        if(!m_models.Add(model))
            return false;

        EnsureModelArrays();
        int index = m_models.Total() - 1;
        m_modelWeights[index] = initialWeight;
        m_modelPerformanceHistory[index] = 0.5;
        m_modelRecentAccuracy[index] = 0.5;
        m_modelWinRate[index] = 0.5;
        m_modelAvgWin[index] = 1.0;
        m_modelAvgLoss[index] = 1.0;
        m_modelRollHead[index] = 0;
        m_modelRollCount[index] = 0;
        m_lastModelSignal[index] = 0;
        m_lastModelConfidence[index] = 0.0;
        return true;
    }

    bool RemoveModel(const int index)
    {
        if(index < 0 || index >= m_models.Total())
            return false;
        if(!m_models.Delete(index))
            return false;

        EnsureModelArrays();
        return true;
    }

    void UpdateKellyWeights()
    {
        int total = m_models.Total();
        if(total <= 0)
            return;

        double totalPos = 0.0;
        double kf[];
        ArrayResize(kf, total);
        for(int i = 0; i < total; i++)
        {
            double p = ClampValue(m_modelWinRate[i], 0.01, 0.99);
            double b = (m_modelAvgLoss[i] > 1e-9) ? (m_modelAvgWin[i] / m_modelAvgLoss[i]) : 1.0;
            double f = (p * (b + 1.0) - 1.0) / (b + 1e-9);
            kf[i] = MathMax(0.0, f) * 0.5;
            kf[i] = MathMax(0.01, MathMin(2.0, kf[i]));
            totalPos += kf[i];
        }

        for(int i = 0; i < total; i++)
            m_modelWeights[i] = (totalPos > 0.0) ? (kf[i] / totalPos) : (1.0 / (double)total);
    }

    bool ProcessMarketData(const double &marketData[], double &ensembleBuySignal, double &ensembleSellSignal, double &confidence)
    {
        ensembleBuySignal = 0.0;
        ensembleSellSignal = 0.0;
        confidence = 0.0;

        if(m_models.Total() <= 0)
            return false;

        EnsureModelArrays();
        ENUM_MARKET_REGIME activeRegime = DetectMarketRegime(marketData);
        UpdateModelWeights(activeRegime);

        double totalWeight = 0.0;
        double noneWeight = 0.0;
        for(int i = 0; i < m_models.Total(); i++)
        {
            CTransformerBrain* model = (CTransformerBrain*)m_models.At(i);
            if(model == NULL)
                continue;

            int dModel = model.GetModelDimension();
            int maxSeqLen = model.GetMaxSequenceLength();
            if(dModel <= 0)
                continue;

            int availableSeqLen = ArraySize(marketData) / dModel;
            int actualSeqLen = MathMin(availableSeqLen, maxSeqLen);
            if(actualSeqLen <= 0)
                continue;

            double modelInput[];
            ArrayResize(modelInput, actualSeqLen * dModel);
            int startOffset = MathMax(0, ArraySize(marketData) - (actualSeqLen * dModel));
            ArrayCopy(modelInput, marketData, 0, startOffset, actualSeqLen * dModel);

            double predictions[];
            if(!model.GetPredictions(modelInput, actualSeqLen, predictions) || ArraySize(predictions) != 3)
                continue;

            double modelWeight = m_modelWeights[i];
            totalWeight += modelWeight;
            noneWeight += predictions[0] * modelWeight;
            ensembleBuySignal += predictions[1] * modelWeight;
            ensembleSellSignal += predictions[2] * modelWeight;

            int signal = 0;
            if(predictions[1] > predictions[2] && predictions[1] > predictions[0])
                signal = 1;
            else if(predictions[2] > predictions[1] && predictions[2] > predictions[0])
                signal = -1;
            m_lastModelSignal[i] = signal;
            m_lastModelConfidence[i] = MathMax(predictions[1], predictions[2]);
        }

        if(totalWeight <= 0.0)
            return false;

        ensembleBuySignal /= totalWeight;
        ensembleSellSignal /= totalWeight;
        double ensembleNone = noneWeight / totalWeight;
        confidence = MathMax(0.0, MathMin(1.0, MathMax(MathMax(ensembleBuySignal, ensembleSellSignal), 1.0 - ensembleNone)));

        if(confidence < m_minConfidence)
        {
            ensembleBuySignal = 0.0;
            ensembleSellSignal = 0.0;
            confidence = 0.0;
            return false;
        }

        m_lastConfidence = confidence;
        return true;
    }

    bool TrainEnsemble(const double &marketData[], const int seqLen, const int targetClass)
    {
        bool anySuccess = false;
        for(int i = 0; i < m_models.Total(); i++)
        {
            CTransformerBrain* model = (CTransformerBrain*)m_models.At(i);
            double loss = 0.0;
            if(model != NULL && TrainModel(model, marketData, seqLen, targetClass, loss))
                anySuccess = true;
        }
        UpdateModelWeights(m_lastDetectedRegime);
        return anySuccess;
    }

    void UpdateModelWeights(const ENUM_MARKET_REGIME regime)
    {
        EnsureModelArrays();
        int total = m_models.Total();
        if(total <= 0)
            return;

        double sum = 0.0;
        for(int i = 0; i < total; i++)
        {
            double weight = CalculateModelWeight(i, regime);
            m_modelWeights[i] = MathMax(0.01, weight);
            sum += m_modelWeights[i];
        }
        if(sum <= 0.0)
            sum = 1.0;
        for(int i = 0; i < total; i++)
            m_modelWeights[i] /= sum;
    }

    void UpdateModelPerformance(const int modelIndex, const double result)
    {
        if(modelIndex < 0 || modelIndex >= m_models.Total())
            return;

        double emaAlpha = 0.10;
        double win = (result > 0.0) ? 1.0 : 0.0;
        m_modelRecentAccuracy[modelIndex] =
            (emaAlpha * win) + ((1.0 - emaAlpha) * m_modelRecentAccuracy[modelIndex]);
        m_modelPerformanceHistory[modelIndex] =
            (0.15 * ClampValue(0.5 + result, 0.0, 1.0)) + (0.85 * m_modelPerformanceHistory[modelIndex]);

        int slot = m_modelRollHead[modelIndex] % ENSEMBLE_ROLLING_WINDOW;
        m_modelRollResults[modelIndex][slot] = result;
        m_modelRollHead[modelIndex]++;
        if(m_modelRollCount[modelIndex] < ENSEMBLE_ROLLING_WINDOW)
            m_modelRollCount[modelIndex]++;
        RecomputeRollingStats(modelIndex);

        // Track per-regime performance
        int regime = (int)m_lastDetectedRegime;
        if(regime >= 0 && regime < REGIME_PERF_REGS && modelIndex < REGIME_PERF_MODELS)
        {
            int base = modelIndex * REGIME_PERF_REGS * REGIME_PERF_WINDOW + regime * REGIME_PERF_WINDOW;
            int rSlot = m_regimePerfHead[modelIndex] % REGIME_PERF_WINDOW;
            m_regimePerfBuf[base + rSlot] = result;
            m_regimePerfHead[modelIndex]++;
            int cntIdx = modelIndex * REGIME_PERF_REGS + regime;
            if(m_regimePerfCount[cntIdx] < REGIME_PERF_WINDOW)
                m_regimePerfCount[cntIdx]++;
        }
    }

    // Compute adaptive regime multiplier from per-regime performance history
    double GetAdaptiveRegimeMultiplier(const int modelIndex, const ENUM_MARKET_REGIME regime) const
    {
        int regimeIdx = (int)regime;
        if(modelIndex < 0 || modelIndex >= m_models.Total() || modelIndex >= REGIME_PERF_MODELS ||
           regimeIdx < 0 || regimeIdx >= REGIME_PERF_REGS)
            return 1.0;

        int cntIdx = modelIndex * REGIME_PERF_REGS + regimeIdx;
        int count = m_regimePerfCount[cntIdx];
        if(count < 5)
            return 1.0;  // Not enough data — neutral

        // Compute regime-specific win rate from performance history
        int wins = 0;
        double sumResult = 0.0;
        int base = modelIndex * REGIME_PERF_REGS * REGIME_PERF_WINDOW + regimeIdx * REGIME_PERF_WINDOW;
        for(int i = 0; i < count; i++)
        {
            double val = m_regimePerfBuf[base + i];
            sumResult += val;
            if(val > 0.0)
                wins++;
        }
        double regimeWinRate = (double)wins / (double)count;
        double regimeExpectancy = sumResult / (double)count;

        // Map performance to multiplier: bad (0.3) → 0.7, neutral (0.5) → 1.0, good (0.7) → 1.3
        // Using expectancy as the primary driver (more meaningful than winrate alone)
        double multiplier = 1.0 + (regimeExpectancy * 2.0);
        multiplier = MathMax(0.5, MathMin(2.0, multiplier));

        return multiplier;
    }

    double CalculateModelWeight(const int modelIndex, const ENUM_MARKET_REGIME regime)
    {
        if(modelIndex < 0 || modelIndex >= m_models.Total())
            return 0.0;

        double performance = m_modelPerformanceHistory[modelIndex];
        double accuracy = m_modelRecentAccuracy[modelIndex];
        double winRate = m_modelWinRate[modelIndex];

        // Adaptive regime multiplier learned from per-regime performance
        double regimeMultiplier = GetAdaptiveRegimeMultiplier(modelIndex, regime);

        double momentumBoost = 1.0 + MathMin(0.25, MathAbs(m_momentum) * 0.5);
        return MathMax(0.05, (performance * 0.40 + accuracy * 0.30 + winRate * 0.30) * regimeMultiplier * momentumBoost);
    }

    double EvaluateModelPerformance(CTransformerBrain* model, const double &testData[])
    {
        if(model == NULL)
            return 0.0;
        double predictions[];
        if(!model.GetPredictions(testData, predictions) || ArraySize(predictions) != 3)
            return 0.0;
        return MathMax(predictions[1], predictions[2]);
    }

    int GetActiveModelCount() const
    {
        return m_models.Total();
    }

    void DeactivateUnderperformingModels(const double threshold = 0.3)
    {
        for(int i = 0; i < ArraySize(m_modelWeights); i++)
        {
            if(m_modelRecentAccuracy[i] < threshold)
                m_modelWeights[i] = MathMax(0.01, m_modelWeights[i] * 0.5);
        }
    }

    bool TrainModel(CTransformerBrain* model, const double &data[], const int seqLen, const int targetClass, double &loss)
    {
        if(model == NULL)
            return false;
        return model.TrainStep(data, targetClass, loss);
    }

    ENUM_MARKET_REGIME DetectMarketRegimeLegacy(const double &marketData[])
    {
        if(ArraySize(marketData) < 50)
            return MARKET_REGIME_RANGING;

        bool stale = (m_lastRegimeUpdate > 0 && (TimeCurrent() - m_lastRegimeUpdate) > 300);
        if(stale || m_lastRegimeUpdate == 0)
            UpdateRegimeState(marketData);

        double atrRatio = (m_atrLong > 1e-9) ? (m_atrShort / (m_atrLong + 1e-9)) : 1.0;
        if(atrRatio > 1.5)
            return MARKET_REGIME_VOLATILE;
        if(MathAbs(m_trendStrength) > 0.003)
            return MARKET_REGIME_TRENDING;
        return MARKET_REGIME_RANGING;
    }

    ENUM_MARKET_REGIME DetectMarketRegime(const double &marketData[])
    {
        UpdateRegimeState(marketData);
        return m_hmm.ToEnum();
    }

    void UpdateRegimeState(const double &marketData[])
    {
        if(ArraySize(marketData) < 60)
            return;

        m_atrShort = CalculateATR(marketData, 14);
        m_atrLong = CalculateATR(marketData, 50);
        m_trendStrength = CalculateTrendStrength(marketData);
        m_momentum = CalculateMomentum(marketData, 14);
        m_lastRegimeUpdate = TimeCurrent();

        double atrRatio = (m_atrLong > 1e-9) ? (m_atrShort / (m_atrLong + 1e-9)) : 1.0;
        int oldRegime = m_hmm.LastRegime();
        int regimeBeforeUpdate = oldRegime;
        m_hmm.Update(atrRatio, m_trendStrength);
        int newRegime = m_hmm.LastRegime();
        if(newRegime != regimeBeforeUpdate)
        {
            m_regimeRepo.OnRegimeChange(oldRegime, newRegime, m_models);

            for(int i = 0; i < m_models.Total(); i++)
            {
                CTransformerBrain* model = (CTransformerBrain*)m_models.At(i);
                if(model == NULL)
                    continue;

                double fisherApprox[];
                model.GetRecentFisherApprox(fisherApprox);
                model.AnchorEWC(fisherApprox);
            }
        }

        m_lastDetectedRegime = m_hmm.ToEnum();
    }

    void SetSymbol(const string &symbol)
    {
        m_symbol = symbol;
    }

    void SetUseSharedTransformer(const bool useShared)
    {
        m_usesSharedTransformer = useShared;
    }

    bool Initialize(const string &symbol, const bool useSharedTransformer = true)
    {
        m_symbol = symbol;
        m_usesSharedTransformer = useSharedTransformer;
        if(m_usesSharedTransformer)
            return CreateInterpretationModels();
        return true;
    }

    bool UpdateEnsemblePerformance(const double tradeResult)
    {
        EnsureModelArrays();
        if(m_models.Total() <= 0)
            return false;

        double direction = 0.0;
        if(tradeResult > 0.0)
            direction = 1.0;
        else if(tradeResult < 0.0)
            direction = -1.0;

        for(int i = 0; i < m_models.Total(); i++)
        {
            double signedResult = 0.0;
            if(direction != 0.0 && m_lastModelSignal[i] != 0)
            {
                signedResult = ((double)m_lastModelSignal[i] == direction) ?
                               MathAbs(tradeResult) : -MathAbs(tradeResult);
            }
            UpdateModelPerformance(i, signedResult);
        }

        m_resolvedTradeCount++;
        if((m_resolvedTradeCount % AI_KELLY_UPDATE_INTERVAL) == 0)
            UpdateKellyWeights();

        if(m_usesSharedTransformer && m_symbol != "")
            g_universalTransformerService.UpdateSymbolPerformance(m_symbol, tradeResult > 0.0 ? 1.0 : 0.0);
        return true;
    }

    void GetEnsembleStatus(string &status)
    {
        status = StringFormat("[ENSEMBLE] models=%d | conf=%.3f | regime=%s | symbol=%s",
                              m_models.Total(),
                              m_lastConfidence,
                              EnumToString(m_lastDetectedRegime),
                              m_symbol);
    }

    bool ProcessWithSharedTransformer(const double &marketData[], double &ensembleBuySignal, double &ensembleSellSignal, double &confidence)
    {
        return ProcessMarketData(marketData, ensembleBuySignal, ensembleSellSignal, confidence);
    }

    CTransformerBrain* CreateShortTermModel()
    {
        return new CTransformerBrain(32, 4, 2, 96, 20, 0.0008);
    }

    CTransformerBrain* CreateLongTermModel()
    {
        return new CTransformerBrain(32, 4, 2, 96, 60, 0.0005);
    }

    CTransformerBrain* CreateMediumTermModel()
    {
        return new CTransformerBrain(32, 4, 2, 96, 40, 0.0007);
    }

    CTransformerBrain* CreateVolatilityFocusedModel()
    {
        return new CTransformerBrain(32, 8, 2, 128, 30, 0.0009);
    }

    bool CreateInterpretationModels()
    {
        m_models.Clear();
        ArrayResize(m_modelWeights, 0);
        ArrayResize(m_modelPerformanceHistory, 0);
        ArrayResize(m_modelRecentAccuracy, 0);
        ArrayResize(m_modelWinRate, 0);
        ArrayResize(m_modelAvgWin, 0);
        ArrayResize(m_modelAvgLoss, 0);
        ArrayResize(m_modelRollHead, 0);
        ArrayResize(m_modelRollCount, 0);
        ArrayResize(m_modelRollResults, 0);
        ArrayResize(m_lastModelSignal, 0);
        ArrayResize(m_lastModelConfidence, 0);

        bool ok = true;
        ok &= AddModel(CreateShortTermModel(), 0.25);
        ok &= AddModel(CreateMediumTermModel(), 0.25);
        ok &= AddModel(CreateLongTermModel(), 0.25);
        ok &= AddModel(CreateVolatilityFocusedModel(), 0.25);
        UpdateKellyWeights();
        return ok;
    }

    double GetConfidence() const
    {
        return m_lastConfidence;
    }

    void GetRegimeProbabilities(double &out[])
    {
        m_hmm.GetProbabilities(out);
    }
    
    // Stub implementations for adapter compatibility
    double GetUncertainty() const
    {
        return 0.5;  // Default uncertainty
    }
    
    bool IsLearningEnabled() const
    {
        return true;  // Always enabled by default
    }
    
    int GetUpdateCount() const
    {
        return 0;  // Not tracked in ensemble
    }
    
    int GetCurrentRegime() const
    {
        return (int)m_lastDetectedRegime;
    }
};

#endif // __ENSEMBLE_META_LEARNER_MQH__
