// Builds the global and per-symbol indicator-strategy enable flag vectors.
// All methods are static - this cluster owns no state; config and the multi-asset
// profiler arrive as parameters.
#property strict

#ifndef CORE_ORCHESTRATION_ORCHESTRATOR_STRATEGY_FLAG_BUILDER_MQH
#define CORE_ORCHESTRATION_ORCHESTRATOR_STRATEGY_FLAG_BUILDER_MQH

#include "OrchestratorConfig.mqh"
#include "OrchestratorSymbolClassifier.mqh"

// Mirrored from EAOrchestrator.mqh; #ifndef-guarded so the value stays single-sourced.
#ifndef STRATEGY_COUNT
#define STRATEGY_COUNT 21
#endif

class COrchestratorStrategyFlagBuilder
{
public:
    static bool BuildStrategyFlags(const SOrchestratorConfig &config, bool &flags[])
    {
        ArrayResize(flags, STRATEGY_COUNT);
        ArrayInitialize(flags, false);

        flags[SI_MOMENTUM] = config.enableMomentum;
        flags[SI_TREND] = config.enableTrend;
        flags[SI_SUPPORT_RESISTANCE] = config.enableSupportResistance;
        flags[SI_CANDLESTICK] = config.enableCandlestick;
        flags[SI_MEAN_REVERSION] = config.enableMeanReversion;
        flags[SI_VOLATILITY_BREAKOUT] = config.enableVolatilityBreakout;
        flags[SI_FVG_SCALPER] = config.enableFVGScalper;
        flags[SI_TURTLE_SOUP] = config.enableTurtleSoup;
        flags[SI_BREAKER_BLOCK] = config.enableBreakerBlock;
        flags[SI_NY_OPEN_GAP] = config.enableNYOpenGap;
        flags[SI_ASIAN_RANGE_BREAK] = config.enableAsianRangeBreak;
        flags[SI_STATISTICAL_ARBITRAGE] = config.enableStatisticalArbitrage;
        flags[SI_LIQUIDITY_SWEEP] = config.enableLiquiditySweep;
        flags[SI_RANGE_COMPRESSION] = config.enableRangeCompression;
        flags[SI_EXIT_OPTIMIZER] = config.enableExitOptimizer;

        if(config.useCuratedStrategySet)
        {
            // Curated mode force-enables every strategy below; a false enableX input does not switch it off.
            if(!config.enableMomentum) flags[SI_MOMENTUM] = true;
            if(!config.enableTrend) flags[SI_TREND] = true;
            if(!config.enableSupportResistance) flags[SI_SUPPORT_RESISTANCE] = true;
            if(!config.enableMeanReversion) flags[SI_MEAN_REVERSION] = true;
            if(!config.enableVolatilityBreakout) flags[SI_VOLATILITY_BREAKOUT] = true;
            if(!config.enableFVGScalper) flags[SI_FVG_SCALPER] = true;
            if(!config.enableTurtleSoup) flags[SI_TURTLE_SOUP] = true;
            if(!config.enableBreakerBlock) flags[SI_BREAKER_BLOCK] = true;
            if(!config.enableNYOpenGap) flags[SI_NY_OPEN_GAP] = true;
            if(!config.enableAsianRangeBreak) flags[SI_ASIAN_RANGE_BREAK] = true;
            if(!config.enableLiquiditySweep) flags[SI_LIQUIDITY_SWEEP] = true;
            if(!config.enableRangeCompression) flags[SI_RANGE_COMPRESSION] = true;
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

        string symbolClass = COrchestratorSymbolClassifier::GetInstrumentExecutionProfileName(symbol);
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
