//+------------------------------------------------------------------+
//| StrategyCatalog.mqh                                              |
//| Batch 145 - Single data-driven registration catalog              |
//|                                                                  |
//| ONE place declares every strategy the EA can register:           |
//|   - 12 indicator strategies (created in-process by a creator fn) |
//|   - 5  AI adapters        (created through CStrategyFactory)     |
//|                                                                  |
//| ADD A STRATEGY (contract):                                       |
//|   1. write the class file in the strategy source folder          |
//|   2. add 3 anchored lines here, all tagged with the same          |
//|      CAT anchor comment (see the rows below)                     |
//|        a) one #include            (section 1)                    |
//|        b) one CATALOG_SIMPLE_CREATOR line (section 5)            |
//|        c) one CatalogAdd(...) row (section 7)                    |
//| REMOVE A STRATEGY: delete the 3 lines carrying its [CAT:] anchor.|
//|                                                                  |
//| NOTE (Batch 145 invariant): flagsIndex holds the LEGACY literal  |
//| index used by the historical if-chain. For rows 5..12 it does    |
//| NOT match the semantic SI_* index; that divergence is preserved  |
//| byte-for-byte and only reported by CatalogLogIndexAudit().       |
//+------------------------------------------------------------------+
#ifndef CORE_STRATEGY_STRATEGY_CATALOG_MQH
#define CORE_STRATEGY_STRATEGY_CATALOG_MQH

#include "../Utils/Enums.mqh"
#include "../../Interfaces/IStrategy.mqh"

//==================================================================//
// 1. PER-STRATEGY INCLUDES (indicator strategies only; AI rows are  //
//    built by CStrategyFactory and need no concrete type here)      //
//==================================================================//
#include "../../Strategies/SimpleMomentumStrategy.mqh"       // [CAT:Momentum]
#include "../../Strategies/StrategyTrend.mqh"                // [CAT:Trend]
#include "../../Strategies/StrategySupportResistance.mqh"    // [CAT:Support/Resistance]
#include "../../Strategies/StrategyCandlestick.mqh"          // [CAT:Candlestick]
#include "../../Strategies/MeanReversionStrategy.mqh"        // [CAT:Mean Reversion]
#include "../../Strategies/VolatilityBreakoutStrategy.mqh"   // [CAT:Volatility Breakout]
#include "../../Strategies/StatisticalArbitrageStrategy.mqh" // [CAT:Statistical Arbitrage]
#include "../../Strategies/FVGScalperStrategy.mqh"           // [CAT:FVG Scalper]
#include "../../Strategies/TurtleSoupStrategy.mqh"           // [CAT:Turtle Soup]
#include "../../Strategies/BreakerBlockStrategy.mqh"         // [CAT:Breaker Block]
#include "../../Strategies/NYOpenGapStrategy.mqh"            // [CAT:NY Open Gap]
#include "../../Strategies/AsianRangeBreakStrategy.mqh"      // [CAT:Asian Range Break]

//==================================================================//
// 2. CATALOG ENUMS                                                  //
//==================================================================//
enum ENUM_CATALOG_KIND
{
    CAT_KIND_INDICATOR = 0,   // in-process strategy object (creator fn)
    CAT_KIND_AI        = 1    // AI adapter built by CStrategyFactory
};

enum ENUM_CATALOG_AI
{
    CAT_AI_NONE = 0,
    CAT_AI_NEURAL_NET,
    CAT_AI_TRANSFORMER,
    CAT_AI_ENSEMBLE,
    CAT_AI_ONNX,
    CAT_AI_PYTHON_BRIDGE
};

//==================================================================//
// 3. CATALOG ROW                                                    //
//==================================================================//
struct SStrategyDefinition
{
    string                name;                 // RegisterStrategy() name (identity key)
    ENUM_CATALOG_KIND     kind;                 // indicator vs AI adapter
    ENUM_CATALOG_AI       aiKind;               // which AI adapter (CAT_AI_NONE for indicators)
    string                factoryName;          // CStrategyFactory key (AI rows only)
    int                   flagsIndex;           // LEGACY enable-flag slot (-1 = always on)
    int                   siIndex;              // semantic ENUM_STRATEGY_INDEX slot (-1 = n/a)
    int                   policyIndex;          // GetIntrabarPolicyHelper() index (-1 = use fixedPolicy)
    ENUM_INTRABAR_POLICY  fixedPolicy;          // used when policyIndex < 0
    double                weight;               // registration weight (indicator rows)
    double                aiFallbackWeight;     // AI weight when registry lookup fails (<0 = multiplier)
    ENUM_STRATEGY_TIER    tier;
    ENUM_TIMEFRAMES       timeframe;
    ENUM_STRATEGY_ROLE    role;
    ENUM_STRATEGY_CLUSTER cluster;
    bool                  liveVoting;
    bool                  requiresPythonBridge; // hard gate: g_pythonBridge connected
    string                allowedSymbols;       // "" = every symbol
    string                failReason;           // MarkRegistered() reason on failure
};

//==================================================================//
// 4. CATALOG STORAGE                                                //
//==================================================================//
typedef IStrategy* (*StrategyCatalogCreator)();

SStrategyDefinition    g_strategyCatalog[];
StrategyCatalogCreator g_strategyCatalogCreators[];
int                    g_strategyCatalogCount = 0;
bool                   g_strategyCatalogBuilt = false;

//==================================================================//
// 5. CREATORS (one line per indicator strategy)                     //
//==================================================================//
#define CATALOG_SIMPLE_CREATOR(fn, ClassName) IStrategy* fn() { return new ClassName(); }

CATALOG_SIMPLE_CREATOR(CatCreate_Momentum,             CSimpleMomentumStrategy)      // [CAT:Momentum]
CATALOG_SIMPLE_CREATOR(CatCreate_Trend,                CStrategyTrend)               // [CAT:Trend]
CATALOG_SIMPLE_CREATOR(CatCreate_SupportResistance,    CStrategySupportResistance)   // [CAT:Support/Resistance]
CATALOG_SIMPLE_CREATOR(CatCreate_Candlestick,          CStrategyCandlestick)         // [CAT:Candlestick]
CATALOG_SIMPLE_CREATOR(CatCreate_MeanReversion,        CMeanReversionStrategy)       // [CAT:Mean Reversion]
CATALOG_SIMPLE_CREATOR(CatCreate_VolatilityBreakout,   CVolatilityBreakoutStrategy)  // [CAT:Volatility Breakout]
CATALOG_SIMPLE_CREATOR(CatCreate_StatisticalArbitrage, CStatisticalArbitrageStrategy)// [CAT:Statistical Arbitrage]
CATALOG_SIMPLE_CREATOR(CatCreate_FVGScalper,           CFVGScalperStrategy)          // [CAT:FVG Scalper]
CATALOG_SIMPLE_CREATOR(CatCreate_TurtleSoup,           CTurtleSoupStrategy)          // [CAT:Turtle Soup]
CATALOG_SIMPLE_CREATOR(CatCreate_BreakerBlock,         CBreakerBlockStrategy)        // [CAT:Breaker Block]
CATALOG_SIMPLE_CREATOR(CatCreate_NYOpenGap,            CNYOpenGapStrategy)           // [CAT:NY Open Gap]
CATALOG_SIMPLE_CREATOR(CatCreate_AsianRangeBreak,      CAsianRangeBreakStrategy)     // [CAT:Asian Range Break]

//==================================================================//
// 6. ROW APPEND                                                     //
//==================================================================//
void CatalogAdd(const string name,
                const ENUM_CATALOG_KIND kind,
                const ENUM_CATALOG_AI aiKind,
                const string factoryName,
                const int flagsIndex,
                const int siIndex,
                const int policyIndex,
                const ENUM_INTRABAR_POLICY fixedPolicy,
                const double weight,
                const double aiFallbackWeight,
                const ENUM_STRATEGY_TIER tier,
                const ENUM_TIMEFRAMES timeframe,
                const ENUM_STRATEGY_ROLE role,
                const ENUM_STRATEGY_CLUSTER cluster,
                const bool liveVoting,
                const bool requiresPythonBridge,
                const string allowedSymbols,
                const string failReason,
                StrategyCatalogCreator creator)
{
    const int newSize = g_strategyCatalogCount + 1;
    if(ArrayResize(g_strategyCatalog, newSize) != newSize)
    {
        PrintFormat("[CATALOG] ArrayResize failed for catalog row %s", name);
        return;
    }
    if(ArrayResize(g_strategyCatalogCreators, newSize) != newSize)
    {
        PrintFormat("[CATALOG] ArrayResize failed for creator row %s", name);
        return;
    }

    const int i = g_strategyCatalogCount;
    g_strategyCatalog[i].name                 = name;
    g_strategyCatalog[i].kind                 = kind;
    g_strategyCatalog[i].aiKind               = aiKind;
    g_strategyCatalog[i].factoryName          = factoryName;
    g_strategyCatalog[i].flagsIndex           = flagsIndex;
    g_strategyCatalog[i].siIndex              = siIndex;
    g_strategyCatalog[i].policyIndex          = policyIndex;
    g_strategyCatalog[i].fixedPolicy          = fixedPolicy;
    g_strategyCatalog[i].weight               = weight;
    g_strategyCatalog[i].aiFallbackWeight     = aiFallbackWeight;
    g_strategyCatalog[i].tier                 = tier;
    g_strategyCatalog[i].timeframe            = timeframe;
    g_strategyCatalog[i].role                 = role;
    g_strategyCatalog[i].cluster              = cluster;
    g_strategyCatalog[i].liveVoting           = liveVoting;
    g_strategyCatalog[i].requiresPythonBridge = requiresPythonBridge;
    g_strategyCatalog[i].allowedSymbols       = allowedSymbols;
    g_strategyCatalog[i].failReason           = failReason;
    g_strategyCatalogCreators[i]              = creator;

    g_strategyCatalogCount++;
}

//==================================================================//
// 7. CATALOG DEFINITION (17 rows: 12 indicator + 5 AI)              //
//    Values below are byte-identical to the pre-Batch-145           //
//    RegisterStrategy() call sites. Do not "tidy" them.             //
//==================================================================//
void BuildStrategyCatalog()
{
    if(g_strategyCatalogBuilt)
        return;

    //--- 12 indicator strategies (legacy if-chain order preserved) ---
    CatalogAdd("Momentum",              CAT_KIND_INDICATOR, CAT_AI_NONE, "",  0, SI_MOMENTUM,              0, INTRABAR_POLICY_OFF, 1.0, -1.0, STRATEGY_TIER_3, PERIOD_CURRENT, PRIMARY_ALPHA, TREND_CLUSTER,          true, false, "", "", CatCreate_Momentum);             // [CAT:Momentum]
    CatalogAdd("Trend",                 CAT_KIND_INDICATOR, CAT_AI_NONE, "",  1, SI_TREND,                 1, INTRABAR_POLICY_OFF, 1.2, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, TREND_CLUSTER,          true, false, "", "", CatCreate_Trend);                // [CAT:Trend]
    CatalogAdd("Support/Resistance",    CAT_KIND_INDICATOR, CAT_AI_NONE, "",  4, SI_SUPPORT_RESISTANCE,    4, INTRABAR_POLICY_OFF, 1.5, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true, false, "", "", CatCreate_SupportResistance);    // [CAT:Support/Resistance]
    CatalogAdd("Candlestick",           CAT_KIND_INDICATOR, CAT_AI_NONE, "",  6, SI_CANDLESTICK,           6, INTRABAR_POLICY_OFF, 1.5, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, false, "", "", CatCreate_Candlestick);          // [CAT:Candlestick]
    CatalogAdd("Mean Reversion",        CAT_KIND_INDICATOR, CAT_AI_NONE, "",  9, SI_MEAN_REVERSION,        9, INTRABAR_POLICY_OFF, 1.8, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true, false, "", "", CatCreate_MeanReversion);        // [CAT:Mean Reversion]
    CatalogAdd("Volatility Breakout",   CAT_KIND_INDICATOR, CAT_AI_NONE, "", 10, SI_VOLATILITY_BREAKOUT,  10, INTRABAR_POLICY_OFF, 2.0, -1.0, STRATEGY_TIER_1, PERIOD_CURRENT, PRIMARY_ALPHA, TREND_CLUSTER,          true, false, "", "", CatCreate_VolatilityBreakout);   // [CAT:Volatility Breakout]
    CatalogAdd("Statistical Arbitrage", CAT_KIND_INDICATOR, CAT_AI_NONE, "", 11, SI_STATISTICAL_ARBITRAGE,11, INTRABAR_POLICY_OFF, 1.8, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true,  true, "", "", CatCreate_StatisticalArbitrage); // [CAT:Statistical Arbitrage]
    CatalogAdd("FVG Scalper",           CAT_KIND_INDICATOR, CAT_AI_NONE, "", 12, SI_FVG_SCALPER,          12, INTRABAR_POLICY_OFF, 1.8, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, false, "", "", CatCreate_FVGScalper);           // [CAT:FVG Scalper]
    CatalogAdd("Turtle Soup",           CAT_KIND_INDICATOR, CAT_AI_NONE, "", 13, SI_TURTLE_SOUP,          13, INTRABAR_POLICY_OFF, 1.6, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, false, "", "", CatCreate_TurtleSoup);           // [CAT:Turtle Soup]
    CatalogAdd("Breaker Block",         CAT_KIND_INDICATOR, CAT_AI_NONE, "", 14, SI_BREAKER_BLOCK,        14, INTRABAR_POLICY_OFF, 1.7, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, false, "", "", CatCreate_BreakerBlock);         // [CAT:Breaker Block]
    CatalogAdd("NY Open Gap",           CAT_KIND_INDICATOR, CAT_AI_NONE, "", 15, SI_NY_OPEN_GAP,          15, INTRABAR_POLICY_OFF, 1.3, -1.0, STRATEGY_TIER_3, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, false, "", "", CatCreate_NYOpenGap);            // [CAT:NY Open Gap]
    CatalogAdd("Asian Range Break",     CAT_KIND_INDICATOR, CAT_AI_NONE, "", 16, SI_ASIAN_RANGE_BREAK,    16, INTRABAR_POLICY_OFF, 1.3, -1.0, STRATEGY_TIER_3, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, false, "", "", CatCreate_AsianRangeBreak);      // [CAT:Asian Range Break]

    //--- 5 AI adapters (created by CStrategyFactory, registered by the orchestrator) ---
    CatalogAdd("Neural Network AI", CAT_KIND_AI, CAT_AI_NEURAL_NET,    "Neural Network AI", -1, -1, -1, INTRABAR_POLICY_LIVE, 0.0, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true, false, "", "nn_adapter_register_failed",            NULL); // [CAT:Neural Network AI]
    CatalogAdd("Transformer AI",    CAT_KIND_AI, CAT_AI_TRANSFORMER,   "Transformer AI",    -1, -1, -1, INTRABAR_POLICY_LIVE, 0.0, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true, false, "", "transformer_adapter_register_failed",   NULL); // [CAT:Transformer AI]
    CatalogAdd("Ensemble AI",       CAT_KIND_AI, CAT_AI_ENSEMBLE,      "Ensemble AI",       -1, -1, -1, INTRABAR_POLICY_LIVE, 0.0, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true, false, "", "ensemble_adapter_register_failed",      NULL); // [CAT:Ensemble AI]
    CatalogAdd("ONNX AI",           CAT_KIND_AI, CAT_AI_ONNX,          "ONNX AI",           -1, -1, -1, INTRABAR_POLICY_LIVE, 0.0,  2.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true, false, "", "onnx_adapter_register_failed",          NULL); // [CAT:ONNX AI]
    CatalogAdd("Python Bridge AI",  CAT_KIND_AI, CAT_AI_PYTHON_BRIDGE, "Python Bridge AI",  -1, -1, -1, INTRABAR_POLICY_LIVE, 0.0,  1.5, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true, false, "", "python_bridge_adapter_register_failed", NULL); // [CAT:Python Bridge AI]

    g_strategyCatalogBuilt = true;
}

//==================================================================//
// 8. LOOKUPS / GATES / AUDIT                                        //
//==================================================================//

//+------------------------------------------------------------------+
//| Row index for a registration name, -1 when absent.               |
//+------------------------------------------------------------------+
int CatalogFindByName(const string name)
{
    for(int i = 0; i < g_strategyCatalogCount; i++)
    {
        if(g_strategyCatalog[i].name == name)
            return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Symbol whitelist gate. Empty whitelist == every symbol allowed.  |
//+------------------------------------------------------------------+
bool CatalogSymbolAllowed(const int i, const string symbol)
{
    if(i < 0 || i >= g_strategyCatalogCount)
        return false;
    if(g_strategyCatalog[i].allowedSymbols == "")
        return true;
    return (StringFind(g_strategyCatalog[i].allowedSymbols, symbol) >= 0);
}

//+------------------------------------------------------------------+
//| Legacy enable-flag gate. flagsIndex < 0 means "always enabled".  |
//+------------------------------------------------------------------+
bool CatalogFlagEnabled(const int i, const bool &flags[])
{
    if(i < 0 || i >= g_strategyCatalogCount)
        return false;
    const int fi = g_strategyCatalog[i].flagsIndex;
    if(fi < 0)
        return true;
    return (fi < ArraySize(flags) && flags[fi]);
}

//+------------------------------------------------------------------+
//| Audit-only: report legacy flag slot vs semantic SI_* slot drift. |
//| Reports, never repairs - the remap is a deferred user decision.  |
//+------------------------------------------------------------------+
void CatalogLogIndexAudit()
{
    for(int i = 0; i < g_strategyCatalogCount; i++)
    {
        const int fi = g_strategyCatalog[i].flagsIndex;
        const int si = g_strategyCatalog[i].siIndex;
        if(fi < 0 || si < 0 || fi == si)
            continue;

        PrintFormat("[CATALOG-AUDIT] %s legacy_flags_index=%d semantic_si_index=%d MISMATCH",
                    g_strategyCatalog[i].name, fi, si);

        if(fi == 15 || fi == 16)
            PrintFormat("[CATALOG-AUDIT] %s DEAD_SLOT legacy_flags_index=%d is never populated - strategy can never register",
                        g_strategyCatalog[i].name, fi);
    }
}

#endif // CORE_STRATEGY_STRATEGY_CATALOG_MQH
