//+------------------------------------------------------------------+
//| SafeModeConfig.mqh                                                |
//| Conservative safe trading mode: kill zone filter, partial profit   |
//| taking, stricter consensus gates, no stacking                     |
//+------------------------------------------------------------------+
#ifndef CORE_RISK_SAFE_MODE_CONFIG_MQH
#define CORE_RISK_SAFE_MODE_CONFIG_MQH

#include "../Utils/Enums.mqh"
#include "../Trading/TradeManager.mqh"

//+------------------------------------------------------------------+
//| Safe mode configuration                                           |
//+------------------------------------------------------------------+
struct SSafeModeConfig
{
   double   minConfidence;           // Min consensus confidence (0.70)
   int      minVoters;               // Min live voters for consensus (3)
   double   minQuorumThreshold;      // Min quorum threshold (0.65)
   double   minConfluence;           // Min strategy confluence (0.60)
   bool     tradeOnlyKillZones;      // Only trade during London/NY kill zones (true)
   bool     avoidNewsEvents;         // Avoid trades near news events (true, stub)
   int      newsAvoidanceMinutes;    // Minutes before/after news to avoid (30)
   bool     noStacking;              // No position stacking allowed (true)
   bool     requireBreakevenFirst;   // Require breakeven before adding to position (true)
   double   maxSpreadATRRatio;       // Stricter spread gate (0.15)
   double   breakevenTriggerR;       // Move SL to breakeven at 0.5R profit
   bool     partialProfitTaking;     // Close 50% at 1R, move SL to BE at 0.5R (true)

   SSafeModeConfig()
   {
      minConfidence        = 0.70;
      minVoters            = 3;
      minQuorumThreshold   = 0.65;
      minConfluence        = 0.60;
      tradeOnlyKillZones   = true;
      avoidNewsEvents      = true;
      newsAvoidanceMinutes = 30;
      noStacking           = true;
      requireBreakevenFirst = true;
      maxSpreadATRRatio    = 0.15;
      breakevenTriggerR    = 0.5;
      partialProfitTaking  = true;
   }
};

//+------------------------------------------------------------------+
//| Safe mode position tracking for partial profit management          |
//+------------------------------------------------------------------+
struct SSafeModePositionState
{
   ulong    ticket;
   string   symbol;
   double   entryPrice;
   double   originalSL;
   double   originalTP;
   double   riskDistance;            // SL distance in price (1R)
   bool     breakevenSet;
   bool     partialClosed;
   bool     isActive;

   SSafeModePositionState()
   {
      ticket       = 0;
      symbol       = "";
      entryPrice   = 0.0;
      originalSL   = 0.0;
      originalTP   = 0.0;
      riskDistance  = 0.0;
      breakevenSet = false;
      partialClosed = false;
      isActive     = false;
   }
};

#define SAFE_MODE_MAX_TRACKED 30

//+------------------------------------------------------------------+
//| CSafeMode — Conservative safe trading mode controller              |
//+------------------------------------------------------------------+
class CSafeMode
{
private:
   SSafeModeConfig          m_config;
   SSafeModePositionState   m_trackedPositions[];
   int                      m_trackedCount;
   bool                     m_initialized;

   //+------------------------------------------------------------------+
   //| Find tracked position by ticket                                   |
   //+------------------------------------------------------------------+
   int FindTrackedPosition(ulong ticket) const
   {
      for(int i = 0; i < m_trackedCount; i++)
      {
         if(m_trackedPositions[i].ticket == ticket && m_trackedPositions[i].isActive)
            return i;
      }
      return -1;
   }

   //+------------------------------------------------------------------+
   //| Remove inactive positions from tracking                           |
   //+------------------------------------------------------------------+
   void CleanupTrackedPositions()
   {
      for(int i = m_trackedCount - 1; i >= 0; i--)
      {
         if(!m_trackedPositions[i].isActive)
         {
            for(int j = i; j < m_trackedCount - 1; j++)
               m_trackedPositions[j] = m_trackedPositions[j + 1];
            m_trackedCount--;
         }
      }
   }

public:
   CSafeMode() : m_trackedCount(0), m_initialized(false)
   {
      ArrayResize(m_trackedPositions, SAFE_MODE_MAX_TRACKED);
   }

   bool IsInitialized() const { return m_initialized; }

   //+------------------------------------------------------------------+
   //| Initialize with config                                            |
   //+------------------------------------------------------------------+
   bool Initialize(const SSafeModeConfig &config)
   {
      m_config = config;
      m_trackedCount = 0;
      m_initialized = true;
      PrintFormat("[SAFE-MODE] Initialized | minConf=%.2f | minVoters=%d | quorum=%.2f | confluence=%.2f | killZones=%s | noStack=%s | breakevenFirst=%s | spreadATR=%.2f | beTrigger=%.1fR | partialProfit=%s",
                  m_config.minConfidence,
                  m_config.minVoters,
                  m_config.minQuorumThreshold,
                  m_config.minConfluence,
                  m_config.tradeOnlyKillZones ? "ON" : "OFF",
                  m_config.noStacking ? "YES" : "NO",
                  m_config.requireBreakevenFirst ? "YES" : "NO",
                  m_config.maxSpreadATRRatio,
                  m_config.breakevenTriggerR,
                  m_config.partialProfitTaking ? "ON" : "OFF");
      return true;
   }

   SSafeModeConfig GetConfig() const { return m_config; }

   //+------------------------------------------------------------------+
   //| Kill Zone Filter: London 07-10 UTC, New York 12-15 UTC           |
   //+------------------------------------------------------------------+
   bool IsInKillZone() const
   {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      int hourUTC = dt.hour;

      bool londonKZ = (hourUTC >= 7 && hourUTC < 10);
      bool nyKZ     = (hourUTC >= 12 && hourUTC < 15);
      return londonKZ || nyKZ;
   }

   //+------------------------------------------------------------------+
   //| News avoidance stub (future: integrate economic calendar)         |
   //+------------------------------------------------------------------+
   bool IsNearNewsEvent() const
   {
      // Stub: always returns false until news calendar integration
      // Future: check MqlCalendarValue for high-impact events within
      // m_config.newsAvoidanceMinutes of current time
      return false;
   }

   //+------------------------------------------------------------------+
   //| Safe mode spread gate: stricter than normal (15% ATR)            |
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
   //| Pre-signal gate: check all safe mode conditions before evaluation |
   //| Returns true if signal evaluation is allowed                      |
   //+------------------------------------------------------------------+
   bool IsSignalEvaluationAllowed(string symbol, double atrValue) const
   {
      if(!m_initialized)
         return false;

      // Kill zone filter
      if(m_config.tradeOnlyKillZones && !IsInKillZone())
         return false;

      // News avoidance
      if(m_config.avoidNewsEvents && IsNearNewsEvent())
         return false;

      // Spread gate
      if(!IsSpreadAcceptable(symbol, atrValue))
         return false;

      return true;
   }

   //+------------------------------------------------------------------+
   //| Check if stacking is allowed (safe mode: never)                   |
   //+------------------------------------------------------------------+
   bool IsStackingAllowed() const
   {
      return !m_config.noStacking;
   }

   //+------------------------------------------------------------------+
   //| Register a swing position for safe mode partial profit tracking   |
   //+------------------------------------------------------------------+
   void RegisterPosition(ulong ticket, string symbol, double entryPrice,
                          double sl, double tp)
   {
      if(FindTrackedPosition(ticket) >= 0)
         return; // Already tracked

      CleanupTrackedPositions();

      if(m_trackedCount >= SAFE_MODE_MAX_TRACKED)
         return;

      // Find first inactive slot or append
      int idx = -1;
      for(int i = 0; i < ArraySize(m_trackedPositions); i++)
      {
         if(!m_trackedPositions[i].isActive || i >= m_trackedCount)
         {
            idx = i;
            break;
         }
      }
      if(idx < 0)
      {
         if(m_trackedCount < ArraySize(m_trackedPositions))
            idx = m_trackedCount;
         else
            return;
      }

      double riskDist = MathAbs(entryPrice - sl);
      m_trackedPositions[idx].ticket       = ticket;
      m_trackedPositions[idx].symbol       = symbol;
      m_trackedPositions[idx].entryPrice   = entryPrice;
      m_trackedPositions[idx].originalSL   = sl;
      m_trackedPositions[idx].originalTP   = tp;
      m_trackedPositions[idx].riskDistance  = riskDist;
      m_trackedPositions[idx].breakevenSet = false;
      m_trackedPositions[idx].partialClosed = false;
      m_trackedPositions[idx].isActive     = true;

      if(idx >= m_trackedCount)
         m_trackedCount = idx + 1;

      PrintFormat("[SAFE-MODE-TRACK] %s | ticket=%I64u | entry=%.5f | SL=%.5f | 1R=%.5f",
                  symbol, ticket, entryPrice, sl, riskDist);
   }

   //+------------------------------------------------------------------+
   //| Remove a position from tracking                                   |
   //+------------------------------------------------------------------+
   void UnregisterPosition(ulong ticket)
   {
      int idx = FindTrackedPosition(ticket);
      if(idx >= 0)
         m_trackedPositions[idx].isActive = false;
   }

   //+------------------------------------------------------------------+
   //| Manage safe mode positions: partial profit taking + breakeven     |
   //| This is for swing positions — different from scalp engine logic   |
   //| - Move SL to breakeven at 0.5R profit                            |
   //| - Close 50% of position at 1R profit                             |
   //+------------------------------------------------------------------+
   void ManageSafeModePositions(CTradeManager* safeModeTradeMgr)
   {
      if(!m_initialized || !m_config.partialProfitTaking)
         return;

      if(safeModeTradeMgr == NULL)
         return;

      for(int i = 0; i < m_trackedCount; i++)
      {
         if(!m_trackedPositions[i].isActive)
            continue;

         ulong ticket = m_trackedPositions[i].ticket;
         if(!PositionSelectByTicket(ticket))
         {
            m_trackedPositions[i].isActive = false;
            continue;
         }

         string posSymbol   = PositionGetString(POSITION_SYMBOL);
         double currentSL   = PositionGetDouble(POSITION_SL);
         double currentTP   = PositionGetDouble(POSITION_TP);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double volume      = PositionGetDouble(POSITION_VOLUME);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double point       = SymbolInfoDouble(posSymbol, SYMBOL_POINT);
         int digits         = (int)SymbolInfoInteger(posSymbol, SYMBOL_DIGITS);
         if(point <= 0.0) continue;

         // Calculate current profit in R
         double profitR = 0.0;
         if(m_trackedPositions[i].riskDistance > 0.0)
         {
            if(posType == POSITION_TYPE_BUY)
               profitR = (currentPrice - m_trackedPositions[i].entryPrice) / m_trackedPositions[i].riskDistance;
            else
               profitR = (m_trackedPositions[i].entryPrice - currentPrice) / m_trackedPositions[i].riskDistance;
         }

         // 1. Move SL to breakeven at breakevenTriggerR (0.5R)
         if(!m_trackedPositions[i].breakevenSet && profitR >= m_config.breakevenTriggerR)
         {
            double beSL = 0.0;
            if(posType == POSITION_TYPE_BUY)
               beSL = NormalizeDouble(m_trackedPositions[i].entryPrice + point, digits); // Entry + 1 point buffer
            else
               beSL = NormalizeDouble(m_trackedPositions[i].entryPrice - point, digits);

            // Only move SL if it improves the position
            bool shouldMove = false;
            if(posType == POSITION_TYPE_BUY && (currentSL < beSL || currentSL == 0.0))
               shouldMove = true;
            else if(posType == POSITION_TYPE_SELL && (currentSL > beSL || currentSL == 0.0))
               shouldMove = true;

            if(shouldMove)
            {
               if(safeModeTradeMgr.ModifyPosition(ticket, beSL, currentTP))
               {
                  m_trackedPositions[i].breakevenSet = true;
                  PrintFormat("[SAFE-MODE-BREAKEVEN] %s | ticket=%I64u | SL=%.5f | profitR=%.2fR | trigger=%.1fR",
                              posSymbol, ticket, beSL, profitR, m_config.breakevenTriggerR);
               }
            }
         }

         // 2. Close 50% at 1R profit
         if(!m_trackedPositions[i].partialClosed && profitR >= 1.0)
         {
            double minVol  = SymbolInfoDouble(posSymbol, SYMBOL_VOLUME_MIN);
            double stepVol = SymbolInfoDouble(posSymbol, SYMBOL_VOLUME_STEP);
            if(stepVol <= 0.0) stepVol = 0.01;

            double halfVol = NormalizeDouble(volume * 0.5, 2);
            halfVol = MathFloor((halfVol + 1e-12) / stepVol) * stepVol;
            halfVol = NormalizeDouble(halfVol, 2);

            if(halfVol >= minVol && halfVol < volume)
            {
               if(safeModeTradeMgr.ClosePositionPartial(ticket, halfVol, "SAFE|1R-PARTIAL"))
               {
                  m_trackedPositions[i].partialClosed = true;
                  PrintFormat("[SAFE-MODE-PARTIAL] %s | ticket=%I64u | closed=%.2f | profitR=%.2fR",
                              posSymbol, ticket, halfVol, profitR);
               }
            }
         }
      }

      // Periodic cleanup
      CleanupTrackedPositions();
   }

   //+------------------------------------------------------------------+
   //| Print safe mode diagnostics                                       |
   //+------------------------------------------------------------------+
   void PrintDiagnostics() const
   {
      PrintFormat("[SAFE-MODE-DIAG] initialized=%s | killZone=%s | trackedPositions=%d | minConf=%.2f | minVoters=%d | quorum=%.2f | spreadATR=%.2f",
                  m_initialized ? "true" : "false",
                  IsInKillZone() ? "IN-ZONE" : "OUTSIDE",
                  m_trackedCount,
                  m_config.minConfidence,
                  m_config.minVoters,
                  m_config.minQuorumThreshold,
                  m_config.maxSpreadATRRatio);
   }
};

#endif // CORE_RISK_SAFE_MODE_CONFIG_MQH
