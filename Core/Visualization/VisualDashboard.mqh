//+------------------------------------------------------------------+
//| Visual Dashboard                                                 |
//| Premium HUD for monitoring EA and AI components                  |
//+------------------------------------------------------------------+
#ifndef CORE_VISUALIZATION_VISUAL_DASHBOARD_MQH
#define CORE_VISUALIZATION_VISUAL_DASHBOARD_MQH

#include "../Utils/Enums.mqh"
#include "../../AIModules/NextGenStrategyBrain.mqh"
#include "../../AIModules/NeuralNetworkStrategy.mqh"

//+------------------------------------------------------------------+
//| Visual Dashboard Class                                           |
//+------------------------------------------------------------------+
class CVisualDashboard
{
private:
    string m_prefix;
    int m_x;
    int m_y;
    int m_rowHeight;
    int m_columnWidth;
    color m_headerColor;
    color m_textColor;
    color m_statusColor;
    int m_fontSize;
    string m_fontName;

public:
    CVisualDashboard(string prefix = "DB_")
    {
        m_prefix = prefix;
        m_x = 20;
        m_y = 20;
        m_rowHeight = 20;
        m_columnWidth = 200;
        m_headerColor = clrGold;
        m_textColor = clrWhite;
        m_statusColor = clrLime;
        m_fontSize = 10;
        m_fontName = "Consolas";
    }

    ~CVisualDashboard()
    {
        Cleanup();
    }

    // Initialize the dashboard
    void Initialize()
    {
        Cleanup();
    }

    // Update the dashboard with latest data
    void Update(int activeStrats, int totalPositions, double balance, double equity, 
                CNextGenStrategyBrain* brain, CNeuralNetworkStrategy* nn)
    {
        int row = 0;
        
        // --- Header ---
        DrawLabel("Title", "MULTY-STRATEGY EA V2.0 | " + TimeToString(TimeCurrent(), TIME_SECONDS), row++, 0, m_headerColor);
        DrawLabel("Separator1", "------------------------------------------------", row++, 0, clrGray);

        // --- Core Stats ---
        DrawLabel("Stats_Active", "Active Strategies: " + (string)activeStrats, row, 0, m_textColor);
        DrawLabel("Stats_Positions", "Positions: " + (string)totalPositions, row++, 1, m_textColor);
        
        DrawLabel("Stats_Balance", "Balance: " + DoubleToString(balance, 2), row, 0, m_textColor);
        DrawLabel("Stats_Equity", "Equity: " + DoubleToString(equity, 2), row++, 1, m_textColor);
        
        DrawLabel("Separator2", "------------------------------------------------", row++, 0, clrGray);

        // --- AI Status Header ---
        DrawLabel("AI_Header", "[ AI SUBSYSTEMS STATUS ]", row++, 0, m_headerColor);

        // --- Neural Network ---
        string nnStatus = (nn != NULL) ? "ACTIVE" : "INACTIVE";
        color nnColor = (nn != NULL) ? clrLime : clrRed;
        DrawLabel("NN_Title", "Neural Network:", row, 0, m_textColor);
        DrawLabel("NN_Status", nnStatus, row++, 1, nnColor);

        // --- Transformer ---
        string tfStatus = "OFFLINE";
        color tfColor = clrRed;
        if(brain != NULL)
        {
            tfStatus = brain.GetEnsembleStatus();
            tfColor = clrCyan;
        }
        DrawLabel("TF_Title", "AI Engine Mode:", row, 0, m_textColor);
        DrawLabel("TF_Status", tfStatus, row++, 1, tfColor);

        // --- Ensemble Meta-Learner ---
        string ensStatus = "N/A";
        if(brain != NULL)
        {
            ensStatus = DoubleToString(brain.GetAccuracy() * 100.0, 1) + "% Acc.";
        }
        DrawLabel("ENS_Title", "Ensemble Accuracy:", row, 0, m_textColor);
        DrawLabel("ENS_Status", ensStatus, row++, 1, clrWhite);

        // --- Uncertainty Quantifier ---
        string uncRec = "UNKNOWN";
        color uncColor = clrYellow;
        if(brain != NULL)
        {
            double unc = brain.GetCurrentUncertainty();
            if(unc < 0.3) { uncRec = "LOW (RELIABLE)"; uncColor = clrLime; }
            else if(unc < 0.6) { uncRec = "MEDIUM (CAUTION)"; uncColor = clrYellow; }
            else { uncRec = "HIGH (UNRELIABLE)"; uncColor = clrOrangeRed; }
        }
        DrawLabel("UNC_Title", "Uncertainty Level:", row, 0, m_textColor);
        DrawLabel("UNC_Status", uncRec, row++, 1, uncColor);

        DrawLabel("Separator3", "------------------------------------------------", row++, 0, clrGray);
        
        // --- Footer ---
        string healthText = "GOOD";
        color healthColor = clrYellow;
        double equityRatio = (balance > 0.0) ? (equity / balance) : 1.0;

        if(activeStrats <= 0 || equityRatio < 0.90)
        {
            healthText = "CRITICAL";
            healthColor = clrRed;
        }
        else if(equityRatio < 0.97)
        {
            healthText = "CAUTION";
            healthColor = clrOrange;
        }
        else if(nn != NULL && brain != NULL)
        {
            healthText = "EXCELLENT";
            healthColor = clrLime;
        }

        DrawLabel("Footer", "System Health: [ " + healthText + " ]", row++, 0, healthColor);
        
        ChartRedraw();
    }

private:
    void DrawLabel(string name, string text, int row, int col, color clr)
    {
        string objName = m_prefix + name;
        if(ObjectFind(0, objName) < 0)
        {
            ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
        }
        
        ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, m_x + (col * m_columnWidth));
        ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, m_y + (row * m_rowHeight));
        ObjectSetString(0, objName, OBJPROP_TEXT, text);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, m_fontSize);
        ObjectSetString(0, objName, OBJPROP_FONT, m_fontName);
        ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
    }

    void Cleanup()
    {
        ObjectsDeleteAll(0, m_prefix);
    }
};

#endif // CORE_VISUALIZATION_VISUAL_DASHBOARD_MQH
