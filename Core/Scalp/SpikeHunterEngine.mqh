//+------------------------------------------------------------------+
//| SpikeHunterEngine.mqh                                            |
//| Spike hunting engine for synthetic CFD indices                   |
//| Detects pre-spike conditions and opens trades IN the spike       |
//| direction, independent of existing long-term positions           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_SPIKE_HUNTER_ENGINE_MQH
#define CORE_SCALP_SPIKE_HUNTER_ENGINE_MQH

#include "../Utils/Instruments.mqh"
#include "../Risk/PositionSizer.mqh"
#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Spike hunter configuration struct                                 |
//+------------------------------------------------------------------+
struct SSpikeHunterConfig
{
   double   velocityMultiplier;         // Tick rate multiplier threshold (default 2.5)
   int      minConsecutiveTicks;        // Min consecutive ticks in one direction (default 12)
   int      consecutiveTickWindowMs;    // Time window for consecutive ticks in ms (default 60000)
   double   atrCompressionRatio;       // ATR compression threshold (default 0.60)
   int      atrPeriod;                 // ATR period (default 14)
   int      atrSmaPeriod;              // SMA period for ATR baseline (default 50)
   double   slAtrMultiplier;           // SL = this * ATR (default 1.5)
   double   tpAtrMultiplier;           // TP = this * ATR (default 3.0)
   int      maxSpikePositions;         // Max concurrent spike positions (default 3)
   int      cooldownMs;                // Cooldown between spike trades in ms (default 60000)
   int      spikeCooldownForLongTermMs;// Cooldown for long-term entries after spike (default 60000)
   int      magicOffset;               // Magic number offset from base (default 9000)
   bool     enablePushAlerts;          // Send push notifications (default true)
   int      alertThrottleSeconds;      // Min seconds between push alerts (default 120)
   int      minConfluence;             // Min detection layers to confirm (default 1)

   // Default constructor with production defaults
   SSpikeHunterConfig()
   {
      velocityMultiplier         = 1.8;
      minConsecutiveTicks        = 6;
      consecutiveTickWindowMs    = 60000;
      atrCompressionRatio       = 0.80;
      atrPeriod                 = 14;
      atrSmaPeriod              = 50;
      slAtrMultiplier           = 1.5;
      tpAtrMultiplier           = 3.0;
      maxSpikePositions         = 3;
      cooldownMs                = 60000;
      spikeCooldownForLongTermMs = 60000;
      magicOffset               = 9000;
      enablePushAlerts          = true;
      alertThrottleSeconds      = 120;
      minConfluence             = 1;
   }
};

//+------------------------------------------------------------------+
//| Per-symbol spike state tracking                                   |
//+------------------------------------------------------------------+
struct SSpikeSymbolState
{
   string   symbol;
   bool     isActive;                  // Is this symbol being monitored

   // Tick velocity tracking
   datetime tickWindowStart;
   int      tickWindowCount;
   double   tickRateBaseline;          // EMA baseline tick rate
   bool     velocityTriggered;         // Layer 1 triggered

   // Direction accumulation tracking
   int      consecutiveUpTicks;        // Consecutive upward ticks
   int      consecutiveDownTicks;      // Consecutive downward ticks
   double   lastBid;                   // Last bid for direction comparison
   datetime directionWindowStart;      // Start of direction accumulation window
   bool     directionTriggered;        // Layer 2 triggered
   int      directionSign;             // +1 = up, -1 = down

   // ATR compression tracking
   double   currentATR;
   double   atrSMA;
   bool     compressionTriggered;      // Layer 3 triggered

   // Spike state
   int      confluenceCount;           // How many layers are triggered
   datetime lastSpikeTradeTime;        // When last spike trade was opened
   datetime lastSpikeDetectionTime;    // When spike was last detected (for long-term cooldown)
   bool     inSpikeCooldown;           // Whether this symbol is in cooldown for long-term entries
   datetime lastDiagTime;              // Last time near-miss diagnostic was logged
};

//+------------------------------------------------------------------+
//| Per-symbol family override parameters (Batch 102)                 |
//+------------------------------------------------------------------+
struct SSpikeHunterFamilyOverrides
{
   string   symbol;
   double   velocityMultiplier;
   int      minConsecutiveTicks;
   double   atrCompressionRatio;
   double   slAtrMultiplier;
   double   tpAtrMultiplier;
   int      magicOffset;
   int      cooldownMs;
   int      minConfluence;
   bool     hasOverrides;

   SSpikeHunterFamilyOverrides()
   {
      symbol                = "";
      velocityMultiplier    = 0.0;    // 0 = use default config
      minConsecutiveTicks   = 0;      // 0 = use default config
      atrCompressionRatio   = 0.0;    // 0 = use default config
      slAtrMultiplier       = 0.0;    // 0 = use default config
      tpAtrMultiplier       = 0.0;    // 0 = use default config
      magicOffset           = 0;      // 0 = use default config
      cooldownMs            = 0;      // 0 = use default config
      minConfluence         = 0;      // 0 = use default config
      hasOverrides          = false;
   }
};

//+------------------------------------------------------------------+
//| CSpikeHunterEngine — Spike hunting engine for synthetic CFDs      |
//+------------------------------------------------------------------+
class CSpikeHunterEngine
{
private:
   SSpikeHunterConfig              m_config;
   SSpikeSymbolState               m_symbolStates[];
   int                             m_symbolCount;
   int                             m_baseMagic;
   CPositionSizer*                 m_positionSizer;
   CTrade                          m_trade;                // For synchronous order execution

   // Family-specific overrides (Batch 102)
   SSpikeHunterFamilyOverrides     m_familyOverrides[];
   int                             m_familyOverrideCount;

   // Alert throttling
   datetime                        m_lastPushAlertTime;
   int                             m_pushAlertCount;

   // ATR handle cache
   int                             m_atrHandles[];         // ATR indicator handles per symbol
   // ATR SMA is computed manually from ATR buffer (MQL5 cannot apply MA to indicator output)

   // Statistics
   int                             m_totalDetections;
   int                             m_totalTradesOpened;
   int                             m_totalTradesSkipped;

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
   //| Find family override index for a symbol (Batch 102)               |
   //+------------------------------------------------------------------+
   int FindFamilyOverrideIndex(const string symbol) const
   {
      for(int i = 0; i < m_familyOverrideCount; i++)
      {
         if(m_familyOverrides[i].symbol == symbol)
            return i;
      }
      return -1;
   }

   //+------------------------------------------------------------------+
   //| Get effective velocity multiplier for a symbol (Batch 102)        |
   //+------------------------------------------------------------------+
   double GetEffectiveVelocityMultiplier(int idx) const
   {
      int oi = FindFamilyOverrideIndex(m_symbolStates[idx].symbol);
      if(oi >= 0 && m_familyOverrides[oi].hasOverrides && m_familyOverrides[oi].velocityMultiplier > 0.0)
         return m_familyOverrides[oi].velocityMultiplier;
      return m_config.velocityMultiplier;
   }

   //+------------------------------------------------------------------+
   //| Get effective min consecutive ticks for a symbol (Batch 102)      |
   //+------------------------------------------------------------------+
   int GetEffectiveMinConsecutiveTicks(int idx) const
   {
      int oi = FindFamilyOverrideIndex(m_symbolStates[idx].symbol);
      if(oi >= 0 && m_familyOverrides[oi].hasOverrides && m_familyOverrides[oi].minConsecutiveTicks > 0)
         return m_familyOverrides[oi].minConsecutiveTicks;
      return m_config.minConsecutiveTicks;
   }

   //+------------------------------------------------------------------+
   //| Get effective ATR compression ratio for a symbol (Batch 102)      |
   //+------------------------------------------------------------------+
   double GetEffectiveATRCompressionRatio(int idx) const
   {
      int oi = FindFamilyOverrideIndex(m_symbolStates[idx].symbol);
      if(oi >= 0 && m_familyOverrides[oi].hasOverrides && m_familyOverrides[oi].atrCompressionRatio > 0.0)
         return m_familyOverrides[oi].atrCompressionRatio;
      return m_config.atrCompressionRatio;
   }

   //+------------------------------------------------------------------+
   //| Get effective SL ATR multiplier for a symbol (Batch 102)          |
   //+------------------------------------------------------------------+
   double GetEffectiveSLAtrMultiplier(int idx) const
   {
      int oi = FindFamilyOverrideIndex(m_symbolStates[idx].symbol);
      if(oi >= 0 && m_familyOverrides[oi].hasOverrides && m_familyOverrides[oi].slAtrMultiplier > 0.0)
         return m_familyOverrides[oi].slAtrMultiplier;
      return m_config.slAtrMultiplier;
   }

   //+------------------------------------------------------------------+
   //| Get effective TP ATR multiplier for a symbol (Batch 102)          |
   //+------------------------------------------------------------------+
   double GetEffectiveTPAtrMultiplier(int idx) const
   {
      int oi = FindFamilyOverrideIndex(m_symbolStates[idx].symbol);
      if(oi >= 0 && m_familyOverrides[oi].hasOverrides && m_familyOverrides[oi].tpAtrMultiplier > 0.0)
         return m_familyOverrides[oi].tpAtrMultiplier;
      return m_config.tpAtrMultiplier;
   }

   //+------------------------------------------------------------------+
   //| Get effective magic offset for a symbol (Batch 102)               |
   //+------------------------------------------------------------------+
   int GetEffectiveMagicOffset(int idx) const
   {
      int oi = FindFamilyOverrideIndex(m_symbolStates[idx].symbol);
      if(oi >= 0 && m_familyOverrides[oi].hasOverrides && m_familyOverrides[oi].magicOffset > 0)
         return m_familyOverrides[oi].magicOffset;
      return m_config.magicOffset;
   }

   //+------------------------------------------------------------------+
   //| Get effective cooldown for a symbol (Batch 102)                   |
   //+------------------------------------------------------------------+
   int GetEffectiveCooldownMs(int idx) const
   {
      int oi = FindFamilyOverrideIndex(m_symbolStates[idx].symbol);
      if(oi >= 0 && m_familyOverrides[oi].hasOverrides && m_familyOverrides[oi].cooldownMs > 0)
         return m_familyOverrides[oi].cooldownMs;
      return m_config.cooldownMs;
   }

   //+------------------------------------------------------------------+
   //| Get effective min confluence for a symbol (Batch 102)             |
   //+------------------------------------------------------------------+
   int GetEffectiveMinConfluence(int idx) const
   {
      int oi = FindFamilyOverrideIndex(m_symbolStates[idx].symbol);
      if(oi >= 0 && m_familyOverrides[oi].hasOverrides && m_familyOverrides[oi].minConfluence > 0)
         return m_familyOverrides[oi].minConfluence;
      return m_config.minConfluence;
   }

   //+------------------------------------------------------------------+
   //| Initialize a symbol state slot with defaults                      |
   //+------------------------------------------------------------------+
   void InitializeSymbolState(int idx, const string symbol)
   {
      m_symbolStates[idx].symbol                = symbol;
      m_symbolStates[idx].isActive              = true;
      m_symbolStates[idx].tickWindowStart       = TimeCurrent();
      m_symbolStates[idx].tickWindowCount       = 0;
      m_symbolStates[idx].tickRateBaseline      = 0.0;
      m_symbolStates[idx].velocityTriggered     = false;
      m_symbolStates[idx].consecutiveUpTicks    = 0;
      m_symbolStates[idx].consecutiveDownTicks  = 0;
      m_symbolStates[idx].lastBid               = 0.0;
      m_symbolStates[idx].directionWindowStart  = TimeCurrent();
      m_symbolStates[idx].directionTriggered    = false;
      m_symbolStates[idx].directionSign         = 0;
      m_symbolStates[idx].currentATR            = 0.0;
      m_symbolStates[idx].atrSMA                = 0.0;
      m_symbolStates[idx].compressionTriggered  = false;
      m_symbolStates[idx].confluenceCount       = 0;
      m_symbolStates[idx].lastSpikeTradeTime    = 0;
      m_symbolStates[idx].lastSpikeDetectionTime = 0;
      m_symbolStates[idx].inSpikeCooldown       = false;
      m_symbolStates[idx].lastDiagTime          = 0;
   }

   //+------------------------------------------------------------------+
   //| Update tick velocity (Layer 1)                                    |
   //| Count ticks per 1-second window, maintain EMA baseline,           |
   //| trigger when currentRate > baseline * velocityMultiplier           |
   //+------------------------------------------------------------------+
   void UpdateTickVelocity(int idx)
   {
      datetime now = TimeCurrent();
      m_symbolStates[idx].tickWindowCount++;

      int elapsedSeconds = (int)(now - m_symbolStates[idx].tickWindowStart);
      if(elapsedSeconds < 1)
         return;

      double currentRate = (double)m_symbolStates[idx].tickWindowCount / (double)MathMax(1, elapsedSeconds);

      // Update EMA baseline: baseline = baseline * 0.85 + currentRate * 0.15
      if(m_symbolStates[idx].tickRateBaseline <= 0.0)
         m_symbolStates[idx].tickRateBaseline = currentRate;
      else
         m_symbolStates[idx].tickRateBaseline = m_symbolStates[idx].tickRateBaseline * 0.85 + currentRate * 0.15;

      // Check trigger: currentRate > baseline * velocityMultiplier
      double threshold = MathMax(1.0, m_symbolStates[idx].tickRateBaseline) * GetEffectiveVelocityMultiplier(idx);
      m_symbolStates[idx].velocityTriggered = (currentRate > threshold);

      // Reset window
      m_symbolStates[idx].tickWindowStart = now;
      m_symbolStates[idx].tickWindowCount = 0;
   }

   //+------------------------------------------------------------------+
   //| Update direction accumulation (Layer 2)                           |
   //| Track consecutive ticks in one direction within a time window     |
   //+------------------------------------------------------------------+
   void UpdateDirectionAccumulation(int idx, double bid)
   {
      datetime now = TimeCurrent();

      // Check if window expired (consecutiveTickWindowMs)
      int windowElapsedMs = (int)((now - m_symbolStates[idx].directionWindowStart) * 1000);
      if(windowElapsedMs > m_config.consecutiveTickWindowMs)
      {
         // Window expired — reset counters
         m_symbolStates[idx].consecutiveUpTicks   = 0;
         m_symbolStates[idx].consecutiveDownTicks = 0;
         m_symbolStates[idx].directionWindowStart = now;
         m_symbolStates[idx].directionTriggered   = false;
         m_symbolStates[idx].directionSign        = 0;
      }

      // Compare with last bid
      if(m_symbolStates[idx].lastBid <= 0.0)
      {
         m_symbolStates[idx].lastBid = bid;
         return;
      }

      if(bid > m_symbolStates[idx].lastBid)
      {
         // Up tick
         m_symbolStates[idx].consecutiveUpTicks++;
         m_symbolStates[idx].consecutiveDownTicks = 0;
      }
      else if(bid < m_symbolStates[idx].lastBid)
      {
         // Down tick
         m_symbolStates[idx].consecutiveDownTicks++;
         m_symbolStates[idx].consecutiveUpTicks = 0;
      }
      else
      {
         // No change — reset both
         m_symbolStates[idx].consecutiveUpTicks   = 0;
         m_symbolStates[idx].consecutiveDownTicks = 0;
      }

      m_symbolStates[idx].lastBid = bid;

      // Check trigger
      int effectiveMinTicks = GetEffectiveMinConsecutiveTicks(idx);
      if(m_symbolStates[idx].consecutiveUpTicks >= effectiveMinTicks)
      {
         m_symbolStates[idx].directionTriggered = true;
         m_symbolStates[idx].directionSign      = 1;
      }
      else if(m_symbolStates[idx].consecutiveDownTicks >= effectiveMinTicks)
      {
         m_symbolStates[idx].directionTriggered = true;
         m_symbolStates[idx].directionSign      = -1;
      }
      else
      {
         m_symbolStates[idx].directionTriggered = false;
      }
   }

   //+------------------------------------------------------------------+
   //| Update ATR compression (Layer 3)                                  |
   //| Trigger when ATR(14) <= SMA(ATR,50) * atrCompressionRatio        |
   //| ATR SMA is computed manually from ATR buffer values               |
   //+------------------------------------------------------------------+
   void UpdateATRCompression(int idx)
   {
      string symbol = m_symbolStates[idx].symbol;

      // Get ATR handle
      if(m_atrHandles[idx] == INVALID_HANDLE)
         return;

      // Read current ATR value
      double atrBuf[];
      ArraySetAsSeries(atrBuf, true);
      if(CopyBuffer(m_atrHandles[idx], 0, 0, 1, atrBuf) <= 0)
         return;

      m_symbolStates[idx].currentATR = atrBuf[0];

      // Compute ATR SMA manually from last atrSmaPeriod ATR values
      double atrHistory[];
      ArraySetAsSeries(atrHistory, true);
      int copied = CopyBuffer(m_atrHandles[idx], 0, 0, m_config.atrSmaPeriod, atrHistory);
      if(copied < m_config.atrSmaPeriod)
      {
         m_symbolStates[idx].compressionTriggered = false;
         return;
      }

      double atrSma = 0.0;
      for(int i = 0; i < copied; i++)
         atrSma += atrHistory[i];
      atrSma /= (double)copied;

      m_symbolStates[idx].atrSMA = atrSma;

      // Check compression: ATR <= SMA * ratio
      if(m_symbolStates[idx].atrSMA > 0.0 && m_symbolStates[idx].currentATR > 0.0)
      {
         m_symbolStates[idx].compressionTriggered =
            (m_symbolStates[idx].currentATR <= m_symbolStates[idx].atrSMA * GetEffectiveATRCompressionRatio(idx));
      }
      else
      {
         m_symbolStates[idx].compressionTriggered = false;
      }
   }

   //+------------------------------------------------------------------+
   //| Count how many detection layers are triggered                     |
   //+------------------------------------------------------------------+
   int CountConfluence(int idx) const
   {
      int count = 0;
      if(m_symbolStates[idx].velocityTriggered)    count++;
      if(m_symbolStates[idx].directionTriggered)   count++;
      if(m_symbolStates[idx].compressionTriggered) count++;
      return count;
   }

   //+------------------------------------------------------------------+
   //| Determine spike direction based on symbol type and detection      |
   //+------------------------------------------------------------------+
   int DetermineSpikeDirection(int idx) const
   {
      string symbol = m_symbolStates[idx].symbol;
      int certainDir = 0;

      if(IsSpikeSymbolDirectionCertain(symbol, certainDir))
         return certainDir;

      // For SFX Vol, FX Vol, SwitchX: use detected direction from Layer 2
      return m_symbolStates[idx].directionSign;
   }

   //+------------------------------------------------------------------+
   //| Check if symbol has a certain spike direction                     |
   //| Returns true and sets direction for PainX/Crash/Boom/GainX       |
   //+------------------------------------------------------------------+
   bool IsSpikeSymbolDirectionCertain(const string symbol, int &direction) const
   {
      // PainX: always SELL (-1)
      if(IsPainSyntheticSymbolName(symbol))
      {
         direction = -1;
         return true;
      }

      // GainX/FlipX: always BUY (+1)
      if(IsGainFlipSyntheticSymbolName(symbol))
      {
         direction = 1;
         return true;
      }

      // Boom/Crash: Boom=BUY(+1), Crash=SELL(-1)
      if(IsBoomCrashSyntheticSymbolName(symbol))
      {
         string normalized = NormalizeInstrumentSymbolName(symbol);
         if(StringFind(normalized, "BOOM") >= 0)
         {
            direction = 1;
            return true;
         }
         if(StringFind(normalized, "CRASH") >= 0)
         {
            direction = -1;
            return true;
         }
      }

      // SFX Vol, FX Vol, SwitchX, and others: direction is not certain
      return false;
   }

   //+------------------------------------------------------------------+
   //| Check if we can open a spike trade for this symbol                |
   //+------------------------------------------------------------------+
   bool CanOpenSpikeTrade(int idx) const
   {
      // Check cooldown (use family-specific cooldown)
      datetime now = TimeCurrent();
      if(m_symbolStates[idx].lastSpikeTradeTime > 0)
      {
         ulong elapsedMs = (ulong)((now - m_symbolStates[idx].lastSpikeTradeTime) * 1000);
         if(elapsedMs < (ulong)GetEffectiveCooldownMs(idx))
            return false;
      }

      // Check max spike positions
      if(GetActiveSpikePositions() >= m_config.maxSpikePositions)
         return false;

      return true;
   }

   //+------------------------------------------------------------------+
   //| Open a spike trade in the given direction                         |
   //+------------------------------------------------------------------+
   bool OpenSpikeTrade(int idx, int direction)
   {
      string symbol = m_symbolStates[idx].symbol;
      double atr = m_symbolStates[idx].currentATR;

      if(atr <= 0.0)
      {
         PrintFormat("[SPIKE-HUNT-TRADE] ATR is zero for %s — cannot calculate SL/TP", symbol);
         return false;
      }

      // Calculate SL and TP distances in price (use family-specific multipliers)
      double slDistance = atr * GetEffectiveSLAtrMultiplier(idx);
      double tpDistance = atr * GetEffectiveTPAtrMultiplier(idx);

      // Convert SL distance to pips for position sizer
      double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
      if(point <= 0.0)
      {
         PrintFormat("[SPIKE-HUNT-TRADE] Invalid point for %s", symbol);
         return false;
      }

      double slPips = slDistance / point;
      double tpPips = tpDistance / point;

      // Get current price
      double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(bid <= 0.0 || ask <= 0.0)
      {
         PrintFormat("[SPIKE-HUNT-TRADE] Invalid prices for %s: bid=%.5f ask=%.5f", symbol, bid, ask);
         return false;
      }

      // Calculate lot size using CPositionSizer
      double lotSize = 0.0;
      ENUM_ORDER_TYPE orderType = (direction == 1) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

      if(m_positionSizer != NULL && m_positionSizer.IsInitialized())
      {
         lotSize = m_positionSizer.CalculateOptimalPositionSize(
                     symbol, orderType, slPips, 0.80);
      }
      else
      {
         double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
         lotSize = (minLot > 0.0) ? minLot : MIN_LOT_SIZE;
      }

      if(lotSize <= 0.0)
      {
         PrintFormat("[SPIKE-HUNT-TRADE] Invalid lot size for %s: %.2f", symbol, lotSize);
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

      // Calculate magic number: baseMagic + familyMagicOffset + symbolIndex
      int magic = m_baseMagic + GetEffectiveMagicOffset(idx) + idx;

      // Set up trade object
      m_trade.SetExpertMagicNumber(magic);
      m_trade.SetDeviationInPoints(50);
      m_trade.SetTypeFilling(ORDER_FILLING_IOC);

      // Execute trade synchronously (speed matters for spikes)
      bool result = false;
      string dirStr = (direction == 1) ? "BUY" : "SELL";

      if(direction == 1)
         result = m_trade.Buy(lotSize, symbol, entryPrice, sl, tp,
                     "SPIKE-HUNT|" + dirStr + "|C:" + IntegerToString(m_symbolStates[idx].confluenceCount) + "/3");
      else
         result = m_trade.Sell(lotSize, symbol, entryPrice, sl, tp,
                     "SPIKE-HUNT|" + dirStr + "|C:" + IntegerToString(m_symbolStates[idx].confluenceCount) + "/3");

      if(result)
      {
         m_symbolStates[idx].lastSpikeTradeTime = TimeCurrent();
         m_symbolStates[idx].lastSpikeDetectionTime = TimeCurrent();
         m_symbolStates[idx].inSpikeCooldown = true;
         m_totalTradesOpened++;

         PrintFormat("[SPIKE-HUNT-TRADE] Symbol=%s Direction=%s Lot=%.2f SL=%.5f TP=%.5f Confluence=%d/3 ATR=%.5f magic=%d",
                     symbol, dirStr, lotSize, sl, tp,
                     m_symbolStates[idx].confluenceCount, atr, magic);
      }
      else
      {
         uint retcode = m_trade.ResultRetcode();
         PrintFormat("[SPIKE-HUNT-TRADE-FAILED] Symbol=%s Direction=%s Lot=%.2f retcode=%u",
                     symbol, dirStr, lotSize, retcode);
      }

      return result;
   }

   //+------------------------------------------------------------------+
   //| Send a throttled push notification                               |
   //+------------------------------------------------------------------+
   void SendThrottledAlert(const string message)
   {
      if(!m_config.enablePushAlerts)
         return;

      datetime now = TimeCurrent();
      int elapsedSeconds = (int)(now - m_lastPushAlertTime);

      if(elapsedSeconds < m_config.alertThrottleSeconds)
      {
         PrintFormat("[SPIKE-HUNT-ALERT-THROTTLED] Alert suppressed (last sent %ds ago)", elapsedSeconds);
         return;
      }

      if(SendNotification(message))
      {
         m_lastPushAlertTime = now;
         m_pushAlertCount++;
         PrintFormat("[SPIKE-HUNT-ALERT] Push notification sent: %s", message);
      }
      else
      {
         PrintFormat("[SPIKE-HUNT-ALERT-FAILED] SendNotification failed for: %s", message);
      }
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CSpikeHunterEngine() :
      m_symbolCount(0),
      m_baseMagic(0),
      m_familyOverrideCount(0),
      m_positionSizer(NULL),
      m_lastPushAlertTime(0),
      m_pushAlertCount(0),
      m_totalDetections(0),
      m_totalTradesOpened(0),
      m_totalTradesSkipped(0)
   {
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CSpikeHunterEngine()
   {
      Deinit();
   }

   //+------------------------------------------------------------------+
   //| Initialize the engine with config and dependencies               |
   //+------------------------------------------------------------------+
   bool Init(const SSpikeHunterConfig &config, int baseMagic, CPositionSizer *pSizer)
   {
      m_config         = config;
      m_baseMagic      = baseMagic;
      m_positionSizer  = pSizer;
      m_symbolCount    = 0;

      PrintFormat("[SPIKE-HUNT-ENGINE] Initialized | velMult=%.1f | minTicks=%d | atrRatio=%.2f | slATR=%.1f | tpATR=%.1f | maxPos=%d | cooldown=%dms | confluence=%d/3 | magicOffset=%d",
                  m_config.velocityMultiplier,
                  m_config.minConsecutiveTicks,
                  m_config.atrCompressionRatio,
                  m_config.slAtrMultiplier,
                  m_config.tpAtrMultiplier,
                  m_config.maxSpikePositions,
                  m_config.cooldownMs,
                  m_config.minConfluence,
                  m_config.magicOffset);

      // Log effective confluence config per symbol family
      PrintFormat("[SPIKE-HUNTER-CONFIG] Base minConfluence=%d/3 | familyOverrides=%d",
                  m_config.minConfluence, m_familyOverrideCount);
      for(int i = 0; i < m_familyOverrideCount; i++)
      {
         if(m_familyOverrides[i].hasOverrides)
         {
            int effConf = (m_familyOverrides[i].minConfluence > 0) ? m_familyOverrides[i].minConfluence : m_config.minConfluence;
            PrintFormat("[SPIKE-HUNTER-CONFIG] %s | effectiveMinConfluence=%d/3 (override=%d base=%d)",
                        m_familyOverrides[i].symbol, effConf,
                        m_familyOverrides[i].minConfluence, m_config.minConfluence);
         }
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Add a symbol to monitor for spikes                               |
   //+------------------------------------------------------------------+
   bool AddSymbol(const string symbol)
   {
      // Check for duplicate
      if(FindSymbolIndex(symbol) >= 0)
      {
         PrintFormat("[SPIKE-HUNT-ENGINE] Symbol %s already registered", symbol);
         return false;
      }

      // Create ATR indicator handle
      int atrHandle = iATR(symbol, PERIOD_M1, m_config.atrPeriod);
      if(atrHandle == INVALID_HANDLE)
      {
         PrintFormat("[SPIKE-HUNT-ENGINE] Failed to create ATR handle for %s", symbol);
         return false;
      }

      // ATR SMA is computed manually from ATR buffer — no separate handle needed

      // Resize arrays
      int newSize = m_symbolCount + 1;

      // Resize symbol states — construct temp struct to handle string members
      SSpikeSymbolState tempStates[];
      ArrayResize(tempStates, newSize);
      for(int i = 0; i < m_symbolCount; i++)
         tempStates[i] = m_symbolStates[i];
      ArrayResize(m_symbolStates, newSize);
      for(int i = 0; i < m_symbolCount; i++)
         m_symbolStates[i] = tempStates[i];

      // Resize handle arrays
      ArrayResize(m_atrHandles, newSize);

      // Initialize new slot
      InitializeSymbolState(m_symbolCount, symbol);
      m_atrHandles[m_symbolCount]    = atrHandle;
      m_symbolCount++;

      PrintFormat("[SPIKE-HUNT-ENGINE] Symbol added: %s (index=%d atrHandle=%d)",
                  symbol, m_symbolCount - 1, atrHandle);

      // Log effective confluence config for this symbol
      int effConf = GetEffectiveMinConfluence(m_symbolCount - 1);
      PrintFormat("[SPIKE-HUNTER-CONFIG] %s | effectiveMinConfluence=%d/3",
                  symbol, effConf);
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
      }
      m_symbolCount = 0;

      PrintFormat("[SPIKE-HUNT-ENGINE] Deinitialized | detections=%d | trades=%d | skipped=%d | alerts=%d",
                  m_totalDetections, m_totalTradesOpened, m_totalTradesSkipped, m_pushAlertCount);
   }

   //+------------------------------------------------------------------+
   //| Process a tick for a given symbol — call every tick               |
   //+------------------------------------------------------------------+
   void ProcessTick(const string symbol, double bid, double ask)
   {
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
         return;

      if(!m_symbolStates[idx].isActive)
         return;

      // Update all three detection layers
      UpdateTickVelocity(idx);
      UpdateDirectionAccumulation(idx, bid);
      UpdateATRCompression(idx);

      // Count confluence
      m_symbolStates[idx].confluenceCount = CountConfluence(idx);

      // Check if spike is confirmed
      if(m_symbolStates[idx].confluenceCount < GetEffectiveMinConfluence(idx))
      {
         // Diagnostic: log near-miss confluence once per minute per symbol
         if(m_symbolStates[idx].confluenceCount > 0)
         {
            datetime now = TimeCurrent();
            if(now - m_symbolStates[idx].lastDiagTime >= 60)
            {
               m_symbolStates[idx].lastDiagTime = now;
               PrintFormat("[SPIKE-HUNTER-DIAG] %s | vel=%s dir=%s comp=%s conf=%d/%d",
                           symbol,
                           m_symbolStates[idx].velocityTriggered ? "ON" : "off",
                           m_symbolStates[idx].directionTriggered ? "ON" : "off",
                           m_symbolStates[idx].compressionTriggered ? "ON" : "off",
                           m_symbolStates[idx].confluenceCount, GetEffectiveMinConfluence(idx));
            }
         }
         return;
      }

      // Spike detected — record detection time for long-term cooldown
      m_symbolStates[idx].lastSpikeDetectionTime = TimeCurrent();
      m_symbolStates[idx].inSpikeCooldown = true;
      m_totalDetections++;

      // Determine direction
      int direction = DetermineSpikeDirection(idx);
      if(direction == 0)
      {
         PrintFormat("[SPIKE-HUNT-DETECT] %s confluence=%d/3 but no direction determined — skipping",
                     symbol, m_symbolStates[idx].confluenceCount);
         m_totalTradesSkipped++;
         return;
      }

      string dirStr = (direction == 1) ? "BUY" : "SELL";
      PrintFormat("[SPIKE-HUNT-DETECT] %s confluence=%d/3 direction=%s vel=%s dir=%s comp=%s",
                  symbol,
                  m_symbolStates[idx].confluenceCount,
                  dirStr,
                  m_symbolStates[idx].velocityTriggered ? "Y" : "N",
                  m_symbolStates[idx].directionTriggered ? "Y" : "N",
                  m_symbolStates[idx].compressionTriggered ? "Y" : "N");

      // Send push alert
      string alertMsg = "SPIKE DETECTED: " + symbol + " " + dirStr +
                        " (" + IntegerToString(m_symbolStates[idx].confluenceCount) + "/3 confluence)";
      SendThrottledAlert(alertMsg);

      // Check if we can open a trade
      if(!CanOpenSpikeTrade(idx))
      {
         PrintFormat("[SPIKE-HUNT-SKIP] %s — cooldown or max positions reached", symbol);
         m_totalTradesSkipped++;
         return;
      }

      // Open the spike trade
      OpenSpikeTrade(idx, direction);
   }

   //+------------------------------------------------------------------+
   //| Check if a symbol is in spike cooldown for long-term entries      |
   //| Clears the cooldown flag if expired                               |
   //+------------------------------------------------------------------+
   bool IsSymbolInSpikeCooldown(const string symbol)
   {
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
         return false;

      if(!m_symbolStates[idx].inSpikeCooldown)
         return false;

      // Check if cooldown has expired
      datetime now = TimeCurrent();
      int cooldownSeconds = m_config.spikeCooldownForLongTermMs / 1000;
      if((int)(now - m_symbolStates[idx].lastSpikeDetectionTime) >= cooldownSeconds)
      {
         m_symbolStates[idx].inSpikeCooldown = false;
         return false;
      }

      return true;
   }

   //+------------------------------------------------------------------+
   //| Count active spike positions (positions with SPIKE-HUNT comment)  |
   //+------------------------------------------------------------------+
   int GetActiveSpikePositions() const
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
            if(StringFind(comment, "SPIKE-HUNT") >= 0)
               count++;
         }
      }
      return count;
   }

   //+------------------------------------------------------------------+
   //| Get total spike detections                                        |
   //+------------------------------------------------------------------+
   int GetTotalDetections() const { return m_totalDetections; }

   //+------------------------------------------------------------------+
   //| Get total spike trades opened                                     |
   //+------------------------------------------------------------------+
   int GetTotalTradesOpened() const { return m_totalTradesOpened; }
   int GetTotalTradesSkipped() const { return m_totalTradesSkipped; }

   //+------------------------------------------------------------------+
   //| Get configuration                                                 |
   //+------------------------------------------------------------------+
   const SSpikeHunterConfig GetConfig() const { return m_config; }

   //+------------------------------------------------------------------+
   //| Set family-specific overrides for a symbol (Batch 102)            |
   //+------------------------------------------------------------------+
   void SetFamilyOverrides(const string symbol, double velMult, int minTicks, double atrRatio,
                           double slMult, double tpMult, int magicOff, int cooldown, int minConf)
   {
      // Check if override already exists for this symbol
      int oi = FindFamilyOverrideIndex(symbol);
      if(oi >= 0)
      {
         // Update existing override
         m_familyOverrides[oi].velocityMultiplier  = velMult;
         m_familyOverrides[oi].minConsecutiveTicks = minTicks;
         m_familyOverrides[oi].atrCompressionRatio = atrRatio;
         m_familyOverrides[oi].slAtrMultiplier     = slMult;
         m_familyOverrides[oi].tpAtrMultiplier     = tpMult;
         m_familyOverrides[oi].magicOffset         = magicOff;
         m_familyOverrides[oi].cooldownMs          = cooldown;
         m_familyOverrides[oi].minConfluence       = minConf;
         m_familyOverrides[oi].hasOverrides        = true;
         PrintFormat("[SPIKE-HUNT-FAMILY] Updated overrides for %s: vel=%.1f ticks=%d atrRatio=%.2f sl=%.1f tp=%.1f magic=%d cooldown=%d conf=%d",
                     symbol, velMult, minTicks, atrRatio, slMult, tpMult, magicOff, cooldown, minConf);
         return;
      }

      // Add new override using temp struct pattern for string members
      int newSize = m_familyOverrideCount + 1;
      SSpikeHunterFamilyOverrides tempOverrides[];
      ArrayResize(tempOverrides, newSize);
      for(int i = 0; i < m_familyOverrideCount; i++)
         tempOverrides[i] = m_familyOverrides[i];
      ArrayResize(m_familyOverrides, newSize);
      for(int i = 0; i < m_familyOverrideCount; i++)
         m_familyOverrides[i] = tempOverrides[i];

      m_familyOverrides[m_familyOverrideCount].symbol                = symbol;
      m_familyOverrides[m_familyOverrideCount].velocityMultiplier    = velMult;
      m_familyOverrides[m_familyOverrideCount].minConsecutiveTicks   = minTicks;
      m_familyOverrides[m_familyOverrideCount].atrCompressionRatio   = atrRatio;
      m_familyOverrides[m_familyOverrideCount].slAtrMultiplier       = slMult;
      m_familyOverrides[m_familyOverrideCount].tpAtrMultiplier       = tpMult;
      m_familyOverrides[m_familyOverrideCount].magicOffset           = magicOff;
      m_familyOverrides[m_familyOverrideCount].cooldownMs            = cooldown;
      m_familyOverrides[m_familyOverrideCount].minConfluence         = minConf;
      m_familyOverrides[m_familyOverrideCount].hasOverrides          = true;
      m_familyOverrideCount++;

      PrintFormat("[SPIKE-HUNT-FAMILY] Set overrides for %s: vel=%.1f ticks=%d atrRatio=%.2f sl=%.1f tp=%.1f magic=%d cooldown=%d conf=%d",
                  symbol, velMult, minTicks, atrRatio, slMult, tpMult, magicOff, cooldown, minConf);
   }

   //+------------------------------------------------------------------+
   //| Print diagnostics                                                 |
   //+------------------------------------------------------------------+
   void PrintDiagnostics()
   {
      PrintFormat("[SPIKE-HUNT-DIAG] symbols=%d | detections=%d | trades=%d | skipped=%d | alerts=%d | activePos=%d",
                  m_symbolCount,
                  m_totalDetections,
                  m_totalTradesOpened,
                  m_totalTradesSkipped,
                  m_pushAlertCount,
                  GetActiveSpikePositions());

      for(int i = 0; i < m_symbolCount; i++)
      {
         PrintFormat("[SPIKE-HUNT-DIAG] %s | vel=%s dir=%s comp=%s confluence=%d dirSign=%d atr=%.5f atrSMA=%.5f cooldown=%s",
                     m_symbolStates[i].symbol,
                     m_symbolStates[i].velocityTriggered ? "Y" : "N",
                     m_symbolStates[i].directionTriggered ? "Y" : "N",
                     m_symbolStates[i].compressionTriggered ? "Y" : "N",
                     m_symbolStates[i].confluenceCount,
                     m_symbolStates[i].directionSign,
                     m_symbolStates[i].currentATR,
                     m_symbolStates[i].atrSMA,
                     m_symbolStates[i].inSpikeCooldown ? "Y" : "N");
      }
   }
};

#endif // CORE_SCALP_SPIKE_HUNTER_ENGINE_MQH
