//+------------------------------------------------------------------+
//| Trade.mqh - Trade operations class                                |
//| Copyright 2025, Your Company Name                                |
//| https://www.yoursite.com                                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Company Name"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

#ifndef __TRADE_MQH__
#define __TRADE_MQH__

#include <Trade\Trade.mqh>
#include <Object.mqh>

// Forward declaration
class CStrategySwing;

//+------------------------------------------------------------------+
//| Trade operations class                                           |
//+------------------------------------------------------------------+
class CTradeWrapper : public CObject
{
private:
    CTrade m_trade;  // Standard MQL5 CTrade object

public:
    //--- Constructor/Destructor
    CTradeWrapper() {}
    ~CTradeWrapper() {}

    //--- Position operations
    bool PositionOpen(const string symbolParam, const ENUM_ORDER_TYPE order_type, double volume, double price,
                      double sl, double tp, const string comment = "")
    { return m_trade.PositionOpen(symbolParam, order_type, volume, price, sl, tp, comment); }

    bool PositionModify(const string symbolParam, double sl, double tp)
    { return m_trade.PositionModify(symbolParam, sl, tp); }

    bool PositionModify(const ulong ticket, double sl, double tp)
    { return m_trade.PositionModify(ticket, sl, tp); }

    bool PositionClose(const string symbolParam, const ulong deviation = ULONG_MAX)
    { return m_trade.PositionClose(symbolParam, deviation); }

    bool PositionClose(const ulong ticket, const ulong deviation = ULONG_MAX)
    { return m_trade.PositionClose(ticket, deviation); }

    bool PositionCloseBy(const ulong ticket, const ulong ticket_by)
    { return m_trade.PositionCloseBy(ticket, ticket_by); }

    bool PositionClosePartial(const string symbolParam, const double volume, const ulong deviation = ULONG_MAX)
    { return m_trade.PositionClosePartial(symbolParam, volume, deviation); }

    bool PositionClosePartial(const ulong ticket, const double volume, const ulong deviation = ULONG_MAX)
    { return m_trade.PositionClosePartial(ticket, volume, deviation); }

    //--- Order operations
    bool OrderOpen(const string symbolParam, const ENUM_ORDER_TYPE order_type, const double volume,
                   const double limit_price, const double price, const double sl, const double tp,
                   const ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC, const datetime expiration = 0,
                   const string comment = "")
    { return m_trade.OrderOpen(symbolParam, order_type, volume, limit_price, price, sl, tp, type_time, expiration, comment); }

    bool OrderModify(const ulong ticket, const double price, const double sl, const double tp, 
                     const ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC, const datetime expiration = 0, 
                     const double stoplimit = 0.0)
    { return m_trade.OrderModify(ticket, price, sl, tp, type_time, expiration, stoplimit); }

    bool OrderDelete(const ulong ticket)
    { return m_trade.OrderDelete(ticket); }

    //--- Trade operations
    bool Buy(const double volume, const string symbolParam = NULL, double price = 0.0,
             const double sl = 0.0, const double tp = 0.0, const string comment = "")
    { return m_trade.Buy(volume, symbolParam, price, sl, tp, comment); }

    bool Sell(const double volume, const string symbolParam = NULL, double price = 0.0,
              const double sl = 0.0, const double tp = 0.0, const string comment = "")
    { return m_trade.Sell(volume, symbolParam, price, sl, tp, comment); }

    bool BuyLimit(const double volume, const double price, const string symbolParam = NULL,
                  const double sl = 0.0, const double tp = 0.0,
                  const ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC, const datetime expiration = 0,
                  const string comment = "")
    { return m_trade.BuyLimit(volume, price, symbolParam, sl, tp, type_time, expiration, comment); }

    bool BuyStop(const double volume, const double price, const string symbolParam = NULL,
                 const double sl = 0.0, const double tp = 0.0,
                 const ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC, const datetime expiration = 0,
                 const string comment = "")
    { return m_trade.BuyStop(volume, price, symbolParam, sl, tp, type_time, expiration, comment); }

    bool SellLimit(const double volume, const double price, const string symbolParam = NULL,
                   const double sl = 0.0, const double tp = 0.0,
                   const ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC, const datetime expiration = 0,
                   const string comment = "")
    { return m_trade.SellLimit(volume, price, symbolParam, sl, tp, type_time, expiration, comment); }

    bool SellStop(const double volume, const double price, const string symbolParam = NULL,
                  const double sl = 0.0, const double tp = 0.0,
                  const ENUM_ORDER_TYPE_TIME type_time = ORDER_TIME_GTC, const datetime expiration = 0,
                  const string comment = "")
    { return m_trade.SellStop(volume, price, symbolParam, sl, tp, type_time, expiration, comment); }

    //--- Validation methods
    bool OrderCheck(const MqlTradeRequest &request, MqlTradeCheckResult &check_result)
    { return m_trade.OrderCheck(request, check_result); }

    bool OrderSend(const MqlTradeRequest &request, MqlTradeResult &result)
    { return m_trade.OrderSend(request, result); }

    //--- Utility methods
    void PrintRequest() { m_trade.PrintRequest(); }
    void PrintResult() { m_trade.PrintResult(); }
    void ClearStructures() { /* Protected method - stubbed */ }
    bool IsStopped(const string symbolParam = "") { /* Protected method - stubbed */ return false; }
    bool SelectPosition(const string symbolParam) { /* Protected method - stubbed */ return false; }
};

#endif // __TRADE_MQH__
