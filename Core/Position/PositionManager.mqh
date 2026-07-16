//+------------------------------------------------------------------+
//| PositionManager.mqh                                              |
//| SINGLE AUTHORITY for all position lifecycle management           |
//| Replaces: TradeManager::ManageAllPositions + PositionLifecycleManager |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_POSITION_POSITION_MANAGER_MQH
#define CORE_POSITION_POSITION_MANAGER_MQH

#include "../Trading/TradeManager.mqh"
#include "../Engines/RegimeEngine.mqh"
#include "../Risk/RiskTierManager.mqh"
#include "../Risk/SafeModeConfig.mqh"
#include "../Risk/FullMarginMode.mqh"
#include "../Utils/Enums.mqh"

// Volatility regime tracking struct (must be global for pointer usage)
struct SVolatilityRegime
{
    string      symbol;
    double      atr14;
    double      atr50;
    int         regime;  // 0=low, 1=normal, 2=high
    datetime    lastUpdate;
    
    SVolatilityRegime() : symbol(""), atr14(0), atr50(0), regime(1), lastUpdate(0) {}
};

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
    
    // SRE config
    bool                    m_sreEnabled;
    double                  m_sreMinConfidence;
    bool                    m_sreProfitGuard;
    double                  m_sreMinLossR;
    double                  m_sreMaxLossR;
    int                     m_sreMinTimeSec;
    bool                    m_structuralInvalidationEnabled;
    
    // Pyramiding config
    bool                    m_pyramidingEnabled;
    double                  m_pyramidingStepPips;
    double                  m_pyramidingSizeMultiplier;
    int                     m_pyramidingMaxLayers;
    
    // Dynamic SL/TP config
    bool                    m_dynamicSLEnabled;
    double                  m_dynamicSLATRMultiplier;
    double                  m_dynamicTPATRMultiplier;
    bool                    m_volatilitySLAdjustEnabled;
    
    // Loss minimization config
    bool                    m_adverseMomentumExitEnabled;
    double                  m_adverseMomentumATRMultiplier;
    int                     m_consecutiveLossLimit;
    int                     m_consecutiveLossCooldownSec;
    double                  m_dailyLossCircuitBreakerPercent;
    double                  m_positionLossLimitPercent;
    
    // Partial profit taking config
    bool                    m_partialProfitTakingEnabled;
    double                  m_partialProfitATRMultiplier;
    double                  m_partialProfitPercent;
    
    // State
    struct SPyramidState
    {
        ulong       baseTicket;
        int         layer;
        double      entryPrice;
        double      nextStepPips;
        double      baseLotSize;
        bool        active;
        
        SPyramidState() : baseTicket(0), layer(0), entryPrice(0), nextStepPips(0), baseLotSize(0), active(false) {}
    };
    
    SPyramidState           m_pyramidStates[];
    int                     m_pyramidStateCount;
    
    SVolatilityRegime       m_volatilityRegimes[];
    int                     m_volatilityRegimeCount;
    
    // Loss tracking
    int                     m_consecutiveLossCount;
    datetime                m_lastLossTime;
    datetime                m_consecutiveLossCooldownUntil;
    double                  m_dailyLossAmount;
    double                  m_dailyRiskBudget;
    datetime                m_dailyResetTime;

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
    
    // Find pyramid state by base ticket
    int FindPyramidState(ulong baseTicket)
    {
        for(int i = 0; i < m_pyramidStateCount; i++)
            if(m_pyramidStates[i].baseTicket == baseTicket && m_pyramidStates[i].active)
                return i;
        return -1;
    }
    
    // Get or create volatility regime for symbol
    SVolatilityRegime GetVolatilityRegime(const string symbol)
    {
        for(int i = 0; i < m_volatilityRegimeCount; i++)
            if(m_volatilityRegimes[i].symbol == symbol)
                return m_volatilityRegimes[i];
        
        int idx = m_volatilityRegimeCount;
        ArrayResize(m_volatilityRegimes, idx + 1);
        m_volatilityRegimes[idx].symbol = symbol;
        m_volatilityRegimeCount++;
        return m_volatilityRegimes[idx];
    }
    
    // Update volatility regimes using ATR from IndicatorManager
    void UpdateVolatilityRegimes()
    {
        datetime now = TimeCurrent();
        for(int i = 0; i < m_volatilityRegimeCount; i++)
        {
            SVolatilityRegime regime = m_volatilityRegimes[i];
            if(now - regime.lastUpdate < 300) continue; // Update every 5 min max
            
            CIndicatorManager* indMgr = CIndicatorManager::Instance();
            if(indMgr == NULL) continue;
            
            ENUM_TIMEFRAMES tf = (ENUM_TIMEFRAMES)Period();
            int atr14Handle = indMgr.GetATRHandle(regime.symbol, tf, 14);
            int atr50Handle = indMgr.GetATRHandle(regime.symbol, tf, 50);
            
            double atr14Buf[], atr50Buf[];
            ArraySetAsSeries(atr14Buf, true);
            ArraySetAsSeries(atr50Buf, true);
            
            if(CopyBuffer(atr14Handle, 0, 0, 1, atr14Buf) > 0 &&
               CopyBuffer(atr50Handle, 0, 0, 1, atr50Buf) > 0)
            {
                regime.atr14 = atr14Buf[0];
                regime.atr50 = atr50Buf[0];
                regime.lastUpdate = now;
                
                if(regime.atr50 > 0)
                {
                    double ratio = regime.atr14 / regime.atr50;
                    if(ratio < 0.7) regime.regime = 0;
                    else if(ratio > 1.3) regime.regime = 2;
                    else regime.regime = 1;
                }
                m_volatilityRegimes[i] = regime;
            }
        }
    }
    
    // --- SRE: Signal Reversal Exit ---
    bool CheckSignalReversalExit()
    {
        if(!m_sreEnabled) return false;
        
        bool anyReversal = false;
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(!IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC))) continue;
            
            string sym = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            
            // Get current consensus signal
            // In practice, this would query the consensus cache or enterprise manager
            // For now, use a simplified check
            double confidence = 0;
            int confluence = 0;
            // This would be filled from the consensus system
            
            bool isBuy = (type == POSITION_TYPE_BUY);
            bool opposingSignal = false; // Would be set based on actual signal
            
            if(opposingSignal)
            {
                double currentProfit = PositionGetDouble(POSITION_PROFIT);
                bool inLoss = (currentProfit < 0);
                
                datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
                int durationSec = (int)(TimeCurrent() - openTime);
                
                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double slPrice = PositionGetDouble(POSITION_SL);
                double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
                double slDistance = MathAbs(openPrice - slPrice);
                double posCurrentDrawdown = MathAbs(openPrice - currentPrice);
                double lossR = (slDistance > 0) ? (posCurrentDrawdown / slDistance) : 0.0;
                
                bool hasBreathingRoom = (durationSec < m_sreMinTimeSec);
                bool isMinorNoise = (inLoss && lossR < m_sreMinLossR);
                bool isLastStandZone = (inLoss && lossR > m_sreMaxLossR);
                
                if(confidence >= m_sreMinConfidence)
                {
                    if(isLastStandZone)
                    {
                        // Skip SRE, let hard SL decide
                    }
                    else if(!hasBreathingRoom || lossR > 0.50)
                    {
                        bool profitGuardBlocked = false;
                        if(m_sreProfitGuard && inLoss && lossR > 0.25)
                            profitGuardBlocked = true;
                        
                        if(!profitGuardBlocked)
                        {
                            m_tradeManager.ClosePosition(ticket, "Signal Reversal Exit");
                            anyReversal = true;
                        }
                    }
                }
                
                if(m_structuralInvalidationEnabled && !anyReversal)
                {
                    // Check structural invalidation - would need consensus context
                }
            }
        }
        
        return anyReversal;
    }
    
    // --- Breakeven & Trailing ---
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
    
    // --- Pyramiding ---
    void ManagePyramiding()
    {
        if(!m_pyramidingEnabled) return;
        
        // Implementation similar to PositionLifecycleManager
        // Iterate positions, check profit, add layers
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(!IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC))) continue;
            
            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double lotSize = PositionGetDouble(POSITION_VOLUME);
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            if(point <= 0) point = 0.00001;
            
            double profitPips = (type == POSITION_TYPE_BUY) 
                ? (currentPrice - openPrice) / point 
                : (openPrice - currentPrice) / point;
            
            int stateIdx = FindPyramidState(ticket);
            if(stateIdx < 0)
            {
                // Create new pyramid state
                SPyramidState state;
                state.baseTicket = ticket;
                state.layer = 0;
                state.entryPrice = openPrice;
                state.nextStepPips = m_pyramidingStepPips;
                state.baseLotSize = lotSize;
                state.active = true;
                
                if(m_pyramidStateCount >= ArraySize(m_pyramidStates))
                    ArrayResize(m_pyramidStates, m_pyramidStateCount + 10);
                m_pyramidStates[m_pyramidStateCount] = state;
                m_pyramidStateCount++;
                stateIdx = m_pyramidStateCount - 1;
            }
            
            SPyramidState state = m_pyramidStates[stateIdx];
            
            if(state.active && state.layer < m_pyramidingMaxLayers && profitPips >= state.nextStepPips)
            {
                double pyramidLotSize = state.baseLotSize * MathPow(m_pyramidingSizeMultiplier, state.layer + 1);
                pyramidLotSize = NormalizeDouble(pyramidLotSize, 2);
                
                ENUM_ORDER_TYPE orderType = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
                string comment = "Pyramid Layer " + IntegerToString(state.layer + 1);
                
                if(m_tradeManager.OpenPosition(symbol, orderType, pyramidLotSize, 0.0, 0.0, 0.0, comment, 0))
                {
                    PrintFormat("[PYRAMID] Added layer %d to %s | ticket=%d | lot=%.2f | profit=%.0f pips",
                                state.layer + 1, symbol, ticket, pyramidLotSize, profitPips);
                    
                    state.layer++;
                    state.nextStepPips = profitPips + m_pyramidingStepPips;
                    m_pyramidStates[stateIdx] = state;
                }
            }
        }
        
        CleanupPyramidStates();
    }
    
    void CleanupPyramidStates()
    {
        int write = 0;
        for(int i = 0; i < m_pyramidStateCount; i++)
        {
            if(!m_pyramidStates[i].active)
            {
                continue;
            }
            
            // Check if base position still exists
            bool positionExists = false;
            for(int j = 0; j < PositionsTotal(); j++)
            {
                ulong ticket = PositionGetTicket(j);
                if(ticket == m_pyramidStates[i].baseTicket)
                {
                    positionExists = true;
                    break;
                }
            }
            
            if(!positionExists)
            {
                PrintFormat("[PYRAMID] Base position %d closed, releasing pyramid state", m_pyramidStates[i].baseTicket);
                m_pyramidStates[i].active = false;
                continue;
            }
            
            if(write != i)
                m_pyramidStates[write] = m_pyramidStates[i];
            write++;
        }
        m_pyramidStateCount = write;
    }
    
    // --- Dynamic SL/TP ---
    void ManageDynamicSLTP()
    {
        if(!m_dynamicSLEnabled) return;
        
        UpdateVolatilityRegimes();
        
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(!IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC))) continue;
            
            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentSL = PositionGetDouble(POSITION_SL);
            double currentTP = PositionGetDouble(POSITION_TP);
            
            SVolatilityRegime regime = GetVolatilityRegime(symbol);
            if(regime.atr14 <= 0) continue;
            
            double slMult = m_dynamicSLATRMultiplier;
            double tpMult = m_dynamicTPATRMultiplier;
            
            if(m_volatilitySLAdjustEnabled)
            {
                if(regime.regime == 0) slMult *= 0.8;
                else if(regime.regime == 2) slMult *= 1.2;
            }
            
            double slDistance = regime.atr14 * slMult;
            double tpDistance = regime.atr14 * tpMult;
            
            double newSL = 0, newTP = 0;
            if(type == POSITION_TYPE_BUY)
            {
                newSL = openPrice - slDistance;
                newTP = openPrice + tpDistance;
            }
            else
            {
                newSL = openPrice + slDistance;
                newTP = openPrice - tpDistance;
            }
            
            int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
            newSL = NormalizeDouble(newSL, digits);
            newTP = NormalizeDouble(newTP, digits);
            
            double slDiff = MathAbs(newSL - currentSL);
            double tpDiff = MathAbs(newTP - currentTP);
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            if(point <= 0) point = 0.00001;
            
            if(slDiff > 10 * point || tpDiff > 10 * point || currentSL == 0 || currentTP == 0)
            {
                m_tradeManager.ModifyPosition(ticket, newSL, newTP);
                PrintFormat("[DYNAMIC-SLTP] %s | ticket=%d | SL=%.5f->%.5f | TP=%.5f->%.5f | ATR=%.5f | regime=%d",
                            symbol, ticket, currentSL, newSL, currentTP, newTP, regime.atr14, regime.regime);
            }
        }
    }
    
    // --- Loss Minimization ---
    void ManageLossMinimization()
    {
        if(!m_adverseMomentumExitEnabled && m_consecutiveLossLimit <= 0) return;
        
        datetime now = TimeCurrent();
        
        // Check consecutive loss cooldown
        if(m_consecutiveLossCooldownUntil > 0 && now < m_consecutiveLossCooldownUntil)
            return;
        
        // Check daily loss circuit breaker
        if(m_dailyRiskBudget > 0 && m_dailyLossAmount >= m_dailyRiskBudget * (m_dailyLossCircuitBreakerPercent / 100.0))
        {
            PrintFormat("[LOSS-MIN] Daily loss circuit breaker triggered: %.2f%% of budget used",
                        m_dailyLossAmount / m_dailyRiskBudget * 100.0);
            return;
        }
        
        // Check consecutive losses
        if(m_consecutiveLossCount >= m_consecutiveLossLimit)
        {
            PrintFormat("[LOSS-MIN] Consecutive loss limit reached (%d). Cooling down for %d sec",
                        m_consecutiveLossCount, m_consecutiveLossCooldownSec);
            m_consecutiveLossCooldownUntil = now + m_consecutiveLossCooldownSec;
            return;
        }
        
        // Check individual position loss limits
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(!IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC))) continue;
            
            double profit = PositionGetDouble(POSITION_PROFIT);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double slPrice = PositionGetDouble(POSITION_SL);
            
            if(slPrice > 0)
            {
                double slDistance = MathAbs(openPrice - slPrice);
                double currentDrawdown = MathAbs(openPrice - currentPrice);
                double lossPercent = (slDistance > 0) ? (currentDrawdown / slDistance) * 100.0 : 0;
                
                if(lossPercent >= m_positionLossLimitPercent)
                {
                    string sym = PositionGetString(POSITION_SYMBOL);
                    PrintFormat("[LOSS-MIN] Position %d on %s hit position loss limit: %.1f%% > %.1f%%",
                                ticket, sym, lossPercent, m_positionLossLimitPercent);
                    m_tradeManager.ClosePosition(ticket, "Position Loss Limit");
                }
            }
        }
    }
    
    // --- Partial Profit Taking ---
    void ManagePartialProfitTaking()
    {
        if(!m_partialProfitTakingEnabled) return;
        
        // Implementation would check if position has moved X ATR in favor
        // and close partial percentage
    }
    
    // --- Magic number check ---
    bool IsEAOwnedMagic(long magic) const
    {
        int maxMagic = m_magicNumber + 10000; // Approximate range
        return (magic >= m_magicNumber && magic <= maxMagic);
    }

public:
    CPositionManager() : 
        m_tradeManager(NULL), m_regimeEngine(NULL), m_riskTierManager(NULL),
        m_safeMode(NULL), m_fullMarginMode(NULL), m_slGuard(NULL),
        m_enabled(true), m_breakevenBufferPts(120.0), m_trailingDistancePts(300.0),
        m_trailingStepPoints(5), m_useATRTrailing(false), m_atrMultiplier(1.5),
        m_magicNumber(0), m_lastManageTimeMs(0),
        m_sreEnabled(true), m_sreMinConfidence(0.58), m_sreProfitGuard(true),
        m_sreMinLossR(0.25), m_sreMaxLossR(0.82), m_sreMinTimeSec(45),
        m_structuralInvalidationEnabled(true),
        m_pyramidingEnabled(false), m_pyramidingStepPips(50.0), m_pyramidingSizeMultiplier(1.5),
        m_pyramidingMaxLayers(3),
        m_dynamicSLEnabled(false), m_dynamicSLATRMultiplier(1.5), m_dynamicTPATRMultiplier(3.0),
        m_volatilitySLAdjustEnabled(false),
        m_adverseMomentumExitEnabled(false), m_adverseMomentumATRMultiplier(0.5),
        m_consecutiveLossLimit(3), m_consecutiveLossCooldownSec(1800),
        m_dailyLossCircuitBreakerPercent(50.0), m_positionLossLimitPercent(75.0),
        m_partialProfitTakingEnabled(false), m_partialProfitATRMultiplier(1.0),
        m_partialProfitPercent(25.0),
        m_pyramidStateCount(0), m_volatilityRegimeCount(0),
        m_consecutiveLossCount(0), m_lastLossTime(0), m_consecutiveLossCooldownUntil(0),
        m_dailyLossAmount(0.0), m_dailyRiskBudget(0.0), m_dailyResetTime(0)
    {
        ArrayResize(m_pyramidStates, 0);
        ArrayResize(m_volatilityRegimes, 0);
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
        if(tm == NULL || regime == NULL || rtm == NULL)
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
        m_sreEnabled = enabled; m_sreMinConfidence = minConf; m_sreProfitGuard = profitGuard;
        m_sreMinLossR = minLossR; m_sreMaxLossR = maxLossR; m_sreMinTimeSec = minTimeSec;
        m_structuralInvalidationEnabled = structuralInv;
    }
    
    void ConfigureLifecycle(bool enabled, double beBuffer, double trailDist, int trailStep, bool useATR, double atrMult)
    {
        m_enabled = enabled; m_breakevenBufferPts = beBuffer; m_trailingDistancePts = trailDist;
        m_trailingStepPoints = trailStep; m_useATRTrailing = useATR; m_atrMultiplier = atrMult;
    }
    
    void ConfigurePyramiding(bool enabled, double stepPips, double sizeMult, int maxLayers)
    {
        m_pyramidingEnabled = enabled; m_pyramidingStepPips = stepPips;
        m_pyramidingSizeMultiplier = sizeMult; m_pyramidingMaxLayers = maxLayers;
    }
    
    void ConfigureDynamicSL(bool enabled, double slMult, double tpMult, bool volAdjust)
    {
        m_dynamicSLEnabled = enabled; m_dynamicSLATRMultiplier = slMult;
        m_dynamicTPATRMultiplier = tpMult; m_volatilitySLAdjustEnabled = volAdjust;
    }
    
    void ConfigureLossMinimization(bool adverseExit, double adverseMult, int consecLimit, int consecCooldown, double dailyCB, double posLimit)
    {
        m_adverseMomentumExitEnabled = adverseExit; m_adverseMomentumATRMultiplier = adverseMult;
        m_consecutiveLossLimit = consecLimit; m_consecutiveLossCooldownSec = consecCooldown;
        m_dailyLossCircuitBreakerPercent = dailyCB; m_positionLossLimitPercent = posLimit;
    }
    
    void ConfigurePartialProfitTaking(bool enabled, double atrMult, double percent)
    {
        m_partialProfitTakingEnabled = enabled; m_partialProfitATRMultiplier = atrMult; m_partialProfitPercent = percent;
    }
    
    void SetDailyRiskBudget(double budget)
    {
        m_dailyRiskBudget = budget;
        m_dailyResetTime = StringToTime(TimeToString(TimeCurrent() + 86400, TIME_DATE));
    }
    
    // Main entry point - call from OnTick or OnTimer
    void ManagePositions()
    {
        if(!m_enabled || PositionsTotal() <= 0)
            return;
        
        // Reset daily loss tracking on new day
        datetime now = TimeCurrent();
        if(now >= m_dailyResetTime)
        {
            m_dailyLossAmount = 0.0;
            m_dailyResetTime = StringToTime(TimeToString(now + 86400, TIME_DATE));
        }
        
        CheckSignalReversalExit();
        ManageBreakevenAndTrailing();
        
        if(m_pyramidingEnabled)
            ManagePyramiding();
        
        if(m_dynamicSLEnabled)
            ManageDynamicSLTP();
        
        if(m_adverseMomentumExitEnabled || m_consecutiveLossLimit > 0)
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
        if(profit < 0)
        {
            m_consecutiveLossCount++;
            m_lastLossTime = TimeCurrent();
            m_dailyLossAmount += MathAbs(profit);
        }
        else
        {
            m_consecutiveLossCount = 0;
        }
    }
    
    // Diagnostics
    string GetStatusReport() const
    {
        string report = "[PositionManager] ";
        report += "Enabled=" + (m_enabled ? "Y" : "N");
        report += " | Pyramid=" + (m_pyramidingEnabled ? "Y" : "N");
        report += " | DynamicSL=" + (m_dynamicSLEnabled ? "Y" : "N");
        report += " | LossMin=" + (m_adverseMomentumExitEnabled ? "Y" : "N");
        report += " | SRE=" + (m_sreEnabled ? "Y" : "N");
        report += " | ConsecLoss=" + IntegerToString(m_consecutiveLossCount);
        report += " | DailyLoss=" + DoubleToString(m_dailyLossAmount, 2);
        report += " | PyramidStates=" + IntegerToString(m_pyramidStateCount);
        report += " | VolRegimes=" + IntegerToString(m_volatilityRegimeCount);
        return report;
    }
};

#endif // CORE_POSITION_POSITION_MANAGER_MQH