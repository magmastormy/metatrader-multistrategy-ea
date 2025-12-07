//+------------------------------------------------------------------+
//| Portfolio Risk Management System                               |
//| Manages overall portfolio risk and exposure limits             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_PORTFOLIO_RISK_MANAGER_MQH
#define CORE_PORTFOLIO_RISK_MANAGER_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "PositionSizer.mqh"

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
//| Portfolio Risk Manager Class                                  |
//+------------------------------------------------------------------+
class CPortfolioRiskManager : public CEnhancedErrorHandler
{
private:
    CPositionSizer* m_positionSizer;     // Position sizer reference
    
    // Risk limits
    double m_maxPortfolioRisk;           // Maximum portfolio risk %
    double m_maxLeverage;                // Maximum leverage allowed
    double m_maxCorrelation;             // Maximum correlation threshold
    int m_maxPositions;                  // Maximum number of positions
    
    // Current risk metrics
    SRiskMetrics m_currentRisk;          // Current risk state
    double m_portfolioValue;             // Current portfolio value
    double m_totalExposure;              // Total position exposure
    
    // Position tracking
    SPositionInfo m_positions[MAX_POSITIONS]; // Position array
    int m_positionCount;                 // Current position count
    int m_instanceId;                    // Instance ID for tracking
    static int m_instanceCount;          // Static instance counter
    bool m_portfolioEmergencyMode;       // Portfolio emergency mode flag (per instance)
    
    // Risk monitoring
    bool m_conservativeMode;             // Conservative mode flag
    bool m_tradingPaused;                // Trading pause flag
    datetime m_lastRiskUpdate;           // Last risk calculation time
    double m_riskHistory[24];            // Hourly risk history
    datetime m_conservativeModeStart;    // When conservative mode started
    datetime m_tradingPauseStart;        // When trading pause started
    datetime m_tradingPauseEnd;          // When trading pause ends
    double m_originalMaxRisk;            // Original max risk before reduction
    string m_pauseReason;                // Reason for trading pause
    
    bool m_initialized;
    
public:
    // Constructor
    CPortfolioRiskManager(void);
    
    // Destructor
    ~CPortfolioRiskManager(void);
    
    // Initialize with dependencies
    bool Initialize(CPositionSizer* positionSizer, 
                   const double maxRisk = MAX_TOTAL_RISK / 100.0,
                   const double maxLeverage = 10.0);
    
    // Risk assessment
    bool IsTradeAllowed(const string symbolParam, const double volume);
    bool CheckRiskLimits(const string symbolParam, const double volume, const double stopLossPips);
    bool CheckCorrelationLimits(const string symbolParam);
    bool CheckLeverageLimits(const double additionalExposure);
    
    // Portfolio management
    void UpdateOpenPositions(void);
    void CalculatePortfolioRisk(void);
    void UpdateRiskMetrics(void);
    
    // Risk monitoring
    bool IsEmergencyMode(void) const { return m_portfolioEmergencyMode; }
    void SetEmergencyMode(const bool emergency) { m_portfolioEmergencyMode = emergency; }
    void CheckEmergencyTriggers(void);
    ENUM_RISK_LEVEL GetRiskLevel(void);
    
    // ENHANCED: Portfolio risk enforcement
    bool ValidatePortfolioRiskWithNewTrade(const string symbol, const double volume);
    bool EnforcePortfolioRiskLimits(void);
    void MonitorPortfolioRiskRealTime(void);
    void GenerateRiskAlert(const string alertType, const string message);
    void CloseRiskiestPositions(void);
    
    // ENHANCED: Correlation monitoring
    void PrintCorrelationMatrix(void);
    string GetCorrelationReport(void);
    void MonitorCorrelationChanges(void);
    
    // ENHANCED: Drawdown-based risk adaptation
    void MonitorDrawdownLevels(void);
    void ActivateConservativeMode(const string reason);
    void DeactivateConservativeMode(void);
    bool IsConservativeMode(void) const { return m_conservativeMode; }
    double GetRiskAdjustmentFactor(void);
    void AdjustRiskParameters(const double drawdownPercent);
    
    // ENHANCED: News and volatility-based trading pauses
    bool IsVolatilitySpike(const string symbolParam);
    void ActivateTradingPause(const string reason, const int durationMinutes);
    void DeactivateTradingPause(void);
    bool IsTradingPaused(void) const { return m_tradingPaused; }
    void MonitorVolatilityLevels(void);
    void AdjustStopLossForVolatility(const string symbolParam, double &stopLoss);
    double CalculateVolatilityAdjustment(const string symbolParam);
    
    // Get risk information
    SRiskMetrics GetCurrentRisk(void) const { return m_currentRisk; }
    double GetPortfolioRisk(void) const { return m_currentRisk.totalRisk; }
    double GetCurrentDrawdown(void) const { return m_currentRisk.drawdown; }
    double GetMarginLevel(void) const { return m_currentRisk.marginLevel; }
    
    // Risk limits management
    void SetMaxPortfolioRisk(const double maxRisk) { m_maxPortfolioRisk = maxRisk; }
    void SetMaxLeverage(const double maxLeverage) { m_maxLeverage = maxLeverage; }
    void SetMaxPositions(const int maxPositions) { m_maxPositions = maxPositions; }
    
    // Reporting
    void PrintRiskReport(void);
    string GetRiskSummary(void);
    
private:
    // Internal calculations
    double CalculateSymbolCorrelation(const string symbol1Param, const string symbol2Param);
    double CalculatePortfolioCorrelation(const string newSymbolParam);
    double CalculatePositionExposure(const SPositionInfo &position);
    double CalculateVaR(const double confidence = 0.95); // Value at Risk
    
    // ENHANCED: Correlation calculation helpers
    bool IsDerivSynthetic(const string symbolParam);
    double CalculateDerivCorrelation(const string symbol1Param, const string symbol2Param);
    double CalculateForexCorrelation(const string symbol1Param, const string symbol2Param);
    
    // Risk validation
    bool ValidateRiskParameters(void);
    void UpdateRiskHistory(void);
    
    // Position management
    void AddPosition(const SPositionInfo &position);
    void RemovePosition(const ulong ticket);
    void UpdatePosition(const SPositionInfo &position);
    int FindPositionIndex(const ulong ticket);
    
    // Emergency procedures
    void TriggerEmergencyStop(const string reason);
    void ReduceRiskExposure(void);
    
    // Logging
    void LogRiskEvent(const ENUM_ERROR_LEVEL level, const string message);
};

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
// Static member initialization
int CPortfolioRiskManager::m_instanceCount = 0;

CPortfolioRiskManager::CPortfolioRiskManager(void)
{
    m_positionSizer = NULL;
    m_maxPortfolioRisk = (MAX_TOTAL_RISK / 100.0);
    m_maxLeverage = 10.0;
    m_maxCorrelation = MAX_CORRELATION;
    m_maxPositions = MAX_POSITIONS;
    m_portfolioValue = 0.0;
    m_totalExposure = 0.0;
    m_instanceId = (++m_instanceCount);
    m_positionCount = 0;
    m_conservativeMode = false;
    m_tradingPaused = false;
    m_portfolioEmergencyMode = false;
    m_lastRiskUpdate = 0;
    m_conservativeModeStart = 0;
    m_tradingPauseStart = 0;
    m_tradingPauseEnd = 0;
    m_originalMaxRisk = (MAX_TOTAL_RISK / 100.0);
    m_pauseReason = "";
    m_initialized = false;
    // Initialize risk metrics
    ZeroMemory(m_currentRisk);
    m_currentRisk.totalRisk = 0.0;
    m_currentRisk.freeMargin = 0.0;
    m_currentRisk.marginLevel = 0.0;
    m_currentRisk.drawdown = 0.0;
    m_currentRisk.maxDrawdown = 0.0;
    m_currentRisk.totalPositions = 0;
    m_currentRisk.correlation = 0.0;
    m_currentRisk.emergencyStop = false;
    
    // Initialize arrays
    ArrayInitialize(m_riskHistory, 0.0);
    for(int i = 0; i < MAX_POSITIONS; i++)
    {
        m_positions[i].ticket = 0;
        m_positions[i].symbol = "";
        m_positions[i].volume = 0.0;
        m_positions[i].profit = 0.0;
    }
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CPortfolioRiskManager::~CPortfolioRiskManager(void)
{
    if(m_initialized)
    {
        PrintRiskReport();
        LogRiskEvent(ERROR_LEVEL_INFO, "Portfolio risk manager destroyed");
    }
}

//+------------------------------------------------------------------+
//| Initialize with dependencies                                   |
//+------------------------------------------------------------------+
bool CPortfolioRiskManager::Initialize(CPositionSizer* pPositionSizer, 
                                      const double maxRisk = MAX_TOTAL_RISK / 100.0,
                                      const double maxLeverage = 10.0)
{
    if(CheckPointer(pPositionSizer) == POINTER_INVALID)
    {
        LogRiskEvent(ERROR_LEVEL_ERROR, "Invalid position sizer pointer");
        return false;
    }
    
    m_positionSizer = pPositionSizer;
    m_maxPortfolioRisk = maxRisk;
    m_maxLeverage = maxLeverage;
    
    // Validate parameters
    if(!ValidateRiskParameters())
    {
        LogRiskEvent(ERROR_LEVEL_ERROR, "Invalid risk parameters");
        return false;
    }
    
    // Initialize portfolio value
    m_portfolioValue = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // Update initial risk metrics
    UpdateOpenPositions();
    CalculatePortfolioRisk();
    
    m_initialized = true;
    m_lastRiskUpdate = TimeCurrent();
    
    LogRiskEvent(ERROR_LEVEL_INFO, 
                StringFormat("Portfolio risk manager initialized - Max Risk: %.1f%%, Max Leverage: %.1fx", 
                            m_maxPortfolioRisk * 100.0, m_maxLeverage));
    
    return true;
}

//+------------------------------------------------------------------+
//| Enhanced Trade Validation - Mandatory Risk Enforcement         |
//+------------------------------------------------------------------+
bool CPortfolioRiskManager::IsTradeAllowed(const string symbolParam, const double volume)
{
    if(!m_initialized)
    {
        LogRiskEvent(ERROR_LEVEL_ERROR, "Risk manager not initialized");
        return false;
    }
    
    // Emergency mode check
    if(m_portfolioEmergencyMode)
    {
        LogRiskEvent(ERROR_LEVEL_WARNING, "Trade blocked - Emergency mode active");
        return false;
    }
    
    // ENHANCED: Trading pause check
    if(m_tradingPaused)
    {
        datetime currentTimeParam = TimeCurrent();
        if(currentTimeParam < m_tradingPauseEnd)
        {
            LogRiskEvent(ERROR_LEVEL_WARNING, 
                        StringFormat("Trade blocked - Trading paused: %s (ends in %d minutes)",
                                    m_pauseReason, (int)((m_tradingPauseEnd - currentTimeParam) / 60)));
            return false;
        }
        else
        {
            // Pause expired, deactivate
            DeactivateTradingPause();
        }
    }
    
    // MANDATORY: Update current risk state before every trade
    UpdateRiskMetrics();
    
    // ENHANCED: Check portfolio risk limit BEFORE allowing trade
    // m_currentRisk.totalRisk is already percentage (0-100)
    // m_maxPortfolioRisk is decimal (0.10 = 10%), so multiply by 100 for comparison
    double maxRiskPercentage = m_maxPortfolioRisk * 100.0;
    if(m_currentRisk.totalRisk > maxRiskPercentage)
    {
        LogRiskEvent(ERROR_LEVEL_WARNING, 
                    StringFormat("Portfolio risk limit exceeded: %.2f%% > %.2f%%", 
                                m_currentRisk.totalRisk, maxRiskPercentage));
        return false;
    }
    
    // Check position limits
    if(m_positionCount >= m_maxPositions)
    {
        LogRiskEvent(ERROR_LEVEL_WARNING, 
                    StringFormat("Maximum positions reached: %d/%d", m_positionCount, m_maxPositions));
        return false;
    }
    
    // ENHANCED: Strict correlation checking
    if(!CheckCorrelationLimits(symbolParam))
    {
        LogRiskEvent(ERROR_LEVEL_WARNING, "Trade blocked - Correlation limit exceeded");
        return false;
    }
    
    // Calculate additional exposure
    double currentPriceParam = SymbolInfoDouble(symbolParam, SYMBOL_BID);
    if(currentPriceParam <= 0)
    {
        LogRiskEvent(ERROR_LEVEL_ERROR, "Invalid price data for " + symbolParam);
        return false;
    }
    
    double additionalExposure = volume * currentPriceParam;
    
    // Check leverage limits
    if(!CheckLeverageLimits(additionalExposure))
    {
        LogRiskEvent(ERROR_LEVEL_WARNING, "Trade blocked - Leverage limit exceeded");
        return false;
    }
    
    // ENHANCED: Final portfolio risk validation with proposed trade
    if(!ValidatePortfolioRiskWithNewTrade(symbolParam, volume))
    {
        LogRiskEvent(ERROR_LEVEL_WARNING, "Trade would exceed portfolio risk limits");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Risk Limits                                              |
//+------------------------------------------------------------------+
bool CPortfolioRiskManager::CheckRiskLimits(const string symbolParam, const double volume, const double stopLossPips)
{
    if(!m_initialized) return false;
    
    // Calculate position risk
    double tickValue = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_VALUE);
    double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
    
    if(tickValue <= 0 || point <= 0)
        return false;
    
    double positionRisk = volume * stopLossPips * (tickValue / point);
    double riskPercent = (positionRisk / m_portfolioValue) * 100.0;
    
    // Check if adding this risk exceeds portfolio limit
    if(m_currentRisk.totalRisk + riskPercent > m_maxPortfolioRisk * 100.0)
    {
        LogRiskEvent(ERROR_LEVEL_WARNING, 
                    StringFormat("Portfolio risk limit exceeded: %.2f%% + %.2f%% > %.2f%%", 
                                m_currentRisk.totalRisk, riskPercent, m_maxPortfolioRisk * 100.0));
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| ENHANCED: Check Correlation Limits with Detailed Logging       |
//+------------------------------------------------------------------+
bool CPortfolioRiskManager::CheckCorrelationLimits(const string symbolParam)
{
    if(!m_initialized) return true;
    
    // Calculate correlation with existing positions
    double maxCorrelation = CalculatePortfolioCorrelation(symbolParam);
    string correlatedSymbol = "";
    
    // Find the most correlated symbol for logging
    for(int i = 0; i < m_positionCount; i++)
    {
        double correlation = MathAbs(CalculateSymbolCorrelation(symbolParam, m_positions[i].symbol));
        if(correlation == maxCorrelation)
        {
            correlatedSymbol = m_positions[i].symbol;
            break;
        }
    }
    
    // Enhanced correlation threshold (0.6 as per requirements)
    double correlationLimit = 0.6;
    
    if(maxCorrelation > correlationLimit)
    {
        LogRiskEvent(ERROR_LEVEL_WARNING,
                    StringFormat("CORRELATION BLOCK: %s blocked due to %.2f correlation with %s (limit: %.2f)",
                                symbolParam, maxCorrelation, correlatedSymbol, correlationLimit));
        
        // Generate correlation alert
        GenerateRiskAlert("CORRELATION_LIMIT_EXCEEDED",
                         StringFormat("%s blocked: %.2f correlation with %s",
                                     symbolParam, maxCorrelation, correlatedSymbol));
        return false;
    }
    
    // Log correlation info for approved trades
    if(maxCorrelation > 0.3) // Log if correlation is significant
    {
        LogRiskEvent(ERROR_LEVEL_INFO,
                    StringFormat("CORRELATION OK: %s approved with %.2f correlation to %s",
                                symbolParam, maxCorrelation, correlatedSymbol));
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Leverage Limits                                          |
//+------------------------------------------------------------------+
bool CPortfolioRiskManager::CheckLeverageLimits(const double additionalExposure)
{
    if(!m_initialized) return true;
    
    double totalExposure = m_totalExposure + additionalExposure;
    double currentLeverage = totalExposure / m_portfolioValue;
    
    if(currentLeverage > m_maxLeverage)
    {
        LogRiskEvent(ERROR_LEVEL_WARNING, 
                    StringFormat("Leverage limit exceeded: %.2fx > %.2fx", currentLeverage, m_maxLeverage));
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Update Open Positions                                          |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::UpdateOpenPositions(void)
{
    if(!m_initialized) return;
    
    // Clear current positions
    m_positionCount = 0;
    m_totalExposure = 0.0;
    
    // Scan all open positions
    int totalPositions = PositionsTotal();
    
    for(int i = 0; i < totalPositions && m_positionCount < MAX_POSITIONS; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelectByTicket(ticket))
        {
            SPositionInfo pos;
            pos.ticket = ticket;
            pos.symbol = PositionGetString(POSITION_SYMBOL);
            pos.type = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
            pos.volume = PositionGetDouble(POSITION_VOLUME);
            pos.openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            pos.currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            pos.stopLoss = PositionGetDouble(POSITION_SL);
            pos.takeProfit = PositionGetDouble(POSITION_TP);
            pos.profit = PositionGetDouble(POSITION_PROFIT);
            pos.openTime = (datetime)PositionGetInteger(POSITION_TIME);
            pos.state = TRADE_STATE_ACTIVE;
            pos.comment = PositionGetString(POSITION_COMMENT);
            
            // Add to position array
            m_positions[m_positionCount] = pos;
            m_positionCount++;
            
            // Update total exposure
            m_totalExposure += CalculatePositionExposure(pos);
        }
    }
    
    m_currentRisk.totalPositions = m_positionCount;
}

//+------------------------------------------------------------------+
//| Calculate Portfolio Risk                                       |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::CalculatePortfolioRisk(void)
{
    if(!m_initialized) return;
    
    double totalRisk = 0.0;
    double totalProfitParam = 0.0;
    
    // Calculate risk from each position
    for(int i = 0; i < m_positionCount; i++)
    {
        SPositionInfo pos = m_positions[i];
        
        if(pos.stopLoss > 0)
        {
            double positionRisk = MathAbs(pos.openPrice - pos.stopLoss) * pos.volume;
            double tickValue = SymbolInfoDouble(pos.symbol, SYMBOL_TRADE_TICK_VALUE);
            double point = SymbolInfoDouble(pos.symbol, SYMBOL_POINT);
            
            if(tickValue > 0 && point > 0)
            {
                positionRisk *= (tickValue / point);
                totalRisk += positionRisk;
            }
        }
        
        totalProfitParam += pos.profit;
    }
    
    // Convert to percentage
    if(m_portfolioValue > 0)
    {
        m_currentRisk.totalRisk = (totalRisk / m_portfolioValue) * 100.0;
    }
    
    // Update other risk metrics
    // Update other risk metrics
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    m_currentRisk.freeMargin = freeMargin;
    
    // Use standard Margin Level from MT5
    m_currentRisk.marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
    
    // Handle case where used margin is 0 (infinite margin level)
    if(m_currentRisk.marginLevel == 0 && AccountInfoDouble(ACCOUNT_MARGIN) == 0)
    {
        m_currentRisk.marginLevel = 999999.0; // Infinite
    }
    
    // Calculate drawdown
    double currentEquityParam = AccountInfoDouble(ACCOUNT_EQUITY);
    double accountBalanceParam = AccountInfoDouble(ACCOUNT_BALANCE);
    
    if(accountBalanceParam > 0)
    {
        m_currentRisk.drawdown = ((accountBalanceParam - currentEquityParam) / accountBalanceParam) * 100.0;
        if(m_currentRisk.drawdown > m_currentRisk.maxDrawdown)
            m_currentRisk.maxDrawdown = m_currentRisk.drawdown;
    }
}

//+------------------------------------------------------------------+
//| Update Risk Metrics                                           |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::UpdateRiskMetrics(void)
{
    if(!m_initialized) return;
    
    // Update portfolio value
    m_portfolioValue = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // Update positions
    UpdateOpenPositions();
    
    // Recalculate risk
    CalculatePortfolioRisk();
    
    // Update risk history
    UpdateRiskHistory();
    
    // Check emergency triggers
    CheckEmergencyTriggers();
    
    m_lastRiskUpdate = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Check Emergency Triggers                                       |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::CheckEmergencyTriggers(void)
{
    if(!m_initialized) return;
    
    bool triggerEmergency = false;
    string reason = "";
    
    // Check drawdown limit
    if(m_currentRisk.drawdown > EMERGENCY_DRAWDOWN)
    {
        triggerEmergency = true;
        reason = StringFormat("Emergency drawdown exceeded: %.2f%%", m_currentRisk.drawdown);
    }
    
    // Check margin level
    if(m_currentRisk.marginLevel < 100.0 && m_currentRisk.marginLevel > 0)
    {
        triggerEmergency = true;
        reason = StringFormat("Critical margin level: %.2f%%", m_currentRisk.marginLevel);
    }
    
    // Check portfolio risk
    if(m_currentRisk.totalRisk > m_maxPortfolioRisk * 150.0) // 150% of limit
    {
        triggerEmergency = true;
        reason = StringFormat("Extreme portfolio risk: %.2f%%", m_currentRisk.totalRisk);
    }
    
    if(triggerEmergency && !m_portfolioEmergencyMode)
    {
        TriggerEmergencyStop(reason);
    }
    // Clear emergency mode when conditions normalize
    else if(!triggerEmergency && m_portfolioEmergencyMode)
    {
        m_portfolioEmergencyMode = false;
        m_currentRisk.emergencyStop = false;
        LogRiskEvent(ERROR_LEVEL_INFO, "Emergency mode deactivated - conditions normalized");
        Print("�?EMERGENCY MODE DEACTIVATED - Trading resumed");
    }
}

//+------------------------------------------------------------------+
//| Print Risk Report                                              |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::PrintRiskReport(void)
{
    if(!m_initialized) return;
    
    UpdateRiskMetrics();
    
    Print("\n=== PORTFOLIO RISK REPORT ===");
    Print("🛡�?RISK METRICS:");
    Print("   Portfolio Risk: ", DoubleToString(m_currentRisk.totalRisk, 2), "%");
    Print("   Max Risk Limit: ", DoubleToString(m_maxPortfolioRisk * 100.0, 2), "%");
    Print("   Current Drawdown: ", DoubleToString(m_currentRisk.drawdown, 2), "%");
    Print("   Maximum Drawdown: ", DoubleToString(m_currentRisk.maxDrawdown, 2), "%");
    
    Print("\n💰 MARGIN & LEVERAGE:");
    Print("   Free Margin: $", DoubleToString(m_currentRisk.freeMargin, 2));
    Print("   Margin Level: ", DoubleToString(m_currentRisk.marginLevel, 2), "%");
    Print("   Total Exposure: $", DoubleToString(m_totalExposure, 2));
    Print("   Current Leverage: ", DoubleToString(m_totalExposure / m_portfolioValue, 2), "x");
    Print("   Max Leverage: ", DoubleToString(m_maxLeverage, 2), "x");
    
    Print("\n📊 POSITION SUMMARY:");
    Print("   Total Positions: ", m_currentRisk.totalPositions);
    Print("   Max Positions: ", m_maxPositions);
    Print("   Portfolio Value: $", DoubleToString(m_portfolioValue, 2));
    
    Print("\n⚠️ STATUS:");
    Print("   Emergency Mode: ", m_portfolioEmergencyMode ? "ACTIVE" : "NORMAL");
    Print("   Risk Level: ", EnumToString(GetRiskLevel()));
    Print("   Last Update: ", TimeToString(m_lastRiskUpdate));
    
    Print("=============================\n");
}

//+------------------------------------------------------------------+
//| Get Risk Summary                                               |
//+------------------------------------------------------------------+
string CPortfolioRiskManager::GetRiskSummary(void)
{
    if(!m_initialized)
        return "Risk manager not initialized";
    
    string mode = "NORMAL";
    if(m_portfolioEmergencyMode) mode = "EMERGENCY";
    else if(m_tradingPaused) mode = "PAUSED";
    else if(m_conservativeMode) mode = "CONSERVATIVE";
    
    return StringFormat("Risk: %.1f%% | DD: %.1f%% | Positions: %d | Leverage: %.1fx | %s",
                       m_currentRisk.totalRisk, m_currentRisk.drawdown, 
                       m_currentRisk.totalPositions, m_totalExposure / m_portfolioValue,
                       mode);
}

//+------------------------------------------------------------------+
//| ENHANCED: Calculate Symbol Correlation with Deriv Support      |
//+------------------------------------------------------------------+
double CPortfolioRiskManager::CalculateSymbolCorrelation(const string symbol1Param, const string symbol2Param)
{
    if(symbol1Param == symbol2Param)
        return 1.0;
    
    // Handle Deriv synthetic indices
    if(IsDerivSynthetic(symbol1Param) && IsDerivSynthetic(symbol2Param))
    {
        return CalculateDerivCorrelation(symbol1Param, symbol2Param);
    }
    
    // Handle mixed Deriv and Forex
    if(IsDerivSynthetic(symbol1Param) || IsDerivSynthetic(symbol2Param))
    {
        return 0.1; // Low correlation between synthetics and forex
    }
    
    // Enhanced Forex correlation calculation
    return CalculateForexCorrelation(symbol1Param, symbol2Param);
}

//+------------------------------------------------------------------+
//| ENHANCED: Check if Symbol is Deriv Synthetic                   |
//+------------------------------------------------------------------+
bool CPortfolioRiskManager::IsDerivSynthetic(const string symbolParam)
{
    // Check for Deriv synthetic patterns
    if(StringFind(symbolParam, "Volatility") >= 0) return true;
    if(StringFind(symbolParam, "Boom") >= 0) return true;
    if(StringFind(symbolParam, "Crash") >= 0) return true;
    if(StringFind(symbolParam, "Step") >= 0) return true;
    if(StringFind(symbolParam, "Jump") >= 0) return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| ENHANCED: Calculate Deriv Synthetic Correlation                |
//+------------------------------------------------------------------+
double CPortfolioRiskManager::CalculateDerivCorrelation(const string symbol1Param, const string symbol2Param)
{
    double correlation = 0.0;
    
    // Same volatility indices have high correlation
    if(StringFind(symbol1Param, "Volatility") >= 0 && StringFind(symbol2Param, "Volatility") >= 0)
    {
        correlation = 0.8; // High correlation between volatility indices
    }
    // Boom indices correlation
    else if(StringFind(symbol1Param, "Boom") >= 0 && StringFind(symbol2Param, "Boom") >= 0)
    {
        correlation = 0.7; // High correlation between boom indices
    }
    // Crash indices correlation
    else if(StringFind(symbol1Param, "Crash") >= 0 && StringFind(symbol2Param, "Crash") >= 0)
    {
        correlation = 0.7; // High correlation between crash indices
    }
    // Step indices correlation
    else if(StringFind(symbol1Param, "Step") >= 0 && StringFind(symbol2Param, "Step") >= 0)
    {
        correlation = 0.6; // Moderate correlation between step indices
    }
    // Jump indices correlation
    else if(StringFind(symbol1Param, "Jump") >= 0 && StringFind(symbol2Param, "Jump") >= 0)
    {
        correlation = 0.6; // Moderate correlation between jump indices
    }
    // Boom vs Crash (inverse correlation)
    else if((StringFind(symbol1Param, "Boom") >= 0 && StringFind(symbol2Param, "Crash") >= 0) ||
            (StringFind(symbol1Param, "Crash") >= 0 && StringFind(symbol2Param, "Boom") >= 0))
    {
        correlation = 0.5; // Moderate correlation (both are spike indices)
    }
    // Different synthetic types
    else
    {
        correlation = 0.3; // Low to moderate correlation
    }
    
    return correlation;
}

//+------------------------------------------------------------------+
//| ENHANCED: Calculate Forex Correlation                          |
//+------------------------------------------------------------------+
double CPortfolioRiskManager::CalculateForexCorrelation(const string symbol1Param, const string symbol2Param)
{
    // Extract currency codes (assuming 6-character symbols like EURUSD)
    if(StringLen(symbol1Param) < 6 || StringLen(symbol2Param) < 6)
        return 0.1; // Low correlation for non-standard symbols
    
    string base1 = StringSubstr(symbol1Param, 0, 3);
    string quote1 = StringSubstr(symbol1Param, 3, 3);
    string base2 = StringSubstr(symbol2Param, 0, 3);
    string quote2 = StringSubstr(symbol2Param, 3, 3);
    
    double correlation = 0.0;
    
    // Same base currency (e.g., EURUSD vs EURJPY)
    if(base1 == base2)
        correlation += 0.6;
    
    // Same quote currency (e.g., EURUSD vs GBPUSD)
    if(quote1 == quote2)
        correlation += 0.5;
    
    // Inverse pairs (e.g., EURUSD vs USDEUR - though USDEUR doesn't exist)
    if(base1 == quote2 && quote1 == base2)
        correlation = 0.9; // Very high inverse correlation
    
    // Cross correlations (one currency appears in both pairs)
    else if(base1 == quote2 || quote1 == base2)
        correlation += 0.4;
    
    // Specific major currency correlations
    if((base1 == "EUR" && base2 == "GBP") || (base1 == "GBP" && base2 == "EUR"))
        correlation += 0.3; // EUR and GBP tend to correlate
    
    if((base1 == "AUD" && base2 == "NZD") || (base1 == "NZD" && base2 == "AUD"))
        correlation += 0.4; // AUD and NZD are highly correlated
    
    if((base1 == "USD" && quote2 == "USD") || (quote1 == "USD" && base2 == "USD"))
    {
        // USD pairs can have inverse correlation
        correlation = MathMax(correlation, 0.3);
    }
    
    return MathMax(0.0, MathMin(1.0, correlation));
}

//+------------------------------------------------------------------+
//| Calculate Portfolio Correlation                                |
//+------------------------------------------------------------------+
double CPortfolioRiskManager::CalculatePortfolioCorrelation(const string newSymbol)
{
    double maxCorrelation = 0.0;
    
    for(int i = 0; i < m_positionCount; i++)
    {
        // Skip self-correlation check - adding to existing position is valid
        if(m_positions[i].symbol == newSymbol)
            continue;
        double correlation = MathAbs(CalculateSymbolCorrelation(newSymbol, m_positions[i].symbol));
        if(correlation > maxCorrelation)
            maxCorrelation = correlation;
    }
    
    return maxCorrelation;
}

//+------------------------------------------------------------------+
//| Calculate Position Exposure                                    |
//+------------------------------------------------------------------+
double CPortfolioRiskManager::CalculatePositionExposure(const SPositionInfo &position)
{
    return position.volume * position.currentPrice;
}

//+------------------------------------------------------------------+
//| Calculate Value at Risk - Historical Simulation Implementation   |
//+------------------------------------------------------------------+
double CPortfolioRiskManager::CalculateVaR(const double confidence = 0.95)
{
    // Production-ready historical simulation VaR calculation
    const int HISTORICAL_DAYS = 252; // 1 year of trading days
    const int MIN_HISTORY = 30;      // Minimum required history
    
    double historicalReturns[];
    ArrayResize(historicalReturns, HISTORICAL_DAYS);
    ArrayInitialize(historicalReturns, 0.0);
    
    int validReturns = 0;
    datetime currentTimeParam = TimeCurrent();
    
    // Collect historical returns for all positions
    for(int i = 0; i < m_positionCount && validReturns < HISTORICAL_DAYS; i++)
    {
        string currentSymbol = m_positions[i].symbol;
        
        // Get historical price data
        double prices[];
        int copied = CopyClose(currentSymbol, PERIOD_D1, 1, HISTORICAL_DAYS + 1, prices);
        
        if(copied >= MIN_HISTORY + 1)
        {
            // Calculate daily returns
            for(int j = 0; j < copied - 1 && validReturns < HISTORICAL_DAYS; j++)
            {
                if(prices[j] > 0 && prices[j + 1] > 0)
                {
                    double dailyReturn = (prices[j] - prices[j + 1]) / prices[j + 1];
                    historicalReturns[validReturns] = dailyReturn;
                    validReturns++;
                }
            }
        }
    }
    
    if(validReturns < MIN_HISTORY)
    {
        // Fallback to parametric VaR if insufficient history
        double portfolioStdDev = m_currentRisk.totalRisk * 0.1;
        double zScore = 1.645; // 95% confidence
        
        if(confidence >= 0.99)
            zScore = 2.326;
        else if(confidence >= 0.95)
            zScore = 1.645;
        else if(confidence >= 0.90)
            zScore = 1.282;
        
        return portfolioStdDev * zScore;
    }
    
    // Resize array to actual valid returns
    ArrayResize(historicalReturns, validReturns);
    
    // Sort returns for percentile calculation
    ArraySort(historicalReturns);
    
    // Calculate VaR using historical simulation
    int varIndex = (int)((1.0 - confidence) * validReturns);
    varIndex = MathMax(0, MathMin(varIndex, validReturns - 1));
    
    double historicalVaR = historicalReturns[varIndex];
    
    // Apply portfolio weighting and current exposure
    double portfolioVaR = MathAbs(historicalVaR) * m_totalExposure;
    
    // Log VaR calculation for audit trail
    LogRiskEvent(ERROR_LEVEL_INFO,
                StringFormat("Historical VaR calculated: %.2f%% at %.0f%% confidence (n=%d days)",
                            portfolioVaR * 100.0, confidence * 100.0, validReturns));
    
    return portfolioVaR;
}

//+------------------------------------------------------------------+
//| Validate Risk Parameters                                       |
//+------------------------------------------------------------------+
bool CPortfolioRiskManager::ValidateRiskParameters(void)
{
    if(m_maxPortfolioRisk <= 0 || m_maxPortfolioRisk > 1.0)
    {
        LogRiskEvent(ERROR_LEVEL_ERROR, "Invalid max portfolio risk");
        return false;
    }
    
    if(m_maxLeverage <= 0 || m_maxLeverage > 100.0)
    {
        LogRiskEvent(ERROR_LEVEL_ERROR, "Invalid max leverage");
        return false;
    }
    
    if(m_maxPositions <= 0 || m_maxPositions > MAX_POSITIONS)
    {
        LogRiskEvent(ERROR_LEVEL_ERROR, "Invalid max positions");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Update Risk History                                            |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::UpdateRiskHistory(void)
{
    static datetime lastHourUpdate = 0;
    datetime currentTimeLocal = TimeCurrent();
    
    // Update hourly
    if(currentTimeLocal - lastHourUpdate >= 3600)
    {
        // Shift array left
        for(int i = 0; i < 23; i++)
            m_riskHistory[i] = m_riskHistory[i + 1];
        
        // Add current risk
        m_riskHistory[23] = m_currentRisk.totalRisk;
        
        lastHourUpdate = currentTimeLocal;
    }
}

//+------------------------------------------------------------------+
//| Trigger Emergency Stop                                         |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::TriggerEmergencyStop(const string reason)
{
    m_portfolioEmergencyMode = true;
    m_currentRisk.emergencyStop = true;
    
    LogRiskEvent(ERROR_LEVEL_CRITICAL, "EMERGENCY STOP TRIGGERED: " + reason);
    
    Alert("PORTFOLIO EMERGENCY STOP: ", reason);
    
    // Reduce risk exposure
    ReduceRiskExposure();
}

//+------------------------------------------------------------------+
//| Reduce Risk Exposure                                           |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::ReduceRiskExposure(void)
{
    LogRiskEvent(ERROR_LEVEL_CRITICAL, "Reducing risk exposure - emergency procedure");
    
    // This would typically:
    // 1. Close most risky positions
    // 2. Reduce position sizes
    // 3. Tighten stop losses
    // 4. Block new trades
    
    // For now, just log the action
    LogRiskEvent(ERROR_LEVEL_INFO, "Risk reduction procedures initiated");
}

//+------------------------------------------------------------------+
//| Get Risk Level                                                 |
//+------------------------------------------------------------------+
ENUM_RISK_LEVEL CPortfolioRiskManager::GetRiskLevel(void)
{
    if(m_portfolioEmergencyMode || m_currentRisk.drawdown > EMERGENCY_DRAWDOWN)
        return RISK_LEVEL_EXTREME;
    else if(m_currentRisk.totalRisk > m_maxPortfolioRisk * 80.0)
        return RISK_LEVEL_HIGH;
    else if(m_currentRisk.totalRisk > m_maxPortfolioRisk * 50.0)
        return RISK_LEVEL_MEDIUM;
    else
        return RISK_LEVEL_LOW;
}

//+------------------------------------------------------------------+
//| ENHANCED: Validate Portfolio Risk With New Trade               |
//+------------------------------------------------------------------+
bool CPortfolioRiskManager::ValidatePortfolioRiskWithNewTrade(const string symbolParam, const double volume)
{
    if(!m_initialized) return false;
    
    // Calculate potential risk from new trade
    double currentPriceLocal = SymbolInfoDouble(symbolParam, SYMBOL_BID);
    if(currentPriceLocal <= 0) return false;
    
    // Estimate stop loss distance (use 2% of price if no specific SL)
    double estimatedSL = currentPriceLocal * 0.02;
    double tickValue = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_VALUE);
    double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
    
    if(tickValue <= 0 || point <= 0) return false;
    
    double potentialRisk = volume * (estimatedSL / point) * tickValue;
    double riskPercent = (potentialRisk / m_portfolioValue) * 100.0;
    
    // Check if adding this risk would exceed 8% portfolio limit
    double totalRiskWithNewTrade = m_currentRisk.totalRisk + riskPercent;
    if(totalRiskWithNewTrade > 8.0)
    {
        LogRiskEvent(ERROR_LEVEL_WARNING, 
                    StringFormat("New trade would exceed 8%% portfolio risk: %.2f%% + %.2f%% = %.2f%%", 
                                m_currentRisk.totalRisk, riskPercent, totalRiskWithNewTrade));
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| ENHANCED: Enforce Portfolio Risk Limits                        |
//+------------------------------------------------------------------+
bool CPortfolioRiskManager::EnforcePortfolioRiskLimits(void)
{
    if(!m_initialized) return false;
    
    UpdateRiskMetrics();
    
    // Check if portfolio risk exceeds 8%
    if(m_currentRisk.totalRisk > 8.0)
    {
        LogRiskEvent(ERROR_LEVEL_CRITICAL, 
                    StringFormat("PORTFOLIO RISK EXCEEDED 8%%: %.2f%% - Initiating position closure", 
                                m_currentRisk.totalRisk));
        
        // Close most risky positions until under 8%
        CloseRiskiestPositions();
        
        // Generate alert
        GenerateRiskAlert("PORTFOLIO_RISK_EXCEEDED", 
                         StringFormat("Portfolio risk %.2f%% exceeded 8%% limit", m_currentRisk.totalRisk));
        
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| ENHANCED: Real-Time Portfolio Risk Monitoring                  |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::MonitorPortfolioRiskRealTime(void)
{
    if(!m_initialized) return;
    
    static datetime lastMonitorTime = 0;
    datetime currentTimeLocal = TimeCurrent();
    
    // Monitor every 30 seconds
    if(currentTimeLocal - lastMonitorTime < 30) return;
    lastMonitorTime = currentTimeLocal;
    
    // Update risk metrics
    UpdateRiskMetrics();
    
    // ENHANCED: Monitor correlation changes
    MonitorCorrelationChanges();
    
    // ENHANCED: Monitor drawdown levels and adjust risk
    MonitorDrawdownLevels();
    
    // ENHANCED: Monitor volatility levels and news events
    MonitorVolatilityLevels();
    
    // Check critical thresholds
    if(m_currentRisk.totalRisk > 8.0)
    {
        EnforcePortfolioRiskLimits();
    }
    else if(m_currentRisk.totalRisk > 6.0)
    {
        GenerateRiskAlert("PORTFOLIO_RISK_WARNING", 
                         StringFormat("Portfolio risk approaching limit: %.2f%%", m_currentRisk.totalRisk));
    }
    
    // Check margin level
    if(m_currentRisk.marginLevel < 200.0 && m_currentRisk.marginLevel > 0)
    {
        GenerateRiskAlert("LOW_MARGIN_WARNING", 
                         StringFormat("Margin level critical: %.2f%%", m_currentRisk.marginLevel));
    }
    
    // Log risk status every 5 minutes with correlation info
    static datetime lastStatusLog = 0;
    if(currentTimeLocal - lastStatusLog >= 300)
    {
        LogRiskEvent(ERROR_LEVEL_INFO, 
                    StringFormat("Portfolio Status: Risk=%.2f%%, Positions=%d, Margin=%.2f%%, MaxCorr=%.2f", 
                                m_currentRisk.totalRisk, m_currentRisk.totalPositions, 
                                m_currentRisk.marginLevel, m_currentRisk.correlation));
        lastStatusLog = currentTimeLocal;
    }
}

//+------------------------------------------------------------------+
//| ENHANCED: Generate Risk Alert                                  |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::GenerateRiskAlert(const string alertType, const string message)
{
    // Log the alert
    LogRiskEvent(ERROR_LEVEL_WARNING, StringFormat("[%s] %s", alertType, message));
    
    // Send MT5 alert
    Alert("PORTFOLIO RISK ALERT: ", message);
    
    // Print to experts log
    Print("🚨 RISK ALERT [", alertType, "]: ", message);
    
    // Could also send email, push notification, etc.
}

//+------------------------------------------------------------------+
//| ENHANCED: Close Riskiest Positions                             |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::CloseRiskiestPositions(void)
{
    if(!m_initialized) return;
    
    // Create array of positions sorted by risk
    struct SPositionRisk {
        ulong ticket;
        double risk;
        string symbol;
        double volume;
    };
    
    SPositionRisk positionRisks[];
    ArrayResize(positionRisks, m_positionCount);
    
    // Calculate risk for each position
    for(int i = 0; i < m_positionCount; i++)
    {
        SPositionInfo pos = m_positions[i];
        double positionRisk = 0.0;
        
        if(pos.stopLoss > 0)
        {
            double riskAmount = MathAbs(pos.openPrice - pos.stopLoss) * pos.volume;
            double tickValue = SymbolInfoDouble(pos.symbol, SYMBOL_TRADE_TICK_VALUE);
            double point = SymbolInfoDouble(pos.symbol, SYMBOL_POINT);
            
            if(tickValue > 0 && point > 0)
            {
                positionRisk = riskAmount * (tickValue / point);
            }
        }
        
        positionRisks[i].ticket = pos.ticket;
        positionRisks[i].risk = positionRisk;
        positionRisks[i].symbol = pos.symbol;
        positionRisks[i].volume = pos.volume;
    }
    
    // Sort by risk (highest first) - simple bubble sort
    for(int i = 0; i < ArraySize(positionRisks) - 1; i++)
    {
        for(int j = 0; j < ArraySize(positionRisks) - i - 1; j++)
        {
            if(positionRisks[j].risk < positionRisks[j + 1].risk)
            {
                SPositionRisk temp = positionRisks[j];
                positionRisks[j] = positionRisks[j + 1];
                positionRisks[j + 1] = temp;
            }
        }
    }
    
    // Close positions starting with highest risk until portfolio risk < 8%
    CTrade tradeLocal;
    for(int i = 0; i < ArraySize(positionRisks) && m_currentRisk.totalRisk > 8.0; i++)
    {
        if(tradeLocal.PositionClose(positionRisks[i].ticket))
        {
            LogRiskEvent(ERROR_LEVEL_WARNING, 
                        StringFormat("Emergency closure: Position %I64u (%s %.2f lots) - Risk: $%.2f", 
                                    positionRisks[i].ticket, positionRisks[i].symbol, 
                                    positionRisks[i].volume, positionRisks[i].risk));
            
            // Update risk metrics after closure
            UpdateRiskMetrics();
        }
        else
        {
            LogRiskEvent(ERROR_LEVEL_ERROR, 
                        StringFormat("Failed to close risky position %I64u: %s", 
                                    positionRisks[i].ticket, tradeLocal.ResultComment()));
        }
    }
}

//+------------------------------------------------------------------+
//| ENHANCED: Print Correlation Matrix                             |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::PrintCorrelationMatrix(void)
{
    if(!m_initialized || m_positionCount == 0) return;
    
    Print("\n=== CORRELATION MATRIX ===");
    
    // Print header
    string header = "Symbol      ";
    for(int i = 0; i < m_positionCount; i++)
    {
        header += StringFormat("%-8s ", StringSubstr(m_positions[i].symbol, 0, 7));
    }
    Print(header);
    
    // Print correlation matrix
    for(int i = 0; i < m_positionCount; i++)
    {
        string row = StringFormat("%-12s", StringSubstr(m_positions[i].symbol, 0, 11));
        
        for(int j = 0; j < m_positionCount; j++)
        {
            double correlation = CalculateSymbolCorrelation(m_positions[i].symbol, m_positions[j].symbol);
            row += StringFormat("%-8.2f ", correlation);
        }
        Print(row);
    }
    Print("============================\n");
}

//+------------------------------------------------------------------+
//| ENHANCED: Get Correlation Report                               |
//+------------------------------------------------------------------+
string CPortfolioRiskManager::GetCorrelationReport(void)
{
    if(!m_initialized || m_positionCount == 0)
        return "No positions for correlation analysis";
    
    string report = "CORRELATION REPORT:\n";
    
    // Find highest correlations
    double maxCorrelation = 0.0;
    string maxPair = "";
    int highCorrelationCount = 0;
    
    for(int i = 0; i < m_positionCount; i++)
    {
        for(int j = i + 1; j < m_positionCount; j++)
        {
            double correlation = CalculateSymbolCorrelation(m_positions[i].symbol, m_positions[j].symbol);
            
            if(correlation > 0.6)
            {
                highCorrelationCount++;
                report += StringFormat("HIGH: %s vs %s = %.2f\n", 
                                     m_positions[i].symbol, m_positions[j].symbol, correlation);
            }
            
            if(correlation > maxCorrelation)
            {
                maxCorrelation = correlation;
                maxPair = StringFormat("%s vs %s", m_positions[i].symbol, m_positions[j].symbol);
            }
        }
    }
    
    report += StringFormat("\nHighest Correlation: %s = %.2f\n", maxPair, maxCorrelation);
    report += StringFormat("High Correlation Pairs (>0.6): %d\n", highCorrelationCount);
    
    return report;
}

//+------------------------------------------------------------------+
//| ENHANCED: Monitor Correlation Changes                          |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::MonitorCorrelationChanges(void)
{
    if(!m_initialized) return;
    
    static datetime lastCorrelationCheck = 0;
    datetime currentTimeLocal = TimeCurrent();
    
    // Check correlations every 5 minutes
    if(currentTimeLocal - lastCorrelationCheck < 300) return;
    lastCorrelationCheck = currentTimeLocal;
    
    // Check for high correlation pairs
    int highCorrelationPairs = 0;
    double maxCorrelation = 0.0;
    
    for(int i = 0; i < m_positionCount; i++)
    {
        for(int j = i + 1; j < m_positionCount; j++)
        {
            double correlation = CalculateSymbolCorrelation(m_positions[i].symbol, m_positions[j].symbol);
            
            if(correlation > 0.6)
            {
                highCorrelationPairs++;
                
                LogRiskEvent(ERROR_LEVEL_WARNING, 
                            StringFormat("HIGH CORRELATION: %s vs %s = %.2f", 
                                        m_positions[i].symbol, m_positions[j].symbol, correlation));
            }
            
            if(correlation > maxCorrelation)
                maxCorrelation = correlation;
        }
    }
    
    // Alert if too many high correlation pairs
    if(highCorrelationPairs > 2)
    {
        GenerateRiskAlert("HIGH_CORRELATION_EXPOSURE", 
                         StringFormat("%d pairs with >0.6 correlation, max: %.2f", 
                                     highCorrelationPairs, maxCorrelation));
    }
    
    // Update correlation in risk metrics
    m_currentRisk.correlation = maxCorrelation;
}

//+------------------------------------------------------------------+
//| ENHANCED: Monitor Drawdown Levels                              |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::MonitorDrawdownLevels(void)
{
    if(!m_initialized) return;
    
    double currentDrawdownLocal = m_currentRisk.drawdown;
    
    // Check for 10% drawdown threshold
    if(currentDrawdownLocal >= 10.0 && !m_conservativeMode)
    {
        ActivateConservativeMode(StringFormat("Drawdown reached %.2f%%", currentDrawdownLocal));
    }
    // Check for recovery (drawdown below 5%)
    else if(currentDrawdownLocal < 5.0 && m_conservativeMode)
    {
        // Only deactivate if we've been in conservative mode for at least 1 hour
        datetime currentTimeLocal2 = TimeCurrent();
        if(currentTimeLocal2 - m_conservativeModeStart >= 3600)
        {
            DeactivateConservativeMode();
        }
    }
    
    // Adjust risk parameters based on drawdown level
    AdjustRiskParameters(currentDrawdownLocal);
    
    // Generate alerts for significant drawdown levels
    if(currentDrawdownLocal >= 15.0)
    {
        GenerateRiskAlert("CRITICAL_DRAWDOWN",
                         StringFormat("Critical drawdown: %.2f%% - Emergency protocols active", currentDrawdownLocal));
    }
    else if(currentDrawdownLocal >= 10.0)
    {
        GenerateRiskAlert("HIGH_DRAWDOWN",
                         StringFormat("High drawdown: %.2f%% - Conservative mode active", currentDrawdownLocal));
    }
    else if(currentDrawdownLocal >= 5.0)
    {
        GenerateRiskAlert("MODERATE_DRAWDOWN",
                         StringFormat("Moderate drawdown: %.2f%% - Risk reduction recommended", currentDrawdownLocal));
    }
}

//+------------------------------------------------------------------+
//| ENHANCED: Activate Conservative Mode                           |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::ActivateConservativeMode(const string reason)
{
    if(m_conservativeMode) return; // Already active
    
    m_conservativeMode = true;
    m_conservativeModeStart = TimeCurrent();
    
    // Store original risk parameters
    m_originalMaxRisk = m_maxPortfolioRisk;
    
    // Reduce risk parameters by 50%
    m_maxPortfolioRisk *= 0.5;
    
    LogRiskEvent(ERROR_LEVEL_WARNING, 
                StringFormat("CONSERVATIVE MODE ACTIVATED: %s - Risk reduced to %.2f%%", 
                            reason, m_maxPortfolioRisk * 100.0));
    
    GenerateRiskAlert("CONSERVATIVE_MODE_ACTIVATED", 
                     StringFormat("Risk reduced by 50%% due to: %s", reason));
    
    Print("🛡�?CONSERVATIVE MODE ACTIVATED: ", reason);
    Print("   Risk limit reduced from ", DoubleToString(m_originalMaxRisk * 100.0, 2), 
          "% to ", DoubleToString(m_maxPortfolioRisk * 100.0, 2), "%");
}

//+------------------------------------------------------------------+
//| ENHANCED: Deactivate Conservative Mode                         |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::DeactivateConservativeMode(void)
{
    if(!m_conservativeMode) return; // Not active
    
    m_conservativeMode = false;
    
    // Restore original risk parameters
    m_maxPortfolioRisk = m_originalMaxRisk;
    
    datetime duration = TimeCurrent() - m_conservativeModeStart;
    
    LogRiskEvent(ERROR_LEVEL_INFO, 
                StringFormat("CONSERVATIVE MODE DEACTIVATED - Duration: %d minutes - Risk restored to %.2f%%", 
                            (int)(duration / 60), m_maxPortfolioRisk * 100.0));
    
    GenerateRiskAlert("CONSERVATIVE_MODE_DEACTIVATED", 
                     StringFormat("Normal risk parameters restored after %d minutes", (int)(duration / 60)));
    
    Print("�?CONSERVATIVE MODE DEACTIVATED");
    Print("   Risk limit restored to ", DoubleToString(m_maxPortfolioRisk * 100.0, 2), "%");
}

//+------------------------------------------------------------------+
//| ENHANCED: Get Risk Adjustment Factor                           |
//+------------------------------------------------------------------+
double CPortfolioRiskManager::GetRiskAdjustmentFactor(void)
{
    double drawdown = m_currentRisk.drawdown;
    double adjustmentFactor = 1.0;
    
    // Progressive risk reduction based on drawdown
    if(drawdown >= 15.0)
    {
        adjustmentFactor = 0.25; // 75% risk reduction
    }
    else if(drawdown >= 10.0)
    {
        adjustmentFactor = 0.5;  // 50% risk reduction
    }
    else if(drawdown >= 5.0)
    {
        adjustmentFactor = 0.75; // 25% risk reduction
    }
    
    // Additional reduction if in conservative mode
    if(m_conservativeMode)
    {
        adjustmentFactor *= 0.8; // Additional 20% reduction
    }
    
    return adjustmentFactor;
}

//+------------------------------------------------------------------+
//| ENHANCED: Adjust Risk Parameters Based on Performance          |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::AdjustRiskParameters(const double drawdownPercent)
{
    static datetime lastAdjustment = 0;
    datetime localCurrentTime = TimeCurrent();
    
    // Adjust parameters every 10 minutes
    if(localCurrentTime - lastAdjustment < 600) return;
    lastAdjustment = localCurrentTime;
    
    double adjustmentFactor = GetRiskAdjustmentFactor();
    
    // Adjust position limits based on drawdown
    if(drawdownPercent >= 10.0)
    {
        // Reduce maximum positions
        int adjustedMaxPositions = (int)(MAX_POSITIONS * adjustmentFactor);
        if(adjustedMaxPositions != m_maxPositions)
        {
            m_maxPositions = MathMax(1, adjustedMaxPositions);
            LogRiskEvent(ERROR_LEVEL_INFO, 
                        StringFormat("Max positions adjusted to %d due to %.2f%% drawdown", 
                                    m_maxPositions, drawdownPercent));
        }
        
        // Tighten correlation limits
        m_maxCorrelation = MathMin(0.5, MAX_CORRELATION * adjustmentFactor);
    }
    else if(drawdownPercent < 2.0 && !m_conservativeMode)
    {
        // Gradually restore normal parameters when performance improves
        m_maxPositions = MAX_POSITIONS;
        m_maxCorrelation = MAX_CORRELATION;
    }
}

//+------------------------------------------------------------------+
//| ENHANCED: Check for Volatility Spike                          |
//+------------------------------------------------------------------+
bool CPortfolioRiskManager::IsVolatilitySpike(const string symbolParam)
{
    // Get ATR for volatility measurement
    int atrHandle = iATR(symbolParam, PERIOD_M15, 14);
    if(atrHandle == INVALID_HANDLE) return false;
    
    double atrValues[3];
    if(CopyBuffer(atrHandle, 0, 0, 3, atrValues) != 3)
    {
        IndicatorRelease(atrHandle);
        return false;
    }
    
    IndicatorRelease(atrHandle);
    
    // Check if current ATR is significantly higher than recent average
    double currentATRLocal = atrValues[0];
    double avgATR = (atrValues[1] + atrValues[2]) / 2.0;
    
    // Volatility spike if current ATR is 2x higher than average
    if(currentATRLocal > avgATR * 2.0)
    {
        LogRiskEvent(ERROR_LEVEL_WARNING,
                    StringFormat("VOLATILITY SPIKE detected on %s: Current ATR=%.5f, Avg ATR=%.5f",
                                symbolParam, currentATRLocal, avgATR));
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| ENHANCED: Activate Trading Pause                               |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::ActivateTradingPause(const string reason, const int durationMinutes)
{
    datetime localCurrentTime = TimeCurrent();
    
    m_tradingPaused = true;
    m_tradingPauseStart = localCurrentTime;
    m_tradingPauseEnd = localCurrentTime + (durationMinutes * 60);
    m_pauseReason = reason;
    
    LogRiskEvent(ERROR_LEVEL_WARNING, 
                StringFormat("TRADING PAUSE ACTIVATED: %s - Duration: %d minutes", 
                            reason, durationMinutes));
    
    GenerateRiskAlert("TRADING_PAUSE_ACTIVATED", 
                     StringFormat("Trading paused for %d minutes: %s", durationMinutes, reason));
    
    Print("⏸️ TRADING PAUSE ACTIVATED: ", reason);
    Print("   Duration: ", durationMinutes, " minutes");
    Print("   Ends at: ", TimeToString(m_tradingPauseEnd));
}

//+------------------------------------------------------------------+
//| ENHANCED: Deactivate Trading Pause                             |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::DeactivateTradingPause(void)
{
    if(!m_tradingPaused) return;
    
    datetime duration = TimeCurrent() - m_tradingPauseStart;
    
    m_tradingPaused = false;
    m_tradingPauseStart = 0;
    m_tradingPauseEnd = 0;
    
    LogRiskEvent(ERROR_LEVEL_INFO, 
                StringFormat("TRADING PAUSE DEACTIVATED - Duration: %d minutes - Reason was: %s", 
                            (int)(duration / 60), m_pauseReason));
    
    GenerateRiskAlert("TRADING_PAUSE_DEACTIVATED", 
                     StringFormat("Trading resumed after %d minutes", (int)(duration / 60)));
    
    Print("▶️ TRADING PAUSE DEACTIVATED");
    Print("   Total pause duration: ", (int)(duration / 60), " minutes");
    
    m_pauseReason = "";
}

//+------------------------------------------------------------------+
//| ENHANCED: Monitor Volatility Levels                            |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::MonitorVolatilityLevels(void)
{
    if(!m_initialized) return;
    
    static datetime lastVolatilityCheck = 0;
    datetime currentTimeLocal = TimeCurrent();
    
    // Check volatility every 2 minutes
    if(currentTimeLocal - lastVolatilityCheck < 120) return;
    lastVolatilityCheck = currentTimeLocal;
    
    // Check volatility for all open positions
    bool highVolatilityDetected = false;
    string volatileSymbols = "";
    
    for(int i = 0; i < m_positionCount; i++)
    {
        string symbolName = m_positions[i].symbol;
        
        if(IsVolatilitySpike(symbolName))
        {
            highVolatilityDetected = true;
            if(volatileSymbols != "") volatileSymbols += ", ";
            volatileSymbols += symbolName;
        }
    }
    
    // Activate trading pause if high volatility detected
    if(highVolatilityDetected && !m_tradingPaused)
    {
        ActivateTradingPause(StringFormat("High volatility on: %s", volatileSymbols), 15);
    }
    
    // Check for news events (simplified - in real implementation would use news calendar)
    static datetime lastNewsCheck = 0;
    if(currentTimeLocal - lastNewsCheck >= 3600) // Check hourly
    {
        lastNewsCheck = currentTimeLocal;
        
        // Check if it's a high-impact news time (simplified)
        MqlDateTime timeStruct;
        TimeToStruct(currentTimeLocal, timeStruct);
        
        // Pause trading during major news hours (8:30, 10:00, 14:00, 16:00 GMT)
        if((timeStruct.hour == 8 && timeStruct.min >= 25 && timeStruct.min <= 35) ||
           (timeStruct.hour == 10 && timeStruct.min <= 10) ||
           (timeStruct.hour == 14 && timeStruct.min <= 10) ||
           (timeStruct.hour == 16 && timeStruct.min <= 10))
        {
            if(!m_tradingPaused)
            {
                ActivateTradingPause("High-impact news time", 10);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| ENHANCED: Adjust Stop Loss for Volatility                      |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::AdjustStopLossForVolatility(const string symbolName, double &stopLoss)
{
    if(stopLoss <= 0) return;
    
    double volatilityAdjustment = CalculateVolatilityAdjustment(symbolName);
    
    // Widen stop loss during high volatility
    if(volatilityAdjustment > 1.5)
    {
        double currentPriceValue = SymbolInfoDouble(symbolName, SYMBOL_BID);
        if(currentPriceValue <= 0) return;
        
        double originalDistance = MathAbs(currentPriceValue - stopLoss);
        double adjustedDistance = originalDistance * volatilityAdjustment;
        
        // Adjust stop loss
        if(stopLoss < currentPriceValue) // Long position
        {
            stopLoss = currentPriceValue - adjustedDistance;
        }
        else // Short position
        {
            stopLoss = currentPriceValue + adjustedDistance;
        }
        
        LogRiskEvent(ERROR_LEVEL_INFO,
                    StringFormat("Stop loss widened for %s due to high volatility (factor: %.2f)",
                                symbolName, volatilityAdjustment));
    }
}

//+------------------------------------------------------------------+
//| ENHANCED: Calculate Volatility Adjustment Factor               |
//+------------------------------------------------------------------+
double CPortfolioRiskManager::CalculateVolatilityAdjustment(const string symbolName)
{
    // Get ATR for volatility measurement
    int atrHandle = iATR(symbolName, PERIOD_H1, 14);
    if(atrHandle == INVALID_HANDLE) return 1.0;
    
    double atrValues[5];
    if(CopyBuffer(atrHandle, 0, 0, 5, atrValues) != 5)
    {
        IndicatorRelease(atrHandle);
        return 1.0;
    }
    
    IndicatorRelease(atrHandle);
    
    // Calculate current vs average volatility
    double currentATRValue = atrValues[0];
    double avgATR = 0.0;
    for(int i = 1; i < 5; i++)
    {
        avgATR += atrValues[i];
    }
    avgATR /= 4.0;
    
    if(avgATR <= 0) return 1.0;
    
    double volatilityRatio = currentATRValue / avgATR;
    
    // Return adjustment factor (1.0 = normal, >1.0 = high volatility)
    return MathMax(1.0, MathMin(3.0, volatilityRatio)); // Cap at 3x adjustment
}

//+------------------------------------------------------------------+
//| Log Risk Event                                                 |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::LogRiskEvent(const ENUM_ERROR_LEVEL level, const string message)
{
    CEnhancedErrorHandler::LogError((ENUM_ERROR_SEVERITY)level, "PortfolioRiskManager", message);
}

#endif // CORE_PORTFOLIO_RISK_MANAGER_MQH
