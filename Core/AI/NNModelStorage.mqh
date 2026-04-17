//+------------------------------------------------------------------+
//| NNModelStorage.mqh                                               |
//| Helpers for persistent NN model checkpoint storage               |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_AI_NN_MODEL_STORAGE_MQH
#define CORE_AI_NN_MODEL_STORAGE_MQH

// Function declarations
string NNModelStorage_SanitizeToken(const string value);
string NNModelStorage_GetTimestamp();
string NNModelStorage_GetBaseName(const string symbol, const ENUM_TIMEFRAMES timeframe, const int version = 5);
string NNModelStorage_GetLegacyBaseName(const string symbol, const ENUM_TIMEFRAMES timeframe);
string NNModelStorage_GetPrimaryPath(const string symbol, const ENUM_TIMEFRAMES timeframe, const int version = 5);
string NNModelStorage_GetBackupPath(const string symbol, const ENUM_TIMEFRAMES timeframe, const int version = 5);
string NNModelStorage_GetTempPath(const string symbol, const ENUM_TIMEFRAMES timeframe, const int version = 5);
string NNModelStorage_GetLegacyPrimaryPath(const string symbol, const ENUM_TIMEFRAMES timeframe);
string NNModelStorage_GetLegacyBackupPath(const string symbol, const ENUM_TIMEFRAMES timeframe);
string NNModelStorage_GetArchivePath(const string symbol, const ENUM_TIMEFRAMES timeframe, const int oldVersion);
void NNModelStorage_EnsureFolders();
bool NNModelStorage_CopyBinaryFile(const string sourceFile, const string targetFile);
bool NNModelStorage_PromoteTempToPrimary(const string tempFile, const string primaryFile, const string backupFile);
bool NNModelStorage_ArchiveOldCheckpoint(const string sourceFile, const string archivePath);
bool NNModelStorage_LegacyCheckpointExists(const string symbol, const ENUM_TIMEFRAMES timeframe);

// Function implementations
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

string NNModelStorage_GetTimestamp()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    return StringFormat("%04d%02d%02d_%02d%02d%02d",
                        dt.year, dt.mon, dt.day,
                        dt.hour, dt.min, dt.sec);
}

string NNModelStorage_GetBaseName(const string symbol, const ENUM_TIMEFRAMES timeframe, const int version = 5)
{
    string safeSymbol = NNModelStorage_SanitizeToken(symbol);
    string safeTf = IntegerToString((int)timeframe);
    return StringFormat("EAModels\\NN\\%s_%s_v%d", safeSymbol, safeTf, version);
}

string NNModelStorage_GetLegacyBaseName(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    string safeSymbol = NNModelStorage_SanitizeToken(symbol);
    string safeTf = IntegerToString((int)timeframe);
    return StringFormat("EAModels\\NN\\%s_%s", safeSymbol, safeTf);
}

string NNModelStorage_GetPrimaryPath(const string symbol, const ENUM_TIMEFRAMES timeframe, const int version = 5)
{
    return NNModelStorage_GetBaseName(symbol, timeframe, version) + ".bin";
}

string NNModelStorage_GetBackupPath(const string symbol, const ENUM_TIMEFRAMES timeframe, const int version = 5)
{
    return NNModelStorage_GetBaseName(symbol, timeframe, version) + ".prev.bin";
}

string NNModelStorage_GetTempPath(const string symbol, const ENUM_TIMEFRAMES timeframe, const int version = 5)
{
    return NNModelStorage_GetBaseName(symbol, timeframe, version) + ".tmp";
}

string NNModelStorage_GetLegacyPrimaryPath(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    return NNModelStorage_GetLegacyBaseName(symbol, timeframe) + ".bin";
}

string NNModelStorage_GetLegacyBackupPath(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    return NNModelStorage_GetLegacyBaseName(symbol, timeframe) + ".prev.bin";
}

string NNModelStorage_GetArchivePath(const string symbol, const ENUM_TIMEFRAMES timeframe, const int oldVersion)
{
    string safeSymbol = NNModelStorage_SanitizeToken(symbol);
    string safeTf = IntegerToString((int)timeframe);
    string timestamp = NNModelStorage_GetTimestamp();
    return StringFormat("EAModels\\NN\\Archive\\%s_%s_v%d_%s.bin", safeSymbol, safeTf, oldVersion, timestamp);
}

void NNModelStorage_EnsureFolders()
{
    ResetLastError();
    FolderCreate("EAModels", FILE_COMMON);
    ResetLastError();
    FolderCreate("EAModels\\NN", FILE_COMMON);
    ResetLastError();
    FolderCreate("EAModels\\NN\\Archive", FILE_COMMON);
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

bool NNModelStorage_ArchiveOldCheckpoint(const string sourceFile, const string archivePath)
{
    if(!FileIsExist(sourceFile, FILE_COMMON))
        return false;

    return NNModelStorage_CopyBinaryFile(sourceFile, archivePath);
}

bool NNModelStorage_LegacyCheckpointExists(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    string legacyPrimary = NNModelStorage_GetLegacyPrimaryPath(symbol, timeframe);
    string legacyBackup = NNModelStorage_GetLegacyBackupPath(symbol, timeframe);
    return (FileIsExist(legacyPrimary, FILE_COMMON) || FileIsExist(legacyBackup, FILE_COMMON));
}

#endif // CORE_AI_NN_MODEL_STORAGE_MQH
