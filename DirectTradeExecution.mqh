//+------------------------------------------------------------------+
//| Direct Trade Execution Functions                                 |
//| Handles direct trade execution when trade manager is unavailable |
//+------------------------------------------------------------------+

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

static CTrade m_trade; // Local static trade instance
// Note: m_positionInfo, g_totalActivePositions, g_activePairs are globals from main EA

//+------------------------------------------------------------------+
//| Execute trade directly using CTrade                              |
//+------------------------------------------------------------------+
bool ExecuteDirectTrade(string symbol, ENUM_ORDER_TYPE orderType, double lotSize, double stopLoss, double takeProfit)
{
    // Set magic number for identification
    m_trade.SetExpertMagicNumber(12345);
    m_trade.SetDeviationInPoints(3);
    
    bool result = false;
    string comment = "Intelligent EA Trade";
    
    if(orderType == ORDER_TYPE_BUY) {
        result = m_trade.Buy(lotSize, symbol, 0, stopLoss, takeProfit, comment);
    } else if(orderType == ORDER_TYPE_SELL) {
        result = m_trade.Sell(lotSize, symbol, 0, stopLoss, takeProfit, comment);
    }
    
    if(!result) {
        Print("[TRADE-ERROR] Failed to execute ", EnumToString(orderType), " for ", symbol);
        Print("[TRADE-ERROR] Error code: ", GetLastError());
        Print("[TRADE-ERROR] Result code: ", m_trade.ResultRetcode());
        Print("[TRADE-ERROR] Result comment: ", m_trade.ResultComment());
    }
    
    return result;
}

//+------------------------------------------------------------------+
//| Update position counter from actual positions                    |
//+------------------------------------------------------------------+
void UpdatePositionCounter()
{
    g_totalActivePositions = PositionsTotal();
    
    // Update active pairs array
    ArrayResize(g_activePairs, 0);
    
    for(int i = 0; i < PositionsTotal(); i++) {
        if(m_positionInfo.SelectByIndex(i)) {
            string posSymbol = m_positionInfo.Symbol();
            
            // Add to active pairs if not already present
            bool found = false;
            for(int j = 0; j < ArraySize(g_activePairs); j++) {
                if(g_activePairs[j] == posSymbol) {
                    found = true;
                    break;
                }
            }
            
            if(!found) {
                ArrayResize(g_activePairs, ArraySize(g_activePairs) + 1);
                g_activePairs[ArraySize(g_activePairs) - 1] = posSymbol;
            }
        }
    }
}
