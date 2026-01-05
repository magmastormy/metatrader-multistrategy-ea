//+------------------------------------------------------------------+
//| WavePatternEngine.mqh                                            |
//| Elliott Wave Pattern Recognition Engine                          |
//| Implements strict Elliott Wave rules with Fibonacci validation   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef __ELLIOTT_WAVE_PATTERN_ENGINE_MQH__
#define __ELLIOTT_WAVE_PATTERN_ENGINE_MQH__

#include "ZigZagFilter.mqh"

//+------------------------------------------------------------------+
//| Wave Type Enum                                                   |
//+------------------------------------------------------------------+
enum ENUM_WAVE_TYPE
{
    WAVE_IMPULSE_BULLISH,
    WAVE_IMPULSE_BEARISH,
    WAVE_CORRECTIVE_ABC,
    WAVE_CORRECTIVE_WXY,
    WAVE_NONE
};

//+------------------------------------------------------------------+
//| Wave State Enum                                                  |
//+------------------------------------------------------------------+
enum ENUM_WAVE_STATE
{
    STATE_WAVE_1,
    STATE_WAVE_2,
    STATE_WAVE_3,
    STATE_WAVE_4,
    STATE_WAVE_5,
    STATE_WAVE_A,
    STATE_WAVE_B,
    STATE_WAVE_C,
    STATE_COMPLETE,
    STATE_INVALID
};

//+------------------------------------------------------------------+
//| Elliott Wave Pattern Structure                                   |
//+------------------------------------------------------------------+
struct SElliottWavePattern
{
    ENUM_WAVE_TYPE      type;
    ENUM_WAVE_STATE     currentState;
    bool                isBullish;
    
    // Wave points
    double              wave0;      // Start of Wave 1
    double              wave1;      // End of Wave 1
    double              wave2;      // End of Wave 2
    double              wave3;      // End of Wave 3
    double              wave4;      // End of Wave 4
    double              wave5;      // End of Wave 5
    
    datetime            time0, time1, time2, time3, time4, time5;
    
    // Fibonacci ratios
    double              wave2Retracement;   // 38.2-78.6% of Wave 1
    double              wave3Extension;     // 100-261.8% of Wave 1
    double              wave4Retracement;   // 23.6-50% of Wave 3
    double              wave5Extension;     // 38.2-100% of Wave 3
    
    // Validation
    bool                isValid;
    bool                isComplete;
    double              confidence;
    string              invalidReason;
    
    // Projections
    double              wave3Target;
    double              wave5Target;
    
    SElliottWavePattern() : type(WAVE_NONE), currentState(STATE_WAVE_1),
                            isBullish(true), wave0(0), wave1(0), wave2(0),
                            wave3(0), wave4(0), wave5(0), time0(0), time1(0),
                            time2(0), time3(0), time4(0), time5(0),
                            wave2Retracement(0), wave3Extension(0),
                            wave4Retracement(0), wave5Extension(0),
                            isValid(false), isComplete(false), confidence(0),
                            invalidReason(""), wave3Target(0), wave5Target(0) {}
};

//+------------------------------------------------------------------+
//| Wave Pattern Engine Class                                        |
//+------------------------------------------------------------------+
class CWavePatternEngine
{
private:
    string                  m_symbol;
    ENUM_TIMEFRAMES         m_timeframe;
    
    // ZigZag filter
    CZigZagFilter*          m_zigzag;
    bool                    m_ownZigZag;
    
    // Patterns
    SElliottWavePattern     m_patterns[];
    int                     m_patternCount;
    int                     m_maxPatterns;
    
    // Configuration
    double                  m_wave2MinRetracement;  // 38.2%
    double                  m_wave2MaxRetracement;  // 78.6%
    double                  m_wave3MinExtension;    // 100%
    double                  m_wave4MaxRetracement;  // 61.8%
    double                  m_tolerance;            // 10%
    
    // Internal methods
    bool                    ValidateWave2(double wave0, double wave1, double wave2, bool isBullish);
    bool                    ValidateWave3(double wave0, double wave1, double wave2, double wave3, bool isBullish);
    bool                    ValidateWave4(double wave1, double wave2, double wave3, double wave4, bool isBullish);
    bool                    ValidateWave5(double wave3, double wave4, double wave5, bool isBullish);
    double                  CalculateWave3Target(double wave0, double wave1, double wave2, bool isBullish);
    double                  CalculateWave5Target(double wave3, double wave4, bool isBullish);
    void                    ScorePattern(SElliottWavePattern &pattern);
    
public:
                            CWavePatternEngine();
                           ~CWavePatternEngine();
    
    // Initialization
    bool                    Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                       CZigZagFilter* zigzag = NULL);
    void                    Deinit();
    
    // Update
    void                    Update();
    void                    ScanPatterns();
    
    // Getters
    int                     GetPatternCount() const { return m_patternCount; }
    bool                    GetPatternAt(int index, SElliottWavePattern &pattern);
    bool                    GetBestBullishPattern(SElliottWavePattern &pattern);
    bool                    GetBestBearishPattern(SElliottWavePattern &pattern);
    
    // Wave state checks
    bool                    IsInWave3Entry(SElliottWavePattern &pattern);
    bool                    IsInWave5Entry(SElliottWavePattern &pattern);
    bool                    IsWaveComplete(const SElliottWavePattern &pattern);
    
    // Projections
    double                  GetWave3Target(const SElliottWavePattern &pattern);
    double                  GetWave5Target(const SElliottWavePattern &pattern);
    
    // Configuration
    void                    SetWave2Retracements(double min, double max)
                            { m_wave2MinRetracement = min; m_wave2MaxRetracement = max; }
    void                    SetWave3MinExtension(double ext) { m_wave3MinExtension = ext; }
    void                    SetWave4MaxRetracement(double ret) { m_wave4MaxRetracement = ret; }
    void                    SetTolerance(double tol) { m_tolerance = tol; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CWavePatternEngine::CWavePatternEngine() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_zigzag(NULL),
    m_ownZigZag(false),
    m_patternCount(0),
    m_maxPatterns(5),
    m_wave2MinRetracement(0.382),
    m_wave2MaxRetracement(0.786),
    m_wave3MinExtension(1.0),
    m_wave4MaxRetracement(0.618),
    m_tolerance(0.10)
{
    ArrayResize(m_patterns, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CWavePatternEngine::~CWavePatternEngine()
{
    Deinit();
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CWavePatternEngine::Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                    CZigZagFilter* zigzag)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    
    if(zigzag != NULL)
    {
        m_zigzag = zigzag;
        m_ownZigZag = false;
    }
    else
    {
        m_zigzag = new CZigZagFilter();
        if(m_zigzag != NULL)
        {
            m_zigzag.Initialize(symbol, timeframe);
            m_ownZigZag = true;
        }
    }
    
    ArrayResize(m_patterns, 0);
    m_patternCount = 0;
    
    return (m_zigzag != NULL);
}

//+------------------------------------------------------------------+
//| Deinitialize                                                     |
//+------------------------------------------------------------------+
void CWavePatternEngine::Deinit()
{
    if(m_ownZigZag && m_zigzag != NULL)
    {
        delete m_zigzag;
        m_zigzag = NULL;
    }
    
    ArrayFree(m_patterns);
}

//+------------------------------------------------------------------+
//| Validate Wave 2 (38.2-78.6% retracement of Wave 1)               |
//+------------------------------------------------------------------+
bool CWavePatternEngine::ValidateWave2(double wave0, double wave1, double wave2, bool isBullish)
{
    double wave1Size = MathAbs(wave1 - wave0);
    if(wave1Size <= 0) return false;
    
    double retracement;
    if(isBullish)
        retracement = (wave1 - wave2) / wave1Size;
    else
        retracement = (wave2 - wave1) / wave1Size;
    
    // Wave 2 must not retrace more than 100% of Wave 1
    if(retracement >= 1.0) return false;
    
    // Wave 2 should retrace 38.2-78.6%
    double minRet = m_wave2MinRetracement * (1.0 - m_tolerance);
    double maxRet = m_wave2MaxRetracement * (1.0 + m_tolerance);
    
    return (retracement >= minRet && retracement <= maxRet);
}

//+------------------------------------------------------------------+
//| Validate Wave 3 (cannot be shortest, must extend beyond Wave 1)  |
//+------------------------------------------------------------------+
bool CWavePatternEngine::ValidateWave3(double wave0, double wave1, double wave2, double wave3, bool isBullish)
{
    double wave1Size = MathAbs(wave1 - wave0);
    double wave3Size = MathAbs(wave3 - wave2);
    
    if(wave1Size <= 0 || wave3Size <= 0) return false;
    
    // Wave 3 must be at least 100% of Wave 1 (with tolerance)
    double minExtension = m_wave3MinExtension * (1.0 - m_tolerance);
    if(wave3Size < wave1Size * minExtension) return false;
    
    // Wave 3 must extend beyond Wave 1's end
    if(isBullish)
        return (wave3 > wave1);
    else
        return (wave3 < wave1);
}

//+------------------------------------------------------------------+
//| Validate Wave 4 (cannot overlap Wave 1 territory)                |
//+------------------------------------------------------------------+
bool CWavePatternEngine::ValidateWave4(double wave1, double wave2, double wave3, double wave4, bool isBullish)
{
    double wave3Size = MathAbs(wave3 - wave2);
    if(wave3Size <= 0) return false;
    
    double retracement;
    if(isBullish)
        retracement = (wave3 - wave4) / wave3Size;
    else
        retracement = (wave4 - wave3) / wave3Size;
    
    // Wave 4 typically retraces 38.2-50%, max 61.8%
    double maxRet = m_wave4MaxRetracement * (1.0 + m_tolerance);
    if(retracement > maxRet) return false;
    
    // Critical: Wave 4 must not overlap Wave 1
    if(isBullish)
        return (wave4 > wave1);  // Wave 4 low must be above Wave 1 high
    else
        return (wave4 < wave1);  // Wave 4 high must be below Wave 1 low
}

//+------------------------------------------------------------------+
//| Validate Wave 5                                                  |
//+------------------------------------------------------------------+
bool CWavePatternEngine::ValidateWave5(double wave3, double wave4, double wave5, bool isBullish)
{
    double wave5Size = MathAbs(wave5 - wave4);
    if(wave5Size <= 0) return false;
    
    // Wave 5 must extend beyond Wave 3
    if(isBullish)
        return (wave5 > wave3);
    else
        return (wave5 < wave3);
}

//+------------------------------------------------------------------+
//| Calculate Wave 3 Target                                          |
//+------------------------------------------------------------------+
double CWavePatternEngine::CalculateWave3Target(double wave0, double wave1, double wave2, bool isBullish)
{
    double wave1Size = MathAbs(wave1 - wave0);
    
    // Wave 3 typical target is 161.8% extension
    if(isBullish)
        return wave2 + (wave1Size * 1.618);
    else
        return wave2 - (wave1Size * 1.618);
}

//+------------------------------------------------------------------+
//| Calculate Wave 5 Target                                          |
//+------------------------------------------------------------------+
double CWavePatternEngine::CalculateWave5Target(double wave3, double wave4, bool isBullish)
{
    double wave4Size = MathAbs(wave4 - wave3);
    
    // Wave 5 typical target is 61.8-100% of Wave 4 retracement
    if(isBullish)
        return wave4 + wave4Size;  // Equal to Wave 4 size
    else
        return wave4 - wave4Size;
}

//+------------------------------------------------------------------+
//| Score Pattern                                                    |
//+------------------------------------------------------------------+
void CWavePatternEngine::ScorePattern(SElliottWavePattern &pattern)
{
    double score = 50.0;  // Base score
    
    // Wave 2 retracement quality
    if(pattern.wave2Retracement >= 0.50 && pattern.wave2Retracement <= 0.618)
        score += 10.0;  // Golden zone
    else if(pattern.wave2Retracement >= 0.382 && pattern.wave2Retracement <= 0.786)
        score += 5.0;
    
    // Wave 3 extension quality
    if(pattern.wave3Extension >= 1.618)
        score += 15.0;  // Strong Wave 3
    else if(pattern.wave3Extension >= 1.0)
        score += 8.0;
    
    // Completion bonus
    if(pattern.isComplete)
        score += 10.0;
    
    // State-based bonus (Wave 3 and 5 entries are high value)
    if(pattern.currentState == STATE_WAVE_3)
        score += 15.0;
    else if(pattern.currentState == STATE_WAVE_5)
        score += 10.0;
    
    pattern.confidence = MathMin(100.0, score) / 100.0;
}

//+------------------------------------------------------------------+
//| Scan Patterns                                                    |
//+------------------------------------------------------------------+
void CWavePatternEngine::ScanPatterns()
{
    if(m_zigzag == NULL) return;
    
    m_zigzag.Update(200);
    
    ArrayResize(m_patterns, 0);
    m_patternCount = 0;
    
    // Get wave points
    SZigZagPivot w0, w1, w2, w3, w4;
    if(!m_zigzag.GetWavePoints(w0, w1, w2, w3, w4))
        return;
    
    // Determine if bullish or bearish based on first two pivots
    bool isBullish = (w1.price > w0.price);
    
    SElliottWavePattern pattern;
    pattern.isBullish = isBullish;
    pattern.wave0 = w0.price; pattern.time0 = w0.time;
    pattern.wave1 = w1.price; pattern.time1 = w1.time;
    pattern.wave2 = w2.price; pattern.time2 = w2.time;
    pattern.wave3 = w3.price; pattern.time3 = w3.time;
    pattern.wave4 = w4.price; pattern.time4 = w4.time;
    
    // Calculate ratios
    double wave1Size = MathAbs(w1.price - w0.price);
    double wave3Size = MathAbs(w3.price - w2.price);
    
    if(wave1Size > 0)
    {
        if(isBullish)
            pattern.wave2Retracement = (w1.price - w2.price) / wave1Size;
        else
            pattern.wave2Retracement = (w2.price - w1.price) / wave1Size;
        
        pattern.wave3Extension = wave3Size / wave1Size;
    }
    
    if(wave3Size > 0)
    {
        if(isBullish)
            pattern.wave4Retracement = (w3.price - w4.price) / wave3Size;
        else
            pattern.wave4Retracement = (w4.price - w3.price) / wave3Size;
    }
    
    // Validate wave structure
    bool wave2Valid = ValidateWave2(w0.price, w1.price, w2.price, isBullish);
    bool wave3Valid = ValidateWave3(w0.price, w1.price, w2.price, w3.price, isBullish);
    bool wave4Valid = ValidateWave4(w1.price, w2.price, w3.price, w4.price, isBullish);
    
    // Determine current state
    double lastPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
    
    if(wave2Valid && !wave3Valid)
    {
        pattern.currentState = STATE_WAVE_3;  // Wave 3 in progress
        pattern.type = isBullish ? WAVE_IMPULSE_BULLISH : WAVE_IMPULSE_BEARISH;
        pattern.isValid = true;
        pattern.wave3Target = CalculateWave3Target(w0.price, w1.price, w2.price, isBullish);
    }
    else if(wave2Valid && wave3Valid && !wave4Valid)
    {
        pattern.currentState = STATE_WAVE_4;  // Wave 4 in progress
        pattern.type = isBullish ? WAVE_IMPULSE_BULLISH : WAVE_IMPULSE_BEARISH;
        pattern.isValid = true;
    }
    else if(wave2Valid && wave3Valid && wave4Valid)
    {
        pattern.currentState = STATE_WAVE_5;  // Wave 5 in progress
        pattern.type = isBullish ? WAVE_IMPULSE_BULLISH : WAVE_IMPULSE_BEARISH;
        pattern.isValid = true;
        pattern.wave5Target = CalculateWave5Target(w3.price, w4.price, isBullish);
        
        // Check if Wave 5 is complete
        if(ValidateWave5(w3.price, w4.price, lastPrice, isBullish))
        {
            pattern.wave5 = lastPrice;
            pattern.isComplete = true;
            pattern.currentState = STATE_COMPLETE;
        }
    }
    else
    {
        pattern.isValid = false;
        pattern.invalidReason = !wave2Valid ? "Invalid Wave 2" : 
                               (!wave3Valid ? "Invalid Wave 3" : "Invalid Wave 4");
    }
    
    if(pattern.isValid)
    {
        ScorePattern(pattern);
        
        if(m_patternCount < m_maxPatterns)
        {
            ArrayResize(m_patterns, m_patternCount + 1);
            m_patterns[m_patternCount++] = pattern;
        }
    }
}

//+------------------------------------------------------------------+
//| Update                                                           |
//+------------------------------------------------------------------+
void CWavePatternEngine::Update()
{
    ScanPatterns();
}

//+------------------------------------------------------------------+
//| Get Pattern At Index                                             |
//+------------------------------------------------------------------+
bool CWavePatternEngine::GetPatternAt(int index, SElliottWavePattern &pattern)
{
    if(index < 0 || index >= m_patternCount) return false;
    pattern = m_patterns[index];
    return true;
}

//+------------------------------------------------------------------+
//| Get Best Bullish Pattern                                         |
//+------------------------------------------------------------------+
bool CWavePatternEngine::GetBestBullishPattern(SElliottWavePattern &pattern)
{
    double bestScore = 0;
    int bestIndex = -1;
    
    for(int i = 0; i < m_patternCount; i++)
    {
        if(m_patterns[i].isBullish && m_patterns[i].isValid &&
           m_patterns[i].confidence > bestScore)
        {
            bestScore = m_patterns[i].confidence;
            bestIndex = i;
        }
    }
    
    if(bestIndex >= 0)
    {
        pattern = m_patterns[bestIndex];
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Get Best Bearish Pattern                                         |
//+------------------------------------------------------------------+
bool CWavePatternEngine::GetBestBearishPattern(SElliottWavePattern &pattern)
{
    double bestScore = 0;
    int bestIndex = -1;
    
    for(int i = 0; i < m_patternCount; i++)
    {
        if(!m_patterns[i].isBullish && m_patterns[i].isValid &&
           m_patterns[i].confidence > bestScore)
        {
            bestScore = m_patterns[i].confidence;
            bestIndex = i;
        }
    }
    
    if(bestIndex >= 0)
    {
        pattern = m_patterns[bestIndex];
        return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| Is In Wave 3 Entry                                               |
//+------------------------------------------------------------------+
bool CWavePatternEngine::IsInWave3Entry(SElliottWavePattern &pattern)
{
    for(int i = 0; i < m_patternCount; i++)
    {
        if(m_patterns[i].isValid && m_patterns[i].currentState == STATE_WAVE_3)
        {
            pattern = m_patterns[i];
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Is In Wave 5 Entry                                               |
//+------------------------------------------------------------------+
bool CWavePatternEngine::IsInWave5Entry(SElliottWavePattern &pattern)
{
    for(int i = 0; i < m_patternCount; i++)
    {
        if(m_patterns[i].isValid && m_patterns[i].currentState == STATE_WAVE_5)
        {
            pattern = m_patterns[i];
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Is Wave Complete                                                 |
//+------------------------------------------------------------------+
bool CWavePatternEngine::IsWaveComplete(const SElliottWavePattern &pattern)
{
    return pattern.isComplete;
}

//+------------------------------------------------------------------+
//| Get Wave 3 Target                                                |
//+------------------------------------------------------------------+
double CWavePatternEngine::GetWave3Target(const SElliottWavePattern &pattern)
{
    return pattern.wave3Target;
}

//+------------------------------------------------------------------+
//| Get Wave 5 Target                                                |
//+------------------------------------------------------------------+
double CWavePatternEngine::GetWave5Target(const SElliottWavePattern &pattern)
{
    return pattern.wave5Target;
}

#endif // __ELLIOTT_WAVE_PATTERN_ENGINE_MQH__
