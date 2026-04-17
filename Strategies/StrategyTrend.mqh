#ifndef __STRATEGY_TREND_MQH__
#define __STRATEGY_TREND_MQH__
#include "../Core/Strategy/StrategyBase.mqh"
// Enhanced Trend Strategy Component Files
#include "TrendFiles/MultiEMASystem.mqh"
#include "TrendFiles/TrendEntryTypes.mqh"
#include "TrendFiles/TrendTrailingStop.mqh"
#include "TrendFiles/ADXPositionSizing.mqh"
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
    // Configuration
    int    m_lastBarProcessed;
    ENUM_TIMEFRAMES m_effectiveTF; // Auto-resolved: chart TF or M30, whichever is higher
    string m_lastRejectReasonTag;
    datetime m_lastRejectLogTime;

    // Resolve the effective analysis timeframe (M30 minimum for trend strategies)
    ENUM_TIMEFRAMES ResolveEffectiveTF(ENUM_TIMEFRAMES chartTF)
    {
        if(chartTF == PERIOD_M1  || chartTF == PERIOD_M2  || chartTF == PERIOD_M3  ||
           chartTF == PERIOD_M4  || chartTF == PERIOD_M5  || chartTF == PERIOD_M6  ||
           chartTF == PERIOD_M10 || chartTF == PERIOD_M12 || chartTF == PERIOD_M15 ||
           chartTF == PERIOD_M20)
            return PERIOD_M30;
        return chartTF;
    }

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
        m_lastBarProcessed(0),
        m_effectiveTF(PERIOD_M30),
        m_lastRejectReasonTag(""),
        m_lastRejectLogTime(0)
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
    }
    //--- Initialization
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
            return false;

        // Resolve effective analysis TF: Trend strategies need structure that only forms
        // on M30+. If the trader is on M1-M20, silently step up to M30 for all sub-components.
        m_effectiveTF = ResolveEffectiveTF(timeframe);

        // Initialize Multi-EMA System (8/21/50/200) on effective TF
        m_emaSystem = new CMultiEMASystem();
        if(m_emaSystem == NULL || !m_emaSystem.Initialize(symbol, m_effectiveTF))
        {
            Print("[TREND v2.0] Failed to initialize Multi-EMA System");
            return false;
        }
        // Initialize Entry Types Engine on effective TF
        m_entryTypes = new CTrendEntryTypes();
        if(m_entryTypes == NULL || !m_entryTypes.Initialize(symbol, m_effectiveTF, m_emaSystem))
        {
            Print("[TREND v2.0] Failed to initialize Entry Types");
            return false;
        }
        // Initialize Trailing Stop System on effective TF
        m_trailingStop = new CTrendTrailingStop();
        if(m_trailingStop == NULL || !m_trailingStop.Initialize(symbol, m_effectiveTF, m_emaSystem))
        {
            Print("[TREND v2.0] Failed to initialize Trailing Stop");
            return false;
        }
        // Initialize ADX Position Sizing on effective TF
        m_adxSizing = new CADXPositionSizing();
        if(m_adxSizing == NULL || !m_adxSizing.Initialize(symbol, m_effectiveTF))
        {
            Print("[TREND v2.0] Failed to initialize ADX Sizing");
            return false;
        }

        // Scale ADX thresholds by effective TF so faster frames tolerate lower ADX.
        // M30: noTrend=15, normal at 28 | H1: 18/30 | H4+: 20/35 (original defaults)
        if(m_effectiveTF == PERIOD_M30)
            m_adxSizing.SetThresholds(15.0, 20.0, 28.0, 40.0);
        else if(m_effectiveTF == PERIOD_H1)
            m_adxSizing.SetThresholds(18.0, 22.0, 30.0, 42.0);
        // H4 and above keep defaults (20/25/35/45)

        PrintFormat("[TREND v2.0] Strategy initialized for %s | chart=%s | analysis=%s",
                    symbol, EnumToString(timeframe), EnumToString(m_effectiveTF));
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
        // Apply ADX-based confidence adjustment
        double adxMult = m_adxSizing.GetPositionSizeMultiplier();
        confidence = MathMin(1.0, bestEntry.confidence * (0.85 + adxMult * 0.15));
        // Minimum confidence filter
        if(confidence < m_minConfidence)
            return RejectSignal("TREND_LOW_CONFIDENCE");
        // Log the signal
        string trendState = EnumToString(m_emaSystem.GetAlignment());
        SetDecisionReasonTag(bestEntry.direction == TRADE_SIGNAL_BUY ? "TREND_SIGNAL_BUY" : "TREND_SIGNAL_SELL");
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
        lotSize = m_adxSizing.CalculateLotSize(entry.entryPrice, entry.stopLoss); // Base lot adjusted by ADX and Exact distance
        return true;
    }
    //--- Trailing Stop Management
    bool ManageTrailingStop(ulong ticket, ENUM_TRADE_SIGNAL direction, double entryPrice, double currentSL)
    {
        if(m_trailingStop == NULL)
            return false;
        STradeTrailInfo tradeInfo;
        tradeInfo.ticket = ticket;
        tradeInfo.entryPrice = entryPrice;
        tradeInfo.currentSL = currentSL;
        tradeInfo.isBuy = (direction == TRADE_SIGNAL_BUY);
        double lastPrice = SymbolInfoDouble(m_symbol, tradeInfo.isBuy ? SYMBOL_BID : SYMBOL_ASK);
        tradeInfo.highestPrice = tradeInfo.isBuy ? MathMax(entryPrice, lastPrice) : 0.0;
        tradeInfo.lowestPrice  = tradeInfo.isBuy ? DBL_MAX : MathMin(entryPrice, lastPrice);
        double newSL = m_trailingStop.CalculateTrailingStop(tradeInfo);
        if(newSL != currentSL && newSL > 0)
        {
            // Return true to signal that SL should be updated
            return true;
        }
        return false;
    }
    //--- Get New Trailing Stop Value
    double GetNewTrailingStop(ENUM_TRADE_SIGNAL direction, double entryPrice, double currentSL)
    {
        if(m_trailingStop == NULL)
            return currentSL;
        STradeTrailInfo tradeInfo;
        tradeInfo.entryPrice = entryPrice;
        tradeInfo.currentSL = currentSL;
        tradeInfo.isBuy = (direction == TRADE_SIGNAL_BUY);
        double lastPrice = SymbolInfoDouble(m_symbol, tradeInfo.isBuy ? SYMBOL_BID : SYMBOL_ASK);
        tradeInfo.highestPrice = tradeInfo.isBuy ? MathMax(entryPrice, lastPrice) : 0.0;
        tradeInfo.lowestPrice  = tradeInfo.isBuy ? DBL_MAX : MathMin(entryPrice, lastPrice);
        return m_trailingStop.CalculateTrailingStop(tradeInfo);
    }
    //--- Check Early Exit Conditions
    bool ShouldExitEarly(ENUM_TRADE_SIGNAL direction, double entryPrice)
    {
        if(m_trailingStop == NULL)
            return false;
        STradeTrailInfo tradeInfo;
        tradeInfo.entryPrice = entryPrice;
        tradeInfo.isBuy = (direction == TRADE_SIGNAL_BUY);
        double lastPrice = SymbolInfoDouble(m_symbol, tradeInfo.isBuy ? SYMBOL_BID : SYMBOL_ASK);
        tradeInfo.highestPrice = tradeInfo.isBuy ? MathMax(entryPrice, lastPrice) : 0.0;
        tradeInfo.lowestPrice  = tradeInfo.isBuy ? DBL_MAX : MathMin(entryPrice, lastPrice);
        return m_trailingStop.ShouldExitEarly(tradeInfo);
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
    //--- Check if in Trading Session
    bool IsInOptimalTradingTime()
    {
        // Best trend trading during London and NY overlap (8 AM - 12 PM EST)
        // EST is UTC-5
        MqlDateTime dt;
        TimeToStruct(TimeGMT(), dt);
        
        // Convert GMT to EST (UTC-5)
        int estHour = dt.hour - 5;
        if(estHour < 0) estHour += 24;
        
        // Overlap: 8 AM to 12 PM EST
        return (estHour >= 8 && estHour <= 12);
    }
};
#endif // __STRATEGY_TREND_MQH__
