// Owns the push-alert throttle state (last alert tick + count) and every SendNotification branch.
// Holds SSpikeHunterConfig by value, assigned in the engine's Init(); before that the default copy carries the
// same production defaults, so an alert fired pre-Init behaves as the original inline code did.
#property strict

#ifndef CORE_SCALP_SPIKE_HUNTER_ALERTS_MQH
#define CORE_SCALP_SPIKE_HUNTER_ALERTS_MQH

#include "SpikeHunterTypes.mqh"

class CSpikeHunterAlerts
{
private:
   SSpikeHunterConfig   m_config;
   ulong                m_lastPushAlertTick;    // L10-016: Use GetTickCount() instead of TimeCurrent()
   int                  m_pushAlertCount;

public:
   CSpikeHunterAlerts() :
      m_lastPushAlertTick(0),
      m_pushAlertCount(0)
   {
   }

   //--- Config injection (mirrors CSpikeHunterEngine::Init assignment)
   void SetConfig(const SSpikeHunterConfig &config) { m_config = config; }

   int GetAlertCount() const { return m_pushAlertCount; }

   void SendThrottledAlert(const string message)
   {
      if(!m_config.enablePushAlerts)
         return;

      // L10-016: Use GetTickCount() (millisecond) instead of TimeCurrent() (second resolution)
      ulong now = GetTickCount();
      int elapsedMs = (int)(now - m_lastPushAlertTick);
      int throttleMs = m_config.alertThrottleSeconds * 1000;

      if(elapsedMs < throttleMs)
      {
         PrintFormat("[SPIKE-HUNT-ALERT-THROTTLED] Alert suppressed (last sent %d ms ago)", elapsedMs);
         return;
      }

      if(SendNotification(message))
      {
         m_lastPushAlertTick = now;
         m_pushAlertCount++;
         PrintFormat("[SPIKE-HUNT-ALERT] Push notification sent: %s", message);
      }
      else
      {
         PrintFormat("[SPIKE-HUNT-ALERT-FAILED] SendNotification failed for: %s", message);
      }
   }
};

#endif // CORE_SCALP_SPIKE_HUNTER_ALERTS_MQH
