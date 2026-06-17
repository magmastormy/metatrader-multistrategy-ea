//+------------------------------------------------------------------+
//| SRSignalScorer.mqh                                               |
//| Weighted Soft Confluence Scoring for S/R Bounce Strategy          |
//| Batch 103: Replaces hard AND logic with 0-100 scoring             |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef __SR_SIGNAL_SCORER_MQH__
#define __SR_SIGNAL_SCORER_MQH__

//+------------------------------------------------------------------+
//| S/R Signal Scorer Class                                          |
//| Weighted scoring instead of hard AND requirements                |
//| Score >= 60 required for signal (out of 100 possible)            |
//+------------------------------------------------------------------+
class CSRSignalScorer
{
private:
    int m_score;

public:
    void Reset() { m_score = 0; }

    // Weighted condition checks (total = 100)
    void AddPriceAtLevel(bool yes)         { if(yes) m_score += 30; }  // Most important
    void AddCandleRejection(bool yes)      { if(yes) m_score += 25; }  // Strong confirmation
    void AddEMAAligned(bool yes)           { if(yes) m_score += 20; }  // Trend alignment
    void AddTrendlineConfluence(bool yes)  { if(yes) m_score += 15; }  // Extra confluence
    void AddMultipleTouches(bool yes)      { if(yes) m_score += 10; }  // Level quality

    // Signal threshold: 60+ out of 100
    bool HasSignal() const { return m_score >= 60; }
    int  GetScore()  const { return m_score; }
};

#endif // __SR_SIGNAL_SCORER_MQH__
