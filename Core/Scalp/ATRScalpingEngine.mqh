//+------------------------------------------------------------------+
//| ATRScalpingEngine.mqh                                            |
//| ATR-based scalping engine for between-spike/between-jump trading |
//| on Deriv synthetic indices. Trades in calm periods, avoids spikes|
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_ATR_SCALPING_ENGINE_MQH
#define CORE_SCALP_ATR_SCALPING_ENGINE_MQH

#include "../Utils/Instruments.mqh"
#include "../Risk/PositionSizer.mqh"
#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| ATR scalping configuration struct                                 |
//+------------------------------------------------------------------+
struct SATRScalpingConfig
{
   int      atrPeriod;                // ATR period (default 14)
   int      emaFastPeriod;            // Fast EMA period (default 5)
   int      emaSlowPeriod;            // Slow EMA period (default 13)
   int      rsiPeriod;                // RSI period (default 7)
   double   spreadMaxATRRatio;        // Max spread as fraction of ATR (default 0.30)
   double   slAtrMultiplier;          // SL = ATR * this (default 1.5)
   double   tpAtrMultiplier;          // TP = ATR * this (default 2.0)
   int      magicOffset;              // Magic number offset (default 7000)
   int      maxPositions;             // Max concurrent scalp positions (default 3)
   int      cooldownMs;               // Cooldown between scalp trades in ms (default 30000)
   int      spikeWindowAvoidMinutes;  // Don't trade this many minutes before expected spike (default 5)
   double   rsiOverbought;            // RSI overbought level (default 70.0)
   double   rsiOversold;              // RSI oversold level (default 30.0)

   // Default constructor with production defaults
   SATRScalpingConfig()
   {
      atrPeriod               = 14;
      emaFastPeriod           = 5;
      emaSlowPeriod           = 13;
      rsiPeriod               = 7;
      spreadMaxATRRatio       = 0.30;
      slAtrMultiplier         = 1.5;
      tpAtrMultiplier         = 2.0;
      magicOffset             = 7000;
      maxPositions            = 3;
      cooldownMs              = 30000;
      spikeWindowAvoidMinutes = 5;
      rsiOverbought           = 70.0;
      rsiOversold             = 30.0;
   }
};

//+------------------------------------------------------------------+
//| Per-symbol ATR scalp state tracking                               |
//+------------------------------------------------------------------+
struct SATRScalpSymbolState
{
   string   symbol;
   bool     isActive;
   datetime lastTradeTime;
   int      activePositions;
   double   currentATR;
   double   emaFastValue;
   double   emaSlowValue;
   double   rsiValue;
   int      lastEmaCrossDirection;     // 0=none, 1=bullish cross, -1=bearish cross
   datetime lastSpikeTime;             // From external spike detection
   int      expectedSpikeIntervalSec;  // e.g., 900 for DEX 900, 1200 for Jump
   bool     inSpikeWindow;             // True if within spikeWindowAvoidMinutes of expected spike
};

//+------------------------------------------------------------------+
//| CATRScalpingEngine — ATR-based between-spike scalping engine      |
//+------------------------------------------------------------------+
class CATRScalpingEngine
{
private:
   SATRScalpingConfig       m_config;
   SATRScalpSymbolState     m_symbolStates[];
   int                      m_symbolCount;
   int                      m_baseMagic;
   CPositionSizer*          m_positionSizer;
   CTrade                   m_trade;

   // Indicator handles per symbol
   int                      m_atrHandles[];
   int                      m_emaFastHandles[];
   int                      m_emaSlowHandles[];
   int                      m_rsiHandles[];

   // Statistics
   int                      m_totalTradesOpened;
   int                      m_totalTradesSkipped;
   int                      m_totalSpikeWindowBlocks;

   //+------------------------------------------------------------------+
   //| Find symbol index in the states array                             |
   //+------------------------------------------------------------------+
   int FindSymbolIndex(const string symbol) const
   {
      for(int i = 0; i < m_symbolCount; i++)
      {
         if(m_symbolStates[i].symbol == symbol)
            return i;
      }
      return -1;
   }

   //+------------------------------------------------------------------+
   //| Initialize a symbol state slot with defaults                      |
   //+------------------------------------------------------------------+
   void InitializeSymbolState(int idx, const string symbol, int spikeIntervalSec)
   {
      m_symbolStates[idx].symbol                   = symbol;
      m_symbolStates[idx].isActive                 = true;
      m_symbolStates[idx].lastTradeTime            = 0;
      m_symbolStates[idx].activePositions          = 0;
      m_symbolStates[idx].currentATR               = 0.0;
      m_symbolStates[idx].emaFastValue             = 0.0;
      m_symbolStates[idx].emaSlowValue             = 0.0;
      m_symbolStates[idx].rsiValue                 = 0.0;
      m_symbolStates[idx].lastEmaCrossDirection    = 0;
      m_symbolStates[idx].lastSpikeTime            = 0;
      m_symbolStates[idx].expectedSpikeIntervalSec = spikeIntervalSec;
      m_symbolStates[idx].inSpikeWindow            = false;
   }

   //+------------------------------------------------------------------+
   //| Update indicator values for a symbol                              |
   //+------------------------------------------------------------------+
   bool UpdateIndicators(int idx)
   {
      string symbol = m_symbolStates[idx].symbol;

      // ATR
      if(m_atrHandles[idx] != INVALID_HANDLE)
      {
         double atrBuf[];
         ArraySetAsSeries(atrBuf, true);
         if(CopyBuffer(m_atrHandles[idx], 0, 0, 1, atrBuf) > 0)
            m_symbolStates[idx].currentATR = atrBuf[0];
      }

      // EMA Fast — need 2 bars for crossover
      double emaFastBuf[];
      ArraySetAsSeries(emaFastBuf, true);
      bool fastOk = false;
      if(m_emaFastHandles[idx] != INVALID_HANDLE)
      {
         if(CopyBuffer(m_emaFastHandles[idx], 0, 0, 2, emaFastBuf) >= 2)
         {
            m_symbolStates[idx].emaFastValue = emaFastBuf[0];
            fastOk = true;
         }
      }

      // EMA Slow — need 2 bars for crossover
      double emaSlowBuf[];
      ArraySetAsSeries(emaSlowBuf, true);
      bool slowOk = false;
      if(m_emaSlowHandles[idx] != INVALID_HANDLE)
      {
         if(CopyBuffer(m_emaSlowHandles[idx], 0, 0, 2, emaSlowBuf) >= 2)
         {
            m_symbolStates[idx].emaSlowValue = emaSlowBuf[0];
            slowOk = true;
         }
      }

      // Detect EMA crossover direction
      if(fastOk && slowOk)
      {
         double fastCurr = emaFastBuf[0], fastPrev = emaFastBuf[1];
         double slowCurr = emaSlowBuf[0], slowPrev = emaSlowBuf[1];

         if(fastPrev <= slowPrev && fastCurr > slowCurr)
            m_symbolStates[idx].lastEmaCrossDirection = 1;   // Bullish cross
         else if(fastPrev >= slowPrev && fastCurr < slowCurr)
            m_symbolStates[idx].lastEmaCrossDirection = -1;  // Bearish cross
         // Keep previous cross direction if no new cross
      }

      // RSI
      if(m_rsiHandles[idx] != INVALID_HANDLE)
      {
         double rsiBuf[];
         ArraySetAsSeries(rsiBuf, true);
         if(CopyBuffer(m_rsiHandles[idx], 0, 0, 1, rsiBuf) > 0)
            m_symbolStates[idx].rsiValue = rsiBuf[0];
      }

      return (m_symbolStates[idx].currentATR > 0.0);
   }

   //+------------------------------------------------------------------+
   //| Check if within spikeWindowAvoidMinutes of expected spike         |
   //+------------------------------------------------------------------+
   bool IsInSpikeWindow(int idx)
   {
      int spikeInterval = m_symbolStates[idx].expectedSpikeIntervalSec;
      datetime lastSpike = m_symbolStates[idx].lastSpikeTime;

      // If no spike interval set, never in spike window
      if(spikeInterval <= 0)
         return false;

      // If we've never seen a spike, can't predict next one
      if(lastSpike <= 0)
         return false;

      datetime now = TimeCurrent();
      int timeSinceLastSpike = (int)(now - lastSpike);
      int timeToNextSpike = spikeInterval - timeSinceLastSpike;

      // In window if time to next spike < spikeWindowAvoidMinutes * 60
      int avoidWindowSec = m_config.spikeWindowAvoidMinutes * 60;
      bool inWindow = (timeToNextSpike > 0 && timeToNextSpike < avoidWindowSec);

      m_symbolStates[idx].inSpikeWindow = inWindow;
      return inWindow;
   }

   //+------------------------------------------------------------------+
   //| Evaluate scalp signal: EMA crossover + RSI + spread + spike gate  |
   //| Returns 0=none, 1=BUY, -1=SELL                                   |
   //+------------------------------------------------------------------+
   int EvaluateScalpSignal(int idx)
   {
      // Must have a fresh EMA crossover
      int crossDir = m_symbolStates[idx].lastEmaCrossDirection;
      if(crossDir == 0)
         return 0;

      // RSI confirmation
      double rsi = m_symbolStates[idx].rsiValue;
      if(crossDir == 1)  // Bullish cross — BUY
      {
         if(rsi <= 0.0 || rsi >= m_config.rsiOverbought)
            return 0;
      }
      else  // Bearish cross — SELL
      {
         if(rsi <= 0.0 || rsi <= m_config.rsiOversold)
            return 0;
      }

      // Spread gate: spread < spreadMaxATRRatio * ATR
      string symbol = m_symbolStates[idx].symbol;
      double atr = m_symbolStates[idx].currentATR;
      if(atr <= 0.0)
         return 0;

      double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
      double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return 0;

      double spreadPrice = spread * point;
      if(spreadPrice > m_config.spreadMaxATRRatio * atr)
         return 0;

      // Spike window gate
      if(IsInSpikeWindow(idx))
      {
         m_totalSpikeWindowBlocks++;
         return 0;
      }

      return crossDir;
   }

   //+------------------------------------------------------------------+
   //| Open a scalp trade in the given direction                         |
   //+------------------------------------------------------------------+
   bool OpenScalpTrade(int idx, int direction)
   {
      string symbol = m_symbolStates[idx].symbol;
      double atr = m_symbolStates[idx].currentATR;

      if(atr <= 0.0)
      {
         PrintFormat("[ATR-SCALP] ATR is zero for %s — cannot calculate SL/TP", symbol);
         return false;
      }

      // Calculate SL and TP distances in price
      double slDistance = atr * m_config.slAtrMultiplier;
      double tpDistance = atr * m_config.tpAtrMultiplier;

      // Get current price
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(bid <= 0.0 || ask <= 0.0)
      {
         PrintFormat("[ATR-SCALP] Invalid prices for %s: bid=%.5f ask=%.5f", symbol, bid, ask);
         return false;
      }

      // Calculate lot size using CPositionSizer
      double lotSize = 0.0;
      ENUM_ORDER_TYPE orderType = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
      {
         PrintFormat("[ATR-SCALP] Invalid point for %s", symbol);
         return false;
      }

      double slPips = slDistance / point;

      if(m_positionSizer != NULL && m_positionSizer.IsInitialized())
      {
         lotSize = m_positionSizer.CalculateOptimalPositionSize(
                     symbol, orderType, slPips, 0.65);
      }
      else
      {
         double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
         lotSize = (minLot > 0.0) ? minLot : MIN_LOT_SIZE;
      }

      if(lotSize <= 0.0)
      {
         PrintFormat("[ATR-SCALP] Invalid lot size for %s: %.2f", symbol, lotSize);
         return false;
      }

      // Cap lot to available margin
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double marginPerLot = 0.0;
      double priceForMargin = (orderType == ORDER_TYPE_BUY) ? ask : bid;
      if(OrderCalcMargin(orderType, symbol, 1.0, priceForMargin, marginPerLot) && marginPerLot > 0.0)
      {
         double maxLotByMargin = freeMargin / (marginPerLot * 1.5);
         double symbolMaxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
         lotSize = MathMin(lotSize, MathMin(maxLotByMargin, symbolMaxVolume));
      }

      // Normalize lot to step size
      double stepVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minVol  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      if(stepVol <= 0.0) stepVol = 0.01;
      lotSize = MathRound(lotSize / stepVol) * stepVol;
      if(lotSize < minVol)
         lotSize = minVol;

      // Calculate entry, SL, TP
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double entryPrice = (direction == 1) ? ask : bid;
      double sl = 0.0, tp = 0.0;

      if(direction == 1) // BUY
      {
         sl = NormalizeDouble(entryPrice - slDistance, digits);
         tp = NormalizeDouble(entryPrice + tpDistance, digits);
      }
      else // SELL
      {
         sl = NormalizeDouble(entryPrice + slDistance, digits);
         tp = NormalizeDouble(entryPrice - tpDistance, digits);
      }

      // Calculate magic number: baseMagic + magicOffset + symbolIndex
      int magic = m_baseMagic + m_config.magicOffset + idx;

      // Set up trade object
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(50);
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);

      // Execute trade
      bool result = false;
      string dirStr = (direction == 1) ? "BUY" : "SELL";

      if(direction == 1)
         result = m_trade.Buy(lotSize, symbol, entryPrice, sl, tp,
                     "ATR-SCALP|" + dirStr);
      else
         result = m_trade.Sell(lotSize, symbol, entryPrice, sl, tp,
                     "ATR-SCALP|" + dirStr);

      if(result)
      {
         m_symbolStates[idx].lastTradeTime = TimeCurrent();
         m_totalTradesOpened++;

         PrintFormat("[ATR-SCALP] Symbol=%s Direction=%s Lot=%.2f SL=%.5f TP=%.5f ATR=%.5f magic=%d",
                     symbol, dirStr, lotSize, sl, tp, atr, magic);
      }
      else
      {
         uint retcode = m_trade.ResultRetcode();
         PrintFormat("[ATR-SCALP-FAILED] Symbol=%s Direction=%s Lot=%.2f retcode=%u",
                     symbol, dirStr, lotSize, retcode);
      }

      return result;
   }

   //+------------------------------------------------------------------+
   //| Manage open scalp positions: partial close, breakeven, trailing   |
   //+------------------------------------------------------------------+
   void ManageScalpPositions(int idx)
   {
      string symbol = m_symbolStates[idx].symbol;
      int total = PositionsTotal();
      int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
         return;

      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         if(!PositionSelectByTicket(ticket)) continue;

         // Only manage ATR-SCALP positions for this symbol
         string posSymbol = PositionGetString(POSITION_SYMBOL);
         if(posSymbol != symbol) continue;

         string comment = PositionGetString(POSITION_COMMENT);
         if(StringFind(comment, "ATR-SCALP") < 0) continue;

         double openPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL    = PositionGetDouble(POSITION_SL);
         double currentTP    = PositionGetDouble(POSITION_TP);
         double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
         double volume       = PositionGetDouble(POSITION_VOLUME);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         // Calculate profit in points
         double profitPoints = 0.0;
         if(posType == POSITION_TYPE_BUY)
            profitPoints = (currentPrice - openPrice) / point;
         else
            profitPoints = (openPrice - currentPrice) / point;

         // SL distance in points (1R)
         double slDistancePoints = 0.0;
         if(posType == POSITION_TYPE_BUY)
            slDistancePoints = MathAbs(openPrice - currentSL) / point;
         else
            slDistancePoints = MathAbs(currentSL - openPrice) / point;

         // 1. Partial close at 1R profit (50% of position)
         if(profitPoints >= slDistancePoints && slDistancePoints > 0.0)
         {
            double minVol  = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
            double stepVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
            if(stepVol <= 0.0) stepVol = 0.01;

            double halfVol = NormalizeDouble(volume * 0.5, 2);
            halfVol = MathFloor((halfVol + 1e-12) / stepVol) * stepVol;
            halfVol = NormalizeDouble(halfVol, 2);

            if(halfVol >= minVol && halfVol < volume)
            {
               if(m_trade.PositionClosePartial(ticket, halfVol))
               {
                  PrintFormat("[ATR-SCALP-PARTIAL] %s | ticket=%I64u | closed=%.2f | profit_pts=%.1f | 1R=%.1f",
                              symbol, ticket, halfVol, profitPoints, slDistancePoints);
               }
            }
         }

         // 2. Move SL to breakeven after breakevenProfitPoints (10 points)
         int breakevenProfitPoints = 10;
         if(profitPoints >= breakevenProfitPoints)
         {
            double beSL = 0.0;
            if(posType == POSITION_TYPE_BUY)
               beSL = NormalizeDouble(openPrice + 1 * point, digits);  // Entry + 1 point buffer
            else
               beSL = NormalizeDouble(openPrice - 1 * point, digits);

            // Only move SL if it improves the position
            bool shouldMove = false;
            if(posType == POSITION_TYPE_BUY && (currentSL < beSL || currentSL == 0.0))
               shouldMove = true;
            else if(posType == POSITION_TYPE_SELL && (currentSL > beSL || currentSL == 0.0))
               shouldMove = true;

            if(shouldMove)
            {
               if(m_trade.PositionModify(ticket, beSL, currentTP))
               {
                  PrintFormat("[ATR-SCALP-BREAKEVEN] %s | ticket=%I64u | SL=%.5f | profit_pts=%.1f",
                              symbol, ticket, beSL, profitPoints);
               }
            }
         }

         // 3. Tight trailing after breakeven (15 points)
         int trailingDistancePoints = 15;
         // Only trail if SL is already at breakeven or better
         bool isBreakevenOrBetter = false;
         if(posType == POSITION_TYPE_BUY && currentSL >= openPrice)
            isBreakevenOrBetter = true;
         else if(posType == POSITION_TYPE_SELL && (currentSL <= openPrice && currentSL > 0.0))
            isBreakevenOrBetter = true;

         if(isBreakevenOrBetter)
         {
            double newSL = 0.0;
            if(posType == POSITION_TYPE_BUY)
            {
               newSL = NormalizeDouble(currentPrice - trailingDistancePoints * point, digits);
               if(newSL > currentSL)
               {
                  m_trade.PositionModify(ticket, newSL, currentTP);
               }
            }
            else
            {
               newSL = NormalizeDouble(currentPrice + trailingDistancePoints * point, digits);
               if(currentSL == 0.0 || newSL < currentSL)
               {
                  m_trade.PositionModify(ticket, newSL, currentTP);
               }
            }
         }
      }
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CATRScalpingEngine() :
      m_symbolCount(0),
      m_baseMagic(0),
      m_positionSizer(NULL),
      m_totalTradesOpened(0),
      m_totalTradesSkipped(0),
      m_totalSpikeWindowBlocks(0)
   {
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CATRScalpingEngine()
   {
      Deinit();
   }

   //+------------------------------------------------------------------+
   //| Initialize the engine with config and dependencies               |
   //+------------------------------------------------------------------+
   bool Init(const SATRScalpingConfig &config, int baseMagic, CPositionSizer *pSizer)
   {
      m_config         = config;
      m_baseMagic      = baseMagic;
      m_positionSizer  = pSizer;
      m_symbolCount    = 0;

      PrintFormat("[ATR-SCALP-ENGINE] Initialized | atrPeriod=%d | emaFast=%d | emaSlow=%d | rsi=%d | slATR=%.1f | tpATR=%.1f | maxPos=%d | cooldown=%dms | spikeAvoid=%dmin | magicOffset=%d",
                  m_config.atrPeriod,
                  m_config.emaFastPeriod,
                  m_config.emaSlowPeriod,
                  m_config.rsiPeriod,
                  m_config.slAtrMultiplier,
                  m_config.tpAtrMultiplier,
                  m_config.maxPositions,
                  m_config.cooldownMs,
                  m_config.spikeWindowAvoidMinutes,
                  m_config.magicOffset);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Add a symbol to monitor for ATR scalping                         |
   //| spikeIntervalSec: expected spike interval (0 = no spike tracking) |
   //+------------------------------------------------------------------+
   bool AddSymbol(const string symbol, int spikeIntervalSec = 0)
   {
      // Check for duplicate
      if(FindSymbolIndex(symbol) >= 0)
      {
         PrintFormat("[ATR-SCALP-ENGINE] Symbol %s already registered", symbol);
         return false;
      }

      // Create indicator handles
      int atrHandle = iATR(symbol, PERIOD_M1, m_config.atrPeriod);
      if(atrHandle == INVALID_HANDLE)
      {
         PrintFormat("[ATR-SCALP-ENGINE] Failed to create ATR handle for %s", symbol);
         return false;
      }

      int emaFastHandle = iMA(symbol, PERIOD_M1, m_config.emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(emaFastHandle == INVALID_HANDLE)
      {
         IndicatorRelease(atrHandle);
         PrintFormat("[ATR-SCALP-ENGINE] Failed to create EMA fast handle for %s", symbol);
         return false;
      }

      int emaSlowHandle = iMA(symbol, PERIOD_M1, m_config.emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
      if(emaSlowHandle == INVALID_HANDLE)
      {
         IndicatorRelease(atrHandle);
         IndicatorRelease(emaFastHandle);
         PrintFormat("[ATR-SCALP-ENGINE] Failed to create EMA slow handle for %s", symbol);
         return false;
      }

      int rsiHandle = iRSI(symbol, PERIOD_M1, m_config.rsiPeriod, PRICE_CLOSE);
      if(rsiHandle == INVALID_HANDLE)
      {
         IndicatorRelease(atrHandle);
         IndicatorRelease(emaFastHandle);
         IndicatorRelease(emaSlowHandle);
         PrintFormat("[ATR-SCALP-ENGINE] Failed to create RSI handle for %s", symbol);
         return false;
      }

      // Resize arrays — use temp struct pattern for string members
      int newSize = m_symbolCount + 1;

      SATRScalpSymbolState tempStates[];
      ArrayResize(tempStates, newSize);
      for(int i = 0; i < m_symbolCount; i++)
         tempStates[i] = m_symbolStates[i];
      ArrayResize(m_symbolStates, newSize);
      for(int i = 0; i < m_symbolCount; i++)
         m_symbolStates[i] = tempStates[i];

      ArrayResize(m_atrHandles, newSize);
      ArrayResize(m_emaFastHandles, newSize);
      ArrayResize(m_emaSlowHandles, newSize);
      ArrayResize(m_rsiHandles, newSize);

      // Initialize new slot
      InitializeSymbolState(m_symbolCount, symbol, spikeIntervalSec);
      m_atrHandles[m_symbolCount]     = atrHandle;
      m_emaFastHandles[m_symbolCount] = emaFastHandle;
      m_emaSlowHandles[m_symbolCount] = emaSlowHandle;
      m_rsiHandles[m_symbolCount]     = rsiHandle;
      m_symbolCount++;

      PrintFormat("[ATR-SCALP-ENGINE] Symbol added: %s (index=%d atrHandle=%d emaFast=%d emaSlow=%d rsi=%d spikeInterval=%ds)",
                  symbol, m_symbolCount - 1, atrHandle, emaFastHandle, emaSlowHandle, rsiHandle, spikeIntervalSec);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Release all indicator handles and clean up                       |
   //+------------------------------------------------------------------+
   void Deinit()
   {
      for(int i = 0; i < m_symbolCount; i++)
      {
         if(m_atrHandles[i] != INVALID_HANDLE)
         {
            IndicatorRelease(m_atrHandles[i]);
            m_atrHandles[i] = INVALID_HANDLE;
         }
         if(m_emaFastHandles[i] != INVALID_HANDLE)
         {
            IndicatorRelease(m_emaFastHandles[i]);
            m_emaFastHandles[i] = INVALID_HANDLE;
         }
         if(m_emaSlowHandles[i] != INVALID_HANDLE)
         {
            IndicatorRelease(m_emaSlowHandles[i]);
            m_emaSlowHandles[i] = INVALID_HANDLE;
         }
         if(m_rsiHandles[i] != INVALID_HANDLE)
         {
            IndicatorRelease(m_rsiHandles[i]);
            m_rsiHandles[i] = INVALID_HANDLE;
         }
      }
      m_symbolCount = 0;

      PrintFormat("[ATR-SCALP-ENGINE] Deinitialized | trades=%d | skipped=%d | spikeBlocks=%d",
                  m_totalTradesOpened, m_totalTradesSkipped, m_totalSpikeWindowBlocks);
   }

   //+------------------------------------------------------------------+
   //| Process a tick for a given symbol — call every tick               |
   //+------------------------------------------------------------------+
   void ProcessTick(const string symbol, double bid, double ask)
   {
      // 1. Find symbol index
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
         return;

      if(!m_symbolStates[idx].isActive)
         return;

      // 2. Update indicator values
      if(!UpdateIndicators(idx))
         return;

      // 3. Check spike window
      bool inSpikeWindow = IsInSpikeWindow(idx);

      // 4. Evaluate scalp signal
      int signal = EvaluateScalpSignal(idx);

      // 5. If signal and not in spike window, open trade
      if(signal != 0 && !inSpikeWindow)
      {
         // Check cooldown
         datetime now = TimeCurrent();
         if(m_symbolStates[idx].lastTradeTime > 0)
         {
            ulong elapsedMs = (ulong)((now - m_symbolStates[idx].lastTradeTime) * 1000);
            if(elapsedMs < (ulong)m_config.cooldownMs)
            {
               m_totalTradesSkipped++;
               // Still manage existing positions even if cooldown blocks new entry
               ManageScalpPositions(idx);
               return;
            }
         }

         // Check max positions
         if(GetActiveScalpPositions() >= m_config.maxPositions)
         {
            m_totalTradesSkipped++;
            ManageScalpPositions(idx);
            return;
         }

         OpenScalpTrade(idx, signal);
      }

      // 6. Manage existing scalp positions
      ManageScalpPositions(idx);
   }

   //+------------------------------------------------------------------+
   //| Called by SpikeHunter when a spike is detected                    |
   //| Updates lastSpikeTime for spike window calculation                |
   //+------------------------------------------------------------------+
   void NotifySpikeDetected(const string symbol)
   {
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
         return;

      m_symbolStates[idx].lastSpikeTime = TimeCurrent();
      PrintFormat("[ATR-SCALP] Spike detected for %s — updated lastSpikeTime", symbol);
   }

   //+------------------------------------------------------------------+
   //| Set expected spike interval for a symbol                          |
   //+------------------------------------------------------------------+
   void SetSpikeInterval(const string symbol, int intervalSec)
   {
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
      {
         PrintFormat("[ATR-SCALP] Cannot set spike interval — symbol %s not registered", symbol);
         return;
      }

      m_symbolStates[idx].expectedSpikeIntervalSec = intervalSec;
      PrintFormat("[ATR-SCALP] Spike interval set for %s: %ds", symbol, intervalSec);
   }

   //+------------------------------------------------------------------+
   //| Count positions with "ATR-SCALP" in comment                       |
   //+------------------------------------------------------------------+
   int GetActiveScalpPositions() const
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
            if(StringFind(comment, "ATR-SCALP") >= 0)
               count++;
         }
      }
      return count;
   }

   //+------------------------------------------------------------------+
   //| Print diagnostics                                                 |
   //+------------------------------------------------------------------+
   void PrintDiagnostics()
   {
      PrintFormat("[ATR-SCALP-DIAG] symbols=%d | trades=%d | skipped=%d | spikeBlocks=%d | activePos=%d",
                  m_symbolCount,
                  m_totalTradesOpened,
                  m_totalTradesSkipped,
                  m_totalSpikeWindowBlocks,
                  GetActiveScalpPositions());

      for(int i = 0; i < m_symbolCount; i++)
      {
         PrintFormat("[ATR-SCALP-DIAG] %s | atr=%.5f emaFast=%.5f emaSlow=%.5f rsi=%.1f cross=%d spikeWindow=%s spikeInterval=%ds lastSpike=%s",
                     m_symbolStates[i].symbol,
                     m_symbolStates[i].currentATR,
                     m_symbolStates[i].emaFastValue,
                     m_symbolStates[i].emaSlowValue,
                     m_symbolStates[i].rsiValue,
                     m_symbolStates[i].lastEmaCrossDirection,
                     m_symbolStates[i].inSpikeWindow ? "Y" : "N",
                     m_symbolStates[i].expectedSpikeIntervalSec,
                     TimeToString(m_symbolStates[i].lastSpikeTime));
      }
   }
};

#endif // CORE_SCALP_ATR_SCALPING_ENGINE_MQH
