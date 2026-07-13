//+------------------------------------------------------------------+
//| AsyncTradeManager.mqh                                            |
//| Asynchronous trade execution - OrderSendAsync +                  |
//| OnTradeTransaction confirmation pattern                          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "2.00"
#property strict

#ifndef CORE_ASYNC_TRADE_MANAGER_MQH
#define CORE_ASYNC_TRADE_MANAGER_MQH

#include <Trade/Trade.mqh>
#include <Trade/PositionInfo.mqh>
#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "TradeTypes.mqh"

#define DEFAULT_ASYNC_TIMEOUT_MS 5000
#define MAX_PENDING_ASYNC_TRADES 50

class CAsyncTradeManager
{
private:
    CTrade m_trade;
    CPositionInfo m_positionInfo;

    SAsyncTradeRequest m_pendingAsyncTrades[];
    int m_maxPendingAsync;
    bool m_asyncModeEnabled;

    // Statistics
    int m_totalAsyncSubmitted;
    int m_totalAsyncConfirmed;
    int m_totalAsyncTimedOut;
    int m_totalAsyncRejected;

    // Callbacks
    CTradeValidator* m_validator;
    CPositionManager* m_positionManager;

public:
    CAsyncTradeManager() : m_trade(), m_positionInfo(), m_maxPendingAsync(MAX_PENDING_ASYNC_TRADES),
                           m_asyncModeEnabled(false), m_totalAsyncSubmitted(0), m_totalAsyncConfirmed(0),
                           m_totalAsyncTimedOut(0), m_totalAsyncRejected(0), m_validator(NULL), m_positionManager(NULL)
    {
        ArrayResize(m_pendingAsyncTrades, m_maxPendingAsync);
    }

    ~CAsyncTradeManager() {}

    void SetDependencies(CTradeValidator* validator, CPositionManager* positionManager)
    {
        m_validator = validator;
        m_positionManager = positionManager;
    }

    void EnableAsyncMode(bool enable) { m_asyncModeEnabled = enable; }
    bool IsAsyncModeEnabled() const { return m_asyncModeEnabled; }
    void SetMaxPendingAsync(int max) { m_maxPendingAsync = max; ArrayResize(m_pendingAsyncTrades, max); }

    // Submit trade asynchronously
    bool SendTradeAsync(const string symbol, const ENUM_ORDER_TYPE orderType,
                       const double lot, const double price,
                       const double sl, const double tp,
                       const ulong magic, const string comment = "",
                       int timeoutMs = DEFAULT_ASYNC_TIMEOUT_MS);

    // Process trade transaction event (call from EA's OnTradeTransaction)
    void ProcessTradeTransaction(const MqlTradeTransaction &trans,
                                const MqlTradeRequest &request,
                                const MqlTradeResult &result);

    // Check for timed-out async trades (call from OnTimer)
    void CheckAsyncTimeouts();

    // Get pending count
    int GetPendingCount() const;

    // Get statistics
    void GetStatistics(int &submitted, int &confirmed, int &timedOut, int &rejected) const
    {
        submitted = m_totalAsyncSubmitted;
        confirmed = m_totalAsyncConfirmed;
        timedOut = m_totalAsyncTimedOut;
        rejected = m_totalAsyncRejected;
    }

    // Find pending trade by order ticket
    int FindPendingTrade(ulong orderTicket) const;

    // Remove confirmed/expired trades from pending
    void CleanupPendingTrades();

private:
    // Internal helpers
    int AddPendingTrade(const SAsyncTradeRequest &trade);
    void RemovePendingTrade(int index);
    bool MatchTransactionToTrade(const MqlTradeTransaction &trans, const MqlTradeRequest &request,
                                 const MqlTradeResult &result, int &index);
    void HandleOrderConfirmation(const SAsyncTradeRequest &trade, const MqlTradeTransaction &trans,
                                 const MqlTradeResult &result);
    void HandleOrderRejection(const SAsyncTradeRequest &trade, const MqlTradeResult &result);
};

#endif // CORE_ASYNC_TRADE_MANAGER_MQH