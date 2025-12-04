//+------------------------------------------------------------------+
//| Dynamic Exit Management Module                                    |
//+------------------------------------------------------------------+
#ifndef __DYNAMIC_EXIT_MANAGER_MQH__
#define __DYNAMIC_EXIT_MANAGER_MQH__

// Include required modules
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

// Exit strategy types
enum ENUM_EXIT_STRATEGY {
    EXIT_FIXED,             // Fixed take profit and stop loss
    EXIT_TRAILING,          // Trailing stop
    EXIT_PARTIAL,           // Partial profit taking
    EXIT_TIME_BASED,        // Time-based exit
    EXIT_VOLATILITY,        // Volatility-based exit
    EXIT_SUPPORT_RESISTANCE // Support/resistance based exit
};

// Exit rule structure
struct SExitRule {
    ENUM_EXIT_STRATEGY strategy;    // Exit strategy type
    double parameters[];            // Strategy-specific parameters
    bool isEnabled;                 // Whether this rule is enabled
};

// Exit plan structure
struct SExitPlan {
    SExitRule rules[];              // Array of exit rules
    int activeRuleIndex;            // Index of currently active rule
    datetime planCreationTime;      // Time when the plan was created
    datetime lastUpdateTime;        // Time of last update
};

// Structure for parameters passed when registering a new trade for dynamic exit management
struct STradeExitParams {
    int    tradeStyle;          // Corresponds to ENUM_TRADE_STYLE (e.g., SCALP, SWING, TREND)
    double initialSLPips;
    double initialTPPips;
    double breakEvenPips;       // Pips in profit to move SL to BreakEven
    double trailingStartPips;   // Pips in profit to start trailing SL
    double trailingStepPips;    // Pips to trail SL by
    double minProfitLockPips;   // Minimum profit pips to lock when SL moves
    // Add any other parameters needed by exit strategies
};

class CDynamicExitManager {
private:
    CTrade m_trade;                 // Trade object for order operations
    CSymbolInfo m_symbolInfo;       // Symbol information
    
    // Collection of exit plans for open positions
    SExitPlan m_exitPlans[];        // Indexed by position ticket
    
    // Create trailing stop exit rule
    SExitRule CreateTrailingStopRule(double activationPips, double trailingPips) {
        SExitRule rule;
        rule.strategy = EXIT_TRAILING;
        ArrayResize(rule.parameters, 2);
        rule.parameters[0] = activationPips;  // Pips in profit before trailing starts
        rule.parameters[1] = trailingPips;    // Trailing distance in pips
        rule.isEnabled = true;
        return rule;
    }
    
    // Create partial profit taking exit rule
    SExitRule CreatePartialProfitRule(double profitPips, double percentToClose) {
        SExitRule rule;
        rule.strategy = EXIT_PARTIAL;
        ArrayResize(rule.parameters, 2);
        rule.parameters[0] = profitPips;      // Pips in profit to trigger partial close
        rule.parameters[1] = percentToClose;  // Percentage of position to close
        rule.isEnabled = true;
        return rule;
    }
    
    // Create time-based exit rule
    SExitRule CreateTimeBasedRule(int maxHoldTimeHours) {
        SExitRule rule;
        rule.strategy = EXIT_TIME_BASED;
        ArrayResize(rule.parameters, 1);
        rule.parameters[0] = maxHoldTimeHours; // Maximum hold time in hours
        rule.isEnabled = true;
        return rule;
    }
    
    // Create volatility-based exit rule
    SExitRule CreateVolatilityRule(double atrMultiplier) {
        SExitRule rule;
        rule.strategy = EXIT_VOLATILITY;
        ArrayResize(rule.parameters, 1);
        rule.parameters[0] = atrMultiplier;    // ATR multiplier for stop distance
        rule.isEnabled = true;
        return rule;
    }
    
    // Create support/resistance based exit rule
    SExitRule CreateSupportResistanceRule(double levelBuffer) {
        SExitRule rule;
        rule.strategy = EXIT_SUPPORT_RESISTANCE;
        ArrayResize(rule.parameters, 1);
        rule.parameters[0] = levelBuffer;      // Buffer around S/R levels in pips
        rule.isEnabled = true;
        return rule;
    }
    
    // Calculate ATR value for a symbol
    double CalculateATR(const string &symbol, ENUM_TIMEFRAMES timeframe, int period) {
        int atrHandle = iATR(symbol, timeframe, period);
        if(atrHandle == INVALID_HANDLE) {
            Print("[ERROR] Failed to create ATR indicator handle: ", GetLastError());
            return 0.0;
        }
        
        double atrValues[1];
        if(CopyBuffer(atrHandle, 0, 0, 1, atrValues) <= 0) {
            Print("[ERROR] Failed to copy ATR values: ", GetLastError());
            IndicatorRelease(atrHandle);
            return 0.0;
        }
        
        IndicatorRelease(atrHandle);
        return atrValues[0];
    }
    
    // Find support and resistance levels
    bool FindSupportResistanceLevels(const string &symbol, ENUM_TIMEFRAMES timeframe, 
                                    double &supportLevel, double &resistanceLevel) {
        // Get recent price data
        MqlRates rates[];
        if(CopyRates(symbol, timeframe, 0, 100, rates) <= 0) {
            Print("[ERROR] Failed to copy rates for ", symbol);
            return false;
        }
        
        // Find local minima and maxima
        double localMinima[10], localMaxima[10];
        int minimaCount = 0, maximaCount = 0;
        
        for(int i = 2; i < ArraySize(rates) - 2; i++) {
            // Check for local minimum
            if(rates[i].low < rates[i-1].low && rates[i].low < rates[i-2].low && 
               rates[i].low < rates[i+1].low && rates[i].low < rates[i+2].low) {
                if(minimaCount < 10) {
                    localMinima[minimaCount++] = rates[i].low;
                }
            }
            
            // Check for local maximum
            if(rates[i].high > rates[i-1].high && rates[i].high > rates[i-2].high && 
               rates[i].high > rates[i+1].high && rates[i].high > rates[i+2].high) {
                if(maximaCount < 10) {
                    localMaxima[maximaCount++] = rates[i].high;
                }
            }
        }
        
        // If we found at least one minimum and maximum, use the most recent ones
        if(minimaCount > 0 && maximaCount > 0) {
            supportLevel = localMinima[minimaCount - 1];
            resistanceLevel = localMaxima[maximaCount - 1];
            return true;
        }
        
        return false;
    }
    
    // Apply trailing stop exit rule
    bool ApplyTrailingStopRule(ulong ticket, const SExitRule &rule) {
        if(!PositionSelectByTicket(ticket)) {
            Print("[ERROR] ApplyTrailingStopRule: Position not found for ticket ", ticket);
            return false;
        }
        
        // Get position details
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        double stopLoss = PositionGetDouble(POSITION_SL);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        string symbol = PositionGetString(POSITION_SYMBOL);
        
        // Get parameters
        double activationPips = rule.parameters[0];
        double trailingPips = rule.parameters[1];
        
        // Convert to price
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double activationDistance = activationPips * point;
        double trailingDistance = trailingPips * point;
        
        // Check if we're in profit enough to activate trailing
        bool inProfitEnough = false;
        if(posType == POSITION_TYPE_BUY) {
            inProfitEnough = (currentPrice - openPrice >= activationDistance);
        } else {
            inProfitEnough = (openPrice - currentPrice >= activationDistance);
        }
        
        // If not in profit enough, do nothing
        if(!inProfitEnough) return false;
        
        // Calculate new stop loss level
        double newStopLoss = 0.0;
        if(posType == POSITION_TYPE_BUY) {
            newStopLoss = currentPrice - trailingDistance;
            // Only move stop loss up
            if(stopLoss == 0 || newStopLoss > stopLoss) {
                return m_trade.PositionModify(ticket, newStopLoss, PositionGetDouble(POSITION_TP));
            }
        } else {
            newStopLoss = currentPrice + trailingDistance;
            // Only move stop loss down
            if(stopLoss == 0 || newStopLoss < stopLoss) {
                return m_trade.PositionModify(ticket, newStopLoss, PositionGetDouble(POSITION_TP));
            }
        }
        
        return false;
    }
    
    // Apply partial profit taking exit rule
    bool ApplyPartialProfitRule(ulong ticket, const SExitRule &rule) {
        if(!PositionSelectByTicket(ticket)) {
            Print("[ERROR] ApplyPartialProfitRule: Position not found for ticket ", ticket);
            return false;
        }
        
        // Get position details
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        double volume = PositionGetDouble(POSITION_VOLUME);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        string symbol = PositionGetString(POSITION_SYMBOL);
        
        // Get parameters
        double profitPips = rule.parameters[0];
        double percentToClose = rule.parameters[1];
        
        // Convert to price
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double profitDistance = profitPips * point;
        
        // Check if we're in profit enough to take partial profits
        bool inProfitEnough = false;
        if(posType == POSITION_TYPE_BUY) {
            inProfitEnough = (currentPrice - openPrice >= profitDistance);
        } else {
            inProfitEnough = (openPrice - currentPrice >= profitDistance);
        }
        
        // If not in profit enough, do nothing
        if(!inProfitEnough) return false;
        
        // Calculate volume to close
        double volumeToClose = volume * percentToClose / 100.0;
        
        // Ensure volume is valid
        double minVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double maxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double volumeStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        
        volumeToClose = MathMax(minVolume, volumeToClose);
        volumeToClose = MathMin(volumeToClose, volume); // Don't close more than we have
        volumeToClose = MathFloor(volumeToClose / volumeStep) * volumeStep; // Round to volume step
        
        // Close partial position
        if(volumeToClose >= minVolume) {
            if(posType == POSITION_TYPE_BUY) {
                return m_trade.Sell(volumeToClose, symbol, 0, 0, 0, "Partial profit taking");
            } else {
                return m_trade.Buy(volumeToClose, symbol, 0, 0, 0, "Partial profit taking");
            }
        }
        
        return false;
    }
    
    // Apply time-based exit rule
    bool ApplyTimeBasedRule(ulong ticket, const SExitRule &rule) {
        if(!PositionSelectByTicket(ticket)) {
            Print("[ERROR] ApplyTimeBasedRule: Position not found for ticket ", ticket);
            return false;
        }
        
        // Get position details
        datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
        string symbol = PositionGetString(POSITION_SYMBOL);
        
        // Get parameters
        int maxHoldTimeHours = (int)rule.parameters[0];
        
        // Calculate time difference in hours
        int hoursSinceOpen = (int)(TimeCurrent() - openTime) / 3600;
        
        // Check if we've held the position long enough to exit
        if(hoursSinceOpen >= maxHoldTimeHours) {
            Print("[INFO] Time-based exit triggered for ", symbol, " after ", hoursSinceOpen, " hours");
            return m_trade.PositionClose(ticket);
        }
        
        return false;
    }
    
    // Apply volatility-based exit rule
    bool ApplyVolatilityRule(ulong ticket, const SExitRule &rule) {
        if(!PositionSelectByTicket(ticket)) {
            Print("[ERROR] ApplyVolatilityRule: Position not found for ticket ", ticket);
            return false;
        }
        
        // Get position details
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
        double stopLoss = PositionGetDouble(POSITION_SL);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        string symbol = PositionGetString(POSITION_SYMBOL);
        
        // Get parameters
        double atrMultiplier = rule.parameters[0];
        
        // Calculate ATR
        double atr = CalculateATR(symbol, PERIOD_CURRENT, 14);
        
        // Calculate new stop loss based on ATR
        double newStopLoss = 0.0;
        if(posType == POSITION_TYPE_BUY) {
            newStopLoss = currentPrice - (atr * atrMultiplier);
            // Only move stop loss up
            if(stopLoss == 0 || newStopLoss > stopLoss) {
                return m_trade.PositionModify(ticket, newStopLoss, PositionGetDouble(POSITION_TP));
            }
        } else {
            newStopLoss = currentPrice + (atr * atrMultiplier);
            // Only move stop loss down
            if(stopLoss == 0 || newStopLoss < stopLoss) {
                return m_trade.PositionModify(ticket, newStopLoss, PositionGetDouble(POSITION_TP));
            }
        }
        
        return false;
    }
    
    // Apply support/resistance based exit rule
    bool ApplySupportResistanceRule(ulong ticket, const SExitRule &rule) {
        if(!PositionSelectByTicket(ticket)) {
            Print("[ERROR] ApplySupportResistanceRule: Position not found for ticket ", ticket);
            return false;
        }
        
        // Get position details
        double takeProfit = PositionGetDouble(POSITION_TP);
        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        string symbol = PositionGetString(POSITION_SYMBOL);
        
        // Get parameters
        double levelBuffer = rule.parameters[0];
        
        // Find support and resistance levels
        double supportLevel = 0.0, resistanceLevel = 0.0;
        if(!FindSupportResistanceLevels(symbol, PERIOD_CURRENT, supportLevel, resistanceLevel)) {
            return false;
        }
        
        // Convert buffer to price
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double bufferDistance = levelBuffer * point;
        
        // Calculate new take profit based on support/resistance
        double newTakeProfit = 0.0;
        if(posType == POSITION_TYPE_BUY) {
            // For buy positions, use resistance as take profit
            newTakeProfit = resistanceLevel - bufferDistance;
            // Only modify if new TP is better than current
            if(takeProfit == 0 || (newTakeProfit > 0 && newTakeProfit < takeProfit)) {
                return m_trade.PositionModify(ticket, PositionGetDouble(POSITION_SL), newTakeProfit);
            }
        } else {
            // For sell positions, use support as take profit
            newTakeProfit = supportLevel + bufferDistance;
            // Only modify if new TP is better than current
            if(takeProfit == 0 || (newTakeProfit > 0 && newTakeProfit > takeProfit)) {
                return m_trade.PositionModify(ticket, PositionGetDouble(POSITION_SL), newTakeProfit);
            }
        }
        
        return false;
    }
    
    // Apply exit rule based on its type
    bool ApplyExitRule(ulong ticket, const SExitRule &rule) {
        if(!rule.isEnabled) return false;
        
        switch(rule.strategy) {
            case EXIT_TRAILING:
                return ApplyTrailingStopRule(ticket, rule);
            case EXIT_PARTIAL:
                return ApplyPartialProfitRule(ticket, rule);
            case EXIT_TIME_BASED:
                return ApplyTimeBasedRule(ticket, rule);
            case EXIT_VOLATILITY:
                return ApplyVolatilityRule(ticket, rule);
            case EXIT_SUPPORT_RESISTANCE:
                return ApplySupportResistanceRule(ticket, rule);
            default:
                return false;
        }
    }
    
public:
    CDynamicExitManager() {
        // Initialize trade object
        m_trade.SetDeviationInPoints(10); // 1 pip deviation
        m_trade.SetTypeFilling(ORDER_FILLING_FOK);
        m_trade.SetAsyncMode(false);
    }
    
    // Initialize with default settings
    void Initialize() {
        // Nothing to initialize yet
    }
    
    // Create exit plan for a new position
    bool CreateExitPlan(ulong ticket, ENUM_POSITION_TYPE posType, const string &symbol, 
                       const string &strategy) {
        // Find index for this ticket
        int index = -1;
        for(int i = 0; i < ArraySize(m_exitPlans); i++) {
            if(i == ticket % 1000) { // Use modulo to keep array size reasonable
                index = i;
                break;
            }
        }
        
        // If not found, resize array
        if(index < 0) {
            index = ArraySize(m_exitPlans);
            ArrayResize(m_exitPlans, index + 1);
        }
        
        // Initialize exit plan
        m_exitPlans[index].activeRuleIndex = 0;
        m_exitPlans[index].planCreationTime = TimeCurrent();
        m_exitPlans[index].lastUpdateTime = TimeCurrent();
        
        // Create exit rules based on strategy and position type
        ArrayResize(m_exitPlans[index].rules, 0); // Clear existing rules
        
        // Add trailing stop rule
        ArrayResize(m_exitPlans[index].rules, ArraySize(m_exitPlans[index].rules) + 1);
        m_exitPlans[index].rules[ArraySize(m_exitPlans[index].rules) - 1] = CreateTrailingStopRule(50, 20);
        
        // Add partial profit rule
        ArrayResize(m_exitPlans[index].rules, ArraySize(m_exitPlans[index].rules) + 1);
        m_exitPlans[index].rules[ArraySize(m_exitPlans[index].rules) - 1] = CreatePartialProfitRule(30, 50);
        
        // Add time-based rule
        ArrayResize(m_exitPlans[index].rules, ArraySize(m_exitPlans[index].rules) + 1);
        m_exitPlans[index].rules[ArraySize(m_exitPlans[index].rules) - 1] = CreateTimeBasedRule(48); // 48 hours max
        
        // Add volatility-based rule
        ArrayResize(m_exitPlans[index].rules, ArraySize(m_exitPlans[index].rules) + 1);
        m_exitPlans[index].rules[ArraySize(m_exitPlans[index].rules) - 1] = CreateVolatilityRule(2.0);
        
        // Add support/resistance rule
        ArrayResize(m_exitPlans[index].rules, ArraySize(m_exitPlans[index].rules) + 1);
        m_exitPlans[index].rules[ArraySize(m_exitPlans[index].rules) - 1] = CreateSupportResistanceRule(5);
        
        Print("[INFO] Created exit plan for ticket ", ticket, " with ", 
              ArraySize(m_exitPlans[index].rules), " rules");
        
        return true;
    }
    
    // Create custom exit plan with specific rules
    bool CreateCustomExitPlan(ulong ticket, const SExitRule &rules[], int ruleCount) {
        // Find index for this ticket
        int index = -1;
        for(int i = 0; i < ArraySize(m_exitPlans); i++) {
            if(i == ticket % 1000) { // Use modulo to keep array size reasonable
                index = i;
                break;
            }
        }
        
        // If not found, resize array
        if(index < 0) {
            index = ArraySize(m_exitPlans);
            ArrayResize(m_exitPlans, index + 1);
        }
        
        // Initialize exit plan
        m_exitPlans[index].activeRuleIndex = 0;
        m_exitPlans[index].planCreationTime = TimeCurrent();
        m_exitPlans[index].lastUpdateTime = TimeCurrent();
        
        // Copy exit rules
        ArrayResize(m_exitPlans[index].rules, ruleCount);
        for(int i = 0; i < ruleCount; i++) {
            m_exitPlans[index].rules[i] = rules[i];
        }
        
        Print("[INFO] Created custom exit plan for ticket ", ticket, " with ", ruleCount, " rules");
        
        return true;
    }
    
    // Process exit plans for all open positions
    void ProcessExitPlans() {
        // Loop through all open positions
        for(int i = 0; i < PositionsTotal(); i++) {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            // Find exit plan for this ticket
            int index = -1;
            for(int j = 0; j < ArraySize(m_exitPlans); j++) {
                if(j == ticket % 1000) { // Use modulo to keep array size reasonable
                    index = j;
                    break;
                }
            }
            
            // If no exit plan exists, create one
            if(index < 0 || ArraySize(m_exitPlans[index].rules) == 0) {
                string symbol = PositionGetString(POSITION_SYMBOL);
                ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                string strategy = PositionGetString(POSITION_COMMENT);
                
                CreateExitPlan(ticket, posType, symbol, strategy);
                
                // Find the index again
                for(int j = 0; j < ArraySize(m_exitPlans); j++) {
                    if(j == ticket % 1000) {
                        index = j;
                        break;
                    }
                }
                
                // If still not found, skip this position
                if(index < 0) continue;
            }
            
            // Apply all exit rules
            bool ruleApplied = false;
            for(int j = 0; j < ArraySize(m_exitPlans[index].rules); j++) {
                if(ApplyExitRule(ticket, m_exitPlans[index].rules[j])) {
                    m_exitPlans[index].activeRuleIndex = j;
                    m_exitPlans[index].lastUpdateTime = TimeCurrent();
                    ruleApplied = true;
                    
                    Print("[INFO] Exit rule ", j, " (", 
                          GetExitStrategyName(m_exitPlans[index].rules[j].strategy), 
                          ") applied to ticket ", ticket);
                    
                    break; // Only apply one rule per cycle
                }
            }
            
            // If no rule was applied, check if we need to create a new plan
            if(!ruleApplied && TimeCurrent() - m_exitPlans[index].lastUpdateTime > 86400) { // 24 hours
                string symbol = PositionGetString(POSITION_SYMBOL);
                ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                string strategy = PositionGetString(POSITION_COMMENT);
                
                CreateExitPlan(ticket, posType, symbol, strategy);
                
                Print("[INFO] Refreshed exit plan for ticket ", ticket, " after 24 hours of inactivity");
            }
        }
    }
    
    // Get exit strategy name
    string GetExitStrategyName(ENUM_EXIT_STRATEGY strategy) {
        switch(strategy) {
            case EXIT_FIXED:
                return "Fixed TP/SL";
            case EXIT_TRAILING:
                return "Trailing Stop";
            case EXIT_PARTIAL:
                return "Partial Profit Taking";
            case EXIT_TIME_BASED:
                return "Time-Based Exit";
            case EXIT_VOLATILITY:
                return "Volatility-Based Exit";
            case EXIT_SUPPORT_RESISTANCE:
                return "Support/Resistance Exit";
            default:
                return "Unknown";
        }
    }
    
    // Print exit plans status
    void PrintExitPlansStatus() {
        Print("=== DYNAMIC EXIT PLANS STATUS ===");
        int activePlans = 0;
        
        for(int i = 0; i < ArraySize(m_exitPlans); i++) {
            if(ArraySize(m_exitPlans[i].rules) > 0) {
                activePlans++;
                
                Print("Plan #", i, ": Created ", TimeToString(m_exitPlans[i].planCreationTime), 
                     ", Last update ", TimeToString(m_exitPlans[i].lastUpdateTime), 
                     ", Active rule: ", m_exitPlans[i].activeRuleIndex, " (", 
                     GetExitStrategyName(m_exitPlans[i].rules[m_exitPlans[i].activeRuleIndex].strategy), ")");
            }
        }
        
        Print("Total active plans: ", activePlans);
        Print("===============================");
    }
};

#endif
