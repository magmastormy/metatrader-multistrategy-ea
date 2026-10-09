// Phase F extraction from CEAOrchestrator (behaviour preserving).
// Effective EA-mode degradation, AI runtime vote threshold and the
// two startup topology log lines. Bodies moved verbatim out of
// CEAOrchestrator; the orchestrator keeps one-line forwarders with
// the original signatures.
// NOTE: LogAIRuntimeTopology() prints __FILE__. Because that macro
// expands at the *definition* site, the orchestrator forwarder
// passes its own __FILE__ in as `sourceFile` so the emitted
// [RUNTIME-FINGERPRINT] line is unchanged.
// All methods are static - this cluster owns no state.
#property strict

#ifndef CORE_ORCHESTRATION_ORCHESTRATOR_MODE_RESOLVER_MQH
#define CORE_ORCHESTRATION_ORCHESTRATOR_MODE_RESOLVER_MQH

#include "OrchestratorConfig.mqh"
#include "OrchestratorSymbolClassifier.mqh"
#include "../../Core/Strategy/StrategyRegistry.mqh"

class COrchestratorModeResolver
{
public:
    //--- was CEAOrchestrator::ResolveAIRuntimeVoteThreshold
    static double ResolveAIRuntimeVoteThreshold(const SOrchestratorConfig &config,
                                                ENUM_EA_MODE effectiveMode)
    {
        return MathMax(0.50, MathMin(1.0, config.aiConfidenceThreshold));
    }

    //--- was CEAOrchestrator::ResolveEffectiveEAMode
    static ENUM_EA_MODE ResolveEffectiveEAMode(const SOrchestratorConfig &config,
                                               CStrategyRegistry *strategyRegistry)
    {
        if(strategyRegistry == NULL) return config.eaMode;

        ENUM_EA_MODE configuredMode = strategyRegistry.GetMode();
        int activeIndicators = strategyRegistry.GetActiveIndicatorCount();
        int activeAI = strategyRegistry.GetActiveAICount();

        ENUM_EA_MODE effectiveMode = configuredMode;
        string reason = "";

        if((configuredMode == EA_MODE_AI_ONLY || configuredMode == EA_MODE_INDICATOR_FILTERED) && activeAI <= 0)
        {
            effectiveMode = EA_MODE_INDICATOR_ONLY;
            reason = "no_active_ai_voters";
        }
        else if((configuredMode == EA_MODE_INDICATOR_ONLY || configuredMode == EA_MODE_AI_ASSISTED) && activeIndicators <= 0 && activeAI > 0)
        {
            effectiveMode = EA_MODE_AI_ONLY;
            reason = "no_active_indicators";
        }
        else if(configuredMode == EA_MODE_HYBRID && activeAI <= 0)
        {
            effectiveMode = EA_MODE_INDICATOR_ONLY;
            reason = "no_active_ai_voters";
        }
        else if(configuredMode == EA_MODE_HYBRID && activeIndicators <= 0 && activeAI > 0)
        {
            effectiveMode = EA_MODE_AI_ONLY;
            reason = "no_active_indicators";
        }
        else if(configuredMode == EA_MODE_AI_ASSISTED && activeAI <= 0)
        {
            effectiveMode = EA_MODE_INDICATOR_ONLY;
            reason = "no_active_ai_voters";
        }
        else if(configuredMode == EA_MODE_INDICATOR_FILTERED && activeIndicators <= 0)
        {
            effectiveMode = EA_MODE_AI_ONLY;
            reason = "no_active_indicators";
        }

        if(effectiveMode != configuredMode)
        {
            PrintFormat("[MODE-DEGRADE] %s → %s | reason=%s | activeIndicators=%d | activeAI=%d",
            EAModeToString(configuredMode), EAModeToString(effectiveMode), reason, activeIndicators, activeAI);
        }

        return effectiveMode;
    }

    //--- was CEAOrchestrator::LogAIRuntimeTopology (m_aiTopologyLogged stays on the
    //    orchestrator; the forwarder sets it after this call, exactly as before).
    static void LogAIRuntimeTopology(const SOrchestratorConfig &config,
                                     CStrategyRegistry *strategyRegistry,
                                     const string sourceFile,
                                     const string firstSymbol)
    {
        if(strategyRegistry == NULL) return;

        ENUM_EA_MODE effectiveMode = ResolveEffectiveEAMode(config, strategyRegistry);
        PrintFormat("[RUNTIME-FINGERPRINT] Runtime=%s | File=%s | TerminalBuild=%d | Curated=%s | RegistrySize=%d | ActiveProfile=%s | RequestedMode=%s | EAMode=%s | HybridStandalone=%s | StandaloneThreshold=%.2f | Indicators=%d | AI=%d",
        TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
        sourceFile, (int)TerminalInfoInteger(TERMINAL_BUILD),
        config.useCuratedStrategySet ? "true" : "false",
        strategyRegistry.GetDescriptorCount(),
        COrchestratorSymbolClassifier::GetInstrumentExecutionProfileName(firstSymbol),
        EAModeToString(config.eaMode),
        EAModeToString(effectiveMode),
        config.allowHybridAIStandalone ? "true" : "false",
        config.aiStandaloneMinConfidence,
        strategyRegistry.GetActiveIndicatorCount(),
        strategyRegistry.GetActiveAICount());
    }

    //--- was CEAOrchestrator::LogPositionLifecycleConfig
    static void LogPositionLifecycleConfig(const SOrchestratorConfig &config)
    {
        PrintFormat("[POSITION-LIFECYCLE] enabled=%s | breakeven_buffer_points=%.1f | trailing_distance_points=%.1f | trailing_step_points=%.1f",
        config.enablePositionLifecycleManager ? "true" : "false",
        config.lifecycleBreakevenBufferPoints,
        config.lifecycleTrailingDistancePoints,
        config.lifecycleTrailingStepPoints);
    }
};

#endif // CORE_ORCHESTRATION_ORCHESTRATOR_MODE_RESOLVER_MQH
