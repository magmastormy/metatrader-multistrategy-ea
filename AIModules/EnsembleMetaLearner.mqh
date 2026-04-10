//+------------------------------------------------------------------+
//|                                                  EnsembleMetaLearner.mqh |
//|                        Copyright 2023, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include <Object.mqh>
#include "TransformerBrain.mqh"

//+------------------------------------------------------------------+
//| Ensemble Meta Learner Class                                     |
//+------------------------------------------------------------------+
class CEnsembleMetaLearner
{
private:
    CArrayObj m_models;
    CArrayDouble m_modelWeights;
    CArrayDouble m_modelPerformanceHistory;
    CArrayDouble m_modelRecentAccuracy;
    
    // Regime detection state
    double m_atrShort;
    double m_atrLong;
    double m_trendStrength;
    double m_momentum;
    datetime m_lastRegimeUpdate;
    
public:
    CEnsembleMetaLearner();
    ~CEnsembleMetaLearner();
    
    // Core methods
    bool AddModel(CTransformerBrain* model, double initialWeight = 1.0);
    bool RemoveModel(int index);
    bool ProcessMarketData(const double &marketData[], double &ensembleBuySignal, double &ensembleSellSignal, double &confidence);
    bool TrainEnsemble(const double &marketData[], int seqLen, int targetClass);
    
    // Model management
    void UpdateModelWeights(ENUM_MARKET_REGIME regime);
    double CalculateModelWeight(int modelIndex, ENUM_MARKET_REGIME regime);
    double EvaluateModelPerformance(CTransformerBrain* model, const double &testData[]);
    int GetActiveModelCount() const;
    void DeactivateUnderperformingModels(double threshold = 0.3);
    
    // Training helpers
    bool TrainModel(CTransformerBrain* model, const double &data[], int seqLen, int targetClass, double &loss);
    
    // Advanced regime detection
    ENUM_MARKET_REGIME DetectMarketRegime(const double &marketData[]);
    void UpdateRegimeState(const double &marketData[]);
    
    double GetConfidence() const { return m_lastConfidence; } 

private:
    double m_lastConfidence;
    double CalculateATR(const double &data[], int period);
    double CalculateTrendStrength(const double &data[]);
    double CalculateMomentum(const double &data[], int period);
};

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CEnsembleMetaLearner::CEnsembleMetaLearner() : 
    m_lastConfidence(0.0),
    m_atrShort(0.0),
    m_atrLong(0.0),
    m_trendStrength(0.0),
    m_momentum(0.0),
    m_lastRegimeUpdate(0)
{
    m_models.FreeMode(true);
    m_modelPerformanceHistory.Resize(0);
    m_modelRecentAccuracy.Resize(0);
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CEnsembleMetaLearner::~CEnsembleMetaLearner()
{
    m_models.Clear();
}

//+------------------------------------------------------------------+
//| Add model to ensemble                                          |
//+------------------------------------------------------------------+
bool CEnsembleMetaLearner::AddModel(CTransformerBrain* model, double initialWeight)
{
    if(model == NULL) return false;
    
    if(m_models.Add(dynamic_cast<CObject*>(model)))
    {
        m_modelWeights.Resize(m_models.Total());
        m_modelWeights.Update(m_models.Total() - 1, initialWeight);
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Remove model from ensemble                                     |
//+------------------------------------------------------------------+
bool CEnsembleMetaLearner::RemoveModel(int index)
{
    if(index < 0 || index >= m_models.Total()) return false;

    if(m_models.Delete(index))
    {
        m_modelWeights.Delete(index);
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Process market data through ensemble                           |
//+------------------------------------------------------------------+
bool CEnsembleMetaLearner::ProcessMarketData(const double &marketData[], double &ensembleBuySignal, double &ensembleSellSignal, double &confidence)
{
    ensembleBuySignal = 0.0;
    ensembleSellSignal = 0.0;
    confidence = 0.0;
    
    if(m_models.Total() == 0) return false;
    
    double weightedNoneSignal = 0.0;
    double weightedBuySignal = 0.0;
    double weightedSellSignal = 0.0;
    double totalWeight = 0.0;
    
    // Get current market regime using advanced detection
    ENUM_MARKET_REGIME activeRegime = DetectMarketRegime(marketData);
    
    // Update model weights based on current regime
    UpdateModelWeights(activeRegime);
    
    // Calculate ensemble signals
    for(int i = 0; i < m_models.Total(); i++)
    {
        CTransformerBrain* model = dynamic_cast<CTransformerBrain*>(m_models.At(i));
        if(model == NULL) continue;
        
        double modelWeight = m_modelWeights.At(i);
        if(modelWeight < 0.01) continue;
        
        int dModel = model.GetModelDimension();
        int maxSeqLen = model.GetMaxSequenceLength();
        int totalFeatures = ArraySize(marketData);
        int availableSeqLen = (dModel > 0) ? (totalFeatures / dModel) : 0;
        int actualSeqLen = MathMin(availableSeqLen, maxSeqLen);
        if(dModel <= 0 || actualSeqLen <= 0)
            continue;

        double modelInput[];
        int startOffset = MathMax(0, totalFeatures - (actualSeqLen * dModel));
        ArrayResize(modelInput, actualSeqLen * dModel);
        ArrayCopy(modelInput, marketData, 0, startOffset, actualSeqLen * dModel);

        double predictions[];
        if(!model.GetPredictions(modelInput, actualSeqLen, predictions) || ArraySize(predictions) != 3)
            continue;

        weightedNoneSignal = weightedNoneSignal + (predictions[0] * modelWeight);
        weightedBuySignal = weightedBuySignal + (predictions[1] * modelWeight);
        weightedSellSignal = weightedSellSignal + (predictions[2] * modelWeight);
        totalWeight = totalWeight + modelWeight;
    }
    
    if(totalWeight > 0)
    {
        double ensembleNoneSignal = weightedNoneSignal / totalWeight;
        ensembleBuySignal = weightedBuySignal / totalWeight;
        ensembleSellSignal = weightedSellSignal / totalWeight;
        double directionalConfidence = MathMax(ensembleBuySignal, ensembleSellSignal);
        confidence = MathMax(0.0, MathMin(1.0, MathMax(directionalConfidence, 1.0 - ensembleNoneSignal)));
        m_lastConfidence = confidence;
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Update model weights based on market regime                      |
//+------------------------------------------------------------------+
void CEnsembleMetaLearner::UpdateModelWeights(ENUM_MARKET_REGIME regime)
{
    if(m_models.Total() == 0) return;
    
    // Calculate raw weights
    for(int i = 0; i < m_models.Total(); i++)
    {
        double weight = CalculateModelWeight(i, regime);
        m_modelWeights.Update(i, weight);
    }
    
    // Normalize weights
    double totalWeight = 0.0;
    for(int i = 0; i < m_modelWeights.Total(); i++)
    {
        totalWeight += m_modelWeights.At(i);
    }
    
    if(totalWeight > 0)
    {
        for(int i = 0; i < m_modelWeights.Total(); i++)
        {
            double normalizedWeight = m_modelWeights.At(i) / totalWeight;
            m_modelWeights.Update(i, normalizedWeight);
        }
    }
}

//+------------------------------------------------------------------+
//| Calculate model weight based on performance and regime         |
//+------------------------------------------------------------------+
double CEnsembleMetaLearner::CalculateModelWeight(int modelIndex, ENUM_MARKET_REGIME regime)
{
    if(modelIndex < 0 || modelIndex >= m_models.Total()) return 0.0;
    
    CTransformerBrain* model = dynamic_cast<CTransformerBrain*>(m_models.At(modelIndex));
    if(model == NULL) return 0.0;
    
    // Base weight from performance history
    double performanceScore = 0.5;
    if(modelIndex < m_modelPerformanceHistory.Total())
    {
        performanceScore = m_modelPerformanceHistory.At(modelIndex);
    }
    
    // Regime-specific adjustment with volatility adaptation
    double regimeMultiplier = 1.0;
    double volatilityAdjustment = 1.0;
    
    switch(regime)
    {
        case MARKET_REGIME_TRENDING:
            regimeMultiplier = 1.3; // Favor trending models
            volatilityAdjustment = (m_atrShort > m_atrLong) ? 0.9 : 1.1;
            break;
        case MARKET_REGIME_VOLATILE:
            regimeMultiplier = 0.7; // Reduce weight in volatile conditions
            volatilityAdjustment = (m_trendStrength > 0.5) ? 1.2 : 0.8;
            break;
        case MARKET_REGIME_RANGING:
            regimeMultiplier = 1.0; // Neutral for ranging
            volatilityAdjustment = 1.0;
            break;
        default:
            regimeMultiplier = 1.0;
            volatilityAdjustment = 1.0;
            break;
    }
    
    // Momentum-based dynamic adjustment
    double momentumAdjustment = 1.0;
    if(MathAbs(m_momentum) > 0.15)
    {
        momentumAdjustment = 1.0 + (MathAbs(m_momentum) * 0.5);
    }
    
    // Combine all factors
    double finalWeight = performanceScore * regimeMultiplier * volatilityAdjustment * momentumAdjustment;
    
    // Ensure weight stays within reasonable bounds
    return MathMax(0.1, MathMin(2.0, finalWeight));
}

//+------------------------------------------------------------------+
//| Train ensemble on market data                                   |
//+------------------------------------------------------------------+
bool CEnsembleMetaLearner::TrainEnsemble(const double &marketData[], int seqLen, int targetClass)
{
    if(m_models.Total() == 0) return false;
    
    bool success = false;
    for(int i = 0; i < m_models.Total(); i++)
    {
        CTransformerBrain* model = dynamic_cast<CTransformerBrain*>(m_models.At(i));
        if(model == NULL) continue;
        
        double loss = 0.0;
        if(TrainModel(model, marketData, seqLen, targetClass, loss))
        {
            success = true;
        }
    }
    
    // Update market regime and adjust weights using advanced detection
    ENUM_MARKET_REGIME detectedRegime = DetectMarketRegime(marketData);
    UpdateModelWeights(detectedRegime);
    
    return success;
}

//+------------------------------------------------------------------+
//| Evaluate model performance                                       |
//+------------------------------------------------------------------+
double CEnsembleMetaLearner::EvaluateModelPerformance(CTransformerBrain* model, const double &testData[])
{
    if(model == NULL || ArraySize(testData) == 0) return 0.0;
    
    double predictions[];
    if(model.GetPredictions(testData, predictions) && ArraySize(predictions) == 3)
        return MathMax(predictions[1], predictions[2]);
    
    return 0.0;
}

//+------------------------------------------------------------------+
//| Get active model count                                          |
//+------------------------------------------------------------------+
int CEnsembleMetaLearner::GetActiveModelCount() const
{
    int count = 0;
    for(int i = 0; i < m_models.Total(); i++)
    {
        CTransformerBrain* model = dynamic_cast<CTransformerBrain*>(m_models.At(i));
        if(model != NULL)
        {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Deactivate underperforming models with advanced performance metrics|
//+------------------------------------------------------------------+
void CEnsembleMetaLearner::DeactivateUnderperformingModels(double threshold)
{
    if(m_models.Total() == 0) return;
    
    // Evaluate each model's recent performance
    for(int i = 0; i < m_models.Total(); i++)
    {
        CTransformerBrain* model = dynamic_cast<CTransformerBrain*>(m_models.At(i));
        if(model == NULL) continue;
        
        // Calculate performance metrics
        double currentWeight = m_modelWeights.At(i);
        double emptyTestData[];
        ArrayResize(emptyTestData, 0);
        double performanceScore = EvaluateModelPerformance(model, emptyTestData);
        
        // Update performance history
        if(i >= m_modelPerformanceHistory.Total())
        {
            m_modelPerformanceHistory.Resize(i + 1);
        }
        m_modelPerformanceHistory.Update(i, performanceScore);
        
        // Calculate moving average of recent performance
        double recentPerformance = 0.0;
        int historySize = MathMin(10, m_modelPerformanceHistory.Total());
        for(int j = MathMax(0, i - historySize + 1); j <= i && j < m_modelPerformanceHistory.Total(); j++)
        {
            recentPerformance += m_modelPerformanceHistory.At(j);
        }
        if(historySize > 0)
            recentPerformance /= historySize;
        
        // Advanced deactivation logic with multiple factors
        bool shouldDeactivate = false;
        
        // Factor 1: Performance below threshold
        if(recentPerformance < threshold)
        {
            shouldDeactivate = true;
        }
        
        // Factor 2: Performance declining over time
        if(i > 0 && i < m_modelPerformanceHistory.Total())
        {
            double previousPerformance = m_modelPerformanceHistory.At(i - 1);
            if(performanceScore < previousPerformance * 0.8) // 20% decline
            {
                shouldDeactivate = true;
            }
        }
        
        // Factor 3: Volatility-based adjustment (keep more models in volatile conditions)
        if(m_atrShort > m_atrLong * 1.3 && recentPerformance > threshold * 0.8)
        {
            shouldDeactivate = false; // Keep model in volatile conditions even if slightly underperforming
        }
        
        // Apply deactivation with gradual weight reduction instead of hard cutoff
        if(shouldDeactivate)
        {
            double newWeight = currentWeight * 0.5; // Reduce by 50%
            if(newWeight < 0.05)
                newWeight = 0.0; // Fully deactivate if very low
            m_modelWeights.Update(i, newWeight);
        }
        else if(currentWeight < 1.0 && recentPerformance > threshold * 1.1)
        {
            // Gradually reactivate improving models
            double newWeight = MathMin(1.0, currentWeight * 1.2);
            m_modelWeights.Update(i, newWeight);
        }
    }
    
    // Re-normalize weights after adjustments
    double totalWeight = 0.0;
    for(int i = 0; i < m_modelWeights.Total(); i++)
    {
        totalWeight += m_modelWeights.At(i);
    }
    
    if(totalWeight > 0)
    {
        for(int i = 0; i < m_modelWeights.Total(); i++)
        {
            double normalizedWeight = m_modelWeights.At(i) / totalWeight;
            m_modelWeights.Update(i, normalizedWeight);
        }
    }
}

//+------------------------------------------------------------------+
//| Train individual model                                          |
//+------------------------------------------------------------------+
bool CEnsembleMetaLearner::TrainModel(CTransformerBrain* model, const double &data[], int seqLen, int targetClass, double &loss)
{
    if(model == NULL || ArraySize(data) == 0 || seqLen <= 0) return false;

    return model.TrainStep(data, targetClass, loss);
}

//+------------------------------------------------------------------+
//| Detect market regime using volatility, trend, and momentum         |
//+------------------------------------------------------------------+
ENUM_MARKET_REGIME CEnsembleMetaLearner::DetectMarketRegime(const double &marketData[])
{
    if(ArraySize(marketData) < 50)
        return MARKET_REGIME_RANGING;
    
    UpdateRegimeState(marketData);
    
    // Volatility ratio: short-term ATR / long-term ATR
    double volatilityRatio = (m_atrLong > 0) ? m_atrShort / m_atrLong : 1.0;
    
    // Determine regime based on multiple factors
    bool isVolatile = (volatilityRatio > 1.5);
    bool isTrending = (MathAbs(m_trendStrength) > 0.3);
    bool isMomentumStrong = (MathAbs(m_momentum) > 0.2);
    
    if(isVolatile)
    {
        return MARKET_REGIME_VOLATILE;
    }
    else if(isTrending && isMomentumStrong)
    {
        return (m_trendStrength > 0) ? MARKET_REGIME_TRENDING : MARKET_REGIME_RANGING;
    }
    
    return MARKET_REGIME_RANGING;
}

//+------------------------------------------------------------------+
//| Update regime detection state variables                            |
//+------------------------------------------------------------------+
void CEnsembleMetaLearner::UpdateRegimeState(const double &marketData[])
{
    if(ArraySize(marketData) < 50)
        return;
    
    m_atrShort = CalculateATR(marketData, 14);
    m_atrLong = CalculateATR(marketData, 50);
    m_trendStrength = CalculateTrendStrength(marketData);
    m_momentum = CalculateMomentum(marketData, 14);
    m_lastRegimeUpdate = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Calculate Average True Range for volatility measurement            |
//+------------------------------------------------------------------+
double CEnsembleMetaLearner::CalculateATR(const double &data[], int period)
{
    if(ArraySize(data) < period + 1)
        return 0.0;
    
    double atr = 0.0;
    double tr = 0.0;
    double prevClose = data[0];
    
    for(int i = 1; i <= period; i++)
    {
        double high = data[i];
        double low = data[i];
        double close = data[i];
        
        double hl = high - low;
        double hc = MathAbs(high - prevClose);
        double lc = MathAbs(low - prevClose);
        
        tr = MathMax(hl, MathMax(hc, lc));
        atr += tr;
        prevClose = close;
    }
    
    return atr / period;
}

//+------------------------------------------------------------------+
//| Calculate trend strength using linear regression slope             |
//+------------------------------------------------------------------+
double CEnsembleMetaLearner::CalculateTrendStrength(const double &data[])
{
    if(ArraySize(data) < 20)
        return 0.0;
    
    int period = MathMin(20, ArraySize(data) - 1);
    double sumX = 0.0, sumY = 0.0, sumXY = 0.0, sumX2 = 0.0;
    
    for(int i = 0; i < period; i++)
    {
        sumX += i;
        sumY += data[i];
        sumXY += i * data[i];
        sumX2 += i * i;
    }
    
    double denominator = (period * sumX2) - (sumX * sumX);
    if(denominator == 0)
        return 0.0;
    
    double slope = ((period * sumXY) - (sumX * sumY)) / denominator;
    
    // Normalize slope by average price
    double avgPrice = sumY / period;
    double normalizedSlope = (avgPrice > 0) ? slope / avgPrice : 0.0;
    
    return normalizedSlope;
}

//+------------------------------------------------------------------+
//| Calculate momentum using rate of change                           |
//+------------------------------------------------------------------+
double CEnsembleMetaLearner::CalculateMomentum(const double &data[], int period)
{
    if(ArraySize(data) < period + 1)
        return 0.0;
    
    double currentPrice = data[0];
    double pastPrice = data[period];
    
    if(pastPrice == 0)
        return 0.0;
    
    return (currentPrice - pastPrice) / pastPrice;
}