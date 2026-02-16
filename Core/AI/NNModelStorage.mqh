//+------------------------------------------------------------------+
//| NNModelStorage.mqh                                               |
//| Helpers for persistent NN model checkpoint storage               |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_AI_NN_MODEL_STORAGE_MQH
#define CORE_AI_NN_MODEL_STORAGE_MQH

string NNModelStorage_SanitizeToken(const string value)
{
    string token = value;
    StringReplace(token, ".", "_");
    StringReplace(token, " ", "_");
    StringReplace(token, "/", "_");
    StringReplace(token, "\\", "_");
    StringReplace(token, "-", "_");
    StringReplace(token, ":", "_");
    StringReplace(token, "*", "_");
    StringReplace(token, "?", "_");
    StringReplace(token, "\"", "_");
    StringReplace(token, "<", "_");
    StringReplace(token, ">", "_");
    StringReplace(token, "|", "_");
    return token;
}

string NNModelStorage_GetBaseName(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    string safeSymbol = NNModelStorage_SanitizeToken(symbol);
    string safeTf = IntegerToString((int)timeframe);
    return StringFormat("EAModels\\NN\\%s_%s", safeSymbol, safeTf);
}

string NNModelStorage_GetPrimaryPath(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    return NNModelStorage_GetBaseName(symbol, timeframe) + ".bin";
}

string NNModelStorage_GetBackupPath(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    return NNModelStorage_GetBaseName(symbol, timeframe) + ".prev.bin";
}

string NNModelStorage_GetTempPath(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    return NNModelStorage_GetBaseName(symbol, timeframe) + ".tmp";
}

void NNModelStorage_EnsureFolders()
{
    ResetLastError();
    FolderCreate("EAModels", FILE_COMMON);
    ResetLastError();
    FolderCreate("EAModels\\NN", FILE_COMMON);
}

bool NNModelStorage_CopyBinaryFile(const string sourceFile, const string targetFile)
{
    int srcHandle = FileOpen(sourceFile, FILE_READ | FILE_BIN | FILE_COMMON);
    if(srcHandle == INVALID_HANDLE)
        return false;

    int dstHandle = FileOpen(targetFile, FILE_WRITE | FILE_BIN | FILE_COMMON);
    if(dstHandle == INVALID_HANDLE)
    {
        FileClose(srcHandle);
        return false;
    }

    uchar buffer[];
    ArrayResize(buffer, 4096);

    while(!FileIsEnding(srcHandle))
    {
        uint bytesRead = FileReadArray(srcHandle, buffer, 0, 4096);
        if(bytesRead <= 0)
            break;

        FileWriteArray(dstHandle, buffer, 0, (int)bytesRead);
    }

    FileClose(dstHandle);
    FileClose(srcHandle);
    return true;
}

bool NNModelStorage_PromoteTempToPrimary(const string tempFile,
                                         const string primaryFile,
                                         const string backupFile)
{
    if(!FileIsExist(tempFile, FILE_COMMON))
        return false;

    if(FileIsExist(primaryFile, FILE_COMMON))
    {
        if(!NNModelStorage_CopyBinaryFile(primaryFile, backupFile))
            return false;
    }

    if(!NNModelStorage_CopyBinaryFile(tempFile, primaryFile))
        return false;

    FileDelete(tempFile, FILE_COMMON);
    return true;
}

#endif // CORE_AI_NN_MODEL_STORAGE_MQH
