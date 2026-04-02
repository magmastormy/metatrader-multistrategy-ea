# AXIOM EA — Strategy Plugin System Spec
> **Document Type:** Codex Implementation Spec — Doc 2 of 3  
> **Scope:** Modular strategy registration, optional vs mandatory, AI/indicator mode flags, single-strategy operation  
> **Read this entire document before touching any file.**

---

## THE PROBLEM IN PLAIN TERMS

Right now the EA has these strategies:
- `CStrategyUnifiedICT` (ICT)
- `CStrategySupportResistance` (S/R + Trendlines)
- `CStrategyTrend` (Multi-EMA)
- `CStrategyCandlestick` (Patterns)
- `CStrategyFibonacci` (Fib)
- `CNeuralNetworkStrategy` (Simple NN)
- `CNextGenStrategyBrain` (Transformer)

**You cannot tell which ones are active.** The EA instantiates all of them, initializes all of them in a chain, and then the signal aggregator just calls `GetSignal()` on all of them and combines results. If a strategy fails init it silently stops contributing — but nothing tells you that. If you want to run with only the ICT strategy, you have to comment out code.

There is also no concept of "AI mode" vs "indicator mode" vs "hybrid." The AI and indicator strategies live in the same list and are treated identically.

---

## WHAT THIS DOCUMENT BUILDS

1. A `CStrategyRegistry` — the single place strategies are registered, enabled, and queried
2. An `ENUM_EA_MODE` — controls whether AI, indicators, or both are active
3. A clean `IStrategy` interface with mandatory vs optional classification
4. A visible active-status system — the dashboard and logs always show which strategies are actually running

---

## SECTION 1 — EA Mode Enum

### 1.1 Create `ENUM_EA_MODE` in `Core/Utils/Enums.mqh`

Add to the existing enums file:

```cpp
//+------------------------------------------------------------------+
//| EA Operating Mode                                                |
//+------------------------------------------------------------------+
enum ENUM_EA_MODE
{
    EA_MODE_INDICATOR_ONLY,     // Only traditional indicator strategies (ICT, S/R, Trend, etc.)
    EA_MODE_AI_ONLY,            // Only AI strategies (NN or Transformer)
    EA_MODE_HYBRID,             // AI + Indicators combined (AI acts as filter or veto)
    EA_MODE_AI_ASSISTED,        // Indicator strategies run primary, AI adds confidence bonus
    EA_MODE_INDICATOR_FILTERED  // AI runs primary, indicators act as confirmation gate
};
```

### 1.2 Expose as an EA input parameter

In the main EA `.mq5` file, add as a user-configurable input:

```cpp
input ENUM_EA_MODE InpEAMode = EA_MODE_HYBRID;         // EA Operating Mode

// Per-strategy enable flags
input bool InpUseICT          = true;   // Enable ICT Strategy
input bool InpUseSR           = true;   // Enable S/R + Trendline Strategy
input bool InpUseTrend        = true;   // Enable Multi-EMA Trend Strategy
input bool InpUseCandlestick  = false;  // Enable Candlestick Pattern Strategy
input bool InpUseFibonacci    = false;  // Enable Fibonacci Strategy
input bool InpUseSimpleNN     = false;  // Enable Simple Neural Network
input bool InpUseTransformer  = false;  // Enable Transformer Brain (heavy, slower)
```

---

## SECTION 2 — Strategy Registry

### 2.1 Create `Core/Strategy/StrategyRegistry.mqh`

```cpp
#ifndef __STRATEGY_REGISTRY_MQH__
#define __STRATEGY_REGISTRY_MQH__

#include "IStrategy.mqh"

//+------------------------------------------------------------------+
//| Strategy Descriptor — metadata about each registered strategy    |
//+------------------------------------------------------------------+
struct SStrategyDescriptor
{
    string          name;           // Human-readable name
    ENUM_STRATEGY_TYPE type;        // Type enum
    bool            isAI;           // True = AI-powered (NN/Transformer)
    bool            isEnabled;      // User wants it active
    bool            isInitialized;  // Successfully initialized
    bool            isMandatory;    // EA cannot run without it (only TradeManager/RiskManager)
    double          weight;         // Signal weight in aggregation
    string          failReason;     // Why it failed init (empty = OK)

    SStrategyDescriptor()
    {
        name          = "";
        type          = STRATEGY_NONE;
        isAI          = false;
        isEnabled     = false;
        isInitialized = false;
        isMandatory   = false;
        weight        = 1.0;
        failReason    = "";
    }
};

//+------------------------------------------------------------------+
//| Strategy Registry Class                                          |
//+------------------------------------------------------------------+
class CStrategyRegistry
{
private:
    static const int MAX_STRATEGIES = 16;

    IStrategy*              m_strategies[MAX_STRATEGIES];
    SStrategyDescriptor     m_descriptors[MAX_STRATEGIES];
    int                     m_count;
    ENUM_EA_MODE            m_mode;
    string                  m_symbol;
    ENUM_TIMEFRAMES         m_timeframe;

public:
    CStrategyRegistry()
    {
        m_count     = 0;
        m_mode      = EA_MODE_HYBRID;
        m_symbol    = "";
        m_timeframe = PERIOD_CURRENT;

        for(int i = 0; i < MAX_STRATEGIES; i++)
            m_strategies[i] = NULL;
    }

    ~CStrategyRegistry()
    {
        // Strategies are owned externally; registry just holds references
        // Do NOT delete here unless registry owns them (document which it is)
    }

    void SetMode(ENUM_EA_MODE mode) { m_mode = mode; }
    void SetContext(const string symbol, ENUM_TIMEFRAMES tf) { m_symbol = symbol; m_timeframe = tf; }

    //------------------------------------------------------------------
    // Register a strategy with metadata
    //------------------------------------------------------------------
    bool Register(IStrategy* strategy,
                  const string name,
                  ENUM_STRATEGY_TYPE type,
                  bool isAI,
                  bool userEnabled,
                  bool isMandatory = false,
                  double weight    = 1.0)
    {
        if(m_count >= MAX_STRATEGIES)
        {
            Print("[REGISTRY] ERROR: Max strategies reached (", MAX_STRATEGIES, ")");
            return false;
        }
        if(strategy == NULL)
        {
            Print("[REGISTRY] ERROR: NULL strategy registered as '", name, "'");
            return false;
        }

        m_strategies[m_count]              = strategy;
        m_descriptors[m_count].name        = name;
        m_descriptors[m_count].type        = type;
        m_descriptors[m_count].isAI        = isAI;
        m_descriptors[m_count].isEnabled   = userEnabled;
        m_descriptors[m_count].isMandatory = isMandatory;
        m_descriptors[m_count].weight      = weight;
        m_descriptors[m_count].isInitialized = false;
        m_descriptors[m_count].failReason  = "Not yet initialized";
        m_count++;

        return true;
    }

    //------------------------------------------------------------------
    // Initialize all registered strategies
    //------------------------------------------------------------------
    bool InitializeAll(void* tradeMgr, void* posSizer)
    {
        bool mandatoryOK = true;

        for(int i = 0; i < m_count; i++)
        {
            SStrategyDescriptor &desc = m_descriptors[i];

            if(!desc.isEnabled)
            {
                desc.failReason = "Disabled by user";
                PrintFormat("[REGISTRY] SKIP: %s (disabled)", desc.name);
                continue;
            }

            // Mode filter: skip AI strategies in indicator-only mode
            if(m_mode == EA_MODE_INDICATOR_ONLY && desc.isAI)
            {
                desc.isEnabled  = false;
                desc.failReason = "AI disabled in current mode";
                PrintFormat("[REGISTRY] SKIP: %s (mode=INDICATOR_ONLY)", desc.name);
                continue;
            }

            // Mode filter: skip non-AI strategies in AI-only mode
            if(m_mode == EA_MODE_AI_ONLY && !desc.isAI)
            {
                desc.isEnabled  = false;
                desc.failReason = "Indicator disabled in current mode";
                PrintFormat("[REGISTRY] SKIP: %s (mode=AI_ONLY)", desc.name);
                continue;
            }

            bool ok = m_strategies[i].Init(m_symbol, m_timeframe, tradeMgr, posSizer);
            desc.isInitialized = ok;

            if(ok)
            {
                PrintFormat("[REGISTRY] OK: %s [%s] weight=%.1f",
                            desc.name, desc.isAI ? "AI" : "IND", desc.weight);
            }
            else
            {
                desc.failReason = "Init() returned false";
                PrintFormat("[REGISTRY] FAIL: %s — %s", desc.name, desc.failReason);

                if(desc.isMandatory)
                {
                    Print("[REGISTRY] FATAL: Mandatory strategy '", desc.name, "' failed init");
                    mandatoryOK = false;
                }
            }
        }

        PrintStatusTable();
        return mandatoryOK;
    }

    //------------------------------------------------------------------
    // Get active strategies of a given category
    //------------------------------------------------------------------
    int GetActiveIndicatorStrategies(IStrategy* &out[], int maxCount)
    {
        int found = 0;
        for(int i = 0; i < m_count && found < maxCount; i++)
        {
            if(m_descriptors[i].isEnabled &&
               m_descriptors[i].isInitialized &&
               !m_descriptors[i].isAI)
            {
                out[found++] = m_strategies[i];
            }
        }
        return found;
    }

    int GetActiveAIStrategies(IStrategy* &out[], int maxCount)
    {
        int found = 0;
        for(int i = 0; i < m_count && found < maxCount; i++)
        {
            if(m_descriptors[i].isEnabled &&
               m_descriptors[i].isInitialized &&
               m_descriptors[i].isAI)
            {
                out[found++] = m_strategies[i];
            }
        }
        return found;
    }

    int GetAllActiveStrategies(IStrategy* &out[], int maxCount)
    {
        int found = 0;
        for(int i = 0; i < m_count && found < maxCount; i++)
        {
            if(m_descriptors[i].isEnabled && m_descriptors[i].isInitialized)
                out[found++] = m_strategies[i];
        }
        return found;
    }

    //------------------------------------------------------------------
    // Status methods
    //------------------------------------------------------------------
    int GetActiveCount() const
    {
        int n = 0;
        for(int i = 0; i < m_count; i++)
            if(m_descriptors[i].isEnabled && m_descriptors[i].isInitialized) n++;
        return n;
    }

    bool HasAnyActive() const { return GetActiveCount() > 0; }

    bool IsStrategyActive(ENUM_STRATEGY_TYPE type) const
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_descriptors[i].type == type &&
               m_descriptors[i].isEnabled &&
               m_descriptors[i].isInitialized)
                return true;
        }
        return false;
    }

    double GetWeight(ENUM_STRATEGY_TYPE type) const
    {
        for(int i = 0; i < m_count; i++)
            if(m_descriptors[i].type == type) return m_descriptors[i].weight;
        return 1.0;
    }

    string GetStrategyName(ENUM_STRATEGY_TYPE type) const
    {
        for(int i = 0; i < m_count; i++)
            if(m_descriptors[i].type == type) return m_descriptors[i].name;
        return "Unknown";
    }

    //------------------------------------------------------------------
    // Runtime enable/disable
    //------------------------------------------------------------------
    bool EnableStrategy(ENUM_STRATEGY_TYPE type)
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_descriptors[i].type == type)
            {
                m_descriptors[i].isEnabled = true;
                PrintFormat("[REGISTRY] ENABLED: %s", m_descriptors[i].name);
                return true;
            }
        }
        return false;
    }

    bool DisableStrategy(ENUM_STRATEGY_TYPE type, const string reason = "Manual disable")
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_descriptors[i].type == type)
            {
                m_descriptors[i].isEnabled = false;
                m_descriptors[i].failReason = reason;
                PrintFormat("[REGISTRY] DISABLED: %s (%s)", m_descriptors[i].name, reason);
                return true;
            }
        }
        return false;
    }

    //------------------------------------------------------------------
    // Print status table to journal
    //------------------------------------------------------------------
    void PrintStatusTable() const
    {
        Print("=== STRATEGY REGISTRY STATUS ===");
        PrintFormat("  Mode: %s | Active: %d / %d",
                    EnumToString(m_mode), GetActiveCount(), m_count);
        Print("  ---");

        for(int i = 0; i < m_count; i++)
        {
            const SStrategyDescriptor &d = m_descriptors[i];
            string status = d.isInitialized ? (d.isEnabled ? " ACTIVE" : "DISABLED") : "  FAILED";
            string category = d.isAI ? "[AI ]" : "[IND]";
            string mandatory = d.isMandatory ? " *MANDATORY*" : "";

            PrintFormat("  %s %-30s %s w=%.1f  %s%s",
                        status, d.name, category, d.weight,
                        d.failReason != "" ? "(" + d.failReason + ")" : "",
                        mandatory);
        }

        Print("================================");
    }

    //------------------------------------------------------------------
    // Dashboard string (one-liner summary for chart display)
    //------------------------------------------------------------------
    string GetDashboardSummary() const
    {
        string line = StringFormat("Mode:%s | ", EnumToString(m_mode));
        int active = 0;

        for(int i = 0; i < m_count; i++)
        {
            if(m_descriptors[i].isEnabled && m_descriptors[i].isInitialized)
            {
                if(active > 0) line += " + ";
                line += m_descriptors[i].name;
                active++;
            }
        }

        if(active == 0) line += "NO STRATEGIES ACTIVE";
        return line;
    }

    void DeinitAll()
    {
        for(int i = 0; i < m_count; i++)
        {
            if(m_strategies[i] != NULL && m_descriptors[i].isInitialized)
                m_strategies[i].Deinit();
        }
    }
};

#endif // __STRATEGY_REGISTRY_MQH__
```

---

## SECTION 3 — Signal Aggregator Update

### 3.1 Mode-Aware Signal Aggregation

The signal aggregator (wherever `GetSignal()` is currently called across all strategies) must be rewritten to respect the mode. Replace the flat loop with a mode-aware version:

```cpp
ENUM_TRADE_SIGNAL CAggregatedSignal::Aggregate(
    CStrategyRegistry &registry,
    double &finalConfidence)
{
    finalConfidence = 0.0;
    ENUM_EA_MODE mode = registry.GetMode();

    // Collect indicator signals
    IStrategy* indStrategies[8];
    int indCount = registry.GetActiveIndicatorStrategies(indStrategies, 8);

    // Collect AI signals
    IStrategy* aiStrategies[4];
    int aiCount = registry.GetActiveAIStrategies(aiStrategies, 4);

    // Edge case: nothing active
    if(indCount == 0 && aiCount == 0)
        return TRADE_SIGNAL_NONE;

    switch(mode)
    {
        case EA_MODE_INDICATOR_ONLY:
            return AggregateIndicators(indStrategies, indCount, registry, finalConfidence);

        case EA_MODE_AI_ONLY:
            return AggregateAI(aiStrategies, aiCount, registry, finalConfidence);

        case EA_MODE_HYBRID:
        {
            // Both must agree on direction
            double indConf = 0, aiConf = 0;
            ENUM_TRADE_SIGNAL indSig = AggregateIndicators(indStrategies, indCount, registry, indConf);
            ENUM_TRADE_SIGNAL aiSig  = AggregateAI(aiStrategies, aiCount, registry, aiConf);

            if(indSig == TRADE_SIGNAL_NONE || aiSig == TRADE_SIGNAL_NONE)
                return TRADE_SIGNAL_NONE;
            if(indSig != aiSig)
                return TRADE_SIGNAL_NONE;  // Disagreement = no trade

            finalConfidence = (indConf * 0.6) + (aiConf * 0.4);  // Indicator-weighted
            return indSig;
        }

        case EA_MODE_AI_ASSISTED:
        {
            // Indicator is primary. AI adds confidence if it agrees.
            double indConf = 0, aiConf = 0;
            ENUM_TRADE_SIGNAL indSig = AggregateIndicators(indStrategies, indCount, registry, indConf);
            if(indSig == TRADE_SIGNAL_NONE) return TRADE_SIGNAL_NONE;

            ENUM_TRADE_SIGNAL aiSig = AggregateAI(aiStrategies, aiCount, registry, aiConf);
            finalConfidence = indConf + (aiSig == indSig ? aiConf * 0.20 : 0.0);
            finalConfidence = MathMin(1.0, finalConfidence);
            return indSig;
        }

        case EA_MODE_INDICATOR_FILTERED:
        {
            // AI is primary. Indicator must not disagree.
            double indConf = 0, aiConf = 0;
            ENUM_TRADE_SIGNAL aiSig = AggregateAI(aiStrategies, aiCount, registry, aiConf);
            if(aiSig == TRADE_SIGNAL_NONE) return TRADE_SIGNAL_NONE;

            ENUM_TRADE_SIGNAL indSig = AggregateIndicators(indStrategies, indCount, registry, indConf);
            if(indSig != TRADE_SIGNAL_NONE && indSig != aiSig)
                return TRADE_SIGNAL_NONE;  // Indicator veto

            finalConfidence = aiConf;
            return aiSig;
        }
    }

    return TRADE_SIGNAL_NONE;
}

// Helper: weighted vote among indicator strategies
ENUM_TRADE_SIGNAL AggregateIndicators(IStrategy* &strategies[], int count,
                                       CStrategyRegistry &registry, double &confidence)
{
    if(count == 0) return TRADE_SIGNAL_NONE;
    if(count == 1)
    {
        // Single strategy — just use its signal directly
        return strategies[0].GetSignal(confidence);
    }

    double buyScore  = 0, sellScore = 0, totalWeight = 0;

    for(int i = 0; i < count; i++)
    {
        double conf = 0;
        ENUM_TRADE_SIGNAL sig = strategies[i].GetSignal(conf);
        double w = registry.GetWeight(strategies[i].GetType());

        if(sig == TRADE_SIGNAL_BUY)  buyScore  += conf * w;
        if(sig == TRADE_SIGNAL_SELL) sellScore += conf * w;
        totalWeight += w;
    }

    if(totalWeight <= 0) return TRADE_SIGNAL_NONE;

    double buyNorm  = buyScore  / totalWeight;
    double sellNorm = sellScore / totalWeight;

    static const double MIN_CONSENSUS = 0.50;  // Majority must agree

    if(buyNorm  >= MIN_CONSENSUS && buyNorm  > sellNorm)
    { confidence = buyNorm;  return TRADE_SIGNAL_BUY; }
    if(sellNorm >= MIN_CONSENSUS && sellNorm > buyNorm)
    { confidence = sellNorm; return TRADE_SIGNAL_SELL; }

    return TRADE_SIGNAL_NONE;
}
```

---

## SECTION 4 — Main EA Setup — Registration

### 4.1 How to register all strategies in `OnInit()`

In the main EA file, replace the current piecemeal initialization with:

```cpp
// Declare registry and strategies as EA-level members
CStrategyRegistry  m_registry;
CStrategyUnifiedICT        m_stratICT;
CStrategySupportResistance m_stratSR;
CStrategyTrend             m_stratTrend;
CStrategyCandlestick       m_stratCandle;
CStrategyFibonacci         m_stratFib;
CNeuralNetworkStrategy     m_stratNN;
CNextGenStrategyBrain      m_stratTransformer;

int OnInit()
{
    m_registry.SetMode(InpEAMode);
    m_registry.SetContext(_Symbol, (ENUM_TIMEFRAMES)Period());

    // Register indicator strategies
    // Register(ptr, name, type, isAI, userEnabled, isMandatory, weight)
    m_registry.Register(&m_stratICT,         "ICT",         STRATEGY_UNIFIED_ICT,         false, InpUseICT,         false, 2.0);
    m_registry.Register(&m_stratSR,          "S/R+TL",      STRATEGY_SUPPORT_RESISTANCE,  false, InpUseSR,          false, 1.5);
    m_registry.Register(&m_stratTrend,       "Trend EMA",   STRATEGY_TREND,               false, InpUseTrend,       false, 1.5);
    m_registry.Register(&m_stratCandle,      "Candlestick", STRATEGY_CANDLESTICK,         false, InpUseCandlestick, false, 1.0);
    m_registry.Register(&m_stratFib,         "Fibonacci",   STRATEGY_FIBONACCI,           false, InpUseFibonacci,   false, 1.0);

    // Register AI strategies
    m_registry.Register(&m_stratNN,          "SimpleNN",    STRATEGY_NEURAL_NETWORK,      true,  InpUseSimpleNN,    false, 1.5);
    m_registry.Register(&m_stratTransformer, "Transformer", STRATEGY_TRANSFORMER,         true,  InpUseTransformer, false, 2.0);

    // Initialize all (mandatory failures kill EA, optional failures are logged)
    if(!m_registry.InitializeAll(&m_tradeManager, &m_positionSizer))
        return INIT_FAILED;

    // Guard: at least one strategy must be active
    if(!m_registry.HasAnyActive())
    {
        Print("[EA] ERROR: No strategies are active. Enable at least one.");
        return INIT_FAILED;
    }

    return INIT_SUCCEEDED;
}
```

---

## SECTION 5 — IStrategy Interface — Mandatory Fields

### 5.1 Ensure `IStrategy` (or `CStrategyBase`) has these methods

All strategies already extend `CStrategyBase`. Verify or add:

```cpp
// These must exist and be implemented on every strategy:
virtual ENUM_STRATEGY_TYPE GetType()   const = 0;
virtual string             GetName()   const = 0;
virtual bool               IsEnabled() const = 0;
virtual void               SetEnabled(bool enabled) = 0;
virtual double             GetWeight() const = 0;

// Signal (the only one that matters):
virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) = 0;

// Lifecycle:
virtual bool Init(const string symbol, ENUM_TIMEFRAMES tf, void* tradeMgr, void* posSizer) = 0;
virtual void Deinit() = 0;
virtual void OnNewBar(const string symbol, ENUM_TIMEFRAMES tf) {}  // Default: no-op
virtual void OnTick() {}                                            // Default: no-op
```

**No strategy should have public methods that are not on this interface** (the aggregator should never call strategy-specific methods like `GetCurrentTrendState()` directly — that bypasses the plugin model).

---

## SECTION 6 — Dashboard Visibility

### 6.1 Add strategy status to the chart dashboard

In the chart overlay / dashboard rendering code, add a section that calls `m_registry.GetDashboardSummary()` and `m_registry.PrintStatusTable()`.

The dashboard panel should show:

```
┌─────────────────────────────────────────┐
│ AXIOM EA — Mode: HYBRID                 │
│ Active Strategies:                      │
│   ✓ ICT          [IND]  w=2.0           │
│   ✓ S/R+TL       [IND]  w=1.5           │
│   ✓ Trend EMA    [IND]  w=1.5           │
│   ✗ Candlestick  disabled               │
│   ✗ Fibonacci    disabled               │
│   ✓ SimpleNN     [AI ]  w=1.5           │
│   ✗ Transformer  failed: Init() false   │
└─────────────────────────────────────────┘
```

This makes it impossible to not know what's active.

---

## SECTION 7 — Single Strategy Operation

### 7.1 Guarantee single-strategy mode works

The only code change needed is the guard in `OnInit()`:

```cpp
// Current broken check (if it exists):
if(m_stratICT == NULL && m_stratSR == NULL && m_stratTrend == NULL)
    return INIT_FAILED;

// Replace with:
if(!m_registry.HasAnyActive())
{
    Print("[EA] At least one strategy must be active. Check input flags.");
    return INIT_FAILED;
}
```

The aggregator's `AggregateIndicators()` already handles the single-strategy case:
```cpp
if(count == 1)
{
    return strategies[0].GetSignal(confidence);  // Passthrough — no voting needed
}
```

**This means setting `InpUseICT = true` and everything else `false` runs ICT standalone with no changes to strategy code.**

---

## SECTION 8 — Removing Compulsory Implicit Dependencies

### 8.1 Audit and eliminate hidden mandatory strategies

Run a search for any code that calls a specific strategy's `GetSignal()` directly (bypassing the registry). If found, move that call into the registry pattern.

Also search for strategy pointers being checked before the registry is consulted:
```cpp
// Bad pattern (hardcoded dependency):
if(m_ictStrategy != NULL)
    m_ictStrategy.Update();

// Good pattern:
// OnNewBar() calls registry, registry calls all active strategies
```

### 8.2 Remove compulsory ICT check from main signal path

If the main EA currently does something like:
```cpp
// Check ICT first, then other strategies
ENUM_TRADE_SIGNAL ictSignal = m_stratICT.GetSignal(conf);
if(ictSignal != TRADE_SIGNAL_NONE) { ... }

// Then check others
ENUM_TRADE_SIGNAL srSignal = m_stratSR.GetSignal(conf);
```

This makes ICT de-facto mandatory. Replace with the registry pattern entirely. The registry decides which strategies to call based on what's registered and enabled.

---

## SUMMARY OF DELIVERABLES

| File | Action |
|---|---|
| `Core/Utils/Enums.mqh` | Add `ENUM_EA_MODE` |
| `Core/Strategy/StrategyRegistry.mqh` | **New file** — complete implementation above |
| Main EA `.mq5` | Add input flags, call `m_registry.Register()` and `m_registry.InitializeAll()` |
| `Core/Strategy/IStrategy.mqh` or `StrategyBase.mqh` | Verify all pure virtuals exist |
| Signal aggregator (wherever signals are combined) | Replace flat loop with mode-aware `Aggregate()` |
| Dashboard rendering | Add `m_registry.GetDashboardSummary()` display |

---

*AXIOM Engineering Studio | Codex Spec Doc 2 of 3*
