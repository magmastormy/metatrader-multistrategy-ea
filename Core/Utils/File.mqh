//+------------------------------------------------------------------+
//| File.mqh - File operations class                                 |
//| Copyright 2025, Your Company Name                                |
//| https://www.yoursite.com                                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Company Name"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

#ifndef __FILE_MQH__
#define __FILE_MQH__

#include <Object.mqh>
#include <Files\File.mqh>

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
//| File operations class                                            |
//+------------------------------------------------------------------+
class CStrategySwing::CFile : public CObject
{
private:
    CFile *m_file;  // Pointer to standard MQL5 CFile
    
public:
    //--- Constructor/Destructor
    CFile() { m_file = new CFile(); }
    ~CFile() { delete m_file; }
    
    //--- File operations
    void SetUnicode(const bool mode) { m_file->SetUnicode(mode); }
    void SetCommon(const bool common) { m_file->SetCommon(common); }
    
    //--- File handling
    bool Open(const string file_name, const int open_flags, const short delimiter = '\t', 
              const uint codepage = CP_ACP) 
    { 
        return m_file->Open(file_name, open_flags, delimiter, codepage); 
    }
    
    void Close() { m_file->Close(); }
    bool Delete() { return m_file->Delete(); }
    
    //--- File properties
    ulong Size() const { return m_file->Size(); }
    ulong Tell() const { return m_file->Tell(); }
    bool Seek(const long offset, const ENUM_FILE_POSITION origin) { return m_file->Seek(offset, origin); }
    void Flush() { m_file->Flush(); }
    
    //--- Position checking
    bool IsEnding() const { return m_file->IsEnding(); }
    bool IsLineEnding() const { return m_file->IsLineEnding(); }
    
    //--- Static file operations
    static bool Delete(const string file_name, const int common_flag = FILE_COMMON) 
    { 
        return CFile::Delete(file_name, common_flag); 
    }
    
    static bool IsExist(const string file_name, const int common_flag = FILE_COMMON) 
    { 
        return CFile::IsExist(file_name, common_flag); 
    }
    
    static bool Copy(const string src_file, const string dst_file, const int common_flags = 0) 
    { 
        return CFile::Copy(src_file, dst_file, common_flags); 
    }
    
    static bool Move(const string src_file, const string dst_file, const int common_flags = 0) 
    { 
        return CFile::Move(src_file, dst_file, common_flags); 
    }
    
    //--- Directory operations
    static bool FolderCreate(const string folder_name, const int common_flag = FILE_COMMON) 
    { 
        return CFile::FolderCreate(folder_name, common_flag); 
    }
    
    static bool FolderDelete(const string folder_name, const int common_flag = FILE_COMMON) 
    { 
        return CFile::FolderDelete(folder_name, common_flag); 
    }
    
    static bool FolderClean(const string folder_name, const int common_flag = FILE_COMMON) 
    { 
        return CFile::FolderClean(folder_name, common_flag); 
    }
    
    //--- File search operations
    static long FileFindFirst(const string file_filter, string &found_file, int common_flag = FILE_COMMON) 
    { 
        return CFile::FileFindFirst(file_filter, found_file, common_flag); 
    }
    
    static bool FileFindNext(const long search_handle, string &found_file) 
    { 
        return CFile::FileFindNext(search_handle, found_file); 
    }
    
    static void FileFindClose(const long search_handle) 
    { 
        CFile::FileFindClose(search_handle); 
    }
};

#endif // __FILE_MQH__
