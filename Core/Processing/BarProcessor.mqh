//+------------------------------------------------------------------+
//| BarProcessor.mqh - Bar detection and scheduling                   |
//+------------------------------------------------------------------+
#ifndef __BAR_PROCESSOR_MQH__
#define __BAR_PROCESSOR_MQH__

struct SSymbolScanState
{
    datetime nextEligibleIntrabarTime;
    int intrabarBackoffTier;
    int consecutiveQuietScans;
    void Reset() { nextEligibleIntrabarTime = 0; intrabarBackoffTier = 0; consecutiveQuietScans = 0; }
};

struct SMTFTimeframeConfig
{
    ENUM_TIMEFRAMES timeframe;
    int lookbackBars;
    bool enabled;
    
    SMTFTimeframeConfig() :
        timeframe(PERIOD_CURRENT),
        lookbackBars(3),
        enabled(true) {}
};

class CBarProcessor
{
private:
    string m_symbols[];
    datetime m_lastSymbolBarTimes[];
    datetime m_lastIntrabarScanTime[];
    bool m_pendingNewBarScans[];
    SSymbolScanState m_symbolScanStates[];
    ENUM_TIMEFRAMES m_timeframe;
    
    // Multi-timeframe support
    SMTFTimeframeConfig m_mtfConfigs[];
    ENUM_TIMEFRAMES m_activeMTFTimeframes[];
    int m_mtfCount;
    bool m_mtfEnabled;
    
    // Inertia tracking for backoff tier preservation
    int m_preservedBackoffTier;
    datetime m_backoffTierPreservedSince;
    int m_maxBackoffTierPreservationBars;
    
public:
    CBarProcessor() : 
        m_timeframe(PERIOD_CURRENT),
        m_mtfCount(0),
        m_mtfEnabled(false),
        m_preservedBackoffTier(0),
        m_backoffTierPreservedSince(0),
        m_maxBackoffTierPreservationBars(3)
    {}
    
    ~CBarProcessor() 
    { 
        ArrayResize(m_symbols, 0); 
        ArrayResize(m_lastSymbolBarTimes, 0);
        ArrayResize(m_mtfConfigs, 0);
        ArrayResize(m_activeMTFTimeframes, 0);
    }
    
    bool Initialize(const string& symbols[], ENUM_TIMEFRAMES tf)
    {
        int size = ArraySize(symbols);
        if(size <= 0) return false;
        ArrayResize(m_symbols, size);
        for(int i = 0; i < size; i++) m_symbols[i] = symbols[i];
        ArrayResize(m_lastSymbolBarTimes, size);
        ArrayResize(m_lastIntrabarScanTime, size);
        ArrayResize(m_pendingNewBarScans, size);
        ArrayResize(m_symbolScanStates, size);
        m_timeframe = tf;
        return true;
    }
    
    void ConfigureMTF(const ENUM_TIMEFRAMES timeframes[], int count)
    {
        ArrayResize(m_mtfConfigs, count);
        ArrayResize(m_activeMTFTimeframes, count);
        m_mtfCount = 0;
        
        for(int i = 0; i < count; i++)
        {
            if(timeframes[i] != m_timeframe)
            {
                m_mtfConfigs[m_mtfCount].timeframe = timeframes[i];
                m_mtfConfigs[m_mtfCount].enabled = true;
                m_activeMTFTimeframes[m_mtfCount] = timeframes[i];
                m_mtfCount++;
            }
        }
        m_mtfEnabled = (m_mtfCount > 0);
        PrintFormat("[BarProcessor] MTF enabled with %d additional timeframes", m_mtfCount);
    }
    
    bool IsMTFEnabled() const { return m_mtfEnabled; }
    int GetMTFCount() const { return m_mtfCount; }
    ENUM_TIMEFRAMES GetMTFTimeframe(int idx) const 
    { 
        return (idx >= 0 && idx < m_mtfCount) ? m_activeMTFTimeframes[idx] : PERIOD_CURRENT; 
    }
    
    bool CheckNewBarMTF(const string symbol, ENUM_TIMEFRAMES tf, int idx)
    {
        if(idx < 0 || idx >= ArraySize(m_symbols)) return false;
        datetime currentBarTime = iTime(symbol, tf, 0);
        if(currentBarTime <= 0) return false;
        
        datetime lastBarTime = GetLastBarTimeMTF(symbol, tf);
        if(lastBarTime <= 0)
        {
            SetLastBarTimeMTF(symbol, tf, currentBarTime);
            return true;
        }
        
        if(lastBarTime < currentBarTime)
        {
            SetLastBarTimeMTF(symbol, tf, currentBarTime);
            return true;
        }
        return false;
    }
    
    datetime GetLastBarTimeMTF(const string symbol, ENUM_TIMEFRAMES tf) const
    {
        return iTime(symbol, tf, 0);
    }
    
    void SetLastBarTimeMTF(const string symbol, ENUM_TIMEFRAMES tf, datetime time)
    {
    }
    
    void SetMaxBackoffTierPreservationBars(int bars) { m_maxBackoffTierPreservationBars = MathMax(1, bars); }
    int GetPreservedBackoffTier() const { return m_preservedBackoffTier; }
    
    void UpdateBackoffTierPreservation(int newTier)
    {
        datetime currentTime = TimeCurrent();
        
        if(newTier > m_preservedBackoffTier)
        {
            m_preservedBackoffTier = newTier;
            m_backoffTierPreservedSince = currentTime;
        }
        else if(newTier < m_preservedBackoffTier)
        {
            int barsSincePreserved = (int)((currentTime - m_backoffTierPreservedSince) / PeriodSeconds(m_timeframe));
            if(barsSincePreserved > m_maxBackoffTierPreservationBars)
            {
                m_preservedBackoffTier = newTier;
                m_backoffTierPreservedSince = currentTime;
            }
        }
    }
    
    bool CheckNewBar(const string symbol, int idx)
    {
        if(idx < 0 || idx >= ArraySize(m_symbols)) return false;
        datetime currentBarTime = iTime(symbol, m_timeframe, 0);
        if(currentBarTime <= 0) return false;
        if(m_lastSymbolBarTimes[idx] < currentBarTime)
        {
            m_lastSymbolBarTimes[idx] = currentBarTime;
            m_pendingNewBarScans[idx] = true;
            return true;
        }
        return false;
    }
    
    bool IsNewBarPending(int idx) const
    {
        if(idx < 0 || idx >= ArraySize(m_pendingNewBarScans)) return false;
        return m_pendingNewBarScans[idx];
    }
    
    void ClearNewBarPending(int idx)
    {
        if(idx >= 0 && idx < ArraySize(m_pendingNewBarScans)) m_pendingNewBarScans[idx] = false;
    }
    
    void PrimeAllNewBarScans(const string reason)
    {
        int size = ArraySize(m_symbols);
        for(int i = 0; i < size; i++)
        {
            m_pendingNewBarScans[i] = true;
            m_symbolScanStates[i].Reset();
            if(m_lastSymbolBarTimes[i] <= 0)
                m_lastSymbolBarTimes[i] = iTime(m_symbols[i], m_timeframe, 0);
        }
    }
    
    void RebuildSchedulerState(const string reason)
    {
        int size = ArraySize(m_symbols);
        ArrayInitialize(m_lastSymbolBarTimes, 0);
        ArrayInitialize(m_lastIntrabarScanTime, 0);
        PrimeAllNewBarScans(reason);
    }
    
    int GetSymbolCount() const { return ArraySize(m_symbols); }
    string GetSymbol(int idx) const { return (idx >= 0 && idx < ArraySize(m_symbols)) ? m_symbols[idx] : ""; }
    datetime GetLastBarTime(int idx) const { return (idx >= 0 && idx < ArraySize(m_lastSymbolBarTimes)) ? m_lastSymbolBarTimes[idx] : 0; }
    void SetLastIntrabarScanTime(int idx, datetime time) { if(idx >= 0 && idx < ArraySize(m_lastIntrabarScanTime)) m_lastIntrabarScanTime[idx] = time; }
};

#endif
