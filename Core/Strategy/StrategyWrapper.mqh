//+------------------------------------------------------------------+
//| StrategyWrapper.mqh                                              |
//| Wrapper for strategy objects                                     |
//+------------------------------------------------------------------+
#ifndef __STRATEGY_WRAPPER_MQH__
#define __STRATEGY_WRAPPER_MQH__

#include <Object.mqh>
#include "../../Interfaces/IStrategy.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CModeManager;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;
class CAIStrategyOrchestrator;

//+------------------------------------------------------------------+
//| Wrapper for strategy objects                                     |
//+------------------------------------------------------------------+
class CStrategyWrapper : public CObject
{
private:
    IStrategy* m_strategy;
    string m_name;
    
public:
    CStrategyWrapper(IStrategy* inst)
    {
        m_strategy = inst;
        m_name = "";
        if(m_strategy != NULL)
        {
            m_name = m_strategy.GetName();
        }
    }
    
    ~CStrategyWrapper()
    {
        m_strategy = NULL;
    }
    
    IStrategy* Strategy() { return m_strategy; }
    string Name() { return m_name; }
};

#endif // __STRATEGY_WRAPPER_MQH__
