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

// Write crash recovery state as JSON with atomic write and checksum.
// Batch 168: the state now carries the halt flags and the broker trading-day key.
// Previously only equity anchors were saved, so a restart cleared the daily-loss
// halt and let the EA trade a second full daily budget after it had already spent
// one; and nothing was written except on graceful deinit, so a real crash left
// nothing to recover.
bool WriteCrashRecoveryState(const string &fileName,
                              double equityBaseline, double peakEquity,
                              int ddBreachCount, double ddMax,
                              int haltFlags, int tradingDayKey)
{
    string tempFile = fileName + ".tmp";
        int fh = FileOpen(tempFile, FILE_WRITE | FILE_TXT | FILE_ANSI);
    if(fh == INVALID_HANDLE)
        return false;

    // Build JSON
    string json = "{";
    json += "\"version\":2,";
    json += "\"equity_baseline\":" + DoubleToString(equityBaseline, 2) + ",";
    json += "\"peak_equity\":" + DoubleToString(peakEquity, 2) + ",";
    json += "\"dd_breach_count\":" + IntegerToString(ddBreachCount) + ",";
    json += "\"dd_max\":" + DoubleToString(ddMax, 2) + ",";
    json += "\"halt_flags\":" + IntegerToString(haltFlags) + ",";
    json += "\"trading_day_key\":" + IntegerToString(tradingDayKey) + ",";
    json += "\"timestamp\":\"" + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "\"";
    json += "}";

    // Compute checksum over the data object EXCLUDING the leading '{'
    // so it matches exactly what ReadCrashRecoveryState recomputes
    // (it skips "checksum":N, and the following ',' and hashes the rest).
    // Old code hashed the full {"version":...} string, which never matched
    // the inner "version":... at read time, so every saved state was rejected.
    string dataObject = StringSubstr(json, 1); // drop leading '{' -> "version":1,...}
    ulong checksum = ComputeStateChecksum(dataObject);
    json = "{\"checksum\":" + IntegerToString((long)checksum) + "," + dataObject;

    // Write and close - with error checking for partial writes
    int bytesWritten = (int)FileWriteString(fh, json);
    if(bytesWritten < 0 || bytesWritten != StringLen(json))
    {
        PrintFormat("[RECOVERY] ERROR: FileWriteString failed or partial write for %s | bytesWritten=%d expected=%d", tempFile, bytesWritten, StringLen(json));
        FileClose(fh);
        FileDelete(tempFile, 0);
        return false;
    }
    FileClose(fh);

    // MQL5 FileMove() does NOT overwrite an existing destination, so remove the
    // stale state file first. flags=0 -> same local MQL5/Files dir used by the
    // FileOpen() calls above and in ReadCrashRecoveryState(). A false return
    // (file absent, e.g. first run) is harmless and intentionally ignored.
    FileDelete(fileName, 0);

    // Atomic move
        if(!FileMove(tempFile, 0, fileName, 0))
        {
            PrintFormat("[RECOVERY] ERROR: FileMove failed for %s -> %s (err=%d)", tempFile, fileName, GetLastError());
            // flags=0 -> local MQL5/Files dir, matching the FileOpen(tempFile, ...)
            // above. Default (FILE_COMMON) would target the shared dir and leak
            // the local .tmp on move failure.
            FileDelete(tempFile, 0);
            return false;
        }
    return true;
}

bool ExtractDoubleFromJson(const string &json, const string &key, double &out)
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
}

bool ExtractIntFromJson(const string &json, const string &key, int &out)
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
}

bool ExtractStringFromJson(const string &json, const string &key, string &out)
{
    string search = "\"" + key + "\":\"";
    int pos = StringFind(json, search);
    if(pos < 0) return false;
    int start = pos + StringLen(search);
    int end = StringFind(json, "\"", start);
    if(end < 0) return false;
    out = StringSubstr(json, start, end - start);
    return true;
}

// Read and validate crash recovery state JSON
bool ReadCrashRecoveryState(const string &fileName,
                             double &equityBaseline, double &peakEquity,
                             int &ddBreachCount, double &ddMax, string &timestamp,
                             int &haltFlags, int &tradingDayKey)
{
    int fh = FileOpen(fileName, FILE_READ | FILE_TXT | FILE_ANSI);
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
    if(!ExtractDoubleFromJson(json, "equity_baseline", equityBaseline)) return false;
    if(!ExtractDoubleFromJson(json, "peak_equity", peakEquity)) return false;
    if(!ExtractIntFromJson(json, "dd_breach_count", ddBreachCount)) return false;
    if(!ExtractDoubleFromJson(json, "dd_max", ddMax)) return false;
    if(!ExtractStringFromJson(json, "timestamp", timestamp)) return false;

    // Batch 168 fields. version:1 files (written before this change) legitimately
    // lack them, so they default rather than reject - otherwise the first upgrade
    // restart would silently discard a live drawdown halt.
    haltFlags = 0;
    tradingDayKey = 0;
    ExtractIntFromJson(json, "halt_flags", haltFlags);
    ExtractIntFromJson(json, "trading_day_key", tradingDayKey);

    // Validate bounds
    if(equityBaseline < 0 || peakEquity < 0 || ddBreachCount < 0 || ddMax < 0)
        return false;
    if(equityBaseline > 1e9 || peakEquity > 1e9) return false; // sanity bounds
    if(haltFlags < 0 || haltFlags > 3) return false;

    return true;
}