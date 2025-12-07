//+------------------------------------------------------------------+
//| Strategy Correlation Matrix Module                                |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_CORRELATION_MATRIX_MQH__
#define __STRATEGY_CORRELATION_MATRIX_MQH__

#ifndef MAX_STRATEGIES
#define MAX_STRATEGIES 15
#endif

// Include project headers
#include "../Core/Strategy/StrategyBase.mqh"
#include "../Core/Utils/Enums.mqh"
#include "../Interfaces/IStrategy.mqh"
#include "../Core/Trading/TradeManager.mqh"
#include "../Core/Risk/PositionSizer.mqh"
#include "../Core/Strategy/StrategyFactory.mqh"

// This file originally contained a manager class. It has been renamed to CCorrelationManager
// to preserve the logic, while a proper strategy stub (CStrategyCorrelationMatrix) has been
// created to resolve compilation errors. The manager logic needs to be integrated properly later.

// Strategy signal history for correlation calculation
struct SStrategySignalHistory {
    int     signals[100];       // Array of historical signals (-1, 0, 1)
    int     currentIndex;       // Current index in the circular buffer
    int     count;              // Number of signals recorded
};

// Renamed from CStrategyCorrelationMatrix to avoid conflict with the actual strategy class
class CStrategyCorrelationMatrix : public CStrategyBase {
private:
    double m_correlationMatrix[MAX_STRATEGIES][MAX_STRATEGIES]; // Correlation matrix
    string m_strategyNames[MAX_STRATEGIES];                     // Strategy names
    int    m_strategyCount;                                     // Number of strategies
    
    // Signal history for correlation calculation
    SStrategySignalHistory m_signalHistory[MAX_STRATEGIES];
    
    // Strategy performance metrics
    double m_strategyWinRate[MAX_STRATEGIES];                   // Win rate for each strategy
    double m_strategyProfitFactor[MAX_STRATEGIES];              // Profit factor for each strategy
    double m_strategyConfidenceThreshold[MAX_STRATEGIES];       // Minimum confidence threshold for each strategy
    
    // Calculate correlation between two strategies based on signal history
    double CalculateCorrelation(int strategyA, int strategyB) {
        if(strategyA < 0 || strategyA >= m_strategyCount || 
           strategyB < 0 || strategyB >= m_strategyCount) {
            return 0.0;
        }
        
        // Need at least 10 signals for meaningful correlation
        if(m_signalHistory[strategyA].count < 10 || m_signalHistory[strategyB].count < 10) {
            return 0.0;
        }
        
        // Calculate correlation using Pearson correlation coefficient
        int n = MathMin(m_signalHistory[strategyA].count, m_signalHistory[strategyB].count);
        n = MathMin(n, 100); // Limit to buffer size
        
        double sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0, sumY2 = 0;
        
        for(int i = 0; i < n; i++) {
            int idxA = (m_signalHistory[strategyA].currentIndex - i + 100) % 100;
            int idxB = (m_signalHistory[strategyB].currentIndex - i + 100) % 100;
            
            double x = (double)m_signalHistory[strategyA].signals[idxA];
            double y = (double)m_signalHistory[strategyB].signals[idxB];
            
            sumX += x;
            sumY += y;
            sumXY += x * y;
            sumX2 += x * x;
            sumY2 += y * y;
        }
        
        // Calculate correlation coefficient
        double numerator = n * sumXY - sumX * sumY;
        double denominator = MathSqrt((n * sumX2 - sumX * sumX) * (n * sumY2 - sumY * sumY));
        
        if(denominator < 0.000001) return 0.0; // Avoid division by zero
        
        double correlation = numerator / denominator;
        
        // Ensure correlation is between -1 and 1
        correlation = MathMax(-1.0, MathMin(1.0, correlation));
        
        return correlation;
    }
    
    // Update correlation matrix based on current signal history
    void UpdateCorrelationMatrix() {
        for(int i = 0; i < m_strategyCount; i++) {
            for(int j = i; j < m_strategyCount; j++) {
                if(i == j) {
                    m_correlationMatrix[i][j] = 1.0; // Perfect correlation with self
                } else {
                    double correlation = CalculateCorrelation(i, j);
                    
                    // Use absolute value for correlation strength
                    double correlationStrength = MathAbs(correlation);
                    
                    m_correlationMatrix[i][j] = correlationStrength;
                    m_correlationMatrix[j][i] = correlationStrength; // Matrix is symmetric
                }
            }
        }
    }
    
public:
    CStrategyCorrelationMatrix(const string name, int magic, CTradeManager* tradeManagerPtr, CPositionSizer* sizerPtr) : CStrategyBase(name, magic) {
        m_strategyCount = 0;
        
        // Initialize correlation matrix to zeros
        ArrayInitialize(m_correlationMatrix, 0.0);
        for(int i = 0; i < MAX_STRATEGIES; i++) {
            for(int j = 0; j < MAX_STRATEGIES; j++) {
                m_correlationMatrix[i][j] = 0.0;
            }
        }
    }

    virtual ~CStrategyCorrelationMatrix() {}

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeManagerPtr, void* positionSizerPtr) override {
        if(!CStrategyBase::Init(symbol, timeframe, tradeManagerPtr, positionSizerPtr)) return false;
        SetEnabled(false); // This is not a real strategy, so disable it.
        return true;
    }

    virtual void Deinit() override {}

    // Initialize with strategy names
    void Initialize(const string &strategyNames[], int count) {
        m_strategyCount = MathMin(count, MAX_STRATEGIES);
        
        // Copy strategy names
        for(int i = 0; i < m_strategyCount; i++) {
            m_strategyNames[i] = strategyNames[i];
        }
        
        // Set predefined correlations for known strategy pairs
        
        // Mean reversion strategies are often correlated
        SetCorrelation("RSI", "MeanReversion", 0.7);
        
        // Trend following strategies are often correlated
        SetCorrelation("Trend", "MACD", 0.6);
        SetCorrelation("Trend", "Ichimoku", 0.6);
        
        // Pattern-based strategies can be correlated
        SetCorrelation("Elliott", "HarmonicPatterns", 0.5);
        SetCorrelation("Fibonacci", "Elliott", 0.6);
        
        // Volatility-based strategies
        SetCorrelation("Volatility", "BollingerBreakout", 0.6);
        
        // Support/resistance based strategies
        SetCorrelation("SupplyDemand", "OrderBlockFVG", 0.7);
    }
    
    // Add a new strategy signal to history
    void AddSignal(int strategyIndex, int signal) {
        if(strategyIndex < 0 || strategyIndex >= m_strategyCount) return;
        
        // Add signal to history
        m_signalHistory[strategyIndex].signals[m_signalHistory[strategyIndex].currentIndex] = signal;
        
        // Update index and count
        m_signalHistory[strategyIndex].currentIndex = (m_signalHistory[strategyIndex].currentIndex + 1) % 100;
        m_signalHistory[strategyIndex].count = MathMin(m_signalHistory[strategyIndex].count + 1, 100);
        
        // Update correlation matrix periodically
        static datetime lastUpdate = 0;
        if(TimeCurrent() - lastUpdate > 3600) { // Update once per hour
            UpdateCorrelationMatrix();
            lastUpdate = TimeCurrent();
        }
    }
    
    // Set correlation between two strategies
    void SetCorrelation(const string &strategyA, const string &strategyB, double correlation) {
        int idxA = -1, idxB = -1;
        
        // Find strategy indices
        for(int i = 0; i < m_strategyCount; i++) {
            if(m_strategyNames[i] == strategyA) idxA = i;
            if(m_strategyNames[i] == strategyB) idxB = i;
        }
        
        if(idxA >= 0 && idxB >= 0) {
            m_correlationMatrix[idxA][idxB] = correlation;
            m_correlationMatrix[idxB][idxA] = correlation; // Matrix is symmetric
        }
    }
    
    // Get correlation between two strategies
    double GetCorrelation(int strategyA, int strategyB) {
        if(strategyA < 0 || strategyA >= m_strategyCount || 
           strategyB < 0 || strategyB >= m_strategyCount) {
            return 0.0;
        }
        
        return m_correlationMatrix[strategyA][strategyB];
    }
    
    // Get correlation between two strategies by name
    double GetCorrelation(const string &strategyA, const string &strategyB) {
        int idxA = -1, idxB = -1;
        
        // Find strategy indices
        for(int i = 0; i < m_strategyCount; i++) {
            if(m_strategyNames[i] == strategyA) idxA = i;
            if(m_strategyNames[i] == strategyB) idxB = i;
        }
        
        if(idxA >= 0 && idxB >= 0) {
            return m_correlationMatrix[idxA][idxB];
        }
        
        return 0.0;
    }
    
    // Update strategy performance metrics
    void UpdateStrategyPerformance(int strategyIndex, double winRate, double profitFactor) {
        if(strategyIndex < 0 || strategyIndex >= m_strategyCount) return;
        
        m_strategyWinRate[strategyIndex] = winRate;
        m_strategyProfitFactor[strategyIndex] = profitFactor;
        
        // Adjust confidence threshold based on performance
        // Higher performing strategies can trade with lower confidence
        if(winRate > 0.6 && profitFactor > 1.5) {
            m_strategyConfidenceThreshold[strategyIndex] = 1.5;
        } else if(winRate < 0.4 || profitFactor < 0.8) {
            m_strategyConfidenceThreshold[strategyIndex] = 3.0; // Require higher confidence
        } else {
            m_strategyConfidenceThreshold[strategyIndex] = 2.0; // Default
        }
    }
    
    // Get minimum confidence threshold for a strategy
    double GetConfidenceThreshold(int strategyIndex) {
        if(strategyIndex < 0 || strategyIndex >= m_strategyCount) return 2.0;
        
        return m_strategyConfidenceThreshold[strategyIndex];
    }
    
    // Filter conflicting signals from correlated strategies
    void FilterConflictingSignals(int &signals[], double &confidences[]) {
        // Create local copies to modify
        int local_signals[];
        double local_confidences[];
        ArrayCopy(local_signals, signals);
        ArrayCopy(local_confidences, confidences);

        // First pass: identify all strategies with signals
        int signalCount = 0;
        int strategiesWithSignals[MAX_STRATEGIES];
        
        for(int i = 0; i < m_strategyCount; i++) {
            if(local_signals[i] != 0) {
                strategiesWithSignals[signalCount] = i;
                signalCount++;
            }
        }
        
        // If we have fewer than 2 signals, no conflicts to resolve
        if(signalCount < 2) return;
        
        // Second pass: check for conflicts between correlated strategies
        for(int i = 0; i < signalCount; i++) {
            int stratA = strategiesWithSignals[i];
            
            // Skip if this strategy's signal was already nullified
            if(local_signals[stratA] == 0) continue;
            
            for(int j = i + 1; j < signalCount; j++) {
                int stratB = strategiesWithSignals[j];
                
                // Skip if this strategy's signal was already nullified
                if(local_signals[stratB] == 0) continue;
                
                // Check if strategies are correlated and have conflicting signals
                if(GetCorrelation(stratA, stratB) > 0.6 && local_signals[stratA] != local_signals[stratB]) {
                    // Decide which signal to keep based on performance
                    bool keepStratA = true;
                    
                    if(m_strategyProfitFactor[stratA] > m_strategyProfitFactor[stratB] * 1.2) keepStratA = true;
                    else if(m_strategyProfitFactor[stratB] > m_strategyProfitFactor[stratA] * 1.2) keepStratA = false;
                    else if(m_strategyWinRate[stratA] > m_strategyWinRate[stratB]) keepStratA = true;
                    else keepStratA = false;
                    
                    if(local_confidences[stratA] > local_confidences[stratB] * 1.5) keepStratA = true;
                    else if(local_confidences[stratB] > local_confidences[stratA] * 1.5) keepStratA = false;
                    
                    if(keepStratA) {
                        local_signals[stratB] = 0;
                        local_confidences[stratB] = 0.0;
                        Print("[CONFLICT] Nullified signal from ", m_strategyNames[stratB], " in favor of ", m_strategyNames[stratA]);
                    } else {
                        local_signals[stratA] = 0;
                        local_confidences[stratA] = 0.0;
                        Print("[CONFLICT] Nullified signal from ", m_strategyNames[stratA], " in favor of ", m_strategyNames[stratB]);
                        break; 
                    }
                }
            }
        }
        // Copy the modified local arrays back to the original references
        ArrayCopy(signals, local_signals);
        ArrayCopy(confidences, local_confidences);
    }
    
    // Apply quality filter to strategy signals
    void ApplyQualityFilter(int &local_strategySignals_ref[], double &local_strategyConfidences_ref[]) {
        for(int i = 0; i < m_strategyCount; i++) {
            // Skip strategies with no signal
            if(local_strategySignals_ref[i] == 0) continue;
            
            // Check if confidence meets the threshold
            if(local_strategyConfidences_ref[i] < m_strategyConfidenceThreshold[i]) {
                Print("[QUALITY FILTER] Nullified low-confidence signal from ", m_strategyNames[i], 
                      " (", NormalizeDouble(local_strategyConfidences_ref[i], 2), " < ", 
                      NormalizeDouble(m_strategyConfidenceThreshold[i], 2), ")");
                
                local_strategySignals_ref[i] = 0;
                local_strategyConfidences_ref[i] = 0.0;
            }
        }
    }
    
    // Print correlation matrix for debugging
    void PrintCorrelationMatrix() {
        Print("Strategy Correlation Matrix:");
        string header = "          ";
        
        // Print header row
        for(int i = 0; i < m_strategyCount; i++) {
            header += StringSubstr(m_strategyNames[i], 0, 8) + " ";
        }
        Print(header);
        
        // Print matrix rows
        for(int i = 0; i < m_strategyCount; i++) {
            string row = StringSubstr(m_strategyNames[i], 0, 8) + " ";
            
            for(int j = 0; j < m_strategyCount; j++) {
                row += DoubleToString(m_correlationMatrix[i][j], 2) + "    ";
            }
            
            Print(row);
        }
    }

    //--- IStrategy implementation (stubbed)
    virtual void OnTick() override {}
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override {}
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        return TRADE_SIGNAL_NONE; // No signal
    }
};





#endif
