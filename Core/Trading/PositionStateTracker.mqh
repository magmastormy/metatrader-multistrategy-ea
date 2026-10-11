// Position SL/TP state registry held BY VALUE inside CTradeManager, which keeps
// thin forwarders with the original public signatures.
// SPositionState stays nested: a field-incompatible top-level struct of the same name
// (Core/Position/PositionMgrStateStore.mqh) would collide in this translation unit.
// UpdatePositionState is the sole SL/TP writer; IsModificationNeeded is the read path.
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
    struct SPositionState {
        ulong ticket;
        double lastSL;
        double lastTP;
        datetime lastModified;
    };
    SPositionState m_positionStates[100]; // Track up to 100 positions
    int m_stateCount;

    bool DoubleEquals(double a, double b, double epsilon = 0.00001)
    {
        return MathAbs(a - b) < epsilon;
    }

// Internal only - called by FindPositionState; never forwarded.
    void RemovePositionState(int index)
    {
        if(index < 0 || index >= m_stateCount) return;

        for(int i = index; i < m_stateCount - 1; i++)
        {
            m_positionStates[i] = m_positionStates[i + 1];
        }

        m_positionStates[m_stateCount - 1].ticket = 0;
        m_positionStates[m_stateCount - 1].lastSL = 0;
        m_positionStates[m_stateCount - 1].lastTP = 0;
        m_positionStates[m_stateCount - 1].lastModified = 0;

        m_stateCount--;
    }

// Internal only - the public methods below are its only callers.
    int FindPositionState(ulong ticket)
    {
        if(ticket <= 0) return -1;

        for(int i = 0; i < m_stateCount; i++)
        {
            if(m_positionStates[i].ticket == ticket)
            {
                if(!PositionSelectByTicket(ticket))
                {
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
        ZeroMemory(m_positionStates);
    }

    void UpdatePositionState(ulong ticket, double sl, double tp)
    {
        if(ticket <= 0) return;

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

        if(!DoubleEquals(m_positionStates[index].lastSL, sl) ||
           !DoubleEquals(m_positionStates[index].lastTP, tp))
        {
            m_positionStates[index].lastSL = sl;
            m_positionStates[index].lastTP = tp;
            m_positionStates[index].lastModified = TimeCurrent();
        }
    }

    void CleanupPositionStates() {
        static datetime lastCleanup = 0;
        datetime localCurrentTime = TimeCurrent();

        if(localCurrentTime - lastCleanup < 300) return;
        lastCleanup = localCurrentTime;

        int removedCount = 0;
        for(int i = m_stateCount - 1; i >= 0; i--) {
            if(!PositionSelectByTicket(m_positionStates[i].ticket)) {
                int errCode = GetLastError();
                if(errCode != 0 && errCode != 4001) {
                    PrintFormat("[TRADE-MGR] PositionSelectByTicket failed in cleanup | ticket=%I64u | err=%d",
                                m_positionStates[i].ticket, errCode);
                }
                for(int j = i; j < m_stateCount - 1; j++) {
                    m_positionStates[j] = m_positionStates[j + 1];
                }
                m_stateCount--;
                removedCount++;
            }
        }
    }

// minModifyIntervalSec is CTradeManager's protective-modify cooldown, passed in by the forwarder.
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

        double point = SymbolInfoDouble(positionSymbol, SYMBOL_POINT);
        double tolerance = point * 5; // 5 points tolerance to avoid micro-adjustments

        bool slChanged = MathAbs(m_positionStates[index].lastSL - newSL) > tolerance;
        bool tpChanged = MathAbs(m_positionStates[index].lastTP - newTP) > tolerance;

        return (slChanged || tpChanged);
    }
};

#endif // CORE_TRADING_POSITION_STATE_TRACKER_MQH
