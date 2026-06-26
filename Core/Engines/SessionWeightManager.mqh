//+------------------------------------------------------------------+
//| SessionWeightManager.mqh                                          |
//| Session-aware weight adjustments for synthetics and forex         |
//| Implements I3 from problems.md                                    |
//+------------------------------------------------------------------+
#ifndef CORE_ENGINES_SESSION_WEIGHT_MANAGER_MQH
#define CORE_ENGINES_SESSION_WEIGHT_MANAGER_MQH

struct SSessionWeights
{
   double sizingMultiplier;
   double convictionThresholdAdj;
   double readinessBoost;
   string sessionName;
};

class CSessionWeightManager
{
private:
   bool m_initialized;
   bool m_syntheticMode;

   SSessionWeights GetSessionWeightsForTime(datetime time)
   {
      MqlDateTime dt;
      TimeToStruct(time, dt);
      int hour = dt.hour;
      int dayOfWeek = dt.day_of_week;

      SSessionWeights sw;
      sw.sizingMultiplier = 1.0;
      sw.convictionThresholdAdj = 0.0;
      sw.readinessBoost = 0.0;
      sw.sessionName = "UNKNOWN";

      if(dayOfWeek == 0 || dayOfWeek == 6)
      {
         sw.sizingMultiplier = 1.2;
         sw.convictionThresholdAdj = -0.03;
         sw.readinessBoost = 0.05;
         sw.sessionName = "WEEKEND";
         return sw;
      }

      if(hour >= 0 && hour < 8)
      {
         sw.sizingMultiplier = 1.1;
         sw.convictionThresholdAdj = 0.0;
         sw.readinessBoost = 0.02;
         sw.sessionName = "ASIAN";
      }
      else if(hour >= 8 && hour < 13)
      {
         sw.sizingMultiplier = 0.95;
         sw.convictionThresholdAdj = 0.01;
         sw.readinessBoost = 0.0;
         sw.sessionName = "LONDON_PRE";
      }
      else if(hour >= 13 && hour < 21)
      {
         sw.sizingMultiplier = 0.85;
         sw.convictionThresholdAdj = 0.02;
         sw.readinessBoost = -0.02;
         sw.sessionName = "LONDON_NY_OVERLAP";
      }
      else
      {
         sw.sizingMultiplier = 1.0;
         sw.convictionThresholdAdj = 0.0;
         sw.readinessBoost = 0.0;
         sw.sessionName = "NY_LATE";
      }

      return sw;
   }

public:
   CSessionWeightManager() : m_initialized(false), m_syntheticMode(true) {}

   bool Initialize(bool syntheticMode = true)
   {
      m_syntheticMode = syntheticMode;
      m_initialized = true;
      Print("[SESSION-WEIGHT-MGR] Initialized | mode=", syntheticMode ? "SYNTHETIC" : "FOREX");
      return true;
   }

   SSessionWeights GetCurrentSessionWeights()
   {
      if(!m_initialized)
      {
         SSessionWeights def;
         def.sizingMultiplier = 1.0;
         def.convictionThresholdAdj = 0.0;
         def.readinessBoost = 0.0;
         def.sessionName = "UNINITIALIZED";
         return def;
      }
      return GetSessionWeightsForTime(TimeCurrent());
   }

   SSessionWeights GetSessionWeights(datetime time)
   {
      if(!m_initialized)
      {
         SSessionWeights def;
         def.sizingMultiplier = 1.0;
         def.convictionThresholdAdj = 0.0;
         def.readinessBoost = 0.0;
         def.sessionName = "UNINITIALIZED";
         return def;
      }
      return GetSessionWeightsForTime(time);
   }

   double ApplySizingMultiplier(double baseLotSize)
   {
      SSessionWeights sw = GetCurrentSessionWeights();
      return baseLotSize * sw.sizingMultiplier;
   }

   double GetAdjustedThreshold(double baseThreshold)
   {
      SSessionWeights sw = GetCurrentSessionWeights();
      double adjusted = baseThreshold + sw.convictionThresholdAdj;
      return MathMax(0.30, MathMin(0.95, adjusted));
   }

   double GetReadinessBoost()
   {
      SSessionWeights sw = GetCurrentSessionWeights();
      return sw.readinessBoost;
   }

   bool IsWeekend()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      return (dt.day_of_week == 0 || dt.day_of_week == 6);
   }

   bool IsInitialized() const { return m_initialized; }
};

#endif // CORE_ENGINES_SESSION_WEIGHT_MANAGER_MQH
