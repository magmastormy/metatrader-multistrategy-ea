//+------------------------------------------------------------------+
//| PositionMgrDynamicSL.mqh                                         |
//| Extracted from PositionManager.mqh (Phase I decomposition)       |
//|                                                                  |
//| STATEFUL module: owns the per-symbol volatility regime cache and |
//| the dynamic SL/TP configuration, and re-prices SL/TP from ATR.   |
//| Bodies are copied verbatim from CPositionManager - zero          |
//| behaviour change.                                                |
//|                                                                  |
//| NOTE: 'SVolatilityRegime' intentionally remains a TOP-LEVEL       |
//| struct (exactly as it was declared in PositionManager.mqh).       |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_POSITION_POSITION_MGR_DYNAMIC_SL_MQH
#define CORE_POSITION_POSITION_MGR_DYNAMIC_SL_MQH

#include "../Trading/TradeManager.mqh"     // CTradeManager (complete type, called by pointer)
#include "../../IndicatorManager.mqh"      // CIndicatorManager::Instance() / GetATRHandle()
#include "PositionMgrMagicFilter.mqh"      // CPositionMgrMagicFilter::IsEAOwnedMagic

// Volatility regime tracking struct (must be global for pointer usage)
struct SVolatilityRegime
{
    string      symbol;
    double      atr14;
    double      atr50;
    int         regime;  // 0=low, 1=normal, 2=high
    datetime    lastUpdate;

    SVolatilityRegime() : symbol(""), atr14(0), atr50(0), regime(1), lastUpdate(0) {}
};

//+------------------------------------------------------------------+
//| CPositionMgrDynamicSL                                            |
//+------------------------------------------------------------------+
class CPositionMgrDynamicSL
{
private:
    // Dynamic SL/TP config
    bool                    m_dynamicSLEnabled;
    double                  m_dynamicSLATRMultiplier;
    double                  m_dynamicTPATRMultiplier;
    bool                    m_volatilitySLAdjustEnabled;

    SVolatilityRegime       m_volatilityRegimes[];
    int                     m_volatilityRegimeCount;

    // Get or create volatility regime for symbol
    SVolatilityRegime GetVolatilityRegime(const string symbol)
    {
        for(int i = 0; i < m_volatilityRegimeCount; i++)
            if(m_volatilityRegimes[i].symbol == symbol)
                return m_volatilityRegimes[i];

        int idx = m_volatilityRegimeCount;
        ArrayResize(m_volatilityRegimes, idx + 1);
        m_volatilityRegimes[idx].symbol = symbol;
        m_volatilityRegimeCount++;
        return m_volatilityRegimes[idx];
    }

    // Update volatility regimes using ATR from IndicatorManager
    void UpdateVolatilityRegimes()
    {
        datetime now = TimeCurrent();
        for(int i = 0; i < m_volatilityRegimeCount; i++)
        {
            SVolatilityRegime regime = m_volatilityRegimes[i];
            if(now - regime.lastUpdate < 300) continue; // Update every 5 min max

            CIndicatorManager* indMgr = CIndicatorManager::Instance();
            if(indMgr == NULL) continue;

            ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();
            int atr14Handle = indMgr.GetATRHandle(regime.symbol, tf, 14);
            int atr50Handle = indMgr.GetATRHandle(regime.symbol, tf, 50);

            double atr14Buf[], atr50Buf[];
            ArraySetAsSeries(atr14Buf, true);
            ArraySetAsSeries(atr50Buf, true);

            if(CopyBuffer(atr14Handle, 0, 0, 1, atr14Buf) > 0 &&
               CopyBuffer(atr50Handle, 0, 0, 1, atr50Buf) > 0)
            {
                regime.atr14 = atr14Buf[0];
                regime.atr50 = atr50Buf[0];
                regime.lastUpdate = now;

                if(regime.atr50 > 0)
                {
                    double ratio = regime.atr14 / regime.atr50;
                    if(ratio < 0.7) regime.regime = 0;
                    else if(ratio > 1.3) regime.regime = 2;
                    else regime.regime = 1;
                }
                m_volatilityRegimes[i] = regime;
            }
        }
    }

public:
    CPositionMgrDynamicSL() :
        m_dynamicSLEnabled(false), m_dynamicSLATRMultiplier(1.5), m_dynamicTPATRMultiplier(3.0),
        m_volatilitySLAdjustEnabled(false),
        m_volatilityRegimeCount(0)
    {
        ArrayResize(m_volatilityRegimes, 0);
    }

    ~CPositionMgrDynamicSL()
    {
        // Arrays auto-cleanup
    }

    //--- Mirrors CPositionManager::ConfigureDynamicSL()
    void Configure(bool enabled, double slMult, double tpMult, bool volAdjust)
    {
        m_dynamicSLEnabled = enabled; m_dynamicSLATRMultiplier = slMult;
        m_dynamicTPATRMultiplier = tpMult; m_volatilitySLAdjustEnabled = volAdjust;
    }

    bool IsEnabled() const { return m_dynamicSLEnabled; }

    int GetRegimeCount() const { return m_volatilityRegimeCount; }

    // --- Dynamic SL/TP ---
    void ManageDynamicSLTP(CTradeManager* tradeManager, const int magicNumber)
    {
        if(!m_dynamicSLEnabled) return;

        UpdateVolatilityRegimes();

        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(!CPositionMgrMagicFilter::IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC), magicNumber)) continue;

            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentTP = PositionGetDouble(POSITION_TP);

            SVolatilityRegime regime = GetVolatilityRegime(symbol);
            if(regime.atr14 <= 0) continue;

            double slMult = m_dynamicSLATRMultiplier;
            double tpMult = m_dynamicTPATRMultiplier;

            if(m_volatilitySLAdjustEnabled)
            {
                if(regime.regime == 0) slMult *= 0.8;
                else if(regime.regime == 2) slMult *= 1.2;
            }

            double slDistance = regime.atr14 * slMult;
            double tpDistance = regime.atr14 * tpMult;

            double newSL = 0, newTP = 0;
            if(type == POSITION_TYPE_BUY)
            {
                newSL = openPrice - slDistance;
                newTP = openPrice + tpDistance;
            }
            else
            {
                newSL = openPrice + slDistance;
                newTP = openPrice - tpDistance;
            }

            int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
            newSL = NormalizeDouble(newSL, digits);
            newTP = NormalizeDouble(newTP, digits);

            double slDiff = MathAbs(newSL - currentSL);
            double tpDiff = MathAbs(newTP - currentTP);
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            if(point <= 0) point = 0.00001;

            if(slDiff > 10 * point || tpDiff > 10 * point || currentSL == 0 || currentTP == 0)
            {
                tradeManager.ModifyPosition(ticket, newSL, newTP);
                PrintFormat("[DYNAMIC-SLTP] %s | ticket=%d | SL=%.5f->%.5f | TP=%.5f->%.5f | ATR=%.5f | regime=%d",
                            symbol, ticket, currentSL, newSL, currentTP, newTP, regime.atr14, regime.regime);
            }
        }
    }
};

#endif // CORE_POSITION_POSITION_MGR_DYNAMIC_SL_MQH
