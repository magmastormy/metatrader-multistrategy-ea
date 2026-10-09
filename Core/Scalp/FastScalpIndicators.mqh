// Decomposition extraction from CFastScalpEngine (behaviour
// preserving).
// Owns the per-symbol cached indicator state that used to live as
// six loose members on CFastScalpEngine:
// m_cachedSymbol, m_cachedBarTime, m_cachedATR,
// m_cachedFastEMA, m_cachedSlowEMA, m_cachedRSI
// Moved methods (bodies verbatim):
// RefreshIndicators(), GetATRCached(), GetEMACrossover(),
// IsRSIConfirmed()
// The engine now holds one CFastScalpIndicators BY VALUE and
// forwards to it with one-line forwarders keeping the exact
// original private signatures. Config values that were read from
// m_config are passed in as a const SScalpConfig reference.
#property strict

#ifndef CORE_SCALP_FAST_SCALP_INDICATORS_MQH
#define CORE_SCALP_FAST_SCALP_INDICATORS_MQH

#include "../Utils/Enums.mqh"
#include "../../IndicatorManager.mqh"
#include "FastScalpTypes.mqh"

// CFastScalpIndicators — stateful M1 indicator cache
class CFastScalpIndicators
{
private:
   // Cached indicator data per symbol (moved verbatim from CFastScalpEngine)
   string                    m_cachedSymbol;
   datetime                  m_cachedBarTime;
   double                    m_cachedATR;
   double                    m_cachedFastEMA;
   double                    m_cachedSlowEMA;
   double                    m_cachedRSI;

public:
// Constructor — reproduces the original CFastScalpEngine ctor list
   CFastScalpIndicators() :
      m_cachedSymbol(""),
      m_cachedBarTime(0),
      m_cachedATR(0.0),
      m_cachedFastEMA(0.0),
      m_cachedSlowEMA(0.0),
      m_cachedRSI(0.0)
   {
   }

   //--- Cache readers
   string   GetCachedSymbol()  const { return m_cachedSymbol; }
   datetime GetCachedBarTime() const { return m_cachedBarTime; }
   double   GetCachedATR()     const { return m_cachedATR; }
   double   GetCachedFastEMA() const { return m_cachedFastEMA; }
   double   GetCachedSlowEMA() const { return m_cachedSlowEMA; }
   double   GetCachedRSI()     const { return m_cachedRSI; }

// Overwrite the cache from an external source (signal cache path)
// Assignment order matches the original EvaluateScalpSignal block.
   void SetCachedValues(const string symbol, datetime barTime, double atr,
                        double fastEMA, double slowEMA, double rsi)
   {
      m_cachedATR     = atr;
      m_cachedFastEMA = fastEMA;
      m_cachedSlowEMA = slowEMA;
      m_cachedRSI     = rsi;
      m_cachedSymbol  = symbol;
      m_cachedBarTime = barTime;
   }

// Refresh cached indicator values for a symbol
   bool RefreshIndicators(const string symbol, const SScalpConfig &config)
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
      int fastHandle = indMgr.GetMAHandle(symbol, PERIOD_M1, config.fastEMA, 0, MODE_EMA, PRICE_CLOSE);
      if(fastHandle == INVALID_HANDLE)
         return false;
      double fastBuf[];
      ArraySetAsSeries(fastBuf, true);
      if(CopyBuffer(fastHandle, 0, 0, 2, fastBuf) < 2)
         return false;
      m_cachedFastEMA = fastBuf[0];

      // Slow EMA(13) on M1
      int slowHandle = indMgr.GetMAHandle(symbol, PERIOD_M1, config.slowEMA, 0, MODE_EMA, PRICE_CLOSE);
      if(slowHandle == INVALID_HANDLE)
         return false;
      double slowBuf[];
      ArraySetAsSeries(slowBuf, true);
      if(CopyBuffer(slowHandle, 0, 0, 2, slowBuf) < 2)
         return false;
      m_cachedSlowEMA = slowBuf[0];

      // RSI(7) on M1
      int rsiHandle = indMgr.GetRSIHandle(symbol, PERIOD_M1, config.rsiPeriod, PRICE_CLOSE);
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

// Get ATR value cached
   double GetATRCached(const string symbol, const SScalpConfig &config)
   {
      if(!RefreshIndicators(symbol, config))
         return 0.0;
      return m_cachedATR;
   }

// Get EMA values for crossover detection
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

// Check RSI confirmation: not overbought for BUY, not oversold
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
