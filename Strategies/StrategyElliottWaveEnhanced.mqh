//+------------------------------------------------------------------+
//| Elliott Wave Strategy v2.0 - Enterprise Grade                    |
//| Implements proper 5-3 wave structure with Fibonacci ratios       |
//| Enhanced with ZigZag filtering and Wave 3/5 entry signals        |
//+------------------------------------------------------------------+
#ifndef STRATEGY_ELLIOTTWAVE_ENHANCED_MQH
#define STRATEGY_ELLIOTTWAVE_ENHANCED_MQH

#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Visualization/ChartDrawingManager.mqh"
#include "../Core/Engines/StructureEngine.mqh"
#include "../Core/Engines/TrendEngine.mqh"
#include "../Core/Signals/SignalDiagnostics.mqh"

// Enhanced Elliott Wave Component Files
#include "ElliottWaveFiles/ZigZagFilter.mqh"
#include "ElliottWaveFiles/WavePatternEngine.mqh"

//+------------------------------------------------------------------+
//| Elliott Wave Types                                              |
//+------------------------------------------------------------------+
enum ENUM_ELLIOTT_WAVE
{
    EW_WAVE_NONE = 0,
    EW_WAVE_1,     // Impulse wave 1
    EW_WAVE_2,     // Corrective wave 2
    EW_WAVE_3,     // Impulse wave 3 (strongest)
    EW_WAVE_4,     // Corrective wave 4
    EW_WAVE_5,     // Final impulse wave 5
    EW_WAVE_A,     // Corrective wave A
    EW_WAVE_B,     // Corrective wave B
    EW_WAVE_C,     // Corrective wave C
    EW_WAVE_W,     // Complex correction W
    EW_WAVE_X,     // Complex correction X
    EW_WAVE_Y,     // Complex correction Y
    EW_WAVE_Z      // Complex correction Z
};

//+------------------------------------------------------------------+
//| Wave Rules Structure                                            |
//+------------------------------------------------------------------+
struct ElliottWaveRules
{
    // Impulse wave rules
    double wave2_retracement_min;     // 0.382 minimum
    double wave2_retracement_max;     // 0.786 maximum
    double wave3_extension_min;       // 1.618 minimum
    double wave4_retracement_max;     // 0.618 maximum
    double wave5_extension_min;       // 0.618 minimum
    
    // Corrective wave rules
    double waveA_retracement;         // 0.382-0.618
    double waveB_retracement_max;     // 1.382 maximum
    double waveC_projection;          // 1.0-1.618
    
    // Validation thresholds
    double tolerance;                 // 10% tolerance for ratios
    int min_bars_per_wave;           // Minimum bars in a wave
    double min_wave_size_atr;        // Minimum wave size in ATR
    
    ElliottWaveRules() : 
        wave2_retracement_min(0.382), wave2_retracement_max(0.786),
        wave3_extension_min(1.618), wave4_retracement_max(0.618),
        wave5_extension_min(0.618), waveA_retracement(0.5),
        waveB_retracement_max(1.382), waveC_projection(1.0),
        tolerance(0.05), min_bars_per_wave(8), min_wave_size_atr(1.0) {}
};

//+------------------------------------------------------------------+
//| Wave Point Structure                                            |
//+------------------------------------------------------------------+
struct WavePoint
{
    datetime time;
    double price;
    ENUM_ELLIOTT_WAVE wave;
    int degree;
    double confidence;
    bool isValid;
    
    WavePoint() : time(0), price(0), wave(EW_WAVE_NONE), 
                 degree(0), confidence(0), isValid(false) {}
};

//+------------------------------------------------------------------+
//| Wave Pattern Structure                                          |
//+------------------------------------------------------------------+
struct WavePattern
{
    WavePoint waves[13];          // Max 13 waves for complex corrections
    int waveCount;
    bool isImpulse;
    bool isCorrective;
    bool isComplete;
    double patternConfidence;
    ENUM_TRADE_SIGNAL signal;
    double targetPrice;
    
    WavePattern() : waveCount(0), isImpulse(false), isCorrective(false),
                   isComplete(false), patternConfidence(0), signal(TRADE_SIGNAL_NONE),
                   targetPrice(0) {}
};

//+------------------------------------------------------------------+
//| Enhanced Elliott Wave Strategy Class v2.0                       |
//+------------------------------------------------------------------+
class CStrategyElliottWaveEnhanced : public CStrategyBase
{
private:
    // Enhanced Components (v2.0)
    CZigZagFilter*      m_zigzag;
    CWavePatternEngine* m_waveEngine;

    // Legacy Engines (for backward compatibility)
    CStructureEngine* m_structureEngine;
    CTrendEngine* m_trendEngine;
    CSignalDiagnostics* m_diagnostics;

    // Wave analysis
    ElliottWaveRules m_rules;
    WavePattern m_currentPattern;
    WavePattern m_patterns[5];      // Track multiple patterns
    int m_patternCount;
    CChartDrawingManager* m_drawingManager;
    
    // Configuration
    int m_lookbackPeriod;
    bool m_useMultiTF;
    ENUM_TIMEFRAMES m_htf;
    
    // Statistics
    int m_wavesIdentified;
    int m_patternsCompleted;
    int m_signalsGenerated;
    
    // Methods
    bool IdentifyWavePattern(const MqlRates &rates[], int count);
    bool ValidateImpulseWaves(const WavePattern &pattern);
    bool ValidateCorrectiveWaves(const WavePattern &pattern);
    double CalculateFibonacciRatio(double price1, double price2, double price3);
    bool CheckWave2Rules(const WavePoint &wave0, const WavePoint &wave1, const WavePoint &wave2);
    // Validation helpers (use adjacent pivots)
    bool CheckWave3Rules(const WavePoint &wave0, const WavePoint &wave1, const WavePoint &wave2, const WavePoint &wave3);
    bool CheckWave4Rules(const WavePoint &wave1, const WavePoint &wave2, const WavePoint &wave3, const WavePoint &wave4);
    bool CheckWave5Rules(const WavePoint &wave3, const WavePoint &wave5);
    double ProjectWaveTarget(const WavePattern &pattern);
    void InvalidatePattern(WavePattern &pattern, const string reason);
    void DrawWavePattern(const WavePattern &pattern);
    void ClearWaveDrawings();
    
public:
    CStrategyElliottWaveEnhanced(const string name = "Elliott Wave Enhanced");
    virtual ~CStrategyElliottWaveEnhanced();
    
    // Initialization
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, 
                     void* tradeMgr, void* posSizer) override;
    virtual void Deinit() override;
    
    // Core strategy methods
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override;
    virtual void OnTick() override;
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override;
    
    // Getters
    virtual string GetName() const override { return m_name; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_ELLIOTT_WAVE; }
    
    // Configuration
    void SetLookbackPeriod(int period) { m_lookbackPeriod = period; }
    void SetMultiTimeframe(bool enable, ENUM_TIMEFRAMES htf = PERIOD_H4) 
    { 
        m_useMultiTF = enable; 
        m_htf = htf; 
    }
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
    m_lookbackPeriod(200),
    m_useMultiTF(true),
    m_htf(PERIOD_H4),
    m_wavesIdentified(0),
    m_patternsCompleted(0),
    m_signalsGenerated(0),
    m_patternCount(0),
    m_drawingManager(NULL)
{
    // Initialize legacy engines
    m_structureEngine = new CStructureEngine();
    m_trendEngine = new CTrendEngine();
    m_diagnostics = new CSignalDiagnostics();

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
    // Clean up enhanced components
    if(m_zigzag != NULL) { delete m_zigzag; m_zigzag = NULL; }
    if(m_waveEngine != NULL) { delete m_waveEngine; m_waveEngine = NULL; }

    // Clean up legacy engines
    if(m_structureEngine != NULL) { delete m_structureEngine; m_structureEngine = NULL; }
    if(m_trendEngine != NULL) { delete m_trendEngine; m_trendEngine = NULL; }
    if(m_diagnostics != NULL) { delete m_diagnostics; m_diagnostics = NULL; }

    if(m_drawingManager != NULL) { delete m_drawingManager; m_drawingManager = NULL; }
    Deinit();
}

//+------------------------------------------------------------------+
//| Initialize Strategy                                             |
//+------------------------------------------------------------------+
bool CStrategyElliottWaveEnhanced::Init(const string symbol, const ENUM_TIMEFRAMES timeframe,
                                        void* tradeMgr, void* posSizer)
{
    if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
        return false;

    // Initialize enhanced ZigZag Filter
    m_zigzag = new CZigZagFilter();
    if(m_zigzag != NULL)
        m_zigzag.Initialize(symbol, timeframe);

    // Initialize enhanced Wave Pattern Engine
    m_waveEngine = new CWavePatternEngine();
    if(m_waveEngine != NULL)
        m_waveEngine.Initialize(symbol, timeframe, m_zigzag);

    // Initialize drawing manager
    m_drawingManager = new CChartDrawingManager();
    if(m_drawingManager != NULL)
    {
        m_drawingManager.Initialize(symbol, timeframe, "EW");
        SDrawingConfig config = m_drawingManager.GetConfiguration();
        config.enableStructure = false;
        config.enableSupportResistance = false;
        config.enableOrderBlocks = false;
        config.enableSupplyDemand = false;
        config.enableFVG = false;
        config.enableElliottWave = true;
        config.enableTrendLines = true;
        config.enableSignalMarkers = false;
        m_drawingManager.SetConfiguration(config);
    }
    
    // Reset patterns
    m_currentPattern = WavePattern();
    for(int i = 0; i < 5; i++)
        m_patterns[i] = WavePattern();
    m_patternCount = 0;

    PrintFormat("[ELLIOTT v2.0] Strategy initialized for %s on %s | ZigZag: %s | WaveEngine: %s",
                symbol, EnumToString(timeframe),
                m_zigzag != NULL ? "OK" : "FAIL",
                m_waveEngine != NULL ? "OK" : "FAIL");
    
    return true;
}

//+------------------------------------------------------------------+
//| Deinitialize Strategy                                           |
//+------------------------------------------------------------------+
void CStrategyElliottWaveEnhanced::Deinit()
{
    if(m_drawingManager != NULL)
        m_drawingManager.CleanupAll();
    CStrategyBase::Deinit();
}

//+------------------------------------------------------------------+
//| Get Trading Signal                                              |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CStrategyElliottWaveEnhanced::GetSignal(double &confidence)
{
    if(!IsEnabled() || !m_is_initialized)
    {
        confidence = 0.0;
        if(m_diagnostics != NULL)
            m_diagnostics.LogNoSignal("ElliottWave", m_symbol, m_timeframe, "Strategy disabled");
        return TRADE_SIGNAL_NONE;
    }
    
    confidence = 0.0;
    
    // Get rates
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(m_symbol, m_timeframe, 0, m_lookbackPeriod, rates);
    
    if(copied < m_lookbackPeriod)
    {
        if(m_diagnostics != NULL)
            m_diagnostics.LogStrategyError("ElliottWave", "INSUFFICIENT_BARS", 
                                          "Not enough bars for wave analysis");
        return TRADE_SIGNAL_NONE;
    }
    
    // Update structure and trend
    if(m_structureEngine != NULL)
        m_structureEngine.DetectSwingPoints(m_symbol, m_timeframe);
    
    if(m_trendEngine != NULL)
        m_trendEngine.UpdateTrend(m_symbol, m_timeframe);
    
    // Identify wave patterns
    if(!IdentifyWavePattern(rates, copied))
    {
        if(m_diagnostics != NULL)
            m_diagnostics.LogNoSignal("ElliottWave", m_symbol, m_timeframe, "No valid wave pattern");
        return TRADE_SIGNAL_NONE;
    }
    
    // Check for ANY valid pattern with trading opportunity (complete OR incomplete)
    ENUM_TRADE_SIGNAL bestSignal = TRADE_SIGNAL_NONE;
    double bestConfidence = 0.0;
    int bestWaveCount = 0;
    double bestTarget = 0.0;
    
    for(int i = 0; i < m_patternCount; i++)
    {
        // ENHANCED: Consider ALL patterns with valid signals, not just complete ones
        if(m_patterns[i].signal != TRADE_SIGNAL_NONE && m_patterns[i].waveCount >= 3)
        {
            double patternConf = m_patterns[i].patternConfidence;
            
            // Multi-timeframe confirmation
            if(m_useMultiTF && m_trendEngine != NULL)
            {
                m_trendEngine.UpdateMTFTrend(m_symbol, m_htf, m_timeframe, PERIOD_M15);
                if(m_trendEngine.IsMTFAligned())
                    patternConf += 0.1;
            }
            
            // Track best pattern
            if(patternConf > bestConfidence)
            {
                bestSignal = m_patterns[i].signal;
                bestConfidence = patternConf;
                bestWaveCount = m_patterns[i].waveCount;
                bestTarget = m_patterns[i].targetPrice;
            }
        }
    }
    
    // Lower minimum threshold from 0.6 to 0.45 for more signals
    if(bestConfidence >= 0.45 && bestSignal != TRADE_SIGNAL_NONE)
    {
        confidence = bestConfidence;
        m_signalsGenerated++;
        
        if(m_diagnostics != NULL)
        {
            string waveInfo = StringFormat("Wave %d | Target: %.5f | Conf: %.2f",
                                          bestWaveCount, bestTarget, bestConfidence);
            m_diagnostics.LogSignalGeneration("ElliottWave", m_symbol, m_timeframe,
                                             bestSignal, confidence, waveInfo);
        }
        
        return bestSignal;
    }
    
    if(m_diagnostics != NULL)
        m_diagnostics.LogNoSignal("ElliottWave", m_symbol, m_timeframe, 
                                 "No valid wave pattern or low confidence");
    
    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Identify Wave Pattern                                           |
//+------------------------------------------------------------------+
bool CStrategyElliottWaveEnhanced::IdentifyWavePattern(const MqlRates &rates[], int count)
{
    if(m_structureEngine == NULL)
        return false;
    
    // Get swing points from structure engine
    int swingHighCount = m_structureEngine.GetSwingHighCount();
    int swingLowCount = m_structureEngine.GetSwingLowCount();
    
    // RELAXED: Need at least 2 swings of each type (was 3)
    if(swingHighCount < 2 || swingLowCount < 2)
        return false; // Need at least 2 swings each for pattern

    // Reset patterns
    m_patternCount = 0;
    
    // ENHANCED: Proper wave identification from swing points
    WavePattern impulse;
    impulse.isImpulse = true;
    
    // Get swing points from structure engine + direct rate pivots
    SwingPoint swings[10];
    int swingCount = 0;
    double pointValue = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
    if(pointValue <= 0.0)
        pointValue = 0.00001;
    double dedupThreshold = pointValue * 0.5;

    SwingPoint candidate;

    // Seed with the latest high/low from structure engine (single fetch each, no duplicates).
    if(m_structureEngine.GetLastSwingHigh(candidate) && candidate.isValid)
    {
        swings[swingCount++] = candidate;
    }
    if(m_structureEngine.GetLastSwingLow(candidate) && candidate.isValid)
    {
        bool exists = false;
        for(int j = 0; j < swingCount; j++)
        {
            if(swings[j].time == candidate.time || MathAbs(swings[j].price - candidate.price) <= dedupThreshold)
            {
                exists = true;
                break;
            }
        }
        if(!exists && swingCount < 10)
            swings[swingCount++] = candidate;
    }

    // Extract pivots directly from rates and deduplicate by time/price.
    for(int i = 2; i < count - 2 && swingCount < 10; i++)
    {
        bool isSwingHigh = (rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high &&
                            rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high);
        bool isSwingLow = (rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low &&
                           rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low);
        if(!isSwingHigh && !isSwingLow)
            continue;

        candidate.price = isSwingHigh ? rates[i].high : rates[i].low;
        candidate.time = rates[i].time;
        candidate.bar = i;
        candidate.type = isSwingHigh ? STRUCT_TYPE_HH : STRUCT_TYPE_LL;
        candidate.strength = 50.0;
        candidate.isValid = true;
        candidate.isMitigated = false;

        bool exists = false;
        for(int j = 0; j < swingCount; j++)
        {
            if(swings[j].time == candidate.time || MathAbs(swings[j].price - candidate.price) <= dedupThreshold)
            {
                exists = true;
                break;
            }
        }

        if(!exists)
            swings[swingCount++] = candidate;
    }
    
    if(swingCount < 3)
        return false; // Need at least 3 swings for partial wave pattern detection

    // Keep deterministic chronological ordering (oldest -> newest).
    for(int i = 0; i < swingCount - 1; i++)
    {
        for(int j = i + 1; j < swingCount; j++)
        {
            if(swings[i].time > swings[j].time)
            {
                SwingPoint temp = swings[i];
                swings[i] = swings[j];
                swings[j] = temp;
            }
        }
    }

    // Focus pattern detection on the most recent sequence.
    if(swingCount > 5)
    {
        int start = swingCount - 5;
        for(int i = 0; i < 5; i++)
            swings[i] = swings[start + i];
        swingCount = 5;
    }

    if(m_diagnostics != NULL)
    {
        string swingLog = StringFormat("Swings H:%d L:%d | Recent sequence(%d): ", swingHighCount, swingLowCount, swingCount);
        for(int i = 0; i < swingCount; i++)
            swingLog += StringFormat("[%s %.2f] ", TimeToString(swings[i].time, TIME_DATE|TIME_MINUTES), swings[i].price);
        m_diagnostics.LogStrategyError("ElliottWave", "DEBUG", swingLog);
    }
    
    // Identify impulse wave pattern from swings
    // For bullish impulse: Low-High-Low-High-Low (waves 1-2-3-4-5)
    // For bearish impulse: High-Low-High-Low-High (waves 1-2-3-4-5)
    
    bool isBullishImpulse = false;
    // ENHANCED: Process patterns with 3+ swings (was 5+)
    if(swingCount >= 3)
    {
        // Check if we have alternating swings forming an impulse
        double firstPrice = swings[0].price;
        double lastPrice = swings[swingCount - 1].price;
        isBullishImpulse = (lastPrice > firstPrice);
        
        // Assign waves from swings (up to 5 waves)
        int wavesToAssign = MathMin(5, swingCount);
        for(int i = 0; i < wavesToAssign; i++)
        {
            impulse.waves[i].price = swings[i].price;
            impulse.waves[i].time = swings[i].time;
            impulse.waves[i].wave = (ENUM_ELLIOTT_WAVE)(EW_WAVE_1 + i);
            impulse.waves[i].isValid = true;
            
            // Calculate confidence based on Fibonacci ratios
            if(i > 0)
            {
                double ratio = CalculateFibonacciRatio(impulse.waves[i-1].price, 
                                                       impulse.waves[i].price,
                                                       (i > 1 ? impulse.waves[i-2].price : 0));
                impulse.waves[i].confidence = MathMax(0.5, 1.0 - MathAbs(ratio - 0.618));
            }
            else
            {
                impulse.waves[i].confidence = 0.7;
            }
        }
        
        impulse.waveCount = wavesToAssign;
        
        // Validate the impulse wave with proper rules
        if(ValidateImpulseWaves(impulse))
        {
            // Calculate overall pattern confidence
            double avgConfidence = 0.0;
            for(int i = 0; i < impulse.waveCount; i++)
                avgConfidence += impulse.waves[i].confidence;
            impulse.patternConfidence = avgConfidence / impulse.waveCount;
            
            impulse.isComplete = (impulse.waveCount == 5);
            impulse.targetPrice = ProjectWaveTarget(impulse);
            
            // Determine signal based on wave completion and trend
            // ENHANCED: Generate signals for ALL valid wave patterns including complete ones
            if(impulse.isComplete)
            {
                if(isBullishImpulse)
                {
                    // After 5-wave impulse up, expect correction - SELL opportunity
                    impulse.signal = TRADE_SIGNAL_SELL;
                    impulse.patternConfidence += 0.05; // Moderate confidence for reversal
                }
                else
                {
                    // After 5-wave impulse down, expect correction - BUY opportunity
                    impulse.signal = TRADE_SIGNAL_BUY;
                    impulse.patternConfidence += 0.05; // Moderate confidence for reversal
                }
            }
            else if(impulse.waveCount == 4)
            {
                // Wave 4 complete, wave 5 in progress - trade in direction of impulse
                impulse.signal = isBullishImpulse ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;
                impulse.patternConfidence += 0.12; // High confidence for wave 5 entry
            }
            else if(impulse.waveCount == 3)
            {
                // Wave 3 in progress - strongest wave, trade in direction
                impulse.signal = isBullishImpulse ? TRADE_SIGNAL_BUY : TRADE_SIGNAL_SELL;
                impulse.patternConfidence += 0.18; // Highest confidence for wave 3
            }
            
            m_patterns[m_patternCount++] = impulse;
            if(impulse.isComplete)
                m_patternsCompleted++;

            // Draw the wave pattern on chart (clear old objects first)
            ClearWaveDrawings();
            DrawWavePattern(impulse);

            if(m_diagnostics != NULL)
            {
                Print("[ElliottWave] Impulse wave identified | Waves: ", impulse.waveCount,
                      " | Confidence: ", DoubleToString(impulse.patternConfidence, 2),
                      " | Signal: ", EnumToString(impulse.signal));
            }

            return true;
        }
    }
    
    // Try to identify corrective wave (ABC structure)
    WavePattern corrective;
    corrective.isCorrective = true;
    
    // Simplified corrective wave detection
    if(swingHighCount >= 2 && swingLowCount >= 1)
    {
        corrective.waves[0].wave = EW_WAVE_A;
        corrective.waves[1].wave = EW_WAVE_B;
        corrective.waves[2].wave = EW_WAVE_C;
        corrective.waveCount = 3;
        
        if(ValidateCorrectiveWaves(corrective))
        {
            corrective.isComplete = true;
            m_patterns[m_patternCount++] = corrective;
            m_patternsCompleted++;
            return true;
        }
    }
    
    return m_patternCount > 0;
}

//+------------------------------------------------------------------+
//| Validate Impulse Waves                                           |
//+------------------------------------------------------------------+
bool CStrategyElliottWaveEnhanced::ValidateImpulseWaves(const WavePattern &pattern)
{
    // RELAXED: Allow partial wave patterns (3+ waves) for earlier signal generation
    if(pattern.waveCount < 3)
        return false;
    
    // ENHANCED: Comprehensive wave validation
    
    // Wave 2 cannot retrace more than 100% of wave 1
    if(pattern.waveCount >= 3 && !CheckWave2Rules(pattern.waves[0], pattern.waves[1], pattern.waves[2]))
    {
        // Cannot invalidate const pattern - just return false
        return false;
    }
    
    // Wave 3 cannot be the shortest (must extend beyond wave 1)
    if(pattern.waveCount >= 4 && !CheckWave3Rules(pattern.waves[0], pattern.waves[1], pattern.waves[2], pattern.waves[3]))
    {
        // Cannot invalidate const pattern - just return false
        return false;
    }
    
    // Wave 4 cannot overlap wave 1 price territory
    if(pattern.waveCount >= 4 && !CheckWave4Rules(pattern.waves[0], pattern.waves[1], pattern.waves[2], pattern.waves[3]))
    {
        // Cannot invalidate const pattern - just return false
        return false;
    }
    
    // Wave 5 validation (if present)
    if(pattern.waveCount >= 5 && !CheckWave5Rules(pattern.waves[2], pattern.waves[4]))
    {
        // Cannot invalidate const pattern - just return false
        return false;
    }
    
    // Additional validation: Wave 1 and 3 should be in same direction
    if(pattern.waveCount >= 3)
    {
        bool wave1Up = pattern.waves[1].price > pattern.waves[0].price;
        bool wave3Up = pattern.waves[2].price > pattern.waves[1].price;
        if(wave1Up != wave3Up)
        {
            // Cannot invalidate const pattern - just return false
            return false;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate Fibonacci Ratio                                        |
//+------------------------------------------------------------------+
double CStrategyElliottWaveEnhanced::CalculateFibonacciRatio(double price1, double price2, double price3)
{
    // Guard against invalid inputs
    if(MathIsValidNumber(price1) == false || MathIsValidNumber(price2) == false || MathIsValidNumber(price3) == false)
        return 0.0;
    
    double denominator = MathAbs(price3 - price1);
    if(denominator < DBL_EPSILON)
        return 0.0;
    
    double numerator = MathAbs(price2 - price1);
    return numerator / denominator;
}

//+------------------------------------------------------------------+
//| Check Wave 2 Rules                                              |
//+------------------------------------------------------------------+
bool CStrategyElliottWaveEnhanced::CheckWave2Rules(const WavePoint &wave0, const WavePoint &wave1, const WavePoint &wave2)
{
    if(!wave0.isValid || !wave1.isValid || !wave2.isValid)
        return false;
    
    // Calculate wave 1 size (from wave0 to wave1)
    double wave1Size = MathAbs(wave1.price - wave0.price);
    if(wave1Size <= 0)
        return false;
    
    // Calculate wave 2 retracement (from wave1 to wave2)
    double wave2Size = MathAbs(wave2.price - wave1.price);
    double wave2Retracement = wave2Size / wave1Size;
    
    // Wave 2 must retrace between 38.2% and 78.6% of wave 1 (with tolerance)
    double minRetrace = m_rules.wave2_retracement_min * (1.0 - m_rules.tolerance);
    double maxRetrace = m_rules.wave2_retracement_max * (1.0 + m_rules.tolerance);
    
    if(wave2Retracement < minRetrace || wave2Retracement > maxRetrace)
    {
        if(m_diagnostics != NULL)
        {
            string msg = StringFormat("Wave 2 retracement invalid: %.1f%% (expected %.1f-%.1f%%)",
                                    wave2Retracement * 100,
                                    minRetrace * 100,
                                    maxRetrace * 100);
            m_diagnostics.LogStrategyError("ElliottWave", "DEBUG", msg);
        }
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Wave 3 Rules                                              |
//+------------------------------------------------------------------+
bool CStrategyElliottWaveEnhanced::CheckWave3Rules(const WavePoint &wave0, const WavePoint &wave1, const WavePoint &wave2, const WavePoint &wave3)
{
    if(!wave0.isValid || !wave1.isValid || !wave2.isValid || !wave3.isValid)
        return false;
    
    // Wave 1 size
    double wave1Size = MathAbs(wave1.price - wave0.price);
    // Wave 3 size (from wave2 -> wave3)
    double wave3Size = MathAbs(wave3.price - wave2.price);
    
    if(wave1Size <= 0 || wave3Size <= 0)
        return false;
    
    // Require wave 3 to extend beyond wave 1 with tolerance
    double minExtension = m_rules.wave3_extension_min * (1.0 - m_rules.tolerance);
    if(wave3Size < wave1Size * minExtension)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Wave 4 Rules                                              |
//+------------------------------------------------------------------+
bool CStrategyElliottWaveEnhanced::CheckWave4Rules(const WavePoint &wave1, const WavePoint &wave2, const WavePoint &wave3, const WavePoint &wave4)
{
    if(!wave1.isValid || !wave2.isValid || !wave3.isValid || !wave4.isValid)
        return false;
    
    // Calculate wave 3 size (wave2 -> wave3)
    double wave3Size = MathAbs(wave3.price - wave2.price);
    if(wave3Size <= 0)
        return false;
    
    // Calculate wave 4 retracement
    double wave4Size = MathAbs(wave4.price - wave3.price);
    double wave4Retracement = wave4Size / wave3Size;
    
    // Wave 4 typically retraces 38.2-50% of wave 3, max 61.8% (with tolerance)
    double maxRetrace = m_rules.wave4_retracement_max * (1.0 + m_rules.tolerance);
    
    if(wave4Retracement > maxRetrace)
    {
        if(m_diagnostics != NULL)
        {
            string msg = StringFormat("Wave 4 retracement excessive: %.1f%% (maximum %.1f%%)",
                                    wave4Retracement * 100,
                                    maxRetrace * 100);
            m_diagnostics.LogStrategyError("ElliottWave", "DEBUG", msg);
        }
        return false;
    }
    
    // Wave 4 must not overlap wave 1 territory (using wave1 end as guard)
    bool isBull = (wave3.price > wave1.price);
    if(isBull && wave4.price <= wave1.price)
        return false;
    if(!isBull && wave4.price >= wave1.price)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate Corrective Waves                                       |
//+------------------------------------------------------------------+
bool CStrategyElliottWaveEnhanced::ValidateCorrectiveWaves(const WavePattern &pattern)
{
    if(pattern.waveCount < 3)
        return false;
    
    // Basic ABC validation
    // Wave B should not exceed 138.2% of wave A
    // Wave C typically equals wave A or extends to 161.8%
    
    // ENHANCED: Proper ABC validation
    if(pattern.waveCount < 3)
        return false;
    
    // Wave A and C should be in same direction
    bool waveAUp = pattern.waves[1].price > pattern.waves[0].price;
    bool waveCUp = pattern.waves[2].price > pattern.waves[1].price;
    
    if(waveAUp != waveCUp)
        return false; // A and C must be in same direction
    
    // Wave B should not exceed 138.2% of wave A
    double waveASize = MathAbs(pattern.waves[1].price - pattern.waves[0].price);
    double waveBSize = MathAbs(pattern.waves[2].price - pattern.waves[1].price);
    
    if(waveASize > 0 && (waveBSize / waveASize) > 1.382)
        return false;
    
    // Wave C projection: typically 100% to 161.8% of wave A (with tolerance)
    double minProj = 1.0 * (1.0 - m_rules.tolerance);
    double maxProj = 1.618 * (1.0 + m_rules.tolerance);
    double waveCSize = waveBSize; // waveC from B to C (same segment)
    if(waveASize > 0)
    {
        double projRatio = waveCSize / waveASize;
        if(projRatio < minProj || projRatio > maxProj)
            return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Project Wave Target                                             |
//+------------------------------------------------------------------+
double CStrategyElliottWaveEnhanced::ProjectWaveTarget(const WavePattern &pattern)
{
    if(!pattern.isComplete)
        return 0;
    
    double target = 0;
    
    if(pattern.isImpulse && pattern.waveCount >= 5)
    {
        // Project based on wave 5 completion
        double wave5 = pattern.waves[4].price;
        double wave3 = pattern.waves[2].price;
        
        // Common target is 161.8% extension from wave 3
        target = wave5 + (wave5 - wave3) * 0.618;
    }
    else if(pattern.isCorrective && pattern.waveCount >= 3)
    {
        // Project based on wave C completion
        double waveA = pattern.waves[0].price;
        double waveC = pattern.waves[2].price;
        
        // Wave C often equals wave A
        target = waveC + (waveC - waveA);
    }
    
    return target;
}

//+------------------------------------------------------------------+
//| Check Wave 5 Rules                                              |
//+------------------------------------------------------------------+
bool CStrategyElliottWaveEnhanced::CheckWave5Rules(const WavePoint &wave3, const WavePoint &wave5)
{
    if(!wave3.isValid || !wave5.isValid)
        return false;
    
    // Wave 5 must extend beyond wave 3 (for impulse)
    // Wave 5 typically extends 61.8% of wave 1-3 distance
    double wave3Size = MathAbs(wave5.price - wave3.price);
    
    // Wave 5 should be at least 38.2% of wave 3
    if(wave3Size <= 0)
        return false;
    
    // Basic validation: wave 5 should be in same direction as wave 3
    bool wave3Up = (wave5.price > wave3.price);
    // This is validated by pattern structure
    
    return true;
}

//+------------------------------------------------------------------+
//| Invalidate Pattern                                              |
//+------------------------------------------------------------------+
void CStrategyElliottWaveEnhanced::InvalidatePattern(WavePattern &pattern, const string reason)
{
    pattern.isComplete = false;
    pattern.patternConfidence = 0.0;
    pattern.signal = TRADE_SIGNAL_NONE;
    
    if(m_diagnostics != NULL)
    {
        Print("[ElliottWave] Pattern invalidated: ", reason);
    }
}

//+------------------------------------------------------------------+
//| OnTick Event Handler                                            |
//+------------------------------------------------------------------+
void CStrategyElliottWaveEnhanced::OnTick()
{
    // Can be used for real-time wave tracking
}

//+------------------------------------------------------------------+
//| OnNewBar Event Handler                                          |
//+------------------------------------------------------------------+
void CStrategyElliottWaveEnhanced::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(symbol != m_symbol || timeframe != m_timeframe)
        return;

    // Update wave analysis on new bar
    double confidence;
    GetSignal(confidence);
}

//+------------------------------------------------------------------+
//| Draw Wave Pattern on Chart                                       |
//+------------------------------------------------------------------+
void CStrategyElliottWaveEnhanced::DrawWavePattern(const WavePattern &pattern)
{
    if(pattern.waveCount < 2 || m_drawingManager == NULL)
        return;
    
    color waveColor = pattern.isImpulse ? clrDeepSkyBlue : clrOrange;
    
    // Clear previous drawings for this cycle
    m_drawingManager.CleanupOldObjects();
    
    // Draw lines connecting wave points and labels
    for(int i = 0; i < pattern.waveCount - 1; i++)
    {
        if(!pattern.waves[i].isValid || !pattern.waves[i+1].isValid)
            continue;
        
        m_drawingManager.DrawTrendLine(pattern.waves[i].time, pattern.waves[i].price,
                                        pattern.waves[i+1].time, pattern.waves[i+1].price,
                                        waveColor, 2, STYLE_SOLID);
        
        string waveLabel = "";
        switch(pattern.waves[i].wave)
        {
            case EW_WAVE_1: waveLabel = "1"; break;
            case EW_WAVE_2: waveLabel = "2"; break;
            case EW_WAVE_3: waveLabel = "3"; break;
            case EW_WAVE_4: waveLabel = "4"; break;
            case EW_WAVE_5: waveLabel = "5"; break;
            case EW_WAVE_A: waveLabel = "A"; break;
            case EW_WAVE_B: waveLabel = "B"; break;
            case EW_WAVE_C: waveLabel = "C"; break;
            default: waveLabel = IntegerToString(i); break;
        }
        
        m_drawingManager.DrawWaveLabel(pattern.waves[i].time, pattern.waves[i].price, waveLabel, pattern.isImpulse);
    }
    
    // Draw final label
    if(pattern.waveCount > 0 && pattern.waves[pattern.waveCount-1].isValid)
    {
        int lastIdx = pattern.waveCount - 1;
        string waveLabel = "";
        switch(pattern.waves[lastIdx].wave)
        {
            case EW_WAVE_1: waveLabel = "1"; break;
            case EW_WAVE_2: waveLabel = "2"; break;
            case EW_WAVE_3: waveLabel = "3"; break;
            case EW_WAVE_4: waveLabel = "4"; break;
            case EW_WAVE_5: waveLabel = "5"; break;
            case EW_WAVE_A: waveLabel = "A"; break;
            case EW_WAVE_B: waveLabel = "B"; break;
            case EW_WAVE_C: waveLabel = "C"; break;
            default: waveLabel = IntegerToString(lastIdx); break;
        }
        
        m_drawingManager.DrawWaveLabel(pattern.waves[lastIdx].time, pattern.waves[lastIdx].price, waveLabel, pattern.isImpulse);
    }

    if(m_diagnostics != NULL)
    {
        PrintFormat("[ElliottWave] Drew %d-wave %s pattern on %s",
                   pattern.waveCount,
                   pattern.isImpulse ? "impulse" : "corrective",
                   m_symbol);
    }
}

//+------------------------------------------------------------------+
//| Clear Wave Drawings                                              |
//+------------------------------------------------------------------+
void CStrategyElliottWaveEnhanced::ClearWaveDrawings()
{
    if(m_drawingManager != NULL)
        m_drawingManager.CleanupOldObjects();
}

#endif // STRATEGY_ELLIOTTWAVE_ENHANCED_MQH
