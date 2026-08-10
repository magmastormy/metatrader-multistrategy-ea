//+------------------------------------------------------------------+
//| GridRecoveryDrawdown.mqh                                         |
//| Drawdown-based recovery guards: floating grid drawdown accounting |
//| and L10-003 equity-floor gates for activation and per-level adds. |
//| Extracted verbatim from GridRecoveryEngine.mqh (structural only). |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_GRID_RECOVERY_DRAWDOWN_MQH
#define CORE_SCALP_GRID_RECOVERY_DRAWDOWN_MQH

#include "GridRecoveryTypes.mqh"

//+------------------------------------------------------------------+
//| CGridRecoveryDrawdown — stateless drawdown / equity-floor guards  |
//+------------------------------------------------------------------+
class CGridRecoveryDrawdown
{
public:
   //+------------------------------------------------------------------+
   //| Calculate grid drawdown as percentage of equity                   |
   //+------------------------------------------------------------------+
   static double CalculateGridDrawdownPercent(const SGridSymbolState &state)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0)
         return 0.0;

      double totalDrawdown = 0.0;
      for(int l = 0; l < state.activeLevelCount; l++)
      {
         if(!state.levels[l].isActive || state.levels[l].ticket == 0)
            continue;

         if(PositionSelectByTicket(state.levels[l].ticket))
         {
            double profit = PositionGetDouble(POSITION_PROFIT);
            if(profit < 0.0)
               totalDrawdown += MathAbs(profit);
         }
      }

      return (totalDrawdown / equity) * 100.0;
   }

   //+------------------------------------------------------------------+
   //| L10-003: Equity floor check for initial grid activation.          |
   //| For initial activation, current equity is used as the baseline;   |
   //| the floor is enforced on subsequent levels via initialEquity.     |
   //+------------------------------------------------------------------+
   static bool PassesActivationEquityFloor(double equityFloorPercent)
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(currentEquity > 0.0 && equityFloorPercent > 0.0)
      {
         double minEquity = currentEquity * (equityFloorPercent / 100.0);
         if(currentEquity < minEquity)
         {
            PrintFormat("[GRID-RECOVERY] REJECTED: Equity %.2f below floor %.2f%% of baseline",
                        currentEquity, equityFloorPercent);
            return false;
         }
      }
      return true;
   }

   //+------------------------------------------------------------------+
   //| L10-003: Equity floor check when adding a grid level —            |
   //| stop the grid if equity dropped below the floor of initialEquity. |
   //+------------------------------------------------------------------+
   static bool PassesLevelEquityFloor(double initialEquity, double equityFloorPercent, int level)
   {
      double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(initialEquity > 0.0 && equityFloorPercent > 0.0)
      {
         double floorEquity = initialEquity * (equityFloorPercent / 100.0);
         if(currentEquity < floorEquity)
         {
            PrintFormat("[GRID-RECOVERY] REJECTED L%d: Equity %.2f below floor %.2f (%.1f%% of initial %.2f)",
                        level, currentEquity, floorEquity, equityFloorPercent, initialEquity);
            return false;
         }
      }
      return true;
   }
};

#endif // CORE_SCALP_GRID_RECOVERY_DRAWDOWN_MQH
