//+------------------------------------------------------------------+
//| NeuralNetRegistry.mqh                                            |
//| Consolidates Neural Network strategies and AI adapters           |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_REGISTRY_NEURAL_NET_REGISTRY_MQH
#define CORE_REGISTRY_NEURAL_NET_REGISTRY_MQH

#include "../../AIModules/NeuralNetworkStrategy.mqh"
#include "../../Core/Strategy/AIStrategyAdapter.mqh"
#include "../../Core/Trading/PositionStateManager.mqh"
#include "../../Core/Trading/TradeAttributionManager.mqh"

class CNeuralNetRegistry
{
private:
    struct SNNEntry
    {
        string                    symbol;
        CNeuralNetworkStrategy*   neuralNet;
        CAIStrategyAdapter*       aiAdapter;
        ENUM_TIMEFRAMES           timeframe;
        bool                      active;
        
        SNNEntry() : symbol(""), neuralNet(NULL), aiAdapter(NULL), timeframe(PERIOD_CURRENT), active(false) {}
        
        ~SNNEntry()
        {
            if(CheckPointer(neuralNet) == POINTER_DYNAMIC) { delete neuralNet; neuralNet = NULL; }
            if(CheckPointer(aiAdapter) == POINTER_DYNAMIC) { delete aiAdapter; aiAdapter = NULL; }
        }
    };
    
    SNNEntry m_entries[];
    int m_entryCount;
    
    int GetIndex(const string symbol, bool createIfMissing = true)
    {
        for(int i = 0; i < m_entryCount; i++)
            if(m_entries[i].symbol == symbol) return i;
        
        if(!createIfMissing) return -1;
        
        int idx = m_entryCount;
        ArrayResize(m_entries, idx + 1);
        m_entries[idx].symbol = symbol;
        m_entryCount++;
        return idx;
    }

public:
    CNeuralNetRegistry() : m_entryCount(0) { ArrayResize(m_entries, 0); }
    ~CNeuralNetRegistry() { Clear(); }
    
    void Clear()
    {
        ArrayResize(m_entries, 0);
        m_entryCount = 0;
    }
    
    // Initialize or get existing neural net for symbol
    CNeuralNetworkStrategy* GetOrCreateNeuralNet(const string symbol, ENUM_TIMEFRAMES timeframe, double confidenceThreshold)
    {
        if(symbol == "") return NULL;
        
        int idx = GetIndex(symbol);
        
        if(m_entries[idx].neuralNet == NULL)
        {
            m_entries[idx].neuralNet = new CNeuralNetworkStrategy();
            if(m_entries[idx].neuralNet != NULL)
            {
                m_entries[idx].neuralNet.SetOnlineTrainingEnabled(true);
                m_entries[idx].neuralNet.SetWeightMutationEnabled(true);
                m_entries[idx].neuralNet.SetConfidenceThreshold(confidenceThreshold);
                
                if(!m_entries[idx].neuralNet.Initialize(symbol, timeframe))
                {
                    Print("[NeuralNetRegistry] Failed to initialize NN for ", symbol);
                    if(CheckPointer(m_entries[idx].neuralNet) == POINTER_DYNAMIC) { delete m_entries[idx].neuralNet; m_entries[idx].neuralNet = NULL; }
                    return NULL;
                }
                
                m_entries[idx].neuralNet.ConfigureOnlineLearning(true, 5, 300, 100);
                m_entries[idx].timeframe = timeframe;
                m_entries[idx].active = true;
                Print("[NeuralNetRegistry] Neural Network created for ", symbol);
            }
        }
        
        return m_entries[idx].neuralNet;
    }
    
    // Get or create AI adapter for symbol
    CAIStrategyAdapter* GetOrCreateAIAdapter(const string symbol, CNeuralNetworkStrategy* neuralNet)
    {
        if(symbol == "" || neuralNet == NULL) return NULL;
        
        int idx = GetIndex(symbol);
        
        if(m_entries[idx].aiAdapter == NULL)
        {
            m_entries[idx].aiAdapter = new CAIStrategyAdapter(neuralNet);
            Print("[NeuralNetRegistry] AI Adapter created for ", symbol);
        }
        
        return m_entries[idx].aiAdapter;
    }
    
    CNeuralNetworkStrategy* GetNeuralNet(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        return (idx >= 0) ? m_entries[idx].neuralNet : NULL;
    }
    
    CAIStrategyAdapter* GetAIAdapter(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        return (idx >= 0) ? m_entries[idx].aiAdapter : NULL;
    }
    
    void ReleaseSymbol(const string symbol)
    {
        int idx = GetIndex(symbol, false);
        if(idx >= 0)
        {
            // Destructors handle cleanup
            for(int i = idx; i < m_entryCount - 1; i++)
                m_entries[i] = m_entries[i + 1];
            ArrayResize(m_entries, m_entryCount - 1);
            m_entryCount--;
        }
    }
    
    void OnDeinitAll()
    {
        // Destructors handle cleanup automatically when Clear() is called
        // CNeuralNetworkStrategy destructor saves checkpoint
    }
    
    int GetActiveCount() const
    {
        int count = 0;
        for(int i = 0; i < m_entryCount; i++)
            if(m_entries[i].active) count++;
        return count;
    }
    
    string GetStatusReport() const
    {
        string report = "[NeuralNetRegistry] Active networks: " + IntegerToString(GetActiveCount()) + "/" + IntegerToString(m_entryCount) + "\n";
        for(int i = 0; i < m_entryCount; i++)
        {
            if(!m_entries[i].active) continue;
            report += "  " + m_entries[i].symbol + ": NN=" + (m_entries[i].neuralNet ? "OK" : "NULL");
            report += " Adapter=" + (m_entries[i].aiAdapter ? "OK" : "NULL");
            report += " TF=" + EnumToString(m_entries[i].timeframe) + "\n";
        }
        return report;
    }
};

#endif // CORE_REGISTRY_NEURAL_NET_REGISTRY_MQH