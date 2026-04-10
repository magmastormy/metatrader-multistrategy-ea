//+------------------------------------------------------------------+
//| Next-Generation Transformer-Based Strategy Brain                |
//| Implements modern attention mechanisms and multi-timeframe AI   |
//+------------------------------------------------------------------+
#property strict

// TRAINING NOTE:
// Only the lightweight 3 x dModel classification head receives gradient updates.
// The transformer encoder blocks themselves remain fixed at Xavier-initialized
// random weights. This is a linear-probing style setup over random features,
// not full transformer fine-tuning. In this EA, the transformer is primarily a
// compact feature extractor; the simple neural network remains the practical
// online learner for adaptive behavior inside MQL5 constraints.

#ifndef __TRANSFORMER_BRAIN_MQH__
#define __TRANSFORMER_BRAIN_MQH__

#include <Arrays\ArrayObj.mqh>
#include <Math\Stat\Math.mqh>
#include <Files\FileTxt.mqh>
#include "..\\Utilities\\Utilities.mqh"

// Forward declarations
class CMultiHeadAttention;
class CFeedForwardNetwork;
class CLayerNorm;
class CPositionalEncoding;
class CTransformerBlock;

//+------------------------------------------------------------------+
//| Multi-Head Attention Layer                                      |
//+------------------------------------------------------------------+
class CMultiHeadAttention : public CObject {
private:
    int m_dModel;           // Model dimension
    int m_numHeads;         // Number of attention heads
    int m_dK;               // Key/Query dimension per head
    int m_dV;               // Value dimension per head
    
    // Weight matrices (flattened)
    double m_WQ[];
    double m_WK[];
    double m_WV[];
    double m_WO[];
    
    double m_attentionWeights[];
    
    // LCG
    uint m_randomState;
    double GetDeterministicRandom() {
        m_randomState = m_randomState * 1664525 + 1013904223;
        return (double)m_randomState / 4294967296.0;
    }
    
    double SoftMax(double &inputArray[], int offset, int length, int index) {
        double softmaxSum = 0.0;
        double maxValue = -DBL_MAX;
        
        // Find max for numerical stability
        for(int i = 0; i < length; i++) {
            if(inputArray[offset + i] > maxValue) maxValue = inputArray[offset + i];
        }
        
        // Calculate softmax sum
        for(int i = 0; i < length; i++) {
            softmaxSum += MathExp(inputArray[offset + i] - maxValue);
        }
        
        // Avoid division by zero
        if(softmaxSum < 1e-9) softmaxSum = 1e-9;
        
        return MathExp(inputArray[offset + index] - maxValue) / softmaxSum;
    }
    
public:
    CMultiHeadAttention(int dModel = 512, int numHeads = 16, int seed = 12345) {
        m_dModel = dModel;
        m_numHeads = numHeads;
        m_dK = dModel / numHeads;
        m_dV = dModel / numHeads;
        m_randomState = (uint)seed;
        
        // Initialize weight matrices
        int qkvSize = dModel * dModel;
        ArrayResize(m_WQ, qkvSize);
        ArrayResize(m_WK, qkvSize);
        ArrayResize(m_WV, qkvSize);
        ArrayResize(m_WO, qkvSize);
        
        // Xavier initialization (Deterministic)
        double scale = MathSqrt(2.0 / dModel);
        for(int i = 0; i < qkvSize; i++) {
            m_WQ[i] = (GetDeterministicRandom() - 0.5) * scale;
            m_WK[i] = (GetDeterministicRandom() - 0.5) * scale;
            m_WV[i] = (GetDeterministicRandom() - 0.5) * scale;
            m_WO[i] = (GetDeterministicRandom() - 0.5) * scale;
        }
    }
    
    // Scaled Dot-Product Attention
    bool ScaledDotProductAttention(const double &Q[], const double &K[], 
                                   const double &V[], double &output[]) {
        int totalQ = ArraySize(Q);
        int seqLen = totalQ / m_dK;
        if(seqLen <= 0) return false;
        
        ArrayResize(m_attentionWeights, seqLen * seqLen);
        
        // Calculate attention scores: Q * K^T / sqrt(d_k)
        double scale = 1.0 / MathSqrt((double)m_dK);
        
        // Optimized matrix multiplication
        for(int i = 0; i < seqLen; i++) {
            int i_offset = i * m_dK;
            int row_offset = i * seqLen;
            
            for(int j = 0; j < seqLen; j++) {
                int j_offset = j * m_dK;
                double attentionScore = 0.0;
                
                // Vectorized-like loop
                for(int k = 0; k < m_dK; k++) {
                    attentionScore += Q[i_offset + k] * K[j_offset + k];
                }
                m_attentionWeights[row_offset + j] = attentionScore * scale;
            }
        }
        
        // Apply softmax to attention scores row by row
        double softmaxScores[]; // Temp buffer
        ArrayResize(softmaxScores, seqLen);
        
        for(int i = 0; i < seqLen; i++) {
            int row_offset = i * seqLen;
            
            // Copy row to temp buffer
            for(int j = 0; j < seqLen; j++) {
                softmaxScores[j] = m_attentionWeights[row_offset + j];
            }
            
            // Apply softmax and write back
            double maxValue = -DBL_MAX;
            for(int j = 0; j < seqLen; j++) if(softmaxScores[j] > maxValue) maxValue = softmaxScores[j];
            
            double sum = 0.0;
            for(int j = 0; j < seqLen; j++) {
                softmaxScores[j] = MathExp(softmaxScores[j] - maxValue);
                sum += softmaxScores[j];
            }
            if(sum < 1e-9) sum = 1e-9;
            
            for(int j = 0; j < seqLen; j++) {
                m_attentionWeights[row_offset + j] = softmaxScores[j] / sum;
            }
        }
        
        // Apply attention to values: Attention * V
        ArrayResize(output, seqLen * m_dV);
        
        for(int i = 0; i < seqLen; i++) {
            int row_offset = i * seqLen;
            int out_offset = i * m_dV;
            
            for(int j = 0; j < m_dV; j++) {
                double sum = 0.0;
                for(int k = 0; k < seqLen; k++) {
                    sum += m_attentionWeights[row_offset + k] * V[k * m_dV + j];
                }
                output[out_offset + j] = sum;
            }
        }
        
        return true;
    }
    
    // Multi-head attention forward pass
    bool Forward(const double &inputData[], double &output[]) {
        int totalInput = ArraySize(inputData);
        if(m_dModel == 0) return false;
        int seqLen = totalInput / m_dModel;
        if(seqLen == 0) return false;
        
        // Transform input to Q, K, V
        double Q[], K[], V[];
        ArrayResize(Q, seqLen * m_dModel);
        ArrayResize(K, seqLen * m_dModel);
        ArrayResize(V, seqLen * m_dModel);
        
        // Proper matrix multiplication for linear transformations
        // Q = inputData * WQ^T, K = inputData * WK^T, V = inputData * WV^T
        // where inputData is [seqLen x dModel] and weights are [dModel x dModel]
        
        for(int i = 0; i < seqLen; i++) {
            for(int j = 0; j < m_dModel; j++) {
                double qSum = 0.0, kSum = 0.0, vSum = 0.0;
                
                // Matrix multiplication: row i of input * column j of weight matrix
                for(int k = 0; k < m_dModel; k++) {
                    int inputIdx = i * m_dModel + k;
                    int weightIdx = k * m_dModel + j;
                    
                    qSum += inputData[inputIdx] * m_WQ[weightIdx];
                    kSum += inputData[inputIdx] * m_WK[weightIdx];
                    vSum += inputData[inputIdx] * m_WV[weightIdx];
                }
                
                Q[i * m_dModel + j] = qSum;
                K[i * m_dModel + j] = kSum;
                V[i * m_dModel + j] = vSum;
            }
        }
        
        // Apply scaled dot-product attention
        double attentionOutput[];
        if(!ScaledDotProductAttention(Q, K, V, attentionOutput)) {
            return false;
        }
        
        // Output projection with proper matrix multiplication
        // output = attentionOutput * WO^T
        ArrayResize(output, seqLen * m_dModel);
        
        for(int i = 0; i < seqLen; i++) {
            for(int j = 0; j < m_dModel; j++) {
                double sum = 0.0;
                
                // Matrix multiplication: row i of attention * column j of WO
                for(int k = 0; k < m_dModel; k++) {
                    int attnIdx = i * m_dModel + k;
                    int weightIdx = k * m_dModel + j;
                    
                    sum += attentionOutput[attnIdx] * m_WO[weightIdx];
                }
                
                output[i * m_dModel + j] = sum;
            }
        }
        
        return true;
    }
    
    void GetAttentionWeights(double &weights[]) {
        ArrayCopy(weights, m_attentionWeights);
    }
};

//+------------------------------------------------------------------+
//| Positional Encoding for Time Series                             |
//+------------------------------------------------------------------+
class CPositionalEncoding : public CObject {
private:
    double m_encodings[];
    int m_maxSeqLen;
    int m_dModel;
    
public:
    CPositionalEncoding(int maxSeqLen = 512, int dModel = 256) {
        m_maxSeqLen = maxSeqLen;
        m_dModel = dModel;
        ArrayResize(m_encodings, maxSeqLen * dModel);
        
        // Generate sinusoidal positional encodings
        for(int pos = 0; pos < maxSeqLen; pos++) {
            for(int i = 0; i < dModel; i++) {
                double angle = pos / MathPow(10000.0, (2.0 * (i / 2)) / dModel);
                if(i % 2 == 0) {
                    m_encodings[pos * dModel + i] = MathSin(angle);
                } else {
                    m_encodings[pos * dModel + i] = MathCos(angle);
                }
            }
        }
    }
    
    bool AddPositionalEncoding(double &inputSeq[], int seqLen) {
        if(seqLen > m_maxSeqLen || ArraySize(inputSeq) != seqLen * m_dModel) {
            return false;
        }
        
        // Add positional encoding to input sequence
        int total = seqLen * m_dModel;
        int encTotal = ArraySize(m_encodings);
        
        for(int i = 0; i < total; i++) {
            inputSeq[i] += m_encodings[i % encTotal];
        }
        
        return true;
    }
};

//+------------------------------------------------------------------+
//| Layer Normalization                                             |
//+------------------------------------------------------------------+
class CLayerNorm : public CObject {
private:
    double m_gamma[];
    double m_beta[];
    int m_dModel;
    double m_epsilon;
    
public:
    CLayerNorm(int dModel = 256, double epsilon = 1e-6) {
        m_dModel = dModel;
        m_epsilon = epsilon;
        ArrayResize(m_gamma, dModel);
        ArrayResize(m_beta, dModel);
        
        // Initialize gamma to 1 and beta to 0
        for(int i = 0; i < dModel; i++) {
            m_gamma[i] = 1.0;
            m_beta[i] = 0.0;
        }
    }
    
    bool Forward(const double &inputData[], double &output[]) {
        if(ArraySize(inputData) != m_dModel) {
             // If input is larger (sequence), normalize each vector in sequence
             if(ArraySize(inputData) % m_dModel == 0) {
                 int seqLen = ArraySize(inputData) / m_dModel;
                 ArrayResize(output, ArraySize(inputData));
                 
                 double tempIn[], tempOut[];
                 ArrayResize(tempIn, m_dModel);
                 
                 for(int i=0; i<seqLen; i++) {
                     ArrayCopy(tempIn, inputData, 0, i*m_dModel, m_dModel);
                     if(!ForwardSingle(tempIn, tempOut)) return false;
                     ArrayCopy(output, tempOut, i*m_dModel, 0, m_dModel);
                 }
                 return true;
             }
             return false;
        }
        return ForwardSingle(inputData, output);
    }
    
    bool ForwardSingle(const double &inputData[], double &output[]) {
        // Calculate mean
        double mean = 0.0;
        for(int i = 0; i < m_dModel; i++) {
            mean += inputData[i];
        }
        mean /= m_dModel;
        
        // Calculate variance
        double variance = 0.0;
        for(int i = 0; i < m_dModel; i++) {
            double diff = inputData[i] - mean;
            variance += diff * diff;
        }
        variance /= m_dModel;
        
        // Normalize
        ArrayResize(output, m_dModel);
        double denom = MathSqrt(variance + m_epsilon);
        
        for(int i = 0; i < m_dModel; i++) {
            double normalized = (inputData[i] - mean) / denom;
            output[i] = normalized * m_gamma[i] + m_beta[i];
        }
        
        return true;
    }
};

//+------------------------------------------------------------------+
//| Feed-Forward Network                                            |
//+------------------------------------------------------------------+
class CFeedForwardNetwork : public CObject {
private:
    int m_dModel;
    int m_dFF;
    double m_W1[];
    double m_W2[];
    double m_B1[];
    double m_B2[];

    // LCG
    uint m_randomState;
    double GetDeterministicRandom() {
        m_randomState = m_randomState * 1664525 + 1013904223;
        return (double)m_randomState / 4294967296.0;
    }
    
    double ReLU(double x) {
        return MathMax(0.0, x);
    }
    
public:
    CFeedForwardNetwork(int dModel = 256, int dFF = 1024, int seed = 12345) {
        m_dModel = dModel;
        m_dFF = dFF;
        m_randomState = (uint)seed;
        
        // Initialize weight matrices and bias vectors
        ArrayResize(m_W1, dModel * dFF);
        ArrayResize(m_W2, dFF * dModel);
        ArrayResize(m_B1, dFF);
        ArrayResize(m_B2, dModel);
        
        // Xavier initialization
        double scale1 = MathSqrt(2.0 / dModel);
        double scale2 = MathSqrt(2.0 / dFF);
        
        for(int i = 0; i < dModel * dFF; i++) {
            m_W1[i] = (GetDeterministicRandom() - 0.5) * scale1;
        }
        
        for(int i = 0; i < dFF * dModel; i++) {
            m_W2[i] = (GetDeterministicRandom() - 0.5) * scale2;
        }
        
        // Initialize biases to zero
        ArrayInitialize(m_B1, 0.0);
        ArrayInitialize(m_B2, 0.0);
    }
    
    bool Forward(const double &inputData[], double &output[]) {
        // Handle sequence input
        int total = ArraySize(inputData);
        if(total % m_dModel != 0) return false;
        
        int seqLen = total / m_dModel;
        ArrayResize(output, total);
        
        // Temp buffers
        double hidden[];
        ArrayResize(hidden, m_dFF);
        
        for(int s = 0; s < seqLen; s++) {
            int inOffset = s * m_dModel;
            int outOffset = s * m_dModel;
            
            // First linear transformation + ReLU
            for(int i = 0; i < m_dFF; i++) {
                double sum = m_B1[i];
                for(int j = 0; j < m_dModel; j++) {
                    sum += inputData[inOffset + j] * m_W1[j * m_dFF + i];
                }
                hidden[i] = ReLU(sum);
            }
            
            // Second linear transformation
            for(int i = 0; i < m_dModel; i++) {
                double sum = m_B2[i];
                for(int j = 0; j < m_dFF; j++) {
                    sum += hidden[j] * m_W2[j * m_dModel + i];
                }
                output[outOffset + i] = sum;
            }
        }
        
        return true;
    }
};

//+------------------------------------------------------------------+
//| Transformer Block                                               |
//+------------------------------------------------------------------+
class CTransformerBlock : public CObject {
private:
    CMultiHeadAttention *m_attention;
    CFeedForwardNetwork *m_feedForward;
    CLayerNorm *m_layerNorm1;
    CLayerNorm *m_layerNorm2;
    double m_residual[];
    
public:
    CTransformerBlock(int dModel = 256, int numHeads = 8, int dFF = 1024, int seed = 0) {
        m_attention = new CMultiHeadAttention(dModel, numHeads, seed);
        m_feedForward = new CFeedForwardNetwork(dModel, dFF, seed + 1);
        m_layerNorm1 = new CLayerNorm(dModel);
        m_layerNorm2 = new CLayerNorm(dModel);
    }
    
    ~CTransformerBlock() {
        if(CheckPointer(m_attention) == POINTER_DYNAMIC) delete m_attention;
        if(CheckPointer(m_feedForward) == POINTER_DYNAMIC) delete m_feedForward;
        if(CheckPointer(m_layerNorm1) == POINTER_DYNAMIC) delete m_layerNorm1;
        if(CheckPointer(m_layerNorm2) == POINTER_DYNAMIC) delete m_layerNorm2;
    }
    
    bool Forward(const double &inputData[], double &output[]) {
        if(!m_attention || !m_feedForward || !m_layerNorm1 || !m_layerNorm2) return false;
        
        // Multi-head attention
        double attentionOutput[];
        if(!m_attention.Forward(inputData, attentionOutput)) return false;
        
        // Add residual connection
        int total = ArraySize(inputData);
        if(ArraySize(attentionOutput) != total) return false;
        
        for(int i = 0; i < total; i++) {
            attentionOutput[i] += inputData[i];
        }
        
        // Layer normalization 1
        double norm1Output[];
        if(!m_layerNorm1.Forward(attentionOutput, norm1Output)) return false;
        
        // Feed-forward network
        double ffOutput[];
        if(!m_feedForward.Forward(norm1Output, ffOutput)) return false;
        
        // Add residual connection
        if(ArraySize(ffOutput) != ArraySize(norm1Output)) return false;
        
        for(int i = 0; i < ArraySize(norm1Output); i++) {
            ffOutput[i] += norm1Output[i];
        }
        
        // Final layer normalization
        if(!m_layerNorm2.Forward(ffOutput, output)) return false;
        
        return true;
    }
    
    bool GetAttentionWeights(double &weights[]) {
        if(!m_attention) return false;
        m_attention.GetAttentionWeights(weights);
        return true;
    }
};

//+------------------------------------------------------------------+
//| Complete Transformer Brain                                      |
//+------------------------------------------------------------------+
class CTransformerBrain : public CObject {
private:
    CArrayObj m_transformerBlocks;
    CPositionalEncoding *m_positionalEncoding;
    double m_attentionWeights[];
    double m_classificationWeights[];     // 3 x dModel classification head
    double m_classificationBiases[];      // 3-class bias
    double m_classificationBiasVelocity[];
    
    // Training parameters
    double m_learningRate;
    int m_trainingSteps;
    double m_totalLoss;
    double m_momentum;
    double m_velocity[];
    uint m_trainingRandomState;
    
    // Model parameters
    int m_dModel;
    int m_numHeads;
    int m_numLayers;
    int m_dFF;
    int m_maxSeqLen;

    double GetTrainingRandom()
    {
        m_trainingRandomState = m_trainingRandomState * 1664525 + 1013904223;
        return (double)m_trainingRandomState / 4294967296.0;
    }

    void InitializeClassificationHead()
    {
        int weightCount = 3 * m_dModel;
        ArrayResize(m_classificationWeights, weightCount);
        ArrayResize(m_classificationBiases, 3);
        ArrayResize(m_velocity, weightCount);
        ArrayResize(m_classificationBiasVelocity, 3);

        ArrayInitialize(m_velocity, 0.0);
        ArrayInitialize(m_classificationBiasVelocity, 0.0);

        double scale = MathSqrt(2.0 / (m_dModel + 3.0));
        for(int i = 0; i < weightCount; i++)
            m_classificationWeights[i] = (GetTrainingRandom() - 0.5) * 2.0 * scale;

        ArrayInitialize(m_classificationBiases, 0.0);
    }

    bool ComputeClassProbabilities(const double &features[], double &probabilities[])
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

    void UpdateClassificationHead(const double &features[], const double &probabilities[], const int targetClass)
    {
        if(ArraySize(features) != m_dModel || ArraySize(probabilities) != 3)
            return;

        for(int c = 0; c < 3; c++)
        {
            double target = (c == targetClass) ? 1.0 : 0.0;
            double error = probabilities[c] - target;
            int rowOffset = c * m_dModel;

            for(int i = 0; i < m_dModel; i++)
            {
                int idx = rowOffset + i;
                double grad = error * features[i];
                m_velocity[idx] = m_momentum * m_velocity[idx] + (1.0 - m_momentum) * grad;
                m_classificationWeights[idx] -= m_learningRate * m_velocity[idx];
            }

            m_classificationBiasVelocity[c] =
                m_momentum * m_classificationBiasVelocity[c] + (1.0 - m_momentum) * error;
            m_classificationBiases[c] -= m_learningRate * m_classificationBiasVelocity[c];
        }
    }
    
public:
    CTransformerBrain(int dModel = 256, int numHeads = 8, int numLayers = 6,
                      int dFF = 1024, int maxSeqLen = 512, double learningRate = 0.001) {
        m_dModel = dModel;
        m_numHeads = numHeads;
        m_numLayers = numLayers;
        m_dFF = dFF;
        m_maxSeqLen = maxSeqLen;
        m_learningRate = learningRate;
        m_trainingSteps = 0;
        m_totalLoss = 0.0;
        m_momentum = 0.9;
        m_trainingRandomState = 20240215;
        
        // Initialize Positional Encoding
        m_positionalEncoding = new CPositionalEncoding(maxSeqLen, dModel);
        
        // Create Transformer Blocks
        m_transformerBlocks.Clear();
        for(int i = 0; i < numLayers; i++) {
            CTransformerBlock *block = new CTransformerBlock(dModel, numHeads, dFF, 42 + i * 10);
            m_transformerBlocks.Add(block);
        }

        InitializeClassificationHead();
        
        PrintFormat("[TRANSFORMER] Initialized with %d layers, dModel=%d, heads=%d", numLayers, dModel, numHeads);
    }
    
    // Safety check: Has the model seen enough data/steps to be reliable?
    bool IsWarmedUp(int threshold = 100) const { return m_trainingSteps >= threshold; }
    
    ~CTransformerBrain() {
        if(CheckPointer(m_positionalEncoding) == POINTER_DYNAMIC) delete m_positionalEncoding;
        m_transformerBlocks.Clear(); // Deletes elements because CArrayObj owns them by default
    }

    int GetModelDimension() const { return m_dModel; }
    int GetMaxSequenceLength() const { return m_maxSeqLen; }

    // Forward pass through the entire transformer
    // Returns encoded features (size m_dModel, not 3-class predictions)
    bool Forward(const double &inputFeatures[], const int actualSeqLen, double &output[]) {
        int totalFeatures = ArraySize(inputFeatures);
        if(totalFeatures <= 0 || totalFeatures > m_maxSeqLen * m_dModel)
            return false;
        if(m_dModel <= 0 || (totalFeatures % m_dModel) != 0)
            return false;

        int derivedSeqLen = totalFeatures / m_dModel;
        int seqLen = MathMin(MathMax(1, actualSeqLen), MathMin(m_maxSeqLen, derivedSeqLen));
        int usableFeatures = seqLen * m_dModel;
        if(usableFeatures <= 0 || usableFeatures > totalFeatures)
            return false;

        double workingData[];
        ArrayResize(workingData, usableFeatures);
        ArrayCopy(workingData, inputFeatures, 0, 0, usableFeatures);

        // Add positional encoding
        if(!m_positionalEncoding) return false;
        if(!m_positionalEncoding.AddPositionalEncoding(workingData, seqLen)) return false;

        // Pass through transformer blocks
        double currentInput[];
        ArrayCopy(currentInput, workingData);
        double currentOutput[];

        for(int i = 0; i < m_transformerBlocks.Total(); i++) {
            CTransformerBlock *block = dynamic_cast<CTransformerBlock*>(m_transformerBlocks.At(i));
            if(!block) return false;

            // Forward pass through transformer block
            if(!block.Forward(currentInput, currentOutput)) return false;

            ArrayCopy(currentInput, currentOutput);
        }

        // Global average pooling
        ArrayResize(output, m_dModel);
        for(int i = 0; i < m_dModel; i++) {
            double sum = 0.0;
            for(int j = 0; j < seqLen; j++) {
                sum += currentOutput[j * m_dModel + i];
            }
            output[i] = sum / seqLen;
        }

        return true;
    }

    bool Forward(const double &inputFeatures[], double &output[]) {
        if(m_dModel <= 0)
            return false;
        int totalFeatures = ArraySize(inputFeatures);
        if(totalFeatures <= 0 || (totalFeatures % m_dModel) != 0)
            return false;
        return Forward(inputFeatures, totalFeatures / m_dModel, output);
    }

    bool GetEncodedFeatures(const double &inputFeatures[], const int actualSeqLen, double &features[])
    {
        return Forward(inputFeatures, actualSeqLen, features);
    }

    // FIX: New method to get 3-class predictions (NONE, BUY, SELL)
    // This applies the classification head to encoded features
    bool GetPredictions(const double &inputFeatures[], double &predictions[]) {
        if(ArraySize(inputFeatures) > m_maxSeqLen * m_dModel) return false;
        return GetPredictions(inputFeatures, ArraySize(inputFeatures) / MathMax(1, m_dModel), predictions);
    }

    bool GetPredictions(const double &inputFeatures[], const int actualSeqLen, double &predictions[]) {
        if(ArraySize(inputFeatures) > m_maxSeqLen * m_dModel) return false;

        // Get encoded features from transformer
        double encodedFeatures[];
        if(!Forward(inputFeatures, actualSeqLen, encodedFeatures)) return false;

        // Apply classification head to get 3-class probabilities
        if(!ComputeClassProbabilities(encodedFeatures, predictions)) return false;

        return true;
    }
    
    // Calculate cross-entropy loss
    double CalculateLoss(const double &predictions[], int targetClass) {
        if(ArraySize(predictions) != 3) return 0.0; // Buy, Sell, Hold
        
        double targetProb = 0.0;
        if(targetClass >= 0 && targetClass < 3) targetProb = predictions[targetClass];
        
        double epsilon = 1e-15;
        return -MathLog(MathMax(targetProb, epsilon));
    }
    
    // Training step with gradient-based weight updates
    bool TrainStep(const double &inputFeatures[], int targetClass, double &loss) {
        if(targetClass < 0 || targetClass > 2)
            return false;

        // Encode input sequence with transformer stack.
        double encodedFeatures[];
        int actualSeqLen = ArraySize(inputFeatures) / MathMax(1, m_dModel);
        if(!Forward(inputFeatures, actualSeqLen, encodedFeatures))
            return false;

        if(ArraySize(encodedFeatures) != m_dModel)
            return false;

        // Predict class probabilities with a trained classification head.
        double probabilities[];
        if(!ComputeClassProbabilities(encodedFeatures, probabilities))
            return false;

        // Cross-entropy objective.
        loss = CalculateLoss(probabilities, targetClass);
        if(!MathIsValidNumber(loss))
            return false;

        // Update classification head weights with momentum SGD.
        UpdateClassificationHead(encodedFeatures, probabilities, targetClass);

        m_totalLoss += loss;
        m_trainingSteps++;
        return true;
    }
    
    // Get model information
    string GetModelInfo() {
        string info = StringFormat("TransformerBrain: dModel=%d, heads=%d, layers=%d, dFF=%d, seqLen=%d\n",
                                   m_dModel, m_numHeads, m_numLayers, m_dFF, m_maxSeqLen);
        info += StringFormat("Training: steps=%d, avgLoss=%.6f, learningRate=%.6f\n",
                             m_trainingSteps, (m_trainingSteps > 0) ? m_totalLoss / m_trainingSteps : 0.0, m_learningRate);
        return info;
    }
    
    // Get attention weights for analysis
    bool GetAttentionWeights(double &outWeights[]) {
        if(m_transformerBlocks.Total() == 0) return false;
        
        CTransformerBlock *firstBlock = dynamic_cast<CTransformerBlock*>(m_transformerBlocks.At(0));
        if(!firstBlock) return false;
        
        return firstBlock.GetAttentionWeights(outWeights);
    }
    
    // Reset training state
    void ResetTraining() {
        m_trainingSteps = 0;
        m_totalLoss = 0.0;
        if(ArraySize(m_velocity) > 0)
            ArrayInitialize(m_velocity, 0.0);
        if(ArraySize(m_classificationBiasVelocity) > 0)
            ArrayInitialize(m_classificationBiasVelocity, 0.0);
    }
    
};

#endif // __TRANSFORMER_BRAIN_MQH__
