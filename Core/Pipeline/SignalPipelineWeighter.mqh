//+------------------------------------------------------------------+
//| Signal Pipeline Weighter - readiness/context/quality scoring     |
//| Stateless scoring helpers extracted from CUnifiedSignalPipeline. |
//+------------------------------------------------------------------+
#ifndef SIGNAL_PIPELINE_WEIGHTER_MQH
#define SIGNAL_PIPELINE_WEIGHTER_MQH

#include "../Utils/Enums.mqh"
#include "SignalPipelineTypes.mqh"

class CSignalPipelineWeighter
{
public:
static double ComputeReadinessScore(const SignalFilterSettings &m_filters, const SPipelineEvidenceSnapshot &m_lastEvidence)
{
    double total = 0.0;
    double components = 0.0;

    // Dynamic base readiness score based on readiness class with adaptive staleness handling
    double trendReadinessScore = m_filters.readinessConfig.warmupScore;
    if(m_lastEvidence.readinessClass == "HEALTHY")
        trendReadinessScore = m_filters.readinessConfig.healthyScore;
    else if(m_lastEvidence.readinessClass == "REUSED_SNAPSHOT")
        trendReadinessScore = MathMax(0.45, m_filters.readinessConfig.reusedSnapshotScore - m_lastEvidence.stalenessPenalty);
    else if(m_lastEvidence.readinessClass == "TRANSIENT_COPY_FAULT")
        trendReadinessScore = m_filters.readinessConfig.transientCopyFaultScore;
    else if(m_lastEvidence.readinessClass == "HANDLE_FAULT")
        trendReadinessScore = m_filters.readinessConfig.handleFaultScore;
    else if(m_lastEvidence.readinessClass == "WARMUP")
        trendReadinessScore = m_filters.readinessConfig.warmupScore;

    // Trend readiness with strength-based adjustment
    if(m_filters.trend.enabled)
    {
        double trendComponent = m_lastEvidence.trendReady ? trendReadinessScore : MathMin(trendReadinessScore, 0.62);
        // Boost trend readiness if trend strength is meaningful
        if(m_lastEvidence.trendReady && m_lastEvidence.trendStrength > 50.0)
            trendComponent = MathMin(1.0, trendComponent + 0.08);
        total += trendComponent * m_filters.readinessWeights.trendWeight;
        components += m_filters.readinessWeights.trendWeight;
    }

    // Structure readiness
    if(m_filters.structure.enabled)
    {
        double structureComponent = m_lastEvidence.structureReady ? 0.88 : 0.65;
        if(m_lastEvidence.structureReady && m_lastEvidence.structureStrength > 0.6)
            structureComponent = MathMin(1.0, structureComponent + 0.07);
        total += structureComponent * m_filters.readinessWeights.structureWeight;
        components += m_filters.readinessWeights.structureWeight;
    }

    // Liquidity readiness
    if(m_filters.liquidity.enabled)
    {
        double liquidityComponent = m_lastEvidence.liquidityReady ? 0.92 : 0.68;
        if(m_lastEvidence.liquidityReady && m_lastEvidence.priceNearLiquidity)
            liquidityComponent = MathMin(1.0, liquidityComponent + 0.05);
        total += liquidityComponent * m_filters.readinessWeights.liquidityWeight;
        components += m_filters.readinessWeights.liquidityWeight;
    }

    // Volatility readiness
    if(m_filters.volatility.enabled)
    {
        double volatilityComponent = 0.75;
        if(m_lastEvidence.volatilityReady)
        {
            if(m_lastEvidence.volatilityState == VOLATILITY_NORMAL)
                volatilityComponent = 1.0;
            else if(m_lastEvidence.volatilityState == VOLATILITY_LOW)
                volatilityComponent = 0.95;
            else if(m_lastEvidence.volatilityState == VOLATILITY_HIGH)
                volatilityComponent = 0.90;
            else if(m_lastEvidence.volatilityState == VOLATILITY_EXTREME)
                volatilityComponent = 0.82;
        }
        total += volatilityComponent * m_filters.readinessWeights.volatilityWeight;
        components += m_filters.readinessWeights.volatilityWeight;
    }

    // Regime readiness with cost score integration
    if(m_filters.regimeCostGate.enabled)
    {
        double regimeComponent = m_lastEvidence.regimeValid ? MathMax(0.72, 1.0 - m_lastEvidence.stalenessPenalty) : 0.72;
        // Integrate cost score into regime readiness for more accurate assessment
        if(m_lastEvidence.regimeValid && m_lastEvidence.costScore > 0.0)
            regimeComponent = MathMax(0.65, MathMin(1.0, (regimeComponent + m_lastEvidence.costScore) / 2.0));
        total += regimeComponent * m_filters.readinessWeights.regimeWeight;
        components += m_filters.readinessWeights.regimeWeight;
    }

    if(components <= 0)
        return 1.0;

    double readinessScore = total / components;
    return MathMax(0.0, MathMin(1.0, readinessScore));
}

static double ComputeContextScore(const SPipelineEvidenceSnapshot &m_lastEvidence, const ENUM_TRADE_SIGNAL signal)
{
    // Trend context scoring with granular strength considerations
    double trendScore = 0.72;
    if(signal == TRADE_SIGNAL_BUY)
    {
        if(m_lastEvidence.trend == TREND_BULLISH_STRONG || m_lastEvidence.trend == TREND_BULLISH_WEAK)
        {
            // More nuanced scoring based on trend strength tiers
            if(m_lastEvidence.trendStrength >= 85.0)
                trendScore = 1.0;
            else if(m_lastEvidence.trendStrength >= 70.0)
                trendScore = 0.94;
            else if(m_lastEvidence.trendStrength >= 55.0)
                trendScore = 0.88;
            else
                trendScore = 0.82;
        }
        else if(m_lastEvidence.trend == TREND_BEARISH_STRONG || m_lastEvidence.trend == TREND_BEARISH_WEAK)
        {
            // Strong opposing trend penalizes more heavily
            if(m_lastEvidence.trendStrength >= 85.0)
                trendScore = 0.38;
            else if(m_lastEvidence.trendStrength >= 70.0)
                trendScore = 0.45;
            else
                trendScore = 0.58;
        }
        else if(m_lastEvidence.trend == TREND_RANGING || m_lastEvidence.trend == TREND_NONE)
        {
            // Neutral trend - moderate score for ranging markets
            trendScore = 0.78;
        }
    }
    else if(signal == TRADE_SIGNAL_SELL)
    {
        if(m_lastEvidence.trend == TREND_BEARISH_STRONG || m_lastEvidence.trend == TREND_BEARISH_WEAK)
        {
            if(m_lastEvidence.trendStrength >= 85.0)
                trendScore = 1.0;
            else if(m_lastEvidence.trendStrength >= 70.0)
                trendScore = 0.94;
            else if(m_lastEvidence.trendStrength >= 55.0)
                trendScore = 0.88;
            else
                trendScore = 0.82;
        }
        else if(m_lastEvidence.trend == TREND_BULLISH_STRONG || m_lastEvidence.trend == TREND_BULLISH_WEAK)
        {
            if(m_lastEvidence.trendStrength >= 85.0)
                trendScore = 0.38;
            else if(m_lastEvidence.trendStrength >= 70.0)
                trendScore = 0.45;
            else
                trendScore = 0.58;
        }
        else if(m_lastEvidence.trend == TREND_RANGING || m_lastEvidence.trend == TREND_NONE)
        {
            trendScore = 0.78;
        }
    }

    // Structure context scoring with improved strength integration
    double structureScore = 0.70;
    if(signal == TRADE_SIGNAL_BUY && m_lastEvidence.bullishStructure)
    {
        // Boost for aligned structure with strength consideration
        structureScore = MathMin(1.0, 0.92 + (m_lastEvidence.structureStrength / 600.0));
    }
    else if(signal == TRADE_SIGNAL_SELL && m_lastEvidence.bearishStructure)
    {
        structureScore = MathMin(1.0, 0.92 + (m_lastEvidence.structureStrength / 600.0));
    }
    else if(m_lastEvidence.structureStrength > 0.0)
    {
        // Partial credit for structure presence even if not aligned
        structureScore = MathMax(0.52, MathMin(0.88, 0.58 + (m_lastEvidence.structureStrength / 300.0)));
    }

    // Liquidity context scoring with sweep and proximity considerations
    double liquidityScore = 0.75;
    if(m_lastEvidence.liquiditySweep)
        liquidityScore = 0.96; // Strong boost for recent liquidity sweep
    if(m_lastEvidence.priceNearLiquidity)
        liquidityScore = MathMin(liquidityScore, 0.80); // Slight reduction near untested liquidity

    // Volatility context scoring with adaptive weighting based on ATR percentage
    double volatilityScore = 0.78;
    if(m_lastEvidence.volatilityState == VOLATILITY_NORMAL)
        volatilityScore = 1.0;
    else if(m_lastEvidence.volatilityState == VOLATILITY_LOW)
        volatilityScore = 0.92;
    else if(m_lastEvidence.volatilityState == VOLATILITY_HIGH)
        volatilityScore = 0.78;
    else if(m_lastEvidence.volatilityState == VOLATILITY_EXTREME)
        volatilityScore = 0.52;
    
    // Additional adjustment based on ATR percentage for fine-tuning
    if(m_lastEvidence.atrPercent > 0.0)
    {
        if(m_lastEvidence.atrPercent < 0.3) // Very low volatility
            volatilityScore = MathMin(volatilityScore, 0.88);
        else if(m_lastEvidence.atrPercent > 1.5) // Very high volatility
            volatilityScore = MathMax(volatilityScore * 0.85, 0.45);
    }

    // Regime context scoring with enhanced state integration
    double regimeScore = m_lastEvidence.costScore;
    if(!m_lastEvidence.regimeValid)
        regimeScore = MathMin(regimeScore, 0.70);
    else
    {
        if(m_lastEvidence.regimeState == REGIME_BREAKOUT || m_lastEvidence.regimeState == REGIME_TREND)
            regimeScore = MathMax(regimeScore, 0.94);
        else if(m_lastEvidence.regimeState == REGIME_RANGE)
            regimeScore = MathMin(MathMax(regimeScore, 0.78), 0.90);
        else if(m_lastEvidence.regimeState == REGIME_CHAOS)
            regimeScore = MathMin(regimeScore, 0.65);
        
        // Adjust for readiness class
        if(m_lastEvidence.readinessClass == "REUSED_SNAPSHOT")
            regimeScore = MathMax(0.65, regimeScore - m_lastEvidence.stalenessPenalty);
    }

    // Weighted average with trend and structure having higher importance
    double trendWeight = 1.25;
    double structureWeight = 1.15;
    double liquidityWeight = 0.90;
    double volatilityWeight = 1.05;
    double regimeWeight = 1.10;
    
    double totalWeight = trendWeight + structureWeight + liquidityWeight + volatilityWeight + regimeWeight;
    double weightedTotal = (trendScore * trendWeight) + 
                          (structureScore * structureWeight) + 
                          (liquidityScore * liquidityWeight) + 
                          (volatilityScore * volatilityWeight) + 
                          (regimeScore * regimeWeight);
    
    double contextScore = weightedTotal / totalWeight;
    return MathMax(0.0, MathMin(1.0, contextScore));
}

static double CalculateQualityScore(double confidence, int confluence, bool passedFilters,
                                   double convictionScore, double readinessScore, double contextScore,
                                   double diversityScore, double costScore, double directionalQuality,
                                   double supportRatio)
{
    double score = 0.0;
    
    // Validate inputs - handle NaN and extreme values
    if(!MathIsValidNumber(confidence) || confidence < 0.0 || confidence > 1.0)
        confidence = 0.0;
    
    // Normalized weights summing to 1.0 (was 0.92, scaled by 1/0.92 = 1.0869565...)
    // Original: confidence=0.20, confluence=0.10, conviction=0.12, readiness=0.08,
    //           context=0.08, diversity=0.07, cost=0.05, directionalQuality=0.15, supportRatio=0.07
    // Filter bonus removed as ad-hoc component; its weight redistributed
    
    // Confidence component
    score += confidence * 0.2174;
    
    // Confluence component (Biased scale to avoid punishing solo high-quality signals)
    double confluenceScore = 0.0;
    if(confluence == 1) confluenceScore = 0.50;      // Solo signal starts with decent baseline
    else if(confluence == 2) confluenceScore = 0.80;
    else if(confluence >= 3) confluenceScore = 1.0;
    score += confluenceScore * 0.1087;
    
    // Decision-path components with NaN protection
    convictionScore = MathIsValidNumber(convictionScore) ? convictionScore : 0.0;
    readinessScore = MathIsValidNumber(readinessScore) ? readinessScore : 0.0;
    contextScore = MathIsValidNumber(contextScore) ? contextScore : 0.0;
    diversityScore = MathIsValidNumber(diversityScore) ? diversityScore : 0.0;
    costScore = MathIsValidNumber(costScore) ? costScore : 0.0;
    directionalQuality = MathIsValidNumber(directionalQuality) ? directionalQuality : 0.0;
    supportRatio = MathIsValidNumber(supportRatio) ? supportRatio : 0.0;
    
    score += MathMax(0.0, MathMin(1.0, convictionScore)) * 0.1304;
    score += MathMax(0.0, MathMin(1.0, readinessScore)) * 0.0870;
    score += MathMax(0.0, MathMin(1.0, contextScore)) * 0.0870;
    score += MathMax(0.0, MathMin(1.0, diversityScore)) * 0.0761;
    score += MathMax(0.0, MathMin(1.0, costScore)) * 0.0543;
    score += MathMax(0.0, MathMin(1.0, directionalQuality)) * 0.1630;
    score += MathMax(0.0, MathMin(1.0, supportRatio)) * 0.0761;
    
    // Filter component (properly weighted at 5%)
    if(passedFilters)
        score += 1.0 * 0.0543;
    
    // Ensure final score is valid and in range [0, 1]
    if(!MathIsValidNumber(score))
        score = 0.0;
    
    return MathMax(0.0, MathMin(1.0, score));
}
};

#endif // SIGNAL_PIPELINE_WEIGHTER_MQH
