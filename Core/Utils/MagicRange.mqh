// Single authority for EA magic-number ownership. Orders carry an asset-class
// offset of 0..9999, so any narrower window silently treats the EA's own
// positions as foreign and skips their exits. Route every ownership test here.
#ifndef CORE_UTILS_MAGIC_RANGE_MQH
#define CORE_UTILS_MAGIC_RANGE_MQH

// Window: base + asset-class offset + per-symbol/cluster slot. The span must
// cover the largest offset any profile emits (DERIV_UNKNOWN = 9999);
// ValidateMagicOwnershipCoverage asserts that at init.
#ifndef MAGIC_ASSET_OFFSET_SPAN
#define MAGIC_ASSET_OFFSET_SPAN 10000
#endif
#ifndef MAGIC_SYMBOL_MULTIPLIER
#define MAGIC_SYMBOL_MULTIPLIER 100
#endif
#ifndef MAGIC_CLUSTER_SPAN
#define MAGIC_CLUSTER_SPAN 99
#endif

class CMagicRange
{
public:
    //--- Pure formula. Single source of truth for the ownership ceiling.
    static long ComputeMax(const long base, const int symbolCount)
    {
        int slots = (symbolCount > 0) ? symbolCount : 0;
        return base + MAGIC_ASSET_OFFSET_SPAN
                    + (long)slots * MAGIC_SYMBOL_MULTIPLIER
                    + MAGIC_CLUSTER_SPAN;
    }

    //--- Fail closed: an unconfigured base owns nothing.
    static bool IsOwned(const long magic, const long base, const long maxMagic)
    {
        if(base <= 0)
            return false;
        if(magic < base)
            return false;
        return (magic <= maxMagic);
    }
};

//--- Configured once in CEAOrchestrator::Initialize after the symbol
//--- universe is known; read by every ownership consumer afterwards.
long g_magicBase = 0;
long g_magicMax  = 0;

void ConfigureMagicOwnership(const long base, const int symbolCount)
{
    g_magicBase = base;
    g_magicMax  = CMagicRange::ComputeMax(base, symbolCount);
    PrintFormat("[MAGIC-AUTHORITY] base=%I64d span=%I64d owned_range=[%I64d, %I64d] | symbolCount=%d",
                base, (long)(g_magicMax - base), base, g_magicMax, symbolCount);
}

bool IsMagicOwned(const long magic)
{
    return CMagicRange::IsOwned(magic, g_magicBase, g_magicMax);
}

//--- True once ConfigureMagicOwnership has run. Consumers that would FAIL OPEN
//--- by excluding rows when ownership is unknown (loss accounting, risk
//--- aggregation) must check this and fall back to counting everything instead.
bool IsMagicOwnershipConfigured()
{
    return (g_magicBase > 0 && g_magicMax >= g_magicBase);
}

// The scalp/grid/spike engines exit their own positions, so lifecycle exits skip
// them while risk and daily-loss accounting still count them as EA-owned. Magic
// cannot separate the two books (scalp sits on offset 7000, which is ASSET_FOREX),
// so the send comment is the discriminator.
string g_enginePositionTags[4] = {"ATR-SCALP", "GRID-RECOVERY", "SPIKE-HUNT", "SCALP|"};

bool IsEngineManagedPosition(const string comment)
{
    for(int i = 0; i < ArraySize(g_enginePositionTags); i++)
    {
        if(StringFind(comment, g_enginePositionTags[i]) == 0)
            return true;
    }
    return false;
}

// Startup assertion: the largest magic number the EA is about to
// ship must fall inside the configured window. maxShippedOffset is
// the largest CMultiAssetProfiler::GetMagicOffset() seen for the
// live symbol universe. A broker-side asset reclassification that
// pushed an offset past the span would otherwise orphan positions
// again, silently.
bool ValidateMagicOwnershipCoverage(const long base, const int maxShippedOffset)
{
    if(!CMagicRange::IsOwned(base, g_magicBase, g_magicMax))
    {
        PrintFormat("[MAGIC-AUTHORITY] FATAL: base magic %I64d is outside the configured window [%I64d, %I64d]",
                    base, g_magicBase, g_magicMax);
        return false;
    }

    long highestShipped = base + (long)MathMax(0, maxShippedOffset);
    if(!CMagicRange::IsOwned(highestShipped, g_magicBase, g_magicMax))
    {
        PrintFormat("[MAGIC-AUTHORITY] FATAL: highest shipped magic %I64d (asset offset +%d) exceeds window max %I64d - positions would be unmanaged",
                    highestShipped, maxShippedOffset, g_magicMax);
        return false;
    }

    PrintFormat("[MAGIC-AUTHORITY] Coverage OK | highest shipped magic=%I64d within max %I64d",
                highestShipped, g_magicMax);
    return true;
}

#endif // CORE_UTILS_MAGIC_RANGE_MQH
