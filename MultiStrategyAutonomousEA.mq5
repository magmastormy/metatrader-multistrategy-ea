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
input bool InpUseEnhancedRisk = true;      // Use enhanced risk management
input double InpMaxRiskPerTrade = 2.0;    // Max risk per trade (e.g., 2.0 for 2%)
input double InpMaxDailyRisk = 6.0;       // Max daily risk (e.g., 6.0 for 6%)
input double InpMaxPortfolioRisk = 10.0;   // Max total portfolio risk (e.g., 10.0 for 10%)
input double InpMaxDrawdown = 15.0;       // Max drawdown (e.g., 15.0 for 15%)
input string InpSymbolsToTrade = "Step Index.0,Jump 10 Index.0,AUXUSD.0,EURUSD.0";               // Comprehensive test symbols
input int    InpMinSecondsBetweenTrades = 120;    // Cooldown in seconds between trades
input int    InpMaxPositionsTotal = 15;           // Global position limit

//--- Strategy Selection (for testing)
input group "Strategy Selection"
input bool InpEnableMomentum = false;        // Enable Momentum Strategy
input bool InpEnableRSI = false;             // Enable RSI Strategy
input bool InpEnableTrend = false;           // Enable Trend Strategy
input bool InpEnableMeanReversion = false;   // Enable Mean Reversion Strategy
input bool InpEnableSwing = false;          // Enable Swing Strategy
input bool InpEnableVolatility = false;     // Enable Volatility Strategy
input bool InpEnableMACD = false;           // Enable MACD Strategy
input bool InpEnableBollinger = false;      // Enable Bollinger Strategy
input bool InpEnableBollingerBreakout = false; // Enable Bollinger Breakout Strategy
input bool InpEnableSMC = false;               // Enable Advanced SMC Strategy
input bool InpEnableBreakout = false;         // Enable Breakout Strategy
input bool InpEnableFibonacci = false;        // Enable Fibonacci Strategy
input bool InpEnableElliottWave = false;       // Enable Elliott Wave Enhanced Strategy
input bool InpEnableIchimoku = false;         // Enable Ichimoku Strategy
input bool InpEnableHarmonicPatterns = false;  // Enable Harmonic Patterns Strategy
input bool InpEnableSupportResistance = false; // Enable Support/Resistance + Trendlines
input bool InpEnableUnifiedICT = false;        // Enable Unified ICT/SMC Strategy
input bool InpEnableCandlestick = false;       // Enable Candlestick Patterns Strategy

//--- AI Mode Settings (NEW)
input group "AI Engine Settings"
input bool InpEnableAIMode = false;            // Enable AI Mode
input bool InpEnableNeuralNetwork = false;     // Enable Neural Network
input bool InpEnableTransformer = false;       // Enable Transformer Brain
input bool InpEnableEnsemble = false;          // Enable Ensemble Learning
input bool InpEnableGeneticOptimizer = false;  // Enable Genetic Optimizer (experimental)
input double InpAIConfidenceThreshold = 0.60;  // AI Confidence Threshold (Increased for better quality)
input double InpAIWeightMultiplier = 1.0;      // AI Weight Multiplier

//--- Enterprise Mode Settings
input group "Enterprise Mode"
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
#include "IndicatorManager.mqh"
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
// DELETED: #include "Core\Connectivity\IntegrationHub.mqh"
#include "Core\Risk\EnhancedRiskManager.mqh"
#include "Core\Strategy\StrategyBase.mqh"
#include "Strategies\SimpleMomentumStrategy.mqh"
// DELETED: #include "Core\Engines\TradingEngine.mqh"
#include "Core\Utils\SymbolContext.mqh"
#include "Core\Strategy\StrategyWrapper.mqh"
// AUDIT FIX: Removed duplicate #include "IndicatorManager.mqh" (already included at line 68)
#include "AIModules\NextGenStrategyBrain.mqh"
#include "AIModules\TransformerBrain.mqh"
#include "AIModules\EnsembleMetaLearner.mqh"
#include "AIModules\NeuralNetworkStrategy.mqh"
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
#include "Strategies\StrategyCandlestick.mqh"

// Advanced AI Modules
// DELETED: #include "AIModules\GeneticOptimizer.mqh"

// Advanced Signal Validation and Position Management
#include "Core\Signals\AdvancedSignalValidator.mqh"
#include "Core\Trading\AdvancedPositionManager.mqh"
#include "Core\Strategy\AIStrategyAdapter.mqh"
#include "Core\Visualization\VisualDashboard.mqh"
#include "Core\Engines\AIEngine.mqh" // Added for AI Adaptation

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
// CAIStrategyOrchestrator aiOrchestrator; // Already declared? Check global scope.
// Using global aiOrchestrator
CAIStrategyOrchestrator aiOrchestrator;
CUtilities utilities;

// CAIIntegrationHub is now included from Core/IntegrationHub.mqh

CNextGenStrategyBrain aiNextGenBrain;
CTransformerBrain transformerBrain;
CEnsembleMetaLearner ensembleLearner;
CNeuralNetworkStrategy* neuralNetStrategy = NULL;
CPositionSizer positionSizer;
CMarketAnalysis marketAnalysis;
// DELETED: CAIIntegrationHub integrationHub;
CEnhancedRiskManager enhancedRiskManager;
CInstrumentRegistry instrumentRegistry;

CTradeManager tradeManager;


// REMOVED: CTradingEngine tradingEngine; // Dead code removal
CEnterpriseStrategyManager* g_enterpriseManager = NULL; // Enterprise Strategy Manager
CAdvancedSignalValidator* g_signalValidator = NULL; // Advanced Signal Validator
CAdvancedPositionManager* g_positionManager = NULL; // Advanced Position Manager
// g_AIEngine declared in AIEngine.mqh
CVisualDashboard g_dashboard;

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
// [DEAD CODE REMOVED] InitializeAISystems and DeinitializeAISystems
// AI initialization strategy moved to OnInit/OnDeinit with proper gating

//+------------------------------------------------------------------+
//| Get Symbol Context Wrapper                                       |
//+------------------------------------------------------------------+
// [REMOVED] GetSymbolContext - Context management moved to CEnterpriseStrategyManager

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
// [REMOVED] GetProcessedSymbolCount helper

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
// [REMOVED] ProcessAllSymbols - Logic consolidated into ProcessTradingLogic and EnterpriseManager

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

    // AUDIT FIX: Gate AI subsystem initialization behind InpEnableAIMode
    if(InpEnableAIMode)
    {
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

        // AI Subsystems initialized
        Print("[AI] All AI subsystems initialized successfully");
    }
    else
    {
        Print("[AI] AI Mode disabled — skipping AI subsystem initialization");
    }

    // Initialize AIEngine with orchestrator
    if(g_AIEngine == NULL)
        g_AIEngine = new CAIEngine();

    SAIAdaptiveConfig aiConfig;
    aiConfig.enabled = true;
    aiConfig.learningRate = 0.1;
    aiConfig.adaptationInterval = 5;
    aiConfig.minConfidenceThreshold = 0.6;

    // Initialize Enhanced Risk Manager
    if(InpUseEnhancedRisk)
    {
        SEnhancedRiskConfig riskConfig;
        riskConfig.enabled = true;
        riskConfig.base_risk_per_trade = InpMaxRiskPerTrade;   // Now 2.0 (percentage)
        riskConfig.max_risk_per_trade = InpMaxRiskPerTrade * 1.5;
        riskConfig.min_risk_per_trade = 0.5;
        riskConfig.max_daily_risk = InpMaxDailyRisk;
        riskConfig.max_weekly_risk = InpMaxDailyRisk * 3.0;
        riskConfig.max_monthly_risk = InpMaxDailyRisk * 10.0;
        riskConfig.max_drawdown_threshold = InpMaxDrawdown;
        riskConfig.recovery_mode_multiplier = 0.5;
        riskConfig.adaptive_risk_adjustment = true;
        riskConfig.volatility_adjustment = true;
        riskConfig.correlation_adjustment = true;
        riskConfig.max_active_positions = InpMaxPositionsTotal;
        
        if(!enhancedRiskManager.Initialize(riskConfig, AccountInfoDouble(ACCOUNT_EQUITY)))
        {
            Print("[ERROR] Failed to initialize Enhanced Risk Manager");
        }
        else
        {
            Print("[INIT] Enhanced Risk Manager initialized — Unit: PERCENTAGE (0-100)");
        }
    }
    
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

    // AUDIT FIX: Initialize PositionSizer BEFORE passing to EnterpriseManager
    SPositionSizingParams sizingParams;
    sizingParams.sizingMode       = POSITION_SIZE_RISK_PERCENT;
    sizingParams.fixedLotSize     = InpLotSize;
    sizingParams.riskPercent      = InpMaxRiskPerTrade;         // Now using consistent 0-100 scale (e.g., 2.0)
    sizingParams.atrPeriod        = 14;
    sizingParams.atrMultiplier    = 1.5;
    sizingParams.maxLotSize       = MAX_LOT_SIZE;
    sizingParams.minLotSize       = MIN_LOT_SIZE;
    sizingParams.correlationAdjustment  = 1.0;
    sizingParams.useVolatilityAdjustment = true;
    sizingParams.useCorrelationAdjustment = false;
    if(!positionSizer.SetParameters(sizingParams))
    {
        Print("[CRITICAL] PositionSizer initialization FAILED — will use min lot fallback!");
    }
    else
    {
        Print("[INIT] PositionSizer initialized — Mode: RISK_PERCENT, Risk: ",
              DoubleToString(sizingParams.riskPercent, 2), "%");
    }

    // Initialize AI Engine for Adaptation
    if(InpEnableAIMode)
    {
        if(g_AIEngine == NULL) g_AIEngine = new CAIEngine();
        
        // Initialize with the GLOBAL orchestrator so they share the same brain
        SAIAdaptiveConfig adaptiveConfig;
        adaptiveConfig.enabled = true;
        adaptiveConfig.learningRate = 0.1;
        adaptiveConfig.adaptationInterval = 1; // Adapt every bar
        adaptiveConfig.minConfidenceThreshold = InpAIConfidenceThreshold;

        if(g_AIEngine.Initialize(&aiOrchestrator, adaptiveConfig))
        {
            Print("[INIT] AI Engine initialized in ADAPTIVE mode");
        }
        else
        {
            Print("[ERROR] Failed to initialize AI Engine");
        }
    }

    // AUDIT FIX: Initialize Risk Gate
    // CRiskValidationGate::Initialize(CPortfolioRiskManager* pPortfolioRiskManager, maxRiskPerTrade, maxPortfolioRisk, correlationThreshold)
    if(!riskGate.Initialize(&portfolioRisk, InpMaxRiskPerTrade, InpMaxPortfolioRisk, 0.7))
    {
        Print("[CRITICAL] RiskValidationGate failed to initialize!");
        return INIT_FAILED;
    }
    Print("[INIT] RiskValidationGate initialized");

    // Initialize Enterprise Strategy Manager (Always Enabled)
    Print("[ENTERPRISE] Initializing Enterprise Strategy Manager...");

    g_enterpriseManager = new CEnterpriseStrategyManager();
    if(g_enterpriseManager != NULL)
    {
        // Initialize manager with CRITICAL components
        // Initialize manager with CRITICAL components and INJECTED Orchestrator
        g_enterpriseManager.Initialize(Symbol(), Period(), InpUseOrchestrator, InpUseSignalPipeline,
                                      &tradeManager, &positionSizer, &aiOrchestrator);

        // Configure pipeline filters

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

        // Auto-register strategies (Complete 18-strategy mapping)
        bool strategyFlags[];
        ArrayResize(strategyFlags, 18);
        strategyFlags[0]  = InpEnableMomentum;
        strategyFlags[1]  = InpEnableRSI;
        strategyFlags[2]  = InpEnableTrend;
        strategyFlags[3]  = InpEnableMeanReversion;
        strategyFlags[4]  = InpEnableSwing;
        strategyFlags[5]  = InpEnableVolatility;
        strategyFlags[6]  = InpEnableMACD;
        strategyFlags[7]  = InpEnableBollinger;
        strategyFlags[8]  = InpEnableBollingerBreakout;
        strategyFlags[9]  = InpEnableSMC;
        strategyFlags[10] = InpEnableBreakout;
        strategyFlags[11] = InpEnableFibonacci;
        strategyFlags[12] = InpEnableElliottWave;
        strategyFlags[13] = InpEnableIchimoku;
        strategyFlags[14] = InpEnableHarmonicPatterns;
        strategyFlags[15] = InpEnableSupportResistance;
        strategyFlags[16] = InpEnableUnifiedICT;
        strategyFlags[17] = InpEnableCandlestick;

        g_enterpriseManager.AutoRegisterStrategies(strategyFlags);

        // AUDIT FIX: NN AI Adapter registration moved to AFTER neuralNetStrategy creation (see line ~680)
        // Previously registered here where neuralNetStrategy was always NULL

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

    // Initialize Neural Network Strategy
    if(InpEnableAIMode && InpEnableNeuralNetwork)
    {
        neuralNetStrategy = new CNeuralNetworkStrategy();
        if(neuralNetStrategy != NULL)
        {
            if(neuralNetStrategy.Initialize(Symbol(), Period()))
            {
                Print("[INIT] Neural Network Strategy initialized successfully");
            }
            else
            {
                Print("[INIT] WARNING: Neural Network Strategy initialization failed");
                delete neuralNetStrategy;
                neuralNetStrategy = NULL;
            }
        }
        Print("[AI-MODE] AI Mode enabled | NN: ", InpEnableNeuralNetwork, " | Transformer: ", InpEnableTransformer, 
              " | Ensemble: ", InpEnableEnsemble, " | Threshold: ", InpAIConfidenceThreshold);

        // AUDIT FIX: Register NN strategy AFTER successful creation (was previously at line ~548 before creation)
        if(neuralNetStrategy != NULL && g_enterpriseManager != NULL)
        {
            Print("[ENTERPRISE] Registering Neural Network AI Adapter (post-init)...");
            double aiWeight = InpAIWeightMultiplier > 0 ? InpAIWeightMultiplier : 3.0;
            g_enterpriseManager.RegisterStrategy(new CAIStrategyAdapter(neuralNetStrategy), "Neural Network AI", true, aiWeight);
        }
    }
    else if(InpEnableAIMode)
    {
        Print("[AI-MODE] AI Mode enabled but Neural Network disabled");
    }

    // Trading Engine Removed - Unified under CTradeManager and CAdvancedPositionManager
    // if(!tradingEngine.Initialize(...)) { ... }

    // Final system initialization
    systemInitialized = true;
    tradingEnabled = true;

    // Initialize Dashboard
    g_dashboard.Initialize();
    
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

    // Properly delete all dynamic objects to prevent memory leaks
    if(g_enterpriseManager != NULL)
    {
        delete g_enterpriseManager;
        g_enterpriseManager = NULL;
    }
    
    if(g_AIEngine != NULL)
    {
        delete g_AIEngine;
        g_AIEngine = NULL;
    }
    
    if(g_signalValidator != NULL)
    {
        delete g_signalValidator;
        g_signalValidator = NULL;
    }
    
    if(g_positionManager != NULL)
    {
        delete g_positionManager;
        g_positionManager = NULL;
    }
    
    if(neuralNetStrategy != NULL)
    {
        delete neuralNetStrategy;
        neuralNetStrategy = NULL;
    }
    
    if(g_AIEngine != NULL)
    {
        delete g_AIEngine;
        g_AIEngine = NULL;
    }

    // Clear chart
    Comment("");

    Print("[MULTI-STRATEGY-EA] ========================================");
    Print("[MULTI-STRATEGY-EA] Shutdown complete - Memory cleaned");
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
        Print("[DEBUG-STATUS] Current symbol: ", _Symbol);

        // Show Enterprise Manager status
        int activeStrats = 0;
        int eaPositions = 0;

        if(g_enterpriseManager != NULL)
        {
            activeStrats = g_enterpriseManager.GetActiveStrategyCount();
            eaPositions = GetEAPositionCount();  // Count only THIS EA's positions
            int cooldownSecs = g_lastTradeTime > 0 ? (int)(TimeCurrent() - g_lastTradeTime) : 0;
            Print("[ENTERPRISE-STATUS] Active strategies: ", activeStrats, " | Cooldown: ",
                  cooldownSecs, "s / ", InpMinSecondsBetweenTrades, "s");
            Print("[ENTERPRISE-STATUS] EA Positions: ", eaPositions, " / ", InpMaxPositionsTotal,
                  " | Account Total: ", PositionsTotal(),
                  " | Last trade: ", g_lastTradeTime > 0 ? TimeToString(g_lastTradeTime) : "Never");
        }
        
        // --- Update Dashboard ---
        g_dashboard.Update(activeStrats, eaPositions, accountBalance, accountEquity, &aiNextGenBrain, neuralNetStrategy);
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
        currentDrawdown = ((peakEquity - currentEquity) / peakEquity) * 100.0; // Standardized to 0-100 scale

    // CRITICAL FIX: New bar detection for zone scanning and chart drawings
    static datetime lastBarTimeLocal = 0;
    datetime currentBarTime = iTime(_Symbol, (ENUM_TIMEFRAMES)Period(), 0);
    bool newBarDetected = (currentBarTime != lastBarTimeLocal);

    if(newBarDetected)
    {
        lastBarTimeLocal = currentBarTime;

        // Call OnNewBar on EnterpriseManager to trigger strategy zone scanning and drawings
        if(g_enterpriseManager != NULL)
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

            // TRIGGER AI ADAPTATION
            if(InpEnableAIMode && g_AIEngine != NULL)
            {
                g_AIEngine.ProcessAdaptation();
                // Print("[AI] Adaptation cycle processed"); // Uncomment for verbose debug
            }

            if(callCount % 100 == 0)
                Print("[DRAWINGS] OnNewBar processed for ", ArraySize(g_activePairs), " symbols");
        }
    }

    // Enterprise Mode Multi-Symbol Signal Generation
    // UNIFIED PIPELINE - All strategies including AI now go through here
    if(g_enterpriseManager != NULL)
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

        // CRITICAL AUDIT FIX: Restrict trading to the current chart symbol ONLY.
        // The previous loop over g_activePairs caused strategies (which are bound to _Symbol)
        // to be evaluated against other symbols, leading to invalid signals (e.g. EURUSD logic applied to GBPUSD).
        // Until strategies are instantiated per-symbol, we must strictly limit execution to _Symbol.
        
        string currentSymbol = _Symbol;
        
        // We simulate a single-iteration loop for the chart symbol to keep the logic structure similar
        // independent of the g_activePairs list for now.
        for(int symIdx = 0; symIdx < 1; symIdx++)
        {
            // string currentSymbol = g_activePairs[symIdx]; // DISABLED


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

                    // AUDIT FIX: Use RiskValidationGate for comprehensive checks
                    STradeValidationRequest tradeReq;
                    tradeReq.symbol = currentSymbol;
                    tradeReq.orderType = orderType;
                    tradeReq.lotSize = 0.0; // Lot size not known yet, validation gate will validate prelim checks
                    tradeReq.stopLossPips = stopLossPips;
                    tradeReq.takeProfitPips = takeProfitPips;
                    tradeReq.confidence = confidence;
                    tradeReq.strategy = "Enterprise AI";
                    tradeReq.reasoning = "Orchestrator consensus signal";
                    
                    // Pre-check risk with 0.01 lot to validate trade parameters first
                    tradeReq.lotSize = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MIN); 
                    
                    SValidationResult riskResult = riskGate.ValidateTradeRequest(tradeReq);
                    
                    if(riskResult.approved && enhancedRiskManager.IsTradeAllowed(proposedRisk, orderType, tickTime))
                    {
                        // Calculate optimal lot size
                        double lotSize = positionSizer.CalculateOptimalPositionSize(currentSymbol, orderType, stopLossPips, confidence);

                        // Update request with actual lot size and re-validate
                        tradeReq.lotSize = lotSize;
                        riskResult = riskGate.ValidateTradeRequest(tradeReq);
                        
                        // Validate the lot size and final risk approval
                        if(lotSize > 0 && riskResult.approved)
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
                                
                                // FIX: Update risk manager usage
                                enhancedRiskManager.AddRiskUsage(proposedRisk);

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
                // FIX: Removed IndicatorRelease(atrHandle) because handles from CIndicatorManager are shared/cached.
                // Releasing them here invalidates the handle for other parts of the EA.
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

    // Collect market data for AI analysis using EnhancedRiskManager stats
    SRiskStats riskStats = enhancedRiskManager.GetRiskStatistics();
    double globalMarketData[20];
    globalMarketData[0] = currentEquity;
    globalMarketData[1] = accountBalance;
    globalMarketData[2] = currentDrawdown;
    globalMarketData[3] = (double)PositionsTotal();
    globalMarketData[4] = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    globalMarketData[5] = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
    globalMarketData[6] = riskStats.current_drawdown;
    globalMarketData[7] = riskStats.total_profit;
    globalMarketData[8] = riskStats.total_loss;
    globalMarketData[9] = (double)riskStats.winning_trades;
    globalMarketData[10] = (double)riskStats.losing_trades;
    globalMarketData[11] = riskStats.max_drawdown;
    globalMarketData[12] = (double)riskStats.win_rate;
    globalMarketData[13] = (double)riskStats.total_trades;

    // AI Market Assessment (Heuristic IntegrationHub removed)
    double globalAIPrediction = 0.0;
    string aiReasoning = "AI Orchestrator Active";

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
//+------------------------------------------------------------------+
//| Trade Transaction Event Handler                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
    // Forward trade events to Enterprise Manager for AI feedback
    if(g_enterpriseManager != NULL)
    {
        g_enterpriseManager.OnTradeTransaction(trans, request, result);
    }
}

