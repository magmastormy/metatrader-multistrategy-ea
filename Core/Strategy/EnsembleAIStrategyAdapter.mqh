//+------------------------------------------------------------------+
//| EnsembleAIStrategyAdapter.mqh                                    |
//| IStrategy adapter for runtime ensemble AI voting                 |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_STRATEGY_ENSEMBLE_AI_STRATEGY_ADAPTER_MQH
#define CORE_STRATEGY_ENSEMBLE_AI_STRATEGY_ADAPTER_MQH

#include "../../Interfaces/IStrategy.mqh"
#include "../../AIModules/EnsembleMetaLearner.mqh"
#include "../AI/AIFeatureVectorBuilder.mqh"

class CEnsembleAIStrategyAdapter : public IStrategy
{
private:
    CEnsembleMetaLearner m_ensemble;
    CTransformerBrain* m_modelA;
    CTransformerBrain* m_modelB;
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    bool m_enabled;
    double m_weight;
    datetime m_lastSignalTime;
    bool m_modelsInitialized;
    ulong m_voteCount;
    ulong m_buyVotes;
    ulong m_sellVotes;
    ulong m_noneVotes;
    datetime m_lastVoteLogTime;
    ENUM_TRADE_SIGNAL m_cachedSignal;
    double m_cachedConfidence;
    datetime m_cacheBarTime;
    bool m_hasCachedSignal;
    string m_lastDecisionReasonTag;
    double m_minConfidence;


    bool EnsureModels()
    {
        if(m_modelsInitialized)
            return true;

        // Two diverse transformer members for ensemble voting.
        m_modelA = new CTransformerBrain(TRANSFORMER_D_MODEL_DEFAULT, TRANSFORMER_NUM_HEADS_DEFAULT, TRANSFORMER_NUM_LAYERS_A_DEFAULT, TRANSFORMER_D_FF_DEFAULT, TRANSFORMER_MAX_SEQ_LEN_DEFAULT, TRANSFORMER_LR_A_DEFAULT);
        m_modelB = new CTransformerBrain(TRANSFORMER_D_MODEL_DEFAULT, TRANSFORMER_NUM_HEADS_DEFAULT, TRANSFORMER_NUM_LAYERS_A_DEFAULT, TRANSFORMER_D_FF_B_DEFAULT, TRANSFORMER_SHORT_SEQ_LEN_DEFAULT, TRANSFORMER_LR_B_DEFAULT);
        if(m_modelA == NULL || m_modelB == NULL)
        {
            // Clean up on failure
            if(m_modelA != NULL)
            {
                delete m_modelA;
                m_modelA = NULL;
            }
            if(m_modelB != NULL)
            {
                delete m_modelB;
                m_modelB = NULL;
            }
            return false;
        }

        if(!m_ensemble.AddModel(m_modelA, 1.0))
        {
            // Clean up on ensemble addition failure
            delete m_modelA;
            m_modelA = NULL;
            delete m_modelB;
            m_modelB = NULL;
            return false;
        }
        if(!m_ensemble.AddModel(m_modelB, 1.0))
        {
            // Clean up on ensemble addition failure
            if(m_ensemble.GetActiveModelCount() > 0)
                m_ensemble.RemoveModel(m_ensemble.GetActiveModelCount() - 1);
            delete m_modelB;
            m_modelB = NULL;
            m_modelA = NULL;
            return false;
        }

        m_modelsInitialized = true;
        return true;
    }

    void LogVoteHeartbeat()
    {
        datetime now = TimeCurrent();
        if(m_lastVoteLogTime == 0 || (now - m_lastVoteLogTime) >= 60)
        {
            PrintFormat("[AI-VOTE][Ensemble] %s | votes=%I64u | buy=%I64u | sell=%I64u | none=%I64u | models=%d",
                        m_symbol, m_voteCount, m_buyVotes, m_sellVotes, m_noneVotes, m_ensemble.GetActiveModelCount());
            m_lastVoteLogTime = now;
        }
    }

public:
    CEnsembleAIStrategyAdapter()
    {
        m_modelA = NULL;
        m_modelB = NULL;
        m_symbol = "";
        m_timeframe = PERIOD_CURRENT;
        m_enabled = true;
        m_weight = 1.0;
        m_lastSignalTime = 0;
        m_modelsInitialized = false;
        m_voteCount = 0;
        m_buyVotes = 0;
        m_sellVotes = 0;
        m_noneVotes = 0;
        m_lastVoteLogTime = 0;
        m_cachedSignal = TRADE_SIGNAL_NONE;
        m_cachedConfidence = 0.0;
        m_cacheBarTime = 0;
        m_hasCachedSignal = false;
        m_lastDecisionReasonTag = "ENSEMBLE_UNSET";
        m_minConfidence = 0.35;
    }

    virtual ~CEnsembleAIStrategyAdapter()
    {
        // FIX: Ensemble owns the models (m_modelA, m_modelB), so we don't delete them here
        // The ensemble destructor will handle cleanup to prevent double-delete
        // Just clear the references
        m_modelA = NULL;
        m_modelB = NULL;
    }

    virtual bool Init(const string symbol,
                      const ENUM_TIMEFRAMES timeframe,
                      void* tradeManagerPtr,
                      void* positionSizerPtr) override
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_cachedSignal = TRADE_SIGNAL_NONE;
        m_cachedConfidence = 0.0;
        m_cacheBarTime = 0;
        m_hasCachedSignal = false;
        bool modelsReady = EnsureModels();
        m_lastDecisionReasonTag = modelsReady ? "ENSEMBLE_INITIALIZED" : "ENSEMBLE_INIT_FAILED";
        return modelsReady;
    }

    virtual void Deinit(void) override
    {
        m_hasCachedSignal = false;
        m_lastDecisionReasonTag = "ENSEMBLE_DEINIT";
    }

    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        m_voteCount++;

        if(!m_enabled || !EnsureModels())
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "ENSEMBLE_DISABLED_OR_UNINIT";
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
        datetime currentBarTime = (m_symbol == "") ? 0 : iTime(m_symbol, m_timeframe, 0);
        bool needsNewInference = (!m_hasCachedSignal || currentBarTime <= 0 || currentBarTime != m_cacheBarTime);
        if(!needsNewInference)
        {
            confidence = m_cachedConfidence;
            signal = m_cachedSignal;
        }
        else
        {
            double inputSequence[];
            if(!CAIFeatureVectorBuilder::BuildTransformerInput(m_symbol, m_timeframe, inputSequence, TRANSFORMER_D_MODEL_DEFAULT, TRANSFORMER_SHORT_SEQ_LEN_DEFAULT))
            {
                m_noneVotes++;
                m_lastDecisionReasonTag = "ENSEMBLE_FEATURES_UNAVAILABLE";
                m_cachedSignal = TRADE_SIGNAL_NONE;
                m_cachedConfidence = 0.0;
                m_cacheBarTime = currentBarTime;
                m_hasCachedSignal = (currentBarTime > 0);
                LogVoteHeartbeat();
                return TRADE_SIGNAL_NONE;
            }

            double ensembleBuy = 0.0;
            double ensembleSell = 0.0;
            double ensembleConfidence = 0.0;
            if(!m_ensemble.ProcessMarketData(inputSequence, ensembleBuy, ensembleSell, ensembleConfidence))
            {
                m_noneVotes++;
                m_lastDecisionReasonTag = "ENSEMBLE_INFERENCE_FAILED";
                m_cachedSignal = TRADE_SIGNAL_NONE;
                m_cachedConfidence = 0.0;
                m_cacheBarTime = currentBarTime;
                m_hasCachedSignal = (currentBarTime > 0);
                LogVoteHeartbeat();
                return TRADE_SIGNAL_NONE;
            }

            double directionalConfidence = MathMax(ensembleBuy, ensembleSell);
            confidence = MathMax(0.0, MathMin(1.0, MathMax(ensembleConfidence, directionalConfidence)));

            if(ensembleBuy > ensembleSell && directionalConfidence >= m_minConfidence)
                signal = TRADE_SIGNAL_BUY;
            else if(ensembleSell > ensembleBuy && directionalConfidence >= m_minConfidence)
                signal = TRADE_SIGNAL_SELL;

            m_cachedSignal = signal;
            m_cachedConfidence = confidence;
            m_cacheBarTime = currentBarTime;
            m_hasCachedSignal = true;
        }

        if(signal == TRADE_SIGNAL_BUY)
        {
            m_buyVotes++;
            m_lastSignalTime = TimeCurrent();
            m_lastDecisionReasonTag = "ENSEMBLE_SIGNAL_BUY";
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            m_sellVotes++;
            m_lastSignalTime = TimeCurrent();
            m_lastDecisionReasonTag = "ENSEMBLE_SIGNAL_SELL";
        }
        else
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "ENSEMBLE_NO_SIGNAL";
        }

        LogVoteHeartbeat();
        return signal;
    }

    virtual void OnNewBar(void) override {}
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override {}

    virtual string GetName(void) const override { return "Ensemble AI"; }
    virtual ENUM_STRATEGY_TYPE GetType(void) const override { return STRATEGY_AI_ENHANCED; }
    virtual bool IsEnabled(void) const override { return m_enabled; }
    virtual void SetEnabled(const bool enabled) override { m_enabled = enabled; }
    virtual double GetWeight(void) const override { return m_weight; }
    virtual void SetWeight(const double weight) override { m_weight = weight; }
    virtual bool ValidateParameters(void) override { return true; }
    virtual datetime GetLastSignalTime(void) const override { return m_lastSignalTime; }
    virtual string GetLastDecisionReasonTag(void) const override { return m_lastDecisionReasonTag; }
    virtual void SetConfidenceThreshold(double threshold) override { m_minConfidence = threshold; }

    virtual void GetStatistics(int &signals, int &successful, double &accuracy) override
    {
        signals = (int)m_voteCount;
        successful = 0;
        accuracy = 0.0;
    }
};

#endif // CORE_STRATEGY_ENSEMBLE_AI_STRATEGY_ADAPTER_MQH
