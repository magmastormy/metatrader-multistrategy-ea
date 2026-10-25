// Forward declarations for EAOrchestrator dependencies; breaks include cycles and cuts compile time.
#ifndef ORCHESTRATOR_FWD_MQH
#define ORCHESTRATOR_FWD_MQH

#include "../Utils/Enums.mqh"

// Core Management
class CEnterpriseStrategyManager;
class CUnifiedRiskManager;
class CPositionSizer;
class CTradeManager;
class CPerformanceAnalytics;
class CEnhancedErrorHandler;
class CUtilities;
class CMarketAnalysis;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionManager;
class CPositionLifecycleManager;
class CSafeMode;
class CFullMarginMode;
class CSpikeMonitor;

// Engine Registry
class CRegistryAggregator;
class CMathematicalEngineRegistry;
class CInstitutionalEngineRegistry;
class CDrawingManagerRegistry;
class CScanSchedulerRegistry;
class CNeuralNetRegistry;
class CFamilyStrategyWeightMatrix;
class CFourStateRegimeDetector;
class CDerivAssetProfiler;
class CMultiAssetProfiler;
class CVPINFilter;
class COrderFlowImbalanceEngine;
class CChartDrawingManager;
class CSessionWeightManager;

// Engines
class CTrendEngine;
class CStructureEngine;
class CLiquidityEngine;
class CVolatilityEngine;
class CRegimeEngine;

// Pipeline & Signals
class CUnifiedSignalPipeline;
class CTimeframeConsistency;
struct SignalFilterSettings;
struct SPipelineEvidenceSnapshot;

// Strategies
class IStrategy;
class IAIStrategy;
class CStrategyBase;
class CAIStrategyAdapter;
class CTransformerAIStrategyAdapter;
class CEnsembleAIStrategyAdapter;
class COnnxAIStrategyAdapter;
class CStrategyRegistry;

class CPythonBridge;
struct SPythonBridgeMetrics;

// Risk & Compounding
class CRiskTierManager;
class CCompoundingTierManager;

class CNeuralNetworkStrategy;
struct SNeuralNetConfig;

struct SConsensusDecisionContext;

class CStrategyHealthMonitor;

class CPythonBridge;
extern CPythonBridge* g_pythonBridge;
extern CEnterpriseStrategyManager* g_enterpriseManagers[];
extern string g_enterpriseManagerSymbols[];

// Global profiler access (initialized in EAOrchestrator)
class CMultiAssetProfiler;
extern CMultiAssetProfiler* g_multiAssetProfiler;

// GlobalDefs.mqh is auto-included so consumers of this header get the extern declarations
// AND their definitions.
#include "GlobalDefs.mqh"

#endif // ORCHESTRATOR_FWD_MQH