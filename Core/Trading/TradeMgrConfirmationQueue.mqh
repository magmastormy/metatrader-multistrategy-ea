// Deferred execution-confirmation queue for CTradeManager
// Extracted from Core/Trading/TradeManager.mqh (God-Object split).
// This module OWNS the non-blocking fill-confirmation queue that
// used to live inside CTradeManager as
// m_pendingConfirmations[MAX_PENDING_CONFIRMATIONS] /
// m_pendingConfirmationCount:
// - Enqueue()                  (was the deferred branch of
// ConfirmExecutionReceipt)
// - CheckPendingConfirmations()(the tick-loop resolver)
// - Clear()                    (destructor / Deinit reset loop)
// STATE OWNERSHIP: CTradeManager holds this class BY VALUE and
// keeps thin forwarders with the original signatures.
// NO BACK-POINTER: the queue never needs to reach back into
// CTradeManager - it only touches MT5 history APIs.
// SPendingConfirmation + MAX_PENDING_CONFIRMATIONS are declared
// here (top-level, exactly as they were in TradeManager.mqh) so
// that every existing reference keeps resolving unchanged. Note
// Core/Orchestration/TradeExecutor.mqh has its own CLASS-NESTED
// struct of the same name; that one is unaffected.
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property strict

#ifndef CORE_TRADING_TRADE_MGR_CONFIRMATION_QUEUE_MQH
#define CORE_TRADING_TRADE_MGR_CONFIRMATION_QUEUE_MQH

#define MAX_PENDING_CONFIRMATIONS 20

#include "../Utils/MagicRange.mqh"

// Pending confirmation tracking for non-blocking execution
struct SPendingConfirmation
{
    ulong    orderTicket;
    string   symbol;
    double   expectedPrice;
    datetime sentAt;
    int      checkAttempts;
    bool     isActive;
};

// Trade Manager Confirmation Queue
// Resolves broker-accepted-but-not-yet-dealt orders lazily, so the
// execution path never blocks on Sleep().
class CTradeMgrConfirmationQueue
{
private:
    SPendingConfirmation m_pendingConfirmations[MAX_PENDING_CONFIRMATIONS];
    int                  m_pendingConfirmationCount;

public:
    CTradeMgrConfirmationQueue() : m_pendingConfirmationCount(0) {}

    int Count() const { return m_pendingConfirmationCount; }

// Queue an order whose deal has not appeared in history yet
    void Enqueue(const string symbolName, const ulong orderTicket, const double expectedPrice)
    {
        // Deal not found yet - defer to pending confirmation for later resolution
        if(orderTicket > 0 && m_pendingConfirmationCount < MAX_PENDING_CONFIRMATIONS)
        {
            int idx = m_pendingConfirmationCount;
            m_pendingConfirmations[idx].orderTicket   = orderTicket;
            m_pendingConfirmations[idx].symbol        = symbolName;
            m_pendingConfirmations[idx].expectedPrice = expectedPrice;
            m_pendingConfirmations[idx].sentAt        = TimeCurrent();
            m_pendingConfirmations[idx].checkAttempts = 0;
            m_pendingConfirmations[idx].isActive      = true;
            m_pendingConfirmationCount++;
            PrintFormat("[EXECUTION-DEFERRED] %s | order=%I64u | added to pending confirmation queue",
                        symbolName, orderTicket);
        }
    }

// Check and resolve pending execution confirmations
// (call from main tick loop)
    void CheckPendingConfirmations()
    {
        if(m_pendingConfirmationCount <= 0)
            return;

        datetime historyFrom = TimeCurrent() - 300;
        datetime historyTo = TimeCurrent() + 60;

        for(int i = m_pendingConfirmationCount - 1; i >= 0; i--)
        {
            if(!m_pendingConfirmations[i].isActive)
                continue;

            m_pendingConfirmations[i].checkAttempts++;

            bool resolved = false;
            if(HistorySelect(historyFrom, historyTo))
            {
                int totalDeals = HistoryDealsTotal();
                for(int d = 0; d < totalDeals; d++)
                {
                    ulong dealTicket = HistoryDealGetTicket(d);
                    if(dealTicket == 0)
                        continue;

                    long dealOrderId = HistoryDealGetInteger(dealTicket, DEAL_ORDER);
                    if((ulong)dealOrderId == m_pendingConfirmations[i].orderTicket)
                    {
                        string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
                        if(dealSymbol == m_pendingConfirmations[i].symbol)
                        {
                            double dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                            double dealVolume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
                            PrintFormat("[EXECUTION-CONFIRMED] %s | order=%I64u | deal=%I64u | price=%.5f | volume=%.2f | attempts=%d",
                                        dealSymbol,
                                        m_pendingConfirmations[i].orderTicket,
                                        dealTicket,
                                        dealPrice,
                                        dealVolume,
                                        m_pendingConfirmations[i].checkAttempts);
                            resolved = true;
                            break;
                        }
                    }
                }
            }

            if(resolved || m_pendingConfirmations[i].checkAttempts >= 5)
            {
                if(!resolved)
                {
                    // Batch 169: this branch used to print and drop, leaving a send that
                    // the broker may well have filled with no deal ever attributed to it -
                    // the order was counted as executed downstream but never reconciled.
                    // On expiry, look for the position the send actually produced so the
                    // outcome is recorded rather than assumed.
                    bool positionExists = HasOpenPositionForSymbol(m_pendingConfirmations[i].symbol);
                    if(positionExists)
                    {
                        PrintFormat("[EXECUTION-CONFIRMED-BY-POSITION] %s | order=%I64u | attempts=%d | no deal found but EA position is OPEN - fill happened, deal history did not attribute it",
                                    m_pendingConfirmations[i].symbol,
                                    m_pendingConfirmations[i].orderTicket,
                                    m_pendingConfirmations[i].checkAttempts);
                        LogCriticalUnreconciled(m_pendingConfirmations[i].symbol,
                                                m_pendingConfirmations[i].orderTicket,
                                                "position_open_no_deal");
                    }
                    else
                    {
                        PrintFormat("[EXECUTION-UNCONFIRMED] %s | order=%I64u | attempts=%d | no deal and no position - order did not execute",
                                    m_pendingConfirmations[i].symbol,
                                    m_pendingConfirmations[i].orderTicket,
                                    m_pendingConfirmations[i].checkAttempts);
                        LogCriticalUnreconciled(m_pendingConfirmations[i].symbol,
                                                m_pendingConfirmations[i].orderTicket,
                                                "no_fill_no_deal");
                    }
                }

                // Remove by shifting
                for(int j = i; j < m_pendingConfirmationCount - 1; j++)
                {
                    m_pendingConfirmations[j] = m_pendingConfirmations[j + 1];
                }
                m_pendingConfirmationCount--;
                m_pendingConfirmations[m_pendingConfirmationCount].isActive = false;
                m_pendingConfirmations[m_pendingConfirmationCount].orderTicket = 0;
                m_pendingConfirmations[m_pendingConfirmationCount].symbol = "";
                m_pendingConfirmations[m_pendingConfirmationCount].expectedPrice = 0.0;
                m_pendingConfirmations[m_pendingConfirmationCount].sentAt = 0;
                m_pendingConfirmations[m_pendingConfirmationCount].checkAttempts = 0;
            }
        }
    }

// Does this EA hold an open position on the symbol?
// Ownership comes from CMagicRange so only this EA's positions
// are considered, never the user's or another EA's.
    bool HasOpenPositionForSymbol(const string symbolName)
    {
        for(int p = PositionsTotal() - 1; p >= 0; p--)
        {
            ulong ticket = PositionGetTicket(p);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(PositionGetString(POSITION_SYMBOL) != symbolName) continue;
            if(!IsMagicOwned(PositionGetInteger(POSITION_MAGIC))) continue;
            return true;
        }
        return false;
    }

// Surface an unreconciled send loudly. This path used to be a
// silent drop; the log signature is what an operator needs to
// act on, and AGENTS.md requires decisions stay explainable.
    void LogCriticalUnreconciled(const string symbolName, const ulong orderTicket, const string outcome)
    {
        PrintFormat("[RISK-UNRECONCILED] CRITICAL | %s | order=%I64u | outcome=%s | verify the basket and any unprotected position on this symbol",
                    symbolName, orderTicket, outcome);
    }

// Clear pending confirmations (destructor / Deinit)
    void Clear()
    {
        m_pendingConfirmationCount = 0;
        for(int i = 0; i < MAX_PENDING_CONFIRMATIONS; i++)
        {
            m_pendingConfirmations[i].orderTicket = 0;
            m_pendingConfirmations[i].symbol = "";
            m_pendingConfirmations[i].expectedPrice = 0.0;
            m_pendingConfirmations[i].sentAt = 0;
            m_pendingConfirmations[i].checkAttempts = 0;
            m_pendingConfirmations[i].isActive = false;
        }
    }
};

#endif // CORE_TRADING_TRADE_MGR_CONFIRMATION_QUEUE_MQH
//+------------------------------------------------------------------+
