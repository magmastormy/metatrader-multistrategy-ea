//+------------------------------------------------------------------+
//| DealInfo.mqh - Deal information class                            |
//| Copyright 2025, Your Company Name                                |
//| https://www.yoursite.com                                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Company Name"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

#ifndef __DEAL_INFO_MQH__
#define __DEAL_INFO_MQH__

#include <Object.mqh>
#include <Trade\DealInfo.mqh>

// Forward declaration
class CStrategySwing;

//+------------------------------------------------------------------+
//| Deal information class                                           |
//+------------------------------------------------------------------+
class CMyDealInfo : public CObject
{
private:
    CDealInfo *m_deal;  // Pointer to standard MQL5 CDealInfo
    
public:
    //--- Constructor/Destructor
    CMyDealInfo() { m_deal = new CDealInfo(); }
    ~CMyDealInfo() { delete m_deal; }
    
    //--- Deal properties
    ulong Order() const { if(!CheckPointer(m_deal)) return 0; return m_deal.Order(); }
    datetime Time() const { if(!CheckPointer(m_deal)) return 0; return m_deal.Time(); }
    ulong TimeMsc() const { if(!CheckPointer(m_deal)) return 0; return m_deal.TimeMsc(); }
    ENUM_DEAL_TYPE DealType() const { if(!CheckPointer(m_deal)) return (ENUM_DEAL_TYPE)0; return m_deal.DealType(); }
    string TypeDescription() const { if(!CheckPointer(m_deal)) return ""; return m_deal.TypeDescription(); }
    ENUM_DEAL_ENTRY Entry() const { if(!CheckPointer(m_deal)) return (ENUM_DEAL_ENTRY)0; return m_deal.Entry(); }
    string EntryDescription() const { if(!CheckPointer(m_deal)) return ""; return m_deal.EntryDescription(); }
    long Magic() const { if(!CheckPointer(m_deal)) return 0; return m_deal.Magic(); }
    long PositionId() const { if(!CheckPointer(m_deal)) return 0; return m_deal.PositionId(); }
    
    //--- Volume and price properties
    double Volume() const { if(!CheckPointer(m_deal)) return 0.0; return m_deal.Volume(); }
    double Price() const { if(!CheckPointer(m_deal)) return 0.0; return m_deal.Price(); }
    double Commission() const { if(!CheckPointer(m_deal)) return 0.0; return m_deal.Commission(); }
    double Swap() const { if(!CheckPointer(m_deal)) return 0.0; return m_deal.Swap(); }
    double Profit() const { if(!CheckPointer(m_deal)) return 0.0; return m_deal.Profit(); }
    
    //--- String properties
    string GetSymbol() const { if(!CheckPointer(m_deal)) return ""; return m_deal.Symbol(); }
    string Comment() const { if(!CheckPointer(m_deal)) return ""; return m_deal.Comment(); }
    string ExternalId() const { if(!CheckPointer(m_deal)) return ""; return m_deal.ExternalId(); }
    
    //--- Information methods
    long InfoInteger(const ENUM_DEAL_PROPERTY_INTEGER prop_id) const { if(!CheckPointer(m_deal)) return 0; long value; return m_deal.InfoInteger(prop_id, value) ? value : 0; }
    double InfoDouble(const ENUM_DEAL_PROPERTY_DOUBLE prop_id) const { if(!CheckPointer(m_deal)) return 0.0; double value; return m_deal.InfoDouble(prop_id, value) ? value : 0.0; }
    string InfoString(const ENUM_DEAL_PROPERTY_STRING prop_id) const { if(!CheckPointer(m_deal)) return ""; string value; return m_deal.InfoString(prop_id, value) ? value : ""; }
    
    //--- Formatting methods
    string FormatAction(string &str, const uint action) { str = IntegerToString(action); return str; }
    string FormatEntry(string &str, const uint entry) { str = IntegerToString(entry); return str; }
    string FormatDeal(string &str, const ulong deal) { str = IntegerToString(deal); return str; }
    
    //--- Selection methods
    bool SelectByIndex(const int index) { if(!CheckPointer(m_deal)) return false; return m_deal.SelectByIndex(index); }
};

// NOTE: Use CMyDealInfo in user code, not CDealInfo. Use GetSymbol() instead of Symbol() to avoid ambiguity.

#endif // __DEAL_INFO_MQH__
