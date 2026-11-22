#ifndef CORE_UTILS_INTENT_TRACE_MQH
#define CORE_UTILS_INTENT_TRACE_MQH

#include "Enums.mqh"

class CIntentTrace
{
public:
    static string BuildId(const string symbol, const datetime eventTime,
                          const ENUM_TIMEFRAMES timeframe, const ENUM_SIGNAL_EVAL_MODE evalMode,
                          const string scope = "SIGNAL")
    {
        if(symbol == "" || eventTime <= 0 || scope == "")
            return "";

        string modeCode = (evalMode == EVAL_MODE_INTRABAR) ? "I" : "N";
        return StringFormat("INT-%d-%I64d-%s-%s-%s", (int)timeframe, (long)eventTime, modeCode, scope, symbol);
    }

    static void LogStage(const string intentId, const string symbol, const string stage,
                         const string outcome, const string reason)
    {
        if(intentId == "")
            return;

        PrintFormat("[INTENT-STAGE] intent_id=%s | stage=%s | outcome=%s | reason=%s | symbol=%s",
                    intentId, stage, outcome, reason, symbol);
    }
};

#endif // CORE_UTILS_INTENT_TRACE_MQH
