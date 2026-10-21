// The SPositionState registry: broker tickets to strategy metadata, prediction IDs and AI snapshots. Bodies
// copied verbatim from CPositionManager, zero behaviour change.
// SPositionState stays a TOP-LEVEL struct so every translation unit that includes PositionManager.mqh keeps
// seeing it, and it must stay declared after Core/Trading/TradeManager.mqh - include order there guarantees it.
#property strict

#ifndef CORE_POSITION_POSITION_MGR_STATE_STORE_MQH
#define CORE_POSITION_POSITION_MGR_STATE_STORE_MQH

#include "../Utils/Enums.mqh"   // ENUM_TRADE_SIGNAL / TRADE_SIGNAL_NONE

// Position State Structure (merged from PositionStateManager)
struct SPositionState
{
    ulong positionId;           // Position ticket ID
    string symbol;
    ENUM_ORDER_TYPE orderType;
    double volume;
    double price;               // Entry price
    double slPips;              // Stop loss in pips
    double tpPips;              // Take profit in pips
    int clusterCode;
    string strategyRole;
    string predictionId;        // Prediction ID associated with position
    datetime aiPredictionTime;
    ENUM_TRADE_SIGNAL aiPredictionSignal;

    SPositionState()
    {
        positionId = 0;
        symbol = "";
        orderType = ORDER_TYPE_BUY;
        volume = 0;
        price = 0;
        slPips = 0;
        tpPips = 0;
        clusterCode = 0;
        strategyRole = "";
        predictionId = "";
        aiPredictionTime = 0;
        aiPredictionSignal = TRADE_SIGNAL_NONE;
    }
};

// Owns: m_positionStates[] / m_positionStateCount / MAX bound.
class CPositionMgrStateStore
{
private:
    static const int        MAX_POSITION_STATES;
    SPositionState          m_positionStates[];
    int                     m_positionStateCount;

    //--- One append path for the three writers: evict the oldest slot when full, then hand back the index of a
    //--- freshly default-constructed tail element.
    int AcquireSlot()
    {
        if(m_positionStateCount >= MAX_POSITION_STATES)
        {
            for(int i = 0; i < m_positionStateCount - 1; i++)
                m_positionStates[i] = m_positionStates[i + 1];
            m_positionStateCount--;
            ArrayResize(m_positionStates, m_positionStateCount);
        }

        ArrayResize(m_positionStates, m_positionStateCount + 1);
        SPositionState blank;
        m_positionStates[m_positionStateCount] = blank;
        return m_positionStateCount++;
    }

    //--- Shift-down erase, shared by the prediction-id and AI-prediction maps, which remove the same slot.
    void EraseAt(const int idx)
    {
        for(int i = idx; i < m_positionStateCount - 1; i++)
            m_positionStates[i] = m_positionStates[i + 1];
        m_positionStateCount--;
        ArrayResize(m_positionStates, m_positionStateCount);
    }

public:
    CPositionMgrStateStore() : m_positionStateCount(0)
    {
        ArrayResize(m_positionStates, 0);
    }

    ~CPositionMgrStateStore()
    {
        // Arrays auto-cleanup
    }

    //--- Linear scan for the slot holding 'positionId'. -1 when absent.
    int FindPositionStateIndex(const ulong positionId)
    {
        for(int i = 0; i < m_positionStateCount; i++)
        {
            if(m_positionStates[i].positionId == positionId)
                return i;
        }
        return -1;
    }

    void UpsertPositionPredictionId(const ulong positionId, const string predictionId)
    {
        if(positionId == 0 || predictionId == "")
            return;

        int idx = FindPositionStateIndex(positionId);
        if(idx >= 0)
        {
            m_positionStates[idx].predictionId = predictionId;
            return;
        }

        const int slot = AcquireSlot();
        m_positionStates[slot].positionId = positionId;
        m_positionStates[slot].predictionId = predictionId;
    }

    string GetPositionPredictionId(const ulong positionId)
    {
        int idx = FindPositionStateIndex(positionId);
        if(idx < 0 || idx >= m_positionStateCount)
            return "";
        return m_positionStates[idx].predictionId;
    }

    void RemovePositionPrediction(const ulong positionId)
    {
        int idx = FindPositionStateIndex(positionId);
        if(idx < 0)
            return;
        EraseAt(idx);
    }

    void UpsertPositionAIPrediction(const ulong positionId, const datetime predictionTime, const ENUM_TRADE_SIGNAL predictionSignal)
    {
        if(positionId == 0 || predictionTime <= 0 || predictionSignal == TRADE_SIGNAL_NONE)
            return;

        int idx = FindPositionStateIndex(positionId);
        if(idx >= 0)
        {
            m_positionStates[idx].aiPredictionTime = predictionTime;
            m_positionStates[idx].aiPredictionSignal = predictionSignal;
            return;
        }

        const int slot = AcquireSlot();
        m_positionStates[slot].positionId = positionId;
        m_positionStates[slot].aiPredictionTime = predictionTime;
        m_positionStates[slot].aiPredictionSignal = predictionSignal;
    }

    datetime GetPositionAIPredictionTime(const ulong positionId)
    {
        int idx = FindPositionStateIndex(positionId);
        if(idx < 0 || idx >= m_positionStateCount)
            return 0;
        return m_positionStates[idx].aiPredictionTime;
    }

    ENUM_TRADE_SIGNAL GetPositionAIPredictionSignal(const ulong positionId)
    {
        int idx = FindPositionStateIndex(positionId);
        if(idx < 0 || idx >= m_positionStateCount)
            return TRADE_SIGNAL_NONE;
        return m_positionStates[idx].aiPredictionSignal;
    }

    void RemovePositionAIPrediction(const ulong positionId)
    {
        int idx = FindPositionStateIndex(positionId);
        if(idx < 0)
            return;
        EraseAt(idx);
    }

    void RegisterPositionState(const ulong positionId, const string symbol, ENUM_ORDER_TYPE orderType,
                               double volume, double price, double slPips, double tpPips,
                               int clusterCode, const string strategyRole)
    {
        if(positionId == 0) return;
        if(FindPositionStateIndex(positionId) >= 0) return;

        const int slot = AcquireSlot();
        m_positionStates[slot].positionId = positionId;
        m_positionStates[slot].symbol = symbol;
        m_positionStates[slot].orderType = orderType;
        m_positionStates[slot].volume = volume;
        m_positionStates[slot].price = price;
        m_positionStates[slot].slPips = slPips;
        m_positionStates[slot].tpPips = tpPips;
        m_positionStates[slot].clusterCode = clusterCode;
        m_positionStates[slot].strategyRole = strategyRole;
    }

    int GetPositionStateCount() const { return m_positionStateCount; }
};

const int CPositionMgrStateStore::MAX_POSITION_STATES = 500;

#endif // CORE_POSITION_POSITION_MGR_STATE_STORE_MQH
