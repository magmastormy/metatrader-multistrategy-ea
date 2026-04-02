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
    
public:
    CAIStrategyAdapter(CNeuralNetworkStrategy* neuralNet)
    {
        m_neuralNet = neuralNet;
        m_enabled = true;
        m_weight = 1.0;
        m_symbol = "";
        m_timeframe = PERIOD_CURRENT;
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
        return (m_neuralNet != NULL);
    }
    
    virtual void Deinit(void) override {}
    
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        if(!m_enabled || m_neuralNet == NULL)
        {
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }
        
        // Use the neural network to get signal
        return m_neuralNet.GetNeuralSignalCached(confidence);
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
    
    virtual datetime GetLastSignalTime(void) const override { return 0; }
    
    virtual void GetStatistics(int &signals, int &successful, double &accuracy) override
    {
        signals = 0;
        successful = 0;
        accuracy = 0.0;
    }
};
