//+------------------------------------------------------------------+
//| RegimeTypes.mqh                                                  |
//| Shared regime value types (enums, snapshot, tuning config)       |
//| Extracted verbatim from RegimeEngine.mqh (no behavior change)    |
//+------------------------------------------------------------------+
#ifndef REGIME_TYPES_MQH
#define REGIME_TYPES_MQH

enum ENUM_REGIME_STATE
{
    REGIME_TREND = 0,
    REGIME_RANGE = 1,
    REGIME_BREAKOUT = 2,
    REGIME_CHAOS = 3
};

// ENHANCEMENT: Multi-Dimensional Regime Classification (Batch 93 - Week 5)
enum ENUM_DETAILED_REGIME
{
    // Trend regimes
    DETAILED_REGIME_STRONG_UPTREND = 0,
    DETAILED_REGIME_WEAK_UPTREND = 1,
    DETAILED_REGIME_STRONG_DOWNTREND = 2,
    DETAILED_REGIME_WEAK_DOWNTREND = 3,

    // Range regimes
    DETAILED_REGIME_HIGH_VOL_RANGE = 4,
    DETAILED_REGIME_LOW_VOL_RANGE = 5,

    // Transition regimes
    DETAILED_REGIME_TRANSITION_UP = 6,
    DETAILED_REGIME_TRANSITION_DOWN = 7,

    // Extreme regimes
    DETAILED_REGIME_CHAOS = 8
};

struct SRegimeSnapshot
{
    bool valid;
    string readinessClass;
    bool reuseActive;
    int stalenessSeconds;
    ENUM_REGIME_STATE state;
    ENUM_REGIME_STATE confirmedState;
    double regimeConfidence;
    int regimeStabilityBars;
    bool compression;
    bool spreadShock;
    bool spreadShockCooldownActive;
    bool lateEntryOutlier;
    double atrValue;
    double bbWidth;
    double bbWidthAtrRatio;
    double spreadPrice;
    double spreadBaseline;
    double spreadToAtrRatio;
    double rangeZScore;
    datetime timestamp;

    // ENHANCEMENT: Detailed Regime Classification (Batch 93 - Week 5)
    ENUM_DETAILED_REGIME detailedRegime;
    double trendStrength;           // ADX value or similar metric
    double volatilityPercentile;    // Current vol vs historical (0-1)

    // ENHANCEMENT: Strategy-Specific Weight Multipliers (Batch 93 - Week 5)
    double momentumWeightMult;      // Momentum strategy multiplier
    double trendWeightMult;         // Trend strategy multiplier
    double meanRevWeightMult;       // Mean Reversion strategy multiplier
    double breakoutWeightMult;      // Volatility Breakout strategy multiplier
    double ictWeightMult;           // ICT strategy multiplier

    SRegimeSnapshot() :
        valid(false),
        readinessClass("WARMUP"),
        reuseActive(false),
        stalenessSeconds(0),
        state(REGIME_RANGE),
        confirmedState(REGIME_RANGE),
        regimeConfidence(0.0),
        regimeStabilityBars(0),
        compression(false),
        spreadShock(false),
        spreadShockCooldownActive(false),
        lateEntryOutlier(false),
        atrValue(0.0),
        bbWidth(0.0),
        bbWidthAtrRatio(0.0),
        spreadPrice(0.0),
        spreadBaseline(0.0),
        spreadToAtrRatio(0.0),
        rangeZScore(0.0),
        timestamp(0),
        detailedRegime(DETAILED_REGIME_LOW_VOL_RANGE),
        trendStrength(0.0),
        volatilityPercentile(0.0),
        momentumWeightMult(1.0),
        trendWeightMult(1.0),
        meanRevWeightMult(1.0),
        breakoutWeightMult(1.0),
        ictWeightMult(1.0)
    {
    }
};

//+------------------------------------------------------------------+
//| Tuning parameters previously held as loose CRegimeEngine fields. |
//| Defaults and clamping bounds are byte-identical to the original  |
//| constructor / Initialize() / ConfigureCostLimits() logic.        |
//+------------------------------------------------------------------+
struct SRegimeConfig
{
    int atrPeriod;
    int bbPeriod;
    double bbDeviation;
    int zScoreWindow;
    int spreadWindow;
    double spreadShockMultiplier;
    int spreadShockCooldownSeconds;
    double maxSpreadToAtrRatio;
    double lateEntryZScoreLimit;
    double compressionRatioThreshold;
    double breakoutZScoreThreshold;

    SRegimeConfig() :
        atrPeriod(14),
        bbPeriod(20),
        bbDeviation(2.0),
        zScoreWindow(30),
        spreadWindow(120),
        spreadShockMultiplier(2.5),
        spreadShockCooldownSeconds(30),
        maxSpreadToAtrRatio(0.25),
        lateEntryZScoreLimit(2.50),
        compressionRatioThreshold(3.0),
        breakoutZScoreThreshold(1.8)
    {
    }

    //--- Clamping previously inlined in CRegimeEngine::Initialize()
    void ApplyInitialize(const int atrPeriodIn,
                         const int bbPeriodIn,
                         const double bbDeviationIn,
                         const int zScoreWindowIn,
                         const int spreadWindowIn)
    {
        atrPeriod = MathMax(5, atrPeriodIn);
        bbPeriod = MathMax(10, bbPeriodIn);
        bbDeviation = MathMax(1.0, bbDeviationIn);
        zScoreWindow = MathMax(10, zScoreWindowIn);
        spreadWindow = MathMax(20, spreadWindowIn);
    }

    //--- Clamping previously inlined in CRegimeEngine::ConfigureCostLimits()
    void ApplyCostLimits(const double maxSpreadToAtrRatioIn,
                         const int spreadShockCooldownSecondsIn,
                         const double lateEntryZScoreLimitIn)
    {
        maxSpreadToAtrRatio = MathMax(0.01, maxSpreadToAtrRatioIn);
        spreadShockCooldownSeconds = MathMax(5, spreadShockCooldownSecondsIn);
        lateEntryZScoreLimit = MathMax(0.5, lateEntryZScoreLimitIn);
    }
};

#endif // REGIME_TYPES_MQH
