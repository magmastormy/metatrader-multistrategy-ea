// Rolling spread sampling, baseline and shock/cooldown state
// Extracted verbatim from RegimeEngine.mqh (no behavior change)
#ifndef REGIME_SPREAD_MQH
#define REGIME_SPREAD_MQH

#include "RegimeTypes.mqh"

// Owns the circular spread sample buffer and the last spread-shock
// timestamp; window / multiplier / cooldown stay in SRegimeConfig.
class CRegimeSpreadTracker
{
private:
    double m_samples[];
    int m_sampleCount;
    int m_sampleCursor;
    datetime m_lastShockTime;

public:
    CRegimeSpreadTracker() :
        m_sampleCount(0),
        m_sampleCursor(0),
        m_lastShockTime(0)
    {
        ArrayResize(m_samples, 0);
    }

    //--- Resize the ring buffer and drop every stored sample
    void Reset(const int window)
    {
        ArrayResize(m_samples, window);
        m_sampleCount = 0;
        m_sampleCursor = 0;
    }

    //--- Clear only the shock timestamp (symbol / timeframe switch)
    void ResetShockTime()
    {
        m_lastShockTime = 0;
    }

    //--- Arithmetic mean of the stored samples
    double ComputeBaseline() const
    {
        if(m_sampleCount <= 0)
            return 0.0;

        double sum = 0.0;
        for(int i = 0; i < m_sampleCount; i++)
            sum += m_samples[i];

        return sum / (double)m_sampleCount;
    }

    //--- Read the live spread, roll it into the buffer and derive the
    //--- baseline / shock / cooldown flags in one pass.
    void CaptureSpread(const string symbol,
                       const SRegimeConfig &config,
                       double &spreadPrice,
                       double &spreadBaseline,
                       bool &spreadShock,
                       bool &cooldownActive);
};

void CRegimeSpreadTracker::CaptureSpread(const string symbol,
                                         const SRegimeConfig &config,
                                         double &spreadPrice,
                                         double &spreadBaseline,
                                         bool &spreadShock,
                                         bool &cooldownActive)
{
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    if(point <= 0.0)
        point = 0.00001;

    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    spreadPrice = 0.0;
    if(ask > 0.0 && bid > 0.0 && ask >= bid)
        spreadPrice = ask - bid;
    else
        spreadPrice = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD) * point;

    if(!MathIsValidNumber(spreadPrice) || spreadPrice < 0.0)
        spreadPrice = 0.0;

    if(config.spreadWindow > 0)
    {
        m_samples[m_sampleCursor] = spreadPrice;
        m_sampleCursor = (m_sampleCursor + 1) % config.spreadWindow;
        if(m_sampleCount < config.spreadWindow)
            m_sampleCount++;
    }

    spreadBaseline = ComputeBaseline();
    spreadShock = false;
    if(spreadBaseline > 0.0 && spreadPrice > (spreadBaseline * config.spreadShockMultiplier))
    {
        spreadShock = true;
        m_lastShockTime = TimeCurrent();
    }

    cooldownActive = false;
    if(m_lastShockTime > 0)
        cooldownActive = ((TimeCurrent() - m_lastShockTime) <= config.spreadShockCooldownSeconds);
}

#endif // REGIME_SPREAD_MQH
