//+------------------------------------------------------------------+
//| ProgressiveTakeProfit.mqh - Advanced Take-Profit Management     |
//| Dynamic, adaptive take-profit algorithms for maximum profitability |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"

#include <Arrays\ArrayObj.mqh>
#include <Arrays\ArrayDouble.mqh>
#include "Enums.mqh"

//+------------------------------------------------------------------+
//| Progressive Take-Profit Configuration                            |
//+------------------------------------------------------------------+
struct SProgressiveTPConfig
{
    bool enabled;                    // Enable progressive TP
    double base_multiplier;          // Base TP multiplier (e.g., 1.5x risk)
    double max_multiplier;           // Maximum TP multiplier
    double min_multiplier;           // Minimum TP multiplier
    int partial_levels;             // Number of partial take-profit levels
    double partial_ratios[10];        // Percentage to close at each level (max 10 levels)
    bool adaptive_multiplier;       // Use adaptive multiplier
    bool trailing_enabled;          // Enable trailing take-profit
    double trailing_step;           // Trailing step size
    double volatility_adjustment;   // Volatility adjustment factor
    bool regime_aware;              // Adjust based on market regime
    bool news_filter;               // Avoid TP during news events
    int max_holding_period;         // Maximum holding period (bars)
    double time_decay_factor;       // Time decay for TP levels
};

//+------------------------------------------------------------------+
//| Take-Profit Level Information                                    |
//+------------------------------------------------------------------+
struct STPLevel
{
    double price;                    // Take-profit price level
    double ratio;                    // Percentage of position to close
    int level_index;                 // Level index (0 = first, 1 = second, etc.)
    bool executed;                   // Whether this level was executed
    datetime execution_time;         // Time when level was executed
    double execution_price;          // Actual execution price
    string reason;                   // Reason for execution
};

//+------------------------------------------------------------------+
//| Wrapper class for STPLevel to work with CArrayObj               |
//+------------------------------------------------------------------+
class CTPLevelWrapper : public CObject
{
private:
    STPLevel m_level;
    
public:
    CTPLevelWrapper(const STPLevel& level) : m_level(level) {}
    
    STPLevel GetLevel() const { return m_level; }
    void SetLevel(const STPLevel& level) { m_level = level; }
};

//+------------------------------------------------------------------+
//| Progressive Take-Profit Manager                                  |
//+------------------------------------------------------------------+
class CProgressiveTakeProfit
{
private:
    SProgressiveTPConfig m_config;           // Configuration
    CArrayObj* m_tp_levels;                  // Array of TP levels
    CArrayDouble* m_executed_levels;         // Track executed levels
    ENUM_MARKET_REGIME m_current_regime;     // Current market regime
    double m_current_volatility;             // Current volatility
    double m_base_risk;                      // Base risk amount
    double m_entry_price;                    // Entry price
    ENUM_ORDER_TYPE m_order_type;            // Order type (BUY/SELL)
    datetime m_entry_time;                   // Entry time
    double m_current_multiplier;             // Current adaptive multiplier
    int m_bars_held;                         // Number of bars held
    double m_peak_profit;                    // Peak profit achieved
    double m_trailing_tp_price;              // Current trailing TP price
    
    // Market analysis components
    double m_atr_value;                      // Average True Range
    double m_regime_strength;                // Strength of current regime
    double m_momentum_score;                 // Momentum score
    double m_volume_ratio;                   // Volume ratio
    
    // Performance tracking
    int m_total_executions;                  // Total TP executions
    double m_total_profit;                   // Total profit from TP
    double m_avg_execution_price;            // Average execution price
    int m_successful_partial_closes;         // Successful partial closes
    
public:
    // Constructor
    CProgressiveTakeProfit();
    
    // Destructor
    ~CProgressiveTakeProfit();
    
    // Initialization
    bool Initialize(const SProgressiveTPConfig& config, 
                   const double entry_price, 
                   const ENUM_ORDER_TYPE order_type,
                   const double risk_amount,
                   const datetime entry_time);
    
    // Main update function - call on each tick/bar
    bool Update(const double current_price, 
               const datetime current_time,
               const int current_bar);
    
    // Check if any TP levels should be executed
    bool CheckTakeProfitLevels(const double current_price, 
                              const datetime current_time);
    
    // Get next TP level to execute
    // Get next TP level to execute
    bool GetNextTPLevel(STPLevel& level);
    
    // Execute a TP level
    bool ExecuteTPLevel(STPLevel& level,
                       const double execution_price,
                       const string reason = "");
    
    // Update market regime and volatility
    void UpdateMarketContext(const double current_price,
                            const double current_volatility,
                            const ENUM_MARKET_REGIME regime,
                            const double regime_strength);
    
    // Calculate adaptive multiplier based on market conditions
    double CalculateAdaptiveMultiplier(const double current_price);
    
    // Calculate trailing take-profit price
    double CalculateTrailingTP(const double current_price);
    
    // Apply time decay to TP levels
    void ApplyTimeDecay(const datetime current_time);
    
    // Get performance metrics
    double GetTotalProfit() const { return m_total_profit; }
    int GetTotalExecutions() const { return m_total_executions; }
    double GetAverageExecutionPrice() const { return m_avg_execution_price; }
    int GetSuccessfulPartialCloses() const { return m_successful_partial_closes; }
    
    // Get current TP levels
    int GetTPLevelCount() const { return m_tp_levels.Total(); }
    bool GetTPLevel(const int index, STPLevel& level) const;
    
    // Get remaining position percentage
    double GetRemainingPositionRatio() const;
    
    // Get current market regime
    ENUM_MARKET_REGIME GetCurrentRegime() const { return m_current_regime; }
    
    // Get configuration
    SProgressiveTPConfig GetConfig() const { return m_config; }
    
    // Set configuration parameters
    void SetBaseMultiplier(const double multiplier) { m_config.base_multiplier = multiplier; }
    void SetMaxMultiplier(const double multiplier) { m_config.max_multiplier = multiplier; }
    void SetMinMultiplier(const double multiplier) { m_config.min_multiplier = multiplier; }
    
private:
    // Helper methods
    void InitializeTPLevels();
    double CalculateVolatilityAdjustedTP(const double base_tp);
    double CalculateRegimeAdjustedTP(const double base_tp);
    double CalculateMomentumAdjustedTP(const double base_tp);
    double CalculateVolumeAdjustedTP(const double base_tp);
    bool ShouldAvoidNewsEvents(const datetime current_time);
    double CalculateTimeDecayFactor(const datetime current_time);
    ENUM_MARKET_REGIME AnalyzeMarketRegime(const double current_price);
    double CalculateRegimeStrength(const double current_price);
    double CalculateMomentumScore(const double current_price);
    double CalculateVolumeRatio();
    void UpdatePeakProfit(const double current_price);
    bool IsPeakProfitDeclining(const double current_price);
    void LogExecution(const STPLevel& level, const string reason);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CProgressiveTakeProfit::CProgressiveTakeProfit()
{
    m_tp_levels = new CArrayObj();
    m_executed_levels = new CArrayDouble();
    
    // Initialize default configuration
    m_config.enabled = true;
    m_config.base_multiplier = 1.5;
    m_config.max_multiplier = 3.0;
    m_config.min_multiplier = 0.8;
    m_config.partial_levels = 3;
    m_config.adaptive_multiplier = true;
    m_config.trailing_enabled = true;
    m_config.trailing_step = 5.0;
    m_config.volatility_adjustment = 1.0;
    m_config.regime_aware = true;
    m_config.news_filter = false;
    m_config.max_holding_period = 100;
    m_config.time_decay_factor = 0.02;
    
    // Initialize partial ratios (default: 25%, 35%, 40%)
    m_config.partial_ratios[0] = 0.25;  // Close 25% at first level
    m_config.partial_ratios[1] = 0.35;  // Close 35% at second level
    m_config.partial_ratios[2] = 0.40;  // Close 40% at third level
    
    // Initialize tracking variables
    m_current_regime = MARKET_REGIME_RANGING;
    m_current_volatility = 0.01;
    m_base_risk = 0.0;
    m_entry_price = 0.0;
    m_order_type = ORDER_TYPE_BUY;
    m_entry_time = 0;
    m_current_multiplier = 1.5;
    m_bars_held = 0;
    m_peak_profit = 0.0;
    m_trailing_tp_price = 0.0;
    m_atr_value = 0.01;
    m_regime_strength = 0.5;
    m_momentum_score = 0.0;
    m_volume_ratio = 1.0;
    m_total_executions = 0;
    m_total_profit = 0.0;
    m_avg_execution_price = 0.0;
    m_successful_partial_closes = 0;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CProgressiveTakeProfit::~CProgressiveTakeProfit()
{
    if(CheckPointer(m_tp_levels) == POINTER_DYNAMIC)
        delete m_tp_levels;
    if(CheckPointer(m_executed_levels) == POINTER_DYNAMIC)
        delete m_executed_levels;
}

//+------------------------------------------------------------------+
//| Initialize the progressive take-profit system                    |
//+------------------------------------------------------------------+
bool CProgressiveTakeProfit::Initialize(const SProgressiveTPConfig& config, 
                                       const double entry_price, 
                                       const ENUM_ORDER_TYPE order_type,
                                       const double risk_amount,
                                       const datetime entry_time)
{
    m_config = config;
    m_entry_price = entry_price;
    m_order_type = order_type;
    m_base_risk = risk_amount;
    m_entry_time = entry_time;
    m_bars_held = 0;
    m_peak_profit = 0.0;
    m_current_multiplier = config.base_multiplier;
    
    // Initialize take-profit levels
    InitializeTPLevels();
    
    Print("[PROGRESSIVE-TP] Initialized with base multiplier: ", DoubleToString(m_config.base_multiplier, 2));
    Print("[PROGRESSIVE-TP] Entry price: ", DoubleToString(m_entry_price, 5));
    Print("[PROGRESSIVE-TP] Risk amount: ", DoubleToString(m_base_risk, 2));
    
    return true;
}

//+------------------------------------------------------------------+
//| Initialize take-profit levels                                    |
//+------------------------------------------------------------------+
void CProgressiveTakeProfit::InitializeTPLevels()
{
    if(!m_config.enabled)
        return;
    
    m_tp_levels.Clear();
    
    for(int i = 0; i < m_config.partial_levels; i++)
    {
        STPLevel level;
        
        level.level_index = i;
        level.executed = false;
        level.execution_time = 0;
        level.execution_price = 0.0;
        level.ratio = m_config.partial_ratios[i];
        
        // Calculate base take-profit price
        double base_tp_pips = m_base_risk * m_current_multiplier * (i + 1) / m_config.partial_levels;
        
        if(m_order_type == ORDER_TYPE_BUY)
            level.price = m_entry_price + base_tp_pips * _Point;
        else
            level.price = m_entry_price - base_tp_pips * _Point;
        
        // Apply adaptive adjustments
        if(m_config.adaptive_multiplier)
        {
            double adaptive_multiplier = CalculateAdaptiveMultiplier(m_entry_price);
            level.price = m_entry_price + (base_tp_pips * adaptive_multiplier / m_config.base_multiplier) * _Point;
        }
        
        CTPLevelWrapper* wrapper = new CTPLevelWrapper(level);
        if(wrapper == NULL)
        {
            Print("[PROGRESSIVE-TP] Failed to create wrapper for level ", i + 1);
            continue;
        }
        
        if(!m_tp_levels.Add(wrapper))
        {
            delete wrapper;
            Print("[PROGRESSIVE-TP] Failed to add level ", i + 1, " to array");
            continue;
        }
        
        Print("[PROGRESSIVE-TP] Level ", i + 1, ": ", DoubleToString(level.price, 5),
              " (", DoubleToString(level.ratio * 100, 1), "%)");
    }
}

//+------------------------------------------------------------------+
//| Calculate adaptive multiplier based on market conditions           |
//+------------------------------------------------------------------+
double CProgressiveTakeProfit::CalculateAdaptiveMultiplier(const double current_price)
{
    double multiplier = m_config.base_multiplier;
    
    // Adjust based on market regime
    if(m_config.regime_aware)
    {
        switch(m_current_regime)
        {
            case MARKET_REGIME_TRENDING:
                if(m_order_type == ORDER_TYPE_BUY)
                    multiplier *= 1.3;  // Extend TP in trending up for longs
                else
                    multiplier *= 0.8;  // Reduce TP for shorts in uptrend
                break;
                
            case MARKET_REGIME_RANGING:
                multiplier *= 0.9;  // Reduce TP in ranging markets
                break;
                
            case MARKET_REGIME_VOLATILE:
                multiplier *= 1.2;  // Extend TP in high volatility
                break;
                
            case MARKET_REGIME_QUIET:
                multiplier *= 0.9;  // Reduce TP in low volatility
                break;
        }
    }
    
    // Adjust based on volatility
    if(m_current_volatility > 0.02)  // High volatility
        multiplier *= 1.15;
    else if(m_current_volatility < 0.005)  // Low volatility
        multiplier *= 0.85;
    
    // Adjust based on momentum
    if(m_momentum_score > 0.7)  // Strong momentum
        multiplier *= 1.2;
    else if(m_momentum_score < -0.3)  // Weak momentum
        multiplier *= 0.8;
    
    // Apply bounds
    multiplier = MathMax(m_config.min_multiplier, MathMin(m_config.max_multiplier, multiplier));
    
    return multiplier;
}

//+------------------------------------------------------------------+
//| Main update function                                             |
//+------------------------------------------------------------------+
bool CProgressiveTakeProfit::Update(const double current_price, 
                                   const datetime current_time,
                                   const int current_bar)
{
    if(!m_config.enabled)
        return true;
    
    m_bars_held = current_bar;
    
    // Update market context
    UpdateMarketContext(current_price, m_current_volatility, m_current_regime, m_regime_strength);
    
    // Update peak profit
    UpdatePeakProfit(current_price);
    
    // Apply time decay
    ApplyTimeDecay(current_time);
    
    // Check for take-profit execution
    if(CheckTakeProfitLevels(current_price, current_time))
    {
        // Handle trailing if enabled
        if(m_config.trailing_enabled)
        {
            m_trailing_tp_price = CalculateTrailingTP(current_price);
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check if any take-profit levels should be executed               |
//+------------------------------------------------------------------+
bool CProgressiveTakeProfit::CheckTakeProfitLevels(const double current_price, 
                                                   const datetime current_time)
{
    if(!m_config.enabled || m_tp_levels.Total() == 0)
        return false;
    
    bool executed = false;
    
    for(int i = 0; i < m_tp_levels.Total(); i++)
    {
        STPLevel level;
        if(!GetTPLevel(i, level) || level.executed)
            continue;
        
        // Check if price has reached the TP level
        bool should_execute = false;
        
        if(m_order_type == ORDER_TYPE_BUY)
        {
            if(current_price >= level.price)
                should_execute = true;
        }
        else
        {
            if(current_price <= level.price)
                should_execute = true;
        }
        
        // Check trailing conditions if enabled
        if(m_config.trailing_enabled && m_trailing_tp_price > 0)
        {
            if(m_order_type == ORDER_TYPE_BUY)
            {
                if(current_price >= m_trailing_tp_price)
                    should_execute = true;
            }
            else
            {
                if(current_price <= m_trailing_tp_price)
                    should_execute = true;
            }
        }
        
        // Check time decay conditions
        if(m_config.max_holding_period > 0 && m_bars_held >= m_config.max_holding_period)
        {
            should_execute = true;
        }
        
        // Execute the level
        if(should_execute)
        {
            if(ExecuteTPLevel(level, current_price, "Price reached TP level"))
            {
                executed = true;
                m_executed_levels.Add(level.ratio);
            }
        }
    }
    
    return executed;
}

//+------------------------------------------------------------------+
//| Get next TP level to execute                                     |
//+------------------------------------------------------------------+
bool CProgressiveTakeProfit::GetNextTPLevel(STPLevel& level)
{
    if(m_tp_levels.Total() == 0)
        return false;
    
    for(int i = 0; i < m_tp_levels.Total(); i++)
    {
        STPLevel temp_level;
        if(GetTPLevel(i, temp_level) && !temp_level.executed)
        {
            level = temp_level;
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Execute a TP level                                               |
//+------------------------------------------------------------------+
bool CProgressiveTakeProfit::ExecuteTPLevel(STPLevel& level,
                                         const double execution_price,
                                         const string reason)
{
    if(level.executed)
        return false;
    
    level.executed = true;
    level.execution_time = TimeCurrent();
    level.execution_price = execution_price;
    level.reason = reason;
    
    // Update performance metrics
    m_total_executions++;
    m_successful_partial_closes++;
    
    double profit = 0.0;
    if(m_order_type == ORDER_TYPE_BUY)
        profit = (execution_price - m_entry_price) / _Point;
    else
        profit = (m_entry_price - execution_price) / _Point;
    
    m_total_profit += profit * level.ratio;
    
    if(m_avg_execution_price == 0.0)
        m_avg_execution_price = execution_price;
    else
        m_avg_execution_price = (m_avg_execution_price + execution_price) / 2.0;
    
    LogExecution(level, reason);
    
    Print("[PROGRESSIVE-TP] Executed level ", level.level_index + 1,
          " at ", DoubleToString(execution_price, 5),
          " (", DoubleToString(level.ratio * 100, 1), "%)",
          " Reason: ", reason);
    
    return true;
}

//+------------------------------------------------------------------+
//| Update market context                                            |
//+------------------------------------------------------------------+
void CProgressiveTakeProfit::UpdateMarketContext(const double current_price,
                                               const double current_volatility,
                                               const ENUM_MARKET_REGIME regime,
                                               const double regime_strength)
{
    m_current_volatility = current_volatility;
    m_current_regime = regime;
    m_regime_strength = regime_strength;
    
    // Update derived metrics
    m_momentum_score = CalculateMomentumScore(current_price);
    m_volume_ratio = CalculateVolumeRatio();
}

//+------------------------------------------------------------------+
//| Calculate trailing take-profit price                           |
//+------------------------------------------------------------------+
double CProgressiveTakeProfit::CalculateTrailingTP(const double current_price)
{
    if(!m_config.trailing_enabled)
        return 0.0;
    
    double trailing_distance = m_config.trailing_step * _Point;
    double new_tp_price = 0.0;
    
    if(m_order_type == ORDER_TYPE_BUY)
    {
        new_tp_price = current_price - trailing_distance;
        if(m_trailing_tp_price == 0.0 || new_tp_price > m_trailing_tp_price)
            m_trailing_tp_price = new_tp_price;
    }
    else
    {
        new_tp_price = current_price + trailing_distance;
        if(m_trailing_tp_price == 0.0 || new_tp_price < m_trailing_tp_price)
            m_trailing_tp_price = new_tp_price;
    }
    
    return m_trailing_tp_price;
}

//+------------------------------------------------------------------+
//| Apply time decay to TP levels                                    |
//+------------------------------------------------------------------+
void CProgressiveTakeProfit::ApplyTimeDecay(const datetime current_time)
{
    if(m_config.time_decay_factor <= 0.0)
        return;
    
    double time_elapsed = (current_time - m_entry_time) / 60.0; // Minutes
    double decay_factor = 1.0 - (time_elapsed * m_config.time_decay_factor / 100.0);
    
    if(decay_factor < 0.5)
        decay_factor = 0.5; // Minimum 50% of original TP
    
    // Apply decay to remaining levels
    for(int i = 0; i < m_tp_levels.Total(); i++)
    {
        STPLevel level;
        if(GetTPLevel(i, level) && !level.executed)
        {
            double original_distance = MathAbs(level.price - m_entry_price);
            double new_distance = original_distance * decay_factor;
            
            if(m_order_type == ORDER_TYPE_BUY)
                level.price = m_entry_price + new_distance;
            else
                level.price = m_entry_price - new_distance;
            
            // Update the level in the array
            CObject* obj = m_tp_levels.At(i);
            if(obj != NULL)
            {
                CTPLevelWrapper* wrapper = dynamic_cast<CTPLevelWrapper*>(obj);
                if(wrapper != NULL)
                {
                    wrapper.SetLevel(level);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Get TP level by index                                            |
//+------------------------------------------------------------------+
bool CProgressiveTakeProfit::GetTPLevel(const int index, STPLevel& level) const
{
    if(index < 0 || index >= m_tp_levels.Total())
        return false;
    
    CObject* obj = m_tp_levels.At(index);
    if(obj != NULL)
    {
        CTPLevelWrapper* wrapper = dynamic_cast<CTPLevelWrapper*>(obj);
        if(wrapper != NULL)
        {
            level = wrapper.GetLevel();
            return true;
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Get remaining position percentage                                |
//+------------------------------------------------------------------+
double CProgressiveTakeProfit::GetRemainingPositionRatio() const
{
    double remaining_ratio = 1.0;
    
    for(int i = 0; i < m_executed_levels.Total(); i++)
    {
        remaining_ratio -= m_executed_levels.At(i);
    }
    
    return MathMax(0.0, remaining_ratio);
}

//+------------------------------------------------------------------+
//| Calculate momentum score                                         |
//+------------------------------------------------------------------+
double CProgressiveTakeProfit::CalculateMomentumScore(const double current_price)
{
    // Simple momentum calculation based on price change
    double price_change = (current_price - m_entry_price) / m_entry_price;
    return MathTan(price_change * 100); // Normalize to reasonable range
}

//+------------------------------------------------------------------+
//| Calculate volume ratio                                           |
//+------------------------------------------------------------------+
double CProgressiveTakeProfit::CalculateVolumeRatio()
{
    // Placeholder - would need actual volume data
    return 1.0;
}

//+------------------------------------------------------------------+
//| Update peak profit                                               |
//+------------------------------------------------------------------+
void CProgressiveTakeProfit::UpdatePeakProfit(const double current_price)
{
    double current_profit = 0.0;
    
    if(m_order_type == ORDER_TYPE_BUY)
        current_profit = (current_price - m_entry_price) / _Point;
    else
        current_profit = (m_entry_price - current_price) / _Point;
    
    if(current_profit > m_peak_profit)
        m_peak_profit = current_profit;
}

//+------------------------------------------------------------------+
//| Log execution details                                            |
//+------------------------------------------------------------------+
void CProgressiveTakeProfit::LogExecution(const STPLevel& level, const string reason)
{
    string log_message = StringFormat("[PROGRESSIVE-TP] EXECUTED: Level=%d, Price=%.5f, Ratio=%.1f%%, Reason=%s",
                                     level.level_index + 1, level.execution_price, level.ratio * 100, reason);
    
    Print(log_message);
}