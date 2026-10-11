// Copyright 2025, Multi-Strategy EA
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef STRATEGY_SUPPORT_RESISTANCE_MQH
#define STRATEGY_SUPPORT_RESISTANCE_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Visualization/ChartDrawingManager.mqh"
#include "../Core/Engines/FibConfluence.mqh"
// Risk gate for entries (AGENTS.md invariant #1)
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "../Core/Engines/HurstEngine.mqh"
#include "../Core/Risk/VPINFilter.mqh"
#include "../Core/Utils/SubsystemLogger.mqh"

#include "SupportResistanceFiles/SupportResistanceDetector.mqh"
#include "SupportResistanceFiles/TrendlineDetector.mqh"
#include "SupportResistanceFiles/SRTradingStrategies.mqh"

enum ENUM_SR_STRATEGY_MODE
{
    SR_MODE_BOUNCE,
    SR_MODE_BREAKOUT,
    SR_MODE_TRENDLINE,
    SR_MODE_ALL
};

class CStrategySupportResistance : public CStrategyBase
{
private:
    CSupportResistanceDetector* m_srDetector;
    CTrendlineDetector*         m_trendDetector;
    CFibConfluence*             m_fibModule;  // Fibonacci confluence helper
    int                         m_atrHandle;  // Cached ATR handle from CIndicatorManager
    
    CSRBounceStrategy*          m_bounceStrategy;
    CSRBreakoutStrategy*        m_breakoutStrategy;
    CTrendlineBounceStrategy*   m_trendlineStrategy;
    CChartDrawingManager*       m_drawingManager;
    
        CSubsystemLogger*           m_logger;  // Subsystem logger for drawing diagnostics

    // Per-symbol engine references (not owned)
    CHurstEngine*               m_hurstEngine;
    CVPINFilter*                m_vpinFilter;

    ENUM_SR_STRATEGY_MODE       m_mode;
    int                         m_lastBarProcessed;
    int                         m_drawBarCounter;  // Batch 103: Throttle drawing
    bool                        m_drawOnChartSymbolOnly;  // Only draw when strategy symbol matches chart symbol
    
    int                         m_signalsGenerated;
    int                         m_levelsDetected;
    int                         m_trendlinesDetected;
    
public:
                                CStrategySupportResistance(const string name = "S/R Strategy v1.0", int magic = 0);
    virtual                    ~CStrategySupportResistance();
    
    virtual bool                Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override;
    virtual void                Deinit() override;
    virtual void                OnTick() override;
    virtual void                OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe);
    virtual ENUM_TRADE_SIGNAL   GetSignal(double &confidence) override;
    virtual string              GetName() const override { return m_name; }
    virtual ENUM_STRATEGY_TYPE  GetType() const override { return STRATEGY_SUPPORT_RESISTANCE; }

    void SetHurstEngine(CHurstEngine* engine) { m_hurstEngine = engine; }
    void SetVPINFilter(CVPINFilter* filter) { m_vpinFilter = filter; }
    
private:
    double                      ApplyFibConfluence(ENUM_TRADE_SIGNAL signal, double price, double confidence);
    
    void                        SetMode(ENUM_SR_STRATEGY_MODE mode) { m_mode = mode; }
    void                        SetMinConfidence(double conf) { m_minConfidence = conf; }
    
    int                         GetLevelCount() const { return m_levelsDetected; }
    int                         GetTrendlineCount() const { return m_trendlinesDetected; }
    
private:
    void                        Cleanup();
    void                        DrawLevels();
    void                        DrawTrendlines();
};

CStrategySupportResistance::CStrategySupportResistance(const string name, int magic) :
    CStrategyBase(name, magic),
        m_srDetector(NULL),
        m_trendDetector(NULL),
        m_fibModule(NULL),
        m_bounceStrategy(NULL),
        m_breakoutStrategy(NULL),
        m_trendlineStrategy(NULL),
        m_drawingManager(NULL),
        m_logger(NULL),
        m_hurstEngine(NULL),
        m_vpinFilter(NULL),
        m_mode(SR_MODE_ALL),
        m_lastBarProcessed(0),
        m_drawBarCounter(0),
        m_drawOnChartSymbolOnly(true),
        m_signalsGenerated(0),
        m_levelsDetected(0),
        m_trendlinesDetected(0),
        m_atrHandle(INVALID_HANDLE)
{
    m_minConfidence = 0.45; // Reduced from 0.50 to allow more M1/M5 level participation
}

CStrategySupportResistance::~CStrategySupportResistance()
{
    Cleanup();
}

void CStrategySupportResistance::Cleanup()
{
    if(m_srDetector != NULL) { delete m_srDetector; m_srDetector = NULL; }
    if(m_trendDetector != NULL) { delete m_trendDetector; m_trendDetector = NULL; }
    if(m_fibModule != NULL) { delete m_fibModule; m_fibModule = NULL; }
    if(m_bounceStrategy != NULL) { delete m_bounceStrategy; m_bounceStrategy = NULL; }
    if(m_breakoutStrategy != NULL) { delete m_breakoutStrategy; m_breakoutStrategy = NULL; }
    if(m_trendlineStrategy != NULL) { delete m_trendlineStrategy; m_trendlineStrategy = NULL; }
    if(m_drawingManager != NULL) { delete m_drawingManager; m_drawingManager = NULL; }
    if(m_logger != NULL) { delete m_logger; m_logger = NULL; }  // Clean up logger
        // Hurst/VPIN engines are not owned - do NOT delete
        m_hurstEngine = NULL;
        m_vpinFilter = NULL;
    // ATR handle is cached from CIndicatorManager (shared ownership) - do NOT release
    m_atrHandle = INVALID_HANDLE;
}

bool CStrategySupportResistance::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer, void* unifiedRiskMgr)
{
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
        return false;
    
    m_srDetector = new CSupportResistanceDetector();
    if(m_srDetector == NULL || !m_srDetector.Initialize(symbol, timeframe, 20, 3))
    {
        Print("[S/R v1.0] Failed to initialize S/R Detector");
        return false;
    }
    
    m_trendDetector = new CTrendlineDetector();
    if(m_trendDetector == NULL || !m_trendDetector.Initialize(symbol, timeframe, 3, 10))
    {
        Print("[S/R v1.0] Failed to initialize Trendline Detector");
        return false;
    }
    
    m_fibModule = new CFibConfluence();
    if(m_fibModule != NULL)
    {
        (*m_fibModule).Initialize(m_symbol, m_timeframe);
    }

    // Initialize cached ATR handle for Fib confluence proximity checks
    m_atrHandle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, 14);
    if(m_atrHandle == INVALID_HANDLE)
    {
        Print("[S/R v1.0] WARNING: Failed to create cached ATR handle for Fib confluence");
    }
    
    m_bounceStrategy = new CSRBounceStrategy();
    if(m_bounceStrategy == NULL || !m_bounceStrategy.Initialize(symbol, timeframe, m_srDetector, m_trendDetector))
    {
        Print("[S/R v1.0] Failed to initialize Bounce Strategy");
        return false;
    }
    m_bounceStrategy.SetMinConfidence(m_minConfidence);
    
    m_breakoutStrategy = new CSRBreakoutStrategy();
    if(m_breakoutStrategy == NULL || !m_breakoutStrategy.Initialize(symbol, timeframe, m_srDetector))
    {
        Print("[S/R v1.0] Failed to initialize Breakout Strategy");
        return false;
    }
    m_breakoutStrategy.SetMinConfidence(m_minConfidence);
    
    m_trendlineStrategy = new CTrendlineBounceStrategy();
    if(m_trendlineStrategy == NULL || !m_trendlineStrategy.Initialize(symbol, timeframe, m_trendDetector, m_srDetector))
    {
        Print("[S/R v1.0] Failed to initialize Trendline Strategy");
        return false;
    }
    m_trendlineStrategy.SetMinConfidence(m_minConfidence);
    
    m_srDetector.DetectLevels(300);  // Increased from 200 to 300 for deeper historical context
    m_trendDetector.DetectTrendlines(100);
    
    m_levelsDetected = m_srDetector.GetLevelCount();
    m_trendlinesDetected = m_trendDetector.GetTrendlineCount();
    
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
    
    m_logger = new CSubsystemLogger();
    if(m_logger != NULL)
    {
        m_logger.Initialize(symbol, "");
        m_logger.Log(LOG_DRAWING, StringFormat("[INIT] S/R Strategy initialized | Symbol=%s TF=%s Levels=%d Trendlines=%d",
                                                symbol, EnumToString(timeframe), m_levelsDetected, m_trendlinesDetected));
    }
    
    // Risk manager arrives through CStrategyBase::Init(); with none injected the gate below is skipped (fail-open).
        if(GetUnifiedRiskManager() != NULL)
            Print("[S/R v1.0] UnifiedRiskManager successfully injected - trades will pass through validation gate");
        else
            Print("[S/R v1.0] WARNING: UnifiedRiskManager not provided - risk validation bypassed!");
    
    PrintFormat("[S/R v1.0] Strategy initialized for %s on %s | Levels: %d | Trendlines: %d",
                symbol, EnumToString(timeframe), m_levelsDetected, m_trendlinesDetected);
    
    return true;
}

void CStrategySupportResistance::Deinit()
{
    if(m_drawingManager != NULL)
        m_drawingManager.CleanupOldObjects();
    Cleanup();
    CStrategyBase::Deinit();
}

void CStrategySupportResistance::OnTick()
{
    if(!m_is_enabled) return;
}

void CStrategySupportResistance::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(!m_is_enabled || symbol != m_symbol || timeframe != m_timeframe)
        return;
    
    int currentBar = iBars(m_symbol, m_timeframe);
    if(currentBar == m_lastBarProcessed)
        return;
    m_lastBarProcessed = currentBar;
    
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
    
    static int s_diagBarCount = 0;
    s_diagBarCount++;
    if(s_diagBarCount % 10 == 0 && m_logger != NULL)
    {
        m_logger.Log(LOG_DRAWING, StringFormat("[BAR-%d] Symbol=%s TF=%s | Levels=%d Trendlines=%d DrawingMgr=%s",
                                                currentBar, symbol, EnumToString(timeframe),
                                                m_levelsDetected, m_trendlinesDetected,
                                                (m_drawingManager != NULL) ? "READY" : "NULL"));
    }
    
    // Regular cleanup to prevent object accumulation
    if(m_drawingManager != NULL)
        m_drawingManager.CleanupOldObjects();

    // Draw every 2 bars: CleanupOldObjects() runs each bar, so a wider gap let cleanup delete objects between draws.
    m_drawBarCounter++;
    if(m_drawBarCounter % 2 == 0)
    {
        DrawLevels();
        DrawTrendlines();
    }
}

void CStrategySupportResistance::DrawLevels()
{
    if(m_drawOnChartSymbolOnly && m_symbol != _Symbol)
        return;
    if(m_srDetector == NULL || m_drawingManager == NULL) return;
    
    SSupportResistance levels[];
    int count = 0;
    for(int i = 0; i < m_srDetector.GetLevelCount(); i++)
    {
        SSupportResistance lvl;
        if(m_srDetector.GetLevel(i, lvl) && lvl.strength >= 0.4)
        {
            ArrayResize(levels, count + 1);
            levels[count] = lvl;
            count++;
        }
    }
    
    static int s_drawLevelCount = 0;
    s_drawLevelCount++;
    if(s_drawLevelCount % 5 == 0 && m_logger != NULL)
    {
        m_logger.Log(LOG_DRAWING, StringFormat("[DRAW-LEVELS] Total=%d PassedFilter=%d WillDraw=%d StrengthThreshold=0.4",
                                                m_srDetector.GetLevelCount(), count, MathMin(count, 8)));
        
        if(count > 0)
        {
            string levelDetails = "";
            int logCount = MathMin(count, 3); // Log first 3 levels
            for(int j = 0; j < logCount; j++)
            {
                SSupportResistance lvl;
                if(m_srDetector.GetLevel(j, lvl))
                {
                    levelDetails += StringFormat("L%d: Price=%.5f Str=%.2f Type=%s | ",
                                                 j+1, lvl.price, lvl.strength,
                                                 lvl.isSupport ? "SUP" : "RES");
                }
            }
            m_logger.Log(LOG_DRAWING, StringFormat("[LEVEL-DETAILS] %s", levelDetails));
        }
    }
    
    // Note: ArraySort sorts ascending by default, so we reverse after sorting
    ArraySort(levels);
    ArrayReverse(levels);
    
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
        
        bool drawn = m_drawingManager.DrawHorizontalLevel(level.price, levelColor, label, STYLE_DOT, 1, true);
        
        if(i == 0 && s_drawLevelCount % 10 == 0 && m_logger != NULL)
        {
            m_logger.Log(LOG_DRAWING, StringFormat("[DRAW-RESULT] Level=%.5f Color=%s Label='%s' Success=%s",
                                                    level.price,
                                                    (level.isSupport ? "BLUE" : "RED"),
                                                    label,
                                                    drawn ? "YES" : "NO"));
        }
    }
}

void CStrategySupportResistance::DrawTrendlines()
{
    if(m_drawOnChartSymbolOnly && m_symbol != _Symbol)
        return;
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
    
    // Note: ArraySort sorts ascending by default, so we reverse after sorting
    ArraySort(lines);
    ArrayReverse(lines);
    
    int drawCount = MathMin(count, 6); // Cap Trendlines to top 6
    
    for(int i = 0; i < drawCount; i++)
    {
        STrendline trendline = lines[i];
        color lineColor = (trendline.type == TRENDLINE_SUPPORT) ? clrLimeGreen : clrOrangeRed;
        
        if(trendline.isBroken)
            lineColor = clrGray;
        
        ENUM_LINE_STYLE style = trendline.isBroken ? STYLE_DOT : STYLE_SOLID;
        
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

ENUM_TRADE_SIGNAL CStrategySupportResistance::GetSignal(double &confidence)
{
    confidence = 0.0;
    SetDecisionReasonTag("SR_UNSET");
    
    if(!m_is_enabled || !m_is_initialized)
    {
        SetDecisionReasonTag("SR_DISABLED_OR_UNINIT");
        return TRADE_SIGNAL_NONE;
    }
    
    if(m_srDetector != NULL) m_srDetector.Update();
    if(m_trendDetector != NULL) m_trendDetector.Update();

    // Hurst regime filter: S/R bounce works best in a mean-reverting regime.
    // Bounce mode is skipped while the market is strongly trending (H > 0.55).
    if(m_hurstEngine != NULL && m_hurstEngine.IsWarmedUp())
    {
        double hurst = m_hurstEngine.GetSnapshot().hurstValue;
        if(hurst > 0.55 && m_mode == SR_MODE_BOUNCE)
        {
            SetDecisionReasonTag("SR_HURST_TRENDING_NO_BOUNCE");
            return TRADE_SIGNAL_NONE;
        }
    }

    // VPIN toxicity filter: no signal while VPIN > 0.5.
    if(m_vpinFilter != NULL && m_vpinFilter.IsWarmedUp())
    {
        if(m_vpinFilter.GetVPIN() > 0.5)
        {
            SetDecisionReasonTag("SR_VPIN_TOXIC");
            return TRADE_SIGNAL_NONE;
        }
    }
    
    SSRSignalResult bestResult;
    bestResult.signal = TRADE_SIGNAL_NONE;
    bestResult.confidence = 0;
    
    if((m_mode == SR_MODE_BOUNCE || m_mode == SR_MODE_ALL) && m_bounceStrategy != NULL)
    {
        SSRSignalResult bounceResult = m_bounceStrategy.GetSignal();
        if(bounceResult.signal != TRADE_SIGNAL_NONE && bounceResult.confidence > bestResult.confidence)
        {
            bestResult = bounceResult;
        }
    }
    
    if((m_mode == SR_MODE_BREAKOUT || m_mode == SR_MODE_ALL) && m_breakoutStrategy != NULL)
    {
        SSRSignalResult breakoutResult = m_breakoutStrategy.GetSignal();
        if(breakoutResult.signal != TRADE_SIGNAL_NONE && breakoutResult.confidence > bestResult.confidence)
        {
            bestResult = breakoutResult;
        }
    }
    
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
        
        if(m_fibModule != NULL && m_srDetector != NULL)
        {
            confidence = ApplyFibConfluence(bestResult.signal, bestResult.entryPrice, confidence);
        }
        
        STradeValidationRequest request;
        request.symbol = m_symbol;
        request.orderType = (bestResult.signal == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        // Lot size is an execution parameter, not a signal-quality one: the placeholder is the broker
        // minimum so the validation gate cannot reject on size before CPositionSizer sizes the trade (invariant #1).
        double brokerMinLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
        if(brokerMinLot <= 0.0) brokerMinLot = 0.01;
        request.lotSize = brokerMinLot;
        PrintFormat("[S/R-LOT-DEFERRED] Lot validation deferred to risk manager | placeholder=%.3f (broker min)",
                    brokerMinLot);
        request.stopLossPips = (bestResult.stopLoss > 0) ? MathAbs(bestResult.entryPrice - bestResult.stopLoss) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
        request.takeProfitPips = (bestResult.takeProfit1 > 0) ? MathAbs(bestResult.takeProfit1 - bestResult.entryPrice) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
        request.confidence = confidence;
        request.strategy = GetName();
        request.clusterCode = "";

        SetProposedStops(request.stopLossPips, request.takeProfitPips); // FINDING 0
        if(!ValidateWithRiskManager(request, "SR", confidence))
            return TRADE_SIGNAL_NONE;
        
        // Consensus logging (AGENTS.md requirement)
        string signalType = "";
        if(m_mode == SR_MODE_BOUNCE) signalType = "Bounce";
        else if(m_mode == SR_MODE_BREAKOUT) signalType = "Breakout";
        else if(m_mode == SR_MODE_TRENDLINE) signalType = "Trendline";
        else signalType = "Mixed";
        
        LogConsensusDiag(bestResult.signal, StringFormat("Mode: %s", signalType), confidence, bestResult.hasTrendlineConfluence ? " [+TL Confluence]" : "");
        
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

double CStrategySupportResistance::ApplyFibConfluence(ENUM_TRADE_SIGNAL signal, double price, double confidence)
{
    if(m_fibModule == NULL || m_srDetector == NULL) return confidence;

    // Find nearest support and resistance for Fib swing range
    SSupportResistance nearestSupport, nearestResistance;
    bool hasSupport = false, hasResistance = false;

    int supIdx = m_srDetector.FindNearestSupport(price);
    int resIdx = m_srDetector.FindNearestResistance(price);

    if(supIdx >= 0) hasSupport = m_srDetector.GetLevel(supIdx, nearestSupport);
    if(resIdx >= 0) hasResistance = m_srDetector.GetLevel(resIdx, nearestResistance);

    // Need both support and resistance to calculate Fib levels
    if(!hasSupport || !hasResistance) return confidence;
    if(nearestResistance.price <= nearestSupport.price) return confidence;

    SFibLevel fibLevels[];
    int fibCount = 0;

    (*m_fibModule).CalculateLevels(nearestResistance.price, nearestSupport.price, fibLevels, fibCount);

    if(fibCount == 0) return confidence;

    // Get current ATR from cached handle (shared, owned by CIndicatorManager)
    if(m_atrHandle == INVALID_HANDLE) return confidence;

    double atrBuf[];
    ArraySetAsSeries(atrBuf, true);
    double atr = 0.0;
    if(CopyBuffer(m_atrHandle, 0, 1, 1, atrBuf) >= 1)
        atr = atrBuf[0];

    if(atr <= 0.0) return confidence;

    double proximityBonus = 0.0;

    for(int i = 0; i < fibCount; i++)
    {
        double distance = MathAbs(price - fibLevels[i].price);
        double halfAtr = 0.5 * atr;
        double fullAtr = 1.0 * atr;

        if(distance <= halfAtr)
        {
            proximityBonus += 0.10;  // Within 0.5 * ATR
            PrintFormat("[SR-FIB] Price %.5f within 0.5*ATR of %.1f%% Fib (%.5f) | +0.10 bonus",
                       price, fibLevels[i].ratio * 100.0, fibLevels[i].price);
        }
        else if(distance <= fullAtr)
        {
            proximityBonus += 0.05;  // Within 1.0 * ATR
            PrintFormat("[SR-FIB] Price %.5f within 1.0*ATR of %.1f%% Fib (%.5f) | +0.05 bonus",
                       price, fibLevels[i].ratio * 100.0, fibLevels[i].price);
        }
    }

    proximityBonus = MathMin(0.20, proximityBonus);

    double adjustedConfidence = MathMin(1.0, confidence + proximityBonus);

    if(proximityBonus > 0.0)
    {
        PrintFormat("[SR-FIB] Confluence bonus +%.2f applied | Conf: %.1f%% -> %.1f%% | Fib levels checked: %d",
                   proximityBonus, confidence * 100.0, adjustedConfidence * 100.0, fibCount);
    }

    return adjustedConfidence;
}

#endif // __STRATEGY_SUPPORT_RESISTANCE_MQH__


