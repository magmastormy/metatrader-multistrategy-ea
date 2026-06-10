//+------------------------------------------------------------------+
//| FullMarginMode.mqh                                               |
//| Full-margin aggressive mode: position stacking, stricter circuit  |
//| breaker, session lockout safeguards                               |
//+------------------------------------------------------------------+
#ifndef CORE_RISK_FULL_MARGIN_MODE_MQH
#define CORE_RISK_FULL_MARGIN_MODE_MQH

#include "../Utils/Enums.mqh"

//+------------------------------------------------------------------+
//| Full-margin configuration                                         |
//+------------------------------------------------------------------+
struct SFullMarginConfig
{
   int      maxStackedPositions;     // Max stacked positions per symbol (3)
   double   stackLotScale;           // Lot scale per stack level (0.5 = 50% of previous)
   double   minProfitForStack;       // Min profit ratio to allow stacking (>0 means in profit)
   int      maxBreachesPerDay;       // Max DD breaches before session lockout (2)
   int      cooldownMinutes;         // Cooldown at conservative tier after breach (120)
   bool     sessionLocked;           // True after 2nd breach in a day — full-margin disabled for session
   double   ddWarningPct;            // DD warning threshold (5%)
   double   ddCriticalPct;           // DD critical threshold (10%)
   double   maxSpreadATRRatio;       // Stricter spread gate (0.20 = 20% of ATR)
   double   dailyLossLimitPct;       // Absolute daily loss limit (25% = hard stop)
   double   minMarginLevelPct;       // Minimum margin level % (200%)

   SFullMarginConfig()
   {
      maxStackedPositions  = 3;
      stackLotScale        = 0.5;
      minProfitForStack    = 0.0;    // Any profit qualifies
      maxBreachesPerDay    = 2;
      cooldownMinutes      = 120;
      sessionLocked        = false;
      ddWarningPct         = 5.0;
      ddCriticalPct        = 10.0;
      maxSpreadATRRatio    = 0.20;
      dailyLossLimitPct    = 25.0;
      minMarginLevelPct    = 200.0;
   }
};

//+------------------------------------------------------------------+
//| Full-margin breach tracking per day                               |
//+------------------------------------------------------------------+
struct SFullMarginBreachState
{
   int      breachCount;             // Number of DD breaches today
   datetime lastBreachTime;          // Time of last breach
   datetime cooldownUntil;           // Cooldown end time (at conservative tier)
   bool     sessionLocked;           // Full-margin disabled for rest of session
   datetime sessionLockDate;         // Date when session was locked (for midnight reset)

   SFullMarginBreachState()
   {
      breachCount     = 0;
      lastBreachTime  = 0;
      cooldownUntil   = 0;
      sessionLocked   = false;
      sessionLockDate = 0;
   }
};

//+------------------------------------------------------------------+
//| CFullMarginMode — Full-margin aggressive mode controller          |
//+------------------------------------------------------------------+
class CFullMarginMode
{
private:
   SFullMarginConfig    m_config;
   SFullMarginBreachState m_breachState;
   bool                 m_initialized;

   //+------------------------------------------------------------------+
   //| Reset breach state on new trading day                             |
   //+------------------------------------------------------------------+
   void CheckDailyReset()
   {
      datetime now = TimeCurrent();
      MqlDateTime nowDt, breachDt;
      TimeToStruct(now, nowDt);

      if(m_breachState.sessionLockDate > 0)
      {
         TimeToStruct(m_breachState.sessionLockDate, breachDt);
         if(nowDt.year != breachDt.year || nowDt.mon != breachDt.mon || nowDt.day != breachDt.day)
         {
            m_breachState.breachCount     = 0;
            m_breachState.lastBreachTime  = 0;
            m_breachState.cooldownUntil   = 0;
            m_breachState.sessionLocked   = false;
            m_breachState.sessionLockDate = 0;
            Print("[FULL-MARGIN] Daily breach reset — new trading day");
         }
      }
   }

public:
   CFullMarginMode() : m_initialized(false)
   {
   }

   bool IsInitialized() const { return m_initialized; }

   //+------------------------------------------------------------------+
   //| Initialize with config                                            |
   //+------------------------------------------------------------------+
   bool Initialize(const SFullMarginConfig &config)
   {
      m_config = config;
      m_breachState = SFullMarginBreachState();
      m_initialized = true;
      PrintFormat("[FULL-MARGIN] Initialized | maxStack=%d | lotScale=%.2f | ddWarn=%.1f%% | ddCrit=%.1f%% | maxSpreadATR=%.2f | dailyLossLimit=%.1f%% | maxBreaches=%d | cooldown=%dmin",
                  m_config.maxStackedPositions,
                  m_config.stackLotScale,
                  m_config.ddWarningPct,
                  m_config.ddCriticalPct,
                  m_config.maxSpreadATRRatio,
                  m_config.dailyLossLimitPct,
                  m_config.maxBreachesPerDay,
                  m_config.cooldownMinutes);
      return true;
   }

   const SFullMarginConfig& GetConfig() const { return m_config; }
   const SFullMarginBreachState& GetBreachState() const { return m_breachState; }

   //+------------------------------------------------------------------+
   //| Count positions by symbol and direction                           |
   //+------------------------------------------------------------------+
   int CountPositionsBySymbolAndDirection(string symbol, ENUM_TRADE_SIGNAL direction) const
   {
      int count = 0;
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != symbol) continue;

         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(direction == TRADE_SIGNAL_BUY && posType == POSITION_TYPE_BUY)
            count++;
         else if(direction == TRADE_SIGNAL_SELL && posType == POSITION_TYPE_SELL)
            count++;
      }
      return count;
   }

   //+------------------------------------------------------------------+
   //| Can we stack another position on this symbol+direction?           |
   //| All existing positions must be in profit to allow stacking.       |
   //+------------------------------------------------------------------+
   bool CanStackPosition(string symbol, ENUM_TRADE_SIGNAL direction) const
   {
      if(!m_initialized)
         return false;

      // Session lockout — no stacking allowed
      if(m_breachState.sessionLocked)
         return false;

      // Cooldown active — no stacking
      if(m_breachState.cooldownUntil > 0 && TimeCurrent() < m_breachState.cooldownUntil)
         return false;

      int existingPositions = CountPositionsBySymbolAndDirection(symbol, direction);
      if(existingPositions >= m_config.maxStackedPositions)
         return false;

      // All existing positions in same symbol+direction must be in profit
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;
         if(PositionGetString(POSITION_SYMBOL) != symbol) continue;

         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         bool directionMatch = false;
         if(direction == TRADE_SIGNAL_BUY && posType == POSITION_TYPE_BUY)
            directionMatch = true;
         else if(direction == TRADE_SIGNAL_SELL && posType == POSITION_TYPE_SELL)
            directionMatch = true;

         if(!directionMatch) continue;

         double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         if(profit < m_config.minProfitForStack)
            return false;
      }
      return true;
   }

   //+------------------------------------------------------------------+
   //| Get stacked lot size: baseLot * scale^level                      |
   //+------------------------------------------------------------------+
   double GetStackedLotSize(double baseLot, int stackLevel) const
   {
      if(stackLevel <= 0)
         return baseLot;
      double lot = baseLot * MathPow(m_config.stackLotScale, (double)stackLevel);
      double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
      if(minLot <= 0.0) minLot = 0.01;
      return MathMax(lot, minLot);
   }

   //+------------------------------------------------------------------+
   //| Get current stack level for a symbol+direction                    |
   //+------------------------------------------------------------------+
   int GetStackLevel(string symbol, ENUM_TRADE_SIGNAL direction) const
   {
      return CountPositionsBySymbolAndDirection(symbol, direction);
   }

   //+------------------------------------------------------------------+
   //| Full-margin circuit breaker check                                 |
   //| Stricter than standard: DD warning at 5%, critical at 10%        |
   //| Returns: true if trading is allowed, false if halted              |
   //+------------------------------------------------------------------+
   bool CheckFullMarginCircuitBreaker(double currentDrawdownPct)
   {
      if(!m_initialized)
         return false;

      CheckDailyReset();

      // Session lockout — full-margin disabled for rest of day
      if(m_breachState.sessionLocked)
      {
         static datetime s_lastLockLog = 0;
         datetime now = TimeCurrent();
         if(s_lastLockLog == 0 || (now - s_lastLockLog) >= 300)
         {
            PrintFormat("[FULL-MARGIN] Session LOCKED — full-margin disabled for rest of day | breaches=%d",
                        m_breachState.breachCount);
            s_lastLockLog = now;
         }
         return false;
      }

      // Cooldown active — still at conservative tier
      if(m_breachState.cooldownUntil > 0 && TimeCurrent() < m_breachState.cooldownUntil)
      {
         return false;
      }

      // Cooldown expired — clear it
      if(m_breachState.cooldownUntil > 0 && TimeCurrent() >= m_breachState.cooldownUntil)
      {
         PrintFormat("[FULL-MARGIN] Cooldown expired — resuming full-margin mode | was at conservative for %d min",
                     m_config.cooldownMinutes);
         m_breachState.cooldownUntil = 0;
      }

      // Critical DD breach
      if(currentDrawdownPct >= m_config.ddCriticalPct)
      {
         m_breachState.breachCount++;
         m_breachState.lastBreachTime = TimeCurrent();

         // Second breach within same day → session lockout
         if(m_breachState.breachCount >= m_config.maxBreachesPerDay)
         {
            m_breachState.sessionLocked = true;
            m_breachState.sessionLockDate = TimeCurrent();
            PrintFormat("[FULL-MARGIN] SESSION LOCKOUT | DD=%.2f%% >= critical=%.2f%% | breach %d/%d | full-margin DISABLED for session",
                        currentDrawdownPct, m_config.ddCriticalPct,
                        m_breachState.breachCount, m_config.maxBreachesPerDay);
            return false;
         }

         // First breach → downgrade to conservative for cooldown period
         m_breachState.cooldownUntil = TimeCurrent() + m_config.cooldownMinutes * 60;
         PrintFormat("[FULL-MARGIN] DD BREACH | DD=%.2f%% >= critical=%.2f%% | breach %d/%d | downgrading to CONSERVATIVE for %d min | cooldown until %s",
                     currentDrawdownPct, m_config.ddCriticalPct,
                     m_breachState.breachCount, m_config.maxBreachesPerDay,
                     m_config.cooldownMinutes,
                     TimeToString(m_breachState.cooldownUntil, TIME_SECONDS));
         return false;
      }

      // Warning DD — still allow but log
      if(currentDrawdownPct >= m_config.ddWarningPct)
      {
         static datetime s_lastWarnLog = 0;
         datetime now = TimeCurrent();
         if(s_lastWarnLog == 0 || (now - s_lastWarnLog) >= 60)
         {
            PrintFormat("[FULL-MARGIN] DD WARNING | DD=%.2f%% >= warning=%.2f%% | trading continues with caution",
                        currentDrawdownPct, m_config.ddWarningPct);
            s_lastWarnLog = now;
         }
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Is the full-margin mode currently in cooldown?                    |
   //+------------------------------------------------------------------+
   bool IsInCooldown() const
   {
      if(m_breachState.cooldownUntil <= 0)
         return false;
      return (TimeCurrent() < m_breachState.cooldownUntil);
   }

   //+------------------------------------------------------------------+
   //| Is the session locked (full-margin disabled for the day)?         |
   //+------------------------------------------------------------------+
   bool IsSessionLocked() const
   {
      if(!m_breachState.sessionLocked)
         return false;
      // Check if still same day
      datetime now = TimeCurrent();
      MqlDateTime nowDt, lockDt;
      TimeToStruct(now, nowDt);
      TimeToStruct(m_breachState.sessionLockDate, lockDt);
      if(nowDt.year != lockDt.year || nowDt.mon != lockDt.mon || nowDt.day != lockDt.day)
         return false; // New day — lock expired
      return true;
   }

   //+------------------------------------------------------------------+
   //| Full-margin spread gate: stricter than normal (20% ATR vs 30%)   |
   //+------------------------------------------------------------------+
   bool IsSpreadAcceptable(string symbol, double atrValue) const
   {
      if(atrValue <= 0.0)
         return false;

      double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return false;

      double spreadPrice = spread * point;
      return (spreadPrice <= m_config.maxSpreadATRRatio * atrValue);
   }

   //+------------------------------------------------------------------+
   //| Full-margin mandatory safeguard check                             |
   //| Returns true if all safeguards are satisfied for a new entry      |
   //+------------------------------------------------------------------+
   bool CheckSafeguards(string symbol, double atrValue) const
   {
      if(!m_initialized)
         return false;

      // 1. Spread gate (stricter: 20% ATR)
      if(!IsSpreadAcceptable(symbol, atrValue))
      {
         PrintFormat("[FULL-MARGIN-SAFEGUARD] REJECTED | %s | spread exceeds %.0f%% ATR",
                     symbol, m_config.maxSpreadATRRatio * 100.0);
         return false;
      }

      // 2. Margin level must be above 200%
      double margin = AccountInfoDouble(ACCOUNT_MARGIN);
      if(margin > 0.0)
      {
         double equity = AccountInfoDouble(ACCOUNT_EQUITY);
         double marginLevel = (equity / margin) * 100.0;
         if(marginLevel < m_config.minMarginLevelPct)
         {
            PrintFormat("[FULL-MARGIN-SAFEGUARD] REJECTED | %s | margin level %.1f%% < %.1f%%",
                        symbol, marginLevel, m_config.minMarginLevelPct);
            return false;
         }
      }

      // 3. Daily loss limit (absolute: 25% budget = hard stop)
      // This is enforced by the UnifiedRiskManager's daily loss limit circuit breaker,
      // but we double-check here for full-margin awareness
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      if(balance > 0.0)
      {
         double dailyPLPct = ((equity - balance) / balance) * 100.0;
         if(dailyPLPct <= -m_config.dailyLossLimitPct)
         {
            PrintFormat("[FULL-MARGIN-SAFEGUARD] REJECTED | %s | daily loss %.2f%% exceeds limit %.1f%%",
                        symbol, dailyPLPct, m_config.dailyLossLimitPct);
            return false;
         }
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Print full-margin diagnostics                                     |
   //+------------------------------------------------------------------+
   void PrintDiagnostics() const
   {
      PrintFormat("[FULL-MARGIN-DIAG] initialized=%s | sessionLocked=%s | cooldown=%s | breaches=%d/%d | maxStack=%d | lotScale=%.2f | spreadATR=%.2f",
                  m_initialized ? "true" : "false",
                  m_breachState.sessionLocked ? "true" : "false",
                  (m_breachState.cooldownUntil > 0 && TimeCurrent() < m_breachState.cooldownUntil) ? "active" : "none",
                  m_breachState.breachCount,
                  m_config.maxBreachesPerDay,
                  m_config.maxStackedPositions,
                  m_config.stackLotScale,
                  m_config.maxSpreadATRRatio);
   }
};

#endif // CORE_RISK_FULL_MARGIN_MODE_MQH
