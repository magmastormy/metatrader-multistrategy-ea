// Rebuild fast-scalp exposure from live broker positions and orders.
#property strict

#ifndef CORE_SCALP_FAST_SCALP_RISK_BUDGET_MQH
#define CORE_SCALP_FAST_SCALP_RISK_BUDGET_MQH

class CFastScalpRiskBudget
{
private:
   double m_usedScalpRiskPct;

   static bool IsFinite(const double value)
   {
      return value == value && value > -1.0e300 && value < 1.0e300;
   }

   void FailClosed()
   {
      m_usedScalpRiskPct = 1.0e100;
   }

   static bool CalculateRiskPct(const ENUM_ORDER_TYPE direction,
                                const string &symbol,
                                const double volume,
                                const double entryPrice,
                                const double stopLoss,
                                const double equity,
                                double &riskPct)
   {
      if(symbol == "" || !(volume > 0.0) || !IsFinite(volume) ||
         !IsFinite(entryPrice) || entryPrice == 0.0 ||
         !IsFinite(stopLoss) || stopLoss == 0.0 ||
         !(equity > 0.0) || !IsFinite(equity))
         return false;

      double profitAtStop = 0.0;
      if(!OrderCalcProfit(direction, symbol, volume, entryPrice, stopLoss, profitAtStop) ||
         !IsFinite(profitAtStop))
         return false;

      double riskMoney = MathMax(0.0, -profitAtStop);
      riskPct = riskMoney / equity * 100.0;
      return riskPct >= 0.0 && IsFinite(riskPct);
   }

   static bool ResolveMarketDirection(const ENUM_ORDER_TYPE orderType,
                                     ENUM_ORDER_TYPE &direction)
   {
      switch(orderType)
      {
         case ORDER_TYPE_BUY:
         case ORDER_TYPE_BUY_LIMIT:
         case ORDER_TYPE_BUY_STOP:
         case ORDER_TYPE_BUY_STOP_LIMIT:
            direction = ORDER_TYPE_BUY;
            return true;
         case ORDER_TYPE_SELL:
         case ORDER_TYPE_SELL_LIMIT:
         case ORDER_TYPE_SELL_STOP:
         case ORDER_TYPE_SELL_STOP_LIMIT:
            direction = ORDER_TYPE_SELL;
            return true;
      }
      return false;
   }

   bool AddRisk(const double riskPct)
   {
      if(!(riskPct >= 0.0) || !IsFinite(riskPct))
         return false;
      m_usedScalpRiskPct += riskPct;
      return IsFinite(m_usedScalpRiskPct);
   }

public:
   CFastScalpRiskBudget() : m_usedScalpRiskPct(1.0e100) {}

   double Get() const { return m_usedScalpRiskPct; }

   static bool EstimateRiskPct(const ENUM_ORDER_TYPE direction,
                               const string &symbol,
                               const double volume,
                               const double entryPrice,
                               const double stopLoss,
                               const double equity,
                               double &riskPct)
   {
      if((direction != ORDER_TYPE_BUY && direction != ORDER_TYPE_SELL) ||
         !(stopLoss > 0.0) || !(entryPrice > 0.0) ||
         (direction == ORDER_TYPE_BUY && stopLoss >= entryPrice) ||
         (direction == ORDER_TYPE_SELL && stopLoss <= entryPrice))
         return false;

      return CalculateRiskPct(direction, symbol, volume, entryPrice, stopLoss, equity, riskPct) &&
             riskPct > 0.0;
   }

   bool Rebuild(const long expectedMagic, const double unresolvedReservationPct)
   {
      m_usedScalpRiskPct = 0.0;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(expectedMagic <= 0 || !(equity > 0.0) || !IsFinite(equity) ||
         !(unresolvedReservationPct >= 0.0) || !IsFinite(unresolvedReservationPct))
      {
         FailClosed();
         return false;
      }

      for(int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !PositionSelectByTicket(ticket))
         {
            FailClosed();
            return false;
         }
         if(PositionGetInteger(POSITION_MAGIC) != expectedMagic)
            continue;

         ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(positionType != POSITION_TYPE_BUY && positionType != POSITION_TYPE_SELL)
         {
            FailClosed();
            return false;
         }
         ENUM_ORDER_TYPE direction = (positionType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         double riskPct = 0.0;
         if(!CalculateRiskPct(direction,
                              PositionGetString(POSITION_SYMBOL),
                              PositionGetDouble(POSITION_VOLUME),
                              PositionGetDouble(POSITION_PRICE_OPEN),
                              PositionGetDouble(POSITION_SL),
                              equity,
                              riskPct) || !AddRisk(riskPct))
         {
            FailClosed();
            return false;
         }
      }

      for(int i = 0; i < OrdersTotal(); i++)
      {
         ulong ticket = OrderGetTicket(i);
         if(ticket == 0 || !OrderSelect(ticket))
         {
            FailClosed();
            return false;
         }
         if(OrderGetInteger(ORDER_MAGIC) != expectedMagic)
            continue;

         ENUM_ORDER_TYPE direction;
         double riskPct = 0.0;
         if(!ResolveMarketDirection((ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE), direction) ||
            !CalculateRiskPct(direction,
                              OrderGetString(ORDER_SYMBOL),
                              OrderGetDouble(ORDER_VOLUME_CURRENT),
                              OrderGetDouble(ORDER_PRICE_OPEN),
                              OrderGetDouble(ORDER_SL),
                              equity,
                              riskPct) || !AddRisk(riskPct))
         {
            FailClosed();
            return false;
         }
      }

      if(!AddRisk(unresolvedReservationPct))
      {
         FailClosed();
         return false;
      }

      return true;
   }
};

#endif // CORE_SCALP_FAST_SCALP_RISK_BUDGET_MQH
