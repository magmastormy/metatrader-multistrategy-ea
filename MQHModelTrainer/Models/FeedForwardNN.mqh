//+------------------------------------------------------------------+
//| FeedForwardNN.mqh                                                |
//| Feed-forward neural network wrapper for training                  |
//| Matches EA's NeuralNetworkStrategy 4-layer architecture           |
//+------------------------------------------------------------------+
#ifndef __MQH_FEED_FORWARD_NN_MQH__
#define __MQH_FEED_FORWARD_NN_MQH__

#include "../AIModules/CNeuralCore.mqh"
#include "../AIModules/AIConfig.mqh"

class CFeedForwardNN
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
    
    double adamM1[FEATURE_VECTOR_SIZE][32];
    double adamM2[32][16];
    double adamM3[16][8];
    double adamM4[8][3];
    double adamV1[FEATURE_VECTOR_SIZE][32];
    double adamV2[32][16];
    double adamV3[16][8];
    double adamV4[8][3];
    double adamB1[32];
    double adamB2[16];
    double adamB3[8];
    double adamB4[3];
    double adamVB1[32];
    double adamVB2[16];
    double adamVB3[8];
    double adamVB4[3];
    long m_adamStep;
    
    double m_learningRate;
    double m_l2Regularization;
    double m_temperature;
    bool m_initialized;
    
    void InitializeWeights()
    {
        double scale1 = MathSqrt(2.0 / ((double)(FEATURE_VECTOR_SIZE + 32)));
        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
            for(int j = 0; j < 32; j++)
                W1[i][j] = (MathRand() / 32767.0 - 0.5) * 2.0 * scale1;
        
        double scale2 = MathSqrt(2.0 / ((double)(32 + 16)));
        for(int i = 0; i < 32; i++)
            for(int j = 0; j < 16; j++)
                W2[i][j] = (MathRand() / 32767.0 - 0.5) * 2.0 * scale2;
        
        double scale3 = MathSqrt(2.0 / ((double)(16 + 8)));
        for(int i = 0; i < 16; i++)
            for(int j = 0; j < 8; j++)
                W3[i][j] = (MathRand() / 32767.0 - 0.5) * 2.0 * scale3;
        
        double scale4 = MathSqrt(2.0 / ((double)(8 + 3)));
        for(int i = 0; i < 8; i++)
            for(int j = 0; j < 3; j++)
                W4[i][j] = (MathRand() / 32767.0 - 0.5) * 2.0 * scale4;
        
        ArrayInitialize(B1, 0.0);
        ArrayInitialize(B2, 0.0);
        ArrayInitialize(B3, 0.0);
        ArrayInitialize(B4, 0.0);
        
        ArrayInitialize(adamM1, 0.0);
        ArrayInitialize(adamM2, 0.0);
        ArrayInitialize(adamM3, 0.0);
        ArrayInitialize(adamM4, 0.0);
        ArrayInitialize(adamV1, 0.0);
        ArrayInitialize(adamV2, 0.0);
        ArrayInitialize(adamV3, 0.0);
        ArrayInitialize(adamV4, 0.0);
        ArrayInitialize(adamB1, 0.0);
        ArrayInitialize(adamB2, 0.0);
        ArrayInitialize(adamB3, 0.0);
        ArrayInitialize(adamB4, 0.0);
        ArrayInitialize(adamVB1, 0.0);
        ArrayInitialize(adamVB2, 0.0);
        ArrayInitialize(adamVB3, 0.0);
        ArrayInitialize(adamVB4, 0.0);
        m_adamStep = 0;
    }
    
    void ReLU(double &values[], const int size)
    {
        for(int i = 0; i < size; i++)
            values[i] = MathMax(0.0, values[i]);
    }
    
    void ForwardPass(const double &inputs[], double &hidden1[], double &hidden2[],
                     double &hidden3[], double &output[])
    {
        ArrayResize(hidden1, 32);
        ArrayResize(hidden2, 16);
        ArrayResize(hidden3, 8);
        ArrayResize(output, 3);
        
        for(int j = 0; j < 32; j++)
        {
            hidden1[j] = B1[j];
            for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
                hidden1[j] += inputs[i] * W1[i][j];
        }
        ReLU(hidden1, 32);
        
        for(int j = 0; j < 16; j++)
        {
            hidden2[j] = B2[j];
            for(int i = 0; i < 32; i++)
                hidden2[j] += hidden1[i] * W2[i][j];
        }
        ReLU(hidden2, 16);
        
        for(int j = 0; j < 8; j++)
        {
            hidden3[j] = B3[j];
            for(int i = 0; i < 16; i++)
                hidden3[j] += hidden2[i] * W3[i][j];
        }
        ReLU(hidden3, 8);
        
        for(int j = 0; j < 3; j++)
        {
            output[j] = B4[j];
            for(int i = 0; i < 8; i++)
                output[j] += hidden3[i] * W4[i][j];
        }
        
        CNeuralCore::Softmax(output, 3, m_temperature);
    }
    
    void UpdateAdam(double &gradW[][], double &gradB[], double &adamM[][],
                    double &adamV[][], double &adamMB[], double &adamVB[],
                    const int rows, const int cols, const int biasSize)
    {
        m_adamStep++;
        double beta1 = 0.9;
        double beta2 = 0.999;
        double eps = 1e-8;
        
        for(int i = 0; i < rows; i++)
            for(int j = 0; j < cols; j++)
            {
                adamM[i][j] = beta1 * adamM[i][j] + (1.0 - beta1) * gradW[i][j];
                adamV[i][j] = beta2 * adamV[i][j] + (1.0 - beta2) * gradW[i][j] * gradW[i][j];
                
                double mHat = adamM[i][j] / (1.0 - MathPow(beta1, (double)m_adamStep));
                double vHat = adamV[i][j] / (1.0 - MathPow(beta2, (double)m_adamStep));
                
                gradW[i][j] = mHat / (MathSqrt(vHat) + eps);
            }
        
        for(int j = 0; j < biasSize; j++)
        {
            adamMB[j] = beta1 * adamMB[j] + (1.0 - beta1) * gradB[j];
            adamVB[j] = beta2 * adamVB[j] + (1.0 - beta2) * gradB[j] * gradB[j];
            
            double mHat = adamMB[j] / (1.0 - MathPow(beta1, (double)m_adamStep));
            double vHat = adamVB[j] / (1.0 - MathPow(beta2, (double)m_adamStep));
            
            gradB[j] = mHat / (MathSqrt(vHat) + eps);
        }
    }
    
public:
    CFeedForwardNN() : m_learningRate(0.001), m_l2Regularization(0.0001), m_temperature(1.0), m_initialized(false), m_adamStep(0) {}
    
    bool Initialize(const double learningRate = 0.001, const double l2Reg = 0.0001, const double temp = 1.0)
    {
        m_learningRate = learningRate;
        m_l2Regularization = l2Reg;
        m_temperature = temp;
        InitializeWeights();
        m_initialized = true;
        PrintFormat("[MQH-TRAIN] NN initialized: lr=%.4f, l2=%.5f, temp=%.2f", learningRate, l2Reg, temp);
        return true;
    }
    
    double TrainStep(const double &inputs[], const int targetClass)
    {
        if(!m_initialized) return 1.0;
        
        double hidden1[], hidden2[], hidden3[], output[];
        ForwardPass(inputs, hidden1, hidden2, hidden3, output);
        
        double loss = CNeuralCore::CrossEntropyLoss(output, 3, targetClass);
        
        double gradW1[FEATURE_VECTOR_SIZE][32];
        double gradW2[32][16];
        double gradW3[16][8];
        double gradW4[8][3];
        double gradB1[32];
        double gradB2[16];
        double gradB3[8];
        double gradB4[3];
        
        CNeuralCore::ComputeGradients(inputs, FEATURE_VECTOR_SIZE,
                                      hidden1, 32, hidden2, 16, hidden3, 8,
                                      output, 3, targetClass,
                                      gradW1, gradB1, gradW2, gradB2,
                                      gradW3, gradB3, gradW4, gradB4);
        
        CNeuralCore::ClipGradientsFull(gradW1, gradB1, gradW2, gradB2, gradW3, gradB3, gradW4, gradB4);
        
        UpdateAdam(gradW1, gradB1, adamM1, adamV1, adamB1, adamVB1, FEATURE_VECTOR_SIZE, 32, 32);
        UpdateAdam(gradW2, gradB2, adamM2, adamV2, adamB2, adamVB2, 32, 16, 16);
        UpdateAdam(gradW3, gradB3, adamM3, adamV3, adamB3, adamVB3, 16, 8, 8);
        UpdateAdam(gradW4, gradB4, adamM4, adamV4, adamB4, adamVB4, 8, 3, 3);
        
        double lr = m_learningRate;
        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
            for(int j = 0; j < 32; j++)
                W1[i][j] -= lr * (gradW1[i][j] + m_l2Regularization * W1[i][j]);
        for(int j = 0; j < 32; j++) B1[j] -= lr * gradB1[j];
        
        for(int i = 0; i < 32; i++)
            for(int j = 0; j < 16; j++)
                W2[i][j] -= lr * (gradW2[i][j] + m_l2Regularization * W2[i][j]);
        for(int j = 0; j < 16; j++) B2[j] -= lr * gradB2[j];
        
        for(int i = 0; i < 16; i++)
            for(int j = 0; j < 8; j++)
                W3[i][j] -= lr * (gradW3[i][j] + m_l2Regularization * W3[i][j]);
        for(int j = 0; j < 8; j++) B3[j] -= lr * gradB3[j];
        
        for(int i = 0; i < 8; i++)
            for(int j = 0; j < 3; j++)
                W4[i][j] -= lr * (gradW4[i][j] + m_l2Regularization * W4[i][j]);
        for(int j = 0; j < 3; j++) B4[j] -= lr * gradB4[j];
        
        return loss;
    }
    
    double Predict(const double &inputs[], int &predictedClass)
    {
        if(!m_initialized)
        {
            predictedClass = 1;
            return 0.0;
        }
        
        double hidden1[], hidden2[], hidden3[], output[];
        ForwardPass(inputs, hidden1, hidden2, hidden3, output);
        
        predictedClass = 0;
        double maxProb = output[0];
        for(int i = 1; i < 3; i++)
        {
            if(output[i] > maxProb)
            {
                maxProb = output[i];
                predictedClass = i;
            }
        }
        
        return maxProb;
    }
    
    void GetOutputs(const double &inputs[], double &outputs[])
    {
        double hidden1[], hidden2[], hidden3[];
        ArrayResize(outputs, 3);
        ForwardPass(inputs, hidden1, hidden2, hidden3, outputs);
    }
    
    bool SaveCheckpoint(const string symbol, const ENUM_TIMEFRAMES timeframe)
    {
        return true;
    }
    
    bool LoadCheckpoint(const string symbol, const ENUM_TIMEFRAMES timeframe)
    {
        return true;
    }
    
    bool IsInitialized() const { return m_initialized; }
    
    void SetLearningRate(const double lr) { m_learningRate = lr; }
    void SetTemperature(const double temp) { m_temperature = temp; }
    void SetL2Regularization(const double l2) { m_l2Regularization = l2; }
    
    double GetLearningRate() const { return m_learningRate; }
    double GetTemperature() const { return m_temperature; }
};

#endif // __MQH_FEED_FORWARD_NN_MQH__
