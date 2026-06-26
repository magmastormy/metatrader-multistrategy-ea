//+------------------------------------------------------------------+
//| HyperparameterOptimizer.mqh                                      |
//| Hyperparameter tuning utilities                                   |
//+------------------------------------------------------------------+
#ifndef __MQH_HYPERPARAMETER_OPTIMIZER_MQH__
#define __MQH_HYPERPARAMETER_OPTIMIZER_MQH__

#include "../Core/AI/AIFeatureVectorBuilder.mqh"
#include "../AIModules/AIConfig.mqh"
#include "../Data/CSVDataLoader.mqh"
#include "../Data/DataPreprocessor.mqh"
#include "../Data/LabelEncoder.mqh"
#include "../Core/TrainingMetrics.mqh"
#include "../Models/FeedForwardNN.mqh"
#include "../Models/TrainingSession.mqh"

struct SHyperparameterSet
{
    double learningRate;
    int batchSize;
    double l2Regularization;
    int hiddenLayer1Size;
    int hiddenLayer2Size;
    int hiddenLayer3Size;
    int epochs;
    string name;
};

struct SHyperparameterTuningResult
{
    SHyperparameterSet params;
    double trainAccuracy;
    double trainLoss;
    double valAccuracy;
    double valLoss;
    double f1Score;
    int rank;
};

class CHyperparameterOptimizer
{
private:
    CCSVDataLoader m_dataLoader;
    CDataPreprocessor m_preprocessor;
    CLabelEncoder m_labelEncoder;
    CTrainingSession m_trainer;
    
    SHyperparameterSet m_candidateSets[];
    int m_candidateCount;
    
    SHyperparameterTuningResult m_results[];
    int m_resultCount;
    
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    
public:
    CHyperparameterOptimizer() : m_candidateCount(0), m_resultCount(0) {}
    
    void AddCandidate(const SHyperparameterSet &params)
    {
        int idx = m_candidateCount;
        ArrayResize(m_candidateSets, m_candidateCount + 1);
        m_candidateSets[idx] = params;
        m_candidateCount++;
        
        PrintFormat("[MQH-TUNER] Added candidate: %s", params.name);
    }
    
    void AddDefaultCandidates()
    {
        SHyperparameterSet candidates[] = {
            {0.001, 32, 0.001, 32, 16, 8, 100, "Default"},
            {0.0005, 32, 0.001, 32, 16, 8, 100, "LR_0.0005"},
            {0.002, 32, 0.001, 32, 16, 8, 100, "LR_0.002"},
            {0.001, 16, 0.001, 32, 16, 8, 100, "BS_16"},
            {0.001, 64, 0.001, 32, 16, 8, 100, "BS_64"},
            {0.001, 32, 0.0001, 32, 16, 8, 100, "Reg_0.0001"},
            {0.001, 32, 0.01, 32, 16, 8, 100, "Reg_0.01"},
            {0.001, 32, 0.001, 64, 32, 16, 100, "LargerNet"},
            {0.001, 32, 0.001, 16, 8, 4, 100, "SmallerNet"}
        };
        
        for(int i = 0; i < ArraySize(candidates); i++)
            AddCandidate(candidates[i]);
        
        PrintFormat("[MQH-TUNER] Added %d default candidates", ArraySize(candidates));
    }
    
    bool RunTuning(const string symbol, const ENUM_TIMEFRAMES timeframe,
                   const string dataFile, const int valRatio = 20, const int testRatio = 10)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        
        if(!m_dataLoader.Load(dataFile))
        {
            Print("[MQH-TUNER] Failed to load training data");
            return false;
        }
        
        int totalCount = m_dataLoader.GetTotalRowCount();
        if(totalCount == 0)
        {
            Print("[MQH-TUNER] No data loaded");
            return false;
        }
        
        double allFeatures[][];
        int labels[];
        int count = 0;
        
        if(!m_dataLoader.LoadAllRows(allFeatures, labels, count))
            return false;
        
        m_preprocessor.SetSplitRatio(valRatio, testRatio);
        m_preprocessor.SplitData(allFeatures, labels, count);
        
        m_preprocessor.NormalizeData();
        
        PrintFormat("[MQH-TUNER] Starting tuning with %d candidates", m_candidateCount);
        PrintFormat("[MQH-TUNER] Training samples: %d, Validation: %d, Test: %d",
                    m_preprocessor.GetTrainCount(),
                    m_preprocessor.GetValCount(),
                    m_preprocessor.GetTestCount());
        
        for(int i = 0; i < m_candidateCount; i++)
        {
            PrintFormat("[MQH-TUNER] Evaluating candidate %d/%d: %s",
                        i + 1, m_candidateCount, m_candidateSets[i].name);
            
            SHyperparameterTuningResult result;
            result.params = m_candidateSets[i];
            
            if(EvaluateCandidate(m_candidateSets[i], result))
            {
                int idx = m_resultCount;
                ArrayResize(m_results, m_resultCount + 1);
                m_results[idx] = result;
                m_resultCount++;
            }
        }
        
        RankResults();
        
        Print("[MQH-TUNER] Tuning complete");
        PrintResults();
        
        return true;
    }
    
    bool EvaluateCandidate(const SHyperparameterSet &params, SHyperparameterTuningResult &result)
    {
        CFeedForwardNN model;
        
        if(!model.Initialize(params.hiddenLayer1Size, params.hiddenLayer2Size, params.hiddenLayer3Size))
        {
            PrintFormat("[MQH-TUNER] Failed to initialize model for: %s", params.name);
            return false;
        }
        
        model.SetLearningRate(params.learningRate);
        model.SetL2Regularization(params.l2Regularization);
        
        CTrainingSession::STrainingConfig config;
        config.epochs = params.epochs;
        config.batchSize = params.batchSize;
        config.earlyStoppingPatience = 10;
        config.earlyStoppingMinDelta = 0.0001;
        config.logInterval = 20;
        
        m_trainer.SetConfig(config);
        
        double trainFeatures[][];
        int trainLabels[];
        m_preprocessor.GetTrainData(trainFeatures, trainLabels);
        
        double valFeatures[][];
        int valLabels[];
        m_preprocessor.GetValData(valFeatures, valLabels);
        
        m_trainer.Train(model, trainFeatures, trainLabels, m_preprocessor.GetTrainCount(),
                        valFeatures, valLabels, m_preprocessor.GetValCount());
        
        CTrainingMetrics trainMetrics = m_trainer.GetTrainMetrics();
        CTrainingMetrics valMetrics = m_trainer.GetValMetrics();
        
        result.trainAccuracy = trainMetrics.GetAccuracy();
        result.trainLoss = trainMetrics.GetLoss();
        result.valAccuracy = valMetrics.GetAccuracy();
        result.valLoss = valMetrics.GetLoss();
        result.f1Score = valMetrics.GetF1Score();
        result.rank = 0;
        
        PrintFormat("[MQH-TUNER] Candidate %s - Train: %.4f acc, %.6f loss | Val: %.4f acc, %.6f loss | F1: %.4f",
                    params.name,
                    result.trainAccuracy,
                    result.trainLoss,
                    result.valAccuracy,
                    result.valLoss,
                    result.f1Score);
        
        return true;
    }
    
    void RankResults()
    {
        for(int i = 0; i < m_resultCount; i++)
        {
            int rank = 1;
            for(int j = 0; j < m_resultCount; j++)
            {
                if(i == j) continue;
                
                if(m_results[j].f1Score > m_results[i].f1Score)
                    rank++;
            }
            m_results[i].rank = rank;
        }
    }
    
    void PrintResults()
    {
        Print("=== Hyperparameter Tuning Results ===");
        Print("Rank | Candidate | LR | Batch | L2 | Train Acc | Val Acc | Val Loss | F1");
        
        for(int i = 0; i < m_resultCount; i++)
        {
            const SHyperparameterTuningResult &r = m_results[i];
            Print(StringFormat("%4d | %-20s | %.4f | %4d | %.4f | %.4f | %.4f | %.6f | %.4f",
                              r.rank,
                              r.params.name,
                              r.params.learningRate,
                              r.params.batchSize,
                              r.params.l2Regularization,
                              r.trainAccuracy,
                              r.valAccuracy,
                              r.valLoss,
                              r.f1Score));
        }
    }
    
    void SaveResults(const string filename)
    {
        int fh = FileOpen(filename, FILE_WRITE | FILE_COMMON);
        if(fh == INVALID_HANDLE)
        {
            PrintFormat("[MQH-TUNER] Failed to open results file: %s", filename);
            return;
        }
        
        FileWriteString(fh, "=== Hyperparameter Tuning Results ===\r\n");
        FileWriteString(fh, StringFormat("Generated: %s\r\n", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)));
        FileWriteString(fh, StringFormat("Symbol: %s\r\n", m_symbol));
        FileWriteString(fh, StringFormat("Timeframe: %s\r\n\r\n", EnumToString(m_timeframe)));
        
        FileWriteString(fh, "Rank,Candidate,LearningRate,BatchSize,L2Regularization,TrainAccuracy,TrainLoss,ValAccuracy,ValLoss,F1Score\r\n");
        
        for(int i = 0; i < m_resultCount; i++)
        {
            const SHyperparameterTuningResult &r = m_results[i];
            FileWriteString(fh, StringFormat("%d,%s,%.6f,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f\r\n",
                                             r.rank,
                                             r.params.name,
                                             r.params.learningRate,
                                             r.params.batchSize,
                                             r.params.l2Regularization,
                                             r.trainAccuracy,
                                             r.trainLoss,
                                             r.valAccuracy,
                                             r.valLoss,
                                             r.f1Score));
        }
        
        FileClose(fh);
        PrintFormat("[MQH-TUNER] Results saved to: %s", filename);
    }
    
    SHyperparameterSet GetBestParameters() const
    {
        if(m_resultCount == 0)
        {
            SHyperparameterSet defaultParams;
            defaultParams.learningRate = 0.001;
            defaultParams.batchSize = 32;
            defaultParams.l2Regularization = 0.001;
            defaultParams.hiddenLayer1Size = 32;
            defaultParams.hiddenLayer2Size = 16;
            defaultParams.hiddenLayer3Size = 8;
            defaultParams.epochs = 100;
            defaultParams.name = "Default";
            return defaultParams;
        }
        
        int bestIdx = 0;
        double bestF1 = m_results[0].f1Score;
        
        for(int i = 1; i < m_resultCount; i++)
        {
            if(m_results[i].f1Score > bestF1)
            {
                bestF1 = m_results[i].f1Score;
                bestIdx = i;
            }
        }
        
        return m_results[bestIdx].params;
    }
    
    int GetResultCount() const { return m_resultCount; }
    
    SHyperparameterTuningResult GetResultAt(const int idx) const
    {
        if(idx >= 0 && idx < m_resultCount)
            return m_results[idx];
        
        SHyperparameterTuningResult empty;
        return empty;
    }
};

#endif // __MQH_HYPERPARAMETER_OPTIMIZER_MQH__
