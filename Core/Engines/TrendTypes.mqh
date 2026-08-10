//+------------------------------------------------------------------+
//| TrendTypes.mqh - Shared trend value types                        |
//| Extracted verbatim from TrendEngine.mqh (no behavior change)     |
//+------------------------------------------------------------------+
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef TREND_TYPES_MQH
#define TREND_TYPES_MQH

//+------------------------------------------------------------------+
//| Trend Types                                                     |
//+------------------------------------------------------------------+
enum ENUM_TREND_TYPE
{
    TREND_NONE = 0,
    TREND_BULLISH_STRONG,
    TREND_BULLISH_WEAK,
    TREND_BEARISH_STRONG,
    TREND_BEARISH_WEAK,
    TREND_RANGING,
    TREND_VOLATILE,
    TREND_TRANSITIONING
};

//+------------------------------------------------------------------+
//| Trend State Structure                                           |
//+------------------------------------------------------------------+
struct TrendState
{
    ENUM_TREND_TYPE type;
    double strength;            // 0-100 trend strength
    double angle;               // Trend angle in degrees
    double momentum;            // Momentum value
    double volatility;          // Current volatility
    bool isAccelerating;        // Trend acceleration
    bool isDecelerating;        // Trend deceleration
    datetime lastUpdate;
    
    TrendState() : type(TREND_NONE), strength(0), angle(0), momentum(0),
                  volatility(0), isAccelerating(false), isDecelerating(false),
                  lastUpdate(0) {}
};

enum ENUM_TREND_READINESS_STATE
{
    TREND_READINESS_WARMUP = 0,
    TREND_READINESS_TRANSIENT_COPY_FAULT = 1,
    TREND_READINESS_HANDLE_FAULT = 2,
    TREND_READINESS_REUSED_SNAPSHOT = 3,
    TREND_READINESS_HEALTHY = 4
};

struct STrendReadinessSnapshot
{
    ENUM_TREND_READINESS_STATE state;
    bool reuseActive;
    int stalenessSeconds;
    datetime lastGoodTime;
    string reasonTag;

    STrendReadinessSnapshot() :
        state(TREND_READINESS_WARMUP),
        reuseActive(false),
        stalenessSeconds(0),
        lastGoodTime(0),
        reasonTag("WARMUP")
    {
    }
};

//+------------------------------------------------------------------+
//| Multi-Timeframe Trend                                           |
//+------------------------------------------------------------------+
struct MTFTrendState
{
    TrendState htf;            // Higher timeframe trend
    TrendState mtf;            // Medium timeframe trend
    TrendState ltf;            // Lower timeframe trend
    double alignment;          // 0-100 alignment score
    bool isAligned;           // All timeframes aligned
    ENUM_TREND_TYPE consensus; // Consensus trend
};

#endif // TREND_TYPES_MQH
