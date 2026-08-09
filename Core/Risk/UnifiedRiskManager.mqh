//+------------------------------------------------------------------+
//| UnifiedRiskManager.mqh                                           |
//| Single authoritative risk contract for the EA runtime            |
//+------------------------------------------------------------------+
#ifndef CORE_RISK_UNIFIED_RISK_MANAGER_MQH
#define CORE_RISK_UNIFIED_RISK_MANAGER_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "../Monitoring/PerformanceAnalytics.mqh"
#include "../Utils/JsonLogger.mqh"
#include "PortfolioRiskManager.mqh"
#include "VirtualPosition.mqh"
#include "../Utils/TradeJournal.mqh"
#include "../Processing/DerivAssetProfiler.mqh"
#include "../Utils/RiskMath.mqh"
// Phase E1 extracted sub-modules (behaviour-preserving decomposition)
#include "RiskClusterCodec.mqh"
#include "RiskSymbolStats.mqh"
#include "RiskValidationStats.mqh"
// Phase E2 extracted sub-modules (behaviour-preserving decomposition)
#include "RiskClusterBudget.mqh"
#include "RiskOpposingConflictGuard.mqh"
#include "RiskCircuitBreaker.mqh"
#include "RiskMarginHealth.mqh"
// Phase E3 extracted sub-modules (behaviour-preserving decomposition)
#include "RiskTieredCorrelation.mqh"
#include "RiskAdaptiveTuner.mqh"
// Phase E4 extracted sub-module (behaviour-preserving decomposition).
// Provides:
//   - SUnifiedRiskConfig / STradeValidationRequest (relocated verbatim, this
//     header is included before they are first used below),
//   - IRiskPipelineHost  (call-back interface implemented by CUnifiedRiskManager),
//   - CRiskValidationPipeline (owns ValidateTradeRequest + the 7 sub-checks).
#include "RiskValidationPipeline.mqh"
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
//|                                                                  |
//| Phase E4: struct SUnifiedRiskConfig was relocated VERBATIM to     |
//| RiskValidationPipeline.mqh (included above) because both          |
//| CUnifiedRiskManager and CRiskValidationPipeline need the complete |
//| type. Field list, order and semantics are unchanged.              |
//+------------------------------------------------------------------+

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
//|                                                                  |
//| Phase E4: struct STradeValidationRequest was relocated VERBATIM   |
//| to RiskValidationPipeline.mqh (included above) because both       |
//| CUnifiedRiskManager and CRiskValidationPipeline need the complete |
//| type. Field list, order, defaults and semantics are unchanged.    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Unified risk manager                                             |
//|                                                                  |
//| Phase E4: implements IRiskPipelineHost so CRiskValidationPipeline |
//| can call back into the owner-private bookkeeping (daily budget,   |
//| per-symbol budgets/overrides, virtual reservations, audit log)    |
//| WITHOUT duplicating any of it. Every interface entry below is an  |
//| already-existing CUnifiedRiskManager method; the single addition  |
//| is CopyRiskConfig() (MQL5 forbids pointers to structures).        |
//+------------------------------------------------------------------+
class CUnifiedRiskManager : public IRiskPipelineHost
{
private:
    SUnifiedRiskConfig m_config;
    // OWNED: Value member - automatically constructed/destroyed with UnifiedRiskManager
    CPortfolioRiskManager m_portfolioRiskManager;
    // OWNED: Value member - automatically constructed/destroyed
    CVirtualPositionBook m_virtualPositionBook;
    // NON-OWNING: Raw pointer to PerformanceAnalytics owned by EAOrchestrator
    // Lifetime: EAOrchestrator creates/owns; UnifiedRiskManager only references
    CPerformanceAnalytics* m_performanceAnalytics;

    // Phase E3: m_activeRiskPerTradePercent now lives in CRiskAdaptiveTuner.
    double m_dailyRiskUsedPercent;
    double m_dailyStartEquity;
    datetime m_lastDailyReset;
    bool m_initialized;
    // Phase E3: m_conservativeMode now lives in CRiskAdaptiveTuner.
    datetime m_lastPressureLogTime;
    
    // Phase E2: drawdown / daily-loss circuit breakers, graduated auto-recovery
    // and the emergency-close escalation flag now live in CRiskCircuitBreaker.
    // OWNED: Value member - constructor performs the zero-init that used to
    // live in this class's initialiser list.
    CRiskCircuitBreaker m_circuitBreaker;

    // Broker trading day boundary tracking
    int m_lastTradingDayKey;         // Cached trading day key (YYYYMMDD)
    int m_tradingDayStartHour;       // Hour when broker trading day starts (default 0 = midnight server time)

    // Per-Symbol Risk Budgeting (Phase 5)
    SSymbolRiskBudget m_symbolBudgets[];
    int m_symbolBudgetCount;
    datetime m_lastBudgetRefresh;

    // Phase E3: m_riskReductionFactor now lives in CRiskAdaptiveTuner.

    // Per-symbol risk overrides (family-specific risk parameters)
    SSymbolRiskOverride m_riskOverrides[];
    int m_riskOverrideCount;

    // Phase E3: m_lastThrottlePressure now lives in CRiskAdaptiveTuner.

    long m_eaMagicNumber;  // Batch 119: EA magic number for position filtering

        // Deriv asset profiler for family detection
        CDerivAssetProfiler m_derivAssetProfiler;

        // Validation gate state (moved from CRiskValidationGate to consolidate risk authority)
    bool m_clusterGovernanceEnabled;
    bool m_clusterMutexEnabled;
    int m_maxConcurrentPerCluster;
    double m_maxClusterRiskPercent;
    // Phase E2: free-margin / margin-level thresholds and the runtime margin
    // health monitor now live in CRiskMarginHealth.
    // OWNED: Value member - constructor performs the zero-init that used to
    // live in this class's initialiser list.
    CRiskMarginHealth m_marginHealth;
    // Phase E2: opposing same-symbol conflict cooldown cache (Fix #9).
    // OWNED: Value member - constructor performs the zero-init that used to
    // live in this class's initialiser list.
    CRiskOpposingConflictGuard m_opposingGuard;
    // Phase E2: per-cluster risk cap registry (Fix #11).
    // OWNED: Value member - constructor seeds the T/R default overrides that
    // used to be written in this class's constructor body.
    CRiskClusterBudget m_clusterBudget;
    string m_clusterSyncCodes[];
    int m_clusterSyncCounts[];
    // Phase E1: validation counters, timing metrics and audit log sink.
    // OWNED: Value member - constructor performs the zero-init that used to
    // live in this class's initialiser list.
    CRiskValidationStats m_validationStats;
    // Phase E3: tiered correlation logic (threshold config + portfolio PRM pointer).
    // OWNED: Value member - constructor seeds the threshold defaults and
    // sets the portfolio risk manager pointer that used to be accessed
    // directly as m_portfolioRiskManager in URM's method bodies.
    CRiskTieredCorrelation m_tieredCorrelation;
    // Phase E3: adaptive risk-sizing state (active risk, conservative mode,
    // throttle pressure, risk reduction factor).
    // OWNED: Value member - constructor performs the zero-init that used to
    // live in this class's initialiser list.
    CRiskAdaptiveTuner m_adaptiveTuner;

    // Additional validation parameters (formerly in CRiskValidationGate)
    double m_emergencyRiskOverride;   // Blueprint 10.4: 0-100 scale (5.0 = 5%)

    // Phase E4: the pre-trade validation pipeline (ValidateTradeRequest and
    // its 7 sub-checks). OWNED: value member - automatically constructed and
    // destroyed with CUnifiedRiskManager. It holds only NON-OWNING pointers
    // back to this object and to the value members declared above; those
    // addresses are stable for this object's whole lifetime.
    // Declared LAST so that every collaborator it points at is already fully
    // constructed when WireValidationPipeline() runs in the constructor body.
    CRiskValidationPipeline m_validationPipeline;

    // Phase E4: single wiring point, called from the constructor body and
    // again from Initialize() (so a re-Initialize refreshes the mirrored
    // scalars). Idempotent.
    void WireValidationPipeline();

public:
    CUnifiedRiskManager();
    ~CUnifiedRiskManager();

    bool Initialize(const SUnifiedRiskConfig &config, CPerformanceAnalytics* performanceAnalytics = NULL);

    // Called each cycle/new bar to keep limits and adaptive risk current.
    void RefreshRuntimeState();
    // IRiskPipelineHost
    virtual void CheckAndResetDailyLimits();
    
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
                                double effectiveDailyLossLimit,
                                double maxRiskPerTradeOverride);

    // Per-symbol risk overrides (family-specific risk parameters)
    void SetRiskPerTrade(const string symbol, double riskPct);
    void SetMaxDrawdownForFamily(const string symbol, double maxDDPct);
    // IRiskPipelineHost
    virtual double GetEffectiveRiskPerTrade(const string symbol) const;
    // IRiskPipelineHost
    virtual double GetEffectiveMaxDrawdown(const string symbol) const;

    // Phase E4 / IRiskPipelineHost: MQL5 has no pointers to structures, so the
    // pipeline cannot hold "&m_config". It copies the live struct at every
    // public entry point instead. Read-only for the caller.
    virtual void CopyRiskConfig(SUnifiedRiskConfig &outConfig) const { outConfig = m_config; }

    // Phase E4 / IRiskPipelineHost: promoted from private to public so the
    // pipeline can reach it through the interface. Behaviour unchanged; the
    // former "= 0.0" default is dropped because every call site in the code
    // base already passes an explicit argument.
    virtual double GetEffectiveDailyRiskUsedPercent(const double additionalRiskPercent);

    // Single trade validation authority.
    // Phase E4: thin forwarder -> CRiskValidationPipeline::Run (signature unchanged).
        SValidationResult ValidateTradeRequest(const STradeValidationRequest &request, const string phaseTag = "runtime", const string corrId = "");
        void ConfigureClusterGovernance(const bool enabled,
                                    const int maxConcurrentPerCluster,
                                    const double maxClusterRiskPercent,
                                    const bool enableMutex);

    // Sync inherited cluster position counts on EA restart
    void SyncClusterPositionCounts();
    // IRiskPipelineHost
    virtual bool ReserveVirtualPosition(const string ownerTag,
                                        const STradeValidationRequest &request,
                                        const double riskPercent);
    // IRiskPipelineHost
    virtual void ReleaseVirtualPosition(const string ownerTag);
    void ClearVirtualPositions();

    // Register accepted risk usage only after successful execution.
    void RegisterExecutedTradeRisk(const SValidationResult &validationResult, const double fillRatio = 1.0);

    double GetActiveRiskPerTradePercent() const { return m_adaptiveTuner.GetActiveRiskPerTradePercent(); }
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
    // IRiskPipelineHost
    virtual bool IsInitialized() const { return m_initialized; }

    // Access portfolio risk manager (for wiring correlation engine to PositionSizer)
    CPortfolioRiskManager* GetPortfolioRiskManager() { return &m_portfolioRiskManager; }

    // Set broker trading day start hour (0=midnight server time, 17=5pm for forex rollover)
    void SetTradingDayStartHour(int hour) { m_tradingDayStartHour = MathMax(0, MathMin(23, hour)); }
    
    // EAMagicNumber is stored for validation gate use
    // Phase E4: push-synced into the pipeline, which mirrors this scalar.
    void SetEAMagicNumber(long magic)
    {
        m_eaMagicNumber = magic;
        m_validationPipeline.SetEAMagicNumber(magic);
    }
    
    // ENHANCEMENT: Circuit Breaker & Correlation Methods (Batch 93 - Week 1)
    // IRiskPipelineHost
    virtual bool CheckDrawdownCircuitBreaker();
    double GetCurrentDrawdownPercent() const;
    bool IsTradingEnabled() const;
    bool IsEmergencyCloseRequested() const;
    void ResetEmergencyCloseRequested();
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
    // IRiskPipelineHost
    virtual bool CheckDailyLossLimit();

    // Per-Symbol Risk Budgeting (Phase 5)
    // IRiskPipelineHost
    virtual double GetSymbolRiskAllocation(const string symbol);
    // IRiskPipelineHost
    virtual bool IsSymbolBudgetAvailable(const string symbol, const double riskPct);
    void RefreshSymbolBudgets();
    // IRiskPipelineHost
    virtual double GetSymbolUsedRisk(const string symbol);
    double GetSymbolWinRate(const string symbol);
    double GetSymbolProfitFactor(const string symbol);

    // Margin health monitoring (Phase 2.4)
    ENUM_MARGIN_HEALTH_LEVEL MonitorMarginHealth();

    // Single source of truth for drawdown state (Phase 2.1)
    // IRiskPipelineHost
    virtual SDrawdownState GetDrawdownState();
    
    // ENHANCEMENT: Correlation and position risk methods (Batch 93)
    double GetSymbolCorrelation(const string symbol1, const string symbol2);
    double CalculatePositionRiskPercent(ulong ticket);

// Inline validation methods (formerly in CRiskValidationGate)
// Phase E4: the bodies now live in CRiskValidationPipeline; the declarations
// below are preserved 1:1 and forward to it (CRiskValidationGate and other
// callers keep working unchanged).
    bool ValidateBasicParameters(const STradeValidationRequest &request, string &message);
    bool ValidateRiskLimits(const STradeValidationRequest &request, string &message, double &riskPercent);
    bool ValidatePortfolioRisk(const STradeValidationRequest &request, const double tradeRiskPercent, string &message);
    bool ValidateCorrelationLimits(const STradeValidationRequest &request, string &message, double &correlationRisk);
    bool ValidateMarginRequirements(const STradeValidationRequest &request, string &message);
    bool ValidateAccountHealth(const STradeValidationRequest &request, string &message);
    bool ValidateClusterGovernance(const STradeValidationRequest &request, const double tradeRiskPercent, string &message);
    // IRiskPipelineHost
    virtual double CalculateTradeRisk(const string symbolParam, const double lotSize, const double stopLossPips) const;
    double CalculateCorrelationRisk(const string symbolParam);
    // IRiskPipelineHost
    virtual double CalculatePortfolioRiskAfterTrade(const double additionalRisk);
    double GetPortfolioRiskValue();
    bool PortfolioAllowsTrade(const string symbolParam, const double lotSize);
    bool PortfolioCorrelationAllowed(const string symbolParam);
    bool PortfolioEmergencyActive();
    bool PortfolioHasUnprotectedPositions();
    // IRiskPipelineHost
    virtual bool IsSymbolDataValid(const string symbolParam);
    double GetSymbolTickValue(const string symbolParam);
    double GetSymbolPoint(const string symbolParam);
    // IRiskPipelineHost
    virtual bool CheckAccountTradingPermissions(void);
    double CalculateSymbolCorrelation(const string symbol1Param, const string symbol2Param);
    double GetMaxCorrelationWithPortfolio(const string symbolParam);
    string NormalizeClusterCode(const string clusterCode) const;
    bool ParseClusterCodeFromComment(const string comment, string &clusterCode) const;
    // IRiskPipelineHost
    virtual double EstimatePositionRiskPercent(const ulong ticket) const;
    // IRiskPipelineHost
    virtual void LogValidationResult(const STradeValidationRequest &request, const SValidationResult &result);
    void WriteAuditLog(const string message);
    string FormatValidationMessage(const STradeValidationRequest &request, const SValidationResult &result);
    // IRiskPipelineHost
    virtual void UpdatePerformanceMetrics(const ulong startTime);
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
    // Phase E4: GetEffectiveDailyRiskUsedPercent moved to the public section
    // (IRiskPipelineHost implementation). Body and behaviour are unchanged.
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
    // Phase E3 forwarder -> CRiskAdaptiveTuner::SetActiveRiskPerTradePercent
    m_adaptiveTuner.SetActiveRiskPerTradePercent(ClampRiskPercent(riskPercent));
}

//+------------------------------------------------------------------+
//| Apply tier overrides without full reinitialization                |
//| Updates only tier-controlled parameters, preserving runtime state |
//+------------------------------------------------------------------+
void CUnifiedRiskManager::ApplyTierOverrides(double tierRiskPerTradePct,
                                             int tierMaxPositions,
                                             double effectiveDaily, double effectivePortfolio,
                                             double effectiveDdWarning, double effectiveDdCritical,
                                             double effectiveDailyLossLimit,
                                             double maxRiskPerTradeOverride)
{
    // Update config parameters controlled by tier system
        m_config.baseRiskPerTradePercent = tierRiskPerTradePct;
        m_config.maxRiskPerTradePercent  = maxRiskPerTradeOverride;  // L5-006: use explicit override instead of 2x formula
        m_config.maxDailyRiskPercent     = effectiveDaily;
        m_config.maxPortfolioRiskPercent = effectivePortfolio;
        m_config.drawdownWarningPercent  = effectiveDdWarning;
        m_config.drawdownCriticalPercent = effectiveDdCritical;
        m_config.dailyLossLimitPercent   = effectiveDailyLossLimit;
        m_config.maxPositionsSameBase    = tierMaxPositions;

        // Update active risk per trade
        // Phase E3 forwarder -> CRiskAdaptiveTuner::SetActiveRiskPerTradePercent
        m_adaptiveTuner.SetActiveRiskPerTradePercent(ClampRiskPercent(m_config.baseRiskPerTradePercent));

        // Update portfolio risk manager limits (no reinitialization)
        m_portfolioRiskManager.SetMaxPortfolioRisk(effectivePortfolio);

        PrintFormat("[RISK-INIT-SINGLE] Tier overrides applied (no reinit) | risk=%.1f%% | maxRisk=%.1f%% | daily=%.1f%% | portfolio=%.1f%% | ddWarn=%.1f%% | ddCrit=%.1f%%",
                    m_config.baseRiskPerTradePercent,
                    m_config.maxRiskPerTradePercent,
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
    // L5-020 FIX: Return active risk per trade (reduced in conservative mode) instead of base risk
    // Phase E3 forwarder -> CRiskAdaptiveTuner::GetActiveRiskPerTradePercent
    return m_adaptiveTuner.GetActiveRiskPerTradePercent();
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
    // Phase E3: m_activeRiskPerTradePercent, m_riskReductionFactor,
    // m_lastThrottlePressure, m_conservativeMode now live in
    // CRiskAdaptiveTuner::CRiskAdaptiveTuner() (identical values).
    m_dailyRiskUsedPercent(0.0),
    m_dailyStartEquity(0.0),
    m_lastDailyReset(0),
    m_initialized(false),
    m_lastPressureLogTime(0),
    // Phase E2: circuit-breaker defaults now live in
    // CRiskCircuitBreaker::CRiskCircuitBreaker() (identical values).
    m_lastTradingDayKey(0),
    m_tradingDayStartHour(0),
    m_symbolBudgetCount(0),
    m_lastBudgetRefresh(0),
    m_riskOverrideCount(0),
    m_eaMagicNumber(0),
    // Validation gate state (moved from CRiskValidationGate)
    m_clusterGovernanceEnabled(true),
    m_clusterMutexEnabled(true),
    m_maxConcurrentPerCluster(5),
    m_maxClusterRiskPercent(5.0),
    // Phase E2: margin-health thresholds now live in
    // CRiskMarginHealth::CRiskMarginHealth() (identical values).
    // Phase E2: opposing-conflict cooldown defaults now live in
    // CRiskOpposingConflictGuard::CRiskOpposingConflictGuard() (identical values).
    // Phase E1: audit-log + validation counter defaults now live in
    // CRiskValidationStats::CRiskValidationStats() (identical values).
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
    m_config.minLotRiskMultiplier = 15.0;     // Restored 15x tolerance for min-lot round-up (reverted L5-002 1x clamp)
    m_config.adaptationMinTrades = 20;
    m_config.enableAdaptiveSizing = true;
    m_config.enableAuditLogging = true;
    m_config.auditLogFile = "UnifiedRiskValidation.log";

    // Phase E2: per-cluster risk caps (Fix #11) default overrides are now
    // seeded by CRiskClusterBudget::CRiskClusterBudget() (identical values).

    // Phase E3: sync correlation threshold config to CRiskTieredCorrelation
    // and wire the portfolio risk manager pointer (stable for URM's lifetime).
    m_tieredCorrelation.SetThresholds(m_config.correlationThreshold,
                                      m_config.correlationReduceThreshold,
                                      m_config.correlationBlockThreshold);
    m_tieredCorrelation.SetPortfolioRiskManager(&m_portfolioRiskManager);

    // Phase E4: wire the validation pipeline here (not in Initialize) so that
    // ValidateTradeRequest is never able to dereference a NULL collaborator,
    // even if it is somehow called before Initialize(). All value members are
    // fully constructed by the time the constructor body runs.
    WireValidationPipeline();
}

//+------------------------------------------------------------------+
//| Phase E4: wire CRiskValidationPipeline to its collaborators.      |
//|                                                                  |
//| Every pointer handed over is NON-OWNING: it is either this object |
//| (as IRiskPipelineHost) or the address of one of this object's own |
//| value members. Those addresses are stable for the whole lifetime  |
//| of CUnifiedRiskManager, so re-running this method is safe and     |
//| idempotent. Mutable scalars mirrored by the pipeline are re-sent  |
//| here and push-synced from their setters.                          |
//+------------------------------------------------------------------+
void CUnifiedRiskManager::WireValidationPipeline()
{
    m_validationPipeline.Initialize(GetPointer(this),
                                    GetPointer(m_circuitBreaker),
                                    GetPointer(m_virtualPositionBook),
                                    GetPointer(m_portfolioRiskManager),
                                    GetPointer(m_adaptiveTuner),
                                    GetPointer(m_tieredCorrelation),
                                    GetPointer(m_clusterBudget),
                                    GetPointer(m_marginHealth),
                                    GetPointer(m_opposingGuard),
                                    GetPointer(m_validationStats),
                                    GetPointer(m_derivAssetProfiler),
                                    m_eaMagicNumber,
                                    m_emergencyRiskOverride,
                                    m_clusterGovernanceEnabled,
                                    m_clusterMutexEnabled,
                                    m_maxConcurrentPerCluster,
                                    m_maxClusterRiskPercent);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CUnifiedRiskManager::~CUnifiedRiskManager()
{
    // No manual cleanup required - all owned resources use RAII via value members:
    // - m_portfolioRiskManager (value member, auto-destroyed)
    // - m_virtualPositionBook (value member, auto-destroyed)
    // - m_performanceAnalytics is NON-OWNING (owned by EAOrchestrator)
    // This class owns NO raw pointers to dynamically allocated memory.
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CUnifiedRiskManager::Initialize(const SUnifiedRiskConfig &config,
                                     CPerformanceAnalytics* perfAnalytics)
{
    m_config = config;
    // NON-OWNING: perfAnalytics is owned by EAOrchestrator (created in OnInit, destroyed in Shutdown)
    // UnifiedRiskManager only stores a reference for metrics queries
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
        m_config.minLotRiskMultiplier = 1.0;

    // Phase E3: sync correlation threshold config to CRiskTieredCorrelation
    // after clamping is complete.
    m_tieredCorrelation.SetThresholds(m_config.correlationThreshold,
                                      m_config.correlationReduceThreshold,
                                      m_config.correlationBlockThreshold);

    if(!m_portfolioRiskManager.Initialize(m_config.maxPortfolioRiskPercent, m_config.correlationThreshold))
    {
        Print("[RISK-UNIFIED] Failed to initialize portfolio risk manager");
        return false;
    }

    m_eaMagicNumber = 0;
    // Phase E3 forwarder -> CRiskAdaptiveTuner::SetActiveRiskPerTradePercent
    m_adaptiveTuner.SetActiveRiskPerTradePercent(ClampRiskPercent(m_config.baseRiskPerTradePercent));
    m_dailyRiskUsedPercent = 0.0;
    m_virtualPositionBook.Clear();
    m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(m_dailyStartEquity <= 0.0)
        m_dailyStartEquity = AccountInfoDouble(ACCOUNT_BALANCE);
    
    // ENHANCEMENT: Initialize drawdown circuit breaker (Batch 93 - Week 1)
    // Phase E2 forwarder -> CRiskCircuitBreaker::InitializeState
    // (also re-arms the daily P&L loss limit circuit breaker)
    m_circuitBreaker.InitializeState(m_dailyStartEquity);

    // Broker trading day boundary
    m_lastTradingDayKey = 0;

    m_lastDailyReset = TimeCurrent();
    m_initialized = true;

    // Phase E4: re-wire the validation pipeline so it picks up the freshly
    // clamped config and the reset m_eaMagicNumber. Idempotent - all pointers
    // are the same stable addresses that were handed over in the constructor.
    WireValidationPipeline();

    // Risk percent scale validation — catch misconfiguration early
    // Phase E3: read from CRiskAdaptiveTuner
    double activeRiskCheck = m_adaptiveTuner.GetActiveRiskPerTradePercent();
    if(activeRiskCheck < 0.01 || activeRiskCheck > 20.0)
        PrintFormat("WARNING: Risk per trade %.2f%% is outside safe range [0.01, 20.0] — verify input scale is 0-100 not 0-1",
                    activeRiskCheck);

    PrintFormat("[RISK-UNIFIED] Initialized | Base %.2f%% | Range %.2f-%.2f%% | Daily %.2f%% | Portfolio %.2f%%",
                m_config.baseRiskPerTradePercent,
                m_config.minRiskPerTradePercent,
                m_config.maxRiskPerTradePercent,
                m_config.maxDailyRiskPercent,
                m_config.maxPortfolioRiskPercent);
    
    PrintFormat("[RISK-CIRCUIT-BREAKER] Enabled | Initial Equity=%.2f | Drawdown Limits: Warning=%.1f%% Critical=%.1f%%",
                m_circuitBreaker.GetPeakEquity(), m_config.drawdownWarningPercent, m_config.drawdownCriticalPercent);

    return true;
}

//+------------------------------------------------------------------+
//| Refresh runtime state                                            |
//+------------------------------------------------------------------+
void CUnifiedRiskManager::RefreshRuntimeState()
{
    if(!m_initialized)
        return;

    // Update peak equity and drawdown from peak - keeps the circuit breaker's
    // drawdown reading current.
    // Phase E2 forwarder -> CRiskCircuitBreaker::RefreshPeakAndDrawdown
    m_circuitBreaker.RefreshPeakAndDrawdown();

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
        // Phase E2 forwarder -> CRiskCircuitBreaker::ResetRecoveryCounterForNewDay
        m_circuitBreaker.ResetRecoveryCounterForNewDay();

        Print("[RISK-UNIFIED] Daily risk usage reset");
    }
}

//+------------------------------------------------------------------+
//| Validate trade request                                           |
//|                                                                  |
//| Phase E4: THIN FORWARDER. The full pre-trade gating pipeline      |
//| (initialization guard, daily-loss / drawdown / family-drawdown    |
//| circuit breakers, daily-budget check, virtual-reservation         |
//| conflict + early reserve/release, the 7 sub-validations, lot      |
//| floor, per-symbol budget, portfolio projection, family position   |
//| limit, tiered correlation block/reduce, risk recompute, projected |
//| daily risk and the approval path) now lives verbatim in           |
//| CRiskValidationPipeline::Run.                                      |
//|                                                                  |
//| The signature, the default arguments and every accept/reject      |
//| decision and its ordering are unchanged. The pipeline calls back  |
//| into this object through IRiskPipelineHost for all owner-private  |
//| bookkeeping, so no state is cloned and no logic is duplicated.    |
//+------------------------------------------------------------------+
SValidationResult CUnifiedRiskManager::ValidateTradeRequest(const STradeValidationRequest &request,
                                                            const string phaseTag,
                                                            const string corrId)
{
    return m_validationPipeline.Run(request, phaseTag, corrId);
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

    // Phase E4: push the (already clamped) values into the pipeline, which
    // mirrors these scalars for ValidateClusterGovernance.
    m_validationPipeline.SetClusterGovernance(m_clusterGovernanceEnabled,
                                              m_maxConcurrentPerCluster,
                                              m_maxClusterRiskPercent,
                                              m_clusterMutexEnabled);

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
        // Phase E3: read from CRiskAdaptiveTuner
        riskUsed = m_adaptiveTuner.GetActiveRiskPerTradePercent();
    double normalizedFillRatio = MathMax(0.0, MathMin(1.0, fillRatio));
    m_dailyRiskUsedPercent += MathMax(0.0, riskUsed * normalizedFillRatio);
}

//+------------------------------------------------------------------+
//| Remaining daily risk                                             |
//+------------------------------------------------------------------+
double CUnifiedRiskManager::GetRemainingDailyRiskPercent()
{
    double remaining = m_config.maxDailyRiskPercent - GetEffectiveDailyRiskUsedPercent(GetReservedVirtualRiskPercent());
    if(remaining < 0.0) {
        PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, 1392, __FUNCTION__);
        return 0.0;
    }
    return remaining;
}

double CUnifiedRiskManager::GetRecommendedRiskPerTradePercent(const double requestedRiskPercent)
{
    if(!m_initialized) {
        PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, 1399, __FUNCTION__);
        return 0.0;
    }

    CheckAndResetDailyLimits();

    if(m_portfolioRiskManager.IsEmergencyMode() || HasUnprotectedPositions()) {
        PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, 1404, __FUNCTION__);
        return 0.0;
    }

    // Phase E3: cache adaptive-tuner state in locals (single-threaded EA, no race)
    double activeRisk = m_adaptiveTuner.GetActiveRiskPerTradePercent();
    bool conservative = m_adaptiveTuner.IsConservativeMode();

    double reservedRisk = GetReservedVirtualRiskPercent();
    double effectiveDailyRisk = GetEffectiveDailyRiskUsedPercent(reservedRisk);
    double openExposureRisk = GetCurrentOpenExposureRiskPercent() + reservedRisk;
    double remainingDailyRisk = MathMax(0.0, m_config.maxDailyRiskPercent - effectiveDailyRisk);
    double remainingPortfolioRisk = MathMax(0.0, m_config.maxPortfolioRiskPercent - openExposureRisk);
    double recommended = (requestedRiskPercent > 0.0) ? requestedRiskPercent : activeRisk;
    recommended = MathMin(recommended, activeRisk);
    recommended = MathMin(recommended, remainingDailyRisk);
    recommended = MathMin(recommended, remainingPortfolioRisk);

    if(recommended <= 0.0) {
        PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, 1417, __FUNCTION__);
        return 0.0;
    }

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

    if(conservative)
        pressureMultiplier = MathMin(pressureMultiplier, 0.80);

    // Issue 17: Store throttle pressure for position-limit adjustment
    // Phase E3 forwarder -> CRiskAdaptiveTuner::SetThrottlePressure
    m_adaptiveTuner.SetThrottlePressure(pressureMultiplier);

    recommended *= pressureMultiplier;
    recommended = MathMin(recommended, remainingDailyRisk);
    recommended = MathMin(recommended, remainingPortfolioRisk);

    if(recommended <= 0.0) {
        PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, 1448, __FUNCTION__);
        return 0.0;
    }

    if(pressureMultiplier < 0.999)
    {
        datetime now = TimeCurrent();
        if(m_lastPressureLogTime == 0 || (now - m_lastPressureLogTime) >= 60)
        {
            PrintFormat("[RISK-THROTTLE] requested=%.2f | active=%.2f | recommended=%.2f | pressure=%.2f | daily_used=%.2f/%.2f | portfolio_used=%.2f/%.2f | conservative=%s",
                        requestedRiskPercent > 0.0 ? requestedRiskPercent : activeRisk,
                        activeRisk,
                        recommended,
                        pressureMultiplier,
                        effectiveDailyRisk,
                        m_config.maxDailyRiskPercent,
                        openExposureRisk,
                        m_config.maxPortfolioRiskPercent,
                        conservative ? "true" : "false");
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
    if(remaining < 0.0) {
        PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, 1479, __FUNCTION__);
        return 0.0;
    }
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
// Phase E3 forwarder -> CRiskAdaptiveTuner::GetThrottlePressure
double CUnifiedRiskManager::GetThrottlePressure() const
{
    return m_adaptiveTuner.GetThrottlePressure();
}

//+------------------------------------------------------------------+
//| Snapshot                                                         |
//+------------------------------------------------------------------+
SUnifiedRiskSnapshot CUnifiedRiskManager::GetSnapshot()
{
    SUnifiedRiskSnapshot snapshot;
    ZeroMemory(snapshot);

    snapshot.activeRiskPerTradePercent = m_adaptiveTuner.GetActiveRiskPerTradePercent();
    snapshot.dailyEntryRiskUsedPercent = MathMax(0.0, m_dailyRiskUsedPercent);
    snapshot.dailyMarkToMarketLossPercent = CalculateDailyMarkToMarketLossPercent();
    snapshot.openExposureRiskPercent = GetCurrentOpenExposureRiskPercent();
    snapshot.virtualReservedRiskPercent = GetReservedVirtualRiskPercent();
    snapshot.dailyRiskUsedPercent = GetEffectiveDailyRiskUsedPercent(snapshot.virtualReservedRiskPercent);
    snapshot.maxDailyRiskPercent = m_config.maxDailyRiskPercent;
    snapshot.portfolioRiskPercent = snapshot.openExposureRiskPercent + snapshot.virtualReservedRiskPercent;
    snapshot.virtualReservationCount = GetVirtualReservationCount();
    snapshot.emergencyMode = m_portfolioRiskManager.IsEmergencyMode();
    snapshot.conservativeMode = m_adaptiveTuner.IsConservativeMode();

    // Inline stats (formerly from m_validationGate)
    int total = m_validationStats.GetValidationCount();
    int approved = m_validationStats.GetApprovedCount();
    int rejected = m_validationStats.GetRejectedCount();
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

    if(baselineEquity <= 0.0) {
        PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, 1577, __FUNCTION__);
        return 0.0;
    }

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
// Phase E3 forwarder -> CRiskAdaptiveTuner::UpdateAdaptiveRiskLevel
// Config values and analytics pointer are passed as parameters because
// they change at runtime (ApplyTierOverrides / SetPerformanceAnalytics).
void CUnifiedRiskManager::UpdateAdaptiveRiskLevel()
{
    m_adaptiveTuner.UpdateAdaptiveRiskLevel(m_config.baseRiskPerTradePercent,
                                            m_config.enableAdaptiveSizing,
                                            m_config.adaptationMinTrades,
                                            m_config.drawdownWarningPercent,
                                            m_config.drawdownCriticalPercent,
                                            m_config.minRiskPerTradePercent,
                                            m_config.maxRiskPerTradePercent,
                                            m_performanceAnalytics);
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
// Phase E2 forwarder -> CRiskCircuitBreaker::CheckDrawdownCircuitBreaker
bool CUnifiedRiskManager::CheckDrawdownCircuitBreaker()
{
    if(!m_initialized)
        return false;

    bool conservative = m_adaptiveTuner.IsConservativeMode();
    bool result = m_circuitBreaker.CheckDrawdownCircuitBreaker(m_config.drawdownWarningPercent,
                                                               m_config.drawdownCriticalPercent,
                                                               conservative);
    m_adaptiveTuner.SetConservativeMode(conservative);
    return result;
}

//+------------------------------------------------------------------+
//| Get current drawdown status                                      |
//+------------------------------------------------------------------+
// Phase E2 forwarder -> CRiskCircuitBreaker::GetMaxDrawdownFromPeak
double CUnifiedRiskManager::GetCurrentDrawdownPercent() const
{
    return m_circuitBreaker.GetMaxDrawdownFromPeak();
}

//+------------------------------------------------------------------+
//| Check if trading is enabled                                      |
//+------------------------------------------------------------------+
// Phase E2 forwarder -> CRiskCircuitBreaker::IsTradingEnabled
bool CUnifiedRiskManager::IsTradingEnabled() const
{
    return m_circuitBreaker.IsTradingEnabled();
}

//+------------------------------------------------------------------+
//| Check if emergency close has been requested                      |
//| L5-019: Emergency close flag set by circuit breaker             |
//+------------------------------------------------------------------+
// Phase E2 forwarder -> CRiskCircuitBreaker::IsEmergencyCloseRequested
bool CUnifiedRiskManager::IsEmergencyCloseRequested() const
{
    return m_circuitBreaker.IsEmergencyCloseRequested();
}

//+------------------------------------------------------------------+
//| Reset emergency close requested flag                             |
//| L5-019: Called after emergency close is executed                |
//+------------------------------------------------------------------+
// Phase E2 forwarder -> CRiskCircuitBreaker::ResetEmergencyCloseRequested
void CUnifiedRiskManager::ResetEmergencyCloseRequested()
{
    m_circuitBreaker.ResetEmergencyCloseRequested();
}

//+------------------------------------------------------------------+
//| Manually reset circuit breaker (after review)                    |
//+------------------------------------------------------------------+
// Phase E2 forwarder -> CRiskCircuitBreaker::ResetCircuitBreaker
void CUnifiedRiskManager::ResetCircuitBreaker()
{
    bool conservative = m_adaptiveTuner.IsConservativeMode();
    m_circuitBreaker.ResetCircuitBreaker(conservative);
    m_adaptiveTuner.SetConservativeMode(conservative);
}

//+------------------------------------------------------------------+
//| Crash recovery getters for circuit breaker state                  |
//+------------------------------------------------------------------+
// Phase E2 forwarder -> CRiskCircuitBreaker::GetPeakEquity
double CUnifiedRiskManager::GetPeakEquity() const
{
    return m_circuitBreaker.GetPeakEquity();
}

double CUnifiedRiskManager::GetDailyStartEquity() const
{
    return m_dailyStartEquity;
}

// Phase E2 forwarder -> CRiskCircuitBreaker::GetDrawdownBreachCount
int CUnifiedRiskManager::GetDrawdownBreachCount() const
{
    return m_circuitBreaker.GetDrawdownBreachCount();
}

// Phase E2 forwarder -> CRiskCircuitBreaker::GetMaxDrawdownFromPeak
double CUnifiedRiskManager::GetMaxDrawdownFromPeak() const
{
    return m_circuitBreaker.GetMaxDrawdownFromPeak();
}

//+------------------------------------------------------------------+
//| Restore circuit breaker state from crash recovery file            |
//+------------------------------------------------------------------+
// Phase E2 forwarder -> CRiskCircuitBreaker::RestoreCircuitBreakerState
void CUnifiedRiskManager::RestoreCircuitBreakerState(double savedPeakEquity, double savedDailyStartEquity,
                                                     int savedBreachCount, double savedMaxDrawdown)
{
    m_circuitBreaker.RestoreCircuitBreakerState(savedPeakEquity, savedDailyStartEquity,
                                                savedBreachCount, savedMaxDrawdown,
                                                m_dailyStartEquity);
}

//+------------------------------------------------------------------+
//| Helper: Get correlation between two symbols (Phase 2.2: engine)  |
//+------------------------------------------------------------------+
// Phase E3 forwarder -> CRiskTieredCorrelation::GetSymbolCorrelation
double CUnifiedRiskManager::GetSymbolCorrelation(const string symbol1, const string symbol2)
{
    return m_tieredCorrelation.GetSymbolCorrelation(symbol1, symbol2);
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

    double currentDrawdownPct = m_circuitBreaker.GetMaxDrawdownFromPeak();

    state.currentDrawdownPct  = currentDrawdownPct;
    state.isWarningActive     = (currentDrawdownPct >= m_config.drawdownWarningPercent &&
                                 currentDrawdownPct < m_config.drawdownCriticalPercent);
    state.isCriticalActive    = (currentDrawdownPct >= m_config.drawdownCriticalPercent);
    state.isTradingEnabled    = m_circuitBreaker.IsTradingEnabled();

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
    if(!PositionSelectByTicket(ticket)) {
        PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, 1950, __FUNCTION__);
        return 0.0;
    }
    
    double volume = PositionGetDouble(POSITION_VOLUME);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double sl = PositionGetDouble(POSITION_SL);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    
    // Issue 4 fix: Validate position exists with non-zero volume and SL
    // Closed or closing positions may still pass PositionSelectByTicket but return
    // zero volume or zero SL — skip them to prevent phantom risk
    if(volume <= 0.0 || sl == 0.0 || openPrice == 0.0) {
        PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, 1961, __FUNCTION__);
        return 0.0;
    }
    
    string symbol = PositionGetString(POSITION_SYMBOL);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    
    if(point <= 0.0 || tickValue <= 0.0) {
        PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, 1968, __FUNCTION__);
        return 0.0;
    }
    
    // Issue 16 fix: Use mark-to-market SL distance (current price to SL) instead of
    // entry price to SL. This ensures the risk budget reflects actual current exposure,
    // not the historical entry-based exposure. If price has moved toward SL, the
    // real risk is lower; if moved away, it's higher.
    double slDistance = MathAbs(currentPrice - sl) / point;
    double riskAmount = volume * slDistance * tickValue;
    
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity <= 0.0) {
        PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, 1979, __FUNCTION__);
        return 0.0;
    }
    
    return (riskAmount / equity) * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale
}

//+------------------------------------------------------------------+
//| Circuit Breaker Auto-Recovery (Phase 2.4)                        |
//| Attempts to re-enable trading after cooldown if drawdown recovers |
//| L5-010 FIX: Uses bar-based cooldown instead of wall-clock minutes |
//+------------------------------------------------------------------+
// Phase E2 forwarder -> CRiskCircuitBreaker::CheckCircuitBreakerRecovery
bool CUnifiedRiskManager::CheckCircuitBreakerRecovery()
{
    if(!m_initialized)
        return false;

    bool conservative = m_adaptiveTuner.IsConservativeMode();
    bool result = m_circuitBreaker.CheckCircuitBreakerRecovery(m_config.drawdownCriticalPercent,
                                                               conservative);
    m_adaptiveTuner.SetConservativeMode(conservative);
    return result;
}

//+------------------------------------------------------------------+
//| Margin Health Monitoring (Phase 2.4)                              |
//| Checks margin level and takes protective action                  |
//+------------------------------------------------------------------+
// Phase E2 forwarder -> CRiskMarginHealth::MonitorMarginHealth
ENUM_MARGIN_HEALTH_LEVEL CUnifiedRiskManager::MonitorMarginHealth()
{
    if(!m_initialized)
        return MARGIN_HEALTH_OK;

    bool conservative = m_adaptiveTuner.IsConservativeMode();
    ENUM_MARGIN_HEALTH_LEVEL level = m_marginHealth.MonitorMarginHealth(m_circuitBreaker, conservative);
    m_adaptiveTuner.SetConservativeMode(conservative);
    return level;
}

//+------------------------------------------------------------------+
//| Daily P&L Loss Limit circuit breaker                              |
//| Halts all trading when daily realized + unrealized loss exceeds   |
//| the configured percentage of daily starting equity. Resets on new day.      |
//+------------------------------------------------------------------+
// Phase E2 forwarder -> CRiskCircuitBreaker::ResetDailyLossHalt / EvaluateDailyLossLimit
bool CUnifiedRiskManager::CheckDailyLossLimit()
{
    if(!m_initialized)
        return false;

    datetime nowTime = TimeCurrent();

    // Reset halt on new trading day.
    // NOTE: IsNewTradingDay() mutates m_lastTradingDayKey, so it MUST stay
    // short-circuited behind the halt flag exactly as in the original code -
    // eagerly evaluating it here would advance the trading-day key and break
    // CheckAndResetDailyLimits().
    if(m_circuitBreaker.IsDailyLossHaltActive() && IsNewTradingDay(nowTime))
        m_circuitBreaker.ResetDailyLossHalt();

    return m_circuitBreaker.EvaluateDailyLossLimit(nowTime,
                                                   m_config.dailyLossLimitPercent,
                                                   m_dailyStartEquity);
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
// Phase E1 forwarder -> CRiskSymbolStats::GetWinRate
double CUnifiedRiskManager::GetSymbolWinRate(const string symbol)
{
    return CRiskSymbolStats::GetWinRate(symbol);
}

//+------------------------------------------------------------------+
//| Get per-symbol profit factor from deal history                    |
//+------------------------------------------------------------------+
// Phase E1 forwarder -> CRiskSymbolStats::GetProfitFactor
double CUnifiedRiskManager::GetSymbolProfitFactor(const string symbol)
{
    return CRiskSymbolStats::GetProfitFactor(symbol);
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
    if(equity <= 0.0) {
        PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, 2583, __FUNCTION__);
        return 0.0;
    }

    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    if(point <= 0.0 || tickValue <= 0.0 || tickSize <= 0.0) {
        PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, 2589, __FUNCTION__);
        return 0.0;
    }

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
    // Phase E3: read reduction factor from CRiskAdaptiveTuner
    double riskReductionFactor = m_adaptiveTuner.GetRiskReductionFactor();
    if(rawUsedRisk <= 0.0 || riskReductionFactor <= 0.0)
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
    double reduction = MathMax(0.0, profitRiskPct * riskReductionFactor);
    double adjustedUsedRisk = rawUsedRisk - reduction;
    adjustedUsedRisk = MathMax(0.0, adjustedUsedRisk);

    if(adjustedUsedRisk < rawUsedRisk)
    {
        PrintFormat("[RISK-BUDGET-PNL-ADJUSTED] Symbol=%s, usedRisk=%.2f%% reduced to %.2f%% (unrealized profit=%.2f, factor=%.1f)",
                    symbol, rawUsedRisk, adjustedUsedRisk, unrealizedProfit, riskReductionFactor);
    }

    return adjustedUsedRisk;
}

//+------------------------------------------------------------------+
//| Inline validation methods (formerly in CRiskValidationGate)      |
//|                                                                  |
//| Phase E4: the bodies were relocated VERBATIM into                 |
//| CRiskValidationPipeline. The seven methods below are kept as thin |
//| forwarders because they are part of the CUnifiedRiskManager       |
//| public API (CRiskValidationGate::ValidatePortfolioRisk delegates  |
//| into ValidatePortfolioRisk, and the pipeline itself is driven     |
//| through ValidateTradeRequest). Signatures are unchanged 1:1.      |
//|                                                                  |
//| No recursion: the pipeline resolves the owner-side helpers        |
//| (IsSymbolDataValid, CalculateTradeRisk, EstimatePositionRiskPercent, |
//| GetDrawdownState, ...) through IRiskPipelineHost, never through   |
//| these forwarders.                                                 |
//+------------------------------------------------------------------+
bool CUnifiedRiskManager::ValidateBasicParameters(const STradeValidationRequest &request, string &message)
{
    return m_validationPipeline.ValidateBasicParameters(request, message);
}

bool CUnifiedRiskManager::ValidateRiskLimits(const STradeValidationRequest &request, string &message, double &riskPercent)
{
    return m_validationPipeline.ValidateRiskLimits(request, message, riskPercent);
}

bool CUnifiedRiskManager::ValidatePortfolioRisk(const STradeValidationRequest &request, const double tradeRiskPercent, string &message)
{
    return m_validationPipeline.ValidatePortfolioRisk(request, tradeRiskPercent, message);
}

// Phase E3 forwarder -> CRiskTieredCorrelation::ValidateCorrelationLimits
// (now reached through CRiskValidationPipeline::ValidateCorrelationLimits).
// maxPositionsSameBase and eaMagicNumber are still supplied by the pipeline
// because they change at runtime (ApplyTierOverrides / SetEAMagicNumber).
bool CUnifiedRiskManager::ValidateCorrelationLimits(const STradeValidationRequest &request, string &message, double &correlationRisk)
{
    return m_validationPipeline.ValidateCorrelationLimits(request, message, correlationRisk);
}

bool CUnifiedRiskManager::ValidateMarginRequirements(const STradeValidationRequest &request, string &message)
{
    return m_validationPipeline.ValidateMarginRequirements(request, message);
}

bool CUnifiedRiskManager::ValidateAccountHealth(const STradeValidationRequest &request, string &message)
{
    return m_validationPipeline.ValidateAccountHealth(request, message);
}

bool CUnifiedRiskManager::ValidateClusterGovernance(const STradeValidationRequest &request,
                                                    const double tradeRiskPercent,
                                                    string &message)
{
    return m_validationPipeline.ValidateClusterGovernance(request, tradeRiskPercent, message);
}

double CUnifiedRiskManager::CalculateTradeRisk(const string symbolParam, double lotSize, double stopLossPips) const
{
    if(symbolParam == "" || stopLossPips <= 0) {
        PrintFormat("[DBG-RET0] %s:%d %s() returned 0.0", __FILE__, 3096, __FUNCTION__);
        return 0.0;
    }
    
    double tickValue = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_SIZE);
    double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
    double contractSize = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_CONTRACT_SIZE);
    
    if(tickValue <= 0 || point <= 0 || tickSize <= 0) {
        PrintFormat("[DBG-RET0] %s:%d %s() returned 0.0", __FILE__, 3105, __FUNCTION__);
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

// Phase E3 forwarder -> CRiskTieredCorrelation::CalculateCorrelationRisk
double CUnifiedRiskManager::CalculateCorrelationRisk(const string symbolParam)
{
    return m_tieredCorrelation.CalculateCorrelationRisk(symbolParam);
}

double CUnifiedRiskManager::CalculatePortfolioRiskAfterTrade(const double additionalRisk)
{
    return GetPortfolioRiskValue() + additionalRisk;
}

// Phase E1 forwarder -> CRiskValidationStats::LogValidationResult
void CUnifiedRiskManager::LogValidationResult(const STradeValidationRequest &request, const SValidationResult &result)
{
    m_validationStats.LogValidationResult(request.symbol,
                                          request.orderType,
                                          request.lotSize,
                                          result.approved,
                                          request.strategyRole,
                                          request.strategyCluster,
                                          request.clusterCode,
                                          result.riskPercent,
                                          result.portfolioRisk,
                                          result.correlationRisk,
                                          result.message);
}

double CUnifiedRiskManager::GetPortfolioRiskValue()
{
    return m_portfolioRiskManager.GetPortfolioRisk();
}

bool CUnifiedRiskManager::PortfolioAllowsTrade(const string symbolParam, const double lotSize)
{
    return m_portfolioRiskManager.IsTradeAllowed(symbolParam, lotSize);
}

// Phase E3 forwarder -> CRiskTieredCorrelation::PortfolioCorrelationAllowed
bool CUnifiedRiskManager::PortfolioCorrelationAllowed(const string symbolParam)
{
    return m_tieredCorrelation.PortfolioCorrelationAllowed(symbolParam);
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

// Phase E3 forwarder -> CRiskTieredCorrelation::CalculateSymbolCorrelation
double CUnifiedRiskManager::CalculateSymbolCorrelation(const string symbol1, const string symbol2)
{
    return m_tieredCorrelation.CalculateSymbolCorrelation(symbol1, symbol2);
}

// Phase E3 forwarder -> CRiskTieredCorrelation::GetMaxCorrelationWithPortfolio
double CUnifiedRiskManager::GetMaxCorrelationWithPortfolio(const string symbolParam)
{
    return m_tieredCorrelation.GetMaxCorrelationWithPortfolio(symbolParam);
}

// Phase E1 forwarder -> CRiskValidationStats::WriteAuditLog
void CUnifiedRiskManager::WriteAuditLog(const string message)
{
    m_validationStats.WriteAuditLog(message);
}

// Phase E1 forwarder -> CRiskValidationStats::FormatValidationMessage
string CUnifiedRiskManager::FormatValidationMessage(const STradeValidationRequest &request, const SValidationResult &result)
{
    return CRiskValidationStats::FormatValidationMessage(request.symbol,
                                                         request.orderType,
                                                         request.lotSize,
                                                         result.approved,
                                                         request.strategyRole,
                                                         request.strategyCluster,
                                                         request.clusterCode,
                                                         result.riskPercent,
                                                         result.portfolioRisk,
                                                         result.correlationRisk);
}

// Phase E1 forwarder -> CRiskValidationStats::UpdatePerformanceMetrics
void CUnifiedRiskManager::UpdatePerformanceMetrics(const ulong startTimeParam)
{
    m_validationStats.UpdatePerformanceMetrics(startTimeParam);
}

// Phase E1 forwarder -> CRiskClusterCodec::NormalizeClusterCode
string CUnifiedRiskManager::NormalizeClusterCode(const string clusterCode) const
{
    return CRiskClusterCodec::NormalizeClusterCode(clusterCode);
}

// Phase E1 forwarder -> CRiskClusterCodec::ParseClusterCodeFromComment
bool CUnifiedRiskManager::ParseClusterCodeFromComment(const string comment, string &clusterCode) const
{
    return CRiskClusterCodec::ParseClusterCodeFromComment(comment, clusterCode);
}

double CUnifiedRiskManager::EstimatePositionRiskPercent(const ulong ticket) const
{
    if(ticket == 0 || !PositionSelectByTicket(ticket)) {
        PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, 3350, __FUNCTION__);
        return 0.0;
    }
    
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

// Phase E2 forwarder -> CRiskClusterBudget::SetClusterRiskCap
void CUnifiedRiskManager::SetClusterRiskCap(const string clusterCode, const double capPercent)
{
    m_clusterBudget.SetClusterRiskCap(clusterCode, capPercent);
}

// Phase E2 forwarder -> CRiskOpposingConflictGuard::ClearOpposingConflictCache
void CUnifiedRiskManager::ClearOpposingConflictCache(const string symbol)
{
    m_opposingGuard.ClearOpposingConflictCache(symbol);
}

// Phase E1 forwarder -> CRiskValidationStats::GetStats
void CUnifiedRiskManager::GetValidationStats(int &total, int &approved, int &rejected, double &approvalRate)
{
    m_validationStats.GetStats(total, approved, rejected, approvalRate);
}

// Phase E1 forwarder -> CRiskValidationStats::Reset
void CUnifiedRiskManager::ResetStats(void)
{
    m_validationStats.Reset();
}

#endif // CORE_RISK_UNIFIED_RISK_MANAGER_MQH

