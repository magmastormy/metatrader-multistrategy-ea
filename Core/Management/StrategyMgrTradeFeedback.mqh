// Owns the EA magic-number ownership window (m_managedMagic / m_managedMagicRangeMax) and the trade-outcome
// feedback loop: ownership predicate, partial-close guard, and OnTradeTransaction (deal -> attribution ->
// performance). Bodies relocated byte-for-byte, manager reads through public accessors; added the
// one deliberate exception - the engine-book filter OnTradeTransaction needed for attribution.
#ifndef STRATEGY_MGR_TRADE_FEEDBACK_MQH
#define STRATEGY_MGR_TRADE_FEEDBACK_MQH

#include "../../Core/Trading/TradeAttributionManager.mqh" // CTradeAttributionManager
#include "../Utils/MagicRange.mqh"                        // IsEngineManagedPosition / CMagicRange

class CEnterpriseStrategyManager;   // forward: held as a mutable pointer

// Magic ownership + trade outcome feedback
class CStrategyMgrTradeFeedback
{
private:
    CEnterpriseStrategyManager* m_src;

    long m_managedMagic;
    long m_managedMagicRangeMax;

public:
    CStrategyMgrTradeFeedback() : m_src(NULL), m_managedMagic(0), m_managedMagicRangeMax(0) {}

    void SetSource(CEnterpriseStrategyManager* src) { m_src = src; }

    //--- Initialize() seeded both fields from the same argument:
    //---   m_managedMagic = managedMagic;
    //---   m_managedMagicRangeMax = managedMagic; // EA updates it later
    void SetManagedMagic(const long managedMagic)
    {
        m_managedMagic = managedMagic;
        m_managedMagicRangeMax = managedMagic; // Default: exact match; EA will update after symbol universe is built
    }
    void SetManagedMagicRangeMax(const long rangeMax) { m_managedMagicRangeMax = rangeMax; }

    long GetManagedMagic() const         { return m_managedMagic; }
    long GetManagedMagicRangeMax() const { return m_managedMagicRangeMax; }

    //--- ownership predicate / partial-close guard
    bool IsEAOwnedMagic(long magic) const;
    bool IsPositionIdStillOpen(const ulong positionId) const;

    //--- trade outcome feedback
    void OnTradeTransaction(const MqlTradeTransaction& trans,
                            const MqlTradeRequest& request,
                            const MqlTradeResult& result);
};

bool CStrategyMgrTradeFeedback::IsEAOwnedMagic(long magic) const
{
    if(m_managedMagic <= 0)
        return false;
    if(magic == m_managedMagic)
        return true;
    if(magic > m_managedMagic && magic <= m_managedMagicRangeMax)
        return true;
    return false;
}

// Is the position still open? (partial-close double-count guard)
bool CStrategyMgrTradeFeedback::IsPositionIdStillOpen(const ulong positionId) const
{
    if(positionId == 0)
        return false;

    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

        ulong openPositionId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
        if(openPositionId == positionId)
            return true;
    }

    return false;
}

void CStrategyMgrTradeFeedback::OnTradeTransaction(const MqlTradeTransaction& trans,
                                                   const MqlTradeRequest& request,
                                                   const MqlTradeResult& result)
{
    if(m_src == NULL)
        return;

    // Check for transaction adding a deal (trade execution)
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
    {
        ulong dealTicket = trans.deal;
        if(HistoryDealSelect(dealTicket))
        {
            long dealMagic = HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
            if(m_managedMagic > 0 && !IsEAOwnedMagic(dealMagic))
                return;

            string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
            if(dealSymbol != "" && dealSymbol != m_src.GetManagedSymbol())
                return;

            // An engine's own fill is not this manager's trade. The contributor context holds the
            // last consensus decision on this symbol, so without this filter a scalp landing in the
            // same window would be scored as the strategies that did not signal it.
            string dealComment = HistoryDealGetString(dealTicket, DEAL_COMMENT);
            if(dealComment == "")
                dealComment = request.comment;
            if(IsEngineManagedPosition(dealComment) ||
               CMagicRange::IsEngineReservedOffset((int)(dealMagic - m_managedMagic)))
                return;

            ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            ulong positionId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

            // Attribution is written at execution, keyed by the fill's own positionId. Re-upserting
            // from the cached contributor list here would overwrite it with whichever decision ran last.

            // We care about exits (deals that close a position) to meaningful profit/loss
            if(entryType == DEAL_ENTRY_OUT || entryType == DEAL_ENTRY_OUT_BY || entryType == DEAL_ENTRY_INOUT)
            {
                // Avoid double-counting partial closes; attribute only once when position is fully closed.
                if(positionId > 0 && IsPositionIdStillOpen(positionId))
                    return;

                double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                double netProfit = profit + swap + commission;

                bool success = (netProfit > 0);
                string contributors[];
                CTradeAttributionManager* attribution = m_src.GetAttribution();
                bool attributed = false;
                if(positionId > 0 && attribution != NULL && attribution.PopPositionAttribution(positionId, contributors))
                    attributed = true;

                // Fallback: when no map entry exists for this position id, score the strategies that
                // produced this symbol's last signal rather than dropping the outcome on the floor. The
                // store above is keyed by position id and the entry map can legitimately miss (a fill the
                // tester reports before the deal reaches history), and an unattributed close teaches the
                // book nothing: the earlier measured window closed 46 positions and credited 2 rows.
                if(!attributed)
                {
                    m_src.GetLastSignalContributors(contributors);
                    attributed = (ArraySize(contributors) > 0);
                }

                if(attributed)
                {
                    // The whole closed-trade attribution path: strategy stats are written here
                    // and nowhere else.
                    for(int contributorIdx = 0; contributorIdx < ArraySize(contributors); contributorIdx++)
                    {
                        if(contributors[contributorIdx] == "")
                            continue;
                        m_src.UpdatePerformance(contributors[contributorIdx], netProfit);
                        // UpdatePerformance already feeds the health monitor (CStrategyPerformanceHealth
                        // forwards it as RecordTradeResult). This used to call RecordTradeResult again
                        // here, so every closed trade entered the rolling sample twice and the
                        // consecutive-loss park fired after 3 real losses, not its stated 5.
                    }
                }

                // Reset cached contributor context after close in manager-only governance mode.
                m_src.ResetLastContributorContext();

                PrintFormat("[EnterpriseManager] Trade Closed | Symbol: %s | Ticket: %I64u | PositionID: %I64u | Net Profit: %.2f | Result: %s",
                           dealSymbol, dealTicket, positionId, netProfit, success ? "SUCCESS" : "FAILURE");

                // Per-symbol loss-streak breaker: the fill that trips it says so once, here, with the symbol name
                // in hand. A winner resets the count, so the block only fires on a real run of losses.
                if(m_src.RecordSymbolClose(netProfit))
                    PrintFormat("[SYMBOL-STREAK] %s | %d consecutive losing closes -> entries held for %d min",
                                dealSymbol, m_src.GetSymbolLossStreak(), m_src.GetSymbolLossStreakCooldownSec() / 60);
            }
        }
    }
}

#endif // STRATEGY_MGR_TRADE_FEEDBACK_MQH

