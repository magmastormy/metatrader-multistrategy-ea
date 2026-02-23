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

    bool EnsureModels()
    {
        if(m_modelsInitialized)
            return true;

        if(!m_ensemble.Initialize())
            return false;

        // Two diverse transformer members for ensemble voting.
        CTransformerBrain* modelA = new CTransformerBrain(256, 8, 4, 512, 64, 0.001);
        CTransformerBrain* modelB = new CTransformerBrain(256, 8, 3, 384, 64, 0.0015);
        if(modelA == NULL || modelB == NULL)
            return false;

        if(!modelA.Initialize() || !modelB.Initialize())
            return false;

        if(!m_ensemble.AddModel(modelA, 1.0))
            return false;
        if(!m_ensemble.AddModel(modelB, 1.0))
            return false;

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
    }

    virtual ~CEnsembleAIStrategyAdapter()
    {
        m_ensemble.Shutdown();
    }

    virtual bool Init(const string symbol,
                      const ENUM_TIMEFRAMES timeframe,
                      void* tradeManagerPtr,
                      void* positionSizerPtr) override
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        return EnsureModels();
    }

    virtual void Deinit(void) override
    {
        m_ensemble.Shutdown();
    }

    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        m_voteCount++;

        if(!m_enabled || !EnsureModels())
        {
            m_noneVotes++;
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        double inputSequence[];
        if(!CAIFeatureVectorBuilder::BuildTransformerInput(m_symbol, m_timeframe, inputSequence, 256, 1))
        {
            m_noneVotes++;
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        double ensembleBuy = 0.0;
        double ensembleSell = 0.0;
        double ensembleConfidence = 0.0;
        if(!m_ensemble.ProcessMarketData(inputSequence, ensembleBuy, ensembleSell, ensembleConfidence))
        {
            m_noneVotes++;
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        double directionalConfidence = MathMax(ensembleBuy, ensembleSell);
        confidence = MathMax(0.0, MathMin(1.0, MathMax(ensembleConfidence, directionalConfidence)));

        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
        if(ensembleBuy > ensembleSell && directionalConfidence >= 0.45)
            signal = TRADE_SIGNAL_BUY;
        else if(ensembleSell > ensembleBuy && directionalConfidence >= 0.45)
            signal = TRADE_SIGNAL_SELL;

        if(signal == TRADE_SIGNAL_BUY)
        {
            m_buyVotes++;
            m_lastSignalTime = TimeCurrent();
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            m_sellVotes++;
            m_lastSignalTime = TimeCurrent();
        }
        else
        {
            m_noneVotes++;
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

    virtual void GetStatistics(int &signals, int &successful, double &accuracy) override
    {
        signals = (int)m_voteCount;
        successful = 0;
        accuracy = 0.0;
    }
};

#endif // CORE_STRATEGY_ENSEMBLE_AI_STRATEGY_ADAPTER_MQH
