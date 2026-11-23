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
    //--- m_managedMagic = managedMagic;
    //--- m_managedMagicRangeMax = managedMagic; // EA updates it later
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
    bool GetPositionNetProfit(const ulong positionId, double &netProfit);

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

bool CStrategyMgrTradeFeedback::GetPositionNetProfit(const ulong positionId, double &netProfit)
{
    netProfit = 0.0;
    if(positionId == 0 || !HistorySelectByPosition(positionId))
        return false;

    double positionNet = 0.0;
    bool foundDeal = false;
    int dealCount = HistoryDealsTotal();
    for(int i = 0; i < dealCount; i++)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        if(dealTicket == 0 || (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) != positionId)
            continue;

        positionNet += HistoryDealGetDouble(dealTicket, DEAL_PROFIT)
                     + HistoryDealGetDouble(dealTicket, DEAL_SWAP)
                     + HistoryDealGetDouble(dealTicket, DEAL_COMMISSION)
                     + HistoryDealGetDouble(dealTicket, DEAL_FEE);
        foundDeal = true;
    }

    if(!foundDeal)
        return false;

    netProfit = positionNet;
    return true;
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

            bool engineManaged = IsEngineManagedPosition(dealComment) ||
                                 CMagicRange::IsEngineReservedOffset((int)(dealMagic - m_managedMagic));

            // Engine-managed exits are correctly excluded from strategy scoring, but they must still
            // leave a realised-P&L record. measured 2,265 fills against only 260
            // "Trade Closed" lines: the fast-scalp path closes on server-side SL/TP, lands here as an
            // engine-managed deal, and returned before anything was printed - so roughly 270 USD of a
            // -258.77 window had no journal line at all. This prints and returns; scoring is untouched.
            if(engineManaged)
            {
                ENUM_DEAL_ENTRY engineEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
                if(engineEntry == DEAL_ENTRY_OUT || engineEntry == DEAL_ENTRY_OUT_BY || engineEntry == DEAL_ENTRY_INOUT)
                {
                    double engineProfit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                    double engineSwap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
                    double engineCommission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
                    double engineFee = HistoryDealGetDouble(dealTicket, DEAL_FEE);
                    PrintFormat("[ENGINE-CLOSE] %s | ticket=%I64u | position=%I64u | magic=%I64d | net=%.2f | comment=%s",
                                dealSymbol, dealTicket,
                                (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID),
                                dealMagic, engineProfit + engineSwap + engineCommission + engineFee, dealComment);
                }
                return;
            }

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

                double netProfit = 0.0;
                bool netProfitAvailable = GetPositionNetProfit(positionId, netProfit);
                string contributors[];
                CTradeAttributionManager* attribution = m_src.GetAttribution();
                bool attributed = false;
                if(positionId > 0 && attribution != NULL && attribution.PopPositionAttribution(positionId, contributors))
                    attributed = true;

                int contributorCount = 0;
                string soleContributor = "";
                for(int contributorIdx = 0; contributorIdx < ArraySize(contributors); contributorIdx++)
                {
                    if(contributors[contributorIdx] == "")
                        continue;
                    contributorCount++;
                    soleContributor = contributors[contributorIdx];
                }

                string netText = netProfitAvailable ? DoubleToString(netProfit, 2) : "unavailable";
                if(netProfitAvailable && attributed && contributorCount == 1 && MathAbs(netProfit) > 0.01)
                {
                    m_src.UpdatePerformance(soleContributor, netProfit);
                    PrintFormat("[STRATEGY-GOVERNANCE] position=%I64u | outcome=eligible | strategy=%s | net=%.2f",
                                positionId, soleContributor, netProfit);
                }
                else
                {
                    string reason = !netProfitAvailable ? "position_history_incomplete" :
                                    !attributed ? "missing_position_attribution" :
                                    contributorCount > 1 ? "multi_contributor_not_causal" :
                                    contributorCount == 0 ? "empty_contributor_set" : "break_even";
                    PrintFormat("[STRATEGY-GOVERNANCE] position=%I64u | outcome=excluded | reason=%s | contributors=%d | net=%s",
                                positionId, reason, contributorCount, netText);
                }

                // Reset cached contributor context after close in manager-only governance mode.
                m_src.ResetLastContributorContext();

                string outcome = !netProfitAvailable ? "UNAVAILABLE" :
                                 (netProfit > 0.0 ? "SUCCESS" : (netProfit < 0.0 ? "FAILURE" : "SCRATCH"));
                PrintFormat("[EnterpriseManager] Trade Closed | Symbol: %s | Ticket: %I64u | PositionID: %I64u | Net Profit: %s | Result: %s",
                           dealSymbol, dealTicket, positionId, netText, outcome);

                // Per-symbol loss-streak breaker: the fill that trips it says so once, here, with the symbol name
                // in hand. A winner resets the count, so the block only fires on a real run of losses.
                if(netProfitAvailable && m_src.RecordSymbolClose(netProfit))
                    PrintFormat("[SYMBOL-STREAK] %s | %d consecutive losing closes -> entries held for %d min",
                                dealSymbol, m_src.GetSymbolLossStreak(), m_src.GetSymbolLossStreakCooldownSec() / 60);
            }
        }
    }
}

#endif // STRATEGY_MGR_TRADE_FEEDBACK_MQH

