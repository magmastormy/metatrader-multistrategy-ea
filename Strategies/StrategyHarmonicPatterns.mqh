//+------------------------------------------------------------------+
//| Harmonic Patterns Strategy v2.0                                  |
//| Enhanced O(n) scanner with confirmation and proper TP/SL         |
//| Copyright 2025, Advanced AI Coding Assistant                     |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_HARMONIC_PATTERNS_MQH__
#define __STRATEGY_HARMONIC_PATTERNS_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Visualization/ChartDrawingManager.mqh"

// Enhanced Harmonic Patterns Component Files
#include "HarmonicFiles/HarmonicPatternScanner.mqh"
#include "HarmonicFiles/HarmonicConfirmation.mqh"

//+------------------------------------------------------------------+
//| Harmonic Patterns Strategy Class v2.0                            |
//+------------------------------------------------------------------+
class CStrategyHarmonicPatterns : public CStrategyBase
{
private:
    // Enhanced Components
    CHarmonicPatternScanner*  m_scanner;
    CHarmonicConfirmation*    m_confirmation;
    CChartDrawingManager*     m_drawingManager;

    // Configuration
    double m_minPatternScore;
    int    m_lastBarProcessed;

    // Statistics
    int m_patternsDetected;
    int m_signalsGenerated;

public:
    CStrategyHarmonicPatterns(const string name = "Harmonic v2.0", int magic = 0);
    virtual ~CStrategyHarmonicPatterns();

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override;
    virtual void Deinit() override;
    virtual void OnTick() override;
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe);
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override;
    virtual string GetName() const override { return m_name; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_HARMONIC_PATTERNS; }

    // Configuration
    void SetMinConfidence(double conf) { m_minConfidence = conf; }
    void SetMinPatternScore(double score) { m_minPatternScore = score; }

private:
    void Cleanup();
    void DrawPatterns();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CStrategyHarmonicPatterns::CStrategyHarmonicPatterns(const string name, int magic) :
    CStrategyBase(name, magic),
    m_scanner(NULL),
    m_confirmation(NULL),
    m_drawingManager(NULL),
    m_minPatternScore(70.0),
    m_lastBarProcessed(0),
    m_patternsDetected(0),
    m_signalsGenerated(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CStrategyHarmonicPatterns::~CStrategyHarmonicPatterns()
{
    Cleanup();
}

//+------------------------------------------------------------------+
//| Cleanup helper                                                   |
//+------------------------------------------------------------------+
void CStrategyHarmonicPatterns::Cleanup()
{
    if(m_scanner != NULL) { delete m_scanner; m_scanner = NULL; }
    if(m_confirmation != NULL) { delete m_confirmation; m_confirmation = NULL; }
    if(m_drawingManager != NULL) { delete m_drawingManager; m_drawingManager = NULL; }
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
bool CStrategyHarmonicPatterns::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer)
{
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
        return false;

    // Initialize Pattern Scanner (O(n) efficient)
    m_scanner = new CHarmonicPatternScanner();
    if(m_scanner == NULL || !m_scanner.Initialize(symbol, timeframe))
    {
        Print("[HARMONIC v2.0] Failed to initialize Pattern Scanner");
        return false;
    }

    // Initialize Confirmation Engine
    m_confirmation = new CHarmonicConfirmation();
    if(m_confirmation == NULL || !m_confirmation.Initialize(symbol, timeframe))
    {
        Print("[HARMONIC v2.0] Failed to initialize Confirmation Engine");
        return false;
    }

    m_drawingManager = new CChartDrawingManager();
    if(m_drawingManager != NULL)
    {
        m_drawingManager.Initialize(symbol, timeframe, "HARM");
        SDrawingConfig config = m_drawingManager.GetConfiguration();
        config.enableSupplyDemand = true;
        config.enableSupportResistance = false;
        config.enableStructure = false;
        config.enableOrderBlocks = false;
        config.enableFVG = false;
        config.enableSignalMarkers = true;
        config.enableTrendLines = true;
        m_drawingManager.SetConfiguration(config);
    }

    PrintFormat("[HARMONIC v2.0] Strategy initialized for %s on %s", symbol, EnumToString(timeframe));
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void CStrategyHarmonicPatterns::Deinit()
{
    if(m_drawingManager != NULL)
        m_drawingManager.CleanupAll();
    Cleanup();
    CStrategyBase::Deinit();
}

//+------------------------------------------------------------------+
//| OnTick Processing                                                |
//+------------------------------------------------------------------+
void CStrategyHarmonicPatterns::OnTick()
{
    if(!m_is_enabled) return;
}

//+------------------------------------------------------------------+
//| OnNewBar Processing                                              |
//+------------------------------------------------------------------+
void CStrategyHarmonicPatterns::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(!m_is_enabled || symbol != m_symbol || timeframe != m_timeframe)
        return;

    int currentBar = iBars(m_symbol, m_timeframe);
    if(currentBar == m_lastBarProcessed)
        return;
    m_lastBarProcessed = currentBar;

    // Update scanner on new bar
    if(m_scanner != NULL)
    {
        m_scanner.Update();
        m_patternsDetected = m_scanner.GetPatternCount();
    }

    // Draw patterns
    if(m_drawingManager != NULL)
        m_drawingManager.CleanupOldObjects();
    DrawPatterns();
}

//+------------------------------------------------------------------+
//| Draw Harmonic Patterns on Chart                                  |
//+------------------------------------------------------------------+
void CStrategyHarmonicPatterns::DrawPatterns()
{
    if(m_scanner == NULL || m_drawingManager == NULL) return;

    int patternCount = m_scanner.GetPatternCount();
    for(int i = 0; i < patternCount; i++)
    {
        SHarmonicPatternData pattern;
        if(m_scanner.GetPatternAt(i, pattern) && pattern.isValid)
        {
            color patternColor = (pattern.direction == HARMONIC_BULLISH) ? clrDodgerBlue : clrCrimson;

            // Draw PRZ zone
            datetime zoneEnd = TimeCurrent();
            datetime zoneStart = pattern.dTime > 0 ? pattern.dTime : zoneEnd - 3 * PeriodSeconds(m_timeframe);
            m_drawingManager.DrawZone(zoneStart, zoneEnd,
                                       pattern.przHigh, pattern.przLow,
                                       StringFormat("%s_PRZ", EnumToString(pattern.type)),
                                       patternColor, true, 70);

            // Draw XABCD legs
            m_drawingManager.DrawTrendLine(pattern.xTime, pattern.xPoint, pattern.aTime, pattern.aPoint, patternColor, 2, STYLE_SOLID);
            m_drawingManager.DrawTrendLine(pattern.aTime, pattern.aPoint, pattern.bTime, pattern.bPoint, patternColor, 2, STYLE_SOLID);
            m_drawingManager.DrawTrendLine(pattern.bTime, pattern.bPoint, pattern.cTime, pattern.cPoint, patternColor, 2, STYLE_SOLID);
            m_drawingManager.DrawTrendLine(pattern.cTime, pattern.cPoint, pattern.dTime, pattern.dPoint, patternColor, 2, STYLE_SOLID);

            // Annotate key points
            m_drawingManager.DrawTextLabel(pattern.xTime, pattern.xPoint, "X", patternColor, 8, ANCHOR_CENTER);
            m_drawingManager.DrawTextLabel(pattern.aTime, pattern.aPoint, "A", patternColor, 8, ANCHOR_CENTER);
            m_drawingManager.DrawTextLabel(pattern.bTime, pattern.bPoint, "B", patternColor, 8, ANCHOR_CENTER);
            m_drawingManager.DrawTextLabel(pattern.cTime, pattern.cPoint, "C", patternColor, 8, ANCHOR_CENTER);
            m_drawingManager.DrawTextLabel(pattern.dTime, pattern.dPoint, "D", patternColor, 8, ANCHOR_CENTER);

            // Add informational label near D
            string info = StringFormat("%s | %.0f%% | PRZ %.1f",
                                       EnumToString(pattern.type),
                                       pattern.strength,
                                       pattern.prz);
            m_drawingManager.DrawTextLabel(pattern.dTime, pattern.dPoint, info, patternColor, 9, ANCHOR_RIGHT);
        }
    }
}

//+------------------------------------------------------------------+
//| Get Signal - Harmonic Pattern with Confirmation                  |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategyHarmonicPatterns::GetSignal(double &confidence)
{
    confidence = 0.0;

    if(!m_is_enabled || !m_is_initialized)
        return TRADE_SIGNAL_NONE;

    if(m_scanner == NULL || m_confirmation == NULL)
        return TRADE_SIGNAL_NONE;

    // Update scanner
    m_scanner.Update();

    // Get best available pattern (choose stronger of bullish/bearish)
    SHarmonicPatternData bestPattern;
    SHarmonicPatternData bullPattern;
    SHarmonicPatternData bearPattern;
    bool hasBull = m_scanner.GetBestBullishPattern(bullPattern);
    bool hasBear = m_scanner.GetBestBearishPattern(bearPattern);

    if(!hasBull && !hasBear)
        return TRADE_SIGNAL_NONE;

    if(hasBull && hasBear)
        bestPattern = (bullPattern.strength >= bearPattern.strength) ? bullPattern : bearPattern;
    else if(hasBull)
        bestPattern = bullPattern;
    else
        bestPattern = bearPattern;

    // Check minimum pattern score
    if(bestPattern.strength < m_minPatternScore)
        return TRADE_SIGNAL_NONE;

    // Check for confirmation
    SHarmonicConfirmation confResult = m_confirmation.CheckConfirmation(bestPattern);

    if(!confResult.isValid)
        return TRADE_SIGNAL_NONE;

    // Calculate confidence
    confidence = bestPattern.strength * confResult.strength;
    confidence = MathMin(1.0, confidence);

    // Minimum confidence filter
    if(confidence < m_minConfidence)
        return TRADE_SIGNAL_NONE;

    ENUM_TRADE_SIGNAL result = TRADE_SIGNAL_NONE;

    if(bestPattern.direction == HARMONIC_BULLISH)
        result = TRADE_SIGNAL_BUY;
    else
        result = TRADE_SIGNAL_SELL;

    if(result != TRADE_SIGNAL_NONE)
    {
        m_signalsGenerated++;

        PrintFormat("[HARMONIC v2.0] %s: %s | Pattern: %s | Conf: %.1f%% | Strength: %.2f | %s",
                   m_symbol,
                   result == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   EnumToString(bestPattern.type),
                   confidence * 100,
                   bestPattern.strength,
                   confResult.description);
    }

    return result;
}

#endif // __STRATEGY_HARMONIC_PATTERNS_MQH__
