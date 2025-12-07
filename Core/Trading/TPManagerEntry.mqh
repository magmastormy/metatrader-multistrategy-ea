//+------------------------------------------------------------------+
//| TPManagerEntry.mqh                                               |
//| Progressive TP entry wrapper per position                        |
//+------------------------------------------------------------------+
#ifndef __TP_MANAGER_ENTRY_MQH__
#define __TP_MANAGER_ENTRY_MQH__

#include <Object.mqh>
#include "ProgressiveTakeProfit.mqh"

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
//| Progressive TP entry wrapper per position                        |
//+------------------------------------------------------------------+
class CTPManagerEntry : public CObject
{
public:
    string                 symbol;
    ulong                  ticket;
    ENUM_ORDER_TYPE        orderType;
    double                 entryPrice;
    CProgressiveTakeProfit *manager;

    CTPManagerEntry(const string &symbolName, const ulong orderTicket, const ENUM_ORDER_TYPE type, const double price, CProgressiveTakeProfit *tpManager) :
        symbol(symbolName),
        ticket(orderTicket),
        orderType(type),
        entryPrice(price),
        manager(tpManager)
    {
    }

    virtual ~CTPManagerEntry()
    {
        if(CheckPointer(manager) == POINTER_DYNAMIC)
        {
            delete manager;
            manager = NULL;
        }
    }
};

#endif // __TP_MANAGER_ENTRY_MQH__
