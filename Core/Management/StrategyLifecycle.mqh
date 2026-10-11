// Writes through the manager's narrow per-field accessors via a NON-const back-pointer.
// Include only from EnterpriseStrategyManager.mqh; it is not usable standalone.
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

    // Unlike CheckStrategyDisabling, this branch does NOT return: the loop below always runs.
    CStrategyHealthMonitor* healthMonitor = m_src.GetHealthMonitor();
    if(healthMonitor != NULL)
    {
        healthMonitor.CheckAllStrategiesReEnabling();
    }

    const int strategyCount = m_src.GetStrategyCount();
    for(int i = 0; i < strategyCount; i++)
    {
        if(m_src.IsStrategyEnabled(i))
            continue;
        if(!m_src.IsStrategyTemporarilyDisabled(i))
            continue;

        // GetStrategyPtr(i) is dereferenced with no NULL guard here; kept as-is deliberately.
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

    // barTime is unused downstream, but iTime() triggers history loading as a side effect.
    datetime barTime = iTime(symbol, timeframe, 0);
    if(barTime <= 0)
        barTime = TimeCurrent();

    CFourStateRegimeDetector* regimeDetector = m_src.GetFourStateRegimeDetectorConst();
    if(regimeDetector != NULL && m_src.IsRegimeDetectorInitialized())
    {
        regimeDetector.Update();
    }

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
