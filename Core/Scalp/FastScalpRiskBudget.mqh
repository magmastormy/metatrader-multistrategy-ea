// Owns the scalp risk-budget accumulator (used risk percent).
// The tracker lookup stays on the caller side (FastScalpExit) so
// this module has no dependency on CFastScalpPositionTracker and
// the include graph stays acyclic.
#property strict

#ifndef CORE_SCALP_FAST_SCALP_RISK_BUDGET_MQH
#define CORE_SCALP_FAST_SCALP_RISK_BUDGET_MQH

#include "../Risk/UnifiedRiskManager.mqh"
#include "FastScalpTypes.mqh"

class CFastScalpRiskBudget
{
private:
   double m_usedScalpRiskPct;     // Tracked scalp risk budget used

public:
   CFastScalpRiskBudget() : m_usedScalpRiskPct(0.0) {}

   double Get() const { return m_usedScalpRiskPct; }

   //--- Consume budget on entry
   void Add(double pct) { m_usedScalpRiskPct += pct; }

   //--- Release budget, clamped at zero (original clamp reproduced)
   void Release(double pct)
   {
      m_usedScalpRiskPct -= pct;
      if(m_usedScalpRiskPct < 0.0)
         m_usedScalpRiskPct = 0.0;
   }

// Release one "risk per trade" unit — the fallback used when the
// actual risk cannot be reconstructed, and by the async expiry path.
   void ReleaseFallback(CUnifiedRiskManager* riskManager)
   {
      double riskPerTrade = riskManager != NULL ?
                            riskManager.GetActiveRiskPerTradePercent() : 1.0;
      Release(riskPerTrade);
   }

// Free the budget consumed by one scalp ticket.
// `found`/`state` are the result of the caller's tracker lookup —
// this mirrors the original for-loop over m_scalpPositions.
   void FreeForTicket(ulong ticket, bool found, const SScalpPositionState &state,
                      CUnifiedRiskManager* riskManager)
   {
      if(found)
      {
         string symbol = state.symbol;
         double lotSize = 0.0;
         double slDistance = 0.0;
         double entryPrice = state.entryPrice;
         double originalSL = state.originalSL;

         if(PositionSelectByTicket(ticket))
         {
            lotSize = PositionGetDouble(POSITION_VOLUME);
            double currentSL = PositionGetDouble(POSITION_SL);
            if(currentSL > 0.0 && entryPrice > 0.0)
            {
               slDistance = MathAbs(entryPrice - currentSL);
            }
         }
         else
         {
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            if(point > 0.0 && originalSL > 0.0 && entryPrice > 0.0)
            {
               slDistance = MathAbs(entryPrice - originalSL);
            }
         }

         if(lotSize > 0.0 && slDistance > 0.0 && riskManager != NULL)
         {
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
            double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
            double equity = AccountInfoDouble(ACCOUNT_EQUITY);

            if(point > 0.0 && tickValue > 0.0 && tickSize > 0.0 && equity > 0.0)
            {
               double slPoints = slDistance / point;
               double riskPerLot = (slPoints * point / tickSize) * tickValue;
               double actualRiskPct = (lotSize * riskPerLot) / equity * 100.0;
               m_usedScalpRiskPct -= actualRiskPct;
               if(m_usedScalpRiskPct < 0.0)
                  m_usedScalpRiskPct = 0.0;
               return;
            }
         }

         ReleaseFallback(riskManager);
         return;
      }

      ReleaseFallback(riskManager);
   }
};

#endif // CORE_SCALP_FAST_SCALP_RISK_BUDGET_MQH
