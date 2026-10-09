// Batch 145 - Single data-driven registration catalog
// ONE place declares every strategy the EA can register:
// - 12 indicator strategies (created in-process by a creator fn)
// - 5  AI adapters        (created through CStrategyFactory)
// ADD A STRATEGY (contract):
// 1. write the class file in the strategy source folder
// 2. add 3 anchored lines here, all tagged with the same
// CAT anchor comment (see the rows below)
// a) one #include            (section 1)
// b) one CATALOG_SIMPLE_CREATOR line (section 5)
// c) one CatalogAdd(...) row (section 7)
// REMOVE A STRATEGY: delete the 3 lines carrying its [CAT:] anchor.
// NOTE: each row carries the SEMANTIC slot pair only (Batch 147
// removed the legacy flagsIndex / policyIndex literals entirely):
// enable slot : siIndex      - the ENUM_STRATEGY_INDEX slot that
// actually writes.
// policy slot : siPolicyIndex - the StrategyConfigBuilder slot
// holding THIS strategy's own intrabar policy.
// Reader (CatalogEnableSlot) and writer (BuildStrategyFlags) now
// agree by construction, so every InpEnable* toggle controls its
// own strategy. The historical legacy divergence is gone.
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
#include "../../Strategies/LiquiditySweepStrategy.mqh"        // [CAT:Liquidity Sweep]
#include "../../Strategies/RangeCompressionBreakout.mqh"      // [CAT:Range Compression]

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
    int                   siIndex;              // enable-flag slot (ENUM_STRATEGY_INDEX); -1 = always on
    int                   siPolicyIndex;        // intrabar-policy slot (own StrategyConfigBuilder row); -1 = use fixedPolicy
    ENUM_INTRABAR_POLICY  fixedPolicy;          // used when the active policy slot < 0
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

CATALOG_SIMPLE_CREATOR(CatCreate_Momentum,             CSimpleMomentumStrategy)
CATALOG_SIMPLE_CREATOR(CatCreate_Trend,                CStrategyTrend)
CATALOG_SIMPLE_CREATOR(CatCreate_SupportResistance,    CStrategySupportResistance)
CATALOG_SIMPLE_CREATOR(CatCreate_Candlestick,          CStrategyCandlestick)
CATALOG_SIMPLE_CREATOR(CatCreate_MeanReversion,        CMeanReversionStrategy)
CATALOG_SIMPLE_CREATOR(CatCreate_VolatilityBreakout,   CVolatilityBreakoutStrategy)
CATALOG_SIMPLE_CREATOR(CatCreate_StatisticalArbitrage, CStatisticalArbitrageStrategy)
CATALOG_SIMPLE_CREATOR(CatCreate_FVGScalper,           CFVGScalperStrategy)
CATALOG_SIMPLE_CREATOR(CatCreate_TurtleSoup,           CTurtleSoupStrategy)
CATALOG_SIMPLE_CREATOR(CatCreate_BreakerBlock,         CBreakerBlockStrategy)
CATALOG_SIMPLE_CREATOR(CatCreate_NYOpenGap,            CNYOpenGapStrategy)
CATALOG_SIMPLE_CREATOR(CatCreate_AsianRangeBreak,      CAsianRangeBreakStrategy)
CATALOG_SIMPLE_CREATOR(CatCreate_LiquiditySweep,        CLiquiditySweepStrategy)
CATALOG_SIMPLE_CREATOR(CatCreate_RangeCompression,      CRangeCompressionBreakout)

//==================================================================//
// 6. ROW APPEND                                                     //
//==================================================================//
void CatalogAdd(const string name,
                const ENUM_CATALOG_KIND kind,
                const ENUM_CATALOG_AI aiKind,
                const string factoryName,
                const int siIndex,
                const int siPolicyIndex,
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
    g_strategyCatalog[i].siIndex              = siIndex;
    g_strategyCatalog[i].siPolicyIndex        = siPolicyIndex;
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
//    Each row carries its SEMANTIC slot pair (siIndex / siPolicyIndex).|
//    Batch 147 removed the legacy flagsIndex/policyIndex literals;  //
//    reader and writer now agree by construction.                   //
//==================================================================//
void BuildStrategyCatalog()
{
    if(g_strategyCatalogBuilt)
        return;

    //--- 12 indicator strategies (legacy if-chain order preserved) ---
    //    Each row carries its SEMANTIC slot pair only: siIndex (the slot
    //    BuildStrategyFlags writes) and siPolicyIndex (this strategy's own
    //    StrategyConfigBuilder intrabar-policy row). The legacy flagsIndex /
    //    policyIndex literals were removed in Batch 147.
    CatalogAdd("Momentum",              CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_MOMENTUM,              0,  INTRABAR_POLICY_OFF, 1.0, -1.0, STRATEGY_TIER_3, PERIOD_CURRENT, PRIMARY_ALPHA, TREND_CLUSTER,          true, false, "", "", CatCreate_Momentum);
    CatalogAdd("Trend",                 CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_TREND,                 1,  INTRABAR_POLICY_OFF, 1.2, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, TREND_CLUSTER,          true, false, "", "", CatCreate_Trend);
    CatalogAdd("Support/Resistance",    CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_SUPPORT_RESISTANCE,    2,  INTRABAR_POLICY_OFF, 1.5, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true, false, "", "", CatCreate_SupportResistance);
    CatalogAdd("Candlestick",           CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_CANDLESTICK,           4,  INTRABAR_POLICY_OFF, 1.5, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, false, "", "", CatCreate_Candlestick);
    CatalogAdd("Mean Reversion",        CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_MEAN_REVERSION,        7,  INTRABAR_POLICY_OFF, 1.8, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true, false, "", "", CatCreate_MeanReversion);
    CatalogAdd("Volatility Breakout",   CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_VOLATILITY_BREAKOUT,  8,  INTRABAR_POLICY_OFF, 2.0, -1.0, STRATEGY_TIER_1, PERIOD_CURRENT, PRIMARY_ALPHA, TREND_CLUSTER,          true, false, "", "", CatCreate_VolatilityBreakout);
    CatalogAdd("Statistical Arbitrage", CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_STATISTICAL_ARBITRAGE,22,  INTRABAR_POLICY_OFF, 1.8, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true,  true, "", "", CatCreate_StatisticalArbitrage);
    CatalogAdd("FVG Scalper",           CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_FVG_SCALPER,          21,  INTRABAR_POLICY_OFF, 1.8, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, false, "", "", CatCreate_FVGScalper);
    CatalogAdd("Turtle Soup",           CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_TURTLE_SOUP,          14,  INTRABAR_POLICY_OFF, 1.6, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, false, "", "", CatCreate_TurtleSoup);
    CatalogAdd("Breaker Block",         CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_BREAKER_BLOCK,        15,  INTRABAR_POLICY_OFF, 1.7, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, false, "", "", CatCreate_BreakerBlock);
    CatalogAdd("NY Open Gap",           CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_NY_OPEN_GAP,          16,  INTRABAR_POLICY_OFF, 1.3, -1.0, STRATEGY_TIER_3, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, false, "", "", CatCreate_NYOpenGap);
    CatalogAdd("Asian Range Break",     CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_ASIAN_RANGE_BREAK,    17,  INTRABAR_POLICY_OFF, 1.3, -1.0, STRATEGY_TIER_3, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, false, "", "", CatCreate_AsianRangeBreak);
    //    NOTE: Liquidity Sweep & Range Compression were previously only auxiliary engines in
    //    OrchestratorMathEngineHub. They now also vote in consensus (Batch 2026-08-14) following
    //    the exact pattern already used by FVG/Turtle/Breaker/NY/Asian: the SAME shared
    //    CStrategyRegistry is fed both by the legacy RegisterDefinition list (EAOrchestrator) and
    //    by this catalog's AutoRegisterStrategies -> RegisterStrategy.
    //    Batch 151: both own dedicated StrategyConfigBuilder rows (18/19). The old literals
    //    cross-wired them into Asian Range Break's row 17 / each other's rows, so a future
    //    policy change on one strategy would have silently leaked into its neighbour.
    CatalogAdd("Liquidity Sweep",       CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_LIQUIDITY_SWEEP,     18,  INTRABAR_POLICY_OFF, 1.5, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, false, "", "", CatCreate_LiquiditySweep);
    CatalogAdd("Range Compression",     CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_RANGE_COMPRESSION,   19,  INTRABAR_POLICY_OFF, 1.6, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, TREND_CLUSTER,          true, false, "", "", CatCreate_RangeCompression);

    //--- 5 AI adapters (created by CStrategyFactory, registered by the orchestrator) ---
    //    Both policy slots are -1: AI rows always resolve to fixedPolicy=LIVE.
    CatalogAdd("Neural Network AI", CAT_KIND_AI, CAT_AI_NEURAL_NET,    "Neural Network AI", -1, -1, INTRABAR_POLICY_LIVE, 0.0, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true, false, "", "nn_adapter_register_failed",            NULL);
    CatalogAdd("Transformer AI",    CAT_KIND_AI, CAT_AI_TRANSFORMER,   "Transformer AI",    -1, -1, INTRABAR_POLICY_LIVE, 0.0, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true, false, "", "transformer_adapter_register_failed",   NULL);
    CatalogAdd("Ensemble AI",       CAT_KIND_AI, CAT_AI_ENSEMBLE,      "Ensemble AI",       -1, -1, INTRABAR_POLICY_LIVE, 0.0, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true, false, "", "ensemble_adapter_register_failed",      NULL);
    CatalogAdd("ONNX AI",           CAT_KIND_AI, CAT_AI_ONNX,          "ONNX AI",           -1, -1, INTRABAR_POLICY_LIVE, 0.0,  2.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true, false, "", "onnx_adapter_register_failed",          NULL);
    CatalogAdd("Python Bridge AI",  CAT_KIND_AI, CAT_AI_PYTHON_BRIDGE, "Python Bridge AI",  -1, -1, INTRABAR_POLICY_LIVE, 0.0,  1.5, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true, false, "", "python_bridge_adapter_register_failed", NULL);

    g_strategyCatalogBuilt = true;
}

//==================================================================//
// 8. LOOKUPS / GATES / AUDIT                                        //
//==================================================================//

// Row index for a registration name, -1 when absent.
int CatalogFindByName(const string name)
{
    for(int i = 0; i < g_strategyCatalogCount; i++)
    {
        if(g_strategyCatalog[i].name == name)
            return i;
    }
    return -1;
}

// Symbol whitelist gate. Empty whitelist == every symbol allowed.
bool CatalogSymbolAllowed(const int i, const string symbol)
{
    if(i < 0 || i >= g_strategyCatalogCount)
        return false;
    if(g_strategyCatalog[i].allowedSymbols == "")
        return true;
    return (StringFind(g_strategyCatalog[i].allowedSymbols, symbol) >= 0);
}

// Active enable-flag slot for a row.
// Batch 147: the legacy flagsIndex literal was removed, so this
// returns siIndex unconditionally - the slot BuildStrategyFlags
// (the only writer of the flag vector) actually populates.
// Returns -1 for "always enabled".
int CatalogEnableSlot(const int i)
{
    if(i < 0 || i >= g_strategyCatalogCount)
        return -1;
    return g_strategyCatalog[i].siIndex;
}

// Active intrabar-policy slot for a row.
// Batch 147: the legacy policyIndex literal was removed; returns
// siPolicyIndex (this strategy's own StrategyConfigBuilder row).
// Returns -1 when the row should fall back to fixedPolicy.
int CatalogPolicySlot(const int i)
{
    if(i < 0 || i >= g_strategyCatalogCount)
        return -1;
    return g_strategyCatalog[i].siPolicyIndex;
}

// Removed in Batch 147: CatalogFlagEnabled (legacy dual-scheme gate) is no
// longer used - AutoRegisterStrategies reads flags[CatalogEnableSlot(i)] directly.

// Report the active slot scheme and per-row resolution.
// Batch 147: the legacy scheme was removed, so this logs SEMANTIC
// only. Reader (CatalogEnableSlot) and writer (BuildStrategyFlags)
// agree by construction - no drift is possible.
void CatalogLogIndexAudit()
{
    PrintFormat("[CATALOG-AUDIT] slot_scheme=SEMANTIC (legacy literals removed in Batch 147)");

    for(int i = 0; i < g_strategyCatalogCount; i++)
    {
        if(g_strategyCatalog[i].kind != CAT_KIND_INDICATOR)
            continue;
        PrintFormat("[CATALOG-AUDIT] %s enable_slot=%d policy_slot=%d",
                    g_strategyCatalog[i].name,
                    g_strategyCatalog[i].siIndex,
                    g_strategyCatalog[i].siPolicyIndex);
    }
}

#endif // CORE_STRATEGY_STRATEGY_CATALOG_MQH
