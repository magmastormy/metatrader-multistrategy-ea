//+------------------------------------------------------------------+
//| AnchoredVWAP.mqh                                                 |
//| Anchored VWAP with 1/2 sigma bands for institutional reference   |
//+------------------------------------------------------------------+
#property strict

#ifndef __UICT_ANCHORED_VWAP_MQH__
#define __UICT_ANCHORED_VWAP_MQH__

class CAnchoredVWAP
{
private:
    string          m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    datetime        m_anchorTime;
    double          m_vwap;
    double          m_band1Up;
    double          m_band1Down;
    double          m_band2Up;
    double          m_band2Down;
    bool            m_ready;

public:
                    CAnchoredVWAP();
                   ~CAnchoredVWAP() {}

    bool            Initialize(const string symbol, const ENUM_TIMEFRAMES timeframe);
    void            SetAnchor(const datetime anchorTime) { m_anchorTime = anchorTime; }
    datetime        GetAnchor() const { return m_anchorTime; }
    void            Update();

    bool            IsReady() const { return m_ready; }
    double          GetVWAP() const { return m_vwap; }
    double          GetBand1Up() const { return m_band1Up; }
    double          GetBand1Down() const { return m_band1Down; }
    double          GetBand2Up() const { return m_band2Up; }
    double          GetBand2Down() const { return m_band2Down; }
    bool            PriceAboveVWAP(const double price) const { return m_ready && price >= m_vwap; }
    bool            PriceBelowVWAP(const double price) const { return m_ready && price <= m_vwap; }
    bool            IsNearVWAP(const double price, const double sigmaMultiplier = 0.75) const;
};

CAnchoredVWAP::CAnchoredVWAP() :
    m_symbol(""),
    m_timeframe(PERIOD_CURRENT),
    m_anchorTime(0),
    m_vwap(0.0),
    m_band1Up(0.0),
    m_band1Down(0.0),
    m_band2Up(0.0),
    m_band2Down(0.0),
    m_ready(false)
{
}

bool CAnchoredVWAP::Initialize(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    m_symbol = symbol;
    m_timeframe = timeframe;
    m_anchorTime = 0;
    m_vwap = 0.0;
    m_band1Up = 0.0;
    m_band1Down = 0.0;
    m_band2Up = 0.0;
    m_band2Down = 0.0;
    m_ready = false;
    return (m_symbol != "");
}

void CAnchoredVWAP::Update()
{
    m_ready = false;
    if(m_symbol == "" || m_anchorTime <= 0)
        return;

    int anchorShift = iBarShift(m_symbol, m_timeframe, m_anchorTime, false);
    if(anchorShift < 0)
        return;

    int count = anchorShift + 1;
    if(count < 3)
        return;

    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    if(CopyRates(m_symbol, m_timeframe, 0, count, rates) <= 0)
        return;

    double weightedPriceSum = 0.0;
    double volumeSum = 0.0;

    for(int i = 0; i < count; i++)
    {
        if(rates[i].time < m_anchorTime)
            continue;

        double volume = (rates[i].real_volume > 0) ? (double)rates[i].real_volume : (double)rates[i].tick_volume;
        if(volume <= 0.0)
            continue;

        double typicalPrice = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
        weightedPriceSum += typicalPrice * volume;
        volumeSum += volume;
    }

    if(volumeSum <= 0.0)
        return;

    m_vwap = weightedPriceSum / volumeSum;

    double varianceSum = 0.0;
    for(int i = 0; i < count; i++)
    {
        if(rates[i].time < m_anchorTime)
            continue;

        double volume = (rates[i].real_volume > 0) ? (double)rates[i].real_volume : (double)rates[i].tick_volume;
        if(volume <= 0.0)
            continue;

        double typicalPrice = (rates[i].high + rates[i].low + rates[i].close) / 3.0;
        double deviation = typicalPrice - m_vwap;
        varianceSum += deviation * deviation * volume;
    }

    double sigma = MathSqrt(MathMax(0.0, varianceSum / volumeSum));
    m_band1Up = m_vwap + sigma;
    m_band1Down = m_vwap - sigma;
    m_band2Up = m_vwap + (sigma * 2.0);
    m_band2Down = m_vwap - (sigma * 2.0);
    m_ready = true;
}

bool CAnchoredVWAP::IsNearVWAP(const double price, const double sigmaMultiplier) const
{
    if(!m_ready)
        return false;

    double sigma = MathMax(MathAbs(m_band1Up - m_vwap), SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 10.0);
    return (MathAbs(price - m_vwap) <= (sigma * MathMax(0.25, sigmaMultiplier)));
}

#endif // __UICT_ANCHORED_VWAP_MQH__
