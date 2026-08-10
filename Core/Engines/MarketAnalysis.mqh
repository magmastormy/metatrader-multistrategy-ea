//+------------------------------------------------------------------+
//| Enhanced Market Analysis Module                                  |
//| Thin coordinator: state and logic live in the MarketAnalysis*    |
//| modules below; this class only forwards (no behavior change).    |
//+------------------------------------------------------------------+

#ifndef MARKET_ANALYSIS_MQH
#define MARKET_ANALYSIS_MQH

// Include Enums first to ensure all enums are defined
#include "../Utils/Enums.mqh"

// Include required MQL5 headers
#include <Indicators/Indicator.mqh>
#include <Trade/SymbolInfo.mqh>
#include <Arrays/ArrayDouble.mqh>
#include <Object.mqh>
#include <Arrays/ArrayObj.mqh>
#include "../Processing/MultiAssetProfiler.mqh"

// Extracted modules (must come after the dependencies above)
#include "MarketAnalysisTypes.mqh"
#include "MarketAnalysisSymbolProfile.mqh"
#include "MarketAnalysisMetricCache.mqh"
#include "MarketAnalysisIndicators.mqh"
#include "MarketAnalysisMetrics.mqh"
#include "MarketAnalysisRegime.mqh"

// Global profiler access declared in OrchestratorFwd.mqh (extern)
// Forward declarations

class CMarketAnalysis {
private:
    // Indicator context + metric computation + last-valid metric cache
    CMarketAnalysisMetrics m_metrics;

    // Regime state machine, history and thresholds
    CMarketAnalysisRegime m_regime;

public:

    // Check if symbol is available for trading/analysis
    bool IsSymbolAvailable(const string symbolName) const {
        return CMarketAnalysisSymbolProfile::IsSymbolAvailable(symbolName);
    }

    CMarketAnalysis() {
    }

    // Destructor to release indicator handles
    ~CMarketAnalysis() {
        m_metrics.ReleaseAllHandles();
    }

    // Initialize a single indicator and handle errors
    bool InitializeIndicator(int &handle, const string symbolName, const ENUM_TIMEFRAMES period, const string indicatorName,
                            const int param1 = 0, const int param2 = 0, const double param3 = 0, const int param4 = 0) {
        return m_metrics.InitializeIndicator(handle, symbolName, period, indicatorName, param1, param2, param3, param4);
    }

    // Check if symbol is compatible with ADX indicator
    bool IsADXCompatible(const string symbolName) {
        return CMarketAnalysisSymbolProfile::IsADXCompatible(symbolName);
    }

    // Check if symbol needs special indicator handling
    bool RequiresSpecialHandling(const string symbolName) {
        return CMarketAnalysisSymbolProfile::RequiresSpecialHandling(symbolName);
    }

    // Initialize all required indicators for the given symbol and period
    bool InitializeIndicators(const string symbolName, const ENUM_TIMEFRAMES period) {
        return m_metrics.InitializeIndicators(symbolName, period);
    }

    // Detect market regime for a given symbol
    ENUM_MARKET_REGIME DetectMarketRegime() {
        if(!m_metrics.IsRegimeInputReady())
            return m_regime.GetCurrentRegime();

        m_metrics.RefreshCurrentMetrics();

        return m_regime.UpdateRegime(m_metrics.Symbol(),
                                     m_metrics.TrendStrengthValue(),
                                     m_metrics.VolatilityValue());
    }

    // Get current market regime
    ENUM_MARKET_REGIME GetCurrentRegime() const {
        return m_regime.GetCurrentRegime();
    }


    // Set market regime (used when loading from session memory)
    void SetMarketRegime(ENUM_MARKET_REGIME regime) {
        m_regime.SetMarketRegime(regime);
    }

    // Get current market volatility (calculated for the analysed symbol/period)
    double GetCurrentVolatility() const {
        return m_metrics.GetCurrentVolatility();
    }

    // Get current market trend strength (calculated for the analysed symbol/period)
    double GetCurrentTrendStrength() const {
        return m_metrics.GetCurrentTrendStrength();
    }

    // Get current market momentum
    double GetMomentum() const {
        return m_metrics.GetMomentum();
    }

    // Get current ATR value
    double GetATRValue();

    // Get ATR value for a specific symbol and period
    double GetATR(const string symbol, int period);
};

//+------------------------------------------------------------------+
//| Get current ATR value                                            |
//+------------------------------------------------------------------+
double CMarketAnalysis::GetATRValue()
{
    return m_metrics.GetATRValue();
}

//+------------------------------------------------------------------+
//| Get ATR value for a specific symbol and period                   |
//+------------------------------------------------------------------+
double CMarketAnalysis::GetATR(const string symbol, int period)
{
    // For now, return the current ATR value
    // In a more complete implementation, this could handle multiple symbols
    return GetATRValue();
}

#endif
