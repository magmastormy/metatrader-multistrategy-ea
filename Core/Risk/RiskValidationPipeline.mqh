//+------------------------------------------------------------------+
//| RiskValidationPipeline.mqh                                       |
//| Phase E4 extraction from CUnifiedRiskManager (behaviour-preserving)|
//|                                                                  |
//| Owns the EA's trade-approval hot path:                           |
//|   CUnifiedRiskManager::ValidateTradeRequest -> CRiskValidationPipeline::Run |
//|   CUnifiedRiskManager::ValidateBasicParameters   -> moved here    |
//|   CUnifiedRiskManager::ValidateRiskLimits        -> moved here    |
//|   CUnifiedRiskManager::ValidatePortfolioRisk     -> moved here    |
//|   CUnifiedRiskManager::ValidateClusterGovernance -> moved here    |
//|   CUnifiedRiskManager::ValidateCorrelationLimits -> moved here    |
//|   CUnifiedRiskManager::ValidateMarginRequirements-> moved here    |
//|   CUnifiedRiskManager::ValidateAccountHealth     -> moved here    |
//|                                                                  |
//| DESIGN NOTES (MQL5 constraints)                                  |
//| 1. MQL5 has no pointers to structures, so the pipeline cannot     |
//|    hold "&m_config". Instead the owner exposes CopyRiskConfig()   |
//|    through IRiskPipelineHost and the pipeline refreshes its local |
//|    SUnifiedRiskConfig copy at every public entry point. Nothing   |
//|    inside the moved code mutates the config, so a single refresh  |
//|    per entry is exactly equivalent to reading the live struct.    |
//| 2. Everything that is an OWNED CLASS value member of the owner is |
//|    handed over as a non-owning pointer in Initialize(). Those     |
//|    addresses are stable for the owner's lifetime.                 |
//| 3. Everything that depends on owner-private scalars/dynamic       |
//|    arrays (daily risk usage, per-symbol budgets, per-symbol risk  |
//|    overrides, trading-day key) is reached through the             |
//|    IRiskPipelineHost interface so that the ORIGINAL implementation|
//|    keeps running - no logic is duplicated and no state is cloned. |
//| 4. Lazy evaluation and short-circuit order of the original method |
//|    bodies are preserved verbatim.                                 |
//+------------------------------------------------------------------+
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
#include "RiskAdaptiveTuner.mqh"

//+------------------------------------------------------------------+
//| Unified risk configuration                                       |
//| Blueprint 10.4: All percent fields use 0-100 scale               |
//| Phase E4: relocated verbatim from UnifiedRiskManager.mqh because  |
//| both CUnifiedRiskManager and CRiskValidationPipeline need it and  |
//| this header is included first.                                    |
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
//| Trade Request Validation Structure                             |
//| Phase E4: relocated verbatim from UnifiedRiskManager.mqh.         |
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

    // Default constructor - ensures all fields are initialized
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

//+------------------------------------------------------------------+
//| IRiskPipelineHost                                                |
//|                                                                  |
//| Narrow call-back surface the validation pipeline needs from its   |
//| owner (CUnifiedRiskManager). Every entry below is an EXISTING     |
//| CUnifiedRiskManager method - the pipeline never re-implements     |
//| owner logic, it only calls back into it. The single exception is  |
//| CopyRiskConfig(), added because MQL5 forbids struct pointers.     |
//|                                                                  |
//| NOTE (MQL5): pure-virtual (= 0) makes any signature drift a LOUD  |
//| compile error ("cannot instantiate abstract class") instead of a  |
//| silent behaviour regression.                                      |
//+------------------------------------------------------------------+
class IRiskPipelineHost
{
public:
    virtual ~IRiskPipelineHost() {}

    //--- lifecycle / configuration
    virtual bool   IsInitialized() const = 0;
    virtual void   CopyRiskConfig(SUnifiedRiskConfig &outConfig) const = 0;

    //--- circuit breakers and daily budget bookkeeping
    virtual bool   CheckDailyLossLimit() = 0;
    virtual bool   CheckDrawdownCircuitBreaker() = 0;
    virtual void   CheckAndResetDailyLimits() = 0;
    virtual double GetEffectiveDailyRiskUsedPercent(const double additionalRiskPercent) = 0;
    virtual SDrawdownState GetDrawdownState() = 0;

    //--- per-symbol overrides (owner holds the m_riskOverrides array)
    virtual double GetEffectiveMaxDrawdown(const string symbol) const = 0;
    virtual double GetEffectiveRiskPerTrade(const string symbol) const = 0;

    //--- virtual position book bookkeeping (owner logs the reserve/release)
    virtual bool   ReserveVirtualPosition(const string ownerTag,
                                          const STradeValidationRequest &request,
                                          const double riskPercent) = 0;
    virtual void   ReleaseVirtualPosition(const string ownerTag) = 0;

    //--- per-symbol risk budgeting (owner holds the m_symbolBudgets array)
    virtual bool   IsSymbolBudgetAvailable(const string symbol, const double riskPct) = 0;
    virtual double GetSymbolRiskAllocation(const string symbol) = 0;
    virtual double GetSymbolUsedRisk(const string symbol) = 0;

    //--- shared validation helpers kept in the owner
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

//+------------------------------------------------------------------+
//| CRiskValidationPipeline                                          |
//| The 7-step trade validation pipeline extracted from               |
//| CUnifiedRiskManager::ValidateTradeRequest.                        |
//+------------------------------------------------------------------+
class CRiskValidationPipeline
{
private:
    //--- NON-OWNING: owner call-back surface (stable for owner lifetime)
    IRiskPipelineHost*          m_host;

    //--- NON-OWNING: pointers to the owner's value members.
    //--- The owner constructs/destroys them; the pipeline only reads/uses them.
    CRiskCircuitBreaker*        m_circuitBreaker;
    CVirtualPositionBook*       m_virtualPositionBook;
    CPortfolioRiskManager*      m_portfolioRiskManager;
    CRiskAdaptiveTuner*         m_adaptiveTuner;
    CRiskTieredCorrelation*     m_tieredCorrelation;
    CRiskClusterBudget*         m_clusterBudget;
    CRiskMarginHealth*          m_marginHealth;
    CRiskOpposingConflictGuard* m_opposingGuard;
    CRiskValidationStats*       m_validationStats;
    CDerivAssetProfiler*        m_derivAssetProfiler;

    //--- Live snapshot of the owner's config (refreshed at every entry point).
    SUnifiedRiskConfig          m_config;

    //--- Owner scalars mirrored here. Mutable ones are push-synced by the
    //--- owner from the exact same setters that mutate them.
    long                        m_eaMagicNumber;           // SetEAMagicNumber / Initialize
    double                      m_emergencyRiskOverride;   // immutable after construction (5.0)
    bool                        m_clusterGovernanceEnabled;// ConfigureClusterGovernance
    bool                        m_clusterMutexEnabled;     // ConfigureClusterGovernance
    int                         m_maxConcurrentPerCluster; // ConfigureClusterGovernance
    double                      m_maxClusterRiskPercent;   // ConfigureClusterGovernance

    //--- Refresh the local config copy from the owner. Nothing inside the
    //--- moved code paths mutates the config, so one refresh per public
    //--- entry point is equivalent to reading the owner's live struct.
    void SyncConfig()
    {
        if(CheckPointer(m_host) != POINTER_INVALID)
            m_host.CopyRiskConfig(m_config);
    }

    //--- True when every collaborator required by the pipeline is wired.
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
    //+--------------------------------------------------------------+
    //| Constructor - zero init only. All wiring happens in           |
    //| Initialize(), which the owner calls from its constructor body  |
    //| and again from CUnifiedRiskManager::Initialize().              |
    //+--------------------------------------------------------------+
    CRiskValidationPipeline() :
        m_host(NULL),
        m_circuitBreaker(NULL),
        m_virtualPositionBook(NULL),
        m_portfolioRiskManager(NULL),
        m_adaptiveTuner(NULL),
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
        // All stored pointers are NON-OWNING (owner value members). Nothing to free.
    }

    //+--------------------------------------------------------------+
    //| Wire the pipeline to its owner's collaborators and state.      |
    //| All pointers are non-owning and stable for the owner lifetime. |
    //+--------------------------------------------------------------+
    void Initialize(IRiskPipelineHost*          host,
                    CRiskCircuitBreaker*        circuitBreaker,
                    CVirtualPositionBook*       virtualPositionBook,
                    CPortfolioRiskManager*      portfolioRiskManager,
                    CRiskAdaptiveTuner*         adaptiveTuner,
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
        m_adaptiveTuner            = adaptiveTuner;
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

    //--- Push-sync mirrors of owner setters that mutate pipeline-visible state.
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

    //+--------------------------------------------------------------+
    //| Run - the trade validation pipeline.                          |
    //| Relocated verbatim from CUnifiedRiskManager::ValidateTradeRequest. |
    //+--------------------------------------------------------------+
    SValidationResult Run(const STradeValidationRequest &request,
                          const string phaseTag = "runtime",
                          const string corrId = "");

    //--- The 7 validation steps (moved out of CUnifiedRiskManager).
    bool ValidateBasicParameters(const STradeValidationRequest &request, string &message);
    bool ValidateRiskLimits(const STradeValidationRequest &request, string &message, double &riskPercent);
    bool ValidatePortfolioRisk(const STradeValidationRequest &request, const double tradeRiskPercent, string &message);
    bool ValidateClusterGovernance(const STradeValidationRequest &request, const double tradeRiskPercent, string &message);
    bool ValidateCorrelationLimits(const STradeValidationRequest &request, string &message, double &correlationRisk);
    bool ValidateMarginRequirements(const STradeValidationRequest &request, string &message);
    bool ValidateAccountHealth(const STradeValidationRequest &request, string &message);
};

//+------------------------------------------------------------------+
//| Run - relocated body of CUnifiedRiskManager::ValidateTradeRequest |
//|                                                                  |
//| Mechanical substitutions only (no logic change):                  |
//|   m_initialized                        -> m_host.IsInitialized()  |
//|   CheckDailyLossLimit()                -> m_host.CheckDailyLossLimit() |
//|   CheckDrawdownCircuitBreaker()        -> m_host.CheckDrawdownCircuitBreaker() |
//|   GetEffectiveMaxDrawdown()            -> m_host.GetEffectiveMaxDrawdown() |
//|   CheckAndResetDailyLimits()           -> m_host.CheckAndResetDailyLimits() |
//|   GetReservedVirtualRiskPercent()      -> m_virtualPositionBook.GetReservedRiskPercent() |
//|   GetCurrentOpenExposureRiskPercent()  -> m_portfolioRiskManager.GetPortfolioRisk() |
//|   GetEffectiveDailyRiskUsedPercent()   -> m_host.GetEffectiveDailyRiskUsedPercent() |
//|   Reserve/ReleaseVirtualPosition()     -> m_host.Reserve/ReleaseVirtualPosition() |
//|   LogValidationResult()                -> m_host.LogValidationResult() |
//|   CalculatePortfolioRiskAfterTrade()   -> m_host.CalculatePortfolioRiskAfterTrade() |
//|   UpdatePerformanceMetrics()           -> m_host.UpdatePerformanceMetrics() |
//|   IsSymbolBudgetAvailable/GetSymbolRiskAllocation/GetSymbolUsedRisk -> m_host.* |
//|   GetVirtualReservationCount()         -> m_virtualPositionBook.GetReservationCount() |
//|   GetEffectiveRiskPerTrade()           -> m_host.GetEffectiveRiskPerTrade() |
//|   GetSymbolCorrelation()               -> m_tieredCorrelation.GetSymbolCorrelation() |
//+------------------------------------------------------------------+
SValidationResult CRiskValidationPipeline::Run(const STradeValidationRequest &request,
                                               const string phaseTag,
                                               const string corrId)
{
    // Refresh the local view of the owner's config before anything reads it.
    SyncConfig();

    // Set correlation ID for structured logging
    if(corrId != "")
        CJsonLogger::SetCorrelationId(corrId);

    SValidationResult result;
    ZeroMemory(result);
    result.approved = false;
    result.adjustedLotSize = request.lotSize;
    result.severity = ERROR_LEVEL_ERROR;
    // BUGFIX (consensus-conf): ZeroMemory() clobbers the struct's documented
    // default confidenceMultiplier (1.0 = "no change") to 0.0. The risk gate
    // does not compute a confidence adjustment, so on the APPROVED path the
    // multiplier must remain a no-op. Restoring it here prevents callers that
    // do `confidence *= result.confidenceMultiplier` (e.g. ValidateWithRiskManager)
    // from silently zeroing a legitimate high-confidence signal.
    result.confidenceMultiplier = 1.0;

    // Defensive: unreachable in production (CUnifiedRiskManager wires the
    // pipeline in its constructor body). Mirrors the not-initialized path so
    // an unwired pipeline can never dereference a NULL collaborator.
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

    // Daily P&L Loss Limit circuit breaker — reject all trades if halt is active
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

    // ENHANCEMENT: Drawdown Circuit Breaker Check (Batch 93 - Week 1)
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

    // Family-specific drawdown check: if this symbol has a tighter drawdown limit,
    // reject trades on it even when the global circuit breaker hasn't tripped
    double familyMaxDD = m_host.GetEffectiveMaxDrawdown(request.symbol);
    if(familyMaxDD < m_config.drawdownCriticalPercent && m_circuitBreaker.GetMaxDrawdownFromPeak() >= familyMaxDD)
    {
        result.message = StringFormat("Family drawdown limit reached for %s: %.2f%% >= %.1f%%",
                                      request.symbol, m_circuitBreaker.GetMaxDrawdownFromPeak(), familyMaxDD);
        result.severity = ERROR_LEVEL_WARNING;
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

    if(m_virtualPositionBook.HasOpposingReservation(request.symbol, request.clusterCode, request.orderType))
    {
        result.message = StringFormat("Virtual reservation conflict on %s (opposing candidate already reserved)",
                                      request.symbol);
        result.severity = ERROR_LEVEL_WARNING;
        CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "VIRTUAL_RESERVATION_CONFLICT",
            "Opposing candidate already reserved", 0.0, 0.0, corrId);
        CJsonLogger::ClearCorrelationId();
        return result;
    }

    // Reserve virtual position early to account for this trade in portfolio risk
    // Will be released on any rejection, kept on approval
    string virtualOwnerTag = StringFormat("%s_%s_%lld", request.symbol, EnumToString(request.orderType), GetMicrosecondCount());
    bool virtualReserved = m_host.ReserveVirtualPosition(virtualOwnerTag, request, 0.0); // riskPercent will be updated after validation

    // Inline validation from CRiskValidationGate::ValidateTradeRequest
    // 1. Validate basic parameters
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
    
    // 2. Validate risk limits
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
    
    // 3. Validate portfolio risk
    if(!ValidatePortfolioRisk(request, tradeRisk, validationMessage))
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

    // 4. Validate cluster governance (strategy cluster mutex + cap)
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
    
    // 5. Validate correlation limits
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
    
    // 6. Validate margin requirements
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
    
    // 7. Validate account health
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
    
    // All validations passed
    result.approved = true;
    result.message = "Trade request approved";
    result.portfolioRisk = m_host.CalculatePortfolioRiskAfterTrade(tradeRisk);
    result.severity = ERROR_LEVEL_INFO;
    m_validationStats.RecordApproval();
    
    m_host.LogValidationResult(request, result);
    m_host.UpdatePerformanceMetrics(GetMicrosecondCount());

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
            CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "LOT_FLOOR_RISK_CAP",
                StringFormat("Lot %.3f < min %.3f, risk ratio %.1fx > cap %.1fx", result.adjustedLotSize, brokerMinLot, riskRatio, m_config.minLotRiskMultiplier),
                riskRatio, m_config.minLotRiskMultiplier, corrId);
            CJsonLogger::ClearCorrelationId();
            return result;
        }
    }

    // Per-Symbol Risk Budget check (Phase 5)
    if(result.riskPercent > 0.0 && !m_host.IsSymbolBudgetAvailable(request.symbol, result.riskPercent))
    {
        double allocation = m_host.GetSymbolRiskAllocation(request.symbol);
        double used = m_host.GetSymbolUsedRisk(request.symbol);

        // Cold-start bypass: if no positions are open and no virtual reservations,
        // allow the trade even if it exceeds the symbol allocation.
        // The portfolio-level check below will still gate the total risk.
        int openPositionCount = PositionsTotal();
        int virtualReservationCount = m_virtualPositionBook.GetReservationCount();
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
        int virtualReservationCount = m_virtualPositionBook.GetReservationCount();
        bool isColdStart = (openPositionCount == 0 && virtualReservationCount == 0);

        if(isColdStart && result.riskPercent > 0.0 && result.riskPercent <= m_host.GetEffectiveRiskPerTrade(request.symbol))
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
                    CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "PORTFOLIO_RISK_EXCEEDED",
                        StringFormat("Open %.2f%% + reserved %.2f%% + new %.2f%% > limit %.2f%%", openExposureRisk, reservedRisk, result.riskPercent, m_config.maxPortfolioRiskPercent),
                        openExposureRisk + reservedRisk + result.riskPercent, m_config.maxPortfolioRiskPercent, corrId);
                    CJsonLogger::ClearCorrelationId();
                    m_host.ReleaseVirtualPosition(virtualOwnerTag);
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
            ENUM_DERIV_FAMILY reqFamily = m_derivAssetProfiler.DetectFamily(reqSymbol);
        
            for(int i = 0; i < totalPositions; i++)
            {
                ulong ticket = PositionGetTicket(i);
                if(ticket <= 0) continue;
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                // Same symbol family = count it
                ENUM_DERIV_FAMILY posFamily = m_derivAssetProfiler.DetectFamily(posSymbol);
                if(posFamily == reqFamily && reqFamily != ENUM_DERIV_FAMILY(-1))
                    familyPositionCount++;
            }

            // Family position limits by Deriv family type
            int maxFamilyPositions = 3; // default
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
                            CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "FAMILY_POSITION_LIMIT",
                                StringFormat("Family %s positions %d/%d", EnumToString(reqFamily), familyPositionCount, maxFamilyPositions),
                                (double)familyPositionCount, (double)maxFamilyPositions, corrId);
                            CJsonLogger::ClearCorrelationId();
                            m_host.ReleaseVirtualPosition(virtualOwnerTag);
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
            double corr = m_tieredCorrelation.GetSymbolCorrelation(request.symbol, posSymbol);
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
                    CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "CORRELATION_BLOCK",
                        StringFormat("Correlation %.2f >= threshold %.2f", maxCorrelation, m_config.correlationBlockThreshold),
                        maxCorrelation, m_config.correlationBlockThreshold, corrId);
                    CJsonLogger::ClearCorrelationId();
                    m_host.ReleaseVirtualPosition(virtualOwnerTag);
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
            CJsonLogger::LogInfo("RiskGateReduce", 
                StringFormat("Correlation reduce | corr=%.2f | factor=%.2f | lot %.2f->%.2f",
                    maxCorrelation, reduceFactor, originalLot, result.adjustedLotSize), corrId);
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

    double projectedDailyRisk = m_host.GetEffectiveDailyRiskUsedPercent(reservedRisk + MathMax(0.0, result.riskPercent));
        if(projectedDailyRisk > m_config.maxDailyRiskPercent)
        {
            result.approved = false;
            result.severity = ERROR_LEVEL_WARNING;
            result.message = StringFormat("Daily risk limit would be exceeded (%s): %.2f%% + %.2f%% > %.2f%%",
                                          phaseTag, effectiveDailyRisk, result.riskPercent, m_config.maxDailyRiskPercent);
            CJsonLogger::LogRiskEvent("RiskGateReject", request.symbol, "DAILY_RISK_WOULD_EXCEED",
                StringFormat("Effective %.2f%% + new %.2f%% > limit %.2f%%", effectiveDailyRisk, result.riskPercent, m_config.maxDailyRiskPercent),
                projectedDailyRisk, m_config.maxDailyRiskPercent, corrId);
            CJsonLogger::ClearCorrelationId();
            m_host.ReleaseVirtualPosition(virtualOwnerTag);
            return result;
        }

    // All validations passed - APPROVED
    result.approved = true;
    result.message = "Trade request approved";
    result.portfolioRisk = m_host.CalculatePortfolioRiskAfterTrade(tradeRisk);
    result.severity = ERROR_LEVEL_INFO;
    m_validationStats.RecordApproval();
    
    CJsonLogger::LogRiskEvent("RiskGateApprove", request.symbol, "APPROVED",
        StringFormat("riskPercent=%.2f portfolioRisk=%.2f lot=%.2f", result.riskPercent, result.portfolioRisk, result.adjustedLotSize),
        result.riskPercent, result.adjustedLotSize, corrId);
    
    m_host.LogValidationResult(request, result);
    m_host.UpdatePerformanceMetrics(GetMicrosecondCount());
    
    CJsonLogger::ClearCorrelationId();
    return result;
}

//+------------------------------------------------------------------+
//| Step 1 - Basic parameter validation                               |
//| Relocated verbatim from CUnifiedRiskManager::ValidateBasicParameters |
//+------------------------------------------------------------------+
bool CRiskValidationPipeline::ValidateBasicParameters(const STradeValidationRequest &request, string &message)
{
    if(!IsWired())
    {
        message = "Risk validation pipeline is not wired";
        return false;
    }
    SyncConfig();

    // Validate symbol
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
    
    // Validate lot size
    if(request.lotSize <= 0)
    {
        message = "Invalid lot size: " + DoubleToString(request.lotSize, 3);
        return false;
    }
    
    double maxLot = SymbolInfoDouble(request.symbol, SYMBOL_VOLUME_MAX);

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
    if(!m_host.CheckAccountTradingPermissions())
    {
        message = "Trading not allowed";
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Step 2 - Risk limit validation                                    |
//| Relocated verbatim from CUnifiedRiskManager::ValidateRiskLimits    |
//+------------------------------------------------------------------+
bool CRiskValidationPipeline::ValidateRiskLimits(const STradeValidationRequest &request, string &message, double &riskPercent)
{
    if(!IsWired())
    {
        message = "Risk validation pipeline is not wired";
        return false;
    }
    SyncConfig();

    // Calculate trade risk
    double tradeRisk = m_host.CalculateTradeRisk(request.symbol, request.lotSize, request.stopLossPips);
    
    if(tradeRisk <= 0)
    {
        message = "Unable to calculate trade risk";
        return false;
    }
    
    // Convert to percentage using centralized equity-aware denominator for stress-consistent risk sizing.
    double riskDenominator = CRiskMath::GetRiskDenominator();
    
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

//+------------------------------------------------------------------+
//| Step 3 - Portfolio risk validation                                |
//| Relocated verbatim from CUnifiedRiskManager::ValidatePortfolioRisk |
//+------------------------------------------------------------------+
bool CRiskValidationPipeline::ValidatePortfolioRisk(const STradeValidationRequest &request, const double tradeRiskPercent, string &message)
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
    
    // L5-009 FIX: Use same calculation as GetRemainingPortfolioRiskPercent() to include virtual reservations
    double openExposureRisk = m_portfolioRiskManager.GetPortfolioRisk();
    double reservedRisk = m_virtualPositionBook.GetReservedRiskPercent();
    double currentRisk = openExposureRisk + reservedRisk;
    double totalRisk = currentRisk + tradeRiskPercent;
    
    if(totalRisk > m_config.maxPortfolioRiskPercent)
    {
        message = StringFormat("Total portfolio risk %.2f%% would exceed maximum %.2f%%", totalRisk, m_config.maxPortfolioRiskPercent);
        return false;
    }
    
    if(!m_portfolioRiskManager.IsTradeAllowed(request.symbol, request.lotSize))
    {
        string portfolioReason = "";  // GetLastBlockReason would need to be added
        message = (portfolioReason != "") ? portfolioReason : "Trade blocked by portfolio risk manager";
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Step 4 - Cluster governance validation                            |
//| Relocated verbatim from CUnifiedRiskManager::ValidateClusterGovernance |
//+------------------------------------------------------------------+
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
    
    // Fix #9: Opposing conflict cooldown cache — skip full scan if recently rejected for same symbol
    // Phase E2 forwarder -> CRiskOpposingConflictGuard::IsCooldownActive
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
                // Fix #9: Update cooldown cache when a new opposing conflict is detected
                // Phase E2 forwarder -> CRiskOpposingConflictGuard::RegisterConflict
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
    
    // Fix #11: Look up per-cluster risk cap first; fall back to global default
    // Phase E2 forwarder -> CRiskClusterBudget::GetClusterRiskCap
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

//+------------------------------------------------------------------+
//| Step 5 - Correlation limit validation                             |
//| Relocated verbatim from CUnifiedRiskManager::ValidateCorrelationLimits |
//| (still a thin Phase E3 forwarder into CRiskTieredCorrelation)      |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Step 6 - Margin requirement validation                            |
//| Relocated verbatim from CUnifiedRiskManager::ValidateMarginRequirements |
//+------------------------------------------------------------------+
bool CRiskValidationPipeline::ValidateMarginRequirements(const STradeValidationRequest &request, string &message)
{
    if(!IsWired())
    {
        message = "Risk validation pipeline is not wired";
        return false;
    }
    SyncConfig();

    // L5-017: Detect hedging/netting mode
    ENUM_ACCOUNT_MARGIN_MODE marginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
    bool isHedging = (marginMode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
    
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
    
    // L5-017: In netting mode, check if we have an opposite position that would net out
    if(!isHedging)
    {
        // Check for existing opposite position on same symbol
        int totalPositions = PositionsTotal();
        for(int i = 0; i < totalPositions; i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0) continue;
            
            string posSymbol = PositionGetString(POSITION_SYMBOL);
            if(posSymbol != request.symbol) continue;
            
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            ENUM_POSITION_TYPE reqType = (request.orderType == ORDER_TYPE_BUY) ? POSITION_TYPE_BUY : POSITION_TYPE_SELL;
            
            // If opposite position exists, the new position will net out
            if(posType != reqType)
            {
                double existingVolume = PositionGetDouble(POSITION_VOLUME);
                double netVolume = request.lotSize - existingVolume;
                if(netVolume <= 0.0)
                {
                    // New position fully or partially closes existing - no additional margin needed
                    marginRequired = 0.0;
                }
                else
                {
                    // Partially closes - recalculate margin for net volume
                    double currentPrice = SymbolInfoDouble(request.symbol, SYMBOL_BID);
                    if(currentPrice <= 0.0) currentPrice = SymbolInfoDouble(request.symbol, SYMBOL_ASK);
                    if(!OrderCalcMargin(request.orderType, request.symbol, netVolume, currentPrice, marginRequired))
                    {
                        PrintFormat("[RISK-VALIDATION] OrderCalcMargin failed for %s: %d", request.symbol, GetLastError());
                        marginRequired = 0.0; // Conservative fallback
                    }
                }
                break;
            }
        }
    }
    
    // Phase E2 forwarder -> CRiskMarginHealth::CheckFreeMarginAndLevel
    // (free-margin headroom + post-trade margin-level thresholds)
    return m_marginHealth.CheckFreeMarginAndLevel(marginRequired, isHedging, message);
}

//+------------------------------------------------------------------+
//| Step 7 - Account health validation                                |
//| Relocated verbatim from CUnifiedRiskManager::ValidateAccountHealth |
//+------------------------------------------------------------------+
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
    
    // Delegate drawdown check to CUnifiedRiskManager — single source of truth
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
