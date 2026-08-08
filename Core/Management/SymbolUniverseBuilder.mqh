//+------------------------------------------------------------------+
//| SymbolUniverseBuilder.mqh                                        |
//| Validates and builds the active trading symbol universe          |
//+------------------------------------------------------------------+
#ifndef SYMBOL_UNIVERSE_BUILDER_MQH
#define SYMBOL_UNIVERSE_BUILDER_MQH

#include "../Utils/Instruments.mqh"

struct SSymbolValidationConfig
{
    long maxSpreadPoints;          // Maximum allowed spread in points
    long minDailyVolumeLots;       // Minimum daily volume in lots
    bool enableVolumeCheck;        // Enable/disable volume liquidity check
};

class CSymbolUniverseBuilder
{
private:
    static bool HasSimilarSymbol(const string &activePairs[], const string symbol)
    {
        string symUpper = symbol;
        StringToUpper(symUpper);
        
        for(int i = 0; i < ArraySize(activePairs); i++)
        {
            string existingUpper = activePairs[i];
            StringToUpper(existingUpper);
            
            // Exact match already handled by ContainsSymbol
            if(symUpper == existingUpper)
                continue;
            
            // For Deriv synthetic indices: compare the index number/name
            if(StringFind(symUpper, "VOLATILITY") >= 0 && StringFind(existingUpper, "VOLATILITY") >= 0)
            {
                // Extract index number: "Volatility 25 Index" -> 25
                int symNum = ExtractVolatilityIndex(symUpper);
                int existingNum = ExtractVolatilityIndex(existingUpper);
                if(symNum > 0 && symNum == existingNum)
                    return true;
            }
            else if((StringFind(symUpper, "BOOM") >= 0 || StringFind(symUpper, "CRASH") >= 0) &&
                    (StringFind(existingUpper, "BOOM") >= 0 || StringFind(existingUpper, "CRASH") >= 0))
            {
                // Boom/Crash: compare the number (1000, 500, etc.)
                int symNum = ExtractBoomCrashIndex(symUpper);
                int existingNum = ExtractBoomCrashIndex(existingUpper);
                if(symNum > 0 && symNum == existingNum)
                    return true;
            }
            else if(StringFind(symUpper, "JUMP") >= 0 && StringFind(existingUpper, "JUMP") >= 0)
            {
                // Jump: compare the number (25, 75, etc.)
                int symNum = ExtractJumpIndex(symUpper);
                int existingNum = ExtractJumpIndex(existingUpper);
                if(symNum > 0 && symNum == existingNum)
                    return true;
            }
            else if(StringFind(symUpper, "STEP INDEX") >= 0 && StringFind(existingUpper, "STEP INDEX") >= 0)
            {
                // Step Index variants - they are different indices
                return true;
            }
            // For Forex: compare base/quote currencies (first 3 and last 3 chars for 6-char pairs)
            else if(StringLen(symUpper) >= 6 && StringLen(existingUpper) >= 6)
            {
                string symBase = StringSubstr(symUpper, 0, 3);
                string symQuote = StringSubstr(symUpper, StringLen(symUpper) - 3, 3);
                string existingBase = StringSubstr(existingUpper, 0, 3);
                string existingQuote = StringSubstr(existingUpper, StringLen(existingUpper) - 3, 3);
                
                // Same base and quote = same pair (e.g., EURUSD vs EURUSDm)
                if(symBase == existingBase && symQuote == existingQuote)
                    return true;
                
                // Same base, different quote = cross pair (not similar for our purposes)
                // Same quote, different base = major/cross (not similar)
            }
            
            return false;
        }
        return false;
    }
    
    // Helper to extract volatility index number
    static int ExtractVolatilityIndex(const string sym)
    {
        int pos = StringFind(sym, "VOLATILITY");
        if(pos < 0) return 0;
        int numStart = pos + StringLen("VOLATILITY");
        string rest = StringSubstr(sym, numStart);
        StringTrimLeft(rest);
        int endPos = StringFind(rest, " ");
        if(endPos < 0) endPos = StringLen(rest);
        string numStr = StringSubstr(rest, 0, endPos);
        return (int)StringToInteger(numStr);
    }
    
    // Helper to extract Boom/Crash index
    static int ExtractBoomCrashIndex(const string sym)
    {
        int pos = StringFind(sym, "BOOM");
        if(pos < 0) pos = StringFind(sym, "CRASH");
        if(pos < 0) return 0;
        int numStart = pos + 4; // BOOM or CRASH = 4 chars
        string rest = StringSubstr(sym, numStart);
        StringTrimLeft(rest);
        int endPos = StringFind(rest, " ");
        if(endPos < 0) endPos = StringLen(rest);
        string numStr = StringSubstr(rest, 0, endPos);
        return (int)StringToInteger(numStr);
    }
    
    // Helper to extract Jump index
    static int ExtractJumpIndex(const string sym)
    {
        int pos = StringFind(sym, "JUMP");
        if(pos < 0) return 0;
        int numStart = pos + 4; // JUMP = 4 chars
        string rest = StringSubstr(sym, numStart);
        StringTrimLeft(rest);
        int endPos = StringFind(rest, " ");
        if(endPos < 0) endPos = StringLen(rest);
        string numStr = StringSubstr(rest, 0, endPos);
        return (int)StringToInteger(numStr);
    }

public:
    static bool ContainsSymbol(const string &activePairs[], const string symbol)
    {
        for(int i = 0; i < ArraySize(activePairs); i++)
        {
            if(activePairs[i] == symbol)
                return true;
        }
        return false;
    }

    static bool Build(const string rawSymbols, string &activePairs[], const SSymbolValidationConfig &config, const string chartSymbol = "")
    {
        ArrayResize(activePairs, 0);

        if(StringLen(rawSymbols) == 0)
        {
            Print("[ERROR] InpSymbolsToTrade is empty - no symbols to trade");
            return false;
        }

        string symbols[];
        int splitCount = StringSplit(rawSymbols, ',', symbols);
        if(splitCount == 0)
        {
            Print("[ERROR] Failed to parse InpSymbolsToTrade - malformed symbol string");
            return false;
        }

        Print("[SYMBOLS] Processing ", ArraySize(symbols), " trading symbols");
        PrintFormat("[SYMBOLS] Validation config: maxSpread=%d points, minVolume=%d lots, volumeCheck=%s",
                    config.maxSpreadPoints, config.minDailyVolumeLots, config.enableVolumeCheck ? "ENABLED" : "DISABLED");

        // ISS-701: Track rejected symbols for detailed reporting
        string rejectedSymbols[];
        ArrayResize(rejectedSymbols, 0);
        int rejectedCount = 0;

        for(int i = 0; i < ArraySize(symbols); i++)
        {
            string sym = symbols[i];
            StringTrimLeft(sym);
            StringTrimRight(sym);

            if(StringLen(sym) == 0)
            {
                Print("[SYMBOLS] Empty symbol token skipped at input index ", i, " - Please check InpSymbolsToTrade parameter for empty entries");
                rejectedCount++;
                ArrayResize(rejectedSymbols, rejectedCount);
                rejectedSymbols[rejectedCount - 1] = sym;
                continue;
            }

            string symUpper = sym;
            StringToUpper(symUpper);

            bool isSynthetic = (StringFind(symUpper, "VOL") >= 0  || StringFind(symUpper, "STEP") >= 0 ||
                                StringFind(symUpper, "BOOM") >= 0 || StringFind(symUpper, "CRASH") >= 0 ||
                                StringFind(symUpper, "JUMP") >= 0 || StringFind(symUpper, "PAINX") >= 0 ||
                                StringFind(symUpper, "PAIN ") >= 0 || StringFind(symUpper, "GAINX") >= 0 ||
                                StringFind(symUpper, "FLIPX") >= 0 || StringFind(symUpper, "FX VOL") >= 0 ||
                                StringFind(symUpper, "SWITCHX") >= 0);

            if(StringFind(sym, " ") >= 0 && StringFind(sym, ".") < 0 && !isSynthetic)
            {
                Print("[WARNING] Symbol '", sym, "' contains spaces without period - likely malformed, skipping");
                continue;
            }

            if(!SymbolSelect(sym, true))
            {
                Print("[WARNING] Symbol ", sym, " not available - skipping");
                rejectedCount++;
                ArrayResize(rejectedSymbols, rejectedCount);
                rejectedSymbols[rejectedCount - 1] = sym;
                continue;
            }

            long symbolTradeMode = SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
            if(symbolTradeMode == SYMBOL_TRADE_MODE_DISABLED)
            {
                Print("[WARNING] Symbol ", sym, " trading is disabled - skipping");
                rejectedCount++;
                ArrayResize(rejectedSymbols, rejectedCount);
                rejectedSymbols[rejectedCount - 1] = sym;
                continue;
            }
            if(symbolTradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
            {
                Print("[WARNING] Symbol ", sym, " is close-only - cannot open new positions, only close existing - skipping");
                rejectedCount++;
                ArrayResize(rejectedSymbols, rejectedCount);
                rejectedSymbols[rejectedCount - 1] = sym;
                continue;
            }
            if(SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP) <= 0.0)
            {
                Print("[WARNING] Symbol ", sym, " has invalid volume step - skipping");
                rejectedCount++;
                ArrayResize(rejectedSymbols, rejectedCount);
                rejectedSymbols[rejectedCount - 1] = sym;
                continue;
            }

            if(ContainsSymbol(activePairs, sym))
            {
                Print("[SYMBOLS] Duplicate symbol skipped: ", sym);
                rejectedCount++;
                ArrayResize(rejectedSymbols, rejectedCount);
                rejectedSymbols[rejectedCount - 1] = sym;
                continue;
            }

            if(HasSimilarSymbol(activePairs, sym))
            {
                Print("[WARNING] Symbol ", sym, " has similar symbol already in list - consider reviewing");
            }

            long spread = SymbolInfoInteger(sym, SYMBOL_SPREAD);
            
            // Allow higher spread threshold for synthetic symbols (Deriv indices trade 24/7 with wider spreads)
            long effectiveMaxSpread = config.maxSpreadPoints;
            if(isSynthetic)
            {
                effectiveMaxSpread = config.maxSpreadPoints * 10;  // 10x multiplier for synthetics (e.g., 1500 -> 15000)
            }
            
            if(spread > effectiveMaxSpread)
            {
                PrintFormat("[SYMBOLS] Symbol %s rejected - spread %d points exceeds maximum threshold (%d points) %s", 
                            sym, spread, effectiveMaxSpread, isSynthetic ? "(synthetic)" : "");
                rejectedCount++;
                ArrayResize(rejectedSymbols, rejectedCount);
                rejectedSymbols[rejectedCount - 1] = sym;
                continue;
            }

            if(config.enableVolumeCheck)
            {
                // Tick-volume liquidity filter (Issue #31): Use CopyTickVolume to verify minimum liquidity
                long tickVol[];
                ArraySetAsSeries(tickVol, true);
                int copied = CopyTickVolume(sym, PERIOD_D1, 0, 20, tickVol);
                if(copied >= 10)
                {
                    long avgTickVol = 0;
                    int count = MathMin(copied, 20);
                    for(int v = 0; v < count; v++)
                        avgTickVol += tickVol[v];
                    avgTickVol /= count;
                    
                    if(avgTickVol < config.minDailyVolumeLots)
                    {
                        PrintFormat("[SYMBOLS] Symbol %s rejected - avg tick volume %lld below minimum %lld", 
                                    sym, avgTickVol, config.minDailyVolumeLots);
                        rejectedCount++;
                        ArrayResize(rejectedSymbols, rejectedCount);
                        rejectedSymbols[rejectedCount - 1] = sym;
                        continue;
                    }
                    PrintFormat("[SYMBOLS] Symbol %s - avg tick volume %lld OK (min %lld)", 
                                sym, avgTickVol, config.minDailyVolumeLots);
                }
                else
                {
                    PrintFormat("[SYMBOLS] Symbol %s - tick volume data unavailable, skipping volume check", sym);
                }
            }

            int size = ArraySize(activePairs);
            ArrayResize(activePairs, size + 1);
            activePairs[size] = sym;

            Print("[SYMBOL] ", sym, " - Configured for trading");
            Print("  - Spread: ", spread, " points");
            Print("  - Min Lot: ", SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN));
            Print("  - Max Lot: ", SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX));
            Print("  - Lot Step: ", SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP));
            Print("  - Contract Size: ", SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE));
            if(config.enableVolumeCheck)
                Print("  - Volume Check: Skipped (not available in MQL5)");
        }

        // ISS-701: Final summary of accepted/rejected symbols
        PrintFormat("[SYMBOL-VALIDATION] Accepted: %d | Rejected: %d", ArraySize(activePairs), splitCount - ArraySize(activePairs));
        if(ArraySize(activePairs) > 0)
        {
            string accepted = "";
            for(int a = 0; a < ArraySize(activePairs); a++)
            {
                if(a > 0) accepted += ", ";
                accepted += activePairs[a];
            }
            PrintFormat("[SYMBOL-VALIDATION] Accepted symbols: %s", accepted);
        }

        // L7-021: Auto-add chart symbol if provided and not already in universe
        if(chartSymbol != "" && !ContainsSymbol(activePairs, chartSymbol))
        {
            if(SymbolSelect(chartSymbol, true))
            {
                long symbolTradeMode = SymbolInfoInteger(chartSymbol, SYMBOL_TRADE_MODE);
                if(symbolTradeMode != SYMBOL_TRADE_MODE_DISABLED && symbolTradeMode != SYMBOL_TRADE_MODE_CLOSEONLY)
                {
                    int size = ArraySize(activePairs);
                    ArrayResize(activePairs, size + 1);
                    activePairs[size] = chartSymbol;
                    PrintFormat("[SYMBOL-UNIVERSE] Auto-added chart symbol: %s", chartSymbol);
                }
                else
                {
                    PrintFormat("[SYMBOL-UNIVERSE] Chart symbol %s not tradeable (mode=%d), not adding", chartSymbol, symbolTradeMode);
                }
            }
            else
            {
                PrintFormat("[SYMBOL-UNIVERSE] Failed to select chart symbol %s, not adding", chartSymbol);
            }
        }

        return (ArraySize(activePairs) > 0);
    }
};

#endif
