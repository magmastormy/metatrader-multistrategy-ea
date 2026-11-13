// Equity curve trading: reduces position size while equity sits below its EMA.
#ifndef CORE_RISK_EQUITY_CURVE_MANAGER_MQH
#define CORE_RISK_EQUITY_CURVE_MANAGER_MQH

#include "../Utils/CommonTypes.mqh"

// Rolling equity (circular buffer) -> EMA -> position size multiplier.
class CEquityCurveManager
{
private:
   double m_equityHistory[];    // Rolling equity history (circular buffer)
   int    m_historySize;        // Max history size (= emaPeriod)
   int    m_currentIndex;       // Circular buffer write index
   int    m_filledCount;        // Number of filled entries
   int    m_emaPeriod;          // EMA period for equity curve
   double m_reductionFactor;    // Position size reduction when equity < EMA (0.50 = half size)
   double m_recoveryFactor;     // Position size multiplier when equity >= EMA (1.0 = normal)
   double m_currentEma;         // Current equity EMA value
   bool   m_isEquityBelowEma;   // Current state

public:
   CEquityCurveManager(int emaPeriod = 20, double reductionFactor = 0.50, double recoveryFactor = 1.0) :
      m_historySize(emaPeriod),
      m_currentIndex(0),
      m_filledCount(0),
      m_emaPeriod(emaPeriod),
      m_reductionFactor(reductionFactor),
      m_recoveryFactor(recoveryFactor),
      m_currentEma(0.0),
      m_isEquityBelowEma(false)
   {
      if(m_emaPeriod < 2)
         m_emaPeriod = 2;
      m_historySize = m_emaPeriod;
      ArrayResize(m_equityHistory, m_historySize);
      ArrayInitialize(m_equityHistory, 0.0);
   }

   ~CEquityCurveManager()
   {
      ArrayFree(m_equityHistory);
   }

// Update — call every evaluation cycle with current equity
   void Update(double equityValue)
   {
      if(equityValue <= 0.0)
         return;

      m_equityHistory[m_currentIndex] = equityValue;
      m_currentIndex = (m_currentIndex + 1) % m_historySize;
      if(m_filledCount < m_historySize)
         m_filledCount++;

      // Data gap: below emaPeriod samples the EMA is undefined, so state stays "not below" (no size cut)
      if(m_filledCount < m_emaPeriod)
      {
         m_currentEma = 0.0;
         m_isEquityBelowEma = false;
         return;
      }

      // First full window: compute SMA as EMA seed
      if(m_currentEma <= 0.0)
      {
         double sum = 0.0;
         for(int i = 0; i < m_historySize; i++)
            sum += m_equityHistory[i];
         m_currentEma = sum / m_historySize;
      }
      else
      {
         double k = 2.0 / (m_emaPeriod + 1.0);
         m_currentEma = equityValue * k + m_currentEma * (1.0 - k);
      }

      bool wasBelow = m_isEquityBelowEma;
      // Dead band: the cut arms only once equity is 0.25% under its EMA and clears when it is back at
      // the EMA. A bare `equity < ema` on floating equity sampled every cycle is a coin toss: the
      // 2026-11-13 demo journal flipped 191 times in 24 minutes on moves of 10-30 cents against a
      // 14,027 balance ("Equity=14027.02 below EMA=14027.11, position size reduced to 50%"), so half
      // of all lots were halved by spread noise.
      if(wasBelow)
         m_isEquityBelowEma = (equityValue < m_currentEma);
      else
         m_isEquityBelowEma = (equityValue < m_currentEma * (1.0 - 0.0025));

      if(m_isEquityBelowEma && !wasBelow)
      {
         PrintFormat("[EQUITY-CURVE-BELOW] Equity=%.2f below EMA=%.2f, position size reduced to %.0f%%",
                     equityValue, m_currentEma, m_reductionFactor * 100.0);
      }
      else if(!m_isEquityBelowEma && wasBelow)
      {
         PrintFormat("[EQUITY-CURVE-ABOVE] Equity=%.2f above EMA=%.2f, position size restored to %.0f%%",
                     equityValue, m_currentEma, m_recoveryFactor * 100.0);
      }
   }

// Position-size multiplier: below EMA → reductionFactor, at/above → recoveryFactor, insufficient history → 1.0
   double GetPositionSizeMultiplier() const
   {
      if(m_filledCount < m_emaPeriod)
         return 1.0;  // Not enough data — no adjustment

      return m_isEquityBelowEma ? m_reductionFactor : m_recoveryFactor;
   }

   bool   IsEquityBelowEma() const { return m_isEquityBelowEma; }
   double GetCurrentEma()    const { return m_currentEma; }
   int    GetFilledCount()   const { return m_filledCount; }
   int    GetEmaPeriod()     const { return m_emaPeriod; }

   void Reset()
   {
      ArrayInitialize(m_equityHistory, 0.0);
      m_currentIndex = 0;
      m_filledCount = 0;
      m_currentEma = 0.0;
      m_isEquityBelowEma = false;
      Print("[EQUITY-CURVE] Reset — history cleared");
   }
};

#endif // CORE_RISK_EQUITY_CURVE_MANAGER_MQH
