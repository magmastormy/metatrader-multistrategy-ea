// Error reporting: logging sinks, verbosity control and error
// aggregation. Extracted verbatim from ErrorHandling.mqh.
#ifndef CORE_ERROR_HANDLING_REPORT_MQH
#define CORE_ERROR_HANDLING_REPORT_MQH

#include "ErrorHandlingTypes.mqh"
#include "ErrorHandlingCore.mqh"

// Log an error with context and enhanced validation
void CEnhancedErrorHandler::LogError(const ENUM_ERROR_SEVERITY severity, const SErrorContext &context)
{
    if(severity < ERROR_INFO || severity > ERROR_FATAL) {
        Print("[ERROR] Invalid error severity level: ", EnumToString(severity));
        return;
    }
    
    if((int)severity < (int)m_minLogLevel) {
        return;
    }
    
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

// Verbose and Debug Logging
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

// Aggregation Methods
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

#endif // CORE_ERROR_HANDLING_REPORT_MQH
