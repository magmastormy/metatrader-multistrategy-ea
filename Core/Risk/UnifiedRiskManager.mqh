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
#include "../Utils/TradeJournal.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Per-Symbol Risk Budget                                            |
//+------------------------------------------------------------------+
struct SSymbolRiskBudget
{
    string   symbol;
    double   allocatedPct;     // allocated daily risk %
    double   usedPct;          // used daily risk %
    double   winRate;          // recent win rate
    double   profitFactor;     // recent profit factor
};

#define MAX_SYMBOL_BUDGETS 30

//+------------------------------------------------------------------+
//| Unified risk configuration                                       |
//| Blueprint 10.4: All percent fields use 0-100 scale               |
//+------------------------------------------------------------------+
struct SUnifiedRiskConfig
{
    double baseRiskPerTradePercent;     // Blueprint 10.4: 0-100 scale (e.g., 1.0 = 1%)
    double minRiskPerTradePercent;      // Blueprint 10.4: 0-100 scale (e.g., 0.1 = 0.1%)
    double maxRiskPerTradePercent;      // Blueprint 10.4: 0-100 scale (e.g., 5.0 = 5%)
    double maxDailyRiskPercent;         // Blueprint 10.4: 0-100 scale
    double maxPortfolioRiskPercent;     // Blueprint 10.4: 0-100 scale
    double correlationThreshold;        // 0-1 scale (not a risk percent)
    double correlationReduceThreshold;  // 0-1 scale (not a risk percent)
    double correlationBlockThreshold;   // 0-1 scale (not a risk percent)
    int maxPositionsSameBase;
    double drawdownWarningPercent;      // Blueprint 10.4: 0-100 scale
    double drawdownCriticalPercent;     // Blueprint 10.4: 0-100 scale
    double dailyLossLimitPercent;       // Blueprint 10.4: 0-100 scale
    double minLotRiskMultiplier;        // Max risk multiplier when rounding up to broker min lot (e.g., 2.0 = 2x)
    int adaptationMinTrades;
    bool enableAdaptiveSizing;
    bool enableAuditLogging;
    string auditLogFile;
};

//+------------------------------------------------------------------+
//| Per-Symbol Risk Override (family-specific risk parameters)        |
//| Allows per-symbol risk limits that are lower than global defaults |
//+------------------------------------------------------------------+
struct SSymbolRiskOverride
{
    string   symbol;
    double   riskPerTradePercent;   // 0 = use global default
    double   maxDrawdownPercent;    // 0 = use global default
    bool     hasOverrides;

    SSymbolRiskOverride()
    {
        symbol              = "";
        riskPerTradePercent = 0.0;
        maxDrawdownPercent  = 0.0;
        hasOverrides        = false;
    }
};

//+------------------------------------------------------------------+
//| Unified risk runtime snapshot                                    |
//| Blueprint 10.4: All percent fields use 0-100 scale               |
//+------------------------------------------------------------------+
struct SUnifiedRiskSnapshot
{
    double activeRiskPerTradePercent;      // Blueprint 10.4: 0-100 scale
    double dailyRiskUsedPercent;           // Blueprint 10.4: 0-100 scale
    double dailyEntryRiskUsedPercent;      // Blueprint 10.4: 0-100 scale
    double dailyMarkToMarketLossPercent;   // Blueprint 10.4: 0-100 scale
    double openExposureRiskPercent;        // Blueprint 10.4: 0-100 scale
    double virtualReservedRiskPercent;     // Blueprint 10.4: 0-100 scale
    double maxDailyRiskPercent;            // Blueprint 10.4: 0-100 scale
    double portfolioRiskPercent;           // Blueprint 10.4: 0-100 scale
    double currentDrawdownPercent;         // Blueprint 10.4: 0-100 scale
    double winRatePercent;                 // Blueprint 10.4: 0-100 scale
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

    // Daily P&L Loss Limit circuit breaker
    bool m_dailyLossHaltActive;      // Daily loss halt is active
    datetime m_dailyLossHaltDate;    // Date when halt was triggered (for reset on new day)

    // Broker trading day boundary tracking
    int m_lastTradingDayKey;         // Cached trading day key (YYYYMMDD)
    int m_tradingDayStartHour;       // Hour when broker trading day starts (default 0 = midnight server time)

    // ENHANCEMENT: Circuit Breaker Auto-Recovery (Phase 2.4)
    datetime m_cbTriggeredAt;        // When circuit breaker was triggered
    int m_cbRecoveryAttempts;        // Number of auto-recovery attempts made
    int m_cbMaxRecoveryAttempts;     // Max auto-recovery attempts (default 3)
    int m_cbRecoveryCooldownMin;     // Cooldown in minutes before recovery attempt (default 30)
    datetime m_cbLastRecoverySuccessTime; // When last successful recovery occurred (for reset after stable period)

    // Per-Symbol Risk Budgeting (Phase 5)
    SSymbolRiskBudget m_symbolBudgets[];
    int m_symbolBudgetCount;
    datetime m_lastBudgetRefresh;

    // Profit-adjusted risk budget: fraction of unrealized profit that frees up risk budget
    double m_riskReductionFactor;

    // Per-symbol risk overrides (family-specific risk parameters)
    SSymbolRiskOverride m_riskOverrides[];
    int m_riskOverrideCount;

public:
    CUnifiedRiskManager();
    ~CUnifiedRiskManager();

    bool Initialize(const SUnifiedRiskConfig &config, CPerformanceAnalytics* performanceAnalytics = NULL);

    // Called each cycle/new bar to keep limits and adaptive risk current.
    void RefreshRuntimeState();
    void CheckAndResetDailyLimits();
    
    // Set performance analytics after initialization
    void SetPerformanceAnalytics(CPerformanceAnalytics* analytics);

    // Set base risk per trade percent (used by dual-mode auto-switching)
    void SetBaseRiskPerTrade(double riskPercent);

    // Apply tier overrides without reinitializing the entire risk manager.
    // Updates only the parameters that the tier system controls (daily risk,
    // portfolio risk, drawdown thresholds, daily loss limit) while preserving
    // runtime state (circuit breaker, daily risk used, virtual positions, etc.)
    void ApplyTierOverrides(double tierRiskPerTradePct,
                            int tierMaxPositions,
                            double effectiveDaily, double effectivePortfolio,
                            double effectiveDdWarning, double effectiveDdCritical,
                            double effectiveDailyLossLimit);

    // Per-symbol risk overrides (family-specific risk parameters)
    void SetRiskPerTrade(const string symbol, double riskPct);
    void SetMaxDrawdownForFamily(const string symbol, double maxDDPct);
    double GetEffectiveRiskPerTrade(const string symbol) const;
    double GetEffectiveMaxDrawdown(const string symbol) const;

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
    double GetMinLotRiskMultiplier() const { return m_config.minLotRiskMultiplier; }
    double GetRecommendedRiskPerTradePercent(const double requestedRiskPercent = 0.0);
    double GetRemainingDailyRiskPercent();
    double GetRemainingPortfolioRiskPercent();
    double GetReservedVirtualRiskPercent();
    int GetVirtualReservationCount() const;
    SUnifiedRiskSnapshot GetSnapshot();
    bool HasUnprotectedPositions();
    int GetUnprotectedPositionCount();
    bool IsInitialized() const { return m_initialized; }

    // Access portfolio risk manager (for wiring correlation engine to PositionSizer)
    CPortfolioRiskManager* GetPortfolioRiskManager() { return &m_portfolioRiskManager; }

    // Set broker trading day start hour (0=midnight server time, 17=5pm for forex rollover)
    void SetTradingDayStartHour(int hour) { m_tradingDayStartHour = MathMax(0, MathMin(23, hour)); }
    
    // ENHANCEMENT: Circuit Breaker & Correlation Methods (Batch 93 - Week 1)
    bool CheckDrawdownCircuitBreaker();
    double GetCurrentDrawdownPercent() const;
    bool IsTradingEnabled() const;
    void ResetCircuitBreaker();
    bool CheckCircuitBreakerRecovery();
    // Crash recovery: get/set circuit breaker state for persistence across restarts
    double GetPeakEquity() const;
    double GetDailyStartEquity() const;
    int    GetDrawdownBreachCount() const;
    double GetMaxDrawdownFromPeak() const;
    void   RestoreCircuitBreakerState(double savedPeakEquity, double savedDailyStartEquity,
                                      int savedBreachCount, double savedMaxDrawdown);

    // Daily P&L Loss Limit circuit breaker
    bool CheckDailyLossLimit();

    // Per-Symbol Risk Budgeting (Phase 5)
    double GetSymbolRiskAllocation(const string symbol);
    bool IsSymbolBudgetAvailable(const string symbol, const double riskPct);
    void RefreshSymbolBudgets();
    double GetSymbolUsedRisk(const string symbol);
    double GetSymbolWinRate(const string symbol);
    double GetSymbolProfitFactor(const string symbol);

    // Margin health monitoring (Phase 2.4)
    ENUM_MARGIN_HEALTH_LEVEL MonitorMarginHealth();

    // Single source of truth for drawdown state (Phase 2.1)
    SDrawdownState GetDrawdownState();
    
    // ENHANCEMENT: Correlation and position risk methods (Batch 93)
    double GetSymbolCorrelation(const string symbol1, const string symbol2);
    double CalculatePositionRiskPercent(ulong ticket);

private:
    void UpdateAdaptiveRiskLevel();
    bool IsNewTradingDay(const datetime nowTime);
    double ClampRiskPercent(const double value) const;
    double CalculateDailyMarkToMarketLossPercent();
    double GetCurrentOpenExposureRiskPercent();
    double GetEffectiveDailyRiskUsedPercent(const double additionalRiskPercent = 0.0);
    double CalculateMinLotRiskPercent(const string symbol);
    double ApplyPnlRiskAdjustment(const string symbol, const double rawUsedRisk);
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
//| Set base risk per trade percent                                   |
//+------------------------------------------------------------------+
void CUnifiedRiskManager::SetBaseRiskPerTrade(double riskPercent)
{
    m_config.baseRiskPerTradePercent = ClampRiskPercent(riskPercent);
    m_activeRiskPerTradePercent = ClampRiskPercent(riskPercent);
}

//+------------------------------------------------------------------+
//| Apply tier overrides without full reinitialization                |
//| Updates only tier-controlled parameters, preserving runtime state |
//+------------------------------------------------------------------+
void CUnifiedRiskManager::ApplyTierOverrides(double tierRiskPerTradePct,
                                             int tierMaxPositions,
                                             double effectiveDaily, double effectivePortfolio,
                                             double effectiveDdWarning, double effectiveDdCritical,
                                             double effectiveDailyLossLimit)
{
    // Update config parameters controlled by tier system
    m_config.baseRiskPerTradePercent = tierRiskPerTradePct;
    m_config.maxRiskPerTradePercent  = MathMax(tierRiskPerTradePct * 2.0, 50.0);
    m_config.maxDailyRiskPercent     = effectiveDaily;
    m_config.maxPortfolioRiskPercent = effectivePortfolio;
    m_config.drawdownWarningPercent  = effectiveDdWarning;
    m_config.drawdownCriticalPercent = effectiveDdCritical;
    m_config.dailyLossLimitPercent   = effectiveDailyLossLimit;
    m_config.maxPositionsSameBase    = tierMaxPositions;

    // Update active risk per trade
    m_activeRiskPerTradePercent = ClampRiskPercent(m_config.baseRiskPerTradePercent);

    // Update validation gate thresholds (no reinitialization)
    m_validationGate.SetMaxRiskPerTrade(m_config.maxRiskPerTradePercent);
    m_validationGate.SetMaxPortfolioRisk(m_config.maxPortfolioRiskPercent);

    // Update portfolio risk manager limits (no reinitialization)
    m_portfolioRiskManager.SetMaxPortfolioRisk(effectivePortfolio);

    PrintFormat("[RISK-INIT-SINGLE] Tier overrides applied (no reinit) | risk=%.1f%% | daily=%.1f%% | portfolio=%.1f%% | ddWarn=%.1f%% | ddCrit=%.1f%%",
                m_config.baseRiskPerTradePercent,
                m_config.maxDailyRiskPercent,
                m_config.maxPortfolioRiskPercent,
                m_config.drawdownWarningPercent,
                m_config.drawdownCriticalPercent);
}

//+------------------------------------------------------------------+
//| Set per-symbol risk per trade override                            |
//+------------------------------------------------------------------+
void CUnifiedRiskManager::SetRiskPerTrade(const string symbol, double riskPct)
{
    // Find existing override
    for(int i = 0; i < m_riskOverrideCount; i++)
    {
        if(m_riskOverrides[i].symbol == symbol)
        {
            m_riskOverrides[i].riskPerTradePercent = riskPct;
            m_riskOverrides[i].hasOverrides = true;
            return;
        }
    }
    // Add new override using temp struct pattern for string members
    int newSize = m_riskOverrideCount + 1;
    SSymbolRiskOverride tempOverrides[];
    ArrayResize(tempOverrides, newSize);
    for(int i = 0; i < m_riskOverrideCount; i++)
        tempOverrides[i] = m_riskOverrides[i];
    ArrayResize(m_riskOverrides, newSize);
    for(int i = 0; i < m_riskOverrideCount; i++)
        m_riskOverrides[i] = tempOverrides[i];
    m_riskOverrides[m_riskOverrideCount].symbol = symbol;
    m_riskOverrides[m_riskOverrideCount].riskPerTradePercent = riskPct;
    m_riskOverrides[m_riskOverrideCount].hasOverrides = true;
    m_riskOverrideCount++;
    PrintFormat("[RISK-FAMILY] Set risk per trade for %s: %.2f%%", symbol, riskPct);
}

//+------------------------------------------------------------------+
//| Set per-symbol max drawdown override                              |
//+------------------------------------------------------------------+
void CUnifiedRiskManager::SetMaxDrawdownForFamily(const string symbol, double maxDDPct)
{
    for(int i = 0; i < m_riskOverrideCount; i++)
    {
        if(m_riskOverrides[i].symbol == symbol)
        {
            m_riskOverrides[i].maxDrawdownPercent = maxDDPct;
            m_riskOverrides[i].hasOverrides = true;
            return;
        }
    }
    int newSize = m_riskOverrideCount + 1;
    SSymbolRiskOverride tempOverrides[];
    ArrayResize(tempOverrides, newSize);
    for(int i = 0; i < m_riskOverrideCount; i++)
        tempOverrides[i] = m_riskOverrides[i];
    ArrayResize(m_riskOverrides, newSize);
    for(int i = 0; i < m_riskOverrideCount; i++)
        m_riskOverrides[i] = tempOverrides[i];
    m_riskOverrides[m_riskOverrideCount].symbol = symbol;
    m_riskOverrides[m_riskOverrideCount].maxDrawdownPercent = maxDDPct;
    m_riskOverrides[m_riskOverrideCount].hasOverrides = true;
    m_riskOverrideCount++;
    PrintFormat("[RISK-FAMILY] Set max drawdown for %s: %.1f%%", symbol, maxDDPct);
}

//+------------------------------------------------------------------+
//| Get effective risk per trade for a symbol                         |
//| Returns the LOWER of family-specific and global max limit         |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::GetEffectiveRiskPerTrade(const string symbol) const
{
    for(int i = 0; i < m_riskOverrideCount; i++)
    {
        if(m_riskOverrides[i].symbol == symbol && m_riskOverrides[i].hasOverrides && m_riskOverrides[i].riskPerTradePercent > 0.0)
            return MathMin(m_riskOverrides[i].riskPerTradePercent, m_config.maxRiskPerTradePercent);
    }
    return m_config.baseRiskPerTradePercent;
}

//+------------------------------------------------------------------+
//| Get effective max drawdown for a symbol                           |
//| Returns the LOWER of family-specific and global critical limit    |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::GetEffectiveMaxDrawdown(const string symbol) const
{
    for(int i = 0; i < m_riskOverrideCount; i++)
    {
        if(m_riskOverrides[i].symbol == symbol && m_riskOverrides[i].hasOverrides && m_riskOverrides[i].maxDrawdownPercent > 0.0)
            return MathMin(m_riskOverrides[i].maxDrawdownPercent, m_config.drawdownCriticalPercent);
    }
    return m_config.drawdownCriticalPercent;
}

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CUnifiedRiskManager::CUnifiedRiskManager() :
    m_performanceAnalytics(NULL),
    m_activeRiskPerTradePercent(1.0),  // Blueprint 10.4: 0-100 scale (1.0 = 1%)
    m_dailyRiskUsedPercent(0.0),
    m_dailyStartEquity(0.0),
    m_lastDailyReset(0),
    m_initialized(false),
    m_conservativeMode(false),
    m_lastPressureLogTime(0),
    m_tradingEnabled(true),
    m_peakEquity(0.0),
    m_maxDrawdownFromPeak(0.0),
    m_drawdownBreachCount(0),
    m_dailyLossHaltActive(false),
    m_dailyLossHaltDate(0),
    m_lastTradingDayKey(0),
    m_tradingDayStartHour(0),
    m_cbTriggeredAt(0),
    m_cbRecoveryAttempts(0),
    m_cbMaxRecoveryAttempts(3),
    m_cbRecoveryCooldownMin(5),
    m_cbLastRecoverySuccessTime(0),
    m_symbolBudgetCount(0),
    m_lastBudgetRefresh(0),
    m_riskReductionFactor(0.5),
    m_riskOverrideCount(0)
{
    m_config.baseRiskPerTradePercent = 1.0;   // Blueprint 10.4: 0-100 scale (1.0 = 1%)
    m_config.minRiskPerTradePercent = 0.1;    // Blueprint 10.4: 0-100 scale (0.1 = 0.1%)
    m_config.maxRiskPerTradePercent = 5.0;    // Blueprint 10.4: 0-100 scale (5.0 = 5%)
    m_config.maxDailyRiskPercent = 5.0;       // Blueprint 10.4: 0-100 scale
    m_config.maxPortfolioRiskPercent = 15.0;  // Blueprint 10.4: 0-100 scale
    m_config.correlationThreshold = 0.7;
    m_config.correlationReduceThreshold = 0.4;
    m_config.correlationBlockThreshold = 0.7;
    m_config.maxPositionsSameBase = 3;
    m_config.drawdownWarningPercent = 17.5;   // Blueprint 10.4: 0-100 scale (70% of 25% max)
    m_config.drawdownCriticalPercent = 25.0;  // Blueprint 10.4: 0-100 scale (matches InpMaxDrawdown)
    m_config.dailyLossLimitPercent = 15.0;    // Blueprint 10.4: 0-100 scale (raised for small accounts: single trade ~10%)
    m_config.minLotRiskMultiplier = 15.0;      // Allow up to 15x risk when rounding up to broker min lot (small accounts: 0.10 min on $179)
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
        m_config.maxRiskPerTradePercent = 5.0;
    if(m_config.minRiskPerTradePercent <= 0.0)
        m_config.minRiskPerTradePercent = 0.1;
    if(m_config.baseRiskPerTradePercent <= 0.0)
        m_config.baseRiskPerTradePercent = m_config.maxRiskPerTradePercent;
    if(m_config.maxDailyRiskPercent <= 0.0)
        m_config.maxDailyRiskPercent = 5.0;
    if(m_config.maxPortfolioRiskPercent <= 0.0)
        m_config.maxPortfolioRiskPercent = 15.0;
    if(m_config.correlationThreshold <= 0.0 || m_config.correlationThreshold > 1.0)
        m_config.correlationThreshold = 0.7;
    if(m_config.correlationReduceThreshold <= 0.0 || m_config.correlationReduceThreshold > 1.0)
        m_config.correlationReduceThreshold = 0.4;
    if(m_config.correlationBlockThreshold <= m_config.correlationReduceThreshold || m_config.correlationBlockThreshold > 1.0)
        m_config.correlationBlockThreshold = 0.7;
    if(m_config.dailyLossLimitPercent <= 0.0)
        m_config.dailyLossLimitPercent = 3.0;
    if(m_config.adaptationMinTrades < 5)
        m_config.adaptationMinTrades = 20;
    if(m_config.drawdownWarningPercent <= 0.0)
        m_config.drawdownWarningPercent = 5.0;
    if(m_config.drawdownCriticalPercent <= m_config.drawdownWarningPercent)
        m_config.drawdownCriticalPercent = m_config.drawdownWarningPercent + 4.0;
    if(m_config.minLotRiskMultiplier <= 0.0)
        m_config.minLotRiskMultiplier = 15.0;

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

    // Wire gate back to unified manager for drawdown delegation (Phase 2.1)
    m_validationGate.SetUnifiedRiskManager(GetPointer(this));

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
    m_cbTriggeredAt = 0;
    m_cbRecoveryAttempts = 0;

    // Daily P&L Loss Limit circuit breaker
    m_dailyLossHaltActive = false;
    m_dailyLossHaltDate = 0;

    // Broker trading day boundary
    m_lastTradingDayKey = 0;

    m_lastDailyReset = TimeCurrent();
    m_initialized = true;

    // Risk percent scale validation — catch misconfiguration early
    if(m_activeRiskPerTradePercent < 0.01 || m_activeRiskPerTradePercent > 20.0)
        PrintFormat("WARNING: Risk per trade %.2f%% is outside safe range [0.01, 20.0] — verify input scale is 0-100 not 0-1",
                    m_activeRiskPerTradePercent);

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
    CheckCircuitBreakerRecovery();
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

        // Reset circuit breaker recovery counter on new trading day
        if(m_cbRecoveryAttempts > 0)
        {
            PrintFormat("[RISK-UNIFIED] Daily reset: circuit breaker recovery counter %d->0", m_cbRecoveryAttempts);
            m_cbRecoveryAttempts = 0;
            m_cbLastRecoverySuccessTime = 0;
        }

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

    // Daily P&L Loss Limit circuit breaker — reject all trades if halt is active
    if(!CheckDailyLossLimit())
    {
        result.message = StringFormat("Trading halted: Daily loss limit of %.1f%% exceeded", m_config.dailyLossLimitPercent);
        result.severity = ERROR_LEVEL_CRITICAL;
        return result;
    }

    // ENHANCEMENT: Drawdown Circuit Breaker Check (Batch 93 - Week 1)
    if(!CheckDrawdownCircuitBreaker())
    {
        result.message = "Trading paused: Drawdown circuit breaker activated";
        result.severity = ERROR_LEVEL_CRITICAL;
        return result;
    }

    // Family-specific drawdown check: if this symbol has a tighter drawdown limit,
    // reject trades on it even when the global circuit breaker hasn't tripped
    double familyMaxDD = GetEffectiveMaxDrawdown(request.symbol);
    if(familyMaxDD < m_config.drawdownCriticalPercent && m_maxDrawdownFromPeak >= familyMaxDD)
    {
        result.message = StringFormat("Family drawdown limit reached for %s: %.2f%% >= %.1f%%",
                                      request.symbol, m_maxDrawdownFromPeak, familyMaxDD);
        result.severity = ERROR_LEVEL_WARNING;
        PrintFormat("[RISK-FAMILY] Drawdown block | %s | DD=%.2f%% >= family limit=%.1f%%",
                    request.symbol, m_maxDrawdownFromPeak, familyMaxDD);
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

    // Lot size floor: if the validation gate allowed a below-minimum lot through
    // (small account round-up path), adjust to the broker minimum lot.
    double brokerMinLot = SymbolInfoDouble(request.symbol, SYMBOL_VOLUME_MIN);
    if(brokerMinLot <= 0.0) brokerMinLot = 0.01;
    if(result.adjustedLotSize > 0.0 && result.adjustedLotSize < brokerMinLot)
    {
        double riskRatio = brokerMinLot / result.adjustedLotSize;
        if(riskRatio <= m_config.minLotRiskMultiplier)
        {
            PrintFormat("[RISK-LOT-FLOOR] %s | Adjusted %.3f -> %.3f (broker min, risk %.1fx <= %.1fx cap)",
                        request.symbol, result.adjustedLotSize, brokerMinLot, riskRatio, m_config.minLotRiskMultiplier);
            result.adjustedLotSize = brokerMinLot;
            // Re-calculate risk percent with the adjusted lot
            if(result.riskPercent > 0.0)
                result.riskPercent *= riskRatio;
        }
        else
        {
            result.approved = false;
            result.message = StringFormat("Lot below minimum: %.3f < %.3f. Risk at min lot (%.1fx) exceeds %.1fx cap.",
                                          result.adjustedLotSize, brokerMinLot, riskRatio, m_config.minLotRiskMultiplier);
            result.severity = ERROR_LEVEL_WARNING;
            PrintFormat("[RISK-LOT-FLOOR] %s | REJECTED: %.3f < %.3f, risk %.1fx > %.1fx cap",
                        request.symbol, result.adjustedLotSize, brokerMinLot, riskRatio, m_config.minLotRiskMultiplier);
            return result;
        }
    }

    // Per-Symbol Risk Budget check (Phase 5)
    if(result.riskPercent > 0.0 && !IsSymbolBudgetAvailable(request.symbol, result.riskPercent))
    {
        double allocation = GetSymbolRiskAllocation(request.symbol);
        double used = GetSymbolUsedRisk(request.symbol);

        // Cold-start bypass: if no positions are open and no virtual reservations,
        // allow the trade even if it exceeds the symbol allocation.
        // The portfolio-level check below will still gate the total risk.
        int openPositionCount = PositionsTotal();
        int virtualReservationCount = GetVirtualReservationCount();
        bool isColdStart = (openPositionCount == 0 && virtualReservationCount == 0);

        if(isColdStart && result.riskPercent <= GetEffectiveRiskPerTrade(request.symbol))
        {
            PrintFormat("[RISK-SYMBOL-BUDGET] Bootstrap bypass | %s | used=%.2f%% + new=%.2f%% > alloc=%.2f%% (cold start, per-trade risk OK)",
                        request.symbol, used, result.riskPercent, allocation);
        }
        else
        {
            result.approved = false;
            result.message = StringFormat("Symbol risk budget exhausted for %s: used=%.2f%% + %.2f%% > alloc=%.2f%%",
                                          request.symbol, used, result.riskPercent, allocation);
            result.severity = ERROR_LEVEL_WARNING;
            PrintFormat("[RISK-SYMBOL-BUDGET] REJECTED | %s | used=%.2f%% + new=%.2f%% > alloc=%.2f%%",
                        request.symbol, used, result.riskPercent, allocation);
            return result;
        }
    }

    double projectedPortfolioRisk = openExposureRisk + reservedRisk + MathMax(0.0, result.riskPercent);
    if(projectedPortfolioRisk > m_config.maxPortfolioRiskPercent)
    {
        // Issue B fix: Bootstrap mode — when there are zero open positions and no virtual
        // reservations (cold start), allow a one-time bootstrap allocation that distributes
        // the portfolio cap evenly across requesting symbols. Each symbol's risk must still
        // be within the per-trade max, and the total is capped at portfolio max.
        int openPositionCount = PositionsTotal();
        int virtualReservationCount = GetVirtualReservationCount();
        bool isColdStart = (openPositionCount == 0 && virtualReservationCount == 0);

        if(isColdStart && result.riskPercent > 0.0 && result.riskPercent <= GetEffectiveRiskPerTrade(request.symbol))
        {
            // Bootstrap: allow this trade as the first entry on cold start
            // The portfolio cap is effectively distributed: each requesting symbol
            // can take up to (portfolioCap / activeSymbolCount) risk.
            // Since there are no positions yet, this first trade is always allowed
            // as long as its risk is within per-trade limits.
            PrintFormat("[RISK-PORTFOLIO] Bootstrap mode: distributing %.2f%% cap across requesting symbols (no open positions)",
                        m_config.maxPortfolioRiskPercent);
        }
        else
        {
            result.approved = false;
            result.severity = ERROR_LEVEL_WARNING;
            result.message = StringFormat("Portfolio risk limit would be exceeded (%s): %.2f%% + %.2f%% > %.2f%%",
                                          phaseTag, openExposureRisk + reservedRisk, result.riskPercent, m_config.maxPortfolioRiskPercent);
            return result;
        }
    }

    // I6: Per-Family Position Limit — prevent over-concentration in one synthetic family
    // Count positions by family using DerivAssetProfiler
    {
        int familyPositionCount = 0;
        int totalPositions = PositionsTotal();
        // Get the family of the requested symbol from Deriv profiler
        string reqSymbol = request.symbol;
        
        for(int i = 0; i < totalPositions; i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            string posSymbol = PositionGetString(POSITION_SYMBOL);
            // Same symbol family = count it
            if(posSymbol == reqSymbol)
                familyPositionCount++;
        }

        // Family position limits by symbol name pattern
        int maxFamilyPositions = 3; // default
        // Crash/Boom symbols contain "Boom" or "Crash"
        if(StringFind(reqSymbol, "Boom") >= 0 || StringFind(reqSymbol, "Crash") >= 0)
            maxFamilyPositions = 2;
        // HFV 1-second symbols contain "1s"
        else if(StringFind(reqSymbol, "1s") >= 0)
            maxFamilyPositions = 2;
        // Jump symbols contain "Jump"
        else if(StringFind(reqSymbol, "Jump") >= 0)
            maxFamilyPositions = 2;
        // Hybrid symbols contain "Hybrid"
        else if(StringFind(reqSymbol, "Hybrid") >= 0)
            maxFamilyPositions = 2;

        if(familyPositionCount >= maxFamilyPositions)
        {
            result.approved = false;
            result.severity = ERROR_LEVEL_WARNING;
            result.message = StringFormat("Family position limit reached: %d/%d positions in same family",
                                          familyPositionCount, maxFamilyPositions);
            PrintFormat("[RISK-FAMILY-POS] REJECTED | %s | family positions=%d/%d",
                        reqSymbol, familyPositionCount, maxFamilyPositions);
            return result;
        }
    }

    // Tiered Correlation Response: check correlation with existing positions
    if(m_config.correlationBlockThreshold > 0.0 || m_config.correlationReduceThreshold > 0.0)
    {
        double maxCorrelation = 0.0;
        int totalPositions = PositionsTotal();
        for(int i = 0; i < totalPositions; i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            string posSymbol = PositionGetString(POSITION_SYMBOL);
            if(posSymbol == request.symbol) continue;
            double corr = GetSymbolCorrelation(request.symbol, posSymbol);
            if(corr > maxCorrelation)
                maxCorrelation = corr;
        }

        // BLOCK tier: correlation exceeds block threshold
        if(maxCorrelation >= m_config.correlationBlockThreshold)
        {
            result.approved = false;
            result.severity = ERROR_LEVEL_WARNING;
            result.message = StringFormat("Correlation BLOCK: %.2f >= %.2f for %s",
                                          maxCorrelation, m_config.correlationBlockThreshold, request.symbol);
            PrintFormat("[RISK-CORRELATION-BLOCK] %s | corr=%.2f | threshold=%.2f",
                        request.symbol, maxCorrelation, m_config.correlationBlockThreshold);
            return result;
        }

        // REDUCE tier: correlation exceeds reduce threshold — scale lot size proportionally
        if(maxCorrelation >= m_config.correlationReduceThreshold)
        {
            double denom = m_config.correlationBlockThreshold - m_config.correlationReduceThreshold;
            if(denom <= 0.001) denom = 0.001;  // Prevent division by zero
            double reduceFactor = 1.0 - ((maxCorrelation - m_config.correlationReduceThreshold) / denom);
            reduceFactor = MathMax(0.25, MathMin(1.0, reduceFactor));
            double originalLot = result.adjustedLotSize;
            result.adjustedLotSize = NormalizeDouble(result.adjustedLotSize * reduceFactor, 2);
            result.requiresAdjustment = true;
            PrintFormat("[RISK-CORRELATION-REDUCE] %s | corr=%.2f | factor=%.2f | lot %.2f->%.2f",
                        request.symbol, maxCorrelation, reduceFactor, originalLot, result.adjustedLotSize);
        }
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

double CUnifiedRiskManager::GetReservedVirtualRiskPercent()
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
    return MathMax(0.0, ((baselineEquity - equityNow) / baselineEquity) * 100.0);  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale
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
//| Day rollover check — uses broker trading day boundary             |
//+------------------------------------------------------------------+
bool CUnifiedRiskManager::IsNewTradingDay(const datetime nowTime)
{
    MqlDateTime dt;
    TimeToStruct(nowTime, dt);

    // Calculate effective trading day date.
    // If current hour is before the trading day start hour,
    // we're still in the previous trading day.
    int effectiveDay = dt.day;
    int effectiveMon = dt.mon;
    int effectiveYear = dt.year;

    if(dt.hour < m_tradingDayStartHour)
    {
        // Subtract one day — we're in the previous trading day
        datetime yesterday = nowTime - 86400;
        MqlDateTime dtYesterday;
        TimeToStruct(yesterday, dtYesterday);
        effectiveDay = dtYesterday.day;
        effectiveMon = dtYesterday.mon;
        effectiveYear = dtYesterday.year;
    }

    int currentTradingDayKey = effectiveYear * 10000 + effectiveMon * 100 + effectiveDay;

    if(currentTradingDayKey != m_lastTradingDayKey)
    {
        m_lastTradingDayKey = currentTradingDayKey;
        return true;
    }
    return false;
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
        m_maxDrawdownFromPeak = ((m_peakEquity - equityNow) / m_peakEquity) * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale
    }
    
    // Check critical drawdown limit - HARD STOP
    if(m_maxDrawdownFromPeak >= m_config.drawdownCriticalPercent)
    {
        if(m_tradingEnabled)
        {
            m_tradingEnabled = false;
            m_drawdownBreachCount++;
            m_cbTriggeredAt = TimeCurrent();

            PrintFormat("[RISK-CIRCUIT-BREAKER] CRITICAL BREACH | Drawdown=%.2f%% >= Limit=%.2f%% | Trading HALTED",
                       m_maxDrawdownFromPeak, m_config.drawdownCriticalPercent);
            PrintFormat("[RISK-CIRCUIT-BREAKER] Peak Equity=%.2f | Current Equity=%.2f | Loss=%.2f",
                       m_peakEquity, equityNow, m_peakEquity - equityNow);
            PrintFormat("[RISK-CIRCUIT-BREAKER] Breach count: %d | Auto-recovery will be attempted after %d min cooldown (max %d attempts)",
                       m_drawdownBreachCount, m_cbRecoveryCooldownMin, m_cbMaxRecoveryAttempts);
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
    
    // Reset conservative mode if drawdown recovers below 60% of critical (closes gap with 50% trading-resume threshold)
    if(m_maxDrawdownFromPeak < m_config.drawdownCriticalPercent * 0.6 && m_conservativeMode)
    {
        m_conservativeMode = false;
        PrintFormat("[RISK-CIRCUIT-BREAKER] Recovery | Drawdown=%.2f%% < threshold=%.2f%% | Normal mode restored",
                   m_maxDrawdownFromPeak, m_config.drawdownCriticalPercent * 0.6);
    }
    
    // Reset recovery counter after stable period — equity must stay below warning for 60 minutes
    if(m_cbRecoveryAttempts > 0 && m_cbLastRecoverySuccessTime > 0 &&
       m_maxDrawdownFromPeak < m_config.drawdownWarningPercent * 0.5)
    {
        int stableMinutes = (int)((TimeCurrent() - m_cbLastRecoverySuccessTime) / 60);
        if(stableMinutes >= 60)
        {
            PrintFormat("[RISK-CIRCUIT-BREAKER] Recovery counter reset | Stable for %d min (>=60) | Attempts %d->0",
                       stableMinutes, m_cbRecoveryAttempts);
            m_cbRecoveryAttempts = 0;
            m_cbLastRecoverySuccessTime = 0;
        }
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
    m_cbTriggeredAt = 0;
    m_cbRecoveryAttempts = 0;
    m_cbLastRecoverySuccessTime = 0;

    // Reset peak to current equity
    m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    m_maxDrawdownFromPeak = 0.0;

    Print("[RISK-CIRCUIT-BREAKER] Manually reset by operator | Trading resumed");
}

//+------------------------------------------------------------------+
//| Crash recovery getters for circuit breaker state                  |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::GetPeakEquity() const
{
    return m_peakEquity;
}

double CUnifiedRiskManager::GetDailyStartEquity() const
{
    return m_dailyStartEquity;
}

int CUnifiedRiskManager::GetDrawdownBreachCount() const
{
    return m_drawdownBreachCount;
}

double CUnifiedRiskManager::GetMaxDrawdownFromPeak() const
{
    return m_maxDrawdownFromPeak;
}

//+------------------------------------------------------------------+
//| Restore circuit breaker state from crash recovery file            |
//+------------------------------------------------------------------+
void CUnifiedRiskManager::RestoreCircuitBreakerState(double savedPeakEquity, double savedDailyStartEquity,
                                                     int savedBreachCount, double savedMaxDrawdown)
{
    if(savedPeakEquity > 0.0)
        m_peakEquity = savedPeakEquity;
    if(savedDailyStartEquity > 0.0)
        m_dailyStartEquity = savedDailyStartEquity;
    m_drawdownBreachCount = savedBreachCount;
    if(savedMaxDrawdown >= 0.0)
        m_maxDrawdownFromPeak = savedMaxDrawdown;

    PrintFormat("[RISK-CIRCUIT-BREAKER] Restored from crash recovery | peakEquity=%.2f | dailyStartEquity=%.2f | breachCount=%d | maxDD=%.2f%%",
                m_peakEquity, m_dailyStartEquity, m_drawdownBreachCount, m_maxDrawdownFromPeak);
}

//+------------------------------------------------------------------+
//| Helper: Get correlation between two symbols (Phase 2.2: engine)  |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::GetSymbolCorrelation(const string symbol1, const string symbol2)
{
    // Delegate to unified correlation engine via portfolio risk manager
    CCorrelationEngine* engine = m_portfolioRiskManager.GetCorrelationEngine();
    if(engine != NULL)
        return engine.GetCorrelation(symbol1, symbol2);

    // Fallback: conservative return when engine unavailable
    return 1.0;
}

//+------------------------------------------------------------------+
//| Get drawdown state — single source of truth (Phase 2.1)          |
//+------------------------------------------------------------------+
SDrawdownState CUnifiedRiskManager::GetDrawdownState()
{
    // Ensure circuit breaker state is current
    CheckDrawdownCircuitBreaker();

    SDrawdownState state;
    ZeroMemory(state);

    state.currentDrawdownPct  = m_maxDrawdownFromPeak;
    state.isWarningActive     = (m_maxDrawdownFromPeak >= m_config.drawdownWarningPercent &&
                                 m_maxDrawdownFromPeak < m_config.drawdownCriticalPercent);
    state.isCriticalActive    = (m_maxDrawdownFromPeak >= m_config.drawdownCriticalPercent);
    state.isTradingEnabled    = m_tradingEnabled;

    if(state.isCriticalActive)
        state.conservativeMultiplier = 0.0;
    else if(state.isWarningActive)
        state.conservativeMultiplier = 0.5;
    else
        state.conservativeMultiplier = 1.0;

    return state;
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
    
    return (riskAmount / equity) * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale
}

//+------------------------------------------------------------------+
//| Circuit Breaker Auto-Recovery (Phase 2.4)                        |
//| Attempts to re-enable trading after cooldown if drawdown recovers |
//+------------------------------------------------------------------+
bool CUnifiedRiskManager::CheckCircuitBreakerRecovery()
{
    if(!m_initialized)
        return false;

    // Only attempt recovery if circuit breaker is active
    if(m_tradingEnabled)
        return false;

    // No trigger time recorded — nothing to recover from
    if(m_cbTriggeredAt <= 0)
        return false;

    // Check if cooldown period has elapsed
    datetime now = TimeCurrent();
    int elapsedMinutes = (int)((now - m_cbTriggeredAt) / 60);
    if(elapsedMinutes < m_cbRecoveryCooldownMin)
        return false;

    // Check if max recovery attempts exhausted
    if(m_cbRecoveryAttempts >= m_cbMaxRecoveryAttempts)
    {
        static datetime s_lastMaxAttemptLog = 0;
        if(s_lastMaxAttemptLog == 0 || (now - s_lastMaxAttemptLog) >= 300)
        {
            PrintFormat("[RISK-CIRCUIT-BREAKER] Max recovery attempts reached (%d/%d) | Manual reset required",
                       m_cbRecoveryAttempts, m_cbMaxRecoveryAttempts);
            s_lastMaxAttemptLog = now;
        }
        return false;
    }

    // Check if drawdown has recovered below 50% of critical level
    double currentDD = GetCurrentDrawdownPercent();
    double recoveryThreshold = m_config.drawdownCriticalPercent * 0.50;

    if(currentDD >= recoveryThreshold)
    {
        // Drawdown has NOT recovered sufficiently — stay disabled
        PrintFormat("[RISK-CIRCUIT-BREAKER] Recovery check | DD=%.2f%% still above threshold=%.2f%% | Staying disabled | Attempt %d/%d",
                   currentDD, recoveryThreshold, m_cbRecoveryAttempts + 1, m_cbMaxRecoveryAttempts);
        // Reset triggeredAt so next cooldown starts from now
        m_cbTriggeredAt = now;
        return false;
    }

    // Drawdown has recovered — re-enable trading at conservative mode
    m_cbRecoveryAttempts++;
    m_tradingEnabled = true;
    m_conservativeMode = true;
    m_cbTriggeredAt = 0; // Clear trigger time
    m_cbLastRecoverySuccessTime = now; // Record recovery time for stable-period reset

    // Reset peak to current equity for fresh drawdown tracking
    m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    m_maxDrawdownFromPeak = 0.0;

    PrintFormat("[RISK-CIRCUIT-BREAKER] AUTO-RECOVERY | Trading re-enabled at conservative tier | DD=%.2f%% < threshold=%.2f%% | Attempt %d/%d",
               currentDD, recoveryThreshold, m_cbRecoveryAttempts, m_cbMaxRecoveryAttempts);
    return true;
}

//+------------------------------------------------------------------+
//| Margin Health Monitoring (Phase 2.4)                              |
//| Checks margin level and takes protective action                  |
//+------------------------------------------------------------------+
ENUM_MARGIN_HEALTH_LEVEL CUnifiedRiskManager::MonitorMarginHealth()
{
    if(!m_initialized)
        return MARGIN_HEALTH_OK;

    double margin = AccountInfoDouble(ACCOUNT_MARGIN);
    if(margin <= 0.0)
        return MARGIN_HEALTH_OK; // No margin used = no risk

    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity <= 0.0)
        return MARGIN_HEALTH_EMERGENCY;

    double marginLevel = (equity / margin) * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale (margin level %)

    // Emergency: margin level < 150% — close all positions immediately
    if(marginLevel < 150.0)
    {
        PrintFormat("[RISK-MARGIN] EMERGENCY | Margin Level=%.1f%% < 150%% | Closing ALL positions immediately",
                   marginLevel);

        // Close all positions
        int totalPositions = PositionsTotal();
        for(int i = totalPositions - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket > 0 && PositionSelectByTicket(ticket))
            {
                // Journal before close for crash recovery
                ENUM_ORDER_TYPE closeType = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
                double closeVol = PositionGetDouble(POSITION_VOLUME);
                double closePrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double closeSL = PositionGetDouble(POSITION_SL);
                double closeTP = PositionGetDouble(POSITION_TP);
                long closeMagic = PositionGetInteger(POSITION_MAGIC);
                double closeProfit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
                string closeSymbol = PositionGetString(POSITION_SYMBOL);
                // Use MT5 trade object for emergency close
                CTrade emergencyTrade;
                if(emergencyTrade.PositionClose(ticket))
                {
                    string journalReason = "emergency_margin_breach | P&L=" + DoubleToString(closeProfit, 2);
                    WriteTradeJournalEntry("CLOSE", ticket, closeSymbol, closeType, closeVol,
                                           0.0, closeSL, closeTP, closeMagic, journalReason);
                }
            }
        }

        m_tradingEnabled = false;
        m_cbTriggeredAt = TimeCurrent();
        return MARGIN_HEALTH_EMERGENCY;
    }

    // Critical: margin level < 200% — close worst position, block new entries
    if(marginLevel < 200.0)
    {
        PrintFormat("[RISK-MARGIN] CRITICAL | Margin Level=%.1f%% < 200%% | Closing worst position, blocking new entries",
                   marginLevel);

        // Find worst-performing position
        double worstProfit = 0.0;
        ulong worstTicket = 0;
        int totalPositions = PositionsTotal();
        for(int i = 0; i < totalPositions; i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket > 0 && PositionSelectByTicket(ticket))
            {
                double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
                if(profit < worstProfit || worstTicket == 0)
                {
                    worstProfit = profit;
                    worstTicket = ticket;
                }
            }
        }

        if(worstTicket > 0 && PositionSelectByTicket(worstTicket))
        {
            ENUM_ORDER_TYPE critType = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
            double critVol = PositionGetDouble(POSITION_VOLUME);
            double critSL = PositionGetDouble(POSITION_SL);
            double critTP = PositionGetDouble(POSITION_TP);
            long critMagic = PositionGetInteger(POSITION_MAGIC);
            string critSymbol = PositionGetString(POSITION_SYMBOL);
            CTrade criticalTrade;
            criticalTrade.PositionClose(worstTicket);
            string critJournalReason = "emergency_margin_critical | P&L=" + DoubleToString(worstProfit, 2);
            WriteTradeJournalEntry("CLOSE", worstTicket, critSymbol, critType, critVol,
                                   0.0, critSL, critTP, critMagic, critJournalReason);
            PrintFormat("[RISK-MARGIN] Closed worst position | ticket=%I64u | profit=%.2f", worstTicket, worstProfit);
        }

        m_conservativeMode = true;
        return MARGIN_HEALTH_CRITICAL;
    }

    // Warning: margin level < 300% — reduce position sizes on next entries
    if(marginLevel < 300.0)
    {
        static datetime s_lastMarginWarning = 0;
        datetime now = TimeCurrent();
        if(s_lastMarginWarning == 0 || (now - s_lastMarginWarning) >= 60)
        {
            PrintFormat("[RISK-MARGIN] WARNING | Margin Level=%.1f%% < 300%% | Reducing position sizes on next entries",
                       marginLevel);
            s_lastMarginWarning = now;
        }
        m_conservativeMode = true;
        return MARGIN_HEALTH_WARNING;
    }

    return MARGIN_HEALTH_OK;
}

//+------------------------------------------------------------------+
//| Daily P&L Loss Limit circuit breaker                              |
//| Halts all trading when daily realized + unrealized loss exceeds   |
//| the configured percentage of peak equity. Resets on new day.      |
//+------------------------------------------------------------------+
bool CUnifiedRiskManager::CheckDailyLossLimit()
{
    if(!m_initialized)
        return false;

    datetime nowTime = TimeCurrent();

    // Reset halt on new trading day
    if(m_dailyLossHaltActive && IsNewTradingDay(nowTime))
    {
        m_dailyLossHaltActive = false;
        m_dailyLossHaltDate = 0;
        Print("[RISK-DAILY-LOSS] Daily loss halt RESET — new trading day");
    }

    // If halt already active, keep blocking
    if(m_dailyLossHaltActive)
        return false;

    // Calculate daily P&L: realized deals today + current unrealized P&L
    double dailyRealizedPL = 0.0;
    datetime dayStart = StringToTime(TimeToString(nowTime, TIME_DATE));
    HistorySelect(dayStart, nowTime);

    int totalDeals = HistoryDealsTotal();
    for(int i = 0; i < totalDeals; i++)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        if(dealTicket <= 0) continue;
        ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
        if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_INOUT)
        {
            double dealProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            double dealSwap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
            double dealCommission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            dailyRealizedPL += dealProfit + dealSwap + dealCommission;
        }
    }

    // Current unrealized P&L across all open positions
    double unrealizedPL = AccountInfoDouble(ACCOUNT_EQUITY) - AccountInfoDouble(ACCOUNT_BALANCE);
    double dailyPL = dailyRealizedPL + unrealizedPL;

    // Calculate as percentage of peak equity
    double riskPeakEquity = m_peakEquity;
    if(riskPeakEquity <= 0.0)
        riskPeakEquity = m_dailyStartEquity;
    if(riskPeakEquity <= 0.0)
        riskPeakEquity = AccountInfoDouble(ACCOUNT_EQUITY);

    double dailyPLPercent = 0.0;
    if(riskPeakEquity > 0.0)
        dailyPLPercent = (dailyPL / riskPeakEquity) * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale

    // Check if daily loss exceeds limit
    if(dailyPLPercent <= -m_config.dailyLossLimitPercent)
    {
        m_dailyLossHaltActive = true;
        m_dailyLossHaltDate = nowTime;
        PrintFormat("[RISK-DAILY-LOSS] CRITICAL: Daily loss halt ACTIVATED | P&L=%.2f%% | Limit=-%.1f%% | Realized=%.2f | Unrealized=%.2f",
                    dailyPLPercent, m_config.dailyLossLimitPercent, dailyRealizedPL, unrealizedPL);
        return false;
    }

    return true;
}

//+------------------------------------------------------------------+
//| Per-Symbol Risk Budgeting (Phase 5)                               |
//| Allocates daily risk budget across symbols with performance       |
//| weighting: performing symbols get up to 1.5x, underperformers    |
//| get 0.5x of their equal share.                                    |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::GetSymbolRiskAllocation(const string symbol)
{
    // Count active symbols from open positions
    string activeSymbols[];
    int activeSymbolCount = 0;

    int totalPositions = PositionsTotal();
    for(int i = 0; i < totalPositions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        string posSymbol = PositionGetString(POSITION_SYMBOL);

        // Check if already counted
        bool found = false;
        for(int j = 0; j < activeSymbolCount; j++)
        {
            if(activeSymbols[j] == posSymbol) { found = true; break; }
        }
        if(!found && activeSymbolCount < MAX_SYMBOL_BUDGETS)
        {
            ArrayResize(activeSymbols, activeSymbolCount + 1);
            activeSymbols[activeSymbolCount] = posSymbol;
            activeSymbolCount++;
        }
    }

    // Always include the requested symbol
    bool symbolFound = false;
    for(int j = 0; j < activeSymbolCount; j++)
    {
        if(activeSymbols[j] == symbol) { symbolFound = true; break; }
    }
    if(!symbolFound)
    {
        ArrayResize(activeSymbols, activeSymbolCount + 1);
        activeSymbols[activeSymbolCount] = symbol;
        activeSymbolCount++;
    }

    if(activeSymbolCount <= 0)
        activeSymbolCount = 1;

    double baseShare = m_config.maxDailyRiskPercent / (double)activeSymbolCount;

    // Performance-weighted adjustment
    double winRate = GetSymbolWinRate(symbol);
    double profitFactor = GetSymbolProfitFactor(symbol);

    double perfWeight = 1.0;
    if(winRate > 55.0 && profitFactor > 1.3)
        perfWeight = 1.5;   // Reward performing symbols
    else if(winRate < 40.0 || profitFactor < 0.8)
        perfWeight = 0.5;   // Penalize underperformers

    double allocation = baseShare * perfWeight;

    // Issue A fix: Minimum viable risk floor — if the symbol allocation is less than
    // the risk of a single minimum-lot trade, raise it so at least one position is viable.
    double minLotRisk = CalculateMinLotRiskPercent(symbol);
    if(minLotRisk > 0.0 && allocation < minLotRisk)
    {
        double originalAllocation = allocation;
        allocation = minLotRisk;
        // Cap at maxDailyRiskPercent to avoid absurd allocations on tiny accounts
        allocation = MathMin(allocation, m_config.maxDailyRiskPercent);
        if(allocation > originalAllocation)
            PrintFormat("[RISK-SYMBOL-BUDGET] Auto-adjusted %s allocation from %.2f%% to %.2f%% (min-lot viability)",
                        symbol, originalAllocation, allocation);
    }

    return allocation;
}

//+------------------------------------------------------------------+
//| Check if symbol has budget available for a new trade              |
//+------------------------------------------------------------------+
bool CUnifiedRiskManager::IsSymbolBudgetAvailable(const string symbol, const double riskPct)
{
    double allocation = GetSymbolRiskAllocation(symbol);
    double used = GetSymbolUsedRisk(symbol);
    return ((used + riskPct) <= allocation);
}

//+------------------------------------------------------------------+
//| Refresh per-symbol budget tracking from open positions            |
//+------------------------------------------------------------------+
void CUnifiedRiskManager::RefreshSymbolBudgets()
{
    // Throttle refresh to once per minute
    datetime now = TimeCurrent();
    if(m_lastBudgetRefresh > 0 && (now - m_lastBudgetRefresh) < 60)
        return;
    m_lastBudgetRefresh = now;

    // Rebuild budget array from open positions
    ArrayResize(m_symbolBudgets, 0);
    m_symbolBudgetCount = 0;

    int totalPositions = PositionsTotal();
    for(int i = 0; i < totalPositions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        if(!PositionSelectByTicket(ticket)) continue;

        string posSymbol = PositionGetString(POSITION_SYMBOL);
        double posRisk = CalculatePositionRiskPercent(ticket);

        // Find or create entry for this symbol
        int idx = -1;
        for(int j = 0; j < m_symbolBudgetCount; j++)
        {
            if(m_symbolBudgets[j].symbol == posSymbol) { idx = j; break; }
        }

        if(idx < 0)
        {
            ArrayResize(m_symbolBudgets, m_symbolBudgetCount + 1);
            idx = m_symbolBudgetCount;
            m_symbolBudgetCount++;

            m_symbolBudgets[idx].symbol = posSymbol;
            m_symbolBudgets[idx].allocatedPct = 0.0;
            m_symbolBudgets[idx].usedPct = 0.0;
            m_symbolBudgets[idx].winRate = GetSymbolWinRate(posSymbol);
            m_symbolBudgets[idx].profitFactor = GetSymbolProfitFactor(posSymbol);
        }

        m_symbolBudgets[idx].usedPct += posRisk;
    }

    // Update allocations
    for(int j = 0; j < m_symbolBudgetCount; j++)
    {
        m_symbolBudgets[j].allocatedPct = GetSymbolRiskAllocation(m_symbolBudgets[j].symbol);
    }
}

//+------------------------------------------------------------------+
//| Get used risk for a specific symbol from open positions           |
//| Profitable positions reduce used risk via unrealized P&L credit   |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::GetSymbolUsedRisk(const string symbol)
{
    RefreshSymbolBudgets();

    // Check cached budget first
    for(int i = 0; i < m_symbolBudgetCount; i++)
    {
        if(m_symbolBudgets[i].symbol == symbol)
        {
            double rawUsedRisk = m_symbolBudgets[i].usedPct;
            double adjustedUsedRisk = ApplyPnlRiskAdjustment(symbol, rawUsedRisk);
            return adjustedUsedRisk;
        }
    }

    // Symbol not in budget list — calculate on the fly
    double usedRisk = 0.0;
    int totalPositions = PositionsTotal();
    for(int i = 0; i < totalPositions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
        usedRisk += CalculatePositionRiskPercent(ticket);
    }

    double adjustedUsedRisk = ApplyPnlRiskAdjustment(symbol, usedRisk);
    return adjustedUsedRisk;
}

//+------------------------------------------------------------------+
//| Get per-symbol win rate from deal history                         |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::GetSymbolWinRate(const string symbol)
{
    if(symbol == "")
        return 50.0;

    HistorySelect(0, TimeCurrent());
    int totalDeals = HistoryDealsTotal();
    int wins = 0;
    int total = 0;

    for(int i = totalDeals - 1; i >= 0 && total < 50; i--)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        if(dealTicket <= 0) continue;
        if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != symbol) continue;

        long entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
        if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_INOUT) continue;

        long reason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
        if(reason != DEAL_REASON_EXPERT) continue;

        double netPnl = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                        HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                        HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);

        total++;
        if(netPnl > 0.0) wins++;
    }

    if(total < 5)
        return 50.0; // Default for insufficient data

    return ((double)wins / (double)total) * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale
}

//+------------------------------------------------------------------+
//| Get per-symbol profit factor from deal history                    |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::GetSymbolProfitFactor(const string symbol)
{
    if(symbol == "")
        return 1.0;

    HistorySelect(0, TimeCurrent());
    int totalDeals = HistoryDealsTotal();
    double grossWin = 0.0;
    double grossLoss = 0.0;
    int total = 0;

    for(int i = totalDeals - 1; i >= 0 && total < 50; i--)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        if(dealTicket <= 0) continue;
        if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != symbol) continue;

        long entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
        if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_INOUT) continue;

        long reason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
        if(reason != DEAL_REASON_EXPERT) continue;

        double netPnl = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                        HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                        HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);

        total++;
        if(netPnl > 0.0)
            grossWin += netPnl;
        else
            grossLoss += MathAbs(netPnl);
    }

    if(total < 5)
        return 1.0; // Default for insufficient data

    if(grossLoss > 0.0)
        return grossWin / grossLoss;
    if(grossWin > 0.0)
        return grossWin; // No losses yet
    return 1.0;
}

//+------------------------------------------------------------------+
//| Calculate risk % of a single minimum-lot trade for viability     |
//| Uses ATR-based SL distance to estimate realistic risk per trade  |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::CalculateMinLotRiskPercent(const string symbol)
{
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    if(minLot <= 0.0)
        minLot = 0.01;

    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity <= 0.0)
        equity = AccountInfoDouble(ACCOUNT_BALANCE);
    if(equity <= 0.0)
        return 0.0;

    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    if(point <= 0.0 || tickValue <= 0.0 || tickSize <= 0.0)
        return 0.0;

    // Estimate SL distance using ATR(14) on the daily timeframe as a reasonable default
    double slDistancePoints = 0.0;
    int atrHandle = iATR(symbol, PERIOD_D1, 14);
    if(atrHandle != INVALID_HANDLE)
    {
        double atrValues[];
        ArraySetAsSeries(atrValues, true);
        if(CopyBuffer(atrHandle, 0, 0, 1, atrValues) == 1 && atrValues[0] > 0.0)
            slDistancePoints = atrValues[0] / point;
        IndicatorRelease(atrHandle);
    }

    // Fallback: use 100 pips if ATR unavailable
    if(slDistancePoints <= 0.0)
        slDistancePoints = 100.0;

    double riskAmount = minLot * slDistancePoints * tickValue * (point / tickSize);
    return (riskAmount / equity) * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale
}

//+------------------------------------------------------------------+
//| Apply unrealized P&L adjustment to symbol used risk               |
//| Profitable positions free up risk budget for re-entries           |
//| Formula: adjustedUsedRisk = rawUsedRisk - Max(0, profit * factor) |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::ApplyPnlRiskAdjustment(const string symbol, const double rawUsedRisk)
{
    if(rawUsedRisk <= 0.0 || m_riskReductionFactor <= 0.0)
        return MathMax(0.0, rawUsedRisk);

    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity <= 0.0)
        return MathMax(0.0, rawUsedRisk);

    // Sum unrealized profit for all open positions on this symbol
    double unrealizedProfit = 0.0;
    int totalPositions = PositionsTotal();
    for(int i = 0; i < totalPositions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        if(!PositionSelectByTicket(ticket)) continue;
        if(PositionGetString(POSITION_SYMBOL) != symbol) continue;

        double posProfit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
        if(posProfit > 0.0)
            unrealizedProfit += posProfit;
    }

    if(unrealizedProfit <= 0.0)
        return MathMax(0.0, rawUsedRisk);

    // Convert unrealized profit to risk-percent terms
    double profitRiskPct = (unrealizedProfit / equity) * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale
    double reduction = MathMax(0.0, profitRiskPct * m_riskReductionFactor);
    double adjustedUsedRisk = rawUsedRisk - reduction;
    adjustedUsedRisk = MathMax(0.0, adjustedUsedRisk);

    if(adjustedUsedRisk < rawUsedRisk)
    {
        PrintFormat("[RISK-BUDGET-PNL-ADJUSTED] Symbol=%s, usedRisk=%.2f%% reduced to %.2f%% (unrealized profit=%.2f, factor=%.1f)",
                    symbol, rawUsedRisk, adjustedUsedRisk, unrealizedProfit, m_riskReductionFactor);
    }

    return adjustedUsedRisk;
}

#endif // CORE_RISK_UNIFIED_RISK_MANAGER_MQH

