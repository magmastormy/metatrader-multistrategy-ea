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
        m_regimeEngine(NULL)
    {}

    ~CPositionLifecycleManager() {}

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
                    double newSL = NormalizeDouble(openPrice + buffer * 0.1, (int)SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_DIGITS));
                    if(newSL > currentSL)
                    {
                        m_tradeManager.ModifyPosition(ticket, newSL, PositionGetDouble(POSITION_TP));
                        PrintFormat("[SL-GUARD] BE applied in RANGE | %s | ticket=%d | SL=%.5f",
                                    PositionGetString(POSITION_SYMBOL), ticket, newSL);
                    }
                }
                else if(!isBuy && currentPrice <= openPrice - buffer && (currentSL > openPrice || currentSL == 0))
                {
                    double newSL = NormalizeDouble(openPrice - buffer * 0.1, (int)SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_DIGITS));
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
};

#endif // __POSITION_LIFECYCLE_MANAGER_MQH__
