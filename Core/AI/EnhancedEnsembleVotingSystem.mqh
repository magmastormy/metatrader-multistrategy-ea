//+------------------------------------------------------------------+
//| Enhanced Ensemble Voting System                               |
//| Advanced voting system with confidence weighting and tie-breaking|
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_ENHANCED_ENSEMBLE_VOTING_SYSTEM_MQH
#define CORE_ENHANCED_ENSEMBLE_VOTING_SYSTEM_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CModeManager;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;
class CAIStrategyOrchestrator;

//+------------------------------------------------------------------+
//| Enhanced Ensemble Vote Structure                               |
//+------------------------------------------------------------------+
struct SEnhancedEnsembleVote
{
    string strategyName;                // Strategy name
    ENUM_TRADE_SIGNAL signal;          // Strategy signal
    double confidence;                  // Signal confidence (0-1)
    double weight;                      // Strategy weight
    double performanceScore;            // Recent performance score (0-1)
    double agreementBonus;              // Bonus for agreement with others
    double disagreementPenalty;         // Penalty for disagreement
    ENUM_MARKET_REGIME preferredRegime; // Strategy's preferred regime
    double regimeMatch;                 // How well current regime matches preference
    datetime signalTime;                // When signal was generated
    string reasoning;                   // Strategy reasoning/explanation
    bool isValid;                       // Vote validity flag
};

//+------------------------------------------------------------------+
//| Ensemble Decision Structure                                    |
//+------------------------------------------------------------------+
struct SEnsembleDecision
{
    ENUM_TRADE_SIGNAL finalSignal;      // Final ensemble decision
    double finalConfidence;             // Final confidence level
    double consensusLevel;              // Level of consensus (0-1)
    int totalVotes;                     // Total number of votes
    int buyVotes;                       // Number of buy votes
    int sellVotes;                      // Number of sell votes
    int neutralVotes;                   // Number of neutral votes
    double averageConfidence;           // Average confidence of all votes
    double weightedConfidence;          // Weighted average confidence
    string tieBreakingReason;           // Reason for tie-breaking decision
    string consensusAnalysis;           // Analysis of consensus
    datetime decisionTime;              // When decision was made
    bool wasUnanimous;                  // Whether decision was unanimous
    bool requiredTieBreaking;           // Whether tie-breaking was needed
};

//+------------------------------------------------------------------+
//| Voting Configuration Structure                                 |
//+------------------------------------------------------------------+
struct SVotingConfig
{
    double minConfidenceThreshold;      // Minimum confidence to participate (default 0.3)
    double consensusThreshold;          // Threshold for consensus (default 0.6)
    double agreementBonusMultiplier;    // Multiplier for agreement bonus (default 1.2)
    double disagreementPenaltyFactor;   // Factor for disagreement penalty (default 0.8)
    bool useConfidenceWeighting;        // Use confidence-based weighting
    bool usePerformanceWeighting;       // Use performance-based weighting
    bool enableAgreementBonus;          // Enable agreement bonus system
    bool enableDisagreementPenalty;     // Enable disagreement penalty
    bool enableRegimeMatching;          // Enable regime preference matching
    int maxVotingStrategies;            // Maximum strategies in voting (default 10)
    double tieBreakingConfidenceBoost;  // Confidence boost for tie-breaking (default 0.1)
};

//+------------------------------------------------------------------+
//| Enhanced Ensemble Voting System Class                         |
//+------------------------------------------------------------------+
class CEnhancedEnsembleVotingSystem
{
private:
    SVotingConfig m_config;             // Voting configuration
    
    // Voting statistics
    int m_totalDecisions;               // Total decisions made
    int m_unanimousDecisions;           // Unanimous decisions
    int m_tieBreakingDecisions;         // Decisions requiring tie-breaking
    double m_averageConsensus;          // Average consensus level
    
    // Performance tracking
    SEnsembleDecision m_lastDecision;   // Last ensemble decision
    SEnsembleDecision m_decisions[100]; // Recent decisions history
    int m_decisionIndex;                // Current decision index
    int m_decisionCount;                // Number of decisions stored
    
    // Market regime integration
    ENUM_MARKET_REGIME m_currentRegime; // Current market regime
    double m_regimeConfidence;          // Regime confidence
    
    bool m_initialized;
    
public:
    // Constructor and destructor
    CEnhancedEnsembleVotingSystem(void);
    ~CEnhancedEnsembleVotingSystem(void);
    
    // Initialization
    bool Initialize(const SVotingConfig &config);
    void SetDefaultConfiguration(void);
    
    // Main voting functions
    SEnsembleDecision ProcessEnsembleVoting(SEnhancedEnsembleVote &votes[], int voteCount);
    ENUM_TRADE_SIGNAL GetEnsembleSignal(SEnhancedEnsembleVote &votes[], int voteCount, double &confidence);
    
    // Voting process steps
    void PreprocessVotes(SEnhancedEnsembleVote &votes[], int voteCount);
    void CalculateAgreementBonuses(SEnhancedEnsembleVote &votes[], int voteCount);
    void ApplyDisagreementPenalties(SEnhancedEnsembleVote &votes[], int voteCount);
    void ApplyRegimeMatching(SEnhancedEnsembleVote &votes[], int voteCount);
    
    // Weighted voting implementation
    SEnsembleDecision ProcessWeightedVoting(SEnhancedEnsembleVote &votes[], int voteCount);
    double CalculateEffectiveWeight(const SEnhancedEnsembleVote &vote);
    double CalculateVoteStrength(const SEnhancedEnsembleVote &vote);
    
    // Confidence-based voting
    SEnsembleDecision ProcessConfidenceWeightedVoting(SEnhancedEnsembleVote &votes[], int voteCount);
    double CalculateConfidenceAdjustedWeight(const SEnhancedEnsembleVote &vote);
    
    // Tie-breaking system
    ENUM_TRADE_SIGNAL ResolveTieBreaking(SEnhancedEnsembleVote &votes[], int voteCount, 
                                        double &confidence, string &reason);
    ENUM_TRADE_SIGNAL HighestConfidenceTieBreaker(SEnhancedEnsembleVote &votes[], int voteCount, 
                                                 double &confidence);
    ENUM_TRADE_SIGNAL PerformanceBasedTieBreaker(SEnhancedEnsembleVote &votes[], int voteCount, 
                                                 double &confidence);
    ENUM_TRADE_SIGNAL RegimePreferenceTieBreaker(SEnhancedEnsembleVote &votes[], int voteCount, 
                                                 double &confidence);
    
    // Consensus analysis
    double CalculateConsensusLevel(SEnhancedEnsembleVote &votes[], int voteCount, ENUM_TRADE_SIGNAL signal);
    bool IsUnanimousDecision(SEnhancedEnsembleVote &votes[], int voteCount, ENUM_TRADE_SIGNAL signal);
    string AnalyzeConsensus(SEnhancedEnsembleVote &votes[], int voteCount, ENUM_TRADE_SIGNAL signal);
    
    // Decision tracking and analysis
    void RecordDecision(const SEnsembleDecision &decision);
    SEnsembleDecision GetLastDecision(void) const { return m_lastDecision; }
    double GetAverageConsensus(void);
    double GetUnanimousDecisionRate(void);
    double GetTieBreakingRate(void);
    
    // Configuration management
    void SetMinConfidenceThreshold(const double threshold);
    void SetConsensusThreshold(const double threshold);
    void EnableAgreementBonus(const bool enable) { m_config.enableAgreementBonus = enable; }
    void EnableDisagreementPenalty(const bool enable) { m_config.enableDisagreementPenalty = enable; }
    void SetCurrentRegime(ENUM_MARKET_REGIME regime, double confidence);
    
    // Information and reporting
    string GetVotingSummary(SEnhancedEnsembleVote &votes[], int voteCount);
    string GetDecisionSummary(const SEnsembleDecision &decision);
    void PrintVotingReport(void);
    void LogEnsembleDecision(const SEnsembleDecision &decision);
    
    // Validation functions
    bool ValidateVote(const SEnhancedEnsembleVote &vote);
    bool ValidateVotes(SEnhancedEnsembleVote &votes[], int voteCount);
    
private:
    // Internal helper functions
    void InitializeDefaultConfig(void);
    void FilterValidVotes(SEnhancedEnsembleVote &votes[], int &voteCount);
    void SortVotesByConfidence(SEnhancedEnsembleVote &votes[], int voteCount);
    void SortVotesByPerformance(SEnhancedEnsembleVote &votes[], int voteCount);
    
    // Agreement/disagreement calculation
    double CalculateAgreementLevel(const SEnhancedEnsembleVote &vote, 
                                  SEnhancedEnsembleVote &allVotes[], int voteCount);
    double CalculateDisagreementLevel(const SEnhancedEnsembleVote &vote, 
                                     SEnhancedEnsembleVote &allVotes[], int voteCount);
    
    // Regime matching helpers
    double CalculateRegimeMatchScore(ENUM_MARKET_REGIME preferred, ENUM_MARKET_REGIME current);
    void ApplyRegimeBonus(SEnhancedEnsembleVote &vote, double matchScore);
    
    // Statistical functions
    void UpdateVotingStatistics(const SEnsembleDecision &decision);
    double CalculateWeightedAverage(SEnhancedEnsembleVote &votes[], int voteCount);
    
    // Logging
    void LogVotingEvent(const ENUM_ERROR_LEVEL level, const string message);
};

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CEnhancedEnsembleVotingSystem::CEnhancedEnsembleVotingSystem(void) :
    m_totalDecisions(0),
    m_unanimousDecisions(0),
    m_tieBreakingDecisions(0),
    m_averageConsensus(0.0),
    m_decisionIndex(0),
    m_decisionCount(0),
    m_currentRegime(MARKET_REGIME_UNKNOWN),
    m_regimeConfidence(0.0),
    m_initialized(false)
{
    InitializeDefaultConfig();
    
    // Initialize decision history
    for(int i = 0; i < 100; i++)
    {
        m_decisions[i].finalSignal = TRADE_SIGNAL_NONE;
        m_decisions[i].finalConfidence = 0.0;
        m_decisions[i].consensusLevel = 0.0;
        m_decisions[i].totalVotes = 0;
        m_decisions[i].buyVotes = 0;
        m_decisions[i].sellVotes = 0;
        m_decisions[i].neutralVotes = 0;
        m_decisions[i].averageConfidence = 0.0;
        m_decisions[i].weightedConfidence = 0.0;
        m_decisions[i].tieBreakingReason = "";
        m_decisions[i].consensusAnalysis = "";
        m_decisions[i].decisionTime = 0;
        m_decisions[i].wasUnanimous = false;
        m_decisions[i].requiredTieBreaking = false;
    }
    
    // Initialize last decision
    m_lastDecision = m_decisions[0];
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CEnhancedEnsembleVotingSystem::~CEnhancedEnsembleVotingSystem(void)
{
    if(m_initialized)
    {
        PrintVotingReport();
        LogVotingEvent(ERROR_LEVEL_INFO, "Enhanced Ensemble Voting System destroyed");
    }
}

//+------------------------------------------------------------------+
//| Initialize Voting System                                       |
//+------------------------------------------------------------------+
bool CEnhancedEnsembleVotingSystem::Initialize(const SVotingConfig &config)
{
    m_config = config;
    
    // Validate configuration
    if(m_config.minConfidenceThreshold < 0.0 || m_config.minConfidenceThreshold > 1.0)
    {
        LogVotingEvent(ERROR_LEVEL_ERROR, "Invalid minimum confidence threshold");
        return false;
    }
    
    if(m_config.consensusThreshold < 0.5 || m_config.consensusThreshold > 1.0)
    {
        LogVotingEvent(ERROR_LEVEL_ERROR, "Invalid consensus threshold");
        return false;
    }
    
    m_initialized = true;
    
    LogVotingEvent(ERROR_LEVEL_INFO, 
                  StringFormat("Enhanced Ensemble Voting System initialized - Min Confidence: %.2f, Consensus: %.2f", 
                              m_config.minConfidenceThreshold, m_config.consensusThreshold));
    
    return true;
}

//+------------------------------------------------------------------+
//| Set Default Configuration                                      |
//+------------------------------------------------------------------+
void CEnhancedEnsembleVotingSystem::SetDefaultConfiguration(void)
{
    SVotingConfig defaultConfig;
    defaultConfig.minConfidenceThreshold = 0.3;
    defaultConfig.consensusThreshold = 0.6;
    defaultConfig.agreementBonusMultiplier = 1.2;
    defaultConfig.disagreementPenaltyFactor = 0.8;
    defaultConfig.useConfidenceWeighting = true;
    defaultConfig.usePerformanceWeighting = true;
    defaultConfig.enableAgreementBonus = true;
    defaultConfig.enableDisagreementPenalty = true;
    defaultConfig.enableRegimeMatching = true;
    defaultConfig.maxVotingStrategies = 10;
    defaultConfig.tieBreakingConfidenceBoost = 0.1;
    
    Initialize(defaultConfig);
}//
+------------------------------------------------------------------+
//| Process Ensemble Voting                                        |
//+------------------------------------------------------------------+
SEnsembleDecision CEnhancedEnsembleVotingSystem::ProcessEnsembleVoting(SEnhancedEnsembleVote &votes[], int voteCount)
{
    SEnsembleDecision decision;
    decision.finalSignal = TRADE_SIGNAL_NONE;
    decision.finalConfidence = 0.0;
    decision.decisionTime = TimeCurrent();
    
    if(!m_initialized || voteCount == 0)
    {
        decision.consensusAnalysis = "No votes or system not initialized";
        return decision;
    }
    
    // Validate and filter votes
    if(!ValidateVotes(votes, voteCount))
    {
        decision.consensusAnalysis = "Vote validation failed";
        return decision;
    }
    
    FilterValidVotes(votes, voteCount);
    
    if(voteCount == 0)
    {
        decision.consensusAnalysis = "No valid votes after filtering";
        return decision;
    }
    
    // Preprocess votes (apply bonuses, penalties, regime matching)
    PreprocessVotes(votes, voteCount);
    
    // Process voting based on configuration
    if(m_config.useConfidenceWeighting)
    {
        decision = ProcessConfidenceWeightedVoting(votes, voteCount);
    }
    else
    {
        decision = ProcessWeightedVoting(votes, voteCount);
    }
    
    // Record and return decision
    RecordDecision(decision);
    m_lastDecision = decision;
    
    LogEnsembleDecision(decision);
    
    return decision;
}

//+------------------------------------------------------------------+
//| Get Ensemble Signal (Simplified Interface)                    |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnhancedEnsembleVotingSystem::GetEnsembleSignal(SEnhancedEnsembleVote &votes[], int voteCount, double &confidence)
{
    SEnsembleDecision decision = ProcessEnsembleVoting(votes, voteCount);
    confidence = decision.finalConfidence;
    return decision.finalSignal;
}

//+------------------------------------------------------------------+
//| Preprocess Votes                                              |
//+------------------------------------------------------------------+
void CEnhancedEnsembleVotingSystem::PreprocessVotes(SEnhancedEnsembleVote &votes[], int voteCount)
{
    if(!m_initialized) return;
    
    // Apply agreement bonuses
    if(m_config.enableAgreementBonus)
    {
        CalculateAgreementBonuses(votes, voteCount);
    }
    
    // Apply disagreement penalties
    if(m_config.enableDisagreementPenalty)
    {
        ApplyDisagreementPenalties(votes, voteCount);
    }
    
    // Apply regime matching
    if(m_config.enableRegimeMatching)
    {
        ApplyRegimeMatching(votes, voteCount);
    }
}

//+------------------------------------------------------------------+
//| Calculate Agreement Bonuses                                    |
//+------------------------------------------------------------------+
void CEnhancedEnsembleVotingSystem::CalculateAgreementBonuses(SEnhancedEnsembleVote &votes[], int voteCount)
{
    for(int i = 0; i < voteCount; i++)
    {
        double agreementLevel = CalculateAgreementLevel(votes[i], votes, voteCount);
        votes[i].agreementBonus = agreementLevel * (m_config.agreementBonusMultiplier - 1.0);
        
        // Apply bonus to effective weight
        votes[i].weight *= (1.0 + votes[i].agreementBonus);
    }
}

//+------------------------------------------------------------------+
//| Apply Disagreement Penalties                                  |
//+------------------------------------------------------------------+
void CEnhancedEnsembleVotingSystem::ApplyDisagreementPenalties(SEnhancedEnsembleVote &votes[], int voteCount)
{
    for(int i = 0; i < voteCount; i++)
    {
        double disagreementLevel = CalculateDisagreementLevel(votes[i], votes, voteCount);
        votes[i].disagreementPenalty = disagreementLevel * (1.0 - m_config.disagreementPenaltyFactor);
        
        // Apply penalty to effective weight
        votes[i].weight *= (1.0 - votes[i].disagreementPenalty);
        
        // Ensure weight doesn't go below minimum
        if(votes[i].weight < 0.1) votes[i].weight = 0.1;
    }
}

//+------------------------------------------------------------------+
//| Apply Regime Matching                                         |
//+------------------------------------------------------------------+
void CEnhancedEnsembleVotingSystem::ApplyRegimeMatching(SEnhancedEnsembleVote &votes[], int voteCount)
{
    for(int i = 0; i < voteCount; i++)
    {
        double matchScore = CalculateRegimeMatchScore(votes[i].preferredRegime, m_currentRegime);
        votes[i].regimeMatch = matchScore;
        
        ApplyRegimeBonus(votes[i], matchScore);
    }
}

//+------------------------------------------------------------------+
//| Process Weighted Voting                                        |
//+------------------------------------------------------------------+
SEnsembleDecision CEnhancedEnsembleVotingSystem::ProcessWeightedVoting(SEnhancedEnsembleVote &votes[], int voteCount)
{
    SEnsembleDecision decision;
    decision.totalVotes = voteCount;
    decision.buyVotes = 0;
    decision.sellVotes = 0;
    decision.neutralVotes = 0;
    decision.decisionTime = TimeCurrent();
    
    double buyWeight = 0.0;
    double sellWeight = 0.0;
    double totalWeight = 0.0;
    double totalConfidence = 0.0;
    
    // Calculate weighted votes
    for(int i = 0; i < voteCount; i++)
    {
        double effectiveWeight = CalculateEffectiveWeight(votes[i]);
        
        if(votes[i].signal == TRADE_SIGNAL_BUY)
        {
            buyWeight += effectiveWeight;
            decision.buyVotes++;
        }
        else if(votes[i].signal == TRADE_SIGNAL_SELL)
        {
            sellWeight += effectiveWeight;
            decision.sellVotes++;
        }
        else
        {
            decision.neutralVotes++;
        }
        
        totalWeight += effectiveWeight;
        totalConfidence += votes[i].confidence * effectiveWeight;
    }
    
    // Calculate averages
    decision.averageConfidence = (voteCount > 0) ? totalConfidence / totalWeight : 0.0;
    decision.weightedConfidence = decision.averageConfidence;
    
    // Determine final signal
    if(totalWeight == 0.0)
    {
        decision.finalSignal = TRADE_SIGNAL_NONE;
        decision.finalConfidence = 0.0;
        decision.consensusLevel = 0.0;
        decision.consensusAnalysis = "No effective weight";
        return decision;
    }
    
    double buyConsensus = buyWeight / totalWeight;
    double sellConsensus = sellWeight / totalWeight;
    
    // Check for consensus
    if(buyConsensus >= m_config.consensusThreshold)
    {
        decision.finalSignal = TRADE_SIGNAL_BUY;
        decision.finalConfidence = decision.weightedConfidence;
        decision.consensusLevel = buyConsensus;
        decision.wasUnanimous = IsUnanimousDecision(votes, voteCount, TRADE_SIGNAL_BUY);
    }
    else if(sellConsensus >= m_config.consensusThreshold)
    {
        decision.finalSignal = TRADE_SIGNAL_SELL;
        decision.finalConfidence = decision.weightedConfidence;
        decision.consensusLevel = sellConsensus;
        decision.wasUnanimous = IsUnanimousDecision(votes, voteCount, TRADE_SIGNAL_SELL);
    }
    else
    {
        // No consensus - use tie-breaking
        string tieReason;
        decision.finalSignal = ResolveTieBreaking(votes, voteCount, decision.finalConfidence, tieReason);
        decision.tieBreakingReason = tieReason;
        decision.requiredTieBreaking = true;
        decision.consensusLevel = MathMax(buyConsensus, sellConsensus);
    }
    
    decision.consensusAnalysis = AnalyzeConsensus(votes, voteCount, decision.finalSignal);
    
    return decision;
}

//+------------------------------------------------------------------+
//| Process Confidence-Weighted Voting                            |
//+------------------------------------------------------------------+
SEnsembleDecision CEnhancedEnsembleVotingSystem::ProcessConfidenceWeightedVoting(SEnhancedEnsembleVote &votes[], int voteCount)
{
    SEnsembleDecision decision;
    decision.totalVotes = voteCount;
    decision.buyVotes = 0;
    decision.sellVotes = 0;
    decision.neutralVotes = 0;
    decision.decisionTime = TimeCurrent();
    
    double buyScore = 0.0;
    double sellScore = 0.0;
    double totalScore = 0.0;
    double confidenceSum = 0.0;
    
    // Calculate confidence-adjusted scores
    for(int i = 0; i < voteCount; i++)
    {
        double adjustedWeight = CalculateConfidenceAdjustedWeight(votes[i]);
        double voteStrength = CalculateVoteStrength(votes[i]);
        
        if(votes[i].signal == TRADE_SIGNAL_BUY)
        {
            buyScore += adjustedWeight * voteStrength;
            decision.buyVotes++;
        }
        else if(votes[i].signal == TRADE_SIGNAL_SELL)
        {
            sellScore += adjustedWeight * voteStrength;
            decision.sellVotes++;
        }
        else
        {
            decision.neutralVotes++;
        }
        
        totalScore += adjustedWeight;
        confidenceSum += votes[i].confidence;
    }
    
    // Calculate metrics
    decision.averageConfidence = (voteCount > 0) ? confidenceSum / voteCount : 0.0;
    decision.weightedConfidence = (totalScore > 0.0) ? (buyScore + sellScore) / totalScore : 0.0;
    
    // Determine final signal
    if(totalScore == 0.0)
    {
        decision.finalSignal = TRADE_SIGNAL_NONE;
        decision.finalConfidence = 0.0;
        decision.consensusLevel = 0.0;
        decision.consensusAnalysis = "No effective score";
        return decision;
    }
    
    double buyRatio = buyScore / totalScore;
    double sellRatio = sellScore / totalScore;
    
    // Apply consensus threshold
    if(buyRatio >= m_config.consensusThreshold)
    {
        decision.finalSignal = TRADE_SIGNAL_BUY;
        decision.finalConfidence = buyRatio * decision.averageConfidence;
        decision.consensusLevel = buyRatio;
        decision.wasUnanimous = IsUnanimousDecision(votes, voteCount, TRADE_SIGNAL_BUY);
    }
    else if(sellRatio >= m_config.consensusThreshold)
    {
        decision.finalSignal = TRADE_SIGNAL_SELL;
        decision.finalConfidence = sellRatio * decision.averageConfidence;
        decision.consensusLevel = sellRatio;
        decision.wasUnanimous = IsUnanimousDecision(votes, voteCount, TRADE_SIGNAL_SELL);
    }
    else
    {
        // Use tie-breaking
        string tieReason;
        decision.finalSignal = ResolveTieBreaking(votes, voteCount, decision.finalConfidence, tieReason);
        decision.tieBreakingReason = tieReason;
        decision.requiredTieBreaking = true;
        decision.consensusLevel = MathMax(buyRatio, sellRatio);
        
        // Apply tie-breaking confidence boost
        decision.finalConfidence += m_config.tieBreakingConfidenceBoost;
        decision.finalConfidence = MathMin(1.0, decision.finalConfidence);
    }
    
    decision.consensusAnalysis = AnalyzeConsensus(votes, voteCount, decision.finalSignal);
    
    return decision;
}

//+------------------------------------------------------------------+
//| Calculate Effective Weight                                     |
//+------------------------------------------------------------------+
double CEnhancedEnsembleVotingSystem::CalculateEffectiveWeight(const SEnhancedEnsembleVote &vote)
{
    double effectiveWeight = vote.weight;
    
    // Apply performance weighting if enabled
    if(m_config.usePerformanceWeighting)
    {
        effectiveWeight *= (0.5 + vote.performanceScore * 0.5); // 0.5 to 1.0 multiplier
    }
    
    // Apply regime matching
    if(m_config.enableRegimeMatching)
    {
        effectiveWeight *= (0.7 + vote.regimeMatch * 0.3); // 0.7 to 1.0 multiplier
    }
    
    return MathMax(0.1, effectiveWeight);
}

//+------------------------------------------------------------------+
//| Calculate Vote Strength                                        |
//+------------------------------------------------------------------+
double CEnhancedEnsembleVotingSystem::CalculateVoteStrength(const SEnhancedEnsembleVote &vote)
{
    // Combine confidence with other factors
    double strength = vote.confidence;
    
    // Boost for high performance
    if(vote.performanceScore > 0.7)
        strength *= 1.1;
    
    // Boost for regime match
    if(vote.regimeMatch > 0.8)
        strength *= 1.05;
    
    return MathMin(1.0, strength);
}

//+------------------------------------------------------------------+
//| Calculate Confidence-Adjusted Weight                          |
//+------------------------------------------------------------------+
double CEnhancedEnsembleVotingSystem::CalculateConfidenceAdjustedWeight(const SEnhancedEnsembleVote &vote)
{
    double baseWeight = CalculateEffectiveWeight(vote);
    
    // Adjust by confidence level
    double confidenceMultiplier = 0.5 + (vote.confidence * 0.5); // 0.5 to 1.0 range
    
    return baseWeight * confidenceMultiplier;
}

//+------------------------------------------------------------------+
//| Resolve Tie-Breaking                                          |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnhancedEnsembleVotingSystem::ResolveTieBreaking(SEnhancedEnsembleVote &votes[], int voteCount, 
                                                                   double &confidence, string &reason)
{
    // Try highest confidence tie-breaker first
    ENUM_TRADE_SIGNAL signal = HighestConfidenceTieBreaker(votes, voteCount, confidence);
    if(signal != TRADE_SIGNAL_NONE)
    {
        reason = "Highest confidence tie-breaker";
        return signal;
    }
    
    // Try performance-based tie-breaker
    signal = PerformanceBasedTieBreaker(votes, voteCount, confidence);
    if(signal != TRADE_SIGNAL_NONE)
    {
        reason = "Performance-based tie-breaker";
        return signal;
    }
    
    // Try regime preference tie-breaker
    signal = RegimePreferenceTieBreaker(votes, voteCount, confidence);
    if(signal != TRADE_SIGNAL_NONE)
    {
        reason = "Regime preference tie-breaker";
        return signal;
    }
    
    // Default to no signal
    confidence = 0.0;
    reason = "No tie-breaking resolution possible";
    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Highest Confidence Tie-Breaker                               |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnhancedEnsembleVotingSystem::HighestConfidenceTieBreaker(SEnhancedEnsembleVote &votes[], int voteCount, 
                                                                            double &confidence)
{
    double maxConfidence = 0.0;
    ENUM_TRADE_SIGNAL bestSignal = TRADE_SIGNAL_NONE;
    
    for(int i = 0; i < voteCount; i++)
    {
        if(votes[i].confidence > maxConfidence && votes[i].signal != TRADE_SIGNAL_NONE)
        {
            maxConfidence = votes[i].confidence;
            bestSignal = votes[i].signal;
        }
    }
    
    // Only use if confidence is significantly high
    if(maxConfidence >= 0.7)
    {
        confidence = maxConfidence;
        return bestSignal;
    }
    
    confidence = 0.0;
    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Performance-Based Tie-Breaker                                |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnhancedEnsembleVotingSystem::PerformanceBasedTieBreaker(SEnhancedEnsembleVote &votes[], int voteCount, 
                                                                           double &confidence)
{
    double maxPerformance = 0.0;
    ENUM_TRADE_SIGNAL bestSignal = TRADE_SIGNAL_NONE;
    double bestConfidence = 0.0;
    
    for(int i = 0; i < voteCount; i++)
    {
        if(votes[i].performanceScore > maxPerformance && votes[i].signal != TRADE_SIGNAL_NONE)
        {
            maxPerformance = votes[i].performanceScore;
            bestSignal = votes[i].signal;
            bestConfidence = votes[i].confidence;
        }
    }
    
    // Only use if performance is significantly high
    if(maxPerformance >= 0.6)
    {
        confidence = bestConfidence * maxPerformance; // Adjust confidence by performance
        return bestSignal;
    }
    
    confidence = 0.0;
    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Regime Preference Tie-Breaker                                |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CEnhancedEnsembleVotingSystem::RegimePreferenceTieBreaker(SEnhancedEnsembleVote &votes[], int voteCount, 
                                                                           double &confidence)
{
    double maxRegimeMatch = 0.0;
    ENUM_TRADE_SIGNAL bestSignal = TRADE_SIGNAL_NONE;
    double bestConfidence = 0.0;
    
    for(int i = 0; i < voteCount; i++)
    {
        if(votes[i].regimeMatch > maxRegimeMatch && votes[i].signal != TRADE_SIGNAL_NONE)
        {
            maxRegimeMatch = votes[i].regimeMatch;
            bestSignal = votes[i].signal;
            bestConfidence = votes[i].confidence;
        }
    }
    
    // Only use if regime match is good
    if(maxRegimeMatch >= 0.7)
    {
        confidence = bestConfidence * maxRegimeMatch; // Adjust confidence by regime match
        return bestSignal;
    }
    
    confidence = 0.0;
    return TRADE_SIGNAL_NONE;
}/
/+------------------------------------------------------------------+
//| Consensus Analysis Functions                                   |
//+------------------------------------------------------------------+
double CEnhancedEnsembleVotingSystem::CalculateConsensusLevel(SEnhancedEnsembleVote &votes[], int voteCount, ENUM_TRADE_SIGNAL signal)
{
    if(voteCount == 0) return 0.0;
    
    int agreementCount = 0;
    double totalWeight = 0.0;
    double agreementWeight = 0.0;
    
    for(int i = 0; i < voteCount; i++)
    {
        double effectiveWeight = CalculateEffectiveWeight(votes[i]);
        totalWeight += effectiveWeight;
        
        if(votes[i].signal == signal)
        {
            agreementCount++;
            agreementWeight += effectiveWeight;
        }
    }
    
    return (totalWeight > 0.0) ? agreementWeight / totalWeight : 0.0;
}

bool CEnhancedEnsembleVotingSystem::IsUnanimousDecision(SEnhancedEnsembleVote &votes[], int voteCount, ENUM_TRADE_SIGNAL signal)
{
    if(voteCount == 0) return false;
    
    for(int i = 0; i < voteCount; i++)
    {
        if(votes[i].signal != signal && votes[i].signal != TRADE_SIGNAL_NONE)
            return false;
    }
    
    return true;
}

string CEnhancedEnsembleVotingSystem::AnalyzeConsensus(SEnhancedEnsembleVote &votes[], int voteCount, ENUM_TRADE_SIGNAL signal)
{
    if(voteCount == 0) return "No votes to analyze";
    
    double consensusLevel = CalculateConsensusLevel(votes, voteCount, signal);
    bool isUnanimous = IsUnanimousDecision(votes, voteCount, signal);
    
    string analysis = "";
    
    if(isUnanimous)
    {
        analysis = "UNANIMOUS decision";
    }
    else if(consensusLevel >= 0.8)
    {
        analysis = "STRONG consensus";
    }
    else if(consensusLevel >= 0.6)
    {
        analysis = "MODERATE consensus";
    }
    else if(consensusLevel >= 0.4)
    {
        analysis = "WEAK consensus";
    }
    else
    {
        analysis = "NO consensus";
    }
    
    analysis += StringFormat(" (%.1f%% agreement)", consensusLevel * 100);
    
    return analysis;
}

//+------------------------------------------------------------------+
//| Decision Tracking Functions                                    |
//+------------------------------------------------------------------+
void CEnhancedEnsembleVotingSystem::RecordDecision(const SEnsembleDecision &decision)
{
    // Store in circular buffer
    m_decisions[m_decisionIndex] = decision;
    m_decisionIndex = (m_decisionIndex + 1) % 100;
    
    if(m_decisionCount < 100)
        m_decisionCount++;
    
    // Update statistics
    UpdateVotingStatistics(decision);
}

double CEnhancedEnsembleVotingSystem::GetAverageConsensus(void)
{
    if(m_decisionCount == 0) return 0.0;
    
    double totalConsensus = 0.0;
    for(int i = 0; i < m_decisionCount; i++)
    {
        totalConsensus += m_decisions[i].consensusLevel;
    }
    
    return totalConsensus / m_decisionCount;
}

double CEnhancedEnsembleVotingSystem::GetUnanimousDecisionRate(void)
{
    if(m_totalDecisions == 0) return 0.0;
    return (double)m_unanimousDecisions / m_totalDecisions;
}

double CEnhancedEnsembleVotingSystem::GetTieBreakingRate(void)
{
    if(m_totalDecisions == 0) return 0.0;
    return (double)m_tieBreakingDecisions / m_totalDecisions;
}

//+------------------------------------------------------------------+
//| Configuration Functions                                        |
//+------------------------------------------------------------------+
void CEnhancedEnsembleVotingSystem::SetMinConfidenceThreshold(const double threshold)
{
    if(threshold >= 0.0 && threshold <= 1.0)
    {
        m_config.minConfidenceThreshold = threshold;
        LogVotingEvent(ERROR_LEVEL_INFO, 
                      StringFormat("Min confidence threshold updated: %.2f", threshold));
    }
}

void CEnhancedEnsembleVotingSystem::SetConsensusThreshold(const double threshold)
{
    if(threshold >= 0.5 && threshold <= 1.0)
    {
        m_config.consensusThreshold = threshold;
        LogVotingEvent(ERROR_LEVEL_INFO, 
                      StringFormat("Consensus threshold updated: %.2f", threshold));
    }
}

void CEnhancedEnsembleVotingSystem::SetCurrentRegime(ENUM_MARKET_REGIME regime, double confidence)
{
    m_currentRegime = regime;
    m_regimeConfidence = confidence;
    
    LogVotingEvent(ERROR_LEVEL_INFO, 
                  StringFormat("Market regime updated: %s (Confidence: %.2f)", 
                              EnumToString(regime), confidence));
}

//+------------------------------------------------------------------+
//| Information and Reporting Functions                           |
//+------------------------------------------------------------------+
string CEnhancedEnsembleVotingSystem::GetVotingSummary(SEnhancedEnsembleVote &votes[], int voteCount)
{
    if(voteCount == 0) return "No votes";
    
    int buyCount = 0, sellCount = 0, neutralCount = 0;
    double totalConfidence = 0.0;
    double totalWeight = 0.0;
    
    for(int i = 0; i < voteCount; i++)
    {
        if(votes[i].signal == TRADE_SIGNAL_BUY) buyCount++;
        else if(votes[i].signal == TRADE_SIGNAL_SELL) sellCount++;
        else neutralCount++;
        
        totalConfidence += votes[i].confidence;
        totalWeight += votes[i].weight;
    }
    
    double avgConfidence = totalConfidence / voteCount;
    
    return StringFormat("Votes: BUY=%d, SELL=%d, NEUTRAL=%d | Avg Confidence: %.2f | Total Weight: %.2f",
                       buyCount, sellCount, neutralCount, avgConfidence, totalWeight);
}

string CEnhancedEnsembleVotingSystem::GetDecisionSummary(const SEnsembleDecision &decision)
{
    string signal = (decision.finalSignal == TRADE_SIGNAL_BUY) ? "BUY" : 
                   (decision.finalSignal == TRADE_SIGNAL_SELL) ? "SELL" : "NONE";
    
    return StringFormat("Decision: %s | Confidence: %.2f | Consensus: %.1f%% | %s | Tie-Breaking: %s",
                       signal, decision.finalConfidence, decision.consensusLevel * 100,
                       decision.consensusAnalysis, decision.requiredTieBreaking ? "YES" : "NO");
}

void CEnhancedEnsembleVotingSystem::PrintVotingReport(void)
{
    if(!m_initialized) return;
    
    Print("\n=== ENHANCED ENSEMBLE VOTING SYSTEM REPORT ===");
    Print("📊 VOTING STATISTICS:");
    Print("   Total Decisions: ", m_totalDecisions);
    Print("   Unanimous Decisions: ", m_unanimousDecisions, " (", DoubleToString(GetUnanimousDecisionRate() * 100, 1), "%)");
    Print("   Tie-Breaking Decisions: ", m_tieBreakingDecisions, " (", DoubleToString(GetTieBreakingRate() * 100, 1), "%)");
    Print("   Average Consensus: ", DoubleToString(GetAverageConsensus() * 100, 1), "%");
    
    Print("\n⚙️ CONFIGURATION:");
    Print("   Min Confidence Threshold: ", DoubleToString(m_config.minConfidenceThreshold, 2));
    Print("   Consensus Threshold: ", DoubleToString(m_config.consensusThreshold, 2));
    Print("   Agreement Bonus Multiplier: ", DoubleToString(m_config.agreementBonusMultiplier, 2));
    Print("   Disagreement Penalty Factor: ", DoubleToString(m_config.disagreementPenaltyFactor, 2));
    Print("   Use Confidence Weighting: ", m_config.useConfidenceWeighting ? "YES" : "NO");
    Print("   Use Performance Weighting: ", m_config.usePerformanceWeighting ? "YES" : "NO");
    Print("   Enable Agreement Bonus: ", m_config.enableAgreementBonus ? "YES" : "NO");
    Print("   Enable Disagreement Penalty: ", m_config.enableDisagreementPenalty ? "YES" : "NO");
    Print("   Enable Regime Matching: ", m_config.enableRegimeMatching ? "YES" : "NO");
    
    Print("\n🎯 LAST DECISION:");
    if(m_lastDecision.totalVotes > 0)
    {
        Print("   ", GetDecisionSummary(m_lastDecision));
        if(StringLen(m_lastDecision.tieBreakingReason) > 0)
        {
            Print("   Tie-Breaking Reason: ", m_lastDecision.tieBreakingReason);
        }
    }
    else
    {
        Print("   No decisions recorded");
    }
    
    Print("===============================================\n");
}

void CEnhancedEnsembleVotingSystem::LogEnsembleDecision(const SEnsembleDecision &decision)
{
    string message = StringFormat("Ensemble Decision: %s", GetDecisionSummary(decision));
    LogVotingEvent(ERROR_LEVEL_INFO, message);
    
    if(decision.requiredTieBreaking)
    {
        LogVotingEvent(ERROR_LEVEL_INFO, "Tie-breaking used: " + decision.tieBreakingReason);
    }
}

//+------------------------------------------------------------------+
//| Validation Functions                                           |
//+------------------------------------------------------------------+
bool CEnhancedEnsembleVotingSystem::ValidateVote(const SEnhancedEnsembleVote &vote)
{
    if(StringLen(vote.strategyName) == 0) return false;
    if(vote.confidence < 0.0 || vote.confidence > 1.0) return false;
    if(vote.weight < 0.0) return false;
    if(vote.performanceScore < 0.0 || vote.performanceScore > 1.0) return false;
    
    return true;
}

bool CEnhancedEnsembleVotingSystem::ValidateVotes(SEnhancedEnsembleVote &votes[], int voteCount)
{
    if(voteCount <= 0 || voteCount > m_config.maxVotingStrategies) return false;
    
    for(int i = 0; i < voteCount; i++)
    {
        if(!ValidateVote(votes[i])) return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Internal Helper Functions                                      |
//+------------------------------------------------------------------+
void CEnhancedEnsembleVotingSystem::InitializeDefaultConfig(void)
{
    m_config.minConfidenceThreshold = 0.3;
    m_config.consensusThreshold = 0.6;
    m_config.agreementBonusMultiplier = 1.2;
    m_config.disagreementPenaltyFactor = 0.8;
    m_config.useConfidenceWeighting = true;
    m_config.usePerformanceWeighting = true;
    m_config.enableAgreementBonus = true;
    m_config.enableDisagreementPenalty = true;
    m_config.enableRegimeMatching = true;
    m_config.maxVotingStrategies = 10;
    m_config.tieBreakingConfidenceBoost = 0.1;
}

void CEnhancedEnsembleVotingSystem::FilterValidVotes(SEnhancedEnsembleVote &votes[], int &voteCount)
{
    int validCount = 0;
    
    for(int i = 0; i < voteCount; i++)
    {
        if(votes[i].isValid && 
           votes[i].confidence >= m_config.minConfidenceThreshold &&
           votes[i].signal != TRADE_SIGNAL_NONE)
        {
            if(validCount != i)
            {
                votes[validCount] = votes[i];
            }
            validCount++;
        }
    }
    
    voteCount = validCount;
}

void CEnhancedEnsembleVotingSystem::SortVotesByConfidence(SEnhancedEnsembleVote &votes[], int voteCount)
{
    // Simple bubble sort by confidence (descending)
    for(int i = 0; i < voteCount - 1; i++)
    {
        for(int j = 0; j < voteCount - i - 1; j++)
        {
            if(votes[j].confidence < votes[j + 1].confidence)
            {
                SEnhancedEnsembleVote temp = votes[j];
                votes[j] = votes[j + 1];
                votes[j + 1] = temp;
            }
        }
    }
}

void CEnhancedEnsembleVotingSystem::SortVotesByPerformance(SEnhancedEnsembleVote &votes[], int voteCount)
{
    // Simple bubble sort by performance (descending)
    for(int i = 0; i < voteCount - 1; i++)
    {
        for(int j = 0; j < voteCount - i - 1; j++)
        {
            if(votes[j].performanceScore < votes[j + 1].performanceScore)
            {
                SEnhancedEnsembleVote temp = votes[j];
                votes[j] = votes[j + 1];
                votes[j + 1] = temp;
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Agreement/Disagreement Calculation                            |
//+------------------------------------------------------------------+
double CEnhancedEnsembleVotingSystem::CalculateAgreementLevel(const SEnhancedEnsembleVote &vote, 
                                                             SEnhancedEnsembleVote &allVotes[], int voteCount)
{
    if(voteCount <= 1) return 0.0;
    
    int agreementCount = 0;
    double totalWeight = 0.0;
    double agreementWeight = 0.0;
    
    for(int i = 0; i < voteCount; i++)
    {
        if(allVotes[i].strategyName == vote.strategyName) continue; // Skip self
        
        totalWeight += allVotes[i].weight;
        
        if(allVotes[i].signal == vote.signal)
        {
            agreementCount++;
            agreementWeight += allVotes[i].weight;
        }
    }
    
    return (totalWeight > 0.0) ? agreementWeight / totalWeight : 0.0;
}

double CEnhancedEnsembleVotingSystem::CalculateDisagreementLevel(const SEnhancedEnsembleVote &vote, 
                                                                SEnhancedEnsembleVote &allVotes[], int voteCount)
{
    return 1.0 - CalculateAgreementLevel(vote, allVotes, voteCount);
}

//+------------------------------------------------------------------+
//| Regime Matching Helpers                                       |
//+------------------------------------------------------------------+
double CEnhancedEnsembleVotingSystem::CalculateRegimeMatchScore(ENUM_MARKET_REGIME preferred, ENUM_MARKET_REGIME current)
{
    if(preferred == current) return 1.0;
    
    // Partial matches for related regimes
    if((preferred == MARKET_REGIME_TRENDING && current == MARKET_REGIME_VOLATILE) ||
       (preferred == MARKET_REGIME_VOLATILE && current == MARKET_REGIME_TRENDING))
        return 0.7;
    
    if((preferred == MARKET_REGIME_RANGING && current == MARKET_REGIME_QUIET) ||
       (preferred == MARKET_REGIME_QUIET && current == MARKET_REGIME_RANGING))
        return 0.7;
    
    // Default partial match
    return 0.5;
}

void CEnhancedEnsembleVotingSystem::ApplyRegimeBonus(SEnhancedEnsembleVote &vote, double matchScore)
{
    if(matchScore > 0.8)
    {
        vote.weight *= 1.1; // 10% bonus for good regime match
    }
    else if(matchScore < 0.3)
    {
        vote.weight *= 0.9; // 10% penalty for poor regime match
    }
}

//+------------------------------------------------------------------+
//| Statistical Functions                                         |
//+------------------------------------------------------------------+
void CEnhancedEnsembleVotingSystem::UpdateVotingStatistics(const SEnsembleDecision &decision)
{
    m_totalDecisions++;
    
    if(decision.wasUnanimous)
        m_unanimousDecisions++;
    
    if(decision.requiredTieBreaking)
        m_tieBreakingDecisions++;
    
    // Update running average consensus
    m_averageConsensus = ((m_averageConsensus * (m_totalDecisions - 1)) + decision.consensusLevel) / m_totalDecisions;
}

double CEnhancedEnsembleVotingSystem::CalculateWeightedAverage(SEnhancedEnsembleVote &votes[], int voteCount)
{
    if(voteCount == 0) return 0.0;
    
    double weightedSum = 0.0;
    double totalWeight = 0.0;
    
    for(int i = 0; i < voteCount; i++)
    {
        double effectiveWeight = CalculateEffectiveWeight(votes[i]);
        weightedSum += votes[i].confidence * effectiveWeight;
        totalWeight += effectiveWeight;
    }
    
    return (totalWeight > 0.0) ? weightedSum / totalWeight : 0.0;
}

//+------------------------------------------------------------------+
//| Logging Function                                               |
//+------------------------------------------------------------------+
void CEnhancedEnsembleVotingSystem::LogVotingEvent(const ENUM_ERROR_LEVEL level, const string message)
{
    string prefix = "";
    switch(level)
    {
        case ERROR_LEVEL_INFO:    prefix = "[ENSEMBLE-INFO] "; break;
        case ERROR_LEVEL_WARNING: prefix = "[ENSEMBLE-WARN] "; break;
        case ERROR_LEVEL_ERROR:   prefix = "[ENSEMBLE-ERROR] "; break;
        default:                  prefix = "[ENSEMBLE] "; break;
    }
    
    Print(prefix + message);
}

#endif // CORE_ENHANCED_ENSEMBLE_VOTING_SYSTEM_MQH