//+------------------------------------------------------------------+
//| OrderInfo.mqh - Order information class                          |
//| Copyright 2025, Your Company Name                                |
//| https://www.yoursite.com                                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Company Name"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

#ifndef __ORDER_INFO_MQH__
#define __ORDER_INFO_MQH__

#include <Object.mqh>
#include <Trade\OrderInfo.mqh>
#include "ErrorHandling.mqh"

//+------------------------------------------------------------------+
//| Wrapper for MQL5 COrderInfo class                                |
//+------------------------------------------------------------------+
class CWrapperOrderInfo : public CEnhancedErrorHandler
{
private:
    COrderInfo m_order; // Composition: directly include COrderInfo object

public:
    //--- Constructor/Destructor
    CWrapperOrderInfo() {}
    ~CWrapperOrderInfo() {}

    //--- Order properties (wrapped methods)
    ulong Ticket() const { return m_order.Ticket(); }
    datetime TimeSetup() const { return m_order.TimeSetup(); }
    ulong TimeSetupMsc() const { return m_order.TimeSetupMsc(); }
    datetime TimeDone() const { return m_order.TimeDone(); }
    ulong TimeDoneMsc() const { return m_order.TimeDoneMsc(); }
    datetime TimeExpiration() const { return m_order.TimeExpiration(); }
    int Type() const { return m_order.Type(); }
    string TypeDescription() const { return m_order.TypeDescription(); }
    ENUM_ORDER_STATE State() const { return m_order.State(); }
    string StateDescription() const { return m_order.StateDescription(); }
    ENUM_ORDER_TYPE_FILLING TypeFilling() const { return m_order.TypeFilling(); }
    string TypeFillingDescription() const { return m_order.TypeFillingDescription(); }
    ENUM_ORDER_TYPE_TIME TypeTime() const { return m_order.TypeTime(); }
    string TypeTimeDescription() const { return m_order.TypeTimeDescription(); }
    long Magic() const { return m_order.Magic(); }
    ulong PositionID(void) const { long value; return InfoInteger(ORDER_POSITION_ID, value) ? (ulong)value : 0; }
    ulong PositionByID(void) const { long value; return InfoInteger(ORDER_POSITION_BY_ID, value) ? (ulong)value : 0; }

    //--- Volume and price properties
    double VolumeInitial() const { return m_order.VolumeInitial(); }
    double VolumeCurrent() const { return m_order.VolumeCurrent(); }
    double PriceOpen() const { return m_order.PriceOpen(); }
    double SL(void) const { double value; return InfoDouble(ORDER_SL, value) ? value : 0.0; }
    double TP(void) const { double value; return InfoDouble(ORDER_TP, value) ? value : 0.0; }
    double PriceCurrent() const { return m_order.PriceCurrent(); }
    double PriceStopLimit() const { return m_order.PriceStopLimit(); }

    //--- String properties
    string Symbol() const { return m_order.Symbol(); }
    string Comment() const { return m_order.Comment(); }
    string ExternalID(void) const { string value; return InfoString(ORDER_EXTERNAL_ID, value) ? value : ""; }

    //--- Information methods
    bool InfoInteger(ENUM_ORDER_PROPERTY_INTEGER prop_id, long &value) const { return m_order.InfoInteger(prop_id, value); }
    bool InfoDouble(ENUM_ORDER_PROPERTY_DOUBLE prop_id, double &value) const { return m_order.InfoDouble(prop_id, value); }
    bool InfoString(ENUM_ORDER_PROPERTY_STRING prop_id, string &value) const { return m_order.InfoString(prop_id, value); }

    //--- Selection methods
    bool Select(ulong ticket) { return m_order.Select(ticket); }
    bool SelectByIndex(int index) { return m_order.SelectByIndex(index); }

    //--- State management
    void StoreState() { m_order.StoreState(); }
    bool CheckState() { return m_order.CheckState(); }
};

// NOTE: InfoInteger, InfoDouble, InfoString, and Format* methods must be called with the correct parameter types and counts. Do not pass extra parameters or references. Use explicit casting for ulong to datetime where needed. No implicit int-to-string conversions allowed.

#endif // __ORDER_INFO_MQH__
