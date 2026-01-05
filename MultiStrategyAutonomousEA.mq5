//+------------------------------------------------------------------+
//| MultiStrategyAutonomousEA.mq5 - Advanced AI Trading System      |
//| Autonomous multi-strategy EA with Python AI integration           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

//--- Input parameters (Fixed compilation errors)
input double InpLotSize = 0.1;              // Base lot size
input int InpMagicNumber = 123456;         // Magic number
input bool InpUseCppAI = false;           // Use C++ AI signals
input bool InpUseHybridAI = false;         // Use hybrid AI signals
input bool InpUseEnhancedRisk = true;      // Use enhanced risk management
input double InpMaxRiskPerTrade = 0.02;   // Max risk per trade (2%)
input double InpMaxDailyRisk = 0.06;       // Max daily risk (6%)
input double InpMaxDrawdown = 0.15;        // Max drawdown (15%)
input bool   InpEnableIntelligentProcess = false; // Legacy - ProcessIntelligentTrading removed
input string InpSymbolsToTrade = "EURUSD.0,GBPUSD.0,USDJPY.0,XAUUSD.0,BTCUSD.0,AUDNZD.0,NZDUSD.0,Volatility 75 Index.0,Volatility 100 Index.0,Step Index.0"; // Comprehensive test: Forex, Metals, Crypto, Synthetic Indices
input int    InpMinSecondsBetweenTrades = 120;    // Cooldown in seconds between trades
input int    InpMaxPositionsTotal = 5;            // Global position limit (reduced for better risk control)

//--- Strategy Selection (for testing)
input group "Strategy Selection"
input bool InpEnableMomentum = true;        // Enable Momentum Strategy
input bool InpEnableRSI = true;             // Enable RSI Strategy
input bool InpEnableTrend = true;           // Enable Trend Strategy
input bool InpEnableMeanReversion = true;   // Enable Mean Reversion Strategy
input bool InpEnableSwing = false;          // Enable Swing Strategy
input bool InpEnableVolatility = false;     // Enable Volatility Strategy
input bool InpEnableMACD = false;           // Enable MACD Strategy
input bool InpEnableBollinger = false;      // Enable Bollinger Strategy
input bool InpEnableBollingerBreakout = false; // Enable Bollinger Breakout Strategy
input bool InpEnableSMC = true;               // Enable Advanced SMC Strategy
input bool InpEnableBreakout = false;         // Enable Breakout Strategy
input bool InpEnableFibonacci = false;        // Enable Fibonacci Strategy
input bool InpEnableElliottWave = true;       // Enable Elliott Wave Enhanced Strategy
input bool InpEnableIchimoku = false;         // Enable Ichimoku Strategy
input bool InpEnableHarmonicPatterns = false;  // Enable Harmonic Patterns Strategy
input bool InpEnableSupportResistance = true;  // Enable Support/Resistance + Trendlines
input bool InpEnableUnifiedICT = true;         // Enable Unified ICT/SMC Strategy

//--- AI Mode Settings (NEW)
input group "AI Engine Settings"
input bool InpEnableAIMode = true;             // Enable AI Mode
input double InpAIConfidenceThreshold = 0.60;  // AI Confidence Threshold (Increased for better quality)
input double InpAIWeightMultiplier = 1.0;      // AI Weight Multiplier

//--- Enterprise Mode Settings
input group "Enterprise Mode"
input bool InpEnableEnterpriseMode = true;     // Enable Enterprise Mode
input bool InpUseSignalPipeline = true;        // Use Signal Pipeline
input bool InpUseOrchestrator = true;          // Use AI Orchestrator
input double InpMinTrendStrength = 50.0;       // Minimum Trend Strength
input double InpMaxVolatility = 3.0;           // Maximum Volatility %
input bool InpEnableStructureFilter = true;    // Enable Structure Filter
input bool InpEnableLiquidityFilter = true;    // Enable Liquidity Filter

//--- Include files
#include <Object.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include "Interfaces\IStrategy.mqh"
#include "Core\Utils\ErrorHandling.mqh"
#include "Core\Utils\Instruments.mqh"
#include "Core\Risk\RiskValidationGate.mqh"
#include "Core\Risk\PortfolioRiskManager.mqh"
#include "Core\Risk\PositionSizer.mqh"
#include "Core\Monitoring\PerformanceAnalytics.mqh"
#include "Core\Risk\AdaptiveRiskManager.mqh"
#include "Core\AI\AIPerformanceFeedback.mqh"
#include "Core\AI\AIStrategyOrchestrator.mqh"
#include "Core\Trading\TradeManager.mqh"
#include "Core\Engines\MarketAnalysis.mqh"
#include "Core\Connectivity\IntegrationHub.mqh"
#include "Core\Risk\EnhancedRiskManager.mqh"
#include "Core\Strategy\StrategyBase.mqh"
#include "Strategies\SimpleMomentumStrategy.mqh"
#include "Core\Engines\TradingEngine.mqh"
#include "Core\Utils\SymbolContext.mqh"
#include "Core\Strategy\StrategyWrapper.mqh"
#include "IndicatorManager.mqh"
#include "AIModules\NextGenStrategyBrain.mqh"
#include "AIModules\TransformerBrain.mqh"
#include "AIModules\EnsembleMetaLearner.mqh"
#include "Core\Engines\AIEngine.mqh"

// Enterprise Components
#include "Core\Management\EnterpriseStrategyManager.mqh"
#include "Core\Pipeline\UnifiedSignalPipeline.mqh"
#include "Core\Engines\StructureEngine.mqh"
#include "Core\Engines\TrendEngine.mqh"
#include "Core\Engines\LiquidityEngine.mqh"
#include "Core\Engines\VolatilityEngine.mqh"

// Enhanced Strategies
#include "Strategies\StrategyElliottWaveEnhanced.mqh"

// Advanced Signal Validation and Position Management
#include "Core\Signals\AdvancedSignalValidator.mqh"
#include "Core\Trading\AdvancedPositionManager.mqh"

//+------------------------------------------------------------------+
//| Forward declarations
//+------------------------------------------------------------------+
// Classes now included from separate files

//+------------------------------------------------------------------+
//| Momentum strategy for multi-instrument orchestration             |
//+------------------------------------------------------------------+
// CSimpleMomentumStrategy moved to Strategies/SimpleMomentumStrategy.mqh

//+------------------------------------------------------------------+
//| Progressive TP entry wrapper per position                        |
//+------------------------------------------------------------------+
// CTPManagerEntry moved to Core/TPManagerEntry.mqh

// CStrategyWrapper moved to Core/StrategyWrapper.mqh

//+------------------------------------------------------------------+
//| Symbol execution context                                         |
//+------------------------------------------------------------------+
// CSymbolContext moved to Core/SymbolContext.mqh

//--- Global variables
CTrade trade;
CSymbolInfo globalSymbol;
CAccountInfo account;
CEnhancedErrorHandler errorHandler;
CRiskValidationGate riskGate;
CPortfolioRiskManager portfolioRisk;
CPerformanceAnalytics performanceAnalytics;
CAdaptiveRiskManager adaptiveRisk;
CAIPerformanceFeedback aiFeedback;
CAIStrategyOrchestrator aiOrchestrator;
CUtilities utilities;

// CAIIntegrationHub is now included from Core/IntegrationHub.mqh

CNextGenStrategyBrain aiNextGenBrain;
CTransformerBrain transformerBrain;
CEnsembleMetaLearner ensembleLearner;
CMarketAnalysis marketAnalysis;
CAIIntegrationHub integrationHub;
CEnhancedRiskManager enhancedRiskManager;
CInstrumentRegistry instrumentRegistry;

CTradeManager tradeManager;
CPositionSizer positionSizer;

CTradingEngine tradingEngine; // New Trading Engine
CEnterpriseStrategyManager* g_enterpriseManager = NULL; // Enterprise Strategy Manager
CAdvancedSignalValidator* g_signalValidator = NULL; // Advanced Signal Validator
CAdvancedPositionManager* g_positionManager = NULL; // Advanced Position Manager
// g_AIEngine declared in AIEngine.mqh

//--- Performance tracking
// Centralized in CPerformanceAnalytics but kept here for display compatibility
double peakEquity = 0.0;
double initialBalance = 0.0;
double accountBalance = 0.0;
double accountEquity = 0.0;
double currentEquity = 0.0;
double currentDrawdown = 0.0;
double totalProfit = 0.0;
double totalLoss = 0.0;
int totalTrades = 0;
int winningTrades = 0;
int losingTrades = 0;
double maxDrawdown = 0.0;

//--- Missing time variables
datetime currentTime = 0;

//--- Risk management
double currentRiskPerTrade = 0.0;
double dailyRiskUsed = 0.0;
double maxDailyRisk = 0.0;
bool recoveryMode = false;
bool drawdownMode = false;
double g_currentDrawdown = 0.0;
ENUM_MARKET_REGIME g_currentRegime = MARKET_REGIME_UNKNOWN;
double g_correlationMatrix[10][10];
datetime g_lastTradeTime = 0;
int g_totalActivePositions = 0;
string g_activePairs[];
int g_minTimeBetweenTrades = 120;
int g_maxPositionsAllowed = 10;
string g_symbolsToTrade = "";
bool g_beastModeProtection = true;
bool systemInitialized = false;
bool tradingEnabled = false;

// Risk configuration defaults (overridable by configuration modules)
double DefaultStopLossPips = 20.0;
double DefaultTakeProfitPips = 40.0;
double MaxRiskPerTrade = 2.0;
double AccountRiskMax = 10.0;
double DrawdownReduceThreshold = 5.0;
double CorrelationThreshold = 0.7;

double InputToPercent(const double value)
{
    return (value > 1.0 ? value / 100.0 : value);
}

bool IsNullOrEmpty(const string &text)
{
    return (text == NULL || text == "");
}

//--- Market state tracking
ENUM_MARKET_REGIME currentRegime = MARKET_REGIME_UNKNOWN;
double currentVolatility = 0.0;
double currentATR = 0.0;
double regimeStrength = 0.0;
double momentumScore = 0.0;
double volumeRatio = 0.0;
bool newsEventActive = false;

//--- AI telemetry
int aiSignalCounter = 0;
datetime lastSignalTime = 0;
double aiSuccessRate = 0.0;

//--- Time management
datetime startTime = 0;
datetime lastTickTime = 0;
int tickCounter = 0;
int barCounter = 0;
bool isNewBar = false;

//+------------------------------------------------------------------+
//| Helper: Initialize AI systems                                    |
//+------------------------------------------------------------------+
bool InitializeAISystems()
{
    Print("[MULTI-STRATEGY-EA] Initializing AI systems");

    if(!aiNextGenBrain.Initialize(Symbol(), Period()))
    {
        Print("[MULTI-STRATEGY-EA] Failed to initialize NextGen AI brain");
        return false;
    }

    if(!transformerBrain.Initialize())
    {
        Print("[MULTI-STRATEGY-EA] Failed to initialize transformer brain");
        return false;
    }

    if(!ensembleLearner.Initialize())
    {
        Print("[MULTI-STRATEGY-EA] Failed to initialize ensemble learner");
        return false;
    }

    if(!integrationHub.Initialize(_Symbol, PERIOD_CURRENT))
    {
        Print("[MULTI-STRATEGY-EA] Failed to initialize AI integration hub");
        return false;
    }

    Print("[MULTI-STRATEGY-EA] AI systems initialized successfully");
    return true;
}

void DeinitializeAISystems()
{
    Print("[MULTI-STRATEGY-EA] Deinitializing AI systems");
    aiNextGenBrain.Shutdown();
    transformerBrain.Shutdown();
    ensembleLearner.Shutdown();
    integrationHub.Deinit();
    Print("[MULTI-STRATEGY-EA] AI systems deinitialized");
}

//+------------------------------------------------------------------+
//| Get Symbol Context Wrapper                                       |
//+------------------------------------------------------------------+
CSymbolContext* GetSymbolContext(string symbol)
{
    return tradingEngine.GetSymbolContext(symbol);
}

//+------------------------------------------------------------------+
//| Update performance tracking                                      |
//+------------------------------------------------------------------+
void UpdatePerformanceTracking()
{
    // Delegate to centralized analytics
    performanceAnalytics.UpdateRealTimeMetrics();
}

//+------------------------------------------------------------------+
//| Save performance data                                            |
//+------------------------------------------------------------------+
void SavePerformanceData()
{
    performanceAnalytics.SaveReportToCSV("MultiStrategyEA_Performance.csv");
}

//+------------------------------------------------------------------+
//| Check if new bar                                                 |
//+------------------------------------------------------------------+
bool IsNewBar(const string symbolParam, const ENUM_TIMEFRAMES timeframe)
{
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(symbolParam, timeframe, 0);

    if(currentBarTime != lastBarTime)
    {
        lastBarTime = currentBarTime;
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Get last error message                                           |
//+------------------------------------------------------------------+
string GetLastErrorMessage()
{
    int errorCode = GetLastError();
    return IntegerToString(errorCode);
}

//+------------------------------------------------------------------+
//| Helper: Get Processed Symbol Count                               |
//+------------------------------------------------------------------+
int g_processedSymbolCount = 0;
int GetProcessedSymbolCount() { return g_processedSymbolCount; }

//+------------------------------------------------------------------+
//| Helper: Count EA Positions (by magic number)                     |
//+------------------------------------------------------------------+
int GetEAPositionCount()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            // Check if position belongs to this EA (by magic number)
            if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
                count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| Robust Symbol Iteration                                          |
//+------------------------------------------------------------------+
void ProcessAllSymbols() {
    string symbols[];
    StringSplit(InpSymbolsToTrade, ',', symbols);
    g_processedSymbolCount = 0;

    for(int i = 0; i < ArraySize(symbols); i++) {
        string currentSymbol = symbols[i];
        StringTrimLeft(currentSymbol);
        StringTrimRight(currentSymbol);

        if(currentSymbol == "") continue;

        // Skip if symbol not available
        if(!SymbolInfoInteger(currentSymbol, SYMBOL_TRADE_MODE)) {
            // Print("[SKIP] Symbol not available: ", currentSymbol);
            continue; // CRITICAL: Continue to next symbol
        }

        CSymbolContext* ctx = tradingEngine.GetSymbolContext(currentSymbol);
        if(ctx == NULL) {
            // Print("[WARNING] Context missing for: ", currentSymbol);
            continue;
        }

        // Process symbol with error isolation
        tradingEngine.ProcessSymbol(ctx);
        g_processedSymbolCount++;
    }
}

//+------------------------------------------------------------------+
//| Expert Advisor Initialization                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("[MULTI-STRATEGY-EA] ========================================");
    Print("[MULTI-STRATEGY-EA] Advanced AI Trading System v2.0 Starting");
    Print("[MULTI-STRATEGY-EA] ========================================");

    // Validate MetaTrader 5 environment
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
    {
        Alert("[CRITICAL] Trading is not allowed in the terminal! Enable AutoTrading!");
        return INIT_FAILED;
    }

    if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
    {
        Alert("[CRITICAL] Trading is not allowed for this EA! Check EA properties!");
        return INIT_FAILED;
    }

    // Initialize trade object with proper settings
    trade.SetExpertMagicNumber(InpMagicNumber);
    trade.SetMarginMode();
    trade.SetTypeFillingBySymbol(Symbol());
    trade.SetDeviationInPoints(10);
    trade.SetAsyncMode(false); // Synchronous mode for reliability

    // Validate account type and permissions
    ENUM_ACCOUNT_TRADE_MODE tradeMode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
    if(tradeMode == ACCOUNT_TRADE_MODE_DEMO)
        Print("[INFO] Running on DEMO account");
    else if(tradeMode == ACCOUNT_TRADE_MODE_REAL)
        Print("[WARNING] Running on REAL account - Trade carefully!");
    else if(tradeMode == ACCOUNT_TRADE_MODE_CONTEST)
        Print("[INFO] Running on CONTEST account");

    // Display account information
    Print("[ACCOUNT] Broker: ", AccountInfoString(ACCOUNT_COMPANY));
    Print("[ACCOUNT] Account: ", AccountInfoInteger(ACCOUNT_LOGIN));
    Print("[ACCOUNT] Currency: ", AccountInfoString(ACCOUNT_CURRENCY));
    Print("[ACCOUNT] Leverage: 1:", AccountInfoInteger(ACCOUNT_LEVERAGE));
    Print("[ACCOUNT] Balance: ", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
    Print("[ACCOUNT] Equity: ", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
    Print("[ACCOUNT] Free Margin: ", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2));

    // Initialize AI components first
    Print("[AI] Initializing AI subsystems...");

    if(!aiNextGenBrain.Initialize(Symbol(), Period()))
    {
        Print("[ERROR] Failed to initialize NextGen AI Brain");
        return INIT_FAILED;
    }

    if(!transformerBrain.Initialize())
    {
        Print("[ERROR] Failed to initialize Transformer Brain");
        return INIT_FAILED;
    }

    if(!ensembleLearner.Initialize())
    {
        Print("[ERROR] Failed to initialize Ensemble Learner");
        return INIT_FAILED;
    }

    // Initialize AI Integration Hub for main symbol
    if(!integrationHub.Initialize(Symbol(), Period()))
    {
        Print("[ERROR] Failed to initialize AI Integration Hub");
        return INIT_FAILED;
    }

    Print("[AI] All AI subsystems initialized successfully");

    // Initialize AIEngine with orchestrator
    if(g_AIEngine == NULL)
        g_AIEngine = new CAIEngine();

    SAIAdaptiveConfig aiConfig;
    aiConfig.enabled = true;
    aiConfig.learningRate = 0.1;
    aiConfig.adaptationInterval = 5;
    aiConfig.minConfidenceThreshold = 0.6;

    if(g_AIEngine != NULL)
    {
        if(!g_AIEngine.Initialize(&aiOrchestrator, aiConfig))
        {
            Print("[WARNING] Failed to initialize AIEngine - continuing without AI hooks");
        }
        else
        {
            Print("[AI] AIEngine initialized with adaptive mode");
        }
    }

    // Initialize Enterprise Strategy Manager if enabled
    if(InpEnableEnterpriseMode)
    {
        Print("[ENTERPRISE] Initializing Enterprise Strategy Manager...");

        g_enterpriseManager = new CEnterpriseStrategyManager();
        if(g_enterpriseManager != NULL)
        {
            // Initialize manager with CRITICAL components
            g_enterpriseManager.Initialize(Symbol(), Period(), InpUseOrchestrator, InpUseSignalPipeline,
                                          &tradeManager, &positionSizer);

            // Configure pipeline filters
            if(InpUseSignalPipeline)
            {
                SignalFilterSettings filters;
                filters.enableTrendFilter = true;
                filters.enableVolatilityFilter = true;
                filters.enableLiquidityFilter = InpEnableLiquidityFilter;
                filters.enableStructureFilter = InpEnableStructureFilter;
                filters.minConfidence = InpAIConfidenceThreshold;
                filters.maxVolatility = InpMaxVolatility;
                filters.minTrendStrength = (int)InpMinTrendStrength;
                g_enterpriseManager.SetPipelineFilters(filters);
            }

            // Auto-register strategies (FVG and SupplyDemand removed - covered by SMC)
            bool strategyFlags[];
            ArrayResize(strategyFlags, 9);
            strategyFlags[0] = InpEnableSMC;
            strategyFlags[1] = InpEnableElliottWave;
            strategyFlags[2] = InpEnableBreakout;
            strategyFlags[3] = InpEnableSwing;
            strategyFlags[4] = InpEnableTrend;
            strategyFlags[5] = InpEnableRSI;
            strategyFlags[6] = InpEnableMACD;
            strategyFlags[7] = InpEnableSupportResistance;
            strategyFlags[8] = InpEnableUnifiedICT;

            g_enterpriseManager.AutoRegisterStrategies(strategyFlags);

            Print("[ENTERPRISE] Manager initialized with ", g_enterpriseManager.GetActiveStrategyCount(), " active strategies");

            // Initialize Advanced Signal Validator
            g_signalValidator = new CAdvancedSignalValidator();
            if(g_signalValidator != NULL)
            {
                // Configure validator for profitability
                g_signalValidator.SetMinConfluence(1);  // Allow single strategy signals
                g_signalValidator.SetMinQualityScore(0.55);  // Match confidence threshold
                g_signalValidator.SetMaxSpreadMultiplier(2.0);  // Max spread = 2x ATR
                g_signalValidator.EnableTimeFilter(true, 1, 22);  // Trade 1 AM - 10 PM GMT
                g_signalValidator.EnableSessionFilter(true, true, true, true);  // All sessions
                g_signalValidator.EnableVolatilityFilter(true, 0.0, 5.0);  // Max 5% volatility
                g_signalValidator.EnableSpreadFilter(true, 2.0);
                Print("[SIGNAL-VALIDATOR] Advanced signal validation enabled");
            }

            // Initialize Advanced Position Manager
            g_positionManager = new CAdvancedPositionManager();
            if(g_positionManager != NULL)
            {
                SPositionManagementConfig posConfig;
                posConfig.enableTrailingStop = true;
                posConfig.trailingStartPips = 20.0;
                posConfig.trailingStepPips = 5.0;
                posConfig.trailingDistancePips = 15.0;
                posConfig.enableBreakeven = true;
                posConfig.breakevenTriggerPips = 15.0;
                posConfig.breakevenBufferPips = 5.0;
                posConfig.enablePartialClose = true;
                posConfig.partialClose1Pips = 30.0;
                posConfig.partialClose1Percent = 50.0;  // Close 50% at 30 pips
                posConfig.partialClose2Pips = 60.0;
                posConfig.partialClose2Percent = 25.0;  // Close 25% more at 60 pips
                posConfig.enableTimeBasedExit = false;
                posConfig.maxPositionHours = 24;

                g_positionManager.SetConfig(posConfig);
                g_positionManager.SetTradeManager(&tradeManager);
                Print("[POSITION-MANAGER] Advanced position management enabled");
            }
        }
        else
        {
            Print("[ERROR] Failed to create Enterprise Strategy Manager");
        }
    }

    // Validate and process trading symbols
    string symbols[];
    StringSplit(InpSymbolsToTrade, ',', symbols);
    Print("[SYMBOLS] Processing ", ArraySize(symbols), " trading symbols");

    // Clear and populate active pairs array
    ArrayResize(g_activePairs, 0);

    for(int i = 0; i < ArraySize(symbols); i++)
    {
        string sym = symbols[i];
        StringTrimLeft(sym);
        StringTrimRight(sym);

        // Validate symbol exists
        if(!SymbolSelect(sym, true))
        {
            Print("[WARNING] Symbol ", sym, " not available - skipping");
            continue;
        }

        // Check if symbol is tradeable
        long symbolTradeMode = SymbolInfoInteger(sym, SYMBOL_TRADE_MODE);
        if(symbolTradeMode == SYMBOL_TRADE_MODE_DISABLED)
        {
            Print("[WARNING] Symbol ", sym, " trading is disabled - skipping");
            continue;
        }

        // Add to active pairs array
        int size = ArraySize(g_activePairs);
        ArrayResize(g_activePairs, size + 1);
        g_activePairs[size] = sym;

        // Display symbol specifications
        Print("[SYMBOL] ", sym, " - Configured for trading");
        Print("  - Spread: ", SymbolInfoInteger(sym, SYMBOL_SPREAD), " points");
        Print("  - Min Lot: ", SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN));
        Print("  - Max Lot: ", SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX));
        Print("  - Lot Step: ", SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP));
        Print("  - Contract Size: ", SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE));
    }

    Print("[SYMBOLS] ", ArraySize(g_activePairs), " symbols validated and ready for trading");
    g_symbolsToTrade = InpSymbolsToTrade;

    // AI Mode configuration already applied via AIEngine initialization above
    if(InpEnableAIMode)
    {
        Print("[AI-MODE] AI Mode enabled with threshold: ", InpAIConfidenceThreshold);
    }

    // Initialize Trading Engine
    if(!tradingEngine.Initialize(&tradeManager, &positionSizer, &aiOrchestrator, &instrumentRegistry,
                                &integrationHub, &aiNextGenBrain, &transformerBrain,
                                &ensembleLearner, &performanceAnalytics))
    {
        Print("[ERROR] Failed to initialize Trading Engine");
        return INIT_FAILED;
    }

    systemInitialized = true;
    tradingEnabled = true;
    EventSetTimer(1);
    Print("[MULTI-STRATEGY-EA] Initialization complete - EA is READY;");
    Print("[MULTI-STRATEGY-EA] ========================================");

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Advisor Deinitialization                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    systemInitialized = false;
    tradingEnabled = false;

    // Kill the timer
    EventKillTimer();

    // Clear chart
    Comment("");

    Print("[MULTI-STRATEGY-EA] ========================================");
    Print("[MULTI-STRATEGY-EA] Shutdown complete");
    Print("[MULTI-STRATEGY-EA] ========================================");
}

//+------------------------------------------------------------------+
//| Get deinitialization reason text                                 |
//+------------------------------------------------------------------+
string GetDeInitReasonText(int reasonCode)
{
    switch(reasonCode)
    {
        case REASON_PROGRAM: return "EA terminated";
        case REASON_REMOVE: return "EA removed from chart";
        case REASON_RECOMPILE: return "EA recompiled";
        case REASON_CHARTCHANGE: return "Symbol or period changed";
        case REASON_CHARTCLOSE: return "Chart closed";
        case REASON_PARAMETERS: return "Input parameters changed";
        case REASON_ACCOUNT: return "Account changed";
        case REASON_TEMPLATE: return "New template applied";
        case REASON_INITFAILED: return "Initialization failed";
        case REASON_CLOSE: return "Terminal closed";
        default: return "Unknown reason";
    }
}

//+------------------------------------------------------------------+
//| Timer Handler - Processes trades when chart symbol is closed     |
//+------------------------------------------------------------------+
void OnTimer()
{
    // Process trading logic via timer (runs every 1 second)
    // This ensures EA runs even when chart symbol (e.g., XAUUSD) is closed
    ProcessTradingLogic(true);  // true = called from timer
}

//+------------------------------------------------------------------+
//| Expert Advisor Tick Handler                                      |
//+------------------------------------------------------------------+
void OnTick()
{
    // Process trading logic via tick
    ProcessTradingLogic(false);  // false = called from tick
}

//+------------------------------------------------------------------+
//| Main Trading Logic - Called from both OnTick and OnTimer         |
//+------------------------------------------------------------------+
void ProcessTradingLogic(bool fromTimer)
{
    // First tick/timer detection
    static bool firstCall = true;
    static int callCount = 0;
    callCount++;

    if(firstCall)
    {
        PrintFormat("[DEBUG-PROCESS] First call received! System initialized: %s, Trading enabled: %s, Source: %s",
                   systemInitialized ? "YES" : "NO",
                   tradingEnabled ? "YES" : "NO",
                   fromTimer ? "TIMER" : "TICK");
        firstCall = false;
    }

    // Enhanced logging every 50 calls to show pipeline activity
    if(callCount % 50 == 0)
    {
        PrintFormat("[DEBUG-PROCESS] Call #%d - EA is processing normally (Source: %s)", callCount, fromTimer ? "TIMER" : "TICK");
        Print("[DEBUG-PROCESS] Call #", callCount, " Time: ", TimeCurrent());
        Print("[DEBUG-STATUS] Current symbol: ", _Symbol, " Symbols processed: ", GetProcessedSymbolCount());

        // Show Enterprise Manager status
        if(InpEnableEnterpriseMode && g_enterpriseManager != NULL)
        {
            int activeStrats = g_enterpriseManager.GetActiveStrategyCount();
            int eaPositions = GetEAPositionCount();  // Count only THIS EA's positions
            int cooldownSecs = g_lastTradeTime > 0 ? (int)(TimeCurrent() - g_lastTradeTime) : 0;
            Print("[ENTERPRISE-STATUS] Active strategies: ", activeStrats, " | Cooldown: ",
                  cooldownSecs, "s / ", InpMinSecondsBetweenTrades, "s");
            Print("[ENTERPRISE-STATUS] EA Positions: ", eaPositions, " / ", InpMaxPositionsTotal,
                  " | Account Total: ", PositionsTotal(),
                  " | Last trade: ", g_lastTradeTime > 0 ? TimeToString(g_lastTradeTime) : "Never");
        }
    }

    if(!systemInitialized || !tradingEnabled)
    {
        PrintFormat("[DEBUG-PROCESS] EA blocked: System initialized: %s, Trading enabled: %s",
                   systemInitialized ? "YES" : "NO",
                   tradingEnabled ? "YES" : "NO");
        return;
    }

    // Check if trading is still allowed
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
    {
        Print("[DEBUG-PROCESS] Trading permissions check failed!");
        Comment("Trading is DISABLED - Waiting for permissions...");
        return;
    }

    currentTime = TimeCurrent();

    // Check and reset daily risk limits at midnight
    if(InpUseEnhancedRisk)
    {
        enhancedRiskManager.CheckAndResetDailyLimits();
    }

    currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    accountEquity = currentEquity;

    // Update peak equity and drawdown
    if(currentEquity > peakEquity)
        peakEquity = currentEquity;

    if(peakEquity > 0)
        currentDrawdown = (peakEquity - currentEquity) / peakEquity;

    // CRITICAL FIX: New bar detection for zone scanning and chart drawings
    static datetime lastBarTimeLocal = 0;
    datetime currentBarTime = iTime(_Symbol, (ENUM_TIMEFRAMES)Period(), 0);
    bool newBarDetected = (currentBarTime != lastBarTimeLocal);

    if(newBarDetected)
    {
        lastBarTimeLocal = currentBarTime;

        // Call OnNewBar on EnterpriseManager to trigger strategy zone scanning and drawings
        if(InpEnableEnterpriseMode && g_enterpriseManager != NULL)
        {
            // Process OnNewBar for chart symbol
            g_enterpriseManager.OnNewBar(_Symbol, (ENUM_TIMEFRAMES)Period());

            // Also process for all active trading pairs
            for(int pairIdx = 0; pairIdx < ArraySize(g_activePairs); pairIdx++)
            {
                if(g_activePairs[pairIdx] != _Symbol)
                {
                    g_enterpriseManager.OnNewBar(g_activePairs[pairIdx], (ENUM_TIMEFRAMES)Period());
                }
            }

            if(callCount % 100 == 0)
                Print("[DRAWINGS] OnNewBar processed for ", ArraySize(g_activePairs), " symbols");
        }
    }

    // Enterprise Mode Multi-Symbol Signal Generation
    if(InpEnableEnterpriseMode && g_enterpriseManager != NULL)
    {
        // Check cooldown to prevent chain trading
        datetime tickTime = TimeCurrent();
        int secondsSinceLastTrade = (int)(tickTime - g_lastTradeTime);

        if(secondsSinceLastTrade < InpMinSecondsBetweenTrades && g_lastTradeTime > 0)
        {
            // Cooldown active - skip trading this tick
            return;
        }

        // Check position limit - count only THIS EA's positions by magic number
        int eaPositions = GetEAPositionCount();
        if(eaPositions >= InpMaxPositionsTotal)
        {
            if(callCount % 100 == 0)  // Log occasionally to avoid spam
                Print("[ENTERPRISE-BLOCKED] Position limit reached: ", eaPositions, " / ", InpMaxPositionsTotal);
            return;
        }

        // Loop through all configured trading symbols
        for(int symIdx = 0; symIdx < ArraySize(g_activePairs); symIdx++)
        {
            string currentSymbol = g_activePairs[symIdx];

            // Get signal with confluence tracking (per-symbol analysis)
            double confidence = 0;
            int confluence = 0;
            ENUM_TRADE_SIGNAL enterpriseSignal = g_enterpriseManager.GetConsensusSignalForSymbolWithConfluence(
                currentSymbol, confidence, confluence);

            // Advanced signal validation
            bool signalApproved = false;
            if(enterpriseSignal != TRADE_SIGNAL_NONE && g_signalValidator != NULL)
            {
                // Get ATR for validation
                CIndicatorManager* indManager = CIndicatorManager::Instance();
                int atrHandle = INVALID_HANDLE;
                double atrValue = 0.0;
                if(indManager != NULL)
                {
                    atrHandle = indManager.GetATRHandle(currentSymbol, (ENUM_TIMEFRAMES)Period(), 14);
                    double atr[];
                    ArraySetAsSeries(atr, true);
                    if(atrHandle != INVALID_HANDLE && CopyBuffer(atrHandle, 0, 0, 1, atr) > 0)
                        atrValue = atr[0];
                }

                // Validate signal
                SSignalValidationResult validation = g_signalValidator.ValidateSignal(
                    currentSymbol, enterpriseSignal, confidence, confluence, atrValue);

                if(!validation.isValid)
                {
                    // IMPROVED: Always log rejections for debugging (was only every 50 calls)
                    Print("[SIGNAL-REJECTED] ", currentSymbol, " | Reason: ", validation.reason,
                          " | Confluence: ", confluence, " | Quality: ", DoubleToString(validation.qualityScore, 2),
                          " | Conf: ", DoubleToString(confidence, 2));
                    continue;  // Skip this signal
                }

                // Signal passed validation - proceed with trade
                string signalType = (enterpriseSignal == TRADE_SIGNAL_BUY) ? "BUY" : "SELL";
                Print("[SIGNAL-VALIDATED] ", currentSymbol, " | Signal: ", signalType,
                      " | Confidence: ", confidence, " | Confluence: ", confluence,
                      " | Quality: ", validation.qualityScore);

                // Use validated confidence
                confidence = validation.qualityScore;  // Use quality score as final confidence
                signalApproved = true;
            }
            else if(enterpriseSignal != TRADE_SIGNAL_NONE && confidence >= InpAIConfidenceThreshold)
            {
                // Fallback if validator not initialized
                string signalType = (enterpriseSignal == TRADE_SIGNAL_BUY) ? "BUY" : "SELL";
                Print("[ENTERPRISE] ", currentSymbol, " | Signal: ", signalType, " | Confidence: ", confidence, " | Confluence: ", confluence);
                signalApproved = true;
            }

            // Execute trade if signal was approved
            if(signalApproved && enterpriseSignal != TRADE_SIGNAL_NONE)
            {
                // Execute trade if risk checks pass
                ENUM_ORDER_TYPE orderType = (enterpriseSignal == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
                string signalType = (enterpriseSignal == TRADE_SIGNAL_BUY) ? "BUY" : "SELL";

                // Get current price
                double entryPrice = (enterpriseSignal == TRADE_SIGNAL_BUY) ?
                                   SymbolInfoDouble(currentSymbol, SYMBOL_ASK) :
                                   SymbolInfoDouble(currentSymbol, SYMBOL_BID);

                // Calculate ATR for adaptive SL/TP using IndicatorManager
                CIndicatorManager* indManager = CIndicatorManager::Instance();
                int atrHandle = INVALID_HANDLE;
                if(indManager != NULL)
                    atrHandle = indManager.GetATRHandle(currentSymbol, (ENUM_TIMEFRAMES)Period(), 14);

                double atr[];
                ArraySetAsSeries(atr, true);
                if(atrHandle != INVALID_HANDLE && CopyBuffer(atrHandle, 0, 0, 1, atr) > 0)
                {
                    // Use ATR-based SL/TP calculation (adaptive)
                    double atrValue = atr[0];
                    double pointValue = SymbolInfoDouble(currentSymbol, SYMBOL_POINT);

                    // Check if this is a synthetic index (different pip calculation)
                    bool isSynthetic = (StringFind(currentSymbol, "Volatility") >= 0 ||
                                       StringFind(currentSymbol, "Boom") >= 0 ||
                                       StringFind(currentSymbol, "Crash") >= 0 ||
                                       StringFind(currentSymbol, "Step") >= 0);

                    double stopLossPips = 0;
                    if(isSynthetic)
                    {
                        // For synthetics: ATR is already in price units, convert carefully
                        // Use 1.5x ATR as SL, but convert to pips properly
                        stopLossPips = (atrValue * 1.5) / pointValue;
                    }
                    else
                    {
                        // For regular pairs: standard calculation
                        stopLossPips = (atrValue / pointValue) * 2.0;
                    }

                    double takeProfitPips = stopLossPips * 2.0;  // 2:1 RR ratio

                    // Clamp SL/TP to reasonable bounds based on price percentage
                    // Min SL: 0.5% of price, Max SL: 3.0% of price (tighter for safety)
                    double minSlPips = (entryPrice * 0.005) / pointValue;
                    double maxSlPips = (entryPrice * 0.03) / pointValue;

                    stopLossPips = MathMax(minSlPips, MathMin(maxSlPips, stopLossPips));
                    takeProfitPips = MathMin(stopLossPips * 2.0, maxSlPips * 2.0);

                    double proposedRisk = InpMaxRiskPerTrade; // Pass decimal (0.02), not dollar amount

                    if(enhancedRiskManager.IsTradeAllowed(proposedRisk, orderType, tickTime))
                    {
                        // Calculate optimal lot size
                        double lotSize = positionSizer.CalculateOptimalPositionSize(currentSymbol, orderType, stopLossPips, confidence);

                        // Validate the lot size
                        if(lotSize > 0)
                        {
                            // Calculate SL/TP prices
                            double slPrice = tradeManager.CalculateStopLoss(currentSymbol, orderType, entryPrice, stopLossPips);
                            double tpPrice = tradeManager.CalculateTakeProfit(currentSymbol, orderType, entryPrice, takeProfitPips);

                            // Execute trade with SL/TP protection
                            bool tradeSuccess = false;

                            if(enterpriseSignal == TRADE_SIGNAL_BUY)
                            {
                                tradeSuccess = trade.Buy(lotSize, currentSymbol, 0, slPrice, tpPrice, "Enterprise AI Signal");
                            }
                            else if(enterpriseSignal == TRADE_SIGNAL_SELL)
                            {
                                tradeSuccess = trade.Sell(lotSize, currentSymbol, 0, slPrice, tpPrice, "Enterprise AI Signal");
                            }

                            // Check trade result
                            if(!tradeSuccess)
                            {
                                int errorCode = GetLastError();
                                Print("[TRADE-ERROR] Failed to execute ", signalType, " order on ", currentSymbol,
                                      " | Lot Size: ", lotSize, " | Error Code: ", errorCode);
                                Print("[TRADE-ERROR] ResultRetcode: ", trade.ResultRetcode(),
                                      " | ResultRetcodeDescription: ", trade.ResultRetcodeDescription());
                            }
                            else
                            {
                                ulong ticket = trade.ResultOrder();

                                // Update last trade time for cooldown
                                g_lastTradeTime = tickTime;

                                Print("[TRADE-SUCCESS] ", signalType, " order executed on ", currentSymbol,
                                      " | Lot Size: ", lotSize,
                                      " | SL: ", slPrice, " (", (int)stopLossPips, " pips)",
                                      " | TP: ", tpPrice, " (", (int)takeProfitPips, " pips)",
                                      " | Ticket: ", ticket);

                                // Stop after first successful trade to enforce cooldown
                                return;
                            }
                        }
                        else
                        {
                            Print("[AI-GLOBAL] Invalid lot size calculated for ", currentSymbol, " - trade skipped");
                        }
                    }
                }
                IndicatorRelease(atrHandle);
            }
        }
    }

    // Advanced Position Management (trailing stops, break-even, partial closes)
    if(g_positionManager != NULL && PositionsTotal() > 0)
    {
        g_positionManager.ManageAllPositions();
    }

    // Emergency stop on excessive drawdown
    if(currentDrawdown > InpMaxDrawdown)
    {
        tradingEnabled = false;
        Alert("[EMERGENCY] Maximum drawdown exceeded! Trading halted!");
        Comment("EMERGENCY STOP - Drawdown: ", NormalizeDouble(currentDrawdown * 100, 2), "%");

        // Close all positions
        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            if(PositionGetTicket(i) > 0)
            {
                if(PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
                {
                    tradeManager.ClosePosition(PositionGetTicket(i), "Emergency Stop");
                }
            }
        }
        return;
    }

    // Collect market data for AI analysis
    double globalMarketData[20];
    globalMarketData[0] = currentEquity;
    globalMarketData[1] = accountBalance;
    globalMarketData[2] = currentDrawdown;
    globalMarketData[3] = (double)PositionsTotal();
    globalMarketData[4] = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    globalMarketData[5] = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
    globalMarketData[6] = dailyRiskUsed;
    globalMarketData[7] = totalProfit;
    globalMarketData[8] = totalLoss;
    globalMarketData[9] = (double)winningTrades;
    globalMarketData[10] = (double)losingTrades;
    globalMarketData[11] = maxDrawdown;
    globalMarketData[12] = 1.0;  // recoveryMultiplier removed
    globalMarketData[13] = (double)totalTrades;

    // Get global AI market assessment
    string aiReasoning = "";
    double globalAIPrediction = integrationHub.GetAIPrediction(globalMarketData, 14, aiReasoning);

    // Adjust trading aggressiveness based on AI
    // Note: If AI is disabled, GetAIPrediction returns 0.0 - treat this as neutral
    if(globalAIPrediction > 0.7)
    {
        currentRiskPerTrade = InpMaxRiskPerTrade * 1.2; // Increase risk in favorable conditions
        Print("[AI-GLOBAL] Market conditions favorable - Risk increased to ", NormalizeDouble(currentRiskPerTrade * 100, 2), "%");
    }
    else if(globalAIPrediction > 0.0 && globalAIPrediction < 0.3)
    {
        // Only reduce risk if AI is active AND predicting unfavorable conditions
        // If AI returns 0.0 (disabled), skip this and use default risk
        currentRiskPerTrade = InpMaxRiskPerTrade * 0.5; // Reduce risk in unfavorable conditions
        Print("[AI-GLOBAL] Market conditions unfavorable - Risk reduced to ", NormalizeDouble(currentRiskPerTrade * 100, 2), "%");
    }
    else
    {
        // Use default risk for neutral conditions or when AI is disabled (0.0)
        currentRiskPerTrade = InpMaxRiskPerTrade;
        if(globalAIPrediction == 0.0)
        {
            // Only log once that AI is disabled to avoid spam
            static bool aiDisabledWarningShown = false;
            if(!aiDisabledWarningShown)
            {
                Print("[AI-GLOBAL] AI systems disabled - Using default risk parameters");
                aiDisabledWarningShown = true;
            }
        }
    }

    // Process trading logic
    ProcessAllSymbols();

    // Manage open positions via Trading Engine
    tradingEngine.ManageOpenPositions();

    // Update performance tracking
    UpdatePerformanceTracking();

    // Prepare AI confidence display (handle NaN, INF, and zero-trade cases)
    string aiConfidenceStr;
    if(MathIsValidNumber(globalAIPrediction) && globalAIPrediction >= 0.0 && globalAIPrediction <= 1.0)
    {
        aiConfidenceStr = StringFormat("%.1f%%", globalAIPrediction * 100);
    }
    else if(winningTrades == 0 && losingTrades == 0)
    {
        aiConfidenceStr = "N/A (No trades yet)";
    }
    else
    {
        aiConfidenceStr = "N/A (Calculating...)";
    }

    // Update chart display
    string status = StringFormat(
        "AI Trading System ACTIVE\n" +
        "Balance: %.2f | Equity: %.2f\n" +
        "Drawdown: %.2f%% | Risk: %.2f%%\n" +
        "Positions: %d | W/L: %d/%d\n" +
        "AI Confidence: %s\n" +
        "Next Update: %s",
        accountBalance,
        currentEquity,
        currentDrawdown * 100,
        currentRiskPerTrade * 100,
        PositionsTotal(),
        winningTrades,
        losingTrades,
        aiConfidenceStr,
        TimeToString(currentTime + 60)
    );

    Comment(status);
}