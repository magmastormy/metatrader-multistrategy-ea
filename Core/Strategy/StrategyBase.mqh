//+------------------------------------------------------------------+
//| StrategyBase.mqh
//+------------------------------------------------------------------+
#property copyright "Copyright 2025"
#property version   "2.00"
#property strict

#ifndef __STRATEGY_BASE_MQH__
#define __STRATEGY_BASE_MQH__

#include <Object.mqh>
#include "../../Interfaces/IStrategy.mqh"
#include "../Utils/Enums.mqh"
#include "../Trading/TradeManager.mqh"
#include "../Risk/PositionSizer.mqh"
#include "../Utils/ErrorHandling.mqh"

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
    datetime          m_lastSignalTime;
    int               m_totalSignals;
    int               m_successfulSignals;
    int               m_errorCount;
    datetime          m_lastErrorTime;

    CTradeManager*    m_tradeManager;
    CPositionSizer*   m_positionSizer;
    CEnhancedErrorHandler* m_errorHandler;

public:
    CStrategyBase(const string name, const int magic = 0);
    virtual ~CStrategyBase();

    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeManagerPtr, void* positionSizerPtr);
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

    virtual void Update(void);

protected:
    virtual ENUM_TRADE_SIGNAL ExecuteSignal(double &confidence);
    virtual void HandleNewBar();
    void RecordSignal(const bool successful = false);
    void RecordSignalOutcome(const bool successful);

public:
    void SetTradeManager(CTradeManager* manager);
    void SetPositionSizer(CPositionSizer* sizer);
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
    m_lastSignalTime(0),
    m_totalSignals(0),
    m_successfulSignals(0),
    m_errorCount(0),
    m_lastErrorTime(0),
    m_tradeManager(NULL),
    m_positionSizer(NULL),
    m_errorHandler(NULL)
{
    m_symbol = (StringLen(Symbol()) > 0) ? Symbol() : "";
    m_timeframe = (ENUM_TIMEFRAMES)Period();
    m_errorHandler = new CEnhancedErrorHandler();
}

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

bool CStrategyBase::Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeManagerPtr, void* positionSizerPtr)
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

    m_is_initialized = (m_tradeManager != NULL && m_positionSizer != NULL);
    return m_is_initialized;
}

void CStrategyBase::Deinit(void)
{
    if(m_is_shutting_down) return;
    m_tradeManager = NULL;
    m_positionSizer = NULL;
    m_is_initialized = false;
    m_lastSignalTime = 0;
    m_errorCount = 0;
    m_lastErrorTime = 0;
}

ENUM_TRADE_SIGNAL CStrategyBase::GetSignal(double &confidence)
{
    confidence = 0.0;
    if(!m_is_enabled || !m_is_initialized)
        return TRADE_SIGNAL_NONE;
    ENUM_TRADE_SIGNAL signal = ExecuteSignal(confidence);
    if(signal != TRADE_SIGNAL_NONE)
        RecordSignal();
    return signal;
}

void CStrategyBase::OnNewBar(void)
{
    if(!m_is_enabled || !m_is_initialized)
        return;
    HandleNewBar();
}

string CStrategyBase::GetName(void) const
{
    return m_name;
}

ENUM_STRATEGY_TYPE CStrategyBase::GetType(void) const
{
    return STRATEGY_TYPE_CUSTOM;
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

#endif
