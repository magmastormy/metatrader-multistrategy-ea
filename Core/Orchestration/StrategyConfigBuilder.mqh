// Pure config-array initialization: no runtime behavior, no invariant surface.
// Every strategy owns exactly one timeframe row and one intrabar row, both indexed by that
// strategy's catalog siPolicyIndex. Two strategies sharing a row lets one clobber the other's
// policy. Slots 3/5/6/20 belong to strategies the catalog no longer carries and keep defaults.
#ifndef STRATEGY_CONFIG_BUILDER_MQH
#define STRATEGY_CONFIG_BUILDER_MQH

#include "OrchestratorConfig.mqh"

class CStrategyConfigBuilder
{
public:
    static void Initialize(SOrchestratorConfig &config)
    {
        for(int i = 0; i < MAX_STRATEGY_CONFIGS; i++)
        {
            config.strategyTimeframes[i] = PERIOD_CURRENT;
            config.strategyIntrabarConfigs[i].defaultPolicy = INTRABAR_POLICY_OFF;
            config.strategyIntrabarConfigs[i].syntheticLeanPrimary = false;
        }

        // Only these two rows name a timeframe other than the chart's. Both reach strategy Init,
        // so InpMomentumScalpTimeframe and InpCandlestickIntrabarTimeframe bind from here.
        config.strategyTimeframes[0] = config.momentumScalpTimeframe;   // Momentum
        config.strategyTimeframes[4] = config.candlestickIntrabarTimeframe; // Candlestick

        config.strategyIntrabarConfigs[0].defaultPolicy  = config.intrabarEligibilityMomentum;
        config.strategyIntrabarConfigs[1].defaultPolicy  = config.intrabarEligibilityTrend;
        config.strategyIntrabarConfigs[1].syntheticLeanPrimary = true;
        config.strategyIntrabarConfigs[2].defaultPolicy  = config.intrabarEligibilitySupportResistance;
        config.strategyIntrabarConfigs[2].syntheticLeanPrimary = true;
        config.strategyIntrabarConfigs[4].defaultPolicy  = config.intrabarEligibilityCandlestick;
        config.strategyIntrabarConfigs[4].syntheticLeanPrimary = true;
        config.strategyIntrabarConfigs[7].defaultPolicy  = config.intrabarEligibilityMeanReversion;
        config.strategyIntrabarConfigs[7].syntheticLeanPrimary = true;
        config.strategyIntrabarConfigs[8].defaultPolicy  = config.intrabarEligibilityVolatilityBreakout;
        config.strategyIntrabarConfigs[8].syntheticLeanPrimary = true;
        config.strategyIntrabarConfigs[9].defaultPolicy  = config.intrabarEligibilityNeuralNetworkAI;
        config.strategyIntrabarConfigs[10].defaultPolicy = config.intrabarEligibilityTransformerAI;
        config.strategyIntrabarConfigs[11].defaultPolicy = config.intrabarEligibilityEnsembleAI;
        config.strategyIntrabarConfigs[12].defaultPolicy = config.intrabarEligibilityOnnxAI;
        config.strategyIntrabarConfigs[13].defaultPolicy = config.intrabarEligibilityPythonBridgeAI;

        // Python Bridge AI owns row 13; FVG Scalper and Statistical Arbitrage own rows 21 and 22.

        config.strategyConfigCount = MAX_STRATEGY_CONFIGS;

        PrintFormat("[CONFIG] Initialized %d strategy timeframe/intrabar configs", config.strategyConfigCount);
    }
};

#endif
