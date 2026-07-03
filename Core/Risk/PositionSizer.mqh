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
    double riskPercent;                      // Blueprint 10.4: 0-100 scale (e.g., 1.0 = 1%)
    int atrPeriod;                           // ATR period for volatility
    double atrMultiplier;                    // ATR multiplier
    double maxLotSize;                       // Maximum allowed lot size
    double minLotSize;                       // Minimum allowed lot size
    double correlationAdjustment;            // Correlation adjustment factor
    bool useVolatilityAdjustment;            // Use volatility adjustment
    bool useCorrelationAdjustment;           // Use correlation adjustment
};

//+------------------------------------------------------------------+
//| Position Sizer Class                                           |
//+------------------------------------------------------------------+
class CPositionSizer : public CEnhancedErrorHandler
{
private:
    SPositionSizingParams m_params;
    bool m_initialized;
    double m_lastCalculatedSize;
    string m_lastSymbol;
    datetime m_lastCalculation;
    
    // Risk metrics
    double m_currentTotalRisk;
    double m_maxAllowedRisk;
    int m_activePositions;
    
    // Indicator handles
    int m_atrHandle;
    
    // FIX: Injected error handler pointer for logging
    CEnhancedErrorHandler* m_errorHandler;

    // Log level for gating diagnostic string building
    int m_logLevel;

    // FIX: Correlation engine pointer �?delegates to CCorrelationEngine instead of own Pearson
    CCorrelationEngine* m_correlationEngine;

    // Anti-Martingale momentum scaling (Blueprint Section 4.3)
    CPerformanceAnalytics* m_perfAnalytics;
    
    // Kelly Criterion statistics
    double m_kellyWinRate;           // Rolling win rate
    double m_kellyAvgWin;            // Average winning trade profit
    double m_kellyAvgLoss;           // Average losing trade loss
    int m_kellyTradeCount;           // Number of trades in rolling window
    double m_kellyFraction;          // Fraction of Kelly to use (half-Kelly)
    double m_kellyMaxCap;            // Maximum fraction of account to risk
    double m_kellyWinHistory[];      // Rolling window of win profits
    double m_kellyLossHistory[];     // Rolling window of loss amounts
    int m_kellyHistoryIndex;         // Circular buffer index
    int m_kellyHistorySize;          // Current filled size of circular buffer
    
    // Equity compounding
    double m_startingEquity;                  // Equity at EA start
    double m_compoundingAggressiveness;       // How aggressively to compound (0=none, 1=full)
    double m_drawdownScalingFactor;           // How much to reduce on drawdown
    bool m_enableCompounding;                 // Enable/disable compounding

    // Min-lot round-up policy (fixes "Lot size below minimum" rejection)
    bool   m_allowMinLotRoundUp;       // Allow rounding up to broker min lot when calculated lot is below min
    double m_minLotRiskMultiplier;     // Max risk multiplier for round-up (e.g., 2.0 = risk at min lot must be <= 2x intended)

    // Pluggable modifier chain (Phase 5: Position Sizer Consolidation)
    CPositionSizerModifier* m_modifiers[5];
    int m_modifierCount;
    
public:
    // Constructor
    CPositionSizer(void);
    
    // Destructor
    ~CPositionSizer(void);
    
    // DEPRECATED: Use CalculateSize() instead �?avoids shared mutable state
    // Initialize with parameters
    bool SetParameters(const SPositionSizingParams &params);
    
void SetErrorHandler(CEnhancedErrorHandler* handler) { m_errorHandler = handler; }

    // Set log level for gating diagnostic string building
    void SetLogLevel(const int level) { m_logLevel = MathMax(0, MathMin(4, level)); }

    // Set min-lot round-up policy (fixes "Lot size below minimum" rejection)
    void SetAllowMinLotRoundUp(bool allow) { m_allowMinLotRoundUp = allow; }
    void SetMinLotRiskMultiplier(double multiplier) { m_minLotRiskMultiplier = MathMax(1.0, multiplier); }

    // Set correlation engine for delegated correlation calculation
    void SetCorrelationEngine(CCorrelationEngine* engine) { m_correlationEngine = engine; }

    // Set performance analytics for anti-Martingale momentum scaling
    void SetPerformanceAnalytics(CPerformanceAnalytics* pa) { m_perfAnalytics = pa; }
    
    // DEPRECATED: Use CalculateSize() instead �?avoids shared mutable state
    // Calculate optimal position size with enhanced risk management
    double CalculateOptimalPositionSize(const string symbol,
                                       const ENUM_ORDER_TYPE orderType,
                                       const double stopLossPips,
                                       const double confidence = 1.0);

    // Stateless position size calculation �?all per-call parameters passed directly.
    // This is the preferred API. SetParameters+CalculateOptimalPositionSize is deprecated.
    // Produces IDENTICAL results to SetParameters(riskPercent=X)+CalculateOptimalPositionSize
    // without mutating shared state, so it is safe to call for multiple symbols per tick.
    double CalculateSize(const string symbol,
                         const ENUM_ORDER_TYPE orderType,
                         const double slDistancePips,
                         const double riskPercent,
                         const double confidence = 1.0);
    double CalculateSizeWithTierCap(const string symbol,
                         const ENUM_ORDER_TYPE orderType,
                         const double slDistancePips,
                         const double riskPercent,
                         const double confidence,
                         double tierRiskPerTradePct);

    // Issue 5: Cap lot size so a single trade cannot consume more than maxBudgetFraction
    // of the remaining daily risk budget. Returns the (possibly reduced) lot size.
    double CapLotForDailyBudget(const string symbol,
                                const ENUM_ORDER_TYPE orderType,
                                const double lotSize,
                                const double slDistancePips,
                                const double riskPercent,
                                const double remainingDailyRiskPct,
                                const double maxBudgetFraction = 0.30);
    
    // Calculate base position size according to sizing mode
    double CalculateBasePositionSize(const string symbol, const double stopLossPips);

    // Private: base size with explicit risk percent
    double CalculateBasePositionSizeWithRisk(const string symbol, const double stopLossPips, const double riskPercent);

    // Private: stateless core calculation �?accepts riskPercent as parameter
    double CalculateOptimalPositionSizeCore(const string symbol,
                                             const ENUM_ORDER_TYPE orderType,
                                             const double stopLossPips,
                                             const double riskPercent,
                                             const double confidence);
    
    // Calculate position size based on risk percentage (see implementation below)
    double CalculateRiskBasedSize(const string symbol,
                                 const double stopLossPips,
                                 const double riskPercent);
    
    // Calculate position size based on volatility (ATR)
    double CalculateVolatilityBasedSize(const string symbol, 
                                       const double baseSize);
    
    // Calculate correlation-adjusted position size
    double CalculateCorrelationAdjustedSize(const string symbol, 
                                           const double baseSize);
    
    // Calculate correlation between two symbols using historical data
    double CalculateCorrelation(const string symbol1, const string symbol2, int period);
    
    // Validate position size against account limits
    double ValidatePositionSize(const string symbol, 
                               const double proposedSize);
    
    // Get current total risk exposure
    double GetCurrentTotalRisk(void) const { return m_currentTotalRisk; }
    
    // Update risk metrics
    void UpdateRiskMetrics(void);
    
    // Get position sizing parameters
    SPositionSizingParams GetParameters(void) const { return m_params; }
    
    // Check if position sizer is initialized
    bool IsInitialized(void) const { return m_initialized; }
    
    // Get last calculated size for debugging
    double GetLastCalculatedSize(void) const { return m_lastCalculatedSize; }
    
    // Calculate minimum viable lot size
    double CalculateMinViableSize(const string symbol);
    
    bool IsHealthy(void) const { return m_initialized && m_lastCalculatedSize >= MIN_LOT_SIZE; }
    
    double GetSafePositionSize(const string symbol, const ENUM_ORDER_TYPE orderType,
                               const double stopLossPips, const double confidence = 1.0)
    {
        if(!IsHealthy())
        {
            Print("[POSITION-SIZER] Fallback to min lot for ", symbol);
            double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
            return (minLot > 0) ? minLot : MIN_LOT_SIZE;
        }
        return CalculateOptimalPositionSize(symbol, orderType, stopLossPips, confidence);
    }
    
    // Calculate maximum safe lot size based on margin
    double CalculateMaxSafeSize(const string symbol);
    
    // Normalize volume to symbol's step size
    double NormalizeVolume(const string symbol, const double volume);
    
    // Calculate tick value for the symbol
    double GetTickValue(const string symbol);
    
    // Get symbol point value
    double GetSymbolPoint(const string symbol);

    // Contract-spec-aware risk helpers
    double GetRiskDenominator(void);
    double CalculateRiskPerLot(const string symbol, const double stopLossPips);
    
    // Check margin requirements with enhanced validation
    bool CheckMarginRequirements(const string symbolParam, const ENUM_ORDER_TYPE orderType, const double lots)
    {
       if(!SymbolSelect(symbolParam, true))
       {
          LogError(ERROR_WARNING, "PositionSizer", "Symbol not selected: " + symbolParam, 0);
          return false;
       }
 
       // Get required margin
       double marginRequired = 0.0;
       double price = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbolParam, SYMBOL_ASK) : SymbolInfoDouble(symbolParam, SYMBOL_BID);
        
        if(!OrderCalcMargin(orderType, symbolParam, lots, price, marginRequired))
        {
            LogError(ERROR_WARNING, "PositionSizer", "Failed to calculate margin requirement", GetLastError());
            return false;
        }
        
        // Get free margin
        double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        
        // Safety check - ensure we have at least 20% buffer
        if(marginRequired > freeMargin * 0.80)
        {
            LogError(ERROR_WARNING, "PositionSizer", "Insufficient margin. Required: " + 
                     DoubleToString(marginRequired, 2) + 
                     ", Free: " + DoubleToString(freeMargin, 2), 0);
            return false;
        }
        
        return true;
    }
    
    // Calculate margin required for a given lot size
    double CalculateMarginRequirement(const string symbol, const double lotSize);
    
    // Apply risk limits to position size
    double ApplyRiskLimits(const double proposedSize, const double maxRisk);
    
    // Get ATR value for volatility calculation
    double GetATR(const string symbol, const int period);
    
    // Calculate correlation with existing positions
    double CalculatePortfolioCorrelation(const string symbol);
    
    // Validate symbol for trading
    bool ValidateSymbol(const string symbol);
    
    // Log position sizing decision
    void LogSizingDecision(const string symbol, const double size, const string reason);

    // Kelly Criterion methods
    void UpdateKellyStats(bool win, double profit, double loss);
    double CalculateKellyFraction(void);

    // Equity compounding methods
    void InitializeCompounding(void);
    double CalculateCompoundingMultiplier(void);

    // Pluggable modifier chain (Phase 5)
    void AddModifier(CPositionSizerModifier* modifier);
    int GetModifierCount(void) const { return m_modifierCount; }

    // Error logging method with proper signature
    void LogError(ENUM_ERROR_SEVERITY severity, string component, string message, int errorCode = 0)
    {
        SErrorContext context;
        context.component = component;
        context.operation = "PositionSizer";
        context.symbol = "";
        context.errorCode = errorCode;
        context.additionalInfo = message;
        context.timestamp = TimeCurrent();
        context.severity = severity;

        CEnhancedErrorHandler::LogError(severity, context);
    }
};

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CPositionSizer::CPositionSizer(void)
{
    m_initialized = false;
    m_lastCalculatedSize = 0.0;
    m_lastSymbol = "";
    m_lastCalculation = 0;
    m_currentTotalRisk = 0.0;
    m_maxAllowedRisk = MAX_TOTAL_RISK;
    m_activePositions = 0;
    m_errorHandler = NULL;
    m_correlationEngine = NULL;
    m_perfAnalytics = NULL;
    m_atrHandle = INVALID_HANDLE;
    m_logLevel = 1;
    // Initialize default parameters
    m_params.sizingMode = POSITION_SIZE_RISK_PERCENT;
    m_params.fixedLotSize = MIN_LOT_SIZE;
    m_params.riskPercent = 1.0;  // Blueprint 10.4: 0-100 scale (1.0 = 1%)
    m_params.atrPeriod = 14;
    m_params.atrMultiplier = 1.5;
    m_params.maxLotSize = MAX_LOT_SIZE;
    m_params.minLotSize = MIN_LOT_SIZE;
    m_params.correlationAdjustment = 1.0;
    m_params.useVolatilityAdjustment = true;
    m_params.useCorrelationAdjustment = true;
    // Kelly Criterion defaults
    m_kellyWinRate = 0.5;
    m_kellyAvgWin = 0.0;
    m_kellyAvgLoss = 0.0;
    m_kellyTradeCount = 0;
    m_kellyFraction = 0.5;      // Half-Kelly
    m_kellyMaxCap = 0.25;       // Cap at 25%
    m_kellyHistoryIndex = 0;
    m_kellyHistorySize = 0;
    ArrayResize(m_kellyWinHistory, 100);
    ArrayResize(m_kellyLossHistory, 100);
    ArrayInitialize(m_kellyWinHistory, 0.0);
    ArrayInitialize(m_kellyLossHistory, 0.0);
    // Equity compounding defaults
    m_startingEquity = 0.0;
    m_compoundingAggressiveness = 0.5;
    m_drawdownScalingFactor = 1.0;
    m_enableCompounding = true;
    // Min-lot round-up defaults
    m_allowMinLotRoundUp = true;
    m_minLotRiskMultiplier = 15.0;
    // Pluggable modifier chain defaults
    m_modifierCount = 0;
    for(int i = 0; i < 5; i++)
        m_modifiers[i] = NULL;
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CPositionSizer::~CPositionSizer(void)
{
    if(CheckPointer(m_errorHandler) != POINTER_INVALID)
    {
        SErrorContext context;
        context.component = "PositionSizer";
        context.operation = "~CPositionSizer";
        context.symbol = "";
        context.errorCode = 0;
        context.additionalInfo = "Position sizer destroyed";
        context.timestamp = TimeCurrent();
        context.severity = ERROR_INFO;
        CEnhancedErrorHandler::LogError(ERROR_INFO, context);
    }
    
    if(m_atrHandle != INVALID_HANDLE)
    {
        IndicatorRelease(m_atrHandle);
        m_atrHandle = INVALID_HANDLE;
    }
}

//+------------------------------------------------------------------+
//| Initialize with parameters                                      |
//+------------------------------------------------------------------+
bool CPositionSizer::SetParameters(const SPositionSizingParams &params)
{
    // DIAGNOSTIC: Log entry
    Print("[POSITIONSIZER-DEBUG] SetParameters called | riskPercent=", DoubleToString(params.riskPercent, 4),
          " | fixedLot=", DoubleToString(params.fixedLotSize, 4),
          " | minLot=", DoubleToString(params.minLotSize, 4),
          " | maxLot=", DoubleToString(params.maxLotSize, 4),
          " | atrPeriod=", params.atrPeriod,
          " | atrMult=", DoubleToString(params.atrMultiplier, 4),
          " | corrAdj=", DoubleToString(params.correlationAdjustment, 4));
    
    // Validate parameters
    if(params.riskPercent <= 0 || params.riskPercent > MAX_RISK_PER_TRADE)
    {
        string errMsg = StringFormat("Invalid risk percent: %.2f (must be >0 and <=%.2f)", params.riskPercent, MAX_RISK_PER_TRADE);
        LogError(ERROR_RECOVERABLE, "PositionSizer", errMsg, 0);
        Print("[POSITIONSIZER-REJECT] ", errMsg);
        return false;
    }
    
    if(params.fixedLotSize < MIN_LOT_SIZE || params.fixedLotSize > MAX_LOT_SIZE)
    {
        string errMsg = StringFormat("Invalid fixed lot size: %.2f (must be >=%.2f and <=%.2f)", params.fixedLotSize, MIN_LOT_SIZE, MAX_LOT_SIZE);
        LogError(ERROR_RECOVERABLE, "PositionSizer", errMsg, 0);
        Print("[POSITIONSIZER-REJECT] ", errMsg);
        return false;
    }
    
    if(params.atrPeriod <= 0 || params.atrPeriod > 100)
    {
        string errMsg = StringFormat("Invalid ATR period: %d (must be >0 and <=100)", params.atrPeriod);
        LogError(ERROR_RECOVERABLE, "PositionSizer", errMsg, 0);
        Print("[POSITIONSIZER-REJECT] ", errMsg);
        return false;
    }
    
    // AUDIT FIX: Add validation for additional parameters
    if(params.atrMultiplier <= 0 || params.atrMultiplier > 10.0)
    {
        string errMsg = StringFormat("Invalid ATR multiplier: %.2f (must be >0 and <=10.0)", params.atrMultiplier);
        LogError(ERROR_RECOVERABLE, "PositionSizer", errMsg, 0);
        Print("[POSITIONSIZER-REJECT] ", errMsg);
        return false;
    }
    
    if(params.maxLotSize <= 0 || params.maxLotSize > MAX_LOT_SIZE)
    {
        string errMsg = StringFormat("Invalid max lot size: %.2f (must be >0 and <=%.2f)", params.maxLotSize, MAX_LOT_SIZE);
        LogError(ERROR_RECOVERABLE, "PositionSizer", errMsg, 0);
        Print("[POSITIONSIZER-REJECT] ", errMsg);
        return false;
    }
    
    if(params.minLotSize <= 0 || params.minLotSize > MAX_LOT_SIZE)
    {
        string errMsg = StringFormat("Invalid min lot size: %.2f (must be >0 and <=%.2f)", params.minLotSize, MAX_LOT_SIZE);
        LogError(ERROR_RECOVERABLE, "PositionSizer", errMsg, 0);
        Print("[POSITIONSIZER-REJECT] ", errMsg);
        return false;
    }
    
    if(params.minLotSize > params.maxLotSize)
    {
        string errMsg = StringFormat("Min lot size (%.2f) > Max lot size (%.2f)", params.minLotSize, params.maxLotSize);
        LogError(ERROR_RECOVERABLE, "PositionSizer", errMsg, 0);
        Print("[POSITIONSIZER-REJECT] ", errMsg);
        return false;
    }
    
    if(params.correlationAdjustment <= 0 || params.correlationAdjustment > 2.0)
    {
        string errMsg = StringFormat("Invalid correlation adjustment: %.2f (must be >0 and <=2.0)", params.correlationAdjustment);
        LogError(ERROR_RECOVERABLE, "PositionSizer", errMsg, 0);
        Print("[POSITIONSIZER-REJECT] ", errMsg);
        return false;
    }
    
    // Set parameters
    m_params = params;
    m_initialized = true;
    
    if(CheckPointer(m_errorHandler) != POINTER_INVALID)
        LogError(ERROR_INFO, "PositionSizer", 
                               StringFormat("Position sizer initialized - Mode: %d, Risk: %.2f%%", 
                                           params.sizingMode, params.riskPercent), 0);
    
    Print("[POSITIONSIZER-SUCCESS] Initialized successfully | mode=", params.sizingMode,
          " | risk=", DoubleToString(params.riskPercent, 2), "%");
    
    return true;
}

//+------------------------------------------------------------------+
//| Calculate optimal position size                                |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateOptimalPositionSize(const string symbolParam,
                                                    const ENUM_ORDER_TYPE orderType,
                                                    const double stopLossPips,
                                                    const double confidence)
{
    return CalculateOptimalPositionSizeCore(symbolParam, orderType, stopLossPips, m_params.riskPercent, confidence);
}

//+------------------------------------------------------------------+
//| Stateless core calculation �?accepts riskPercent as parameter     |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateOptimalPositionSizeCore(const string symbolParam,
                                                          const ENUM_ORDER_TYPE orderType,
                                                          const double stopLossPips,
                                                          const double riskPercent,
                                                          const double confidence)
{
    if(!m_initialized)
    {
        SErrorContext context;
        context.component = "PositionSizer";
        context.operation = "CalculatePositionSize";
        context.symbol = symbolParam;
        context.errorCode = 0;
        context.additionalInfo = "Position sizer not initialized";
        context.timestamp = TimeCurrent();
        context.severity = ERROR_RECOVERABLE;
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, context);
        return NormalizeVolume(symbolParam, MIN_LOT_SIZE);
    }

    if(!ValidateSymbol(symbolParam))
    {
        SErrorContext symbolContext;
        symbolContext.component = "PositionSizer";
        symbolContext.operation = "CalculatePositionSize";
        symbolContext.symbol = symbolParam;
        symbolContext.errorCode = 0;
        symbolContext.additionalInfo = "Invalid symbol: " + symbolParam;
        symbolContext.timestamp = TimeCurrent();
        symbolContext.severity = ERROR_RECOVERABLE;
        CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, symbolContext);
        return NormalizeVolume(symbolParam, MIN_LOT_SIZE);
    }

    if(stopLossPips <= 0)
    {
        SErrorContext slContext;
        slContext.component = "PositionSizer";
        slContext.operation = "CalculatePositionSize";
        slContext.symbol = symbolParam;
        slContext.errorCode = 0;
        slContext.additionalInfo = "Invalid stop loss pips: " + DoubleToString(stopLossPips, 2);
        slContext.timestamp = TimeCurrent();
        slContext.severity = ERROR_WARNING;
        CEnhancedErrorHandler::LogError(ERROR_WARNING, slContext);
        return NormalizeVolume(symbolParam, MIN_LOT_SIZE);
    }

    UpdateRiskMetrics();

    // Use the riskPercent parameter instead of m_params.riskPercent
    double baseSize = CalculateBasePositionSizeWithRisk(symbolParam, stopLossPips, riskPercent);

    if(confidence > 0 && confidence != 1.0)
    {
        baseSize *= confidence;
        LogSizingDecision(symbolParam, baseSize, StringFormat("Confidence adjusted (%.2f)", confidence));
    }

    if(m_params.useVolatilityAdjustment && m_params.sizingMode != POSITION_SIZE_VOLATILITY)
        baseSize = CalculateVolatilityBasedSize(symbolParam, baseSize);

    if(m_params.useCorrelationAdjustment && m_params.sizingMode != POSITION_SIZE_CORRELATION)
        baseSize = CalculateCorrelationAdjustedSize(symbolParam, baseSize);

    baseSize *= CalculateCompoundingMultiplier();

    for(int i = 0; i < m_modifierCount; i++)
    {
        if(CheckPointer(m_modifiers[i]) != POINTER_INVALID)
        {
            double preMod = baseSize;
            baseSize = m_modifiers[i].AdjustLotSize(baseSize, symbolParam, confidence);
            if(MathAbs(baseSize - preMod) > 0.001)
                LogSizingDecision(symbolParam, baseSize, StringFormat("Modifier[%d] %s: %.2f->%.2f", i, m_modifiers[i].GetName(), preMod, baseSize));
        }
    }

    double finalSize = ValidatePositionSize(symbolParam, baseSize);

    if(m_perfAnalytics != NULL)
    {
        double momentumScale = m_perfAnalytics.CalculateMomentumScale();
        if(momentumScale != 1.0 && momentumScale > 0.0)
        {
            double preMomentum = finalSize;
            finalSize *= momentumScale;
            finalSize = NormalizeVolume(symbolParam, finalSize);
            if(MathAbs(preMomentum - finalSize) > 0.001)
                LogSizingDecision(symbolParam, finalSize, StringFormat("Momentum scale applied (%.2fx)", momentumScale));
        }
    }

    m_lastCalculatedSize = finalSize;
    m_lastSymbol = symbolParam;
    m_lastCalculation = TimeCurrent();

    return finalSize;
}

//+------------------------------------------------------------------+
//| Stateless position size calculation (Blueprint Section 10.5)      |
//| All per-call parameters passed directly �?no shared state mutation|
//+------------------------------------------------------------------+
double CPositionSizer::CalculateSize(const string symbol,
                                      const ENUM_ORDER_TYPE orderType,
                                      const double slDistancePips,
                                      const double riskPercent,
                                      const double confidence)
{
    // Validate risk percent before proceeding
    if(riskPercent <= 0.0 || riskPercent > MAX_RISK_PER_TRADE)
    {
        PrintFormat("[POSITIONSIZER-CALCULATE-SIZE] Invalid risk percent: %.2f �?falling back to min lot for %s",
                    riskPercent, symbol);
        return NormalizeVolume(symbol, MIN_LOT_SIZE);
    }

    if(!m_initialized)
    {
        PrintFormat("[POSITIONSIZER] WARNING: CalculateSize called before SetParameters - using defaults for %s", symbol);
        m_initialized = true;
    }

    // Direct call �?no shared state mutation (Blueprint Section 10.5)
    double lotSize = CalculateOptimalPositionSizeCore(symbol, orderType, slDistancePips, riskPercent, confidence);

    // Momentum scaling already applied in CalculateOptimalPositionSizeCore
    return lotSize;
}

//+------------------------------------------------------------------+
//| Stateless position size with tier cap (Blueprint Section 10.5)   |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateSizeWithTierCap(const string symbol,
                                      const ENUM_ORDER_TYPE orderType,
                                      const double slDistancePips,
                                      const double riskPercent,
                                      const double confidence,
                                      double tierRiskPerTradePct)
{
    double lotSize = CalculateSize(symbol, orderType, slDistancePips, riskPercent, confidence);

    // Apply tier cap
    double riskDenominator = GetRiskDenominator();
    double tierMaxRisk = riskDenominator * (tierRiskPerTradePct / 100.0);  // Blueprint 10.4: / 100.0 converts 0-100 scale to fraction
    double riskPerLot = CalculateRiskPerLot(symbol, slDistancePips);
    if(riskPerLot > 0.0)
    {
        double tierMaxLot = tierMaxRisk / riskPerLot;
        if(lotSize > tierMaxLot)
        {
            LogSizingDecision(symbol, tierMaxLot, StringFormat("Tier cap applied (%.1f%%)", tierRiskPerTradePct));
            lotSize = tierMaxLot;
            lotSize = NormalizeVolume(symbol, lotSize);
        }
    }

    return lotSize;
}

//+------------------------------------------------------------------+
//| Issue 5: Cap lot size for daily budget protection                 |
//| Prevents a single trade from consuming more than maxBudgetFraction|
//| of the remaining daily risk budget (default 30%).                 |
//+------------------------------------------------------------------+
double CPositionSizer::CapLotForDailyBudget(const string symbol,
                                            const ENUM_ORDER_TYPE orderType,
                                            const double lotSize,
                                            const double slDistancePips,
                                            const double riskPercent,
                                            const double remainingDailyRiskPct,
                                            const double maxBudgetFraction)
{
    if(lotSize <= 0.0 || remainingDailyRiskPct <= 0.0 || riskPercent <= 0.0)
        return lotSize;

    double maxAllowedRisk = remainingDailyRiskPct * maxBudgetFraction;

    if(riskPercent <= maxAllowedRisk)
        return lotSize;

    double reductionFactor = maxAllowedRisk / riskPercent;
    double cappedLot = lotSize * reductionFactor;

    double brokerMinLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    if(brokerMinLot <= 0.0) brokerMinLot = MIN_LOT_SIZE;
    cappedLot = MathMax(brokerMinLot, cappedLot);
    cappedLot = NormalizeVolume(symbol, cappedLot);

    if(cappedLot < lotSize)
    {
        PrintFormat("[DAILY-BUDGET-CAP] %s | lot %.2f -> %.2f | risk %.2f%% -> %.2f%% | remaining_budget=%.2f%% | cap_fraction=%.0f%%",
                    symbol, lotSize, cappedLot,
                    riskPercent, riskPercent * reductionFactor,
                    remainingDailyRiskPct, maxBudgetFraction * 100.0);
    }

    return cappedLot;
}

//+------------------------------------------------------------------+
//| Calculate base position size according to sizing mode           |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateBasePositionSize(const string symbolParam, const double stopLossPips)
{
    double baseSize = 0.0;
    
    // Calculate base size according to sizing mode
    switch(m_params.sizingMode)
    {
        case POSITION_SIZE_FIXED:
            baseSize = m_params.fixedLotSize;
            LogSizingDecision(symbolParam, baseSize, "Fixed lot size");
            break;
            
        case POSITION_SIZE_RISK_PERCENT:
            baseSize = CalculateRiskBasedSize(symbolParam, stopLossPips, m_params.riskPercent);
            LogSizingDecision(symbolParam, baseSize, "Risk percentage based");
            break;
            
        case POSITION_SIZE_VOLATILITY:
            baseSize = CalculateRiskBasedSize(symbolParam, stopLossPips, m_params.riskPercent);
            baseSize = CalculateVolatilityBasedSize(symbolParam, baseSize);
            LogSizingDecision(symbolParam, baseSize, "Volatility adjusted");
            break;
            
        case POSITION_SIZE_CORRELATION:
            baseSize = CalculateRiskBasedSize(symbolParam, stopLossPips, m_params.riskPercent);
            baseSize = CalculateCorrelationAdjustedSize(symbolParam, baseSize);
            LogSizingDecision(symbolParam, baseSize, "Correlation adjusted");
            break;
            
        case POSITION_SIZE_KELLY:
        {
            double kellyFraction = CalculateKellyFraction();
            double equity = AccountInfoDouble(ACCOUNT_EQUITY);
            double riskAmount = equity * kellyFraction;
            double riskPerLot = CalculateRiskPerLot(symbolParam, stopLossPips);
            if(riskPerLot > 0.0)
            {
                baseSize = riskAmount / riskPerLot;
                LogSizingDecision(symbolParam, baseSize, StringFormat("Kelly Criterion (fraction=%.4f)", kellyFraction));
            }
            else
            {
                baseSize = MIN_LOT_SIZE;
                LogSizingDecision(symbolParam, baseSize, "Kelly Criterion fallback (invalid risk per lot)");
            }
            break;
        }
            
        default:
            baseSize = MIN_LOT_SIZE;
            LogSizingDecision(symbolParam, baseSize, "Default minimum size");
            break;
    }
    
    return baseSize;
}

//+------------------------------------------------------------------+
//| Calculate base position size with explicit risk percent          |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateBasePositionSizeWithRisk(const string symbolParam, const double stopLossPips, const double riskPercent)
{
    double baseSize = 0.0;
    switch(m_params.sizingMode)
    {
        case POSITION_SIZE_FIXED:
            baseSize = m_params.fixedLotSize;
            LogSizingDecision(symbolParam, baseSize, "Fixed lot size");
            break;
        case POSITION_SIZE_RISK_PERCENT:
            baseSize = CalculateRiskBasedSize(symbolParam, stopLossPips, riskPercent);
            LogSizingDecision(symbolParam, baseSize, "Risk percentage based");
            break;
        case POSITION_SIZE_VOLATILITY:
            baseSize = CalculateRiskBasedSize(symbolParam, stopLossPips, riskPercent);
            baseSize = CalculateVolatilityBasedSize(symbolParam, baseSize);
            LogSizingDecision(symbolParam, baseSize, "Volatility adjusted");
            break;
        case POSITION_SIZE_CORRELATION:
            baseSize = CalculateRiskBasedSize(symbolParam, stopLossPips, riskPercent);
            baseSize = CalculateCorrelationAdjustedSize(symbolParam, baseSize);
            LogSizingDecision(symbolParam, baseSize, "Correlation adjusted");
            break;
        case POSITION_SIZE_KELLY:
        {
            double kellyFraction = CalculateKellyFraction();
            double equity = AccountInfoDouble(ACCOUNT_EQUITY);
            double riskAmount = equity * kellyFraction;
            double riskPerLot = CalculateRiskPerLot(symbolParam, stopLossPips);
            if(riskPerLot > 0.0)
            {
                baseSize = riskAmount / riskPerLot;
                LogSizingDecision(symbolParam, baseSize, StringFormat("Kelly Criterion (fraction=%.4f)", kellyFraction));
            }
            else
            {
                baseSize = MIN_LOT_SIZE;
                LogSizingDecision(symbolParam, baseSize, "Kelly Criterion fallback (invalid risk per lot)");
            }
            break;
        }
        default:
            baseSize = MIN_LOT_SIZE;
            LogSizingDecision(symbolParam, baseSize, "Default minimum size");
            break;
    }
    return baseSize;
}

//+------------------------------------------------------------------+
//| Calculate position size based on risk percentage               |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateRiskBasedSize(const string symbolParam,
                                             const double stopLossPips,
                                             const double riskPercent)
{
    // Validate stop-loss parameter - must be positive
    if(stopLossPips <= 0.0)
    {
        LogError(ERROR_RECOVERABLE, "PositionSizer", "Invalid stop-loss pips: must be greater than 0", 0);
        return MIN_LOT_SIZE;
    }
    
    // Validate risk percentage parameter
    if(riskPercent <= 0.0 || riskPercent > MAX_RISK_PER_TRADE)
    {
        LogError(ERROR_RECOVERABLE, "PositionSizer", "Invalid risk percentage: must be between 0 and " + DoubleToString(MAX_RISK_PER_TRADE, 1), 0);
        return MIN_LOT_SIZE;
    }
    
    double riskDenominator = GetRiskDenominator();
    if(riskDenominator <= 0.0)
    {
        LogError(ERROR_RECOVERABLE, "PositionSizer", "Invalid account risk denominator", 0);
        return MIN_LOT_SIZE;
    }
    
    // Calculate risk amount in account currency
    double riskAmount = riskDenominator * (riskPercent / 100.0);  // Blueprint 10.4: / 100.0 converts 0-100 scale to fraction

    double riskPerLot = CalculateRiskPerLot(symbolParam, stopLossPips);
    if(riskPerLot <= 0.0)
    {
        LogError(ERROR_RECOVERABLE, "PositionSizer", "Unable to calculate risk per lot for " + symbolParam, 0);
        return MIN_LOT_SIZE;
    }

    double lotSize = riskAmount / riskPerLot;
    
    return MathMax(MIN_LOT_SIZE, lotSize);
}

//+------------------------------------------------------------------+
//| Calculate position size based on volatility (ATR)              |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateVolatilityBasedSize(const string symbolParam,
                                                    const double baseSize)
{
    double atr = GetATR(symbolParam, m_params.atrPeriod);
    if(atr <= 0)
    {
        SErrorContext context;
        context.component = "PositionSizer";
        context.operation = "GetVolatilityAdjustedSize";
        context.symbol = symbolParam;
        context.errorCode = 0;
        context.additionalInfo = "Invalid ATR for " + symbolParam;
        context.timestamp = TimeCurrent();
        context.severity = ERROR_WARNING;
        CEnhancedErrorHandler::LogError(ERROR_WARNING, context);
        return baseSize;
    }
    
    // Get current price for normalization
    double currentPriceVal = SymbolInfoDouble(symbolParam, SYMBOL_BID);
    if(currentPriceVal <= 0)
    {
        return baseSize;
    }
    
    // Calculate volatility ratio with minimum price threshold to avoid exaggeration for low-priced symbols
    double minPriceThreshold = 0.01; // Minimum price to use for normalization
    double normalizedPrice = MathMax(currentPriceVal, minPriceThreshold);
    double volatilityRatio = atr / normalizedPrice;
    
    // Adjust size inversely to volatility
    double volatilityAdjustment = 1.0 / (1.0 + volatilityRatio * m_params.atrMultiplier);
    
    return baseSize * volatilityAdjustment;
}

//+------------------------------------------------------------------+
//| Calculate correlation-adjusted position size                   |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateCorrelationAdjustedSize(const string symbolParam,
                                                        const double baseSize)
{
    double correlation = CalculatePortfolioCorrelation(symbolParam);
    
    // Reduce size based on correlation
    double correlationAdjustment = 1.0 - (MathAbs(correlation) * m_params.correlationAdjustment);
    correlationAdjustment = MathMax(0.1, correlationAdjustment); // Minimum 10% of base size
    
    return baseSize * correlationAdjustment;
}

//+------------------------------------------------------------------+
//| Validate position size against account limits                  |
//+------------------------------------------------------------------+
double CPositionSizer::ValidatePositionSize(const string symbolParam,
                                            const double proposedSize)
{
    double validatedSize = proposedSize;

    // --- Min-lot round-up gate (before NormalizeVolume clamps silently) ---
    // If the calculated lot is below the broker minimum, decide whether to
    // round up (within risk budget) or skip the trade entirely.
    double brokerMinLot = SymbolInfoDouble(symbolParam, SYMBOL_VOLUME_MIN);
    if(brokerMinLot <= 0.0) brokerMinLot = MIN_LOT_SIZE;
    double effectiveMinLot = MathMax(brokerMinLot, m_params.minLotSize);

    if(validatedSize > 0.0 && validatedSize < effectiveMinLot)
    {
        if(m_allowMinLotRoundUp)
        {
            double riskRatio = effectiveMinLot / validatedSize;  // How many times bigger the risk would be
            if(riskRatio <= m_minLotRiskMultiplier)
            {
                Print("[POSITION-SIZER] Lot below minimum: calculated=", DoubleToString(validatedSize, 3),
                      " < min=", DoubleToString(effectiveMinLot, 3),
                      ". Round-up allowed (risk ", DoubleToString(riskRatio, 2),
                      "x <= cap ", DoubleToString(m_minLotRiskMultiplier, 2), "x)");
                validatedSize = effectiveMinLot;
                LogSizingDecision(symbolParam, validatedSize, "Rounded up to broker minimum (within risk cap)");
            }
            else
            {
                Print("[POSITION-SIZER] Lot below minimum: calculated=", DoubleToString(validatedSize, 3),
                      " < min=", DoubleToString(effectiveMinLot, 3),
                      ". Risk at min lot (", DoubleToString(riskRatio, 2),
                      "x) exceeds ", DoubleToString(m_minLotRiskMultiplier, 2),
                      "x cap. Trade skipped.");
                return 0.0;
            }
        }
        else
        {
            // Round-up disabled �?skip trade with clear message
            Print("[POSITION-SIZER] Lot below minimum: calculated=", DoubleToString(validatedSize, 3),
                  " < min=", DoubleToString(effectiveMinLot, 3),
                  ". Round-up disabled. Trade skipped.");
            return 0.0;
        }
    }
    else if(validatedSize <= 0.0)
    {
        // Zero or negative lot �?always skip
        Print("[POSITION-SIZER] Calculated lot is zero or negative: ", DoubleToString(validatedSize, 3),
              ". Trade skipped.");
        return 0.0;
    }

    // Normalize volume to symbol's step size
    validatedSize = NormalizeVolume(symbolParam, validatedSize);

    // Check maximum size
    double maxSize = CalculateMaxSafeSize(symbolParam);
    if(validatedSize > maxSize)
    {
        validatedSize = maxSize;
        LogSizingDecision(symbolParam, validatedSize, "Adjusted to maximum safe size");
    }

    // Check parameter limits
    if(validatedSize > m_params.maxLotSize)
    {
        validatedSize = m_params.maxLotSize;
        LogSizingDecision(symbolParam, validatedSize, "Adjusted to parameter maximum");
    }

    // Check margin requirements
    double marginRequired = CalculateMarginRequirement(symbolParam, validatedSize);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

    if(marginRequired > freeMargin * 0.80) // Use max 80% of free margin
    {
        double safeSize = (freeMargin * 0.80) / (marginRequired / validatedSize);
        validatedSize = MathMax(MIN_LOT_SIZE, safeSize);
        LogSizingDecision(symbolParam, validatedSize, "Adjusted for margin requirements");
    }

    // Final normalization to ensure compliance
    validatedSize = NormalizeVolume(symbolParam, validatedSize);

    return validatedSize;
}

//+------------------------------------------------------------------+
//| Update risk metrics                                            |
//+------------------------------------------------------------------+
void CPositionSizer::UpdateRiskMetrics(void)
{
    m_activePositions = PositionsTotal();
    m_currentTotalRisk = 0.0;
    
    // Calculate current total risk from open positions
    for(int i = 0; i < m_activePositions; i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            string posSym = PositionGetString(POSITION_SYMBOL);
            double tickVal = SymbolInfoDouble(posSym, SYMBOL_TRADE_TICK_VALUE);
            double tickSz  = SymbolInfoDouble(posSym, SYMBOL_TRADE_TICK_SIZE);
            
            if(tickSz > 0)
            {
                double points = MathAbs(PositionGetDouble(POSITION_PRICE_OPEN) - PositionGetDouble(POSITION_SL)) / tickSz;
                double positionRisk = PositionGetDouble(POSITION_VOLUME) * points * tickVal;
                m_currentTotalRisk += positionRisk;
            }
        }
    }
    
    // Convert to percentage using the same stress denominator as the risk gate.
    double riskDenominator = GetRiskDenominator();
    if(riskDenominator > 0.0)
    {
        m_currentTotalRisk = (m_currentTotalRisk / riskDenominator) * 100.0;  // Blueprint 10.4: * 100.0 converts fraction to 0-100 scale
    }
}

//+------------------------------------------------------------------+
//| Calculate maximum safe lot size based on margin                |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateMaxSafeSize(const string symbolParam)
{
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double marginRequired = CalculateMarginRequirement(symbolParam, 1.0);
    
    if(marginRequired <= 0 || freeMargin <= 0)
        return MIN_LOT_SIZE;
    
    // Use maximum 90% of free margin for safety
    double maxSize = (freeMargin * 0.9) / marginRequired;
    
    return MathMax(MIN_LOT_SIZE, MathMin(maxSize, MAX_LOT_SIZE));
}

//+------------------------------------------------------------------+
//| Calculate minimum viable lot size                              |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateMinViableSize(const string symbolParam)
{
    double minLot = SymbolInfoDouble(symbolParam, SYMBOL_VOLUME_MIN);
    return MathMax(MIN_LOT_SIZE, minLot);
}

//+------------------------------------------------------------------+
//| Calculate tick value for the symbol                            |
//+------------------------------------------------------------------+
double CPositionSizer::GetTickValue(const string symbolParam)
{
    return SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_VALUE);
}

//+------------------------------------------------------------------+
//| Get symbol point value                                         |
//+------------------------------------------------------------------+
double CPositionSizer::GetSymbolPoint(const string symbolParam)
{
    return SymbolInfoDouble(symbolParam, SYMBOL_POINT);
}

//+------------------------------------------------------------------+
//| Account risk denominator                                        |
//+------------------------------------------------------------------+
// AUDIT FIX: This implementation must be kept in sync with CPortfolioRiskManager::GetRiskDenominator
// to ensure consistent risk calculation across all risk components.
double CPositionSizer::GetRiskDenominator(void)
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);

    if(balance > 0.0 && equity > 0.0)
        return MathMin(balance, equity);

    return MathMax(balance, equity);
}

//+------------------------------------------------------------------+
//| Risk per 1.0 lot for a stop distance                            |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateRiskPerLot(const string symbolParam, const double stopLossPips)
{
    if(symbolParam == "" || stopLossPips <= 0.0)
        return 0.0;

    double tickValue = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbolParam, SYMBOL_TRADE_TICK_SIZE);
    double point = SymbolInfoDouble(symbolParam, SYMBOL_POINT);
    string profitCurrency = SymbolInfoString(symbolParam, SYMBOL_CURRENCY_PROFIT);
    string accountCurrency = AccountInfoString(ACCOUNT_CURRENCY);

    if(tickValue <= 0.0 || tickSize <= 0.0 || point <= 0.0)
        return 0.0;

    double stopDistancePrice = stopLossPips * point;
    double riskPerLot = (stopDistancePrice / tickSize) * tickValue;

    // Convert to account currency if needed
    if(profitCurrency != accountCurrency)
    {
        string conversionSymbol = profitCurrency + accountCurrency;
        if(!SymbolSelect(conversionSymbol, true))
        {
            conversionSymbol = accountCurrency + profitCurrency;
            if(SymbolSelect(conversionSymbol, true))
            {
                double conversionRate = SymbolInfoDouble(conversionSymbol, SYMBOL_BID);
                if(conversionRate > 0)
                    riskPerLot /= conversionRate;
            }
        }
        else
        {
            double conversionRate = SymbolInfoDouble(conversionSymbol, SYMBOL_BID);
            if(conversionRate > 0)
                riskPerLot *= conversionRate;
        }
    }

    return riskPerLot;
}

//+------------------------------------------------------------------+
//| Normalize volume to symbol's step size                         |
//+------------------------------------------------------------------+
double CPositionSizer::NormalizeVolume(const string symbolParam, const double volume)
{
    if(volume <= 0) return 0.0;
    
    // Get symbol volume constraints
    double minVol = SymbolInfoDouble(symbolParam, SYMBOL_VOLUME_MIN);
    double maxVol = SymbolInfoDouble(symbolParam, SYMBOL_VOLUME_MAX);
    double stepVol = SymbolInfoDouble(symbolParam, SYMBOL_VOLUME_STEP);
    
    // Ensure we have valid step (default to 0.01 for forex, but check for synthetics)
    if(stepVol <= 0) stepVol = 0.01;
    
    // Normalize to step size
    double normalized = MathRound(volume / stepVol) * stepVol;
    
    // Clamp to min/max - CRITICAL for Deriv synthetics!
    if(normalized < minVol)
    {
        normalized = minVol;
        Print("[VOLUME-NORM] ", symbolParam, ": Volume adjusted to minimum: ", normalized);
    }
    if(normalized > maxVol)
    {
        normalized = maxVol;
        Print("[VOLUME-NORM] ", symbolParam, ": Volume adjusted to maximum: ", normalized);
    }
    
    // Log normalization result
    if(MathAbs(normalized - volume) > 0.001)
    {
        Print("[VOLUME-NORM] ", symbolParam, ": ", volume, " -> ", normalized);
    }
    
    return normalized;
}

//+------------------------------------------------------------------+
//| Calculate margin requirement for position                      |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateMarginRequirement(const string symbolParam, const double lotSize)
{
    if(lotSize <= 0.0 || symbolParam == "")
        return 0.0;

    double ask = SymbolInfoDouble(symbolParam, SYMBOL_ASK);
    double bid = SymbolInfoDouble(symbolParam, SYMBOL_BID);

    double marginBuy = 0.0;
    double marginSell = 0.0;
    bool buyOk = (ask > 0.0) && OrderCalcMargin(ORDER_TYPE_BUY, symbolParam, lotSize, ask, marginBuy);
    bool sellOk = (bid > 0.0) && OrderCalcMargin(ORDER_TYPE_SELL, symbolParam, lotSize, bid, marginSell);

    if(buyOk && sellOk)
        return MathMax(marginBuy, marginSell);
    if(buyOk)
        return marginBuy;
    if(sellOk)
        return marginSell;

    return 0.0;
}

//+------------------------------------------------------------------+
//| Apply risk limits to position size                             |
//+------------------------------------------------------------------+
double CPositionSizer::ApplyRiskLimits(const double proposedSize, const double maxRisk)
{
    if(m_currentTotalRisk + maxRisk > m_maxAllowedRisk)
    {
        double availableRisk = m_maxAllowedRisk - m_currentTotalRisk;
        if(availableRisk <= 0)
            return 0.0;
        
        return proposedSize * (availableRisk / maxRisk);
    }
    
    return proposedSize;
}

//+------------------------------------------------------------------+
//| Get ATR value for volatility calculation                       |
//+------------------------------------------------------------------+
double CPositionSizer::GetATR(const string symbolParam, const int period)
{
    CIndicatorManager* indicatorManager = CIndicatorManager::Instance();
    if(indicatorManager != NULL)
    {
        int sharedHandle = indicatorManager.GetATRHandle(symbolParam, PERIOD_CURRENT, period);
        if(sharedHandle != INVALID_HANDLE)
        {
            double atrArrayShared[];
            ArraySetAsSeries(atrArrayShared, true);
            if(CopyBuffer(sharedHandle, 0, 0, 1, atrArrayShared) > 0 && atrArrayShared[0] > 0.0)
                return atrArrayShared[0];
        }
    }

    if(m_atrHandle == INVALID_HANDLE || m_lastSymbol != symbolParam)
    {
        if(m_atrHandle != INVALID_HANDLE)
            IndicatorRelease(m_atrHandle);
        m_atrHandle = iATR(symbolParam, PERIOD_CURRENT, period);
        m_lastSymbol = symbolParam;
    }

    if(m_atrHandle == INVALID_HANDLE)
        return 0.0;

    double atrArray[];
    ArraySetAsSeries(atrArray, true);
    if(CopyBuffer(m_atrHandle, 0, 0, 1, atrArray) <= 0)
        return 0.0;

    return atrArray[0];
}

//+------------------------------------------------------------------+
//| Calculate correlation with existing positions                  |
//+------------------------------------------------------------------+
double CPositionSizer::CalculatePortfolioCorrelation(const string symbolParam)
{
    double maxCorrelation = 0.0;
    
    // Check correlation with existing positions
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            string existingSymbol = PositionGetString(POSITION_SYMBOL);
            if(existingSymbol != symbolParam)
            {
                // Advanced correlation calculation using historical price data
                double correlation = CalculateCorrelation(symbolParam, existingSymbol, 50);
                
                maxCorrelation = MathMax(maxCorrelation, MathAbs(correlation));
            }
        }
    }
    
    return maxCorrelation;
}

//+------------------------------------------------------------------+
//| Validate symbol for trading                                    |
//+------------------------------------------------------------------+
bool CPositionSizer::ValidateSymbol(const string symbolParam)
{
    if(StringLen(symbolParam) == 0)
        return false;
    
    if(!SymbolSelect(symbolParam, true))
        return false;
    
    double bid = SymbolInfoDouble(symbolParam, SYMBOL_BID);
    double ask = SymbolInfoDouble(symbolParam, SYMBOL_ASK);
    
    return (bid > 0 && ask > 0);
}

//+------------------------------------------------------------------+
//| Calculate correlation between two symbols �?delegates to engine   |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateCorrelation(const string symbol1, const string symbol2, int period)
{
    // Delegate to unified correlation engine if available
    if(CheckPointer(m_correlationEngine) != POINTER_INVALID)
    {
        double corr = m_correlationEngine.GetCorrelation(symbol1, symbol2);
        // Engine returns conservative fallback (1.0) when data insufficient;
        // for position sizing, 0.0 is safer (no correlation penalty).
        // Only accept values that look like real correlations.
        if(corr >= -1.0 && corr <= 1.0)
            return corr;
        return 0.0;
    }

    // Fallback: simple same-direction heuristic when engine is unavailable.
    // If both symbols share the same base currency, assume positive correlation.
    // Otherwise, assume zero correlation (no penalty).
    string base1 = StringSubstr(symbol1, 0, 3);
    string base2 = StringSubstr(symbol2, 0, 3);
    string quote1 = StringSubstr(symbol1, 3, 3);
    string quote2 = StringSubstr(symbol2, 3, 3);

    if(base1 == base2 || quote1 == quote2)
        return 0.5;  // Moderate positive correlation assumption

    return 0.0;
}

//+------------------------------------------------------------------+
//| Log position sizing decision                                   |
//+------------------------------------------------------------------+
void CPositionSizer::LogSizingDecision(const string symbolParam, const double size, const string reason)
{
    if(m_logLevel < 3)
        return;

    string message = StringFormat("Position size calculated: %s = %.2f lots (%s)",
                                 symbolParam, size, reason);
    SErrorContext context;
    context.component = "PositionSizer";
    context.operation = "LogPositionSize";
    context.symbol = symbolParam;
    context.errorCode = 0;
    context.additionalInfo = message;
    context.timestamp = TimeCurrent();
    context.severity = ERROR_INFO;
    CEnhancedErrorHandler::LogError(ERROR_INFO, context);
}

//+------------------------------------------------------------------+
//| Update Kelly Criterion rolling statistics                      |
//+------------------------------------------------------------------+
void CPositionSizer::UpdateKellyStats(bool win, double profit, double loss)
{
    // Store in circular buffer (last 100 trades)
    m_kellyWinHistory[m_kellyHistoryIndex] = win ? profit : 0.0;
    m_kellyLossHistory[m_kellyHistoryIndex] = win ? 0.0 : MathAbs(loss);
    m_kellyHistoryIndex = (m_kellyHistoryIndex + 1) % 100;
    if(m_kellyHistorySize < 100)
        m_kellyHistorySize++;
    
    // Recalculate rolling statistics
    double totalWins = 0.0;
    double totalLosses = 0.0;
    int winCount = 0;
    int lossCount = 0;
    
    for(int i = 0; i < m_kellyHistorySize; i++)
    {
        if(m_kellyWinHistory[i] > 0.0)
        {
            totalWins += m_kellyWinHistory[i];
            winCount++;
        }
        if(m_kellyLossHistory[i] > 0.0)
        {
            totalLosses += m_kellyLossHistory[i];
            lossCount++;
        }
    }
    
    m_kellyTradeCount = m_kellyHistorySize;
    m_kellyWinRate = (m_kellyTradeCount > 0) ? (double)winCount / (double)m_kellyTradeCount : 0.5;
    m_kellyAvgWin = (winCount > 0) ? totalWins / winCount : 0.0;
    m_kellyAvgLoss = (lossCount > 0) ? totalLosses / lossCount : 0.0;
    
    Print("[KELLY-STATS] WinRate=", DoubleToString(m_kellyWinRate, 4),
          " AvgWin=", DoubleToString(m_kellyAvgWin, 2),
          " AvgLoss=", DoubleToString(m_kellyAvgLoss, 2),
          " Trades=", m_kellyTradeCount);
}

//+------------------------------------------------------------------+
//| Calculate Kelly Criterion fraction                             |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateKellyFraction(void)
{
    // If not enough data, use conservative default
    if(m_kellyTradeCount < 10 || m_kellyAvgLoss <= 0.0)
    {
        Print("[KELLY] Insufficient data (trades=", m_kellyTradeCount, "), using conservative 1%");
        return 0.01;
    }
    
    double payoffRatio = m_kellyAvgWin / MathMax(m_kellyAvgLoss, 0.0001);
    double kelly = m_kellyWinRate - ((1.0 - m_kellyWinRate) / payoffRatio);
    double adjustedKelly = kelly * m_kellyFraction;  // Half-Kelly
    double result = MathMax(0.01, MathMin(adjustedKelly, m_kellyMaxCap));  // Floor at 1%, cap at 25%
    
    Print("[KELLY] PayoffRatio=", DoubleToString(payoffRatio, 4),
          " RawKelly=", DoubleToString(kelly, 4),
          " AdjustedKelly=", DoubleToString(adjustedKelly, 4),
          " Final=", DoubleToString(result, 4));
    
    return result;
}

//+------------------------------------------------------------------+
//| Initialize equity compounding                                  |
//+------------------------------------------------------------------+
void CPositionSizer::InitializeCompounding(void)
{
    m_startingEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    Print("[COMPOUNDING] Initialized with starting equity: ", DoubleToString(m_startingEquity, 2));
}

//+------------------------------------------------------------------+
//| Calculate equity compounding multiplier                        |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateCompoundingMultiplier(void)
{
    if(!m_enableCompounding)
        return 1.0;
    
    if(m_startingEquity <= 0.0)
    {
        // Not initialized yet �?initialize on first call
        InitializeCompounding();
        return 1.0;
    }
    
    double sizerEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    double equityRatio = sizerEquity / MathMax(m_startingEquity, 0.01);
    
    double multiplier;
    if(equityRatio > 1.0)
    {
        // Growing: scale up with square root to avoid over-leveraging
        multiplier = 1.0 + (MathSqrt(equityRatio) - 1.0) * m_compoundingAggressiveness;
    }
    else
    {
        // Declining: scale down linearly (more conservative)
        multiplier = equityRatio * m_drawdownScalingFactor;
    }
    
    // Safety floor: never scale below 0.1x
    multiplier = MathMax(0.1, multiplier);
    
    Print("[COMPOUNDING] EquityRatio=", DoubleToString(equityRatio, 4),
          " Multiplier=", DoubleToString(multiplier, 4),
          " StartingEquity=", DoubleToString(m_startingEquity, 2),
          " CurrentEquity=", DoubleToString(sizerEquity, 2));
    
    return multiplier;
}

//+------------------------------------------------------------------+
//| Add a pluggable modifier to the chain (Phase 5)                   |
//+------------------------------------------------------------------+
void CPositionSizer::AddModifier(CPositionSizerModifier* modifier)
{
    if(modifier == NULL)
    {
        Print("[POSITIONSIZER] AddModifier: NULL modifier ignored");
        return;
    }
    if(m_modifierCount >= 5)
    {
        Print("[POSITIONSIZER] AddModifier: Max 5 modifiers reached, ignoring ", modifier.GetName());
        return;
    }
    m_modifiers[m_modifierCount] = modifier;
    m_modifierCount++;
    PrintFormat("[POSITIONSIZER] Modifier added: %s (total=%d)", modifier.GetName(), m_modifierCount);
}

#endif // CORE_POSITION_SIZER_MQH

