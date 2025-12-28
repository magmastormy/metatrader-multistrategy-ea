//+------------------------------------------------------------------+
//| Intelligent Risk Management Functions                            |
//| Emergency fixes for catastrophic EA performance                  |
//+------------------------------------------------------------------+

#include "Core/Utils/Enums.mqh"
#include "Core/StrategyManager.mqh"

// Note: These globals are defined in MultiStrategyAutonomousEA.mq5
// No extern needed in MQL5 - just reference them directly
CPositionInfo m_positionInfo; // Instance for position checking (defined here, used in DirectTradeExecution.mqh)

const double RISK_DEFAULT_CONFIDENCE_FLOOR   = 0.3;
const double RISK_MAX_DRAWDOWN_BLOCK        = 15.0;
const double RISK_MIN_ACCOUNT_BALANCE       = 50.0;
const double RISK_DEFAULT_MAX_RISK          = 2.0;
const double RISK_DEFAULT_MAX_PORTFOLIO     = 10.0;
const double RISK_DEFAULT_MAX_LOT           = 0.5;
const double RISK_DRAWDOWN_REDUCE_THRESHOLD = 5.0;

// Shared risk configuration constants (defined in MultiStrategyAutonomousEA.mq5)

//+------------------------------------------------------------------+
//| Update current drawdown status                                   |
//+------------------------------------------------------------------+
void UpdateDrawdownStatus()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    if(balance > 0) {
        g_currentDrawdown = ((balance - equity) / balance) * 100.0;
    }
    
    // Log significant drawdown changes
    static double lastDrawdown = 0.0;
    if(MathAbs(g_currentDrawdown - lastDrawdown) > 1.0) {
        Print("[RISK] Current drawdown: ", DoubleToString(g_currentDrawdown, 2), "%");
        lastDrawdown = g_currentDrawdown;
    }
}

//+------------------------------------------------------------------+
//| Update market regime detection                                   |
//+------------------------------------------------------------------+
void UpdateMarketRegime()
{
    // 🛡�?SURGICAL FIX: Use static handles to prevent indicator handle leaks
    static int atrHandle = INVALID_HANDLE;
    static int ma20Handle = INVALID_HANDLE;
    static int ma50Handle = INVALID_HANDLE;
    
    // Initialize handles only once
    if(atrHandle == INVALID_HANDLE) {
        atrHandle = iATR(_Symbol, PERIOD_H1, 14);
        ma20Handle = iMA(_Symbol, PERIOD_H1, 20, 0, MODE_EMA, PRICE_CLOSE);
        ma50Handle = iMA(_Symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
        
        if(atrHandle == INVALID_HANDLE || ma20Handle == INVALID_HANDLE || ma50Handle == INVALID_HANDLE) {
            Print("🚨 [SURGICAL-ERROR] Failed to create indicator handles for market regime detection");
            return;
        }
    }
    
    double atrBuffer[1], ma20Buffer[1], ma50Buffer[1];
    if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) <= 0 ||
       CopyBuffer(ma20Handle, 0, 0, 1, ma20Buffer) <= 0 ||
       CopyBuffer(ma50Handle, 0, 0, 1, ma50Buffer) <= 0) {
        return;
    }
    
    double atr = atrBuffer[0];
    double ma20 = ma20Buffer[0];
    double ma50 = ma50Buffer[0];
    double priceBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    
    // Determine regime
    ENUM_MARKET_REGIME newRegime = MARKET_REGIME_UNKNOWN;
    
    double volatilityThreshold = SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 100;
    if(atr > volatilityThreshold)
    {
        const bool bullishTrend = (ma20 > ma50 && priceBid > ma20);
        const bool bearishTrend = (ma20 < ma50 && priceBid < ma20);

        if(bullishTrend || bearishTrend)
            newRegime = MARKET_REGIME_TRENDING;
        else
            newRegime = MARKET_REGIME_VOLATILE;
    }
    else
    {
        newRegime = MARKET_REGIME_RANGING;
    }
    
    // Update regime if changed
    if(newRegime != g_currentRegime) {
        g_currentRegime = newRegime;
        Print("[REGIME] Market regime changed to: ", EnumToString(g_currentRegime));
    }
}

//+------------------------------------------------------------------+
//| Update correlation matrix for major pairs                        |
//+------------------------------------------------------------------+
void UpdateCorrelationMatrix()
{
    string pairs[] = {"EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "USDCHF", "NZDUSD", "EURJPY", "GBPJPY", "AUDJPY"};
    int pairCount = ArraySize(pairs);
    
    // Calculate correlation for each pair combination
    for(int i = 0; i < pairCount; i++) {
        for(int j = 0; j < pairCount; j++) {
            if(i == j) {
                g_correlationMatrix[i][j] = 1.0; // Perfect correlation with itself
                continue;
            }
            
            // Calculate simple correlation based on recent price movements
            double correlation = CalculatePairCorrelation(pairs[i], pairs[j]);
            g_correlationMatrix[i][j] = correlation;
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate correlation between two currency pairs                 |
//+------------------------------------------------------------------+
double CalculatePairCorrelation(string pair1, string pair2)
{
    // Simple correlation calculation using last 20 bars
    double returns1[20], returns2[20];
    
    // Get price data for both pairs
    for(int i = 0; i < 20; i++) {
        double close1_current = iClose(pair1, PERIOD_H1, i);
        double close1_prev = iClose(pair1, PERIOD_H1, i + 1);
        double close2_current = iClose(pair2, PERIOD_H1, i);
        double close2_prev = iClose(pair2, PERIOD_H1, i + 1);
        
        if(close1_prev != 0 && close2_prev != 0) {
            returns1[i] = (close1_current - close1_prev) / close1_prev;
            returns2[i] = (close2_current - close2_prev) / close2_prev;
        } else {
            returns1[i] = 0;
            returns2[i] = 0;
        }
    }
    
    // Calculate correlation coefficient
    double sum1 = 0, sum2 = 0, sum1sq = 0, sum2sq = 0, sumProduct = 0;
    
    for(int i = 0; i < 20; i++) {
        sum1 += returns1[i];
        sum2 += returns2[i];
        sum1sq += returns1[i] * returns1[i];
        sum2sq += returns2[i] * returns2[i];
        sumProduct += returns1[i] * returns2[i];
    }
    
    double numerator = (20 * sumProduct) - (sum1 * sum2);
    double denominator = MathSqrt((20 * sum1sq - sum1 * sum1) * (20 * sum2sq - sum2 * sum2));
    
    if(denominator == 0) return 0;
    
    return numerator / denominator;
}

//+------------------------------------------------------------------+
//| Check if symbol has highly correlated position                   |
//+------------------------------------------------------------------+
bool HasHighlyCorrelatedPosition(string symbol)
{
    string pairs[] = {"EURUSD", "GBPUSD", "USDJPY", "AUDUSD", "USDCAD", "USDCHF", "NZDUSD", "EURJPY", "GBPJPY", "AUDJPY"};
    int symbolIndex = -1;
    
    // Find symbol index
    for(int i = 0; i < ArraySize(pairs); i++) {
        if(pairs[i] == symbol) {
            symbolIndex = i;
            break;
        }
    }
    
    if(symbolIndex == -1) return false; // Symbol not in correlation matrix
    
    // Check existing positions for high correlation
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(m_positionInfo.SelectByIndex(i)) {
            string posSymbol = m_positionInfo.Symbol();
            
            // Find position symbol index
            int posIndex = -1;
            for(int j = 0; j < ArraySize(pairs); j++) {
                if(pairs[j] == posSymbol) {
                    posIndex = j;
                    break;
                }
            }
            
            if(posIndex != -1 && MathAbs(g_correlationMatrix[symbolIndex][posIndex]) > CorrelationThreshold) {
                Print("[CORRELATION] High correlation detected: ", symbol, " vs ", posSymbol, " (", 
                      DoubleToString(g_correlationMatrix[symbolIndex][posIndex], 3), ")");
                return true;
            }
        }
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Check if strategy is valid for current market regime             |
//+------------------------------------------------------------------+
bool IsStrategyValidForRegime(string symbol, ENUM_MARKET_REGIME regime)
{
    // Supply/Demand strategy works best in ranging markets
    if(regime == MARKET_REGIME_RANGING) {
        return true; // S/D strategy is good for ranging markets
    }
    
    // In trending markets, avoid counter-trend S/D trades
    if(regime == MARKET_REGIME_TRENDING) {
        // Only allow S/D if it aligns with trend
        int ma20Handle = iMA(symbol, PERIOD_H1, 20, 0, MODE_EMA, PRICE_CLOSE);
        double ma20Buffer[1];
        if(CopyBuffer(ma20Handle, 0, 0, 1, ma20Buffer) <= 0) return true;
        double ma20 = ma20Buffer[0];
        double symbolBid = SymbolInfoDouble(symbol, SYMBOL_BID);
        
        if(symbolBid < ma20) {
            return false; // Don't sell in uptrend
        }
    }
    
    // In volatile markets, be more cautious
    if(regime == MARKET_REGIME_VOLATILE) {
        return false; // Skip volatile periods
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Fuse AI and strategy signals intelligently                       |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL FuseAIAndStrategySignals(const ENUM_TRADE_SIGNAL strategySignal, const SEnhancedTradeSignal &aiSignal, const string &symbol)
{
    // If AI confidence is very high, trust AI
    if(aiSignal.confidence > 0.8) {
        Print("[AI-FUSION] High confidence AI signal: ", EnumToString(aiSignal.signal), " (", DoubleToString(aiSignal.confidence, 3), ")");
        return aiSignal.signal;
    }
    
    // If AI and strategy agree, proceed
    if(aiSignal.signal == strategySignal && aiSignal.confidence > 0.5) {
        Print("[AI-FUSION] AI and strategy agree: ", EnumToString(strategySignal));
        return strategySignal;
    }
    
    // If AI disagrees with strategy and has decent confidence, block trade
    if(aiSignal.signal != strategySignal && aiSignal.confidence > 0.6) {
        Print("[AI-FUSION] AI disagrees with strategy, blocking trade");
        return TRADE_SIGNAL_NONE;
    }
    
    // Default to strategy signal if AI confidence is low
    if(aiSignal.confidence < 0.5)
        return strategySignal;

    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Calculate adaptive stop loss based on volatility and regime      |
//+------------------------------------------------------------------+
double CalculateAdaptiveStopLoss(const string symbol, const ENUM_MARKET_REGIME regime)
{
    int atrHandle = iATR(symbol, PERIOD_H1, 14);
    double atrBuffer[1];
    if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) <= 0) return DefaultStopLossPips;
    double atr = atrBuffer[0];
    double pointValue = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double baseStopLoss = DefaultStopLossPips;
    
    // Adjust based on volatility
    double volatilityMultiplier = atr / (pointValue * 10); // Convert ATR to pips equivalent
    
    // Adjust based on market regime
    double regimeMultiplier = 1.0;
    switch(regime) {
        case MARKET_REGIME_VOLATILE:
            regimeMultiplier = 2.0; // Wider stops in volatile markets
            break;
        case MARKET_REGIME_RANGING:
            regimeMultiplier = 0.8; // Tighter stops in ranging markets
            break;
        case MARKET_REGIME_TRENDING:
            regimeMultiplier = 1.5; // Medium stops in trending markets
            break;
        default:
            regimeMultiplier = 1.0;
    }
    
    double adaptiveStopLoss = baseStopLoss * volatilityMultiplier * regimeMultiplier;
    
    // Ensure reasonable bounds
    adaptiveStopLoss = MathMax(adaptiveStopLoss, 10.0); // Minimum 10 pips
    adaptiveStopLoss = MathMin(adaptiveStopLoss, 100.0); // Maximum 100 pips
    
    Print("[ADAPTIVE-SL] ", symbol, " SL: ", DoubleToString(adaptiveStopLoss, 1), " pips (Regime: ", EnumToString(regime), ")");
    
    return adaptiveStopLoss;
}

//+------------------------------------------------------------------+
//| Calculate dynamic account-aware lot size                         |
//+------------------------------------------------------------------+
double CalculateIntelligentLotSize(const string symbol, const double stopLossPips, const double aiConfidence)
{
    double localAccountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double localAccountEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // BEAST MODE EMERGENCY CONTROLS - ABSOLUTE SAFETY LIMITS
    if(g_beastModeProtection)
    {
        // EMERGENCY KILL SWITCH: Check account health before ANY position sizing
        const double drawdownPercent = (localAccountBalance > 0.0 ? ((localAccountBalance - localAccountEquity) / localAccountBalance) * 100.0 : 0.0);
        if(drawdownPercent > RISK_MAX_DRAWDOWN_BLOCK)
        {
            Print(" EMERGENCY: Drawdown ", DoubleToString(drawdownPercent, 2), "% - ZERO LOT SIZE ENFORCED");
            return 0.0;
        }

        // EMERGENCY BALANCE CHECK
        if(localAccountBalance < RISK_MIN_ACCOUNT_BALANCE)
        {
            Print(" EMERGENCY: Account too small for trading - ZERO LOT SIZE ENFORCED");
            return 0.0;
        }
    }
    
    // DYNAMIC ACCOUNT-AWARE SCALING
    double baseRisk = currentRiskPerTrade;
    
    // Scale risk based on account size
    double accountSizeMultiplier = 1.0;
    if(localAccountBalance < 1000) {
        accountSizeMultiplier = 0.5; // Very conservative for small accounts
    } else if(localAccountBalance < 5000) {
        accountSizeMultiplier = 0.7; // Conservative for medium accounts
    } else if(localAccountBalance < 10000) {
        accountSizeMultiplier = 1.0; // Normal risk for larger accounts
    } else {
        accountSizeMultiplier = 1.2; // Slightly more aggressive for large accounts
    }

    double riskAmount = localAccountBalance * baseRisk * accountSizeMultiplier;

    // Adjust risk based on AI confidence (0.3x to 1.5x)
    double confidenceMultiplier = 0.3 + (aiConfidence * 1.2);
    riskAmount *= confidenceMultiplier;
    
    // Adjust for current drawdown
    if(g_currentDrawdown > RISK_DRAWDOWN_REDUCE_THRESHOLD) {
        double drawdownReduction = MathMax(0.2, 1.0 - (g_currentDrawdown / 100.0));
        riskAmount *= drawdownReduction;
        Print("[RISK-REDUCTION] Reducing position size due to drawdown: ", DoubleToString(g_currentDrawdown, 2), "%");
    }
    
    // Account health adjustment
    double healthRatio = (localAccountBalance > 0.0 ? localAccountEquity / localAccountBalance : 0.0);
    if(healthRatio < 0.9) {
        riskAmount *= healthRatio; // Reduce risk if account is underwater
    }
    
    // Calculate lot size
    const double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    const double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    const double pointValue = SymbolInfoDouble(symbol, SYMBOL_POINT);
    const double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    const double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    const double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    if(tickValue == 0 || tickSize == 0 || pointValue == 0) {
        Print("[ERROR] Invalid symbol data for ", symbol);
        return 0;
    }
    
    // 🛡�?SURGICAL FIX: Prevent division by zero
    if(stopLossPips <= 0) {
        Print("🚨 [SURGICAL-ERROR] Invalid stopLossPips: ", stopLossPips, " for ", symbol);
        return 0.0;
    }
    
    double pipValue = (tickValue * pointValue) / tickSize;
    if(pipValue <= 0) {
        Print("🚨 [SURGICAL-ERROR] Invalid pipValue calculation: ", pipValue, " for ", symbol);
        return 0.0;
    }
    
    double maxAccountLot = localAccountBalance / 10000.0; // Max 1 lot per $10k
    if(localAccountBalance < 1000) maxAccountLot = 0.5; // Very conservative for small accounts
    else if(localAccountBalance < 5000) maxAccountLot = 0.7; // Conservative for medium accounts
    else if(localAccountBalance < 10000) maxAccountLot = 1.0; // Normal risk for larger accounts
    else maxAccountLot = MathMin(RISK_DEFAULT_MAX_LOT, localAccountBalance / 20000.0); // Max 0.5 lot even for large accounts

    double emergencyMaxLot = 0.01; // ABSOLUTE MAXIMUM - NO EXCEPTIONS
    if(localAccountBalance >= 500.0 && localAccountBalance < 2000.0)
        emergencyMaxLot = 0.05; // Small positions for small accounts
    else if(localAccountBalance >= 2000.0)
        emergencyMaxLot = 0.1; // Conservative maximum even for larger accounts

    double lotSize = riskAmount / (stopLossPips * pipValue);
    
    lotSize = MathMax(lotSize, minLot);
    lotSize = MathMin(lotSize, maxLot);
    lotSize = MathMin(lotSize, MathMin(RISK_DEFAULT_MAX_LOT, localAccountBalance / 20000.0)); // Max 0.5 lot even for large accounts
    lotSize = MathMin(lotSize, emergencyMaxLot); // 🚨 ABSOLUTE SAFETY CAP
    
    // Round to lot step
    if(lotStep > 0) {
        lotSize = MathRound(lotSize / lotStep) * lotStep;
    }
    
    // 🚨 FINAL BEAST MODE VALIDATION - TRIPLE CHECK BEFORE RETURN 🚨
    if(lotSize > RISK_DEFAULT_MAX_LOT) {
        Print("🚨🚨🚨 CRITICAL ALERT: Lot size ", DoubleToString(lotSize, 3), " exceeds 0.5 - FORCING TO 0.01");
        lotSize = 0.01;
    }
    
    // Calculate actual risk percentage for final validation
    double actualRisk = (localAccountBalance > 0.0 ? (lotSize * stopLossPips * 10.0) / localAccountBalance * 100.0 : 0.0); // Rough risk calculation
    if(actualRisk > RISK_DEFAULT_MAX_RISK) { // Never risk more than 2% per trade
        Print("🚨🚨🚨 CRITICAL ALERT: Risk ", DoubleToString(actualRisk, 2), "% exceeds 2% - REDUCING LOT SIZE");
        lotSize = (localAccountBalance * (RISK_DEFAULT_MAX_RISK / 100.0)) / (stopLossPips * 10.0); // Force 2% max risk
        lotSize = MathMax(lotSize, minLot);
        lotSize = MathMin(lotSize, 0.01); // Still cap at 0.01
    }
    
    Print("🛡�?[BEAST-MODE-SIZING] ", symbol, " FINAL LOT: ", DoubleToString(lotSize, 3), 
          " | Balance: $", DoubleToString(localAccountBalance, 0),
          " | Emergency Cap: ", DoubleToString(emergencyMaxLot, 3),
          " | Actual Risk: ", DoubleToString(actualRisk, 2), "%",
          " | AI Confidence: ", DoubleToString(aiConfidence, 3));
    
    return lotSize;
}

//+------------------------------------------------------------------+
//| Final trade risk validation                                       |
//+------------------------------------------------------------------+
bool ValidateTradeRisk(const string symbol, const double lotSize, const double stopLossPips)
{
    // 🚨 BEAST MODE EMERGENCY VALIDATION - ABSOLUTE SAFETY FIRST 🚨
    
    // EMERGENCY LOT SIZE VALIDATION - NO EXCEPTIONS
    if(lotSize <= 0) {
        Print("🚨 [BEAST-VALIDATION] Invalid lot size: ", lotSize, " - TRADE BLOCKED");
        return false;
    }
    
    if(lotSize > 0.5) {
        Print("🚨🚨🚨 [BEAST-VALIDATION] CATASTROPHIC LOT SIZE DETECTED: ", DoubleToString(lotSize, 3), " - TRADE BLOCKED");
        return false;
    }
    
    // EMERGENCY ACCOUNT HEALTH CHECK
    double localValidationBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double localValidationEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double drawdownPercent = (localValidationBalance > 0.0 ? ((localValidationBalance - localValidationEquity) / localValidationBalance) * 100.0 : 0.0);

    if(drawdownPercent > RISK_MAX_DRAWDOWN_BLOCK) {
        Print("🚨 [BEAST-VALIDATION] Drawdown ", DoubleToString(drawdownPercent, 2), "% exceeds 15% - TRADE BLOCKED");
        return false;
    }

    if(localValidationBalance < RISK_MIN_ACCOUNT_BALANCE) {
        Print("🚨 [BEAST-VALIDATION] Account balance $", DoubleToString(localValidationBalance, 2), " too low - TRADE BLOCKED");
        return false;
    }
    
    // Check if we have enough margin
    double marginRequired = 0;
    if(!OrderCalcMargin(ORDER_TYPE_BUY, symbol, lotSize, SymbolInfoDouble(symbol, SYMBOL_ASK), marginRequired)) {
        Print("[RISK-VALIDATION] Failed to calculate margin for ", symbol);
        return false;
    }
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

    if(marginRequired > freeMargin * 0.8) { // Use max 80% of free margin
        Print("[RISK-VALIDATION] Insufficient margin. Required: ", marginRequired, ", Available: ", freeMargin);
        return false;
    }
    
    // Check maximum risk per trade
    double tradeRisk = (lotSize * stopLossPips * SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE)) / SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    double riskPercent = (localValidationBalance > 0.0 ? (tradeRisk / localValidationBalance) * 100.0 : 0.0);

    const double maxRisk = (MaxRiskPerTrade > 0.0 ? MaxRiskPerTrade : RISK_DEFAULT_MAX_RISK);
    if(riskPercent > maxRisk) {
        Print("[RISK-VALIDATION] Trade risk too high: ", DoubleToString(riskPercent, 2), "% > ", DoubleToString(maxRisk, 2), "%");
        return false;
    }
    
    // Check total portfolio risk
    double totalRisk = CalculateTotalPortfolioRisk() + riskPercent;
    const double maxPortfolioRisk = (AccountRiskMax > 0.0 ? AccountRiskMax : RISK_DEFAULT_MAX_PORTFOLIO);
    if(totalRisk > maxPortfolioRisk) {
        Print("[RISK-VALIDATION] Total portfolio risk too high: ", DoubleToString(totalRisk, 2), "% > ", DoubleToString(maxPortfolioRisk, 2), "%");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate total portfolio risk                                    |
//+------------------------------------------------------------------+
double CalculateTotalPortfolioRisk()
{
    double totalRisk = 0.0;
    double portfolioBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    for(int i = PositionsTotal() - 1; i >= 0; i--) {
        if(m_positionInfo.SelectByIndex(i)) {
            double positionRisk = MathAbs(m_positionInfo.Profit());
            if(portfolioBalance > 0.0)
                totalRisk += (positionRisk / portfolioBalance) * 100.0;
        }
    }
    
    return totalRisk;
}

//+------------------------------------------------------------------+
//| Normalize and validate stop levels to prevent Error 4756         |
//+------------------------------------------------------------------+
bool NormalizeAndValidateStops(const string symbol, const ENUM_ORDER_TYPE type, 
                             const double desiredSL, const double desiredTP, 
                             double &outSL, double &outTP, string &errorMsg)
{
    // Get symbol properties
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    int stopLevel = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    
    // Safety check for invalid symbol data
    if(point <= 0 || digits < 0) {
        errorMsg = "Invalid symbol data (point/digits)";
        return false;
    }
    
    // Convert stop level to price distance
    double minStopDistance = stopLevel * point;
    
    // For synthetic indices or high volatility, add extra safety margin
    if(StringFind(symbol, "Volatility") >= 0 || StringFind(symbol, "Step") >= 0 || 
       StringFind(symbol, "Boom") >= 0 || StringFind(symbol, "Crash") >= 0) {
        minStopDistance *= 2.0; // Double the stop level for safety
    }
    
    // Ensure minimum distance is at least 1 point
    if(minStopDistance < point) minStopDistance = point;
    
    // Initialize output with normalized input
    outSL = NormalizeDouble(desiredSL, digits);
    outTP = NormalizeDouble(desiredTP, digits);
    
    // Determine current price and open price reference
    double currentPrice = (type == ORDER_TYPE_BUY) ? ask : bid;
    
    // Validate and Adjust SL
    if(outSL > 0) {
        double distSL = MathAbs(currentPrice - outSL);
        
        // Check side
        if(type == ORDER_TYPE_BUY && outSL >= currentPrice) {
            // SL must be below price for BUY
            outSL = currentPrice - minStopDistance;
            errorMsg = "BUY SL adjusted below price";
        }
        else if(type == ORDER_TYPE_SELL && outSL <= currentPrice) {
            // SL must be above price for SELL
            outSL = currentPrice + minStopDistance;
            errorMsg = "SELL SL adjusted above price";
        }
        
        // Check distance
        if(distSL < minStopDistance) {
            if(type == ORDER_TYPE_BUY)
                outSL = currentPrice - minStopDistance;
            else
                outSL = currentPrice + minStopDistance;
            errorMsg = StringFormat("SL adjusted to min distance (%.5f)", minStopDistance);
        }
        
        outSL = NormalizeDouble(outSL, digits);
    }
    
    // Validate and Adjust TP
    if(outTP > 0) {
        double distTP = MathAbs(currentPrice - outTP);
        
        // Check side
        if(type == ORDER_TYPE_BUY && outTP <= currentPrice) {
            // TP must be above price for BUY
            outTP = currentPrice + minStopDistance;
            errorMsg = "BUY TP adjusted above price";
        }
        else if(type == ORDER_TYPE_SELL && outTP >= currentPrice) {
            // TP must be below price for SELL
            outTP = currentPrice - minStopDistance;
            errorMsg = "SELL TP adjusted below price";
        }
        
        // Check distance
        if(distTP < minStopDistance) {
            if(type == ORDER_TYPE_BUY)
                outTP = currentPrice + minStopDistance;
            else
                outTP = currentPrice - minStopDistance;
            errorMsg = StringFormat("TP adjusted to min distance (%.5f)", minStopDistance);
        }
        
        outTP = NormalizeDouble(outTP, digits);
    }
    
    // Final sanity check - if adjustment failed to produce valid stops (e.g. extreme volatility), fail
    if(outSL > 0 && MathAbs(currentPrice - outSL) < minStopDistance * 0.9) {
        errorMsg = "Unable to validate SL distance";
        return false;
    }
    if(outTP > 0 && MathAbs(currentPrice - outTP) < minStopDistance * 0.9) {
        errorMsg = "Unable to validate TP distance";
        return false;
    }
    
    return true;
}

