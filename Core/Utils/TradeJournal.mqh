//+------------------------------------------------------------------+
//| Trade Journal - Persistent CSV trade logging for crash recovery  |
//| Records open/close events for orphaned-position reconciliation   |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, MiMoCode"
#property link      ""
#property version   "1.00"
#property strict

#ifndef CORE_TRADE_JOURNAL_MQH
#define CORE_TRADE_JOURNAL_MQH

//+------------------------------------------------------------------+
//| Write a single CSV row to the trade journal                     |
//+------------------------------------------------------------------+
void WriteTradeJournalEntry(const string &action, ulong ticket, const string &symbol,
                            ENUM_ORDER_TYPE type, double volume, double price,
                            double sl, double tp, long magic, const string &reason)
{
    string fileName = "trade_journal_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".csv";
    int handle = FileOpen(fileName, FILE_WRITE | FILE_READ | FILE_CSV | FILE_COMMON, ',');
    if(handle == INVALID_HANDLE)
    {
        PrintFormat("[JOURNAL] Failed to open journal file: %s", fileName);
        return;
    }

    FileSeek(handle, 0, SEEK_END);
    FileWrite(handle,
              TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
              action,
              IntegerToString(ticket),
              symbol,
              EnumToString(type),
              DoubleToString(volume, 2),
              DoubleToString(price, 5),
              DoubleToString(sl, 5),
              DoubleToString(tp, 5),
              IntegerToString(magic),
              reason);
    FileClose(handle);
}

//+------------------------------------------------------------------+
//| Journal an open trade event                                      |
//+------------------------------------------------------------------+
void JournalTradeOpen(ulong ticket, const string &symbol, ENUM_ORDER_TYPE type,
                      double volume, double price, double sl, double tp,
                      long magic, const string &reason)
{
    WriteTradeJournalEntry("OPEN", ticket, symbol, type, volume, price, sl, tp, magic, reason);
    PrintFormat("[JOURNAL-OPEN] ticket=%I64u | %s %s %.2f @ %.5f | SL=%.5f TP=%.5f | magic=%d | %s",
                ticket, EnumToString(type), symbol, volume, price, sl, tp, magic, reason);
}

//+------------------------------------------------------------------+
//| Journal a close trade event                                      |
//+------------------------------------------------------------------+
void JournalTradeClose(ulong ticket, const string &symbol, ENUM_ORDER_TYPE type,
                       double volume, double exitPrice, double sl, double tp,
                       long magic, double profit, const string &reason)
{
    string closeReason = reason + " | P&L=" + DoubleToString(profit, 2);
    WriteTradeJournalEntry("CLOSE", ticket, symbol, type, volume, exitPrice, sl, tp, magic,
                           closeReason);
    PrintFormat("[JOURNAL-CLOSE] ticket=%I64u | %s %s %.2f @ %.5f | P&L=%.2f | %s",
                ticket, EnumToString(type), symbol, volume, exitPrice, profit, reason);
}

//+------------------------------------------------------------------+
//| Reconcile trade journal against live positions on init           |
//| Detects orphaned trades (open without matching close)            |
//+------------------------------------------------------------------+
void ReconcileTradeJournal(uint eaMagicNumber)
{
    string fileName = "trade_journal_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".csv";
    if(!FileIsExist(fileName, FILE_COMMON))
    {
        Print("[JOURNAL] No journal file found — nothing to reconcile");
        return;
    }

    int handle = FileOpen(fileName, FILE_READ | FILE_CSV | FILE_COMMON, ',');
    if(handle == INVALID_HANDLE)
    {
        Print("[JOURNAL] Failed to open journal for reconciliation");
        return;
    }

    // Track open events: ticket -> { symbol, type, volume, price, sl, tp, magic, time }
    struct SJournalOpen {
        ulong ticket;
        string symbol;
        ENUM_ORDER_TYPE type;
        double volume;
        double price;
        double sl;
        double tp;
        long magic;
        string time;
    };

    SJournalOpen openEvents[];
    int openCount = 0;

    // Also track which tickets had CLOSE events
    ulong closedTickets[];
    int closedCount = 0;

    while(!FileIsEnding(handle))
    {
        string timestamp = FileReadString(handle);
        string action    = FileReadString(handle);
        string ticketStr = FileReadString(handle);
        string symbol    = FileReadString(handle);
        string typeStr   = FileReadString(handle);
        string volStr    = FileReadString(handle);
        string priceStr  = FileReadString(handle);
        string slStr     = FileReadString(handle);
        string tpStr     = FileReadString(handle);
        string magicStr  = FileReadString(handle);
        // reason may contain commas in the P&L suffix, read rest of line
        string reason    = FileReadString(handle);
        while(!FileIsEnding(handle))
        {
            string extra = FileReadString(handle);
            if(extra == "") break;
            reason += "," + extra;
        }

        ulong ticket = (ulong)StringToInteger(ticketStr);
        if(ticket == 0) continue;

        if(action == "OPEN")
        {
            int idx = openCount;
            openCount++;
            ArrayResize(openEvents, openCount);
            openEvents[idx].ticket  = ticket;
            openEvents[idx].symbol  = symbol;
            openEvents[idx].type    = (ENUM_ORDER_TYPE)StringToInteger(typeStr);
            openEvents[idx].volume  = StringToDouble(volStr);
            openEvents[idx].price   = StringToDouble(priceStr);
            openEvents[idx].sl      = StringToDouble(slStr);
            openEvents[idx].tp      = StringToDouble(tpStr);
            openEvents[idx].magic   = StringToInteger(magicStr);
            openEvents[idx].time    = timestamp;
        }
        else if(action == "CLOSE")
        {
            int idx = closedCount;
            closedCount++;
            ArrayResize(closedTickets, closedCount);
            closedTickets[idx] = ticket;
        }
    }
    FileClose(handle);

    // Find orphaned trades: OPEN events without matching CLOSE
    int orphanCount = 0;
    for(int i = 0; i < openCount; i++)
    {
        bool foundClose = false;
        for(int j = 0; j < closedCount; j++)
        {
            if(closedTickets[j] == openEvents[i].ticket)
            {
                foundClose = true;
                break;
            }
        }

        if(!foundClose)
        {
            // Check if this trade belongs to this EA's magic range
            long tradeMagic = openEvents[i].magic;
            if(eaMagicNumber > 0 && (tradeMagic < (long)eaMagicNumber || tradeMagic > (long)eaMagicNumber + 999))
                continue;

            // Check if position still exists in MT5
            if(PositionSelectByTicket(openEvents[i].ticket))
            {
                // Position is live — expected, no action needed
                PrintFormat("[JOURNAL-RECONCILE] Open position confirmed live: ticket=%I64u | %s %s %.2f @ %.5f | magic=%d | opened=%s",
                            openEvents[i].ticket,
                            EnumToString(openEvents[i].type),
                            openEvents[i].symbol,
                            openEvents[i].volume,
                            openEvents[i].price,
                            openEvents[i].magic,
                            openEvents[i].time);
            }
            else
            {
                // Orphaned: logged as open in journal but no matching close and no live position
                // This means the position was closed externally (manual, SL/TP hit, or broker action)
                // Journal the close event to mark it as resolved
                orphanCount++;
                PrintFormat("[JOURNAL-ORPHAN] ticket=%I64u | %s %s %.2f @ %.5f | opened=%s | closed externally (SL/TP/manual/broker)",
                            openEvents[i].ticket,
                            EnumToString(openEvents[i].type),
                            openEvents[i].symbol,
                            openEvents[i].volume,
                            openEvents[i].price,
                            openEvents[i].time);

                // Write synthetic close to keep journal consistent
                WriteTradeJournalEntry("CLOSE", openEvents[i].ticket, openEvents[i].symbol,
                                       openEvents[i].type, openEvents[i].volume, 0.0,
                                       openEvents[i].sl, openEvents[i].tp,
                                       openEvents[i].magic,
                                       "reconciled_orphan | closed externally");
            }
        }
    }

    PrintFormat("[JOURNAL-RECONCILE] Complete: %d open events | %d close events | %d orphans detected",
                openCount, closedCount, orphanCount);
}

#endif // CORE_TRADE_JOURNAL_MQH
