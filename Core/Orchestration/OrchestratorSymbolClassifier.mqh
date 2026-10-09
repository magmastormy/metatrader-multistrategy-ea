// Pure symbol / strategy-roster classification helpers.
// All methods are static - this cluster owns no state.
#property strict

#ifndef CORE_ORCHESTRATION_ORCHESTRATOR_SYMBOL_CLASSIFIER_MQH
#define CORE_ORCHESTRATION_ORCHESTRATOR_SYMBOL_CLASSIFIER_MQH

#include "OrchestratorConfig.mqh"

// Mirrored from EAOrchestrator.mqh and #ifndef-guarded so the indices stay single-sourced
// whatever the include order.
#ifndef STRATEGY_NEURAL_NETWORK_AI
#define STRATEGY_NEURAL_NETWORK_AI 17
#endif
#ifndef STRATEGY_TRANSFORMER_AI
#define STRATEGY_TRANSFORMER_AI 18
#endif
#ifndef STRATEGY_ENSEMBLE_AI
#define STRATEGY_ENSEMBLE_AI 19
#endif
#ifndef STRATEGY_ONNX_AI
#define STRATEGY_ONNX_AI 20
#endif

class COrchestratorSymbolClassifier
{
public:
    static bool IsSyntheticIndexSymbolName(const string &symbol)
    {
        // The string heuristic is authoritative for common synthetic families: it avoids the shared
        // global profiler, which can be an invalid pointer during multi-instance re-initialization.
        if(StringFind(symbol, "Volatility") >= 0 ||
           StringFind(symbol, "Boom")      >= 0 ||
           StringFind(symbol, "Crash")     >= 0 ||
           StringFind(symbol, "Jump")      >= 0 ||
           StringFind(symbol, "Step Index")>= 0)
            return true;
        // Secondary, guarded profiler check for edge-case synthetic families.
        if(g_multiAssetProfiler != NULL)
        {
            SAssetProfile profile = g_multiAssetProfiler.GetProfile(symbol);
            return IsSyntheticAssetClass(profile.assetClass);
        }
        return false;
    }

    static bool IsForexSymbol(const string &symbol)
    {
        // Forex pair: 6-7 characters, first 6 all uppercase letters.
        int len = StringLen(symbol);
        if(len >= 6 && len <= 7)
        {
            string base = StringSubstr(symbol, 0, 3);
            string quote = StringSubstr(symbol, 3, 3);
            for(int i = 0; i < 6; i++)
            {
                if(i < StringLen(symbol))
                {
                    ushort c = StringGetCharacter(symbol, i);
                    if(!(c >= 'A' && c <= 'Z')) return false;
                }
            }
            return true;
        }
        return false;
    }

    static string GetInstrumentExecutionProfileName(const string &symbol)
    {
        if(IsSyntheticIndexSymbolName(symbol)) return "SYNTHETIC";
        if(IsForexSymbol(symbol)) return "FOREX";
        return "UNKNOWN";
    }

    static string GetSymbolStrategyProfileLabel(const string &symbol, const bool &strategyFlags[])
    {
        if(IsSyntheticIndexSymbolName(symbol)) return "SYNTHETIC_LEAN";
        return "STANDARD";
    }

    static bool UseSyntheticLeanRosterProfile(const SOrchestratorConfig &config,
                                              const string &symbol,
                                              const bool &strategyFlags[])
    {
        return config.useSymbolClassProfiles && IsSyntheticIndexSymbolName(symbol);
    }

    static int CountEffectiveIndicatorStrategiesForSymbol(const bool &symbolFlags[])
    {
        int count = 0;
        for(int i = 0; i < ArraySize(symbolFlags); i++)
        {
            if(symbolFlags[i])
            count++;
        }
        // Exclude AI strategies from this count
        if(symbolFlags[STRATEGY_NEURAL_NETWORK_AI]) count--;
        if(symbolFlags[STRATEGY_TRANSFORMER_AI]) count--;
        if(symbolFlags[STRATEGY_ENSEMBLE_AI]) count--;
        if(symbolFlags[STRATEGY_ONNX_AI]) count--;
        return count;
    }

    static string BuildEnabledStrategyList(const bool &strategyFlags[])
    {
        string list = "";
        for(int i = 0; i < ArraySize(strategyFlags); i++)
        {
            if(strategyFlags[i])
            {
                if(list != "") list += ", ";
                list += EnumToString((ENUM_STRATEGY_TYPE)i);
            }
        }
        return list;
    }

    static double ClampConsensusInput(double value)
    {
        return MathMax(0.0, MathMin(1.0, value));
    }
};

#endif // CORE_ORCHESTRATION_ORCHESTRATOR_SYMBOL_CLASSIFIER_MQH
