//+------------------------------------------------------------------+
//| ScalpVolatilityBreakout.mqh                                       |
//| Enter on the first bar that breaks out of a squeeze                |
//| Entry: ATR at 20-bar low + BB breakout + strong bar + RSI confirm  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_SCALP_VOLATILITY_BREAKOUT_MQH
#define CORE_SCALP_SCALP_VOLATILITY_BREAKOUT_MQH

#include "../Strategy/StrategyBase.mqh"

//+------------------------------------------------------------------+
//| CScalpVolatilityBreakout — Squeeze breakout scalper                |
//+------------------------------------------------------------------+
class CScalpVolatilityBreakout : public CStrategyBase
{
private:
    int      m_atrPeriod;
    int      m_bbPeriod;
    double   m_bbDeviation;
    int      m_rsiPeriod;
    int      m_squeezeLookback;       // Bars to check ATR low (20)
    double   m_bodyATRRatio;          // Bar body > 0.5 * ATR threshold
    double   m_tpATRRatio;            // TP = 2.0 * ATR

    double   m_lastSLPips;
    double   m_lastTPPips;

public:
    CScalpVolatilityBreakout(const string symbol = "", const ENUM_TIMEFRAMES timeframe = PERIOD_M1,
                              const int magic = 0) :
        CStrategyBase("ScalpVolBreakout", magic),
        m_atrPeriod(14),
        m_bbPeriod(20),
        m_bbDeviation(2.0),
        m_rsiPeriod(7),
        m_squeezeLookback(20),
        m_bodyATRRatio(0.5),
        m_tpATRRatio(2.0),
        m_lastSLPips(0.0),
        m_lastTPPips(0.0)
    {
        if(StringLen(symbol) > 0)
            m_symbol = symbol;
        if(timeframe > 0)
            m_timeframe = timeframe;
        SetStrategyCluster(SCALP_CLUSTER);
    }

    ~CScalpVolatilityBreakout() {}

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
        return STRATEGY_VOLATILITY_BREAKOUT;
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
            SetDecisionReasonTag("SCALP_VBRK_DISABLED_OR_UNINIT");
            return TRADE_SIGNAL_NONE;
        }

        CIndicatorManager* indMgr = CIndicatorManager::Instance();
        if(indMgr == NULL)
        {
            SetDecisionReasonTag("SCALP_VBRK_NO_INDMGR");
            return TRADE_SIGNAL_NONE;
        }

        //--- Read ATR (need squeezeLookback bars for 20-bar low check)
        int atrHandle = indMgr.GetATRHandle(m_symbol, m_timeframe, m_atrPeriod);
        if(atrHandle == INVALID_HANDLE)
        {
            SetDecisionReasonTag("SCALP_VBRK_NO_ATR");
            return TRADE_SIGNAL_NONE;
        }
        double atr[];
        ArraySetAsSeries(atr, true);
        int atrNeeded = m_squeezeLookback + 1;
        if(CopyBuffer(atrHandle, 0, 0, atrNeeded, atr) < atrNeeded)
        {
            SetDecisionReasonTag("SCALP_VBRK_ATR_COPY_FAIL");
            return TRADE_SIGNAL_NONE;
        }

        //--- Read Bollinger Bands (upper=1, middle=0, lower=2)
        int bbHandle = indMgr.GetBandsHandle(m_symbol, m_timeframe, m_bbPeriod, 0, m_bbDeviation, PRICE_CLOSE);
        if(bbHandle == INVALID_HANDLE)
        {
            SetDecisionReasonTag("SCALP_VBRK_NO_BB");
            return TRADE_SIGNAL_NONE;
        }
        double bbUpper[];
        double bbMiddle[];
        double bbLower[];
        ArraySetAsSeries(bbUpper, true);
        ArraySetAsSeries(bbMiddle, true);
        ArraySetAsSeries(bbLower, true);
        if(CopyBuffer(bbHandle, 1, 0, 1, bbUpper) < 1 ||
           CopyBuffer(bbHandle, 0, 0, 1, bbMiddle) < 1 ||
           CopyBuffer(bbHandle, 2, 0, 1, bbLower) < 1)
        {
            SetDecisionReasonTag("SCALP_VBRK_BB_COPY_FAIL");
            return TRADE_SIGNAL_NONE;
        }

        //--- Read RSI
        int rsiHandle = indMgr.GetRSIHandle(m_symbol, m_timeframe, m_rsiPeriod, PRICE_CLOSE);
        if(rsiHandle == INVALID_HANDLE)
        {
            SetDecisionReasonTag("SCALP_VBRK_NO_RSI");
            return TRADE_SIGNAL_NONE;
        }
        double rsi[];
        ArraySetAsSeries(rsi, true);
        if(CopyBuffer(rsiHandle, 0, 0, 1, rsi) < 1)
        {
            SetDecisionReasonTag("SCALP_VBRK_RSI_COPY_FAIL");
            return TRADE_SIGNAL_NONE;
        }

        //--- Current bar data
        double closePrice = iClose(m_symbol, m_timeframe, 0);
        double openPrice  = iOpen(m_symbol, m_timeframe, 0);
        if(closePrice <= 0.0 || openPrice <= 0.0)
        {
            SetDecisionReasonTag("SCALP_VBRK_NO_PRICE");
            return TRADE_SIGNAL_NONE;
        }

        //--- Condition 1: ATR at 20-bar low (squeeze condition)
        bool atrAtLow = true;
        for(int i = 1; i < m_squeezeLookback; i++)
        {
            if(atr[0] > atr[i])
            {
                atrAtLow = false;
                break;
            }
        }

        //--- Condition 2: Price breaks above BB upper (BUY) or below BB lower (SELL)
        ENUM_TRADE_SIGNAL direction = TRADE_SIGNAL_NONE;
        bool bbBreakoutUp   = (closePrice > bbUpper[0]);
        bool bbBreakoutDown = (closePrice < bbLower[0]);

        if(bbBreakoutUp)
            direction = TRADE_SIGNAL_BUY;
        else if(bbBreakoutDown)
            direction = TRADE_SIGNAL_SELL;
        else
        {
            SetDecisionReasonTag("SCALP_VBRK_NO_BB_BREAK");
            return TRADE_SIGNAL_NONE;
        }

        //--- Condition 3: Bar body > 0.5 * ATR (strong candle)
        double bodySize = MathAbs(closePrice - openPrice);
        bool strongBar = (bodySize > m_bodyATRRatio * atr[0]);

        //--- Condition 4: RSI confirmation
        //    BUY: RSI > 55 (momentum confirmation)
        //    SELL: RSI < 45 (momentum confirmation)
        bool rsiConfirmed = false;
        if(direction == TRADE_SIGNAL_BUY && rsi[0] > 55.0)
            rsiConfirmed = true;
        else if(direction == TRADE_SIGNAL_SELL && rsi[0] < 45.0)
            rsiConfirmed = true;

        //--- Gate: Strong bar and RSI confirmation required
        if(!strongBar)
        {
            SetDecisionReasonTag("SCALP_VBRK_WEAK_BAR");
            return TRADE_SIGNAL_NONE;
        }
        if(!rsiConfirmed)
        {
            SetDecisionReasonTag("SCALP_VBRK_RSI_FAIL");
            return TRADE_SIGNAL_NONE;
        }

        //--- Calculate confidence
        confidence = 0.55;  // Base
        if(atrAtLow)        confidence += 0.15;  // Strong squeeze
        if(strongBar)       confidence += 0.10;
        if(rsiConfirmed)    confidence += 0.10;

        //--- Cap confidence
        confidence = MathMin(confidence, 0.90);

        //--- Calculate SL/TP in pips
        //    TP: 2.0 * ATR(14)
        //    SL: BB middle band distance from current price
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        double slDistance = MathAbs(closePrice - bbMiddle[0]);
        double tpDistance = m_tpATRRatio * atr[0];

        //--- Ensure minimum SL distance (at least 0.5 ATR)
        if(slDistance < 0.5 * atr[0])
            slDistance = 0.5 * atr[0];

        if(point > 0.0)
        {
            m_lastSLPips = slDistance / point;
            m_lastTPPips = tpDistance / point;
        }

        //--- Set reason tag
        string dirStr = (direction == TRADE_SIGNAL_BUY) ? "BUY" : "SELL";
        SetDecisionReasonTag(StringFormat("SCALP_VBRK_%s|SQZ=%d|STR=%d|RSI=%.1f",
                                           dirStr, atrAtLow ? 1 : 0, strongBar ? 1 : 0, rsi[0]));

        return direction;
    }

    //+------------------------------------------------------------------+
    //| Validate parameters                                               |
    //+------------------------------------------------------------------+
    virtual bool ValidateParameters(void) override
    {
        if(m_atrPeriod <= 0) return false;
        if(m_bbPeriod <= 0) return false;
        if(m_bbDeviation <= 0.0) return false;
        if(m_rsiPeriod <= 0) return false;
        if(m_squeezeLookback <= 0) return false;
        if(m_tpATRRatio <= 0.0) return false;
        return true;
    }
};

#endif // CORE_SCALP_SCALP_VOLATILITY_BREAKOUT_MQH
