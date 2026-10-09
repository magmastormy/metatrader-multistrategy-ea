// Shared stateless JSON primitives for the dashboard bridge.
// Extracted verbatim from DashboardBridge.mqh (behaviour unchanged)
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

#ifndef CORE_DASHBRIDGE_TYPES_MQH
#define CORE_DASHBRIDGE_TYPES_MQH

// Dashboard Bridge JSON Helpers (static-only, no state)
class CDashBridgeJson
{
public:
   // JSON escaping
   static string     EscapeJsonString(const string &str);
};

string CDashBridgeJson::EscapeJsonString(const string &str)
{
   string result = str;
   StringReplace(result, "\\", "\\\\");
   StringReplace(result, "\"", "\\\"");
   StringReplace(result, "\n", "\\n");
   StringReplace(result, "\r", "\\r");
   StringReplace(result, "\t", "\\t");
   return result;
}

#endif // CORE_DASHBRIDGE_TYPES_MQH
