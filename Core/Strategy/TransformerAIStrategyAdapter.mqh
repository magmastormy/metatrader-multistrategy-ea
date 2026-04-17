//+------------------------------------------------------------------+
//| TransformerAIStrategyAdapter.mqh                                 |
//| IStrategy adapter for runtime transformer voting                 |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_STRATEGY_TRANSFORMER_AI_STRATEGY_ADAPTER_MQH
#define CORE_STRATEGY_TRANSFORMER_AI_STRATEGY_ADAPTER_MQH

#include "../../Interfaces/IStrategy.mqh"
#include "../../AIModules/TransformerBrain.mqh"
#include "../AI/AIFeatureVectorBuilder.mqh"

class CTransformerAIStrategyAdapter : public IStrategy
{
private:
    CTransformerBrain* m_transformer;
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    bool m_enabled;
    double m_weight;
    datetime m_lastSignalTime;
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


    datetime GetCurrentBarTime() const
    {
        if(m_symbol == "")
            return 0;
        return iTime(m_symbol, m_timeframe, 0);
    }

    bool NeedsNewInference(const datetime currentBarTime) const
    {
        return (!m_hasCachedSignal || currentBarTime <= 0 || currentBarTime != m_cacheBarTime);
    }

    void UpdateCache(const datetime currentBarTime, const ENUM_TRADE_SIGNAL signal, const double confidence)
    {
        m_cachedSignal = signal;
        m_cachedConfidence = confidence;
        m_cacheBarTime = currentBarTime;
        m_hasCachedSignal = true;
    }

    void LogVoteHeartbeat()
    {
        datetime now = TimeCurrent();
        if(m_lastVoteLogTime == 0 || (now - m_lastVoteLogTime) >= 10) // More frequent heartbeats
        {
            PrintFormat("[AI-VOTE][Transformer] %s | votes=%I64u | buy=%I64u | sell=%I64u | none=%I64u | conf=%.2f | reason=%s",
                        m_symbol, m_voteCount, m_buyVotes, m_sellVotes, m_noneVotes, m_cachedConfidence, m_lastDecisionReasonTag);
            m_lastVoteLogTime = now;
        }
    }

public:
    CTransformerAIStrategyAdapter()
    {
        // Runtime-lean transformer profile; per-symbol instance owned by adapter.
        m_transformer = new CTransformerBrain(TRANSFORMER_D_MODEL_DEFAULT, TRANSFORMER_NUM_HEADS_DEFAULT, TRANSFORMER_NUM_LAYERS_A_DEFAULT, TRANSFORMER_D_FF_DEFAULT, TRANSFORMER_DROPOUT_DEFAULT, TRANSFORMER_LR_A_DEFAULT);
        m_symbol = "";
        m_timeframe = PERIOD_CURRENT;
        m_enabled = true;
        m_weight = 1.0;
        m_lastSignalTime = 0;
        m_voteCount = 0;
        m_buyVotes = 0;
        m_sellVotes = 0;
        m_noneVotes = 0;
        m_lastVoteLogTime = 0;
        m_cachedSignal = TRADE_SIGNAL_NONE;
        m_cachedConfidence = 0.0;
        m_cacheBarTime = 0;
        m_hasCachedSignal = false;
        m_lastDecisionReasonTag = "TRANSFORMER_UNSET";
        m_minConfidence = 0.35;
    }

    virtual ~CTransformerAIStrategyAdapter()
    {
        if(m_transformer != NULL)
        {
            delete m_transformer;
            m_transformer = NULL;
        }
    }

    virtual bool Init(const string symbol,
                      const ENUM_TIMEFRAMES timeframe,
                      void* tradeManagerPtr,
                      void* positionSizerPtr) override
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        if(m_transformer == NULL)
            m_transformer = new CTransformerBrain(TRANSFORMER_D_MODEL_DEFAULT, TRANSFORMER_NUM_HEADS_DEFAULT, TRANSFORMER_NUM_LAYERS_A_DEFAULT, TRANSFORMER_D_FF_DEFAULT, TRANSFORMER_DROPOUT_DEFAULT, TRANSFORMER_LR_A_DEFAULT);
        if(m_transformer == NULL)
            return false;
        m_cachedSignal = TRADE_SIGNAL_NONE;
        m_cachedConfidence = 0.0;
        m_cacheBarTime = 0;
        m_hasCachedSignal = false;
        m_lastDecisionReasonTag = (m_transformer != NULL) ? "TRANSFORMER_INITIALIZED" : "TRANSFORMER_INIT_FAILED";
        return true;
    }

    virtual void Deinit(void) override
    {
        m_hasCachedSignal = false;
        m_lastDecisionReasonTag = "TRANSFORMER_DEINIT";
    }

    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        m_voteCount++;

        if(!m_enabled || m_transformer == NULL)
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "TRANSFORMER_DISABLED_OR_UNINIT";
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        datetime currentBarTime = GetCurrentBarTime();
        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
        if(!NeedsNewInference(currentBarTime))
        {
            confidence = m_cachedConfidence;
            signal = m_cachedSignal;
        }
        else
        {
            double inputSequence[];
            if(!CAIFeatureVectorBuilder::BuildTransformerInput(m_symbol, m_timeframe, inputSequence, TRANSFORMER_D_MODEL_DEFAULT, 8))
            {
                m_noneVotes++;
                m_lastDecisionReasonTag = "TRANSFORMER_FEATURES_UNAVAILABLE";
                UpdateCache(currentBarTime, TRADE_SIGNAL_NONE, 0.0);
                LogVoteHeartbeat();
                return TRADE_SIGNAL_NONE;
            }

            double predictions[];
            if(!m_transformer.GetPredictions(inputSequence, 8, predictions) || ArraySize(predictions) != 3)
            {
                m_noneVotes++;
                m_lastDecisionReasonTag = "TRANSFORMER_INFERENCE_FAILED";
                UpdateCache(currentBarTime, TRADE_SIGNAL_NONE, 0.0);
                LogVoteHeartbeat();
                return TRADE_SIGNAL_NONE;
            }

            double pNone = predictions[0];
            double pBuy = predictions[1];
            double pSell = predictions[2];

            double directionalConfidence = MathMax(pBuy, pSell);
            confidence = MathMax(0.0, MathMin(1.0, directionalConfidence));

            if(pBuy > pSell && pBuy >= pNone && directionalConfidence >= m_minConfidence)
                signal = TRADE_SIGNAL_BUY;
            else if(pSell > pBuy && pSell >= pNone && directionalConfidence >= m_minConfidence)
                signal = TRADE_SIGNAL_SELL;

            UpdateCache(currentBarTime, signal, confidence);
        }

        if(signal == TRADE_SIGNAL_BUY)
        {
            m_buyVotes++;
            m_lastSignalTime = TimeCurrent();
            m_lastDecisionReasonTag = "TRANSFORMER_SIGNAL_BUY";
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            m_sellVotes++;
            m_lastSignalTime = TimeCurrent();
            m_lastDecisionReasonTag = "TRANSFORMER_SIGNAL_SELL";
        }
        else
        {
            m_noneVotes++;
            m_lastDecisionReasonTag = "TRANSFORMER_NO_SIGNAL";
        }

        LogVoteHeartbeat();
        return signal;
    }

    virtual void OnNewBar(void) override {}
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override {}

    virtual string GetName(void) const override { return "Transformer AI"; }
    virtual ENUM_STRATEGY_TYPE GetType(void) const override { return STRATEGY_AI_ENHANCED; }
    virtual bool IsEnabled(void) const override { return m_enabled; }
    virtual void SetEnabled(const bool enabled) override { m_enabled = enabled; }
    virtual double GetWeight(void) const override { return m_weight; }
    virtual void SetWeight(const double weight) override { m_weight = weight; }
    virtual bool ValidateParameters(void) override { return (m_transformer != NULL); }
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

#endif // CORE_STRATEGY_TRANSFORMER_AI_STRATEGY_ADAPTER_MQH
