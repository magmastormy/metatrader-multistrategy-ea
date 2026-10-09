//+------------------------------------------------------------------+
//| RiskDashboardPanel.mqh                                           |
//| On-chart risk monitoring panel - no external dashboard needed    |
//+------------------------------------------------------------------+
#property strict
#ifndef CORE_VISUALIZATION_RISK_DASHBOARD_PANEL_MQH
#define CORE_VISUALIZATION_RISK_DASHBOARD_PANEL_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/LogMacros.mqh"

//+------------------------------------------------------------------+
//| CRiskDashboardPanel                                              |
//+------------------------------------------------------------------+
class CRiskDashboardPanel
{
private:
    long   m_chartId;
    string m_prefix;
    int    m_corner;
    int    m_xOffset, m_yOffset;
    bool   m_visible;
    datetime m_lastUpdate;
    int    m_updateIntervalSec;
    
    // Cached metrics
    double m_portfolioRiskPct;
    double m_dailyRiskPct;
    double m_drawdownPct;
    int    m_positionsTotal;
    int    m_positionsLimit;
    double m_marginUsedPct;
    double m_freeMargin;
    string m_eaMode;
    double m_equity;
    double m_balance;
    double m_unrealizedPnl;
    
    // Thresholds for color coding
    struct SThresholds {
        double portfolioRiskWarn, portfolioRiskCrit;
        double dailyRiskWarn, dailyRiskCrit;
        double drawdownWarn, drawdownCrit;
        double marginWarn, marginCrit;
        int positionsWarn, positionsCrit;
    } m_thresholds;
    
    // Object names array for cleanup
    string m_objectNames[50];
    int    m_objectCount;
    
    // External input for max positions (set via init)
    int    m_maxPositionsTotal;

public:
    CRiskDashboardPanel() : m_chartId(0), m_prefix("RISK_DASH_"), m_corner(CORNER_RIGHT_UPPER),
                            m_xOffset(10), m_yOffset(10), m_visible(true), m_lastUpdate(0),
                            m_updateIntervalSec(5), m_objectCount(0), m_maxPositionsTotal(10) {
        // Default thresholds
        m_thresholds.portfolioRiskWarn = 60; m_thresholds.portfolioRiskCrit = 80;
        m_thresholds.dailyRiskWarn = 50; m_thresholds.dailyRiskCrit = 75;
        m_thresholds.drawdownWarn = 8; m_thresholds.drawdownCrit = 12;
        m_thresholds.marginWarn = 70; m_thresholds.marginCrit = 85;
        m_thresholds.positionsWarn = -1; m_thresholds.positionsCrit = -1; // Set dynamically
    }
    
    ~CRiskDashboardPanel() {
        Destroy();
    }
    
    // Initialize panel on chart
    void Init(long chartId, int corner = CORNER_RIGHT_UPPER, int xOffset = 10, int yOffset = 10, int maxPositionsTotal = 10) {
        m_chartId = chartId;
        m_corner = corner;
        m_xOffset = xOffset;
        m_yOffset = yOffset;
        m_maxPositionsTotal = maxPositionsTotal;
        
        // Set dynamic position thresholds
        m_thresholds.positionsWarn = (int)(m_maxPositionsTotal * 0.7);
        m_thresholds.positionsCrit = (int)(m_maxPositionsTotal * 0.9);
        
        CreateObjects();
        UpdateAll();
        Print("[RISK-DASH] Initialized on chart ", chartId);
    }
    
    // Update metrics from orchestrator
    void UpdateMetrics(double portfolioRisk, double dailyRisk, double dd, 
                       int posTotal, int posLimit, double marginPct, double freeMarg, 
                       string mode, double equity = 0, double balance = 0, double unrealized = 0) {
        m_portfolioRiskPct = portfolioRisk;
        m_dailyRiskPct = dailyRisk;
        m_drawdownPct = dd;
        m_positionsTotal = posTotal;
        m_positionsLimit = posLimit;
        m_marginUsedPct = marginPct;
        m_freeMargin = freeMarg;
        m_eaMode = mode;
        m_equity = equity;
        m_balance = balance;
        m_unrealizedPnl = unrealized;
    }
    
    // Update thresholds (call when config changes)
    void UpdateThresholds(double portWarn, double portCrit, double dailyWarn, double dailyCrit,
                          double ddWarn, double ddCrit, double marginWarn, double marginCrit) {
        m_thresholds.portfolioRiskWarn = portWarn; m_thresholds.portfolioRiskCrit = portCrit;
        m_thresholds.dailyRiskWarn = dailyWarn; m_thresholds.dailyRiskCrit = dailyCrit;
        m_thresholds.drawdownWarn = ddWarn; m_thresholds.drawdownCrit = ddCrit;
        m_thresholds.marginWarn = marginWarn; m_thresholds.marginCrit = marginCrit;
    }
    
    // Called from OnTimer
    void OnTimer() {
        if(!m_visible) return;
        if(TimeCurrent() - m_lastUpdate < m_updateIntervalSec) return;
        UpdateAll();
    }
    
    // Show/hide panel
    void SetVisible(bool v) { 
        m_visible = v; 
        UpdateVisibility(); 
    }
    
    bool IsVisible() const { return m_visible; }
    
    // Toggle visibility
    void Toggle() { SetVisible(!m_visible); }
    
    // Cleanup
    void Destroy() {
        if(m_chartId == 0) return;
        for(int i = 0; i < m_objectCount; i++) {
            if(m_objectNames[i] != "") ObjectDelete(m_chartId, m_objectNames[i]);
        }
        m_objectCount = 0;
    }

private:
    // Create all chart objects
    void CreateObjects() {
        m_objectCount = 0;
        
        // Background panel (rectangle label)
        AddRectLabel("BG", m_xOffset, m_yOffset, 280, 220, clrBlack, clrGray);
        
        // Title bar
        AddRectLabel("TITLE_BG", m_xOffset, m_yOffset, 280, 24, clrDimGray, clrDimGray);
        
        // Title text
        AddLabel("TITLE", "RISK DASHBOARD", 10, 3, 260, 20, clrWhite, 11);
        
        // Close button (X)
        AddLabel("CLOSE", "X", 255, 3, 20, 20, clrGray, 10);
        
        // Metric rows - labels and values
        struct SRow { string key; string label; int y; double warn; double crit; bool pct; };
        SRow rows[] = {
            {"PORTFOLIO", "Portfolio Risk", 30, m_thresholds.portfolioRiskWarn, m_thresholds.portfolioRiskCrit, true},
            {"DAILY", "Daily Risk", 50, m_thresholds.dailyRiskWarn, m_thresholds.dailyRiskCrit, true},
            {"DD", "Drawdown", 70, m_thresholds.drawdownWarn, m_thresholds.drawdownCrit, true},
            {"POS", "Positions", 90, m_thresholds.positionsWarn, m_thresholds.positionsCrit, false},
            {"MARGIN", "Margin Used", 110, m_thresholds.marginWarn, m_thresholds.marginCrit, true},
            {"FREEMARGIN", "Free Margin", 130, 0, 0, false},
            {"EQUITY", "Equity", 150, 0, 0, false},
            {"UNREALIZED", "Unrealized PnL", 170, 0, 0, false},
            {"MODE", "EA Mode", 190, 0, 0, false}
        };
        
        for(int i = 0; i < ArraySize(rows); i++) {
            SRow r = rows[i];
            AddLabel("LBL_" + r.key, r.label + ":", 15, r.y, 130, 18, clrGray, 9);
            AddLabel("VAL_" + r.key, "—", 150, r.y, 120, 18, clrWhite, 10);
        }
        
        // Separator lines
        for(int i = 1; i < ArraySize(rows); i++) {
            int y = rows[i].y - 5;
            AddHLine("SEP_" + IntegerToString(i), m_xOffset + 10, m_yOffset + y, clrDarkGray);
        }
    }
    
    void AddRectLabel(string suffix, int x, int y, int w, int h, color bgColor, color borderColor) {
        if(m_objectCount >= ArraySize(m_objectNames)) return;
        string name = m_prefix + suffix;
        ObjectCreate(m_chartId, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
        ObjectSetInteger(m_chartId, name, OBJPROP_CORNER, m_corner);
        ObjectSetInteger(m_chartId, name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(m_chartId, name, OBJPROP_YDISTANCE, y);
        ObjectSetInteger(m_chartId, name, OBJPROP_XSIZE, w);
        ObjectSetInteger(m_chartId, name, OBJPROP_YSIZE, h);
        ObjectSetInteger(m_chartId, name, OBJPROP_BGCOLOR, bgColor);
        ObjectSetInteger(m_chartId, name, OBJPROP_BORDER_COLOR, borderColor);
        ObjectSetInteger(m_chartId, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
        ObjectSetInteger(m_chartId, name, OBJPROP_ZORDER, 1000);
        ObjectSetInteger(m_chartId, name, OBJPROP_HIDDEN, true);
        ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(m_chartId, name, OBJPROP_SELECTED, false);
        ObjectSetInteger(m_chartId, name, OBJPROP_BACK, true);
        m_objectNames[m_objectCount++] = name;
    }
    
    void AddHLine(string suffix, int x, int y, color clr) {
        if(m_objectCount >= ArraySize(m_objectNames)) return;
        string name = m_prefix + suffix;
        ObjectCreate(m_chartId, name, OBJ_HLINE, 0, 0, 0);
        ObjectSetInteger(m_chartId, name, OBJPROP_CORNER, m_corner);
        ObjectSetInteger(m_chartId, name, OBJPROP_XDISTANCE, x);
        ObjectSetInteger(m_chartId, name, OBJPROP_YDISTANCE, y);
        ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(m_chartId, name, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(m_chartId, name, OBJPROP_WIDTH, 1);
        ObjectSetInteger(m_chartId, name, OBJPROP_ZORDER, 1000);
        ObjectSetInteger(m_chartId, name, OBJPROP_HIDDEN, true);
        ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
        m_objectNames[m_objectCount++] = name;
    }
    
    void AddLabel(string suffix, string text, int x, int y, int w, int h, 
                  color clr, int fontsize) {
        if(m_objectCount >= ArraySize(m_objectNames)) return;
        string name = m_prefix + suffix;
        ObjectCreate(m_chartId, name, OBJ_LABEL, 0, 0, 0);
        ObjectSetString(m_chartId, name, OBJPROP_TEXT, text);
        ObjectSetInteger(m_chartId, name, OBJPROP_CORNER, m_corner);
        ObjectSetInteger(m_chartId, name, OBJPROP_XDISTANCE, m_xOffset + x);
        ObjectSetInteger(m_chartId, name, OBJPROP_YDISTANCE, m_yOffset + y);
        ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(m_chartId, name, OBJPROP_FONTSIZE, fontsize);
        // Note: OBJPROP_BOLD is not available for OBJ_LABEL in MQL5
        ObjectSetInteger(m_chartId, name, OBJPROP_BACK, false);
        ObjectSetInteger(m_chartId, name, OBJPROP_SELECTABLE, false);
        ObjectSetInteger(m_chartId, name, OBJPROP_SELECTED, false);
        ObjectSetInteger(m_chartId, name, OBJPROP_HIDDEN, true);
        ObjectSetInteger(m_chartId, name, OBJPROP_ZORDER, 1002);
        m_objectNames[m_objectCount++] = name;
    }
    
    // Update all displayed values
    void UpdateAll() {
        UpdateValue("VAL_PORTFOLIO", m_portfolioRiskPct, "%", m_thresholds.portfolioRiskWarn, m_thresholds.portfolioRiskCrit);
        UpdateValue("VAL_DAILY", m_dailyRiskPct, "%", m_thresholds.dailyRiskWarn, m_thresholds.dailyRiskCrit);
        UpdateValue("VAL_DD", m_drawdownPct, "%", m_thresholds.drawdownWarn, m_thresholds.drawdownCrit);
        UpdateValue("VAL_POS", (double)m_positionsTotal, "/" + IntegerToString(m_positionsLimit), 
                    m_thresholds.positionsWarn, m_thresholds.positionsCrit);
        UpdateValue("VAL_MARGIN", m_marginUsedPct, "%", m_thresholds.marginWarn, m_thresholds.marginCrit);
        UpdateValue("VAL_FREEMARGIN", m_freeMargin, "", 0, 0);
        UpdateValue("VAL_EQUITY", m_equity, "", 0, 0);
        UpdateValue("VAL_UNREALIZED", m_unrealizedPnl, "", 0, 0, m_unrealizedPnl >= 0 ? clrLime : clrRed);
        UpdateValue("VAL_MODE", 0, "", 0, 0, clrWhite, m_eaMode);
        
        m_lastUpdate = TimeCurrent();
        ChartRedraw(m_chartId);
    }
    
    void UpdateValue(string suffix, double value, string suffixText, 
                     double warn, double crit, color overrideClr = clrWhite, string overrideText = "") {
        string name = m_prefix + suffix;
        string text = overrideText != "" ? overrideText : DoubleToString(value, 2) + suffixText;
        color clr = overrideClr;
        
        if(overrideText == "" && (warn > 0 || crit > 0)) {
            if(value >= crit) clr = clrRed;
            else if(value >= warn) clr = clrYellow;
            else clr = clrLime;
        } else if(overrideText == "" && value < 0 && suffixText == "") {
            clr = clrRed; // Negative PnL
        }
        
        ObjectSetString(m_chartId, name, OBJPROP_TEXT, text);
        ObjectSetInteger(m_chartId, name, OBJPROP_COLOR, clr);
    }
    
    void UpdateVisibility() {
        for(int i = 0; i < m_objectCount; i++) {
            if(m_objectNames[i] != "") {
                ObjectSetInteger(m_chartId, m_objectNames[i], OBJPROP_HIDDEN, !m_visible);
            }
        }
        ChartRedraw(m_chartId);
    }
};

#endif // CORE_VISUALIZATION_RISK_DASHBOARD_PANEL_MQH