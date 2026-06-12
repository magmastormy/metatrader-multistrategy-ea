//+------------------------------------------------------------------+
//| RankingMatrix.mqh                                               |
//| Tier-based prioritization for ICT and Indicator signals         |
//+------------------------------------------------------------------+
#ifndef CORE_RANKING_MATRIX_MQH
#define CORE_RANKING_MATRIX_MQH

#include "Enums.mqh"

//+------------------------------------------------------------------+
//| Ranking Matrix Configuration                                     |
//+------------------------------------------------------------------+
class CRankingMatrix
{
public:
    // Returns the priority multiplier for a given tier (higher = more influence)
    static double GetTierMultiplier(ENUM_STRATEGY_TIER tier)
    {
        switch(tier)
        {
            case STRATEGY_TIER_1: return 2.5; // Institutional/Liquidity
            case STRATEGY_TIER_2: return 1.5; // Market Structure
            case STRATEGY_TIER_3: return 0.8; // Indicators/Oscillators
            default: return 1.0;
        }
    }

    // Returns the confidence required for a signal to be considered "Quality" based on tier
    static double GetRequiredConfidence(ENUM_STRATEGY_TIER tier)
    {
        switch(tier)
        {
            case STRATEGY_TIER_1: return 0.25; // Reduced from 0.30
            case STRATEGY_TIER_2: return 0.45; // Reduced from 0.50
            case STRATEGY_TIER_3: return 0.50; // Tier 3: reduced to allow indicator-only signals (was 0.62)
            default: return 0.45;
        }
    }

    // Resolves conflict between two signals
    // Returns 1 if signal A wins, -1 if signal B wins, 0 if tie
    static int ResolveConflict(ENUM_STRATEGY_TIER tierA, double confA, 
                               ENUM_STRATEGY_TIER tierB, double confB)
    {
        double scoreA = confA * GetTierMultiplier(tierA);
        double scoreB = confB * GetTierMultiplier(tierB);

        if(scoreA > scoreB * 1.2) return 1;
        if(scoreB > scoreA * 1.2) return -1;
        return 0;
    }

    // NEW: Check for dynamic tier escalation (e.g., Trend + S/R agreement = Tier 1 power)
    static ENUM_STRATEGY_TIER CheckConfluenceEscalation(const string nameA, double confA, ENUM_TRADE_SIGNAL signalA,
                                                      const string nameB, double confB, ENUM_TRADE_SIGNAL signalB)
    {
        // Special Case: Trend + Support/Resistance Agreement on a Reversal/Strong Move
        if(signalA == signalB && signalA != TRADE_SIGNAL_NONE)
        {
            // Extract base names if they are qualified (e.g., EURUSD::Trend -> Trend)
            string baseA = nameA;
            string baseB = nameB;

            int posA = StringFind(nameA, "::");
            if(posA >= 0) baseA = StringSubstr(nameA, posA + 2);

            int posB = StringFind(nameB, "::");
            if(posB >= 0) baseB = StringSubstr(nameB, posB + 2);

            // Fibonacci REMOVED — Trend + S/R confluence escalation replaces the old Trend+Fib pair
            if((baseA == "Trend" && baseB == "Support/Resistance") || (baseA == "Support/Resistance" && baseB == "Trend"))
            {
                if(confA > 0.65 && confB > 0.65)
                {
                    // If Trend and S/R agree with high confidence, they escalate to Tier 1 influence
                    return STRATEGY_TIER_1;
                }
            }
        }
        return STRATEGY_TIER_3; // No escalation
    }
};

#endif // CORE_RANKING_MATRIX_MQH
