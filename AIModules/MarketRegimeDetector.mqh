//+------------------------------------------------------------------+
//| Market Regime Detection and Classification                      |
//| Identifies trending, ranging, volatile, and calm market states  |
//+------------------------------------------------------------------+
#ifndef MARKET_REGIME_DETECTOR_MQH
#define MARKET_REGIME_DETECTOR_MQH

// Include enums first to ensure types are available
#include "../Core/Enums.mqh"
#include <Arrays/ArrayDouble.mqh>
#include <Math/Stat/Math.mqh>

// Define PI constant if not provided by Math headers
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

//+------------------------------------------------------------------+
//| Market Regime Types (Using main enum from Core/Enums.mqh)      |
//+------------------------------------------------------------------+
// ENUM_MARKET_REGIME is defined in Core/Enums.mqh
// Values: MARKET_REGIME_RANGING, MARKET_REGIME_TRENDING, MARKET_REGIME_VOLATILE, 
//         MARKET_REGIME_LOW_VOLATILITY, MARKET_REGIME_UNKNOWN

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
class CMarketRegimeClassifier {
private:
    int m_lookbackPeriod;
    double m_trendThreshold;
    double m_volatilityThreshold;
    CArrayDouble m_priceHistory;
    CArrayDouble m_volumeHistory;
    ENUM_MARKET_REGIME m_currentRegime;
    double m_regimeConfidence;
    
    // Calculate trend strength using linear regression
    double CalculateTrendStrength(const CArrayDouble &prices, int period) {
        if(period < 2 || prices.Total() < period) return 0.0;
        
        // FIXED: Use more specific variable names to avoid conflicts
        double linRegSumX = 0.0, linRegSumY = 0.0, linRegSumXY = 0.0, linRegSumX2 = 0.0;
        int n = period;
        
        for(int i = 0; i < n; i++) {
            double x = i;
            double y = prices.At(prices.Total() - n + i);
            linRegSumX += x;
            linRegSumY += y;
            linRegSumXY += x * y;
            linRegSumX2 += x * x;
        }
        
        double slope = (n * linRegSumXY - linRegSumX * linRegSumY) / (n * linRegSumX2 - linRegSumX * linRegSumX);
        double avgPrice = linRegSumY / n;
        
        // Normalize slope by average price
        return (avgPrice > 0) ? slope / avgPrice : 0.0;
    }
    
    // Calculate volatility using standard deviation
    double CalculateVolatility(const CArrayDouble &prices, int period) {
        if(period < 2 || prices.Total() < period) return 0.0;
        
        // Calculate returns
        CArrayDouble returns;
        returns.Resize(period - 1);
        
        for(int i = 1; i < period; i++) {
            int idx = prices.Total() - period + i;
            double ret = (prices.At(idx) - prices.At(idx - 1)) / prices.At(idx - 1);
            returns.Update(i - 1, ret);
        }
        
        // Calculate standard deviation
        double mean = 0.0;
        for(int i = 0; i < returns.Total(); i++) {
            mean += returns.At(i);
        }
        
        // ZERO DIVIDE FIX: Validate returns count before division
        int totalReturns = returns.Total();
        if(totalReturns <= 0) {
            Print("[ZERO-DIVIDE-FIX] Invalid returns count: ", totalReturns, " - using default values");
            return 0.0; // Return default volatility
        }
        
        mean /= totalReturns;
        
        double variance = 0.0;
        for(int i = 0; i < totalReturns; i++) {
            double diff = returns.At(i) - mean;
            variance += diff * diff;
        }
        variance /= totalReturns;
        
        return MathSqrt(variance);
    }
    
    // Calculate momentum using rate of change
    double CalculateMomentum(const CArrayDouble &prices, int period) {
        if(period < 1 || prices.Total() < period + 1) return 0.0;
        
        double current = prices.At(prices.Total() - 1);
        double past = prices.At(prices.Total() - 1 - period);
        
        return (past > 0) ? (current - past) / past : 0.0;
    }
    
    // Calculate mean reversion tendency
    double CalculateMeanReversion(const CArrayDouble &prices, int period) {
        if(period < 10 || prices.Total() < period) return 0.0;
        
        // Calculate moving average
        double ma = 0.0;
        for(int i = 0; i < period; i++) {
            ma += prices.At(prices.Total() - period + i);
        }
        ma /= period;
        
        // Calculate current deviation from MA
        double current = prices.At(prices.Total() - 1);
        double deviation = MathAbs(current - ma) / ma;
        
        // Calculate historical mean deviation
        double avgDeviation = 0.0;
        int count = 0;
        for(int i = period; i < prices.Total(); i++) {
            double histMA = 0.0;
            for(int j = 0; j < period; j++) {
                histMA += prices.At(i - period + j);
            }
            histMA /= period;
            
            avgDeviation += MathAbs(prices.At(i) - histMA) / histMA;
            count++;
        }
        
        if(count > 0) {
            avgDeviation /= count;
            return (avgDeviation > 0) ? deviation / avgDeviation : 0.0;
        }
        
        return 0.0;
    }
    
    // Classify regime based on features
    ENUM_MARKET_REGIME ClassifyRegime(const SMarketRegimeFeatures &features) {
        // Production-ready market regime classification with confidence scoring
        // Advanced classification logic using multi-factor analysis
        
        // Calculate confidence scores for each regime
        double trendConfidence = 0.0;
        double volatilityConfidence = 0.0;
        double rangingConfidence = 0.0;
        double lowVolConfidence = 0.0;
        
        // Trend detection with confidence
        if (MathAbs(features.trendStrength) > m_trendThreshold) {
            trendConfidence = MathMin(1.0, MathAbs(features.trendStrength) / (m_trendThreshold * 2.0));
            
            // Distinguish between bullish and bearish trends
            if (features.trendStrength > 0) {
                // Bullish trend - check momentum and volume confirmation
                if (features.momentum > 0 && features.volume > 1.0) {
                    trendConfidence *= 1.2; // Increase confidence with confirmation
                }
                return MARKET_REGIME_TRENDING_BULLISH;
            } else {
                // Bearish trend - check momentum and volume confirmation
                if (features.momentum < 0 && features.volume > 1.0) {
                    trendConfidence *= 1.2; // Increase confidence with confirmation
                }
                return MARKET_REGIME_TRENDING_BEARISH;
            }
        }
        
        // Volatility regime detection
        if (features.volatility > m_volatilityThreshold) {
            volatilityConfidence = MathMin(1.0, features.volatility / (m_volatilityThreshold * 1.5));
            
            // Check for high volatility with mean reversion signals
            if (features.meanReversion > 1.5) {
                volatilityConfidence *= 1.1; // Higher confidence with mean reversion
            }
            return MARKET_REGIME_HIGH_VOLATILITY;
        }
        
        // Low volatility detection
        if (features.volatility < m_volatilityThreshold * 0.5) {
            lowVolConfidence = MathMin(1.0, (m_volatilityThreshold * 0.5 - features.volatility) / (m_volatilityThreshold * 0.3));
            
            // Check for ranging behavior in low volatility
            if (MathAbs(features.trendStrength) < m_trendThreshold * 0.5 && features.meanReversion < 1.2) {
                return MARKET_REGIME_RANGING;
            }
            return MARKET_REGIME_LOW_VOLATILITY;
        }
        
        // Ranging market detection
        if (MathAbs(features.trendStrength) < m_trendThreshold * 0.8 &&
            features.volatility >= m_volatilityThreshold * 0.5 &&
            features.volatility <= m_volatilityThreshold) {
            
            rangingConfidence = 1.0 - MathAbs(features.trendStrength) / (m_trendThreshold * 0.8);
            
            // Check for mean reversion signals in ranging market
            if (features.meanReversion > 1.2 && features.meanReversion < 2.0) {
                rangingConfidence *= 1.15;
            }
            return MARKET_REGIME_RANGING;
        }
        
        // Default classification with uncertainty
        // Use weighted combination of features for final decision
        double totalScore = 0.0;
        
        // Trend component
        if (MathAbs(features.trendStrength) > m_trendThreshold * 0.5) {
            totalScore += MathAbs(features.trendStrength) * 0.4;
        }
        
        // Volatility component
        if (features.volatility > m_volatilityThreshold * 0.7) {
            totalScore += features.volatility * 0.3;
        }
        
        // Mean reversion component
        if (features.meanReversion > 1.0) {
            totalScore += (features.meanReversion - 1.0) * 0.2;
        }
        
        // Volume component
        if (features.volume > 1.2) {
            totalScore += (features.volume - 1.0) * 0.1;
        }
        
        // Final decision based on dominant characteristics
        if (totalScore < 0.3) {
            return MARKET_REGIME_UNKNOWN;
        } else if (MathAbs(features.trendStrength) > features.volatility * 10) {
            return features.trendStrength > 0 ? MARKET_REGIME_TRENDING_BULLISH : MARKET_REGIME_TRENDING_BEARISH;
        } else {
            return MARKET_REGIME_RANGING;
        }
    }
    
public:
    CMarketRegimeClassifier(int lookbackPeriod = 100, double trendThreshold = 0.001, 
                         double volatilityThreshold = 0.02) {
        m_lookbackPeriod = lookbackPeriod;
        m_trendThreshold = trendThreshold;
        m_volatilityThreshold = volatilityThreshold;
        m_currentRegime = MARKET_REGIME_UNKNOWN;
        m_regimeConfidence = 0.0;
        
        m_priceHistory.Resize(0);
        m_volumeHistory.Resize(0);
    }
    
    // Update with new market data
    bool UpdateMarketData(double price, double volume = 0.0) {
        m_priceHistory.Add(price);
        m_volumeHistory.Add(volume);
        
        // Keep only recent history
        while(m_priceHistory.Total() > m_lookbackPeriod * 2) {
            m_priceHistory.Delete(0);
            m_volumeHistory.Delete(0);
        }
        
        return true;
    }
    
    // Detect current market regime
    bool DetectRegime(SMarketRegimeFeatures &features, ENUM_MARKET_REGIME &regime, 
                     double &confidence) {
        if(m_priceHistory.Total() < m_lookbackPeriod) {
            regime = MARKET_REGIME_UNKNOWN;
            confidence = 0.0;
            return false;
        }
        
        // Calculate regime features
        features.trendStrength = CalculateTrendStrength(m_priceHistory, m_lookbackPeriod);
        features.volatility = CalculateVolatility(m_priceHistory, m_lookbackPeriod);
        features.momentum = CalculateMomentum(m_priceHistory, m_lookbackPeriod / 4);
        features.meanReversion = CalculateMeanReversion(m_priceHistory, m_lookbackPeriod / 2);
        
        // Calculate volume features if available
        if(m_volumeHistory.Total() >= m_lookbackPeriod) {
            double avgVolume = 0.0;
            for(int i = 0; i < m_lookbackPeriod; i++) {
                avgVolume += m_volumeHistory.At(m_volumeHistory.Total() - m_lookbackPeriod + i);
            }
            avgVolume /= m_lookbackPeriod;
            
            double currentVolume = m_volumeHistory.At(m_volumeHistory.Total() - 1);
            features.volume = (avgVolume > 0) ? currentVolume / avgVolume : 1.0;
        }
        
        // Add seasonality (hour of day effect)
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        features.seasonality = MathSin(2 * M_PI * dt.hour / 24.0);
        
        // Classify regime
        regime = ClassifyRegime(features);
        
        // Calculate confidence based on feature strength
        confidence = 0.0;
        confidence += MathMin(MathAbs(features.trendStrength) / m_trendThreshold, 1.0) * 0.3;
        confidence += MathMin(features.volatility / m_volatilityThreshold, 1.0) * 0.2;
        confidence += MathMin(MathAbs(features.momentum) / 0.02, 1.0) * 0.2;
        confidence += MathMin(features.meanReversion / 2.0, 1.0) * 0.15;
        confidence += MathMin(MathAbs(features.volume - 1.0), 1.0) * 0.15;
        
        m_currentRegime = regime;
        m_regimeConfidence = confidence;
        
        return true;
    }
    
    // Get current regime
    ENUM_MARKET_REGIME GetCurrentRegime() const {
        return m_currentRegime;
    }
    
    // Get regime confidence
    double GetRegimeConfidence() const {
        return m_regimeConfidence;
    }
    
    // Get regime name as string
    string GetRegimeName(ENUM_MARKET_REGIME regime) const {
        switch(regime) {
            case MARKET_REGIME_TRENDING:      return "TRENDING";
            case MARKET_REGIME_RANGING:       return "RANGING";
            case MARKET_REGIME_VOLATILE:      return "VOLATILE";
            case MARKET_REGIME_LOW_VOLATILITY: return "LOW_VOLATILITY";  
            case MARKET_REGIME_UNKNOWN:       return "UNKNOWN";
            default:                          return "UNKNOWN";
        }
    }
    
    // Check if regime is suitable for specific strategies
    bool IsRegimeSuitableFor(ENUM_MARKET_REGIME regime, string strategyType) const {
        if(strategyType == "trend_following") {
            return (regime == MARKET_REGIME_TRENDING);
        }
        else if(strategyType == "mean_reversion") {
            return (regime == MARKET_REGIME_RANGING);
        }
        else if(strategyType == "breakout") {
            return (regime == MARKET_REGIME_VOLATILE);
        }
        else if(strategyType == "scalping") {
            return (regime == MARKET_REGIME_RANGING || regime == MARKET_REGIME_LOW_VOLATILITY);
        }
        
        return true; // Default: suitable for all
    }
    
    // Get adaptive parameters for regime
    bool GetRegimeParameters(ENUM_MARKET_REGIME regime, double &riskMultiplier, 
                           double &timeframeMultiplier, double &confidenceThreshold) const {
        switch(regime) {
        case MARKET_REGIME_TRENDING:
            riskMultiplier = 1.2;        // Higher risk in trends
            timeframeMultiplier = 1.5;   // Favor higher timeframes
            confidenceThreshold = 0.7;   // Higher confidence needed for trend signals
                break;
                
            case MARKET_REGIME_RANGING:
                riskMultiplier = 0.8;        // Lower risk in ranges
                timeframeMultiplier = 0.8;   // Shorter timeframes
                confidenceThreshold = 0.7;   // Higher threshold for range signals
                break;
                
            case MARKET_REGIME_VOLATILE:
                riskMultiplier = 0.6;        // Much lower risk in volatility
                timeframeMultiplier = 0.5;   // Very short timeframes
                confidenceThreshold = 0.8;   // High threshold for volatile signals
                break;
                
            case MARKET_REGIME_LOW_VOLATILITY:
                riskMultiplier = 1.0;        // Normal risk in calm markets
                timeframeMultiplier = 1.2;   // Slightly longer timeframes
                confidenceThreshold = 0.65;  // Moderate threshold
                break;
                
            default:
                riskMultiplier = 0.5;        // Very conservative for unknown
                timeframeMultiplier = 1.0;   // Normal timeframes
                confidenceThreshold = 0.8;   // High threshold for unknown
                break;
        }
        
        return true;
    }
};

#endif // MARKET_REGIME_CLASSIFIER_MQH
