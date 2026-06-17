//+------------------------------------------------------------------+
//| TimeframeConfluence.mqh                                          |
//| Multi-Timeframe Alignment Scorer for ICT Strategies              |
//| Batch 103: Checks H1/M15/M5 structure alignment                 |
//| Copyright 2026, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef __UICT_TIMEFRAME_CONFLUENCE_MQH__
#define __UICT_TIMEFRAME_CONFLUENCE_MQH__

#include "MarketStructureAnalyzer.mqh"

//+------------------------------------------------------------------+
//| Per-Timeframe Cache Structure                                     |
//+------------------------------------------------------------------+
struct STFAlignmentCache
{
    ENUM_TIMEFRAMES timeframe;
    bool            isBullish;
    bool            isBearish;
    bool            isConsolidating;
    datetime        lastBarTime;    // Cache invalidation on new bar
    bool            isValid;

    STFAlignmentCache() : timeframe(PERIOD_CURRENT), isBullish(false), isBearish(false),
                          isConsolidating(true), lastBarTime(0), isValid(false) {}
};

//+------------------------------------------------------------------+
//| Timeframe Confluence Scorer Class                                |
//+------------------------------------------------------------------+
class CTimeframeConfluence
{
private:
    string              m_symbol;
    ENUM_TIMEFRAMES     m_baseTimeframe;

    // Per-timeframe analyzers
    CMarketStructureAnalyzer* m_h1Analyzer;
    CMarketStructureAnalyzer* m_m15Analyzer;
    CMarketStructureAnalyzer* m_m5Analyzer;

    // Per-timeframe caches
    STFAlignmentCache   m_h1Cache;
    STFAlignmentCache   m_m15Cache;
    STFAlignmentCache   m_m5Cache;

    bool                NeedsUpdate(STFAlignmentCache &cache, ENUM_TIMEFRAMES tf)
    {
        datetime barTime = iTime(m_symbol, tf, 0);
        if(barTime != cache.lastBarTime || !cache.isValid)
        {
            cache.lastBarTime = barTime;
            cache.isValid = true;
            return true;
        }
        return false;
    }

    void UpdateCache(STFAlignmentCache &cache, CMarketStructureAnalyzer* analyzer, ENUM_TIMEFRAMES tf)
    {
        if(analyzer == NULL) return;
        if(NeedsUpdate(cache, tf))
        {
            analyzer.Update();
            cache.isBullish = analyzer.IsBullishStructure();
            cache.isBearish = analyzer.IsBearishStructure();
            cache.isConsolidating = !cache.isBullish && !cache.isBearish;
        }
    }

public:
                        CTimeframeConfluence();
                       ~CTimeframeConfluence();

    bool                Initialize(const string symbol, ENUM_TIMEFRAMES baseTimeframe);
    void                Deinit();

    // Get alignment score 0-100 for a given direction
    // direction: 1 = bullish, -1 = bearish
    int                 GetAlignmentScore(int direction);

    // Quick check: is the majority of timeframes aligned?
    bool                IsMajorityAligned(bool bullish);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTimeframeConfluence::CTimeframeConfluence() :
    m_symbol(""),
    m_baseTimeframe(PERIOD_M5),
    m_h1Analyzer(NULL),
    m_m15Analyzer(NULL),
    m_m5Analyzer(NULL)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTimeframeConfluence::~CTimeframeConfluence()
{
    Deinit();
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CTimeframeConfluence::Initialize(const string symbol, ENUM_TIMEFRAMES baseTimeframe)
{
    m_symbol = symbol;
    m_baseTimeframe = baseTimeframe;

    // Create per-timeframe analyzers
    m_h1Analyzer = new CMarketStructureAnalyzer();
    m_m15Analyzer = new CMarketStructureAnalyzer();
    m_m5Analyzer = new CMarketStructureAnalyzer();

    if(m_h1Analyzer == NULL || m_m15Analyzer == NULL || m_m5Analyzer == NULL)
        return false;

    if(!m_h1Analyzer.Initialize(symbol, PERIOD_H1, 3))
    {
        Print("[TF-CONF] Failed to initialize H1 analyzer");
        return false;
    }
    if(!m_m15Analyzer.Initialize(symbol, PERIOD_M15, 3))
    {
        Print("[TF-CONF] Failed to initialize M15 analyzer");
        return false;
    }
    if(!m_m5Analyzer.Initialize(symbol, PERIOD_M5, 3))
    {
        Print("[TF-CONF] Failed to initialize M5 analyzer");
        return false;
    }

    m_h1Cache.timeframe = PERIOD_H1;
    m_m15Cache.timeframe = PERIOD_M15;
    m_m5Cache.timeframe = PERIOD_M5;

    return true;
}

//+------------------------------------------------------------------+
//| Deinit                                                           |
//+------------------------------------------------------------------+
void CTimeframeConfluence::Deinit()
{
    if(m_h1Analyzer != NULL) { delete m_h1Analyzer; m_h1Analyzer = NULL; }
    if(m_m15Analyzer != NULL) { delete m_m15Analyzer; m_m15Analyzer = NULL; }
    if(m_m5Analyzer != NULL) { delete m_m5Analyzer; m_m5Analyzer = NULL; }
}

//+------------------------------------------------------------------+
//| Get Alignment Score — returns 0-100                              |
//| H1 alignment = 40 points, M15 = 30 points, M5 = 30 points      |
//+------------------------------------------------------------------+
int CTimeframeConfluence::GetAlignmentScore(int direction)
{
    // Update caches (per-bar, not per-tick)
    UpdateCache(m_h1Cache, m_h1Analyzer, PERIOD_H1);
    UpdateCache(m_m15Cache, m_m15Analyzer, PERIOD_M15);
    UpdateCache(m_m5Cache, m_m5Analyzer, PERIOD_M5);

    int score = 0;
    bool bullish = (direction > 0);

    // H1 alignment: 40 points
    if(bullish && m_h1Cache.isBullish) score += 40;
    if(!bullish && m_h1Cache.isBearish) score += 40;

    // M15 alignment: 30 points
    if(bullish && m_m15Cache.isBullish) score += 30;
    if(!bullish && m_m15Cache.isBearish) score += 30;

    // M5 alignment: 30 points
    if(bullish && m_m5Cache.isBullish) score += 30;
    if(!bullish && m_m5Cache.isBearish) score += 30;

    return score;
}

//+------------------------------------------------------------------+
//| Is Majority Aligned — at least 2 of 3 timeframes aligned        |
//+------------------------------------------------------------------+
bool CTimeframeConfluence::IsMajorityAligned(bool bullish)
{
    UpdateCache(m_h1Cache, m_h1Analyzer, PERIOD_H1);
    UpdateCache(m_m15Cache, m_m15Analyzer, PERIOD_M15);
    UpdateCache(m_m5Cache, m_m5Analyzer, PERIOD_M5);

    int aligned = 0;
    if(bullish)
    {
        if(m_h1Cache.isBullish) aligned++;
        if(m_m15Cache.isBullish) aligned++;
        if(m_m5Cache.isBullish) aligned++;
    }
    else
    {
        if(m_h1Cache.isBearish) aligned++;
        if(m_m15Cache.isBearish) aligned++;
        if(m_m5Cache.isBearish) aligned++;
    }

    return aligned >= 2;
}

#endif // __UICT_TIMEFRAME_CONFLUENCE_MQH__
