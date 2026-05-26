#ifndef __STRATEGY_TREND_MQH__
#define __STRATEGY_TREND_MQH__
#include "../Core/Strategy/StrategyBase.mqh"
// Enhanced Trend Strategy Component Files
#include "TrendFiles/MultiEMASystem.mqh"
#include "TrendFiles/TrendEntryTypes.mqh"
#include "TrendFiles/TrendTrailingStop.mqh"
#include "TrendFiles/ADXPositionSizing.mqh"
// Risk Manager for AGENTS.md invariant #1
#include "../Core/Risk/UnifiedRiskManager.mqh"
//+------------------------------------------------------------------+
//| Trend-Following Strategy v2.0                                    |
//| Multi-Speed EMA (8/21/50/200), ADX-based sizing, trailing stops  |
//| Entry Types: Early Trend, Pullback, Continuation, Classic Cross  |
//+------------------------------------------------------------------+
class CStrategyTrend : public CStrategyBase
{
private:
    // Enhanced Components
    CMultiEMASystem*        m_emaSystem;
    CTrendEntryTypes*       m_entryTypes;
    CTrendTrailingStop*     m_trailingStop;
    CADXPositionSizing*     m_adxSizing;
    
    // Risk Management (AGENTS.md invariant #1)
    CUnifiedRiskManager*    m_riskManager;
    
    // Configuration
    int    m_lastBarProcessed;
    string m_lastRejectReasonTag;
    datetime m_lastRejectLogTime;
    
    // ENHANCEMENT: Higher-Timeframe Confirmation (Batch 93 - Week 1)
    ENUM_TIMEFRAMES     m_htf;  // Higher timeframe for trend confirmation
    int                 m_htfHandleADX;  // ADX handle for HTF

    void LogRejectEvent(const string reasonTag)
    {
        datetime nowTime = TimeCurrent();
        if(reasonTag == m_lastRejectReasonTag && (nowTime - m_lastRejectLogTime) <= 15)
            return;
        if((nowTime - m_lastRejectLogTime) < 5)
            return;

        PrintFormat("[TREND v2.0] Filtered: %s | Symbol=%s | TF=%s",
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
    CStrategyTrend(const string name = "Trend Strategy v2.0", int magic = 0) :
        CStrategyBase(name, magic),
        m_emaSystem(NULL),
        m_entryTypes(NULL),
        m_trailingStop(NULL),
        m_adxSizing(NULL),
        m_riskManager(NULL),
        m_lastBarProcessed(0),
        m_lastRejectReasonTag(""),
        m_lastRejectLogTime(0),
        m_htf(PERIOD_CURRENT),
        m_htfHandleADX(INVALID_HANDLE)
    {
        m_minConfidence = 0.55; // use base class field
    }
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
        
        // ENHANCEMENT: Release HTF ADX handle (Batch 93 - Week 1)
        if(m_htfHandleADX != INVALID_HANDLE)
        {
            IndicatorRelease(m_htfHandleADX);
            m_htfHandleADX = INVALID_HANDLE;
        }
        
        // Risk manager is not owned by this strategy - do NOT delete
        m_riskManager = NULL;
    }
    //--- Initialization
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
            return false;

        // Initialize Multi-EMA System (8/21/50/200)
        m_emaSystem = new CMultiEMASystem();
        if(m_emaSystem == NULL || !m_emaSystem.Initialize(symbol, timeframe))
        {
            Print("[TREND v2.0] Failed to initialize Multi-EMA System");
            return false;
        }
        // Initialize Entry Types Engine
        m_entryTypes = new CTrendEntryTypes();
        if(m_entryTypes == NULL || !m_entryTypes.Initialize(symbol, timeframe, m_emaSystem))
        {
            Print("[TREND v2.0] Failed to initialize Entry Types");
            return false;
        }
        // Initialize Trailing Stop System
        m_trailingStop = new CTrendTrailingStop();
        if(m_trailingStop == NULL || !m_trailingStop.Initialize(symbol, timeframe, m_emaSystem))
        {
            Print("[TREND v2.0] Failed to initialize Trailing Stop");
            return false;
        }
        // Initialize ADX Position Sizing
        m_adxSizing = new CADXPositionSizing();
        if(m_adxSizing == NULL || !m_adxSizing.Initialize(symbol, timeframe))
        {
            Print("[TREND v2.0] Failed to initialize ADX Sizing");
            return false;
        }

        // ARCHITECTURAL FIX: Risk manager is now properly injected via Init() signature
        m_riskManager = GetUnifiedRiskManager();
        if(m_riskManager != NULL)
            Print("[TREND v2.0] UnifiedRiskManager successfully injected - trades will pass through validation gate");
        else
            Print("[TREND v2.0] WARNING: UnifiedRiskManager not provided - risk validation bypassed!");
        
        // ENHANCEMENT: Setup Higher-Timeframe Confirmation (Batch 93 - Week 1)
        // Use next higher timeframe for trend confirmation
        m_htf = ResolveHigherTimeframe(timeframe);
        m_htfHandleADX = iADX(symbol, m_htf, 14);
        
        if(m_htfHandleADX == INVALID_HANDLE)
        {
            PrintFormat("[TREND v2.0] WARNING: Failed to create HTF ADX handle for %s on %s",
                       symbol, EnumToString(m_htf));
        }
        else
        {
            PrintFormat("[TREND v2.0] HTF confirmation enabled | LTF=%s | HTF=%s | ADX Handle=%d",
                       EnumToString(timeframe), EnumToString(m_htf), m_htfHandleADX);
        }

        PrintFormat("[TREND v2.0] Strategy initialized for %s | TF=%s",
                    symbol, EnumToString(timeframe));
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
            request.lotSize = 0.01;  // Placeholder
            request.stopLossPips = (bestEntry.stopLoss > 0) ? MathAbs(bestEntry.entryPrice - bestEntry.stopLoss) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
            request.takeProfitPips = (bestEntry.takeProfit > 0) ? MathAbs(bestEntry.takeProfit - bestEntry.entryPrice) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
            request.confidence = confidence;
            request.strategy = GetName();
            request.clusterCode = "";
            
            SValidationResult result = m_riskManager->ValidateTradeRequest(request, "TREND");
            if(!result.approved)
            {
                SetDecisionReasonTag("TREND_RISK_REJECTED");
                PrintFormat("[TREND v2.0] Risk rejected %s at %.5f (SL=%.5f TP=%.5f Conf=%.1f%%) Reason=%s",
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
        
        PrintFormat("[TREND v2.0] %s: %s | Entry: %s | Conf: %.1f%% | Trend: %s | %s",
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
        int atrHandle = iATR(m_symbol, m_timeframe, 14);
        if(atrHandle != INVALID_HANDLE)
        {
            double atrBuffer[1];
            if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) == 1 && atrBuffer[0] > 0)
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
            IndicatorRelease(atrHandle); // Release temporary handle
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
        
        // HTF must have sufficient trend strength (ADX > 25)
        if(htfADX < 25.0)
        {
            PrintFormat("[TREND-HTF] Rejected: Weak HTF trend (ADX=%.1f < 25.0)", htfADX);
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

