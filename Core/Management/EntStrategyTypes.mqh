// Enterprise Strategy Types (Phase G - G1)
// Shared value types (struct StrategyEntry, the 40-field registration record) and free
// enum -> text / reason-tag / [0,1] clamp helpers, extracted verbatim.
// These are file-scope (non-member) declarations. They are consumed
// by the Phase C slice modules (CStrategyStateReporter,
// CStrategyRegistryState, CIntrabarPolicy, CConsensusEngine) which
// rely on them being visible BEFORE their own definitions, so this
// header must stay included at the exact position the originals
// occupied in EnterpriseStrategyManager.mqh: after the strategy
// registry include, before the slice-module includes.
// NOTHING IN THIS FILE WAS CHANGED - every body is a byte-for-byte
// relocation of the original.
#ifndef ENT_STRATEGY_TYPES_MQH
#define ENT_STRATEGY_TYPES_MQH

#include "../Utils/Enums.mqh"              // ENUM_STRATEGY_TIER / ROLE / CLUSTER / INTRABAR_POLICY / TRADE_SIGNAL
#include "../../Interfaces/IStrategy.mqh"  // IStrategy* member of StrategyEntry

struct StrategyEntry
{
    IStrategy* strategy;
    string name;
    bool enabled;
    bool intrabarEligible;
    int intrabarPolicy;
    bool liveVotingEnabled;
    int role;
    int cluster;
    ENUM_STRATEGY_TIER tier;             // Strategy Tier (Ranking Matrix)
    double weight;
    double originalWeight;              // Track original weight for decay recovery
    ENUM_TIMEFRAMES timeframe;
    int successCount;
    int failCount;
    double healthScore;
    double participationScore;
    double avgConfidence;
    ENUM_TRADE_SIGNAL lastSignal;
    double lastSignalConfidence;
    datetime lastEvaluationTime;
    int consecutiveFilterCount;         // Count consecutive no-signal cycles for decay

    int totalTrades;
    int winningTrades;
    double winRate;
    double avgProfit;
    double avgLoss;
    double profitFactor;
    double sharpeRatio;
    
    // Recent performance tracking (20-trade rolling window)
    double recentTrades[20];
    int recentTradeIndex;
    int recentTradeCount;
    double recentWinRate;
    
    int consecutiveLosses;
    int maxConsecutiveLosses;
    int consecutiveWins;
    
    bool temporarilyDisabled;
    datetime disabledUntil;
    datetime lastUpdate;

    // Consensus component scores (populated by pipeline/consensus engine)
    double participation;        // Participation multiplier [0-1]
    double readinessScore;
    double contextScore;
    double costScore;
    bool isProbeEligible;        // Eligible for intrabar probe voting

    double regimePerformance[5];
    int regimeTrades[5];
};




string StrategyRoleToString(const ENUM_STRATEGY_ROLE role)
{
    switch(role)
    {
        case PRIMARY_ALPHA: return "PRIMARY_ALPHA";
        case CONTEXT_FEATURE: return "CONTEXT_FEATURE";
        default: return "PRIMARY_ALPHA";
    }
}

string StrategyClusterToString(const ENUM_STRATEGY_CLUSTER cluster)
{
    switch(cluster)
    {
        case TREND_CLUSTER: return "TREND_CLUSTER";
        case MEAN_REVERSION_CLUSTER: return "MEAN_REVERSION_CLUSTER";
        case STRUCTURE_CLUSTER: return "STRUCTURE_CLUSTER";
        case SCALP_CLUSTER: return "SCALP_CLUSTER";
        case STRATEGY_CLUSTER_NONE:
        default:
            return "NONE";
    }
}

string StrategyClusterShortCode(const ENUM_STRATEGY_CLUSTER cluster)
{
    switch(cluster)
    {
        case TREND_CLUSTER: return "T";
        case MEAN_REVERSION_CLUSTER: return "R";
        case STRUCTURE_CLUSTER: return "S";
        case SCALP_CLUSTER: return "X";
        case STRATEGY_CLUSTER_NONE:
        default:
            return "N";
    }
}

string IntrabarPolicyToString(const ENUM_INTRABAR_POLICY policy)
{
    switch(policy)
    {
        case INTRABAR_POLICY_OFF: return "OFF";
        case INTRABAR_POLICY_PROBE: return "PROBE";
        case INTRABAR_POLICY_LIVE: return "LIVE";
        default: return "OFF";
    }
}


string TradeSignalToString(const ENUM_TRADE_SIGNAL signal)
{
    switch(signal)
    {
        case TRADE_SIGNAL_BUY: return "BUY";
        case TRADE_SIGNAL_SELL: return "SELL";
        case TRADE_SIGNAL_NONE: return "NONE";
        default: return "UNKNOWN";
    }
}

bool IsInfrastructureNoSignalReasonTag(const string reasonTag)
{
    if(reasonTag == "")
        return false;

    return (StringFind(reasonTag, "_WARMING_UP") >= 0 ||
            StringFind(reasonTag, "_UNAVAILABLE") >= 0 ||
            StringFind(reasonTag, "_DISABLED_OR_UNAVAILABLE") >= 0 ||
            StringFind(reasonTag, "_DISABLED_OR_UNINIT") >= 0 ||
            StringFind(reasonTag, "_INVALID_HANDLES") >= 0 ||
            StringFind(reasonTag, "_INIT_FAILED") >= 0 ||
            StringFind(reasonTag, "_FEATURES_UNAVAILABLE") >= 0 ||
            StringFind(reasonTag, "_SCALER_APPLY_FAILED") >= 0 ||
            StringFind(reasonTag, "_INFERENCE_FAILED") >= 0 ||
            StringFind(reasonTag, "_MODEL_UNAVAILABLE") >= 0);
}

// Clamp value to [0.0, 1.0] range
inline double ClampUnitValue(const double value)
{
    return MathMax(0.0, MathMin(1.0, value));
}

#endif // ENT_STRATEGY_TYPES_MQH
