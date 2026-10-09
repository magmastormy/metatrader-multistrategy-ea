// Extracted from PositionManager.mqh (Phase I decomposition)
// STATEFUL module: owns the SPositionState registry that maps
// broker position tickets to strategy metadata, prediction IDs and
// AI prediction snapshots. Method bodies are copied verbatim from
// CPositionManager - zero behaviour change.
// NOTE: 'SPositionState' intentionally remains a TOP-LEVEL struct
// (exactly as it was declared in PositionManager.mqh) so that any
// translation unit including PositionManager.mqh keeps seeing it.
// It must stay declared AFTER Core/Trading/TradeManager.mqh is
// pulled in, which PositionManager.mqh guarantees by include order.
#property strict

#ifndef CORE_POSITION_POSITION_MGR_STATE_STORE_MQH
#define CORE_POSITION_POSITION_MGR_STATE_STORE_MQH

#include "../Utils/Enums.mqh"   // ENUM_TRADE_SIGNAL / TRADE_SIGNAL_NONE

// Position State Structure (merged from PositionStateManager)
struct SPositionState
{
    ulong positionId;           // Position ticket ID
    string symbol;              // Symbol
    ENUM_ORDER_TYPE orderType;  // Order type
    double volume;              // Volume
    double price;               // Entry price
    double slPips;              // Stop loss in pips
    double tpPips;              // Take profit in pips
    int clusterCode;            // Cluster code
    string strategyRole;        // Strategy role
    string predictionId;        // Prediction ID associated with position
    datetime aiPredictionTime;  // AI prediction time
    ENUM_TRADE_SIGNAL aiPredictionSignal; // AI prediction signal

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

        // Check bounds before adding new state
        if(m_positionStateCount >= MAX_POSITION_STATES)
        {
            // Remove oldest entry to make room
            for(int i = 0; i < m_positionStateCount - 1; i++)
            {
                m_positionStates[i] = m_positionStates[i + 1];
            }
            m_positionStateCount--;
            ArrayResize(m_positionStates, m_positionStateCount);
        }

        // Create new state
        ArrayResize(m_positionStates, m_positionStateCount + 1);
        ZeroMemory(m_positionStates[m_positionStateCount]);
        SPositionState newState;
        newState.positionId = positionId;
        newState.predictionId = predictionId;
        newState.aiPredictionTime = 0;
        newState.aiPredictionSignal = TRADE_SIGNAL_NONE;
        m_positionStates[m_positionStateCount] = newState;
        m_positionStateCount++;
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

        // Shift elements
        for(int i = idx; i < m_positionStateCount - 1; i++)
        {
            m_positionStates[i] = m_positionStates[i + 1];
        }

        m_positionStateCount--;
        ArrayResize(m_positionStates, m_positionStateCount);
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

        // Check bounds before adding new state
        if(m_positionStateCount >= MAX_POSITION_STATES)
        {
            // Remove oldest entry to make room
            for(int i = 0; i < m_positionStateCount - 1; i++)
            {
                m_positionStates[i] = m_positionStates[i + 1];
            }
            m_positionStateCount--;
            ArrayResize(m_positionStates, m_positionStateCount);
        }

        // Create new state
        ArrayResize(m_positionStates, m_positionStateCount + 1);
        SPositionState newState;
        newState.positionId = positionId;
        newState.predictionId = "";
        newState.aiPredictionTime = predictionTime;
        newState.aiPredictionSignal = predictionSignal;
        m_positionStates[m_positionStateCount] = newState;
        m_positionStateCount++;
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

        // Shift elements
        for(int i = idx; i < m_positionStateCount - 1; i++)
        {
            m_positionStates[i] = m_positionStates[i + 1];
        }

        m_positionStateCount--;
        ArrayResize(m_positionStates, m_positionStateCount);
    }

    bool GetPositionStateByIndex(const int index, SPositionState &state)
    {
        if(index < 0 || index >= m_positionStateCount)
            return false;
        state = m_positionStates[index];
        return true;
    }

    void RegisterPositionState(const ulong positionId, const string symbol, ENUM_ORDER_TYPE orderType,
                               double volume, double price, double slPips, double tpPips,
                               int clusterCode, const string strategyRole)
    {
        if(positionId == 0) return;

        // Check if already exists
        int idx = FindPositionStateIndex(positionId);
        if(idx >= 0) return;

        // Check bounds before adding new state
        if(m_positionStateCount >= MAX_POSITION_STATES)
        {
            // Remove oldest entry to make room
            for(int i = 0; i < m_positionStateCount - 1; i++)
            {
                m_positionStates[i] = m_positionStates[i + 1];
            }
            m_positionStateCount--;
            ArrayResize(m_positionStates, m_positionStateCount);
        }

        // Create new state
        ArrayResize(m_positionStates, m_positionStateCount + 1);
        SPositionState newState;
        newState.positionId = positionId;
        newState.symbol = symbol;
        newState.orderType = orderType;
        newState.volume = volume;
        newState.price = price;
        newState.slPips = slPips;
        newState.tpPips = tpPips;
        newState.clusterCode = clusterCode;
        newState.strategyRole = strategyRole;
        newState.predictionId = "";
        newState.aiPredictionTime = 0;
        newState.aiPredictionSignal = TRADE_SIGNAL_NONE;
        m_positionStates[m_positionStateCount] = newState;
        m_positionStateCount++;
    }

    // Batch 153: ClearAllPositionStates / RemoveStalePositionStates /
    // GetAllPositionStateIds / IsPositionStateInitialized /
    // PrintPositionStateDebugInfo were removed - zero callers repo-wide
    // once the CPositionManager forwarders were deleted.

    int GetPositionStateCount() const { return m_positionStateCount; }
};

const int CPositionMgrStateStore::MAX_POSITION_STATES = 500;

#endif // CORE_POSITION_POSITION_MGR_STATE_STORE_MQH
