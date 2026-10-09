// Strategy Manager Trade Feedback (Phase G - G6)
// Owns the EA magic-number ownership window and the trade-outcome
// feedback loop that used to be loose members / bodies of
// - m_managedMagic / m_managedMagicRangeMax  (ownership window)
// - IsEAOwnedMagic          (ownership predicate)
// - IsPositionIdStillOpen   (partial-close guard)
// - OnTradeTransaction      (deal -> attribution -> performance)
// *** BEHAVIOUR CONTRACT ***
// Every body is a byte-for-byte relocation of the original manager
// body. The only mechanical substitutions are the manager-member
// reads, which now go through the manager's existing public
// accessors:
// m_symbol                  -> m_src.GetManagedSymbol()
// m_attribution             -> m_src.GetAttribution()
// m_healthMonitor           -> m_src.GetHealthMonitor()
// m_successfulSignals++     -> m_src.IncrementSuccessfulSignals()
// m_lastContributorCount    -> m_src.GetLastContributorCountValue()
// ArraySize(m_lastSignalContributors)
// -> m_src.GetLastContributorArraySize()
// m_lastSignalContributors  -> m_src.GetLastSignalContributors()
// (read-only copy; the callee only
// reads the array)
// the 3-statement contributor reset
// -> m_src.ResetLastContributorContext()
// FindStrategyIndexByName   -> m_src.GetStrategyIndexByName()
// No comparison, no arithmetic and no log string was altered.
// This module MUTATES the manager, so it holds a NON-const back-
// pointer. It mirrors no injected manager pointer (the attribution
// manager and health monitor are re-read from the manager on every
// call), so it needs no re-sync on Deinit.
// NOTE: this header is an implementation detail of
// EnterpriseStrategyManager.mqh and is included from there (after
// the shared free helpers, before the manager class). It is not
// intended to be included standalone.
#ifndef STRATEGY_MGR_TRADE_FEEDBACK_MQH
#define STRATEGY_MGR_TRADE_FEEDBACK_MQH

#include "StrategyHealthMonitor.mqh"                      // CStrategyHealthMonitor::RecordTradeResult
#include "../../Core/Trading/TradeAttributionManager.mqh" // CTradeAttributionManager

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

// Check if magic number is owned by this EA
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

// OnTradeTransaction - Handle trade events for AI feedback
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

            ENUM_DEAL_ENTRY entryType = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            ulong positionId = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);

            if((entryType == DEAL_ENTRY_IN || entryType == DEAL_ENTRY_INOUT) &&
               positionId > 0 &&
               m_src.GetLastContributorCountValue() > 0 &&
               m_src.GetLastContributorArraySize() > 0)
            {
                CTradeAttributionManager* attribution = m_src.GetAttribution();
                if(attribution != NULL)
                {
                    string lastContributors[];
                    m_src.GetLastSignalContributors(lastContributors);
                    attribution.UpsertPositionAttribution(positionId, lastContributors);
                }
            }

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
                if(success)
                    m_src.IncrementSuccessfulSignals();

                // Pop position attribution from trade attribution manager
                string contributors[];
                CTradeAttributionManager* attribution = m_src.GetAttribution();
                if(positionId > 0 && attribution != NULL && attribution.PopPositionAttribution(positionId, contributors))
                {
                    // Store in closed trade attribution for PopClosedTradeAttribution
                    // The TradeAttributionManager handles this internally
                    for(int contributorIdx = 0; contributorIdx < ArraySize(contributors); contributorIdx++)
                    {
                        if(contributors[contributorIdx] == "")
                            continue;
                        m_src.UpdatePerformance(contributors[contributorIdx], netProfit);
                        // Also update health monitor
                        CStrategyHealthMonitor* healthMonitor = m_src.GetHealthMonitor();
                        if(healthMonitor != NULL)
                        {
                            int stratIdx = m_src.GetStrategyIndexByName(contributors[contributorIdx]);
                            if(stratIdx >= 0)
                            {
                                healthMonitor.RecordTradeResult(stratIdx, netProfit);
                            }
                        }
                    }
                }

                // Reset cached contributor context after close in manager-only governance mode.
                m_src.ResetLastContributorContext();

                PrintFormat("[EnterpriseManager] Trade Closed | Symbol: %s | Ticket: %I64u | PositionID: %I64u | Net Profit: %.2f | Result: %s",
                           dealSymbol, dealTicket, positionId, netProfit, success ? "SUCCESS" : "FAILURE");
            }
        }
    }
}

#endif // STRATEGY_MGR_TRADE_FEEDBACK_MQH
