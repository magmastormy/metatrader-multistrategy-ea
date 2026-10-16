// Builds the global and per-symbol indicator-strategy enable flag vectors.
// All methods are static - this cluster owns no state; config and the multi-asset
// profiler arrive as parameters.
#property strict

#ifndef CORE_ORCHESTRATION_ORCHESTRATOR_STRATEGY_FLAG_BUILDER_MQH
#define CORE_ORCHESTRATION_ORCHESTRATOR_STRATEGY_FLAG_BUILDER_MQH

#include "OrchestratorConfig.mqh"
#include "OrchestratorSymbolClassifier.mqh"
#include "../Strategy/StrategyCatalog.mqh"

// Mirrored from EAOrchestrator.mqh; #ifndef-guarded so the value stays single-sourced.
#ifndef STRATEGY_COUNT
#define STRATEGY_COUNT 21
#endif

class COrchestratorStrategyFlagBuilder
{
public:
    // The operator's enable input for one flag slot. A slot with no case here has no input, and the
    // caller prints which row that leaves switched off.
    static bool ConfigEnableForSlot(const SOrchestratorConfig &config, const int si, bool &hasInput)
    {
        hasInput = true;
        switch(si)
        {
            case SI_MOMENTUM:               return config.enableMomentum;
            case SI_TREND:                  return config.enableTrend;
            case SI_SUPPORT_RESISTANCE:     return config.enableSupportResistance;
            case SI_CANDLESTICK:            return config.enableCandlestick;
            case SI_MEAN_REVERSION:         return config.enableMeanReversion;
            case SI_VOLATILITY_BREAKOUT:    return config.enableVolatilityBreakout;
            case SI_STATISTICAL_ARBITRAGE:  return config.enableStatisticalArbitrage;
            case SI_FVG_SCALPER:            return config.enableFVGScalper;
            case SI_TURTLE_SOUP:            return config.enableTurtleSoup;
            case SI_BREAKER_BLOCK:          return config.enableBreakerBlock;
            case SI_NY_OPEN_GAP:            return config.enableNYOpenGap;
            case SI_ASIAN_RANGE_BREAK:      return config.enableAsianRangeBreak;
            case SI_LIQUIDITY_SWEEP:        return config.enableLiquiditySweep;
            case SI_RANGE_COMPRESSION:      return config.enableRangeCompression;
        }
        hasInput = false;
        return false;
    }

    static bool BuildStrategyFlags(const SOrchestratorConfig &config, bool &flags[])
    {
        ArrayResize(flags, STRATEGY_COUNT);
        ArrayInitialize(flags, false);

        BuildStrategyCatalog();
        for(int i = 0; i < g_strategyCatalogCount; i++)
        {
            if(g_strategyCatalog[i].kind != CAT_KIND_INDICATOR)
                continue;
            const int si = CatalogEnableSlot(i);
            if(si < 0 || si >= STRATEGY_COUNT)
                continue;

            bool hasInput = false;
            const bool on = ConfigEnableForSlot(config, si, hasInput);
            if(!hasInput)
            {
                PrintFormat("[CATALOG] %s | enable slot %d has no operator input - it stays off unless curated",
                            g_strategyCatalog[i].name, si);
                continue;
            }
            flags[si] = on;
            // Curated mode force-enables the rows marked curatedEnable; a false enableX input does not switch those off.
            if(config.useCuratedStrategySet && CatalogCuratedEnable(i)) flags[si] = true;
        }

        return true;
    }

    static bool BuildStrategyFlagsForSymbol(const SOrchestratorConfig &config,
                                            CMultiAssetProfiler *multiAssetProfiler,
                                            const string &symbol,
                                            const bool &globalFlags[],
                                            bool &symbolFlags[])
    {
        ArrayResize(symbolFlags, ArraySize(globalFlags));
        ArrayCopy(symbolFlags, globalFlags);

        bool isSynthetic = COrchestratorSymbolClassifier::IsSyntheticIndexSymbolName(symbol);

        if(config.useSymbolClassProfiles)
        {
            if(isSynthetic)
            {
                // Per-family enablement flags come from DerivAssetProfiler.
                CDerivAssetProfiler* derivProfiler = (multiAssetProfiler != NULL)
                                                     ? multiAssetProfiler.GetDerivProfiler()
                                                     : NULL;
                if(derivProfiler != NULL)
                {
                    SDerivProfile profile = derivProfiler.GetProfile(symbol);

                    if(!profile.enableTrendStrategies)
                    {
                        symbolFlags[SI_TREND] = false;
                    }
                    if(!profile.enableMomentumStrategies)
                    {
                        symbolFlags[SI_MOMENTUM] = false;
                    }

                    PrintFormat("[DERIV-PROFILER] %s → family=%s | enableTrend=%s | enableMomentum=%s",
                    symbol, EnumToString(profile.family),
                    profile.enableTrendStrategies ? "true" : "false",
                    profile.enableMomentumStrategies ? "true" : "false");
                }
                else
                {
                    // Fallback when the profiler is unavailable: static synthetic roster below.
                    symbolFlags[SI_MOMENTUM] = false;
                    symbolFlags[SI_TREND] = false;
                    symbolFlags[SI_MEAN_REVERSION] = true;
                    symbolFlags[SI_VOLATILITY_BREAKOUT] = true;
                    symbolFlags[SI_FVG_SCALPER] = true;
                }
            }
            else
            {
                // Non-synthetic symbols: trend and momentum are always enabled.
                symbolFlags[SI_TREND] = true;
                symbolFlags[SI_MOMENTUM] = true;
            }
        }

        return true;
    }
};

#endif // CORE_ORCHESTRATION_ORCHESTRATOR_STRATEGY_FLAG_BUILDER_MQH
