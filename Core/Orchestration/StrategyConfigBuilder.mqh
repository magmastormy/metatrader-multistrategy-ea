// Initializes the strategy-specific timeframe overrides.
#ifndef STRATEGY_CONFIG_BUILDER_MQH
#define STRATEGY_CONFIG_BUILDER_MQH

#include "OrchestratorConfig.mqh"

class CStrategyConfigBuilder
{
public:
    static void Initialize(SOrchestratorConfig &config)
    {
        for(int i = 0; i < MAX_STRATEGY_CONFIGS; i++)
            config.strategyTimeframes[i] = PERIOD_CURRENT;

        // Only these two rows name a timeframe other than the chart's. Both reach strategy Init,
        // so InpMomentumScalpTimeframe and InpCandlestickIntrabarTimeframe bind from here.
        config.strategyTimeframes[0] = config.momentumScalpTimeframe;   // Momentum
        config.strategyTimeframes[4] = config.candlestickIntrabarTimeframe; // Candlestick

        config.strategyConfigCount = MAX_STRATEGY_CONFIGS;

        PrintFormat("[CONFIG] Initialized %d strategy timeframe overrides", config.strategyConfigCount);
    }
};

#endif
