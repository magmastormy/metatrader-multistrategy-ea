// Stateless string<->enum descriptors for trade primitives
// Extracted from Core/Trading/TradeManager.mqh in Phase D T1.
// All members are static pure functions - no instance state.
// Bodies are verbatim copies; the original `const` qualifier on
// OrderTypeFromString was dropped because MQL5 does not permit
// `static ... const` methods.
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property strict

#ifndef CORE_TRADING_TRADE_DESCRIPTOR_MQH
#define CORE_TRADING_TRADE_DESCRIPTOR_MQH

// Human-readable retcode text and order-type string parsing.
class CTradeDescriptor
{
public:
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
            // Batch 152 (T-11): async/partial/connection outcomes were falling
            // through to "Unknown error" although they are routine live results.
            case TRADE_RETCODE_PLACED:           return "Order placed";
            case TRADE_RETCODE_DONE_PARTIAL:     return "Partial fill";
            case TRADE_RETCODE_INVALID_FILL:     return "Invalid fill type";
            case TRADE_RETCODE_CONNECTION:       return "No connection to server";
            case TRADE_RETCODE_LOCKED:           return "Request locked";
            case TRADE_RETCODE_FROZEN:           return "Position frozen";
            case TRADE_RETCODE_LIMIT_ORDERS:     return "Pending order limit reached";
            case TRADE_RETCODE_LIMIT_VOLUME:     return "Volume limit reached";
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
