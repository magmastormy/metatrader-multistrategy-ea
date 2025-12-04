//+------------------------------------------------------------------+
//| System Health Monitor                                          |
//| Comprehensive health monitoring and alerting system           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_SYSTEM_HEALTH_MONITOR_MQH
#define CORE_SYSTEM_HEALTH_MONITOR_MQH

#include "Enums.mqh"
#include "ErrorHandling.mqh"

//+------------------------------------------------------------------+
//| Health Check Result Structure                                  |
//+------------------------------------------------------------------+
struct SHealthCheckResult
{
    string componentName;          // Component being checked
    bool isHealthy;                // Overall health status
    double healthScore;            // Health score (0-1)
    string statusMessage;          // Status description
    datetime lastCheck;            // Last check timestamp
    int checksPerformed;           // Total checks performed
    int failedChecks;              // Number of failed checks
    double averageResponseTime;    // Average response time in ms
    string lastError;              // Last error message
};

//+------------------------------------------------------------------+
//| Performance Metrics Structure                                  |
//+------------------------------------------------------------------+
struct SPerformanceMetrics
{
    double cpuUsage;               // CPU usage percentage
    double memoryUsage;            // Memory usage in MB
    int activeHandles;             // Number of active handles
    double averageLatency;         // Average operation latency
    int operationsPerSecond;       // Operations per second
    datetime lastUpdate;           // Last metrics update
};

//+------------------------------------------------------------------+
//| Alert Configuration Structure                                  |
//+------------------------------------------------------------------+
struct SAlertConfig
{
    bool enableAlerts;             // Enable/disable alerts
    double healthThreshold;        // Health score threshold for alerts
    int maxFailedChecks;           // Max failed checks before alert
    int alertCooldownSeconds;      // Cooldown between alerts
    bool sendEmailAlerts;          // Send email alerts
    bool sendPushNotifications;    // Send push notifications
    bool logToFile;                // Log alerts to file
};

//+------------------------------------------------------------------+
//| System Health Monitor Class                                   |
//+------------------------------------------------------------------+
class CSystemHealthMonitor
{
private:
    static SHealthCheckResult m_healthResults[];
    static int m_componentCount;
    static SPerformanceMetrics m_systemMetrics;
    static SAlertConfig m_alertConfig;
    static datetime m_lastSystemCheck;
    static datetime m_lastAlert[];
    static bool m_monitoringEnabled;
    static int m_checkInterval;
    static string m_alertLogFile;

public:
    // Constructor
    CSystemHealthMonitor(void);
    
    // Destructor
    ~CSystemHealthMonitor(void);
    
    // Initialize health monitoring system
    static bool Initialize(const int checkIntervalSeconds = 30);
    
    // Component registration and management
    static bool RegisterComponent(const string componentName, 
                                 const double healthThreshold = 0.7);
    static bool UnregisterComponent(const string componentName);
    
    // Health check operations
    static bool PerformHealthCheck(const string componentName);
    static void PerformSystemHealthCheck(void);
    static bool PerformAllHealthChecks(void);
    
    // Component-specific health checks
    static bool CheckAISystemHealth(void);
    static bool CheckRiskManagerHealth(void);
    static bool CheckStrategyManagerHealth(void);
    static bool CheckTradeManagerHealth(void);
    static bool CheckPositionSizerHealth(void);
    static bool CheckBrokerConnectionHealth(void);
    
    // Health status retrieval
    static SHealthCheckResult GetComponentHealth(const string componentName);
    static void GetAllHealthResults(SHealthCheckResult &results[], int &count);
    static double GetSystemHealthScore(void);
    static bool IsSystemHealthy(void);
    
    // Performance monitoring
    static void UpdatePerformanceMetrics(void);
    static SPerformanceMetrics GetPerformanceMetrics(void);
    static void ResetPerformanceCounters(void);
    
    // Automatic restart and recovery
    static bool AttemptComponentRestart(const string componentName);
    static bool AttemptSystemRecovery(void);
    static void EnableAutoRecovery(const bool enable = true);
    
    // Alert system
    static void ConfigureAlerts(const SAlertConfig &config);
    static void SendHealthAlert(const string componentName, const string message);
    static void CheckAndSendAlerts(void);
    
    // Dashboard and reporting
    static void GenerateHealthDashboard(string &dashboard);
    static void GenerateDetailedReport(string &report);
    static void LogHealthStatus(void);
    
    // Configuration
    static void SetMonitoringEnabled(const bool enabled);
    static void SetCheckInterval(const int intervalSeconds);
    static bool IsMonitoringEnabled(void) { return m_monitoringEnabled; }
    
    // Utility functions
    static string GetHealthStatusString(const double healthScore);
    static color GetHealthStatusColor(const double healthScore);
    
private:
    // Internal helper methods
    static int FindComponentIndex(const string componentName);
    static void UpdateComponentHealth(const string componentName, 
                                    const bool isHealthy, 
                                    const double healthScore,
                                    const string statusMessage = "");
    static bool ShouldSendAlert(const string componentName);
    static void LogAlert(const string componentName, const string message);
    static double CalculateHealthScore(const string componentName);
    static void CleanupOldData(void);
};

// Static member initialization
static SHealthCheckResult CSystemHealthMonitor::m_healthResults[];
static int CSystemHealthMonitor::m_componentCount = 0;
static SPerformanceMetrics CSystemHealthMonitor::m_systemMetrics;
static SAlertConfig CSystemHealthMonitor::m_alertConfig = {true, 0.7, 3, 300, false, true, true};
static datetime CSystemHealthMonitor::m_lastSystemCheck = 0;
static datetime CSystemHealthMonitor::m_lastAlert[];
static bool CSystemHealthMonitor::m_monitoringEnabled = false;
static int CSystemHealthMonitor::m_checkInterval = 30;
static string CSystemHealthMonitor::m_alertLogFile = "health_alerts.log";

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CSystemHealthMonitor::CSystemHealthMonitor(void)
{
    // Constructor implementation
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CSystemHealthMonitor::~CSystemHealthMonitor(void)
{
    if(m_monitoringEnabled)
    {
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            localErrorHandler.LogError(ERROR_INFO, "HealthMonitor",
                                       "Health monitoring system shutdown");
        }
    }
}

//+------------------------------------------------------------------+
//| Initialize health monitoring system                            |
//+------------------------------------------------------------------+
bool CSystemHealthMonitor::Initialize(const int checkIntervalSeconds = 30)
{
    m_checkInterval = checkIntervalSeconds;
    m_monitoringEnabled = true;
    m_componentCount = 0;
    
    // Initialize arrays
    ArrayResize(m_healthResults, 20); // Initial capacity
    ArrayResize(m_lastAlert, 20);
    ArrayInitialize(m_lastAlert, 0);
    
    // Initialize system metrics
    m_systemMetrics.cpuUsage = 0.0;
    m_systemMetrics.memoryUsage = 0.0;
    m_systemMetrics.activeHandles = 0;
    m_systemMetrics.averageLatency = 0.0;
    m_systemMetrics.operationsPerSecond = 0;
    m_systemMetrics.lastUpdate = TimeCurrent();
    
    // Register core components
    RegisterComponent("AISystem", 0.8);
    RegisterComponent("RiskManager", 0.9);
    RegisterComponent("StrategyManager", 0.8);
    RegisterComponent("TradeManager", 0.9);
    RegisterComponent("PositionSizer", 0.8);
    RegisterComponent("BrokerConnection", 0.9);
    
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_INFO, "HealthMonitor", 
                                   "Health monitoring system initialized successfully");
    }
    
    return true;
}//+-------
-----------------------------------------------------------+
//| Register component for health monitoring                       |
//+------------------------------------------------------------------+
bool CSystemHealthMonitor::RegisterComponent(const string componentName, 
                                            const double healthThreshold = 0.7)
{
    // Check if component already exists
    int index = FindComponentIndex(componentName);
    if(index >= 0) return true; // Already registered
    
    // Resize arrays if needed
    if(m_componentCount >= ArraySize(m_healthResults))
    {
        ArrayResize(m_healthResults, ArraySize(m_healthResults) + 10);
        ArrayResize(m_lastAlert, ArraySize(m_lastAlert) + 10);
    }
    
    // Initialize component health result
    m_healthResults[m_componentCount].componentName = componentName;
    m_healthResults[m_componentCount].isHealthy = true;
    m_healthResults[m_componentCount].healthScore = 1.0;
    m_healthResults[m_componentCount].statusMessage = "Component registered";
    m_healthResults[m_componentCount].lastCheck = TimeCurrent();
    m_healthResults[m_componentCount].checksPerformed = 0;
    m_healthResults[m_componentCount].failedChecks = 0;
    m_healthResults[m_componentCount].averageResponseTime = 0.0;
    m_healthResults[m_componentCount].lastError = "";
    
    m_lastAlert[m_componentCount] = 0;
    m_componentCount++;
    
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_INFO, "HealthMonitor", 
                                   "Component registered for monitoring: " + componentName);
    }
    return true;
}

//+------------------------------------------------------------------+
//| Perform health check for specific component                   |
//+------------------------------------------------------------------+
bool CSystemHealthMonitor::PerformHealthCheck(const string componentName)
{
    if(!m_monitoringEnabled) return true;
    
    datetime startTime = GetMicrosecondCount();
    bool healthCheckResult = false;
    string statusMessage = "";
    
    // Perform component-specific health check
    if(componentName == "AISystem")
        healthCheckResult = CheckAISystemHealth();
    else if(componentName == "RiskManager")
        healthCheckResult = CheckRiskManagerHealth();
    else if(componentName == "StrategyManager")
        healthCheckResult = CheckStrategyManagerHealth();
    else if(componentName == "TradeManager")
        healthCheckResult = CheckTradeManagerHealth();
    else if(componentName == "PositionSizer")
        healthCheckResult = CheckPositionSizerHealth();
    else if(componentName == "BrokerConnection")
        healthCheckResult = CheckBrokerConnectionHealth();
    else
    {
        // Generic health check
        healthCheckResult = true;
        statusMessage = "Generic health check passed";
    }
    
    // Calculate response time
    double responseTime = (GetMicrosecondCount() - startTime) / 1000.0; // Convert to milliseconds
    
    // Update component health
    double healthScore = healthCheckResult ? 1.0 : 0.0;
    if(statusMessage == "")
        statusMessage = healthCheckResult ? "Health check passed" : "Health check failed";
    
    UpdateComponentHealth(componentName, healthCheckResult, healthScore, statusMessage);
    
    // Update response time
    int index = FindComponentIndex(componentName);
    if(index >= 0)
    {
        m_healthResults[index].checksPerformed++;
        if(!healthCheckResult)
            m_healthResults[index].failedChecks++;
        
        // Update average response time
        if(m_healthResults[index].checksPerformed == 1)
            m_healthResults[index].averageResponseTime = responseTime;
        else
            m_healthResults[index].averageResponseTime = 
                (m_healthResults[index].averageResponseTime * (m_healthResults[index].checksPerformed - 1) + responseTime) / 
                m_healthResults[index].checksPerformed;
    }
    
    return healthCheckResult;
}

//+------------------------------------------------------------------+
//| Perform system-wide health check                              |
//+------------------------------------------------------------------+
void CSystemHealthMonitor::PerformSystemHealthCheck(void)
{
    if(!m_monitoringEnabled) return;
    
    m_lastSystemCheck = TimeCurrent();
    
    // Update performance metrics
    UpdatePerformanceMetrics();
    
    // Check all registered components
    PerformAllHealthChecks();
    
    // Check and send alerts if needed
    CheckAndSendAlerts();
    
    // Log system health status
    LogHealthStatus();
    
    // Cleanup old data
    CleanupOldData();
}

//+------------------------------------------------------------------+
//| Perform health checks for all components                      |
//+------------------------------------------------------------------+
bool CSystemHealthMonitor::PerformAllHealthChecks(void)
{
    bool allHealthy = true;
    
    for(int i = 0; i < m_componentCount; i++)
    {
        bool componentHealthy = PerformHealthCheck(m_healthResults[i].componentName);
        if(!componentHealthy)
            allHealthy = false;
    }
    
    return allHealthy;
}

//+------------------------------------------------------------------+
//| Check AI System health                                        |
//+------------------------------------------------------------------+
bool CSystemHealthMonitor::CheckAISystemHealth(void)
{
    // Check if AI components are responding
    ENUM_COMPONENT_STATUS aiStatus = CEnhancedErrorHandler::GetComponentStatus("AISystem");
    
    if(aiStatus == COMPONENT_FAILED || aiStatus == COMPONENT_DISABLED)
        return false;
    
    // Additional AI-specific checks could be added here
    // For example: check model loading, prediction accuracy, etc.
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Risk Manager health                                     |
//+------------------------------------------------------------------+
bool CSystemHealthMonitor::CheckRiskManagerHealth(void)
{
    // Check risk manager component status
    ENUM_COMPONENT_STATUS riskStatus = CEnhancedErrorHandler::GetComponentStatus("RiskManager");
    
    if(riskStatus == COMPONENT_FAILED || riskStatus == COMPONENT_DISABLED)
        return false;
    
    // Check account balance and margin
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    double freeMargin = AccountInfoDouble(ACCOUNT_FREEMARGIN);
    
    if(balance <= 0 || margin < 0 || freeMargin < MIN_FREE_MARGIN)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Strategy Manager health                                 |
//+------------------------------------------------------------------+
bool CSystemHealthMonitor::CheckStrategyManagerHealth(void)
{
    // Check strategy manager component status
    ENUM_COMPONENT_STATUS strategyStatus = CEnhancedErrorHandler::GetComponentStatus("StrategyManager");
    
    if(strategyStatus == COMPONENT_FAILED || strategyStatus == COMPONENT_DISABLED)
        return false;
    
    // Additional strategy-specific checks could be added here
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Trade Manager health                                    |
//+------------------------------------------------------------------+
bool CSystemHealthMonitor::CheckTradeManagerHealth(void)
{
    // Check trade manager component status
    ENUM_COMPONENT_STATUS tradeStatus = CEnhancedErrorHandler::GetComponentStatus("TradeManager");
    
    if(tradeStatus == COMPONENT_FAILED || tradeStatus == COMPONENT_DISABLED)
        return false;
    
    // Check if trading is allowed
    if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Position Sizer health                                   |
//+------------------------------------------------------------------+
bool CSystemHealthMonitor::CheckPositionSizerHealth(void)
{
    // Check position sizer component status
    ENUM_COMPONENT_STATUS sizerStatus = CEnhancedErrorHandler::GetComponentStatus("PositionSizer");
    
    if(sizerStatus == COMPONENT_FAILED || sizerStatus == COMPONENT_DISABLED)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Broker Connection health                                |
//+------------------------------------------------------------------+
bool CSystemHealthMonitor::CheckBrokerConnectionHealth(void)
{
    // Check terminal connection
    if(!TerminalInfoInteger(TERMINAL_CONNECTED))
        return false;
    
    // Check if we can get current prices
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    
    if(bid <= 0 || ask <= 0 || ask <= bid)
        return false;
    
    // Check spread
    double spread = ask - bid;
    double normalSpread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD) * SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    
    if(spread > normalSpread * 3) // Spread too wide
        return false;
    
    return true;
}/
/+------------------------------------------------------------------+
//| Update system performance metrics                              |
//+------------------------------------------------------------------+
void CSystemHealthMonitor::UpdatePerformanceMetrics(void)
{
    // Update timestamp
    m_systemMetrics.lastUpdate = TimeCurrent();
    
    // Get memory usage (approximate)
    m_systemMetrics.memoryUsage = TerminalInfoInteger(TERMINAL_MEMORY_USED) / 1024.0; // Convert to MB
    
    // Count active handles (approximate by counting symbols)
    m_systemMetrics.activeHandles = SymbolsTotal(true);
    
    // CPU usage is not directly available in MQL5, so we'll estimate based on operations
    // This is a simplified approach
    static int lastOperationCount = 0;
    static datetime lastUpdateTime = 0;
    
    if(lastUpdateTime > 0)
    {
        int timeDiff = (int)(TimeCurrent() - lastUpdateTime);
        if(timeDiff > 0)
        {
            m_systemMetrics.operationsPerSecond = (lastOperationCount) / timeDiff;
        }
    }
    
    lastUpdateTime = TimeCurrent();
    lastOperationCount = 0; // Reset for next measurement
    
    // Update average latency (simplified)
    double totalResponseTime = 0;
    int validComponents = 0;
    
    for(int i = 0; i < m_componentCount; i++)
    {
        if(m_healthResults[i].averageResponseTime > 0)
        {
            totalResponseTime += m_healthResults[i].averageResponseTime;
            validComponents++;
        }
    }
    
    if(validComponents > 0)
        m_systemMetrics.averageLatency = totalResponseTime / validComponents;
}

//+------------------------------------------------------------------+
//| Get system performance metrics                                 |
//+------------------------------------------------------------------+
SPerformanceMetrics CSystemHealthMonitor::GetPerformanceMetrics(void)
{
    return m_systemMetrics;
}

//+------------------------------------------------------------------+
//| Attempt component restart                                      |
//+------------------------------------------------------------------+
bool CSystemHealthMonitor::AttemptComponentRestart(const string componentName)
{
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_INFO, "HealthMonitor", 
                                   "Attempting to restart component: " + componentName);
    }
    
    // Update component status to degraded for restart attempt
    CEnhancedErrorHandler::UpdateComponentHealth(componentName, COMPONENT_DEGRADED, 
                                                "Restart attempted");
    
    // Reset component health metrics
    int index = FindComponentIndex(componentName);
    if(index >= 0)
    {
        m_healthResults[index].failedChecks = 0;
        m_healthResults[index].healthScore = 0.5; // Partial health during restart
        m_healthResults[index].statusMessage = "Component restarting";
        m_healthResults[index].lastError = "";
    }
    
    // Perform health check to see if restart was successful
    bool restartSuccess = PerformHealthCheck(componentName);
    
    if(restartSuccess)
    {
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            localErrorHandler.LogError(ERROR_INFO, "HealthMonitor", 
                                       "Component restart successful: " + componentName);
        }
        CEnhancedErrorHandler::UpdateComponentHealth(componentName, COMPONENT_HEALTHY, 
                                                    "Restart successful");
    }
    else
    {
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            localErrorHandler.LogError(ERROR_WARNING, "HealthMonitor", 
                                       "Component restart failed: " + componentName);
        }
        CEnhancedErrorHandler::UpdateComponentHealth(componentName, COMPONENT_FAILING, 
                                                    "Restart failed");
    }
    
    return restartSuccess;
}

//+------------------------------------------------------------------+
//| Attempt system recovery                                        |
//+------------------------------------------------------------------+
bool CSystemHealthMonitor::AttemptSystemRecovery(void)
{
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_INFO, "HealthMonitor", 
                                   "Attempting system recovery");
    }
    
    bool recoverySuccess = true;
    
    // Attempt to restart failed components
    for(int i = 0; i < m_componentCount; i++)
    {
        if(!m_healthResults[i].isHealthy || m_healthResults[i].healthScore < 0.5)
        {
            bool componentRecovered = AttemptComponentRestart(m_healthResults[i].componentName);
            if(!componentRecovered)
                recoverySuccess = false;
        }
    }
    
    // Reset performance counters
    ResetPerformanceCounters();
    
    // Perform full system health check
    PerformSystemHealthCheck();
    
    if(recoverySuccess)
    {
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            localErrorHandler.LogError(ERROR_INFO, "HealthMonitor", 
                                       "System recovery completed successfully");
        }
    }
    else
    {
        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            localErrorHandler.LogError(ERROR_WARNING, "HealthMonitor", 
                                       "System recovery completed with some failures");
        }
    }
    
    return recoverySuccess;
}

//+------------------------------------------------------------------+
//| Configure alert system                                         |
//+------------------------------------------------------------------+
void CSystemHealthMonitor::ConfigureAlerts(const SAlertConfig &config)
{
    m_alertConfig = config;
    
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_INFO, "HealthMonitor", 
                                   StringFormat("Alert configuration updated - Enabled: %s, Threshold: %.2f",
                                   enabled ? "true" : "false", threshold));
    } 
                                               config.enableAlerts ? "Yes" : "No", 
                                               config.healthThreshold));
}

//+------------------------------------------------------------------+
//| Send health alert                                              |
//+------------------------------------------------------------------+
void CSystemHealthMonitor::SendHealthAlert(const string componentName, const string message)
{
    if(!m_alertConfig.enableAlerts) return;
    
    string alertMessage = StringFormat("🚨 HEALTH ALERT: %s - %s", componentName, message);
    
    // Send push notification if enabled
    if(m_alertConfig.sendPushNotifications)
    {
        SendNotification(alertMessage);
    }
    
    // Send terminal alert
    Alert(alertMessage);
    
    // Log to file if enabled
    if(m_alertConfig.logToFile)
    {
        LogAlert(componentName, message);
    }
    
    // Update last alert time
    int index = FindComponentIndex(componentName);
    if(index >= 0)
    {
        m_lastAlert[index] = TimeCurrent();
    }
    
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_WARNING, "HealthAlert", alertMessage);
    }
}

//+------------------------------------------------------------------+
//| Check and send alerts if needed                               |
//+------------------------------------------------------------------+
void CSystemHealthMonitor::CheckAndSendAlerts(void)
{
    if(!m_alertConfig.enableAlerts) return;
    
    for(int i = 0; i < m_componentCount; i++)
    {
        SHealthCheckResult &result = m_healthResults[i];
        
        // Check if alert should be sent
        bool shouldAlert = false;
        string alertReason = "";
        
        if(result.healthScore < m_alertConfig.healthThreshold)
        {
            shouldAlert = true;
            alertReason = StringFormat("Health score below threshold: %.2f < %.2f", 
                                     result.healthScore, m_alertConfig.healthThreshold);
        }
        
        if(result.failedChecks >= m_alertConfig.maxFailedChecks)
        {
            shouldAlert = true;
            alertReason = StringFormat("Too many failed checks: %d >= %d", 
                                     result.failedChecks, m_alertConfig.maxFailedChecks);
        }
        
        if(shouldAlert && ShouldSendAlert(result.componentName))
        {
            SendHealthAlert(result.componentName, alertReason);
        }
    }
}

//+------------------------------------------------------------------+
//| Generate health dashboard                                      |
//+------------------------------------------------------------------+
void CSystemHealthMonitor::GenerateHealthDashboard(string &dashboard)
{
    dashboard = "=== SYSTEM HEALTH DASHBOARD ===\n";
    dashboard += "Last Update: " + TimeToString(TimeCurrent()) + "\n";
    dashboard += "Monitoring: " + (m_monitoringEnabled ? "ENABLED" : "DISABLED") + "\n";
    dashboard += "System Health: " + GetHealthStatusString(GetSystemHealthScore()) + "\n\n";
    
    // Performance metrics
    dashboard += "PERFORMANCE METRICS:\n";
    dashboard += StringFormat("Memory Usage: %.1f MB\n", m_systemMetrics.memoryUsage);
    dashboard += StringFormat("Active Handles: %d\n", m_systemMetrics.activeHandles);
    dashboard += StringFormat("Avg Latency: %.2f ms\n", m_systemMetrics.averageLatency);
    dashboard += StringFormat("Operations/sec: %d\n\n", m_systemMetrics.operationsPerSecond);
    
    // Component status
    dashboard += "COMPONENT STATUS:\n";
    for(int i = 0; i < m_componentCount; i++)
    {
        SHealthCheckResult &result = m_healthResults[i];
        string status = GetHealthStatusString(result.healthScore);
        
        dashboard += StringFormat("%-15s: %s (%.2f) - %s\n", 
                                 result.componentName, 
                                 status, 
                                 result.healthScore,
                                 result.statusMessage);
        
        if(result.failedChecks > 0)
        {
            dashboard += StringFormat("                 Failed Checks: %d/%d\n", 
                                     result.failedChecks, result.checksPerformed);
        }
    }
    
    dashboard += "\n=== END DASHBOARD ===";
}

//+------------------------------------------------------------------+
//| Get system health score                                        |
//+------------------------------------------------------------------+
double CSystemHealthMonitor::GetSystemHealthScore(void)
{
    if(m_componentCount == 0) return 1.0;
    
    double totalScore = 0.0;
    for(int i = 0; i < m_componentCount; i++)
    {
        totalScore += m_healthResults[i].healthScore;
    }
    
    return totalScore / m_componentCount;
}

//+------------------------------------------------------------------+
//| Check if system is healthy                                     |
//+------------------------------------------------------------------+
bool CSystemHealthMonitor::IsSystemHealthy(void)
{
    return GetSystemHealthScore() >= m_alertConfig.healthThreshold;
}//+--------
----------------------------------------------------------+
//| Private helper methods                                         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Find component index by name                                  |
//+------------------------------------------------------------------+
int CSystemHealthMonitor::FindComponentIndex(const string componentName)
{
    for(int i = 0; i < m_componentCount; i++)
    {
        if(m_healthResults[i].componentName == componentName)
            return i;
    }
    return -1; // Not found
}

//+------------------------------------------------------------------+
//| Update component health                                        |
//+------------------------------------------------------------------+
void CSystemHealthMonitor::UpdateComponentHealth(const string componentName, 
                                                const bool isHealthy, 
                                                const double healthScore,
                                                const string statusMessage = "")
{
    int index = FindComponentIndex(componentName);
    if(index < 0) return; // Component not found
    
    m_healthResults[index].isHealthy = isHealthy;
    m_healthResults[index].healthScore = healthScore;
    m_healthResults[index].statusMessage = statusMessage;
    m_healthResults[index].lastCheck = TimeCurrent();
    
    if(!isHealthy && statusMessage != "")
    {
        m_healthResults[index].lastError = statusMessage;
    }
}

//+------------------------------------------------------------------+
//| Check if alert should be sent                                 |
//+------------------------------------------------------------------+
bool CSystemHealthMonitor::ShouldSendAlert(const string componentName)
{
    int index = FindComponentIndex(componentName);
    if(index < 0) return false;
    
    // Check cooldown period
    datetime now = TimeCurrent();
    if(now - m_lastAlert[index] < m_alertConfig.alertCooldownSeconds)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Log alert to file                                              |
//+------------------------------------------------------------------+
void CSystemHealthMonitor::LogAlert(const string componentName, const string message)
{
    int handle = FileOpen(m_alertLogFile, FILE_WRITE | FILE_READ | FILE_TXT);
    if(handle == INVALID_HANDLE) return;
    
    FileSeek(handle, 0, SEEK_END);
    string logEntry = StringFormat("[%s] ALERT: %s - %s", 
                                  TimeToString(TimeCurrent()), 
                                  componentName, 
                                  message);
    FileWrite(handle, logEntry);
    FileClose(handle);
}

//+------------------------------------------------------------------+
//| Get health status string                                       |
//+------------------------------------------------------------------+
string CSystemHealthMonitor::GetHealthStatusString(const double healthScore)
{
    if(healthScore >= 0.9) return "EXCELLENT";
    else if(healthScore >= 0.8) return "GOOD";
    else if(healthScore >= 0.7) return "FAIR";
    else if(healthScore >= 0.5) return "POOR";
    else if(healthScore >= 0.3) return "CRITICAL";
    else return "FAILED";
}

//+------------------------------------------------------------------+
//| Get health status color                                        |
//+------------------------------------------------------------------+
color CSystemHealthMonitor::GetHealthStatusColor(const double healthScore)
{
    if(healthScore >= 0.8) return clrGreen;
    else if(healthScore >= 0.6) return clrYellow;
    else if(healthScore >= 0.4) return clrOrange;
    else return clrRed;
}

//+------------------------------------------------------------------+
//| Reset performance counters                                     |
//+------------------------------------------------------------------+
void CSystemHealthMonitor::ResetPerformanceCounters(void)
{
    m_systemMetrics.cpuUsage = 0.0;
    m_systemMetrics.averageLatency = 0.0;
    m_systemMetrics.operationsPerSecond = 0;
    m_systemMetrics.lastUpdate = TimeCurrent();
    
    // Reset component counters
    for(int i = 0; i < m_componentCount; i++)
    {
        m_healthResults[i].checksPerformed = 0;
        m_healthResults[i].failedChecks = 0;
        m_healthResults[i].averageResponseTime = 0.0;
    }
    
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_INFO, "HealthMonitor", 
                                   "Performance counters reset");
    }
}

//+------------------------------------------------------------------+
//| Log health status                                              |
//+------------------------------------------------------------------+
void CSystemHealthMonitor::LogHealthStatus(void)
{
    double systemHealth = GetSystemHealthScore();
    string healthStatus = GetHealthStatusString(systemHealth);
    
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_INFO, "HealthMonitor", 
                                   StringFormat("System health check completed - Status: %s (%.2f)",
                                   overallHealth.isHealthy ? "HEALTHY" : "UNHEALTHY", overallHealth.healthScore));
    } 
                                               healthStatus, systemHealth));
    
    // Log individual component status if any are unhealthy
    for(int i = 0; i < m_componentCount; i++)
    {
        if(m_healthResults[i].healthScore < 0.8)
        {
            CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
            if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
                localErrorHandler.LogError(ERROR_WARNING, "HealthMonitor", 
                                           StringFormat("Component %s health: %s (%.2f) - %s",
                                           componentName, result.isHealthy ? "HEALTHY" : "UNHEALTHY", 
                                           result.healthScore, result.statusMessage));
            } 
                                                       m_healthResults[i].componentName,
                                                       GetHealthStatusString(m_healthResults[i].healthScore),
                                                       m_healthResults[i].healthScore,
                                                       m_healthResults[i].statusMessage));
        }
    }
}

//+------------------------------------------------------------------+
//| Cleanup old data                                               |
//+------------------------------------------------------------------+
void CSystemHealthMonitor::CleanupOldData(void)
{
    datetime now = TimeCurrent();
    
    // Reset old alert timestamps (older than 1 hour)
    for(int i = 0; i < m_componentCount; i++)
    {
        if(m_lastAlert[i] > 0 && now - m_lastAlert[i] > 3600)
        {
            m_lastAlert[i] = 0;
        }
    }
}

//+------------------------------------------------------------------+
//| Set monitoring enabled/disabled                                |
//+------------------------------------------------------------------+
void CSystemHealthMonitor::SetMonitoringEnabled(const bool enabled)
{
    m_monitoringEnabled = enabled;
    
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_INFO, "HealthMonitor", 
                                   enabled ? "Health monitoring enabled" : "Health monitoring disabled");
    }
}

//+------------------------------------------------------------------+
//| Set check interval                                             |
//+------------------------------------------------------------------+
void CSystemHealthMonitor::SetCheckInterval(const int intervalSeconds)
{
    m_checkInterval = intervalSeconds;
    
    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        localErrorHandler.LogError(ERROR_INFO, "HealthMonitor", 
                                   StringFormat("Health check interval set to %d seconds", intervalSeconds));
    }
}

//+------------------------------------------------------------------+
//| Generate detailed report                                       |
//+------------------------------------------------------------------+
void CSystemHealthMonitor::GenerateDetailedReport(string &report)
{
    report = "=== DETAILED SYSTEM HEALTH REPORT ===\n";
    report += "Generated: " + TimeToString(TimeCurrent()) + "\n";
    report += "Monitoring Status: " + (m_monitoringEnabled ? "ENABLED" : "DISABLED") + "\n";
    report += "Check Interval: " + IntegerToString(m_checkInterval) + " seconds\n";
    report += "Last System Check: " + TimeToString(m_lastSystemCheck) + "\n\n";
    
    // Overall system health
    double systemHealth = GetSystemHealthScore();
    report += "OVERALL SYSTEM HEALTH:\n";
    report += StringFormat("Health Score: %.2f (%s)\n", systemHealth, GetHealthStatusString(systemHealth));
    report += "System Status: " + (IsSystemHealthy() ? "HEALTHY" : "UNHEALTHY") + "\n\n";
    
    // Performance metrics
    report += "PERFORMANCE METRICS:\n";
    report += StringFormat("Memory Usage: %.1f MB\n", m_systemMetrics.memoryUsage);
    report += StringFormat("Active Handles: %d\n", m_systemMetrics.activeHandles);
    report += StringFormat("Average Latency: %.2f ms\n", m_systemMetrics.averageLatency);
    report += StringFormat("Operations per Second: %d\n", m_systemMetrics.operationsPerSecond);
    report += "Last Metrics Update: " + TimeToString(m_systemMetrics.lastUpdate) + "\n\n";
    
    // Alert configuration
    report += "ALERT CONFIGURATION:\n";
    report += StringFormat("Alerts Enabled: %s\n", m_alertConfig.enableAlerts ? "Yes" : "No");
    report += StringFormat("Health Threshold: %.2f\n", m_alertConfig.healthThreshold);
    report += StringFormat("Max Failed Checks: %d\n", m_alertConfig.maxFailedChecks);
    report += StringFormat("Alert Cooldown: %d seconds\n", m_alertConfig.alertCooldownSeconds);
    report += StringFormat("Push Notifications: %s\n", m_alertConfig.sendPushNotifications ? "Yes" : "No");
    report += StringFormat("Log to File: %s\n\n", m_alertConfig.logToFile ? "Yes" : "No");
    
    // Detailed component information
    report += "COMPONENT DETAILS:\n";
    for(int i = 0; i < m_componentCount; i++)
    {
        SHealthCheckResult &result = m_healthResults[i];
        
        report += StringFormat("Component: %s\n", result.componentName);
        report += StringFormat("  Status: %s\n", result.isHealthy ? "HEALTHY" : "UNHEALTHY");
        report += StringFormat("  Health Score: %.2f (%s)\n", result.healthScore, GetHealthStatusString(result.healthScore));
        report += StringFormat("  Last Check: %s\n", TimeToString(result.lastCheck));
        report += StringFormat("  Checks Performed: %d\n", result.checksPerformed);
        report += StringFormat("  Failed Checks: %d\n", result.failedChecks);
        report += StringFormat("  Success Rate: %.1f%%\n", 
                              result.checksPerformed > 0 ? 
                              (double)(result.checksPerformed - result.failedChecks) / result.checksPerformed * 100 : 100.0);
        report += StringFormat("  Avg Response Time: %.2f ms\n", result.averageResponseTime);
        report += StringFormat("  Status Message: %s\n", result.statusMessage);
        
        if(result.lastError != "")
            report += StringFormat("  Last Error: %s\n", result.lastError);
        
        datetime lastAlert = 0;
        if(i < ArraySize(m_lastAlert))
            lastAlert = m_lastAlert[i];
        
        if(lastAlert > 0)
            report += StringFormat("  Last Alert: %s\n", TimeToString(lastAlert));
        
        report += "\n";
    }
    
    report += "=== END DETAILED REPORT ===";
}

//+------------------------------------------------------------------+
//| Get component health result                                    |
//+------------------------------------------------------------------+
SHealthCheckResult CSystemHealthMonitor::GetComponentHealth(const string componentName)
{
    SHealthCheckResult emptyResult;
    emptyResult.componentName = componentName;
    emptyResult.isHealthy = false;
    emptyResult.healthScore = 0.0;
    emptyResult.statusMessage = "Component not found";
    
    int index = FindComponentIndex(componentName);
    if(index >= 0)
        return m_healthResults[index];
    
    return emptyResult;
}

//+------------------------------------------------------------------+
//| Get all health results                                         |
//+------------------------------------------------------------------+
void CSystemHealthMonitor::GetAllHealthResults(SHealthCheckResult &results[], int &count)
{
    count = m_componentCount;
    ArrayResize(results, count);
    
    for(int i = 0; i < count; i++)
    {
        results[i] = m_healthResults[i];
    }
}

#endif // CORE_SYSTEM_HEALTH_MONITOR_MQH