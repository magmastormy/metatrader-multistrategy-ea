//+------------------------------------------------------------------+
//| TrainingVisualizer.mqh                                           |
//| Chart visualization for training analysis                         |
//+------------------------------------------------------------------+
#ifndef MQH_TRAINING_VISUALIZER_MQH
#define MQH_TRAINING_VISUALIZER_MQH

class CTrainingVisualizer
{
private:
    string m_chartName;
    long m_chartId;

    double m_lossHistory[];
    double m_accHistory[];
    int m_historyCount;

    void CreateLabel(const string objName, const int x, const int y, const string text, const int fontSize = 12, const bool bold = false)
    {
        if(ObjectFind(m_chartId, objName) < 0)
            ObjectCreate(m_chartId, objName, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(m_chartId, objName, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(m_chartId, objName, OBJPROP_YDISTANCE, y);
        ObjectSetInteger(m_chartId, objName, OBJPROP_FONTSIZE, fontSize);
        ObjectSetString(m_chartId, objName, OBJPROP_FONT, "Arial");
        ObjectSetString(m_chartId, objName, OBJPROP_TEXT, text);
        if(bold)
            ObjectSetInteger(m_chartId, objName, OBJPROP_COLOR, clrWhite);
        else
            ObjectSetInteger(m_chartId, objName, OBJPROP_COLOR, clrAqua);
    }

public:
    CTrainingVisualizer() : m_chartId(-1), m_historyCount(0) {}

    bool Initialize(const string chartName = "MQH_Training_Progress")
    {
        m_chartName = chartName;
        m_chartId = ChartID();

        if(m_chartId == -1)
        {
            Print("[MQH-VIZ] No chart available");
            return false;
        }

        CreateLabel("MQH_LabelTraining", 10, 10, "MQH Model Training", 14, true);
        CreateLabel("MQH_LabelEpoch", 10, 40, "Epoch: 0");
        CreateLabel("MQH_LabelLoss", 10, 70, "Loss: 0.0000");
        CreateLabel("MQH_LabelAccuracy", 10, 100, "Accuracy: 0.0000");

        ArrayResize(m_lossHistory, 1000);
        ArrayResize(m_accHistory, 1000);

        Print("[MQH-VIZ] Visualizer initialized");
        return true;
    }

    void UpdateProgress(const int epoch, const double loss, const double accuracy)
    {
        CreateLabel("MQH_LabelEpoch", 10, 40, StringFormat("Epoch: %d", epoch));
        CreateLabel("MQH_LabelLoss", 10, 70, StringFormat("Loss: %.6f", loss));
        CreateLabel("MQH_LabelAccuracy", 10, 100, StringFormat("Accuracy: %.4f", accuracy));

        if(m_historyCount < ArraySize(m_lossHistory))
        {
            m_lossHistory[m_historyCount] = loss;
            m_accHistory[m_historyCount] = accuracy;
            m_historyCount++;
        }
    }

    void ShowMetricsTable(const double accuracy, const double precision,
                          const double recall, const double f1Score, const double loss)
    {
        CreateLabel("MQH_LabelMetricsTitle", 10, 140, "=== Final Metrics ===", 12, true);
        CreateLabel("MQH_LabelAccuracyVal", 10, 170, StringFormat("Accuracy: %.4f", accuracy), 11);
        CreateLabel("MQH_LabelPrecisionVal", 10, 195, StringFormat("Precision: %.4f", precision), 11);
        CreateLabel("MQH_LabelRecallVal", 10, 220, StringFormat("Recall: %.4f", recall), 11);
        CreateLabel("MQH_LabelF1Val", 10, 245, StringFormat("F1 Score: %.4f", f1Score), 11);
        CreateLabel("MQH_LabelLossVal", 10, 270, StringFormat("Loss: %.6f", loss), 11);
    }

    void DrawConfusionMatrix(const int &inMatrix[][3])
    {
        int xBase = 300;
        int yBase = 50;
        int cellSize = 60;

        CreateLabel("MQH_LabelCMTitle", xBase, yBase, "Confusion Matrix", 12, true);

        for(int i = 0; i < 3; i++)
        {
            for(int j = 0; j < 3; j++)
            {
                int x = xBase + j * cellSize;
                int y = yBase + 30 + i * cellSize;
                CreateLabel(StringFormat("MQH_CM_%d_%d", i, j), x, y, StringFormat("%d", inMatrix[i][j]), 10);
            }
        }
    }

    void Clear()
    {
        m_historyCount = 0;
        ArrayInitialize(m_lossHistory, 0);
        ArrayInitialize(m_accHistory, 0);
        CreateLabel("MQH_LabelEpoch", 10, 40, "Epoch: 0");
        CreateLabel("MQH_LabelLoss", 10, 70, "Loss: 0.0000");
        CreateLabel("MQH_LabelAccuracy", 10, 100, "Accuracy: 0.0000");
        Print("[MQH-VIZ] Visualizer cleared");
    }

    void Shutdown()
    {
        Print("[MQH-VIZ] Visualizer shutdown");
    }

    void SaveChartImage(const string filename)
    {
        if(m_chartId == -1)
        {
            Print("[MQH-VIZ] No chart to save");
            return;
        }
        ChartScreenShot(m_chartId, filename, 800, 600);
        PrintFormat("[MQH-VIZ] Chart screenshot saved to: %s", filename);
    }

    bool IsInitialized() const { return m_chartId != -1; }
};

#endif // __MQH_TRAINING_VISUALIZER_MQH__
