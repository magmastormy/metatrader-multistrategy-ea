//+------------------------------------------------------------------+
//| Multi-Strategy Selection and Rotation System                     |
//| Enhanced with AI mode, weighted signals, and orchestration       |
//+------------------------------------------------------------------+

#include "Core/Enums.mqh"
#include "Core/StrategyBase.mqh"
#include "Core/StrategyManager.mqh"
#include "Core/AIEngine.mqh"

class CStrategyManager;
class CTradeManager;
class CPortfolioRiskManager;
class CAdaptiveRiskManager;
class CEnhancedRiskManager;

//+------------------------------------------------------------------+
//| Enhanced Signal Result Structure                                  |
//| Returns comprehensive signal data including contributions         |
//+------------------------------------------------------------------+
struct SEnhancedSignalResult {
    ENUM_TRADE_SIGNAL finalSignal;      // The final trading signal
    double confidence;                   // Overall confidence (0-1)
    double riskFactor;                   // Risk adjustment factor
    double buyScore;                     // Aggregate buy score
    double sellScore;                    // Aggregate sell score
    int activeStrategies;                // Number of contributing strategies
    
    // Strategy contributions
    double contributions[7];             // Individual strategy contributions
    string topContributor;               // Name of top contributing strategy
    double topContributorWeight;         // Weight of top contributor
    
    // AI mode overrides
    bool aiModeActive;                   // Whether AI mode is active
    double aiConfidenceModifier;         // AI confidence adjustment
    string aiReason;                     // AI override reason
    
    // Market context
    ENUM_MARKET_REGIME regime;           // Current market regime
    datetime timestamp;                  // Signal generation time
    
    SEnhancedSignalResult() {
        finalSignal = TRADE_SIGNAL_NONE;
        confidence = 0.0;
        riskFactor = 1.0;
        buyScore = 0.0;
        sellScore = 0.0;
        activeStrategies = 0;
        ArrayInitialize(contributions, 0.0);
        topContributor = "";
        topContributorWeight = 0.0;
        aiModeActive = false;
        aiConfidenceModifier = 1.0;
        aiReason = "";
        regime = MARKET_REGIME_UNKNOWN;
        timestamp = 0;
    }
};

// AI Mode state tracking
static bool g_aiModeEnabled = false;
static double g_aiConfidenceThreshold = 0.65;
static double g_aiWeightMultiplier = 1.0;

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
//| AI Mode Control Functions                                         |
//+------------------------------------------------------------------+
void EnableAIMode(bool enable, double confidenceThreshold = 0.65, double weightMultiplier = 1.0) {
    g_aiModeEnabled = enable;
    g_aiConfidenceThreshold = confidenceThreshold;
    g_aiWeightMultiplier = weightMultiplier;
    Print("[AI-MODE] ", enable ? "ENABLED" : "DISABLED", 
          " - Threshold: ", DoubleToString(confidenceThreshold, 2),
          " - Multiplier: ", DoubleToString(weightMultiplier, 2));
}

bool IsAIModeEnabled() { return g_aiModeEnabled; }
double GetAIConfidenceThreshold() { return g_aiConfidenceThreshold; }

//+------------------------------------------------------------------+
//| Get Enhanced Signal Result with full data                         |
//+------------------------------------------------------------------+
SEnhancedSignalResult GetEnhancedMultiStrategySignal(string symbol, ENUM_MARKET_REGIME regime)
{
    SEnhancedSignalResult result;
    result.regime = regime;
    result.timestamp = TimeCurrent();
    result.aiModeActive = g_aiModeEnabled;
    
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
    weights[0] = (regime == MARKET_REGIME_RANGING) ? 1.5 : 0.7;
    
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
    weights[5] = 1.1;
    
    // 7. CORRELATION MATRIX STRATEGY
    signals[6] = GetCorrelationMatrixSignal(symbol, regime);
    confidences[6] = CalculateCorrelationMatrixConfidence(symbol, regime);
    weights[6] = 1.0;
    
    // Apply AI mode weight multiplier if enabled
    if(g_aiModeEnabled && g_AIEngine != NULL) {
        for(int i = 0; i < 7; i++) {
            weights[i] *= g_aiWeightMultiplier;
        }
    }
    
    // Perform enhanced fusion with contribution tracking
    result = FuseWithContributions(signals, confidences, weights, symbol, regime, result);
    
    // Apply AI confidence modifier if active
    if(g_aiModeEnabled && result.confidence > 0.0) {
        ApplyAIModifiers(result);
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Original function for backward compatibility                      |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL GetMultiStrategySignal(string symbol, ENUM_MARKET_REGIME regime)
{
    SEnhancedSignalResult enhanced = GetEnhancedMultiStrategySignal(symbol, regime);
    return enhanced.finalSignal;
}

//+------------------------------------------------------------------+
//| Enhanced Fusion with Contribution Tracking                        |
//+------------------------------------------------------------------+
SEnhancedSignalResult FuseWithContributions(ENUM_TRADE_SIGNAL &signals[], double &confidences[], 
    double &weights[], string symbol, ENUM_MARKET_REGIME regime, SEnhancedSignalResult &result)
{
    double totalWeight = 0.0;
    double maxContribution = 0.0;
    int topContributorIdx = -1;
    
    Print("[STRATEGY-FUSION] Analyzing signals for ", symbol, " in regime: ", EnumToString(regime));
    
    for(int i = 0; i < ArraySize(signals); i++) {
        if(signals[i] == TRADE_SIGNAL_NONE) continue;
        
        double strategyScore = confidences[i] * weights[i];
        result.contributions[i] = strategyScore;
        totalWeight += weights[i];
        result.activeStrategies++;
        
        // Track top contributor
        if(strategyScore > maxContribution) {
            maxContribution = strategyScore;
            topContributorIdx = i;
        }
        
        if(signals[i] == TRADE_SIGNAL_BUY) {
            result.buyScore += strategyScore;
            Print("  [", g_strategyNames[i], "] BUY signal - Confidence: ", DoubleToString(confidences[i], 3), 
                  " Weight: ", DoubleToString(weights[i], 2), " Score: ", DoubleToString(strategyScore, 3));
        } else if(signals[i] == TRADE_SIGNAL_SELL) {
            result.sellScore += strategyScore;
            Print("  [", g_strategyNames[i], "] SELL signal - Confidence: ", DoubleToString(confidences[i], 3), 
                  " Weight: ", DoubleToString(weights[i], 2), " Score: ", DoubleToString(strategyScore, 3));
        }
    }
    
    // Record top contributor
    if(topContributorIdx >= 0) {
        result.topContributor = g_strategyNames[topContributorIdx];
        result.topContributorWeight = weights[topContributorIdx];
    }
    
    // Require at least 2 strategies to agree
    if(result.activeStrategies < 2) {
        Print("[STRATEGY-FUSION] Insufficient strategy consensus (", result.activeStrategies, " active)");
        result.finalSignal = TRADE_SIGNAL_NONE;
        result.confidence = 0.0;
        return result;
    }
    
    // Calculate final scores
    double finalBuyScore = result.buyScore / totalWeight;
    double finalSellScore = result.sellScore / totalWeight;
    double scoreDifference = MathAbs(finalBuyScore - finalSellScore);
    
    // Use AI threshold if AI mode is enabled, otherwise default
    double minConfidenceThreshold = g_aiModeEnabled ? g_aiConfidenceThreshold : 0.6;
    
    // Calculate risk factor based on consensus strength
    result.riskFactor = CalculateRiskFactor(result.activeStrategies, scoreDifference, regime);
    
    if(finalBuyScore > finalSellScore && finalBuyScore > minConfidenceThreshold && scoreDifference > 0.2) {
        Print("[STRATEGY-FUSION] CONSENSUS BUY - Score: ", DoubleToString(finalBuyScore, 3), 
              " (", result.activeStrategies, " strategies)");
        result.finalSignal = TRADE_SIGNAL_BUY;
        result.confidence = finalBuyScore;
    } else if(finalSellScore > finalBuyScore && finalSellScore > minConfidenceThreshold && scoreDifference > 0.2) {
        Print("[STRATEGY-FUSION] CONSENSUS SELL - Score: ", DoubleToString(finalSellScore, 3), 
              " (", result.activeStrategies, " strategies)");
        result.finalSignal = TRADE_SIGNAL_SELL;
        result.confidence = finalSellScore;
    } else {
        Print("[STRATEGY-FUSION] NO CONSENSUS - Buy: ", DoubleToString(finalBuyScore, 3), 
              " Sell: ", DoubleToString(finalSellScore, 3), " (", result.activeStrategies, " strategies)");
        result.finalSignal = TRADE_SIGNAL_NONE;
        result.confidence = MathMax(finalBuyScore, finalSellScore);
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Calculate Risk Factor based on consensus and market conditions    |
//+------------------------------------------------------------------+
double CalculateRiskFactor(int activeStrategies, double scoreDifference, ENUM_MARKET_REGIME regime)
{
    double baseFactor = 1.0;
    
    // More strategies agreeing = lower risk
    if(activeStrategies >= 5) baseFactor *= 0.8;
    else if(activeStrategies >= 3) baseFactor *= 0.9;
    else baseFactor *= 1.1;
    
    // Stronger consensus = lower risk
    if(scoreDifference > 0.5) baseFactor *= 0.85;
    else if(scoreDifference > 0.3) baseFactor *= 0.95;
    else baseFactor *= 1.05;
    
    // Market regime adjustment
    if(regime == MARKET_REGIME_VOLATILE) baseFactor *= 1.3;
    else if(regime == MARKET_REGIME_RANGING) baseFactor *= 0.95;
    
    return MathMax(0.5, MathMin(2.0, baseFactor));
}

//+------------------------------------------------------------------+
//| Apply AI Modifiers to the signal result                           |
//+------------------------------------------------------------------+
void ApplyAIModifiers(SEnhancedSignalResult &result)
{
    if(g_AIEngine == NULL) return;
    
    // Check if AI engine has adaptive mode recommendations
    if(g_AIEngine.IsAdaptiveModeActive()) {
        double accuracy = g_AIEngine.GetPredictionAccuracy();
        
        // Adjust confidence based on AI performance
        if(accuracy > 0.6) {
            result.aiConfidenceModifier = 1.0 + (accuracy - 0.6) * 0.5;
            result.confidence *= result.aiConfidenceModifier;
            result.aiReason = "AI confidence boost (accuracy: " + DoubleToString(accuracy * 100, 1) + "%)";
        } else if(accuracy < 0.4) {
            result.aiConfidenceModifier = 0.7;
            result.confidence *= result.aiConfidenceModifier;
            result.riskFactor *= 1.3; // Increase risk factor
            result.aiReason = "AI caution (low accuracy)";
        }
    }
    
    // Cap confidence at 1.0
    result.confidence = MathMin(1.0, result.confidence);
}

//+------------------------------------------------------------------+
//| Legacy Fuse function for backward compatibility                   |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL FuseMultipleStrategies(ENUM_TRADE_SIGNAL &signals[], double &confidences[], double &weights[], string symbol, ENUM_MARKET_REGIME regime)
{
    SEnhancedSignalResult result;
    result.regime = regime;
    result = FuseWithContributions(signals, confidences, weights, symbol, regime, result);
    return result.finalSignal;
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
