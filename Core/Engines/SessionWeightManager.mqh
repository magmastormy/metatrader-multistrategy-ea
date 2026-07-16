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

   double m_sessionATRHistory[5][24];
   int    m_atrHistoryCount;
   double m_typicalATR[24];
   double m_currentSessionATR;

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
            // Batch 118: Only apply weekend boost for synthetics (forex markets are closed)
            if(m_syntheticMode)
            {
               sw.sizingMultiplier = 1.2;
               sw.convictionThresholdAdj = -0.03;
               sw.readinessBoost = 0.05;
            }
            else
            {
               sw.sizingMultiplier = 0.5;  // Penalize forex weekend trading
               sw.convictionThresholdAdj = 0.10;
               sw.readinessBoost = 0.0;
            }
            sw.sessionName = "WEEKEND";
            return sw;
         }

         // For synthetic symbols in synthetic mode: bypass ALL session adjustments (trade 24/7)
         if(m_syntheticMode)
         {
            sw.sizingMultiplier = 1.0;
            sw.convictionThresholdAdj = 0.0;
            sw.readinessBoost = 0.0;
            sw.sessionName = "SYNTHETIC_24_7";
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
           // FIX: London/NY overlap is the BEST session - should have HIGHEST multiplier, not penalty
           sw.sizingMultiplier = 1.2;
           sw.convictionThresholdAdj = -0.02;
           sw.readinessBoost = 0.05;
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
   CSessionWeightManager() : m_initialized(false), m_syntheticMode(true), m_atrHistoryCount(0), m_currentSessionATR(0.0)
   {
      ArrayInitialize(m_typicalATR, 0.0);
      for(int d = 0; d < 5; d++)
         for(int h = 0; h < 24; h++)
            m_sessionATRHistory[d][h] = 0.0;
   }

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

   void TrackATR(double atr)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;
      int dayOfWeek = dt.day_of_week;

      if(dayOfWeek < 1 || dayOfWeek > 5)
         return;

      int dayIndex = dayOfWeek - 1;
      if(dayIndex < 0 || dayIndex >= 5)
         return;

      m_sessionATRHistory[dayIndex][hour] = atr;
      m_currentSessionATR = atr;

      int totalSamples = 0;
      double sumATR[24];
      int countATR[24];
      ArrayInitialize(sumATR, 0.0);
      ArrayInitialize(countATR, 0);

      for(int d = 0; d < 5; d++)
      {
         for(int h = 0; h < 24; h++)
         {
            if(m_sessionATRHistory[d][h] > 0.0)
            {
               sumATR[h] += m_sessionATRHistory[d][h];
               countATR[h]++;
               totalSamples++;
            }
         }
      }

      m_atrHistoryCount = totalSamples;

      for(int h = 0; h < 24; h++)
      {
         if(countATR[h] > 0)
            m_typicalATR[h] = sumATR[h] / countATR[h];
         else
            m_typicalATR[h] = 0.0;
      }
   }

   double GetTypicalATR(int hour)
   {
      if(hour < 0 || hour >= 24)
         return 0.0;
      return m_typicalATR[hour];
   }

   double GetVolatilityMultiplier()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;

      double typical = m_typicalATR[hour];
      if(typical <= 0.0 || m_currentSessionATR <= 0.0)
         return 1.0;

      double ratio = m_currentSessionATR / typical;

      if(ratio < 0.7)
         return 1.2;
      else if(ratio > 1.5)
         return 0.8;
      else
         return 1.0;
   }

   bool IsHighVolatilitySession()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;

      double typical = m_typicalATR[hour];
      if(typical <= 0.0 || m_currentSessionATR <= 0.0)
         return false;

      return (m_currentSessionATR / typical) > 1.5;
   }

   bool IsLowVolatilitySession()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      int hour = dt.hour;

      double typical = m_typicalATR[hour];
      if(typical <= 0.0 || m_currentSessionATR <= 0.0)
         return false;

      return (m_currentSessionATR / typical) < 0.7;
   }
};

#endif // CORE_ENGINES_SESSION_WEIGHT_MANAGER_MQH
