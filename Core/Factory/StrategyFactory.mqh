//+------------------------------------------------------------------+
//| StrategyFactory.mqh                                              |
//| Centralized strategy creation - eliminates registration bloat    |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_FACTORY_STRATEGY_FACTORY_MQH
#define CORE_FACTORY_STRATEGY_FACTORY_MQH

// g_onnxModel is declared in main EA via #resource directive
// It's globally visible when this header is included in the main EA
// No declaration needed here

#include "../../Interfaces/IStrategy.mqh"
#include "../../Core/Utils/Enums.mqh"
#include "../../Core/Strategy/StrategyBase.mqh"
#include "../../Strategies/SimpleMomentumStrategy.mqh"
#include "../../Strategies/StrategyTrend.mqh"
#include "../../Strategies/StrategySupportResistance.mqh"
#include "../../Strategies/StrategyUnifiedICT.mqh"
#include "../../Strategies/StrategyCandlestick.mqh"
#include "../../Strategies/CUnicornModelStrategy.mqh"
#include "../../Strategies/CPowerOfThreeStrategy.mqh"
#include "../../Strategies/MeanReversionStrategy.mqh"
#include "../../Strategies/VolatilityBreakoutStrategy.mqh"
#include "../../Strategies/StatisticalArbitrageStrategy.mqh"
#include "../../Strategies/FVGScalperStrategy.mqh"
#include "../../Strategies/TurtleSoupStrategy.mqh"
#include "../../Strategies/BreakerBlockStrategy.mqh"
#include "../../Strategies/NYOpenGapStrategy.mqh"
#include "../../Strategies/AsianRangeBreakStrategy.mqh"
#include "../../Core/Strategy/AIStrategyAdapter.mqh"
#include "../../Core/Strategy/TransformerAIStrategyAdapter.mqh"
#include "../../Core/Strategy/EnsembleAIStrategyAdapter.mqh"
#include "../../Core/Strategy/OnnxAIStrategyAdapter.mqh"
#include "../../AIModules/NeuralNetworkStrategy.mqh"
#include "../../Core/Utils/PythonBridge.mqh"
#include "../../Core/Engines/OrnsteinUhlenbeckEngine.mqh"
#include "../../Core/Engines/HurstEngine.mqh"

class CStrategyFactory
{
private:
    // Strategy configuration bundle
    struct SStrategyConfig
    {
        string          symbol;
        ENUM_TIMEFRAMES timeframe;
        double          weight;
        ENUM_STRATEGY_TIER tier;
        bool            intrabarEligible;
        bool            liveVotingEnabled;
        ENUM_STRATEGY_ROLE role;
        ENUM_STRATEGY_CLUSTER cluster;
        
        // Strategy-specific parameters
        bool            momentumScalpingEnabled;
        int             momentumScalpCooldown;
        double          trendADXNoTrendThreshold;
        bool            ictRequireKillZone;
        bool            candlestickRequireTrend;
        bool            meanReversionSyntheticMode;
        bool            statArbUsePythonBridge;
        CPythonBridge*  pythonBridge;
        COrnsteinUhlenbeckEngine* ouEngine;
        CHurstEngine*   hurstEngine;
        
        SStrategyConfig() : 
            symbol(""), timeframe(PERIOD_CURRENT), weight(1.0), tier(STRATEGY_TIER_2),
            intrabarEligible(false), liveVotingEnabled(false),
            role(PRIMARY_ALPHA), cluster(STRATEGY_CLUSTER_NONE),
            momentumScalpingEnabled(false), momentumScalpCooldown(0),
            trendADXNoTrendThreshold(12.0), ictRequireKillZone(false),
            candlestickRequireTrend(false), meanReversionSyntheticMode(false),
            statArbUsePythonBridge(false), pythonBridge(NULL), ouEngine(NULL), hurstEngine(NULL)
        {}
    };
    
    // Creator function type
    typedef IStrategy* (*CreatorFunc)(const SStrategyConfig&);
    
    // Static registry
    static string s_strategyNames[];
    static CreatorFunc s_creators[];
    static int s_registryCount;
    static bool s_initialized;
    
    // Private constructor - static class
    CStrategyFactory() {}
    
    // Register a creator
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
    
    // ============================================================
    // STRATEGY CREATORS (one per strategy)
    // ============================================================
    
    static IStrategy* CreateMomentum(const SStrategyConfig& cfg)
    {
        CSimpleMomentumStrategy* s = new CSimpleMomentumStrategy();
        if(s != NULL)
            s.SetScalpingMode(cfg.momentumScalpingEnabled, cfg.momentumScalpCooldown);
        return s;
    }
    
    static IStrategy* CreateTrend(const SStrategyConfig& cfg)
    {
        CStrategyTrend* s = new CStrategyTrend();
        if(s != NULL)
            s.SetADXThresholds(cfg.trendADXNoTrendThreshold, 20.0, 25.0, 35.0);
        return s;
    }
    
    static IStrategy* CreateSupportResistance(const SStrategyConfig& cfg)
    {
        return new CStrategySupportResistance();
    }
    
    static IStrategy* CreateUnifiedICT(const SStrategyConfig& cfg)
    {
        CStrategyUnifiedICT* s = new CStrategyUnifiedICT();
        if(s != NULL)
            s.SetRequireKillZone(cfg.ictRequireKillZone);
        return s;
    }
    
    static IStrategy* CreateCandlestick(const SStrategyConfig& cfg)
    {
        CStrategyCandlestick* s = new CStrategyCandlestick();
        if(s != NULL)
            s.SetRequireTrendAlignment(cfg.candlestickRequireTrend);
        return s;
    }
    
    static IStrategy* CreateUnicornModel(const SStrategyConfig& cfg)
    {
        return new CUnicornModelStrategy();
    }
    
    static IStrategy* CreatePowerOfThree(const SStrategyConfig& cfg)
    {
        return new CPowerOfThreeStrategy();
    }
    
    static IStrategy* CreateMeanReversion(const SStrategyConfig& cfg)
    {
        CMeanReversionStrategy* s = new CMeanReversionStrategy();
        if(s != NULL)
            s.SetSyntheticMode(cfg.meanReversionSyntheticMode);
        if(s != NULL && cfg.hurstEngine != NULL)
            s.SetHurstEngine(cfg.hurstEngine);
        return s;
    }
    
    static IStrategy* CreateVolatilityBreakout(const SStrategyConfig& cfg)
    {
        return new CVolatilityBreakoutStrategy();
    }
    
    static IStrategy* CreateStatisticalArbitrage(const SStrategyConfig& cfg)
    {
        CStatisticalArbitrageStrategy* s = new CStatisticalArbitrageStrategy();
        if(s != NULL && cfg.statArbUsePythonBridge && cfg.pythonBridge != NULL)
            s.SetPythonBridge(cfg.pythonBridge);
        if(s != NULL && cfg.ouEngine != NULL)
            s.SetOUEngine(cfg.ouEngine);
        return s;
    }
    
    static IStrategy* CreateFVGScalper(const SStrategyConfig& cfg)
    {
        return new CFVGScalperStrategy();
    }
    
    static IStrategy* CreateTurtleSoup(const SStrategyConfig& cfg)
    {
        return new CTurtleSoupStrategy();
    }
    
    static IStrategy* CreateBreakerBlock(const SStrategyConfig& cfg)
    {
        return new CBreakerBlockStrategy();
    }
    
    static IStrategy* CreateNYOpenGap(const SStrategyConfig& cfg)
    {
        return new CNYOpenGapStrategy();
    }
    
    static IStrategy* CreateAsianRangeBreak(const SStrategyConfig& cfg)
    {
        return new CAsianRangeBreakStrategy();
    }
    
    static IStrategy* CreateNeuralNetworkAI(const SStrategyConfig& cfg)
    {
        CNeuralNetworkStrategy* nn = new CNeuralNetworkStrategy();
        if(nn != NULL)
        {
            // NN will be initialized separately via InitializeNeuralNetForSymbol
            // This adapter wraps the NN
        }
        return new CAIStrategyAdapter(nn); // nn may be NULL here, adapter handles it
    }
    
    static IStrategy* CreateTransformerAI(const SStrategyConfig& cfg)
    {
        return new CTransformerAIStrategyAdapter();
    }
    
    static IStrategy* CreateEnsembleAI(const SStrategyConfig& cfg)
    {
        return new CEnsembleAIStrategyAdapter();
    }
    
    static IStrategy* CreateONNXAI(const SStrategyConfig& cfg)
    {
        // Note: ONNX model is global (g_onnxModel resource) - declared in main EA
        return new COnnxAIStrategyAdapter(g_onnxModel);
    }

public:
    // Initialize factory - call once at startup
    static void Initialize()
    {
        if(s_initialized) return;
        
        ArrayResize(s_strategyNames, 0);
        ArrayResize(s_creators, 0);
        s_registryCount = 0;
        
        // --- Core Indicator Strategies ---
        RegisterInternal("Momentum", CreateMomentum);
        RegisterInternal("Trend", CreateTrend);
        RegisterInternal("Support/Resistance", CreateSupportResistance);
        RegisterInternal("Unified ICT", CreateUnifiedICT);
        RegisterInternal("Candlestick", CreateCandlestick);
        RegisterInternal("Unicorn Model", CreateUnicornModel);
        RegisterInternal("Power of Three", CreatePowerOfThree);
        
        // --- Batch 93/103 Strategies ---
        RegisterInternal("Mean Reversion", CreateMeanReversion);
        RegisterInternal("Volatility Breakout", CreateVolatilityBreakout);
        RegisterInternal("Statistical Arbitrage", CreateStatisticalArbitrage);
        
        // --- Batch 103 ICT/SMC Strategies ---
        RegisterInternal("FVG Scalper", CreateFVGScalper);
        RegisterInternal("Turtle Soup", CreateTurtleSoup);
        RegisterInternal("Breaker Block", CreateBreakerBlock);
        RegisterInternal("NY Open Gap", CreateNYOpenGap);
        RegisterInternal("Asian Range Break", CreateAsianRangeBreak);
        
        // --- AI Adapters ---
        RegisterInternal("Neural Network AI", CreateNeuralNetworkAI);
        RegisterInternal("Transformer AI", CreateTransformerAI);
        RegisterInternal("Ensemble AI", CreateEnsembleAI);
        RegisterInternal("ONNX AI", CreateONNXAI);
        
        s_initialized = true;
        Print("[StrategyFactory] Initialized with ", s_registryCount, " strategy creators");
    }
    
    // Create strategy by name with configuration
    static IStrategy* Create(const string name, const SStrategyConfig& cfg)
    {
        if(!s_initialized) Initialize();
        
        int idx = FindCreator(name);
        if(idx < 0)
        {
            Print("[StrategyFactory] ERROR: Unknown strategy '", name, "'");
            return NULL;
        }
        
        IStrategy* strategy = s_creators[idx](cfg);
        if(strategy == NULL)
        {
            Print("[StrategyFactory] ERROR: Creator returned NULL for '", name, "'");
            return NULL;
        }
        
        return strategy;
    }
    
    // Check if strategy is registered
    static bool IsRegistered(const string name)
    {
        if(!s_initialized) Initialize();
        return FindCreator(name) >= 0;
    }
    
    // Get all registered strategy names
    static void GetRegisteredNames(string &names[])
    {
        if(!s_initialized) Initialize();
        ArrayResize(names, s_registryCount);
        for(int i = 0; i < s_registryCount; i++)
            names[i] = s_strategyNames[i];
    }
    
    // Get count
    static int GetCount()
    {
        if(!s_initialized) Initialize();
        return s_registryCount;
    }
    
    // Build config from EA inputs (helper for migration)
    static SStrategyConfig BuildConfigFromEA(const string symbol, 
                                              const string strategyName,
                                              const bool &strategyFlags[],
                                              CEnterpriseStrategyManager* manager = NULL)
    {
        SStrategyConfig cfg;
        cfg.symbol = symbol;
        cfg.timeframe = PERIOD_CURRENT; // Will be resolved by manager
        cfg.weight = 1.0; // Will be overridden by registry weight
        cfg.tier = STRATEGY_TIER_2;
        cfg.intrabarEligible = false;
        cfg.liveVotingEnabled = false;
        cfg.role = PRIMARY_ALPHA;
        cfg.cluster = STRATEGY_CLUSTER_NONE;
        
        // These would be filled from EA inputs in actual usage
        // For now, return base config - caller should override
        return cfg;
    }
};

// Static member definitions
string CStrategyFactory::s_strategyNames[];
CStrategyFactory::CreatorFunc CStrategyFactory::s_creators[];
int CStrategyFactory::s_registryCount = 0;
bool CStrategyFactory::s_initialized = false;

#endif // CORE_FACTORY_STRATEGY_FACTORY_MQH