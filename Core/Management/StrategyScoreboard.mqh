// Per-strategy performance scoreboard, persisted across restarts.
//
// Why this exists: the roster's per-strategy counters (trades / wins / failures / consecutive streaks /
// average profit / health score / park-until) live only in memory, so every restart reset every row to
// the 0.55 prior and un-parked everything. The auto-pruning loop in CStrategyPerformanceHealth
// therefore restarted from zero on each attach, which means the system could never accumulate the one
// piece of knowledge that decides whether it makes money: which rows actually earn.
//
// Keying: the roster is per SYMBOL (11 managers own 11 rosters), so the file is keyed by
// symbol+strategy, not by strategy name alone. Writing name only would have collapsed eleven symbols'
// counters into whichever manager saved last.
//
// Scope, stated: counters and the park flag only. Strategy weights are adjusted at runtime by
// CConsensusWeightingConfig and are NOT restored here - writing them back would make an operator's
// dialog weight override lose to a stale file. strategy_scoreboard.csv is also the operator's
// scoreboard: sort by avgProfit to see which rows carry the book.
#property strict

#ifndef STRATEGY_SCOREBOARD_MQH
#define STRATEGY_SCOREBOARD_MQH

#include "EnterpriseStrategyManager.mqh"

class CStrategyScoreboard
{
private:
    static string FileName() { return "strategy_scoreboard.csv"; }

    static void WriteManagerRows(int handle, CEnterpriseStrategyManager* mgr, int &rows)
    {
        if(mgr == NULL || handle == INVALID_HANDLE)
            return;

        string symbol = mgr.GetManagedSymbol();
        int count = mgr.GetStrategyCount();
        for(int i = 0; i < count; i++)
        {
            string name = mgr.GetStrategyName(i);
            if(name == "")
                continue;

            string line = symbol + ";" + name + ";"
                + IntegerToString(mgr.GetStrategyTotalTrades(i)) + ";"
                + IntegerToString(mgr.GetStrategySuccessCount(i)) + ";"
                + IntegerToString(mgr.GetStrategyFailCount(i)) + ";"
                + IntegerToString(mgr.GetStrategyWinningTrades(i)) + ";"
                + IntegerToString(mgr.GetStrategyConsecutiveWins(i)) + ";"
                + IntegerToString(mgr.GetStrategyConsecutiveLosses(i)) + ";"
                + DoubleToString(mgr.GetStrategyAvgProfit(i), 6) + ";"
                + DoubleToString(mgr.GetStrategyHealthScore(i), 6) + ";"
                + IntegerToString((long)mgr.GetStrategyDisabledUntil(i)) + "\r\n";
            FileWriteString(handle, line);
            rows++;
        }
    }

public:
    // managers[] is the orchestrator's per-symbol manager array; every manager's roster is written
    // into one file, header first.
    static bool Save(CEnterpriseStrategyManager* &managers[], const int managerCount)
    {
        int handle = FileOpen(FileName(), FILE_WRITE | FILE_TXT | FILE_ANSI);
        if(handle == INVALID_HANDLE)
        {
            PrintFormat("[SCOREBOARD] write failed | file=%s | err=%d", FileName(), GetLastError());
            return false;
        }

        FileWriteString(handle, "symbol;name;trades;success;fail;wins;consecW;consecL;avgProfit;health;disabledUntil\r\n");

        int rows = 0;
        for(int m = 0; m < managerCount; m++)
            WriteManagerRows(handle, managers[m], rows);

        FileClose(handle);
        PrintFormat("[SCOREBOARD] saved %d rows | file=%s", rows, FileName());
        return (rows > 0);
    }

    // Returns the rows restored. A missing file is not an error: a first run has nothing to restore
    // and must keep the code's own defaults.
    static int Load(CEnterpriseStrategyManager* &managers[], const int managerCount)
    {
        if(!FileIsExist(FileName()))
        {
            PrintFormat("[SCOREBOARD] no saved state | file=%s | starting from defaults", FileName());
            return 0;
        }

        int handle = FileOpen(FileName(), FILE_READ | FILE_TXT | FILE_ANSI);
        if(handle == INVALID_HANDLE)
        {
            PrintFormat("[SCOREBOARD] read failed | file=%s | err=%d", FileName(), GetLastError());
            return 0;
        }

        if(!FileIsEnding(handle))
            FileReadString(handle); // header

        int restored = 0;
        int parked = 0;
        int unmatched = 0;
        while(!FileIsEnding(handle))
        {
            string line = FileReadString(handle);
            if(StringLen(line) < 5)
                continue;

            string parts[];
            int fields = StringSplit(line, ';', parts);
            if(fields < 11)
                continue;

            string symbol = parts[0];
            string name   = parts[1];

            CEnterpriseStrategyManager* target = NULL;
            for(int m = 0; m < managerCount; m++)
            {
                if(managers[m] != NULL && managers[m].GetManagedSymbol() == symbol)
                {
                    target = managers[m];
                    break;
                }
            }
            if(target == NULL)
            {
                unmatched++;
                continue;
            }

            int idx = target.GetStrategyIndexByName(name);
            if(idx < 0 || idx >= target.GetStrategyCount())
            {
                unmatched++;
                continue;
            }

            target.SetStrategyTotalTrades(idx,       (int)StringToInteger(parts[2]));
            target.SetStrategySuccessCount(idx,      (int)StringToInteger(parts[3]));
            target.SetStrategyFailCount(idx,         (int)StringToInteger(parts[4]));
            target.SetStrategyWinningTrades(idx,     (int)StringToInteger(parts[5]));
            target.SetStrategyConsecutiveWins(idx,   (int)StringToInteger(parts[6]));
            target.SetStrategyConsecutiveLosses(idx, (int)StringToInteger(parts[7]));
            target.SetStrategyAvgProfit(idx,         StringToDouble(parts[8]));
            target.SetStrategyHealthScore(idx,       StringToDouble(parts[9]));

            datetime until = (datetime)StringToInteger(parts[10]);
            target.SetStrategyDisabledUntil(idx, until);
            bool stillParked = (until > TimeCurrent());
            target.SetStrategyTemporarilyDisabled(idx, stillParked);
            if(stillParked)
                parked++;

            restored++;
        }

        FileClose(handle);
        PrintFormat("[SCOREBOARD] restored %d rows | parked=%d | unmatched=%d | file=%s",
                    restored, parked, unmatched, FileName());
        return restored;
    }
};

#endif // STRATEGY_SCOREBOARD_MQH
