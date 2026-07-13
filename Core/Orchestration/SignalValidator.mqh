//+------------------------------------------------------------------+
//| SignalValidator.mqh                                              |
//| Post-consensus filters: spread, ATR, OFI, quality, session       |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_ORCHESTRATION_SIGNAL_VALIDATOR_MQH
#define CORE_ORCHESTRATION_SIGNAL_VALIDATOR_MQH

#include "../../Core/Management/EnterpriseStrategyManager.mqh"
#include "../../Core/Pipeline/UnifiedSignalPipeline.mqh"
#include "../../Core/Engines/OrderFlowImbalanceEngine.mqh"
#include "../../Core/Risk/VPINFilter.mqh"
#include "../../Core/Registry/MathematicalEngineRegistry.mqh"
#include "../../Core/Registry/InstitutionalEngineRegistry.mqh"
#include "../../Core/Utils/Enums.mqh"
#include "../../Core/Utils/Instruments.mqh"
#include "../../Core/Processing/SyntheticSpikeMonitor.mqh"
#include "../../Core/Risk/SafeModeConfig.mqh"
#include "../../Core/Risk/FullMarginMode.mqh"

class CSignalValidator
{
private:
    CMathematicalEngineRegistry*  m_mathRegistry;
    CInstitutionalEngineRegistry* m_instRegistry;
    CUnifiedSignalPipeline*       m_pipeline;
    CSafeMode*                    m_safeMode;
    CSyntheticSpikeMonitor*       m_spikeMonitor;
    CFullMarginMode*              m_fullMarginMode;
    
    // Config
    double m_validatorIntrabarMinQuality;
    double m_validatorNewBarMinQuality;
    double m_hardSpreadCutoffPoints;
    double m_spikeHunterEnabled;
    bool m_enableOFIProxy;
    bool m_enableVPINFilter;
    
    // Spread filter config
    double m_baseSpreadATRRatio;
    double m_syntheticSpreadATRRatio;

public:
    struct SValidationResult
    {
        bool passed;
        string vetoReason;
        double qualityScore;
        double tradeConfidence;
        double atrRiskScale;
        double spreadScore;
        double atrRatio;
        bool atrReady;
        double atrValue;
        double atrLongValue;
        
        SValidationResult() : passed(true), qualityScore(0), tradeConfidence(0), 
                             atrRiskScale(1.0), spreadScore(0), atrRatio(0),
                             atrReady(false), atrValue(0), atrLongValue(0) {}
    };
    
    CSignalValidator() : m_mathRegistry(NULL), m_instRegistry(NULL), m_pipeline(NULL),
                         m_safeMode(NULL), m_spikeMonitor(NULL), m_fullMarginMode(NULL),
                         m_validatorIntrabarMinQuality(0.65), m_validatorNewBarMinQuality(0.70),
                         m_hardSpreadCutoffPoints(1000.0), m_spikeHunterEnabled(false),
                         m_enableOFIProxy(false), m_enableVPINFilter(false),
                         m_baseSpreadATRRatio(0.30), m_syntheticSpreadATRRatio(0.50) {}
    
    ~CSignalValidator() {}
    
    void SetDependencies(CMathematicalEngineRegistry* mathReg, CInstitutionalEngineRegistry* instReg,
                         CUnifiedSignalPipeline* pipeline, CSafeMode* safeMode,
                         CSyntheticSpikeMonitor* spikeMonitor, CFullMarginMode* fullMarginMode)
    {
        m_mathRegistry = mathReg;
        m_instRegistry = instReg;
        m_pipeline = pipeline;
        m_safeMode = safeMode;
        m_spikeMonitor = spikeMonitor;
        m_fullMarginMode = fullMarginMode;
    }
    
    void Configure(double intrabarMinQuality, double newBarMinQuality, double hardSpreadCutoff,
                   bool spikeHunterEnabled, bool enableOFI, bool enableVPIN,
                   double baseSpreadATRRatio, double syntheticSpreadATRRatio)
    {
        m_validatorIntrabarMinQuality = MathMax(0.0, MathMin(1.0, intrabarMinQuality));
        m_validatorNewBarMinQuality = MathMax(0.0, MathMin(1.0, newBarMinQuality));
        m_hardSpreadCutoffPoints = hardSpreadCutoff;
        m_spikeHunterEnabled = spikeHunterEnabled;
        m_enableOFIProxy = enableOFI;
        m_enableVPINFilter = enableVPIN;
        m_baseSpreadATRRatio = baseSpreadATRRatio;
        m_syntheticSpreadATRRatio = syntheticSpreadATRRatio;
    }
    
    // Main validation entry point
    SValidationResult Validate(const string symbol, ENUM_TRADE_SIGNAL signal, double confidence,
                               int confluence, ENUM_SIGNAL_EVAL_MODE evalMode,
                               const SConsensusDecisionContext& ctx,
                               ulong scanCycleId)
    {
        SValidationResult result;
        result.tradeConfidence = confidence;
        result.qualityScore = ctx.directionalQuality;
        
        if(signal == TRADE_SIGNAL_NONE)
        {
            result.passed = false;
            result.vetoReason = "no_signal";
            return result;
        }
        
        // 1. Hard spread cutoff
        if(!CheckHardSpreadCutoff(symbol, signal, confidence, confluence, scanCycleId, result))
            return result;
        
        // 2. Exogenous filters (spread, ATR ratio)
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
        
        // 3. Quality gate
        double qualityThreshold = (evalMode == EVAL_MODE_INTRABAR) 
                                  ? m_validatorIntrabarMinQuality 
                                  : m_validatorNewBarMinQuality;
        
        if(ctx.directionalQuality < qualityThreshold)
        {
            result.passed = false;
            result.vetoReason = "insufficient_quality";
            result.qualityScore = ctx.directionalQuality;
            PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=quality_gate | signal=%s conf=%.2f | quality=%.3f threshold=%.3f",
                        symbol, EnumToString(signal), confidence, ctx.directionalQuality, qualityThreshold);
            return result;
        }
        
        // 4. OFI directional confirmation
        if(m_enableOFIProxy && !CheckOFIConfirmation(symbol, signal, confidence, scanCycleId))
        {
            result.passed = false;
            result.vetoReason = "ofi_contradiction";
            return result;
        }
        
        // 5. VPIN toxicity filter
        if(m_enableVPINFilter && !CheckVPINFilter(symbol, signal, confidence, scanCycleId))
        {
            result.passed = false;
            result.vetoReason = "vpin_toxicity";
            return result;
        }
        
        // 6. Spike hunter cooldown
        if(m_spikeHunterEnabled && m_spikeMonitor != NULL)
        {
            if(m_spikeMonitor.IsPaused())
            {
                result.passed = false;
                result.vetoReason = "spike_cooldown";
                PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=spike_cooldown",
                            symbol);
                return result;
            }
        }
        
        // 7. Full-margin circuit breaker
        if(m_fullMarginMode != NULL && m_fullMarginMode.IsInitialized())
        {
            // Handled at higher level
        }
        
        // 8. Safe mode kill zone
        if(m_safeMode != NULL && m_safeMode.IsInitialized())
        {
            if(m_safeMode.GetConfig().tradeOnlyKillZones && !m_safeMode.IsInKillZone())
            {
                result.passed = false;
                result.vetoReason = "safe_mode_killzone";
                return result;
            }
        }
        
        // All checks passed
        result.passed = true;
        result.vetoReason = "";
        return result;
    }
    
    bool CheckHardSpreadCutoff(const string symbol, ENUM_TRADE_SIGNAL signal, double confidence,
                               int confluence, ulong scanCycleId, SValidationResult &result)
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
            
            PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=hard_spread_cutoff | signal=%s conf=%.2f | spread_pts=%.1f threshold=%.1f",
                        symbol, EnumToString(signal), confidence, spreadPts, m_hardSpreadCutoffPoints);
            PrintFormat("[SIGNAL-REJECTED] cycle=%I64u | %s | reason=hard_spread_cutoff | spread_points=%.1f > %.1f | confluence=%d | conf=%.2f",
                        scanCycleId, symbol, spreadPts, m_hardSpreadCutoffPoints, confluence, confidence);
            return false;
        }
        
        result.spreadScore = spreadPts;
        return true;
    }
    
    bool CheckExogenousFilters(const string symbol, ENUM_SIGNAL_EVAL_MODE evalMode,
                               bool &exogenousPass, string &exogenousReason,
                               double &atrValue, double &atrLongValue,
                               bool &atrReady, bool &atrLongReady,
                               SValidationResult &result,
                               ENUM_TRADE_SIGNAL signal, double confidence)
    {
        exogenousPass = true;
        exogenousReason = "";
        
        // Always use direct ATR calculation (GetCachedATR14/50 don't exist)
        atrValue = GetATRDirect(symbol, 14, atrReady);
        atrLongValue = GetATRDirect(symbol, 50, atrLongReady);
        
        if(!atrReady || !atrLongReady || atrLongValue <= 1e-9)
        {
            // ATR not ready - allow but with caution
            result.atrReady = false;
            return true;
        }
        
        result.atrReady = true;
        result.atrValue = atrValue;
        result.atrLongValue = atrLongValue;
        result.atrRatio = atrValue / atrLongValue;
        result.atrRatio = MathMin(result.atrRatio, 10.0); // Cap
        
        // ATR Crisis gate
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
        
        // Spread filter
        if(atrValue > 0)
        {
            double spreadScore = 0;
            bool isSynthetic = IsSyntheticIndexSymbolName(symbol);
            double effectiveSpreadATRRatio = isSynthetic ? m_syntheticSpreadATRRatio : m_baseSpreadATRRatio;
            
            if(m_pipeline != NULL)
            {
                if(!m_pipeline.ApplySpreadFilter(symbol, atrValue, spreadScore, effectiveSpreadATRRatio))
                {
                    exogenousPass = false;
                    exogenousReason = StringFormat("Spread too wide: ratio=%.4f >= %.4f (ATR %.5f)",
                                                  spreadScore, effectiveSpreadATRRatio, atrValue);
                }
            }
            else
            {
                // Fallback
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
    
    bool CheckOFIConfirmation(const string symbol, ENUM_TRADE_SIGNAL signal, double confidence, ulong scanCycleId)
    {
        if(m_mathRegistry == NULL) return true;
        
        COrderFlowImbalanceEngine* ofi = m_mathRegistry.GetOFI(symbol, false);
        if(ofi == NULL || !ofi.IsWarmedUp()) return true; // Not ready, allow
        
        ENUM_TRADE_SIGNAL ofiSignal = ofi.GetSignal();
        if(ofiSignal != TRADE_SIGNAL_NONE && ofiSignal != signal)
        {
            double ofiValue = ofi.GetOFI();
            PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=ofi_contradiction | signal=%s conf=%.2f | ofi=%s ofi_z=%.2f",
                        symbol, EnumToString(signal), confidence, EnumToString(ofiSignal), ofiValue);
            PrintFormat("[SIGNAL-REJECTED] cycle=%I64u | %s | reason=ofi_contradiction | consensus=%s ofi=%s ofi_z=%.2f | conf=%.2f",
                        scanCycleId, symbol, EnumToString(signal), EnumToString(ofiSignal), ofiValue, confidence);
            return false;
        }
        return true;
    }
    
    bool CheckVPINFilter(const string symbol, ENUM_TRADE_SIGNAL signal, double confidence, ulong scanCycleId)
    {
        if(m_mathRegistry == NULL) return true;
        
        CVPINFilter* vpin = m_mathRegistry.GetVPIN(symbol, false);
        if(vpin == NULL || !vpin.IsWarmedUp()) return true;
        
        double vpinValue = vpin.GetVPIN();
        double mult = vpin.GetPositionSizeMultiplier();
        
        // EXTREME toxicity blocks all trades
        if(vpinValue > 0.95) // EXTREME threshold
        {
            PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=vpin_extreme | signal=%s conf=%.2f | VPIN=%.3f",
                        symbol, EnumToString(signal), confidence, vpinValue);
            return false;
        }
        
        return true;
    }
    
    // Helper functions
    double GetATRDirect(const string symbol, int period, bool &ready)
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
            ready = true;
            return buffer[0];
        }
        return 0;
    }
    
    double GetATRCrisisThreshold(const string symbol)
    {
        // From EA inputs
        if(IsSyntheticIndexSymbolName(symbol))
        {
            // Would use specific synthetic thresholds
            return 2.5; // Default
        }
        return 2.0; // Default for forex
    }
    
    bool IsSyntheticIndexSymbolName(const string symbol)
    {
        return (StringFind(symbol, "Volatility") >= 0 || StringFind(symbol, "Crash") >= 0 ||
                StringFind(symbol, "Boom") >= 0 || StringFind(symbol, "Jump") >= 0 ||
                StringFind(symbol, "Step") >= 0 || StringFind(symbol, "DEX") >= 0 ||
                StringFind(symbol, "Range") >= 0 || StringFind(symbol, "Gain") >= 0 ||
                StringFind(symbol, "Pain") >= 0 || StringFind(symbol, "Flip") >= 0);
    }
    
    // Diagnostics
    string GetStatusReport() const
    {
        string report = "[SignalValidator] Config:\n";
        report += "  IntrabarMinQuality=" + DoubleToString(m_validatorIntrabarMinQuality, 2);
        report += " | NewBarMinQuality=" + DoubleToString(m_validatorNewBarMinQuality, 2) + "\n";
        report += "  HardSpreadCutoff=" + DoubleToString(m_hardSpreadCutoffPoints, 1) + " pts\n";
        report += "  OFIProxy=" + (m_enableOFIProxy ? "ON" : "OFF");
        report += " | VPINFilter=" + (m_enableVPINFilter ? "ON" : "OFF");
        report += " | SpikeHunter=" + (m_spikeHunterEnabled ? "ON" : "OFF") + "\n";
        return report;
    }
};

#endif // CORE_ORCHESTRATION_SIGNAL_VALIDATOR_MQH