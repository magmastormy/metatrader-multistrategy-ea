// Dashboard state payload assembly: account panel, positions panel
// and the composition of every sub-section produced by the
// protocol / health modules into the final /state document.
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

#ifndef CORE_DASHBRIDGE_PANELS_MQH
#define CORE_DASHBRIDGE_PANELS_MQH

#include "DashBridgeTypes.mqh"
#include "DashBridgeProtocol.mqh"
#include "DashBridgeHealth.mqh"

class CDashBridgePanels
{
public:
   // Full /state document
   static string     BuildStateJson(const CDashBridgeProtocol &protocolData,
                                    const CDashBridgeHealth &healthData);

   static string     BuildAccountJson();
   static string     BuildPositionsJson();
   static string     BuildScalpJson();
};

string CDashBridgePanels::BuildAccountJson()
{
   string json = "\"account\":{";
   json += "\"balance\":" + DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2) + ",";
   json += "\"equity\":" + DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2) + ",";
   json += "\"free_margin\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2) + ",";
   json += "\"margin_level\":" + DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_LEVEL), 2);
   json += "}";
   return json;
}

string CDashBridgePanels::BuildPositionsJson()
{
   string json = "\"positions\":[";
   int posTotal = PositionsTotal();
   int posAdded = 0;
   for(int i = 0; i < posTotal; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;

      if(posAdded > 0) json += ",";
      json += "{";
      json += "\"ticket\":" + IntegerToString((long)ticket) + ",";
      json += "\"symbol\":\"" + CDashBridgeJson::EscapeJsonString(PositionGetString(POSITION_SYMBOL)) + "\",";
      json += "\"type\":\"" + (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "BUY" : "SELL") + "\",";
      json += "\"lots\":" + DoubleToString(PositionGetDouble(POSITION_VOLUME), 2) + ",";
      json += "\"open_price\":" + DoubleToString(PositionGetDouble(POSITION_PRICE_OPEN), 5) + ",";
      json += "\"current_price\":" + DoubleToString(PositionGetDouble(POSITION_PRICE_CURRENT), 5) + ",";
      json += "\"sl\":" + DoubleToString(PositionGetDouble(POSITION_SL), 5) + ",";
      json += "\"tp\":" + DoubleToString(PositionGetDouble(POSITION_TP), 5) + ",";
      json += "\"profit\":" + DoubleToString(PositionGetDouble(POSITION_PROFIT), 2) + ",";
      json += "\"swap\":" + DoubleToString(PositionGetDouble(POSITION_SWAP), 2) + ",";
      json += "\"open_time\":\"" + TimeToString((datetime)PositionGetInteger(POSITION_TIME), TIME_DATE|TIME_SECONDS) + "\",";
      json += "\"duration_minutes\":" + IntegerToString((int)((TimeCurrent() - PositionGetInteger(POSITION_TIME)) / 60)) + ",";
      json += "\"strategy\":\"" + CDashBridgeJson::EscapeJsonString(PositionGetString(POSITION_COMMENT)) + "\"";
      json += "}";
      posAdded++;
   }
   json += "]";
   return json;
}

// Build scalp panel JSON (placeholder for now)
string CDashBridgePanels::BuildScalpJson()
{
   string json = "\"scalp\":{";
   json += "\"active\":false,";
   json += "\"open_positions\":0,";
   json += "\"max_positions\":0,";
   json += "\"total_entries\":0,";
   json += "\"total_rejections\":0";
   json += "}";
   return json;
}

string CDashBridgePanels::BuildStateJson(const CDashBridgeProtocol &protocolData,
                                         const CDashBridgeHealth &healthData)
{
   string json = "{";

   json += "\"timestamp\":\"" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\",";

   json += BuildAccountJson() + ",";

   json += BuildPositionsJson() + ",";

   json += protocolData.BuildRiskJson() + ",";

   json += protocolData.BuildPerformanceJson() + ",";

   json += CDashBridgeProtocol::BuildConsensusJson() + ",";

   json += protocolData.BuildAIJson() + ",";

   json += CDashBridgeProtocol::BuildStrategiesJson() + ",";

   json += BuildScalpJson() + ",";

   // Heartbeat carries the live counters supplied by SetHeartbeatCounters.
   json += healthData.BuildHeartbeatJson() + ",";

   json += "\"execution_mode\":\"LIVE_SEND\",";

   json += protocolData.BuildPythonBridgeJson();

   json += "}";

   return json;
}

#endif // CORE_DASHBRIDGE_PANELS_MQH
