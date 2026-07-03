//+------------------------------------------------------------------+
//| StrategyBase.mqh
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property version   "2.00"
#property strict

#ifndef STRATEGY_BASE_MQH
#define STRATEGY_BASE_MQH

#include <Object.mqh>
#include "../../Interfaces/IStrategy.mqh"
#include "../Utils/Enums.mqh"
#include "../Engines/RegimeEngine.mqh"
#include "../../IndicatorManager.mqh"
#include "../Trading/TradeManager.mqh"
#include "../Risk/PositionSizer.mqh"
#include "../Risk/UnifiedRiskManager.mqh"
#include "../Utils/ErrorHandling.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CPositionSizer;
class CTradeManager;

class CStrategyBase : public IStrategy
{
protected:
    string            m_name;
    string            m_symbol;
    ENUM_TIMEFRAMES   m_timeframe;
    int               m_magic;
    bool              m_is_initialized;
    bool              m_is_enabled;
    bool              m_is_shutting_down;
    double            m_weight;
    double            m_minConfidence;    // Minimum confidence threshold
    datetime          m_lastSignalTime;
    int               m_totalSignals;
    int               m_successfulSignals;
    int               m_lowConfidenceFiltered;  // Count of filtered low-conf signals
    int               m_errorCount;
    datetime          m_lastErrorTime;
    string            m_lastDecisionReasonTag;
    int               m_regimeDetailedType;   // Regime context from RegimeEngine (ENUM_DETAILED_REGIME as int)
    int               m_strategyCluster;      // Strategy cluster type (ENUM_STRATEGY_CLUSTER as int)

    CTradeManager*    m_tradeManager;
    CPositionSizer*   m_positionSizer;
    CUnifiedRiskManager* m_unifiedRiskManager;  // Unified risk validation gate (injected)
    CEnhancedErrorHandler* m_errorHandler;

    static double     s_defaultMinConfidence;

    static void SetDefaultMinConfidence(const double value);
    static double GetDefaultMinConfidence(void);

public:
    CStrategyBase(const string name, const int magic = 0);
    virtual ~CStrategyBase();

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeManagerPtr, void* positionSizerPtr, void* unifiedRiskManagerPtr = NULL);
    virtual void Deinit(void);

    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence);
    virtual void OnNewBar(void);

    virtual string GetName(void) const;
    virtual ENUM_STRATEGY_TYPE GetType(void) const;
    virtual bool IsEnabled(void) const;
    virtual void SetEnabled(const bool enabled);
    virtual double GetWeight(void) const;
    virtual void SetWeight(const double weight);
    virtual bool ValidateParameters(void);
    virtual datetime GetLastSignalTime(void) const;
    virtual void GetStatistics(int &signals, int &successful, double &accuracy);
    virtual string GetLastDecisionReasonTag(void) const override;
    virtual void SetConfidenceThreshold(double threshold) override;
    virtual ENUM_TRADE_SIGNAL GetQuickProbeSignal() override { return TRADE_SIGNAL_NONE; }


    virtual void Update(void);

    void OverrideMinConfidence(const double value);
    double GetMinConfidence(void) const;

    // Feature 1: Regime-Aware Strategy Weighting - setters
    void SetRegimeContext(int detailedRegime);
    void SetStrategyCluster(int cluster);

protected:
    virtual ENUM_TRADE_SIGNAL ExecuteSignal(double &confidence);
    virtual void HandleNewBar();
    void RecordSignal(const bool successful = false);
    void RecordSignalOutcome(const bool successful);
    void SetDecisionReasonTag(const string tag);

    // Feature 1: Regime-Aware Strategy Weighting
    double GetRegimeConfidenceMultiplier();

    // Feature 2: Volatility Direction Awareness
    ENUM_VOLATILITY_DIRECTION GetVolatilityDirection();
    double GetVolatilityDirectionMultiplier();

    // Feature 3: Multi-Timeframe Confluence
    bool IsAlignedWithHigherTF(int signalDirection);
    ENUM_TIMEFRAMES GetNextHigherTF(ENUM_TIMEFRAMES tf);

public:
    void SetTradeManager(CTradeManager* manager);
    void SetPositionSizer(CPositionSizer* sizer);
    CUnifiedRiskManager* GetUnifiedRiskManager() const { return m_unifiedRiskManager; }
    virtual bool Initialize(void);
    virtual bool IsInitialized(void) const;

    virtual void OnTick();
    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe);
    virtual void OnTimer();

    virtual int GetTotalTrades() const;
    virtual int GetWinningTrades() const;
    virtual int GetLosingTrades() const;
    virtual double GetTotalProfit() const;
    virtual double GetTotalLoss() const;

    virtual void ResetMetrics();
    bool IsErrorRateLimitExceeded();
    string GetSymbol(void) const;
    ENUM_TIMEFRAMES GetTimeframe(void) const;
    int GetMagicNumber(void) const;
};

CStrategyBase::CStrategyBase(const string name, const int magic) :
    m_name(name),
    m_magic(magic),
    m_is_initialized(false),
    m_is_enabled(true),
    m_is_shutting_down(false),
    m_weight(1.0),
    m_minConfidence(GetDefaultMinConfidence()),
    m_lastSignalTime(0),
    m_totalSignals(0),
    m_successfulSignals(0),
    m_lowConfidenceFiltered(0),
    m_errorCount(0),
    m_lastErrorTime(0),
    m_lastDecisionReasonTag("BASE_UNSET"),
    m_regimeDetailedType(0),
    m_strategyCluster(0),
    m_tradeManager(NULL),
    m_positionSizer(NULL),
    m_unifiedRiskManager(NULL),
    m_errorHandler(NULL)
{
    m_symbol = (StringLen(Symbol()) > 0) ? Symbol() : "";
    m_timeframe = (ENUM_TIMEFRAMES)Period();
    m_errorHandler = new CEnhancedErrorHandler();
}

//+------------------------------------------------------------------+
//| Static confidence configuration                                  |
//+------------------------------------------------------------------+
void CStrategyBase::SetDefaultMinConfidence(const double value)
{
    double bounded = MathMax(0.0, MathMin(1.0, value));
    s_defaultMinConfidence = bounded;
}

double CStrategyBase::GetDefaultMinConfidence(void)
{
    return s_defaultMinConfidence;
}

void CStrategyBase::OverrideMinConfidence(const double value)
{
    double bounded = MathMax(0.0, MathMin(1.0, value));
    m_minConfidence = bounded;
}

double CStrategyBase::GetMinConfidence(void) const
{
    return m_minConfidence;
}

double CStrategyBase::s_defaultMinConfidence = 0.30;

CStrategyBase::~CStrategyBase()
{
    if(m_is_shutting_down) return;
    m_is_shutting_down = true;
    if(CheckPointer(m_errorHandler) == POINTER_DYNAMIC)
    {
        delete m_errorHandler;
    }
    m_tradeManager = NULL;
    m_positionSizer = NULL;
    m_errorHandler = NULL;
}

bool CStrategyBase::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeManagerPtr, void* positionSizerPtr, void* unifiedRiskManagerPtr)
{
    if(StringLen(symbol) == 0)
        return false;

    m_symbol = symbol;
    m_timeframe = (timeframe > 0) ? timeframe : (ENUM_TIMEFRAMES)Period();

    if(CheckPointer(tradeManagerPtr) == POINTER_INVALID)
        return false;
    m_tradeManager = (CTradeManager*)tradeManagerPtr;

    if(CheckPointer(positionSizerPtr) == POINTER_INVALID)
        return false;
    m_positionSizer = (CPositionSizer*)positionSizerPtr;

    // Unified risk manager is optional (backward compatibility)
    if(CheckPointer(unifiedRiskManagerPtr) != POINTER_INVALID)
        m_unifiedRiskManager = (CUnifiedRiskManager*)unifiedRiskManagerPtr;

    m_is_initialized = (m_tradeManager != NULL && m_positionSizer != NULL);
    m_lastDecisionReasonTag = m_is_initialized ? "BASE_INITIALIZED" : "BASE_INIT_FAILED";
    return m_is_initialized;
}

void CStrategyBase::Deinit(void)
{
    if(m_is_shutting_down) return;
    m_tradeManager = NULL;
    m_positionSizer = NULL;
    m_unifiedRiskManager = NULL;
    m_is_initialized = false;
    m_lastSignalTime = 0;
    m_errorCount = 0;
    m_lastErrorTime = 0;
    m_lastDecisionReasonTag = "BASE_DEINIT";
}

ENUM_TRADE_SIGNAL CStrategyBase::GetSignal(double &confidence)
{
    confidence = 0.0;
    m_lastDecisionReasonTag = "";
    if(!m_is_enabled || !m_is_initialized)
    {
        m_lastDecisionReasonTag = "BASE_DISABLED_OR_UNINITIALIZED";
        return TRADE_SIGNAL_NONE;
    }
    ENUM_TRADE_SIGNAL signal = ExecuteSignal(confidence);
    if(signal != TRADE_SIGNAL_NONE)
    {
        // Feature 1: Regime-aware confidence adjustment
        confidence *= GetRegimeConfidenceMultiplier();

        // Feature 2: Volatility direction confidence adjustment
        confidence *= GetVolatilityDirectionMultiplier();

        // Feature 3: HTF alignment filter - halve confidence for counter-HTF signals
        if(!IsAlignedWithHigherTF((int)signal))
        {
            confidence *= 0.5;
        }

        RecordSignal();
        if(m_lastDecisionReasonTag == "")
            m_lastDecisionReasonTag = "BASE_SIGNAL";
    }
    else if(m_lastDecisionReasonTag == "")
    {
        m_lastDecisionReasonTag = "BASE_NO_SIGNAL";
    }
    return signal;
}

void CStrategyBase::OnNewBar(void)
{
    OnNewBar(m_symbol, m_timeframe);
}

string CStrategyBase::GetName(void) const
{
    return m_name;
}

ENUM_STRATEGY_TYPE CStrategyBase::GetType(void) const
{
    return (ENUM_STRATEGY_TYPE)STRATEGY_TYPE_CUSTOM;
}

bool CStrategyBase::IsEnabled(void) const
{
    return m_is_enabled;
}

void CStrategyBase::SetEnabled(const bool enabled)
{
    m_is_enabled = enabled;
}

double CStrategyBase::GetWeight(void) const
{
    return m_weight;
}

void CStrategyBase::SetWeight(const double weight)
{
    m_weight = MathMax(0.0, MathMin(5.0, weight));
}

bool CStrategyBase::ValidateParameters(void)
{
    return true;
}

datetime CStrategyBase::GetLastSignalTime(void) const
{
    return m_lastSignalTime;
}

void CStrategyBase::GetStatistics(int &signals, int &successful, double &accuracy)
{
    signals = m_totalSignals;
    successful = m_successfulSignals;
    accuracy = (m_totalSignals > 0 ? ((double)m_successfulSignals / (double)m_totalSignals) * 100.0 : 0.0);
}

string CStrategyBase::GetLastDecisionReasonTag(void) const
{
    return m_lastDecisionReasonTag;
}

void CStrategyBase::Update(void)
{
    if(!m_is_enabled || !m_is_initialized)
        return;
}

ENUM_TRADE_SIGNAL CStrategyBase::ExecuteSignal(double &confidence)
{
    return TRADE_SIGNAL_NONE;
}

void CStrategyBase::HandleNewBar()
{
}

void CStrategyBase::RecordSignal(const bool successful)
{
    m_totalSignals++;
    if(successful)
        m_successfulSignals++;
    m_lastSignalTime = TimeCurrent();
}

void CStrategyBase::RecordSignalOutcome(const bool successful)
{
    if(successful)
        m_successfulSignals++;
}

void CStrategyBase::SetDecisionReasonTag(const string tag)
{
    m_lastDecisionReasonTag = tag;
}

void CStrategyBase::SetConfidenceThreshold(double threshold)
{
    OverrideMinConfidence(threshold);
}

void CStrategyBase::SetTradeManager(CTradeManager* manager)
{
    m_tradeManager = manager;
}

void CStrategyBase::SetPositionSizer(CPositionSizer* sizer)
{
    m_positionSizer = sizer;
}

bool CStrategyBase::Initialize(void)
{
    if(m_is_initialized)
        return true;
    if(m_tradeManager == NULL || m_positionSizer == NULL)
        return false;
    m_is_initialized = true;
    return true;
}

bool CStrategyBase::IsInitialized(void) const
{
    return m_is_initialized;
}

void CStrategyBase::OnTick()
{
}

void CStrategyBase::OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe)
{
    if(!m_is_enabled || !m_is_initialized)
        return;
    if(symbol != m_symbol || timeframe != m_timeframe)
        return;
    HandleNewBar();
}

void CStrategyBase::OnTimer()
{
}

int CStrategyBase::GetTotalTrades() const
{
    return 0;
}

int CStrategyBase::GetWinningTrades() const
{
    return 0;
}

int CStrategyBase::GetLosingTrades() const
{
    return 0;
}

double CStrategyBase::GetTotalProfit() const
{
    return 0.0;
}

double CStrategyBase::GetTotalLoss() const
{
    return 0.0;
}

void CStrategyBase::ResetMetrics()
{
    m_lastSignalTime = 0;
    m_totalSignals = 0;
    m_successfulSignals = 0;
    m_errorCount = 0;
    m_lastErrorTime = 0;
}

bool CStrategyBase::IsErrorRateLimitExceeded()
{
    const int MAX_ERRORS_PER_MINUTE = 10;
    const int ERROR_WINDOW_SECONDS = 60;
    datetime errorWindowNow = TimeCurrent();
    if(errorWindowNow - m_lastErrorTime > ERROR_WINDOW_SECONDS)
    {
        m_errorCount = 0;
    }
    return (m_errorCount >= MAX_ERRORS_PER_MINUTE);
}

string CStrategyBase::GetSymbol(void) const
{
    return m_symbol;
}

ENUM_TIMEFRAMES CStrategyBase::GetTimeframe(void) const
{
    return m_timeframe;
}

int CStrategyBase::GetMagicNumber(void) const
{
    return m_magic;
}

//+------------------------------------------------------------------+
//| Feature 1: Set regime context from RegimeEngine                  |
//+------------------------------------------------------------------+
void CStrategyBase::SetRegimeContext(int detailedRegime)
{
    m_regimeDetailedType = detailedRegime;
}

//+------------------------------------------------------------------+
//| Feature 1: Set strategy cluster type                             |
//+------------------------------------------------------------------+
void CStrategyBase::SetStrategyCluster(int cluster)
{
    m_strategyCluster = cluster;
}

//+------------------------------------------------------------------+
//| Feature 1: Regime-aware confidence multiplier                    |
//+------------------------------------------------------------------+
double CStrategyBase::GetRegimeConfidenceMultiplier()
{
    if(m_strategyCluster == STRATEGY_CLUSTER_NONE) return 1.0;

    bool isStrongTrend = (m_regimeDetailedType == DETAILED_REGIME_STRONG_UPTREND ||
                          m_regimeDetailedType == DETAILED_REGIME_STRONG_DOWNTREND);
    bool isRange = (m_regimeDetailedType == DETAILED_REGIME_HIGH_VOL_RANGE ||
                    m_regimeDetailedType == DETAILED_REGIME_LOW_VOL_RANGE);

    if(m_strategyCluster == TREND_CLUSTER)
    {
        if(isStrongTrend) return 1.5;
        if(isRange) return 0.3;
    }
    else if(m_strategyCluster == MEAN_REVERSION_CLUSTER)
    {
        if(isRange) return 1.5;
        if(isStrongTrend) return 0.2;
    }
    // STRUCTURE_CLUSTER or unknown: neutral
    return 1.0;
}

//+------------------------------------------------------------------+
//| Feature 2: Detect volatility direction via ATR comparison        |
//+------------------------------------------------------------------+
ENUM_VOLATILITY_DIRECTION CStrategyBase::GetVolatilityDirection()
{
    int atrHandle = CIndicatorManager::Instance().GetATRHandle(m_symbol, m_timeframe, 14);
    if(atrHandle == INVALID_HANDLE)
        return VOL_STABLE;

    double atrValues[];
    ArraySetAsSeries(atrValues, true);
    int copied = CopyBuffer(atrHandle, 0, 0, 6, atrValues);
    if(copied < 6)
        return VOL_STABLE;

    double strategyATR = atrValues[0];
    double prevATR = atrValues[5];

    if(prevATR <= 0.0)
        return VOL_STABLE;

    double ratio = strategyATR / prevATR;

    if(ratio > 1.15) return VOL_EXPANDING;
    if(ratio < 0.85) return VOL_CONTRACTING;
    return VOL_STABLE;
}

//+------------------------------------------------------------------+
//| Feature 2: Volatility direction confidence multiplier            |
//+------------------------------------------------------------------+
double CStrategyBase::GetVolatilityDirectionMultiplier()
{
    ENUM_VOLATILITY_DIRECTION volDir = GetVolatilityDirection();
    switch(volDir)
    {
        case VOL_EXPANDING:   return 1.2;  // Breakouts more likely
        case VOL_CONTRACTING: return 0.8;  // Squeeze forming, reduce confidence
        default:              return 1.0;  // VOL_STABLE
    }
}

//+------------------------------------------------------------------+
//| Feature 3: Check if signal aligns with higher TF trend           |
//+------------------------------------------------------------------+
bool CStrategyBase::IsAlignedWithHigherTF(int signalDirection)
{
    ENUM_TIMEFRAMES htf = GetNextHigherTF(m_timeframe);
    if(htf == m_timeframe) return true; // Can't go higher, assume aligned

    int emaHandle = CIndicatorManager::Instance().GetMAHandle(m_symbol, htf, 50, 0, MODE_EMA, PRICE_CLOSE);
    if(emaHandle == INVALID_HANDLE) return true; // Can't determine, assume aligned

    double emaValues[];
    ArraySetAsSeries(emaValues, true);
    int copied = CopyBuffer(emaHandle, 0, 0, 2, emaValues);
    if(copied < 2) return true;

    double closePrice = iClose(m_symbol, htf, 0);
    bool htfBullish = (closePrice > emaValues[0]);

    if(signalDirection == 1 && htfBullish) return true;   // BUY aligned with HTF uptrend
    if(signalDirection == -1 && !htfBullish) return true;  // SELL aligned with HTF downtrend
    return false;
}

//+------------------------------------------------------------------+
//| Feature 3: Get next higher timeframe                             |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES CStrategyBase::GetNextHigherTF(ENUM_TIMEFRAMES tf)
{
    switch(tf)
    {
        case PERIOD_M1:  return PERIOD_M5;
        case PERIOD_M5:  return PERIOD_M15;
        case PERIOD_M15: return PERIOD_M30;
        case PERIOD_M30: return PERIOD_H1;
        case PERIOD_H1:  return PERIOD_H4;
        case PERIOD_H4:  return PERIOD_D1;
        case PERIOD_D1:  return PERIOD_W1;
        case PERIOD_W1:  return PERIOD_MN1;
        default:         return tf;
    }
}

#endif
