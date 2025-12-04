//+------------------------------------------------------------------+
//| Pre-Trade Validation Module                                      |
//+------------------------------------------------------------------+
#ifndef __PRE_TRADE_VALIDATOR_MQH__
#define __PRE_TRADE_VALIDATOR_MQH__

// Include required modules
#include <Trade\SymbolInfo.mqh>

// Validation result structure
struct SValidationResult {
    bool    isValid;            // Overall validation result
    string  message;            // Validation message or error
    double  adjustedStopLoss;   // Adjusted stop loss level if needed
    double  adjustedTakeProfit; // Adjusted take profit level if needed
    double  adjustedLotSize;    // Adjusted lot size if needed
    double  minStopDistance;    // Minimum stop distance in points
};

class CPreTradeValidator {
private:
    CSymbolInfo m_symbolInfo;   // Symbol information object
    double      m_riskPercent;  // Risk percentage per trade
    double      m_maxRiskPercent; // Maximum risk percentage per trade
    double      m_totalRiskPercent; // Maximum total account risk percentage
    
    // Calculate volatility-based buffer for stop levels
    double CalculateVolatilityBuffer(const string &symbol, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT) {
        // Use ATR to determine volatility
        int atrHandle = iATR(symbol, timeframe, 14);
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
        
        // Return the current ATR value with a minimum value to prevent zero
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        return MathMax(atrValues[0], point * 10);
    }
    
    // Detect instrument type for specialized handling
    enum ENUM_INSTRUMENT_TYPE {
        INST_FOREX,
        INST_SYNTHETIC,
        INST_CRYPTO,
        INST_COMMODITY,
        INST_INDEX,
        INST_STOCK
    };
    
    ENUM_INSTRUMENT_TYPE DetectInstrumentType(const string &symbol) {
        string description = SymbolInfoString(symbol, SYMBOL_DESCRIPTION);
        
        // Check for synthetic indices
        if(StringFind(symbol, "Volatility") >= 0 || 
           StringFind(symbol, "Step") >= 0 || 
           StringFind(symbol, "Range") >= 0 || 
           StringFind(symbol, "SYNTH:") >= 0 ||
           StringFind(description, "Synthetic") >= 0) {
            return INST_SYNTHETIC;
        }
        
        // Check for cryptocurrencies
        if(StringFind(symbol, "BTC") >= 0 || 
           StringFind(symbol, "ETH") >= 0 || 
           StringFind(description, "Crypto") >= 0) {
            return INST_CRYPTO;
        }
        
        // Check for commodities
        if(StringFind(symbol, "GOLD") >= 0 || 
           StringFind(symbol, "SILVER") >= 0 || 
           StringFind(symbol, "OIL") >= 0 ||
           StringFind(description, "Gold") >= 0 ||
           StringFind(description, "Silver") >= 0 ||
           StringFind(description, "Oil") >= 0) {
            return INST_COMMODITY;
        }
        
        // Check for indices
        if(StringFind(symbol, "US30") >= 0 || 
           StringFind(symbol, "US500") >= 0 || 
           StringFind(symbol, "NAS100") >= 0 ||
           StringFind(description, "Index") >= 0) {
            return INST_INDEX;
        }
        
        // Check for stocks
        if(StringFind(description, "Stock") >= 0 ||
           StringFind(description, "CFD") >= 0) {
            return INST_STOCK;
        }
        
        // Default to forex
        return INST_FOREX;
    }
    
    // Get instrument-specific volatility buffer percentage
    double GetVolatilityBufferPercentage(ENUM_INSTRUMENT_TYPE instrumentType) {
        switch(instrumentType) {
            case INST_SYNTHETIC:
                return 5.0;  // 500% of ATR for synthetic indices
            case INST_CRYPTO:
                return 3.0;  // 300% of ATR for cryptocurrencies
            case INST_COMMODITY:
                return 2.0;  // 200% of ATR for commodities
            case INST_INDEX:
                return 2.0;  // 200% of ATR for indices
            case INST_STOCK:
                return 2.5;  // 250% of ATR for stocks
            case INST_FOREX:
            default:
                return 2.0;  // 200% of ATR for forex
        }
    }
    
    // Get instrument-specific safety margin in points
    int GetSafetyMarginPoints(ENUM_INSTRUMENT_TYPE instrumentType) {
        switch(instrumentType) {
            case INST_SYNTHETIC:
                return 50;   // 50 points for synthetic indices
            case INST_CRYPTO:
                return 30;   // 30 points for cryptocurrencies
            case INST_COMMODITY:
                return 20;   // 20 points for commodities
            case INST_INDEX:
                return 25;   // 25 points for indices
            case INST_STOCK:
                return 20;   // 20 points for stocks
            case INST_FOREX:
            default:
                return 15;   // 15 points for forex
        }
    }
    
    // Simulate order placement to check for potential errors
    bool SimulateOrderPlacement(const string &symbol, int direction, double lotSize, 
                               double entryPrice, double stopLoss, double takeProfit, string &errorMsg) {
        // Check if trading is allowed
        if(!SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE)) {
            errorMsg = "Trading is not allowed for this symbol";
            return false;
        }
        
        // Check if we have enough money for this trade
        double margin = SymbolInfoDouble(symbol, SYMBOL_MARGIN_INITIAL) * lotSize;
        if(AccountInfoDouble(ACCOUNT_MARGIN_FREE) < margin) {
            errorMsg = "Not enough free margin for this trade";
            return false;
        }
        
        // Check if lot size is within allowed range
        double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        
        if(lotSize < minLot) {
            errorMsg = "Lot size is below minimum allowed (" + DoubleToString(minLot, 2) + ")";
            return false;
        }
        
        if(lotSize > maxLot) {
            errorMsg = "Lot size is above maximum allowed (" + DoubleToString(maxLot, 2) + ")";
            return false;
        }
        
        // Check if lot size is a multiple of lot step
        if(MathAbs(MathMod(lotSize, lotStep)) > 0.00001) {
            errorMsg = "Lot size is not a multiple of lot step (" + DoubleToString(lotStep, 2) + ")";
            return false;
        }
        
        // Check stop loss and take profit levels
        int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        int stopLevel = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
        double minStopDistance = stopLevel * point;
        
        if(direction > 0) { // Buy
            if(entryPrice - stopLoss < minStopDistance) {
                errorMsg = "Stop loss is too close to entry price (minimum: " + 
                          DoubleToString(minStopDistance / point, 1) + " points)";
                return false;
            }
            
            if(takeProfit - entryPrice < minStopDistance) {
                errorMsg = "Take profit is too close to entry price (minimum: " + 
                          DoubleToString(minStopDistance / point, 1) + " points)";
                return false;
            }
        }
        else if(direction < 0) { // Sell
            if(stopLoss - entryPrice < minStopDistance) {
                errorMsg = "Stop loss is too close to entry price (minimum: " + 
                          DoubleToString(minStopDistance / point, 1) + " points)";
                return false;
            }
            
            if(entryPrice - takeProfit < minStopDistance) {
                errorMsg = "Take profit is too close to entry price (minimum: " + 
                          DoubleToString(minStopDistance / point, 1) + " points)";
                return false;
            }
        }
        
        // All checks passed
        return true;
    }
    
    // Calculate total account risk from existing positions
    double CalculateTotalAccountRisk() {
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

public:
    CPreTradeValidator() {
        m_riskPercent = 1.0;
        m_maxRiskPercent = 2.0;
        m_totalRiskPercent = 6.0;
    }
    
    // Set risk parameters
    void SetRiskParameters(double riskPercent, double maxRiskPercent, double totalRiskPercent) {
        m_riskPercent = riskPercent;
        m_maxRiskPercent = maxRiskPercent;
        m_totalRiskPercent = totalRiskPercent;
    }
    
    // Validate trade parameters and adjust if necessary
    SValidationResult ValidateTrade(const string &symbol, int direction, double lotSize, 
                                   double stopLossPips, double takeProfitPips) {
        SValidationResult result;
        result.isValid = false;
        result.adjustedLotSize = lotSize;
        
        // Initialize symbol info
        if(!m_symbolInfo.Name(symbol)) {
            result.message = "Failed to get symbol info for " + symbol;
            return result;
        }
        
        // Get symbol properties
        double point = m_symbolInfo.Point();
        double ask = m_symbolInfo.Ask();
        double bid = m_symbolInfo.Bid();
        int digits = m_symbolInfo.Digits();
        double tickSize = m_symbolInfo.TickSize();
        double tickValue = m_symbolInfo.TickValue();
        
        // Detect instrument type
        ENUM_INSTRUMENT_TYPE instrumentType = DetectInstrumentType(symbol);
        
        // Calculate minimum stop distance based on broker requirements and volatility
        int stopLevel = (int)m_symbolInfo.StopsLevel();
        int freezeLevel = (int)m_symbolInfo.FreezeLevel();
        int minLevel = MathMax(stopLevel, freezeLevel);
        
        // Add safety margin based on instrument type
        minLevel += GetSafetyMarginPoints(instrumentType);
        
        // Calculate volatility-based buffer
        double atr = CalculateVolatilityBuffer(symbol);
        double volatilityBufferPercentage = GetVolatilityBufferPercentage(instrumentType);
        double volatilityBuffer = atr * volatilityBufferPercentage;
        
        // Calculate minimum stop distance in price terms
        double minDistancePoints = MathMax(minLevel, volatilityBuffer / point);
        result.minStopDistance = minDistancePoints;
        
        // Convert stop loss and take profit from pips to price
        double slDistance = stopLossPips * point;
        double tpDistance = takeProfitPips * point;
        
        // Entry price based on direction
        double entryPrice = (direction > 0) ? ask : bid;
        
        // Calculate initial stop loss and take profit levels
        double stopLoss = (direction > 0) ? entryPrice - slDistance : entryPrice + slDistance;
        double takeProfit = (direction > 0) ? entryPrice + tpDistance : entryPrice - tpDistance;
        
        // Check if stop distance is sufficient
        double actualStopDistance = (direction > 0) ? entryPrice - stopLoss : stopLoss - entryPrice;
        double minStopDistancePrice = minDistancePoints * point;
        
        // Adjust stop loss if needed
        if(actualStopDistance < minStopDistancePrice) {
            if(direction > 0) {
                stopLoss = entryPrice - minStopDistancePrice;
            } else {
                stopLoss = entryPrice + minStopDistancePrice;
            }
            
            result.message += "Stop loss adjusted to meet minimum distance requirement. ";
        }
        
        // Check if take profit distance is sufficient
        double actualTpDistance = (direction > 0) ? takeProfit - entryPrice : entryPrice - takeProfit;
        
        // Adjust take profit if needed
        if(actualTpDistance < minStopDistancePrice) {
            if(direction > 0) {
                takeProfit = entryPrice + minStopDistancePrice;
            } else {
                takeProfit = entryPrice - minStopDistancePrice;
            }
            
            result.message += "Take profit adjusted to meet minimum distance requirement. ";
        }
        
        // Calculate risk amount
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double currentDrawdown = (accountBalance - equity) / accountBalance * 100.0;
        
        // Calculate risk percentage with dynamic adjustment based on drawdown
        double adjustedRiskPercent = m_riskPercent;
        
        // Reduce risk during drawdown periods
        if(currentDrawdown > 0) {
            // Linear reduction: at 5% drawdown risk is 100%, at 10% drawdown risk is 25%
            double reductionFactor = 1.0 - 0.75 * MathMin(currentDrawdown, 10.0) / 10.0;
            adjustedRiskPercent *= reductionFactor;
            
            result.message += "Risk reduced to " + DoubleToString(adjustedRiskPercent, 2) + 
                             "% due to current drawdown of " + DoubleToString(currentDrawdown, 2) + "%. ";
        }
        
        // Cap risk at maximum per trade
        adjustedRiskPercent = MathMin(adjustedRiskPercent, m_maxRiskPercent);
        
        // Calculate risk money
        double riskMoney = accountBalance * adjustedRiskPercent / 100.0;
        
        // Calculate lot size based on risk
        double calculatedLot = 0.0;
        double actualStopLossPips = (direction > 0) ? (entryPrice - stopLoss) / point : (stopLoss - entryPrice) / point;
        
        if(actualStopLossPips > 0) {
            calculatedLot = riskMoney / (actualStopLossPips * point / tickSize * tickValue);
        }
        
        // Check existing positions for cumulative risk
        double totalRisk = CalculateTotalAccountRisk();
        double additionalRisk = (riskMoney / accountBalance) * 100.0;
        
        // Check if adding this trade would exceed total account risk
        if(totalRisk + additionalRisk > m_totalRiskPercent) {
            // Calculate maximum additional risk allowed
            double maxAdditionalRisk = m_totalRiskPercent - totalRisk;
            if(maxAdditionalRisk <= 0) {
                result.message = "Maximum account risk of " + DoubleToString(m_totalRiskPercent, 2) + 
                                "% already reached. Cannot open new position.";
                return result;
            }
            
            // Adjust lot size to stay within total risk limit
            double riskRatio = maxAdditionalRisk / additionalRisk;
            calculatedLot *= riskRatio;
            
            result.message += "Lot size reduced to stay within maximum account risk of " + 
                             DoubleToString(m_totalRiskPercent, 2) + "%. ";
        }
        
        // Normalize lot size according to symbol requirements
        double minLot = m_symbolInfo.LotsMin();
        double maxLot = m_symbolInfo.LotsMax();
        double lotStep = m_symbolInfo.LotsStep();
        
        calculatedLot = MathMax(minLot, calculatedLot);
        calculatedLot = MathMin(maxLot, calculatedLot);
        calculatedLot = MathFloor(calculatedLot / lotStep) * lotStep;
        
        // Use the smaller of calculated lot and provided lot
        double finalLotSize = (calculatedLot < lotSize) ? calculatedLot : lotSize;
        
        // Simulate order placement to check for potential errors
        string errorMsg;
        if(!SimulateOrderPlacement(symbol, direction, finalLotSize, entryPrice, stopLoss, takeProfit, errorMsg)) {
            result.message = "Pre-trade validation failed: " + errorMsg;
            return result;
        }
        
        // Set adjusted values
        result.isValid = true;
        result.adjustedStopLoss = NormalizeDouble(stopLoss, digits);
        result.adjustedTakeProfit = NormalizeDouble(takeProfit, digits);
        result.adjustedLotSize = NormalizeDouble(finalLotSize, 2);
        
        if(StringLen(result.message) == 0) {
            result.message = "Trade validated successfully.";
        } else {
            result.message = "Trade validated with adjustments: " + result.message;
        }
        
        return result;
    }
};

#endif
