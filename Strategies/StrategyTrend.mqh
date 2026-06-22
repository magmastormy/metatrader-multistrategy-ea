#ifndef __STRATEGY_TREND_MQH__
#define __STRATEGY_TREND_MQH__
#include "../Core/Strategy/StrategyBase.mqh"
// Enhanced Trend Strategy Component Files
#include "TrendFiles/MultiEMASystem.mqh"
#include "TrendFiles/TrendEntryTypes.mqh"
#include "TrendFiles/TrendTrailingStop.mqh"
#include "TrendFiles/ADXPositionSizing.mqh"
#include "TrendFiles/TrendSignalEnhancers.mqh"
// Risk Manager for AGENTS.md invariant #1
#include "../Core/Risk/UnifiedRiskManager.mqh"
// Batch 103: Hurst/VPIN engine access
#include "../Core/Engines/HurstEngine.mqh"
#include "../Core/Risk/VPINFilter.mqh"
// Batch 103: Asset class detection for ADX thresholds
#include "../Core/Utils/Instruments.mqh"
//+------------------------------------------------------------------+
//| Trend-Following Strategy v2.1                                    |
//| Multi-Speed EMA (8/21/50/200), ADX-based sizing, trailing stops  |
//| Entry Types: Early Trend, Pullback, Continuation, Classic Cross  |
//| Batch 103: Hurst filter, VPIN filter, EMA slope, freshness,     |
//|           trailing stop integration, asset-class ADX thresholds  |
//+------------------------------------------------------------------+
class CStrategyTrend : public CStrategyBase
{
private:
    // Enhanced Components
    CMultiEMASystem*        m_emaSystem;
    CTrendEntryTypes*       m_entryTypes;
    CTrendTrailingStop*     m_trailingStop;
    CADXPositionSizing*     m_adxSizing;
    CTrendSignalEnhancer*   m_signalEnhancer;  // Batch 103: EMA slope + freshness

    // Risk Management (AGENTS.md invariant #1)
    CUnifiedRiskManager*    m_riskManager;

    // Batch 103: Per-symbol engine references (not owned)
    CHurstEngine*           m_hurstEngine;
    CVPINFilter*            m_vpinFilter;

    // Asset class (detected at Init, used for filter relaxation)
    int    m_assetClassId;

    // Configuration
    int    m_lastBarProcessed;
    string m_lastRejectReasonTag;
    datetime m_lastRejectLogTime;
    int    m_signalsGenerated;

    // ENHANCEMENT: Higher-Timeframe Confirmation (Batch 93 - Week 1)
    ENUM_TIMEFRAMES     m_htf;  // Higher timeframe for trend confirmation
    int                 m_htfHandleADX;  // ADX handle for HTF
    int                 m_tradeParamATRHandle;  // Cached ATR handle for GetTradeParameters

    // Configurable ADX thresholds (lowered for synthetic CFDs)
    double              m_adxNoTrendThreshold;
    double              m_adxWeakThreshold;
    double              m_adxNormalThreshold;
    double              m_adxStrongThreshold;

    void LogRejectEvent(const string reasonTag)
    {
        datetime nowTime = TimeCurrent();
        if(reasonTag == m_lastRejectReasonTag && (nowTime - m_lastRejectLogTime) <= 15)
            return;
        if((nowTime - m_lastRejectLogTime) < 5)
            return;

        PrintFormat("[TREND v2.1] Filtered: %s | Symbol=%s | TF=%s",
                    reasonTag, m_symbol, EnumToString(m_timeframe));
        m_lastRejectReasonTag = reasonTag;
        m_lastRejectLogTime = nowTime;
    }

    ENUM_TRADE_SIGNAL RejectSignal(const string reasonTag)
    {
        SetDecisionReasonTag(reasonTag);
        LogRejectEvent(reasonTag);
        return TRADE_SIGNAL_NONE;
    }
public:
    //--- Constructor
    CStrategyTrend(const string name = "Trend Strategy v2.1", int magic = 0) :
        CStrategyBase(name, magic),
        m_emaSystem(NULL),
        m_entryTypes(NULL),
        m_trailingStop(NULL),
        m_adxSizing(NULL),
        m_signalEnhancer(NULL),
        m_riskManager(NULL),
        m_hurstEngine(NULL),
        m_vpinFilter(NULL),
        m_assetClassId(9),  // ASSET_UNIVERSAL until Init detects actual class
        m_lastBarProcessed(0),
        m_lastRejectReasonTag(""),
        m_lastRejectLogTime(0),
        m_signalsGenerated(0),
        m_htf(PERIOD_CURRENT),
        m_htfHandleADX(INVALID_HANDLE),
        m_adxNoTrendThreshold(0),
        m_adxWeakThreshold(25.0),
        m_adxNormalThreshold(30.0),
        m_adxStrongThreshold(40.0)
    {
        m_minConfidence = 0.55; // use base class field
    }
    //--- Set ADX thresholds (called from EA input parameters)
    void SetADXThresholds(double noTrend, double weak, double normal, double strong)
    {
        m_adxNoTrendThreshold = noTrend;
        m_adxWeakThreshold = weak;
        m_adxNormalThreshold = normal;
        m_adxStrongThreshold = strong;
    }
    //--- Batch 103: Set per-symbol Hurst engine (not owned)
    void SetHurstEngine(CHurstEngine* engine) { m_hurstEngine = engine; }
    //--- Batch 103: Set per-symbol VPIN filter (not owned)
    void SetVPINFilter(CVPINFilter* filter) { m_vpinFilter = filter; }
    //--- Destructor
    ~CStrategyTrend()
    {
        Cleanup();
    }
    //--- Cleanup helper
    void Cleanup()
    {
        if(m_emaSystem != NULL) { delete m_emaSystem; m_emaSystem = NULL; }
        if(m_entryTypes != NULL) { delete m_entryTypes; m_entryTypes = NULL; }
        if(m_trailingStop != NULL) { delete m_trailingStop; m_trailingStop = NULL; }
        if(m_adxSizing != NULL) { delete m_adxSizing; m_adxSizing = NULL; }
        if(m_signalEnhancer != NULL) { delete m_signalEnhancer; m_signalEnhancer = NULL; }

        // ENHANCEMENT: Release HTF ADX handle — managed by CIndicatorManager
        m_htfHandleADX = INVALID_HANDLE;

        // Release cached ATR handle for GetTradeParameters — managed by CIndicatorManager
        m_tradeParamATRHandle = INVALID_HANDLE;

        // Risk manager is not owned by this strategy - do NOT delete
        m_riskManager = NULL;
        // Hurst/VPIN engines are not owned - do NOT delete
        m_hurstEngine = NULL;
        m_vpinFilter = NULL;
    }
    //--- Initialization
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;

        // Initialize Multi-EMA System (8/21/50/200)
        m_emaSystem = new CMultiEMASystem();
        if(m_emaSystem == NULL || !m_emaSystem.Initialize(symbol, timeframe))
        {
            Print("[TREND v2.1] Failed to initialize Multi-EMA System");
            return false;
        }
        // Initialize Entry Types Engine
        m_entryTypes = new CTrendEntryTypes();
        if(m_entryTypes == NULL || !m_entryTypes.Initialize(symbol, timeframe, m_emaSystem))
        {
            Print("[TREND v2.1] Failed to initialize Entry Types");
            return false;
        }
        // Initialize Trailing Stop System
        m_trailingStop = new CTrendTrailingStop();
        if(m_trailingStop == NULL || !m_trailingStop.Initialize(symbol, timeframe, m_emaSystem))
        {
            Print("[TREND v2.1] Failed to initialize Trailing Stop");
            return false;
        }
        // Initialize ADX Position Sizing
        m_adxSizing = new CADXPositionSizing();
        if(m_adxSizing == NULL || !m_adxSizing.Initialize(symbol, timeframe))
        {
            Print("[TREND v2.1] Failed to initialize ADX Sizing");
            return false;
        }
        // Batch 103: Apply asset-class-specific ADX thresholds if no EA overrides
        if(m_adxNoTrendThreshold <= 0)
        {
            m_assetClassId = DetectAssetClassId(symbol);
            m_adxSizing.InitForAssetClass(m_assetClassId);
            PrintFormat("[TREND v2.1] Asset-class ADX thresholds applied | Class=%d | Symbol=%s",
                        m_assetClassId, symbol);
        }
        else
        {
            // EA input overrides take precedence
            m_assetClassId = DetectAssetClassId(symbol);
            m_adxSizing.SetThresholds(m_adxNoTrendThreshold, m_adxWeakThreshold, m_adxNormalThreshold, m_adxStrongThreshold);
        }
        PrintFormat("[TREND v2.1] ADX thresholds applied | Symbol=%s | Source=%s",
                    symbol, m_adxNoTrendThreshold > 0 ? "EA_INPUT" : "ASSET_CLASS");

        // Batch 103: Initialize Signal Enhancer (EMA slope + freshness)
        m_signalEnhancer = new CTrendSignalEnhancer();
        if(m_signalEnhancer != NULL)
        {
            m_signalEnhancer.Initialize(symbol, timeframe, m_emaSystem);
        }

        // ARCHITECTURAL FIX: Risk manager is now properly injected via Init() signature
        m_riskManager = GetUnifiedRiskManager();
        if(m_riskManager != NULL)
            Print("[TREND v2.1] UnifiedRiskManager successfully injected - trades will pass through validation gate");
        else
            Print("[TREND v2.1] WARNING: UnifiedRiskManager not provided - risk validation bypassed!");

        // ENHANCEMENT: Setup Higher-Timeframe Confirmation (Batch 93 - Week 1)
        // Use next higher timeframe for trend confirmation
        m_htf = ResolveHigherTimeframe(timeframe);
        m_htfHandleADX = CIndicatorManager::Instance().GetADXHandle(symbol, m_htf, 14);

        if(m_htfHandleADX == INVALID_HANDLE)
        {
            PrintFormat("[TREND v2.1] WARNING: Failed to create HTF ADX handle for %s on %s",
                       symbol, EnumToString(m_htf));
        }
        else
        {
            PrintFormat("[TREND v2.1] HTF confirmation enabled | LTF=%s | HTF=%s | ADX Handle=%d",
                       EnumToString(timeframe), EnumToString(m_htf), m_htfHandleADX);
        }

        PrintFormat("[TREND v2.1] Strategy initialized for %s | TF=%s | Hurst=%s | VPIN=%s",
                    symbol, EnumToString(timeframe),
                    m_hurstEngine != NULL ? "WIRED" : "NULL",
                    m_vpinFilter != NULL ? "WIRED" : "NULL");
        return true;
    }
    //--- Deinitialization
    virtual void Deinit() override
    {
        Cleanup();
        CStrategyBase::Deinit();
    }
    //--- New Bar Handler - Update all components
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override
    {
        if(!IsEnabled() || !m_is_initialized)
            return;
        if(symbol != m_symbol || timeframe != m_timeframe)
            return;
        int currentBar = iBars(m_symbol, m_timeframe);
        if(currentBar == m_lastBarProcessed)
            return;
        m_lastBarProcessed = currentBar;
        // Update all components on new bar
        if(m_emaSystem != NULL) m_emaSystem.Update();
        if(m_entryTypes != NULL) m_entryTypes.Update();
    }
    //--- Main Signal Generation
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("TREND_UNSET");
        if(!IsEnabled() || !m_is_initialized)
            return RejectSignal("TREND_DISABLED_OR_UNINIT");
        if(m_emaSystem == NULL || m_entryTypes == NULL || m_adxSizing == NULL)
            return RejectSignal("TREND_COMPONENTS_NOT_READY");
        // Update components
        m_emaSystem.Update();
        m_entryTypes.Update();

        // Batch 103: Hurst regime filter — asset-class-adjusted thresholds
        // Real instruments: Hurst < 0.45 reject, 0.45–0.50 attenuate by 0.6
        // Synthetics: Hurst < 0.35 reject (algorithmic mean-reversion is inherent)
        double hurstAttenuation = 1.0;
        if(m_hurstEngine != NULL && m_hurstEngine.IsWarmedUp())
        {
            double hurst = m_hurstEngine.GetSnapshot().hurstValue;
            bool isSynthetic = (m_assetClassId >= 4 && m_assetClassId <= 8);
            double rejectThreshold = isSynthetic ? 0.35 : 0.45;
            double attenuateThreshold = isSynthetic ? 0.40 : 0.50;
            if(hurst < rejectThreshold)
            {
                PrintFormat("[TREND-HURST-REJECTED] Hurst=%.4f < %.2f (%s) | Symbol=%s",
                           hurst, rejectThreshold, isSynthetic ? "SYNTHETIC" : "REAL", m_symbol);
                return RejectSignal("TREND_HURST_MEAN_REVERTING");
            }
            if(hurst < attenuateThreshold)
            {
                hurstAttenuation = 0.6;
                PrintFormat("[TREND-HURST-ATTENUATED] Hurst=%.4f | Attenuation=%.2f | %s | Symbol=%s",
                           hurst, hurstAttenuation, isSynthetic ? "SYNTHETIC" : "REAL", m_symbol);
            }
        }

        // Batch 103: VPIN toxicity filter — skip during high toxicity
        if(m_vpinFilter != NULL && m_vpinFilter.IsWarmedUp())
        {
            if(m_vpinFilter.GetVPIN() > 0.5)
                return RejectSignal("TREND_VPIN_TOXIC");
        }

        // Check if ADX allows trading (trend strength filter)
        if(!m_adxSizing.ShouldTrade())
            return RejectSignal("TREND_ADX_FILTERED");

        // Regime Lockout: Ensure directional clarity (pDI vs mDI separation)
        if(!m_adxSizing.IsDirectionallyClear())
            return RejectSignal("TREND_REGIME_CHOP_LOCKOUT");
        // Get best entry signal from all entry types
        STrendEntrySignal bestEntry = m_entryTypes.GetBestEntry();
        if(bestEntry.direction == TRADE_SIGNAL_NONE)
            return RejectSignal("TREND_NO_ENTRY");

        // ENHANCEMENT: Higher-Timeframe Confirmation (Batch 93 - Week 1)
        // Ensure LTF signal aligns with HTF trend direction
        if(!IsHTFTrendConfirmed(bestEntry.direction))
            return RejectSignal("TREND_HTF_CONFLICT");
        // Apply ADX-based confidence adjustment
        double adxMult = m_adxSizing.GetPositionSizeMultiplier();
        confidence = MathMin(1.0, bestEntry.confidence * (0.85 + adxMult * 0.15));

        // Batch 103: EMA slope momentum bonus (+10% for strong momentum)
        if(m_signalEnhancer != NULL && m_signalEnhancer.HasEMAMomentum(bestEntry.direction))
            confidence *= 1.10;

        // Batch 103: Trend freshness scoring (+15% new, -10% mature)
        if(m_signalEnhancer != NULL)
            confidence *= m_signalEnhancer.GetTrendFreshnessMultiplier();

        confidence = MathMin(1.0, confidence);

        // Apply Hurst attenuation for weakly mean-reverting regime (0.45 <= H < 0.50)
        confidence *= hurstAttenuation;

        // Minimum confidence filter
        if(confidence < m_minConfidence)
            return RejectSignal("TREND_LOW_CONFIDENCE");
        // Log the signal
        string trendState = EnumToString(m_emaSystem.GetAlignment());
        SetDecisionReasonTag(bestEntry.direction == TRADE_SIGNAL_BUY ? "TREND_SIGNAL_BUY" : "TREND_SIGNAL_SELL");

        // CRITICAL: Validate through UnifiedRiskManager (AGENTS.md invariant #1)
        if(m_riskManager != NULL)
        {
            STradeValidationRequest request;
            request.symbol = m_symbol;
            request.orderType = (bestEntry.direction == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            request.lotSize = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);  // Use broker minimum
            request.stopLossPips = (bestEntry.stopLoss > 0) ? MathAbs(bestEntry.entryPrice - bestEntry.stopLoss) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
            request.takeProfitPips = (bestEntry.takeProfit > 0) ? MathAbs(bestEntry.takeProfit - bestEntry.entryPrice) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
            request.confidence = confidence;
            request.strategy = GetName();
            request.clusterCode = "";

            CUnifiedRiskManager* riskMgr = m_riskManager;
            SValidationResult result;
            ZeroMemory(result);
            if(riskMgr != NULL)
                result = (*riskMgr).ValidateTradeRequest(request, "TREND");
            if(!result.approved)
            {
                SetDecisionReasonTag("TREND_RISK_REJECTED");
                PrintFormat("[TREND v2.1] Risk rejected %s at %.5f (SL=%.5f TP=%.5f Conf=%.1f%%) Reason=%s",
                           bestEntry.direction == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                           bestEntry.entryPrice, bestEntry.stopLoss, bestEntry.takeProfit, confidence * 100,
                           result.message);
                return TRADE_SIGNAL_NONE;
            }
            confidence *= result.confidenceMultiplier;
        }

        m_signalsGenerated++;
        RecordSignal();

        // CONSENSUS LOGGING (AGENTS.md requirement)
        PrintFormat("[CONSENSUS-DIAG] %s | %s | EntryType: %s | Conf: %.1f%% | Weight: %.2f | Trend: %s | Reason: %s",
                   m_symbol,
                   bestEntry.direction == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   EnumToString(bestEntry.type),
                   confidence * 100,
                   m_weight,
                   trendState,
                   m_lastDecisionReasonTag);

        PrintFormat("[TREND v2.1] %s: %s | Entry: %s | Conf: %.1f%% | Trend: %s | %s",
                   m_symbol,
                   bestEntry.direction == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   EnumToString(bestEntry.type),
                   confidence * 100,
                   trendState,
                   bestEntry.reason);
        return bestEntry.direction;
    }
    //--- Strategy Type
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_TREND; }
    //--- Get Trade Parameters (SL/TP based on entry type)
    bool GetTradeParameters(double &stopLoss, double &takeProfit, double &lotSize)
    {
        if(m_entryTypes == NULL || m_adxSizing == NULL)
            return false;
        STrendEntrySignal entry = m_entryTypes.GetBestEntry();
        if(entry.direction == TRADE_SIGNAL_NONE)
            return false;

        stopLoss = entry.stopLoss;
        takeProfit = entry.takeProfit;

        // ENHANCEMENT: ATR-Based Exit Logic (Batch 93 - Week 1)
        // Calculate dynamic TP levels based on ATR multiples
        // Use cached ATR handle from CIndicatorManager
        if(m_tradeParamATRHandle == INVALID_HANDLE)
            m_tradeParamATRHandle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, 14);
        if(m_tradeParamATRHandle != INVALID_HANDLE)
        {
            double atrBuffer[1];
            if(CopyBuffer(m_tradeParamATRHandle, 0, 0, 1, atrBuffer) == 1 && atrBuffer[0] > 0)
            {
                double atr = atrBuffer[0];

                // Conservative TP: 2x ATR from entry
                double atr_tp = entry.entryPrice + (entry.direction == TRADE_SIGNAL_BUY ? 2.0 : -2.0) * atr;

                // Use ATR-based TP if it's more conservative than original TP
                if(entry.direction == TRADE_SIGNAL_BUY && atr_tp < takeProfit)
                {
                    PrintFormat("[TREND-EXIT] ATR-adjusted TP | Original=%.5f | ATR_TP=%.5f (2x ATR=%.1f pts)",
                               takeProfit, atr_tp, 2.0 * atr / SymbolInfoDouble(m_symbol, SYMBOL_POINT));
                    takeProfit = atr_tp;
                }
                else if(entry.direction == TRADE_SIGNAL_SELL && atr_tp > takeProfit)
                {
                    PrintFormat("[TREND-EXIT] ATR-adjusted TP | Original=%.5f | ATR_TP=%.5f (2x ATR=%.1f pts)",
                               takeProfit, atr_tp, 2.0 * atr / SymbolInfoDouble(m_symbol, SYMBOL_POINT));
                    takeProfit = atr_tp;
                }
            }
        }

        lotSize = m_adxSizing.CalculateLotSize(entry.entryPrice, entry.stopLoss); // Base lot adjusted by ADX and Exact distance
        return true;
    }
    //--- Get Position Size Multiplier
    double GetPositionSizeMultiplier()
    {
        if(m_adxSizing == NULL)
            return 1.0;
        return m_adxSizing.GetPositionSizeMultiplier();
    }
    //--- Get Current Trend State
    STrendState GetCurrentTrendState()
    {
        if(m_emaSystem == NULL)
            return STrendState();
        return m_emaSystem.GetTrendState();
    }
    //--- Get EMA Alignment Score
    ENUM_EMA_ALIGNMENT GetEMAAlignment()
    {
        if(m_emaSystem == NULL)
            return EMA_NEUTRAL;
        return m_emaSystem.GetAlignment();
    }

    //--- Batch 103: Trailing stop integration
    void ApplyTrailingStop(ulong ticket)
    {
        if(m_trailingStop == NULL) return;
        if(!PositionSelectByTicket(ticket)) return;

        double entry = PositionGetDouble(POSITION_PRICE_OPEN);
        double currentSL = PositionGetDouble(POSITION_SL);
        double current = PositionGetDouble(POSITION_PRICE_CURRENT);
        bool isBuy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

        STradeTrailInfo info;
        info.ticket = ticket;
        info.entryPrice = entry;
        info.currentSL = currentSL;
        info.highestPrice = isBuy ? current : entry;
        info.lowestPrice = isBuy ? entry : current;
        info.isBuy = isBuy;
        info.atBreakeven = (currentSL >= entry && isBuy) || (currentSL <= entry && !isBuy);
        info.method = TRAIL_HYBRID;
        info.openTime = (datetime)PositionGetInteger(POSITION_TIME);

        // Step 1: Move SL to breakeven at 1R
        double atr = 0;
        if(m_tradeParamATRHandle == INVALID_HANDLE)
            m_tradeParamATRHandle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, 14);
        if(m_tradeParamATRHandle != INVALID_HANDLE)
        {
            double atrBuf[1];
            if(CopyBuffer(m_tradeParamATRHandle, 0, 0, 1, atrBuf) == 1)
                atr = atrBuf[0];
        }

        if(atr > 0)
        {
            double rr = isBuy ? (current - entry) / atr : (entry - current) / atr;

            // Move to breakeven at 1R
            if(rr >= 1.0 && !info.atBreakeven)
            {
                double beSL = entry + (isBuy ? 5 * SymbolInfoDouble(m_symbol, SYMBOL_POINT) :
                                                -5 * SymbolInfoDouble(m_symbol, SYMBOL_POINT));
                CTradeManager* tm = (CTradeManager*)m_tradeManager;
                if(tm != NULL) tm.ModifyPosition(ticket, beSL, 0);
                return;
            }
        }

        // Step 2: Start trailing after breakeven
        double newSL = m_trailingStop.CalculateTrailingStop(info);
        if(newSL <= 0 || newSL == currentSL) return;

        // Only move SL in favorable direction
        if(isBuy && newSL > currentSL)
        {
            CTradeManager* tm = (CTradeManager*)m_tradeManager;
            if(tm != NULL) tm.ModifyPosition(ticket, newSL, 0);
        }
        else if(!isBuy && newSL < currentSL)
        {
            CTradeManager* tm = (CTradeManager*)m_tradeManager;
            if(tm != NULL) tm.ModifyPosition(ticket, newSL, 0);
        }
    }

private:
    // ENHANCEMENT: Helper Methods (Batch 93 - Week 1)

    // Resolve next higher timeframe for confirmation
    ENUM_TIMEFRAMES ResolveHigherTimeframe(ENUM_TIMEFRAMES currentTF)
    {
        switch(currentTF)
        {
            case PERIOD_M1:  return PERIOD_M5;
            case PERIOD_M5:  return PERIOD_M15;
            case PERIOD_M15: return PERIOD_H1;
            case PERIOD_H1:  return PERIOD_H4;
            case PERIOD_H4:  return PERIOD_D1;
            case PERIOD_D1:  return PERIOD_W1;
            default:         return currentTF; // No higher TF available
        }
    }

    // Check if HTF trend confirms LTF signal
    bool IsHTFTrendConfirmed(ENUM_TRADE_SIGNAL ltfSignal)
    {
        if(m_htfHandleADX == INVALID_HANDLE)
            return true; // Skip HTF check if handle not available

        double adxBuffer[3];
        if(CopyBuffer(m_htfHandleADX, 0, 0, 3, adxBuffer) < 3)
            return true; // Skip on data error

        double htfADX = adxBuffer[0];

        // HTF must have sufficient trend strength — lower threshold for synthetics
        bool isSynthetic = (m_assetClassId >= 4 && m_assetClassId <= 8);
        double htfThreshold = isSynthetic ? 20.0 : 25.0;
        if(htfADX < htfThreshold)
        {
            PrintFormat("[TREND-HTF] Rejected: Weak HTF trend (ADX=%.1f < %.1f, %s)",
                       htfADX, htfThreshold, isSynthetic ? "SYNTHETIC" : "REAL");
            return false;
        }

        // Check HTF directional bias using +DI/-DI
        double plusDIBuffer[3], minusDIBuffer[3];
        if(CopyBuffer(m_htfHandleADX, 1, 0, 3, plusDIBuffer) < 3 ||
           CopyBuffer(m_htfHandleADX, 2, 0, 3, minusDIBuffer) < 3)
            return true; // Skip on data error

        double htfPlusDI = plusDIBuffer[0];
        double htfMinusDI = minusDIBuffer[0];

        // For BUY signals, HTF should be bullish (+DI > -DI)
        if(ltfSignal == TRADE_SIGNAL_BUY && htfPlusDI <= htfMinusDI)
        {
            PrintFormat("[TREND-HTF] Rejected: HTF bearish bias (+DI=%.1f <= -DI=%.1f)",
                       htfPlusDI, htfMinusDI);
            return false;
        }

        // For SELL signals, HTF should be bearish (-DI > +DI)
        if(ltfSignal == TRADE_SIGNAL_SELL && htfMinusDI <= htfPlusDI)
        {
            PrintFormat("[TREND-HTF] Rejected: HTF bullish bias (-DI=%.1f <= +DI=%.1f)",
                       htfMinusDI, htfPlusDI);
            return false;
        }

        PrintFormat("[TREND-HTF] Confirmed | Signal=%s | HTF_ADX=%.1f | +DI=%.1f | -DI=%.1f",
                   ltfSignal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                   htfADX, htfPlusDI, htfMinusDI);

        return true;
    }
};
#endif // __STRATEGY_TREND_MQH__
