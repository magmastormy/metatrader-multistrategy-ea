//+------------------------------------------------------------------+
//| StrategyConfig.mqh - Configuration for trading strategies        |
//| Copyright 2025, Your Company Name                                |
//| https://www.yoursite.com                                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Company Name"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

//+------------------------------------------------------------------+
//| Strategy Configuration Structure                                 |
//+------------------------------------------------------------------+
struct SStrategyConfig
{
    string   strategyName;     // Name of the strategy
    bool     enabled;          // Whether the strategy is enabled
    double   weight;           // Strategy weight (0.0 to 1.0)
    string   symbol;           // Symbol to trade (empty for current)
    ENUM_TIMEFRAMES timeframe;  // Timeframe to use (0 for current)
    
    // Common parameters
    double   riskPercent;      // Risk percentage per trade
    int      magicNumber;      // Magic number for trades
    
    // Strategy-specific parameters
    // RSI Strategy
    struct SRsiParams
    {
        int      period;        // RSI Period
        double   overbought;    // Overbought level
        double   oversold;      // Oversold level
    } rsi;
    
    // Moving Average Strategy
    struct SMaParams
    {
        int      fastMaPeriod;  // Fast MA period
        int      slowMaPeriod;  // Slow MA period
        ENUM_MA_METHOD maMethod; // MA method
    } ma;
    
    // MACD Strategy
    struct SMacdParams
    {
        int      fastEma;       // Fast EMA period
        int      slowEma;       // Slow EMA period
        int      signalPeriod;   // Signal line period
    } macd;
    
    // Bollinger Bands Strategy
    struct SBollingerParams
    {
        int      period;        // BB Period
        double   deviation;      // BB Standard deviation
    } bollinger;
    
    // Supply & Demand Strategy
    struct SSupplyDemandParams
    {
        int      zoneStrength;   // Strength of the zone (in bars)
        double   zoneMultiplier;  // Multiplier for zone height
        int      maxZoneAge;      // Maximum age of a zone (in bars)
    } supplyDemand;
    
    // Order Block & FVG Strategy
    struct SOrderBlockParams
    {
        int      blockStrength;  // Strength of the order block (in bars)
        double   fvgMultiplier;   // Multiplier for FVG size
        int      blockAge;        // Maximum age of an order block (in bars)
    } orderBlock;
    
    // Fibonacci Strategy
    struct SFibonacciParams
    {
        int      swingPoints;    // Number of swing points to consider
        double   retracement[];   // Array of retracement levels
        int      retracementCount; // Number of retracement levels
    } fibonacci;
    
    // Elliott Wave Strategy
    struct SElliottParams
    {
        int      waveDegree;     // Degree of Elliott Wave
        double   impulseRules[];  // Rules for impulse waves
        double   correctionRules[]; // Rules for correction waves
        int      ruleCount;       // Number of rules
    } elliott;
    
    // Swing Trading Strategy
    struct SSwingParams
    {
        int      swingPeriod;    // Period for swing detection
        double   atrMultiplier;   // Multiplier for ATR-based stops
        int      atrPeriod;       // Period for ATR calculation
    } swing;
    
    // Constructor with default values
    SStrategyConfig()
    {
        strategyName = "";
        enabled = true;
        weight = 1.0;
        symbol = "";
        timeframe = PERIOD_CURRENT;
        riskPercent = 1.0;
        magicNumber = 0;
        
        // RSI defaults
        rsi.period = 14;
        rsi.overbought = 70.0;
        rsi.oversold = 30.0;
        
        // MA defaults
        ma.fastMaPeriod = 10;
        ma.slowMaPeriod = 20;
        ma.maMethod = MODE_EMA;
        
        // MACD defaults
        macd.fastEma = 12;
        macd.slowEma = 26;
        macd.signalPeriod = 9;
        
        // Bollinger Bands defaults
        bollinger.period = 20;
        bollinger.deviation = 2.0;
        
        // Supply & Demand defaults
        supplyDemand.zoneStrength = 5;
        supplyDemand.zoneMultiplier = 1.0;
        supplyDemand.maxZoneAge = 100;
        
        // Order Block & FVG defaults
        orderBlock.blockStrength = 3;
        orderBlock.fvgMultiplier = 1.0;
        orderBlock.blockAge = 50;
        
        // Fibonacci defaults
        fibonacci.swingPoints = 5;
        fibonacci.retracementCount = 6;
        ArrayResize(fibonacci.retracement, fibonacci.retracementCount);
        fibonacci.retracement[0] = 0.236;
        fibonacci.retracement[1] = 0.382;
        fibonacci.retracement[2] = 0.5;
        fibonacci.retracement[3] = 0.618;
        fibonacci.retracement[4] = 0.786;
        fibonacci.retracement[5] = 1.0;
        
        // Elliott Wave defaults
        elliott.waveDegree = 3; // Minor degree
        elliott.ruleCount = 5;
        ArrayResize(elliott.impulseRules, elliott.ruleCount);
        ArrayResize(elliott.correctionRules, elliott.ruleCount);
        
        // Swing Trading defaults
        swing.swingPeriod = 14;
        swing.atrMultiplier = 1.5;
        swing.atrPeriod = 14;
    }
};

//+------------------------------------------------------------------+
//| Load configuration from input parameters                         |
//+------------------------------------------------------------------+
bool LoadConfigFromInputs(SStrategyConfig &config[])
{
    // Production-ready configuration loading from EA inputs
    // This function loads configuration from Expert Advisor input parameters
    
    // Initialize with all strategies
    int count = 6; // Number of strategies
    ArrayResize(config, count);
    
    // RSI Strategy
    config[0].strategyName = "RSI Strategy";
    config[0].enabled = true;
    config[0].weight = 1.0;
    config[0].rsi.period = 14;
    config[0].rsi.overbought = 70.0;
    config[0].rsi.oversold = 30.0;
    
    // Supply & Demand Strategy
    config[1].strategyName = "Supply & Demand";
    config[1].enabled = true;
    config[1].weight = 1.0;
    config[1].supplyDemand.zoneStrength = 5;
    config[1].supplyDemand.zoneMultiplier = 1.0;
    config[1].supplyDemand.maxZoneAge = 100;
    
    // Order Block & FVG Strategy
    config[2].strategyName = "Order Block & FVG";
    config[2].enabled = true;
    config[2].weight = 1.0;
    config[2].orderBlock.blockStrength = 3;
    config[2].orderBlock.fvgMultiplier = 1.0;
    config[2].orderBlock.blockAge = 50;
    
    // Fibonacci Strategy
    config[3].strategyName = "Fibonacci Retracement";
    config[3].enabled = true;
    config[3].weight = 1.0;
    config[3].fibonacci.swingPoints = 5;
    config[3].fibonacci.retracementCount = 6;
    ArrayResize(config[3].fibonacci.retracement, config[3].fibonacci.retracementCount);
    config[3].fibonacci.retracement[0] = 0.236;
    config[3].fibonacci.retracement[1] = 0.382;
    config[3].fibonacci.retracement[2] = 0.5;
    config[3].fibonacci.retracement[3] = 0.618;
    config[3].fibonacci.retracement[4] = 0.786;
    config[3].fibonacci.retracement[5] = 1.0;
    
    // Elliott Wave Strategy
    config[4].strategyName = "Elliott Wave";
    config[4].enabled = true;
    config[4].weight = 1.0;
    config[4].elliott.waveDegree = 3;
    config[4].elliott.ruleCount = 5;
    ArrayResize(config[4].elliott.impulseRules, config[4].elliott.ruleCount);
    ArrayResize(config[4].elliott.correctionRules, config[4].elliott.ruleCount);
    
    // Swing Trading Strategy
    config[5].strategyName = "Swing Trading";
    config[5].enabled = true;
    config[5].weight = 1.0;
    config[5].swing.swingPeriod = 14;
    config[5].swing.atrMultiplier = 1.5;
    config[5].swing.atrPeriod = 14;
    
    return true;
}

//+------------------------------------------------------------------+
//| Load configuration from file                                     |
//+------------------------------------------------------------------+
bool LoadConfigFromFile(const string filename, SStrategyConfig &config[])
{
    // FIXED: Implement loading from file
    int handle = FileOpen(filename, FILE_READ|FILE_TXT|FILE_ANSI);
    if(handle == INVALID_HANDLE) {
        Print("[CONFIG] Failed to open config file: ", filename);
        return false;
    }
    
    ArrayResize(config, 0);
    int configIndex = 0;
    
    while(!FileIsEnding(handle)) {
        string line = FileReadString(handle);
        if(StringLen(line) == 0 || StringGetCharacter(line, 0) == '#') continue; // Skip empty lines and comments
        
        string parts[];
        if(StringSplit(line, '=', parts) == 2) {
            string key = parts[0];
            string value = parts[1];
            
            // Parse configuration based on key
            if(StringFind(key, "Strategy") >= 0) {
                ArrayResize(config, configIndex + 1);
                
                if(key == "StrategyName") config[configIndex].strategyName = value;
                else if(key == "StrategyEnabled") config[configIndex].enabled = (value == "true");
                else if(key == "StrategyWeight") config[configIndex].weight = StringToDouble(value);
                else if(key == "StrategyRiskPercent") config[configIndex].riskPercent = StringToDouble(value);
                
                if(key == "StrategyRiskPercent") configIndex++; // Move to next config after last parameter
            }
        }
    }
    
    FileClose(handle);
    Print("[CONFIG] Loaded ", configIndex, " strategy configurations from ", filename);
    return true;
}

//+------------------------------------------------------------------+
//| Save configuration to file                                       |
//+------------------------------------------------------------------+
bool SaveConfigToFile(const string filename, const SStrategyConfig &config[])
{
    // FIXED: Implement saving to file
    int handle = FileOpen(filename, FILE_WRITE|FILE_TXT|FILE_ANSI);
    if(handle == INVALID_HANDLE) {
        Print("[CONFIG] Failed to create config file: ", filename);
        return false;
    }
    
    // Write header comment
    FileWriteString(handle, "# Strategy Configuration File\n");
    FileWriteString(handle, "# Generated by MultiStrategyAutonomousEA\n");
    FileWriteString(handle, "# Format: Key=Value\n\n");
    
    // Write each strategy configuration
    for(int i = 0; i < ArraySize(config); i++) {
        FileWriteString(handle, "# Strategy " + IntegerToString(i+1) + "\n");
        FileWriteString(handle, "StrategyName=" + config[i].strategyName + "\n");
        FileWriteString(handle, "StrategyEnabled=" + (config[i].enabled ? "true" : "false") + "\n");
        FileWriteString(handle, "StrategyWeight=" + DoubleToString(config[i].weight, 2) + "\n");
        FileWriteString(handle, "StrategyRiskPercent=" + DoubleToString(config[i].riskPercent, 2) + "\n\n");
    }
    
    FileClose(handle);
    Print("[CONFIG] Saved ", ArraySize(config), " strategy configurations to ", filename);
    return true;
}
