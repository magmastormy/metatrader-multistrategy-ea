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
            
            if(StringFind(symUpper, existingUpper) >= 0 || StringFind(existingUpper, symUpper) >= 0)
            {
                if(symUpper != existingUpper)
                    return true;
            }
        }
        return false;
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

    static bool Build(const string rawSymbols, string &activePairs[], const SSymbolValidationConfig &config)
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

        for(int i = 0; i < ArraySize(symbols); i++)
        {
            string sym = symbols[i];
            StringTrimLeft(sym);
            StringTrimRight(sym);

            if(StringLen(sym) == 0)
            {
                Print("[SYMBOLS] Empty symbol token skipped at input index ", i, " - Please check InpSymbolsToTrade parameter for empty entries");
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
                continue;
            }

            long symbolTradeMode = SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
            if(symbolTradeMode == SYMBOL_TRADE_MODE_DISABLED)
            {
                Print("[WARNING] Symbol ", sym, " trading is disabled - skipping");
                continue;
            }
            if(symbolTradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
            {
                Print("[WARNING] Symbol ", sym, " is close-only - cannot open new positions, only close existing - skipping");
                continue;
            }
            if(SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP) <= 0.0)
            {
                Print("[WARNING] Symbol ", sym, " has invalid volume step - skipping");
                continue;
            }

            if(ContainsSymbol(activePairs, sym))
            {
                Print("[SYMBOLS] Duplicate symbol skipped: ", sym);
                continue;
            }

            if(HasSimilarSymbol(activePairs, sym))
            {
                Print("[WARNING] Symbol ", sym, " has similar symbol already in list - consider reviewing");
            }

            long spread = SymbolInfoInteger(sym, SYMBOL_SPREAD);
            if(spread > config.maxSpreadPoints)
            {
                PrintFormat("[SYMBOLS] Symbol %s rejected - spread %d points exceeds maximum threshold (%d points)", 
                            sym, spread, config.maxSpreadPoints);
                continue;
            }

            if(config.enableVolumeCheck)
            {
                // Volume check skipped - SYMBOL_VOLUME not available in MQL5
                // Use tick volume or other liquidity proxies instead
                PrintFormat("[SYMBOLS] Symbol %s - volume check skipped (not available)", sym);
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

        return (ArraySize(activePairs) > 0);
    }
};

#endif
