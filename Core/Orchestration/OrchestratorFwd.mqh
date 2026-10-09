// Orchestrator Forward Declarations - Enterprise Grade
// Forward declarations for EAOrchestrator dependencies
// Use this header to break include cycles and reduce compile time
#ifndef ORCHESTRATOR_FWD_MQH
#define ORCHESTRATOR_FWD_MQH

// Core system enums
#include "../Utils/Enums.mqh"

// Forward Declarations - Core Management
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
class CIntelligentSLGuard;
class CTickSafetyMonitor;
class CSpikeMonitor;

// Forward Declarations - Engine Registry
class CRegistryAggregator;
class CMathematicalEngineRegistry;
class CInstitutionalEngineRegistry;
class CDrawingManagerRegistry;
class CScanSchedulerRegistry;
class CSymbolStateTracker;
class CNeuralNetRegistry;
class CFamilyStrategyWeightMatrix;
class CFourStateRegimeDetector;
class CDerivAssetProfiler;
class CMultiAssetProfiler;
class CVPINFilter;
class COrderFlowImbalanceEngine;
class CChartDrawingManager;
class CSessionWeightManager;
class CSymbolScanScheduler;

// Forward Declarations - Engines
class CTrendEngine;
class CStructureEngine;
class CLiquidityEngine;
class CVolatilityEngine;
class CRegimeEngine;

// Forward Declarations - Pipeline & Signals
class CUnifiedSignalPipeline;
class CTimeframeConsistency;
struct SignalFilterSettings;
struct SPipelineEvidenceSnapshot;

// Forward Declarations - Strategies
class IStrategy;
class IAIStrategy;
class CStrategyBase;
class CAIStrategyAdapter;
class CTransformerAIStrategyAdapter;
class CEnsembleAIStrategyAdapter;
class COnnxAIStrategyAdapter;
class CStrategyRegistry;

// Forward Declarations - Python Bridge
class CPythonBridge;
struct SPythonBridgeMetrics;

// Forward Declarations - Risk & Compounding
class CRiskTierManager;
class CCompoundingTierManager;

// Forward Declarations - Neural Network
class CNeuralNetworkStrategy;
struct SNeuralNetConfig;

// Forward Declarations - Consensus
struct SConsensusDecisionContext;

// Forward Declarations - Diagnostics & Health
class CStrategyHealthMonitor;

// External References
class CPythonBridge;
extern CPythonBridge* g_pythonBridge;
extern CEnterpriseStrategyManager* g_enterpriseManagers[];
extern string g_enterpriseManagerSymbols[];

// Global profiler access (initialized in EAOrchestrator)
class CMultiAssetProfiler;
extern CMultiAssetProfiler* g_multiAssetProfiler;

// Auto-include definitions so that any file including this header
// gets both the extern declarations AND the actual definitions
#include "GlobalDefs.mqh"

#endif // ORCHESTRATOR_FWD_MQH