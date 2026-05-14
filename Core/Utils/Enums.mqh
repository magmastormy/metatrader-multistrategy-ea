//+------------------------------------------------------------------+
//| Core Trading Enums and Constants                                |
//| Essential definitions for the Multi-Strategy EA                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_ENUMS_MQH
#define CORE_ENUMS_MQH

//+------------------------------------------------------------------+
//| Trading Signal Types                                            |
//+------------------------------------------------------------------+
enum ENUM_TRADE_SIGNAL
{
    TRADE_SIGNAL_NONE = 0,     // No signal
    TRADE_SIGNAL_BUY = 1,      // Buy signal
    TRADE_SIGNAL_SELL = -1     // Sell signal
};

//+------------------------------------------------------------------+
//| Trading Style Enumeration                                       |
//+------------------------------------------------------------------+
enum ENUM_TRADE_STYLE
{
    TRADE_SCALP = 0,           // Scalping style
    TRADE_SWING = 1,           // Swing trading
    TRADE_TREND = 2,           // Trend following
    TRADE_RANGE = 3            // Range trading
};

//+------------------------------------------------------------------+
//| Trading Mode Enumeration (Killer Scalper vs HTF Follower)       |
//+------------------------------------------------------------------+
enum ENUM_TRADING_MODE
{
    TRADING_MODE_NO_TRADE = 0,      // No trading allowed
    TRADING_MODE_KILLER_SCALPER = 1, // Ultra-fast, high frequency
    TRADING_MODE_HTF_FOLLOWER = 2    // Structural, trend following
};

//+------------------------------------------------------------------+
//| Market Regime Enumeration                                      |
//+------------------------------------------------------------------+
enum ENUM_MARKET_REGIME
{
    MARKET_REGIME_UNKNOWN = 0,     // Unknown regime
    MARKET_REGIME_TRENDING = 1,    // Trending market
    MARKET_REGIME_RANGING = 2,     // Ranging market
    MARKET_REGIME_VOLATILE = 3,    // Volatile market
    MARKET_REGIME_QUIET = 4        // Quiet market
};

//+------------------------------------------------------------------+
//| Strategy Tier Enumeration                                       |
//+------------------------------------------------------------------+
enum ENUM_STRATEGY_TIER
{
    STRATEGY_TIER_1 = 1,           // Top tier strategies
    STRATEGY_TIER_2 = 2,           // Mid tier strategies
    STRATEGY_TIER_3 = 3,           // Lower tier strategies
    STRATEGY_TIER_DISABLED = 0     // Disabled strategies
};

//+------------------------------------------------------------------+
//| Strategy Type Enumeration                                       |
//+------------------------------------------------------------------+
enum ENUM_STRATEGY_TYPE
{
    STRATEGY_MOMENTUM = 1,         // Momentum strategy
    STRATEGY_TREND = 2,            // Trend strategy
    STRATEGY_FIBONACCI = 3,        // Fibonacci strategy
    STRATEGY_ELLIOTT_WAVE = 4,     // Elliott Wave strategy
    STRATEGY_SUPPORT_RESISTANCE = 5, // Support/Resistance strategy
    STRATEGY_UNIFIED_ICT = 6,      // Unified ICT strategy
    STRATEGY_CANDLESTICK = 7,      // Candlestick strategy
    STRATEGY_CUSTOM = 99,          // Custom strategy
    STRATEGY_BRAIN = 100,          // Strategy brain type
    STRATEGY_AI_ENHANCED = 101     // AI enhanced strategy type
};

//+------------------------------------------------------------------+
//| EA Operating Mode Enumeration                                   |
//+------------------------------------------------------------------+
enum ENUM_EA_MODE
{
    EA_MODE_INDICATOR_ONLY = 1,   // Indicator-based strategies only
    EA_MODE_AI_ONLY = 2,          // AI strategies only
    EA_MODE_HYBRID = 3,           // Both indicators and AI
    EA_MODE_AI_ASSISTED = 4,      // AI assisted strategies
    EA_MODE_INDICATOR_FILTERED = 5 // Indicator filtered strategies
};

//+------------------------------------------------------------------+
//| Python bridge telemetry mode                                     |
//+------------------------------------------------------------------+
enum ENUM_PYTHON_BRIDGE_MODE
{
    PYTHON_BRIDGE_OFF = 0,        // No Python sidecar expectations
    PYTHON_BRIDGE_OBSERVE = 1,    // Log configured Python sidecar topology only
    PYTHON_BRIDGE_REQUIRED = 2    // Operator expects Python sidecar to be part of workflow
};

//+------------------------------------------------------------------+
//| Error Level Enumeration                                        |
//+------------------------------------------------------------------+
enum ENUM_ERROR_LEVEL
{
    ERROR_LEVEL_INFO = 0,         // Informational
    ERROR_LEVEL_WARNING = 1,      // Warning
    ERROR_LEVEL_ERROR = 2,        // Error
    ERROR_LEVEL_CRITICAL = 3      // Critical error
};


//+------------------------------------------------------------------+
//| Risk Management Enumeration                                     |
//+------------------------------------------------------------------+
enum ENUM_RISK_MODE
{
    RISK_MODE_FIXED = 1,           // Fixed lot size
    RISK_MODE_PERCENTAGE = 2,      // Percentage risk
    RISK_MODE_ADAPTIVE = 3         // Adaptive risk management
};

//+------------------------------------------------------------------+
//| Signal Evaluation Mode                                          |
//+------------------------------------------------------------------+
enum ENUM_SIGNAL_EVAL_MODE
{
    EVAL_MODE_NEW_BAR = 0,         // New bar evaluation
    EVAL_MODE_INTRABAR = 1         // Intrabar evaluation
};

//+------------------------------------------------------------------+
//| Validation Profile                                              |
//+------------------------------------------------------------------+
enum ENUM_VALIDATION_PROFILE
{
    VALIDATION_PROFILE_NEW_BAR = 0,     // New bar validation profile
    VALIDATION_PROFILE_INTRABAR = 1     // Intrabar validation profile
};

//+------------------------------------------------------------------+
//| Strategy Role Enumeration                                       |
//+------------------------------------------------------------------+
enum ENUM_STRATEGY_ROLE
{
    PRIMARY_ALPHA = 0,
    CONTEXT_FEATURE = 1,
    SHADOW_RESEARCH = 2
};

//+------------------------------------------------------------------+
//| Strategy Cluster Enumeration                                    |
//+------------------------------------------------------------------+
enum ENUM_STRATEGY_CLUSTER
{
    STRATEGY_CLUSTER_NONE = 0,
    TREND_CLUSTER = 1,
    MEAN_REVERSION_CLUSTER = 2,
    STRUCTURE_CLUSTER = 3
};

//+------------------------------------------------------------------+
//| Intrabar Policy Enumeration                                    |
//+------------------------------------------------------------------+
enum ENUM_INTRABAR_POLICY
{
    INTRABAR_POLICY_OFF = 0,
    INTRABAR_POLICY_PROBE = 1,
    INTRABAR_POLICY_LIVE = 2
};

//+------------------------------------------------------------------+
//| Consensus Decision Class Enumeration                           |
//+------------------------------------------------------------------+
enum ENUM_CONSENSUS_DECISION_CLASS
{
    CONSENSUS_DECISION_NONE = 0,
    CONSENSUS_DECISION_FULL_QUORUM = 1,
    CONSENSUS_DECISION_SPARSE_INTRABAR = 2,
    CONSENSUS_DECISION_VETOED = 3
};

//+------------------------------------------------------------------+
//| Risk Level Enumeration                                          |
//+------------------------------------------------------------------+
enum ENUM_RISK_LEVEL
{
    RISK_LEVEL_LOW = 0,
    RISK_LEVEL_MEDIUM = 1,
    RISK_LEVEL_HIGH = 2,
    RISK_LEVEL_CRITICAL = 3,
    RISK_LEVEL_EXTREME = 4
};

//+------------------------------------------------------------------+
//| Constants                                                       |
//+------------------------------------------------------------------+
#define MAX_STRATEGIES 150              // Maximum number of strategies (increased for multi-symbol support)
#define MAX_POSITIONS 20                // Maximum number of positions
#define DEFAULT_MAGIC 123456            // Default magic number
#define MAX_LOT_SIZE 100.0              // Maximum lot size
#define MIN_LOT_SIZE 0.01               // Minimum lot size
#define MAX_SPREAD_POINTS 50            // Maximum spread in points
#define DEFAULT_SLIPPAGE 3              // Default slippage in points

// Risk Management Constants
#define MIN_ACCOUNT_BALANCE 1.0         // Minimum account balance (lowered for micro-account testing)
#define DRAWDOWN_CRITICAL 100.0           // Critical drawdown level (increased to 100% for max risk)
#define DRAWDOWN_WARNING 70.0            // Warning drawdown level (increased for consistency)
#define MAX_RISK_PER_TRADE 100.0        // Maximum risk per trade as percentage (e.g., 3.0 = 3%, 100.0 = 100%)
#define MAX_TOTAL_RISK 100.0             // Maximum total portfolio risk (increased to 100%)
#define BENCHMARK_RETURN 0.15           // Annual benchmark return (15%)

// Position Sizing Enumeration
enum ENUM_POSITION_SIZING_MODE
{
    POSITION_SIZE_FIXED = 1,           // Fixed position sizing
    POSITION_SIZE_RISK_PERCENT = 2,    // Risk percentage sizing
    POSITION_SIZE_VOLATILITY = 3,      // Volatility-based sizing
    POSITION_SIZE_CORRELATION = 4      // Correlation-based sizing
};

// Position Sizing Constants (for backward compatibility)
#define POSITION_SIZE_FIXED 1           // Fixed position sizing
#define POSITION_SIZE_RISK_PERCENT 2    // Risk percentage sizing
#define POSITION_SIZE_VOLATILITY 3      // Volatility-based sizing
#define POSITION_SIZE_CORRELATION 4     // Correlation-based sizing

// Performance Monitoring Constants
#define MIN_TRADES_FOR_STATS 10         // Minimum trades for statistics
#define MAX_CONSECUTIVE_LOSSES 5        // Maximum consecutive losses

// Risk Level Constants
#define RISK_LEVEL_EXTREME 4           // Extreme risk level

// Strategy Type Constants
#define STRATEGY_BRAIN 100              // Strategy brain type
#define STRATEGY_AI_ENHANCED 101        // AI enhanced strategy type

// Extended Strategy Type Enumeration
enum ENUM_STRATEGY_TYPE_EXTENDED
{
    STRATEGY_TYPE_CUSTOM = 99,         // Custom strategy type
    STRATEGY_TYPE_BRAIN = 100,         // Strategy brain type
    STRATEGY_TYPE_AI_ENHANCED = 101    // AI enhanced strategy type
};

//+------------------------------------------------------------------+
//| Consensus Decision Context Structure                            |
//+------------------------------------------------------------------+
struct SConsensusDecisionContext
{
    string symbol;                 // Symbol being analyzed
    ENUM_TRADE_SIGNAL signal;       // Final consensus signal
    int decisionClass;              // Decision classification
    double confidence;               // Final confidence level
    double convictionScore;          // Conviction score
    double buyScore;                // Total buy score
    double sellScore;               // Total sell score
    double buySupport;              // Buy support ratio
    double sellSupport;             // Sell support ratio
    double readyLiveWeight;         // Ready live weight
    double totalLiveWeight;         // Total live weight
    double readinessScore;          // Readiness score
    double contextScore;            // Context score
    double costScore;                // Cost score
    double diversityScore;          // Diversity score
    double directionalQuality;      // Directional quality
    double supportRatio;            // Support ratio
    double directionalWeight;       // Directional weight
    double readyCoverage;           // Ready coverage
    double quorumGap;               // Gap between buy/sell scores
    double stalenessPenalty;        // Staleness penalty
    int eligibleLiveVoterCount;     // Eligible live voter count
    int effectiveMinVoters;         // Effective minimum voters
    string quorumMode;              // Quorum mode
    string vetoCode;                // Veto reason code
    int confluence;                 // Number of concurring strategies
    string reason;                  // Decision reason
    
    // Default constructor
    SConsensusDecisionContext() :
        symbol(""),
        signal(TRADE_SIGNAL_NONE),
        decisionClass(0),
        confidence(0.0),
        convictionScore(0.0),
        buyScore(0.0),
        sellScore(0.0),
        buySupport(0.0),
        sellSupport(0.0),
        readyLiveWeight(0.0),
        totalLiveWeight(0.0),
        readinessScore(0.0),
        contextScore(0.0),
        costScore(0.0),
        diversityScore(0.0),
        directionalQuality(0.0),
        supportRatio(0.0),
        directionalWeight(0.0),
        readyCoverage(0.0),
        quorumGap(0.0),
        stalenessPenalty(0.0),
        eligibleLiveVoterCount(0),
        effectiveMinVoters(0),
        quorumMode("FULL_QUORUM"),
        vetoCode(""),
        confluence(0),
        reason("")
    {}
    
    // Copy constructor
    SConsensusDecisionContext(const SConsensusDecisionContext &other) :
        symbol(other.symbol),
        signal(other.signal),
        decisionClass(other.decisionClass),
        confidence(other.confidence),
        convictionScore(other.convictionScore),
        buyScore(other.buyScore),
        sellScore(other.sellScore),
        buySupport(other.buySupport),
        sellSupport(other.sellSupport),
        readyLiveWeight(other.readyLiveWeight),
        totalLiveWeight(other.totalLiveWeight),
        readinessScore(other.readinessScore),
        contextScore(other.contextScore),
        costScore(other.costScore),
        diversityScore(other.diversityScore),
        directionalQuality(other.directionalQuality),
        supportRatio(other.supportRatio),
        directionalWeight(other.directionalWeight),
        readyCoverage(other.readyCoverage),
        quorumGap(other.quorumGap),
        stalenessPenalty(other.stalenessPenalty),
        eligibleLiveVoterCount(other.eligibleLiveVoterCount),
        effectiveMinVoters(other.effectiveMinVoters),
        quorumMode(other.quorumMode),
        vetoCode(other.vetoCode),
        confluence(other.confluence),
        reason(other.reason)
    {}
    
    // Assignment operator
    void operator=(const SConsensusDecisionContext &other)
    {
        symbol = other.symbol;
        signal = other.signal;
        decisionClass = other.decisionClass;
        confidence = other.confidence;
        convictionScore = other.convictionScore;
        buyScore = other.buyScore;
        sellScore = other.sellScore;
        buySupport = other.buySupport;
        sellSupport = other.sellSupport;
        readyLiveWeight = other.readyLiveWeight;
        totalLiveWeight = other.totalLiveWeight;
        readinessScore = other.readinessScore;
        contextScore = other.contextScore;
        costScore = other.costScore;
        diversityScore = other.diversityScore;
        directionalQuality = other.directionalQuality;
        supportRatio = other.supportRatio;
        directionalWeight = other.directionalWeight;
        readyCoverage = other.readyCoverage;
        quorumGap = other.quorumGap;
        stalenessPenalty = other.stalenessPenalty;
        eligibleLiveVoterCount = other.eligibleLiveVoterCount;
        effectiveMinVoters = other.effectiveMinVoters;
        quorumMode = other.quorumMode;
        vetoCode = other.vetoCode;
        confluence = other.confluence;
        reason = other.reason;
    }
};

//+------------------------------------------------------------------+
//| Validation Result Structure (alias for compatibility)            |
//+------------------------------------------------------------------+
struct SValidationResult
{
    bool approved;                 // Whether the signal is approved
    string message;                // Validation message
    double adjustedLotSize;        // Adjusted lot size
    double riskPercent;            // Risk percentage
    double portfolioRisk;          // Portfolio risk
    double correlationRisk;        // Correlation risk
    bool requiresAdjustment;       // Whether adjustment is required
    ENUM_ERROR_LEVEL severity;     // Error severity level
    
    // Additional fields used by AdvancedSignalValidator
    bool isValid;                  // Signal validity
    double qualityScore;           // Quality score
    string reason;                  // Reason for validation
    double strategyConfluence;      // Strategy confluence
    double avgConfidence;           // Average confidence
    bool passedSpreadFilter;       // Passed spread filter
    bool passedTimeFilter;         // Passed time filter
    bool passedVolatilityFilter;   // Passed volatility filter
    bool passedSessionFilter;      // Passed session filter
    
    // Default constructor
    SValidationResult() :
        approved(false),
        message(""),
        adjustedLotSize(0.0),
        riskPercent(0.0),
        portfolioRisk(0.0),
        correlationRisk(0.0),
        requiresAdjustment(false),
        severity(ERROR_LEVEL_INFO),
        isValid(false),
        qualityScore(0.0),
        reason(""),
        strategyConfluence(0.0),
        avgConfidence(0.0),
        passedSpreadFilter(false),
        passedTimeFilter(false),
        passedVolatilityFilter(false),
        passedSessionFilter(false)
    {}
    
    // Copy constructor
    SValidationResult(const SValidationResult &other) :
        approved(other.approved),
        message(other.message),
        adjustedLotSize(other.adjustedLotSize),
        riskPercent(other.riskPercent),
        portfolioRisk(other.portfolioRisk),
        correlationRisk(other.correlationRisk),
        requiresAdjustment(other.requiresAdjustment),
        severity(other.severity),
        isValid(other.isValid),
        qualityScore(other.qualityScore),
        reason(other.reason),
        strategyConfluence(other.strategyConfluence),
        avgConfidence(other.avgConfidence),
        passedSpreadFilter(other.passedSpreadFilter),
        passedTimeFilter(other.passedTimeFilter),
        passedVolatilityFilter(other.passedVolatilityFilter),
        passedSessionFilter(other.passedSessionFilter)
    {}
    
    // Assignment operator
    void operator=(const SValidationResult &other)
    {
        approved = other.approved;
        message = other.message;
        adjustedLotSize = other.adjustedLotSize;
        riskPercent = other.riskPercent;
        portfolioRisk = other.portfolioRisk;
        correlationRisk = other.correlationRisk;
        requiresAdjustment = other.requiresAdjustment;
        severity = other.severity;
        isValid = other.isValid;
        qualityScore = other.qualityScore;
        reason = other.reason;
        strategyConfluence = other.strategyConfluence;
        avgConfidence = other.avgConfidence;
        passedSpreadFilter = other.passedSpreadFilter;
        passedTimeFilter = other.passedTimeFilter;
        passedVolatilityFilter = other.passedVolatilityFilter;
        passedSessionFilter = other.passedSessionFilter;
    }
};


//+------------------------------------------------------------------+
//| Risk Metrics Structure                                         |
//+------------------------------------------------------------------+
struct SRiskMetrics
{
    double totalRisk;             // Total portfolio risk %
    double freeMargin;            // Available free margin
    double marginLevel;           // Current margin level %
    double drawdown;              // Current drawdown %
    double maxDrawdown;           // Maximum drawdown %
    int totalPositions;           // Total open positions
    double correlation;           // Average position correlation
    bool emergencyStop;           // Emergency stop flag
    
    // Default constructor
    SRiskMetrics() :
        totalRisk(0.0),
        freeMargin(0.0),
        marginLevel(0.0),
        drawdown(0.0),
        maxDrawdown(0.0),
        totalPositions(0),
        correlation(0.0),
        emergencyStop(false)
    {}
    
    // Copy constructor
    SRiskMetrics(const SRiskMetrics &other) :
        totalRisk(other.totalRisk),
        freeMargin(other.freeMargin),
        marginLevel(other.marginLevel),
        drawdown(other.drawdown),
        maxDrawdown(other.maxDrawdown),
        totalPositions(other.totalPositions),
        correlation(other.correlation),
        emergencyStop(other.emergencyStop)
    {}
    
    // Assignment operator
    void operator=(const SRiskMetrics &other)
    {
        totalRisk = other.totalRisk;
        freeMargin = other.freeMargin;
        marginLevel = other.marginLevel;
        drawdown = other.drawdown;
        maxDrawdown = other.maxDrawdown;
        totalPositions = other.totalPositions;
        correlation = other.correlation;
        emergencyStop = other.emergencyStop;
    }
};

//+------------------------------------------------------------------+
//| Performance Metrics Structure                                  |
//+------------------------------------------------------------------+
struct SPerformanceMetrics
{
    int totalTrades;              // Total number of trades
    int winningTrades;            // Number of winning trades
    int losingTrades;             // Number of losing trades
    double winRate;               // Win rate percentage
    double totalProfit;           // Total profit/loss
    double averageWin;            // Average winning trade
    double averageLoss;           // Average losing trade
    double profitFactor;          // Profit factor
    double sharpeRatio;           // Sharpe ratio
    double maxDrawdown;           // Maximum drawdown
    double recoveryFactor;        // Recovery factor
};

//+------------------------------------------------------------------+
//| Market Analysis Structure                                       |
//+------------------------------------------------------------------+
struct SMarketAnalysis
{
    ENUM_MARKET_REGIME regime;    // Current market regime
    double volatility;             // Current volatility level
    double trendStrength;         // Trend strength [0-1]
    double momentum;              // Momentum indicator
    double support;               // Support level
    double resistance;            // Resistance level
    bool newsImpact;              // High impact news expected
    datetime analysisTime;        // Analysis timestamp
};

//+------------------------------------------------------------------+
//| Enhanced Trade Signal Structure                                 |
//+------------------------------------------------------------------+
struct SEnhancedTradeSignal
{
    ENUM_TRADE_SIGNAL signal;           // Trading signal
    double confidence;                   // Signal confidence
    double strength;                     // Signal strength
    string reasoning;                    // Signal reasoning
    datetime timestamp;                  // Signal timestamp
    bool isValid;                        // Signal validity
    double qualityScore;                 // Quality score
    string reason;                       // Reason for signal
    double strategyConfluence;           // Strategy confluence
    double avgConfidence;                // Average confidence
    bool passedSpreadFilter;             // Passed spread filter
    bool passedTimeFilter;               // Passed time filter
    bool passedVolatilityFilter;         // Passed volatility filter
    bool passedSessionFilter;            // Passed session filter
    
    // Additional fields for AI signals
    double buyProbability;               // Buy probability
    double sellProbability;              // Sell probability
    double uncertainty;                  // Uncertainty value
    double riskAdjustedSize;             // Risk adjusted position size
    
    // Default constructor
    SEnhancedTradeSignal() :
        signal(TRADE_SIGNAL_NONE),
        confidence(0.0),
        strength(0.0),
        reasoning(""),
        timestamp(0),
        isValid(false),
        qualityScore(0.0),
        reason(""),
        strategyConfluence(0.0),
        avgConfidence(0.0),
        passedSpreadFilter(false),
        passedTimeFilter(false),
        passedVolatilityFilter(false),
        passedSessionFilter(false),
        buyProbability(0.0),
        sellProbability(0.0),
        uncertainty(0.0),
        riskAdjustedSize(0.0)
    {
    }
    
    // Copy constructor
    SEnhancedTradeSignal(const SEnhancedTradeSignal &other) :
        signal(other.signal),
        confidence(other.confidence),
        strength(other.strength),
        reasoning(other.reasoning),
        timestamp(other.timestamp),
        isValid(other.isValid),
        qualityScore(other.qualityScore),
        reason(other.reason),
        strategyConfluence(other.strategyConfluence),
        avgConfidence(other.avgConfidence),
        passedSpreadFilter(other.passedSpreadFilter),
        passedTimeFilter(other.passedTimeFilter),
        passedVolatilityFilter(other.passedVolatilityFilter),
        passedSessionFilter(other.passedSessionFilter),
        buyProbability(other.buyProbability),
        sellProbability(other.sellProbability),
        uncertainty(other.uncertainty),
        riskAdjustedSize(other.riskAdjustedSize)
    {
    }
    
    // Assignment operator
    void operator=(const SEnhancedTradeSignal &other)
    {
        signal = other.signal;
        confidence = other.confidence;
        strength = other.strength;
        reasoning = other.reasoning;
        timestamp = other.timestamp;
        isValid = other.isValid;
        qualityScore = other.qualityScore;
        reason = other.reason;
        strategyConfluence = other.strategyConfluence;
        avgConfidence = other.avgConfidence;
        passedSpreadFilter = other.passedSpreadFilter;
        passedTimeFilter = other.passedTimeFilter;
        passedVolatilityFilter = other.passedVolatilityFilter;
        passedSessionFilter = other.passedSessionFilter;
        buyProbability = other.buyProbability;
        sellProbability = other.sellProbability;
        uncertainty = other.uncertainty;
        riskAdjustedSize = other.riskAdjustedSize;
    }
};

#endif // CORE_ENUMS_MQH
