// MarketAnalysisRegime.mqh - Regime state machine and history
// Extracted verbatim from MarketAnalysis.mqh (no behavior change)
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef MARKET_ANALYSIS_REGIME_MQH
#define MARKET_ANALYSIS_REGIME_MQH

#include "../Utils/Enums.mqh"

// Owns the market regime state, the rolling regime history and the
// classification thresholds.
class CMarketAnalysisRegime
{
private:
    ENUM_MARKET_REGIME m_currentRegime;
    ENUM_MARKET_REGIME m_previousRegime;
    datetime m_lastRegimeChange;
    int m_regimeStability; // Counter for regime stability

    ENUM_MARKET_REGIME m_regimeHistory[20];
    datetime m_regimeChangeTime[20];
    int m_regimeHistoryCount;

    double m_trendThreshold;
    double m_volatilityThreshold;

public:
    CMarketAnalysisRegime() :
        m_currentRegime(MARKET_REGIME_RANGING),
        m_previousRegime(MARKET_REGIME_RANGING),
        m_lastRegimeChange(0),
        m_regimeStability(0),
        m_regimeHistoryCount(0)
    {
        // Initialize thresholds based on typical values
        m_trendThreshold = 0.6;     // 60% trend strength needed to confirm trend regime
        m_volatilityThreshold = 0.7; // 70% volatility needed to confirm volatile regime
    }

    //--- Classify the supplied metrics and roll the regime history
    ENUM_MARKET_REGIME UpdateRegime(const string symbol, const double trendStrength, const double volatility);

    ENUM_MARKET_REGIME GetCurrentRegime() const { return m_currentRegime; }

    //--- Set market regime (used when loading from session memory)
    void SetMarketRegime(ENUM_MARKET_REGIME regime) { m_currentRegime = regime; }
};

ENUM_MARKET_REGIME CMarketAnalysisRegime::UpdateRegime(const string symbol, const double trendStrength, const double volatility)
{
    ENUM_MARKET_REGIME detectedRegime = MARKET_REGIME_RANGING;

    // Determine market regime based on calculated metrics and thresholds
    if (trendStrength >= m_trendThreshold) {
        detectedRegime = MARKET_REGIME_TRENDING;
    } else if (volatility >= m_volatilityThreshold) {
        detectedRegime = MARKET_REGIME_VOLATILE;
    } else {
        detectedRegime = MARKET_REGIME_RANGING;
    }

    if(detectedRegime != m_currentRegime) {
        m_previousRegime = m_currentRegime;
        m_currentRegime = detectedRegime;
        m_lastRegimeChange = TimeCurrent();
        m_regimeStability = 0;

        if(m_regimeHistoryCount < ArraySize(m_regimeHistory)) {
            m_regimeHistory[m_regimeHistoryCount] = m_currentRegime;
            m_regimeChangeTime[m_regimeHistoryCount] = m_lastRegimeChange;
            m_regimeHistoryCount++;
        } else {
            for(int i = 0; i < ArraySize(m_regimeHistory) - 1; i++) {
                m_regimeHistory[i] = m_regimeHistory[i+1];
                m_regimeChangeTime[i] = m_regimeChangeTime[i+1];
            }
            m_regimeHistory[ArraySize(m_regimeHistory)-1] = m_currentRegime;
            m_regimeChangeTime[ArraySize(m_regimeHistory)-1] = m_lastRegimeChange;
        }
        PrintFormat("[INFO] Market regime for %s changed to %s (Trend: %.2f, Vol: %.2f)", symbol, EnumToString(m_currentRegime), trendStrength, volatility);
    } else {
        m_regimeStability++;
    }

    return m_currentRegime;
}

#endif // MARKET_ANALYSIS_REGIME_MQH
