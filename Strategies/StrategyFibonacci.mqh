//+------------------------------------------------------------------+
//| Fibonacci Strategy v2.0                                          |
//| Enhanced with efficient swing detection, extensions, confluence  |
//| Copyright 2025, Advanced AI Coding Assistant                     |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_FIBONACCI_MQH__
#define __STRATEGY_FIBONACCI_MQH__

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Visualization/DrawingCoordinator.mqh"
#include "../Core/Visualization/ChartDrawingManager.mqh"

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
    CChartDrawingManager*   m_drawingManager;

    // Configuration
    int    m_lastBarProcessed;
    string m_drawPrefix;
    int    m_symbolDigits;
    string GetPriceFormatString() const;

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
    m_drawingManager(NULL),
    m_lastBarProcessed(0),
    m_drawPrefix("FIB_"),
    m_symbolDigits(5)  // Default to 5-digit precision
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
    if(m_drawingManager != NULL) { delete m_drawingManager; m_drawingManager = NULL; }
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
    
    // Get symbol precision for display formatting
    m_symbolDigits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    PrintFormat("[FIB v2.0] Symbol %s has %d digits for price precision", symbol, m_symbolDigits);

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

    // Initialize Drawing Manager
    m_drawingManager = new CChartDrawingManager();
    if(m_drawingManager != NULL)
    {
        m_drawingManager.Initialize(symbol, timeframe, "FIB");
        SDrawingConfig config = m_drawingManager.GetConfiguration();
        config.enableDrawing = true;
        config.enableSupportResistance = true;
        config.enableTrendLines = false;
        config.enableStructure = false;
        config.enableOrderBlocks = false;
        config.enableFVG = false;
        config.enableSignalMarkers = false;
        m_drawingManager.SetConfiguration(config);
    }

    PrintFormat("[FIB v2.0] Strategy initialized for %s on %s", symbol, EnumToString(timeframe));
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void CStrategyFibonacci::Deinit()
{
    if(m_drawingManager != NULL)
        m_drawingManager.CleanupAll();
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

    // Regular cleanup to prevent object accumulation
    if(m_drawingManager != NULL)
        m_drawingManager.CleanupOldObjects();

    // Draw Fibonacci levels
    if(MQLInfoInteger(MQL_VISUAL_MODE))
        DrawFibLevels();
}

//+------------------------------------------------------------------+
//| Get Price Format String based on symbol digits                    |
//+------------------------------------------------------------------+
string CStrategyFibonacci::GetPriceFormatString() const
{
    // Return format string based on symbol digit count
    // Example: digits=5 -> "%.5f", digits=3 -> "%.3f"
    return StringFormat("%%.%df", m_symbolDigits);
}

//+------------------------------------------------------------------+
//| Draw Fibonacci Levels on Chart                                   |
//+------------------------------------------------------------------+
void CStrategyFibonacci::DrawFibLevels()
{
    if(m_levelsCalc == NULL || m_drawingManager == NULL) return;

    SFibSetup setup;
    if(!m_levelsCalc.GetBestBullishSetup(setup))
        if(!m_levelsCalc.GetBestBearishSetup(setup))
            return;
    
    string priceFormat = GetPriceFormatString();

    for(int i = 0; i < setup.levelCount; i++)
    {
        SFibLevel level = setup.levels[i];
        color clr = clrGray;

        if(level.ratio == 0.618) clr = clrGold;
        else if(level.ratio == 0.500) clr = clrGoldenrod;
        else if(level.ratio == 0.382) clr = clrDarkGoldenrod;
        else if(level.ratio > 1.0) clr = clrDodgerBlue;

        string priceText = StringFormat(priceFormat, level.price);
        string label = StringFormat("%s%% (%s)", level.name, priceText);
        
        m_drawingManager.DrawHorizontalLevel(level.price, clr, label, STYLE_DOT, 1, true);
    }
}

//+------------------------------------------------------------------+
//| Get Signal - Fibonacci Confluence with Confirmation              |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategyFibonacci::GetSignal(double &confidence)
{
    confidence = 0.0;
    SetDecisionReasonTag("FIB_UNSET");

    if(!m_is_enabled || !m_is_initialized)
    {
        SetDecisionReasonTag("FIB_DISABLED_OR_UNINIT");
        return TRADE_SIGNAL_NONE;
    }

    if(m_swingDetector == NULL || m_levelsCalc == NULL || m_confirmation == NULL)
    {
        SetDecisionReasonTag("FIB_COMPONENTS_NOT_READY");
        return TRADE_SIGNAL_NONE;
    }

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
    {
        SetDecisionReasonTag("FIB_NO_SETUP");
        return TRADE_SIGNAL_NONE;
    }

    // We need a specific level for confirmation. Use 61.8% as primary entry
    double entryLevel = setup.fib618;
    
    // Check for confirmation at the Fib level
    SFibConfirmation confirm = m_confirmation.GetConfirmation(entryLevel, setup.isBullish);

    if(confirm.type == CONFIRM_NONE)
    {
        SetDecisionReasonTag("FIB_NO_CONFIRMATION");
        return TRADE_SIGNAL_NONE;
    }

    // Calculate confidence based on setup score and confirmation
    confidence = (setup.overallScore / 100.0) * confirm.strength;
    confidence = MathMin(1.0, confidence);

    // Minimum confidence filter
    if(confidence < m_minConfidence)
    {
        SetDecisionReasonTag("FIB_LOW_CONFIDENCE");
        return TRADE_SIGNAL_NONE;
    }

    if(signalType != TRADE_SIGNAL_NONE)
    {
        string priceFormat = GetPriceFormatString();
        string entryPriceText = StringFormat(priceFormat, entryLevel);
        
        SetDecisionReasonTag(signalType == TRADE_SIGNAL_BUY ? "FIB_SIGNAL_BUY" : "FIB_SIGNAL_SELL");
        PrintFormat("[FIB v2.0] %s: %s | Conf: %.1f%% | Level: 61.8%% (%s) | %s",
                    m_symbol,
                    signalType == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                    confidence * 100,
                    entryPriceText,
                    confirm.description);
        
        RecordSignal();
    }

    return signalType;
}

#endif // __STRATEGY_FIBONACCI_MQH__
