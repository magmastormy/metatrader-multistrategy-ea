//+------------------------------------------------------------------+
//| PosLifecycleMagicFilter.mqh                                       |
//| Shared magic-number ownership predicate extracted from            |
//| PositionLifecycleManager.mqh (Phase H — God Object decomposition) |
//|                                                                   |
//| Behaviour is byte-for-byte identical to the original inline check |
//| CPositionLifecycleManager::IsEAOwnedMagic():                      |
//|     int maxMagic = base + symbolCount * 100 + maxClusterCode;     |
//|     return (magic >= base && magic <= maxMagic);                  |
//| The caller pre-computes [magicBase, magicMax] and passes it in so |
//| that no ownership state is duplicated across modules.             |
//+------------------------------------------------------------------+
#ifndef POS_LIFECYCLE_MAGIC_FILTER_MQH
#define POS_LIFECYCLE_MAGIC_FILTER_MQH

//+------------------------------------------------------------------+
//| Stateless helper — all methods are static.                        |
//+------------------------------------------------------------------+
class CPosLifecycleMagicFilter
{
public:
    //--- Returns true when `magic` falls inside this EA's ownership range.
    //--- NOTE: static methods cannot be const in MQL5.
    static bool IsOwned(const long magic, const int magicBase, const int magicMax)
    {
        return (magic >= magicBase && magic <= magicMax);
    }
};

#endif // POS_LIFECYCLE_MAGIC_FILTER_MQH
