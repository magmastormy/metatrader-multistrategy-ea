// Tick-level cached indicator architecture for zero-computation
// fast-path signal evaluation in the scalp pipeline
#property copyright "Copyright 2026, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef CORE_SCALP_SCALP_SIGNAL_CACHE_MQH
#define CORE_SCALP_SCALP_SIGNAL_CACHE_MQH

#include "..\..\IndicatorManager.mqh"

#define SCALP_CACHE_MAX_SYMBOLS 20

// Scalp indicator cache struct — one per symbol
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
   double            rsiValue;         // Current RSI

   // Tick-level values (updated every tick, zero computation)
   double            spreadPoints;

   datetime          lastBarTime;      // For new-bar detection
   bool              isValid;          // Whether cache is populated

   // Handle references (obtained from CIndicatorManager, NOT created here)
   int               emaFastHandle;
   int               emaSlowHandle;
   int               atrHandle;
   int               rsiHandle;

   SScalpIndicatorCache() :
      symbol(""),
      timeframe(PERIOD_M1),
      emaFast(0.0), emaFastPrev(0.0),
      emaSlow(0.0), emaSlowPrev(0.0),
      atrValue(0.0),
      rsiValue(0.0),
      spreadPoints(0.0),
      lastBarTime(0),
      isValid(false),
      emaFastHandle(INVALID_HANDLE),
      emaSlowHandle(INVALID_HANDLE),
      atrHandle(INVALID_HANDLE),
      rsiHandle(INVALID_HANDLE)
   {
   }
};

// UpdateOnNewBar()  = only place CopyBuffer is called
// UpdateTickValues() = zero computation, only SymbolInfoDouble
class CScalpSignalCache
{
private:
   SScalpIndicatorCache  m_cache[SCALP_CACHE_MAX_SYMBOLS];
   int                   m_cacheCount;
   int                   m_emaFastPeriod;    // Default 5
   int                   m_emaSlowPeriod;    // Default 13
   int                   m_atrPeriod;        // Default 14
   int                   m_rsiPeriod;        // Default 7

// Find cache index by symbol name
   int FindIndex(string symbol) const
   {
      for(int i = 0; i < m_cacheCount; i++)
      {
         if(m_cache[i].symbol == symbol)
            return i;
      }
      return -1;
   }

// Copy 2 values from a handle (current + previous bar)
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

// Copy 1 value from a handle (current bar only)
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


public:
   CScalpSignalCache() :
      m_cacheCount(0),
      m_emaFastPeriod(5),
      m_emaSlowPeriod(13),
      m_atrPeriod(14),
      m_rsiPeriod(7)
   {
   }

   ~CScalpSignalCache()
   {
      Cleanup();
   }

// Obtains indicator handles from CIndicatorManager::Instance()
   bool Initialize(const string &symbols[], int symbolCount, ENUM_TIMEFRAMES timeframe)
   {
      if(symbolCount <= 0 || symbolCount > SCALP_CACHE_MAX_SYMBOLS)
      {
         PrintFormat("[SCALP-CACHE] DEFERRED: symbolCount=%d (max=%d) — will init after symbol registration",
                     symbolCount, SCALP_CACHE_MAX_SYMBOLS);
         return false;
      }

      CIndicatorManager* indMgr = CIndicatorManager::Instance();
      if(indMgr == NULL)
      {
         Print("[SCALP-CACHE] ERROR: CIndicatorManager::Instance() returned NULL");
         return false;
      }

      Cleanup();

      for(int i = 0; i < symbolCount; i++)
      {
         string sym = symbols[i];
         if(sym == "")
            continue;

         m_cache[m_cacheCount].symbol    = sym;
         m_cache[m_cacheCount].timeframe = timeframe;

         // Ensure symbol is registered in Market Watch and has enough bars
         if(!SymbolInfoInteger(sym, SYMBOL_VISIBLE))
            SymbolSelect(sym, true);

         int symBars = iBars(sym, timeframe);
         if(symBars < 50)
         {
            // Non-blocking: if bars still insufficient, skip and retry next init cycle
            PrintFormat("[SCALP-CACHE] SKIP: %s still insufficient bars (%d)", sym, symBars);
            continue;
          }

         // iMA/iATR can transiently fail when symbol data is not yet loaded
         int maxHandleRetries = 3;
         for(int attempt = 0; attempt < maxHandleRetries; attempt++)
         {
            m_cache[m_cacheCount].emaFastHandle = indMgr.GetMAHandle(sym, timeframe, m_emaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
            m_cache[m_cacheCount].emaSlowHandle = indMgr.GetMAHandle(sym, timeframe, m_emaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
            m_cache[m_cacheCount].atrHandle     = indMgr.GetATRHandle(sym, timeframe, m_atrPeriod);

            bool criticalOk = (m_cache[m_cacheCount].emaFastHandle != INVALID_HANDLE &&
                               m_cache[m_cacheCount].emaSlowHandle != INVALID_HANDLE &&
                               m_cache[m_cacheCount].atrHandle != INVALID_HANDLE);
            if(criticalOk)
               break;

            if(attempt < maxHandleRetries - 1)
            {
               PrintFormat("[SCALP-CACHE] RETRY %d/%d: Critical handles incomplete for %s (emaFast=%d emaSlow=%d atr=%d) — retrying next cycle",
                           attempt + 1, maxHandleRetries, sym,
                           m_cache[m_cacheCount].emaFastHandle, m_cache[m_cacheCount].emaSlowHandle, m_cache[m_cacheCount].atrHandle);
            }
         }

         // Validate critical handles — ATR and EMA are required for scalp
         if(m_cache[m_cacheCount].emaFastHandle == INVALID_HANDLE || m_cache[m_cacheCount].emaSlowHandle == INVALID_HANDLE ||
            m_cache[m_cacheCount].atrHandle == INVALID_HANDLE)
         {
            // Do NOT alias emaFastHandle to the slow handle - two identical series make every crossover comparison degenerate; exclude the symbol from the cache instead.
            if(m_cache[m_cacheCount].emaFastHandle == INVALID_HANDLE &&
               m_cache[m_cacheCount].emaSlowHandle != INVALID_HANDLE &&
               m_cache[m_cacheCount].atrHandle != INVALID_HANDLE)
            {
               PrintFormat("[SCALP-CACHE] ERROR: emaFast unavailable for %s after retries - symbol excluded | emaFast=%d emaSlow=%d atr=%d",
                           sym, m_cache[m_cacheCount].emaFastHandle, m_cache[m_cacheCount].emaSlowHandle, m_cache[m_cacheCount].atrHandle);
               // Reset fields individually (ZeroMemory corrupts string reference counting)
               m_cache[m_cacheCount].symbol = "";
               m_cache[m_cacheCount].emaFastHandle = INVALID_HANDLE;
               m_cache[m_cacheCount].emaSlowHandle = INVALID_HANDLE;
               m_cache[m_cacheCount].atrHandle = INVALID_HANDLE;
               m_cache[m_cacheCount].rsiHandle = INVALID_HANDLE;
               m_cache[m_cacheCount].isValid = false;
               continue;
            }
            else if(m_cache[m_cacheCount].emaFastHandle == INVALID_HANDLE &&
                    m_cache[m_cacheCount].emaSlowHandle != INVALID_HANDLE &&
                    m_cache[m_cacheCount].atrHandle == INVALID_HANDLE)
            {
               PrintFormat("[SCALP-CACHE] ERROR: Both emaFast and atr missing for %s after retries | emaFast=%d emaSlow=%d atr=%d",
                           sym, m_cache[m_cacheCount].emaFastHandle, m_cache[m_cacheCount].emaSlowHandle, m_cache[m_cacheCount].atrHandle);
               // Reset fields individually (ZeroMemory corrupts string reference counting)
               m_cache[m_cacheCount].symbol = "";
               m_cache[m_cacheCount].emaFastHandle = INVALID_HANDLE;
               m_cache[m_cacheCount].emaSlowHandle = INVALID_HANDLE;
               m_cache[m_cacheCount].atrHandle = INVALID_HANDLE;
               m_cache[m_cacheCount].rsiHandle = INVALID_HANDLE;
               m_cache[m_cacheCount].isValid = false;
               continue;
            }
            else if(m_cache[m_cacheCount].emaSlowHandle == INVALID_HANDLE)
            {
               PrintFormat("[SCALP-CACHE] ERROR: emaSlow missing for %s after retries | emaFast=%d emaSlow=%d atr=%d",
                           sym, m_cache[m_cacheCount].emaFastHandle, m_cache[m_cacheCount].emaSlowHandle, m_cache[m_cacheCount].atrHandle);
               // Reset fields individually (ZeroMemory corrupts string reference counting)
               m_cache[m_cacheCount].symbol = "";
               m_cache[m_cacheCount].emaFastHandle = INVALID_HANDLE;
               m_cache[m_cacheCount].emaSlowHandle = INVALID_HANDLE;
               m_cache[m_cacheCount].atrHandle = INVALID_HANDLE;
               m_cache[m_cacheCount].rsiHandle = INVALID_HANDLE;
               m_cache[m_cacheCount].isValid = false;
               continue;
            }
         }

         // Non-critical handle - obtained after the critical handles are confirmed
         m_cache[m_cacheCount].rsiHandle = indMgr.GetRSIHandle(sym, timeframe, m_rsiPeriod, PRICE_CLOSE);

         if(m_cache[m_cacheCount].rsiHandle == INVALID_HANDLE)
            PrintFormat("[SCALP-CACHE] WARNING: RSI handle missing for %s", sym);

         m_cacheCount++;

         PrintFormat("[SCALP-CACHE] Initialized %s | EMA(%d/%d) ATR(%d) RSI(%d)",
                     sym,
                     m_emaFastPeriod, m_emaSlowPeriod,
                     m_atrPeriod, m_rsiPeriod);
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

// Update cached indicator values — call on new bar ONLY
// This is the ONLY place CopyBuffer is called
   void UpdateOnNewBar()
   {
      for(int i = 0; i < m_cacheCount; i++)
      {
         datetime barTime = iTime(m_cache[i].symbol, m_cache[i].timeframe, 0);
         if(barTime == 0)
            continue;  // No data yet
         if(barTime == m_cache[i].lastBarTime)
            continue;  // Same bar — skip

         bool anyFailed = false;

         if(!CopyBuffer2(m_cache[i].emaFastHandle, m_cache[i].emaFast, m_cache[i].emaFastPrev))
         {
            m_cache[i].emaFast = 0.0;
            m_cache[i].emaFastPrev = 0.0;
            anyFailed = true;
         }

         if(!CopyBuffer2(m_cache[i].emaSlowHandle, m_cache[i].emaSlow, m_cache[i].emaSlowPrev))
         {
            m_cache[i].emaSlow = 0.0;
            m_cache[i].emaSlowPrev = 0.0;
            anyFailed = true;
         }

         if(!CopyBuffer1(m_cache[i].atrHandle, m_cache[i].atrValue))
         {
            m_cache[i].atrValue = 0.0;
            anyFailed = true;
         }

         if(!CopyBuffer1(m_cache[i].rsiHandle, m_cache[i].rsiValue))
         {
            m_cache[i].rsiValue = 0.0;
            // Not in isValid on purpose: EvaluateFromCache refuses a signal at rsiValue <= 0.0, so a missing
            // RSI costs a trade rather than reading 0.0 as "not overbought".
         }

         // Mark cache as valid if critical values populated
         m_cache[i].isValid = (m_cache[i].emaFast > 0.0 && m_cache[i].emaSlow > 0.0 && m_cache[i].atrValue > 0.0);
         m_cache[i].lastBarTime = barTime;

         if(anyFailed && m_cache[i].isValid)
         {
            PrintFormat("[SCALP-CACHE] WARNING: Partial update for %s — some indicators failed",
                        m_cache[i].symbol);
         }
      }
   }

// Update tick-level values — call every tick, ZERO computation
// Only reads SymbolInfoDouble — no CopyBuffer calls
   void UpdateTickValues()
   {
      for(int i = 0; i < m_cacheCount; i++)
      {
         double bid = SymbolInfoDouble(m_cache[i].symbol, SYMBOL_BID);
         double ask = SymbolInfoDouble(m_cache[i].symbol, SYMBOL_ASK);
         double point = SymbolInfoDouble(m_cache[i].symbol, SYMBOL_POINT);
         m_cache[i].spreadPoints = (point > 0.0) ? (ask - bid) / point : 0.0;
      }
   }

   bool GetCache(string symbol, SScalpIndicatorCache &outCache)
   {
      int idx = FindIndex(symbol);
      if(idx < 0)
         return false;
      outCache = m_cache[idx];
      return true;
   }

   void Cleanup()
   {
      // Note: handles are owned by CIndicatorManager — do NOT call IndicatorRelease here.
      // CIndicatorManager::DestroyInstance() handles cleanup.
      for(int i = 0; i < m_cacheCount; i++)
      {
         m_cache[i].emaFastHandle  = INVALID_HANDLE;
         m_cache[i].emaSlowHandle  = INVALID_HANDLE;
         m_cache[i].atrHandle      = INVALID_HANDLE;
         m_cache[i].rsiHandle      = INVALID_HANDLE;

         m_cache[i].symbol         = "";
         m_cache[i].isValid        = false;
         m_cache[i].lastBarTime    = 0;
      }
      m_cacheCount = 0;
   }


};

#endif // CORE_SCALP_SCALP_SIGNAL_CACHE_MQH
