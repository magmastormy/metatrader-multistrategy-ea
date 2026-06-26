//+------------------------------------------------------------------+
//| CSVDataLoader.mqh                                                |
//| Loads and parses CSV training data exported by TrainingDataExporter.mq5 |
//+------------------------------------------------------------------+
#ifndef __MQH_CSV_DATA_LOADER_MQH__
#define __MQH_CSV_DATA_LOADER_MQH__

#include <Arrays\ArrayString.mqh>
#include <Arrays\ArrayDouble.mqh>
#include "../Core/AI/AIFeatureVectorBuilder.mqh"

class CCSVDataLoader
{
private:
    string m_filename;
    int m_totalRows;
    int m_featureCount;
    int m_labelCount;
    bool m_hasHeader;
    
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    
    bool ParseCSVLine(const string line, double &features[], int &label, double &metaInput[], datetime &timestamp)
    {
        string fields[];
        int fieldCount = StringSplit(line, ',', fields);
        if(fieldCount < 9) return false;
        
        int fieldIdx = 0;
        m_symbol = fields[fieldIdx++];
        
        string timeStr = fields[fieldIdx++];
        timestamp = StringToTime(timeStr);
        
        fieldIdx += 6;
        
        for(int i = 0; i < FEATURE_VECTOR_SIZE && fieldIdx < fieldCount; i++, fieldIdx++)
        {
            string val = fields[fieldIdx];
            StringTrimLeft(val);
            StringTrimRight(val);
            features[i] = val == "" ? 0.0 : StringToDouble(val);
        }
        
        fieldIdx += 28;
        fieldIdx += 10;
        
        for(int i = 0; i < AI_MLP_INPUT && fieldIdx < fieldCount; i++, fieldIdx++)
        {
            string val = fields[fieldIdx];
            StringTrimLeft(val);
            StringTrimRight(val);
            metaInput[i] = val == "" ? 0.0 : StringToDouble(val);
        }
        
        if(fieldIdx < fieldCount)
        {
            string labelVal = fields[fieldIdx];
            StringTrimLeft(labelVal);
            StringTrimRight(labelVal);
            label = (int)StringToInteger(labelVal);
        }
        else
        {
            label = 0;
        }
        
        return true;
    }
    
public:
    CCSVDataLoader() : m_totalRows(0), m_featureCount(FEATURE_VECTOR_SIZE), m_labelCount(3), m_hasHeader(true) {}
    
    bool LoadFile(const string filename)
    {
        m_filename = filename;
        
        int fh = FileOpen(filename, FILE_READ | FILE_CSV | FILE_COMMON);
        if(fh == INVALID_HANDLE)
        {
            PrintFormat("[MQH-TRAIN] Failed to open CSV file: %s | err=%d", filename, GetLastError());
            return false;
        }
        
        m_totalRows = 0;
        string line;
        
        if(m_hasHeader)
        {
            if(!FileReadString(fh, line))
            {
                FileClose(fh);
                return false;
            }
        }
        
        while(FileReadString(fh, line))
        {
            m_totalRows++;
        }
        
        FileClose(fh);
        PrintFormat("[MQH-TRAIN] CSV file loaded: %s | rows=%d", filename, m_totalRows);
        return true;
    }
    
    bool GetRowAt(const int index, double &features[], int &label, double &metaInput[], datetime &timestamp)
    {
        int fh = FileOpen(m_filename, FILE_READ | FILE_CSV | FILE_COMMON);
        if(fh == INVALID_HANDLE)
            return false;
        
        string line;
        int currentRow = 0;
        
        if(m_hasHeader)
            FileReadString(fh, line);
        
        while(FileReadString(fh, line))
        {
            if(currentRow == index)
            {
                bool result = ParseCSVLine(line, features, label, metaInput, timestamp);
                FileClose(fh);
                return result;
            }
            currentRow++;
        }
        
        FileClose(fh);
        return false;
    }
    
    int GetTotalRows() const { return m_totalRows; }
    int GetFeatureCount() const { return m_featureCount; }
    int GetLabelCount() const { return m_labelCount; }
    string GetSymbol() const { return m_symbol; }
    ENUM_TIMEFRAMES GetTimeframe() const { return m_timeframe; }
    
    bool LoadAllRows(double &allFeatures[][], int &labels[], int &rowCount)
    {
        if(m_totalRows == 0)
            return false;
        
        ArrayResize(allFeatures, m_totalRows, FEATURE_VECTOR_SIZE);
        ArrayResize(labels, m_totalRows);
        
        int fh = FileOpen(m_filename, FILE_READ | FILE_CSV | FILE_COMMON);
        if(fh == INVALID_HANDLE)
            return false;
        
        string line;
        if(m_hasHeader)
            FileReadString(fh, line);
        
        rowCount = 0;
        while(FileReadString(fh, line) && rowCount < m_totalRows)
        {
            double features[];
            ArrayResize(features, FEATURE_VECTOR_SIZE);
            int label = 0;
            double metaInput[];
            ArrayResize(metaInput, AI_MLP_INPUT);
            datetime timestamp;
            
            if(ParseCSVLine(line, features, label, metaInput, timestamp))
            {
                for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
                    allFeatures[rowCount][i] = features[i];
                labels[rowCount] = label;
                rowCount++;
            }
        }
        
        FileClose(fh);
        return rowCount > 0;
    }
};

#endif // __MQH_CSV_DATA_LOADER_MQH__
