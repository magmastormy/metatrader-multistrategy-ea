//+------------------------------------------------------------------+
//| Uncertainty Quantification and Confidence Estimation           |
//| Provides confidence intervals and risk-aware predictions        |
//+------------------------------------------------------------------+
#ifndef __UNCERTAINTY_QUANTIFIER_MQH__
#define __UNCERTAINTY_QUANTIFIER_MQH__

#include <Math\Stat\Math.mqh>

//+------------------------------------------------------------------+
//| Prediction with Uncertainty (Extended version)                 |
//+------------------------------------------------------------------+
// Extended struct with additional fields beyond CommonTypes.mqh
struct SPredictionWithUncertainty {
    double prediction;         // Main prediction
    double lowerBound;        // Lower confidence bound
    double upperBound;        // Upper confidence bound
    double uncertainty;       // Uncertainty measure (0-1)
    double confidence;        // Confidence level (0-1)
    double entropy;           // Prediction entropy
    datetime timestamp;       // From base struct
    bool isValid;             // From base struct
    
    SPredictionWithUncertainty() {
        prediction = 0.0;
        lowerBound = 0.0;
        upperBound = 0.0;
        uncertainty = 1.0;
        confidence = 0.0;
        entropy = 0.0;
        timestamp = 0;
        isValid = false;
    }
};

//+------------------------------------------------------------------+
//| Uncertainty Quantification Methods                             |
//+------------------------------------------------------------------+
class CUncertaintyQuantifier {
private:
    double m_predictionHistory[];
    double m_errorHistory[];
    
    int m_historySize;
    int m_predictionHead;
    int m_predictionCount;
    int m_errorHead;
    int m_errorCount;
    double m_confidenceLevel;
    bool m_initialized;

    // Realized volatility from price returns (not prediction signals)
    double m_priceReturnHistory[];
    int m_priceReturnHead;
    int m_priceReturnCount;
    int m_priceReturnSize;

    void RingPush(double &values[], int &head, int &count, const double value)
    {
        // Validate all parameters before accessing array
        if(m_historySize <= 0)
        {
            static datetime s_lastLog = 0;
            if(s_lastLog == 0 || (TimeCurrent() - s_lastLog) >= 300)
            {
                Print("[UNCERTAINTY] ERROR: RingPush called with invalid historySize=", m_historySize);
                s_lastLog = TimeCurrent();
            }
            return;
        }

        int arrSize = ArraySize(values);
        if(arrSize <= 0)
        {
            static datetime s_lastLog2 = 0;
            if(s_lastLog2 == 0 || (TimeCurrent() - s_lastLog2) >= 300)
            {
                Print("[UNCERTAINTY] ERROR: RingPush called with empty array");
                s_lastLog2 = TimeCurrent();
            }
            return;
        }

        // Validate head index is within bounds
        if(head < 0 || head >= arrSize)
        {
            static datetime s_lastLog3 = 0;
            if(s_lastLog3 == 0 || (TimeCurrent() - s_lastLog3) >= 300)
            {
                PrintFormat("[UNCERTAINTY] ERROR: RingPush head=%d out of bounds [0,%d]", head, arrSize - 1);
                s_lastLog3 = TimeCurrent();
            }
            head = 0;  // Reset to safe value
        }

        values[head] = value;
        head = (head + 1) % m_historySize;
        if(count < m_historySize)
            count++;
    }

    double RingGet(const double &values[], const int head, const int count, const int logicalIndex) const
    {
        if(count <= 0 || logicalIndex < 0 || logicalIndex >= count || m_historySize <= 0)
            return 0.0;

        int physicalIndex = (head - count + logicalIndex + m_historySize) % m_historySize;
        return values[physicalIndex];
    }
    
    // Calculate prediction entropy
    double CalculateEntropy(double buyProb, double sellProb, double holdProb) {
        double entropy = 0.0;
        
        if(buyProb > 0) entropy -= buyProb * MathLog(buyProb);
        if(sellProb > 0) entropy -= sellProb * MathLog(sellProb);
        if(holdProb > 0) entropy -= holdProb * MathLog(holdProb);
        
        return entropy / MathLog(3.0); // Normalize by max entropy
    }
    
    // Calculate realized volatility from price returns (replaces prediction-history based volatility)
    double CalculateHistoricalVolatility(int lookback = 20) {
        if(m_priceReturnCount < lookback)
        {
            // Fallback to prediction history if price returns not available
            if(m_predictionCount < lookback) return 1.0;
            double mean = 0.0;
            int startIndex = m_predictionCount - lookback;
            for(int i = 0; i < lookback; i++)
                mean += RingGet(m_predictionHistory, m_predictionHead, m_predictionCount, startIndex + i);
            mean /= lookback;
            double variance = 0.0;
            for(int i = 0; i < lookback; i++)
            {
                double diff = RingGet(m_predictionHistory, m_predictionHead, m_predictionCount, startIndex + i) - mean;
                variance += diff * diff;
            }
            variance /= lookback;
            return MathSqrt(variance);
        }
        
        double mean = 0.0;
        int startIndex = m_priceReturnCount - lookback;
        for(int i = 0; i < lookback; i++)
            mean += RingGet(m_priceReturnHistory, m_priceReturnHead, m_priceReturnCount, startIndex + i);
        mean /= lookback;
        
        double variance = 0.0;
        for(int i = 0; i < lookback; i++)
        {
            double diff = RingGet(m_priceReturnHistory, m_priceReturnHead, m_priceReturnCount, startIndex + i) - mean;
            variance += diff * diff;
        }
        variance /= lookback;
        
        return MathSqrt(variance);
    }

    double CalculateModelUncertainty(int lookback = 20) {
        if(m_predictionCount < lookback) return 1.0;
        
        double mean = 0.0;
        int startIndex = m_predictionCount - lookback;
        for(int i = 0; i < lookback; i++)
            mean += RingGet(m_predictionHistory, m_predictionHead, m_predictionCount, startIndex + i);
        mean /= lookback;
        
        double variance = 0.0;
        for(int i = 0; i < lookback; i++)
        {
            double diff = RingGet(m_predictionHistory, m_predictionHead, m_predictionCount, startIndex + i) - mean;
            variance += diff * diff;
        }
        variance /= lookback;
        
        return MathSqrt(variance);
    }
    
    // Calculate prediction error statistics
    double CalculatePredictionError(int lookback = 50) {
        if(m_errorCount < lookback) return 1.0;
        
        double meanError = 0.0;
        int startIndex = m_errorCount - lookback;
        for(int i = 0; i < lookback; i++) {
            meanError += MathAbs(RingGet(m_errorHistory, m_errorHead, m_errorCount, startIndex + i));
        }
        
        return meanError / lookback;
    }
    
public:
    CUncertaintyQuantifier(int historySize = 500, double confidenceLevel = 0.95) {
        m_historySize = MathMax(8, historySize);
        m_predictionHead = 0;
        m_predictionCount = 0;
        m_errorHead = 0;
        m_errorCount = 0;
        m_confidenceLevel = confidenceLevel;
        m_initialized = false;

        ArrayResize(m_predictionHistory, m_historySize);
        ArrayResize(m_errorHistory, m_historySize);
        ArrayInitialize(m_predictionHistory, 0.0);
        ArrayInitialize(m_errorHistory, 0.0);

        m_priceReturnSize = MathMax(8, historySize);
        m_priceReturnHead = 0;
        m_priceReturnCount = 0;
        ArrayResize(m_priceReturnHistory, m_priceReturnSize);
        ArrayInitialize(m_priceReturnHistory, 0.0);
        
        Print("[UNCERTAINTY] Quantifier initialized with ", m_historySize, " history size");
    }
    
    // Update prediction history
    bool UpdatePredictionHistory(double prediction, double actualOutcome = 0.0, bool hasOutcome = false) {
        RingPush(m_predictionHistory, m_predictionHead, m_predictionCount, prediction);

        if(hasOutcome) {
            double error = prediction - actualOutcome;
            RingPush(m_errorHistory, m_errorHead, m_errorCount, error);
        }

        m_initialized = true;
        return true;
    }

    // Feed realized price return for proper volatility calculation
    // priceReturn = (close[t] - close[t-1]) / close[t-1]  (percentage return)
    void UpdateRealizedVolatility(const double priceReturn) {
        RingPush(m_priceReturnHistory, m_priceReturnHead, m_priceReturnCount, priceReturn);
    }
    
    // Quantify uncertainty using multiple methods
    bool QuantifyUncertainty(double inBuySignal, double inSellSignal, double inHoldSignal,
                           SPredictionWithUncertainty &result) {
        // Main prediction (strongest signal)
        if(inBuySignal > inSellSignal && inBuySignal > inHoldSignal) {
            result.prediction = inBuySignal;
        } else if(inSellSignal > inBuySignal && inSellSignal > inHoldSignal) {
            result.prediction = -inSellSignal; // Negative for sell
        } else {
            result.prediction = 0.0; // Hold
        }
        
        // Calculate entropy-based uncertainty
        result.entropy = CalculateEntropy(inBuySignal, inSellSignal, inHoldSignal);
        
        // Calculate confidence based on signal strength
        double maxSignal = MathMax(MathMax(inBuySignal, inSellSignal), inHoldSignal);
        double signalSpread = maxSignal - MathMin(MathMin(inBuySignal, inSellSignal), inHoldSignal);
        result.confidence = signalSpread; // Higher spread = higher confidence
        
        // Historical volatility from real price returns (not prediction signals)
        double historicalVol = 1.0;
        if(m_initialized) {
            historicalVol = CalculateHistoricalVolatility();
        }
        
        // Model uncertainty from prediction history (signal instability)
        double modelUncertainty = 0.5;
        if(m_initialized && m_predictionCount > 10) {
            modelUncertainty = CalculateModelUncertainty();
        }
        
        // Prediction error-based uncertainty
        double predictionError = 1.0;
        if(m_initialized && m_errorCount > 10) {
            predictionError = CalculatePredictionError();
        }
        
        // Combined uncertainty: entropy + realized vol + model uncertainty + prediction error
        result.uncertainty = (result.entropy + historicalVol + modelUncertainty + predictionError) / 4.0;
        result.uncertainty = MathMax(0.0, MathMin(1.0, result.uncertainty));
        
        // Calculate confidence bounds using t-distribution approximation
        double tValue = 1.96;
        if(m_confidenceLevel >= 0.999) tValue = 3.29;
        else if(m_confidenceLevel >= 0.99) tValue = 2.58;
        else if(m_confidenceLevel >= 0.975) tValue = 2.24;
        else if(m_confidenceLevel >= 0.95) tValue = 1.96;
        else if(m_confidenceLevel >= 0.90) tValue = 1.64;
        else if(m_confidenceLevel >= 0.80) tValue = 1.28;
        else tValue = 1.96;
        
        double margin = tValue * result.uncertainty;
        result.lowerBound = result.prediction - margin;
        result.upperBound = result.prediction + margin;
        
        // Ensure bounds are within valid range [-1, 1]
        result.lowerBound = MathMax(-1.0, result.lowerBound);
        result.upperBound = MathMin(1.0, result.upperBound);
        
        return true;
    }
    
    // Risk-aware position sizing based on uncertainty
    double GetRiskAdjustedSize(double baseSize, double uncertainty, double maxUncertaintyReduction = 0.5) {
        // Reduce position size based on uncertainty
        double reductionFactor = 1.0 - (uncertainty * maxUncertaintyReduction);
        reductionFactor = MathMax(0.1, reductionFactor); // Minimum 10% of base size
        
        return baseSize * reductionFactor;
    }
    
    // Determine if prediction is reliable enough for trading
    bool IsPredictionReliable(const SPredictionWithUncertainty &prediction, 
                             double minConfidence = 0.6, double maxUncertainty = 0.4) {
        return (prediction.confidence >= minConfidence && prediction.uncertainty <= maxUncertainty);
    }
    
    // Get uncertainty-based trading recommendation
    string GetTradingRecommendation(const SPredictionWithUncertainty &prediction) {
        string recommendation = "";
        
        if(!IsPredictionReliable(prediction)) {
            recommendation = "AVOID - High uncertainty (U=" + DoubleToString(prediction.uncertainty, 2) + ")";
        }
        else if(prediction.prediction > 0.1) {
            recommendation = "BUY - Confidence: " + DoubleToString(prediction.confidence, 2);
        }
        else if(prediction.prediction < -0.1) {
            recommendation = "SELL - Confidence: " + DoubleToString(prediction.confidence, 2);
        }
        else {
            recommendation = "HOLD - Neutral signal";
        }
        
        return recommendation;
    }
    
    // Calculate Value at Risk (VaR) based on uncertainty
    double CalculateVaR(double position, const SPredictionWithUncertainty &prediction, 
                       double confidenceLevel = 0.95) {
        if(MathAbs(position) < 1e-9)
            return 0.0;
        
        double worstCase = (position > 0) ? prediction.lowerBound : prediction.upperBound;
        double expectedLoss = MathAbs(position * worstCase);
        
        // Scale by confidence level (higher confidence → more conservative VaR)
        double confidenceScale = 1.0 + (confidenceLevel - 0.95) * 4.0;
        return expectedLoss * confidenceScale;
    }
    
    // Bayesian confidence update
    bool UpdateBayesianConfidence(double priorConfidence, double likelihood, double &posteriorConfidence) {
        // Simple Bayesian update
        double evidence = priorConfidence * likelihood + (1.0 - priorConfidence) * (1.0 - likelihood);
        
        if(evidence > 0) {
            posteriorConfidence = (priorConfidence * likelihood) / evidence;
            return true;
        }
        
        posteriorConfidence = priorConfidence;
        return false;
    }
    
    // Get uncertainty statistics
    void GetUncertaintyStats(double &avgUncertainty, double &maxUncertainty, 
                           double &avgError, int &sampleCount) {
        avgUncertainty = 0.0;
        maxUncertainty = 0.0;
        avgError = 0.0;
        sampleCount = m_predictionCount;
        
        if(sampleCount == 0) return;
        
        // Calculate average uncertainty (using volatility as proxy)
        avgUncertainty = CalculateHistoricalVolatility(sampleCount);
        maxUncertainty = avgUncertainty * 2.0; // Estimate
        
        // Calculate average error
        if(m_errorCount > 0) {
            for(int i = 0; i < m_errorCount; i++) {
                avgError += MathAbs(RingGet(m_errorHistory, m_errorHead, m_errorCount, i));
            }
            avgError /= m_errorCount;
        }
    }
    
    // Generate uncertainty report
    string GenerateUncertaintyReport(const SPredictionWithUncertainty &prediction) {
        string report = "\n=== UNCERTAINTY ANALYSIS ===\n";
        report += StringFormat("Prediction: %.3f [%.3f, %.3f]\n", 
                              prediction.prediction, prediction.lowerBound, prediction.upperBound);
        report += StringFormat("Confidence: %.1f%% | Uncertainty: %.1f%%\n", 
                              prediction.confidence * 100, prediction.uncertainty * 100);
        report += StringFormat("Entropy: %.3f | Reliable: %s\n", 
                              prediction.entropy, IsPredictionReliable(prediction) ? "YES" : "NO");
        
        double avgUnc, maxUnc, avgErr;
        int samples;
        GetUncertaintyStats(avgUnc, maxUnc, avgErr, samples);
        
        report += StringFormat("Historical: Avg Uncertainty=%.3f, Avg Error=%.3f, Samples=%d\n", 
                              avgUnc, avgErr, samples);
        report += "Recommendation: " + GetTradingRecommendation(prediction) + "\n";
        
        return report;
    }
};

// NOTE: g_uncertaintyQuantifier removed — dead code. Each EA instance creates
// its own CUncertaintyQuantifier via NextGenStrategyBrain. In MT5, globals are
// per-chart (separate program memory space), so no cross-symbol collision.

// Stub for backward compatibility (callers in main EA)
void UncertaintyDeinit() { /* no-op: per-instance cleanup handled by owner */ }

#endif // __UNCERTAINTY_QUANTIFIER_MQH__
