// Owns the per-symbol spike registry and the three detection layers (tick-rate EMA, consecutive-tick direction, ATR compression)
// Keeps its own by-value copy of SSpikeHunterConfig; config is write-once (no setter existed), so the copy can never diverge.
#property strict

#ifndef CORE_SCALP_SPIKE_HUNTER_DETECTOR_MQH
#define CORE_SCALP_SPIKE_HUNTER_DETECTOR_MQH

#include "SpikeHunterTypes.mqh"
#include "SpikeHunterOverrides.mqh"

class CSpikeHunterDetector
{
private:
   SSpikeHunterConfig      m_config;
   SSpikeSymbolState       m_symbolStates[];
   int                     m_symbolCount;

   int                     m_atrHandles[];         // ATR indicator handles per symbol
   // ATR SMA is computed manually from ATR buffer (MQL5 cannot apply MA to indicator output)

   // Family-specific overrides (Batch 102) â€?held BY VALUE
   CSpikeHunterOverrides   m_overrides;

public:
   CSpikeHunterDetector() : m_symbolCount(0) {}

   //--- Config injection (mirrors CSpikeHunterEngine::Init assignment)
   void SetConfig(const SSpikeHunterConfig &config) { m_config = config; }

   //--- Was the bare `m_symbolCount = 0;` line inside Init()
   void ResetSymbolCount() { m_symbolCount = 0; }

   int  GetSymbolCount() const { return m_symbolCount; }
   int  GetOverrideCount() const { return m_overrides.Count(); }

   int FindSymbolIndex(const string symbol) const
   {
      for(int i = 0; i < m_symbolCount; i++)
      {
         if(m_symbolStates[i].symbol == symbol)
            return i;
      }
      return -1;
   }

   int FindFamilyOverrideIndex(const string symbol) const
   {
      return m_overrides.FindFamilyOverrideIndex(symbol);
   }

   void SetFamilyOverrides(const string symbol, double velMult, int minTicks, double atrRatio,
                           double slMult, double tpMult, int magicOff, int cooldown, int minConf)
   {
      m_overrides.SetFamilyOverrides(symbol, velMult, minTicks, atrRatio, slMult, tpMult,
                                     magicOff, cooldown, minConf);
   }

   void LogOverridesSummary() const { m_overrides.LogConfigSummary(m_config.minConfluence); }

// Effective (override-aware) parameter resolution (Batch 102)
   double GetEffectiveVelocityMultiplier(int idx) const
   {
      return m_overrides.GetEffectiveVelocityMultiplier(m_symbolStates[idx].symbol, m_config.velocityMultiplier);
   }

   int GetEffectiveMinConsecutiveTicks(int idx) const
   {
      return m_overrides.GetEffectiveMinConsecutiveTicks(m_symbolStates[idx].symbol, m_config.minConsecutiveTicks);
   }

   double GetEffectiveATRCompressionRatio(int idx) const
   {
      return m_overrides.GetEffectiveATRCompressionRatio(m_symbolStates[idx].symbol, m_config.atrCompressionRatio);
   }

   double GetEffectiveSLAtrMultiplier(int idx) const
   {
      return m_overrides.GetEffectiveSLAtrMultiplier(m_symbolStates[idx].symbol, m_config.slAtrMultiplier);
   }

   double GetEffectiveTPAtrMultiplier(int idx) const
   {
      return m_overrides.GetEffectiveTPAtrMultiplier(m_symbolStates[idx].symbol, m_config.tpAtrMultiplier);
   }

   int GetEffectiveMagicOffset(int idx) const
   {
      return m_overrides.GetEffectiveMagicOffset(m_symbolStates[idx].symbol, m_config.magicOffset);
   }

   int GetEffectiveCooldownMs(int idx) const
   {
      return m_overrides.GetEffectiveCooldownMs(m_symbolStates[idx].symbol, m_config.cooldownMs);
   }

   int GetEffectiveMinConfluence(int idx) const
   {
      return m_overrides.GetEffectiveMinConfluence(m_symbolStates[idx].symbol, m_config.minConfluence);
   }

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

   bool AddSymbol(const string symbol)
   {
      if(FindSymbolIndex(symbol) >= 0)
      {
         PrintFormat("[SPIKE-HUNT-ENGINE] Symbol %s already registered", symbol);
         return false;
      }

      int atrHandle = iATR(symbol, PERIOD_M1, m_config.atrPeriod);
      if(atrHandle == INVALID_HANDLE)
      {
         PrintFormat("[SPIKE-HUNT-ENGINE] Failed to create ATR handle for %s", symbol);
         return false;
      }

      // ATR SMA is computed manually from ATR buffer â€?no separate handle needed

      int newSize = m_symbolCount + 1;

      // Resize symbol states â€?construct temp struct to handle string members
      SSpikeSymbolState tempStates[];
      ArrayResize(tempStates, newSize);
      for(int i = 0; i < m_symbolCount; i++)
         tempStates[i] = m_symbolStates[i];
      ArrayResize(m_symbolStates, newSize);
      for(int i = 0; i < m_symbolCount; i++)
         m_symbolStates[i] = tempStates[i];

      ArrayResize(m_atrHandles, newSize);

      InitializeSymbolState(m_symbolCount, symbol);
      m_atrHandles[m_symbolCount]    = atrHandle;
      m_symbolCount++;

      PrintFormat("[SPIKE-HUNT-ENGINE] Symbol added: %s (index=%d atrHandle=%d)",
                  symbol, m_symbolCount - 1, atrHandle);

      int effConf = GetEffectiveMinConfluence(m_symbolCount - 1);
      PrintFormat("[SPIKE-HUNTER-CONFIG] %s | effectiveMinConfluence=%d/3",
                  symbol, effConf);
      return true;
   }

// (was the loop body of CSpikeHunterEngine::Deinit)
   void ReleaseHandles()
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
   }

// Count ticks per 1-second window, maintain EMA baseline,
// trigger when currentRate > baseline * velocityMultiplier
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

      m_symbolStates[idx].tickWindowStart = now;
      m_symbolStates[idx].tickWindowCount = 0;
   }

// Track consecutive ticks in one direction within a time window
   void UpdateDirectionAccumulation(int idx, double bid)
   {
      datetime now = TimeCurrent();

      // Check if window expired (consecutiveTickWindowMs)
      // use long to prevent integer overflow on stale windows
      long windowElapsedMs = (long)((now - m_symbolStates[idx].directionWindowStart) * 1000);
      if(windowElapsedMs > m_config.consecutiveTickWindowMs)
      {
         // Window expired â€?reset counters
         m_symbolStates[idx].consecutiveUpTicks   = 0;
         m_symbolStates[idx].consecutiveDownTicks = 0;
         m_symbolStates[idx].directionWindowStart = now;
         m_symbolStates[idx].directionTriggered   = false;
         m_symbolStates[idx].directionSign        = 0;
      }

      if(m_symbolStates[idx].lastBid <= 0.0)
      {
         m_symbolStates[idx].lastBid = bid;
         return;
      }

      if(bid > m_symbolStates[idx].lastBid)
      {
         m_symbolStates[idx].consecutiveUpTicks++;
         m_symbolStates[idx].consecutiveDownTicks = 0;
      }
      else if(bid < m_symbolStates[idx].lastBid)
      {
         m_symbolStates[idx].consecutiveDownTicks++;
         m_symbolStates[idx].consecutiveUpTicks = 0;
      }
      else
      {
         // No change â€?reset both
         m_symbolStates[idx].consecutiveUpTicks   = 0;
         m_symbolStates[idx].consecutiveDownTicks = 0;
      }

      m_symbolStates[idx].lastBid = bid;

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

// Trigger when ATR(14) <= SMA(ATR,50) * atrCompressionRatio
   void UpdateATRCompression(int idx)
   {
      string symbol = m_symbolStates[idx].symbol;

      if(m_atrHandles[idx] == INVALID_HANDLE)
         return;

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

// Count how many detection layers are triggered
   int CountConfluence(int idx) const
   {
      int count = 0;
      if(m_symbolStates[idx].velocityTriggered)    count++;
      if(m_symbolStates[idx].directionTriggered)   count++;
      if(m_symbolStates[idx].compressionTriggered) count++;
      return count;
   }

// Per-symbol state accessors used by the engine coordinator
   bool     IsSymbolActive(int idx) const          { return m_symbolStates[idx].isActive; }
   string   GetSymbolName(int idx) const           { return m_symbolStates[idx].symbol; }
   int      GetConfluenceCount(int idx) const      { return m_symbolStates[idx].confluenceCount; }
   void     SetConfluenceCount(int idx, int count) { m_symbolStates[idx].confluenceCount = count; }
   int      GetDirectionSign(int idx) const        { return m_symbolStates[idx].directionSign; }
   double   GetCurrentATR(int idx) const           { return m_symbolStates[idx].currentATR; }
   datetime GetLastSpikeTradeTime(int idx) const   { return m_symbolStates[idx].lastSpikeTradeTime; }
   bool     IsVelocityTriggered(int idx) const     { return m_symbolStates[idx].velocityTriggered; }
   bool     IsDirectionTriggered(int idx) const    { return m_symbolStates[idx].directionTriggered; }
   bool     IsCompressionTriggered(int idx) const  { return m_symbolStates[idx].compressionTriggered; }

// Spike detected â€?record detection time for long-term cooldown
   void MarkSpikeDetected(int idx)
   {
      m_symbolStates[idx].lastSpikeDetectionTime = TimeCurrent();
      m_symbolStates[idx].inSpikeCooldown = true;
   }

// Spike trade filled â€?record trade time and arm the cooldown
   void MarkSpikeTradeOpened(int idx)
   {
      m_symbolStates[idx].lastSpikeTradeTime = TimeCurrent();
      m_symbolStates[idx].lastSpikeDetectionTime = TimeCurrent();
      m_symbolStates[idx].inSpikeCooldown = true;
   }

// Check if a symbol is in spike cooldown for long-term entries
// Clears the cooldown flag if expired
   bool IsSymbolInSpikeCooldown(const string symbol, int spikeCooldownForLongTermMs)
   {
      int idx = FindSymbolIndex(symbol);
      if(idx < 0)
         return false;

      if(!m_symbolStates[idx].inSpikeCooldown)
         return false;

      datetime now = TimeCurrent();
      int cooldownSeconds = spikeCooldownForLongTermMs / 1000;
      if((int)(now - m_symbolStates[idx].lastSpikeDetectionTime) >= cooldownSeconds)
      {
         m_symbolStates[idx].inSpikeCooldown = false;
         return false;
      }

      return true;
   }

// Diagnostic: log near-miss confluence once per minute per symbol
   void LogNearMissDiagnostic(int idx)
   {
      if(m_symbolStates[idx].confluenceCount > 0)
      {
         datetime now = TimeCurrent();
         if(now - m_symbolStates[idx].lastDiagTime >= 60)
         {
            m_symbolStates[idx].lastDiagTime = now;
            PrintFormat("[SPIKE-HUNTER-DIAG] %s | vel=%s dir=%s comp=%s conf=%d/%d",
                        m_symbolStates[idx].symbol,
                        m_symbolStates[idx].velocityTriggered ? "ON" : "off",
                        m_symbolStates[idx].directionTriggered ? "ON" : "off",
                        m_symbolStates[idx].compressionTriggered ? "ON" : "off",
                        m_symbolStates[idx].confluenceCount, GetEffectiveMinConfluence(idx));
         }
      }
   }

// Confirmed spike log line (was inline in ProcessTick)
   void LogSpikeDetected(int idx, const string dirStr) const
   {
      PrintFormat("[SPIKE-HUNT-DETECT] %s confluence=%d/3 direction=%s vel=%s dir=%s comp=%s",
                  m_symbolStates[idx].symbol,
                  m_symbolStates[idx].confluenceCount,
                  dirStr,
                  m_symbolStates[idx].velocityTriggered ? "Y" : "N",
                  m_symbolStates[idx].directionTriggered ? "Y" : "N",
                  m_symbolStates[idx].compressionTriggered ? "Y" : "N");
   }

// Per-symbol diagnostics (was the loop inside PrintDiagnostics)
   void PrintSymbolDiagnostics() const
   {
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

#endif // CORE_SCALP_SPIKE_HUNTER_DETECTOR_MQH

