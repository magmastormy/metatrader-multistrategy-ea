//+------------------------------------------------------------------+
//| ModelEvaluator.mqh                                                |
//| Model evaluation and validation utilities                          |
//+------------------------------------------------------------------+
#ifndef MQH_MODEL_EVALUATOR_MQH
#define MQH_MODEL_EVALUATOR_MQH

#include "../Core/AI/AIFeatureVectorBuilder.mqh"
#include "../AIModules/AIConfig.mqh"
#include "../Data/LabelEncoder.mqh"
#include "../Core/TrainingMetrics.mqh"
#include "FeedForwardNN.mqh"

class CModelEvaluator
{
private:
    CFeedForwardNN m_model;
    CLabelEncoder m_labelEncoder;
    CTrainingMetrics m_metrics;
    
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    
public:
    CModelEvaluator() {}
    
    bool LoadModel(const string symbol, const ENUM_TIMEFRAMES timeframe)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        
        if(!m_model.LoadCheckpoint(symbol, timeframe))
        {
            PrintFormat("[MQH-EVAL] Failed to load model for %s %s", symbol, EnumToString(timeframe));
            return false;
        }
        
        PrintFormat("[MQH-EVAL] Model loaded successfully for %s %s", symbol, EnumToString(timeframe));
        return true;
    }
    
    bool Evaluate(const double &features[][], const int &labels[], const int count,
                  const string outputFile = "")
    {
        if(count == 0)
        {
            Print("[MQH-EVAL] No evaluation data provided");
            return false;
        }
        
        double totalLoss = 0.0;
        int correct = 0;
        int confusionMatrix[3][3];
        ArrayInitialize(confusionMatrix, 0);
        
        for(int i = 0; i < count; i++)
        {
            double input[];
            ArrayResize(input, FEATURE_VECTOR_SIZE);
            for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
                input[f] = features[i][f];
            
            int predictedClass;
            double prob = m_model.Predict(input, predictedClass);
            
            int actualClass = m_labelEncoder.EncodeLabel(labels[i]);
            
            double outputs[];
            m_model.GetOutputs(input, outputs);
            double loss = CNeuralCore::CrossEntropyLoss(outputs, 3, actualClass);
            totalLoss += loss;
            
            if(predictedClass == actualClass)
                correct++;
            
            if(predictedClass >= 0 && predictedClass < 3 && actualClass >= 0 && actualClass < 3)
                confusionMatrix[actualClass][predictedClass]++;
        }
        
        m_metrics.UpdateMetrics(confusionMatrix, 3, totalLoss / (double)count, count);
        
        Print("=== Model Evaluation Results ===");
        Print(StringFormat("Total Samples: %d", count));
        Print(StringFormat("Loss: %.6f", totalLoss / (double)count));
        Print(StringFormat("Accuracy: %.4f", m_metrics.GetAccuracy()));
        Print(StringFormat("Precision: %.4f", m_metrics.GetPrecision()));
        Print(StringFormat("Recall: %.4f", m_metrics.GetRecall()));
        Print(StringFormat("F1 Score: %.4f", m_metrics.GetF1Score()));
        m_metrics.PrintConfusionMatrix();
        
        if(outputFile != "")
            m_metrics.SaveMetrics(outputFile);
        
        return true;
    }
    
    void EvaluateWithConfidence(const double &features[][], const int &labels[], const int count)
    {
        double totalWeightedCorrect = 0.0;
        double totalConfidence = 0.0;
        
        for(int i = 0; i < count; i++)
        {
            double input[];
            ArrayResize(input, FEATURE_VECTOR_SIZE);
            for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
                input[f] = features[i][f];
            
            int predictedClass;
            double prob = m_model.Predict(input, predictedClass);
            
            int actualClass = m_labelEncoder.EncodeLabel(labels[i]);
            
            if(predictedClass == actualClass)
                totalWeightedCorrect += prob;
            
            totalConfidence += prob;
        }
        
        double confidenceWeightedAccuracy = totalConfidence > 0 ? totalWeightedCorrect / totalConfidence : 0.0;
        Print(StringFormat("Confidence-Weighted Accuracy: %.4f", confidenceWeightedAccuracy));
    }
    
    void GenerateReport(const string filename)
    {
        int fh = FileOpen(filename, FILE_WRITE | FILE_COMMON);
        if(fh == INVALID_HANDLE)
        {
            PrintFormat("[MQH-EVAL] Failed to open report file: %s", filename);
            return;
        }
        
        FileWriteString(fh, "=== Model Evaluation Report ===\r\n");
        FileWriteString(fh, StringFormat("Generated: %s\r\n", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)));
        FileWriteString(fh, StringFormat("Symbol: %s\r\n", m_symbol));
        FileWriteString(fh, StringFormat("Timeframe: %s\r\n\r\n", EnumToString(m_timeframe)));
        
        FileWriteString(fh, "=== Metrics ===\r\n");
        FileWriteString(fh, StringFormat("Loss: %.6f\r\n", m_metrics.GetLoss()));
        FileWriteString(fh, StringFormat("Accuracy: %.4f\r\n", m_metrics.GetAccuracy()));
        FileWriteString(fh, StringFormat("Precision: %.4f\r\n", m_metrics.GetPrecision()));
        FileWriteString(fh, StringFormat("Recall: %.4f\r\n", m_metrics.GetRecall()));
        FileWriteString(fh, StringFormat("F1 Score: %.4f\r\n", m_metrics.GetF1Score()));
        FileWriteString(fh, StringFormat("Total Samples: %d\r\n\r\n", m_metrics.GetTotalSamples()));
        
        int matrix[3][3];
        m_metrics.GetConfusionMatrix(matrix);
        FileWriteString(fh, "=== Confusion Matrix ===\r\n");
        FileWriteString(fh, "          Predicted\r\n");
        FileWriteString(fh, "          -1   0   +1\r\n");
        FileWriteString(fh, StringFormat("Actual -1: %3d %3d %3d\r\n", matrix[0][0], matrix[0][1], matrix[0][2]));
        FileWriteString(fh, StringFormat("Actual  0: %3d %3d %3d\r\n", matrix[1][0], matrix[1][1], matrix[1][2]));
        FileWriteString(fh, StringFormat("Actual +1: %3d %3d %3d\r\n", matrix[2][0], matrix[2][1], matrix[2][2]));
        
        FileClose(fh);
        PrintFormat("[MQH-EVAL] Report saved to: %s", filename);
    }
    
    CTrainingMetrics& GetMetrics() { return m_metrics; }
    CFeedForwardNN& GetModel() { return m_model; }
};

#endif // __MQH_MODEL_EVALUATOR_MQH__
