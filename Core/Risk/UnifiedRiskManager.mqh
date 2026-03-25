//+------------------------------------------------------------------+
//| UnifiedRiskManager.mqh                                           |
//| Single authoritative risk contract for the EA runtime            |
//+------------------------------------------------------------------+
#ifndef CORE_RISK_UNIFIED_RISK_MANAGER_MQH
#define CORE_RISK_UNIFIED_RISK_MANAGER_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "../Monitoring/PerformanceAnalytics.mqh"
#include "PortfolioRiskManager.mqh"
#include "RiskValidationGate.mqh"

//+------------------------------------------------------------------+
//| Unified risk configuration                                       |
//+------------------------------------------------------------------+
struct SUnifiedRiskConfig
{
    double baseRiskPerTradePercent;
    double minRiskPerTradePercent;
    double maxRiskPerTradePercent;
    double maxDailyRiskPercent;
    double maxPortfolioRiskPercent;
    double correlationThreshold;
    double drawdownWarningPercent;
    double drawdownCriticalPercent;
    int adaptationMinTrades;
    bool enableAdaptiveSizing;
    bool enableAuditLogging;
    string auditLogFile;
};

//+------------------------------------------------------------------+
//| Unified risk runtime snapshot                                    |
//+------------------------------------------------------------------+
struct SUnifiedRiskSnapshot
{
    double activeRiskPerTradePercent;
    double dailyRiskUsedPercent;           // Effective max(entry_budget, mtm_loss, open_exposure)
    double dailyEntryRiskUsedPercent;      // Cumulative accepted entry risk intents
    double dailyMarkToMarketLossPercent;   // Equity loss vs daily baseline
    double openExposureRiskPercent;        // Current stop-defined portfolio exposure
    double maxDailyRiskPercent;
    double portfolioRiskPercent;
    double currentDrawdownPercent;
    double winRatePercent;
    double profitFactor;
    double netProfit;
    int totalTrades;
    int winningTrades;
    int losingTrades;
    int gateValidationCount;
    int gateApprovedCount;
    int gateRejectedCount;
    bool conservativeMode;
    bool emergencyMode;
};

//+------------------------------------------------------------------+
//| Unified risk manager                                             |
//+------------------------------------------------------------------+
class CUnifiedRiskManager
{
private:
    SUnifiedRiskConfig m_config;
    CRiskValidationGate m_validationGate;
    CPortfolioRiskManager m_portfolioRiskManager;
    CPerformanceAnalytics* m_performanceAnalytics;

    double m_activeRiskPerTradePercent;
    double m_dailyRiskUsedPercent;
    double m_dailyStartEquity;
    datetime m_lastDailyReset;
    bool m_initialized;
    bool m_conservativeMode;

public:
    CUnifiedRiskManager();
    ~CUnifiedRiskManager();

    bool Initialize(const SUnifiedRiskConfig &config, CPerformanceAnalytics* performanceAnalytics = NULL);

    // Called each cycle/new bar to keep limits and adaptive risk current.
    void RefreshRuntimeState();
    void CheckAndResetDailyLimits();

    // Single trade validation authority.
    SValidationResult ValidateTradeRequest(const STradeValidationRequest &request, const string phaseTag = "runtime");
    void ConfigureClusterGovernance(const bool enabled,
                                    const int maxConcurrentPerCluster,
                                    const double maxClusterRiskPercent,
                                    const bool enableMutex);

    // Register accepted risk usage only after successful execution.
    void RegisterExecutedTradeRisk(const SValidationResult &validationResult, const double fillRatio = 1.0);

    double GetActiveRiskPerTradePercent() const { return m_activeRiskPerTradePercent; }
    double GetRemainingDailyRiskPercent();
    SUnifiedRiskSnapshot GetSnapshot();
    bool HasUnprotectedPositions();
    int GetUnprotectedPositionCount();

private:
    void UpdateAdaptiveRiskLevel();
    bool IsNewTradingDay(const datetime nowTime) const;
    double ClampRiskPercent(const double value) const;
    double CalculateDailyMarkToMarketLossPercent();
    double GetCurrentOpenExposureRiskPercent();
    double GetEffectiveDailyRiskUsedPercent();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CUnifiedRiskManager::CUnifiedRiskManager() :
    m_performanceAnalytics(NULL),
    m_activeRiskPerTradePercent(1.0),
    m_dailyRiskUsedPercent(0.0),
    m_dailyStartEquity(0.0),
    m_lastDailyReset(0),
    m_initialized(false),
    m_conservativeMode(false)
{
    m_config.baseRiskPerTradePercent = 1.0;
    m_config.minRiskPerTradePercent = 0.1;
    m_config.maxRiskPerTradePercent = 2.0;
    m_config.maxDailyRiskPercent = 6.0;
    m_config.maxPortfolioRiskPercent = 10.0;
    m_config.correlationThreshold = 0.7;
    m_config.drawdownWarningPercent = 6.0;
    m_config.drawdownCriticalPercent = 12.0;
    m_config.adaptationMinTrades = 20;
    m_config.enableAdaptiveSizing = true;
    m_config.enableAuditLogging = true;
    m_config.auditLogFile = "UnifiedRiskValidation.log";
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CUnifiedRiskManager::~CUnifiedRiskManager()
{
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CUnifiedRiskManager::Initialize(const SUnifiedRiskConfig &config,
                                     CPerformanceAnalytics* perfAnalytics)
{
    m_config = config;
    m_performanceAnalytics = perfAnalytics;

    if(m_config.maxRiskPerTradePercent <= 0.0)
        m_config.maxRiskPerTradePercent = 2.0;
    if(m_config.minRiskPerTradePercent <= 0.0)
        m_config.minRiskPerTradePercent = 0.1;
    if(m_config.baseRiskPerTradePercent <= 0.0)
        m_config.baseRiskPerTradePercent = m_config.maxRiskPerTradePercent;
    if(m_config.maxDailyRiskPercent <= 0.0)
        m_config.maxDailyRiskPercent = 6.0;
    if(m_config.maxPortfolioRiskPercent <= 0.0)
        m_config.maxPortfolioRiskPercent = 10.0;
    if(m_config.correlationThreshold <= 0.0 || m_config.correlationThreshold > 1.0)
        m_config.correlationThreshold = 0.7;
    if(m_config.adaptationMinTrades < 5)
        m_config.adaptationMinTrades = 20;
    if(m_config.drawdownWarningPercent <= 0.0)
        m_config.drawdownWarningPercent = 6.0;
    if(m_config.drawdownCriticalPercent <= m_config.drawdownWarningPercent)
        m_config.drawdownCriticalPercent = m_config.drawdownWarningPercent + 4.0;

    if(!m_portfolioRiskManager.Initialize(m_config.maxPortfolioRiskPercent, m_config.correlationThreshold))
    {
        Print("[RISK-UNIFIED] Failed to initialize portfolio risk manager");
        return false;
    }

    if(!m_validationGate.Initialize(&m_portfolioRiskManager,
                                    m_config.maxRiskPerTradePercent,
                                    m_config.maxPortfolioRiskPercent,
                                    m_config.correlationThreshold))
    {
        Print("[RISK-UNIFIED] Failed to initialize validation gate");
        return false;
    }

    m_validationGate.EnableAuditLogging(m_config.enableAuditLogging, m_config.auditLogFile);

    m_activeRiskPerTradePercent = ClampRiskPercent(m_config.baseRiskPerTradePercent);
    m_dailyRiskUsedPercent = 0.0;
    m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(m_dailyStartEquity <= 0.0)
        m_dailyStartEquity = AccountInfoDouble(ACCOUNT_BALANCE);
    m_lastDailyReset = TimeCurrent();
    m_initialized = true;

    PrintFormat("[RISK-UNIFIED] Initialized | Base %.2f%% | Range %.2f-%.2f%% | Daily %.2f%% | Portfolio %.2f%%",
                m_config.baseRiskPerTradePercent,
                m_config.minRiskPerTradePercent,
                m_config.maxRiskPerTradePercent,
                m_config.maxDailyRiskPercent,
                m_config.maxPortfolioRiskPercent);

    return true;
}

//+------------------------------------------------------------------+
//| Refresh runtime state                                            |
//+------------------------------------------------------------------+
void CUnifiedRiskManager::RefreshRuntimeState()
{
    if(!m_initialized)
        return;

    CheckAndResetDailyLimits();
    UpdateAdaptiveRiskLevel();
}

//+------------------------------------------------------------------+
//| Daily reset                                                      |
//+------------------------------------------------------------------+
void CUnifiedRiskManager::CheckAndResetDailyLimits()
{
    if(!m_initialized)
        return;

    datetime nowTime = TimeCurrent();
    if(IsNewTradingDay(nowTime))
    {
        m_dailyRiskUsedPercent = 0.0;
        m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        if(m_dailyStartEquity <= 0.0)
            m_dailyStartEquity = AccountInfoDouble(ACCOUNT_BALANCE);
        m_lastDailyReset = nowTime;
        Print("[RISK-UNIFIED] Daily risk usage reset");
    }
}

//+------------------------------------------------------------------+
//| Validate trade request                                           |
//+------------------------------------------------------------------+
SValidationResult CUnifiedRiskManager::ValidateTradeRequest(const STradeValidationRequest &request,
                                                            const string phaseTag)
{
    SValidationResult result;
    ZeroMemory(result);
    result.approved = false;
    result.adjustedLotSize = request.lotSize;
    result.severity = ERROR_LEVEL_ERROR;

    if(!m_initialized)
    {
        result.message = "Unified risk manager is not initialized";
        return result;
    }

    CheckAndResetDailyLimits();

    double effectiveDailyRisk = GetEffectiveDailyRiskUsedPercent();
    if(effectiveDailyRisk >= m_config.maxDailyRiskPercent)
    {
        result.message = StringFormat("Daily risk budget exhausted: %.2f%% / %.2f%%",
                                      effectiveDailyRisk, m_config.maxDailyRiskPercent);
        result.severity = ERROR_LEVEL_WARNING;
        return result;
    }

    result = m_validationGate.ValidateTradeRequest(request);
    if(!result.approved)
        return result;

    double projectedDailyRisk = effectiveDailyRisk + MathMax(0.0, result.riskPercent);
    if(projectedDailyRisk > m_config.maxDailyRiskPercent)
    {
        result.approved = false;
        result.severity = ERROR_LEVEL_WARNING;
        result.message = StringFormat("Daily risk limit would be exceeded (%s): %.2f%% + %.2f%% > %.2f%%",
                                      phaseTag, effectiveDailyRisk, result.riskPercent, m_config.maxDailyRiskPercent);
    }

    return result;
}

void CUnifiedRiskManager::ConfigureClusterGovernance(const bool enabled,
                                                     const int maxConcurrentPerCluster,
                                                     const double maxClusterRiskPercent,
                                                     const bool enableMutex)
{
    m_validationGate.ConfigureClusterGovernance(enabled,
                                                maxConcurrentPerCluster,
                                                maxClusterRiskPercent,
                                                enableMutex);
}

//+------------------------------------------------------------------+
//| Register executed trade risk                                     |
//+------------------------------------------------------------------+
void CUnifiedRiskManager::RegisterExecutedTradeRisk(const SValidationResult &validationResult, const double fillRatio)
{
    if(!m_initialized)
        return;

    CheckAndResetDailyLimits();

    double riskUsed = validationResult.riskPercent;
    if(riskUsed <= 0.0)
        riskUsed = m_activeRiskPerTradePercent;
    double normalizedFillRatio = MathMax(0.0, MathMin(1.0, fillRatio));
    m_dailyRiskUsedPercent += MathMax(0.0, riskUsed * normalizedFillRatio);
}

//+------------------------------------------------------------------+
//| Remaining daily risk                                             |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::GetRemainingDailyRiskPercent()
{
    double remaining = m_config.maxDailyRiskPercent - GetEffectiveDailyRiskUsedPercent();
    if(remaining < 0.0)
        return 0.0;
    return remaining;
}

//+------------------------------------------------------------------+
//| Snapshot                                                         |
//+------------------------------------------------------------------+
SUnifiedRiskSnapshot CUnifiedRiskManager::GetSnapshot()
{
    SUnifiedRiskSnapshot snapshot;
    ZeroMemory(snapshot);

    snapshot.activeRiskPerTradePercent = m_activeRiskPerTradePercent;
    snapshot.dailyEntryRiskUsedPercent = MathMax(0.0, m_dailyRiskUsedPercent);
    snapshot.dailyMarkToMarketLossPercent = CalculateDailyMarkToMarketLossPercent();
    snapshot.openExposureRiskPercent = GetCurrentOpenExposureRiskPercent();
    snapshot.dailyRiskUsedPercent = MathMax(snapshot.dailyEntryRiskUsedPercent,
                                            MathMax(snapshot.dailyMarkToMarketLossPercent,
                                                    snapshot.openExposureRiskPercent));
    snapshot.maxDailyRiskPercent = m_config.maxDailyRiskPercent;
    snapshot.portfolioRiskPercent = snapshot.openExposureRiskPercent;
    snapshot.emergencyMode = m_portfolioRiskManager.IsEmergencyMode();
    snapshot.conservativeMode = m_conservativeMode;

    int total = 0;
    int approved = 0;
    int rejected = 0;
    double approvalRate = 0.0;
    m_validationGate.GetValidationStats(total, approved, rejected, approvalRate);
    snapshot.gateValidationCount = total;
    snapshot.gateApprovedCount = approved;
    snapshot.gateRejectedCount = rejected;

    if(CheckPointer(m_performanceAnalytics) != POINTER_INVALID)
    {
        CPerformanceAnalytics* analytics = m_performanceAnalytics;
        SPerformanceMetrics perf = analytics.GetPerformanceMetrics();
        snapshot.totalTrades = perf.totalTrades;
        snapshot.winningTrades = perf.winningTrades;
        snapshot.losingTrades = perf.losingTrades;
        snapshot.winRatePercent = perf.winRate;
        snapshot.profitFactor = perf.profitFactor;
        snapshot.netProfit = perf.totalProfit;
        snapshot.currentDrawdownPercent = analytics.GetCurrentDrawdown();
    }
    else
    {
        snapshot.currentDrawdownPercent = 0.0;
    }

    return snapshot;
}

//+------------------------------------------------------------------+
//| Runtime unprotected-position state                                |
//+------------------------------------------------------------------+
bool CUnifiedRiskManager::HasUnprotectedPositions()
{
    return (GetUnprotectedPositionCount() > 0);
}

int CUnifiedRiskManager::GetUnprotectedPositionCount()
{
    // Refresh portfolio risk state first so missing-stop flags are current.
    m_portfolioRiskManager.GetPortfolioRisk();
    return m_portfolioRiskManager.GetUnprotectedPositionCount();
}

//+------------------------------------------------------------------+
//| Mark-to-market daily drawdown component                           |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::CalculateDailyMarkToMarketLossPercent()
{
    double baselineEquity = m_dailyStartEquity;
    if(baselineEquity <= 0.0)
        baselineEquity = AccountInfoDouble(ACCOUNT_BALANCE);

    if(baselineEquity <= 0.0)
        return 0.0;

    double equityNow = AccountInfoDouble(ACCOUNT_EQUITY);
    return MathMax(0.0, ((baselineEquity - equityNow) / baselineEquity) * 100.0);
}

//+------------------------------------------------------------------+
//| Open exposure component                                           |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::GetCurrentOpenExposureRiskPercent()
{
    return m_portfolioRiskManager.GetPortfolioRisk();
}

//+------------------------------------------------------------------+
//| Effective daily risk usage (entry-budget + mark-to-market loss)  |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::GetEffectiveDailyRiskUsedPercent()
{
    double effective = MathMax(0.0, m_dailyRiskUsedPercent);
    effective = MathMax(effective, CalculateDailyMarkToMarketLossPercent());
    effective = MathMax(effective, GetCurrentOpenExposureRiskPercent());
    return effective;
}

//+------------------------------------------------------------------+
//| Update adaptive risk                                             |
//+------------------------------------------------------------------+
void CUnifiedRiskManager::UpdateAdaptiveRiskLevel()
{
    double targetRisk = m_config.baseRiskPerTradePercent;
    m_conservativeMode = false;

    if(!m_config.enableAdaptiveSizing)
    {
        m_activeRiskPerTradePercent = ClampRiskPercent(targetRisk);
        return;
    }

    CPerformanceAnalytics* analytics = m_performanceAnalytics;
    if(CheckPointer(analytics) == POINTER_INVALID)
    {
        m_activeRiskPerTradePercent = ClampRiskPercent(targetRisk);
        return;
    }

    SPerformanceMetrics perf = analytics.GetPerformanceMetrics();
    if(perf.totalTrades < m_config.adaptationMinTrades)
    {
        m_activeRiskPerTradePercent = ClampRiskPercent(targetRisk);
        return;
    }

    double reductionFactor = analytics.GetRecommendedRiskReduction();
    reductionFactor = MathMax(0.1, MathMin(1.0, reductionFactor));

    double drawdownValue = analytics.GetCurrentDrawdown();
    if(drawdownValue >= m_config.drawdownCriticalPercent)
        reductionFactor = MathMin(reductionFactor, 0.35);
    else if(drawdownValue >= m_config.drawdownWarningPercent)
        reductionFactor = MathMin(reductionFactor, 0.65);

    if(analytics.ShouldEnableConservativeMode())
    {
        m_conservativeMode = true;
        reductionFactor = MathMin(reductionFactor, 0.60);
    }

    targetRisk = m_config.baseRiskPerTradePercent * reductionFactor;
    m_activeRiskPerTradePercent = ClampRiskPercent(targetRisk);
}

//+------------------------------------------------------------------+
//| Day rollover check                                               |
//+------------------------------------------------------------------+
bool CUnifiedRiskManager::IsNewTradingDay(const datetime nowTime) const
{
    if(m_lastDailyReset <= 0)
        return true;

    MqlDateTime nowStruct;
    MqlDateTime resetStruct;
    TimeToStruct(nowTime, nowStruct);
    TimeToStruct(m_lastDailyReset, resetStruct);

    return (nowStruct.year != resetStruct.year ||
            nowStruct.mon != resetStruct.mon ||
            nowStruct.day != resetStruct.day);
}

//+------------------------------------------------------------------+
//| Clamp risk percent                                               |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::ClampRiskPercent(const double value) const
{
    return MathMax(m_config.minRiskPerTradePercent,
                   MathMin(m_config.maxRiskPerTradePercent, value));
}

#endif // CORE_RISK_UNIFIED_RISK_MANAGER_MQH
