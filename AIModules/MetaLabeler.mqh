//+------------------------------------------------------------------+
//| MetaLabeler.mqh                                                  |
//| Secondary profitability filter for AI-originated trade signals   |
//+------------------------------------------------------------------+
#property strict

#ifndef META_LABELER_MQH
#define META_LABELER_MQH

#include "AIConfig.mqh"

#define ML_INPUT  AI_MLP_INPUT
#define ML_H1     AI_MLP_HIDDEN
#define ML_OUT    AI_MLP_OUTPUT

class CMetaLabeler
{
private:
    double m_w1[ML_INPUT][ML_H1];
    double m_b1[ML_H1];
    double m_w2[ML_H1][ML_OUT];
    double m_b2[ML_OUT];
    double m_m1[ML_INPUT][ML_H1];
    double m_v1[ML_INPUT][ML_H1];
    double m_m2[ML_H1][ML_OUT];
    double m_v2[ML_H1][ML_OUT];
    double m_mb1[ML_H1];
    double m_vb1[ML_H1];
    double m_mb2[ML_OUT];
    double m_vb2[ML_OUT];
    long   m_step;
    double m_bufX[][ML_INPUT];
    int    m_bufY[];
    int    m_bufHead;
    int    m_bufCount;
    int    m_bufMax;
    
    // Early stopping parameters
    double m_lossHistory[];
    int    m_lossHead;
    int    m_lossCount;
    int    m_earlyStoppingPatience;
    double m_earlyStoppingThreshold;
    int    m_consecutiveNoImprovement;
    
    // Training cooldown to prevent overfitting
    int    m_samplesSinceLastTrain;
    int    m_trainCooldown;

    // Recent model performance tracking for enriched meta-features
    double m_recentWinRate;
    double m_recentAvgConfidence;
    int    m_recentCorrect;
    int    m_recentTotal;
    int    m_perfWindowHead;

    double Sigmoid(const double value) const
    {
        if(value >= 0.0)
        {
            double z = MathExp(-value);
            return 1.0 / (1.0 + z);
        }
        double z = MathExp(value);
        return z / (1.0 + z);
    }

    double RandNormal()
    {
        double u1 = (MathRand() + 1.0) / 32768.0;
        double u2 = (MathRand() + 1.0) / 32768.0;
        return MathSqrt(-2.0 * MathLog(u1)) * MathCos(2.0 * M_PI * u2);
    }

    void AdamScalarUpdate(double &param,
                          double &m,
                          double &v,
                          const double grad,
                          const double lr,
                          const double beta1,
                          const double beta2,
                          const double eps,
                          const double wd)
    {
        m = beta1 * m + (1.0 - beta1) * grad;
        v = beta2 * v + (1.0 - beta2) * grad * grad;
        double mHat = m / (1.0 - MathPow(beta1, (double)m_step));
        double vHat = v / (1.0 - MathPow(beta2, (double)m_step));
        param -= lr * ((mHat / (MathSqrt(vHat) + eps)) + (wd * param));
    }

    void ClipGradients(double &gradW1[][ML_H1], double &gradB1[], 
                      double &gradW2[][ML_OUT], double &gradB2[],
                      const double maxNorm = 1.0) const
    {
        double norm = 0.0;
        
        for(int i = 0; i < ML_INPUT; i++)
            for(int j = 0; j < ML_H1; j++)
                norm += gradW1[i][j] * gradW1[i][j];
        for(int j = 0; j < ML_H1; j++)
            norm += gradB1[j] * gradB1[j];
        for(int i = 0; i < ML_H1; i++)
            for(int j = 0; j < ML_OUT; j++)
                norm += gradW2[i][j] * gradW2[i][j];
        for(int j = 0; j < ML_OUT; j++)
            norm += gradB2[j] * gradB2[j];
        
        norm = MathSqrt(norm);
        if(norm > maxNorm && norm > 1e-12)
        {
            double scale = maxNorm / norm;
            for(int i = 0; i < ML_INPUT; i++)
                for(int j = 0; j < ML_H1; j++)
                    gradW1[i][j] *= scale;
            for(int j = 0; j < ML_H1; j++)
                gradB1[j] *= scale;
            for(int i = 0; i < ML_H1; i++)
                for(int j = 0; j < ML_OUT; j++)
                    gradW2[i][j] *= scale;
            for(int j = 0; j < ML_OUT; j++)
                gradB2[j] *= scale;
        }
    }

    void TrainStep(const int steps, const int batch)
    {
        double lr = 1e-3;
        double beta1 = 0.9;
        double beta2 = 0.999;
        double eps = 1e-8;
        double wd = 1e-4;
        double clipNorm = 1.0;

        double gradW1[ML_INPUT][ML_H1];
        double gradB1[ML_H1];
        double gradW2[ML_H1][ML_OUT];
        double gradB2[ML_OUT];
        double batchTotalLoss = 0.0;
        int lossCount = 0;

        for(int iter = 0; iter < steps; iter++)
        {
            for(int i = 0; i < ML_INPUT; i++)
                for(int j = 0; j < ML_H1; j++)
                    gradW1[i][j] = 0.0;
            ArrayInitialize(gradB1, 0.0);
            for(int i = 0; i < ML_H1; i++)
                for(int j = 0; j < ML_OUT; j++)
                    gradW2[i][j] = 0.0;
            ArrayInitialize(gradB2, 0.0);

            int effectiveBatch = MathMax(1, MathMin(batch, m_bufCount));
            for(int sampleIdx = 0; sampleIdx < effectiveBatch; sampleIdx++)
            {
                int idx = MathRand() % m_bufCount;
                double hidden[ML_H1];
                double preHidden[ML_H1];
                for(int j = 0; j < ML_H1; j++)
                {
                    double sum = m_b1[j];
                    for(int i = 0; i < ML_INPUT; i++)
                        sum += m_bufX[idx][i] * m_w1[i][j];
                    preHidden[j] = sum;
                    hidden[j] = MathMax(0.0, sum);
                }

                double logits[ML_OUT];
                for(int j = 0; j < ML_OUT; j++)
                {
                    double sum = m_b2[j];
                    for(int i = 0; i < ML_H1; i++)
                        sum += hidden[i] * m_w2[i][j];
                    logits[j] = sum;
                }

                double pProfit = Sigmoid(logits[1] - logits[0]);
                double target = (m_bufY[idx] > 0) ? 1.0 : 0.0;
                double dProfit = pProfit - target;
                
                // Calculate binary cross-entropy loss
                double logEps = 1e-15;
                double loss = -target * MathLog(MathMax(pProfit, logEps)) - (1.0 - target) * MathLog(MathMax(1.0 - pProfit, logEps));
                batchTotalLoss += loss;
                lossCount++;
                double dOut[ML_OUT];
                dOut[1] = dProfit;
                dOut[0] = -dProfit;

                for(int i = 0; i < ML_H1; i++)
                {
                    for(int j = 0; j < ML_OUT; j++)
                        gradW2[i][j] += dOut[j] * hidden[i];
                }
                for(int j = 0; j < ML_OUT; j++)
                    gradB2[j] += dOut[j];

                double dHidden[ML_H1];
                for(int i = 0; i < ML_H1; i++)
                {
                    double sum = 0.0;
                    for(int j = 0; j < ML_OUT; j++)
                        sum += dOut[j] * m_w2[i][j];
                    dHidden[i] = (preHidden[i] > 0.0) ? sum : 0.0;
                }

                for(int i = 0; i < ML_INPUT; i++)
                {
                    for(int j = 0; j < ML_H1; j++)
                        gradW1[i][j] += dHidden[j] * m_bufX[idx][i];
                }
                for(int j = 0; j < ML_H1; j++)
                    gradB1[j] += dHidden[j];
            }

            m_step++;
            
            // Apply gradient clipping to prevent exploding gradients
            ClipGradients(gradW1, gradB1, gradW2, gradB2, clipNorm);
            
            double invBatch = 1.0 / (double)effectiveBatch;
            for(int i = 0; i < ML_INPUT; i++)
            {
                for(int j = 0; j < ML_H1; j++)
                {
                    AdamScalarUpdate(m_w1[i][j], m_m1[i][j], m_v1[i][j],
                                     gradW1[i][j] * invBatch, lr, beta1, beta2, eps, wd);
                }
            }
            for(int j = 0; j < ML_H1; j++)
            {
                AdamScalarUpdate(m_b1[j], m_mb1[j], m_vb1[j],
                                 gradB1[j] * invBatch, lr, beta1, beta2, eps, wd);
            }
            for(int i = 0; i < ML_H1; i++)
            {
                for(int j = 0; j < ML_OUT; j++)
                {
                    AdamScalarUpdate(m_w2[i][j], m_m2[i][j], m_v2[i][j],
                                     gradW2[i][j] * invBatch, lr, beta1, beta2, eps, wd);
                }
            }
            for(int j = 0; j < ML_OUT; j++)
            {
                AdamScalarUpdate(m_b2[j], m_mb2[j], m_vb2[j],
                                 gradB2[j] * invBatch, lr, beta1, beta2, eps, wd);
            }
        }
        
        // Record average loss for early stopping
        if(lossCount > 0)
        {
            double avgLoss = batchTotalLoss / (double)lossCount;
            RecordLoss(avgLoss);
        }
    }

public:
    CMetaLabeler()
    {
        m_step = 0;
        m_bufHead = 0;
        m_bufCount = 0;
        m_bufMax = 500;
    }

    void Init(const int bufferMax = 500)
    {
        m_bufMax = MathMax(64, bufferMax);
        ArrayResize(m_bufX, m_bufMax);
        ArrayResize(m_bufY, m_bufMax);
        for(int i = 0; i < m_bufMax; i++)
        {
            for(int j = 0; j < ML_INPUT; j++)
                m_bufX[i][j] = 0.0;
            m_bufY[i] = 0;
        }

        m_bufHead = 0;
        m_bufCount = 0;
        m_step = 0;
        
        // Initialize early stopping parameters
        ArrayResize(m_lossHistory, 20);
        ArrayInitialize(m_lossHistory, 0.0);
        m_lossHead = 0;
        m_lossCount = 0;
        m_earlyStoppingPatience = AI_META_EARLY_STOP_PATIENCE;
        m_earlyStoppingThreshold = AI_META_EARLY_STOP_THRESHOLD;
        m_consecutiveNoImprovement = 0;
        m_samplesSinceLastTrain = 0;
        m_trainCooldown = AI_META_TRAIN_COOLDOWN;
        m_recentWinRate = 0.5;
        m_recentAvgConfidence = 0.5;
        m_recentCorrect = 0;
        m_recentTotal = 0;
        m_perfWindowHead = 0;

        MathSrand((int)(TimeLocal() % 2147483647));
        double scale1 = MathSqrt(2.0 / (double)ML_INPUT);
        double scale2 = MathSqrt(2.0 / (double)ML_H1);
        for(int i = 0; i < ML_INPUT; i++)
        {
            for(int j = 0; j < ML_H1; j++)
            {
                m_w1[i][j] = RandNormal() * scale1;
                m_m1[i][j] = 0.0;
                m_v1[i][j] = 0.0;
            }
        }
        for(int i = 0; i < ML_H1; i++)
        {
            m_b1[i] = 0.0;
            m_mb1[i] = 0.0;
            m_vb1[i] = 0.0;
            for(int j = 0; j < ML_OUT; j++)
            {
                m_w2[i][j] = RandNormal() * scale2;
                m_m2[i][j] = 0.0;
                m_v2[i][j] = 0.0;
            }
        }
        for(int j = 0; j < ML_OUT; j++)
        {
            m_b2[j] = 0.0;
            m_mb2[j] = 0.0;
            m_vb2[j] = 0.0;
        }
    }

    void Deinit() {}

    // Enhanced meta-input layout (24 features):
    // [0]    primaryConf
    // [1..4] regimeProbs (4 HMM states)
    // [5]    barVolRatio
    // [6..9] signal probabilities (none, buy, sell, entropy)
    // [10]   conformalUncertainty
    // [11]   recentWinRate
    // [12]   recentAvgConfidence
    // [13..22] featSubset (first 10 normalized features)
    // [23]   momentum (price change ratio)
    void BuildInput(const double primaryConf,
                    const double &regimeProbs[],
                    const double barVolRatio,
                    const double noneProb,
                    const double buyProb,
                    const double sellProb,
                    const double entropy,
                    const double conformalUncertainty,
                    const double recentWinRate,
                    const double recentAvgConfidence,
                    const double &featSubset[],
                    const double momentum,
                    double &out[])
    {
        ArrayResize(out, AI_MLP_INPUT);
        ArrayInitialize(out, 0.0);
        out[0] = primaryConf;
        for(int i = 0; i < 4; i++)
            out[1 + i] = (i < ArraySize(regimeProbs)) ? regimeProbs[i] : 0.0;
        out[5] = barVolRatio;
        out[6] = noneProb;
        out[7] = buyProb;
        out[8] = sellProb;
        out[9] = entropy;
        out[10] = conformalUncertainty;
        out[11] = recentWinRate;
        out[12] = recentAvgConfidence;
        for(int i = 0; i < 10; i++)
            out[13 + i] = (i < ArraySize(featSubset)) ? featSubset[i] : 0.0;
        out[23] = momentum;
    }

    double Predict(const double &inp[])
    {
        if(ArraySize(inp) < ML_INPUT)
            return 0.5;

        double hidden[ML_H1];
        for(int j = 0; j < ML_H1; j++)
        {
            double sum = m_b1[j];
            for(int i = 0; i < ML_INPUT; i++)
                sum += inp[i] * m_w1[i][j];
            hidden[j] = MathMax(0.0, sum);
        }

        double logits[ML_OUT];
        for(int j = 0; j < ML_OUT; j++)
        {
            double sum = m_b2[j];
            for(int i = 0; i < ML_H1; i++)
                sum += hidden[i] * m_w2[i][j];
            logits[j] = sum;
        }

        return Sigmoid(logits[1] - logits[0]);
    }

    bool Approve(const double &inp[], const double thresh = 0.52)
    {
        return Predict(inp) >= thresh;
    }

    // Track meta-labeler prediction outcomes for enriched features
    void RecordOutcome(const bool correct, const double confidence)
    {
        m_recentTotal++;
        if(correct)
            m_recentCorrect++;
        // Rolling window of last 50 outcomes
        if(m_recentTotal > 50)
        {
            m_recentTotal = 50;
            m_recentCorrect = (int)(m_recentWinRate * 50.0);
        }
        m_recentWinRate = (m_recentTotal > 0) ? ((double)m_recentCorrect / (double)m_recentTotal) : 0.5;
        m_recentAvgConfidence = 0.85 * m_recentAvgConfidence + 0.15 * confidence;
    }

    double GetRecentWinRate() const { return m_recentWinRate; }
    double GetRecentAvgConfidence() const { return m_recentAvgConfidence; }

    bool ShouldStopEarly() const
    {
        // Never stop early until minimum training has occurred
        if(m_step < AI_META_MIN_TRAIN_STEPS)
            return false;
        if(m_lossCount < m_earlyStoppingPatience)
            return false;
        
        // Calculate average loss over patience window
        double recentAvg = 0.0;
        double olderAvg = 0.0;
        int patience = m_earlyStoppingPatience;
        
        for(int i = 0; i < patience; i++)
        {
            int recentIdx = (m_lossHead - 1 - i + ArraySize(m_lossHistory)) % ArraySize(m_lossHistory);
            int olderIdx = (m_lossHead - 1 - patience - i + ArraySize(m_lossHistory)) % ArraySize(m_lossHistory);
            recentAvg += m_lossHistory[recentIdx];
            olderAvg += m_lossHistory[olderIdx];
        }
        
        recentAvg /= (double)patience;
        olderAvg /= (double)patience;
        
        // If recent loss is not improving, stop early
        return (olderAvg - recentAvg) < m_earlyStoppingThreshold;
    }

    void RecordLoss(const double loss)
    {
        m_lossHistory[m_lossHead] = loss;
        m_lossHead = (m_lossHead + 1) % ArraySize(m_lossHistory);
        if(m_lossCount < ArraySize(m_lossHistory))
            m_lossCount++;
    }

    void AddSample(const double &inp[], const int label)
    {
        if(ArraySize(inp) < ML_INPUT || ArraySize(m_bufX) == 0)
            return;

        int slot = m_bufHead % m_bufMax;
        for(int i = 0; i < ML_INPUT; i++)
            m_bufX[slot][i] = inp[i];
        m_bufY[slot] = (label > 0) ? 1 : 0;
        m_bufHead++;
        if(m_bufCount < m_bufMax)
            m_bufCount++;

        m_samplesSinceLastTrain++;
        if(m_bufCount >= 50 && !ShouldStopEarly() && m_samplesSinceLastTrain >= m_trainCooldown)
        {
            TrainStep(8, 12);
            m_samplesSinceLastTrain = 0;
            static datetime s_lastTrainLog = 0;
            if(s_lastTrainLog == 0 || (TimeCurrent() - s_lastTrainLog) >= 60)
            {
                PrintFormat("[AI-META-TRAIN] samples=%d | step=%I64d | loss_count=%d | buf=%d/%d",
                            m_bufCount, m_step, m_lossCount, m_bufCount, m_bufMax);
                s_lastTrainLog = TimeCurrent();
            }
        }
    }
};

#endif // __META_LABELER_MQH__
