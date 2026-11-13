// Builds the five AI adapters, keyed by SStrategyDefinition.factoryName. Indicator strategies come from
// their catalog row's creator; a Create() call naming one is an error, not a second construction path.
#property strict

#ifndef CORE_FACTORY_STRATEGY_FACTORY_MQH
#define CORE_FACTORY_STRATEGY_FACTORY_MQH

// g_onnxModel: ONNX model byte buffer consumed by COnnxAIStrategyAdapter.
// Declared here as a static empty array so the file compiles standalone.
// The main EA may populate this via #resource directive before factory use.
uchar g_onnxModel[];

#include "../../Interfaces/IStrategy.mqh"
#include "../../Core/Utils/Enums.mqh"
#include "../../Core/Strategy/StrategyBase.mqh"
#include "../../Core/Strategy/AIStrategyAdapter.mqh"
#include "../../Core/Strategy/TransformerAIStrategyAdapter.mqh"
#include "../../Core/Strategy/EnsembleAIStrategyAdapter.mqh"
#include "../../Core/Strategy/OnnxAIStrategyAdapter.mqh"
#include "../../Core/Strategy/PythonBridgeAIStrategyAdapter.mqh"
#include "../../AIModules/NeuralNetworkStrategy.mqh"
#include "../../Core/Utils/PythonBridge.mqh"

class CStrategyFactory
{
private:
    typedef IStrategy* (*CreatorFunc)();
    
    // Static registry
    static string s_strategyNames[];
    static CreatorFunc s_creators[];
    static int s_registryCount;
    static bool s_initialized;
    
    // Private constructor - static class
    CStrategyFactory() {}
    
    static bool RegisterInternal(const string name, CreatorFunc creator)
    {
        if(s_registryCount >= 50) return false; // Safety limit
        
        ArrayResize(s_strategyNames, s_registryCount + 1);
        ArrayResize(s_creators, s_registryCount + 1);
        s_strategyNames[s_registryCount] = name;
        s_creators[s_registryCount] = creator;
        s_registryCount++;
        return true;
    }
    
    // Find creator index
    static int FindCreator(const string name)
    {
        for(int i = 0; i < s_registryCount; i++)
        {
            if(s_strategyNames[i] == name)
                return i;
        }
        return -1;
    }
    
    // AI adapter creators. Indicator strategies come from their catalog row's creator, never from here.
    static IStrategy* CreateNeuralNetworkAI()
        {
            CNeuralNetworkStrategy* nn = new CNeuralNetworkStrategy();
            return new CAIStrategyAdapter(nn, true); // Adapter owns NN when factory-created
        }
    
    static IStrategy* CreateTransformerAI()
    {
        return new CTransformerAIStrategyAdapter();
    }
    
    static IStrategy* CreateEnsembleAI()
    {
        return new CEnsembleAIStrategyAdapter();
    }
    
    static IStrategy* CreateONNXAI()
    {
        // The ONNX model buffer is the global g_onnxModel resource, not a per-call argument.
        return new COnnxAIStrategyAdapter(g_onnxModel);
    }
    
    static IStrategy* CreatePythonBridgeAI()
        {
            // Python Bridge is the global g_pythonBridge, declared in OrchestratorFwd.mqh.
            return new CPythonBridgeAIStrategyAdapter(g_pythonBridge);
        }

public:
    // Initialize factory - call once at startup
    static void Initialize()
    {
        if(s_initialized) return;
        
        ArrayResize(s_strategyNames, 0);
        ArrayResize(s_creators, 0);
        s_registryCount = 0;
        
        // --- AI Adapters (the only things this factory builds) ---
        RegisterInternal("Neural Network AI", CreateNeuralNetworkAI);
        RegisterInternal("Transformer AI", CreateTransformerAI);
        RegisterInternal("Ensemble AI", CreateEnsembleAI);
        RegisterInternal("ONNX AI", CreateONNXAI);
        RegisterInternal("Python Bridge AI", CreatePythonBridgeAI);
        
        s_initialized = true;
        Print("[StrategyFactory] Initialized with ", s_registryCount, " strategy creators");
    }
    
    static IStrategy* Create(const string name)
    {
        if(!s_initialized) Initialize();
        
        int idx = FindCreator(name);
        if(idx < 0)
        {
            Print("[StrategyFactory] ERROR: Unknown strategy '", name, "'");
            return NULL;
        }
        
        IStrategy* strategy = s_creators[idx]();
        if(strategy == NULL)
        {
            Print("[StrategyFactory] ERROR: Creator returned NULL for '", name, "'");
            return NULL;
        }
        
        return strategy;
    }
};

// Static member definitions
string CStrategyFactory::s_strategyNames[];
CStrategyFactory::CreatorFunc CStrategyFactory::s_creators[];
int CStrategyFactory::s_registryCount = 0;
bool CStrategyFactory::s_initialized = false;

#endif // CORE_FACTORY_STRATEGY_FACTORY_MQH
