// Position-state and prediction-map registry for the positions this EA owns.
// It is not an exit authority and has not been one since the batch that deleted its Manage*/Configure*/
// Initialize surface: no caller reached any of it, and CPositionLifecycleManager is the live exit path
// (EAOrchestrator::ManageOpenPositions). What survives is what TradeExecutor and TradeAttributionManager
// actually call: RegisterPositionState, the SPositionState registry and the prediction-id/position maps.
#property strict

#ifndef CORE_POSITION_POSITION_MANAGER_MQH
#define CORE_POSITION_POSITION_MANAGER_MQH

#include "../Trading/TradeManager.mqh"
#include "../Engines/RegimeEngine.mqh"
#include "../Risk/RiskTierManager.mqh"
#include "../Risk/SafeModeConfig.mqh"
#include "../Utils/Enums.mqh"

//--- Phase I extracted submodules.
//--- Include order matters: each declares a complete type that is held
//--- BY VALUE as a member of CPositionManager below. They are pulled in
//--- AFTER TradeManager.mqh so that the top-level SPositionState /
//--- SVolatilityRegime declarations keep their original relative order.
#include "PositionMgrMagicFilter.mqh"   // stateless EA-magic ownership filter
#include "PositionMgrStateStore.mqh"    // SPositionState + position state registry
#include "PositionMgrSRE.mqh"           // signal reversal exit
#include "PositionMgrPyramid.mqh"       // pyramiding layer ledger
#include "PositionMgrDynamicSL.mqh"     // SVolatilityRegime + dynamic SL/TP
#include "PositionMgrLossGuard.mqh"     // loss minimization + daily loss budget

class CPositionManager
{
private:
    // The four collaborator pointers and the trailing/pyramiding/partial-profit config were read only by the
    // exit methods that had no caller. m_enabled stays because GetStatusReport prints it - and no caller ever
    // reached the one setter that wrote it, so it has been true for the whole life of this class.
    bool                    m_enabled;
    
    //--- Extracted submodules (owned BY VALUE, zero-initialised by their ctors)
    CPositionMgrStateStore  m_stateStore;   // SPositionState registry
    CPositionMgrSRE         m_sre;          // signal reversal exit
    CPositionMgrPyramid     m_pyramid;
    CPositionMgrDynamicSL   m_dynamicSL;    // volatility regimes + dynamic SL/TP
    CPositionMgrLossGuard   m_lossGuard;    // loss minimization + daily budget

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

    bool GetPositionStateByIndex(const int index, SPositionState &state)
    {
        return m_stateStore.GetPositionStateByIndex(index, state);
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

    // Batch 153: RemoveStalePositionStates / GetAllPositionStateIds /
    // IsPositionStateInitialized / PrintPositionStateDebugInfo /
    // ClearAllPositionStateMaps were removed - zero callers repo-wide.

    CPositionManager() : m_enabled(true)
    {
        // Submodule state (pyramid ledger, volatility regimes, position states,
        // SRE config, loss tracking) is zero-initialised by each submodule ctor.
    }
    
    ~CPositionManager()
    {
        // Arrays auto-cleanup
    }
    

    // Record closed trade for loss tracking
    void RecordClosedTrade(double profit)
    {
        m_lossGuard.RecordClosedTrade(profit);
    }
    
    // Diagnostics
    string GetStatusReport() const
    {
        string report = "[PositionManager] ";
        report += "Enabled=" + (m_enabled ? "Y" : "N");
        report += " | Pyramid=" + (m_pyramid.IsEnabled() ? "Y" : "N");
        report += " | DynamicSL=" + (m_dynamicSL.IsEnabled() ? "Y" : "N");
        report += " | LossMin=" + (m_lossGuard.IsAdverseMomentumExitEnabled() ? "Y" : "N");
        report += " | SRE=" + (m_sre.IsEnabled() ? "Y" : "N");
        report += " | ConsecLoss=" + IntegerToString(m_lossGuard.GetConsecutiveLossCount());
        report += " | DailyLoss=" + DoubleToString(m_lossGuard.GetDailyLossAmount(), 2);
        report += " | PyramidStates=" + IntegerToString(m_pyramid.GetStateCount());
        report += " | VolRegimes=" + IntegerToString(m_dynamicSL.GetRegimeCount());
        return report;
    }
    
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
