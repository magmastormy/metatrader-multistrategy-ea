//+------------------------------------------------------------------+
//| Visual Dashboard — AI Monitoring HUD                             |
//| Multi-panel live dashboard for AI subsystems, regime, ensemble,  |
//| conformal, meta-labeler, hot-swap, features, and trade stats     |
//+------------------------------------------------------------------+
#ifndef CORE_VISUALIZATION_VISUAL_DASHBOARD_MQH
#define CORE_VISUALIZATION_VISUAL_DASHBOARD_MQH

#include "../Utils/Enums.mqh"
#include "../../AIModules/NextGenStrategyBrain.mqh"
#include "../../AIModules/NeuralNetworkStrategy.mqh"
#include "../../AIModules/EnsembleMetaLearner.mqh"
#include "../../AIModules/MetaLabeler.mqh"
#include "../../AIModules/OnnxBrain.mqh"
#include "../Engines/AIEngine.mqh"
#include "../Utils/DashboardBridge.mqh"

class CVisualDashboard
{
private:
    string m_prefix;
    int    m_fontSize;
    string m_fontName;

    // Color palette
    color  m_bgColor;
    color  m_headerColor;
    color  m_textColor;
    color  m_goodColor;
    color  m_warnColor;
    color  m_badColor;
    color  m_accentColor;
    color  m_dimColor;

    // Panel positions (4-column layout)
    int    m_col1X;   // Left column - System Health + Neural Net
    int    m_col2X;   // Middle-Left - AI Brain & Regime
    int    m_col3X;   // Middle-Right - Config & Advanced AI
    int    m_col4X;   // Right column - Trade Signals & Risk
    int    m_startY;
    int    m_rowH;
    int    m_panelW;

    // Data cache
    double m_cachedBalance;
    double m_cachedEquity;
    double m_cachedPnl;
    int    m_cachedTrades;
    int    m_cachedWins;

    void CreateLabel(const string name, const string text, const int x, const int y, const color clr, const int fontSize = 0)
    {
        string objName = m_prefix + name;
        if(ObjectFind(0, objName) < 0)
            ObjectCreate(0, objName, OBJ_LABEL, 0, 0, 0);
        ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
        ObjectSetString(0, objName, OBJPROP_TEXT, text);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, objName, OBJPROP_FONTSIZE, (fontSize > 0) ? fontSize : m_fontSize);
        ObjectSetString(0, objName, OBJPROP_FONT, m_fontName);
        ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
        ObjectSetInteger(0, objName, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
    }

    void CreateRect(const string name, const int x, const int y, const int width, const int height, const color clr)
    {
        string objName = m_prefix + name;
        if(ObjectFind(0, objName) < 0)
            ObjectCreate(0, objName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(0, objName, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(0, objName, OBJPROP_YDISTANCE, y);
        ObjectSetInteger(0, objName, OBJPROP_XSIZE, width);
        ObjectSetInteger(0, objName, OBJPROP_YSIZE, height);
        ObjectSetInteger(0, objName, OBJPROP_BGCOLOR, clr);
        ObjectSetInteger(0, objName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(0, objName, OBJPROP_COLOR, clrDarkGray);
        ObjectSetInteger(0, objName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    }

    // Draw a horizontal bar chart (0.0 to 1.0)
    void DrawBar(const string name, const int x, const int y, const double value, const int maxWidth, const color clr)
    {
        int barWidth = (int)(MathMax(0.0, MathMin(1.0, value)) * maxWidth);
        CreateRect(name + "_bg", x, y, maxWidth, 12, clrDarkSlateGray);
        if(barWidth > 0)
            CreateRect(name + "_fill", x, y, barWidth, 12, clr);
    }

    color GetHealthColor(const double ratio) const
    {
        if(ratio >= 0.97) return m_goodColor;
        if(ratio >= 0.93) return m_warnColor;
        return m_badColor;
    }

    color GetConfidenceColor(const double conf) const
    {
        if(conf >= 0.70) return m_goodColor;
        if(conf >= 0.50) return m_warnColor;
        return m_badColor;
    }

    color GetUncertaintyColor(const double unc) const
    {
        if(unc <= 0.30) return m_goodColor;
        if(unc <= 0.60) return m_warnColor;
        return m_badColor;
    }

    color GetSignalColor(const string signal) const
    {
        if(signal == "BUY") return m_goodColor;
        if(signal == "SELL") return m_badColor;
        return m_dimColor;
    }

    string RegimeName(const int regime) const
    {
        if(regime == 0) return "TREND";
        if(regime == 1) return "RANGE";
        if(regime == 2) return "VOLAT";
        if(regime == 3) return "SPIKE";
        return "???";
    }

public:
    CVisualDashboard(const string prefix = "AIDB_")
    {
        m_prefix = prefix;
        m_fontSize = 9;
        m_fontName = "Consolas";

        m_bgColor      = C'15,15,25';
        m_headerColor  = clrGold;
        m_textColor    = C'180,180,200';
        m_goodColor    = clrLime;
        m_warnColor    = clrYellow;
        m_badColor     = clrOrangeRed;
        m_accentColor  = clrCyan;
        m_dimColor     = C'100,100,120';

        m_col1X = 10;
        m_col2X = 260;
        m_col3X = 510;
        m_col4X = 760;
        m_startY = 30;
        m_rowH = 16;
        m_panelW = 240;
    }

    ~CVisualDashboard() { Cleanup(); }

    void Initialize() { Cleanup(); }

    // Master update — call every tick or every few seconds
    void Update(CNeuralNetworkStrategy *nn,
                CNextGenStrategyBrain *brain,
                CEnsembleMetaLearner *ensemble,
                CMetaLabeler *metaLabeler,
                COnnxBrain *onnx,
                CPythonBridge *pythonBridge,
                int activeStrats, int totalPositions,
                double balance, double equity,
                int nnTotalTrades, int nnWinningTrades,
                double totalPnl,
                const string currentSymbol,
                ENUM_TRADE_SIGNAL currentSignal,
                double signalConfidence)
    {
        // Cache values
        m_cachedBalance = balance;
        m_cachedEquity = equity;
        m_cachedPnl = totalPnl;
        m_cachedTrades = nnTotalTrades;
        m_cachedWins = nnWinningTrades;
        double eqRatio = (balance > 0) ? equity / balance : 1.0;
        double winRate = (nnTotalTrades > 0) ? (double)nnWinningTrades / (double)nnTotalTrades : 0.0;

        int row;

        // ====================================================================
        // COLUMN 1: System Health + Neural Network
        // ====================================================================
        row = 0;
        CreateRect("Bg1", m_col1X - 5, m_startY - 5, m_panelW, 480, m_bgColor);

        CreateLabel("H1_Title", "SYSTEM HEALTH", m_col1X, m_startY + row * m_rowH, m_headerColor, 11);
        row++;
        CreateLabel("H1_Sep", "==========================", m_col1X, m_startY + row * m_rowH, m_dimColor);
        row++;

        // Equity curve indicator
        CreateLabel("Health_Eq", "Equity/Balance:", m_col1X, m_startY + row * m_rowH, m_textColor);
        CreateLabel("Health_EqVal", DoubleToString(eqRatio * 100.0, 1) + "%", m_col1X + 120, m_startY + row * m_rowH, GetHealthColor(eqRatio));
        DrawBar("Health_EqBar", m_col1X, m_startY + (row + 1) * m_rowH, eqRatio, m_panelW - 10, GetHealthColor(eqRatio));
        row += 2;

        // Balance / Equity
        CreateLabel("Sys_Bal", "Balance: $" + DoubleToString(balance, 0), m_col1X, m_startY + row * m_rowH, m_textColor);
        CreateLabel("Sys_Eq", "Equity: $" + DoubleToString(equity, 0), m_col1X + 120, m_startY + row * m_rowH, m_textColor);
        row++;

        // P&L
        color pnlColor = (totalPnl >= 0) ? m_goodColor : m_badColor;
        CreateLabel("Sys_PnL", "P&L: $" + DoubleToString(totalPnl, 2), m_col1X, m_startY + row * m_rowH, pnlColor);
        CreateLabel("Sys_Trades", "Trades: " + (string)nnTotalTrades, m_col1X + 120, m_startY + row * m_rowH, m_textColor);
        row++;

        // Win rate
        CreateLabel("Sys_WR", "Win Rate:", m_col1X, m_startY + row * m_rowH, m_textColor);
        CreateLabel("Sys_WRVal", DoubleToString(winRate * 100.0, 1) + "%", m_col1X + 120, m_startY + row * m_rowH, GetConfidenceColor(winRate));
        DrawBar("Sys_WRBar", m_col1X, m_startY + (row + 1) * m_rowH, winRate, m_panelW - 10, GetConfidenceColor(winRate));
        row += 2;

        // Position info
        CreateLabel("Sys_Pos", "Open Positions: " + (string)totalPositions, m_col1X, m_startY + row * m_rowH, m_textColor);
        row++;
        CreateLabel("Sys_Sym", "Symbol: " + currentSymbol, m_col1X, m_startY + row * m_rowH, m_textColor);
        row++;

        // Drawdown
        double dd = (balance > 0) ? (1.0 - equity / balance) : 0.0;
        color ddColor = (dd <= 0.05) ? m_goodColor : (dd <= 0.10) ? m_warnColor : m_badColor;
        CreateLabel("Sys_DD", "Drawdown:", m_col1X, m_startY + row * m_rowH, m_textColor);
        CreateLabel("Sys_DDVal", DoubleToString(dd * 100.0, 1) + "%", m_col1X + 120, m_startY + row * m_rowH, ddColor);
        DrawBar("Sys_DDBar", m_col1X, m_startY + (row + 1) * m_rowH, MathMin(1.0, dd * 10), m_panelW - 10, ddColor);
        row += 2;

        row++;
        CreateLabel("H1_Sep2", "------- NEURAL NET --------", m_col1X, m_startY + row * m_rowH, m_accentColor);
        row++;

        if(nn != NULL)
        {
            CreateLabel("NN_Status", "Status: ACTIVE", m_col1X, m_startY + row * m_rowH, m_goodColor);
            row++;
            CreateLabel("NN_Labels", "Labels: " + (string)nn.GetCompletedTradesCount(), m_col1X, m_startY + row * m_rowH, m_textColor);
            CreateLabel("NN_Steps", "Steps: " + (string)nn.GetTrainingSteps(), m_col1X + 120, m_startY + row * m_rowH, m_textColor);
            row++;

            double nnConf = 0.0;
            ENUM_TRADE_SIGNAL nnSig = nn.GetNeuralSignal(nnConf);
            string sigText = "NONE";
            color sigColor = m_dimColor;
            if(nnSig == TRADE_SIGNAL_BUY) { sigText = "BUY"; sigColor = m_goodColor; }
            else if(nnSig == TRADE_SIGNAL_SELL) { sigText = "SELL"; sigColor = m_badColor; }
            CreateLabel("NN_Sig", "Signal:", m_col1X, m_startY + row * m_rowH, m_textColor);
            CreateLabel("NN_SigVal", sigText + " @ " + DoubleToString(nnConf * 100.0, 1) + "%", m_col1X + 120, m_startY + row * m_rowH, sigColor);
            row++;

            // Conformal quantile
            double confQ = nn.GetLastUncertainty();
            CreateLabel("NN_ConfQ", "Conformal Q:", m_col1X, m_startY + row * m_rowH, m_textColor);
            CreateLabel("NN_ConfQVal", DoubleToString(confQ, 3), m_col1X + 120, m_startY + row * m_rowH, GetUncertaintyColor(confQ));
            DrawBar("NN_ConfBar", m_col1X, m_startY + (row + 1) * m_rowH, confQ, m_panelW - 10, GetUncertaintyColor(confQ));
            row += 2;

            // Asset class
            CreateLabel("NN_Asset", "Asset Class: " + (string)nn.GetAssetClass(), m_col1X, m_startY + row * m_rowH, m_textColor);
            row++;
            CreateLabel("NN_BarK", "Barrier K: " + DoubleToString(nn.GetBarrierK(), 2), m_col1X, m_startY + row * m_rowH, m_textColor);
            CreateLabel("NN_BarV", "Vert Bars: " + (string)nn.GetBarrierVertBars(), m_col1X + 120, m_startY + row * m_rowH, m_textColor);
            row++;
        }
        else
        {
            CreateLabel("NN_Status", "Status: INACTIVE", m_col1X, m_startY + row * m_rowH, m_badColor);
            row += 3;
        }

        // ====================================================================
        // COLUMN 2: AI Brain / Transformer + Regime
        // ====================================================================
        row = 0;
        CreateRect("Bg2", m_col2X - 5, m_startY - 5, m_panelW, 480, m_bgColor);

        CreateLabel("H2_Title", "AI BRAIN & REGIME", m_col2X, m_startY + row * m_rowH, m_headerColor, 11);
        row++;
        CreateLabel("H2_Sep", "==========================", m_col2X, m_startY + row * m_rowH, m_dimColor);
        row++;

        if(brain != NULL && brain.IsInitialized())
        {
            CreateLabel("Brain_Status", "Brain: " + brain.GetRuntimeMode(), m_col2X, m_startY + row * m_rowH, m_accentColor);
            row++;

            // Uncertainty
            double unc = brain.GetCurrentUncertainty();
            string uncRec = "LOW";
            color uncColor = m_goodColor;
            if(unc >= 0.60) { uncRec = "HIGH"; uncColor = m_badColor; }
            else if(unc >= 0.30) { uncRec = "MEDIUM"; uncColor = m_warnColor; }
            CreateLabel("Brain_Unc", "Uncertainty:", m_col2X, m_startY + row * m_rowH, m_textColor);
            CreateLabel("Brain_UncVal", DoubleToString(unc * 100.0, 1) + "% [" + uncRec + "]", m_col2X + 120, m_startY + row * m_rowH, uncColor);
            DrawBar("Brain_UncBar", m_col2X, m_startY + (row + 1) * m_rowH, unc, m_panelW - 10, uncColor);
            row += 2;

            // Accuracy
            double acc = brain.GetAccuracy();
            CreateLabel("Brain_Acc", "Accuracy:", m_col2X, m_startY + row * m_rowH, m_textColor);
            CreateLabel("Brain_AccVal", DoubleToString(acc * 100.0, 1) + "%", m_col2X + 120, m_startY + row * m_rowH, GetConfidenceColor(acc));
            DrawBar("Brain_AccBar", m_col2X, m_startY + (row + 1) * m_rowH, acc, m_panelW - 10, GetConfidenceColor(acc));
            row += 2;

            // Trade count
            CreateLabel("Brain_Trades", "Total Trades:", m_col2X, m_startY + row * m_rowH, m_textColor);
            CreateLabel("Brain_TradesVal", (string)brain.GetTradeCount(), m_col2X + 120, m_startY + row * m_rowH, m_textColor);
            row++;

            // Mode details
            CreateLabel("Brain_Mode", "Mode: " + brain.GetRuntimeMode(), m_col2X, m_startY + row * m_rowH, m_textColor);
            row++;

            row++;
            CreateLabel("H2_Sep2", "------ FEATURE VECTOR ------", m_col2X, m_startY + row * m_rowH, m_accentColor);
            row++;
            CreateLabel("Feat_Size", "Features: 65 (57 base + 8 candle)", m_col2X, m_startY + row * m_rowH, m_goodColor);
            row++;
            CreateLabel("Feat_Candle", "New: PinBar Engulf Doji Hammer", m_col2X, m_startY + row * m_rowH, m_dimColor);
            row++;
            CreateLabel("Feat_Candle2", "Shooting Morning/Evening Star", m_col2X, m_startY + row * m_rowH, m_dimColor);
            row++;
            CreateLabel("Feat_Candle3", "Candle Body/Wick Ratios", m_col2X, m_startY + row * m_rowH, m_dimColor);
            row++;
        }
        else
        {
            CreateLabel("Brain_Status", "Brain: OFFLINE", m_col2X, m_startY + row * m_rowH, m_badColor);
            row += 8;
        }

        // ====================================================================
        // COLUMN 3: Ensemble, Meta-Labeler, Hot-Swap, Barrier
        // ====================================================================
        row = 0;
        CreateRect("Bg3", m_col3X - 5, m_startY - 5, m_panelW, 480, m_bgColor);

        CreateLabel("H3_Title", "ENSEMBLE & META", m_col3X, m_startY + row * m_rowH, m_headerColor, 11);
        row++;
        CreateLabel("H3_Sep", "==========================", m_col3X, m_startY + row * m_rowH, m_dimColor);
        row++;

        // Ensemble
        if(ensemble != NULL)
        {
            CreateLabel("Ens_Status", "Ensemble: ACTIVE", m_col3X, m_startY + row * m_rowH, m_goodColor);
            row++;
            CreateLabel("Ens_Models", "Models: " + (string)ensemble.GetActiveModelCount(), m_col3X, m_startY + row * m_rowH, m_textColor);
            row++;
            CreateLabel("Ens_Conf", "Confidence: " + DoubleToString(ensemble.GetConfidence() * 100.0, 1) + "%", m_col3X, m_startY + row * m_rowH, m_textColor);
            row++;

            row++;
            CreateLabel("H3_Sep2", "------ META-LABELER ------", m_col3X, m_startY + row * m_rowH, m_accentColor);
            row++;

            // Meta-Labeler
            if(metaLabeler != NULL)
            {
                CreateLabel("ML_Status", "Status: ACTIVE", m_col3X, m_startY + row * m_rowH, m_goodColor);
                row++;
                // Note: MetaLabeler methods may vary
                CreateLabel("ML_Note", "Connected", m_col3X, m_startY + row * m_rowH, m_dimColor);
                row++;
            }
            else
            {
                CreateLabel("ML_Status", "Status: INACTIVE", m_col3X, m_startY + row * m_rowH, m_dimColor);
                row += 2;
            }

            // Hot-Swap
            CreateLabel("H3_Sep3", "------ HOT-SWAP ---------", m_col3X, m_startY + row * m_rowH, m_accentColor);
            row++;
            CreateLabel("HS_Promo", "Promotion: --", m_col3X, m_startY + row * m_rowH, m_textColor);
            row++;
            CreateLabel("HS_DD", "DD Guard: --", m_col3X, m_startY + row * m_rowH, m_textColor);
            row++;
            CreateLabel("HS_Cooldown", "Cooldown: --", m_col3X, m_startY + row * m_rowH, m_textColor);
            row++;

            // Barrier / Conformal
            CreateLabel("H3_Sep4", "------ BARRIER/CONF ------", m_col3X, m_startY + row * m_rowH, m_accentColor);
            row++;
            CreateLabel("Bar_Width", "Min Width: --", m_col3X, m_startY + row * m_rowH, m_textColor);
            row++;
            CreateLabel("Bar_PerAsset", "Per-Asset-Class: --", m_col3X, m_startY + row * m_rowH, m_textColor);
            row++;
            CreateLabel("Conf_Regime", "Regime-Aware ACI: --", m_col3X, m_startY + row * m_rowH, m_textColor);
            row++;
            CreateLabel("Conf_ACI", "Adaptive ACI: --", m_col3X, m_startY + row * m_rowH, m_textColor);
            row++;

            // ONNX
            CreateLabel("H3_Sep5", "------ ONNX INFERENCE ----", m_col3X, m_startY + row * m_rowH, m_accentColor);
            row++;
            if(onnx != NULL)
            {
                CreateLabel("Onnx_Status", "ONNX: LOADED", m_col3X, m_startY + row * m_rowH, m_goodColor);
                row++;
                CreateLabel("Onnx_Note", "Model loaded", m_col3X, m_startY + row * m_rowH, m_dimColor);
                row++;
            }
            else
            {
                CreateLabel("Onnx_Status", "ONNX: NOT LOADED", m_col3X, m_startY + row * m_rowH, m_badColor);
                row += 2;
            }
        }
        else
        {
            CreateLabel("Ens_Status", "Ensemble: OFFLINE", m_col3X, m_startY + row * m_rowH, m_badColor);
            row += 3;
        }

        // ====================================================================
        // COLUMN 4: Trade Signals + Risk + Python Bridge
        // ====================================================================
        row = 0;
        CreateRect("Bg4", m_col4X - 5, m_startY - 5, m_panelW, 480, m_bgColor);

        CreateLabel("H4_Title", "SIGNALS & RISK", m_col4X, m_startY + row * m_rowH, m_headerColor, 11);
        row++;
        CreateLabel("H4_Sep", "==========================", m_col4X, m_startY + row * m_rowH, m_dimColor);
        row++;

        // Current Signal
        string sigText = "FLAT";
        color sigColor = m_dimColor;
        if(currentSignal == TRADE_SIGNAL_BUY) { sigText = "BUY"; sigColor = m_goodColor; }
        else if(currentSignal == TRADE_SIGNAL_SELL) { sigText = "SELL"; sigColor = m_badColor; }

        CreateLabel("Sig_Current", "Current Signal:", m_col4X, m_startY + row * m_rowH, m_textColor);
        CreateLabel("Sig_CurrVal", sigText, m_col4X + 100, m_startY + row * m_rowH, sigColor, 12);
        row++;
        CreateLabel("Sig_Conf", "Confidence:", m_col4X, m_startY + row * m_rowH, m_textColor);
        CreateLabel("Sig_ConfVal", DoubleToString(signalConfidence * 100.0, 1) + "%", m_col4X + 100, m_startY + row * m_rowH, GetConfidenceColor(signalConfidence));
        DrawBar("Sig_ConfBar", m_col4X, m_startY + (row + 1) * m_rowH, signalConfidence, m_panelW - 10, GetConfidenceColor(signalConfidence));
        row += 2;

        // Risk metrics
        CreateLabel("H4_Sep2", "------ RISK METRICS ------", m_col4X, m_startY + row * m_rowH, m_accentColor);
        row++;

        double riskPerTrade = (balance > 0 && totalPositions > 0) ? MathAbs(totalPnl) / balance * 100.0 : 0.0;
        color riskColor = (riskPerTrade <= 1.0) ? m_goodColor : (riskPerTrade <= 3.0) ? m_warnColor : m_badColor;
        CreateLabel("Risk_PerTrade", "Risk/Trade:", m_col4X, m_startY + row * m_rowH, m_textColor);
        CreateLabel("Risk_PerTradeVal", DoubleToString(riskPerTrade, 2) + "%", m_col4X + 100, m_startY + row * m_rowH, riskColor);
        row++;

        double portRisk = (balance > 0) ? (totalPositions * 0.5) : 0.0; // rough estimate
        color portRiskColor = (portRisk <= 5.0) ? m_goodColor : (portRisk <= 10.0) ? m_warnColor : m_badColor;
        CreateLabel("Risk_Port", "Portfolio Risk:", m_col4X, m_startY + row * m_rowH, m_textColor);
        CreateLabel("Risk_PortVal", DoubleToString(portRisk, 1) + "%", m_col4X + 100, m_startY + row * m_rowH, portRiskColor);
        DrawBar("Risk_PortBar", m_col4X, m_startY + (row + 1) * m_rowH, MathMin(1.0, portRisk / 20.0), m_panelW - 10, portRiskColor);
        row += 2;

        // Kelly / Position sizing
        double kellyF = (winRate > 0 && nnTotalTrades > 10) ? winRate - (1.0 - winRate) / (totalPnl != 0 ? MathAbs(totalPnl / nnTotalTrades) / 100.0 : 1.0) : 0.0;
        kellyF = MathMax(0.0, MathMin(1.0, kellyF));
        CreateLabel("Risk_Kelly", "Kelly Optimal:", m_col4X, m_startY + row * m_rowH, m_textColor);
        CreateLabel("Risk_KellyVal", DoubleToString(kellyF * 100.0, 1) + "%", m_col4X + 100, m_startY + row * m_rowH, m_accentColor);
        row++;

        // Margin usage
        double marginUsed = 0.0; // would need account info
        CreateLabel("Risk_Margin", "Margin Used:", m_col4X, m_startY + row * m_rowH, m_textColor);
        CreateLabel("Risk_MarginVal", DoubleToString(marginUsed, 1) + "%", m_col4X + 100, m_startY + row * m_rowH, m_textColor);
        row++;

        // Python Bridge Status
        CreateLabel("H4_Sep3", "------ PYTHON BRIDGE -----", m_col4X, m_startY + row * m_rowH, m_accentColor);
        row++;

        if(pythonBridge != NULL)
        {
            CreateLabel("Py_Status", "Status: CONNECTED", m_col4X, m_startY + row * m_rowH, m_goodColor);
            row++;
            CreateLabel("Py_Note", "Bridge active", m_col4X, m_startY + row * m_rowH, m_dimColor);
            row++;
        }
        else
        {
            CreateLabel("Py_Status", "Status: DISCONNECTED", m_col4X, m_startY + row * m_rowH, m_badColor);
            row++;
            CreateLabel("Py_Host", "Host: localhost", m_col4X, m_startY + row * m_rowH, m_dimColor);
            row++;
            CreateLabel("Py_Port", "Port: 8000", m_col4X, m_startY + row * m_rowH, m_dimColor);
            row++;
        }

        // Strategy Performance
        CreateLabel("H4_Sep4", "------ STRATEGY PERF -----", m_col4X, m_startY + row * m_rowH, m_accentColor);
        row++;

        // Active strategies
        CreateLabel("Strat_Count", "Active: " + (string)activeStrats + " / 16", m_col4X, m_startY + row * m_rowH, m_textColor);
        row++;

        // Performance indicator
        string healthStatus = (eqRatio >= 0.97) ? "EXCELLENT" : (eqRatio >= 0.93) ? "CAUTION" : "CRITICAL";
        color healthCol = (eqRatio >= 0.97) ? m_goodColor : (eqRatio >= 0.93) ? m_warnColor : m_badColor;
        CreateLabel("Strat_Health", "System Health: " + healthStatus, m_col4X, m_startY + row * m_rowH, healthCol);
        row++;

        // Timestamp
        row = 26;
        CreateLabel("H4_Sep5", "------ TIMESTAMP ---------", m_col4X, m_startY + row * m_rowH, m_accentColor);
        row++;
        string timestamp = "Updated: " + TimeToString(TimeCurrent(), TIME_SECONDS);
        CreateLabel("Bottom_Time", timestamp, m_col4X, m_startY + row * m_rowH, m_dimColor, 9);

        // ====================================================================
        // BOTTOM ROW: Summary
        // ====================================================================
        row = 28;
        CreateRect("BgBottom", m_col1X - 5, m_startY + row * m_rowH - 5, 995, 35, m_bgColor);
        CreateLabel("Bottom_Sep", "=====================================================================================", m_col1X, m_startY + row * m_rowH, m_dimColor);
        row++;

        string summary = "AI: " + (string)activeStrats + " active | Features: 65 | Health: " + healthStatus + 
                        " | Signal: " + sigText + " (" + DoubleToString(signalConfidence * 100.0, 1) + "%)" +
                        " | P&L: $" + DoubleToString(totalPnl, 2) + " | DD: " + DoubleToString(dd * 100.0, 1) + "%";
        CreateLabel("Bottom_Summary", summary, m_col1X, m_startY + row * m_rowH, m_textColor, 10);

        ChartRedraw();
    }

    void Cleanup()
    {
        ObjectsDeleteAll(0, m_prefix);
    }
};

#endif // CORE_VISUALIZATION_VISUAL_DASHBOARD_MQH
