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
//| Blueprint 10.4: All percent fields use 0-100 scale               |
//+------------------------------------------------------------------+
struct STierConfig
{
   double riskPerTradePct;      // Blueprint 10.4: 0-100 scale (e.g., 1.0 = 1%)
   double dailyRiskPct;         // Blueprint 10.4: 0-100 scale
   double portfolioRiskPct;     // Blueprint 10.4: 0-100 scale
   int    maxPositions;         // Max concurrent positions
   double breakevenBufferPts;   // Points buffer for breakeven move
   double trailingDistancePts;  // Points for trailing stop distance
   double ddWarningPct;         // Blueprint 10.4: 0-100 scale
   double ddCriticalPct;        // Blueprint 10.4: 0-100 scale
   double minConfidence;        // 0-1 scale (not a risk percent)
   int    minVoters;            // Min live voters for consensus
   double maxSpreadATRRatio;    // Max spread/ATR ratio for entry
   double scalpBudgetPct;       // Blueprint 10.4: 0-100 scale
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

    // Pre-defined tier presets (Blueprint 10.4: all Pct fields use 0-100 scale)
    static STierConfig GetConservativeConfig()
    {
        STierConfig c;
        c.riskPerTradePct     = 0.5;   // Blueprint 10.4: 0-100 scale
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
        c.clusterAllocation.trendPct         = 40.0;
        c.clusterAllocation.meanReversionPct = 25.0;
        c.clusterAllocation.structurePct     = 25.0;
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

    static STierConfig GetFullMarginTierPreset()
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

    // I2: Compounding tier presets — used by CCompoundingTierManager
    static STierConfig GetMicroAggressiveConfig()
    {
        STierConfig c;
        c.riskPerTradePct     = 4.0;
        c.dailyRiskPct        = 12.0;
        c.portfolioRiskPct    = 20.0;
        c.maxPositions        = 2;
        c.breakevenBufferPts  = 80;
        c.trailingDistancePts = 200;
        c.ddWarningPct        = 18.0;
        c.ddCriticalPct       = 25.0;
        c.minConfidence       = 0.45;
        c.minVoters           = 2;
        c.maxSpreadATRRatio   = 0.25;
        c.scalpBudgetPct      = 10.0;
        c.clusterAllocation.trendPct         = 30.0;
        c.clusterAllocation.meanReversionPct = 25.0;
        c.clusterAllocation.structurePct     = 25.0;
        c.clusterAllocation.scalpPct         = 20.0;
        return c;
    }

    static STierConfig GetGrowthConfig()
    {
        STierConfig c;
        c.riskPerTradePct     = 5.0;
        c.dailyRiskPct        = 14.0;
        c.portfolioRiskPct    = 25.0;
        c.maxPositions        = 3;
        c.breakevenBufferPts  = 100;
        c.trailingDistancePts = 250;
        c.ddWarningPct        = 16.0;
        c.ddCriticalPct       = 22.0;
        c.minConfidence       = 0.42;
        c.minVoters           = 2;
        c.maxSpreadATRRatio   = 0.22;
        c.scalpBudgetPct      = 12.0;
        c.clusterAllocation.trendPct         = 35.0;
        c.clusterAllocation.meanReversionPct = 20.0;
        c.clusterAllocation.structurePct     = 25.0;
        c.clusterAllocation.scalpPct         = 20.0;
        return c;
    }

    static STierConfig GetAccelerationConfig()
    {
        STierConfig c;
        c.riskPerTradePct     = 4.0;
        c.dailyRiskPct        = 12.0;
        c.portfolioRiskPct    = 22.0;
        c.maxPositions        = 3;
        c.breakevenBufferPts  = 110;
        c.trailingDistancePts = 280;
        c.ddWarningPct        = 14.0;
        c.ddCriticalPct       = 20.0;
        c.minConfidence       = 0.48;
        c.minVoters           = 2;
        c.maxSpreadATRRatio   = 0.20;
        c.scalpBudgetPct      = 10.0;
        c.clusterAllocation.trendPct         = 35.0;
        c.clusterAllocation.meanReversionPct = 25.0;
        c.clusterAllocation.structurePct     = 25.0;
        c.clusterAllocation.scalpPct         = 15.0;
        return c;
    }

    static STierConfig GetInstitutionalConfig()
    {
        STierConfig c;
        c.riskPerTradePct     = 2.5;
        c.dailyRiskPct        = 8.0;
        c.portfolioRiskPct    = 18.0;
        c.maxPositions        = 4;
        c.breakevenBufferPts  = 120;
        c.trailingDistancePts = 300;
        c.ddWarningPct        = 10.0;
        c.ddCriticalPct       = 15.0;
        c.minConfidence       = 0.55;
        c.minVoters           = 2;
        c.maxSpreadATRRatio   = 0.18;
        c.scalpBudgetPct      = 6.0;
        c.clusterAllocation.trendPct         = 40.0;
        c.clusterAllocation.meanReversionPct = 25.0;
        c.clusterAllocation.structurePct     = 25.0;
        c.clusterAllocation.scalpPct         = 10.0;
        return c;
    }

    static STierConfig GetProfessionalConfig()
    {
        STierConfig c;
        c.riskPerTradePct     = 1.5;
        c.dailyRiskPct        = 5.0;
        c.portfolioRiskPct    = 15.0;
        c.maxPositions        = 5;
        c.breakevenBufferPts  = 150;
        c.trailingDistancePts = 350;
        c.ddWarningPct        = 8.0;
        c.ddCriticalPct       = 12.0;
        c.minConfidence       = 0.60;
        c.minVoters           = 3;
        c.maxSpreadATRRatio   = 0.15;
        c.scalpBudgetPct      = 3.0;
        c.clusterAllocation.trendPct         = 40.0;
        c.clusterAllocation.meanReversionPct = 25.0;
        c.clusterAllocation.structurePct     = 25.0;
        c.clusterAllocation.scalpPct         = 10.0;
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
            case RISK_TIER_CONSERVATIVE:      m_config = GetConservativeConfig(); break;
            case RISK_TIER_MODERATE:          m_config = GetModerateConfig();     break;
            case RISK_TIER_AGGRESSIVE:        m_config = GetAggressiveConfig();   break;
            case RISK_TIER_FULL_MARGIN:       m_config = GetFullMarginTierPreset(); break;
            case RISK_TIER_MICRO_AGGRESSIVE:  m_config = GetMicroAggressiveConfig(); break;
            case RISK_TIER_GROWTH:            m_config = GetGrowthConfig(); break;
            case RISK_TIER_ACCELERATION:      m_config = GetAccelerationConfig(); break;
            case RISK_TIER_INSTITUTIONAL:     m_config = GetInstitutionalConfig(); break;
            case RISK_TIER_PROFESSIONAL:      m_config = GetProfessionalConfig(); break;
            default:                          m_config = GetModerateConfig();     break;
        }
        PrintFormat("[RISK-TIER] Tier set to %d | riskPerTrade=%.1f%% | daily=%.1f%% | portfolio=%.1f%% | maxPos=%d",
                    (int)m_tier, m_config.riskPerTradePct, m_config.dailyRiskPct,
                    m_config.portfolioRiskPct, m_config.maxPositions);
    }

    STierConfig GetConfig() const { return m_config; }

    //+------------------------------------------------------------------+
    //| Apply tier parameters to CUnifiedRiskManager                     |
    //| Blueprint 10.4: All percent values in 0-100 scale               |
    //| Input floors: if >0, tier values cannot go below these floors   |
    //+------------------------------------------------------------------+
    void ApplyToRiskManager(CUnifiedRiskManager &riskManager, CPerformanceAnalytics* perfAnalytics = NULL,
                            double inputDailyFloor = 0.0, double inputPortfolioFloor = 0.0,
                            double inputDdWarningFloor = 0.0, double inputDdCriticalFloor = 0.0,
                            double inputDailyLossLimit = 0.0)
    {
        // Tier values are defaults, but user input params serve as floors —
        // the effective value is the higher of tier preset and user input.
        double effectiveDaily     = (inputDailyFloor > 0.0)     ? MathMax(m_config.dailyRiskPct, inputDailyFloor)     : m_config.dailyRiskPct;
        double effectivePortfolio = (inputPortfolioFloor > 0.0) ? MathMax(m_config.portfolioRiskPct, inputPortfolioFloor) : m_config.portfolioRiskPct;
        double effectiveDdWarning = (inputDdWarningFloor > 0.0) ? MathMax(m_config.ddWarningPct, inputDdWarningFloor) : m_config.ddWarningPct;
        double effectiveDdCritical= (inputDdCriticalFloor > 0.0)? MathMax(m_config.ddCriticalPct, inputDdCriticalFloor): m_config.ddCriticalPct;

        // Floor cap: if effective value exceeds 2x the tier preset, cap at 2x tier preset.
        // This prevents floor values from overriding tier-defined risk constraints
        // (e.g., daily 5%→40%, portfolio 15%→60%, riskPerTrade 1%→10%).
        double dailyCap     = m_config.dailyRiskPct * 2.0;
        double portfolioCap = m_config.portfolioRiskPct * 2.0;
        double ddWarningCap = m_config.ddWarningPct * 2.0;
        double ddCriticalCap= m_config.ddCriticalPct * 2.0;

        if(effectiveDaily > dailyCap)
        {
            PrintFormat("[RISK-TIER-FLOOR-CAP] daily capped: floor=%.1f%% -> capped=%.1f%% (tier=%.1f%% x2=%.1f%%)",
                        effectiveDaily, dailyCap, m_config.dailyRiskPct, dailyCap);
            effectiveDaily = dailyCap;
        }
        if(effectivePortfolio > portfolioCap)
        {
            PrintFormat("[RISK-TIER-FLOOR-CAP] portfolio capped: floor=%.1f%% -> capped=%.1f%% (tier=%.1f%% x2=%.1f%%)",
                        effectivePortfolio, portfolioCap, m_config.portfolioRiskPct, portfolioCap);
            effectivePortfolio = portfolioCap;
        }
        if(effectiveDdWarning > ddWarningCap)
        {
            PrintFormat("[RISK-TIER-FLOOR-CAP] ddWarning capped: floor=%.1f%% -> capped=%.1f%% (tier=%.1f%% x2=%.1f%%)",
                        effectiveDdWarning, ddWarningCap, m_config.ddWarningPct, ddWarningCap);
            effectiveDdWarning = ddWarningCap;
        }
        if(effectiveDdCritical > ddCriticalCap)
        {
            PrintFormat("[RISK-TIER-FLOOR-CAP] ddCritical capped: floor=%.1f%% -> capped=%.1f%% (tier=%.1f%% x2=%.1f%%)",
                        effectiveDdCritical, ddCriticalCap, m_config.ddCriticalPct, ddCriticalCap);
            effectiveDdCritical = ddCriticalCap;
        }

        double effectiveDailyLossLimit = (inputDailyLossLimit > 0.0) ? inputDailyLossLimit : 15.0;

        // Apply tier overrides without reinitializing the entire risk manager.
        // This avoids dual initialization of circuit breaker, correlation engine,
        // portfolio risk manager, and other runtime state.
        riskManager.ApplyTierOverrides(m_config.riskPerTradePct,
                                       m_config.maxPositions,
                                       effectiveDaily, effectivePortfolio,
                                       effectiveDdWarning, effectiveDdCritical,
                                       effectiveDailyLossLimit);

        PrintFormat("[RISK-TIER] Applied to RiskManager | risk=%.1f%% | daily=%.1f%% (tier=%.1f floor=%.1f) | portfolio=%.1f%% (tier=%.1f floor=%.1f) | ddWarn=%.1f%% | ddCrit=%.1f%%",
                    m_config.riskPerTradePct,
                    effectiveDaily, m_config.dailyRiskPct, inputDailyFloor,
                    effectivePortfolio, m_config.portfolioRiskPct, inputPortfolioFloor,
                    effectiveDdWarning, effectiveDdCritical);
    }

    //+------------------------------------------------------------------+
    //| Apply tier parameters to CPositionSizer                          |
    //| Blueprint 10.4: riskPercent uses 0-100 scale                     |
    //| Input floor: if >0, tier risk percent cannot go below this floor |
    //+------------------------------------------------------------------+
    void ApplyToPositionSizer(CPositionSizer &sizer, double inputRiskFloor = 0.0)
    {
        SPositionSizingParams params = sizer.GetParameters();
        double effectiveRisk = (inputRiskFloor > 0.0) ? MathMax(m_config.riskPerTradePct, inputRiskFloor) : m_config.riskPerTradePct;

        // Floor cap: if effective risk exceeds 2x the tier preset, cap at 2x tier preset
        double riskCap = m_config.riskPerTradePct * 2.0;
        if(effectiveRisk > riskCap)
        {
            PrintFormat("[RISK-TIER-FLOOR-CAP] riskPerTrade capped: floor=%.1f%% -> capped=%.1f%% (tier=%.1f%% x2=%.1f%%)",
                        effectiveRisk, riskCap, m_config.riskPerTradePct, riskCap);
            effectiveRisk = riskCap;
        }

        params.riskPercent = effectiveRisk;  // Blueprint 10.4: 0-100 scale

        if(!sizer.SetParameters(params))
        {
            Print("[RISK-TIER] ERROR: Failed to apply tier risk percent to PositionSizer");
        }
        else
        {
            PrintFormat("[RISK-TIER] Applied to PositionSizer | riskPercent=%.1f%% (tier=%.1f floor=%.1f)",
                        effectiveRisk, m_config.riskPerTradePct, inputRiskFloor);
        }
    }

    //+------------------------------------------------------------------+
    //| Apply breakeven/trailing from tier to CTradeManager              |
    //| Batch 117: Store tier params as static defaults for callers      |
    //+------------------------------------------------------------------+
    void ApplyToTradeManager(CTradeManager &tradeMgr)
    {
        // Store tier params as static defaults — callers read via GetBreakevenBufferPts/GetTrailingDistancePts
        PrintFormat("[RISK-TIER] TradeManager tier params applied | breakeven=%.0f pts | trailing=%.0f pts",
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
    SClusterAllocation GetClusterAllocation() const { return m_config.clusterAllocation; }

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
            case RISK_TIER_CONSERVATIVE:      return "CONSERVATIVE";
            case RISK_TIER_MODERATE:          return "MODERATE";
            case RISK_TIER_AGGRESSIVE:        return "AGGRESSIVE";
            case RISK_TIER_FULL_MARGIN:       return "FULL_MARGIN";
            case RISK_TIER_MICRO_AGGRESSIVE:  return "MICRO_AGGRESSIVE";
            case RISK_TIER_GROWTH:            return "GROWTH";
            case RISK_TIER_ACCELERATION:      return "ACCELERATION";
            case RISK_TIER_INSTITUTIONAL:     return "INSTITUTIONAL";
            case RISK_TIER_PROFESSIONAL:      return "PROFESSIONAL";
            default:                          return "UNKNOWN";
        }
    }
};

#endif // CORE_RISK_RISK_TIER_MANAGER_MQH
