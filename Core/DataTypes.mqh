#property strict

#ifndef __DATA_TYPES_MQH__
#define __DATA_TYPES_MQH__

#include <Object.mqh>

//+------------------------------------------------------------------+
//| Structure to hold information about an open position             |
//+------------------------------------------------------------------+
class SOpenPositionInfo : public CObject
{
public:
    ulong    ticket;
    string   symbol;      // Symbol
    double   lots;        // Position volume
    ENUM_POSITION_TYPE type;
    double   entryPrice;  // Position entry price

    //--- Constructor
    SOpenPositionInfo(string p_symbol, double p_volume, double p_price)
    {
        symbol = p_symbol;
        lots = p_volume;
        entryPrice = p_price;
    }
    SOpenPositionInfo(){}
};

//+------------------------------------------------------------------+
//| Structure to hold information about a closed trade record        |
//+------------------------------------------------------------------+
struct STradeRecord
{
    ulong    ticket;
    string   symbol;
    string   strategy;
    int      direction; // 1 for buy, -1 for sell
    double   volume;
    double   openPrice;
    datetime openTime;
    double   closePrice;
    datetime closeTime;
    double   profit;
    double   pips;
    bool     isWin;
};

#endif // __DATA_TYPES_MQH__
