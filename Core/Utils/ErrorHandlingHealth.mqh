//+------------------------------------------------------------------+
//| ErrorHandlingHealth.mqh                                          |
//| Component health tracking, error counters/stats and emergency    |
//| handling. Extracted verbatim from ErrorHandling.mqh.             |
//+------------------------------------------------------------------+
#ifndef CORE_ERROR_HANDLING_HEALTH_MQH
#define CORE_ERROR_HANDLING_HEALTH_MQH

#include "ErrorHandlingTypes.mqh"
#include "ErrorHandlingCore.mqh"

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

void CEnhancedErrorHandler::UpdateErrorCounters(const ENUM_ERROR_SEVERITY severity)
{
    if(severity < ERROR_INFO || severity > ERROR_FATAL) return;
    m_errorCount[severity]++;
    m_lastError = TimeCurrent();
}

#endif // CORE_ERROR_HANDLING_HEALTH_MQH
