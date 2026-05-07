//+------------------------------------------------------------------+
//| TrainingDataExporter.mq5                                          |
//| One-shot MT5 OHLCV exporter for ONNX training                     |
//+------------------------------------------------------------------+
#property strict
#property version "1.00"

#include "Core\AI\AIFeatureVectorBuilder.mqh"

input string          InpExportSymbols   = "EURUSD.0,GBPUSD.0,USDJPY.0,XAUUSD.0,BTCUSD.0,AUDUSD.0";
input ENUM_TIMEFRAMES InpExportTimeframe = PERIOD_H1;
input datetime        InpFromDate        = D'2024.01.01 00:00:00';
input datetime        InpToDate          = D'2026.04.20 00:00:00';
input string          InpOutputFile      = "AITraining_OHLCV_H1.csv";
input bool            InpExportFeatureVectors = false;

string TrimString(string value)
{
    StringTrimLeft(value);
    StringTrimRight(value);
    return value;
}

bool ExportSymbolHistory(const int fileHandle,
                         const string symbol,
                         const ENUM_TIMEFRAMES timeframe,
                         const datetime fromDate,
                         const datetime toDate,
                         int &rowsWritten)
{
    if(symbol == "")
        return false;

    SymbolSelect(symbol, true);

    MqlRates rates[];
    ArraySetAsSeries(rates, false);
    ResetLastError();
    int copied = CopyRates(symbol, timeframe, fromDate, toDate, rates);
    if(copied <= 0)
    {
        PrintFormat("[TRAIN-EXPORT] No rates exported for %s %s | err=%d",
                    symbol, EnumToString(timeframe), GetLastError());
        return false;
    }

    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    for(int i = 0; i < copied; i++)
    {
        string row = StringFormat("%s,%s,%s,%s,%s,%s,%I64d",
                                  symbol,
                                  TimeToString(rates[i].time, TIME_DATE | TIME_SECONDS),
                                  DoubleToString(rates[i].open, digits),
                                  DoubleToString(rates[i].high, digits),
                                  DoubleToString(rates[i].low, digits),
                                  DoubleToString(rates[i].close, digits),
                                  (long)rates[i].tick_volume);

        if(InpExportFeatureVectors)
        {
            int shift = iBarShift(symbol, timeframe, rates[i].time, false);
            double features[];
            if(shift < 1 || !CAIFeatureVectorBuilder::BuildNNFeatureVector(symbol, timeframe, features, shift))
                continue;

            for(int f = 0; f < ArraySize(features); f++)
                row += StringFormat(",%.10f", features[f]);
        }

        FileWriteString(fileHandle, row + "\r\n");
        rowsWritten++;
    }

    PrintFormat("[TRAIN-EXPORT] %s %s | rows=%d",
                symbol, EnumToString(timeframe), copied);
    return true;
}

int OnInit()
{
    datetime toDate = (InpToDate > 0) ? InpToDate : TimeCurrent();
    if(toDate <= InpFromDate)
    {
        Print("[TRAIN-EXPORT] Invalid date window");
        ExpertRemove();
        return INIT_FAILED;
    }

    int fileHandle = FileOpen(InpOutputFile, FILE_COMMON | FILE_WRITE | FILE_CSV | FILE_ANSI);
    if(fileHandle == INVALID_HANDLE)
    {
        PrintFormat("[TRAIN-EXPORT] Failed to open output file %s | err=%d", InpOutputFile, GetLastError());
        ExpertRemove();
        return INIT_FAILED;
    }

    string header = "symbol,date,open,high,low,close,volume";
    if(InpExportFeatureVectors)
    {
        for(int i = 0; i < FEATURE_VECTOR_SIZE; i++)
            header += StringFormat(",feature_%02d", i);
    }
    FileWriteString(fileHandle, header + "\r\n");

    string rawSymbols[];
    int symbolCount = StringSplit(InpExportSymbols, ',', rawSymbols);
    int rowsWritten = 0;

    for(int i = 0; i < symbolCount; i++)
    {
        string symbol = TrimString(rawSymbols[i]);
        if(symbol == "")
            continue;
        ExportSymbolHistory(fileHandle, symbol, InpExportTimeframe, InpFromDate, toDate, rowsWritten);
    }

    FileClose(fileHandle);
    CIndicatorManager::DestroyInstance();

    PrintFormat("[TRAIN-EXPORT] Completed | symbols=%d | rows=%d | file=%s",
                symbolCount, rowsWritten, InpOutputFile);
    PrintFormat("[TRAIN-EXPORT] Common files root: %s",
                TerminalInfoString(TERMINAL_COMMONDATA_PATH));

    ExpertRemove();
    return INIT_SUCCEEDED;
}

void OnTick()
{
}
