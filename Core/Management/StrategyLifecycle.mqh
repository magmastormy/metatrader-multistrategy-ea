// Enable/disable lifecycle, governance-driven activation and the per-bar strategy
// state transition: manual activation / deactivation by name, the governance and
// AI-degeneration sweeps, the cooldown / AI-recovery sweep and per-bar readiness reset.
// Like C4/C5 this module MUTATES the manager, so it holds a
// NON-const back-pointer and writes through the manager's narrow
// per-field accessors.
// DELIBERATELY NOT MOVED:
// - SyncEnabledWithRegistry(). It is enable/disable lifecycle by
// nature but is an explicit DO-NOT-TOUCH C9 guard: its body
// must stay verbatim in the manager and its only call site is
// Core/Orchestration/EAOrchestrator.mqh:768.
// - RegisterStrategy(). Registration allocates and Init()s the
// strategy object and owns the whole StrategyEntry construction
// (35+ field initialisers); relocating it would require a
// write accessor for every field in the struct, which is a
// wider contract than the extraction warrants.
// - The per-name governance setters (SetStrategyRoleByName,
// SetStrategyClusterByName, ...). Those are C4-class config
// setters that Slice 2 deliberately left in the manager.
// BEHAVIOURAL FIDELITY NOTES (both preserved verbatim, see the
// inline comments at the call sites):
// 1. CheckStrategyDisabling returns after delegating to the
// health monitor; CheckStrategyReEnabling does NOT and falls
// through into its fallback loop. This asymmetry exists in the
// original and is intentionally reproduced.
// 2. CheckStrategyReEnabling dereferences the strategy pointer
// without a NULL guard. Reproduced as-is.
// NOTE: this header is an implementation detail of
// EnterpriseStrategyManager.mqh and is included from there (after
// the shared free helpers, before the manager class). It is not
// intended to be included standalone.
#ifndef STRATEGY_LIFECYCLE_MQH
#define STRATEGY_LIFECYCLE_MQH

#include "../Utils/Enums.mqh"                          // ENUM_TRADE_SIGNAL, ENUM_TIMEFRAMES
#include "../../Interfaces/IStrategy.mqh"              // IStrategy::SetEnabled / ShouldDisableModel / OnNewBar
#include "StrategyHealthMonitor.mqh"                   // CStrategyHealthMonitor
#include "../Engines/FourStateRegimeDetector.mqh"      // CFourStateRegimeDetector
#include "../Visualization/ChartDrawingManager.mqh"    // CChartDrawingManager

class CEnterpriseStrategyManager;   // forward: held as a mutable pointer

// Lifecycle facade over CEnterpriseStrategyManager
class CStrategyLifecycle
{
private:
    CEnterpriseStrategyManager* m_src;

public:
    CStrategyLifecycle() : m_src(NULL) {}

    void SetSource(CEnterpriseStrategyManager* src) { m_src = src; }

    bool EnableStrategy(const string name);
    bool DisableStrategy(const string name);
    void CheckStrategyDisabling();
    void CheckStrategyReEnabling();
    void OnNewBar(const string symbol, ENUM_TIMEFRAMES timeframe);
};

bool CStrategyLifecycle::EnableStrategy(const string name)
{
    if(m_src == NULL)
        return false;

    int index = m_src.GetStrategyIndexByName(name);
    if(index < 0)
        return false;

    m_src.SetStrategyEnabledFlag(index, true);
    m_src.SetStrategyTemporarilyDisabled(index, false);
    m_src.SetStrategyDisabledUntil(index, 0);

    IStrategy* strategy = m_src.GetStrategyPtr(index);
    if(strategy != NULL)
        strategy.SetEnabled(true);

    PrintFormat("[EnterpriseStrategyManager] Strategy ENABLED: %s", name);
    return true;
}

bool CStrategyLifecycle::DisableStrategy(const string name)
{
    if(m_src == NULL)
        return false;

    int index = m_src.GetStrategyIndexByName(name);
    if(index < 0)
        return false;

    m_src.SetStrategyEnabledFlag(index, false);

    IStrategy* strategy = m_src.GetStrategyPtr(index);
    if(strategy != NULL)
        strategy.SetEnabled(false);

    PrintFormat("[EnterpriseStrategyManager] Strategy DISABLED: %s", name);
    return true;
}

void CStrategyLifecycle::CheckStrategyDisabling()
{
    if(m_src == NULL)
        return;

    CStrategyHealthMonitor* healthMonitor = m_src.GetHealthMonitor();
    if(healthMonitor != NULL)
    {
        healthMonitor.CheckAllStrategiesDisabling();
        return;
    }

    // Fallback if health monitor not initialized
    const int strategyCount = m_src.GetStrategyCount();
    for(int i = 0; i < strategyCount; i++)
    {
        IStrategy* strategy = m_src.GetStrategyPtr(i);
        if(strategy == NULL)
            continue;
        if(!m_src.IsStrategyEnabled(i))
            continue;
        if(m_src.IsStrategyTemporarilyDisabled(i))
            continue;

        // L6-006: Check AI model degeneration
        if(strategy.ShouldDisableModel())
        {
            m_src.SetStrategyTemporarilyDisabled(i, true);
            m_src.SetStrategyDisabledUntil(i, TimeCurrent() + 3600); // 1 hour cooldown
            m_src.SetStrategyEnabledFlag(i, false);
            PrintFormat("[Enterprise-Adaptation] Strategy %s disabled by AI model degeneration check",
                        m_src.GetStrategyName(i));
            continue;
        }

        if(m_src.ShouldDisableStrategy(i))
        {
            m_src.SetStrategyTemporarilyDisabled(i, true);
            m_src.SetStrategyDisabledUntil(i, TimeCurrent() + 3600); // 1 hour cooldown
            m_src.SetStrategyEnabledFlag(i, false);
            PrintFormat("[Enterprise-Adaptation] Strategy %s disabled by governance | recent_winrate=%.2f | losses=%d",
                        m_src.GetStrategyName(i),
                        m_src.GetStrategyRecentWinRate(i),
                        m_src.GetStrategyConsecutiveLosses(i));
        }
    }
}

void CStrategyLifecycle::CheckStrategyReEnabling()
{
    if(m_src == NULL)
        return;

    // L1-007: Delegate to CStrategyHealthMonitor.
    // NOTE (verbatim): unlike CheckStrategyDisabling this branch does NOT
    // return - the fallback loop below always runs. Preserved as-is.
    CStrategyHealthMonitor* healthMonitor = m_src.GetHealthMonitor();
    if(healthMonitor != NULL)
    {
        healthMonitor.CheckAllStrategiesReEnabling();
    }

    // Fallback if health monitor not initialized
    const int strategyCount = m_src.GetStrategyCount();
    for(int i = 0; i < strategyCount; i++)
    {
        if(m_src.IsStrategyEnabled(i))
            continue;
        if(!m_src.IsStrategyTemporarilyDisabled(i))
            continue;

        // L6-006: Check AI model recovery for re-enabling.
        // NOTE (verbatim): the original dereferences the strategy pointer with
        // no NULL guard here. Preserved as-is - no behaviour change.
        if(!m_src.GetStrategyPtr(i).ShouldDisableModel())
        {
            if(m_src.ShouldReEnableStrategy(i))
            {
                m_src.SetStrategyTemporarilyDisabled(i, false);
                m_src.SetStrategyDisabledUntil(i, 0);
                m_src.SetStrategyEnabledFlag(i, true);
                PrintFormat("[Enterprise-Adaptation] Strategy %s re-enabled after AI model recovery",
                            m_src.GetStrategyName(i));
            }
            continue;
        }

        if(m_src.ShouldReEnableStrategy(i))
        {
            m_src.SetStrategyTemporarilyDisabled(i, false);
            m_src.SetStrategyDisabledUntil(i, 0);
            m_src.SetStrategyEnabledFlag(i, true);
            PrintFormat("[Enterprise-Adaptation] Strategy %s re-enabled after cooldown",
                        m_src.GetStrategyName(i));
        }
    }
}

// Must be called from main EA on each new bar
void CStrategyLifecycle::OnNewBar(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    if(m_src == NULL)
        return;

    const int strategyCount = m_src.GetStrategyCount();
    if(!m_src.IsManagerInitialized() || strategyCount == 0)
        return;

    CChartDrawingManager* drawingManager = m_src.GetDrawingManager();
    if(drawingManager != NULL)
        drawingManager.CleanupOldObjects();

    // NOTE (verbatim): barTime is unused downstream, but iTime() may trigger
    // history loading as a side effect, so the call is preserved.
    datetime barTime = iTime(symbol, timeframe, 0);
    if(barTime <= 0)
        barTime = TimeCurrent();

    CFourStateRegimeDetector* regimeDetector = m_src.GetFourStateRegimeDetectorConst();
    if(regimeDetector != NULL && m_src.IsRegimeDetectorInitialized())
    {
        regimeDetector.Update();
    }

    // Call OnNewBar and persist per-bar analysis snapshots
    for(int i = 0; i < strategyCount; i++)
    {
        IStrategy* strategy = m_src.GetStrategyPtr(i);
        if(strategy == NULL)
            continue;

        if(m_src.IsStrategyEnabled(i))
        {
            strategy.OnNewBar(symbol, m_src.GetStrategyTimeframe(i));
        }
        else
        {
            m_src.SetStrategyLastSignal(i, TRADE_SIGNAL_NONE);
            m_src.SetStrategyLastSignalConfidence(i, 0.0);
        }
    }
}

#endif // STRATEGY_LIFECYCLE_MQH
