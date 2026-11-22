// Writes through the manager's narrow per-field accessors via a NON-const back-pointer.
// Include only from EnterpriseStrategyManager.mqh; it is not usable standalone.
#ifndef STRATEGY_LIFECYCLE_MQH
#define STRATEGY_LIFECYCLE_MQH

#include "../Utils/Enums.mqh"                          // ENUM_TRADE_SIGNAL, ENUM_TIMEFRAMES
#include "../../Interfaces/IStrategy.mqh"              // IStrategy::SetEnabled / ShouldDisableModel / OnNewBar
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

    void OnNewBar(const string symbol, ENUM_TIMEFRAMES timeframe);
};

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
