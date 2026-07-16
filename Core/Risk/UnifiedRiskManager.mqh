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
//| Trade Request Validation Structure                             |
//+------------------------------------------------------------------+
struct STradeValidationRequest
{
    string symbol;                    // Trading symbol
    ENUM_ORDER_TYPE orderType;        // Order type (BUY/SELL)
    double lotSize;                   // Requested lot size
    double stopLossPips;              // Stop loss in pips
    double takeProfitPips;            // Take profit in pips
    double confidence;                // Signal confidence (0-1)
    string strategy;                  // Source strategy name
    string reasoning;                 // Trade reasoning
    string strategyRole;              // Strategy governance role tag
    string strategyCluster;           // Strategy cluster tag
    string clusterCode;               // Compact cluster code (T/R/S/N)
    string contributorContext;        // Contributor summary
    datetime requestTime;             // Request timestamp
};

//+------------------------------------------------------------------+
//| Unified risk manager                                             |
//+------------------------------------------------------------------+
class CUnifiedRiskManager
{
private:
    SUnifiedRiskConfig m_config;
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
    int m_cbRecoveryLevel;           // Graduated recovery level: 0=halted, 1=partial(75%), 2=full(50%)

    // Per-Symbol Risk Budgeting (Phase 5)
    SSymbolRiskBudget m_symbolBudgets[];
    int m_symbolBudgetCount;
    datetime m_lastBudgetRefresh;

    // Profit-adjusted risk budget: fraction of unrealized profit that frees up risk budget
    double m_riskReductionFactor;

    // Per-symbol risk overrides (family-specific risk parameters)
    SSymbolRiskOverride m_riskOverrides[];
    int m_riskOverrideCount;

    // Issue 17: Last computed throttle pressure (1.0 = no pressure, 0.0 = max pressure)
    double m_lastThrottlePressure;

    long m_eaMagicNumber;  // Batch 119: EA magic number for position filtering

    // Emergency close flag for circuit breaker 2nd+ breach
    bool m_emergencyCloseRequested;

    // Validation gate state (moved from CRiskValidationGate to consolidate risk authority)
    bool m_clusterGovernanceEnabled;
    bool m_clusterMutexEnabled;
    int m_maxConcurrentPerCluster;
    double m_maxClusterRiskPercent;
    double m_maxFreeMarginUsage;
    double m_minMarginLevel;
    int m_opposingConflictCooldownSec;
    datetime m_lastOpposingConflictTime;
    string m_lastOpposingConflictSymbol;
    string m_clusterRiskCapCodes[];
    double m_clusterRiskCapValues[];
    string m_clusterSyncCodes[];
    int m_clusterSyncCounts[];
    bool m_auditLogging;
    string m_auditLogFile;
    int m_validationCount;
    int m_approvedCount;
    int m_rejectedCount;
    datetime m_lastValidation;
    double m_avgValidationTime;

    // Additional validation parameters (formerly in CRiskValidationGate)
    double m_emergencyRiskOverride;   // Blueprint 10.4: 0-100 scale (5.0 = 5%)

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

    // Sync inherited cluster position counts on EA restart
    void SyncClusterPositionCounts();
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
    // Issue 17: Expose current throttle pressure for position-limit adjustment
    double GetThrottlePressure() const;
    bool HasUnprotectedPositions();
    int GetUnprotectedPositionCount();
    bool IsInitialized() const { return m_initialized; }

    // Access portfolio risk manager (for wiring correlation engine to PositionSizer)
    CPortfolioRiskManager* GetPortfolioRiskManager() { return &m_portfolioRiskManager; }

    // Set broker trading day start hour (0=midnight server time, 17=5pm for forex rollover)
    void SetTradingDayStartHour(int hour) { m_tradingDayStartHour = MathMax(0, MathMin(23, hour)); }
    
    // EAMagicNumber is stored for validation gate use
    void SetEAMagicNumber(long magic) { m_eaMagicNumber = magic; }
    
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

// Inline validation methods (formerly in CRiskValidationGate)
    bool ValidateBasicParameters(const STradeValidationRequest &request, string &message);
    bool ValidateRiskLimits(const STradeValidationRequest &request, string &message, double &riskPercent);
    bool ValidatePortfolioRisk(const STradeValidationRequest &request, const double tradeRiskPercent, string &message);
    bool ValidateCorrelationLimits(const STradeValidationRequest &request, string &message, double &correlationRisk);
    bool ValidateMarginRequirements(const STradeValidationRequest &request, string &message);
    bool ValidateAccountHealth(const STradeValidationRequest &request, string &message);
    bool ValidateClusterGovernance(const STradeValidationRequest &request, const double tradeRiskPercent, string &message);
    double CalculateTradeRisk(const string symbolParam, const double lotSize, const double stopLossPips) const;
    double CalculateCorrelationRisk(const string symbolParam);
    double CalculatePortfolioRiskAfterTrade(const double additionalRisk);
    double GetPortfolioRiskValue();
    bool PortfolioAllowsTrade(const string symbolParam, const double lotSize);
    bool PortfolioCorrelationAllowed(const string symbolParam);
    bool PortfolioEmergencyActive();
    bool PortfolioHasUnprotectedPositions();
    bool IsSymbolDataValid(const string symbolParam);
    double GetSymbolTickValue(const string symbolParam);
    double GetSymbolPoint(const string symbolParam);
    bool CheckAccountTradingPermissions(void);
    double CalculateSymbolCorrelation(const string symbol1Param, const string symbol2Param);
    double GetMaxCorrelationWithPortfolio(const string symbolParam);
    string NormalizeClusterCode(const string clusterCode) const;
    bool ParseClusterCodeFromComment(const string comment, string &clusterCode) const;
    double EstimatePositionRiskPercent(const ulong ticket) const;
    void LogValidationResult(const STradeValidationRequest &request, const SValidationResult &result);
    void WriteAuditLog(const string message);
    string FormatValidationMessage(const STradeValidationRequest &request, const SValidationResult &result);
    void UpdatePerformanceMetrics(const ulong startTime);
    double GetCurrentPortfolioRisk();
    void SetClusterRiskCap(const string clusterCode, const double capPercent);
    void ClearOpposingConflictCache(const string symbol);
    void GetValidationStats(int &total, int &approved, int &rejected, double &approvalRate);
    void ResetStats(void);

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
    m_config.maxRiskPerTradePercent  = MathMin(tierRiskPerTradePct * 2.0, 50.0);
    m_config.maxDailyRiskPercent     = effectiveDaily;
    m_config.maxPortfolioRiskPercent = effectivePortfolio;
    m_config.drawdownWarningPercent  = effectiveDdWarning;
    m_config.drawdownCriticalPercent = effectiveDdCritical;
    m_config.dailyLossLimitPercent   = effectiveDailyLossLimit;
    m_config.maxPositionsSameBase    = tierMaxPositions;

    // Update active risk per trade
    m_activeRiskPerTradePercent = ClampRiskPercent(m_config.baseRiskPerTradePercent);

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
    m_cbRecoveryLevel(0),
    m_symbolBudgetCount(0),
    m_lastBudgetRefresh(0),
    m_riskReductionFactor(0.5),
    m_riskOverrideCount(0),
    m_lastThrottlePressure(1.0),
    m_eaMagicNumber(0),
    m_emergencyCloseRequested(false),
    // Validation gate state (moved from CRiskValidationGate)
    m_clusterGovernanceEnabled(true),
    m_clusterMutexEnabled(true),
    m_maxConcurrentPerCluster(5),
    m_maxClusterRiskPercent(5.0),
    m_maxFreeMarginUsage(0.8),
    m_minMarginLevel(200.0),
    m_opposingConflictCooldownSec(120),
    m_lastOpposingConflictTime(0),
    m_lastOpposingConflictSymbol(""),
    m_auditLogging(true),
    m_auditLogFile("UnifiedRiskValidation.log"),
    m_validationCount(0),
    m_approvedCount(0),
    m_rejectedCount(0),
    m_lastValidation(0),
    m_avgValidationTime(0.0),
    m_emergencyRiskOverride(5.0)
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

    // Per-cluster risk caps (Fix #11): default overrides
    ArrayResize(m_clusterRiskCapCodes, 2);
    ArrayResize(m_clusterRiskCapValues, 2);
    m_clusterRiskCapCodes[0] = "T";
    m_clusterRiskCapValues[0] = 10.0;  // Trend cluster gets 10% cap
    m_clusterRiskCapCodes[1] = "R";
    m_clusterRiskCapValues[1] = 5.0;   // Reversion cluster stays at default 5%
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CUnifiedRiskManager::~CUnifiedRiskManager()
{
    // Intentionally empty - no dynamic resources to release
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
    // FIX: Hard cap at 50% per trade (PositionSizer::MAX_RISK_PER_TRADE = 10.0, but allow override)
    if(m_config.maxRiskPerTradePercent > 50.0)
        m_config.maxRiskPerTradePercent = 50.0;
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

    m_eaMagicNumber = 0;
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
    m_cbRecoveryLevel = 0;

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

    // Update peak equity and drawdown from peak - ensures m_maxDrawdownFromPeak is always current
    double equityNow = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equityNow > m_peakEquity)
    {
        m_peakEquity = equityNow;
        m_maxDrawdownFromPeak = 0.0;
    }
    else if(m_peakEquity > 0 && equityNow > 0)
    {
        m_maxDrawdownFromPeak = ((m_peakEquity - equityNow) / m_peakEquity) * 100.0;
    }
    
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
        PrintFormat("[RISK-GATE-REJECT] %s | reason=daily_loss_limit | limit=%.1f%% | phase=%s",
                    request.symbol, m_config.dailyLossLimitPercent, phaseTag);
        return result;
    }

    // ENHANCEMENT: Drawdown Circuit Breaker Check (Batch 93 - Week 1)
    if(!CheckDrawdownCircuitBreaker())
    {
        result.message = "Trading paused: Drawdown circuit breaker activated";
        result.severity = ERROR_LEVEL_CRITICAL;
        PrintFormat("[RISK-GATE-REJECT] %s | reason=drawdown_circuit_breaker | dd=%.2f%% | phase=%s",
                    request.symbol, m_maxDrawdownFromPeak, phaseTag);
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
        PrintFormat("[RISK-GATE-REJECT] %s | reason=family_drawdown_limit | dd=%.2f%% | family_limit=%.1f%% | phase=%s",
                    request.symbol, m_maxDrawdownFromPeak, familyMaxDD, phaseTag);
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
        PrintFormat("[RISK-GATE-REJECT] %s | reason=daily_budget_exhausted | effective=%.2f%% | limit=%.2f%% | phase=%s",
                    request.symbol, effectiveDailyRisk, m_config.maxDailyRiskPercent, phaseTag);
        return result;
    }

    if(m_virtualPositionBook.HasOpposingReservation(request.symbol, request.clusterCode, request.orderType))
    {
        result.message = StringFormat("Virtual reservation conflict on %s (opposing candidate already reserved)",
                                      request.symbol);
        result.severity = ERROR_LEVEL_WARNING;
        PrintFormat("[RISK-GATE-REJECT] %s | reason=virtual_reservation_conflict | phase=%s",
                    request.symbol, phaseTag);
        return result;
    }

    // Inline validation from CRiskValidationGate::ValidateTradeRequest
    // 1. Validate basic parameters
    string validationMessage = "";
    if(!ValidateBasicParameters(request, validationMessage))
    {
        result.message = "Basic validation failed: " + validationMessage;
        result.severity = ERROR_LEVEL_ERROR;
        LogValidationResult(request, result);
        return result;
    }
    
    // 2. Validate risk limits
    double tradeRisk = 0.0;
    if(!ValidateRiskLimits(request, validationMessage, tradeRisk))
    {
        result.message = "Risk limit validation failed: " + validationMessage;
        result.riskPercent = tradeRisk;
        result.severity = ERROR_LEVEL_ERROR;
        LogValidationResult(request, result);
        return result;
    }
    result.riskPercent = tradeRisk;
    
    // 3. Validate portfolio risk
    if(!ValidatePortfolioRisk(request, tradeRisk, validationMessage))
    {
        result.message = "Portfolio risk validation failed: " + validationMessage;
        result.severity = ERROR_LEVEL_ERROR;
        LogValidationResult(request, result);
        return result;
    }

    // 4. Validate cluster governance (strategy cluster mutex + cap)
    if(!ValidateClusterGovernance(request, tradeRisk, validationMessage))
    {
        result.message = "Cluster governance validation failed: " + validationMessage;
        result.severity = ERROR_LEVEL_WARNING;
        LogValidationResult(request, result);
        return result;
    }
    
    // 5. Validate correlation limits
    double correlationRisk = 0.0;
    if(!ValidateCorrelationLimits(request, validationMessage, correlationRisk))
    {
        result.message = "Correlation validation failed: " + validationMessage;
        result.correlationRisk = correlationRisk;
        result.severity = ERROR_LEVEL_WARNING;
        LogValidationResult(request, result);
        return result;
    }
    result.correlationRisk = correlationRisk;
    
    // 6. Validate margin requirements
    if(!ValidateMarginRequirements(request, validationMessage))
    {
        result.message = "Margin validation failed: " + validationMessage;
        result.severity = ERROR_LEVEL_ERROR;
        LogValidationResult(request, result);
        return result;
    }
    
    // 7. Validate account health
    if(!ValidateAccountHealth(request, validationMessage))
    {
        result.message = "Account health validation failed: " + validationMessage;
        result.severity = ERROR_LEVEL_CRITICAL;
        LogValidationResult(request, result);
        return result;
    }
    
    // All validations passed
    result.approved = true;
    result.message = "Trade request approved";
    result.portfolioRisk = CalculatePortfolioRiskAfterTrade(tradeRisk);
    result.severity = ERROR_LEVEL_INFO;
    m_approvedCount++;
    
    LogValidationResult(request, result);
    UpdatePerformanceMetrics(GetMicrosecondCount());

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
            PrintFormat("[RISK-GATE-REJECT] %s | reason=lot_floor_risk_cap | lot=%.3f | min_lot=%.3f | risk_ratio=%.1f | cap=%.1f | phase=%s",
                        request.symbol, result.adjustedLotSize, brokerMinLot, riskRatio, m_config.minLotRiskMultiplier, phaseTag);
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
            PrintFormat("[RISK-GATE-REJECT] %s | reason=symbol_budget_exhausted | used=%.2f%% + new=%.2f%% > alloc=%.2f%% | phase=%s",
                        request.symbol, used, result.riskPercent, allocation, phaseTag);
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
            PrintFormat("[RISK-GATE-REJECT] %s | reason=portfolio_risk_exceeded | open=%.2f%% + reserved=%.2f%% + new=%.2f%% > limit=%.2f%% | phase=%s",
                        request.symbol, openExposureRisk, reservedRisk, result.riskPercent, m_config.maxPortfolioRiskPercent, phaseTag);
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
            PrintFormat("[RISK-GATE-REJECT] %s | reason=family_position_limit | family_positions=%d/%d | phase=%s",
                        reqSymbol, familyPositionCount, maxFamilyPositions, phaseTag);
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
            PrintFormat("[RISK-GATE-REJECT] %s | reason=correlation_block | corr=%.2f >= threshold=%.2f | phase=%s",
                        request.symbol, maxCorrelation, m_config.correlationBlockThreshold, phaseTag);
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

    // Batch 116: Recompute risk percent after correlation reduction to avoid stale over-rejection
    if(result.requiresAdjustment && result.adjustedLotSize > 0.0 && result.adjustedLotSize != request.lotSize)
    {
        double point = SymbolInfoDouble(request.symbol, SYMBOL_POINT);
        double tickValue = SymbolInfoDouble(request.symbol, SYMBOL_TRADE_TICK_VALUE);
        double tickSize = SymbolInfoDouble(request.symbol, SYMBOL_TRADE_TICK_SIZE);
        if(point > 0.0 && tickValue > 0.0 && tickSize > 0.0 && request.stopLossPips > 0.0)
        {
            double slDistancePrice = request.stopLossPips * point * 10.0;
            double slTicks = slDistancePrice / tickSize;
            double riskAmount = result.adjustedLotSize * slTicks * tickValue;
            double equity = MathMin(AccountInfoDouble(ACCOUNT_BALANCE), AccountInfoDouble(ACCOUNT_EQUITY));
            if(equity > 0.0)
                result.riskPercent = (riskAmount / equity) * 100.0;
        }
    }

    double projectedDailyRisk = GetEffectiveDailyRiskUsedPercent(reservedRisk + MathMax(0.0, result.riskPercent));
    if(projectedDailyRisk > m_config.maxDailyRiskPercent)
    {
        result.approved = false;
        result.severity = ERROR_LEVEL_WARNING;
        result.message = StringFormat("Daily risk limit would be exceeded (%s): %.2f%% + %.2f%% > %.2f%%",
                                      phaseTag, effectiveDailyRisk, result.riskPercent, m_config.maxDailyRiskPercent);
        PrintFormat("[RISK-GATE-REJECT] %s | reason=daily_risk_would_exceed | effective=%.2f%% + new=%.2f%% > limit=%.2f%% | phase=%s",
                    request.symbol, effectiveDailyRisk, result.riskPercent, m_config.maxDailyRiskPercent, phaseTag);
    }

    return result;
}

void CUnifiedRiskManager::ConfigureClusterGovernance(const bool enabled,
                                                     const int maxConcurrentPerCluster,
                                                     const double maxClusterRiskPercent,
                                                     const bool enableMutex)
{
    m_clusterGovernanceEnabled = enabled;
    m_clusterMutexEnabled = enableMutex;
    m_maxConcurrentPerCluster = MathMax(1, maxConcurrentPerCluster);
    m_maxClusterRiskPercent = MathMax(0.1, maxClusterRiskPercent);

    PrintFormat("[RISK-CLUSTER-CAP] Cluster position cap applied | max_positions=%d | max_risk=%.2f%%",
                m_maxConcurrentPerCluster, m_maxClusterRiskPercent);

    PrintFormat("[RISK-CLUSTER] governance=%s | mutex=%s | max_positions=%d | max_risk=%.2f%%",
                m_clusterGovernanceEnabled ? "enabled" : "disabled",
                m_clusterMutexEnabled ? "enabled" : "disabled",
                m_maxConcurrentPerCluster,
                m_maxClusterRiskPercent);
}

void CUnifiedRiskManager::SyncClusterPositionCounts()
{
    // Batch 120: Diagnostic method — populates sync arrays for logging
    // ValidateClusterGovernance counts positions directly from terminal,
    // so these arrays are for diagnostic output only, not gating logic
    // Clear previous sync data
    ArrayResize(m_clusterSyncCodes, 0);
    ArrayResize(m_clusterSyncCounts, 0);

    int totalPositions = PositionsTotal();
    for(int i = 0; i < totalPositions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

        string posComment = PositionGetString(POSITION_COMMENT);
        string clusterCode = "N";
        ParseClusterCodeFromComment(posComment, clusterCode);
        clusterCode = NormalizeClusterCode(clusterCode);

        if(clusterCode == "N")
            continue;

        // Find or add cluster in sync arrays
        bool found = false;
        for(int c = 0; c < ArraySize(m_clusterSyncCodes); c++)
        {
            if(m_clusterSyncCodes[c] == clusterCode)
            {
                m_clusterSyncCounts[c]++;
                found = true;
                break;
            }
        }
        if(!found)
        {
            int newSize = ArraySize(m_clusterSyncCodes) + 1;
            ArrayResize(m_clusterSyncCodes, newSize);
            ArrayResize(m_clusterSyncCounts, newSize);
            m_clusterSyncCodes[newSize - 1] = clusterCode;
            m_clusterSyncCounts[newSize - 1] = 1;
        }
    }

    // Log reconciled state
    PrintFormat("[RISK-CLUSTER-SYNC] Reconciled %d clusters from %d live positions:",
                ArraySize(m_clusterSyncCodes), totalPositions);
    for(int c = 0; c < ArraySize(m_clusterSyncCodes); c++)
    {
        PrintFormat("[RISK-CLUSTER-SYNC]   cluster=%s | inherited_positions=%d | max=%d",
                    m_clusterSyncCodes[c], m_clusterSyncCounts[c], m_maxConcurrentPerCluster);
        if(m_clusterSyncCounts[c] > m_maxConcurrentPerCluster)
        {
            PrintFormat("[RISK-CLUSTER-SYNC]   WARNING: cluster=%s has %d inherited positions exceeding cap %d — blocking new entries until positions close",
                        m_clusterSyncCodes[c], m_clusterSyncCounts[c], m_maxConcurrentPerCluster);
        }
    }
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

    // Issue 17: Store throttle pressure for position-limit adjustment
    m_lastThrottlePressure = pressureMultiplier;

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
//| Issue 17: Expose last throttle pressure                          |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::GetThrottlePressure() const
{
    return m_lastThrottlePressure;
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

    // Inline stats (formerly from m_validationGate)
    int total = m_validationCount;
    int approved = m_approvedCount;
    int rejected = m_rejectedCount;
    double approvalRate = 0.0;
    if(total > 0)
        approvalRate = (double)approved / total * 100.0;
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
    // Issue 2 fix: Cap at the daily risk limit to prevent overflow race condition.
    // Without this cap, MTM P&L + entry exposure can exceed limit by 2x before blocking.
    if(effective > m_config.maxDailyRiskPercent)
    {
        PrintFormat("[RISK-DAILY-CAP] effective=%.2f%% capped to limit=%.2f%% | entry_used=%.2f%% | mtm=%.2f%% | open_exp=%.2f%%",
                    effective, m_config.maxDailyRiskPercent,
                    m_dailyRiskUsedPercent, CalculateDailyMarkToMarketLossPercent(),
                    GetCurrentOpenExposureRiskPercent());
        effective = m_config.maxDailyRiskPercent;
    }
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
            m_cbRecoveryLevel = 0; // Reset graduated recovery level on new halt

            PrintFormat("[RISK-CIRCUIT-BREAKER] CRITICAL BREACH | Drawdown=%.2f%% >= Limit=%.2f%% | Trading HALTED",
                       m_maxDrawdownFromPeak, m_config.drawdownCriticalPercent);
            PrintFormat("[RISK-CIRCUIT-BREAKER] Peak Equity=%.2f | Current Equity=%.2f | Loss=%.2f",
                       m_peakEquity, equityNow, m_peakEquity - equityNow);
            PrintFormat("[RISK-CIRCUIT-BREAKER] Breach count: %d | Auto-recovery will be attempted after %d min cooldown (max %d attempts)",
                       m_drawdownBreachCount, m_cbRecoveryCooldownMin, m_cbMaxRecoveryAttempts);
            
            // P1: On 2nd or subsequent breach, close all positions to stop bleeding
            if(m_drawdownBreachCount >= 2)
            {
                PrintFormat("[RISK-CIRCUIT-BREAKER] SECOND+ BREACH - EMERGENCY CLOSING ALL POSITIONS!");
                m_emergencyCloseRequested = true;
            }
            
            // P1: Emergency exit trigger - if drawdown exceeds 2x critical threshold, close everything
            double emergencyThreshold = m_config.drawdownCriticalPercent * 2.0;
            if(m_maxDrawdownFromPeak >= emergencyThreshold)
            {
                PrintFormat("[RISK-EMERGENCY-EXIT] Drawdown %.2f%% exceeds 2x critical %.2f%% - EMERGENCY CLOSING ALL POSITIONS!",
                           m_maxDrawdownFromPeak, m_config.drawdownCriticalPercent);
                m_emergencyCloseRequested = true;
                m_tradingEnabled = false;
            }
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
    m_cbRecoveryLevel = 0;
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
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    
    // Issue 4 fix: Validate position exists with non-zero volume and SL
    // Closed or closing positions may still pass PositionSelectByTicket but return
    // zero volume or zero SL — skip them to prevent phantom risk
    if(volume <= 0.0 || sl == 0.0 || openPrice == 0.0)
        return 0.0;
    
    string symbol = PositionGetString(POSITION_SYMBOL);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    
    if(point <= 0.0 || tickValue <= 0.0)
        return 0.0;
    
    // Issue 16 fix: Use mark-to-market SL distance (current price to SL) instead of
    // entry price to SL. This ensures the risk budget reflects actual current exposure,
    // not the historical entry-based exposure. If price has moved toward SL, the
    // real risk is lower; if moved away, it's higher.
    double slDistance = MathAbs(currentPrice - sl) / point;
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

    // Graduated recovery: two levels to avoid impossible recovery targets
    // Level 1: DD < haltThreshold * 0.75  → re-enable at ultra-conservative
    // Level 2: DD < haltThreshold * 0.50  → full normal mode
    double currentDD = GetCurrentDrawdownPercent();
    double level1Threshold = m_config.drawdownCriticalPercent * 0.75;
    double level2Threshold = m_config.drawdownCriticalPercent * 0.50;

    // Level 2 check: full recovery — DD below 50% of halt threshold
    if(m_cbRecoveryLevel >= 1 && currentDD < level2Threshold)
    {
        m_cbRecoveryLevel = 2;
        m_cbRecoveryAttempts++;
        m_tradingEnabled = true;
        m_conservativeMode = false;
        m_cbTriggeredAt = 0;
        m_cbLastRecoverySuccessTime = now;

        m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_maxDrawdownFromPeak = 0.0;

        PrintFormat("[RISK-CIRCUIT-BREAKER] AUTO-RECOVERY L2 | Normal mode restored | DD=%.2f%% < threshold=%.2f%% | Attempt %d/%d",
                   currentDD, level2Threshold, m_cbRecoveryAttempts, m_cbMaxRecoveryAttempts);
        return true;
    }

    // Level 1 check: partial recovery — DD below 75% of halt threshold
    if(currentDD < level1Threshold)
    {
        m_cbRecoveryLevel = 1;
        m_cbRecoveryAttempts++;
        m_tradingEnabled = true;
        m_conservativeMode = true;
        m_cbTriggeredAt = 0;
        m_cbLastRecoverySuccessTime = now;

        m_peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_maxDrawdownFromPeak = 0.0;

        PrintFormat("[RISK-CIRCUIT-BREAKER] AUTO-RECOVERY L1 | Trading re-enabled ultra-conservative | DD=%.2f%% < threshold=%.2f%% | Attempt %d/%d",
                   currentDD, level1Threshold, m_cbRecoveryAttempts, m_cbMaxRecoveryAttempts);
        return true;
    }

    // Drawdown has NOT recovered sufficiently — stay disabled
    PrintFormat("[RISK-CIRCUIT-BREAKER] Recovery check | DD=%.2f%% still above L1=%.2f%% L2=%.2f%% | Staying disabled | Attempt %d/%d",
               currentDD, level1Threshold, level2Threshold, m_cbRecoveryAttempts + 1, m_cbMaxRecoveryAttempts);
    m_cbTriggeredAt = now;
    return false;
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

        // Issue 4 fix: Detect phantom risk — position exists but has zero risk
        // contribution (closed/closing position with stale terminal entry)
        if(posRisk <= 0.0)
        {
            double vol = PositionGetDouble(POSITION_VOLUME);
            double slCheck = PositionGetDouble(POSITION_SL);
            if(vol > 0.0 && slCheck > 0.0)
            {
                // Position has volume and SL but zero risk — likely a phantom entry
                // from a recently closed position. Log and skip it.
                static datetime s_lastPhantomLog = 0;
                if(now - s_lastPhantomLog > 30)
                {
                    PrintFormat("[RISK-PHANTOM] Skipped phantom risk entry | ticket=%I64u | symbol=%s | vol=%.2f | SL=%.5f",
                                ticket, posSymbol, vol, slCheck);
                    s_lastPhantomLog = now;
                }
            }
            continue;
        }

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
        double posRisk = CalculatePositionRiskPercent(ticket);
        if(posRisk > 0.0)
            usedRisk += posRisk;
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
    // Batch 116: use static cached handle to avoid repeated create/destroy overhead
    double slDistancePoints = 0.0;
    static int s_atrHandle = INVALID_HANDLE;
    static string s_atrSymbol = "";
    if(s_atrHandle == INVALID_HANDLE || s_atrSymbol != symbol)
    {
        if(s_atrHandle != INVALID_HANDLE)
            IndicatorRelease(s_atrHandle);
        s_atrHandle = iATR(symbol, PERIOD_D1, 14);
        s_atrSymbol = symbol;
    }
    if(s_atrHandle != INVALID_HANDLE)
    {
        double atrValues[];
        ArraySetAsSeries(atrValues, true);
        if(CopyBuffer(s_atrHandle, 0, 0, 1, atrValues) == 1 && atrValues[0] > 0.0)
            slDistancePoints = atrValues[0] / point;
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

//+------------------------------------------------------------------+
//| Inline validation methods (formerly in CRiskValidationGate)      |
//+------------------------------------------------------------------+
bool CUnifiedRiskManager::ValidateBasicParameters(const STradeValidationRequest &request, string &message)
{
    // Validate symbol
    if(StringLen(request.symbol) == 0)
    {
        message = "Empty symbol";
        return false;
    }
    
    if(!IsSymbolDataValid(request.symbol))
    {
        message = "Invalid symbol data for " + request.symbol;
        return false;
    }
    
    // Validate lot size
    if(request.lotSize <= 0)
    {
        message = "Invalid lot size: " + DoubleToString(request.lotSize, 3);
        return false;
    }
    
    double minLot = SymbolInfoDouble(request.symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(request.symbol, SYMBOL_VOLUME_MAX);
    
    if(request.lotSize < minLot)
    {
        // On small accounts, the calculated lot may be below broker minimum.
        // If the lot is within the minLotRiskMultiplier tolerance, allow a round-up
        // rather than rejecting outright. The PositionSizer will handle the risk assessment.
        // This prevents the validation gate from being a hard blocker for small accounts
        // or symbols with high minimum lots (e.g., Deriv Volatility 25 Index min=0.50).
        double riskRatio = (request.lotSize > 0.0) ? (minLot / request.lotSize) : 999.0;
        if(riskRatio <= 15.0)  // Allow round-up if within 15x risk tolerance
        {
            // Don't reject — the caller (UnifiedRiskManager) will re-calculate
            // with the min lot and assess whether the risk is acceptable
        }
        else
        {
            message = "Lot size below minimum: " + DoubleToString(request.lotSize, 3) + " < " + DoubleToString(minLot, 3);
            return false;
        }
    }
    
    if(request.lotSize > maxLot)
    {
        PrintFormat("[RISK-GATE] Lot %.4f exceeds broker max %.4f for %s — caller must cap", request.lotSize, maxLot, request.symbol);
    }
    
    // Validate stop loss
    if(request.stopLossPips <= 0)
    {
        PrintFormat("[RISK-GATE] Rejected %s %s: Missing stop loss (strategy=%s, SL=%.1f pips)",
                    request.symbol, EnumToString(request.orderType), request.strategy, request.stopLossPips);
        message = "Invalid stop loss: " + DoubleToString(request.stopLossPips, 1) + " pips";
        return false;
    }
    
    // Validate order type
    if(request.orderType != ORDER_TYPE_BUY && request.orderType != ORDER_TYPE_SELL)
    {
        message = "Invalid order type: " + EnumToString(request.orderType);
        return false;
    }
    
    // Check trading permissions
    if(!CheckAccountTradingPermissions())
    {
        message = "Trading not allowed";
        return false;
    }
    
    return true;
}

bool CUnifiedRiskManager::ValidateRiskLimits(const STradeValidationRequest &request, string &message, double &riskPercent)
{
    // Calculate trade risk
    double tradeRisk = CalculateTradeRisk(request.symbol, request.lotSize, request.stopLossPips);
    
    if(tradeRisk <= 0)
    {
        message = "Unable to calculate trade risk";
        return false;
    }
    
    // Convert to percentage using equity-aware denominator for stress-consistent risk sizing.
    double accountBalanceLocal = AccountInfoDouble(ACCOUNT_BALANCE);
    double accountEquityLocal = AccountInfoDouble(ACCOUNT_EQUITY);
    double riskDenominator = 0.0;
    
    // Handle negative balance/equity scenarios (margin call, etc.)
    if(accountBalanceLocal <= 0.0 && accountEquityLocal <= 0.0)
    {
        message = "Account in critical state - negative balance and equity";
        return false;
    }
    
    if(accountBalanceLocal > 0.0 && accountEquityLocal > 0.0)
        riskDenominator = MathMin(accountBalanceLocal, accountEquityLocal);
    else if(accountBalanceLocal > 0.0)
        riskDenominator = accountBalanceLocal;
    else
        riskDenominator = accountEquityLocal;
    
    if(riskDenominator <= 0.0)
    {
        message = "Invalid account risk denominator";
        return false;
    }
    
    riskPercent = (tradeRisk / riskDenominator) * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale
    
    // Check against maximum risk per trade
    if(riskPercent > m_config.maxRiskPerTradePercent)
    {
        message = StringFormat("Risk %.2f%% exceeds maximum %.2f%%", riskPercent, m_config.maxRiskPerTradePercent);
        return false;
    }
    
    // Check emergency override
    if(m_emergencyRiskOverride > 0.0 && riskPercent > m_emergencyRiskOverride)
    {
        message = StringFormat("Emergency risk override exceeded: %.2f%% > %.2f%%", riskPercent, m_emergencyRiskOverride);
        return false;
    }
    
    return true;
}

bool CUnifiedRiskManager::ValidatePortfolioRisk(const STradeValidationRequest &request, const double tradeRiskPercent, string &message)
{
    CPortfolioRiskManager* manager = &m_portfolioRiskManager;
    
    if(CheckPointer(manager) == POINTER_INVALID)
    {
        message = "Portfolio risk manager not available";
        return false;
    }
    
    if(PortfolioHasUnprotectedPositions())
    {
        message = "Open position without protective stop-loss detected";
        return false;
    }
    
    double currentRisk = GetPortfolioRiskValue();
    double totalRisk = currentRisk + tradeRiskPercent;
    
    if(totalRisk > m_config.maxPortfolioRiskPercent)
    {
        message = StringFormat("Total portfolio risk %.2f%% would exceed maximum %.2f%%", totalRisk, m_config.maxPortfolioRiskPercent);
        return false;
    }
    
    if(!PortfolioAllowsTrade(request.symbol, request.lotSize))
    {
        string portfolioReason = "";  // GetLastBlockReason would need to be added
        message = (portfolioReason != "") ? portfolioReason : "Trade blocked by portfolio risk manager";
        return false;
    }
    
    return true;
}

bool CUnifiedRiskManager::ValidateCorrelationLimits(const STradeValidationRequest &request, string &message, double &correlationRisk)
{
    // Check same base currency limit
    int sameBaseCount = 0;
    // Batch 118: Extract base currency up to first non-alpha character (handles US30, BTCUSD, etc.)
    string symbolBase = "";
    for(int c = 0; c < StringLen(request.symbol); c++)
    {
        ushort ch = StringGetCharacter(request.symbol, c);
        if((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z'))
            symbolBase += ShortToString(ch);
        else
            break;
    }
    if(StringLen(symbolBase) < 3)
        symbolBase = StringSubstr(request.symbol, 0, 3);  // fallback
    
    // Batch 119: Only count EA-owned positions (filter by magic number)
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            string posSymbol = PositionGetString(POSITION_SYMBOL);
            long posMagic = PositionGetInteger(POSITION_MAGIC);
            // Only count positions with magic 0 (manual) or matching EA magic
            if(StringFind(posSymbol, symbolBase) >= 0 &&
               (posMagic == 0 || posMagic == m_eaMagicNumber))
                sameBaseCount++;
        }
    }
    
    if(sameBaseCount >= m_config.maxPositionsSameBase)
    {
        message = StringFormat("Too many positions on base %s (>= %d)", symbolBase, m_config.maxPositionsSameBase);
        correlationRisk = 1.0;
        return false;
    }
    
    correlationRisk = CalculateCorrelationRisk(request.symbol);
    
    if(correlationRisk > m_config.correlationThreshold)
    {
        message = StringFormat("Correlation risk %.2f exceeds threshold %.2f", correlationRisk, m_config.correlationThreshold);
        return false;
    }
    
    if(CheckPointer(&m_portfolioRiskManager) != POINTER_INVALID)
    {
        CPortfolioRiskManager* manager = &m_portfolioRiskManager;
        if(!PortfolioCorrelationAllowed(request.symbol))
        {
            string correlationReason = "";  // GetLastBlockReason would need to be added
            message = (correlationReason != "") ? correlationReason : "Correlation limit exceeded";
            return false;
        }
    }
    
    return true;
}

bool CUnifiedRiskManager::ValidateMarginRequirements(const STradeValidationRequest &request, string &message)
{
    // Calculate margin requirement
    double marginRequired = 0.0;
    double currentPriceLocal = (request.orderType == ORDER_TYPE_BUY) ?
                              SymbolInfoDouble(request.symbol, SYMBOL_ASK) :
                              SymbolInfoDouble(request.symbol, SYMBOL_BID);
    
    if(!OrderCalcMargin(request.orderType, request.symbol, request.lotSize, currentPriceLocal, marginRequired))
    {
        message = "Unable to calculate margin requirement";
        return false;
    }
    
    // Check available margin
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    if(marginRequired > freeMargin * m_maxFreeMarginUsage) // Use configurable max free margin usage
    {
        message = StringFormat("Insufficient margin: required %.2f, available %.2f (threshold: %.0f%%)", 
                             marginRequired, freeMargin, m_maxFreeMarginUsage * 100.0);
        return false;
    }
    
    // Check margin level after trade
    double currentMarginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
    if(currentMarginLevel > 0 && currentMarginLevel < m_minMarginLevel)
    {
        message = StringFormat("Margin level too low: %.2f%% (threshold: %.0f%%)", 
                             currentMarginLevel, m_minMarginLevel);
        return false;
    }
    
    return true;
}

bool CUnifiedRiskManager::ValidateAccountHealth(const STradeValidationRequest &request, string &message)
{
    double accountBalanceLocal2 = AccountInfoDouble(ACCOUNT_BALANCE);
    if(accountBalanceLocal2 < 100.0)  // MIN_ACCOUNT_BALANCE
    {
        message = StringFormat("Account balance too low: %.2f", accountBalanceLocal2);
        return false;
    }
    
    // Delegate drawdown check to CUnifiedRiskManager — single source of truth
    SDrawdownState ddState = GetDrawdownState();
    if(ddState.isCriticalActive)
    {
        message = StringFormat("Drawdown critical: %.2f%% — trading halted by unified risk manager",
                               ddState.currentDrawdownPct);
        return false;
    }
    
    if(PortfolioEmergencyActive())
    {
        message = "Emergency mode active - trading suspended";
        return false;
    }
    
    return true;
}

bool CUnifiedRiskManager::ValidateClusterGovernance(const STradeValidationRequest &request,
                                                    const double tradeRiskPercent,
                                                    string &message)
{
    if(!m_clusterGovernanceEnabled)
        return true;
    
    string requestClusterCode = NormalizeClusterCode(request.clusterCode);
    if(requestClusterCode == "N")
        requestClusterCode = NormalizeClusterCode(request.strategyCluster);
    
    if(requestClusterCode == "N")
        return true;
    
    // Fix #9: Opposing conflict cooldown cache — skip full scan if recently rejected for same symbol
    if(m_clusterMutexEnabled &&
       m_lastOpposingConflictSymbol == request.symbol &&
       m_lastOpposingConflictTime > 0 &&
       (TimeCurrent() - m_lastOpposingConflictTime) < m_opposingConflictCooldownSec)
    {
        message = StringFormat("Opposing conflict cooldown active for %s (%ds remaining)",
                               request.symbol,
                               m_opposingConflictCooldownSec - (int)(TimeCurrent() - m_lastOpposingConflictTime));
        PrintFormat("[RISK-MUTEX-COOLDOWN] symbol=%s | cooldown_remaining=%ds | last_conflict=%s",
                    request.symbol,
                    m_opposingConflictCooldownSec - (int)(TimeCurrent() - m_lastOpposingConflictTime),
                    TimeToString(m_lastOpposingConflictTime, TIME_DATE | TIME_SECONDS));
        return false;
    }
    
    int clusterOpenPositions = 0;
    double clusterOpenRiskPercent = 0.0;
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        
        string existingSymbol = PositionGetString(POSITION_SYMBOL);
        ENUM_POSITION_TYPE existingType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
        string existingComment = PositionGetString(POSITION_COMMENT);
        string existingClusterCode = "N";
        ParseClusterCodeFromComment(existingComment, existingClusterCode);
        existingClusterCode = NormalizeClusterCode(existingClusterCode);
        
        if(existingClusterCode == "N" && existingSymbol == request.symbol)
            existingClusterCode = requestClusterCode;
        
        if(m_clusterMutexEnabled && existingSymbol == request.symbol)
        {
            bool oppositeDirection = ((request.orderType == ORDER_TYPE_BUY && existingType == POSITION_TYPE_SELL) ||
                                      (request.orderType == ORDER_TYPE_SELL && existingType == POSITION_TYPE_BUY));
            if(oppositeDirection &&
               (existingClusterCode == "N" || existingClusterCode != requestClusterCode))
            {
                // Fix #9: Update cooldown cache when a new opposing conflict is detected
                m_lastOpposingConflictTime = TimeCurrent();
                m_lastOpposingConflictSymbol = request.symbol;
                
                message = StringFormat("Opposing same-symbol cluster conflict (request=%s existing=%s ticket=%I64u)",
                                       requestClusterCode, existingClusterCode, ticket);
                PrintFormat("[RISK-MUTEX-BLOCK] symbol=%s | request_cluster=%s | existing_cluster=%s | request_side=%s | existing_side=%s | ticket=%I64u",
                            request.symbol,
                            requestClusterCode,
                            existingClusterCode,
                            EnumToString(request.orderType),
                            EnumToString(existingType),
                            ticket);
                return false;
            }
        }
        
        if(existingClusterCode == requestClusterCode)
        {
            clusterOpenPositions++;
            clusterOpenRiskPercent += EstimatePositionRiskPercent(ticket);
        }
    }
    
    int projectedPositions = clusterOpenPositions + 1;
    double projectedRisk = clusterOpenRiskPercent + MathMax(0.0, tradeRiskPercent);
    
    // Fix #11: Look up per-cluster risk cap first; fall back to global default
    double effectiveClusterRiskCap = m_maxClusterRiskPercent;
    for(int c = 0; c < ArraySize(m_clusterRiskCapCodes); c++)
    {
        if(m_clusterRiskCapCodes[c] == requestClusterCode)
        {
            effectiveClusterRiskCap = m_clusterRiskCapValues[c];
            PrintFormat("[RISK-CLUSTER-CAP-PER] cluster=%s | per_cluster_cap=%.2f%% applied",
                        requestClusterCode, effectiveClusterRiskCap);
            break;
        }
    }
    
    PrintFormat("[RISK-CLUSTER] cluster=%s | open_positions=%d | projected_positions=%d | open_risk=%.2f%% | projected_risk=%.2f%% | caps=%d/%.2f%%",
                requestClusterCode,
                clusterOpenPositions,
                projectedPositions,
                clusterOpenRiskPercent,
                projectedRisk,
                m_maxConcurrentPerCluster,
                effectiveClusterRiskCap);
    
    if(projectedPositions > m_maxConcurrentPerCluster)
    {
        message = StringFormat("Cluster position cap exceeded (%d > %d) for cluster %s",
                               projectedPositions, m_maxConcurrentPerCluster, requestClusterCode);
        return false;
    }
    
    if(projectedRisk > effectiveClusterRiskCap)
    {
        message = StringFormat("Cluster risk cap exceeded (%.2f%% > %.2f%%) for cluster %s",
                               projectedRisk, effectiveClusterRiskCap, requestClusterCode);
        return false;
    }
    
    return true;
}

double CUnifiedRiskManager::CalculateTradeRisk(const string symbolParam, double lotSize, double stopLossPips) const
{
    if(symbolParam == "" || stopLossPips <= 0) {
        return 0.0;
    }
    
    double tickValue = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_SIZE);
    double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
    double contractSize = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_CONTRACT_SIZE);
    
    if(tickValue <= 0 || point <= 0 || tickSize <= 0) {
        return 0.0;
    }
    
    // 🔥 FIX: Calculate risk properly based on symbol type
    // stopLossPips is actually in POINTS (e.g., 50 points)
    // For EURGBP: point = 0.00001, so 50 points = 0.0005 = 5 pips
    // For EURUSD: point = 0.00001, so 50 points = 0.0005 = 5 pips
    
    double stopLossPrice = stopLossPips * point;  // Convert points to price difference
    double riskPerLot = (stopLossPrice / tickSize) * tickValue;  // Risk per 1.0 lot
    double totalRisk = lotSize * riskPerLot;
    
    // Debug logging for problem symbols
    static datetime g_lastRiskCalcLog = 0;
    if((symbolParam == "EURGBP.0" || symbolParam == "XPTUSD.0") && 
       TimeCurrent() - g_lastRiskCalcLog > 120)
    {
        PrintFormat("[RISK-CALC-DEBUG] %s: Lot=%.2f, SL_pts=%.0f, Point=%.5f, TickVal=%.2f, TickSz=%.5f, Risk=$%.2f",
                   symbolParam, lotSize, stopLossPips, point, tickValue, tickSize, totalRisk);
        g_lastRiskCalcLog = TimeCurrent();
    }
    
    return totalRisk;
}

double CUnifiedRiskManager::CalculateCorrelationRisk(const string symbolParam)
{
    double maxCorrelation = 0.0;
    
    // Check correlation with all open positions
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            string existingSymbol = PositionGetString(POSITION_SYMBOL);
            if(existingSymbol != symbolParam)
            {
                double correlation = CalculateSymbolCorrelation(symbolParam, existingSymbol);
                maxCorrelation = MathMax(maxCorrelation, MathAbs(correlation));
            }
        }
    }
    
    return maxCorrelation;
}

double CUnifiedRiskManager::CalculatePortfolioRiskAfterTrade(const double additionalRisk)
{
    return GetPortfolioRiskValue() + additionalRisk;
}

void CUnifiedRiskManager::LogValidationResult(const STradeValidationRequest &request, const SValidationResult &result)
{
    if(!m_auditLogging)
        return;
    
    string logMessage = FormatValidationMessage(request, result);
    WriteAuditLog(logMessage);
    
    // Also log to error handler
    CEnhancedErrorHandler::LogError(ERROR_INFO, "UnifiedRiskManager", result.message, 0);
}

double CUnifiedRiskManager::GetPortfolioRiskValue()
{
    return m_portfolioRiskManager.GetPortfolioRisk();
}

bool CUnifiedRiskManager::PortfolioAllowsTrade(const string symbolParam, const double lotSize)
{
    return m_portfolioRiskManager.IsTradeAllowed(symbolParam, lotSize);
}

bool CUnifiedRiskManager::PortfolioCorrelationAllowed(const string symbolParam)
{
    return m_portfolioRiskManager.CheckCorrelationLimits(symbolParam);
}

bool CUnifiedRiskManager::PortfolioEmergencyActive()
{
    return m_portfolioRiskManager.IsEmergencyMode();
}

bool CUnifiedRiskManager::PortfolioHasUnprotectedPositions()
{
    return m_portfolioRiskManager.HasUnprotectedPositions();
}

bool CUnifiedRiskManager::IsSymbolDataValid(const string symbolParam)
{
    if(!SymbolSelect(symbolParam, true))
        return false;
    
    double bid = SymbolInfoDouble(symbolParam, SYMBOL_BID);
    double ask = SymbolInfoDouble(symbolParam, SYMBOL_ASK);
    
    return (bid > 0 && ask > 0);
}

double CUnifiedRiskManager::GetSymbolTickValue(const string symbolParam)
{
    return SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_VALUE);
}

double CUnifiedRiskManager::GetSymbolPoint(const string symbolParam)
{
    return SymbolInfoDouble(symbolParam, SYMBOL_POINT);
}

bool CUnifiedRiskManager::CheckAccountTradingPermissions(void)
{
    if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
        return false;
    
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
        return false;
    
    if(!TerminalInfoInteger(TERMINAL_CONNECTED))
        return false;
    
    return true;
}

double CUnifiedRiskManager::CalculateSymbolCorrelation(const string symbol1, const string symbol2)
{
    // Delegate to unified correlation engine via portfolio risk manager
    if(CheckPointer(&m_portfolioRiskManager) != POINTER_INVALID)
    {
        CCorrelationEngine* engine = m_portfolioRiskManager.GetCorrelationEngine();
        if(engine != NULL)
            return engine.GetCorrelation(symbol1, symbol2);
    }
    
    // Fallback: conservative return when engine unavailable
    return 1.0;
}

double CUnifiedRiskManager::GetMaxCorrelationWithPortfolio(const string symbolParam)
{
    // This is an alias for CalculateCorrelationRisk
    return CalculateCorrelationRisk(symbolParam);
}

void CUnifiedRiskManager::WriteAuditLog(const string message)
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

string CUnifiedRiskManager::FormatValidationMessage(const STradeValidationRequest &request, const SValidationResult &result)
{
    string clusterCode = NormalizeClusterCode(request.clusterCode);
    return StringFormat("VALIDATION: %s %s %.3f lots | %s | Role=%s | Cluster=%s(%s) | Risk: %.2f%% | Portfolio: %.2f%% | Correlation: %.2f",
                       request.symbol,
                       EnumToString(request.orderType),
                       request.lotSize,
                       result.approved ? "APPROVED" : "REJECTED",
                       request.strategyRole,
                       request.strategyCluster,
                       clusterCode,
                       result.riskPercent,
                       result.portfolioRisk,
                       result.correlationRisk);
}

void CUnifiedRiskManager::UpdatePerformanceMetrics(const ulong startTimeParam)
{
    ulong endTime = GetMicrosecondCount();
    double validationTime = 0.0;
    if(endTime >= startTimeParam)
        validationTime = (double)(endTime - startTimeParam) / 1000.0; // microseconds -> milliseconds
    
    if(m_validationCount == 1)
    {
        m_avgValidationTime = validationTime;
    }
    else
    {
        m_avgValidationTime = (m_avgValidationTime * (m_validationCount - 1) + validationTime) / m_validationCount;
    }
    
    m_lastValidation = TimeCurrent();
}

string CUnifiedRiskManager::NormalizeClusterCode(const string clusterCode) const
{
    string code = clusterCode;
    StringTrimLeft(code);
    StringTrimRight(code);
    StringToUpper(code);
    
    if(StringLen(code) <= 0)
        return "N";
    
    string first = StringSubstr(code, 0, 1);
    if(first == "T" || first == "R" || first == "S" || first == "N")
        return first;
    
    if(StringFind(code, "TREND") >= 0)
        return "T";
    if(StringFind(code, "MEAN") >= 0 || StringFind(code, "REVERSION") >= 0)
        return "R";
    if(StringFind(code, "STRUCTURE") >= 0)
        return "S";
    
    return "N";
}

bool CUnifiedRiskManager::ParseClusterCodeFromComment(const string comment, string &clusterCode) const
{
    clusterCode = "N";
    int marker = StringFind(comment, "K:");
    if(marker < 0 || (marker + 2) >= StringLen(comment))
        return false;
    
    clusterCode = NormalizeClusterCode(StringSubstr(comment, marker + 2, 1));
    return true;
}

double CUnifiedRiskManager::EstimatePositionRiskPercent(const ulong ticket) const
{
    if(ticket == 0 || !PositionSelectByTicket(ticket))
        return 0.0;
    
    string symbol = PositionGetString(POSITION_SYMBOL);
    double volume = PositionGetDouble(POSITION_VOLUME);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double stopLoss = PositionGetDouble(POSITION_SL);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    if(point <= 0.0)
        point = 0.00001;
    
    if(stopLoss <= 0.0 || openPrice <= 0.0 || volume <= 0.0)
    {
        // Batch 120: Conservative — assume max risk for positions without SL
        // This prevents cluster risk budget from being underestimated
        return m_config.maxRiskPerTradePercent;
    }
    
    double slPoints = MathAbs(openPrice - stopLoss) / point;
    if(slPoints <= 0.0)
    {
        // Batch 120: Same conservative treatment for zero-distance SL
        return m_config.maxRiskPerTradePercent;
    }
    
    double riskAmount = CalculateTradeRisk(symbol, volume, slPoints);
    if(riskAmount <= 0.0)
        return m_config.maxRiskPerTradePercent;
    
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double denominator = 0.0;
    if(balance > 0.0 && equity > 0.0)
        denominator = MathMin(balance, equity);
    else
        denominator = MathMax(balance, equity);
    
    if(denominator <= 0.0)
        return m_config.maxRiskPerTradePercent;
    
    return (riskAmount / denominator) * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale
}

double CUnifiedRiskManager::GetCurrentPortfolioRisk()
{
    return m_portfolioRiskManager.GetPortfolioRisk();
}

void CUnifiedRiskManager::SetClusterRiskCap(const string clusterCode, const double capPercent)
{
    string normalizedCode = NormalizeClusterCode(clusterCode);
    // Update existing entry if found
    for(int i = 0; i < ArraySize(m_clusterRiskCapCodes); i++)
    {
        if(m_clusterRiskCapCodes[i] == normalizedCode)
        {
            m_clusterRiskCapValues[i] = MathMax(0.1, capPercent);
            PrintFormat("[RISK-CLUSTER-CAP-PER] Updated cluster=%s cap=%.2f%%", normalizedCode, m_clusterRiskCapValues[i]);
            return;
        }
    }
    // Add new entry
    int newSize = ArraySize(m_clusterRiskCapCodes) + 1;
    ArrayResize(m_clusterRiskCapCodes, newSize);
    ArrayResize(m_clusterRiskCapValues, newSize);
    m_clusterRiskCapCodes[newSize - 1] = normalizedCode;
    m_clusterRiskCapValues[newSize - 1] = MathMax(0.1, capPercent);
    PrintFormat("[RISK-CLUSTER-CAP-PER] Added cluster=%s cap=%.2f%%", normalizedCode, m_clusterRiskCapValues[newSize - 1]);
}

void CUnifiedRiskManager::ClearOpposingConflictCache(const string symbol)
{
    if(m_lastOpposingConflictSymbol == symbol)
    {
        m_lastOpposingConflictTime = 0;
        m_lastOpposingConflictSymbol = "";
        PrintFormat("[RISK-MUTEX-COOLDOWN] cache cleared for symbol=%s", symbol);
    }
}

void CUnifiedRiskManager::GetValidationStats(int &total, int &approved, int &rejected, double &approvalRate)
{
    total = m_validationCount;
    approved = m_approvedCount;
    rejected = m_rejectedCount;
    
    if(total > 0)
        approvalRate = (double)approved / total * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale
    else
        approvalRate = 0.0;
}

void CUnifiedRiskManager::ResetStats(void)
{
    m_validationCount = 0;
    m_approvedCount = 0;
    m_rejectedCount = 0;
    
    WriteAuditLog("Validation statistics reset");
}

#endif // CORE_RISK_UNIFIED_RISK_MANAGER_MQH

