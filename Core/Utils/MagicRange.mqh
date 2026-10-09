//+------------------------------------------------------------------+
//| MagicRange.mqh                                                   |
//| Single authority for EA magic-number ownership (Batch 168).      |
//|                                                                  |
//| Before this file, five separate predicates computed the ownership |
//| window differently (base..base+symbolCount*100+99,               |
//| base..base+10000, base..base+999, base..base+13, and a           |
//| min/max pair passed in the wrong order). Positions the EA sends  |
//| carry an asset-class offset of 7000..9400                        |
//| (CMultiAssetProfiler::magicOffset), which falls outside the      |
//| symbolCount-scaled windows - so most consumers classified the    |
//| EA's own positions as foreign and silently skipped trailing,     |
//| breakeven, pyramiding, loss guards and no-SL remediation.        |
//|                                                                  |
//| Every ownership test must now route through IsMagicOwned().      |
//+------------------------------------------------------------------+
#ifndef CORE_UTILS_MAGIC_RANGE_MQH
#define CORE_UTILS_MAGIC_RANGE_MQH

//+------------------------------------------------------------------+
//| Ownership window layout.                                         |
//|   base + asset-class offset (0..MAGIC_ASSET_OFFSET_SPAN)         |
//|          + per-symbol/cluster slot (0..symbolCount*100 + 99)     |
//|                                                                  |
//| MAGIC_ASSET_OFFSET_SPAN is pinned to the largest asset-class      |
//| offset any profile can emit: CMultiAssetProfiler tops out at 9400 |
//| (ASSET_DERIV_DEX) and CDerivAssetProfiler at 9999 (DERIV_UNKNOWN, |
//| the fallback for an unrecognised symbol). ValidateMagicOwnership- |
//| Coverage asserts this at init, so a future offset beyond 9999     |
//| fails loudly instead of silently orphaning positions.            |
//+------------------------------------------------------------------+
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

    //--- Pure predicate. Fail closed: an unconfigured base owns nothing,
    //--- so no close/modify path can act on an unverifiable position.
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

//+------------------------------------------------------------------+
//| Engine-managed positions (Batch 170).                            |
//|                                                                  |
//| The scalp / grid / spike engines send AND exit through their own |
//| modules. Batch 168 switched the lifecycle exit chain on for every|
//| owned position, which put a second exit authority on those books:|
//| breakeven and trailing were free to close a scalp position the   |
//| engine was still managing toward its own target.                 |
//|                                                                  |
//| Magic number cannot separate them - the engines compose their    |
//| magics from the same asset-offset space as the strategy book (the|
//| ATR scalp engine sits on offset 7000, which IS ASSET_FOREX), and |
//| moving them into a reserved band is not safe while the profiler  |
//| adds its per-symbol slot on top of every offset. The send comment|
//| is the one field each engine stamps uniquely and that survives a |
//| restart, so it is the discriminator.                             |
//|                                                                  |
//| These positions stay EA-OWNED (risk, exposure and daily-loss     |
//| accounting must still see them); they are only excluded from     |
//| lifecycle exits.                                                 |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Startup assertion: the largest magic number the EA is about to   |
//| ship must fall inside the configured window. maxShippedOffset is |
//| the largest CMultiAssetProfiler::GetMagicOffset() seen for the   |
//| live symbol universe. A broker-side asset reclassification that  |
//| pushed an offset past the span would otherwise orphan positions  |
//| again, silently.                                                 |
//+------------------------------------------------------------------+
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
