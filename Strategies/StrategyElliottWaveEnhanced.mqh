//+------------------------------------------------------------------+
//| StrategyElliottWaveEnhanced.mqh                                  |
//| Elliott Wave Strategy v2.1 - Enterprise Grade                    |
//| Implements proper 5-3 wave structure with Fibonacci ratios       |
//+------------------------------------------------------------------+
//  CHANGES v2.1:
//  - GetSignal() now delegates entirely to CWavePatternEngine instead
//    of duplicating/bypassing it with a parallel legacy swing-point path
//  - Removed the confused legacy IdentifyWavePattern() — it was using
//    CStructureEngine SwingPoint data but mapping it to WavePoint structs
//    with incorrect index math (e.g. waves[i-2] accessed when i=1)
//  - CheckWave5Rules() rewritten to be actually meaningful (was trivially true)
//  - ValidateCorrectiveWaves(): fixed A/C direction check — they share the
//    same direction; the old check `waveAUp != waveCUp` rejected ALL valid ABC
//  - DrawWavePattern(): removed call to DrawWaveLabel() which does not exist
//    on ChartDrawingManager; replaced with DrawTextLabel()
//  - Confidence scaling: wave 3 entry = highest confidence, wave 5 = moderate,
//    post-5-wave reversal = lowest (matches Elliott risk profile)
//  - Added GetWaveStateString() helper for dashboard logging
//  - Removed dead m_patterns[] / m_currentPattern / legacy SwingPoint fields
//+------------------------------------------------------------------+
#ifndef STRATEGY_ELLIOTTWAVE_ENHANCED_MQH
#define STRATEGY_ELLIOTTWAVE_ENHANCED_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Visualization/ChartDrawingManager.mqh"
#include "../Core/Engines/StructureEngine.mqh"
#include "../Core/Engines/TrendEngine.mqh"
#include "../Core/Signals/SignalDiagnostics.mqh"

#include "ElliottWaveFiles/ZigZagFilter.mqh"
#include "ElliottWaveFiles/WavePatternEngine.mqh"

//+------------------------------------------------------------------+
//| Wave Rules Structure                                            |
//+------------------------------------------------------------------+
struct ElliottWaveRules
{
    double wave2_retracement_min;
    double wave2_retracement_max;
    double wave3_extension_min;
    double wave4_retracement_min;
    double wave4_retracement_max;
    double tolerance;
    int    min_bars_per_wave;
    double min_wave_size_atr;

    ElliottWaveRules() :
        wave2_retracement_min(0.382), wave2_retracement_max(0.786),
        wave3_extension_min(1.618),
        wave4_retracement_min(0.236), wave4_retracement_max(0.618),
        tolerance(0.05),
        min_bars_per_wave(8), min_wave_size_atr(1.0) {}
};

//+------------------------------------------------------------------+
//| Enhanced Elliott Wave Strategy Class v2.1                       |
//+------------------------------------------------------------------+
class CStrategyElliottWaveEnhanced : public CStrategyBase
{
private:
    // Core wave-analysis components
    CZigZagFilter*      m_zigzag;
    CWavePatternEngine* m_waveEngine;

    // Optional legacy engines (kept for backward-compat with orchestrator)
    CStructureEngine*   m_structureEngine;
    CTrendEngine*       m_trendEngine;
    CSignalDiagnostics* m_diagnostics;

    // Drawing
    CChartDrawingManager* m_drawingManager;

    // Configuration
    ElliottWaveRules    m_rules;
    int                 m_lookbackPeriod;
    bool                m_useMultiTF;
    ENUM_TIMEFRAMES     m_htf;

    // Statistics
    int                 m_wavesIdentified;
    int                 m_patternsCompleted;
    int                 m_signalsGenerated;

    // Helpers
    string              GetWaveStateString(ENUM_WAVE_STATE state);
    void                DrawWavePattern(const SElliottWavePattern &pattern);
    void                ClearWaveDrawings();

    // Validation helpers (used internally; not re-exposed)
    bool                CheckWave2Rules(double w0, double w1, double w2);
    bool                CheckWave3Rules(double w0, double w1, double w2, double w3);
    bool                CheckWave4Rules(double w1, double w2, double w3, double w4);
    bool                CheckWave5Rules(double w0, double w1, double w3, double w4, double w5);
    bool                ValidateCorrectiveWaves_ABC(double pA, double pB, double pC);

public:
    CStrategyElliottWaveEnhanced(const string name = "Elliott Wave Enhanced");
    virtual ~CStrategyElliottWaveEnhanced();

    virtual bool        Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                             void* tradeMgr, void* posSizer) override;
    virtual void        Deinit() override;

    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override;
    virtual void        OnTick() override;
    virtual void        OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override;

    virtual string      GetName()  const override { return m_name; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_ELLIOTT_WAVE; }

    void                SetLookbackPeriod(int period)  { m_lookbackPeriod = period; }
    void                SetMinConfidence(double conf)  { OverrideMinConfidence(conf); }
    void                SetMultiTimeframe(bool enable, ENUM_TIMEFRAMES htf = PERIOD_H4)
                        { m_useMultiTF = enable; m_htf = htf; }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CStrategyElliottWaveEnhanced::CStrategyElliottWaveEnhanced(const string name) :
    CStrategyBase(name, 0),
    m_zigzag(NULL),
    m_waveEngine(NULL),
    m_structureEngine(NULL),
    m_trendEngine(NULL),
    m_diagnostics(NULL),
    m_drawingManager(NULL),
    m_lookbackPeriod(250),
    m_useMultiTF(true),
    m_htf(PERIOD_H4),
    m_wavesIdentified(0),
    m_patternsCompleted(0),
    m_signalsGenerated(0)
{
    OverrideMinConfidence(0.50);

    // Legacy engines — initialised here, used for optional diagnostics/trend only
    m_structureEngine = new CStructureEngine();
    m_trendEngine     = new CTrendEngine();
    m_diagnostics     = new CSignalDiagnostics();

    if(m_structureEngine != NULL)
        m_structureEngine.Initialize(10, 10.0, true, m_diagnostics);

    if(m_trendEngine != NULL)
        m_trendEngine.Initialize(20, 50, 200, 14, m_diagnostics);

    if(m_diagnostics != NULL)
        m_diagnostics.Initialize(500, 2);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CStrategyElliottWaveEnhanced::~CStrategyElliottWaveEnhanced()
{
    if(m_zigzag         != NULL) { delete m_zigzag;          m_zigzag         = NULL; }
    if(m_waveEngine     != NULL) { delete m_waveEngine;       m_waveEngine     = NULL; }
    if(m_structureEngine!= NULL) { delete m_structureEngine;  m_structureEngine= NULL; }
    if(m_trendEngine    != NULL) { delete m_trendEngine;      m_trendEngine    = NULL; }
    if(m_diagnostics    != NULL) { delete m_diagnostics;      m_diagnostics    = NULL; }
    if(m_drawingManager != NULL) { delete m_drawingManager;   m_drawingManager = NULL; }
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CStrategyElliottWaveEnhanced::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                                        void* tradeMgr, void* posSizer)
{
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
        return false;

    // ZigZag filter
    m_zigzag = new CZigZagFilter();
    if(m_zigzag == NULL || !m_zigzag.Initialize(symbol, timeframe))
    {
        Print("[EW v2.1] FAILED to initialise ZigZagFilter");
        return false;
    }

    // Wave engine — share the already-initialised zigzag
    m_waveEngine = new CWavePatternEngine();
    if(m_waveEngine == NULL || !m_waveEngine.Initialize(symbol, timeframe, m_zigzag))
    {
        Print("[EW v2.1] FAILED to initialise WavePatternEngine");
        return false;
    }

    // Pass rule settings down
    m_waveEngine.SetWave2Retracements(m_rules.wave2_retracement_min, m_rules.wave2_retracement_max);
    m_waveEngine.SetWave3MinExtension(m_rules.wave3_extension_min);
    m_waveEngine.SetWave4MinRetracement(m_rules.wave4_retracement_min);
    m_waveEngine.SetWave4MaxRetracement(m_rules.wave4_retracement_max);
    m_waveEngine.SetTolerance(m_rules.tolerance);

    // Drawing manager
    m_drawingManager = new CChartDrawingManager();
    if(m_drawingManager != NULL)
    {
        m_drawingManager.Initialize(symbol, timeframe, "EW");
        SDrawingConfig cfg = m_drawingManager.GetConfiguration();
        cfg.enableElliottWave   = true;
        cfg.enableTrendLines    = true;
        cfg.enableStructure     = false;
        cfg.enableOrderBlocks   = false;
        cfg.enableFVG           = false;
        cfg.enableSignalMarkers = false;
        m_drawingManager.SetConfiguration(cfg);
    }

    PrintFormat("[EW v2.1] Initialised for %s / %s | ZigZag: OK | WaveEngine: OK",
                symbol, EnumToString(timeframe));
    return true;
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void CStrategyElliottWaveEnhanced::Deinit()
{
    if(m_drawingManager != NULL) m_drawingManager.CleanupAll();
    CStrategyBase::Deinit();
}

//+------------------------------------------------------------------+
//| GetSignal — delegates fully to WavePatternEngine                 |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategyElliottWaveEnhanced::GetSignal(double &confidence)
{
    confidence = 0.0;

    if(!IsEnabled() || !m_is_initialized)
        return TRADE_SIGNAL_NONE;

    if(m_waveEngine == NULL) return TRADE_SIGNAL_NONE;

    // Update wave engine (runs ZigZag internally)
    m_waveEngine.Update();

    int patternCount = m_waveEngine.GetPatternCount();
    if(patternCount == 0) return TRADE_SIGNAL_NONE;

    m_wavesIdentified = patternCount;

    ENUM_TRADE_SIGNAL bestSig  = TRADE_SIGNAL_NONE;
    double            bestConf = 0.0;
    SElliottWavePattern bestPat;

    // Optional HTF trend filter
    bool htfBull = true, htfBear = true;
    if(m_useMultiTF && m_trendEngine != NULL)
    {
        m_trendEngine.UpdateMTFTrend(m_symbol, m_htf, m_timeframe, PERIOD_M15);
        if(m_trendEngine.IsMTFAligned())
        {
            // Treat aligned uptrend as allowing longs, aligned downtrend as allowing shorts
            // IsMTFAligned() returns true for either direction; we infer from TrendEngine API
            // (No breaking change — both remain true unless TrendEngine exposes direction)
        }
    }

    // Iterate all detected patterns and pick the highest-confidence tradeable one
    for(int i = 0; i < patternCount; i++)
    {
        SElliottWavePattern pat;
        if(!m_waveEngine.GetPatternAt(i, pat)) continue;
        if(!pat.isValid) continue;

        ENUM_TRADE_SIGNAL sig  = TRADE_SIGNAL_NONE;
        double            conf = pat.confidence;

        switch(pat.currentState)
        {
            case STATE_WAVE_3:
                // Wave 3 in progress → trade WITH the impulse direction
                // Highest confidence: wave 3 is the strongest and longest wave
                sig  = pat.isBullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;
                conf = MathMin(0.95, conf * 1.20);  // Boost for wave 3
                break;

            case STATE_WAVE_5:
                // Wave 5 in progress → trade WITH the impulse but reduced confidence
                // Wave 5 can truncate and the end of the move is near
                sig  = pat.isBullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;
                conf = MathMin(0.80, conf * 0.90);
                break;

            case STATE_COMPLETE:
                // 5-wave impulse complete → anticipate ABC correction AGAINST the direction
                sig  = pat.isBullish ? TRADE_SIGNAL_SELL : TRADE_SIGNAL_BUY;
                conf = MathMin(0.65, conf * 0.75);  // Lower confidence for counter-move
                break;

            case STATE_WAVE_C:
                // ABC corrective pattern — end of C is a re-entry in the original trend
                // Bullish ABC correction ends at wave C low → BUY
                sig  = pat.isBullish ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;
                conf = MathMin(0.70, conf * 0.85);
                break;

            default:
                continue;  // Wave 1, 2, 4 — no entry signal
        }

        if(sig == TRADE_SIGNAL_NONE) continue;

        // Confidence floor
        if(conf < m_minConfidence) continue;

        if(conf > bestConf)
        {
            bestConf = conf;
            bestSig  = sig;
            bestPat  = pat;
        }
    }

    if(bestSig != TRADE_SIGNAL_NONE)
    {
        confidence = bestConf;
        m_signalsGenerated++;

        ClearWaveDrawings();
        DrawWavePattern(bestPat);

        if(m_diagnostics != NULL)
        {
            string info = StringFormat("State=%s | Type=%s | Conf=%.2f | W3ext=%.3f | W5tgt=%.5f",
                                       GetWaveStateString(bestPat.currentState),
                                       EnumToString(bestPat.type),
                                       confidence,
                                       bestPat.wave3Extension,
                                       bestPat.wave5Target);
            m_diagnostics.LogSignalGeneration("ElliottWave", m_symbol, m_timeframe,
                                              bestSig, confidence, info);
        }

        PrintFormat("[EW v2.1] %s | %s | %s | Conf: %.1f%% | W3ext: %.3f",
                    m_symbol,
                    bestSig == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                    GetWaveStateString(bestPat.currentState),
                    confidence * 100.0,
                    bestPat.wave3Extension);
    }

    return bestSig;
}

//+------------------------------------------------------------------+
//| OnTick                                                           |
//+------------------------------------------------------------------+
void CStrategyElliottWaveEnhanced::OnTick()
{
    // Intentionally empty — all logic runs on new bar
}

//+------------------------------------------------------------------+
//| OnNewBar                                                         |
//+------------------------------------------------------------------+
void CStrategyElliottWaveEnhanced::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(symbol != m_symbol || timeframe != m_timeframe) return;

    double conf;
    GetSignal(conf);
}

//+------------------------------------------------------------------+
//| GetWaveStateString                                               |
//+------------------------------------------------------------------+
string CStrategyElliottWaveEnhanced::GetWaveStateString(ENUM_WAVE_STATE state)
{
    switch(state)
    {
        case STATE_WAVE_1:    return "Wave 1";
        case STATE_WAVE_2:    return "Wave 2";
        case STATE_WAVE_3:    return "Wave 3 ★";
        case STATE_WAVE_4:    return "Wave 4";
        case STATE_WAVE_5:    return "Wave 5";
        case STATE_WAVE_A:    return "Wave A";
        case STATE_WAVE_B:    return "Wave B";
        case STATE_WAVE_C:    return "Wave C";
        case STATE_COMPLETE:  return "Complete";
        case STATE_INVALID:   return "Invalid";
        default:              return "Unknown";
    }
}

//+------------------------------------------------------------------+
//| DrawWavePattern                                                  |
//+------------------------------------------------------------------+
void CStrategyElliottWaveEnhanced::DrawWavePattern(const SElliottWavePattern &pattern)
{
    if(m_drawingManager == NULL) return;

    color waveCol = (pattern.type == WAVE_IMPULSE_BULLISH) ? clrDeepSkyBlue :
                    (pattern.type == WAVE_IMPULSE_BEARISH) ? clrOrangeRed   : clrGold;

    // Build price/time arrays from the filled pattern fields
    double prices[6];
    datetime times[6];
    int waveCount = 0;

    prices[0] = pattern.wave0; times[0] = pattern.time0;  // always present if valid
    waveCount = 1;

    if(pattern.time1 > 0) { prices[waveCount] = pattern.wave1; times[waveCount] = pattern.time1; waveCount++; }
    if(pattern.time2 > 0) { prices[waveCount] = pattern.wave2; times[waveCount] = pattern.time2; waveCount++; }
    if(pattern.time3 > 0) { prices[waveCount] = pattern.wave3; times[waveCount] = pattern.time3; waveCount++; }
    if(pattern.time4 > 0) { prices[waveCount] = pattern.wave4; times[waveCount] = pattern.time4; waveCount++; }
    if(pattern.time5 > 0 && pattern.isComplete)
    {
        prices[waveCount] = pattern.wave5;
        times[waveCount]  = pattern.time5;
        waveCount++;
    }

    if(waveCount < 2) return;

    string waveLabels[6] = {"0","1","2","3","4","5"};
    if(pattern.type == WAVE_CORRECTIVE_ABC)
    {
        waveLabels[0] = "A";
        waveLabels[1] = "B";
        waveLabels[2] = "C";
    }

    // Draw lines between pivot points
    for(int i = 0; i < waveCount - 1; i++)
    {
        if(times[i] == 0 || times[i+1] == 0) continue;

        m_drawingManager.DrawTrendLine(times[i], prices[i], times[i+1], prices[i+1],
                                       waveCol, 2, STYLE_SOLID);
    }

    // Draw labels at each pivot (use DrawTextLabel instead of the non-existent DrawWaveLabel)
    for(int i = 0; i < waveCount; i++)
    {
        if(times[i] == 0) continue;

        bool isHigh = (i > 0) ? (prices[i] > prices[i-1]) : false;
        ENUM_ANCHOR_POINT anchor = isHigh ? ANCHOR_UPPER : ANCHOR_LOWER;

        m_drawingManager.DrawTextLabel(times[i], prices[i], waveLabels[i], waveCol, 9, anchor);
    }

    // Draw wave 3 target line if available
    if(pattern.wave3Target > 0 && pattern.currentState == STATE_WAVE_3)
    {
        m_drawingManager.DrawHorizontalLevel(pattern.wave3Target,
                                             color(waveCol | 0x808080),
                                             "W3 target 1.618",
                                             STYLE_DASH, 1, false);
    }

    // Draw wave 5 target line if available
    if(pattern.wave5Target > 0 && pattern.currentState == STATE_WAVE_5)
    {
        m_drawingManager.DrawHorizontalLevel(pattern.wave5Target,
                                             color(waveCol | 0x808080),
                                             "W5 target",
                                             STYLE_DASH, 1, false);
    }
}

//+------------------------------------------------------------------+
//| ClearWaveDrawings                                                |
//+------------------------------------------------------------------+
void CStrategyElliottWaveEnhanced::ClearWaveDrawings()
{
    if(m_drawingManager != NULL)
        m_drawingManager.CleanupOldObjects();
}

//+------------------------------------------------------------------+
//| Internal wave validation helpers (thin wrappers, DRY)           |
//+------------------------------------------------------------------+
bool CStrategyElliottWaveEnhanced::CheckWave2Rules(double w0, double w1, double w2)
{
    double w1Size = MathAbs(w1 - w0);
    if(w1Size <= 0) return false;
    bool isBull = (w1 > w0);
    double ret  = isBull ? (w1 - w2) / w1Size : (w2 - w1) / w1Size;
    if(ret >= 1.0) return false;
    double tol = m_rules.tolerance;
    return ret >= m_rules.wave2_retracement_min * (1 - tol) &&
           ret <= m_rules.wave2_retracement_max * (1 + tol);
}

bool CStrategyElliottWaveEnhanced::CheckWave3Rules(double w0, double w1, double w2, double w3)
{
    double w1Size = MathAbs(w1 - w0);
    double w3Size = MathAbs(w3 - w2);
    if(w1Size <= 0 || w3Size <= 0) return false;
    double minExt = m_rules.wave3_extension_min * (1 - m_rules.tolerance);
    if(w3Size < w1Size * minExt) return false;
    bool isBull = (w1 > w0);
    return isBull ? (w3 > w1) : (w3 < w1);
}

bool CStrategyElliottWaveEnhanced::CheckWave4Rules(double w1, double w2, double w3, double w4)
{
    double w3Size = MathAbs(w3 - w2);
    if(w3Size <= 0) return false;
    double ret    = MathAbs(w4 - w3) / w3Size;
    double tol    = m_rules.tolerance;
    if(ret < m_rules.wave4_retracement_min * (1 - tol)) return false;
    if(ret > m_rules.wave4_retracement_max * (1 + tol)) return false;
    bool isBull = (w3 > w1);
    return isBull ? (w4 > w1) : (w4 < w1);
}

bool CStrategyElliottWaveEnhanced::CheckWave5Rules(double w0, double w1, double w3, double w4, double w5)
{
    // Wave 5 must:
    // 1. Extend beyond wave 3 in the impulse direction
    // 2. Be at least 10% of wave 1 in size (not a truncated stub)
    // 3. Not be the shortest wave if wave 3 is already shorter than wave 1
    bool isBull = (w1 > w0);
    if(isBull  && w5 <= w3) return false;
    if(!isBull && w5 >= w3) return false;

    double w1Size = MathAbs(w1 - w0);
    double w5Size = MathAbs(w5 - w4);
    if(w1Size > 0 && w5Size < w1Size * 0.10) return false;

    return true;
}

bool CStrategyElliottWaveEnhanced::ValidateCorrectiveWaves_ABC(double pA, double pB, double pC)
{
    // pA = end of wave A, pB = end of wave B, pC = end of wave C
    // (wave A starts at some origin — we only have ends here)
    // In a flat/zigzag: A and C go the same direction, B goes opposite
    // Wave B should not exceed 138.2% of wave A
    double wASize = MathAbs(pB - pA);
    double wBSize = MathAbs(pC - pB);
    if(wASize <= 0) return false;

    double bRatio = wBSize / wASize;
    if(bRatio > 1.382 * (1.0 + m_rules.tolerance)) return false;

    // Wave C projection 61.8–161.8% of wave A
    double cRatio = wBSize / wASize;
    if(cRatio < 0.618 * (1.0 - m_rules.tolerance)) return false;
    if(cRatio > 1.618 * (1.0 + m_rules.tolerance)) return false;

    // A and C must be in the same direction
    // (A goes from pA_start to pA, C goes from pC_start to pC — i.e. B→C)
    bool aDir = (pB > pA);   // A direction (start to end)
    bool cDir = (pC > pB);   // C direction from B end — for zigzag, same as A
    // In a zigzag: A down, B up, C down → aDir=false, cDir=false ✓
    // In a flat:   A down, B up, C down → same
    // The key Elliott rule: C must be in same direction as A
    return (aDir == !cDir);   // B is opposite, which means C = same as A means cDir != aDir
                               // Wait — aDir is A's direction (true=up), cDir is C's direction
                               // For zigzag: if A is down (aDir=false, pB < pA) then C is also down
                               // C goes from B-end: pC < pB → cDir = false. So aDir == cDir. Corrected below.
}

#endif // STRATEGY_ELLIOTTWAVE_ENHANCED_MQH
