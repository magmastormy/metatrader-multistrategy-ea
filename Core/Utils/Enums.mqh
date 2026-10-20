// Core Trading Enums and Constants
// Essential definitions for the Multi-Strategy EA
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_ENUMS_MQH
#define CORE_ENUMS_MQH

// Trading Signal Types
enum ENUM_TRADE_SIGNAL
{
    TRADE_SIGNAL_NONE = 0,
    TRADE_SIGNAL_BUY = 1,
    TRADE_SIGNAL_SELL = -1
};

// Trading Style Enumeration
enum ENUM_TRADE_STYLE
{
    TRADE_SCALP = 0,           // Scalping style
    TRADE_SWING = 1,           // Swing trading
    TRADE_TREND = 2,           // Trend following
    TRADE_RANGE = 3            // Range trading
};

// Trading Mode Enumeration (Killer Scalper vs HTF Follower)
enum ENUM_TRADING_MODE
{
    TRADING_MODE_NO_TRADE = 0,      // No trading allowed
    TRADING_MODE_KILLER_SCALPER = 1, // Ultra-fast, high frequency
    TRADING_MODE_HTF_FOLLOWER = 2    // Structural, trend following
};

enum ENUM_MARKET_REGIME
{
    MARKET_REGIME_UNKNOWN = 0,
    MARKET_REGIME_TRENDING = 1,
    MARKET_REGIME_RANGING = 2,
    MARKET_REGIME_VOLATILE = 3,
    MARKET_REGIME_QUIET = 4
};

enum ENUM_STRATEGY_TIER
{
    STRATEGY_TIER_1 = 1,           // Top tier strategies
    STRATEGY_TIER_2 = 2,           // Mid tier strategies
    STRATEGY_TIER_3 = 3,           // Lower tier strategies
    STRATEGY_TIER_DISABLED = 0     // Disabled strategies
};

enum ENUM_STRATEGY_TYPE
{
    STRATEGY_MOMENTUM = 1,
    STRATEGY_TREND = 2,
    // STRATEGY_FIBONACCI = 3 — REMOVED: merged into Support/Resistance as confluence module
    // STRATEGY_ELLIOTT_WAVE = 4 — REMOVED: subjective pattern recognition, unsuitable for automation
    STRATEGY_SUPPORT_RESISTANCE = 5,
    STRATEGY_CANDLESTICK = 7,
    STRATEGY_MEAN_REVERSION = 8,   // Mean Reversion strategy (NEW: Batch 93)
    STRATEGY_VOLATILITY_BREAKOUT = 9, // Volatility Breakout strategy (NEW: Batch 93 - Week 3)
    STRATEGY_STATISTICAL_ARBITRAGE = 10, // Statistical Arbitrage strategy (NEW: Batch 93 - Week 4 - ADVANCED)
    STRATEGY_FVG_SCALPER = 11,      // FVG Scalper strategy (NEW: Batch 103)
    STRATEGY_TURTLE_SOUP = 12,      // Turtle Soup strategy (NEW: Batch 103)
    STRATEGY_BREAKER_BLOCK = 13,    // Breaker Block strategy (NEW: Batch 103)
    STRATEGY_NY_OPEN_GAP = 14,      // NY Open Gap strategy (NEW: Batch 103)
    STRATEGY_ASIAN_RANGE_BREAK = 15, // Asian Range Break strategy (NEW: Batch 103)
    STRATEGY_LIQUIDITY_SWEEP = 18,
    STRATEGY_RANGE_COMPRESSION = 19,  // Range Compression Breakout strategy
    STRATEGY_EXIT_OPTIMIZER = 20,
    STRATEGY_CUSTOM = 99,
    STRATEGY_BRAIN = 100,          // Strategy brain type
    STRATEGY_AI_ENHANCED = 101,    // AI enhanced strategy type
    STRATEGY_ONNX = 102            // ONNX AI strategy type
};

// Strategy Array Index Enumeration (L7-004)
// Maps array indices 0-20 to strategies - single source of truth
enum ENUM_STRATEGY_INDEX
{
    SI_MOMENTUM = 0,
    SI_TREND = 1,
    SI_SUPPORT_RESISTANCE = 4,
    SI_CANDLESTICK = 6,
    SI_MEAN_REVERSION = 7,
    SI_VOLATILITY_BREAKOUT = 8,
    SI_STATISTICAL_ARBITRAGE = 9,
    SI_FVG_SCALPER = 10,
    SI_TURTLE_SOUP = 11,
    SI_BREAKER_BLOCK = 12,
    SI_NY_OPEN_GAP = 13,
    SI_ASIAN_RANGE_BREAK = 14,
    SI_LIQUIDITY_SWEEP = 17,
    SI_RANGE_COMPRESSION = 18,
    SI_MAX = 20
};

// EA Operating Mode Enumeration
enum ENUM_EA_MODE
{
    EA_MODE_INDICATOR_ONLY = 1,   // Indicator-based strategies only
    EA_MODE_AI_ONLY = 2,          // AI strategies only
    EA_MODE_HYBRID = 3,           // Both indicators and AI
    EA_MODE_AI_ASSISTED = 4,      // AI assisted strategies
    EA_MODE_INDICATOR_FILTERED = 5 // Indicator filtered strategies
};

// Python bridge telemetry mode
enum ENUM_PYTHON_BRIDGE_MODE
{
    PYTHON_BRIDGE_OFF = 0,        // No Python sidecar expectations
    PYTHON_BRIDGE_OBSERVE = 1,    // Log configured Python sidecar topology only
    PYTHON_BRIDGE_REQUIRED = 2    // Operator expects Python sidecar to be part of workflow
};

enum ENUM_ERROR_LEVEL
{
    ERROR_LEVEL_INFO = 0,
    ERROR_LEVEL_WARNING = 1,
    ERROR_LEVEL_ERROR = 2,        // Error
    ERROR_LEVEL_CRITICAL = 3
};

// Log Level Enumeration (L2-028: Gate verbose PrintFormat)
enum ENUM_LOG_LEVEL
{
    LOG_LEVEL_NONE = 0,
    LOG_LEVEL_ERROR = 1,     // Errors only
    LOG_LEVEL_WARNING = 2,   // Errors + warnings
    LOG_LEVEL_INFO = 3,      // Errors + warnings + info
    LOG_LEVEL_DEBUG = 4,     // All including debug/verbose
    LOG_LEVEL_TRACE = 5      // Everything including trace/heartbeat diagnostics
};

// Risk Management Enumeration
enum ENUM_RISK_MODE
{
    RISK_MODE_FIXED = 1,           // Fixed lot size
    RISK_MODE_PERCENTAGE = 2,
    RISK_MODE_ADAPTIVE = 3         // Adaptive risk management
};

enum ENUM_SIGNAL_EVAL_MODE
{
    EVAL_MODE_NEW_BAR = 0,
    EVAL_MODE_INTRABAR = 1
};

enum ENUM_VALIDATION_PROFILE
{
    VALIDATION_PROFILE_NEW_BAR = 0,
    VALIDATION_PROFILE_INTRABAR = 1
};

enum ENUM_STRATEGY_ROLE
{
    PRIMARY_ALPHA = 0,
    CONTEXT_FEATURE = 1
};

enum ENUM_STRATEGY_CLUSTER
{
    STRATEGY_CLUSTER_NONE = 0,
    TREND_CLUSTER = 1,
    MEAN_REVERSION_CLUSTER = 2,
    STRUCTURE_CLUSTER = 3,
    SCALP_CLUSTER = 4
};

enum ENUM_VOLATILITY_DIRECTION
{
    VOL_EXPANDING = 1,          // ATR expanding - breakouts more likely
    VOL_STABLE = 0,             // ATR stable - no adjustment
    VOL_CONTRACTING = -1        // ATR contracting - squeeze forming
};

enum ENUM_INTRABAR_POLICY
{
    INTRABAR_POLICY_OFF = 0,
    INTRABAR_POLICY_PROBE = 1,
    INTRABAR_POLICY_LIVE = 2
};

enum ENUM_CONSENSUS_DECISION_CLASS
{
    CONSENSUS_DECISION_NONE = 0,
    CONSENSUS_DECISION_FULL_QUORUM = 1,
    CONSENSUS_DECISION_SPARSE_INTRABAR = 2,
    CONSENSUS_DECISION_VETOED = 3,
    CONSENSUS_DECISION_MARGINAL_ADMIT = 4,
    CONSENSUS_DECISION_SOLO_FALLBACK = 5  // Fallback when all strategies abstain
};

enum ENUM_RISK_LEVEL
{
    RISK_LEVEL_LOW = 0,
    RISK_LEVEL_MEDIUM = 1,
    RISK_LEVEL_HIGH = 2,
    RISK_LEVEL_CRITICAL = 3,
    RISK_LEVEL_EXTREME = 4
};

// Margin Health Level (Phase 2.4)
enum ENUM_MARGIN_HEALTH_LEVEL
{
    MARGIN_HEALTH_OK = 0,           // Margin level >= 300%
    MARGIN_HEALTH_WARNING = 1,      // Margin level >= 200% and < 300%
    MARGIN_HEALTH_CRITICAL = 2,     // Margin level >= 150% and < 200%
    MARGIN_HEALTH_EMERGENCY = 3     // Margin level < 150%
};

// Risk Tier (Phase 2.3)
enum ENUM_RISK_TIER
{
   RISK_TIER_CONSERVATIVE,      // Conservative: low risk, tight controls
   RISK_TIER_MODERATE,          // Moderate: balanced risk/reward
   RISK_TIER_AGGRESSIVE,        // Aggressive: higher risk tolerance
   RISK_TIER_FULL_MARGIN,       // Full margin: maximum exposure
   RISK_TIER_MICRO_AGGRESSIVE,  // Micro aggressive: $10-25 accounts, rapid compounding
   RISK_TIER_GROWTH,            // Growth: $25-50 accounts, balanced aggression
   RISK_TIER_ACCELERATION,      // Acceleration: $50-100 accounts, protect gains
   RISK_TIER_INSTITUTIONAL,     // Institutional: $100-500 accounts, capital preservation
   RISK_TIER_PROFESSIONAL       // Professional: $500+ accounts, full institutional
};

// Constants
#define MAX_STRATEGIES 150              // Maximum number of strategies (increased for multi-symbol support)
#define MAX_POSITIONS 20                // Maximum number of positions
#define DEFAULT_MAGIC 123456            // Default magic number
#define MAX_LOT_SIZE 100.0              // Maximum lot size
#define MIN_LOT_SIZE 0.01               // Minimum lot size
#define MAX_SPREAD_POINTS 50            // Maximum spread in points
#define DEFAULT_SLIPPAGE 3              // Default slippage in points

// Risk Percent Scale Conversion Helpers (Blueprint Section 10.4)
// Convention: All risk parameters use 0-100 scale (e.g., 1.5 = 1.5%)
// Internal calculations divide by 100 when fraction is needed.

// Convert risk percent (0-100 scale) to fraction (0-1 scale)
double RiskPercentToFraction(double riskPercent)
{
    return MathMax(0.0, riskPercent) / 100.0;
}

// Convert fraction (0-1 scale) to risk percent (0-100 scale)
double FractionToRiskPercent(double fraction)
{
    return fraction * 100.0;
}

// Validate that a risk percent value is in the expected 0-100 scale
bool IsValidRiskPercent(double riskPercent)
{
    return (riskPercent >= 0.0 && riskPercent <= 100.0);
}

// Clamp risk percent to safe range [0.01, 50.0]
double ClampRiskPercentGlobal(double riskPercent)
{
    return MathMax(0.01, MathMin(riskPercent, 50.0));
}

// Risk Management Constants
#define MIN_ACCOUNT_BALANCE 1.0         // Minimum account balance (lowered for micro-account testing)
#define DRAWDOWN_CRITICAL 10.0           // Critical drawdown level (Blueprint 10.4: 0-100 scale)
#define DRAWDOWN_WARNING 5.0            // Warning drawdown level (Blueprint 10.4: 0-100 scale)
#define MAX_RISK_PER_TRADE 50.0       // Maximum risk per trade as percentage (Blueprint 10.4: 0-100 scale)
// Ceiling on rounding a sub-minimum lot up to SYMBOL_VOLUME_MIN: the uplift multiplies the risk the gate approved,
// so it bounds every consumer that sizes or gates a lot, not only CPositionSizer.
#ifndef MAX_MIN_LOT_RISK_MULTIPLIER
#define MAX_MIN_LOT_RISK_MULTIPLIER 3.0
#endif
#define MAX_TOTAL_RISK 10.0             // Maximum total portfolio risk (Blueprint 10.4: 0-100 scale)
#define BENCHMARK_RETURN 0.15           // Annual benchmark return (15%)

// Drawdown state — single source of truth for all drawdown queries
// (Phase 2.1: Defined here to break circular include dependency)
struct SDrawdownState
{
    double currentDrawdownPct;       // Current drawdown from peak equity (%)
    bool   isWarningActive;         // Drawdown >= warning threshold
    bool   isCriticalActive;        // Drawdown >= critical threshold (trading halted)
    bool   isTradingEnabled;        // Master trading switch
    double conservativeMultiplier;   // Position size multiplier (1.0 normal, 0.5 warning)
};

// Position Sizing Enumeration
// L5-006: Unified enum matching CPositionSizer usage
enum ENUM_POSITION_SIZING_MODE
{
    POSITION_SIZING_FIXED_LOT = 0,         // Fixed lot size
    POSITION_SIZING_FIXED_RISK = 1,        // Fixed risk percentage
    POSITION_SIZING_KELLY = 2,             // Kelly Criterion
    POSITION_SIZING_VOLATILITY_TARGET = 3,
    POSITION_SIZING_EQUITY_CURVE = 4       // Equity curve scaling
};

// Performance Monitoring Constants
#define MIN_TRADES_FOR_STATS 10         // Minimum trades for statistics
#define MAX_CONSECUTIVE_LOSSES 5        // Maximum consecutive losses

// Risk Level Constants
#define RISK_LEVEL_EXTREME 4           // Extreme risk level

enum ENUM_STRATEGY_TYPE_EXTENDED
{
    STRATEGY_TYPE_CUSTOM = 99,
    STRATEGY_TYPE_BRAIN = 100,
    STRATEGY_TYPE_AI_ENHANCED = 101
};

struct SConsensusDecisionContext
{
    string symbol;                 // Symbol being analyzed
    ENUM_TRADE_SIGNAL signal;       // Final consensus signal
    int decisionClass;
    double confidence;               // Final confidence level
    double convictionScore;
    double buyScore;                // Total buy score
    double sellScore;               // Total sell score
    double buySupport;              // Buy support ratio
    double sellSupport;             // Sell support ratio
    double readyLiveWeight;
    double totalLiveWeight;
    double readinessScore;
    double contextScore;
    double costScore;
    double directionalQuality;
    double supportRatio;
    double quorumGap;               // Gap between buy/sell scores
    int eligibleLiveVoterCount;
    int effectiveMinVoters;
    string quorumMode;
    string vetoCode;                // Veto reason code
    int confluence;                 // Number of concurring strategies
    string reason;                  // Decision reason
    ENUM_STRATEGY_CLUSTER dominantCluster; // Dominant cluster for this decision
    
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
        directionalQuality(0.0),
        supportRatio(0.0),
        quorumGap(0.0),
        eligibleLiveVoterCount(0),
        effectiveMinVoters(0),
        quorumMode("FULL_QUORUM"),
        vetoCode(""),
        confluence(0),
        reason(""),
        dominantCluster(STRATEGY_CLUSTER_NONE)
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
        directionalQuality(other.directionalQuality),
        supportRatio(other.supportRatio),
        quorumGap(other.quorumGap),
        eligibleLiveVoterCount(other.eligibleLiveVoterCount),
        effectiveMinVoters(other.effectiveMinVoters),
        quorumMode(other.quorumMode),
        vetoCode(other.vetoCode),
        confluence(other.confluence),
        reason(other.reason),
        dominantCluster(other.dominantCluster)
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
        directionalQuality = other.directionalQuality;
        supportRatio = other.supportRatio;
        quorumGap = other.quorumGap;
        eligibleLiveVoterCount = other.eligibleLiveVoterCount;
        effectiveMinVoters = other.effectiveMinVoters;
        quorumMode = other.quorumMode;
        vetoCode = other.vetoCode;
        confluence = other.confluence;
        reason = other.reason;
        dominantCluster = other.dominantCluster;
    }
};

// Validation Result Structure (alias for compatibility)
struct SValidationResult
{
    bool approved;                 // Whether the signal is approved
    string message;                // Validation message
    double adjustedLotSize;
    double riskPercent;
    double portfolioRisk;
    double correlationRisk;
    bool requiresAdjustment;       // Whether adjustment is required
    ENUM_ERROR_LEVEL severity;
    
    // Additional fields used by AdvancedSignalValidator
    bool isValid;                  // Signal validity
    double qualityScore;
    string reason;                  // Reason for validation
    double strategyConfluence;
    double avgConfidence;
    bool passedSpreadFilter;
    bool passedTimeFilter;
    bool passedVolatilityFilter;
    bool passedSessionFilter;
    
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


struct SRiskMetrics
{
    double totalRisk;             // Total portfolio risk %
    double freeMargin;            // Available free margin
    double marginLevel;           // Current margin level %
    double drawdown;              // Current drawdown %
    double maxDrawdown;
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

struct SPerformanceMetrics
{
    int totalTrades;              // Total number of trades
    int winningTrades;            // Number of winning trades
    int losingTrades;             // Number of losing trades
    double winRate;               // Win rate percentage
    double totalProfit;           // Total profit/loss
    double averageWin;            // Average winning trade
    double averageLoss;           // Average losing trade
    double profitFactor;
    double sharpeRatio;
    double sharpeRatioWithRiskFree; // Sharpe ratio with risk-free rate
    double maxDrawdown;
    double recoveryFactor;
};

struct SMarketAnalysis
{
    ENUM_MARKET_REGIME regime;    // Current market regime
    double volatility;             // Current volatility level
    double trendStrength;
    double momentum;              // Momentum indicator
    double support;               // Support level
    double resistance;            // Resistance level
    bool newsImpact;              // High impact news expected
    datetime analysisTime;
};

struct SEnhancedTradeSignal
{
    ENUM_TRADE_SIGNAL signal;           // Trading signal
    double confidence;                   // Signal confidence
    double strength;                     // Signal strength
    string reasoning;                    // Signal reasoning
    datetime timestamp;                  // Signal timestamp
    bool isValid;                        // Signal validity
    double qualityScore;
    string reason;                       // Reason for signal
    double strategyConfluence;
    double avgConfidence;
    bool passedSpreadFilter;
    bool passedTimeFilter;
    bool passedVolatilityFilter;
    bool passedSessionFilter;
    
    // Additional fields for AI signals
    double buyProbability;
    double sellProbability;
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

// Escape JSON string (global utility)
string EscapeJsonString(const string &str)
{
    string result = str;
    StringReplace(result, "\\", "\\\\");
    StringReplace(result, "\"", "\\\"");
    StringReplace(result, "\n", "\\n");
    StringReplace(result, "\r", "\\r");
    StringReplace(result, "\t", "\\t");
    return result;
}

// Log Level Constants (mapped to g_logLevel 0-4 scale)
// g_logLevel: 0=Silent, 1=Errors, 2=Normal/Info, 3=Verbose/Debug, 4=Trace
#define LOG_LEVEL_SILENT    0
#define LOG_LEVEL_ERROR     1
#define LOG_LEVEL_WARN      1
#define LOG_LEVEL_INFO      2
#define LOG_LEVEL_DEBUG     3
#define LOG_LEVEL_TRACE     4

// Global log level variable (set from InpLogLevel input during EA initialization)
int g_logLevel = LOG_LEVEL_ERROR;

// Conditional Logging Macro (L2-028: Gate verbose PrintFormat)
// Uses existing g_logLevel (int 0-4) mapped to ENUM_LOG_VERBOSITY
// MQL5 doesn't support { } blocks in macro definitions, so we use simple statements
// Users must wrap LOG_IF calls in { } if used in if-else contexts
#define LOG_IF0(verbosity, format) if(g_logLevel >= (int)verbosity) PrintFormat(format)
#define LOG_IF1(verbosity, format, arg1) if(g_logLevel >= (int)verbosity) PrintFormat(format, arg1)
#define LOG_IF2(verbosity, format, arg1, arg2) if(g_logLevel >= (int)verbosity) PrintFormat(format, arg1, arg2)
#define LOG_IF3(verbosity, format, arg1, arg2, arg3) if(g_logLevel >= (int)verbosity) PrintFormat(format, arg1, arg2, arg3)
#define LOG_IF4(verbosity, format, arg1, arg2, arg3, arg4) if(g_logLevel >= (int)verbosity) PrintFormat(format, arg1, arg2, arg3, arg4)
#define LOG_IF5(verbosity, format, arg1, arg2, arg3, arg4, arg5) if(g_logLevel >= (int)verbosity) PrintFormat(format, arg1, arg2, arg3, arg4, arg5)
#define LOG_IF6(verbosity, format, arg1, arg2, arg3, arg4, arg5, arg6) if(g_logLevel >= (int)verbosity) PrintFormat(format, arg1, arg2, arg3, arg4, arg5, arg6)
#define LOG_IF7(verbosity, format, arg1, arg2, arg3, arg4, arg5, arg6, arg7) if(g_logLevel >= (int)verbosity) PrintFormat(format, arg1, arg2, arg3, arg4, arg5, arg6, arg7)
#define LOG_IF8(verbosity, format, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8) if(g_logLevel >= (int)verbosity) PrintFormat(format, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8)
#define LOG_IF9(verbosity, format, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9) if(g_logLevel >= (int)verbosity) PrintFormat(format, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9)
#define LOG_IF10(verbosity, format, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10) if(g_logLevel >= (int)verbosity) PrintFormat(format, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10)
#define LOG_IF11(verbosity, format, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11) if(g_logLevel >= (int)verbosity) PrintFormat(format, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11)
#define LOG_IF12(verbosity, format, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12) if(g_logLevel >= (int)verbosity) PrintFormat(format, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12)

// Users must use LOG_IF0, LOG_IF1, etc. explicitly based on number of format args
// Wrap in { } if used in if-else context: if(cond) { LOG_IF1(...); } else { ... }

#endif // CORE_ENUMS_MQH
