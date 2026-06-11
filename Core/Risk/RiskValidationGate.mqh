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
#include "CorrelationEngine.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;
class CUnifiedRiskManager;

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
    string strategyRole;              // Strategy governance role tag
    string strategyCluster;           // Strategy cluster tag
    string clusterCode;               // Compact cluster code (T/R/S/N)
    string contributorContext;        // Contributor summary
    datetime requestTime;             // Request timestamp
};


//+------------------------------------------------------------------+
//| Risk Validation Gate Class                                    |
//+------------------------------------------------------------------+
class CRiskValidationGate
{
private:
    CPortfolioRiskManager* m_portfolioRiskManager;  // Use pointer instead of reference
    CUnifiedRiskManager*   m_unifiedRiskManager;    // Unified drawdown authority (Phase 2.1)
    
    // Validation parameters
    double m_maxRiskPerTrade;         // Blueprint 10.4: 0-100 scale (e.g., 3.0 = 3%)
    double m_maxPortfolioRisk;        // Blueprint 10.4: 0-100 scale (e.g., 10.0 = 10%)
    double m_correlationThreshold;    // Correlation blocking threshold (0-1 scale, not a risk percent)
    int m_maxPositionsSameBase;       // Max positions with the same base currency
    double m_emergencyRiskOverride;   // Blueprint 10.4: 0-100 scale (5.0 = 5%)
    bool m_clusterGovernanceEnabled;  // Cluster-level risk governance
    bool m_clusterMutexEnabled;       // Same-symbol opposing-cluster mutex
    int m_maxConcurrentPerCluster;    // Max open positions per cluster
    double m_maxClusterRiskPercent;   // Blueprint 10.4: 0-100 scale
    
    // Margin check thresholds (configurable for broker differences)
    double m_maxFreeMarginUsage;      // Maximum free margin usage percentage (default 0.8 = 80%)
    double m_minMarginLevel;         // Minimum acceptable margin level (default 200.0 = 200%)
    
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
                   const double correlationThreshold = 0.7,
                   const int maxPositionsSameBase = 3,
                   const double maxFreeMarginUsage = 0.8,
                   const double minMarginLevel = 200.0);
    
    // Main validation function - MUST approve every trade
    SValidationResult ValidateTradeRequest(const STradeValidationRequest &request);
    
    // Individual validation checks
    bool ValidateBasicParameters(const STradeValidationRequest &request, string &message);
    bool ValidateRiskLimits(const STradeValidationRequest &request, string &message, double &riskPercent);
    bool ValidatePortfolioRisk(const STradeValidationRequest &request, const double tradeRiskPercent, string &message);
    bool ValidateCorrelationLimits(const STradeValidationRequest &request, string &message, double &correlationRisk);
    bool ValidateMarginRequirements(const STradeValidationRequest &request, string &message);
    bool ValidateAccountHealth(const STradeValidationRequest &request, string &message);
    
    // Risk calculations
    double CalculateTradeRisk(const string symbolParam, const double lotSize, const double stopLossPips) const;
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
    void SetMaxPortfolioRisk(const double maxRisk) { m_maxPortfolioRisk = maxRisk; }
    void SetCorrelationThreshold(const double threshold) { m_correlationThreshold = threshold; }
    void SetUnifiedRiskManager(CUnifiedRiskManager* manager) { m_unifiedRiskManager = manager; }
    void ConfigureClusterGovernance(const bool enabled,
                                    const int maxConcurrentPerCluster,
                                    const double maxClusterRiskPercent,
                                    const bool enableMutex);
    
private:
    // Portfolio helper accessors
    double GetPortfolioRiskValue() const;
    bool PortfolioAllowsTrade(const string symbolParam, const double lotSize) const;
    bool PortfolioCorrelationAllowed(const string symbolParam) const;
    bool PortfolioEmergencyActive() const;
    bool PortfolioHasUnprotectedPositions() const;

    // Internal helper functions
    bool IsSymbolDataValid(const string symbolParam);
    double GetSymbolTickValue(const string symbolParam);
    double GetSymbolPoint(const string symbolParam);
    bool CheckAccountTradingPermissions(void);
    bool ValidateClusterGovernance(const STradeValidationRequest &request,
                                   const double tradeRiskPercent,
                                   string &message);
    bool ParseClusterCodeFromComment(const string comment, string &clusterCode) const;
    string NormalizeClusterCode(const string clusterCode) const;
    double EstimatePositionRiskPercent(const ulong ticket) const;
    
    // Correlation calculations
    double CalculateSymbolCorrelation(const string symbol1Param, const string symbol2Param);
    double GetMaxCorrelationWithPortfolio(const string symbolParam);
    
    // Audit functions
    void WriteAuditLog(const string message);
    string FormatValidationMessage(const STradeValidationRequest &request, const SValidationResult &result);
    
    // Performance tracking
    void UpdatePerformanceMetrics(const ulong startTime);
};

//+------------------------------------------------------------------+
//| Portfolio helper implementations                                |
//+------------------------------------------------------------------+
double CRiskValidationGate::GetPortfolioRiskValue() const
{
    CPortfolioRiskManager* manager = m_portfolioRiskManager;
    if(manager == NULL)
        return 0.0;
    return (*manager).GetPortfolioRisk();
}

bool CRiskValidationGate::PortfolioAllowsTrade(const string symbolParam, const double lotSize) const
{
    CPortfolioRiskManager* manager = m_portfolioRiskManager;
    if(manager == NULL)
        return true;
    return (*manager).IsTradeAllowed(symbolParam, lotSize);
}

bool CRiskValidationGate::PortfolioCorrelationAllowed(const string symbolParam) const
{
    CPortfolioRiskManager* manager = m_portfolioRiskManager;
    if(manager == NULL)
        return true;
    return (*manager).CheckCorrelationLimits(symbolParam);
}

bool CRiskValidationGate::PortfolioEmergencyActive() const
{
    CPortfolioRiskManager* manager = m_portfolioRiskManager;
    if(manager == NULL)
        return false;
    return (*manager).IsEmergencyMode();
}

bool CRiskValidationGate::PortfolioHasUnprotectedPositions() const
{
    CPortfolioRiskManager* manager = m_portfolioRiskManager;
    if(manager == NULL)
        return false;
    return (*manager).HasUnprotectedPositions();
}

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CRiskValidationGate::CRiskValidationGate() : m_portfolioRiskManager(NULL),
                                           m_unifiedRiskManager(NULL),
                                           m_maxRiskPerTrade(2.0),
                                           m_maxPortfolioRisk(10.0),
                                           m_correlationThreshold(0.7),
                                           m_maxPositionsSameBase(3),
                                           m_emergencyRiskOverride(5.0),
                                           m_clusterGovernanceEnabled(true),
                                           m_clusterMutexEnabled(true),
                                           m_maxConcurrentPerCluster(3),
                                           m_maxClusterRiskPercent(5.0),
                                           m_maxFreeMarginUsage(0.8),
                                           m_minMarginLevel(200.0),
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
                                    const double correlationThreshold,
                                    const int maxPositionsSameBase,
                                    const double maxFreeMarginUsage,
                                    const double minMarginLevel)
{
    if(pPortfolioRiskManager == NULL)
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "RiskValidationGate", "Invalid portfolio risk manager pointer", 0);
        return false;
    }
    
    m_portfolioRiskManager = pPortfolioRiskManager;
    
    // Validate parameters
    if(maxRiskPerTrade <= 0 || maxRiskPerTrade > 100.0)
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "RiskValidationGate", "Invalid max risk per trade", 0);
        return false;
    }
    
    if(maxPortfolioRisk <= 0 || maxPortfolioRisk > 100.0)
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "RiskValidationGate", "Invalid max portfolio risk", 0);
        return false;
    }
    
    if(correlationThreshold < 0 || correlationThreshold > 1.0)
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "RiskValidationGate", "Invalid correlation threshold", 0);
        return false;
    }
    
    // Validate margin threshold parameters
    if(maxFreeMarginUsage <= 0 || maxFreeMarginUsage > 1.0)
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "RiskValidationGate", "Invalid max free margin usage", 0);
        return false;
    }
    
    if(minMarginLevel < 100.0 || minMarginLevel > 1000.0)
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "RiskValidationGate", "Invalid min margin level", 0);
        return false;
    }
    
    // Set parameters
    m_maxRiskPerTrade = maxRiskPerTrade;
    m_maxPortfolioRisk = maxPortfolioRisk;
    m_correlationThreshold = correlationThreshold;
    m_maxPositionsSameBase = maxPositionsSameBase;
    m_maxFreeMarginUsage = maxFreeMarginUsage;
    m_minMarginLevel = minMarginLevel;
    
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
    ulong startTimeParam = GetMicrosecondCount();
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

    // 4. Validate cluster governance (strategy cluster mutex + cap)
    if(!ValidateClusterGovernance(request, tradeRisk, validationMessage))
    {
        result.message = "Cluster governance validation failed: " + validationMessage;
        result.severity = ERROR_LEVEL_WARNING;
        m_rejectedCount++;
        LogValidationResult(request, result);
        return result;
    }
    
    // 5. Validate correlation limits
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
    
    // 6. Validate margin requirements
    if(!ValidateMarginRequirements(request, validationMessage))
    {
        result.message = "Margin validation failed: " + validationMessage;
        result.severity = ERROR_LEVEL_ERROR;
        m_rejectedCount++;
        LogValidationResult(request, result);
        return result;
    }
    
    // 7. Validate account health
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
        // On small accounts, the calculated lot may be below broker minimum.
        // If the lot is at least 10% of minLot, allow a round-up rather than
        // rejecting outright. The PositionSizer will handle the risk assessment.
        // This prevents the validation gate from being a hard blocker for small accounts.
        if(request.lotSize >= minLot * 0.1)
        {
            // Don't reject — the caller (UnifiedRiskManager) will re-calculate
            // with the min lot and assess whether the risk is acceptable
        }
        else
        {
            message = "Lot size below minimum: " + DoubleToString(request.lotSize, 3) + " < " + DoubleToString(minLot, 3);
            return false;
        }
    }
    
    if(request.lotSize > maxLot)
    {
        message = "Lot size above maximum: " + DoubleToString(request.lotSize, 3) + " > " + DoubleToString(maxLot, 3);
        return false;
    }
    
    // Validate stop loss
    if(request.stopLossPips <= 0)
    {
        PrintFormat("[RISK-GATE] Rejected %s %s: Missing stop loss (strategy=%s, SL=%.1f pips)",
                    request.symbol, EnumToString(request.orderType), request.strategy, request.stopLossPips);
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
    
    // Convert to percentage using equity-aware denominator for stress-consistent risk sizing.
    double accountBalanceLocal = AccountInfoDouble(ACCOUNT_BALANCE);
    double accountEquityLocal = AccountInfoDouble(ACCOUNT_EQUITY);
    double riskDenominator = 0.0;
    
    // Handle negative balance/equity scenarios (margin call, etc.)
    if(accountBalanceLocal <= 0.0 && accountEquityLocal <= 0.0)
    {
        message = "Account in critical state - negative balance and equity";
        return false;
    }
    
    if(accountBalanceLocal > 0.0 && accountEquityLocal > 0.0)
        riskDenominator = MathMin(accountBalanceLocal, accountEquityLocal);
    else if(accountBalanceLocal > 0.0)
        riskDenominator = accountBalanceLocal;
    else
        riskDenominator = accountEquityLocal;

    if(riskDenominator <= 0.0)
    {
        message = "Invalid account risk denominator";
        return false;
    }
    
    riskPercent = (tradeRisk / riskDenominator) * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale
    
    // Check against maximum risk per trade
    if(riskPercent > m_maxRiskPerTrade)
    {
        message = StringFormat("Risk %.2f%% exceeds maximum %.2f%%", riskPercent, m_maxRiskPerTrade);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate portfolio risk                                        |
//+------------------------------------------------------------------+
bool CRiskValidationGate::ValidatePortfolioRisk(const STradeValidationRequest &request, const double tradeRiskPercent, string &message)
{
    CPortfolioRiskManager* manager = m_portfolioRiskManager;

    if(CheckPointer(manager) == POINTER_INVALID)
    {
        message = "Portfolio risk manager not available";
        return false;
    }

    if(PortfolioHasUnprotectedPositions())
    {
        message = "Open position without protective stop-loss detected";
        return false;
    }

    double currentRisk = (*manager).GetPortfolioRisk();
    double totalRisk = currentRisk + tradeRiskPercent;

    if(totalRisk > m_maxPortfolioRisk)
    {
        message = StringFormat("Total portfolio risk %.2f%% would exceed maximum %.2f%%", totalRisk, m_maxPortfolioRisk);
        return false;
    }

    if(!(*manager).IsTradeAllowed(request.symbol, request.lotSize, request.stopLossPips))
    {
        string portfolioReason = (*manager).GetLastBlockReason();
        message = (portfolioReason != "") ? portfolioReason : "Trade blocked by portfolio risk manager";
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Validate correlation limits                                    |
//+------------------------------------------------------------------+
bool CRiskValidationGate::ValidateCorrelationLimits(const STradeValidationRequest &request, string &message, double &correlationRisk)
{
    // Check same base currency limit
    int sameBaseCount = 0;
    string symbolBase = StringSubstr(request.symbol, 0, 3);
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            string posSymbol = PositionGetString(POSITION_SYMBOL);
            if(StringFind(posSymbol, symbolBase) >= 0)
                sameBaseCount++;
        }
    }
    
    if(sameBaseCount >= m_maxPositionsSameBase)
    {
        message = StringFormat("Too many positions on base %s (>= %d)", symbolBase, m_maxPositionsSameBase);
        correlationRisk = 1.0;
        return false;
    }

    correlationRisk = CalculateCorrelationRisk(request.symbol);

    if(correlationRisk > m_correlationThreshold)
    {
        message = StringFormat("Correlation risk %.2f exceeds threshold %.2f", correlationRisk, m_correlationThreshold);
        return false;
    }

    if(CheckPointer(m_portfolioRiskManager) != POINTER_INVALID)
    {
        CPortfolioRiskManager* manager = m_portfolioRiskManager;
        if(!(*manager).CheckCorrelationLimits(request.symbol))
        {
            string correlationReason = (*manager).GetLastBlockReason();
            message = (correlationReason != "") ? correlationReason : "Correlation limit exceeded";
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
    
    if(marginRequired > freeMargin * m_maxFreeMarginUsage) // Use configurable max free margin usage
    {
        message = StringFormat("Insufficient margin: required %.2f, available %.2f (threshold: %.0f%%)", 
                             marginRequired, freeMargin, m_maxFreeMarginUsage * 100.0);
        return false;
    }
    
    // Check margin level after trade
    double currentMarginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
    if(currentMarginLevel > 0 && currentMarginLevel < m_minMarginLevel)
    {
        message = StringFormat("Margin level too low: %.2f%% (threshold: %.0f%%)", 
                             currentMarginLevel, m_minMarginLevel);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Validate account health                                        |
//| Drawdown authority delegated to CUnifiedRiskManager (Phase 2.1) |
//+------------------------------------------------------------------+
bool CRiskValidationGate::ValidateAccountHealth(const STradeValidationRequest &request, string &message)
{
    double accountBalanceLocal2 = AccountInfoDouble(ACCOUNT_BALANCE);
    if(accountBalanceLocal2 < MIN_ACCOUNT_BALANCE)
    {
        message = StringFormat("Account balance too low: %.2f", accountBalanceLocal2);
        return false;
    }

    // Delegate drawdown check to CUnifiedRiskManager — single source of truth
    if(CheckPointer(m_unifiedRiskManager) != POINTER_INVALID)
    {
        SDrawdownState ddState = m_unifiedRiskManager.GetDrawdownState();
        if(ddState.isCriticalActive)
        {
            message = StringFormat("Drawdown critical: %.2f%% — trading halted by unified risk manager",
                                   ddState.currentDrawdownPct);
            return false;
        }
    }
    else
    {
        // Fallback: independent calculation only when unified manager is unavailable
        double accountEquityLocal = AccountInfoDouble(ACCOUNT_EQUITY);
        double drawdown = 0.0;
        if(accountBalanceLocal2 > 0)
            drawdown = ((accountBalanceLocal2 - accountEquityLocal) / accountBalanceLocal2) * 100.0;

        if(drawdown > DRAWDOWN_CRITICAL)
        {
            message = StringFormat("Drawdown too high: %.2f%% (fallback — unified manager not linked)", drawdown);
            return false;
        }
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
double CRiskValidationGate::CalculateTradeRisk(const string symbolParam, double lotSize, double stopLossPips) const
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
void CRiskValidationGate::EnableAuditLogging(const bool enabled, const string logFile)
{
    m_auditLogging = enabled;
    m_auditLogFile = logFile;
    
    if(enabled)
    {
        WriteAuditLog("Audit logging enabled");
    }
}

void CRiskValidationGate::ConfigureClusterGovernance(const bool enabled,
                                                     const int maxConcurrentPerCluster,
                                                     const double maxClusterRiskPercent,
                                                     const bool enableMutex)
{
    m_clusterGovernanceEnabled = enabled;
    m_clusterMutexEnabled = enableMutex;
    m_maxConcurrentPerCluster = MathMax(1, maxConcurrentPerCluster);
    m_maxClusterRiskPercent = MathMax(0.1, maxClusterRiskPercent);

    PrintFormat("[RISK-CLUSTER] governance=%s | mutex=%s | max_positions=%d | max_risk=%.2f%%",
                m_clusterGovernanceEnabled ? "enabled" : "disabled",
                m_clusterMutexEnabled ? "enabled" : "disabled",
                m_maxConcurrentPerCluster,
                m_maxClusterRiskPercent);
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
        approvalRate = (double)approved / total * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale
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
string CRiskValidationGate::NormalizeClusterCode(const string clusterCode) const
{
    string code = clusterCode;
    StringTrimLeft(code);
    StringTrimRight(code);
    StringToUpper(code);

    if(StringLen(code) <= 0)
        return "N";

    string first = StringSubstr(code, 0, 1);
    if(first == "T" || first == "R" || first == "S" || first == "N")
        return first;

    if(StringFind(code, "TREND") >= 0)
        return "T";
    if(StringFind(code, "MEAN") >= 0 || StringFind(code, "REVERSION") >= 0)
        return "R";
    if(StringFind(code, "STRUCTURE") >= 0)
        return "S";

    return "N";
}

bool CRiskValidationGate::ParseClusterCodeFromComment(const string comment, string &clusterCode) const
{
    clusterCode = "N";
    int marker = StringFind(comment, "K:");
    if(marker < 0 || (marker + 2) >= StringLen(comment))
        return false;

    clusterCode = NormalizeClusterCode(StringSubstr(comment, marker + 2, 1));
    return true;
}

double CRiskValidationGate::EstimatePositionRiskPercent(const ulong ticket) const
{
    if(ticket == 0 || !PositionSelectByTicket(ticket))
        return 0.0;

    string symbol = PositionGetString(POSITION_SYMBOL);
    double volume = PositionGetDouble(POSITION_VOLUME);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double stopLoss = PositionGetDouble(POSITION_SL);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    if(point <= 0.0)
        point = 0.00001;

    if(stopLoss <= 0.0 || openPrice <= 0.0 || volume <= 0.0)
        return m_maxRiskPerTrade;

    double slPoints = MathAbs(openPrice - stopLoss) / point;
    if(slPoints <= 0.0)
        return m_maxRiskPerTrade;

    double riskAmount = CalculateTradeRisk(symbol, volume, slPoints);
    if(riskAmount <= 0.0)
        return m_maxRiskPerTrade;

    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double denominator = 0.0;
    if(balance > 0.0 && equity > 0.0)
        denominator = MathMin(balance, equity);
    else
        denominator = MathMax(balance, equity);

    if(denominator <= 0.0)
        return m_maxRiskPerTrade;

    return (riskAmount / denominator) * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale
}

bool CRiskValidationGate::ValidateClusterGovernance(const STradeValidationRequest &request,
                                                    const double tradeRiskPercent,
                                                    string &message)
{
    if(!m_clusterGovernanceEnabled)
        return true;

    string requestClusterCode = NormalizeClusterCode(request.clusterCode);
    if(requestClusterCode == "N")
        requestClusterCode = NormalizeClusterCode(request.strategyCluster);

    if(requestClusterCode == "N")
        return true;

    int clusterOpenPositions = 0;
    double clusterOpenRiskPercent = 0.0;

    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

        string existingSymbol = PositionGetString(POSITION_SYMBOL);
        ENUM_POSITION_TYPE existingType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        string existingComment = PositionGetString(POSITION_COMMENT);
        string existingClusterCode = "N";
        ParseClusterCodeFromComment(existingComment, existingClusterCode);
        existingClusterCode = NormalizeClusterCode(existingClusterCode);

        if(existingClusterCode == "N" && existingSymbol == request.symbol)
            existingClusterCode = requestClusterCode;

        if(m_clusterMutexEnabled && existingSymbol == request.symbol)
        {
            bool oppositeDirection = ((request.orderType == ORDER_TYPE_BUY && existingType == POSITION_TYPE_SELL) ||
                                      (request.orderType == ORDER_TYPE_SELL && existingType == POSITION_TYPE_BUY));
            if(oppositeDirection &&
               (existingClusterCode == "N" || existingClusterCode != requestClusterCode))
            {
                message = StringFormat("Opposing same-symbol cluster conflict (request=%s existing=%s ticket=%I64u)",
                                       requestClusterCode, existingClusterCode, ticket);
                PrintFormat("[RISK-MUTEX-BLOCK] symbol=%s | request_cluster=%s | existing_cluster=%s | request_side=%s | existing_side=%s | ticket=%I64u",
                            request.symbol,
                            requestClusterCode,
                            existingClusterCode,
                            EnumToString(request.orderType),
                            EnumToString(existingType),
                            ticket);
                return false;
            }
        }

        if(existingClusterCode == requestClusterCode)
        {
            clusterOpenPositions++;
            clusterOpenRiskPercent += EstimatePositionRiskPercent(ticket);
        }
    }

    int projectedPositions = clusterOpenPositions + 1;
    double projectedRisk = clusterOpenRiskPercent + MathMax(0.0, tradeRiskPercent);

    PrintFormat("[RISK-CLUSTER] cluster=%s | open_positions=%d | projected_positions=%d | open_risk=%.2f%% | projected_risk=%.2f%% | caps=%d/%.2f%%",
                requestClusterCode,
                clusterOpenPositions,
                projectedPositions,
                clusterOpenRiskPercent,
                projectedRisk,
                m_maxConcurrentPerCluster,
                m_maxClusterRiskPercent);

    if(projectedPositions > m_maxConcurrentPerCluster)
    {
        message = StringFormat("Cluster position cap exceeded (%d > %d) for cluster %s",
                               projectedPositions, m_maxConcurrentPerCluster, requestClusterCode);
        return false;
    }

    if(projectedRisk > m_maxClusterRiskPercent)
    {
        message = StringFormat("Cluster risk cap exceeded (%.2f%% > %.2f%%) for cluster %s",
                               projectedRisk, m_maxClusterRiskPercent, requestClusterCode);
        return false;
    }

    return true;
}

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
//| Calculate symbol correlation (Phase 2.2: delegates to engine)    |
//+------------------------------------------------------------------+
double CRiskValidationGate::CalculateSymbolCorrelation(const string symbol1, const string symbol2)
{
    // Delegate to unified correlation engine via portfolio risk manager
    if(CheckPointer(m_portfolioRiskManager) != POINTER_INVALID)
    {
        CCorrelationEngine* engine = m_portfolioRiskManager.GetCorrelationEngine();
        if(engine != NULL)
            return engine.GetCorrelation(symbol1, symbol2);
    }

    // Fallback: conservative return when engine unavailable
    return 1.0;
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
    string clusterCode = NormalizeClusterCode(request.clusterCode);
    return StringFormat("VALIDATION: %s %s %.3f lots | %s | Role=%s | Cluster=%s(%s) | Risk: %.2f%% | Portfolio: %.2f%% | Correlation: %.2f",
                       request.symbol,
                       EnumToString(request.orderType),
                       request.lotSize,
                       result.approved ? "APPROVED" : "REJECTED",
                       request.strategyRole,
                       request.strategyCluster,
                       clusterCode,
                       result.riskPercent,
                       result.portfolioRisk,
                       result.correlationRisk);
}

//+------------------------------------------------------------------+
//| Update performance metrics                                     |
//+------------------------------------------------------------------+
void CRiskValidationGate::UpdatePerformanceMetrics(const ulong startTimeParam)
{
    ulong endTime = GetMicrosecondCount();
    double validationTime = 0.0;
    if(endTime >= startTimeParam)
        validationTime = (double)(endTime - startTimeParam) / 1000.0; // microseconds -> milliseconds
    
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

