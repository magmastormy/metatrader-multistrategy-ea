// Single authoritative risk contract for the EA runtime
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
#include "RiskClusterCodec.mqh"
#include "RiskSymbolStats.mqh"
#include "RiskValidationStats.mqh"
#include "RiskClusterBudget.mqh"
#include "RiskOpposingConflictGuard.mqh"
#include "RiskCircuitBreaker.mqh"
#include "RiskMarginHealth.mqh"
#include "RiskTieredCorrelation.mqh"
#include "RiskAdaptiveTuner.mqh"
// Declares SUnifiedRiskConfig, STradeValidationRequest, IRiskPipelineHost and CRiskValidationPipeline: must stay included before their first use.
#include "RiskValidationPipeline.mqh"
#include <Trade/Trade.mqh>

struct SSymbolRiskBudget
{
    string   symbol;
    double   allocatedPct;     // allocated daily risk %
    double   usedPct;          // used daily risk %
    double   winRate;          // recent win rate
    double   profitFactor;     // recent profit factor
};

#define MAX_SYMBOL_BUDGETS 30

// All percent fields in this file use the 0-100 scale (5.0 = 5%), never 0-1 fractions.

// Allows per-symbol risk limits that are lower than global defaults
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

struct SUnifiedRiskSnapshot
{
    double activeRiskPerTradePercent;
    double dailyRiskUsedPercent;
    double dailyEntryRiskUsedPercent;
    double dailyMarkToMarketLossPercent;
    double openExposureRiskPercent;
    double virtualReservedRiskPercent;
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

// IRiskPipelineHost lets CRiskValidationPipeline call back into owner-private bookkeeping instead of duplicating it.
class CUnifiedRiskManager : public IRiskPipelineHost
{
private:
    SUnifiedRiskConfig m_config;
    CPortfolioRiskManager m_portfolioRiskManager;
    CVirtualPositionBook m_virtualPositionBook;
    // NON-OWNING: PerformanceAnalytics is created and owned by EAOrchestrator; referenced only.
    CPerformanceAnalytics* m_performanceAnalytics;

    double m_dailyRiskUsedPercent;
    double m_dailyStartEquity;
    datetime m_lastDailyReset;
    bool m_initialized;
    datetime m_lastPressureLogTime;
    
    CRiskCircuitBreaker m_circuitBreaker;

    int m_lastTradingDayKey;         // Cached trading day key (YYYYMMDD)
    int m_tradingDayStartHour;       // Hour when broker trading day starts (default 0 = midnight server time)

    SSymbolRiskBudget m_symbolBudgets[];
    int m_symbolBudgetCount;
    datetime m_lastBudgetRefresh;

    SSymbolRiskOverride m_riskOverrides[];
    int m_riskOverrideCount;

    long m_eaMagicNumber;  // Magic number used to filter positions for EA-owned accounting

    // Configured envelope captured once at Initialize; ApplyTierOverrides clamps tier values to it, so tiers may LOWER authorised risk but never raise it.
    double m_envelopeMaxRiskPerTradePercent;
    double m_envelopeBaseRiskPerTradePercent;
    double m_envelopeMaxDailyRiskPercent;
    double m_envelopeMaxPortfolioRiskPercent;
    double m_envelopeDrawdownWarningPercent;
    double m_envelopeDrawdownCriticalPercent;
    double m_envelopeDailyLossLimitPercent;
    int    m_envelopeMaxPositionsSameBase;
    bool   m_envelopeCaptured;

        CDerivAssetProfiler m_derivAssetProfiler;

    bool m_clusterGovernanceEnabled;
    bool m_clusterMutexEnabled;
    int m_maxConcurrentPerCluster;
    double m_maxClusterRiskPercent;
    CRiskMarginHealth m_marginHealth;
    CRiskOpposingConflictGuard m_opposingGuard;
    CRiskClusterBudget m_clusterBudget;
    string m_clusterSyncCodes[];
    int m_clusterSyncCounts[];
    CRiskValidationStats m_validationStats;
    CRiskTieredCorrelation m_tieredCorrelation;
    CRiskAdaptiveTuner m_adaptiveTuner;

    double m_emergencyRiskOverride;   // 0-100 scale (5.0 = 5%)

    // Declared last: it holds non-owning pointers to the members above, so WireValidationPipeline() needs their final addresses.
    CRiskValidationPipeline m_validationPipeline;

    // Called from the constructor body and again from Initialize(); idempotent.
    void WireValidationPipeline();

public:
    CUnifiedRiskManager();
    ~CUnifiedRiskManager();

    bool Initialize(const SUnifiedRiskConfig &config, CPerformanceAnalytics* performanceAnalytics = NULL);

    // Called each cycle/new bar to keep limits and adaptive risk current.
    void RefreshRuntimeState();
    virtual void CheckAndResetDailyLimits();

    void SetPerformanceAnalytics(CPerformanceAnalytics* analytics);

    // No caller in this repo: dual-mode auto-switching never wired to this setter.
    void SetBaseRiskPerTrade(double riskPercent);

    // Tier overrides applied in place (no reinit): only daily/portfolio risk, drawdown thresholds and daily-loss limit change; circuit breaker, daily risk used and virtual reservations keep state.
        void ApplyTierOverrides(double tierRiskPerTradePct,
                                int tierMaxPositions,
                                double effectiveDaily, double effectivePortfolio,
                                double effectiveDdWarning, double effectiveDdCritical,
                                double effectiveDailyLossLimit,
                                double maxRiskPerTradeOverride);

    void SetRiskPerTrade(const string symbol, double riskPct);
    void SetMaxDrawdownForFamily(const string symbol, double maxDDPct);
    virtual double GetEffectiveRiskPerTrade(const string symbol) const;
    virtual double GetEffectiveMaxDrawdown(const string symbol) const;

    // MQL5 has no pointers to structures, so the pipeline copies the live struct at every public entry point (read-only).
    virtual void CopyRiskConfig(SUnifiedRiskConfig &outConfig) const { outConfig = m_config; }

    // Public only so the pipeline reaches it through IRiskPipelineHost; no default argument - every call site passes one.
    virtual double GetEffectiveDailyRiskUsedPercent(const double additionalRiskPercent);

        SValidationResult ValidateTradeRequest(const STradeValidationRequest &request, const string phaseTag = "runtime", const string corrId = "");
        void ConfigureClusterGovernance(const bool enabled,
                                    const int maxConcurrentPerCluster,
                                    const double maxClusterRiskPercent,
                                    const bool enableMutex);

    // Sync inherited cluster position counts on EA restart
    void SyncClusterPositionCounts();
    virtual bool ReserveVirtualPosition(const string ownerTag,
                                        const STradeValidationRequest &request,
                                        const double riskPercent);
    virtual void ReleaseVirtualPosition(const string ownerTag);
    virtual void UpdateVirtualPositionRisk(const string ownerTag, const double riskPercent);
    // No caller in this repo. Reservations are released by each rejection branch in the pipeline; one approved but never executed lingers until its 60s TTL is pruned.
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
    // Throttle pressure written by GetRecommendedRiskPerTradePercent; no consumer of this accessor in this repo.
    double GetThrottlePressure() const;
    bool HasUnprotectedPositions();
    int GetUnprotectedPositionCount();
    virtual bool IsInitialized() const { return m_initialized; }

    // Access portfolio risk manager (for wiring correlation engine to PositionSizer)
    CPortfolioRiskManager* GetPortfolioRiskManager() { return &m_portfolioRiskManager; }

    // Trading-day roll hour (0 = server midnight). No caller sets this setter, so the day always rolls at midnight server time, not at the 17:00 forex rollover.
    void SetTradingDayStartHour(int hour) { m_tradingDayStartHour = MathMax(0, MathMin(23, hour)); }
    
    // Push-synced: the validation pipeline mirrors this scalar, so both copies stay equal.
    void SetEAMagicNumber(long magic)
    {
        m_eaMagicNumber = magic;
        m_validationPipeline.SetEAMagicNumber(magic);
    }
    
    virtual bool CheckDrawdownCircuitBreaker();
    double GetCurrentDrawdownPercent() const;
    bool IsTradingEnabled() const;
    bool IsEmergencyCloseRequested() const;
    void ResetEmergencyCloseRequested();
    void ResetCircuitBreaker();
    bool CheckCircuitBreakerRecovery();
    // Crash-recovery getters: the EAOrchestrator state writer persists these and RestoreCircuitBreakerState() feeds them back.
    double GetPeakEquity() const;
    double GetDailyStartEquity() const;
    int    GetDrawdownBreachCount() const;
    double GetMaxDrawdownFromPeak() const;
    // Halt flags are persisted and restored; the day key is exposed so the writer can stamp which broker day the restored state belongs to.
    bool   IsDailyLossHaltActive() const;
    int    GetCurrentTradingDayKey();
    // Seeding suppresses the spurious trading-day reset that would otherwise clobber the restored m_dailyStartEquity.
    void   SeedTradingDayKey(int dayKey);
    void   RestoreCircuitBreakerState(double savedPeakEquity, double savedDailyStartEquity,
                                      int savedBreachCount, double savedMaxDrawdown,
                                      bool restoreDailyLossHalt, bool restoreTradingHalt);

    // Realised daily P&L loss breaker; distinct from the drawdown circuit breaker.
    virtual bool CheckDailyLossLimit();

    virtual double GetSymbolRiskAllocation(const string symbol);
    virtual bool IsSymbolBudgetAvailable(const string symbol, const double riskPct);
    void RefreshSymbolBudgets();
    virtual double GetSymbolUsedRisk(const string symbol);
    double GetSymbolWinRate(const string symbol);
    double GetSymbolProfitFactor(const string symbol);

    ENUM_MARGIN_HEALTH_LEVEL MonitorMarginHealth();

    virtual SDrawdownState GetDrawdownState();
    
    double GetSymbolCorrelation(const string symbol1, const string symbol2);
    double CalculatePositionRiskPercent(ulong ticket);

    bool ValidateBasicParameters(const STradeValidationRequest &request, string &message);
    bool ValidateRiskLimits(const STradeValidationRequest &request, string &message, double &riskPercent);
    bool ValidatePortfolioRisk(const STradeValidationRequest &request, const double tradeRiskPercent, string &message);
    bool ValidateCorrelationLimits(const STradeValidationRequest &request, string &message, double &correlationRisk);
    bool ValidateMarginRequirements(const STradeValidationRequest &request, string &message);
    bool ValidateAccountHealth(const STradeValidationRequest &request, string &message);
    bool ValidateClusterGovernance(const STradeValidationRequest &request, const double tradeRiskPercent, string &message);
    virtual double CalculateTradeRisk(const string symbolParam, const double lotSize, const double stopLossPips) const;
    double CalculateCorrelationRisk(const string symbolParam);
    virtual double CalculatePortfolioRiskAfterTrade(const double additionalRisk);
    double GetPortfolioRiskValue();
    bool PortfolioAllowsTrade(const string symbolParam, const double lotSize);
    bool PortfolioCorrelationAllowed(const string symbolParam);
    bool PortfolioEmergencyActive();
    bool PortfolioHasUnprotectedPositions();
    virtual bool IsSymbolDataValid(const string symbolParam);
    double GetSymbolTickValue(const string symbolParam);
    double GetSymbolPoint(const string symbolParam);
    virtual bool CheckAccountTradingPermissions(void);
    double CalculateSymbolCorrelation(const string symbol1Param, const string symbol2Param);
    double GetMaxCorrelationWithPortfolio(const string symbolParam);
    string NormalizeClusterCode(const string clusterCode) const;
    bool ParseClusterCodeFromComment(const string comment, string &clusterCode) const;
    virtual double EstimatePositionRiskPercent(const ulong ticket) const;
    virtual void LogValidationResult(const STradeValidationRequest &request, const SValidationResult &result);
    void WriteAuditLog(const string message);
    string FormatValidationMessage(const STradeValidationRequest &request, const SValidationResult &result);
    virtual void UpdatePerformanceMetrics(const ulong startTime);
    double GetCurrentPortfolioRisk();

    void ClearOpposingConflictCache(const string symbol);
    void GetValidationStats(int &total, int &approved, int &rejected, double &approvalRate);
    void ResetStats(void);

private:
    void UpdateAdaptiveRiskLevel();
    int TradingDayKey(const datetime nowTime) const;
    bool IsNewTradingDay(const datetime nowTime);
    double ClampRiskPercent(const double value) const;
    double CalculateDailyMarkToMarketLossPercent();
    double GetCurrentOpenExposureRiskPercent();
    double CalculateMinLotRiskPercent(const string symbol);
    double ApplyPnlRiskAdjustment(const string symbol, const double rawUsedRisk);
};

void CUnifiedRiskManager::SetPerformanceAnalytics(CPerformanceAnalytics* analytics)
{
    m_performanceAnalytics = analytics;
    if(analytics != NULL)
        Print("[RISK-UNIFIED] Performance analytics linked");
}

void CUnifiedRiskManager::SetBaseRiskPerTrade(double riskPercent)
{
    m_config.baseRiskPerTradePercent = ClampRiskPercent(riskPercent);
    m_adaptiveTuner.SetActiveRiskPerTradePercent(ClampRiskPercent(riskPercent));
}

void CUnifiedRiskManager::ApplyTierOverrides(double tierRiskPerTradePct,
                                             int tierMaxPositions,
                                             double effectiveDaily, double effectivePortfolio,
                                             double effectiveDdWarning, double effectiveDdCritical,
                                             double effectiveDailyLossLimit,
                                             double maxRiskPerTradeOverride)
{
    // Every tier value is clamped to the operator's envelope: lowering risk is allowed, raising it past what was configured is not.
    double clampedBaseRisk   = m_envelopeCaptured ? MathMin(tierRiskPerTradePct, m_envelopeBaseRiskPerTradePercent) : tierRiskPerTradePct;
    double clampedMaxRisk    = m_envelopeCaptured ? MathMin(maxRiskPerTradeOverride, m_envelopeMaxRiskPerTradePercent) : maxRiskPerTradeOverride;
    double clampedDaily      = m_envelopeCaptured ? MathMin(effectiveDaily, m_envelopeMaxDailyRiskPercent) : effectiveDaily;
    double clampedPortfolio  = m_envelopeCaptured ? MathMin(effectivePortfolio, m_envelopeMaxPortfolioRiskPercent) : effectivePortfolio;
    double clampedDdWarning  = m_envelopeCaptured ? MathMin(effectiveDdWarning, m_envelopeDrawdownWarningPercent) : effectiveDdWarning;
    double clampedDdCritical = m_envelopeCaptured ? MathMin(effectiveDdCritical, m_envelopeDrawdownCriticalPercent) : effectiveDdCritical;
    double clampedDailyLoss  = m_envelopeCaptured ? MathMin(effectiveDailyLossLimit, m_envelopeDailyLossLimitPercent) : effectiveDailyLossLimit;
    int    clampedSameBase   = (m_envelopeCaptured && m_envelopeMaxPositionsSameBase > 0)
                               ? MathMin(tierMaxPositions, m_envelopeMaxPositionsSameBase) : tierMaxPositions;

    // Clamping can invert the warning/critical pair; restore the same +4 relationship Initialize uses.
    if(clampedDdCritical <= clampedDdWarning)
        clampedDdCritical = clampedDdWarning + 4.0;

    // Base risk must never exceed the per-trade cap after clamping.
    if(clampedBaseRisk > clampedMaxRisk)
        clampedBaseRisk = clampedMaxRisk;

    if(clampedBaseRisk < tierRiskPerTradePct || clampedMaxRisk < maxRiskPerTradeOverride ||
       clampedDaily < effectiveDaily || clampedPortfolio < effectivePortfolio ||
       clampedDdWarning < effectiveDdWarning || clampedDdCritical < effectiveDdCritical ||
       clampedDailyLoss < effectiveDailyLossLimit ||
       clampedSameBase < tierMaxPositions)
    {
        PrintFormat("[RISK-ENVELOPE] Tier %s values clamped to configured ceiling | risk %.2f%%->%.2f%% max %.2f%%->%.2f%% daily %.2f%%->%.2f%% portfolio %.2f%%->%.2f%% ddWarn %.2f%%->%.2f%% ddCrit %.2f%%->%.2f%% dailyLoss %.2f%%->%.2f%% sameBase %d->%d",
                    "COMPOUNDING", tierRiskPerTradePct, clampedBaseRisk,
                    maxRiskPerTradeOverride, clampedMaxRisk, effectiveDaily, clampedDaily,
                    effectivePortfolio, clampedPortfolio, effectiveDdWarning, clampedDdWarning,
                    effectiveDdCritical, clampedDdCritical,
                    effectiveDailyLossLimit, clampedDailyLoss, tierMaxPositions, clampedSameBase);
    }

    m_config.baseRiskPerTradePercent = clampedBaseRisk;
    m_config.maxRiskPerTradePercent  = clampedMaxRisk;
    m_config.maxDailyRiskPercent     = clampedDaily;
    m_config.maxPortfolioRiskPercent = clampedPortfolio;
    m_config.drawdownWarningPercent  = clampedDdWarning;
    m_config.drawdownCriticalPercent = clampedDdCritical;
    m_config.dailyLossLimitPercent   = clampedDailyLoss;
    m_config.maxPositionsSameBase    = clampedSameBase;

        m_adaptiveTuner.SetActiveRiskPerTradePercent(ClampRiskPercent(m_config.baseRiskPerTradePercent));

        m_portfolioRiskManager.SetMaxPortfolioRisk(clampedPortfolio);

        PrintFormat("[RISK-INIT-SINGLE] Tier overrides applied (no reinit) | risk=%.1f%% | maxRisk=%.1f%% | daily=%.1f%% | portfolio=%.1f%% | ddWarn=%.1f%% | ddCrit=%.1f%%",
                    m_config.baseRiskPerTradePercent,
                    m_config.maxRiskPerTradePercent,
                    m_config.maxDailyRiskPercent,
                    m_config.maxPortfolioRiskPercent,
                    m_config.drawdownWarningPercent,
                    m_config.drawdownCriticalPercent);
}

void CUnifiedRiskManager::SetRiskPerTrade(const string symbol, double riskPct)
{
    for(int i = 0; i < m_riskOverrideCount; i++)
    {
        if(m_riskOverrides[i].symbol == symbol)
        {
            m_riskOverrides[i].riskPerTradePercent = riskPct;
            m_riskOverrides[i].hasOverrides = true;
            return;
        }
    }
    // Struct arrays with string members must be copied through a temp array before resizing.
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

// Returns the LOWER of family-specific and global max limit
double CUnifiedRiskManager::GetEffectiveRiskPerTrade(const string symbol) const
{
    for(int i = 0; i < m_riskOverrideCount; i++)
    {
        if(m_riskOverrides[i].symbol == symbol && m_riskOverrides[i].hasOverrides && m_riskOverrides[i].riskPerTradePercent > 0.0)
            return MathMin(m_riskOverrides[i].riskPerTradePercent, m_config.maxRiskPerTradePercent);
    }
    // Falls back to the ACTIVE risk per trade, already reduced by conservative mode.
    return m_adaptiveTuner.GetActiveRiskPerTradePercent();
}

// Returns the LOWER of family-specific and global critical limit
double CUnifiedRiskManager::GetEffectiveMaxDrawdown(const string symbol) const
{
    for(int i = 0; i < m_riskOverrideCount; i++)
    {
        if(m_riskOverrides[i].symbol == symbol && m_riskOverrides[i].hasOverrides && m_riskOverrides[i].maxDrawdownPercent > 0.0)
            return MathMin(m_riskOverrides[i].maxDrawdownPercent, m_config.drawdownCriticalPercent);
    }
    return m_config.drawdownCriticalPercent;
}

CUnifiedRiskManager::CUnifiedRiskManager() :
    m_performanceAnalytics(NULL),
    m_dailyRiskUsedPercent(0.0),
    m_dailyStartEquity(0.0),
    m_lastDailyReset(0),
    m_initialized(false),
    m_lastPressureLogTime(0),
    m_lastTradingDayKey(0),
    m_tradingDayStartHour(0),
    m_symbolBudgetCount(0),
    m_lastBudgetRefresh(0),
    m_riskOverrideCount(0),
    m_eaMagicNumber(0),
    m_envelopeMaxRiskPerTradePercent(0.0),
    m_envelopeBaseRiskPerTradePercent(0.0),
    m_envelopeMaxDailyRiskPercent(0.0),
    m_envelopeMaxPortfolioRiskPercent(0.0),
    m_envelopeDrawdownWarningPercent(0.0),
    m_envelopeDrawdownCriticalPercent(0.0),
    m_envelopeDailyLossLimitPercent(0.0),
    m_envelopeMaxPositionsSameBase(0),
    m_envelopeCaptured(false),
    m_clusterGovernanceEnabled(true),
    m_clusterMutexEnabled(true),
    m_maxConcurrentPerCluster(5),
    m_maxClusterRiskPercent(5.0),
    m_emergencyRiskOverride(5.0)
{
    m_config.baseRiskPerTradePercent = 1.0;
    m_config.minRiskPerTradePercent = 0.1;
    m_config.maxRiskPerTradePercent = 5.0;
    m_config.maxDailyRiskPercent = 5.0;
    m_config.maxPortfolioRiskPercent = 15.0;  // 0-100 scale
    m_config.correlationThreshold = 0.7;
    m_config.correlationReduceThreshold = 0.4;
    m_config.correlationBlockThreshold = 0.7;
    m_config.maxPositionsSameBase = 3;
    m_config.drawdownWarningPercent = 17.5;   // 70% of the 25% max
    m_config.drawdownCriticalPercent = 25.0;  // matches input InpMaxDrawdown
    m_config.dailyLossLimitPercent = 15.0;    // sized for small accounts, where one trade can be ~10%
    m_config.minLotRiskMultiplier = 15.0;     // tolerates a min-lot round-up of up to 15x intended risk
    m_config.adaptationMinTrades = 20;
    m_config.enableAdaptiveSizing = true;
    m_config.enableAuditLogging = true;
    m_config.auditLogFile = "UnifiedRiskValidation.log";

    // CRiskTieredCorrelation keeps its own copy of the entry threshold; the portfolio-manager pointer stays
    // valid for URM's lifetime. The reduce/block tiers are enforced by the pipeline from its config copy.
    m_tieredCorrelation.SetThresholds(m_config.correlationThreshold);
    m_tieredCorrelation.SetPortfolioRiskManager(&m_portfolioRiskManager);

    // Wired here, not in Initialize(), so ValidateTradeRequest can never dereference a NULL collaborator.
    WireValidationPipeline();
}

// Every pointer handed over is NON-OWNING and stable for this object's lifetime, so re-running is idempotent; mirrored scalars are push-synced from the setters.
void CUnifiedRiskManager::WireValidationPipeline()
{
    m_validationPipeline.Initialize(GetPointer(this),
                                    GetPointer(m_circuitBreaker),
                                    GetPointer(m_virtualPositionBook),
                                    GetPointer(m_portfolioRiskManager),
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

CUnifiedRiskManager::~CUnifiedRiskManager()
{
    // No manual cleanup: this class owns no raw pointers (m_performanceAnalytics is NON-OWNING, owned by EAOrchestrator).
}

bool CUnifiedRiskManager::Initialize(const SUnifiedRiskConfig &config,
                                     CPerformanceAnalytics* perfAnalytics)
{
    m_config = config;
    // NON-OWNING: EAOrchestrator holds it as a value member (EAOrchestrator.mqh m_performanceAnalytics) and passes its pointer here; used only for metrics queries.
    m_performanceAnalytics = perfAnalytics;

    if(m_config.maxRiskPerTradePercent <= 0.0)
        m_config.maxRiskPerTradePercent = 5.0;
    // Hard ceiling of 50%/trade, the same value as MAX_RISK_PER_TRADE (Core/Utils/Enums.mqh); EAOrchestrator's configured max is already capped at 25%.
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

    // Snapshot the operator envelope after the clamps above and before any tier can overwrite it; captured once because ApplyTierOverrides mutates m_config in place, so re-snapshotting would let the ceiling drift.
    if(!m_envelopeCaptured)
    {
        m_envelopeMaxRiskPerTradePercent   = m_config.maxRiskPerTradePercent;
        m_envelopeBaseRiskPerTradePercent  = m_config.baseRiskPerTradePercent;
        m_envelopeMaxDailyRiskPercent      = m_config.maxDailyRiskPercent;
        m_envelopeMaxPortfolioRiskPercent  = m_config.maxPortfolioRiskPercent;
        m_envelopeDrawdownWarningPercent   = m_config.drawdownWarningPercent;
        m_envelopeDrawdownCriticalPercent  = m_config.drawdownCriticalPercent;
        m_envelopeDailyLossLimitPercent    = m_config.dailyLossLimitPercent;
        m_envelopeMaxPositionsSameBase     = m_config.maxPositionsSameBase;
        m_envelopeCaptured = true;
        PrintFormat("[RISK-ENVELOPE] Operator ceiling captured | risk/trade<=%.2f%% daily<=%.2f%% portfolio<=%.2f%% ddWarn<=%.2f%% ddCrit<=%.2f%% dailyLoss<=%.2f%% sameBase<=%d",
                    m_envelopeMaxRiskPerTradePercent, m_envelopeMaxDailyRiskPercent,
                    m_envelopeMaxPortfolioRiskPercent, m_envelopeDrawdownWarningPercent,
                    m_envelopeDrawdownCriticalPercent, m_envelopeDailyLossLimitPercent,
                    m_envelopeMaxPositionsSameBase);
    }

    // Re-synced after clamping so CRiskTieredCorrelation never sees an unclamped threshold.
    m_tieredCorrelation.SetThresholds(m_config.correlationThreshold);

    if(!m_portfolioRiskManager.Initialize(m_config.maxPortfolioRiskPercent, m_config.correlationThreshold))
    {
        Print("[RISK-UNIFIED] Failed to initialize portfolio risk manager");
        return false;
    }

    m_eaMagicNumber = 0;
    m_adaptiveTuner.SetActiveRiskPerTradePercent(ClampRiskPercent(m_config.baseRiskPerTradePercent));
    m_dailyRiskUsedPercent = 0.0;
    m_virtualPositionBook.Clear();
    m_dailyStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(m_dailyStartEquity <= 0.0)
        m_dailyStartEquity = AccountInfoDouble(ACCOUNT_BALANCE);
    
    // InitializeState also re-arms the daily P&L loss-limit breaker.
    m_circuitBreaker.InitializeState(m_dailyStartEquity);

    m_lastTradingDayKey = 0;

    m_lastDailyReset = TimeCurrent();
    m_initialized = true;

    // Re-wire so the pipeline picks up the freshly clamped config and the reset m_eaMagicNumber (same stable addresses).
    WireValidationPipeline();

    // Scale guard: active risk must land in [0.01, 20.0] %, i.e. inputs are 0-100 not 0-1.
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

void CUnifiedRiskManager::RefreshRuntimeState()
{
    if(!m_initialized)
        return;

    // Keeps the circuit breaker's peak-equity / drawdown-from-peak reading current.
    m_circuitBreaker.RefreshPeakAndDrawdown();

    // Feeds the CVaR equity sampler (minute-gated inside) so IsCVaRLimitExceeded and GetCurrentCVaR work on real data.
    m_portfolioRiskManager.UpdateEquityCurve();

    CheckAndResetDailyLimits();
    UpdateAdaptiveRiskLevel();
    CheckCircuitBreakerRecovery();

    // Breakers must arm with no candidate in flight, so they run on every cycle here as well as inside the pipeline.
    CheckDrawdownCircuitBreaker();
    CheckDailyLossLimit();
}

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

        m_circuitBreaker.ResetRecoveryCounterForNewDay();

        Print("[RISK-UNIFIED] Daily risk usage reset");
    }
}

// The one entry authority: thin forwarder, every pre-trade gate is evaluated inside CRiskValidationPipeline::Run.
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

    // Push the (already clamped) values into the pipeline, which mirrors these scalars for ValidateClusterGovernance.
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
    // Diagnostic output only: the pipeline's ValidateClusterGovernance re-counts positions from the terminal, so these arrays gate nothing.
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

// Re-syncs an early reservation's risk with the validated one: lot-floor and correlation-reduce adjustments land only after Reserve.
void CUnifiedRiskManager::UpdateVirtualPositionRisk(const string ownerTag, const double riskPercent)
{
    if(m_virtualPositionBook.UpdateRisk(ownerTag, riskPercent))
    {
        PrintFormat("[RISK-VIRTUAL] update | owner=%s | risk=%.2f", ownerTag, riskPercent);
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

void CUnifiedRiskManager::RegisterExecutedTradeRisk(const SValidationResult &validationResult, const double fillRatio)
{
    if(!m_initialized)
        return;

    CheckAndResetDailyLimits();

    double riskUsed = validationResult.riskPercent;
    if(riskUsed <= 0.0)
        riskUsed = m_adaptiveTuner.GetActiveRiskPerTradePercent();
    double normalizedFillRatio = MathMax(0.0, MathMin(1.0, fillRatio));
    m_dailyRiskUsedPercent += MathMax(0.0, riskUsed * normalizedFillRatio);
}

double CUnifiedRiskManager::GetRemainingDailyRiskPercent()
{
    double remaining = m_config.maxDailyRiskPercent - GetEffectiveDailyRiskUsedPercent(GetReservedVirtualRiskPercent());
    if(remaining < 0.0) {
        return 0.0;
    }
    return remaining;
}

double CUnifiedRiskManager::GetRecommendedRiskPerTradePercent(const double requestedRiskPercent)
{
    if(!m_initialized) {
        return 0.0;
    }

    CheckAndResetDailyLimits();

    if(m_portfolioRiskManager.IsEmergencyMode() || HasUnprotectedPositions()) {
        return 0.0;
    }

    // Single-threaded EA, so tuner state can be read straight into locals.
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

    m_adaptiveTuner.SetThrottlePressure(pressureMultiplier);

    recommended *= pressureMultiplier;
    recommended = MathMin(recommended, remainingDailyRisk);
    recommended = MathMin(recommended, remainingPortfolioRisk);

    if(recommended <= 0.0) {
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

double CUnifiedRiskManager::GetThrottlePressure() const
{
    return m_adaptiveTuner.GetThrottlePressure();
}

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

double CUnifiedRiskManager::CalculateDailyMarkToMarketLossPercent()
{
    double baselineEquity = m_dailyStartEquity;
    if(baselineEquity <= 0.0)
        baselineEquity = AccountInfoDouble(ACCOUNT_BALANCE);

    if(baselineEquity <= 0.0) {
        return 0.0;
    }

    double equityNow = AccountInfoDouble(ACCOUNT_EQUITY);
    return MathMax(0.0, ((baselineEquity - equityNow) / baselineEquity) * 100.0);  // fraction -> 0-100 % scale
}

double CUnifiedRiskManager::GetCurrentOpenExposureRiskPercent()
{
    return m_portfolioRiskManager.GetPortfolioRisk();
}

// Daily risk consumption: the worst of entry budget, mark-to-market loss and open exposure.
double CUnifiedRiskManager::GetEffectiveDailyRiskUsedPercent(const double additionalRiskPercent)
{
    double additionalRisk = MathMax(0.0, additionalRiskPercent);
    double effective = MathMax(0.0, m_dailyRiskUsedPercent + additionalRisk);
    effective = MathMax(effective, CalculateDailyMarkToMarketLossPercent());
    effective = MathMax(effective, GetCurrentOpenExposureRiskPercent() + additionalRisk);
    // Capped at the daily limit so MTM P&L plus entry exposure cannot stack to 2x the limit before blocking.
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

int CUnifiedRiskManager::TradingDayKey(const datetime nowTime) const
{
    MqlDateTime dt;
    TimeToStruct(nowTime, dt);

    // Before the trading-day start hour the position still belongs to the previous broker day.
    if(dt.hour < m_tradingDayStartHour)
        TimeToStruct(nowTime - 86400, dt);

    return dt.year * 10000 + dt.mon * 100 + dt.day;
}

bool CUnifiedRiskManager::IsNewTradingDay(const datetime nowTime)
{
    int currentTradingDayKey = TradingDayKey(nowTime);

    if(currentTradingDayKey != m_lastTradingDayKey)
    {
        m_lastTradingDayKey = currentTradingDayKey;
        return true;
    }
    return false;
}

double CUnifiedRiskManager::ClampRiskPercent(const double value) const
{
    return MathMax(m_config.minRiskPerTradePercent,
                   MathMin(m_config.maxRiskPerTradePercent, value));
}

// true = trading allowed; false = drawdown breaker at/over the critical level, and false when the manager is not initialised (fail-closed).
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

double CUnifiedRiskManager::GetCurrentDrawdownPercent() const
{
    return m_circuitBreaker.GetMaxDrawdownFromPeak();
}

bool CUnifiedRiskManager::IsTradingEnabled() const
{
    return m_circuitBreaker.IsTradingEnabled();
}

// Flatten flag raised by the breaker (2nd+ breach or drawdown >= 2x critical); EAOrchestrator's close-all paths consume it.
bool CUnifiedRiskManager::IsEmergencyCloseRequested() const
{
    return m_circuitBreaker.IsEmergencyCloseRequested();
}

// Called after the emergency close has been executed.
void CUnifiedRiskManager::ResetEmergencyCloseRequested()
{
    m_circuitBreaker.ResetEmergencyCloseRequested();
}

// Manual breaker reset; no caller in this repo, so nothing in the runtime can clear a halt.
void CUnifiedRiskManager::ResetCircuitBreaker()
{
    bool conservative = m_adaptiveTuner.IsConservativeMode();
    m_circuitBreaker.ResetCircuitBreaker(conservative);
    m_adaptiveTuner.SetConservativeMode(conservative);
}

double CUnifiedRiskManager::GetPeakEquity() const
{
    return m_circuitBreaker.GetPeakEquity();
}

double CUnifiedRiskManager::GetDailyStartEquity() const
{
    return m_dailyStartEquity;
}

int CUnifiedRiskManager::GetDrawdownBreachCount() const
{
    return m_circuitBreaker.GetDrawdownBreachCount();
}

double CUnifiedRiskManager::GetMaxDrawdownFromPeak() const
{
    return m_circuitBreaker.GetMaxDrawdownFromPeak();
}

// Restore circuit breaker state from crash recovery file
void CUnifiedRiskManager::RestoreCircuitBreakerState(double savedPeakEquity, double savedDailyStartEquity,
                                                     int savedBreachCount, double savedMaxDrawdown,
                                                     bool restoreDailyLossHalt, bool restoreTradingHalt)
{
    m_circuitBreaker.RestoreCircuitBreakerState(savedPeakEquity, savedDailyStartEquity,
                                                savedBreachCount, savedMaxDrawdown,
                                                restoreDailyLossHalt, restoreTradingHalt,
                                                m_dailyStartEquity);
}

bool CUnifiedRiskManager::IsDailyLossHaltActive() const
{
    return m_circuitBreaker.IsDailyLossHaltActive();
}

// Pure read: never advances m_lastTradingDayKey, so the periodic state writer can call it without stealing the daily reset.
int CUnifiedRiskManager::GetCurrentTradingDayKey()
{
    return TradingDayKey(TimeCurrent());
}

void CUnifiedRiskManager::SeedTradingDayKey(int dayKey)
{
    if(dayKey <= 0)
        return;
    m_lastTradingDayKey = dayKey;
    PrintFormat("[RISK-UNIFIED] Trading day key seeded to %d - suppresses the spurious daily reset on restart", dayKey);
}

double CUnifiedRiskManager::GetSymbolCorrelation(const string symbol1, const string symbol2)
{
    return m_tieredCorrelation.GetSymbolCorrelation(symbol1, symbol2);
}

// Single source of truth for drawdown state; refreshes the breaker first so its readings are current.
SDrawdownState CUnifiedRiskManager::GetDrawdownState()
{
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

double CUnifiedRiskManager::CalculatePositionRiskPercent(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) {
        return 0.0;
    }
    
    double volume = PositionGetDouble(POSITION_VOLUME);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double sl = PositionGetDouble(POSITION_SL);
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    
    // MT5 quirk: closed/closing positions still pass PositionSelectByTicket but report zero volume or zero SL; skipping them avoids phantom risk.
    if(volume <= 0.0 || sl == 0.0 || openPrice == 0.0) {
        return 0.0;
    }
    
    string symbol = PositionGetString(POSITION_SYMBOL);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

    if(point <= 0.0 || tickValue <= 0.0) {
        return 0.0;
    }

    // MTM SL distance (current price -> SL), so the budget tracks live exposure rather than the distance at entry.
    double slDistance = MathAbs(currentPrice - sl) / point;
    // Units: slDistance is in POINTS (SYMBOL_POINT) while tickValue is per TICK; those coincide only when tickSize == point, so unscaled index/metal risk is understated.
    double ticksPerPoint = (tickSize > 0.0) ? (point / tickSize) : 1.0;
    double riskAmount = volume * slDistance * tickValue * ticksPerPoint;
    
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity <= 0.0) {
        return 0.0;
    }
    
    return (riskAmount / equity) * 100.0;  // fraction -> 0-100 % scale
}

// Recovery cooldown counts bars (iBarShift), not wall-clock minutes; wall clock is used only when the bar shift fails.
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

ENUM_MARGIN_HEALTH_LEVEL CUnifiedRiskManager::MonitorMarginHealth()
{
    if(!m_initialized)
        return MARGIN_HEALTH_OK;

    bool conservative = m_adaptiveTuner.IsConservativeMode();
    ENUM_MARGIN_HEALTH_LEVEL level = m_marginHealth.MonitorMarginHealth(m_circuitBreaker, conservative);
    m_adaptiveTuner.SetConservativeMode(conservative);
    return level;
}

// Daily-loss breaker: halts all trading once realised + floating loss (live deals and positions, magic-scoped) exceeds dailyLossLimitPercent of the day's starting equity; the halt latches until the trading-day key changes.
bool CUnifiedRiskManager::CheckDailyLossLimit()
{
    if(!m_initialized)
        return false;

    datetime nowTime = TimeCurrent();

    // TradingDayKey() is a pure read here: CheckAndResetDailyLimits() owns the one-shot daily budget reset and must see the day change first.
    if(m_circuitBreaker.IsDailyLossHaltActive()
       && TradingDayKey(nowTime) != m_lastTradingDayKey)
        m_circuitBreaker.ResetDailyLossHalt();

    return m_circuitBreaker.EvaluateDailyLossLimit(nowTime,
                                                   m_config.dailyLossLimitPercent,
                                                   m_dailyStartEquity);
}

// Splits maxDailyRiskPercent equally over symbols with open positions, then weights it: 1.5x if winRate>55% and PF>1.3, 0.5x if winRate<40% or PF<0.8.
double CUnifiedRiskManager::GetSymbolRiskAllocation(const string symbol)
{
    string activeSymbols[];
    int activeSymbolCount = 0;

    int totalPositions = PositionsTotal();
    for(int i = 0; i < totalPositions; i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        string posSymbol = PositionGetString(POSITION_SYMBOL);

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

    double winRate = GetSymbolWinRate(symbol);
    double profitFactor = GetSymbolProfitFactor(symbol);

    double perfWeight = 1.0;
    if(winRate > 55.0 && profitFactor > 1.3)
        perfWeight = 1.5;
    else if(winRate < 40.0 || profitFactor < 0.8)
        perfWeight = 0.5;

    double allocation = baseShare * perfWeight;

    // Floor at the minimum-lot trade's risk, otherwise a small allocation can never open even one position.
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

bool CUnifiedRiskManager::IsSymbolBudgetAvailable(const string symbol, const double riskPct)
{
    double allocation = GetSymbolRiskAllocation(symbol);
    double used = GetSymbolUsedRisk(symbol);
    return ((used + riskPct) <= allocation);
}

void CUnifiedRiskManager::RefreshSymbolBudgets()
{
    datetime now = TimeCurrent();
    if(m_lastBudgetRefresh > 0 && (now - m_lastBudgetRefresh) < 60)
        return;
    m_lastBudgetRefresh = now;

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

        // Phantom risk: a closed/closing position still in the terminal contributes zero risk.
        if(posRisk <= 0.0)
        {
            double vol = PositionGetDouble(POSITION_VOLUME);
            double slCheck = PositionGetDouble(POSITION_SL);
            if(vol > 0.0 && slCheck > 0.0)
            {
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

    for(int j = 0; j < m_symbolBudgetCount; j++)
    {
        m_symbolBudgets[j].allocatedPct = GetSymbolRiskAllocation(m_symbolBudgets[j].symbol);
    }
}

// Profitable positions reduce used risk via unrealized P&L credit
double CUnifiedRiskManager::GetSymbolUsedRisk(const string symbol)
{
    RefreshSymbolBudgets();

    for(int i = 0; i < m_symbolBudgetCount; i++)
    {
        if(m_symbolBudgets[i].symbol == symbol)
        {
            double rawUsedRisk = m_symbolBudgets[i].usedPct;
            double adjustedUsedRisk = ApplyPnlRiskAdjustment(symbol, rawUsedRisk);
            return adjustedUsedRisk;
        }
    }

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

double CUnifiedRiskManager::GetSymbolWinRate(const string symbol)
{
    return CRiskSymbolStats::GetWinRate(symbol);
}

double CUnifiedRiskManager::GetSymbolProfitFactor(const string symbol)
{
    return CRiskSymbolStats::GetProfitFactor(symbol);
}

double CUnifiedRiskManager::CalculateMinLotRiskPercent(const string symbol)
{
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    if(minLot <= 0.0)
        minLot = 0.01;

    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity <= 0.0)
        equity = AccountInfoDouble(ACCOUNT_BALANCE);
    if(equity <= 0.0) {
        return 0.0;
    }

    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    if(point <= 0.0 || tickValue <= 0.0 || tickSize <= 0.0) {
        return 0.0;
    }

    // SL distance proxy = ATR(14) on PERIOD_D1; the handle must come from CIndicatorManager, whose registry owns it - a statically cached handle is invalidated and crashes.
    double slDistancePoints = 0.0;
    CIndicatorManager* indManager = CIndicatorManager::Instance();
    if(indManager != NULL)
    {
        int atrHandle = indManager.GetATRHandle(symbol, PERIOD_D1, 14);
        if(atrHandle != INVALID_HANDLE)
        {
            double atrValues[];
            ArraySetAsSeries(atrValues, true);
            if(CopyBuffer(atrHandle, 0, 0, 1, atrValues) == 1 && atrValues[0] > 0.0)
                slDistancePoints = atrValues[0] / point;
        }
    }

    // Fallback if ATR is unavailable: 100 POINTS (slDistancePoints unit), not pips.
    if(slDistancePoints <= 0.0)
        slDistancePoints = 100.0;

    double riskAmount = minLot * slDistancePoints * tickValue * (point / tickSize);
    return (riskAmount / equity) * 100.0;  // fraction -> 0-100 % scale
}

// Formula: adjustedUsedRisk = rawUsedRisk - Max(0, profit * factor)
double CUnifiedRiskManager::ApplyPnlRiskAdjustment(const string symbol, const double rawUsedRisk)
{
    double riskReductionFactor = m_adaptiveTuner.GetRiskReductionFactor();
    if(rawUsedRisk <= 0.0 || riskReductionFactor <= 0.0)
        return MathMax(0.0, rawUsedRisk);

    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(equity <= 0.0)
        return MathMax(0.0, rawUsedRisk);

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

    double profitRiskPct = (unrealizedProfit / equity) * 100.0;  // fraction -> 0-100 % scale
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

// Public-API forwarders into CRiskValidationPipeline. No recursion: the pipeline reaches owner-side helpers (IsSymbolDataValid, CalculateTradeRisk, EstimatePositionRiskPercent, GetDrawdownState, ...) through IRiskPipelineHost, not through these.
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

// The pipeline supplies maxPositionsSameBase and eaMagicNumber to the tiered-correlation gate because both change at runtime (ApplyTierOverrides / SetEAMagicNumber).
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
    if(symbolParam == "" || stopLossPips <= 0 || lotSize <= 0) {
        return 0.0;
    }

    double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
    if(point <= 0) {
        return 0.0;
    }

    double dist = stopLossPips * point;  // price distance of the stop

    // Authoritative risk = the broker's own P/L for closing at the stop; the tickValue/tickSize/point chain below UNDERSTATES some symbols (e.g. Volatility 75), which would let oversized trades through the re-gate.
    double ask = SymbolInfoDouble(symbolParam, SYMBOL_ASK);
    double bid = SymbolInfoDouble(symbolParam, SYMBOL_BID);
    double risk = 0.0;
    double p = 0.0;
    // BUY stopped at ask-dist, SELL stopped at bid+dist; risk is the loss magnitude.
    if(OrderCalcProfit(ORDER_TYPE_BUY, symbolParam, lotSize, ask, ask - dist, p) && p < 0.0)
        risk = -p;
    if(OrderCalcProfit(ORDER_TYPE_SELL, symbolParam, lotSize, bid, bid + dist, p) && p < 0.0)
        risk = MathMax(risk, -p);

    if(risk > 0.0)
        return risk;

    // Fallback manual math when OrderCalcProfit fails; returns 0.0 if tickSize/tickValue are missing, which charges no risk.
    double tickValue = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_VALUE);
    double tickSize  = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_SIZE);
    if(tickValue <= 0 || tickSize <= 0)
        return 0.0;
    double stopLossPrice = dist;
    double riskPerLot = (stopLossPrice / tickSize) * tickValue;
    return lotSize * riskPerLot;
}

double CUnifiedRiskManager::CalculateCorrelationRisk(const string symbolParam)
{
    return m_tieredCorrelation.CalculateCorrelationRisk(symbolParam);
}

double CUnifiedRiskManager::CalculatePortfolioRiskAfterTrade(const double additionalRisk)
{
    return GetPortfolioRiskValue() + additionalRisk;
}

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

double CUnifiedRiskManager::CalculateSymbolCorrelation(const string symbol1, const string symbol2)
{
    return m_tieredCorrelation.CalculateSymbolCorrelation(symbol1, symbol2);
}

double CUnifiedRiskManager::GetMaxCorrelationWithPortfolio(const string symbolParam)
{
    return m_tieredCorrelation.GetMaxCorrelationWithPortfolio(symbolParam);
}

void CUnifiedRiskManager::WriteAuditLog(const string message)
{
    m_validationStats.WriteAuditLog(message);
}

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

void CUnifiedRiskManager::UpdatePerformanceMetrics(const ulong startTimeParam)
{
    m_validationStats.UpdatePerformanceMetrics(startTimeParam);
}

string CUnifiedRiskManager::NormalizeClusterCode(const string clusterCode) const
{
    return CRiskClusterCodec::NormalizeClusterCode(clusterCode);
}

bool CUnifiedRiskManager::ParseClusterCodeFromComment(const string comment, string &clusterCode) const
{
    return CRiskClusterCodec::ParseClusterCodeFromComment(comment, clusterCode);
}

double CUnifiedRiskManager::EstimatePositionRiskPercent(const ulong ticket) const
{
    if(ticket == 0 || !PositionSelectByTicket(ticket)) {
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
        // Fail closed: a position with no SL is charged maxRiskPerTradePercent so the cluster budget is never underestimated.
        return m_config.maxRiskPerTradePercent;
    }
    
    double slPoints = MathAbs(openPrice - stopLoss) / point;
    if(slPoints <= 0.0)
    {
        // Same conservative treatment for a zero-distance SL.
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
    
    return (riskAmount / denominator) * 100.0;  // fraction -> 0-100 % scale
}

double CUnifiedRiskManager::GetCurrentPortfolioRisk()
{
    return m_portfolioRiskManager.GetPortfolioRisk();
}

void CUnifiedRiskManager::ClearOpposingConflictCache(const string symbol)
{
    m_opposingGuard.ClearOpposingConflictCache(symbol);
}

void CUnifiedRiskManager::GetValidationStats(int &total, int &approved, int &rejected, double &approvalRate)
{
    m_validationStats.GetStats(total, approved, rejected, approvalRate);
}

void CUnifiedRiskManager::ResetStats(void)
{
    m_validationStats.Reset();
}

#endif // CORE_RISK_UNIFIED_RISK_MANAGER_MQH

