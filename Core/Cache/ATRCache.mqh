//+------------------------------------------------------------------+
//| ATR Value Cache                                                  |
//| Caches ATR values per symbol+timeframe to avoid redundant       |
//| indicator handle reads within a single bar cycle                 |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_CACHE_ATR_CACHE_MQH
#define CORE_CACHE_ATR_CACHE_MQH

#define ATR_CACHE_MAX_ENTRIES 20

struct SATRCacheEntry
{
    string           symbol;
    ENUM_TIMEFRAMES  timeframe;
    double           atrValue;
    datetime         barTime;
    bool             isActive;
};

class CATRCache
{
private:
    SATRCacheEntry   m_entries[ATR_CACHE_MAX_ENTRIES];
    int              m_count;

public:
    CATRCache() : m_count(0)
    {
        Reset();
    }

    void Reset()
    {
        for(int i = 0; i < ATR_CACHE_MAX_ENTRIES; i++)
        {
            m_entries[i].symbol    = "";
            m_entries[i].timeframe = PERIOD_CURRENT;
            m_entries[i].atrValue  = 0.0;
            m_entries[i].barTime   = 0;
            m_entries[i].isActive  = false;
        }
        m_count = 0;
    }

    double GetATR(const string symbol, const ENUM_TIMEFRAMES tf)
    {
        datetime currentBarTime = iTime(symbol, tf, 0);
        if(currentBarTime == 0)
            return INVALID_VALUE;

        for(int i = 0; i < m_count; i++)
        {
            if(m_entries[i].isActive &&
               m_entries[i].symbol == symbol &&
               m_entries[i].timeframe == tf)
            {
                if(m_entries[i].barTime == currentBarTime)
                    return m_entries[i].atrValue;
                else
                {
                    m_entries[i].isActive = false;
                    return INVALID_VALUE;
                }
            }
        }
        return INVALID_VALUE;
    }

    void StoreATR(const string symbol, const ENUM_TIMEFRAMES tf, const double value, const datetime barTime)
    {
        if(value <= 0.0 || barTime == 0)
            return;

        for(int i = 0; i < m_count; i++)
        {
            if(m_entries[i].isActive &&
               m_entries[i].symbol == symbol &&
               m_entries[i].timeframe == tf)
            {
                m_entries[i].atrValue = value;
                m_entries[i].barTime  = barTime;
                return;
            }
        }

        if(m_count < ATR_CACHE_MAX_ENTRIES)
        {
            m_entries[m_count].symbol   = symbol;
            m_entries[m_count].timeframe = tf;
            m_entries[m_count].atrValue  = value;
            m_entries[m_count].barTime   = barTime;
            m_entries[m_count].isActive  = true;
            m_count++;
        }
        else
        {
            for(int i = 0; i < m_count; i++)
            {
                if(!m_entries[i].isActive)
                {
                    m_entries[i].symbol    = symbol;
                    m_entries[i].timeframe = tf;
                    m_entries[i].atrValue  = value;
                    m_entries[i].barTime   = barTime;
                    m_entries[i].isActive  = true;
                    return;
                }
            }
            m_entries[0].symbol    = symbol;
            m_entries[0].timeframe = tf;
            m_entries[0].atrValue  = value;
            m_entries[0].barTime   = barTime;
            m_entries[0].isActive  = true;
        }
    }
};

#endif // CORE_CACHE_ATR_CACHE_MQH
