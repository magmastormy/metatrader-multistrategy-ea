// Win rate + profit factor: HistorySelect materializes the whole deal history per call, so both
// metrics share ONE pass, memoized per symbol for RISK_SYMBOL_STATS_TTL_SECONDS (staleness is harmless).
#ifndef CORE_RISK_RISK_SYMBOL_STATS_MQH
#define CORE_RISK_RISK_SYMBOL_STATS_MQH

#define RISK_SYMBOL_STATS_TTL_SECONDS 60
#define RISK_SYMBOL_STATS_MAX_ENTRIES 64

// Per-symbol deal-history statistics (pure, memoized)
class CRiskSymbolStats
{
private:
    struct SSymbolStatsEntry
    {
        string   symbol;
        double   winRate;
        double   profitFactor;
        datetime lastUpdate;
    };

    static SSymbolStatsEntry s_entries[];

    //--- Both metrics from one pass over the 50 most recent EA-closed out-deals of the symbol.
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

    //--- Memoized read: recomputes at most once per TTL window; winRate/pf are always populated.
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

            ComputeStats(symbol, winRate, pf);
            s_entries[i].winRate = winRate;
            s_entries[i].profitFactor = pf;
            s_entries[i].lastUpdate = now;
            return;
        }

        //--- Unknown symbol: compute fresh; once full the table overwrites entries round-robin.
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
    //--- Win rate (0-100 scale) over the last 50 EA-closed deals; 50.0 when fewer than 5 deals.
    static double GetWinRate(const string symbol)
    {
        if(symbol == "")
            return 50.0;

        double winRate = 50.0;
        double pf = 1.0;
        GetStats(symbol, winRate, pf);
        return winRate;
    }

    //--- Profit factor (grossWin / grossLoss) over the same 50-deal sample; 1.0 when fewer than 5 deals.
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

//--- Static member storage needs this file-scope definition (MQL5 requirement); do not remove.
CRiskSymbolStats::SSymbolStatsEntry CRiskSymbolStats::s_entries[];

#endif // CORE_RISK_RISK_SYMBOL_STATS_MQH
