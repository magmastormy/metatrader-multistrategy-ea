// Validation-gate counters, timing metrics and audit-log sink.
// Extracted verbatim from CUnifiedRiskManager (Phase E1). Owns the
// state that used to live in the manager:
// m_auditLogging, m_auditLogFile, m_validationCount,
// m_approvedCount, m_rejectedCount, m_lastValidation,
// The constructor performs the zero-initialisation that previously
// happened in the CUnifiedRiskManager initialiser list, so default
// values are unchanged.
// The message-formatting entry points take primitives instead of
// STradeValidationRequest / SValidationResult so this module has no
// dependency on UnifiedRiskManager.mqh (which includes it).
// CUnifiedRiskManager keeps thin forwarders with the original
// struct-based signatures.
#ifndef CORE_RISK_RISK_VALIDATION_STATS_MQH
#define CORE_RISK_RISK_VALIDATION_STATS_MQH

#include "../Utils/ErrorHandling.mqh"
#include "RiskClusterCodec.mqh"

// Validation statistics + audit log (stateful, owned by value)
class CRiskValidationStats
{
private:
    bool     m_auditLogging;        // Audit log enabled
    string   m_auditLogFile;        // Audit log file name
    int      m_validationCount;     // Total validations performed
    int      m_approvedCount;       // Approved validations
    int      m_rejectedCount;       // Rejected validations
    datetime m_lastValidation;      // Timestamp of the last validation
    double   m_avgValidationTime;   // Rolling average validation time (ms)

public:
    //--- Reproduces the original CUnifiedRiskManager initialiser-list defaults.
    CRiskValidationStats() :
        m_auditLogging(true),
        m_auditLogFile("UnifiedRiskValidation.log"),
        m_validationCount(0),
        m_approvedCount(0),
        m_rejectedCount(0),
        m_lastValidation(0),
        m_avgValidationTime(0.0)
    {}

    ~CRiskValidationStats() {}

    //--- Configuration -------------------------------------------------
    void   SetAuditLogging(const bool enabled)     { m_auditLogging = enabled; }
    bool   IsAuditLogging() const                  { return m_auditLogging; }
    void   SetAuditLogFile(const string fileName)  { m_auditLogFile = fileName; }
    string GetAuditLogFile() const                 { return m_auditLogFile; }

    //--- Counter accessors ---------------------------------------------
    int      GetValidationCount() const   { return m_validationCount; }
    int      GetApprovedCount() const     { return m_approvedCount; }
    int      GetRejectedCount() const     { return m_rejectedCount; }
    datetime GetLastValidation() const    { return m_lastValidation; }
    double   GetAvgValidationTime() const { return m_avgValidationTime; }

    //--- Record an approval. Mirrors the original inline pair:
    //---   m_approvedCount++;
    //---   m_validationCount++;
    void RecordApproval()
    {
        m_approvedCount++;
        m_validationCount++;
    }

    //--- Batch 152: rejection counterpart - m_rejectedCount existed but had no
    //--- writer, so rejection telemetry always read zero.
    void RecordRejection()
    {
        m_rejectedCount++;
        m_validationCount++;
    }

    //--- Aggregated stats (original CUnifiedRiskManager::GetValidationStats).
    void GetStats(int &total, int &approved, int &rejected, double &approvalRate)
    {
        total = m_validationCount;
        approved = m_approvedCount;
        rejected = m_rejectedCount;

        if(total > 0)
            approvalRate = (double)approved / total * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale
        else
            approvalRate = 0.0;
    }

    //--- Append a line to the audit log file.
    //--- Batch 119 optimisation (static file handle) preserved verbatim.
    //--- Declared before its in-class callers (Reset / LogValidationResult).
    void WriteAuditLog(const string message)
    {
        if(!m_auditLogging)
            return;

        // Batch 119: Use static file handle to avoid open/close per call
        static int s_auditHandle = INVALID_HANDLE;
        static string s_auditFile = "";

        if(s_auditHandle == INVALID_HANDLE || s_auditFile != m_auditLogFile)
        {
            if(s_auditHandle != INVALID_HANDLE)
                FileClose(s_auditHandle);
            s_auditHandle = FileOpen(m_auditLogFile, FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI);
            s_auditFile = m_auditLogFile;
        }

        if(s_auditHandle != INVALID_HANDLE)
        {
            FileSeek(s_auditHandle, 0, SEEK_END);
            string timestamp = TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS);
            FileWrite(s_auditHandle, StringFormat("[%s] %s", timestamp, message));
        }
    }

    //--- Build the audit line for a validation outcome.
    //--- rawClusterCode is normalised internally, exactly as the original did.
    static string FormatValidationMessage(const string symbol,
                                          const ENUM_ORDER_TYPE orderType,
                                          const double lotSize,
                                          const bool approved,
                                          const string strategyRole,
                                          const string strategyCluster,
                                          const string rawClusterCode,
                                          const double riskPercent,
                                          const double portfolioRisk,
                                          const double correlationRisk)
    {
        string clusterCode = CRiskClusterCodec::NormalizeClusterCode(rawClusterCode);
        return StringFormat("VALIDATION: %s %s %.3f lots | %s | Role=%s | Cluster=%s(%s) | Risk: %.2f%% | Portfolio: %.2f%% | Correlation: %.2f",
                           symbol,
                           EnumToString(orderType),
                           lotSize,
                           approved ? "APPROVED" : "REJECTED",
                           strategyRole,
                           strategyCluster,
                           clusterCode,
                           riskPercent,
                           portfolioRisk,
                           correlationRisk);
    }

    //--- Log a validation outcome to the audit file and the error handler.
    //--- Guard order and side effects match the original implementation:
    //---   1. bail out when audit logging is disabled (no formatting cost)
    //---   2. format + write audit line
    //---   3. mirror the result message into CEnhancedErrorHandler
    void LogValidationResult(const string symbol,
                             const ENUM_ORDER_TYPE orderType,
                             const double lotSize,
                             const bool approved,
                             const string strategyRole,
                             const string strategyCluster,
                             const string rawClusterCode,
                             const double riskPercent,
                             const double portfolioRisk,
                             const double correlationRisk,
                             const string resultMessage)
    {
        if(!m_auditLogging)
            return;

        string logMessage = FormatValidationMessage(symbol,
                                                    orderType,
                                                    lotSize,
                                                    approved,
                                                    strategyRole,
                                                    strategyCluster,
                                                    rawClusterCode,
                                                    riskPercent,
                                                    portfolioRisk,
                                                    correlationRisk);
        WriteAuditLog(logMessage);

        // Also log to error handler
        CEnhancedErrorHandler::LogError(ERROR_INFO, "UnifiedRiskManager", resultMessage, 0);
    }

    //--- Update the rolling average validation time (milliseconds).
    void UpdatePerformanceMetrics(const ulong startTimeParam)
    {
        ulong endTime = GetMicrosecondCount();
        double validationTime = 0.0;
        if(endTime >= startTimeParam)
            validationTime = (double)(endTime - startTimeParam) / 1000.0; // microseconds -> milliseconds

        if(m_validationCount <= 0)
        {
            m_avgValidationTime = validationTime;
        }
        else if(m_validationCount == 1)
        {
            m_avgValidationTime = validationTime;
        }
        else
        {
            m_avgValidationTime = (m_avgValidationTime * (m_validationCount - 1) + validationTime) / m_validationCount;
        }

        m_lastValidation = TimeCurrent();
    }

    //--- Reset all counters and timing metrics. Audit configuration
    //--- (m_auditLogging / m_auditLogFile) is intentionally preserved so
    //--- the reset itself can still be recorded. Mirrors the original
    //--- CUnifiedRiskManager::ResetStats behaviour exactly.
    void Reset(void)
    {
        m_validationCount = 0;
        m_approvedCount = 0;
        m_rejectedCount = 0;
        m_lastValidation = 0;
        m_avgValidationTime = 0.0;
        WriteAuditLog("Validation statistics reset");
    }
};

#endif // CORE_RISK_RISK_VALIDATION_STATS_MQH
