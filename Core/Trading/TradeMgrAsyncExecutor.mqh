// OrderSendAsync submission, confirmation, timeout and persistence
// Extracted from Core/Trading/TradeManager.mqh (God-Object split).
// OWNS: m_pendingAsyncTrades[] / m_maxPendingAsync /
// m_asyncModeEnabled, plus every async code path.
// CTradeManager holds this class BY VALUE and keeps thin
// forwarders with the original public signatures.
// SPLIT POINT - SendTradeAsync: guards that only need async state
// live here (CheckSendGuards); the volume/price/preflight steps
// that need CTradeManager collaborators stay in the forwarder and
// hand resolved values to SubmitAsync(). Order of checks, prints
// and side effects is identical to the original function.
// NO BACK-POINTER: execution-quality accounting is done by passing
// the caller's CExecutionQualityTracker in by reference.
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property strict

#ifndef CORE_TRADING_TRADE_MGR_ASYNC_EXECUTOR_MQH
#define CORE_TRADING_TRADE_MGR_ASYNC_EXECUTOR_MQH

#include "TradeTypes.mqh"
#include "TradeDescriptor.mqh"
#include "ExecutionQualityTracker.mqh"

class CTradeMgrAsyncExecutor
{
private:
    SAsyncTradeRequest m_pendingAsyncTrades[];  // Dynamic array of pending async confirmations
    int                m_maxPendingAsync;       // Maximum pending async trades (default 10)
    bool               m_asyncModeEnabled;      // Whether async mode is active

public:
    CTradeMgrAsyncExecutor() : m_maxPendingAsync(10),
                               m_asyncModeEnabled(false)
    {
        ArrayResize(m_pendingAsyncTrades, 0);
    }

    bool IsAsyncModeEnabled() const { return m_asyncModeEnabled; }
    void SetAsyncModeEnabled(const bool enabled) { m_asyncModeEnabled = enabled; }
    void FreePending() { ArrayFree(m_pendingAsyncTrades); }

// Get pending async trade count
    int GetPendingAsyncCount() const
    {
        return ArraySize(m_pendingAsyncTrades);
    }

// Get pending async trade ticket by index
    ulong GetPendingAsyncTicket(int index) const
    {
        if(index < 0 || index >= ArraySize(m_pendingAsyncTrades))
            return 0;
        return m_pendingAsyncTrades[index].ticket;
    }

    bool IsDuplicateIdempotencyKey(const string key) const
    {
        for(int i = 0; i < ArraySize(m_pendingAsyncTrades); i++)
        {
            if(m_pendingAsyncTrades[i].idempotencyKey == key)
                return true;
        }
        return false;
    }

// SendTradeAsync guards that only depend on async state
    bool CheckSendGuards(const string symbol, const double lot)
    {
        // Guard: async mode must be enabled
        if(!m_asyncModeEnabled)
        {
            PrintFormat("[ASYNC-TRADE-REJECTED] %s | reason=AsyncModeDisabled", symbol);
            return false;
        }

        // Validate inputs
        if(symbol == "")
        {
            Print("[ASYNC-TRADE-REJECTED] reason=EmptySymbol");
            return false;
        }
        if(lot <= 0.0)
        {
            PrintFormat("[ASYNC-TRADE-REJECTED] %s | reason=InvalidLot lot=%.2f", symbol, lot);
            return false;
        }

        // Enforce maximum pending limit
        int pendingCount = ArraySize(m_pendingAsyncTrades);
        if(pendingCount >= m_maxPendingAsync)
        {
            PrintFormat("[ASYNC-TRADE-REJECTED] %s | reason=MaxPendingReached count=%d max=%d",
                        symbol, pendingCount, m_maxPendingAsync);
            return false;
        }

        return true;
    }

// Build + submit the async request and record it as pending
    bool SubmitAsync(const ENUM_ORDER_TYPE orderType,
                     const string symbol,
                     const double normalizedLot,
                     const double executionPrice,
                     const double sl,
                     const double tp,
                     const ulong magic,
                     const int timeoutMs,
                     const uint slippage,
                     const ENUM_ORDER_TYPE_FILLING orderFillMode)
    {
        // Build the trade request
        MqlTradeRequest request = {};
        request.action    = TRADE_ACTION_DEAL;
        request.symbol    = symbol;
        request.volume    = normalizedLot;
        request.type      = orderType;
        request.price     = executionPrice;
        request.sl        = sl;
        request.tp        = tp;
        request.magic     = magic;
        request.comment   = "AsyncTrade";
        request.deviation = slippage;
        request.type_filling = orderFillMode;

        // FIX: Generate idempotency key for deduplication
        string idempotencyKey = StringFormat("ASYNC_%s_%s_%.2f_%.5f_%.5f_%.5f_%I64u_%d",
                                             symbol, EnumToString(orderType), normalizedLot, executionPrice, sl, tp, magic, (int)TimeCurrent());

        // Submit via OrderSendAsync
        MqlTradeResult result = {};
        bool sent = OrderSendAsync(request, result);

        if(!sent)
        {
            PrintFormat("[ASYNC-TRADE-FAILED] %s | retcode=%u | comment=%s | err=%d",
                        symbol, result.retcode, result.comment, GetLastError());
            return false;
        }

        // Store in pending array for later confirmation via OnTradeTransaction
        int newSize = ArraySize(m_pendingAsyncTrades) + 1;
        ArrayResize(m_pendingAsyncTrades, newSize);
        int idx = newSize - 1;

        m_pendingAsyncTrades[idx].ticket      = result.order;
        m_pendingAsyncTrades[idx].symbol      = symbol;
        m_pendingAsyncTrades[idx].orderType   = orderType;
        m_pendingAsyncTrades[idx].lot         = normalizedLot;
        m_pendingAsyncTrades[idx].price       = executionPrice;
        m_pendingAsyncTrades[idx].sl          = sl;
        m_pendingAsyncTrades[idx].tp          = tp;
        m_pendingAsyncTrades[idx].magic       = magic;
        m_pendingAsyncTrades[idx].submitTime  = TimeCurrent();
        m_pendingAsyncTrades[idx].timeoutMs   = timeoutMs;
        m_pendingAsyncTrades[idx].confirmed   = false;
        m_pendingAsyncTrades[idx].expired     = false;
        m_pendingAsyncTrades[idx].idempotencyKey = idempotencyKey;
        m_pendingAsyncTrades[idx].retryCount = 0;
        m_pendingAsyncTrades[idx].persisted = false;
        m_pendingAsyncTrades[idx].persistedTime = 0;

        PrintFormat("[ASYNC-TRADE-SENT] Symbol=%s Type=%s Lot=%.2f Price=%.5f Ticket=%I64u Key=%s",
                    symbol, EnumToString(orderType), normalizedLot, executionPrice, result.order, idempotencyKey);

        // FIX: Persist async trade request to CSV for replay on restart
        PersistAsyncTradeRequest(m_pendingAsyncTrades[idx]);

        return true;
    }

// Process trade transaction event (call from OnTradeTransaction)
    void ProcessTradeTransaction(const MqlTradeTransaction &trans,
                                 const MqlTradeRequest &request,
                                 const MqlTradeResult &result,
                                 CExecutionQualityTracker &execQuality)
    {
        // Only process deal-add transactions (completed fills)
        if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
            return;

        int pendingCount = ArraySize(m_pendingAsyncTrades);
        if(pendingCount == 0)
            return;

        ulong dealOrder = (ulong)trans.order;

        // Search for matching pending request by order ticket
        for(int i = pendingCount - 1; i >= 0; i--)
        {
            if(m_pendingAsyncTrades[i].ticket == dealOrder && !m_pendingAsyncTrades[i].confirmed)
            {
                // Mark as confirmed
                m_pendingAsyncTrades[i].confirmed = true;

                // Calculate slippage
                double pointSize = SymbolInfoDouble(m_pendingAsyncTrades[i].symbol, SYMBOL_POINT);
                // Guard against denormalized/zero point size to prevent NaN slippage
                if(pointSize <= 1e-15) pointSize = 1e-15;
                double slippage = 0.0;
                if(pointSize > 0.0 && trans.price > 0.0 && m_pendingAsyncTrades[i].price > 0.0)
                    slippage = MathAbs(trans.price - m_pendingAsyncTrades[i].price) / pointSize;

                PrintFormat("[ASYNC-TRADE-CONFIRMED] Ticket=%I64u Price=%.5f (expected=%.5f slippage=%.1f pts)",
                            m_pendingAsyncTrades[i].ticket,
                            trans.price,
                            m_pendingAsyncTrades[i].price,
                            slippage);

                // Update execution quality metrics
                STradeExecutionReceipt receipt;
                receipt.accepted        = true;
                receipt.orderTicket     = m_pendingAsyncTrades[i].ticket;
                receipt.requestedVolume = m_pendingAsyncTrades[i].lot;
                receipt.filledVolume    = trans.volume;
                receipt.requestedPrice  = m_pendingAsyncTrades[i].price;
                receipt.averagePrice    = trans.price;
                receipt.slippagePoints  = slippage;
                receipt.stopLoss        = m_pendingAsyncTrades[i].sl;
                receipt.takeProfit      = m_pendingAsyncTrades[i].tp;
                receipt.symbol          = m_pendingAsyncTrades[i].symbol;
                receipt.submitTime      = m_pendingAsyncTrades[i].submitTime;
                receipt.note            = "async_confirmed";
                if(m_pendingAsyncTrades[i].submitTime > 0)
                {
                    ulong elapsedMs = (ulong)(TimeCurrent() - m_pendingAsyncTrades[i].submitTime) * 1000;
                    receipt.roundTripMs = elapsedMs;
                }
                execQuality.UpdateExecutionMetrics(receipt);

                // Remove confirmed entry by shifting remaining elements
                for(int j = i; j < ArraySize(m_pendingAsyncTrades) - 1; j++)
                    m_pendingAsyncTrades[j] = m_pendingAsyncTrades[j + 1];
                ArrayResize(m_pendingAsyncTrades, ArraySize(m_pendingAsyncTrades) - 1);

                break;
            }
        }
    }

// Check for timed-out async trades (call from OnTimer)
    void CheckAsyncTimeouts(CExecutionQualityTracker &execQuality)
    {
        int pendingCount = ArraySize(m_pendingAsyncTrades);
        if(pendingCount == 0)
            return;

        datetime checkTime = TimeCurrent();

        for(int i = pendingCount - 1; i >= 0; i--)
        {
            if(m_pendingAsyncTrades[i].confirmed || m_pendingAsyncTrades[i].expired)
                continue;

            // Calculate elapsed time in milliseconds
            long elapsedMs = (long)(checkTime - m_pendingAsyncTrades[i].submitTime) * 1000;

            if(elapsedMs > m_pendingAsyncTrades[i].timeoutMs)
            {
                m_pendingAsyncTrades[i].expired = true;

                PrintFormat("[ASYNC-TRADE-TIMEOUT] Ticket=%I64u expired after %I64dms (limit=%dms)",
                            m_pendingAsyncTrades[i].ticket,
                            elapsedMs,
                            m_pendingAsyncTrades[i].timeoutMs);

                // Update execution metrics for the timeout
                STradeExecutionReceipt receipt;
                receipt.accepted        = false;
                receipt.orderTicket     = m_pendingAsyncTrades[i].ticket;
                receipt.requestedVolume = m_pendingAsyncTrades[i].lot;
                receipt.requestedPrice  = m_pendingAsyncTrades[i].price;
                receipt.stopLoss        = m_pendingAsyncTrades[i].sl;
                receipt.takeProfit      = m_pendingAsyncTrades[i].tp;
                receipt.symbol          = m_pendingAsyncTrades[i].symbol;
                receipt.submitTime      = m_pendingAsyncTrades[i].submitTime;
                receipt.note            = "async_timeout";
                if(m_pendingAsyncTrades[i].submitTime > 0)
                    receipt.roundTripMs = (ulong)elapsedMs;
                execQuality.UpdateExecutionMetrics(receipt);

                // Remove expired entry by shifting remaining elements
                for(int j = i; j < ArraySize(m_pendingAsyncTrades) - 1; j++)
                    m_pendingAsyncTrades[j] = m_pendingAsyncTrades[j + 1];
                ArrayResize(m_pendingAsyncTrades, ArraySize(m_pendingAsyncTrades) - 1);
            }
        }
    }

// Persist async trade request to CSV for replay on restart
    static void PersistAsyncTradeRequest(const SAsyncTradeRequest &asyncTrade)
    {
        string fileName = "async_trades_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".csv";
        // Batch 150: FILE_WRITE alone truncates - every persist erased the whole
        // crash-recovery ledger. Open read+write and append at end instead.
        int handle = FileOpen(fileName, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
        if(handle == INVALID_HANDLE)
        {
            PrintFormat("[ASYNC-PERSIST] ERROR: Cannot open %s for writing", fileName);
            return;
        }
        FileSeek(handle, 0, SEEK_END);

        // Check if file is empty (needs header)
        bool writeHeader = (FileSize(handle) == 0);

        if(writeHeader)
        {
            FileWrite(handle, "ticket,symbol,orderType,lot,price,sl,tp,magic,submitTime,timeoutMs,confirmed,expired,idempotencyKey,retryCount,persisted,persistedTime,comment");
        }

        string line = StringFormat("%I64u,%s,%s,%.2f,%.5f,%.5f,%.5f,%I64u,%d,%d,%d,%d,%s,%d,%d,%d,%s",
                                   asyncTrade.ticket,
                                   asyncTrade.symbol,
                                   EnumToString(asyncTrade.orderType),
                                   asyncTrade.lot,
                                   asyncTrade.price,
                                   asyncTrade.sl,
                                   asyncTrade.tp,
                                   asyncTrade.magic,
                                   (int)asyncTrade.submitTime,
                                   asyncTrade.timeoutMs,
                                   asyncTrade.confirmed ? 1 : 0,
                                   asyncTrade.expired ? 1 : 0,
                                   asyncTrade.idempotencyKey,
                                   asyncTrade.retryCount,
                                   asyncTrade.persisted ? 1 : 0,
                                   (int)asyncTrade.persistedTime,
                                   asyncTrade.comment);

        FileWrite(handle, line);
        FileClose(handle);
    }

// Replay async trade requests from CSV on EA restart
    void ReplayAsyncTradeRequests()
    {
        string fileName = "async_trades_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".csv";
        int handle = FileOpen(fileName, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
        if(handle == INVALID_HANDLE)
        {
            PrintFormat("[ASYNC-REPLAY] No async trade persistence file found: %s", fileName);
            return;
        }

        int replayed = 0;
        string line;
        bool skipHeader = true;

        while(!FileIsEnding(handle))
        {
            line = FileReadString(handle);
            if(StringLen(line) == 0) continue;

            if(skipHeader)
            {
                skipHeader = false;
                continue;
            }

            string fields[];
            int count = StringSplit(line, ',', fields);
            if(count < 17) continue;  // Need all fields

// Parse fields
            ulong ticket = (ulong)StringToInteger(fields[0]);
            string symbol = fields[1];
            ENUM_ORDER_TYPE orderType = CTradeDescriptor::OrderTypeFromString(fields[2]);
            double lot = StringToDouble(fields[3]);
            double price = StringToDouble(fields[4]);
            double sl = StringToDouble(fields[5]);
            double tp = StringToDouble(fields[6]);
            ulong magic = (ulong)StringToInteger(fields[7]);
            datetime submitTime = (datetime)StringToInteger(fields[8]);
            int timeoutMs = (int)StringToInteger(fields[9]);
            bool confirmed = StringToInteger(fields[10]) == 1;
            bool expired = StringToInteger(fields[11]) == 1;
            string idempotencyKey = fields[12];
            int retryCount = (int)StringToInteger(fields[13]);
            bool persisted = StringToInteger(fields[14]) == 1;
            datetime persistedTime = (datetime)StringToInteger(fields[15]);
            string comment = fields[16];

            // Skip already confirmed/expired trades
            if(confirmed || expired)
                continue;

            // Check if we already have this idempotency key in pending array (deduplication)
            bool duplicate = false;
            for(int i = 0; i < ArraySize(m_pendingAsyncTrades); i++)
            {
                if(m_pendingAsyncTrades[i].idempotencyKey == idempotencyKey)
                {
                    duplicate = true;
                    break;
                }
            }

            if(duplicate)
            {
                PrintFormat("[ASYNC-REPLAY] Skipping duplicate idempotency key: %s", idempotencyKey);
                continue;
            }

            // Add to pending array for confirmation on next OnTradeTransaction
            int newSize = ArraySize(m_pendingAsyncTrades) + 1;
            ArrayResize(m_pendingAsyncTrades, newSize);
            int idx = newSize - 1;

            m_pendingAsyncTrades[idx].ticket = ticket;
            m_pendingAsyncTrades[idx].symbol = symbol;
            m_pendingAsyncTrades[idx].orderType = orderType;
            m_pendingAsyncTrades[idx].lot = lot;
            m_pendingAsyncTrades[idx].price = price;
            m_pendingAsyncTrades[idx].sl = sl;
            m_pendingAsyncTrades[idx].tp = tp;
            m_pendingAsyncTrades[idx].magic = magic;
            m_pendingAsyncTrades[idx].submitTime = submitTime;
            m_pendingAsyncTrades[idx].timeoutMs = timeoutMs;
            m_pendingAsyncTrades[idx].confirmed = false;
            m_pendingAsyncTrades[idx].expired = false;
            m_pendingAsyncTrades[idx].idempotencyKey = idempotencyKey;
            m_pendingAsyncTrades[idx].retryCount = retryCount;
            m_pendingAsyncTrades[idx].persisted = true;
            m_pendingAsyncTrades[idx].persistedTime = persistedTime;
            m_pendingAsyncTrades[idx].comment = comment;

            replayed++;
            PrintFormat("[ASYNC-REPLAY] Replayed async trade: %s %s %.2f @ %.5f (key=%s)",
                        symbol, EnumToString(orderType), lot, price, idempotencyKey);
        }

        FileClose(handle);

        if(replayed > 0)
        {
            PrintFormat("[ASYNC-REPLAY] Replayed %d unconfirmed async trade(s) from persistence", replayed);
        }
    }

// Clean up confirmed/expired persisted async trades
    static void CleanupPersistedAsyncTrades()
    {
        string fileName = "async_trades_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".csv";
        int handle = FileOpen(fileName, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
        if(handle == INVALID_HANDLE)
            return;

        // Read all lines
        string lines[];
        string line;
        bool skipHeader = true;
        while(!FileIsEnding(handle))
        {
            line = FileReadString(handle);
            if(StringLen(line) == 0) continue;
            if(skipHeader) { skipHeader = false; continue; }

            string fields[];
            int count = StringSplit(line, ',', fields);
            if(count < 11) continue;

            bool confirmed = StringToInteger(fields[10]) == 1;
            bool expired = StringToInteger(fields[11]) == 1;

            // Keep only unconfirmed, unexpired trades
            if(!confirmed && !expired)
            {
                int newSize = ArraySize(lines) + 1;
                ArrayResize(lines, newSize);
                lines[newSize - 1] = line;
            }
        }
        FileClose(handle);

        // Rewrite file with only active trades
        handle = FileOpen(fileName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
        if(handle == INVALID_HANDLE) return;

        FileWrite(handle, "ticket,symbol,orderType,lot,price,sl,tp,magic,submitTime,timeoutMs,confirmed,expired,idempotencyKey,retryCount,persisted,persistedTime,comment");
        for(int i = ArraySize(lines) - 1; i >= 0; i--)
        {
            FileWrite(handle, lines[i]);
        }
        FileClose(handle);
    }
};

#endif // CORE_TRADING_TRADE_MGR_ASYNC_EXECUTOR_MQH
