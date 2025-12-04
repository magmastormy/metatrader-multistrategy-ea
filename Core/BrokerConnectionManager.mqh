//+------------------------------------------------------------------+
//| Broker Connection Manager                                      |
//| Comprehensive broker connection resilience and monitoring     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_BROKER_CONNECTION_MANAGER_MQH
#define CORE_BROKER_CONNECTION_MANAGER_MQH

#include "Enums.mqh"
#include "ErrorHandling.mqh"

//+------------------------------------------------------------------+
//| Connection Status                                              |
//+------------------------------------------------------------------+
enum ENUM_CONNECTION_STATUS
{
    CONNECTION_UNKNOWN = 0,         // Unknown status
    CONNECTION_CONNECTED = 1,       // Connected and healthy
    CONNECTION_DISCONNECTED = 2,    // Disconnected
    CONNECTION_UNSTABLE = 3,        // Connected but unstable
    CONNECTION_RECONNECTING = 4,    // Attempting to reconnect
    CONNECTION_FAILED = 5           // Connection failed
};

//+------------------------------------------------------------------+
//| Trade Execution Status                                         |
//+------------------------------------------------------------------+
enum ENUM_EXECUTION_STATUS
{
    EXECUTION_SUCCESS = 0,          // Execution successful
    EXECUTION_RETRY = 1,            // Should retry execution
    EXECUTION_FAILED = 2,           // Execution failed permanently
    EXECUTION_TIMEOUT = 3,          // Execution timed out
    EXECUTION_REJECTED = 4          // Execution rejected by broker
};

//+------------------------------------------------------------------+
//| Connection Health Metrics                                      |
//+------------------------------------------------------------------+
struct SConnectionHealth
{
    ENUM_CONNECTION_STATUS status;  // Current connection status
    datetime lastConnected;         // Last successful connection
    datetime lastDisconnected;      // Last disconnection
    int connectionAttempts;         // Number of connection attempts
    int successfulConnections;      // Number of successful connections
    double connectionUptime;        // Connection uptime percentage
    double averageLatency;          // Average response latency
    int failedRequests;             // Number of failed requests
    int totalRequests;              // Total requests made
    string lastError;               // Last error message
};

//+------------------------------------------------------------------+
//| Retry Configuration                                            |
//+------------------------------------------------------------------+
struct SRetryConfiguration
{
    int maxRetries;                 // Maximum retry attempts
    int baseDelayMs;                // Base delay in milliseconds
    double backoffMultiplier;       // Exponential backoff multiplier
    int maxDelayMs;                 // Maximum delay between retries
    bool enableJitter;              // Add random jitter to delays
    int timeoutMs;                  // Request timeout in milliseconds
};

//+------------------------------------------------------------------+
//| Trade Request with Retry Info                                 |
//+------------------------------------------------------------------+
struct STradeRequestInfo
{
    MqlTradeRequest request;        // Original trade request
    int attemptCount;               // Current attempt count
    datetime firstAttempt;          // First attempt timestamp
    datetime lastAttempt;           // Last attempt timestamp
    int lastErrorCode;              // Last error code
    string lastErrorMessage;        // Last error message
    bool isRetryable;               // Whether request is retryable
};

//+------------------------------------------------------------------+
//| Broker Connection Manager Class                               |
//+------------------------------------------------------------------+
class CBrokerConnectionManager
{
private:
    static SConnectionHealth m_connectionHealth;
    static SRetryConfiguration m_retryConfig;
    static bool m_initialized;
    static bool m_autoReconnectEnabled;
    static int m_reconnectIntervalSeconds;
    static datetime m_lastHealthCheck;
    static datetime m_lastReconnectAttempt;
    static STradeRequestInfo m_pendingRequests[];
    static int m_pendingRequestCount;
    static bool m_emergencyMode;
    static string m_alternativeBrokers[];
    static int m_currentBrokerIndex;

public:
    // Constructor
    CBrokerConnectionManager(void);
    
    // Destructor
    ~CBrokerConnectionManager(void);
    
    // Initialize connection manager
    static bool Initialize(const SRetryConfiguration &retryConfig);
    
    // Connection monitoring and management
    static ENUM_CONNECTION_STATUS CheckConnectionStatus(void);
    static bool IsConnected(void);
    static bool IsConnectionStable(void);
    static void UpdateConnectionHealth(void);
    static SConnectionHealth GetConnectionHealth(void);
    
    // Automatic reconnection
    static bool AttemptReconnection(void);
    static void EnableAutoReconnect(const bool enabled = true);
    static void SetReconnectInterval(const int intervalSeconds);
    static bool PerformReconnectionCycle(void);
    
    // Trade execution with retry logic
    static ENUM_EXECUTION_STATUS ExecuteTradeWithRetry(const MqlTradeRequest &request, 
                                                      MqlTradeResult &result);
    static ENUM_EXECUTION_STATUS ExecuteSingleTrade(const MqlTradeRequest &request, 
                                                    MqlTradeResult &result);
    static bool IsTradeErrorRetryable(const int errorCode);
    static int CalculateRetryDelay(const int attemptNumber);
    
    // Alternative execution paths
    static bool SetAlternativeBrokers(const string &brokerList[]);
    static bool SwitchToAlternativeBroker(void);
    static string GetCurrentBrokerInfo(void);
    
    // Request queue management
    static bool QueueTradeRequest(const MqlTradeRequest &request);
    static void ProcessPendingRequests(void);
    static void ClearPendingRequests(void);
    static int GetPendingRequestCount(void);
    
    // Network and latency monitoring
    static double MeasureLatency(void);
    static bool TestBrokerAPI(void);
    static void MonitorNetworkHealth(void);
    static bool IsNetworkHealthy(void);
    
    // Emergency procedures
    static void ActivateEmergencyMode(const string reason);
    static void DeactivateEmergencyMode(void);
    static bool IsEmergencyMode(void) { return m_emergencyMode; }
    static void HandleConnectionEmergency(void);
    
    // Configuration and settings
    static void SetRetryConfiguration(const SRetryConfiguration &config);
    static SRetryConfiguration GetRetryConfiguration(void);
    static void SetConnectionTimeout(const int timeoutMs);
    
    // Reporting and diagnostics
    static void GenerateConnectionReport(string &report);
    static void LogConnectionStatus(void);
    static void ResetConnectionStats(void);
    
    // Utility functions
    static string GetConnectionStatusString(const ENUM_CONNECTION_STATUS status);
    static string GetExecutionStatusString(const ENUM_EXECUTION_STATUS status);
    static bool IsConnectionError(const int errorCode);
    
private:
    // Internal helper methods
    static void UpdateLatencyMetrics(const double latency);
    static void UpdateRequestStats(const bool success);
    static bool WaitForConnection(const int timeoutSeconds);
    static void AddJitterToDelay(int &delayMs);
    static int FindPendingRequestIndex(const ulong ticket);
    static void RemovePendingRequest(const int index);
    static bool ValidateTradeRequest(const MqlTradeRequest &request);
};

// Static member initialization
static SConnectionHealth CBrokerConnectionManager::m_connectionHealth;
static SRetryConfiguration CBrokerConnectionManager::m_retryConfig = {3, 1000, 2.0, 30000, true, 10000};
static bool CBrokerConnectionManager::m_initialized = false;
static bool CBrokerConnectionManager::m_autoReconnectEnabled = true;
static int CBrokerConnectionManager::m_reconnectIntervalSeconds = 30;
static datetime CBrokerConnectionManager::m_lastHealthCheck = 0;
static datetime CBrokerConnectionManager::m_lastReconnectAttempt = 0;
static STradeRequestInfo CBrokerConnectionManager::m_pendingRequests[];
static int CBrokerConnectionManager::m_pendingRequestCount = 0;
static bool CBrokerConnectionManager::m_emergencyMode = false;
static string CBrokerConnectionManager::m_alternativeBrokers[];
static int CBrokerConnectionManager::m_currentBrokerIndex = 0;

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CBrokerConnectionManager::CBrokerConnectionManager(void)
{
    // Constructor implementation
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CBrokerConnectionManager::~CBrokerConnectionManager(void)
{
    if(m_initialized)
    {
        ClearPendingRequests();
        CEnhancedErrorHandler::LogError(ERROR_INFO, "BrokerConnectionManager", 
                                       "Broker connection manager shutdown");
    }
}

//+------------------------------------------------------------------+
//| Initialize connection manager                                  |
//+------------------------------------------------------------------+
bool CBrokerConnectionManager::Initialize(const SRetryConfiguration &retryConfig)
{
    m_retryConfig = retryConfig;
    m_initialized = true;
    m_emergencyMode = false;
    m_pendingRequestCount = 0;
    
    // Initialize arrays
    ArrayResize(m_pendingRequests, 100); // Initial capacity
    ArrayResize(m_alternativeBrokers, 10);
    
    // Initialize connection health
    m_connectionHealth.status = CONNECTION_UNKNOWN;
    m_connectionHealth.lastConnected = 0;
    m_connectionHealth.lastDisconnected = 0;
    m_connectionHealth.connectionAttempts = 0;
    m_connectionHealth.successfulConnections = 0;
    m_connectionHealth.connectionUptime = 0.0;
    m_connectionHealth.averageLatency = 0.0;
    m_connectionHealth.failedRequests = 0;
    m_connectionHealth.totalRequests = 0;
    m_connectionHealth.lastError = "";
    
    // Perform initial connection check
    UpdateConnectionHealth();
    
    CEnhancedErrorHandler::LogError(ERROR_INFO, "BrokerConnectionManager", 
                                   "Broker connection manager initialized successfully");
    
    return true;
}//+---
---------------------------------------------------------------+
//| Check connection status                                        |
//+------------------------------------------------------------------+
ENUM_CONNECTION_STATUS CBrokerConnectionManager::CheckConnectionStatus(void)
{
    if(!m_initialized) return CONNECTION_UNKNOWN;
    
    // Check terminal connection
    if(!TerminalInfoInteger(TERMINAL_CONNECTED))
    {
        m_connectionHealth.status = CONNECTION_DISCONNECTED;
        return CONNECTION_DISCONNECTED;
    }
    
    // Check if we can get account information
    if(AccountInfoInteger(ACCOUNT_LOGIN) <= 0)
    {
        m_connectionHealth.status = CONNECTION_UNSTABLE;
        return CONNECTION_UNSTABLE;
    }
    
    // Test basic API functionality
    if(!TestBrokerAPI())
    {
        m_connectionHealth.status = CONNECTION_UNSTABLE;
        return CONNECTION_UNSTABLE;
    }
    
    m_connectionHealth.status = CONNECTION_CONNECTED;
    return CONNECTION_CONNECTED;
}

//+------------------------------------------------------------------+
//| Check if connected                                             |
//+------------------------------------------------------------------+
bool CBrokerConnectionManager::IsConnected(void)
{
    ENUM_CONNECTION_STATUS status = CheckConnectionStatus();
    return (status == CONNECTION_CONNECTED || status == CONNECTION_UNSTABLE);
}

//+------------------------------------------------------------------+
//| Check if connection is stable                                  |
//+------------------------------------------------------------------+
bool CBrokerConnectionManager::IsConnectionStable(void)
{
    return (CheckConnectionStatus() == CONNECTION_CONNECTED);
}

//+------------------------------------------------------------------+
//| Update connection health metrics                               |
//+------------------------------------------------------------------+
void CBrokerConnectionManager::UpdateConnectionHealth(void)
{
    if(!m_initialized) return;
    
    m_lastHealthCheck = TimeCurrent();
    ENUM_CONNECTION_STATUS currentStatus = CheckConnectionStatus();
    ENUM_CONNECTION_STATUS previousStatus = m_connectionHealth.status;
    
    // Update connection status
    m_connectionHealth.status = currentStatus;
    
    // Handle status changes
    if(previousStatus != currentStatus)
    {
        if(currentStatus == CONNECTION_CONNECTED)
        {
            m_connectionHealth.lastConnected = TimeCurrent();
            m_connectionHealth.successfulConnections++;
            
            CEnhancedErrorHandler::LogError(ERROR_INFO, "BrokerConnectionManager", 
                                           "Connection established");
            
            // Process pending requests if any
            if(m_pendingRequestCount > 0)
            {
                ProcessPendingRequests();
            }
        }
        else if(currentStatus == CONNECTION_DISCONNECTED)
        {
            m_connectionHealth.lastDisconnected = TimeCurrent();
            
            CEnhancedErrorHandler::LogError(ERROR_WARNING, "BrokerConnectionManager", 
                                           "Connection lost");
            
            // Attempt reconnection if enabled
            if(m_autoReconnectEnabled)
            {
                AttemptReconnection();
            }
        }
    }
    
    // Update uptime calculation
    if(m_connectionHealth.lastConnected > 0)
    {
        datetime totalTime = TimeCurrent() - m_connectionHealth.lastConnected;
        datetime connectedTime = totalTime;
        
        if(m_connectionHealth.lastDisconnected > m_connectionHealth.lastConnected)
        {
            connectedTime = m_connectionHealth.lastDisconnected - m_connectionHealth.lastConnected;
        }
        
        if(totalTime > 0)
            m_connectionHealth.connectionUptime = (double)connectedTime / totalTime * 100.0;
    }
    
    // Measure current latency
    double latency = MeasureLatency();
    if(latency > 0)
    {
        UpdateLatencyMetrics(latency);
    }
}

//+------------------------------------------------------------------+
//| Attempt reconnection                                           |
//+------------------------------------------------------------------+
bool CBrokerConnectionManager::AttemptReconnection(void)
{
    if(!m_initialized) return false;
    
    datetime now = TimeCurrent();
    
    // Check if enough time has passed since last attempt
    if(now - m_lastReconnectAttempt < m_reconnectIntervalSeconds)
        return false;
    
    m_lastReconnectAttempt = now;
    m_connectionHealth.connectionAttempts++;
    
    CEnhancedErrorHandler::LogError(ERROR_INFO, "BrokerConnectionManager", 
                                   StringFormat("Attempting reconnection (attempt %d)", 
                                               m_connectionHealth.connectionAttempts));
    
    // Wait for connection to be established
    bool reconnected = WaitForConnection(30); // Wait up to 30 seconds
    
    if(reconnected)
    {
        CEnhancedErrorHandler::LogError(ERROR_INFO, "BrokerConnectionManager", 
                                       "Reconnection successful");
        
        // Update connection health
        UpdateConnectionHealth();
        
        // Deactivate emergency mode if it was active
        if(m_emergencyMode)
        {
            DeactivateEmergencyMode();
        }
        
        return true;
    }
    else
    {
        CEnhancedErrorHandler::LogError(ERROR_WARNING, "BrokerConnectionManager", 
                                       "Reconnection failed");
        
        // Try alternative broker if available
        if(ArraySize(m_alternativeBrokers) > 0)
        {
            SwitchToAlternativeBroker();
        }
        
        return false;
    }
}

//+------------------------------------------------------------------+
//| Execute trade with retry logic                                |
//+------------------------------------------------------------------+
ENUM_EXECUTION_STATUS CBrokerConnectionManager::ExecuteTradeWithRetry(const MqlTradeRequest &request, 
                                                                      MqlTradeResult &result)
{
    if(!m_initialized) return EXECUTION_FAILED;
    
    // Validate request
    if(!ValidateTradeRequest(request))
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "BrokerConnectionManager", 
                                       "Invalid trade request");
        return EXECUTION_FAILED;
    }
    
    // Check if connection is available
    if(!IsConnected())
    {
        CEnhancedErrorHandler::LogError(ERROR_WARNING, "BrokerConnectionManager", 
                                       "No connection available for trade execution");
        
        // Queue request if connection is down
        QueueTradeRequest(request);
        return EXECUTION_RETRY;
    }
    
    ENUM_EXECUTION_STATUS executionStatus = EXECUTION_FAILED;
    int attemptCount = 0;
    
    while(attemptCount < m_retryConfig.maxRetries)
    {
        attemptCount++;
        
        // Execute single trade attempt
        executionStatus = ExecuteSingleTrade(request, result);
        
        if(executionStatus == EXECUTION_SUCCESS)
        {
            UpdateRequestStats(true);
            
            CEnhancedErrorHandler::LogError(ERROR_INFO, "BrokerConnectionManager", 
                                           StringFormat("Trade executed successfully on attempt %d", attemptCount));
            break;
        }
        else if(executionStatus == EXECUTION_FAILED)
        {
            UpdateRequestStats(false);
            
            CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "BrokerConnectionManager", 
                                           StringFormat("Trade execution failed permanently on attempt %d", attemptCount));
            break;
        }
        else if(executionStatus == EXECUTION_RETRY && attemptCount < m_retryConfig.maxRetries)
        {
            // Calculate delay for next attempt
            int delay = CalculateRetryDelay(attemptCount);
            
            CEnhancedErrorHandler::LogError(ERROR_INFO, "BrokerConnectionManager", 
                                           StringFormat("Trade execution failed, retrying in %d ms (attempt %d/%d)", 
                                                       delay, attemptCount, m_retryConfig.maxRetries));
            
            Sleep(delay);
            
            // Check connection status before retry
            if(!IsConnected())
            {
                AttemptReconnection();
            }
        }
    }
    
    // If all retries failed, queue the request
    if(executionStatus != EXECUTION_SUCCESS && attemptCount >= m_retryConfig.maxRetries)
    {
        CEnhancedErrorHandler::LogError(ERROR_WARNING, "BrokerConnectionManager", 
                                       "All retry attempts exhausted, queueing request");
        QueueTradeRequest(request);
        executionStatus = EXECUTION_RETRY;
    }
    
    return executionStatus;
}

//+------------------------------------------------------------------+
//| Execute single trade attempt                                   |
//+------------------------------------------------------------------+
ENUM_EXECUTION_STATUS CBrokerConnectionManager::ExecuteSingleTrade(const MqlTradeRequest &request, 
                                                                   MqlTradeResult &result)
{
    // Record start time for latency measurement
    datetime startTime = GetMicrosecondCount();
    
    // Execute the trade
    bool success = OrderSend(request, result);
    
    // Calculate and record latency
    double latency = (GetMicrosecondCount() - startTime) / 1000.0; // Convert to milliseconds
    UpdateLatencyMetrics(latency);
    
    if(success)
    {
        return EXECUTION_SUCCESS;
    }
    
    // Analyze the error
    int errorCode = result.retcode;
    
    if(IsTradeErrorRetryable(errorCode))
    {
        CEnhancedErrorHandler::LogError(ERROR_INFO, "BrokerConnectionManager", 
                                       StringFormat("Retryable trade error: %d - %s", 
                                                   errorCode, 
                                                   CEnhancedErrorHandler::GetErrorDescription(errorCode)));
        return EXECUTION_RETRY;
    }
    else
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "BrokerConnectionManager", 
                                       StringFormat("Non-retryable trade error: %d - %s", 
                                                   errorCode, 
                                                   CEnhancedErrorHandler::GetErrorDescription(errorCode)));
        return EXECUTION_FAILED;
    }
}

//+------------------------------------------------------------------+
//| Check if trade error is retryable                             |
//+------------------------------------------------------------------+
bool CBrokerConnectionManager::IsTradeErrorRetryable(const int errorCode)
{
    switch(errorCode)
    {
        case TRADE_RETCODE_REQUOTE:         // Requote
        case TRADE_RETCODE_CONNECTION:      // No connection
        case TRADE_RETCODE_PRICE_CHANGED:   // Price changed
        case TRADE_RETCODE_TIMEOUT:         // Timeout
        case TRADE_RETCODE_PRICE_OFF:       // Invalid price
        case TRADE_RETCODE_REJECT:          // Request rejected
        case TRADE_RETCODE_CANCEL:          // Request canceled
        case TRADE_RETCODE_PLACED:          // Order placed
        case TRADE_RETCODE_DONE_PARTIAL:    // Request completed partially
        case TRADE_RETCODE_ERROR:           // Common error
        case TRADE_RETCODE_TOO_MANY_REQUESTS: // Too frequent requests
        case TRADE_RETCODE_NO_CHANGES:      // No changes in request
        case TRADE_RETCODE_SERVER_DISABLES_AT: // Autotrading disabled by server
        case TRADE_RETCODE_CLIENT_DISABLES_AT: // Autotrading disabled by client
        case TRADE_RETCODE_LOCKED:          // Request locked for processing
        case TRADE_RETCODE_FROZEN:          // Order or position frozen
        case TRADE_RETCODE_CONNECTION:      // No connection with trade server
            return true;
            
        case TRADE_RETCODE_INVALID_VOLUME:  // Invalid volume
        case TRADE_RETCODE_INVALID_PRICE:   // Invalid price
        case TRADE_RETCODE_INVALID_STOPS:   // Invalid stops
        case TRADE_RETCODE_TRADE_DISABLED:  // Trade disabled
        case TRADE_RETCODE_MARKET_CLOSED:   // Market closed
        case TRADE_RETCODE_NO_MONEY:        // Not enough money
        case TRADE_RETCODE_INVALID_FILL:    // Invalid order filling type
        case TRADE_RETCODE_ONLY_REAL:       // Only for live accounts
        case TRADE_RETCODE_LIMIT_ORDERS:    // Limit orders limit reached
        case TRADE_RETCODE_LIMIT_VOLUME:    // Volume limit reached
        case TRADE_RETCODE_INVALID_ORDER:   // Incorrect order type
        case TRADE_RETCODE_POSITION_CLOSED: // Position already closed
            return false; // These require manual intervention
            
        default:
            return false; // Unknown errors are not retryable by default
    }
}//+-----
-------------------------------------------------------------+
//| Calculate retry delay with exponential backoff                |
//+------------------------------------------------------------------+
int CBrokerConnectionManager::CalculateRetryDelay(const int attemptNumber)
{
    int delay = (int)(m_retryConfig.baseDelayMs * MathPow(m_retryConfig.backoffMultiplier, attemptNumber - 1));
    
    // Apply maximum delay limit
    delay = MathMin(delay, m_retryConfig.maxDelayMs);
    
    // Add jitter if enabled
    if(m_retryConfig.enableJitter)
    {
        AddJitterToDelay(delay);
    }
    
    return delay;
}

//+------------------------------------------------------------------+
//| Queue trade request for later execution                       |
//+------------------------------------------------------------------+
bool CBrokerConnectionManager::QueueTradeRequest(const MqlTradeRequest &request)
{
    if(m_pendingRequestCount >= ArraySize(m_pendingRequests))
    {
        ArrayResize(m_pendingRequests, ArraySize(m_pendingRequests) + 50);
    }
    
    // Create request info
    m_pendingRequests[m_pendingRequestCount].request = request;
    m_pendingRequests[m_pendingRequestCount].attemptCount = 0;
    m_pendingRequests[m_pendingRequestCount].firstAttempt = TimeCurrent();
    m_pendingRequests[m_pendingRequestCount].lastAttempt = 0;
    m_pendingRequests[m_pendingRequestCount].lastErrorCode = 0;
    m_pendingRequests[m_pendingRequestCount].lastErrorMessage = "";
    m_pendingRequests[m_pendingRequestCount].isRetryable = true;
    
    m_pendingRequestCount++;
    
    CEnhancedErrorHandler::LogError(ERROR_INFO, "BrokerConnectionManager", 
                                   StringFormat("Trade request queued (total pending: %d)", m_pendingRequestCount));
    
    return true;
}

//+------------------------------------------------------------------+
//| Process pending trade requests                                 |
//+------------------------------------------------------------------+
void CBrokerConnectionManager::ProcessPendingRequests(void)
{
    if(m_pendingRequestCount == 0 || !IsConnected()) return;
    
    CEnhancedErrorHandler::LogError(ERROR_INFO, "BrokerConnectionManager", 
                                   StringFormat("Processing %d pending requests", m_pendingRequestCount));
    
    int processedCount = 0;
    int successCount = 0;
    
    for(int i = m_pendingRequestCount - 1; i >= 0; i--)
    {
        MqlTradeResult result;
        ENUM_EXECUTION_STATUS status = ExecuteSingleTrade(m_pendingRequests[i].request, result);
        
        processedCount++;
        
        if(status == EXECUTION_SUCCESS)
        {
            successCount++;
            RemovePendingRequest(i);
        }
        else if(status == EXECUTION_FAILED)
        {
            // Remove failed requests that are not retryable
            RemovePendingRequest(i);
        }
        // Keep retryable requests in queue
        
        // Limit processing to avoid overloading
        if(processedCount >= 10) break;
    }
    
    CEnhancedErrorHandler::LogError(ERROR_INFO, "BrokerConnectionManager", 
                                   StringFormat("Processed %d requests, %d successful, %d remaining", 
                                               processedCount, successCount, m_pendingRequestCount));
}

//+------------------------------------------------------------------+
//| Measure network latency                                        |
//+------------------------------------------------------------------+
double CBrokerConnectionManager::MeasureLatency(void)
{
    datetime startTime = GetMicrosecondCount();
    
    // Simple latency test - get account balance
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    double latency = (GetMicrosecondCount() - startTime) / 1000.0; // Convert to milliseconds
    
    return latency;
}

//+------------------------------------------------------------------+
//| Test broker API functionality                                  |
//+------------------------------------------------------------------+
bool CBrokerConnectionManager::TestBrokerAPI(void)
{
    // Test basic API calls
    if(AccountInfoInteger(ACCOUNT_LOGIN) <= 0) return false;
    if(AccountInfoDouble(ACCOUNT_BALANCE) < 0) return false;
    if(SymbolInfoDouble(_Symbol, SYMBOL_BID) <= 0) return false;
    if(SymbolInfoDouble(_Symbol, SYMBOL_ASK) <= 0) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Activate emergency mode                                        |
//+------------------------------------------------------------------+
void CBrokerConnectionManager::ActivateEmergencyMode(const string reason)
{
    if(!m_emergencyMode)
    {
        m_emergencyMode = true;
        
        CEnhancedErrorHandler::LogError(ERROR_CRITICAL, "BrokerConnectionManager", 
                                       "Emergency mode activated: " + reason);
        
        // Send alert
        Alert("🚨 BROKER CONNECTION EMERGENCY: ", reason);
        
        // Clear pending requests to prevent further issues
        ClearPendingRequests();
        
        // Attempt immediate reconnection
        AttemptReconnection();
    }
}

//+------------------------------------------------------------------+
//| Generate connection report                                     |
//+------------------------------------------------------------------+
void CBrokerConnectionManager::GenerateConnectionReport(string &report)
{
    UpdateConnectionHealth();
    
    report = "=== BROKER CONNECTION REPORT ===\n";
    report += "Generated: " + TimeToString(TimeCurrent()) + "\n";
    report += "Status: " + GetConnectionStatusString(m_connectionHealth.status) + "\n";
    report += "Emergency Mode: " + (m_emergencyMode ? "ACTIVE" : "Inactive") + "\n\n";
    
    // Connection statistics
    report += "CONNECTION STATISTICS:\n";
    report += StringFormat("Connection Attempts: %d\n", m_connectionHealth.connectionAttempts);
    report += StringFormat("Successful Connections: %d\n", m_connectionHealth.successfulConnections);
    report += StringFormat("Connection Uptime: %.2f%%\n", m_connectionHealth.connectionUptime);
    report += StringFormat("Average Latency: %.2f ms\n", m_connectionHealth.averageLatency);
    
    if(m_connectionHealth.lastConnected > 0)
        report += "Last Connected: " + TimeToString(m_connectionHealth.lastConnected) + "\n";
    if(m_connectionHealth.lastDisconnected > 0)
        report += "Last Disconnected: " + TimeToString(m_connectionHealth.lastDisconnected) + "\n";
    
    report += "\n";
    
    // Request statistics
    report += "REQUEST STATISTICS:\n";
    report += StringFormat("Total Requests: %d\n", m_connectionHealth.totalRequests);
    report += StringFormat("Failed Requests: %d\n", m_connectionHealth.failedRequests);
    
    if(m_connectionHealth.totalRequests > 0)
    {
        double successRate = (double)(m_connectionHealth.totalRequests - m_connectionHealth.failedRequests) / 
                            m_connectionHealth.totalRequests * 100.0;
        report += StringFormat("Success Rate: %.2f%%\n", successRate);
    }
    
    report += StringFormat("Pending Requests: %d\n", m_pendingRequestCount);
    report += "\n";
    
    // Configuration
    report += "RETRY CONFIGURATION:\n";
    report += StringFormat("Max Retries: %d\n", m_retryConfig.maxRetries);
    report += StringFormat("Base Delay: %d ms\n", m_retryConfig.baseDelayMs);
    report += StringFormat("Backoff Multiplier: %.2f\n", m_retryConfig.backoffMultiplier);
    report += StringFormat("Max Delay: %d ms\n", m_retryConfig.maxDelayMs);
    report += StringFormat("Jitter Enabled: %s\n", m_retryConfig.enableJitter ? "Yes" : "No");
    report += StringFormat("Timeout: %d ms\n", m_retryConfig.timeoutMs);
    report += StringFormat("Auto Reconnect: %s\n", m_autoReconnectEnabled ? "Yes" : "No");
    report += StringFormat("Reconnect Interval: %d seconds\n", m_reconnectIntervalSeconds);
    
    if(m_connectionHealth.lastError != "")
        report += "\nLast Error: " + m_connectionHealth.lastError + "\n";
    
    report += "\n=== END REPORT ===";
}

//+------------------------------------------------------------------+
//| Private helper methods                                         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Update latency metrics                                         |
//+------------------------------------------------------------------+
void CBrokerConnectionManager::UpdateLatencyMetrics(const double latency)
{
    if(m_connectionHealth.totalRequests == 0)
        m_connectionHealth.averageLatency = latency;
    else
        m_connectionHealth.averageLatency = (m_connectionHealth.averageLatency * m_connectionHealth.totalRequests + latency) / 
                                           (m_connectionHealth.totalRequests + 1);
}

//+------------------------------------------------------------------+
//| Update request statistics                                      |
//+------------------------------------------------------------------+
void CBrokerConnectionManager::UpdateRequestStats(const bool success)
{
    m_connectionHealth.totalRequests++;
    if(!success)
        m_connectionHealth.failedRequests++;
}

//+------------------------------------------------------------------+
//| Wait for connection to be established                          |
//+------------------------------------------------------------------+
bool CBrokerConnectionManager::WaitForConnection(const int timeoutSeconds)
{
    datetime startTime = TimeCurrent();
    
    while(TimeCurrent() - startTime < timeoutSeconds)
    {
        if(IsConnected())
            return true;
        
        Sleep(1000); // Wait 1 second before checking again
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Add random jitter to delay                                     |
//+------------------------------------------------------------------+
void CBrokerConnectionManager::AddJitterToDelay(int &delayMs)
{
    // Add up to 20% random jitter
    int jitter = (int)(delayMs * 0.2 * (MathRand() / 32767.0));
    delayMs += jitter;
}

//+------------------------------------------------------------------+
//| Remove pending request by index                                |
//+------------------------------------------------------------------+
void CBrokerConnectionManager::RemovePendingRequest(const int index)
{
    if(index < 0 || index >= m_pendingRequestCount) return;
    
    // Shift elements to remove the request
    for(int i = index; i < m_pendingRequestCount - 1; i++)
    {
        m_pendingRequests[i] = m_pendingRequests[i + 1];
    }
    
    m_pendingRequestCount--;
}

//+------------------------------------------------------------------+
//| Validate trade request                                         |
//+------------------------------------------------------------------+
bool CBrokerConnectionManager::ValidateTradeRequest(const MqlTradeRequest &request)
{
    // Basic validation
    if(request.symbol == "") return false;
    if(request.volume <= 0) return false;
    if(request.action < 0) return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Get connection status string                                   |
//+------------------------------------------------------------------+
string CBrokerConnectionManager::GetConnectionStatusString(const ENUM_CONNECTION_STATUS status)
{
    switch(status)
    {
        case CONNECTION_UNKNOWN: return "UNKNOWN";
        case CONNECTION_CONNECTED: return "CONNECTED";
        case CONNECTION_DISCONNECTED: return "DISCONNECTED";
        case CONNECTION_UNSTABLE: return "UNSTABLE";
        case CONNECTION_RECONNECTING: return "RECONNECTING";
        case CONNECTION_FAILED: return "FAILED";
        default: return "INVALID";
    }
}

//+------------------------------------------------------------------+
//| Clear all pending requests                                     |
//+------------------------------------------------------------------+
void CBrokerConnectionManager::ClearPendingRequests(void)
{
    m_pendingRequestCount = 0;
    CEnhancedErrorHandler::LogError(ERROR_INFO, "BrokerConnectionManager", 
                                   "All pending requests cleared");
}

#endif // CORE_BROKER_CONNECTION_MANAGER_MQH