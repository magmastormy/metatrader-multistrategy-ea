// StructureTypes.mqh - Shared market structure value types
// Extracted verbatim from StructureEngine.mqh (no behavior change)
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef STRUCTURE_TYPES_MQH
#define STRUCTURE_TYPES_MQH

enum ENUM_STRUCTURE_TYPE
{
    STRUCT_TYPE_NONE = 0,
    STRUCT_TYPE_HH,          // Higher High
    STRUCT_TYPE_HL,          // Higher Low  
    STRUCT_TYPE_LH,          // Lower High
    STRUCT_TYPE_LL,          // Lower Low
    STRUCT_TYPE_EQH,         // Equal High
    STRUCT_TYPE_EQL,         // Equal Low
    STRUCT_TYPE_BOS,         // Break of Structure
    STRUCT_TYPE_CHOCH,       // Change of Character
    STRUCT_TYPE_SWEEP,       // Liquidity Sweep
    STRUCT_TYPE_RAID         // Stop Hunt/Raid
};

struct SwingPoint
{
    double price;
    datetime time;
    int bar;
    ENUM_STRUCTURE_TYPE type;
    double strength;        // 0-100 strength score
    bool isValid;
    bool isMitigated;
    
    SwingPoint() : price(0), time(0), bar(0), type(STRUCT_TYPE_NONE), 
                   strength(0), isValid(false), isMitigated(false) {}
};

struct MarketStructureState
{
    ENUM_STRUCTURE_TYPE currentStructure;
    bool isBullish;
    bool isBearish;
    double lastHigh;
    double lastLow;
    double prevHigh;
    double prevLow;
    int bosCount;           // Break of Structure count
    int chochCount;         // Change of Character count
    double structureStrength;
    datetime lastUpdate;
    
    MarketStructureState() : currentStructure(STRUCT_TYPE_NONE), isBullish(false),
                            isBearish(false), lastHigh(0), lastLow(0),
                            prevHigh(0), prevLow(0), bosCount(0), chochCount(0),
                            structureStrength(0), lastUpdate(0) {}
};

#endif // STRUCTURE_TYPES_MQH
