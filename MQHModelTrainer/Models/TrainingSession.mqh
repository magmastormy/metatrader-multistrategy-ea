// Training session orchestration and management
#ifndef MQH_TRAINING_SESSION_MQH
#define MQH_TRAINING_SESSION_MQH

#include "../../Core/AI/AIFeatureVectorBuilder.mqh"
#include "../../AIModules/AIConfig.mqh"
#include "../Data/LabelEncoder.mqh"
#include "FeedForwardNN.mqh"
#include "../Core/TrainingMetrics.mqh"

struct STrainingConfig
{
    int epochs;
    int batchSize;
    int earlyStoppingPatience;
    double earlyStoppingMinDelta;
    int logInterval;

    // MQL5 does not zero-fill a local struct, and no caller sets this one, so the default lives here:
    // CheckEarlyStopping reads it, and an unset member would be garbage.
    STrainingConfig() : earlyStoppingMinDelta(0.000001) {}
};

class CTrainingSession
{
private:
    CLabelEncoder m_labelEncoder;
    CTrainingMetrics m_metrics;
    CTrainingMetrics m_trainMetrics;
    
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
    double m_earlyStopMinDelta;
    bool m_earlyStopTriggered;
    
    int m_totalEpochs;
    int m_currentEpoch;
    int m_batchSize;
    
    string m_logFile;
    int m_logHandle;
    
    int m_progressUpdateInterval;
    
public:
    CTrainingSession() : m_bestValLoss(1e10), m_bestEpoch(0), m_earlyStopCounter(0),
                         m_earlyStopPatience(50), m_earlyStopMinDelta(0.000001), m_earlyStopTriggered(false),
                         m_totalEpochs(500), m_currentEpoch(0), m_batchSize(32),
                         m_logFile(""), m_logHandle(INVALID_HANDLE), m_progressUpdateInterval(10),
                         m_model_ptr(NULL) {}
    
    void SetConfig(const STrainingConfig &config)
    {
        m_totalEpochs = config.epochs;
        m_batchSize = config.batchSize;
        m_earlyStopPatience = config.earlyStoppingPatience;
        m_earlyStopMinDelta = config.earlyStoppingMinDelta;
        m_progressUpdateInterval = config.logInterval;
    }

    void LogMessage(const string message)
    {
        string logLine = StringFormat("[%s] %s", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), message);
        Print(logLine);
        if(m_logHandle != INVALID_HANDLE)
            FileWriteString(m_logHandle, logLine + "\r\n");
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

        // The tuner reuses one session across candidates, so the file name is set once per program run and
        // each candidate appends to it instead of truncating the previous result.
        if(m_logFile == "")
        {
            m_logFile = StringFormat("MQHTrainingLog_%s.txt", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
            PrintFormat("[MQH-TRAIN] Training log: %s", m_logFile);
        }
        m_logHandle = FileOpen(m_logFile, FILE_READ | FILE_WRITE | FILE_COMMON);
        if(m_logHandle == INVALID_HANDLE)
            PrintFormat("[MQH-TRAIN] Warning: Failed to open log file: %s", m_logFile);
        else
            FileSeek(m_logHandle, 0, SEEK_END);

        // Early-stopping state belongs to one run: without this the next candidate is measured against the
        // previous candidate's best validation loss and inherits its stop flag.
        m_bestValLoss = 1e10;
        m_bestEpoch = 0;
        m_earlyStopCounter = 0;
        m_earlyStopTriggered = false;

        for(m_currentEpoch = 1; m_currentEpoch <= m_totalEpochs; m_currentEpoch++)
        {
            double trainLoss = TrainEpochWithModel();
            double valLoss = EvaluateWithModel(valFeatures, valLabels, valCount, m_metrics);

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

    bool CheckEarlyStopping(const double valLoss)
    {
        if(valLoss < m_bestValLoss - m_earlyStopMinDelta)
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
        LogMessage(StringFormat("Training completed | stop=%s | bestEpoch=%d | bestValLoss=%.6f",
                                m_earlyStopTriggered ? "early-stopping" : "epoch-budget",
                                m_bestEpoch, m_bestValLoss));

        double valLoss = EvaluateWithModel(m_valFeatures, m_valLabels, m_valCount, m_metrics);
        double trainLoss = EvaluateWithModel(m_trainFeatures, m_trainLabels, m_trainCount, m_trainMetrics);
        LogMessage(StringFormat("Train: Loss=%.6f | Accuracy=%.4f | F1=%.4f | samples=%d",
                                trainLoss, m_trainMetrics.GetAccuracy(), m_trainMetrics.GetF1Score(), m_trainCount));
        LogMessage(StringFormat("Validation: Loss=%.6f | Accuracy=%.4f | F1=%.4f | samples=%d",
                                valLoss, m_metrics.GetAccuracy(), m_metrics.GetF1Score(), m_valCount));

        m_metrics.PrintConfusionMatrix();

        if(m_logHandle != INVALID_HANDLE)
        {
            FileClose(m_logHandle);
            m_logHandle = INVALID_HANDLE;
        }
    }
    
    CTrainingMetrics GetTrainMetrics() const { return m_trainMetrics; }
    CTrainingMetrics GetValMetrics() const { return m_metrics; }
    
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

    double EvaluateWithModel(const double &features[][], const int &labels[], const int count,
                             CTrainingMetrics &target)
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
        target.UpdateMetrics(confusionMatrix, 3, totalLoss / (double)count, count);
        return totalLoss / (double)count;
    }
};

#endif // __MQH_TRAINING_SESSION_MQH__
