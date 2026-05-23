//+------------------------------------------------------------------+
//| Visual Dashboard                                                 |
//| Premium HUD for monitoring EA and AI components                  |
//+------------------------------------------------------------------+
#ifndef CORE_VISUALIZATION_VISUAL_DASHBOARD_MQH
#define CORE_VISUALIZATION_VISUAL_DASHBOARD_MQH

#include "../Utils/Enums.mqh"
#include "../../AIModules/NextGenStrategyBrain.mqh"
#include "../../AIModules/NeuralNetworkStrategy.mqh"
#include "../Engines/AIEngine.mqh"

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
                CNextGenStrategyBrain* brain, CNeuralNetworkStrategy* nn, CAIEngine* aiEngine = NULL)
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
        if(brain != NULL && brain.IsInitialized())
        {
            tfStatus = brain.GetRuntimeMode();
            tfColor = clrCyan;
        }
        DrawLabel("TF_Title", "AI Engine Mode:", row, 0, m_textColor);
        DrawLabel("TF_Status", tfStatus, row++, 1, tfColor);

        // --- External LLM ---
        string llmStatus = "DISABLED";
        color llmColor = clrRed;
        if(aiEngine != NULL && aiEngine.IsExternalLLMEnabled())
        {
            llmStatus = "ENABLED";
            llmColor = clrLime;
        }
        DrawLabel("LLM_Title", "External LLM:", row, 0, m_textColor);
        DrawLabel("LLM_Status", llmStatus, row++, 1, llmColor);

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

    //+------------------------------------------------------------------+
    //| Update drawing statistics section                                 |
    //+------------------------------------------------------------------+
    void UpdateDrawingStats(int globalObjectCount, int maxObjects, int alertLevel,
                           int fibonacciObjects, int supportResObjects, int ictObjects)
    {
        int row = 0;
        int startX = 800;
        
        // --- Drawing Stats Header ---
        DrawLabelAt("Draw_Title", "CHART OBJECTS", startX, m_y + (row++ * m_rowHeight), m_headerColor);
        DrawLabelAt("Draw_Sep", "--------------------", startX, m_y + (row++ * m_rowHeight), clrGray);

        // --- Global Object Count ---
        string globalText = (string)globalObjectCount + "/" + (string)maxObjects;
        color globalColor = clrWhite;
        if(globalObjectCount >= 950)
            globalColor = clrRed;
        else if(globalObjectCount >= 900)
            globalColor = clrOrange;
        else if(globalObjectCount >= 800)
            globalColor = clrYellow;
        else
            globalColor = clrLime;
        
        DrawLabelAt("Draw_Global", "Total: " + globalText, startX, m_y + (row++ * m_rowHeight), globalColor);

        // --- Alert Level ---
        string alertText = "NORMAL";
        color alertColor = clrLime;
        if(alertLevel >= 3) { alertText = "EMERGENCY"; alertColor = clrRed; }
        else if(alertLevel >= 2) { alertText = "CRITICAL"; alertColor = clrOrangeRed; }
        else if(alertLevel >= 1) { alertText = "WARNING"; alertColor = clrYellow; }
        
        DrawLabelAt("Draw_Alert", "Alert: " + alertText, startX, m_y + (row++ * m_rowHeight), alertColor);

        // --- Per-Strategy Breakdown ---
        DrawLabelAt("Draw_Sep2", "--------------------", startX, m_y + (row++ * m_rowHeight), clrGray);
        DrawLabelAt("Draw_FIB", "Fibonacci: " + (string)fibonacciObjects, startX, m_y + (row++ * m_rowHeight), m_textColor);
        DrawLabelAt("Draw_SR", "S/R: " + (string)supportResObjects, startX, m_y + (row++ * m_rowHeight), m_textColor);
        DrawLabelAt("Draw_ICT", "ICT: " + (string)ictObjects, startX, m_y + (row++ * m_rowHeight), m_textColor);

        // --- Health Warning ---
        if(globalObjectCount >= 900)
        {
            string warning = "DRAWING LIMITED";
            DrawLabelAt("Draw_Warning", warning, startX, m_y + (row++ * m_rowHeight), clrOrangeRed);
        }

        ChartRedraw();
    }

    //+------------------------------------------------------------------+
    //| Draw label at specific position                                    |
    //+------------------------------------------------------------------+
    void DrawLabelAt(string name, string text, int x, int y, color clr)
    {
        string objName = m_prefix + name;
        if(ObjectFind(0, objName) < 0)
        {
            ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
        }
        
        ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
        ObjectSetString(0, objName, OBJPROP_TEXT, text);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, m_fontSize);
        ObjectSetString(0, objName, OBJPROP_FONT, m_fontName);
        ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
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
