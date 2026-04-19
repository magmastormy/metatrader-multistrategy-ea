//+------------------------------------------------------------------+
//| MetaLabeler.mqh                                                  |
//| Secondary profitability filter for AI-originated trade signals   |
//+------------------------------------------------------------------+
#property strict

#ifndef __META_LABELER_MQH__
#define __META_LABELER_MQH__

#define ML_INPUT  16
#define ML_H1     24
#define ML_OUT     2

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

    void TrainStep(const int steps, const int batch)
    {
        double lr = 1e-3;
        double beta1 = 0.9;
        double beta2 = 0.999;
        double eps = 1e-8;
        double wd = 1e-4;

        double gradW1[ML_INPUT][ML_H1];
        double gradB1[ML_H1];
        double gradW2[ML_H1][ML_OUT];
        double gradB2[ML_OUT];

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

    void BuildInput(const double primaryConf,
                    const double &regimeProbs[],
                    const double barVolRatio,
                    const double &featSubset[],
                    double &out[])
    {
        ArrayResize(out, ML_INPUT);
        out[0] = primaryConf;
        for(int i = 0; i < 4; i++)
            out[1 + i] = (i < ArraySize(regimeProbs)) ? regimeProbs[i] : 0.0;
        out[5] = barVolRatio;
        for(int i = 0; i < 10; i++)
            out[6 + i] = (i < ArraySize(featSubset)) ? featSubset[i] : 0.0;
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

    void AddSample(const double &inp[], const int label)
    {
        if(ArraySize(inp) < ML_INPUT)
            return;

        int slot = m_bufHead % m_bufMax;
        for(int i = 0; i < ML_INPUT; i++)
            m_bufX[slot][i] = inp[i];
        m_bufY[slot] = (label > 0) ? 1 : 0;
        m_bufHead++;
        if(m_bufCount < m_bufMax)
            m_bufCount++;

        if(m_bufCount >= 50)
            TrainStep(8, 12);
    }
};

#endif // __META_LABELER_MQH__
