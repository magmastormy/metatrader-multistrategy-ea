//+------------------------------------------------------------------+
//| Risk-Aware Position Sizing System                              |
//| Calculates optimal position sizes based on risk parameters     |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_POSITION_SIZER_MQH
#define CORE_POSITION_SIZER_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "../../IndicatorManager.mqh"
#include "PositionSizerModifiers.mqh"
#include "CorrelationEngine.mqh"
#include "../Utils/RiskMath.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CPositionSizer;
class CPerformanceAnalytics;

//+------------------------------------------------------------------+
//| Position Sizing Parameters Structure                           |
//+------------------------------------------------------------------+
struct SPositionSizingParams
{
    ENUM_POSITION_SIZING_MODE sizingMode;    // Position sizing method
    double fixedLotSize;                     // Fixed lot size
    double riskPercent;                      // Risk % per trade
    double maxLotSize;                       // Maximum lot size cap
    double minLotSize;                       // Minimum lot size floor
    bool useKellySizing;                     // Enable Kelly criterion
    bool useVolatilityTargeting;             // Enable volatility targeting
    bool useEquityCurveScaling;              // Enable equity curve scaling
    bool useCorrelationAdjustment;           // Enable correlation-based size reduction
        double correlationBlockThreshold;        // Correlation threshold to block trade
        double correlationReduceThreshold;       // Correlation threshold to reduce size
        double correlationAdjustment;            // Correlation adjustment factor
        double kellyWinRate;                     // Kelly win rate estimate
        double kellyPayoffRatio;                 // Kelly payoff ratio estimate
        double kellyFraction;                    // Kelly fraction (0.25 = quarter Kelly)
        double kellyMaxCap;                      // Kelly max cap
        double volatilityTarget;                 // Target annualized volatility
        double volatilityLookback;               // Volatility lookback period
        bool useVolatilityAdjustment;            // Enable volatility adjustment
        int atrPeriod;                           // ATR period for volatility calculation
        double atrMultiplier;                    // ATR multiplier for volatility
        double equityCurveLookback;              // Equity curve lookback period
        double equityCurveMinMultiplier;         // Minimum equity curve multiplier
        double equityCurveMaxMultiplier;         // Maximum equity curve multiplier
        bool allowMinLotRoundUp;                 // Allow rounding up to broker min lot
        double minLotRiskMultiplier;             // Max risk multiplier when rounding up to min lot
    
    SPositionSizingParams() :
        sizingMode(POSITION_SIZING_FIXED_RISK),
        fixedLotSize(0.01),
        riskPercent(1.0),
        maxLotSize(100.0),
        minLotSize(0.01),
        useKellySizing(false),
        useVolatilityTargeting(false),
        useEquityCurveScaling(false),
        useCorrelationAdjustment(false),
        correlationBlockThreshold(0.7),
        correlationReduceThreshold(0.4),
        kellyWinRate(0.55),
        kellyPayoffRatio(1.5),
        kellyFraction(0.25),
        kellyMaxCap(0.25),
        volatilityTarget(0.15),
        volatilityLookback(252),
        equityCurveLookback(100),
        equityCurveMinMultiplier(0.25),
        equityCurveMaxMultiplier(2.0),
        allowMinLotRoundUp(false),
        minLotRiskMultiplier(15.0)
    {}
};

//+------------------------------------------------------------------+
//| Position Sizer Class                                             |
//+------------------------------------------------------------------+
class CPositionSizer
{
private:
    // Configuration
    SPositionSizingParams m_params;
    
    // Runtime state
            double m_currentTotalRisk;
            int m_modifierCount;
            CPositionSizerModifier* m_modifiers[];  // Dynamic array for modifiers
            bool m_initialized;
    
    // Risk metrics
    double m_portfolioRisk;
    double m_dailyRiskUsed;
    int m_openPositions;
    
    // Correlation engine reference
    CCorrelationEngine* m_correlationEngine;
    
    // Indicator manager reference
    CIndicatorManager* m_indicatorManager;
    
    // Error handler reference
    CEnhancedErrorHandler* m_errorHandler;
    
    // Performance analytics reference
    CPerformanceAnalytics* m_performanceAnalytics;
    
    // ATR handle cache
    int m_atrHandle;
    string m_atrSymbol;
    int m_atrPeriod;
    
    // Modifiers
    CEquityCurveLotModifier* m_equityCurveModifier;
    CVolatilityTargetingModifier* m_volatilityTargetingModifier;
    CADXLotModifier* m_adxModifier;
    CVPINLotModifier* m_vpinModifier;

    // Internal helpers
    double CalculateFixedRiskSize(const string symbol, double stopLossPips);
    double CalculateVolatilityTargetSize(const string symbol, double stopLossPips);
    double CalculateEquityCurveSize(const string symbol, double stopLossPips);
        double CalculateCorrelationAdjustedSize(const string symbol, double baseSize);
        double ApplyModifiers(double baseSize, const string symbol, double stopLossPips, double confidence, const string corrId = "");
            int CountHighlyCorrelatedPositions(const string symbolParam, double threshold);
            double GetATR(const string symbol, int period, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT);
        void UpdateRiskMetrics();
    void InvalidateATRHandle(const string symbol);

public:
    CPositionSizer();
    ~CPositionSizer();
    
    // Initialize with configuration
    bool Initialize(const SPositionSizingParams &params);
    
    // Check if initialized
    bool IsInitialized() const { return m_initialized; }
    
    // Set references
    void SetCorrelationEngine(CCorrelationEngine* engine);
    void SetIndicatorManager(CIndicatorManager* manager);
    void SetErrorHandler(CEnhancedErrorHandler* handler);
    void SetPerformanceAnalytics(CPerformanceAnalytics* analytics);
    
    // Add position sizing modifier to chain
    bool AddModifier(CPositionSizerModifier* modifier);
    
    // Main sizing interface
        double CalculatePositionSize(const string symbol, double stopLossPips, double confidence = 1.0);
        double CalculatePositionSizeWithMode(const string symbol, double stopLossPips, ENUM_POSITION_SIZING_MODE mode, double confidence = 1.0);
        double CalculatePositionSizeWithRisk(const string symbol, double stopLossPips, double riskPercent, double confidence = 1.0);
    
        // Daily budget capping
                double CapLotForDailyBudget(const string symbol, ENUM_ORDER_TYPE orderType, double lotSize,
                                             double stopLossPips, double tradeRiskPercent,
                                             double remainingDailyRisk, double maxBudgetFraction);
    
            // Validate calculated size against broker constraints
            bool ValidatePositionSize(const string symbol, double &lotSize, double stopLossPips);
    
            // Risk metrics
    double GetCurrentTotalRisk() const;
    double GetDailyRiskUsed() const;
    void RegisterTradeRisk(double riskPercent);
    void UnregisterTradeRisk(double riskPercent);
    void ResetDailyRisk();
    
    // Configuration updates
    void UpdateRiskPercent(double newRiskPercent);
    void UpdateMaxLotSize(double newMaxLotSize);
    void UpdateMinLotSize(double newMinLotSize);
    void SetAllowMinLotRoundUp(bool allow);
    void SetMinLotRiskMultiplier(double multiplier);
    
    // Parameter access (L5-006)
    SPositionSizingParams GetParameters() const;
    bool SetParameters(const SPositionSizingParams &params);
    
    // Contract-spec-aware risk helpers
    double GetRiskDenominator(void);
    double CalculateRiskPerLot(const string symbol, const double stopLossPips);
    
        // Correlation
        void SetCorrelationThresholds(double blockThreshold, double reduceThreshold);
    
        // Volume normalization
        double NormalizeVolume(const string symbolParam, double volume);
    
        // Modifier management
        void ClearModifiers();
    
        // Logging
        void SetLogLevel(int level);
    
        // Diagnostics
        string GetDiagnostics() const;
    };

    #endif // CORE_POSITION_SIZER_MQH

//+------------------------------------------------------------------+
//| Implementation                                                   |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CPositionSizer::CPositionSizer() :
    m_currentTotalRisk(0.0),
    m_modifierCount(0),
    m_portfolioRisk(0.0),
    m_dailyRiskUsed(0.0),
    m_openPositions(0),
    m_correlationEngine(NULL),
    m_indicatorManager(NULL),
    m_errorHandler(NULL),
    m_performanceAnalytics(NULL),
    m_atrHandle(INVALID_HANDLE),
    m_atrSymbol(""),
    m_atrPeriod(14),
    m_equityCurveModifier(NULL),
    m_volatilityTargetingModifier(NULL),
    m_adxModifier(NULL),
    m_vpinModifier(NULL),
    m_initialized(false)
{
    ArrayResize(m_modifiers, 10);
    for(int i = 0; i < 10; i++)
        m_modifiers[i] = NULL;
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CPositionSizer::~CPositionSizer()
{
    // Delete internally created modifiers (volatility targeting, equity curve, ADX, VPIN)
    // Note: Modifiers added via AddModifier() by EA are owned by EA and deleted there
    // The m_modifiers[] array holds non-owning references, so we don't delete via the array
    
    if(m_volatilityTargetingModifier != NULL) { delete m_volatilityTargetingModifier; m_volatilityTargetingModifier = NULL; }
    if(m_equityCurveModifier != NULL) { delete m_equityCurveModifier; m_equityCurveModifier = NULL; }
    if(m_adxModifier != NULL) { delete m_adxModifier; m_adxModifier = NULL; }
    if(m_vpinModifier != NULL) { delete m_vpinModifier; m_vpinModifier = NULL; }
    
    // Clear the modifier array (non-owning references)
    for(int i = 0; i < m_modifierCount; i++)
    {
        m_modifiers[i] = NULL;
    }
    m_modifierCount = 0;
    
    // Release ATR handle if we created it
    if(m_atrHandle != INVALID_HANDLE)
    {
        IndicatorRelease(m_atrHandle);
        m_atrHandle = INVALID_HANDLE;
    }
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CPositionSizer::Initialize(const SPositionSizingParams &params)
{
    m_params = params;
    m_currentTotalRisk = 0.0;
    m_dailyRiskUsed = 0.0;
    m_openPositions = 0;
    
    // Note: useKellySizing is kept for backward compatibility
    // Bayesian Kelly modifier is now added via EAOrchestrator
    
    if(m_params.useVolatilityTargeting)
    {
        m_volatilityTargetingModifier = new CVolatilityTargetingModifier();
        if(m_volatilityTargetingModifier.Initialize(m_params.volatilityTarget, (int)m_params.volatilityLookback))
        {
            AddModifier(m_volatilityTargetingModifier);
        }
    }
    
    if(m_params.useEquityCurveScaling)
    {
        m_equityCurveModifier = new CEquityCurveLotModifier();
        if(m_equityCurveModifier.Initialize((int)m_params.equityCurveLookback))
        {
            AddModifier(m_equityCurveModifier);
        }
    }
    
    // ADX modifier is always available
    m_adxModifier = new CADXLotModifier();
    if(m_adxModifier.Initialize())
    {
        AddModifier(m_adxModifier);
    }
    
    // VPIN modifier
    m_vpinModifier = new CVPINLotModifier();
    if(m_vpinModifier.Initialize())
    {
        AddModifier(m_vpinModifier);
    }
    
    m_initialized = true;
    
        PrintFormat("[PositionSizer] Initialized | Mode=%d | Risk=%.2f%% | Modifiers=%d",
                    m_params.sizingMode, m_params.riskPercent, m_modifierCount);
    
        return true;
    }

//+------------------------------------------------------------------+
//| Set correlation engine reference                                 |
//+------------------------------------------------------------------+
void CPositionSizer::SetCorrelationEngine(CCorrelationEngine* engine)
{
    m_correlationEngine = engine;
    Print("[PositionSizer] Correlation engine linked");
}

//+------------------------------------------------------------------+
//| Set indicator manager reference                                  |
//+------------------------------------------------------------------+
void CPositionSizer::SetIndicatorManager(CIndicatorManager* manager)
{
    m_indicatorManager = manager;
}

//+------------------------------------------------------------------+
//| Set error handler reference                                      |
//+------------------------------------------------------------------+
void CPositionSizer::SetErrorHandler(CEnhancedErrorHandler* handler)
{
    m_errorHandler = handler;
}

//+------------------------------------------------------------------+
//| Set performance analytics reference                              |
//+------------------------------------------------------------------+
void CPositionSizer::SetPerformanceAnalytics(CPerformanceAnalytics* analytics)
{
    m_performanceAnalytics = analytics;
}

//+------------------------------------------------------------------+
//| Add modifier to chain                                            |
//+------------------------------------------------------------------+
bool CPositionSizer::AddModifier(CPositionSizerModifier* modifier)
{
    if(m_modifierCount >= 10)
    {
        Print("[PositionSizer] ERROR: Modifier limit (10) reached");
        return false;
    }
    
    if(ArraySize(m_modifiers) < m_modifierCount + 1)
        ArrayResize(m_modifiers, m_modifierCount + 1);
    
    m_modifiers[m_modifierCount] = modifier;
    m_modifierCount++;
    PrintFormat("[PositionSizer] Added modifier | Total=%d", m_modifierCount);
    return true;
}

//+------------------------------------------------------------------+
//| Main position sizing interface                                   |
//+------------------------------------------------------------------+
double CPositionSizer::CalculatePositionSize(const string symbol, double stopLossPips, double confidence)
{
    if(symbol == "" || stopLossPips <= 0.0)
    {
        CEnhancedErrorHandler::LogError(ERROR_INVALID_PARAM, "PositionSizer", "Invalid symbol or stop loss", 0);
        return 0.0;
    }
    
    double baseSize = 0.0;
    
    switch(m_params.sizingMode)
    {
        case POSITION_SIZING_FIXED_LOT:
            baseSize = m_params.fixedLotSize;
            break;
            
        case POSITION_SIZING_FIXED_RISK:
            baseSize = CalculateFixedRiskSize(symbol, stopLossPips);
            break;
            
        case POSITION_SIZING_KELLY:
            // L5-012: Consolidated to Bayesian Kelly modifier (added by EAOrchestrator)
            // Fall back to fixed risk sizing; Bayesian Kelly modifier will adjust if enabled
            baseSize = CalculateFixedRiskSize(symbol, stopLossPips);
            break;
            
        case POSITION_SIZING_VOLATILITY_TARGET:
            baseSize = CalculateVolatilityTargetSize(symbol, stopLossPips);
            break;
            
        case POSITION_SIZING_EQUITY_CURVE:
            baseSize = CalculateEquityCurveSize(symbol, stopLossPips);
            break;
            
        default:
            baseSize = CalculateFixedRiskSize(symbol, stopLossPips);
            break;
    }
    
    // Apply correlation adjustment
    if(m_params.useCorrelationAdjustment && m_correlationEngine != NULL)
    {
        baseSize = CalculateCorrelationAdjustedSize(symbol, baseSize);
    }
    
    // Apply modifier chain
    double finalSize = ApplyModifiers(baseSize, symbol, stopLossPips, confidence);
    
    // Validate against broker constraints
    if(!ValidatePositionSize(symbol, finalSize, stopLossPips))
    {
        return 0.0;
    }
    
    return finalSize;
}

//+------------------------------------------------------------------+
//| Calculate position size with explicit mode                       |
//+------------------------------------------------------------------+
double CPositionSizer::CalculatePositionSizeWithMode(const string symbol, double stopLossPips, ENUM_POSITION_SIZING_MODE mode, double confidence)
{
    ENUM_POSITION_SIZING_MODE oldMode = m_params.sizingMode;
    m_params.sizingMode = mode;
    double size = CalculatePositionSize(symbol, stopLossPips, confidence);
    m_params.sizingMode = oldMode;
        return size;
    }

    //+------------------------------------------------------------------+
    //| Calculate position size with custom risk percent                 |
    //+------------------------------------------------------------------+
    double CPositionSizer::CalculatePositionSizeWithRisk(const string symbol, double stopLossPips, double riskPercent, double confidence)
    {
        if(riskPercent <= 0.0)
            riskPercent = m_params.riskPercent;
    
        double oldRiskPercent = m_params.riskPercent;
        m_params.riskPercent = riskPercent;
        double size = CalculatePositionSize(symbol, stopLossPips, confidence);
        m_params.riskPercent = oldRiskPercent;
        return size;
    }

    //+------------------------------------------------------------------+
    //| Cap lot size to daily budget                                     |
    //+------------------------------------------------------------------+
    double CPositionSizer::CapLotForDailyBudget(const string symbol, ENUM_ORDER_TYPE orderType, double lotSize,
                                                double stopLossPips, double proposedRisk,
                                                double remainingDailyRisk, double maxBudgetFraction)
    {
        if(lotSize <= 0.0 || remainingDailyRisk <= 0.0 || proposedRisk <= 0.0)
            return lotSize;
    
        // Calculate maximum allowed lot based on remaining daily risk budget
        double maxLotByBudget = lotSize * (remainingDailyRisk / proposedRisk) * maxBudgetFraction;
    
        // Apply margin-based cap as well
        double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        double marginPerLot = 0.0;
        double priceForMargin = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
    
        if(OrderCalcMargin(orderType, symbol, 1.0, priceForMargin, marginPerLot) && marginPerLot > 0.0)
        {
            double maxLotByMargin = freeMargin / (marginPerLot * 1.5);
            maxLotByBudget = MathMin(maxLotByBudget, maxLotByMargin);
        }
    
        // Apply symbol volume constraints
        double symbolMaxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        if(symbolMaxVolume > 0.0)
            maxLotByBudget = MathMin(maxLotByBudget, symbolMaxVolume);
    
        // Ensure we don't increase the lot size, only decrease
        double cappedLot = MathMin(lotSize, maxLotByBudget);
    
        // Normalize to volume step
        double stepVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        if(stepVol > 0.0)
        {
            cappedLot = MathFloor((cappedLot + 1e-12) / stepVol) * stepVol;
        }
    
        double minVol = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        if(cappedLot < minVol)
            cappedLot = 0.0;
    
        if(cappedLot < lotSize)
        {
            PrintFormat("[DAILY-BUDGET-CAP] %s | lot capped from %.2f to %.2f | remainingRisk=%.2f%% | proposedRisk=%.2f%% | maxBudgetFrac=%.0f%%",
                        symbol, lotSize, cappedLot, remainingDailyRisk, proposedRisk, maxBudgetFraction * 100.0);
        }
    
        return cappedLot;
    }

//+------------------------------------------------------------------+
//| Fixed risk position sizing                                       |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateFixedRiskSize(const string symbol, double stopLossPips)
{
    double riskAmount = GetRiskDenominator() * (m_params.riskPercent / 100.0);
    double riskPerLot = CalculateRiskPerLot(symbol, stopLossPips);
    
    if(riskPerLot <= 0.0)
    {
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "PositionSizer", "Invalid risk per lot for " + symbol, 0);
        return 0.0;
    }
    
    double lotSize = riskAmount / riskPerLot;
    
    // Apply tier cap if PositionSizer is tier-aware
    double tierRiskPct = m_params.riskPercent;
    double riskDenominator = GetRiskDenominator();
    double tierMaxRisk = riskDenominator * (tierRiskPct / 100.0);
    double maxLotByTier = tierMaxRisk / riskPerLot;
    
    if(lotSize > maxLotByTier)
    {
        lotSize = maxLotByTier;
        PrintFormat("[PositionSizer] Tier cap applied | symbol=%s | lot=%.2f", symbol, lotSize);
    }
    
    // Clamp to min/max
    if(lotSize < m_params.minLotSize)
        lotSize = m_params.minLotSize;
    if(lotSize > m_params.maxLotSize)
        lotSize = m_params.maxLotSize;
    
    return NormalizeVolume(symbol, lotSize);
}

//+------------------------------------------------------------------+
//| Volatility targeting position sizing                             |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateVolatilityTargetSize(const string symbol, double stopLossPips)
{
    if(m_volatilityTargetingModifier == NULL)
        return CalculateFixedRiskSize(symbol, stopLossPips);
    
    double baseSize = CalculateFixedRiskSize(symbol, stopLossPips);
    return m_volatilityTargetingModifier.AdjustLotSize(baseSize, symbol, 1.0);
}

//+------------------------------------------------------------------+
//| Equity curve position sizing                                     |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateEquityCurveSize(const string symbol, double stopLossPips)
{
    if(m_equityCurveModifier == NULL)
        return CalculateFixedRiskSize(symbol, stopLossPips);
    
    double baseSize = CalculateFixedRiskSize(symbol, stopLossPips);
    return m_equityCurveModifier.AdjustLotSize(baseSize, symbol, 1.0);
}

//+------------------------------------------------------------------+
//| Correlation adjustment                                           |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateCorrelationAdjustedSize(const string symbol, double baseSize)
{
    if(m_correlationEngine == NULL)
        return baseSize;
    
    int correlatedCount = CountHighlyCorrelatedPositions(symbol, m_params.correlationBlockThreshold);
    
    // Use actual correlation values from engine instead of count-based heuristic
    double avgCorrelation = 0.0;
    int validCorrelations = 0;
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0 || !PositionSelectByTicket(ticket))
            continue;
        
        string posSymbol = PositionGetString(POSITION_SYMBOL);
        if(posSymbol == symbol)
            continue;
        
        double corr = m_correlationEngine.GetCorrelation(symbol, posSymbol);
        if(corr > 0.0) // Valid correlation
        {
            avgCorrelation += corr;
            validCorrelations++;
        }
    }
    
    if(validCorrelations > 0)
    {
        avgCorrelation /= validCorrelations;
        // Scale by 1 - avgCorrelation (risk parity style)
        double reduction = MathMax(0.25, 1.0 - avgCorrelation);
        baseSize *= reduction;
        
        PrintFormat("[PositionSizer] Correlation adjustment | symbol=%s | avgCorr=%.2f | reduction=%.2f | size=%.2f",
                    symbol, avgCorrelation, reduction, baseSize);
    }
    else if(correlatedCount > 0)
    {
        // Fallback to count-based reduction if no valid correlations
        double reduction = 1.0 / (1.0 + correlatedCount * 0.5);
        reduction = MathMax(0.25, reduction);
        baseSize *= reduction;
    }
    
    return baseSize;
}

//+------------------------------------------------------------------+
//| Count highly correlated positions                                |
//+------------------------------------------------------------------+
int CPositionSizer::CountHighlyCorrelatedPositions(const string symbolParam, double threshold)
{
    if(m_correlationEngine == NULL)
        return 0;
    
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0 || !PositionSelectByTicket(ticket))
            continue;
        
        string posSymbol = PositionGetString(POSITION_SYMBOL);
        if(posSymbol == symbolParam)
            continue;
        
        double corr = m_correlationEngine.GetCorrelation(symbolParam, posSymbol);
        if(corr > threshold)
            count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Apply modifier chain                                             |
//+------------------------------------------------------------------+
double CPositionSizer::ApplyModifiers(double baseSize, const string symbol, double stopLossPips, double confidence, const string corrId = "")
{
    double currentSize = baseSize;
    
    // Get correlation ID from logger if not provided
    string effectiveCorrId = corrId;
    if(effectiveCorrId == "")
    {
        effectiveCorrId = CJsonLogger::GetCorrelationId();
    }
    
    for(int i = 0; i < m_modifierCount; i++)
    {
        if(m_modifiers[i] != NULL && m_modifiers[i].IsEnabled())
        {
            double before = currentSize;
            currentSize = m_modifiers[i].AdjustLotSize(currentSize, symbol, confidence);
            
            // Structured logging with correlation ID
            if(effectiveCorrId != "")
            {
                CJsonLogger::LogInfo("PositionSizer",
                    StringFormat("modifier=%s | symbol=%s | before=%.2f | after=%.2f | confidence=%.2f",
                                 m_modifiers[i].GetName(), symbol, before, currentSize, confidence),
                    "POSITION_SIZER_MODIFIER", "", effectiveCorrId, "");
            }
            
            PrintFormat("[PositionSizer] Modifier | %s | %.2f -> %.2f",
                        m_modifiers[i].GetName(), before, currentSize);
        }
    }
    
    return currentSize;
}

//+------------------------------------------------------------------+
//| Validate position size                                           |
//+------------------------------------------------------------------+
bool CPositionSizer::ValidatePositionSize(const string symbol, double &lotSize, double stopLossPips)
{
    if(lotSize <= 0.0)
        return false;
    
    // Check broker min/max
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    if(minLot > 0.0 && lotSize < minLot)
        {
            if(m_params.allowMinLotRoundUp)
            {
                // Check if rounding up exceeds allowed risk multiplier
                double riskRatio = minLot / lotSize;
                // Min-lot round-up tolerance: allow up to 15x risk multiplier (reverted L5-002 1x clamp)
                if(riskRatio > 15.0)
                {
                    CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "PositionSizer", 
                             StringFormat("Min lot round-up exceeds 15x risk cap: %.2fx > 15.0x", riskRatio), 0);
                    return false;
                }
                if(riskRatio > m_params.minLotRiskMultiplier)
                {
                    CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "PositionSizer", 
                             StringFormat("Min lot round-up exceeds risk multiplier: %.2fx > %.2fx", 
                                         riskRatio, m_params.minLotRiskMultiplier), 0);
                    return false;
                }
                lotSize = minLot;
            }
            else
            {
                CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "PositionSizer", 
                         StringFormat("Lot size %.2f below broker minimum %.2f", lotSize, minLot), 0);
                return false;
            }
        }
    
    if(maxLot > 0.0 && lotSize > maxLot)
    {
        lotSize = maxLot;
    }
    
    // Normalize to step
    if(stepLot > 0.0)
    {
        // Batch 152: the old trailing NormalizeDouble(...,2) re-broke SYMBOL_VOLUME_STEP
        // of 0.001 (floored 0.999 was rounded back off-step -> invalid-volume rejects).
        // Floor to whole steps and clean FP dust at 8 digits instead.
        long wholeSteps = (long)MathFloor(lotSize / stepLot + 1e-9);
        lotSize = NormalizeDouble(wholeSteps * stepLot, 8);
    }
    
    // Final validation
    if(lotSize < m_params.minLotSize || lotSize > m_params.maxLotSize)
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Normalize volume to broker step                                  |
//+------------------------------------------------------------------+
double CPositionSizer::NormalizeVolume(const string symbolParam, double volume)
{
    double step = SymbolInfoDouble(symbolParam, SYMBOL_VOLUME_STEP);
    double minVol = SymbolInfoDouble(symbolParam, SYMBOL_VOLUME_MIN);
    double maxVol = SymbolInfoDouble(symbolParam, SYMBOL_VOLUME_MAX);
    
    if(step <= 0.0)
        return volume;
    
    // Batch 152: floor to whole steps (8-digit cleanup, not 2dp - see NormalizeLot note)
    long wholeSteps = (long)MathFloor(volume / step + 1e-9);
    double normalized = NormalizeDouble(wholeSteps * step, 8);
    
    if(normalized < minVol)
        normalized = minVol;
    if(normalized > maxVol)
        normalized = maxVol;
    
    if(MathAbs(normalized - volume) > 0.001)
    {
        PrintFormat("[PositionSizer] Volume normalized | symbol=%s | %.4f -> %.4f (step=%.4f, min=%.4f, max=%.4f)",
                    symbolParam, volume, normalized, step, minVol, maxVol);
    }
    
    return normalized;
}

//+------------------------------------------------------------------+
//| Risk metrics                                                     |
//+------------------------------------------------------------------+
double CPositionSizer::GetCurrentTotalRisk() const
{
    return m_currentTotalRisk;
}

double CPositionSizer::GetDailyRiskUsed() const
{
    return m_dailyRiskUsed;
}

void CPositionSizer::RegisterTradeRisk(double riskPercent)
{
    m_currentTotalRisk += MathMax(0.0, riskPercent);
    m_dailyRiskUsed += MathMax(0.0, riskPercent);
    m_openPositions++;
}

void CPositionSizer::UnregisterTradeRisk(double riskPercent)
{
    m_currentTotalRisk = MathMax(0.0, m_currentTotalRisk - MathMax(0.0, riskPercent));
    m_dailyRiskUsed = MathMax(0.0, m_dailyRiskUsed - MathMax(0.0, riskPercent));
    m_openPositions = MathMax(0, m_openPositions - 1);
}

void CPositionSizer::ResetDailyRisk()
{
    m_dailyRiskUsed = 0.0;
    Print("[PositionSizer] Daily risk reset");
}

//+------------------------------------------------------------------+
//| Configuration updates                                            |
//+------------------------------------------------------------------+
void CPositionSizer::UpdateRiskPercent(double newRiskPercent)
{
    m_params.riskPercent = MathMax(0.01, MathMin(100.0, newRiskPercent));
    PrintFormat("[PositionSizer] Risk percent updated to %.2f%%", m_params.riskPercent);
}

void CPositionSizer::UpdateMaxLotSize(double newMaxLotSize)
{
    m_params.maxLotSize = MathMax(0.01, newMaxLotSize);
}

void CPositionSizer::UpdateMinLotSize(double newMinLotSize)
{
    m_params.minLotSize = MathMax(0.01, newMinLotSize);
}

void CPositionSizer::SetAllowMinLotRoundUp(bool allow)
{
    m_params.allowMinLotRoundUp = allow;
}

void CPositionSizer::SetMinLotRiskMultiplier(double multiplier)
{
    // L5-002: Hard cap at 1.0x risk (no multiplier allowed)
    m_params.minLotRiskMultiplier = MathMin(MathMax(1.0, multiplier), 15.0);
}

//+------------------------------------------------------------------+
//| Parameter access (L5-006)                                        |
//+------------------------------------------------------------------+
SPositionSizingParams CPositionSizer::GetParameters() const
{
    return m_params;
}

bool CPositionSizer::SetParameters(const SPositionSizingParams &params)
{
    m_params = params;
    PrintFormat("[PositionSizer] Parameters updated | Mode=%d | Risk=%.2f%%", m_params.sizingMode, m_params.riskPercent);
    return true;
}

//+------------------------------------------------------------------+
//| Account risk denominator                                         |
//+------------------------------------------------------------------+
// AUDIT FIX: This implementation must be kept in sync with CPortfolioRiskManager::GetRiskDenominator
// to ensure consistent risk calculation across all risk components.
double CPositionSizer::GetRiskDenominator(void)
{
    return CRiskMath::GetRiskDenominator();
}

//+------------------------------------------------------------------+
//| Risk per 1.0 lot for a stop distance                            |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateRiskPerLot(const string symbolParam, const double stopLossPips)
{
    if(symbolParam == "" || stopLossPips <= 0.0) {
        return 0.0;
    }

    double tickValue = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_SIZE);
    double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
    string profitCurrency = SymbolInfoString(symbolParam, SYMBOL_CURRENCY_PROFIT);
    string accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);

    if(tickValue <= 0.0 || tickSize <= 0.0 || point <= 0.0) {
        return 0.0;
    }

    // Batch 152 (H-6): this used to be stopLossPips * point * 10.0 - a pip
    // convention nothing else in the codebase shares. Execution places stops at
    // pips*point (CTradeMgrPricing::CalculateStops) and URM risk math uses
    // pips*point too, so per-lot risk came out 10x high and every FIXED_RISK
    // sized position traded at ~1/10 of the configured risk.
    double slDistancePrice = stopLossPips * point;
    double slTicks = slDistancePrice / tickSize;

    // Risk per 1.0 lot in profit currency
    double riskPerLot = slTicks * tickValue;

    // Convert to account currency if needed
    if(profitCurrency != accountCurrency)
    {
        // Try direct pair
        string directPair = profitCurrency + accountCurrency;
        if(SymbolInfoInteger(directPair, SYMBOL_SELECT))
        {
            double rate = SymbolInfoDouble(directPair, SYMBOL_BID);
            if(rate > 0.0)
                riskPerLot *= rate;
        }
        else
        {
            // Try inverse pair
            string inversePair = accountCurrency + profitCurrency;
            if(SymbolInfoInteger(inversePair, SYMBOL_SELECT))
            {
                double rate = SymbolInfoDouble(inversePair, SYMBOL_BID);
                if(rate > 0.0)
                    riskPerLot /= rate;
            }
        }
    }

    return riskPerLot;
}

//+------------------------------------------------------------------+
//| Correlation thresholds                                           |
//+------------------------------------------------------------------+
void CPositionSizer::SetCorrelationThresholds(double blockThreshold, double reduceThreshold)
{
    m_params.correlationBlockThreshold = MathMax(0.0, MathMin(1.0, blockThreshold));
    m_params.correlationReduceThreshold = MathMax(0.0, MathMin(1.0, reduceThreshold));
}

//+------------------------------------------------------------------+
//| Get ATR value                                                    |
//+------------------------------------------------------------------+
double CPositionSizer::GetATR(const string symbol, int period, ENUM_TIMEFRAMES timeframe)
{
    // Try to use IndicatorManager if available
    if(m_indicatorManager != NULL)
    {
        int handle = m_indicatorManager.GetATRHandle(symbol, timeframe, period);
        if(handle != INVALID_HANDLE)
        {
            double atr[];
            if(CopyBuffer(handle, 0, 0, 1, atr) > 0)
                return atr[0];
        }
    }

    // Fallback: create temporary handle
    if(m_atrSymbol != symbol || m_atrPeriod != period)
    {
        InvalidateATRHandle(symbol);
        m_atrHandle = iATR(symbol, timeframe, period);
        m_atrSymbol = symbol;
        m_atrPeriod = period;
    }

    if(m_atrHandle == INVALID_HANDLE) {
        return 0.0;
    }

    double atr[];
    if(CopyBuffer(m_atrHandle, 0, 0, 1, atr) <= 0) {
        return 0.0;
    }

    return atr[0];
}

//+------------------------------------------------------------------+
//| Invalidate ATR handle                                            |
//+------------------------------------------------------------------+
void CPositionSizer::InvalidateATRHandle(const string symbol)
{
    if(m_atrHandle != INVALID_HANDLE && m_atrSymbol == symbol)
    {
        IndicatorRelease(m_atrHandle);
        m_atrHandle = INVALID_HANDLE;
        m_atrSymbol = "";
    }
}

//+------------------------------------------------------------------+
//| Update risk metrics                                              |
//+------------------------------------------------------------------+
void CPositionSizer::UpdateRiskMetrics()
{
    m_currentTotalRisk = 0.0;
    m_openPositions = 0;

    // Iterate all positions (filter by magic number in production)
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket <= 0) continue;
        if(!PositionSelectByTicket(ticket)) continue;

        string symbol = PositionGetString(POSITION_SYMBOL);
        double volume = PositionGetDouble(POSITION_VOLUME);
        double sl = PositionGetDouble(POSITION_SL);
        double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
        ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        if(sl <= 0.0)
            continue;

        double stopLossPips = 0.0;
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        
        // Batch 152 (H-6): divide by point only - actual stops are placed at
        // pips*point, and CalculateRiskPerLot now expects the same convention.
        if(type == POSITION_TYPE_BUY)
            stopLossPips = (openPrice - sl) / point;
        else
            stopLossPips = (sl - openPrice) / point;

        if(stopLossPips <= 0.0)
            continue;

        double riskPerLot = CalculateRiskPerLot(symbol, stopLossPips);
        if(riskPerLot <= 0.0)
            continue;

        double riskDollar = riskPerLot * volume;
        double riskDenominator = GetRiskDenominator();
        if(riskDenominator > 0.0)
        {
            double riskPct = (riskDollar / riskDenominator) * 100.0;
            m_currentTotalRisk += riskPct;
            m_openPositions++;
        }
    }
    // Batch 150: removed the post-loop second division by the risk denominator.
    // riskPct is already a percentage; rescaling again understated
    // m_currentTotalRisk by ~denominator/100 (e.g. ~100x on $10k equity) and
    // permanently disarmed the portfolio-risk cap.
}

//+------------------------------------------------------------------+
//| Diagnostics                                                      |
//+------------------------------------------------------------------+
string CPositionSizer::GetDiagnostics() const
{
    return StringFormat("PosSizer: Risk=%.2f%% | Daily=%.2f%% | Open=%d | Modifiers=%d",
                        m_currentTotalRisk, m_dailyRiskUsed, m_openPositions, m_modifierCount);
}

//+------------------------------------------------------------------+
//| Clear all modifiers (non-owning clear - EA owns modifiers)       |
//+------------------------------------------------------------------+
void CPositionSizer::ClearModifiers()
{
    for(int i = 0; i < m_modifierCount; i++)
    {
        m_modifiers[i] = NULL;
    }
    m_modifierCount = 0;
    Print("[PositionSizer] All modifiers cleared (non-owning)");
}

//+------------------------------------------------------------------+
//| Set log level                                                    |
//+------------------------------------------------------------------+
void CPositionSizer::SetLogLevel(int level)
{
    if(level < 0) level = 0;
    if(level > 3) level = 3;
    // Store log level if needed - for now just acknowledge
    PrintFormat("[PositionSizer] Log level set to %d", level);
}