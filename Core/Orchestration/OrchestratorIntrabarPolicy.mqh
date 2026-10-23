// Centralized intrabar policy resolution.
// All methods are static - this cluster owns no state; config and the multi-asset
// profiler arrive as parameters.
#property strict

#ifndef CORE_ORCHESTRATION_ORCHESTRATOR_INTRABAR_POLICY_MQH
#define CORE_ORCHESTRATION_ORCHESTRATOR_INTRABAR_POLICY_MQH

#include "OrchestratorConfig.mqh"
#include "OrchestratorSymbolClassifier.mqh"

class COrchestratorIntrabarPolicy
{
public:
    // Synthetic-lean overrides come from the CDerivAssetProfiler family profile, never hardcoded indices.
    static ENUM_INTRABAR_POLICY GetIntrabarPolicy(const SOrchestratorConfig &config,
                                                  CMultiAssetProfiler *multiAssetProfiler,
                                                  const string symbol,
                                                  int strategyIndex,
                                                  const bool &strategyFlags[])
    {
        if(strategyIndex < 0 || strategyIndex >= config.strategyConfigCount)
        return INTRABAR_POLICY_OFF;

        ENUM_INTRABAR_POLICY policy = config.strategyIntrabarConfigs[strategyIndex].defaultPolicy;

        if(strategyIndex < ArraySize(strategyFlags) && !strategyFlags[strategyIndex])
        return INTRABAR_POLICY_OFF;

        if(COrchestratorSymbolClassifier::IsSyntheticIndexSymbolName(symbol) &&
           config.strategyIntrabarConfigs[strategyIndex].syntheticLeanPrimary)
        {
            if(policy == INTRABAR_POLICY_PROBE)
            policy = INTRABAR_POLICY_LIVE;
            // The profile override upgrades a policy but never resurrects INTRABAR_POLICY_OFF.
            CDerivAssetProfiler* derivProfiler = (multiAssetProfiler != NULL)
                                                 ? multiAssetProfiler.GetDerivProfiler()
                                                 : NULL;
            if(derivProfiler != NULL)
            {
                SDerivProfile profile = derivProfiler.GetProfile(symbol);
                if(profile.enableIntrabarOverride && policy != INTRABAR_POLICY_OFF)
                {
                    policy = INTRABAR_POLICY_LIVE;
                }
            }
        }

        return policy;
    }
};

#endif // CORE_ORCHESTRATION_ORCHESTRATOR_INTRABAR_POLICY_MQH
