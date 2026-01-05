//+------------------------------------------------------------------+
//| Fibonacci Strategy v2.0                                          |
//| Enhanced with efficient swing detection, extensions, confluence  |
//| Copyright 2025, Advanced AI Coding Assistant                     |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_FIBONACCI_MQH__
#define __STRATEGY_FIBONACCI_MQH__

#include "../Core/Strategy/StrategyBase.mqh"

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
    double m_minConfidence;
    int    m_lastBarProcessed;

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
    void SetMinConfidence(double conf) { m_minConfidence = conf; }

private:
    void Cleanup();
    void DrawFibLevels();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CStrategyFibonacci::CStrategyFibonacci(const string name, int magic) :
    CStrategyBase(name, magic),
    m_swingDetector(NULL),
    m_levelsCalc(NULL),
    m_confirmation(NULL),
    m_minConfidence(0.55),
    m_lastBarProcessed(0)
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

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
bool CStrategyFibonacci::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer)
{
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
        return false;

    // Initialize Swing Detector
    m_swingDetector = new CFibSwingDetector();
    if(m_swingDetector == NULL || !m_swingDetector.Initialize(symbol, timeframe))
    {
        Print("[FIB v2.0] Failed to initialize Swing Detector");
        return false;
    }

    // Initialize Levels Calculator
    m_levelsCalc = new CFibLevelsCalculator();
    if(m_levelsCalc == NULL || !m_levelsCalc.Initialize(symbol, timeframe, m_swingDetector))
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
    ObjectsDeleteAll(0, "FIB_");
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
    if(m_swingDetector != NULL) m_swingDetector.Update();
    if(m_levelsCalc != NULL) m_levelsCalc.Update();

    // Draw Fibonacci levels
    DrawFibLevels();
}

//+------------------------------------------------------------------+
//| Draw Fibonacci Levels on Chart                                   |
//+------------------------------------------------------------------+
void CStrategyFibonacci::DrawFibLevels()
{
    if(m_levelsCalc == NULL) return;

    // Draw retracement levels
    int levelCount = m_levelsCalc.GetLevelCount();
    for(int i = 0; i < levelCount; i++)
    {
        SFibLevel level;
        if(m_levelsCalc.GetLevel(i, level) && level.isActive)
        {
            string name = StringFormat("FIB_%s_%.3f", level.isBullish ? "BULL" : "BEAR", level.ratio);
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
    m_levelsCalc.Update();

    // Get best Fibonacci setup
    SFibSetup setup = m_levelsCalc.GetBestSetup();

    if(setup.direction == 0)
        return TRADE_SIGNAL_NONE;

    // Check for confirmation
    SFibConfirmationResult confResult = m_confirmation.CheckConfirmation(setup);

    if(!confResult.confirmed)
        return TRADE_SIGNAL_NONE;

    // Calculate confidence based on setup score and confirmation
    confidence = (setup.score / 100.0) * confResult.strength;
    confidence = MathMin(1.0, confidence);

    // Minimum confidence filter
    if(confidence < m_minConfidence)
        return TRADE_SIGNAL_NONE;

    ENUM_TRADE_SIGNAL result = TRADE_SIGNAL_NONE;

    if(setup.direction > 0)
        result = TRADE_SIGNAL_BUY;
    else if(setup.direction < 0)
        result = TRADE_SIGNAL_SELL;

    if(result != TRADE_SIGNAL_NONE)
    {
        PrintFormat("[FIB v2.0] %s: %s | Conf: %.1f%% | Level: %.1f%% | %s | SL: %.5f | TP: %.5f",
                   m_symbol,
                   result == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   confidence * 100,
                   setup.level * 100,
                   confResult.pattern,
                   setup.stopLoss,
                   setup.takeProfit);
    }

    return result;
}

#endif // __STRATEGY_FIBONACCI_MQH__
