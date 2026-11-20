// OrderSendAsync submission, confirmation, timeout and persistence
// CTradeManager holds this class BY VALUE and forwards the original public signatures;
// it owns m_pendingAsyncTrades[], m_maxPendingAsync and m_asyncModeEnabled.
// The split sits at SendTradeAsync: guards needing only async state live here, while
// CTradeManager resolves volume/price/preflight and hands the values to SubmitAsync().
// Execution-quality accounting runs on the caller's CExecutionQualityTracker, passed in by reference.
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property strict

#ifndef CORE_TRADING_TRADE_MGR_ASYNC_EXECUTOR_MQH
#define CORE_TRADING_TRADE_MGR_ASYNC_EXECUTOR_MQH

#include "TradeTypes.mqh"
#include "TradeDescriptor.mqh"
#include "ExecutionQualityTracker.mqh"

#define ASYNC_RECONCILE_MAX_ATTEMPTS 20

class CTradeMgrAsyncExecutor
{
private:
    SAsyncTradeRequest m_pendingAsyncTrades[];  // Dynamic array of pending async confirmations
    SAsyncTradeRequest m_quarantineTrades[];    // Quarantine list for unresolved orders awaiting broker history
    int                m_maxPendingAsync;       // Maximum pending async trades (default 10)
    bool               m_asyncModeEnabled;      // Whether async mode is active
    bool               m_asyncReplayComplete;
    ulong              m_requestSequence;

    string BuildRequestId(const ulong magic)
    {
        m_requestSequence++;
        return StringFormat("%I64d_%I64u_%I64d_%d_%u_%I64u",
                            AccountInfoInteger(ACCOUNT_LOGIN), magic, ChartID(),
                            (int)TimeCurrent(), GetTickCount(), m_requestSequence);
    }

public:
    CTradeMgrAsyncExecutor() : m_maxPendingAsync(10),
                               m_asyncModeEnabled(false),
                               m_asyncReplayComplete(false),
                               m_requestSequence(0)
    {
        ArrayResize(m_pendingAsyncTrades, 0);
        ArrayResize(m_quarantineTrades, 0);
    }

    bool IsAsyncModeEnabled() const { return m_asyncModeEnabled; }
    void SetAsyncModeEnabled(const bool enabled) { m_asyncModeEnabled = enabled; }
    void FreePending() { ArrayFree(m_pendingAsyncTrades); ArrayFree(m_quarantineTrades); }

    int GetPendingAsyncCount() const
    {
        return ArraySize(m_pendingAsyncTrades);
    }

    int GetQuarantineCount() const
    {
        return ArraySize(m_quarantineTrades);
    }

    int GetUnresolvedAsyncRequestCount() const
    {
        return ArraySize(m_pendingAsyncTrades) + ArraySize(m_quarantineTrades);
    }

    int GetAsyncRecoverySnapshot(SAsyncTradeRequest &requests[], bool &replayComplete) const
    {
        int pendingCount = ArraySize(m_pendingAsyncTrades);
        int quarantineCount = ArraySize(m_quarantineTrades);
        int total = pendingCount + quarantineCount;
        if(ArrayResize(requests, total) != total)
        {
            replayComplete = false;
            return -1;
        }

        for(int i = 0; i < pendingCount; i++)
            requests[i] = m_pendingAsyncTrades[i];
        for(int i = 0; i < quarantineCount; i++)
            requests[pendingCount + i] = m_quarantineTrades[i];

        replayComplete = m_asyncReplayComplete;
        return total;
    }

    ulong GetPendingAsyncTicket(int index) const
    {
        if(index < 0 || index >= ArraySize(m_pendingAsyncTrades))
            return 0;
        return m_pendingAsyncTrades[index].ticket;
    }

    ulong GetQuarantineTicket(int index) const
    {
        if(index < 0 || index >= ArraySize(m_quarantineTrades))
            return 0;
        return m_quarantineTrades[index].ticket;
    }

    bool IsDuplicateIdempotencyKey(const string key) const
    {
        for(int i = 0; i < ArraySize(m_pendingAsyncTrades); i++)
        {
            if(m_pendingAsyncTrades[i].idempotencyKey == key)
                return true;
        }
        for(int i = 0; i < ArraySize(m_quarantineTrades); i++)
        {
            if(m_quarantineTrades[i].idempotencyKey == key)
                return true;
        }
        return false;
    }

    bool CheckSendGuards(const string symbol, const double lot)
    {
        if(!m_asyncReplayComplete)
        {
            PrintFormat("[ASYNC-TRADE-REJECTED] %s | reason=AsyncRecoveryNotComplete", symbol);
            return false;
        }

        if(!m_asyncModeEnabled)
        {
            PrintFormat("[ASYNC-TRADE-REJECTED] %s | reason=AsyncModeDisabled", symbol);
            return false;
        }

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

        int trackedCount = ArraySize(m_pendingAsyncTrades) + ArraySize(m_quarantineTrades);
        if(trackedCount >= m_maxPendingAsync)
        {
            PrintFormat("[ASYNC-TRADE-REJECTED] %s | reason=MaxTrackedReached pending=%d quarantined=%d max=%d",
                        symbol, ArraySize(m_pendingAsyncTrades), ArraySize(m_quarantineTrades), m_maxPendingAsync);
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
                     const ENUM_ORDER_TYPE_FILLING orderFillMode,
                     const double riskReservedPct)
    {
        if(!(riskReservedPct > 0.0) || !MathIsValidNumber(riskReservedPct))
        {
            PrintFormat("[ASYNC-TRADE-REJECTED] %s | reason=MissingOrInvalidRiskReservation riskPct=%.17g",
                        symbol, riskReservedPct);
            return false;
        }

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

        string requestId = BuildRequestId(magic);
        string idempotencyKey = requestId;

        if(IsDuplicateIdempotencyKey(idempotencyKey))
        {
            PrintFormat("[ASYNC-TRADE-DUPLICATE] %s | key=%s - send suppressed", symbol, idempotencyKey);
            return false;
        }

        int newSize = ArraySize(m_pendingAsyncTrades) + 1;
        if(ArrayResize(m_pendingAsyncTrades, newSize) != newSize)
        {
            PrintFormat("[ASYNC-TRADE-REJECTED] %s | reason=PendingTrackingAllocationFailed", symbol);
            return false;
        }
        int idx = newSize - 1;
        m_pendingAsyncTrades[idx].requestId = requestId;
        m_pendingAsyncTrades[idx].riskReservedPct = riskReservedPct;
        m_pendingAsyncTrades[idx].journalState = ASYNC_JOURNAL_PREPARED;
        m_pendingAsyncTrades[idx].ticket = 0;
        m_pendingAsyncTrades[idx].symbol = symbol;
        m_pendingAsyncTrades[idx].orderType = orderType;
        m_pendingAsyncTrades[idx].lot = normalizedLot;
        m_pendingAsyncTrades[idx].price = executionPrice;
        m_pendingAsyncTrades[idx].sl = sl;
        m_pendingAsyncTrades[idx].tp = tp;
        m_pendingAsyncTrades[idx].magic = magic;
        m_pendingAsyncTrades[idx].submitTime = TimeCurrent();
        m_pendingAsyncTrades[idx].timeoutMs = timeoutMs;
        m_pendingAsyncTrades[idx].confirmed = false;
        m_pendingAsyncTrades[idx].expired = false;
        m_pendingAsyncTrades[idx].comment = request.comment;
        m_pendingAsyncTrades[idx].idempotencyKey = idempotencyKey;
        m_pendingAsyncTrades[idx].retryCount = 0;
        m_pendingAsyncTrades[idx].persisted = false;
        m_pendingAsyncTrades[idx].persistedTime = 0;
        m_pendingAsyncTrades[idx].filledVolume = 0.0;
        m_pendingAsyncTrades[idx].filledValue = 0.0;

        if(!PersistAsyncTradeRequest(m_pendingAsyncTrades[idx]))
        {
            RemovePendingAt(idx);
            PrintFormat("[ASYNC-TRADE-REJECTED] %s | reason=PreparedRiskReservationNotDurable", symbol);
            return false;
        }
        m_pendingAsyncTrades[idx].persisted = true;

        MqlTradeResult result = {};
        bool sent = OrderSendAsync(request, result);

        if(!sent || (result.retcode != TRADE_RETCODE_PLACED &&
                     result.retcode != TRADE_RETCODE_DONE &&
                     result.retcode != TRADE_RETCODE_DONE_PARTIAL))
        {
            PrintFormat("[ASYNC-TRADE-FAILED] %s | retcode=%u | comment=%s | err=%d",
                        symbol, result.retcode, result.comment, GetLastError());
            m_pendingAsyncTrades[idx].journalState = ASYNC_JOURNAL_FAILED;
            m_pendingAsyncTrades[idx].expired = true;
            m_pendingAsyncTrades[idx].persistedTime = TimeCurrent();
            if(!PersistAsyncTradeRequest(m_pendingAsyncTrades[idx]))
            {
                m_asyncReplayComplete = false;
                PrintFormat("[ASYNC-TRADE-JOURNAL-CRITICAL] request=%s | failed-send tombstone not durable; PREPARED reservation remains unresolved",
                            m_pendingAsyncTrades[idx].requestId);
            }
            RemovePendingAt(idx);
            return false;
        }

        m_pendingAsyncTrades[idx].ticket      = result.order;
        m_pendingAsyncTrades[idx].journalState = ASYNC_JOURNAL_PENDING;
        m_pendingAsyncTrades[idx].persistedTime = TimeCurrent();
        if(!PersistAsyncTradeRequest(m_pendingAsyncTrades[idx]))
        {
            m_asyncReplayComplete = false;
            PrintFormat("[ASYNC-TRADE-JOURNAL-CRITICAL] request=%s ticket=%I64u | accepted ticket not durable; PREPARED reservation remains unresolved",
                        m_pendingAsyncTrades[idx].requestId, result.order);
        }

        PrintFormat("[ASYNC-TRADE-SENT] Symbol=%s Type=%s Lot=%.2f Price=%.5f Ticket=%I64u Key=%s",
                    symbol, EnumToString(orderType), normalizedLot, executionPrice, result.order, idempotencyKey);

        return true;
    }

// Process trade transaction event (call from OnTradeTransaction)
    void ProcessTradeTransaction(const MqlTradeTransaction &trans,
                                 const MqlTradeRequest &request,
                                 const MqlTradeResult &result,
                                 CExecutionQualityTracker &execQuality)
    {
        if(!m_asyncReplayComplete)
            return;
        if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
            return;

        if(trans.deal == 0 || !HistoryDealSelect(trans.deal))
            return;

        ulong dealOrder = (ulong)HistoryDealGetInteger(trans.deal, DEAL_ORDER);
        ulong dealMagic = (ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
        string dealSymbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
        if(dealOrder != trans.order || dealSymbol == "")
            return;

        int pendingCount = ArraySize(m_pendingAsyncTrades);
        if(pendingCount == 0)
            return;

        // Matched by ORDER ticket: SubmitAsync stored result.order, trans.order carries it.
        for(int i = pendingCount - 1; i >= 0; i--)
        {
            if(m_pendingAsyncTrades[i].ticket == dealOrder &&
               m_pendingAsyncTrades[i].magic == dealMagic &&
               m_pendingAsyncTrades[i].symbol == dealSymbol &&
               !m_pendingAsyncTrades[i].confirmed)
            {
                m_pendingAsyncTrades[i].filledVolume += trans.volume;
                m_pendingAsyncTrades[i].filledValue  += trans.price * trans.volume;

                double filled = m_pendingAsyncTrades[i].filledVolume;
                double requested = m_pendingAsyncTrades[i].lot;
                if(filled + 1e-8 < requested)
                {
                    m_pendingAsyncTrades[i].persistedTime = TimeCurrent();
                    if(!PersistAsyncTradeRequest(m_pendingAsyncTrades[i]))
                    {
                        m_asyncReplayComplete = false;
                        PrintFormat("[ASYNC-TRADE-JOURNAL-CRITICAL] request=%s | partial fill update not durable",
                                    m_pendingAsyncTrades[i].requestId);
                    }
                    PrintFormat("[ASYNC-TRADE-PARTIAL] Ticket=%I64u filled=%.4f of %.4f - awaiting remainder or timeout",
                                m_pendingAsyncTrades[i].ticket, filled, requested);
                    break;
                }

                m_pendingAsyncTrades[i].confirmed = true;
                m_pendingAsyncTrades[i].journalState = ASYNC_JOURNAL_RESOLVED;
                m_pendingAsyncTrades[i].persistedTime = TimeCurrent();
                if(!PersistAsyncTradeRequest(m_pendingAsyncTrades[i]))
                {
                    m_asyncReplayComplete = false;
                    PrintFormat("[ASYNC-TRADE-JOURNAL-CRITICAL] request=%s | resolved fill tombstone not durable",
                                m_pendingAsyncTrades[i].requestId);
                }
                double averagePrice = m_pendingAsyncTrades[i].filledValue / filled;

                double pointSize = SymbolInfoDouble(m_pendingAsyncTrades[i].symbol, SYMBOL_POINT);
                // Point size is the slippage divisor: clamp it so bad symbol data cannot give NaN.
                if(pointSize <= 1e-15) pointSize = 1e-15;
                double slippage = 0.0;
                if(pointSize > 0.0 && averagePrice > 0.0 && m_pendingAsyncTrades[i].price > 0.0)
                    slippage = MathAbs(averagePrice - m_pendingAsyncTrades[i].price) / pointSize;

                PrintFormat("[ASYNC-TRADE-CONFIRMED] Ticket=%I64u Price=%.5f (expected=%.5f slippage=%.1f pts)",
                            m_pendingAsyncTrades[i].ticket,
                            averagePrice,
                            m_pendingAsyncTrades[i].price,
                            slippage);

                STradeExecutionReceipt receipt;
                receipt.accepted        = true;
                receipt.orderTicket     = m_pendingAsyncTrades[i].ticket;
                receipt.requestedVolume = requested;
                receipt.filledVolume    = filled;
                receipt.requestedPrice  = m_pendingAsyncTrades[i].price;
                receipt.averagePrice    = averagePrice;
                receipt.slippagePoints  = slippage;
                receipt.stopLoss        = m_pendingAsyncTrades[i].sl;
                receipt.takeProfit      = m_pendingAsyncTrades[i].tp;
                receipt.symbol          = m_pendingAsyncTrades[i].symbol;
                receipt.submitTime      = m_pendingAsyncTrades[i].submitTime;
                receipt.note            = m_pendingAsyncTrades[i].expired ? "async_late_fill" : "async_confirmed";
                if(m_pendingAsyncTrades[i].submitTime > 0)
                {
                    ulong elapsedMs = (ulong)(TimeCurrent() - m_pendingAsyncTrades[i].submitTime) * 1000;
                    receipt.roundTripMs = elapsedMs;
                }
                execQuality.UpdateExecutionMetrics(receipt);
                RemovePendingAt(i);

                break;
            }
        }
    }

// Check for timed-out async trades (call from OnTimer)
    void CheckAsyncTimeouts(CExecutionQualityTracker &execQuality)
    {
        if(!m_asyncReplayComplete)
            return;
        datetime checkTime = TimeCurrent();

        for(int i = ArraySize(m_pendingAsyncTrades) - 1; i >= 0; i--)
        {
            if(m_pendingAsyncTrades[i].confirmed)
                continue;

            if(!m_pendingAsyncTrades[i].expired)
            {
                long elapsedMs = (long)(checkTime - m_pendingAsyncTrades[i].submitTime) * 1000;
                if(elapsedMs <= m_pendingAsyncTrades[i].timeoutMs)
                    continue;

                m_pendingAsyncTrades[i].expired = true;
                PrintFormat("[ASYNC-TRADE-TIMEOUT] Ticket=%I64u expired after %I64dms (limit=%dms) - reconciling with broker",
                            m_pendingAsyncTrades[i].ticket,
                            elapsedMs,
                            m_pendingAsyncTrades[i].timeoutMs);
            }

            if(SettleExpiredRequest(i, execQuality))
                RemovePendingAt(i);
        }

        // Re-check quarantined orders against broker history every timer tick so a late
        // fill is still reconciled instead of escaping tracking.
        CheckQuarantineReconciliation(execQuality);
    }

    // Re-check quarantined orders against broker history on each timer tick.
    // An order stays in quarantine until the broker shows a deal for it; only then is it
    // reconciled and removed, so a later fill can never escape reconciliation.
    void CheckQuarantineReconciliation(CExecutionQualityTracker &execQuality)
    {
        if(ArraySize(m_quarantineTrades) == 0)
            return;

        for(int i = ArraySize(m_quarantineTrades) - 1; i >= 0; i--)
        {
            ulong ticket = m_quarantineTrades[i].ticket;
            string symbol = m_quarantineTrades[i].symbol;
            datetime submitTime = m_quarantineTrades[i].submitTime;
            datetime historyFrom = (submitTime > 3600) ? submitTime - 3600 : 0;
            if(!HistorySelect(historyFrom, TimeCurrent() + 3600))
                continue;

            double filledVolume = 0.0;
            double filledValue  = 0.0;
            bool historyHasFill = false;

            int total = HistoryDealsTotal();
            for(int d = 0; d < total; d++)
            {
                ulong dealTicket = HistoryDealGetTicket(d);
                if(dealTicket == 0)
                    continue;
                long dealOrder = HistoryDealGetInteger(dealTicket, DEAL_ORDER);
                if((ulong)dealOrder != ticket)
                    continue;
                string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
                if(dealSymbol != symbol ||
                   (ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != m_quarantineTrades[i].magic)
                    continue;

                double dealVol   = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
                double dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                if(dealVol <= 0.0 || dealPrice <= 0.0)
                    continue;
                filledVolume   += dealVol;
                filledValue    += dealPrice * dealVol;
                historyHasFill = true;
            }

            if(!HistoryOrderSelect(ticket))
                continue;
            if((ulong)HistoryOrderGetInteger(ticket, ORDER_MAGIC) != m_quarantineTrades[i].magic ||
               HistoryOrderGetString(ticket, ORDER_SYMBOL) != symbol)
                continue;

            ENUM_ORDER_STATE orderState = (ENUM_ORDER_STATE)HistoryOrderGetInteger(ticket, ORDER_STATE);
            if(!IsTerminalOrderState(orderState))
                continue;

            if(!historyHasFill && m_quarantineTrades[i].filledVolume > 0.0)
            {
                filledVolume = m_quarantineTrades[i].filledVolume;
                filledValue  = m_quarantineTrades[i].filledValue;
            }

            m_quarantineTrades[i].filledVolume = filledVolume;
            m_quarantineTrades[i].filledValue  = filledValue;
            m_quarantineTrades[i].journalState = ASYNC_JOURNAL_RESOLVED;
            m_quarantineTrades[i].confirmed = (filledVolume > 0.0);
            m_quarantineTrades[i].expired = (filledVolume <= 0.0);
            m_quarantineTrades[i].persistedTime = TimeCurrent();
            if(!PersistAsyncTradeRequest(m_quarantineTrades[i]))
            {
                m_asyncReplayComplete = false;
                PrintFormat("[ASYNC-TRADE-JOURNAL-CRITICAL] request=%s | quarantine resolution not durable; reservation retained",
                            m_quarantineTrades[i].requestId);
                continue;
            }
            double averagePrice = filledVolume > 0.0 ? filledValue / filledVolume : 0.0;

            PrintFormat("[ASYNC-TRADE-RECONCILED] Ticket=%I64u | %s | terminal fill volume=%.4f of %.4f | avgPrice=%.5f",
                        ticket, symbol, filledVolume, m_quarantineTrades[i].lot, averagePrice);

            STradeExecutionReceipt receipt;
            receipt.accepted        = (filledVolume > 0.0);
            receipt.orderTicket     = ticket;
            receipt.requestedVolume = m_quarantineTrades[i].lot;
            receipt.filledVolume    = filledVolume;
            receipt.averagePrice    = averagePrice;
            receipt.requestedPrice  = m_quarantineTrades[i].price;
            receipt.stopLoss        = m_quarantineTrades[i].sl;
            receipt.takeProfit      = m_quarantineTrades[i].tp;
            receipt.symbol          = symbol;
            receipt.submitTime      = m_quarantineTrades[i].submitTime;
            receipt.note            = (filledVolume > 0.0) ? "async_quarantine_reconciled" : "async_quarantine_zero_fill";
            if(m_quarantineTrades[i].submitTime > 0)
                receipt.roundTripMs = (ulong)(TimeCurrent() - m_quarantineTrades[i].submitTime) * 1000;
            execQuality.UpdateExecutionMetrics(receipt);

            RemoveQuarantineAt(i);
        }
    }

    static bool IsTerminalOrderState(const ENUM_ORDER_STATE state)
    {
        return (state == ORDER_STATE_CANCELED || state == ORDER_STATE_FILLED ||
                state == ORDER_STATE_REJECTED || state == ORDER_STATE_EXPIRED);
    }

    void RemoveQuarantineAt(const int index)
    {
        for(int j = index; j < ArraySize(m_quarantineTrades) - 1; j++)
            m_quarantineTrades[j] = m_quarantineTrades[j + 1];
        ArrayResize(m_quarantineTrades, ArraySize(m_quarantineTrades) - 1);
    }

    // Sum fill volume and value from broker deals filtered by DEAL_ORDER for a given order ticket.
    bool FillVolumeFromDeals(const ulong ticket, const string symbol, const ulong magic,
                             double &filledVolume, double &filledValue)
    {
        filledVolume = 0.0;
        filledValue  = 0.0;
        datetime historyFrom = TimeCurrent() - 3600;
        datetime historyTo   = TimeCurrent() + 3600;
        if(!HistorySelect(historyFrom, historyTo))
            return false;

        int total = HistoryDealsTotal();
        for(int d = 0; d < total; d++)
        {
            ulong dealTicket = HistoryDealGetTicket(d);
            if(dealTicket == 0)
                continue;
            long dealOrder = HistoryDealGetInteger(dealTicket, DEAL_ORDER);
            if((ulong)dealOrder != ticket)
                continue;
            string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
            if(dealSymbol != symbol || (ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC) != magic)
                continue;

            double dealVol  = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
            double dealPrice= HistoryDealGetDouble(dealTicket, DEAL_PRICE);
            filledVolume   += dealVol;
            filledValue    += dealPrice * dealVol;
        }
        return filledVolume > 0.0;
    }

    // Returns true once the broker reports a final order state and the receipt has been emitted,
    // or the order has been moved to quarantine (removed from pending either way).
    bool SettleExpiredRequest(const int i, CExecutionQualityTracker &execQuality)
    {
        const ulong ticket = m_pendingAsyncTrades[i].ticket;
        m_pendingAsyncTrades[i].retryCount++;
        datetime submitTime = m_pendingAsyncTrades[i].submitTime;
        datetime historyFrom = (submitTime > 3600) ? submitTime - 3600 : 0;
        if(!HistorySelect(historyFrom, TimeCurrent() + 3600))
            return false;

        // Order still live on the broker: cancel the remainder, then re-test.
        if(ticket > 0 && OrderSelect(ticket))
        {
            if((ulong)OrderGetInteger(ORDER_MAGIC) != m_pendingAsyncTrades[i].magic ||
               OrderGetString(ORDER_SYMBOL) != m_pendingAsyncTrades[i].symbol)
            {
                PrintFormat("[ASYNC-TRADE-RECONCILE] Refusing to cancel foreign/mismatched order %I64u",
                            ticket);
                return false;
            }
            CancelOrderRemainder(m_pendingAsyncTrades[i]);
            if(OrderSelect(ticket))
                return false;   // still live, keep waiting for a fill
        }

        bool inHistory = HistoryOrderSelect(ticket);

        // Not in history yet and still within the retry budget: keep pending, re-check next tick.
        if(!inHistory && m_pendingAsyncTrades[i].retryCount < ASYNC_RECONCILE_MAX_ATTEMPTS)
            return false;

        if(inHistory)
        {
            if((ulong)HistoryOrderGetInteger(ticket, ORDER_MAGIC) != m_pendingAsyncTrades[i].magic ||
               HistoryOrderGetString(ticket, ORDER_SYMBOL) != m_pendingAsyncTrades[i].symbol)
                return false;
            ENUM_ORDER_STATE orderState = (ENUM_ORDER_STATE)HistoryOrderGetInteger(ticket, ORDER_STATE);
            if(!IsTerminalOrderState(orderState))
                return false;
        }

        // Resolve fill volume and average price from broker deals filtered by DEAL_ORDER,
        // not from order-level volumes (a partial fill need not move ORDER_VOLUME_CURRENT).
        double historyFilled = 0.0;
        double historyValue  = 0.0;
        if(inHistory)
            FillVolumeFromDeals(ticket, m_pendingAsyncTrades[i].symbol, m_pendingAsyncTrades[i].magic,
                                historyFilled, historyValue);

        double filled = MathMax(m_pendingAsyncTrades[i].filledVolume, historyFilled);
        double filledValue = (historyFilled >= m_pendingAsyncTrades[i].filledVolume && historyFilled > 0.0)
                             ? historyValue
                             : m_pendingAsyncTrades[i].filledValue;

        bool unreconciled = !inHistory && m_pendingAsyncTrades[i].retryCount >= ASYNC_RECONCILE_MAX_ATTEMPTS;

        if(unreconciled)
        {
            // Do not drop the order: a later fill must still be reconcilable.
            // Move it to quarantine; the timer re-checks quarantine each tick until the broker shows a final state.
            int newSize = ArraySize(m_quarantineTrades) + 1;
            if(ArrayResize(m_quarantineTrades, newSize) != newSize)
            {
                PrintFormat("[ASYNC-TRADE-QUARANTINE-FAILED] Ticket=%I64u | %s | tracking capacity unavailable; pending record retained",
                            ticket, m_pendingAsyncTrades[i].symbol);
                return false;
            }
            int qidx = newSize - 1;
            m_quarantineTrades[qidx] = m_pendingAsyncTrades[i];
            m_quarantineTrades[qidx].filledVolume = filled;
            m_quarantineTrades[qidx].filledValue  = filledValue;
            m_quarantineTrades[qidx].journalState = ASYNC_JOURNAL_QUARANTINED;
            m_quarantineTrades[qidx].persistedTime = TimeCurrent();
            if(!PersistAsyncTradeRequest(m_quarantineTrades[qidx]))
            {
                m_asyncReplayComplete = false;
                PrintFormat("[ASYNC-TRADE-JOURNAL-CRITICAL] request=%s | quarantine transition not durable; reservation remains unresolved",
                            m_quarantineTrades[qidx].requestId);
            }
            PrintFormat("[ASYNC-TRADE-QUARANTINED] Ticket=%I64u | %s | no broker history after %d checks - awaiting broker final state",
                        ticket, m_pendingAsyncTrades[i].symbol, m_pendingAsyncTrades[i].retryCount);
            return true;   // removed from pending; lifecycle continues in quarantine
        }

        m_pendingAsyncTrades[i].filledVolume = filled;
        m_pendingAsyncTrades[i].filledValue = filledValue;
        m_pendingAsyncTrades[i].journalState = ASYNC_JOURNAL_RESOLVED;
        m_pendingAsyncTrades[i].confirmed = (filled > 0.0);
        m_pendingAsyncTrades[i].expired = (filled <= 0.0);
        m_pendingAsyncTrades[i].persistedTime = TimeCurrent();
        if(!PersistAsyncTradeRequest(m_pendingAsyncTrades[i]))
        {
            m_asyncReplayComplete = false;
            PrintFormat("[ASYNC-TRADE-JOURNAL-CRITICAL] request=%s | timeout resolution not durable; reservation retained",
                        m_pendingAsyncTrades[i].requestId);
            return false;
        }

        if(inHistory)
        {
            PrintFormat("[ASYNC-TRADE-RECONCILED] Ticket=%I64u | %s | filled=%.4f of %.4f | avgPrice=%.5f",
                        ticket, m_pendingAsyncTrades[i].symbol, filled, m_pendingAsyncTrades[i].lot,
                        filled > 0.0 ? filledValue / filled : 0.0);
        }

        STradeExecutionReceipt receipt;
        receipt.accepted        = filled > 0.0;
        receipt.orderTicket     = ticket;
        receipt.requestedVolume = m_pendingAsyncTrades[i].lot;
        receipt.filledVolume    = filled;
        receipt.averagePrice    = filled > 0.0 ? filledValue / filled : 0.0;
        receipt.requestedPrice  = m_pendingAsyncTrades[i].price;
        receipt.stopLoss        = m_pendingAsyncTrades[i].sl;
        receipt.takeProfit      = m_pendingAsyncTrades[i].tp;
        receipt.symbol          = m_pendingAsyncTrades[i].symbol;
        receipt.submitTime      = m_pendingAsyncTrades[i].submitTime;
        receipt.note            = filled > 0.0 ? "async_partial_timeout" : "async_timeout";
        if(m_pendingAsyncTrades[i].submitTime > 0)
            receipt.roundTripMs = (ulong)(TimeCurrent() - m_pendingAsyncTrades[i].submitTime) * 1000;
        execQuality.UpdateExecutionMetrics(receipt);
        return true;
    }

    static void CancelOrderRemainder(const SAsyncTradeRequest &asyncTrade)
    {
        if(asyncTrade.ticket == 0 || !OrderSelect(asyncTrade.ticket))
            return;
        if((ulong)OrderGetInteger(ORDER_MAGIC) != asyncTrade.magic ||
           OrderGetString(ORDER_SYMBOL) != asyncTrade.symbol)
        {
            PrintFormat("[ASYNC-TRADE-CANCEL] Refusing foreign/mismatched order %I64u", asyncTrade.ticket);
            return;
        }

        MqlTradeRequest request = {};
        MqlTradeResult result = {};
        request.action = TRADE_ACTION_REMOVE;
        request.order = asyncTrade.ticket;
        request.symbol = asyncTrade.symbol;
        request.magic = asyncTrade.magic;
        if(!OrderSend(request, result) || result.retcode != TRADE_RETCODE_DONE)
            PrintFormat("[ASYNC-TRADE-CANCEL] Ticket=%I64u remainder cancel retcode=%u comment=%s",
                        asyncTrade.ticket, result.retcode, result.comment);
    }

    void RemovePendingAt(const int index)
    {
        for(int j = index; j < ArraySize(m_pendingAsyncTrades) - 1; j++)
            m_pendingAsyncTrades[j] = m_pendingAsyncTrades[j + 1];
        ArrayResize(m_pendingAsyncTrades, ArraySize(m_pendingAsyncTrades) - 1);
    }

// Append one immutable reservation or lifecycle event for replay on restart.
    static bool PersistAsyncTradeRequest(const SAsyncTradeRequest &asyncTrade)
    {
        if(MQLInfoInteger(MQL_TESTER))
            return true;

        string fileName = "async_trades_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".csv";
        // FILE_READ|FILE_WRITE + FileSeek(SEEK_END), not FILE_WRITE alone: FILE_WRITE truncates,
        // which would erase the persisted rows a restart replays.
        int handle = FileOpen(fileName, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
        if(handle == INVALID_HANDLE)
        {
            PrintFormat("[ASYNC-PERSIST] ERROR: Cannot open %s for writing", fileName);
            return false;
        }
        FileSeek(handle, 0, SEEK_END);

        bool writeHeader = (FileSize(handle) == 0);

        if(writeHeader)
        {
            FileWrite(handle, "ticket,symbol,orderType,lot,price,sl,tp,magic,submitTime,timeoutMs,confirmed,expired,idempotencyKey,retryCount,persisted,persistedTime,comment,requestId,riskReservedPct,journalState,filledVolume,filledValue");
        }

        string line = StringFormat("%I64u,%s,%s,%.16g,%.16g,%.16g,%.16g,%I64u,%I64d,%d,%d,%d,%s,%d,%d,%I64d,%s,%s,%.16g,%d,%.16g,%.16g",
                                   asyncTrade.ticket,
                                   asyncTrade.symbol,
                                   EnumToString(asyncTrade.orderType),
                                   asyncTrade.lot,
                                   asyncTrade.price,
                                   asyncTrade.sl,
                                   asyncTrade.tp,
                                   asyncTrade.magic,
                                   asyncTrade.submitTime,
                                   asyncTrade.timeoutMs,
                                   asyncTrade.confirmed ? 1 : 0,
                                   asyncTrade.expired ? 1 : 0,
                                   asyncTrade.idempotencyKey,
                                   asyncTrade.retryCount,
                                   asyncTrade.persisted ? 1 : 0,
                                   asyncTrade.persistedTime,
                                   asyncTrade.comment,
                                   asyncTrade.requestId,
                                   asyncTrade.riskReservedPct,
                                   (int)asyncTrade.journalState,
                                   asyncTrade.filledVolume,
                                   asyncTrade.filledValue);

        uint bytesWritten = FileWrite(handle, line);
        FileFlush(handle);
        FileClose(handle);
        return bytesWritten > 0;
    }

// Replay async trade requests from CSV on EA restart
    void ReplayAsyncTradeRequests(const long magicBase, const long magicRangeMax)
    {
        if(m_asyncReplayComplete)
            return;

        m_asyncReplayComplete = false;
        if(MQLInfoInteger(MQL_TESTER))
        {
            m_asyncReplayComplete = true;
            return;
        }

        if(magicBase <= 0)
        {
            PrintFormat("[ASYNC-REPLAY] Invalid magic base=%I64d; asynchronous sending remains blocked", magicBase);
            return;
        }

        long effectiveMagicMax = magicRangeMax;
        if(effectiveMagicMax < magicBase)
            effectiveMagicMax = magicBase;

        string fileName = "async_trades_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".csv";
        if(!FileIsExist(fileName, FILE_COMMON))
        {
            m_asyncReplayComplete = true;
            PrintFormat("[ASYNC-REPLAY] No journal exists yet: %s", fileName);
            return;
        }

        int handle = FileOpen(fileName, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
        if(handle == INVALID_HANDLE)
        {
            PrintFormat("[ASYNC-REPLAY] Cannot read existing journal %s; asynchronous sending remains blocked", fileName);
            return;
        }

        SAsyncTradeRequest latestRequests[];
        int latestCount = 0;
        bool replayValid = true;
        bool sawHeader = false;
        string line;

        while(!FileIsEnding(handle))
        {
            line = FileReadString(handle);
            if(StringLen(line) == 0) continue;

            if(!sawHeader)
            {
                if(StringFind(line, "ticket,symbol,orderType") != 0)
                {
                    PrintFormat("[ASYNC-REPLAY] Invalid journal header; asynchronous sending remains blocked: %s", line);
                    replayValid = false;
                    break;
                }
                sawHeader = true;
                continue;
            }

            string fields[];
            int count = StringSplit(line, ',', fields);
            if(count < 8)
            {
                PrintFormat("[ASYNC-REPLAY] Truncated row cannot be scoped safely; asynchronous sending remains blocked: %s", line);
                replayValid = false;
                continue;
            }

            long parsedMagic = StringToInteger(fields[7]);
            if(parsedMagic <= 0 || IntegerToString(parsedMagic) != fields[7])
            {
                PrintFormat("[ASYNC-REPLAY] Invalid magic field; asynchronous sending remains blocked: %s", line);
                replayValid = false;
                continue;
            }
            if(parsedMagic < magicBase || parsedMagic > effectiveMagicMax)
                continue;

            if(count < 17 || (count > 17 && count < 22))
            {
                PrintFormat("[ASYNC-REPLAY] Truncated in-scope row; asynchronous sending remains blocked: %s", line);
                replayValid = false;
                continue;
            }

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
            string requestId = idempotencyKey;
            double riskReservedPct = 0.0;
            ENUM_ASYNC_JOURNAL_STATE journalState = ASYNC_JOURNAL_PENDING;
            double filledVolume = 0.0;
            double filledValue = 0.0;

            if(count >= 22)
            {
                requestId = fields[17];
                riskReservedPct = StringToDouble(fields[18]);
                long stateValue = StringToInteger(fields[19]);
                if(stateValue < ASYNC_JOURNAL_PREPARED || stateValue > ASYNC_JOURNAL_RESOLVED ||
                   !MathIsValidNumber(riskReservedPct) || riskReservedPct < 0.0 || requestId == "")
                {
                    PrintFormat("[ASYNC-REPLAY] Invalid lifecycle row; asynchronous sending remains blocked: %s", line);
                    replayValid = false;
                    continue;
                }
                journalState = (ENUM_ASYNC_JOURNAL_STATE)stateValue;
                filledVolume = StringToDouble(fields[20]);
                filledValue = StringToDouble(fields[21]);
                if(!MathIsValidNumber(filledVolume) || filledVolume < 0.0 ||
                   !MathIsValidNumber(filledValue) || filledValue < 0.0)
                {
                    PrintFormat("[ASYNC-REPLAY] Invalid fill totals; asynchronous sending remains blocked: %s", line);
                    replayValid = false;
                    continue;
                }
            }
            else if(requestId == "")
            {
                PrintFormat("[ASYNC-REPLAY] Legacy row has no stable idempotency key; asynchronous sending remains blocked: %s", line);
                replayValid = false;
                continue;
            }

            if(count == 17 && confirmed)
                journalState = ASYNC_JOURNAL_RESOLVED;

            SAsyncTradeRequest recovered;
            recovered.requestId = requestId;
            recovered.riskReservedPct = riskReservedPct;
            recovered.journalState = journalState;
            recovered.ticket = ticket;
            recovered.symbol = symbol;
            recovered.orderType = orderType;
            recovered.lot = lot;
            recovered.price = price;
            recovered.sl = sl;
            recovered.tp = tp;
            recovered.magic = (ulong)parsedMagic;
            recovered.submitTime = submitTime;
            recovered.timeoutMs = timeoutMs;
            recovered.confirmed = confirmed;
            recovered.expired = expired;
            recovered.idempotencyKey = idempotencyKey;
            recovered.retryCount = retryCount;
            recovered.persisted = persisted;
            recovered.persistedTime = persistedTime;
            recovered.comment = comment;
            recovered.filledVolume = filledVolume;
            recovered.filledValue = filledValue;

            int existing = -1;
            for(int i = 0; i < latestCount; i++)
            {
                if(latestRequests[i].requestId == requestId)
                {
                    existing = i;
                    break;
                }
            }

            if(existing >= 0)
            {
                latestRequests[existing] = recovered;
            }
            else
            {
                if(ArrayResize(latestRequests, latestCount + 1) != latestCount + 1)
                {
                    Print("[ASYNC-REPLAY] Request map allocation failed; asynchronous sending remains blocked");
                    replayValid = false;
                    break;
                }
                latestRequests[latestCount++] = recovered;
            }
        }

        FileClose(handle);
        if(!sawHeader)
        {
            PrintFormat("[ASYNC-REPLAY] Journal has no readable header: %s", fileName);
            replayValid = false;
        }

        int replayed = 0;
        for(int i = 0; i < latestCount; i++)
        {
            SAsyncTradeRequest recovered = latestRequests[i];
            if(recovered.journalState == ASYNC_JOURNAL_FAILED ||
               recovered.journalState == ASYNC_JOURNAL_RESOLVED ||
               recovered.confirmed)
               continue;

            if(recovered.journalState != ASYNC_JOURNAL_PREPARED &&
               recovered.journalState != ASYNC_JOURNAL_PENDING &&
               recovered.journalState != ASYNC_JOURNAL_QUARANTINED)
            {
                replayValid = false;
                continue;
            }

            recovered.persisted = true;
            if(recovered.journalState == ASYNC_JOURNAL_QUARANTINED)
            {
                int qidx = ArraySize(m_quarantineTrades);
                if(ArrayResize(m_quarantineTrades, qidx + 1) != qidx + 1)
                {
                    replayValid = false;
                    break;
                }
                m_quarantineTrades[qidx] = recovered;
            }
            else
            {
                int pidx = ArraySize(m_pendingAsyncTrades);
                if(ArrayResize(m_pendingAsyncTrades, pidx + 1) != pidx + 1)
                {
                    replayValid = false;
                    break;
                }
                m_pendingAsyncTrades[pidx] = recovered;
            }
            replayed++;
        }

        m_asyncReplayComplete = replayValid;
        PrintFormat("[ASYNC-REPLAY] Recovered %d unresolved in-scope request(s) | complete=%s | magic=%I64d..%I64d",
                    replayed, m_asyncReplayComplete ? "true" : "false", magicBase, effectiveMagicMax);
    }

};

#endif // CORE_TRADING_TRADE_MGR_ASYNC_EXECUTOR_MQH
