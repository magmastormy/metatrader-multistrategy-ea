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
//+------------------------------------------------------------------+
#ifndef CORE_RISK_RISK_SYMBOL_STATS_MQH
#define CORE_RISK_RISK_SYMBOL_STATS_MQH

//+------------------------------------------------------------------+
//| Per-symbol deal-history statistics (pure, stateless)             |
//+------------------------------------------------------------------+
class CRiskSymbolStats
{
public:
    //--- Win rate (0-100 scale) over the most recent 50 EA-closed deals
    //--- for the symbol. Returns 50.0 when there is insufficient data.
    static double GetWinRate(const string symbol)
    {
        if(symbol == "")
            return 50.0;

        HistorySelect(0, TimeCurrent());
        int totalDeals = HistoryDealsTotal();
        int wins = 0;
        int total = 0;

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
            if(netPnl > 0.0) wins++;
        }

        if(total < 5)
            return 50.0; // Default for insufficient data

        return ((double)wins / (double)total) * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale
    }

    //--- Profit factor over the most recent 50 EA-closed deals for the
    //--- symbol. Returns 1.0 when there is insufficient data.
    static double GetProfitFactor(const string symbol)
    {
        if(symbol == "")
            return 1.0;

        HistorySelect(0, TimeCurrent());
        int totalDeals = HistoryDealsTotal();
        double grossWin = 0.0;
        double grossLoss = 0.0;
        int total = 0;

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
                grossWin += netPnl;
            else
                grossLoss += MathAbs(netPnl);
        }

        if(total < 5)
            return 1.0; // Default for insufficient data

        if(grossLoss > 0.0)
            return grossWin / grossLoss;
        if(grossWin > 0.0)
            return grossWin; // No losses yet
        return 1.0;
    }
};

#endif // CORE_RISK_RISK_SYMBOL_STATS_MQH
