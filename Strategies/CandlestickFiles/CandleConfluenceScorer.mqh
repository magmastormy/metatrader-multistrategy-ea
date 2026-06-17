//+------------------------------------------------------------------+
//|                                    CandleConfluenceScorer.mqh    |
//|                     Confluence Scoring for Candlestick Patterns   |
//|                     Scores 0-100 based on pattern + location +    |
//|                     trend alignment quality                       |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026"
#property strict

//+------------------------------------------------------------------+
//| Confluence Score Components                                       |
//| Pattern detected: +50 pts                                        |
//| At key level (S/R, EMA, FVG): +30 pts                           |
//| Trend aligned: +20 pts                                           |
//| Signal threshold: >= 70 pts                                      |
//+------------------------------------------------------------------+

class CCandleConfluenceScorer
{
private:
    int    m_score;
    bool   m_patternValid;
    bool   m_atKeyLevel;
    bool   m_trendAligned;
    string m_scoreBreakdown;

public:
    CCandleConfluenceScorer() : m_score(0), m_patternValid(false), m_atKeyLevel(false), m_trendAligned(false), m_scoreBreakdown("") {}

    void Reset()
    {
        m_score = 0;
        m_patternValid = false;
        m_atKeyLevel = false;
        m_trendAligned = false;
        m_scoreBreakdown = "";
    }

    // Add valid pattern detection (50 pts)
    void AddValidPattern(bool yes)
    {
        if(yes)
        {
            m_score += 50;
            m_patternValid = true;
            m_scoreBreakdown += "PAT+50 ";
        }
    }

    // Add key level proximity (30 pts)
    // Key levels: S/R, EMA, FVG zones
    void AddAtKeyLevel(bool yes)
    {
        if(yes)
        {
            m_score += 30;
            m_atKeyLevel = true;
            m_scoreBreakdown += "KEY+30 ";
        }
    }

    // Add trend alignment (20 pts)
    void AddTrendAligned(bool yes)
    {
        if(yes)
        {
            m_score += 20;
            m_trendAligned = true;
            m_scoreBreakdown += "TREND+20 ";
        }
    }

    // Check if confluence score meets signal threshold (>= 70)
    bool HasSignal() const { return m_score >= 70; }

    // Get the raw confluence score (0-100)
    int GetScore() const { return m_score; }

    // Get score as 0-1 confidence value
    double GetConfidence() const { return MathMin(1.0, (double)m_score / 100.0); }

    // Get score breakdown string for logging
    string GetBreakdown() const { return m_scoreBreakdown; }

    // Individual component accessors
    bool IsPatternValid() const { return m_patternValid; }
    bool IsAtKeyLevel() const { return m_atKeyLevel; }
    bool IsTrendAligned() const { return m_trendAligned; }
};
