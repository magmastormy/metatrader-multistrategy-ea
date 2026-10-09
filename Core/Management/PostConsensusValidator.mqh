// Validation applied AFTER a consensus decision has been produced: hard spread
// cutoff, exogenous (ATR / spread) filters, adaptive quality gate, OFI directional
// confirmation, VPIN toxicity.
// Checks that VETO a trade: no_signal, hard_spread_cutoff (spread in points vs
// m_hardSpreadCutoffPoints), ATR-ratio crisis (ATR14/ATR50), spread too wide vs
// ATR, insufficient_quality, OFI contradiction. Checks that only scale risk DOWN:
// ATR ratio > 1.5 halves atrRiskScale, VPIN sets a sizing multiplier. The validator
// can reduce risk but can never raise it.
// NOTE: this header is an implementation detail of EnterpriseStrategyManager.mqh and
// is included from there (after the shared free helpers, before the manager class).
// It is not intended to be included standalone.
#ifndef POST_CONSENSUS_VALIDATOR_MQH
#define POST_CONSENSUS_VALIDATOR_MQH

#include "../Utils/Enums.mqh"                     // ENUM_TRADE_SIGNAL, SConsensusDecisionContext
#include "../Utils/JsonLogger.mqh"
#include "../Pipeline/UnifiedSignalPipeline.mqh"  // CUnifiedSignalPipeline::ApplySpreadFilter
#include "../Risk/VPINFilter.mqh"
#include "../Engines/OrderFlowImbalanceEngine.mqh"
#include "../Processing/MultiAssetProfiler.mqh"   // CMultiAssetProfiler, IsSyntheticAssetClass
#include "../../IndicatorManager.mqh"             // CIndicatorManager (ATR handles)
#include "StrategyStateReporter.mqh"              // ConsensusDecisionClassToString (static)

class CEnterpriseStrategyManager;   // forward: held only as a const pointer

// Must stay a global struct: CPostConsensusValidator is declared before the manager,
// and MQL5 cannot name a type nested inside a class that is not yet declared.
// Also keeps clear of the unrelated SValidationResult in Core/Utils/Enums.mqh
// (approved/message), whose name this one used to shadow.
struct SPostConsensusValidation
{
    bool   passed;
    string vetoReason;
    double qualityScore;
    double tradeConfidence;
    double atrRiskScale;
    double spreadScore;
    double atrRatio;
    bool   atrReady;
    double atrValue;
    double atrLongValue;

    SPostConsensusValidation() : passed(true), qualityScore(0), tradeConfidence(0),
                                 atrRiskScale(1.0), spreadScore(0), atrRatio(0),
                                 atrReady(false), atrValue(0), atrLongValue(0) {}
};

// Post-consensus validation facade over CEnterpriseStrategyManager
class CPostConsensusValidator
{
private:
    const CEnterpriseStrategyManager* m_src;

    //--- Validator configuration (owned here; no reader outside the validator methods)
    double m_validatorIntrabarMinQuality;
    double m_validatorNewBarMinQuality;
    double m_hardSpreadCutoffPoints;
    bool   m_spikeHunterEnabled;
    bool   m_enableOFIProxy;
    bool   m_enableVPINFilter;
    double m_baseSpreadATRRatio;
    double m_syntheticSpreadATRRatio;
    double m_lastVPINMultiplier;   // position-size multiplier, consumed by sizing

public:
    CPostConsensusValidator() : m_src(NULL),
                                m_validatorIntrabarMinQuality(0.72),
                                m_validatorNewBarMinQuality(0.75),
                                // [BUGFIX] Cutoff tracks the configured max entry spread (InpMaxEntrySpreadPoints=15000):
                                // synthetic indices spread 1,727-11,140 pts, so the old 1000-pt default vetoed every one.
                                m_hardSpreadCutoffPoints(15000.0),
                                m_spikeHunterEnabled(false),
                                m_enableOFIProxy(false),
                                m_enableVPINFilter(false),
                                m_baseSpreadATRRatio(0.30),
                                m_syntheticSpreadATRRatio(0.50),
                                m_lastVPINMultiplier(1.0) {}

    void SetSource(const CEnterpriseStrategyManager* src) { m_src = src; }

    SPostConsensusValidation ValidateSignal(const string symbol, ENUM_TRADE_SIGNAL signal, double confidence,
                                            int confluence, ENUM_SIGNAL_EVAL_MODE evalMode,
                                            const SConsensusDecisionContext& ctx,
                                            ulong scanCycleId, const string corrId = "");
    bool CheckHardSpreadCutoff(const string symbol, ENUM_TRADE_SIGNAL signal, double confidence,
                               int confluence, ulong scanCycleId, SPostConsensusValidation &result,
                               const string corrId = "");
    bool CheckExogenousFilters(const string symbol, ENUM_SIGNAL_EVAL_MODE evalMode,
                               bool &exogenousPass, string &exogenousReason,
                               double &atrValue, double &atrLongValue,
                               bool &atrReady, bool &atrLongReady,
                               SPostConsensusValidation &result,
                               ENUM_TRADE_SIGNAL signal, double confidence);
    bool   CheckOFIConfirmation(const string symbol, ENUM_TRADE_SIGNAL signal, double confidence, ulong scanCycleId);
    bool   CheckVPINFilter(const string symbol, ENUM_TRADE_SIGNAL signal, double confidence, ulong scanCycleId);
    double GetATRDirect(const string symbol, int period, bool &ready);
    double GetATRCrisisThreshold(const string symbol);
    bool   IsSyntheticSymbolForValidation(const string symbol);
    double GetAdaptiveQualityThreshold(const SConsensusDecisionContext& ctx, ENUM_SIGNAL_EVAL_MODE evalMode);
    string GetValidationStatusReport() const;
    double GetLastVPINMultiplier() const { return m_lastVPINMultiplier; }

    void SetValidatorConfig(double intrabarMinQuality, double newBarMinQuality, double hardSpreadCutoff,
                            bool spikeHunterEnabled, bool enableOFI, bool enableVPIN,
                            double baseSpreadATRRatio, double syntheticSpreadATRRatio);
};

SPostConsensusValidation CPostConsensusValidator::ValidateSignal(const string symbol,
                                                                 ENUM_TRADE_SIGNAL signal,
                                                                 double confidence,
                                                                 int confluence,
                                                                 ENUM_SIGNAL_EVAL_MODE evalMode,
                                                                 const SConsensusDecisionContext& ctx,
                                                                 ulong scanCycleId,
                                                                 const string corrId)
{
    SPostConsensusValidation result;
    result.tradeConfidence = confidence;
    result.qualityScore = ctx.directionalQuality;

    if(signal == TRADE_SIGNAL_NONE)
    {
        result.passed = false;
        result.vetoReason = "no_signal";
        return result;
    }

    if(!CheckHardSpreadCutoff(symbol, signal, confidence, confluence, scanCycleId, result, corrId))
        return result;

    bool exogenousPass = true;
    string exogenousReason = "";
    double atrValue = 0, atrLongValue = 0;
    bool atrReady = false, atrLongReady = false;

    if(!CheckExogenousFilters(symbol, evalMode, exogenousPass, exogenousReason,
                              atrValue, atrLongValue, atrReady, atrLongReady, result, signal, confidence))
    {
        result.passed = false;
        result.vetoReason = exogenousReason;
        return result;
    }

    // Quality gate: the threshold adapts to the consensus decision class
    double qualityThreshold = GetAdaptiveQualityThreshold(ctx, evalMode);

    if(ctx.directionalQuality < qualityThreshold)
    {
        result.passed = false;
        result.vetoReason = "insufficient_quality";
        result.qualityScore = ctx.directionalQuality;

        if(corrId != "")
        {
            CJsonLogger::LogSignal(symbol, signal, confidence, "VALIDATOR", corrId,
                "{\"event\":\"quality_gate_rejected\",\"class\":\"" + CStrategyStateReporter::ConsensusDecisionClassToString((ENUM_CONSENSUS_DECISION_CLASS)ctx.decisionClass) + "\",\"quality\":" + DoubleToString(ctx.directionalQuality, 3) + "\",\"threshold\":" + DoubleToString(qualityThreshold, 3) + "}");
        }
        PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=quality_gate | class=%s | signal=%s conf=%.2f | quality=%.3f threshold=%.3f",
                    symbol, CStrategyStateReporter::ConsensusDecisionClassToString((ENUM_CONSENSUS_DECISION_CLASS)ctx.decisionClass),
                    EnumToString(signal), confidence, ctx.directionalQuality, qualityThreshold);
        return result;
    }

    if(m_enableOFIProxy && !CheckOFIConfirmation(symbol, signal, confidence, scanCycleId))
    {
        result.passed = false;
        result.vetoReason = "ofi_contradiction";
        return result;
    }

    if(m_enableVPINFilter && !CheckVPINFilter(symbol, signal, confidence, scanCycleId))
    {
        result.passed = false;
        result.vetoReason = "vpin_toxicity";
        return result;
    }

    if(m_spikeHunterEnabled)
    {
        // No-op: the spike monitor is not reachable from the validator.
    }

    // Full-margin circuit breaker and safe-mode kill zone are enforced at higher levels.

    result.passed = true;
    result.vetoReason = "";
    return result;
}

bool CPostConsensusValidator::CheckHardSpreadCutoff(const string symbol,
                                                    ENUM_TRADE_SIGNAL signal,
                                                    double confidence,
                                                    int confluence,
                                                    ulong scanCycleId,
                                                    SPostConsensusValidation &result,
                                                    const string corrId)
{
    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

    if(point <= 0.0) point = 0.00001;
    double spread = (ask > 0.0 && bid > 0.0 && ask >= bid) ? (ask - bid) : 0.0;
    double spreadPts = spread / point;

    if(spreadPts > m_hardSpreadCutoffPoints)
    {
        result.passed = false;
        result.vetoReason = "hard_spread_cutoff";
        result.spreadScore = spreadPts;

        if(CJsonLogger::IsEnabled())
        {
            string jsonData = "{\"filter\":\"hard_spread_cutoff\",\"signal\":\"" + EnumToString(signal) + "\",\"confidence\":" + DoubleToString(confidence, 2) + "\",\"spread_pts\":" + DoubleToString(spreadPts, 1) + "\",\"threshold\":" + DoubleToString(m_hardSpreadCutoffPoints, 1) + "\",\"confluence\":" + IntegerToString(confluence) + "}";
            CJsonLogger::LogWarning("SIGNAL-VALIDATOR", "Signal rejected: hard spread cutoff", "SIGNAL_REJECTED", symbol, corrId, jsonData);
        }

        PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=hard_spread_cutoff | signal=%s conf=%.2f | spread_pts=%.1f threshold=%.1f",
                    symbol, EnumToString(signal), confidence, spreadPts, m_hardSpreadCutoffPoints);
        PrintFormat("[SIGNAL-REJECTED] cycle=%I64u | %s | reason=hard_spread_cutoff | spread_points=%.1f > %.1f | confluence=%d | conf=%.2f",
                    scanCycleId, symbol, spreadPts, m_hardSpreadCutoffPoints, confluence, confidence);
        return false;
    }

    result.spreadScore = spreadPts;
    return true;
}

bool CPostConsensusValidator::CheckExogenousFilters(const string symbol,
                                                    ENUM_SIGNAL_EVAL_MODE evalMode,
                                                    bool &exogenousPass,
                                                    string &exogenousReason,
                                                    double &atrValue,
                                                    double &atrLongValue,
                                                    bool &atrReady,
                                                    bool &atrLongReady,
                                                    SPostConsensusValidation &result,
                                                    ENUM_TRADE_SIGNAL signal,
                                                    double confidence)
{
    exogenousPass = true;
    exogenousReason = "";

    atrValue = GetATRDirect(symbol, 14, atrReady);
    atrLongValue = GetATRDirect(symbol, 50, atrLongReady);

    if(!atrReady || !atrLongReady || atrLongValue <= 1e-9)
    {
        // Missing ATR never vetoes: the signal passes unmeasured
        result.atrReady = false;
        return true;
    }

    result.atrReady = true;
    result.atrValue = atrValue;
    result.atrLongValue = atrLongValue;
    result.atrRatio = atrValue / atrLongValue;
    result.atrRatio = MathMin(result.atrRatio, 10.0);

    // Crisis gate: ATR14/ATR50 above the symbol ceiling vetoes
    double atrCrisisThreshold = GetATRCrisisThreshold(symbol);
    if(result.atrRatio > atrCrisisThreshold)
    {
        exogenousPass = false;
        exogenousReason = StringFormat("ATR ratio crisis gate: %.3f > %.3f (ATR14 %.5f / ATR50 %.5f)",
                                        result.atrRatio, atrCrisisThreshold, atrValue, atrLongValue);
        PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=atr_ratio | signal=%s conf=%.2f | %s",
                    symbol, EnumToString(signal), confidence, exogenousReason);
        return true; // Return true to let caller handle veto
    }
    else if(result.atrRatio > 1.5)
    {
        result.atrRiskScale = 0.5;
        PrintFormat("[RISK-VOL-GATE] %s | atr_ratio=%.3f | action=halve_risk", symbol, result.atrRatio);
    }

    if(atrValue > 0)
    {
        double spreadScore = 0;
        bool isSynthetic = IsSyntheticSymbolForValidation(symbol);
        double effectiveSpreadATRRatio = isSynthetic ? m_syntheticSpreadATRRatio : m_baseSpreadATRRatio;

        CUnifiedSignalPipeline* pipeline = (m_src != NULL) ? m_src.GetPipelineConst() : NULL;
        if(pipeline != NULL)
        {
            if(!pipeline.ApplySpreadFilter(symbol, atrValue, spreadScore, effectiveSpreadATRRatio))
            {
                exogenousPass = false;
                exogenousReason = StringFormat("Spread too wide: ratio=%.4f >= %.4f (ATR %.5f)",
                                                spreadScore, effectiveSpreadATRRatio, atrValue);
            }
        }
        else
        {
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            if(point <= 0.0) point = 0.00001;
            double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
            double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
            double spread = (ask > 0.0 && bid > 0.0 && ask >= bid) ? (ask - bid) : 0.0;
            double maxSpread = atrValue * MathMax(0.01, effectiveSpreadATRRatio);
            if(spread > maxSpread)
            {
                exogenousPass = false;
                exogenousReason = StringFormat("Spread too wide: %.5f > %.5f (ATR %.5f)", spread, maxSpread, atrValue);
            }
        }

        result.spreadScore = spreadScore;
    }

    return exogenousPass;
}

bool CPostConsensusValidator::CheckOFIConfirmation(const string symbol,
                                                   ENUM_TRADE_SIGNAL signal,
                                                   double confidence,
                                                   ulong scanCycleId)
{
    COrderFlowImbalanceEngine* ofiEngine = (m_src != NULL) ? m_src.GetOFIEngineConst() : NULL;

    // Unwired / not warmed up / neutral OFI all pass through. Only a directional OFI
    // that contradicts consensus with |ofi_z| >= 1.0 vetoes; milder divergence is
    // logged but allowed (openness refinement).
    if(ofiEngine == NULL) return true;

    if(!ofiEngine.IsWarmedUp())
    {
        return true;
    }

    ENUM_TRADE_SIGNAL ofiSignal = ofiEngine.GetSignal();

    if(ofiSignal == TRADE_SIGNAL_NONE)
    {
        return true;
    }

    if(ofiSignal != signal)
    {
        double ofiValue = ofiEngine.GetOFI();
        if(MathAbs(ofiValue) >= 1.0)
        {
            PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=ofi_contradiction | signal=%s conf=%.2f | ofi=%s ofi_z=%.2f",
                        symbol, EnumToString(signal), confidence, EnumToString(ofiSignal), ofiValue);
            PrintFormat("[SIGNAL-REJECTED] cycle=%I64u | %s | reason=ofi_contradiction | consensus=%s ofi=%s ofi_z=%.2f | conf=%.2f",
                        scanCycleId, symbol, EnumToString(signal), EnumToString(ofiSignal), ofiValue, confidence);
            return false;
        }
        PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=ofi_mild_contradiction_allowed | signal=%s conf=%.2f | ofi=%s ofi_z=%.2f",
                    symbol, EnumToString(signal), confidence, EnumToString(ofiSignal), ofiValue);
    }

    return true;
}

bool CPostConsensusValidator::CheckVPINFilter(const string symbol,
                                              ENUM_TRADE_SIGNAL signal,
                                              double confidence,
                                              ulong scanCycleId)
{
    CVPINFilter* vpinFilter = (m_src != NULL) ? m_src.GetVPINFilterConst() : NULL;
    if(vpinFilter == NULL || !vpinFilter.IsWarmedUp()) return true;

    double vpinValue = vpinFilter.GetVPIN();
    double mult = vpinFilter.GetPositionSizeMultiplier();

    // VPIN never vetoes: EXTREME (>0.95) sizes down to a multiplier floored at 10%,
    // HIGH (>0.85) applies the filter's multiplier as-is.
    if(vpinValue > 0.95)
    {
        PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=vpin_extreme | signal=%s conf=%.2f | VPIN=%.3f | mult=%.3f (reduced size)",
                    symbol, EnumToString(signal), confidence, vpinValue, mult);
        m_lastVPINMultiplier = MathMax(mult, 0.1);
        return true;
    }

    if(vpinValue > 0.85)
    {
        m_lastVPINMultiplier = mult;
        return true;
    }

    m_lastVPINMultiplier = 1.0;
    return true;
}

double CPostConsensusValidator::GetATRDirect(const string symbol, int period, bool &ready)
{
    ready = false;
    CIndicatorManager* indManager = CIndicatorManager::Instance();
    if(indManager == NULL) return 0;

    ENUM_TIMEFRAMES tf = Period();
    if(tf == PERIOD_CURRENT || tf == 0) tf = PERIOD_M15;

    int handle = indManager.GetATRHandle(symbol, tf, period);
    if(handle == INVALID_HANDLE) return 0;

    double buffer[];
    ArraySetAsSeries(buffer, true);
    if(CopyBuffer(handle, 0, 0, 1, buffer) > 0)
    {
        double atrValue = buffer[0];
        if(atrValue > 0.0 && MathIsValidNumber(atrValue))
        {
            ready = true;
            return atrValue;
        }
    }
    return 0;
}

double CPostConsensusValidator::GetATRCrisisThreshold(const string symbol)
{
    if(IsSyntheticSymbolForValidation(symbol))
    {
        return 2.5;
    }
    return 2.0; // ATR14/ATR50 crisis ceiling: 2.5 synthetic, 2.0 forex
}

bool CPostConsensusValidator::IsSyntheticSymbolForValidation(const string symbol)
{
    CMultiAssetProfiler* profiler = (m_src != NULL) ? m_src.GetMultiAssetProfilerConst() : NULL;
    if(profiler != NULL)
    {
        SAssetProfile profile = profiler.GetProfile(symbol);
        return IsSyntheticAssetClass(profile.assetClass);
    }

    // No profiler: synthetic classification falls back to symbol name patterns
    return (StringFind(symbol, "Volatility") >= 0 || StringFind(symbol, "Crash") >= 0 ||
            StringFind(symbol, "Boom") >= 0 || StringFind(symbol, "Jump") >= 0 ||
            StringFind(symbol, "Step") >= 0 || StringFind(symbol, "DEX") >= 0 ||
            StringFind(symbol, "Range") >= 0 || StringFind(symbol, "Gain") >= 0 ||
            StringFind(symbol, "Pain") >= 0 || StringFind(symbol, "Flip") >= 0);
}

double CPostConsensusValidator::GetAdaptiveQualityThreshold(const SConsensusDecisionContext& ctx,
                                                            ENUM_SIGNAL_EVAL_MODE evalMode)
{
    double baseThreshold = (evalMode == EVAL_MODE_INTRABAR)
        ? m_validatorIntrabarMinQuality
        : m_validatorNewBarMinQuality;

    // The effective floor adapts to the consensus decision class; anything
    // unrecognised keeps the configured validator thresholds.
    ENUM_CONSENSUS_DECISION_CLASS decisionClass = (ENUM_CONSENSUS_DECISION_CLASS)ctx.decisionClass;

    switch(decisionClass)
    {
        case CONSENSUS_DECISION_FULL_QUORUM:
            return MathMax(0.40, ctx.directionalQuality * 0.9);

        case CONSENSUS_DECISION_SPARSE_INTRABAR:
            return MathMax(0.45, ctx.directionalQuality * 0.85);

        case CONSENSUS_DECISION_MARGINAL_ADMIT:
            return 0.65;

        case CONSENSUS_DECISION_SOLO_FALLBACK:
            return (evalMode == EVAL_MODE_INTRABAR) ? 0.70 : 0.65;

        default:
            return baseThreshold;
    }
}

string CPostConsensusValidator::GetValidationStatusReport() const
{
    string report = "[EnterpriseStrategyManager::Validation] Config:\n";
    report += "  IntrabarMinQuality=" + DoubleToString(m_validatorIntrabarMinQuality, 2);
    report += " | NewBarMinQuality=" + DoubleToString(m_validatorNewBarMinQuality, 2) + "\n";
    report += "  HardSpreadCutoff=" + DoubleToString(m_hardSpreadCutoffPoints, 1) + " pts\n";
    report += "  OFIProxy=" + (m_enableOFIProxy ? "ON" : "OFF");
    report += " | VPINFilter=" + (m_enableVPINFilter ? "ON" : "OFF");
    report += " | SpikeHunter=" + (m_spikeHunterEnabled ? "ON" : "OFF") + "\n";
    report += "  LastVPINMultiplier=" + DoubleToString(m_lastVPINMultiplier, 3) + "\n";
    return report;
}

void CPostConsensusValidator::SetValidatorConfig(double intrabarMinQuality,
                                                 double newBarMinQuality,
                                                 double hardSpreadCutoff,
                                                 bool spikeHunterEnabled,
                                                 bool enableOFI,
                                                 bool enableVPIN,
                                                 double baseSpreadATRRatio,
                                                 double syntheticSpreadATRRatio)
{
    m_validatorIntrabarMinQuality = MathMax(0.0, MathMin(1.0, intrabarMinQuality));
    m_validatorNewBarMinQuality = MathMax(0.0, MathMin(1.0, newBarMinQuality));
    // [BUGFIX] Floor of 1000 pts keeps a stale/small config from disarming the cutoff; larger settings pass through.
    m_hardSpreadCutoffPoints = MathMax(hardSpreadCutoff, 1000.0);
    m_spikeHunterEnabled = spikeHunterEnabled;
    m_enableOFIProxy = enableOFI;
    m_enableVPINFilter = enableVPIN;
    m_baseSpreadATRRatio = baseSpreadATRRatio;
    m_syntheticSpreadATRRatio = syntheticSpreadATRRatio;
}

#endif // POST_CONSENSUS_VALIDATOR_MQH
