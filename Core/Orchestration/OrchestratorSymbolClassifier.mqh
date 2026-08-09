//+------------------------------------------------------------------+
//| OrchestratorSymbolClassifier.mqh                                 |
//| Phase F extraction from CEAOrchestrator (behaviour preserving).  |
//|                                                                  |
//| Pure symbol / strategy-roster classification helpers. Every      |
//| method below was moved verbatim out of CEAOrchestrator; the      |
//| orchestrator now keeps one-line forwarders with the original     |
//| signatures so no caller had to change.                           |
//|                                                                  |
//| All methods are static - this cluster owns no state.             |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_ORCHESTRATION_ORCHESTRATOR_SYMBOL_CLASSIFIER_MQH
#define CORE_ORCHESTRATION_ORCHESTRATOR_SYMBOL_CLASSIFIER_MQH

#include "OrchestratorConfig.mqh"

// Mirrored from EAOrchestrator.mqh. Guarded so the values stay single-sourced
// when this header is pulled in after the orchestrator has already defined them.
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

//+------------------------------------------------------------------+
//| COrchestratorSymbolClassifier                                    |
//+------------------------------------------------------------------+
class COrchestratorSymbolClassifier
{
public:
    //--- Synthetic index detection (was CEAOrchestrator::IsSyntheticIndexSymbolName)
    static bool IsSyntheticIndexSymbolName(const string &symbol)
    {
        // Fast string heuristic is authoritative for all common synthetic families and
        // avoids any dependency on the shared global profiler, which can be invalid
        // during multi-instance runtime re-initialization (invalid pointer access).
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

    //--- Forex detection (was CEAOrchestrator::IsForexSymbol)
    static bool IsForexSymbol(const string &symbol)
    {
        // Simple check for forex pairs (6-7 chars, no spaces)
        int len = StringLen(symbol);
        if(len >= 6 && len <= 7)
        {
            string base = StringSubstr(symbol, 0, 3);
            string quote = StringSubstr(symbol, 3, 3);
            // Check if all letters
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

    //--- Execution profile name (was CEAOrchestrator::GetInstrumentExecutionProfileName)
    static string GetInstrumentExecutionProfileName(const string &symbol)
    {
        if(IsSyntheticIndexSymbolName(symbol)) return "SYNTHETIC";
        if(IsForexSymbol(symbol)) return "FOREX";
        return "UNKNOWN";
    }

    //--- Roster profile label (was CEAOrchestrator::GetSymbolStrategyProfileLabel)
    static string GetSymbolStrategyProfileLabel(const string &symbol, const bool &strategyFlags[])
    {
        if(IsSyntheticIndexSymbolName(symbol)) return "SYNTHETIC_LEAN";
        return "STANDARD";
    }

    //--- Lean roster gate (was CEAOrchestrator::UseSyntheticLeanRosterProfile)
    static bool UseSyntheticLeanRosterProfile(const SOrchestratorConfig &config,
                                              const string &symbol,
                                              const bool &strategyFlags[])
    {
        return config.useSymbolClassProfiles && IsSyntheticIndexSymbolName(symbol);
    }

    //--- Effective indicator count (was CEAOrchestrator::CountEffectiveIndicatorStrategiesForSymbol)
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

    //--- Human readable roster (was CEAOrchestrator::BuildEnabledStrategyList)
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

    //--- Consensus input clamp (was CEAOrchestrator::ClampConsensusInput)
    static double ClampConsensusInput(double value)
    {
        return MathMax(0.0, MathMin(1.0, value));
    }
};

#endif // CORE_ORCHESTRATION_ORCHESTRATOR_SYMBOL_CLASSIFIER_MQH
