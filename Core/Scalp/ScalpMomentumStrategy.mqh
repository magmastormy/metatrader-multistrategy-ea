//+------------------------------------------------------------------+
//| ScalpMomentumStrategy.mqh                                        |
//| Ride short-term momentum bursts on tick-level data                |
//| Entry: EMA trend + pullback + ATR expanding + tight spread + RSI  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_SCALP_MOMENTUM_STRATEGY_MQH
#define CORE_SCALP_SCALP_MOMENTUM_STRATEGY_MQH

#include "../Strategy/StrategyBase.mqh"

//+------------------------------------------------------------------+
//| CScalpMomentumStrategy — Momentum burst scalper                   |
//+------------------------------------------------------------------+
class CScalpMomentumStrategy : public CStrategyBase
{
private:
    int      m_emaFastPeriod;
    int      m_emaSlowPeriod;
    int      m_atrPeriod;
    int      m_rsiPeriod;
    double   m_pullbackATRRatio;      // Pullback proximity threshold (0.5 ATR)
    double   m_atrExpandRatio;        // ATR expansion threshold (1.05)
    double   m_maxSpreadATRRatio;     // Max spread as fraction of ATR (0.30)
    double   m_tpATRRatio;            // TP = 1.5 * ATR
    double   m_slATRRatio;            // SL = 0.75 * ATR

    double   m_lastSLPips;
    double   m_lastTPPips;

public:
    CScalpMomentumStrategy(const string symbol = "", const ENUM_TIMEFRAMES timeframe = PERIOD_M1,
                            const int magic = 0) :
        CStrategyBase("ScalpMomentum", magic),
        m_emaFastPeriod(5),
        m_emaSlowPeriod(13),
        m_atrPeriod(14),
        m_rsiPeriod(7),
        m_pullbackATRRatio(0.5),
        m_atrExpandRatio(1.05),
        m_maxSpreadATRRatio(0.30),
        m_tpATRRatio(1.5),
        m_slATRRatio(0.75),
        m_lastSLPips(0.0),
        m_lastTPPips(0.0)
    {
        if(StringLen(symbol) > 0)
            m_symbol = symbol;
        if(timeframe > 0)
            m_timeframe = timeframe;
        SetStrategyCluster(SCALP_CLUSTER);
    }

    ~CScalpMomentumStrategy() {}

    //+------------------------------------------------------------------+
    //| Get SL in pips from last signal                                   |
    //+------------------------------------------------------------------+
    double GetLastSLPips() const { return m_lastSLPips; }

    //+------------------------------------------------------------------+
    //| Get TP in pips from last signal                                   |
    //+------------------------------------------------------------------+
    double GetLastTPPips() const { return m_lastTPPips; }

    //+------------------------------------------------------------------+
    //| Strategy type override                                            |
    //+------------------------------------------------------------------+
    virtual ENUM_STRATEGY_TYPE GetType(void) const override
    {
        return STRATEGY_MOMENTUM;
    }

    //+------------------------------------------------------------------+
    //| Execute signal — core logic                                       |
    //| Base class GetSignal() already applies regime/volatility/HTF      |
    //+------------------------------------------------------------------+
    virtual ENUM_TRADE_SIGNAL ExecuteSignal(double &confidence) override
    {
        confidence = 0.0;
        m_lastSLPips = 0.0;
        m_lastTPPips = 0.0;

        if(!m_is_enabled || !m_is_initialized)
        {
            SetDecisionReasonTag("SCALP_MOM_DISABLED_OR_UNINIT");
            return TRADE_SIGNAL_NONE;
        }

        CIndicatorManager* indMgr = CIndicatorManager::Instance();
        if(indMgr == NULL)
        {
            SetDecisionReasonTag("SCALP_MOM_NO_INDMGR");
            return TRADE_SIGNAL_NONE;
        }

        //--- Read EMA fast
        int emaFastHandle = indMgr.GetMAHandle(m_symbol, m_timeframe, m_emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
        if(emaFastHandle == INVALID_HANDLE)
        {
            SetDecisionReasonTag("SCALP_MOM_NO_EMA_FAST");
            return TRADE_SIGNAL_NONE;
        }
        double emaFast[];
        ArraySetAsSeries(emaFast, true);
        if(CopyBuffer(emaFastHandle, 0, 0, 2, emaFast) < 2)
        {
            SetDecisionReasonTag("SCALP_MOM_EMA_FAST_COPY_FAIL");
            return TRADE_SIGNAL_NONE;
        }

        //--- Read EMA slow
        int emaSlowHandle = indMgr.GetMAHandle(m_symbol, m_timeframe, m_emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
        if(emaSlowHandle == INVALID_HANDLE)
        {
            SetDecisionReasonTag("SCALP_MOM_NO_EMA_SLOW");
            return TRADE_SIGNAL_NONE;
        }
        double emaSlow[];
        ArraySetAsSeries(emaSlow, true);
        if(CopyBuffer(emaSlowHandle, 0, 0, 2, emaSlow) < 2)
        {
            SetDecisionReasonTag("SCALP_MOM_EMA_SLOW_COPY_FAIL");
            return TRADE_SIGNAL_NONE;
        }

        //--- Read ATR (need 6 bars for expansion check)
        int atrHandle = indMgr.GetATRHandle(m_symbol, m_timeframe, m_atrPeriod);
        if(atrHandle == INVALID_HANDLE)
        {
            SetDecisionReasonTag("SCALP_MOM_NO_ATR");
            return TRADE_SIGNAL_NONE;
        }
        double atr[];
        ArraySetAsSeries(atr, true);
        if(CopyBuffer(atrHandle, 0, 0, 6, atr) < 6)
        {
            SetDecisionReasonTag("SCALP_MOM_ATR_COPY_FAIL");
            return TRADE_SIGNAL_NONE;
        }

        //--- Read RSI
        int rsiHandle = indMgr.GetRSIHandle(m_symbol, m_timeframe, m_rsiPeriod, PRICE_CLOSE);
        if(rsiHandle == INVALID_HANDLE)
        {
            SetDecisionReasonTag("SCALP_MOM_NO_RSI");
            return TRADE_SIGNAL_NONE;
        }
        double rsi[];
        ArraySetAsSeries(rsi, true);
        if(CopyBuffer(rsiHandle, 0, 0, 1, rsi) < 1)
        {
            SetDecisionReasonTag("SCALP_MOM_RSI_COPY_FAIL");
            return TRADE_SIGNAL_NONE;
        }

        //--- Current price
        double closePrice = iClose(m_symbol, m_timeframe, 0);
        if(closePrice <= 0.0)
        {
            SetDecisionReasonTag("SCALP_MOM_NO_PRICE");
            return TRADE_SIGNAL_NONE;
        }

        //--- Condition 1: EMA trend direction
        bool bullishTrend = (emaFast[0] > emaSlow[0]);
        bool bearishTrend = (emaFast[0] < emaSlow[0]);

        //--- Determine direction
        ENUM_TRADE_SIGNAL direction = TRADE_SIGNAL_NONE;
        if(bullishTrend)
            direction = TRADE_SIGNAL_BUY;
        else if(bearishTrend)
            direction = TRADE_SIGNAL_SELL;
        else
        {
            SetDecisionReasonTag("SCALP_MOM_NO_TREND");
            return TRADE_SIGNAL_NONE;
        }

        //--- Condition 2: Price pullback to near EMA fast (within 0.5 ATR)
        double pullbackDistance = 0.0;
        bool pullbackOk = false;
        if(direction == TRADE_SIGNAL_BUY)
            pullbackDistance = emaFast[0] - closePrice;  // Positive when price below EMA (pullback)
        else
            pullbackDistance = closePrice - emaFast[0];  // Positive when price above EMA (pullback)

        pullbackOk = (MathAbs(pullbackDistance) <= m_pullbackATRRatio * atr[0]);

        //--- Condition 3: ATR expanding (current > 5 bars ago * 1.05)
        bool atrExpanding = false;
        if(atr[5] > 0.0)
            atrExpanding = (atr[0] > atr[5] * m_atrExpandRatio);

        //--- Condition 4: Spread check (spread < 1.5x normal = ATR * 0.3)
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        long   spreadLong = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
        double spreadPrice = (point > 0.0) ? (double)spreadLong * point : 999.0;
        bool spreadOk = (spreadPrice <= m_maxSpreadATRRatio * atr[0]);

        //--- Condition 5: RSI between 40-60 (not overbought/oversold)
        bool rsiOk = (rsi[0] >= 40.0 && rsi[0] <= 60.0);

        //--- Gate: All conditions must pass
        if(!pullbackOk)
        {
            SetDecisionReasonTag("SCALP_MOM_NO_PULLBACK");
            return TRADE_SIGNAL_NONE;
        }
        if(!spreadOk)
        {
            SetDecisionReasonTag("SCALP_MOM_WIDE_SPREAD");
            return TRADE_SIGNAL_NONE;
        }
        if(!rsiOk)
        {
            SetDecisionReasonTag("SCALP_MOM_RSI_EXTREME");
            return TRADE_SIGNAL_NONE;
        }

        //--- Calculate confidence
        confidence = 0.60;  // Base
        if(atrExpanding)    confidence += 0.10;
        if(pullbackOk)      confidence += 0.10;
        if(spreadOk)        confidence += 0.10;

        //--- Cap confidence
        confidence = MathMin(confidence, 0.90);

        //--- Calculate SL/TP in pips
        double slPrice = m_slATRRatio * atr[0];
        double tpPrice = m_tpATRRatio * atr[0];
        if(point > 0.0)
        {
            m_lastSLPips = slPrice / point;
            m_lastTPPips = tpPrice / point;
        }

        //--- Set reason tag
        string dirStr = (direction == TRADE_SIGNAL_BUY) ? "BUY" : "SELL";
        SetDecisionReasonTag(StringFormat("SCALP_MOM_%s|ATR_EXP=%d|PULL=%d|SPR=%d|RSI=%.1f",
                                           dirStr, atrExpanding ? 1 : 0, pullbackOk ? 1 : 0,
                                           spreadOk ? 1 : 0, rsi[0]));

        return direction;
    }

    //+------------------------------------------------------------------+
    //| Validate parameters                                               |
    //+------------------------------------------------------------------+
    virtual bool ValidateParameters(void) override
    {
        if(m_emaFastPeriod <= 0 || m_emaSlowPeriod <= 0) return false;
        if(m_emaFastPeriod >= m_emaSlowPeriod) return false;
        if(m_atrPeriod <= 0) return false;
        if(m_rsiPeriod <= 0) return false;
        if(m_slATRRatio <= 0.0 || m_tpATRRatio <= 0.0) return false;
        return true;
    }
};

#endif // CORE_SCALP_SCALP_MOMENTUM_STRATEGY_MQH
