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

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;

//+------------------------------------------------------------------+
//| Position Sizing Parameters Structure                           |
//+------------------------------------------------------------------+
struct SPositionSizingParams
{
    ENUM_POSITION_SIZING_MODE sizingMode;    // Position sizing method
    double fixedLotSize;                     // Fixed lot size
    double riskPercent;                      // Risk percentage per trade
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
    
public:
    // Constructor
    CPositionSizer(void);
    
    // Destructor
    ~CPositionSizer(void);
    
    // Initialize with parameters
    bool SetParameters(const SPositionSizingParams &params);
    
void SetErrorHandler(CEnhancedErrorHandler* handler) { m_errorHandler = handler; }
    
    // Calculate optimal position size with enhanced risk management
    double CalculateOptimalPositionSize(const string symbol,
                                       const ENUM_ORDER_TYPE orderType,
                                       const double stopLossPips,
                                       const double confidence = 1.0);
    
    // Calculate base position size according to sizing mode
    double CalculateBasePositionSize(const string symbol, const double stopLossPips);
    
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
        
        // Safety check - ensure we have at least 5% buffer (instead of 20%)
        if(marginRequired > freeMargin * 0.95)
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
    m_atrHandle = INVALID_HANDLE;
    // Initialize default parameters
    m_params.sizingMode = POSITION_SIZE_RISK_PERCENT;
    m_params.fixedLotSize = MIN_LOT_SIZE;
    m_params.riskPercent = 1.0;
    m_params.atrPeriod = 14;
    m_params.atrMultiplier = 1.5;
    m_params.maxLotSize = MAX_LOT_SIZE;
    m_params.minLotSize = MIN_LOT_SIZE;
    m_params.correlationAdjustment = 1.0;
    m_params.useVolatilityAdjustment = true;
    m_params.useCorrelationAdjustment = true;
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
    // Validate parameters
    if(params.riskPercent <= 0 || params.riskPercent > MAX_RISK_PER_TRADE)
    {
        LogError(ERROR_RECOVERABLE, "PositionSizer", 
                                   StringFormat("Invalid risk percent: %.2f", params.riskPercent), 0);
        return false;
    }
    
    if(params.fixedLotSize < MIN_LOT_SIZE || params.fixedLotSize > MAX_LOT_SIZE)
    {
        LogError(ERROR_RECOVERABLE, "PositionSizer", 
                                   StringFormat("Invalid fixed lot size: %.2f", params.fixedLotSize), 0);
        return false;
    }
    
    if(params.atrPeriod <= 0 || params.atrPeriod > 100)
    {
        LogError(ERROR_RECOVERABLE, "PositionSizer", 
                                   StringFormat("Invalid ATR period: %d", params.atrPeriod), 0);
        return false;
    }
    
    // AUDIT FIX: Add validation for additional parameters
    if(params.atrMultiplier <= 0 || params.atrMultiplier > 10.0)
    {
        LogError(ERROR_RECOVERABLE, "PositionSizer", 
                                   StringFormat("Invalid ATR multiplier: %.2f", params.atrMultiplier), 0);
        return false;
    }
    
    if(params.maxLotSize <= 0 || params.maxLotSize > MAX_LOT_SIZE)
    {
        LogError(ERROR_RECOVERABLE, "PositionSizer", 
                                   StringFormat("Invalid max lot size: %.2f", params.maxLotSize), 0);
        return false;
    }
    
    if(params.minLotSize <= 0 || params.minLotSize > MAX_LOT_SIZE)
    {
        LogError(ERROR_RECOVERABLE, "PositionSizer", 
                                   StringFormat("Invalid min lot size: %.2f", params.minLotSize), 0);
        return false;
    }
    
    if(params.minLotSize > params.maxLotSize)
    {
        LogError(ERROR_RECOVERABLE, "PositionSizer", 
                                   StringFormat("Min lot size (%.2f) > Max lot size (%.2f)", 
                                               params.minLotSize, params.maxLotSize), 0);
        return false;
    }
    
    if(params.correlationAdjustment <= 0 || params.correlationAdjustment > 2.0)
    {
        LogError(ERROR_RECOVERABLE, "PositionSizer", 
                                   StringFormat("Invalid correlation adjustment: %.2f", params.correlationAdjustment), 0);
        return false;
    }
    
    // Set parameters
    m_params = params;
    m_initialized = true;
    
    if(CheckPointer(m_errorHandler) != POINTER_INVALID)
        LogError(ERROR_INFO, "PositionSizer", 
                               StringFormat("Position sizer initialized - Mode: %d, Risk: %.2f%%", 
                                           params.sizingMode, params.riskPercent), 0);
    
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
        // CRITICAL FIX: Normalize before returning!
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
        // CRITICAL FIX: Normalize before returning!
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
        // CRITICAL FIX: Normalize before returning!
        return NormalizeVolume(symbolParam, MIN_LOT_SIZE);
    }
    
    // Update risk metrics
    UpdateRiskMetrics();
    
    // Calculate base size according to sizing mode
    double baseSize = CalculateBasePositionSize(symbolParam, stopLossPips);
    
    // Apply confidence adjustment
    if(confidence > 0 && confidence != 1.0)
    {
        baseSize *= confidence;
        LogSizingDecision(symbolParam, baseSize, StringFormat("Confidence adjusted (%.2f)", confidence));
    }
    
    // Apply additional adjustments if enabled
    if(m_params.useVolatilityAdjustment && m_params.sizingMode != POSITION_SIZE_VOLATILITY)
    {
        baseSize = CalculateVolatilityBasedSize(symbolParam, baseSize);
    }
    
    if(m_params.useCorrelationAdjustment && m_params.sizingMode != POSITION_SIZE_CORRELATION)
    {
        baseSize = CalculateCorrelationAdjustedSize(symbolParam, baseSize);
    }
    
    // Validate final size
    double finalSize = ValidatePositionSize(symbolParam, baseSize);
    
    // Store for debugging
    m_lastCalculatedSize = finalSize;
    m_lastSymbol = symbolParam;
    m_lastCalculation = TimeCurrent();
    
    return finalSize;
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
    double riskAmount = riskDenominator * (riskPercent / 100.0);

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
    
    // Calculate volatility ratio (normalized ATR)
    double volatilityRatio = atr / currentPriceVal;
    
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
    
    // Normalize volume to symbol's step size FIRST
    validatedSize = NormalizeVolume(symbolParam, validatedSize);
    
    // Check minimum size
    double minSize = CalculateMinViableSize(symbolParam);
    if(validatedSize < minSize)
    {
        validatedSize = minSize;
        LogSizingDecision(symbolParam, validatedSize, "Adjusted to minimum viable size");
    }
    
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
    
    if(validatedSize < m_params.minLotSize)
    {
        validatedSize = m_params.minLotSize;
        LogSizingDecision(symbolParam, validatedSize, "Adjusted to parameter minimum");
    }
    
    // Check margin requirements
    double marginRequired = CalculateMarginRequirement(symbolParam, validatedSize);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    
    if(marginRequired > freeMargin * 0.95) // Use max 95% of free margin
    {
        double safeSize = (freeMargin * 0.95) / (marginRequired / validatedSize);
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
        m_currentTotalRisk = (m_currentTotalRisk / riskDenominator) * 100.0;
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

    if(tickValue <= 0.0 || tickSize <= 0.0 || point <= 0.0)
        return 0.0;

    double stopDistancePrice = stopLossPips * point;
    return (stopDistancePrice / tickSize) * tickValue;
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
//| Calculate correlation between two symbols using historical data     |
//+------------------------------------------------------------------+
double CPositionSizer::CalculateCorrelation(const string symbol1, const string symbol2, int period)
{
    if(period < 10) period = 10;
    if(period > 200) period = 200;
    
    // Get historical close prices for both symbols
    double prices1[];
    double prices2[];
    ArrayResize(prices1, period);
    ArrayResize(prices2, period);
    
    int count1 = 0, count2 = 0;
    for(int i = 0; i < period; i++)
    {
        double close1 = iClose(symbol1, PERIOD_CURRENT, i);
        double close2 = iClose(symbol2, PERIOD_CURRENT, i);
        
        if(close1 > 0)
        {
            prices1[count1] = close1;
            count1++;
        }
        if(close2 > 0)
        {
            prices2[count2] = close2;
            count2++;
        }
    }
    
    // Need at least 10 data points for meaningful correlation
    if(count1 < 10 || count2 < 10)
        return 0.0;
    
    // Use the minimum count
    int n = MathMin(count1, count2);
    ArrayResize(prices1, n);
    ArrayResize(prices2, n);
    
    // Calculate means
    double mean1 = 0.0, mean2 = 0.0;
    for(int i = 0; i < n; i++)
    {
        mean1 += prices1[i];
        mean2 += prices2[i];
    }
    mean1 /= n;
    mean2 /= n;
    
    // Calculate covariance and variances
    double covariance = 0.0;
    double variance1 = 0.0;
    double variance2 = 0.0;
    
    for(int i = 0; i < n; i++)
    {
        double diff1 = prices1[i] - mean1;
        double diff2 = prices2[i] - mean2;
        
        covariance += diff1 * diff2;
        variance1 += diff1 * diff1;
        variance2 += diff2 * diff2;
    }
    
    covariance /= n;
    variance1 /= n;
    variance2 /= n;
    
    // Calculate correlation coefficient
    double stdDev1 = MathSqrt(variance1);
    double stdDev2 = MathSqrt(variance2);
    
    if(stdDev1 > 0.0 && stdDev2 > 0.0)
        return covariance / (stdDev1 * stdDev2);
    
    return 0.0;
}

//+------------------------------------------------------------------+
//| Log position sizing decision                                   |
//+------------------------------------------------------------------+
void CPositionSizer::LogSizingDecision(const string symbolParam, const double size, const string reason)
{
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

#endif // CORE_POSITION_SIZER_MQH
