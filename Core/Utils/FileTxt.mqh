//+------------------------------------------------------------------+
//| FileTxt.mqh - Text file operations class                         |
//| Copyright 2025, Your Company Name                                |
//| https://www.yoursite.com                                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Company Name"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

#ifndef __FILETXT_MQH__
#define __FILETXT_MQH__

#include "File.mqh"
#include <Files\FileTxt.mqh>

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
//| Text file operations class                                       |
//+------------------------------------------------------------------+
class CFileTxt : public CFile
{
private:
    CFileTxt *m_filetxt;  // Pointer to standard MQL5 CFileTxt
    
public:
    //--- Constructor/Destructor
    CFileTxt() { m_filetxt = new ::CFileTxt(); }
    ~CFileTxt() { delete m_filetxt; }
    
    //--- File operations
    bool Open(const string file_name, const int open_flags, const uint codepage = CP_ACP) 
    { 
        return m_filetxt.Open(file_name, open_flags, codepage); 
    }
    
    //--- Text operations
    void WriteString(const string text) { m_filetxt.WriteString(text); }
    string ReadString() { return m_filetxt.ReadString(); }
    
    //--- Close method
    void Close() { if(m_filetxt != NULL) m_filetxt.Close(); }
    
    //--- Check if file is open
    bool IsOpened() const { return (m_filetxt != NULL && m_filetxt.Handle() != INVALID_HANDLE); }
};

#endif // __FILETXT_MQH__
