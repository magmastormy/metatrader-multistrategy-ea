// SINGLE AUTHORITY for all position lifecycle management
// Replaces: TradeManager::ManageAllPositions + PositionLifecycleManager
// Phase I decomposition: cohesive clusters were extracted into
// sibling PositionMgr*.mqh modules. The public API of
// CPositionManager is UNCHANGED - every former method survives as
// a thin forwarder with its original signature.
#property strict

#ifndef CORE_POSITION_POSITION_MANAGER_MQH
#define CORE_POSITION_POSITION_MANAGER_MQH

#include "../Trading/TradeManager.mqh"
#include "../Engines/RegimeEngine.mqh"
#include "../Risk/RiskTierManager.mqh"
#include "../Risk/SafeModeConfig.mqh"
#include "../Risk/FullMarginMode.mqh"
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
    CTradeManager*          m_tradeManager;
    CRegimeEngine*          m_regimeEngine;
    CRiskTierManager*       m_riskTierManager;
    CSafeMode*              m_safeMode;
    CFullMarginMode*        m_fullMarginMode;
    CIntelligentSLGuard*    m_slGuard;
    
    // Configuration
    bool                    m_enabled;
    double                  m_breakevenBufferPts;
    double                  m_trailingDistancePts;
    int                     m_trailingStepPoints;
    bool                    m_useATRTrailing;
    double                  m_atrMultiplier;
    int                     m_magicNumber;
    uint                    m_lastManageTimeMs;
    
    // Partial profit taking config
    bool                    m_partialProfitTakingEnabled;
    double                  m_partialProfitATRMultiplier;
    double                  m_partialProfitPercent;
    
    //--- Extracted submodules (owned BY VALUE, zero-initialised by their ctors)
    CPositionMgrStateStore  m_stateStore;   // SPositionState registry
    CPositionMgrSRE         m_sre;          // signal reversal exit
    CPositionMgrPyramid     m_pyramid;
    CPositionMgrDynamicSL   m_dynamicSL;    // volatility regimes + dynamic SL/TP
    CPositionMgrLossGuard   m_lossGuard;    // loss minimization + daily budget

    // Safe delete helper
    template<typename T>
    void SafeDelete(T* &ptr)
    {
        if(CheckPointer(ptr) == POINTER_DYNAMIC)
        {
            delete ptr;
            ptr = NULL;
        }
    }
    
    // --- SRE: Signal Reversal Exit (forwarder -> CPositionMgrSRE) ---
    bool CheckSignalReversalExit()
    {
        return m_sre.CheckSignalReversalExit(m_tradeManager, m_magicNumber);
    }
    
    void ManageBreakevenAndTrailing()
    {
        if(!m_enabled) return;
        
        uint nowMs = GetTickCount();
        if(m_lastManageTimeMs != 0 && (nowMs - m_lastManageTimeMs) < 500)
            return;
        
        // Check regime - pause trailing in ranging markets
        bool pauseTrailing = false;
        if(m_regimeEngine != NULL)
        {
            SRegimeSnapshot snap = m_regimeEngine.GetSnapshot();
            if(snap.state == REGIME_RANGE)
                pauseTrailing = true;
        }
        
        if(pauseTrailing)
        {
            // Only breakeven in ranging markets
            for(int i = PositionsTotal() - 1; i >= 0; i--)
            {
                ulong ticket = PositionGetTicket(i);
                if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
                if(!IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC))) continue;
                
                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
                double currentSL = PositionGetDouble(POSITION_SL);
                ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                double point = SymbolInfoDouble(PositionGetString(POSITION_SYMBOL), SYMBOL_POINT);
                if(point <= 0) point = 0.00001;
                
                bool isBuy = (type == POSITION_TYPE_BUY);
                double buffer = m_breakevenBufferPts * point;
                
                if(isBuy && currentPrice >= openPrice + buffer && (currentSL < openPrice || currentSL == 0))
                {
                    double newSL = NormalizeDouble(openPrice + buffer, (int)SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_DIGITS));
                    if(newSL > currentSL)
                        m_tradeManager.ModifyPosition(ticket, newSL, PositionGetDouble(POSITION_TP));
                }
                else if(!isBuy && currentPrice <= openPrice - buffer && (currentSL > openPrice || currentSL == 0))
                {
                    double newSL = NormalizeDouble(openPrice - buffer, (int)SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_DIGITS));
                    if(newSL < currentSL || currentSL == 0)
                        m_tradeManager.ModifyPosition(ticket, newSL, PositionGetDouble(POSITION_TP));
                }
            }
        }
        else
        {
            // Full management via TradeManager
            m_tradeManager.ManageAllPositions(m_breakevenBufferPts, m_trailingDistancePts, m_trailingStepPoints, m_useATRTrailing, m_atrMultiplier);
        }
        
        // Safe mode partial profit taking
        if(m_riskTierManager != NULL && m_riskTierManager.GetCurrentTier() == RISK_TIER_CONSERVATIVE && m_safeMode != NULL && m_safeMode.IsInitialized())
        {
            m_safeMode.ManageSafeModePositions(m_tradeManager);
        }
        
        m_lastManageTimeMs = nowMs;
    }
    
    // --- Pyramiding (forwarder -> CPositionMgrPyramid) ---
    void ManagePyramiding()
    {
        m_pyramid.ManagePyramiding(m_tradeManager, m_magicNumber);
    }
    
    // --- Dynamic SL/TP (forwarder -> CPositionMgrDynamicSL) ---
    void ManageDynamicSLTP()
    {
        m_dynamicSL.ManageDynamicSLTP(m_tradeManager, m_magicNumber);
    }
    
    // --- Loss Minimization (forwarder -> CPositionMgrLossGuard) ---
    void ManageLossMinimization()
    {
        m_lossGuard.ManageLossMinimization(m_tradeManager, m_magicNumber);
    }
    
    void ManagePartialProfitTaking()
    {
        if(!m_partialProfitTakingEnabled) return;
        
        // Implementation would check if position has moved X ATR in favor
        // and close partial percentage
    }
    
    // --- Magic number check (forwarder -> CPositionMgrMagicFilter) ---
    bool IsEAOwnedMagic(long magic) const
    {
        return CPositionMgrMagicFilter::IsEAOwnedMagic(magic);
    }
    
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

    CPositionManager() :
        m_tradeManager(NULL), m_regimeEngine(NULL), m_riskTierManager(NULL),
        m_safeMode(NULL), m_fullMarginMode(NULL), m_slGuard(NULL),
        m_enabled(true), m_breakevenBufferPts(120.0), m_trailingDistancePts(300.0),
        m_trailingStepPoints(5), m_useATRTrailing(false), m_atrMultiplier(1.5),
        m_magicNumber(0), m_lastManageTimeMs(0),
        m_partialProfitTakingEnabled(false), m_partialProfitATRMultiplier(1.0),
        m_partialProfitPercent(25.0)
    {
        // Submodule state (pyramid ledger, volatility regimes, position states,
        // SRE config, loss tracking) is zero-initialised by each submodule ctor.
    }
    
    ~CPositionManager()
    {
        // Arrays auto-cleanup
    }
    
    // Initialize with dependencies
    bool Initialize(CTradeManager* tm, CRegimeEngine* regime, CRiskTierManager* rtm, 
                    CSafeMode* safe, CFullMarginMode* fullMargin, CIntelligentSLGuard* slGuard,
                    int magicNumber)
    {
        if(tm == NULL || rtm == NULL)
            return false;
        
        m_tradeManager = tm;
        m_regimeEngine = regime;
        m_riskTierManager = rtm;
        m_safeMode = safe;
        m_fullMarginMode = fullMargin;
        m_slGuard = slGuard;
        m_magicNumber = magicNumber;
        
        return true;
    }
    
    // Configuration setters
    void ConfigureSRE(bool enabled, double minConf, bool profitGuard, double minLossR, double maxLossR, int minTimeSec, bool structuralInv)
    {
        m_sre.Configure(enabled, minConf, profitGuard, minLossR, maxLossR, minTimeSec, structuralInv);
    }
    
    void ConfigureLifecycle(bool enabled, double beBuffer, double trailDist, int trailStep, bool useATR, double atrMult)
    {
        m_enabled = enabled; m_breakevenBufferPts = beBuffer; m_trailingDistancePts = trailDist;
        m_trailingStepPoints = trailStep; m_useATRTrailing = useATR; m_atrMultiplier = atrMult;
    }
    
    void ConfigurePyramiding(bool enabled, double stepPips, double sizeMult, int maxLayers)
    {
        m_pyramid.Configure(enabled, stepPips, sizeMult, maxLayers);
    }
    
    void ConfigureDynamicSL(bool enabled, double slMult, double tpMult, bool volAdjust)
    {
        m_dynamicSL.Configure(enabled, slMult, tpMult, volAdjust);
    }
    
    void ConfigureLossMinimization(bool adverseExit, double adverseMult, int consecLimit, int consecCooldown, double dailyCB, double posLimit)
    {
        m_lossGuard.Configure(adverseExit, adverseMult, consecLimit, consecCooldown, dailyCB, posLimit);
    }
    
    void ConfigurePartialProfitTaking(bool enabled, double atrMult, double percent)
    {
        m_partialProfitTakingEnabled = enabled; m_partialProfitATRMultiplier = atrMult; m_partialProfitPercent = percent;
    }
    
    void SetDailyRiskBudget(double budget)
    {
        m_lossGuard.SetDailyRiskBudget(budget);
    }
    
    // Main entry point - call from OnTick or OnTimer
    void ManagePositions()
    {
        if(!m_enabled || PositionsTotal() <= 0)
            return;
        
        // Reset daily loss tracking on new day
        datetime now = TimeCurrent();
        m_lossGuard.ResetDailyIfNeeded(now);
        
        CheckSignalReversalExit();
        ManageBreakevenAndTrailing();
        
        if(m_pyramid.IsEnabled())
            ManagePyramiding();
        
        if(m_dynamicSL.IsEnabled())
            ManageDynamicSLTP();
        
        if(m_lossGuard.ShouldRunLossMinimization())
            ManageLossMinimization();
        
        if(m_partialProfitTakingEnabled)
            ManagePartialProfitTaking();
        
        // Update daily loss tracking
        double dailyPnL = 0;
        // Would calculate from closed positions
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
