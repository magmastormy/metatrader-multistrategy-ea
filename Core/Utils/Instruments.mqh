//+------------------------------------------------------------------+
//| Tradable Instruments Registry                                   |
//| Provides manual and automatic instrument discovery               |
//+------------------------------------------------------------------+
#ifndef CORE_INSTRUMENTS_MQH
#define CORE_INSTRUMENTS_MQH

#include <Trade\SymbolInfo.mqh>
#include "../Utils/ErrorHandling.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;

// Manual list (Mode A) - Optimized for Deriv broker compatibility
// NOTE: Removed duplicates, preferring .0 suffix for Deriv symbols
static const string s_manualInstrumentList[] = {
    // Major Forex Pairs (Deriv .0 format preferred)
    "EURUSD.0", "GBPUSD.0", "USDJPY.0", "USDCHF.0", "AUDUSD.0", "NZDUSD.0",
    "USDCAD.0", "EURGBP.0", "EURJPY.0", "GBPJPY.0", "AUDJPY.0", "EURAUD.0",
    "EURCHF.0", "GBPCHF.0", "AUDCAD.0", "AUDNZD.0", "CADJPY.0", "CHFJPY.0",
    "NZDCAD.0", "NZDJPY.0", "NZDCHF.0",

    // Metals (Deriv .0 format)
    "XAUUSD.0", "XAGUSD.0", "XPTUSD.0", "XPDUSD.0",

    // Indices & CFDs (Note: Most indices not available on Deriv)
    "US30.0", "US500.0", "NAS100.0",

    // Commodities
    "WTICOUSD.0", "BRENTUSD.0", "NGASUSD.0", "COPPER.0",

    // Crypto Majors (Deriv .0 format)
    "BTCUSD.0", "ETHUSD.0", "LTCUSD.0", "XRPUSD.0", "ADAUSD.0", "SOLUSD.0",
    "BNBUSD.0", "DOGEUSD.0", "DOTUSD.0", "SHIBUSD.0",

    // Volatility Indices (Standard)
    "Volatility 10 Index.0",
    "Volatility 25 Index.0",
    "Volatility 50 Index.0",
    "Volatility 75 Index.0",
    "Volatility 100 Index.0",

    // Volatility Indices (1-second variants)
    "Volatility 10 (1s) Index.0",
    "Volatility 25 (1s) Index.0",
    "Volatility 50 (1s) Index.0",
    "Volatility 75 (1s) Index.0",
    "Volatility 100 (1s) Index.0",
    "Volatility 150 (1s) Index.0",
    "Volatility 200 (1s) Index.0",
    "Volatility 250 (1s) Index.0",

    // Jump Indices
    "Jump 10 Index.0",
    "Jump 25 Index.0",
    "Jump 50 Index.0",
    "Jump 75 Index.0",
    "Jump 100 Index.0",

    // Crash/Boom Indices
    "Crash 1000 Index.0",
    "Crash 500 Index.0",
    "Boom 1000 Index.0",
    "Boom 500 Index.0",

    // Range Break Indices
    "Range Break 100 Index.0",
    "Range Break 200 Index.0",

    // Step Indices (Deriv variants)
    "Step Index.0",
    "Step Index 200.0",
    "Step Index 300.0",
    "Step Index 400.0",
    "Step Index 500.0"

};

string NormalizeInstrumentSymbolName(const string symbol)
{
    string normalized = symbol;
    StringToUpper(normalized);
    StringReplace(normalized, ".0", "");
    return normalized;
}

bool IsVolatilitySyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "VOLATILITY ") >= 0 ||
            StringFind(normalized, "SFX VOL ") >= 0 ||
            StringFind(normalized, "FX VOL ") >= 0);
}

bool IsJumpSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "JUMP ") >= 0);
}

bool IsStepSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "STEP INDEX") >= 0);
}

bool IsBoomCrashSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "BOOM ") >= 0 || StringFind(normalized, "CRASH ") >= 0);
}

bool IsRangeBreakSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "RANGE BREAK ") >= 0);
}

bool IsPainSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "PAINX ") >= 0 || StringFind(normalized, "PAIN ") >= 0);
}

bool IsSwitchSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "SWITCHX ") >= 0 || StringFind(normalized, "SWITCH ") >= 0);
}

bool IsGainFlipSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "GAINX ") >= 0 ||
            StringFind(normalized, "GAIN ") >= 0 ||
            StringFind(normalized, "FLIPX ") >= 0 ||
            StringFind(normalized, "FLIP ") >= 0);
}

//--- Batch 102: Extended Deriv family detection (18 families)

bool IsDexSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "DEX ") >= 0);
}

bool IsMultiStepSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "MULTI") >= 0 && StringFind(normalized, "STEP") >= 0);
}

bool IsExponentialSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "EXP") >= 0 || StringFind(normalized, "GROWTH") >= 0);
}

bool IsHybridSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "HYBRID") >= 0);
}

bool IsSkewStepSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "SKEW") >= 0 && StringFind(normalized, "STEP") >= 0);
}

bool IsVolSwitchSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "VOL") >= 0 && StringFind(normalized, "SWITCH") >= 0);
}

bool IsDriftSwitchSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "DRIFT") >= 0 && StringFind(normalized, "SWITCH") >= 0);
}

bool IsTrekSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "TREK") >= 0);
}

bool IsTacticalSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "TACTICAL") >= 0);
}

bool IsDerivedSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "DERIVED") >= 0);
}

bool IsStableSpreadSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "STABLE") >= 0);
}

bool IsSpotVolatilitySyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "SPOT VOL") >= 0);
}

bool IsPairsArbitrageSyntheticSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "PAIRS") >= 0);
}

bool IsSyntheticIndexSymbolName(const string symbol)
{
    return (IsVolatilitySyntheticSymbolName(symbol) ||
            IsJumpSyntheticSymbolName(symbol) ||
            IsStepSyntheticSymbolName(symbol) ||
            IsBoomCrashSyntheticSymbolName(symbol) ||
            IsRangeBreakSyntheticSymbolName(symbol) ||
            IsPainSyntheticSymbolName(symbol) ||
            IsSwitchSyntheticSymbolName(symbol) ||
            IsGainFlipSyntheticSymbolName(symbol) ||
            IsDexSyntheticSymbolName(symbol) ||
            IsMultiStepSyntheticSymbolName(symbol) ||
            IsExponentialSyntheticSymbolName(symbol) ||
            IsHybridSyntheticSymbolName(symbol) ||
            IsSkewStepSyntheticSymbolName(symbol) ||
            IsVolSwitchSyntheticSymbolName(symbol) ||
            IsDriftSwitchSyntheticSymbolName(symbol) ||
            IsTrekSyntheticSymbolName(symbol) ||
            IsTacticalSyntheticSymbolName(symbol) ||
            IsDerivedSyntheticSymbolName(symbol) ||
            IsStableSpreadSyntheticSymbolName(symbol) ||
            IsSpotVolatilitySyntheticSymbolName(symbol) ||
            IsPairsArbitrageSyntheticSymbolName(symbol));
}

//+------------------------------------------------------------------+
//| Detect Deriv family ID from symbol name                          |
//| Priority order matches CDerivAssetProfiler::DetectFamily()       |
//| Returns: 0-17 for known families, -1 for non-Deriv symbols      |
//+------------------------------------------------------------------+
int DetectFamilyId(const string symbol)
{
    if(IsBoomCrashSyntheticSymbolName(symbol))    return 0;   // DERIV_CRASH_BOOM
    if(IsDexSyntheticSymbolName(symbol))           return 4;   // DERIV_DEX
    if(IsJumpSyntheticSymbolName(symbol))           return 3;   // DERIV_JUMP
    if(IsVolSwitchSyntheticSymbolName(symbol))      return 10;  // DERIV_VOL_SWITCH (before Volatility!)
    if(IsDriftSwitchSyntheticSymbolName(symbol))    return 11;  // DERIV_DRIFT_SWITCH
    if(IsSkewStepSyntheticSymbolName(symbol))       return 9;   // DERIV_SKEW_STEP
    if(IsMultiStepSyntheticSymbolName(symbol))      return 5;   // DERIV_MULTISTEP
    if(IsStepSyntheticSymbolName(symbol))           return 2;   // DERIV_STEP
    if(IsVolatilitySyntheticSymbolName(symbol))     return 1;   // DERIV_VOLATILITY
    if(IsExponentialSyntheticSymbolName(symbol))    return 6;   // DERIV_EXPONENTIAL
    if(IsHybridSyntheticSymbolName(symbol))         return 7;   // DERIV_HYBRID
    if(IsRangeBreakSyntheticSymbolName(symbol))     return 8;   // DERIV_RANGE_BREAK
    if(IsTrekSyntheticSymbolName(symbol))           return 12;  // DERIV_TREK
    if(IsTacticalSyntheticSymbolName(symbol))       return 13;  // DERIV_TACTICAL
    if(IsDerivedSyntheticSymbolName(symbol))        return 14;  // DERIV_DERIVED
    if(IsStableSpreadSyntheticSymbolName(symbol))   return 15;  // DERIV_STABLE_SPREAD
    if(IsPairsArbitrageSyntheticSymbolName(symbol)) return 16;  // DERIV_PAIRS_ARBITRAGE
    if(IsSpotVolatilitySyntheticSymbolName(symbol)) return 17;  // DERIV_SPOT_VOLATILITY
    return -1;
}

//+------------------------------------------------------------------+
//| Batch 103: Non-Deriv asset class detection functions             |
//+------------------------------------------------------------------+

bool IsMetalsSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "XAU") >= 0 ||
            StringFind(normalized, "XAG") >= 0 ||
            StringFind(normalized, "XPT") >= 0 ||
            StringFind(normalized, "XPD") >= 0 ||
            StringFind(normalized, "GOLD") >= 0 ||
            StringFind(normalized, "SILVER") >= 0);
}

bool IsIndicesSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "US30") >= 0 ||
            StringFind(normalized, "US500") >= 0 ||
            StringFind(normalized, "US100") >= 0 ||
            StringFind(normalized, "NAS100") >= 0 ||
            StringFind(normalized, "GER40") >= 0 ||
            StringFind(normalized, "UK100") >= 0 ||
            StringFind(normalized, "DOW") >= 0 ||
            StringFind(normalized, "NAS") >= 0 ||
            StringFind(normalized, "DAX") >= 0 ||
            StringFind(normalized, "SPX") >= 0 ||
            StringFind(normalized, "SP500") >= 0 ||
            StringFind(normalized, "FTSE") >= 0 ||
            StringFind(normalized, "NIKKEI") >= 0);
}

bool IsEnergiesSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    return (StringFind(normalized, "WTI") >= 0 ||
            StringFind(normalized, "OIL") >= 0 ||
            StringFind(normalized, "BRENT") >= 0 ||
            StringFind(normalized, "NGAS") >= 0 ||
            StringFind(normalized, "NATGAS") >= 0 ||
            StringFind(normalized, "XTI") >= 0 ||
            StringFind(normalized, "XBR") >= 0 ||
            StringFind(normalized, "WTICO") >= 0);
}

//+------------------------------------------------------------------+
//| Detect asset class ID from symbol name                           |
//| Priority: Deriv > Metals > Indices > Energies > Forex > Unknown  |
//| Returns: 0-9 for known asset classes (ENUM_ASSET_CLASS values)   |
//+------------------------------------------------------------------+
int DetectAssetClassId(const string symbol)
{
    // Deriv synthetics first (most specific)
    if(IsSyntheticIndexSymbolName(symbol))
    {
        if(IsBoomCrashSyntheticSymbolName(symbol) ||
           IsExponentialSyntheticSymbolName(symbol) ||
           IsHybridSyntheticSymbolName(symbol))
           return 4;   // ASSET_DERIV_CRASHBOOM
        if(IsVolatilitySyntheticSymbolName(symbol) ||
           IsVolSwitchSyntheticSymbolName(symbol) ||
           IsDriftSwitchSyntheticSymbolName(symbol) ||
           IsRangeBreakSyntheticSymbolName(symbol) ||
           IsSpotVolatilitySyntheticSymbolName(symbol))
           return 5;   // ASSET_DERIV_VOLATILITY
        if(IsStepSyntheticSymbolName(symbol) ||
           IsMultiStepSyntheticSymbolName(symbol) ||
           IsSkewStepSyntheticSymbolName(symbol) ||
           IsStableSpreadSyntheticSymbolName(symbol) ||
           IsPairsArbitrageSyntheticSymbolName(symbol) ||
           IsTrekSyntheticSymbolName(symbol) ||
           IsTacticalSyntheticSymbolName(symbol) ||
           IsDerivedSyntheticSymbolName(symbol))
           return 6;   // ASSET_DERIV_STEP
        if(IsJumpSyntheticSymbolName(symbol))
           return 7;   // ASSET_DERIV_JUMP
        if(IsDexSyntheticSymbolName(symbol))
           return 8;   // ASSET_DERIV_DEX
        return 9;      // ASSET_UNIVERSAL (unclassified Deriv)
    }

    // Traditional asset classes
    if(IsMetalsSymbolName(symbol))    return 1;  // ASSET_METALS
    if(IsIndicesSymbolName(symbol))   return 2;  // ASSET_INDICES
    if(IsEnergiesSymbolName(symbol))  return 3;  // ASSET_ENERGIES
    if(IsForexPairSymbolName(symbol)) return 0;  // ASSET_FOREX

    return 9;  // ASSET_UNIVERSAL
}

bool IsForexCurrencyCode(const string code)
{
    return (code == "USD" || code == "EUR" || code == "GBP" || code == "JPY" ||
            code == "CHF" || code == "AUD" || code == "NZD" || code == "CAD");
}

bool IsForexPairSymbolName(const string symbol)
{
    string normalized = NormalizeInstrumentSymbolName(symbol);
    StringReplace(normalized, "/", "");
    StringReplace(normalized, " ", "");
    StringReplace(normalized, "-", "");

    if(StringLen(normalized) < 6)
        return false;

    string base = StringSubstr(normalized, 0, 3);
    string quote = StringSubstr(normalized, 3, 3);
    return (IsForexCurrencyCode(base) && IsForexCurrencyCode(quote));
}

string GetInstrumentExecutionProfileName(const string symbol)
{
    if(IsBoomCrashSyntheticSymbolName(symbol))
        return "SYNTHETIC_BOOM_CRASH";
    if(IsVolatilitySyntheticSymbolName(symbol))
        return "SYNTHETIC_VOLATILITY";
    if(IsStepSyntheticSymbolName(symbol) && !IsSkewStepSyntheticSymbolName(symbol) && !IsMultiStepSyntheticSymbolName(symbol))
        return "SYNTHETIC_STEP";
    if(IsJumpSyntheticSymbolName(symbol))
        return "SYNTHETIC_JUMP";
    if(IsDexSyntheticSymbolName(symbol))
        return "SYNTHETIC_DEX";
    if(IsMultiStepSyntheticSymbolName(symbol))
        return "SYNTHETIC_MULTI_STEP";
    if(IsExponentialSyntheticSymbolName(symbol))
        return "SYNTHETIC_EXPONENTIAL";
    if(IsHybridSyntheticSymbolName(symbol))
        return "SYNTHETIC_HYBRID";
    if(IsRangeBreakSyntheticSymbolName(symbol))
        return "SYNTHETIC_RANGE_BREAK";
    if(IsSkewStepSyntheticSymbolName(symbol))
        return "SYNTHETIC_SKEW_STEP";
    if(IsVolSwitchSyntheticSymbolName(symbol))
        return "SYNTHETIC_VOL_SWITCH";
    if(IsDriftSwitchSyntheticSymbolName(symbol))
        return "SYNTHETIC_DRIFT_SWITCH";
    if(IsTrekSyntheticSymbolName(symbol))
        return "SYNTHETIC_TREK";
    if(IsTacticalSyntheticSymbolName(symbol))
        return "SYNTHETIC_TACTICAL";
    if(IsDerivedSyntheticSymbolName(symbol))
        return "SYNTHETIC_DERIVED";
    if(IsStableSpreadSyntheticSymbolName(symbol))
        return "SYNTHETIC_STABLE_SPREAD";
    if(IsSpotVolatilitySyntheticSymbolName(symbol))
        return "SYNTHETIC_SPOT_VOLATILITY";
    if(IsPairsArbitrageSyntheticSymbolName(symbol))
        return "SYNTHETIC_PAIRS_ARBITRAGE";
    if(IsPainSyntheticSymbolName(symbol))
        return "SYNTHETIC_PAIN";
    if(IsSwitchSyntheticSymbolName(symbol))
        return "SYNTHETIC_SWITCH";
    if(IsGainFlipSyntheticSymbolName(symbol))
        return "SYNTHETIC_GAIN_FLIP";
    if(IsForexPairSymbolName(symbol))
        return "FOREX";
    if(IsMetalsSymbolName(symbol))
        return "METALS";
    if(IsIndicesSymbolName(symbol))
        return "INDICES";
    if(IsEnergiesSymbolName(symbol))
        return "ENERGIES";
    return "GENERIC";
}

// Utility struct to hold discovery results
struct SInstrumentDirectory
{
    string           symbols[];
    bool             useManual;
    datetime         lastDiscovery;

    void Reset()
    {
        ArrayFree(symbols);
        useManual = true;
        lastDiscovery = 0;
    }
};

class CInstrumentRegistry : public CEnhancedErrorHandler
{
private:
    SInstrumentDirectory m_directory;
    string               m_component;
    int                  m_discoveryIntervalSeconds;

public:
    CInstrumentRegistry()
        : m_component("InstrumentRegistry"),
          m_discoveryIntervalSeconds(300)
    {
        m_directory.Reset();
    }

    bool Initialize(const int discoveryIntervalSeconds = 300)
    {
        if(discoveryIntervalSeconds < 60 || discoveryIntervalSeconds > 3600)
        {
            LogError(ERROR_RECOVERABLE, m_component, "Invalid discovery interval", discoveryIntervalSeconds);
            return false;
        }
        m_discoveryIntervalSeconds = discoveryIntervalSeconds;
        BuildManualDirectory();
        return true;
    }

    string Component() const { return m_component; }

    // Mode A: manual list to array
    void BuildManualDirectory()
    {
        ArrayFree(m_directory.symbols);
        int count = ArraySize(s_manualInstrumentList);
        ArrayResize(m_directory.symbols, count);
        for(int i = 0; i < count; ++i)
            m_directory.symbols[i] = s_manualInstrumentList[i];
        m_directory.useManual = true;
        m_directory.lastDiscovery = TimeCurrent();
    }

    // Mode B: discover from Market Watch
    int DiscoverFromMarketWatch(const bool force = false)
    {
        datetime now = TimeCurrent();
        if(!force && (now - m_directory.lastDiscovery) < m_discoveryIntervalSeconds && !m_directory.useManual)
            return ArraySize(m_directory.symbols);

        ArrayFree(m_directory.symbols);
        int total = SymbolsTotal(true);
        if(total <= 0)
        {
            LogError(ERROR_WARNING, m_component, "No symbols in Market Watch");
            BuildManualDirectory();
            return ArraySize(m_directory.symbols);
        }

        string active[];
        for(int i = 0; i < total; ++i)
        {
            string name = SymbolName(i, true);
            if(name == "")
                continue;

            if(!SymbolSelect(name, true))
                continue;

            MqlTick tick;
            if(!SymbolInfoTick(name, tick))
                continue;

            double minLot = SymbolInfoDouble(name, SYMBOL_VOLUME_MIN);
            double maxLot = SymbolInfoDouble(name, SYMBOL_VOLUME_MAX);
            if(minLot <= 0.0 || maxLot <= 0.0)
                continue;

            if(tick.bid <= 0.0 && tick.ask <= 0.0)
                continue;

            int idx = ArraySize(active);
            ArrayResize(active, idx + 1);
            active[idx] = name;
        }

        int discovered = ArraySize(active);
        if(discovered == 0)
        {
            LogError(ERROR_WARNING, m_component, "Auto-discovery yielded no tradeable symbols; falling back to manual list");
            BuildManualDirectory();
            return ArraySize(m_directory.symbols);
        }

        ArrayResize(m_directory.symbols, discovered);
        for(int i = 0; i < discovered; ++i)
            m_directory.symbols[i] = active[i];

        m_directory.useManual = false;
        m_directory.lastDiscovery = now;
        return discovered;
    }

    // Public accessor merges manual/auto discovery logic
    int GetTradableSymbols(string &outSymbols[], const bool refreshIfNeeded = true)
    {
        if(refreshIfNeeded && !m_directory.useManual)
            DiscoverFromMarketWatch(false);

        int size = ArraySize(m_directory.symbols);
        if(size == 0)
        {
            DiscoverFromMarketWatch(true);
            size = ArraySize(m_directory.symbols);
        }

        ArrayResize(outSymbols, size);
        for(int i = 0; i < size; ++i)
            outSymbols[i] = m_directory.symbols[i];
        return size;
    }

    bool UseManualMode() const { return m_directory.useManual; }
    datetime LastDiscovery() const { return m_directory.lastDiscovery; }
    void ForceRefresh() { DiscoverFromMarketWatch(true); }
};

#endif // CORE_INSTRUMENTS_MQH
