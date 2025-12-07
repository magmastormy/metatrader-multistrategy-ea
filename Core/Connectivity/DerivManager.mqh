//+------------------------------------------------------------------+
//| Deriv Contract Management Module                                   |
//+------------------------------------------------------------------+
#ifndef __DERIV_MANAGER_MQH__
#define __DERIV_MANAGER_MQH__

#include "../Utilities/Utilities.mqh"

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

// Define Deriv contract types
enum ENUM_DERIV_CONTRACT_TYPE {
    DERIV_CONTRACT_VOLATILITY,
    DERIV_CONTRACT_STEP,
    DERIV_CONTRACT_RANGE,
    DERIV_CONTRACT_UPDOWN,
    DERIV_CONTRACT_BOOM_CRASH,
    DERIV_CONTRACT_JUMP
};

// Define Deriv synthetic instrument types
enum ENUM_DERIV_SYNTHETIC_TYPE {
    DERIV_VOLATILITY_10,
    DERIV_VOLATILITY_25,
    DERIV_VOLATILITY_50,
    DERIV_VOLATILITY_75,
    DERIV_VOLATILITY_100,
    DERIV_STEP_10,
    DERIV_STEP_25,
    DERIV_STEP_50,
    DERIV_STEP_100,
    DERIV_BOOM_300,
    DERIV_BOOM_500,
    DERIV_BOOM_1000,
    DERIV_CRASH_300,
    DERIV_CRASH_500,
    DERIV_CRASH_1000,
    DERIV_JUMP_10,
    DERIV_JUMP_25,
    DERIV_JUMP_50,
    DERIV_JUMP_75,
    DERIV_JUMP_100
};

// Synthetic instrument configuration
struct SyntheticConfig {
    string symbol;
    ENUM_DERIV_SYNTHETIC_TYPE type;
    double minStopDistance;     // Minimum stop distance in points
    double optimalSpread;       // Typical spread
    double volatilityFactor;    // Volatility multiplier for position sizing
    int ticksPerSecond;         // Average ticks per second
    bool isHighFrequency;       // Suitable for scalping
    double maxLeverage;         // Maximum recommended leverage
    string description;
};

// Define Deriv contract structure
struct DerivContract {
    string symbol;
    ENUM_DERIV_CONTRACT_TYPE type;
    int duration;
    double barrier;
    datetime startTime;
    datetime endTime;
    bool isActive;
    double entryPrice;
    double currentPrice;
    int direction; // 1 for up, -1 for down
};

class CDerivManager {
private:
    bool m_isDerivSynthetic;
    string m_syntheticPrefix;
    DerivContract m_activeContracts[];
    int m_maxActiveContracts;
    CUtilities* m_utilities;
    ENUM_DERIV_CONTRACT_TYPE m_defaultContractType;
    int m_defaultDuration;
    double m_defaultBarrier;
    
    // Synthetic instruments configuration
    SyntheticConfig m_syntheticConfigs[];
    bool m_aggressiveMode;
    double m_maxRiskPerSynthetic;
    int m_maxPositionsPerSynthetic;
    
    // Check specific contract types
    bool CheckVolatilityContract(int contractIndex) {
        if(contractIndex < 0 || contractIndex >= ArraySize(m_activeContracts)) return false;
        if(!m_activeContracts[contractIndex].isActive) return false;
        
        DerivContract contract = m_activeContracts[contractIndex];
        
        // Get current price
        double price = SymbolInfoDouble(contract.symbol, SYMBOL_BID);
        contract.currentPrice = price;
        
        // Check if contract has expired
        datetime now = TimeCurrent();
        if(now >= contract.endTime) {
            contract.isActive = false;
            string logMsg = StringFormat("Volatility contract for %s has expired. Entry: %f, Exit: %f", 
                contract.symbol, contract.entryPrice, contract.currentPrice);
            m_utilities.LogInfo("DerivManager", logMsg);
            return false;
        }
        
        return true;
    }
    
    bool CheckStepContract(int contractIndex) {
        if(contractIndex < 0 || contractIndex >= ArraySize(m_activeContracts)) return false;
        if(!m_activeContracts[contractIndex].isActive) return false;
        
        DerivContract contract = m_activeContracts[contractIndex];
        
        // Get current price
        double price = SymbolInfoDouble(contract.symbol, SYMBOL_BID);
        contract.currentPrice = price;
        
        // Check if contract has expired or hit barrier
        datetime now = TimeCurrent();
        if(now >= contract.endTime || MathAbs(price - contract.barrier) <= _Point) {
            contract.isActive = false;
            string logMsg = StringFormat("Step contract for %s has ended. Entry: %f, Exit: %f, Barrier: %f", 
                contract.symbol, contract.entryPrice, contract.currentPrice, contract.barrier);
            m_utilities.LogInfo("DerivManager", logMsg);
            return false;
        }
        
        return true;
    }
    
    bool CheckRangeContract(int contractIndex) {
        if(contractIndex < 0 || contractIndex >= ArraySize(m_activeContracts)) return false;
        if(!m_activeContracts[contractIndex].isActive) return false;
        
        DerivContract contract = m_activeContracts[contractIndex];
        
        // Get current price
        double price = SymbolInfoDouble(contract.symbol, SYMBOL_BID);
        contract.currentPrice = price;
        
        // Check if price has broken out of range
        datetime now = TimeCurrent();
        if(now >= contract.endTime || MathAbs(price - contract.barrier) > contract.duration * _Point) {
            contract.isActive = false;
            string logMsg = StringFormat("Range contract for %s has ended. Entry: %f, Exit: %f, Range: %f", 
                contract.symbol, contract.entryPrice, contract.currentPrice, contract.duration * _Point);
            m_utilities.LogInfo("DerivManager", logMsg);
            return false;
        }
        
        return true;
    }
    
    bool CheckUpDownContract(int contractIndex) {
        if(contractIndex < 0 || contractIndex >= ArraySize(m_activeContracts)) return false;
        if(!m_activeContracts[contractIndex].isActive) return false;
        
        DerivContract contract = m_activeContracts[contractIndex];
        
        // Get current price
        double price = SymbolInfoDouble(contract.symbol, SYMBOL_BID);
        contract.currentPrice = price;
        
        // Check if contract has expired
        datetime now = TimeCurrent();
        if(now >= contract.endTime) {
            contract.isActive = false;
            bool isWin = (contract.direction == 1 && price > contract.entryPrice) ||
                        (contract.direction == -1 && price < contract.entryPrice);
            string logMsg = StringFormat("Up/Down contract for %s has ended. Entry: %f, Exit: %f, Direction: %d, Result: %s", 
                contract.symbol, contract.entryPrice, contract.currentPrice, 
                contract.direction, isWin ? "WIN" : "LOSS");
            m_utilities.LogInfo("DerivManager", logMsg);
            return false;
        }
        
        return true;
    }
    
    // Initialize synthetic instruments configuration
    void InitializeSyntheticConfigs() {
        ArrayResize(m_syntheticConfigs, 20);
        
        // Volatility Indices - High frequency, low spreads
        m_syntheticConfigs[0].symbol = "Volatility 10 Index";
        m_syntheticConfigs[0].type = DERIV_VOLATILITY_10;
        m_syntheticConfigs[0].minStopDistance = 0.5;
        m_syntheticConfigs[0].optimalSpread = 0.01;
        m_syntheticConfigs[0].volatilityFactor = 1.0;
        m_syntheticConfigs[0].ticksPerSecond = 100;
        m_syntheticConfigs[0].isHighFrequency = true;
        m_syntheticConfigs[0].maxLeverage = 1000;
        m_syntheticConfigs[0].description = "Ultra-high frequency, 1 tick per second";
        
        m_syntheticConfigs[1].symbol = "Volatility 25 Index";
        m_syntheticConfigs[1].type = DERIV_VOLATILITY_25;
        m_syntheticConfigs[1].minStopDistance = 1.0;
        m_syntheticConfigs[1].optimalSpread = 0.02;
        m_syntheticConfigs[1].volatilityFactor = 2.5;
        m_syntheticConfigs[1].ticksPerSecond = 40;
        m_syntheticConfigs[1].isHighFrequency = true;
        m_syntheticConfigs[1].maxLeverage = 500;
        m_syntheticConfigs[1].description = "High frequency, moderate volatility";
        
        m_syntheticConfigs[2].symbol = "Volatility 50 Index";
        m_syntheticConfigs[2].type = DERIV_VOLATILITY_50;
        m_syntheticConfigs[2].minStopDistance = 2.0;
        m_syntheticConfigs[2].optimalSpread = 0.03;
        m_syntheticConfigs[2].volatilityFactor = 5.0;
        m_syntheticConfigs[2].ticksPerSecond = 20;
        m_syntheticConfigs[2].isHighFrequency = true;
        m_syntheticConfigs[2].maxLeverage = 200;
        m_syntheticConfigs[2].description = "Medium frequency, balanced volatility";
        
        m_syntheticConfigs[3].symbol = "Volatility 75 Index";
        m_syntheticConfigs[3].type = DERIV_VOLATILITY_75;
        m_syntheticConfigs[3].minStopDistance = 3.0;
        m_syntheticConfigs[3].optimalSpread = 0.04;
        m_syntheticConfigs[3].volatilityFactor = 7.5;
        m_syntheticConfigs[3].ticksPerSecond = 15;
        m_syntheticConfigs[3].isHighFrequency = true;
        m_syntheticConfigs[3].maxLeverage = 100;
        m_syntheticConfigs[3].description = "Lower frequency, higher volatility";
        
        m_syntheticConfigs[4].symbol = "Volatility 100 Index";
        m_syntheticConfigs[4].type = DERIV_VOLATILITY_100;
        m_syntheticConfigs[4].minStopDistance = 4.0;
        m_syntheticConfigs[4].optimalSpread = 0.05;
        m_syntheticConfigs[4].volatilityFactor = 10.0;
        m_syntheticConfigs[4].ticksPerSecond = 10;
        m_syntheticConfigs[4].isHighFrequency = false;
        m_syntheticConfigs[4].maxLeverage = 50;
        m_syntheticConfigs[4].description = "Lowest frequency, highest volatility";
        
        // Step Indices - Predictable movements
        m_syntheticConfigs[5].symbol = "Step Index 10";
        m_syntheticConfigs[5].type = DERIV_STEP_10;
        m_syntheticConfigs[5].minStopDistance = 1.0;
        m_syntheticConfigs[5].optimalSpread = 0.02;
        m_syntheticConfigs[5].volatilityFactor = 1.0;
        m_syntheticConfigs[5].ticksPerSecond = 50;
        m_syntheticConfigs[5].isHighFrequency = true;
        m_syntheticConfigs[5].maxLeverage = 500;
        m_syntheticConfigs[5].description = "Steps every 10 ticks on average";
        
        m_syntheticConfigs[6].symbol = "Step Index 25";
        m_syntheticConfigs[6].type = DERIV_STEP_25;
        m_syntheticConfigs[6].minStopDistance = 2.0;
        m_syntheticConfigs[6].optimalSpread = 0.03;
        m_syntheticConfigs[6].volatilityFactor = 2.5;
        m_syntheticConfigs[6].ticksPerSecond = 30;
        m_syntheticConfigs[6].isHighFrequency = true;
        m_syntheticConfigs[6].maxLeverage = 300;
        m_syntheticConfigs[6].description = "Steps every 25 ticks on average";
        
        m_syntheticConfigs[7].symbol = "Step Index 50";
        m_syntheticConfigs[7].type = DERIV_STEP_50;
        m_syntheticConfigs[7].minStopDistance = 3.0;
        m_syntheticConfigs[7].optimalSpread = 0.04;
        m_syntheticConfigs[7].volatilityFactor = 5.0;
        m_syntheticConfigs[7].ticksPerSecond = 20;
        m_syntheticConfigs[7].isHighFrequency = true;
        m_syntheticConfigs[7].maxLeverage = 200;
        m_syntheticConfigs[7].description = "Steps every 50 ticks on average";
        
        m_syntheticConfigs[8].symbol = "Step Index 100";
        m_syntheticConfigs[8].type = DERIV_STEP_100;
        m_syntheticConfigs[8].minStopDistance = 5.0;
        m_syntheticConfigs[8].optimalSpread = 0.05;
        m_syntheticConfigs[8].volatilityFactor = 10.0;
        m_syntheticConfigs[8].ticksPerSecond = 10;
        m_syntheticConfigs[8].isHighFrequency = false;
        m_syntheticConfigs[8].maxLeverage = 100;
        m_syntheticConfigs[8].description = "Steps every 100 ticks on average";
        
        // Boom/Crash Indices - Spike patterns
        m_syntheticConfigs[9].symbol = "Boom 300 Index";
        m_syntheticConfigs[9].type = DERIV_BOOM_300;
        m_syntheticConfigs[9].minStopDistance = 10.0;
        m_syntheticConfigs[9].optimalSpread = 0.1;
        m_syntheticConfigs[9].volatilityFactor = 15.0;
        m_syntheticConfigs[9].ticksPerSecond = 5;
        m_syntheticConfigs[9].isHighFrequency = false;
        m_syntheticConfigs[9].maxLeverage = 50;
        m_syntheticConfigs[9].description = "Boom spikes every 300 ticks on average";
        
        m_syntheticConfigs[10].symbol = "Boom 500 Index";
        m_syntheticConfigs[10].type = DERIV_BOOM_500;
        m_syntheticConfigs[10].minStopDistance = 15.0;
        m_syntheticConfigs[10].optimalSpread = 0.15;
        m_syntheticConfigs[10].volatilityFactor = 20.0;
        m_syntheticConfigs[10].ticksPerSecond = 3;
        m_syntheticConfigs[10].isHighFrequency = false;
        m_syntheticConfigs[10].maxLeverage = 30;
        m_syntheticConfigs[10].description = "Boom spikes every 500 ticks on average";
        
        m_syntheticConfigs[11].symbol = "Boom 1000 Index";
        m_syntheticConfigs[11].type = DERIV_BOOM_1000;
        m_syntheticConfigs[11].minStopDistance = 25.0;
        m_syntheticConfigs[11].optimalSpread = 0.2;
        m_syntheticConfigs[11].volatilityFactor = 30.0;
        m_syntheticConfigs[11].ticksPerSecond = 2;
        m_syntheticConfigs[11].isHighFrequency = false;
        m_syntheticConfigs[11].maxLeverage = 20;
        m_syntheticConfigs[11].description = "Boom spikes every 1000 ticks on average";
        
        m_syntheticConfigs[12].symbol = "Crash 300 Index";
        m_syntheticConfigs[12].type = DERIV_CRASH_300;
        m_syntheticConfigs[12].minStopDistance = 10.0;
        m_syntheticConfigs[12].optimalSpread = 0.1;
        m_syntheticConfigs[12].volatilityFactor = 15.0;
        m_syntheticConfigs[12].ticksPerSecond = 5;
        m_syntheticConfigs[12].isHighFrequency = false;
        m_syntheticConfigs[12].maxLeverage = 50;
        m_syntheticConfigs[12].description = "Crash spikes every 300 ticks on average";
        
        m_syntheticConfigs[13].symbol = "Crash 500 Index";
        m_syntheticConfigs[13].type = DERIV_CRASH_500;
        m_syntheticConfigs[13].minStopDistance = 15.0;
        m_syntheticConfigs[13].optimalSpread = 0.15;
        m_syntheticConfigs[13].volatilityFactor = 20.0;
        m_syntheticConfigs[13].ticksPerSecond = 3;
        m_syntheticConfigs[13].isHighFrequency = false;
        m_syntheticConfigs[13].maxLeverage = 30;
        m_syntheticConfigs[13].description = "Crash spikes every 500 ticks on average";
        
        m_syntheticConfigs[14].symbol = "Crash 1000 Index";
        m_syntheticConfigs[14].type = DERIV_CRASH_1000;
        m_syntheticConfigs[14].minStopDistance = 25.0;
        m_syntheticConfigs[14].optimalSpread = 0.2;
        m_syntheticConfigs[14].volatilityFactor = 30.0;
        m_syntheticConfigs[14].ticksPerSecond = 2;
        m_syntheticConfigs[14].isHighFrequency = false;
        m_syntheticConfigs[14].maxLeverage = 20;
        m_syntheticConfigs[14].description = "Crash spikes every 1000 ticks on average";
        
        // Jump Indices - Sudden jumps
        m_syntheticConfigs[15].symbol = "Jump 10 Index";
        m_syntheticConfigs[15].type = DERIV_JUMP_10;
        m_syntheticConfigs[15].minStopDistance = 2.0;
        m_syntheticConfigs[15].optimalSpread = 0.03;
        m_syntheticConfigs[15].volatilityFactor = 2.0;
        m_syntheticConfigs[15].ticksPerSecond = 40;
        m_syntheticConfigs[15].isHighFrequency = true;
        m_syntheticConfigs[15].maxLeverage = 300;
        m_syntheticConfigs[15].description = "Jump every 10 ticks on average";
        
        m_syntheticConfigs[16].symbol = "Jump 25 Index";
        m_syntheticConfigs[16].type = DERIV_JUMP_25;
        m_syntheticConfigs[16].minStopDistance = 4.0;
        m_syntheticConfigs[16].optimalSpread = 0.05;
        m_syntheticConfigs[16].volatilityFactor = 5.0;
        m_syntheticConfigs[16].ticksPerSecond = 25;
        m_syntheticConfigs[16].isHighFrequency = true;
        m_syntheticConfigs[16].maxLeverage = 200;
        m_syntheticConfigs[16].description = "Jump every 25 ticks on average";
        
        m_syntheticConfigs[17].symbol = "Jump 50 Index";
        m_syntheticConfigs[17].type = DERIV_JUMP_50;
        m_syntheticConfigs[17].minStopDistance = 6.0;
        m_syntheticConfigs[17].optimalSpread = 0.07;
        m_syntheticConfigs[17].volatilityFactor = 8.0;
        m_syntheticConfigs[17].ticksPerSecond = 15;
        m_syntheticConfigs[17].isHighFrequency = true;
        m_syntheticConfigs[17].maxLeverage = 150;
        m_syntheticConfigs[17].description = "Jump every 50 ticks on average";
        
        m_syntheticConfigs[18].symbol = "Jump 75 Index";
        m_syntheticConfigs[18].type = DERIV_JUMP_75;
        m_syntheticConfigs[18].minStopDistance = 8.0;
        m_syntheticConfigs[18].optimalSpread = 0.09;
        m_syntheticConfigs[18].volatilityFactor = 12.0;
        m_syntheticConfigs[18].ticksPerSecond = 10;
        m_syntheticConfigs[18].isHighFrequency = false;
        m_syntheticConfigs[18].maxLeverage = 100;
        m_syntheticConfigs[18].description = "Jump every 75 ticks on average";
        
        m_syntheticConfigs[19].symbol = "Jump 100 Index";
        m_syntheticConfigs[19].type = DERIV_JUMP_100;
        m_syntheticConfigs[19].minStopDistance = 10.0;
        m_syntheticConfigs[19].optimalSpread = 0.1;
        m_syntheticConfigs[19].volatilityFactor = 15.0;
        m_syntheticConfigs[19].ticksPerSecond = 8;
        m_syntheticConfigs[19].isHighFrequency = false;
        m_syntheticConfigs[19].maxLeverage = 80;
        m_syntheticConfigs[19].description = "Jump every 100 ticks on average";
    }
    
public:
    CDerivManager(CUtilities* utils): 
        m_isDerivSynthetic(false),
        m_syntheticPrefix(""),
        m_maxActiveContracts(10),
        m_aggressiveMode(true),
        m_maxRiskPerSynthetic(2.0),
        m_maxPositionsPerSynthetic(5),
        m_utilities(utils),
        m_defaultContractType(DERIV_CONTRACT_VOLATILITY), // Default contract type
        m_defaultDuration(5),                             // Default duration e.g. 5 minutes
        m_defaultBarrier(0.0)                             // Default barrier, adjust as needed
    {
        ArrayResize(m_activeContracts, 0);
    }
    
    void Initialize(bool isDerivSynthetic, string prefix, int maxContracts) {
        m_isDerivSynthetic = isDerivSynthetic;
        m_syntheticPrefix = prefix;
        m_maxActiveContracts = maxContracts;
    }
    
    bool InitializeDerivSynthetic(string symbol) {
        if(!m_isDerivSynthetic) return true;
        
        string fullSymbol = m_syntheticPrefix + symbol;
        if(!SymbolSelect(fullSymbol, true)) {
            string errorMsg = "Failed to select Deriv Synthetic symbol: " + fullSymbol;
            if (m_utilities != NULL) {
                m_utilities.LogError("DerivManager", errorMsg);
            } else {
                Print("Error: ", errorMsg);
            }
            return false;
        }
        
        return true;
    }
    
    // Initialize synthetic symbol (alias for InitializeDerivSynthetic)
    bool InitializeSynthetic(string symbol) {
        return InitializeDerivSynthetic(symbol);
    }

    void SetIsDerivSynthetic(bool isSynthetic) {
        m_isDerivSynthetic = isSynthetic;
    }

    void SetSyntheticPrefix(string prefix) {
        m_syntheticPrefix = prefix;
    }

    void SetDefaultContractParams(ENUM_DERIV_CONTRACT_TYPE type, int duration, double barrier) {
        m_defaultContractType = type;
        m_defaultDuration = duration;
        m_defaultBarrier = barrier;
    }
    
    // AGGRESSIVE FIX: Check if symbol is a Deriv synthetic with validation
    bool IsDerivSynthetic(const string symbol) {
        for(int i = 0; i < ArraySize(m_syntheticConfigs); i++) {
            if(StringCompare(m_syntheticConfigs[i].symbol, symbol, false) == 0) {
                return true;
            }
        }
        return false;
    }
    
    // AGGRESSIVE FIX: Validate and ensure symbol availability
    bool ValidateAndEnsureSymbol(const string symbol) {
        // First check if symbol exists in market watch
        if(!SymbolSelect(symbol, true)) {
            Print("[DERIV] Symbol ", symbol, " not in market watch, attempting to add...");
            if(!SymbolSelect(symbol, true)) {
                Print("[ERROR] Failed to add symbol ", symbol, " to market watch");
                return false;
            }
        }
        
        // Wait for symbol to synchronize
        int timeout = 5000; // 5 seconds
        int elapsed = 0;
        while(elapsed < timeout) {
            double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
            double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
            if(bid > 0 && ask > 0) {
                Print("[DERIV] Symbol ", symbol, " synchronized successfully (Bid: ", bid, ", Ask: ", ask, ")");
                return true;
            }
            Sleep(100);
            elapsed += 100;
        }
        
        Print("[ERROR] Symbol ", symbol, " failed to synchronize after ", timeout, "ms");
        return false;
    }
    
    bool CreateContract(string symbol, ENUM_DERIV_CONTRACT_TYPE type, int duration, 
                       double barrier, int direction = 1) {
        if(ArraySize(m_activeContracts) >= m_maxActiveContracts) {
            if (m_utilities != NULL) {
                m_utilities.LogWarning("DerivManager", "Maximum number of active contracts reached");
            } else {
                Print("Warning: Maximum number of active contracts reached");
            }
            return false;
        }
        
        DerivContract contract;
        contract.symbol = symbol;
        contract.type = type;
        contract.duration = duration;
        contract.barrier = barrier;
        contract.startTime = TimeCurrent();
        contract.endTime = contract.startTime + duration * 60; // Convert minutes to seconds
        contract.isActive = true;
        contract.entryPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
        contract.currentPrice = contract.entryPrice;
        contract.direction = direction;
        
        int size = ArraySize(m_activeContracts);
        ArrayResize(m_activeContracts, size + 1);
        m_activeContracts[size] = contract;
        
        if (m_utilities != NULL) {
            string logMsg = StringFormat("Created new %s contract for %s. Duration: %d mins, Barrier: %f", 
                EnumToString(type), symbol, duration, barrier);
            m_utilities.LogInfo("DerivManager", logMsg);
        }
        
        return true;
    }
    
    void ManageDerivContracts() {
        if(!m_isDerivSynthetic) return;
        
        // Process active contracts
        for(int i = ArraySize(m_activeContracts) - 1; i >= 0; i--) {
            if(!m_activeContracts[i].isActive) continue;
            
            bool isActive = false;
            switch(m_activeContracts[i].type) {
                case DERIV_CONTRACT_VOLATILITY:
                    isActive = CheckVolatilityContract(i);
                    break;
                case DERIV_CONTRACT_STEP:
                    isActive = CheckStepContract(i);
                    break;
                case DERIV_CONTRACT_RANGE:
                    isActive = CheckRangeContract(i);
                    break;
                case DERIV_CONTRACT_UPDOWN:
                    isActive = CheckUpDownContract(i);
                    break;
            }
            
            // Remove inactive contracts
            if(!isActive) {
                // Move last contract to this position and resize array
                if(i < ArraySize(m_activeContracts) - 1) {
                    m_activeContracts[i] = m_activeContracts[ArraySize(m_activeContracts) - 1];
                }
                ArrayResize(m_activeContracts, ArraySize(m_activeContracts) - 1);
            }
        }
    }
    
    int GetActiveContractCount() const {
        return ArraySize(m_activeContracts);
    }
    
    bool GetContractDetails(int index, DerivContract &contract) {
        if(index < 0 || index >= ArraySize(m_activeContracts)) return false;
        contract = m_activeContracts[index];
        return true;
    }
    
    bool IsDerivSynthetic() const {
        return m_isDerivSynthetic;
    }
    
    string GetSyntheticPrefix() const {
        return m_syntheticPrefix;
    }
    
    // Get the synthetic symbol name for a given base symbol
    string GetSyntheticSymbol(const string &baseSymbol) {
        if(!m_isDerivSynthetic) return baseSymbol; // Return original if not using synthetics
        return m_syntheticPrefix + baseSymbol;
    }
    
    // AGGRESSIVE TRADING METHODS FOR DERIV SYNTHETICS
    
    // Initialize for aggressive synthetic trading
    bool InitializeAggressiveMode() {
        InitializeSyntheticConfigs();
        m_aggressiveMode = true;
        m_maxRiskPerSynthetic = 3.0; // 3% risk per synthetic
        m_maxPositionsPerSynthetic = 10; // Up to 10 positions per synthetic
        
        Print("[DERIV] Aggressive mode initialized - Ready for high-frequency synthetic trading!");
        return true;
    }
    
    // Get optimal synthetic symbols for aggressive trading
    void GetAggressiveSyntheticSymbols(string &symbols[]) {
        ArrayResize(symbols, 0);
        
        // Prioritize high-frequency, low-spread synthetics
        string aggressiveSymbols[] = {
            "Volatility 10 Index",  // Ultra-high frequency
            "Volatility 25 Index",  // High frequency
            "Step Index 10",        // Predictable steps
            "Step Index 25",        // Moderate steps
            "Jump 10 Index",        // Frequent jumps
            "Jump 25 Index",        // Moderate jumps
            "Volatility 50 Index",  // Balanced volatility
            "Step Index 50",        // Larger steps
            "Boom 300 Index",       // Spike opportunities
            "Crash 300 Index"       // Crash opportunities
        };
        
        ArrayResize(symbols, ArraySize(aggressiveSymbols));
        for(int i = 0; i < ArraySize(aggressiveSymbols); i++) {
            symbols[i] = aggressiveSymbols[i];
        }
    }
    
    // Get synthetic configuration by symbol
    SyntheticConfig GetSyntheticConfig(const string symbol) {
        for(int i = 0; i < ArraySize(m_syntheticConfigs); i++) {
            if(m_syntheticConfigs[i].symbol == symbol) {
                return m_syntheticConfigs[i];
            }
        }
        
        // Return default config if not found
        SyntheticConfig defaultConfig;
        defaultConfig.symbol = symbol;
        defaultConfig.type = DERIV_VOLATILITY_10;
        defaultConfig.minStopDistance = 1.0;
        defaultConfig.optimalSpread = 0.02;
        defaultConfig.volatilityFactor = 1.0;
        defaultConfig.ticksPerSecond = 50;
        defaultConfig.isHighFrequency = true;
        defaultConfig.maxLeverage = 100;
        defaultConfig.description = "Unknown synthetic";
        return defaultConfig;
    }
    
    // Calculate optimal position size for synthetic
    double CalculateAggressivePositionSize(const string symbol, double accountBalance, double riskPercent) {
        SyntheticConfig config = GetSyntheticConfig(symbol);
        
        // Base position size calculation - ZERO DIVIDE FIX
        double baseSize = 0.01; // Default safe value
        if(config.minStopDistance > 0) {
            baseSize = (accountBalance * riskPercent / 100.0) / config.minStopDistance;
        } else {
            Print("[ZERO-DIVIDE-FIX] Invalid minStopDistance: ", config.minStopDistance, " - using default size");
        }
        
        // Adjust for volatility and frequency
        if(config.isHighFrequency) {
            baseSize *= 1.5; // Increase size for high-frequency instruments
        }
        
        // Apply leverage if aggressive mode
        if(m_aggressiveMode && config.maxLeverage > 1) {
            baseSize *= MathMin(config.maxLeverage / 100.0, 5.0); // Max 5x leverage
        }
        
        // Normalize to minimum lot size (typically 0.01)
        double minLot = 0.01;
        baseSize = MathMax(minLot, MathRound(baseSize / minLot) * minLot);
        
        return baseSize;
    }
    
    // Get optimal stop loss for synthetic
    double GetOptimalStopLoss(const string symbol, double entryPrice, bool isBuy) {
        SyntheticConfig config = GetSyntheticConfig(symbol);
        
        double stopDistance = config.minStopDistance * 1.2; // 20% buffer
        
        // Adjust for instrument type
        if(config.type >= DERIV_BOOM_300 && config.type <= DERIV_CRASH_1000) {
            stopDistance *= 2.0; // Wider stops for boom/crash
        }
        
        if(isBuy) {
            return entryPrice - stopDistance;
        } else {
            return entryPrice + stopDistance;
        }
    }
    
    // Get optimal take profit for synthetic
    double GetOptimalTakeProfit(const string symbol, double entryPrice, bool isBuy) {
        SyntheticConfig config = GetSyntheticConfig(symbol);
        
        double profitDistance = config.minStopDistance * 2.0; // 2:1 risk-reward minimum
        
        // Adjust for high-frequency instruments
        if(config.isHighFrequency) {
            profitDistance *= 1.5; // Smaller but more frequent profits
        }
        
        // Adjust for volatility
        profitDistance *= config.volatilityFactor;
        
        if(isBuy) {
            return entryPrice + profitDistance;
        } else {
            return entryPrice - profitDistance;
        }
    }
    
    // Check if symbol is suitable for scalping
    bool IsSuitableForScalping(const string symbol) {
        SyntheticConfig config = GetSyntheticConfig(symbol);
        return config.isHighFrequency && config.ticksPerSecond >= 20;
    }
    
    // Get recommended timeframes for synthetic
    void GetRecommendedTimeframes(const string symbol, ENUM_TIMEFRAMES &timeframes[]) {
        SyntheticConfig config = GetSyntheticConfig(symbol);
        
        ArrayResize(timeframes, 0);
        
        if(config.isHighFrequency) {
            // High-frequency instruments: M1, M5
            ArrayResize(timeframes, 2);
            timeframes[0] = PERIOD_M1;
            timeframes[1] = PERIOD_M5;
        } else {
            // Lower frequency: M5, M15, H1
            ArrayResize(timeframes, 3);
            timeframes[0] = PERIOD_M5;
            timeframes[1] = PERIOD_M15;
            timeframes[2] = PERIOD_H1;
        }
    }
    
    // Log synthetic trading statistics
    void LogSyntheticStats() {
        Print("[DERIV] === SYNTHETIC TRADING STATISTICS ===");
        Print("[DERIV] Aggressive Mode: ", m_aggressiveMode ? "ENABLED" : "DISABLED");
        Print("[DERIV] Max Risk Per Synthetic: ", m_maxRiskPerSynthetic, "%");
        Print("[DERIV] Max Positions Per Synthetic: ", m_maxPositionsPerSynthetic);
        Print("[DERIV] Total Synthetic Configs: ", ArraySize(m_syntheticConfigs));
        
        // Log high-frequency instruments
        int hfCount = 0;
        for(int i = 0; i < ArraySize(m_syntheticConfigs); i++) {
            if(m_syntheticConfigs[i].isHighFrequency) hfCount++;
        }
        Print("[DERIV] High-Frequency Instruments: ", hfCount, "/", ArraySize(m_syntheticConfigs));
    }
};

#endif

