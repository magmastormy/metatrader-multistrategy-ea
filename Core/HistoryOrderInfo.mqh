//+------------------------------------------------------------------+
//| HistoryOrderInfo.mqh - Historical order information class        |
//| Copyright 2025, Your Company Name                                |
//| https://www.yoursite.com                                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Company Name"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

#ifndef __HISTORY_ORDER_INFO_MQH__
#define __HISTORY_ORDER_INFO_MQH__

#include <Object.mqh>
#include <Trade\HistoryOrderInfo.mqh>
#include "../Utilities/Utilities.mqh"
#include "ErrorHandling.mqh"

// Forward declaration
class CStrategySwing;

//+------------------------------------------------------------------+
//| Historical order information class                               |
//+------------------------------------------------------------------+
class CStrategySwing_HistoryOrderInfo : public CEnhancedErrorHandler
{
private:
    CHistoryOrderInfo m_history_order;  // Pointer to standard MQL5 CHistoryOrderInfo
    
public:
    //--- Constructor/Destructor
    CStrategySwing_HistoryOrderInfo() { m_history_order = CHistoryOrderInfo(); }
    ~CStrategySwing_HistoryOrderInfo() { }
    
    //--- Order properties
    datetime TimeSetup() { if(!POINTER_VALID(&m_history_order)) return 0; return m_history_order.TimeSetup(); }
    datetime TimeSetupMsc() { if(!POINTER_VALID(&m_history_order)) return 0; return (datetime)m_history_order.TimeSetupMsc(); }
    datetime TimeDone() { if(!POINTER_VALID(&m_history_order)) return 0; return m_history_order.TimeDone(); }
    datetime TimeDoneMsc() { if(!POINTER_VALID(&m_history_order)) return 0; return (datetime)m_history_order.TimeDoneMsc(); }
    ENUM_ORDER_TYPE OrderType() { if(!POINTER_VALID(&m_history_order)) return (ENUM_ORDER_TYPE)0; return m_history_order.OrderType(); }
    string TypeDescription() { if(!POINTER_VALID(&m_history_order)) return ""; return m_history_order.TypeDescription(); }
    ENUM_ORDER_STATE State() { if(!POINTER_VALID(&m_history_order)) return (ENUM_ORDER_STATE)0; return m_history_order.State(); }
    string StateDescription() { if(!POINTER_VALID(&m_history_order)) return ""; return m_history_order.StateDescription(); }
    datetime TimeExpiration() { if(!POINTER_VALID(&m_history_order)) return 0; return m_history_order.TimeExpiration(); }
    ENUM_ORDER_TYPE_FILLING TypeFilling() { if(!POINTER_VALID(&m_history_order)) return (ENUM_ORDER_TYPE_FILLING)0; return m_history_order.TypeFilling(); }
    string TypeFillingDescription() { if(!POINTER_VALID(&m_history_order)) return ""; return m_history_order.TypeFillingDescription(); }
    ENUM_ORDER_TYPE_TIME TypeTime() { if(!POINTER_VALID(&m_history_order)) return (ENUM_ORDER_TYPE_TIME)0; return m_history_order.TypeTime(); }
    string TypeTimeDescription() { if(!POINTER_VALID(&m_history_order)) return ""; return m_history_order.TypeTimeDescription(); }
    long Magic() { if(!POINTER_VALID(&m_history_order)) return 0; return m_history_order.Magic(); }
    long PositionId() { if(!POINTER_VALID(&m_history_order)) return 0; return m_history_order.PositionId(); }
    long PositionById() { if(!POINTER_VALID(&m_history_order)) return 0; return m_history_order.PositionById(); }
    
    //--- Volume and price properties
    double VolumeInitial() { if(!POINTER_VALID(&m_history_order)) return 0.0; return m_history_order.VolumeInitial(); }
    double VolumeCurrent() { if(!POINTER_VALID(&m_history_order)) return 0.0; return m_history_order.VolumeCurrent(); }
    double PriceOpen() { if(!POINTER_VALID(&m_history_order)) return 0.0; return m_history_order.PriceOpen(); }
    double StopLoss() { if(!POINTER_VALID(&m_history_order)) return 0.0; return m_history_order.StopLoss(); }
    double TakeProfit() { if(!POINTER_VALID(&m_history_order)) return 0.0; return m_history_order.TakeProfit(); }
    double PriceCurrent() { if(!POINTER_VALID(&m_history_order)) return 0.0; return m_history_order.PriceCurrent(); }
    double PriceStopLimit() { if(!POINTER_VALID(&m_history_order)) return 0.0; return m_history_order.PriceStopLimit(); }
    
    //--- String properties
    string Symbol() { if(!POINTER_VALID(&m_history_order)) return ""; return m_history_order.Symbol(); }
    string Comment() { if(!POINTER_VALID(&m_history_order)) return ""; return m_history_order.Comment(); }
    string ExternalId() { if(!POINTER_VALID(&m_history_order)) return ""; return m_history_order.ExternalId(); }
    
    //--- Information methods
    long InfoInteger(const ENUM_ORDER_PROPERTY_INTEGER prop_id) { if(!POINTER_VALID(&m_history_order)) return 0; long value; return m_history_order.InfoInteger(prop_id, value) ? value : 0; }
    double InfoDouble(const ENUM_ORDER_PROPERTY_DOUBLE prop_id) { if(!POINTER_VALID(&m_history_order)) return 0.0; double value; return m_history_order.InfoDouble(prop_id, value) ? value : 0.0; }
    string InfoString(const ENUM_ORDER_PROPERTY_STRING prop_id) { if(!POINTER_VALID(&m_history_order)) return ""; string value; return m_history_order.InfoString(prop_id, value) ? value : ""; }
    
    //--- Formatting methods
    static string FormatType(string &str, const ENUM_ORDER_TYPE type) { str = EnumToString(type); return str; }
    static string FormatStatus(string &str, const ENUM_ORDER_STATE status) { str = EnumToString(status); return str; }
    static string FormatTypeFilling(string &str, const ENUM_ORDER_TYPE_FILLING type) { str = EnumToString(type); return str; }
    static string FormatTypeTime(string &str, const ENUM_ORDER_TYPE_TIME type) { str = EnumToString(type); return str; }
    static string FormatOrder(string &str, const long order) { str = IntegerToString(order); return str; }
    static string FormatPrice(string &str, const double price, const double point = 0.0, const uint digits = 0) 
    { 
        str = DoubleToString(price, (int)digits); 
        return str; 
    }
    
    //--- Selection methods
    bool SelectByIndex(const int index) { if(!POINTER_VALID(&m_history_order)) return false; return m_history_order.SelectByIndex(index); }
    
    //--- State management
    bool StoreState() { if(!POINTER_VALID(&m_history_order)) return false; return true; }
    bool CheckState() { if(!POINTER_VALID(&m_history_order)) return false; return true; }
};

#endif // __HISTORY_ORDER_INFO_MQH__
