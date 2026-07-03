//+------------------------------------------------------------------+
//| ModelComparer.mqh                                                |
//| Compare multiple trained models                                   |
//+------------------------------------------------------------------+
#ifndef MQH_MODEL_COMPARER_MQH
#define MQH_MODEL_COMPARER_MQH

#include "../Core/AI/AIFeatureVectorBuilder.mqh"
#include "../AIModules/AIConfig.mqh"
#include "../Data/LabelEncoder.mqh"
#include "../Core/TrainingMetrics.mqh"
#include "FeedForwardNN.mqh"
#include "ModelEvaluator.mqh"

struct SModelComparisonResult
{
    string modelName;
    double accuracy;
    double precision;
    double recall;
    double f1Score;
    double loss;
    int totalSamples;
    int rank;
};

class CModelComparer
{
private:
    CModelEvaluator m_evaluator;
    CLabelEncoder m_labelEncoder;
    
    SModelComparisonResult m_results[];
    int m_resultCount;
    
    string m_reportFile;
    
public:
    CModelComparer() : m_resultCount(0) {}
    
    bool AddModel(const string modelName, const string symbol, const ENUM_TIMEFRAMES timeframe,
                  const double &features[][], const int &labels[], const int count)
    {
        PrintFormat("[MQH-COMPARE] Evaluating model: %s", modelName);
        
        if(!m_evaluator.LoadModel(symbol, timeframe))
            return false;
        
        if(!m_evaluator.Evaluate(features, labels, count))
            return false;
        
        CTrainingMetrics &metrics = m_evaluator.GetMetrics();
        
        int idx = m_resultCount;
        ArrayResize(m_results, m_resultCount + 1);
        m_results[idx].modelName = modelName;
        m_results[idx].accuracy = metrics.GetAccuracy();
        m_results[idx].precision = metrics.GetPrecision();
        m_results[idx].recall = metrics.GetRecall();
        m_results[idx].f1Score = metrics.GetF1Score();
        m_results[idx].loss = metrics.GetLoss();
        m_results[idx].totalSamples = metrics.GetTotalSamples();
        m_results[idx].rank = 0;
        
        m_resultCount++;
        
        return true;
    }
    
    void RankModels(const ENUM_COMPARISON_CRITERION criterion = CRITERION_F1)
    {
        for(int i = 0; i < m_resultCount; i++)
        {
            int rank = 1;
            for(int j = 0; j < m_resultCount; j++)
            {
                if(i == j) continue;
                
                bool isBetter = false;
                switch(criterion)
                {
                    case CRITERION_F1:
                        isBetter = m_results[j].f1Score > m_results[i].f1Score;
                        break;
                    case CRITERION_ACCURACY:
                        isBetter = m_results[j].accuracy > m_results[i].accuracy;
                        break;
                    case CRITERION_LOSS:
                        isBetter = m_results[j].loss < m_results[i].loss;
                        break;
                    case CRITERION_PRECISION:
                        isBetter = m_results[j].precision > m_results[i].precision;
                        break;
                    case CRITERION_RECALL:
                        isBetter = m_results[j].recall > m_results[i].recall;
                        break;
                }
                
                if(isBetter) rank++;
            }
            m_results[i].rank = rank;
        }
    }
    
    void PrintComparison()
    {
        Print("=== Model Comparison Results ===");
        Print("Rank | Model Name | Accuracy | Precision | Recall | F1 Score | Loss");
        
        for(int i = 0; i < m_resultCount; i++)
        {
            Print(StringFormat("%4d | %-20s | %.4f | %.4f | %.4f | %.4f | %.6f",
                              m_results[i].rank,
                              m_results[i].modelName,
                              m_results[i].accuracy,
                              m_results[i].precision,
                              m_results[i].recall,
                              m_results[i].f1Score,
                              m_results[i].loss));
        }
    }
    
    void GenerateComparisonReport(const string filename)
    {
        m_reportFile = filename;
        
        int fh = FileOpen(filename, FILE_WRITE | FILE_COMMON);
        if(fh == INVALID_HANDLE)
        {
            PrintFormat("[MQH-COMPARE] Failed to open report file: %s", filename);
            return;
        }
        
        FileWriteString(fh, "=== Model Comparison Report ===\r\n");
        FileWriteString(fh, StringFormat("Generated: %s\r\n\r\n", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)));
        
        FileWriteString(fh, "Rank | Model Name | Accuracy | Precision | Recall | F1 Score | Loss\r\n");
        FileWriteString(fh, "-----|------------|----------|-----------|--------|----------|------\r\n");
        
        for(int i = 0; i < m_resultCount; i++)
        {
            FileWriteString(fh, StringFormat("%4d | %-20s | %.4f | %.4f | %.4f | %.4f | %.6f\r\n",
                                             m_results[i].rank,
                                             m_results[i].modelName,
                                             m_results[i].accuracy,
                                             m_results[i].precision,
                                             m_results[i].recall,
                                             m_results[i].f1Score,
                                             m_results[i].loss));
        }
        
        string bestModel = GetBestModelName();
        FileWriteString(fh, StringFormat("\r\nBest Model: %s\r\n", bestModel));
        
        FileClose(fh);
        PrintFormat("[MQH-COMPARE] Comparison report saved to: %s", filename);
    }
    
    string GetBestModelName() const
    {
        if(m_resultCount == 0) return "";
        
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
        
        return m_results[bestIdx].modelName;
    }
    
    int GetResultCount() const { return m_resultCount; }
    
    SModelComparisonResult GetResultAt(const int idx) const
    {
        if(idx >= 0 && idx < m_resultCount)
            return m_results[idx];
        
        SModelComparisonResult empty;
        empty.modelName = "";
        empty.rank = 0;
        return empty;
    }
};

enum ENUM_COMPARISON_CRITERION
{
    CRITERION_F1 = 0,
    CRITERION_ACCURACY = 1,
    CRITERION_LOSS = 2,
    CRITERION_PRECISION = 3,
    CRITERION_RECALL = 4
};

#endif // __MQH_MODEL_COMPARER_MQH__
