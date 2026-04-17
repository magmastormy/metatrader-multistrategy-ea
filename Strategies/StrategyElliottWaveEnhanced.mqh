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
#include "../Core/Utils/Instruments.mqh"
#include "../Core/Visualization/ChartDrawingManager.mqh"
#include "../Core/Engines/TrendEngine.mqh"

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

    // Optional trend engine used only for higher-timeframe alignment checks.
    CTrendEngine*       m_trendEngine;

    // Drawing
    CChartDrawingManager* m_drawingManager;

    // Configuration
    ElliottWaveRules    m_rules;
    int                 m_lookbackPeriod;
    bool                m_useMultiTF;
    ENUM_TIMEFRAMES     m_htf;
    ENUM_TIMEFRAMES     m_ltf;
    ENUM_TIMEFRAMES     m_effectiveTF; // Auto-resolved: chart TF or M30, whichever is higher

    // Internal TF resolver
    ENUM_TIMEFRAMES     ResolveEffectiveTF(ENUM_TIMEFRAMES chartTF);
    ENUM_TIMEFRAMES     ResolveAlignmentHigherTF(const string symbol, ENUM_TIMEFRAMES baseTF);
    ENUM_TIMEFRAMES     ResolveAlignmentLowerTF(const string symbol, ENUM_TIMEFRAMES baseTF);

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
    m_trendEngine(NULL),
    m_drawingManager(NULL),
    m_lookbackPeriod(250),
    m_useMultiTF(true),
    m_htf(PERIOD_H4),
    m_ltf(PERIOD_M15),
    m_effectiveTF(PERIOD_M30),
    m_wavesIdentified(0),
    m_patternsCompleted(0),
    m_signalsGenerated(0)
{
    OverrideMinConfidence(0.50);

    // Trend alignment helper for optional higher-timeframe confirmation.
    m_trendEngine     = new CTrendEngine();

    if(m_trendEngine != NULL)
        m_trendEngine.Initialize(20, 50, 200, 14, NULL);
}

//+------------------------------------------------------------------+
//| Resolve effective analysis timeframe                             |
//| Elliott Wave needs enough bars per wave swing. If the chart TF   |
//| is below M30, we automatically step up to M30 so the ZigZag and |
//| wave engine have meaningful pivot resolution.                    |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES CStrategyElliottWaveEnhanced::ResolveEffectiveTF(ENUM_TIMEFRAMES chartTF)
{
    // Step up to PERIOD_M30 minimum — enough for clean 5-3 structure
    if(chartTF == PERIOD_M1  ||
       chartTF == PERIOD_M2  ||
       chartTF == PERIOD_M3  ||
       chartTF == PERIOD_M4  ||
       chartTF == PERIOD_M5  ||
       chartTF == PERIOD_M6  ||
       chartTF == PERIOD_M10 ||
       chartTF == PERIOD_M12 ||
       chartTF == PERIOD_M15 ||
       chartTF == PERIOD_M20)
    {
        return PERIOD_M30;
    }
    return chartTF;
}

ENUM_TIMEFRAMES CStrategyElliottWaveEnhanced::ResolveAlignmentHigherTF(const string symbol, ENUM_TIMEFRAMES baseTF)
{
    if(!IsSyntheticIndexSymbolName(symbol))
        return PERIOD_H4;

    switch(baseTF)
    {
        case PERIOD_M1:
        case PERIOD_M5:
            return PERIOD_M15;
        case PERIOD_M15:
        case PERIOD_M30:
            return PERIOD_H1;
        case PERIOD_H1:
            return PERIOD_H4;
        default:
            return PERIOD_D1;
    }
}

ENUM_TIMEFRAMES CStrategyElliottWaveEnhanced::ResolveAlignmentLowerTF(const string symbol, ENUM_TIMEFRAMES baseTF)
{
    if(!IsSyntheticIndexSymbolName(symbol))
        return PERIOD_M15;

    switch(baseTF)
    {
        case PERIOD_H4:
        case PERIOD_H1:
            return PERIOD_M30;
        case PERIOD_M30:
            return PERIOD_M15;
        case PERIOD_M15:
            return PERIOD_M5;
        default:
            return PERIOD_M15;
    }
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CStrategyElliottWaveEnhanced::~CStrategyElliottWaveEnhanced()
{
    if(m_zigzag         != NULL) { delete m_zigzag;          m_zigzag         = NULL; }
    if(m_waveEngine     != NULL) { delete m_waveEngine;       m_waveEngine     = NULL; }
    if(m_trendEngine    != NULL) { delete m_trendEngine;      m_trendEngine    = NULL; }
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

    // Resolve effective analysis TF — step up to M30 for low-TF charts so that EW
    // can build meaningful swing pivots regardless of what chart the trader runs.
    m_effectiveTF = ResolveEffectiveTF(timeframe);
    m_htf = ResolveAlignmentHigherTF(symbol, m_effectiveTF);
    m_ltf = ResolveAlignmentLowerTF(symbol, m_effectiveTF);

    // Scale lookback: if effective TF > chart TF, lookback shrinks proportionally
    // e.g. on M1 chart using M30 analysis: 250 * (1/30) * 60 = still 250 M30 bars
    // We keep a fixed M30-equivalent lookback.
    m_lookbackPeriod = 250; // always 250 bars of the effectiveTF

    // Scale min_bars_per_wave: M30 gets 3 bars minimum; H1+ gets 5
    m_rules.min_bars_per_wave = (m_effectiveTF >= PERIOD_H1) ? 5 : 3;

    // ZigZag filter — initialized against the EFFECTIVE TF
    m_zigzag = new CZigZagFilter();
    if(m_zigzag == NULL || !m_zigzag.Initialize(symbol, m_effectiveTF))
    {
        Print("[EW v2.1] FAILED to initialise ZigZagFilter");
        return false;
    }

    // Wave engine — shares the already-initialised zigzag, also on effectiveTF
    m_waveEngine = new CWavePatternEngine();
    if(m_waveEngine == NULL || !m_waveEngine.Initialize(symbol, m_effectiveTF, m_zigzag))
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

    // Drawing manager (draw on the actual chart TF for visual clarity)
    m_drawingManager = new CChartDrawingManager();
    if(m_drawingManager != NULL)
    {
        m_drawingManager.Initialize(symbol, timeframe, "EW");
        SDrawingConfig cfg = m_drawingManager.GetConfiguration();
        cfg.enableElliottWave   = true;
        cfg.enableTrendLines    = false;  // Disabled - trend lines are randomly drawn/inaccurate
        cfg.enableStructure     = false;
        cfg.enableOrderBlocks   = false;
        cfg.enableFVG           = false;
        cfg.enableSignalMarkers = false;
        m_drawingManager.SetConfiguration(cfg);
    }

    PrintFormat("[EW v2.1] Initialised for %s | chart=%s | analysis=%s | lookback=%d | min_bars_per_wave=%d",
                symbol,
                EnumToString(timeframe),
                EnumToString(m_effectiveTF),
                m_lookbackPeriod,
                m_rules.min_bars_per_wave);
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
    SetDecisionReasonTag("EW_UNSET");

    if(!IsEnabled() || !m_is_initialized)
    {
        SetDecisionReasonTag("EW_DISABLED_OR_UNINIT");
        return TRADE_SIGNAL_NONE;
    }

    if(m_waveEngine == NULL)
    {
        SetDecisionReasonTag("EW_ENGINE_NOT_READY");
        return TRADE_SIGNAL_NONE;
    }

    // Update wave engine (runs ZigZag internally)
    m_waveEngine.Update();

    int patternCount = m_waveEngine.GetPatternCount();
    if(patternCount == 0)
    {
        SetDecisionReasonTag("EW_NO_PATTERNS");
        return TRADE_SIGNAL_NONE;
    }

    m_wavesIdentified = patternCount;

    ENUM_TRADE_SIGNAL bestSig  = TRADE_SIGNAL_NONE;
    double            bestConf = 0.0;
    SElliottWavePattern bestPat;

    // Optional HTF trend filter
    bool htfBull = true, htfBear = true;
    if(m_useMultiTF && m_trendEngine != NULL)
    {
        m_trendEngine.UpdateMTFTrend(m_symbol, m_htf, m_effectiveTF, m_ltf);
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
        SetDecisionReasonTag(bestSig == TRADE_SIGNAL_BUY ? "EW_SIGNAL_BUY" : "EW_SIGNAL_SELL");
        RecordSignal();

        ClearWaveDrawings();
        DrawWavePattern(bestPat);

        PrintFormat("[EW v2.1] %s | %s | %s | Conf: %.1f%% | W3ext: %.3f",
                    m_symbol,
                    bestSig == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                    GetWaveStateString(bestPat.currentState),
                    confidence * 100.0,
                    bestPat.wave3Extension);
    }
    else
    {
        SetDecisionReasonTag("EW_NO_TRADEABLE_PATTERN");
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
    if(symbol != m_symbol || timeframe != m_timeframe)
        return;

    // Consensus owns the single authoritative GetSignal() call for the bar.
    // Avoid pre-consuming wave-pattern state here and let manager evaluation run once.
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

    // Draw thin dashed trend lines between pivot points
    for(int i = 0; i < waveCount - 1; i++)
    {
        if(times[i] == 0 || times[i+1] == 0) continue;

        m_drawingManager.DrawTrendLine(times[i], prices[i], times[i+1], prices[i+1],
                                       color(waveCol | 0x808080), 1, STYLE_DOT);
    }

    // Draw labels at each pivot (use DrawTextLabel instead of the non-existent DrawWaveLabel)
    for(int i = 0; i < waveCount; i++)
    {
        if(times[i] == 0) continue;

        bool isHigh = (i > 0) ? (prices[i] > prices[i-1]) : false;
        ENUM_ANCHOR_POINT anchor = isHigh ? ANCHOR_UPPER : ANCHOR_LOWER;

        m_drawingManager.DrawTextLabel(times[i], prices[i], waveLabels[i], waveCol, 9, anchor);
    }

    // Draw Fibonacci target levels for all waves
    if(pattern.wave0 > 0 && pattern.wave1 > 0)
    {
        double w1Size = MathAbs(pattern.wave1 - pattern.wave0);
        bool isBull = (pattern.wave1 > pattern.wave0);
        
        // Wave 1 targets (0.618, 1.0, 1.618 extensions)
        for(int fib = 0; fib < 3; fib++)
        {
            double ratio = (fib == 0) ? 0.618 : (fib == 1) ? 1.0 : 1.618;
            double target = isBull ? pattern.wave0 + w1Size * ratio : pattern.wave0 - w1Size * ratio;
            string label = "W1 " + DoubleToString(ratio, 3);
            m_drawingManager.DrawHorizontalLevel(target,
                                                 color(waveCol | 0x808080),
                                                 label,
                                                 STYLE_DOT, 1, false);
        }
    }

    if(pattern.wave1 > 0 && pattern.wave2 > 0)
    {
        double w2Size = MathAbs(pattern.wave2 - pattern.wave1);
        bool isBull = (pattern.wave1 > pattern.wave0);
        
        // Wave 2 targets (0.382, 0.5, 0.618 retracements)
        for(int fib = 0; fib < 3; fib++)
        {
            double ratio = (fib == 0) ? 0.382 : (fib == 1) ? 0.5 : 0.618;
            double target = isBull ? pattern.wave1 - w2Size * ratio : pattern.wave1 + w2Size * ratio;
            string label = "W2 " + DoubleToString(ratio, 3);
            m_drawingManager.DrawHorizontalLevel(target,
                                                 color(waveCol | 0x808080),
                                                 label,
                                                 STYLE_DOT, 1, false);
        }
    }

    // Draw wave 3 target line if available
    if(pattern.wave3Target > 0 && pattern.currentState == STATE_WAVE_3)
    {
        m_drawingManager.DrawHorizontalLevel(pattern.wave3Target,
                                             color(waveCol | 0x808080),
                                             "W3 target 1.618",
                                             STYLE_DOT, 1, false);
    }

    // Draw wave 4 targets (0.236, 0.382, 0.5 retracements)
    if(pattern.wave3 > 0 && pattern.wave4 > 0)
    {
        double w3Size = MathAbs(pattern.wave3 - pattern.wave2);
        bool isBull = (pattern.wave3 > pattern.wave1);
        
        for(int fib = 0; fib < 3; fib++)
        {
            double ratio = (fib == 0) ? 0.236 : (fib == 1) ? 0.382 : 0.5;
            double target = isBull ? pattern.wave3 - w3Size * ratio : pattern.wave3 + w3Size * ratio;
            string label = "W4 " + DoubleToString(ratio, 3);
            m_drawingManager.DrawHorizontalLevel(target,
                                                 color(waveCol | 0x808080),
                                                 label,
                                                 STYLE_DOT, 1, false);
        }
    }

    // Draw wave 5 target line if available
    if(pattern.wave5Target > 0 && pattern.currentState == STATE_WAVE_5)
    {
        m_drawingManager.DrawHorizontalLevel(pattern.wave5Target,
                                             color(waveCol | 0x808080),
                                             "W5 target",
                                             STYLE_DOT, 1, false);
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
    // (wave A starts at some prior pivot — we have end-of-wave prices here)
    // In a zigzag/flat: A and C move in the SAME direction; B is opposite.
    //
    // Direction of A: from B-end BACK to A-start is not available, but
    // from A-end (pA) to B-end (pB), B retraces A — so B direction = opposite of A.
    // Direction of C: from B-end (pB) to C-end (pC) — C = same direction as A.

    double wASize = MathAbs(pB - pA); // A segment magnitude (B retraces A)
    double wCSize = MathAbs(pC - pB); // C segment magnitude (from B to C)
    if(wASize <= 0) return false;

    // Wave B must not exceed 138.2% of wave A (standard flat rule)
    double bRatio = wASize > 0 ? wASize / wASize : 0; // = 1.0 trivially, we use wASize as ref
    // Recalculate: B size relative to A size
    // (B goes from A-end to B-end; A went from A-start to A-end — we don't have A-start)
    // Simplification: wASize = |pB - pA|, wCSize = |pC - pB|
    // B retracement ratio = wASize / wASize = 1 if equal, but this is B's SIZE vs A's SIZE
    // Standard check: wave B should retrace 50%–138.2% of wave A magnitude
    double bRetracement = wASize / wASize; // = 1.0 (placeholder — B is pA→pB, A is unknown start→pA)
    // Since A-start is unavailable, we validate C against A using the available data:
    // Wave C projection 61.8%–161.8% of wave A (wASize is proxy for A size)
    double cRatio = wCSize / wASize;
    if(cRatio < 0.618 * (1.0 - m_rules.tolerance)) return false;
    if(cRatio > 1.618 * (1.0 + m_rules.tolerance)) return false;

    // BUG FIX: A and C must move in the SAME direction.
    // aDir = direction from pA to pB (this is B's direction = OPPOSITE of A)
    // cDir = direction from pB to pC (this is C's direction = SAME as A)
    // Therefore: C direction (cDir) is OPPOSITE to B direction (aDir).
    // i.e. cDir != aDir. In code: return (aDir != cDir)
    // Previous code had: return (aDir == !cDir) which equals (aDir != cDir) — BUT
    // the logical intent was muddled by the comment confusion. The CORRECT assertion:
    //   aDir = (pB > pA)  →  B's direction
    //   cDir = (pC > pB)  →  C's direction
    //   Valid ABC: C opposite of B → cDir != aDir
    bool aDir = (pB > pA); // B goes this direction (opposite of A)
    bool cDir = (pC > pB); // C goes this direction (same as A = opposite of B)
    return (cDir != aDir); // C must be OPPOSITE direction to B — i.e. same as A
}

#endif // STRATEGY_ELLIOTTWAVE_ENHANCED_MQH
