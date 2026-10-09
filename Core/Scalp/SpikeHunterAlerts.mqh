// Owns the push-notification throttle state (last alert tick + alert count).
// SendThrottledAlert() — enable gate, GetTickCount() delta vs
// alertThrottleSeconds*1000, SendNotification() success/failure
// branches and all three log tags.
// The module keeps its own by-value copy of SSpikeHunterConfig.
// The engine assigns it in Init() exactly where m_config was
// assigned; before Init() the default-constructed copy carries the
// identical production defaults, so the pre-Init behaviour of the
// original (enablePushAlerts=true, throttle=120s) is unchanged.
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
