//+------------------------------------------------------------------+
//| AIStrategyAdapter.mqh                                            |
//| Adapter to integrate CNeuralNetworkStrategy into Enterprise Manager|
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Advanced Trading Systems"
#property strict

#include "../../Interfaces/IStrategy.mqh"
#include "../../AIModules/NeuralNetworkStrategy.mqh"

//+------------------------------------------------------------------+
//| AI Strategy Adapter Class                                        |
//+------------------------------------------------------------------+
class CAIStrategyAdapter : public IStrategy
{
private:
    CNeuralNetworkStrategy* m_neuralNet;
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    bool m_enabled;
    double m_weight;
    datetime m_lastSignalTime;
    string m_lastDecisionReasonTag;
    
    bool IsValidConfidence(const double conf) const
    {
        return !MathIsNaN(conf) && !MathIsInf(conf) && conf >= 0.0 && conf <= 1.0;
    }
    
public:
    CAIStrategyAdapter(CNeuralNetworkStrategy* neuralNet)
    {
        m_neuralNet = neuralNet;
        m_enabled = true;
        m_weight = 1.0;
        m_symbol = "";
        m_timeframe = PERIOD_CURRENT;
        m_lastSignalTime = 0;
        m_lastDecisionReasonTag = "NNAI_UNSET";
    }
    
    ~CAIStrategyAdapter()
    {
        // Do NOT delete m_neuralNet as it's managed externally
        m_neuralNet = NULL;
    }
    
    //+------------------------------------------------------------------+
    //| IStrategy Interface Implementation                               |
    //+------------------------------------------------------------------+
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, 
                     void* tradeManagerPtr, void* positionSizerPtr) override
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        m_lastDecisionReasonTag = (m_neuralNet != NULL) ? "NNAI_INITIALIZED" : "NNAI_INIT_FAILED";
        return (m_neuralNet != NULL);
    }
    
    virtual void Deinit(void) override
    {
        m_lastDecisionReasonTag = "NNAI_DEINIT";
    }
    
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        if(!m_enabled || m_neuralNet == NULL)
        {
            confidence = 0.0;
            m_lastDecisionReasonTag = "NNAI_DISABLED_OR_UNINIT";
            return TRADE_SIGNAL_NONE;
        }
        
        // Use the neural network to get signal
        ENUM_TRADE_SIGNAL signal = m_neuralNet.GetNeuralSignalCached(confidence);
        
        // Validate confidence value
        if(!IsValidConfidence(confidence))
        {
            static datetime s_lastInvalidLog = 0;
            if(s_lastInvalidLog == 0 || (TimeCurrent() - s_lastInvalidLog) >= 300)
            {
                PrintFormat("[AI-ADAPTER] Invalid confidence value: %.10f", confidence);
                s_lastInvalidLog = TimeCurrent();
            }
            confidence = 0.0;
            m_lastDecisionReasonTag = "NNAI_INVALID_CONFIDENCE";
            return TRADE_SIGNAL_NONE;
        }
        
        if(signal == TRADE_SIGNAL_BUY)
        {
            m_lastSignalTime = TimeCurrent();
            m_lastDecisionReasonTag = "NNAI_SIGNAL_BUY";
        }
        else if(signal == TRADE_SIGNAL_SELL)
        {
            m_lastSignalTime = TimeCurrent();
            m_lastDecisionReasonTag = "NNAI_SIGNAL_SELL";
        }
        else
        {
            m_lastDecisionReasonTag = "NNAI_NO_SIGNAL";
        }
        return signal;
    }
    
    virtual void OnNewBar(void) override {}
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override {}
    
    virtual string GetName(void) const override { return "Neural Network AI"; }
    
    virtual ENUM_STRATEGY_TYPE GetType(void) const override { return STRATEGY_BRAIN; }
    
    virtual bool IsEnabled(void) const override { return m_enabled; }
    
    virtual void SetEnabled(const bool enabled) override { m_enabled = enabled; }
    
    virtual double GetWeight(void) const override { return m_weight; }
    
    virtual void SetWeight(const double weight) override { m_weight = weight; }
    
    virtual bool ValidateParameters(void) override { return (m_neuralNet != NULL); }
    
    virtual datetime GetLastSignalTime(void) const override { return m_lastSignalTime; }
    virtual string GetLastDecisionReasonTag(void) const override { return m_lastDecisionReasonTag; }
    
    virtual void GetStatistics(int &signals, int &successful, double &accuracy) override
    {
        signals = 0;
        successful = 0;
        accuracy = 0.0;
    }
};
