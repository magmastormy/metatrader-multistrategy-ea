//+------------------------------------------------------------------+
//| FastScalpEngine.mqh                                              |
//| Dedicated scalping pipeline bypassing full consensus engine       |
//| Single-strategy-allowed signals, tight stops, tick-level mgmt    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_FAST_SCALP_ENGINE_MQH
#define CORE_SCALP_FAST_SCALP_ENGINE_MQH

#include "../Utils/Enums.mqh"
#include "../Trading/TradeManager.mqh"
#include "../Risk/UnifiedRiskManager.mqh"
#include "../Risk/PositionSizer.mqh"
#include "../Risk/RiskTierManager.mqh"
#include "../../IndicatorManager.mqh"
#include "ScalpSignalCache.mqh"

//+------------------------------------------------------------------+
//| Scalp configuration struct                                        |
//+------------------------------------------------------------------+
struct SScalpConfig
{
   int      maxScalpPositions;       // Max concurrent scalp positions (3)
   double   scalpRiskPct;            // Risk % from tier scalpBudgetPct
   int      scalpSLPips;             // Tight SL in pips (50-80)
   int      scalpTPPips;             // TP in pips (75-120, 1.5-2x SL)
   int      scalpCooldownMs;         // Cooldown between scalps in ms (5000)
   int      fastEMA;                 // Fast EMA period (5)
   int      slowEMA;                 // Slow EMA period (13)
   int      rsiPeriod;               // RSI period (7)
   double   rsiOverbought;           // RSI overbought level (75)
   double   rsiOversold;             // RSI oversold level (25)
   double   maxSpreadATRRatio;       // Reject if spread > 30% ATR (0.30)
   double   momentumBurstATRRatio;   // Bar body > 80% ATR (0.80)
   bool     usePendingOrders;        // Use pending limit orders (true)
   int      pendingOrderTTL;         // Pending order TTL in seconds (120)
   bool     partialCloseEnabled;     // Close 50% at 1R profit (true)
   int      breakevenProfitPoints;   // Points profit to trigger BE (10)
   int      breakevenBufferPoints;   // Buffer past entry for BE (5)
   int      trailingDistancePoints;  // Trailing distance in points (15)

   // Default constructor with production defaults
   SScalpConfig()
   {
      maxScalpPositions       = 3;
      scalpRiskPct            = 3.0;
      scalpSLPips             = 60;
      scalpTPPips             = 90;
      scalpCooldownMs         = 5000;
      fastEMA                 = 5;
      slowEMA                 = 13;
      rsiPeriod               = 7;
      rsiOverbought           = 75.0;
      rsiOversold             = 25.0;
      maxSpreadATRRatio       = 0.30;
      momentumBurstATRRatio   = 0.80;
      usePendingOrders        = true;
      pendingOrderTTL         = 20;
      partialCloseEnabled     = true;
      breakevenProfitPoints   = 10;
      breakevenBufferPoints   = 5;
      trailingDistancePoints  = 15;
   }
};

//+------------------------------------------------------------------+
//| Pending scalp order tracking                                      |
//+------------------------------------------------------------------+
struct SPendingScalpOrder
{
   ulong    ticket;
   string   symbol;
   ENUM_ORDER_TYPE orderType;
   double   lotSize;
   double   entryPrice;
   double   stopLoss;
   double   takeProfit;
   datetime placedAt;
   bool     isActive;
};

//+------------------------------------------------------------------+
//| Async scalp order tracking (for OrderSendAsync confirmation)      |
//+------------------------------------------------------------------+
struct SScalpPendingAsync
{
   ulong    orderTicket;      // Order ticket from OrderSendAsync
   string   symbol;           // Symbol
   int      direction;        // 1=BUY, -1=SELL
   double   lotSize;          // Requested lots
   double   entryPrice;       // Expected entry price
   double   stopLoss;         // SL price
   double   takeProfit;       // TP price
   uint     sendTimestampMs;  // GetTickCount at send time
   bool     confirmed;        // Whether deal was confirmed
   bool     expired;          // Whether order expired
};

//+------------------------------------------------------------------+
//| Scalp position state for tick-level management                    |
//+------------------------------------------------------------------+
struct SScalpPositionState
{
   ulong    ticket;
   string   symbol;
   bool     breakevenSet;
   bool     partialClosed;
   double   entryPrice;
   double   originalSL;
   double   originalTP;
   double   oneRProfitPrice;   // Price at 1R profit (for partial close)
};

//+------------------------------------------------------------------+
//| CFastScalpEngine — Dedicated scalping pipeline                    |
//+------------------------------------------------------------------+
class CFastScalpEngine
{
private:
   SScalpConfig              m_config;
   CTradeManager*            m_tradeManager;
   CUnifiedRiskManager*      m_riskManager;
   CPositionSizer*           m_positionSizer;
   CRiskTierManager*         m_riskTierManager;
   CScalpSignalCache*        m_signalCache;          // External cache reference (optional)
   CTrade                    m_tradeObj;             // For pending order operations (OrderDelete)

   datetime                  m_lastScalpTime;        // Last scalp entry time
   double                    m_usedScalpRiskPct;     // Tracked scalp risk budget used
   uint                      m_magicNumber;          // EA magic number for pending orders
   bool                      m_initialized;

   // Pending order tracking
   SPendingScalpOrder        m_pendingOrders[10];
   int                       m_pendingOrderCount;

   // Scalp position tracking
   SScalpPositionState       m_scalpPositions[20];
   int                       m_scalpPositionCount;

   // Async order tracking
   SScalpPendingAsync        m_pendingAsync[20];
   int                       m_pendingAsyncCount;
   bool                      m_asyncMode;            // Whether async mode is enabled
   uint                      m_maxLatencyMs;         // Max acceptable latency

   // Cached indicator data per symbol
   string                    m_cachedSymbol;
   datetime                  m_cachedBarTime;
   double                    m_cachedATR;
   double                    m_cachedFastEMA;
   double                    m_cachedSlowEMA;
   double                    m_cachedRSI;

   //+------------------------------------------------------------------+
   //| Refresh cached indicator values for a symbol                      |
   //+------------------------------------------------------------------+
   bool RefreshIndicators(string symbol)
   {
      // Only refresh on new bar for M1
      datetime barTime = iTime(symbol, PERIOD_M1, 0);
      if(barTime == m_cachedBarTime && symbol == m_cachedSymbol && m_cachedATR > 0.0)
         return true;

      CIndicatorManager* indMgr = CIndicatorManager::Instance();
      if(indMgr == NULL)
         return false;

      // ATR(14) on M1
      int atrHandle = indMgr.GetATRHandle(symbol, PERIOD_M1, 14);
      if(atrHandle == INVALID_HANDLE)
         return false;
      double atrBuf[];
      ArraySetAsSeries(atrBuf, true);
      if(CopyBuffer(atrHandle, 0, 0, 1, atrBuf) <= 0)
         return false;
      m_cachedATR = atrBuf[0];

      // Fast EMA(5) on M1
      int fastHandle = indMgr.GetMAHandle(symbol, PERIOD_M1, m_config.fastEMA, 0, MODE_EMA, PRICE_CLOSE);
      if(fastHandle == INVALID_HANDLE)
         return false;
      double fastBuf[];
      ArraySetAsSeries(fastBuf, true);
      if(CopyBuffer(fastHandle, 0, 0, 2, fastBuf) < 2)
         return false;
      m_cachedFastEMA = fastBuf[0];

      // Slow EMA(13) on M1
      int slowHandle = indMgr.GetMAHandle(symbol, PERIOD_M1, m_config.slowEMA, 0, MODE_EMA, PRICE_CLOSE);
      if(slowHandle == INVALID_HANDLE)
         return false;
      double slowBuf[];
      ArraySetAsSeries(slowBuf, true);
      if(CopyBuffer(slowHandle, 0, 0, 2, slowBuf) < 2)
         return false;
      m_cachedSlowEMA = slowBuf[0];

      // RSI(7) on M1
      int rsiHandle = indMgr.GetRSIHandle(symbol, PERIOD_M1, m_config.rsiPeriod, PRICE_CLOSE);
      if(rsiHandle == INVALID_HANDLE)
         return false;
      double rsiBuf[];
      ArraySetAsSeries(rsiBuf, true);
      if(CopyBuffer(rsiHandle, 0, 0, 1, rsiBuf) <= 0)
         return false;
      m_cachedRSI = rsiBuf[0];

      m_cachedSymbol = symbol;
      m_cachedBarTime = barTime;
      return true;
   }

   //+------------------------------------------------------------------+
   //| Refresh market price with tick-level freshness check              |
   //| Returns true if valid prices obtained, false otherwise            |
   //| Prevents retcode=10015 (Invalid price) by ensuring latest tick   |
   //+------------------------------------------------------------------+
   bool RefreshScalpPrice(string symbol, double &ask, double &bid)
   {
      ask = 0.0;
      bid = 0.0;

      // Get the latest tick — most authoritative price source
      MqlTick tick;
      if(!SymbolInfoTick(symbol, tick))
      {
         PrintFormat("[SCALP-PRICE] SymbolInfoTick failed for %s — falling back to SymbolInfoDouble", symbol);
         ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
         bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      }
      else
      {
         ask = tick.ask;
         bid = tick.bid;
      }

      if(ask <= 0.0 || bid <= 0.0)
      {
         PrintFormat("[SCALP-PRICE] Invalid prices for %s: ask=%.5f bid=%.5f", symbol, ask, bid);
         return false;
      }

      // Batch 117: removed debug log — fires on every tick, creates excessive output
      return true;
   }

   //+------------------------------------------------------------------+
   //| Get ATR value cached                                              |
   //+------------------------------------------------------------------+
   double GetATRCached(string symbol)
   {
      if(!RefreshIndicators(symbol))
         return 0.0;
      return m_cachedATR;
   }

   //+------------------------------------------------------------------+
   //| Get EMA values for crossover detection                            |
   //+------------------------------------------------------------------+
   bool GetEMACrossover(string symbol, ENUM_TRADE_SIGNAL &signal)
   {
      CIndicatorManager* indMgr = CIndicatorManager::Instance();
      if(indMgr == NULL)
         return false;

      // Need 2 bars for crossover detection
      int fastHandle = indMgr.GetMAHandle(symbol, PERIOD_M1, m_config.fastEMA, 0, MODE_EMA, PRICE_CLOSE);
      int slowHandle = indMgr.GetMAHandle(symbol, PERIOD_M1, m_config.slowEMA, 0, MODE_EMA, PRICE_CLOSE);
      if(fastHandle == INVALID_HANDLE || slowHandle == INVALID_HANDLE)
         return false;

      double fastBuf[], slowBuf[];
      ArraySetAsSeries(fastBuf, true);
      ArraySetAsSeries(slowBuf, true);
      if(CopyBuffer(fastHandle, 0, 0, 2, fastBuf) < 2) return false;
      if(CopyBuffer(slowHandle, 0, 0, 2, slowBuf) < 2) return false;

      // Crossover: fast crosses above slow => BUY; fast crosses below slow => SELL
      double fastCurr = fastBuf[0], fastPrev = fastBuf[1];
      double slowCurr = slowBuf[0], slowPrev = slowBuf[1];

      if(fastPrev <= slowPrev && fastCurr > slowCurr)
         signal = TRADE_SIGNAL_BUY;
      else if(fastPrev >= slowPrev && fastCurr < slowCurr)
         signal = TRADE_SIGNAL_SELL;
      else
         signal = TRADE_SIGNAL_NONE;

      return true;
   }

   //+------------------------------------------------------------------+
   //| Check momentum burst: current bar body > threshold * ATR         |
   //+------------------------------------------------------------------+
   bool IsMomentumBurst(string symbol)
   {
      double atr = GetATRCached(symbol);
      if(atr <= 0.0)
         return false;

      double open1  = iOpen(symbol, PERIOD_M1, 0);
      double close1 = iClose(symbol, PERIOD_M1, 0);
      if(open1 <= 0.0 || close1 <= 0.0)
         return false;

      double bodySize = MathAbs(close1 - open1);
      return (bodySize > m_config.momentumBurstATRRatio * atr);
   }

   //+------------------------------------------------------------------+
   //| Check spread gate: reject if spread > maxSpreadATRRatio * ATR    |
   //+------------------------------------------------------------------+
   bool IsSpreadAcceptable(string symbol)
   {
      double atr = GetATRCached(symbol);
      if(atr <= 0.0)
         return false;

      double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return false;

      double spreadPrice = spread * point;
      return (spreadPrice <= m_config.maxSpreadATRRatio * atr);
   }

   //+------------------------------------------------------------------+
   //| Check if Symbol is Synthetic Index                              |
   //+------------------------------------------------------------------+
   bool IsSyntheticSymbol(const string symbol)
   {
      if(symbol == "") return false;
      
      // Check for broker-specific synthetic products that trade 24/7
      if(StringFind(symbol, "Vol") >= 0  ||      // Vol 10, Vol 25, Vol 50, etc.
         StringFind(symbol, "Step") >= 0 ||      // Step Index variants
         StringFind(symbol, "Boom") >= 0 ||      // Boom 1000, Boom 500
         StringFind(symbol, "Crash") >= 0 ||     // Crash 1000, Crash 500
         StringFind(symbol, "Jump") >= 0 ||      // Jump 10, Jump 25, etc.
         StringFind(symbol, "PainX") >= 0 ||     // Weltrade synthetic family
         StringFind(symbol, "Pain ") >= 0 ||     // Additional naming variant
         StringFind(symbol, "SFX Vol") >= 0 ||
         StringFind(symbol, "FX Vol") >= 0 ||
         StringFind(symbol, "GainX") >= 0 ||
         StringFind(symbol, "FlipX") >= 0 ||
         StringFind(symbol, "SwitchX") >= 0 ||   // SwitchX 1200 and variants
         StringFind(symbol, "Synth") >= 0 ||
         StringFind(symbol, "Index") >= 0)
      {
         return true;
      }
      return false;
   }

   //+------------------------------------------------------------------+
   //| Check if scalp is cost-viable given spread + commission           |
   //| Rejects if breakeven WR > 70% or total cost > 25% of TP          |
   //| Returns true if commission data is unavailable (pass-through)    |
   //| SYNTHETIC SYMBOLS: More permissive thresholds (wider spreads)    |
   //+------------------------------------------------------------------+
   bool IsScalpCostViable(const string symbol, double slPoints, double tpPoints)
   {
      // Get total transaction cost
      double spreadPoints = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);

      // MQL5 does not have SYMBOL_TRADE_COMMISSION — estimate commission from
      // SYMBOL_TRADE_TICK_VALUE_PROFIT and SYMBOL_TRADE_CONTRACT_SIZE
      // For synthetic CFDs, commission is often embedded in the spread.
      // We use a conservative estimate: commission ≈ 0 if not detectable.
      double commissionPerLot = 0.0;

      // Try to detect commission from the difference between tick value profit and loss
      double tickValueProfit = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
      double tickValueLoss   = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tickValueProfit > 0.0 && tickValueLoss > 0.0)
      {
         // If tick values differ, the difference is broker commission per tick
         double commissionPerTick = MathAbs(tickValueProfit - tickValueLoss);
         double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
         if(tickSize > 0.0)
            commissionPerLot = commissionPerTick * (1.0 / tickSize); // Convert to per-lot
      }

      // Total cost = spread + estimated commission (round-trip)
      double commissionPoints = 0.0;
      if(commissionPerLot > 0.0)
      {
         double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
         double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
         if(tickValue > 0.0 && tickSize > 0.0)
         {
            double pointValue = tickValue / tickSize;
            commissionPoints = commissionPerLot * 2.0 * pointValue; // Round-trip
         }
      }

      double totalCostPoints = spreadPoints + commissionPoints;

      // Breakeven win rate
      double breakevenWR = totalCostPoints / (totalCostPoints + tpPoints);

      // Check if symbol is synthetic - use more permissive thresholds
      bool isSynthetic = IsSyntheticSymbol(symbol);
      
      // Thresholds: standard vs synthetic
      double maxBreakevenWR = isSynthetic ? 0.85 : 0.70;   // Allow up to 85% breakeven WR for synthetics
      double maxCostRatioTP = isSynthetic ? 0.60 : 0.25;   // Allow up to 60% of TP for synthetics

      // Reject if cost is too high relative to target
      if(breakevenWR > maxBreakevenWR)
      {
         Print("[SCALP-COST-REJECTED] ", symbol, " cost too high: spread=", spreadPoints,
               " comm=", commissionPoints, " total=", totalCostPoints,
               " tp=", tpPoints, " breakevenWR=", DoubleToString(breakevenWR, 3),
               " > ", DoubleToString(maxBreakevenWR, 2), " (", isSynthetic ? "SYNTHETIC" : "STANDARD", ")");
         return false;
      }

      // Also reject if total cost > maxCostRatio of TP
      if(totalCostPoints > tpPoints * maxCostRatioTP)
      {
         Print("[SCALP-COST-REJECTED] ", symbol, " cost ratio too high: ",
               DoubleToString(totalCostPoints / tpPoints * 100.0, 1), "% of TP > ",
               DoubleToString(maxCostRatioTP * 100.0, 0), "% (", isSynthetic ? "SYNTHETIC" : "STANDARD", ")");
         return false;
      }

      Print("[SCALP-COST-OK] ", symbol, " cost viable: totalCost=", totalCostPoints,
            " tp=", tpPoints, " breakevenWR=", DoubleToString(breakevenWR, 3),
            " (", isSynthetic ? "SYNTHETIC" : "STANDARD", ")");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Check RSI confirmation: not overbought for BUY, not oversold     |
   //+------------------------------------------------------------------+
   bool IsRSIConfirmed(ENUM_TRADE_SIGNAL signal)
   {
      if(m_cachedRSI <= 0.0)
         return false;

      if(signal == TRADE_SIGNAL_BUY)
         return (m_cachedRSI < m_config.rsiOverbought);
      else if(signal == TRADE_SIGNAL_SELL)
         return (m_cachedRSI > m_config.rsiOversold);

      return false;
   }

   //+------------------------------------------------------------------+
   //| Cap lot size to available margin and symbol volume limits         |
   //| Prevents margin rejections (retcode=10018) and volume limit       |
   //| rejections (retcode=10034) on small accounts                     |
   //+------------------------------------------------------------------+
   double CapLotToMargin(double calculatedLot, string symbol)
   {
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double marginPerLot = 0;
      double askPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(!OrderCalcMargin(ORDER_TYPE_BUY, symbol, 1.0, askPrice, marginPerLot) || marginPerLot <= 0.0)
         return calculatedLot;
      double maxLotByMargin = freeMargin / (marginPerLot * 1.5); // 1.5x safety factor
      double symbolMaxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double cappedLot = MathMin(calculatedLot, MathMin(maxLotByMargin, symbolMaxVolume));
      if(cappedLot < calculatedLot)
      {
         Print("[SCALP-LOT-CAPPED] ", symbol, " lot capped from ", calculatedLot, " to ", cappedLot,
               " (margin_max=", maxLotByMargin, " vol_max=", symbolMaxVolume, ")");
      }
      return cappedLot;
   }

   //+------------------------------------------------------------------+
   //| Register a scalp position in the tracking array                   |
   //+------------------------------------------------------------------+
   void RegisterScalpPosition(ulong ticket, string symbol, double entryPrice,
                               double sl, double tp, double oneRPrice)
   {
      if(m_scalpPositionCount >= ArraySize(m_scalpPositions))
         return;

      m_scalpPositions[m_scalpPositionCount].ticket          = ticket;
      m_scalpPositions[m_scalpPositionCount].symbol          = symbol;
      m_scalpPositions[m_scalpPositionCount].breakevenSet    = false;
      m_scalpPositions[m_scalpPositionCount].partialClosed   = false;
      m_scalpPositions[m_scalpPositionCount].entryPrice      = entryPrice;
      m_scalpPositions[m_scalpPositionCount].originalSL      = sl;
      m_scalpPositions[m_scalpPositionCount].originalTP      = tp;
      m_scalpPositions[m_scalpPositionCount].oneRProfitPrice = oneRPrice;
      m_scalpPositionCount++;
   }

   //+------------------------------------------------------------------+
   //| Remove a scalp position from tracking by ticket                   |
   //+------------------------------------------------------------------+
   void RemoveScalpPosition(ulong ticket)
   {
      for(int i = 0; i < m_scalpPositionCount; i++)
      {
         if(m_scalpPositions[i].ticket == ticket)
         {
            // Shift remaining
            for(int j = i; j < m_scalpPositionCount - 1; j++)
               m_scalpPositions[j] = m_scalpPositions[j + 1];
            m_scalpPositionCount--;
            // Clear last slot
            ZeroMemory(m_scalpPositions[m_scalpPositionCount]);
            return;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Find scalp position state by ticket                               |
   //+------------------------------------------------------------------+
   int FindScalpPositionState(ulong ticket)
   {
      for(int i = 0; i < m_scalpPositionCount; i++)
      {
         if(m_scalpPositions[i].ticket == ticket)
            return i;
      }
      return -1;
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CFastScalpEngine() :
      m_tradeManager(NULL),
      m_riskManager(NULL),
      m_positionSizer(NULL),
      m_riskTierManager(NULL),
      m_signalCache(NULL),
      m_lastScalpTime(0),
      m_usedScalpRiskPct(0.0),
      m_magicNumber(123456),
      m_initialized(false),
      m_pendingOrderCount(0),
      m_scalpPositionCount(0),
      m_pendingAsyncCount(0),
      m_asyncMode(false),
      m_maxLatencyMs(500),
      m_cachedSymbol(""),
      m_cachedBarTime(0),
      m_cachedATR(0.0),
      m_cachedFastEMA(0.0),
      m_cachedSlowEMA(0.0),
      m_cachedRSI(0.0)
   {
      ZeroMemory(m_pendingOrders);
      ZeroMemory(m_scalpPositions);
      ZeroMemory(m_pendingAsync);
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CFastScalpEngine()
   {
      // Cancel any remaining pending orders
      for(int i = 0; i < m_pendingOrderCount; i++)
      {
         if(m_pendingOrders[i].isActive && m_pendingOrders[i].ticket > 0)
         {
            if(OrderSelect(m_pendingOrders[i].ticket))
               m_tradeObj.OrderDelete(m_pendingOrders[i].ticket);
         }
      }
      m_pendingOrderCount = 0;
      m_scalpPositionCount = 0;
   }

   //+------------------------------------------------------------------+
   //| Initialize with external dependencies                             |
   //+------------------------------------------------------------------+
   bool Initialize(CTradeManager* scalpTradeMgr,
                   CUnifiedRiskManager* riskManager,
                   CPositionSizer* scalpPosSizer,
                   CRiskTierManager* riskTierManager)
   {
      if(scalpTradeMgr == NULL || riskManager == NULL ||
         scalpPosSizer == NULL || riskTierManager == NULL)
      {
         Print("[SCALP-ENGINE] ERROR: NULL dependency passed to Initialize");
         return false;
      }

      m_tradeManager    = scalpTradeMgr;
      m_riskManager     = riskManager;
      m_positionSizer   = scalpPosSizer;
      m_riskTierManager = riskTierManager;

      // Capture magic number from trade manager for pending orders
      // Note: CTradeManager doesn't expose GetMagicNumber, so we use the default
      // The market order path goes through CTradeManager which sets magic internally

      // Load scalp budget from tier config
      m_config.scalpRiskPct = m_riskTierManager.GetScalpBudgetPct();
      if(m_config.scalpRiskPct <= 0.0)
      {
         Print("[SCALP-ENGINE] Scalp budget is 0% — scalp engine will not trade");
         m_config.maxScalpPositions = 0;
      }

      m_initialized = true;
      PrintFormat("[SCALP-ENGINE] Initialized | maxPos=%d | risk=%.1f%% | SL=%d | TP=%d | cooldown=%dms | pending=%s | partial=%s",
                  m_config.maxScalpPositions,
                  m_config.scalpRiskPct,
                  m_config.scalpSLPips,
                  m_config.scalpTPPips,
                  m_config.scalpCooldownMs,
                  m_config.usePendingOrders ? "ON" : "OFF",
                  m_config.partialCloseEnabled ? "ON" : "OFF");
      return true;
   }

   //+------------------------------------------------------------------+
   //| Set custom configuration                                         |
   //+------------------------------------------------------------------+
   void SetConfig(const SScalpConfig &config)
   {
      m_config = config;
      PrintFormat("[SCALP-ENGINE] Config updated | maxPos=%d | risk=%.1f%% | SL=%d | TP=%d",
                  m_config.maxScalpPositions, m_config.scalpRiskPct,
                  m_config.scalpSLPips, m_config.scalpTPPips);
   }

   //+------------------------------------------------------------------+
   //| Get current configuration                                         |
   //+------------------------------------------------------------------+
   SScalpConfig GetConfig() const { return m_config; }

   //+------------------------------------------------------------------+
   //| Set magic number for pending orders                               |
   //+------------------------------------------------------------------+
   void SetMagicNumber(uint magic) { m_magicNumber = magic; }

   //+------------------------------------------------------------------+
   //| Set external signal cache for fast-path evaluation                |
   //| When set, EvaluateScalpSignal reads from cache instead of         |
   //| calling CopyBuffer — zero indicator computation in fast path      |
   //+------------------------------------------------------------------+
   void SetSignalCache(CScalpSignalCache* cache) { m_signalCache = cache; }

   //+------------------------------------------------------------------+
   //| Set async mode for scalp order execution                          |
   //+------------------------------------------------------------------+
   void SetAsyncMode(bool enabled)
   {
      m_asyncMode = enabled;
      PrintFormat("[SCALP-ASYNC] Async mode %s", m_asyncMode ? "ENABLED" : "DISABLED");
   }

   //+------------------------------------------------------------------+
   //| Set max acceptable latency for async order confirmation           |
   //+------------------------------------------------------------------+
   void SetMaxLatencyMs(uint maxMs)
   {
      m_maxLatencyMs = (maxMs > 0) ? maxMs : 500;
      PrintFormat("[SCALP-ASYNC] Max latency set to %u ms", m_maxLatencyMs);
   }

   //+------------------------------------------------------------------+
   //| Get pending async order count                                     |
   //+------------------------------------------------------------------+
   int GetPendingAsyncCount() const { return m_pendingAsyncCount; }

   //+------------------------------------------------------------------+
   //| Is the engine initialized and enabled?                            |
   //+------------------------------------------------------------------+
   bool IsInitialized() const { return m_initialized; }

   //+------------------------------------------------------------------+
   //| Evaluate scalp signal for a symbol                                |
   //| Micro-trend: EMA5/EMA13 crossover on M1                          |
   //| Momentum burst: bar body > 0.8 * ATR                             |
   //| RSI confirmation: not overbought/oversold                         |
   //| Spread gate: reject if spread > 30% of ATR                       |
   //+------------------------------------------------------------------+
   ENUM_TRADE_SIGNAL EvaluateScalpSignal(string symbol)
   {
      if(!m_initialized)
         return TRADE_SIGNAL_NONE;

      // Try fast-path: read from signal cache (zero CopyBuffer)
      if(m_signalCache != NULL)
      {
         SScalpIndicatorCache cache;
         if(m_signalCache.GetCache(symbol, cache) && cache.isValid)
         {
            // Spread gate using cached values
            double pointVal = SymbolInfoDouble(symbol, SYMBOL_POINT);
            if(pointVal > 0.0 && cache.atrValue > 0.0)
            {
               double spreadPrice = cache.spreadPoints * pointVal;
               if(spreadPrice > m_config.maxSpreadATRRatio * cache.atrValue)
                  return TRADE_SIGNAL_NONE;
            }
            else
               return TRADE_SIGNAL_NONE;

            // EMA crossover detection using cached values
            ENUM_TRADE_SIGNAL emaSignal = TRADE_SIGNAL_NONE;
            if(cache.emaFastPrev <= cache.emaSlowPrev && cache.emaFast > cache.emaSlow)
               emaSignal = TRADE_SIGNAL_BUY;
            else if(cache.emaFastPrev >= cache.emaSlowPrev && cache.emaFast < cache.emaSlow)
               emaSignal = TRADE_SIGNAL_SELL;

            if(emaSignal == TRADE_SIGNAL_NONE)
               return TRADE_SIGNAL_NONE;

            // RSI confirmation using cached value
            if(emaSignal == TRADE_SIGNAL_BUY && cache.rsiValue >= m_config.rsiOverbought)
               return TRADE_SIGNAL_NONE;
            if(emaSignal == TRADE_SIGNAL_SELL && cache.rsiValue <= m_config.rsiOversold)
               return TRADE_SIGNAL_NONE;

            // Cache the indicator values for ShouldEnterScalp's confidence calculation
            m_cachedATR     = cache.atrValue;
            m_cachedFastEMA = cache.emaFast;
            m_cachedSlowEMA = cache.emaSlow;
            m_cachedRSI     = cache.rsiValue;
            m_cachedSymbol  = symbol;
            m_cachedBarTime = cache.lastBarTime;

            return emaSignal;
         }
      }

      // Fallback: existing RefreshIndicators path (slow path / timer path)
      if(!RefreshIndicators(symbol))
         return TRADE_SIGNAL_NONE;

      // Spread gate first — cheap rejection
      if(!IsSpreadAcceptable(symbol))
         return TRADE_SIGNAL_NONE;

      // EMA crossover detection
      ENUM_TRADE_SIGNAL emaSignal2 = TRADE_SIGNAL_NONE;
      if(!GetEMACrossover(symbol, emaSignal2))
         return TRADE_SIGNAL_NONE;

      if(emaSignal2 == TRADE_SIGNAL_NONE)
         return TRADE_SIGNAL_NONE;

      // RSI confirmation
      if(!IsRSIConfirmed(emaSignal2))
         return TRADE_SIGNAL_NONE;

      // Momentum burst as confluence booster (not required, but adds confidence)
      // Signal is valid without burst, but burst increases confidence
      return emaSignal2;
   }

   //+------------------------------------------------------------------+
   //| Should we enter a scalp trade?                                    |
   //| Checks: cooldown, max positions, scalp risk budget, signal, lots  |
   //+------------------------------------------------------------------+
   bool ShouldEnterScalp(string symbol, ENUM_TRADE_SIGNAL &signal,
                          double &confidence, double &lotSize)
   {
      signal     = TRADE_SIGNAL_NONE;
      confidence = 0.0;
      lotSize    = 0.0;

      if(!m_initialized)
         return false;

      // Check cooldown
      datetime now = TimeCurrent();
      ulong elapsedMs = (ulong)((now - m_lastScalpTime) * 1000);
      if(m_lastScalpTime > 0 && elapsedMs < (ulong)m_config.scalpCooldownMs)
         return false;

      // Check max scalp positions
      int scalpCount = CountScalpPositions();
      if(scalpCount >= m_config.maxScalpPositions)
         return false;

      // Check scalp risk budget
      if(m_usedScalpRiskPct >= m_config.scalpRiskPct)
         return false;

      // Evaluate signal
      signal = EvaluateScalpSignal(symbol);
      if(signal == TRADE_SIGNAL_NONE)
         return false;

      // Calculate confidence
      confidence = 0.60; // Base confidence for EMA crossover + RSI

      // Boost confidence with momentum burst
      if(IsMomentumBurst(symbol))
         confidence += 0.15;

      // Tight spread bonus
      double atr = GetATRCached(symbol);
      if(atr > 0.0)
      {
         double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
         double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
         if(point > 0.0)
         {
            double spreadRatio = (spread * point) / atr;
            if(spreadRatio < 0.15)
               confidence += 0.10;
         }
      }

      // Cap confidence at 0.90
      confidence = MathMin(confidence, 0.90);

      // Calculate lot size using CPositionSizer
      if(m_positionSizer != NULL && m_positionSizer.IsInitialized())
      {
         ENUM_ORDER_TYPE orderType = (signal == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         lotSize = m_positionSizer.CalculateOptimalPositionSize(
                     symbol, orderType, (double)m_config.scalpSLPips, confidence);
      }
      else
      {
         // Fallback to minimum lot
         double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
         lotSize = (minLot > 0.0) ? minLot : MIN_LOT_SIZE;
      }

      // Validate lot size
      if(lotSize <= 0.0)
         return false;

      // Commission-aware cost validation: reject if total cost (spread + commission)
      // makes the scalp unviable (breakeven WR > 70% or cost > 25% of TP)
      if(!IsScalpCostViable(symbol, (double)m_config.scalpSLPips, (double)m_config.scalpTPPips))
         return false;

      // Risk validation through CUnifiedRiskManager
      if(m_riskManager != NULL && m_riskManager.IsInitialized())
      {
         ENUM_ORDER_TYPE orderType = (signal == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
         STradeValidationRequest request;
         request.symbol          = symbol;
         request.orderType       = orderType;
         request.lotSize         = lotSize;
         request.stopLossPips    = (double)m_config.scalpSLPips;
         request.takeProfitPips  = (double)m_config.scalpTPPips;
         request.confidence      = confidence;
         request.strategy        = "FastScalp";
         request.reasoning       = "Scalp: EMA crossover + RSI + spread gate";
         request.strategyRole    = "PRIMARY_ALPHA";
         request.strategyCluster = "TREND_CLUSTER";
         request.clusterCode     = "T";
         request.requestTime     = TimeCurrent();

         SValidationResult result = m_riskManager.ValidateTradeRequest(request, "scalp");
         if(!result.approved)
         {
            PrintFormat("[SCALP-REJECTED] %s | reason=%s | confidence=%.2f",
                        symbol, result.message, confidence);
            return false;
         }

         // Use risk-adjusted lot size if provided
         if(result.adjustedLotSize > 0.0)
            lotSize = result.adjustedLotSize;
      }

      // Cap lot size to available margin and symbol volume limits
      lotSize = CapLotToMargin(lotSize, symbol);

      // Minimum lot check: skip scalp signal if capped lot is below symbol minimum
      double symbolMinLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      if(lotSize < symbolMinLot)
      {
         PrintFormat("[SCALP-LOT-MIN] %s | capped lot %.2f < min lot %.2f — skipping scalp signal",
                     symbol, lotSize, symbolMinLot);
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Execute a scalp trade (market order)                              |
   //| Supports both synchronous and async execution modes               |
   //+------------------------------------------------------------------+
   bool ExecuteScalpTrade(string symbol, ENUM_TRADE_SIGNAL signal,
                           double lotSize, double confidence)
   {
      if(m_tradeManager == NULL)
         return false;

      ENUM_ORDER_TYPE orderType = (signal == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      // Build comment with SCALP tag for position identification
      string comment = "SCALP|EMA" + IntegerToString(m_config.fastEMA) + "/" +
                       IntegerToString(m_config.slowEMA) + "|C:" +
                       DoubleToString(confidence, 2);

      //--- Async mode: use OrderSendAsync for non-blocking execution
      if(m_asyncMode)
      {
         int direction = (signal == TRADE_SIGNAL_BUY) ? 1 : -1;
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         if(point <= 0.0)
            return false;

         // Refresh prices immediately before order submission to prevent retcode=10015
         double bid = 0.0, ask = 0.0;
         if(!RefreshScalpPrice(symbol, ask, bid))
            return false;

         double entryPrice = (orderType == ORDER_TYPE_BUY) ? ask : bid;
         int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
         double sl = 0.0, tp = 0.0;

         if(orderType == ORDER_TYPE_BUY)
         {
            sl = NormalizeDouble(entryPrice - m_config.scalpSLPips * point, digits);
            tp = NormalizeDouble(entryPrice + m_config.scalpTPPips * point, digits);
         }
         else
         {
            sl = NormalizeDouble(entryPrice + m_config.scalpSLPips * point, digits);
            tp = NormalizeDouble(entryPrice - m_config.scalpTPPips * point, digits);
         }

         MqlTradeRequest request = {};
         MqlTradeResult  result  = {};

         request.action       = TRADE_ACTION_DEAL;
         request.symbol       = symbol;
         request.volume       = lotSize;
         request.type         = orderType;
         request.price        = entryPrice;
         request.sl           = sl;
         request.tp           = tp;
         request.deviation    = 50;
         request.magic        = m_magicNumber;
         request.comment      = comment;
         request.type_filling = ORDER_FILLING_IOC;

         if(!OrderSendAsync(request, result))
         {
            PrintFormat("[SCALP-ASYNC-FAILED] %s | %s | lot=%.2f | retcode=%u | comment=%s",
                        symbol,
                        signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                        lotSize,
                        result.retcode,
                        result.comment);
            return false;
         }

         if(result.retcode != TRADE_RETCODE_PLACED && result.retcode != 0)
         {
            PrintFormat("[SCALP-ASYNC-REJECTED] %s | %s | lot=%.2f | retcode=%u",
                        symbol,
                        signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                        lotSize,
                        result.retcode);
            return false;
         }

         // Track the pending async order
         OnAsyncOrderSent(result.order, symbol, direction, lotSize, entryPrice, sl, tp);

         m_lastScalpTime = TimeCurrent();

         // Track risk usage optimistically (will adjust on confirmation)
         double riskPerTrade = m_riskManager != NULL ?
                               m_riskManager.GetActiveRiskPerTradePercent() : 1.0;
         m_usedScalpRiskPct += riskPerTrade;

         PrintFormat("[SCALP-ASYNC-SENT] %s | %s | lot=%.2f | SL=%d | TP=%d | confidence=%.2f | order=%I64u",
                     symbol,
                     signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                     lotSize,
                     m_config.scalpSLPips,
                     m_config.scalpTPPips,
                     confidence,
                     result.order);

         return true;
      }

      //--- Synchronous mode: use CTradeManager (original path)
      bool result = m_tradeManager.OpenPosition(
                       symbol,
                       orderType,
                       lotSize,
                       0.0,  // price = 0 => market order
                       (double)m_config.scalpSLPips,
                       (double)m_config.scalpTPPips,
                       comment);

      if(result)
      {
         m_lastScalpTime = TimeCurrent();

         // Track risk usage
         double riskPerTrade = m_riskManager != NULL ?
                               m_riskManager.GetActiveRiskPerTradePercent() : 1.0;
         m_usedScalpRiskPct += riskPerTrade;

         // Register the position for tick-level management
         ulong ticket = m_tradeManager.GetLastTicket();
         double entryPrice = m_tradeManager.GetLastRequestedPrice();
         double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double sl = 0.0, tp = 0.0;
         if(point > 0.0)
         {
            if(orderType == ORDER_TYPE_BUY)
            {
               sl = entryPrice - m_config.scalpSLPips * point;
               tp = entryPrice + m_config.scalpTPPips * point;
            }
            else
            {
               sl = entryPrice + m_config.scalpSLPips * point;
               tp = entryPrice - m_config.scalpTPPips * point;
            }
         }

         // Calculate 1R profit price for partial close
         double oneRPrice = 0.0;
         if(point > 0.0)
         {
            if(orderType == ORDER_TYPE_BUY)
               oneRPrice = entryPrice + m_config.scalpSLPips * point;  // 1R = SL distance
            else
               oneRPrice = entryPrice - m_config.scalpSLPips * point;
         }

         RegisterScalpPosition(ticket, symbol, entryPrice, sl, tp, oneRPrice);

         PrintFormat("[SCALP-ENTRY] %s | %s | lot=%.2f | SL=%d | TP=%d | confidence=%.2f | ticket=%I64u",
                     symbol,
                     signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                     lotSize,
                     m_config.scalpSLPips,
                     m_config.scalpTPPips,
                     confidence,
                     ticket);
      }
      else
      {
         PrintFormat("[SCALP-ENTRY-FAILED] %s | %s | lot=%.2f | retcode=%u",
                     symbol,
                     signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                     lotSize,
                     m_tradeManager.GetLastRetcode());
      }

      return result;
   }

   //+------------------------------------------------------------------+
   //| Place a scalp pending order (BUY_LIMIT/SELL_LIMIT)               |
   //+------------------------------------------------------------------+
   bool PlaceScalpPendingOrder(string symbol, ENUM_TRADE_SIGNAL signal, double lotSize)
   {
      if(!m_config.usePendingOrders)
         return false;
      if(m_pendingOrderCount >= ArraySize(m_pendingOrders))
         return false;

      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return false;

      // Refresh prices immediately before order submission to prevent retcode=10015
      double bid = 0.0, ask = 0.0;
      if(!RefreshScalpPrice(symbol, ask, bid))
         return false;

      // Calculate minimum offset from current price for pending orders
      // Must respect broker's SYMBOL_TRADE_STOPS_LEVEL
      long stopsLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
      long freezeLevel = SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
      long minDistPoints = MathMax(stopsLevel, freezeLevel);
      double minOffset = minDistPoints * point;

      // For synthetic CFDs, SYMBOL_TRADE_STOPS_LEVEL often returns 0.
      // Use a percentage-based minimum as fallback: 0.1% of mid-price.
      // This ensures stops are far enough from entry for high-priced instruments.
      double midPrice = (ask + bid) / 2.0;
      double pctMinDistance = midPrice * 0.001;  // 0.1% of price
      double absMinOffset = 10 * point;           // absolute minimum: 10 points
      minOffset = MathMax(minOffset, MathMax(absMinOffset, pctMinDistance));

      // SL/TP must also be at least the same minimum distance away from entry price
      // Enforce minimum SL and TP distances to prevent "Invalid stops"
      double slDistance = m_config.scalpSLPips * point;
      double tpDistance = m_config.scalpTPPips * point;
      double minStopDistance = minOffset;  // Use same minimum as entry offset
      if(slDistance < minStopDistance)
      {
         PrintFormat("[SCALP-STOPS] %s | SL distance %.2f < min stop distance %.2f (pct-based), adjusting", symbol, slDistance, minStopDistance);
         slDistance = minStopDistance;
      }
      if(tpDistance < minStopDistance)
      {
         PrintFormat("[SCALP-STOPS] %s | TP distance %.2f < min stop distance %.2f (pct-based), adjusting", symbol, tpDistance, minStopDistance);
         tpDistance = minStopDistance;
      }

      // Place limit order at broker-minimum distance from current price
      double entryPrice = 0.0;
      double sl = 0.0, tp = 0.0;
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      ENUM_ORDER_TYPE pendingType;

      if(signal == TRADE_SIGNAL_BUY)
      {
         // BUY_LIMIT must be below current ask by at least stops_level
         entryPrice = NormalizeDouble(ask - minOffset, digits);
         sl = NormalizeDouble(entryPrice - slDistance, digits);
         tp = NormalizeDouble(entryPrice + tpDistance, digits);
         pendingType = ORDER_TYPE_BUY_LIMIT;
      }
      else
      {
         // SELL_LIMIT must be above current bid by at least stops_level
         entryPrice = NormalizeDouble(bid + minOffset, digits);
         sl = NormalizeDouble(entryPrice + slDistance, digits);
         tp = NormalizeDouble(entryPrice - tpDistance, digits);
         pendingType = ORDER_TYPE_SELL_LIMIT;
      }

      // Use CTradeManager's underlying CTrade object via OpenPosition is not suitable
      // for pending orders — use MQL5 trade API directly
      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      request.action    = TRADE_ACTION_PENDING;
      request.symbol    = symbol;
      request.volume    = lotSize;
      request.type      = pendingType;
      request.price     = entryPrice;
      request.sl        = sl;
      request.tp        = tp;
      request.deviation = 50;
      request.magic     = m_magicNumber;
      request.comment   = "SCALP|PEND";
      request.type_filling = ORDER_FILLING_IOC;

      if(!OrderSend(request, result))
      {
         PrintFormat("[SCALP-PENDING-FAILED] %s | retcode=%u | comment=%s",
                     symbol, result.retcode, result.comment);
         return false;
      }

      // Track the pending order
      m_pendingOrders[m_pendingOrderCount].ticket     = result.order;
      m_pendingOrders[m_pendingOrderCount].symbol     = symbol;
      m_pendingOrders[m_pendingOrderCount].orderType  = pendingType;
      m_pendingOrders[m_pendingOrderCount].lotSize    = lotSize;
      m_pendingOrders[m_pendingOrderCount].entryPrice = entryPrice;
      m_pendingOrders[m_pendingOrderCount].stopLoss   = sl;
      m_pendingOrders[m_pendingOrderCount].takeProfit = tp;
      m_pendingOrders[m_pendingOrderCount].placedAt   = TimeCurrent();
      m_pendingOrders[m_pendingOrderCount].isActive   = true;
      m_pendingOrderCount++;

      m_lastScalpTime = TimeCurrent();

      PrintFormat("[SCALP-PENDING] %s | %s | price=%.5f | lot=%.2f | ticket=%I64u | TTL=%ds",
                  symbol,
                  signal == TRADE_SIGNAL_BUY ? "BUY_LIMIT" : "SELL_LIMIT",
                  entryPrice,
                  lotSize,
                  result.order,
                  m_config.pendingOrderTTL);

      return true;
   }

   //+------------------------------------------------------------------+
   //| Check and manage pending scalp orders (cancel expired)            |
   //+------------------------------------------------------------------+
   void CheckPendingScalpOrders()
   {
      if(m_pendingOrderCount <= 0)
         return;

      datetime now = TimeCurrent();

      for(int i = m_pendingOrderCount - 1; i >= 0; i--)
      {
         if(!m_pendingOrders[i].isActive)
            continue;

         // Check if order still exists
         if(!OrderSelect(m_pendingOrders[i].ticket))
         {
            // Order no longer exists — either filled or cancelled
            // If filled, it becomes a position that ManageScalpPositions will pick up
            RemovePendingOrder(i);
            continue;
         }

         // Check TTL
         int elapsedSec = (int)(now - m_pendingOrders[i].placedAt);
         if(elapsedSec >= m_config.pendingOrderTTL)
         {
            // Cancel expired pending order
            if(m_tradeObj.OrderDelete(m_pendingOrders[i].ticket))
            {
               PrintFormat("[SCALP-PENDING-EXPIRED] %s | ticket=%I64u | elapsed=%ds",
                           m_pendingOrders[i].symbol,
                           m_pendingOrders[i].ticket,
                           elapsedSec);
            }
            RemovePendingOrder(i);
            continue;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Remove pending order from tracking array by index                 |
   //+------------------------------------------------------------------+
   void RemovePendingOrder(int index)
   {
      if(index < 0 || index >= m_pendingOrderCount)
         return;

      for(int j = index; j < m_pendingOrderCount - 1; j++)
         m_pendingOrders[j] = m_pendingOrders[j + 1];

      ZeroMemory(m_pendingOrders[m_pendingOrderCount - 1]);
      m_pendingOrderCount--;
   }

   //+------------------------------------------------------------------+
   //| Manage scalp positions at tick level                              |
   //| Quick profit lock, tight trailing, partial close                  |
   //| NOT throttled to 1 second like swing trailing                     |
   //+------------------------------------------------------------------+
   void ManageScalpPositions()
   {
      if(!m_initialized || m_tradeManager == NULL)
         return;

      // Sync tracked positions with actual open positions
      SyncScalpPositionTracking();

      for(int i = m_scalpPositionCount - 1; i >= 0; i--)
      {
         ulong ticket = m_scalpPositions[i].ticket;

         if(!PositionSelectByTicket(ticket))
         {
            // Position closed — remove from tracking and free risk budget
            FreeScalpRiskBudget(m_scalpPositions[i].ticket);
            RemoveScalpPosition(ticket);
            continue;
         }

         string posSymbol   = PositionGetString(POSITION_SYMBOL);
         double openPrice   = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL   = PositionGetDouble(POSITION_SL);
         double currentTP   = PositionGetDouble(POSITION_TP);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double volume      = PositionGetDouble(POSITION_VOLUME);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double point       = SymbolInfoDouble(posSymbol, SYMBOL_POINT);
         if(point <= 0.0) continue;

         // Calculate profit in points
         double profitPoints = 0.0;
         if(posType == POSITION_TYPE_BUY)
            profitPoints = (currentPrice - openPrice) / point;
         else
            profitPoints = (openPrice - currentPrice) / point;

         // 1. Partial close at 1R profit (50% of position)
         if(m_config.partialCloseEnabled && !m_scalpPositions[i].partialClosed && m_scalpPositions[i].oneRProfitPrice > 0.0)
         {
            bool reachedOneR = false;
            if(posType == POSITION_TYPE_BUY && currentPrice >= m_scalpPositions[i].oneRProfitPrice)
               reachedOneR = true;
            else if(posType == POSITION_TYPE_SELL && currentPrice <= m_scalpPositions[i].oneRProfitPrice)
               reachedOneR = true;

            if(reachedOneR && volume > SymbolInfoDouble(posSymbol, SYMBOL_VOLUME_MIN))
            {
               double halfVol = NormalizeDouble(volume * 0.5, 2);
               double minVol  = SymbolInfoDouble(posSymbol, SYMBOL_VOLUME_MIN);
               double stepVol = SymbolInfoDouble(posSymbol, SYMBOL_VOLUME_STEP);
               if(stepVol <= 0.0) stepVol = 0.01;
               halfVol = MathFloor((halfVol + 1e-12) / stepVol) * stepVol;
               halfVol = NormalizeDouble(halfVol, 2);

               if(halfVol >= minVol && halfVol < volume)
               {
                  if(m_tradeManager.ClosePositionPartial(ticket, halfVol, "SCALP|1R-PARTIAL"))
                  {
                     m_scalpPositions[i].partialClosed = true;
                     PrintFormat("[SCALP-PARTIAL] %s | ticket=%I64u | closed=%.2f | profit_pts=%.1f",
                                 posSymbol, ticket, halfVol, profitPoints);
                  }
               }
            }
         }

         // 2. Move to breakeven after breakevenProfitPoints
         if(!m_scalpPositions[i].breakevenSet && profitPoints >= m_config.breakevenProfitPoints)
         {
            double beSL = 0.0;
            if(posType == POSITION_TYPE_BUY)
               beSL = NormalizeDouble(openPrice + m_config.breakevenBufferPoints * point,
                                      (int)SymbolInfoInteger(posSymbol, SYMBOL_DIGITS));
            else
               beSL = NormalizeDouble(openPrice - m_config.breakevenBufferPoints * point,
                                      (int)SymbolInfoInteger(posSymbol, SYMBOL_DIGITS));

            // Only move SL if it improves the position
            bool shouldMove = false;
            if(posType == POSITION_TYPE_BUY && (currentSL < beSL || currentSL == 0.0))
               shouldMove = true;
            else if(posType == POSITION_TYPE_SELL && (currentSL > beSL || currentSL == 0.0))
               shouldMove = true;

            if(shouldMove)
            {
               if(m_tradeManager.ModifyPosition(ticket, beSL, currentTP))
               {
                  m_scalpPositions[i].breakevenSet = true;
                  PrintFormat("[SCALP-BREAKEVEN] %s | ticket=%I64u | SL=%.5f | profit_pts=%.1f",
                              posSymbol, ticket, beSL, profitPoints);
               }
            }
         }

         // 3. Tight trailing after breakeven is set
         if(m_scalpPositions[i].breakevenSet && m_config.trailingDistancePoints > 0)
         {
            double newSL = 0.0;
            int digits = (int)SymbolInfoInteger(posSymbol, SYMBOL_DIGITS);

            if(posType == POSITION_TYPE_BUY)
            {
               newSL = NormalizeDouble(currentPrice - m_config.trailingDistancePoints * point, digits);
               if(newSL > currentSL)
               {
                  m_tradeManager.ModifyPosition(ticket, newSL, currentTP);
               }
            }
            else
            {
               newSL = NormalizeDouble(currentPrice + m_config.trailingDistancePoints * point, digits);
               if(currentSL == 0.0 || newSL < currentSL)
               {
                  m_tradeManager.ModifyPosition(ticket, newSL, currentTP);
               }
            }
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Count positions with "SCALP" in comment                           |
   //+------------------------------------------------------------------+
   int CountScalpPositions()
   {
      int count = 0;
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(PositionSelectByTicket(ticket))
         {
            string comment = PositionGetString(POSITION_COMMENT);
            if(StringFind(comment, "SCALP") >= 0)
               count++;
         }
      }
      return count;
   }

   //+------------------------------------------------------------------+
   //| Check if a position is a scalp position                           |
   //+------------------------------------------------------------------+
   bool IsScalpPosition(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket))
         return false;
      string comment = PositionGetString(POSITION_COMMENT);
      return (StringFind(comment, "SCALP") >= 0);
   }

   //+------------------------------------------------------------------+
   //| Sync tracked scalp positions with actual open positions           |
   //+------------------------------------------------------------------+
   void SyncScalpPositionTracking()
   {
      // Remove tracked positions that no longer exist or are no longer scalp
      for(int i = m_scalpPositionCount - 1; i >= 0; i--)
      {
         ulong ticket = m_scalpPositions[i].ticket;
         if(!PositionSelectByTicket(ticket) || !IsScalpPosition(ticket))
         {
            FreeScalpRiskBudget(ticket);
            RemoveScalpPosition(ticket);
         }
      }

      // Add new scalp positions not yet tracked
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;

         string comment = PositionGetString(POSITION_COMMENT);
         if(StringFind(comment, "SCALP") < 0) continue;

         // Already tracked?
         if(FindScalpPositionState(ticket) >= 0) continue;

         // Register new scalp position
         string posSymbol = PositionGetString(POSITION_SYMBOL);
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double sl        = PositionGetDouble(POSITION_SL);
         double tp        = PositionGetDouble(POSITION_TP);
         double point     = SymbolInfoDouble(posSymbol, SYMBOL_POINT);

         double oneRPrice = 0.0;
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         if(point > 0.0)
         {
            double slDistance = MathAbs(openPrice - sl) / point;
            if(posType == POSITION_TYPE_BUY)
               oneRPrice = openPrice + slDistance * point;
            else
               oneRPrice = openPrice - slDistance * point;
         }

         RegisterScalpPosition(ticket, posSymbol, openPrice, sl, tp, oneRPrice);
      }
   }

   //+------------------------------------------------------------------+
   //| Free scalp risk budget when a position closes                     |
   //+------------------------------------------------------------------+
   void FreeScalpRiskBudget(ulong ticket)
   {
      // Approximate: release 1 trade's worth of risk
      double riskPerTrade = m_riskManager != NULL ?
                            m_riskManager.GetActiveRiskPerTradePercent() : 1.0;
      m_usedScalpRiskPct -= riskPerTrade;
      if(m_usedScalpRiskPct < 0.0)
         m_usedScalpRiskPct = 0.0;
   }

   //+------------------------------------------------------------------+
   //| Track a pending async order after OrderSendAsync                  |
   //+------------------------------------------------------------------+
   void OnAsyncOrderSent(ulong orderTicket, string symbol, int direction,
                          double lotSize, double entryPrice, double sl, double tp)
   {
      if(m_pendingAsyncCount >= ArraySize(m_pendingAsync))
      {
         PrintFormat("[SCALP-ASYNC-OVERFLOW] Cannot track order %I64u — pending array full (%d)",
                     orderTicket, m_pendingAsyncCount);
         return;
      }

      m_pendingAsync[m_pendingAsyncCount].orderTicket     = orderTicket;
      m_pendingAsync[m_pendingAsyncCount].symbol          = symbol;
      m_pendingAsync[m_pendingAsyncCount].direction       = direction;
      m_pendingAsync[m_pendingAsyncCount].lotSize         = lotSize;
      m_pendingAsync[m_pendingAsyncCount].entryPrice      = entryPrice;
      m_pendingAsync[m_pendingAsyncCount].stopLoss        = sl;
      m_pendingAsync[m_pendingAsyncCount].takeProfit      = tp;
      m_pendingAsync[m_pendingAsyncCount].sendTimestampMs = GetTickCount();
      m_pendingAsync[m_pendingAsyncCount].confirmed       = false;
      m_pendingAsync[m_pendingAsyncCount].expired         = false;
      m_pendingAsyncCount++;
   }

   //+------------------------------------------------------------------+
   //| Handle deal confirmation for async scalp orders                   |
   //| Called from OnTradeTransaction when a deal matches a pending order|
   //+------------------------------------------------------------------+
   void OnDealConfirmed(ulong dealTicket, ulong orderTicket)
   {
      if(m_pendingAsyncCount <= 0)
         return;

      // Find the matching pending async order
      for(int i = 0; i < m_pendingAsyncCount; i++)
      {
         if(m_pendingAsync[i].orderTicket == orderTicket && !m_pendingAsync[i].confirmed)
         {
            // Calculate execution latency
            uint latencyMs = GetTickCount() - m_pendingAsync[i].sendTimestampMs;

            // Check for stale fill
            if(latencyMs > m_maxLatencyMs)
            {
               PrintFormat("[SCALP-ASYNC-LATENCY] %s: Execution latency %u ms exceeds max %u ms. Stale fill detected.",
                           m_pendingAsync[i].symbol, latencyMs, m_maxLatencyMs);
               // Don't reject the fill (it's already executed), but flag it for monitoring
               // Consider tighter SL for stale fills
            }

            m_pendingAsync[i].confirmed = true;

            // Register the position in m_scalpPositions for tick-level management
            // Use the position ID from the deal as the tracking ticket
            ulong positionId = 0;
            if(HistoryDealSelect(dealTicket))
               positionId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

            if(positionId > 0)
            {
               double point = SymbolInfoDouble(m_pendingAsync[i].symbol, SYMBOL_POINT);
               double oneRPrice = 0.0;
               if(point > 0.0)
               {
                  if(m_pendingAsync[i].direction == 1)  // BUY
                     oneRPrice = m_pendingAsync[i].entryPrice + m_config.scalpSLPips * point;
                  else  // SELL
                     oneRPrice = m_pendingAsync[i].entryPrice - m_config.scalpSLPips * point;
               }

               RegisterScalpPosition(positionId, m_pendingAsync[i].symbol, m_pendingAsync[i].entryPrice,
                                      m_pendingAsync[i].stopLoss, m_pendingAsync[i].takeProfit, oneRPrice);
            }

            PrintFormat("[SCALP-ASYNC-CONFIRMED] %s | %s | order=%I64u | deal=%I64u | position=%I64u | lot=%.2f | latency=%u ms",
                        m_pendingAsync[i].symbol,
                        m_pendingAsync[i].direction == 1 ? "BUY" : "SELL",
                        orderTicket,
                        dealTicket,
                        positionId,
                        m_pendingAsync[i].lotSize,
                        latencyMs);

            // Remove from pending array
            RemovePendingAsync(i);
            return;
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Check pending async orders for expiration                         |
   //| Called from OnTick to detect stale unconfirmed orders             |
   //+------------------------------------------------------------------+
   void CheckPendingAsyncOrders()
   {
      if(m_pendingAsyncCount <= 0)
         return;

      uint nowMs = GetTickCount();

      for(int i = m_pendingAsyncCount - 1; i >= 0; i--)
      {
         if(m_pendingAsync[i].confirmed || m_pendingAsync[i].expired)
            continue;

         uint elapsedMs = nowMs - m_pendingAsync[i].sendTimestampMs;

         // Expire orders that exceed 3x max latency without confirmation
         uint expireThresholdMs = m_maxLatencyMs * 3;
         if(elapsedMs > expireThresholdMs)
         {
            m_pendingAsync[i].expired = true;

            // Release risk budget for expired order
            double riskPerTrade = m_riskManager != NULL ?
                                  m_riskManager.GetActiveRiskPerTradePercent() : 1.0;
            m_usedScalpRiskPct -= riskPerTrade;
            if(m_usedScalpRiskPct < 0.0)
               m_usedScalpRiskPct = 0.0;

            PrintFormat("[SCALP-ASYNC-EXPIRED] %s | order=%I64u | elapsed=%u ms | threshold=%u ms",
                        m_pendingAsync[i].symbol,
                        m_pendingAsync[i].orderTicket,
                        elapsedMs,
                        expireThresholdMs);

            RemovePendingAsync(i);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Remove a pending async order from tracking array by index         |
   //+------------------------------------------------------------------+
   void RemovePendingAsync(int index)
   {
      if(index < 0 || index >= m_pendingAsyncCount)
         return;

      for(int j = index; j < m_pendingAsyncCount - 1; j++)
         m_pendingAsync[j] = m_pendingAsync[j + 1];

      ZeroMemory(m_pendingAsync[m_pendingAsyncCount - 1]);
      m_pendingAsyncCount--;
   }

   //+------------------------------------------------------------------+
   //| Get scalp engine diagnostics                                      |
   //+------------------------------------------------------------------+
   void PrintDiagnostics()
   {
      PrintFormat("[SCALP-DIAG] initialized=%s | maxPos=%d | currentPos=%d | riskUsed=%.1f/%.1f%% | pending=%d | tracked=%d | async=%s | pendingAsync=%d",
                  m_initialized ? "true" : "false",
                  m_config.maxScalpPositions,
                  CountScalpPositions(),
                  m_usedScalpRiskPct,
                  m_config.scalpRiskPct,
                  m_pendingOrderCount,
                  m_scalpPositionCount,
                  m_asyncMode ? "ON" : "OFF",
                  m_pendingAsyncCount);
   }

   //+------------------------------------------------------------------+
   //| Get used scalp risk budget                                        |
   //+------------------------------------------------------------------+
   double GetUsedScalpRiskPct() const { return m_usedScalpRiskPct; }

   //+------------------------------------------------------------------+
   //| Get pending order count                                           |
   //+------------------------------------------------------------------+
   int GetPendingOrderCount() const { return m_pendingOrderCount; }
};

#endif // CORE_SCALP_FAST_SCALP_ENGINE_MQH
