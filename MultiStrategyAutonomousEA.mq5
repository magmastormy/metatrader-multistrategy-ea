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
input bool InpUsePythonAI = false;        // Use Python AI signals
input bool InpUseCppAI = false;           // Use C++ AI signals
input bool InpUseHybridAI = false;         // Use hybrid AI signals
input bool InpUseProgressiveTP = true;     // Use progressive take-profit
input bool InpUseEnhancedRisk = true;      // Use enhanced risk management
input double InpMaxRiskPerTrade = 0.02;   // Max risk per trade (2%)
input double InpMaxDailyRisk = 0.06;       // Max daily risk (6%)
input double InpMaxDrawdown = 0.15;        // Max drawdown (15%)
input bool   InpEnableIntelligentProcess = true; // Enable ProcessIntelligentTrading loop
input string InpSymbolsToTrade = "EURUSD.0,GBPUSD.0,USDJPY.0,XAUUSD.0,BTCUSD.0,AUDNZD.0,NZDUSD.0,Volatility 75 Index.0,Volatility 100 Index.0,Step Index.0"; // Comprehensive test: Forex, Metals, Crypto, Synthetic Indices
input int    InpMinSecondsBetweenTrades = 120;    // Cooldown in seconds between trades
input int    InpMaxPositionsTotal = 10;           // Global position limit for intelligent module

//--- Strategy Selection (for testing)
input group "Strategy Selection"
input bool InpEnableMomentum = true;        // Enable Momentum Strategy
input bool InpEnableRSI = true;             // Enable RSI Strategy
input bool InpEnableTrend = true;           // Enable Trend Strategy
input bool InpEnableMeanReversion = true;   // Enable Mean Reversion Strategy
input bool InpEnableSupplyDemand = false;   // Enable Supply/Demand Strategy
input bool InpEnableSwing = false;          // Enable Swing Strategy
input bool InpEnableVolatility = false;     // Enable Volatility Strategy
input bool InpEnableOrderBlockFVG = false;  // Enable Order Block FVG Strategy
input bool InpEnableStepIndex = false;      // Enable Step Index Strategy
input bool InpEnableMACD = false;           // Enable MACD Strategy
input bool InpEnableOrderBlock = false;     // Enable Order Block Strategy
input bool InpEnableBollinger = false;      // Enable Bollinger Strategy
input bool InpEnableBollingerBreakout = false; // Enable Bollinger Breakout Strategy
input bool InpEnableSMC = true;               // Enable Advanced SMC Strategy
input bool InpEnableBreakout = false;         // Enable Breakout Strategy
input bool InpEnableFibonacci = false;        // Enable Fibonacci Strategy
input bool InpEnableElliottWave = false;      // Enable Elliott Wave Strategy
input bool InpEnableIchimoku = false;         // Enable Ichimoku Strategy
input bool InpEnableFairValueGap = false;     // Enable Fair Value Gap Strategy
input bool InpEnableHarmonicPatterns = false; // Enable Harmonic Patterns Strategy
input bool InpEnableElliott = false;          // Enable Elliott Advanced Strategy

//--- AI Mode Settings (NEW)
input group "AI Engine Settings"
input bool InpEnableAIMode = true;             // Enable AI Mode
input double InpAIConfidenceThreshold = 0.65;  // AI Confidence Threshold
input double InpAIWeightMultiplier = 1.0;      // AI Weight Multiplier

//--- Include files
#include <Object.mqh>
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Arrays\ArrayObj.mqh>
#include <Arrays\ArrayDouble.mqh>
#include "Core\Enums.mqh"
#include "Interfaces\IStrategy.mqh"  // MOVED TO TOP
#include "Core\ErrorHandling.mqh"
#include "Core\Instruments.mqh"
#include "Core\SafetyLayer.mqh"
#include "Core\RiskValidationGate.mqh"
#include "Core\PortfolioRiskManager.mqh"
#include "Core\PositionSizer.mqh"
#include "Core\PerformanceAnalytics.mqh"
#include "Core\AdaptiveRiskManager.mqh"
#include "Core\AIPerformanceFeedback.mqh"
#include "Core\PerformanceBasedStrategyAdapter.mqh"
#include "Core\AIStrategyOrchestrator.mqh"
#include "Core\TradeManager.mqh"
#include "Core\MarketAnalysis.mqh"
#include "Core\IntegrationHub.mqh"
#include "Core\CrashBoomSpikeDetector.mqh"
#include "Core\StepIndexLevelBreaker.mqh"
#include "Core\EnhancedRiskManager.mqh"
#include "Core\ProgressiveTakeProfit.mqh"
#include "Core\StrategyBase.mqh"
#include "Strategies\StrategyStepIndex.mqh"
#include "Strategies\SimpleMomentumStrategy.mqh"
#include "Core\TradingEngine.mqh"
#include "Core\SymbolContext.mqh"
#include "Core\StrategyWrapper.mqh"
#include "Core\TPManagerEntry.mqh"
#include "AIModules\NextGenStrategyBrain.mqh"
#include "AIModules\TransformerBrain.mqh"
#include "AIModules\EnsembleMetaLearner.mqh"
#include "Core\AIEngine.mqh"
#include "MultiStrategySelection.mqh"

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
CSafetyLayer safetyLayer;
CRiskValidationGate riskGate;
CPortfolioRiskManager portfolioRisk;
CPositionSizer positionSizer;
CPerformanceAnalytics performanceAnalytics;
CAdaptiveRiskManager adaptiveRisk;
CAIPerformanceFeedback aiFeedback;
CPerformanceBasedStrategyAdapter strategyAdapter;
CAIStrategyOrchestrator aiOrchestrator;
CStrategyManager strategyManager;
CTradeManager tradeManager;
CUtilities utilities;
    


// CAIIntegrationHub is now included from Core/IntegrationHub.mqh

CNextGenStrategyBrain aiNextGenBrain;
CTransformerBrain transformerBrain;
CEnsembleMetaLearner ensembleLearner;
CMarketAnalysis marketAnalysis;
CAIIntegrationHub integrationHub;
CCrashBoomSpikeDetector spikeDetector;
CStepIndexLevelBreaker* levelBreaker = NULL;  // Needs to be initialized with parameters
CEnhancedRiskManager enhancedRiskManager;
CInstrumentRegistry instrumentRegistry;
CTradingEngine tradingEngine; // New Trading Engine



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

//--- Missing variables for trade management
double currentPrice = 0.0;
double recoveryMultiplier = 1.0;

//--- Take-profit management
bool progressiveTPEnabled = false;
SProgressiveTPConfig tpConfig;
CArrayObj* activeTPManagers = NULL;
int tpManagerCounter = 0;

//--- Time management
datetime startTime = 0;
datetime lastTickTime = 0;
int tickCounter = 0;
int barCounter = 0;
bool isNewBar = false;



// CStrategyWrapper moved to Core/StrategyWrapper.mqh

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
//| Update take-profit management                                    |
//+------------------------------------------------------------------+
void UpdateTakeProfitManagement()
{
    if(activeTPManagers == NULL || (*activeTPManagers).Total() == 0)
        return;

    for(int i = (*activeTPManagers).Total() - 1; i >= 0; --i)
    {
        CTPManagerEntry* entry = (CTPManagerEntry*)(*activeTPManagers).At(i);
        if(entry == NULL)
            continue;

        CSymbolContext* context = GetSymbolContext((*entry).symbol);
        if(context == NULL)
            continue;

        double midPrice = ((*entry).orderType == ORDER_TYPE_BUY ? (*context).lastValidBid : (*context).lastValidAsk);
        if(midPrice <= 0.0)
            midPrice = (*context).lastPrice;

        if((*entry).manager != NULL)
            (*(*entry).manager).Update(midPrice, currentTime, iBarShift((*entry).symbol, PERIOD_CURRENT, currentTime));

        if((*entry).manager != NULL && (*(*entry).manager).CheckTakeProfitLevels(midPrice, currentTime))
        {
            PrintFormat("[MULTI-STRATEGY-EA] Progressive TP levels executed for %s (ticket %I64u)", (*entry).symbol, (*entry).ticket);
        }

        if((*entry).manager != NULL && (*(*entry).manager).GetRemainingPositionRatio() <= 0.01)
        {
            (*activeTPManagers).Delete(i);
            delete entry;
            tpManagerCounter--;
        }
    }
}

//+------------------------------------------------------------------+
//| Update performance tracking                                      |
//+------------------------------------------------------------------+
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
    
    if(!g_AIEngine.Initialize(&aiOrchestrator, aiConfig))
    {
        Print("[WARNING] Failed to initialize AIEngine - continuing without AI hooks");
    }
    else
    {
        Print("[AI] AIEngine initialized with adaptive mode");
    }
    
    // Validate and process trading symbols
    string symbols[];
    StringSplit(InpSymbolsToTrade, ',', symbols);
    Print("[SYMBOLS] Processing ", ArraySize(symbols), " trading symbols");
    
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
        
        // Display symbol specifications
        Print("[SYMBOL] ", sym, " - Configured for trading");
        Print("  - Spread: ", SymbolInfoInteger(sym, SYMBOL_SPREAD), " points");
        Print("  - Min Lot: ", SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN));
        Print("  - Max Lot: ", SymbolInfoDouble(sym, SYMBOL_VOLUME_MAX));
        Print("  - Lot Step: ", SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP));
        Print("  - Contract Size: ", SymbolInfoDouble(sym, SYMBOL_TRADE_CONTRACT_SIZE));
    }

    // Enable AI Mode if configured
    if(InpEnableAIMode)
    {
        EnableAIMode(true, InpAIConfidenceThreshold, InpAIWeightMultiplier);
        Print("[AI-MODE] AI Mode enabled with threshold: ", InpAIConfidenceThreshold);
    }
    
    // Initialize Trading Engine
    if(!tradingEngine.Initialize(&tradeManager, &positionSizer, &aiOrchestrator, &instrumentRegistry, 
                                &spikeDetector, levelBreaker, &integrationHub, 
                                &aiNextGenBrain, &transformerBrain, &ensembleLearner,
                                &performanceAnalytics))
    {
        Print("[ERROR] Failed to initialize Trading Engine");
        return INIT_FAILED;
    }
    
    // Initialize instruments
    if(!tradingEngine.InitializeInstruments(300))
    {
        Print("[ERROR] Failed to initialize instruments");
        return INIT_FAILED;
    }

    // Initialize strategies
    if(!tradingEngine.InitializeStrategies())
    {
        Print("[ERROR] Failed to initialize strategies");
        return INIT_FAILED;
    }

    // Initialize AI systems integration
    if(InpUsePythonAI || InpUseCppAI || InpUseHybridAI)
    {
        if(!InitializeAISystems())
        {
            Print("[WARNING] Failed to initialize extended AI systems - continuing with basic AI");
        }
    }
    
    // Initialize risk management systems
    if(InpUseEnhancedRisk)
    {
        SEnhancedRiskConfig riskConfig;
        riskConfig.enabled = true;
        riskConfig.base_risk_per_trade = InpMaxRiskPerTrade;
        riskConfig.max_risk_per_trade = InpMaxRiskPerTrade * 1.5;
        riskConfig.min_risk_per_trade = InpMaxRiskPerTrade * 0.5;
        riskConfig.max_daily_risk = InpMaxDailyRisk;
        riskConfig.max_weekly_risk = InpMaxDailyRisk * 5;
        riskConfig.max_monthly_risk = InpMaxDailyRisk * 20;
        riskConfig.max_drawdown_threshold = InpMaxDrawdown;
        riskConfig.recovery_mode_multiplier = 0.5;
        riskConfig.adaptive_risk_adjustment = true;
        riskConfig.anti_martingale = true;
        riskConfig.kelly_criterion = false;
        riskConfig.volatility_adjustment = true;
        riskConfig.regime_aware = true;
        riskConfig.correlation_adjustment = true;
        riskConfig.news_filter = false;
        riskConfig.consecutive_losses_limit = 5;
        riskConfig.win_rate_threshold = 0.4;
        riskConfig.profit_factor_threshold = 1.2;
        riskConfig.sharpe_ratio_threshold = 1.0;
        riskConfig.trailing_stop_loss = true;
        riskConfig.trailing_step = 10.0;
        riskConfig.partial_close_on_drawdown = true;
        riskConfig.partial_close_threshold = 0.1;
        riskConfig.hedge_mode = false;
        riskConfig.hedge_ratio = 0.5;
        riskConfig.martingale_recovery = false;
        riskConfig.martingale_multiplier = 2.0;
        riskConfig.martingale_max_levels = 3;
        riskConfig.grid_recovery = false;
        riskConfig.grid_spacing = 20.0;
        riskConfig.grid_max_levels = 5;
        
        enhancedRiskManager.Initialize(riskConfig, AccountInfoDouble(ACCOUNT_BALANCE));
        Print("[RISK] Enhanced risk management activated with adaptive features");
    }

    // Initialize take-profit management
    if(InpUseProgressiveTP)
    {
        activeTPManagers = new CArrayObj();
        progressiveTPEnabled = true;
        Print("[TP] Progressive take-profit system activated");
    }
    
    // Initialize performance tracking
    startTime = TimeCurrent();
    peakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    initialBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    accountBalance = initialBalance;
    currentEquity = peakEquity;
    accountEquity = peakEquity;
    
    // 🔥 CRITICAL FIX: Initialize daily risk limits!
    // Allow risking up to 10% of account per day (conservative daily limit)
    maxDailyRisk = accountEquity * 0.10;  // 10% of equity per day max
    dailyRiskUsed = 0.0;
    PrintFormat("[RISK-INIT] Max daily risk set to %.2f (10%% of equity %.2f)", 
               maxDailyRisk, accountEquity);
    
    // 🔥 CRITICAL FIX: Initialize Portfolio Risk Manager and Risk Validation Gate!
    // InpMaxDailyRisk is already in decimal format (0.06 = 6%), don't divide by 100!
    if(!portfolioRisk.Initialize(&positionSizer, InpMaxDailyRisk, 10.0))
    {
        Print("[ERROR] Failed to initialize portfolio risk manager");
        return INIT_FAILED;
    }
    PrintFormat("[PORTFOLIO-RISK] Portfolio risk manager initialized with max risk: %.2f%%", InpMaxDailyRisk * 100.0);
    
    // InpMaxRiskPerTrade is decimal (0.02 = 2%), multiply by 100 for percentage
    if(!riskGate.Initialize(&portfolioRisk, InpMaxRiskPerTrade * 100.0, InpMaxDailyRisk * 100.0, 0.7))
    {
        Print("[ERROR] Failed to initialize risk validation gate");
        return INIT_FAILED;
    }
    PrintFormat("[RISK-GATE] Risk validation gate initialized successfully (MaxRisk: %.1f%%, MaxDaily: %.1f%%)", 
               InpMaxRiskPerTrade * 100.0, InpMaxDailyRisk * 100.0);
    
    // Set up chart display
    ChartSetInteger(0, CHART_SHOW_GRID, false);
    ChartSetInteger(0, CHART_SHOW_VOLUMES, CHART_VOLUME_TICK);
    Comment("AI Trading System ACTIVE\nMagic: ", InpMagicNumber, "\nSymbols: ", InpSymbolsToTrade);

    systemInitialized = true;
    tradingEnabled = true;
    currentTime = TimeCurrent();

    Print("[MULTI-STRATEGY-EA] ========================================");
    Print("[MULTI-STRATEGY-EA] System initialization SUCCESSFUL");
    Print("[MULTI-STRATEGY-EA] Live trading is ACTIVE");
    Print("[MULTI-STRATEGY-EA] ========================================");
    
    // Send notification if available
    if(TerminalInfoInteger(TERMINAL_NOTIFICATIONS_ENABLED))
    {
        SendNotification("AI Trading System activated on " + AccountInfoString(ACCOUNT_COMPANY));
    }
    
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert Advisor Deinitialization                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("[MULTI-STRATEGY-EA] ========================================");
    Print("[MULTI-STRATEGY-EA] Shutting down AI Trading System");
    Print("[MULTI-STRATEGY-EA] Reason: ", GetDeInitReasonText(reason));
    Print("[MULTI-STRATEGY-EA] ========================================");

    // Save final performance report
    SavePerformanceData();
    
    // Generate final statistics
    datetime endTime = TimeCurrent();
    int tradingSeconds = (int)(endTime - startTime);
    int tradingHours = tradingSeconds / 3600;
    int tradingDays = tradingHours / 24;
    
    Print("[FINAL REPORT] ========================================");
    Print("[FINAL] Trading Duration: ", tradingDays, " days, ", tradingHours % 24, " hours");
    double finalBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double finalEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double netProfit = finalEquity - initialBalance;
    double returnPct = initialBalance > 0 ? (netProfit / initialBalance) * 100 : 0;
    
    Print("[FINAL] Initial Balance: ", DoubleToString(initialBalance, 2));
    Print("[FINAL] Final Balance: ", DoubleToString(finalBalance, 2));
    Print("[FINAL] Final Equity: ", DoubleToString(finalEquity, 2));
    Print("[FINAL] Net Profit: ", DoubleToString(netProfit, 2));
    Print("[FINAL] Return: ", DoubleToString(returnPct, 2), "%");
    Print("[FINAL] Total Trades: ", totalTrades);
    Print("[FINAL] Winning Trades: ", winningTrades);
    Print("[FINAL] Losing Trades: ", losingTrades);
    Print("[FINAL] Win Rate: ", DoubleToString((winningTrades > 0 ? (double)winningTrades / totalTrades * 100 : 0), 2), "%");
    Print("[FINAL] Max Drawdown: ", DoubleToString(maxDrawdown * 100, 2), "%");
    Print("[FINAL] Peak Equity: ", DoubleToString(peakEquity, 2));
    
    // Display AI performance metrics
    if(systemInitialized)
    {
        Print("[AI METRICS] ========================================");
        Print("[AI] Neural Network Accuracy: ", DoubleToString(aiNextGenBrain.GetAccuracy() * 100, 2), "%");
        Print("[AI] Training Epochs: ", aiNextGenBrain.GetEpochCount());
        Print("[AI] Ensemble Confidence: ", DoubleToString(ensembleLearner.GetConfidence() * 100, 2), "%");
    }

    // Deinitialize AI systems
    if(systemInitialized)
    {
        aiNextGenBrain.Shutdown();
        transformerBrain.Shutdown();
        ensembleLearner.Shutdown();
        integrationHub.Deinit();
        DeinitializeAISystems();
        
        // Cleanup AIEngine
        if(g_AIEngine != NULL)
        {
            delete g_AIEngine;
            g_AIEngine = NULL;
            Print("[AI] AIEngine cleaned up");
        }
    }



    // Clean up take-profit managers
    if(activeTPManagers != NULL)
    {
        for(int i = (*activeTPManagers).Total() - 1; i >= 0; i--)
        {
            CTPManagerEntry* entry = (CTPManagerEntry*)(*activeTPManagers).At(i);
            if(entry != NULL)
                delete entry;
        }
        delete activeTPManagers;
        activeTPManagers = NULL;
    }
    
    // Clean up level breaker if initialized
    if(levelBreaker != NULL)
    {
        delete levelBreaker;
        levelBreaker = NULL;
    }

    systemInitialized = false;
    tradingEnabled = false;
    
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
//| Expert Advisor Tick Handler                                      |
//+------------------------------------------------------------------+
void OnTick()
{
    // 🔥 DEBUG: First tick detection
    static bool firstTick = true;
    static int tickCount = 0;
    tickCount++;
    
    if(firstTick)
    {
        PrintFormat("[DEBUG-ONTICK] First tick received! System initialized: %s, Trading enabled: %s",
                   systemInitialized ? "YES" : "NO",
                   tradingEnabled ? "YES" : "NO");
        firstTick = false;
    }
    
    // Log every 100 ticks to show activity
    if(tickCount % 100 == 0)
    {
        PrintFormat("[DEBUG-ONTICK] Tick #%d - EA is processing ticks normally", tickCount);
        Print("[DEBUG-TICK] Tick #", tickCount, " Time: ", TimeCurrent());
        Print("[DEBUG-STATUS] Current symbol: ", _Symbol, " Symbols processed: ", GetProcessedSymbolCount());
    }
    
    if(!systemInitialized || !tradingEnabled)
    {
        PrintFormat("[DEBUG-ONTICK] EA blocked: System initialized: %s, Trading enabled: %s",
                   systemInitialized ? "YES" : "NO",
                   tradingEnabled ? "YES" : "NO");
        return;
    }
        
    // Check if trading is still allowed
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
    {
        Print("[DEBUG-ONTICK] Trading permissions check failed!");
        Comment("Trading is DISABLED - Waiting for permissions...");
        return;
    }

    currentTime = TimeCurrent();
    currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    accountEquity = currentEquity;

    // Update peak equity and drawdown
    if(currentEquity > peakEquity)
        peakEquity = currentEquity;

    if(peakEquity > 0)
        currentDrawdown = (peakEquity - currentEquity) / peakEquity;
        
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
    globalMarketData[12] = recoveryMultiplier;
    globalMarketData[13] = (double)totalTrades;
    
    // Get global AI market assessment
    double globalAIPrediction = integrationHub.GetAIPrediction(globalMarketData, 14);
    
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
    // Process trading logic
    // tradingEngine.OnTick(); // Replaced with robust loop
    ProcessAllSymbols();

    // Manage open positions via Trading Engine
    tradingEngine.ManageOpenPositions();

    // Update take-profit management
    if(progressiveTPEnabled)
        UpdateTakeProfitManagement();

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