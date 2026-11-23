// Conservative risk-tier configuration and status reporting.
#ifndef CORE_RISK_SAFE_MODE_CONFIG_MQH
#define CORE_RISK_SAFE_MODE_CONFIG_MQH

struct SSafeModeConfig
{
   double minConfidence;
   int    minVoters;
   double minQuorumThreshold;
   bool   noStacking;
   double maxSpreadATRRatio;

   SSafeModeConfig()
   {
      minConfidence      = 0.70;
      minVoters          = 3;
      minQuorumThreshold = 0.65;
      noStacking         = true;
      maxSpreadATRRatio  = 0.15;
   }
};

class CSafeMode
{
private:
   SSafeModeConfig m_config;
   bool            m_initialized;

   bool IsWithinFxKillZone() const
   {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      return (dt.hour >= 7 && dt.hour < 10) || (dt.hour >= 12 && dt.hour < 15);
   }

public:
   CSafeMode() : m_initialized(false) {}

   bool IsInitialized() const { return m_initialized; }

   bool Initialize(const SSafeModeConfig &config)
   {
      m_config = config;
      m_initialized = true;
      PrintFormat("[SAFE-MODE] Initialized | minConf=%.2f | minVoters=%d | quorum=%.2f | noStack=%s | spreadATR=%.2f",
                  m_config.minConfidence,
                  m_config.minVoters,
                  m_config.minQuorumThreshold,
                  m_config.noStacking ? "YES" : "NO",
                  m_config.maxSpreadATRRatio);
      return true;
   }

   SSafeModeConfig GetConfig() const { return m_config; }

   void PrintDiagnostics() const
   {
      PrintFormat("[SAFE-MODE-DIAG] initialized=%s | fxSessionWindow=%s | minConf=%.2f | minVoters=%d | quorum=%.2f | noStack=%s | spreadATR=%.2f",
                  m_initialized ? "true" : "false",
                  IsWithinFxKillZone() ? "IN" : "OUT",
                  m_config.minConfidence,
                  m_config.minVoters,
                  m_config.minQuorumThreshold,
                  m_config.noStacking ? "YES" : "NO",
                  m_config.maxSpreadATRRatio);
   }
};

#endif // CORE_RISK_SAFE_MODE_CONFIG_MQH
