//+------------------------------------------------------------------+
//| RiskTierManager.mqh                                              |
//| Tiered position sizing: maps risk tier to risk/sizer/trade params |
//+------------------------------------------------------------------+
#ifndef CORE_RISK_RISK_TIER_MANAGER_MQH
#define CORE_RISK_RISK_TIER_MANAGER_MQH

#include "../Utils/Enums.mqh"
#include "UnifiedRiskManager.mqh"
#include "PositionSizer.mqh"
#include "../Trading/TradeManager.mqh"
#include "FullMarginMode.mqh"
#include "SafeModeConfig.mqh"

//+------------------------------------------------------------------+
//| Per-cluster risk allocation percentages                          |
//+------------------------------------------------------------------+
struct SClusterAllocation
{
   double trendPct;           // % of daily risk budget for TREND_CLUSTER
   double meanReversionPct;   // % of daily risk budget for MEAN_REVERSION_CLUSTER
   double structurePct;       // % of daily risk budget for STRUCTURE_CLUSTER
   double scalpPct;           // % of daily risk budget for SCALP_CLUSTER
};

//+------------------------------------------------------------------+
//| Per-tier configuration                                           |
//+------------------------------------------------------------------+
struct STierConfig
{
   double riskPerTradePct;      // Risk per trade as % of equity
   double dailyRiskPct;         // Max daily risk %
   double portfolioRiskPct;     // Max portfolio risk %
   int    maxPositions;         // Max concurrent positions
   double breakevenBufferPts;   // Points buffer for breakeven move
   double trailingDistancePts;  // Points for trailing stop distance
   double ddWarningPct;         // Drawdown warning threshold %
   double ddCriticalPct;        // Drawdown critical threshold %
   double minConfidence;        // Min consensus confidence for entry
   int    minVoters;            // Min live voters for consensus
   double maxSpreadATRRatio;    // Max spread/ATR ratio for entry
   double scalpBudgetPct;       // % of daily risk budget for scalps
   SClusterAllocation clusterAllocation; // Per-cluster risk allocation
};

//+------------------------------------------------------------------+
//| Risk Tier Manager                                                |
//+------------------------------------------------------------------+
class CRiskTierManager
{
private:
    ENUM_RISK_TIER m_tier;
    STierConfig    m_config;

    // Pre-defined tier presets
    static STierConfig GetConservativeConfig()
    {
        STierConfig c;
        c.riskPerTradePct     = 0.5;
        c.dailyRiskPct        = 2.0;
        c.portfolioRiskPct    = 6.0;
        c.maxPositions        = 3;
        c.breakevenBufferPts  = 80;
        c.trailingDistancePts = 200;
        c.ddWarningPct        = 3.0;
        c.ddCriticalPct       = 6.0;
        c.minConfidence       = 0.70;
        c.minVoters           = 3;
        c.maxSpreadATRRatio   = 0.15;
        c.scalpBudgetPct      = 0.0;
        c.clusterAllocation.trendPct         = 30.0;
        c.clusterAllocation.meanReversionPct = 30.0;
        c.clusterAllocation.structurePct     = 30.0;
        c.clusterAllocation.scalpPct         = 10.0;
        return c;
    }

    static STierConfig GetModerateConfig()
    {
        STierConfig c;
        c.riskPerTradePct     = 1.0;
        c.dailyRiskPct        = 5.0;
        c.portfolioRiskPct    = 15.0;
        c.maxPositions        = 5;
        c.breakevenBufferPts  = 120;
        c.trailingDistancePts = 300;
        c.ddWarningPct        = 5.0;
        c.ddCriticalPct       = 10.0;
        c.minConfidence       = 0.55;
        c.minVoters           = 2;
        c.maxSpreadATRRatio   = 0.20;
        c.scalpBudgetPct      = 3.0;
        c.clusterAllocation.trendPct         = 40.0;
        c.clusterAllocation.meanReversionPct = 25.0;
        c.clusterAllocation.structurePct     = 25.0;
        c.clusterAllocation.scalpPct         = 10.0;
        return c;
    }

    static STierConfig GetAggressiveConfig()
    {
        STierConfig c;
        c.riskPerTradePct     = 2.0;
        c.dailyRiskPct        = 10.0;
        c.portfolioRiskPct    = 30.0;
        c.maxPositions        = 8;
        c.breakevenBufferPts  = 100;
        c.trailingDistancePts = 250;
        c.ddWarningPct        = 8.0;
        c.ddCriticalPct       = 15.0;
        c.minConfidence       = 0.40;
        c.minVoters           = 2;
        c.maxSpreadATRRatio   = 0.25;
        c.scalpBudgetPct      = 8.0;
        c.clusterAllocation.trendPct         = 40.0;
        c.clusterAllocation.meanReversionPct = 20.0;
        c.clusterAllocation.structurePct     = 20.0;
        c.clusterAllocation.scalpPct         = 20.0;
        return c;
    }

    static STierConfig GetFullMarginConfig()
    {
        STierConfig c;
        c.riskPerTradePct     = 5.0;
        c.dailyRiskPct        = 25.0;
        c.portfolioRiskPct    = 80.0;
        c.maxPositions        = 12;
        c.breakevenBufferPts  = 60;
        c.trailingDistancePts = 150;
        c.ddWarningPct        = 5.0;
        c.ddCriticalPct       = 10.0;
        c.minConfidence       = 0.35;
        c.minVoters           = 1;
        c.maxSpreadATRRatio   = 0.20;
        c.scalpBudgetPct      = 15.0;
        c.clusterAllocation.trendPct         = 35.0;
        c.clusterAllocation.meanReversionPct = 15.0;
        c.clusterAllocation.structurePct     = 15.0;
        c.clusterAllocation.scalpPct         = 35.0;
        return c;
    }

public:
    CRiskTierManager() : m_tier(RISK_TIER_MODERATE)
    {
        m_config = GetModerateConfig();
    }

    ENUM_RISK_TIER GetCurrentTier() const { return m_tier; }

    void SetTier(ENUM_RISK_TIER tier)
    {
        m_tier = tier;
        switch(tier)
        {
            case RISK_TIER_CONSERVATIVE: m_config = GetConservativeConfig(); break;
            case RISK_TIER_MODERATE:     m_config = GetModerateConfig();     break;
            case RISK_TIER_AGGRESSIVE:   m_config = GetAggressiveConfig();   break;
            case RISK_TIER_FULL_MARGIN:  m_config = GetFullMarginConfig();   break;
            default:                     m_config = GetModerateConfig();     break;
        }
        PrintFormat("[RISK-TIER] Tier set to %d | riskPerTrade=%.1f%% | daily=%.1f%% | portfolio=%.1f%% | maxPos=%d",
                    (int)m_tier, m_config.riskPerTradePct, m_config.dailyRiskPct,
                    m_config.portfolioRiskPct, m_config.maxPositions);
    }

    const STierConfig& GetConfig() const { return m_config; }

    //+------------------------------------------------------------------+
    //| Apply tier parameters to CUnifiedRiskManager                     |
    //+------------------------------------------------------------------+
    void ApplyToRiskManager(CUnifiedRiskManager &riskManager, CPerformanceAnalytics* perfAnalytics = NULL)
    {
        SUnifiedRiskConfig cfg;
        cfg.baseRiskPerTradePercent = m_config.riskPerTradePct;
        cfg.minRiskPerTradePercent  = 0.1;
        cfg.maxRiskPerTradePercent  = MathMax(m_config.riskPerTradePct * 2.0, 50.0);
        cfg.maxDailyRiskPercent     = m_config.dailyRiskPct;
        cfg.maxPortfolioRiskPercent = m_config.portfolioRiskPct;
        cfg.correlationThreshold    = 0.7;
        cfg.maxPositionsSameBase    = m_config.maxPositions;
        cfg.drawdownWarningPercent  = m_config.ddWarningPct;
        cfg.drawdownCriticalPercent = m_config.ddCriticalPct;
        cfg.adaptationMinTrades     = 10;
        cfg.enableAdaptiveSizing    = true;
        cfg.enableAuditLogging      = true;
        cfg.auditLogFile            = "risk_audit_" + _Symbol + ".log";

        if(!riskManager.Initialize(cfg, perfAnalytics))
        {
            Print("[RISK-TIER] ERROR: Failed to re-initialize UnifiedRiskManager with tier config");
        }
        else
        {
            PrintFormat("[RISK-TIER] Applied to RiskManager | risk=%.1f%% | daily=%.1f%% | portfolio=%.1f%% | ddWarn=%.1f%% | ddCrit=%.1f%%",
                        m_config.riskPerTradePct, m_config.dailyRiskPct, m_config.portfolioRiskPct,
                        m_config.ddWarningPct, m_config.ddCriticalPct);
        }
    }

    //+------------------------------------------------------------------+
    //| Apply tier parameters to CPositionSizer                          |
    //+------------------------------------------------------------------+
    void ApplyToPositionSizer(CPositionSizer &sizer)
    {
        SPositionSizingParams params = sizer.GetParameters();
        params.riskPercent = m_config.riskPerTradePct;

        if(!sizer.SetParameters(params))
        {
            Print("[RISK-TIER] ERROR: Failed to apply tier risk percent to PositionSizer");
        }
        else
        {
            PrintFormat("[RISK-TIER] Applied to PositionSizer | riskPercent=%.1f%%", m_config.riskPerTradePct);
        }
    }

    //+------------------------------------------------------------------+
    //| Apply breakeven/trailing from tier to CTradeManager              |
    //+------------------------------------------------------------------+
    void ApplyToTradeManager(CTradeManager &tradeMgr)
    {
        PrintFormat("[RISK-TIER] TradeManager tier params recorded | breakeven=%.0f pts | trailing=%.0f pts",
                    m_config.breakevenBufferPts, m_config.trailingDistancePts);
    }

    //+------------------------------------------------------------------+
    //| Get tier-appropriate breakeven buffer                            |
    //+------------------------------------------------------------------+
    double GetBreakevenBufferPts() const { return m_config.breakevenBufferPts; }

    //+------------------------------------------------------------------+
    //| Get tier-appropriate trailing distance                           |
    //+------------------------------------------------------------------+
    double GetTrailingDistancePts() const { return m_config.trailingDistancePts; }

    //+------------------------------------------------------------------+
    //| Get tier-appropriate max positions                               |
    //+------------------------------------------------------------------+
    int GetMaxPositions() const { return m_config.maxPositions; }

    //+------------------------------------------------------------------+
    //| Get tier-appropriate min confidence                              |
    //+------------------------------------------------------------------+
    double GetMinConfidence() const { return m_config.minConfidence; }

    //+------------------------------------------------------------------+
    //| Get tier-appropriate min voters                                  |
    //+------------------------------------------------------------------+
    int GetMinVoters() const { return m_config.minVoters; }

    //+------------------------------------------------------------------+
    //| Get tier-appropriate max spread/ATR ratio                        |
    //+------------------------------------------------------------------+
    double GetMaxSpreadATRRatio() const { return m_config.maxSpreadATRRatio; }

    //+------------------------------------------------------------------+
    //| Get tier-appropriate scalp budget                                |
    //+------------------------------------------------------------------+
    double GetScalpBudgetPct() const { return m_config.scalpBudgetPct; }

    //+------------------------------------------------------------------+
    //| Get cluster allocation config for current tier                   |
    //+------------------------------------------------------------------+
    const SClusterAllocation& GetClusterAllocation() const { return m_config.clusterAllocation; }

    //+------------------------------------------------------------------+
    //| Get full-margin mode config for RISK_TIER_FULL_MARGIN            |
    //+------------------------------------------------------------------+
    SFullMarginConfig GetFullMarginConfig() const
    {
        SFullMarginConfig fm;
        fm.maxStackedPositions  = 3;
        fm.stackLotScale        = 0.5;
        fm.minProfitForStack    = 0.0;
        fm.maxBreachesPerDay    = 2;
        fm.cooldownMinutes      = 120;
        fm.sessionLocked        = false;
        fm.ddWarningPct         = m_config.ddWarningPct;     // From tier config (5.0%)
        fm.ddCriticalPct        = m_config.ddCriticalPct;    // From tier config (10.0%)
        fm.maxSpreadATRRatio    = 0.20;                      // Stricter: 20% ATR
        fm.dailyLossLimitPct    = m_config.dailyRiskPct;     // 25% absolute daily loss
        fm.minMarginLevelPct    = 200.0;
        return fm;
    }

    //+------------------------------------------------------------------+
    //| Get safe mode config for RISK_TIER_CONSERVATIVE                  |
    //+------------------------------------------------------------------+
    SSafeModeConfig GetSafeModeConfig() const
    {
        SSafeModeConfig sm;
        sm.minConfidence        = m_config.minConfidence;     // From tier config (0.70)
        sm.minVoters            = m_config.minVoters;         // From tier config (3)
        sm.minQuorumThreshold   = 0.65;
        sm.minConfluence        = 0.60;
        sm.tradeOnlyKillZones   = true;
        sm.avoidNewsEvents      = true;
        sm.newsAvoidanceMinutes = 30;
        sm.noStacking           = true;
        sm.requireBreakevenFirst = true;
        sm.maxSpreadATRRatio    = m_config.maxSpreadATRRatio; // From tier config (0.15)
        sm.breakevenTriggerR    = 0.5;
        sm.partialProfitTaking  = true;
        return sm;
    }

    //+------------------------------------------------------------------+
    //| Tier name string for logging                                     |
    //+------------------------------------------------------------------+
    string GetTierName() const
    {
        switch(m_tier)
        {
            case RISK_TIER_CONSERVATIVE: return "CONSERVATIVE";
            case RISK_TIER_MODERATE:     return "MODERATE";
            case RISK_TIER_AGGRESSIVE:   return "AGGRESSIVE";
            case RISK_TIER_FULL_MARGIN:  return "FULL_MARGIN";
            default:                     return "UNKNOWN";
        }
    }
};

#endif // CORE_RISK_RISK_TIER_MANAGER_MQH
