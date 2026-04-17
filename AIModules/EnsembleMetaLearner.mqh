//+------------------------------------------------------------------+
//|                                                  EnsembleMetaLearner.mqh |
//|                        Copyright 2023, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#include <Object.mqh>
#include "TransformerBrain.mqh"
#include "UniversalTransformerService.mqh"

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
    bool m_usesSharedTransformer;  // Use shared transformer service
    string m_symbol;               // Symbol for shared service
    
    // Regime detection state
    double m_atrShort;
    double m_atrLong;
    double m_trendStrength;
    double m_momentum;
    datetime m_lastRegimeUpdate;
    ENUM_MARKET_REGIME m_lastDetectedRegime;
    
    // Thompson Sampling state
    CArrayDouble m_alphas; // Success counts
    CArrayDouble m_betas;  // Failure counts
    
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
    void UpdateModelPerformance(int modelIndex, double result);
    double CalculateModelWeight(int modelIndex, ENUM_MARKET_REGIME regime);
    double EvaluateModelPerformance(CTransformerBrain* model, const double &testData[]);
    int GetActiveModelCount() const;
    void DeactivateUnderperformingModels(double threshold = 0.3);
    
    // Training helpers
    bool TrainModel(CTransformerBrain* model, const double &data[], int seqLen, int targetClass, double &loss);
    
    // Advanced regime detection
    ENUM_MARKET_REGIME DetectMarketRegime(const double &marketData[]);
    void UpdateRegimeState(const double &marketData[]);
    
        
    // Configuration
    void SetSymbol(const string& symbol) { m_symbol = symbol; }
    void SetUseSharedTransformer(bool useShared) { m_usesSharedTransformer = useShared; }
    
    // Universal Transformer integration
    bool Initialize(const string& symbol, bool useSharedTransformer = true);
    bool UpdateEnsemblePerformance(double tradeResult);
    void GetEnsembleStatus(string& status);
    
    // Core methods with shared transformer support
    bool ProcessWithSharedTransformer(const double &marketData[], double &ensembleBuySignal, double &ensembleSellSignal, double &confidence);
    bool CreateInterpretationModels();
    
    // Model creation methods
    CTransformerBrain* CreateShortTermModel();
    CTransformerBrain* CreateLongTermModel();
    CTransformerBrain* CreateMediumTermModel();
    CTransformerBrain* CreateVolatilityFocusedModel();
    
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
    m_lastRegimeUpdate(0),
    m_lastDetectedRegime(MARKET_REGIME_RANGING),
    m_usesSharedTransformer(true),
    m_symbol("")
{
    m_models.FreeMode(true);
    m_modelPerformanceHistory.Resize(0);
    m_modelRecentAccuracy.Resize(0);
    m_alphas.Resize(0);
    m_betas.Resize(0);
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
        
        m_alphas.Resize(m_models.Total());
        m_alphas.Update(m_models.Total() - 1, 1.0); // Prior: 1 success
        
        m_betas.Resize(m_models.Total());
        m_betas.Update(m_models.Total() - 1, 1.0);  // Prior: 1 failure
        
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
        m_alphas.Delete(index);
        m_betas.Delete(index);
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

        // AUDIT FIX: Validate prediction values for NaN/invalid before aggregation
        if(!MathIsValidNumber(predictions[0]) || !MathIsValidNumber(predictions[1]) || !MathIsValidNumber(predictions[2]))
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
        
        // Guard against NaN
        if(confidence != confidence) // NaN check
            confidence = 0.0;
            
        m_lastConfidence = confidence;
        return true;
    }
    
    // Set confidence to 0.0 when no valid signals
    confidence = 0.0;
    m_lastConfidence = 0.0;
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
//| Update model performance based on trade result                  |
//+------------------------------------------------------------------+
void CEnsembleMetaLearner::UpdateModelPerformance(int modelIndex, double result)
{
    if(modelIndex < 0 || modelIndex >= m_models.Total()) return;
    
    // Ensure m_modelRecentAccuracy is sized correctly
    if(m_modelRecentAccuracy.Total() <= modelIndex)
    {
        m_modelRecentAccuracy.Resize(m_models.Total());
        for(int i = m_modelRecentAccuracy.Total(); i < m_models.Total(); i++)
            m_modelRecentAccuracy.Update(i, 0.5); // Default to neutral accuracy
    }
    
    // Update accuracy with smoothing (exponential moving average)
    double alpha = 0.1; // 10% weight to new result
    double currentAccuracy = m_modelRecentAccuracy.At(modelIndex);
    double win = (result > 0) ? 1.0 : 0.0;
    
    // Thompson update
    if(win > 0.5)
        m_alphas.Update(modelIndex, m_alphas.At(modelIndex) + 1.0);
    else
        m_betas.Update(modelIndex, m_betas.At(modelIndex) + 1.0);
        
    double updatedAccuracy = (alpha * win) + ((1.0 - alpha) * currentAccuracy);
    m_modelRecentAccuracy.Update(modelIndex, updatedAccuracy);
    
    // Periodically re-normalize weights
    UpdateModelWeights(m_lastDetectedRegime);
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
    
    // Incorporate recent accuracy (Thompson-lite weighting)
    if(modelIndex < m_modelRecentAccuracy.Total())
    {
        double recentAcc = m_modelRecentAccuracy.At(modelIndex);
        
        // Advanced Thompson Sampling Sample: Mean = alpha / (alpha + beta)
        double a = m_alphas.At(modelIndex);
        double b = m_betas.At(modelIndex);
        double thompsonMean = a / (a + b);
        
        // Combine history, recent EMA, and Thompson mean
        performanceScore = (performanceScore * 0.4) + (recentAcc * 0.3) + (thompsonMean * 0.3);
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
        m_lastDetectedRegime = MARKET_REGIME_VOLATILE;
    }
    else if(isTrending && isMomentumStrong)
    {
        m_lastDetectedRegime = (m_trendStrength > 0) ? MARKET_REGIME_TRENDING : MARKET_REGIME_RANGING;
    }
    else
    {
        m_lastDetectedRegime = MARKET_REGIME_RANGING;
    }
    
    return m_lastDetectedRegime;
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

//+------------------------------------------------------------------+
//| Create differentiated models for true ensemble diversity       |
//+------------------------------------------------------------------+
CTransformerBrain* CEnsembleMetaLearner::CreateShortTermModel()
{
    // Short-term model: smaller sequence length, faster learning
    return new CTransformerBrain(32, 2, 1, 64, 20, 0.002); // dModel=32, heads=2, layers=1, seqLen=20, lr=0.002
}

CTransformerBrain* CEnsembleMetaLearner::CreateLongTermModel()
{
    // Long-term model: longer sequence, slower learning
    return new CTransformerBrain(32, 2, 1, 64, 50, 0.0005); // dModel=32, heads=2, layers=1, seqLen=50, lr=0.0005
}

CTransformerBrain* CEnsembleMetaLearner::CreateMediumTermModel()
{
    // Medium-term model: balanced parameters
    return new CTransformerBrain(32, 2, 1, 64, 30, 0.001); // dModel=32, heads=2, layers=1, seqLen=30, lr=0.001
}

CTransformerBrain* CEnsembleMetaLearner::CreateVolatilityFocusedModel()
{
    // Volatility-focused model: more heads for pattern detection
    return new CTransformerBrain(32, 4, 1, 64, 35, 0.0015); // dModel=32, heads=4, layers=1, seqLen=35, lr=0.0015
}

//+------------------------------------------------------------------+
//| Create differentiated interpretation models using shared transformer
//+------------------------------------------------------------------+
bool CEnsembleMetaLearner::CreateInterpretationModels()
{
    if(m_symbol == "") return false;
    
    // Ensure symbol is registered with universal transformer service
    if(!g_universalTransformerService.IsSymbolRegistered(m_symbol))
    {
        if(!g_universalTransformerService.RegisterSymbol(m_symbol))
        {
            PrintFormat("[ENSEMBLE] ERROR: Failed to register symbol %s with universal transformer", m_symbol);
            return false;
        }
    }
    
    // Clear existing models
    m_models.Clear();
    m_modelWeights.Resize(0);
    m_modelPerformanceHistory.Resize(0);
    m_modelRecentAccuracy.Resize(0);
    m_alphas.Resize(0);
    m_betas.Resize(0);
    
    // Create different model types for ensemble diversity
    CTransformerBrain* shortTermModel = CreateShortTermModel();
    CTransformerBrain* longTermModel = CreateLongTermModel();
    CTransformerBrain* mediumTermModel = CreateMediumTermModel();
    CTransformerBrain* volatilityModel = CreateVolatilityFocusedModel();
    
    // Add models to ensemble with initial weights
    bool success = true;
    if(shortTermModel) success &= AddModel(shortTermModel, 0.25);
    if(longTermModel) success &= AddModel(longTermModel, 0.25);
    if(mediumTermModel) success &= AddModel(mediumTermModel, 0.25);
    if(volatilityModel) success &= AddModel(volatilityModel, 0.25);
    
    PrintFormat("[ENSEMBLE] Created %d interpretation models for symbol %s", m_models.Total(), m_symbol);
    return success;
}

//+------------------------------------------------------------------+
//| Process market data using shared transformer service            |
//+------------------------------------------------------------------+
bool CEnsembleMetaLearner::ProcessWithSharedTransformer(const double &marketData[], double &ensembleBuySignal, double &ensembleSellSignal, double &confidence)
{
    ensembleBuySignal = 0.0;
    ensembleSellSignal = 0.0;
    confidence = 0.0;
    
    if(m_symbol == "" || !m_usesSharedTransformer) return false;
    
    // Ensure symbol is registered
    if(!g_universalTransformerService.IsSymbolRegistered(m_symbol))
    {
        if(!g_universalTransformerService.RegisterSymbol(m_symbol))
        {
            PrintFormat("[ENSEMBLE] ERROR: Failed to register symbol %s", m_symbol);
            return false;
        }
    }
    
    // Get symbol features from universal transformer
    double symbolFeatures[];
    int seqLen = MathMax(1, ArraySize(marketData) / 64); // Estimate sequence length
    
    if(!g_universalTransformerService.GetSymbolFeatures(m_symbol, marketData, seqLen, symbolFeatures))
    {
        PrintFormat("[ENSEMBLE] ERROR: Failed to get features for symbol %s", m_symbol);
        return false;
    }
    
    // Simple ensemble approach using universal transformer features
    if(ArraySize(symbolFeatures) < 3) return false;
    
    // Analyze features for trading signals
    double buyScore = 0.0, sellScore = 0.0, noneScore = 0.0;
    
    // Weight different feature groups
    for(int i = 0; i < MathMin(32, ArraySize(symbolFeatures)); i++)
    {
        if(i < 10) buyScore += symbolFeatures[i];      // Short-term features
        else if(i < 20) sellScore += symbolFeatures[i]; // Medium-term features
        else noneScore += symbolFeatures[i];            // Long-term features
    }
    
    // Normalize scores
    double totalScore = MathAbs(buyScore) + MathAbs(sellScore) + MathAbs(noneScore) + 1e-9;
    ensembleBuySignal = MathAbs(buyScore) / totalScore;
    ensembleSellSignal = MathAbs(sellScore) / totalScore;
    double noneSignal = MathAbs(noneScore) / totalScore;
    
    // Calculate confidence
    confidence = MathMax(ensembleBuySignal, ensembleSellSignal);
    confidence = MathMax(0.0, MathMin(1.0, confidence));
    
    // Guard against NaN
    if(confidence != confidence) // NaN check
        confidence = 0.0;
        
    m_lastConfidence = confidence;
    
    return true;
}

//+------------------------------------------------------------------+
//| Initialize ensemble with shared transformer                     |
//+------------------------------------------------------------------+
bool CEnsembleMetaLearner::Initialize(const string& symbol, bool useSharedTransformer)
{
    m_symbol = symbol;
    m_usesSharedTransformer = useSharedTransformer;
    
    if(m_usesSharedTransformer)
    {
        PrintFormat("[ENSEMBLE] Initializing with Universal Transformer service for symbol: %s", m_symbol);
        return CreateInterpretationModels();
    }
    else
    {
        PrintFormat("[ENSEMBLE] Initializing with local models for symbol: %s", m_symbol);
        return true;
    }
}

//+------------------------------------------------------------------+
//| Get ensemble status and performance metrics                     |
//+------------------------------------------------------------------+
void CEnsembleMetaLearner::GetEnsembleStatus(string& status)
{
    status = "[ENSEMBLE] ";
    status += "Models: " + IntegerToString(GetActiveModelCount()) + " | ";
    status += "Shared Transformer: " + string(m_usesSharedTransformer ? "YES" : "NO") + " | ";
    status += "Symbol: " + m_symbol + " | ";
    status += "Confidence: " + DoubleToString(m_lastConfidence, 3);
}

//+------------------------------------------------------------------+
//| Update ensemble performance with trade results                  |
//+------------------------------------------------------------------+
bool CEnsembleMetaLearner::UpdateEnsemblePerformance(double tradeResult)
{
    // Update performance for all models
    for(int i = 0; i < m_models.Total(); i++)
    {
        UpdateModelPerformance(i, tradeResult);
    }
    
    // Update universal transformer service if using shared transformer
    if(m_usesSharedTransformer && m_symbol != "")
    {
        double performance = (tradeResult > 0) ? 1.0 : 0.0;
        g_universalTransformerService.UpdateSymbolPerformance(m_symbol, performance);
    }
    
    return true;
}
