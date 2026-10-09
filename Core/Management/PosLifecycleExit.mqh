//+------------------------------------------------------------------+
//| PosLifecycleExit.mqh                                              |
//| Scheduled exit rules — partial profit taking (partial close) and  |
//| maximum position hold time — extracted from                       |
//| PositionLifecycleManager.mqh (Phase H — God Object decomposition) |
//|                                                                   |
//| Owns: partial-profit config + max-hold-time config.               |
//| Behaviour preserved 1:1 — no logic changes.                       |
//+------------------------------------------------------------------+
#ifndef POS_LIFECYCLE_EXIT_MQH
#define POS_LIFECYCLE_EXIT_MQH

#include "..\Trading\TradeManager.mqh"
#include "PosLifecycleMagicFilter.mqh"
#include "PosLifecycleVolatility.mqh"   // CPosLifecycleVolatility::GetATR()

//+------------------------------------------------------------------+
//| CPosLifecycleExit                                                 |
//| Stateful module — held BY VALUE by CPositionLifecycleManager.     |
//+------------------------------------------------------------------+
class CPosLifecycleExit
{
private:
    // EXECUTION REFINEMENT: Partial profit taking config
    bool   m_partialProfitTakingEnabled;
    double m_partialProfitATRMultiplier;
    double m_partialProfitPercent;

    // Issue #44: Maximum position hold time config
    bool   m_maxHoldTimeEnabled;
    int    m_maxHoldHoursIntraday;   // Max hold time for intraday (H1 and lower) — default 24h
    int    m_maxHoldHoursSwing;      // Max hold time for swing (H4 and higher) — default 120h (5 days)
    bool   m_maxHoldOnlyIfLoss;      // Only close if position is in loss (default true)

    // Batch 150: tickets that already took their partial close. Without this marker
    // the partial-profit rule closed m_partialProfitPercent of remaining volume
    // every tick until the position was gone.
    ulong  m_partialDoneTickets[];
    int    m_partialDoneCount;

public:
    CPosLifecycleExit() :
        m_partialProfitTakingEnabled(false),
        m_partialProfitATRMultiplier(1.0),
        m_partialProfitPercent(25.0),
        m_maxHoldTimeEnabled(true),
        m_maxHoldHoursIntraday(24),
        m_maxHoldHoursSwing(120),
        m_maxHoldOnlyIfLoss(true),
        m_partialDoneCount(0)
    {}

    //--- EXECUTION REFINEMENT: Configure partial profit taking
    void ConfigurePartialProfitTaking(bool enabled, double atrMultiplier, double profitPercent)
    {
        m_partialProfitTakingEnabled = enabled;
        m_partialProfitATRMultiplier = atrMultiplier;
        m_partialProfitPercent = profitPercent;
    }

    //--- Issue #44: Configure maximum position hold time
    void ConfigureMaxHoldTime(bool enabled, int maxHoldHoursIntraday, int maxHoldHoursSwing, bool onlyIfLoss)
    {
        m_maxHoldTimeEnabled = enabled;
        m_maxHoldHoursIntraday = maxHoldHoursIntraday;
        m_maxHoldHoursSwing = maxHoldHoursSwing;
        m_maxHoldOnlyIfLoss = onlyIfLoss;
    }

    //--- Guard-clause accessors used by CPositionLifecycleManager::ManagePositions()
    bool IsPartialProfitTakingEnabled() const { return m_partialProfitTakingEnabled; }
    bool IsMaxHoldTimeEnabled()         const { return m_maxHoldTimeEnabled; }

    //--- EXECUTION REFINEMENT: Partial profit taking management
    bool PartialAlreadyTaken(const ulong ticket) const
    {
        for(int i = 0; i < m_partialDoneCount; i++)
            if(m_partialDoneTickets[i] == ticket) return true;
        return false;
    }

    void MarkPartialTaken(const ulong ticket)
    {
        if(PartialAlreadyTaken(ticket)) return;
        int n = m_partialDoneCount;
        ArrayResize(m_partialDoneTickets, n + 1);
        m_partialDoneTickets[n] = ticket;
        m_partialDoneCount = n + 1;
    }

    // Drop markers for positions that no longer exist (lazy compaction)
    void CompactPartialMarkers()
    {
        int w = 0;
        for(int i = 0; i < m_partialDoneCount; i++)
        {
            if(PositionSelectByTicket(m_partialDoneTickets[i]))
                m_partialDoneTickets[w++] = m_partialDoneTickets[i];
        }
        if(w != m_partialDoneCount)
        {
            m_partialDoneCount = w;
            ArrayResize(m_partialDoneTickets, w);
        }
    }

    void ManagePartialProfitTaking(CTradeManager* tradeManager, const int magicBase, const int magicMax)
    {
        if(m_partialDoneCount > 64) CompactPartialMarkers();

        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(!CPosLifecycleMagicFilter::IsLifecycleManaged(PositionGetInteger(POSITION_MAGIC),
                                                             PositionGetString(POSITION_COMMENT),
                                                             magicBase, magicMax)) continue;
            if(PartialAlreadyTaken(ticket)) continue;   // one partial per position lifetime

            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double currentVolume = PositionGetDouble(POSITION_VOLUME);
            double currentTP = PositionGetDouble(POSITION_TP);

            // Skip if no TP set or already took partial profit
            if(currentTP == 0) continue;

            // Calculate profit distance
            double profitDistance = 0.0;
            if(type == POSITION_TYPE_BUY)
                profitDistance = currentPrice - openPrice;
            else
                profitDistance = openPrice - currentPrice;

            // Get ATR
            double atr = CPosLifecycleVolatility::GetATR(symbol, 14);
            if(atr <= 0) continue;

            // Check if reached partial profit target
            double partialTarget = atr * m_partialProfitATRMultiplier;
            if(profitDistance >= partialTarget && currentVolume > 0.01)
            {
                // Calculate partial close amount
                double closeAmount = currentVolume * (m_partialProfitPercent / 100.0);
                closeAmount = NormalizeDouble(closeAmount, 2);

                if(closeAmount >= 0.01)
                {
                    PrintFormat("[PARTIAL-PROFIT] Taking partial profit | ticket=%I64u | amount=%.2f | profit=%.5f",
                                ticket, closeAmount, profitDistance);
                    if(tradeManager.ClosePositionPartial(ticket, closeAmount, "Partial Profit"))
                        MarkPartialTaken(ticket);
                }
            }
        }
    }

    //--- Issue #44: Maximum position hold time management
    void ManageMaxHoldTime(CTradeManager* tradeManager, const int magicBase, const int magicMax)
    {
        if(!m_maxHoldTimeEnabled)
            return;

        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(!CPosLifecycleMagicFilter::IsLifecycleManaged(PositionGetInteger(POSITION_MAGIC),
                                                             PositionGetString(POSITION_COMMENT),
                                                             magicBase, magicMax)) continue;

            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            double currentProfit = PositionGetDouble(POSITION_PROFIT);

            // Calculate hours open
            int hoursOpen = (int)((TimeCurrent() - openTime) / 3600);

            // Determine max hold time based on timeframe
            ENUM_TIMEFRAMES currentTF = (ENUM_TIMEFRAMES)Period();
            int maxHoldHours = (currentTF <= PERIOD_H1) ? m_maxHoldHoursIntraday : m_maxHoldHoursSwing;

            // Check if position exceeds max hold time
            if(hoursOpen > maxHoldHours)
            {
                // If only close on loss, check profit
                if(m_maxHoldOnlyIfLoss && currentProfit >= 0.0)
                {
                    continue; // Position is profitable, don't force close
                }

                PrintFormat("[TIME-EXIT] Position %d held for %d hours (max %d) on %s with profit %.2f - closing",
                            ticket, hoursOpen, maxHoldHours, symbol, currentProfit);
                tradeManager.ClosePosition(ticket, "Max Hold Time");
            }
        }
    }
};

#endif // POS_LIFECYCLE_EXIT_MQH
