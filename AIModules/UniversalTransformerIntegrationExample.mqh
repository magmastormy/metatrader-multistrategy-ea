//+------------------------------------------------------------------+
//| Universal Transformer Integration Example                       |
//| Demonstrates how to integrate Universal Transformer with EA     |
//+------------------------------------------------------------------+
#ifndef __UNIVERSAL_TRANSFORMER_INTEGRATION_EXAMPLE_MQH__
#define __UNIVERSAL_TRANSFORMER_INTEGRATION_EXAMPLE_MQH__

#include "NextGenStrategyBrain.mqh"
#include "EnsembleMetaLearner.mqh"
#include "NeuralNetworkStrategy.mqh"

//+------------------------------------------------------------------+
//| Example EA Integration Class                                    |
//+------------------------------------------------------------------+
class CUniversalTransformerEAIntegration
{
private:
    CNextGenStrategyBrain* m_strategyBrain;
    CEnsembleMetaLearner* m_ensembleLearner;
    CNeuralNetworkStrategy* m_neuralNetwork;
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    bool m_initialized;
    
public:
    CUniversalTransformerEAIntegration() : 
        m_strategyBrain(NULL),
        m_ensembleLearner(NULL),
        m_neuralNetwork(NULL),
        m_symbol(""),
        m_timeframe(PERIOD_CURRENT),
        m_initialized(false)
    {
    }
    
    ~CUniversalTransformerEAIntegration()
    {
        if(m_strategyBrain != NULL) delete m_strategyBrain;
        if(m_ensembleLearner != NULL) delete m_ensembleLearner;
        if(m_neuralNetwork != NULL) delete m_neuralNetwork;
    }
    
    // Initialize all AI components
    bool Initialize(const string& symbol, ENUM_TIMEFRAMES timeframe)
    {
        m_symbol = symbol;
        m_timeframe = timeframe;
        
        // Initialize Universal Transformer Service
        if(!g_universalTransformerService.Initialize())
        {
            Print("[INTEGRATION] ERROR: Failed to initialize Universal Transformer Service");
            return false;
        }
        
        // Initialize Strategy Brain with Universal Transformer
        m_strategyBrain = new CNextGenStrategyBrain();
        if(m_strategyBrain == NULL || !m_strategyBrain->Initialize(symbol, timeframe))
        {
            Print("[INTEGRATION] ERROR: Failed to initialize Strategy Brain");
            return false;
        }
        
        // Enable Universal Transformer for Strategy Brain
        m_strategyBrain->SetUseUniversalTransformer(true);
        
        // Initialize Ensemble Meta Learner
        m_ensembleLearner = new CEnsembleMetaLearner();
        if(m_ensembleLearner == NULL || !m_ensembleLearner->Initialize(symbol, true))
        {
            Print("[INTEGRATION] ERROR: Failed to initialize Ensemble Learner");
            return false;
        }
        
        // Initialize Neural Network Strategy
        m_neuralNetwork = new CNeuralNetworkStrategy();
        if(m_neuralNetwork == NULL || !m_neuralNetwork->Initialize(symbol, timeframe))
        {
            Print("[INTEGRATION] ERROR: Failed to initialize Neural Network");
            return false;
        }
        
        // Enable Universal Transformer for Neural Network
        m_neuralNetwork->SetUseSharedTransformer(true);
        
        m_initialized = true;
        Print("[INTEGRATION] Successfully initialized Universal Transformer integration for ", symbol);
        return true;
    }
    
    // Generate trading signal using multiple AI components
    bool GenerateTradingSignal(const double& marketData[], int seqLen, SEnhancedTradeSignal& signal)
    {
        if(!m_initialized) return false;
        
        double brainBuySignal = 0.0, brainSellSignal = 0.0, brainConfidence = 0.0;
        double ensembleBuySignal = 0.0, ensembleSellSignal = 0.0, ensembleConfidence = 0.0;
        double neuralBuySignal = 0.0, neuralSellSignal = 0.0, neuralConfidence = 0.0;
        
        // Get signals from Strategy Brain
        if(m_strategyBrain != NULL)
        {
            // Strategy brain processes its own data, so we use a simplified approach
            double price = marketData[ArraySize(marketData) - 1]; // Latest price
            double volume = 1.0; // Placeholder volume
            double indicators[10]; // Placeholder indicators
            ArrayInitialize(indicators, 0.0);
            
            if(m_strategyBrain->GenerateSignal(price, volume, indicators, signal))
            {
                brainBuySignal = signal.buyProbability;
                brainSellSignal = signal.sellProbability;
                brainConfidence = signal.confidence;
            }
        }
        
        // Get signals from Ensemble Learner
        if(m_ensembleLearner != NULL)
        {
            if(m_ensembleLearner->ProcessWithSharedTransformer(marketData, ensembleBuySignal, ensembleSellSignal, ensembleConfidence))
            {
                // Successfully processed with shared transformer
            }
        }
        
        // Get signals from Neural Network
        if(m_neuralNetwork != NULL)
        {
            ENUM_TRADE_SIGNAL nnSignal = m_neuralNetwork->GenerateSignal(marketData, seqLen);
            neuralConfidence = m_neuralNetwork->GetLastConfidence();
            
            switch(nnSignal)
            {
                case TRADE_SIGNAL_BUY:
                    neuralBuySignal = neuralConfidence;
                    break;
                case TRADE_SIGNAL_SELL:
                    neuralSellSignal = neuralConfidence;
                    break;
                default:
                    neuralBuySignal = neuralSellSignal = 0.0;
                    break;
            }
        }
        
        // Combine signals from all components
        double combinedBuySignal = (brainBuySignal + ensembleBuySignal + neuralBuySignal) / 3.0;
        double combinedSellSignal = (brainSellSignal + ensembleSellSignal + neuralSellSignal) / 3.0;
        double combinedConfidence = (brainConfidence + ensembleConfidence + neuralConfidence) / 3.0;
        
        // Determine final signal
        signal.signal = TRADE_SIGNAL_NONE;
        signal.confidence = combinedConfidence;
        signal.buyProbability = combinedBuySignal;
        signal.sellProbability = combinedSellSignal;
        signal.timestamp = TimeCurrent();
        signal.reasoning = "Universal Transformer Ensemble";
        
        if(combinedBuySignal > 0.6 && combinedBuySignal > combinedSellSignal)
        {
            signal.signal = TRADE_SIGNAL_BUY;
        }
        else if(combinedSellSignal > 0.6 && combinedSellSignal > combinedBuySignal)
        {
            signal.signal = TRADE_SIGNAL_SELL;
        }
        
        return true;
    }
    
    // Update performance feedback to all components
    bool UpdatePerformance(double tradeReturn, bool isWin)
    {
        if(!m_initialized) return false;
        
        // Update Strategy Brain
        if(m_strategyBrain != NULL)
        {
            m_strategyBrain->UpdatePerformance(tradeReturn, isWin);
        }
        
        // Update Ensemble Learner
        if(m_ensembleLearner != NULL)
        {
            m_ensembleLearner->UpdateEnsemblePerformance(tradeReturn);
        }
        
        // Update Neural Network
        if(m_neuralNetwork != NULL)
        {
            m_neuralNetwork->UpdatePerformance(tradeReturn, isWin);
        }
        
        return true;
    }
    
    // Get system status
    string GetSystemStatus()
    {
        if(!m_initialized) return "Not Initialized";
        
        string status = "[UNIVERSAL TRANSFORMER SYSTEM]\n";
        status += "Symbol: " + m_symbol + "\n";
        status += "Timeframe: " + EnumToString(m_timeframe) + "\n";
        
        if(m_strategyBrain != NULL)
        {
            double totalReturn = 0.0;
            double winRate = 0.0;
            int totalTrades = 0;
            m_strategyBrain->GetPerformanceStats(totalReturn, winRate, totalTrades);
            status += StringFormat("Strategy Brain - Trades: %d, Win Rate: %.2f%%, Return: %.2f\n", 
                                 totalTrades, winRate * 100, totalReturn);
        }
        
        if(m_ensembleLearner != NULL)
        {
            int modelCount = m_ensembleLearner->GetActiveModelCount();
            status += "Ensemble Learner - Models: " + IntegerToString(modelCount) + "\n";
        }
        
        // Get Universal Transformer service status
        string serviceStatus;
        g_universalTransformerService.GetServiceStatus(serviceStatus);
        status += serviceStatus + "\n";
        
        return status;
    }
    
    // Check if system is ready for trading
    bool IsReadyForTrading()
    {
        if(!m_initialized) return false;
        
        bool strategyReady = (m_strategyBrain != NULL);
        bool ensembleReady = (m_ensembleLearner != NULL);
        bool neuralReady = (m_neuralNetwork != NULL);
        bool serviceReady = g_universalTransformerService.IsWarmedUp(50);
        
        return strategyReady && ensembleReady && neuralReady && serviceReady;
    }
    
    // Get individual component references
    CNextGenStrategyBrain* GetStrategyBrain() { return m_strategyBrain; }
    CEnsembleMetaLearner* GetEnsembleLearner() { return m_ensembleLearner; }
    CNeuralNetworkStrategy* GetNeuralNetwork() { return m_neuralNetwork; }
};

#endif // __UNIVERSAL_TRANSFORMER_INTEGRATION_EXAMPLE_MQH__