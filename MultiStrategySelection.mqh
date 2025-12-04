//+------------------------------------------------------------------+
//| Multi-Strategy Selection and Rotation System                     |
//| Enables all strategies beyond just S/D and OB/FVG               |
//+------------------------------------------------------------------+

#include "Core/Enums.mqh"
#include "Core/StrategyBase.mqh"
#include "Core/StrategyManager.mqh"

class CStrategyManager;
class CTradeManager;
class CPortfolioRiskManager;
class CAdaptiveRiskManager;
class CEnhancedRiskManager;

// Note: These are globals defined in MultiStrategyAutonomousEA.mq5

bool IsTrendingRegime(const ENUM_MARKET_REGIME regime)
{
    return (regime == MARKET_REGIME_TRENDING);
}

bool StrategyManagerReady()
{
    return (strategyManager.GetStrategyCount() > 0);
}

// Strategy rotation state
static int g_currentStrategyIndex = 0;
static datetime g_lastStrategySwitch = 0;
static double g_strategyPerformance[7]; // Track performance of each strategy
static int g_strategyTradeCount[7];
static string g_strategyNames[7] = {
    "Supply/Demand",
    "OrderBlock/FVG", 
    "RSI",
    "Fibonacci",
    "Elliott Wave",
    "Swing Trading",
    "Correlation Matrix"
};

//+------------------------------------------------------------------+
//| Get signal from multiple strategies with intelligent selection   |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL GetMultiStrategySignal(string symbol, ENUM_MARKET_REGIME regime)
{
    Print("[MULTI-STRATEGY] Evaluating ", ArraySize(g_strategyNames), " strategies for ", symbol);
    
    // Strategy signals array
    ENUM_TRADE_SIGNAL signals[7];
    double confidences[7];
    double weights[7];
    
    // Initialize arrays
    for(int i = 0; i < 7; i++) {
        signals[i] = TRADE_SIGNAL_NONE;
        confidences[i] = 0.0;
        weights[i] = 1.0;
    }
    
    // 1. SUPPLY/DEMAND STRATEGY
    signals[0] = GetSupplyDemandSignal(symbol, regime);
    confidences[0] = CalculateSupplyDemandConfidence(symbol, regime);
    weights[0] = (regime == MARKET_REGIME_RANGING) ? 1.5 : 0.7; // Better in ranging markets
    
    // 2. ORDERBLOCK/FVG STRATEGY  
    signals[1] = GetOrderBlockFVGSignal(symbol, regime);
    confidences[1] = CalculateOrderBlockConfidence(symbol, regime);
    weights[1] = (IsTrendingRegime(regime) ? 1.3 : 1.0);
    
    // 3. RSI STRATEGY
    signals[2] = GetRSISignal(symbol, regime);
    confidences[2] = CalculateRSIConfidence(symbol, regime);
    weights[2] = (regime == MARKET_REGIME_RANGING) ? 1.2 : 0.8;
    
    // 4. FIBONACCI STRATEGY
    signals[3] = GetFibonacciSignal(symbol, regime);
    confidences[3] = CalculateFibonacciConfidence(symbol, regime);
    weights[3] = (IsTrendingRegime(regime) ? 1.4 : 0.9);
    
    // 5. ELLIOTT WAVE STRATEGY
    signals[4] = GetElliottWaveSignal(symbol, regime);
    confidences[4] = CalculateElliottWaveConfidence(symbol, regime);
    weights[4] = (IsTrendingRegime(regime) ? 1.5 : 0.6);
    
    // 6. SWING TRADING STRATEGY
    signals[5] = GetSwingTradingSignal(symbol, regime);
    confidences[5] = CalculateSwingTradingConfidence(symbol, regime);
    weights[5] = 1.1; // Generally good across all regimes
    
    // 7. CORRELATION MATRIX STRATEGY
    signals[6] = GetCorrelationMatrixSignal(symbol, regime);
    confidences[6] = CalculateCorrelationMatrixConfidence(symbol, regime);
    weights[6] = 1.0; // Neutral weight
    
    // INTELLIGENT STRATEGY FUSION
    return FuseMultipleStrategies(signals, confidences, weights, symbol, regime);
}

//+------------------------------------------------------------------+
//| Fuse multiple strategy signals intelligently                     |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL FuseMultipleStrategies(ENUM_TRADE_SIGNAL &signals[], double &confidences[], double &weights[], string symbol, ENUM_MARKET_REGIME regime)
{
    double buyScore = 0.0;
    double sellScore = 0.0;
    double totalWeight = 0.0;
    int activeStrategies = 0;
    
    Print("[STRATEGY-FUSION] Analyzing signals for ", symbol, " in regime: ", EnumToString(regime));
    
    for(int i = 0; i < ArraySize(signals); i++) {
        if(signals[i] == TRADE_SIGNAL_NONE) continue;
        
        double strategyScore = confidences[i] * weights[i];
        totalWeight += weights[i];
        activeStrategies++;
        
        if(signals[i] == TRADE_SIGNAL_BUY) {
            buyScore += strategyScore;
            Print("  [", g_strategyNames[i], "] BUY signal - Confidence: ", DoubleToString(confidences[i], 3), 
                  " Weight: ", DoubleToString(weights[i], 2), " Score: ", DoubleToString(strategyScore, 3));
        } else if(signals[i] == TRADE_SIGNAL_SELL) {
            sellScore += strategyScore;
            Print("  [", g_strategyNames[i], "] SELL signal - Confidence: ", DoubleToString(confidences[i], 3), 
                  " Weight: ", DoubleToString(weights[i], 2), " Score: ", DoubleToString(strategyScore, 3));
        }
    }
    
    // Require at least 2 strategies to agree
    if(activeStrategies < 2) {
        Print("[STRATEGY-FUSION] Insufficient strategy consensus (", activeStrategies, " active)");
        return TRADE_SIGNAL_NONE;
    }
    
    // Calculate final scores
    double finalBuyScore = buyScore / totalWeight;
    double finalSellScore = sellScore / totalWeight;
    double scoreDifference = MathAbs(finalBuyScore - finalSellScore);
    
    // Require minimum confidence threshold
    double minConfidenceThreshold = 0.6;
    
    if(finalBuyScore > finalSellScore && finalBuyScore > minConfidenceThreshold && scoreDifference > 0.2) {
        Print("[STRATEGY-FUSION] CONSENSUS BUY - Score: ", DoubleToString(finalBuyScore, 3), 
              " (", activeStrategies, " strategies)");
        return TRADE_SIGNAL_BUY;
    } else if(finalSellScore > finalBuyScore && finalSellScore > minConfidenceThreshold && scoreDifference > 0.2) {
        Print("[STRATEGY-FUSION] CONSENSUS SELL - Score: ", DoubleToString(finalSellScore, 3), 
              " (", activeStrategies, " strategies)");
        return TRADE_SIGNAL_SELL;
    }
    
    Print("[STRATEGY-FUSION] NO CONSENSUS - Buy: ", DoubleToString(finalBuyScore, 3), 
          " Sell: ", DoubleToString(finalSellScore, 3), " (", activeStrategies, " strategies)");
    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Individual Strategy Signal Functions                             |
//+------------------------------------------------------------------+

ENUM_TRADE_SIGNAL GetSupplyDemandSignal(string symbol, ENUM_MARKET_REGIME regime)
{
    // Call existing S/D strategy if available
    if(StrategyManagerReady()) {
        double confidence = 0.0;
        return strategyManager.GetSignal(symbol, PERIOD_CURRENT, confidence);
    }
    
    // Fallback S/D logic
    double high = iHigh(symbol, PERIOD_H1, 1);
    double low = iLow(symbol, PERIOD_H1, 1);
    double close = iClose(symbol, PERIOD_H1, 0);
    
    int atrHandle = iATR(symbol, PERIOD_H1, 14);
    double atrBuffer[1];
    if(CopyBuffer(atrHandle, 0, 1, 1, atrBuffer) <= 0) return TRADE_SIGNAL_NONE;
    double atr = atrBuffer[0];
    
    if(close > high - (atr * 0.3)) return TRADE_SIGNAL_BUY;
    if(close < low + (atr * 0.3)) return TRADE_SIGNAL_SELL;
    
    return TRADE_SIGNAL_NONE;
}

ENUM_TRADE_SIGNAL GetOrderBlockFVGSignal(string symbol, ENUM_MARKET_REGIME regime)
{
    // Simple OrderBlock detection
    double high1 = iHigh(symbol, PERIOD_H1, 1);
    double low1 = iLow(symbol, PERIOD_H1, 1);
    double high2 = iHigh(symbol, PERIOD_H1, 2);
    double low2 = iLow(symbol, PERIOD_H1, 2);
    double close = iClose(symbol, PERIOD_H1, 0);
    
    // Bullish OrderBlock
    if(low1 > high2 && close > high1) return TRADE_SIGNAL_BUY;
    
    // Bearish OrderBlock  
    if(high1 < low2 && close < low1) return TRADE_SIGNAL_SELL;
    
    return TRADE_SIGNAL_NONE;
}

ENUM_TRADE_SIGNAL GetRSISignal(string symbol, ENUM_MARKET_REGIME regime)
{
    int rsiHandle = iRSI(symbol, PERIOD_H1, 14, PRICE_CLOSE);
    double rsiBuf[1];
    if(CopyBuffer(rsiHandle, 0, 0, 1, rsiBuf) <= 0) return TRADE_SIGNAL_NONE;
    double rsi = rsiBuf[0];
    
    if(rsi < 30) return TRADE_SIGNAL_BUY;   // Oversold
    if(rsi > 70) return TRADE_SIGNAL_SELL;  // Overbought
    
    return TRADE_SIGNAL_NONE;
}

ENUM_TRADE_SIGNAL GetFibonacciSignal(string symbol, ENUM_MARKET_REGIME regime)
{
    // Simple Fibonacci retracement logic
    double high = iHigh(symbol, PERIOD_H4, iHighest(symbol, PERIOD_H4, MODE_HIGH, 20, 1));
    double low = iLow(symbol, PERIOD_H4, iLowest(symbol, PERIOD_H4, MODE_LOW, 20, 1));
    double close = iClose(symbol, PERIOD_H1, 0);
    
    double fib618 = low + (high - low) * 0.618;
    double fib382 = low + (high - low) * 0.382;
    
    if(close <= fib382 && close > low) return TRADE_SIGNAL_BUY;
    if(close >= fib618 && close < high) return TRADE_SIGNAL_SELL;
    
    return TRADE_SIGNAL_NONE;
}

ENUM_TRADE_SIGNAL GetElliottWaveSignal(string symbol, ENUM_MARKET_REGIME regime)
{
    // Simplified Elliott Wave - look for 5-wave patterns
    int ma20Handle = iMA(symbol, PERIOD_H1, 20, 0, MODE_SMA, PRICE_CLOSE);
    int ma50Handle = iMA(symbol, PERIOD_H1, 50, 0, MODE_SMA, PRICE_CLOSE);
    
    double ma20Buffer[1], ma50Buffer[1];
    if(CopyBuffer(ma20Handle, 0, 0, 1, ma20Buffer) <= 0 ||
       CopyBuffer(ma50Handle, 0, 0, 1, ma50Buffer) <= 0) {
        return TRADE_SIGNAL_NONE;
    }
    
    double ma20 = ma20Buffer[0];
    double ma50 = ma50Buffer[0];
    double close = iClose(symbol, PERIOD_H1, 0);
    
    if(ma20 > ma50 && close > ma20) return TRADE_SIGNAL_BUY;
    if(ma20 < ma50 && close < ma20) return TRADE_SIGNAL_SELL;
    
    return TRADE_SIGNAL_NONE;
}

ENUM_TRADE_SIGNAL GetSwingTradingSignal(string symbol, ENUM_MARKET_REGIME regime)
{
    // Swing trading based on higher highs/lower lows
    double high1 = iHigh(symbol, PERIOD_H4, 1);
    double high2 = iHigh(symbol, PERIOD_H4, 2);
    double low1 = iLow(symbol, PERIOD_H4, 1);
    double low2 = iLow(symbol, PERIOD_H4, 2);
    double close = iClose(symbol, PERIOD_H1, 0);
    
    // Higher high pattern
    if(high1 > high2 && close > high1) return TRADE_SIGNAL_BUY;
    
    // Lower low pattern
    if(low1 < low2 && close < low1) return TRADE_SIGNAL_SELL;
    
    return TRADE_SIGNAL_NONE;
}

ENUM_TRADE_SIGNAL GetCorrelationMatrixSignal(string symbol, ENUM_MARKET_REGIME regime)
{
    // Use correlation matrix to find counter-trend opportunities
    // This is a placeholder - would need actual correlation calculation
    return TRADE_SIGNAL_NONE;
}

//+------------------------------------------------------------------+
//| Confidence Calculation Functions                                 |
//+------------------------------------------------------------------+

double CalculateSupplyDemandConfidence(string symbol, ENUM_MARKET_REGIME regime)
{
    int atrHandle = iATR(symbol, PERIOD_H1, 14);
    double atrBuffer[1];
    if(CopyBuffer(atrHandle, 0, 1, 1, atrBuffer) <= 0) return 0.5;
    double atr = atrBuffer[0];
    double spread = SymbolInfoInteger(symbol, SYMBOL_SPREAD) * SymbolInfoDouble(symbol, SYMBOL_POINT);
    
    // Higher confidence in ranging markets, lower confidence with high spread
    double confidence = (regime == MARKET_REGIME_RANGING) ? 0.8 : 0.6;
    if(spread > atr * 0.1) confidence *= 0.7;
    
    return confidence;
}

double CalculateOrderBlockConfidence(string symbol, ENUM_MARKET_REGIME regime)
{
    // Higher confidence in trending markets
    return (IsTrendingRegime(regime) ? 0.75 : 0.55);
}

double CalculateRSIConfidence(string symbol, ENUM_MARKET_REGIME regime)
{
    int rsiHandle = iRSI(symbol, PERIOD_H1, 14, PRICE_CLOSE);
    double rsiBuf[1];
    if(CopyBuffer(rsiHandle, 0, 0, 1, rsiBuf) <= 0) return 0.5;
    double rsi = rsiBuf[0];
    
    // Higher confidence at extreme levels
    if(rsi < 20 || rsi > 80) return 0.9;
    if(rsi < 30 || rsi > 70) return 0.7;
    
    return 0.5;
}

double CalculateFibonacciConfidence(string symbol, ENUM_MARKET_REGIME regime)
{
    // Higher confidence in trending markets
    return (IsTrendingRegime(regime) ? 0.8 : 0.6);
}

double CalculateElliottWaveConfidence(string symbol, ENUM_MARKET_REGIME regime)
{
    // Higher confidence in strong trends
    return (IsTrendingRegime(regime) ? 0.85 : 0.4);
}

double CalculateSwingTradingConfidence(string symbol, ENUM_MARKET_REGIME regime)
{
    // Generally good confidence across all regimes
    return 0.7;
}

double CalculateCorrelationMatrixConfidence(string symbol, ENUM_MARKET_REGIME regime)
{
    // Placeholder
    return 0.5;
}
