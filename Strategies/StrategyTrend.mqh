// Trend-following strategy using multi-EMA system with ADX sizing
// Includes trailing stop, signal enhancers, and regime awareness
#ifndef STRATEGY_TREND_MQH
#define STRATEGY_TREND_MQH
#include "../Core/Strategy/StrategyBase.mqh"
#include "TrendFiles/MultiEMASystem.mqh"
#include "TrendFiles/TrendEntryTypes.mqh"
#include "TrendFiles/TrendTrailingStop.mqh"
#include "TrendFiles/ADXPositionSizing.mqh"
#include "TrendFiles/TrendSignalEnhancers.mqh"
// Risk Manager for AGENTS.md invariant #1
#include "../Core/Risk/UnifiedRiskManager.mqh"
#include "../Utilities/SafeCopyBuffer.mqh"
#include "../Core/Engines/HurstEngine.mqh"
#include "../Core/Risk/VPINFilter.mqh"
// Asset class detection drives the ADX thresholds
#include "../Core/Utils/Instruments.mqh"
// EMAs 8/21/50/200, ADX-sized positions, trailing stop, Hurst/VPIN/EMA-slope/freshness filters
class CStrategyTrend : public CStrategyBase
{
private:
    CMultiEMASystem*        m_emaSystem;
    CTrendEntryTypes*       m_entryTypes;
    CTrendTrailingStop*     m_trailingStop;
    CADXPositionSizing*     m_adxSizing;
    CTrendSignalEnhancer*   m_signalEnhancer;  // EMA slope + freshness

    // Risk ownership: AGENTS.md invariant #1 - uses CStrategyBase::GetUnifiedRiskManager()

    // Per-symbol engine references (not owned - do NOT delete)
    CHurstEngine*           m_hurstEngine;
    CVPINFilter*            m_vpinFilter;

    // Asset class (detected at Init, relaxes the regime filters)
    int    m_assetClassId;

    // Per-bar state
    int    m_lastBarProcessed;
    int    m_signalsGenerated;

    // Higher-timeframe confirmation
    ENUM_TIMEFRAMES     m_htf;
    int                 m_htfHandleADX;
    int                 m_tradeParamATRHandle;  // ATR(14) handle for the trailing stop's R measurement
    int                 m_macdHandle;  // MACD histogram momentum confirmation

    bool MACDConfirmed(ENUM_TRADE_SIGNAL signal)
    {
        if(m_macdHandle == INVALID_HANDLE)
            return true;

        double macdMain[2], macdSignal[2];
        if(!SafeCopyBuffer(m_macdHandle, 0, 1, 2, macdMain) ||
           !SafeCopyBuffer(m_macdHandle, 1, 1, 2, macdSignal))
            return true;

        // Non-series copies are oldest-first: [1] is the newest closed bar, [0] the bar
        // before it. Reading them the other way round confirmed BUYs on a FALLING histogram.
        double histNow = macdMain[1] - macdSignal[1];
        double histPrev = macdMain[0] - macdSignal[0];

        if(signal == TRADE_SIGNAL_BUY)
            return (histNow > histPrev);
        else
            return (histNow < histPrev);
    }
public:
    CStrategyTrend(const string name = "Trend Strategy v2.1", int magic = 0) :
        CStrategyBase(name, magic),
                m_emaSystem(NULL),
                m_entryTypes(NULL),
                m_trailingStop(NULL),
                m_adxSizing(NULL),
                m_signalEnhancer(NULL),
                m_hurstEngine(NULL),
                m_vpinFilter(NULL),
                m_assetClassId(9),  // ASSET_UNIVERSAL until Init detects actual class
                m_lastBarProcessed(0),
                m_signalsGenerated(0),
                m_htf(PERIOD_CURRENT),
                m_htfHandleADX(INVALID_HANDLE),
                m_macdHandle(INVALID_HANDLE)
    {
        m_strategyPrefix = "TREND v2.1";
        m_minConfidence = 0.55; // use base class field
    }
    //--- Set per-symbol Hurst engine (not owned)
    void SetHurstEngine(CHurstEngine* engine) { m_hurstEngine = engine; }
    //--- Set per-symbol VPIN filter (not owned)
    void SetVPINFilter(CVPINFilter* filter) { m_vpinFilter = filter; }
    ~CStrategyTrend()
    {
        Cleanup();
    }
    void Cleanup()
    {
        if(m_emaSystem != NULL) { delete m_emaSystem; m_emaSystem = NULL; }
        if(m_entryTypes != NULL) { delete m_entryTypes; m_entryTypes = NULL; }
        if(m_trailingStop != NULL) { delete m_trailingStop; m_trailingStop = NULL; }
        if(m_adxSizing != NULL) { delete m_adxSizing; m_adxSizing = NULL; }
        if(m_signalEnhancer != NULL) { delete m_signalEnhancer; m_signalEnhancer = NULL; }

        // HTF ADX, ATR and MACD handles belong to CIndicatorManager: invalidate, never release
        m_htfHandleADX = INVALID_HANDLE;

        m_tradeParamATRHandle = INVALID_HANDLE;

        m_macdHandle = INVALID_HANDLE;

        // Hurst/VPIN engines are not owned - do NOT delete
                m_hurstEngine = NULL;
                m_vpinFilter = NULL;
    }
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer, void* unifiedRiskMgr = NULL) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer, unifiedRiskMgr))
            return false;

        m_emaSystem = new CMultiEMASystem();
        if(m_emaSystem == NULL || !m_emaSystem.Initialize(symbol, timeframe))
        {
            Print("[TREND v2.1] Failed to initialize Multi-EMA System");
            return false;
        }
        m_entryTypes = new CTrendEntryTypes();
        if(m_entryTypes == NULL || !m_entryTypes.Initialize(symbol, timeframe, m_emaSystem))
        {
            Print("[TREND v2.1] Failed to initialize Entry Types");
            return false;
        }
        m_trailingStop = new CTrendTrailingStop();
        if(m_trailingStop == NULL || !m_trailingStop.Initialize(symbol, timeframe, m_emaSystem))
        {
            Print("[TREND v2.1] Failed to initialize Trailing Stop");
            return false;
        }
        m_adxSizing = new CADXPositionSizing();
        if(m_adxSizing == NULL || !m_adxSizing.Initialize(symbol, timeframe))
        {
            Print("[TREND v2.1] Failed to initialize ADX Sizing");
            return false;
        }
        // One ADX authority: the per-asset-class table. A wired EA-wide constant
        // would replace that tuning on every symbol, so no input feeds these thresholds.
        m_assetClassId = DetectAssetClassId(symbol);
        m_adxSizing.InitForAssetClass(m_assetClassId);
        PrintFormat("[TREND v2.1] Asset-class ADX thresholds applied | Class=%d | Symbol=%s",
                    m_assetClassId, symbol);

        m_signalEnhancer = new CTrendSignalEnhancer();
        if(m_signalEnhancer != NULL)
        {
            m_signalEnhancer.Initialize(symbol, timeframe, m_emaSystem);
        }

        m_macdHandle = CIndicatorManager::Instance().GetMACDHandle(symbol, timeframe, 12, 26, 9, PRICE_CLOSE);

        // The risk manager arrives through the base class Init()
            if(GetUnifiedRiskManager() != NULL)
                Print("[TREND v2.1] UnifiedRiskManager successfully injected - trades will pass through validation gate");
            else
                Print("[TREND v2.1] WARNING: UnifiedRiskManager not provided - risk validation bypassed!");

        // HTF confirmation uses the next timeframe up
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
    virtual void Deinit() override
    {
        Cleanup();
        CStrategyBase::Deinit();
    }
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
        if(m_emaSystem != NULL) m_emaSystem.Update();
        if(m_entryTypes != NULL) m_entryTypes.Update();
    }
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        SetDecisionReasonTag("TREND_UNSET");
        if(!IsEnabled() || !m_is_initialized)
            return RejectSignal("TREND_DISABLED_OR_UNINIT");
        if(m_emaSystem == NULL || m_entryTypes == NULL || m_adxSizing == NULL)
            return RejectSignal("TREND_COMPONENTS_NOT_READY");
        m_emaSystem.Update();
        m_entryTypes.Update();

        // Hurst regime filter, asset-class-adjusted:
        // real instruments reject below 0.42 and attenuate by x0.6 below 0.47;
        // synthetics reject below 0.35 (algorithmic mean reversion is inherent to them).
        double hurstAttenuation = 1.0;
        if(m_hurstEngine != NULL && m_hurstEngine.IsWarmedUp())
        {
            double hurst = m_hurstEngine.GetSnapshot().hurstValue;
            bool isSynthetic = (m_assetClassId >= 4 && m_assetClassId <= 8);
            double rejectThreshold = isSynthetic ? 0.35 : 0.42;
            double attenuateThreshold = isSynthetic ? 0.40 : 0.47;
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

        // VPIN toxicity gate: stand aside above 0.5
        if(m_vpinFilter != NULL && m_vpinFilter.IsWarmedUp())
        {
            if(m_vpinFilter.GetVPIN() > 0.5)
                return RejectSignal("TREND_VPIN_TOXIC");
        }

        if(!m_adxSizing.ShouldTrade())
            return RejectSignal("TREND_ADX_FILTERED");

        // Regime Lockout: pDI/mDI must be separated; chop is not a trend
        if(!m_adxSizing.IsDirectionallyClear())
            return RejectSignal("TREND_REGIME_CHOP_LOCKOUT");
        STrendEntrySignal bestEntry = m_entryTypes.GetBestEntry();
        if(bestEntry.direction == TRADE_SIGNAL_NONE)
            return RejectSignal("TREND_NO_ENTRY");

        // MTF agreement: the LTF signal must match the HTF direction and strength
        if(!IsHTFTrendConfirmed(bestEntry.direction))
            return RejectSignal("TREND_HTF_CONFLICT");
        if(!MACDConfirmed(bestEntry.direction))
            return RejectSignal("TREND_MACD_MOMENTUM_MISALIGNED");

        // Confidence scales with the ADX position-size multiplier (0.85 to 1.0)
        double adxMult = m_adxSizing.GetPositionSizeMultiplier();
        confidence = MathMin(1.0, bestEntry.confidence * (0.85 + adxMult * 0.15));

        // EMA slope momentum: +10%
        if(m_signalEnhancer != NULL && m_signalEnhancer.HasEMAMomentum(bestEntry.direction))
            confidence *= 1.10;

        // Trend freshness: +15% new, -10% mature
        if(m_signalEnhancer != NULL)
            confidence *= m_signalEnhancer.GetTrendFreshnessMultiplier();

        confidence = MathMin(1.0, confidence);

        // x0.6 while Hurst sits in the borderline band (see the regime filter above)
        confidence *= hurstAttenuation;

        if(confidence < m_minConfidence)
            return RejectSignal("TREND_LOW_CONFIDENCE");
        string trendState = EnumToString(m_emaSystem.GetAlignment());
        SetDecisionReasonTag(bestEntry.direction == TRADE_SIGNAL_BUY ? "TREND_SIGNAL_BUY" : "TREND_SIGNAL_SELL");

        STradeValidationRequest request;
        request.symbol = m_symbol;
        request.orderType = (bestEntry.direction == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
        request.lotSize = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
        request.stopLossPips = (bestEntry.stopLoss > 0) ? MathAbs(bestEntry.entryPrice - bestEntry.stopLoss) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
        request.takeProfitPips = (bestEntry.takeProfit > 0) ? MathAbs(bestEntry.takeProfit - bestEntry.entryPrice) / SymbolInfoDouble(m_symbol, SYMBOL_POINT) : 0;
        request.confidence = confidence;
        request.strategy = GetName();
        request.clusterCode = "";

        SetProposedStops(request.stopLossPips, request.takeProfitPips);
        if(!ValidateWithRiskManager(request, "TREND", confidence))
            return TRADE_SIGNAL_NONE;

        m_signalsGenerated++;
        RecordSignal();

        // [CONSENSUS-DIAG] log required by AGENTS.md §6
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
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_TREND; }
    STrendState GetCurrentTrendState()
    {
        if(m_emaSystem == NULL)
            return STrendState();
        return m_emaSystem.GetTrendState();
    }
    ENUM_EMA_ALIGNMENT GetEMAAlignment()
    {
        if(m_emaSystem == NULL)
            return EMA_NEUTRAL;
        return m_emaSystem.GetAlignment();
    }

    //--- Trailing stop integration
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

        // R is measured in ATR(14) units
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

        // Trailing begins only once the position is past breakeven
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

    bool IsHTFTrendConfirmed(ENUM_TRADE_SIGNAL ltfSignal)
    {
        // Fail closed: a missing handle or a short copy is not HTF confirmation. Returning
        // true there would delete the main protection against taking an LTF wiggle against
        // an HTF trend, which is exactly when the filter matters.
        if(m_htfHandleADX == INVALID_HANDLE)
            return false;

        double adxBuffer[3];
        if(CopyBuffer(m_htfHandleADX, 0, 0, 3, adxBuffer) < 3)
            return false;

        // Raw CopyBuffer into a static array is NOT as-series: [0] is the OLDEST of the
        // window, so with start=0, count=3 the last closed HTF bar (shift 1) is [1].
        double htfADX = adxBuffer[1];

        // HTF must have sufficient trend strength — lower threshold for synthetics
        bool isSynthetic = (m_assetClassId >= 4 && m_assetClassId <= 8);
        double htfThreshold = isSynthetic ? 20.0 : 25.0;
        if(htfADX < htfThreshold)
        {
            PrintFormat("[TREND-HTF] Rejected: Weak HTF trend (ADX=%.1f < %.1f, %s)",
                       htfADX, htfThreshold, isSynthetic ? "SYNTHETIC" : "REAL");
            return false;
        }

        double plusDIBuffer[3], minusDIBuffer[3];
        if(CopyBuffer(m_htfHandleADX, 1, 0, 3, plusDIBuffer) < 3 ||
           CopyBuffer(m_htfHandleADX, 2, 0, 3, minusDIBuffer) < 3)
            return false;  // fail closed on a data error

        double htfPlusDI = plusDIBuffer[1];
        double htfMinusDI = minusDIBuffer[1];

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
#endif
