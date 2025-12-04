//+------------------------------------------------------------------+
//| Risk Management Module                                            |
//+------------------------------------------------------------------+
#ifndef __RISK_MANAGER_MQH__
#define __RISK_MANAGER_MQH__

// Include required modules
#include <Trade\SymbolInfo.mqh>

// Risk state enumeration
enum ENUM_RISK_STATE {
    RISK_NORMAL,       // Normal trading allowed
    RISK_REDUCED,      // Reduced position sizing
    RISK_PAUSED        // Trading paused due to circuit breaker
};

// Trade result structure
struct STradeResult {
    bool    isWin;          // Whether the trade was a win
    double  profit;         // Profit/loss amount
    double  pips;           // Profit/loss in pips
    string  symbol;         // Symbol traded
    string  strategy;       // Strategy used
    datetime openTime;      // Trade open time
    datetime closeTime;     // Trade close time
    int     direction;      // Trade direction (1=buy, -1=sell)
};

class CRiskManager {
private:
    double m_baseRiskPercent;           // Base risk percentage per trade
    double m_maxRiskPerTrade;           // Maximum risk percentage per trade
    double m_maxAccountRisk;            // Maximum total account risk percentage
    double m_drawdownReduceThreshold;   // Drawdown threshold to reduce position size
    double m_drawdownStopThreshold;     // Drawdown threshold to stop trading
    int m_consecutiveLossThreshold;     // Consecutive loss threshold for circuit breaker
    double m_dailyLossThreshold;        // Daily loss threshold as percentage of balance
    
    // Current risk state
    ENUM_RISK_STATE m_riskState;
    
    // Tracking variables
    int m_consecutiveLosses;            // Current consecutive loss count
    int m_consecutiveWins;              // Current consecutive win count
    double m_dailyPnL;                  // Daily profit/loss
    datetime m_lastTradeTime;           // Time of last trade
    datetime m_circuitBreakerTime;      // Time when circuit breaker was triggered
    int m_circuitBreakerDuration;       // Duration of circuit breaker in seconds
    
    // Trade history for analysis
    STradeResult m_recentTrades[100];   // Circular buffer of recent trades
    int m_tradeHistoryIndex;            // Current index in trade history buffer
    int m_tradeHistoryCount;            // Number of trades in history
    
    // Calculate current drawdown
    double CalculateDrawdown() {
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double balance = AccountInfoDouble(ACCOUNT_BALANCE);
        
        // Avoid division by zero
        if(balance <= 0) return 0.0;
        
        return (balance - equity) / balance * 100.0;
    }
    
    // EMERGENCY FIX: Calculate recent win rate for adaptive risk management
    double CalculateRecentWinRate() {
        if(m_tradeHistoryCount < 5) return 0.5; // Default 50% if insufficient data
        
        int recentTrades = MathMin(20, m_tradeHistoryCount); // Use last 20 trades
        int wins = 0;
        
        for(int i = 0; i < recentTrades; i++) {
            if(m_recentTrades[i].isWin) wins++;
        }
        
        return (double)wins / recentTrades;
    }
    
    // Calculate total risk from open positions
    double CalculateTotalOpenRisk() {
        double totalRisk = 0.0;
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        
        // Loop through all open positions
        for(int i = 0; i < PositionsTotal(); i++) {
            if(PositionSelectByTicket(PositionGetTicket(i))) {
                double positionVolume = PositionGetDouble(POSITION_VOLUME);
                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double stopLoss = PositionGetDouble(POSITION_SL);
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                
                // Skip positions without stop loss
                if(stopLoss == 0) continue;
                
                // Calculate risk for this position
                double tickSize = SymbolInfoDouble(posSymbol, SYMBOL_TRADE_TICK_SIZE);
                double tickValue = SymbolInfoDouble(posSymbol, SYMBOL_TRADE_TICK_VALUE);
                
                double riskMoney = 0;
                if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) {
                    riskMoney = (openPrice - stopLoss) / tickSize * tickValue * positionVolume;
                } else {
                    riskMoney = (stopLoss - openPrice) / tickSize * tickValue * positionVolume;
                }
                
                // Add to total risk as percentage
                totalRisk += (riskMoney / accountBalance) * 100.0;
            }
        }
        
        return totalRisk;
    }
    
    // Reset daily P&L at the start of a new day
    void CheckDailyReset() {
        static datetime lastDay = 0;
        datetime currentTime = TimeCurrent();
        
        // Get the date part only
        MqlDateTime currentTimeStruct;
        TimeToStruct(currentTime, currentTimeStruct);
        
        // Create a datetime for the start of the current day
        datetime currentDay = StringToTime(
            StringFormat("%04d.%02d.%02d 00:00:00", 
                        currentTimeStruct.year, 
                        currentTimeStruct.mon, 
                        currentTimeStruct.day)
        );
        
        // Check if we've moved to a new day
        if(currentDay > lastDay) {
            m_dailyPnL = 0.0;
            lastDay = currentDay;
            Print("[RISK] Daily P&L reset for new trading day");
        }
    }
    
    // Update circuit breaker status
    void UpdateCircuitBreaker() {
        // Check if circuit breaker is active
        if(m_riskState == RISK_PAUSED) {
            // Check if circuit breaker duration has elapsed
            if(TimeCurrent() - m_circuitBreakerTime >= m_circuitBreakerDuration) {
                m_riskState = RISK_NORMAL;
                Print("[RISK] Circuit breaker deactivated after ", 
                      m_circuitBreakerDuration / 60, " minutes. Trading resumed.");
            }
        }
        
        // Check drawdown for circuit breaker
        double currentDrawdown = CalculateDrawdown();
        if(currentDrawdown >= m_drawdownStopThreshold && m_riskState != RISK_PAUSED) {
            TriggerCircuitBreaker("Drawdown exceeded " + DoubleToString(m_drawdownStopThreshold, 1) + "%");
        }
        
        // Check daily loss for circuit breaker
        if(m_dailyPnL <= -m_dailyLossThreshold && m_riskState != RISK_PAUSED) {
            TriggerCircuitBreaker("Daily loss exceeded " + DoubleToString(m_dailyLossThreshold, 1) + "%");
        }
    }
    
    // Trigger the circuit breaker
    void TriggerCircuitBreaker(string reason) {
        m_riskState = RISK_PAUSED;
        m_circuitBreakerTime = TimeCurrent();
        
        // Scale circuit breaker duration based on consecutive losses
        int durationMinutes = 30 + (m_consecutiveLosses * 15);
        m_circuitBreakerDuration = durationMinutes * 60; // Convert to seconds
        
        Print("[RISK CIRCUIT BREAKER] Trading halted for ", durationMinutes, 
              " minutes. Reason: ", reason, 
              ". Consecutive losses: ", m_consecutiveLosses);
    }
    
public:
    CRiskManager() {
        m_baseRiskPercent = 1.0;
        m_maxRiskPerTrade = 2.0;
        m_maxAccountRisk = 6.0;
        m_drawdownReduceThreshold = 5.0;
        m_drawdownStopThreshold = 10.0;
        m_consecutiveLossThreshold = 3;
        m_dailyLossThreshold = 3.0; // 3% of account balance
        
        m_riskState = RISK_NORMAL;
        m_consecutiveLosses = 0;
        m_consecutiveWins = 0;
        m_dailyPnL = 0.0;
        m_lastTradeTime = 0;
        m_circuitBreakerTime = 0;
        m_circuitBreakerDuration = 1800; // 30 minutes default
        
        m_tradeHistoryIndex = 0;
        m_tradeHistoryCount = 0;
    }

    void InitializeParameters(double baseRisk, double maxTradeRisk, double maxAccountRisk,
                              double drawdownReduce, double drawdownStop) {
        m_baseRiskPercent = baseRisk;
        m_maxRiskPerTrade = maxTradeRisk;
        m_maxAccountRisk = maxAccountRisk;
        m_drawdownReduceThreshold = drawdownReduce;
        m_drawdownStopThreshold = drawdownStop;
    }
    
    // Initialize with risk parameters
    void Initialize(double baseRiskPercent, double maxRiskPerTrade, double maxAccountRisk,
                   double drawdownReduceThreshold, double drawdownStopThreshold) {
        m_baseRiskPercent = baseRiskPercent;
        m_maxRiskPerTrade = maxRiskPerTrade;
        m_maxAccountRisk = maxAccountRisk;
        m_drawdownReduceThreshold = drawdownReduceThreshold;
        m_drawdownStopThreshold = drawdownStopThreshold;
    }
    
    // Set circuit breaker parameters
    void SetCircuitBreakerParameters(int consecutiveLossThreshold, double dailyLossThreshold) {
        m_consecutiveLossThreshold = consecutiveLossThreshold;
        m_dailyLossThreshold = dailyLossThreshold;
    }
    
    // Update risk state based on current conditions
    void UpdateRiskState() {
        // Reset daily P&L if needed
        CheckDailyReset();
        
        // Update circuit breaker status
        UpdateCircuitBreaker();
        
        // If circuit breaker is active, no need to check other conditions
        if(m_riskState == RISK_PAUSED) return;
        
        // Check drawdown for reduced risk
        double currentDrawdown = CalculateDrawdown();
        if(currentDrawdown >= m_drawdownReduceThreshold) {
            m_riskState = RISK_REDUCED;
        } else {
            m_riskState = RISK_NORMAL;
        }
        
        // Check consecutive losses for circuit breaker
        if(m_consecutiveLosses >= m_consecutiveLossThreshold) {
            TriggerCircuitBreaker("Consecutive losses threshold reached");
        }
    }
    
    // Calculate adjusted risk percentage based on current conditions
    double GetAdjustedRiskPercent() {
        // EMERGENCY FIX: Performance-based risk adjustment
        double adjustedRisk = m_baseRiskPercent;
        
        // Calculate recent win rate for adaptive scaling
        double recentWinRate = CalculateRecentWinRate();
        
        // Reduce risk when losing, increase when winning (within limits)
        if(recentWinRate < 0.3) {
            adjustedRisk *= 0.5; // Halve risk when win rate below 30%
            Print("[ADAPTIVE-RISK] Risk reduced due to poor performance: ", recentWinRate * 100, "% win rate");
        }
        else if(recentWinRate > 0.6) {
            adjustedRisk *= 1.2; // Increase risk by 20% when win rate above 60%
            adjustedRisk = MathMin(adjustedRisk, m_maxRiskPerTrade); // Cap at max
            Print("[ADAPTIVE-RISK] Risk increased due to good performance: ", recentWinRate * 100, "% win rate");
        }
        
        // Get current drawdown
        double currentDrawdown = CalculateDrawdown();
        
        // Adjust based on risk state
        if(m_riskState == RISK_REDUCED) {
            // Linear reduction: at DrawdownReduceThreshold risk is 100%, at DrawdownStopThreshold risk is 25%
            double reductionFactor = 1.0 - 0.75 * (currentDrawdown - m_drawdownReduceThreshold) / 
                                    (m_drawdownStopThreshold - m_drawdownReduceThreshold);
            
            // Ensure factor is between 0.25 and 1.0
            reductionFactor = MathMax(0.25, MathMin(1.0, reductionFactor));
            
            adjustedRisk *= reductionFactor;
            
            Print("[RISK] Risk reduced to ", NormalizeDouble(adjustedRisk, 2), 
                  "% due to drawdown of ", NormalizeDouble(currentDrawdown, 2), "%");
        } else if(m_riskState == RISK_PAUSED) {
            // No trading allowed
            adjustedRisk = 0.0;
        }
        
        // Adjust based on consecutive wins (anti-martingale)
        if(m_consecutiveWins >= 2) {
            double winBonus = 1.0 + (m_consecutiveWins * 0.1); // +10% per win
            winBonus = MathMin(winBonus, 1.5); // Cap at +50%
            adjustedRisk *= winBonus;
            
            Print("[RISK] Risk increased to ", NormalizeDouble(adjustedRisk, 2), 
                  "% due to ", m_consecutiveWins, " consecutive wins");
        }
        
        // Adjust based on consecutive losses (reduce risk)
        if(m_consecutiveLosses >= 1 && m_riskState != RISK_PAUSED) {
            double lossReduction = 1.0 - (m_consecutiveLosses * 0.15); // -15% per loss
            lossReduction = MathMax(lossReduction, 0.5); // Floor at -50%
            adjustedRisk *= lossReduction;
            
            Print("[RISK] Risk reduced to ", NormalizeDouble(adjustedRisk, 2), 
                  "% due to ", m_consecutiveLosses, " consecutive losses");
        }
        
        // Cap at maximum risk per trade
        adjustedRisk = MathMin(adjustedRisk, m_maxRiskPerTrade);
        
        return adjustedRisk;
    }
    
    // Calculate lot size based on risk parameters
    double CalculateLotSize(const string &symbol, double stopLossPips) {
        // If trading is paused, return 0
        if(m_riskState == RISK_PAUSED) return 0.0;
        
        // Validate inputs
        if(stopLossPips <= 0) {
            Print("[ERROR] CalculateLotSize: Invalid stop loss pips: ", stopLossPips);
            return 0.0;
        }
        
        // Get symbol properties with validation
        CSymbolInfo symbolInfo;
        if(!symbolInfo.Name(symbol)) {
            Print("[ERROR] CalculateLotSize: Failed to get symbol info for ", symbol);
            return 0.0;
        }
        
        double point = symbolInfo.Point();
        double tickSize = symbolInfo.TickSize();
        double tickValue = symbolInfo.TickValue();
        double minLot = symbolInfo.LotsMin();
        double maxLot = symbolInfo.LotsMax();
        double lotStep = symbolInfo.LotsStep();
        
        // Calculate stop loss in price terms
        double slDistance = stopLossPips * point;
        
        // Get account balance and equity
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        
        // Get adjusted risk percentage
        double adjustedRiskPercent = GetAdjustedRiskPercent();
        
        // Calculate risk money
        double riskMoney = accountBalance * adjustedRiskPercent / 100.0;
        
        // Calculate lot size based on risk
        double calculatedLot = 0.0;
        if(slDistance > 0) {
            calculatedLot = riskMoney / (slDistance / tickSize * tickValue);
        }
        
        // Check existing positions for cumulative risk
        double totalRisk = CalculateTotalOpenRisk();
        double additionalRisk = adjustedRiskPercent;
        
        // Check if adding this trade would exceed total account risk
        if(totalRisk + additionalRisk > m_maxAccountRisk) {
            // Calculate maximum additional risk allowed
            double maxAdditionalRisk = m_maxAccountRisk - totalRisk;
            if(maxAdditionalRisk <= 0) {
                Print("[RISK] Maximum account risk of ", m_maxAccountRisk, 
                      "% already reached. Cannot open new position.");
                return 0.0;
            }
            
            // Adjust lot size to stay within total risk limit
            double riskRatio = maxAdditionalRisk / additionalRisk;
            calculatedLot *= riskRatio;
            
            Print("[RISK] Lot size reduced to stay within maximum account risk of ", 
                  m_maxAccountRisk, "%");
        }
        
        // Normalize lot size
        calculatedLot = MathMax(minLot, calculatedLot);
        calculatedLot = MathMin(maxLot, calculatedLot);
        calculatedLot = MathFloor(calculatedLot / lotStep) * lotStep;
        
        // ABSOLUTE SAFETY CAP: Never allow more than 10 lots regardless of account size
        double absoluteMaxLot = 10.0;
        calculatedLot = MathMin(calculatedLot, absoluteMaxLot);
        
        // Log calculated lot size
        Print("[RISK] Calculated lot size for ", symbol, ": ", NormalizeDouble(calculatedLot, 2), 
              " (risk: ", adjustedRiskPercent, "%, SL pips: ", stopLossPips, ")");
        
        return NormalizeDouble(calculatedLot, 2);
    }
    
    // Update trade result
    void UpdateTradeResult(bool isWin, double profit, double pips, 
                          const string &symbol, const string &strategy) {
        // Update consecutive win/loss counters
        if(isWin) {
            m_consecutiveWins++;
            m_consecutiveLosses = 0;
        } else {
            m_consecutiveLosses++;
            m_consecutiveWins = 0;
        }
        
        // Update daily P&L
        m_dailyPnL += profit;
        
        // Update trade history
        m_recentTrades[m_tradeHistoryIndex].isWin = isWin;
        m_recentTrades[m_tradeHistoryIndex].profit = profit;
        m_recentTrades[m_tradeHistoryIndex].pips = pips;
        m_recentTrades[m_tradeHistoryIndex].symbol = symbol;
        m_recentTrades[m_tradeHistoryIndex].strategy = strategy;
        m_recentTrades[m_tradeHistoryIndex].openTime = m_lastTradeTime;
        m_recentTrades[m_tradeHistoryIndex].closeTime = TimeCurrent();
        
        // Update index and count
        m_tradeHistoryIndex = (m_tradeHistoryIndex + 1) % 100;
        m_tradeHistoryCount = MathMin(m_tradeHistoryCount + 1, 100);
        
        // Update last trade time
        m_lastTradeTime = TimeCurrent();
        
        // Update risk state
        UpdateRiskState();
        
        // Log trade result
        Print("[TRADE RESULT] ", symbol, " ", strategy, ": ", 
              (isWin ? "WIN" : "LOSS"), " ", 
              NormalizeDouble(profit, 2), "$ (", 
              NormalizeDouble(pips, 1), " pips)");
    }
    
    // Check if trading is allowed
    bool IsTradingAllowed() {
        // Update risk state first
        UpdateRiskState();
        
        return (m_riskState != RISK_PAUSED);
    }
    
    // Get current risk state
    ENUM_RISK_STATE GetRiskState() const {
        return m_riskState;
    }
    
    // Get risk state description
    string GetRiskStateDescription() const {
        switch(m_riskState) {
            case RISK_NORMAL:
                return "Normal";
            case RISK_REDUCED:
                return "Reduced Risk";
            case RISK_PAUSED:
                return "Trading Paused";
            default:
                return "Unknown";
        }
    }
    
    // Get consecutive win/loss counts
    void GetStreakCounts(int &wins, int &losses) const {
        wins = m_consecutiveWins;
        losses = m_consecutiveLosses;
    }
    
    // Get daily P&L
    double GetDailyPnL() const {
        return m_dailyPnL;
    }
    
    // Get time remaining in circuit breaker (seconds)
    int GetCircuitBreakerTimeRemaining() const {
        if(m_riskState != RISK_PAUSED) return 0;
        
        int timeElapsed = (int)(TimeCurrent() - m_circuitBreakerTime);
        return MathMax(0, m_circuitBreakerDuration - timeElapsed);
    }
    
    // Print risk status report
    void PrintRiskReport() {
        double currentDrawdown = CalculateDrawdown();
        double totalRisk = CalculateTotalOpenRisk();
        
        Print("=== RISK MANAGEMENT REPORT ===");
        Print("Risk State: ", GetRiskStateDescription());
        Print("Current Drawdown: ", NormalizeDouble(currentDrawdown, 2), "%");
        Print("Total Open Risk: ", NormalizeDouble(totalRisk, 2), "% of ", m_maxAccountRisk, "% max");
        Print("Consecutive Wins: ", m_consecutiveWins);
        Print("Consecutive Losses: ", m_consecutiveLosses);
        Print("Daily P&L: ", NormalizeDouble(m_dailyPnL, 2), "$");
        
        if(m_riskState == RISK_PAUSED) {
            int minutesRemaining = GetCircuitBreakerTimeRemaining() / 60;
            Print("Circuit Breaker: Active for ", minutesRemaining, " more minutes");
        }
        
        Print("Adjusted Risk %: ", NormalizeDouble(GetAdjustedRiskPercent(), 2), "%");
        Print("==============================");
    }
};

#endif
