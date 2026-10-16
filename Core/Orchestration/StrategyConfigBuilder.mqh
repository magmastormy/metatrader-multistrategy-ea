// Pure config-array initialization: no runtime behavior, no invariant surface.
// Every strategy owns exactly one timeframe row and one intrabar row.
#ifndef STRATEGY_CONFIG_BUILDER_MQH
#define STRATEGY_CONFIG_BUILDER_MQH

#include "OrchestratorConfig.mqh"

class CStrategyConfigBuilder
{
public:
    static void Initialize(SOrchestratorConfig &config)
    {
        config.strategyConfigCount = 0;

        config.strategyTimeframeConfigs[0].name = "Momentum";
        config.strategyTimeframeConfigs[0].defaultTF = config.momentumScalpTimeframe;
        config.strategyTimeframeConfigs[0].intrabarEnabled = (config.intrabarEligibilityMomentum != INTRABAR_POLICY_OFF);
        config.strategyTimeframeConfigs[0].intrabarTF = config.momentumScalpTimeframe;
        config.strategyTimeframeConfigs[0].forceHigherOnM1Synthetic = true;

        config.strategyIntrabarConfigs[0].name = "Momentum";
        config.strategyIntrabarConfigs[0].defaultPolicy = config.intrabarEligibilityMomentum;
        config.strategyIntrabarConfigs[0].syntheticLeanPrimary = false;

        config.strategyTimeframeConfigs[1].name = "Trend";
        config.strategyTimeframeConfigs[1].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[1].intrabarEnabled = (config.intrabarEligibilityTrend != INTRABAR_POLICY_OFF);
        config.strategyTimeframeConfigs[1].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[1].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[1].name = "Trend";
        config.strategyIntrabarConfigs[1].defaultPolicy = config.intrabarEligibilityTrend;
        config.strategyIntrabarConfigs[1].syntheticLeanPrimary = true;

        config.strategyTimeframeConfigs[2].name = "Support/Resistance";
        config.strategyTimeframeConfigs[2].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[2].intrabarEnabled = (config.intrabarEligibilitySupportResistance != INTRABAR_POLICY_OFF);
        config.strategyTimeframeConfigs[2].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[2].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[2].name = "Support/Resistance";
        config.strategyIntrabarConfigs[2].defaultPolicy = config.intrabarEligibilitySupportResistance;
        config.strategyIntrabarConfigs[2].syntheticLeanPrimary = true;



        config.strategyTimeframeConfigs[4].name = "Candlestick";
        config.strategyTimeframeConfigs[4].defaultTF = config.candlestickIntrabarTimeframe;
        config.strategyTimeframeConfigs[4].intrabarEnabled = (config.intrabarEligibilityCandlestick != INTRABAR_POLICY_OFF);
        config.strategyTimeframeConfigs[4].intrabarTF = config.candlestickIntrabarTimeframe;
        config.strategyTimeframeConfigs[4].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[4].name = "Candlestick";
        config.strategyIntrabarConfigs[4].defaultPolicy = config.intrabarEligibilityCandlestick;
        config.strategyIntrabarConfigs[4].syntheticLeanPrimary = true;





        config.strategyTimeframeConfigs[7].name = "Mean Reversion";
        config.strategyTimeframeConfigs[7].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[7].intrabarEnabled = (config.intrabarEligibilityMeanReversion != INTRABAR_POLICY_OFF);
        config.strategyTimeframeConfigs[7].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[7].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[7].name = "Mean Reversion";
        config.strategyIntrabarConfigs[7].defaultPolicy = config.intrabarEligibilityMeanReversion;
        config.strategyIntrabarConfigs[7].syntheticLeanPrimary = true;

        config.strategyTimeframeConfigs[8].name = "Volatility Breakout";
        config.strategyTimeframeConfigs[8].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[8].intrabarEnabled = (config.intrabarEligibilityVolatilityBreakout != INTRABAR_POLICY_OFF);
        config.strategyTimeframeConfigs[8].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[8].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[8].name = "Volatility Breakout";
        config.strategyIntrabarConfigs[8].defaultPolicy = config.intrabarEligibilityVolatilityBreakout;
        config.strategyIntrabarConfigs[8].syntheticLeanPrimary = true;

        config.strategyTimeframeConfigs[9].name = "Neural Network AI";
        config.strategyTimeframeConfigs[9].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[9].intrabarEnabled = (config.intrabarEligibilityNeuralNetworkAI != INTRABAR_POLICY_OFF);
        config.strategyTimeframeConfigs[9].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[9].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[9].name = "Neural Network AI";
        config.strategyIntrabarConfigs[9].defaultPolicy = config.intrabarEligibilityNeuralNetworkAI;
        config.strategyIntrabarConfigs[9].syntheticLeanPrimary = false;

        config.strategyTimeframeConfigs[10].name = "Transformer AI";
        config.strategyTimeframeConfigs[10].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[10].intrabarEnabled = (config.intrabarEligibilityTransformerAI != INTRABAR_POLICY_OFF);
        config.strategyTimeframeConfigs[10].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[10].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[10].name = "Transformer AI";
        config.strategyIntrabarConfigs[10].defaultPolicy = config.intrabarEligibilityTransformerAI;
        config.strategyIntrabarConfigs[10].syntheticLeanPrimary = false;

        config.strategyTimeframeConfigs[11].name = "Ensemble AI";
        config.strategyTimeframeConfigs[11].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[11].intrabarEnabled = (config.intrabarEligibilityEnsembleAI != INTRABAR_POLICY_OFF);
        config.strategyTimeframeConfigs[11].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[11].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[11].name = "Ensemble AI";
        config.strategyIntrabarConfigs[11].defaultPolicy = config.intrabarEligibilityEnsembleAI;
        config.strategyIntrabarConfigs[11].syntheticLeanPrimary = false;

        config.strategyTimeframeConfigs[12].name = "ONNX AI";
        config.strategyTimeframeConfigs[12].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[12].intrabarEnabled = (config.intrabarEligibilityOnnxAI != INTRABAR_POLICY_OFF);
        config.strategyTimeframeConfigs[12].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[12].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[12].name = "ONNX AI";
        config.strategyIntrabarConfigs[12].defaultPolicy = config.intrabarEligibilityOnnxAI;
        config.strategyIntrabarConfigs[12].syntheticLeanPrimary = false;

        config.strategyTimeframeConfigs[13].name = "Python Bridge AI";
        config.strategyTimeframeConfigs[13].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[13].intrabarEnabled = (config.intrabarEligibilityPythonBridgeAI != INTRABAR_POLICY_OFF);
        config.strategyTimeframeConfigs[13].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[13].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[13].name = "Python Bridge AI";
        config.strategyIntrabarConfigs[13].defaultPolicy = config.intrabarEligibilityPythonBridgeAI;
        config.strategyIntrabarConfigs[13].syntheticLeanPrimary = false;

        // Python Bridge AI owns row 13; FVG Scalper and Statistical Arbitrage own rows 21 and 22.

        config.strategyTimeframeConfigs[14].name = "Turtle Soup";
        config.strategyTimeframeConfigs[14].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[14].intrabarEnabled = false;
        config.strategyTimeframeConfigs[14].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[14].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[14].name = "Turtle Soup";
        config.strategyIntrabarConfigs[14].defaultPolicy = INTRABAR_POLICY_OFF;
        config.strategyIntrabarConfigs[14].syntheticLeanPrimary = false;

        config.strategyTimeframeConfigs[15].name = "Breaker Block";
        config.strategyTimeframeConfigs[15].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[15].intrabarEnabled = false;
        config.strategyTimeframeConfigs[15].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[15].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[15].name = "Breaker Block";
        config.strategyIntrabarConfigs[15].defaultPolicy = INTRABAR_POLICY_OFF;
        config.strategyIntrabarConfigs[15].syntheticLeanPrimary = false;

        config.strategyTimeframeConfigs[16].name = "NY Open Gap";
        config.strategyTimeframeConfigs[16].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[16].intrabarEnabled = false;
        config.strategyTimeframeConfigs[16].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[16].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[16].name = "NY Open Gap";
        config.strategyIntrabarConfigs[16].defaultPolicy = INTRABAR_POLICY_OFF;
        config.strategyIntrabarConfigs[16].syntheticLeanPrimary = false;

        config.strategyTimeframeConfigs[17].name = "Asian Range Break";
        config.strategyTimeframeConfigs[17].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[17].intrabarEnabled = false;
        config.strategyTimeframeConfigs[17].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[17].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[17].name = "Asian Range Break";
        config.strategyIntrabarConfigs[17].defaultPolicy = INTRABAR_POLICY_OFF;
        config.strategyIntrabarConfigs[17].syntheticLeanPrimary = false;

        config.strategyTimeframeConfigs[18].name = "Liquidity Sweep";
        config.strategyTimeframeConfigs[18].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[18].intrabarEnabled = false;
        config.strategyTimeframeConfigs[18].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[18].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[18].name = "Liquidity Sweep";
        config.strategyIntrabarConfigs[18].defaultPolicy = INTRABAR_POLICY_OFF;
        config.strategyIntrabarConfigs[18].syntheticLeanPrimary = false;

        config.strategyTimeframeConfigs[19].name = "Range Compression";
        config.strategyTimeframeConfigs[19].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[19].intrabarEnabled = false;
        config.strategyTimeframeConfigs[19].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[19].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[19].name = "Range Compression";
        config.strategyIntrabarConfigs[19].defaultPolicy = INTRABAR_POLICY_OFF;
        config.strategyIntrabarConfigs[19].syntheticLeanPrimary = false;

        config.strategyTimeframeConfigs[20].name = "Exit Optimizer";
        config.strategyTimeframeConfigs[20].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[20].intrabarEnabled = false;
        config.strategyTimeframeConfigs[20].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[20].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[20].name = "Exit Optimizer";
        config.strategyIntrabarConfigs[20].defaultPolicy = INTRABAR_POLICY_OFF;
        config.strategyIntrabarConfigs[20].syntheticLeanPrimary = false;

        // Rows are indexed by each strategy's catalog policy index; two strategies sharing a row
        // lets one clobber the other's intrabar policy. Rows 21/22 carry INTRABAR_POLICY_OFF.

        // Strategy 21: FVG Scalper
        config.strategyTimeframeConfigs[21].name = "FVG Scalper";
        config.strategyTimeframeConfigs[21].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[21].intrabarEnabled = false;
        config.strategyTimeframeConfigs[21].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[21].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[21].name = "FVG Scalper";
        config.strategyIntrabarConfigs[21].defaultPolicy = INTRABAR_POLICY_OFF;
        config.strategyIntrabarConfigs[21].syntheticLeanPrimary = false;

        // Strategy 22: Statistical Arbitrage
        config.strategyTimeframeConfigs[22].name = "Statistical Arbitrage";
        config.strategyTimeframeConfigs[22].defaultTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[22].intrabarEnabled = false;
        config.strategyTimeframeConfigs[22].intrabarTF = PERIOD_CURRENT;
        config.strategyTimeframeConfigs[22].forceHigherOnM1Synthetic = false;

        config.strategyIntrabarConfigs[22].name = "Statistical Arbitrage";
        config.strategyIntrabarConfigs[22].defaultPolicy = INTRABAR_POLICY_OFF;
        config.strategyIntrabarConfigs[22].syntheticLeanPrimary = false;

        config.strategyConfigCount = MAX_STRATEGY_CONFIGS;

        PrintFormat("[CONFIG] Initialized %d strategy timeframe/intrabar configs", config.strategyConfigCount);
    }
};

#endif
