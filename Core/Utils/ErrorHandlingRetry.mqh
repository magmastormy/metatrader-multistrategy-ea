// Retry / backoff logic and retry bookkeeping cleanup.
// Extracted verbatim from ErrorHandling.mqh.
#ifndef CORE_ERROR_HANDLING_RETRY_MQH
#define CORE_ERROR_HANDLING_RETRY_MQH

#include "ErrorHandlingTypes.mqh"
#include "ErrorHandlingCore.mqh"

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
            PrintFormat("Retryable error %d in %s, attempt %d/%d, retrying immediately (non-blocking)",
                       error, context, attempt + 1, m_defaultRetryConfig.maxRetries);
            
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

#endif // CORE_ERROR_HANDLING_RETRY_MQH
