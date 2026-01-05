//+------------------------------------------------------------------+
//| Harmonic Patterns Strategy v2.0                                  |
//| Enhanced O(n) scanner with confirmation and proper TP/SL         |
//| Copyright 2025, Advanced AI Coding Assistant                     |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_HARMONIC_PATTERNS_MQH__
#define __STRATEGY_HARMONIC_PATTERNS_MQH__

#include "../Core/Strategy/StrategyBase.mqh"

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

    PrintFormat("[HARMONIC v2.0] Strategy initialized for %s on %s", symbol, EnumToString(timeframe));
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                 |
//+------------------------------------------------------------------+
void CStrategyHarmonicPatterns::Deinit()
{
    ObjectsDeleteAll(0, "HARM_");
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
    DrawPatterns();
}

//+------------------------------------------------------------------+
//| Draw Harmonic Patterns on Chart                                  |
//+------------------------------------------------------------------+
void CStrategyHarmonicPatterns::DrawPatterns()
{
    if(m_scanner == NULL) return;

    int patternCount = m_scanner.GetPatternCount();
    for(int i = 0; i < patternCount; i++)
    {
        SHarmonicPatternData pattern;
        if(m_scanner.GetPatternAt(i, pattern) && pattern.isValid)
        {
            // Draw pattern lines X-A-B-C-D
            string baseName = StringFormat("HARM_%s_%d", EnumToString(pattern.type), i);
            color patternColor = (pattern.direction == HARMONIC_BULLISH) ? clrDodgerBlue : clrCrimson;

            // Draw PRZ zone
            string przName = baseName + "_PRZ";
            double przTop = pattern.przHigh;
            double przBottom = pattern.przLow;

            if(ObjectFind(0, przName) >= 0)
                ObjectDelete(0, przName);

            ObjectCreate(0, przName, OBJ_RECTANGLE, 0,
                pattern.dTime, przTop,
                TimeCurrent(), przBottom);
            ObjectSetInteger(0, przName, OBJPROP_COLOR, patternColor);
            ObjectSetInteger(0, przName, OBJPROP_FILL, true);
            ObjectSetInteger(0, przName, OBJPROP_BACK, true);
            ObjectSetInteger(0, przName, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, przName, OBJPROP_WIDTH, 1);
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
