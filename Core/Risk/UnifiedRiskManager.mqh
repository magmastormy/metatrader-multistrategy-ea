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
#include "VirtualPosition.mqh"

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
    int maxPositionsSameBase;
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
    double virtualReservedRiskPercent;     // Scan-time reserved candidate risk
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
    int virtualReservationCount;
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
    CVirtualPositionBook m_virtualPositionBook;
    CPerformanceAnalytics* m_performanceAnalytics;

    double m_activeRiskPerTradePercent;
    double m_dailyRiskUsedPercent;
    double m_dailyStartEquity;
    datetime m_lastDailyReset;
    bool m_initialized;
    bool m_conservativeMode;
    datetime m_lastPressureLogTime;
    
    // ENHANCEMENT: Drawdown Circuit Breaker (Batch 93 - Week 1)
    bool m_tradingEnabled;           // Master switch for trading
    double m_peakEquity;             // Highest equity reached
    double m_maxDrawdownFromPeak;    // Current max drawdown from peak
    int m_drawdownBreachCount;       // Number of times drawdown limit hit

public:
    CUnifiedRiskManager();
    ~CUnifiedRiskManager();

    bool Initialize(const SUnifiedRiskConfig &config, CPerformanceAnalytics* performanceAnalytics = NULL);

    // Called each cycle/new bar to keep limits and adaptive risk current.
    void RefreshRuntimeState();
    void CheckAndResetDailyLimits();
    
    // Set performance analytics after initialization
    void SetPerformanceAnalytics(CPerformanceAnalytics* analytics);

    // Single trade validation authority.
    SValidationResult ValidateTradeRequest(const STradeValidationRequest &request, const string phaseTag = "runtime");
    void ConfigureClusterGovernance(const bool enabled,
                                    const int maxConcurrentPerCluster,
                                    const double maxClusterRiskPercent,
                                    const bool enableMutex);
    bool ReserveVirtualPosition(const string ownerTag,
                                const STradeValidationRequest &request,
                                const double riskPercent);
    void ReleaseVirtualPosition(const string ownerTag);
    void ClearVirtualPositions();

    // Register accepted risk usage only after successful execution.
    void RegisterExecutedTradeRisk(const SValidationResult &validationResult, const double fillRatio = 1.0);

    double GetActiveRiskPerTradePercent() const { return m_activeRiskPerTradePercent; }
    double GetRecommendedRiskPerTradePercent(const double requestedRiskPercent = 0.0);
    double GetRemainingDailyRiskPercent();
    double GetRemainingPortfolioRiskPercent();
    double GetReservedVirtualRiskPercent() const;
    int GetVirtualReservationCount() const;
    SUnifiedRiskSnapshot GetSnapshot();
    bool HasUnprotectedPositions();
    int GetUnprotectedPositionCount();
    bool IsInitialized() const { return m_initialized; }
    
    // ENHANCEMENT: Circuit Breaker & Correlation Methods (Batch 93 - Week 1)
    bool CheckDrawdownCircuitBreaker();
    double GetCurrentDrawdownPercent() const;
    bool IsTradingEnabled() const;
    void ResetCircuitBreaker();
    bool CheckCorrelationRisk(const string symbol, double newRiskPercent);
    
    // ENHANCEMENT: Correlation and position risk methods (Batch 93)
    double GetSymbolCorrelation(const string symbol1, const string symbol2);
    double CalculatePositionRiskPercent(ulong ticket);

private:
    void UpdateAdaptiveRiskLevel();
    bool IsNewTradingDay(const datetime nowTime) const;
    double ClampRiskPercent(const double value) const;
    double CalculateDailyMarkToMarketLossPercent();
    double GetCurrentOpenExposureRiskPercent();
    double GetEffectiveDailyRiskUsedPercent(const double additionalRiskPercent = 0.0);
};

//+------------------------------------------------------------------+
//| Set Performance Analytics                                        |
//+------------------------------------------------------------------+
void CUnifiedRiskManager::SetPerformanceAnalytics(CPerformanceAnalytics* analytics)
{
    m_performanceAnalytics = analytics;
    if(analytics != NULL)
        Print("[RISK-UNIFIED] Performance analytics linked");
}

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
    m_conservativeMode(false),
    m_lastPressureLogTime(0),
    m_tradingEnabled(true),
    m_peakEquity(0.0),
    m_maxDrawdownFromPeak(0.0),
    m_drawdownBreachCount(0)
{
    m_config.baseRiskPerTradePercent = 10.0;
    m_config.minRiskPerTradePercent = 0.1;
    m_config.maxRiskPerTradePercent = 50.0;
    m_config.maxDailyRiskPercent = 30.0;
    m_config.maxPortfolioRiskPercent = 50.0;
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
        m_config.maxRiskPerTradePercent = 50.0;
    if(m_config.minRiskPerTradePercent <= 0.0)
        m_config.minRiskPerTradePercent = 0.1;
    if(m_config.baseRiskPerTradePercent <= 0.0)
        m_config.baseRiskPerTradePercent = m_config.maxRiskPerTradePercent;
    if(m_config.maxDailyRiskPercent <= 0.0)
        m_config.maxDailyRiskPercent = 30.0;
    if(m_config.maxPortfolioRiskPercent <= 0.0)
        m_config.maxPortfolioRiskPercent = 50.0;
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
                                    m_config.correlationThreshold,
                                    m_config.maxPositionsSameBase))
    {
        Print("[RISK-UNIFIED] Failed to initialize validation gate");
        return false;
    }

    m_validationGate.EnableAuditLogging(m_config.enableAuditLogging, m_config.auditLogFile);

    m_activeRiskPerTradePercent = ClampRiskPercent(m_config.baseRiskPerTradePercent);
    m_dailyRiskUsedPercent = 0.0;
    m_virtualPositionBook.Clear();
    m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(m_dailyStartEquity <= 0.0)
        m_dailyStartEquity = AccountInfoDouble(ACCOUNT_BALANCE);
    
    // ENHANCEMENT: Initialize drawdown circuit breaker (Batch 93 - Week 1)
    m_peakEquity = m_dailyStartEquity;
    m_maxDrawdownFromPeak = 0.0;
    m_drawdownBreachCount = 0;
    m_tradingEnabled = true;
    
    m_lastDailyReset = TimeCurrent();
    m_initialized = true;

    PrintFormat("[RISK-UNIFIED] Initialized | Base %.2f%% | Range %.2f-%.2f%% | Daily %.2f%% | Portfolio %.2f%%",
                m_config.baseRiskPerTradePercent,
                m_config.minRiskPerTradePercent,
                m_config.maxRiskPerTradePercent,
                m_config.maxDailyRiskPercent,
                m_config.maxPortfolioRiskPercent);
    
    PrintFormat("[RISK-CIRCUIT-BREAKER] Enabled | Initial Equity=%.2f | Drawdown Limits: Warning=%.1f%% Critical=%.1f%%",
                m_peakEquity, m_config.drawdownWarningPercent, m_config.drawdownCriticalPercent);

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
    
    // ENHANCEMENT: Drawdown Circuit Breaker Check (Batch 93 - Week 1)
    if(!CheckDrawdownCircuitBreaker())
    {
        result.message = "Trading paused: Drawdown circuit breaker activated";
        result.severity = ERROR_LEVEL_CRITICAL;
        return result;
    }

    CheckAndResetDailyLimits();

    double reservedRisk = GetReservedVirtualRiskPercent();
    double openExposureRisk = GetCurrentOpenExposureRiskPercent();
    double effectiveDailyRisk = GetEffectiveDailyRiskUsedPercent(reservedRisk);
    if(effectiveDailyRisk >= m_config.maxDailyRiskPercent)
    {
        result.message = StringFormat("Daily risk budget exhausted: %.2f%% / %.2f%%",
                                      effectiveDailyRisk, m_config.maxDailyRiskPercent);
        result.severity = ERROR_LEVEL_WARNING;
        return result;
    }

    if(m_virtualPositionBook.HasOpposingReservation(request.symbol, request.clusterCode, request.orderType))
    {
        result.message = StringFormat("Virtual reservation conflict on %s (opposing candidate already reserved)",
                                      request.symbol);
        result.severity = ERROR_LEVEL_WARNING;
        return result;
    }

    result = m_validationGate.ValidateTradeRequest(request);
    if(!result.approved)
        return result;

    double projectedPortfolioRisk = openExposureRisk + reservedRisk + MathMax(0.0, result.riskPercent);
    if(projectedPortfolioRisk > m_config.maxPortfolioRiskPercent)
    {
        result.approved = false;
        result.severity = ERROR_LEVEL_WARNING;
        result.message = StringFormat("Portfolio risk limit would be exceeded (%s): %.2f%% + %.2f%% > %.2f%%",
                                      phaseTag, openExposureRisk + reservedRisk, result.riskPercent, m_config.maxPortfolioRiskPercent);
        return result;
    }

    double projectedDailyRisk = GetEffectiveDailyRiskUsedPercent(reservedRisk + MathMax(0.0, result.riskPercent));
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

bool CUnifiedRiskManager::ReserveVirtualPosition(const string ownerTag,
                                                 const STradeValidationRequest &request,
                                                 const double riskPercent)
{
    if(!m_initialized)
        return false;

    bool reserved = m_virtualPositionBook.Reserve(ownerTag,
                                                  request.symbol,
                                                  request.orderType,
                                                  request.strategyCluster,
                                                  request.clusterCode,
                                                  request.lotSize,
                                                  riskPercent);
    if(reserved)
    {
        PrintFormat("[RISK-VIRTUAL] reserve | owner=%s | symbol=%s | lot=%.2f | risk=%.2f | cluster=%s",
                    ownerTag,
                    request.symbol,
                    request.lotSize,
                    riskPercent,
                    request.strategyCluster);
    }
    return reserved;
}

void CUnifiedRiskManager::ReleaseVirtualPosition(const string ownerTag)
{
    int before = m_virtualPositionBook.GetReservationCount();
    m_virtualPositionBook.ClearOwner(ownerTag);
    int after = m_virtualPositionBook.GetReservationCount();
    if(before != after)
    {
        PrintFormat("[RISK-VIRTUAL] release | owner=%s | remaining=%d",
                    ownerTag,
                    after);
    }
}

void CUnifiedRiskManager::ClearVirtualPositions()
{
    int count = m_virtualPositionBook.GetReservationCount();
    if(count <= 0)
        return;

    m_virtualPositionBook.Clear();
    Print("[RISK-VIRTUAL] clear | remaining=0");
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
    double remaining = m_config.maxDailyRiskPercent - GetEffectiveDailyRiskUsedPercent(GetReservedVirtualRiskPercent());
    if(remaining < 0.0)
        return 0.0;
    return remaining;
}

double CUnifiedRiskManager::GetRecommendedRiskPerTradePercent(const double requestedRiskPercent)
{
    if(!m_initialized)
        return 0.0;

    CheckAndResetDailyLimits();

    if(m_portfolioRiskManager.IsEmergencyMode() || HasUnprotectedPositions())
        return 0.0;

    double reservedRisk = GetReservedVirtualRiskPercent();
    double effectiveDailyRisk = GetEffectiveDailyRiskUsedPercent(reservedRisk);
    double openExposureRisk = GetCurrentOpenExposureRiskPercent() + reservedRisk;
    double remainingDailyRisk = MathMax(0.0, m_config.maxDailyRiskPercent - effectiveDailyRisk);
    double remainingPortfolioRisk = MathMax(0.0, m_config.maxPortfolioRiskPercent - openExposureRisk);
    double recommended = (requestedRiskPercent > 0.0) ? requestedRiskPercent : m_activeRiskPerTradePercent;
    recommended = MathMin(recommended, m_activeRiskPerTradePercent);
    recommended = MathMin(recommended, remainingDailyRisk);
    recommended = MathMin(recommended, remainingPortfolioRisk);

    if(recommended <= 0.0)
        return 0.0;

    double pressureMultiplier = 1.0;
    double dailyUtilization = (m_config.maxDailyRiskPercent > 0.0) ? (effectiveDailyRisk / m_config.maxDailyRiskPercent) : 0.0;
    double portfolioUtilization = (m_config.maxPortfolioRiskPercent > 0.0) ? (openExposureRisk / m_config.maxPortfolioRiskPercent) : 0.0;

    if(dailyUtilization >= 0.95)
        pressureMultiplier = MathMin(pressureMultiplier, 0.25);
    else if(dailyUtilization >= 0.85)
        pressureMultiplier = MathMin(pressureMultiplier, 0.50);
    else if(dailyUtilization >= 0.70)
        pressureMultiplier = MathMin(pressureMultiplier, 0.80);

    if(portfolioUtilization >= 0.92)
        pressureMultiplier = MathMin(pressureMultiplier, 0.30);
    else if(portfolioUtilization >= 0.80)
        pressureMultiplier = MathMin(pressureMultiplier, 0.60);
    else if(portfolioUtilization >= 0.65)
        pressureMultiplier = MathMin(pressureMultiplier, 0.85);

    if(m_conservativeMode)
        pressureMultiplier = MathMin(pressureMultiplier, 0.80);

    recommended *= pressureMultiplier;
    recommended = MathMin(recommended, remainingDailyRisk);
    recommended = MathMin(recommended, remainingPortfolioRisk);

    if(recommended <= 0.0)
        return 0.0;

    if(pressureMultiplier < 0.999)
    {
        datetime now = TimeCurrent();
        if(m_lastPressureLogTime == 0 || (now - m_lastPressureLogTime) >= 60)
        {
            PrintFormat("[RISK-THROTTLE] requested=%.2f | active=%.2f | recommended=%.2f | pressure=%.2f | daily_used=%.2f/%.2f | portfolio_used=%.2f/%.2f | conservative=%s",
                        requestedRiskPercent > 0.0 ? requestedRiskPercent : m_activeRiskPerTradePercent,
                        m_activeRiskPerTradePercent,
                        recommended,
                        pressureMultiplier,
                        effectiveDailyRisk,
                        m_config.maxDailyRiskPercent,
                        openExposureRisk,
                        m_config.maxPortfolioRiskPercent,
                        m_conservativeMode ? "true" : "false");
            m_lastPressureLogTime = now;
        }
    }

    if(recommended < m_config.minRiskPerTradePercent)
        return recommended;

    return ClampRiskPercent(recommended);
}

double CUnifiedRiskManager::GetRemainingPortfolioRiskPercent()
{
    double remaining = m_config.maxPortfolioRiskPercent - (GetCurrentOpenExposureRiskPercent() + GetReservedVirtualRiskPercent());
    if(remaining < 0.0)
        return 0.0;
    return remaining;
}

double CUnifiedRiskManager::GetReservedVirtualRiskPercent() const
{
    return m_virtualPositionBook.GetReservedRiskPercent();
}

int CUnifiedRiskManager::GetVirtualReservationCount() const
{
    return m_virtualPositionBook.GetReservationCount();
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
    snapshot.virtualReservedRiskPercent = GetReservedVirtualRiskPercent();
    snapshot.dailyRiskUsedPercent = GetEffectiveDailyRiskUsedPercent(snapshot.virtualReservedRiskPercent);
    snapshot.maxDailyRiskPercent = m_config.maxDailyRiskPercent;
    snapshot.portfolioRiskPercent = snapshot.openExposureRiskPercent + snapshot.virtualReservedRiskPercent;
    snapshot.virtualReservationCount = GetVirtualReservationCount();
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
double CUnifiedRiskManager::GetEffectiveDailyRiskUsedPercent(const double additionalRiskPercent)
{
    double additionalRisk = MathMax(0.0, additionalRiskPercent);
    double effective = MathMax(0.0, m_dailyRiskUsedPercent + additionalRisk);
    effective = MathMax(effective, CalculateDailyMarkToMarketLossPercent());
    effective = MathMax(effective, GetCurrentOpenExposureRiskPercent() + additionalRisk);
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

//+------------------------------------------------------------------+
//| ENHANCEMENT: Drawdown Circuit Breaker (Batch 93 - Week 1)         |
//| Checks if drawdown from peak equity exceeds limits                |
//| Returns: true if trading is allowed, false if circuit breaker hit |
//+------------------------------------------------------------------+
bool CUnifiedRiskManager::CheckDrawdownCircuitBreaker()
{
    if(!m_initialized)
        return false;
    
    double equityNow = AccountInfoDouble(ACCOUNT_EQUITY);
    
    // Update peak equity tracking
    if(equityNow > m_peakEquity)
    {
        m_peakEquity = equityNow;
        m_maxDrawdownFromPeak = 0.0;
    }
    
    // Calculate current drawdown from peak
    if(m_peakEquity > 0)
    {
        m_maxDrawdownFromPeak = ((m_peakEquity - equityNow) / m_peakEquity) * 100.0;
    }
    
    // Check critical drawdown limit - HARD STOP
    if(m_maxDrawdownFromPeak >= m_config.drawdownCriticalPercent)
    {
        if(m_tradingEnabled)
        {
            m_tradingEnabled = false;
            m_drawdownBreachCount++;
            
            PrintFormat("[RISK-CIRCUIT-BREAKER] CRITICAL BREACH | Drawdown=%.2f%% >= Limit=%.2f%% | Trading HALTED",
                       m_maxDrawdownFromPeak, m_config.drawdownCriticalPercent);
            PrintFormat("[RISK-CIRCUIT-BREAKER] Peak Equity=%.2f | Current Equity=%.2f | Loss=%.2f",
                       m_peakEquity, equityNow, m_peakEquity - equityNow);
            PrintFormat("[RISK-CIRCUIT-BREAKER] Breach count: %d | Manual reset required", m_drawdownBreachCount);
        }
        return false;
    }
    
    // Check warning drawdown limit - Reduce position sizes by 50%
    if(m_maxDrawdownFromPeak >= m_config.drawdownWarningPercent && m_maxDrawdownFromPeak < m_config.drawdownCriticalPercent)
    {
        if(m_conservativeMode == false)
        {
            m_conservativeMode = true;
            
            PrintFormat("[RISK-CIRCUIT-BREAKER] WARNING | Drawdown=%.2f%% >= Warning=%.2f%% | Position sizes reduced 50%%",
                       m_maxDrawdownFromPeak, m_config.drawdownWarningPercent);
            PrintFormat("[RISK-CIRCUIT-BREAKER] Peak Equity=%.2f | Current Equity=%.2f",
                       m_peakEquity, equityNow);
        }
        // Still allow trading but in conservative mode
        return true;
    }
    
    // Reset conservative mode if drawdown recovers
    if(m_maxDrawdownFromPeak < m_config.drawdownWarningPercent * 0.5 && m_conservativeMode)
    {
        m_conservativeMode = false;
        PrintFormat("[RISK-CIRCUIT-BREAKER] Recovery | Drawdown=%.2f%% < Half-Warning=%.2f%% | Normal mode restored",
                   m_maxDrawdownFromPeak, m_config.drawdownWarningPercent * 0.5);
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Get current drawdown status                                      |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::GetCurrentDrawdownPercent() const
{
    return m_maxDrawdownFromPeak;
}

//+------------------------------------------------------------------+
//| Check if trading is enabled                                      |
//+------------------------------------------------------------------+
bool CUnifiedRiskManager::IsTradingEnabled() const
{
    return m_tradingEnabled;
}

//+------------------------------------------------------------------+
//| Manually reset circuit breaker (after review)                    |
//+------------------------------------------------------------------+
void CUnifiedRiskManager::ResetCircuitBreaker()
{
    m_tradingEnabled = true;
    m_conservativeMode = false;
    m_drawdownBreachCount = 0;
    
    // Reset peak to current equity
    m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    m_maxDrawdownFromPeak = 0.0;
    
    Print("[RISK-CIRCUIT-BREAKER] Manually reset by operator | Trading resumed");
}

//+------------------------------------------------------------------+
//| ENHANCEMENT: Correlation-Aware Risk Check (Batch 93 - Week 1)     |
//| Prevents overexposure to highly correlated positions              |
//+------------------------------------------------------------------+
bool CUnifiedRiskManager::CheckCorrelationRisk(const string symbol, double newRiskPercent)
{
    if(!m_initialized || m_config.correlationThreshold <= 0.0)
        return true; // Skip if not configured
    
    // Get all open positions and calculate correlated risk
    double totalCorrelatedRisk = 0.0;
    int totalPositions = PositionsTotal();
    
    for(int i = 0; i < totalPositions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        
        string posSymbol = PositionGetString(POSITION_SYMBOL);
        if(posSymbol == symbol) continue; // Skip same symbol
        
        // Check correlation with new symbol
        double correlation = GetSymbolCorrelation(symbol, posSymbol);
        
        // If highly correlated, add to correlated risk
        if(correlation > m_config.correlationThreshold)
        {
            double posRisk = CalculatePositionRiskPercent(ticket);
            totalCorrelatedRisk += posRisk;
            
            PrintFormat("[RISK-CORRELATION] High correlation detected | %s <-> %s = %.2f | Pos Risk=%.2f%%",
                       symbol, posSymbol, correlation, posRisk);
        }
    }
    
    // Add new position risk
    totalCorrelatedRisk += newRiskPercent;
    
    // Check if correlated risk exceeds portfolio limit
    double maxCorrelatedRisk = m_config.maxPortfolioRiskPercent * 0.5; // Max 50% of portfolio in correlated positions
    
    if(totalCorrelatedRisk > maxCorrelatedRisk)
    {
        PrintFormat("[RISK-CORRELATION] REJECTED | Correlated risk=%.2f%% > Limit=%.2f%% (50%% of portfolio)",
                   totalCorrelatedRisk, maxCorrelatedRisk);
        return false;
    }
    
    PrintFormat("[RISK-CORRELATION] Approved | Correlated risk=%.2f%% < Limit=%.2f%%",
               totalCorrelatedRisk, maxCorrelatedRisk);
    
    return true;
}

//+------------------------------------------------------------------+
//| Helper: Calculate simple correlation between two symbols          |
//| Uses price change correlation over last N bars                    |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::GetSymbolCorrelation(const string symbol1, const string symbol2)
{
    // Simplified correlation: check if both symbols move in same direction
    // Over last 10 bars (can be enhanced with proper Pearson correlation)
    int lookback = 10;
    
    double close1[], close2[];
    if(CopyClose(symbol1, PERIOD_CURRENT, 1, lookback, close1) < lookback ||
       CopyClose(symbol2, PERIOD_CURRENT, 1, lookback, close2) < lookback)
        return 0.0; // Cannot calculate
    
    int sameDirection = 0;
    for(int i = 1; i < lookback; i++)
    {
        bool dir1 = (close1[i-1] > close1[i]); // Price went up?
        bool dir2 = (close2[i-1] > close2[i]);
        
        if(dir1 == dir2)
            sameDirection++;
    }
    
    // Correlation = same direction moves / total moves
    double correlation = (double)sameDirection / (double)(lookback - 1);
    
    return correlation;
}

//+------------------------------------------------------------------+
//| Helper: Calculate risk percent for a position                     |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::CalculatePositionRiskPercent(ulong ticket)
{
    if(!PositionSelectByTicket(ticket))
        return 0.0;
    
    double volume = PositionGetDouble(POSITION_VOLUME);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double sl = PositionGetDouble(POSITION_SL);
    
    if(sl == 0.0 || openPrice == 0.0)
        return 0.0; // No SL set
    
    string symbol = PositionGetString(POSITION_SYMBOL);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    
    double slDistance = MathAbs(openPrice - sl) / point;
    double riskAmount = volume * slDistance * tickValue;
    
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity <= 0.0)
        return 0.0;
    
    return (riskAmount / equity) * 100.0;
}

#endif // CORE_RISK_UNIFIED_RISK_MANAGER_MQH

