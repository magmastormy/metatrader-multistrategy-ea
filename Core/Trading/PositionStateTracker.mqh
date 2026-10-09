// Position SL/TP state registry extracted from CTradeManager
// Phase D, batch T3. This module OWNS the "BEAST MODE" position
// state cache that used to live in CTradeManager as
// m_positionStates[100] / m_stateCount:
// - FindPositionState      (internal; self-heals stale entries)
// - RemovePositionState    (internal; called by FindPositionState)
// - UpdatePositionState    (the single ingest point)
// - CleanupPositionStates  (periodic sweep of closed positions)
// - IsModificationNeeded   (the throttle/dedup read path)
// STATE OWNERSHIP: CTradeManager holds this class BY VALUE and
// keeps thin forwarders with the original signatures, so every
// existing call site is unchanged - in particular the five
// UpdatePositionState(...) calls and the two IsModificationNeeded
// (...) calls on the live ModifyPosition / breakeven paths.
// NO BACK-POINTER: IsModificationNeeded needs exactly one
// CTradeManager configuration value (m_minModifyIntervalSec, the
// protective-modify cooldown). It is passed in as a parameter
// rather than read through a back-pointer, keeping this module
// free of any dependency on CTradeManager. The forwarder supplies
// it, so the call sites stay textually identical.
// NESTED STRUCT - DELIBERATE: SPositionState is kept nested and
// private here, exactly as it was nested inside CTradeManager.
// It is NOT promoted to top-level because a DIFFERENT, field-
// incompatible top-level "struct SPositionState" already exists in
// Core/Position/PositionManager.mqh (:21), and that file includes
// Core/Trading/TradeManager.mqh at its line 11 - i.e. before its
// own declaration. Promoting this one would put two unrelated
// structs of the same name in the same translation unit and break
// the build. Nesting keeps the global namespace footprint at zero.
// See the T3 report for details.
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property strict

#ifndef CORE_TRADING_POSITION_STATE_TRACKER_MQH
#define CORE_TRADING_POSITION_STATE_TRACKER_MQH

// Owns the per-ticket last-known SL/TP cache used to suppress
// redundant broker modification requests.
class CPositionStateTracker
{
private:
    // BEAST MODE: State tracking to prevent redundant modifications
    struct SPositionState {
        ulong ticket;
        double lastSL;
        double lastTP;
        datetime lastModified;
    };
    SPositionState m_positionStates[100]; // Track up to 100 positions
    int m_stateCount;

// Check if two double values are approximately equal
// Private copy of the CTradeManager helper of the same name; the
// original stays in CTradeManager (Phase D T1 left it there) and
// is not reachable from this module. Identical epsilon.
    bool DoubleEquals(double a, double b, double epsilon = 0.00001)
    {
        return MathAbs(a - b) < epsilon;
    }

// Internal only - called by FindPositionState. Never forwarded.
    void RemovePositionState(int index)
    {
        if(index < 0 || index >= m_stateCount) return;

        // Shift remaining elements
        for(int i = index; i < m_stateCount - 1; i++)
        {
            m_positionStates[i] = m_positionStates[i + 1];
        }

        // Clear last element
        m_positionStates[m_stateCount - 1].ticket = 0;
        m_positionStates[m_stateCount - 1].lastSL = 0;
        m_positionStates[m_stateCount - 1].lastTP = 0;
        m_positionStates[m_stateCount - 1].lastModified = 0;

        m_stateCount--;
    }

// Find position state by ticket with enhanced validation
// Internal only - both former callers now live in this module.
    int FindPositionState(ulong ticket)
    {
        if(ticket <= 0) return -1;

        for(int i = 0; i < m_stateCount; i++)
        {
            if(m_positionStates[i].ticket == ticket)
            {
                // Validate that the position still exists
                if(!PositionSelectByTicket(ticket))
                {
                    // Position no longer exists, remove from tracking
                    RemovePositionState(i);
                    return -1;
                }
                return i;
            }
        }
        return -1;
    }

public:
    CPositionStateTracker() : m_stateCount(0)
    {
        // Verbatim replacement for the ZeroMemory(m_positionStates) that
        // used to run in CTradeManager's constructor, and for the
        // m_stateCount(0) entry in its initializer list.
        ZeroMemory(m_positionStates);
    }

// Update position state with validation
    void UpdatePositionState(ulong ticket, double sl, double tp)
    {
        if(ticket <= 0) return;

        // Validate position exists before updating state
        if(!PositionSelectByTicket(ticket))
        {
            return;
        }

        int index = FindPositionState(ticket);
        if(index == -1)
        {
            if(m_stateCount < ArraySize(m_positionStates))
            {
                index = m_stateCount++;
                m_positionStates[index].ticket = ticket;
                m_positionStates[index].lastModified = TimeCurrent();
            }
            else
            {
                return;
            }
        }

        // Only update if values have changed
        if(!DoubleEquals(m_positionStates[index].lastSL, sl) ||
           !DoubleEquals(m_positionStates[index].lastTP, tp))
        {
            m_positionStates[index].lastSL = sl;
            m_positionStates[index].lastTP = tp;
            m_positionStates[index].lastModified = TimeCurrent();
        }
    }

// BEAST MODE: Clean up closed position states
    void CleanupPositionStates() {
        static datetime lastCleanup = 0;
        datetime localCurrentTime = TimeCurrent();

        // Clean up every 5 minutes
        if(localCurrentTime - lastCleanup < 300) return;
        lastCleanup = localCurrentTime;

        int removedCount = 0;
        for(int i = m_stateCount - 1; i >= 0; i--) {
            // Check if position still exists
            if(!PositionSelectByTicket(m_positionStates[i].ticket)) {
                int errCode = GetLastError();
                if(errCode != 0 && errCode != 4001) {
                    PrintFormat("[TRADE-MGR] PositionSelectByTicket failed in cleanup | ticket=%I64u | err=%d",
                                m_positionStates[i].ticket, errCode);
                }
                // Position closed or not found, remove from state tracking
                for(int j = i; j < m_stateCount - 1; j++) {
                    m_positionStates[j] = m_positionStates[j + 1];
                }
                m_stateCount--;
                removedCount++;
            }
        }
    }

// BEAST MODE: Check if modification is needed
// minModifyIntervalSec is CTradeManager::m_minModifyIntervalSec,
// passed in by the forwarder (see NO BACK-POINTER note above).
    bool IsModificationNeeded(ulong ticket, double newSL, double newTP, const int minModifyIntervalSec) {
        int index = FindPositionState(ticket);
        if(index == -1) return true; // New position, modification needed

        if(!PositionSelectByTicket(ticket)) {
            int errCode = GetLastError();
            if(errCode != 0 && errCode != 4001) {
                PrintFormat("[TRADE-MGR] PositionSelectByTicket failed in IsModificationNeeded | ticket=%I64u | err=%d",
                            ticket, errCode);
            }
            return false;
        }

        string positionSymbol = PositionGetString(POSITION_SYMBOL);
        double currentSL = PositionGetDouble(POSITION_SL);

        // Bounded throttling with emergency bypass only for missing protection.
        datetime localCurrentTime2 = TimeCurrent();
        int elapsedSec = (int)(localCurrentTime2 - m_positionStates[index].lastModified);
        if(elapsedSec < minModifyIntervalSec) {
            bool missingProtection = (newSL > 0.0 && currentSL <= 0.0);
            if(!missingProtection)
                return false;
        }

        // Get symbol for proper tolerance calculation
        double point = SymbolInfoDouble(positionSymbol, SYMBOL_POINT);
        double tolerance = point * 5; // 5 points tolerance to avoid micro-adjustments

        bool slChanged = MathAbs(m_positionStates[index].lastSL - newSL) > tolerance;
        bool tpChanged = MathAbs(m_positionStates[index].lastTP - newTP) > tolerance;

        return (slChanged || tpChanged);
    }
};

#endif // CORE_TRADING_POSITION_STATE_TRACKER_MQH
//+------------------------------------------------------------------+
