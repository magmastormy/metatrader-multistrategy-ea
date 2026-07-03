//+------------------------------------------------------------------+
//| ConsensusCache.mqh - Cache consensus results per symbol/mode     |
//| Avoids repeated full consensus evaluation in SRE hot path        |
//+------------------------------------------------------------------+
#ifndef CONSENSUS_CACHE_MQH
#define CONSENSUS_CACHE_MQH

#include "..\Utils\Enums.mqh"

//+------------------------------------------------------------------+
//| Cache Entry Structure                                            |
//+------------------------------------------------------------------+
struct SConsensusCacheEntry
{
    string              symbol;
    ENUM_SIGNAL_EVAL_MODE evalMode;
    ENUM_TRADE_SIGNAL   signal;
    double              confidence;
    int                 confluence;
    uint                computedAtMs;
    bool                valid;

    SConsensusCacheEntry() :
        symbol(""),
        evalMode(EVAL_MODE_NEW_BAR),
        signal(TRADE_SIGNAL_NONE),
        confidence(0.0),
        confluence(0),
        computedAtMs(0),
        valid(false)
    {
    }
};

//+------------------------------------------------------------------+
//| Consensus Cache Class                                            |
//+------------------------------------------------------------------+
class CConsensusCache
{
private:
    SConsensusCacheEntry m_entries[];
    int                  m_maxSymbols;
    uint                 m_ttlMs;
    int                  m_count;

    int FindIndex(const string symbol, ENUM_SIGNAL_EVAL_MODE evalMode) const
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_entries[i].valid &&
               m_entries[i].symbol == symbol &&
               m_entries[i].evalMode == evalMode)
                return i;
        }
        return -1;
    }

    int FindFreeSlot()
    {
        for(int i = 0; i < m_count; i++)
        {
            if(!m_entries[i].valid)
                return i;
        }
        if(m_count < m_maxSymbols)
        {
            int slot = m_count;
            m_count++;
            ArrayResize(m_entries, m_count);
            m_entries[slot] = SConsensusCacheEntry();
            return slot;
        }
        // Evict oldest entry
        uint oldestMs = 0xFFFFFFFF;
        int oldestIdx = 0;
        for(int i = 0; i < m_count; i++)
        {
            if(m_entries[i].computedAtMs < oldestMs)
            {
                oldestMs = m_entries[i].computedAtMs;
                oldestIdx = i;
            }
        }
        m_entries[oldestIdx] = SConsensusCacheEntry();
        return oldestIdx;
    }

public:
    CConsensusCache() :
        m_maxSymbols(20),
        m_ttlMs(1000),
        m_count(0)
    {
        ArrayResize(m_entries, 0);
    }

    void SetTtlMs(uint ttlMs) { m_ttlMs = (ttlMs > 0) ? ttlMs : 1000; }

    bool TryGet(const string symbol,
                ENUM_SIGNAL_EVAL_MODE evalMode,
                ENUM_TRADE_SIGNAL &signal,
                double &confidence,
                int &confluence)
    {
        int idx = FindIndex(symbol, evalMode);
        if(idx < 0 || !m_entries[idx].valid)
            return false;

        uint nowMs = GetTickCount();
        if(nowMs - m_entries[idx].computedAtMs > m_ttlMs)
        {
            m_entries[idx].valid = false;
            return false;
        }

        signal = m_entries[idx].signal;
        confidence = m_entries[idx].confidence;
        confluence = m_entries[idx].confluence;
        return true;
    }

    void Store(const string symbol,
               ENUM_SIGNAL_EVAL_MODE evalMode,
               ENUM_TRADE_SIGNAL signal,
               double confidence,
               int confluence)
    {
        int idx = FindIndex(symbol, evalMode);
        if(idx < 0)
            idx = FindFreeSlot();

        m_entries[idx].symbol = symbol;
        m_entries[idx].evalMode = evalMode;
        m_entries[idx].signal = signal;
        m_entries[idx].confidence = confidence;
        m_entries[idx].confluence = confluence;
        m_entries[idx].computedAtMs = GetTickCount();
        m_entries[idx].valid = true;
    }

    void Invalidate(const string symbol)
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_entries[i].valid && m_entries[i].symbol == symbol)
                m_entries[i].valid = false;
        }
    }

    void InvalidateAll()
    {
        for(int i = 0; i < m_count; i++)
            m_entries[i].valid = false;
        m_count = 0;
        ArrayResize(m_entries, 0);
    }
};

#endif // __CONSENSUS_CACHE_MQH__
