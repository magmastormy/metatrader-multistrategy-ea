//+------------------------------------------------------------------+
//| EnhancedRiskManager.mqh - Advanced Risk Management System       |
//| Adaptive, multi-dimensional risk management for maximum profitability |
//+------------------------------------------------------------------+
#ifndef ENHANCED_RISK_MANAGER_MQH
#define ENHANCED_RISK_MANAGER_MQH

#property copyright "Copyright 2025, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"

#include <Arrays\ArrayObj.mqh>
#include <Arrays\ArrayDouble.mqh>
#include "../Utils/Enums.mqh"
#include "../Utils/CoreConfig.mqh"

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
//| Enhanced Risk Management Configuration                           |
//+------------------------------------------------------------------+
struct SEnhancedRiskConfig
{
    bool enabled;                    // Enable enhanced risk management
    double base_risk_per_trade;      // Base risk per trade (% of equity)
    double max_risk_per_trade;       // Maximum risk per trade
    double min_risk_per_trade;       // Minimum risk per trade
    double max_daily_risk;           // Maximum daily risk
    double max_weekly_risk;          // Maximum weekly risk
    double max_monthly_risk;          // Maximum monthly risk
    double max_drawdown_threshold;   // Maximum drawdown threshold
    double recovery_mode_multiplier;   // Risk multiplier in recovery mode
    bool adaptive_risk_adjustment;   // Use adaptive risk adjustment
    bool anti_martingale;            // Use anti-martingale strategy
    bool kelly_criterion;            // Use Kelly criterion for sizing
    bool volatility_adjustment;      // Adjust risk based on volatility
    bool regime_aware;                // Adjust based on market regime
    bool correlation_adjustment;     // Adjust based on correlation
    bool news_filter;                // Reduce risk during news events
    int consecutive_losses_limit;    // Maximum consecutive losses
    double win_rate_threshold;        // Win rate threshold for adjustment
    double profit_factor_threshold;   // Profit factor threshold
    double sharpe_ratio_threshold;    // Sharpe ratio threshold
    bool trailing_stop_loss;         // Use trailing stop loss
    double trailing_step;            // Trailing step size
    bool partial_close_on_drawdown;  // Partial close on drawdown
    double partial_close_threshold;   // Partial close threshold
    bool hedge_mode;                 // Enable hedging
    double hedge_ratio;              // Hedge ratio
    bool martingale_recovery;        // Use martingale for recovery
    double martingale_multiplier;    // Martingale multiplier
    int martingale_max_levels;       // Maximum martingale levels
    bool grid_recovery;              // Use grid for recovery
    double grid_spacing;             // Grid spacing
    int grid_max_levels;             // Maximum grid levels
    int max_active_positions;        // Maximum global active positions
};

//+------------------------------------------------------------------+
//| Risk Management Statistics                                       |
//+------------------------------------------------------------------+
struct SRiskStats
{
    double total_trades;             // Total number of trades
    double winning_trades;           // Number of winning trades
    double losing_trades;            // Number of losing trades
    double win_rate;                 // Win rate percentage
    double profit_factor;            // Profit factor
    double sharpe_ratio;             // Sharpe ratio
    double max_drawdown;             // Maximum drawdown
    double current_drawdown;         // Current drawdown
    double consecutive_wins;         // Consecutive wins
    double consecutive_losses;       // Consecutive losses
    double total_profit;             // Total profit
    double total_loss;               // Total loss
    double average_win;              // Average win
    double average_loss;             // Average loss
    double largest_win;              // Largest win
    double largest_loss;             // Largest loss
    double risk_adjusted_return;     // Risk-adjusted return
    double volatility;               // Portfolio volatility
    double correlation_coefficient;    // Correlation coefficient
    double beta_coefficient;           // Beta coefficient
    double alpha_coefficient;          // Alpha coefficient
    double information_ratio;          // Information ratio
    double sortino_ratio;              // Sortino ratio
    double calmar_ratio;               // Calmar ratio
    double sterling_ratio;             // Sterling ratio
    double burke_ratio;                // Burke ratio
};

//+------------------------------------------------------------------+
//| Enhanced Risk Manager                                            |
//+------------------------------------------------------------------+
class CEnhancedRiskManager
{
private:
    SEnhancedRiskConfig m_config;           // Configuration
    SRiskStats m_stats;                     // Risk statistics
    CArrayObj* m_trade_history;             // Trade history
    CArrayDouble* m_equity_curve;         // Equity curve
    CArrayDouble* m_drawdown_series;       // Drawdown series
    CArrayDouble* m_returns_series;        // Returns series
    
    // Current state
    double m_current_equity;               // Current equity
    double m_peak_equity;                  // Peak equity
    double m_current_risk;                 // Current risk level
    double m_recovery_mode_multiplier;       // Recovery mode multiplier
    int m_consecutive_losses;              // Current consecutive losses
    int m_consecutive_wins;                // Current consecutive wins
    bool m_recovery_mode;                  // Recovery mode active
    bool m_drawdown_mode;                  // Drawdown mode active
    int m_martingale_level;                // Current martingale level
    int m_grid_level;                      // Current grid level
    double m_last_trade_risk;              // Last trade risk
    ENUM_MARKET_REGIME m_current_regime;   // Current market regime
    double m_current_volatility;           // Current volatility
    double m_correlation_coefficient;      // Correlation coefficient
    
    // Performance tracking
    double m_daily_risk_used;              // Daily risk used
    double m_weekly_risk_used;             // Weekly risk used
    double m_monthly_risk_used;            // Monthly risk used
    datetime m_last_trade_time;            // Last trade time
    int m_trades_today;                    // Trades today
    int m_trades_this_week;                // Trades this week
    int m_trades_this_month;               // Trades this month
    datetime m_last_reset_date;            // Last daily reset date
    
    // Risk adjustment factors
    double m_volatility_factor;            // Volatility adjustment factor
    double m_regime_factor;                // Regime adjustment factor
    double m_correlation_factor;             // Correlation adjustment factor
    double m_performance_factor;             // Performance adjustment factor
    double m_kelly_fraction;                 // Kelly criterion fraction
    
public:
    // Constructor
    CEnhancedRiskManager();
    
    // Destructor
    ~CEnhancedRiskManager();
    
    // Initialization
    bool Initialize(const SEnhancedRiskConfig& config, const double initial_equity);
    
    // Main risk assessment function
    double CalculateRiskPerTrade(const double current_equity,
                                const double current_price,
                                const ENUM_ORDER_TYPE order_type,
                                const double stop_loss_pips,
                                const ENUM_MARKET_REGIME regime,
                                const double volatility,
                                const datetime current_time);
    
    // Update risk statistics after trade
    bool UpdateTradeResult(const double profit_loss,
                          const double risk_taken,
                          const datetime close_time,
                          const bool was_winner);
    
    // Check if trade is allowed based on risk limits
    bool IsTradeAllowed(const double proposed_risk,
                       const ENUM_ORDER_TYPE order_type,
                       const datetime current_time);

    // Track risk usage
    void AddRiskUsage(const double risk_percent)
    {
       m_daily_risk_used += risk_percent;
       m_weekly_risk_used += risk_percent;
       m_monthly_risk_used += risk_percent;
       m_trades_today++;
       m_trades_this_week++;
       m_trades_this_month++;
       
       PrintFormat("[ENHANCED-RISK] Tracked usage: +%.2f%% | Total daily: %.2f%%", 
                   risk_percent, m_daily_risk_used);
    }

    
    // Get current risk level
    double GetCurrentRiskLevel() const { return m_current_risk; }
    
    // Get risk statistics
    SRiskStats GetRiskStatistics() const { return m_stats; }
    
    // Update market context
    void UpdateMarketContext(const ENUM_MARKET_REGIME regime,
                           const double volatility,
                           const double correlation);
    
    // Recovery mode functions
    bool IsRecoveryMode() const { return m_recovery_mode; }
    void EnterRecoveryMode();
    void ExitRecoveryMode();
    
    // Drawdown management
    bool IsInDrawdown() const { return m_drawdown_mode; }
    double GetCurrentDrawdown() const { return m_stats.current_drawdown; }
    double GetMaxDrawdown() const { return m_stats.max_drawdown; }
    
    // Position sizing functions
    double CalculatePositionSize(const double risk_amount,
                               const double stop_loss_pips,
                               const double current_price,
                               const ENUM_ORDER_TYPE order_type);
    
    // Kelly criterion calculation
    double CalculateKellyFraction();
    
    // Anti-martingale sizing
    double CalculateAntiMartingaleSize(const double base_size);
    
    // Martingale recovery sizing
    double CalculateMartingaleSize(const double base_size);
    
    // Grid recovery sizing
    double CalculateGridSize(const double base_size, const int grid_level);
    
    // Volatility adjustment
    double CalculateVolatilityAdjustment(const double current_volatility);
    
    // Regime adjustment
    double CalculateRegimeAdjustment(const ENUM_MARKET_REGIME regime);
    
    // Correlation adjustment
    double CalculateCorrelationAdjustment(const double correlation);
    
    // Performance adjustment
    double CalculatePerformanceAdjustment();
    
    // Risk limit checks
    bool CheckDailyRiskLimit(const double proposed_risk);
    bool CheckWeeklyRiskLimit(const double proposed_risk);
    bool CheckMonthlyRiskLimit(const double proposed_risk);
    bool CheckDrawdownLimit(const double proposed_risk);
    bool CheckConsecutiveLossLimit();
    
    // Daily reset management
    void CheckAndResetDailyLimits();
    
    // Get configuration
    SEnhancedRiskConfig GetConfig() const { return m_config; }
    
    // Set configuration parameters
    void SetBaseRiskPerTrade(const double risk) { m_config.base_risk_per_trade = risk; }
    void SetMaxRiskPerTrade(const double risk) { m_config.max_risk_per_trade = risk; }
    void SetMinRiskPerTrade(const double risk) { m_config.min_risk_per_trade = risk; }
    
    // Risk reporting
    string GenerateRiskReport();
    void PrintRiskStatistics();
    
private:
    // Helper methods
    void InitializeStatistics();
    void UpdateStatistics(const double profit_loss, const bool was_winner);
    void UpdateDrawdown(const double current_equity);
    void UpdateReturns(const double profit_loss);
    void CalculatePerformanceMetrics();
    double CalculateSharpeRatio();
    double CalculateSortinoRatio();
    double CalculateCalmarRatio();
    double CalculateSterlingRatio();
    double CalculateBurkeRatio();
    double CalculateInformationRatio();
    double CalculateBetaCoefficient();
    double CalculateAlphaCoefficient();
    bool ShouldEnterRecoveryMode();
    bool ShouldExitRecoveryMode();
    void AdjustRiskForRecovery();
    void ResetMartingaleLevel();
    void ResetGridLevel();
    void LogRiskEvent(const string event, const double value);
    string GetRegimeString(const ENUM_MARKET_REGIME regime);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CEnhancedRiskManager::CEnhancedRiskManager()
{
    m_trade_history = new CArrayObj();
    m_equity_curve = new CArrayDouble();
    m_drawdown_series = new CArrayDouble();
    m_returns_series = new CArrayDouble();
    
    // Initialize default configuration
    m_config.enabled = true;
    m_config.base_risk_per_trade = GLOBAL_DEFAULT_RISK_PERCENT;
    m_config.max_risk_per_trade = GLOBAL_MAX_RISK_PERCENT;
    m_config.min_risk_per_trade = GLOBAL_MIN_RISK_PERCENT;
    m_config.max_daily_risk = 0.06;      // 6% max daily risk
    m_config.max_weekly_risk = 0.12;     // 12% max weekly risk
    m_config.max_monthly_risk = 0.20;     // 20% max monthly risk
    m_config.max_drawdown_threshold = 0.15; // 15% max drawdown
    m_config.recovery_mode_multiplier = 0.5; // Reduce risk by 50% in recovery
    m_config.adaptive_risk_adjustment = true;
    m_config.anti_martingale = true;
    m_config.kelly_criterion = true;
    m_config.volatility_adjustment = true;
    m_config.regime_aware = true;
    m_config.correlation_adjustment = true;
    m_config.news_filter = false;
    m_config.consecutive_losses_limit = 5;
    m_config.win_rate_threshold = 0.45;
    m_config.profit_factor_threshold = 1.2;
    m_config.sharpe_ratio_threshold = 0.5;
    m_config.trailing_stop_loss = true;
    m_config.trailing_step = 5.0;
    m_config.partial_close_on_drawdown = true;
    m_config.partial_close_threshold = 0.08;
    m_config.hedge_mode = false;
    m_config.hedge_ratio = 0.3;
    m_config.martingale_recovery = false;
    m_config.martingale_multiplier = 2.0;
    m_config.martingale_max_levels = 3;
    m_config.grid_recovery = false;
    m_config.grid_spacing = 50.0;
    m_config.grid_max_levels = 5;
    m_config.max_active_positions = 5;  // Default limit
    
    // Initialize state variables
    m_current_equity = 0.0;
    m_peak_equity = 0.0;
    m_current_risk = m_config.base_risk_per_trade;
    m_recovery_mode_multiplier = 1.0;
    m_consecutive_losses = 0;
    m_consecutive_wins = 0;
    m_recovery_mode = false;
    m_drawdown_mode = false;
    m_martingale_level = 0;
    m_grid_level = 0;
    m_last_trade_risk = 0.0;
    m_current_regime = MARKET_REGIME_RANGING;
    m_current_volatility = 0.01;
    m_correlation_coefficient = 0.0;
    m_daily_risk_used = 0.0;
    m_weekly_risk_used = 0.0;
    m_monthly_risk_used = 0.0;
    m_last_trade_time = 0;
    m_trades_today = 0;
    m_trades_this_week = 0;
    m_trades_this_month = 0;
    m_volatility_factor = 1.0;
    m_regime_factor = 1.0;
    m_correlation_factor = 1.0;
    m_performance_factor = 1.0;
    m_kelly_fraction = 0.25;
    m_last_reset_date = 0;
    
    InitializeStatistics();
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CEnhancedRiskManager::~CEnhancedRiskManager()
{
    if(CheckPointer(m_trade_history) == POINTER_DYNAMIC)
        delete m_trade_history;
    if(CheckPointer(m_equity_curve) == POINTER_DYNAMIC)
        delete m_equity_curve;
    if(CheckPointer(m_drawdown_series) == POINTER_DYNAMIC)
        delete m_drawdown_series;
    if(CheckPointer(m_returns_series) == POINTER_DYNAMIC)
        delete m_returns_series;
}

//+------------------------------------------------------------------+
//| Initialize the enhanced risk manager                             |
//+------------------------------------------------------------------+
bool CEnhancedRiskManager::Initialize(const SEnhancedRiskConfig& config, const double initial_equity)
{
    m_config = config;
    m_current_equity = initial_equity;
    m_peak_equity = initial_equity;
    m_current_risk = m_config.base_risk_per_trade;
    m_recovery_mode_multiplier = 1.0;
    
    InitializeStatistics();
    
    Print("[ENHANCED-RISK] Initialized with base risk: ", DoubleToString(m_config.base_risk_per_trade, 2), "%");
    Print("[ENHANCED-RISK] Max risk per trade: ", DoubleToString(m_config.max_risk_per_trade, 2), "%");
    Print("[ENHANCED-RISK] Max active positions: ", m_config.max_active_positions);
    Print("[ENHANCED-RISK] Max drawdown: ", DoubleToString(m_config.max_drawdown_threshold, 2), "%");
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate risk per trade with all adjustments                    |
//+------------------------------------------------------------------+
double CEnhancedRiskManager::CalculateRiskPerTrade(const double current_equity,
                                                  const double current_price,
                                                  const ENUM_ORDER_TYPE order_type,
                                                  const double stop_loss_pips,
                                                  const ENUM_MARKET_REGIME regime,
                                                  const double volatility,
                                                  const datetime current_time)
{
    if(!m_config.enabled)
        return m_config.base_risk_per_trade;
    
    m_current_equity = current_equity;
    m_current_regime = regime;
    m_current_volatility = volatility;
    
    // Base risk calculation
    double base_risk = m_config.base_risk_per_trade;
    
    // Apply recovery mode adjustment
    if(m_recovery_mode)
        base_risk *= m_config.recovery_mode_multiplier;
    
    // Apply volatility adjustment
    if(m_config.volatility_adjustment)
        base_risk *= CalculateVolatilityAdjustment(volatility);
    
    // Apply regime adjustment
    if(m_config.regime_aware)
        base_risk *= CalculateRegimeAdjustment(regime);
    
    // Apply correlation adjustment
    if(m_config.correlation_adjustment)
        base_risk *= CalculateCorrelationAdjustment(m_correlation_coefficient);
    
    // Apply performance adjustment
    if(m_config.adaptive_risk_adjustment)
        base_risk *= CalculatePerformanceAdjustment();
    
    // Apply Kelly criterion if enabled
    if(m_config.kelly_criterion)
        base_risk = MathMin(base_risk, CalculateKellyFraction()); // Kelly returns percentage 0-100
    
    // Apply bounds
    base_risk = MathMax(m_config.min_risk_per_trade, MathMin(m_config.max_risk_per_trade, base_risk));
    
    // Check risk limits
    if(!IsTradeAllowed(base_risk, order_type, current_time))
    {
        base_risk = 0.0; // No trade allowed
    }
    
    m_current_risk = base_risk;
    m_last_trade_risk = base_risk;
    
    return base_risk;
}

//+------------------------------------------------------------------+
//| Check if trade is allowed based on risk limits                   |
//+------------------------------------------------------------------+
bool CEnhancedRiskManager::IsTradeAllowed(const double proposed_risk,
                                        const ENUM_ORDER_TYPE order_type,
                                        const datetime current_time)
{
    CheckAndResetDailyLimits();
    
    if(!m_config.enabled)
        return true;
    
    // Check daily risk limit
    if(!CheckDailyRiskLimit(proposed_risk))
    {
        Print("[ENHANCED-RISK] ❌ DAILY RISK LIMIT EXCEEDED!");
        PrintFormat("[ENHANCED-RISK] Daily risk used: %.2f%% | Proposed: %.2f%% | Max allowed: %.2f%%",
                    m_daily_risk_used, proposed_risk, m_config.max_daily_risk);
        PrintFormat("[ENHANCED-RISK] Total would be: %.2f%% > %.2f%% (limit)",
                    (m_daily_risk_used + proposed_risk), m_config.max_daily_risk);
        Print("[ENHANCED-RISK] ℹ️ Risk resets at midnight. Close losing positions or wait until tomorrow.");
        return false;
    }
    
    // Check weekly risk limit
    if(!CheckWeeklyRiskLimit(proposed_risk))
    {
        Print("[ENHANCED-RISK] Weekly risk limit exceeded");
        return false;
    }
    
    // Check monthly risk limit
    if(!CheckMonthlyRiskLimit(proposed_risk))
    {
        Print("[ENHANCED-RISK] Monthly risk limit exceeded");
        return false;
    }
    
    // Check drawdown limit
    if(!CheckDrawdownLimit(proposed_risk))
    {
        Print("[ENHANCED-RISK] Drawdown limit exceeded");
        return false;
    }
    
    // Check consecutive loss limit
    if(!CheckConsecutiveLossLimit())
    {
        Print("[ENHANCED-RISK] Consecutive loss limit exceeded");
        return false;
    }
    
    // Check global position limit (Double Trading / Over-trading protection)
    if(PositionsTotal() >= m_config.max_active_positions)
    {
        Print("[ENHANCED-RISK] ❌ GLOBAL POSITION LIMIT REACHED (", m_config.max_active_positions, ")");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Update trade result and statistics                               |
//+------------------------------------------------------------------+
bool CEnhancedRiskManager::UpdateTradeResult(const double profit_loss,
                                           const double risk_taken,
                                           const datetime close_time,
                                           const bool was_winner)
{
    if(!m_config.enabled)
        return true;
    
    // Update statistics
    UpdateStatistics(profit_loss, was_winner);
    
    // Update equity curve
    m_current_equity += profit_loss;
    m_equity_curve.Add(m_current_equity);
    
    // Update drawdown
    UpdateDrawdown(m_current_equity);
    
    // Update returns series
    UpdateReturns(profit_loss);
    
    // Update consecutive counts
    if(was_winner)
    {
        m_consecutive_wins++;
        m_consecutive_losses = 0;
    }
    else
    {
        m_consecutive_losses++;
        m_consecutive_wins = 0;
    }
    
    // Update time-based counters
    m_last_trade_time = close_time;
    
    // Check for recovery mode
    if(ShouldEnterRecoveryMode())
        EnterRecoveryMode();
    else if(ShouldExitRecoveryMode())
        ExitRecoveryMode();
    
    // Update martingale/grid levels
    if(was_winner)
    {
        ResetMartingaleLevel();
        ResetGridLevel();
    }
    else
    {
        if(m_config.martingale_recovery && m_martingale_level < m_config.martingale_max_levels)
            m_martingale_level++;
        
        if(m_config.grid_recovery && m_grid_level < m_config.grid_max_levels)
            m_grid_level++;
    }
    
    // Calculate performance metrics
    CalculatePerformanceMetrics();
    
    LogRiskEvent("TRADE_RESULT", profit_loss);
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate volatility adjustment                                  |
//+------------------------------------------------------------------+
double CEnhancedRiskManager::CalculateVolatilityAdjustment(const double current_volatility)
{
    double base_volatility = 0.01; // 1% base volatility
    double adjustment = 1.0;
    
    if(current_volatility > base_volatility * 2.0)  // High volatility
        adjustment = 0.7;  // Reduce risk by 30%
    else if(current_volatility < base_volatility * 0.5)  // Low volatility
        adjustment = 1.3;  // Increase risk by 30%
    
    return adjustment;
}

//+------------------------------------------------------------------+
//| Calculate regime adjustment                                    |
//+------------------------------------------------------------------+
double CEnhancedRiskManager::CalculateRegimeAdjustment(const ENUM_MARKET_REGIME regime)
{
    double adjustment = 1.0;
    
    switch(regime)
    {
        case MARKET_REGIME_TRENDING:
            adjustment = 1.2;  // Increase risk in trending markets
            break;
            
        case MARKET_REGIME_RANGING:
            adjustment = 0.8;  // Reduce risk in ranging markets
            break;
            
        case MARKET_REGIME_VOLATILE:
            adjustment = 0.7;  // Reduce risk in volatile markets
            break;
            
        case MARKET_REGIME_QUIET:
            adjustment = 1.1;  // Slightly increase risk in quiet markets
            break;
    }
    
    return adjustment;
}

//+------------------------------------------------------------------+
//| Calculate correlation adjustment                               |
//+------------------------------------------------------------------+
double CEnhancedRiskManager::CalculateCorrelationAdjustment(const double correlation)
{
    double adjustment = 1.0;
    
    if(MathAbs(correlation) > 0.7)  // High correlation
        adjustment = 0.6;  // Reduce risk significantly
    else if(MathAbs(correlation) > 0.5)  // Medium correlation
        adjustment = 0.8;  // Reduce risk moderately
    
    return adjustment;
}

//+------------------------------------------------------------------+
//| Calculate performance adjustment                               |
//+------------------------------------------------------------------+
double CEnhancedRiskManager::CalculatePerformanceAdjustment()
{
    double adjustment = 1.0;
    
    // Adjust based on win rate
    if(m_stats.win_rate < m_config.win_rate_threshold)
        adjustment *= 0.8;  // Reduce risk if win rate is low (threshold is percentage, e.g. 40.0)
    
    // Adjust based on profit factor
    if(m_stats.profit_factor < m_config.profit_factor_threshold)
        adjustment *= 0.9;  // Reduce risk if profit factor is low
    
    // Adjust based on Sharpe ratio
    if(m_stats.sharpe_ratio < m_config.sharpe_ratio_threshold)
        adjustment *= 0.85;  // Reduce risk if Sharpe ratio is low
    
    // Anti-martingale: increase risk after wins, decrease after losses
    if(m_config.anti_martingale)
    {
        if(m_consecutive_wins > 2)
            adjustment *= 1.2;  // Increase risk after wins
        else if(m_consecutive_losses > 2)
            adjustment *= 0.7;  // Reduce risk after losses
    }
    
    return adjustment;
}

//+------------------------------------------------------------------+
//| Check daily risk limit                                           |
//+------------------------------------------------------------------+
bool CEnhancedRiskManager::CheckDailyRiskLimit(const double proposed_risk)
{
    return (m_daily_risk_used + proposed_risk) <= m_config.max_daily_risk;
}

//+------------------------------------------------------------------+
//| Check weekly risk limit                                          |
//+------------------------------------------------------------------+
bool CEnhancedRiskManager::CheckWeeklyRiskLimit(const double proposed_risk)
{
    return (m_weekly_risk_used + proposed_risk) <= m_config.max_weekly_risk;
}

//+------------------------------------------------------------------+
//| Check monthly risk limit                                         |
//+------------------------------------------------------------------+
bool CEnhancedRiskManager::CheckMonthlyRiskLimit(const double proposed_risk)
{
    return (m_monthly_risk_used + proposed_risk) <= m_config.max_monthly_risk;
}

//+------------------------------------------------------------------+
//| Check drawdown limit                                             |
//+------------------------------------------------------------------+
bool CEnhancedRiskManager::CheckDrawdownLimit(const double proposed_risk)
{
    return (m_stats.current_drawdown + proposed_risk) <= m_config.max_drawdown_threshold;
}

//+------------------------------------------------------------------+
//| Check consecutive loss limit                                     |
//+------------------------------------------------------------------+
bool CEnhancedRiskManager::CheckConsecutiveLossLimit()
{
    return m_consecutive_losses < m_config.consecutive_losses_limit;
}

//| Check and reset daily limits at midnight                         |
//+------------------------------------------------------------------+
void CEnhancedRiskManager::CheckAndResetDailyLimits()
{
    datetime localCurrentTime = TimeCurrent();
    MqlDateTime currentStruct;
    TimeToStruct(localCurrentTime, currentStruct);
    
    // Create datetime for start of current day (midnight)
    MqlDateTime dayStruct;
    ZeroMemory(dayStruct);
    dayStruct.year = currentStruct.year;
    dayStruct.mon = currentStruct.mon;
    dayStruct.day = currentStruct.day;
    datetime currentDay = StructToTime(dayStruct);
    
    // Check if we've crossed into a new day
    if(currentDay > m_last_reset_date)
    {
        // Reset daily counters
        m_daily_risk_used = 0.0;
        m_trades_today = 0;
        m_last_reset_date = currentDay;
        
        // Check for weekly reset (Monday)
        if(currentStruct.day_of_week == 1)
        {
            m_weekly_risk_used = 0.0;
            m_trades_this_week = 0;
            Print("[ENHANCED-RISK] Weekly risk counters reset (new week)");
        }
        
        // Check for monthly reset (1st of month)
        if(currentStruct.day == 1)
        {
            m_monthly_risk_used = 0.0;
            m_trades_this_month = 0;
            Print("[ENHANCED-RISK] Monthly risk counters reset (new month)");
        }
        
        Print("[ENHANCED-RISK] Daily risk counters reset for new trading day");
        PrintFormat("[ENHANCED-RISK] Daily risk: 0.00%% | Max allowed: %.2f%%", 
                   m_config.max_daily_risk);
    }
}

//+------------------------------------------------------------------+
//| Enter recovery mode                                              |
//+------------------------------------------------------------------+
void CEnhancedRiskManager::EnterRecoveryMode()
{
    if(m_recovery_mode)
        return;
    
    m_recovery_mode = true;
    m_recovery_mode_multiplier = m_config.recovery_mode_multiplier;
    
    Print("[ENHANCED-RISK] Entered recovery mode - risk reduced by ", 
          DoubleToString((1.0 - m_config.recovery_mode_multiplier) * 100, 1), "%");
    
    LogRiskEvent("RECOVERY_MODE_ENTERED", m_stats.current_drawdown);
}

//+------------------------------------------------------------------+
//| Exit recovery mode                                               |
//+------------------------------------------------------------------+
void CEnhancedRiskManager::ExitRecoveryMode()
{
    if(!m_recovery_mode)
        return;
    
    m_recovery_mode = false;
    m_recovery_mode_multiplier = 1.0;
    
    Print("[ENHANCED-RISK] Exited recovery mode");
    
    LogRiskEvent("RECOVERY_MODE_EXITED", m_stats.current_drawdown);
}

//+------------------------------------------------------------------+
//| Initialize statistics                                           |
//+------------------------------------------------------------------+
void CEnhancedRiskManager::InitializeStatistics()
{
    ZeroMemory(m_stats);
    m_stats.total_trades = 0;
    m_stats.win_rate = 0.5;  // Default 50%
    m_stats.profit_factor = 1.0;  // Default 1.0
    m_stats.sharpe_ratio = 0.0;
    m_stats.max_drawdown = 0.0;
    m_stats.current_drawdown = 0.0;
}

//+------------------------------------------------------------------+
//| Update statistics                                                |
//+------------------------------------------------------------------+
void CEnhancedRiskManager::UpdateStatistics(const double profit_loss, const bool was_winner)
{
    m_stats.total_trades++;
    
    if(was_winner)
    {
        m_stats.winning_trades++;
        m_stats.total_profit += profit_loss;
        m_stats.average_win = (m_stats.average_win * (m_stats.winning_trades - 1) + profit_loss) / m_stats.winning_trades;
        if(profit_loss > m_stats.largest_win)
            m_stats.largest_win = profit_loss;
    }
    else
    {
        m_stats.losing_trades++;
        m_stats.total_loss += MathAbs(profit_loss);
        m_stats.average_loss = (m_stats.average_loss * (m_stats.losing_trades - 1) + MathAbs(profit_loss)) / m_stats.losing_trades;
        if(MathAbs(profit_loss) > m_stats.largest_loss)
            m_stats.largest_loss = MathAbs(profit_loss);
    }
    
    // Calculate win rate
    if(m_stats.total_trades > 0)
        m_stats.win_rate = (m_stats.winning_trades / (double)m_stats.total_trades) * 100.0;
    
    // Calculate profit factor
    if(m_stats.total_loss > 0)
        m_stats.profit_factor = m_stats.total_profit / m_stats.total_loss;
    else if(m_stats.total_profit > 0)
        m_stats.profit_factor = 999.0;  // Very high profit factor
    else
        m_stats.profit_factor = 0.0;
}

//+------------------------------------------------------------------+
//| Update drawdown                                                  |
//+------------------------------------------------------------------+
void CEnhancedRiskManager::UpdateDrawdown(const double current_equity)
{
    if(current_equity > m_peak_equity)
    {
        m_peak_equity = current_equity;
        m_stats.current_drawdown = 0.0;
    }
    else
    {
        m_stats.current_drawdown = ((m_peak_equity - current_equity) / m_peak_equity) * 100.0;
        if(m_stats.current_drawdown > m_stats.max_drawdown)
            m_stats.max_drawdown = m_stats.current_drawdown;
    }
    
    m_drawdown_mode = (m_stats.current_drawdown > m_config.max_drawdown_threshold * 0.5);
    
    m_drawdown_series.Add(m_stats.current_drawdown);
}

//+------------------------------------------------------------------+
//| Update returns series                                            |
//+------------------------------------------------------------------+
void CEnhancedRiskManager::UpdateReturns(const double profit_loss)
{
    double return_pct = (profit_loss / m_current_equity) * 100.0;
    m_returns_series.Add(return_pct);
}

//+------------------------------------------------------------------+
//| Calculate performance metrics                                    |
//+------------------------------------------------------------------+
void CEnhancedRiskManager::CalculatePerformanceMetrics()
{
    m_stats.sharpe_ratio = CalculateSharpeRatio();
    m_stats.sortino_ratio = CalculateSortinoRatio();
    m_stats.calmar_ratio = CalculateCalmarRatio();
    m_stats.sterling_ratio = CalculateSterlingRatio();
    m_stats.burke_ratio = CalculateBurkeRatio();
    m_stats.information_ratio = CalculateInformationRatio();
    m_stats.beta_coefficient = CalculateBetaCoefficient();
    m_stats.alpha_coefficient = CalculateAlphaCoefficient();
}

//+------------------------------------------------------------------+
//| Calculate Sharpe ratio                                           |
//+------------------------------------------------------------------+
double CEnhancedRiskManager::CalculateSharpeRatio()
{
    if(m_returns_series.Total() < 2)
        return 0.0;
    
    double avg_return = 0.0;
    for(int i = 0; i < m_returns_series.Total(); i++)
        avg_return += m_returns_series.At(i);
    avg_return /= m_returns_series.Total();
    
    double variance = 0.0;
    for(int i = 0; i < m_returns_series.Total(); i++)
    {
        double diff = m_returns_series.At(i) - avg_return;
        variance += diff * diff;
    }
    variance /= (m_returns_series.Total() - 1);
    
    double std_dev = MathSqrt(variance);
    if(std_dev == 0.0)
        return 0.0;
    
    return avg_return / std_dev;
}

//+------------------------------------------------------------------+
//| Check if should enter recovery mode                              |
//+------------------------------------------------------------------+
bool CEnhancedRiskManager::ShouldEnterRecoveryMode()
{
    return (m_stats.current_drawdown > m_config.max_drawdown_threshold * 0.7) ||
           (m_consecutive_losses >= 3) ||
           (m_stats.win_rate < 0.3 && m_stats.total_trades > 10);
}

//+------------------------------------------------------------------+
//| Check if should exit recovery mode                               |
//+------------------------------------------------------------------+
bool CEnhancedRiskManager::ShouldExitRecoveryMode()
{
    return (m_stats.current_drawdown < m_config.max_drawdown_threshold * 0.3) &&
           (m_consecutive_losses < 2) &&
           (m_stats.win_rate > 0.4 || m_stats.total_trades <= 10);
}

//+------------------------------------------------------------------+
//| Log risk event                                                   |
//+------------------------------------------------------------------+
void CEnhancedRiskManager::LogRiskEvent(const string event, const double value)
{
    string log_message = StringFormat("[ENHANCED-RISK] EVENT: %s, VALUE: %.4f", event, value);
    Print(log_message);
}

//+------------------------------------------------------------------+
//| Generate risk report                                             |
//+------------------------------------------------------------------+
string CEnhancedRiskManager::GenerateRiskReport()
{
    string report = "[ENHANCED-RISK] RISK MANAGEMENT REPORT\n";
    report += "=====================================\n";
    report += StringFormat("Current Equity: %.2f\n", m_current_equity);
    report += StringFormat("Peak Equity: %.2f\n", m_peak_equity);
    report += StringFormat("Current Drawdown: %.2f%%\n", m_stats.current_drawdown);
    report += StringFormat("Max Drawdown: %.2f%%\n", m_stats.max_drawdown);
    report += StringFormat("Win Rate: %.2f%%\n", m_stats.win_rate);
    report += StringFormat("Profit Factor: %.2f\n", m_stats.profit_factor);
    report += StringFormat("Sharpe Ratio: %.4f\n", m_stats.sharpe_ratio);
    report += StringFormat("Recovery Mode: %s\n", m_recovery_mode ? "ACTIVE" : "INACTIVE");
    report += StringFormat("Consecutive Losses: %d\n", m_consecutive_losses);
    report += StringFormat("Current Risk Level: %.2f%%\n", m_current_risk);
    
    return report;
}

//+------------------------------------------------------------------+
//| Update market context                                            |
//+------------------------------------------------------------------+
void CEnhancedRiskManager::UpdateMarketContext(const ENUM_MARKET_REGIME regime,
                                               const double volatility,
                                               const double correlation)
{
    m_current_regime = regime;
    m_current_volatility = volatility;
    m_correlation_coefficient = correlation;
    
    // Update volatility-based risk adjustment
    m_volatility_factor = CalculateVolatilityAdjustment(volatility);
    
    // Update regime-based risk multiplier
    switch(regime)
    {
        case MARKET_REGIME_TRENDING:
            m_regime_factor = 1.2; // Higher risk in trending markets
            break;
        case MARKET_REGIME_RANGING:
            m_regime_factor = 0.8; // Moderate risk in ranging
            break;
        case MARKET_REGIME_VOLATILE:
            m_regime_factor = 0.5; // Low risk in high volatility
            break;
        case MARKET_REGIME_QUIET:
            m_regime_factor = 1.0; // Normal risk in quiet markets
            break;
        default:
            m_regime_factor = 1.0;
            break;
    }
    
    // Apply correlation adjustment
    if(correlation > 0.7) // High correlation
        m_correlation_factor = 0.7;
    else if(correlation < -0.3) // Negative correlation
        m_correlation_factor = 1.2;
    else
        m_correlation_factor = 1.0;
}

//+------------------------------------------------------------------+
//| Print risk statistics                                            |
//+------------------------------------------------------------------+
void CEnhancedRiskManager::PrintRiskStatistics()
{
    Print(GenerateRiskReport());
}

//+------------------------------------------------------------------+
//| Calculate Kelly Criterion Fraction                               |
//+------------------------------------------------------------------+
double CEnhancedRiskManager::CalculateKellyFraction()
{
    if(m_stats.total_trades < 10)
        return m_config.base_risk_per_trade;
        
    double p = m_stats.win_rate / 100.0; // Win probability (0-1)
    double q = 1.0 - p;                  // Loss probability
    
    // b = odds (Average Win / Average Loss)
    double b = (m_stats.average_loss > 0) ? (m_stats.average_win / m_stats.average_loss) : 1.0;
    
    if(b <= 0) return m_config.min_risk_per_trade;
    
    // Kelly Formula: K = (p*(b+1) - 1) / b
    double kelly = (p * (b + 1.0) - 1.0) / b;
    
    // Apply 25% dampening (Fractional Kelly) for safety
    kelly *= 0.25;
    
    // Convert to percentage (0-100) and bound
    double kelly_pct = MathMax(m_config.min_risk_per_trade, MathMin(m_config.max_risk_per_trade, kelly * 100.0));
    
    return kelly_pct;
}

#endif // ENHANCED_RISK_MANAGER_MQH
