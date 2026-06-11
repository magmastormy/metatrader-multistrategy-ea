//+------------------------------------------------------------------+
//| UnprotectedPositionTracker.mqh                                   |
//| Tracks and remediates positions without stop-loss protection     |
//| 3-attempt escalation: standard SL → broker-min SL → forced close |
//+------------------------------------------------------------------+
#ifndef CORE_RISK_UNPROTECTED_POSITION_TRACKER_MQH
#define CORE_RISK_UNPROTECTED_POSITION_TRACKER_MQH

#include "../Utils/Enums.mqh"
#include "UnifiedRiskManager.mqh"
#include "../Trading/TradeManager.mqh"

//+------------------------------------------------------------------+
//| Magic-number range constants (mirrored from EA globals)          |
//+------------------------------------------------------------------+
#define UNPROT_MAGIC_SYMBOL_MULTIPLIER 100
#define UNPROT_MAGIC_MAX_CLUSTER_CODE  99

//+------------------------------------------------------------------+
//| Unprotected Position Tracker                                     |
//| Encapsulates detection, tracking, and remediation of positions   |
//| that lack stop-loss protection. Implements a 3-attempt           |
//| escalation protocol before forced closure.                       |
//+------------------------------------------------------------------+
class CUnprotectedPositionTracker
{
private:
    ulong  m_tickets[];       // Position tickets being tracked
    int    m_attempts[];      // Remediation attempt count per ticket
    datetime m_lastAttempt;   // Timestamp of last remediation sweep

    CTradeManager*       m_tradeManager;
    CUnifiedRiskManager* m_riskManager;
    int                  m_magicNumber;
    int                  m_symbolCount;        // For IsEAOwnedMagic range calculation
    int                  m_remediationIntervalSec;
    int                  m_maxRestoreAttempts;

public:
    CUnprotectedPositionTracker()
        : m_tradeManager(NULL),
          m_riskManager(NULL),
          m_magicNumber(0),
          m_symbolCount(0),
          m_lastAttempt(0),
          m_remediationIntervalSec(15),
          m_maxRestoreAttempts(3)
    {
        ArrayResize(m_tickets, 0);
        ArrayResize(m_attempts, 0);
    }

    //+------------------------------------------------------------------+
    //| Initialize with external dependencies                           |
    //+------------------------------------------------------------------+
    void Initialize(CTradeManager* tradeMgr, CUnifiedRiskManager* riskMgr,
                    int magicNumber, int symbolCount = 0,
                    int remediationIntervalSec = 15, int maxRestoreAttempts = 3)
    {
        m_tradeManager  = tradeMgr;
        m_riskManager   = riskMgr;
        m_magicNumber   = magicNumber;
        m_symbolCount   = (symbolCount > 0) ? symbolCount : 1;
        m_remediationIntervalSec = MathMax(5, remediationIntervalSec);
        m_maxRestoreAttempts      = MathMax(1, maxRestoreAttempts);
    }

    //+------------------------------------------------------------------+
    //| Update symbol count (call when enterprise managers are rebuilt) |
    //+------------------------------------------------------------------+
    void SetSymbolCount(int symbolCount)
    {
        m_symbolCount = (symbolCount > 0) ? symbolCount : 1;
    }

    //+------------------------------------------------------------------+
    //| Check if a magic number falls within this EA's ownership range   |
    //| Range: [m_magicNumber, m_magicNumber + symbolCount*100 + 99]   |
    //+------------------------------------------------------------------+
    bool IsEAOwnedMagic(long magic) const
    {
        int maxMagic = m_magicNumber + m_symbolCount * UNPROT_MAGIC_SYMBOL_MULTIPLIER + UNPROT_MAGIC_MAX_CLUSTER_CODE;
        return (magic >= m_magicNumber && magic <= maxMagic);
    }

    //+------------------------------------------------------------------+
    //| Find tracker index for a ticket (-1 if not found)               |
    //+------------------------------------------------------------------+
    int FindTrackerIndex(const ulong ticket) const
    {
        for(int i = 0; i < ArraySize(m_tickets); i++)
        {
            if(m_tickets[i] == ticket)
                return i;
        }
        return -1;
    }

    //+------------------------------------------------------------------+
    //| Get attempt count for a ticket                                   |
    //+------------------------------------------------------------------+
    int GetAttempts(const ulong ticket) const
    {
        int idx = FindTrackerIndex(ticket);
        if(idx < 0 || idx >= ArraySize(m_attempts))
            return 0;
        return m_attempts[idx];
    }

    //+------------------------------------------------------------------+
    //| Set attempt count for a ticket (adds entry if new)              |
    //+------------------------------------------------------------------+
    void SetAttempts(const ulong ticket, const int attempts)
    {
        int idx = FindTrackerIndex(ticket);
        if(idx < 0)
        {
            int size = ArraySize(m_tickets);
            const int MAX_TRACKERS = 1000;
            if(size >= MAX_TRACKERS)
            {
                // Remove oldest entry if at limit
                int last = size - 1;
                if(last >= 0)
                {
                    if(0 != last)
                    {
                        m_tickets[0]  = m_tickets[last];
                        m_attempts[0] = m_attempts[last];
                    }
                    ArrayResize(m_tickets, last);
                    ArrayResize(m_attempts, last);
                    size = last;
                }
            }

            ArrayResize(m_tickets, size + 1);
            ArrayResize(m_attempts, size + 1);
            m_tickets[size]  = ticket;
            m_attempts[size] = MathMax(0, attempts);
            return;
        }

        m_attempts[idx] = MathMax(0, attempts);
    }

    //+------------------------------------------------------------------+
    //| Clear a ticket from the tracker                                 |
    //+------------------------------------------------------------------+
    void ClearTicket(const ulong ticket)
    {
        int idx = FindTrackerIndex(ticket);
        if(idx < 0)
            return;

        int last = ArraySize(m_tickets) - 1;
        if(last < 0)
            return;

        m_tickets[idx]  = m_tickets[last];
        m_attempts[idx] = m_attempts[last];
        ArrayResize(m_tickets, last);
        ArrayResize(m_attempts, last);
    }

    //+------------------------------------------------------------------+
    //| Remove entries for positions that no longer need tracking       |
    //+------------------------------------------------------------------+
    void Cleanup()
    {
        for(int i = ArraySize(m_tickets) - 1; i >= 0; i--)
        {
            ulong ticket = m_tickets[i];
            if(ticket == 0 || !PositionSelectByTicket(ticket) || PositionGetDouble(POSITION_SL) > 0.0)
                ClearTicket(ticket);
        }
    }

    //+------------------------------------------------------------------+
    //| Build fallback stop-loss distance in points                     |
    //+------------------------------------------------------------------+
    static double BuildFallbackStopPoints(const string symbol, const double referencePrice)
    {
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(point <= 0.0)
            point = 0.00001;

        int stopLevelPts = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
        double fallbackByStops = MathMax(50.0, (double)stopLevelPts * 2.0);
        double fallbackByPrice = (referencePrice > 0.0) ? ((referencePrice * 0.01) / point) : fallbackByStops;
        return MathMax(fallbackByStops, fallbackByPrice);
    }

    //+------------------------------------------------------------------+
    //| Main remediation sweep — 3-attempt escalation protocol          |
    //| Escalation-1: Standard SL at fallback distance                  |
    //| Escalation-2: Broker minimum distance SL                        |
    //| Escalation-3: Forced close (position must not exist without SL) |
    //+------------------------------------------------------------------+
    void AttemptRemediation()
    {
        if(m_riskManager == NULL || m_tradeManager == NULL)
            return;

        int unprotectedDetected = m_riskManager.GetUnprotectedPositionCount();
        if(unprotectedDetected <= 0)
        {
            Cleanup();
            return;
        }

        datetime nowTime = TimeCurrent();
        if(m_lastAttempt != 0 && (nowTime - m_lastAttempt) < m_remediationIntervalSec)
            return;
        m_lastAttempt = nowTime;
        Cleanup();

        int restoredCount = 0;
        int restoreFailedCount = 0;
        int forcedClosedCount = 0;
        int externalUnprotectedCount = 0;

        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket))
                continue;

            if(PositionGetDouble(POSITION_SL) > 0.0)
            {
                ClearTicket(ticket);
                continue;
            }

            long positionMagic = PositionGetInteger(POSITION_MAGIC);
            if(!IsEAOwnedMagic(positionMagic))
            {
                externalUnprotectedCount++;
                continue;
            }

            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            if(currentPrice <= 0.0)
            {
                currentPrice = (posType == POSITION_TYPE_BUY) ?
                               SymbolInfoDouble(symbol, SYMBOL_BID) :
                               SymbolInfoDouble(symbol, SYMBOL_ASK);
            }

            if(currentPrice <= 0.0)
            {
                restoreFailedCount++;
                SetAttempts(ticket, GetAttempts(ticket) + 1);
                continue;
            }

            double fallbackStopPoints = BuildFallbackStopPoints(symbol, currentPrice);
            double fallbackTakeProfitPoints = fallbackStopPoints * 2.0;
            ENUM_ORDER_TYPE syntheticOrderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            double newSL = m_tradeManager.CalculateStopLoss(symbol, syntheticOrderType, currentPrice, fallbackStopPoints);
            double newTP = m_tradeManager.CalculateTakeProfit(symbol, syntheticOrderType, currentPrice, fallbackTakeProfitPoints);

            // --- Attempt 1: Standard SL at 3x ATR / fallback distance ---
            if(newSL > 0.0 && m_tradeManager.ModifyPosition(ticket, newSL, newTP))
            {
                restoredCount++;
                ClearTicket(ticket);
                PrintFormat("[RISK-UNPROTECTED] Escalation-1: Standard SL applied | ticket=%I64u | SL=%.5f", ticket, newSL);
                continue;
            }

            // --- Attempt 2: Broker minimum distance SL ---
            double symbolPoint = SymbolInfoDouble(symbol, SYMBOL_POINT);
            double stopsLevel = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
            double freezeLevel = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
            double minDistancePoints = MathMax(stopsLevel, freezeLevel) * symbolPoint;
            if(minDistancePoints <= 0.0)
                minDistancePoints = symbolPoint * 10.0; // Absolute minimum

            double minSL = 0.0;
            if(posType == POSITION_TYPE_BUY)
                minSL = currentPrice - minDistancePoints;
            else
                minSL = currentPrice + minDistancePoints;

            if(minSL > 0.0 && m_tradeManager.ModifyPosition(ticket, minSL, newTP))
            {
                restoredCount++;
                ClearTicket(ticket);
                PrintFormat("[RISK-UNPROTECTED] Escalation-2: Broker-min SL applied | ticket=%I64u | SL=%.5f", ticket, minSL);
                continue;
            }

            // --- Attempt 3: Close the position — no position should exist without SL ---
            int attempts = GetAttempts(ticket) + 1;
            SetAttempts(ticket, attempts);
            restoreFailedCount++;

            if(attempts >= m_maxRestoreAttempts)
            {
                if(m_tradeManager.ClosePosition(ticket, "SL remediation escalation: all attempts failed"))
                {
                    forcedClosedCount++;
                    ClearTicket(ticket);
                    PrintFormat("[RISK-UNPROTECTED] Escalation-3: Position closed (no SL possible) | ticket=%I64u", ticket);
                }
                else
                {
                    PrintFormat("[RISK-UNPROTECTED] CRITICAL: Cannot add SL or close position | ticket=%I64u", ticket);
                }
            }
        }

        int remainingUnprotected = m_riskManager.GetUnprotectedPositionCount();
        PrintFormat("[RISK-UNPROTECTED] detected=%d | restored=%d | failed=%d | forced_closed=%d | external=%d | remaining=%d",
                    unprotectedDetected, restoredCount, restoreFailedCount,
                    forcedClosedCount, externalUnprotectedCount, remainingUnprotected);

        if(externalUnprotectedCount > 0)
        {
            PrintFormat("[RISK-UNPROTECTED] External unprotected positions are blocking entries (count=%d)",
                        externalUnprotectedCount);
        }
    }

    //+------------------------------------------------------------------+
    //| Reset all tracking state (for OnInit / OnDeinit)                |
    //+------------------------------------------------------------------+
    void Reset()
    {
        m_lastAttempt = 0;
        ArrayResize(m_tickets, 0);
        ArrayResize(m_attempts, 0);
    }
};

#endif // CORE_RISK_UNPROTECTED_POSITION_TRACKER_MQH
