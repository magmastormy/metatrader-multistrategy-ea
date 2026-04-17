//+------------------------------------------------------------------+
//| Ensemble Types                                                  |
//| Common structures for AI voting and tiered validation           |
//+------------------------------------------------------------------+
#ifndef CORE_ENSEMBLE_TYPES_MQH
#define CORE_ENSEMBLE_TYPES_MQH

#include "Enums.mqh"

//+------------------------------------------------------------------+
//| Ensemble Voting Structure                                       |
//+------------------------------------------------------------------+
struct SEnsembleVote
{
    string strategyName;            // Strategy name
    ENUM_TRADE_SIGNAL signal;      // Strategy signal
    double confidence;              // Signal confidence
    double weight;                  // Strategy weight
    double adjustedWeight;          // Performance-adjusted weight
    ENUM_MARKET_REGIME regime;      // Current market regime
    ENUM_STRATEGY_TIER tier;        // Strategy tier (Ranking Matrix)
    double signalStrength;          // Signal strength (0-1)
    string reasoning;               // Strategy reasoning
    datetime timestamp;             // Vote timestamp
    bool isValid;                   // Vote validity flag
};

//+------------------------------------------------------------------+
//| Ensemble Decision Structure                                     |
//+------------------------------------------------------------------+
struct SEnsembleDecision
{
    ENUM_TRADE_SIGNAL finalSignal;  // Final ensemble decision
    double confidence;              // Final confidence
    int totalVotes;                 // Total votes received
    int validVotes;                 // Valid votes processed
    double consensusStrength;       // Consensus strength (0-1)
    string decisionReasoning;       // Decision reasoning
    datetime decisionTime;          // Decision timestamp
    
    // Vote breakdown
    int buyVotes;                   // Number of buy votes
    int sellVotes;                  // Number of sell votes
    int neutralVotes;               // Number of neutral votes
    double buyWeight;               // Total buy weight
    double sellWeight;              // Total sell weight
    
    // Tiered metrics
    double tier1Weight;
    double tier2Weight;
    double tier3Weight;
    int tier1Votes;
    int tier2Votes;
    int tier3Votes;
    double setupQuality;
    double reliabilityScore;
    bool conflictDetected;

    // Performance tracking
    bool wasSuccessful;             // Track if decision was successful
    double actualOutcome;           // Actual trade outcome
    datetime outcomeTime;           // Outcome timestamp

    SEnsembleDecision()
    {
        finalSignal = TRADE_SIGNAL_NONE;
        confidence = 0.0;
        totalVotes = 0;
        validVotes = 0;
        consensusStrength = 0.0;
        decisionReasoning = "";
        decisionTime = 0;

        buyVotes = 0;
        sellVotes = 0;
        neutralVotes = 0;
        buyWeight = 0.0;
        sellWeight = 0.0;

        tier1Weight = 0.0;
        tier2Weight = 0.0;
        tier3Weight = 0.0;
        tier1Votes = 0;
        tier2Votes = 0;
        tier3Votes = 0;
        setupQuality = 0.0;
        reliabilityScore = 0.0;
        conflictDetected = false;

        wasSuccessful = false;
        actualOutcome = 0.0;
        outcomeTime = 0;
    }

    SEnsembleDecision(const SEnsembleDecision &other)
    {
        finalSignal = other.finalSignal;
        confidence = other.confidence;
        totalVotes = other.totalVotes;
        validVotes = other.validVotes;
        consensusStrength = other.consensusStrength;
        decisionReasoning = other.decisionReasoning;
        decisionTime = other.decisionTime;

        buyVotes = other.buyVotes;
        sellVotes = other.sellVotes;
        neutralVotes = other.neutralVotes;
        buyWeight = other.buyWeight;
        sellWeight = other.sellWeight;

        tier1Weight = other.tier1Weight;
        tier2Weight = other.tier2Weight;
        tier3Weight = other.tier3Weight;
        tier1Votes = other.tier1Votes;
        tier2Votes = other.tier2Votes;
        tier3Votes = other.tier3Votes;
        setupQuality = other.setupQuality;
        reliabilityScore = other.reliabilityScore;
        conflictDetected = other.conflictDetected;

        wasSuccessful = other.wasSuccessful;
        actualOutcome = other.actualOutcome;
        outcomeTime = other.outcomeTime;
    }
};

#endif // CORE_ENSEMBLE_TYPES_MQH
