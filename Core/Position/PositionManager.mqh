// Position-state and prediction-map registry: TradeExecutor registers each fill (TradeExecutor.mqh:312) and
// TradeAttributionManager reads the maps back by ticket (TradeAttributionManager.mqh:606). Exits belong to
// CPositionLifecycleManager; this class holds no exit logic and no status reporting.
#property strict

#ifndef CORE_POSITION_POSITION_MANAGER_MQH
#define CORE_POSITION_POSITION_MANAGER_MQH

//--- TradeManager.mqh stays first: CPositionMgrStateStore declares the top-level SPositionState after it, and
//--- every translation unit that includes this header relies on that relative order.
#include "../Trading/TradeManager.mqh"
#include "../Utils/Enums.mqh"
#include "PositionMgrStateStore.mqh"

class CPositionManager
{
private:
    CPositionMgrStateStore  m_stateStore;   // SPositionState registry

    // --- Position State Tracking (forwarders -> CPositionMgrStateStore) ---
    int FindPositionStateIndex(const ulong positionId)
    {
        return m_stateStore.FindPositionStateIndex(positionId);
    }
    
    void UpsertPositionPredictionId(const ulong positionId, const string predictionId)
    {
        m_stateStore.UpsertPositionPredictionId(positionId, predictionId);
    }
    
    string GetPositionPredictionId(const ulong positionId)
    {
        return m_stateStore.GetPositionPredictionId(positionId);
    }
    
    void RemovePositionPrediction(const ulong positionId)
    {
        m_stateStore.RemovePositionPrediction(positionId);
    }
    
    void UpsertPositionAIPrediction(const ulong positionId, const datetime predictionTime, const ENUM_TRADE_SIGNAL predictionSignal)
    {
        m_stateStore.UpsertPositionAIPrediction(positionId, predictionTime, predictionSignal);
    }
    
    datetime GetPositionAIPredictionTime(const ulong positionId)
    {
        return m_stateStore.GetPositionAIPredictionTime(positionId);
    }
    
    ENUM_TRADE_SIGNAL GetPositionAIPredictionSignal(const ulong positionId)
    {
        return m_stateStore.GetPositionAIPredictionSignal(positionId);
    }
    
    void RemovePositionAIPrediction(const ulong positionId)
    {
        m_stateStore.RemovePositionAIPrediction(positionId);
    }

public:
    void RegisterPositionState(const ulong positionId, const string symbol, ENUM_ORDER_TYPE orderType,
                               double volume, double price, double slPips, double tpPips,
                               int clusterCode, const string strategyRole)
    {
        m_stateStore.RegisterPositionState(positionId, symbol, orderType, volume, price,
                                           slPips, tpPips, clusterCode, strategyRole);
    }

    int GetPositionStateCount() const { return m_stateStore.GetPositionStateCount(); }

    // Position State Tracking accessors (for TradeAttributionManager)
    int FindPredictionPositionIndex(const ulong positionId)
    {
        return FindPositionStateIndex(positionId);
    }
    
    void UpsertPredictionPositionMap(const ulong positionId, const string predictionId)
    {
        UpsertPositionPredictionId(positionId, predictionId);
    }
    
    string GetPredictionIdForPosition(const ulong positionId)
    {
        return GetPositionPredictionId(positionId);
    }
    
    void RemovePredictionPositionMap(const ulong positionId)
    {
        RemovePositionPrediction(positionId);
    }
    
    int FindAIPredictionPositionIndex(const ulong positionId)
    {
        return FindPositionStateIndex(positionId);
    }
    
    void UpsertAIPredictionPositionMap(const ulong positionId, const datetime predictionTime, const ENUM_TRADE_SIGNAL predictionSignal)
    {
        UpsertPositionAIPrediction(positionId, predictionTime, predictionSignal);
    }
    
    datetime GetAIPredictionTimeForPosition(const ulong positionId)
    {
        return GetPositionAIPredictionTime(positionId);
    }
    
    ENUM_TRADE_SIGNAL GetAIPredictionSignalForPosition(const ulong positionId)
    {
        return GetPositionAIPredictionSignal(positionId);
    }
    
    void RemoveAIPredictionPositionMap(const ulong positionId)
    {
        RemovePositionAIPrediction(positionId);
    }
};

#endif // CORE_POSITION_POSITION_MANAGER_MQH
