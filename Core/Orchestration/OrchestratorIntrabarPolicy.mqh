//+------------------------------------------------------------------+
//| OrchestratorIntrabarPolicy.mqh                                   |
//| Phase F extraction from CEAOrchestrator (behaviour preserving).  |
//|                                                                  |
//| L7-009 / L7-010 centralized intrabar policy + timeframe config   |
//| resolution. Bodies moved verbatim out of CEAOrchestrator; the    |
//| orchestrator keeps one-line forwarders with the original         |
//| signatures.                                                      |
//|                                                                  |
//| All methods are static - this cluster owns no state. The two     |
//| collaborators the original bodies reached for (m_config and      |
//| m_multiAssetProfiler) are now explicit parameters.               |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_ORCHESTRATION_ORCHESTRATOR_INTRABAR_POLICY_MQH
#define CORE_ORCHESTRATION_ORCHESTRATOR_INTRABAR_POLICY_MQH

#include "OrchestratorConfig.mqh"
#include "OrchestratorSymbolClassifier.mqh"

//+------------------------------------------------------------------+
//| COrchestratorIntrabarPolicy                                      |
//+------------------------------------------------------------------+
class COrchestratorIntrabarPolicy
{
public:
    //--- was CEAOrchestrator::ResolveSparseIntrabarMinQualityForSymbol
    static double ResolveSparseIntrabarMinQualityForSymbol(const SOrchestratorConfig &config,
                                                           const string &symbol,
                                                           const bool &strategyFlags[])
    {
        if(COrchestratorSymbolClassifier::IsSyntheticIndexSymbolName(symbol))
        return config.syntheticLeanSparseIntrabarMinQuality;
        return config.sparseIntrabarMinQuality;
    }

    //--- was CEAOrchestrator::ResolveIntrabarSingleVoterMinConfidenceForSymbol
    static double ResolveIntrabarSingleVoterMinConfidenceForSymbol(const SOrchestratorConfig &config,
                                                                   const string &symbol,
                                                                   const bool &strategyFlags[])
    {
        if(COrchestratorSymbolClassifier::IsSyntheticIndexSymbolName(symbol))
        return config.syntheticLeanIntrabarSingleVoterMinConfidence;
        return config.intrabarSingleVoterMinConfidence;
    }

    // L7-009/L7-010: Centralized intrabar policy resolution
    // Replaces hardcoded switch statements and duplicate resolution functions
    // Synthetic lean overrides driven by CDerivAssetProfiler family profile, not hardcoded indices
    //--- was CEAOrchestrator::GetIntrabarPolicy
    static ENUM_INTRABAR_POLICY GetIntrabarPolicy(const SOrchestratorConfig &config,
                                                  CMultiAssetProfiler *multiAssetProfiler,
                                                  const string symbol,
                                                  int strategyIndex,
                                                  const bool &strategyFlags[])
    {
        // Bounds check
        if(strategyIndex < 0 || strategyIndex >= config.strategyConfigCount)
        return INTRABAR_POLICY_OFF;

        // Get base policy from centralized config
        ENUM_INTRABAR_POLICY policy = config.strategyIntrabarConfigs[strategyIndex].defaultPolicy;

        // If strategy is disabled, return OFF
        if(strategyIndex < ArraySize(strategyFlags) && !strategyFlags[strategyIndex])
        return INTRABAR_POLICY_OFF;

        // Synthetic lean override: check if symbol is synthetic and strategy is marked as primary
        if(COrchestratorSymbolClassifier::IsSyntheticIndexSymbolName(symbol) &&
           config.strategyIntrabarConfigs[strategyIndex].syntheticLeanPrimary)
        {
            // For synthetic lean symbols, upgrade PROBE to LIVE if configured
            if(policy == INTRABAR_POLICY_PROBE)
            policy = INTRABAR_POLICY_LIVE;
            // For synthetic lean, we might also allow LIVE where it was OFF for certain strategies
            // This is driven by the family profile from CDerivAssetProfiler
            CDerivAssetProfiler* derivProfiler = (multiAssetProfiler != NULL)
                                                 ? multiAssetProfiler.GetDerivProfiler()
                                                 : NULL;
            if(derivProfiler != NULL)
            {
                SDerivProfile profile = derivProfiler.GetProfile(symbol);
                if(profile.enableIntrabarOverride && policy != INTRABAR_POLICY_OFF)
                {
                    // Family profile allows intrabar for this strategy
                    policy = INTRABAR_POLICY_LIVE;
                }
            }
        }

        return policy;
    }

    // L7-009: Get strategy timeframe config from centralized array
    //--- was CEAOrchestrator::GetStrategyTimeframeConfig
    static SStrategyTimeframeConfig GetStrategyTimeframeConfig(const SOrchestratorConfig &config,
                                                               int strategyIndex)
    {
        static SStrategyTimeframeConfig defaultConfig;
        if(strategyIndex < 0 || strategyIndex >= config.strategyConfigCount)
        return defaultConfig;
        return config.strategyTimeframeConfigs[strategyIndex];
    }
};

#endif // CORE_ORCHESTRATION_ORCHESTRATOR_INTRABAR_POLICY_MQH
