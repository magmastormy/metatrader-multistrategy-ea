// Signal Pipeline Normalizer - symbol classification (extracted)
#ifndef SIGNAL_PIPELINE_NORMALIZER_MQH
#define SIGNAL_PIPELINE_NORMALIZER_MQH

#include "../Utils/Enums.mqh"
#include "../Processing/MultiAssetProfiler.mqh"

// Forward declaration for global profiler access (initialized in EAOrchestrator)
class CMultiAssetProfiler;
extern CMultiAssetProfiler* g_multiAssetProfiler;

class CSignalPipelineNormalizer
{
public:
static bool IsSyntheticSymbol(const string symbol)
{
    if(symbol == "") return false;
    
    // Use global multi-asset profiler for proper asset classification
    if(g_multiAssetProfiler != NULL)
    {
        SAssetProfile profile = g_multiAssetProfiler.GetProfile(symbol);
        return IsSyntheticAssetClass(profile.assetClass);
    }
    
    // Fallback to string matching if profiler not available
    // Check for broker-specific synthetic products that trade 24/7 or outside regular FX sessions.
    if(StringFind(symbol, "Vol") >= 0  ||      // Vol 10, Vol 25, Vol 50, etc.
       StringFind(symbol, "Step") >= 0 ||      // Step Index variants
       StringFind(symbol, "Boom") >= 0 ||      // Boom 1000, Boom 500
       StringFind(symbol, "Crash") >= 0 ||     // Crash 1000, Crash 500
       StringFind(symbol, "Jump") >= 0 ||      // Jump 10, Jump 25, etc.
       StringFind(symbol, "PainX") >= 0 ||     // Weltrade synthetic family
       StringFind(symbol, "Pain ") >= 0 ||     // Additional naming variant
       StringFind(symbol, "SFX Vol") >= 0 ||
       StringFind(symbol, "FX Vol") >= 0 ||
       StringFind(symbol, "GainX") >= 0 ||
       StringFind(symbol, "FlipX") >= 0 ||
       StringFind(symbol, "SwitchX") >= 0 ||   // SwitchX 1200 and variants
       StringFind(symbol, "Synth") >= 0 ||
       StringFind(symbol, "Index") >= 0)
    {
        return true;
    }
    return false;
}
};

#endif // SIGNAL_PIPELINE_NORMALIZER_MQH
