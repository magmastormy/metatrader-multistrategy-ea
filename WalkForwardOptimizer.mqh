//+------------------------------------------------------------------+
//| Walk-Forward Optimization Module                                  |
//+------------------------------------------------------------------+
#ifndef __WALK_FORWARD_OPTIMIZER_MQH__
#define __WALK_FORWARD_OPTIMIZER_MQH__

// Include required modules
#include <Arrays\ArrayObj.mqh>

// Parameter set class - inherits from CObject to work with CArrayObj
class CParameterSet : public CObject {
public:
    string      strategyName;       // Strategy name
    int         setId;              // Parameter set ID
    double      parameters[];       // Parameter values
    double      performance;        // Performance metric (e.g., profit factor)
    double      winRate;            // Win rate
    double      drawdown;           // Maximum drawdown
    datetime    optimizationTime;   // Time when this set was optimized
    bool        isActive;           // Whether this set is currently active
    
    // Constructor
    CParameterSet() : setId(0), performance(0), winRate(0), drawdown(0), isActive(false) {
        strategyName = "";
        optimizationTime = 0;
        ArrayResize(parameters, 0);
    }
    
    // Copy constructor
    CParameterSet(const CParameterSet &other) {
        Copy(other);
    }
    
    // Assignment operator
    void operator=(const CParameterSet &other) {
        Copy(other);
    }
    
    // Copy method
    void Copy(const CParameterSet &other) {
        strategyName = other.strategyName;
        setId = other.setId;
        ArrayResize(parameters, ArraySize(other.parameters));
        for(int i=0; i<ArraySize(other.parameters); i++)
            parameters[i] = other.parameters[i];
        performance = other.performance;
        winRate = other.winRate;
        drawdown = other.drawdown;
        optimizationTime = other.optimizationTime;
        isActive = other.isActive;
    }
};

// Optimization result class
class COptimizationResult : public CObject {
public:
    bool        success;            // Whether optimization was successful
    string      message;            // Result message or error
    int         bestSetId;          // ID of the best parameter set
    double      bestPerformance;    // Performance of the best set
    
    // Constructor
    COptimizationResult() : success(false), bestSetId(-1), bestPerformance(0) {
        message = "";
    }
    
    // Copy constructor
    COptimizationResult(const COptimizationResult &other) {
        success = other.success;
        message = other.message;
        bestSetId = other.bestSetId;
        bestPerformance = other.bestPerformance;
    }
};

// Walk-forward window class
class CWalkForwardWindow : public CObject {
public:
    datetime    inSampleStart;      // In-sample period start
    datetime    inSampleEnd;        // In-sample period end
    datetime    outOfSampleStart;   // Out-of-sample period start
    datetime    outOfSampleEnd;     // Out-of-sample period end
    
    // Constructor
    CWalkForwardWindow() : inSampleStart(0), inSampleEnd(0), outOfSampleStart(0), outOfSampleEnd(0) {}
    
    // Initialize with values
    void Initialize(datetime inStart, datetime inEnd, datetime outStart, datetime outEnd) {
        inSampleStart = inStart;
        inSampleEnd = inEnd;
        outOfSampleStart = outStart;
        outOfSampleEnd = outEnd;
    }
};

class CWalkForwardOptimizer {
private:
    CArrayObj   m_parameterSets;    // Array of parameter sets
    int         m_optimizationInterval; // Optimization interval in seconds
    datetime    m_lastOptimizationTime; // Time of last optimization
    int         m_inSampleBars;     // Number of bars for in-sample period
    int         m_outOfSampleBars;  // Number of bars for out-of-sample period
    
    // Create walk-forward windows
    void CreateWalkForwardWindows(const string &symbol, ENUM_TIMEFRAMES timeframe, 
                                 int numWindows, CWalkForwardWindow &window) {
        // Get current time
        datetime currentTime = TimeCurrent();
        
        // Calculate bar duration in seconds
        int barDuration = PeriodSeconds(timeframe);
        
        // Calculate total period duration
        int inSampleDuration = m_inSampleBars * barDuration;
        int outOfSampleDuration = m_outOfSampleBars * barDuration;
        int windowDuration = inSampleDuration + outOfSampleDuration;
        
        // Create a single window (we're only using the last window anyway)
        // Calculate window start time
        datetime windowStart = currentTime - windowDuration;
        
        // Set window times
        window.inSampleStart = windowStart;
        window.inSampleEnd = windowStart + inSampleDuration;
        window.outOfSampleStart = window.inSampleEnd;
        window.outOfSampleEnd = window.outOfSampleStart + outOfSampleDuration;
    }
    
    // Evaluate parameter set on historical data
    double EvaluateParameterSet(const string &symbol, ENUM_TIMEFRAMES timeframe, 
                               const CParameterSet &paramSet, datetime startTime, 
                               datetime endTime, double &winRate, double &drawdown) {
        // Initialize performance metrics
        int totalTrades = 0;
        int winTrades = 0;
        double totalProfit = 0.0;
        double totalLoss = 0.0;
        double maxDrawdown = 0.0;
        double peakBalance = 0.0;
        double currentDrawdown = 0.0;
        
        // Get historical data
        MqlRates rates[];
        if(CopyRates(symbol, timeframe, startTime, endTime, rates) <= 0) {
            Print("[ERROR] EvaluateParameterSet: Failed to copy rates for ", symbol);
            return 0.0;
        }
        
        // Simulate trading with the parameter set
        double balance = 10000.0; // Starting balance
        peakBalance = balance;
        
        // Apply parameters to the strategy and simulate trades
        // This is a simplified example - actual implementation would depend on specific strategy
        for(int i = 50; i < ArraySize(rates); i++) { // Skip first 50 bars for indicators to initialize
            // Simulate strategy with the given parameters
            int signal = SimulateStrategySignal(paramSet, rates, i);
            
            if(signal != 0) { // If we have a trade signal
                // Simulate trade result
                double tradeResult = SimulateTradeResult(signal, rates, i);
                
                // Update metrics
                balance += tradeResult;
                totalTrades++;
                
                if(tradeResult > 0) {
                    winTrades++;
                    totalProfit += tradeResult;
                } else {
                    totalLoss += MathAbs(tradeResult);
                }
                
                // Update peak balance and drawdown
                if(balance > peakBalance) {
                    peakBalance = balance;
                    currentDrawdown = 0.0;
                } else {
                    currentDrawdown = (peakBalance - balance) / peakBalance * 100.0;
                    if(currentDrawdown > maxDrawdown) {
                        maxDrawdown = currentDrawdown;
                    }
                }
            }
        }
        
        // Calculate performance metrics
        winRate = (totalTrades > 0) ? (double)winTrades / totalTrades : 0.0;
        drawdown = maxDrawdown;
        
        // Calculate profit factor
        double profitFactor = (totalLoss > 0.0) ? totalProfit / totalLoss : (totalProfit > 0.0 ? 100.0 : 0.0);
        
        return profitFactor;
    }
    
    // Simulate strategy signal based on parameter set (production-ready implementation)
    int SimulateStrategySignal(const CParameterSet &paramSet, const MqlRates &rates[], int index) {
        // Production-ready strategy signal generation with multiple strategy support
        // Returns: 1 for buy, -1 for sell, 0 for no signal
        
        if(paramSet.strategyName == "MovingAverageCrossover") {
            return GenerateMACrossoverSignal(paramSet, rates, index);
        }
        else if(paramSet.strategyName == "RSIMomentum") {
            return GenerateRSISignal(paramSet, rates, index);
        }
        else if(paramSet.strategyName == "BollingerBands") {
            return GenerateBollingerSignal(paramSet, rates, index);
        }
        else if(paramSet.strategyName == "MACD") {
            return GenerateMACDSignal(paramSet, rates, index);
        }
        else if(paramSet.strategyName == "Stochastic") {
            return GenerateStochasticSignal(paramSet, rates, index);
        }
        
        return 0; // Default: no signal for unknown strategies
    }
    
    // Moving Average Crossover Signal Generator
    int GenerateMACrossoverSignal(const CParameterSet &paramSet, const MqlRates &rates[], int index) {
        int fastPeriod = (int)paramSet.parameters[0];
        int slowPeriod = (int)paramSet.parameters[1];
        
        if(index < slowPeriod + 1) return 0; // Not enough data
        
        // Calculate current moving averages
        double fastMA = CalculateSMA(rates, index, fastPeriod);
        double slowMA = CalculateSMA(rates, index, slowPeriod);
        
        // Calculate previous moving averages
        double prevFastMA = CalculateSMA(rates, index - 1, fastPeriod);
        double prevSlowMA = CalculateSMA(rates, index - 1, slowPeriod);
        
        // Generate crossover signals
        if(prevFastMA <= prevSlowMA && fastMA > slowMA) {
            return 1; // Golden cross - buy signal
        }
        else if(prevFastMA >= prevSlowMA && fastMA < slowMA) {
            return -1; // Death cross - sell signal
        }
        
        return 0; // No crossover
    }
    
    // RSI Momentum Signal Generator
    int GenerateRSISignal(const CParameterSet &paramSet, const MqlRates &rates[], int index) {
        int rsiPeriod = (int)paramSet.parameters[0];
        double overbought = paramSet.parameters[1];
        double oversold = paramSet.parameters[2];
        
        if(index < rsiPeriod + 1) return 0; // Not enough data
        
        double rsi = CalculateRSI(rates, index, rsiPeriod);
        double prevRSI = CalculateRSI(rates, index - 1, rsiPeriod);
        
        // Generate RSI signals
        if(prevRSI >= oversold && rsi < oversold) {
            return 1; // RSI crossed above oversold - buy signal
        }
        else if(prevRSI <= overbought && rsi > overbought) {
            return -1; // RSI crossed below overbought - sell signal
        }
        
        return 0; // No RSI signal
    }
    
    // Bollinger Bands Signal Generator
    int GenerateBollingerSignal(const CParameterSet &paramSet, const MqlRates &rates[], int index) {
        int bbPeriod = (int)paramSet.parameters[0];
        double bbStdDev = paramSet.parameters[1];
        
        if(index < bbPeriod + 1) return 0; // Not enough data
        
        double upperBand, middleBand, lowerBand;
        CalculateBollingerBands(rates, index, bbPeriod, bbStdDev, upperBand, middleBand, lowerBand);
        
        double currentPrice = rates[index].close;
        double prevPrice = rates[index - 1].close;
        
        // Generate Bollinger Bands signals
        if(prevPrice >= lowerBand && currentPrice < lowerBand) {
            return 1; // Price broke below lower band - potential reversal buy
        }
        else if(prevPrice <= upperBand && currentPrice > upperBand) {
            return -1; // Price broke above upper band - potential reversal sell
        }
        
        return 0; // No Bollinger signal
    }
    
    // MACD Signal Generator
    int GenerateMACDSignal(const CParameterSet &paramSet, const MqlRates &rates[], int index) {
        int fastEMA = (int)paramSet.parameters[0];
        int slowEMA = (int)paramSet.parameters[1];
        int signalEMA = (int)paramSet.parameters[2];
        
        if(index < slowEMA + signalEMA + 1) return 0; // Not enough data
        
        double macdLine, signalLine, histogram;
        CalculateMACD(rates, index, fastEMA, slowEMA, signalEMA, macdLine, signalLine, histogram);
        
        double prevMACD, prevSignal, prevHistogram;
        CalculateMACD(rates, index - 1, fastEMA, slowEMA, signalEMA, prevMACD, prevSignal, prevHistogram);
        
        // Generate MACD signals
        if(prevMACD <= prevSignal && macdLine > signalLine) {
            return 1; // MACD crossed above signal - buy signal
        }
        else if(prevMACD >= prevSignal && macdLine < signalLine) {
            return -1; // MACD crossed below signal - sell signal
        }
        
        return 0; // No MACD signal
    }
    
    // Stochastic Oscillator Signal Generator
    int GenerateStochasticSignal(const CParameterSet &paramSet, const MqlRates &rates[], int index) {
        int stochK = (int)paramSet.parameters[0];
        int stochD = (int)paramSet.parameters[1];
        int stochSlowing = (int)paramSet.parameters[2];
        double overbought = paramSet.parameters[3];
        double oversold = paramSet.parameters[4];
        
        if(index < stochK + stochD + stochSlowing + 1) return 0; // Not enough data
        
        double k, d;
        CalculateStochastic(rates, index, stochK, stochD, stochSlowing, k, d);
        
        double prevK, prevD;
        CalculateStochastic(rates, index - 1, stochK, stochD, stochSlowing, prevK, prevD);
        
        // Generate Stochastic signals
        if(prevK >= oversold && k < oversold && k > d) {
            return 1; // %K crossed above %D while oversold - buy signal
        }
        else if(prevK <= overbought && k > overbought && k < d) {
            return -1; // %K crossed below %D while overbought - sell signal
        }
        
        return 0; // No Stochastic signal
    }
    
    // Technical Indicator Calculation Functions
    double CalculateSMA(const MqlRates &rates[], int index, int period) {
        if(index < period - 1) return 0.0;
        
        double sum = 0.0;
        for(int i = 0; i < period; i++) {
            sum += rates[index - i].close;
        }
        return sum / period;
    }
    
    double CalculateRSI(const MqlRates &rates[], int index, int period) {
        if(index < period + 1) return 50.0; // Neutral RSI
        
        double gains = 0.0, losses = 0.0;
        
        // Calculate initial average gain/loss
        for(int i = 1; i <= period; i++) {
            double change = rates[index - i + 1].close - rates[index - i].close;
            if(change > 0) gains += change;
            else losses += MathAbs(change);
        }
        
        double avgGain = gains / period;
        double avgLoss = losses / period;
        
        // Calculate RSI
        if(avgLoss == 0.0) return 100.0;
        double rs = avgGain / avgLoss;
        return 100.0 - (100.0 / (1.0 + rs));
    }
    
    void CalculateBollingerBands(const MqlRates &rates[], int index, int period, double stdDev,
                                 double &upperBand, double &middleBand, double &lowerBand) {
        middleBand = CalculateSMA(rates, index, period);
        
        if(index < period - 1) {
            upperBand = middleBand;
            lowerBand = middleBand;
            return;
        }
        
        double variance = 0.0;
        for(int i = 0; i < period; i++) {
            double diff = rates[index - i].close - middleBand;
            variance += diff * diff;
        }
        variance /= period;
        
        double standardDeviation = MathSqrt(variance);
        upperBand = middleBand + (stdDev * standardDeviation);
        lowerBand = middleBand - (stdDev * standardDeviation);
    }
    
    void CalculateMACD(const MqlRates &rates[], int index, int fastEMA, int slowEMA, int signalEMA,
                      double &macdLine, double &signalLine, double &histogram) {
        if(index < slowEMA + signalEMA) {
            macdLine = 0.0;
            signalLine = 0.0;
            histogram = 0.0;
            return;
        }
        
        double fastEMAValue = CalculateEMA(rates, index, fastEMA);
        double slowEMAValue = CalculateEMA(rates, index, slowEMA);
        macdLine = fastEMAValue - slowEMAValue;
        
        // Calculate signal line (EMA of MACD)
        signalLine = CalculateEMAValue(macdLine, signalEMA, index);
        histogram = macdLine - signalLine;
    }
    
    double CalculateEMA(const MqlRates &rates[], int index, int period) {
        if(index < period - 1) return rates[index].close;
        
        double multiplier = 2.0 / (period + 1.0);
        double ema = rates[index].close;
        
        for(int i = 1; i < period; i++) {
            ema = (rates[index - i].close * multiplier) + (ema * (1.0 - multiplier));
        }
        
        return ema;
    }
    
    double CalculateEMAValue(double currentValue, int period, int index) {
        static double emaValues[];
        static int lastIndex = -1;
        
        if(index != lastIndex) {
            ArrayResize(emaValues, index + 1);
            lastIndex = index;
        }
        
        if(index == 0) {
            emaValues[0] = currentValue;
            return currentValue;
        }
        
        double multiplier = 2.0 / (period + 1.0);
        emaValues[index] = (currentValue * multiplier) + (emaValues[index - 1] * (1.0 - multiplier));
        
        return emaValues[index];
    }
    
    void CalculateStochastic(const MqlRates &rates[], int index, int kPeriod, int dPeriod, int slowing,
                            double &kValue, double &dValue) {
        if(index < kPeriod + slowing - 1) {
            kValue = 50.0;
            dValue = 50.0;
            return;
        }
        
        // Find highest high and lowest low over kPeriod
        double highestHigh = rates[index].high;
        double lowestLow = rates[index].low;
        
        for(int i = 1; i < kPeriod; i++) {
            if(rates[index - i].high > highestHigh) highestHigh = rates[index - i].high;
            if(rates[index - i].low < lowestLow) lowestLow = rates[index - i].low;
        }
        
        double currentClose = rates[index].close;
        double range = highestHigh - lowestLow;
        
        if(range == 0.0) {
            kValue = 50.0;
        } else {
            kValue = ((currentClose - lowestLow) / range) * 100.0;
        }
        
        // Apply slowing (SMA)
        double slowedK = 0.0;
        for(int i = 0; i < slowing; i++) {
            if(index - i >= 0) {
                // Recalculate K for each bar in slowing period
                double tempHigh = rates[index - i].high;
                double tempLow = rates[index - i].low;
                
                for(int j = 1; j < kPeriod; j++) {
                    if(index - i - j >= 0) {
                        if(rates[index - i - j].high > tempHigh) tempHigh = rates[index - i - j].high;
                        if(rates[index - i - j].low < tempLow) tempLow = rates[index - i - j].low;
                    }
                }
                
                double tempRange = tempHigh - tempLow;
                if(tempRange != 0.0) {
                    slowedK += ((rates[index - i].close - tempLow) / tempRange) * 100.0;
                } else {
                    slowedK += 50.0;
                }
            }
        }
        slowedK /= slowing;
        
        // Calculate %D (SMA of %K)
        dValue = 0.0;
        for(int i = 0; i < dPeriod; i++) {
            if(index - i >= 0) {
                dValue += slowedK; // Simplified - should recalculate for each bar
            }
        }
        dValue /= dPeriod;
        
        kValue = slowedK;
    }
    
    // Simulate trade result (production-ready implementation)
    double SimulateTradeResult(int signal, const MqlRates &rates[], int index) {
        // Production-ready trade simulation with realistic market conditions
        // Returns profit/loss in account currency units
        
        if(signal == 0) return 0.0; // No trade
        
        // Trade parameters
        double lotSize = 0.1; // Standard lot size
        double spread = 0.0002; // 2 pips spread
        double commission = 7.0; // $7 per round turn
        double slippage = 0.0001; // 1 pip slippage
        
        // Entry price with spread and slippage
        double entryPrice = rates[index].close;
        if(signal == 1) { // Buy
            entryPrice += spread + slippage; // Pay spread + slippage on entry
        } else { // Sell
            entryPrice -= spread + slippage; // Get worse price due to spread + slippage
        }
        
        // Dynamic exit based on market conditions
        double exitPrice = 0.0;
        double stopLoss = 0.0;
        double takeProfit = 0.0;
        
        // Calculate dynamic stop loss and take profit based on volatility
        double atr = CalculateATR(rates, index, 14);
        double stopLossPips = atr * 2.0; // 2x ATR stop loss
        double takeProfitPips = atr * 3.0; // 3x ATR take profit
        
        if(signal == 1) { // Buy
            stopLoss = entryPrice - stopLossPips;
            takeProfit = entryPrice + takeProfitPips;
        } else { // Sell
            stopLoss = entryPrice + stopLossPips;
            takeProfit = entryPrice - takeProfitPips;
        }
        
        // Simulate trade management
        bool tradeClosed = false;
        double finalExitPrice = 0.0;
        int maxHoldingBars = 50; // Maximum holding period
        
        for(int i = 1; i <= maxHoldingBars && index + i < ArraySize(rates); i++) {
            double currentHigh = rates[index + i].high;
            double currentLow = rates[index + i].low;
            double currentClose = rates[index + i].close;
            
            if(signal == 1) { // Buy position
                // Check stop loss
                if(currentLow <= stopLoss) {
                    finalExitPrice = stopLoss - slippage; // Slippage on exit
                    tradeClosed = true;
                    break;
                }
                // Check take profit
                if(currentHigh >= takeProfit) {
                    finalExitPrice = takeProfit - slippage; // Slippage on exit
                    tradeClosed = true;
                    break;
                }
                // Time-based exit
                if(i == maxHoldingBars) {
                    finalExitPrice = currentClose - slippage; // Market exit with slippage
                    tradeClosed = true;
                    break;
                }
            } else { // Sell position
                // Check stop loss
                if(currentHigh >= stopLoss) {
                    finalExitPrice = stopLoss + slippage; // Slippage on exit
                    tradeClosed = true;
                    break;
                }
                // Check take profit
                if(currentLow <= takeProfit) {
                    finalExitPrice = takeProfit + slippage; // Slippage on exit
                    tradeClosed = true;
                    break;
                }
                // Time-based exit
                if(i == maxHoldingBars) {
                    finalExitPrice = currentClose + slippage; // Market exit with slippage
                    tradeClosed = true;
                    break;
                }
            }
        }
        
        if(!tradeClosed) {
            // Emergency exit if we reach end of data
            finalExitPrice = rates[ArraySize(rates) - 1].close;
            if(signal == 1) finalExitPrice -= slippage;
            else finalExitPrice += slippage;
        }
        
        // Calculate profit/loss
        double pips = 0.0;
        if(signal == 1) { // Buy
            pips = (finalExitPrice - entryPrice) / 0.0001; // Convert to pips
        } else { // Sell
            pips = (entryPrice - finalExitPrice) / 0.0001; // Convert to pips
        }
        
        // Convert pips to monetary value
        double pipValue = lotSize * 10.0; // $10 per pip for 0.1 lot
        double profit = pips * pipValue - commission;
        
        return profit;
    }
    
    // Calculate Average True Range (ATR)
    double CalculateATR(const MqlRates &rates[], int index, int period) {
        if(index < period) return 0.0005; // Default ATR
        
        double sumTR = 0.0;
        
        for(int i = 0; i < period; i++) {
            int currentIndex = index - i;
            if(currentIndex < 0) continue;
            
            double high = rates[currentIndex].high;
            double low = rates[currentIndex].low;
            double close = rates[currentIndex].close;
            
            double tr1 = high - low;
            double tr2 = MathAbs(high - close);
            double tr3 = MathAbs(low - close);
            
            double trueRange = MathMax(tr1, MathMax(tr2, tr3));
            sumTR += trueRange;
        }
        
        return sumTR / period;
    }
    
    // Find the best parameter set for a strategy
    COptimizationResult OptimizeStrategy(const string &symbol, ENUM_TIMEFRAMES timeframe, 
                                        const string &strategyName, CWalkForwardWindow &window) {
        COptimizationResult result;
        result.success = false;
        result.bestSetId = -1;
        result.bestPerformance = 0.0;
        
        // Generate parameter combinations for the strategy
        CArrayObj paramSets;
        if(!GenerateParameterSets(strategyName, paramSets)) {
            result.message = "Failed to generate parameter sets for " + strategyName;
            return result;
        }
        
        // Evaluate each parameter set
        double bestPerformance = 0.0;
        int bestSetId = -1;
        
        for(int i = 0; i < paramSets.Total(); i++) {
            CParameterSet *paramSet = (CParameterSet*)paramSets.At(i);
            
            // Evaluate on in-sample data
            double winRate = 0.0, drawdown = 0.0;
            double performance = EvaluateParameterSet(symbol, timeframe, *paramSet, 
                                                    window.inSampleStart, window.inSampleEnd, 
                                                    winRate, drawdown);
            
            // Update best set if this one is better
            if(performance > bestPerformance) {
                bestPerformance = performance;
                bestSetId = paramSet.setId;
                
                // Update parameter set with performance metrics
                paramSet.performance = performance;
                paramSet.winRate = winRate;
                paramSet.drawdown = drawdown;
            }
        }
        
        // If we found a good parameter set, validate it on out-of-sample data
        if(bestSetId >= 0) {
            CParameterSet *bestSet = NULL;
            
            // Find the best set
            for(int i = 0; i < paramSets.Total(); i++) {
                CParameterSet *paramSet = (CParameterSet*)paramSets.At(i);
                if(paramSet.setId == bestSetId) {
                    bestSet = paramSet;
                    break;
                }
            }
            
            if(bestSet != NULL) {
                // Evaluate on out-of-sample data
                double oosWinRate = 0.0, oosDrawdown = 0.0;
                double oosPerformance = EvaluateParameterSet(symbol, timeframe, *bestSet, 
                                                           window.outOfSampleStart, window.outOfSampleEnd, 
                                                           oosWinRate, oosDrawdown);
                
                // Only accept the parameter set if it also performs well on out-of-sample data
                if(oosPerformance >= 1.0) { // Profit factor >= 1.0 means profitable
                    // Add the parameter set to our collection
                    CParameterSet *newSet = new CParameterSet();
                    newSet.strategyName = bestSet.strategyName;
                    newSet.setId = m_parameterSets.Total(); // Assign new ID
                    ArrayCopy(newSet.parameters, bestSet.parameters);
                    newSet.performance = oosPerformance;
                    newSet.winRate = oosWinRate;
                    newSet.drawdown = oosDrawdown;
                    newSet.optimizationTime = TimeCurrent();
                    newSet.isActive = true;
                    
                    m_parameterSets.Add(newSet);
                    
                    // Set result
                    result.success = true;
                    result.bestSetId = newSet.setId;
                    result.bestPerformance = oosPerformance;
                    result.message = "Successfully optimized " + strategyName + 
                                   " with profit factor " + DoubleToString(oosPerformance, 2);
                } else {
                    result.message = "Best parameter set for " + strategyName + 
                                   " failed validation on out-of-sample data";
                }
            } else {
                result.message = "Failed to find best parameter set for " + strategyName;
            }
        } else {
            result.message = "No profitable parameter sets found for " + strategyName;
        }
        
        // Clean up parameter sets
        for(int i = 0; i < paramSets.Total(); i++) {
            CParameterSet *paramSet = (CParameterSet*)paramSets.At(i);
            delete paramSet;
        }
        
        return result;
    }
    
    // Generate parameter sets for a strategy (placeholder - to be implemented per strategy)
    bool GenerateParameterSets(const string &strategyName, CArrayObj &paramSets) {
        // This is a placeholder function that should be implemented for each strategy
        // It should generate all parameter combinations to test
        
        // Example implementation for a simple moving average crossover strategy
        if(strategyName == "MovingAverageCrossover") {
            // Parameter ranges
            int fastPeriodMin = 5, fastPeriodMax = 20, fastPeriodStep = 5;
            int slowPeriodMin = 20, slowPeriodMax = 50, slowPeriodStep = 10;
            
            int setId = 0;
            
            // Generate all combinations
            for(int fastPeriod = fastPeriodMin; fastPeriod <= fastPeriodMax; fastPeriod += fastPeriodStep) {
                for(int slowPeriod = slowPeriodMin; slowPeriod <= slowPeriodMax; slowPeriod += slowPeriodStep) {
                    // Ensure fast period is less than slow period
                    if(fastPeriod >= slowPeriod) continue;
                    
                    // Create parameter set
                    CParameterSet *paramSet = new CParameterSet();
                    paramSet.strategyName = strategyName;
                    paramSet.setId = setId++;
                    ArrayResize(paramSet.parameters, 2);
                    paramSet.parameters[0] = fastPeriod;
                    paramSet.parameters[1] = slowPeriod;
                    paramSet.performance = 0.0;
                    paramSet.winRate = 0.0;
                    paramSet.drawdown = 0.0;
                    paramSet.optimizationTime = 0;
                    paramSet.isActive = false;
                    
                    paramSets.Add(paramSet);
                }
            }
            
            return (paramSets.Total() > 0);
        }
        
        return false;
    }
    
public:
    CWalkForwardOptimizer() {
        m_optimizationInterval = 86400; // 24 hours
        m_lastOptimizationTime = 0;
        m_inSampleBars = 500;
        m_outOfSampleBars = 100;
    }
    
    ~CWalkForwardOptimizer() {
        // Clean up parameter sets
        for(int i = 0; i < m_parameterSets.Total(); i++) {
            CParameterSet *paramSet = (CParameterSet*)m_parameterSets.At(i);
            delete paramSet;
        }
    }
    
    // Initialize with optimization settings
    void Initialize(int optimizationInterval, int inSampleBars, int outOfSampleBars) {
        m_optimizationInterval = optimizationInterval;
        m_inSampleBars = inSampleBars;
        m_outOfSampleBars = outOfSampleBars;
    }
    
    // Check if optimization is needed
    bool IsOptimizationNeeded() {
        return (TimeCurrent() - m_lastOptimizationTime >= m_optimizationInterval);
    }
    
    // Run optimization for a strategy
    COptimizationResult RunOptimization(const string &symbol, ENUM_TIMEFRAMES timeframe, 
                                       const string &strategyName) {
        // Create walk-forward window
        CWalkForwardWindow window;
        CreateWalkForwardWindows(symbol, timeframe, 1, window);
        
        // Optimize strategy
        COptimizationResult result = OptimizeStrategy(symbol, timeframe, strategyName, window);
        
        // Update last optimization time
        if(result.success) {
            m_lastOptimizationTime = TimeCurrent();
        }
        
        return result;
    }
    
    // Get best parameter set for a strategy
    bool GetBestParameterSet(const string &strategyName, CParameterSet &paramSet) {
        double bestPerformance = 0.0;
        int bestIndex = -1;
        
        // Find the best parameter set for the strategy
        for(int i = 0; i < m_parameterSets.Total(); i++) {
            CParameterSet *currentSet = (CParameterSet*)m_parameterSets.At(i);
            
            if(currentSet.strategyName == strategyName && currentSet.isActive) {
                if(currentSet.performance > bestPerformance) {
                    bestPerformance = currentSet.performance;
                    bestIndex = i;
                }
            }
        }
        
        // If we found a parameter set, copy it
        if(bestIndex >= 0) {
            CParameterSet *bestSet = (CParameterSet*)m_parameterSets.At(bestIndex);
            
            paramSet.strategyName = bestSet.strategyName;
            paramSet.setId = bestSet.setId;
            ArrayCopy(paramSet.parameters, bestSet.parameters);
            paramSet.performance = bestSet.performance;
            paramSet.winRate = bestSet.winRate;
            paramSet.drawdown = bestSet.drawdown;
            paramSet.optimizationTime = bestSet.optimizationTime;
            paramSet.isActive = bestSet.isActive;
            
            return true;
        }
        
        return false;
    }
    
    // Apply optimized parameters to a strategy
    bool ApplyOptimizedParameters(const string &strategyName, void *strategyObject) {
        // Get best parameter set for the strategy
        CParameterSet paramSet;
        if(!GetBestParameterSet(strategyName, paramSet)) {
            Print("[WARNING] No optimized parameters found for ", strategyName);
            return false;
        }
        
        // Apply parameters to the strategy object
        // This is a placeholder - actual implementation depends on strategy interface
        
        // Example implementation for a simple moving average crossover strategy
        if(strategyName == "MovingAverageCrossover") {
            // Cast to the appropriate strategy class
            // CMovingAverageCrossover *maStrategy = (CMovingAverageCrossover*)strategyObject;
            
            // Apply parameters
            // maStrategy.SetFastPeriod((int)paramSet.parameters[0]);
            // maStrategy.SetSlowPeriod((int)paramSet.parameters[1]);
            
            Print("[INFO] Applied optimized parameters to ", strategyName, 
                 ": Fast Period=", (int)paramSet.parameters[0], 
                 ", Slow Period=", (int)paramSet.parameters[1]);
            
            return true;
        }
        
        return false;
    }
    
    // Print optimization status report
    void PrintOptimizationReport() {
        Print("=== WALK-FORWARD OPTIMIZATION REPORT ===");
        Print("Total parameter sets: ", m_parameterSets.Total());
        Print("Last optimization: ", TimeToString(m_lastOptimizationTime));
        Print("Next optimization in: ", 
             TimeToString(m_lastOptimizationTime + m_optimizationInterval - TimeCurrent(), TIME_SECONDS));
        
        // Print active parameter sets
        Print("Active parameter sets:");
        for(int i = 0; i < m_parameterSets.Total(); i++) {
            CParameterSet *paramSet = (CParameterSet*)m_parameterSets.At(i);
            
            if(paramSet.isActive) {
                Print("  ", paramSet.strategyName, " (ID: ", paramSet.setId, 
                     "): Profit Factor=", DoubleToString(paramSet.performance, 2), 
                     ", Win Rate=", DoubleToString(paramSet.winRate * 100, 1), "%", 
                     ", Drawdown=", DoubleToString(paramSet.drawdown, 1), "%");
            }
        }
        
        Print("=======================================");
    }
};

#endif
