// Shared enums, structs and severity macros for the error
// handling framework. Extracted verbatim from ErrorHandling.mqh.
#ifndef CORE_ERROR_HANDLING_TYPES_MQH
#define CORE_ERROR_HANDLING_TYPES_MQH

// Forward declarations
class CEnhancedErrorHandler;

// Logging Verbosity Levels
enum ENUM_LOG_VERBOSITY
{
    VERBOSITY_SILENT = 0,       // No logging at all
    VERBOSITY_ERRORS_ONLY = 1, // Only errors and critical
    VERBOSITY_WARNING = 2,     // Errors and warnings
    VERBOSITY_NORMAL = 3,       // Normal logging (default)
    VERBOSITY_VERBOSE = 4,     // Detailed logging
    VERBOSITY_DEBUG = 5         // Debug-level logging
};

struct SRetryConfig
{
    int maxRetries;          // Maximum number of retry attempts
    int retryDelay;          // Delay between retries in milliseconds
    bool exponentialBackoff; // Use exponential backoff for delays
    int maxDelayMs;          // Maximum delay in milliseconds
    
    SRetryConfig() : maxRetries(3), retryDelay(100), exponentialBackoff(false), maxDelayMs(30000) {}
};

// Error Classification System
enum ENUM_ERROR_SEVERITY
{
    ERROR_INFO = 0,          // Informational, no action needed
    ERROR_WARNING = 1,       // Warning, continue with caution
    ERROR_RECOVERABLE = 2,   // Error that can be handled gracefully
    ERROR_CRITICAL = 3,      // Critical error, disable affected component
    ERROR_FATAL = 4          // Fatal error, emergency shutdown
};

// Additional error codes for PositionSizer
#define ERROR_INVALID_PARAM ERROR_RECOVERABLE
#define ERROR_INVALID_INPUT ERROR_RECOVERABLE

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

// Component Health Status
enum ENUM_COMPONENT_STATUS
{
    COMPONENT_HEALTHY = 0,       // Component operating normally
    COMPONENT_DEGRADED = 1,      // Component operating with reduced functionality
    COMPONENT_FAILING = 2,       // Component experiencing failures
    COMPONENT_FAILED = 3,        // Component completely failed
    COMPONENT_DISABLED = 4,      // Component manually disabled
    COMPONENT_UNKNOWN = 5        // Component status unknown
};

// Retry Strategy Types
enum ENUM_RETRY_STRATEGY
{
    RETRY_NONE = 0,
    RETRY_IMMEDIATE = 1,
    RETRY_LINEAR = 2,           // Linear backoff
    RETRY_EXPONENTIAL = 3       // Exponential backoff
};

struct SErrorContext
{
    string component;           // Component name
    string operation;           // Operation being performed
    string symbol;              // Symbol (if applicable)
    int errorCode;              // System error code
    string additionalInfo;      // Additional context information
    datetime timestamp;         // Error timestamp
    ENUM_ERROR_SEVERITY severity;
    
    SErrorContext() :
        component(""), operation(""), symbol(""), errorCode(0),
        additionalInfo(""), timestamp(0), severity(ERROR_INFO) {}
};

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

#endif // CORE_ERROR_HANDLING_TYPES_MQH

