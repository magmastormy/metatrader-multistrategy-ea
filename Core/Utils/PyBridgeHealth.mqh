// Heartbeat / health monitoring, reconnection backoff, server
// version negotiation and the NOT_CONFIGURED log throttle.
// Owns the heartbeat/reconnect/version state; the transport is
// supplied by reference so no ownership cycle is created.
// Extracted verbatim from PythonBridge.mqh (behaviour unchanged).
#property copyright "Copyright 2025"
#property link      ""
#property version   "1.00"
#property strict

#ifndef CORE_PYBRIDGE_HEALTH_MQH
#define CORE_PYBRIDGE_HEALTH_MQH

#include "Enums.mqh"
#include "PyBridgeTypes.mqh"
#include "PyBridgeProtocol.mqh"
#include "PyBridgeTransport.mqh"

// Python Bridge Health / Reconnection Monitor
class CPyBridgeHealth
{
private:
   int                  m_heartbeat_timeout;
   datetime             m_last_heartbeat;          // Last successful heartbeat
   datetime             m_last_reconnect;          // Last reconnection attempt
   int                  m_reconnect_attempts;      // Number of reconnect attempts
   int                  m_max_reconnect_attempts;
   int                  m_reconnect_backoff;
   SPythonBridgeVersion m_server_version;          // Server version info
   datetime             m_lastNotConfiguredLogTime;// Throttle NOT_CONFIGURED dashboard logs

public:
                     CPyBridgeHealth();

   // Lifecycle
   void              Configure(int heartbeat_timeout_s, int max_reconnect_attempts,
                               int reconnect_backoff_ms);
   void              Reset();

   bool              CheckHealth(CPyBridgeTransport &transport);
   bool              SendHeartbeat(CPyBridgeTransport &transport);
   bool              AttemptReconnect(CPyBridgeTransport &transport);
   SPythonBridgeHealthStatus GetHealthStatus(const CPyBridgeTransport &transport) const;

   bool              CheckVersion(CPyBridgeTransport &transport);
   SPythonBridgeVersion GetServerVersion() const { return m_server_version; }

   // Utility
   bool              ShouldLogNotConfigured();
   void              MarkHeartbeat(datetime heartbeat_time) { m_last_heartbeat = heartbeat_time; }
};

// Constructor - defaults identical to the original CPythonBridge
CPyBridgeHealth::CPyBridgeHealth()
{
   m_heartbeat_timeout = 30;
   m_last_heartbeat = 0;
   m_last_reconnect = 0;
   m_reconnect_attempts = 0;
   m_max_reconnect_attempts = 5;
   m_reconnect_backoff = 2000;
   m_lastNotConfiguredLogTime = 0;
}

// Apply the health configuration supplied to Initialize()
void CPyBridgeHealth::Configure(int heartbeat_timeout_s, int max_reconnect_attempts,
                                int reconnect_backoff_ms)
{
   m_heartbeat_timeout = heartbeat_timeout_s;
   m_max_reconnect_attempts = max_reconnect_attempts;
   m_reconnect_backoff = reconnect_backoff_ms;
}

// Reset all health-owned state (Shutdown semantics)
void CPyBridgeHealth::Reset()
{
   m_heartbeat_timeout = 0;
   m_last_heartbeat = 0;
   m_last_reconnect = 0;
   m_reconnect_attempts = 0;
   m_max_reconnect_attempts = 0;
   m_reconnect_backoff = 0;
   m_lastNotConfiguredLogTime = 0;
   m_server_version.version = "";
   m_server_version.compatible = false;
}

// Check server health
bool CPyBridgeHealth::CheckHealth(CPyBridgeTransport &transport)
{
   if(transport.GetMode() == PYTHON_BRIDGE_OFF)
      return false;
   
   string response;
   string healthUrl = transport.GetEndpoint() + "/health";
   bool success = transport.SendHttpRequest("GET", healthUrl, "", response);
   
   if(success && StringFind(response, "\"status\":\"healthy\"") != -1)
   {
      m_last_heartbeat = TimeCurrent();
      if(transport.GetState() != PYTHON_BRIDGE_CONNECTED)
      {
         transport.SetState(PYTHON_BRIDGE_CONNECTED);
         m_reconnect_attempts = 0;
         transport.LogBridgeState("Python bridge connection restored");
      }
      return true;
   }
   else
   {
      // Handle disconnection
      if(transport.GetState() == PYTHON_BRIDGE_CONNECTED)
      {
         transport.SetState(PYTHON_BRIDGE_DISCONNECTED);
         transport.LogBridgeState("Python bridge disconnected - will attempt reconnection", ERROR_LEVEL_WARNING);
      }
      return AttemptReconnect(transport);
   }
}

bool CPyBridgeHealth::SendHeartbeat(CPyBridgeTransport &transport)
{
   if(transport.GetMode() == PYTHON_BRIDGE_OFF)
      return false;
   
   string response;
   string heartbeatUrl = transport.GetEndpoint() + "/heartbeat";
   bool success = transport.SendHttpRequest("GET", heartbeatUrl, "", response);
   
   if(success && StringFind(response, "\"status\":\"ok\"") != -1)
   {
      m_last_heartbeat = TimeCurrent();
      if(transport.GetState() != PYTHON_BRIDGE_CONNECTED)
      {
         transport.SetState(PYTHON_BRIDGE_CONNECTED);
         m_reconnect_attempts = 0;
         transport.LogBridgeState("Python bridge connection restored via heartbeat");
      }
      return true;
   }
   else
   {
      if(transport.GetState() == PYTHON_BRIDGE_CONNECTED)
      {
         transport.SetState(PYTHON_BRIDGE_DISCONNECTED);
         transport.LogBridgeState("Python bridge heartbeat failed", ERROR_LEVEL_WARNING);
      }
      return AttemptReconnect(transport);
   }
}

bool CPyBridgeHealth::AttemptReconnect(CPyBridgeTransport &transport)
{
   if(transport.GetMode() == PYTHON_BRIDGE_OFF)
      return false;
   
   datetime now = TimeCurrent();
   
   if((now - m_last_reconnect) < (m_reconnect_backoff / 1000))
      return false;
   
   if(m_reconnect_attempts >= m_max_reconnect_attempts)
   {
      if(transport.GetState() != PYTHON_BRIDGE_ERROR)
      {
         // In OBSERVE mode, Python sidecar is optional — stay DISCONNECTED, not ERROR
         if(transport.GetMode() == PYTHON_BRIDGE_OBSERVE)
         {
            transport.SetState(PYTHON_BRIDGE_DISCONNECTED);
            transport.LogBridgeState("Max reconnection attempts reached - Python sidecar not available (OBSERVE mode, using local AI fallback)", ERROR_LEVEL_WARNING);
         }
         else
         {
            transport.SetState(PYTHON_BRIDGE_ERROR);
            transport.LogBridgeState("Max reconnection attempts reached - using local AI fallback", ERROR_LEVEL_ERROR);
         }
      }
      return false;
   }
   
   m_last_reconnect = now;
   m_reconnect_attempts++;
   transport.SetState(PYTHON_BRIDGE_CONNECTING);
   
   string reconnectMsg = "Attempting reconnection (" + IntegerToString(m_reconnect_attempts) + 
                         "/" + IntegerToString(m_max_reconnect_attempts) + ")...";
   transport.LogBridgeState(reconnectMsg);
   
   // Try health check
   string response;
   string healthUrl = transport.GetEndpoint() + "/health";
   bool success = transport.SendHttpRequest("GET", healthUrl, "", response);
   
   if(success && StringFind(response, "\"status\":\"healthy\"") != -1)
   {
      transport.SetState(PYTHON_BRIDGE_CONNECTED);
      m_reconnect_attempts = 0;
      m_last_heartbeat = now;
      transport.LogBridgeState("Reconnection successful!");
      return true;
   }
   else
   {
      // Exponential backoff (explicit cast: MathMin returns double)
      m_reconnect_backoff = (int)MathMin(m_reconnect_backoff * 2, 30000);
      transport.SetState(PYTHON_BRIDGE_DISCONNECTED);
      return false;
   }
}

// Check server version
bool CPyBridgeHealth::CheckVersion(CPyBridgeTransport &transport)
{
   if(transport.GetMode() == PYTHON_BRIDGE_OFF || !transport.IsInitialized())
      return false;
   
   string response;
   string versionUrl = transport.GetEndpoint() + "/version";
   if(transport.SendHttpRequest("GET", versionUrl, "", response))
   {
      if(CPyBridgeProtocol::ParseVersionResponse(response, m_server_version))
      {
         if(m_server_version.compatible)
         {
            transport.LogBridgeState("Python bridge version OK: " + m_server_version.version);
            return true;
         }
         else
         {
            transport.LogBridgeState("Python bridge version incompatible! Required: " + 
                          IntegerToString(1) + "." + IntegerToString(0) + 
                          ", Got: " + m_server_version.version, ERROR_LEVEL_ERROR);
            transport.SetState(PYTHON_BRIDGE_ERROR);
            return false;
         }
      }
   }
   
   transport.LogBridgeState("Failed to check Python bridge version", ERROR_LEVEL_WARNING);
   return false;
}

SPythonBridgeHealthStatus CPyBridgeHealth::GetHealthStatus(const CPyBridgeTransport &transport) const
{
   SPythonBridgeHealthStatus status;
   
   status.state = transport.GetState();
   status.connected = transport.IsConnected();
   status.healthy = (transport.GetState() == PYTHON_BRIDGE_CONNECTED && 
                     (TimeCurrent() - m_last_heartbeat) < m_heartbeat_timeout);
   status.last_heartbeat = m_last_heartbeat;
   status.reconnect_attempts = m_reconnect_attempts;
   status.request_count = transport.GetRequestCount();
   status.success_count = transport.GetSuccessCount();
   status.error_count = transport.GetErrorCount();
   status.last_error = transport.GetLastError();
   status.version = m_server_version;
   
   return status;
}

// Should log NOT_CONFIGURED dashboard entry (throttled to 300s)
bool CPyBridgeHealth::ShouldLogNotConfigured()
{
   datetime now = TimeCurrent();
   if(m_lastNotConfiguredLogTime == 0 || (now - m_lastNotConfiguredLogTime) >= 300)
   {
      m_lastNotConfiguredLogTime = now;
      return true;
   }
   return false;
}

#endif // CORE_PYBRIDGE_HEALTH_MQH
