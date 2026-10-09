// Ownership predicate for the CPositionLifecycleManager family.
// Batch 168: the arithmetic moved to CMagicRange so this predicate
// and every other ownership test in the EA agree on one window.
// Callers still pre-compute [magicBase, magicMax] via
// CPositionLifecycleManager::MagicMax(), which now delegates to
// CMagicRange::ComputeMax().
#ifndef POS_LIFECYCLE_MAGIC_FILTER_MQH
#define POS_LIFECYCLE_MAGIC_FILTER_MQH

#include "../Utils/MagicRange.mqh"

// Stateless helper — all methods are static.
class CPosLifecycleMagicFilter
{
public:
    //--- Returns true when `magic` falls inside this EA's ownership range.
    //--- NOTE: static methods cannot be const in MQL5.
    static bool IsOwned(const long magic, const int magicBase, const int magicMax)
    {
        return CMagicRange::IsOwned(magic, magicBase, magicMax);
    }

    //--- Batch 170: owned, and not one of the engine-managed books whose exits
    //--- their own engines already own. Use this wherever an EXIT decision is
    //--- made; use IsOwned() for ownership/accounting.
    static bool IsLifecycleManaged(const long magic, const string comment,
                                   const int magicBase, const int magicMax)
    {
        if(!CMagicRange::IsOwned(magic, magicBase, magicMax))
            return false;
        return !IsEngineManagedPosition(comment);
    }
};

#endif // POS_LIFECYCLE_MAGIC_FILTER_MQH
