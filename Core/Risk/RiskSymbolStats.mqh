//+------------------------------------------------------------------+
//| RiskSymbolStats.mqh                                              |
//| Stateless per-symbol historical performance statistics derived   |
//| from the terminal deal history.                                  |
//|                                                                  |
//| Extracted verbatim from CUnifiedRiskManager (Phase E1):          |
//|   CUnifiedRiskManager::GetSymbolWinRate      -> GetWinRate       |
//|   CUnifiedRiskManager::GetSymbolProfitFactor -> GetProfitFactor  |
//|                                                                  |
//| Behaviour is byte-identical to the original member functions;    |
//| CUnifiedRiskManager keeps thin forwarders with the original      |
//| signatures so that all call sites remain unchanged.              |
//|                                                                  |
//| Batch 152 (M-14): HistorySelect(0, ...) materializes the entire  |
//| terminal deal history on every call, and GetSymbolRiskAllocation |
//| queries both metrics for every tracked symbol on each budget     |
//| refresh. Both metrics are now computed in ONE shared pass and    |
//| memoized per symbol for RISK_SYMBOL_STATS_TTL_SECONDS; deal      |
//| history changes slowly so the staleness window is immaterial     |
//| for adaptive weighting.                                          |
//+------------------------------------------------------------------+
#ifndef CORE_RISK_RISK_SYMBOL_STATS_MQH
#define CORE_RISK_RISK_SYMBOL_STATS_MQH

#define RISK_SYMBOL_STATS_TTL_SECONDS 60
#define RISK_SYMBOL_STATS_MAX_ENTRIES 64

//+------------------------------------------------------------------+
//| Per-symbol deal-history statistics (pure, memoized)              |
//+------------------------------------------------------------------+
class CRiskSymbolStats
{
private:
    //--- Memoized metric pair per symbol
    struct SSymbolStatsEntry
    {
        string   symbol;
        double   winRate;
        double   profitFactor;
        datetime lastUpdate;
    };

    static SSymbolStatsEntry s_entries[];

    //--- Single shared pass over the most recent 50 EA-closed deals
    //--- for the symbol; computes both metrics in one HistorySelect.
    static void ComputeStats(const string symbol, double &winRate, double &profitFactor)
    {
        HistorySelect(0, TimeCurrent());
        int totalDeals = HistoryDealsTotal();
        int wins = 0;
        int total = 0;
        double grossWin = 0.0;
        double grossLoss = 0.0;

        for(int i = totalDeals - 1; i >= 0 && total < 50; i--)
        {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(dealTicket <= 0) continue;
            if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != symbol) continue;

            long entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
            if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_INOUT) continue;

            long reason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
            if(reason != DEAL_REASON_EXPERT) continue;

            double netPnl = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                            HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                            HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);

            total++;
            if(netPnl > 0.0)
            {
                wins++;
                grossWin += netPnl;
            }
            else
            {
                grossLoss += MathAbs(netPnl);
            }
        }

        //--- Win rate (0-100 scale); default 50.0 for insufficient data
        winRate = (total < 5) ? 50.0 : ((double)wins / (double)total) * 100.0;

        //--- Profit factor; default 1.0 for insufficient data
        if(total < 5)
            profitFactor = 1.0;
        else if(grossLoss > 0.0)
            profitFactor = grossWin / grossLoss;
        else if(grossWin > 0.0)
            profitFactor = grossWin; // No losses yet
        else
            profitFactor = 1.0;
    }

    //--- Return memoized stats for the symbol, recomputing at most once
    //--- per TTL window. Always yields fresh values through winRate/pf.
    static void GetStats(const string symbol, double &winRate, double &pf)
    {
        datetime now = TimeCurrent();

        int count = ArraySize(s_entries);
        for(int i = 0; i < count; i++)
        {
            if(s_entries[i].symbol != symbol)
                continue;

            if(now - s_entries[i].lastUpdate < RISK_SYMBOL_STATS_TTL_SECONDS)
            {
                winRate = s_entries[i].winRate;
                pf = s_entries[i].profitFactor;
                return;
            }

            //--- Entry exists but is stale: recompute in place
            ComputeStats(symbol, winRate, pf);
            s_entries[i].winRate = winRate;
            s_entries[i].profitFactor = pf;
            s_entries[i].lastUpdate = now;
            return;
        }

        //--- Unknown symbol: compute fresh and store (ring-buffer style
        //--- overwrite once the table is full)
        ComputeStats(symbol, winRate, pf);

        if(count < RISK_SYMBOL_STATS_MAX_ENTRIES)
        {
            ArrayResize(s_entries, count + 1);
            s_entries[count].symbol = symbol;
            s_entries[count].winRate = winRate;
            s_entries[count].profitFactor = pf;
            s_entries[count].lastUpdate = now;
        }
        else
        {
            static int s_nextSlot = 0;
            if(s_nextSlot >= RISK_SYMBOL_STATS_MAX_ENTRIES)
                s_nextSlot = 0;
            s_entries[s_nextSlot].symbol = symbol;
            s_entries[s_nextSlot].winRate = winRate;
            s_entries[s_nextSlot].profitFactor = pf;
            s_entries[s_nextSlot].lastUpdate = now;
            s_nextSlot++;
        }
    }

public:
    //--- Win rate (0-100 scale) over the most recent 50 EA-closed deals
    //--- for the symbol. Returns 50.0 when there is insufficient data.
    static double GetWinRate(const string symbol)
    {
        if(symbol == "")
            return 50.0;

        double winRate = 50.0;
        double pf = 1.0;
        GetStats(symbol, winRate, pf);
        return winRate;
    }

    //--- Profit factor over the most recent 50 EA-closed deals for the
    //--- symbol. Returns 1.0 when there is insufficient data.
    static double GetProfitFactor(const string symbol)
    {
        if(symbol == "")
            return 1.0;

        double winRate = 50.0;
        double pf = 1.0;
        GetStats(symbol, winRate, pf);
        return pf;
    }
};

//--- Batch 152: file-scope storage for static class members (MQL5 requirement)
CRiskSymbolStats::SSymbolStatsEntry CRiskSymbolStats::s_entries[];

#endif // CORE_RISK_RISK_SYMBOL_STATS_MQH
