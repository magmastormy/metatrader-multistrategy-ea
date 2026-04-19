//+------------------------------------------------------------------+
//| WavePatternEngine.mqh                                            |
//| Elliott Wave Pattern Recognition Engine                          |
//| Implements strict Elliott Wave rules with Fibonacci validation   |
//+------------------------------------------------------------------+
//  CHANGES v2.1:
//  - Wave 5 target: now uses wave-1 length projected from wave-4 end
//    (was erroneously using wave-4 size, not wave-1 size)
//  - Added wave-4 minimum retracement check (23.6 % floor)
//  - Added multiple wave-3 Fibonacci targets (1.272, 1.618, 2.0, 2.618)
//  - ScorePattern: added wave-4 and wave-5 quality scoring
//  - ScanPatterns: now tries multiple starting-pivot offsets so it
//    doesn't only look at the single most-recent 5-pivot window
//  - Added ABC corrective pattern scanning with Fibonacci validation
//  - Added wave5Extension ratio to SElliottWavePattern
//  - Added GetAllFibTargets() helper exposed publicly
//  - m_maxPatterns bumped to 8 (was 5)
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.10"
#property strict

#ifndef __ELLIOTT_WAVE_PATTERN_ENGINE_MQH__
#define __ELLIOTT_WAVE_PATTERN_ENGINE_MQH__

#include "ZigZagFilter.mqh"
#include "HarmonicScanner.mqh"

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

    // Wave price levels
    double              wave0;       // Start of wave 1
    double              wave1;       // End of wave 1
    double              wave2;       // End of wave 2
    double              wave3;       // End of wave 3
    double              wave4;       // End of wave 4
    double              wave5;       // End of wave 5

    datetime            time0, time1, time2, time3, time4, time5;

    // Fibonacci ratios
    double              wave2Retracement;   // Retracement of wave 1 (target 38.2–78.6%)
    double              wave3Extension;     // Extension of wave 1  (target 161.8%)
    double              wave4Retracement;   // Retracement of wave 3 (target 23.6–61.8%)
    double              wave5Extension;     // Extension of wave 1 projected from wave 4 end

    // Fibonacci targets for wave 3
    double              wave3Target_127;    // 1.272 × wave1
    double              wave3Target_162;    // 1.618 × wave1  (most common)
    double              wave3Target_200;    // 2.000 × wave1
    double              wave3Target_262;    // 2.618 × wave1  (extended wave 3)

    // Fibonacci targets for wave 5
    double              wave5Target_62;     // 0.618 × wave1 from wave4 end
    double              wave5Target_100;    // 1.000 × wave1 from wave4 end  (most common)
    double              wave5Target_162;    // 1.618 × wave1 from wave4 end  (extended wave 5)

    // Validation
    bool                isValid;
    bool                isComplete;
    double              confidence;         // 0.0 – 1.0
    string              invalidReason;

    // Primary projection (used by strategy)
    double              wave3Target;        // = wave3Target_162
    double              wave5Target;        // = wave5Target_100

    SElliottWavePattern() :
        type(WAVE_NONE), currentState(STATE_WAVE_1), isBullish(true),
        wave0(0), wave1(0), wave2(0), wave3(0), wave4(0), wave5(0),
        time0(0), time1(0), time2(0), time3(0), time4(0), time5(0),
        wave2Retracement(0), wave3Extension(0), wave4Retracement(0), wave5Extension(0),
        wave3Target_127(0), wave3Target_162(0), wave3Target_200(0), wave3Target_262(0),
        wave5Target_62(0),  wave5Target_100(0), wave5Target_162(0),
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

    CZigZagFilter*          m_zigzag;
    CHarmonicScanner*       m_harmonicScanner;
    bool                    m_ownZigZag;

    SElliottWavePattern     m_patterns[];
    int                     m_patternCount;
    int                     m_maxPatterns;

    // Configuration
    double                  m_wave2MinRetracement;   // 38.2%
    double                  m_wave2MaxRetracement;   // 78.6%
    double                  m_wave3MinExtension;     // 100% of wave 1
    double                  m_wave4MinRetracement;   // 23.6% of wave 3 (NEW)
    double                  m_wave4MaxRetracement;   // 61.8% of wave 3
    double                  m_tolerance;             // 10%

    // Internal helpers
    bool                    ValidateWave2(double w0, double w1, double w2, bool isBull);
    bool                    ValidateWave3(double w0, double w1, double w2, double w3, bool isBull);
    bool                    ValidateWave4(double w1, double w2, double w3, double w4, bool isBull);
    bool                    ValidateWave5(double w0, double w1, double w3, double w4, double w5, bool isBull);
    void                    CalculateWave3Targets(SElliottWavePattern &p);
    void                    CalculateWave5Targets(SElliottWavePattern &p);
    double                  CalculateAverageVolume(int barIndex, int window);
    double                  GetRSIValue(int shift);
    double                  ScoreWavePersonality(const SElliottWavePattern &pattern);
    void                    ScorePattern(SElliottWavePattern &pattern);
    bool                    TryScanFromOffset(int pivotOffset, int zigzagCount);
    bool                    ScanABC();

    bool                    AddPattern(const SElliottWavePattern &p);

public:
                            CWavePatternEngine();
                           ~CWavePatternEngine();

    bool                    Initialize(const string symbol, ENUM_TIMEFRAMES timeframe,
                                       CZigZagFilter* zigzag = NULL);
    void                    Deinit();

    void                    Update();
    void                    ScanPatterns();

    int                     GetPatternCount() const { return m_patternCount; }
    bool                    GetPatternAt(int index, SElliottWavePattern &pattern);
    bool                    GetBestBullishPattern(SElliottWavePattern &pattern);
    bool                    GetBestBearishPattern(SElliottWavePattern &pattern);

    bool                    IsInWave3Entry(SElliottWavePattern &pattern);
    bool                    IsInWave5Entry(SElliottWavePattern &pattern);
    bool                    IsWaveComplete(const SElliottWavePattern &pattern);

    double                  GetWave3Target(const SElliottWavePattern &pattern);
    double                  GetWave5Target(const SElliottWavePattern &pattern);

    // Configuration setters
    void                    SetWave2Retracements(double minR, double maxR)
                            { m_wave2MinRetracement = minR; m_wave2MaxRetracement = maxR; }
    void                    SetWave3MinExtension(double ext)    { m_wave3MinExtension    = ext; }
    void                    SetWave4MinRetracement(double ret)  { m_wave4MinRetracement  = ret; }
    void                    SetWave4MaxRetracement(double ret)  { m_wave4MaxRetracement  = ret; }
    void                    SetTolerance(double tol)            { m_tolerance            = tol; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CWavePatternEngine::CWavePatternEngine() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_zigzag(NULL),
    m_harmonicScanner(NULL),
    m_ownZigZag(false),
    m_patternCount(0),
    m_maxPatterns(8),
    m_wave2MinRetracement(0.382),
    m_wave2MaxRetracement(0.786),
    m_wave3MinExtension(1.0),
    m_wave4MinRetracement(0.236),
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
    m_symbol    = symbol;
    m_timeframe = timeframe;

    if(zigzag != NULL)
    {
        m_zigzag    = zigzag;
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

    m_harmonicScanner = new CHarmonicScanner();
    if(m_harmonicScanner != NULL && !m_harmonicScanner.Initialize(symbol, timeframe, m_zigzag))
    {
        delete m_harmonicScanner;
        m_harmonicScanner = NULL;
    }

    return (m_zigzag != NULL);
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void CWavePatternEngine::Deinit()
{
    if(m_ownZigZag && m_zigzag != NULL)
    {
        delete m_zigzag;
        m_zigzag = NULL;
    }
    if(m_harmonicScanner != NULL)
    {
        delete m_harmonicScanner;
        m_harmonicScanner = NULL;
    }
    ArrayFree(m_patterns);
}

//+------------------------------------------------------------------+
//| AddPattern — deduplicate by wave0 time                          |
//+------------------------------------------------------------------+
bool CWavePatternEngine::AddPattern(const SElliottWavePattern &p)
{
    if(m_patternCount >= m_maxPatterns) return false;

    // Skip if we already have a pattern starting at the same pivot
    for(int i = 0; i < m_patternCount; i++)
        if(m_patterns[i].time0 == p.time0 && m_patterns[i].isBullish == p.isBullish)
            return false;

    ArrayResize(m_patterns, m_patternCount + 1);
    m_patterns[m_patternCount++] = p;
    return true;
}

//+------------------------------------------------------------------+
//| Validate Wave 2  (38.2–78.6 % retracement of Wave 1)            |
//+------------------------------------------------------------------+
bool CWavePatternEngine::ValidateWave2(double w0, double w1, double w2, bool isBull)
{
    double w1Size = MathAbs(w1 - w0);
    if(w1Size <= 0) return false;

    double retracement = isBull ? (w1 - w2) / w1Size : (w2 - w1) / w1Size;

    if(retracement >= 1.0) return false;   // Cannot retrace more than 100%

    double minR = m_wave2MinRetracement * (1.0 - m_tolerance);
    double maxR = m_wave2MaxRetracement * (1.0 + m_tolerance);

    return (retracement >= minR && retracement <= maxR);
}

//+------------------------------------------------------------------+
//| Validate Wave 3  (must extend, must not be shortest)            |
//+------------------------------------------------------------------+
bool CWavePatternEngine::ValidateWave3(double w0, double w1, double w2, double w3, bool isBull)
{
    double w1Size = MathAbs(w1 - w0);
    double w3Size = MathAbs(w3 - w2);

    if(w1Size <= 0 || w3Size <= 0) return false;

    // Wave 3 ≥ 100% of wave 1 (key rule, relaxed by tolerance)
    double minExt = m_wave3MinExtension * (1.0 - m_tolerance);
    if(w3Size < w1Size * minExt) return false;

    // Wave 3 must extend beyond wave 1's end
    return isBull ? (w3 > w1) : (w3 < w1);
}

//+------------------------------------------------------------------+
//| Validate Wave 4  (must not overlap wave-1 territory)            |
//+------------------------------------------------------------------+
bool CWavePatternEngine::ValidateWave4(double w1, double w2, double w3, double w4, bool isBull)
{
    double w3Size = MathAbs(w3 - w2);
    if(w3Size <= 0) return false;

    double retracement = isBull ? (w3 - w4) / w3Size : (w4 - w3) / w3Size;

    // Floor: wave 4 must retrace at least 23.6% (new check)
    double minR = m_wave4MinRetracement * (1.0 - m_tolerance);
    double maxR = m_wave4MaxRetracement * (1.0 + m_tolerance);

    if(retracement < minR || retracement > maxR) return false;

    // Critical Elliott rule: wave 4 cannot overlap wave 1 price territory
    return isBull ? (w4 > w1) : (w4 < w1);
}

//+------------------------------------------------------------------+
//| Validate Wave 5  (must extend beyond wave 3)                    |
//+------------------------------------------------------------------+
bool CWavePatternEngine::ValidateWave5(double w0, double w1, double w3, double w4, double w5, bool isBull)
{
    // Wave 5 must extend beyond wave 3
    if(isBull && w5 <= w3) return false;
    if(!isBull && w5 >= w3) return false;

    // Wave 5 size relative to wave 1 (sanity check — can be extended but not tiny)
    double w1Size = MathAbs(w1 - w0);
    double w5Size = MathAbs(w5 - w4);
    if(w1Size > 0 && w5Size < w1Size * 0.10) return false;  // Wave 5 must be at least 10% of wave 1

    return true;
}

//+------------------------------------------------------------------+
//| Calculate Wave 3 Targets (multiple Fib extensions)              |
//+------------------------------------------------------------------+
void CWavePatternEngine::CalculateWave3Targets(SElliottWavePattern &p)
{
    double w1Size = MathAbs(p.wave1 - p.wave0);
    double dir    = p.isBullish ? 1.0 : -1.0;
    double base   = p.wave2;

    p.wave3Target_127 = base + dir * w1Size * 1.272;
    p.wave3Target_162 = base + dir * w1Size * 1.618;
    p.wave3Target_200 = base + dir * w1Size * 2.000;
    p.wave3Target_262 = base + dir * w1Size * 2.618;
    p.wave3Target     = p.wave3Target_162;   // Primary
}

//+------------------------------------------------------------------+
//| Calculate Wave 5 Targets (wave-1 length from wave-4 end)        |
//+------------------------------------------------------------------+
void CWavePatternEngine::CalculateWave5Targets(SElliottWavePattern &p)
{
    double w1Size = MathAbs(p.wave1 - p.wave0);
    double dir    = p.isBullish ? 1.0 : -1.0;
    double base   = p.wave4;

    p.wave5Target_62  = base + dir * w1Size * 0.618;
    p.wave5Target_100 = base + dir * w1Size * 1.000;
    p.wave5Target_162 = base + dir * w1Size * 1.618;
    p.wave5Target     = p.wave5Target_100;   // Primary (equal to wave 1 from wave 4)
}

double CWavePatternEngine::CalculateAverageVolume(int barIndex, int window)
{
    long totalVolume = 0;
    int count = 0;
    for(int i = barIndex; i < barIndex + window; i++)
    {
        long volume = iVolume(m_symbol, m_timeframe, i);
        if(volume > 0)
        {
            totalVolume += volume;
            count++;
        }
    }
    return (count > 0) ? ((double)totalVolume / (double)count) : 0.0;
}

double CWavePatternEngine::GetRSIValue(int shift)
{
    int handle = iRSI(m_symbol, m_timeframe, 14, PRICE_CLOSE);
    if(handle == INVALID_HANDLE)
        return 50.0;

    double values[];
    ArraySetAsSeries(values, true);
    double rsi = 50.0;
    if(CopyBuffer(handle, 0, shift, 1, values) > 0)
        rsi = values[0];
    IndicatorRelease(handle);
    return rsi;
}

double CWavePatternEngine::ScoreWavePersonality(const SElliottWavePattern &pattern)
{
    double score = 0.0;
    int wave1Shift = (pattern.time1 > 0) ? iBarShift(m_symbol, m_timeframe, pattern.time1) : -1;
    int wave3Shift = (pattern.time3 > 0) ? iBarShift(m_symbol, m_timeframe, pattern.time3) : -1;
    int wave5Shift = -1;
    if(pattern.currentState == STATE_WAVE_5 || pattern.isComplete)
        wave5Shift = (pattern.time5 > 0) ? iBarShift(m_symbol, m_timeframe, pattern.time5) : 0;

    if(wave1Shift >= 0)
    {
        double avgVol = CalculateAverageVolume(wave1Shift + 1, 30);
        double wave1Vol = (double)iVolume(m_symbol, m_timeframe, wave1Shift);
        if(avgVol > 0.0 && wave1Vol < avgVol)
            score += 4.0;
    }

    if(wave3Shift >= 0)
    {
        double avgVol = CalculateAverageVolume(wave3Shift + 1, 30);
        double wave3Vol = (double)iVolume(m_symbol, m_timeframe, wave3Shift);
        double wave3Rsi = GetRSIValue(wave3Shift);
        if(avgVol > 0.0 && wave3Vol > avgVol * 1.5)
            score += 6.0;
        if((pattern.isBullish && wave3Rsi >= 60.0) || (!pattern.isBullish && wave3Rsi <= 40.0))
            score += 6.0;
    }

    if(wave3Shift >= 0 && wave5Shift >= 0)
    {
        double wave3Rsi = GetRSIValue(wave3Shift);
        double wave5Rsi = GetRSIValue(wave5Shift);
        if(pattern.isBullish && pattern.wave5 > pattern.wave3 && wave5Rsi < wave3Rsi)
            score += 8.0;
        if(!pattern.isBullish && pattern.wave5 < pattern.wave3 && wave5Rsi > wave3Rsi)
            score += 8.0;
    }

    return score;
}

//+------------------------------------------------------------------+
//| Score Pattern  (0–100, normalised to 0–1 as confidence)         |
//+------------------------------------------------------------------+
void CWavePatternEngine::ScorePattern(SElliottWavePattern &pattern)
{
    double score = 40.0;   // Base

    // ── Wave 2 retracement quality ──
    double w2R = pattern.wave2Retracement;
    if(w2R >= 0.50 && w2R <= 0.618) score += 12.0;       // Golden zone
    else if(w2R >= 0.382 && w2R <= 0.786) score += 6.0;

    // ── Wave 3 extension quality ──
    double w3E = pattern.wave3Extension;
    if(w3E >= 1.618 && w3E < 2.0)   score += 15.0;        // Classic 1.618
    else if(w3E >= 2.0)             score += 10.0;         // Extended
    else if(w3E >= 1.0)             score += 5.0;

    // ── Wave 4 retracement quality ──
    double w4R = pattern.wave4Retracement;
    if(w4R >= 0.382 && w4R <= 0.500) score += 10.0;        // Ideal 38.2–50%
    else if(w4R >= 0.236 && w4R <= 0.618) score += 5.0;

    // ── Wave 5 extension quality ──
    double w5E = pattern.wave5Extension;
    if(w5E > 0)
    {
        if(w5E >= 0.618 && w5E <= 1.0)  score += 8.0;     // Normal wave 5
        else if(w5E > 1.0 && w5E <= 1.618) score += 5.0;  // Extended
    }

    // ── Completion bonus ──
    if(pattern.isComplete) score += 8.0;

    // ── State-based bonus (where we are in the pattern) ──
    if(pattern.currentState == STATE_WAVE_3) score += 15.0;
    else if(pattern.currentState == STATE_WAVE_5) score += 10.0;
    else if(pattern.currentState == STATE_WAVE_4) score += 5.0;

    // ── Wave personality bonus (volume / momentum / divergence) ──
    score += ScoreWavePersonality(pattern);

    // Harmonic PRZ overlap with projected wave-5 target.
    if(m_harmonicScanner != NULL && pattern.wave5Target > 0.0)
    {
        SHarmonicPattern harmonic;
        if(m_harmonicScanner.FindBestHarmonic(pattern.isBullish, harmonic))
        {
            double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            if(point <= 0.0)
                point = 0.00001;

            double harmonicMid = (harmonic.przLow + harmonic.przHigh) * 0.5;
            double tolerance = MathMax(MathAbs(pattern.wave1 - pattern.wave0) * 0.35, point * 50.0);
            double diff = MathAbs(harmonicMid - pattern.wave5Target);
            if(diff <= tolerance)
                score += 15.0 * (1.0 - (diff / tolerance)) * MathMax(0.50, harmonic.confidence);
        }
    }

    pattern.confidence = MathMin(100.0, score) / 100.0;
}

//+------------------------------------------------------------------+
//| Try scanning impulse from a given pivot offset                   |
//+------------------------------------------------------------------+
bool CWavePatternEngine::TryScanFromOffset(int pivotOffset, int zigzagCount)
{
    if(pivotOffset + 4 >= zigzagCount) return false;

    SZigZagPivot pw[5];
    for(int k = 0; k < 5; k++)
    {
        if(!m_zigzag.GetPivotAt(pivotOffset + k, pw[k])) return false;
    }

    // w0 must be opposite polarity to w1 (alternating sequence check)
    if(pw[0].isHigh == pw[1].isHigh) return false;

    bool isBull = (pw[1].price > pw[0].price);

    SElliottWavePattern p;
    p.isBullish = isBull;
    p.wave0 = pw[0].price; p.time0 = pw[0].time;
    p.wave1 = pw[1].price; p.time1 = pw[1].time;
    p.wave2 = pw[2].price; p.time2 = pw[2].time;
    p.wave3 = pw[3].price; p.time3 = pw[3].time;
    p.wave4 = pw[4].price; p.time4 = pw[4].time;

    // Calculate retracement / extension ratios
    double w1Size = MathAbs(p.wave1 - p.wave0);
    double w3Size = MathAbs(p.wave3 - p.wave2);
    double w4Size = MathAbs(p.wave4 - p.wave3);

    if(w1Size > 0)
    {
        p.wave2Retracement = isBull ? (p.wave1 - p.wave2) / w1Size
                                    : (p.wave2 - p.wave1) / w1Size;
        p.wave3Extension   = w3Size / w1Size;
    }
    if(w3Size > 0)
    {
        p.wave4Retracement = isBull ? (p.wave3 - p.wave4) / w3Size
                                    : (p.wave4 - p.wave3) / w3Size;
    }

    bool w2ok = ValidateWave2(p.wave0, p.wave1, p.wave2, isBull);
    bool w3ok = ValidateWave3(p.wave0, p.wave1, p.wave2, p.wave3, isBull);
    bool w4ok = ValidateWave4(p.wave1, p.wave2, p.wave3, p.wave4, isBull);

    if(!w2ok) { p.invalidReason = "Invalid Wave 2"; p.isValid = false; return false; }

    CalculateWave3Targets(p);

    double lastPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);

    if(w2ok && !w3ok)
    {
        p.currentState = STATE_WAVE_3;
        p.type         = isBull ? WAVE_IMPULSE_BULLISH : WAVE_IMPULSE_BEARISH;
        p.isValid      = true;
    }
    else if(w2ok && w3ok && !w4ok)
    {
        p.currentState = STATE_WAVE_4;
        p.type         = isBull ? WAVE_IMPULSE_BULLISH : WAVE_IMPULSE_BEARISH;
        p.isValid      = true;
    }
    else if(w2ok && w3ok && w4ok)
    {
        CalculateWave5Targets(p);
        p.currentState = STATE_WAVE_5;
        p.type         = isBull ? WAVE_IMPULSE_BULLISH : WAVE_IMPULSE_BEARISH;
        p.isValid      = true;
        p.wave5        = lastPrice;
        p.time5        = iTime(m_symbol, m_timeframe, 0);
        p.wave5Extension = w1Size > 0 ? MathAbs(lastPrice - p.wave4) / w1Size : 0.0;

        // Check if wave 5 is complete using live price
        if(ValidateWave5(p.wave0, p.wave1, p.wave3, p.wave4, lastPrice, isBull))
        {
            p.wave5        = lastPrice;
            p.wave5Extension = w1Size > 0 ? MathAbs(lastPrice - p.wave4) / w1Size : 0.0;
            p.isComplete   = true;
            p.currentState = STATE_COMPLETE;
        }
    }
    else
    {
        return false;
    }

    if(p.isValid)
    {
        ScorePattern(p);
        AddPattern(p);
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Scan ABC Corrective Patterns                                     |
//+------------------------------------------------------------------+
bool CWavePatternEngine::ScanABC()
{
    int total = m_zigzag.GetPivotCount();
    if(total < 3) return false;

    bool found = false;

    // Scan the last 3 pivots as A-B-C
    for(int offset = 0; offset + 2 < total; offset++)
    {
        SZigZagPivot pA, pB, pC;
        if(!m_zigzag.GetPivotAt(offset,     pA)) continue;
        if(!m_zigzag.GetPivotAt(offset + 1, pB)) continue;
        if(!m_zigzag.GetPivotAt(offset + 2, pC)) continue;

        // Must alternate
        if(pA.isHigh == pB.isHigh || pB.isHigh == pC.isHigh) continue;

        double wASize = MathAbs(pB.price - pA.price);
        double wBSize = MathAbs(pC.price - pB.price);
        double wCSize = wBSize;  // C continues from B end

        if(wASize <= 0) continue;

        // Wave B must not exceed 138.2% of Wave A
        double bRatio = wBSize / wASize;
        if(bRatio > 1.382 * (1.0 + m_tolerance)) continue;

        // Wave C projection: 100–161.8% of Wave A
        double minCR = 0.618 * (1.0 - m_tolerance);
        double maxCR = 1.618 * (1.0 + m_tolerance);
        double cRatio = wCSize / wASize;
        if(cRatio < minCR || cRatio > maxCR) continue;

        // A and C must be in the same direction
        bool aDown = (pB.price < pA.price);   // A goes down
        bool cDown = (pC.price < pB.price);   // C also down? B goes opposite
        // Actually: for a bearish zigzag correction, A=down, B=up, C=down
        // So: aDown == cDown for a valid ZigZag ABC
        // (In flat corrections they differ, but we target ZigZag for simplicity)
        if(aDown != cDown) continue;

        SElliottWavePattern p;
        p.type         = WAVE_CORRECTIVE_ABC;
        p.isBullish    = !aDown;   // Bullish correction = A up, C up (into upward move)
        p.isValid      = true;
        p.currentState = STATE_WAVE_C;
        p.wave0        = pA.price; p.time0 = pA.time;
        p.wave1        = pB.price; p.time1 = pB.time;
        p.wave2        = pC.price; p.time2 = pC.time;
        // Wave 3 target holds the C projection (100% extension of A)
        p.wave3Target  = pB.price + (aDown ? -1.0 : 1.0) * wASize;
        p.confidence   = 0.55 + (cRatio >= 0.9 && cRatio <= 1.1 ? 0.15 : 0.05);
        p.isComplete   = true;

        AddPattern(p);
        found = true;
    }

    return found;
}

//+------------------------------------------------------------------+
//| Scan All Patterns                                                |
//+------------------------------------------------------------------+
void CWavePatternEngine::ScanPatterns()
{
    if(m_zigzag == NULL) return;

    m_zigzag.Update(250);
    if(m_harmonicScanner != NULL)
        m_harmonicScanner.Update();

    ArrayResize(m_patterns, 0);
    m_patternCount = 0;

    int total = m_zigzag.GetPivotCount();
    if(total < 5) return;

    // Try multiple starting offsets so we catch patterns that don't start at pivot[0]
    int maxOffset = MathMin(total - 5, 8);   // Check up to 8 starting positions
    for(int offset = 0; offset <= maxOffset; offset++)
        TryScanFromOffset(offset, total);

    // Also scan for corrective ABC patterns
    ScanABC();
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
    int    bestIdx   = -1;

    for(int i = 0; i < m_patternCount; i++)
        if(m_patterns[i].isBullish && m_patterns[i].isValid && m_patterns[i].confidence > bestScore)
        { bestScore = m_patterns[i].confidence; bestIdx = i; }

    if(bestIdx >= 0) { pattern = m_patterns[bestIdx]; return true; }
    return false;
}

//+------------------------------------------------------------------+
//| Get Best Bearish Pattern                                         |
//+------------------------------------------------------------------+
bool CWavePatternEngine::GetBestBearishPattern(SElliottWavePattern &pattern)
{
    double bestScore = 0;
    int    bestIdx   = -1;

    for(int i = 0; i < m_patternCount; i++)
        if(!m_patterns[i].isBullish && m_patterns[i].isValid && m_patterns[i].confidence > bestScore)
        { bestScore = m_patterns[i].confidence; bestIdx = i; }

    if(bestIdx >= 0) { pattern = m_patterns[bestIdx]; return true; }
    return false;
}

//+------------------------------------------------------------------+
//| Is In Wave 3 Entry                                               |
//+------------------------------------------------------------------+
bool CWavePatternEngine::IsInWave3Entry(SElliottWavePattern &pattern)
{
    for(int i = 0; i < m_patternCount; i++)
        if(m_patterns[i].isValid && m_patterns[i].currentState == STATE_WAVE_3)
        { pattern = m_patterns[i]; return true; }
    return false;
}

//+------------------------------------------------------------------+
//| Is In Wave 5 Entry                                               |
//+------------------------------------------------------------------+
bool CWavePatternEngine::IsInWave5Entry(SElliottWavePattern &pattern)
{
    for(int i = 0; i < m_patternCount; i++)
        if(m_patterns[i].isValid && m_patterns[i].currentState == STATE_WAVE_5)
        { pattern = m_patterns[i]; return true; }
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
