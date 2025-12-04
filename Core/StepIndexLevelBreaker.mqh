//+------------------------------------------------------------------+
//| Step Index Level-Break Strategy Module                            |
//| Specialized level detection and break strategies for Step Indices |
//+------------------------------------------------------------------+
#ifndef __STEP_INDEX_LEVEL_BREAKER_MQH__
#define __STEP_INDEX_LEVEL_BREAKER_MQH__

#include "../Utilities/Utilities.mqh"
#include "ErrorHandling.mqh"
#include "TradeManager.mqh"

// Step level data structure
struct StepLevel {
    double price;
    datetime establishedAt;
    int touchCount;
    bool isBroken;
    bool isResistance;          // true for resistance, false for support
    double strength;            // Level strength (0-1)
    int ticksAtLevel;          // Ticks spent at this level
};

// Level break event
struct LevelBreakEvent {
    datetime timestamp;
    string symbol;
    double levelPrice;
    double breakPrice;
    bool isUpwardBreak;
    double breakStrength;       // How strong the break was
    int volumeAtBreak;
    double priceMovement;       // Price movement after break
    bool wasSuccessful;         // If break led to continued movement
};

// Step index configuration
struct StepIndexConfig {
    string symbol;
    double stepSize;            // Expected step size
    int stepFrequency;          // Expected steps per hour
    double levelTolerance;      // Price tolerance for level detection
    int minTouchesForLevel;     // Minimum touches to establish level
    double breakThreshold;      // Minimum break size to consider valid

    // FIX: Provide explicit constructors to avoid deprecated copy/assignment behavior
    /*
    StepIndexConfig()
    {
        symbol = "";
        stepSize = 0.0;
        stepFrequency = 0;
        levelTolerance = 0.0;
        minTouchesForLevel = 0;
        breakThreshold = 0.0;
    }

    StepIndexConfig(const StepIndexConfig &other)
    {
        symbol = other.symbol;
        stepSize = other.stepSize;
        stepFrequency = other.stepFrequency;
        levelTolerance = other.levelTolerance;
        minTouchesForLevel = other.minTouchesForLevel;
        breakThreshold = other.breakThreshold;
    }
    */
};

// Step index performance tracking
struct StepIndexPerformance {
    string symbol;
    int totalLevelsDetected;
    int successfulBreaks;
    double avgBreakProfit;
    double avgTimeAtLevel;
    double bestBreakProfit;
    int totalTrades;
    double winRate;
    datetime lastLevelTime;
};

class CStepIndexLevelBreaker {
private:
    CUtilities* m_utilities;
    CEnhancedErrorHandler* m_errorHandler;
    
    // Configuration and tracking arrays
    StepIndexConfig m_configs[];
    StepLevel m_activeLevels[];
    LevelBreakEvent m_breakHistory[];
    StepIndexPerformance m_performance[];
    
    // Detection parameters
    int m_maxActiveLevels;
    int m_maxBreakHistory;
    double m_minLevelStrength;
    int m_levelAnalysisWindow;
    
    // Price tracking for level detection
    double m_recentPrices[];
    datetime m_priceTimes[];
    int m_priceHistorySize;
    
    // Detect step levels in price action
    void DetectStepLevels(const string symbolParam) {
        int configIndex = GetConfigIndex(symbolParam);
        if(configIndex == -1) return;
        
        StepIndexConfig config = m_configs[configIndex];
        
        // Get recent price data
        UpdatePriceHistory(symbolParam);
        
        // Analyze price clusters to find levels
        double priceClusters[];
        int clusterCounts[];
        
        FindPriceClusters(priceClusters, clusterCounts, config.levelTolerance);
        
        // Create levels from significant clusters
        for(int i = 0; i < ArraySize(priceClusters); i++) {
            if(clusterCounts[i] >= config.minTouchesForLevel) {
                CreateOrUpdateLevel(symbolParam, priceClusters[i], clusterCounts[i]);
            }
        }
        
        // Clean up old or broken levels
        CleanupLevels(symbolParam);
    }
    
    // Find price clusters in recent data
    void FindPriceClusters(double &clusters[], int &counts[], double tolerance) {
        ArrayResize(clusters, 0);
        ArrayResize(counts, 0);
        
        // Group prices within tolerance
        for(int i = 0; i < ArraySize(m_recentPrices); i++) {
            double price = m_recentPrices[i];
            bool foundCluster = false;
            
            // Check existing clusters
            for(int j = 0; j < ArraySize(clusters); j++) {
                if(MathAbs(price - clusters[j]) <= tolerance) {
                    // Add to existing cluster
                    clusters[j] = (clusters[j] * counts[j] + price) / (counts[j] + 1);
                    counts[j]++;
                    foundCluster = true;
                    break;
                }
            }
            
            // Create new cluster if not found
            if(!foundCluster) {
                int size = ArraySize(clusters);
                ArrayResize(clusters, size + 1);
                ArrayResize(counts, size + 1);
                clusters[size] = price;
                counts[size] = 1;
            }
        }
    }
    
    // Create or update a step level
    void CreateOrUpdateLevel(const string symbolParam, double price, int touchCount) {
        // Check if level already exists
        int levelIndex = FindLevelIndex(symbolParam, price);
        
        if(levelIndex != -1) {
            // Update existing level
            m_activeLevels[levelIndex].touchCount = touchCount;
            m_activeLevels[levelIndex].strength = CalculateLevelStrength(touchCount, 
                m_activeLevels[levelIndex].ticksAtLevel);
        } else {
            // Create new level
            if(ArraySize(m_activeLevels) >= m_maxActiveLevels) {
                RemoveWeakestLevel();
            }
            
            int size = ArraySize(m_activeLevels);
            ArrayResize(m_activeLevels, size + 1);
            
            m_activeLevels[size].price = price;
            m_activeLevels[size].establishedAt = TimeCurrent();
            m_activeLevels[size].touchCount = touchCount;
            m_activeLevels[size].isBroken = false;
            m_activeLevels[size].isResistance = DetermineResistanceSupport(symbolParam, price);
            m_activeLevels[size].strength = CalculateLevelStrength(touchCount, 0);
            m_activeLevels[size].ticksAtLevel = 0;
        }
    }
    
    // Calculate level strength based on touches and time
    double CalculateLevelStrength(int touchCount, int ticksAtLevel) {
        double touchStrength = MathMin(1.0, touchCount / 10.0); // Max at 10 touches
        double timeStrength = MathMin(0.5, ticksAtLevel / 1000.0); // Time component
        
        return touchStrength + timeStrength;
    }
    
    // Determine if level is resistance or support
    bool DetermineResistanceSupport(const string symbolParam, double levelPrice) {
        double currentPriceLocal = 0;
        if(!SymbolInfoDouble(symbolParam, SYMBOL_BID, currentPriceLocal)) {
            currentPriceLocal = 0;
        }
        return (levelPrice > currentPriceLocal); // Above current = resistance
    }
    
    // Check for level breaks
    bool CheckForLevelBreak(const string symbolParam, double currentPriceParam) {
        int configIndex = GetConfigIndex(symbolParam);
        if(configIndex == -1) return false;
        
        StepIndexConfig config = m_configs[configIndex];
        
        // Check all active levels for this symbol
        for(int i = 0; i < ArraySize(m_activeLevels); i++) {
            if(m_activeLevels[i].isBroken) continue;
            
            double levelPrice = m_activeLevels[i].price;
            double breakDistance = MathAbs(currentPriceParam - levelPrice);
            
            // Check if break threshold is met
            if(breakDistance >= config.breakThreshold) {
                bool isUpwardBreak = (currentPriceParam > levelPrice);
                
                // Validate break direction matches level type
                if((m_activeLevels[i].isResistance && isUpwardBreak) ||
                   (!m_activeLevels[i].isResistance && !isUpwardBreak)) {
                     
                    // Record level break
                    RecordLevelBreak(symbolParam, i, currentPriceParam, isUpwardBreak);
                    return true;
                }
            }
        }
        
        return false;
    }
    
    // Record a level break event
    void RecordLevelBreak(const string symbolParam, int levelIndex, double breakPrice, bool isUpwardBreak) {
        // Create break event
        LevelBreakEvent breakEvent;
        breakEvent.timestamp = TimeCurrent();
        breakEvent.symbol = symbolParam;
        breakEvent.levelPrice = m_activeLevels[levelIndex].price;
        breakEvent.breakPrice = breakPrice;
        breakEvent.isUpwardBreak = isUpwardBreak;
        breakEvent.breakStrength = m_activeLevels[levelIndex].strength;
        long volInt = 0;
        if(!SymbolInfoInteger(symbolParam, SYMBOL_VOLUME, volInt)) {
            volInt = 0;
        }
        breakEvent.volumeAtBreak = (int)volInt;
        breakEvent.priceMovement = 0.0; // Will be updated later
        breakEvent.wasSuccessful = false; // Will be determined later
        
        // Add to history
        AddBreakToHistory(breakEvent);
        
        // Mark level as broken
        m_activeLevels[levelIndex].isBroken = true;
        
        // Update performance
        UpdateBreakPerformance(symbolParam);
        
        // Log break
        string message = StringFormat("%s level break on %s: Level=%.5f, Break=%.5f, Direction=%s, Strength=%.2f",
            isUpwardBreak ? "Resistance" : "Support", symbolParam,
            m_activeLevels[levelIndex].price, breakPrice,
            isUpwardBreak ? "UP" : "DOWN", m_activeLevels[levelIndex].strength);
        Print(StringFormat("%s level break on %s: Level=%.5f, Break=%.5f, Direction=%s, Strength=%.2f",
            isUpwardBreak ? "Resistance" : "Support", symbolParam,
            m_activeLevels[levelIndex].price, breakPrice,
            isUpwardBreak ? "UP" : "DOWN", m_activeLevels[levelIndex].strength));
    }
    
    // Update price history for analysis
    void UpdatePriceHistory(const string symbolParam) {
        double currentPriceLocal = 0;
        if(!SymbolInfoDouble(symbolParam, SYMBOL_BID, currentPriceLocal)) {
            currentPriceLocal = 0;
        }
        datetime currentTimeLocal = TimeCurrent();
        
        // Add to history
        int size = ArraySize(m_recentPrices);
        if(size >= m_priceHistorySize) {
            // Shift arrays left
            for(int i = 0; i < size - 1; i++) {
                m_recentPrices[i] = m_recentPrices[i + 1];
                m_priceTimes[i] = m_priceTimes[i + 1];
            }
            m_recentPrices[size - 1] = currentPriceLocal;
            m_priceTimes[size - 1] = currentTimeLocal;
        } else {
            ArrayResize(m_recentPrices, size + 1);
            ArrayResize(m_priceTimes, size + 1);
            m_recentPrices[size] = currentPriceLocal;
            m_priceTimes[size] = currentTimeLocal;
        }
    }
    
public:
    // Advanced entry strategy with multiple confirmations
    struct StepEntrySignal {
        int direction;           // -1, 0, 1
        double confidence;       // 0.0 to 1.0
        double entryPrice;
        double stopLoss;
        double takeProfit;
        string reasoning;
        bool hasVolumeConfirmation;
        bool hasMomentumConfirmation;
        bool hasLevelConfirmation;
    };
    
    // Get comprehensive level-break strategy recommendation
    struct StepBreakStrategy {
        int signal;              // -1, 0, 1 for sell, none, buy
        double confidence;       // 0.0 to 1.0
        double stopLoss;
        double takeProfit;
        string reasoning;
        double riskAdjustment;   // Risk multiplier based on performance
    };
    
    // Comprehensive performance analytics
    struct DetailedStepPerformance {
        string symbol;
        int totalTrades;
        int winningTrades;
        double winRate;
        double avgProfit;
        double avgLoss;
        double profitFactor;
        double maxProfit;
        double maxLoss;
        double avgTimeInTrade;
        int levelsDetected;
        int successfulBreaks;
        double levelAccuracy;
        datetime lastUpdate;
    };
    
    CStepIndexLevelBreaker(CUtilities* utils, CEnhancedErrorHandler* errHandler) :
        m_utilities(utils),
        m_errorHandler(errHandler),
        m_maxActiveLevels(50),
        m_maxBreakHistory(200),
        m_minLevelStrength(0.3),
        m_levelAnalysisWindow(100),
        m_priceHistorySize(500)
    {
        ArrayResize(m_configs, 0);
        ArrayResize(m_activeLevels, 0);
        ArrayResize(m_breakHistory, 0);
        ArrayResize(m_performance, 0);
        ArrayResize(m_recentPrices, 0);
        ArrayResize(m_priceTimes, 0);
    }
    
    ~CStepIndexLevelBreaker() {
        ArrayFree(m_configs);
        ArrayFree(m_activeLevels);
        ArrayFree(m_breakHistory);
        ArrayFree(m_performance);
        ArrayFree(m_recentPrices);
        ArrayFree(m_priceTimes);
    }
    
    // Initialize step index level detection
    bool InitializeStepIndex(const string symbolParam, double stepSize = 1.0, int stepFrequency = 10) {
        if(!SymbolSelect(symbolParam, true)) {
            SErrorContext context;
            context.component = "StepLevelBreaker";
            context.operation = "InitializeStepIndex";
            context.symbol = symbolParam;
            context.errorCode = ERR_INVALID_PARAMETER;
            context.additionalInfo = "Failed to select step index: " + symbolParam;
            context.timestamp = TimeCurrent();
            context.severity = ERROR_RECOVERABLE;
            CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
            if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
                CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, context);
            }
            return false;
        }
        
        // Add configuration
        int size = ArraySize(m_configs);
        ArrayResize(m_configs, size + 1);
        
        m_configs[size].symbol = symbolParam;
        m_configs[size].stepSize = stepSize;
        m_configs[size].stepFrequency = stepFrequency;
        m_configs[size].levelTolerance = stepSize * 0.1; // 10% of step size
        m_configs[size].minTouchesForLevel = 3;
        m_configs[size].breakThreshold = stepSize * 0.5; // 50% of step size
        
        // Initialize performance tracking
        int perfSize = ArraySize(m_performance);
        ArrayResize(m_performance, perfSize + 1);
        
        m_performance[perfSize].symbol = symbolParam;
        m_performance[perfSize].totalLevelsDetected = 0;
        m_performance[perfSize].successfulBreaks = 0;
        m_performance[perfSize].avgBreakProfit = 0.0;
        m_performance[perfSize].avgTimeAtLevel = 0.0;
        m_performance[perfSize].bestBreakProfit = 0.0;
        m_performance[perfSize].totalTrades = 0;
        m_performance[perfSize].winRate = 0.0;
        m_performance[perfSize].lastLevelTime = 0;
        
        Print(StringFormat("Initialized step index level detection for %s (Step Size: %s)",
            symbolParam, DoubleToString(stepSize, 2)));
        
        return true;
    }
    
    // Monitor step levels and detect breaks
    void MonitorStepLevels(const string symbolParam) {
        // Update level detection
        DetectStepLevels(symbolParam);
        
        // Check for level breaks
        double currentPriceLocal = 0;
        if(!SymbolInfoDouble(symbolParam, SYMBOL_BID, currentPriceLocal)) {
            currentPriceLocal = 0;
        }
        CheckForLevelBreak(symbolParam, currentPriceLocal);
        
        // Update level tick counts
        UpdateLevelTickCounts(symbolParam, currentPriceLocal);
    }
    
    // Get level-break entry signal with enhanced strategy logic
    int GetLevelBreakSignal(const string symbolParam) {
        // Check recent break history
        for(int i = ArraySize(m_breakHistory) - 1; i >= 0; i--) {
            if(m_breakHistory[i].symbol != symbolParam) continue;
            
            // Check if break is recent (within last 30 seconds)
            if(TimeCurrent() - m_breakHistory[i].timestamp > 30) break;
            
            // Enhanced break validation with multiple criteria
            if(ValidateBreakStrength(i) && ValidateBreakMomentum(i, symbolParam)) {
                if(m_breakHistory[i].isUpwardBreak) {
                    return 1; // Buy signal on upward break
                } else {
                    return -1; // Sell signal on downward break
                }
            }
        }
        
        return 0; // No signal
    }
    
    // Enhanced level-break entry strategies
    int GetAdvancedLevelBreakSignal(const string symbolParam, double &confidence) {
        confidence = 0.0;
        
        // Multi-criteria level break analysis
        double currentPriceLocal = 0;
        if(!SymbolInfoDouble(symbolParam, SYMBOL_BID, currentPriceLocal)) {
            currentPriceLocal = 0;
        }
        
        // Check for imminent level breaks
        StepLevel nearestLevel;
        double distanceToLevel = 0.0;
        
        if(FindNearestLevel(symbolParam, currentPriceLocal, nearestLevel, distanceToLevel)) {
            int configIndex = GetConfigIndex(symbolParam);
            if(configIndex == -1) return 0;
            
            StepIndexConfig config = m_configs[configIndex];
            
            // Calculate break probability based on multiple factors
            double breakProbability = CalculateBreakProbability(symbolParam, nearestLevel, distanceToLevel);
            
            // Enhanced entry conditions
            if(breakProbability > 0.7) {
                confidence = breakProbability;
                
                // Determine direction based on level type and market momentum
                bool isUpwardBreak = (currentPriceLocal > nearestLevel.price && nearestLevel.isResistance) ||
                                   (currentPriceLocal < nearestLevel.price && !nearestLevel.isResistance);
                
                // Additional momentum confirmation
                double momentum = CalculateStepMomentum(symbolParam);
                if(MathAbs(momentum) > 0.5) {
                    confidence *= (1.0 + MathAbs(momentum) * 0.2);
                    
                    if(isUpwardBreak && momentum > 0) return 1;
                    if(!isUpwardBreak && momentum < 0) return -1;
                }
            }
        }
        
        return 0;
    }
    
    // Enhanced step-specific position management parameters
    void GetStepPositionParams(const string symbolParam, double &stopLoss, double &takeProfit,
                               double entryPrice, bool isBuy) {
        int configIndex = GetConfigIndex(symbolParam);
        if(configIndex == -1) return;
        
        StepIndexConfig config = m_configs[configIndex];
        
        // Dynamic position management based on level strength and market conditions
        StepLevel nearestLevel;
        double distanceToLevel = 0.0;
        
        if(FindNearestLevel(symbolParam, entryPrice, nearestLevel, distanceToLevel)) {
            // Adaptive stop loss based on level strength
            double stopMultiplier = 0.8 - (nearestLevel.strength * 0.3); // Stronger levels = tighter stops
            double stopDistance = config.stepSize * MathMax(0.3, stopMultiplier);
            
            // Adaptive take profit based on step frequency and volatility
            double volatility = CalculateStepVolatility(symbolParam);
            double profitMultiplier = 1.5 + (volatility * 0.5); // Higher volatility = larger targets
            double profitDistance = config.stepSize * profitMultiplier;
            
            if(isBuy) {
                stopLoss = entryPrice - stopDistance;
                takeProfit = entryPrice + profitDistance;
            } else {
                stopLoss = entryPrice + stopDistance;
                takeProfit = entryPrice - profitDistance;
            }
        } else {
            // Fallback to standard parameters
            double stopDistance = config.stepSize * 0.8;
            double profitDistance = config.stepSize * 1.5;
            
            if(isBuy) {
                stopLoss = entryPrice - stopDistance;
                takeProfit = entryPrice + profitDistance;
            } else {
                stopLoss = entryPrice + stopDistance;
                takeProfit = entryPrice - profitDistance;
            }
        }
    }
    
    // Advanced position management with trailing stops
    void ManageStepPosition(const string symbolParam, ulong ticket, double entryPrice, bool isBuy, CTradeManager* pTradeManager) {
        if(pTradeManager == NULL) return;

        int configIndex = GetConfigIndex(symbolParam);
        if(configIndex == -1) return;
        
        StepIndexConfig config = m_configs[configIndex];
        double currentPriceLocal = 0;
        if(!SymbolInfoDouble(symbolParam, SYMBOL_BID, currentPriceLocal)) {
            currentPriceLocal = 0;
        }
        
        // Check if position has moved favorably by one step
        double priceMovement = isBuy ? (currentPriceLocal - entryPrice) : (entryPrice - currentPriceLocal);
        
        if(priceMovement >= config.stepSize) {
            // Move stop loss to breakeven + small buffer
            double newStopLoss = isBuy ? entryPrice + (config.stepSize * 0.2) :
                                       entryPrice - (config.stepSize * 0.2);
            
            // Update stop loss if it's better than current
            if(!PositionSelectByTicket(ticket)) return;
            
            double currentStopLoss = PositionGetDouble(POSITION_SL);
            bool shouldUpdate = isBuy ? (newStopLoss > currentStopLoss) : (newStopLoss < currentStopLoss);
            
            if(shouldUpdate) {
                // Use TradeManager for modification with validation
                double currentTP = PositionGetDouble(POSITION_TP);
                if(pTradeManager.ModifyPosition(ticket, newStopLoss, currentTP)) {
                    Print(StringFormat("Updated stop loss for %s position #%I64u to breakeven+buffer: %.5f",
                        symbolParam, ticket, newStopLoss));
                }
            }
        }
    }
    
    // Get active levels for symbol
    void GetActiveLevels(const string symbolParam, StepLevel &levels[]) {
        ArrayResize(levels, 0);
        
        for(int i = 0; i < ArraySize(m_activeLevels); i++) {
            if(!m_activeLevels[i].isBroken && 
               m_activeLevels[i].strength >= m_minLevelStrength) {
                
                int size = ArraySize(levels);
                ArrayResize(levels, size + 1);
                levels[size] = m_activeLevels[i];
            }
        }
    }
    
    // Update trade performance
    void UpdateTradePerformance(const string symbolName, double tradeReturn, bool wasSuccessful) {
        int perfIndex = GetPerformanceIndex(symbolName);
        if(perfIndex == -1) return;
        
        m_performance[perfIndex].totalTrades++;
        
        if(wasSuccessful) {
            m_performance[perfIndex].successfulBreaks++;
            
            // Update average break profit
            double totalSuccessful = m_performance[perfIndex].successfulBreaks;
            m_performance[perfIndex].avgBreakProfit =
                (m_performance[perfIndex].avgBreakProfit * (totalSuccessful - 1) + tradeReturn) / totalSuccessful;
            
            // Update best break profit
            if(tradeReturn > m_performance[perfIndex].bestBreakProfit) {
                m_performance[perfIndex].bestBreakProfit = tradeReturn;
            }
        }
        
        // Update win rate
        m_performance[perfIndex].winRate =
            (double)m_performance[perfIndex].successfulBreaks / m_performance[perfIndex].totalTrades;
        
        // Log performance update
        Print(StringFormat("Performance update for %s: Trades=%d, WinRate=%.2f%%, AvgTime=%.1fmin",
            symbolName, m_performance[perfIndex].totalTrades,
            m_performance[perfIndex].winRate * 100.0,
            m_performance[perfIndex].avgTimeAtLevel));
    }
    
    // Get performance data
    StepIndexPerformance GetPerformanceData(const string symbolName) {
        int perfIndex = GetPerformanceIndex(symbolName);
        if(perfIndex != -1) {
            return m_performance[perfIndex];
        }
        
        StepIndexPerformance emptyPerf;
        emptyPerf.symbol = symbolName;
        return emptyPerf;
    }
    
    // Enhanced performance tracking methods
    void UpdateDetailedPerformance(const string symbolName, double entryPrice, double exitPrice,
                                  bool wasSuccessful, datetime entryTime, datetime exitTime) {
        int perfIndex = GetPerformanceIndex(symbolName);
        if(perfIndex == -1) return;
        
        double tradeReturn = wasSuccessful ? MathAbs(exitPrice - entryPrice) : -MathAbs(exitPrice - entryPrice);
        double timeInTrade = (double)(exitTime - entryTime) / 60.0; // Minutes
        
        // Update comprehensive performance metrics
        m_performance[perfIndex].totalTrades++;
        
        if(wasSuccessful) {
            m_performance[perfIndex].successfulBreaks++;
            
            // Update average time at level
            double totalSuccessful = m_performance[perfIndex].successfulBreaks;
            m_performance[perfIndex].avgTimeAtLevel = 
                (m_performance[perfIndex].avgTimeAtLevel * (totalSuccessful - 1) + timeInTrade) / totalSuccessful;
        }
        
        // Update win rate
        m_performance[perfIndex].winRate = 
            (double)m_performance[perfIndex].successfulBreaks / m_performance[perfIndex].totalTrades;
        
        // Log performance update
        Print(StringFormat("Performance update for %s: Trades=%d, WinRate=%.2f%%, AvgTime=%.1fmin",
            symbolName, m_performance[perfIndex].totalTrades,
            m_performance[perfIndex].winRate * 100.0,
            m_performance[perfIndex].avgTimeAtLevel));
    }
    
    // Get performance summary for all step indices
    string GetPerformanceSummary() {
        string summary = "=== Step Index Performance Summary ===\n";
        
        for(int i = 0; i < ArraySize(m_performance); i++) {
            StepIndexPerformance perf = m_performance[i];
            
            summary += StringFormat("%s: Levels=%d, Trades=%d, WinRate=%.1f%%, BestProfit=%.5f\n",
                perf.symbol, perf.totalLevelsDetected, perf.totalTrades, 
                perf.winRate * 100.0, perf.bestBreakProfit);
        }
        
        return summary;
    }
    
    // Reset performance tracking for a symbol
    void ResetPerformanceTracking(const string symbolName) {
        int perfIndex = GetPerformanceIndex(symbolName);
        if(perfIndex == -1) return;
        
        m_performance[perfIndex].totalLevelsDetected = 0;
        m_performance[perfIndex].successfulBreaks = 0;
        m_performance[perfIndex].avgBreakProfit = 0.0;
        m_performance[perfIndex].avgTimeAtLevel = 0.0;
        m_performance[perfIndex].bestBreakProfit = 0.0;
        m_performance[perfIndex].totalTrades = 0;
        m_performance[perfIndex].winRate = 0.0;
        m_performance[perfIndex].lastLevelTime = 0;
        
        Print("Reset performance tracking for " + symbolName);
    }
    
    // Check if step index is performing well
    bool IsPerformingWell(const string symbolName, double minWinRate = 0.6) {
        int perfIndex = GetPerformanceIndex(symbolName);
        if(perfIndex == -1) return false;
        
        StepIndexPerformance perf = m_performance[perfIndex];
        
        // Require minimum number of trades for reliable assessment
        if(perf.totalTrades < 10) return true; // Give benefit of doubt for new symbols
        
        return perf.winRate >= minWinRate;
    }
    
    
    StepBreakStrategy GetLevelBreakStrategy(const string symbolName, double entryPrice) {
        StepBreakStrategy strategy;
        strategy.signal = 0;
        strategy.confidence = 0.0;
        strategy.stopLoss = 0.0;
        strategy.takeProfit = 0.0;
        strategy.reasoning = "No signal";
        strategy.riskAdjustment = 1.0;
        
        // Get advanced signal with confidence
        double signalConfidence = 0.0;
        int signal = GetAdvancedLevelBreakSignal(symbolName, signalConfidence);
        
        if(signal != 0) {
            strategy.signal = signal;
            strategy.confidence = signalConfidence;
            
            // Calculate position parameters
            bool isBuy = (signal > 0);
            GetStepPositionParams(symbolName, strategy.stopLoss, strategy.takeProfit, entryPrice, isBuy);
            
            // Adjust risk based on performance
            if(IsPerformingWell(symbolName, 0.6)) {
                strategy.riskAdjustment = 1.2; // Increase risk for good performers
            } else if(!IsPerformingWell(symbolName, 0.4)) {
                strategy.riskAdjustment = 0.7; // Reduce risk for poor performers
            }
            
            // Build reasoning
            StepLevel nearestLevel;
            double distance = 0.0;
            if(FindNearestLevel(symbolName, entryPrice, nearestLevel, distance)) {
                strategy.reasoning = StringFormat("Level break %s at %.5f (strength=%.2f, distance=%.5f)",
                    isBuy ? "BUY" : "SELL", nearestLevel.price, nearestLevel.strength, distance);
            } else {
                strategy.reasoning = StringFormat("Step momentum %s (confidence=%.2f)",
                    isBuy ? "BUY" : "SELL", signalConfidence);
            }
        }
        
        return strategy;
    }
    
private:
    // Helper methods
    int GetConfigIndex(const string symbolParam) {
        for(int i = 0; i < ArraySize(m_configs); i++) {
            if(m_configs[i].symbol == symbolParam) {
                return i;
            }
        }
        return -1;
    }
    
    int GetPerformanceIndex(const string symbol) {
        for(int i = 0; i < ArraySize(m_performance); i++) {
            if(m_performance[i].symbol == symbol) {
                return i;
            }
        }
        return -1;
    }
    
    int FindLevelIndex(const string symbolParam, double price) {
        for(int i = 0; i < ArraySize(m_activeLevels); i++) {
            if(!m_activeLevels[i].isBroken && 
               MathAbs(m_activeLevels[i].price - price) < 0.0001) {
                return i;
            }
        }
        return -1;
    }
    
    void RemoveWeakestLevel() {
        if(ArraySize(m_activeLevels) == 0) return;
        
        int weakestIndex = 0;
        double weakestStrength = m_activeLevels[0].strength;
        
        for(int i = 1; i < ArraySize(m_activeLevels); i++) {
            if(m_activeLevels[i].strength < weakestStrength) {
                weakestStrength = m_activeLevels[i].strength;
                weakestIndex = i;
            }
        }
        
        // Remove weakest level
        for(int i = weakestIndex; i < ArraySize(m_activeLevels) - 1; i++) {
            m_activeLevels[i] = m_activeLevels[i + 1];
        }
        ArrayResize(m_activeLevels, ArraySize(m_activeLevels) - 1);
    }
    
    void CleanupLevels(const string symbol) {
        // Remove old or broken levels
        for(int i = ArraySize(m_activeLevels) - 1; i >= 0; i--) {
            if(m_activeLevels[i].isBroken || 
               TimeCurrent() - m_activeLevels[i].establishedAt > 3600) { // 1 hour old
                
                // Remove level
                for(int j = i; j < ArraySize(m_activeLevels) - 1; j++) {
                    m_activeLevels[j] = m_activeLevels[j + 1];
                }
                ArrayResize(m_activeLevels, ArraySize(m_activeLevels) - 1);
            }
        }
    }
    
    void UpdateLevelTickCounts(const string symbolParam, double currentPriceLocal) {
        for(int i = 0; i < ArraySize(m_activeLevels); i++) {
            if(!m_activeLevels[i].isBroken) {
                // Check if price is near this level
                double distance = MathAbs(currentPriceLocal - m_activeLevels[i].price);
                int configIndex = GetConfigIndex(symbolParam);
                if(configIndex != -1) {
                    double tolerance = m_configs[configIndex].levelTolerance;
                    if(distance <= tolerance) {
                        m_activeLevels[i].ticksAtLevel++;
                        // Update level strength based on time spent at level
                        m_activeLevels[i].strength = CalculateLevelStrength(
                            m_activeLevels[i].touchCount, m_activeLevels[i].ticksAtLevel);
                    }
                }
            }
        }
    }
    
    // Validate break strength based on multiple criteria
    bool ValidateBreakStrength(int breakIndex) {
        if(breakIndex < 0 || breakIndex >= ArraySize(m_breakHistory)) return false;
        
        LevelBreakEvent breakEvent = m_breakHistory[breakIndex];
        
        // Multiple validation criteria
        bool strongBreak = breakEvent.breakStrength > 0.6;
        bool significantMovement = MathAbs(breakEvent.breakPrice - breakEvent.levelPrice) > 
                                  (breakEvent.levelPrice * 0.001); // 0.1% movement
        bool volumeConfirmation = breakEvent.volumeAtBreak > 0; // Has volume data
        
        return strongBreak && significantMovement;
    }
    
    // Validate break momentum using price action analysis
    bool ValidateBreakMomentum(int breakIndex, const string symbolParam) {
        if(breakIndex < 0 || breakIndex >= ArraySize(m_breakHistory)) return false;
        
        LevelBreakEvent breakEvent = m_breakHistory[breakIndex];
        double currentPriceLocal = 0;
        if(!SymbolInfoDouble(symbolParam, SYMBOL_BID, currentPriceLocal)) {
            currentPriceLocal = 0;
        }
        
        // Check if price continues in break direction
        bool momentumConfirmed = false;
        if(breakEvent.isUpwardBreak) {
            momentumConfirmed = (currentPriceLocal > breakEvent.breakPrice);
        } else {
            momentumConfirmed = (currentPriceLocal < breakEvent.breakPrice);
        }
        
        // Additional momentum validation using recent price movement
        double momentum = CalculateStepMomentum(symbolParam);
        bool momentumAligned = (breakEvent.isUpwardBreak && momentum > 0.3) || 
                              (!breakEvent.isUpwardBreak && momentum < -0.3);
        
        return momentumConfirmed && momentumAligned;
    }
    
    // Find nearest level to given price
    bool FindNearestLevel(const string symbol, double price, StepLevel &nearestLevel, double &distance) {
        distance = DBL_MAX;
        bool found = false;
        
        for(int i = 0; i < ArraySize(m_activeLevels); i++) {
            if(!m_activeLevels[i].isBroken) {
                double levelDistance = MathAbs(price - m_activeLevels[i].price);
                if(levelDistance < distance) {
                    distance = levelDistance;
                    nearestLevel = m_activeLevels[i];
                    found = true;
                }
            }
        }
        
        return found;
    }
    
    // Calculate break probability based on multiple factors
    double CalculateBreakProbability(const string symbolParam, const StepLevel &level, double distanceToLevel) {
        int configIndex = GetConfigIndex(symbolParam);
        if(configIndex == -1) return 0.0;
        
        StepIndexConfig config = m_configs[configIndex];
        
        // Factor 1: Level strength (stronger levels more likely to break with significance)
        double strengthFactor = level.strength;
        
        // Factor 2: Distance to level (closer = higher probability)
        double distanceFactor = 1.0 - MathMin(1.0, distanceToLevel / (config.stepSize * 0.5));
        
        // Factor 3: Time at level (longer time = higher break probability)
        double timeFactor = MathMin(1.0, level.ticksAtLevel / 100.0);
        
        // Factor 4: Market momentum
        double momentum = CalculateStepMomentum(symbolParam);
        double momentumFactor = MathAbs(momentum);
        
        // Factor 5: Touch count (more touches = stronger level, higher break significance)
        double touchFactor = MathMin(1.0, level.touchCount / 8.0);
        
        // Weighted combination
        double probability = (strengthFactor * 0.3) + (distanceFactor * 0.25) + 
                           (timeFactor * 0.2) + (momentumFactor * 0.15) + (touchFactor * 0.1);
        
        return MathMax(0.0, MathMin(1.0, probability));
    }
    
    // Calculate step momentum using recent price changes
    double CalculateStepMomentum(const string symbolParam) {
        if(ArraySize(m_recentPrices) < 10) return 0.0;
        
        int size = ArraySize(m_recentPrices);
        double recentChange = 0.0;
        int periods = MathMin(10, size - 1);
        
        // Calculate average price change over recent periods
        for(int i = size - periods; i < size - 1; i++) {
            recentChange += (m_recentPrices[i + 1] - m_recentPrices[i]);
        }
        
        if(periods > 0) {
            recentChange /= periods;
            
            // Normalize momentum relative to step size
            int configIndex = GetConfigIndex(symbolParam);
            if(configIndex != -1) {
                double stepSize = m_configs[configIndex].stepSize;
                return recentChange / stepSize; // Returns momentum as fraction of step size
            }
        }
        
        return 0.0;
    }
    
    // Calculate step volatility for position sizing
    double CalculateStepVolatility(const string symbolParam) {
        if(ArraySize(m_recentPrices) < 20) return 0.5; // Default volatility
        
        int size = ArraySize(m_recentPrices);
        double priceChanges[];
        ArrayResize(priceChanges, 0);
        
        // Calculate price changes
        for(int i = 1; i < size; i++) {
            double change = MathAbs(m_recentPrices[i] - m_recentPrices[i - 1]);
            int changeSize = ArraySize(priceChanges);
            ArrayResize(priceChanges, changeSize + 1);
            priceChanges[changeSize] = change;
        }
        
        // Calculate standard deviation of price changes
        double mean = 0.0;
        for(int i = 0; i < ArraySize(priceChanges); i++) {
            mean += priceChanges[i];
        }
        mean /= ArraySize(priceChanges);
        
        double variance = 0.0;
        for(int i = 0; i < ArraySize(priceChanges); i++) {
            variance += MathPow(priceChanges[i] - mean, 2);
        }
        variance /= ArraySize(priceChanges);
        
        double volatility = MathSqrt(variance);
        
        // Normalize relative to step size
        int configIndex = GetConfigIndex(symbolParam);
        if(configIndex != -1) {
            double stepSize = m_configs[configIndex].stepSize;
            return volatility / stepSize;
        }
        
        return volatility;
    }
    
    // Add break event to history
    void AddBreakToHistory(const LevelBreakEvent &breakEvent) {
        if(ArraySize(m_breakHistory) >= m_maxBreakHistory) {
            // Remove oldest break
            for(int i = 0; i < ArraySize(m_breakHistory) - 1; i++) {
                m_breakHistory[i] = m_breakHistory[i + 1];
            }
            m_breakHistory[ArraySize(m_breakHistory) - 1] = breakEvent;
        } else {
            int size = ArraySize(m_breakHistory);
            ArrayResize(m_breakHistory, size + 1);
            m_breakHistory[size] = breakEvent;
        }
    }
    
    // Update break performance metrics
    void UpdateBreakPerformance(const string symbol) {
        int perfIndex = GetPerformanceIndex(symbol);
        if(perfIndex == -1) return;
        
        // Count recent breaks for this symbol
        int recentBreaks = 0;
        datetime cutoffTime = TimeCurrent() - 3600; // Last hour
        
        for(int i = ArraySize(m_breakHistory) - 1; i >= 0; i--) {
            if(m_breakHistory[i].symbol == symbol && m_breakHistory[i].timestamp >= cutoffTime) {
                recentBreaks++;
            } else if(m_breakHistory[i].timestamp < cutoffTime) {
                break; // History is chronological
            }
        }
        
        // Update performance metrics
        m_performance[perfIndex].totalLevelsDetected++;
        m_performance[perfIndex].lastLevelTime = TimeCurrent();
        
        // Log performance update
        Print(StringFormat("Break performance update for %s: Recent breaks=%d, Total levels=%d", 
                symbol, recentBreaks, m_performance[perfIndex].totalLevelsDetected));
    }
    
    // Enhanced level detection with multi-timeframe analysis
    void EnhancedLevelDetection(const string symbol) {
        // Detect levels on multiple timeframes for better accuracy
        ENUM_TIMEFRAMES timeframes[] = {PERIOD_M1, PERIOD_M5, PERIOD_M15, PERIOD_H1};
        
        for(int tf = 0; tf < ArraySize(timeframes); tf++) {
            AnalyzeLevelsOnTimeframe(symbol, timeframes[tf]);
        }
        
        // Consolidate levels from different timeframes
        ConsolidateMultiTimeframeLevels(symbol);
    }
    
    // Analyze levels on specific timeframe
    void AnalyzeLevelsOnTimeframe(const string symbol, ENUM_TIMEFRAMES timeframe) {
        // Get price data for this timeframe
        double high[], low[], close[];
        int bars = 100; // Analyze last 100 bars
        
        if(CopyHigh(symbol, timeframe, 0, bars, high) != bars ||
           CopyLow(symbol, timeframe, 0, bars, low) != bars ||
           CopyClose(symbol, timeframe, 0, bars, close) != bars) {
            return; // Failed to get data
        }
        
        // Find significant levels (swing highs/lows)
        for(int i = 2; i < bars - 2; i++) {
            // Check for swing high
            if(high[i] > high[i-1] && high[i] > high[i-2] && 
               high[i] > high[i+1] && high[i] > high[i+2]) {
                CreateOrUpdateLevel(symbol, high[i], 1);
            }
            
            // Check for swing low
            if(low[i] < low[i-1] && low[i] < low[i-2] && 
               low[i] < low[i+1] && low[i] < low[i+2]) {
                CreateOrUpdateLevel(symbol, low[i], 1);
            }
        }
        
        ArrayFree(high);
        ArrayFree(low);
        ArrayFree(close);
    }
    
    // Consolidate levels from multiple timeframes
    void ConsolidateMultiTimeframeLevels(const string symbol) {
        int configIndex = GetConfigIndex(symbol);
        if(configIndex == -1) return;
        
        double tolerance = m_configs[configIndex].levelTolerance * 2.0; // Wider tolerance for consolidation
        
        // Group nearby levels and strengthen them
        for(int i = 0; i < ArraySize(m_activeLevels) - 1; i++) {
            if(m_activeLevels[i].isBroken) continue;
            
            for(int j = i + 1; j < ArraySize(m_activeLevels); j++) {
                if(m_activeLevels[j].isBroken) continue;
                
                double distance = MathAbs(m_activeLevels[i].price - m_activeLevels[j].price);
                if(distance <= tolerance) {
                    // Merge levels - keep stronger one, add touches
                    if(m_activeLevels[i].strength >= m_activeLevels[j].strength) {
                        m_activeLevels[i].touchCount += m_activeLevels[j].touchCount;
                        m_activeLevels[i].strength = CalculateLevelStrength(
                            m_activeLevels[i].touchCount, m_activeLevels[i].ticksAtLevel);
                        m_activeLevels[j].isBroken = true; // Mark for removal
                    } else {
                        m_activeLevels[j].touchCount += m_activeLevels[i].touchCount;
                        m_activeLevels[j].strength = CalculateLevelStrength(
                            m_activeLevels[j].touchCount, m_activeLevels[j].ticksAtLevel);
                        m_activeLevels[i].isBroken = true; // Mark for removal
                    }
                }
            }
        }
    }
    
    
    StepEntrySignal GetAdvancedEntrySignal(const string symbol) {
        StepEntrySignal signal;
        signal.direction = 0;
        signal.confidence = 0.0;
        double askPrice = 0;
        SymbolInfoDouble(symbol, SYMBOL_ASK, askPrice);
        signal.entryPrice = askPrice;
        signal.stopLoss = 0.0;
        signal.takeProfit = 0.0;
        signal.reasoning = "No signal";
        signal.hasVolumeConfirmation = false;
        signal.hasMomentumConfirmation = false;
        signal.hasLevelConfirmation = false;
        
        // Enhanced level detection
        EnhancedLevelDetection(symbol);
        
        // Check for level break opportunities
        StepLevel nearestLevel;
        double distanceToLevel = 0.0;
        
        if(FindNearestLevel(symbol, signal.entryPrice, nearestLevel, distanceToLevel)) {
            double breakProbability = CalculateBreakProbability(symbol, nearestLevel, distanceToLevel);
            
            if(breakProbability > 0.65) {
                // Determine direction
                bool isUpwardBreak = (signal.entryPrice > nearestLevel.price && nearestLevel.isResistance) ||
                                   (signal.entryPrice < nearestLevel.price && !nearestLevel.isResistance);
                
                signal.direction = isUpwardBreak ? 1 : -1;
                signal.confidence = breakProbability;
                signal.hasLevelConfirmation = true;
                
                // Check momentum confirmation
                double momentum = CalculateStepMomentum(symbol);
                if((isUpwardBreak && momentum > 0.2) || (!isUpwardBreak && momentum < -0.2)) {
                    signal.hasMomentumConfirmation = true;
                    signal.confidence *= 1.2; // Boost confidence
                }
                
                // Check volume confirmation (if available)
                long volume = SymbolInfoInteger(symbol, SYMBOL_VOLUME);
                if(volume > 0) {
                    signal.hasVolumeConfirmation = true;
                    signal.confidence *= 1.1; // Small boost for volume
                }
                
                // Calculate position parameters
                GetStepPositionParams(symbol, signal.stopLoss, signal.takeProfit, 
                                    signal.entryPrice, isUpwardBreak);
                
                // Build reasoning
                signal.reasoning = StringFormat("Level break %s at %.5f (prob=%.2f, momentum=%.2f)", 
                    isUpwardBreak ? "BUY" : "SELL", nearestLevel.price, breakProbability, momentum);
                
                // Ensure confidence doesn't exceed 1.0
                signal.confidence = MathMin(1.0, signal.confidence);
            }
        }
        
        return signal;
    }
    
    // Dynamic position management with step-specific logic
    void DynamicStepPositionManagement(const string symbol, ulong ticket) {
        if(!PositionSelectByTicket(ticket)) return;
        
        double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentPriceValue = PositionGetDouble(POSITION_PRICE_CURRENT);
        bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
        
        int configIndex = GetConfigIndex(symbol);
        if(configIndex == -1) return;
        
        StepIndexConfig config = m_configs[configIndex];
        
        // Calculate profit in step units
        double priceMovement = isBuy ? (currentPriceValue - entryPrice) : (entryPrice - currentPriceValue);
        double stepsProfit = priceMovement / config.stepSize;
        
        // Dynamic trailing stop based on steps achieved
        if(stepsProfit >= 1.0) {
            // Move stop to breakeven + 20% of step size
            double newStopLoss = isBuy ? entryPrice + (config.stepSize * 0.2) : 
                                       entryPrice - (config.stepSize * 0.2);
            
            UpdatePositionStopLoss(ticket, newStopLoss, isBuy);
        }
        
        if(stepsProfit >= 2.0) {
            // Move stop to +1 step profit
            double newStopLoss = isBuy ? entryPrice + config.stepSize : 
                                       entryPrice - config.stepSize;
            
            UpdatePositionStopLoss(ticket, newStopLoss, isBuy);
        }
        
        if(stepsProfit >= 3.0) {
            // Trailing stop at 50% of current profit
            double trailingStop = isBuy ? currentPriceValue - (priceMovement * 0.5) : 
                                        currentPriceValue + (priceMovement * 0.5);
            
            UpdatePositionStopLoss(ticket, trailingStop, isBuy);
        }
    }
    
    // Update position stop loss if beneficial
    void UpdatePositionStopLoss(ulong ticket, double newStopLoss, bool isBuy) {
        if(!PositionSelectByTicket(ticket)) return;
        
        double currentStopLoss = PositionGetDouble(POSITION_SL);
        bool shouldUpdate = false;
        
        if(isBuy) {
            shouldUpdate = (newStopLoss > currentStopLoss) || (currentStopLoss == 0.0);
        } else {
            shouldUpdate = (newStopLoss < currentStopLoss) || (currentStopLoss == 0.0);
        }
        
        if(shouldUpdate) {
            MqlTradeRequest request = {};
            MqlTradeResult result = {};
            
            request.action = TRADE_ACTION_SLTP;
            request.position = ticket;
            request.sl = newStopLoss;
            request.tp = PositionGetDouble(POSITION_TP);
            
            if(OrderSend(request, result)) {
                Print("StepLevelBreaker: Updated stop loss for position #", ticket, " to ", DoubleToString(newStopLoss, 5));
            }
        }
    }
    
    
    DetailedStepPerformance GetDetailedPerformance(const string symbol) {
        DetailedStepPerformance detailed;
        detailed.symbol = symbol;
        detailed.totalTrades = 0;
        detailed.winningTrades = 0;
        detailed.winRate = 0.0;
        detailed.avgProfit = 0.0;
        detailed.avgLoss = 0.0;
        detailed.profitFactor = 0.0;
        detailed.maxProfit = 0.0;
        detailed.maxLoss = 0.0;
        detailed.avgTimeInTrade = 0.0;
        detailed.levelsDetected = 0;
        detailed.successfulBreaks = 0;
        detailed.levelAccuracy = 0.0;
        detailed.lastUpdate = TimeCurrent();
        
        // Get basic performance data
        int perfIndex = GetPerformanceIndex(symbol);
        if(perfIndex != -1) {
            StepIndexPerformance basic = m_performance[perfIndex];
            detailed.totalTrades = basic.totalTrades;
            detailed.winningTrades = basic.successfulBreaks;
            detailed.winRate = basic.winRate;
            detailed.levelsDetected = basic.totalLevelsDetected;
            detailed.successfulBreaks = basic.successfulBreaks;
            detailed.avgTimeInTrade = basic.avgTimeAtLevel;
            
            if(detailed.levelsDetected > 0) {
                detailed.levelAccuracy = (double)detailed.successfulBreaks / detailed.levelsDetected;
            }
        }
        
        // Calculate additional metrics from break history
        double totalProfitLocal = 0.0, totalLossLocal = 0.0;
        int profitTrades = 0, lossTrades = 0;
        
        for(int i = 0; i < ArraySize(m_breakHistory); i++) {
            if(m_breakHistory[i].symbol == symbol) {
                if(m_breakHistory[i].wasSuccessful && m_breakHistory[i].priceMovement > 0) {
                    totalProfitLocal += m_breakHistory[i].priceMovement;
                    profitTrades++;
                    if(m_breakHistory[i].priceMovement > detailed.maxProfit) {
                        detailed.maxProfit = m_breakHistory[i].priceMovement;
                    }
                } else if(!m_breakHistory[i].wasSuccessful && m_breakHistory[i].priceMovement < 0) {
                    totalLossLocal += MathAbs(m_breakHistory[i].priceMovement);
                    lossTrades++;
                    if(MathAbs(m_breakHistory[i].priceMovement) > detailed.maxLoss) {
                        detailed.maxLoss = MathAbs(m_breakHistory[i].priceMovement);
                    }
                }
            }
        }
        
        if(profitTrades > 0) detailed.avgProfit = totalProfitLocal / profitTrades;
        if(lossTrades > 0) detailed.avgLoss = totalLossLocal / lossTrades;
        if(detailed.avgLoss > 0) detailed.profitFactor = detailed.avgProfit / detailed.avgLoss;
        
        return detailed;
    }
    
    // Export performance data for analysis
    bool ExportPerformanceData(const string symbol, const string filename) {
        DetailedStepPerformance perf = GetDetailedPerformance(symbol);
        
        int fileHandle = FileOpen(filename, FILE_WRITE | FILE_CSV);
        if(fileHandle == INVALID_HANDLE) {
            CEnhancedErrorHandler::LogError(ERROR_CRITICAL, "StepLevelBreaker", 
                "Failed to create performance export file: " + filename, GetLastError());
            return false;
        }
        
        // Write header
        FileWrite(fileHandle, "Symbol", "Total Trades", "Winning Trades", "Win Rate %", 
                 "Avg Profit", "Avg Loss", "Profit Factor", "Max Profit", "Max Loss",
                 "Avg Time in Trade", "Levels Detected", "Successful Breaks", "Level Accuracy %");
        
        // Write data
        FileWrite(fileHandle, perf.symbol, perf.totalTrades, perf.winningTrades, 
                 perf.winRate * 100.0, perf.avgProfit, perf.avgLoss, perf.profitFactor,
                 perf.maxProfit, perf.maxLoss, perf.avgTimeInTrade, perf.levelsDetected,
                 perf.successfulBreaks, perf.levelAccuracy * 100.0);
        
        FileClose(fileHandle);
        
        Print("StepLevelBreaker: Exported performance data for ", symbol, " to ", filename);
        
        return true;
    }
};

#endif // __STEP_INDEX_LEVEL_BREAKER_MQH__