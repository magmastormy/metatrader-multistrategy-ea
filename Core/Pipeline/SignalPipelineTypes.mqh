// Signal Pipeline Types - shared structs/enums (extracted)
// Owns filter settings + evidence snapshot data model.
#ifndef SIGNAL_PIPELINE_TYPES_MQH
#define SIGNAL_PIPELINE_TYPES_MQH

#include "../Utils/Enums.mqh"
#include "../../Core/Registry/MathematicalEngineRegistry.mqh"

// Filter Preset Types
enum ENUM_FILTER_PRESET
{
    FILTER_PRESET_CONSERVATIVE,
    FILTER_PRESET_BALANCED,
    FILTER_PRESET_AGGRESSIVE,
    FILTER_PRESET_CUSTOM
};

struct SReadinessScoreConfig
{
    double healthyScore;
    double reusedSnapshotScore;
    double transientCopyFaultScore;
    double handleFaultScore;
    double warmupScore;
    double stalenessPenaltyMax;
    int stalenessPenaltyDivisor;
    
    SReadinessScoreConfig() :
        healthyScore(1.00),
        reusedSnapshotScore(0.88),
        transientCopyFaultScore(0.65),
        handleFaultScore(0.40),
        warmupScore(0.58),
        stalenessPenaltyMax(0.30),
        stalenessPenaltyDivisor(120) {} // 2 minutes
    
    bool Validate() const
    {
        if(healthyScore < 0.0 || healthyScore > 1.0)
            return false;
        if(reusedSnapshotScore < 0.0 || reusedSnapshotScore > 1.0)
            return false;
        if(transientCopyFaultScore < 0.0 || transientCopyFaultScore > 1.0)
            return false;
        if(handleFaultScore < 0.0 || handleFaultScore > 1.0)
            return false;
        if(warmupScore < 0.0 || warmupScore > 1.0)
            return false;
        if(stalenessPenaltyMax < 0.0 || stalenessPenaltyMax > 1.0)
            return false;
        if(stalenessPenaltyDivisor <= 0)
            return false;
        return true;
    }
};

// Signal Filter Settings - Grouped Nested Structs

struct STrendFilterSettings
{
    bool enabled;
    int minStrength;
    
    STrendFilterSettings() : enabled(true), minStrength(50) {}
    
    bool Validate() const
    {
        return minStrength >= 0 && minStrength <= 100;
    }
};

struct SVolatilityFilterSettings
{
    bool enabled;
    double maxVolatility;
    
    SVolatilityFilterSettings() : enabled(true), maxVolatility(3.0) {}
    
    bool Validate() const
    {
        return maxVolatility >= 0.0 && maxVolatility <= 10.0;
    }
};

struct SLiquidityFilterSettings
{
    bool enabled;
    
    SLiquidityFilterSettings() : enabled(true) {}
    
    bool Validate() const { return true; }
};

struct SStructureFilterSettings
{
    bool enabled;
    
    SStructureFilterSettings() : enabled(true) {}
    
    bool Validate() const { return true; }
};

// Session/Time Filter Settings
struct SSessionFilterSettings
{
    bool enableTimeFilter;
    bool enableSessionFilter;
    bool allowSyntheticOffHours;
    bool tradeLondonSession;
    bool tradeNewYorkSession;
    bool tradeTokyoSession;
    
    SSessionFilterSettings() : 
        enableTimeFilter(false),
        enableSessionFilter(false),
        allowSyntheticOffHours(true),
        tradeLondonSession(true),
        tradeNewYorkSession(true),
        tradeTokyoSession(true) {}
    
    bool Validate() const { return true; }
};

struct SRegimeCostGateSettings
{
    bool enabled;
    double maxSpreadToAtrRatio;
    int spreadShockCooldownSeconds;
    double maxEntryRangeZScore;
    
    SRegimeCostGateSettings() : 
        enabled(true),
        maxSpreadToAtrRatio(0.25),
        spreadShockCooldownSeconds(30),
        maxEntryRangeZScore(2.50) {}
    
    bool Validate() const
    {
        if(maxSpreadToAtrRatio < 0.0 || maxSpreadToAtrRatio > 10.0)
            return false;
        if(maxEntryRangeZScore < 0.0 || maxEntryRangeZScore > 10.0)
            return false;
        if(spreadShockCooldownSeconds < 0)
            return false;
        return true;
    }
};

struct SConfidenceSettings
{
    double minConfidence;
    double intrabarConfidenceCap;
    
    SConfidenceSettings() : minConfidence(0.35), intrabarConfidenceCap(0.05) {}
    
    bool Validate() const
    {
        if(minConfidence < 0.0 || minConfidence > 1.0)
            return false;
        if(intrabarConfidenceCap < 0.0 || intrabarConfidenceCap > 1.0)
            return false;
        return true;
    }
};

struct SFilterOrderSettings
{
    int filterOrder[7];
    int filterOrderCount;
    
    SFilterOrderSettings() : filterOrderCount(7)
    {
        // Default filter order: RegimeCostGate -> Trend -> Volatility -> Liquidity -> Structure -> Time -> Session
        filterOrder[0] = 0; // RegimeCostGate
        filterOrder[1] = 1; // Trend
        filterOrder[2] = 2; // Volatility
        filterOrder[3] = 3; // Liquidity
        filterOrder[4] = 4; // Structure
        filterOrder[5] = 5; // Time
        filterOrder[6] = 6; // Session
    }
    
    bool Validate() const
    {
        if(filterOrderCount < 1 || filterOrderCount > 7)
            return false;
        for(int i = 0; i < filterOrderCount; i++)
        {
            if(filterOrder[i] < 0 || filterOrder[i] > 6)
                return false;
        }
        return true;
    }
};

// Readiness Component Weights
struct SReadinessComponentWeights
{
    double trendWeight;
    double structureWeight;
    double liquidityWeight;
    double volatilityWeight;
    double regimeWeight;
    
    SReadinessComponentWeights() : 
        trendWeight(1.25),
        structureWeight(1.15),
        liquidityWeight(0.90),
        volatilityWeight(1.05),
        regimeWeight(1.10) {}
    
    bool Validate() const
    {
        double sum = trendWeight + structureWeight + liquidityWeight + volatilityWeight + regimeWeight;
        return sum > 0.0 && MathAbs(sum - 5.45) < 0.001; // Expected sum
    }
};

// Main Signal Filter Settings - Composed of grouped structs
struct SignalFilterSettings
{
    STrendFilterSettings trend;
    SVolatilityFilterSettings volatility;
    SLiquidityFilterSettings liquidity;
    SStructureFilterSettings structure;
    SSessionFilterSettings session;
    SRegimeCostGateSettings regimeCostGate;
    SConfidenceSettings confidence;
    SFilterOrderSettings filterOrder;
    SReadinessScoreConfig readinessConfig;
    SReadinessComponentWeights readinessWeights;
    
    SignalFilterSettings() {}
    
    // Validate all grouped settings
    bool Validate() const
    {
        return trend.Validate() &&
               volatility.Validate() &&
               liquidity.Validate() &&
               structure.Validate() &&
               session.Validate() &&
               regimeCostGate.Validate() &&
               confidence.Validate() &&
               filterOrder.Validate() &&
               readinessConfig.Validate() &&
               readinessWeights.Validate();
    }
    
    // Apply a preset configuration
    void ApplyPreset(ENUM_FILTER_PRESET preset)
    {
        switch(preset)
        {
            case FILTER_PRESET_CONSERVATIVE:
                trend.enabled = true; trend.minStrength = 60;
                volatility.enabled = true; volatility.maxVolatility = 2.0;
                liquidity.enabled = true;
                structure.enabled = true;
                session.enableTimeFilter = true; session.enableSessionFilter = true;
                regimeCostGate.enabled = true; regimeCostGate.maxSpreadToAtrRatio = 0.15; regimeCostGate.maxEntryRangeZScore = 2.0;
                confidence.minConfidence = 0.45; confidence.intrabarConfidenceCap = 0.03;
                break;
                
            case FILTER_PRESET_BALANCED:
                trend.enabled = true; trend.minStrength = 50;
                volatility.enabled = true; volatility.maxVolatility = 3.0;
                liquidity.enabled = true;
                structure.enabled = true;
                session.enableTimeFilter = false; session.enableSessionFilter = false;
                regimeCostGate.enabled = true; regimeCostGate.maxSpreadToAtrRatio = 0.25; regimeCostGate.maxEntryRangeZScore = 2.5;
                confidence.minConfidence = 0.40; confidence.intrabarConfidenceCap = 0.05;
                break;
                
            case FILTER_PRESET_AGGRESSIVE:
                trend.enabled = true; trend.minStrength = 35;
                volatility.enabled = true; volatility.maxVolatility = 4.5;
                liquidity.enabled = true;
                structure.enabled = true;
                session.enableTimeFilter = false; session.enableSessionFilter = false;
                regimeCostGate.enabled = true; regimeCostGate.maxSpreadToAtrRatio = 0.40; regimeCostGate.maxEntryRangeZScore = 3.0;
                confidence.minConfidence = 0.30; confidence.intrabarConfidenceCap = 0.08;
                break;
                
            case FILTER_PRESET_CUSTOM:
            default:
                // Keep current values
                break;
        }
        // Re-validate after preset
        Validate();
    }
};

struct SPipelineEvidenceSnapshot
{
    string symbol;
    ENUM_TIMEFRAMES timeframe;
    bool contextPrepared;
    bool trendReady;
    bool structureReady;
    bool liquidityReady;
    bool volatilityReady;
    bool regimeValid;
    ENUM_TREND_TYPE trend;
    double trendStrength;
    ENUM_VOLATILITY_STATE volatilityState;
    double atrValue;
    double atrPercent;
    double structureStrength;
    bool bullishStructure;
    bool bearishStructure;
    bool liquiditySweep;
    bool priceNearLiquidity;
    ENUM_REGIME_STATE regimeState;
    double spreadToAtrRatio;
    double rangeZScore;
    string readinessClass;
    bool reuseActive;
    int stalenessSeconds;
    double stalenessPenalty;
    double readinessScore;
    double contextScore;
    double costScore;
    double effectiveMinConfidence;
    bool softThresholdPass;
    string vetoReasonTag;

    SPipelineEvidenceSnapshot()
    {
        symbol = "";
        timeframe = PERIOD_CURRENT;
        contextPrepared = false;
        trendReady = false;
        structureReady = false;
        liquidityReady = false;
        volatilityReady = false;
        regimeValid = false;
        trend = TREND_NONE;
        trendStrength = 0.0;
        volatilityState = VOLATILITY_LOW;
        atrValue = 0.0;
        atrPercent = 0.0;
        structureStrength = 0.0;
        bullishStructure = false;
        bearishStructure = false;
        liquiditySweep = false;
        priceNearLiquidity = false;
        regimeState = REGIME_RANGE;
        spreadToAtrRatio = 0.0;
        rangeZScore = 0.0;
        readinessClass = "WARMUP";
        reuseActive = false;
        stalenessSeconds = 0;
        stalenessPenalty = 0.0;
        readinessScore = 0.5;
        contextScore = 0.5;
        costScore = 0.5;
        effectiveMinConfidence = 0.4;
        softThresholdPass = false;
        vetoReasonTag = "";
    }
};

#endif // SIGNAL_PIPELINE_TYPES_MQH

