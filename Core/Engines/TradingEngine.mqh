//+------------------------------------------------------------------+
//| Trading Engine Class                                             |
//+------------------------------------------------------------------+
#ifndef __TRADING_ENGINE_MQH__
#define __TRADING_ENGINE_MQH__

#include "../Trading/TradeManager.mqh"
#include "../Risk/PositionSizer.mqh"
#include "../AI/AIStrategyOrchestrator.mqh"
#include "../Utils/Instruments.mqh"
#include "../Market/CrashBoomSpikeDetector.mqh"
#include "../Market/StepIndexLevelBreaker.mqh"
#include "../Connectivity/IntegrationHub.mqh"
#include "../Utils/SymbolContext.mqh"
#include "../Utils/ModeManager.mqh"
#include "../Risk/EnhancedRiskManager.mqh"
#include "../../AIModules/NextGenStrategyBrain.mqh"
#include "../../AIModules/TransformerBrain.mqh"
#include "../../AIModules/EnsembleMetaLearner.mqh"
#include "../../Strategies/SimpleMomentumStrategy.mqh"
#include "../../Strategies/StrategyRSI.mqh"
#include "../../Strategies/StrategyTrend.mqh"
#include "../../Strategies/StrategyMeanReversion.mqh"
#include "../../Strategies/StrategySupplyDemand.mqh"
#include "../../Strategies/StrategySwing.mqh"
#include "../../Strategies/StrategyVolatility.mqh"
#include "../../Strategies/StrategyOrderBlockFVG.mqh"
#include "../../Strategies/StrategyStepIndex.mqh"
#include "../../Strategies/StrategyMACD.mqh"
#include "../../Strategies/StrategyOrderBlock.mqh"
#include "../../Strategies/StrategyBollinger.mqh"
#include "../../Strategies/StrategyBollingerBreakout.mqh"
#include "../../Strategies/StrategySMC.mqh"
#include "../../Strategies/StrategyBreakout.mqh"
#include "../../Strategies/StrategyIchimoku.mqh"
#include "../../Strategies/StrategyElliottWave.mqh"
#include "../../Strategies/StrategyFairValueGap.mqh"
#include "../../Strategies/StrategyHarmonicPatterns.mqh"
#include "../Strategy/StrategyWrapper.mqh"
#include "../Monitoring/PerformanceAnalytics.mqh"

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

//+------------------------------------------------------------------+
//| Trading Engine Class                                             |
//+------------------------------------------------------------------+
class CTradingEngine : public CObject
{
private:
    // Core components (external dependencies)
    CTradeManager*          m_tradeManager;
    CPositionSizer*         m_positionSizer;
    CAIStrategyOrchestrator* m_aiOrchestrator;
    CInstrumentRegistry*    m_instrumentRegistry;
    CCrashBoomSpikeDetector* m_spikeDetector;
    CStepIndexLevelBreaker* m_levelBreaker;
    CAIIntegrationHub*      m_integrationHub;
    CModeManager*           m_modeManager;
    CEnhancedRiskManager*   m_riskManager;
    
    // AI Components (external dependencies)
    CNextGenStrategyBrain*  m_aiNextGenBrain;
    CTransformerBrain*      m_transformerBrain;
    CEnsembleMetaLearner*   m_ensembleLearner;
    CPerformanceAnalytics*  m_performanceAnalytics;

    // Internal state
    CArrayObj*              m_symbolContexts;
    datetime                m_lastStrategyDebugTime;
    datetime                m_lastHistoryCheck;
    
    // Configuration
    double                  m_defaultRiskPerTrade;
    double                  m_recoveryMultiplier;

public:
    CTradingEngine();
    ~CTradingEngine();

    // Initialization
    bool Initialize(CTradeManager* p_tradeManager,
                   CPositionSizer* p_positionSizer,
                   CAIStrategyOrchestrator* p_aiOrchestrator,
                   CInstrumentRegistry* p_instrumentRegistry,
                   CCrashBoomSpikeDetector* p_spikeDetector,
                   CStepIndexLevelBreaker* p_levelBreaker,
                   CAIIntegrationHub* p_integrationHub,
                   CNextGenStrategyBrain* p_aiNextGenBrain,
                   CTransformerBrain* p_transformerBrain,
                   CEnsembleMetaLearner* p_ensembleLearner,
                   CPerformanceAnalytics* p_performanceAnalytics);

    // Setup functions
    bool InitializeInstruments(int maxSymbols = 300);
    bool InitializeStrategies();
    
    // Main processing loop
    void OnTick();
    void ProcessSymbol(CSymbolContext* ctx);
    
    // Helpers
    bool ValidateSymbol(const string symbolName);
    void RefreshSymbolData(CSymbolContext* ctx);
    ENUM_TRADE_SIGNAL EvaluateStrategies(CSymbolContext* context, double &confidence);
    
    // Configuration setters
    void SetDefaultRiskPerTrade(double risk) { m_defaultRiskPerTrade = risk; }
    void SetRecoveryMultiplier(double multiplier) { m_recoveryMultiplier = multiplier; }
    
    // Accessors
    int GetSymbolContextCount() { return (m_symbolContexts != NULL) ? m_symbolContexts.Total() : 0; }
    CSymbolContext* GetSymbolContext(int index) { return (m_symbolContexts != NULL) ? (CSymbolContext*)m_symbolContexts.At(index) : NULL; }
    CSymbolContext* GetSymbolContext(string symbol);
    
    // Position management
    void ManageOpenPositions();
    void ProcessClosedTrades();
    bool CanOpenNewPosition(string symbol);  // CRITICAL FIX: Position limit validation

private:
    bool ShouldTradeSymbol(CSymbolContext* ctx, double &volumeOut, double &stopLossOut);
    bool ExecuteTradeForSymbol(CSymbolContext* ctx, ENUM_TRADE_SIGNAL signal, double confidence, MqlTick &tick, double volume, double stopLoss);
    bool ExecuteTradeWithRetry(string symbol, ENUM_ORDER_TYPE order_type, double volume, double price, double sl, double tp, string comment="");
    void LogMalformedTick(CSymbolContext* ctx, MqlTick &tick);
    void UpdateSymbolMarketState(CSymbolContext* ctx);
    void UpdateSymbolRiskUsage(CSymbolContext* ctx, double riskAmount);
    int  CountOpenPositions(string symbol);  // CRITICAL FIX: Count positions per symbol
    
    // Position management

};
//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CTradingEngine::CTradingEngine() :
    m_tradeManager(NULL),
    m_positionSizer(NULL),
    m_aiOrchestrator(NULL),
    m_performanceAnalytics(NULL),
    m_instrumentRegistry(NULL),
    m_spikeDetector(NULL),
    m_levelBreaker(NULL),
    m_integrationHub(NULL),
    m_aiNextGenBrain(NULL),
    m_transformerBrain(NULL),
    m_ensembleLearner(NULL),
    m_symbolContexts(NULL),
    m_lastStrategyDebugTime(0),
    m_lastHistoryCheck(0),
    m_defaultRiskPerTrade(0.02),
    m_recoveryMultiplier(1.0),
    m_modeManager(NULL),
    m_riskManager(NULL)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CTradingEngine::~CTradingEngine()
{
    if(m_symbolContexts != NULL)
    {
        delete m_symbolContexts;
        m_symbolContexts = NULL;
    }
    
    if(m_modeManager != NULL)
    {
        delete m_modeManager;
        m_modeManager = NULL;
    }
    
    if(m_riskManager != NULL)
    {
        delete m_riskManager;
        m_riskManager = NULL;
    }
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CTradingEngine::Initialize(CTradeManager* p_tradeManager,
                   CPositionSizer* p_positionSizer,
                   CAIStrategyOrchestrator* p_aiOrchestrator,
                   CInstrumentRegistry* p_instrumentRegistry,
                   CCrashBoomSpikeDetector* p_spikeDetector,
                   CStepIndexLevelBreaker* p_levelBreaker,
                   CAIIntegrationHub* p_integrationHub,
                   CNextGenStrategyBrain* p_aiNextGenBrain,
                   CTransformerBrain* p_transformerBrain,
                   CEnsembleMetaLearner* p_ensembleLearner,
                   CPerformanceAnalytics* p_performanceAnalytics)
{
    m_tradeManager = p_tradeManager;
    m_positionSizer = p_positionSizer;
    m_aiOrchestrator = p_aiOrchestrator;
    m_instrumentRegistry = p_instrumentRegistry;
    m_spikeDetector = p_spikeDetector;
    m_levelBreaker = p_levelBreaker;
    m_integrationHub = p_integrationHub;
    m_aiNextGenBrain = p_aiNextGenBrain;
    m_transformerBrain = p_transformerBrain;
    m_ensembleLearner = p_ensembleLearner;
    m_performanceAnalytics = p_performanceAnalytics;
    
    // Initialize Mode Manager
    if(m_modeManager == NULL)
    {
        m_modeManager = new CModeManager();
        // Default params: VolHTF=0.18, VolLow=0.02, VolHigh=0.08, SpreadMax=1.5, HTF=H1
        m_modeManager.Init(0.18, 0.02, 0.08, 1.5, PERIOD_H1);
    }
    
    // Initialize Risk Manager
    if(m_riskManager == NULL)
    {
        m_riskManager = new CEnhancedRiskManager();
        SEnhancedRiskConfig riskConfig;
        // Enable enhanced risk management
        riskConfig.enabled = true;
        // Core risk parameters
        riskConfig.base_risk_per_trade = 0.02;      // 2% base risk
        riskConfig.max_risk_per_trade = 0.05;       // 5% max per trade
        riskConfig.min_risk_per_trade = 0.005;      // 0.5% min per trade
        // CRITICAL: Daily/Weekly/Monthly limits must be set!
        riskConfig.max_daily_risk = 0.10;           // 10% max daily risk  
        riskConfig.max_weekly_risk = 0.25;          // 25% max weekly risk
        riskConfig.max_monthly_risk = 0.50;         // 50% max monthly risk
        riskConfig.max_drawdown_threshold = 0.15;   // 15% max drawdown
        riskConfig.recovery_mode_multiplier = 0.5;
        // Adaptive features
        riskConfig.adaptive_risk_adjustment = true;
        riskConfig.anti_martingale = true;
        riskConfig.kelly_criterion = false;
        riskConfig.volatility_adjustment = true;
        riskConfig.regime_aware = true;
        riskConfig.correlation_adjustment = false;
        riskConfig.news_filter = false;
        // Limits
        riskConfig.consecutive_losses_limit = 5;
        riskConfig.win_rate_threshold = 0.4;
        riskConfig.profit_factor_threshold = 1.2;
        riskConfig.sharpe_ratio_threshold = 0.5;
        // Additional features
        riskConfig.trailing_stop_loss = true;
        riskConfig.trailing_step = 10.0;
        riskConfig.partial_close_on_drawdown = false;
        riskConfig.partial_close_threshold = 0.1;
        riskConfig.hedge_mode = false;
        riskConfig.hedge_ratio = 0.5;
        riskConfig.martingale_recovery = false;
        riskConfig.martingale_multiplier = 2.0;
        riskConfig.martingale_max_levels = 3;
        riskConfig.grid_recovery = false;
        riskConfig.grid_spacing = 50.0;
        riskConfig.grid_max_levels = 5;
        
        m_riskManager.Initialize(riskConfig, AccountInfoDouble(ACCOUNT_EQUITY));
    }
    
    if(m_tradeManager == NULL || m_positionSizer == NULL || m_instrumentRegistry == NULL)
    {
        Print("[TRADING-ENGINE] Critical components missing during initialization");
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Initialize Instruments                                           |
//+------------------------------------------------------------------+
bool CTradingEngine::InitializeInstruments(int maxSymbols)
{
    Print("[TRADING-ENGINE] Building instrument directory");

    if(m_instrumentRegistry == NULL)
    {
        Print("[TRADING-ENGINE] Instrument registry not initialized");
        return false;
    }

    if(!m_instrumentRegistry.Initialize(maxSymbols))
    {
        Print("[TRADING-ENGINE] Instrument registry initialization failed");
        return false;
    }

    string tradableSymbols[];
    int symbolCount = m_instrumentRegistry.GetTradableSymbols(tradableSymbols, true);
    if(symbolCount <= 0)
    {
        Print("[TRADING-ENGINE] No tradable symbols discovered");
        return false;
    }

    if(m_symbolContexts == NULL)
        m_symbolContexts = new CArrayObj();
    else
    {
        m_symbolContexts.Clear(); // Clear existing contexts
    }

    int validatedCount = 0;
    int skippedCount = 0;

    for(int i = 0; i < symbolCount; ++i)
    {
        string symbolName = tradableSymbols[i];
        
        // Enhanced validation - reject invalid symbols early
        if(!ValidateSymbol(symbolName))
        {
            if(symbolName != "")
                PrintFormat("[TRADING-ENGINE] Skipping invalid symbol: %s", symbolName);
            skippedCount++;
            continue;
        }

        CSymbolContext *context = new CSymbolContext(symbolName, PERIOD_CURRENT);
        if(context == NULL)
        {
            PrintFormat("[TRADING-ENGINE] Failed to create context for %s", symbolName);
            skippedCount++;
            continue;
        }

        if(context.strategyWrappers == NULL)
        {
            PrintFormat("[TRADING-ENGINE] Failed to create strategy wrappers for %s", symbolName);
            delete context;
            skippedCount++;
            continue;
        }

        RefreshSymbolData(context);
        
        if(m_spikeDetector != NULL)
            m_spikeDetector.MonitorForSpikes(context.symbol);
            
        if(m_levelBreaker != NULL)
            m_levelBreaker.MonitorStepLevels(context.symbol);
            
        m_symbolContexts.Add(context);
        validatedCount++;
    }

    int totalContexts = m_symbolContexts.Total();
    PrintFormat("[TRADING-ENGINE] Instrument universe initialized: %d valid, %d skipped, %d total contexts", 
                validatedCount, skippedCount, totalContexts);
    return (totalContexts > 0);
}

//+------------------------------------------------------------------+
//| Refresh Symbol Data                                              |
//+------------------------------------------------------------------+
void CTradingEngine::RefreshSymbolData(CSymbolContext* ctx)
{
    if(ctx == NULL)
        return;

    const string symbol = ctx.symbol;
    if(symbol == "")
        return;

    if(!SymbolSelect(symbol, true))
    {
        ctx.isTradable = false;
        ctx.tradingSuspended = true;
        return;
    }

    ctx.digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    ctx.point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    ctx.lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    ctx.minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    ctx.maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    ctx.contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);

    ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
    ctx.isTradable = (tradeMode != SYMBOL_TRADE_MODE_DISABLED);
    ctx.tradingSuspended = !ctx.isTradable;

    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double last = SymbolInfoDouble(symbol, SYMBOL_LAST);

    if(bid > 0.0)
        ctx.lastValidBid = bid;

    if(ask > 0.0)
        ctx.lastValidAsk = ask;

    if(bid > 0.0 && ask > 0.0)
        ctx.lastPrice = 0.5 * (bid + ask);
    else if(last > 0.0)
        ctx.lastPrice = last;

    double pt = ctx.point;
    if(pt > 0.0 && bid > 0.0 && ask > 0.0)
        ctx.UpdateSpreadStatistics((ask - bid) / pt);

    if(ctx.riskPerTrade <= 0.0)
        ctx.riskPerTrade = m_defaultRiskPerTrade;
}

//+------------------------------------------------------------------+
//| Initialize Strategies                                            |
//+------------------------------------------------------------------+
bool CTradingEngine::InitializeStrategies()
{
    // NOTE: This method references undefined InpEnable* input variables
    // These should be passed as parameters or configured differently
    // Commenting out experimental code for now
    
    /*
    if(m_symbolContexts == NULL || m_symbolContexts.Total() == 0)
        return false;

    Print("[TRADING-ENGINE] Initializing strategy universe");

    for(int i = 0; i < m_symbolContexts.Total(); ++i)
    {
        CSymbolContext *context = (CSymbolContext*)m_symbolContexts.At(i);
        if(context == NULL)
            continue;

        if(context.strategyWrappers == NULL)
            context.strategyWrappers = new CArrayObj();

        // Initialize strategies based on input parameters
        int strategiesInitialized = 0;
        
        // 1. Simple Momentum Strategy
        if(InpEnableMomentum)
        {
            CSimpleMomentumStrategy *momentum = new CSimpleMomentumStrategy(StringFormat("Momentum_%s", context.symbol));
            if(momentum != NULL && momentum.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(momentum);
                if(wrapper != NULL)
                {
                    context.strategyWrappers.Add(wrapper);
                    strategiesInitialized++;
                }
                else
                {
                    delete momentum;
                }
            }
            else if(momentum != NULL)
            {
                delete momentum;
            }
        }
        
        // 2. RSI Strategy
        if(InpEnableRSI)
        {
            CStrategyRSI *rsi = new CStrategyRSI(StringFormat("RSI_%s", context.symbol));
            if(rsi != NULL && rsi.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(rsi);
                if(wrapper != NULL)
                {
                    context.strategyWrappers.Add(wrapper);
                    strategiesInitialized++;
                }
                else
                {
                    delete rsi;
                }
            }
            else if(rsi != NULL)
            {
                delete rsi;
            }
        }
        
        // 3. Trend Strategy
        if(InpEnableTrend)
        {
            CStrategyTrend *trend = new CStrategyTrend(StringFormat("Trend_%s", context.symbol));
            if(trend != NULL && trend.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(trend);
                if(wrapper != NULL)
                {
                    context.strategyWrappers.Add(wrapper);
                    strategiesInitialized++;
                }
                else
                {
                    delete trend;
                }
            }
            else if(trend != NULL)
            {
                delete trend;
            }
        }
        
        // 4. Mean Reversion Strategy
        if(InpEnableMeanReversion)
        {
            CStrategyMeanReversion *meanRev = new CStrategyMeanReversion(StringFormat("MeanRev_%s", context.symbol));
            if(meanRev != NULL && meanRev.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(meanRev);
                if(wrapper != NULL)
                {
                    context.strategyWrappers.Add(wrapper);
                    strategiesInitialized++;
                }
                else
                {
                    delete meanRev;
                }
            }
            else if(meanRev != NULL)
            {
                delete meanRev;
            }
        }
        
        // 5. Supply Demand Strategy
        if(InpEnableSupplyDemand)
        {
            CStrategySupplyDemand *supplyDemand = new CStrategySupplyDemand(StringFormat("SupplyDemand_%s", context.symbol));
            if(supplyDemand != NULL && supplyDemand.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(supplyDemand);
                if(wrapper != NULL) { context.strategyWrappers.Add(wrapper); strategiesInitialized++; }
                else delete supplyDemand;
            }
            else if(supplyDemand != NULL) delete supplyDemand;
        }
        
        // 6. Swing Strategy
        if(InpEnableSwing)
        {
            CStrategySwing *swing = new CStrategySwing(StringFormat("Swing_%s", context.symbol));
            if(swing != NULL && swing.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(swing);
                if(wrapper != NULL) { context.strategyWrappers.Add(wrapper); strategiesInitialized++; }
                else delete swing;
            }
            else if(swing != NULL) delete swing;
        }
        
        // 7. Volatility Strategy
        if(InpEnableVolatility)
        {
            CStrategyVolatility *volatility = new CStrategyVolatility(StringFormat("Volatility_%s", context.symbol));
            if(volatility != NULL && volatility.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(volatility);
                if(wrapper != NULL) { context.strategyWrappers.Add(wrapper); strategiesInitialized++; }
                else delete volatility;
            }
            else if(volatility != NULL) delete volatility;
        }
        
        // 8. Order Block FVG Strategy
        if(InpEnableOrderBlockFVG)
        {
            CStrategyOrderBlockFVG *obfvg = new CStrategyOrderBlockFVG(StringFormat("OBFVG_%s", context.symbol), 0);
            if(obfvg != NULL && obfvg.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(obfvg);
                if(wrapper != NULL) { context.strategyWrappers.Add(wrapper); strategiesInitialized++; }
                else delete obfvg;
            }
            else if(obfvg != NULL) delete obfvg;
        }
        
        // 9. Step Index Strategy (skip if dependencies unavailable)
        if(InpEnableStepIndex && m_levelBreaker != NULL)
        {
            CStrategyStepIndex *stepIndex = new CStrategyStepIndex(m_levelBreaker, NULL, NULL);
            if(stepIndex != NULL && stepIndex.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(stepIndex);
                if(wrapper != NULL) { context.strategyWrappers.Add(wrapper); strategiesInitialized++; }
                else delete stepIndex;
            }
            else if(stepIndex != NULL) delete stepIndex;
        }
        
        // 10. MACD Strategy
        if(InpEnableMACD)
        {
            CStrategyMACD *macd = new CStrategyMACD(StringFormat("MACD_%s", context.symbol));
            if(macd != NULL && macd.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(macd);
                if(wrapper != NULL) { context.strategyWrappers.Add(wrapper); strategiesInitialized++; }
                else delete macd;
            }
            else if(macd != NULL) delete macd;
        }
        
        // 11. Order Block Strategy
        if(InpEnableOrderBlock)
        {
            CStrategyOrderBlock *ob = new CStrategyOrderBlock(StringFormat("OrderBlock_%s", context.symbol));
            if(ob != NULL && ob.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(ob);
                if(wrapper != NULL) { context.strategyWrappers.Add(wrapper); strategiesInitialized++; }
                else delete ob;
            }
            else if(ob != NULL) delete ob;
        }
        
        // 12. Bollinger Strategy
        if(InpEnableBollinger)
        {
            CStrategyBollinger *bb = new CStrategyBollinger(StringFormat("Bollinger_%s", context.symbol));
            if(bb != NULL && bb.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(bb);
                if(wrapper != NULL) { context.strategyWrappers.Add(wrapper); strategiesInitialized++; }
                else delete bb;
            }
            else if(bb != NULL) delete bb;
        }
        
        // 13. Bollinger Breakout Strategy
        if(InpEnableBollingerBreakout)
        {
            CStrategyBollingerBreakout *bbBreak = new CStrategyBollingerBreakout(StringFormat("BBBreak_%s", context.symbol));
            if(bbBreak != NULL && bbBreak.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(bbBreak);
                if(wrapper != NULL) { context.strategyWrappers.Add(wrapper); strategiesInitialized++; }
                else delete bbBreak;
            }
            else if(bbBreak != NULL) delete bbBreak;
        }
        
        // 14. Advanced SMC Strategy
        if(InpEnableSMC)
        {
            CStrategySMC *smc = new CStrategySMC();
            if(smc != NULL && smc.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(smc);
                if(wrapper != NULL) { context.strategyWrappers.Add(wrapper); strategiesInitialized++; }
                else delete smc;
            }
            else if(smc != NULL) delete smc;
        }
        
        // 15. Breakout Strategy
        if(InpEnableBreakout)
        {
            CStrategyBreakout *breakout = new CStrategyBreakout(StringFormat("Breakout_%s", context.symbol));
            if(breakout != NULL && breakout.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(breakout);
                if(wrapper != NULL) { context.strategyWrappers.Add(wrapper); strategiesInitialized++; }
                else delete breakout;
            }
            else if(breakout != NULL) delete breakout;
        }
        
        // 16. Fibonacci Strategy (Already included via StrategyFactory - uses existing class)
        if(InpEnableFibonacci)
        {
            CStrategyFibonacci *fib = new CStrategyFibonacci(StringFormat("Fibonacci_%s", context.symbol), 0);
            if(fib != NULL && fib.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(fib);
                if(wrapper != NULL) { context.strategyWrappers.Add(wrapper); strategiesInitialized++; }
                else delete fib;
            }
            else if(fib != NULL) delete fib;
        }
        
        // 17. Elliott Wave Strategy
        if(InpEnableElliottWave)
        {
            CStrategyElliottWave *elliottWave = new CStrategyElliottWave();
            if(elliottWave != NULL && elliottWave.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(elliottWave);
                if(wrapper != NULL) { context.strategyWrappers.Add(wrapper); strategiesInitialized++; }
                else delete elliottWave;
            }
            else if(elliottWave != NULL) delete elliottWave;
        }
        
        // 18. Ichimoku Strategy
        if(InpEnableIchimoku)
        {
            CStrategyIchimoku *ichimoku = new CStrategyIchimoku(StringFormat("Ichimoku_%s", context.symbol));
            if(ichimoku != NULL && ichimoku.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(ichimoku);
                if(wrapper != NULL) { context.strategyWrappers.Add(wrapper); strategiesInitialized++; }
                else delete ichimoku;
            }
            else if(ichimoku != NULL) delete ichimoku;
        }
        
        // 19. Fair Value Gap Strategy
        if(InpEnableFairValueGap)
        {
            CStrategyFairValueGap *fvg = new CStrategyFairValueGap(StringFormat("FVG_%s", context.symbol));
            if(fvg != NULL && fvg.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(fvg);
                if(wrapper != NULL) { context.strategyWrappers.Add(wrapper); strategiesInitialized++; }
                else delete fvg;
            }
            else if(fvg != NULL) delete fvg;
        }
        
        // 20. Harmonic Patterns Strategy
        if(InpEnableHarmonicPatterns)
        {
            CStrategyHarmonicPatterns *harmonic = new CStrategyHarmonicPatterns(StringFormat("Harmonic_%s", context.symbol));
            if(harmonic != NULL && harmonic.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(harmonic);
                if(wrapper != NULL) { context.strategyWrappers.Add(wrapper); strategiesInitialized++; }
                else delete harmonic;
            }
            else if(harmonic != NULL) delete harmonic;
        }
        
        // 21. Elliott Advanced Strategy (Already included via StrategyFactory - uses existing class)
        if(InpEnableElliott)
        {
            CStrategyElliott *elliott = new CStrategyElliott(StringFormat("Elliott_%s", context.symbol));
            if(elliott != NULL && elliott.Init(context.symbol, context.timeframe, m_tradeManager, m_positionSizer))
            {
                CStrategyWrapper *wrapper = new CStrategyWrapper(elliott);
                if(wrapper != NULL) { context.strategyWrappers.Add(wrapper); strategiesInitialized++; }
                else delete elliott;
            }
            else if(elliott != NULL) delete elliott;
        }
        
        if(strategiesInitialized > 0)
        {
            PrintFormat("[TRADING-ENGINE] Initialized %d strategies for %s", strategiesInitialized, context.symbol);
        }
    }

    return true;
    */
    
    // Return true for now - strategies should be registered via EnterpriseStrategyManager
    return true;
}

//+------------------------------------------------------------------+
//| Evaluate Strategies                                              |
//+------------------------------------------------------------------+
ENUM_TRADE_SIGNAL CTradingEngine::EvaluateStrategies(CSymbolContext* context, double &confidence)
{
    confidence = 0.0;

    if(context == NULL)
        return TRADE_SIGNAL_NONE;

    CArrayObj* wrappers = context.strategyWrappers;
    if(wrappers == NULL)
        return TRADE_SIGNAL_NONE;

    ENUM_TRADE_SIGNAL bestSignal = TRADE_SIGNAL_NONE;
    double bestConfidence = 0.0;
    int strategiesEvaluated = 0;
    int strategiesWithNoSignal = 0;

    // Update Trading Mode for this symbol
    if(m_modeManager != NULL)
    {
        m_modeManager.UpdateMode(context.symbol);
    }

    for(int i = 0; i < wrappers.Total(); ++i)
    {
        CStrategyWrapper* wrapper = (CStrategyWrapper*)wrappers.At(i);
        if(wrapper == NULL)
            continue;

        IStrategy* strategy = wrapper.Strategy();
        if(strategy == NULL)
            continue;

        if(!strategy.IsEnabled())
            continue;

        strategiesEvaluated++;
        double localConfidence = 0.0;
        ENUM_TRADE_SIGNAL signal = strategy.GetSignal(localConfidence);
        if(signal == TRADE_SIGNAL_NONE)
        {
            strategiesWithNoSignal++;
            continue;
        }

        localConfidence = MathMax(0.0, MathMin(1.0, localConfidence));

        if(localConfidence > bestConfidence)
        {
            bestConfidence = localConfidence;
            bestSignal = signal;
            PrintFormat("[SIGNAL] %s: %s signal with %.1f%% confidence from %s",
                       context.symbol,
                       signal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                       localConfidence * 100,
                       strategy.GetName());
        }
    }

    // Debug logging every 2 minutes for symbols with no signals
    if(bestSignal == TRADE_SIGNAL_NONE && TimeCurrent() - m_lastStrategyDebugTime > 120)
    {
        if(strategiesEvaluated > 0)
        {
            PrintFormat("[DEBUG] %s: %d strategies evaluated, %d with no signal (Regime: %s, Trend: %.2f, Vol: %.2f)",
                       context.symbol, strategiesEvaluated, strategiesWithNoSignal,
                       EnumToString(context.regime), context.regimeStrength, context.volatility);
        }
        m_lastStrategyDebugTime = TimeCurrent();
    }

    confidence = bestConfidence;
    return bestSignal;
}

//+------------------------------------------------------------------+
//| On Tick                                                          |
//+------------------------------------------------------------------+
void CTradingEngine::OnTick()
{
    if(m_symbolContexts == NULL)
        return;

    for(int i = 0; i < m_symbolContexts.Total(); ++i)
    {
        CSymbolContext* ctx = (CSymbolContext*)m_symbolContexts.At(i);
        if(ctx != NULL)
        {
            ProcessSymbol(ctx);
        }
    }
}

//+------------------------------------------------------------------+
//| Process Symbol                                                   |
//+------------------------------------------------------------------+
void CTradingEngine::ProcessSymbol(CSymbolContext* ctx)
{
    if(ctx == NULL) return;
    
    RefreshSymbolData(ctx);
    
    MqlTick tick;
    string symName = ctx.symbol;
    
    if(SymbolInfoTick(symName, tick))
    {
        ctx.lastTick = tick;
        ctx.lastTickTime = tick.time;
        
        if(tick.bid > 0.0) ctx.lastValidBid = tick.bid;
        if(tick.ask > 0.0) ctx.lastValidAsk = tick.ask;
        
        if(tick.bid > 0.0 && tick.ask > 0.0)
            ctx.lastPrice = 0.5 * (tick.bid + tick.ask);
        else if(tick.last > 0.0)
            ctx.lastPrice = tick.last;
            
        double pt = ctx.point;
        if(pt > 0.0 && tick.ask > 0.0 && tick.bid > 0.0)
            ctx.UpdateSpreadStatistics((tick.ask - tick.bid) / pt);
            
        ctx.malformedTickCount = 0;
    }
    else
    {
        ZeroMemory(tick);
        LogMalformedTick(ctx, tick);
        return;
    }
    
    // Risk configuration
    if(ctx.riskPerTrade <= 0.0)
        ctx.riskPerTrade = m_defaultRiskPerTrade;
        
    UpdateSymbolMarketState(ctx);
    
    double volumeOut = 0.0;
    double stopLossOut = 0.0;
    if(!ShouldTradeSymbol(ctx, volumeOut, stopLossOut))
    {
        ctx.lastSignal = TRADE_SIGNAL_NONE;
        ctx.lastSignalConfidence = 0.0;
        return;
    }
    
    double confidence = 0.0;
    ENUM_TRADE_SIGNAL signal = EvaluateStrategies(ctx, confidence);
    ctx.lastSignal = signal;
    ctx.lastSignalConfidence = confidence;
    
    if(signal == TRADE_SIGNAL_NONE) return;
    
    // CRITICAL FIX: Check position limits before trading
    if(!CanOpenNewPosition(ctx.symbol))
    {
        PrintFormat("[TRADING-ENGINE] Position limit reached for %s, signal ignored", ctx.symbol);
        return;
    }
    
    if(ExecuteTradeForSymbol(ctx, signal, confidence, tick, volumeOut, stopLossOut))
    {
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double recovery = (m_recoveryMultiplier > 0.0 ? m_recoveryMultiplier : 1.0);
        double riskAmt = ctx.riskPerTrade;
        double totalRisk = equity * riskAmt * recovery;
        if(totalRisk > 0.0)
            UpdateSymbolRiskUsage(ctx, totalRisk);
    }
}

//+------------------------------------------------------------------+
//| Process Closed Trades for Risk Management                        |
//+------------------------------------------------------------------+
void CTradingEngine::ProcessClosedTrades()
{
    if(m_riskManager == NULL) return;
    
    datetime now = TimeCurrent();
    if(m_lastHistoryCheck == 0)
    {
        m_lastHistoryCheck = now;
        return;
    }
    
    // Select history since last check
    if(!HistorySelect(m_lastHistoryCheck, now)) return;
    
    int deals = HistoryDealsTotal();
    for(int i = 0; i < deals; i++)
    {
        ulong ticket = HistoryDealGetTicket(i);
        if(ticket > 0)
        {
            long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            if(entry == DEAL_ENTRY_OUT) // Only closing deals
            {
                double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
                double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
                double dealProfit = profit + swap + commission;
                
                // Estimate risk taken (simplified, ideally we track this per trade)
                // For now, we assume standard risk was used
                double riskTaken = 0.0; // TODO: Retrieve actual risk from comment or magic
                
                m_riskManager.UpdateTradeResult(dealProfit, riskTaken, (datetime)HistoryDealGetInteger(ticket, DEAL_TIME), dealProfit > 0);
            }
        }
    }
    
    m_lastHistoryCheck = now;
}

//+------------------------------------------------------------------+
//| Helper: Should Trade Symbol                                      |
//+------------------------------------------------------------------+
bool CTradingEngine::ShouldTradeSymbol(CSymbolContext* ctx, double &volumeOut, double &stopLossOut)
{
    if(ctx == NULL) return false;
    
    // Basic checks
    if(!ctx.isTradable || ctx.tradingSuspended) return false;
    
    // Check if we already have max positions for this symbol
    // This would require checking open positions, which we can do via TradeManager or PositionInfo
    // For now, we'll assume TradeManager handles position limits
    
    return true;
}

//+------------------------------------------------------------------+
//| Helper: Execute Trade For Symbol                                 |
//+------------------------------------------------------------------+
bool CTradingEngine::ExecuteTradeForSymbol(CSymbolContext* ctx, ENUM_TRADE_SIGNAL signal, double confidence, MqlTick &tick, double volume, double stopLoss)
{
    if(ctx == NULL || m_tradeManager == NULL) return false;
    
    // Calculate volume if not provided
    if(volume <= 0.0 && m_positionSizer != NULL)
    {
        double riskPercent = ctx.riskPerTrade * 100.0; // Default fallback
        
        // Dynamic Risk Calculation
        if(m_riskManager != NULL && m_modeManager != NULL)
        {
            ENUM_TRADING_MODE currentMode = m_modeManager.GetCurrentMode();
            
            // Calculate dynamic risk
            double dynamicRisk = m_riskManager.CalculateRiskPerTrade(
                AccountInfoDouble(ACCOUNT_EQUITY),
                (signal == TRADE_SIGNAL_BUY) ? tick.ask : tick.bid,
                (signal == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                50.0, // Placeholder SL pips, will be refined
                ctx.regime,
                ctx.volatility,
                TimeCurrent()
            );
            
            // If risk manager returns 0 (e.g. paused), abort trade
            if(dynamicRisk <= 0.0)
            {
                PrintFormat("[TRADING-ENGINE] Trade aborted by Risk Manager for %s (Risk=0.0)", ctx.symbol);
                return false;
            }
            
            riskPercent = dynamicRisk * 100.0; // Convert to percent for PositionSizer
        }
        
        double slPips = 50.0; // Default SL pips if not calculated
        
        // Use ATR for SL if available
        if(ctx.atr > 0.0 && ctx.point > 0.0)
        {
            slPips = (ctx.atr * 2.0) / ctx.point;
        }
        
        volume = m_positionSizer.CalculateRiskBasedSize(ctx.symbol, slPips, riskPercent);
    }
    
    // Execute trade via TradeManager
    ENUM_ORDER_TYPE orderType = (signal == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
    double price = (signal == TRADE_SIGNAL_BUY) ? tick.ask : tick.bid;
    double sl = 0.0;
    double tp = 0.0;
    
    // Calculate SL/TP
    double point = ctx.point;
    if(point > 0.0)
    {
        double atr = (ctx.atr > 0.0) ? ctx.atr : 0.0010; // Fallback ATR
        double slDist = atr * 2.0;
        double tpDist = atr * 3.0; // 1.5 R:R
        
        if(signal == TRADE_SIGNAL_BUY)
        {
            sl = price - slDist;
            tp = price + tpDist;
        }
        else
        {
            sl = price + slDist;
            tp = price - tpDist;
        }
    }
    
    // Convert SL/TP to pips for TradeManager (Legacy)
    // double slPips = MathAbs(price - sl) / point;
    // double tpPips = MathAbs(price - tp) / point;
    
    // return m_tradeManager.OpenPosition(ctx.symbol, orderType, volume, price, slPips, tpPips, "AI Trade");
    
    // Use robust execution with retry
    return ExecuteTradeWithRetry(ctx.symbol, orderType, volume, price, sl, tp, "AI Trade");
}

//+------------------------------------------------------------------+
//| Helper: Execute Trade With Retry                                 |
//+------------------------------------------------------------------+
bool CTradingEngine::ExecuteTradeWithRetry(string symbol, ENUM_ORDER_TYPE order_type, double volume, 
                          double price, double sl, double tp, string comment="") {
    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);
    
    // Get symbol specifications for volume normalization
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    // Check if this is a Deriv synthetic symbol
    bool isSynthetic = (StringFind(symbol, "Volatility") >= 0 || 
                        StringFind(symbol, "Boom") >= 0 ||
                        StringFind(symbol, "Crash") >= 0 ||
                        StringFind(symbol, "Step Index") >= 0 ||
                        StringFind(symbol, "Jump") >= 0 ||
                        StringFind(symbol, "Range Break") >= 0);
    
    // Normalize volume to valid lot size
    if(lotStep > 0) {
        volume = MathFloor(volume / lotStep) * lotStep;
    }
    
    // Ensure volume is at least minLot, at most maxLot
    if(volume < minLot) {
        volume = minLot;
        if(isSynthetic) {
            PrintFormat("[SYNTHETIC] Volume normalized to min lot: %.3f for %s", volume, symbol);
        }
    }
    if(volume > maxLot) {
        volume = maxLot;
    }
    
    // Fill trade request
    request.action = TRADE_ACTION_DEAL;
    request.symbol = symbol;
    request.volume = volume;
    request.type = order_type;
    request.price = price;
    request.sl = sl;
    request.tp = tp;
    request.comment = comment;
    request.magic = 123456; // Default magic number
    request.deviation = 10;
    request.type_filling = ORDER_FILLING_FOK;
    
    // For Deriv synthetics, skip strict OrderCheck and proceed directly
    if(!isSynthetic) {
        // First check order for non-synthetic symbols
        MqlTradeCheckResult checkResult = {0};
        if(!OrderCheck(request, checkResult)) {
            int error = GetLastError();
            Print("[ORDER CHECK FAILED] ", symbol, " Error: ", error, " Retcode: ", checkResult.retcode, " Comment: ", checkResult.comment);
            return false;
        }
    } else {
        // For synthetics, do a soft validation and auto-adjust
        MqlTradeCheckResult checkResult = {0};
        if(!OrderCheck(request, checkResult)) {
            // If volume is invalid, try with adjusted volume
            if(checkResult.retcode == TRADE_RETCODE_INVALID_VOLUME) {
                // Try with minimum lot size
                request.volume = minLot;
                PrintFormat("[SYNTHETIC-FIX] Retrying %s with min lot: %.3f", symbol, minLot);
                
                if(!OrderCheck(request, checkResult)) {
                    // Still failing - print detailed info and skip
                    PrintFormat("[SYNTHETIC-SKIP] %s still failing after volume fix. MinLot=%.3f, MaxLot=%.3f, Step=%.3f", 
                                symbol, minLot, maxLot, lotStep);
                    return false;
                }
            } else {
                // Non-volume error - log and continue anyway for synthetics
                PrintFormat("[SYNTHETIC-WARN] %s OrderCheck warning (retcode=%d), attempting trade anyway...", 
                            symbol, checkResult.retcode);
            }
        }
    }
    
    // Send order with retry logic
    for(int attempt = 0; attempt < 3; attempt++) {
        if(OrderSend(request, result)) {
            if(result.retcode == TRADE_RETCODE_DONE) {
                Print("[SUCCESS] Order executed: ", symbol, " Ticket: ", result.order);
                return true;
            } else {
                Print("[ATTEMPT ", attempt+1, "] OrderSend returned true but retcode: ", result.retcode, " Comment: ", result.comment);
                // Some retcodes might be retryable
                if(result.retcode == TRADE_RETCODE_REQUOTE || result.retcode == TRADE_RETCODE_PRICE_OFF) {
                    Sleep(1000);
                    // Refresh price if needed (simplified here)
                    continue;
                }
                return false; // Non-retryable error
            }
        } else {
            int error = GetLastError();
            Print("[ATTEMPT ", attempt+1, "] OrderSend failed: ", error, " Retcode: ", result.retcode);
            Sleep(1000); // Wait before retry
        }
    }
    
    Print("[FINAL FAILURE] Could not execute order for ", symbol);
    return false;
}

//+------------------------------------------------------------------+
//| Helper: Log Malformed Tick                                       |
//+------------------------------------------------------------------+
void CTradingEngine::LogMalformedTick(CSymbolContext* ctx, MqlTick &tick)
{
    if(ctx == NULL) return;
    
    ctx.malformedTickCount++;
    if(ctx.malformedTickCount % 100 == 0)
    {
        PrintFormat("[TRADING-ENGINE] Warning: %d malformed ticks for %s", ctx.malformedTickCount, ctx.symbol);
    }
}

//+------------------------------------------------------------------+
//| Helper: Update Symbol Market State                               |
//+------------------------------------------------------------------+
void CTradingEngine::UpdateSymbolMarketState(CSymbolContext* ctx)
{
    if(ctx == NULL || ctx.analysis == NULL) return;
    
    // Update market analysis
    ctx.analysis.DetectMarketRegime();
    
    // Update context state
    ctx.regime = ctx.analysis.GetCurrentRegime();
    ctx.regimeStrength = ctx.analysis.GetCurrentTrendStrength();
    ctx.volatility = ctx.analysis.GetCurrentVolatility();
    ctx.atr = ctx.analysis.GetATRValue();
    ctx.momentumScore = ctx.analysis.GetMomentum();
}

//+------------------------------------------------------------------+
//| Helper: Update Symbol Risk Usage                                 |
//+------------------------------------------------------------------+
void CTradingEngine::UpdateSymbolRiskUsage(CSymbolContext* ctx, double riskAmount)
{
    if(ctx == NULL) return;
    
    ctx.symbolDailyRiskUsed += riskAmount;
}
//+------------------------------------------------------------------+
//| Get Symbol Context by Name                                       |
//+------------------------------------------------------------------+
CSymbolContext* CTradingEngine::GetSymbolContext(string symbol)
{
    if(m_symbolContexts == NULL) return NULL;
    
    for(int i = 0; i < m_symbolContexts.Total(); i++)
    {
        CSymbolContext* ctx = (CSymbolContext*)m_symbolContexts.At(i);
        if(ctx != NULL && ctx.symbol == symbol)
            return ctx;
    }
    return NULL;
}
//+------------------------------------------------------------------+
//| Manage Open Positions                                            |
//+------------------------------------------------------------------+
void CTradingEngine::ManageOpenPositions()
{
    if(m_symbolContexts == NULL || m_symbolContexts.Total() == 0)
        return;

    int totalPos = PositionsTotal();
    
    for(int idx = totalPos - 1; idx >= 0; idx--)
    {
        ulong posTicket = PositionGetTicket(idx);
        if(posTicket == 0)
            continue;
            
        if(PositionSelectByTicket(posTicket))
        {
            string posSymbol = PositionGetString(POSITION_SYMBOL);
            double posProfit = PositionGetDouble(POSITION_PROFIT);
            double posVolume = PositionGetDouble(POSITION_VOLUME);
            double posOpenPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double posCurrentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            long posType = PositionGetInteger(POSITION_TYPE);
            long posMagic = PositionGetInteger(POSITION_MAGIC);
            
            // Skip manual trades or trades from other EAs
            // Note: We need to know the magic number. For now, we'll assume we manage all positions
            // or we need to pass the magic number to the engine.
            // Ideally, TradeManager handles magic numbers.
            
            ENUM_ORDER_TYPE orderType = (posType == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
            
            // Get context for symbol
            CSymbolContext* ctx = GetSymbolContext(posSymbol);
            if(ctx == NULL)
                continue;
                
            // Update performance metrics
            if(m_performanceAnalytics != NULL)
            {
                // TODO: We don't record closed trades here yet, but we could update real-time metrics if needed
                // For now, we'll rely on the main loop calling UpdateRealTimeMetrics
            }
            
            // AI-based position management
            double marketData[10];
            marketData[0] = posCurrentPrice;
            marketData[1] = posOpenPrice;
            marketData[2] = posProfit;
            marketData[3] = posVolume;
            marketData[4] = (double)posType;
            marketData[5] = ctx.volatility;
            marketData[6] = ctx.regimeStrength;
            marketData[7] = ctx.lastValidBid;
            marketData[8] = ctx.lastValidAsk;
            marketData[9] = ctx.lastPrice;
            
            // Get AI prediction for position
            double aiPrediction = 0.5;
            if(m_integrationHub != NULL)
            {
                 aiPrediction = m_integrationHub.GetAIPrediction(marketData, 10);
            }
            
            // Dynamic position management based on AI
            bool shouldClose = false;
            
            // 🔥 CRITICAL: Only use AI signals if AI is actually enabled and working
            // If aiPrediction == 0.0, it means AI is disabled (GetAIPrediction returns 0.0 when disabled)
            // Don't close positions based on 0.0 prediction!
            bool aiEnabled = (aiPrediction != 0.0);
            
            // Check for AI-driven exit signals (ONLY if AI is enabled)
            if(aiEnabled && orderType == ORDER_TYPE_BUY)
            {
                if(aiPrediction < 0.3) // Strong sell signal
                {
                    shouldClose = true;
                    PrintFormat("[AI-POSITION] AI suggests closing BUY position for %s (prediction: %.2f)", posSymbol, aiPrediction);
                }
                else if(posProfit > 0 && aiPrediction < 0.45) // Take profit on weakness
                {
                    shouldClose = true;
                    PrintFormat("[AI-POSITION] Taking profit on BUY for %s due to weakening signal", posSymbol);
                }
            }
            else if(aiEnabled) // SELL position (ONLY if AI enabled)
            {
                if(aiPrediction > 0.7) // Strong buy signal
                {
                    shouldClose = true;
                    PrintFormat("[AI-POSITION] AI suggests closing SELL position for %s (prediction: %.2f)", posSymbol, aiPrediction);
                }
                else if(posProfit > 0 && aiPrediction > 0.55) // Take profit on strength
                {
                    shouldClose = true;
                    PrintFormat("[AI-POSITION] Taking profit on SELL for %s due to strengthening signal", posSymbol);
                }
            }
            
            // Risk management overrides
            double accountEquityNow = AccountInfoDouble(ACCOUNT_EQUITY);
            double posRiskPct = (accountEquityNow > 0) ? MathAbs(posProfit) / accountEquityNow : 0.0;
            
            // Hardcoded max risk per trade check (should be configurable)
            if(posRiskPct > 0.04) // 4% max risk per trade hard cap
            {
                shouldClose = true;
                PrintFormat("[RISK] Closing position for %s due to excessive risk (%.2f%%)", posSymbol, posRiskPct * 100);
            }
            
            // Execute close if needed
            if(shouldClose)
            {
                if(m_tradeManager != NULL && m_tradeManager.ClosePosition(posTicket, "AI Signal Close"))
                {
                    PrintFormat("[POSITION] Successfully closed position %I64u for %s", posTicket, posSymbol);
                    
                    // Record closed trade in performance analytics
                    if(m_performanceAnalytics != NULL)
                    {
                        m_performanceAnalytics.RecordClosedTrade(posTicket, posProfit);
                    }
                    
                    // Train AI with outcome
                    double target = posProfit > 0 ? 1.0 : 0.0;
                    if(m_integrationHub != NULL)
                    {
                        m_integrationHub.TrainModels(marketData, target);
                    }
                }
                else
                {
                    PrintFormat("[ERROR] Failed to close position %I64u", posTicket);
                }
            }
            else
            {
                // Update trailing stop based on AI confidence (ONLY if AI enabled)
                if(aiEnabled && posProfit > 0 && aiPrediction > 0.6)
                {
                    double newSL = 0;
                    double pointValue = SymbolInfoDouble(posSymbol, SYMBOL_POINT);
                    double trailDistance = 20 * pointValue; // 20 points trail
                    
                    if(orderType == ORDER_TYPE_BUY)
                    {
                        newSL = posCurrentPrice - trailDistance;
                        double currentSL = PositionGetDouble(POSITION_SL);
                        if(newSL > currentSL)
                        {
                            if(m_tradeManager != NULL)
                            {
                                m_tradeManager.ModifyPosition(posTicket, newSL, PositionGetDouble(POSITION_TP));
                                PrintFormat("[TRAIL] Updated trailing stop for BUY position %I64u", posTicket);
                            }
                        }
                    }
                    else
                    {
                        newSL = posCurrentPrice + trailDistance;
                        double currentSL = PositionGetDouble(POSITION_SL);
                        if(currentSL == 0 || newSL < currentSL)
                        {
                            if(m_tradeManager != NULL)
                            {
                                m_tradeManager.ModifyPosition(posTicket, newSL, PositionGetDouble(POSITION_TP));
                                PrintFormat("[TRAIL] Updated trailing stop for SELL position %I64u", posTicket);
                            }
                        }
                    }
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Helper: Validate Symbol                                          |
//+------------------------------------------------------------------+
bool CTradingEngine::ValidateSymbol(const string symbolName)
{
    if(symbolName == "") return false;
    
    // Check if symbol exists and is selected
    if(!SymbolSelect(symbolName, true))
        return false;
        
    // Check if trading is allowed for this symbol
    ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbolName, SYMBOL_TRADE_MODE);
    if(tradeMode == SYMBOL_TRADE_MODE_DISABLED)
        return false;
        
    // Check for valid price data
    double bid = SymbolInfoDouble(symbolName, SYMBOL_BID);
    double ask = SymbolInfoDouble(symbolName, SYMBOL_ASK);
    
    if(bid <= 0.0 || ask <= 0.0)
        return false;
        
    return true;
}

//+------------------------------------------------------------------+
//| CRITICAL FIX: Count Open Positions for Symbol                    |
//+------------------------------------------------------------------+
int CTradingEngine::CountOpenPositions(string symbol)
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionGetSymbol(i) == symbol)
        {
            count++;
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| CRITICAL FIX: Can Open New Position (Position Limit Validation) |
//+------------------------------------------------------------------+
bool CTradingEngine::CanOpenNewPosition(string symbol)
{
    // MULTI-STRATEGY SCALPING MODE: Increased limits for 4 strategies
    
    // Check 1: Max positions per symbol (allow multiple strategies to trade)
    const int MAX_POSITIONS_PER_SYMBOL = 10;  // 10 positions per symbol (4 strategies * 2-3 each)
    int symbolPositions = CountOpenPositions(symbol);
    
    if(symbolPositions >= MAX_POSITIONS_PER_SYMBOL)
    {
        PrintFormat("[POSITION-LIMIT] %s has %d positions (max: %d) - Multi-strategy limit reached", 
                   symbol, symbolPositions, MAX_POSITIONS_PER_SYMBOL);
        return false;
    }
    
    // Check 2: Max total open positions (prevent portfolio over-exposure)
    const int MAX_TOTAL_POSITIONS = 40;  // 40 total positions across all symbols/strategies
    int totalPositions = PositionsTotal();
    
    if(totalPositions >= MAX_TOTAL_POSITIONS)
    {
        PrintFormat("[POSITION-LIMIT] Total positions: %d (max: %d) - Portfolio limit reached", 
                   totalPositions, MAX_TOTAL_POSITIONS);
        return false;
    }
    
    // Multi-strategy scalping: Position count is the primary control
    return true;
}

#endif // __TRADING_ENGINE_MQH__
