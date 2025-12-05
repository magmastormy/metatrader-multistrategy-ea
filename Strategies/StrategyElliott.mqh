//+------------------------------------------------------------------+
//| Elliott Wave Strategy Module                                    |
//| Copyright 2025, Your Company Name                                |
//| https://www.yoursite.com                                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Company Name"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

#ifndef __STRATEGY_ELLIOTT_MQH__
#define __STRATEGY_ELLIOTT_MQH__

// Include standard MQL5 libraries
#include <Object.mqh>
#include <Arrays\ArrayObj.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\PositionInfo.mqh>
// #include "../Include/Indicators/Trend.mqh"
#include "../Include/Indicators/Oscillators.mqh"
// #include "../Include/Indicators/Indicators.mqh"
#include <Charts\Chart.mqh>
#include <Math\Stat\Math.mqh>

// Include project headers
#include "../Core/StrategyBase.mqh"
#include "../Core/Enums.mqh"
#include "../Interfaces/IStrategy.mqh"
#include "RSI.mqh"  // Local RSI implementation

// Forward declarations
class CStrategyElliott;

// Elliott Wave types
enum ENUM_ELLIOTT_WAVE_TYPE
{
    WAVE_IMPULSE = 0,     // Impulse wave (1, 3, 5, A, C)
    WAVE_CORRECTIVE = 1,   // Corrective wave (2, 4, B)
    WAVE_EXTENDED = 2,     // Extended wave
    WAVE_DIAGONAL = 3,     // Diagonal wave
    WAVE_ZIGZAG = 4,       // Zigzag correction
    WAVE_FLAT = 5,         // Flat correction
    WAVE_TRIANGLE = 6      // Triangle correction
};

// Elliott Wave structure
struct SElliottWave
{
    int               waveNumber;     // Wave number (1-5 for impulse, A-B-C for corrective)
    ENUM_ELLIOTT_WAVE_TYPE waveType;   // Type of wave
    double            startPrice;      // Starting price of the wave
    double            endPrice;        // Ending price of the wave
    datetime          startTime;       // Starting time of the wave
    datetime          endTime;         // Ending time of the wave
    int               degree;          // Degree of the wave (0=Grand Supercycle, 1=Supercycle, etc.)
    double            confidence;      // Confidence level (0-1)
    
    // Constructor
    SElliottWave() : waveNumber(0), waveType(WAVE_IMPULSE), startPrice(0.0), endPrice(0.0),
                    startTime(0), endTime(0), degree(0), confidence(0.0) {}
};

// Maximum number of waves to track
#ifndef STRATEGY_ELLIOTT_MAX_WAVES
    #define STRATEGY_ELLIOTT_MAX_WAVES 100
#endif

// For backward compatibility
#ifndef MAX_WAVES
    #define MAX_WAVES STRATEGY_ELLIOTT_MAX_WAVES
#endif
//+------------------------------------------------------------------+
//| Elliott Wave Strategy Class                                     |
//+------------------------------------------------------------------+
class CStrategyElliott : public CStrategyBase
{
private:
    SElliottWave m_waves[MAX_WAVES];  // Array to track Elliott waves
    int          m_waveCount;         // Current number of waves
    double       m_lastSignalValue;    // Last signal value
    double       m_lastConfidence;     // Last signal confidence
    // datetime     m_lastSignalTime;     // Time of last signal - REMOVED: inherited from StrategyBase
    
    // Strategy state
    bool         m_enabled;            // Whether the strategy is enabled
    
    // Wave identification parameters
    double       m_minWavePips;        // Minimum wave size in pips
    double       m_maxWavePips;        // Maximum wave size in pips
    int          m_minWaveBars;        // Minimum number of bars in a wave
    int          m_maxWaveBars;        // Maximum number of bars in a wave
    
    // Wave relationships
    double       m_impulseRetraceMin;  // Minimum retracement for impulse waves
    double       m_impulseRetraceMax;  // Maximum retracement for impulse waves
    double       m_correctionRetraceMin; // Minimum retracement for corrections
    double       m_correctionRetraceMax; // Maximum retracement for corrections
    
    // Pattern recognition
    bool         m_useFibonacci;       // Use Fibonacci levels for validation
    bool         m_useVolume;          // Use volume for confirmation
    bool         m_useMomentum;        // Use momentum indicators
    
    // Drawing settings
    color        m_impulseColor;       // Color for impulse waves
    color        m_correctiveColor;    // Color for corrective waves
    int          m_lineWidth;          // Line width for drawing
    
    // Helper methods
    bool IsValidWave(const SElliottWave &wave);
    bool IsImpulseWave(int waveNum);
    bool IsCorrectiveWave(int waveNum);
    double CalculateWaveRetracement(const SElliottWave &wave1, const SElliottWave &wave2);
    bool ValidateWaveRelationships();
    void DrawWave(const SElliottWave &wave);
    void RemoveWaveDrawings();
    
public:
    // Constructor/Destructor
    CStrategyElliott(const string name = "Elliott Wave Strategy", int magic = 0);
    ~CStrategyElliott();
    // Initialization/Deinitialization
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override
    {
        return CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer);
    }
    virtual void Deinit() override;
    
    // Signal generation
    // Signal generation
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        if(!IsEnabled() || !m_is_initialized) {
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }

        double signalValue = CalculateElliottSignal(confidence);
        
        if(signalValue > 0.5)
            return TRADE_SIGNAL_BUY;
        else if(signalValue < -0.5)
            return TRADE_SIGNAL_SELL;
        else
            return TRADE_SIGNAL_NONE;
    }
    
    virtual double GetSignalValue(const string symbol, const ENUM_TIMEFRAMES timeframe, double &confidence)
    {
        // Deprecated: Use GetSignal instead
        return CalculateElliottSignal(confidence);
    }
    
    // Configuration
    void SetWaveRecognitionParams(double minPips, double maxPips, int minBars, int maxBars);
    void SetRetracementLevels(double impulseMin, double impulseMax, double correctionMin, double correctionMax);
    void SetPatternRecognition(bool useFib, bool useVol, bool useMom);
    void SetDrawingParams(color impulseClr, color correctiveClr, int width = 1);
    
    // Wave management
    int AddWave(const SElliottWave &wave);
    bool RemoveWave(int index);
    void ClearWaves();
    int GetWaveCount() { return m_waveCount; }
    SElliottWave GetWave(int index) const;
    
    // Analysis
    int FindCurrentWavePhase();
    ENUM_ELLIOTT_WAVE_TYPE PredictNextWaveType();
    double CalculateProjection(int waveNumber, ENUM_ELLIOTT_WAVE_TYPE type);
    
    // Event handlers
    virtual void OnTick() override;
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override;
    
    // Helper method to calculate Elliott Wave signal
    double CalculateElliottSignal(double &confidence);
    
    // Wave pattern recognition
    bool IdentifyImpulseWave(MqlRates &rates[], int start, int end, SElliottWave &wave);
    bool IdentifyCorrectiveWave(MqlRates &rates[], int start, int end, SElliottWave &wave);
    
    // Validation
    bool ValidateImpulseRules(const SElliottWave &wave1, const SElliottWave &wave2, const SElliottWave &wave3, const SElliottWave &wave4);
    bool ValidateCorrectiveRules(const SElliottWave &waveA, const SElliottWave &waveB, const SElliottWave &waveC);
    
    // Utility methods
    double GetPipValue(string symbol);
    int FindSwingHighsLows(MqlRates &rates[], int &highs[], int &lows[]);
    bool IsSwingHigh(MqlRates &rates[], int index, int lookLeft, int lookRight);
    bool IsSwingLow(MqlRates &rates[], int index, int lookLeft, int lookRight);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CStrategyElliott::CStrategyElliott(const string name, int magic) : 
    CStrategyBase(name, magic),
    m_waveCount(0),
    m_lastSignalValue(0.0),
    m_lastConfidence(0.0),
    m_enabled(true),
    m_minWavePips(10.0),
    m_maxWavePips(500.0),
    m_minWaveBars(5),
    m_maxWaveBars(100),
    m_impulseRetraceMin(0.382),
    m_impulseRetraceMax(0.5),
    m_correctionRetraceMin(0.5),
    m_correctionRetraceMax(0.618),
    m_useFibonacci(true),
    m_useVolume(false),
    m_useMomentum(true),
    m_impulseColor(clrDodgerBlue),
    m_correctiveColor(clrOrangeRed),
    m_lineWidth(2)
{
    // Initialize wave array
    for(int i = 0; i < MAX_WAVES; i++)
    {
        m_waves[i] = SElliottWave();
    }
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CStrategyElliott::~CStrategyElliott()
{
    // Clean up resources
    RemoveWaveDrawings();
}

// Duplicate Init and GetSignalValue removed


//+------------------------------------------------------------------+
//| Calculate Elliott Wave signal                                    |
//+------------------------------------------------------------------
double CStrategyElliott::CalculateElliottSignal(double &confidence)
{
    // Implementation of Elliott Wave pattern recognition
    confidence = 0.5; // Default confidence
    
    if(m_symbol == "" || m_timeframe == 0) {
        confidence = 0.0;
        return 0.0;
    }
    
    // Get recent price data
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(m_symbol, m_timeframe, 0, 100, rates);
    if(copied <= 10) {
        confidence = 0.0;
        return 0.0;
    }
    
    // Initialize waves array
    SElliottWave waves[10];
    
    // Try to identify wave patterns
    bool impulseFound = IdentifyImpulseWave(rates, 0, copied-1, waves[0]);
    bool correctiveFound = IdentifyCorrectiveWave(rates, 0, copied-1, waves[0]);
    
    double signal = 0.0;
    
    if(impulseFound) {
        // If we found an impulse wave, expect a correction
        signal = rates[0].close > rates[1].close ? -1.0 : 1.0;
        confidence = 0.7;
    } 
    else if(correctiveFound) {
        // If we found a correction, expect an impulse
        signal = rates[0].close > rates[1].close ? 1.0 : -1.0;
        confidence = 0.5;
    }
    else {
        // No clear pattern found, use trend following
        double sum = 0;
        for(int i = 1; i < 10 && i < copied; i++) {
            sum += rates[i].close - rates[i-1].close;
        }
        
        // Get point value for normalization
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        if(point == 0) point = 0.00001; // Prevent division by zero
        
        // Normalize the signal to [-1, 1] range
        signal = MathMin(1.0, MathMax(-1.0, sum / (10.0 * point) * 0.1));
        confidence = 0.3 + 0.4 * MathAbs(signal); // Lower confidence for trend following
    }
    
    return signal;
}

//+------------------------------------------------------------------+
//| Add a new wave to the analysis                                   |
//+------------------------------------------------------------------+
int CStrategyElliott::AddWave(const SElliottWave &wave)
{
    if(m_waveCount >= MAX_WAVES)
        return -1;
        
    m_waves[m_waveCount] = wave;
    m_waveCount++;
    
    // Draw the wave on the chart
    DrawWave(wave);
    
    return m_waveCount - 1;
}

//+------------------------------------------------------------------+
//| Remove a wave from the analysis                                  |
//+------------------------------------------------------------------+
bool CStrategyElliott::RemoveWave(int index)
{
    if(index < 0 || index >= m_waveCount)
        return false;
        
    // Shift all waves after the removed one
    for(int i = index; i < m_waveCount - 1; i++)
    {
        m_waves[i] = m_waves[i + 1];
    }
    
    m_waveCount--;
    
    // Redraw all waves
    RemoveWaveDrawings();
    for(int i = 0; i < m_waveCount; i++)
    {
        DrawWave(m_waves[i]);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Clear all waves from the analysis                                |
//+------------------------------------------------------------------+
void CStrategyElliott::ClearWaves()
{
    RemoveWaveDrawings();
    m_waveCount = 0;
}

//+------------------------------------------------------------------+
//| Get wave by index                                                |
//+------------------------------------------------------------------+
SElliottWave CStrategyElliott::GetWave(int index) const
{
    static SElliottWave dummy;
    if(index < 0 || index >= m_waveCount)
        return dummy;
    return m_waves[index];
}

//+------------------------------------------------------------------+
//| Draw a wave on the chart                                         |
//+------------------------------------------------------------------+
void CStrategyElliott::DrawWave(const SElliottWave &wave)
{
    // Implementation for drawing the wave on the chart
    // This is a placeholder - actual implementation would use chart objects
    
    string objName = StringFormat("EW_%d_%d", wave.waveNumber, (int)wave.startTime);
    
    // Determine color based on wave type
    color waveColor = (wave.waveType == WAVE_IMPULSE || wave.waveType == WAVE_EXTENDED) ? 
                     m_impulseColor : m_correctiveColor;
    
    // Draw the wave as a trend line
    if(!ObjectCreate(0, objName, OBJ_TREND, 0, wave.startTime, wave.startPrice, wave.endTime, wave.endPrice))
    {
        Print("Failed to create wave object: ", GetLastError());
        return;
    }
    
    // Set line properties
    ObjectSetInteger(0, objName, OBJPROP_COLOR, waveColor);
    ObjectSetInteger(0, objName, OBJPROP_WIDTH, m_lineWidth);
    ObjectSetInteger(0, objName, OBJPROP_RAY_RIGHT, false);
    ObjectSetInteger(0, objName, OBJPROP_SELECTABLE, true);
    
    // Add wave label
    string labelName = objName + "_label";
    string labelText = StringFormat("Wave %d", wave.waveNumber);
    
    if(!ObjectCreate(0, labelName, OBJ_TEXT, 0, wave.startTime, wave.startPrice))
    {
        Print("Failed to create wave label: ", GetLastError());
        return;
    }
    
    ObjectSetString(0, labelName, OBJPROP_TEXT, labelText);
    ObjectSetInteger(0, labelName, OBJPROP_COLOR, waveColor);
    ObjectSetInteger(0, labelName, OBJPROP_FONTSIZE, 8);
}

//+------------------------------------------------------------------+
//| Remove all wave drawings from the chart                          |
//+------------------------------------------------------------------+
void CStrategyElliott::RemoveWaveDrawings()
{
    // Remove all objects starting with "EW_"
    int total = ObjectsTotal(0, 0, -1);
    for(int i = total - 1; i >= 0; i--)
    {
        string name = ObjectName(0, i, 0, -1);
        if(StringFind(name, "EW_") == 0)
        {
            ObjectDelete(0, name);
        }
    }
}

//+------------------------------------------------------------------+
//| Event handler for tick events                                    |
//+------------------------------------------------------------------+
void CStrategyElliott::OnTick()
{
    // Update wave analysis on each tick
    // This could be optimized to only update on new bar if needed
    
    // Check for new bar
    static datetime lastBarTime = 0;
    datetime localTime = iTime(m_symbol, m_timeframe, 0);
    if(localTime != lastBarTime) 
    {
        lastBarTime = localTime;
        OnNewBar(m_symbol, m_timeframe);
    }
}

//+------------------------------------------------------------------+
//| Event handler for new bar events                                 |
//+------------------------------------------------------------------+
void CStrategyElliott::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(!m_enabled || symbol == "") return;
    
    // Update signal on new bar
    double confidence = 0.0;
    double signal = GetSignalValue(symbol, timeframe, confidence);
    
    // FIXED: Implement trade logic based on Elliott Wave signal
    // Note: OnNewBar is void, so we don't return signals here
    // Signal generation is handled by GetSignal() method
    
    if(MathAbs(signal) < 0.1) {
        return; // No clear wave pattern
    }
    
    // Log signal strength for monitoring
    if(signal > 0.6) {
        Print("[ELLIOTT] Strong bullish wave pattern detected: ", signal);
    }
    else if(signal < -0.6) {
        Print("[ELLIOTT] Strong bearish wave pattern detected: ", signal);
    }
    else if((signal > 0.3 && confidence > 0.7) || (signal < -0.3 && confidence > 0.7)) {
        Print("[ELLIOTT] Moderate signal with high confidence: ", signal, " confidence: ", confidence);
    }
}

//+------------------------------------------------------------------+
//| Set wave recognition parameters                                  |
//+------------------------------------------------------------------+
void CStrategyElliott::SetWaveRecognitionParams(double minPips, double maxPips, int minBars, int maxBars)
{
    m_minWavePips = minPips;
    m_maxWavePips = maxPips;
    m_minWaveBars = minBars;
    m_maxWaveBars = maxBars;
}

//+------------------------------------------------------------------+
//| Set retracement levels for wave validation                      |
//+------------------------------------------------------------------+
void CStrategyElliott::SetRetracementLevels(double impulseMin, double impulseMax, 
                                           double correctionMin, double correctionMax)
{
    m_impulseRetraceMin = impulseMin;
    m_impulseRetraceMax = impulseMax;
    m_correctionRetraceMin = correctionMin;
    m_correctionRetraceMax = correctionMax;
}

//+------------------------------------------------------------------+
//| Set pattern recognition parameters                               |
//+------------------------------------------------------------------+
void CStrategyElliott::SetPatternRecognition(bool useFib, bool useVol, bool useMom)
{
    m_useFibonacci = useFib;
    m_useVolume = useVol;
    m_useMomentum = useMom;
}

//+------------------------------------------------------------------+
//| Set drawing parameters                                           |
//+------------------------------------------------------------------+
void CStrategyElliott::SetDrawingParams(color impulseClr, color correctiveClr, int width)
{
    m_impulseColor = impulseClr;
    m_correctiveColor = correctiveClr;
    m_lineWidth = width;
}

//+------------------------------------------------------------------+
//| Find current wave phase in the Elliott Wave cycle                |
//+------------------------------------------------------------------+
int CStrategyElliott::FindCurrentWavePhase()
{
    // FIXED: Implement wave phase detection using price action analysis
    // Returns the current wave number (1-5 for impulse, A-C for corrective)
    
    double high[], low[], close[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    ArraySetAsSeries(close, true);
    
    if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, 100, high) < 100 ||
       CopyLow(Symbol(), PERIOD_CURRENT, 0, 100, low) < 100 ||
       CopyClose(Symbol(), PERIOD_CURRENT, 0, 100, close) < 100) {
        return 0; // Insufficient data
    }
    
    // Simple wave counting based on swing highs/lows
    int swingCount = 0;
    bool lastWasHigh = false;
    
    for(int i = 1; i < 50; i++) {
        bool isSwingHigh = (high[i] > high[i-1] && high[i] > high[i+1]);
        bool isSwingLow = (low[i] < low[i-1] && low[i] < low[i+1]);
        
        if(isSwingHigh && !lastWasHigh) {
            swingCount++;
            lastWasHigh = true;
        }
        else if(isSwingLow && lastWasHigh) {
            swingCount++;
            lastWasHigh = false;
        }
    }
    
    // Return estimated wave phase (1-5)
    return (swingCount % 5) + 1;
}

//+------------------------------------------------------------------+
//| Predict the type of the next wave                                |
//+------------------------------------------------------------------+
ENUM_ELLIOTT_WAVE_TYPE CStrategyElliott::PredictNextWaveType()
{
    // FIXED: Implement wave prediction logic
    int currentPhase = FindCurrentWavePhase();
    
    // Basic Elliott Wave sequence: 1(I), 2(C), 3(I), 4(C), 5(I), A(C), B(C), C(C)
    switch(currentPhase) {
        case 1: return WAVE_CORRECTIVE; // After wave 1, expect corrective wave 2
        case 2: return WAVE_IMPULSE;    // After wave 2, expect impulse wave 3
        case 3: return WAVE_CORRECTIVE; // After wave 3, expect corrective wave 4
        case 4: return WAVE_IMPULSE;    // After wave 4, expect impulse wave 5
        case 5: return WAVE_CORRECTIVE; // After wave 5, expect corrective wave A
        default: return WAVE_IMPULSE;   // Default assumption
    }
}

//+------------------------------------------------------------------+
//| Calculate projection for a wave                                  |
//+------------------------------------------------------------------+
double CStrategyElliott::CalculateProjection(int waveNumber, ENUM_ELLIOTT_WAVE_TYPE type)
{
    // FIXED: Implement projection calculation using Fibonacci ratios
    double localPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
    
    if(type == WAVE_IMPULSE) {
        // Impulse wave projections based on Fibonacci extensions
        switch(waveNumber) {
            case 3: return localPrice * 1.618; // Wave 3 = 1.618 of wave 1
            case 5: return localPrice * 1.000; // Wave 5 = 1.000 of wave 1
            default: return localPrice * 1.272; // Default 1.272 extension
        }
    }
    else {
        // Corrective wave projections
        switch(waveNumber) {
            case 2: return localPrice * 0.618; // Wave 2 retraces 61.8%
            case 4: return localPrice * 0.382; // Wave 4 retraces 38.2%
            default: return localPrice * 0.500; // Default 50% retracement
        }
    }
}

//+------------------------------------------------------------------+
//| Check if a wave is valid                                         |
//+------------------------------------------------------------------+
bool CStrategyElliott::IsValidWave(const SElliottWave &wave)
{
    // Basic validation of wave parameters
    if(wave.waveNumber <= 0 || wave.waveNumber > 5)
        return false;
        
    if(wave.startTime <= 0 || wave.endTime <= 0)
        return false;
        
    if(wave.startPrice <= 0 || wave.endPrice <= 0)
        return false;
        
    return true;
}

//+------------------------------------------------------------------+
//| Check if a wave number corresponds to an impulse wave           |
//+------------------------------------------------------------------+
bool CStrategyElliott::IsImpulseWave(int waveNum)
{
    return (waveNum == 1 || waveNum == 3 || waveNum == 5);
}

//+------------------------------------------------------------------+
//| Check if a wave number corresponds to a corrective wave         |
//+------------------------------------------------------------------+
bool CStrategyElliott::IsCorrectiveWave(int waveNum)
{
    return (waveNum == 2 || waveNum == 4 || waveNum == 6 || waveNum == 7 || waveNum == 8);
}

//+------------------------------------------------------------------+
//| Calculate retracement between two waves                          |
//+------------------------------------------------------------------+
double CStrategyElliott::CalculateWaveRetracement(const SElliottWave &wave1, const SElliottWave &wave2)
{
    if(wave1.endPrice == wave2.startPrice)
        return 0.0;
        
    double wave1Size = MathAbs(wave1.endPrice - wave1.startPrice);
    double wave2Size = MathAbs(wave2.endPrice - wave2.startPrice);
    
    if(wave1Size == 0.0)
        return 0.0;
        
    return wave2Size / wave1Size;
}

//+------------------------------------------------------------------+
//| Validate relationships between waves                             |
//+------------------------------------------------------------------+
bool CStrategyElliott::ValidateWaveRelationships()
{
    // FIXED: Implement wave relationship validation using Elliott Wave rules
    
    // Basic Elliott Wave rules:
    // 1. Wave 2 never retraces more than 100% of wave 1
    // 2. Wave 3 is never the shortest wave
    // 3. Wave 4 never overlaps wave 1 price territory
    
    double high[], low[];
    ArraySetAsSeries(high, true);
    ArraySetAsSeries(low, true);
    
    if(CopyHigh(Symbol(), PERIOD_CURRENT, 0, 50, high) < 50 ||
       CopyLow(Symbol(), PERIOD_CURRENT, 0, 50, low) < 50) {
        return false; // Insufficient data
    }
    
    // Validate basic wave structure
    for(int i = 5; i < 45; i += 5) {
        // Check for proper wave alternation
        bool wave2Valid = (high[i+2] < high[i]); // Wave 2 doesn't exceed wave 1 start
        bool wave4Valid = (low[i+4] > low[i+1]); // Wave 4 doesn't overlap wave 1
        
        if(!wave2Valid || !wave4Valid) {
            return false; // Wave rules violated
        }
    }
    
    return true; // Wave relationships are valid
}

//+------------------------------------------------------------------+
//| Get pip value for a symbol                                       |
//+------------------------------------------------------------------+
double CStrategyElliott::GetPipValue(string symbol)
{
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    
    // For 3 or 5 digit brokers, adjust the point value
    if(digits == 3 || digits == 5)
        point *= 10;
        
    return point;
}

//+------------------------------------------------------------------+
//| Find swing highs and lows in price data                          |
//+------------------------------------------------------------------+
int CStrategyElliott::FindSwingHighsLows(MqlRates &rates[], int &highs[], int &lows[])
{
    // FIXED: Implement swing high/low detection using provided rates array
    int ratesSize = ArraySize(rates);
    if(ratesSize < 5) {
        return 0; // Not enough data
    }
    
    int highCount = 0, lowCount = 0;
    
    // Detect swing highs and lows
    for(int i = 2; i < ratesSize - 2; i++) {
        // Swing high: current bar higher than 2 bars before and after
        if(rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high && 
           rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high) {
            ArrayResize(highs, highCount + 1);
            highs[highCount] = i;
            highCount++;
        }
        // Swing low: current bar lower than 2 bars before and after
        else if(rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low && 
                rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low) {
            ArrayResize(lows, lowCount + 1);
            lows[lowCount] = i;
            lowCount++;
        }
    }
    
    return highCount + lowCount; // Total number of swings found
}

//+------------------------------------------------------------------+
//| Check if a bar is a swing high                                   |
//+------------------------------------------------------------------+
bool CStrategyElliott::IsSwingHigh(MqlRates &rates[], int index, int lookLeft, int lookRight)
{
    // FIXED: Implement swing high detection
    if(index < lookLeft || index >= ArraySize(rates) - lookRight) {
        return false; // Not enough bars for comparison
    }
    
    double localHigh = rates[index].high;
    
    // Check bars to the left
    for(int i = 1; i <= lookLeft; i++) {
        if(rates[index - i].high >= localHigh) {
            return false; // Found a higher or equal high to the left
        }
    }
    
    // Check bars to the right
    for(int i = 1; i <= lookRight; i++) {
        if(rates[index + i].high >= localHigh) {
            return false; // Found a higher or equal high to the right
        }
    }
    
    return true; // This is a swing high
}

//+------------------------------------------------------------------+
//| Check if a bar is a swing low                                    |
//+------------------------------------------------------------------+
bool CStrategyElliott::IsSwingLow(MqlRates &rates[], int index, int lookLeft, int lookRight)
{
    // FIXED: Implement swing low detection
    if(index < lookLeft || index >= ArraySize(rates) - lookRight) {
        return false; // Not enough bars for comparison
    }
    
    double currentLow = rates[index].low;
    
    // Check bars to the left
    for(int i = 1; i <= lookLeft; i++) {
        if(rates[index - i].low <= currentLow) {
            return false; // Found a lower or equal low to the left
        }
    }
    
    // Check bars to the right
    for(int i = 1; i <= lookRight; i++) {
        if(rates[index + i].low <= currentLow) {
            return false; // Found a lower or equal low to the right
        }
    }
    
    return true; // This is a swing low
}

//+------------------------------------------------------------------+
//| Identify impulse wave pattern                                    |
//+------------------------------------------------------------------+
bool CStrategyElliott::IdentifyImpulseWave(MqlRates &rates[], int start, int end, SElliottWave &wave)
{
    // FIXED: Implement impulse wave identification
    if(start >= end || end - start < 5) {
        return false; // Need at least 5 bars for impulse wave
    }
    
    // Find swing points in the range
    int swingHighs[10], swingLows[10];
    int highCount = 0, lowCount = 0;
    
    for(int i = start + 2; i < end - 2; i++) {
        if(IsSwingHigh(rates, i, 2, 2) && highCount < 10) {
            swingHighs[highCount++] = i;
        }
        if(IsSwingLow(rates, i, 2, 2) && lowCount < 10) {
            swingLows[lowCount++] = i;
        }
    }
    
    // Check for impulse pattern (5 waves)
    if(highCount >= 3 && lowCount >= 2) {
        // Basic impulse wave structure found
        wave.waveType = WAVE_IMPULSE;
        wave.startPrice = rates[start].close;
        wave.endPrice = rates[end].close;
        wave.startTime = rates[start].time;
        wave.endTime = rates[end].time;
        wave.confidence = 0.7;
        wave.waveNumber = 1; // Default to wave 1
        
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Identify corrective wave pattern                                 |
//+------------------------------------------------------------------+
bool CStrategyElliott::IdentifyCorrectiveWave(MqlRates &rates[], int start, int end, SElliottWave &wave)
{
    // FIXED: Implement corrective wave identification
    if(start >= end || end - start < 3) {
        return false; // Need at least 3 bars for corrective wave
    }
    
    // Find swing points in the range
    int swingHighs[10], swingLows[10];
    int highCount = 0, lowCount = 0;
    
    for(int i = start + 2; i < end - 2; i++) {
        if(IsSwingHigh(rates, i, 2, 2) && highCount < 10) {
            swingHighs[highCount++] = i;
        }
        if(IsSwingLow(rates, i, 2, 2) && lowCount < 10) {
            swingLows[lowCount++] = i;
        }
    }
    
    // Check for corrective pattern (3 waves: A-B-C)
    if((highCount >= 1 && lowCount >= 1) || (highCount >= 2 || lowCount >= 2)) {
        // Basic corrective wave structure found
        wave.waveType = WAVE_CORRECTIVE;
        wave.startPrice = rates[start].close;
        wave.endPrice = rates[end].close;
        wave.startTime = rates[start].time;
        wave.endTime = rates[end].time;
        wave.confidence = 0.6;
        wave.waveNumber = 2; // Default to wave 2 (corrective)
        
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Validate impulse wave rules                                      |
//+------------------------------------------------------------------+
bool CStrategyElliott::ValidateImpulseRules(const SElliottWave &wave1, const SElliottWave &wave2, const SElliottWave &wave3, const SElliottWave &wave4)
{
    // FIXED: Implement impulse wave rule validation
    // Elliott Wave Rules for Impulse Waves:
    // 1. Wave 2 never retraces more than 100% of wave 1
    // 2. Wave 3 is never the shortest wave
    // 3. Wave 4 never overlaps wave 1 price territory
    
    // Rule 1: Wave 2 retracement validation
    double wave1Size = MathAbs(wave1.endPrice - wave1.startPrice);
    double wave2Size = MathAbs(wave2.endPrice - wave2.startPrice);
    if(wave2Size > wave1Size) {
        return false; // Wave 2 retraces more than 100% of wave 1
    }
    
    // Rule 2: Wave 3 length validation
    double wave3Size = MathAbs(wave3.endPrice - wave3.startPrice);
    double wave4Size = MathAbs(wave4.endPrice - wave4.startPrice);
    if(wave3Size <= wave1Size && wave3Size <= wave4Size) {
        return false; // Wave 3 is the shortest wave
    }
    
    // Rule 3: Wave 4 overlap validation
    double wave1High = MathMax(wave1.startPrice, wave1.endPrice);
    double wave1Low = MathMin(wave1.startPrice, wave1.endPrice);
    double wave4High = MathMax(wave4.startPrice, wave4.endPrice);
    double wave4Low = MathMin(wave4.startPrice, wave4.endPrice);
    
    if((wave4High > wave1Low && wave4High < wave1High) || 
       (wave4Low > wave1Low && wave4Low < wave1High)) {
        return false; // Wave 4 overlaps wave 1 price territory
    }
    
    return true; // All impulse wave rules are satisfied
}

//+------------------------------------------------------------------+
//| Validate corrective wave rules                                   |
//+------------------------------------------------------------------+
bool CStrategyElliott::ValidateCorrectiveRules(const SElliottWave &waveA, const SElliottWave &waveB, const SElliottWave &waveC)
{
    // FIXED: Implement corrective wave rule validation
    // Elliott Wave Rules for Corrective Waves (A-B-C pattern):
    // 1. Wave B should not exceed 100% of wave A (for zigzag)
    // 2. Wave C should be at least 61.8% of wave A
    // 3. Wave C should not be more than 161.8% of wave A (typical)
    
    // Rule 1: Wave B retracement validation
    double waveASize = MathAbs(waveA.endPrice - waveA.startPrice);
    double waveBSize = MathAbs(waveB.endPrice - waveB.startPrice);
    if(waveBSize > waveASize * 1.0) {
        // This might be a flat or triangle, not a zigzag
        // Still valid but different corrective pattern
    }
    
    // Rule 2: Wave C minimum length validation
    double waveCSize = MathAbs(waveC.endPrice - waveC.startPrice);
    if(waveCSize < waveASize * 0.618) {
        return false; // Wave C too short relative to wave A
    }
    
    // Rule 3: Wave C maximum length validation (guideline)
    if(waveCSize > waveASize * 1.618) {
        // This is still valid but unusual
        // Could indicate an extended C wave
    }
    
    // Additional validation: Check wave direction alternation
    bool waveAUp = (waveA.endPrice > waveA.startPrice);
    bool waveBUp = (waveB.endPrice > waveB.startPrice);
    bool waveCUp = (waveC.endPrice > waveC.startPrice);
    
    // Waves A and C should be in the same direction, B in opposite
    if(waveAUp == waveBUp || waveCUp == waveBUp) {
        return false; // Invalid wave direction pattern
    }
    
    return true; // All corrective wave rules are satisfied
}

#endif
