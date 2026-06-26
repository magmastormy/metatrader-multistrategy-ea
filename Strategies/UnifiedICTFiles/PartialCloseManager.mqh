//+------------------------------------------------------------------+
//| PartialCloseManager.mqh                                          |
//| Partial Position Management for ICT Strategies                   |
//| Batch 103: 50% close at 1R, BE move, ATR trailing after 2R     |
//| Copyright 2026, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2026, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef __UICT_PARTIAL_CLOSE_MANAGER_MQH__
#define __UICT_PARTIAL_CLOSE_MANAGER_MQH__

#include <Trade\Trade.mqh>
#include "../../IndicatorManager.mqh"

//+------------------------------------------------------------------+
//| Partial Close State per Position                                 |
//+------------------------------------------------------------------+
struct SPartialCloseState
{
    ulong    ticket;
    bool     partialClosed;       // 50% closed at 1R
    bool     beMoved;             // SL moved to breakeven
    bool     trailingActive;      // ATR trailing started (after 2R)
    double   entryPrice;
    double   originalSL;
    double   atrAtEntry;

    SPartialCloseState() : ticket(0), partialClosed(false), beMoved(false),
                           trailingActive(false), entryPrice(0), originalSL(0), atrAtEntry(0) {}
};

//+------------------------------------------------------------------+
//| Partial Close Manager Class                                      |
//+------------------------------------------------------------------+
class CPartialCloseManager
{
private:
    SPartialCloseState  m_states[];
    int                 m_stateCount;
    int                 m_maxStates;
    CTrade              m_trade;
    string              m_symbol;

    int                 FindState(ulong ticket)
    {
        for(int i = 0; i < m_stateCount; i++)
        {
            if(m_states[i].ticket == ticket)
                return i;
        }
        return -1;
    }

    int                 AddState(ulong ticket, double entryPrice, double sl, double atr)
    {
        // Check if already tracked
        int existing = FindState(ticket);
        if(existing >= 0) return existing;

        if(m_stateCount >= m_maxStates)
        {
            // Compact: remove closed positions
            CompactStates();
            if(m_stateCount >= m_maxStates)
                return -1;  // Still full
        }

        ArrayResize(m_states, m_stateCount + 1);
        m_states[m_stateCount].ticket = ticket;
        m_states[m_stateCount].entryPrice = entryPrice;
        m_states[m_stateCount].originalSL = sl;
        m_states[m_stateCount].atrAtEntry = atr;
        m_states[m_stateCount].partialClosed = false;
        m_states[m_stateCount].beMoved = false;
        m_states[m_stateCount].trailingActive = false;
        m_stateCount++;
        return m_stateCount - 1;
    }

    void                CompactStates()
    {
        int writeIdx = 0;
        for(int i = 0; i < m_stateCount; i++)
        {
            // Keep only positions that still exist
            if(PositionSelectByTicket(m_states[i].ticket))
            {
                if(writeIdx != i)
                    m_states[writeIdx] = m_states[i];
                writeIdx++;
            }
        }
        m_stateCount = writeIdx;
        ArrayResize(m_states, m_stateCount);
    }

    double              GetATR(string symbol, ENUM_TIMEFRAMES tf, int period = 14)
    {
        int handle = CIndicatorManager::Instance().GetATRHandle(symbol, tf, period);
        if(handle == INVALID_HANDLE) return 0;
        double buf[];
        ArraySetAsSeries(buf, true);
        double result = 0;
        if(CopyBuffer(handle, 0, 0, 1, buf) > 0)
            result = buf[0];
        return result;
    }

public:
                        CPartialCloseManager();
                       ~CPartialCloseManager();

    bool                Initialize(const string symbol);
    void                RegisterPosition(ulong ticket, double entryPrice, double sl, double atr);
    void                ManagePosition(ulong ticket);
    void                ManageAllPositions();
    void                RemovePosition(ulong ticket);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CPartialCloseManager::CPartialCloseManager() :
    m_stateCount(0),
    m_maxStates(50),
    m_symbol("")
{
    ArrayResize(m_states, 0);
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CPartialCloseManager::~CPartialCloseManager()
{
    ArrayFree(m_states);
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CPartialCloseManager::Initialize(const string symbol)
{
    m_symbol = symbol;
    m_trade.SetExpertMagicNumber(0);  // Use position's own magic
    return true;
}

//+------------------------------------------------------------------+
//| Register Position — call when a new position is opened           |
//+------------------------------------------------------------------+
void CPartialCloseManager::RegisterPosition(ulong ticket, double entryPrice, double sl, double atr)
{
    AddState(ticket, entryPrice, sl, atr);
}

//+------------------------------------------------------------------+
//| Manage Position — call per tick or per bar for a single position |
//+------------------------------------------------------------------+
void CPartialCloseManager::ManagePosition(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return;

    int idx = FindState(ticket);
    if(idx < 0)
    {
        // Auto-register if not tracked
        double entry = PositionGetDouble(POSITION_PRICE_OPEN);
        double sl = PositionGetDouble(POSITION_SL);
        double atr = GetATR(m_symbol, PERIOD_M5, 14);
        if(atr <= 0) atr = entry * 0.005;  // Fallback
        RegisterPosition(ticket, entry, sl, atr);
        idx = FindState(ticket);
        if(idx < 0) return;
    }

    double entry = m_states[idx].entryPrice;
    double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
    double currentSL = PositionGetDouble(POSITION_SL);
    double currentTP = PositionGetDouble(POSITION_TP);
    double volume = PositionGetDouble(POSITION_VOLUME);
    ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

    if(entry <= 0 || m_states[idx].atrAtEntry <= 0) return;

    // Calculate R-multiple (profit in terms of initial risk)
    double risk = MathAbs(entry - m_states[idx].originalSL);
    if(risk <= 0) risk = m_states[idx].atrAtEntry;  // Fallback to ATR
    double profit = 0;
    if(posType == POSITION_TYPE_BUY)
        profit = currentPrice - entry;
    else
        profit = entry - currentPrice;

    double rr = profit / risk;

    // Step 1: 50% close at 1R
    if(rr >= 1.0 && !m_states[idx].partialClosed)
    {
        double minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
        double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
        double closeLot = MathFloor(volume * 0.5 / lotStep) * lotStep;
        if(closeLot < minLot) closeLot = minLot;  // Project memory: use SYMBOL_VOLUME_MIN

        if(closeLot < volume)  // Don't close the entire position
        {
            bool ok = false;
            if(posType == POSITION_TYPE_BUY)
                ok = m_trade.PositionClosePartial(ticket, closeLot);
            else
                ok = m_trade.PositionClosePartial(ticket, closeLot);

            if(ok)
            {
                m_states[idx].partialClosed = true;
                PrintFormat("[PARTIAL-CLOSE] %s | Ticket %d | Closed %.2f lots at 1R (RR=%.2f)",
                           m_symbol, ticket, closeLot, rr);
            }
        }
    }

    // Step 2: Move SL to breakeven after 1R
    if(rr >= 1.0 && !m_states[idx].beMoved)
    {
        double bePrice = entry;
        // Add a small buffer (0.1% of entry) to ensure profitable close
        double buffer = entry * 0.001;
        if(posType == POSITION_TYPE_BUY)
            bePrice = entry + buffer;
        else
            bePrice = entry - buffer;

        bool shouldMove = false;
        if(posType == POSITION_TYPE_BUY && (currentSL < bePrice || currentSL == 0))
            shouldMove = true;
        if(posType == POSITION_TYPE_SELL && (currentSL > bePrice || currentSL == 0))
            shouldMove = true;

        if(shouldMove)
        {
            // Validate stop distance
            double stopsLevel = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
            double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            double minDist = MathMax(stopsLevel * point, entry * 0.001);  // Project Memory: 0.1% min for synthetics

            bool validStop = true;
            if(posType == POSITION_TYPE_BUY && (bePrice > currentPrice - minDist))
                validStop = false;
            if(posType == POSITION_TYPE_SELL && (bePrice < currentPrice + minDist))
                validStop = false;

            if(validStop)
            {
                if(m_trade.PositionModify(ticket, bePrice, currentTP))
                {
                    m_states[idx].beMoved = true;
                    PrintFormat("[PARTIAL-CLOSE] %s | Ticket %d | SL moved to BE %.5f",
                               m_symbol, ticket, bePrice);
                }
            }
        }
    }

    // Step 3: ATR trailing after 2R
    if(rr >= 2.0)
    {
        double atr = GetATR(m_symbol, PERIOD_M5, 14);
        if(atr <= 0) atr = m_states[idx].atrAtEntry;

        double trailingSL = 0;
        if(posType == POSITION_TYPE_BUY)
            trailingSL = currentPrice - 1.5 * atr;
        else
            trailingSL = currentPrice + 1.5 * atr;

        // Only move SL in favorable direction
        bool shouldTrail = false;
        if(posType == POSITION_TYPE_BUY && trailingSL > currentSL)
            shouldTrail = true;
        if(posType == POSITION_TYPE_SELL && (trailingSL < currentSL || currentSL == 0))
            shouldTrail = true;

        if(shouldTrail)
        {
            // Validate stop distance
            double stopsLevel = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
            double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
            double minDist = MathMax(stopsLevel * point, currentPrice * 0.001);

            bool validStop = true;
            if(posType == POSITION_TYPE_BUY && (trailingSL > currentPrice - minDist))
                validStop = false;
            if(posType == POSITION_TYPE_SELL && (trailingSL < currentPrice + minDist))
                validStop = false;

            if(validStop)
            {
                if(m_trade.PositionModify(ticket, trailingSL, currentTP))
                {
                    m_states[idx].trailingActive = true;
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Manage All Positions — iterate all tracked positions             |
//+------------------------------------------------------------------+
void CPartialCloseManager::ManageAllPositions()
{
    for(int i = 0; i < m_stateCount; i++)
    {
        ManagePosition(m_states[i].ticket);
    }

    // Periodic cleanup
    static datetime lastCleanup = 0;
    datetime now = TimeCurrent();
    if(now - lastCleanup >= 300)  // Every 5 minutes
    {
        CompactStates();
        lastCleanup = now;
    }
}

//+------------------------------------------------------------------+
//| Remove Position — call when a position is closed                 |
//+------------------------------------------------------------------+
void CPartialCloseManager::RemovePosition(ulong ticket)
{
    int idx = FindState(ticket);
    if(idx < 0) return;

    // Shift remaining states
    for(int i = idx; i < m_stateCount - 1; i++)
        m_states[i] = m_states[i + 1];
    m_stateCount--;
    ArrayResize(m_states, m_stateCount);
}

#endif // __UICT_PARTIAL_CLOSE_MANAGER_MQH__
