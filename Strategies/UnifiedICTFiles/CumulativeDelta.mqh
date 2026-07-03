//+------------------------------------------------------------------+
//| CumulativeDelta.mqh                                              |
//| Tick-volume delta proxy for order-flow confirmation              |
//+------------------------------------------------------------------+
#property strict

#ifndef UICT_CUMULATIVE_DELTA_MQH
#define UICT_CUMULATIVE_DELTA_MQH

class CCumulativeDelta
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    datetime        m_barTime;
    double          m_lastPrice;
    double          m_lastTickVolume;
    double          m_upVolume;
    double          m_downVolume;
    double          m_delta;
    bool            m_ready;

public:
                    CCumulativeDelta();
                   ~CCumulativeDelta() {}

    bool            Initialize(const string symbol, const ENUM_TIMEFRAMES timeframe);
    void            Reset();
    void            PrimeFromRecentBars(const int lookback = 12);
    void            UpdateTick();

    bool            IsReady() const { return m_ready; }
    double          GetDelta() const { return m_delta; }
    double          GetBuyPressure() const;
    double          GetSellPressure() const { return 1.0 - GetBuyPressure(); }
    double          GetNormalizedDelta() const;
    bool            IsBuyingPressure(const double threshold = 0.60) const { return GetBuyPressure() >= threshold; }
    bool            IsSellingPressure(const double threshold = 0.40) const { return GetBuyPressure() <= threshold; }
};

CCumulativeDelta::CCumulativeDelta() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_barTime(0),
    m_lastPrice(0.0),
    m_lastTickVolume(0.0),
    m_upVolume(0.0),
    m_downVolume(0.0),
    m_delta(0.0),
    m_ready(false)
{
}

bool CCumulativeDelta::Initialize(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    Reset();
    return (m_symbol != "");
}

void CCumulativeDelta::Reset()
{
    m_barTime = 0;
    m_lastPrice = 0.0;
    m_lastTickVolume = 0.0;
    m_upVolume = 0.0;
    m_downVolume = 0.0;
    m_delta = 0.0;
    m_ready = false;
}

void CCumulativeDelta::PrimeFromRecentBars(const int lookback)
{
    if(m_symbol == "")
        return;

    double up = 0.0;
    double down = 0.0;
    for(int i = 1; i <= lookback; i++)
    {
        double openPrice = iOpen(m_symbol, m_timeframe, i);
        double closePrice = iClose(m_symbol, m_timeframe, i);
        double volume = (double)iVolume(m_symbol, m_timeframe, i);
        if(volume <= 0.0)
            continue;

        if(closePrice >= openPrice)
            up += volume;
        else
            down += volume;
    }

    if((up + down) <= 0.0)
        return;

    m_upVolume = up;
    m_downVolume = down;
    m_delta = up - down;
    m_ready = true;
}

void CCumulativeDelta::UpdateTick()
{
    if(m_symbol == "")
        return;

    datetime currentBarTime = iTime(m_symbol, m_timeframe, 0);
    if(currentBarTime <= 0)
        return;

    if(m_barTime != currentBarTime)
    {
        m_barTime = currentBarTime;
        m_lastTickVolume = 0.0;
        m_upVolume = 0.0;
        m_downVolume = 0.0;
        m_delta = 0.0;
        m_ready = false;
    }

    MqlTick tick;
    if(!SymbolInfoTick(m_symbol, tick))
        return;

    double price = tick.last;
    if(price <= 0.0)
        price = (tick.bid > 0.0) ? tick.bid : tick.ask;
    if(price <= 0.0)
        return;

    double totalVolume = (tick.volume_real > 0) ? (double)tick.volume_real : (double)tick.volume;

    if(m_lastPrice <= 0.0)
    {
        m_lastPrice = price;
        m_lastTickVolume = totalVolume;
        PrimeFromRecentBars(8);
        return;
    }

    double volumeDelta = totalVolume - m_lastTickVolume;
    if(volumeDelta <= 0.0)
        volumeDelta = 1.0;

    if(price > m_lastPrice)
        m_upVolume += volumeDelta;
    else if(price < m_lastPrice)
        m_downVolume += volumeDelta;

    m_lastPrice = price;
    m_lastTickVolume = totalVolume;
    m_delta = m_upVolume - m_downVolume;
    m_ready = ((m_upVolume + m_downVolume) > 0.0);
}

double CCumulativeDelta::GetBuyPressure() const
{
    double total = m_upVolume + m_downVolume;
    if(total <= 0.0)
        return 0.50;
    return MathMax(0.0, MathMin(1.0, m_upVolume / total));
}

double CCumulativeDelta::GetNormalizedDelta() const
{
    double total = m_upVolume + m_downVolume;
    if(total <= 0.0)
        return 0.0;
    return m_delta / total;
}

#endif // __UICT_CUMULATIVE_DELTA_MQH__
