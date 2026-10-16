// Owns the per-symbol cached M1 indicator state for the scalp fast path.
// The engine holds one of these by value; one cache slot is shared by
// every symbol, so a refresh only commits when both reads succeed.
// The EMAs are not cached: GetEMACrossover needs two bars, which a one-slot cache cannot give it.
#property strict

#ifndef CORE_SCALP_FAST_SCALP_INDICATORS_MQH
#define CORE_SCALP_FAST_SCALP_INDICATORS_MQH

#include "../Utils/Enums.mqh"
#include "../../IndicatorManager.mqh"
#include "FastScalpTypes.mqh"

class CFastScalpIndicators
{
private:
   string                    m_cachedSymbol;
   datetime                  m_cachedBarTime;
   double                    m_cachedATR;
   double                    m_cachedRSI;

public:
   CFastScalpIndicators() :
      m_cachedSymbol(""),
      m_cachedBarTime(0),
      m_cachedATR(0.0),
      m_cachedRSI(0.0)
   {
   }

// Overwrite the cache from an external source (signal cache path)
   void SetCachedValues(const string symbol, datetime barTime, double atr, double rsi)
   {
      m_cachedATR     = atr;
      m_cachedRSI     = rsi;
      m_cachedSymbol  = symbol;
      m_cachedBarTime = barTime;
   }

   bool RefreshIndicators(const string symbol, const SScalpConfig &config)
   {
      // Only refresh on new bar for M1
      datetime barTime = iTime(symbol, PERIOD_M1, 0);
      if(barTime == m_cachedBarTime && symbol == m_cachedSymbol && m_cachedATR > 0.0)
         return true;

      CIndicatorManager* indMgr = CIndicatorManager::Instance();
      if(indMgr == NULL)
         return false;

      double atrBuf[];
      double rsiBuf[];

      // Reads land in locals: the cache is one slot shared by every symbol, so writing a member before a
      // later read fails would leave this symbol's numbers tagged as the previous symbol - and the
      // new-bar test above would then hand them back to that symbol for the rest of its bar.
      int atrHandle = indMgr.GetATRHandle(symbol, PERIOD_M1, 14);
      if(atrHandle == INVALID_HANDLE)
         return false;
      ArraySetAsSeries(atrBuf, true);
      if(CopyBuffer(atrHandle, 0, 0, 1, atrBuf) <= 0)
         return false;

      int rsiHandle = indMgr.GetRSIHandle(symbol, PERIOD_M1, config.rsiPeriod, PRICE_CLOSE);
      if(rsiHandle == INVALID_HANDLE)
         return false;
      ArraySetAsSeries(rsiBuf, true);
      if(CopyBuffer(rsiHandle, 0, 0, 1, rsiBuf) <= 0)
         return false;

      m_cachedATR = atrBuf[0];
      m_cachedRSI = rsiBuf[0];
      m_cachedSymbol = symbol;
      m_cachedBarTime = barTime;
      return true;
   }

   double GetATRCached(const string symbol, const SScalpConfig &config)
   {
      if(!RefreshIndicators(symbol, config))
         return 0.0;
      return m_cachedATR;
   }

// Stateless — reads handles/buffers only, touches no member state.
   static bool GetEMACrossover(const string symbol, const SScalpConfig &config,
                               ENUM_TRADE_SIGNAL &signal)
   {
      CIndicatorManager* indMgr = CIndicatorManager::Instance();
      if(indMgr == NULL)
         return false;

      // Need 2 bars for crossover detection
      int fastHandle = indMgr.GetMAHandle(symbol, PERIOD_M1, config.fastEMA, 0, MODE_EMA, PRICE_CLOSE);
      int slowHandle = indMgr.GetMAHandle(symbol, PERIOD_M1, config.slowEMA, 0, MODE_EMA, PRICE_CLOSE);
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

   bool IsRSIConfirmed(ENUM_TRADE_SIGNAL signal, const SScalpConfig &config) const
   {
      if(m_cachedRSI <= 0.0)
         return false;

      if(signal == TRADE_SIGNAL_BUY)
         return (m_cachedRSI < config.rsiOverbought);
      else if(signal == TRADE_SIGNAL_SELL)
         return (m_cachedRSI > config.rsiOversold);

      return false;
   }
};

#endif // CORE_SCALP_FAST_SCALP_INDICATORS_MQH
