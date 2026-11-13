// Switches the risk profile between equity brackets as account equity grows.
// Milestone crossings only log/Alert; the active tier comes from the equity bracket alone.
#ifndef CORE_RISK_COMPOUNDING_TIER_MANAGER_MQH
#define CORE_RISK_COMPOUNDING_TIER_MANAGER_MQH

#include "../Utils/Enums.mqh"
#include "RiskTierManager.mqh"
#include "UnifiedRiskManager.mqh"
#include "PositionSizer.mqh"
#include "../Trading/TradeManager.mqh"

// Deliberately separate from ENUM_RISK_TIER; nothing maps between them except GetTierName() log strings
enum ENUM_COMPOUNDING_TIER
{
    COMPOUNDING_TIER_MICRO_AGGRESSIVE = 0,   // $10-$25
    COMPOUNDING_TIER_GROWTH = 1,              // $25-$50
    COMPOUNDING_TIER_ACCELERATION = 2,        // $50-$100
    COMPOUNDING_TIER_INSTITUTIONAL = 3,       // $100-$500
    COMPOUNDING_TIER_PROFESSIONAL = 4,        // $500-$1,000
    COMPOUNDING_TIER_HIGH_GROWTH = 5,         // $1,000-$5,000
    COMPOUNDING_TIER_AGGRESSIVE_GROWTH = 6,   // $5,000-$10,000
    COMPOUNDING_TIER_MAXIMUM_GROWTH = 7,      // $10,000-$50,000
    COMPOUNDING_TIER_CAPITAL_PRESERVATION = 8 // $50,000+
};

struct SCompoundingTierConfig
{
    double minEquity;
    double maxEquity;
    ENUM_COMPOUNDING_TIER compoundingTier; // Use separate compounding tier enum
    ENUM_RISK_TIER riskTier;               // Which static risk tier to map to
    double riskPerTradeOverride;           // Override risk % (0 = use tier default)
    double maxRiskPerTradeOverride;        // Explicit max risk per trade
    double maxDailyRiskOverride;
    double maxPortfolioRiskOverride;
    double drawdownWarnOverride;
    double drawdownCriticalOverride;
    int    maxConcurrentOverride;          // Override max concurrent positions
    double dailyLossLimitOverride;
};

class CCompoundingTierManager
{
private:
    SCompoundingTierConfig m_tiers[];
    int    m_tierCount;
    int    m_currentTierIndex;
    double m_previousEquity;
    double m_startingEquity;  // Track starting equity for % milestones
    bool   m_autoSwitchEnabled;
    bool   m_initialized;

    datetime m_lastTierSwitchTime;
    double   m_peakEquity;
    int      m_switchCount;
    double   m_highestMilestoneReached;  // one-way watermark for milestones

        void BuildTierConfigs()
        {
            m_tierCount = 9;
            ArrayResize(m_tiers, m_tierCount);

            // Tier 0: Micro Aggressive ($10-$25)
                    m_tiers[0].minEquity              = 10.0;
                    m_tiers[0].maxEquity              = 25.0;
                    m_tiers[0].compoundingTier          = COMPOUNDING_TIER_MICRO_AGGRESSIVE;
                    m_tiers[0].riskTier                = RISK_TIER_MICRO_AGGRESSIVE;
                    m_tiers[0].riskPerTradeOverride    = 4.0;
                    m_tiers[0].maxRiskPerTradeOverride = 8.0;    // explicit override (2x riskPerTradeOverride)
                    m_tiers[0].maxDailyRiskOverride    = 12.0;
                    m_tiers[0].maxPortfolioRiskOverride= 20.0;
                    m_tiers[0].drawdownWarnOverride    = 18.0;
                    m_tiers[0].drawdownCriticalOverride= 25.0;
                    m_tiers[0].maxConcurrentOverride   = 2;
                    m_tiers[0].dailyLossLimitOverride  = 15.0;

                    // Tier 1: Growth ($25-$50)
                    m_tiers[1].minEquity              = 25.0;
                    m_tiers[1].maxEquity              = 50.0;
                    m_tiers[1].compoundingTier          = COMPOUNDING_TIER_GROWTH;
                    m_tiers[1].riskTier                = RISK_TIER_GROWTH;
                    m_tiers[1].riskPerTradeOverride    = 5.0;
                    m_tiers[1].maxRiskPerTradeOverride = 10.0;   // explicit override
                    m_tiers[1].maxDailyRiskOverride    = 14.0;
                    m_tiers[1].maxPortfolioRiskOverride= 25.0;
                    m_tiers[1].drawdownWarnOverride    = 16.0;
                    m_tiers[1].drawdownCriticalOverride= 22.0;
                    m_tiers[1].maxConcurrentOverride   = 3;
                    m_tiers[1].dailyLossLimitOverride  = 18.0;

                    // Tier 2: Acceleration ($50-$100)
                    m_tiers[2].minEquity              = 50.0;
                    m_tiers[2].maxEquity              = 100.0;
                    m_tiers[2].compoundingTier          = COMPOUNDING_TIER_ACCELERATION;
                    m_tiers[2].riskTier                = RISK_TIER_ACCELERATION;
                    m_tiers[2].riskPerTradeOverride    = 4.0;
                    m_tiers[2].maxRiskPerTradeOverride = 8.0;    // explicit override
                    m_tiers[2].maxDailyRiskOverride    = 12.0;
                    m_tiers[2].maxPortfolioRiskOverride= 22.0;
                    m_tiers[2].drawdownWarnOverride    = 14.0;
                    m_tiers[2].drawdownCriticalOverride= 20.0;
                    m_tiers[2].maxConcurrentOverride   = 3;
                    m_tiers[2].dailyLossLimitOverride  = 20.0;

                    // Tier 3: Institutional ($100-$500)
                    m_tiers[3].minEquity              = 100.0;
                    m_tiers[3].maxEquity              = 500.0;
                    m_tiers[3].compoundingTier          = COMPOUNDING_TIER_INSTITUTIONAL;
                    m_tiers[3].riskTier                = RISK_TIER_INSTITUTIONAL;
                    m_tiers[3].riskPerTradeOverride    = 2.5;
                    m_tiers[3].maxRiskPerTradeOverride = 5.0;    // explicit override
                    m_tiers[3].maxDailyRiskOverride    = 8.0;
                    m_tiers[3].maxPortfolioRiskOverride= 18.0;
                    m_tiers[3].drawdownWarnOverride    = 10.0;
                    m_tiers[3].drawdownCriticalOverride= 15.0;
                    m_tiers[3].maxConcurrentOverride   = 4;
                    m_tiers[3].dailyLossLimitOverride  = 25.0;

                    // Tier 4: Professional ($500-$1,000)
                    m_tiers[4].minEquity              = 500.0;
                    m_tiers[4].maxEquity              = 1000.0;
                    m_tiers[4].compoundingTier          = COMPOUNDING_TIER_PROFESSIONAL;
                    m_tiers[4].riskTier                = RISK_TIER_PROFESSIONAL;
                    m_tiers[4].riskPerTradeOverride    = 1.5;
                    m_tiers[4].maxRiskPerTradeOverride = 3.0;    // explicit override
                    m_tiers[4].maxDailyRiskOverride    = 5.0;
                    m_tiers[4].maxPortfolioRiskOverride= 15.0;
                    m_tiers[4].drawdownWarnOverride    = 8.0;
                    m_tiers[4].drawdownCriticalOverride= 12.0;
                    m_tiers[4].maxConcurrentOverride   = 5;
                    m_tiers[4].dailyLossLimitOverride  = 15.0;

                    // Tier 5: High Growth ($1,000-$5,000)
                    m_tiers[5].minEquity              = 1000.0;
                    m_tiers[5].maxEquity              = 5000.0;
                    m_tiers[5].compoundingTier          = COMPOUNDING_TIER_HIGH_GROWTH;
                    m_tiers[5].riskTier                = RISK_TIER_GROWTH;  // Reuse GROWTH tier
                    m_tiers[5].riskPerTradeOverride    = 5.0;   // 5% risk per trade for <$1K equity
                    m_tiers[5].maxRiskPerTradeOverride = 10.0;  // explicit override
                    m_tiers[5].maxDailyRiskOverride    = 15.0;
                    m_tiers[5].maxPortfolioRiskOverride= 30.0;
                    m_tiers[5].drawdownWarnOverride    = 10.0;
                    m_tiers[5].drawdownCriticalOverride= 18.0;
                    m_tiers[5].maxConcurrentOverride   = 6;
                    m_tiers[5].dailyLossLimitOverride  = 20.0;

                    // Tier 6: Aggressive Growth ($5,000-$10,000)
                    m_tiers[6].minEquity              = 5000.0;
                    m_tiers[6].maxEquity              = 10000.0;
                    m_tiers[6].compoundingTier          = COMPOUNDING_TIER_AGGRESSIVE_GROWTH;
                    m_tiers[6].riskTier                = RISK_TIER_ACCELERATION;  // Reuse ACCELERATION tier
                    m_tiers[6].riskPerTradeOverride    = 10.0;  // 10% risk per trade for <$5K equity
                    m_tiers[6].maxRiskPerTradeOverride = 20.0;  // explicit override
                    m_tiers[6].maxDailyRiskOverride    = 25.0;
                    m_tiers[6].maxPortfolioRiskOverride= 40.0;
                    m_tiers[6].drawdownWarnOverride    = 12.0;
                    m_tiers[6].drawdownCriticalOverride= 22.0;
                    m_tiers[6].maxConcurrentOverride   = 8;
                    m_tiers[6].dailyLossLimitOverride  = 25.0;

                    // Tier 7: Maximum Growth ($10,000-$50,000)
                    m_tiers[7].minEquity              = 10000.0;
                    m_tiers[7].maxEquity              = 50000.0;
                    m_tiers[7].compoundingTier          = COMPOUNDING_TIER_MAXIMUM_GROWTH;
                    m_tiers[7].riskTier                = RISK_TIER_MICRO_AGGRESSIVE;  // Reuse MICRO_AGGRESSIVE tier
                    m_tiers[7].riskPerTradeOverride    = 15.0;  // 15% risk per trade for <$10K equity
                    m_tiers[7].maxRiskPerTradeOverride = 30.0;  // explicit override
                    m_tiers[7].maxDailyRiskOverride    = 35.0;
                    m_tiers[7].maxPortfolioRiskOverride= 50.0;
                    m_tiers[7].drawdownWarnOverride    = 15.0;
                    m_tiers[7].drawdownCriticalOverride= 25.0;
                    m_tiers[7].maxConcurrentOverride   = 10;
                    m_tiers[7].dailyLossLimitOverride  = 30.0;

                    // Tier 8: Capital Preservation ($50,000+)
                    m_tiers[8].minEquity              = 50000.0;
                    m_tiers[8].maxEquity              = 1e10;
                    m_tiers[8].compoundingTier          = COMPOUNDING_TIER_CAPITAL_PRESERVATION;
                    m_tiers[8].riskTier                = RISK_TIER_INSTITUTIONAL;
                    m_tiers[8].riskPerTradeOverride    = 1.5;
                    m_tiers[8].maxRiskPerTradeOverride = 3.0;   // explicit override
                    m_tiers[8].maxDailyRiskOverride    = 5.0;
                    m_tiers[8].maxPortfolioRiskOverride= 18.0;
                    m_tiers[8].drawdownWarnOverride    = 8.0;
                    m_tiers[8].drawdownCriticalOverride= 12.0;
                    m_tiers[8].maxConcurrentOverride   = 5;
                    m_tiers[8].dailyLossLimitOverride  = 15.0;
        }

// Bracket match is [min, max) in account-currency equity; equity below the first bracket matches no tier and
// returns the LAST one (Capital Preservation, the most conservative), not the most aggressive
    int FindTierIndex(double equity)
    {
        // No per-call tracing: this runs on the sizing path and printed its entire bracket table
        // (1 + tierCount lines) on every evaluation - 5,861 lines in a 7-hour window. The selected
        // tier is already reported at Initialize and on every transition.
        for(int i = 0; i < m_tierCount; i++)
        {
            if(equity >= m_tiers[i].minEquity && equity < m_tiers[i].maxEquity)
                return i;
        }
        return m_tierCount - 1; // highest tier
    }

        string GetTierName(int index) const
        {
            string riskTierName = "UNKNOWN";
            switch(m_tiers[index].riskTier)
            {
                case RISK_TIER_MICRO_AGGRESSIVE: riskTierName = "MICRO_AGGRESSIVE"; break;
                case RISK_TIER_GROWTH:           riskTierName = "GROWTH"; break;
                case RISK_TIER_ACCELERATION:     riskTierName = "ACCELERATION"; break;
                case RISK_TIER_INSTITUTIONAL:    riskTierName = "INSTITUTIONAL"; break;
                case RISK_TIER_PROFESSIONAL:     riskTierName = "PROFESSIONAL"; break;
                default:                         riskTierName = "UNKNOWN"; break;
            }
        
            string compoundingTierName = "UNKNOWN";
            switch(m_tiers[index].compoundingTier)
            {
                case COMPOUNDING_TIER_MICRO_AGGRESSIVE:        compoundingTierName = "MICRO_AGGRESSIVE"; break;
                case COMPOUNDING_TIER_GROWTH:                   compoundingTierName = "GROWTH"; break;
                case COMPOUNDING_TIER_ACCELERATION:             compoundingTierName = "ACCELERATION"; break;
                case COMPOUNDING_TIER_INSTITUTIONAL:            compoundingTierName = "INSTITUTIONAL"; break;
                case COMPOUNDING_TIER_PROFESSIONAL:             compoundingTierName = "PROFESSIONAL"; break;
                case COMPOUNDING_TIER_HIGH_GROWTH:              compoundingTierName = "HIGH_GROWTH"; break;
                case COMPOUNDING_TIER_AGGRESSIVE_GROWTH:        compoundingTierName = "AGGRESSIVE_GROWTH"; break;
                case COMPOUNDING_TIER_MAXIMUM_GROWTH:           compoundingTierName = "MAXIMUM_GROWTH"; break;
                case COMPOUNDING_TIER_CAPITAL_PRESERVATION:     compoundingTierName = "CAPITAL_PRESERVATION"; break;
                default:                                        compoundingTierName = "UNKNOWN"; break;
            }
        
            return compoundingTierName + "/" + riskTierName;
        }

    // Key/value text in MQL5\Files: starting equity, peak equity, the milestone watermark, the tier
    // index, the switch count and the last switch time. Written on every transition and at teardown.
    static string StateFileName()
    {
        return "compounding_tier_state.csv";
    }

    int Load()
    {
        if(!FileIsExist(StateFileName()))
            return 0;

        int handle = FileOpen(StateFileName(), FILE_READ | FILE_TXT | FILE_ANSI);
        if(handle == INVALID_HANDLE)
        {
            PrintFormat("[COMPOUNDING-TIER] read failed | file=%s | err=%d", StateFileName(), GetLastError());
            return 0;
        }

        int rows = 0;
        if(!FileIsEnding(handle))
            FileReadString(handle); // header

        while(!FileIsEnding(handle))
        {
            string line = FileReadString(handle);
            if(StringLen(line) <= 0)
                continue;

            string parts[];
            int n = StringSplit(line, ';', parts);
            if(n < 2)
                continue;

            string key = parts[0];
            double value = StringToDouble(parts[1]);

            if(key == "startingEquity")      { m_startingEquity = value;           rows++; }
            else if(key == "peakEquity")     { m_peakEquity = value;               rows++; }
            else if(key == "highestMilestone"){ m_highestMilestoneReached = value; rows++; }
            else if(key == "tierIndex")      { m_currentTierIndex = (int)value;    rows++; }
            else if(key == "switches")       { m_switchCount = (int)value;         rows++; }
            else if(key == "lastSwitchTime") { m_lastTierSwitchTime = (datetime)(long)value; rows++; }
        }

        FileClose(handle);
        return rows;
    }

public:
    bool Save()
    {
        if(!m_initialized)
            return false;

        int handle = FileOpen(StateFileName(), FILE_WRITE | FILE_TXT | FILE_ANSI);
        if(handle == INVALID_HANDLE)
        {
            PrintFormat("[COMPOUNDING-TIER] save failed | file=%s | err=%d", StateFileName(), GetLastError());
            return false;
        }

        FileWriteString(handle, "key;value\r\n");
        FileWriteString(handle, StringFormat("startingEquity;%.2f\r\n", m_startingEquity));
        FileWriteString(handle, StringFormat("peakEquity;%.2f\r\n", m_peakEquity));
        FileWriteString(handle, StringFormat("highestMilestone;%.2f\r\n", m_highestMilestoneReached));
        FileWriteString(handle, StringFormat("tierIndex;%d\r\n", m_currentTierIndex));
        FileWriteString(handle, StringFormat("switches;%d\r\n", m_switchCount));
        FileWriteString(handle, StringFormat("lastSwitchTime;%I64d\r\n", (long)m_lastTierSwitchTime));
        FileClose(handle);
        return true;
    }

public:
    CCompoundingTierManager() : m_tierCount(0), m_currentTierIndex(-1),
        m_previousEquity(0), m_autoSwitchEnabled(true), m_initialized(false),
        m_highestMilestoneReached(0),
        m_lastTierSwitchTime(0), m_peakEquity(0), m_switchCount(0) {}

        bool Initialize(bool autoSwitch = true)
        {
            BuildTierConfigs();
            m_autoSwitchEnabled = autoSwitch;
            m_previousEquity = AccountInfoDouble(ACCOUNT_EQUITY);
            m_peakEquity = m_previousEquity;
            m_startingEquity = m_previousEquity;  // Track starting equity for % milestones

            // Restore what a restart used to throw away. Before this, every init re-seeded starting/peak
            // equity and the milestone watermark from the live account, so a restart silently lowered the
            // milestone baseline to the equity at restart and reset the tier history.
            int restored = Load();

            // The live account is authoritative for current equity; the file only supplies history.
            if(restored > 0)
            {
                double liveEquity = AccountInfoDouble(ACCOUNT_EQUITY);
                if(m_startingEquity <= 0.0)
                    m_startingEquity = liveEquity;
                if(liveEquity > m_peakEquity)
                {
                    PrintFormat("[COMPOUNDING-TIER] restored peak=%.2f is below live equity=%.2f | peak raised to live",
                                m_peakEquity, liveEquity);
                    m_peakEquity = liveEquity;
                }
                if(m_currentTierIndex < 0 || m_currentTierIndex >= m_tierCount)
                    m_currentTierIndex = FindTierIndex(m_previousEquity);

                PrintFormat("[COMPOUNDING-TIER] restored state | started=%.2f | peak=%.2f | highestMilestone=%.2f | tierIndex=%d | switches=%d",
                            m_startingEquity, m_peakEquity, m_highestMilestoneReached, m_currentTierIndex, m_switchCount);
            }
            else
            {
                m_currentTierIndex = FindTierIndex(m_previousEquity);
                PrintFormat("[COMPOUNDING-TIER] no saved state | file=%s | starting from live equity %.2f",
                            StateFileName(), m_previousEquity);
            }
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

// Driven from the orchestrator OnTimer tier check; returns true only when the tier index changed.
// The CTradeManager& argument is not referenced by this method.
        bool CheckTierTransition(CUnifiedRiskManager &riskMgr,
                                 CPositionSizer &posSizer,
                                 CTradeManager &tradeMgr)
        {
            if(!m_initialized || !m_autoSwitchEnabled)
                return false;

            double equity = AccountInfoDouble(ACCOUNT_EQUITY);
            if(equity > m_peakEquity)
                m_peakEquity = equity;

            // Milestone message only: it never selects a tier, FindTierIndex(equity) below does
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
                // The cooldown blocks every switch, upgrades included, and returns with no log line; a downgrade
                // additionally needs equity below 90% of the CURRENT tier's min
                datetime now = TimeCurrent();
                const int COOLDOWN_SECONDS = 3600; // 1 hour cooldown between tier changes
            
                if(now - m_lastTierSwitchTime < COOLDOWN_SECONDS)
                {
                    m_previousEquity = equity;
                    return false;
                }
            
                bool isUpgrade = (newTierIndex > m_currentTierIndex);
                bool isDowngrade = (newTierIndex < m_currentTierIndex);
            
                if(isDowngrade)
                {
                    double tierMinEquity = m_tiers[m_currentTierIndex].minEquity;
                    double hysteresisThreshold = tierMinEquity * 0.90; // 10% buffer
                
                    if(equity >= hysteresisThreshold)
                    {
                        PrintFormat("[COMPOUNDING-TIER] Downgrade blocked by hysteresis | equity=%.2f | threshold=%.2f | tierMin=%.2f",
                                    equity, hysteresisThreshold, tierMinEquity);
                        m_previousEquity = equity;
                        return false;
                    }
                }
            
                int oldIndex = m_currentTierIndex;
                m_currentTierIndex = newTierIndex;
                m_switchCount++;
                m_lastTierSwitchTime = now;

                PrintFormat("[COMPOUNDING-TIER] *** TIER TRANSITION *** | $%.2f -> $%.2f | %s -> %s | switch #%d",
                                        m_tiers[oldIndex].minEquity, m_tiers[newTierIndex].minEquity,
                            GetTierName(oldIndex), GetTierName(newTierIndex), m_switchCount);

                ApplyTierToRiskManager(riskMgr);
                ApplyTierToPositionSizer(posSizer, riskMgr);
                Save(); // a transition is the one moment the watermark must survive a restart

                string direction = isUpgrade ? "UPGRADE" : "DOWNGRADE";
                Alert("COMPOUNDING TIER ", direction, ": Account $", DoubleToString(equity, 2),
                      " | New tier: ", GetTierName(m_currentTierIndex),
                      " | Risk: ", DoubleToString(m_tiers[m_currentTierIndex].riskPerTradeOverride, 1), "%");

                m_previousEquity = equity;
                return true;
            }

            m_previousEquity = equity;
            return false;
        }

// Hands all eight overrides to CUnifiedRiskManager::ApplyTierOverrides, which clamps each value to the operator
// envelope captured at risk-manager init (a tier can lower risk, never raise it past the configured ceiling)
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
                tier.dailyLossLimitOverride,
                tier.maxRiskPerTradeOverride  // pass explicit override
            );

            PrintFormat("[COMPOUNDING-TIER] Applied to RiskManager | risk=%.1f%% | maxRisk=%.1f%% | daily=%.1f%% | portfolio=%.1f%% | ddWarn=%.1f%% | ddCrit=%.1f%% | maxPos=%d | dailyLoss=%.1f%%",
                        tier.riskPerTradeOverride,
                        tier.maxRiskPerTradeOverride,
                        tier.maxDailyRiskOverride,
                        tier.maxPortfolioRiskOverride,
                        tier.drawdownWarnOverride,
                        tier.drawdownCriticalOverride,
                        tier.maxConcurrentOverride,
                        tier.dailyLossLimitOverride);
    }

// CPositionSizer::SetParameters does no clamping, so the tier value is clamped here to the risk the
// manager actually approved after its own envelope clamp (ApplyTierToRiskManager runs first at both
// call sites). Without this the sizer sizes above the ceiling and the per-trade cap check refuses the
// entry instead of clamping it, so the tier trades nothing.
    void ApplyTierToPositionSizer(CPositionSizer &posSizer, CUnifiedRiskManager &riskManager)
    {
        if(m_currentTierIndex < 0 || m_currentTierIndex >= m_tierCount)
            return;

        SCompoundingTierConfig tier = m_tiers[m_currentTierIndex];
        double tierRisk = tier.riskPerTradeOverride;

        double approvedRisk = riskManager.GetActiveRiskPerTradePercent();
        bool clampedToEnvelope = (approvedRisk > 0.0 && tierRisk > approvedRisk);
        if(clampedToEnvelope)
            tierRisk = approvedRisk;

        SPositionSizingParams params = posSizer.GetParameters();
        params.riskPercent = tierRisk;
        posSizer.SetParameters(params);

        PrintFormat("[COMPOUNDING-TIER] Applied to PositionSizer | riskPercent=%.1f%% (tier %.1f%%%s)",
                    tierRisk, tier.riskPerTradeOverride,
                    clampedToEnvelope ? " | clamped to approved envelope" : "");
    }

    SCompoundingTierConfig GetCurrentTier() const
    {
        if(m_currentTierIndex >= 0 && m_currentTierIndex < m_tierCount)
            return m_tiers[m_currentTierIndex];

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

// The four accessors below are percent (0-100 scale) except GetMaxConcurrent (position count); each returns a
// hardcoded fallback (1.0 / 3 / 15.0 / 10.0) when no tier is active. No caller in this repo invokes them.
    double GetRiskPerTrade() const
    {
        if(m_currentTierIndex >= 0 && m_currentTierIndex < m_tierCount)
            return m_tiers[m_currentTierIndex].riskPerTradeOverride;
        return 1.0;
    }

    int GetMaxConcurrent() const
    {
        if(m_currentTierIndex >= 0 && m_currentTierIndex < m_tierCount)
            return m_tiers[m_currentTierIndex].maxConcurrentOverride;
        return 3;
    }

    double GetDailyLossLimit() const
    {
        if(m_currentTierIndex >= 0 && m_currentTierIndex < m_tierCount)
            return m_tiers[m_currentTierIndex].dailyLossLimitOverride;
        return 15.0;
    }

    double GetDrawdownCritical() const
    {
        if(m_currentTierIndex >= 0 && m_currentTierIndex < m_tierCount)
            return m_tiers[m_currentTierIndex].drawdownCriticalOverride;
        return 10.0;
    }

// Milestones are multiples of the equity captured at Initialize (1.25x, 1.5x, 2x, 3x, 6x); "" when none crossed
        string CheckMilestone(double prevEquity, double currEquity)
        {
            double milestones[] = {1.25, 1.50, 2.0, 3.0, 6.0};

            for(int i = 0; i < ArraySize(milestones); i++)
            {
                double milestoneEquity = m_startingEquity * milestones[i];
                // One-way watermark: a milestone at or below the highest already reached never re-fires
                if(prevEquity < milestoneEquity && currEquity >= milestoneEquity && milestoneEquity > m_highestMilestoneReached)
                {
                    m_highestMilestoneReached = milestoneEquity;
                    return StringFormat("ACCOUNT MILESTONE: %.0f%% growth ($%.0f -> $%.0f) reached",
                                        (milestones[i] - 1.0) * 100.0, m_startingEquity, milestoneEquity);
                }
            }
            return "";
        }

// SetAutoSwitch is called from the orchestrator config path; IsAutoSwitchEnabled has no caller
    void SetAutoSwitch(bool enabled) { m_autoSwitchEnabled = enabled; }
    bool IsAutoSwitchEnabled() const { return m_autoSwitchEnabled; }

// String only, no caller in this repo: the heartbeat uses GetHeartbeatString below
        string GetDiagnostics() const
        {
            return StringFormat("Tier=%s | Equity=$%.2f | Switches=%d | Peak=$%.2f",
                                (m_currentTierIndex >= 0) ? GetTierName(m_currentTierIndex) : "NONE",
                                m_previousEquity, m_switchCount, m_peakEquity);
        }

// Feeds [COMPOUNDING-TIER-HEARTBEAT] through DiagnosticsManager. "next_milestone" is the tier's equity ceiling and
// "balance" is previous equity - neither is the growth milestone CheckMilestone reports
        string GetHeartbeatString() const
        {
            if(m_currentTierIndex < 0 || m_currentTierIndex >= m_tierCount)
                return "UNINITIALIZED";
        
            SCompoundingTierConfig tier = m_tiers[m_currentTierIndex];
            double currentBalance = m_previousEquity;
            double nextMilestone = tier.maxEquity;
            double distToNext = nextMilestone - currentBalance;
        
            return StringFormat("tier=%s | balance=%.2f | next_milestone=%.2f | dist_to_next=%.2f | risk=%.1f%% | maxdd=%.1f%%",
                                GetTierName(m_currentTierIndex), currentBalance, nextMilestone,
                                distToNext, tier.riskPerTradeOverride, tier.drawdownCriticalOverride);
        }

        bool IsInitialized() const { return m_initialized; }
    int GetCurrentTierIndex() const { return m_currentTierIndex; }
    int GetSwitchCount() const { return m_switchCount; }
};

#endif // CORE_RISK_COMPOUNDING_TIER_MANAGER_MQH


