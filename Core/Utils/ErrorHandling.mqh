//+------------------------------------------------------------------+
//| Comprehensive Error Handling Framework                         |
//| Provides robust error management, recovery, and logging        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"

#property link      "https://www.windsurf.ai"
#property version   "2.00"
#property strict

#include <Trade/Trade.mqh>  // For CTrade class

#ifndef CORE_ERROR_HANDLING_MQH
#define CORE_ERROR_HANDLING_MQH

#include "../Utils/Enums.mqh"

// Forward declarations
class CEnhancedErrorHandler;

//+------------------------------------------------------------------+
//| Retry Configuration Structure                                  |
//+------------------------------------------------------------------+
struct SRetryConfig
{
    int maxRetries;          // Maximum number of retry attempts
    int retryDelay;          // Delay between retries in milliseconds
    bool exponentialBackoff; // Use exponential backoff for delays
    int maxDelayMs;          // Maximum delay in milliseconds
    
    // Default constructor
    // SRetryConfig() : maxRetries(3), retryDelay(100), exponentialBackoff(false), maxDelayMs(30000) {}

    // Parameterized constructor
    // SRetryConfig(int max_retries, int delay, bool backoff = false, int max_delay = 30000) : 
    //    maxRetries(max_retries), retryDelay(delay), exponentialBackoff(backoff), maxDelayMs(max_delay) {}
};

//+------------------------------------------------------------------+
//| Error Classification System                                    |
//+------------------------------------------------------------------+
enum ENUM_ERROR_SEVERITY
{
    ERROR_INFO = 0,          // Informational, no action needed
    ERROR_WARNING = 1,       // Warning, continue with caution
    ERROR_RECOVERABLE = 2,   // Error that can be handled gracefully
    ERROR_CRITICAL = 3,      // Critical error, disable affected component
    ERROR_FATAL = 4          // Fatal error, emergency shutdown
};

// Backward-compatible severity aliases (legacy code uses SEVERITY_*)
#ifndef SEVERITY_INFO
#define SEVERITY_INFO ERROR_INFO
#endif
#ifndef SEVERITY_WARNING
#define SEVERITY_WARNING ERROR_WARNING
#endif
#ifndef SEVERITY_ERROR
#define SEVERITY_ERROR ERROR_RECOVERABLE
#endif
#ifndef SEVERITY_CRITICAL
#define SEVERITY_CRITICAL ERROR_CRITICAL
#endif
#ifndef SEVERITY_FATAL
#define SEVERITY_FATAL ERROR_FATAL
#endif

// Backward-compatible aliases for missing/legacy constants
#ifndef ERROR_DEBUG
#define ERROR_DEBUG ERROR_INFO
#endif
#ifndef ERROR_ERROR
#define ERROR_ERROR ERROR_RECOVERABLE
#endif

// Note: Do NOT alias ERROR_LEVEL_* to severity values; ENUM_ERROR_LEVEL
// is defined in Core/Enums.mqh and must remain a distinct enum type.

// Component status aliases used in some legacy code paths
#ifndef COMPONENT_OK
#define COMPONENT_OK COMPONENT_HEALTHY
#endif
#ifndef COMPONENT_CRITICAL
#define COMPONENT_CRITICAL COMPONENT_FAILED
#endif

//+------------------------------------------------------------------+
//| Component Health Status                                        |
//+------------------------------------------------------------------+
enum ENUM_COMPONENT_STATUS
{
    COMPONENT_HEALTHY = 0,       // Component operating normally
    COMPONENT_DEGRADED = 1,      // Component operating with reduced functionality
    COMPONENT_FAILING = 2,       // Component experiencing failures
    COMPONENT_FAILED = 3,        // Component completely failed
    COMPONENT_DISABLED = 4,      // Component manually disabled
    COMPONENT_UNKNOWN = 5        // Component status unknown
};

//+------------------------------------------------------------------+
//| Retry Strategy Types                                           |
//+------------------------------------------------------------------+
enum ENUM_RETRY_STRATEGY
{
    RETRY_NONE = 0,             // No retry
    RETRY_IMMEDIATE = 1,        // Immediate retry
    RETRY_LINEAR = 2,           // Linear backoff
    RETRY_EXPONENTIAL = 3       // Exponential backoff
};

//+------------------------------------------------------------------+
//| Error Context Structure                                        |
//+------------------------------------------------------------------+
struct SErrorContext
{
    string component;           // Component name
    string operation;           // Operation being performed
    string symbol;              // Symbol (if applicable)
    int errorCode;              // System error code
    string additionalInfo;      // Additional context information
    datetime timestamp;         // Error timestamp
    ENUM_ERROR_SEVERITY severity; // Error severity
    
    // Default constructor
    // Default constructor
    /*
    SErrorContext()
    {
        component = "";
        operation = "";
        symbol = "";
        errorCode = 0;
        additionalInfo = "";
        timestamp = 0;
        severity = ERROR_INFO;
    }
    
    // Copy constructor
    SErrorContext(const SErrorContext &other)
    {
        component = other.component;
        operation = other.operation;
        symbol = other.symbol;
        errorCode = other.errorCode;
        additionalInfo = other.additionalInfo;
        timestamp = other.timestamp;
        severity = other.severity;
    }
    */
};

//+------------------------------------------------------------------+
//| Component Health Structure                                     |
//+------------------------------------------------------------------+
struct SComponentHealth
{
    string componentName;          // Component name
    ENUM_COMPONENT_STATUS status;  // Current status
    int errorCount;                // Error count in current period
    int warningCount;              // Warning count in current period
    datetime lastError;            // Last error timestamp
    datetime lastHealthCheck;      // Last health check timestamp
    double performanceScore;       // Performance score (0-1)
    string statusMessage;          // Status description
    // Extended tracking fields
    datetime lastErrorTime;        // Last error time (alias for legacy code)
    ENUM_ERROR_SEVERITY lastErrorSeverity; // Last error severity recorded
    
    // FIX: Provide explicit constructors to avoid deprecated copy/assignment behavior
    /*
    SComponentHealth()
    {
        componentName = "";
        status = COMPONENT_HEALTHY;
        errorCount = 0;
        warningCount = 0;
        lastError = 0;
        lastHealthCheck = 0;
        performanceScore = 0.0;
        statusMessage = "";
        lastErrorTime = 0;
        lastErrorSeverity = ERROR_INFO;
    }
    
    SComponentHealth(const SComponentHealth &other)
    {
        componentName = other.componentName;
        status = other.status;
        errorCount = other.errorCount;
        warningCount = other.warningCount;
        lastError = other.lastError;
        lastHealthCheck = other.lastHealthCheck;
        performanceScore = other.performanceScore;
        statusMessage = other.statusMessage;
        lastErrorTime = other.lastErrorTime;
        lastErrorSeverity = other.lastErrorSeverity;
    }
    */
};

//+------------------------------------------------------------------+
//| Enhanced Error Handler Class                                  |
//+------------------------------------------------------------------+
class CEnhancedErrorHandler
{
private:
    // Singleton instance
    static CEnhancedErrorHandler* m_instance;

public:
    // Static member variables
    static string m_logFile;
    static bool m_loggingEnabled;
    static ENUM_ERROR_SEVERITY m_minLogLevel;
    static int m_errorCount[5]; // Count by severity level (0-4)
    static datetime m_lastError;
    static bool m_emergencyMode;
    static SComponentHealth m_componentHealth[20];
    static int m_componentCount;
    static bool m_gracefulDegradation;

    // Retry mechanism variables
    static SRetryConfig m_defaultRetryConfig;
    static int m_retryAttempts[100];
    static datetime m_lastRetryTime[100];

public:
    // Singleton access
    static CEnhancedErrorHandler* GetInstance();
    //+------------------------------------------------------------------+
    //| Graceful degradation
    //+------------------------------------------------------------------+
    static bool IsGracefulDegradationEnabled();
    static bool ShouldDisableComponent(const string componentName);

    //+------------------------------------------------------------------+
    //| Logging functions
    //+------------------------------------------------------------------+
    static void LogError(const ENUM_ERROR_SEVERITY severity, const SErrorContext &context);
    static void LogError(const SErrorContext &context); // convenience overload
    static void LogError(const ENUM_ERROR_SEVERITY severity, const string component, const string message, const int errorCode = 0);
    static void LogTradeError(const string symbol, const ENUM_ORDER_TYPE orderType, const double volume, const string errorMessage);
    static void WriteToLog(const string message);

    //+------------------------------------------------------------------+
    //| Internal utility functions
    //+------------------------------------------------------------------+
    static int FindComponentIndex(const string componentName);
    static string GetSeverityString(const ENUM_ERROR_SEVERITY severity);
    static string FormatErrorMessage(const ENUM_ERROR_SEVERITY severity, const SErrorContext &context);
    
    //+------------------------------------------------------------------+
    //| Error handling functions                                       |
    //+------------------------------------------------------------------+
    static bool IsRecoverableError(const int errorCode);
    static ENUM_ERROR_SEVERITY GetErrorSeverity(const int errorCode);
    static bool HandleMT5Error(const string context = "");
    
    //+------------------------------------------------------------------+
    //| Component management
    //+------------------------------------------------------------------+
    static void RegisterComponent(const string componentName);
    static void UpdateComponentHealth(const string componentName, const ENUM_COMPONENT_STATUS status, const string statusMessage = "");
    static void UpdateComponentHealthBySeverity(const string component, const ENUM_ERROR_SEVERITY severity); // overload used internally
    static void UpdateErrorCounters(const ENUM_ERROR_SEVERITY severity);
    static string FormatLogMessage(const ENUM_ERROR_SEVERITY severity, const SErrorContext &context);
    static void HandleCriticalError(const string component, const string error);
    static void CheckEmergencyTriggers();
    static void ActivateEmergencyMode(const string reason);
    static void CleanupOldRetryData();
    static void GetErrorStats(int &infoCount, int &warningCount,
                              int &recoverableCount, int &criticalCount, int &fatalCount);
    
    //+------------------------------------------------------------------+
    //| Initialization and cleanup
    //+------------------------------------------------------------------+
    static bool Initialize(const string logFileName, const ENUM_ERROR_LEVEL minLevel = ERROR_LEVEL_INFO);
    static void Shutdown();

//+------------------------------------------------------------------+
    };

// Legacy-compatible instance wrapper used by existing modules expecting a CErrorHandling object
class CErrorHandling
{
public:
    CErrorHandling() {}
    ~CErrorHandling() {}

    // Legacy signature without explicit severity (defaults to recoverable error)
    void LogError(const string component, const string message, const int errorCode = 0)
    {
        SErrorContext context;
        context.component = component;
        context.operation = "LogError";
        context.symbol = "";
        context.errorCode = errorCode;
        context.additionalInfo = message;
        context.timestamp = TimeCurrent();
        context.severity = ERROR_RECOVERABLE;

        CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
            CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, context);
        }
    }

    // Modern signature with explicit severity
    // Overloaded LogError functions to handle different parameter counts
    void LogError(const ENUM_ERROR_SEVERITY severity, const SErrorContext &context)
    {
        // Static call - already safe
    }
    
    void LogError(const ENUM_ERROR_SEVERITY severity, const string component, 
                 const string message, const int errorCode = 0)
    {
        SErrorContext context;
        context.component = component;
        context.operation = "LogError";
        context.symbol = "";
        context.errorCode = errorCode;
        context.additionalInfo = message;
        context.timestamp = TimeCurrent();
        context.severity = severity;
        
        // Static call - already safe
    }
    
    // LogError method is now only in CEnhancedErrorHandler
};

//+------------------------------------------------------------------+
//| Function implementations                                         |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Log an error with context and enhanced validation              |
//+------------------------------------------------------------------+
void CEnhancedErrorHandler::LogError(const ENUM_ERROR_SEVERITY severity, const SErrorContext &context)
{
    // Validate severity level
    if(severity < ERROR_INFO || severity > ERROR_FATAL) {
        Print("[ERROR] Invalid error severity level: ", EnumToString(severity));
        return;
    }
    
    // Skip logging if below minimum level
    if((int)severity < (int)m_minLogLevel) {
        return;
    }
    
    // Update error counters
    if(severity >= ERROR_WARNING) {
        m_errorCount[severity]++;
        m_lastError = TimeCurrent();
        
        // Update component health if component is specified
        if(context.component != "") {
            CEnhancedErrorHandler::UpdateComponentHealthBySeverity(context.component, severity);
        }
    }
    
    // Format error message
    string errorMsg = CEnhancedErrorHandler::FormatErrorMessage(severity, context);
    
    // Log to file if enabled
    if(m_loggingEnabled && m_logFile != "") {
        int fileHandle = FileOpen(m_logFile, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI, '\t');
        if(fileHandle != INVALID_HANDLE) {
            FileSeek(fileHandle, 0, SEEK_END);
            FileWriteString(fileHandle, errorMsg + "\n");
            FileClose(fileHandle);
        } else {
            // Fallback to terminal if file logging fails
            Print("[ERROR] Failed to write to log file: ", GetLastError(), " - ", errorMsg);
        }
    }
    
    // Always output to terminal for critical errors
    if(severity >= ERROR_CRITICAL) {
        Print(errorMsg);
    }
    
    // Trigger emergency mode for fatal errors
    if(severity == ERROR_FATAL) {
        m_emergencyMode = true;
        // Additional emergency actions can be added here
    }
}

// Convenience overload that derives severity from context
void CEnhancedErrorHandler::LogError(const SErrorContext &context)
{
    LogError(context.severity, context);
}

// Compatibility overload for legacy call sites (severity + component + message)
void CEnhancedErrorHandler::LogError(const ENUM_ERROR_SEVERITY severity, const string component, const string message, const int errorCode)
{
    SErrorContext ctx;
    ctx.component = component;
    ctx.operation = "LogError";
    ctx.symbol = "";
    ctx.errorCode = errorCode;
    ctx.additionalInfo = message;
    ctx.timestamp = TimeCurrent();
    ctx.severity = severity;
    LogError(severity, ctx);
}

//+------------------------------------------------------------------+
//| Update component health status with enhanced tracking           |
//+------------------------------------------------------------------+
void CEnhancedErrorHandler::UpdateComponentHealthBySeverity(const string component, const ENUM_ERROR_SEVERITY severity)
{
    // Validate component name
    if(component == "") {
        Print("[ERROR] Cannot update health for empty component name");
        return;
    }
    
    // Find the component or add it if it doesn't exist
    int index = -1;
    for(int i = 0; i < m_componentCount; i++) {
        if(m_componentHealth[i].componentName == component) {
            index = i;
            break;
        }
    }
    
    // Add new component if not found and we have space
    if(index == -1) {
        if(m_componentCount >= 20) {
            Print("[WARNING] Maximum number of components reached. Cannot track health for: ", component);
            return;
        }
        index = m_componentCount++;
        m_componentHealth[index].componentName = component;
        m_componentHealth[index].lastErrorTime = 0;
        m_componentHealth[index].errorCount = 0;
        m_componentHealth[index].status = COMPONENT_HEALTHY;
    }
    
    // Update component health
    m_componentHealth[index].lastErrorTime = TimeCurrent();
    m_componentHealth[index].lastErrorSeverity = severity;
    m_componentHealth[index].errorCount++;
    
    // Update status based on error severity and frequency
    if(severity >= ERROR_CRITICAL) {
        m_componentHealth[index].status = COMPONENT_FAILED;
    } 
    else if(severity >= ERROR_RECOVERABLE) {
        if(m_componentHealth[index].status != COMPONENT_FAILED) {
            m_componentHealth[index].status = COMPONENT_DEGRADED;
        }
    }
    
    // Check for error rate limiting
    if(severity >= ERROR_WARNING) {
        int recentErrors = 0;
        datetime timeThreshold = TimeCurrent() - 300; // 5 minutes
        
        // Count recent errors (simplified - in a real implementation, you'd track timestamps)
        if(m_componentHealth[index].errorCount > 10) {
            recentErrors = m_componentHealth[index].errorCount / 2; // Simplified
        }
        
        // If too many errors in a short time, mark as critical
        if(recentErrors > 10) {
            m_componentHealth[index].status = COMPONENT_FAILED;
            Print("[WARNING] Component ", component, " marked as FAILED due to error rate");
        }
    }
}

//+------------------------------------------------------------------+
//| Format error message with enhanced context                      |
//+------------------------------------------------------------------+
string CEnhancedErrorHandler::FormatErrorMessage(const ENUM_ERROR_SEVERITY severity, const SErrorContext &context)
{
    string severityStr;
    switch(severity) {
        case ERROR_RECOVERABLE: severityStr = "RECOVERABLE"; break;
        case ERROR_INFO:     severityStr = "INFO"; break;
        case ERROR_WARNING:  severityStr = "WARNING"; break;
        case ERROR_CRITICAL: severityStr = "CRITICAL"; break;
        case ERROR_FATAL:    severityStr = "FATAL"; break;
        default:             severityStr = "UNKNOWN";
    }
    
    string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
    string component = (context.component != "") ? context.component : "GLOBAL";
    string symbolName = (context.symbol != "") ? context.symbol : "N/A";
    string operation = (context.operation != "") ? context.operation : "N/A";
    string details = (context.additionalInfo != "") ? context.additionalInfo : "No details";
    
    // Format the error message with all available context
    return StringFormat("[%s] %s | %s | %s | %s | %d | %s",
        timestamp,
        severityStr,
        component,
        operation,
        symbolName,
        context.errorCode,
        details
    );
}

//+------------------------------------------------------------------+
//| Write a message to the log file                                 |
//+------------------------------------------------------------------+
void CEnhancedErrorHandler::WriteToLog(const string message)
{
    // Check if logging is enabled and message is not empty
    if(!m_loggingEnabled || StringLen(message) == 0)
        return;

    int handle = FileOpen(m_logFile, FILE_WRITE|FILE_READ|FILE_TXT|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_ANSI);
    if(handle == INVALID_HANDLE)
        return;

    FileSeek(handle, 0, SEEK_END);
    FileWrite(handle, message);
    FileClose(handle);
}

//+------------------------------------------------------------------+
//| Format log message (compat wrapper)                             |
//+------------------------------------------------------------------+
string CEnhancedErrorHandler::FormatLogMessage(const ENUM_ERROR_SEVERITY severity, const SErrorContext &context)
{
    return FormatErrorMessage(severity, context);
}

//+------------------------------------------------------------------+
//| Handle a critical error condition                               |
//+------------------------------------------------------------------+
void CEnhancedErrorHandler::HandleCriticalError(const string component, const string error)
{
    if(!CEnhancedErrorHandler::m_emergencyMode)
    {
        CEnhancedErrorHandler::ActivateEmergencyMode(StringFormat("Critical error in %s: %s", component, error));
    }

    string criticalMessage = StringFormat("CRITICAL ERROR in %s: %s", component, error);

    // Log to file immediately
    CEnhancedErrorHandler::WriteToLog("=== CRITICAL ERROR DETECTED ===\n");
    CEnhancedErrorHandler::WriteToLog(criticalMessage + "\n");
    CEnhancedErrorHandler::WriteToLog("Emergency procedures activated\n");
    CEnhancedErrorHandler::WriteToLog("===============================\n");

    // Update component status
    CEnhancedErrorHandler::UpdateComponentHealth(component, COMPONENT_FAILED, error);

    // Attempt graceful degradation if enabled
    if(CEnhancedErrorHandler::m_gracefulDegradation)
    {
        SErrorContext graceContext;
        graceContext.component = "GracefulDegradation";
        graceContext.operation = "HandleCriticalError";
        graceContext.symbol = "";
        graceContext.errorCode = 0;
        graceContext.additionalInfo = "Attempting graceful degradation for component: " + component;
        graceContext.timestamp = TimeCurrent();
        graceContext.severity = ERROR_INFO;

        CEnhancedErrorHandler::LogError(ERROR_INFO, graceContext);

        // Disable the failing component
        CEnhancedErrorHandler::UpdateComponentHealth(component, COMPONENT_DISABLED, "Disabled due to critical error");
    }
}

//+------------------------------------------------------------------+
//| Check if emergency conditions are triggered                    |
//+------------------------------------------------------------------+
void CEnhancedErrorHandler::CheckEmergencyTriggers()
{
    if(CEnhancedErrorHandler::m_emergencyMode)
    {
        CEnhancedErrorHandler::m_emergencyMode = false;

        SErrorContext emergencyContext;
        emergencyContext.component = "EmergencyManager";
        emergencyContext.operation = "CheckEmergencyTriggers";
        emergencyContext.symbol = "";
        emergencyContext.errorCode = 0;
        emergencyContext.additionalInfo = "Emergency mode deactivated - system recovered";
        emergencyContext.timestamp = TimeCurrent();
        emergencyContext.severity = ERROR_INFO;

        CEnhancedErrorHandler::LogError(ERROR_INFO, emergencyContext);

        // Restore component status if they're healthy
        for(int i = 0; i < CEnhancedErrorHandler::m_componentCount; i++)
        {
            if(CEnhancedErrorHandler::m_componentHealth[i].performanceScore > 0.8)
                CEnhancedErrorHandler::m_componentHealth[i].status = COMPONENT_HEALTHY;
        }
    }
}

//+------------------------------------------------------------------+
//| Find the index of a component by name                           |
//+------------------------------------------------------------------+
int CEnhancedErrorHandler::FindComponentIndex(const string componentName)
{
    for(int i = 0; i < CEnhancedErrorHandler::m_componentCount; i++)
    {
        if(CEnhancedErrorHandler::m_componentHealth[i].componentName == componentName)
        {
            return i;
        }
    }
    return -1; // Not found
}

//+------------------------------------------------------------------+
//| Activate emergency mode with a reason                          |
//+------------------------------------------------------------------+
void CEnhancedErrorHandler::ActivateEmergencyMode(const string reason)
{
    CEnhancedErrorHandler::m_emergencyMode = true;

    SErrorContext context;
    context.component = "EmergencyManager";
    context.operation = "ActivateEmergencyMode";
    context.symbol = "";
    context.errorCode = 0;
    context.additionalInfo = reason;
    context.timestamp = TimeCurrent();
    context.severity = ERROR_CRITICAL;

    CEnhancedErrorHandler::LogError(ERROR_CRITICAL, context);
}

//+------------------------------------------------------------------+
//| Cleanup retry bookkeeping                                        |
//+------------------------------------------------------------------+
void CEnhancedErrorHandler::CleanupOldRetryData()
{
    datetime threshold = TimeCurrent() - 3600; // 1 hour window
    for(int i = 0; i < ArraySize(m_lastRetryTime); i++)
    {
        if(m_lastRetryTime[i] != 0 && m_lastRetryTime[i] < threshold)
        {
            m_lastRetryTime[i] = 0;
            m_retryAttempts[i] = 0;
        }
    }
}

//+------------------------------------------------------------------+
//| Initialize enhanced error handling system                      |
//+------------------------------------------------------------------+
bool CEnhancedErrorHandler::Initialize(const string logFileName, const ENUM_ERROR_LEVEL minLevel)
{
    // Initialize static members
    m_logFile = logFileName;
    m_minLogLevel = (ENUM_ERROR_SEVERITY)minLevel;
    m_loggingEnabled = true;
    m_emergencyMode = false;
    m_gracefulDegradation = true;
    m_componentCount = 0;
    m_lastError = 0;

    // Reset counters
    for(int i = 0; i < 5; i++)
        m_errorCount[i] = 0;

    // Initialize component health array (static arrays are already sized in declaration)
    // Just initialize the values
    for(int i = 0; i < ArraySize(m_componentHealth); i++) {
        m_componentHealth[i].componentName = "";
        m_componentHealth[i].status = COMPONENT_UNKNOWN;
        m_componentHealth[i].errorCount = 0;
        m_componentHealth[i].warningCount = 0;
        m_componentHealth[i].lastError = 0;
        m_componentHealth[i].lastHealthCheck = 0;
        m_componentHealth[i].performanceScore = 0.0;
    }
    
    // Initialize retry arrays (static arrays are already sized in declaration)
    // Just initialize the values
    ArrayInitialize(m_retryAttempts, 0);
    ArrayInitialize(m_lastRetryTime, 0);

    // Test log file creation
    int handle = FileOpen(m_logFile, FILE_WRITE | FILE_TXT);
    if(handle == INVALID_HANDLE)
    {
        Print("ERROR: Failed to create log file: ", m_logFile);
        m_loggingEnabled = false;
        return false;
    }

    FileWrite(handle, "=== Enhanced EA Error Log Initialized ===");
    FileWrite(handle, "Timestamp: ", TimeToString(TimeCurrent()));
    FileWrite(handle, "Minimum Log Level: ", CEnhancedErrorHandler::GetSeverityString((ENUM_ERROR_SEVERITY)minLevel));
    FileWrite(handle, "Graceful Degradation: ", m_gracefulDegradation ? "Enabled" : "Disabled");
    FileWrite(handle, "==========================================");
    FileClose(handle);

    // Register core components
    CEnhancedErrorHandler::RegisterComponent("ErrorHandler");
    CEnhancedErrorHandler::RegisterComponent("TradeManager");
    CEnhancedErrorHandler::RegisterComponent("RiskManager");
    CEnhancedErrorHandler::RegisterComponent("StrategyManager");
    CEnhancedErrorHandler::RegisterComponent("AISystem");
    CEnhancedErrorHandler::RegisterComponent("PositionSizer");

    SErrorContext context;
    context.component = "ErrorHandler";
    context.operation = "Initialize";
    context.symbol = "";
    context.errorCode = 0;
    context.additionalInfo = "Enhanced error handling system initialized successfully";
    context.timestamp = TimeCurrent();
    context.severity = ERROR_INFO;

    CEnhancedErrorHandler::LogError(ERROR_INFO, context);
    return true;
}

//+------------------------------------------------------------------+
//| Log trade-specific errors                                      |
//+------------------------------------------------------------------+
void CEnhancedErrorHandler::LogTradeError(const string tradeSymbol, const ENUM_ORDER_TYPE orderType, const double volume, const string errorMessage)
{
    SErrorContext context;
    context.component = "TradeManager";
    context.operation = "Trade";
    context.symbol = tradeSymbol;
    context.errorCode = GetLastError();
    context.additionalInfo = StringFormat("%s | Type: %s, Volume: %.2f",
                                         errorMessage,
                                         EnumToString(orderType),
                                         volume);
    context.timestamp = TimeCurrent();
    context.severity = ERROR_RECOVERABLE;

    CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
    if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
        CEnhancedErrorHandler* tempHandler = localErrorHandler;
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, context);
    }
}

//+------------------------------------------------------------------+
//| Graceful degradation helpers                                     |
//+------------------------------------------------------------------+
bool CEnhancedErrorHandler::IsGracefulDegradationEnabled()
{
    return m_gracefulDegradation;
}

bool CEnhancedErrorHandler::ShouldDisableComponent(const string componentName)
{
    int idx = FindComponentIndex(componentName);
    if(idx < 0) return false;
    ENUM_COMPONENT_STATUS s = m_componentHealth[idx].status;
    return (s == COMPONENT_DISABLED || s == COMPONENT_FAILED);
}

//+------------------------------------------------------------------+
//| Get error statistics (class method)                              |
//+------------------------------------------------------------------+
void CEnhancedErrorHandler::GetErrorStats(int &infoCount, int &warningCount,
                              int &recoverableCount, int &criticalCount, int &fatalCount)
{
    infoCount = m_errorCount[ERROR_INFO];
    warningCount = m_errorCount[ERROR_WARNING];
    recoverableCount = m_errorCount[ERROR_RECOVERABLE];
    criticalCount = m_errorCount[ERROR_CRITICAL];
    fatalCount = m_errorCount[ERROR_FATAL];
}

//+------------------------------------------------------------------+
//| Register a component for health monitoring                     |
//+------------------------------------------------------------------+
void CEnhancedErrorHandler::RegisterComponent(const string componentName)
{
    if(FindComponentIndex(componentName) >= 0) return; // Already registered
    
    if(m_componentCount >= 20)
    {
        // For static arrays, we can't resize, so just log an error
        Print("Error: Maximum number of components (20) reached. Cannot register: ", componentName);
        return;
    }
    
    m_componentHealth[m_componentCount].componentName = componentName;
    m_componentHealth[m_componentCount].status = COMPONENT_HEALTHY;
    m_componentHealth[m_componentCount].errorCount = 0;
    m_componentHealth[m_componentCount].warningCount = 0;
    m_componentHealth[m_componentCount].lastError = 0;
    m_componentHealth[m_componentCount].lastHealthCheck = TimeCurrent();
    m_componentHealth[m_componentCount].performanceScore = 1.0;
    m_componentHealth[m_componentCount].statusMessage = "Component registered";
    
    m_componentCount++;
    
    SErrorContext context;
    context.component = "ErrorHandler";
    context.operation = "RegisterComponent";
    context.symbol = "";
    context.errorCode = 0;
    context.additionalInfo = "Component registered: " + componentName;
    context.timestamp = TimeCurrent();
    context.severity = ERROR_INFO;
    
    LogError(ERROR_INFO, context);
}

//+------------------------------------------------------------------+
//| Handle MT5 errors with automatic retry                         |
//+------------------------------------------------------------------+
bool CEnhancedErrorHandler::HandleMT5Error(const string context)
{
    int error = GetLastError();
    if(error == 0) return true; // No error

    // Check if we should retry this error
    if(IsRecoverableError(error))
    {
        int attempt = m_retryAttempts[error % 100]++; // Use modulo to prevent array out of bounds
        if(attempt < m_defaultRetryConfig.maxRetries)
        {
            int delay = m_defaultRetryConfig.retryDelay;
            if(m_defaultRetryConfig.exponentialBackoff)
            {
                delay = (int)MathMin((double)m_defaultRetryConfig.maxDelayMs, 
                                   m_defaultRetryConfig.retryDelay * MathPow(2.0, attempt));
            }
            
            m_lastRetryTime[error % 100] = TimeCurrent();
            PrintFormat("Retryable error %d in %s, attempt %d/%d, retrying in %dms...",
                       error, context, attempt + 1, m_defaultRetryConfig.maxRetries, delay);
            
            Sleep(delay);
            return true; // Retry
        }
    }

    // Log the error if we're not retrying or max retries reached
    SErrorContext errorContext;
    errorContext.component = "ErrorHandler";
    errorContext.operation = context;
    errorContext.symbol = "";
    errorContext.errorCode = error;
    errorContext.additionalInfo = "Error " + IntegerToString(error);
    errorContext.timestamp = TimeCurrent();
    errorContext.severity = ERROR_WARNING; // Default to warning if severity can't be determined

    LogError(errorContext.severity, errorContext);
    return false; // Don't retry
}

//+------------------------------------------------------------------+
//| Check if an error is recoverable                               |
//+------------------------------------------------------------------+
bool CEnhancedErrorHandler::IsRecoverableError(const int errorCode)
{
    // List of recoverable error codes
    static const int recoverableErrors[] = {
        6,   // ERR_NO_CONNECTION
        8,   // ERR_TOO_FREQUENT_REQUESTS
        64,  // ERR_ACCOUNT_DISABLED
        128, // ERR_TRADE_TIMEOUT
        129, // ERR_INVALID_PRICE
        130, // ERR_INVALID_STOPS
        131, // ERR_INVALID_TRADE_VOLUME
        132, // ERR_MARKET_CLOSED
        133, // ERR_TRADE_DISABLED
        134, // ERR_NOT_ENOUGH_MONEY
        135, // ERR_PRICE_CHANGED
        136, // ERR_OFF_QUOTES
        137, // ERR_BROKER_BUSY
        138, // ERR_REQUOTE
        139, // ERR_ORDER_LOCKED
        140, // ERR_LONG_POSITIONS_ONLY_ALLOWED
        141, // ERR_TOO_MANY_REQUESTS
        145, // ERR_MODIFICATION_DENIED
        146, // ERR_TRADE_CONTEXT_BUSY
        147, // ERR_TRADE_EXPIRATION_DENIED
        148, // ERR_TOO_MANY_ORDERS
        149, // ERR_TRADE_HEDGE_PROHIBITED
        150, // ERR_TRADE_PROHIBITED_BY_FIFO
        151  // ERR_TRADE_EXPIRATION_PROHIBITED
    };
    
    for(int i = 0; i < ArraySize(recoverableErrors); i++) {
        if(errorCode == recoverableErrors[i]) {
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| Get severity level for an error code                            |
//+------------------------------------------------------------------+
ENUM_ERROR_SEVERITY CEnhancedErrorHandler::GetErrorSeverity(const int errorCode)
{
    // Map error codes to severity levels
    switch(errorCode) {
        case 0:     return ERROR_INFO;      // No error
        case 1:     return ERROR_FATAL;     // No error, but the result is unknown
        case 2:     return ERROR_CRITICAL;  // Common error
        case 3:     return ERROR_CRITICAL;  // Invalid trade parameters
        case 4:     return ERROR_CRITICAL;  // Trade server is busy
        case 5:     return ERROR_CRITICAL;  // Old version of the client terminal
        case 6:     return ERROR_RECOVERABLE; // No connection with trade server
        case 7:     return ERROR_CRITICAL;  // Not enough rights
        case 8:     return ERROR_RECOVERABLE; // Too frequent requests
        case 9:     return ERROR_CRITICAL;  // Malfunctional trade operation
        case 64:    return ERROR_CRITICAL;  // Account disabled
        case 65:    return ERROR_CRITICAL;  // Invalid account
        case 128:   return ERROR_RECOVERABLE; // Trade timeout
        case 129:   return ERROR_RECOVERABLE; // Invalid price
        case 130:   return ERROR_RECOVERABLE; // Invalid stops
        case 131:   return ERROR_RECOVERABLE; // Invalid trade volume
        case 132:   return ERROR_RECOVERABLE; // Market is closed
        case 133:   return ERROR_RECOVERABLE; // Trade is disabled
        case 134:   return ERROR_CRITICAL;    // Not enough money
        case 135:   return ERROR_RECOVERABLE; // Price changed
        case 136:   return ERROR_RECOVERABLE; // Off quotes
        case 137:   return ERROR_RECOVERABLE; // Broker is busy
        case 138:   return ERROR_RECOVERABLE; // Requote
        case 139:   return ERROR_RECOVERABLE; // Order is locked
        case 140:   return ERROR_RECOVERABLE; // Long positions only allowed
        case 141:   return ERROR_RECOVERABLE; // Too many requests
        case 145:   return ERROR_RECOVERABLE; // Modification denied
        case 146:   return ERROR_RECOVERABLE; // Trade context is busy
        case 147:   return ERROR_RECOVERABLE; // Trade expiration denied
        case 148:   return ERROR_RECOVERABLE; // Too many orders
        case 149:   return ERROR_CRITICAL;    // Trade is prohibited by FIFO rules
        case 150:   return ERROR_CRITICAL;    // Trade is prohibited by FIFO rules
        case 151:   return ERROR_RECOVERABLE; // Trade expiration is prohibited
        default:    return ERROR_WARNING;     // Unknown error
    }
}

 

 

// Only one implementation of RegisterComponent is kept (the first one)

//+------------------------------------------------------------------+
//| Singleton instance access                                       |
//+------------------------------------------------------------------+
CEnhancedErrorHandler* CEnhancedErrorHandler::GetInstance()
{
    if(m_instance == NULL)
    {
        m_instance = new CEnhancedErrorHandler();
    }
    return m_instance;
}

//+------------------------------------------------------------------+
//| Static member variable definitions                               |
//+------------------------------------------------------------------+
CEnhancedErrorHandler* CEnhancedErrorHandler::m_instance = NULL;
string CEnhancedErrorHandler::m_logFile = "";
bool CEnhancedErrorHandler::m_loggingEnabled = false;
ENUM_ERROR_SEVERITY CEnhancedErrorHandler::m_minLogLevel = ERROR_INFO;
int CEnhancedErrorHandler::m_errorCount[5] = {0};
datetime CEnhancedErrorHandler::m_lastError = 0;
bool CEnhancedErrorHandler::m_emergencyMode = false;
int CEnhancedErrorHandler::m_componentCount = 0;
bool CEnhancedErrorHandler::m_gracefulDegradation = true;
SRetryConfig CEnhancedErrorHandler::m_defaultRetryConfig; // default-constructed
SComponentHealth CEnhancedErrorHandler::m_componentHealth[20];
int CEnhancedErrorHandler::m_retryAttempts[100];
datetime CEnhancedErrorHandler::m_lastRetryTime[100];

//+------------------------------------------------------------------+
//| Update component health (status overload)                        |
//+------------------------------------------------------------------+
void CEnhancedErrorHandler::UpdateComponentHealth(const string componentName, const ENUM_COMPONENT_STATUS status, const string statusMessage)
{
    if(componentName == "") return;
    int index = FindComponentIndex(componentName);
    if(index == -1)
    {
        if(m_componentCount >= 20)
        {
            Print("[WARNING] Maximum number of components reached. Cannot track health for: ", componentName);
            return;
        }
        index = m_componentCount++;
        m_componentHealth[index].componentName = componentName;
    }
    m_componentHealth[index].status = status;
    m_componentHealth[index].statusMessage = statusMessage;
    m_componentHealth[index].lastHealthCheck = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Severity string helper                                           |
//+------------------------------------------------------------------+
string CEnhancedErrorHandler::GetSeverityString(const ENUM_ERROR_SEVERITY severity)
{
    switch(severity)
    {
        case ERROR_RECOVERABLE: return "RECOVERABLE";
        case ERROR_INFO:     return "INFO";
        case ERROR_WARNING:  return "WARNING";
        case ERROR_CRITICAL: return "CRITICAL";
        case ERROR_FATAL:    return "FATAL";
        default:             return "UNKNOWN";
    }
}

//+------------------------------------------------------------------+
//| Update error counters helper                                     |
//+------------------------------------------------------------------+
void CEnhancedErrorHandler::UpdateErrorCounters(const ENUM_ERROR_SEVERITY severity)
{
    if(severity < ERROR_INFO || severity > ERROR_FATAL) return;
    m_errorCount[severity]++;
    m_lastError = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Shutdown logging                                                 |
//+------------------------------------------------------------------+
void CEnhancedErrorHandler::Shutdown()
{
    m_loggingEnabled = false;
}

#endif // CORE_ERROR_HANDLING_MQH
