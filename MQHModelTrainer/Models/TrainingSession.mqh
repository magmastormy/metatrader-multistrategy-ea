//+------------------------------------------------------------------+
//| TrainingSession.mqh                                              |
//| Training session orchestration and management                     |
//+------------------------------------------------------------------+
#ifndef MQH_TRAINING_SESSION_MQH
#define MQH_TRAINING_SESSION_MQH

#include "../../Core/AI/AIFeatureVectorBuilder.mqh"
#include "../../AIModules/AIConfig.mqh"
#include "../Data/LabelEncoder.mqh"
#include "FeedForwardNN.mqh"
#include "../Core/TrainingMetrics.mqh"
#include "../Core/TrainingVisualizer.mqh"

struct STrainingConfig
{
    int epochs;
    int batchSize;
    int earlyStoppingPatience;
    double earlyStoppingMinDelta;
    int logInterval;
    bool enableVisualization;
};

class CTrainingSession
{
private:
    CFeedForwardNN m_model;
    CLabelEncoder m_labelEncoder;
    CTrainingMetrics m_metrics;
    
    double m_trainFeatures[][FEATURE_VECTOR_SIZE];
    int m_trainLabels[];
    int m_trainCount;

    double m_valFeatures[][FEATURE_VECTOR_SIZE];
    int m_valLabels[];
    int m_valCount;
    
    double m_bestValLoss;
    int m_bestEpoch;
    int m_earlyStopCounter;
    int m_earlyStopPatience;
    bool m_earlyStopTriggered;
    
    int m_totalEpochs;
    int m_currentEpoch;
    int m_batchSize;
    
    string m_logFile;
    int m_logHandle;
    
    int m_progressUpdateInterval;
    
public:
    CTrainingSession() : m_bestValLoss(1e10), m_bestEpoch(0), m_earlyStopCounter(0),
                         m_earlyStopPatience(50), m_earlyStopTriggered(false),
                         m_totalEpochs(500), m_currentEpoch(0), m_batchSize(32),
                         m_progressUpdateInterval(10), m_model_ptr(NULL) {}
    
    bool Initialize(const double &trainFeatures[][], const int &trainLabels[], const int trainCount,
                    const double &valFeatures[][], const int &valLabels[], const int valCount,
                    const int epochs = 500, const int batchSize = 32, const int patience = 50)
    {
        m_trainCount = trainCount;
        m_valCount = valCount;
        m_totalEpochs = epochs;
        m_batchSize = batchSize;
        m_earlyStopPatience = patience;
        
        ArrayResize(m_trainFeatures, trainCount, FEATURE_VECTOR_SIZE);
        ArrayResize(m_trainLabels, trainCount);
        ArrayResize(m_valFeatures, valCount, FEATURE_VECTOR_SIZE);
        ArrayResize(m_valLabels, valCount);
        
        for(int i = 0; i < trainCount; i++)
        {
            for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
                m_trainFeatures[i][f] = trainFeatures[i][f];
            m_trainLabels[i] = trainLabels[i];
        }
        
        for(int i = 0; i < valCount; i++)
        {
            for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
                m_valFeatures[i][f] = valFeatures[i][f];
            m_valLabels[i] = valLabels[i];
        }
        
        if(!m_model.Initialize())
            return false;
        
        m_logFile = StringFormat("MQHTrainingLog_%s.txt", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
        m_logHandle = FileOpen(m_logFile, FILE_WRITE | FILE_COMMON);
        if(m_logHandle == INVALID_HANDLE)
            PrintFormat("[MQH-TRAIN] Warning: Failed to open log file: %s", m_logFile);
        
        LogMessage("Training session initialized");
        LogMessage(StringFormat("Train samples: %d | Val samples: %d", trainCount, valCount));
        LogMessage(StringFormat("Epochs: %d | Batch size: %d | Early stop patience: %d", epochs, batchSize, patience));

        return true;
    }

    void SetConfig(const STrainingConfig &config)
    {
        m_totalEpochs = config.epochs;
        m_batchSize = config.batchSize;
        m_earlyStopPatience = config.earlyStoppingPatience;
        m_progressUpdateInterval = config.logInterval;
    }

    void SetVisualizer(CTrainingVisualizer &visualizer)
    {
        // Visualizer integration placeholder - visualizer is used by the calling script
    }

    void LogMessage(const string message)
    {
        string logLine = StringFormat("[%s] %s", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), message);
        Print(logLine);
        if(m_logHandle != INVALID_HANDLE)
            FileWriteString(m_logHandle, logLine + "\r\n");
    }
    
    bool Train()
    {
        for(m_currentEpoch = 1; m_currentEpoch <= m_totalEpochs; m_currentEpoch++)
        {
            double trainLoss = TrainEpoch();
            double valLoss = Evaluate(m_valFeatures, m_valLabels, m_valCount);
            
            bool shouldStop = CheckEarlyStopping(valLoss);
            
            if(m_currentEpoch % m_progressUpdateInterval == 0 || m_currentEpoch == 1)
            {
                LogMessage(StringFormat("Epoch %d/%d | Train Loss: %.6f | Val Loss: %.6f",
                                       m_currentEpoch, m_totalEpochs, trainLoss, valLoss));
                
                double valAcc = m_metrics.GetAccuracy();
                double valF1 = m_metrics.GetF1Score();
                LogMessage(StringFormat("Validation Accuracy: %.4f | F1 Score: %.4f", valAcc, valF1));
            }
            
            if(shouldStop)
            {
                LogMessage(StringFormat("Early stopping triggered at epoch %d", m_currentEpoch));
                break;
            }
        }
        
        Finalize();
        return true;
    }

    bool Train(CFeedForwardNN &model, const double &trainFeatures[][], const int &trainLabels[], const int trainCount,
               const double &valFeatures[][], const int &valLabels[], const int valCount)
    {
        // Store data
        m_trainCount = trainCount;
        m_valCount = valCount;
        m_totalEpochs = m_totalEpochs > 0 ? m_totalEpochs : 500;
        m_batchSize = m_batchSize > 0 ? m_batchSize : 32;

        ArrayResize(m_trainFeatures, trainCount, FEATURE_VECTOR_SIZE);
        ArrayResize(m_trainLabels, trainCount);
        ArrayResize(m_valFeatures, valCount, FEATURE_VECTOR_SIZE);
        ArrayResize(m_valLabels, valCount);

        for(int i = 0; i < trainCount; i++)
        {
            for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
                m_trainFeatures[i][f] = trainFeatures[i][f];
            m_trainLabels[i] = trainLabels[i];
        }
        for(int i = 0; i < valCount; i++)
        {
            for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
                m_valFeatures[i][f] = valFeatures[i][f];
            m_valLabels[i] = valLabels[i];
        }

        m_model_ptr = GetPointer(model);

        for(m_currentEpoch = 1; m_currentEpoch <= m_totalEpochs; m_currentEpoch++)
        {
            double trainLoss = TrainEpochWithModel();
            double valLoss = EvaluateWithModel(valFeatures, valLabels, valCount);

            bool shouldStop = CheckEarlyStopping(valLoss);

            if(m_currentEpoch % m_progressUpdateInterval == 0 || m_currentEpoch == 1)
            {
                LogMessage(StringFormat("Epoch %d/%d | Train Loss: %.6f | Val Loss: %.6f",
                                       m_currentEpoch, m_totalEpochs, trainLoss, valLoss));
                LogMessage(StringFormat("Val Accuracy: %.4f | F1: %.4f", m_metrics.GetAccuracy(), m_metrics.GetF1Score()));
            }

            if(shouldStop)
            {
                LogMessage(StringFormat("Early stopping at epoch %d", m_currentEpoch));
                break;
            }
        }

        Finalize();
        return true;
    }

    double TrainEpoch()
    {
        double totalLoss = 0.0;
        int sampleCount = 0;
        
        int batches = (m_trainCount + m_batchSize - 1) / m_batchSize;
        
        for(int b = 0; b < batches; b++)
        {
            int start = b * m_batchSize;
            int end = MathMin(start + m_batchSize, m_trainCount);
            
            for(int i = start; i < end; i++)
            {
                double features[];
                ArrayResize(features, FEATURE_VECTOR_SIZE);
                for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
                    features[f] = m_trainFeatures[i][f];
                
                int encodedLabel = m_labelEncoder.EncodeLabel(m_trainLabels[i]);
                double loss = m_model.TrainStep(features, encodedLabel);
                
                totalLoss += loss;
                sampleCount++;
            }
        }
        
        return sampleCount > 0 ? totalLoss / (double)sampleCount : 0.0;
    }
    
    double Evaluate(const double &features[][], const int &labels[], const int count)
    {
        double totalLoss = 0.0;
        int correct = 0;
        int confusionMatrix[3][3];
        ArrayInitialize(confusionMatrix, 0);
        
        for(int i = 0; i < count; i++)
        {
            double inputVec[];
            ArrayResize(inputVec, FEATURE_VECTOR_SIZE);
            for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
                inputVec[f] = features[i][f];

            int predictedClass;
            double prob = m_model.Predict(inputVec, predictedClass);

            int actualClass = m_labelEncoder.EncodeLabel(labels[i]);

            double outputs[];
            m_model.GetOutputs(inputVec, outputs);
            double loss = CNeuralCore::CrossEntropyLoss(outputs, 3, actualClass);
            totalLoss += loss;

            if(predictedClass == actualClass)
                correct++;

            if(predictedClass >= 0 && predictedClass < 3 && actualClass >= 0 && actualClass < 3)
                confusionMatrix[actualClass][predictedClass]++;
        }
        
        m_metrics.UpdateMetrics(confusionMatrix, 3, totalLoss / (double)count, count);
        
        return totalLoss / (double)count;
    }
    
    bool CheckEarlyStopping(const double valLoss)
    {
        if(valLoss < m_bestValLoss - 1e-6)
        {
            m_bestValLoss = valLoss;
            m_bestEpoch = m_currentEpoch;
            m_earlyStopCounter = 0;
            return false;
        }
        
        m_earlyStopCounter++;
        
        if(m_earlyStopCounter >= m_earlyStopPatience)
        {
            m_earlyStopTriggered = true;
            return true;
        }
        
        return false;
    }
    
    void Finalize()
    {
        LogMessage("Training completed");
        LogMessage(StringFormat("Best epoch: %d | Best val loss: %.6f", m_bestEpoch, m_bestValLoss));
        
        double testLoss = Evaluate(m_valFeatures, m_valLabels, m_valCount);
        LogMessage(StringFormat("Final validation: Loss=%.6f | Accuracy=%.4f | F1=%.4f",
                               testLoss, m_metrics.GetAccuracy(), m_metrics.GetF1Score()));
        
        m_metrics.PrintConfusionMatrix();
        
        if(m_logHandle != INVALID_HANDLE)
            FileClose(m_logHandle);
    }
    
    CFeedForwardNN  GetModel() { return m_model; }
    CTrainingMetrics GetMetrics() { return m_metrics; }
    CTrainingMetrics GetTrainMetrics() const { return m_metrics; }
    CTrainingMetrics GetValMetrics() const { return m_metrics; }
    
    void SetLearningRate(const double lr) { m_model.SetLearningRate(lr); }
    void SetTemperature(const double temp) { m_model.SetTemperature(temp); }
    void SetL2Regularization(const double l2) { m_model.SetL2Regularization(l2); }
    
    int GetCurrentEpoch() const { return m_currentEpoch; }
    int GetBestEpoch() const { return m_bestEpoch; }
    double GetBestValLoss() const { return m_bestValLoss; }
    bool EarlyStopTriggered() const { return m_earlyStopTriggered; }

private:
    CFeedForwardNN *m_model_ptr;

    double TrainEpochWithModel()
    {
        double totalLoss = 0.0;
        int sampleCount = 0;
        int batches = (m_trainCount + m_batchSize - 1) / m_batchSize;

        for(int b = 0; b < batches; b++)
        {
            int start = b * m_batchSize;
            int end = MathMin(start + m_batchSize, m_trainCount);
            for(int i = start; i < end; i++)
            {
                double features[];
                ArrayResize(features, FEATURE_VECTOR_SIZE);
                for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
                    features[f] = m_trainFeatures[i][f];
                int encodedLabel = m_labelEncoder.EncodeLabel(m_trainLabels[i]);
                double loss = m_model_ptr.TrainStep(features, encodedLabel);
                totalLoss += loss;
                sampleCount++;
            }
        }
        return sampleCount > 0 ? totalLoss / (double)sampleCount : 0.0;
    }

    double EvaluateWithModel(const double &features[][], const int &labels[], const int count)
    {
        double totalLoss = 0.0;
        int correct = 0;
        int confusionMatrix[3][3];
        ArrayInitialize(confusionMatrix, 0);

        for(int i = 0; i < count; i++)
        {
            double inputVec[];
            ArrayResize(inputVec, FEATURE_VECTOR_SIZE);
            for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
                inputVec[f] = features[i][f];
            int predictedClass;
            m_model_ptr.Predict(inputVec, predictedClass);
            int actualClass = m_labelEncoder.EncodeLabel(labels[i]);
            double outputs[];
            m_model_ptr.GetOutputs(inputVec, outputs);
            double loss = CNeuralCore::CrossEntropyLoss(outputs, 3, actualClass);
            totalLoss += loss;
            if(predictedClass == actualClass) correct++;
            if(predictedClass >= 0 && predictedClass < 3 && actualClass >= 0 && actualClass < 3)
                confusionMatrix[actualClass][predictedClass]++;
        }
        m_metrics.UpdateMetrics(confusionMatrix, 3, totalLoss / (double)count, count);
        return totalLoss / (double)count;
    }
};

#endif // __MQH_TRAINING_SESSION_MQH__
