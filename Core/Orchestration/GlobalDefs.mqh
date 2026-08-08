//+------------------------------------------------------------------+
//| GlobalDefs.mqh                                                   |
//| Shared global variable definitions for all .mq5 compilation units |
//| Declared extern in OrchestratorFwd.mqh                            |
//| Each .mq5 must include this to get actual definitions              |
//+------------------------------------------------------------------+

#ifndef GLOBAL_DEFS_MQH
#define GLOBAL_DEFS_MQH

// Forward declarations for types used in global definitions
class CPythonBridge;
class CMultiAssetProfiler;
class CEnterpriseStrategyManager;

//--- Global variable definitions (mirrors extern in OrchestratorFwd.mqh)
CPythonBridge* g_pythonBridge = NULL;
CMultiAssetProfiler* g_multiAssetProfiler = NULL;
CEnterpriseStrategyManager* g_enterpriseManagers[];
string g_enterpriseManagerSymbols[];

#endif // GLOBAL_DEFS_MQH
