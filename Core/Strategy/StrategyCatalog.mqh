// One row per strategy the EA can register: 14 indicator + 5 AI adapters.
// ADD: class file + the three [CAT:] anchored lines here (include, creator, CatalogAdd row).
// REMOVE: delete the three lines carrying that [CAT:] anchor.
// Row names must match EAOrchestrator's CStrategyRegistry definitions; an unmatched row is forced disabled.
// CatalogEnableSlot reads the siIndex slot BuildStrategyFlags writes, so InpEnable* toggles cannot drift.
#ifndef CORE_STRATEGY_STRATEGY_CATALOG_MQH
#define CORE_STRATEGY_STRATEGY_CATALOG_MQH

#include "../Utils/Enums.mqh"
#include "../../Interfaces/IStrategy.mqh"

// 1. Per-strategy includes (indicator rows only; AI adapters are built by CStrategyFactory, no concrete type here)
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

// 2. Catalog enums
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

// 3. Catalog row
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
    bool                  curatedEnable;        // joins the curated force-enable roster
    bool                  requiresPythonBridge; // hard gate: g_pythonBridge connected
    string                allowedSymbols;       // "" = every symbol
    string                failReason;           // MarkRegistered() reason on failure
    int                   registryType;         // ENUM_STRATEGY_TYPE for the registry definition; -1 = none
};

// 4. Catalog storage
typedef IStrategy* (*StrategyCatalogCreator)();

SStrategyDefinition    g_strategyCatalog[];
StrategyCatalogCreator g_strategyCatalogCreators[];
int                    g_strategyCatalogCount = 0;
bool                   g_strategyCatalogBuilt = false;

// 5. Creators (one line per indicator strategy)
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

// 6. Row append
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
                const bool curatedEnable,
                const bool requiresPythonBridge,
                const string allowedSymbols,
                const string failReason,
                StrategyCatalogCreator creator,
                const int registryType)
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
    g_strategyCatalog[i].curatedEnable        = curatedEnable;
    g_strategyCatalog[i].requiresPythonBridge = requiresPythonBridge;
    g_strategyCatalog[i].allowedSymbols       = allowedSymbols;
    g_strategyCatalog[i].failReason           = failReason;
    g_strategyCatalogCreators[i]              = creator;
    g_strategyCatalog[i].registryType         = registryType;

    g_strategyCatalogCount++;
}

// 7. Catalog definition: 14 indicator rows + 5 AI rows
void BuildStrategyCatalog()
{
    if(g_strategyCatalogBuilt)
        return;

    CatalogAdd("Momentum",              CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_MOMENTUM,              0,  INTRABAR_POLICY_OFF, 1.0, -1.0, STRATEGY_TIER_3, PERIOD_CURRENT, PRIMARY_ALPHA, TREND_CLUSTER,          true, true, false, "", "", CatCreate_Momentum, STRATEGY_MOMENTUM);
    CatalogAdd("Trend",                 CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_TREND,                 1,  INTRABAR_POLICY_OFF, 1.2, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, TREND_CLUSTER,          true, true, false, "", "", CatCreate_Trend, STRATEGY_TREND);
    CatalogAdd("Support/Resistance",    CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_SUPPORT_RESISTANCE,    2,  INTRABAR_POLICY_OFF, 1.5, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true, true, false, "", "", CatCreate_SupportResistance, STRATEGY_SUPPORT_RESISTANCE);
    CatalogAdd("Candlestick",           CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_CANDLESTICK,           4,  INTRABAR_POLICY_OFF, 1.5, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, false, false, "", "", CatCreate_Candlestick, STRATEGY_CANDLESTICK);
    CatalogAdd("Mean Reversion",        CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_MEAN_REVERSION,        7,  INTRABAR_POLICY_OFF, 1.8, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true, true, false, "", "", CatCreate_MeanReversion, STRATEGY_MEAN_REVERSION);
    CatalogAdd("Volatility Breakout",   CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_VOLATILITY_BREAKOUT,  8,  INTRABAR_POLICY_OFF, 2.0, -1.0, STRATEGY_TIER_1, PERIOD_CURRENT, PRIMARY_ALPHA, TREND_CLUSTER,          true, true, false, "", "", CatCreate_VolatilityBreakout, STRATEGY_VOLATILITY_BREAKOUT);
    CatalogAdd("Statistical Arbitrage", CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_STATISTICAL_ARBITRAGE,22,  INTRABAR_POLICY_OFF, 1.8, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, MEAN_REVERSION_CLUSTER, true, false,  true, "", "", CatCreate_StatisticalArbitrage, STRATEGY_STATISTICAL_ARBITRAGE);
    CatalogAdd("FVG Scalper",           CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_FVG_SCALPER,          21,  INTRABAR_POLICY_OFF, 1.8, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, true, false, "", "", CatCreate_FVGScalper, STRATEGY_FVG_SCALPER);
    CatalogAdd("Turtle Soup",           CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_TURTLE_SOUP,          14,  INTRABAR_POLICY_OFF, 1.6, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, true, false, "", "", CatCreate_TurtleSoup, STRATEGY_TURTLE_SOUP);
    CatalogAdd("Breaker Block",         CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_BREAKER_BLOCK,        15,  INTRABAR_POLICY_OFF, 1.7, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, true, false, "", "", CatCreate_BreakerBlock, STRATEGY_BREAKER_BLOCK);
    CatalogAdd("NY Open Gap",           CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_NY_OPEN_GAP,          16,  INTRABAR_POLICY_OFF, 1.3, -1.0, STRATEGY_TIER_3, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, true, false, "", "", CatCreate_NYOpenGap, STRATEGY_NY_OPEN_GAP);
    CatalogAdd("Asian Range Break",     CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_ASIAN_RANGE_BREAK,    17,  INTRABAR_POLICY_OFF, 1.3, -1.0, STRATEGY_TIER_3, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, true, false, "", "", CatCreate_AsianRangeBreak, STRATEGY_ASIAN_RANGE_BREAK);
    // siPolicyIndex must be the row's OWN StrategyConfigBuilder slot: two rows sharing a slot inherit the same policy.
    CatalogAdd("Liquidity Sweep",       CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_LIQUIDITY_SWEEP,     18,  INTRABAR_POLICY_OFF, 1.5, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRUCTURE_CLUSTER,      true, true, false, "", "", CatCreate_LiquiditySweep, STRATEGY_LIQUIDITY_SWEEP);
    CatalogAdd("Range Compression",     CAT_KIND_INDICATOR, CAT_AI_NONE, "",  SI_RANGE_COMPRESSION,   19,  INTRABAR_POLICY_OFF, 1.6, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, TREND_CLUSTER,          true, true, false, "", "", CatCreate_RangeCompression, STRATEGY_RANGE_COMPRESSION);

    //--- 5 AI adapters: created by CStrategyFactory and registered by the orchestrator, not by AutoRegisterStrategies ---
    //    Both slots are -1, so AI rows always resolve to fixedPolicy = LIVE.
    CatalogAdd("Neural Network AI", CAT_KIND_AI, CAT_AI_NEURAL_NET,    "Neural Network AI", -1, -1, INTRABAR_POLICY_LIVE, 0.0, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true, false, false, "", "nn_adapter_register_failed",            NULL, -1);
    CatalogAdd("Transformer AI",    CAT_KIND_AI, CAT_AI_TRANSFORMER,   "Transformer AI",    -1, -1, INTRABAR_POLICY_LIVE, 0.0, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true, false, false, "", "transformer_adapter_register_failed",   NULL, -1);
    CatalogAdd("Ensemble AI",       CAT_KIND_AI, CAT_AI_ENSEMBLE,      "Ensemble AI",       -1, -1, INTRABAR_POLICY_LIVE, 0.0, -1.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true, false, false, "", "ensemble_adapter_register_failed",      NULL, -1);
    CatalogAdd("ONNX AI",           CAT_KIND_AI, CAT_AI_ONNX,          "ONNX AI",           -1, -1, INTRABAR_POLICY_LIVE, 0.0,  2.0, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true, false, false, "", "onnx_adapter_register_failed",          NULL, -1);
    CatalogAdd("Python Bridge AI",  CAT_KIND_AI, CAT_AI_PYTHON_BRIDGE, "Python Bridge AI",  -1, -1, INTRABAR_POLICY_LIVE, 0.0,  1.5, STRATEGY_TIER_2, PERIOD_CURRENT, PRIMARY_ALPHA, STRATEGY_CLUSTER_NONE, true, false, false, "", "python_bridge_adapter_register_failed", NULL, -1);

    g_strategyCatalogBuilt = true;
}

// 8. Lookups / gates / audit

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

// Enable slot (siIndex); -1 = always enabled, and an out-of-range row also resolves to -1.
int CatalogEnableSlot(const int i)
{
    if(i < 0 || i >= g_strategyCatalogCount)
        return -1;
    return g_strategyCatalog[i].siIndex;
}

// curated roster rather than being switched on by an accident of array order.
bool CatalogCuratedEnable(const int i)
{
    if(i < 0 || i >= g_strategyCatalogCount)
        return false;
    return g_strategyCatalog[i].curatedEnable;
}

// Consensus reads the row weight through GetStrategyWeight(), so the operator's InpWeight* has to land
// here before any manager registers; a row that keeps its code default from an input is a dead knob.
void CatalogApplyConfigWeight(const int siIndex, const double weight)
{
    if(siIndex < 0 || weight < 0.0)
        return;

    for(int i = 0; i < g_strategyCatalogCount; i++)
    {
        if(g_strategyCatalog[i].kind != CAT_KIND_INDICATOR || g_strategyCatalog[i].siIndex != siIndex)
            continue;
        if(MathAbs(g_strategyCatalog[i].weight - weight) > 0.0001)
        {
            PrintFormat("[CATALOG] %s | registration weight %.2f -> %.2f from operator input",
                        g_strategyCatalog[i].name, g_strategyCatalog[i].weight, weight);
            g_strategyCatalog[i].weight = weight;
        }
        return;
    }
    PrintFormat("[CATALOG] weight input for siIndex %d has no indicator row - the value reaches nothing", siIndex);
}

// Policy slot (siPolicyIndex); -1 = the row falls back to its fixedPolicy.
int CatalogPolicySlot(const int i)
{
    if(i < 0 || i >= g_strategyCatalogCount)
        return -1;
    return g_strategyCatalog[i].siPolicyIndex;
}

// Contributor strings come from CStrategyMgrRoster::GetStrategyName(), which is the row name, so a
// contributor's class is a fact about its row. Token lists copied from those names drift the moment a
// row is added or renamed - six indicator rows and one AI row were unreadable that way.
int CatalogRowOfContributor(const string contributorName)
{
    if(contributorName == "")
        return -1;
    for(int i = 0; i < g_strategyCatalogCount; i++)
        if(StringFind(contributorName, g_strategyCatalog[i].name) >= 0)
            return i;
    return -1;
}

bool CatalogContributorIsIndicator(const string contributorName)
{
    int row = CatalogRowOfContributor(contributorName);
    return (row >= 0 && g_strategyCatalog[row].kind == CAT_KIND_INDICATOR);
}

bool CatalogContributorIsAI(const string contributorName)
{
    int row = CatalogRowOfContributor(contributorName);
    return (row >= 0 && g_strategyCatalog[row].kind == CAT_KIND_AI);
}

bool CatalogContributorIsAIKind(const string contributorName, const ENUM_CATALOG_AI aiKind)
{
    int row = CatalogRowOfContributor(contributorName);
    return (row >= 0 && g_strategyCatalog[row].aiKind == aiKind);
}


// Report-only audit: prints the resolved slot pair for each indicator row.
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
