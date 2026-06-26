//+------------------------------------------------------------------+
//| TrainingVisualizer.mqh                                           |
//| Chart visualization for training analysis                         |
//+------------------------------------------------------------------+
#ifndef __MQH_TRAINING_VISUALIZER_MQH__
#define __MQH_TRAINING_VISUALIZER_MQH__

#include <ChartObjects\ChartObjectsTxtControls.mqh>
#include <ChartObjects\ChartObjectsLines.mqh>
#include <ChartObjects\ChartObjectsIndicators.mqh>

class CTrainingVisualizer
{
private:
    string m_chartName;
    long m_chartId;
    
    CChartObjectLabel m_labelTraining;
    CChartObjectLabel m_labelEpoch;
    CChartObjectLabel m_labelLoss;
    CChartObjectLabel m_labelAccuracy;
    
    CChartObjectLine m_lineLoss;
    CChartObjectLine m_lineAccuracy;
    
    double m_lossHistory[];
    double m_accHistory[];
    int m_historyCount;
    
public:
    CTrainingVisualizer() : m_chartId(-1), m_historyCount(0) {}
    
    bool Initialize(const string chartName = "MQH_Training_Progress")
    {
        m_chartName = chartName;
        m_chartId = ChartFind(chartName);
        
        if(m_chartId == -1)
            m_chartId = ChartCreate(chartName, 0, 0, 800, 600);
        
        if(m_chartId == -1)
        {
            Print("[MQH-VIZ] Failed to create chart");
            return false;
        }
        
        ChartSetInteger(m_chartId, CHART_SHOW, true);
        ChartSetInteger(m_chartId, CHART_AUTOSCROLL, true);
        
        m_labelTraining.Create(m_chartId, "LabelTraining", 0, 10, 10);
        m_labelTraining.SetFont("Arial", 14, true);
        m_labelTraining.SetText("MQH Model Training");
        
        m_labelEpoch.Create(m_chartId, "LabelEpoch", 0, 10, 40);
        m_labelEpoch.SetFont("Arial", 12);
        m_labelEpoch.SetText("Epoch: 0");
        
        m_labelLoss.Create(m_chartId, "LabelLoss", 0, 10, 70);
        m_labelLoss.SetFont("Arial", 12);
        m_labelLoss.SetText("Loss: 0.0000");
        
        m_labelAccuracy.Create(m_chartId, "LabelAccuracy", 0, 10, 100);
        m_labelAccuracy.SetFont("Arial", 12);
        m_labelAccuracy.SetText("Accuracy: 0.0000");
        
        m_lineLoss.Create(m_chartId, "LineLoss", 0);
        m_lineLoss.SetColor(clrRed);
        m_lineLoss.SetWidth(2);
        
        m_lineAccuracy.Create(m_chartId, "LineAccuracy", 0);
        m_lineAccuracy.SetColor(clrGreen);
        m_lineAccuracy.SetWidth(2);
        
        ArrayResize(m_lossHistory, 1000);
        ArrayResize(m_accHistory, 1000);
        
        Print("[MQH-VIZ] Visualizer initialized");
        return true;
    }
    
    void UpdateProgress(const int epoch, const double loss, const double accuracy)
    {
        m_labelEpoch.SetText(StringFormat("Epoch: %d", epoch));
        m_labelLoss.SetText(StringFormat("Loss: %.6f", loss));
        m_labelAccuracy.SetText(StringFormat("Accuracy: %.4f", accuracy));
        
        if(m_historyCount < ArraySize(m_lossHistory))
        {
            m_lossHistory[m_historyCount] = loss;
            m_accHistory[m_historyCount] = accuracy;
            m_historyCount++;
        }
        
        UpdateLines();
    }
    
    void UpdateLines()
    {
        if(m_historyCount < 2) return;
        
        m_lineLoss.DeleteAllPoints();
        m_lineAccuracy.DeleteAllPoints();
        
        double maxLoss = 0.0;
        for(int i = 0; i < m_historyCount; i++)
            if(m_lossHistory[i] > maxLoss) maxLoss = m_lossHistory[i];
        
        if(maxLoss == 0) maxLoss = 1.0;
        
        for(int i = 0; i < m_historyCount; i++)
        {
            double x = i;
            double yLoss = 100 - (m_lossHistory[i] / maxLoss) * 90;
            double yAcc = 100 - m_accHistory[i] * 90;
            
            m_lineLoss.AddPoint(x, yLoss);
            m_lineAccuracy.AddPoint(x, yAcc);
        }
    }
    
    void ShowMetricsTable(const double accuracy, const double precision,
                          const double recall, const double f1Score, const double loss)
    {
        CChartObjectLabel label;
        
        label.Create(m_chartId, "LabelMetricsTitle", 0, 10, 140);
        label.SetFont("Arial", 12, true);
        label.SetText("=== Final Metrics ===");
        
        label.Create(m_chartId, "LabelAccuracyVal", 0, 10, 170);
        label.SetFont("Arial", 11);
        label.SetText(StringFormat("Accuracy: %.4f", accuracy));
        
        label.Create(m_chartId, "LabelPrecisionVal", 0, 10, 195);
        label.SetFont("Arial", 11);
        label.SetText(StringFormat("Precision: %.4f", precision));
        
        label.Create(m_chartId, "LabelRecallVal", 0, 10, 220);
        label.SetFont("Arial", 11);
        label.SetText(StringFormat("Recall: %.4f", recall));
        
        label.Create(m_chartId, "LabelF1Val", 0, 10, 245);
        label.SetFont("Arial", 11);
        label.SetText(StringFormat("F1 Score: %.4f", f1Score));
        
        label.Create(m_chartId, "LabelLossVal", 0, 10, 270);
        label.SetFont("Arial", 11);
        label.SetText(StringFormat("Loss: %.6f", loss));
    }
    
    void DrawConfusionMatrix(const int matrix[3][3])
    {
        int xBase = 300;
        int yBase = 50;
        int cellSize = 60;
        
        CChartObjectLabel label;
        
        label.Create(m_chartId, "LabelCMTitle", 0, xBase, yBase);
        label.SetFont("Arial", 12, true);
        label.SetText("Confusion Matrix");
        
        for(int i = 0; i < 3; i++)
        {
            for(int j = 0; j < 3; j++)
            {
                int x = xBase + j * cellSize;
                int y = yBase + 30 + i * cellSize;
                
                label.Create(m_chartId, StringFormat("CM_%d_%d", i, j), 0, x, y);
                label.SetFont("Arial", 10);
                
                int value = matrix[i][j];
                string color = i == j ? "0xFF00FF00" : "0xFFFF0000";
                label.SetText(StringFormat("%d", value));
            }
        }
    }
    
    void Clear()
    {
        if(m_chartId == -1) return;
        
        m_lineLoss.DeleteAllPoints();
        m_lineAccuracy.DeleteAllPoints();
        
        m_historyCount = 0;
        ArrayInitialize(m_lossHistory, 0);
        ArrayInitialize(m_accHistory, 0);
        
        m_labelEpoch.SetText("Epoch: 0");
        m_labelLoss.SetText("Loss: 0.0000");
        m_labelAccuracy.SetText("Accuracy: 0.0000");
        
        Print("[MQH-VIZ] Visualizer cleared");
    }
    
    void Shutdown()
    {
        if(m_chartId != -1)
        {
            ChartClose(m_chartId);
            m_chartId = -1;
        }
        
        Print("[MQH-VIZ] Visualizer shutdown");
    }
    
    void SaveChartImage(const string filename)
    {
        if(m_chartId == -1)
        {
            Print("[MQH-VIZ] No chart to save");
            return;
        }
        
        string filePath = TerminalInfoString(TERMINAL_DATA_PATH) + "\\Files\\" + filename;
        ChartSaveAsImage(m_chartId, filePath);
        
        PrintFormat("[MQH-VIZ] Chart saved to: %s", filePath);
    }
    
    bool IsInitialized() const { return m_chartId != -1; }
};

#endif // __MQH_TRAINING_VISUALIZER_MQH__
