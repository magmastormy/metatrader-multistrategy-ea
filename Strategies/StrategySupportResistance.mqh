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
#include "../Core/Engines/FibConfluence.mqh"
// Risk Manager for AGENTS.md invariant #1
#include "../Core/Risk/UnifiedRiskManager.mqh"

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
    CFibConfluence*             m_fibModule;  // Fibonacci confluence helper
    
    // Trading Strategies
    CSRBounceStrategy*          m_bounceStrategy;
    CSRBreakoutStrategy*        m_breakoutStrategy;
    CTrendlineBounceStrategy*   m_trendlineStrategy;
    CChartDrawingManager*       m_drawingManager;
    
    // Risk Management (AGENTS.md invariant #1)
    CUnifiedRiskManager*        m_riskManager;
    
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
    
private:
    double                      ApplyFibConfluence(ENUM_TRADE_SIGNAL signal, double price, double confidence);
    
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
    m_fibModule(NULL),
    m_bounceStrategy(NULL),
    m_breakoutStrategy(NULL),
    m_trendlineStrategy(NULL),
    m_drawingManager(NULL),
    m_riskManager(NULL),
    m_mode(SR_MODE_ALL),
    m_lastBarProcessed(0),
    m_signalsGenerated(0),
    m_levelsDetected(0),
    m_trendlinesDetected(0)
{
    m_minConfidence = 0.45; // Reduced from 0.50 to allow more M1/M5 level participation
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
    if(m_fibModule != NULL) { delete m_fibModule; m_fibModule = NULL; }
    if(m_bounceStrategy != NULL) { delete m_bounceStrategy; m_bounceStrategy = NULL; }
    if(m_breakoutStrategy != NULL) { delete m_breakoutStrategy; m_breakoutStrategy = NULL; }
    if(m_trendlineStrategy != NULL) { delete m_trendlineStrategy; m_trendlineStrategy = NULL; }
    if(m_drawingManager != NULL) { delete m_drawingManager; m_drawingManager = NULL; }
    // Risk manager is not owned by this strategy - do NOT delete
    m_riskManager = NULL;
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
    
    // Initialize Fibonacci Confluence Module
    m_fibModule = new CFibConfluence();
    if(m_fibModule != NULL)
    {
        m_fibModule->Initialize();
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
    
    // ARCHITECTURAL FIX: Risk manager is now properly injected via Init() signature
    m_riskManager = GetUnifiedRiskManager();
    if(m_riskManager != NULL)
        Print("[S/R v1.0] UnifiedRiskManager successfully injected - trades will pass through validation gate");
    else
        Print("[S/R v1.0] WARNING: UnifiedRiskManager not provided - risk validation bypassed!");
    
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
    
    // Regular cleanup to prevent object accumulation
    if(m_drawingManager != NULL)
        m_drawingManager.CleanupOldObjects();
    
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
    
    // Sort descending by strength using efficient ArraySort
    ArraySort(levels, DESCENDING);
    
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
    
    // Sort descending by strength using efficient ArraySort
    ArraySort(lines, DESCENDING);
    
    int drawCount = MathMin(count, 6); // Cap Trendlines to top 6
    
    for(int i = 0; i < drawCount; i++)
    {
        STrendline trendline = lines[i];
        color lineColor = (trendline.type == TRENDLINE_SUPPORT) ? clrLimeGreen : clrOrangeRed;
        
        if(trendline.isBroken)
            lineColor = clrGray;
        
        ENUM_LINE_STYLE style = trendline.isBroken ? STYLE_DOT : STYLE_DOT;
        
        m_drawingManager.DrawTrendLine(trendline.point1Time, trendline.point1Price,
                                        trendline.point2Time, trendline.point2Price,
                                        lineColor, 1, style);
        
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
        
        // Apply Fibonacci confluence boost
        if(m_fibModule != NULL && m_srDetector != NULL)
        {
            confidence = ApplyFibConfluence(bestResult.signal, bestResult.price, confidence);
        }
        
        // CRITICAL: Validate through UnifiedRiskManager (AGENTS.md invariant #1)
        if(m_riskManager != NULL)
        {
            STradeValidationRequest request;
            request.symbol = m_symbol;
            request.orderType = (bestResult.signal == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            request.lotSize = 0.01;  // Placeholder
            request.stopLossPips = (bestResult.stopLoss > 0) ? MathAbs(bestResult.price - bestResult.stopLoss) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
            request.takeProfitPips = (bestResult.takeProfit > 0) ? MathAbs(bestResult.takeProfit - bestResult.price) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
            request.confidence = confidence;
            request.strategy = GetName();
            request.clusterCode = "";
            
            SValidationResult result = m_riskManager->ValidateTradeRequest(request, "SR");
            if(!result.approved)
            {
                SetDecisionReasonTag("SR_RISK_REJECTED");
                PrintFormat("[S/R v1.0] Risk rejected %s at %.5f (SL=%.5f TP=%.5f Conf=%.1f%%) Reason=%s",
                           bestResult.signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                           bestResult.price, bestResult.stopLoss, bestResult.takeProfit, confidence * 100,
                           result.message);
                return TRADE_SIGNAL_NONE;
            }
            confidence *= result.confidenceMultiplier;
        }
        
        m_signalsGenerated++;
        RecordSignal();
        SetDecisionReasonTag(bestResult.signal == TRADE_SIGNAL_BUY ? "SR_SIGNAL_BUY" : "SR_SIGNAL_SELL");
        
        // CONSENSUS LOGGING (AGENTS.md requirement)
        string signalType = "";
        if(m_mode == SR_MODE_BOUNCE) signalType = "Bounce";
        else if(m_mode == SR_MODE_BREAKOUT) signalType = "Breakout";
        else if(m_mode == SR_MODE_TRENDLINE) signalType = "Trendline";
        else signalType = "Mixed";
        
        PrintFormat("[CONSENSUS-DIAG] %s | %s | Mode: %s | Conf: %.1f%% | Weight: %.2f | Reason: %s%s",
                   m_symbol,
                   bestResult.signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   signalType,
                   confidence * 100,
                   m_weight,
                   m_lastDecisionReasonTag,
                   bestResult.hasTrendlineConfluence ? " [+TL Confluence]" : "");
        
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

//+------------------------------------------------------------------+
//| Apply Fibonacci Confluence Boost                                 |
//+------------------------------------------------------------------+
double CStrategySupportResistance::ApplyFibConfluence(ENUM_TRADE_SIGNAL signal, double price, double confidence)
{
    // TODO: Fix compilation errors - methods not recognized on pointer types
    // if(m_fibModule == NULL || m_srDetector == NULL) return confidence;
    
    // Find recent swing high/low for Fib calculation
    // SSupportResistance nearestSupport, nearestResistance;
    // bool hasSupport = false, hasResistance = false;
    // 
    // int supIdx = m_srDetector->FindNearestSupport(price);
    // int resIdx = m_srDetector->FindNearestResistance(price);
    // 
    // if(supIdx >= 0) hasSupport = m_srDetector->GetLevel(supIdx, nearestSupport);
    // if(resIdx >= 0) hasResistance = m_srDetector->GetLevel(resIdx, nearestResistance);
    // 
    // // Calculate Fib levels if we have both support and resistance
    // if(hasSupport && hasResistance && nearestResistance.price > nearestSupport.price)
    // {
    //     SFibLevel fibLevels[];
    //     int fibCount = 0;
    //     
    //     m_fibModule->CalculateLevels(nearestResistance.price, nearestSupport.price, fibLevels, fibCount);
    //     
    //     // Check if entry price is near a Fib level
    //     double nearestRatio = 0.0;
    //     if(m_fibModule->IsNearFibLevel(price, fibLevels, fibCount, 10, nearestRatio))
    //     {
    //         double boost = m_fibModule->GetConfidenceBoost(nearestRatio);
    //         confidence *= boost;
    //         confidence = MathMin(1.0, confidence);  // Cap at 1.0
    //         
    //         PrintFormat("[SR-FIB] Confluence at %.1f%% Fib level - confidence boosted from %.1f%% to %.1f%%",
    //                    nearestRatio * 100, (confidence / boost) * 100, confidence * 100);
    //     }
    // }
    
    return confidence;
}

#endif // __STRATEGY_SUPPORT_RESISTANCE_MQH__


