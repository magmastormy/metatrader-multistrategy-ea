//+------------------------------------------------------------------+
//| TransformerBrain.mqh                                             |
//| Pre-norm transformer encoder with RoPE and AdamW classification  |
//+------------------------------------------------------------------+
#property strict

#ifndef __TRANSFORMER_BRAIN_MQH__
#define __TRANSFORMER_BRAIN_MQH__

#include <Arrays/ArrayObj.mqh>

#define TRANSFORMER_HEAD_STATE_MAGIC   1414677859
#define TRANSFORMER_HEAD_STATE_VERSION 2

class CEWCRegularizer
{
private:
    double m_fisherDiag[];
    double m_thetaStar[];
    double m_lambda;
    bool   m_initialized;
    int    m_weightCount;

public:
    CEWCRegularizer()
    {
        m_lambda = 400.0;
        m_initialized = false;
        m_weightCount = 0;
    }

    void Init(const int weightCount, const double lambda = 400.0)
    {
        m_weightCount = MathMax(0, weightCount);
        ArrayResize(m_fisherDiag, m_weightCount);
        ArrayResize(m_thetaStar, m_weightCount);
        ArrayInitialize(m_fisherDiag, 0.0);
        ArrayInitialize(m_thetaStar, 0.0);
        m_lambda = lambda;
        m_initialized = false;
    }

    void Anchor(const double &currentWeights[], const double &recentGradSq[], const int count)
    {
        int size = MathMin(m_weightCount, ArraySize(currentWeights));
        for(int i = 0; i < m_weightCount; i++)
        {
            m_thetaStar[i] = (i < size) ? currentWeights[i] : 0.0;
            m_fisherDiag[i] = (i < count && i < ArraySize(recentGradSq)) ? recentGradSq[i] : 0.0;
        }
        m_initialized = true;
    }

    double PenaltyGrad(const double &currentWeights[], const int index) const
    {
        if(!m_initialized || index < 0 || index >= m_weightCount || index >= ArraySize(currentWeights))
            return 0.0;
        return m_lambda * m_fisherDiag[index] * (currentWeights[index] - m_thetaStar[index]);
    }

    bool IsAnchored() const { return m_initialized; }
};

class CRoPEEncoding : public CObject
{
private:
    double m_cos[];
    double m_sin[];
    int    m_dModel;
    int    m_maxSeqLen;

    int Offset(const int pos, const int dim) const
    {
        return pos * m_dModel + dim;
    }

public:
    CRoPEEncoding()
    {
        m_dModel = 0;
        m_maxSeqLen = 0;
    }

    void Init(const int dModel, const int maxSeqLen)
    {
        m_dModel = MathMax(2, dModel);
        m_maxSeqLen = MathMax(1, maxSeqLen);
        ArrayResize(m_cos, m_maxSeqLen * m_dModel);
        ArrayResize(m_sin, m_maxSeqLen * m_dModel);
        ArrayInitialize(m_cos, 1.0);
        ArrayInitialize(m_sin, 0.0);

        for(int pos = 0; pos < m_maxSeqLen; pos++)
        {
            for(int i = 0; i < m_dModel / 2; i++)
            {
                double theta = MathPow(10000.0, (-2.0 * (double)i) / (double)m_dModel) * (double)pos;
                double cosTheta = MathCos(theta);
                double sinTheta = MathSin(theta);
                int even = 2 * i;
                int odd = even + 1;
                if(odd >= m_dModel)
                    break;
                m_cos[Offset(pos, even)] = cosTheta;
                m_cos[Offset(pos, odd)] = cosTheta;
                m_sin[Offset(pos, even)] = -sinTheta;
                m_sin[Offset(pos, odd)] = sinTheta;
            }
        }
    }

    void Apply(double &vec[], const int pos)
    {
        if(pos < 0 || pos >= m_maxSeqLen || ArraySize(vec) < 2)
            return;

        int width = MathMin(ArraySize(vec), m_dModel);
        for(int i = 0; i < width - 1; i += 2)
        {
            double v0 = vec[i];
            double v1 = vec[i + 1];
            vec[i] = v0 * m_cos[Offset(pos, i)] + v1 * m_sin[Offset(pos, i)];
            vec[i + 1] = v0 * m_cos[Offset(pos, i + 1)] + v1 * m_sin[Offset(pos, i + 1)];
        }
    }
};

class CLayerNorm : public CObject
{
private:
    double m_gamma[];
    double m_beta[];
    int    m_width;
    double m_epsilon;

public:
    CLayerNorm(const int width = 32, const double epsilon = 1e-6)
    {
        m_width = MathMax(1, width);
        m_epsilon = epsilon;
        ArrayResize(m_gamma, m_width);
        ArrayResize(m_beta, m_width);
        for(int i = 0; i < m_width; i++)
        {
            m_gamma[i] = 1.0;
            m_beta[i] = 0.0;
        }
    }

    bool ForwardSingle(const double &inputData[], double &output[])
    {
        if(ArraySize(inputData) != m_width)
            return false;

        double mean = 0.0;
        for(int i = 0; i < m_width; i++)
            mean += inputData[i];
        mean /= (double)m_width;

        double variance = 0.0;
        for(int i = 0; i < m_width; i++)
        {
            double diff = inputData[i] - mean;
            variance += diff * diff;
        }
        variance /= (double)m_width;

        double denom = MathSqrt(variance + m_epsilon);
        ArrayResize(output, m_width);
        for(int i = 0; i < m_width; i++)
        {
            double normalized = (inputData[i] - mean) / denom;
            output[i] = normalized * m_gamma[i] + m_beta[i];
        }
        return true;
    }

    bool Forward(const double &inputData[], double &output[])
    {
        if(ArraySize(inputData) == m_width)
            return ForwardSingle(inputData, output);

        if(ArraySize(inputData) <= 0 || (ArraySize(inputData) % m_width) != 0)
            return false;

        int seqLen = ArraySize(inputData) / m_width;
        ArrayResize(output, ArraySize(inputData));
        double sliceIn[];
        double sliceOut[];
        ArrayResize(sliceIn, m_width);

        for(int step = 0; step < seqLen; step++)
        {
            for(int i = 0; i < m_width; i++)
                sliceIn[i] = inputData[step * m_width + i];
            if(!ForwardSingle(sliceIn, sliceOut))
                return false;
            for(int i = 0; i < m_width; i++)
                output[step * m_width + i] = sliceOut[i];
        }
        return true;
    }
};

class CFeedForwardNetwork : public CObject
{
private:
    int    m_dModel;
    int    m_dFF;
    double m_w1[];
    double m_b1[];
    double m_w2[];
    double m_b2[];
    uint   m_state;

    double NextRand()
    {
        m_state = m_state * 1664525 + 1013904223;
        return (double)m_state / 4294967296.0;
    }

public:
    CFeedForwardNetwork(const int dModel = 32, const int dFF = 64, const int seed = 1)
    {
        m_dModel = MathMax(1, dModel);
        m_dFF = MathMax(m_dModel, dFF);
        m_state = (uint)MathMax(1, seed);

        ArrayResize(m_w1, m_dModel * m_dFF);
        ArrayResize(m_b1, m_dFF);
        ArrayResize(m_w2, m_dFF * m_dModel);
        ArrayResize(m_b2, m_dModel);

        double scale1 = MathSqrt(2.0 / (double)(m_dModel + m_dFF));
        double scale2 = MathSqrt(2.0 / (double)(m_dFF + m_dModel));
        for(int i = 0; i < ArraySize(m_w1); i++)
            m_w1[i] = (NextRand() - 0.5) * 2.0 * scale1;
        for(int i = 0; i < ArraySize(m_w2); i++)
            m_w2[i] = (NextRand() - 0.5) * 2.0 * scale2;
        ArrayInitialize(m_b1, 0.0);
        ArrayInitialize(m_b2, 0.0);
    }

    bool Forward(const double &inputData[], double &output[])
    {
        if(ArraySize(inputData) <= 0 || (ArraySize(inputData) % m_dModel) != 0)
            return false;

        int seqLen = ArraySize(inputData) / m_dModel;
        ArrayResize(output, ArraySize(inputData));

        double hidden[];
        ArrayResize(hidden, m_dFF);

        for(int step = 0; step < seqLen; step++)
        {
            for(int j = 0; j < m_dFF; j++)
            {
                double sum = m_b1[j];
                for(int i = 0; i < m_dModel; i++)
                    sum += inputData[step * m_dModel + i] * m_w1[i * m_dFF + j];
                hidden[j] = MathMax(0.0, sum);
            }

            for(int j = 0; j < m_dModel; j++)
            {
                double sum = m_b2[j];
                for(int i = 0; i < m_dFF; i++)
                    sum += hidden[i] * m_w2[i * m_dModel + j];
                output[step * m_dModel + j] = sum;
            }
        }

        return true;
    }
};

class CMultiHeadAttention : public CObject
{
private:
    int           m_dModel;
    int           m_numHeads;
    int           m_dHead;
    double        m_wq[];
    double        m_wk[];
    double        m_wv[];
    double        m_wo[];
    double        m_attentionWeights[];
    CRoPEEncoding m_rope;
    uint          m_state;

    double NextRand()
    {
        m_state = m_state * 1664525 + 1013904223;
        return (double)m_state / 4294967296.0;
    }

    bool Project(const double &inputData[], const double &weights[], double &output[])
    {
        if(ArraySize(inputData) <= 0 || (ArraySize(inputData) % m_dModel) != 0)
            return false;

        int seqLen = ArraySize(inputData) / m_dModel;
        ArrayResize(output, ArraySize(inputData));
        for(int t = 0; t < seqLen; t++)
        {
            for(int outIdx = 0; outIdx < m_dModel; outIdx++)
            {
                double sum = 0.0;
                for(int inIdx = 0; inIdx < m_dModel; inIdx++)
                    sum += inputData[t * m_dModel + inIdx] * weights[inIdx * m_dModel + outIdx];
                output[t * m_dModel + outIdx] = sum;
            }
        }
        return true;
    }

public:
    CMultiHeadAttention(const int dModel = 32, const int numHeads = 4, const int maxSeqLen = 60, const int seed = 1)
    {
        m_dModel = MathMax(2, dModel);
        m_numHeads = MathMax(1, numHeads);
        while((m_dModel % m_numHeads) != 0 && m_numHeads > 1)
            m_numHeads--;
        m_dHead = MathMax(1, m_dModel / m_numHeads);
        m_state = (uint)MathMax(1, seed);

        ArrayResize(m_wq, m_dModel * m_dModel);
        ArrayResize(m_wk, m_dModel * m_dModel);
        ArrayResize(m_wv, m_dModel * m_dModel);
        ArrayResize(m_wo, m_dModel * m_dModel);

        double scale = MathSqrt(2.0 / (double)(m_dModel + m_dModel));
        for(int i = 0; i < ArraySize(m_wq); i++)
        {
            m_wq[i] = (NextRand() - 0.5) * 2.0 * scale;
            m_wk[i] = (NextRand() - 0.5) * 2.0 * scale;
            m_wv[i] = (NextRand() - 0.5) * 2.0 * scale;
            m_wo[i] = (NextRand() - 0.5) * 2.0 * scale;
        }

        m_rope.Init(m_dHead, maxSeqLen);
    }

    bool Forward(const double &inputData[], double &output[])
    {
        if(ArraySize(inputData) <= 0 || (ArraySize(inputData) % m_dModel) != 0)
            return false;

        int seqLen = ArraySize(inputData) / m_dModel;
        double q[];
        double k[];
        double v[];
        if(!Project(inputData, m_wq, q) || !Project(inputData, m_wk, k) || !Project(inputData, m_wv, v))
            return false;

        for(int t = 0; t < seqLen; t++)
        {
            for(int head = 0; head < m_numHeads; head++)
            {
                double qVec[];
                double kVec[];
                ArrayResize(qVec, m_dHead);
                ArrayResize(kVec, m_dHead);

                int offset = t * m_dModel + head * m_dHead;
                for(int i = 0; i < m_dHead; i++)
                {
                    qVec[i] = q[offset + i];
                    kVec[i] = k[offset + i];
                }

                m_rope.Apply(qVec, t);
                m_rope.Apply(kVec, t);

                for(int i = 0; i < m_dHead; i++)
                {
                    q[offset + i] = qVec[i];
                    k[offset + i] = kVec[i];
                }
            }
        }

        ArrayResize(output, ArraySize(inputData));
        ArrayInitialize(output, 0.0);
        ArrayResize(m_attentionWeights, m_numHeads * seqLen * seqLen);
        ArrayInitialize(m_attentionWeights, 0.0);

        double headOutput[];
        ArrayResize(headOutput, seqLen * m_dHead);
        double scores[];
        ArrayResize(scores, seqLen);

        for(int head = 0; head < m_numHeads; head++)
        {
            for(int t = 0; t < seqLen; t++)
            {
                double maxScore = -DBL_MAX;
                for(int src = 0; src < seqLen; src++)
                {
                    double dot = 0.0;
                    int qOffset = t * m_dModel + head * m_dHead;
                    int kOffset = src * m_dModel + head * m_dHead;
                    for(int d = 0; d < m_dHead; d++)
                        dot += q[qOffset + d] * k[kOffset + d];
                    scores[src] = dot / MathSqrt((double)m_dHead);
                    if(scores[src] > maxScore)
                        maxScore = scores[src];
                }

                double sumExp = 0.0;
                for(int src = 0; src < seqLen; src++)
                {
                    scores[src] = MathExp(scores[src] - maxScore);
                    sumExp += scores[src];
                }
                if(sumExp <= 1e-9)
                    sumExp = 1.0;

                int attnBase = head * seqLen * seqLen + t * seqLen;
                for(int src = 0; src < seqLen; src++)
                {
                    scores[src] /= sumExp;
                    m_attentionWeights[attnBase + src] = scores[src];
                }

                for(int d = 0; d < m_dHead; d++)
                {
                    double sum = 0.0;
                    for(int src = 0; src < seqLen; src++)
                    {
                        int vOffset = src * m_dModel + head * m_dHead + d;
                        sum += scores[src] * v[vOffset];
                    }
                    headOutput[t * m_dHead + d] = sum;
                }
            }

            for(int t = 0; t < seqLen; t++)
            {
                for(int d = 0; d < m_dHead; d++)
                    output[t * m_dModel + head * m_dHead + d] = headOutput[t * m_dHead + d];
            }
        }

        double projected[];
        if(!Project(output, m_wo, projected))
            return false;
        ArrayCopy(output, projected);
        return true;
    }

    void GetAttentionWeights(double &weights[])
    {
        ArrayCopy(weights, m_attentionWeights);
    }
};

class CTransformerBlock : public CObject
{
private:
    CMultiHeadAttention* m_attention;
    CFeedForwardNetwork* m_feedForward;
    CLayerNorm*          m_layerNorm1;
    CLayerNorm*          m_layerNorm2;

public:
    CTransformerBlock(const int dModel = 32,
                      const int numHeads = 4,
                      const int dFF = 64,
                      const int maxSeqLen = 60,
                      const int seed = 1)
    {
        m_attention = new CMultiHeadAttention(dModel, numHeads, maxSeqLen, seed);
        m_feedForward = new CFeedForwardNetwork(dModel, dFF, seed + 17);
        m_layerNorm1 = new CLayerNorm(dModel);
        m_layerNorm2 = new CLayerNorm(dModel);
    }

    virtual ~CTransformerBlock()
    {
        if(CheckPointer(m_attention) == POINTER_DYNAMIC) delete m_attention;
        if(CheckPointer(m_feedForward) == POINTER_DYNAMIC) delete m_feedForward;
        if(CheckPointer(m_layerNorm1) == POINTER_DYNAMIC) delete m_layerNorm1;
        if(CheckPointer(m_layerNorm2) == POINTER_DYNAMIC) delete m_layerNorm2;
    }

    bool Forward(const double &inputData[], double &output[])
    {
        if(m_attention == NULL || m_feedForward == NULL || m_layerNorm1 == NULL || m_layerNorm2 == NULL)
            return false;

        double norm1[];
        if(!m_layerNorm1.Forward(inputData, norm1))
            return false;

        double attnOut[];
        if(!m_attention.Forward(norm1, attnOut))
            return false;
        if(ArraySize(attnOut) != ArraySize(inputData))
            return false;

        double residual1[];
        ArrayResize(residual1, ArraySize(inputData));
        for(int i = 0; i < ArraySize(inputData); i++)
            residual1[i] = inputData[i] + attnOut[i];

        double norm2[];
        if(!m_layerNorm2.Forward(residual1, norm2))
            return false;

        double ffnOut[];
        if(!m_feedForward.Forward(norm2, ffnOut))
            return false;
        if(ArraySize(ffnOut) != ArraySize(residual1))
            return false;

        ArrayResize(output, ArraySize(residual1));
        for(int i = 0; i < ArraySize(residual1); i++)
            output[i] = residual1[i] + ffnOut[i];
        return true;
    }

    bool GetAttentionWeights(double &weights[])
    {
        if(m_attention == NULL)
            return false;
        m_attention.GetAttentionWeights(weights);
        return true;
    }
};

class CTransformerBrain : public CObject
{
private:
    CArrayObj       m_blocks;
    double          m_attentionWeights[];
    double          m_classificationWeights[];
    double          m_classificationBiases[];
    double          m_patternWeights[];
    double          m_patternBiases[];
    double          m_classAdamM[];
    double          m_classAdamV[];
    double          m_classBiasAdamM[];
    double          m_classBiasAdamV[];
    double          m_patternAdamM[];
    double          m_patternAdamV[];
    double          m_patternBiasAdamM[];
    double          m_patternBiasAdamV[];
    double          m_gradSqBuffer[];
    int             m_gradBufHead;
    int             m_gradBufCount;
    long            m_adamStep;
    double          m_adamBeta1;
    double          m_adamBeta2;
    double          m_adamEps;
    double          m_adamWD;
    double          m_adamLR;
    double          m_totalLoss;
    int             m_trainingSteps;
    int             m_dModel;
    int             m_numHeads;
    int             m_numLayers;
    int             m_dFF;
    int             m_maxSeqLen;
    uint            m_state;
    CEWCRegularizer m_ewc;

    int GradSqOffset(const int row, const int col) const
    {
        int total = ArraySize(m_classificationWeights) + ArraySize(m_classificationBiases);
        if(total <= 0)
            return 0;
        return row * total + col;
    }

    double NextRand()
    {
        m_state = m_state * 1664525 + 1013904223;
        return (double)m_state / 4294967296.0;
    }

    void InitHeadWeights()
    {
        int classWeightCount = 3 * m_dModel;
        int patternWeightCount = 10 * m_dModel;
        ArrayResize(m_classificationWeights, classWeightCount);
        ArrayResize(m_classificationBiases, 3);
        ArrayResize(m_patternWeights, patternWeightCount);
        ArrayResize(m_patternBiases, 10);

        ArrayResize(m_classAdamM, classWeightCount);
        ArrayResize(m_classAdamV, classWeightCount);
        ArrayResize(m_classBiasAdamM, 3);
        ArrayResize(m_classBiasAdamV, 3);
        ArrayResize(m_patternAdamM, patternWeightCount);
        ArrayResize(m_patternAdamV, patternWeightCount);
        ArrayResize(m_patternBiasAdamM, 10);
        ArrayResize(m_patternBiasAdamV, 10);

        ArrayInitialize(m_classAdamM, 0.0);
        ArrayInitialize(m_classAdamV, 0.0);
        ArrayInitialize(m_classBiasAdamM, 0.0);
        ArrayInitialize(m_classBiasAdamV, 0.0);
        ArrayInitialize(m_patternAdamM, 0.0);
        ArrayInitialize(m_patternAdamV, 0.0);
        ArrayInitialize(m_patternBiasAdamM, 0.0);
        ArrayInitialize(m_patternBiasAdamV, 0.0);

        double scaleClass = MathSqrt(2.0 / (double)(m_dModel + 3));
        double scalePattern = MathSqrt(2.0 / (double)(m_dModel + 10));
        for(int i = 0; i < classWeightCount; i++)
            m_classificationWeights[i] = (NextRand() - 0.5) * 2.0 * scaleClass;
        for(int i = 0; i < patternWeightCount; i++)
            m_patternWeights[i] = (NextRand() - 0.5) * 2.0 * scalePattern;
        ArrayInitialize(m_classificationBiases, 0.0);
        ArrayInitialize(m_patternBiases, 0.0);

        int totalClassParams = classWeightCount + ArraySize(m_classificationBiases);
        m_ewc.Init(totalClassParams);
        ArrayResize(m_gradSqBuffer, 50 * totalClassParams);
        ArrayInitialize(m_gradSqBuffer, 0.0);
        m_gradBufHead = 0;
        m_gradBufCount = 0;
    }

    double GetCyclicLR() const
    {
        int cycleLen = 1000;
        double progress = (double)(m_adamStep % cycleLen) / (double)cycleLen;
        return m_adamLR * (0.1 + 0.9 * 0.5 * (1.0 + MathCos(M_PI * progress)));
    }

    void StoreGradSq(const int index, const double gradSq)
    {
        int total = ArraySize(m_classificationWeights) + ArraySize(m_classificationBiases);
        if(index < 0 || total <= 0 || ArraySize(m_gradSqBuffer) < (50 * total))
            return;
        int row = m_gradBufHead % 50;
        if(index >= total)
            return;
        m_gradSqBuffer[GradSqOffset(row, index)] = gradSq;
    }

    void AdamWUpdate(double &weights[],
                     double &m[],
                     double &v[],
                     const int index,
                     double grad,
                     const bool applyEwc,
                     const int ewcIndex)
    {
        double currentWeights[];
        if(applyEwc)
            GetWeights(currentWeights);

        double totalGrad = grad;
        if(applyEwc)
            totalGrad += m_ewc.PenaltyGrad(currentWeights, ewcIndex);

        if(applyEwc)
            StoreGradSq(ewcIndex, totalGrad * totalGrad);

        m[index] = m_adamBeta1 * m[index] + (1.0 - m_adamBeta1) * totalGrad;
        v[index] = m_adamBeta2 * v[index] + (1.0 - m_adamBeta2) * totalGrad * totalGrad;
        double mHat = m[index] / (1.0 - MathPow(m_adamBeta1, (double)m_adamStep));
        double vHat = v[index] / (1.0 - MathPow(m_adamBeta2, (double)m_adamStep));
        double lr = GetCyclicLR();
        weights[index] -= lr * ((mHat / (MathSqrt(vHat) + m_adamEps)) + (m_adamWD * weights[index]));
    }

    bool ComputeClassProbabilities(const double &features[], double &probabilities[]) const
    {
        if(ArraySize(features) != m_dModel)
            return false;

        double logits[3];
        for(int c = 0; c < 3; c++)
        {
            double score = m_classificationBiases[c];
            int rowOffset = c * m_dModel;
            for(int i = 0; i < m_dModel; i++)
                score += m_classificationWeights[rowOffset + i] * features[i];
            logits[c] = score;
        }

        double maxLogit = MathMax(logits[0], MathMax(logits[1], logits[2]));
        double exp0 = MathExp(logits[0] - maxLogit);
        double exp1 = MathExp(logits[1] - maxLogit);
        double exp2 = MathExp(logits[2] - maxLogit);
        double sumExp = exp0 + exp1 + exp2;
        if(sumExp <= 1e-12)
            return false;

        ArrayResize(probabilities, 3);
        probabilities[0] = exp0 / sumExp;
        probabilities[1] = exp1 / sumExp;
        probabilities[2] = exp2 / sumExp;
        return true;
    }

    bool ComputePatternProbabilities(const double &features[], double &probabilities[]) const
    {
        if(ArraySize(features) != m_dModel)
            return false;

        ArrayResize(probabilities, 10);
        double logits[10];
        double maxLogit = -DBL_MAX;
        for(int c = 0; c < 10; c++)
        {
            double score = m_patternBiases[c];
            int rowOffset = c * m_dModel;
            for(int i = 0; i < m_dModel; i++)
                score += m_patternWeights[rowOffset + i] * features[i];
            logits[c] = score;
            if(score > maxLogit)
                maxLogit = score;
        }

        double sumExp = 0.0;
        for(int c = 0; c < 10; c++)
        {
            probabilities[c] = MathExp(logits[c] - maxLogit);
            sumExp += probabilities[c];
        }
        if(sumExp <= 1e-12)
            return false;

        for(int c = 0; c < 10; c++)
            probabilities[c] /= sumExp;
        return true;
    }

    void UpdateClassificationHead(const double &features[], const double &probabilities[], const int targetClass)
    {
        if(ArraySize(features) != m_dModel || ArraySize(probabilities) != 3 || targetClass < 0 || targetClass >= 3)
            return;

        m_adamStep++;
        int ewcIndex = 0;
        for(int c = 0; c < 3; c++)
        {
            double target = (c == targetClass) ? 1.0 : 0.0;
            double error = probabilities[c] - target;
            int rowOffset = c * m_dModel;

            for(int i = 0; i < m_dModel; i++)
            {
                int idx = rowOffset + i;
                AdamWUpdate(m_classificationWeights, m_classAdamM, m_classAdamV, idx, error * features[i], true, ewcIndex);
                ewcIndex++;
            }

            AdamWUpdate(m_classificationBiases, m_classBiasAdamM, m_classBiasAdamV, c, error, true, ewcIndex);
            ewcIndex++;
        }

        int completedRow = m_gradBufHead % 50;
        int total = ArraySize(m_classificationWeights) + ArraySize(m_classificationBiases);
        for(int clearIdx = ewcIndex; clearIdx < total; clearIdx++)
            m_gradSqBuffer[GradSqOffset(completedRow, clearIdx)] = 0.0;
        m_gradBufHead++;
        if(m_gradBufCount < 50)
            m_gradBufCount++;
    }

    void UpdatePatternHead(const double &features[], const double &probabilities[], const int targetClass)
    {
        if(ArraySize(features) != m_dModel || ArraySize(probabilities) != 10 || targetClass < 0 || targetClass >= 10)
            return;

        m_adamStep++;
        for(int c = 0; c < 10; c++)
        {
            double target = (c == targetClass) ? 1.0 : 0.0;
            double error = probabilities[c] - target;
            int rowOffset = c * m_dModel;
            for(int i = 0; i < m_dModel; i++)
            {
                int idx = rowOffset + i;
                AdamWUpdate(m_patternWeights, m_patternAdamM, m_patternAdamV, idx, error * features[i], false, -1);
            }
            AdamWUpdate(m_patternBiases, m_patternBiasAdamM, m_patternBiasAdamV, c, error, false, -1);
        }
    }

public:
    CTransformerBrain(const int dModel = 32,
                      const int numHeads = 4,
                      const int numLayers = 2,
                      const int dFF = 64,
                      const int maxSeqLen = 60,
                      const double learningRate = 0.001)
    {
        m_dModel = MathMax(2, dModel);
        m_numHeads = MathMax(1, numHeads);
        m_numLayers = MathMax(1, numLayers);
        m_dFF = MathMax(m_dModel, dFF);
        m_maxSeqLen = MathMax(1, maxSeqLen);
        m_adamLR = learningRate;
        m_adamBeta1 = 0.9;
        m_adamBeta2 = 0.999;
        m_adamEps = 1e-8;
        m_adamWD = 1e-4;
        m_adamStep = 0;
        m_totalLoss = 0.0;
        m_trainingSteps = 0;
        m_state = 20260419;

        m_blocks.FreeMode(true);
        for(int i = 0; i < m_numLayers; i++)
            m_blocks.Add(new CTransformerBlock(m_dModel, m_numHeads, m_dFF, m_maxSeqLen, 100 + i * 17));

        InitHeadWeights();
        PrintFormat("[TRANSFORMER] Initialized | dModel=%d | heads=%d | layers=%d | seq=%d",
                    m_dModel, m_numHeads, m_numLayers, m_maxSeqLen);
    }

    virtual ~CTransformerBrain()
    {
        m_blocks.Clear();
    }

    int GetModelDimension() const { return m_dModel; }
    int GetMaxSequenceLength() const { return m_maxSeqLen; }
    bool IsWarmedUp(const int threshold = 100) const { return m_trainingSteps >= threshold; }

    bool Forward(const double &inputFeatures[], const int actualSeqLen, double &output[])
    {
        int total = ArraySize(inputFeatures);
        if(total <= 0 || m_dModel <= 0 || (total % m_dModel) != 0)
            return false;

        int derivedSeqLen = total / m_dModel;
        int seqLen = MathMin(MathMax(1, actualSeqLen), MathMin(m_maxSeqLen, derivedSeqLen));
        if(seqLen <= 0)
            return false;

        int usable = seqLen * m_dModel;
        double current[];
        ArrayResize(current, usable);
        ArrayCopy(current, inputFeatures, 0, 0, usable);

        double next[];
        for(int i = 0; i < m_blocks.Total(); i++)
        {
            CTransformerBlock* block = (CTransformerBlock*)m_blocks.At(i);
            if(block == NULL || !block.Forward(current, next))
                return false;
            ArrayCopy(current, next);
        }

        ArrayResize(output, m_dModel);
        ArrayInitialize(output, 0.0);
        for(int d = 0; d < m_dModel; d++)
        {
            double sum = 0.0;
            for(int t = 0; t < seqLen; t++)
                sum += current[t * m_dModel + d];
            output[d] = sum / (double)seqLen;
        }

        if(m_blocks.Total() > 0)
        {
            CTransformerBlock* first = (CTransformerBlock*)m_blocks.At(0);
            if(first != NULL)
                first.GetAttentionWeights(m_attentionWeights);
        }

        return true;
    }

    bool Forward(const double &inputFeatures[], double &output[])
    {
        if(m_dModel <= 0 || ArraySize(inputFeatures) <= 0 || (ArraySize(inputFeatures) % m_dModel) != 0)
            return false;
        return Forward(inputFeatures, ArraySize(inputFeatures) / m_dModel, output);
    }

    bool GetEncodedFeatures(const double &inputFeatures[], const int actualSeqLen, double &features[])
    {
        return Forward(inputFeatures, actualSeqLen, features);
    }

    bool GetPredictions(const double &inputFeatures[], double &predictions[])
    {
        if(m_dModel <= 0 || ArraySize(inputFeatures) <= 0 || (ArraySize(inputFeatures) % m_dModel) != 0)
            return false;
        return GetPredictions(inputFeatures, ArraySize(inputFeatures) / m_dModel, predictions);
    }

    bool GetPredictions(const double &inputFeatures[], const int actualSeqLen, double &predictions[])
    {
        double encoded[];
        if(!Forward(inputFeatures, actualSeqLen, encoded))
            return false;
        return ComputeClassProbabilities(encoded, predictions);
    }

    bool GetPatternPredictions(const double &inputFeatures[], double &patternProbabilities[], int &patternIndex, double &confidence)
    {
        double encoded[];
        if(!Forward(inputFeatures, ArraySize(inputFeatures) / MathMax(1, m_dModel), encoded))
            return false;

        if(!ComputePatternProbabilities(encoded, patternProbabilities))
            return false;

        patternIndex = 0;
        confidence = patternProbabilities[0];
        for(int i = 1; i < ArraySize(patternProbabilities); i++)
        {
            if(patternProbabilities[i] > confidence)
            {
                confidence = patternProbabilities[i];
                patternIndex = i;
            }
        }
        return true;
    }

    double CalculateLoss(const double &predictions[], const int targetClass) const
    {
        if(ArraySize(predictions) != 3 || targetClass < 0 || targetClass >= 3)
            return 0.0;
        return -MathLog(MathMax(predictions[targetClass], 1e-12));
    }

    bool TrainStep(const double &inputFeatures[], const int targetClass, double &loss)
    {
        if(targetClass < 0 || targetClass >= 3)
            return false;

        double encoded[];
        if(!Forward(inputFeatures, ArraySize(inputFeatures) / MathMax(1, m_dModel), encoded))
            return false;

        double probabilities[];
        if(!ComputeClassProbabilities(encoded, probabilities))
            return false;

        loss = CalculateLoss(probabilities, targetClass);
        if(!MathIsValidNumber(loss))
            return false;

        UpdateClassificationHead(encoded, probabilities, targetClass);
        m_totalLoss += loss;
        m_trainingSteps++;

        if((m_trainingSteps % 25) == 0)
        {
            PrintFormat("[TRANSFORMER-LR] step=%d | lr=%.8f | loss=%.6f | ewc=%s",
                        m_trainingSteps, GetCyclicLR(), loss, m_ewc.IsAnchored() ? "anchored" : "cold");
        }

        return true;
    }

    bool TrainPatternStep(const double &inputFeatures[], const int targetPatternClass, double &loss)
    {
        if(targetPatternClass < 0 || targetPatternClass >= 10)
            return false;

        double encoded[];
        if(!Forward(inputFeatures, ArraySize(inputFeatures) / MathMax(1, m_dModel), encoded))
            return false;

        double probabilities[];
        if(!ComputePatternProbabilities(encoded, probabilities))
            return false;

        loss = -MathLog(MathMax(probabilities[targetPatternClass], 1e-12));
        if(!MathIsValidNumber(loss))
            return false;

        UpdatePatternHead(encoded, probabilities, targetPatternClass);
        m_totalLoss += loss;
        m_trainingSteps++;
        return true;
    }

    void GetAttentionWeights(double &outWeights[])
    {
        ArrayCopy(outWeights, m_attentionWeights);
    }

    void ResetTraining()
    {
        m_trainingSteps = 0;
        m_totalLoss = 0.0;
        ArrayInitialize(m_classAdamM, 0.0);
        ArrayInitialize(m_classAdamV, 0.0);
        ArrayInitialize(m_classBiasAdamM, 0.0);
        ArrayInitialize(m_classBiasAdamV, 0.0);
        ArrayInitialize(m_patternAdamM, 0.0);
        ArrayInitialize(m_patternAdamV, 0.0);
        ArrayInitialize(m_patternBiasAdamM, 0.0);
        ArrayInitialize(m_patternBiasAdamV, 0.0);
    }

    string GetModelInfo()
    {
        return StringFormat("TransformerBrain(dModel=%d, heads=%d, layers=%d, seq=%d, steps=%d, avgLoss=%.6f)",
                            m_dModel,
                            m_numHeads,
                            m_numLayers,
                            m_maxSeqLen,
                            m_trainingSteps,
                            (m_trainingSteps > 0) ? (m_totalLoss / (double)m_trainingSteps) : 0.0);
    }

    void GetRecentFisherApprox(double &out[])
    {
        int total = ArraySize(m_classificationWeights) + ArraySize(m_classificationBiases);
        ArrayResize(out, total);
        ArrayInitialize(out, 0.0);
        if(m_gradBufCount <= 0)
            return;

        for(int row = 0; row < m_gradBufCount; row++)
        {
            for(int col = 0; col < total; col++)
                out[col] += m_gradSqBuffer[GradSqOffset(row, col)];
        }
        for(int col = 0; col < total; col++)
            out[col] /= (double)m_gradBufCount;
    }

    void GetWeights(double &out[])
    {
        int total = ArraySize(m_classificationWeights) + ArraySize(m_classificationBiases);
        ArrayResize(out, total);
        int idx = 0;
        for(int i = 0; i < ArraySize(m_classificationWeights); i++)
            out[idx++] = m_classificationWeights[i];
        for(int i = 0; i < ArraySize(m_classificationBiases); i++)
            out[idx++] = m_classificationBiases[i];
    }

    void AnchorEWC(const double &fisherApprox[])
    {
        double weights[];
        GetWeights(weights);
        m_ewc.Anchor(weights, fisherApprox, ArraySize(fisherApprox));
    }

    bool IsEWCAnchored() const
    {
        return m_ewc.IsAnchored();
    }

    bool SaveHeadState(const string filePath)
    {
        int fh = FileOpen(filePath, FILE_WRITE | FILE_BIN | FILE_COMMON);
        if(fh == INVALID_HANDLE)
            return false;

        FileWriteInteger(fh, TRANSFORMER_HEAD_STATE_MAGIC);
        FileWriteInteger(fh, TRANSFORMER_HEAD_STATE_VERSION);
        FileWriteInteger(fh, m_dModel);
        FileWriteLong(fh, m_adamStep);
        FileWriteDouble(fh, m_totalLoss);
        FileWriteInteger(fh, m_trainingSteps);
        FileWriteInteger(fh, ArraySize(m_classificationWeights));
        for(int i = 0; i < ArraySize(m_classificationWeights); i++)
            FileWriteDouble(fh, m_classificationWeights[i]);
        for(int i = 0; i < ArraySize(m_classificationBiases); i++)
            FileWriteDouble(fh, m_classificationBiases[i]);
        FileWriteInteger(fh, ArraySize(m_patternWeights));
        for(int i = 0; i < ArraySize(m_patternWeights); i++)
            FileWriteDouble(fh, m_patternWeights[i]);
        for(int i = 0; i < ArraySize(m_patternBiases); i++)
            FileWriteDouble(fh, m_patternBiases[i]);
        FileClose(fh);
        return true;
    }

    bool LoadHeadState(const string filePath)
    {
        if(!FileIsExist(filePath, FILE_COMMON))
            return false;

        int fh = FileOpen(filePath, FILE_READ | FILE_BIN | FILE_COMMON);
        if(fh == INVALID_HANDLE)
            return false;

        int magic = FileReadInteger(fh);
        int version = FileReadInteger(fh);
        int dModel = FileReadInteger(fh);
        if(magic != TRANSFORMER_HEAD_STATE_MAGIC || version != TRANSFORMER_HEAD_STATE_VERSION || dModel != m_dModel)
        {
            FileClose(fh);
            return false;
        }

        m_adamStep = FileReadLong(fh);
        m_totalLoss = FileReadDouble(fh);
        m_trainingSteps = FileReadInteger(fh);

        int classWeightCount = FileReadInteger(fh);
        if(classWeightCount != ArraySize(m_classificationWeights))
        {
            FileClose(fh);
            return false;
        }
        for(int i = 0; i < classWeightCount; i++)
            m_classificationWeights[i] = FileReadDouble(fh);
        for(int i = 0; i < ArraySize(m_classificationBiases); i++)
            m_classificationBiases[i] = FileReadDouble(fh);

        int patternWeightCount = FileReadInteger(fh);
        if(patternWeightCount != ArraySize(m_patternWeights))
        {
            FileClose(fh);
            return false;
        }
        for(int i = 0; i < patternWeightCount; i++)
            m_patternWeights[i] = FileReadDouble(fh);
        for(int i = 0; i < ArraySize(m_patternBiases); i++)
            m_patternBiases[i] = FileReadDouble(fh);

        FileClose(fh);
        return true;
    }
};

#endif // __TRANSFORMER_BRAIN_MQH__
