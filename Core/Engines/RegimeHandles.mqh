// Indicator handle lifecycle + symbol/timeframe context
// Extracted verbatim from RegimeEngine.mqh (no behavior change)
#ifndef REGIME_HANDLES_MQH
#define REGIME_HANDLES_MQH

#include "RegimeTypes.mqh"

// Owns the ATR / Bollinger / ADX handles together with the symbol
// and timeframe they were created for.
class CRegimeHandles
{
private:
    int m_atrHandle;
    int m_bbHandle;
    int m_adxHandle;  // ENHANCEMENT: ADX for trend strength (Batch 93 - Week 5)
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;

public:
    CRegimeHandles() :
        m_atrHandle(INVALID_HANDLE),
        m_bbHandle(INVALID_HANDLE),
        m_adxHandle(INVALID_HANDLE),  // Batch 117: initialize to INVALID_HANDLE
        m_symbol(""),
        m_timeframe(PERIOD_CURRENT)
    {
    }

    ~CRegimeHandles()
    {
        ResetHandles();
    }

    //--- Resolve PERIOD_CURRENT to the actual chart timeframe
    static ENUM_TIMEFRAMES ResolveTimeframe(const ENUM_TIMEFRAMES timeframe)
    {
        ENUM_TIMEFRAMES resolvedTimeframe = timeframe;
        if(resolvedTimeframe == PERIOD_CURRENT || resolvedTimeframe == 0)
            resolvedTimeframe = Period();
        return resolvedTimeframe;
    }

    void ResetHandles()
    {
        if(m_atrHandle != INVALID_HANDLE)
        {
            IndicatorRelease(m_atrHandle);
            m_atrHandle = INVALID_HANDLE;
        }
        if(m_bbHandle != INVALID_HANDLE)
        {
            IndicatorRelease(m_bbHandle);
            m_bbHandle = INVALID_HANDLE;
        }
        // ENHANCEMENT: Release ADX handle (Batch 93 - Week 5)
        if(m_adxHandle != INVALID_HANDLE)
        {
            IndicatorRelease(m_adxHandle);
            m_adxHandle = INVALID_HANDLE;
        }
    }

    bool AreHandlesReady() const
    {
        return (m_atrHandle != INVALID_HANDLE && m_bbHandle != INVALID_HANDLE && m_adxHandle != INVALID_HANDLE);
    }

    bool MatchesContext(const string symbol, const ENUM_TIMEFRAMES resolvedTimeframe) const
    {
        return (m_symbol == symbol && m_timeframe == resolvedTimeframe);
    }

    //--- Release and re-create every handle for the supplied context
    bool Recreate(const string symbol, const ENUM_TIMEFRAMES resolvedTimeframe, const SRegimeConfig &config)
    {
        ResetHandles();

        m_symbol = symbol;
        m_timeframe = resolvedTimeframe;
        m_atrHandle = iATR(symbol, resolvedTimeframe, config.atrPeriod);
        m_bbHandle = iBands(symbol, resolvedTimeframe, config.bbPeriod, 0, config.bbDeviation, PRICE_CLOSE);
        // ENHANCEMENT: Create ADX handle for trend strength (Batch 93 - Week 5)
        m_adxHandle = iADX(symbol, resolvedTimeframe, 14);

        return AreHandlesReady();
    }

    int GetAtrHandle() const { return m_atrHandle; }
    int GetBbHandle() const { return m_bbHandle; }
    int GetAdxHandle() const { return m_adxHandle; }
    string GetSymbol() const { return m_symbol; }
    ENUM_TIMEFRAMES GetTimeframe() const { return m_timeframe; }
};

#endif // REGIME_HANDLES_MQH
