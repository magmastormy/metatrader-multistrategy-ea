//+------------------------------------------------------------------+
//| Mandatory Risk Validation Gate - CLEAN VERSION                 |
//| Comprehensive trade validation before execution                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_RISK_VALIDATION_GATE_MQH
#define CORE_RISK_VALIDATION_GATE_MQH

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
//| Trade Request Validation Structure                             |
//+------------------------------------------------------------------+
struct STradeValidationRequest
{
    string symbol;                    // Trading symbol
    ENUM_ORDER_TYPE orderType;        // Order type (BUY/SELL)
    double lotSize;                   // Requested lot size
    double stopLossPips;              // Stop loss in pips
    double takeProfitPips;            // Take profit in pips
    double confidence;                // Signal confidence (0-1)
    string strategy;                  // Source strategy name
    string reasoning;                 // Trade reasoning
    datetime requestTime;             // Request timestamp
};

//+------------------------------------------------------------------+
//| Validation Result Structure                                    |
//+------------------------------------------------------------------+
struct SValidationResult
{
    bool approved;                    // Trade approved/rejected
    string message;                   // Validation message
    double adjustedLotSize;           // Adjusted lot size if needed
    double riskPercent;               // Calculated risk percentage
    double portfolioRisk;             // Total portfolio risk after trade
    double correlationRisk;           // Correlation risk factor
    bool requiresAdjustment;          // Lot size was adjusted
    ENUM_ERROR_LEVEL severity;        // Message severity level
};

//+------------------------------------------------------------------+
//| Risk Validation Gate Class                                    |
//+------------------------------------------------------------------+
class CRiskValidationGate
{
private:
    CPortfolioRiskManager* m_portfolioRiskManager;  // Use pointer instead of reference
    
    // Validation parameters
    double m_maxRiskPerTrade;         // Maximum risk per trade (3%)
    double m_maxPortfolioRisk;        // Maximum total portfolio risk (10%)
    double m_correlationThreshold;    // Correlation blocking threshold (0.7)
    double m_emergencyRiskOverride;   // Emergency risk override (5%)
    
    // Audit trail
    bool m_auditLogging;
    string m_auditLogFile;
    int m_validationCount;
    int m_approvedCount;
    int m_rejectedCount;
    
    // Performance tracking
    datetime m_lastValidation;
    double m_avgValidationTime;
    
public:
    // Constructor/Destructor declarations
    CRiskValidationGate();
    ~CRiskValidationGate();
    
    // Delete copy constructor and assignment operator
    CRiskValidationGate(const CRiskValidationGate&) = delete;
    void operator=(const CRiskValidationGate&) = delete;
    
    // Initialize validation gate
    bool Initialize(CPortfolioRiskManager* portfolioRiskManager,
                   const double maxRiskPerTrade = 3.0,  // 🔥 Changed from 2.0 to 3.0 to match EA's InpMaxRiskPerTrade
                   const double maxPortfolioRisk = 10.0,
                   const double correlationThreshold = 0.7);
    
    // Main validation function - MUST approve every trade
    SValidationResult ValidateTradeRequest(const STradeValidationRequest &request);
    
    // Individual validation checks
    bool ValidateBasicParameters(const STradeValidationRequest &request, string &message);
    bool ValidateRiskLimits(const STradeValidationRequest &request, string &message, double &riskPercent);
    bool ValidatePortfolioRisk(const STradeValidationRequest &request, const double tradeRisk, string &message);
    bool ValidateCorrelationLimits(const STradeValidationRequest &request, string &message, double &correlationRisk);
    bool ValidateMarginRequirements(const STradeValidationRequest &request, string &message);
    bool ValidateAccountHealth(const STradeValidationRequest &request, string &message);
    
    // Risk calculations
    double CalculateTradeRisk(const string symbolParam, const double lotSize, const double stopLossPips);
    double CalculateCorrelationRisk(const string symbolParam);
    double CalculatePortfolioRiskAfterTrade(const double additionalRisk);
    
    // Position size adjustments
    double AdjustLotSizeForRisk(const STradeValidationRequest &request, const double maxRisk);
    double AdjustLotSizeForCorrelation(const STradeValidationRequest &request, const double correlationFactor);
    
    // Audit and logging
    void LogValidationResult(const STradeValidationRequest &request, const SValidationResult &result);
    void EnableAuditLogging(const bool enabled, const string logFile = "RiskValidation.log");
    
    // Statistics
    void GetValidationStats(int &total, int &approved, int &rejected, double &approvalRate);
    void ResetStats(void);
    
    // Configuration
    void SetMaxRiskPerTrade(const double maxRisk) { m_maxRiskPerTrade = maxRisk; }

//+------------------------------------------------------------------+
//| Portfolio helper implementations                                |
//+------------------------------------------------------------------+
double CRiskValidationGate::GetPortfolioRiskValue() const
{
    CPortfolioRiskManager* manager = m_portfolioRiskManager;
    if(CheckPointer(manager) == POINTER_INVALID)
        return 0.0;
    return (*manager).GetPortfolioRisk();
}

bool CRiskValidationGate::PortfolioAllowsTrade(const string symbolParam, const double lotSize) const
{
    CPortfolioRiskManager* manager = m_portfolioRiskManager;
    if(CheckPointer(manager) == POINTER_INVALID)
        return true;
    return (*manager).IsTradeAllowed(symbolParam, lotSize);
}

bool CRiskValidationGate::PortfolioCorrelationAllowed(const string symbolParam) const
{
    CPortfolioRiskManager* manager = m_portfolioRiskManager;
    if(CheckPointer(manager) == POINTER_INVALID)
        return true;
    return (*manager).CheckCorrelationLimits(symbolParam);
}

bool CRiskValidationGate::PortfolioEmergencyActive() const
{
    CPortfolioRiskManager* manager = m_portfolioRiskManager;
    if(CheckPointer(manager) == POINTER_INVALID)
        return false;
    return (*manager).IsEmergencyMode();
}
    void SetMaxPortfolioRisk(const double maxRisk) { m_maxPortfolioRisk = maxRisk; }
    void SetCorrelationThreshold(const double threshold) { m_correlationThreshold = threshold; }
    
private:
    // Internal helper functions
    bool IsSymbolDataValid(const string symbolParam);
    double GetSymbolTickValue(const string symbolParam);
    double GetSymbolPoint(const string symbolParam);
    bool CheckAccountTradingPermissions(void);
    
    // Correlation calculations
    double CalculateSymbolCorrelation(const string symbol1Param, const string symbol2Param);
    double GetMaxCorrelationWithPortfolio(const string symbolParam);
    
    // Audit functions
    void WriteAuditLog(const string message);
    string FormatValidationMessage(const STradeValidationRequest &request, const SValidationResult &result);
    
    // Performance tracking
    void UpdatePerformanceMetrics(const datetime startTime);
};

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CRiskValidationGate::CRiskValidationGate() : m_portfolioRiskManager(NULL),
                                           m_maxRiskPerTrade(2.0),
                                           m_maxPortfolioRisk(10.0),
                                           m_correlationThreshold(0.7),
                                           m_emergencyRiskOverride(5.0),
                                           m_auditLogging(true),
                                           m_auditLogFile("RiskValidation.log"),
                                           m_validationCount(0),
                                           m_approvedCount(0),
                                           m_rejectedCount(0),
                                           m_lastValidation(0),
                                           m_avgValidationTime(0.0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CRiskValidationGate::~CRiskValidationGate()
{
    if(m_auditLogging)
    {
        WriteAuditLog("Risk Validation Gate shutdown - Stats: " + 
                     IntegerToString(m_validationCount) + " total, " +
                     IntegerToString(m_approvedCount) + " approved, " +
                     IntegerToString(m_rejectedCount) + " rejected");
    }
}

//+------------------------------------------------------------------+
//| Initialize validation gate                                     |
//+------------------------------------------------------------------+
bool CRiskValidationGate::Initialize(CPortfolioRiskManager* pPortfolioRiskManager,
                                    const double maxRiskPerTrade,
                                    const double maxPortfolioRisk,
                                    const double correlationThreshold)
{
    if(CheckPointer(pPortfolioRiskManager) == POINTER_INVALID)
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "RiskValidationGate", "Invalid portfolio risk manager pointer", 0);
        return false;
    }
    
    m_portfolioRiskManager = pPortfolioRiskManager;
    
    // Validate parameters
    if(maxRiskPerTrade <= 0 || maxRiskPerTrade > 10.0)
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "RiskValidationGate", "Invalid max risk per trade", 0);
        return false;
    }
    
    if(maxPortfolioRisk <= 0 || maxPortfolioRisk > 50.0)
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "RiskValidationGate", "Invalid max portfolio risk", 0);
        return false;
    }
    
    if(correlationThreshold < 0 || correlationThreshold > 1.0)
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "RiskValidationGate", "Invalid correlation threshold", 0);
        return false;
    }
    
    // Set parameters
    m_maxRiskPerTrade = maxRiskPerTrade;
    m_maxPortfolioRisk = maxPortfolioRisk;
    m_correlationThreshold = correlationThreshold;
    
    // Initialize audit logging
    if(m_auditLogging)
    {
        WriteAuditLog("Risk Validation Gate initialized - Max Risk: " + 
                     DoubleToString(maxRiskPerTrade, 1) + "%, Portfolio: " +
                     DoubleToString(maxPortfolioRisk, 1) + "%, Correlation: " +
                     DoubleToString(correlationThreshold, 2));
    }
    
    CEnhancedErrorHandler::LogError(ERROR_INFO, "RiskValidationGate", "Risk validation gate initialized successfully", 0);
    return true;
}

//| Main validation function - MUST approve every trade           |
//+------------------------------------------------------------------+
SValidationResult CRiskValidationGate::ValidateTradeRequest(const STradeValidationRequest &request)
{
    datetime startTimeParam = TimeCurrent();
    m_validationCount++;
    
    SValidationResult result;
    result.approved = false;
    result.message = "";
    result.adjustedLotSize = request.lotSize;
    result.riskPercent = 0.0;
    result.portfolioRisk = 0.0;
    result.correlationRisk = 0.0;
    result.requiresAdjustment = false;
    result.severity = ERROR_LEVEL_INFO;
    
    string validationMessage = "";
    
    // 1. Validate basic parameters
    if(!ValidateBasicParameters(request, validationMessage))
    {
        result.message = "Basic validation failed: " + validationMessage;
        result.severity = ERROR_LEVEL_ERROR;
        m_rejectedCount++;
        LogValidationResult(request, result);
        return result;
    }
    
    // 2. Validate risk limits
    double tradeRisk = 0.0;
    if(!ValidateRiskLimits(request, validationMessage, tradeRisk))
    {
        result.message = "Risk limit validation failed: " + validationMessage;
        result.riskPercent = tradeRisk;
        result.severity = ERROR_LEVEL_ERROR;
        m_rejectedCount++;
        LogValidationResult(request, result);
        return result;
    }
    result.riskPercent = tradeRisk;
    
    // 3. Validate portfolio risk
    if(!ValidatePortfolioRisk(request, tradeRisk, validationMessage))
    {
        result.message = "Portfolio risk validation failed: " + validationMessage;
        result.severity = ERROR_LEVEL_ERROR;
        m_rejectedCount++;
        LogValidationResult(request, result);
        return result;
    }
    
    // 4. Validate correlation limits
    double correlationRisk = 0.0;
    if(!ValidateCorrelationLimits(request, validationMessage, correlationRisk))
    {
        result.message = "Correlation validation failed: " + validationMessage;
        result.correlationRisk = correlationRisk;
        result.severity = ERROR_LEVEL_WARNING;
        m_rejectedCount++;
        LogValidationResult(request, result);
        return result;
    }
    result.correlationRisk = correlationRisk;
    
    // 5. Validate margin requirements
    if(!ValidateMarginRequirements(request, validationMessage))
    {
        result.message = "Margin validation failed: " + validationMessage;
        result.severity = ERROR_LEVEL_ERROR;
        m_rejectedCount++;
        LogValidationResult(request, result);
        return result;
    }
    
    // 6. Validate account health
    if(!ValidateAccountHealth(request, validationMessage))
    {
        result.message = "Account health validation failed: " + validationMessage;
        result.severity = ERROR_LEVEL_CRITICAL;
        m_rejectedCount++;
        LogValidationResult(request, result);
        return result;
    }
    
    // All validations passed
    result.approved = true;
    result.message = "Trade request approved";
    result.portfolioRisk = CalculatePortfolioRiskAfterTrade(tradeRisk);
    result.severity = ERROR_LEVEL_INFO;
    m_approvedCount++;
    
    LogValidationResult(request, result);
    UpdatePerformanceMetrics(startTimeParam);
    
    return result;
}

//+------------------------------------------------------------------+
//| Validate basic parameters                                      |
//+------------------------------------------------------------------+
bool CRiskValidationGate::ValidateBasicParameters(const STradeValidationRequest &request, string &message)
{
    // Validate symbol
    if(StringLen(request.symbol) == 0)
    {
        message = "Empty symbol";
        return false;
    }
    
    if(!IsSymbolDataValid(request.symbol))
    {
        message = "Invalid symbol data for " + request.symbol;
        return false;
    }
    
    // Validate lot size
    if(request.lotSize <= 0)
    {
        message = "Invalid lot size: " + DoubleToString(request.lotSize, 3);
        return false;
    }
    
    double minLot = SymbolInfoDouble(request.symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(request.symbol, SYMBOL_VOLUME_MAX);
    
    if(request.lotSize < minLot)
    {
        message = "Lot size below minimum: " + DoubleToString(request.lotSize, 3) + " < " + DoubleToString(minLot, 3);
        return false;
    }
    
    if(request.lotSize > maxLot)
    {
        message = "Lot size above maximum: " + DoubleToString(request.lotSize, 3) + " > " + DoubleToString(maxLot, 3);
        return false;
    }
    
    // Validate stop loss
    if(request.stopLossPips <= 0)
    {
        message = "Invalid stop loss: " + DoubleToString(request.stopLossPips, 1) + " pips";
        return false;
    }
    
    // Validate order type
    if(request.orderType != ORDER_TYPE_BUY && request.orderType != ORDER_TYPE_SELL)
    {
        message = "Invalid order type: " + EnumToString(request.orderType);
        return false;
    }
    
    // Check trading permissions
    if(!CheckAccountTradingPermissions())
    {
        message = "Trading not allowed";
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate risk limits                                           |
//+------------------------------------------------------------------+
bool CRiskValidationGate::ValidateRiskLimits(const STradeValidationRequest &request, string &message, double &riskPercent)
{
    // Calculate trade risk
    double tradeRisk = CalculateTradeRisk(request.symbol, request.lotSize, request.stopLossPips);
    
    if(tradeRisk <= 0)
    {
        message = "Unable to calculate trade risk";
        return false;
    }
    
    // Convert to percentage
    double accountBalanceLocal = AccountInfoDouble(ACCOUNT_BALANCE);
    if(accountBalanceLocal <= 0)
    {
        message = "Invalid account balance";
        return false;
    }
    
    riskPercent = (tradeRisk / accountBalanceLocal) * 100.0;
    
    // Check against maximum risk per trade
    if(riskPercent > m_maxRiskPerTrade)
    {
        message = StringFormat("Risk %.2f%% exceeds maximum %.2f%%", riskPercent, m_maxRiskPerTrade);
        return false;
    }
    
    // Emergency risk override check
    if(riskPercent > m_emergencyRiskOverride)
    {
        message = StringFormat("Risk %.2f%% exceeds emergency override %.2f%%", riskPercent, m_emergencyRiskOverride);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate portfolio risk                                        |
//+------------------------------------------------------------------+
bool CRiskValidationGate::ValidatePortfolioRisk(const STradeValidationRequest &request, const double tradeRisk, string &message)
{
    CPortfolioRiskManager* manager = m_portfolioRiskManager;

    if(CheckPointer(manager) == POINTER_INVALID)
    {
        message = "Portfolio risk manager not available";
        return false;
    }

    double currentRisk = (*manager).GetPortfolioRisk();
    double totalRisk = currentRisk + tradeRisk;

    if(totalRisk > m_maxPortfolioRisk)
    {
        message = StringFormat("Total portfolio risk %.2f%% would exceed maximum %.2f%%", totalRisk, m_maxPortfolioRisk);
        return false;
    }

    if(!(*manager).IsTradeAllowed(request.symbol, request.lotSize))
    {
        message = "Trade blocked by portfolio risk manager";
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Validate correlation limits                                    |
//+------------------------------------------------------------------+
bool CRiskValidationGate::ValidateCorrelationLimits(const STradeValidationRequest &request, string &message, double &correlationRisk)
{
    correlationRisk = CalculateCorrelationRisk(request.symbol);

    if(correlationRisk > m_correlationThreshold)
    {
        message = StringFormat("Correlation risk %.2f exceeds threshold %.2f", correlationRisk, m_correlationThreshold);
        return false;
    }

    if(CheckPointer(m_portfolioRiskManager) != POINTER_INVALID)
    {
        CPortfolioRiskManager* manager = m_portfolioRiskManager;
        if(CheckPointer(manager) != POINTER_INVALID && !(*manager).CheckCorrelationLimits(request.symbol))
        {
            message = "Correlation limit exceeded";
            return false;
        }
    }

    return true;
}

//+------------------------------------------------------------------+
//| Validate margin requirements                                   |
//+------------------------------------------------------------------+
bool CRiskValidationGate::ValidateMarginRequirements(const STradeValidationRequest &request, string &message)
{
    // Calculate margin requirement
    double marginRequired = 0.0;
    double currentPriceLocal = (request.orderType == ORDER_TYPE_BUY) ?
                              SymbolInfoDouble(request.symbol, SYMBOL_ASK) :
                              SymbolInfoDouble(request.symbol, SYMBOL_BID);
    
    if(!OrderCalcMargin(request.orderType, request.symbol, request.lotSize, currentPriceLocal, marginRequired))
    {
        message = "Unable to calculate margin requirement";
        return false;
    }
    
    // Check available margin
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    if(marginRequired > freeMargin * 0.8) // Use max 80% of free margin
    {
        message = StringFormat("Insufficient margin: required %.2f, available %.2f", marginRequired, freeMargin);
        return false;
    }
    
    // Check margin level after trade
    double currentMarginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
    if(currentMarginLevel > 0 && currentMarginLevel < 200.0)
    {
        message = StringFormat("Margin level too low: %.2f%%", currentMarginLevel);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate account health                                        |
//+------------------------------------------------------------------+
bool CRiskValidationGate::ValidateAccountHealth(const STradeValidationRequest &request, string &message)
{
    double accountBalanceLocal2 = AccountInfoDouble(ACCOUNT_BALANCE);
    if(accountBalanceLocal2 < MIN_ACCOUNT_BALANCE)
    {
        message = StringFormat("Account balance too low: %.2f", accountBalanceLocal2);
        return false;
    }

    double accountEquityLocal = AccountInfoDouble(ACCOUNT_EQUITY);
    double drawdown = 0.0;

    if(accountBalanceLocal2 > 0)
    {
        drawdown = ((accountBalanceLocal2 - accountEquityLocal) / accountBalanceLocal2) * 100.0;
    }

    if(drawdown > DRAWDOWN_CRITICAL)
    {
        message = StringFormat("Drawdown too high: %.2f%%", drawdown);
        return false;
    }

    if(PortfolioEmergencyActive())
    {
        message = "Emergency mode active - trading suspended";
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Calculate trade risk                                           |
//+------------------------------------------------------------------
double CRiskValidationGate::CalculateTradeRisk(const string symbolParam, double lotSize, double stopLossPips)
{
    if(symbolParam == "" || stopLossPips <= 0) {
        return 0.0;
    }
    
    double tickValue = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_SIZE);
    double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
    double contractSize = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_CONTRACT_SIZE);
    
    if(tickValue <= 0 || point <= 0 || tickSize <= 0) {
        return 0.0;
    }
    
    // 🔥 FIX: Calculate risk properly based on symbol type
    // stopLossPips is actually in POINTS (e.g., 50 points)
    // For EURGBP: point = 0.00001, so 50 points = 0.0005 = 5 pips
    // For EURUSD: point = 0.00001, so 50 points = 0.0005 = 5 pips
    
    double stopLossPrice = stopLossPips * point;  // Convert points to price difference
    double riskPerLot = (stopLossPrice / tickSize) * tickValue;  // Risk per 1.0 lot
    double totalRisk = lotSize * riskPerLot;
    
    // Debug logging for problem symbols
    static datetime g_lastRiskCalcLog = 0;
    if((symbolParam == "EURGBP.0" || symbolParam == "XPTUSD.0") && 
       TimeCurrent() - g_lastRiskCalcLog > 120)
    {
        PrintFormat("[RISK-CALC-DEBUG] %s: Lot=%.2f, SL_pts=%.0f, Point=%.5f, TickVal=%.2f, TickSz=%.5f, Risk=$%.2f",
                   symbolParam, lotSize, stopLossPips, point, tickValue, tickSize, totalRisk);
        g_lastRiskCalcLog = TimeCurrent();
    }
    
    return totalRisk;
}

//+------------------------------------------------------------------+
//| Calculate correlation risk                                     |
//+------------------------------------------------------------------+
double CRiskValidationGate::CalculateCorrelationRisk(const string symbolParam)
{
    double maxCorrelation = 0.0;
    
    // Check correlation with all open positions
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            string existingSymbol = PositionGetString(POSITION_SYMBOL);
            if(existingSymbol != symbolParam)
            {
                double correlation = CalculateSymbolCorrelation(symbolParam, existingSymbol);
                maxCorrelation = MathMax(maxCorrelation, MathAbs(correlation));
            }
        }
    }
    
    return maxCorrelation;
}

//+------------------------------------------------------------------+
//| Calculate portfolio risk after trade                          |
//+------------------------------------------------------------------+
double CRiskValidationGate::CalculatePortfolioRiskAfterTrade(const double additionalRisk)
{
    return GetPortfolioRiskValue() + additionalRisk;
}

//+------------------------------------------------------------------+
//| Log validation result                                          |
//+------------------------------------------------------------------+
void CRiskValidationGate::LogValidationResult(const STradeValidationRequest &request, const SValidationResult &result)
{
    if(!m_auditLogging)
        return;
    
    string logMessage = FormatValidationMessage(request, result);
    WriteAuditLog(logMessage);
    
    // Also log to error handler
    CEnhancedErrorHandler::LogError(ERROR_INFO, "RiskValidationGate", result.message, 0);
}

//+------------------------------------------------------------------+
//| Enable audit logging                                           |
//+------------------------------------------------------------------+
void CRiskValidationGate::EnableAuditLogging(const bool enabled, const string logFile = "RiskValidation.log")
{
    m_auditLogging = enabled;
    m_auditLogFile = logFile;
    
    if(enabled)
    {
        WriteAuditLog("Audit logging enabled");
    }
}

//+------------------------------------------------------------------+
//| Get validation statistics                                      |
//+------------------------------------------------------------------+
void CRiskValidationGate::GetValidationStats(int &total, int &approved, int &rejected, double &approvalRate)
{
    total = m_validationCount;
    approved = m_approvedCount;
    rejected = m_rejectedCount;
    
    if(total > 0)
        approvalRate = (double)approved / total * 100.0;
    else
        approvalRate = 0.0;
}

//+------------------------------------------------------------------+
//| Reset statistics                                               |
//+------------------------------------------------------------------+
void CRiskValidationGate::ResetStats(void)
{
    m_validationCount = 0;
    m_approvedCount = 0;
    m_rejectedCount = 0;
    
    WriteAuditLog("Validation statistics reset");
}

//+------------------------------------------------------------------+
//| Internal helper functions                                      |
//+------------------------------------------------------------------+
bool CRiskValidationGate::IsSymbolDataValid(const string symbolParam)
{
    if(!SymbolSelect(symbolParam, true))
        return false;
    
    double bid = SymbolInfoDouble(symbolParam, SYMBOL_BID);
    double ask = SymbolInfoDouble(symbolParam, SYMBOL_ASK);
    
    return (bid > 0 && ask > 0);
}

double CRiskValidationGate::GetSymbolTickValue(const string symbolParam)
{
    return SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_VALUE);
}

double CRiskValidationGate::GetSymbolPoint(const string symbolParam)
{
    return SymbolInfoDouble(symbolParam, SYMBOL_POINT);
}

bool CRiskValidationGate::CheckAccountTradingPermissions(void)
{
    if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
        return false;
    
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
        return false;
    
    if(!TerminalInfoInteger(TERMINAL_CONNECTED))
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate symbol correlation                                   |
//+------------------------------------------------------------------+
double CRiskValidationGate::CalculateSymbolCorrelation(const string symbol1, const string symbol2)
{
    // Simple correlation calculation based on recent price movements
    double prices1[], prices2[];
    int period = 20; // Use 20 periods for correlation
    
    if(CopyClose(symbol1, PERIOD_H1, 0, period, prices1) < period ||
       CopyClose(symbol2, PERIOD_H1, 0, period, prices2) < period) {
        return 0.0; // No correlation if insufficient data
    }
    
    // Calculate returns
    double returns1[], returns2[];
    ArrayResize(returns1, period - 1);
    ArrayResize(returns2, period - 1);
    
    for(int i = 1; i < period; i++) {
        returns1[i-1] = (prices1[i] - prices1[i-1]) / prices1[i-1];
        returns2[i-1] = (prices2[i] - prices2[i-1]) / prices2[i-1];
    }
    
    // Calculate correlation coefficient
    double sum1 = 0, sum2 = 0, sum12 = 0, sum1sq = 0, sum2sq = 0;
    int n = period - 1;
    
    for(int i = 0; i < n; i++) {
        sum1 += returns1[i];
        sum2 += returns2[i];
        sum12 += returns1[i] * returns2[i];
        sum1sq += returns1[i] * returns1[i];
        sum2sq += returns2[i] * returns2[i];
    }
    
    double numerator = n * sum12 - sum1 * sum2;
    double denominator = MathSqrt((n * sum1sq - sum1 * sum1) * (n * sum2sq - sum2 * sum2));
    
    if(denominator == 0) return 0.0;
    
    return numerator / denominator;
}

//+------------------------------------------------------------------+
//| Write audit log                                               |
//+------------------------------------------------------------------+
void CRiskValidationGate::WriteAuditLog(const string message)
{
    if(!m_auditLogging)
        return;
    
    int handle = FileOpen(m_auditLogFile, FILE_WRITE | FILE_READ | FILE_TXT);
    if(handle != INVALID_HANDLE)
    {
        FileSeek(handle, 0, SEEK_END);
        string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
        FileWrite(handle, StringFormat("[%s] %s", timestamp, message));
        FileClose(handle);
    }
}

//+------------------------------------------------------------------+
//| Format validation message                                      |
//+------------------------------------------------------------------+
string CRiskValidationGate::FormatValidationMessage(const STradeValidationRequest &request, const SValidationResult &result)
{
    return StringFormat("VALIDATION: %s %s %.3f lots | %s | Risk: %.2f%% | Portfolio: %.2f%% | Correlation: %.2f",
                       request.symbol,
                       EnumToString(request.orderType),
                       request.lotSize,
                       result.approved ? "APPROVED" : "REJECTED",
                       result.riskPercent,
                       result.portfolioRisk,
                       result.correlationRisk);
}

//+------------------------------------------------------------------+
//| Update performance metrics                                     |
//+------------------------------------------------------------------+
void CRiskValidationGate::UpdatePerformanceMetrics(const datetime startTimeParam)
{
    datetime endTime = (datetime)GetMicrosecondCount();
    double validationTime = (double)(endTime - startTimeParam) / 1000.0; // Convert to milliseconds
    
    if(m_validationCount == 1)
    {
        m_avgValidationTime = validationTime;
    }
    else
    {
        m_avgValidationTime = (m_avgValidationTime * (m_validationCount - 1) + validationTime) / m_validationCount;
    }
    
    m_lastValidation = TimeCurrent();
}

#endif // CORE_RISK_VALIDATION_GATE_MQH

