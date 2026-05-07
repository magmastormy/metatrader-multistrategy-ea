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

class CBarProcessor
{
private:
    string m_symbols[];
    datetime m_lastSymbolBarTimes[];
    datetime m_lastIntrabarScanTime[];
    bool m_pendingNewBarScans[];
    SSymbolScanState m_symbolScanStates[];
    ENUM_TIMEFRAMES m_timeframe;
    
public:
    CBarProcessor() : m_timeframe(PERIOD_CURRENT) {}
    ~CBarProcessor() { ArrayResize(m_symbols, 0); ArrayResize(m_lastSymbolBarTimes, 0); }
    
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
