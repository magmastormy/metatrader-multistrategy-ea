// Pure formatting and error-code classification helpers.
// Extracted verbatim from ErrorHandling.mqh.
#ifndef CORE_ERROR_HANDLING_FORMAT_MQH
#define CORE_ERROR_HANDLING_FORMAT_MQH

#include "ErrorHandlingTypes.mqh"
#include "ErrorHandlingCore.mqh"

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
    string errSymbol = (context.symbol != "") ? context.symbol : "N/A";
    string operation = (context.operation != "") ? context.operation : "N/A";
    string details = (context.additionalInfo != "") ? context.additionalInfo : "No details";
    
    return StringFormat("[%s] %s | %s | %s | %s | %d | %s",
        timestamp,
        severityStr,
        component,
        operation,
        errSymbol,
        context.errorCode,
        details
    );
}

string CEnhancedErrorHandler::FormatLogMessage(const ENUM_ERROR_SEVERITY severity, const SErrorContext &context)
{
    return FormatErrorMessage(severity, context);
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

#endif // CORE_ERROR_HANDLING_FORMAT_MQH
