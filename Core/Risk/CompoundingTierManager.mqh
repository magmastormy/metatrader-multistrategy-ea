//+------------------------------------------------------------------+
//| CompoundingTierManager.mqh                                        |
//| Auto-switches risk tier based on account equity milestones        |
//| Implements I2 (Compounding Tier System) from problems.md          |
//+------------------------------------------------------------------+
#ifndef CORE_RISK_COMPOUNDING_TIER_MANAGER_MQH
#define CORE_RISK_COMPOUNDING_TIER_MANAGER_MQH

#include "../Utils/Enums.mqh"
#include "RiskTierManager.mqh"
#include "UnifiedRiskManager.mqh"
#include "PositionSizer.mqh"
#include "../Trading/TradeManager.mqh"

//+------------------------------------------------------------------+
//| Compounding Tier Configuration                                   |
//+------------------------------------------------------------------+
struct SCompoundingTierConfig
{
    double minBalance;
    double maxBalance;
    ENUM_RISK_TIER riskTier;          // Which static tier to map to
    double riskPerTradeOverride;      // Override risk % (0 = use tier default)
    double maxDailyRiskOverride;      // Override daily risk %
    double maxPortfolioRiskOverride;  // Override portfolio risk %
    double drawdownWarnOverride;      // Override drawdown warning %
    double drawdownCriticalOverride;  // Override drawdown critical %
    int    maxConcurrentOverride;     // Override max concurrent positions
    double dailyLossLimitOverride;    // Override daily loss limit %
};

//+------------------------------------------------------------------+
//| Compounding Tier Manager                                          |
//| Automatically switches risk profile as account grows              |
//+------------------------------------------------------------------+
class CCompoundingTierManager
{
private:
    SCompoundingTierConfig m_tiers[];
    int    m_tierCount;
    int    m_currentTierIndex;
    double m_previousEquity;
    bool   m_autoSwitchEnabled;
    bool   m_initialized;

    // Tracking
    datetime m_lastTierSwitchTime;
    double   m_peakEquity;
    int      m_switchCount;
    double   m_highestMilestoneReached;  // Batch 117: one-way watermark for milestones

    //+------------------------------------------------------------------+
    //| Build tier configurations                                         |
    //+------------------------------------------------------------------+
    void BuildTierConfigs()
    {
        m_tierCount = 9;
        ArrayResize(m_tiers, m_tierCount);

        // Tier 0: Micro Aggressive ($10-$25)
        // High risk for rapid compounding, accept 25% drawdown
        m_tiers[0].minBalance              = 10.0;
        m_tiers[0].maxBalance              = 25.0;
        m_tiers[0].riskTier                = RISK_TIER_MICRO_AGGRESSIVE;
        m_tiers[0].riskPerTradeOverride    = 4.0;
        m_tiers[0].maxDailyRiskOverride    = 12.0;
        m_tiers[0].maxPortfolioRiskOverride= 20.0;
        m_tiers[0].drawdownWarnOverride    = 18.0;
        m_tiers[0].drawdownCriticalOverride= 25.0;
        m_tiers[0].maxConcurrentOverride   = 2;
        m_tiers[0].dailyLossLimitOverride  = 15.0;

        // Tier 1: Growth ($25-$50)
        // Moderate aggression, still compounding hard
        m_tiers[1].minBalance              = 25.0;
        m_tiers[1].maxBalance              = 50.0;
        m_tiers[1].riskTier                = RISK_TIER_GROWTH;
        m_tiers[1].riskPerTradeOverride    = 5.0;
        m_tiers[1].maxDailyRiskOverride    = 14.0;
        m_tiers[1].maxPortfolioRiskOverride= 25.0;
        m_tiers[1].drawdownWarnOverride    = 16.0;
        m_tiers[1].drawdownCriticalOverride= 22.0;
        m_tiers[1].maxConcurrentOverride   = 3;
        m_tiers[1].dailyLossLimitOverride  = 18.0;

        // Tier 2: Acceleration ($50-$100)
        // Balanced — protect gains while still growing
        m_tiers[2].minBalance              = 50.0;
        m_tiers[2].maxBalance              = 100.0;
        m_tiers[2].riskTier                = RISK_TIER_ACCELERATION;
        m_tiers[2].riskPerTradeOverride    = 4.0;
        m_tiers[2].maxDailyRiskOverride    = 12.0;
        m_tiers[2].maxPortfolioRiskOverride= 22.0;
        m_tiers[2].drawdownWarnOverride    = 14.0;
        m_tiers[2].drawdownCriticalOverride= 20.0;
        m_tiers[2].maxConcurrentOverride   = 3;
        m_tiers[2].dailyLossLimitOverride  = 20.0;

        // Tier 3: Institutional ($100-$500)
        // Capital preservation mode — slow but steady
        m_tiers[3].minBalance              = 100.0;
        m_tiers[3].maxBalance              = 500.0;
        m_tiers[3].riskTier                = RISK_TIER_INSTITUTIONAL;
        m_tiers[3].riskPerTradeOverride    = 2.5;
        m_tiers[3].maxDailyRiskOverride    = 8.0;
        m_tiers[3].maxPortfolioRiskOverride= 18.0;
        m_tiers[3].drawdownWarnOverride    = 10.0;
        m_tiers[3].drawdownCriticalOverride= 15.0;
        m_tiers[3].maxConcurrentOverride   = 4;
        m_tiers[3].dailyLossLimitOverride  = 25.0;

        // Tier 4: Professional ($500-$1,000)
        // Full institutional approach — strict capital preservation
        m_tiers[4].minBalance              = 500.0;
        m_tiers[4].maxBalance              = 1000.0;
        m_tiers[4].riskTier                = RISK_TIER_PROFESSIONAL;
        m_tiers[4].riskPerTradeOverride    = 1.5;
        m_tiers[4].maxDailyRiskOverride    = 5.0;
        m_tiers[4].maxPortfolioRiskOverride= 15.0;
        m_tiers[4].drawdownWarnOverride    = 8.0;
        m_tiers[4].drawdownCriticalOverride= 12.0;
        m_tiers[4].maxConcurrentOverride   = 5;
        m_tiers[4].dailyLossLimitOverride  = 15.0;

        // Tier 5: High Growth ($1,000-$5,000) — USER REQUESTED: 5% risk
        // Aggressive growth with controlled risk
        m_tiers[5].minBalance              = 1000.0;
        m_tiers[5].maxBalance              = 5000.0;
        m_tiers[5].riskTier                = RISK_TIER_GROWTH;  // Reuse GROWTH tier
        m_tiers[5].riskPerTradeOverride    = 5.0;   // 5% risk per trade for <$1K equity
        m_tiers[5].maxDailyRiskOverride    = 15.0;
        m_tiers[5].maxPortfolioRiskOverride= 30.0;
        m_tiers[5].drawdownWarnOverride    = 10.0;
        m_tiers[5].drawdownCriticalOverride= 18.0;
        m_tiers[5].maxConcurrentOverride   = 6;
        m_tiers[5].dailyLossLimitOverride  = 20.0;

        // Tier 6: Aggressive Growth ($5,000-$10,000) — USER REQUESTED: 10% risk
        // Higher risk for aggressive growth
        m_tiers[6].minBalance              = 5000.0;
        m_tiers[6].maxBalance              = 10000.0;
        m_tiers[6].riskTier                = RISK_TIER_ACCELERATION;  // Reuse ACCELERATION tier
        m_tiers[6].riskPerTradeOverride    = 10.0;  // 10% risk per trade for <$5K equity
        m_tiers[6].maxDailyRiskOverride    = 25.0;
        m_tiers[6].maxPortfolioRiskOverride= 40.0;
        m_tiers[6].drawdownWarnOverride    = 12.0;
        m_tiers[6].drawdownCriticalOverride= 22.0;
        m_tiers[6].maxConcurrentOverride   = 8;
        m_tiers[6].dailyLossLimitOverride  = 25.0;

        // Tier 7: Maximum Growth ($10,000-$50,000) — USER REQUESTED: 15% risk
        // Maximum risk for accounts that can absorb drawdown
        m_tiers[7].minBalance              = 10000.0;
        m_tiers[7].maxBalance              = 50000.0;
        m_tiers[7].riskTier                = RISK_TIER_MICRO_AGGRESSIVE;  // Reuse MICRO_AGGRESSIVE tier
        m_tiers[7].riskPerTradeOverride    = 15.0;  // 15% risk per trade for <$10K equity
        m_tiers[7].maxDailyRiskOverride    = 35.0;
        m_tiers[7].maxPortfolioRiskOverride= 50.0;
        m_tiers[7].drawdownWarnOverride    = 15.0;
        m_tiers[7].drawdownCriticalOverride= 25.0;
        m_tiers[7].maxConcurrentOverride   = 10;
        m_tiers[7].dailyLossLimitOverride  = 30.0;

        // Tier 8: Capital Preservation ($50,000+) — Institutional mode
        // Full institutional approach — strict capital preservation
        m_tiers[8].minBalance              = 50000.0;
        m_tiers[8].maxBalance              = 1e10;
        m_tiers[8].riskTier                = RISK_TIER_INSTITUTIONAL;
        m_tiers[8].riskPerTradeOverride    = 1.5;
        m_tiers[8].maxDailyRiskOverride    = 5.0;
        m_tiers[8].maxPortfolioRiskOverride= 18.0;
        m_tiers[8].drawdownWarnOverride    = 8.0;
        m_tiers[8].drawdownCriticalOverride= 12.0;
        m_tiers[8].maxConcurrentOverride   = 5;
        m_tiers[8].dailyLossLimitOverride  = 15.0;
    }

    //+------------------------------------------------------------------+
    //| Find tier index for given balance                                |
    //+------------------------------------------------------------------+
    int FindTierIndex(double balance)
    {
        PrintFormat("[COMPOUNDING-TIER-DEBUG] FindTierIndex called | balance=%.2f | tierCount=%d", balance, m_tierCount);
        for(int i = 0; i < m_tierCount; i++)
        {
            PrintFormat("[COMPOUNDING-TIER-DEBUG]   Tier %d: min=%.2f max=%.2f riskTier=%s risk=%.1f%%", 
                        i, m_tiers[i].minBalance, m_tiers[i].maxBalance, 
                        GetTierName(i), m_tiers[i].riskPerTradeOverride);
            if(balance >= m_tiers[i].minBalance && balance < m_tiers[i].maxBalance)
            {
                PrintFormat("[COMPOUNDING-TIER-DEBUG]   -> MATCHED Tier %d (%s)", i, GetTierName(i));
                return i;
            }
        }
        PrintFormat("[COMPOUNDING-TIER-DEBUG]   -> NO MATCH, returning highest tier %d", m_tierCount - 1);
        return m_tierCount - 1; // highest tier
    }

    //+------------------------------------------------------------------+
    //| Get tier name for logging                                        |
    //+------------------------------------------------------------------+
    string GetTierName(int index) const
    {
        switch(m_tiers[index].riskTier)
        {
            case RISK_TIER_MICRO_AGGRESSIVE: return "MICRO_AGGRESSIVE";
            case RISK_TIER_GROWTH:           return "GROWTH";
            case RISK_TIER_ACCELERATION:     return "ACCELERATION";
            case RISK_TIER_INSTITUTIONAL:    return "INSTITUTIONAL";
            case RISK_TIER_PROFESSIONAL:     return "PROFESSIONAL";
            default:                         return "UNKNOWN";
        }
    }

public:
    CCompoundingTierManager() : m_tierCount(0), m_currentTierIndex(-1),
        m_previousEquity(0), m_autoSwitchEnabled(true), m_initialized(false),
        m_highestMilestoneReached(0),
        m_lastTierSwitchTime(0), m_peakEquity(0), m_switchCount(0) {}

    //+------------------------------------------------------------------+
    //| Initialize with default tier configs                             |
    //+------------------------------------------------------------------+
    bool Initialize(bool autoSwitch = true)
    {
        BuildTierConfigs();
        m_autoSwitchEnabled = autoSwitch;
        m_previousEquity = AccountInfoDouble(ACCOUNT_EQUITY);
        m_peakEquity = m_previousEquity;

        // Determine starting tier
        m_currentTierIndex = FindTierIndex(m_previousEquity);
        m_initialized = true;

        PrintFormat("[COMPOUNDING-TIER] Initialized | equity=%.2f | tier=%s | autoSwitch=%s",
                    m_previousEquity, GetTierName(m_currentTierIndex),
                    autoSwitch ? "true" : "false");
        PrintFormat("[COMPOUNDING-TIER] Risk=%.1f%% | Daily=%.1f%% | Portfolio=%.1f%% | DDWarn=%.1f%% | DDCrit=%.1f%% | MaxPos=%d | DailyLoss=%.1f%%",
                    m_tiers[m_currentTierIndex].riskPerTradeOverride,
                    m_tiers[m_currentTierIndex].maxDailyRiskOverride,
                    m_tiers[m_currentTierIndex].maxPortfolioRiskOverride,
                    m_tiers[m_currentTierIndex].drawdownWarnOverride,
                    m_tiers[m_currentTierIndex].drawdownCriticalOverride,
                    m_tiers[m_currentTierIndex].maxConcurrentOverride,
                    m_tiers[m_currentTierIndex].dailyLossLimitOverride);

        return true;
    }

    //+------------------------------------------------------------------+
    //| Check for tier transition — call from OnTimer or OnTick          |
    //| Returns true if tier changed                                     |
    //+------------------------------------------------------------------+
    bool CheckTierTransition(CUnifiedRiskManager &riskMgr,
                             CPositionSizer &posSizer,
                             CTradeManager &tradeMgr)
    {
        if(!m_initialized || !m_autoSwitchEnabled)
            return false;

        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        if(equity > m_peakEquity)
            m_peakEquity = equity;

        // I8: Check for account milestones
        string milestoneMsg = CheckMilestone(m_previousEquity, equity);
        if(StringLen(milestoneMsg) > 0)
        {
            SCompoundingTierConfig newTier = GetCurrentTier();
            PrintFormat("[COMPOUNDING-TIER-MILESTONE] %s | New tier: %s | Risk=%.1f%% | MaxDD=%.1f%% | MaxPos=%d",
                        milestoneMsg, GetTierName(m_currentTierIndex),
                        newTier.riskPerTradeOverride, newTier.drawdownCriticalOverride,
                        newTier.maxConcurrentOverride);
            Alert(milestoneMsg + " | Tier: " + GetTierName(m_currentTierIndex) +
                  " | Risk: " + DoubleToString(newTier.riskPerTradeOverride, 1) + "%");
        }

        int newTierIndex = FindTierIndex(equity);

        if(newTierIndex != m_currentTierIndex)
        {
            int oldIndex = m_currentTierIndex;
            m_currentTierIndex = newTierIndex;
            m_switchCount++;
            m_lastTierSwitchTime = TimeCurrent();

            PrintFormat("[COMPOUNDING-TIER] *** TIER TRANSITION *** | $%.2f -> $%.2f | %s -> %s | switch #%d",
                        m_tiers[oldIndex].minBalance, m_tiers[newTierIndex].minBalance,
                        GetTierName(oldIndex), GetTierName(newTierIndex), m_switchCount);

            // Apply new tier parameters
            ApplyTierToRiskManager(riskMgr);
            ApplyTierToPositionSizer(posSizer);

            // Alert
            Alert("COMPOUNDING TIER UPGRADE: Account $", DoubleToString(equity, 2),
                  " | New tier: ", GetTierName(m_currentTierIndex),
                  " | Risk: ", DoubleToString(m_tiers[m_currentTierIndex].riskPerTradeOverride, 1), "%");

            m_previousEquity = equity;
            return true;
        }

        m_previousEquity = equity;
        return false;
    }

    //+------------------------------------------------------------------+
    //| Apply current tier to risk manager                               |
    //+------------------------------------------------------------------+
    void ApplyTierToRiskManager(CUnifiedRiskManager &riskManager)
    {
        if(m_currentTierIndex < 0 || m_currentTierIndex >= m_tierCount)
            return;

        SCompoundingTierConfig tier = m_tiers[m_currentTierIndex];

        riskManager.ApplyTierOverrides(
            tier.riskPerTradeOverride,
            tier.maxConcurrentOverride,
            tier.maxDailyRiskOverride,
            tier.maxPortfolioRiskOverride,
            tier.drawdownWarnOverride,
            tier.drawdownCriticalOverride,
            tier.dailyLossLimitOverride
        );

        PrintFormat("[COMPOUNDING-TIER] Applied to RiskManager | risk=%.1f%% | daily=%.1f%% | portfolio=%.1f%% | ddWarn=%.1f%% | ddCrit=%.1f%% | maxPos=%d | dailyLoss=%.1f%%",
                    tier.riskPerTradeOverride,
                    tier.maxDailyRiskOverride,
                    tier.maxPortfolioRiskOverride,
                    tier.drawdownWarnOverride,
                    tier.drawdownCriticalOverride,
                    tier.maxConcurrentOverride,
                    tier.dailyLossLimitOverride);
    }

    //+------------------------------------------------------------------+
    //| Apply current tier to position sizer                             |
    //+------------------------------------------------------------------+
    void ApplyTierToPositionSizer(CPositionSizer &posSizer)
    {
        if(m_currentTierIndex < 0 || m_currentTierIndex >= m_tierCount)
            return;

        SCompoundingTierConfig tier = m_tiers[m_currentTierIndex];

        SPositionSizingParams params = posSizer.GetParameters();
        params.riskPercent = tier.riskPerTradeOverride;
        posSizer.SetParameters(params);

        PrintFormat("[COMPOUNDING-TIER] Applied to PositionSizer | riskPercent=%.1f%%",
                    tier.riskPerTradeOverride);
    }

    //+------------------------------------------------------------------+
    //| Get current tier config                                           |
    //+------------------------------------------------------------------+
    SCompoundingTierConfig GetCurrentTier() const
    {
        if(m_currentTierIndex >= 0 && m_currentTierIndex < m_tierCount)
            return m_tiers[m_currentTierIndex];

        // Fallback
        SCompoundingTierConfig fallback;
        fallback.riskPerTradeOverride = 1.0;
        fallback.maxDailyRiskOverride = 5.0;
        fallback.maxPortfolioRiskOverride = 15.0;
        fallback.drawdownWarnOverride = 5.0;
        fallback.drawdownCriticalOverride = 10.0;
        fallback.maxConcurrentOverride = 3;
        fallback.dailyLossLimitOverride = 40.0;
        return fallback;
    }

    //+------------------------------------------------------------------+
    //| Get current tier risk percentage                                  |
    //+------------------------------------------------------------------+
    double GetRiskPerTrade() const
    {
        if(m_currentTierIndex >= 0 && m_currentTierIndex < m_tierCount)
            return m_tiers[m_currentTierIndex].riskPerTradeOverride;
        return 1.0;
    }

    //+------------------------------------------------------------------+
    //| Get current max concurrent positions                              |
    //+------------------------------------------------------------------+
    int GetMaxConcurrent() const
    {
        if(m_currentTierIndex >= 0 && m_currentTierIndex < m_tierCount)
            return m_tiers[m_currentTierIndex].maxConcurrentOverride;
        return 3;
    }

    //+------------------------------------------------------------------+
    //| Get current daily loss limit                                      |
    //+------------------------------------------------------------------+
    double GetDailyLossLimit() const
    {
        if(m_currentTierIndex >= 0 && m_currentTierIndex < m_tierCount)
            return m_tiers[m_currentTierIndex].dailyLossLimitOverride;
        return 15.0;
    }

    //+------------------------------------------------------------------+
    //| Get current drawdown critical threshold                           |
    //+------------------------------------------------------------------+
    double GetDrawdownCritical() const
    {
        if(m_currentTierIndex >= 0 && m_currentTierIndex < m_tierCount)
            return m_tiers[m_currentTierIndex].drawdownCriticalOverride;
        return 10.0;
    }

    //+------------------------------------------------------------------+
    //| Check if account qualifies for higher tier (milestone check)      |
    //+------------------------------------------------------------------+
    string CheckMilestone(double prevEquity, double currEquity)
    {
        double milestones[] = {25.0, 50.0, 100.0, 200.0, 500.0};

        for(int i = 0; i < ArraySize(milestones); i++)
        {
            // Batch 117: one-way watermark — only fire for milestones above highest reached
            if(prevEquity < milestones[i] && currEquity >= milestones[i] && milestones[i] > m_highestMilestoneReached)
            {
                m_highestMilestoneReached = milestones[i];
                return StringFormat("ACCOUNT MILESTONE: $%.0f reached", milestones[i]);
            }
        }
        return "";
    }

    //+------------------------------------------------------------------+
    //| Enable/disable auto-switching                                     |
    //+------------------------------------------------------------------+
    void SetAutoSwitch(bool enabled) { m_autoSwitchEnabled = enabled; }
    bool IsAutoSwitchEnabled() const { return m_autoSwitchEnabled; }

    //+------------------------------------------------------------------+
    //| Get tier info for diagnostics                                     |
    //+------------------------------------------------------------------+
    string GetDiagnostics() const
    {
        return StringFormat("Tier=%s | Equity=$%.2f | Switches=%d | Peak=$%.2f",
                            (m_currentTierIndex >= 0) ? GetTierName(m_currentTierIndex) : "NONE",
                            m_previousEquity, m_switchCount, m_peakEquity);
    }

    bool IsInitialized() const { return m_initialized; }
    int GetCurrentTierIndex() const { return m_currentTierIndex; }
    int GetSwitchCount() const { return m_switchCount; }
};

#endif // CORE_RISK_COMPOUNDING_TIER_MANAGER_MQH
