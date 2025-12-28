//+------------------------------------------------------------------+
//| Strategy Management Module                                         |
//+------------------------------------------------------------------+
#ifndef __STRATEGIES_CORE_LEGACY_DISABLED__
#define __STRATEGIES_CORE_LEGACY_DISABLED__

#include "../Interfaces/IStrategy.mqh" // Defines the IStrategy interface
#include "../Core/MarketAnalysis.mqh" // For ENUM_MARKET_REGIME

#ifndef MAX_STRATEGIES
#define MAX_STRATEGIES 15 // Max index 14 used in GetStrategySignals (0-14 strategies)
#endif

// Forward declarations for dependencies passed to strategies
class CPerformanceAnalytics;
class CMarketRegimeClassifier;
// CMarketAnalysis is already included for ENUM_MARKET_REGIME
class CTradeManager;

// LEGACY MODULE DISABLED: retained for reference but excluded from build
class CStrategyManager_LegacyHidden {
private:
    IStrategy* m_strategies[];         // Dynamic array of strategy pointers
    string m_managedStrategyNames[]; // Names corresponding to m_strategies
    int m_strategyCount;             // Current number of managed strategies

    // ---- NEWLY ADDED MEMBER VARIABLES ----
    double m_minConfirmation;
    ENUM_MARKET_REGIME m_currentRegime;

    int    m_strategySignals[MAX_STRATEGIES];     // Stores the latest signal from each strategy
    double m_strategyConfidences[MAX_STRATEGIES]; // Stores the confidence for each signal
    string m_strategyNames[MAX_STRATEGIES];       // Stores the names of the strategies (for fixed array indexing)
    double m_strategyWinRate[MAX_STRATEGIES];     // Stores win rate for each strategy
    int    m_strategyTradeCount[MAX_STRATEGIES];  // Stores trade count for each strategy
    int    m_strategyWinCount[MAX_STRATEGIES];    // Stores win count for each strategy
    int    m_strategyLossCount[MAX_STRATEGIES];   // Stores loss count for each strategy
    double m_strategyProfitFactor[MAX_STRATEGIES];// Stores profit factor for each strategy
    
    double m_correlationMatrix[MAX_STRATEGIES][MAX_STRATEGIES]; // Stores correlation between strategies

    // For adaptive confirmation and lot sizing
    int m_winStreak;
    int m_lossStreak;
    datetime m_lastPerformanceUpdate;
    bool m_strategyEnabled[MAX_STRATEGIES];       // Indicates if a strategy is currently enabled for trading
    // ---- END OF NEWLY ADDED MEMBER VARIABLES ----

public:
    CStrategyManager_LegacyHidden() {
        m_strategyCount = 0;
        ArrayFree(m_strategies);
        ArrayFree(m_managedStrategyNames);

        // ---- INITIALIZE NEW MEMBERS ----
        m_minConfirmation = 0.5; // Default minimum confirmation
        m_currentRegime = REGIME_UNKNOWN;
        m_winStreak = 0;
        m_lossStreak = 0;
        m_lastPerformanceUpdate = 0;

        for(int i = 0; i < MAX_STRATEGIES; i++) {
            m_strategySignals[i] = 0;
            m_strategyConfidences[i] = 0.0;
            // m_strategyNames[i] = ""; // This will be populated by AddStrategy or a dedicated setup method
            m_strategyWinRate[i] = 0.5; // Default win rate
            m_strategyTradeCount[i] = 0;
            m_strategyWinCount[i] = 0;
            m_strategyLossCount[i] = 0;
            m_strategyProfitFactor[i] = 1.0; // Default profit factor
            for(int j = 0; j < MAX_STRATEGIES; j++) {
                m_correlationMatrix[i][j] = (i == j) ? 1.0 : 0.0; // Self-correlation is 1, others 0 initially
            }
            m_strategyEnabled[i] = true; // Initialize all strategies as enabled
        }
        // It's important to populate m_strategyNames correctly. For now, let's assume they get set up. Example:
        // m_strategyNames[0] = "RSI"; m_strategyNames[1] = "SupplyDemand"; ... m_strategyNames[10] = "Brain";
        // This setup should ideally happen in a dedicated method or after all strategies are added.
        // For now, ensure that any function using m_strategyNames checks for empty strings or uses m_managedStrategyNames.

        // ---- END OF INITIALIZATION ----

        PrintFormat("[INFO] CStrategyManager_LegacyHidden: Instance created and members initialized.");
    }

    ~CStrategyManager_LegacyHidden() {
        PrintFormat("[INFO] CStrategyManager_LegacyHidden: Destructor called. Cleaning up %d strategies...", m_strategyCount);
        for (int i = 0; i < m_strategyCount; i++) {
            if (CheckPointer(m_strategies[i]) == POINTER_DYNAMIC) {
                delete m_strategies[i];
            }
        }
        ArrayFree(m_strategies);
        ArrayFree(m_managedStrategyNames);
        m_strategyCount = 0;
        PrintFormat("[INFO] CStrategyManager_LegacyHidden: Cleanup complete.");
    }

    bool AddStrategy(IStrategy* strategy_ptr, const string strategy_name) {
        if (CheckPointer(strategy_ptr) != POINTER_DYNAMIC) {
            PrintFormat("[ERROR] CStrategyManager_LegacyHidden::AddStrategy: Invalid strategy pointer for '%s'.", strategy_name);
            return false;
        }

        int newSize = m_strategyCount + 1;
        if (ArrayResize(m_strategies, newSize) == newSize && ArrayResize(m_managedStrategyNames, newSize) == newSize) {
            m_strategies[m_strategyCount] = strategy_ptr;
            m_managedStrategyNames[m_strategyCount] = strategy_name;
            m_strategyCount = newSize;
            PrintFormat("[INFO] CStrategyManager_LegacyHidden::AddStrategy: Successfully added strategy '%s'. Total strategies: %d", strategy_name, m_strategyCount);
            return true;
        } else {
            PrintFormat("[ERROR] CStrategyManager_LegacyHidden::AddStrategy: Failed to resize strategy arrays for '%s'.", strategy_name);
            // Clean up the passed pointer if it can't be added, as the caller might not manage it anymore
            delete strategy_ptr; 
            return false;
        }
    }

    int GetStrategyCount() const {
        return m_strategyCount;
    }

    // Initializes all managed strategies
    bool InitializeStrategies(CPerformanceAnalytics *analytics, CMarketRegimeClassifier *regimeClassifier, 
                              CMarketAnalysis *pMarketAnalysis, CTradeManager *pTradeMgr, const string &symbol_for_all) {
        if (m_strategyCount == 0) {
            PrintFormat("[WARNING] CStrategyManager_LegacyHidden::InitializeStrategies: No strategies to initialize.");
            return true; // No strategies, so technically initialization is successful (or vacuously true)
        }
        bool all_initialized = true;
        for (int i = 0; i < m_strategyCount; i++) {
            if (CheckPointer(m_strategies[i]) == POINTER_DYNAMIC) {
                PrintFormat("[INFO] CStrategyManager_LegacyHidden::InitializeStrategies: Initializing strategy '%s' for symbol '%s'...", m_managedStrategyNames[i], symbol_for_all);
                if (!m_strategies[i].Initialize(analytics, regimeClassifier, pMarketAnalysis, pTradeMgr, symbol_for_all)) {
                    PrintFormat("[ERROR] CStrategyManager_LegacyHidden::InitializeStrategies: Failed to initialize strategy '%s'.", m_managedStrategyNames[i]);
                    all_initialized = false;
                    // Decide if one failure means all fail, or continue initializing others
                }
            } else {
                 PrintFormat("[ERROR] CStrategyManager_LegacyHidden::InitializeStrategies: Found invalid pointer for strategy '%s'.", m_managedStrategyNames[i]);
                 all_initialized = false;
            }
        }
        return all_initialized;
    }

    // Gets signals from all managed strategies
    void GetSignals(const string &symbol, ENUM_MARKET_REGIME regimeParam, 
                    int &out_signals[], double &out_confidences[], string &out_names[]) {
        if (m_strategyCount == 0) {
            ArrayResize(out_signals, 0);
            ArrayResize(out_confidences, 0);
            ArrayResize(out_names, 0);
            return;
        }

        ArrayResize(out_signals, m_strategyCount);
        ArrayResize(out_confidences, m_strategyCount);
        ArrayResize(out_names, m_strategyCount);

        for (int i = 0; i < m_strategyCount; i++) {
            if (CheckPointer(m_strategies[i]) == POINTER_DYNAMIC) {
                out_signals[i] = m_strategies[i].GetSignal(symbol, out_confidences[i], regimeParam);
                out_names[i] = m_strategies[i].GetName(); // Or use m_managedStrategyNames[i]
            } else {
                out_signals[i] = 0; // No signal
                out_confidences[i] = 0.0;
                out_names[i] = "Error: Invalid Strategy Ptr";
                PrintFormat("[ERROR] CStrategyManager_LegacyHidden::GetSignals: Invalid strategy pointer at index %d ('%s').", i, m_managedStrategyNames[i]);
            }
        }
    }
    
    // Calls OnTick for all managed strategies
    void OnTick(const string &symbol) {
        for (int i = 0; i < m_strategyCount; i++) {
            if (CheckPointer(m_strategies[i]) == POINTER_DYNAMIC) {
                m_strategies[i].OnTick(symbol);
            }
        }
    }

    // Calls OnTimer for all managed strategies
    void OnTimer(const string &symbol) {
        for (int i = 0; i < m_strategyCount; i++) {
            if (CheckPointer(m_strategies[i]) == POINTER_DYNAMIC) {
                m_strategies[i].OnTimer(symbol);
            }
        }
    }
    
    // Updates parameters for all managed strategies
    void UpdateParameters(const CTradeManager* pTradeMgr) {
        for (int i = 0; i < m_strategyCount; i++) {
            if (CheckPointer(m_strategies[i]) == POINTER_DYNAMIC) {
                m_strategies[i].UpdateParameters(pTradeMgr);
            }
        }
    }

    // Resets state for all managed strategies
    void ResetStates() {
        for (int i = 0; i < m_strategyCount; i++) {
            if (CheckPointer(m_strategies[i]) == POINTER_DYNAMIC) {
                m_strategies[i].ResetState();
            }
        }
    }

    void Initialize(double minConfirmation) {
        m_minConfirmation = minConfirmation;
    }
    
    void SetMarketRegime(ENUM_MARKET_REGIME regime) {
        m_currentRegime = regime;
    }
    
    // Filter conflicting signals from correlated strategies
    void FilterConflictingSignals() {
        // First pass: identify all strategies with signals
        int signalCount = 0;
        int strategiesWithSignals[MAX_STRATEGIES];
        int signalDirections[MAX_STRATEGIES];
        
        for(int i=0; i<MAX_STRATEGIES; i++) {
            if(m_strategySignals[i] != 0) {
                strategiesWithSignals[signalCount] = i;
                signalDirections[signalCount] = m_strategySignals[i];
                signalCount++;
            }
        }
        
        // If we have fewer than 2 signals, no conflicts to resolve
        if(signalCount < 2) return;
        
        // Second pass: check for conflicts between correlated strategies
        for(int i=0; i<signalCount; i++) {
            int stratA = strategiesWithSignals[i];
            int signalA = signalDirections[i];
            
            // Skip if this strategy's signal was already nullified
            if(m_strategySignals[stratA] == 0) continue;
            
            for(int j=i+1; j<signalCount; j++) {
                int stratB = strategiesWithSignals[j];
                int signalB = signalDirections[j];
                
                // Skip if this strategy's signal was already nullified
                if(m_strategySignals[stratB] == 0) continue;
                
                // Check if strategies are correlated and have conflicting signals
                if(m_correlationMatrix[stratA][stratB] > 0.5 && signalA != signalB) {
                    // Conflict detected between correlated strategies
                    // Keep the signal from the strategy with better performance
                    if(m_strategyWinRate[stratA] >= m_strategyWinRate[stratB]) {
                        // Strategy A has better performance, keep its signal
                        m_strategySignals[stratB] = 0;
                        m_strategyConfidences[stratB] = 0.0;
                        Print("[CORRELATION FILTER] Removed conflicting signal from ", 
                              m_strategyNames[stratB], " (win rate: ", 
                              NormalizeDouble(m_strategyWinRate[stratB], 2), 
                              ") in favor of ", m_strategyNames[stratA], 
                              " (win rate: ", NormalizeDouble(m_strategyWinRate[stratA], 2), ")");
                    } else {
                        // Strategy B has better performance, keep its signal
                        m_strategySignals[stratA] = 0;
                        m_strategyConfidences[stratA] = 0.0;
                        Print("[CORRELATION FILTER] Removed conflicting signal from ", 
                              m_strategyNames[stratA], " (win rate: ", 
                              NormalizeDouble(m_strategyWinRate[stratA], 2), 
                              ") in favor of ", m_strategyNames[stratB], 
                              " (win rate: ", NormalizeDouble(m_strategyWinRate[stratB], 2), ")");
                        break; // Break inner loop since stratA's signal is now nullified
                    }
                }
            }
        }
    }
    
    // Filter strategies based on market regime and performance
    void FilterStrategies() {
        // Reset all strategies to enabled
        for(int i=0; i<MAX_STRATEGIES; i++) {
            m_strategyEnabled[i] = true;
        }
        
        // Always enable the Brain strategy as it's our meta-strategy
        m_strategyEnabled[10] = true;
        
        // Filter based on market regime
        switch(m_currentRegime) {
            case REGIME_TREND:
                // In trending markets, prioritize trend-following strategies
                m_strategyEnabled[7] = true;  // Trend
                m_strategyEnabled[13] = true; // Ichimoku
                
                // Reduce priority of mean-reversion strategies
                if(m_strategyWinRate[0] < 0.4) m_strategyEnabled[0] = false; // RSI
                if(m_strategyWinRate[8] < 0.4) m_strategyEnabled[8] = false; // MeanReversion
                break;
                
            case REGIME_RANGE:
                // In ranging markets, prioritize mean-reversion strategies
                m_strategyEnabled[0] = true;  // RSI
                m_strategyEnabled[8] = true;  // MeanReversion
                m_strategyEnabled[12] = true; // BollingerBreakout
                
                // Reduce priority of trend-following strategies
                if(m_strategyWinRate[7] < 0.4) m_strategyEnabled[7] = false; // Trend
                break;
                
            case REGIME_VOLATILE:
                // In volatile markets, prioritize breakout and volatility strategies
                m_strategyEnabled[6] = true;  // Volatility
                m_strategyEnabled[9] = true;  // Breakout
                m_strategyEnabled[12] = true; // BollingerBreakout
                
                // Disable pattern-based strategies which may fail in volatile conditions
                m_strategyEnabled[3] = false; // Fibonacci
                m_strategyEnabled[4] = false; // Elliott
                m_strategyEnabled[14] = false; // HarmonicPatterns
                break;
        }
        
        // Disable strategies with consistently poor performance
        for(int i=0; i<MAX_STRATEGIES; i++) {
            if(i == 10) continue; // Skip Brain strategy
            
            if(m_strategyTradeCount[i] >= 10 && m_strategyWinRate[i] < 0.3) {
                m_strategyEnabled[i] = false;
                Print("[STRATEGY FILTER] Disabling low-performing strategy: ", m_strategyNames[i], 
                      ", Win rate: ", NormalizeDouble(m_strategyWinRate[i], 2));
            }
        }
    }
    
    // Get strategy signals with error handling
    bool GetStrategySignals(string symbol) {
        // Validate input
        if(symbol == "") {
            Print("[ERROR] GetStrategySignals: Empty symbol");
            return false;
        }
        
        // Check if symbol is valid before proceeding
        if(!SymbolInfoInteger(symbol, SYMBOL_SELECT)) {
            Print("[ERROR] GetStrategySignals: Symbol ", symbol, " is not selected in Market Watch");
            return false;
        }
        
        // Filter strategies based on current market conditions
        FilterStrategies();
        
        // Initialize arrays with default values
        ArrayInitialize(m_strategySignals, 0);       // No signal by default
        ArrayInitialize(m_strategyConfidences, 0.0); // No confidence by default
        
        // Performance tracking
        uint startTime = (uint)GetTickCount();
        bool anyStrategySucceeded = false;
        
        // Execute RSI strategy if enabled
        if(m_strategyEnabled[0]) {
            m_strategySignals[0] = StrategyRSI(m_strategyConfidences[0]);
            if(GetLastError() == 0) anyStrategySucceeded = true;
            else Print("[ERROR] RSI Strategy failed: ", GetLastError());
        }
        
        // Supply/Demand and OrderBlockFVG strategies removed - covered by SMC
        // Use SMC strategy instead which includes both
        
        // Execute Fibonacci strategy if enabled
        if(m_strategyEnabled[3]) {
            m_strategySignals[3] = StrategyFibonacci(m_strategyConfidences[3]);
            if(GetLastError() == 0) anyStrategySucceeded = true;
            else Print("[ERROR] Fibonacci Strategy failed: ", GetLastError());
        }
        
        // Elliott strategy removed - redundant with Elliott Wave Enhanced
        // (covered by StrategyElliottWaveEnhanced in TradingEngine)
        
        // Execute Swing strategy if enabled
        if(m_strategyEnabled[5]) {
            m_strategySignals[5] = StrategySwing(m_strategyConfidences[5]);
            if(GetLastError() == 0) anyStrategySucceeded = true;
            else Print("[ERROR] Swing Strategy failed: ", GetLastError());
        }
        
        // Execute Volatility strategy if enabled
        if(m_strategyEnabled[6]) {
            m_strategySignals[6] = StrategyVolatility(m_strategyConfidences[6]);
            if(GetLastError() == 0) anyStrategySucceeded = true;
            else Print("[ERROR] Volatility Strategy failed: ", GetLastError());
        }
        
        // Execute Trend strategy if enabled
        if(m_strategyEnabled[7]) {
            m_strategySignals[7] = StrategyTrend(m_strategyConfidences[7]);
            if(GetLastError() == 0) anyStrategySucceeded = true;
            else Print("[ERROR] Trend Strategy failed: ", GetLastError());
        }
        
        // Execute MeanReversion strategy if enabled
        if(m_strategyEnabled[8]) {
            m_strategySignals[8] = StrategyMeanReversion(m_strategyConfidences[8]);
            if(GetLastError() == 0) anyStrategySucceeded = true;
            else Print("[ERROR] Mean Reversion Strategy failed: ", GetLastError());
        }
        
        // Execute Breakout strategy if enabled
        if(m_strategyEnabled[9]) {
            m_strategySignals[9] = StrategyBreakout(m_strategyConfidences[9]);
            if(GetLastError() == 0) anyStrategySucceeded = true;
            else Print("[ERROR] Breakout Strategy failed: ", GetLastError());
        }
        
        // Execute MACD strategy if enabled
        if(m_strategyEnabled[11]) {
            m_strategySignals[11] = StrategyMACD(m_strategyConfidences[11]);
            if(GetLastError() == 0) anyStrategySucceeded = true;
            else Print("[ERROR] MACD Strategy failed: ", GetLastError());
        }
        
        // Execute BollingerBreakout strategy if enabled
        if(m_strategyEnabled[12]) {
            m_strategySignals[12] = StrategyBollingerBreakout(m_strategyConfidences[12]);
            if(GetLastError() == 0) anyStrategySucceeded = true;
            else Print("[ERROR] Bollinger Breakout Strategy failed: ", GetLastError());
        }
        
        // Execute Ichimoku strategy if enabled
        if(m_strategyEnabled[13]) {
            m_strategySignals[13] = StrategyIchimoku(m_strategyConfidences[13]);
            if(GetLastError() == 0) anyStrategySucceeded = true;
            else Print("[ERROR] Ichimoku Strategy failed: ", GetLastError());
        }
        
        // Execute HarmonicPatterns strategy if enabled
        if(m_strategyEnabled[14]) {
            m_strategySignals[14] = StrategyHarmonicPatterns(m_strategyConfidences[14]);
            if(GetLastError() == 0) anyStrategySucceeded = true;
            else Print("[ERROR] Harmonic Patterns Strategy failed: ", GetLastError());
        }
        
        // Filter conflicting signals from correlated strategies
        FilterConflictingSignals();
        
        // Get brain signal last as it depends on other signals
        if(anyStrategySucceeded) {
            // Always enable the Brain strategy
            m_strategyEnabled[10] = true;
            
            double brainInputs[14]; // Increased array size to include new strategies
            ArrayCopy(brainInputs, m_strategyConfidences, 0, 0, 14);
            m_strategySignals[10] = StrategyBrain(m_strategyConfidences[10], brainInputs);
            if(GetLastError() == 0) anyStrategySucceeded = true;
            else Print("[ERROR] Brain Strategy failed: ", GetLastError());
        }
        
        // Log performance metrics
        uint endTime = (uint)GetTickCount();
        uint executionTime = endTime - startTime;
        if(executionTime > 100) { // Log only if execution time is significant
            Print("[PERFORMANCE] GetStrategySignals for ", symbol, " took ", executionTime, " ms");
        }
        
        return anyStrategySucceeded;
    }
    
    // Weighted voting system
    void WeightedVote(int& buyVotes, int& sellVotes, double& confSumBuy, double& confSumSell) {
        buyVotes = 0; sellVotes = 0; 
        confSumBuy = 0; confSumSell = 0;
        
        for(int i = 0; i < MAX_STRATEGIES; i++) {
            double weight = 1.0 + m_strategyWinRate[i];
            if(m_strategySignals[i] == 1) {
                buyVotes++;
                confSumBuy += m_strategyConfidences[i] * weight;
            } else if(m_strategySignals[i] == -1) {
                sellVotes++;
                confSumSell += m_strategyConfidences[i] * weight;
            }
        }
    }
    
    // Get weighted voting results for strategy signals
    void GetWeightedVotingResults(int& buyVotes, int& sellVotes, double& confSumBuy, double& confSumSell) {
        WeightedVote(buyVotes, sellVotes, confSumBuy, confSumSell);
    }
    
    // Get adaptive minimum confirmation threshold based on market conditions
    int GetAdaptiveMinimumConfirmation() const {
        return (int)AdaptiveMinimumConfirmation();
    }
    
    // Calculate smart lot size based on strategy performance
    double GetSmartLotSize(double baseLot) {
        // Adjust lot size based on win streak and market regime
        double multiplier = 1.0;
        
        // Increase lot size if we're on a winning streak
        if(m_winStreak >= 3) multiplier *= 1.2;
        if(m_winStreak >= 5) multiplier *= 1.3;
        
        // Decrease lot size if we're on a losing streak
        if(m_lossStreak >= 2) multiplier *= 0.8;
        if(m_lossStreak >= 4) multiplier *= 0.7;
        
        // Adjust based on market regime
        if(m_currentRegime == REGIME_VOLATILE) multiplier *= 0.8; // Reduce risk in volatile markets
        if(m_currentRegime == REGIME_TREND) multiplier *= 1.2;   // Increase in trending markets
        
        // Apply multiplier to base lot size
        double smartLot = baseLot * multiplier;
        
        // Ensure minimum lot size (0.01 for most brokers)
        return MathMax(smartLot, 0.01);
    }
    
    // Update strategy performance metrics
    void UpdateStrategyWinRate(int strategyIdx, bool win, double profit = 0.0, double loss = 0.0) {
        if(strategyIdx < 0 || strategyIdx >= MAX_STRATEGIES) return;
        
        // Update trade count
        m_strategyTradeCount[strategyIdx]++;
        
        // Update win/loss counts and streaks
        if(win) {
            m_strategyWinCount[strategyIdx]++;
            m_winStreak++;
            m_lossStreak = 0;
            
            // Update profit factor if loss data is available
            if(loss > 0.0) {
                double totalProfit = m_strategyProfitFactor[strategyIdx] * m_strategyLossCount[strategyIdx] * loss;
                totalProfit += profit;
                m_strategyProfitFactor[strategyIdx] = totalProfit / (m_strategyLossCount[strategyIdx] * loss);
            }
        } else {
            m_strategyLossCount[strategyIdx]++;
            m_lossStreak++;
            m_winStreak = 0;
            
            // Update profit factor if profit data is available
            if(profit > 0.0) {
                double totalLoss = m_strategyLossCount[strategyIdx] * loss;
                double totalProfit = m_strategyWinCount[strategyIdx] * profit;
                if(totalLoss > 0.0) {
                    m_strategyProfitFactor[strategyIdx] = totalProfit / totalLoss;
                }
            }
        }
        
        // Calculate win rate directly from win/loss counts for more accuracy
        if(m_strategyTradeCount[strategyIdx] > 0) {
            m_strategyWinRate[strategyIdx] = (double)m_strategyWinCount[strategyIdx] / m_strategyTradeCount[strategyIdx];
        } else {
            // Default to 50% if no trades yet
            m_strategyWinRate[strategyIdx] = 0.5;
        }
        
        // Log performance update
        Print("[PERFORMANCE] Strategy ", m_strategyNames[strategyIdx], 
              " updated: Win Rate=", NormalizeDouble(m_strategyWinRate[strategyIdx], 2), 
              ", Trades=", m_strategyTradeCount[strategyIdx], 
              ", Profit Factor=", NormalizeDouble(m_strategyProfitFactor[strategyIdx], 2));
        
        // Update last performance update timestamp
        m_lastPerformanceUpdate = TimeCurrent();
    }
    
    // Get strategy name by index
    string GetStrategyName(int index) const {
        if(index >= 0 && index < MAX_STRATEGIES)
            return m_strategyNames[index];
        return "Unknown";
    }
    
    // Get current confidence threshold
    double GetConfidenceThreshold() const {
        return AdaptiveMinimumConfirmation();
    }
    
    // Update trade result for performance tracking
    void UpdateTradeResult(bool success, double profit = 0.0, double loss = 0.0) {
        // Update brain strategy performance (index 10)
        int brainIndex = 10;
        
        // Update win/loss streaks
        if(success) {
            m_winStreak++;
            m_lossStreak = 0;
        } else {
            m_lossStreak++;
            m_winStreak = 0;
        }
        
        // Update strategy win rate
        UpdateStrategyWinRate(brainIndex, success, profit, loss);
        
        // Log the update
        Print("[PERFORMANCE] Brain strategy trade result updated: ", 
              (success ? "SUCCESS" : "FAILURE"), 
              ", Win streak: ", m_winStreak, 
              ", Loss streak: ", m_lossStreak);
    }

private:
    // Returns adaptive minimum confirmation threshold (placeholder implementation)
    double AdaptiveMinimumConfirmation() const {
        return 1.0;
    }

// --- Temporary stub strategy functions (to be replaced with real implementations) ---
#define DECLARE_STUB_STRATEGY(name) int name(double &out_confidence) { out_confidence = 0.0; return 0; }

    DECLARE_STUB_STRATEGY(StrategyMACD)
    DECLARE_STUB_STRATEGY(StrategyBollingerBreakout)
    DECLARE_STUB_STRATEGY(StrategyIchimoku)
    DECLARE_STUB_STRATEGY(StrategyHarmonicPatterns)
#undef DECLARE_STUB_STRATEGY

};

#endif
