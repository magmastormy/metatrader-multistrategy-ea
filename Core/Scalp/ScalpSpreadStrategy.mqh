//+------------------------------------------------------------------+
//| ScalpSpreadStrategy.mqh                                           |
//| Exploit temporary spread widening (market-making lite)             |
//| Entry: Wide spread returning + mean-reversion near EMA + RSI       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_SCALP_SPREAD_STRATEGY_MQH
#define CORE_SCALP_SCALP_SPREAD_STRATEGY_MQH

#include "../Strategy/StrategyBase.mqh"

//+------------------------------------------------------------------+
//| CScalpSpreadStrategy — Spread normalization scalper                |
//+------------------------------------------------------------------+
class CScalpSpreadStrategy : public CStrategyBase
{
private:
    int      m_emaSlowPeriod;
    int      m_atrPeriod;
    int      m_rsiPeriod;
    double   m_wideSpreadATRRatio;    // Spread > 0.6 * ATR / 10 considered wide
    double   m_emaProximityATR;       // Price near EMA threshold (0.3 ATR)
    double   m_tpATRRatio;            // TP = 1.0 * ATR * 0.3
    double   m_slATRRatio;            // SL = ATR * 0.06 (2x normal spread proxy)

    double   m_lastSLPips;
    double   m_lastTPPips;
    long     m_prevSpread;            // Previous tick spread for returning check

public:
    CScalpSpreadStrategy(const string symbol = "", const ENUM_TIMEFRAMES timeframe = PERIOD_M1,
                          const int magic = 0) :
        CStrategyBase("ScalpSpread", magic),
        m_emaSlowPeriod(13),
        m_atrPeriod(14),
        m_rsiPeriod(7),
        m_wideSpreadATRRatio(0.06),     // 0.6 * ATR / 10 = 0.06 * ATR
        m_emaProximityATR(0.3),
        m_tpATRRatio(0.3),              // 1.0 * ATR * 0.3
        m_slATRRatio(0.06),             // ATR * 0.06
        m_lastSLPips(0.0),
        m_lastTPPips(0.0),
        m_prevSpread(0)
    {
        if(StringLen(symbol) > 0)
            m_symbol = symbol;
        if(timeframe > 0)
            m_timeframe = timeframe;
        SetStrategyCluster(MEAN_REVERSION_CLUSTER);
    }

    ~CScalpSpreadStrategy() {}

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
        return STRATEGY_MEAN_REVERSION;
    }

    //+------------------------------------------------------------------+
    //| OnTick — track previous spread for returning detection            |
    //+------------------------------------------------------------------+
    virtual void OnTick() override
    {
        long currentSpread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
        if(currentSpread > 0)
            m_prevSpread = currentSpread;
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
            SetDecisionReasonTag("SCALP_SPRD_DISABLED_OR_UNINIT");
            return TRADE_SIGNAL_NONE;
        }

        CIndicatorManager* indMgr = CIndicatorManager::Instance();
        if(indMgr == NULL)
        {
            SetDecisionReasonTag("SCALP_SPRD_NO_INDMGR");
            return TRADE_SIGNAL_NONE;
        }

        //--- Read ATR
        int atrHandle = indMgr->GetATRHandle(m_symbol, m_timeframe, m_atrPeriod);
        if(atrHandle == INVALID_HANDLE)
        {
            SetDecisionReasonTag("SCALP_SPRD_NO_ATR");
            return TRADE_SIGNAL_NONE;
        }
        double atr[];
        ArraySetAsSeries(atr, true);
        if(CopyBuffer(atrHandle, 0, 0, 1, atr) < 1)
        {
            SetDecisionReasonTag("SCALP_SPRD_ATR_COPY_FAIL");
            return TRADE_SIGNAL_NONE;
        }

        //--- Read EMA slow
        int emaSlowHandle = indMgr->GetMAHandle(m_symbol, m_timeframe, m_emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
        if(emaSlowHandle == INVALID_HANDLE)
        {
            SetDecisionReasonTag("SCALP_SPRD_NO_EMA_SLOW");
            return TRADE_SIGNAL_NONE;
        }
        double emaSlow[];
        ArraySetAsSeries(emaSlow, true);
        if(CopyBuffer(emaSlowHandle, 0, 0, 1, emaSlow) < 1)
        {
            SetDecisionReasonTag("SCALP_SPRD_EMA_SLOW_COPY_FAIL");
            return TRADE_SIGNAL_NONE;
        }

        //--- Read RSI
        int rsiHandle = indMgr->GetRSIHandle(m_symbol, m_timeframe, m_rsiPeriod, PRICE_CLOSE);
        if(rsiHandle == INVALID_HANDLE)
        {
            SetDecisionReasonTag("SCALP_SPRD_NO_RSI");
            return TRADE_SIGNAL_NONE;
        }
        double rsi[];
        ArraySetAsSeries(rsi, true);
        if(CopyBuffer(rsiHandle, 0, 0, 1, rsi) < 1)
        {
            SetDecisionReasonTag("SCALP_SPRD_RSI_COPY_FAIL");
            return TRADE_SIGNAL_NONE;
        }

        //--- Current price
        double closePrice = iClose(m_symbol, m_timeframe, 0);
        if(closePrice <= 0.0)
        {
            SetDecisionReasonTag("SCALP_SPRD_NO_PRICE");
            return TRADE_SIGNAL_NONE;
        }

        //--- Condition 1: Current spread > 2x average spread proxy (0.06 * ATR)
        double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
        long   currentSpread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
        double spreadPrice = (point > 0.0) ? (double)currentSpread * point : 999.0;
        double wideThreshold = m_wideSpreadATRRatio * atr[0];

        bool spreadWide = (spreadPrice > wideThreshold);
        if(!spreadWide)
        {
            SetDecisionReasonTag("SCALP_SPRD_NOT_WIDE");
            return TRADE_SIGNAL_NONE;
        }

        //--- Condition 2: Spread returning to normal (current < previous)
        bool spreadReturning = (m_prevSpread > 0 && currentSpread < m_prevSpread);

        //--- Condition 3: Price near EMA slow (within 0.3 ATR) — mean-reversion
        double emaDistance = MathAbs(closePrice - emaSlow[0]);
        bool priceNearEMA = (emaDistance <= m_emaProximityATR * atr[0]);

        //--- Determine direction based on price position relative to EMA
        ENUM_TRADE_SIGNAL direction = TRADE_SIGNAL_NONE;
        if(closePrice < emaSlow[0])
            direction = TRADE_SIGNAL_BUY;   // Price below EMA — expect reversion up
        else if(closePrice > emaSlow[0])
            direction = TRADE_SIGNAL_SELL;  // Price above EMA — expect reversion down
        else
        {
            SetDecisionReasonTag("SCALP_SPRD_AT_EMA");
            return TRADE_SIGNAL_NONE;
        }

        //--- Condition 4: RSI confirmation
        //    BUY: RSI < 55 (slight oversold)
        //    SELL: RSI > 45 (slight overbought)
        bool rsiOk = false;
        if(direction == TRADE_SIGNAL_BUY && rsi[0] < 55.0)
            rsiOk = true;
        else if(direction == TRADE_SIGNAL_SELL && rsi[0] > 45.0)
            rsiOk = true;

        if(!rsiOk)
        {
            SetDecisionReasonTag("SCALP_SPRD_RSI_FAIL");
            return TRADE_SIGNAL_NONE;
        }

        //--- Price near EMA is required for mean-reversion entry
        if(!priceNearEMA)
        {
            SetDecisionReasonTag("SCALP_SPRD_FAR_FROM_EMA");
            return TRADE_SIGNAL_NONE;
        }

        //--- Calculate confidence
        confidence = 0.50;  // Base
        if(spreadReturning) confidence += 0.20;
        if(priceNearEMA)    confidence += 0.10;

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
        SetDecisionReasonTag(StringFormat("SCALP_SPRD_%s|RET=%d|NEAR=%d|RSI=%.1f|SPR=%I64d",
                                           dirStr, spreadReturning ? 1 : 0, priceNearEMA ? 1 : 0,
                                           rsi[0], currentSpread));

        return direction;
    }

    //+------------------------------------------------------------------+
    //| Validate parameters                                               |
    //+------------------------------------------------------------------+
    virtual bool ValidateParameters(void) override
    {
        if(m_emaSlowPeriod <= 0) return false;
        if(m_atrPeriod <= 0) return false;
        if(m_rsiPeriod <= 0) return false;
        if(m_slATRRatio <= 0.0 || m_tpATRRatio <= 0.0) return false;
        return true;
    }
};

#endif // CORE_SCALP_SCALP_SPREAD_STRATEGY_MQH
