//+------------------------------------------------------------------+
//| Market Regime Detection and Classification                      |
//| Identifies trending, ranging, volatile, and calm market states  |
//+------------------------------------------------------------------+
#ifndef MARKET_REGIME_DETECTOR_MQH
#define MARKET_REGIME_DETECTOR_MQH

// Include enums first to ensure types are available
#include "Enums.mqh"
#include <Arrays/ArrayDouble.mqh>
#include <Math/Stat/Math.mqh>

// Define PI constant if not provided by Math headers
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

//+------------------------------------------------------------------+
//| Market Regime Features                                          |
//+------------------------------------------------------------------+
struct SMarketRegimeFeatures {
    double trendStrength;      // -1 to 1 (bearish to bullish)
    double volatility;         // 0 to 1 (calm to volatile)
    double momentum;           // Rate of price change
    double meanReversion;      // Tendency to revert to mean
    double volume;             // Relative volume
    double correlation;        // Cross-asset correlation
    double seasonality;        // Time-based patterns
    
    SMarketRegimeFeatures() {
        trendStrength = 0.0;
        volatility = 0.0;
        momentum = 0.0;
        meanReversion = 0.0;
        volume = 0.0;
        correlation = 0.0;
        seasonality = 0.0;
    }
};

//+------------------------------------------------------------------+
//| Market Regime Classifier Class                                   |
//+------------------------------------------------------------------+
class CMarketRegimeClassifier
{
private:
    int m_lookbackPeriod;
    double m_trendThreshold;
    double m_volatilityThreshold;
    CArrayDouble m_priceHistory;
    CArrayDouble m_volumeHistory;
    
    // Internal calculation methods
    double CalculateTrendStrength(const CArrayDouble &prices);
    double CalculateVolatility(const CArrayDouble &prices);
    double CalculateMomentum(const CArrayDouble &prices);
    double CalculateMeanReversion(const CArrayDouble &prices);
    double CalculateVolumeRatio(const CArrayDouble &volumes);
    
public:
    CMarketRegimeClassifier(int lookbackPeriod = 100, double trendThreshold = 0.001, 
                         double volatilityThreshold = 0.02);
    ~CMarketRegimeClassifier();
    
    // Main classification method
    ENUM_MARKET_REGIME ClassifyMarketRegime(const string symbol, const ENUM_TIMEFRAMES timeframe);
    
    // Get detailed regime features
    SMarketRegimeFeatures GetRegimeFeatures(const string symbol, const ENUM_TIMEFRAMES timeframe);
    
    // Get regime-specific parameters for strategy adaptation
    bool GetRegimeParameters(ENUM_MARKET_REGIME regime, double &riskMultiplier, 
                           double &timeframeMultiplier, double &confidenceThreshold) const;
    
    // Update with new price data
    void UpdatePriceData(double price, double volume = 0.0);
    
    // Reset history
    void Reset();
};

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CMarketRegimeClassifier::CMarketRegimeClassifier(int lookbackPeriod, double trendThreshold, 
                                              double volatilityThreshold)
{
    m_lookbackPeriod = lookbackPeriod;
    m_trendThreshold = trendThreshold;
    m_volatilityThreshold = volatilityThreshold;
    m_priceHistory.Resize(lookbackPeriod);
    m_volumeHistory.Resize(lookbackPeriod);
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CMarketRegimeClassifier::~CMarketRegimeClassifier()
{
    m_priceHistory.Shutdown();
    m_volumeHistory.Shutdown();
}

//+------------------------------------------------------------------+
//| Classify market regime                                          |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME CMarketRegimeClassifier::ClassifyMarketRegime(const string symbolParam,
                                                               const ENUM_TIMEFRAMES timeframe)
{
    SMarketRegimeFeatures features = GetRegimeFeatures(symbolParam, timeframe);
    
    // Simple classification logic - can be enhanced with ML models
    if (MathAbs(features.trendStrength) > m_trendThreshold) {
        return MARKET_REGIME_TRENDING;
    } 
    else if (features.volatility > m_volatilityThreshold) {
        return MARKET_REGIME_VOLATILE;
    }
    else if (features.volatility < m_volatilityThreshold * 0.5) {
        return MARKET_REGIME_LOW_VOLATILITY;
    }
    
    return MARKET_REGIME_RANGING;
}

//+------------------------------------------------------------------+
//| Get detailed regime features                                    |
//+------------------------------------------------------------------+
SMarketRegimeFeatures CMarketRegimeClassifier::GetRegimeFeatures(const string symbolParam,
                                                               const ENUM_TIMEFRAMES timeframe)
{
    SMarketRegimeFeatures features;
    
    // Get price history if not already populated
    if (m_priceHistory.Total() < m_lookbackPeriod) {
        double close[];
        ArraySetAsSeries(close, true);
        CopyClose(symbolParam, timeframe, 0, m_lookbackPeriod, close);
        
        m_priceHistory.Clear();
        for (int i = 0; i < m_lookbackPeriod; i++) {
            m_priceHistory.Add(close[i]);
        }
    }
    
    // Calculate features
    features.trendStrength = CalculateTrendStrength(m_priceHistory);
    features.volatility = CalculateVolatility(m_priceHistory);
    features.momentum = CalculateMomentum(m_priceHistory);
    features.meanReversion = CalculateMeanReversion(m_priceHistory);
    
    // Add volume data if available
    if (m_volumeHistory.Total() > 0) {
        features.volume = CalculateVolumeRatio(m_volumeHistory);
    }
    
    return features;
}

//+------------------------------------------------------------------+
//| Calculate trend strength using linear regression                |
//+------------------------------------------------------------------+
double CMarketRegimeClassifier::CalculateTrendStrength(const CArrayDouble &prices)
{
    if (prices.Total() < 2) return 0.0;
    
    double sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0;
    int n = prices.Total();
    
    for (int i = 0; i < n; i++) {
        sumX += i;
        sumY += prices.At(i);
        sumXY += i * prices.At(i);
        sumX2 += i * i;
    }
    
    double slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
    double avgPrice = sumY / n;
    
    // Normalize slope by average price to get percentage change
    return (avgPrice != 0.0) ? (slope * n) / avgPrice : 0.0;
}

//+------------------------------------------------------------------+
//| Calculate volatility as standard deviation of returns           |
//+------------------------------------------------------------------+
double CMarketRegimeClassifier::CalculateVolatility(const CArrayDouble &prices)
{
    if (prices.Total() < 2) return 0.0;
    
    // Calculate log returns
    CArrayDouble returns;
    for (int i = 1; i < prices.Total(); i++) {
        if (prices.At(i-1) > 0) {
            returns.Add(MathLog(prices.At(i) / prices.At(i-1)));
        }
    }
    
    // Calculate standard deviation of returns
    double sum = 0.0, sum2 = 0.0;
    for (int i = 0; i < returns.Total(); i++) {
        sum += returns.At(i);
        sum2 += returns.At(i) * returns.At(i);
    }
    
    double mean = sum / returns.Total();
    double variance = (sum2 - 2 * mean * sum + returns.Total() * mean * mean) / returns.Total();
    
    // Annualize the volatility (assuming daily data)
    return MathSqrt(variance) * MathSqrt(252.0);
}

//+------------------------------------------------------------------+
//| Calculate momentum as rate of change                            |
//+------------------------------------------------------------------+
double CMarketRegimeClassifier::CalculateMomentum(const CArrayDouble &prices)
{
    if (prices.Total() < 2) return 0.0;
    
    int n = MathMin(10, prices.Total() - 1);
    return (prices.At(0) - prices.At(n)) / prices.At(n);
}

//+------------------------------------------------------------------+
//| Calculate mean reversion using Hurst exponent                   |
//+------------------------------------------------------------------+
double CMarketRegimeClassifier::CalculateMeanReversion(const CArrayDouble &prices)
{
    // Simplified version - returns 0.5 for random walk, < 0.5 for mean-reverting
    if (prices.Total() < 10) return 0.5;
    
    double sum = 0.0;
    for (int i = 1; i < prices.Total(); i++) {
        sum += MathLog(prices.At(i) / prices.At(i-1));
    }
    
    double mean = sum / (prices.Total() - 1);
    double variance = 0.0;
    
    for (int i = 1; i < prices.Total(); i++) {
        double diff = MathLog(prices.At(i) / prices.At(i-1)) - mean;
        variance += diff * diff;
    }
    
    variance /= (prices.Total() - 1);
    
    // Simplified Hurst exponent estimation
    return 0.5 * (1.0 - MathLog(variance) / MathLog(prices.Total() - 1));
}

//+------------------------------------------------------------------+
//| Calculate volume ratio                                          |
//+------------------------------------------------------------------+
double CMarketRegimeClassifier::CalculateVolumeRatio(const CArrayDouble &volumes)
{
    if (volumes.Total() < 2) return 1.0;
    
    // Calculate average volume over the lookback period
    double sum = 0.0;
    for (int i = 0; i < volumes.Total(); i++) {
        sum += volumes.At(i);
    }
    double avgVolume = sum / volumes.Total();
    
    // Return ratio of current volume to average
    return (avgVolume > 0) ? volumes.At(0) / avgVolume : 1.0;
}

//+------------------------------------------------------------------+
//| Get regime-specific parameters                                  |
//+------------------------------------------------------------------+
bool CMarketRegimeClassifier::GetRegimeParameters(ENUM_MARKET_REGIME regime, 
                                                double &riskMultiplier, 
                                                double &timeframeMultiplier, 
                                                double &confidenceThreshold) const
{
    switch(regime) {
        case MARKET_REGIME_TRENDING:
            riskMultiplier = 1.2;        // Higher risk in trends
            timeframeMultiplier = 1.5;   // Favor higher timeframes
            confidenceThreshold = 0.7;   // Higher confidence needed
            break;
            
        case MARKET_REGIME_RANGING:
            riskMultiplier = 0.8;        // Lower risk in ranging
            timeframeMultiplier = 0.7;   // Favor lower timeframes
            confidenceThreshold = 0.6;
            break;
            
        case MARKET_REGIME_VOLATILE:
            riskMultiplier = 0.5;        // Much lower risk in high volatility
            timeframeMultiplier = 1.0;
            confidenceThreshold = 0.8;   // Highest confidence needed
            break;
            
        case MARKET_REGIME_LOW_VOLATILITY:
            riskMultiplier = 1.0;
            timeframeMultiplier = 1.0;
            confidenceThreshold = 0.5;   // Lower confidence threshold
            break;
            
        default:
            riskMultiplier = 1.0;
            timeframeMultiplier = 1.0;
            confidenceThreshold = 0.5;
            return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Update with new price data                                      |
//+------------------------------------------------------------------+
void CMarketRegimeClassifier::UpdatePriceData(double price, double volume)
{
    // Shift arrays
    for (int i = m_priceHistory.Total() - 1; i > 0; i--) {
        m_priceHistory.Update(i, m_priceHistory.At(i-1));
    }
    
    // Add new price
    m_priceHistory.Update(0, price);
    
    // Update volume if provided
    if (volume > 0) {
        for (int i = m_volumeHistory.Total() - 1; i > 0; i--) {
            m_volumeHistory.Update(i, m_volumeHistory.At(i-1));
        }
        m_volumeHistory.Update(0, volume);
    }
}

//+------------------------------------------------------------------+
//| Reset history                                                   |
//+------------------------------------------------------------------+
void CMarketRegimeClassifier::Reset()
{
    m_priceHistory.Clear();
    m_volumeHistory.Clear();
}

#endif // MARKET_REGIME_DETECTOR_MQH
