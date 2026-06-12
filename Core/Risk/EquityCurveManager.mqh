//+------------------------------------------------------------------+
//| EquityCurveManager.mqh                                           |
//| Equity curve trading — reduces position size when equity drops   |
//| below its EMA. Research shows 15-30% max DD reduction.          |
//+------------------------------------------------------------------+
#ifndef CORE_RISK_EQUITY_CURVE_MANAGER_MQH
#define CORE_RISK_EQUITY_CURVE_MANAGER_MQH

#include "../Utils/CommonTypes.mqh"

//+------------------------------------------------------------------+
//| Equity Curve Manager Class                                       |
//| Tracks rolling equity via circular buffer, computes EMA, and     |
//| returns a position size multiplier based on whether equity is    |
//| above or below its moving average.                               |
//+------------------------------------------------------------------+
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
   //+------------------------------------------------------------------+
   //| Constructor                                                      |
   //+------------------------------------------------------------------+
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

   //+------------------------------------------------------------------+
   //| Destructor                                                       |
   //+------------------------------------------------------------------+
   ~CEquityCurveManager()
   {
      ArrayFree(m_equityHistory);
   }

   //+------------------------------------------------------------------+
   //| Update — call every evaluation cycle with current equity        |
   //| Adds equity to circular buffer, calculates EMA                  |
   //+------------------------------------------------------------------+
   void Update(double equityValue)
   {
      if(equityValue <= 0.0)
         return;

      // Store in circular buffer
      m_equityHistory[m_currentIndex] = equityValue;
      m_currentIndex = (m_currentIndex + 1) % m_historySize;
      if(m_filledCount < m_historySize)
         m_filledCount++;

      // Not enough data for EMA — seed with SMA on first full window
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
         // Standard EMA formula: EMA = price * k + prevEMA * (1 - k)
         double k = 2.0 / (m_emaPeriod + 1.0);
         m_currentEma = equityValue * k + m_currentEma * (1.0 - k);
      }

      // Detect state transition
      bool wasBelow = m_isEquityBelowEma;
      m_isEquityBelowEma = (equityValue < m_currentEma);

      // Log state transitions only
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

   //+------------------------------------------------------------------+
   //| Get position size multiplier based on equity curve state        |
   //| Below EMA → reductionFactor, above EMA → recoveryFactor        |
   //| Insufficient data → 1.0 (no adjustment)                        |
   //+------------------------------------------------------------------+
   double GetPositionSizeMultiplier() const
   {
      if(m_filledCount < m_emaPeriod)
         return 1.0;  // Not enough data — no adjustment

      return m_isEquityBelowEma ? m_reductionFactor : m_recoveryFactor;
   }

   //+------------------------------------------------------------------+
   //| Get current state                                                |
   //+------------------------------------------------------------------+
   bool   IsEquityBelowEma() const { return m_isEquityBelowEma; }
   double GetCurrentEma()    const { return m_currentEma; }
   int    GetFilledCount()   const { return m_filledCount; }
   int    GetEmaPeriod()     const { return m_emaPeriod; }

   //+------------------------------------------------------------------+
   //| Reset — clear all history and state                              |
   //+------------------------------------------------------------------+
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
