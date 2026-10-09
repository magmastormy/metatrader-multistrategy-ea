// MarketAnalysisSymbolProfile.mqh - Symbol capability probes
// Extracted verbatim from MarketAnalysis.mqh (no behavior change)
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef MARKET_ANALYSIS_SYMBOL_PROFILE_MQH
#define MARKET_ANALYSIS_SYMBOL_PROFILE_MQH

#include "../Processing/MultiAssetProfiler.mqh"

// Global profiler access (g_multiAssetProfiler) is declared by the
// including translation unit, exactly as before this extraction.

// Stateless symbol classification helpers.
// Every method depends only on its argument and on the global
// multi-asset profiler, never on engine instance state.
class CMarketAnalysisSymbolProfile
{
public:
    //--- Check if symbol is available for trading/analysis
    static bool IsSymbolAvailable(const string symbolName);

    //--- Check if symbol is compatible with ADX indicator
    static bool IsADXCompatible(const string symbolName);

    //--- Check if symbol needs special indicator handling
    static bool RequiresSpecialHandling(const string symbolName);
};

// Check if symbol is available for trading/analysis
bool CMarketAnalysisSymbolProfile::IsSymbolAvailable(const string symbolName)
{
    // Check if symbol exists in Market Watch
    if(!SymbolInfoInteger(symbolName, SYMBOL_SELECT)) {
        return false;
    }

    // Check if we have price data
    double bid = SymbolInfoDouble(symbolName, SYMBOL_BID);
    double ask = SymbolInfoDouble(symbolName, SYMBOL_ASK);
    if(bid <= 0 || ask <= 0) {
        return false;
    }

    return true;
}

// Check if symbol is compatible with ADX indicator
bool CMarketAnalysisSymbolProfile::IsADXCompatible(const string symbolName)
{
    // Use global multi-asset profiler for proper asset classification
    if(g_multiAssetProfiler != NULL)
    {
        SAssetProfile profile = g_multiAssetProfiler.GetProfile(symbolName);
        if(IsSyntheticAssetClass(profile.assetClass))
        {
            // Check Deriv family for specific incompatible families
            CDerivAssetProfiler* derivProfiler = g_multiAssetProfiler.GetDerivProfiler();
            if(derivProfiler != NULL)
            {
                ENUM_DERIV_FAMILY family = derivProfiler.DetectFamily(symbolName);
                if(family == DERIV_CRASH_BOOM || family == DERIV_JUMP)
                    return false;
            }
        }
        return true;
    }

    // Fallback to string matching if profiler not available
    // Boom/Crash indices are incompatible
    if(StringFind(symbolName, "Boom") >= 0 || StringFind(symbolName, "Crash") >= 0)
        return false;

    // Jump indices have issues with ADX (error 4805)
    if(StringFind(symbolName, "Jump") >= 0)
        return false;

    return true;
}

// Check if symbol needs special indicator handling
bool CMarketAnalysisSymbolProfile::RequiresSpecialHandling(const string symbolName)
{
    // Use global multi-asset profiler for proper asset classification
    if(g_multiAssetProfiler != NULL)
    {
        SAssetProfile profile = g_multiAssetProfiler.GetProfile(symbolName);
        if(IsSyntheticAssetClass(profile.assetClass))
            return true;
        return false;
    }

    // Fallback to string matching if profiler not available
    // Volatility indices
    if(StringFind(symbolName, "Vol") >= 0)
        return true;

    // Jump indices
    if(StringFind(symbolName, "Jump") >= 0)
        return true;

    // Step indices
    if(StringFind(symbolName, "Step") >= 0)
        return true;

    // Weltrade / Other Synthetic indices
    if(StringFind(symbolName, "Boom") >= 0 ||
       StringFind(symbolName, "Crash") >= 0 ||
       StringFind(symbolName, "PainX") >= 0 ||
       StringFind(symbolName, "SFX Vol") >= 0 ||
       StringFind(symbolName, "GainX") >= 0 ||
       StringFind(symbolName, "FX Vol") >= 0 ||
       StringFind(symbolName, "FlipX") >= 0 ||
       StringFind(symbolName, "Volatility") >= 0 ||  // Deriv synthetic family
       StringFind(symbolName, "Jump") >= 0)           // Deriv Jump indices
        return true;

    return false;
}

#endif // MARKET_ANALYSIS_SYMBOL_PROFILE_MQH
