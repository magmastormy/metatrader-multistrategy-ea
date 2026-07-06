//+------------------------------------------------------------------+
//| CVDEngine.mqh                                                    |
//| Cumulative Volume Delta — measures buy vs sell pressure            |
//| For forex markets only                                           |
//+------------------------------------------------------------------
#ifndef CORE_ENGINES_CVD_ENGINE_MQH
#define CORE_ENGINES_CVD_ENGINE_MQH

struct SCVDResult
{
    double cvd;            // Cumulative Volume Delta
    double delta;          // Current bar delta
    double cvdMA;          // CVD moving average
    bool   bullDivergence; // Price lower low + CVD higher low
    bool   bearDivergence; // Price higher high + CVD lower high
    bool   isExtreme;      // CVD at ±2σ extreme
    bool   isValid;
};

class CCVDEngine
{
private:
    string m_symbol;
    int    m_divergenceLookback;
    double m_extremeThreshold;
    int    m_cvdMALength;
    
    // Session tracking
    datetime m_sessionStartDate;
    datetime m_lastProcessedBarTime;  // Batch 117: prevent CVD re-accumulation
    double   m_sessionCVD;
    double   m_cvdHistory[];
    double   m_priceHistory[];
    int      m_historyIndex;
    int      m_historySize;
    
    SCVDResult m_lastResult;
    bool       m_initialized;
    
    void ResetSession()
    {
        m_sessionCVD = 0;
        m_historyIndex = 0;
        ArrayInitialize(m_cvdHistory, 0);
        ArrayInitialize(m_priceHistory, 0);
    }
    
public:
    CCVDEngine() : m_symbol(""), m_divergenceLookback(30),
        m_extremeThreshold(2.0), m_cvdMALength(20),
        m_sessionStartDate(0), m_lastProcessedBarTime(0), m_sessionCVD(0),
        m_historyIndex(0), m_historySize(200), m_initialized(false)
    {
        ZeroMemory(m_lastResult);
    }
    
    bool Initialize(string symbol, int divLookback = 30, double extremeThresh = 2.0, int cvdMALen = 20)
    {
        m_symbol = symbol;
        m_divergenceLookback = divLookback;
        m_extremeThreshold = extremeThresh;
        m_cvdMALength = cvdMALen;
        m_historySize = MathMax(divLookback * 2, 200);
        ArrayResize(m_cvdHistory, m_historySize);
        ArrayResize(m_priceHistory, m_historySize);
        ArrayInitialize(m_cvdHistory, 0);
        ArrayInitialize(m_priceHistory, 0);
        ResetSession();
        m_initialized = true;
        Print("[CVD-ENGINE] Initialized | symbol=", symbol, " | divLookback=", divLookback);
        return true;
    }
    
    SCVDResult Calculate()
    {
        ZeroMemory(m_lastResult);
        if(!m_initialized) return m_lastResult;
        
        // Check for session reset
        datetime currentBarTime = iTime(m_symbol, PERIOD_CURRENT, 0);
        MqlDateTime dt;
        TimeToStruct(currentBarTime, dt);
        datetime currentDay = StringToTime(IntegerToString(dt.year) + "." + IntegerToString(dt.mon) + "." + IntegerToString(dt.day));
        
        if(m_sessionStartDate == 0 || currentDay != m_sessionStartDate)
        {
            ResetSession();
            m_sessionStartDate = currentDay;
        }
        
        // Batch 117: Skip if same bar — prevent CVD re-accumulation
        if(currentBarTime == m_lastProcessedBarTime)
        {
            m_lastResult.cvd = m_sessionCVD;
            return m_lastResult;
        }
        m_lastProcessedBarTime = currentBarTime;
        
        // Calculate delta for recent bars
        for(int i = 1; i <= MathMin(m_divergenceLookback, Bars(m_symbol, PERIOD_CURRENT) - 1); i++)
        {
            double open = iOpen(m_symbol, PERIOD_CURRENT, i);
            double close = iClose(m_symbol, PERIOD_CURRENT, i);
            double volume = (double)iVolume(m_symbol, PERIOD_CURRENT, i);
            
            // Classify bar: close > open = buy volume, close < open = sell volume
            double delta = 0;
            if(close > open)
                delta = volume;  // Buy pressure
            else if(close < open)
                delta = -volume; // Sell pressure
            // else delta = 0 (doji — neutral)
            
            m_sessionCVD += delta;
            
            // Store in history
            int idx = (m_historyIndex + m_historySize - i) % m_historySize;
            m_cvdHistory[idx] = m_sessionCVD;
            m_priceHistory[idx] = close;
        }
        
        m_lastResult.cvd = m_sessionCVD;
        m_lastResult.delta = (iClose(m_symbol, PERIOD_CURRENT, 1) > iOpen(m_symbol, PERIOD_CURRENT, 1)) ? 
                             (double)iVolume(m_symbol, PERIOD_CURRENT, 1) : -(double)iVolume(m_symbol, PERIOD_CURRENT, 1);
        
        // Calculate CVD MA — Batch 117: include zero values (valid CVD reading)
        double sum = 0;
        int count = 0;
        for(int i = 0; i < MathMin(m_cvdMALength, m_historySize); i++)
        {
            sum += m_cvdHistory[i];
            count++;
        }
        m_lastResult.cvdMA = (count > 0) ? sum / count : 0;
        
        // Check for extremes (±2σ)
        double cvdMean = m_lastResult.cvdMA;
        double cvdVariance = 0;
        count = 0;
        for(int i = 0; i < MathMin(m_divergenceLookback, m_historySize); i++)
        {
            if(m_cvdHistory[i] != 0) { cvdVariance += MathPow(m_cvdHistory[i] - cvdMean, 2); count++; }
        }
        double cvdStdDev = (count > 1) ? MathSqrt(cvdVariance / (count - 1)) : 1;
        m_lastResult.isExtreme = (cvdStdDev > 0 && MathAbs(m_sessionCVD - cvdMean) > m_extremeThreshold * cvdStdDev);
        
        // Check for divergences
        m_lastResult.bullDivergence = false;
        m_lastResult.bearDivergence = false;
        
        if(m_historyIndex >= m_divergenceLookback)
        {
            // Price making lower low but CVD making higher low = bullish divergence
            double priceNow = iClose(m_symbol, PERIOD_CURRENT, 1);
            double priceThen = iClose(m_symbol, PERIOD_CURRENT, m_divergenceLookback);
            double cvdNow = m_sessionCVD;
            double cvdThen = m_cvdHistory[(m_historyIndex + m_historySize - m_divergenceLookback) % m_historySize];
            
            if(priceNow < priceThen && cvdNow > cvdThen)
                m_lastResult.bullDivergence = true;
            
            if(priceNow > priceThen && cvdNow < cvdThen)
                m_lastResult.bearDivergence = true;
        }
        
        m_lastResult.isValid = true;
        m_historyIndex = (m_historyIndex + 1) % m_historySize;
        
        return m_lastResult;
    }
    
    // Get CVD direction: 1 = positive (buying), -1 = negative (selling), 0 = neutral
    int GetDirection()
    {
        if(!m_lastResult.isValid) return 0;
        if(m_sessionCVD > 0) return 1;
        if(m_sessionCVD < 0) return -1;
        return 0;
    }
    
    // Check if CVD confirms price direction
    bool ConfirmsPrice(double currentPrice, double previousPrice)
    {
        if(!m_lastResult.isValid) return false;
        bool priceUp = currentPrice > previousPrice;
        bool cvdPositive = m_sessionCVD > 0;
        return (priceUp && cvdPositive) || (!priceUp && !cvdPositive);
    }
    
    bool IsInitialized() const { return m_initialized; }
    SCVDResult GetLastResult() const { return m_lastResult; }
};

#endif // CORE_ENGINES_CVD_ENGINE_MQH
