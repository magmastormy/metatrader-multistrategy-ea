//+------------------------------------------------------------------+
//| TradeSpreadCostModel.mqh                                         |
//| Stateless spread-cost estimation for a prospective/filled trade  |
//|                                                                  |
//| Extracted from Core/Trading/TradeManager.mqh in Phase D T1.      |
//| All members are static pure functions - no instance state.       |
//| Body is a verbatim copy of the original CalculateSpreadCost.     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property strict

#ifndef CORE_TRADING_TRADE_SPREAD_COST_MODEL_MQH
#define CORE_TRADING_TRADE_SPREAD_COST_MODEL_MQH

//+------------------------------------------------------------------+
//| Trade Spread Cost Model                                          |
//| Converts quoted spread into account-currency cost for a volume.  |
//+------------------------------------------------------------------+
class CTradeSpreadCostModel
{
public:
    // Calculate spread cost for a trade
    static double CalculateSpreadCost(const string symbol, const double volume)
    {
        if(symbol == "" || volume <= 0.0) {
            PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, 1605, __FUNCTION__);
            return 0.0;
        }

        double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);

        if(point <= 0.0 || tickSize <= 0.0) {
            PrintFormat("[DBG-RET0] %s:%d %s() return 0.0", __FILE__, 1613, __FUNCTION__);
            return 0.0;
        }

        // Spread cost = spread_points * point * volume * (tick_value / tick_size)
        double spreadCostPoints = spread * point;
        double valuePerPoint = tickValue / tickSize;
        double spreadCost = spreadCostPoints * volume * valuePerPoint;

        return spreadCost;
    }
};

#endif // CORE_TRADING_TRADE_SPREAD_COST_MODEL_MQH
//+------------------------------------------------------------------+
