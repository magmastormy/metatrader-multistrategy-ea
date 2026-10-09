// Stateless classification of MT5 trade server return codes
// Extracted from Core/Trading/TradeManager.mqh in Phase D T1.
// All members are static pure functions - no instance state.
// Bodies are verbatim copies; the original `const` qualifiers were
// dropped because MQL5 does not permit `static ... const` methods.
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property strict

#ifndef CORE_TRADING_TRADE_RETCODE_CLASSIFIER_MQH
#define CORE_TRADING_TRADE_RETCODE_CLASSIFIER_MQH

// Groups broker retcodes into retry / fill semantics.
class CTradeRetcodeClassifier
{
public:
// Retcodes worth retrying repeatedly (transient market conditions)
// Batch 150: TIMEOUT/CONNECTION removed - order state is UNKNOWN
// after these; resending can duplicate a filled order.
    static bool IsTransientTradeRetcode(const uint retcode)
    {
        return (retcode == TRADE_RETCODE_REQUOTE ||
                retcode == TRADE_RETCODE_PRICE_CHANGED ||
                retcode == TRADE_RETCODE_PRICE_OFF ||
                retcode == TRADE_RETCODE_TOO_MANY_REQUESTS);
    }

// Retcodes worth exactly one retry
    static bool IsLimitedRetryRetcode(const uint retcode)
    {
        return (retcode == TRADE_RETCODE_LOCKED ||
                retcode == TRADE_RETCODE_FROZEN);
    }

// Retcodes that represent a filled (whole or partial) order
    static bool IsSuccessfulFillRetcode(const uint retcode)
    {
        return (retcode == TRADE_RETCODE_DONE ||
                retcode == TRADE_RETCODE_DONE_PARTIAL);
    }
};

#endif // CORE_TRADING_TRADE_RETCODE_CLASSIFIER_MQH
//+------------------------------------------------------------------+
