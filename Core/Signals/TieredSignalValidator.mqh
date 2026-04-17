//+------------------------------------------------------------------+
//| TieredSignalValidator.mqh                                        |
//| Comprehensive multi-tier signal validation and conflict resolution|
//+------------------------------------------------------------------+
#ifndef CORE_TIERED_SIGNAL_VALIDATOR_MQH
#define CORE_TIERED_SIGNAL_VALIDATOR_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/RankingMatrix.mqh"
#include "../Utils/EnsembleTypes.mqh"

//+------------------------------------------------------------------+
//| Signal Validation Result Structure                              |
//+------------------------------------------------------------------+
struct STieredValidationResult
{
    ENUM_TRADE_SIGNAL finalSignal;
    double confidence;
    double consensusScore;
    double tier1Weight;
    double tier2Weight;
    double tier3Weight;
    int tier1Votes;
    int tier2Votes;
    int tier3Votes;
    string reason;
    bool conflictDetected;
    double setupQuality;             // Overall setup quality (0.0 to 1.0)
    double reliabilityScore;         // Weighted reliability based on tier performance
};

//+------------------------------------------------------------------+
//| Tier Performance Metrics Structure                               |
//+------------------------------------------------------------------+
struct STierPerformance
{
    ENUM_STRATEGY_TIER tier;
    int totalSignals;
    int successfulSignals;
    double accuracy;
    double avgConfidence;
    double lastAccuracy;            // Last 20 signals accuracy
    int successBuffer[20];
    int bufferIndex;

    STierPerformance() : totalSignals(0), successfulSignals(0), accuracy(0), avgConfidence(0), lastAccuracy(0), bufferIndex(0) 
    {
        ArrayInitialize(successBuffer, 0);
    }
};

//+------------------------------------------------------------------+
//| Tiered Signal Validator Class                                    |
//+------------------------------------------------------------------+
class CTieredSignalValidator
{
private:
    double m_conflictThreshold;
    double m_minQuorumWeight;
    STierPerformance m_tierMetrics[3]; // T1, T2, T3
    
    // Configurable Weights for Decision Making
    double m_wTier1;
    double m_wTier2;
    double m_wTier3;
    double m_wSetupQuality;

public:
    CTieredSignalValidator() : 
        m_conflictThreshold(0.3), 
        m_minQuorumWeight(0.5),
        m_wTier1(0.50),
        m_wTier2(0.30),
        m_wTier3(0.20),
        m_wSetupQuality(0.4)
    {
        m_tierMetrics[0].tier = STRATEGY_TIER_1;
        m_tierMetrics[1].tier = STRATEGY_TIER_2;
        m_tierMetrics[2].tier = STRATEGY_TIER_3;
    }

    // Main validation entry point
    STieredValidationResult ValidateSignals(SEnsembleVote &votes[], int voteCount)
    {
        STieredValidationResult result;
        result.finalSignal = TRADE_SIGNAL_NONE;
        result.confidence = 0.0;
        result.consensusScore = 0.0;
        result.tier1Weight = 0.0;
        result.tier2Weight = 0.0;
        result.tier3Weight = 0.0;
        result.tier1Votes = 0;
        result.tier2Votes = 0;
        result.tier3Votes = 0;
        result.conflictDetected = false;
        result.setupQuality = 0.0;
        result.reliabilityScore = 0.0;

        if(voteCount == 0) return result;

        double buyWeight = 0.0;
        double sellWeight = 0.0;
        double totalWeight = 0.0;
        double totalSetupQuality = 0.0;

        for(int i = 0; i < voteCount; i++)
        {
            if(!votes[i].isValid) continue;

            double tierMult = CRankingMatrix::GetTierMultiplier(votes[i].tier);
            double effectiveWeight = votes[i].adjustedWeight * tierMult * votes[i].confidence;
            
            // setup quality integration
            totalSetupQuality += votes[i].signalStrength * effectiveWeight;

            // Update tier-specific stats
            if(votes[i].tier == STRATEGY_TIER_1) { result.tier1Votes++; result.tier1Weight += effectiveWeight; }
            else if(votes[i].tier == STRATEGY_TIER_2) { result.tier2Votes++; result.tier2Weight += effectiveWeight; }
            else { result.tier3Votes++; result.tier3Weight += effectiveWeight; }

            if(votes[i].signal == TRADE_SIGNAL_BUY) buyWeight += effectiveWeight;
            else if(votes[i].signal == TRADE_SIGNAL_SELL) sellWeight += effectiveWeight;
            
            totalWeight += effectiveWeight;
        }

        if(totalWeight <= 0) return result;

        double buyRatio = buyWeight / totalWeight;
        double sellRatio = sellWeight / totalWeight;
        result.setupQuality = totalSetupQuality / totalWeight;

        // Detect and Resolve Conflicts
        ENUM_TRADE_SIGNAL resolvedSignal = ResolveTierConflicts(votes, voteCount, result);
        
        // Reliability Scoring (Historical + Real-time)
        result.reliabilityScore = CalculateReliability(result);

        // Weighted Decision Logic considering Setup Quality
        double decisionThreshold = 0.65 - (result.setupQuality * 0.1); // Higher quality lowers threshold slightly
        
        if(resolvedSignal != TRADE_SIGNAL_NONE)
        {
            double directionRatio = (resolvedSignal == TRADE_SIGNAL_BUY) ? buyRatio : sellRatio;
            if(directionRatio >= decisionThreshold)
            {
                result.finalSignal = resolvedSignal;
            }
        }

        result.confidence = MathMax(buyRatio, sellRatio);
        result.consensusScore = (totalWeight / (double)voteCount); 
        
        result.reason = StringFormat("T1:%d T2:%d T3:%d | Quality:%.2f | Buy:%.1f%% Sell:%.1f%% %s", 
                                     result.tier1Votes, result.tier2Votes, result.tier3Votes,
                                     result.setupQuality, buyRatio * 100, sellRatio * 100,
                                     result.conflictDetected ? "[CONFLICT]" : "");

        return result;
    }

    // Track performance by tier and signal type
    void RecordOutcome(int tier1Votes, int tier2Votes, int tier3Votes, bool successful)
    {
        if(tier1Votes > 0) RecordTierOutcome(STRATEGY_TIER_1, successful);
        if(tier2Votes > 0) RecordTierOutcome(STRATEGY_TIER_2, successful);
        if(tier3Votes > 0) RecordTierOutcome(STRATEGY_TIER_3, successful);
    }

private:
    void RecordTierOutcome(ENUM_STRATEGY_TIER tier, bool successful)
    {
        int idx = (int)tier - 1;
        if(idx < 0 || idx >= 3) return;

        m_tierMetrics[idx].totalSignals++;
        if(successful) m_tierMetrics[idx].successfulSignals++;
        
        m_tierMetrics[idx].accuracy = (double)m_tierMetrics[idx].successfulSignals / m_tierMetrics[idx].totalSignals;
        
        // Rolling accuracy
        m_tierMetrics[idx].successBuffer[m_tierMetrics[idx].bufferIndex] = successful ? 1 : 0;
        m_tierMetrics[idx].bufferIndex = (m_tierMetrics[idx].bufferIndex + 1) % 20;
        
        int rollingSum = 0;
        int count = 0;
        for(int i = 0; i < 20; i++)
        {
            if(m_tierMetrics[idx].totalSignals > i)
            {
                rollingSum += m_tierMetrics[idx].successBuffer[i];
                count++;
            }
        }
        if(count > 0) m_tierMetrics[idx].lastAccuracy = (double)rollingSum / count;
    }

private:
    ENUM_TRADE_SIGNAL ResolveTierConflicts(SEnsembleVote &votes[], int voteCount, STieredValidationResult &result)
    {
        ENUM_TRADE_SIGNAL t1Signal = GetTierDominantSignal(votes, voteCount, STRATEGY_TIER_1);
        ENUM_TRADE_SIGNAL t2Signal = GetTierDominantSignal(votes, voteCount, STRATEGY_TIER_2);
        ENUM_TRADE_SIGNAL t3Signal = GetTierDominantSignal(votes, voteCount, STRATEGY_TIER_3);

        if(t1Signal == TRADE_SIGNAL_NONE) 
        {
            // If no Tier 1, require T2 and T3 agreement or strong T2
            if(t2Signal != TRADE_SIGNAL_NONE && t2Signal == t3Signal) return t2Signal;
            if(t2Signal != TRADE_SIGNAL_NONE && GetTierWeight(result, STRATEGY_TIER_2) > GetTierWeight(result, STRATEGY_TIER_3) * 2) return t2Signal;
            return TRADE_SIGNAL_NONE;
        }

        // Conflict Detection
        if((t2Signal != TRADE_SIGNAL_NONE && t2Signal != t1Signal) ||
           (t3Signal != TRADE_SIGNAL_NONE && t3Signal != t1Signal))
        {
            result.conflictDetected = true;
            
            // Conflict Resolution Protocol:
            // 1. If Tier 1 has high confidence and T2/T3 are split, follow T1
            // 2. If T2 and T3 agree against T1 AND they have combined weight > T1 * 1.5, follow T2/T3
            // 3. Otherwise, stay neutral (signal none)
            
            double w1 = GetTierWeight(result, STRATEGY_TIER_1);
            double w2 = GetTierWeight(result, STRATEGY_TIER_2);
            double w3 = GetTierWeight(result, STRATEGY_TIER_3);
            
            if(t2Signal == t3Signal && t2Signal != TRADE_SIGNAL_NONE)
            {
                if((w2 + w3) > w1 * 1.5) return t2Signal; // Tier 2+3 consensus overrides Tier 1
            }
            
            if(w1 > (w2 + w3) * 1.2) return t1Signal; // Tier 1 dominance
            
            return TRADE_SIGNAL_NONE; // Unresolved conflict
        }

        return t1Signal; // No conflict, follow Tier 1
    }

    double GetTierWeight(STieredValidationResult &res, ENUM_STRATEGY_TIER tier)
    {
        if(tier == STRATEGY_TIER_1) return res.tier1Weight;
        if(tier == STRATEGY_TIER_2) return res.tier2Weight;
        return res.tier3Weight;
    }

    double CalculateReliability(STieredValidationResult &res)
    {
        double totalWeight = res.tier1Weight + res.tier2Weight + res.tier3Weight;
        if(totalWeight <= 0) return 0.0;

        double r1 = m_tierMetrics[0].lastAccuracy > 0 ? m_tierMetrics[0].lastAccuracy : 0.6;
        double r2 = m_tierMetrics[1].lastAccuracy > 0 ? m_tierMetrics[1].lastAccuracy : 0.5;
        double r3 = m_tierMetrics[2].lastAccuracy > 0 ? m_tierMetrics[2].lastAccuracy : 0.4;

        return (res.tier1Weight * r1 + res.tier2Weight * r2 + res.tier3Weight * r3) / totalWeight;
    }

    ENUM_TRADE_SIGNAL GetTierDominantSignal(SEnsembleVote &votes[], int voteCount, ENUM_STRATEGY_TIER tier)
    {
        double buyW = 0, sellW = 0;
        int count = 0;
        for(int i = 0; i < voteCount; i++)
        {
            if(votes[i].tier == tier && votes[i].isValid)
            {
                if(votes[i].signal == TRADE_SIGNAL_BUY) buyW += votes[i].adjustedWeight * votes[i].confidence;
                else if(votes[i].signal == TRADE_SIGNAL_SELL) sellW += votes[i].adjustedWeight * votes[i].confidence;
                count++;
            }
        }
        if(count == 0) return TRADE_SIGNAL_NONE;
        if(buyW > sellW * 1.3) return TRADE_SIGNAL_BUY;
        if(sellW > buyW * 1.3) return TRADE_SIGNAL_SELL;
        return TRADE_SIGNAL_NONE;
    }
};

#endif // CORE_TIERED_SIGNAL_VALIDATOR_MQH
