#property copyright "Copyright 2026"
#property strict

// Score = 50 (valid pattern) + 30 (key level: S/R, EMA, FVG) + 20 (trend aligned).
// HasSignal needs >= 70, so a detected pattern on its own never signals.

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

    void AddValidPattern(bool yes)
    {
        if(yes)
        {
            m_score += 50;
            m_patternValid = true;
            m_scoreBreakdown += "PAT+50 ";
        }
    }

    void AddAtKeyLevel(bool yes)
    {
        if(yes)
        {
            m_score += 30;
            m_atKeyLevel = true;
            m_scoreBreakdown += "KEY+30 ";
        }
    }

    void AddTrendAligned(bool yes)
    {
        if(yes)
        {
            m_score += 20;
            m_trendAligned = true;
            m_scoreBreakdown += "TREND+20 ";
        }
    }

    bool HasSignal() const { return m_score >= 70; }

    int GetScore() const { return m_score; }

    double GetConfidence() const { return MathMin(1.0, (double)m_score / 100.0); }

    string GetBreakdown() const { return m_scoreBreakdown; }

    bool IsPatternValid() const { return m_patternValid; }
    bool IsAtKeyLevel() const { return m_atKeyLevel; }
    bool IsTrendAligned() const { return m_trendAligned; }
};
