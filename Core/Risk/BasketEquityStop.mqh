// Theme 3 (MQL5 article 23662): basket-level equity stop.
// Tracks the account equity PEAK and current drawdown %. When DD
// from peak exceeds a configurable threshold it:
// (a) halts new entries (consumed by the EA's canOpenNewTrades
// gate), and optionally
// (b) sweeps ONLY this EA's basket (magic-filtered) so manual /
// other-EA positions are never touched (unlike
// CTradeManager::CloseAllPositions which is account-wide and
// magic-unfiltered).
// ADDITIVE: it does NOT touch consensus, candidate building, or
// position sizing. The only influence on entry flow is the single
// OR-term on canOpenNewTrades.
#property strict

#ifndef CORE_RISK_BASKET_EQUITY_STOP_MQH
#define CORE_RISK_BASKET_EQUITY_STOP_MQH

#include "../Position/PositionMgrMagicFilter.mqh"

class CTradeManager;   // forward declaration; resolved by EAOrchestrator include order

class CBasketEquityStop
{
private:
   bool           m_enabled;
   double         m_thresholdPct;     // DD% from peak equity that triggers
   bool           m_closeOnBreach;    // also sweep the basket when triggered
   int            m_magicNumber;
   CTradeManager*  m_tradeManager;

   double         m_peakEquity;
   double         m_drawdownPct;
   bool           m_haltActive;       // gates new entries
   bool           m_closeRequested;   // one-shot close request (consumed)

public:
   CBasketEquityStop() : m_enabled(false), m_thresholdPct(10.0), m_closeOnBreach(false),
                         m_magicNumber(0), m_tradeManager(NULL),
                         m_peakEquity(0.0), m_drawdownPct(0.0), m_haltActive(false),
                         m_closeRequested(false) {}

   void Configure(bool enabled, double thresholdPct, bool closeOnBreach,
                  CTradeManager* tm, int magicNumber)
   {
      m_enabled       = enabled;
      m_thresholdPct  = (thresholdPct > 0.0) ? thresholdPct : 10.0;
      m_closeOnBreach = closeOnBreach;
      m_tradeManager  = tm;
      m_magicNumber   = magicNumber;
      m_peakEquity    = 0.0;   // first Update() seeds the peak from live equity
      m_drawdownPct   = 0.0;
      m_haltActive    = false;
      m_closeRequested = false;
   }

   // Call once per timer tick. Seeds + updates the equity peak and sets the halt /
   // close flags. No-op when disabled. Idempotent and side-effect free except for
   // the (intended) flag transitions and a single informational Print on breach.
   void Update(double equity)
   {
      if(!m_enabled) { m_haltActive = false; m_closeRequested = false; return; }
      if(equity <= 0.0) return;

      if(m_peakEquity <= 0.0 || equity > m_peakEquity)
      {
         // New equity high -> reset drawdown and resume entries (prior breach recovered).
         m_peakEquity  = equity;
         m_drawdownPct = 0.0;
         m_haltActive  = false;
      }
      else
      {
         m_drawdownPct = ((m_peakEquity - equity) / m_peakEquity) * 100.0;
      }

      if(m_drawdownPct >= m_thresholdPct)
      {
         if(!m_haltActive)
            PrintFormat("[BASKET-STOP] Drawdown %.2f%% >= threshold %.2f%% -> halting new entries%s",
                        m_drawdownPct, m_thresholdPct,
                        m_closeOnBreach ? " (close-on-breach armed)" : "");
         m_haltActive = true;
         if(m_closeOnBreach && !m_closeRequested)
            m_closeRequested = true;   // consumed once by CloseBasket()
      }
   }

   // Consumed by the EA's entry gate (EAOrchestrator.mqh: canOpenNewTrades).
   bool IsHaltActive() const { return m_enabled && m_haltActive; }

   // True once when a close-on-breach sweep is due. One-shot (consumed by CloseBasket).
   bool ShouldCloseBasket()
   {
      if(!m_enabled || !m_closeOnBreach || !m_closeRequested)
         return false;
      m_closeRequested = false;
      return true;
   }

   // Magic-filtered sweep: closes ONLY this EA's basket positions. Never touches
   // manual / other-EA positions. Returns the number of positions closed.
   int CloseBasket()
   {
      if(m_tradeManager == NULL) return 0;
      int closed = 0;
      int total  = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket <= 0) continue;
         long magic = PositionGetInteger(POSITION_MAGIC);
         if(CPositionMgrMagicFilter::IsEAOwnedMagic(magic))
         {
            if(m_tradeManager.ClosePosition(ticket, "Basket equity stop"))
               closed++;
         }
      }
      if(closed > 0)
         PrintFormat("[BASKET-STOP] Closed %d EA-owned basket position(s) on drawdown breach", closed);
      return closed;
   }

   double GetDrawdownPct() const { return m_drawdownPct; }
   double GetPeakEquity()  const { return m_peakEquity; }
};

#endif // CORE_RISK_BASKET_EQUITY_STOP_MQH
