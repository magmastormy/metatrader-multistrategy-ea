//+------------------------------------------------------------------+
//| TradeDescriptor.mqh                                              |
//| Stateless string<->enum descriptors for trade primitives         |
//|                                                                  |
//| Extracted from Core/Trading/TradeManager.mqh in Phase D T1.      |
//| All members are static pure functions - no instance state.       |
//| Bodies are verbatim copies; the original `const` qualifier on    |
//| OrderTypeFromString was dropped because MQL5 does not permit     |
//| `static ... const` methods.                                      |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property strict

#ifndef CORE_TRADING_TRADE_DESCRIPTOR_MQH
#define CORE_TRADING_TRADE_DESCRIPTOR_MQH

//+------------------------------------------------------------------+
//| Trade Descriptor                                                 |
//| Human-readable retcode text and order-type string parsing.       |
//+------------------------------------------------------------------+
class CTradeDescriptor
{
public:
    //+------------------------------------------------------------------+
    //| Get trade error description                                      |
    //+------------------------------------------------------------------+
    static string GetTradeErrorDescription(int errorCode)
    {
        switch(errorCode)
        {
            case TRADE_RETCODE_REQUOTE:          return "Requote";
            case TRADE_RETCODE_PRICE_OFF:        return "Price off";
            case TRADE_RETCODE_INVALID_PRICE:    return "Invalid price";
            case TRADE_RETCODE_INVALID_STOPS:    return "Invalid stops";
            case TRADE_RETCODE_INVALID_VOLUME:   return "Invalid volume";
            case TRADE_RETCODE_MARKET_CLOSED:    return "Market closed";
            case TRADE_RETCODE_NO_MONEY:         return "Not enough money";
            case TRADE_RETCODE_PRICE_CHANGED:    return "Price changed";
            case TRADE_RETCODE_TIMEOUT:          return "Timeout";
            case TRADE_RETCODE_INVALID_EXPIRATION: return "Invalid expiration";
            case TRADE_RETCODE_ORDER_CHANGED:    return "Order changed";
            case TRADE_RETCODE_TOO_MANY_REQUESTS: return "Too many requests";
            case TRADE_RETCODE_NO_CHANGES:       return "No changes";
            case TRADE_RETCODE_SERVER_DISABLES_AT: return "AutoTrading disabled";
            case TRADE_RETCODE_CLIENT_DISABLES_AT: return "AutoTrading disabled by client";
            case TRADE_RETCODE_INVALID_ORDER:    return "Invalid order";
            case TRADE_RETCODE_POSITION_CLOSED:  return "Position closed";
            case TRADE_RETCODE_TRADE_DISABLED:   return "Trading disabled";
            case TRADE_RETCODE_HEDGE_PROHIBITED: return "Hedging prohibited";
            case TRADE_RETCODE_DONE:             return "Success";
            default:                             return "Unknown error (" + IntegerToString(errorCode) + ")";
        }
    }

    // Convert order type string to ENUM_ORDER_TYPE
    static ENUM_ORDER_TYPE OrderTypeFromString(const string orderTypeStr)
    {
        if(StringCompare(orderTypeStr, "ORDER_TYPE_BUY", true) == 0)
            return ORDER_TYPE_BUY;
        else if(StringCompare(orderTypeStr, "ORDER_TYPE_SELL", true) == 0)
            return ORDER_TYPE_SELL;
        else if(StringCompare(orderTypeStr, "ORDER_TYPE_BUY_LIMIT", true) == 0)
            return ORDER_TYPE_BUY_LIMIT;
        else if(StringCompare(orderTypeStr, "ORDER_TYPE_SELL_LIMIT", true) == 0)
            return ORDER_TYPE_SELL_LIMIT;
        else if(StringCompare(orderTypeStr, "ORDER_TYPE_BUY_STOP", true) == 0)
            return ORDER_TYPE_BUY_STOP;
        else if(StringCompare(orderTypeStr, "ORDER_TYPE_SELL_STOP", true) == 0)
            return ORDER_TYPE_SELL_STOP;
        else if(StringCompare(orderTypeStr, "ORDER_TYPE_BUY_STOP_LIMIT", true) == 0)
            return ORDER_TYPE_BUY_STOP_LIMIT;
        else if(StringCompare(orderTypeStr, "ORDER_TYPE_SELL_STOP_LIMIT", true) == 0)
            return ORDER_TYPE_SELL_STOP_LIMIT;
        return ORDER_TYPE_BUY; // Default fallback
    }
};

#endif // CORE_TRADING_TRADE_DESCRIPTOR_MQH
//+------------------------------------------------------------------+
