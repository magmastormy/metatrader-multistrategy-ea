//+------------------------------------------------------------------+
//| Symbol Diversification Optimizer                               |
//| Intelligent symbol selection, rotation, and performance optimization |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_SYMBOL_DIVERSIFICATION_OPTIMIZER_MQH
#define CORE_SYMBOL_DIVERSIFICATION_OPTIMIZER_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "PortfolioRiskManager.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CModeManager;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;
class CAIStrategyOrchestrator;

//+------------------------------------------------------------------+
//| Symbol Performance Metrics Structure                           |
//+------------------------------------------------------------------+
struct SSymbolPerformance
{
    string symbol;                    // Symbol name
    double totalReturn;               // Total return %
    double sharpeRatio;               // Risk-adjusted return
    double winRate;                   // Win rate %
    double profitFactor;              // Profit factor
    double maxDrawdown;               // Maximum drawdown %
    double averageReturn;             // Average return per trade
    double volatility;                // Price volatility
    int totalTrades;                  // Total number of trades
    int winningTrades;                // Number of winning trades
    int losingTrades;                 // Number of losing trades
    datetime lastTradeTime;           // Last trade timestamp
    double correlationScore;          // Average correlation with portfolio
    double diversificationValue;      // Diversification contribution score
    bool isActive;                    // Currently active for trading
    bool isBlacklisted;               // Temporarily blacklisted
    datetime blacklistExpiry;         // When blacklist expires
    string blacklistReason;           // Reason for blacklisting
    double performanceScore;          // Overall performance score (0-100)
    double riskScore;                 // Risk score (0-100, lower is better)
    double diversificationScore;      // Diversification score (0-100)
    
    // Enhanced metrics for intelligent selection
    double correlationStability;      // How stable correlation is over time
    double performanceTrend;          // Recent performance trend (-1 to 1)
    double optimalStrategyScore;      // Best strategy performance for this symbol
    ENUM_STRATEGY_TYPE bestStrategy;  // Most effective strategy for this symbol
    double strategyConsistency;       // How consistent the best strategy performs
    double marketRegimeFit;           // How well symbol fits current market regime
    int rankingPosition;              // Current ranking position (1 = best)
    double diversificationContribution; // Actual diversification contribution to portfolio
};

//+------------------------------------------------------------------+
//| Symbol Correlation Matrix                                      |
//+------------------------------------------------------------------+
struct SCorrelationMatrix
{
    string symbols[MAX_SYMBOLS];      // Symbol names
    double correlations[MAX_SYMBOLS][MAX_SYMBOLS]; // Correlation matrix
    int symbolCount;                  // Number of symbols
    datetime lastUpdate;              // Last correlation update
    bool isValid;                     // Matrix validity flag
};

//+------------------------------------------------------------------+
//| Symbol-Strategy Performance Tracking                           |
//+------------------------------------------------------------------+
struct SSymbolStrategyPerformance
{
    string symbol;                    // Symbol name
    ENUM_STRATEGY_TYPE strategy;      // Strategy type
    double winRate;                   // Win rate for this combination
    double profitFactor;              // Profit factor for this combination
    double sharpeRatio;               // Sharpe ratio for this combination
    int totalTrades;                  // Total trades for this combination
    double averageReturn;             // Average return per trade
    double consistency;               // Performance consistency score
    datetime lastUpdate;              // Last performance update
    bool isOptimal;                   // Is this the optimal strategy for symbol
};

//+------------------------------------------------------------------+
//| Symbol Selection Criteria                                      |
//+------------------------------------------------------------------+
struct SSelectionCriteria
{
    double minSharpeRatio;            // Minimum Sharpe ratio
    double minWinRate;                // Minimum win rate %
    double maxDrawdown;               // Maximum allowed drawdown %
    double maxCorrelation;            // Maximum correlation with portfolio
    int minTrades;                    // Minimum number of trades for evaluation
    double minDiversificationValue;   // Minimum diversification contribution
    bool requireProfitability;        // Must be profitable
    bool excludeHighRisk;             // Exclude high-risk symbols
    double riskTolerance;             // Risk tolerance level (0-100)
    
    // Enhanced intelligent selection criteria
    double minCorrelationStability;   // Minimum correlation stability
    double minPerformanceTrend;       // Minimum performance trend
    bool requireOptimalStrategy;      // Must have identified optimal strategy
    double minStrategyConsistency;    // Minimum strategy consistency
    double maxCorrelationChange;      // Maximum allowed correlation change
};

//+------------------------------------------------------------------+
//| Symbol Diversification Optimizer Class                         |
//+------------------------------------------------------------------+
class CSymbolDiversificationOptimizer
{
private:
    CPortfolioRiskManager* m_riskManager;     // Risk manager reference
    
    // Symbol tracking
    SSymbolPerformance m_symbolPerformance[MAX_SYMBOLS]; // Performance metrics
    SCorrelationMatrix m_correlationMatrix;   // Correlation matrix
    string m_activeSymbols[MAX_SYMBOLS];      // Currently active symbols
    string m_availableSymbols[MAX_SYMBOLS];   // All available symbols
    int m_activeSymbolCount;                  // Number of active symbols
    int m_availableSymbolCount;               // Number of available symbols
    
    // Selection criteria
    SSelectionCriteria m_selectionCriteria;  // Current selection criteria
    
    // Rotation settings
    int m_maxActiveSymbols;                   // Maximum active symbols
    int m_rotationPeriodHours;                // Rotation period in hours
    datetime m_lastRotation;                  // Last rotation timestamp
    bool m_autoRotationEnabled;               // Auto rotation flag
    
    // Performance tracking
    datetime m_lastPerformanceUpdate;         // Last performance update
    datetime m_lastCorrelationUpdate;         // Last correlation update
    int m_performanceUpdateIntervalMinutes;   // Update interval
    
    // Optimization settings
    bool m_adaptiveSelection;                 // Adaptive selection enabled
    double m_performanceDecayFactor;          // Performance decay factor
    double m_correlationThreshold;            // Correlation threshold
    
    // Enhanced intelligent selection data
    SSymbolStrategyPerformance m_strategyPerformance[MAX_SYMBOLS * 10]; // Strategy performance per symbol
    int m_strategyPerformanceCount;           // Number of strategy performance records
    double m_previousCorrelations[MAX_SYMBOLS][MAX_SYMBOLS]; // Previous correlation matrix
    datetime m_lastCorrelationChangeCheck;    // Last correlation change analysis
    bool m_correlationChangeDetected;         // Flag for correlation changes
    
    // Symbol ranking and rotation
    SSymbolPerformance m_performanceRankings[MAX_SYMBOLS]; // Current performance rankings
    int m_rankingCount;                       // Number of ranked symbols
    datetime m_lastRankingUpdate;             // Last ranking update
    int m_rotationCandidatesCount;            // Number of rotation candidates
    
    bool m_initialized;
    
public:
    // Constructor
    CSymbolDiversificationOptimizer(void);
    
    // Destructor
    ~CSymbolDiversificationOptimizer(void);
    
    // Initialize with dependencies
    bool Initialize(CPortfolioRiskManager* riskManager,
                   const string &availableSymbols[],
                   const int symbolCount);
    
    // Symbol selection and management
    bool SelectOptimalSymbols(string &selectedSymbols[], int &count);
    bool RotateSymbols(void);
    bool AddSymbolToPortfolio(const string symbol);
    bool RemoveSymbolFromPortfolio(const string symbol);
    
    // Performance tracking
    void UpdateSymbolPerformance(const string symbol, const STradeResult &tradeResult);
    void UpdateAllSymbolPerformance(void);
    void CalculatePerformanceScores(void);
    
    // Correlation analysis
    void UpdateCorrelationMatrix(void);
    double CalculateSymbolCorrelation(const string symbol1, const string symbol2);
    double GetPortfolioCorrelation(const string newSymbol);
    void PrintCorrelationMatrix(void);
    
    // Diversification optimization
    double CalculateDiversificationValue(const string symbol);
    bool OptimizePortfolioDiversification(void);
    string GetBestDiversificationSymbol(void);
    
    // Symbol ranking and scoring
    void RankSymbolsByPerformance(string &rankedSymbols[], double &scores[]);
    void RankSymbolsByDiversification(string &rankedSymbols[], double &scores[]);
    double CalculateOverallScore(const string symbol);
    
    // Blacklist management
    void BlacklistSymbol(const string symbol, const string reason, const int durationHours = 24);
    void RemoveFromBlacklist(const string symbol);
    bool IsSymbolBlacklisted(const string symbol);
    void ProcessBlacklistExpiry(void);
    
    // Strategy optimization per symbol
    void OptimizeSymbolStrategies(void);
    ENUM_STRATEGY_TYPE GetOptimalStrategy(const string symbol);
    void UpdateSymbolStrategyPerformance(const string symbol, const ENUM_STRATEGY_TYPE strategy, 
                                        const STradeResult &result);
    
    // Enhanced intelligent selection and rotation
    bool IntelligentSymbolSelection(string &selectedSymbols[], int &count);
    bool OptimalDiversificationRotation(void);
    void CreateSymbolPerformanceRanking(SSymbolPerformance &rankings[], int &rankingCount);
    void AnalyzeSymbolCorrelationChanges(void);
    void AdjustPositionLimitsBasedOnCorrelation(void);
    
    // Symbol-specific strategy optimization
    void OptimizeStrategiesPerSymbol(void);
    double CalculateStrategyEffectiveness(const string symbol, const ENUM_STRATEGY_TYPE strategy);
    void UpdateSymbolStrategyMapping(void);
    string GetSymbolSpecificStrategyReport(const string symbol);
    
    // Configuration
    void SetSelectionCriteria(const SSelectionCriteria &criteria);
    void SetMaxActiveSymbols(const int maxSymbols) { m_maxActiveSymbols = maxSymbols; }
    void SetRotationPeriod(const int hours) { m_rotationPeriodHours = hours; }
    void EnableAutoRotation(const bool enable) { m_autoRotationEnabled = enable; }
    
    // Information retrieval
    SSymbolPerformance GetSymbolPerformance(const string symbol);
    string GetActiveSymbolsList(void);
    string GetPerformanceReport(void);
    string GetDiversificationReport(void);
    int GetActiveSymbolCount(void) const { return m_activeSymbolCount; }
    
    // Validation and monitoring
    bool ValidateSymbolSelection(void);
    void MonitorSymbolHealth(void);
    bool IsSymbolHealthy(const string symbol);
    
private:
    // Internal calculations
    void InitializeDefaultCriteria(void);
    void InitializeSymbolPerformance(void);
    void UpdateSymbolMetrics(const string symbol);
    double CalculateVolatility(const string symbol, const int periods = 20);
    
    // Selection algorithms
    bool SelectByPerformance(string &symbols[], int &count);
    bool SelectByDiversification(string &symbols[], int &count);
    bool SelectHybridApproach(string &symbols[], int &count);
    
    // Correlation calculations
    double CalculateForexCorrelation(const string symbol1, const string symbol2);
    double CalculateDerivCorrelation(const string symbol1, const string symbol2);
    bool IsDerivSynthetic(const string symbol);
    
    // Performance calculations
    void CalculateSharpeRatio(SSymbolPerformance &performance);
    void CalculateDrawdown(SSymbolPerformance &performance);
    void ApplyPerformanceDecay(SSymbolPerformance &performance);
    
    // Utility functions
    int FindSymbolIndex(const string symbol);
    bool IsSymbolActive(const string symbol);
    void SortSymbolsByScore(string &symbols[], double &scores[], const int count);
    
    // Logging
    void LogOptimizationEvent(const ENUM_ERROR_LEVEL level, const string message);
};

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CSymbolDiversificationOptimizer::CSymbolDiversificationOptimizer(void) :
    m_riskManager(NULL),
    m_activeSymbolCount(0),
    m_availableSymbolCount(0),
    m_maxActiveSymbols(8),
    m_rotationPeriodHours(24),
    m_lastRotation(0),
    m_autoRotationEnabled(true),
    m_lastPerformanceUpdate(0),
    m_lastCorrelationUpdate(0),
    m_performanceUpdateIntervalMinutes(60),
    m_adaptiveSelection(true),
    m_performanceDecayFactor(0.95),
    m_correlationThreshold(0.6),
    m_strategyPerformanceCount(0),
    m_lastCorrelationChangeCheck(0),
    m_correlationChangeDetected(false),
    m_rankingCount(0),
    m_lastRankingUpdate(0),
    m_rotationCandidatesCount(0),
    m_initialized(false)
{
    // Initialize arrays
    ArrayInitialize(m_activeSymbols, "");
    ArrayInitialize(m_availableSymbols, "");
    
    // Initialize correlation matrix
    m_correlationMatrix.symbolCount = 0;
    m_correlationMatrix.lastUpdate = 0;
    m_correlationMatrix.isValid = false;
    ArrayInitialize(m_correlationMatrix.symbols, "");
    
    // Initialize performance array
    for(int i = 0; i < MAX_SYMBOLS; i++)
    {
        m_symbolPerformance[i].symbol = "";
        m_symbolPerformance[i].isActive = false;
        m_symbolPerformance[i].isBlacklisted = false;
        m_symbolPerformance[i].performanceScore = 0.0;
        m_symbolPerformance[i].totalTrades = 0;
    }
    
    InitializeDefaultCriteria();
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CSymbolDiversificationOptimizer::~CSymbolDiversificationOptimizer(void)
{
    if(m_initialized)
    {
        LogOptimizationEvent(ERROR_LEVEL_INFO, "Symbol diversification optimizer destroyed");
    }
}

//+------------------------------------------------------------------+
//| Initialize with dependencies                                   |
//+------------------------------------------------------------------+
bool CSymbolDiversificationOptimizer::Initialize(CPortfolioRiskManager* riskManager,
                                                const string &availableSymbols[],
                                                const int symbolCount)
{
    if(CheckPointer(riskManager) == POINTER_INVALID)
    {
        LogOptimizationEvent(ERROR_LEVEL_ERROR, "Invalid risk manager pointer");
        return false;
    }
    
    if(symbolCount <= 0 || symbolCount > MAX_SYMBOLS)
    {
        LogOptimizationEvent(ERROR_LEVEL_ERROR, 
                           StringFormat("Invalid symbol count: %d (max: %d)", symbolCount, MAX_SYMBOLS));
        return false;
    }
    
    m_riskManager = riskManager;
    m_availableSymbolCount = symbolCount;
    
    // Copy available symbols
    for(int i = 0; i < symbolCount; i++)
    {
        m_availableSymbols[i] = availableSymbols[i];
    }
    
    // Initialize symbol performance tracking
    InitializeSymbolPerformance();
    
    // Initial symbol selection
    string initialSymbols[];
    int initialCount = 0;
    if(SelectOptimalSymbols(initialSymbols, initialCount))
    {
        LogOptimizationEvent(ERROR_LEVEL_INFO, 
                           StringFormat("Initial symbol selection: %d symbols", initialCount));
    }
    
    m_initialized = true;
    m_lastPerformanceUpdate = TimeCurrent();
    m_lastCorrelationUpdate = TimeCurrent();
    
    LogOptimizationEvent(ERROR_LEVEL_INFO, 
                        StringFormat("Symbol diversification optimizer initialized with %d symbols", 
                                    symbolCount));
    
    return true;
}//
+------------------------------------------------------------------+
//| Select Optimal Symbols Based on Performance and Diversification |
//+------------------------------------------------------------------+
bool CSymbolDiversificationOptimizer::SelectOptimalSymbols(string &selectedSymbols[], int &count)
{
    if(!m_initialized)
    {
        LogOptimizationEvent(ERROR_LEVEL_ERROR, "Optimizer not initialized");
        return false;
    }
    
    // Update performance metrics before selection
    UpdateAllSymbolPerformance();
    UpdateCorrelationMatrix();
    
    // Clear previous selection
    ArrayResize(selectedSymbols, 0);
    count = 0;
    
    // Use hybrid approach for optimal selection
    if(!SelectHybridApproach(selectedSymbols, count))
    {
        LogOptimizationEvent(ERROR_LEVEL_ERROR, "Failed to select optimal symbols");
        return false;
    }
    
    // Update active symbols list
    m_activeSymbolCount = count;
    for(int i = 0; i < count && i < MAX_SYMBOLS; i++)
    {
        m_activeSymbols[i] = selectedSymbols[i];
        
        // Mark symbol as active in performance tracking
        int symbolIndex = FindSymbolIndex(selectedSymbols[i]);
        if(symbolIndex >= 0)
        {
            m_symbolPerformance[symbolIndex].isActive = true;
        }
    }
    
    LogOptimizationEvent(ERROR_LEVEL_INFO, 
                        StringFormat("Selected %d optimal symbols for trading", count));
    
    return true;
}

//+------------------------------------------------------------------+
//| Rotate Symbols Based on Performance and Market Conditions      |
//+------------------------------------------------------------------+
bool CSymbolDiversificationOptimizer::RotateSymbols(void)
{
    if(!m_initialized || !m_autoRotationEnabled)
        return false;
    
    datetime currentTime = TimeCurrent();
    
    // Check if rotation period has elapsed
    if(currentTime - m_lastRotation < m_rotationPeriodHours * 3600)
        return false;
    
    LogOptimizationEvent(ERROR_LEVEL_INFO, "Starting symbol rotation process");
    
    // Update all metrics before rotation
    UpdateAllSymbolPerformance();
    CalculatePerformanceScores();
    
    // Identify underperforming symbols
    string underperformers[];
    string candidates[];
    int underperformerCount = 0;
    int candidateCount = 0;
    
    // Find underperforming active symbols
    for(int i = 0; i < m_activeSymbolCount; i++)
    {
        string symbol = m_activeSymbols[i];
        SSymbolPerformance perf = GetSymbolPerformance(symbol);
        
        // Criteria for underperformance
        if(perf.performanceScore < 30.0 || // Low performance score
           perf.sharpeRatio < 0.5 ||       // Poor risk-adjusted returns
           perf.winRate < 40.0 ||          // Low win rate
           perf.totalTrades > 10 && perf.profitFactor < 1.1) // Unprofitable with sufficient trades
        {
            ArrayResize(underperformers, underperformerCount + 1);
            underperformers[underperformerCount] = symbol;
            underperformerCount++;
            
            LogOptimizationEvent(ERROR_LEVEL_INFO, 
                               StringFormat("Identified underperformer: %s (Score: %.1f, Sharpe: %.2f)", 
                                           symbol, perf.performanceScore, perf.sharpeRatio));
        }
    }
    
    // Find replacement candidates
    for(int i = 0; i < m_availableSymbolCount; i++)
    {
        string symbol = m_availableSymbols[i];
        
        // Skip if already active or blacklisted
        if(IsSymbolActive(symbol) || IsSymbolBlacklisted(symbol))
            continue;
        
        SSymbolPerformance perf = GetSymbolPerformance(symbol);
        
        // Criteria for good candidates
        if(perf.performanceScore > 50.0 && // Good performance score
           perf.sharpeRatio > 0.8 &&       // Good risk-adjusted returns
           GetPortfolioCorrelation(symbol) < m_correlationThreshold) // Low correlation
        {
            ArrayResize(candidates, candidateCount + 1);
            candidates[candidateCount] = symbol;
            candidateCount++;
        }
    }
    
    // Perform rotation
    int rotationsPerformed = 0;
    int maxRotations = MathMin(underperformerCount, candidateCount);
    maxRotations = MathMin(maxRotations, m_activeSymbolCount / 3); // Limit to 1/3 of portfolio
    
    for(int i = 0; i < maxRotations; i++)
    {
        // Remove underperformer
        if(RemoveSymbolFromPortfolio(underperformers[i]))
        {
            // Add best candidate
            if(AddSymbolToPortfolio(candidates[i]))
            {
                rotationsPerformed++;
                LogOptimizationEvent(ERROR_LEVEL_INFO, 
                                   StringFormat("Rotated: %s -> %s", underperformers[i], candidates[i]));
            }
        }
    }
    
    m_lastRotation = currentTime;
    
    LogOptimizationEvent(ERROR_LEVEL_INFO, 
                        StringFormat("Symbol rotation completed: %d symbols rotated", rotationsPerformed));
    
    return rotationsPerformed > 0;
}

//+------------------------------------------------------------------+
//| Update Symbol Performance Metrics                              |
//+------------------------------------------------------------------+
void CSymbolDiversificationOptimizer::UpdateSymbolPerformance(const string symbol, const STradeResult &tradeResult)
{
    if(!m_initialized)
        return;
    
    int symbolIndex = FindSymbolIndex(symbol);
    if(symbolIndex < 0)
    {
        // Add new symbol to tracking
        for(int i = 0; i < MAX_SYMBOLS; i++)
        {
            if(m_symbolPerformance[i].symbol == "")
            {
                m_symbolPerformance[i].symbol = symbol;
                symbolIndex = i;
                break;
            }
        }
    }
    
    if(symbolIndex < 0)
    {
        LogOptimizationEvent(ERROR_LEVEL_WARNING, "Cannot track more symbols - array full");
        return;
    }
    
    SSymbolPerformance &perf = m_symbolPerformance[symbolIndex];
    
    // Update trade statistics
    perf.totalTrades++;
    perf.lastTradeTime = tradeResult.closeTime;
    
    if(tradeResult.profit > 0)
    {
        perf.winningTrades++;
        perf.totalReturn += tradeResult.profitPercent;
    }
    else
    {
        perf.losingTrades++;
        perf.totalReturn += tradeResult.profitPercent; // Negative value
    }
    
    // Calculate derived metrics
    if(perf.totalTrades > 0)
    {
        perf.winRate = (double)perf.winningTrades / perf.totalTrades * 100.0;
        perf.averageReturn = perf.totalReturn / perf.totalTrades;
    }
    
    // Calculate profit factor
    double grossProfit = 0.0;
    double grossLoss = 0.0;
    
    // This is simplified - in real implementation, you'd track all trades
    if(tradeResult.profit > 0)
        grossProfit += tradeResult.profit;
    else
        grossLoss += MathAbs(tradeResult.profit);
    
    if(grossLoss > 0)
        perf.profitFactor = grossProfit / grossLoss;
    else
        perf.profitFactor = grossProfit > 0 ? 10.0 : 1.0;
    
    // Update performance score
    CalculatePerformanceScores();
    
    LogOptimizationEvent(ERROR_LEVEL_DEBUG, 
                        StringFormat("Updated performance for %s: WR=%.1f%%, PF=%.2f, Score=%.1f", 
                                    symbol, perf.winRate, perf.profitFactor, perf.performanceScore));
}

//+------------------------------------------------------------------+
//| Update Correlation Matrix                                      |
//+------------------------------------------------------------------+
void CSymbolDiversificationOptimizer::UpdateCorrelationMatrix(void)
{
    if(!m_initialized)
        return;
    
    datetime currentTime = TimeCurrent();
    
    // Update every hour
    if(currentTime - m_lastCorrelationUpdate < 3600)
        return;
    
    LogOptimizationEvent(ERROR_LEVEL_DEBUG, "Updating correlation matrix");
    
    // Update symbol list in correlation matrix
    m_correlationMatrix.symbolCount = m_availableSymbolCount;
    for(int i = 0; i < m_availableSymbolCount; i++)
    {
        m_correlationMatrix.symbols[i] = m_availableSymbols[i];
    }
    
    // Calculate correlations
    for(int i = 0; i < m_availableSymbolCount; i++)
    {
        for(int j = 0; j < m_availableSymbolCount; j++)
        {
            if(i == j)
            {
                m_correlationMatrix.correlations[i][j] = 1.0;
            }
            else
            {
                m_correlationMatrix.correlations[i][j] = 
                    CalculateSymbolCorrelation(m_availableSymbols[i], m_availableSymbols[j]);
            }
        }
    }
    
    m_correlationMatrix.lastUpdate = currentTime;
    m_correlationMatrix.isValid = true;
    m_lastCorrelationUpdate = currentTime;
    
    LogOptimizationEvent(ERROR_LEVEL_INFO, "Correlation matrix updated successfully");
}

//+------------------------------------------------------------------+
//| Calculate Diversification Value of a Symbol                    |
//+------------------------------------------------------------------+
double CSymbolDiversificationOptimizer::CalculateDiversificationValue(const string symbol)
{
    if(!m_initialized)
        return 0.0;
    
    double diversificationValue = 0.0;
    double totalCorrelation = 0.0;
    int correlationCount = 0;
    
    // Calculate average correlation with active symbols
    for(int i = 0; i < m_activeSymbolCount; i++)
    {
        if(m_activeSymbols[i] != symbol)
        {
            double correlation = MathAbs(CalculateSymbolCorrelation(symbol, m_activeSymbols[i]));
            totalCorrelation += correlation;
            correlationCount++;
        }
    }
    
    if(correlationCount > 0)
    {
        double averageCorrelation = totalCorrelation / correlationCount;
        // Higher diversification value for lower correlation
        diversificationValue = (1.0 - averageCorrelation) * 100.0;
    }
    else
    {
        // No active symbols to correlate with - maximum diversification
        diversificationValue = 100.0;
    }
    
    // Bonus for different asset classes
    bool isDerivSymbol = IsDerivSynthetic(symbol);
    int derivCount = 0;
    int forexCount = 0;
    
    for(int i = 0; i < m_activeSymbolCount; i++)
    {
        if(IsDerivSynthetic(m_activeSymbols[i]))
            derivCount++;
        else
            forexCount++;
    }
    
    // Bonus for balancing asset classes
    if(isDerivSymbol && forexCount > derivCount)
        diversificationValue += 20.0; // Bonus for adding Deriv when forex dominates
    else if(!isDerivSymbol && derivCount > forexCount)
        diversificationValue += 20.0; // Bonus for adding forex when Deriv dominates
    
    return MathMax(0.0, MathMin(100.0, diversificationValue));
}

//+------------------------------------------------------------------+
//| Optimize Portfolio Diversification                             |
//+------------------------------------------------------------------+
bool CSymbolDiversificationOptimizer::OptimizePortfolioDiversification(void)
{
    if(!m_initialized)
        return false;
    
    LogOptimizationEvent(ERROR_LEVEL_INFO, "Starting portfolio diversification optimization");
    
    // Update correlation matrix
    UpdateCorrelationMatrix();
    
    // Calculate current portfolio correlation
    double totalCorrelation = 0.0;
    int correlationPairs = 0;
    
    for(int i = 0; i < m_activeSymbolCount; i++)
    {
        for(int j = i + 1; j < m_activeSymbolCount; j++)
        {
            double correlation = MathAbs(CalculateSymbolCorrelation(m_activeSymbols[i], m_activeSymbols[j]));
            totalCorrelation += correlation;
            correlationPairs++;
        }
    }
    
    double averageCorrelation = correlationPairs > 0 ? totalCorrelation / correlationPairs : 0.0;
    
    LogOptimizationEvent(ERROR_LEVEL_INFO, 
                        StringFormat("Current portfolio average correlation: %.3f", averageCorrelation));
    
    // If correlation is too high, replace most correlated symbols
    if(averageCorrelation > m_correlationThreshold)
    {
        // Find the most correlated pair
        double maxCorrelation = 0.0;
        int maxI = -1, maxJ = -1;
        
        for(int i = 0; i < m_activeSymbolCount; i++)
        {
            for(int j = i + 1; j < m_activeSymbolCount; j++)
            {
                double correlation = MathAbs(CalculateSymbolCorrelation(m_activeSymbols[i], m_activeSymbols[j]));
                if(correlation > maxCorrelation)
                {
                    maxCorrelation = correlation;
                    maxI = i;
                    maxJ = j;
                }
            }
        }
        
        if(maxI >= 0 && maxJ >= 0)
        {
            // Remove the worse performing symbol from the correlated pair
            SSymbolPerformance perfI = GetSymbolPerformance(m_activeSymbols[maxI]);
            SSymbolPerformance perfJ = GetSymbolPerformance(m_activeSymbols[maxJ]);
            
            string symbolToRemove = (perfI.performanceScore < perfJ.performanceScore) ? 
                                   m_activeSymbols[maxI] : m_activeSymbols[maxJ];
            
            // Find best diversification replacement
            string bestReplacement = GetBestDiversificationSymbol();
            
            if(bestReplacement != "" && bestReplacement != symbolToRemove)
            {
                if(RemoveSymbolFromPortfolio(symbolToRemove) && AddSymbolToPortfolio(bestReplacement))
                {
                    LogOptimizationEvent(ERROR_LEVEL_INFO, 
                                       StringFormat("Diversification optimization: %s -> %s (correlation reduced from %.3f)", 
                                                   symbolToRemove, bestReplacement, maxCorrelation));
                    return true;
                }
            }
        }
    }
    
    LogOptimizationEvent(ERROR_LEVEL_INFO, "Portfolio diversification is optimal");
    return false;
}

//+------------------------------------------------------------------+
//| Get Best Symbol for Diversification                            |
//+------------------------------------------------------------------+
string CSymbolDiversificationOptimizer::GetBestDiversificationSymbol(void)
{
    string bestSymbol = "";
    double bestScore = -1.0;
    
    for(int i = 0; i < m_availableSymbolCount; i++)
    {
        string symbol = m_availableSymbols[i];
        
        // Skip if already active or blacklisted
        if(IsSymbolActive(symbol) || IsSymbolBlacklisted(symbol))
            continue;
        
        // Calculate combined score (performance + diversification)
        SSymbolPerformance perf = GetSymbolPerformance(symbol);
        double diversificationValue = CalculateDiversificationValue(symbol);
        
        // Weighted score: 60% performance, 40% diversification
        double combinedScore = (perf.performanceScore * 0.6) + (diversificationValue * 0.4);
        
        if(combinedScore > bestScore)
        {
            bestScore = combinedScore;
            bestSymbol = symbol;
        }
    }
    
    return bestSymbol;
}

//+------------------------------------------------------------------+
//| Calculate Symbol Correlation (Enhanced)                        |
//+------------------------------------------------------------------+
double CSymbolDiversificationOptimizer::CalculateSymbolCorrelation(const string symbol1, const string symbol2)
{
    if(symbol1 == symbol2)
        return 1.0;
    
    // Handle Deriv synthetic indices
    if(IsDerivSynthetic(symbol1) && IsDerivSynthetic(symbol2))
    {
        return CalculateDerivCorrelation(symbol1, symbol2);
    }
    
    // Handle mixed Deriv and Forex
    if(IsDerivSynthetic(symbol1) || IsDerivSynthetic(symbol2))
    {
        return 0.1; // Low correlation between synthetics and forex
    }
    
    // Enhanced Forex correlation calculation
    return CalculateForexCorrelation(symbol1, symbol2);
}
//+------------------------------------------------------------------+
//| Calculate Deriv Correlation                                    |
//+------------------------------------------------------------------+
double CSymbolDiversificationOptimizer::CalculateDerivCorrelation(const string symbol1, const string symbol2)
{
    // Simple correlation calculation for Deriv synthetic indices
    // Based on common underlying assets and volatility patterns
    if(symbol1 == symbol2)
        return 1.0;
    
    // Extract base asset names (remove "R_" prefix)
    string base1 = StringSubstr(symbol1, 2);
    string base2 = StringSubstr(symbol2, 2);
    
    // High correlation if same base asset
    if(base1 == base2)
        return 0.8;
    
    // Medium correlation for similar volatility indices
    if((StringFind(symbol1, "BOOM") != -1 && StringFind(symbol2, "CRASH") != -1) ||
       (StringFind(symbol1, "CRASH") != -1 && StringFind(symbol2, "BOOM") != -1))
        return -0.7; // Negative correlation between boom and crash
    
    // Low correlation for unrelated synthetic indices
    return 0.1;
}

//+------------------------------------------------------------------+
//| Calculate Forex Correlation                                     |
//+------------------------------------------------------------------+
double CSymbolDiversificationOptimizer::CalculateForexCorrelation(const string symbol1, const string symbol2)
{
    if(symbol1 == symbol2)
        return 1.0;
    
    // Extract currency pairs
    string curr1_1 = StringSubstr(symbol1, 0, 3);
    string curr1_2 = StringSubstr(symbol1, 3, 3);
    string curr2_1 = StringSubstr(symbol2, 0, 3);
    string curr2_2 = StringSubstr(symbol2, 3, 3);
    
    // High correlation for same base currency
    if(curr1_1 == curr2_1)
        return 0.8;
    
    // High correlation for same quote currency  
    if(curr1_2 == curr2_2)
        return 0.7;
    
    // Cross correlation (e.g., EUR/USD and GBP/USD)
    if(curr1_2 == curr2_2 && curr1_1 != curr2_1)
        return 0.6;
    
    // Negative correlation for inverse pairs
    if((curr1_1 == curr2_2 && curr1_2 == curr2_1))
        return -0.9;
    
    // Default low correlation
    return 0.1;
}

//+------------------------------------------------------------------+
//| Hybrid Symbol Selection Approach                               |
//+------------------------------------------------------------------+
bool CSymbolDiversificationOptimizer::SelectHybridApproach(string &symbols[], int &count)
{
    // Step 1: Get performance-ranked symbols
    string performanceRanked[];
    double performanceScores[];
    RankSymbolsByPerformance(performanceRanked, performanceScores);
    
    // Step 2: Get diversification-ranked symbols
    string diversificationRanked[];
    double diversificationScores[];
    RankSymbolsByDiversification(diversificationRanked, diversificationScores);
    
    // Step 3: Combine using weighted scoring
    struct SSymbolScore
    {
        string symbol;
        double combinedScore;
        double performanceScore;
        double diversificationScore;
    };
    
    SSymbolScore candidateScores[];
    ArrayResize(candidateScores, m_availableSymbolCount);
    
    for(int i = 0; i < m_availableSymbolCount; i++)
    {
        string symbol = m_availableSymbols[i];
        
        // Skip blacklisted symbols
        if(IsSymbolBlacklisted(symbol))
            continue;
        
        SSymbolPerformance perf = GetSymbolPerformance(symbol);
        double diversificationValue = CalculateDiversificationValue(symbol);
        
        candidateScores[i].symbol = symbol;
        candidateScores[i].performanceScore = perf.performanceScore;
        candidateScores[i].diversificationScore = diversificationValue;
        
        // Weighted combination: 70% performance, 30% diversification
        candidateScores[i].combinedScore = (perf.performanceScore * 0.7) + (diversificationValue * 0.3);
    }
    
    // Sort by combined score
    for(int i = 0; i < m_availableSymbolCount - 1; i++)
    {
        for(int j = i + 1; j < m_availableSymbolCount; j++)
        {
            if(candidateScores[j].combinedScore > candidateScores[i].combinedScore)
            {
                SSymbolScore temp = candidateScores[i];
                candidateScores[i] = candidateScores[j];
                candidateScores[j] = temp;
            }
        }
    }
    
    // Select top symbols with correlation checking
    ArrayResize(symbols, 0);
    count = 0;
    
    for(int i = 0; i < m_availableSymbolCount && count < m_maxActiveSymbols; i++)
    {
        string candidate = candidateScores[i].symbol;
        
        if(candidate == "" || IsSymbolBlacklisted(candidate))
            continue;
        
        // Check correlation with already selected symbols
        bool correlationOk = true;
        for(int j = 0; j < count; j++)
        {
            double correlation = MathAbs(CalculateSymbolCorrelation(candidate, symbols[j]));
            if(correlation > m_correlationThreshold)
            {
                correlationOk = false;
                break;
            }
        }
        
        if(correlationOk)
        {
            ArrayResize(symbols, count + 1);
            symbols[count] = candidate;
            count++;
            
            LogOptimizationEvent(ERROR_LEVEL_DEBUG, 
                               StringFormat("Selected symbol: %s (Score: %.1f, Perf: %.1f, Div: %.1f)", 
                                           candidate, candidateScores[i].combinedScore,
                                           candidateScores[i].performanceScore, 
                                           candidateScores[i].diversificationScore));
        }
    }
    
    return count > 0;
}

//+------------------------------------------------------------------+
//| Enhanced Intelligent Symbol Selection                          |
//+------------------------------------------------------------------+
bool CSymbolDiversificationOptimizer::IntelligentSymbolSelection(string &selectedSymbols[], int &count)
{
    if(!m_initialized)
    {
        LogOptimizationEvent(ERROR_LEVEL_ERROR, "Optimizer not initialized");
        return false;
    }
    
    LogOpt