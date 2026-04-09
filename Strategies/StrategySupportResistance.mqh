//+------------------------------------------------------------------+
//| StrategySupportResistance.mqh                                    |
//| Support & Resistance + Trendlines Strategy v1.0                  |
//| Copyright 2025, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef __STRATEGY_SUPPORT_RESISTANCE_MQH__
#define __STRATEGY_SUPPORT_RESISTANCE_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Visualization/ChartDrawingManager.mqh"

// S/R Strategy Component Files
#include "SupportResistanceFiles/SupportResistanceDetector.mqh"
#include "SupportResistanceFiles/TrendlineDetector.mqh"
#include "SupportResistanceFiles/SRTradingStrategies.mqh"

//+------------------------------------------------------------------+
//| S/R Strategy Mode                                                |
//+------------------------------------------------------------------+
enum ENUM_SR_STRATEGY_MODE
{
    SR_MODE_BOUNCE,
    SR_MODE_BREAKOUT,
    SR_MODE_TRENDLINE,
    SR_MODE_ALL
};

//+------------------------------------------------------------------+
//| Support & Resistance Strategy Class                              |
//+------------------------------------------------------------------+
class CStrategySupportResistance : public CStrategyBase
{
private:
    // Core Components
    CSupportResistanceDetector* m_srDetector;
    CTrendlineDetector*         m_trendDetector;
    
    // Trading Strategies
    CSRBounceStrategy*          m_bounceStrategy;
    CSRBreakoutStrategy*        m_breakoutStrategy;
    CTrendlineBounceStrategy*   m_trendlineStrategy;
    CChartDrawingManager*       m_drawingManager;
    
    // Configuration
    ENUM_SR_STRATEGY_MODE       m_mode;
    int                         m_lastBarProcessed;
    
    // Statistics
    int                         m_signalsGenerated;
    int                         m_levelsDetected;
    int                         m_trendlinesDetected;
    
public:
                                CStrategySupportResistance(const string name = "S/R Strategy v1.0", int magic = 0);
    virtual                    ~CStrategySupportResistance();
    
    virtual bool                Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override;
    virtual void                Deinit() override;
    virtual void                OnTick() override;
    virtual void                OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe);
    virtual ENUM_TRADE_SIGNAL   GetSignal(double &confidence) override;
    virtual string              GetName() const override { return m_name; }
    virtual ENUM_STRATEGY_TYPE  GetType() const override { return STRATEGY_SUPPORT_RESISTANCE; }
    
    // Configuration
    void                        SetMode(ENUM_SR_STRATEGY_MODE mode) { m_mode = mode; }
    void                        SetMinConfidence(double conf) { m_minConfidence = conf; }
    
    // Getters
    int                         GetLevelCount() const { return m_levelsDetected; }
    int                         GetTrendlineCount() const { return m_trendlinesDetected; }
    
private:
    void                        Cleanup();
    void                        DrawLevels();
    void                        DrawTrendlines();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CStrategySupportResistance::CStrategySupportResistance(const string name, int magic) :
    CStrategyBase(name, magic),
    m_srDetector(NULL),
    m_trendDetector(NULL),
    m_bounceStrategy(NULL),
    m_breakoutStrategy(NULL),
    m_trendlineStrategy(NULL),
    m_drawingManager(NULL),
    m_mode(SR_MODE_ALL),
    m_lastBarProcessed(0),
    m_signalsGenerated(0),
    m_levelsDetected(0),
    m_trendlinesDetected(0)
{
    m_minConfidence = 0.50; // Lowered from 0.60: M1 levels rarely reach 0.60 on first valid touch
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CStrategySupportResistance::~CStrategySupportResistance()
{
    Cleanup();
}

//+------------------------------------------------------------------+
//| Cleanup                                                          |
//+------------------------------------------------------------------+
void CStrategySupportResistance::Cleanup()
{
    if(m_srDetector != NULL) { delete m_srDetector; m_srDetector = NULL; }
    if(m_trendDetector != NULL) { delete m_trendDetector; m_trendDetector = NULL; }
    if(m_bounceStrategy != NULL) { delete m_bounceStrategy; m_bounceStrategy = NULL; }
    if(m_breakoutStrategy != NULL) { delete m_breakoutStrategy; m_breakoutStrategy = NULL; }
    if(m_trendlineStrategy != NULL) { delete m_trendlineStrategy; m_trendlineStrategy = NULL; }
    if(m_drawingManager != NULL) { delete m_drawingManager; m_drawingManager = NULL; }
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
bool CStrategySupportResistance::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer)
{
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
        return false;
    
    // Initialize S/R Detector
    m_srDetector = new CSupportResistanceDetector();
    if(m_srDetector == NULL || !m_srDetector.Initialize(symbol, timeframe, 20, 3))
    {
        Print("[S/R v1.0] Failed to initialize S/R Detector");
        return false;
    }
    
    // Initialize Trendline Detector
    m_trendDetector = new CTrendlineDetector();
    if(m_trendDetector == NULL || !m_trendDetector.Initialize(symbol, timeframe, 3, 10))
    {
        Print("[S/R v1.0] Failed to initialize Trendline Detector");
        return false;
    }
    
    // Initialize Bounce Strategy
    m_bounceStrategy = new CSRBounceStrategy();
    if(m_bounceStrategy == NULL || !m_bounceStrategy.Initialize(symbol, timeframe, m_srDetector, m_trendDetector))
    {
        Print("[S/R v1.0] Failed to initialize Bounce Strategy");
        return false;
    }
    m_bounceStrategy.SetMinConfidence(m_minConfidence);
    
    // Initialize Breakout Strategy
    m_breakoutStrategy = new CSRBreakoutStrategy();
    if(m_breakoutStrategy == NULL || !m_breakoutStrategy.Initialize(symbol, timeframe, m_srDetector))
    {
        Print("[S/R v1.0] Failed to initialize Breakout Strategy");
        return false;
    }
    m_breakoutStrategy.SetMinConfidence(m_minConfidence);
    
    // Initialize Trendline Strategy
    m_trendlineStrategy = new CTrendlineBounceStrategy();
    if(m_trendlineStrategy == NULL || !m_trendlineStrategy.Initialize(symbol, timeframe, m_trendDetector, m_srDetector))
    {
        Print("[S/R v1.0] Failed to initialize Trendline Strategy");
        return false;
    }
    m_trendlineStrategy.SetMinConfidence(m_minConfidence);
    
    // Initial detection
    m_srDetector.DetectLevels(200);
    m_trendDetector.DetectTrendlines(100);
    
    m_levelsDetected = m_srDetector.GetLevelCount();
    m_trendlinesDetected = m_trendDetector.GetTrendlineCount();
    
    // Initialize drawing manager
    m_drawingManager = new CChartDrawingManager();
    if(m_drawingManager != NULL)
    {
        m_drawingManager.Initialize(symbol, timeframe, "SR");
        SDrawingConfig config = m_drawingManager.GetConfiguration();
        config.enableDrawing = true;
        config.enableSupportResistance = true;
        config.enableTrendLines = true;
        config.enableStructure = false;
        config.enableOrderBlocks = false;
        config.enableSupplyDemand = false;
        config.enableFVG = false;
        config.enableSignalMarkers = false;
        m_drawingManager.SetConfiguration(config);
    }
    
    PrintFormat("[S/R v1.0] Strategy initialized for %s on %s | Levels: %d | Trendlines: %d",
                symbol, EnumToString(timeframe), m_levelsDetected, m_trendlinesDetected);
    
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void CStrategySupportResistance::Deinit()
{
    if(m_drawingManager != NULL)
        m_drawingManager.CleanupOldObjects();
    Cleanup();
    CStrategyBase::Deinit();
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void CStrategySupportResistance::OnTick()
{
    if(!m_is_enabled) return;
}

//+------------------------------------------------------------------+
//| OnNewBar                                                         |
//+------------------------------------------------------------------+
void CStrategySupportResistance::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(!m_is_enabled || symbol != m_symbol || timeframe != m_timeframe)
        return;
    
    int currentBar = iBars(m_symbol, m_timeframe);
    if(currentBar == m_lastBarProcessed)
        return;
    m_lastBarProcessed = currentBar;
    
    // Update detectors
    if(m_srDetector != NULL)
    {
        m_srDetector.Update();
        m_levelsDetected = m_srDetector.GetLevelCount();
    }
    
    if(m_trendDetector != NULL)
    {
        m_trendDetector.Update();
        m_trendlinesDetected = m_trendDetector.GetTrendlineCount();
    }
    
    if(m_drawingManager != NULL)
        m_drawingManager.CleanupAll();
    
    DrawLevels();
    DrawTrendlines();
}

//+------------------------------------------------------------------+
//| Draw S/R Levels                                                  |
//+------------------------------------------------------------------+
void CStrategySupportResistance::DrawLevels()
{
    if(m_srDetector == NULL || m_drawingManager == NULL) return;
    
    SSupportResistance levels[];
    int count = 0;
    for(int i = 0; i < m_srDetector.GetLevelCount(); i++)
    {
        SSupportResistance lvl;
        // Filter out weak lines dynamically via gate (e.g. 0.4)
        if(m_srDetector.GetLevel(i, lvl) && lvl.strength >= 0.4)
        {
            ArrayResize(levels, count + 1);
            levels[count] = lvl;
            count++;
        }
    }
    
    // Bubble sort descending by strength
    for(int i=0; i<count-1; i++) {
        for(int j=0; j<count-i-1; j++) {
            if(levels[j].strength < levels[j+1].strength) {
                SSupportResistance temp = levels[j];
                levels[j] = levels[j+1];
                levels[j+1] = temp;
            }
        }
    }
    
    int drawCount = MathMin(count, 8); // Cap S/R levels to top 8
    
    for(int i = 0; i < drawCount; i++)
    {
        SSupportResistance level = levels[i];
        color levelColor = level.isSupport ? clrDodgerBlue : clrCrimson;
        
        if(level.isBroken)
            levelColor = clrGray;
        else if(level.roleReversed)
            levelColor = clrGold;
        
        string label = StringFormat("%s %.0f%% (T:%d)",
                                    level.isSupport ? "Sup" : "Res",
                                    level.strength * 100.0,
                                    level.touches);
        
        // Pass price as string tag label
        m_drawingManager.DrawHorizontalLevel(level.price, levelColor, label, STYLE_DOT, 1, true);
    }
}

//+------------------------------------------------------------------+
//| Draw Trendlines                                                  |
//+------------------------------------------------------------------+
void CStrategySupportResistance::DrawTrendlines()
{
    if(m_trendDetector == NULL || m_drawingManager == NULL) return;
    
    STrendline lines[];
    int count = 0;
    for(int i = 0; i < m_trendDetector.GetTrendlineCount(); i++)
    {
        STrendline line;
        if(m_trendDetector.GetTrendline(i, line) && line.isValid)
        {
            ArrayResize(lines, count + 1);
            lines[count] = line;
            count++;
        }
    }
    
    // Bubble sort descending by strength
    for(int i=0; i<count-1; i++) {
        for(int j=0; j<count-i-1; j++) {
            if(lines[j].strength < lines[j+1].strength) {
                STrendline temp = lines[j];
                lines[j] = lines[j+1];
                lines[j+1] = temp;
            }
        }
    }
    
    int drawCount = MathMin(count, 6); // Cap Trendlines to top 6
    
    for(int i = 0; i < drawCount; i++)
    {
        STrendline trendline = lines[i];
        color lineColor = (trendline.type == TRENDLINE_SUPPORT) ? clrLimeGreen : clrOrangeRed;
        
        if(trendline.isBroken)
            lineColor = clrGray;
        
        ENUM_LINE_STYLE style = trendline.isBroken ? STYLE_DASHDOT : STYLE_SOLID;
        
        string nameID = StringFormat("TL_%d", i);
        // In the absence of a proper ID param in drawing mgr wrapper, assume it creates its own.
        // If the wrapper needs unique names, DrawTrendLine might need one, but looking at usage below, it's missing.
        m_drawingManager.DrawTrendLine(trendline.point1Time, trendline.point1Price,
                                        trendline.point2Time, trendline.point2Price,
                                        lineColor, 2, style);
        
        string label = StringFormat("%s %.0f%% (T:%d)",
                                    trendline.type == TRENDLINE_SUPPORT ? "TL Sup" : "TL Res",
                                    trendline.strength * 100.0,
                                    trendline.touches);
                                    
        m_drawingManager.DrawTextLabel(trendline.point2Time, trendline.point2Price, label, lineColor, 8, ANCHOR_LEFT);
    }
}

//+------------------------------------------------------------------+
//| Get Signal                                                       |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategySupportResistance::GetSignal(double &confidence)
{
    confidence = 0.0;
    SetDecisionReasonTag("SR_UNSET");
    
    if(!m_is_enabled || !m_is_initialized)
    {
        SetDecisionReasonTag("SR_DISABLED_OR_UNINIT");
        return TRADE_SIGNAL_NONE;
    }
    
    // Update components
    if(m_srDetector != NULL) m_srDetector.Update();
    if(m_trendDetector != NULL) m_trendDetector.Update();
    
    SSRSignalResult bestResult;
    bestResult.signal = TRADE_SIGNAL_NONE;
    bestResult.confidence = 0;
    
    // Check Bounce Strategy
    if((m_mode == SR_MODE_BOUNCE || m_mode == SR_MODE_ALL) && m_bounceStrategy != NULL)
    {
        SSRSignalResult bounceResult = m_bounceStrategy.GetSignal();
        if(bounceResult.signal != TRADE_SIGNAL_NONE && bounceResult.confidence > bestResult.confidence)
        {
            bestResult = bounceResult;
        }
    }
    
    // Check Breakout Strategy
    if((m_mode == SR_MODE_BREAKOUT || m_mode == SR_MODE_ALL) && m_breakoutStrategy != NULL)
    {
        SSRSignalResult breakoutResult = m_breakoutStrategy.GetSignal();
        if(breakoutResult.signal != TRADE_SIGNAL_NONE && breakoutResult.confidence > bestResult.confidence)
        {
            bestResult = breakoutResult;
        }
    }
    
    // Check Trendline Strategy
    if((m_mode == SR_MODE_TRENDLINE || m_mode == SR_MODE_ALL) && m_trendlineStrategy != NULL)
    {
        SSRSignalResult trendlineResult = m_trendlineStrategy.GetSignal();
        if(trendlineResult.signal != TRADE_SIGNAL_NONE && trendlineResult.confidence > bestResult.confidence)
        {
            bestResult = trendlineResult;
        }
    }
    
    if(bestResult.signal != TRADE_SIGNAL_NONE)
    {
        confidence = bestResult.confidence;
        m_signalsGenerated++;
        SetDecisionReasonTag(bestResult.signal == TRADE_SIGNAL_BUY ? "SR_SIGNAL_BUY" : "SR_SIGNAL_SELL");
        RecordSignal();
        
        PrintFormat("[S/R v1.0] %s: %s | Conf: %.1f%% | %s%s",
                   m_symbol,
                   bestResult.signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   confidence * 100,
                   bestResult.reason,
                   bestResult.hasTrendlineConfluence ? " [+TL Confluence]" : "");
    }
    else
    {
        SetDecisionReasonTag("SR_NO_SIGNAL");
    }
    
    return bestResult.signal;
}

#endif // __STRATEGY_SUPPORT_RESISTANCE_MQH__
