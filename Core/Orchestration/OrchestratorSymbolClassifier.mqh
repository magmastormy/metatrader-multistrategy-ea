// Pure symbol / strategy-roster classification helpers.
// All methods are static - this cluster owns no state.
#property strict

#ifndef CORE_ORCHESTRATION_ORCHESTRATOR_SYMBOL_CLASSIFIER_MQH
#define CORE_ORCHESTRATION_ORCHESTRATOR_SYMBOL_CLASSIFIER_MQH

#include "OrchestratorConfig.mqh"
#include "../Strategy/StrategyCatalog.mqh"

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

    // Indicator rows only: AI adapters are registered by the orchestrator and own no enable slot, so
    // there is nothing to subtract. The literal AI indices this used to subtract were flag-array slots
    // 17-20, which belong to Liquidity Sweep, Range Compression and Exit Optimizer.
    static int CountEffectiveIndicatorStrategiesForSymbol(const bool &symbolFlags[])
    {
        const int size = ArraySize(symbolFlags);
        int count = 0;
        BuildStrategyCatalog();
        for(int i = 0; i < g_strategyCatalogCount; i++)
        {
            if(g_strategyCatalog[i].kind != CAT_KIND_INDICATOR)
                continue;
            const int si = CatalogEnableSlot(i);
            if(si >= 0 && si < size && symbolFlags[si])
                count++;
        }
        return count;
    }

    static string BuildEnabledStrategyList(const bool &strategyFlags[])
    {
        const int size = ArraySize(strategyFlags);
        string list = "";
        BuildStrategyCatalog();
        for(int i = 0; i < g_strategyCatalogCount; i++)
        {
            if(g_strategyCatalog[i].kind != CAT_KIND_INDICATOR)
                continue;
            const int si = CatalogEnableSlot(i);
            if(si < 0 || si >= size || !strategyFlags[si])
                continue;
            if(list != "") list += ", ";
            list += g_strategyCatalog[i].name;
        }
        return list;
    }

};

#endif // CORE_ORCHESTRATION_ORCHESTRATOR_SYMBOL_CLASSIFIER_MQH
