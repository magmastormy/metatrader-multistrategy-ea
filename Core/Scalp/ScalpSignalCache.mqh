//+------------------------------------------------------------------+
//| ScalpSignalCache.mqh                                             |
//| Tick-level cached indicator architecture for zero-computation    |
//| fast-path signal evaluation in the scalp pipeline                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_SCALP_SIGNAL_CACHE_MQH
#define CORE_SCALP_SCALP_SIGNAL_CACHE_MQH

#include "..\..\IndicatorManager.mqh"

#define SCALP_CACHE_MAX_SYMBOLS 20

//+------------------------------------------------------------------+
//| Scalp indicator cache struct — one per symbol                     |
//+------------------------------------------------------------------+
struct SScalpIndicatorCache
{
   string            symbol;
   ENUM_TIMEFRAMES   timeframe;

   // Cached indicator values (updated on new bar)
   double            emaFast;          // EMA fast value
   double            emaFastPrev;      // Previous bar EMA fast
   double            emaSlow;          // EMA slow value
   double            emaSlowPrev;      // Previous bar EMA slow
   double            atrValue;         // Current ATR
   double            atrPrev;          // ATR 5 bars ago (for direction)
   double            rsiValue;         // Current RSI
   double            bbUpper;          // Bollinger Band upper
   double            bbLower;          // Bollinger Band lower
   double            bbMiddle;         // Bollinger Band middle
   double            adxValue;         // Current ADX
   double            volumeAvg;        // Average volume (20-bar)
   double            volumeCurrent;    // Current bar volume

   // Tick-level values (updated every tick, zero computation)
   double            bidPrice;
   double            askPrice;
   double            spreadPoints;

   // State tracking
   datetime          lastBarTime;      // For new-bar detection
   bool              isValid;          // Whether cache is populated
   bool              scalpSetupActive; // Pre-qualified for scalping
   int               setupType;        // Current setup type (0=none, 1=momentum, 2=spread, 3=breakout)

   // Handle references (obtained from CIndicatorManager, NOT created here)
   int               emaFastHandle;
   int               emaSlowHandle;
   int               atrHandle;
   int               rsiHandle;
   int               bbHandle;
   int               adxHandle;
   int               volumeHandle;

   SScalpIndicatorCache() :
      symbol(""),
      timeframe(PERIOD_M1),
      emaFast(0.0), emaFastPrev(0.0),
      emaSlow(0.0), emaSlowPrev(0.0),
      atrValue(0.0), atrPrev(0.0),
      rsiValue(0.0),
      bbUpper(0.0), bbLower(0.0), bbMiddle(0.0),
      adxValue(0.0),
      volumeAvg(0.0), volumeCurrent(0.0),
      bidPrice(0.0), askPrice(0.0), spreadPoints(0.0),
      lastBarTime(0),
      isValid(false),
      scalpSetupActive(false),
      setupType(0),
      emaFastHandle(INVALID_HANDLE),
      emaSlowHandle(INVALID_HANDLE),
      atrHandle(INVALID_HANDLE),
      rsiHandle(INVALID_HANDLE),
      bbHandle(INVALID_HANDLE),
      adxHandle(INVALID_HANDLE),
      volumeHandle(INVALID_HANDLE)
   {
   }
};

//+------------------------------------------------------------------+
//| CScalpSignalCache — Dedicated tick-level indicator cache          |
//| UpdateOnNewBar()  = only place CopyBuffer is called               |
//| UpdateTickValues() = zero computation, only SymbolInfoDouble      |
//+------------------------------------------------------------------+
class CScalpSignalCache
{
private:
   SScalpIndicatorCache  m_cache[SCALP_CACHE_MAX_SYMBOLS];
   int                   m_cacheCount;
   int                   m_emaFastPeriod;    // Default 5
   int                   m_emaSlowPeriod;    // Default 13
   int                   m_atrPeriod;        // Default 14
   int                   m_rsiPeriod;        // Default 7
   int                   m_bbPeriod;         // Default 20
   double                m_bbDeviation;      // Default 2.0
   int                   m_adxPeriod;        // Default 14
   int                   m_volumePeriod;     // Default 20

   //+------------------------------------------------------------------+
   //| Find cache index by symbol name                                   |
   //+------------------------------------------------------------------+
   int FindIndex(string symbol) const
   {
      for(int i = 0; i < m_cacheCount; i++)
      {
         if(m_cache[i].symbol == symbol)
            return i;
      }
      return -1;
   }

   //+------------------------------------------------------------------+
   //| Copy 2 values from a handle (current + previous bar)             |
   //+------------------------------------------------------------------+
   bool CopyBuffer2(int handle, double &val0, double &val1) const
   {
      if(handle == INVALID_HANDLE)
         return false;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(handle, 0, 0, 2, buf) < 2)
         return false;
      val0 = buf[0];
      val1 = buf[1];
      return true;
   }

   //+------------------------------------------------------------------+
   //| Copy 1 value from a handle (current bar only)                    |
   //+------------------------------------------------------------------+
   bool CopyBuffer1(int handle, double &val0) const
   {
      if(handle == INVALID_HANDLE)
         return false;
      double buf[];
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(handle, 0, 0, 1, buf) < 1)
         return false;
      val0 = buf[0];
      return true;
   }

   //+------------------------------------------------------------------+
   //| Copy N values from a handle starting at a shift                  |
   //+------------------------------------------------------------------+
   bool CopyBufferN(int handle, int shift, int count, double &buf[]) const
   {
      if(handle == INVALID_HANDLE)
         return false;
      ArraySetAsSeries(buf, true);
      if(CopyBuffer(handle, 0, shift, count, buf) < count)
         return false;
      return true;
   }

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CScalpSignalCache() :
      m_cacheCount(0),
      m_emaFastPeriod(5),
      m_emaSlowPeriod(13),
      m_atrPeriod(14),
      m_rsiPeriod(7),
      m_bbPeriod(20),
      m_bbDeviation(2.0),
      m_adxPeriod(14),
      m_volumePeriod(20)
   {
   }

   //+------------------------------------------------------------------+
   //| Destructor                                                        |
   //+------------------------------------------------------------------+
   ~CScalpSignalCache()
   {
      Cleanup();
   }

   //+------------------------------------------------------------------+
   //| Initialize cache for a set of symbols                             |
   //| Obtains indicator handles from CIndicatorManager::Instance()      |
   //+------------------------------------------------------------------+
   bool Initialize(const string &symbols[], int symbolCount, ENUM_TIMEFRAMES timeframe)
   {
      if(symbolCount <= 0 || symbolCount > SCALP_CACHE_MAX_SYMBOLS)
      {
         PrintFormat("[SCALP-CACHE] ERROR: Invalid symbolCount=%d (max=%d)",
                     symbolCount, SCALP_CACHE_MAX_SYMBOLS);
         return false;
      }

      CIndicatorManager* indMgr = CIndicatorManager::Instance();
      if(indMgr == NULL)
      {
         Print("[SCALP-CACHE] ERROR: CIndicatorManager::Instance() returned NULL");
         return false;
      }

      // Clean any previous state
      Cleanup();

      for(int i = 0; i < symbolCount; i++)
      {
         string sym = symbols[i];
         if(sym == "")
            continue;

         SScalpIndicatorCache &entry = m_cache[m_cacheCount];
         entry.symbol    = sym;
         entry.timeframe = timeframe;

         // Obtain handles from CIndicatorManager — never call iMA/iATR/iRSI directly
         entry.emaFastHandle = indMgr.GetMAHandle(sym, timeframe, m_emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
         entry.emaSlowHandle = indMgr.GetMAHandle(sym, timeframe, m_emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
         entry.atrHandle     = indMgr.GetATRHandle(sym, timeframe, m_atrPeriod);
         entry.rsiHandle     = indMgr.GetRSIHandle(sym, timeframe, m_rsiPeriod, PRICE_CLOSE);
         entry.bbHandle      = indMgr.GetBandsHandle(sym, timeframe, m_bbPeriod, 0, m_bbDeviation, PRICE_CLOSE);
         entry.adxHandle     = indMgr.GetADXHandle(sym, timeframe, m_adxPeriod);
         entry.volumeHandle  = indMgr.GetVolumesHandle(sym, timeframe, VOLUME_TICK);

         // Validate critical handles — ATR and EMA are required for scalp
         if(entry.emaFastHandle == INVALID_HANDLE || entry.emaSlowHandle == INVALID_HANDLE ||
            entry.atrHandle == INVALID_HANDLE)
         {
            PrintFormat("[SCALP-CACHE] ERROR: Critical handle missing for %s | emaFast=%d emaSlow=%d atr=%d",
                        sym, entry.emaFastHandle, entry.emaSlowHandle, entry.atrHandle);
            // Skip this symbol — cannot scalp without EMA and ATR
            ZeroMemory(entry);
            entry.symbol = "";
            continue;
         }

         // Warn on non-critical handle failures
         if(entry.rsiHandle == INVALID_HANDLE)
            PrintFormat("[SCALP-CACHE] WARNING: RSI handle missing for %s", sym);
         if(entry.bbHandle == INVALID_HANDLE)
            PrintFormat("[SCALP-CACHE] WARNING: BB handle missing for %s", sym);
         if(entry.adxHandle == INVALID_HANDLE)
            PrintFormat("[SCALP-CACHE] WARNING: ADX handle missing for %s", sym);
         if(entry.volumeHandle == INVALID_HANDLE)
            PrintFormat("[SCALP-CACHE] WARNING: Volume handle missing for %s", sym);

         m_cacheCount++;

         PrintFormat("[SCALP-CACHE] Initialized %s | EMA(%d/%d) ATR(%d) RSI(%d) BB(%d,%.1f) ADX(%d) Vol(%d)",
                     sym,
                     m_emaFastPeriod, m_emaSlowPeriod,
                     m_atrPeriod, m_rsiPeriod,
                     m_bbPeriod, m_bbDeviation,
                     m_adxPeriod, m_volumePeriod);
      }

      if(m_cacheCount == 0)
      {
         Print("[SCALP-CACHE] ERROR: No symbols initialized successfully");
         return false;
      }

      PrintFormat("[SCALP-CACHE] Ready | symbols=%d | tf=%s",
                  m_cacheCount, EnumToString(timeframe));
      return true;
   }

   //+------------------------------------------------------------------+
   //| Update cached indicator values — call on new bar ONLY             |
   //| This is the ONLY place CopyBuffer is called                      |
   //+------------------------------------------------------------------+
   void UpdateOnNewBar()
   {
      for(int i = 0; i < m_cacheCount; i++)
      {
         SScalpIndicatorCache &c = m_cache[i];

         // New-bar detection
         datetime barTime = iTime(c.symbol, c.timeframe, 0);
         if(barTime == 0)
            continue;  // No data yet
         if(barTime == c.lastBarTime)
            continue;  // Same bar — skip

         bool anyFailed = false;

         // EMA fast (2 values: current + previous)
         if(!CopyBuffer2(c.emaFastHandle, c.emaFast, c.emaFastPrev))
         {
            c.emaFast = 0.0;
            c.emaFastPrev = 0.0;
            anyFailed = true;
         }

         // EMA slow (2 values: current + previous)
         if(!CopyBuffer2(c.emaSlowHandle, c.emaSlow, c.emaSlowPrev))
         {
            c.emaSlow = 0.0;
            c.emaSlowPrev = 0.0;
            anyFailed = true;
         }

         // ATR (current + 5 bars ago for direction)
         {
            double atrBuf[];
            if(CopyBufferN(c.atrHandle, 0, 6, atrBuf))
            {
               c.atrValue = atrBuf[0];
               c.atrPrev  = atrBuf[5];
            }
            else
            {
               // Fallback: try just current value
               if(!CopyBuffer1(c.atrHandle, c.atrValue))
               {
                  c.atrValue = 0.0;
                  anyFailed = true;
               }
               c.atrPrev = 0.0;
            }
         }

         // RSI (current only)
         if(!CopyBuffer1(c.rsiHandle, c.rsiValue))
         {
            c.rsiValue = 0.0;
            // Non-critical — don't set anyFailed
         }

         // Bollinger Bands (3 buffers: 0=base/median, 1=upper, 2=lower)
         if(c.bbHandle != INVALID_HANDLE)
         {
            double bbBuf[];
            ArraySetAsSeries(bbBuf, true);
            // Buffer 0 = middle line
            if(CopyBuffer(c.bbHandle, 0, 0, 1, bbBuf) >= 1)
               c.bbMiddle = bbBuf[0];
            else
               c.bbMiddle = 0.0;

            // Buffer 1 = upper band
            if(CopyBuffer(c.bbHandle, 1, 0, 1, bbBuf) >= 1)
               c.bbUpper = bbBuf[0];
            else
               c.bbUpper = 0.0;

            // Buffer 2 = lower band
            if(CopyBuffer(c.bbHandle, 2, 0, 1, bbBuf) >= 1)
               c.bbLower = bbBuf[0];
            else
               c.bbLower = 0.0;
         }
         else
         {
            c.bbUpper  = 0.0;
            c.bbLower  = 0.0;
            c.bbMiddle = 0.0;
         }

         // ADX (current only — buffer 0 = main ADX line)
         if(!CopyBuffer1(c.adxHandle, c.adxValue))
         {
            c.adxValue = 0.0;
            // Non-critical
         }

         // Volume (current + average over m_volumePeriod bars)
         if(c.volumeHandle != INVALID_HANDLE)
         {
            double volBuf[];
            if(CopyBufferN(c.volumeHandle, 0, m_volumePeriod + 1, volBuf))
            {
               c.volumeCurrent = volBuf[0];
               double sum = 0.0;
               for(int v = 1; v <= m_volumePeriod; v++)
                  sum += volBuf[v];
               c.volumeAvg = sum / m_volumePeriod;
            }
            else
            {
               c.volumeCurrent = 0.0;
               c.volumeAvg    = 0.0;
            }
         }
         else
         {
            c.volumeCurrent = 0.0;
            c.volumeAvg    = 0.0;
         }

         // Mark cache as valid if critical values populated
         c.isValid = (c.emaFast > 0.0 && c.emaSlow > 0.0 && c.atrValue > 0.0);
         c.lastBarTime = barTime;

         if(anyFailed && c.isValid)
         {
            PrintFormat("[SCALP-CACHE] WARNING: Partial update for %s — some indicators failed",
                        c.symbol);
         }
      }
   }

   //+------------------------------------------------------------------+
   //| Update tick-level values — call every tick, ZERO computation      |
   //| Only reads SymbolInfoDouble — no CopyBuffer calls                |
   //+------------------------------------------------------------------+
   void UpdateTickValues()
   {
      for(int i = 0; i < m_cacheCount; i++)
      {
         SScalpIndicatorCache &c = m_cache[i];

         c.bidPrice = SymbolInfoDouble(c.symbol, SYMBOL_BID);
         c.askPrice = SymbolInfoDouble(c.symbol, SYMBOL_ASK);

         double point = SymbolInfoDouble(c.symbol, SYMBOL_POINT);
         if(point > 0.0)
            c.spreadPoints = (c.askPrice - c.bidPrice) / point;
         else
            c.spreadPoints = 0.0;
      }
   }

   //+------------------------------------------------------------------+
   //| Get cache for a specific symbol (pointer for fast access)        |
   //+------------------------------------------------------------------+
   SScalpIndicatorCache* GetCache(string symbol)
   {
      int idx = FindIndex(symbol);
      if(idx < 0)
         return NULL;
      return &m_cache[idx];
   }

   //+------------------------------------------------------------------+
   //| Check if a new bar has formed for a symbol                       |
   //+------------------------------------------------------------------+
   bool HasNewBar(string symbol)
   {
      int idx = FindIndex(symbol);
      if(idx < 0)
         return false;

      datetime barTime = iTime(symbol, m_cache[idx].timeframe, 0);
      return (barTime > m_cache[idx].lastBarTime);
   }

   //+------------------------------------------------------------------+
   //| Mark a symbol as pre-qualified for scalping                      |
   //+------------------------------------------------------------------+
   void SetScalpSetup(string symbol, bool active, int setupType)
   {
      int idx = FindIndex(symbol);
      if(idx < 0)
         return;

      m_cache[idx].scalpSetupActive = active;
      m_cache[idx].setupType = setupType;
   }

   //+------------------------------------------------------------------+
   //| Release all handles and reset cache                               |
   //+------------------------------------------------------------------+
   void Cleanup()
   {
      // Note: handles are owned by CIndicatorManager — do NOT call IndicatorRelease here.
      // CIndicatorManager::DestroyInstance() handles cleanup.
      // We only reset our references.
      for(int i = 0; i < m_cacheCount; i++)
      {
         m_cache[i].emaFastHandle  = INVALID_HANDLE;
         m_cache[i].emaSlowHandle  = INVALID_HANDLE;
         m_cache[i].atrHandle      = INVALID_HANDLE;
         m_cache[i].rsiHandle      = INVALID_HANDLE;
         m_cache[i].bbHandle       = INVALID_HANDLE;
         m_cache[i].adxHandle      = INVALID_HANDLE;
         m_cache[i].volumeHandle   = INVALID_HANDLE;

         m_cache[i].symbol         = "";
         m_cache[i].isValid        = false;
         m_cache[i].scalpSetupActive = false;
         m_cache[i].setupType      = 0;
         m_cache[i].lastBarTime    = 0;
      }
      m_cacheCount = 0;
   }

   //+------------------------------------------------------------------+
   //| Get cache count                                                   |
   //+------------------------------------------------------------------+
   int GetCacheCount() const { return m_cacheCount; }

   //+------------------------------------------------------------------+
   //| Set indicator periods (call before Initialize)                   |
   //+------------------------------------------------------------------+
   void SetPeriods(int emaFast, int emaSlow, int atr, int rsi,
                   int bb, double bbDev, int adx, int volume)
   {
      m_emaFastPeriod = emaFast;
      m_emaSlowPeriod = emaSlow;
      m_atrPeriod     = atr;
      m_rsiPeriod     = rsi;
      m_bbPeriod      = bb;
      m_bbDeviation   = bbDev;
      m_adxPeriod     = adx;
      m_volumePeriod  = volume;
   }
};

#endif // CORE_SCALP_SCALP_SIGNAL_CACHE_MQH
