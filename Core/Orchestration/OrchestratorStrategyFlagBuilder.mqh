// Phase F extraction from CEAOrchestrator (behaviour preserving).
// Builds the global and per-symbol indicator-strategy enable flag
// vectors. Moved verbatim out of CEAOrchestrator; the orchestrator
// keeps one-line forwarders with the original signatures, so the
// flag semantics, curated overrides and every log line are
// byte-for-byte unchanged.
// All methods are static - this cluster owns no state. The two
// collaborators the original bodies reached for (m_config and
// m_multiAssetProfiler) are now explicit parameters.
#property strict

#ifndef CORE_ORCHESTRATION_ORCHESTRATOR_STRATEGY_FLAG_BUILDER_MQH
#define CORE_ORCHESTRATION_ORCHESTRATOR_STRATEGY_FLAG_BUILDER_MQH

#include "OrchestratorConfig.mqh"
#include "OrchestratorSymbolClassifier.mqh"

// Mirrored from EAOrchestrator.mqh (guarded - identical value).
#ifndef STRATEGY_COUNT
#define STRATEGY_COUNT 21
#endif

class COrchestratorStrategyFlagBuilder
{
public:
    //--- Global roster (was CEAOrchestrator::BuildStrategyFlags)
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

        // Curated mode overrides (Batch 114)
        if(config.useCuratedStrategySet)
        {
            // Apply curated defaults - but explicit enables remain authoritative
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

    //--- Per-symbol roster (was CEAOrchestrator::BuildStrategyFlagsForSymbol)
    static bool BuildStrategyFlagsForSymbol(const SOrchestratorConfig &config,
                                            CMultiAssetProfiler *multiAssetProfiler,
                                            const string &symbol,
                                            const bool &globalFlags[],
                                            bool &symbolFlags[])
    {
        // Start with global flags
        ArrayResize(symbolFlags, ArraySize(globalFlags));
        ArrayCopy(symbolFlags, globalFlags);

        // Apply symbol-specific overrides
        string symbolClass = COrchestratorSymbolClassifier::GetInstrumentExecutionProfileName(symbol);
        bool isSynthetic = COrchestratorSymbolClassifier::IsSyntheticIndexSymbolName(symbol);

        if(config.useSymbolClassProfiles)
        {
            if(isSynthetic)
            {
                // L7-006: Query DerivAssetProfiler for per-family strategy enablement flags
                CDerivAssetProfiler* derivProfiler = (multiAssetProfiler != NULL)
                                                     ? multiAssetProfiler.GetDerivProfiler()
                                                     : NULL;
                if(derivProfiler != NULL)
                {
                    SDerivProfile profile = derivProfiler.GetProfile(symbol);

                    // Use per-family flags instead of blanket synthetic logic
                    if(!profile.enableTrendStrategies)
                    {
                        symbolFlags[SI_TREND] = false;
                    }
                    if(!profile.enableMomentumStrategies)
                    {
                        symbolFlags[SI_MOMENTUM] = false;
                    }

                    // Log the family-specific configuration
                    PrintFormat("[DERIV-PROFILER] %s → family=%s | enableTrend=%s | enableMomentum=%s",
                    symbol, EnumToString(profile.family),
                    profile.enableTrendStrategies ? "true" : "false",
                    profile.enableMomentumStrategies ? "true" : "false");
                }
                else
                {
                    // Fallback to original logic if profiler not available
                    symbolFlags[SI_MOMENTUM] = false;
                    symbolFlags[SI_TREND] = false;
                    symbolFlags[SI_MEAN_REVERSION] = true;
                    symbolFlags[SI_VOLATILITY_BREAKOUT] = true;
                    symbolFlags[SI_FVG_SCALPER] = true;
                }
            }
            else
            {
                // Forex: enable trend/momentum, suppress some synthetic-specific
                symbolFlags[SI_TREND] = true;
                symbolFlags[SI_MOMENTUM] = true;
            }
        }

        return true;
    }
};

#endif // CORE_ORCHESTRATION_ORCHESTRATOR_STRATEGY_FLAG_BUILDER_MQH
