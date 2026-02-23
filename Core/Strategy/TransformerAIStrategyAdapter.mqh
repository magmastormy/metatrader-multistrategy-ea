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

    void Softmax3(const double in0, const double in1, const double in2, double &out0, double &out1, double &out2) const
    {
        double maxValue = MathMax(in0, MathMax(in1, in2));
        double ex0 = MathExp(in0 - maxValue);
        double ex1 = MathExp(in1 - maxValue);
        double ex2 = MathExp(in2 - maxValue);
        double sum = ex0 + ex1 + ex2;
        if(sum <= 1e-12)
            sum = 1e-12;

        out0 = ex0 / sum;
        out1 = ex1 / sum;
        out2 = ex2 / sum;
    }

    void LogVoteHeartbeat()
    {
        datetime now = TimeCurrent();
        if(m_lastVoteLogTime == 0 || (now - m_lastVoteLogTime) >= 60)
        {
            PrintFormat("[AI-VOTE][Transformer] %s | votes=%I64u | buy=%I64u | sell=%I64u | none=%I64u",
                        m_symbol, m_voteCount, m_buyVotes, m_sellVotes, m_noneVotes);
            m_lastVoteLogTime = now;
        }
    }

public:
    CTransformerAIStrategyAdapter()
    {
        // Runtime-lean transformer profile; per-symbol instance owned by adapter.
        m_transformer = new CTransformerBrain(256, 8, 4, 512, 64, 0.001);
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
    }

    virtual ~CTransformerAIStrategyAdapter()
    {
        if(m_transformer != NULL)
        {
            m_transformer.Shutdown();
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
            m_transformer = new CTransformerBrain(256, 8, 4, 512, 64, 0.001);
        if(m_transformer == NULL)
            return false;
        return m_transformer.Initialize();
    }

    virtual void Deinit(void) override
    {
        if(m_transformer != NULL)
            m_transformer.Shutdown();
    }

    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        confidence = 0.0;
        m_voteCount++;

        if(!m_enabled || m_transformer == NULL)
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

        double output[];
        if(!m_transformer.Forward(inputSequence, output) || ArraySize(output) < 3)
        {
            m_noneVotes++;
            LogVoteHeartbeat();
            return TRADE_SIGNAL_NONE;
        }

        // Map logits to class probabilities using NN-compatible labels:
        // class 0 = NONE, class 1 = BUY, class 2 = SELL.
        double pNone = 0.0;
        double pBuy = 0.0;
        double pSell = 0.0;
        Softmax3(output[0], output[1], output[2], pNone, pBuy, pSell);

        double directionalConfidence = MathMax(pBuy, pSell);
        confidence = MathMax(0.0, MathMin(1.0, directionalConfidence));

        ENUM_TRADE_SIGNAL signal = TRADE_SIGNAL_NONE;
        if(pBuy > pSell && pBuy >= pNone && directionalConfidence >= 0.45)
            signal = TRADE_SIGNAL_BUY;
        else if(pSell > pBuy && pSell >= pNone && directionalConfidence >= 0.45)
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

    virtual string GetName(void) const override { return "Transformer AI"; }
    virtual ENUM_STRATEGY_TYPE GetType(void) const override { return STRATEGY_AI_ENHANCED; }
    virtual bool IsEnabled(void) const override { return m_enabled; }
    virtual void SetEnabled(const bool enabled) override { m_enabled = enabled; }
    virtual double GetWeight(void) const override { return m_weight; }
    virtual void SetWeight(const double weight) override { m_weight = weight; }
    virtual bool ValidateParameters(void) override { return (m_transformer != NULL); }
    virtual datetime GetLastSignalTime(void) const override { return m_lastSignalTime; }

    virtual void GetStatistics(int &signals, int &successful, double &accuracy) override
    {
        signals = (int)m_voteCount;
        successful = 0;
        accuracy = 0.0;
    }
};

#endif // CORE_STRATEGY_TRANSFORMER_AI_STRATEGY_ADAPTER_MQH
