//+------------------------------------------------------------------+
//| Comprehensive Error Handling Framework                           |
//| Provides robust error management, recovery, and logging        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"

#property link      "https://www.windsurf.ai"
#property version   "2.10"
#property strict

#include <Trade/Trade.mqh>  // For CTrade class

#ifndef CORE_ERROR_HANDLING_MQH
#define CORE_ERROR_HANDLING_MQH

#include "../Utils/Enums.mqh"

// Forward declarations
class CEnhancedErrorHandler;

//+------------------------------------------------------------------+
//| Logging Verbosity Levels                                         |
//+------------------------------------------------------------------+
enum ENUM_LOG_VERBOSITY
{
    VERBOSITY_SILENT = 0,       // No logging at all
    VERBOSITY_ERRORS_ONLY = 1, // Only errors and critical
    VERBOSITY_WARNING = 2,     // Errors and warnings
    VERBOSITY_NORMAL = 3,       // Normal logging (default)
    VERBOSITY_VERBOSE = 4,     // Detailed logging
    VERBOSITY_DEBUG = 5         // Debug-level logging
};

//+------------------------------------------------------------------+
//| Retry Configuration Structure                                  |
//+------------------------------------------------------------------+
struct SRetryConfig
{
    int maxRetries;          // Maximum number of retry attempts
    int retryDelay;          // Delay between retries in milliseconds
    bool exponentialBackoff; // Use exponential backoff for delays
    int maxDelayMs;          // Maximum delay in milliseconds
    
    SRetryConfig() : maxRetries(3), retryDelay(100), exponentialBackoff(false), maxDelayMs(30000) {}
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

#ifndef ERROR_DEBUG
#define ERROR_DEBUG ERROR_INFO
#endif
#ifndef ERROR_ERROR
#define ERROR_ERROR ERROR_RECOVERABLE
#endif

#ifndef COMPONENT_OK
#define COMPONENT_OK COMPONENT_HEALTHY
#endif
#ifndef COMPONENT_CRITICAL
#define COMPONENT_CRITICAL COMPONENT_FAILED
#endif

//+------------------------------------------------------------------+
//| Error Aggregation Structure                                    |
//+------------------------------------------------------------------+
struct SErrorAggregation
{
    int errorCode;
    int count;
    datetime firstOccurrence;
    datetime lastOccurrence;
    ENUM_ERROR_SEVERITY maxSeverity;
    string lastComponent;
    string lastMessage;
    
    SErrorAggregation() : 
        errorCode(0), count(0), firstOccurrence(0), lastOccurrence(0), 
        maxSeverity(ERROR_INFO), lastComponent(""), lastMessage("") {}
};

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
    
    SErrorContext() :
        component(""), operation(""), symbol(""), errorCode(0),
        additionalInfo(""), timestamp(0), severity(ERROR_INFO) {}
};

//+------------------------------------------------------------------+
//| Component Health Structure                                     |
//+------------------------------------------------------------------+
struct SComponentHealth
{
    string componentName;
    ENUM_COMPONENT_STATUS status;
    int errorCount;
    int warningCount;
    datetime lastError;
    datetime lastHealthCheck;
    double performanceScore;
    string statusMessage;
    datetime lastErrorTime;
    ENUM_ERROR_SEVERITY lastErrorSeverity;
    
    SComponentHealth() :
        componentName(""), status(COMPONENT_HEALTHY), errorCount(0), warningCount(0),
        lastError(0), lastHealthCheck(0), performanceScore(0.0), statusMessage(""),
        lastErrorTime(0), lastErrorSeverity(ERROR_INFO) {}
};

//+------------------------------------------------------------------+
//| Enhanced Error Handler Class                                  |
//+------------------------------------------------------------------+
class CEnhancedErrorHandler
{
private:
    static CEnhancedErrorHandler* m_instance;

public:
    static string m_logFile;
    static bool m_loggingEnabled;
    static ENUM_ERROR_SEVERITY m_minLogLevel;
    static ENUM_LOG_VERBOSITY m_verbosityLevel;
    static int m_errorCount[5];
    static datetime m_lastError;
    static bool m_emergencyMode;
    static SComponentHealth m_componentHealth[20];
    static int m_componentCount;
    static bool m_gracefulDegradation;
    static SRetryConfig m_defaultRetryConfig;
    static int m_retryAttempts[100];
    static datetime m_lastRetryTime[100];
    
    // Error aggregation
    static SErrorAggregation m_errorAggregations[50];
    static int m_aggregationCount;
    static int m_aggregationWindowSeconds;
    static bool m_aggregationEnabled;
    
public:
    static CEnhancedErrorHandler* GetInstance();
    static bool IsGracefulDegradationEnabled();
    static bool ShouldDisableComponent(const string componentName);
    
    static void LogError(const ENUM_ERROR_SEVERITY severity, const SErrorContext &context);
    static void LogError(const SErrorContext &context);
    static void LogError(const ENUM_ERROR_SEVERITY severity, const string component, const string message, const int errorCode = 0);
    static void LogTradeError(const string symbol, const ENUM_ORDER_TYPE orderType, const double volume, const string errorMessage);
    static void WriteToLog(const string message);
    
    static void LogVerbose(const ENUM_LOG_VERBOSITY level, const string message);
    static void LogDebug(const string component, const string message);
    
    static int FindComponentIndex(const string componentName);
    static string GetSeverityString(const ENUM_ERROR_SEVERITY severity);
    static string FormatErrorMessage(const ENUM_ERROR_SEVERITY severity, const SErrorContext &context);
    
    static bool IsRecoverableError(const int errorCode);
    static ENUM_ERROR_SEVERITY GetErrorSeverity(const int errorCode);
    static bool HandleMT5Error(const string context = "");
    
    static void RegisterComponent(const string componentName);
    static void UpdateComponentHealth(const string componentName, const ENUM_COMPONENT_STATUS status, const string statusMessage = "");
    static void UpdateComponentHealthBySeverity(const string component, const ENUM_ERROR_SEVERITY severity);
    static void UpdateErrorCounters(const ENUM_ERROR_SEVERITY severity);
    static string FormatLogMessage(const ENUM_ERROR_SEVERITY severity, const SErrorContext &context);
    static void HandleCriticalError(const string component, const string error);
    static void CheckEmergencyTriggers();
    static void ActivateEmergencyMode(const string reason);
    static void CleanupOldRetryData();
    static void GetErrorStats(int &infoCount, int &warningCount,
                              int &recoverableCount, int &criticalCount, int &fatalCount);
    
    static void SetVerbosityLevel(ENUM_LOG_VERBOSITY level);
    static ENUM_LOG_VERBOSITY GetVerbosityLevel();
    static void SetAggregationEnabled(bool enabled);
    static void SetAggregationWindow(int seconds);
    static void GetAggregatedErrors(SErrorAggregation &aggregations[], int &count);
    static void ClearAggregations();
    
    static bool Initialize(const string logFileName, const ENUM_ERROR_SEVERITY minLevel = ERROR_INFO);
    static void Shutdown();
};

class CErrorHandling
{
public:
    CErrorHandling() {}
    ~CErrorHandling() {}

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

    void LogError(const ENUM_ERROR_SEVERITY severity, const SErrorContext &context) {}
    
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
    }
};

//+------------------------------------------------------------------+
//| Log an error with context and enhanced validation              |
//+------------------------------------------------------------------+
void CEnhancedErrorHandler::LogError(const ENUM_ERROR_SEVERITY severity, const SErrorContext &context)
{
    if(severity < ERROR_INFO || severity > ERROR_FATAL) {
        Print("[ERROR] Invalid error severity level: ", EnumToString(severity));
        return;
    }
    
    if((int)severity < (int)m_minLogLevel) {
        return;
    }
    
    // Error aggregation
    if(m_aggregationEnabled && severity >= ERROR_WARNING)
    {
        bool found = false;
        datetime cutoff = TimeCurrent() - m_aggregationWindowSeconds;
        
        for(int i = 0; i < m_aggregationCount; i++)
        {
            if(m_errorAggregations[i].errorCode == context.errorCode)
            {
                if(m_errorAggregations[i].lastOccurrence > cutoff)
                {
                    m_errorAggregations[i].count++;
                    m_errorAggregations[i].lastOccurrence = TimeCurrent();
                    m_errorAggregations[i].lastComponent = context.component;
                    m_errorAggregations[i].lastMessage = context.additionalInfo;
                    if(severity > m_errorAggregations[i].maxSeverity)
                        m_errorAggregations[i].maxSeverity = severity;
                    found = true;
                    break;
                }
            }
        }
        
        if(!found && m_aggregationCount < 50)
        {
            m_errorAggregations[m_aggregationCount].errorCode = context.errorCode;
            m_errorAggregations[m_aggregationCount].count = 1;
            m_errorAggregations[m_aggregationCount].firstOccurrence = TimeCurrent();
            m_errorAggregations[m_aggregationCount].lastOccurrence = TimeCurrent();
            m_errorAggregations[m_aggregationCount].maxSeverity = severity;
            m_errorAggregations[m_aggregationCount].lastComponent = context.component;
            m_errorAggregations[m_aggregationCount].lastMessage = context.additionalInfo;
            m_aggregationCount++;
        }
    }
    
    if(severity >= ERROR_WARNING) {
        m_errorCount[severity]++;
        m_lastError = TimeCurrent();
        
        if(context.component != "") {
            CEnhancedErrorHandler::UpdateComponentHealthBySeverity(context.component, severity);
        }
    }
    
    string errorMsg = CEnhancedErrorHandler::FormatErrorMessage(severity, context);
    
    if(m_loggingEnabled && m_logFile != "") {
        int fileHandle = FileOpen(m_logFile, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI, '\t');
        if(fileHandle != INVALID_HANDLE) {
            FileSeek(fileHandle, 0, SEEK_END);
            FileWriteString(fileHandle, errorMsg + "\n");
            FileClose(fileHandle);
        } else {
            Print("[ERROR] Failed to write to log file: ", GetLastError(), " - ", errorMsg);
        }
    }
    
    if(severity >= ERROR_CRITICAL) {
        Print(errorMsg);
    }
    
    if(severity == ERROR_FATAL) {
        m_emergencyMode = true;
    }
}

void CEnhancedErrorHandler::LogError(const SErrorContext &context)
{
    LogError(context.severity, context);
}

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
//| Verbose and Debug Logging                                       |
//+------------------------------------------------------------------+
void CEnhancedErrorHandler::LogVerbose(const ENUM_LOG_VERBOSITY level, const string message)
{
    if(level > m_verbosityLevel)
        return;
    
    string levelStr;
    switch(level)
    {
        case VERBOSITY_SILENT: levelStr = "SILENT"; break;
        case VERBOSITY_ERRORS_ONLY: levelStr = "ERRORS"; break;
        case VERBOSITY_WARNING: levelStr = "WARN"; break;
        case VERBOSITY_NORMAL: levelStr = "INFO"; break;
        case VERBOSITY_VERBOSE: levelStr = "VERBOSE"; break;
        case VERBOSITY_DEBUG: levelStr = "DEBUG"; break;
        default: levelStr = "UNKNOWN"; break;
    }
    
    string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
    PrintFormat("[%s] [%s] %s", timestamp, levelStr, message);
}

void CEnhancedErrorHandler::LogDebug(const string component, const string message)
{
    if(m_verbosityLevel < VERBOSITY_DEBUG)
        return;
    
    string timestamp = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
    PrintFormat("[%s] [DEBUG] [%s] %s", timestamp, component, message);
}

//+------------------------------------------------------------------+
//| Aggregation Methods                                             |
//+------------------------------------------------------------------+
void CEnhancedErrorHandler::SetVerbosityLevel(ENUM_LOG_VERBOSITY level)
{
    m_verbosityLevel = level;
    PrintFormat("[ErrorHandler] Verbosity level set to %d", level);
}

ENUM_LOG_VERBOSITY CEnhancedErrorHandler::GetVerbosityLevel()
{
    return m_verbosityLevel;
}

void CEnhancedErrorHandler::SetAggregationEnabled(bool enabled)
{
    m_aggregationEnabled = enabled;
    PrintFormat("[ErrorHandler] Error aggregation %s", enabled ? "ENABLED" : "DISABLED");
}

void CEnhancedErrorHandler::SetAggregationWindow(int seconds)
{
    m_aggregationWindowSeconds = MathMax(60, seconds);
    PrintFormat("[ErrorHandler] Aggregation window set to %d seconds", m_aggregationWindowSeconds);
}

void CEnhancedErrorHandler::GetAggregatedErrors(SErrorAggregation &aggregations[], int &count)
{
    ArrayResize(aggregations, m_aggregationCount);
    for(int i = 0; i < m_aggregationCount; i++)
    {
        aggregations[i] = m_errorAggregations[i];
    }
    count = m_aggregationCount;
}

void CEnhancedErrorHandler::ClearAggregations()
{
    for(int i = 0; i < m_aggregationCount; i++)
    {
        m_errorAggregations[i].count = 0;
        m_errorAggregations[i].firstOccurrence = 0;
        m_errorAggregations[i].lastOccurrence = 0;
    }
    m_aggregationCount = 0;
    Print("[ErrorHandler] Error aggregations cleared");
}

//+------------------------------------------------------------------+
//| Update component health status with enhanced tracking           |
//+------------------------------------------------------------------+
void CEnhancedErrorHandler::UpdateComponentHealthBySeverity(const string component, const ENUM_ERROR_SEVERITY severity)
{
    if(component == "") {
        Print("[ERROR] Cannot update health for empty component name");
        return;
    }
    
    int index = -1;
    for(int i = 0; i < m_componentCount; i++) {
        if(m_componentHealth[i].componentName == component) {
            index = i;
            break;
        }
    }
    
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
    
    m_componentHealth[index].lastErrorTime = TimeCurrent();
    m_componentHealth[index].lastErrorSeverity = severity;
    m_componentHealth[index].errorCount++;
    
    if(severity >= ERROR_CRITICAL) {
        m_componentHealth[index].status = COMPONENT_FAILED;
    } 
    else if(severity >= ERROR_RECOVERABLE) {
        if(m_componentHealth[index].status != COMPONENT_FAILED) {
            m_componentHealth[index].status = COMPONENT_DEGRADED;
        }
    }
    
    if(severity >= ERROR_WARNING) {
        int recentErrors = 0;
        datetime timeThreshold = TimeCurrent() - 300;
        
        if(m_componentHealth[index].lastError > 0 && 
           m_componentHealth[index].lastError > timeThreshold) {
            recentErrors = 1;
        }
        
        if(m_componentHealth[index].errorCount > 0) {
            datetime timeSinceLastError = TimeCurrent() - m_componentHealth[index].lastError;
            if(timeSinceLastError < 30) {
                recentErrors += m_componentHealth[index].errorCount;
            }
        }
        
        if(recentErrors > 10) {
            m_componentHealth[index].status = COMPONENT_FAILED;
            Print("[WARNING] Component ", component, " marked as FAILED due to error rate (recent errors: ", recentErrors, ")");
        }
    }
}

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

void CEnhancedErrorHandler::WriteToLog(const string message)
{
    if(!m_loggingEnabled || StringLen(message) == 0)
        return;

    int handle = FileOpen(m_logFile, FILE_WRITE|FILE_READ|FILE_TXT|FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_ANSI);
    if(handle == INVALID_HANDLE)
        return;

    FileSeek(handle, 0, SEEK_END);
    FileWrite(handle, message);
    FileClose(handle);
}

string CEnhancedErrorHandler::FormatLogMessage(const ENUM_ERROR_SEVERITY severity, const SErrorContext &context)
{
    return FormatErrorMessage(severity, context);
}

void CEnhancedErrorHandler::HandleCriticalError(const string component, const string error)
{
    if(!CEnhancedErrorHandler::m_emergencyMode)
    {
        CEnhancedErrorHandler::ActivateEmergencyMode(StringFormat("Critical error in %s: %s", component, error));
    }

    string criticalMessage = StringFormat("CRITICAL ERROR in %s: %s", component, error);

    CEnhancedErrorHandler::WriteToLog("=== CRITICAL ERROR DETECTED ===\n");
    CEnhancedErrorHandler::WriteToLog(criticalMessage + "\n");
    CEnhancedErrorHandler::WriteToLog("Emergency procedures activated\n");
    CEnhancedErrorHandler::WriteToLog("===============================\n");

    CEnhancedErrorHandler::UpdateComponentHealth(component, COMPONENT_FAILED, error);

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
        CEnhancedErrorHandler::UpdateComponentHealth(component, COMPONENT_DISABLED, "Disabled due to critical error");
    }
}

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

        for(int i = 0; i < CEnhancedErrorHandler::m_componentCount; i++)
        {
            if(CEnhancedErrorHandler::m_componentHealth[i].performanceScore > 0.8)
                CEnhancedErrorHandler::m_componentHealth[i].status = COMPONENT_HEALTHY;
        }
    }
}

int CEnhancedErrorHandler::FindComponentIndex(const string componentName)
{
    for(int i = 0; i < CEnhancedErrorHandler::m_componentCount; i++)
    {
        if(CEnhancedErrorHandler::m_componentHealth[i].componentName == componentName)
        {
            return i;
        }
    }
    return -1;
}

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

void CEnhancedErrorHandler::CleanupOldRetryData()
{
    datetime threshold = TimeCurrent() - 3600;
    for(int i = 0; i < ArraySize(m_lastRetryTime); i++)
    {
        if(m_lastRetryTime[i] != 0 && m_lastRetryTime[i] < threshold)
        {
            m_lastRetryTime[i] = 0;
            m_retryAttempts[i] = 0;
        }
    }
}

bool CEnhancedErrorHandler::Initialize(const string logFileName, const ENUM_ERROR_SEVERITY minLevel)
{
    m_logFile = logFileName;
    m_minLogLevel = minLevel;
    m_loggingEnabled = true;
    m_emergencyMode = false;
    m_gracefulDegradation = true;
    m_componentCount = 0;
    m_lastError = 0;
    m_verbosityLevel = VERBOSITY_NORMAL;
    m_aggregationCount = 0;
    m_aggregationWindowSeconds = 300;
    m_aggregationEnabled = true;

    for(int i = 0; i < 5; i++)
        m_errorCount[i] = 0;

    for(int i = 0; i < ArraySize(m_componentHealth); i++) {
        m_componentHealth[i].componentName = "";
        m_componentHealth[i].status = COMPONENT_UNKNOWN;
        m_componentHealth[i].errorCount = 0;
        m_componentHealth[i].warningCount = 0;
        m_componentHealth[i].lastError = 0;
        m_componentHealth[i].lastHealthCheck = 0;
        m_componentHealth[i].performanceScore = 0.0;
    }
    
    ArrayInitialize(m_retryAttempts, 0);
    ArrayInitialize(m_lastRetryTime, 0);
    // Cannot use ArrayInitialize with struct - initialize manually
    for(int i = 0; i < 50; i++)
    {
        m_errorAggregations[i].errorCode = 0;
        m_errorAggregations[i].count = 0;
        m_errorAggregations[i].firstOccurrence = 0;
        m_errorAggregations[i].lastOccurrence = 0;
        m_errorAggregations[i].maxSeverity = ERROR_INFO;
        m_errorAggregations[i].lastComponent = "";
        m_errorAggregations[i].lastMessage = "";
    }

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
    FileWrite(handle, "Verbosity Level: ", EnumToString(m_verbosityLevel));
    FileWrite(handle, "Error Aggregation: ", m_aggregationEnabled ? "Enabled" : "Disabled");
    FileWrite(handle, "Graceful Degradation: ", m_gracefulDegradation ? "Enabled" : "Disabled");
    FileWrite(handle, "==========================================");
    FileClose(handle);

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

void CEnhancedErrorHandler::GetErrorStats(int &infoCount, int &warningCount,
                              int &recoverableCount, int &criticalCount, int &fatalCount)
{
    infoCount = m_errorCount[ERROR_INFO];
    warningCount = m_errorCount[ERROR_WARNING];
    recoverableCount = m_errorCount[ERROR_RECOVERABLE];
    criticalCount = m_errorCount[ERROR_CRITICAL];
    fatalCount = m_errorCount[ERROR_FATAL];
}

void CEnhancedErrorHandler::RegisterComponent(const string componentName)
{
    if(FindComponentIndex(componentName) >= 0) return;
    
    if(m_componentCount >= 20)
    {
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

bool CEnhancedErrorHandler::HandleMT5Error(const string context)
{
    int error = GetLastError();
    if(error == 0) return true;

    if(IsRecoverableError(error))
    {
        int attempt = m_retryAttempts[error % 100]++;
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
            return true;
        }
    }

    SErrorContext errorContext;
    errorContext.component = "ErrorHandler";
    errorContext.operation = context;
    errorContext.symbol = "";
    errorContext.errorCode = error;
    errorContext.additionalInfo = "Error " + IntegerToString(error);
    errorContext.timestamp = TimeCurrent();
    errorContext.severity = ERROR_WARNING;

    LogError(errorContext.severity, errorContext);
    return false;
}

bool CEnhancedErrorHandler::IsRecoverableError(const int errorCode)
{
    static const int recoverableErrors[] = {
        6, 8, 64, 128, 129, 130, 131, 132, 133, 134, 135, 136, 137, 138, 139, 140,
        141, 145, 146, 147, 148, 149, 150, 151
    };
    
    for(int i = 0; i < ArraySize(recoverableErrors); i++) {
        if(errorCode == recoverableErrors[i]) {
            return true;
        }
    }
    return false;
}

ENUM_ERROR_SEVERITY CEnhancedErrorHandler::GetErrorSeverity(const int errorCode)
{
    switch(errorCode) {
        case 0:     return ERROR_INFO;
        case 1:     return ERROR_FATAL;
        case 2:     return ERROR_CRITICAL;
        case 3:     return ERROR_CRITICAL;
        case 4:     return ERROR_CRITICAL;
        case 5:     return ERROR_CRITICAL;
        case 6:     return ERROR_RECOVERABLE;
        case 7:     return ERROR_CRITICAL;
        case 8:     return ERROR_RECOVERABLE;
        case 9:     return ERROR_CRITICAL;
        case 64:    return ERROR_CRITICAL;
        case 65:    return ERROR_CRITICAL;
        case 128:   return ERROR_RECOVERABLE;
        case 129:   return ERROR_RECOVERABLE;
        case 130:   return ERROR_RECOVERABLE;
        case 131:   return ERROR_RECOVERABLE;
        case 132:   return ERROR_RECOVERABLE;
        case 133:   return ERROR_RECOVERABLE;
        case 134:   return ERROR_CRITICAL;
        case 135:   return ERROR_RECOVERABLE;
        case 136:   return ERROR_RECOVERABLE;
        case 137:   return ERROR_RECOVERABLE;
        case 138:   return ERROR_RECOVERABLE;
        case 139:   return ERROR_RECOVERABLE;
        case 140:   return ERROR_RECOVERABLE;
        case 141:   return ERROR_RECOVERABLE;
        case 145:   return ERROR_RECOVERABLE;
        case 146:   return ERROR_RECOVERABLE;
        case 147:   return ERROR_RECOVERABLE;
        case 148:   return ERROR_RECOVERABLE;
        case 149:   return ERROR_CRITICAL;
        case 150:   return ERROR_CRITICAL;
        case 151:   return ERROR_RECOVERABLE;
        default:    return ERROR_WARNING;
    }
}

CEnhancedErrorHandler* CEnhancedErrorHandler::GetInstance()
{
    if(m_instance == NULL)
    {
        m_instance = new CEnhancedErrorHandler();
    }
    return m_instance;
}

CEnhancedErrorHandler* CEnhancedErrorHandler::m_instance = NULL;
string CEnhancedErrorHandler::m_logFile = "";
bool CEnhancedErrorHandler::m_loggingEnabled = false;
ENUM_ERROR_SEVERITY CEnhancedErrorHandler::m_minLogLevel = ERROR_INFO;
ENUM_LOG_VERBOSITY CEnhancedErrorHandler::m_verbosityLevel = VERBOSITY_NORMAL;
int CEnhancedErrorHandler::m_errorCount[5] = {0};
datetime CEnhancedErrorHandler::m_lastError = 0;
bool CEnhancedErrorHandler::m_emergencyMode = false;
int CEnhancedErrorHandler::m_componentCount = 0;
bool CEnhancedErrorHandler::m_gracefulDegradation = true;
SRetryConfig CEnhancedErrorHandler::m_defaultRetryConfig;
SComponentHealth CEnhancedErrorHandler::m_componentHealth[20];
int CEnhancedErrorHandler::m_retryAttempts[100];
datetime CEnhancedErrorHandler::m_lastRetryTime[100];
SErrorAggregation CEnhancedErrorHandler::m_errorAggregations[50];
int CEnhancedErrorHandler::m_aggregationCount = 0;
int CEnhancedErrorHandler::m_aggregationWindowSeconds = 300;
bool CEnhancedErrorHandler::m_aggregationEnabled = true;

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

string CEnhancedErrorHandler::GetSeverityString(const ENUM_ERROR_SEVERITY severity)
{
    switch(severity)
    {
        case ERROR_INFO:     return "INFO";
        case ERROR_WARNING:  return "WARNING";
        case ERROR_RECOVERABLE: return "RECOVERABLE";
        case ERROR_CRITICAL: return "CRITICAL";
        case ERROR_FATAL:    return "FATAL";
        default:             return "UNKNOWN";
    }
}

void CEnhancedErrorHandler::UpdateErrorCounters(const ENUM_ERROR_SEVERITY severity)
{
    if(severity < ERROR_INFO || severity > ERROR_FATAL) return;
    m_errorCount[severity]++;
    m_lastError = TimeCurrent();
}

void CEnhancedErrorHandler::Shutdown()
{
    m_loggingEnabled = false;
}

#endif // CORE_ERROR_HANDLING_MQH
