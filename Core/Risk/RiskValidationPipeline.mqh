// Owns the EA's trade-approval hot path: CUnifiedRiskManager::ValidateTradeRequest -> CRiskValidationPipeline::Run
// MQL5 has no pointers to structs, so m_config is a local copy refreshed at every public entry point;
// nothing in this class writes to it.
// Owner value members arrive as non-owning pointers; owner-private state (daily risk usage, per-symbol budgets
// and risk overrides, trading-day key) is reached through IRiskPipelineHost and never cloned here.
// The order of the gates below IS the veto order: each gate returns before the next one runs.
#ifndef CORE_RISK_RISK_VALIDATION_PIPELINE_MQH
#define CORE_RISK_RISK_VALIDATION_PIPELINE_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "../Utils/JsonLogger.mqh"
#include "../Utils/RiskMath.mqh"
#include "../Processing/DerivAssetProfiler.mqh"
#include "PortfolioRiskManager.mqh"
#include "VirtualPosition.mqh"
#include "RiskClusterCodec.mqh"
#include "RiskValidationStats.mqh"
#include "RiskClusterBudget.mqh"
#include "RiskOpposingConflictGuard.mqh"
#include "RiskCircuitBreaker.mqh"
#include "RiskMarginHealth.mqh"
#include "RiskTieredCorrelation.mqh"

// All percent fields in SUnifiedRiskConfig use the 0-100 scale (1.0 = 1%), never 0-1 fractions.
struct SUnifiedRiskConfig
{
    double baseRiskPerTradePercent;
    double minRiskPerTradePercent;
    double maxRiskPerTradePercent;
    double maxDailyRiskPercent;
    double maxPortfolioRiskPercent;
    double correlationThreshold;        // 0-1 scale (not a risk percent)
    double correlationReduceThreshold;  // 0-1 scale (not a risk percent)
    double correlationBlockThreshold;   // 0-1 scale (not a risk percent)
    int maxPositionsSameBase;
    double drawdownWarningPercent;
    double drawdownCriticalPercent;
    double dailyLossLimitPercent;
    double minLotRiskMultiplier;        // Max risk multiplier when rounding up to broker min lot (e.g., 2.0 = 2x)
    bool allowMinLotRoundUp;            // InpAllowMinLotRoundUp: when false a sub-minimum lot is refused, never widened
    int adaptationMinTrades;
    bool enableAdaptiveSizing;
    bool enableAuditLogging;
    string auditLogFile;
};

struct STradeValidationRequest
{
    string symbol;
    ENUM_ORDER_TYPE orderType;
    double lotSize;                   // Requested lot size
    double stopLossPips;
    double takeProfitPips;
    double confidence;                // Signal confidence (0-1)
    string strategy;
    string reasoning;
    string strategyRole;
    string strategyCluster;
    string clusterCode;               // T/R/S/N
    string contributorContext;
    datetime requestTime;

    STradeValidationRequest() :
        symbol(""),
        orderType(ORDER_TYPE_BUY),
        lotSize(0.0),
        stopLossPips(0.0),
        takeProfitPips(0.0),
        confidence(0.0),
        strategy(""),
        reasoning(""),
        strategyRole(""),
        strategyCluster(""),
        clusterCode(""),
        contributorContext(""),
        requestTime(0)
    {}
};

// Call-back surface the pipeline needs from its owner (CUnifiedRiskManager); every entry is an owner method.
// pure-virtual (= 0) turns a signature mismatch into a compile error instead of a silent behaviour change.
class IRiskPipelineHost
{
public:
    virtual ~IRiskPipelineHost() {}

    virtual bool   IsInitialized() const = 0;
    virtual void   CopyRiskConfig(SUnifiedRiskConfig &outConfig) const = 0;

    virtual bool   CheckDailyLossLimit() = 0;
    virtual bool   CheckDrawdownCircuitBreaker() = 0;
    // Margin ladder's entry hold, measured outside the pipeline on MARGIN_HEALTH_POLL_MS. Distinct from the drawdown
    // breaker: this one is lifted by the next margin poll, not by the drawdown-graded auto-recovery.
    virtual bool   IsMarginEntriesHeld() const = 0;
    virtual void   CheckAndResetDailyLimits() = 0;
    virtual double GetEffectiveDailyRiskUsedPercent(const double additionalRiskPercent) = 0;
    virtual SDrawdownState GetDrawdownState() = 0;

    virtual double GetEffectiveMaxDrawdown(const string symbol) const = 0;
    virtual double GetEffectiveRiskPerTrade(const string symbol) const = 0;

    virtual bool   ReserveVirtualPosition(const string ownerTag,
                                          const STradeValidationRequest &request,
                                          const double riskPercent) = 0;
    virtual void   ReleaseVirtualPosition(const string ownerTag) = 0;
    virtual void   UpdateVirtualPositionRisk(const string ownerTag, const double lotSize, const double riskPercent) = 0;

    virtual bool   IsSymbolBudgetAvailable(const string symbol, const double riskPct) = 0;
    virtual double GetSymbolRiskAllocation(const string symbol) = 0;
    virtual double GetSymbolUsedRisk(const string symbol) = 0;

    virtual bool   IsSymbolDataValid(const string symbolParam) = 0;
    virtual bool   CheckAccountTradingPermissions(void) = 0;
    virtual double CalculateTradeRisk(const string symbolParam,
                                      const double lotSize,
                                      const double stopLossPips) const = 0;
    virtual double EstimatePositionRiskPercent(const ulong ticket) const = 0;
    virtual double CalculatePortfolioRiskAfterTrade(const double additionalRisk) = 0;
    virtual void   LogValidationResult(const STradeValidationRequest &request,
                                       const SValidationResult &result) = 0;
    virtual void   UpdatePerformanceMetrics(const ulong startTime) = 0;
};

// The 7-step pre-trade gate behind CUnifiedRiskManager::ValidateTradeRequest; every entry passes it.
class CRiskValidationPipeline
{
private:
    IRiskPipelineHost*          m_host;

    //--- NON-OWNING: the owner's value members; it constructs/destroys them, this class only uses them.
    CRiskCircuitBreaker*        m_circuitBreaker;
    CVirtualPositionBook*       m_virtualPositionBook;
    CPortfolioRiskManager*      m_portfolioRiskManager;
    CRiskTieredCorrelation*     m_tieredCorrelation;
    CRiskClusterBudget*         m_clusterBudget;
    CRiskMarginHealth*          m_marginHealth;
    CRiskOpposingConflictGuard* m_opposingGuard;
    CRiskValidationStats*       m_validationStats;
    CDerivAssetProfiler*        m_derivAssetProfiler;

    SUnifiedRiskConfig          m_config;

    //--- Owner scalars mirrored here; the owner push-syncs them from the same setters that mutate them
    //--- (SetEAMagicNumber and ConfigureClusterGovernance both call back here).
    long                        m_eaMagicNumber;           // SetEAMagicNumber / Initialize
    double                      m_emergencyRiskOverride;   // immutable after construction (5.0)
    bool                        m_clusterGovernanceEnabled;
    bool                        m_clusterMutexEnabled;
    int                         m_maxConcurrentPerCluster;
    double                      m_maxClusterRiskPercent;

    void SyncConfig()
    {
        if(CheckPointer(m_host) != POINTER_INVALID)
            m_host.CopyRiskConfig(m_config);
    }

    //--- IsWired gates every collaborator this class holds, so a new pointer must land in both places.
    bool IsWired() const
    {
        return (CheckPointer(m_host)                 != POINTER_INVALID &&
                CheckPointer(m_circuitBreaker)       != POINTER_INVALID &&
                CheckPointer(m_virtualPositionBook)  != POINTER_INVALID &&
                CheckPointer(m_portfolioRiskManager) != POINTER_INVALID &&
                CheckPointer(m_tieredCorrelation)    != POINTER_INVALID &&
                CheckPointer(m_clusterBudget)        != POINTER_INVALID &&
                CheckPointer(m_marginHealth)         != POINTER_INVALID &&
                CheckPointer(m_opposingGuard)        != POINTER_INVALID &&
                CheckPointer(m_validationStats)      != POINTER_INVALID &&
                CheckPointer(m_derivAssetProfiler)   != POINTER_INVALID);
    }

public:
// Zero init only; wiring happens in Initialize(), which the owner calls from its constructor and its Initialize().
    CRiskValidationPipeline() :
        m_host(NULL),
        m_circuitBreaker(NULL),
        m_virtualPositionBook(NULL),
        m_portfolioRiskManager(NULL),
        m_tieredCorrelation(NULL),
        m_clusterBudget(NULL),
        m_marginHealth(NULL),
        m_opposingGuard(NULL),
        m_validationStats(NULL),
        m_derivAssetProfiler(NULL),
        m_eaMagicNumber(0),
        m_emergencyRiskOverride(5.0),
        m_clusterGovernanceEnabled(true),
        m_clusterMutexEnabled(true),
        m_maxConcurrentPerCluster(5),
        m_maxClusterRiskPercent(5.0)
    {
        ZeroMemory(m_config);
    }

    ~CRiskValidationPipeline()
    {
        // Empty by design: every stored pointer is NON-OWNING.
    }

    void Initialize(IRiskPipelineHost*          host,
                    CRiskCircuitBreaker*        circuitBreaker,
                    CVirtualPositionBook*       virtualPositionBook,
                    CPortfolioRiskManager*      portfolioRiskManager,
                    CRiskTieredCorrelation*     tieredCorrelation,
                    CRiskClusterBudget*         clusterBudget,
                    CRiskMarginHealth*          marginHealth,
                    CRiskOpposingConflictGuard* opposingGuard,
                    CRiskValidationStats*       validationStats,
                    CDerivAssetProfiler*        derivAssetProfiler,
                    const long                  eaMagicNumber,
                    const double                emergencyRiskOverride,
                    const bool                  clusterGovernanceEnabled,
                    const bool                  clusterMutexEnabled,
                    const int                   maxConcurrentPerCluster,
                    const double                maxClusterRiskPercent)
    {
        m_host                     = host;
        m_circuitBreaker           = circuitBreaker;
        m_virtualPositionBook      = virtualPositionBook;
        m_portfolioRiskManager     = portfolioRiskManager;
        m_tieredCorrelation        = tieredCorrelation;
        m_clusterBudget            = clusterBudget;
        m_marginHealth             = marginHealth;
        m_opposingGuard            = opposingGuard;
        m_validationStats          = validationStats;
        m_derivAssetProfiler       = derivAssetProfiler;
        m_eaMagicNumber            = eaMagicNumber;
        m_emergencyRiskOverride    = emergencyRiskOverride;
        m_clusterGovernanceEnabled = clusterGovernanceEnabled;
        m_clusterMutexEnabled      = clusterMutexEnabled;
        m_maxConcurrentPerCluster  = maxConcurrentPerCluster;
        m_maxClusterRiskPercent    = maxClusterRiskPercent;

        SyncConfig();
    }

    void SetEAMagicNumber(const long magic) { m_eaMagicNumber = magic; }

    void SetClusterGovernance(const bool enabled,
                              const int maxConcurrentPerCluster,
                              const double maxClusterRiskPercent,
                              const bool enableMutex)
    {
        m_clusterGovernanceEnabled = enabled;
        m_clusterMutexEnabled      = enableMutex;
        m_maxConcurrentPerCluster  = maxConcurrentPerCluster;
        m_maxClusterRiskPercent    = maxClusterRiskPercent;
    }

    SValidationResult Run(const STradeValidationRequest &request,
                          const string phaseTag = "runtime",
                          const string corrId = "");

    // Validation body; Run() wraps it for timing and approve/reject counts.
    SValidationResult RunInternal(const STradeValidationRequest &request,
                          const string phaseTag = "runtime",
                          const string corrId = "");

    bool ValidateBasicParameters(const STradeValidationRequest &request, string &message);
    bool ValidateRiskLimits(const STradeValidationRequest &request, string &message, double &riskPercent);
    bool ValidatePortfolioRisk(const STradeValidationRequest &request, const double tradeRiskPercent, string &message, const double ownReservationRiskPercent = 0.0);
    bool ValidateClusterGovernance(const STradeValidationRequest &request, const double tradeRiskPercent, string &message);
    bool ValidateCorrelationLimits(const STradeValidationRequest &request, string &message, double &correlationRisk);
    bool ValidateMarginRequirements(const STradeValidationRequest &request, string &message);
    bool ValidateAccountHealth(const STradeValidationRequest &request, string &message);
};

    SValidationResult CRiskValidationPipeline::Run(const STradeValidationRequest &request,
                          const string phaseTag,
                          const string corrId)
    {
        ulong validationStartUs = GetMicrosecondCount();
        SValidationResult result = RunInternal(request, phaseTag, corrId);
        if(result.approved)
            m_validationStats.RecordApproval();
        else
            m_validationStats.RecordRejection();
        m_host.UpdatePerformanceMetrics(validationStartUs);
        return result;
    }

    SValidationResult CRiskValidationPipeline::RunInternal(const STradeValidationRequest &request,
                                               const string phaseTag,
                                               const string corrId)
    {
    SyncConfig();

    if(corrId != "")
        CJsonLogger::SetCorrelationId(corrId);

    SValidationResult result;
    ZeroMemory(result);
    result.approved = false;
    result.adjustedLotSize = request.lotSize;
    result.severity = ERROR_LEVEL_ERROR;

    // Fail-closed: this returns before any collaborator is read (the owner wires them in its constructor body,
    // WireValidationPipeline). Caveat: the Run() wrapper still touches m_validationStats and m_host on this path.
    if(!IsWired())
    {
        result.message = "Unified risk manager is not initialized";
        CJsonLogger::LogRiskEvent("RiskGate", request.symbol, "NOT_INITIALIZED",
            "Unified risk manager is not initialized", 0.0, 0.0, corrId);
        CJsonLogger::ClearCorrelationId();
        return result;
    }

    if(!m_host.IsInitialized())
    {
        result.message = "Unified risk manager is not initialized";
        CJsonLogger::LogRiskEvent("RiskGate", request.symbol, "NOT_INITIALIZED", 
            "Unified risk manager is not initialized", 0.0, 0.0, corrId);
        CJsonLogger::ClearCorrelationId();
        return result;
    }

    if(!m_host.CheckDailyLossLimit())
    {
        result.message = StringFormat("Trading halted: Daily loss limit of %.1f%% exceeded", m_config.dailyLossLimitPercent);
        result.severity = ERROR_LEVEL_CRITICAL;
        CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "DAILY_LOSS_LIMIT",
            StringFormat("Daily loss limit %.1f%% exceeded", m_config.dailyLossLimitPercent),
            m_config.dailyLossLimitPercent, 0.0, corrId);
        CJsonLogger::ClearCorrelationId();
        return result;
    }

    if(!m_host.CheckDrawdownCircuitBreaker())
    {
        result.message = "Trading paused: Drawdown circuit breaker activated";
        result.severity = ERROR_LEVEL_CRITICAL;
        CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "DRAWDOWN_CIRCUIT_BREAKER",
            StringFormat("Drawdown %.2f%% triggered circuit breaker", m_circuitBreaker.GetMaxDrawdownFromPeak()),
            m_circuitBreaker.GetMaxDrawdownFromPeak(), 0.0, corrId);
        CJsonLogger::ClearCorrelationId();
        return result;
    }

    // Margin ladder hold, measured on the runtime cadence. Printed here rather than only in the monitor because the
    // refusal and the entry it refuses belong in the same place, and the level is read live instead of restated.
    if(m_host.IsMarginEntriesHeld())
    {
        double marginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
        result.message = StringFormat("Trading paused: account margin level %.1f%% is below 200%%", marginLevel);
        result.severity = ERROR_LEVEL_CRITICAL;
        PrintFormat("[RISK-MARGIN] %s | entry refused | marginLevel=%.1f%% | margin=%.2f equity=%.2f",
                    request.symbol, marginLevel, AccountInfoDouble(ACCOUNT_MARGIN), AccountInfoDouble(ACCOUNT_EQUITY));
        CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "MARGIN_HEALTH_HOLD",
            StringFormat("Margin level %.1f%% below 200%%", marginLevel), marginLevel, 200.0, corrId);
        CJsonLogger::ClearCorrelationId();
        return result;
    }

    // The ceiling is this symbol's asset-class drawdown limit (SAssetProfile.maxDrawdownPercent: Forex 10,
    // Metals 12, Deriv volatility 10, Step 8) and it rejects before the global breaker only while tighter than
    // drawdownCriticalPercent; a looser override is never reached here. The measured quantity is the ACCOUNT-wide
    // peak drawdown, so unrelated positions' losses can halt this entry below InpMaxDrawdown - both numbers print.
    double familyMaxDD = m_host.GetEffectiveMaxDrawdown(request.symbol);
    if(familyMaxDD < m_config.drawdownCriticalPercent && m_circuitBreaker.GetMaxDrawdownFromPeak() >= familyMaxDD)
    {
        result.message = StringFormat("Account drawdown %.2f%% reached the %.1f%% asset-class ceiling for %s",
                                      m_circuitBreaker.GetMaxDrawdownFromPeak(), familyMaxDD, request.symbol);
        result.severity = ERROR_LEVEL_WARNING;
        PrintFormat("[RISK-ASSET-DD] %s | accountDD=%.2f%% >= ceiling=%.1f%% | criticalLimit=%.1f%% | entry refused",
                    request.symbol, m_circuitBreaker.GetMaxDrawdownFromPeak(), familyMaxDD,
                    m_config.drawdownCriticalPercent);
        CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "FAMILY_DRAWDOWN_LIMIT",
            StringFormat("Family DD=%.2f%% >= family limit=%.1f%%", m_circuitBreaker.GetMaxDrawdownFromPeak(), familyMaxDD),
            m_circuitBreaker.GetMaxDrawdownFromPeak(), familyMaxDD, corrId);
        CJsonLogger::ClearCorrelationId();
        return result;
    }

    m_host.CheckAndResetDailyLimits();

    double reservedRisk = m_virtualPositionBook.GetReservedRiskPercent();
    double openExposureRisk = m_portfolioRiskManager.GetPortfolioRisk();
    double effectiveDailyRisk = m_host.GetEffectiveDailyRiskUsedPercent(reservedRisk);
    if(effectiveDailyRisk >= m_config.maxDailyRiskPercent)
    {
        result.message = StringFormat("Daily risk budget exhausted: %.2f%% / %.2f%%",
                                      effectiveDailyRisk, m_config.maxDailyRiskPercent);
        result.severity = ERROR_LEVEL_WARNING;
        CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "DAILY_BUDGET_EXHAUSTED",
            StringFormat("Effective daily risk %.2f%% >= limit %.2f%%", effectiveDailyRisk, m_config.maxDailyRiskPercent),
            effectiveDailyRisk, m_config.maxDailyRiskPercent, corrId);
        CJsonLogger::ClearCorrelationId();
        return result;
    }

    if(m_virtualPositionBook.HasOpposingReservation(request.symbol, request.orderType))
    {
        result.message = StringFormat("Virtual reservation conflict on %s (opposing candidate already reserved)",
                                      request.symbol);
        result.severity = ERROR_LEVEL_WARNING;
        CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "VIRTUAL_RESERVATION_CONFLICT",
            "Opposing candidate already reserved", 0.0, 0.0, corrId);
        CJsonLogger::ClearCorrelationId();
        return result;
    }

    // Reserve before the gates so the trade counts toward portfolio risk; released on rejection, kept on approval.
    // Reserve() refuses riskPercent<=0 and lotSize<=0, hence the provisional risk, re-synced by UpdateVirtualPositionRisk().
    int preValidationReservations = m_virtualPositionBook.GetReservationCount();
    double provTradeRisk = m_host.CalculateTradeRisk(request.symbol, request.lotSize, request.stopLossPips);
    double provDenom = CRiskMath::GetRiskDenominator();
    double provisionalRiskPct = (provTradeRisk > 0.0 && provDenom > 0.0) ? (provTradeRisk / provDenom) * 100.0 : 0.0;
    string virtualOwnerTag = StringFormat("%s_%s_%lld", request.symbol, EnumToString(request.orderType), GetMicrosecondCount());
    bool virtualReserved = (provisionalRiskPct > 0.0) &&
                           m_host.ReserveVirtualPosition(virtualOwnerTag, request, provisionalRiskPct);

    string validationMessage = "";
    if(!ValidateBasicParameters(request, validationMessage))
    {
        result.message = "Basic validation failed: " + validationMessage;
        result.severity = ERROR_LEVEL_ERROR;
        if(virtualReserved) m_host.ReleaseVirtualPosition(virtualOwnerTag);
        CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "BASIC_VALIDATION_FAILED",
            validationMessage, 0.0, 0.0, corrId);
        m_host.LogValidationResult(request, result);
        CJsonLogger::ClearCorrelationId();
        return result;
    }
    
    double tradeRisk = 0.0;
    if(!ValidateRiskLimits(request, validationMessage, tradeRisk))
    {
        result.message = "Risk limit validation failed: " + validationMessage;
        result.riskPercent = tradeRisk;
        result.severity = ERROR_LEVEL_ERROR;
        if(virtualReserved) m_host.ReleaseVirtualPosition(virtualOwnerTag);
        CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "RISK_LIMITS_FAILED",
            validationMessage, tradeRisk, 0.0, corrId);
        m_host.LogValidationResult(request, result);
        CJsonLogger::ClearCorrelationId();
        return result;
    }
    result.riskPercent = tradeRisk;
    
    if(!ValidatePortfolioRisk(request, tradeRisk, validationMessage, virtualReserved ? provisionalRiskPct : 0.0))
    {
        result.message = "Portfolio risk validation failed: " + validationMessage;
        result.severity = ERROR_LEVEL_ERROR;
        if(virtualReserved) m_host.ReleaseVirtualPosition(virtualOwnerTag);
        CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "PORTFOLIO_RISK_FAILED",
            validationMessage, tradeRisk, 0.0, corrId);
        m_host.LogValidationResult(request, result);
        CJsonLogger::ClearCorrelationId();
        return result;
    }

    if(!ValidateClusterGovernance(request, tradeRisk, validationMessage))
    {
        result.message = "Cluster governance validation failed: " + validationMessage;
        result.severity = ERROR_LEVEL_WARNING;
        if(virtualReserved) m_host.ReleaseVirtualPosition(virtualOwnerTag);
        CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "CLUSTER_GOVERNANCE_FAILED",
            validationMessage, tradeRisk, 0.0, corrId);
        m_host.LogValidationResult(request, result);
        CJsonLogger::ClearCorrelationId();
        return result;
    }
    
    double correlationRisk = 0.0;
    if(!ValidateCorrelationLimits(request, validationMessage, correlationRisk))
    {
        result.message = "Correlation validation failed: " + validationMessage;
        result.correlationRisk = correlationRisk;
        result.severity = ERROR_LEVEL_WARNING;
        if(virtualReserved) m_host.ReleaseVirtualPosition(virtualOwnerTag);
        CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "CORRELATION_LIMITS_FAILED",
            validationMessage, correlationRisk, 0.0, corrId);
        m_host.LogValidationResult(request, result);
        CJsonLogger::ClearCorrelationId();
        return result;
    }
    result.correlationRisk = correlationRisk;
    
    if(!ValidateMarginRequirements(request, validationMessage))
    {
        result.message = "Margin validation failed: " + validationMessage;
        result.severity = ERROR_LEVEL_ERROR;
        if(virtualReserved) m_host.ReleaseVirtualPosition(virtualOwnerTag);
        CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "MARGIN_REQUIREMENTS_FAILED",
            validationMessage, 0.0, 0.0, corrId);
        m_host.LogValidationResult(request, result);
        CJsonLogger::ClearCorrelationId();
        return result;
    }
    
    if(!ValidateAccountHealth(request, validationMessage))
    {
        result.message = "Account health validation failed: " + validationMessage;
        result.severity = ERROR_LEVEL_CRITICAL;
        if(virtualReserved) m_host.ReleaseVirtualPosition(virtualOwnerTag);
        CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "ACCOUNT_HEALTH_FAILED",
            validationMessage, 0.0, 0.0, corrId);
        m_host.LogValidationResult(request, result);
        CJsonLogger::ClearCorrelationId();
        return result;
    }
    
    // approved=true here is provisional: the lot floor / symbol budget / portfolio / family / correlation /
    // daily-risk / CVaR gates below can still reject. Approval bookkeeping runs again at the final exit.
    result.approved = true;
    result.message = "Trade request approved";
    result.portfolioRisk = m_host.CalculatePortfolioRiskAfterTrade(tradeRisk);
    result.severity = ERROR_LEVEL_INFO;

    // Lot floor: a sub-SYMBOL_VOLUME_MIN lot is clamped UP to the minimum (CPositionSizer::NormalizeVolume behaviour, not
    // CTradeMgrPricing's 0.0-and-refuse), riskPercent scaled by that ratio, and only while the ratio <= minLotRiskMultiplier
    // and the operator has allowed the round-up at all.
    double brokerMinLot = SymbolInfoDouble(request.symbol, SYMBOL_VOLUME_MIN);
    if(brokerMinLot <= 0.0) brokerMinLot = 0.01;
    if(result.adjustedLotSize > 0.0 && result.adjustedLotSize < brokerMinLot)
    {
        double riskRatio = brokerMinLot / result.adjustedLotSize;
        if(!m_config.allowMinLotRoundUp)
        {
            result.approved = false;
            result.message = StringFormat("Lot %.3f below broker minimum %.3f and InpAllowMinLotRoundUp is false.",
                                          result.adjustedLotSize, brokerMinLot);
            result.severity = ERROR_LEVEL_WARNING;
            PrintFormat("[RISK-GATE-REJECT] %s | reason=lot_below_min_roundup_disabled | lot=%.3f | min_lot=%.3f | uplift=%.1fx | phase=%s",
                        request.symbol, result.adjustedLotSize, brokerMinLot, riskRatio, phaseTag);
            CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "LOT_BELOW_MIN_ROUNDUP_DISABLED",
                StringFormat("Lot %.3f < min %.3f, round-up refused by the operator", result.adjustedLotSize, brokerMinLot),
                riskRatio, brokerMinLot, corrId);
            CJsonLogger::ClearCorrelationId();
            if(virtualReserved) m_host.ReleaseVirtualPosition(virtualOwnerTag);
            return result;
        }
        else if(riskRatio <= m_config.minLotRiskMultiplier)
        {
            PrintFormat("[RISK-LOT-FLOOR] %s | Adjusted %.3f -> %.3f (broker min, risk %.1fx <= %.1fx cap)",
                        request.symbol, result.adjustedLotSize, brokerMinLot, riskRatio, m_config.minLotRiskMultiplier);
            result.adjustedLotSize = brokerMinLot;
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
            CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "LOT_FLOOR_RISK_CAP",
                StringFormat("Lot %.3f < min %.3f, risk ratio %.1fx > cap %.1fx", result.adjustedLotSize, brokerMinLot, riskRatio, m_config.minLotRiskMultiplier),
                riskRatio, m_config.minLotRiskMultiplier, corrId);
            CJsonLogger::ClearCorrelationId();
            if(virtualReserved) m_host.ReleaseVirtualPosition(virtualOwnerTag);
            return result;
        }
    }

    if(result.riskPercent > 0.0 && !m_host.IsSymbolBudgetAvailable(request.symbol, result.riskPercent))
    {
        double allocation = m_host.GetSymbolRiskAllocation(request.symbol);
        double used = m_host.GetSymbolUsedRisk(request.symbol);

        // Cold-start bypass: with no open positions and no prior reservations the per-symbol allocation is ignored.
        // The portfolio gate below shares this same condition, so on a cold start nothing caps total risk.
        int openPositionCount = PositionsTotal();
        // Snapshot taken before this trade's own reservation, so it cannot disable the bypass.
        int virtualReservationCount = preValidationReservations;
        bool isColdStart = (openPositionCount == 0 && virtualReservationCount == 0);

        if(isColdStart && result.riskPercent <= m_host.GetEffectiveRiskPerTrade(request.symbol))
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
            CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "SYMBOL_BUDGET_EXHAUSTED",
                StringFormat("Used %.2f%% + new %.2f%% > alloc %.2f%%", used, result.riskPercent, allocation),
                used + result.riskPercent, allocation, corrId);
            CJsonLogger::ClearCorrelationId();
            if(virtualReserved) m_host.ReleaseVirtualPosition(virtualOwnerTag);
            return result;
        }
    }

    double projectedPortfolioRisk = openExposureRisk + reservedRisk + MathMax(0.0, result.riskPercent);
    if(projectedPortfolioRisk > m_config.maxPortfolioRiskPercent)
    {
        // Cold-start bypass of the portfolio cap: exceeding maxPortfolioRiskPercent is logged, not refused. Nothing
        // splits the cap across symbols and no aggregate limit holds; GetEffectiveRiskPerTrade() is the only check left.
        int openPositionCount = PositionsTotal();
        int virtualReservationCount = preValidationReservations;
        bool isColdStart = (openPositionCount == 0 && virtualReservationCount == 0);

        if(isColdStart && result.riskPercent > 0.0 && result.riskPercent <= m_host.GetEffectiveRiskPerTrade(request.symbol))
                {
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
                    CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "PORTFOLIO_RISK_EXCEEDED",
                        StringFormat("Open %.2f%% + reserved %.2f%% + new %.2f%% > limit %.2f%%", openExposureRisk, reservedRisk, result.riskPercent, m_config.maxPortfolioRiskPercent),
                        openExposureRisk + reservedRisk + result.riskPercent, m_config.maxPortfolioRiskPercent, corrId);
                    CJsonLogger::ClearCorrelationId();
                    m_host.ReleaseVirtualPosition(virtualOwnerTag);
                    return result;
                }
    }

    // Per-family position cap: 2 for crash/boom, step, jump and hybrid, 3 otherwise. DetectFamily answers
    // DERIV_UNKNOWN for every name that is not a Deriv synthetic, so counting it as a family capped the whole
    // non-Deriv half of the universe at 3 positions together - EURUSD, GBPUSD, USDJPY, AUDUSD, XAUUSD and BTCUSD
    // on the default list - while InpMaxPositionsPerSymbol = 5 and InpMaxPositionsTotal = 15 allow more. Those
    // caps already govern those symbols; this bucket only means "the same synthetic family".
        ENUM_DERIV_FAMILY reqFamily = m_derivAssetProfiler.DetectFamily(request.symbol);
        if(reqFamily != DERIV_UNKNOWN)
        {
            int familyPositionCount = 0;
            int totalPositions = PositionsTotal();
        
            for(int i = 0; i < totalPositions; i++)
            {
                ulong ticket = PositionGetTicket(i);
                if(ticket <= 0) continue;
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                ENUM_DERIV_FAMILY posFamily = m_derivAssetProfiler.DetectFamily(posSymbol);
                if(posFamily == reqFamily)
                    familyPositionCount++;
            }

            int maxFamilyPositions = 3;
            switch(reqFamily)
            {
                case DERIV_CRASH_BOOM:
                case DERIV_STEP:
                case DERIV_JUMP:
                case DERIV_HYBRID:
                    maxFamilyPositions = 2;
                    break;
                default:
                    maxFamilyPositions = 3;
                    break;
            }

            if(familyPositionCount >= maxFamilyPositions)
                        {
                            result.approved = false;
                            result.severity = ERROR_LEVEL_WARNING;
                            result.message = StringFormat("Family position limit reached: %d/%d positions in same family",
                                                          familyPositionCount, maxFamilyPositions);
                            PrintFormat("[RISK-FAMILY-POS] %s | family=%s | positions=%d/%d | entry refused",
                                        request.symbol, EnumToString(reqFamily), familyPositionCount, maxFamilyPositions);
                            CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "FAMILY_POSITION_LIMIT",
                                StringFormat("Family %s positions %d/%d", EnumToString(reqFamily), familyPositionCount, maxFamilyPositions),
                                (double)familyPositionCount, (double)maxFamilyPositions, corrId);
                            CJsonLogger::ClearCorrelationId();
                            m_host.ReleaseVirtualPosition(virtualOwnerTag);
                            return result;
                        }
        }

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
            double corr = m_tieredCorrelation.GetSymbolCorrelation(request.symbol, posSymbol);
            if(corr > maxCorrelation)
                maxCorrelation = corr;
        }

                // BLOCK tier uses >=, and maxCorrelation starts at 0.0, so a 0.0 block threshold would veto every
                // candidate; EAOrchestrator pins correlationBlockThreshold to 0.7.
                if(maxCorrelation >= m_config.correlationBlockThreshold)
                {
                    result.approved = false;
                    result.severity = ERROR_LEVEL_WARNING;
                    result.message = StringFormat("Correlation BLOCK: %.2f >= %.2f for %s",
                                                  maxCorrelation, m_config.correlationBlockThreshold, request.symbol);
                    CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "CORRELATION_BLOCK",
                        StringFormat("Correlation %.2f >= threshold %.2f", maxCorrelation, m_config.correlationBlockThreshold),
                        maxCorrelation, m_config.correlationBlockThreshold, corrId);
                    CJsonLogger::ClearCorrelationId();
                    m_host.ReleaseVirtualPosition(virtualOwnerTag);
                    return result;
                }

        // REDUCE tier: lot scaled by a factor clamped to [0.25, 1.0].
        if(maxCorrelation >= m_config.correlationReduceThreshold)
        {
            double denom = m_config.correlationBlockThreshold - m_config.correlationReduceThreshold;
            if(denom <= 0.001) denom = 0.001;
            double reduceFactor = 1.0 - ((maxCorrelation - m_config.correlationReduceThreshold) / denom);
            reduceFactor = MathMax(0.25, MathMin(1.0, reduceFactor));
            double originalLot = result.adjustedLotSize;
            // Align to the symbol's volume step: blind 2dp rounding gave 0.001-step symbols
            // off-step lots, which the broker then rejected as invalid volume.
            double volStep = SymbolInfoDouble(request.symbol, SYMBOL_VOLUME_STEP);
            if(volStep > 0.0)
            {
                long wholeSteps = (long)MathFloor((result.adjustedLotSize * reduceFactor) / volStep + 1e-9);
                result.adjustedLotSize = NormalizeDouble(wholeSteps * volStep, 8);
            }
            else
                result.adjustedLotSize = NormalizeDouble(result.adjustedLotSize * reduceFactor, 2);

            // A min-lot position cannot be reduced: the step floor lands on 0.0 and every consumer
            // adopts adjustedLotSize only when > 0.0, so approving here traded the full lot with the
            // correlation discount silently gone. Refuse instead.
            double corrMinLot = SymbolInfoDouble(request.symbol, SYMBOL_VOLUME_MIN);
            if(result.adjustedLotSize < corrMinLot)
            {
                result.approved = false;
                result.severity = ERROR_LEVEL_WARNING;
                result.message = StringFormat("Correlation %.2f needs lot cut to %.3f, below broker min %.3f",
                                              maxCorrelation, result.adjustedLotSize, corrMinLot);
                if(virtualReserved) m_host.ReleaseVirtualPosition(virtualOwnerTag);
                PrintFormat("[RISK-GATE-REJECT] %s | reason=correlation_reduce_below_min_lot | corr=%.2f | lot=%.3f->%.3f | min=%.3f",
                            request.symbol, maxCorrelation, originalLot, result.adjustedLotSize, corrMinLot);
                CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "CORRELATION_REDUCE_BELOW_MIN_LOT",
                    StringFormat("Correlation reduce | corr=%.2f | factor=%.2f | lot %.2f->%.2f < min %.2f",
                        maxCorrelation, reduceFactor, originalLot, result.adjustedLotSize, corrMinLot),
                    maxCorrelation, reduceFactor, corrId);
                CJsonLogger::ClearCorrelationId();
                return result;
            }

            result.requiresAdjustment = true;
            CJsonLogger::LogInfo("RiskGateReduce",
                StringFormat("Correlation reduce | corr=%.2f | factor=%.2f | lot %.2f->%.2f",
                    maxCorrelation, reduceFactor, originalLot, result.adjustedLotSize), corrId);
        }
    }

    // Recompute riskPercent after any lot change through host.CalculateTradeRisk (stopLossPips are SYMBOL_POINT
    // units, not point*10 pips) over CRiskMath::GetRiskDenominator, which is min(balance, equity).
    if(result.requiresAdjustment && result.adjustedLotSize > 0.0 && result.adjustedLotSize != request.lotSize)
    {
        double tradeRiskReduced = m_host.CalculateTradeRisk(request.symbol, result.adjustedLotSize, request.stopLossPips);
        double riskDenom = CRiskMath::GetRiskDenominator();
        if(tradeRiskReduced > 0.0 && riskDenom > 0.0)
            result.riskPercent = (tradeRiskReduced / riskDenom) * 100.0;
    }

    // The margin gate above priced request.lotSize, and the lot floor at :522 can have raised it since. Re-check on the
    // lot the candidate actually ships, so a round-up to the broker minimum cannot be approved on margin never verified.
    if(result.adjustedLotSize > request.lotSize)
    {
        STradeValidationRequest finalLotRequest = request;
        finalLotRequest.lotSize = result.adjustedLotSize;
        string finalLotMarginMessage = "";
        if(!ValidateMarginRequirements(finalLotRequest, finalLotMarginMessage))
        {
            result.approved = false;
            result.severity = ERROR_LEVEL_WARNING;
            result.message = StringFormat("Margin insufficient at the raised minimum lot: %s", finalLotMarginMessage);
            PrintFormat("[RISK-GATE-REJECT] %s | reason=lot_floor_margin | lot=%.3f -> %.3f | %s",
                        request.symbol, request.lotSize, result.adjustedLotSize, finalLotMarginMessage);
            CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "LOT_FLOOR_MARGIN",
                finalLotMarginMessage, result.adjustedLotSize, request.lotSize, corrId);
            CJsonLogger::ClearCorrelationId();
            if(virtualReserved) m_host.ReleaseVirtualPosition(virtualOwnerTag);
            return result;
        }
    }

    double projectedDailyRisk = m_host.GetEffectiveDailyRiskUsedPercent(reservedRisk + MathMax(0.0, result.riskPercent));
    // >= and not >: GetEffectiveDailyRiskUsedPercent clamps its answer to maxDailyRiskPercent, so a
    // strict comparison could never hold and this post-adjustment projection never refused a trade.
    // The pre-approval budget gate above uses the same >= against the same clamped value.
        if(projectedDailyRisk >= m_config.maxDailyRiskPercent)
        {
            result.approved = false;
            result.severity = ERROR_LEVEL_WARNING;
            result.message = StringFormat("Daily risk limit would be exceeded (%s): %.2f%% + %.2f%% >= %.2f%%",
                                          phaseTag, effectiveDailyRisk, result.riskPercent, m_config.maxDailyRiskPercent);
            PrintFormat("[RISK-DAILY-LIMIT] %s | reason=daily_risk_would_exceed | phase=%s | effective=%.2f%% + new=%.2f%% >= limit=%.2f%% | lot=%.4f",
                        request.symbol, phaseTag, effectiveDailyRisk, result.riskPercent,
                        m_config.maxDailyRiskPercent, result.adjustedLotSize);
            CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "DAILY_RISK_WOULD_EXCEED",
                StringFormat("Effective %.2f%% + new %.2f%% > limit %.2f%%", effectiveDailyRisk, result.riskPercent, m_config.maxDailyRiskPercent),
                projectedDailyRisk, m_config.maxDailyRiskPercent, corrId);
            CJsonLogger::ClearCorrelationId();
            m_host.ReleaseVirtualPosition(virtualOwnerTag);
            return result;
        }

    // CVaR tail gate: IsCVaRLimitExceeded takes a FRACTION (m_cvarMaxRisk 0.10 = 10%), hence the /100 here, and it
    // fails open below 20 equity-curve samples.
    if(m_portfolioRiskManager.IsCVaRLimitExceeded(MathMax(0.0, result.riskPercent) / 100.0))
    {
        result.approved = false;
        result.severity = ERROR_LEVEL_WARNING;
        result.message = StringFormat("CVaR tail-risk limit exceeded (%s): worst-case equity loss + %.2f%% trade risk above cap",
                                      phaseTag, result.riskPercent);
        CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "CVAR_TAIL_RISK",
            "Worst-tail equity-curve loss + proposed trade risk exceeds CVaR cap",
            MathAbs(m_portfolioRiskManager.GetCurrentCVaR()), result.riskPercent / 100.0, corrId);
        CJsonLogger::ClearCorrelationId();
        PrintFormat("[RISK-GATE-REJECT] %s | reason=cvar_tail_risk | risk=%.2f%% | phase=%s",
                    request.symbol, result.riskPercent, phaseTag);
        if(virtualReserved) m_host.ReleaseVirtualPosition(virtualOwnerTag);
        return result;
    }

    // Sync the reservation to the final lot and risk so post-approval budget checks see real exposure, not the
    // provisional estimate, and so the fill can discharge the pending risk instead of double-counting it.
    if(virtualReserved && result.riskPercent > 0.0 && result.adjustedLotSize > 0.0)
        m_host.UpdateVirtualPositionRisk(virtualOwnerTag, result.adjustedLotSize, result.riskPercent);

    result.approved = true;
    result.message = "Trade request approved";
    result.portfolioRisk = m_host.CalculatePortfolioRiskAfterTrade(tradeRisk);
    result.severity = ERROR_LEVEL_INFO;

    CJsonLogger::LogRiskEvent("RiskGateApprove", request.symbol, "APPROVED",
        StringFormat("riskPercent=%.2f portfolioRisk=%.2f lot=%.2f", result.riskPercent, result.portfolioRisk, result.adjustedLotSize),
        result.riskPercent, result.adjustedLotSize, corrId);

    m_host.LogValidationResult(request, result);

    CJsonLogger::ClearCorrelationId();
    return result;
}

bool CRiskValidationPipeline::ValidateBasicParameters(const STradeValidationRequest &request, string &message)
{
    if(!IsWired())
    {
        message = "Risk validation pipeline is not wired";
        return false;
    }
    SyncConfig();

    if(StringLen(request.symbol) == 0)
    {
        message = "Empty symbol";
        return false;
    }
    
    if(!m_host.IsSymbolDataValid(request.symbol))
    {
        message = "Invalid symbol data for " + request.symbol;
        return false;
    }
    
    if(request.lotSize <= 0)
    {
        message = "Invalid lot size: " + DoubleToString(request.lotSize, 3);
        return false;
    }
    
    double maxLot = SymbolInfoDouble(request.symbol, SYMBOL_VOLUME_MAX);

    if(maxLot > 0.0 && request.lotSize > maxLot)
    {
        message = StringFormat("Lot %.4f exceeds broker max %.4f for %s", request.lotSize, maxLot, request.symbol);
        return false;
    }
    
    if(request.stopLossPips <= 0)
    {
        PrintFormat("[RISK-GATE] Rejected %s %s: Missing stop loss (strategy=%s, SL=%.1f pips)",
                    request.symbol, EnumToString(request.orderType), request.strategy, request.stopLossPips);
        message = "Invalid stop loss: " + DoubleToString(request.stopLossPips, 1) + " pips";
        return false;
    }
    
    if(request.orderType != ORDER_TYPE_BUY && request.orderType != ORDER_TYPE_SELL)
    {
        message = "Invalid order type: " + EnumToString(request.orderType);
        return false;
    }
    
    if(!m_host.CheckAccountTradingPermissions())
    {
        message = "Trading not allowed";
        return false;
    }
    
    return true;
}

bool CRiskValidationPipeline::ValidateRiskLimits(const STradeValidationRequest &request, string &message, double &riskPercent)
{
    if(!IsWired())
    {
        message = "Risk validation pipeline is not wired";
        return false;
    }
    SyncConfig();

    double tradeRisk = m_host.CalculateTradeRisk(request.symbol, request.lotSize, request.stopLossPips);
    
    if(tradeRisk <= 0)
    {
        message = "Unable to calculate trade risk";
        return false;
    }
    
    // riskPercent is currency risk as a 0-100 percent of CRiskMath::GetRiskDenominator = min(balance, equity).
    double riskDenominator = CRiskMath::GetRiskDenominator();
    
    if(riskDenominator <= 0.0)
    {
        message = "Invalid account risk denominator";
        return false;
    }
    
    riskPercent = (tradeRisk / riskDenominator) * 100.0;  // fraction -> 0-100 % scale
    
    if(riskPercent > m_config.maxRiskPerTradePercent)
    {
        message = StringFormat("Risk %.2f%% exceeds maximum %.2f%%", riskPercent, m_config.maxRiskPerTradePercent);
        return false;
    }
    
    if(m_emergencyRiskOverride > 0.0 && riskPercent > m_emergencyRiskOverride)
    {
        message = StringFormat("Emergency risk override exceeded: %.2f%% > %.2f%%", riskPercent, m_emergencyRiskOverride);
        return false;
    }
    
    return true;
}

bool CRiskValidationPipeline::ValidatePortfolioRisk(const STradeValidationRequest &request, const double tradeRiskPercent, string &message, const double ownReservationRiskPercent)
{
    if(!IsWired())
    {
        message = "Risk validation pipeline is not wired";
        return false;
    }
    SyncConfig();

    CPortfolioRiskManager* manager = m_portfolioRiskManager;
    
    if(CheckPointer(manager) == POINTER_INVALID)
    {
        message = "Portfolio risk manager not available";
        return false;
    }
    
    if(m_portfolioRiskManager.HasUnprotectedPositions())
    {
        message = "Open position without protective stop-loss detected";
        return false;
    }
    
    // Same basis as CUnifiedRiskManager::GetRemainingPortfolioRiskPercent (open exposure + reservations). The book
    // already holds THIS trade's provisional reservation, so the caller passes it in to subtract it.
    double openExposureRisk = m_portfolioRiskManager.GetPortfolioRisk();
    double reservedRisk = m_virtualPositionBook.GetReservedRiskPercent() - MathMax(0.0, ownReservationRiskPercent);
    double currentRisk = openExposureRisk + reservedRisk;
    double totalRisk = currentRisk + tradeRiskPercent;
    
    if(totalRisk > m_config.maxPortfolioRiskPercent)
    {
        message = StringFormat("Total portfolio risk %.2f%% would exceed maximum %.2f%%", totalRisk, m_config.maxPortfolioRiskPercent);
        return false;
    }
    
    if(!m_portfolioRiskManager.IsTradeAllowed(request.symbol, request.lotSize))
    {
        string portfolioReason = "";  // no block-reason accessor on the manager yet, so the generic message stands
        message = (portfolioReason != "") ? portfolioReason : "Trade blocked by portfolio risk manager";
        return false;
    }
    
    return true;
}

bool CRiskValidationPipeline::ValidateClusterGovernance(const STradeValidationRequest &request,
                                                        const double tradeRiskPercent,
                                                        string &message)
{
    if(!IsWired())
    {
        message = "Risk validation pipeline is not wired";
        return false;
    }
    SyncConfig();

    if(!m_clusterGovernanceEnabled)
        return true;
    
    string requestClusterCode = CRiskClusterCodec::NormalizeClusterCode(request.clusterCode);
    if(requestClusterCode == "N")
        requestClusterCode = CRiskClusterCodec::NormalizeClusterCode(request.strategyCluster);
    
    if(requestClusterCode == "N")
        return true;
    
    // Cooldown cache: skips the full position scan when this symbol was recently rejected for conflict.
    if(m_clusterMutexEnabled && m_opposingGuard.IsCooldownActive(request.symbol, message))
        return false;
    
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
        CRiskClusterCodec::ParseClusterCodeFromComment(existingComment, existingClusterCode);
        existingClusterCode = CRiskClusterCodec::NormalizeClusterCode(existingClusterCode);
        
        if(existingClusterCode == "N" && existingSymbol == request.symbol)
            existingClusterCode = requestClusterCode;
        
        if(m_clusterMutexEnabled && existingSymbol == request.symbol)
        {
            bool oppositeDirection = ((request.orderType == ORDER_TYPE_BUY && existingType == POSITION_TYPE_SELL) ||
                                      (request.orderType == ORDER_TYPE_SELL && existingType == POSITION_TYPE_BUY));
            if(oppositeDirection &&
               (existingClusterCode == "N" || existingClusterCode != requestClusterCode))
            {
                // Feed the cooldown cache so the next opposing conflict is blocked without a scan.
                            m_opposingGuard.RegisterConflict(request.symbol);
                
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
            clusterOpenRiskPercent += m_host.EstimatePositionRiskPercent(ticket);
        }
    }
    
    int projectedPositions = clusterOpenPositions + 1;
    double projectedRisk = clusterOpenRiskPercent + MathMax(0.0, tradeRiskPercent);
    
    // Per-cluster risk cap first, global default only as the fallback.
    double effectiveClusterRiskCap = m_clusterBudget.GetClusterRiskCap(requestClusterCode,
                                                                       m_maxClusterRiskPercent);
    
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

bool CRiskValidationPipeline::ValidateCorrelationLimits(const STradeValidationRequest &request, string &message, double &correlationRisk)
{
    if(!IsWired())
    {
        message = "Risk validation pipeline is not wired";
        return false;
    }
    SyncConfig();

    return m_tieredCorrelation.ValidateCorrelationLimits(request.symbol, message, correlationRisk,
                                                         m_config.maxPositionsSameBase, m_eaMagicNumber);
}

bool CRiskValidationPipeline::ValidateMarginRequirements(const STradeValidationRequest &request, string &message)
{
    if(!IsWired())
    {
        message = "Risk validation pipeline is not wired";
        return false;
    }
    SyncConfig();

    ENUM_ACCOUNT_MARGIN_MODE marginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
    bool isHedging = (marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
    
    double marginRequired = 0.0;
    double currentPriceLocal = (request.orderType == ORDER_TYPE_BUY) ?
                              SymbolInfoDouble(request.symbol, SYMBOL_ASK) :
                              SymbolInfoDouble(request.symbol, SYMBOL_BID);
    
    if(!OrderCalcMargin(request.orderType, request.symbol, request.lotSize, currentPriceLocal, marginRequired))
    {
        message = "Unable to calculate margin requirement";
        return false;
    }
    
    // Netting mode: an opposite position nets the order out, so margin is re-asked for the net volume; the loop breaks
    // on the first one. Margin is checked on request.lotSize, not the adjustedLotSize the lot floor may still raise below.
    if(!isHedging)
    {
        int totalPositions = PositionsTotal();
        for(int i = 0; i < totalPositions; i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            string posSymbol = PositionGetString(POSITION_SYMBOL);
            if(posSymbol != request.symbol) continue;
            
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            ENUM_POSITION_TYPE reqType = (request.orderType == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
            
            if(posType != reqType)
            {
                double existingVolume = PositionGetDouble(POSITION_VOLUME);
                double netVolume = request.lotSize - existingVolume;
                if(netVolume <= 0.0)
                {
                    // Net volume <= 0: the order only closes existing exposure, so margin 0.0 is intentional here
                    marginRequired = 0.0;
                }
                else
                {
                    double currentPrice = SymbolInfoDouble(request.symbol, SYMBOL_BID);
                    if(currentPrice <= 0.0) currentPrice = SymbolInfoDouble(request.symbol, SYMBOL_ASK);
                    if(!OrderCalcMargin(request.orderType, request.symbol, netVolume, currentPrice, marginRequired))
                    {
                        // Fail closed: marginRequired = 0.0 would pass the affordability check
                        // trivially, so an unresolvable margin must reject the trade.
                        PrintFormat("[RISK-VALIDATION] OrderCalcMargin failed for %s: %d", request.symbol, GetLastError());
                        message = StringFormat("Unable to calculate net margin requirement for %s", request.symbol);
                        return false;
                    }
                }
                break;
            }
        }
    }
    
    return m_marginHealth.CheckFreeMarginAndLevel(marginRequired, isHedging, message);
}

bool CRiskValidationPipeline::ValidateAccountHealth(const STradeValidationRequest &request, string &message)
{
    if(!IsWired())
    {
        message = "Risk validation pipeline is not wired";
        return false;
    }
    SyncConfig();

    double accountBalanceLocal2 = AccountInfoDouble(ACCOUNT_BALANCE);
    if(accountBalanceLocal2 < 100.0)  // MIN_ACCOUNT_BALANCE
    {
        message = StringFormat("Account balance too low: %.2f", accountBalanceLocal2);
        return false;
    }
    
    // Drawdown state comes from the host (CUnifiedRiskManager::GetDrawdownState); only isCriticalActive vetoes here.
    SDrawdownState ddState = m_host.GetDrawdownState();
    if(ddState.isCriticalActive)
    {
        message = StringFormat("Drawdown critical: %.2f%% — trading halted by unified risk manager",
                               ddState.currentDrawdownPct);
        return false;
    }
    
    if(m_portfolioRiskManager.IsEmergencyMode())
    {
        message = "Emergency mode active - trading suspended";
        return false;
    }
    
    return true;
}

#endif // CORE_RISK_RISK_VALIDATION_PIPELINE_MQH
