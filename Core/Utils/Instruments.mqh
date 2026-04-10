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
class CModeManager;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;
class CAIStrategyOrchestrator;

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
    return (StringFind(normalized, "VOLATILITY ") >= 0);
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

bool IsSyntheticIndexSymbolName(const string symbol)
{
    return (IsVolatilitySyntheticSymbolName(symbol) ||
            IsJumpSyntheticSymbolName(symbol) ||
            IsStepSyntheticSymbolName(symbol) ||
            IsBoomCrashSyntheticSymbolName(symbol) ||
            IsRangeBreakSyntheticSymbolName(symbol) ||
            IsPainSyntheticSymbolName(symbol));
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
    if(IsVolatilitySyntheticSymbolName(symbol))
        return "SYNTHETIC_VOLATILITY";
    if(IsJumpSyntheticSymbolName(symbol))
        return "SYNTHETIC_JUMP";
    if(IsStepSyntheticSymbolName(symbol))
        return "SYNTHETIC_STEP";
    if(IsBoomCrashSyntheticSymbolName(symbol))
        return "SYNTHETIC_BOOM_CRASH";
    if(IsRangeBreakSyntheticSymbolName(symbol))
        return "SYNTHETIC_RANGE_BREAK";
    if(IsPainSyntheticSymbolName(symbol))
        return "SYNTHETIC_PAIN";
    if(IsForexPairSymbolName(symbol))
        return "FOREX";
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
