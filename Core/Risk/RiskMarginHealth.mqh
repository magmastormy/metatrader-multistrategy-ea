// Free-margin / margin-level pre-flight checks and the runtime
// margin-health monitor with protective de-risking actions.
// Extracted verbatim from CUnifiedRiskManager (Phase E2, E-G):
// free-margin/margin-level tail of ValidateMarginRequirements
// Behaviour is byte-identical to the original member functions;
// CUnifiedRiskManager keeps thin forwarders with the original
// signatures so that all call sites remain unchanged.
// OWNERSHIP NOTE: the emergency halt performed at the <150% margin
// level mutates circuit-breaker state (m_tradingEnabled /
// m_cbTriggeredAt) and the shared conservative-mode flag. Rather
// than duplicating that state or holding a back-pointer, both are
// passed in as parameters from the forwarder.
#ifndef CORE_RISK_RISK_MARGIN_HEALTH_MQH
#define CORE_RISK_RISK_MARGIN_HEALTH_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/TradeJournal.mqh"
#include "RiskCircuitBreaker.mqh"
#include <Trade/Trade.mqh>

// Margin health monitor (stateful config holder, owned by value)
class CRiskMarginHealth
{
private:
    double m_maxFreeMarginUsage;   // Fraction of free margin usable by one order (0.8 = 80%)
    double m_minMarginLevel;       // Minimum acceptable post-trade margin level (%)

public:
    //--- Constructor performs the zero-init that used to live in the
    //--- CUnifiedRiskManager initialiser list (identical values).
    CRiskMarginHealth() :
        m_maxFreeMarginUsage(0.8),
        m_minMarginLevel(200.0)
    {
    }

    ~CRiskMarginHealth()
    {
        // No owned resources.
    }

// Pre-flight validation

    //--- Free-margin headroom + post-trade margin-level check used by
    //--- CUnifiedRiskManager::ValidateMarginRequirements.
    //--- Returns true when the requested margin is acceptable.
    bool CheckFreeMarginAndLevel(const double marginRequired,
                                 const bool isHedging,
                                 string &message) const
    {
        // Check available margin
        double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

        if(marginRequired > freeMargin * m_maxFreeMarginUsage) // Fixed at construction: SetMaxFreeMarginUsage has no caller and no input feeds it
        {
            message = StringFormat("Insufficient margin: required %.2f, available %.2f (threshold: %.0f%%) [mode: %s]",
                                 marginRequired, freeMargin, m_maxFreeMarginUsage * 100.0,
                                 isHedging ? "hedging" : "netting");
            return false;
        }

        // Check margin level after trade
        double currentMarginLevel = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
        if(currentMarginLevel > 0 && currentMarginLevel < m_minMarginLevel)
        {
            message = StringFormat("Margin level too low: %.2f%% (threshold: %.0f%%)",
                                 currentMarginLevel, m_minMarginLevel);
            return false;
        }

        return true;
    }

// Runtime monitoring

    //--- Margin Health Monitoring (Phase 2.4).
    //--- Checks margin level and takes protective action.
    //--- `breaker` receives the emergency halt; `conservativeMode` is the
    //--- owner's shared conservative-mode flag.
    ENUM_MARGIN_HEALTH_LEVEL MonitorMarginHealth(CRiskCircuitBreaker &breaker,
                                                 bool &conservativeMode)
    {
        double margin = AccountInfoDouble(ACCOUNT_MARGIN);
        if(margin <= 0.0)
            return MARGIN_HEALTH_OK; // No margin used = no risk

        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        if(equity <= 0.0)
            return MARGIN_HEALTH_EMERGENCY;

        double marginLevel = (equity / margin) * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale (margin level %)

        // Emergency: margin level < 150% — close all positions immediately
        if(marginLevel < 150.0)
        {
            PrintFormat("[RISK-MARGIN] EMERGENCY | Margin Level=%.1f%% < 150%% | Closing ALL positions immediately",
                       marginLevel);

            // Close all positions
            int totalPositions = PositionsTotal();
            for(int i = totalPositions - 1; i >= 0; i--)
            {
                ulong ticket = PositionGetTicket(i);
                if(ticket > 0 && PositionSelectByTicket(ticket))
                {
                    // Journal before close for crash recovery
                    ENUM_ORDER_TYPE closeType = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
                    double closeVol = PositionGetDouble(POSITION_VOLUME);
                    double closePrice = PositionGetDouble(POSITION_PRICE_OPEN);
                    double closeSL = PositionGetDouble(POSITION_SL);
                    double closeTP = PositionGetDouble(POSITION_TP);
                    long closeMagic = PositionGetInteger(POSITION_MAGIC);
                    double closeProfit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
                    string closeSymbol = PositionGetString(POSITION_SYMBOL);
                    // Use MT5 trade object for emergency close
                    CTrade emergencyTrade;
                    if(emergencyTrade.PositionClose(ticket))
                    {
                        string journalReason = "emergency_margin_breach | P&L=" + DoubleToString(closeProfit, 2);
                        WriteTradeJournalEntry("CLOSE", ticket, closeSymbol, closeType, closeVol,
                                               0.0, closeSL, closeTP, closeMagic, journalReason);
                    }
                }
            }

            breaker.HaltForMarginEmergency();
            return MARGIN_HEALTH_EMERGENCY;
        }

        // Critical: margin level < 200% — close worst position, block new entries
        if(marginLevel < 200.0)
        {
            PrintFormat("[RISK-MARGIN] CRITICAL | Margin Level=%.1f%% < 200%% | Closing worst position, blocking new entries",
                       marginLevel);

            // Find worst-performing position
            double worstProfit = 0.0;
            ulong worstTicket = 0;
            int totalPositions = PositionsTotal();
            for(int i = 0; i < totalPositions; i++)
            {
                ulong ticket = PositionGetTicket(i);
                if(ticket > 0 && PositionSelectByTicket(ticket))
                {
                    double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
                    if(profit < worstProfit || worstTicket == 0)
                    {
                        worstProfit = profit;
                        worstTicket = ticket;
                    }
                }
            }

            if(worstTicket > 0 && PositionSelectByTicket(worstTicket))
            {
                ENUM_ORDER_TYPE critType = (ENUM_ORDER_TYPE)PositionGetInteger(POSITION_TYPE);
                double critVol = PositionGetDouble(POSITION_VOLUME);
                double critSL = PositionGetDouble(POSITION_SL);
                double critTP = PositionGetDouble(POSITION_TP);
                long critMagic = PositionGetInteger(POSITION_MAGIC);
                string critSymbol = PositionGetString(POSITION_SYMBOL);
                CTrade criticalTrade;
                criticalTrade.PositionClose(worstTicket);
                string critJournalReason = "emergency_margin_critical | P&L=" + DoubleToString(worstProfit, 2);
                WriteTradeJournalEntry("CLOSE", worstTicket, critSymbol, critType, critVol,
                                       0.0, critSL, critTP, critMagic, critJournalReason);
                PrintFormat("[RISK-MARGIN] Closed worst position | ticket=%I64u | profit=%.2f", worstTicket, worstProfit);
            }

            conservativeMode = true;
            return MARGIN_HEALTH_CRITICAL;
        }

        // Warning: margin level < 300% — reduce position sizes on next entries
        if(marginLevel < 300.0)
        {
            static datetime s_lastMarginWarning = 0;
            datetime now = TimeCurrent();
            if(s_lastMarginWarning == 0 || (now - s_lastMarginWarning) >= 60)
            {
                PrintFormat("[RISK-MARGIN] WARNING | Margin Level=%.1f%% < 300%% | Reducing position sizes on next entries",
                           marginLevel);
                s_lastMarginWarning = now;
            }
            conservativeMode = true;
            return MARGIN_HEALTH_WARNING;
        }

        return MARGIN_HEALTH_OK;
    }

// Accessors

    double GetMaxFreeMarginUsage() const
    {
        return m_maxFreeMarginUsage;
    }

    void SetMaxFreeMarginUsage(const double value)
    {
        m_maxFreeMarginUsage = value;
    }

    double GetMinMarginLevel() const
    {
        return m_minMarginLevel;
    }

    void SetMinMarginLevel(const double value)
    {
        m_minMarginLevel = value;
    }
};

#endif // CORE_RISK_RISK_MARGIN_HEALTH_MQH
