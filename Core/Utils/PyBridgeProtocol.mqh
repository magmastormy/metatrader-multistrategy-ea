//+------------------------------------------------------------------+
//| PyBridgeProtocol.mqh                                             |
//| Stateless message framing / (de)serialization helpers for the    |
//| Python bridge: JSON escaping, JSON scalar extraction, response   |
//| parsing, request building and version validation.                |
//| Extracted verbatim from PythonBridge.mqh (behaviour unchanged).  |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

#ifndef CORE_PYBRIDGE_PROTOCOL_MQH
#define CORE_PYBRIDGE_PROTOCOL_MQH

#include "PyBridgeTypes.mqh"

//+------------------------------------------------------------------+
//| Python Bridge Protocol Helpers (static-only, no state)           |
//+------------------------------------------------------------------+
class CPyBridgeProtocol
{
public:
   // JSON escaping
   static string     EscapeJsonString(const string &str);

   // JSON parsing helpers (Phase 6.3 — consolidated from 18+ duplicated patterns)
   static double     ParseJsonDouble(const string &json_str, const string &key);
   static string     ParseJsonString(const string &json_str, const string &key);
   static long       ParseJsonInteger(const string &json_str, const string &key);

   // Response / request framing
   static bool       ValidateJsonResponse(const string &json_str);
   static SPythonBridgeResponse ParsePredictionResponse(const string &json_str);
   static string     BuildPredictRequest(const double &features[], int features_size,
                                         const string mode,
                                         int family_id,
                                         const string symbol,
                                         int asset_class,
                                         const string asset_class_name);

   // Version handling
   static bool       ParseVersionResponse(const string &json_str, SPythonBridgeVersion &version);
   static bool       CheckVersionCompatibility(const SPythonBridgeVersion &version);
};

//+------------------------------------------------------------------+
//| Escape JSON string                                               |
//+------------------------------------------------------------------+
string CPyBridgeProtocol::EscapeJsonString(const string &str)
{
   string result = str;
   StringReplace(result, "\\", "\\\\");
   StringReplace(result, "\"", "\\\"");
   StringReplace(result, "\n", "\\n");
   StringReplace(result, "\r", "\\r");
   StringReplace(result, "\t", "\\t");
   return result;
}

//+------------------------------------------------------------------+
//| JSON parsing helpers (Phase 6.3 — consolidated from 18+ patterns)|
//+------------------------------------------------------------------+
double CPyBridgeProtocol::ParseJsonDouble(const string &json_str, const string &key)
{
   string searchKey = "\"" + key + "\":";
   int pos = StringFind(json_str, searchKey);
   if(pos == -1) { return 0.0; }

   string val_str = StringSubstr(json_str, pos + StringLen(searchKey));
   int end_pos = StringFind(val_str, ",");
   if(end_pos == -1) end_pos = StringFind(val_str, "}");
   if(end_pos != -1) val_str = StringSubstr(val_str, 0, end_pos);
   return StringToDouble(val_str);
}

string CPyBridgeProtocol::ParseJsonString(const string &json_str, const string &key)
{
   string searchKey = "\"" + key + "\":";
   int pos = StringFind(json_str, searchKey);
   if(pos == -1) return "";

   int val_start = StringFind(json_str, "\"", pos + StringLen(searchKey));
   int val_end   = StringFind(json_str, "\"", val_start + 1);
   if(val_start != -1 && val_end != -1)
      return StringSubstr(json_str, val_start + 1, val_end - val_start - 1);
   return "";
}

long CPyBridgeProtocol::ParseJsonInteger(const string &json_str, const string &key)
{
   string searchKey = "\"" + key + "\":";
   int pos = StringFind(json_str, searchKey);
   if(pos == -1) return 0;

   string val_str = StringSubstr(json_str, pos + StringLen(searchKey));
   int end_pos = StringFind(val_str, ",");
   if(end_pos == -1) end_pos = StringFind(val_str, "}");
   if(end_pos != -1) val_str = StringSubstr(val_str, 0, end_pos);
   return StringToInteger(val_str);
}

//+------------------------------------------------------------------+
//| Validate JSON response                                           |
//+------------------------------------------------------------------+
bool CPyBridgeProtocol::ValidateJsonResponse(const string &json_str)
{
   if(json_str == "")
      return false;
   
   // Basic JSON validation - check for balanced braces
   int brace_count = 0;
   int bracket_count = 0;
   bool in_string = false;
   
   for(int i = 0; i < StringLen(json_str); i++)
   {
      ushort c = StringGetCharacter(json_str, i);
      
      if(c == '"' && (i == 0 || StringGetCharacter(json_str, i-1) != '\\'))
         in_string = !in_string;
      
      if(in_string)
         continue;
      
      if(c == '{') brace_count++;
      if(c == '}') brace_count--;
      if(c == '[') bracket_count++;
      if(c == ']') bracket_count--;
      
      if(brace_count < 0 || bracket_count < 0)
         return false;
   }
   
   return (brace_count == 0 && bracket_count == 0 && !in_string);
}

//+------------------------------------------------------------------+
//| Parse prediction response JSON                                   |
//+------------------------------------------------------------------+
SPythonBridgeResponse CPyBridgeProtocol::ParsePredictionResponse(const string &json_str)
{
   SPythonBridgeResponse result;
   
   if(json_str == "")
   {
      result.success = false;
      result.error_message = "Empty response from server";
      return result;
   }
   
   // Check for error in response
   if(StringFind(json_str, "\"error\"") != -1)
   {
      result.success = false;
      result.error_message = ParseJsonString(json_str, "error");
      if(result.error_message == "")
         result.error_message = "Unknown error in server response";
      return result;
   }
   
   result.success = true;

   // Extract numeric fields via consolidated helper (Phase 6.3)
   result.buy_prob       = ParseJsonDouble(json_str, "buy_prob");
   result.sell_prob      = ParseJsonDouble(json_str, "sell_prob");
   result.hold_prob      = ParseJsonDouble(json_str, "hold_prob");
   result.lgbm_buy       = ParseJsonDouble(json_str, "lgbm_buy");
   result.lgbm_sell      = ParseJsonDouble(json_str, "lgbm_sell");
   result.stacker_signal = ParseJsonDouble(json_str, "stacker_signal");
   result.catboost_buy   = ParseJsonDouble(json_str, "catboost_buy");
   result.catboost_sell  = ParseJsonDouble(json_str, "catboost_sell");
   result.xgboost_buy    = ParseJsonDouble(json_str, "xgboost_buy");
   result.xgboost_sell   = ParseJsonDouble(json_str, "xgboost_sell");
   result.onnx_buy       = ParseJsonDouble(json_str, "onnx_buy");
   result.onnx_sell      = ParseJsonDouble(json_str, "onnx_sell");

   // Extract integer fields
   result.family_id     = (int)ParseJsonInteger(json_str, "family_id");
   result.asset_class   = (int)ParseJsonInteger(json_str, "asset_class");

   // Extract string fields
   result.family_name     = ParseJsonString(json_str, "family_name");
   result.asset_class_name = ParseJsonString(json_str, "asset_class_name");
   result.ts            = ParseJsonString(json_str, "ts");
   result.mode          = ParseJsonString(json_str, "mode");

   return result;
}

//+------------------------------------------------------------------+
//| Build the /predict request payload                               |
//+------------------------------------------------------------------+
string CPyBridgeProtocol::BuildPredictRequest(const double &features[], int features_size,
                                              const string mode,
                                              int family_id,
                                              const string symbol,
                                              int asset_class,
                                              const string asset_class_name)
{
   // Build JSON request
   string json = "{\"features\":[";
   for(int i = 0; i < features_size; i++)
   {
      if(i > 0) json += ",";
      json += DoubleToString(features[i], 10);
   }
   json += "],\"mode\":\"" + EscapeJsonString(mode) + "\"";
   if(family_id >= 0)
      json += ",\"family_id\":" + IntegerToString(family_id);
   if(symbol != "")
      json += ",\"symbol\":\"" + EscapeJsonString(symbol) + "\"";
   // Batch 103: Multi-asset class routing
   if(asset_class >= 0)
      json += ",\"asset_class\":" + IntegerToString(asset_class);
   if(asset_class_name != "")
      json += ",\"asset_class_name\":\"" + EscapeJsonString(asset_class_name) + "\"";
   json += "}";
   return json;
}

//+------------------------------------------------------------------+
//| Parse version response                                           |
//+------------------------------------------------------------------+
bool CPyBridgeProtocol::ParseVersionResponse(const string &json_str, SPythonBridgeVersion &version)
{
   if(!ValidateJsonResponse(json_str))
      return false;

   // Extract version string
   version.version = ParseJsonString(json_str, "version");
   
   // Parse version components
   if(version.version != "")
   {
      string parts[];
      int parts_count = StringSplit(version.version, '.', parts);
      if(parts_count >= 1) version.major = (int)StringToInteger(parts[0]);
      if(parts_count >= 2) version.minor = (int)StringToInteger(parts[1]);
      if(parts_count >= 3) version.patch = (int)StringToInteger(parts[2]);
   }
   
   // Check compatibility
   version.compatible = CheckVersionCompatibility(version);
   
   return true;
}

//+------------------------------------------------------------------+
//| Check version compatibility                                      |
//+------------------------------------------------------------------+
bool CPyBridgeProtocol::CheckVersionCompatibility(const SPythonBridgeVersion &version)
{
   const int REQUIRED_MAJOR = 1;
   const int REQUIRED_MINOR = 0;
   
   // Major version must match
   if(version.major != REQUIRED_MAJOR)
      return false;
   
   // Minor version must be >= required
   if(version.minor < REQUIRED_MINOR)
      return false;
   
   return true;
}

#endif // CORE_PYBRIDGE_PROTOCOL_MQH
