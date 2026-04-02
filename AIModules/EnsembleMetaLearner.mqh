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
    
    double GetConfidence() const { return m_lastConfidence; } 

private:
    double m_lastConfidence;
};

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CEnsembleMetaLearner::CEnsembleMetaLearner() : m_lastConfidence(0.0)
{
    m_models.FreeMode(true);
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
    
    // Get current market regime (simplified - using default)
    ENUM_MARKET_REGIME activeRegime = MARKET_REGIME_RANGING;
    
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
    
    // Base weight from performance score
    double baseWeight = 0.5; // Default neutral weight
    
    // Regime-specific adjustment (simplified)
    double regimeMultiplier = 1.0;
    switch(regime)
    {
        case MARKET_REGIME_TRENDING:
            regimeMultiplier = 1.2;
            break;
        case MARKET_REGIME_VOLATILE:
            regimeMultiplier = 0.8;
            break;
        case MARKET_REGIME_RANGING:
            regimeMultiplier = 1.0;
            break;
        default:
            regimeMultiplier = 1.0;
            break;
    }
    
    return baseWeight * regimeMultiplier;
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
    
    // Update market regime and adjust weights (simplified - using default)
    ENUM_MARKET_REGIME localCurrentRegime = MARKET_REGIME_RANGING;
    UpdateModelWeights(localCurrentRegime);
    
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
//| Deactivate underperforming models                               |
//+------------------------------------------------------------------+
void CEnsembleMetaLearner::DeactivateUnderperformingModels(double threshold)
{
    // Simplified implementation - in a real system, this would evaluate performance
    // and deactivate models below the threshold
    for(int i = 0; i < m_models.Total(); i++)
    {
        CTransformerBrain* model = dynamic_cast<CTransformerBrain*>(m_models.At(i));
        if(model != NULL)
        {
            // Placeholder for actual deactivation logic
            double weight = m_modelWeights.At(i);
            if(weight < threshold)
            {
                m_modelWeights.Update(i, 0.0); // Set weight to 0 to effectively deactivate
            }
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
