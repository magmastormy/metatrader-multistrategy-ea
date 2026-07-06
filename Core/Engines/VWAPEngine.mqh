//+------------------------------------------------------------------+
//| VWAPEngine.mqh                                                   |
//| Volume-Weighted Average Price with deviation bands                |
//| For forex markets only (real volume required)                     |
//+------------------------------------------------------------------
#ifndef CORE_ENGINES_VWAP_ENGINE_MQH
#define CORE_ENGINES_VWAP_ENGINE_MQH

struct SVWAPResult
{
    double vwap;
    double upperBand1;    // +1σ
    double lowerBand1;    // -1σ
    double upperBand2;    // +2σ
    double lowerBand2;    // -2σ
    double upperBand3;    // +3σ (exhaustion)
    double lowerBand3;    // -3σ (exhaustion)
    double sessionVolume;
    bool   isValid;
};

class CVWAPEngine
{
private:
    string m_symbol;
    int    m_minPeriodBars;
    double m_bandMultiplier1;
    double m_bandMultiplier2;
    double m_bandMultiplier3;
    
    // Session tracking
    datetime m_sessionStartDate;
    datetime m_lastProcessedBarTime;  // Batch 117: prevent VWAP re-accumulation
    double   m_cumulativeTPV;  // cumulative (typical price * volume)
    double   m_cumulativePV;   // cumulative (price - vwap)^2 * volume
    double   m_cumulativeVol;
    int      m_barCount;
    int      m_lastProcessedBarIndex;
    
    // Cached result
    SVWAPResult m_lastResult;
    bool        m_initialized;
    
    double GetTypicalPrice(int shift)
    {
        double h = iHigh(m_symbol, PERIOD_CURRENT, shift);
        double l = iLow(m_symbol, PERIOD_CURRENT, shift);
        double c = iClose(m_symbol, PERIOD_CURRENT, shift);
        return (h + l + c) / 3.0;
    }
    
    double GetVolume(int shift)
    {
        return (double)iVolume(m_symbol, PERIOD_CURRENT, shift);
    }
    
    void ResetSession()
    {
        m_cumulativeTPV = 0;
        m_cumulativePV = 0;
        m_cumulativeVol = 0;
        m_barCount = 0;
        m_lastProcessedBarIndex = 0;
        m_sessionStartDate = 0;
    }
    
public:
    CVWAPEngine() : m_symbol(""), m_minPeriodBars(30),
        m_bandMultiplier1(1.0), m_bandMultiplier2(1.5),
        m_bandMultiplier3(2.0),
        m_sessionStartDate(0), m_lastProcessedBarTime(0), m_cumulativeTPV(0),
        m_cumulativePV(0), m_cumulativeVol(0),
        m_barCount(0), m_lastProcessedBarIndex(0), m_initialized(false)
    {
        ZeroMemory(m_lastResult);
    }
    
    bool Initialize(string symbol, int minPeriod = 30,
                    double band1 = 1.0, double band2 = 1.5,
                    double band3 = 2.0)
    {
        m_symbol = symbol;
        m_minPeriodBars = minPeriod;
        m_bandMultiplier1 = band1;
        m_bandMultiplier2 = band2;
        m_bandMultiplier3 = band3;
        ResetSession();
        m_initialized = true;
        Print("[VWAP-ENGINE] Initialized | symbol=", symbol, " | minPeriod=", minPeriod);
        return true;
    }
    
    SVWAPResult Calculate()
    {
        ZeroMemory(m_lastResult);
        if(!m_initialized) return m_lastResult;
        
        // Check for session reset (new day)
        datetime currentBarTime = iTime(m_symbol, PERIOD_CURRENT, 0);
        MqlDateTime dt;
        TimeToStruct(currentBarTime, dt);
        datetime currentDay = StringToTime(IntegerToString(dt.year) + "." + IntegerToString(dt.mon) + "." + IntegerToString(dt.day));
        
        if(m_sessionStartDate == 0 || currentDay != m_sessionStartDate)
        {
            ResetSession();
            m_sessionStartDate = currentDay;
        }
        
        // Batch 117: Skip if same bar — prevent VWAP re-accumulation
        if(currentBarTime == m_lastProcessedBarTime)
        {
            m_lastResult.isValid = true;
            m_lastResult.vwap = (m_cumulativeVol > 0) ? m_cumulativeTPV / m_cumulativeVol : 0;
            return m_lastResult;
        }
        m_lastProcessedBarTime = currentBarTime;
        
        // Accumulate only new bars since last call
        int totalBars = Bars(m_symbol, PERIOD_CURRENT);
        int startBar = MathMin(totalBars - 1, m_lastProcessedBarIndex > 0 ? m_lastProcessedBarIndex : totalBars - 1);
        for(int i = startBar; i >= 1; i--)
        {
            datetime barTime = iTime(m_symbol, PERIOD_CURRENT, i);
            if(barTime < m_sessionStartDate) break;
            
            double tp = GetTypicalPrice(i);
            double vol = GetVolume(i);
            
            m_cumulativeTPV += tp * vol;
            m_cumulativeVol += vol;
            m_barCount++;
        }
        m_lastProcessedBarIndex = totalBars - 1;
        
        if(m_cumulativeVol <= 0 || m_barCount < m_minPeriodBars)
        {
            m_lastResult.isValid = false;
            return m_lastResult;
        }
        
        // Calculate VWAP
        double vwap = m_cumulativeTPV / m_cumulativeVol;
        
        // Calculate standard deviation
        double variance = 0;
        for(int i = Bars(m_symbol, PERIOD_CURRENT) - 1; i >= 1; i--)
        {
            datetime barTime = iTime(m_symbol, PERIOD_CURRENT, i);
            if(barTime < m_sessionStartDate) break;
            
            double tp = GetTypicalPrice(i);
            double vol = GetVolume(i);
            variance += vol * MathPow(tp - vwap, 2);
        }
        double stdDev = MathSqrt(variance / m_cumulativeVol);
        
        // Fill result
        m_lastResult.vwap = vwap;
        m_lastResult.upperBand1 = vwap + m_bandMultiplier1 * stdDev;
        m_lastResult.lowerBand1 = vwap - m_bandMultiplier1 * stdDev;
        m_lastResult.upperBand2 = vwap + m_bandMultiplier2 * stdDev;
        m_lastResult.lowerBand2 = vwap - m_bandMultiplier2 * stdDev;
        m_lastResult.upperBand3 = vwap + m_bandMultiplier3 * stdDev;
        m_lastResult.lowerBand3 = vwap - m_bandMultiplier3 * stdDev;
        m_lastResult.sessionVolume = m_cumulativeVol;
        m_lastResult.isValid = true;
        
        return m_lastResult;
    }
    
    // Get VWAP position relative to bands (0 = at VWAP, +1 = at +1σ, -1 = at -1σ)
    double GetVWAPPosition(double currentPrice)
    {
        if(!m_lastResult.isValid) return 0;
        double stdDev = (m_lastResult.upperBand1 - m_lastResult.vwap);
        if(stdDev <= 0) return 0;
        return (currentPrice - m_lastResult.vwap) / stdDev;
    }
    
    // Check if price is at exhaustion zone (±3σ)
    bool IsAtExhaustion(double currentPrice)
    {
        if(!m_lastResult.isValid) return false;
        return (currentPrice >= m_lastResult.upperBand3 || currentPrice <= m_lastResult.lowerBand3);
    }
    
    // Check if price is at mean-reversion zone (±2σ)
    bool IsAtMeanReversion(double currentPrice)
    {
        if(!m_lastResult.isValid) return false;
        return (currentPrice >= m_lastResult.upperBand2 || currentPrice <= m_lastResult.lowerBand2);
    }
    
    // Get VWAP direction bias: 1 = above VWAP (bullish), -1 = below (bearish), 0 = at VWAP
    int GetDirectionBias(double currentPrice)
    {
        if(!m_lastResult.isValid) return 0;
        if(currentPrice > m_lastResult.vwap) return 1;
        if(currentPrice < m_lastResult.vwap) return -1;
        return 0;
    }
    
    bool IsInitialized() const { return m_initialized; }
    SVWAPResult GetLastResult() const { return m_lastResult; }
};

#endif // CORE_ENGINES_VWAP_ENGINE_MQH
