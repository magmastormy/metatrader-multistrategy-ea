// Validation-gate counters, timing metrics and audit-log sink.
// Formatting entry points take primitives, not structs, to avoid a dependency on UnifiedRiskManager.mqh.
#ifndef CORE_RISK_RISK_VALIDATION_STATS_MQH
#define CORE_RISK_RISK_VALIDATION_STATS_MQH

#include "../Utils/ErrorHandling.mqh"
#include "RiskClusterCodec.mqh"

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

    void   SetAuditLogging(const bool enabled)     { m_auditLogging = enabled; }
    bool   IsAuditLogging() const                  { return m_auditLogging; }
    void   SetAuditLogFile(const string fileName)  { m_auditLogFile = fileName; }
    string GetAuditLogFile() const                 { return m_auditLogFile; }

    int      GetValidationCount() const   { return m_validationCount; }
    int      GetApprovedCount() const     { return m_approvedCount; }
    int      GetRejectedCount() const     { return m_rejectedCount; }
    datetime GetLastValidation() const    { return m_lastValidation; }
    double   GetAvgValidationTime() const { return m_avgValidationTime; }

    void RecordApproval()
    {
        m_approvedCount++;
        m_validationCount++;
    }

    void RecordRejection()
    {
        m_rejectedCount++;
        m_validationCount++;
    }

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

    //--- Append a line to the audit log file (no-op when audit logging is disabled).
    void WriteAuditLog(const string message)
    {
        if(!m_auditLogging)
            return;

        // Static handle keeps the log file open across calls instead of open/close per line.
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

    //--- Formats the audit line; rawClusterCode is normalised internally.
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

    //--- Writes the outcome to the audit file and mirrors resultMessage into CEnhancedErrorHandler.
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

    //--- Resets counters and timing metrics only; audit configuration stays on so the
    //--- reset itself is still written to the audit log.
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
