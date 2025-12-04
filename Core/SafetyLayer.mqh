//+------------------------------------------------------------------+
//| Emergency Safety Layer - Critical Account Protection           |
//| Implements kill switches and emergency protection protocols    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_SAFETY_LAYER_MQH
#define CORE_SAFETY_LAYER_MQH

#include "Enums.mqh"
#include "ErrorHandling.mqh"

//+------------------------------------------------------------------+
//| Safety Status Enumeration                                      |
//+------------------------------------------------------------------+
enum ENUM_SAFETY_STATUS
{
    SAFETY_STATUS_NORMAL = 0,      // Normal operation
    SAFETY_STATUS_WARNING = 1,     // Warning level - reduce risk
    SAFETY_STATUS_CRITICAL = 2,    // Critical level - emergency mode
    SAFETY_STATUS_EMERGENCY = 3    // Emergency - halt all trading
};

//+------------------------------------------------------------------+
//| Account Health Metrics Structure                               |
//+------------------------------------------------------------------+
struct SAccountHealth
{
    double currentBalance;         // Current account balance
    double currentEquity;          // Current account equity
    double drawdownPercent;        // Current drawdown percentage
    double marginLevel;            // Current margin level
    double freeMargin;             // Available free margin
    int totalPositions;            // Total open positions
    double totalRisk;              // Total portfolio risk
    ENUM_SAFETY_STATUS status;     // Current safety status
    datetime lastUpdate;           // Last health check time
    bool emergencyTriggered;       // Emergency flag
};

//+------------------------------------------------------------------+
//| Safety Layer Class                                            |
//+------------------------------------------------------------------+
class CSafetyLayer : public CEnhancedErrorHandler
{
private:
    // Safety parameters
    double m_emergencyDrawdownThreshold;   // Emergency drawdown threshold (20%)
    double m_warningDrawdownThreshold;     // Warning drawdown threshold (10%)
    double m_minAccountBalance;            // Minimum account balance ($50)
    double m_maxLotSizeSmallAccount;       // Max lot size for small accounts (0.1)
    double m_smallAccountThreshold;        // Small account threshold ($1000)
    double m_maxRiskPerTrade;              // Maximum risk per trade (2%)
    double m_emergencyRiskOverride;        // Emergency risk override (5%)
    
    // Health monitoring
    SAccountHealth m_accountHealth;
    datetime m_lastHealthCheck;
    int m_healthCheckInterval;             // Health check interval (30 seconds)
    
    // Emergency state
    bool m_safetyEmergencyMode;
    bool m_killSwitchActivated;
    string m_emergencyReason;
    datetime m_emergencyTime;
    
    // Position monitoring
    datetime m_lastPositionCheck;
    int m_positionCheckInterval;
    // Logging
    bool m_safetyLoggingEnabled;
    string m_safetyLogFile;            // Position check interval (5 seconds)
    
public:
    // Constructor
    CSafetyLayer(void);
    
    // Destructor
    ~CSafetyLayer(void);
    
    // Initialize safety layer
    bool Initialize(const double emergencyDrawdown = 20.0,
                   const double warningDrawdown = 10.0,
                   const double minBalance = 50.0);
    
    // Main safety check - call this frequently
    bool PerformSafetyCheck(void);
    
    // Validate trade request before execution
    bool ValidateTradeRequest(const string symbol, 
                             const ENUM_ORDER_TYPE orderType,
                             const double lotSize,
                             const double stopLoss,
                             string &validationMessage);
    
    // Apply emergency position size caps
    double ApplyPositionSizeCaps(const string symbol, 
                                const double proposedLotSize,
                                const double accountBalance);
    
    // Check if trading is allowed
    bool IsTradingAllowed(void) const;
    
    // Get current safety status
    ENUM_SAFETY_STATUS GetSafetyStatus(void) const { return m_accountHealth.status; }
    
    // Get account health metrics
    SAccountHealth GetAccountHealth(void) const { return m_accountHealth; }
    
    // Emergency kill switch activation
    void ActivateKillSwitch(const string reason);
    
    // Check if kill switch is active
    bool IsKillSwitchActive(void) const { return m_killSwitchActivated; }
    
    // Get emergency reason
    string GetEmergencyReason(void) const { return m_emergencyReason; }
    
    // Force emergency EA removal
    void ForceEARemoval(const string reason);
    
    // Update account health metrics
    void UpdateAccountHealth(void);
    
    // Check position size limits
    bool CheckPositionSizeLimits(const string symbol, const double lotSize);
    
    // Monitor existing positions for safety
    void MonitorExistingPositions(void);
    
    // Calculate current portfolio risk
    double CalculateCurrentPortfolioRisk(void);
    
    // Enable/disable logging
    void SetLogging(const bool enabled, const string logFile = "SafetyLayer.log");
    
private:
    // Internal safety checks
    bool CheckDrawdownLimits(void);
    bool CheckAccountBalance(void);
    bool CheckMarginLevels(void);
    bool CheckPositionLimits(void);
    bool CheckRiskLimits(void);
    
    // Emergency procedures
    void TriggerEmergencyMode(const string reason);
    void CloseAllPositions(const string reason);
    void SendEmergencyAlert(const string message);
    
    // Logging functions
    void LogSafetyEvent(const ENUM_ERROR_SEVERITY level, const string message);
    void LogAccountHealth(void);
    
    // Utility functions
    double CalculateDrawdown(const double balance, const double equity);
    bool IsSmallAccount(const double balance);
    string SafetyStatusToString(const ENUM_SAFETY_STATUS status);
};

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CSafetyLayer::CSafetyLayer(void) : m_emergencyDrawdownThreshold(20.0),
                                   m_warningDrawdownThreshold(10.0),
                                   m_minAccountBalance(50.0),
                                   m_maxLotSizeSmallAccount(0.1),
                                   m_smallAccountThreshold(1000.0),
                                   m_maxRiskPerTrade(2.0),
                                   m_emergencyRiskOverride(5.0),
                                   m_lastHealthCheck(0),
                                   m_healthCheckInterval(30),
                                   m_safetyEmergencyMode(false),
                                   m_killSwitchActivated(false),
                                   m_emergencyReason(""),
                                   m_emergencyTime(0),
                                   m_lastPositionCheck(0),
                                   m_positionCheckInterval(5),
                                   m_safetyLoggingEnabled(true),
                                   m_safetyLogFile("SafetyLayer.log")
{
    // Initialize account health structure
    ZeroMemory(m_accountHealth);
    m_accountHealth.status = SAFETY_STATUS_NORMAL;
    m_accountHealth.lastUpdate = 0;
    m_accountHealth.emergencyTriggered = false;
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CSafetyLayer::~CSafetyLayer(void)
{
    if(m_safetyLoggingEnabled)
    {
        LogSafetyEvent(ERROR_INFO, "Safety Layer shutdown");
    }
}

//+------------------------------------------------------------------+
//| Initialize safety layer                                        |
//+------------------------------------------------------------------+
bool CSafetyLayer::Initialize(const double emergencyDrawdown = 20.0,
                             const double warningDrawdown = 10.0,
                             const double minBalance = 50.0)
{
    // Validate parameters
    if(emergencyDrawdown <= 0 || emergencyDrawdown > 50.0)
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "SafetyLayer", 
                               "Invalid emergency drawdown threshold");
        return false;
    }
    
    if(warningDrawdown <= 0 || warningDrawdown >= emergencyDrawdown)
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "SafetyLayer", 
                               "Invalid warning drawdown threshold");
        return false;
    }
    
    if(minBalance <= 0)
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "SafetyLayer", 
                               "Invalid minimum balance");
        return false;
    }
    
    // Set parameters
    m_emergencyDrawdownThreshold = emergencyDrawdown;
    m_warningDrawdownThreshold = warningDrawdown;
    m_minAccountBalance = minBalance;
    
    // Perform initial safety check
    UpdateAccountHealth();
    
    // Check if account is already in emergency state
    if(m_accountHealth.drawdownPercent > m_emergencyDrawdownThreshold)
    {
        ActivateKillSwitch("Initial drawdown check failed");
        return false;
    }
    
    if(m_accountHealth.currentBalance < m_minAccountBalance)
    {
        ActivateKillSwitch("Account balance below minimum threshold");
        return false;
    }
    
    LogSafetyEvent(ERROR_INFO, 
                   StringFormat("Safety Layer initialized - Emergency: %.1f%%, Warning: %.1f%%, Min Balance: $%.2f",
                               emergencyDrawdown, warningDrawdown, minBalance));
    
    return true;
}

//+------------------------------------------------------------------+
//| Main safety check - call this frequently                       |
//+------------------------------------------------------------------+
bool CSafetyLayer::PerformSafetyCheck(void)
{
    datetime currentTimeParam = TimeCurrent();
    
    // Check if it's time for health check
    if(currentTimeParam - m_lastHealthCheck < m_healthCheckInterval)
        return !m_killSwitchActivated;
    
    // Update account health
    UpdateAccountHealth();
    m_lastHealthCheck = currentTimeParam;
    
    // Perform all safety checks
    bool safetyPassed = true;
    
    if(!CheckDrawdownLimits())
        safetyPassed = false;
    
    if(!CheckAccountBalance())
        safetyPassed = false;
    
    if(!CheckMarginLevels())
        safetyPassed = false;
    
    if(!CheckPositionLimits())
        safetyPassed = false;
    
    if(!CheckRiskLimits())
        safetyPassed = false;
    
    // Monitor existing positions
    if(currentTimeParam - m_lastPositionCheck >= m_positionCheckInterval)
    {
        MonitorExistingPositions();
        m_lastPositionCheck = currentTimeParam;
    }
    
    // Log health status periodically
    static datetime lastHealthLog = 0;
    if(currentTimeParam - lastHealthLog >= 300) // Log every 5 minutes
    {
        LogAccountHealth();
        lastHealthLog = currentTimeParam;
    }
    
    return safetyPassed && !m_killSwitchActivated;
}

//+------------------------------------------------------------------+
//| Validate trade request before execution                        |
//+------------------------------------------------------------------+
bool CSafetyLayer::ValidateTradeRequest(const string symbolParam,
                                       const ENUM_ORDER_TYPE orderType,
                                       const double lotSize,
                                       const double stopLoss,
                                       string &validationMessage)
{
    validationMessage = "";
    
    // Check if kill switch is active
    if(m_killSwitchActivated)
    {
        validationMessage = "Kill switch activated: " + m_emergencyReason;
        return false;
    }
    
    // Check if trading is allowed
    if(!IsTradingAllowed())
    {
        validationMessage = "Trading not allowed - Safety status: " + SafetyStatusToString(m_accountHealth.status);
        return false;
    }
    
    // Validate symbol
    if(StringLen(symbolParam) == 0)
    {
        validationMessage = "Invalid symbol";
        return false;
    }
    
    // Validate lot size
    if(lotSize <= 0)
    {
        validationMessage = "Invalid lot size: " + DoubleToString(lotSize, 2);
        return false;
    }
    
    // Check position size limits
    if(!CheckPositionSizeLimits(symbolParam, lotSize))
    {
        validationMessage = "Position size exceeds safety limits";
        return false;
    }
    
    // Apply position size caps
    double cappedLotSize = ApplyPositionSizeCaps(symbolParam, lotSize, m_accountHealth.currentBalance);
    if(cappedLotSize < lotSize)
    {
        validationMessage = StringFormat("Position size capped from %.2f to %.2f lots", lotSize, cappedLotSize);
        LogSafetyEvent(ERROR_WARNING, validationMessage);
        // This is a warning, not a failure
    }
    
    // Check portfolio risk
    double currentRisk = CalculateCurrentPortfolioRisk();
    if(currentRisk > m_emergencyRiskOverride)
    {
        validationMessage = StringFormat("Portfolio risk too high: %.2f%% > %.2f%%", currentRisk, m_emergencyRiskOverride);
        return false;
    }
    
    // Check margin requirements
    double marginRequired = SymbolInfoDouble(symbolParam, SYMBOL_MARGIN_INITIAL) * lotSize;
    if(marginRequired > m_accountHealth.freeMargin * 0.8)
    {
        validationMessage = "Insufficient margin for trade";
        return false;
    }
    
    // All checks passed
    return true;
}

//+------------------------------------------------------------------+
//| Apply emergency position size caps                             |
//+------------------------------------------------------------------+
double CSafetyLayer::ApplyPositionSizeCaps(const string symbolParam,
                                          const double proposedLotSize,
                                          const double accountBalanceParam)
{
    double cappedSize = proposedLotSize;
    
    // Apply small account caps
    if(IsSmallAccount(accountBalanceParam))
    {
        if(cappedSize > m_maxLotSizeSmallAccount)
        {
            cappedSize = m_maxLotSizeSmallAccount;
            LogSafetyEvent(ERROR_WARNING, 
                          StringFormat("Small account cap applied: %.2f -> %.2f lots", 
                                      proposedLotSize, cappedSize));
        }
    }
    
    // Apply emergency risk override
    double maxRiskAmount = m_accountHealth.currentBalance * (m_maxRiskPerTrade / 100.0);
    double tickValue = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_VALUE);
    double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
    
    if(tickValue > 0 && point > 0)
    {
        double riskPerLot = tickValue * (1.0 / point) * 100; // Assume 100 pip stop loss
        double maxLotsForRisk = maxRiskAmount / riskPerLot;
        
        if(cappedSize > maxLotsForRisk)
        {
            cappedSize = maxLotsForRisk;
            LogSafetyEvent(ERROR_WARNING, 
                          StringFormat("Risk cap applied: %.2f -> %.2f lots", 
                                      proposedLotSize, cappedSize));
        }
    }
    
    // Ensure minimum lot size
    double minLot = SymbolInfoDouble(symbolParam, SYMBOL_VOLUME_MIN);
    if(cappedSize < minLot)
        cappedSize = minLot;
    
    return cappedSize;
}

//| Check if trading is allowed                                    |
//+------------------------------------------------------------------+
bool CSafetyLayer::IsTradingAllowed(void) const
{
    if(m_killSwitchActivated)
        return false;
    
    if(m_accountHealth.status == SAFETY_STATUS_EMERGENCY)
        return false;
    
    // Check account trading permissions
    if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
        return false;
    
    // Check terminal trading permissions
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
        return false;
    
    // Check connection
    if(!TerminalInfoInteger(TERMINAL_CONNECTED))
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Emergency kill switch activation                               |
//+------------------------------------------------------------------+
void CSafetyLayer::ActivateKillSwitch(const string reason)
{
    if(m_killSwitchActivated)
        return; // Already activated
    
    m_killSwitchActivated = true;
    m_safetyEmergencyMode = true;
    m_emergencyReason = reason;
    m_emergencyTime = TimeCurrent();
    m_accountHealth.status = SAFETY_STATUS_EMERGENCY;
    m_accountHealth.emergencyTriggered = true;
    
    string alertMessage = "🚨 EMERGENCY KILL SWITCH ACTIVATED 🚨\nReason: " + reason;
    
    LogSafetyEvent(ERROR_CRITICAL, alertMessage);
    SendEmergencyAlert(alertMessage);
    
    // Close all positions immediately
    CloseAllPositions("Kill switch activated");
    
    // Force EA removal after a short delay
    ForceEARemoval(reason);
}

//+------------------------------------------------------------------+
//| Force emergency EA removal                                     |
//+------------------------------------------------------------------+
void CSafetyLayer::ForceEARemoval(const string reason)
{
    string finalMessage = "🚨 EMERGENCY EA REMOVAL 🚨\nReason: " + reason + 
                         "\nTime: " + TimeToString(TimeCurrent());
    
    LogSafetyEvent(ERROR_CRITICAL, finalMessage);
    Print(finalMessage);
    Alert(finalMessage);
    
    // Remove the EA
    ExpertRemove();
}

//+------------------------------------------------------------------+
//| Update account health metrics                                  |
//+------------------------------------------------------------------+
void CSafetyLayer::UpdateAccountHealth(void)
{
    m_accountHealth.currentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    m_accountHealth.currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    m_accountHealth.marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
    m_accountHealth.freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    m_accountHealth.totalPositions = PositionsTotal();
    m_accountHealth.drawdownPercent = CalculateDrawdown(m_accountHealth.currentBalance, 
                                                       m_accountHealth.currentEquity);
    m_accountHealth.totalRisk = CalculateCurrentPortfolioRisk();
    m_accountHealth.lastUpdate = TimeCurrent();
    
    // Update safety status
    if(m_accountHealth.drawdownPercent > m_emergencyDrawdownThreshold)
        m_accountHealth.status = SAFETY_STATUS_EMERGENCY;
    else if(m_accountHealth.drawdownPercent > m_warningDrawdownThreshold)
        m_accountHealth.status = SAFETY_STATUS_CRITICAL;
    else if(m_accountHealth.drawdownPercent > 5.0)
        m_accountHealth.status = SAFETY_STATUS_WARNING;
    else
        m_accountHealth.status = SAFETY_STATUS_NORMAL;
}

//+------------------------------------------------------------------+
//| Check position size limits                                     |
//+------------------------------------------------------------------+
bool CSafetyLayer::CheckPositionSizeLimits(const string symbolParam, const double lotSize)
{
    // Check against small account limits
    if(IsSmallAccount(m_accountHealth.currentBalance))
    {
        if(lotSize > m_maxLotSizeSmallAccount)
        {
            LogSafetyEvent(ERROR_WARNING,
                          StringFormat("Position size %.2f exceeds small account limit %.2f",
                                      lotSize, m_maxLotSizeSmallAccount));
            return false;
        }
    }
    
    // Check against symbol limits
    double maxLot = SymbolInfoDouble(symbolParam, SYMBOL_VOLUME_MAX);
    if(lotSize > maxLot)
    {
        LogSafetyEvent(ERROR_RECOVERABLE, 
                      StringFormat("Position size %.2f exceeds symbol maximum %.2f", 
                                  lotSize, maxLot));
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Monitor existing positions for safety                          |
//+------------------------------------------------------------------+
void CSafetyLayer::MonitorExistingPositions(void)
{
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            double positionProfit = PositionGetDouble(POSITION_PROFIT);
            double positionVolume = PositionGetDouble(POSITION_VOLUME);
            string positionSymbol = PositionGetString(POSITION_SYMBOL);
            
            // Check for oversized positions
            if(IsSmallAccount(m_accountHealth.currentBalance) && 
               positionVolume > m_maxLotSizeSmallAccount)
            {
                LogSafetyEvent(ERROR_CRITICAL, 
                              StringFormat("Oversized position detected: %s %.2f lots", 
                                          positionSymbol, positionVolume));
                
                // Close oversized position immediately
                CTrade tradeObject;
                if(tradeObject.PositionClose(PositionGetTicket(i)))
                {
                    LogSafetyEvent(ERROR_WARNING,
                                  StringFormat("Oversized position closed: %s", positionSymbol));
                }
            }
            
            // Check for excessive losses
            double lossPercent = (positionProfit / m_accountHealth.currentBalance) * 100.0;
            if(lossPercent < -m_maxRiskPerTrade)
            {
                LogSafetyEvent(ERROR_WARNING, 
                              StringFormat("Position with excessive loss: %s %.2f%%", 
                                          positionSymbol, lossPercent));
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate current portfolio risk                               |
//+------------------------------------------------------------------+
double CSafetyLayer::CalculateCurrentPortfolioRisk(void)
{
    double totalRisk = 0.0;
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            double positionRisk = MathAbs(PositionGetDouble(POSITION_PROFIT));
            totalRisk += positionRisk;
        }
    }
    
    if(m_accountHealth.currentBalance > 0)
        return (totalRisk / m_accountHealth.currentBalance) * 100.0;
    
    return 0.0;
}

//+------------------------------------------------------------------+
//| Internal safety checks                                         |
//+------------------------------------------------------------------+
bool CSafetyLayer::CheckDrawdownLimits(void)
{
    if(m_accountHealth.drawdownPercent > m_emergencyDrawdownThreshold)
    {
        ActivateKillSwitch(StringFormat("Emergency drawdown threshold exceeded: %.2f%%", 
                                       m_accountHealth.drawdownPercent));
        return false;
    }
    
    if(m_accountHealth.drawdownPercent > m_warningDrawdownThreshold)
    {
        LogSafetyEvent(ERROR_WARNING, 
                      StringFormat("Warning drawdown level reached: %.2f%%", 
                                  m_accountHealth.drawdownPercent));
    }
    
    return true;
}

bool CSafetyLayer::CheckAccountBalance(void)
{
    if(m_accountHealth.currentBalance < m_minAccountBalance)
    {
        ActivateKillSwitch(StringFormat("Account balance below minimum: $%.2f < $%.2f", 
                                       m_accountHealth.currentBalance, m_minAccountBalance));
        return false;
    }
    
    return true;
}

bool CSafetyLayer::CheckMarginLevels(void)
{
    if(m_accountHealth.marginLevel > 0 && m_accountHealth.marginLevel < 200.0)
    {
        LogSafetyEvent(ERROR_WARNING, 
                      StringFormat("Low margin level: %.2f%%", m_accountHealth.marginLevel));
        
        if(m_accountHealth.marginLevel < 100.0)
        {
            ActivateKillSwitch(StringFormat("Critical margin level: %.2f%%", 
                                           m_accountHealth.marginLevel));
            return false;
        }
    }
    
    return true;
}

bool CSafetyLayer::CheckPositionLimits(void)
{
    if(m_accountHealth.totalPositions > MAX_POSITIONS)
    {
        LogSafetyEvent(ERROR_WARNING, 
                      StringFormat("Too many positions: %d > %d", 
                                  m_accountHealth.totalPositions, MAX_POSITIONS));
        return false;
    }
    
    return true;
}

bool CSafetyLayer::CheckRiskLimits(void)
{
    if(m_accountHealth.totalRisk > MAX_TOTAL_RISK)
    {
        LogSafetyEvent(ERROR_CRITICAL, 
                      StringFormat("Total risk exceeded: %.2f%% > %.2f%%", 
                                  m_accountHealth.totalRisk, MAX_TOTAL_RISK));
        
        if(m_accountHealth.totalRisk > m_emergencyRiskOverride)
        {
            ActivateKillSwitch(StringFormat("Emergency risk threshold exceeded: %.2f%%", 
                                           m_accountHealth.totalRisk));
            return false;
        }
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Emergency procedures                                           |
//+------------------------------------------------------------------+
void CSafetyLayer::TriggerEmergencyMode(const string reason)
{
    m_safetyEmergencyMode = true;
    m_accountHealth.status = SAFETY_STATUS_EMERGENCY;
    
    LogSafetyEvent(ERROR_CRITICAL, "Emergency mode triggered: " + reason);
}

void CSafetyLayer::CloseAllPositions(const string reason)
{
    LogSafetyEvent(ERROR_CRITICAL, "Closing all positions: " + reason);
    
    CTrade tradeObject;
    int closedCount = 0;
    
    for(int i = PositionsTotal() - 1; i >= 0; i--)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            ulong ticket = PositionGetTicket(i);
            if(tradeObject.PositionClose(ticket))
            {
                closedCount++;
                LogSafetyEvent(ERROR_INFO, 
                              StringFormat("Position closed: %llu", ticket));
            }
            else
            {
                LogSafetyEvent(ERROR_RECOVERABLE, 
                              StringFormat("Failed to close position: %llu", ticket));
            }
        }
    }
    
    LogSafetyEvent(ERROR_INFO, 
                  StringFormat("Emergency closure completed: %d positions closed", closedCount));
}

void CSafetyLayer::SendEmergencyAlert(const string message)
{
    // Send alert to terminal
    Alert(message);
    
    // Print to log
    Print(message);
    
    // Send notification if possible
    SendNotification(message);
}

//+------------------------------------------------------------------+
//| Logging functions                                              |
//+------------------------------------------------------------------+
void CSafetyLayer::LogSafetyEvent(const ENUM_ERROR_SEVERITY level, const string message)
{
    if(!m_safetyLoggingEnabled)
        return;
    
    LogError(level, "SafetyLayer", message);
    
    // Also log to safety-specific file
    int handle = FileOpen(m_safetyLogFile, FILE_WRITE | FILE_READ | FILE_TXT);
    if(handle != INVALID_HANDLE)
    {
        FileSeek(handle, 0, SEEK_END);
        string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
        string levelStr = (level == ERROR_INFO) ? "INFO" : 
                         (level == ERROR_WARNING) ? "WARN" : 
                         (level == ERROR_RECOVERABLE) ? "ERROR" : "CRITICAL";
        
        FileWrite(handle, StringFormat("[%s] %s | %s", timestamp, levelStr, message));
        FileClose(handle);
    }
}

void CSafetyLayer::LogAccountHealth(void)
{
    string healthReport = StringFormat(
        "Account Health: Balance=$%.2f, Equity=$%.2f, Drawdown=%.2f%%, Margin=%.2f%%, Positions=%d, Risk=%.2f%%, Status=%s",
        m_accountHealth.currentBalance,
        m_accountHealth.currentEquity,
        m_accountHealth.drawdownPercent,
        m_accountHealth.marginLevel,
        m_accountHealth.totalPositions,
        m_accountHealth.totalRisk,
        SafetyStatusToString(m_accountHealth.status)
    );
    
    LogSafetyEvent(ERROR_INFO, healthReport);
}

//+------------------------------------------------------------------+
//| Utility functions                                             |
//+------------------------------------------------------------------+
double CSafetyLayer::CalculateDrawdown(const double balance, const double equity)
{
    if(balance <= 0)
        return 0.0;
    
    if(equity >= balance)
        return 0.0;
    
    return ((balance - equity) / balance) * 100.0;
}

bool CSafetyLayer::IsSmallAccount(const double balance)
{
    return balance < m_smallAccountThreshold;
}

string CSafetyLayer::SafetyStatusToString(const ENUM_SAFETY_STATUS status)
{
    switch(status)
    {
        case SAFETY_STATUS_NORMAL: return "NORMAL";
        case SAFETY_STATUS_WARNING: return "WARNING";
        case SAFETY_STATUS_CRITICAL: return "CRITICAL";
        case SAFETY_STATUS_EMERGENCY: return "EMERGENCY";
        default: return "UNKNOWN";
    }
}

void CSafetyLayer::SetLogging(const bool enabled, const string logFile = "SafetyLayer.log")
{
    m_safetyLoggingEnabled = enabled;
    m_safetyLogFile = logFile;
}

#endif // CORE_SAFETY_LAYER_MQH
