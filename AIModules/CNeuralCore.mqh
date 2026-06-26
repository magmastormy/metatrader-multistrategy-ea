//+------------------------------------------------------------------+
//| CNeuralCore.mqh                                                   |
//| Core neural network operations (activations, loss, etc.)          |
//+------------------------------------------------------------------+
#ifndef __NEURAL_CORE_MQH__
#define __NEURAL_CORE_MQH__

#include "CNeuralTrainingDataManager.mqh"

class CNeuralCore
{
public:
    static void Softmax(double &values[], const int size, const double temperature = 1.0)
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
    
    static double CrossEntropyLoss(const double &predictions[], const int size, const int targetClass)
    {
        if(targetClass < 0 || targetClass >= size)
            return 1.0;
        
        double pred = MathMax(1e-15, MathMin(1.0 - 1e-15, predictions[targetClass]));
        return -MathLog(pred);
    }
    
    static void ComputeGradients(const double &inputs[], const int inputSize,
                                  const double &hidden1[], const int h1Size,
                                  const double &hidden2[], const int h2Size,
                                  const double &hidden3[], const int h3Size,
                                  const double &output[], const int outSize,
                                  const int targetClass,
                                  double &gradW1[][], double &gradB1[],
                                  double &gradW2[][], double &gradB2[],
                                  double &gradW3[][], double &gradB3[],
                                  double &gradW4[][], double &gradB4[])
    {
        double gradOutput[];
        ArrayResize(gradOutput, outSize);
        for(int i = 0; i < outSize; i++)
            gradOutput[i] = (i == targetClass) ? output[i] - 1.0 : output[i];
        
        ArrayResize(gradW4, h3Size, outSize);
        ArrayResize(gradB4, outSize);
        for(int i = 0; i < h3Size; i++)
            for(int j = 0; j < outSize; j++)
                gradW4[i][j] = hidden3[i] * gradOutput[j];
        for(int j = 0; j < outSize; j++)
            gradB4[j] = gradOutput[j];
        
        double gradHidden3[];
        ArrayResize(gradHidden3, h3Size);
        for(int i = 0; i < h3Size; i++)
        {
            gradHidden3[i] = 0.0;
            for(int j = 0; j < outSize; j++)
                gradHidden3[i] += gradOutput[j] * gradW4[i][j];
            gradHidden3[i] *= (hidden3[i] > 0.0) ? 1.0 : 0.0;
        }
        
        ArrayResize(gradW3, h2Size, h3Size);
        ArrayResize(gradB3, h3Size);
        for(int i = 0; i < h2Size; i++)
            for(int j = 0; j < h3Size; j++)
                gradW3[i][j] = hidden2[i] * gradHidden3[j];
        for(int j = 0; j < h3Size; j++)
            gradB3[j] = gradHidden3[j];
        
        double gradHidden2[];
        ArrayResize(gradHidden2, h2Size);
        for(int i = 0; i < h2Size; i++)
        {
            gradHidden2[i] = 0.0;
            for(int j = 0; j < h3Size; j++)
                gradHidden2[i] += gradHidden3[j] * gradW3[i][j];
            gradHidden2[i] *= (hidden2[i] > 0.0) ? 1.0 : 0.0;
        }
        
        ArrayResize(gradW2, h1Size, h2Size);
        ArrayResize(gradB2, h2Size);
        for(int i = 0; i < h1Size; i++)
            for(int j = 0; j < h2Size; j++)
                gradW2[i][j] = hidden1[i] * gradHidden2[j];
        for(int j = 0; j < h2Size; j++)
            gradB2[j] = gradHidden2[j];
        
        double gradHidden1[];
        ArrayResize(gradHidden1, h1Size);
        for(int i = 0; i < h1Size; i++)
        {
            gradHidden1[i] = 0.0;
            for(int j = 0; j < h2Size; j++)
                gradHidden1[i] += gradHidden2[j] * gradW2[i][j];
            gradHidden1[i] *= (hidden1[i] > 0.0) ? 1.0 : 0.0;
        }
        
        ArrayResize(gradW1, inputSize, h1Size);
        ArrayResize(gradB1, h1Size);
        for(int i = 0; i < inputSize; i++)
            for(int j = 0; j < h1Size; j++)
                gradW1[i][j] = inputs[i] * gradHidden1[j];
        for(int j = 0; j < h1Size; j++)
            gradB1[j] = gradHidden1[j];
    }
    
    static void ClipGradientsFull(double &gradW1[][], double &gradB1[], 
                                  double &gradW2[][], double &gradB2[],
                                  double &gradW3[][], double &gradB3[],
                                  double &gradW4[][], double &gradB4[],
                                  const double maxNorm = 5.0)
    {
        double norm = 0.0;
        
        for(int i = 0; i < ArrayRange(gradW1, 0); i++)
            for(int j = 0; j < ArrayRange(gradW1, 1); j++)
                norm += gradW1[i][j] * gradW1[i][j];
        for(int j = 0; j < ArraySize(gradB1); j++)
            norm += gradB1[j] * gradB1[j];
        for(int i = 0; i < ArrayRange(gradW2, 0); i++)
            for(int j = 0; j < ArrayRange(gradW2, 1); j++)
                norm += gradW2[i][j] * gradW2[i][j];
        for(int j = 0; j < ArraySize(gradB2); j++)
            norm += gradB2[j] * gradB2[j];
        for(int i = 0; i < ArrayRange(gradW3, 0); i++)
            for(int j = 0; j < ArrayRange(gradW3, 1); j++)
                norm += gradW3[i][j] * gradW3[i][j];
        for(int j = 0; j < ArraySize(gradB3); j++)
            norm += gradB3[j] * gradB3[j];
        for(int i = 0; i < ArrayRange(gradW4, 0); i++)
            for(int j = 0; j < ArrayRange(gradW4, 1); j++)
                norm += gradW4[i][j] * gradW4[i][j];
        for(int j = 0; j < ArraySize(gradB4); j++)
            norm += gradB4[j] * gradB4[j];
        
        norm = MathSqrt(norm);
        if(norm > maxNorm && norm > 1e-12)
        {
            double scale = maxNorm / norm;
            for(int i = 0; i < ArrayRange(gradW1, 0); i++)
                for(int j = 0; j < ArrayRange(gradW1, 1); j++)
                    gradW1[i][j] *= scale;
            for(int j = 0; j < ArraySize(gradB1); j++)
                gradB1[j] *= scale;
            for(int i = 0; i < ArrayRange(gradW2, 0); i++)
                for(int j = 0; j < ArrayRange(gradW2, 1); j++)
                    gradW2[i][j] *= scale;
            for(int j = 0; j < ArraySize(gradB2); j++)
                gradB2[j] *= scale;
            for(int i = 0; i < ArrayRange(gradW3, 0); i++)
                for(int j = 0; j < ArrayRange(gradW3, 1); j++)
                    gradW3[i][j] *= scale;
            for(int j = 0; j < ArraySize(gradB3); j++)
                gradB3[j] *= scale;
            for(int i = 0; i < ArrayRange(gradW4, 0); i++)
                for(int j = 0; j < ArrayRange(gradW4, 1); j++)
                    gradW4[i][j] *= scale;
            for(int j = 0; j < ArraySize(gradB4); j++)
                gradB4[j] *= scale;
        }
    }
};

#endif // __NEURAL_CORE_MQH__
