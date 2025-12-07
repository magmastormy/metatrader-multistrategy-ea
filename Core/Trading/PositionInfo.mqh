//+------------------------------------------------------------------+
//| PositionInfo.mqh - Position information class                     |
//| Copyright 2025, Your Company Name                                |
//| https://www.yoursite.com                                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Company Name"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

#ifndef __POSITION_INFO_MQH__
#define __POSITION_INFO_MQH__

#include <Object.mqh>
#include <Trade\PositionInfo.mqh>
#include "../Utils/ErrorHandling.mqh"

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

// Forward declaration
class CStrategySwing;

//+------------------------------------------------------------------+
//| Position information class                                       |
//+------------------------------------------------------------------+
class CWrapperPositionInfo : public CEnhancedErrorHandler
{
private:
    CPositionInfo *m_position;  // Pointer to standard MQL5 CPositionInfo
    
public:
    //--- Constructor/Destructor
    CWrapperPositionInfo() { m_position = new CPositionInfo(); }
    ~CWrapperPositionInfo() { delete m_position; }
    
    //--- Position properties
    ulong Ticket() const { if(!CheckPointer(m_position)) return 0; return m_position.Ticket(); }
    datetime Time() const { if(!CheckPointer(m_position)) return 0; return m_position.Time(); }
    ulong TimeMsc() const { if(!CheckPointer(m_position)) return 0; return m_position.TimeMsc(); }
    datetime TimeUpdate() const { if(!CheckPointer(m_position)) return 0; return m_position.TimeUpdate(); }
    ulong TimeUpdateMsc() const { if(!CheckPointer(m_position)) return 0; return m_position.TimeUpdateMsc(); }
    int Type() const { if(!CheckPointer(m_position)) return 0; return m_position.PositionType(); }
    ENUM_POSITION_TYPE PositionType() const { if(!CheckPointer(m_position)) return (ENUM_POSITION_TYPE)0; return m_position.PositionType(); }
    string TypeDescription() const { if(!CheckPointer(m_position)) return ""; return m_position.TypeDescription(); }
    long Magic() const { if(!CheckPointer(m_position)) return 0; return m_position.Magic(); }
    long Identifier() const { if(!CheckPointer(m_position)) return 0; return m_position.Identifier(); }
    
    //--- Volume and price properties
    double Volume() const { if(!CheckPointer(m_position)) return 0.0; return m_position.Volume(); }
    double PriceOpen() const { if(!CheckPointer(m_position)) return 0.0; return m_position.PriceOpen(); }
    double StopLoss() const { if(!CheckPointer(m_position)) return 0.0; return m_position.StopLoss(); }
    double TakeProfit() const { if(!CheckPointer(m_position)) return 0.0; return m_position.TakeProfit(); }
    double PriceCurrent() const { if(!CheckPointer(m_position)) return 0.0; return m_position.PriceCurrent(); }
    double Commission() const { if(!CheckPointer(m_position)) return 0.0; return m_position.Commission(); }
    double Swap() const { if(!CheckPointer(m_position)) return 0.0; return m_position.Swap(); }
    double Profit() const { if(!CheckPointer(m_position)) return 0.0; return m_position.Profit(); }
    
    //--- String properties
    string Symbol() const { if(!CheckPointer(m_position)) return ""; return m_position.Symbol(); }
    string Comment() const { if(!CheckPointer(m_position)) return ""; return m_position.Comment(); }
    
    //--- Information methods
    long InfoInteger(const ENUM_POSITION_PROPERTY_INTEGER prop_id) const { if(!CheckPointer(m_position)) return 0; long value; return m_position.InfoInteger(prop_id, value) ? value : 0; }
    double InfoDouble(const ENUM_POSITION_PROPERTY_DOUBLE prop_id) const { if(!CheckPointer(m_position)) return 0.0; double value; return m_position.InfoDouble(prop_id, value) ? value : 0.0; }
    string InfoString(const ENUM_POSITION_PROPERTY_STRING prop_id) const { if(!CheckPointer(m_position)) return ""; string value; return m_position.InfoString(prop_id, value) ? value : ""; }
    
    //--- Formatting methods
    static string FormatType(string &str, const ENUM_POSITION_TYPE type) { str = EnumToString(type); return str; }
    static string FormatPosition(string &str, const string symbol) 
    { 
        str = symbol; 
        return str; 
    }
    
    //--- Selection methods
    bool Select(const string symbol) { if(!CheckPointer(m_position)) return false; return m_position.Select(symbol); }
    bool SelectByMagic(const string symbol, const ulong magic) { if(!CheckPointer(m_position)) return false; return m_position.SelectByMagic(symbol, magic); }
    bool SelectByTicket(const ulong ticket) { if(!CheckPointer(m_position)) return false; return m_position.SelectByTicket(ticket); }
    bool SelectByIndex(const int index, const int pool_index=0) { if(!CheckPointer(m_position)) return false; return m_position.SelectByIndex(index); }
    
    //--- State management
    bool StoreState() { if(!CheckPointer(m_position)) return false; return true; }
    bool CheckState() { if(!CheckPointer(m_position)) return false; return m_position.CheckState(); }
};

#endif // __POSITION_INFO_MQH__
