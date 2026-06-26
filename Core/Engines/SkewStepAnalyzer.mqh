//+------------------------------------------------------------------+
//| SkewStepAnalyzer.mqh                                              |
//| Step-size distribution analyzer for Skew Step indices             |
//| Implements I4 from problems.md                                    |
//+------------------------------------------------------------------+
#ifndef CORE_ENGINES_SKEW_STEP_ANALYZER_MQH
#define CORE_ENGINES_SKEW_STEP_ANALYZER_MQH

enum ENUM_SKEW_STEP_PHASE
{
   SKEW_PHASE_CALM,
   SKEW_PHASE_TRANSITION,
   SKEW_PHASE_POST_SPIKE,
   SKEW_PHASE_COUNTER_DUE
};

struct SSkewStepAnalysisResult
{
   ENUM_SKEW_STEP_PHASE phase;
   double phaseScore;
   double sizingMultiplier;
   double counterMoveProbability;
   int    stepsSinceLastLarge;
   int    smallStepCount;
   int    largeStepCount;
   bool   isCounterMoveDue;
};

class CSkewStepAnalyzer
{
private:
   double m_stepBuffer[];
   int    m_bufferSize;
   int    m_currentIndex;
   int    m_totalSteps;
   double m_calmThreshold;
   double m_smallStepThreshold;
   double m_largeStepThreshold;
   bool   m_initialized;
   SSkewStepAnalysisResult m_lastResult;

   void RecalculatePhase()
   {
      int count = MathMin(m_totalSteps, m_bufferSize);
      if(count < 10)
      {
         m_lastResult.phase = SKEW_PHASE_CALM;
         m_lastResult.phaseScore = 1.0;
         m_lastResult.sizingMultiplier = 1.0;
         m_lastResult.counterMoveProbability = 0.15;
         m_lastResult.stepsSinceLastLarge = count;
         m_lastResult.smallStepCount = 0;
         m_lastResult.largeStepCount = 0;
         m_lastResult.isCounterMoveDue = false;
         return;
      }

      int smallCount = 0;
      int largeCount = 0;
      int stepsSinceLarge = 0;
      bool foundLarge = false;

      for(int i = 0; i < count; i++)
      {
         int idx = (m_currentIndex - 1 - i + m_bufferSize * 2) % m_bufferSize;
         double mag = MathAbs(m_stepBuffer[idx]);

         if(mag >= m_largeStepThreshold)
         {
            largeCount++;
            if(!foundLarge)
            {
               stepsSinceLarge = i;
               foundLarge = true;
            }
         }
         else if(mag < m_smallStepThreshold)
         {
            smallCount++;
         }
      }

      double phaseScore = (double)smallCount / count;
      m_lastResult.phaseScore = phaseScore;
      m_lastResult.smallStepCount = smallCount;
      m_lastResult.largeStepCount = largeCount;
      m_lastResult.stepsSinceLastLarge = foundLarge ? stepsSinceLarge : count;

      double observedRate = (double)largeCount / count;
      m_lastResult.counterMoveProbability = MathMax(0.05, MathMin(0.50, observedRate));

      double expectedStepsBetweenLarge = (observedRate > 0.001) ? (1.0 / observedRate) : 100.0;
      m_lastResult.isCounterMoveDue = (m_lastResult.stepsSinceLastLarge > expectedStepsBetweenLarge * 2.0);

      if(phaseScore >= m_calmThreshold)
      {
         m_lastResult.phase = SKEW_PHASE_CALM;
         m_lastResult.sizingMultiplier = 1.3;
      }
      else if(m_lastResult.isCounterMoveDue)
      {
         m_lastResult.phase = SKEW_PHASE_COUNTER_DUE;
         m_lastResult.sizingMultiplier = 0.5;
      }
      else if(stepsSinceLarge <= 5 && foundLarge)
      {
         m_lastResult.phase = SKEW_PHASE_POST_SPIKE;
         m_lastResult.sizingMultiplier = 0.6;
      }
      else
      {
         m_lastResult.phase = SKEW_PHASE_TRANSITION;
         m_lastResult.sizingMultiplier = 1.0;
      }
   }

public:
   CSkewStepAnalyzer() : m_bufferSize(0), m_currentIndex(0), m_totalSteps(0),
      m_calmThreshold(0.80), m_smallStepThreshold(0.2), m_largeStepThreshold(0.5),
      m_initialized(false) {}

   bool Initialize(int bufferSize = 200, double calmThreshold = 0.80,
                   double smallStepThreshold = 0.2, double largeStepThreshold = 0.5)
   {
      m_bufferSize = bufferSize;
      m_calmThreshold = calmThreshold;
      m_smallStepThreshold = smallStepThreshold;
      m_largeStepThreshold = largeStepThreshold;
      m_currentIndex = 0;
      m_totalSteps = 0;

      ArrayResize(m_stepBuffer, m_bufferSize);
      ArrayInitialize(m_stepBuffer, 0.0);

      m_initialized = true;
      Print("[SKEW-STEP-ANALYZER] Initialized | bufferSize=", bufferSize,
            " | calmThreshold=", calmThreshold);
      return true;
   }

   void RecordStep(double stepSize)
   {
      if(!m_initialized) return;

      m_stepBuffer[m_currentIndex % m_bufferSize] = stepSize;
      m_currentIndex++;
      if(m_totalSteps < m_bufferSize)
         m_totalSteps++;

      RecalculatePhase();
   }

   SSkewStepAnalysisResult GetLastResult() const { return m_lastResult; }
   double GetSizingMultiplier() const { return m_lastResult.sizingMultiplier; }
   ENUM_SKEW_STEP_PHASE GetPhase() const { return m_lastResult.phase; }
   bool IsCounterMoveDue() const { return m_lastResult.isCounterMoveDue; }

   string GetPhaseName() const
   {
      switch(m_lastResult.phase)
      {
         case SKEW_PHASE_CALM:         return "CALM";
         case SKEW_PHASE_TRANSITION:   return "TRANSITION";
         case SKEW_PHASE_POST_SPIKE:   return "POST_SPIKE";
         case SKEW_PHASE_COUNTER_DUE:  return "COUNTER_DUE";
         default:                      return "UNKNOWN";
      }
   }

   string GetDiagnostics() const
   {
      return StringFormat("phase=%s | score=%.2f | sizing=%.2f | P(counter)=%.2f | stepsSinceLarge=%d | small=%d | large=%d",
                          GetPhaseName(), m_lastResult.phaseScore, m_lastResult.sizingMultiplier,
                          m_lastResult.counterMoveProbability, m_lastResult.stepsSinceLastLarge,
                          m_lastResult.smallStepCount, m_lastResult.largeStepCount);
   }

   bool IsInitialized() const { return m_initialized; }
   int GetTotalStepsRecorded() const { return m_totalSteps; }
};

#endif // CORE_ENGINES_SKEW_STEP_ANALYZER_MQH
