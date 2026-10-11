// Heartbeat counter state + heartbeat JSON section for the
// dashboard bridge. Owns the scan/signal/trade/spike counters and
// the "counters have been supplied" flag.
// Extracted verbatim from DashboardBridge.mqh (behaviour unchanged)
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

#ifndef CORE_DASHBRIDGE_HEALTH_MQH
#define CORE_DASHBRIDGE_HEALTH_MQH

// Dashboard Bridge Heartbeat / Health Counters
class CDashBridgeHealth
{
private:
   int                 m_pScansCount;          // Scans performed
   int                 m_pSignalsGenerated;
   int                 m_pSignalsValidated;
   int                 m_pTradesOpened;
   int                 m_pSpikeEvents;         // Spike events observed
   bool                m_heartbeatCountersSet; // Counters supplied at least once

public:
                     CDashBridgeHealth();

   void              SetHeartbeatCounters(int scans, int signalsGen, int signalsVal,
                                          int tradesOpened, int spikeEvents);

   // Serialization
   string            BuildHeartbeatJson() const;
};

CDashBridgeHealth::CDashBridgeHealth()
{
   m_pScansCount = 0;
   m_pSignalsGenerated = 0;
   m_pSignalsValidated = 0;
   m_pTradesOpened = 0;
   m_pSpikeEvents = 0;
   m_heartbeatCountersSet = false;
}

// Set heartbeat counter references
void CDashBridgeHealth::SetHeartbeatCounters(int scans, int signalsGen, int signalsVal,
                                             int tradesOpened, int spikeEvents)
{
   m_pScansCount = scans;
   m_pSignalsGenerated = signalsGen;
   m_pSignalsValidated = signalsVal;
   m_pTradesOpened = tradesOpened;
   m_pSpikeEvents = spikeEvents;
   m_heartbeatCountersSet = true;
}

// Build heartbeat JSON from counters
string CDashBridgeHealth::BuildHeartbeatJson() const
{
   string json = "\"heartbeat\":{";

   if(m_heartbeatCountersSet)
   {
      json += "\"scans\":" + IntegerToString(m_pScansCount) + ",";
      json += "\"signals_generated\":" + IntegerToString(m_pSignalsGenerated) + ",";
      json += "\"signals_validated\":" + IntegerToString(m_pSignalsValidated) + ",";
      json += "\"trades_opened\":" + IntegerToString(m_pTradesOpened) + ",";
      json += "\"spike_events\":" + IntegerToString(m_pSpikeEvents);
   }
   else
   {
      json += "\"scans\":0,";
      json += "\"signals_generated\":0,";
      json += "\"signals_validated\":0,";
      json += "\"trades_opened\":0,";
      json += "\"spike_events\":0";
   }

   json += "}";
   return json;
}

#endif // CORE_DASHBRIDGE_HEALTH_MQH
