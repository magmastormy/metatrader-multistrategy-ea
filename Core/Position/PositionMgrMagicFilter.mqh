//+------------------------------------------------------------------+
//| PositionMgrMagicFilter.mqh                                       |
//| Extracted from PositionManager.mqh (Phase I decomposition)       |
//|                                                                  |
//| STATELESS helper: decides whether a broker position magic number |
//| belongs to this EA instance. Batch 168 replaced the old           |
//| `magicNumber + 10000 // Approximate range` guess with the         |
//| CMagicRange authority so this and every other ownership test in   |
//| the EA agree on one window.                                       |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_POSITION_POSITION_MGR_MAGIC_FILTER_MQH
#define CORE_POSITION_POSITION_MGR_MAGIC_FILTER_MQH

#include "../Utils/MagicRange.mqh"

//+------------------------------------------------------------------+
//| CPositionMgrMagicFilter                                          |
//| Pure static utility - holds no state, allocates nothing.         |
//+------------------------------------------------------------------+
class CPositionMgrMagicFilter
{
public:
    //--- Returns true when 'magic' falls inside this EA instance's window.
    //--- Reads the process-wide configured range; callers no longer supply a
    //--- base, because a per-object base plus a guessed span was the original
    //--- defect. NOTE: static methods cannot be const in MQL5.
    static bool IsEAOwnedMagic(const long magic)
    {
        return IsMagicOwned(magic);
    }
};

#endif // CORE_POSITION_POSITION_MGR_MAGIC_FILTER_MQH
