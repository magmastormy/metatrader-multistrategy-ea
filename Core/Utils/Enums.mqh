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
//| Confluence Factors for Scoring                                  |
//+------------------------------------------------------------------+
enum ENUM_CONFLUENCE_FACTOR
{
    CONFLUENCE_HTF_BIAS = 0,        // HTF Trend alignment
    CONFLUENCE_OB_UNMITIGATED = 1,  // Unmitigated Order Block
    CONFLUENCE_FVG_OVERLAP = 2,     // FVG overlapping zone
    CONFLUENCE_LIQUIDITY_SWEEP = 3, // Liquidity sweep confirmation
    CONFLUENCE_VOLUME_SPIKE = 4,    // Volume/Volatility spike
    CONFLUENCE_SESSION_MATCH = 5,   // Session alignment
    CONFLUENCE_LOW_SPREAD = 6       // Low spread condition
};

//+------------------------------------------------------------------+
//| Position Sizing Methods                                         |
//+------------------------------------------------------------------+
enum ENUM_POSITION_SIZING_MODE
{
    POSITION_SIZE_FIXED = 0,        // Fixed lot size
    POSITION_SIZE_RISK_PERCENT = 1, // Risk percentage based
    POSITION_SIZE_VOLATILITY = 2,   // ATR/Volatility based
    POSITION_SIZE_CORRELATION = 3   // Correlation adjusted
};

//+------------------------------------------------------------------+
//| Risk Level Classification                                       |
//+------------------------------------------------------------------+
enum ENUM_RISK_LEVEL
{
    RISK_LEVEL_LOW = 0,        // Low risk
    RISK_LEVEL_MEDIUM = 1,     // Medium risk
    RISK_LEVEL_HIGH = 2,       // High risk
    RISK_LEVEL_CRITICAL = 3,   // Critical risk
    RISK_LEVEL_EMERGENCY = 4,  // Emergency risk
    RISK_LEVEL_EXTREME = 5     // Extreme risk
};

//+------------------------------------------------------------------+
//| Market Regime Classification                                    |
//+------------------------------------------------------------------+
enum ENUM_MARKET_REGIME
{
    MARKET_REGIME_UNKNOWN = 0,     // Unknown/Undefined
    MARKET_REGIME_TRENDING = 1,    // Strong trending market
    MARKET_REGIME_RANGING = 2,     // Sideways/ranging market
    MARKET_REGIME_VOLATILE = 3,    // High volatility market
    MARKET_REGIME_QUIET = 4,       // Low volatility market
    MARKET_REGIME_LOW_VOLATILITY = 4  // Alias for low volatility market
};

//+------------------------------------------------------------------+
//| Strategy Types                                                  |
//+------------------------------------------------------------------+
enum ENUM_STRATEGY_TYPE
{
    STRATEGY_TYPE_CUSTOM = -1,         // Custom strategy type
    STRATEGY_RSI = 0,                  // RSI based strategy
    STRATEGY_FIBONACCI = 3,            // Fibonacci retracements
    STRATEGY_SWING = 5,                // Swing trading
    STRATEGY_CORRELATION = 6,          // Correlation matrix
    STRATEGY_AI_ENHANCED = 7,          // AI enhanced signals
    STRATEGY_MOMENTUM = 8,             // Momentum strategy
    STRATEGY_BREAKOUT = 9,             // Breakout strategy
    STRATEGY_TREND = 10,               // Trend following strategy
    STRATEGY_MEAN_REVERSION = 11,      // Mean reversion strategy
    STRATEGY_VOLATILITY = 12,          // Volatility breakout strategy
    STRATEGY_MACD = 14,                // MACD strategy
    STRATEGY_BOLLINGER = 15,           // Bollinger Bands strategy
    STRATEGY_BOLLINGER_BREAKOUT = 16,  // Bollinger Breakout strategy
    STRATEGY_FIBONACCI_RETRACEMENT = 17, // Fibonacci Retracement strategy
    STRATEGY_ICHIMOKU = 18,            // Ichimoku Cloud strategy
    STRATEGY_HARMONIC_PATTERNS = 19,   // Harmonic Patterns strategy
    STRATEGY_ELLIOTT_WAVE = 21,        // Elliott Wave Enhanced strategy
    STRATEGY_BRAIN = 22,               // Neural Network Brain strategy
    STRATEGY_SMC = 23,                 // Advanced Smart Money Concepts strategy (includes Order Blocks, Supply/Demand, FVG)
    STRATEGY_SUPPORT_RESISTANCE = 24,  // Support/Resistance + Trendlines strategy
    STRATEGY_UNIFIED_ICT = 25          // Unified ICT/SMC comprehensive strategy
};

//+------------------------------------------------------------------+
//| Trade Management States                                         |
//+------------------------------------------------------------------+
enum ENUM_TRADE_STATE
{
    TRADE_STATE_PENDING = 0,       // Trade pending execution
    TRADE_STATE_ACTIVE = 1,        // Trade is active
    TRADE_STATE_BREAKEVEN = 2,     // Trade moved to breakeven
    TRADE_STATE_TRAILING = 3,      // Trailing stop active
    TRADE_STATE_CLOSED = 4         // Trade closed
};

//+------------------------------------------------------------------+
//| Error Severity Levels                                          |
//+------------------------------------------------------------------+
enum ENUM_ERROR_LEVEL
{
    ERROR_LEVEL_INFO = 0,      // Information message
    ERROR_LEVEL_WARNING = 1,   // Warning message
    ERROR_LEVEL_ERROR = 2,     // Error message
    ERROR_LEVEL_CRITICAL = 3,  // Critical error
    ERROR_LEVEL_FATAL = 4      // Fatal error
};

//+------------------------------------------------------------------+
//| AI Confidence Levels                                           |
//+------------------------------------------------------------------+
enum ENUM_AI_CONFIDENCE
{
    AI_CONFIDENCE_VERY_LOW = 0,    // < 0.3
    AI_CONFIDENCE_LOW = 1,         // 0.3 - 0.5
    AI_CONFIDENCE_MEDIUM = 2,      // 0.5 - 0.7
    AI_CONFIDENCE_HIGH = 3,        // 0.7 - 0.9
    AI_CONFIDENCE_VERY_HIGH = 4    // > 0.9
};

//+------------------------------------------------------------------+
//| Spike Type Classification for Crash/Boom Indices              |
//+------------------------------------------------------------------+
enum ENUM_SPIKE_TYPE
{
    SPIKE_TYPE_UNKNOWN = 0,        // Unknown spike type
    SPIKE_TYPE_MICRO = 1,          // Small spike (< 5 points)
    SPIKE_TYPE_NORMAL = 2,         // Normal spike (5-20 points)
    SPIKE_TYPE_LARGE = 3,          // Large spike (20-50 points)
    SPIKE_TYPE_EXTREME = 4,        // Extreme spike (> 50 points)
    SPIKE_TYPE_REVERSAL = 5,       // Reversal spike pattern
    SPIKE_TYPE_CONTINUATION = 6    // Continuation spike pattern
};

//+------------------------------------------------------------------+
//| Trading Constants                                               |
//+------------------------------------------------------------------+
#ifndef MAX_STRATEGIES
#define MAX_STRATEGIES 10          // Maximum strategies per symbol
#endif

#ifndef MAX_SYMBOLS
#define MAX_SYMBOLS 50             // Maximum symbols to trade
#endif
#define MAX_POSITIONS 100          // Maximum total positions
#define MIN_LOT_SIZE 0.01          // Minimum lot size
#define MAX_LOT_SIZE 100.0         // Maximum lot size
#define DEFAULT_SLIPPAGE 3         // Default slippage in points
#define EMERGENCY_DRAWDOWN 20.0    // Emergency stop drawdown %
#define MIN_ACCOUNT_BALANCE 50.0   // Minimum account balance
#define MAX_CORRELATION 0.8        // Maximum allowed correlation
#define AI_UPDATE_INTERVAL 300     // AI update interval in seconds

//+------------------------------------------------------------------+
//| Risk Management Constants                                       |
//+------------------------------------------------------------------+
#define MAX_RISK_PER_TRADE 2.0     // Maximum risk per trade %
#define MAX_TOTAL_RISK 10.0        // Maximum total portfolio risk %
#define DRAWDOWN_WARNING 5.0       // Drawdown warning level %
#define DRAWDOWN_CRITICAL 10.0     // Critical drawdown level %
#define MIN_FREE_MARGIN 100.0      // Minimum free margin required
#define CORRELATION_THRESHOLD 0.7   // Correlation blocking threshold

//+------------------------------------------------------------------+
//| Performance Tracking Constants                                  |
//+------------------------------------------------------------------+
#define PERFORMANCE_HISTORY_DAYS 30    // Days of performance history
#define MIN_TRADES_FOR_STATS 10        // Minimum trades for statistics
#define BENCHMARK_RETURN 0.1           // Daily benchmark return %
#define MAX_CONSECUTIVE_LOSSES 5       // Max consecutive losses allowed

//+------------------------------------------------------------------+
//| Uncertainty Quantification Structure                           |
//+------------------------------------------------------------------+
struct SUncertaintyMetrics
{
    double uncertainty;        // Overall uncertainty [0-1]
    double modelVariance;      // Model prediction variance
    double dataQuality;        // Input data quality score
    double marketStability;    // Market stability indicator
    string uncertaintySource;  // Source of uncertainty
};

//+------------------------------------------------------------------+
//| Enhanced Trade Signal Structure                                |
//+------------------------------------------------------------------+
struct SEnhancedTradeSignal
{
    ENUM_TRADE_SIGNAL signal;         // Primary trade signal
    double confidence;                 // Signal confidence [0-1]
    SUncertaintyMetrics uncertainty;   // Uncertainty quantification
    double riskAdjustedSize;          // Risk-adjusted position size
    string reasoning;                  // AI reasoning for signal
    string marketContext;             // Current market context
    double volatilityFactor;          // Volatility adjustment factor
    double trendStrength;             // Trend strength indicator
    double momentumScore;             // Momentum score
    // Extended next-gen fields
    double buyProbability;            // Probability of buy
    double sellProbability;           // Probability of sell
    ENUM_MARKET_REGIME regime;        // Detected market regime
    double regimeConfidence;          // Confidence in regime detection [0-1]
    double supportResistanceLevel;    // Midpoint or key S/R level
    datetime timestamp;               // Signal generation time (alias of signalTime)
    datetime signalTime;              // Legacy field for backward compatibility
    ENUM_STRATEGY_TYPE sourceStrategy; // Source strategy type
};

//+------------------------------------------------------------------+
//| Position Information Structure                                  |
//+------------------------------------------------------------------+
struct SPositionInfo
{
    ulong ticket;                 // Position ticket
    string symbol;                // Symbol
    ENUM_ORDER_TYPE type;         // Order type
    double volume;                // Position volume
    double openPrice;             // Open price
    double currentPrice;          // Current price
    double stopLoss;              // Stop loss level
    double takeProfit;            // Take profit level
    double profit;                // Current profit
    datetime openTime;            // Open time
    ENUM_TRADE_STATE state;       // Current trade state
    string comment;               // Position comment
    
    // Default constructor
    SPositionInfo() : 
        ticket(0),
        symbol(""),
        type(WRONG_VALUE),
        volume(0.0),
        openPrice(0.0),
        currentPrice(0.0),
        stopLoss(0.0),
        takeProfit(0.0),
        profit(0.0),
        openTime(0),
        state(TRADE_STATE_CLOSED),
        comment("")
    {}
    
    // Copy constructor
    SPositionInfo(const SPositionInfo &other) :
        ticket(other.ticket),
        symbol(other.symbol),
        type(other.type),
        volume(other.volume),
        openPrice(other.openPrice),
        currentPrice(other.currentPrice),
        stopLoss(other.stopLoss),
        takeProfit(other.takeProfit),
        profit(other.profit),
        openTime(other.openTime),
        state(other.state),
        comment(other.comment)
    {}
    
    // Assignment operator
    void operator=(const SPositionInfo &other)
    {
        ticket = other.ticket;
        symbol = other.symbol;
        type = other.type;
        volume = other.volume;
        openPrice = other.openPrice;
        currentPrice = other.currentPrice;
        stopLoss = other.stopLoss;
        takeProfit = other.takeProfit;
        profit = other.profit;
        openTime = other.openTime;
        state = other.state;
        comment = other.comment;
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
    double volatility;            // Current volatility level
    double trendStrength;         // Trend strength [0-1]
    double momentum;              // Momentum indicator
    double support;               // Support level
    double resistance;            // Resistance level
    bool newsImpact;              // High impact news expected
    datetime analysisTime;        // Analysis timestamp
};

#endif // CORE_ENUMS_MQH