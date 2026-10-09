// Volatility-regime tracking + dynamic SL/TP recalculation and the
// shared ATR accessor, extracted from PositionLifecycleManager.mqh
// (Phase H — God Object decomposition)
// Owns: CVolatilityRegime registry + dynamic SL/TP configuration.
// Behaviour preserved 1:1 — no logic changes.
#ifndef POS_LIFECYCLE_VOLATILITY_MQH
#define POS_LIFECYCLE_VOLATILITY_MQH

#include "..\Trading\TradeManager.mqh"
#include "..\..\IndicatorManager.mqh"
#include "PosLifecycleMagicFilter.mqh"

class CVolatilityRegime
{
public:
    string   symbol;       // Symbol this regime belongs to
    double   atr14;
    double   atr50;
    double   atrRatio;
    int      regime;       // 0=low, 1=normal, 2=high
    datetime lastUpdate;

    CVolatilityRegime(void)
    {
        symbol = "";
        atr14 = 0.0;
        atr50 = 0.0;
        atrRatio = 1.0;
        regime = 1;
        lastUpdate = 0;
    }
};

// Stateful module — held BY VALUE by CPositionLifecycleManager.
// GetATR() is stateless and therefore exposed as a static helper so
// that the loss-guard and exit-rule modules can reuse it without
// duplicating the IndicatorManager plumbing.
class CPosLifecycleVolatility
{
private:
    bool   m_dynamicSLEnabled;
    double m_dynamicSLATRMultiplier;
    double m_dynamicTPATRMultiplier;
    bool   m_volatilitySLAdjustEnabled;

    CVolatilityRegime* m_volatilityRegimes[];  // Per-symbol volatility regime
    int                m_volatilityRegimeCount;

public:
    CPosLifecycleVolatility() :
        m_dynamicSLEnabled(false),
        m_dynamicSLATRMultiplier(1.5),
        m_dynamicTPATRMultiplier(3.0),
        m_volatilitySLAdjustEnabled(false),
        m_volatilityRegimeCount(0)
    {}

    ~CPosLifecycleVolatility()
    {
        for(int i = 0; i < m_volatilityRegimeCount; i++)
        {
            if(CheckPointer(m_volatilityRegimes[i]) == POINTER_DYNAMIC)
                delete m_volatilityRegimes[i];
        }
        m_volatilityRegimeCount = 0;
        ArrayFree(m_volatilityRegimes);
    }

    void Configure(bool enabled, double slATRMultiplier, double tpATRMultiplier, bool volAdjust)
    {
        m_dynamicSLEnabled = enabled;
        m_dynamicSLATRMultiplier = slATRMultiplier;
        m_dynamicTPATRMultiplier = tpATRMultiplier;
        m_volatilitySLAdjustEnabled = volAdjust;
    }

    bool IsEnabled() const { return m_dynamicSLEnabled; }

    void ManageDynamicSLTP(CTradeManager* tradeManager, string &symbols[], const int symbolCount,
                           const int magicBase, const int magicMax)
    {
        if(!m_dynamicSLEnabled)
            return;

        UpdateVolatilityRegimes(symbols, symbolCount);

        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(!CPosLifecycleMagicFilter::IsLifecycleManaged(PositionGetInteger(POSITION_MAGIC),
                                                             PositionGetString(POSITION_COMMENT),
                                                             magicBase, magicMax)) continue;

            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentTP = PositionGetDouble(POSITION_TP);

            CVolatilityRegime* regime = GetVolatilityRegime(symbol);
            if(regime == NULL) continue;

            // Calculate dynamic SL/TP based on ATR
            double atr = regime.atr14;
            if(atr <= 0) continue;

            double slMultiplier = m_dynamicSLATRMultiplier;
            double tpMultiplier = m_dynamicTPATRMultiplier;

            if(m_volatilitySLAdjustEnabled)
            {
                if(regime.regime == 0) // Low volatility
                    slMultiplier *= 0.8;
                else if(regime.regime == 2) // High volatility
                    slMultiplier *= 1.2;
            }

            double slDistance = atr * slMultiplier;
            double tpDistance = atr * tpMultiplier;

            double newSL = 0.0;
            double newTP = 0.0;

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

            // Normalize to symbol digits
            int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
            newSL = NormalizeDouble(newSL, digits);
            newTP = NormalizeDouble(newTP, digits);

            // Only modify if significantly different (avoid excessive modifications)
            double slDiff = MathAbs(newSL - currentSL);
            double tpDiff = MathAbs(newTP - currentTP);
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            if(point <= 0) point = 0.00001;

            if(slDiff > 10 * point || tpDiff > 10 * point || currentSL == 0 || currentTP == 0)
            {
                if(tradeManager.ModifyPosition(ticket, newSL, newTP))
                {
                    PrintFormat("[DYNAMIC-SLTP] %s | ticket=%d | SL=%.5f -> %.5f | TP=%.5f -> %.5f | ATR=%.5f | regime=%d",
                                symbol, ticket, currentSL, newSL, currentTP, newTP, atr, regime.regime);
                }
            }
        }
    }

    void UpdateVolatilityRegimes(string &symbols[], const int symbolCount)
    {
        datetime now = TimeCurrent();

        for(int i = 0; i < symbolCount; i++)
        {
            string symbol = symbols[i];

            CVolatilityRegime* regime = GetVolatilityRegime(symbol);
            if(regime == NULL)
            {
                regime = CreateVolatilityRegime(symbol);
                if(regime == NULL) continue;
            }

            // Update every 5 minutes to avoid excessive calculations
            if(now - regime.lastUpdate < 300) continue;

            double atr14 = GetATR(symbol, 14);
            double atr50 = GetATR(symbol, 50);

            if(atr14 > 0 && atr50 > 0)
            {
                regime.atr14 = atr14;
                regime.atr50 = atr50;
                regime.atrRatio = atr14 / atr50;

                if(regime.atrRatio < 0.5)
                    regime.regime = 0; // Low volatility
                else if(regime.atrRatio > 1.5)
                    regime.regime = 2; // High volatility
                else
                    regime.regime = 1; // Normal volatility

                regime.lastUpdate = now;
            }
        }
    }

    CVolatilityRegime* GetVolatilityRegime(const string symbol)
    {
        for(int i = 0; i < m_volatilityRegimeCount; i++)
        {
            if(CheckPointer(m_volatilityRegimes[i]) == POINTER_DYNAMIC &&
               m_volatilityRegimes[i].symbol == symbol)
                return m_volatilityRegimes[i];
        }
        return NULL;
    }

    CVolatilityRegime* CreateVolatilityRegime(const string symbol)
    {
        if(m_volatilityRegimeCount >= ArraySize(m_volatilityRegimes))
            ArrayResize(m_volatilityRegimes, m_volatilityRegimeCount + 10);

        CVolatilityRegime* regime = new CVolatilityRegime();
        regime.symbol = symbol;
        // atr14/atr50/regime/ratio left as defaults; caller populates from data

        m_volatilityRegimes[m_volatilityRegimeCount] = regime;
        m_volatilityRegimeCount++;
        return regime;
    }

    //--- Stateless: exposed as static so sibling lifecycle modules can reuse it.
    //--- NOTE: static methods cannot be const in MQL5.
    static double GetATR(const string symbol, int period)
    {
        CIndicatorManager* indManager = CIndicatorManager::Instance();
        if(indManager == NULL)
        {
            PrintFormat("[LIFECYCLE-ATR] ERROR: IndicatorManager not available for %s period=%d", symbol, period);
            return 0;
        }

        // Resolve PERIOD_CURRENT to actual chart timeframe
        ENUM_TIMEFRAMES actualTimeframe = Period();
        if(actualTimeframe == PERIOD_CURRENT || actualTimeframe == 0)
            actualTimeframe = PERIOD_M15;

        int atrHandle = indManager.GetATRHandle(symbol, actualTimeframe, period);
        if(atrHandle == INVALID_HANDLE)
        {
            PrintFormat("[LIFECYCLE-ATR] ERROR: Failed to get ATR handle for %s period=%d timeframe=%s",
                        symbol, period, EnumToString(actualTimeframe));
            return 0;
        }

        double atrBuffer[];
        ArraySetAsSeries(atrBuffer, true);
        if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) <= 0)
        {
            int err = GetLastError();
            PrintFormat("[LIFECYCLE-ATR] ERROR: CopyBuffer failed for %s period=%d timeframe=%s err=%d",
                        symbol, period, EnumToString(actualTimeframe), err);
            // Don't release handle - IndicatorManager manages lifecycle
            return 0;
        }

        double atr = atrBuffer[0];
        if(atr <= 0.0 || !MathIsValidNumber(atr))
        {
            PrintFormat("[LIFECYCLE-ATR] WARNING: Invalid ATR value %.5f for %s period=%d", atr, symbol, period);
            return 0;
        }
        return atr;
    }
};

#endif // POS_LIFECYCLE_VOLATILITY_MQH
