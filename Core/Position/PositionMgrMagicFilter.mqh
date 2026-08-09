//+------------------------------------------------------------------+
//| PositionMgrMagicFilter.mqh                                       |
//| Extracted from PositionManager.mqh (Phase I decomposition)       |
//|                                                                  |
//| STATELESS helper: decides whether a broker position magic number |
//| belongs to this EA instance. Behaviour is byte-for-byte identical|
//| to the original CPositionManager::IsEAOwnedMagic() body.         |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_POSITION_POSITION_MGR_MAGIC_FILTER_MQH
#define CORE_POSITION_POSITION_MGR_MAGIC_FILTER_MQH

//+------------------------------------------------------------------+
//| CPositionMgrMagicFilter                                          |
//| Pure static utility - holds no state, allocates nothing.         |
//+------------------------------------------------------------------+
class CPositionMgrMagicFilter
{
public:
    //--- Returns true when 'magic' falls inside this EA instance's magic range.
    //--- @param magic        POSITION_MAGIC value read from the terminal
    //--- @param magicNumber  base magic number configured for this EA instance
    static bool IsEAOwnedMagic(const long magic, const int magicNumber)
    {
        int maxMagic = magicNumber + 10000; // Approximate range
        return (magic >= magicNumber && magic <= maxMagic);
    }
};

#endif // CORE_POSITION_POSITION_MGR_MAGIC_FILTER_MQH
