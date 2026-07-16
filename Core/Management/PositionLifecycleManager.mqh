//+------------------------------------------------------------------+
//| PositionLifecycleManager.mqh                                      |
//| Encapsulates position lifecycle management extracted from          |
//| MultiStrategyAutonomousEA.mq5 ManageOpenPositionsIfNeeded()       |
//| Blueprint Section 10.1 — Monolith Decomposition (R6a)            |
//+------------------------------------------------------------------+
#ifndef POSITION_LIFECYCLE_MANAGER_MQH
#define POSITION_LIFECYCLE_MANAGER_MQH

#include "..\Utils\Enums.mqh"
#include "..\Trading\TradeManager.mqh"
#include "..\Management\EnterpriseStrategyManager.mqh"
#include "..\Cache\ConsensusCache.mqh"
#include "..\Risk\RiskTierManager.mqh"
#include "..\Risk\SafeModeConfig.mqh"
#include "..\Trading\IntelligentSLGuard.mqh"
#include "..\..\IndicatorManager.mqh"

// AGGRESSIVE: Pyramid state tracking
// NOTE: Using 'class' (not 'struct') because MQL5 does not allow pointers
// to 'struct' types (error 299: "class type expected"). Only class-typed
// objects may be referenced by pointer.
class CPyramidState
{
public:
    int    layer;              // Current pyramid layer (0 = base position)
    double entryPrice;         // Entry price of base position
    double nextStepPips;       // Profit threshold for next pyramid layer
    double baseLotSize;        // Base lot size for calculating pyramid layers
    ulong  baseTicket;         // Base position ticket
    bool   active;             // Whether pyramiding is active for this position

    CPyramidState(void)
    {
        layer = 0;
        entryPrice = 0.0;
        nextStepPips = 0.0;
        baseLotSize = 0.0;
        baseTicket = 0;
        active = false;
    }
};

// AGGRESSIVE: Volatility regime tracking
class CVolatilityRegime
{
public:
    string   symbol;       // Symbol this regime belongs to
    double   atr14;
    double   atr50;
    double   atrRatio;
    int      regime;       // 0=low, 1=normal, 2=high
    datetime lastUpdate;

    CVolatilityRegime(void)
    {
        symbol = "";
        atr14 = 0.0;
        atr50 = 0.0;
        atrRatio = 1.0;
        regime = 1;
        lastUpdate = 0;
    }
};

class CPositionLifecycleManager
{
private:
    CTradeManager*              m_tradeManager;
    CEnterpriseStrategyManager* m_managers[];      // per-symbol (not owned)
    string                      m_symbols[];       // parallel symbol names (CEnterpriseStrategyManager has no GetSymbol())
    CConsensusCache*            m_consensusCache;
    CRiskTierManager*           m_riskTierManager;
    CSafeMode*                  m_safeMode;
    int                         m_symbolCount;
    bool                        m_initialized;
    uint                        m_lastManageTimeMs;

    // SRE config
    bool   m_sreEnabled;
    double m_sreMinConfidence;
    bool   m_sreProfitGuard;
    double m_sreMinLossR;
    double m_sreMaxLossR;
    int    m_sreMinTimeSec;
    bool   m_structuralInvalidationEnabled;

    // Lifecycle config
    bool   m_lifecycleEnabled;
    double m_breakevenBufferPts;
    double m_trailingDistancePts;
    int    m_trailingStepPoints;
    bool   m_useATRTrailing;
    double m_atrMultiplier;

    // Magic number for position filtering
    int    m_magicNumber;

    // I2: Intelligent SL Guard
    CIntelligentSLGuard m_slGuard;
    CRegimeEngine*      m_regimeEngine;

    // AGGRESSIVE: Pyramiding config
    bool   m_pyramidingEnabled;
    double m_pyramidingStepPips;
    double m_pyramidingSizeMultiplier;
    int    m_pyramidingMaxLayers;

    // AGGRESSIVE: Dynamic SL/TP config
    bool   m_dynamicSLEnabled;
    double m_dynamicSLATRMultiplier;
    double m_dynamicTPATRMultiplier;
    bool   m_volatilitySLAdjustEnabled;

    // EXECUTION REFINEMENT: Partial profit taking config
    bool   m_partialProfitTakingEnabled;
    double m_partialProfitATRMultiplier;
    double m_partialProfitPercent;

    CPyramidState*      m_pyramidStates[];  // Array indexed by position ticket
    int                  m_pyramidStateCount;

    CVolatilityRegime*  m_volatilityRegimes[];  // Per-symbol volatility regime
    int                  m_volatilityRegimeCount;

    // EXECUTION REFINEMENT: Loss minimization config
    bool   m_adverseMomentumExitEnabled;
    double m_adverseMomentumATRMultiplier;
    int    m_consecutiveLossLimit;
    int    m_consecutiveLossCooldownSec;
    double m_dailyLossCircuitBreakerPercent;
    double m_positionLossLimitPercent;

    // EXECUTION REFINEMENT: Loss tracking
    int     m_consecutiveLossCount;
    datetime m_lastLossTime;
    datetime m_consecutiveLossCooldownUntil;
    double  m_dailyLossAmount;
    double  m_dailyRiskBudget;
    datetime m_dailyResetTime;

    // Issue #44: Maximum position hold time config
    bool   m_maxHoldTimeEnabled;
    int    m_maxHoldHoursIntraday;   // Max hold time for intraday (H1 and lower) — default 24h
    int    m_maxHoldHoursSwing;      // Max hold time for swing (H4 and higher) — default 120h (5 days)
    bool   m_maxHoldOnlyIfLoss;      // Only close if position is in loss (default true)

public:
    CPositionLifecycleManager() :
        m_tradeManager(NULL),
        m_consensusCache(NULL),
        m_riskTierManager(NULL),
        m_safeMode(NULL),
        m_symbolCount(0),
        m_initialized(false),
        m_lastManageTimeMs(0),
        m_sreEnabled(true),
        m_sreMinConfidence(0.58),
        m_sreProfitGuard(true),
        m_sreMinLossR(0.25),
        m_sreMaxLossR(0.82),
        m_sreMinTimeSec(45),
        m_structuralInvalidationEnabled(true),
        m_lifecycleEnabled(true),
        m_breakevenBufferPts(120.0),
        m_trailingDistancePts(300.0),
        m_trailingStepPoints(5),
        m_useATRTrailing(false),
        m_atrMultiplier(1.5),
        m_magicNumber(0),
        m_regimeEngine(NULL),
        m_pyramidingEnabled(false),
        m_pyramidingStepPips(50.0),
        m_pyramidingSizeMultiplier(1.5),
        m_pyramidingMaxLayers(3),
        m_dynamicSLEnabled(false),
        m_dynamicSLATRMultiplier(1.5),
        m_dynamicTPATRMultiplier(3.0),
        m_volatilitySLAdjustEnabled(false),
        m_partialProfitTakingEnabled(false),
        m_partialProfitATRMultiplier(1.0),
        m_partialProfitPercent(25.0),
        m_pyramidStateCount(0),
        m_volatilityRegimeCount(0),
        m_adverseMomentumExitEnabled(false),
        m_adverseMomentumATRMultiplier(0.5),
        m_consecutiveLossLimit(3),
        m_consecutiveLossCooldownSec(1800),
        m_dailyLossCircuitBreakerPercent(50.0),
        m_positionLossLimitPercent(75.0),
        m_consecutiveLossCount(0),
        m_lastLossTime(0),
        m_consecutiveLossCooldownUntil(0),
        m_dailyLossAmount(0.0),
        m_dailyRiskBudget(0.0),
        m_dailyResetTime(0),
        m_maxHoldTimeEnabled(true),
        m_maxHoldHoursIntraday(24),
        m_maxHoldHoursSwing(120),
        m_maxHoldOnlyIfLoss(true)
    {}

    ~CPositionLifecycleManager()
    {
        // Clean up pyramid states
        for(int i = 0; i < m_pyramidStateCount; i++)
        {
            if(CheckPointer(m_pyramidStates[i]) == POINTER_DYNAMIC)
                delete m_pyramidStates[i];
        }
        m_pyramidStateCount = 0;
        ArrayFree(m_pyramidStates);

        // Clean up volatility regimes
        for(int i = 0; i < m_volatilityRegimeCount; i++)
        {
            if(CheckPointer(m_volatilityRegimes[i]) == POINTER_DYNAMIC)
                delete m_volatilityRegimes[i];
        }
        m_volatilityRegimeCount = 0;
        ArrayFree(m_volatilityRegimes);
    }

    bool Initialize(CTradeManager* tm, CConsensusCache* cache,
                    CRiskTierManager* rtm, CSafeMode* sm, int magicNumber)
    {
        if(tm == NULL || cache == NULL || rtm == NULL)
            return false;
        m_tradeManager = tm;
        m_consensusCache = cache;
        m_riskTierManager = rtm;
        m_safeMode = sm;
        m_magicNumber = magicNumber;
        m_initialized = true;
        return true;
    }

    void SetManagers(CEnterpriseStrategyManager* &managers[], string &symbols[], int count)
    {
        ArrayResize(m_managers, count);
        ArrayResize(m_symbols, count);
        for(int i = 0; i < count; i++)
        {
            m_managers[i] = managers[i];
            m_symbols[i]  = symbols[i];
        }
        m_symbolCount = count;
    }

    void ConfigureSRE(bool enabled, double minConf, bool profitGuard,
                      double minLossR, double maxLossR, int minTimeSec,
                      bool structuralInvalidation)
    {
        m_sreEnabled = enabled;
        m_sreMinConfidence = minConf;
        m_sreProfitGuard = profitGuard;
        m_sreMinLossR = minLossR;
        m_sreMaxLossR = maxLossR;
        m_sreMinTimeSec = minTimeSec;
        m_structuralInvalidationEnabled = structuralInvalidation;
    }

    void ConfigureLifecycle(bool enabled, double breakevenBuffer, double trailingDistance,
                           int trailingStep, bool useATR, double atrMult)
    {
        m_lifecycleEnabled = enabled;
        m_breakevenBufferPts = breakevenBuffer;
        m_trailingDistancePts = trailingDistance;
        m_trailingStepPoints = trailingStep;
        m_useATRTrailing = useATR;
        m_atrMultiplier = atrMult;
    }

    // AGGRESSIVE: Configure pyramiding
    void ConfigurePyramiding(bool enabled, double stepPips, double sizeMultiplier, int maxLayers)
    {
        m_pyramidingEnabled = enabled;
        m_pyramidingStepPips = stepPips;
        m_pyramidingSizeMultiplier = sizeMultiplier;
        m_pyramidingMaxLayers = maxLayers;
    }

    // AGGRESSIVE: Configure dynamic SL/TP
    void ConfigureDynamicSL(bool enabled, double slATRMultiplier, double tpATRMultiplier, bool volAdjust)
    {
        m_dynamicSLEnabled = enabled;
        m_dynamicSLATRMultiplier = slATRMultiplier;
        m_dynamicTPATRMultiplier = tpATRMultiplier;
        m_volatilitySLAdjustEnabled = volAdjust;
    }

    // EXECUTION REFINEMENT: Configure loss minimization
    void ConfigureLossMinimization(bool adverseMomentumExit, double adverseMomentumATR,
                                   int consecutiveLossLimit, int consecutiveLossCooldown,
                                   double dailyLossCircuitBreaker, double positionLossLimit)
    {
        m_adverseMomentumExitEnabled = adverseMomentumExit;
        m_adverseMomentumATRMultiplier = adverseMomentumATR;
        m_consecutiveLossLimit = consecutiveLossLimit;
        m_consecutiveLossCooldownSec = consecutiveLossCooldown;
        m_dailyLossCircuitBreakerPercent = dailyLossCircuitBreaker;
        m_positionLossLimitPercent = positionLossLimit;
    }

    // EXECUTION REFINEMENT: Configure partial profit taking
    void ConfigurePartialProfitTaking(bool enabled, double atrMultiplier, double profitPercent)
    {
        m_partialProfitTakingEnabled = enabled;
        m_partialProfitATRMultiplier = atrMultiplier;
        m_partialProfitPercent = profitPercent;
    }

    // Issue #44: Configure maximum position hold time
    void ConfigureMaxHoldTime(bool enabled, int maxHoldHoursIntraday, int maxHoldHoursSwing, bool onlyIfLoss)
    {
        m_maxHoldTimeEnabled = enabled;
        m_maxHoldHoursIntraday = maxHoldHoursIntraday;
        m_maxHoldHoursSwing = maxHoldHoursSwing;
        m_maxHoldOnlyIfLoss = onlyIfLoss;
    }

    bool IsInitialized() const { return m_initialized; }

    void SetRegimeEngine(CRegimeEngine* engine) { m_regimeEngine = engine; }

    //--- Check if a magic number falls within this EA's ownership range
    //--- Range: [m_magicNumber, m_magicNumber + symbolCount*100 + 99]
    bool IsEAOwnedMagic(long magic) const
    {
        int maxMagic = m_magicNumber + m_symbolCount * 100 + 99;
        return (magic >= m_magicNumber && magic <= maxMagic);
    }

    //--- Get enterprise manager for a symbol
    CEnterpriseStrategyManager* GetManagerForSymbol(const string symbol)
    {
        for(int i = 0; i < m_symbolCount; i++)
        {
            if(m_managers[i] != NULL && m_symbols[i] == symbol)
                return m_managers[i];
        }
        return NULL;
    }

    //--- Main entry point — replaces ManageOpenPositionsIfNeeded()
    void ManagePositions()
    {
        if(!m_initialized || PositionsTotal() <= 0)
            return;

        CheckSignalReversalExit();
        ManageBreakevenAndTrailing();

        // AGGRESSIVE: Manage pyramiding
        if(m_pyramidingEnabled)
            ManagePyramiding();

        // AGGRESSIVE: Manage dynamic SL/TP
        if(m_dynamicSLEnabled)
            ManageDynamicSLTP();

        // EXECUTION REFINEMENT: Manage loss minimization
        if(m_adverseMomentumExitEnabled || m_consecutiveLossLimit > 0)
            ManageLossMinimization();

        // EXECUTION REFINEMENT: Manage partial profit taking
        if(m_partialProfitTakingEnabled)
            ManagePartialProfitTaking();

        // Issue #44: Manage maximum position hold time
        if(m_maxHoldTimeEnabled)
            ManageMaxHoldTime();
    }

    //--- Signal Reversal Exit (SRE) — high-speed scalp logic
    bool CheckSignalReversalExit()
    {
        if(!m_sreEnabled)
            return false;

        bool anyReversal = false;

        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(!IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC))) continue;

            string sym = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

            CEnterpriseStrategyManager* manager = GetManagerForSymbol(sym);
            if(manager == NULL) continue;

            double confidence = 0;
            int confluence = 0;
            ENUM_TRADE_SIGNAL currentSignal;
            if(!m_consensusCache.TryGet(sym, EVAL_MODE_INTRABAR, currentSignal, confidence, confluence))
            {
                currentSignal = manager.GetConsensusSignalForSymbolWithConfluenceMode(sym, confidence, confluence, EVAL_MODE_INTRABAR);
                m_consensusCache.Store(sym, EVAL_MODE_INTRABAR, currentSignal, confidence, confluence);
            }

            bool reversalDetected = false;
            bool isBuy = (type == POSITION_TYPE_BUY);
            bool opposingSignal = (isBuy && currentSignal == TRADE_SIGNAL_SELL) || (!isBuy && currentSignal == TRADE_SIGNAL_BUY);

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
                        static datetime lastLastStandLog = 0;
                        if(TimeCurrent() - lastLastStandLog > 60)
                        {
                            PrintFormat("[SRE-LAST-STAND] %s | ignoring reversal signal | lossR=%.2f exceeds %.2f | Let hard SL decide", sym, lossR, m_sreMaxLossR);
                            lastLastStandLog = TimeCurrent();
                        }
                    }
                    else
                    {
                        if(!hasBreathingRoom || lossR > 0.50)
                        {
                            // Issue 9 fix: SRE profit guard — only trigger signal reversal
                            // exit when position is in profit or still near entry. If the
                            // position has drifted deep into loss (>25% of SL distance),
                            // skip SRE and let structural invalidation or hard SL decide.
                            bool profitGuardBlocked = false;
                            if(m_sreProfitGuard && inLoss)
                            {
                                if(lossR > 0.25)
                                {
                                    profitGuardBlocked = true;
                                    static datetime s_lastProfitGuardLog = 0;
                                    if(TimeCurrent() - s_lastProfitGuardLog > 60)
                                    {
                                        PrintFormat("[SRE-PROFIT-GUARD] %s | blocking SRE | in loss, lossR=%.2f > 0.25 threshold | letting SL/structural decide",
                                                    sym, lossR);
                                        s_lastProfitGuardLog = TimeCurrent();
                                    }
                                }
                            }
                            if(!profitGuardBlocked)
                                reversalDetected = true;
                        }
                    }
                }

                if(m_structuralInvalidationEnabled && !reversalDetected)
                {
                    SConsensusDecisionContext context;
                    if(manager.GetLastDecisionContext(context))
                    {
                        if(context.dominantCluster == STRUCTURE_CLUSTER && confidence >= 0.45)
                        {
                            if(lossR > 0.10 || !inLoss)
                            {
                                PrintFormat("[STRUCTURAL-EXIT] %s | trend invalidated | conf=%.2f | lossR=%.2f", sym, confidence, lossR);
                                reversalDetected = true;
                            }
                        }
                    }
                }
            }

            if(reversalDetected)
            {
                PrintFormat("[SCALP-EXIT] Reversal detected on %s | type=%s | signal=%s | conf=%.2f",
                            sym, EnumToString(type), EnumToString(currentSignal), confidence);
                m_tradeManager.ClosePosition(ticket, "Signal Reversal");
                anyReversal = true;
            }
        }

        return anyReversal;
    }

    //--- Breakeven and trailing stop management
    void ManageBreakevenAndTrailing()
    {
        if(!m_lifecycleEnabled)
            return;

        uint nowMs = GetTickCount();
        if(m_lastManageTimeMs != 0 && (nowMs - m_lastManageTimeMs) < 500)
            return;

        // I2: Check regime state — pause trailing in ranging markets
        bool pauseTrailing = false;
        if(m_regimeEngine != NULL)
        {
            SRegimeSnapshot snap = m_regimeEngine.GetSnapshot();
            if(snap.state == REGIME_RANGE)
            {
                pauseTrailing = true;
            }
        }

        if(pauseTrailing)
        {
            // In ranging regime, only allow breakeven moves (free money), skip trailing
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

                // Only move to breakeven — no trailing in ranging market
                if(isBuy && currentPrice >= openPrice + buffer && (currentSL < openPrice || currentSL == 0))
                {
                    // Batch 116: SL at openPrice + buffer (full offset), not buffer * 0.1
                    double newSL = NormalizeDouble(openPrice + buffer, (int)SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_DIGITS));
                    if(newSL > currentSL)
                    {
                        m_tradeManager.ModifyPosition(ticket, newSL, PositionGetDouble(POSITION_TP));
                        PrintFormat("[SL-GUARD] BE applied in RANGE | %s | ticket=%d | SL=%.5f",
                                    PositionGetString(POSITION_SYMBOL), ticket, newSL);
                    }
                }
                else if(!isBuy && currentPrice <= openPrice - buffer && (currentSL > openPrice || currentSL == 0))
                {
                    // Batch 116: SL at openPrice - buffer (full offset), not buffer * 0.1
                    double newSL = NormalizeDouble(openPrice - buffer, (int)SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_DIGITS));
                    if(newSL < currentSL || currentSL == 0)
                    {
                        m_tradeManager.ModifyPosition(ticket, newSL, PositionGetDouble(POSITION_TP));
                        PrintFormat("[SL-GUARD] BE applied in RANGE | %s | ticket=%d | SL=%.5f",
                                    PositionGetString(POSITION_SYMBOL), ticket, newSL);
                    }
                }
            }
        }
        else
        {
            // Normal mode — full BE + trailing
            m_tradeManager.ManageAllPositions(m_breakevenBufferPts,
                                              m_trailingDistancePts,
                                              m_trailingStepPoints,
                                              m_useATRTrailing,
                                              m_atrMultiplier);
        }

        // Safe mode partial profit taking for swing positions
        if(m_riskTierManager.GetCurrentTier() == RISK_TIER_CONSERVATIVE && m_safeMode != NULL && m_safeMode.IsInitialized())
        {
            m_safeMode.ManageSafeModePositions(m_tradeManager);
        }

        m_lastManageTimeMs = nowMs;
    }

    // AGGRESSIVE: Pyramiding management
    void ManagePyramiding()
    {
        if(!m_pyramidingEnabled)
            return;

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

            // Calculate profit in pips
            double profitPips = 0.0;
            if(type == POSITION_TYPE_BUY)
                profitPips = (currentPrice - openPrice) / point;
            else
                profitPips = (openPrice - currentPrice) / point;

            // Find or create pyramid state for this position
            CPyramidState* state = GetPyramidState(ticket);
            if(state == NULL)
            {
                // Initialize pyramid state for new position
                state = CreatePyramidState(ticket, openPrice, lotSize);
                if(state == NULL) continue;
            }

            // Check if we should add a pyramid layer
            if(state.active && state.layer < m_pyramidingMaxLayers && profitPips >= state.nextStepPips)
            {
                // Calculate pyramid lot size
                double pyramidLotSize = state.baseLotSize * MathPow(m_pyramidingSizeMultiplier, state.layer + 1);
                pyramidLotSize = NormalizeDouble(pyramidLotSize, 2);

                // Send pyramid order
                ENUM_ORDER_TYPE orderType = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
                string comment = "Pyramid Layer " + IntegerToString(state.layer + 1);
                double entryPriceZero = 0.0;
                double slPipsZero = 0.0;
                double tpPipsZero = 0.0;
                uint magicZero = 0;
                if(m_tradeManager.OpenPosition(symbol, orderType, pyramidLotSize, entryPriceZero, slPipsZero, tpPipsZero, comment, magicZero))
                {
                    PrintFormat("[PYRAMID] Added layer %d to %s | ticket=%d | lot=%.2f | profit=%.0f pips",
                                state.layer + 1, symbol, ticket, pyramidLotSize, profitPips);

                    // Update pyramid state
                    state.layer++;
                    state.nextStepPips = profitPips + m_pyramidingStepPips;
                }
            }
        }

        // Clean up pyramid states for closed positions
        CleanupPyramidStates();
    }

    // AGGRESSIVE: Get pyramid state for a position
    CPyramidState* GetPyramidState(ulong ticket)
    {
        for(int i = 0; i < m_pyramidStateCount; i++)
        {
            if(CheckPointer(m_pyramidStates[i]) == POINTER_DYNAMIC &&
               m_pyramidStates[i].baseTicket == ticket &&
               m_pyramidStates[i].active)
                return m_pyramidStates[i];
        }
        return NULL;
    }

    // AGGRESSIVE: Create pyramid state for new position
    CPyramidState* CreatePyramidState(ulong ticket, double entryPrice, double lotSize)
    {
        // Resize array if needed
        if(m_pyramidStateCount >= ArraySize(m_pyramidStates))
            ArrayResize(m_pyramidStates, m_pyramidStateCount + 10);

        CPyramidState* state = new CPyramidState();
        state.layer = 0;
        state.entryPrice = entryPrice;
        state.nextStepPips = m_pyramidingStepPips;
        state.baseLotSize = lotSize;
        state.baseTicket = ticket;
        state.active = true;

        m_pyramidStates[m_pyramidStateCount] = state;
        m_pyramidStateCount++;
        return state;
    }

    // AGGRESSIVE: Clean up pyramid states for closed positions
    void CleanupPyramidStates()
    {
        int write = 0;
        for(int i = 0; i < m_pyramidStateCount; i++)
        {
            if(CheckPointer(m_pyramidStates[i]) != POINTER_DYNAMIC)
            {
                // Skip invalid entries, free slot
                continue;
            }

            if(!m_pyramidStates[i].active)
            {
                // Already marked inactive, remove
                delete m_pyramidStates[i];
                m_pyramidStates[i] = NULL;
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
                // Base position closed, free and drop
                PrintFormat("[PYRAMID] Base position %d closed, releasing pyramid state",
                            m_pyramidStates[i].baseTicket);
                delete m_pyramidStates[i];
                m_pyramidStates[i] = NULL;
                continue;
            }

            // Keep, compact
            if(write != i)
                m_pyramidStates[write] = m_pyramidStates[i];
            write++;
        }
        // Null out any remaining slots beyond `write`
        for(int i = write; i < m_pyramidStateCount; i++)
            m_pyramidStates[i] = NULL;
        m_pyramidStateCount = write;
    }

    // AGGRESSIVE: Dynamic SL/TP management
    void ManageDynamicSLTP()
    {
        if(!m_dynamicSLEnabled)
            return;

        // Update volatility regimes for all symbols
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

            // Get volatility regime for this symbol
            CVolatilityRegime* regime = GetVolatilityRegime(symbol);
            if(regime == NULL) continue;

            // Calculate dynamic SL/TP based on ATR
            double atr = regime.atr14;
            if(atr <= 0) continue;

            double slMultiplier = m_dynamicSLATRMultiplier;
            double tpMultiplier = m_dynamicTPATRMultiplier;

            // Adjust SL based on volatility regime
            if(m_volatilitySLAdjustEnabled)
            {
                if(regime.regime == 0) // Low volatility
                    slMultiplier *= 0.8;
                else if(regime.regime == 2) // High volatility
                    slMultiplier *= 1.2;
            }

            double slDistance = atr * slMultiplier;
            double tpDistance = atr * tpMultiplier;

            double newSL = 0.0;
            double newTP = 0.0;

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

            // Normalize to symbol digits
            int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
            newSL = NormalizeDouble(newSL, digits);
            newTP = NormalizeDouble(newTP, digits);

            // Only modify if significantly different (avoid excessive modifications)
            double slDiff = MathAbs(newSL - currentSL);
            double tpDiff = MathAbs(newTP - currentTP);
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            if(point <= 0) point = 0.00001;

            if(slDiff > 10 * point || tpDiff > 10 * point || currentSL == 0 || currentTP == 0)
            {
                if(m_tradeManager.ModifyPosition(ticket, newSL, newTP))
                {
                    PrintFormat("[DYNAMIC-SLTP] %s | ticket=%d | SL=%.5f -> %.5f | TP=%.5f -> %.5f | ATR=%.5f | regime=%d",
                                symbol, ticket, currentSL, newSL, currentTP, newTP, atr, regime.regime);
                }
            }
        }
    }

    // AGGRESSIVE: Update volatility regimes for all symbols
    void UpdateVolatilityRegimes()
    {
        datetime now = TimeCurrent();

        for(int i = 0; i < m_symbolCount; i++)
        {
            string symbol = m_symbols[i];

            // Find or create regime for this symbol
            CVolatilityRegime* regime = GetVolatilityRegime(symbol);
            if(regime == NULL)
            {
                regime = CreateVolatilityRegime(symbol);
                if(regime == NULL) continue;
            }

            // Update every 5 minutes to avoid excessive calculations
            if(now - regime.lastUpdate < 300) continue;

            // Get ATR values
            double atr14 = GetATR(symbol, 14);
            double atr50 = GetATR(symbol, 50);

            if(atr14 > 0 && atr50 > 0)
            {
                regime.atr14 = atr14;
                regime.atr50 = atr50;
                regime.atrRatio = atr14 / atr50;

                // Determine regime
                if(regime.atrRatio < 0.5)
                    regime.regime = 0; // Low volatility
                else if(regime.atrRatio > 1.5)
                    regime.regime = 2; // High volatility
                else
                    regime.regime = 1; // Normal volatility

                regime.lastUpdate = now;
            }
        }
    }

    // AGGRESSIVE: Get volatility regime for a symbol
    CVolatilityRegime* GetVolatilityRegime(const string symbol)
    {
        for(int i = 0; i < m_volatilityRegimeCount; i++)
        {
            if(CheckPointer(m_volatilityRegimes[i]) == POINTER_DYNAMIC &&
               m_volatilityRegimes[i].symbol == symbol)
                return m_volatilityRegimes[i];
        }
        return NULL;
    }

    // AGGRESSIVE: Create volatility regime for a symbol
    CVolatilityRegime* CreateVolatilityRegime(const string symbol)
    {
        // Resize array if needed
        if(m_volatilityRegimeCount >= ArraySize(m_volatilityRegimes))
            ArrayResize(m_volatilityRegimes, m_volatilityRegimeCount + 10);

        CVolatilityRegime* regime = new CVolatilityRegime();
        regime.symbol = symbol;
        // atr14/atr50/regime/ratio left as defaults; caller populates from data

        m_volatilityRegimes[m_volatilityRegimeCount] = regime;
        m_volatilityRegimeCount++;
        return regime;
    }

    // AGGRESSIVE: Get ATR value for a symbol using IndicatorManager
    double GetATR(const string symbol, int period)
    {
        CIndicatorManager* indManager = CIndicatorManager::Instance();
        if(indManager == NULL)
        {
            PrintFormat("[LIFECYCLE-ATR] ERROR: IndicatorManager not available for %s period=%d", symbol, period);
            return 0;
        }
        
        // Resolve PERIOD_CURRENT to actual chart timeframe
        ENUM_TIMEFRAMES actualTimeframe = Period();
        if(actualTimeframe == PERIOD_CURRENT || actualTimeframe == 0)
            actualTimeframe = PERIOD_M15;
        
        int atrHandle = indManager.GetATRHandle(symbol, actualTimeframe, period);
        if(atrHandle == INVALID_HANDLE)
        {
            PrintFormat("[LIFECYCLE-ATR] ERROR: Failed to get ATR handle for %s period=%d timeframe=%s",
                        symbol, period, EnumToString(actualTimeframe));
            return 0;
        }

        double atrBuffer[];
        ArraySetAsSeries(atrBuffer, true);
        if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) <= 0)
        {
            int err = GetLastError();
            PrintFormat("[LIFECYCLE-ATR] ERROR: CopyBuffer failed for %s period=%d timeframe=%s err=%d",
                        symbol, period, EnumToString(actualTimeframe), err);
            // Don't release handle - IndicatorManager manages lifecycle
            return 0;
        }

        double atr = atrBuffer[0];
        if(atr <= 0.0 || !MathIsValidNumber(atr))
        {
            PrintFormat("[LIFECYCLE-ATR] WARNING: Invalid ATR value %.5f for %s period=%d", atr, symbol, period);
            return 0;
        }
        return atr;
    }

    // EXECUTION REFINEMENT: Loss minimization management
    void ManageLossMinimization()
    {
        // Reset daily loss tracking at midnight
        datetime now = TimeCurrent();
        MqlDateTime dt;
        TimeToStruct(now, dt);
        datetime midnight = StringToTime(IntegerToString(dt.year) + "." + IntegerToString(dt.mon) + "." + IntegerToString(dt.day) + " 00:00:00");
        if(now >= midnight + 86400)  // Next day
        {
            m_dailyLossAmount = 0.0;
            m_dailyResetTime = midnight;
        }

        // Check consecutive loss cooldown
        if(m_consecutiveLossCooldownUntil > 0 && now < m_consecutiveLossCooldownUntil)
        {
            static datetime lastCooldownLog = 0;
            if(now - lastCooldownLog > 60)
            {
                PrintFormat("[LOSS-MIN] In consecutive loss cooldown | cooldown until %s", TimeToString(m_consecutiveLossCooldownUntil));
                lastCooldownLog = now;
            }
            return;  // Skip trading during cooldown
        }

        // Check daily loss circuit breaker
        if(m_dailyLossCircuitBreakerPercent > 0 && m_dailyRiskBudget > 0)
        {
            double dailyLossLimit = m_dailyRiskBudget * (m_dailyLossCircuitBreakerPercent / 100.0);
            if(m_dailyLossAmount >= dailyLossLimit)
            {
                static datetime lastCircuitLog = 0;
                if(now - lastCircuitLog > 60)
                {
                    PrintFormat("[LOSS-MIN] Daily loss circuit breaker triggered | loss=%.2f limit=%.2f | stopping trading",
                                m_dailyLossAmount, dailyLossLimit);
                    lastCircuitLog = now;
                }
                return;  // Stop trading for the day
            }
        }

        // Manage individual positions
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(!IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC))) continue;

            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double slPrice = PositionGetDouble(POSITION_SL);
            double currentProfit = PositionGetDouble(POSITION_PROFIT);

            // Adverse momentum exit
            if(m_adverseMomentumExitEnabled)
            {
                double atr = GetATR(symbol, 14);
                if(atr > 0)
                {
                    double adverseThreshold = atr * m_adverseMomentumATRMultiplier;
                    double priceMove = 0.0;

                    if(type == POSITION_TYPE_BUY)
                        priceMove = openPrice - currentPrice;
                    else
                        priceMove = currentPrice - openPrice;

                    if(priceMove > adverseThreshold && currentProfit < 0)
                    {
                        PrintFormat("[LOSS-MIN] Adverse momentum exit | ticket=%d | move=%.5f threshold=%.5f",
                                    ticket, priceMove, adverseThreshold);
                        m_tradeManager.ClosePosition(ticket, "Adverse Momentum");
                        m_consecutiveLossCount++;
                        m_lastLossTime = now;
                        m_dailyLossAmount += MathAbs(currentProfit);
                        continue;
                    }
                }
            }

            // Position loss limit
            if(m_positionLossLimitPercent > 0 && slPrice > 0)
            {
                double slDistance = MathAbs(openPrice - slPrice);
                double currentDrawdownLocal = MathAbs(openPrice - currentPrice);
                double lossRatio = (slDistance > 0) ? (currentDrawdownLocal / slDistance) : 0.0;

                if(lossRatio > (m_positionLossLimitPercent / 100.0) && currentProfit < 0)
                {
                    PrintFormat("[LOSS-MIN] Position loss limit exit | ticket=%d | lossRatio=%.2f limit=%.2f",
                                ticket, lossRatio, m_positionLossLimitPercent / 100.0);
                    m_tradeManager.ClosePosition(ticket, "Position Loss Limit");
                    m_consecutiveLossCount++;
                    m_lastLossTime = now;
                    m_dailyLossAmount += MathAbs(currentProfit);
                    continue;
                }
            }
        }

        // Check consecutive loss limit
        if(m_consecutiveLossLimit > 0 && m_consecutiveLossCount >= m_consecutiveLossLimit)
        {
            m_consecutiveLossCooldownUntil = now + m_consecutiveLossCooldownSec;
            PrintFormat("[LOSS-MIN] Consecutive loss limit reached | count=%d | cooldown for %d seconds",
                        m_consecutiveLossCount, m_consecutiveLossCooldownSec);
            m_consecutiveLossCount = 0;  // Reset after triggering cooldown
        }
    }

    // EXECUTION REFINEMENT: Partial profit taking management
    void ManagePartialProfitTaking()
    {
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(!IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC))) continue;

            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            double currentVolume = PositionGetDouble(POSITION_VOLUME);
            double currentTP = PositionGetDouble(POSITION_TP);

            // Skip if no TP set or already took partial profit
            if(currentTP == 0) continue;

            // Calculate profit distance
            double profitDistance = 0.0;
            if(type == POSITION_TYPE_BUY)
                profitDistance = currentPrice - openPrice;
            else
                profitDistance = openPrice - currentPrice;

            // Get ATR
            double atr = GetATR(symbol, 14);
            if(atr <= 0) continue;

            // Check if reached partial profit target
            double partialTarget = atr * m_partialProfitATRMultiplier;
            if(profitDistance >= partialTarget && currentVolume > 0.01)
            {
                // Calculate partial close amount
                double closeAmount = currentVolume * (m_partialProfitPercent / 100.0);
                closeAmount = NormalizeDouble(closeAmount, 2);

                if(closeAmount >= 0.01)
                {
                    PrintFormat("[PARTIAL-PROFIT] Taking partial profit | ticket=%d | amount=%.2f | profit=%.5f",
                                ticket, closeAmount, profitDistance);
                    m_tradeManager.ClosePositionPartial(ticket, closeAmount, "Partial Profit");
                }
            }
        }
    }

    // Issue #44: Maximum position hold time management
    void ManageMaxHoldTime()
    {
        if(!m_maxHoldTimeEnabled)
            return;

        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(!IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC))) continue;

            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
            double currentProfit = PositionGetDouble(POSITION_PROFIT);

            // Calculate hours open
            int hoursOpen = (int)((TimeCurrent() - openTime) / 3600);

            // Determine max hold time based on timeframe
            ENUM_TIMEFRAMES currentTF = (ENUM_TIMEFRAMES)Period();
            int maxHoldHours = (currentTF <= PERIOD_H1) ? m_maxHoldHoursIntraday : m_maxHoldHoursSwing;

            // Check if position exceeds max hold time
            if(hoursOpen > maxHoldHours)
            {
                // If only close on loss, check profit
                if(m_maxHoldOnlyIfLoss && currentProfit >= 0.0)
                {
                    continue; // Position is profitable, don't force close
                }

                PrintFormat("[TIME-EXIT] Position %d held for %d hours (max %d) on %s with profit %.2f - closing",
                            ticket, hoursOpen, maxHoldHours, symbol, currentProfit);
                m_tradeManager.ClosePosition(ticket, "Max Hold Time");
            }
        }
    }
};

#endif // __POSITION_LIFECYCLE_MANAGER_MQH__
