//+------------------------------------------------------------------+
//| Fibonacci Strategy v2.0                                          |
//| Enhanced with efficient swing detection, extensions, confluence  |
//| Copyright 2025, Advanced AI Coding Assistant                     |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_FIBONACCI_MQH__
#define __STRATEGY_FIBONACCI_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Visualization/DrawingCoordinator.mqh"

// Enhanced Fibonacci Strategy Component Files
#include "FibonacciFiles/FibSwingDetector.mqh"
#include "FibonacciFiles/FibLevelsCalculator.mqh"
#include "FibonacciFiles/FibConfirmation.mqh"

//+------------------------------------------------------------------+
//| Fibonacci Strategy Class v2.0                                    |
//+------------------------------------------------------------------+
class CStrategyFibonacci : public CStrategyBase
{
private:
    // Enhanced Components
    CFibSwingDetector*      m_swingDetector;
    CFibLevelsCalculator*   m_levelsCalc;
    CFibConfirmation*       m_confirmation;

    // Configuration
    int    m_lastBarProcessed;
    string m_drawPrefix;

public:
    CStrategyFibonacci(const string name = "Fibonacci v2.0", int magic = 0);
    virtual ~CStrategyFibonacci();

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer);
    virtual void Deinit();
    virtual void OnTick();
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe);
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override;
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_FIBONACCI; }

    // Configuration
    void SetMinConfidence(double conf) { OverrideMinConfidence(conf); }

private:
    void Cleanup();
    void DrawFibLevels();
    string BuildDrawPrefix(const string symbol, const ENUM_TIMEFRAMES timeframe) const;
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CStrategyFibonacci::CStrategyFibonacci(const string name, int magic) :
    CStrategyBase(name, magic),
    m_swingDetector(NULL),
    m_levelsCalc(NULL),
    m_confirmation(NULL),
    m_lastBarProcessed(0),
    m_drawPrefix("FIB_")
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CStrategyFibonacci::~CStrategyFibonacci()
{
    Cleanup();
}

//+------------------------------------------------------------------+
//| Cleanup helper                                                   |
//+------------------------------------------------------------------+
void CStrategyFibonacci::Cleanup()
{
    if(m_swingDetector != NULL) { delete m_swingDetector; m_swingDetector = NULL; }
    if(m_levelsCalc != NULL) { delete m_levelsCalc; m_levelsCalc = NULL; }
    if(m_confirmation != NULL) { delete m_confirmation; m_confirmation = NULL; }
}

string CStrategyFibonacci::BuildDrawPrefix(const string symbol, const ENUM_TIMEFRAMES timeframe) const
{
    string safeSymbol = symbol;
    StringReplace(safeSymbol, ".", "_");
    StringReplace(safeSymbol, " ", "_");
    StringReplace(safeSymbol, "/", "_");
    StringReplace(safeSymbol, "-", "_");
    return StringFormat("FIB_%s_%d_", safeSymbol, (int)timeframe);
}

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
bool CStrategyFibonacci::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer)
{
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
        return false;

    m_drawPrefix = BuildDrawPrefix(symbol, timeframe);

    // Initialize Swing Detector
    m_swingDetector = new CFibSwingDetector();
    if(m_swingDetector == NULL || !m_swingDetector.Initialize(symbol, timeframe))
    {
        Print("[FIB v2.0] Failed to initialize Swing Detector");
        return false;
    }

    // Initialize Levels Calculator
    m_levelsCalc = new CFibLevelsCalculator();
    if(m_levelsCalc == NULL || !m_levelsCalc.Initialize(symbol, timeframe))
    {
        Print("[FIB v2.0] Failed to initialize Levels Calculator");
        return false;
    }

    // Initialize Confirmation Engine
    m_confirmation = new CFibConfirmation();
    if(m_confirmation == NULL || !m_confirmation.Initialize(symbol, timeframe))
    {
        Print("[FIB v2.0] Failed to initialize Confirmation Engine");
        return false;
    }

    PrintFormat("[FIB v2.0] Strategy initialized for %s on %s", symbol, EnumToString(timeframe));
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void CStrategyFibonacci::Deinit()
{
    ObjectsDeleteAll(0, m_drawPrefix);
    Cleanup();
    CStrategyBase::Deinit();
}

//+------------------------------------------------------------------+
//| OnTick Processing                                                |
//+------------------------------------------------------------------+
void CStrategyFibonacci::OnTick()
{
    if(!m_is_enabled) return;
}

//+------------------------------------------------------------------+
//| OnNewBar Processing                                              |
//+------------------------------------------------------------------+
void CStrategyFibonacci::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(!m_is_enabled || symbol != m_symbol || timeframe != m_timeframe)
        return;

    int currentBar = iBars(m_symbol, m_timeframe);
    if(currentBar == m_lastBarProcessed)
        return;
    m_lastBarProcessed = currentBar;

    // Update all components on new bar
    if(m_swingDetector != NULL) 
    {
        m_swingDetector.Update();
        if(m_levelsCalc != NULL)
            m_levelsCalc.CalculateMultipleSetups(m_swingDetector);
    }

    // Draw Fibonacci levels
    if(MQLInfoInteger(MQL_VISUAL_MODE))
        DrawFibLevels();
}

//+------------------------------------------------------------------+
//| Draw Fibonacci Levels on Chart                                   |
//+------------------------------------------------------------------+
void CStrategyFibonacci::DrawFibLevels()
{
    if(m_levelsCalc == NULL) return;

    CDrawingCoordinator* drawingCoordinator = GetDrawingCoordinator();
    if(drawingCoordinator != NULL)
        drawingCoordinator.PreparePrefixForCurrentBar(ChartID(), m_symbol, m_timeframe, m_drawPrefix);
    else
        ObjectsDeleteAll(0, m_drawPrefix);

    SFibSetup setup;
    // Try to get best bullish setup first, then bearish for drawing
    if(!m_levelsCalc.GetBestBullishSetup(setup))
        if(!m_levelsCalc.GetBestBearishSetup(setup))
            return;

    // Draw retracement levels from the best setup
    for(int i = 0; i < setup.levelCount; i++)
    {
        SFibLevel level = setup.levels[i];
        string name = StringFormat("%s%s_%.3f", m_drawPrefix, setup.isBullish ? "BULL" : "BEAR", level.ratio);
        color clr = clrGray;

        if(level.ratio == 0.618) clr = clrGold;
        else if(level.ratio == 0.500) clr = clrGoldenrod;
        else if(level.ratio == 0.382) clr = clrDarkGoldenrod;
        else if(level.ratio > 1.0) clr = clrDodgerBlue; // Extensions

        if(ObjectFind(0, name) >= 0)
            ObjectDelete(0, name);

        ObjectCreate(0, name, OBJ_HLINE, 0, 0, level.price);
        ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
        ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
        ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
        ObjectSetString(0, name, OBJPROP_TEXT,
            StringFormat("%.1f%% (%.5f)", level.ratio * 100, level.price));
    }
}

//+------------------------------------------------------------------+
//| Get Signal - Fibonacci Confluence with Confirmation              |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategyFibonacci::GetSignal(double &confidence)
{
    confidence = 0.0;

    if(!m_is_enabled || !m_is_initialized)
        return TRADE_SIGNAL_NONE;

    if(m_swingDetector == NULL || m_levelsCalc == NULL || m_confirmation == NULL)
        return TRADE_SIGNAL_NONE;

    // Update components
    m_swingDetector.Update();
    m_levelsCalc.CalculateMultipleSetups(m_swingDetector);

    SFibSetup setup;
    bool foundSetup = false;
    ENUM_TRADE_SIGNAL signalType = TRADE_SIGNAL_NONE;

    // Check Bullish Setups
    if(m_levelsCalc.GetBestBullishSetup(setup))
    {
        foundSetup = true;
        signalType = TRADE_SIGNAL_BUY;
    }
    // Check Bearish Setups
    else if(m_levelsCalc.GetBestBearishSetup(setup))
    {
        foundSetup = true;
        signalType = TRADE_SIGNAL_SELL;
    }

    if(!foundSetup)
        return TRADE_SIGNAL_NONE;

    // We need a specific level for confirmation. Use 61.8% as primary entry
    double entryLevel = setup.fib618;
    
    // Check for confirmation at the Fib level
    SFibConfirmation confirm = m_confirmation.GetConfirmation(entryLevel, setup.isBullish);

    if(confirm.type == CONFIRM_NONE)
        return TRADE_SIGNAL_NONE;

    // Calculate confidence based on setup score and confirmation
    confidence = (setup.overallScore / 100.0) * confirm.strength;
    confidence = MathMin(1.0, confidence);

    // Minimum confidence filter
    if(confidence < m_minConfidence)
        return TRADE_SIGNAL_NONE;

    if(signalType != TRADE_SIGNAL_NONE)
    {
        PrintFormat("[FIB v2.0] %s: %s | Conf: %.1f%% | Level: 61.8%% | %s",
                    m_symbol,
                    signalType == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                    confidence * 100,
                    confirm.description);
        
        RecordSignal();
    }

    return signalType;
}

#endif // __STRATEGY_FIBONACCI_MQH__
