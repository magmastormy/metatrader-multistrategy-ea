// Risk-aware position sizing: turns the configured risk % into a broker-legal lot size
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

class CEnhancedErrorHandler;
class CPositionSizer;
class CPerformanceAnalytics;

// Hard ceiling on the min-lot round-up multiplier: rounding a sub-minimum lot up to SYMBOL_VOLUME_MIN multiplies
// the risk the pre-trade gate approved, because sizing happens after that gate.
#ifndef MAX_MIN_LOT_RISK_MULTIPLIER
#define MAX_MIN_LOT_RISK_MULTIPLIER 3.0
#endif

struct SPositionSizingParams
{
    ENUM_POSITION_SIZING_MODE sizingMode;
    double fixedLotSize;
    double riskPercent;                      // Risk % per trade
    double maxLotSize;
    double minLotSize;
    bool useKellySizing;
    bool useVolatilityTargeting;
    bool useEquityCurveScaling;
        double kellyWinRate;
        double kellyPayoffRatio;
        double kellyFraction;                    // Kelly fraction (0.25 = quarter Kelly)
        double kellyMaxCap;
        double volatilityTarget;                 // Target annualized volatility
        double volatilityLookback;
        int atrPeriod;
        double atrMultiplier;
        double equityCurveLookback;
        double equityCurveMinMultiplier;
        double equityCurveMaxMultiplier;
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
        minLotRiskMultiplier(MAX_MIN_LOT_RISK_MULTIPLIER)
    {}
};

class CPositionSizer
{
private:
    SPositionSizingParams m_params;
    
            double m_currentTotalRisk;
            int m_modifierCount;
            CPositionSizerModifier* m_modifiers[];
            bool m_initialized;
    
    double m_portfolioRisk;
    double m_dailyRiskUsed;
    int m_openPositions;
    
    
    CIndicatorManager* m_indicatorManager;
    
    CEnhancedErrorHandler* m_errorHandler;
    
    CPerformanceAnalytics* m_performanceAnalytics;
    
    int m_atrHandle;
    string m_atrSymbol;
    int m_atrPeriod;
    
    CEquityCurveLotModifier* m_equityCurveModifier;
    CVolatilityTargetingModifier* m_volatilityTargetingModifier;
    CVPINLotModifier* m_vpinModifier;

    double CalculateFixedRiskSize(const string symbol, double stopLossPips);
    double CalculateVolatilityTargetSize(const string symbol, double stopLossPips);
    double CalculateEquityCurveSize(const string symbol, double stopLossPips);
        double ApplyModifiers(double baseSize, const string symbol, double stopLossPips, double confidence, const string corrId = "");
            double GetATR(const string symbol, int period, ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT);
        void UpdateRiskMetrics();
    void InvalidateATRHandle(const string symbol);

public:
    CPositionSizer();
    ~CPositionSizer();
    
    bool Initialize(const SPositionSizingParams &params);
    
    bool IsInitialized() const { return m_initialized; }
    
    void RegisterVPINFilter(const string symbol, CVPINFilter* filter);
    int  VPINFilterCount() const;
    string DescribeModifiers() const;
    void SetIndicatorManager(CIndicatorManager* manager);
    void SetErrorHandler(CEnhancedErrorHandler* handler);
    void SetPerformanceAnalytics(CPerformanceAnalytics* analytics);
    
    bool AddModifier(CPositionSizerModifier* modifier);
    
        double CalculatePositionSize(const string symbol, double stopLossPips, double confidence = 1.0);
        double CalculatePositionSizeWithMode(const string symbol, double stopLossPips, ENUM_POSITION_SIZING_MODE mode, double confidence = 1.0);
        double CalculatePositionSizeWithRisk(const string symbol, double stopLossPips, double riskPercent, double confidence = 1.0);
    
                double CapLotForDailyBudget(const string symbol, ENUM_ORDER_TYPE orderType, double lotSize,
                                             double stopLossPips, double tradeRiskPercent,
                                             double remainingDailyRisk, double maxBudgetFraction);
    
            bool ValidatePositionSize(const string symbol, double &lotSize, double stopLossPips);
    
    double GetCurrentTotalRisk() const;
    double GetDailyRiskUsed() const;
    void RegisterTradeRisk(double riskPercent);
    void UnregisterTradeRisk(double riskPercent);
    void ResetDailyRisk();
    
    void UpdateRiskPercent(double newRiskPercent);
    void UpdateMaxLotSize(double newMaxLotSize);
    void UpdateMinLotSize(double newMinLotSize);
    void SetAllowMinLotRoundUp(bool allow);
    void SetMinLotRiskMultiplier(double multiplier);
    
    // Parameter snapshot
    SPositionSizingParams GetParameters() const;
    bool SetParameters(const SPositionSizingParams &params);
    
    // Contract-spec risk helpers
    double GetRiskDenominator(void);
    double CalculateRiskPerLot(const string symbol, const double stopLossPips);
    
    
        double NormalizeVolume(const string symbolParam, double volume);
    
        void ClearModifiers();
    
        void SetLogLevel(int level);
    
        string GetDiagnostics() const;
    };

    #endif // CORE_POSITION_SIZER_MQH


CPositionSizer::CPositionSizer() :
    m_currentTotalRisk(0.0),
    m_modifierCount(0),
    m_portfolioRisk(0.0),
    m_dailyRiskUsed(0.0),
    m_openPositions(0),
    m_indicatorManager(NULL),
    m_errorHandler(NULL),
    m_performanceAnalytics(NULL),
    m_atrHandle(INVALID_HANDLE),
    m_atrSymbol(""),
    m_atrPeriod(14),
    m_equityCurveModifier(NULL),
    m_volatilityTargetingModifier(NULL),
    m_vpinModifier(NULL),
    m_initialized(false)
{
    ArrayResize(m_modifiers, 10);
    for(int i = 0; i < 10; i++)
        m_modifiers[i] = NULL;
}

CPositionSizer::~CPositionSizer()
{
    // Deletes only the modifiers this sizer created (volatility, equity curve, ADX, VPIN). Modifiers handed to
    // AddModifier() belong to the EA, and m_modifiers[] holds non-owning references: never delete through the array.

    if(m_volatilityTargetingModifier != NULL) { delete m_volatilityTargetingModifier; m_volatilityTargetingModifier = NULL; }
    if(m_equityCurveModifier != NULL) { delete m_equityCurveModifier; m_equityCurveModifier = NULL; }
    if(m_vpinModifier != NULL) { delete m_vpinModifier; m_vpinModifier = NULL; }
    
    for(int i = 0; i < m_modifierCount; i++)
    {
        m_modifiers[i] = NULL;
    }
    m_modifierCount = 0;
    
    // Released only because this sizer created the handle itself
    if(m_atrHandle != INVALID_HANDLE)
    {
        IndicatorRelease(m_atrHandle);
        m_atrHandle = INVALID_HANDLE;
    }
}

bool CPositionSizer::Initialize(const SPositionSizingParams &params)
{
    m_params = params;
    m_currentTotalRisk = 0.0;
    m_dailyRiskUsed = 0.0;
    m_openPositions = 0;
    
    // useKellySizing does nothing here: the Bayesian Kelly modifier is registered by EAOrchestrator

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
    
    // ADX is not registered here: CEAOrchestrator adds the configured CADXLotModifier to this
    // same chain, so a second instance multiplied the tier again - ADX >= 30 shipped 1.69x and
    // 2.25x the lot the risk math had computed.
    
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

// The per-symbol VPIN filters live in the math hub, which is what feeds them ticks; the lot modifier
// holds references, so toxicity sizing shrinks a lot it never sized.
void CPositionSizer::RegisterVPINFilter(const string symbol, CVPINFilter* filter)
{
    if(m_vpinModifier != NULL)
        m_vpinModifier.RegisterFilter(symbol, filter);
}

int CPositionSizer::VPINFilterCount() const
{
    return (m_vpinModifier != NULL) ? m_vpinModifier.FilterCount() : 0;
}

// Which modifiers actually sit in the chain, by name: the count and the list are the only way an operator
// can see whether a sizing input reached a multiplier at all.
string CPositionSizer::DescribeModifiers() const
{
    string names = "";
    for(int i = 0; i < m_modifierCount; i++)
    {
        if(m_modifiers[i] == NULL) continue;
        if(names != "") names += ",";
        names += m_modifiers[i].GetName();
    }
    return names;
}

void CPositionSizer::SetIndicatorManager(CIndicatorManager* manager)
{
    m_indicatorManager = manager;
}

void CPositionSizer::SetErrorHandler(CEnhancedErrorHandler* handler)
{
    m_errorHandler = handler;
}

void CPositionSizer::SetPerformanceAnalytics(CPerformanceAnalytics* analytics)
{
    m_performanceAnalytics = analytics;
}

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
            // KELLY sizes on fixed risk; the Bayesian Kelly modifier (EAOrchestrator) does the adjusting
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
    
        double finalSize = ApplyModifiers(baseSize, symbol, stopLossPips, confidence);
    
    if(!ValidatePositionSize(symbol, finalSize, stopLossPips))
    {
        return 0.0;
    }
    
    return finalSize;
}

double CPositionSizer::CalculatePositionSizeWithMode(const string symbol, double stopLossPips, ENUM_POSITION_SIZING_MODE mode, double confidence)
{
    ENUM_POSITION_SIZING_MODE oldMode = m_params.sizingMode;
    m_params.sizingMode = mode;
    double size = CalculatePositionSize(symbol, stopLossPips, confidence);
    m_params.sizingMode = oldMode;
        return size;
    }

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

    double CPositionSizer::CapLotForDailyBudget(const string symbol, ENUM_ORDER_TYPE orderType, double lotSize,
                                                double stopLossPips, double proposedRisk,
                                                double remainingDailyRisk, double maxBudgetFraction)
    {
        if(lotSize <= 0.0 || remainingDailyRisk <= 0.0 || proposedRisk <= 0.0)
            return lotSize;
    
        // Lot ceiling from the remaining daily risk budget, scaled by maxBudgetFraction
        double maxLotByBudget = lotSize * (remainingDailyRisk / proposedRisk) * maxBudgetFraction;
    
        double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
        double marginPerLot = 0.0;
        double priceForMargin = (orderType == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
    
        if(OrderCalcMargin(orderType, symbol, 1.0, priceForMargin, marginPerLot) && marginPerLot > 0.0)
        {
            double maxLotByMargin = freeMargin / (marginPerLot * 1.5);
            maxLotByBudget = MathMin(maxLotByBudget, maxLotByMargin);
        }
    
        double symbolMaxVolume = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        if(symbolMaxVolume > 0.0)
            maxLotByBudget = MathMin(maxLotByBudget, symbolMaxVolume);
    
        // A budget cap may only shrink the lot, never grow it
        double cappedLot = MathMin(lotSize, maxLotByBudget);
    
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
    
    // Tier ceiling recomputed from the tier's own risk %
    double tierRiskPct = m_params.riskPercent;
    double riskDenominator = GetRiskDenominator();
    double tierMaxRisk = riskDenominator * (tierRiskPct / 100.0);
    double maxLotByTier = tierMaxRisk / riskPerLot;
    
    if(lotSize > maxLotByTier)
    {
        lotSize = maxLotByTier;
        PrintFormat("[PositionSizer] Tier cap applied | symbol=%s | lot=%.2f", symbol, lotSize);
    }
    
    if(lotSize < m_params.minLotSize)
        lotSize = m_params.minLotSize;
    if(lotSize > m_params.maxLotSize)
        lotSize = m_params.maxLotSize;
    
    return NormalizeVolume(symbol, lotSize);
}

double CPositionSizer::CalculateVolatilityTargetSize(const string symbol, double stopLossPips)
{
    if(m_volatilityTargetingModifier == NULL)
        return CalculateFixedRiskSize(symbol, stopLossPips);
    
    double baseSize = CalculateFixedRiskSize(symbol, stopLossPips);
    return m_volatilityTargetingModifier.AdjustLotSize(baseSize, symbol, 1.0);
}

double CPositionSizer::CalculateEquityCurveSize(const string symbol, double stopLossPips)
{
    if(m_equityCurveModifier == NULL)
        return CalculateFixedRiskSize(symbol, stopLossPips);
    
    double baseSize = CalculateFixedRiskSize(symbol, stopLossPips);
    return m_equityCurveModifier.AdjustLotSize(baseSize, symbol, 1.0);
}

double CPositionSizer::ApplyModifiers(double baseSize, const string symbol, double stopLossPips, double confidence, const string corrId = "")
{
    double currentSize = baseSize;
    
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

// false = refuse the send: rounding here would change the risk the pre-trade gate approved
bool CPositionSizer::ValidatePositionSize(const string symbol, double &lotSize, double stopLossPips)
{
    if(lotSize <= 0.0)
        return false;
    
    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double stepLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
    
    if(minLot > 0.0 && lotSize < minLot)
        {
            if(m_params.allowMinLotRoundUp)
            {
                double riskRatio = minLot / lotSize;
                // Ceiling already clamped to MAX_MIN_LOT_RISK_MULTIPLIER (3.0) in SetMinLotRiskMultiplier
                if(riskRatio > m_params.minLotRiskMultiplier)
                {
                    CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "PositionSizer",
                             StringFormat("Min lot round-up refused: %.2f -> %.2f lots is %.2fx the sized risk, ceiling %.2fx (raise the stop distance or accept %.2fx to trade this symbol at min lot)",
                                         lotSize, minLot, riskRatio, m_params.minLotRiskMultiplier,
                                         m_params.minLotRiskMultiplier), 0);
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
    
    if(stepLot > 0.0)
    {
        // Floor to whole SYMBOL_VOLUME_STEP and clean FP dust at 8 digits: NormalizeDouble(...,2) pushed a
        // 0.001-step lot (0.999) back off-step and the broker rejected it as invalid volume
        long wholeSteps = (long)MathFloor(lotSize / stepLot + 1e-9);
        lotSize = NormalizeDouble(wholeSteps * stepLot, 8);
    }
    
    if(lotSize < m_params.minLotSize || lotSize > m_params.maxLotSize)
        return false;
    
    return true;
}

double CPositionSizer::NormalizeVolume(const string symbolParam, double volume)
{
    double step = SymbolInfoDouble(symbolParam, SYMBOL_VOLUME_STEP);
    double minVol = SymbolInfoDouble(symbolParam, SYMBOL_VOLUME_MIN);
    double maxVol = SymbolInfoDouble(symbolParam, SYMBOL_VOLUME_MAX);
    
    if(step <= 0.0)
        return volume;
    
    // Same step floor as ValidatePositionSize: 8 digits, never 2dp
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
    // Enforced in code, not config: a min-lot round-up multiplies the risk the pre-trade gate approved, so this
    // multiplier IS the per-trade risk cap on a small account (risk 1.0% x 15.0 would let one position risk 15%)
    double clamped = MathMin(MathMax(1.0, multiplier), MAX_MIN_LOT_RISK_MULTIPLIER);
    if(MathAbs(clamped - multiplier) > 0.000001)
        PrintFormat("[RISK-MINLOT] round-up multiplier %.2fx requested, %.2fx applied (code ceiling - a min-lot round-up multiplies the risk the pre-trade gate approved)",
                    multiplier, clamped);

    m_params.minLotRiskMultiplier = clamped;
}

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

// Account risk denominator: must stay in sync with CPortfolioRiskManager::GetRiskDenominator so every risk
// component measures against the same value
double CPositionSizer::GetRiskDenominator(void)
{
    return CRiskMath::GetRiskDenominator();
}

// Money-risked per 1.0 lot for a stop distance in pips
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

    // pips*point is the convention everywhere (CTradeMgrPricing::CalculateStops places stops that way and URM risk
    // math reads them the same way); the old pips*point*10.0 pip-vs-point mistake made per-lot risk 10x high, so
    // FIXED_RISK traded about 1/10 of the configured risk.
    double slDistancePrice = stopLossPips * point;
    double slTicks = slDistancePrice / tickSize;

    double riskPerLot = slTicks * tickValue;

    // Reprice into the account currency when the symbol pays out in another one
    if(profitCurrency != accountCurrency)
    {
        string directPair = profitCurrency + accountCurrency;
        if(SymbolInfoInteger(directPair, SYMBOL_SELECT))
        {
            double rate = SymbolInfoDouble(directPair, SYMBOL_BID);
            if(rate > 0.0)
                riskPerLot *= rate;
        }
        else
        {
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

double CPositionSizer::GetATR(const string symbol, int period, ENUM_TIMEFRAMES timeframe)
{
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

    // Fallback: this sizer's own handle, rebuilt when symbol or period changes
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

void CPositionSizer::InvalidateATRHandle(const string symbol)
{
    if(m_atrHandle != INVALID_HANDLE && m_atrSymbol == symbol)
    {
        IndicatorRelease(m_atrHandle);
        m_atrHandle = INVALID_HANDLE;
        m_atrSymbol = "";
    }
}

void CPositionSizer::UpdateRiskMetrics()
{
    m_currentTotalRisk = 0.0;
    m_openPositions = 0;

    // Counts every open position on the account: no magic-number filter here, unlike the daily-loss breaker
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
        
        // Pips back out as price distance / point only: stops sit at pips*point and CalculateRiskPerLot expects that
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
    // No post-loop division by the risk denominator: riskPct is already a percentage, and dividing again understated
    // m_currentTotalRisk (~100x on $10k equity), permanently disarming the portfolio-risk cap.
}

string CPositionSizer::GetDiagnostics() const
{
    return StringFormat("PosSizer: Risk=%.2f%% | Daily=%.2f%% | Open=%d | Modifiers=%d",
                        m_currentTotalRisk, m_dailyRiskUsed, m_openPositions, m_modifierCount);
}

// Clear all modifiers (non-owning clear - EA owns modifiers)
void CPositionSizer::ClearModifiers()
{
    for(int i = 0; i < m_modifierCount; i++)
    {
        m_modifiers[i] = NULL;
    }
    m_modifierCount = 0;
    Print("[PositionSizer] All modifiers cleared (non-owning)");
}

void CPositionSizer::SetLogLevel(int level)
{
    if(level < 0) level = 0;
    if(level > 3) level = 3;
    PrintFormat("[PositionSizer] Log level set to %d", level);
}