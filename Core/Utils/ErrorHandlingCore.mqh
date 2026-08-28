//+------------------------------------------------------------------+
//| ErrorHandlingCore.mqh                                            |
//| Class declarations, static state storage and lifecycle           |
//| (GetInstance / Initialize / Shutdown / DestroyInstance).         |
//| Extracted verbatim from ErrorHandling.mqh.                       |
//+------------------------------------------------------------------+
#ifndef CORE_ERROR_HANDLING_CORE_MQH
#define CORE_ERROR_HANDLING_CORE_MQH

#include "ErrorHandlingTypes.mqh"

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
    static void DestroyInstance();
};

// Batch 153: the CErrorHandling instance-wrapper class was removed - it had
// zero references repo-wide and its non-trivial overloads either dropped the
// payload or double-routed into CEnhancedErrorHandler.

//+------------------------------------------------------------------+
//| Static member storage                                            |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Singleton access                                                 |
//+------------------------------------------------------------------+
CEnhancedErrorHandler* CEnhancedErrorHandler::GetInstance()
{
    if(m_instance == NULL)
    {
        m_instance = new CEnhancedErrorHandler();
    }
    return m_instance;
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

void CEnhancedErrorHandler::Shutdown()
{
    m_loggingEnabled = false;
}

void CEnhancedErrorHandler::DestroyInstance()
{
    if(m_instance != NULL)
    {
        // Flush any pending log writes
        if(m_logFile != "" && m_loggingEnabled)
        {
            int handle = FileOpen(m_logFile, FILE_READ|FILE_WRITE|FILE_TXT|FILE_ANSI, '\t');
            if(handle != INVALID_HANDLE)
            {
                FileClose(handle);
            }
        }
        
        // Delete the singleton instance
        delete m_instance;
        m_instance = NULL;
        
        // Reset static members
        m_logFile = "";
        m_loggingEnabled = false;
        m_minLogLevel = ERROR_INFO;
        m_verbosityLevel = VERBOSITY_NORMAL;
        for(int i = 0; i < 5; i++)
            m_errorCount[i] = 0;
        m_lastError = 0;
        m_emergencyMode = false;
        m_componentCount = 0;
        m_gracefulDegradation = true;
        m_aggregationCount = 0;
        m_aggregationWindowSeconds = 300;
        m_aggregationEnabled = true;
    }
}

#endif // CORE_ERROR_HANDLING_CORE_MQH
