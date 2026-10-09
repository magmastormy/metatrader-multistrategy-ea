// Signal Pipeline Filter - trend/vol/liq/structure/time/session
// + regime-cost gate + spread filter (extracted, stateless).
#ifndef SIGNAL_PIPELINE_FILTER_MQH
#define SIGNAL_PIPELINE_FILTER_MQH

#include "../Utils/Enums.mqh"
#include "../../Core/Registry/MathematicalEngineRegistry.mqh"
#include "SignalPipelineTypes.mqh"
#include "SignalPipelineNormalizer.mqh"

class CSignalPipelineFilter
{
public:
static void LogResult(string &m_lastFilterName, string &m_lastFilterReason, const string filter, bool passed, const string reason)
{
    if(passed)
        return;

    if(StringLen(m_lastFilterName) > 0)
        m_lastFilterName += "+";
    m_lastFilterName += filter;

    if(StringLen(reason) > 0)
    {
        if(StringLen(m_lastFilterReason) > 0)
            m_lastFilterReason += "; ";
        m_lastFilterReason += reason;
    }

    // Note: Generic per-filter logs are intentionally suppressed here.
    // Note: Authoritative runtime telemetry is emitted by the manager, validator, and regime/cost gates.
}

static bool ApplyRegimeAndCostGate(CMathematicalEngineRegistry* m_mathRegistry, const SignalFilterSettings &m_filters, SPipelineEvidenceSnapshot &m_lastEvidence, bool &m_lastRegimeSnapshotValid, ENUM_REGIME_STATE &m_lastRegimeState, int &m_regimeGateLogCounter, const int m_regimeGateLogInterval, const string symbol, ENUM_TIMEFRAMES timeframe, ENUM_TRADE_SIGNAL &signal, double &confidence, string &vetoReasonTag)
{
    vetoReasonTag = "";
    m_lastRegimeSnapshotValid = false;
    m_lastEvidence.costScore = 0.72;
    m_lastEvidence.regimeValid = false;
    CRegimeEngine* regimeEngine = m_mathRegistry ? m_mathRegistry.GetRegime(symbol) : NULL;
    if(regimeEngine == NULL)
        return true;

    if(!regimeEngine.Update(symbol, timeframe))
    {
        // Neutral degrade when regime engine data is warming/faulted.
        confidence = MathMax(0.0, confidence * 0.98);
        return true;
    }

    SRegimeSnapshot snapshot = regimeEngine.GetSnapshot();
    if(!snapshot.valid)
        return true;

    m_lastRegimeSnapshotValid = true;
        m_lastRegimeState = snapshot.state;
        m_lastEvidence.regimeValid = true;
        m_lastEvidence.regimeState = snapshot.state;
        m_lastEvidence.spreadToAtrRatio = snapshot.spreadToAtrRatio;
        m_lastEvidence.rangeZScore = snapshot.rangeZScore;
        if(snapshot.readinessClass != "")
            m_lastEvidence.readinessClass = snapshot.readinessClass;
        m_lastEvidence.reuseActive = (m_lastEvidence.reuseActive || snapshot.reuseActive);
        m_lastEvidence.stalenessSeconds = MathMax(m_lastEvidence.stalenessSeconds, snapshot.stalenessSeconds);
        m_lastEvidence.stalenessPenalty = MathMax(m_lastEvidence.stalenessPenalty,
                                                  MathMin(m_filters.readinessConfig.stalenessPenaltyMax, (double)snapshot.stalenessSeconds / (double)MathMax(10, m_filters.readinessConfig.stalenessPenaltyDivisor) * m_filters.readinessConfig.stalenessPenaltyMax));

        string regimeTag = regimeEngine.GetStateTag();
    
        // L4-013 Fix: Regime gate log throttling
        m_regimeGateLogCounter++;
        if(m_regimeGateLogCounter >= m_regimeGateLogInterval)
        {
            m_regimeGateLogCounter = 0;
            LOG_IF9(LOG_LEVEL_DEBUG, "[COST-GATE] %s | regime=%s | spread_atr=%.6f/%.6f | spread=%.5f | atr=%.5f | cooldown=%s | z=%.3f/%.3f",
                        symbol,
                        regimeTag,
                        snapshot.spreadToAtrRatio,
                        m_filters.regimeCostGate.maxSpreadToAtrRatio,
                        snapshot.spreadPrice,
                        snapshot.atrValue,
                        snapshot.spreadShockCooldownActive ? "true" : "false",
                        snapshot.rangeZScore,
                        m_filters.regimeCostGate.maxEntryRangeZScore);
        }

    // Regime-aware confidence attenuation while preserving deterministic output.
    // REDUCED PENALTIES: was 0.97 RANGE, 0.92 CHAOS - now much lighter to avoid blocking marginal signals
    if(snapshot.state == REGIME_RANGE)
        confidence = MathMax(0.0, confidence * 0.99);  // Minimal penalty for ranging
    else if(snapshot.state == REGIME_CHAOS)
        confidence = MathMax(0.0, confidence * 0.97);  // Reduced from 0.92 for chaos

    double spreadPenalty = 0.0;
    if(m_filters.regimeCostGate.maxSpreadToAtrRatio > 0.0)
        spreadPenalty = MathMin(0.30, (snapshot.spreadToAtrRatio / m_filters.regimeCostGate.maxSpreadToAtrRatio) * 0.15);
    double zPenalty = 0.0;
    if(m_filters.regimeCostGate.maxEntryRangeZScore > 0.0)
        zPenalty = MathMin(0.20, (MathAbs(snapshot.rangeZScore) / m_filters.regimeCostGate.maxEntryRangeZScore) * 0.10);
    double regimeBaseScore = 0.85;
    if(snapshot.state == REGIME_TREND || snapshot.state == REGIME_BREAKOUT)
        regimeBaseScore = 1.0;
    else if(snapshot.state == REGIME_RANGE)
        regimeBaseScore = 0.84;
    else if(snapshot.state == REGIME_CHAOS)
        regimeBaseScore = 0.62;
    if(snapshot.reuseActive)
        regimeBaseScore = MathMin(regimeBaseScore, 0.82);
    m_lastEvidence.costScore = MathMax(0.10, MathMin(1.0, regimeBaseScore - spreadPenalty - zPenalty));

    if(snapshot.spreadShockCooldownActive)
        {
            vetoReasonTag = StringFormat("REGIME_%s | spread shock cooldown active", regimeTag);
            m_lastEvidence.vetoReasonTag = vetoReasonTag;
            LOG_IF2(LOG_LEVEL_WARN, "[ENTRY-VETO] %s | reason=%s", symbol, vetoReasonTag);
            signal = TRADE_SIGNAL_NONE;
            confidence = 0.0;
            return false;
        }

    if(snapshot.spreadToAtrRatio > m_filters.regimeCostGate.maxSpreadToAtrRatio)
        {
            vetoReasonTag = StringFormat("REGIME_%s | spread/ATR ratio %.4f exceeds %.4f",
                                         regimeTag, snapshot.spreadToAtrRatio, m_filters.regimeCostGate.maxSpreadToAtrRatio);
            m_lastEvidence.vetoReasonTag = vetoReasonTag;
            LOG_IF2(LOG_LEVEL_WARN, "[ENTRY-VETO] %s | reason=%s", symbol, vetoReasonTag);
            signal = TRADE_SIGNAL_NONE;
            confidence = 0.0;
            return false;
        }

    if(MathAbs(snapshot.rangeZScore) > m_filters.regimeCostGate.maxEntryRangeZScore)
        {
            vetoReasonTag = StringFormat("REGIME_%s | late-entry z-score %.3f exceeds %.3f",
                                         regimeTag, snapshot.rangeZScore, m_filters.regimeCostGate.maxEntryRangeZScore);
            m_lastEvidence.vetoReasonTag = vetoReasonTag;
            LOG_IF2(LOG_LEVEL_WARN, "[ENTRY-VETO] %s | reason=%s", symbol, vetoReasonTag);
            signal = TRADE_SIGNAL_NONE;
            confidence = 0.0;
            return false;
        }

    return true;
}

static bool ApplyTrendFilter(CMathematicalEngineRegistry* m_mathRegistry, const string m_lastEvaluatedSymbol, string &m_lastFilterName, string &m_lastFilterReason, ENUM_TRADE_SIGNAL &signal, double &confidence)
{
    CTrendEngine* trendEngine = m_mathRegistry ? m_mathRegistry.GetTrend(m_lastEvaluatedSymbol) : NULL;
    if(trendEngine == NULL)
        return true;
    
    ENUM_TREND_TYPE trend = trendEngine.GetCurrentTrend();
    double trendStrength = trendEngine.GetTrendStrength();
    
    // Only bypass trend alignment in neutral/ranging regimes for truly exceptional confidence.
    if(confidence > 0.82 && (trend == TREND_RANGING || trend == TREND_NONE))
    {
        LogResult(m_lastFilterName, m_lastFilterReason, "TrendFilter", true, 
                       StringFormat("BYPASSED - High confidence in neutral trend (%.2f) | Trend: %s", 
                                  confidence, EnumToString(trend)));
        return true;
    }
    
    // ✨ FIX: Allow ranging markets - check if trend is actively AGAINST the signal
    // Only reject if there's a STRONG opposing trend
    bool strongOpposingTrend = false;
    
    if(signal == TRADE_SIGNAL_BUY && trendEngine.IsTrendBearish() && trendStrength > 75)
        strongOpposingTrend = true;
    else if(signal == TRADE_SIGNAL_SELL && trendEngine.IsTrendBullish() && trendStrength > 75)
        strongOpposingTrend = true;
    
    if(strongOpposingTrend)
    {
        if(trendStrength >= 90.0) // Increased from 85.0
        {
            LogResult(m_lastFilterName, m_lastFilterReason, "TrendFilter", false, 
                           StringFormat("Hard opposing trend veto: %s (%.1f)", 
                                      EnumToString(trend), trendStrength));
            return false;
        }

        confidence *= 0.85; // Relaxed from 0.72
        confidence = MathMin(1.0, MathMax(0.0, confidence));
        LogResult(m_lastFilterName, m_lastFilterReason, "TrendFilter", true,
                       StringFormat("Opposing trend attenuated: %s (%.1f)", EnumToString(trend), trendStrength));
        return true;
    }
    
    // ✨ FIX: ALLOW signals in ranging markets (TREND_RANGING, TREND_NONE)
    // These are valid trading opportunities
    if(trend == TREND_RANGING || trend == TREND_NONE)
    {
        LogResult(m_lastFilterName, m_lastFilterReason, "TrendFilter", true, 
                       StringFormat("PASSED - Ranging market | Strength: %.1f", trendStrength));
        return true;
    }
    
    // Check signal alignment with trend (only for trending markets)
    bool aligned = false;
    if(signal == TRADE_SIGNAL_BUY && trendEngine.IsTrendBullish())
        aligned = true;
    else if(signal == TRADE_SIGNAL_SELL && trendEngine.IsTrendBearish())
        aligned = true;
    
    if(!aligned)
    {
        if(trendStrength < 60)
        {
            confidence *= 0.93;
            LogResult(m_lastFilterName, m_lastFilterReason, "TrendFilter", true, 
                           StringFormat("Weak trend misalignment (%.1f) - ALLOWING signal", trendStrength));
            return true;
        }

        confidence *= 0.80;
        confidence = MathMin(1.0, MathMax(0.0, confidence));
        LogResult(m_lastFilterName, m_lastFilterReason, "TrendFilter", true, 
                       StringFormat("Managed trend misalignment: %s (%.1f) | confidence attenuated", 
                                  EnumToString(trend), trendStrength));
        return true;
    }
    
    // Boost confidence for strong aligned trends
    if(trendEngine.IsStrongTrend())
        confidence *= 1.10;
    
    // Cap confidence to valid range [0.0, 1.0]
    confidence = MathMin(1.0, MathMax(0.0, confidence));
    
    LogResult(m_lastFilterName, m_lastFilterReason, "TrendFilter", true, 
                   StringFormat("Trend: %s, Strength: %.1f", 
                              EnumToString(trend), trendStrength));
    
    return true;
}

static bool ApplyVolatilityFilter(CMathematicalEngineRegistry* m_mathRegistry, const string m_lastEvaluatedSymbol, const SignalFilterSettings &m_filters, string &m_lastFilterName, string &m_lastFilterReason, ENUM_TRADE_SIGNAL &signal, double &confidence)
{
    CVolatilityEngine* volatilityEngine = m_mathRegistry ? m_mathRegistry.GetVolatility(m_lastEvaluatedSymbol) : NULL;
    if(volatilityEngine == NULL)
        return true;
    
    ENUM_VOLATILITY_STATE volState = volatilityEngine.GetVolatilityState();
    double atrPercent = volatilityEngine.GetATRPercent();
    
    double hardVolatilityLimit = m_filters.volatility.maxVolatility * 1.35;
    if(atrPercent > hardVolatilityLimit)
    {
        LogResult(m_lastFilterName, m_lastFilterReason, "VolatilityFilter", false,
                       StringFormat("Volatility %.2f%% exceeds hard limit %.2f%%",
                                    atrPercent, hardVolatilityLimit));
        return false;
    }
    else if(atrPercent > m_filters.volatility.maxVolatility)
    {
        confidence *= 0.82;
        confidence = MathMin(1.0, MathMax(0.0, confidence));
        LogResult(m_lastFilterName, m_lastFilterReason, "VolatilityFilter", true,
                       StringFormat("Volatility %.2f%% above soft maximum %.2f%% | confidence attenuated",
                                    atrPercent, m_filters.volatility.maxVolatility));
        return true;
    }
    
    // Adjust confidence based on volatility
    if(volState == VOLATILITY_LOW)
        confidence *= 1.1;
    else if(volState == VOLATILITY_HIGH)
        confidence *= 0.9;
    else if(volState == VOLATILITY_EXTREME)
        confidence *= 0.7;
    
    // Cap confidence to valid range [0.0, 1.0]
    confidence = MathMin(1.0, MathMax(0.0, confidence));
    
    LogResult(m_lastFilterName, m_lastFilterReason, "VolatilityFilter", true, 
                   StringFormat("Volatility: %s (%.2f%%)", 
                              EnumToString(volState), atrPercent));
    
    return true;
}

static bool ApplyLiquidityFilter(CMathematicalEngineRegistry* m_mathRegistry, string &m_lastFilterName, string &m_lastFilterReason, ENUM_TRADE_SIGNAL &signal, double &confidence, const string symbol)
{
    CLiquidityEngine* liquidityEngine = m_mathRegistry ? m_mathRegistry.GetLiquidity(symbol) : NULL;
    if(liquidityEngine == NULL)
        return true;
    
    // Check for recent liquidity sweep
    if(liquidityEngine.HasLiquiditySweep(5))
    {
        confidence *= 1.15; // Boost confidence after liquidity grab
        LogResult(m_lastFilterName, m_lastFilterReason, "LiquidityFilter", true, "Recent liquidity sweep detected");
    }
    
    // Check if price is near liquidity
    string liquiditySymbol = (symbol != "") ? symbol : _Symbol;
    double localCurrentPrice = SymbolInfoDouble(liquiditySymbol, SYMBOL_BID);
    if(liquidityEngine.IsPriceNearLiquidity(localCurrentPrice, 30))
    {
        confidence *= 0.95; // Slightly reduce confidence near untested liquidity
        LogResult(m_lastFilterName, m_lastFilterReason, "LiquidityFilter", true, "Price near liquidity zone");
    }
    
    // Cap confidence to valid range [0.0, 1.0]
    confidence = MathMin(1.0, MathMax(0.0, confidence));
    
    return true;
}

static bool ApplyStructureFilter(CMathematicalEngineRegistry* m_mathRegistry, const string m_lastEvaluatedSymbol, string &m_lastFilterName, string &m_lastFilterReason, ENUM_TRADE_SIGNAL &signal, double &confidence)
{
    CStructureEngine* structureEngine = m_mathRegistry ? m_mathRegistry.GetStructure(m_lastEvaluatedSymbol) : NULL;
    if(structureEngine == NULL)
        return true;
    
    bool structureAligned = false;
    
    // Check for BOS/CHOCH alignment
    if(signal == TRADE_SIGNAL_BUY)
    {
        if(structureEngine.HasBullishBOS(5) || structureEngine.HasBullishCHOCH(5))
        {
            structureAligned = true;
            confidence *= 1.2;
        }
    }
    else if(signal == TRADE_SIGNAL_SELL)
    {
        if(structureEngine.HasBearishBOS(5) || structureEngine.HasBearishCHOCH(5))
        {
            structureAligned = true;
            confidence *= 1.2;
        }
    }
    
    if(!structureAligned)
    {
        // Still allow signal but with reduced confidence
        confidence *= 0.85;
        LogResult(m_lastFilterName, m_lastFilterReason, "StructureFilter", true, "No recent structure break");
    }
    else
    {
        LogResult(m_lastFilterName, m_lastFilterReason, "StructureFilter", true, "Structure break confirmed");
    }
    
    // Cap confidence to valid range [0.0, 1.0]
    confidence = MathMin(1.0, MathMax(0.0, confidence));
    
    return true;
}

static bool ApplyTimeFilter(const SignalFilterSettings &m_filters, string &m_lastFilterName, string &m_lastFilterReason, ENUM_TRADE_SIGNAL &signal, const string symbol)
{
    // Synthetic indices trade 24/7 - bypass ALL time restrictions including weekends
    if(CSignalPipelineNormalizer::IsSyntheticSymbol(symbol))
    {
        LogResult(m_lastFilterName, m_lastFilterReason, "TimeFilter", true, "Synthetic index - 24/7 trading enabled");
        return true;
    }
    
    // If synthetic indices and off-hours allowed, bypass time filter
    if(m_filters.session.allowSyntheticOffHours && CSignalPipelineNormalizer::IsSyntheticSymbol(symbol))
        return true;
    
    MqlDateTime dt;
    TimeToStruct(TimeGMT(), dt);
    int currentHour = dt.hour;
    
    // Check trading hours (0 AM - 10 PM GMT: Allowing Asia session)
    int startHour = 0;
    int endHour = 22;
    
    if(startHour <= endHour)
    {
        if(currentHour < startHour || currentHour >= endHour)
        {
            LogResult(m_lastFilterName, m_lastFilterReason, "TimeFilter", false, StringFormat("Outside trading hours: %d:00 GMT", currentHour));
            return false;
        }
    }
    else  // Overnight hours (e.g., 22 to 2)
    {
        if(currentHour < startHour && currentHour >= endHour)
        {
            LogResult(m_lastFilterName, m_lastFilterReason, "TimeFilter", false, StringFormat("Outside trading hours: %d:00 GMT", currentHour));
            return false;
        }
    }
    
    // Skip weekends (only for non-synthetic symbols)
    if(dt.day_of_week == 0 || dt.day_of_week == 6)
    {
        LogResult(m_lastFilterName, m_lastFilterReason, "TimeFilter", false, "Weekend - trading disabled");
        return false;
    }
    
    LogResult(m_lastFilterName, m_lastFilterReason, "TimeFilter", true, "Active trading session");
    return true;
}

static bool ApplySessionFilter(const SignalFilterSettings &m_filters, string &m_lastFilterName, string &m_lastFilterReason, const string symbol)
{
    // If synthetic indices and off-hours allowed, bypass session filter
    if(m_filters.session.allowSyntheticOffHours && CSignalPipelineNormalizer::IsSyntheticSymbol(symbol))
        return true;
    
    if(!m_filters.session.enableSessionFilter)
        return true;
    
    MqlDateTime dt;
    TimeToStruct(TimeGMT(), dt);
    int gmtHour = dt.hour;
    
    if(m_filters.session.tradeTokyoSession && gmtHour >= 0 && gmtHour < 9)
        return true;
    
    if(m_filters.session.tradeLondonSession && gmtHour >= 8 && gmtHour < 17)
        return true;
    
    if(m_filters.session.tradeNewYorkSession && gmtHour >= 13 && gmtHour < 22)
        return true;
    
    LogResult(m_lastFilterName, m_lastFilterReason, "SessionFilter", false, StringFormat("Not in active trading session: %d:00 GMT", gmtHour));
    return false;
}

static bool ApplySpreadFilter(CMathematicalEngineRegistry* m_mathRegistry, const SignalFilterSettings &m_filters, SPipelineEvidenceSnapshot &m_lastEvidence, string &m_lastFilterName, string &m_lastFilterReason, const string symbol, double &spreadScore, double overrideThreshold, double atrValue)
{
    if(symbol == "")
        return true;

    double atr = atrValue;
    if(atr <= 0.0)
    {
        atr = m_lastEvidence.atrValue;
        if(atr <= 0.0)
        {
            CVolatilityEngine* volatilityEngine = m_mathRegistry ? m_mathRegistry.GetVolatility(symbol) : NULL;
            if(volatilityEngine != NULL)
                atr = volatilityEngine.GetATR();
        }
    }
    if(atr <= 0.0)
    {
        spreadScore = 0.0;
        return true;
    }

    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    if(point <= 0.0)
        point = 0.00001;

    long spreadRaw = SymbolInfoInteger(symbol, SYMBOL_SPREAD);
    double spread = (double)spreadRaw * point;

    double threshold = (overrideThreshold > 0.0) ? overrideThreshold : m_filters.regimeCostGate.maxSpreadToAtrRatio;
    double ratio = spread / atr;
    spreadScore = ratio;

    if(ratio >= threshold)
    {
        LogResult(m_lastFilterName, m_lastFilterReason, "SpreadFilter", false,
                        StringFormat("Spread ratio %.4f >= %.4f (spread %.5f, ATR %.5f)",
                                    ratio, threshold, spread, atr));
        return false;
    }

    LogResult(m_lastFilterName, m_lastFilterReason, "SpreadFilter", true,
                    StringFormat("Spread ratio %.4f < %.4f (spread %.5f, ATR %.5f)",
                                ratio, threshold, spread, atr));
    return true;
}
};

#endif // SIGNAL_PIPELINE_FILTER_MQH
