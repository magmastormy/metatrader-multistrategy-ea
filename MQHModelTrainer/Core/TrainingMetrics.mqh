//+------------------------------------------------------------------+
//| TrainingMetrics.mqh                                              |
//| Performance metrics calculation for training evaluation            |
//+------------------------------------------------------------------+
#ifndef MQH_TRAINING_METRICS_MQH
#define MQH_TRAINING_METRICS_MQH

class CTrainingMetrics
{
private:
    double m_accuracy;
    double m_precision;
    double m_recall;
    double m_f1Score;
    double m_loss;
    int m_totalSamples;
    int m_confusionMatrix[3][3];
    
public:
    CTrainingMetrics() : m_accuracy(0.0), m_precision(0.0), m_recall(0.0),
                         m_f1Score(0.0), m_loss(0.0), m_totalSamples(0)
    {
        ArrayInitialize(m_confusionMatrix, 0);
    }
    
    void UpdateMetrics(const int &confusionMatrix[][3], const int numClasses,
                       const double loss, const int totalSamples)
    {
        for(int i = 0; i < numClasses && i < 3; i++)
            for(int j = 0; j < numClasses && j < 3; j++)
                m_confusionMatrix[i][j] = confusionMatrix[i][j];
        
        m_loss = loss;
        m_totalSamples = totalSamples;
        
        CalculateDerivedMetrics(numClasses);
    }
    
    void CalculateDerivedMetrics(const int numClasses)
    {
        int correct = 0;
        int total = 0;
        
        for(int i = 0; i < numClasses && i < 3; i++)
        {
            correct += m_confusionMatrix[i][i];
            for(int j = 0; j < numClasses && j < 3; j++)
                total += m_confusionMatrix[i][j];
        }
        
        m_accuracy = total > 0 ? (double)correct / (double)total : 0.0;
        
        double macroPrecision = 0.0;
        double macroRecall = 0.0;
        int validClasses = 0;
        
        for(int i = 0; i < numClasses && i < 3; i++)
        {
            int tp = m_confusionMatrix[i][i];
            int fp = 0, fn = 0;
            
            for(int j = 0; j < numClasses && j < 3; j++)
            {
                if(j != i)
                {
                    fp += m_confusionMatrix[j][i];
                    fn += m_confusionMatrix[i][j];
                }
            }
            
            if(tp + fp > 0)
            {
                macroPrecision += (double)tp / (double)(tp + fp);
                validClasses++;
            }
            
            if(tp + fn > 0)
                macroRecall += (double)tp / (double)(tp + fn);
        }
        
        m_precision = validClasses > 0 ? macroPrecision / (double)validClasses : 0.0;
        m_recall = validClasses > 0 ? macroRecall / (double)validClasses : 0.0;
        
        double denom = m_precision + m_recall;
        m_f1Score = denom > 0 ? 2.0 * m_precision * m_recall / denom : 0.0;
    }
    
    void PrintConfusionMatrix()
    {
        Print("=== Confusion Matrix ===");
        Print("          Predicted");
        Print("          -1   0   +1");
        Print(StringFormat("Actual -1: %3d %3d %3d", m_confusionMatrix[0][0], m_confusionMatrix[0][1], m_confusionMatrix[0][2]));
        Print(StringFormat("Actual  0: %3d %3d %3d", m_confusionMatrix[1][0], m_confusionMatrix[1][1], m_confusionMatrix[1][2]));
        Print(StringFormat("Actual +1: %3d %3d %3d", m_confusionMatrix[2][0], m_confusionMatrix[2][1], m_confusionMatrix[2][2]));
    }
    
    void PrintAllMetrics()
    {
        Print("=== Training Metrics ===");
        Print(StringFormat("Loss: %.6f", m_loss));
        Print(StringFormat("Accuracy: %.4f", m_accuracy));
        Print(StringFormat("Precision: %.4f", m_precision));
        Print(StringFormat("Recall: %.4f", m_recall));
        Print(StringFormat("F1 Score: %.4f", m_f1Score));
        Print(StringFormat("Total Samples: %d", m_totalSamples));
    }
    
    void SaveMetrics(const string filename)
    {
        int fh = FileOpen(filename, FILE_WRITE | FILE_COMMON);
        if(fh == INVALID_HANDLE) return;
        
        FileWriteString(fh, "=== Training Metrics ===\r\n");
        FileWriteString(fh, StringFormat("Loss: %.6f\r\n", m_loss));
        FileWriteString(fh, StringFormat("Accuracy: %.4f\r\n", m_accuracy));
        FileWriteString(fh, StringFormat("Precision: %.4f\r\n", m_precision));
        FileWriteString(fh, StringFormat("Recall: %.4f\r\n", m_recall));
        FileWriteString(fh, StringFormat("F1 Score: %.4f\r\n", m_f1Score));
        FileWriteString(fh, StringFormat("Total Samples: %d\r\n", m_totalSamples));
        
        FileWriteString(fh, "\r\n=== Confusion Matrix ===\r\n");
        FileWriteString(fh, StringFormat("%d,%d,%d\r\n", m_confusionMatrix[0][0], m_confusionMatrix[0][1], m_confusionMatrix[0][2]));
        FileWriteString(fh, StringFormat("%d,%d,%d\r\n", m_confusionMatrix[1][0], m_confusionMatrix[1][1], m_confusionMatrix[1][2]));
        FileWriteString(fh, StringFormat("%d,%d,%d\r\n", m_confusionMatrix[2][0], m_confusionMatrix[2][1], m_confusionMatrix[2][2]));
        
        FileClose(fh);
    }
    
    double GetAccuracy() const { return m_accuracy; }
    double GetPrecision() const { return m_precision; }
    double GetRecall() const { return m_recall; }
    double GetF1Score() const { return m_f1Score; }
    double GetLoss() const { return m_loss; }
    int GetTotalSamples() const { return m_totalSamples; }
    
    void GetConfusionMatrix(int &outMatrix[][3])
    {
        for(int i = 0; i < 3; i++)
            for(int j = 0; j < 3; j++)
                outMatrix[i][j] = m_confusionMatrix[i][j];
    }
};

#endif // __MQH_TRAINING_METRICS_MQH__
