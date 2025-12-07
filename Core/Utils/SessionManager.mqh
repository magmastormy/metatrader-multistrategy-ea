//+------------------------------------------------------------------+
//| Session Memory Management Module                                   |
//+------------------------------------------------------------------+
#ifndef __SESSION_MANAGER_MQH__
#define __SESSION_MANAGER_MQH__

#include <Files/FileTxt.mqh>
#include "MarketAnalysis.mqh"
#include "StrategyManager.mqh"

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

// Declare that these global variables are defined elsewhere (in the .mq5 file)
extern CMarketAnalysis  *marketAnalysis;
extern CStrategyManager *strategyManager;

class CSessionManager {
private:
    string m_sessionFilePrefix;
    datetime m_lastFullProcessTime;
    string m_processedSymbols[];
    int m_symbolIndex;
    int m_maxAge;  // Maximum age for memory objects in seconds
    
    // File operations
    bool SaveToFile(const string &filename, const string &content) {
        int fileHandle = FileOpen(filename, FILE_WRITE|FILE_TXT);
        if(fileHandle != INVALID_HANDLE) {
            FileWriteString(fileHandle, content);
            FileClose(fileHandle);
            return true;
        }
        Print("[ERROR] SaveToFile: Failed to open file ", filename, " for writing");
        return false;
    }
    
    string LoadFromFile(const string &filename) {
        if(!FileIsExist(filename)) {
            Print("[INFO] LoadFromFile: File does not exist: ", filename);
            return "";
        }
        
        int fileHandle = FileOpen(filename, FILE_READ|FILE_TXT);
        if(fileHandle == INVALID_HANDLE) {
            Print("[ERROR] LoadFromFile: Failed to open file ", filename);
            return "";
        }
        
        string content = "";
        while(!FileIsEnding(fileHandle)) {
            content += FileReadString(fileHandle) + "\n";
        }
        FileClose(fileHandle);
        return content;
    }
    
    // Parse session data
    bool ParseSessionData(const string &content, string &key, string &value) {
        string parts[];
        StringSplit(content, ':', parts);
        
        if(ArraySize(parts) < 2) return false;
        
        key = StringTrim(parts[0]);
        value = StringTrim(parts[1]);
        return true;
    }
    
    // Helper function to trim strings
    string StringTrim(string str) {
        StringTrimLeft(str);
        StringTrimRight(str);
        return str;
    }
    
public:
    CSessionManager() {
        m_sessionFilePrefix = "EA_Memory_";
        m_lastFullProcessTime = 0;
        m_symbolIndex = 0;
        m_maxAge = 3600; // Default 1 hour
    }
    
    void Initialize(string filePrefix, int maxAge = 3600) {
        m_sessionFilePrefix = filePrefix;
        m_maxAge = maxAge;
    }
    
    bool SaveSessionMemory(const string &symbol, const CMarketAnalysis &ma_param, 
                         const CStrategyManager &sm_param) {
        string fileName = m_sessionFilePrefix + symbol + ".txt";
        string content = "";
        
        // Save current session data
        content += "LastProcessTime: " + TimeToString(m_lastFullProcessTime) + "\n";
        content += "CurrentRegime: " + IntegerToString((int)ma_param.GetCurrentRegime()) + "\n";
        
        // Save strategy performance data
        for(int i=0; i<11; i++) {
            content += "Strategy" + IntegerToString(i) + ": " + "Unknown" + "\n"; // GetStrategyName method not available
        }
        
        return SaveToFile(fileName, content);
    }
    
    // Simplified version that uses global objects
    bool SaveSessionMemory(const string &symbol) {
        // Assuming marketAnalysis and strategyManager are global objects
        // Global marketAnalysis and strategyManager pointers will be used directly.
        // (Removed incorrect extern declarations)
        
        if(marketAnalysis == NULL || strategyManager == NULL) {
            Print("[ERROR] SaveSessionMemory: Global objects not initialized");
            return false;
        }
        
        // Update last process time
        m_lastFullProcessTime = TimeCurrent();
        
        // Call the full version with the global objects
        return SaveSessionMemory(symbol, *marketAnalysis, *strategyManager);
    }
    
    // Clean up old session memory files
    void CleanupMemory() {
        if(m_maxAge <= 0) return; // No cleanup if max age is not set
        
        datetime currentTime = TimeCurrent();
        int filesRemoved = 0;
        int filesTotal = 0;
        
        string fileName;
        long handle = FileFindFirst(m_sessionFilePrefix + "*.txt", fileName);
        
        if(handle != INVALID_HANDLE) {
            do {
                filesTotal++;
                string fullPath = m_sessionFilePrefix + fileName;
                
                // Get file attributes
                datetime fileTime = 0;
                if(FileGetInteger(fullPath, FILE_MODIFY_DATE, fileTime)) {
                    // Check if file is older than max age
                    if(currentTime - fileTime > m_maxAge) {
                        if(FileDelete(fullPath)) {
                            filesRemoved++;
                            Print("[CLEANUP] Removed old session file: ", fileName);
                        }
                    }
                }
            } while(FileFindNext(handle, fileName));
            
            FileFindClose(handle);
        }
        
        if(filesRemoved > 0) {
            Print("[CLEANUP] Removed ", filesRemoved, " of ", filesTotal, " session files older than ", 
                  m_maxAge, " seconds");
        }
    }
    
    bool LoadSessionMemory(const string &symbol, CMarketAnalysis &ma_param, 
                         CStrategyManager &sm_param) {
        string fileName = m_sessionFilePrefix + symbol + ".txt";
        string content = LoadFromFile(fileName);
        
        if(content == "") return false;
        
        string lines[];
        int lineCount = StringSplit(content, '\n', lines);
        
        for(int i=0; i<lineCount; i++) {
            string key, value;
            if(!ParseSessionData(lines[i], key, value)) continue;
            
            if(key == "LastProcessTime") {
                m_lastFullProcessTime = StringToTime(value);
            }
            else if(key == "CurrentRegime") {
                ma_param.SetMarketRegime((ENUM_MARKET_REGIME)StringToInteger(value));
            }
            else if(StringFind(key, "Strategy") == 0) {
                // Process strategy data if needed
            }
        }
        
        return true;
    }
    
    void ProcessSymbols(const string &symbolList) {
        // Split symbols string only once and cache the result
        if(ArraySize(m_processedSymbols) == 0) {
            StringSplit(symbolList, ',', m_processedSymbols);
            for(int i=0; i<ArraySize(m_processedSymbols); i++) {
                m_processedSymbols[i] = StringTrim(m_processedSymbols[i]);
            }
        }
        
        // Process one symbol per tick in a round-robin fashion
        int symbolCount = ArraySize(m_processedSymbols);
        if(symbolCount > 0) {
            // Reset index if we've processed all symbols
            if(m_symbolIndex >= symbolCount) m_symbolIndex = 0;
            
            // Process the current symbol
            string sym = m_processedSymbols[m_symbolIndex];
            if(sym != "") {
                Print("[INFO] Processing symbol: ", sym, " (", m_symbolIndex+1, "/", symbolCount, ")");
                // Symbol processing will be done by the main EA
            }
            
            // Move to the next symbol for the next tick
            m_symbolIndex++;
        }
    }
    
    datetime GetLastProcessTime() const {
        return m_lastFullProcessTime;
    }
    
    void SetLastProcessTime(datetime time) {
        m_lastFullProcessTime = time;
    }
    
    int GetSymbolIndex() const {
        return m_symbolIndex;
    }
    
    void ResetSymbolIndex() {
        m_symbolIndex = 0;
    }
    
    string GetCurrentSymbol(const string &symbolList) {
        // Make sure we have processed the symbol list
        if(ArraySize(m_processedSymbols) == 0) {
            ProcessSymbols(symbolList);
        }
        
        int symbolCount = ArraySize(m_processedSymbols);
        if(symbolCount > 0 && m_symbolIndex < symbolCount) {
            return m_processedSymbols[m_symbolIndex];
        }
        
        return "";
    }
};

#endif

