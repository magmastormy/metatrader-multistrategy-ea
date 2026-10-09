// Tracks and remediates positions without stop-loss protection
// 3-attempt escalation: standard SL → broker-min SL → forced close
#ifndef CORE_RISK_UNPROTECTED_POSITION_TRACKER_MQH
#define CORE_RISK_UNPROTECTED_POSITION_TRACKER_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/MagicRange.mqh"
#include "UnifiedRiskManager.mqh"
#include "../Trading/TradeManager.mqh"

// Encapsulates detection, tracking, and remediation of positions
// that lack stop-loss protection. Implements a 3-attempt
// escalation protocol before forced closure.
// L5-022 FIX: Pass min/max magic directly to Initialize()
// L5-023 FIX: Context-aware escalation (position size, DD, vol)
class CUnprotectedPositionTracker
{
private:
    ulong  m_tickets[];       // Position tickets being tracked
    int    m_attempts[];      // Remediation attempt count per ticket
    datetime m_lastAttempt;   // Timestamp of last remediation sweep

    CTradeManager*       m_tradeManager;
    CUnifiedRiskManager* m_riskManager;
    int                  m_remediationIntervalSec;
    int                  m_maxRestoreAttempts;

    // L5-023: Context-aware escalation parameters
    double               m_maxPositionSizeForEscalation; // Max position size (lots) before aggressive escalation
    double               m_maxDrawdownForEscalation;     // Max drawdown % before aggressive escalation
    double               m_volatilityThreshold;          // ATR threshold for high volatility

public:
    CUnprotectedPositionTracker()
        : m_tradeManager(NULL),
          m_riskManager(NULL),
          m_lastAttempt(0),
          m_remediationIntervalSec(15),
          m_maxRestoreAttempts(3),
          m_maxPositionSizeForEscalation(10.0),
          m_maxDrawdownForEscalation(10.0),
          m_volatilityThreshold(0.0)
    {
        ArrayResize(m_tickets, 0);
        ArrayResize(m_attempts, 0);
    }

// Initialize with external dependencies
// Batch 168: the magic window is no longer passed in here. The
// previous call site handed the symbol-array length to the
// maxMagicNumber parameter, producing the empty range
// [123456, 13] - so IsEAOwnedMagic was false for every position
// and no-SL remediation never ran. Ownership now resolves through
// CMagicRange, configured once by the orchestrator.
    void Initialize(CTradeManager* tradeMgr, CUnifiedRiskManager* riskMgr,
                    int remediationIntervalSec = 15, int maxRestoreAttempts = 3)
    {
        m_tradeManager  = tradeMgr;
        m_riskManager   = riskMgr;
        m_remediationIntervalSec = MathMax(5, remediationIntervalSec);
        m_maxRestoreAttempts      = MathMax(1, maxRestoreAttempts);
    }

// Set context-aware escalation parameters (L5-023)
    void SetEscalationContext(double maxPositionSizeLots, double maxDrawdownPct, double volatilityATRThreshold)
    {
        m_maxPositionSizeForEscalation = MathMax(0.01, maxPositionSizeLots);
        m_maxDrawdownForEscalation = MathMax(0.0, maxDrawdownPct);
        m_volatilityThreshold = MathMax(0.0, volatilityATRThreshold);
    }

// Check if a magic number falls within this EA's ownership range
// Batch 168: resolves through CMagicRange, the single authority.
    bool IsEAOwnedMagic(long magic) const
    {
        return IsMagicOwned(magic);
    }

// Find tracker index for a ticket (-1 if not found)
    int FindTrackerIndex(const ulong ticket) const
    {
        for(int i = 0; i < ArraySize(m_tickets); i++)
        {
            if(m_tickets[i] == ticket)
                return i;
        }
        return -1;
    }

// Get attempt count for a ticket
    int GetAttempts(const ulong ticket) const
    {
        int idx = FindTrackerIndex(ticket);
        if(idx < 0 || idx >= ArraySize(m_attempts))
            return 0;
        return m_attempts[idx];
    }

// Set attempt count for a ticket (adds entry if new)
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

// Clear a ticket from the tracker
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

// Remove entries for positions that no longer need tracking
    void Cleanup()
    {
        for(int i = ArraySize(m_tickets) - 1; i >= 0; i--)
        {
            ulong ticket = m_tickets[i];
            if(ticket == 0 || !PositionSelectByTicket(ticket) || PositionGetDouble(POSITION_SL) > 0.0)
                ClearTicket(ticket);
        }
    }

// Build fallback stop-loss distance in points
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

// Main remediation sweep — 3-attempt escalation protocol
// Escalation-1: Standard SL at fallback distance
// Escalation-2: Broker minimum distance SL
// Escalation-3: Forced close (position must not exist without SL)
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
            double volume = PositionGetDouble(POSITION_VOLUME);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
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

            // L5-023: Calculate context-aware escalation parameters
            double profitPct = 0.0;
            if(openPrice > 0.0)
            {
                if(posType == POSITION_TYPE_BUY)
                    profitPct = (currentPrice - openPrice) / openPrice * 100.0;
                else
                    profitPct = (openPrice - currentPrice) / openPrice * 100.0;
            }
            
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            int minutesHeld = (int)((nowTime - openTime) / 60);
            
            // Get ATR for volatility-aware SL distance
            double atr = 0.0;
            CIndicatorManager* indMgr = CIndicatorManager::Instance();
            if(indMgr != NULL)
            {
                int atrHandle = indMgr.GetATRHandle(symbol, PERIOD_CURRENT, 14);
                if(atrHandle != INVALID_HANDLE)
                {
                    double atrBuf[];
                    if(CopyBuffer(atrHandle, 0, 0, 1, atrBuf) > 0)
                        atr = atrBuf[0];
                }
            }
            
            double fallbackStopPoints = BuildFallbackStopPoints(symbol, currentPrice);
            
            // L5-023: Adjust fallback distance based on context
            // High volatility = wider SL
            if(atr > 0.0 && atr > m_volatilityThreshold)
            {
                double atrPoints = atr / SymbolInfoDouble(symbol, SYMBOL_POINT);
                fallbackStopPoints = MathMax(fallbackStopPoints, atrPoints * 1.5);
            }
            
            // Large losing position = faster escalation
            bool isLargeLoss = (profitPct < -m_maxDrawdownForEscalation && volume > m_maxPositionSizeForEscalation);
            bool isOldPosition = (minutesHeld > 480); // 8 hours
            
            double fallbackTakeProfitPoints = fallbackStopPoints * 2.0;
            ENUM_ORDER_TYPE syntheticOrderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            double newSL = m_tradeManager.CalculateStopLoss(symbol, syntheticOrderType, currentPrice, fallbackStopPoints);
            double newTP = m_tradeManager.CalculateTakeProfit(symbol, syntheticOrderType, currentPrice, fallbackTakeProfitPoints);

            // --- Attempt 1: Standard SL at fallback distance ---
            // L5-023: For large losing positions, skip to faster escalation
            bool skipStandardSL = isLargeLoss || isOldPosition;
            
            if(!skipStandardSL && newSL > 0.0 && m_tradeManager.ModifyPosition(ticket, newSL, newTP))
            {
                restoredCount++;
                ClearTicket(ticket);
                PrintFormat("[RISK-UNPROTECTED] Escalation-1: Standard SL applied | ticket=%I64u | SL=%.5f | P&L=%.2f%% | vol=%.2f", 
                            ticket, newSL, profitPct, volume);
                continue;
            }
            else if(skipStandardSL)
            {
                PrintFormat("[RISK-UNPROTECTED] Escalation-1 SKIPPED (context) | ticket=%I64u | P&L=%.2f%% | vol=%.2f | held=%dmin",
                            ticket, profitPct, volume, minutesHeld);
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
                PrintFormat("[RISK-UNPROTECTED] Escalation-2: Broker-min SL applied | ticket=%I64u | SL=%.5f | P&L=%.2f%% | vol=%.2f", 
                            ticket, minSL, profitPct, volume);
                continue;
            }

            // --- Attempt 3: Close the position — no position should exist without SL ---
            int attempts = GetAttempts(ticket) + 1;
            SetAttempts(ticket, attempts);
            restoreFailedCount++;

            // L5-023: Force close for large losses regardless of attempt count
            bool forceClose = isLargeLoss && isOldPosition;
            
            if(forceClose || attempts >= m_maxRestoreAttempts)
            {
                string reason = forceClose ? "SL remediation: large loss, old position" : "SL remediation escalation: all attempts failed";
                if(m_tradeManager.ClosePosition(ticket, reason))
                {
                    forcedClosedCount++;
                    ClearTicket(ticket);
                    PrintFormat("[RISK-UNPROTECTED] Escalation-3: Position closed (%s) | ticket=%I64u | P&L=%.2f%% | vol=%.2f | attempts=%d",
                                forceClose ? "large loss" : "max attempts", ticket, profitPct, volume, attempts);
                }
                else
                {
                    PrintFormat("[RISK-UNPROTECTED] CRITICAL: Cannot add SL or close position | ticket=%I64u", ticket);
                }
            }
            else
            {
                // Not enough attempts yet, but SL failed - continue monitoring
                continue;
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

// Reset all tracking state (for OnInit / OnDeinit)
    void Reset()
    {
        m_lastAttempt = 0;
        ArrayResize(m_tickets, 0);
        ArrayResize(m_attempts, 0);
    }
};

#endif // CORE_RISK_UNPROTECTED_POSITION_TRACKER_MQH
