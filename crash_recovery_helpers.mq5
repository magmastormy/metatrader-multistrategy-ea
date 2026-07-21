//+------------------------------------------------------------------+
//| Crash Recovery State File Helpers (L2-003)                       |
//| JSON with version, checksum, and atomic write                    |
//+------------------------------------------------------------------+
// Simple xorshift checksum (64-bit)
ulong ComputeStateChecksum(const string &jsonData)
{
    ulong hash = 0x123456789ABCDEF0;
    for(int i = 0; i < StringLen(jsonData); i++)
    {
        hash ^= (ulong)StringGetCharacter(jsonData, i);
        hash = hash * 6364136223846793005ULL + 1442695040888963407ULL;
    }
    return hash;
}

// Write crash recovery state as JSON with atomic write and checksum
bool WriteCrashRecoveryState(const string &fileName, 
                              double equityBaseline, double peakEquity,
                              int ddBreachCount, double ddMax)
{
    string tempFile = fileName + ".tmp";
    int fh = FileOpen(tempFile, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
    if(fh == INVALID_HANDLE)
        return false;

    // Build JSON
    string json = "{";
    json += "\"version\":1,";
    json += "\"equity_baseline\":" + DoubleToString(equityBaseline, 2) + ",";
    json += "\"peak_equity\":" + DoubleToString(peakEquity, 2) + ",";
    json += "\"dd_breach_count\":" + IntegerToString(ddBreachCount) + ",";
    json += "\"dd_max\":" + DoubleToString(ddMax, 2) + ",";
    json += "\"timestamp\":\"" + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "\"";
    json += "}";

    // Compute checksum
    ulong checksum = ComputeStateChecksum(json);
    json = "{\"checksum\":" + LongToString((long)checksum) + "," + StringSubstr(json, 1);

    // Write and close
    FileWriteString(fh, json);
    FileClose(fh);

    // Atomic move
    if(!FileMove(tempFile, fileName, FILE_COMMON))
    {
        FileDelete(tempFile, FILE_COMMON);
        return false;
    }
    return true;
}

// Read and validate crash recovery state JSON
bool ReadCrashRecoveryState(const string &fileName,
                             double &equityBaseline, double &peakEquity,
                             int &ddBreachCount, double &ddMax, string &timestamp)
{
    int fh = FileOpen(fileName, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
    if(fh == INVALID_HANDLE)
        return false;

    // Read entire file
    string json = "";
    while(!FileIsEnding(fh))
    {
        json += FileReadString(fh);
    }
    FileClose(fh);

    if(json == "")
        return false;

    // Extract checksum
    int checksumPos = StringFind(json, "\"checksum\":");
    if(checksumPos < 0)
    {
        Print("[RECOVERY-STATE] No checksum in state file - rejecting");
        return false;
    }
    int valStart = checksumPos + 11; // skip "checksum":
    int valEnd = StringFind(json, ",", valStart);
    if(valStart < 0 || valEnd < 0)
        return false;
    ulong storedChecksum = (ulong)StringToInteger(StringSubstr(json, valStart, valEnd - valStart));

    // Compute checksum of data (excluding checksum field)
    int dataStart = valEnd + 1; // skip comma after checksum value
    if(dataStart >= StringLen(json))
        return false;
    string dataJson = StringSubstr(json, dataStart);
    ulong computedChecksum = ComputeStateChecksum(dataJson);

    if(storedChecksum != computedChecksum)
    {
        PrintFormat("[RECOVERY-STATE] Checksum mismatch - stored=0x%016llX computed=0x%016llX - rejecting", storedChecksum, computedChecksum);
        return false;
    }

    // Parse fields (simple string parsing for JSON-like structure)
    auto ExtractDouble = [&](const string &key, double &out) -> bool
    {
        string search = "\"" + key + "\":";
        int pos = StringFind(json, search);
        if(pos < 0) return false;
        int start = pos + StringLen(search);
        int end = StringFind(json, ",", start);
        if(end < 0) end = StringFind(json, "}", start);
        if(end < 0) return false;
        out = StringToDouble(StringSubstr(json, start, end - start));
        return true;
    };

    auto ExtractInt = [&](const string &key, int &out) -> bool
    {
        string search = "\"" + key + "\":";
        int pos = StringFind(json, search);
        if(pos < 0) return false;
        int start = pos + StringLen(search);
        int end = StringFind(json, ",", start);
        if(end < 0) end = StringFind(json, "}", start);
        if(end < 0) return false;
        out = (int)StringToInteger(StringSubstr(json, start, end - start));
        return true;
    };

    auto ExtractString = [&](const string &key, string &out) -> bool
    {
        string search = "\"" + key + "\":\"";
        int pos = StringFind(json, search);
        if(pos < 0) return false;
        int start = pos + StringLen(search);
        int end = StringFind(json, "\"", start);
        if(end < 0) return false;
        out = StringSubstr(json, start, end - start);
        return true;
    };

    if(!ExtractDouble("equity_baseline", equityBaseline)) return false;
    if(!ExtractDouble("peak_equity", peakEquity)) return false;
    if(!ExtractInt("dd_breach_count", ddBreachCount)) return false;
    if(!ExtractDouble("dd_max", ddMax)) return false;
    if(!ExtractString("timestamp", timestamp)) return false;

    // Validate bounds
    if(equityBaseline < 0 || peakEquity < 0 || ddBreachCount < 0 || ddMax < 0)
        return false;
    if(equityBaseline > 1e9 || peakEquity > 1e9) return false; // sanity bounds

    return true;
}