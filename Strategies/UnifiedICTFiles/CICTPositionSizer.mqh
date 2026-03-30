//+------------------------------------------------------------------+
//| CICTPositionSizer.mqh                                            |
//| ICT-Specific Position Sizing Engine                              |
//| P1-C: Pure risk-based lot sizing anchored to SL distance         |
//| P3-D: Daily/weekly risk guards                                   |
//| Copyright 2025, Multi-Strategy EA                                |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef __ICT_POSITION_SIZER_MQH__
#define __ICT_POSITION_SIZER_MQH__

//+------------------------------------------------------------------+
//| ICT Position Sizer Class                                        |
//+------------------------------------------------------------------+
class CICTPositionSizer
{
private:
    string          m_symbol;

    // Risk parameters
    double          m_riskPctPerTrade;      // % of account to risk per trade (e.g., 1.0 = 1%)
    double          m_maxDailyDrawdownPct;  // Maximum daily loss as % of account (e.g., 3.0 = 3%)
    double          m_maxWeeklyDrawdownPct; // Maximum weekly loss as % of account (e.g., 6.0 = 6%)
    double          m_maxLotSize;           // Hard cap on lot size
    double          m_minLotSize;           // Broker minimum

    // Drawdown tracking
    double          m_startOfDayBalance;
    double          m_startOfWeekBalance;
    datetime        m_lastDayReset;
    datetime        m_lastWeekReset;
    double          m_dailyPnL;
    double          m_weeklyPnL;

    // Internal helpers
    void            UpdateDailyTracking();
    void            UpdateWeeklyTracking();
    double          GetTickValue();
    double          GetTickSize();

public:
                    CICTPositionSizer();
                   ~CICTPositionSizer();

    // Initialization
    bool            Initialize(const string symbol,
                               double riskPctPerTrade  = 1.0,
                               double maxDailyDDPct    = 3.0,
                               double maxWeeklyDDPct   = 6.0,
                               double maxLotSize       = 100.0);

    // P1-C: Core sizing method
    // Returns the lot size that risks exactly riskPctPerTrade% of the account
    // given the distance from entry to stop loss.
    double          CalculateLotSize(double entryPrice, double stopLossPrice);

    // P3-D: Risk guards — call before placing any trade
    bool            CanTrade(string &reason);

    // Drawdown tracker — call on each account update or OnTick
    void            Update();

    // Getters
    double          GetRiskPct()          const { return m_riskPctPerTrade; }
    double          GetDailyPnL()         const { return m_dailyPnL; }
    double          GetWeeklyPnL()        const { return m_weeklyPnL; }
    double          GetDailyDDUsedPct()   const;
    double          GetWeeklyDDUsedPct()  const;

    // Setters
    void            SetRiskPct(double pct)        { m_riskPctPerTrade = MathMax(0.01, MathMin(pct, 10.0)); }
    void            SetMaxDailyDD(double pct)     { m_maxDailyDrawdownPct = pct; }
    void            SetMaxWeeklyDD(double pct)    { m_maxWeeklyDrawdownPct = pct; }
    void            SetMaxLotSize(double lots)    { m_maxLotSize = MathMax(lots, 0.01); }
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CICTPositionSizer::CICTPositionSizer() :
    m_symbol(""),
    m_riskPctPerTrade(1.0),
    m_maxDailyDrawdownPct(3.0),
    m_maxWeeklyDrawdownPct(6.0),
    m_maxLotSize(100.0),
    m_minLotSize(0.01),
    m_startOfDayBalance(0),
    m_startOfWeekBalance(0),
    m_lastDayReset(0),
    m_lastWeekReset(0),
    m_dailyPnL(0),
    m_weeklyPnL(0)
{}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CICTPositionSizer::~CICTPositionSizer()
{}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CICTPositionSizer::Initialize(const string symbol,
                                   double riskPctPerTrade,
                                   double maxDailyDDPct,
                                   double maxWeeklyDDPct,
                                   double maxLotSize)
{
    m_symbol               = symbol;
    m_riskPctPerTrade      = MathMax(0.01, MathMin(riskPctPerTrade, 10.0));
    m_maxDailyDrawdownPct  = maxDailyDDPct;
    m_maxWeeklyDrawdownPct = maxWeeklyDDPct;
    m_maxLotSize           = MathMax(maxLotSize, 0.01);
    m_minLotSize           = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);

    double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
    m_startOfDayBalance  = balance;
    m_startOfWeekBalance = balance;

    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    m_lastDayReset  = TimeCurrent();
    m_lastWeekReset = TimeCurrent();

    Print("[ICT-SIZER] Initialized | Symbol:", m_symbol,
          " | Risk:", m_riskPctPerTrade, "%",
          " | MaxDD Day:", m_maxDailyDrawdownPct, "%",
          " | MaxDD Week:", m_maxWeeklyDrawdownPct, "%");

    return true;
}

//+------------------------------------------------------------------+
//| Get Tick Value                                                   |
//+------------------------------------------------------------------+
double CICTPositionSizer::GetTickValue()
{
    return SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
}

//+------------------------------------------------------------------+
//| Get Tick Size                                                    |
//+------------------------------------------------------------------+
double CICTPositionSizer::GetTickSize()
{
    double ts = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
    return (ts > 0) ? ts : SymbolInfoDouble(m_symbol, SYMBOL_POINT);
}

//+------------------------------------------------------------------+
//| P1-C: Calculate Lot Size                                        |
//+------------------------------------------------------------------+
// Formula:
//   SL_Distance (in price) = |entry - stopLoss|
//   SL_Distance (in ticks) = SL_Distance / tick_size
//   Risk_per_tick (per lot) = tick_value
//   RiskableAmount = account_balance * riskPct / 100
//   Lots = RiskableAmount / (SL_in_ticks * tick_value_per_lot)
double CICTPositionSizer::CalculateLotSize(double entryPrice, double stopLossPrice)
{
    // Validate inputs
    double slDistance = MathAbs(entryPrice - stopLossPrice);
    if(slDistance <= 0)
    {
        Print("[ICT-SIZER] WARNING: Zero SL distance — returning min lot");
        return m_minLotSize;
    }

    double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = balance * (m_riskPctPerTrade / 100.0);

    double tickSize  = GetTickSize();
    double tickValue = GetTickValue();

    if(tickSize <= 0 || tickValue <= 0)
    {
        Print("[ICT-SIZER] ERROR: Invalid tick data — cannot calculate lots");
        return m_minLotSize;
    }

    double slInTicks     = slDistance / tickSize;
    double riskPerLot    = slInTicks * tickValue;

    if(riskPerLot <= 0)
    {
        Print("[ICT-SIZER] ERROR: riskPerLot = 0 — returning min lot");
        return m_minLotSize;
    }

    double rawLots = riskAmount / riskPerLot;

    // Round to broker lot step
    double lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
    if(lotStep > 0)
        rawLots = MathFloor(rawLots / lotStep) * lotStep;

    // Clamp to min/max
    rawLots = MathMax(m_minLotSize, MathMin(rawLots, m_maxLotSize));

    PrintFormat("[ICT-SIZER] Lots=%.2f | Risk=$%.2f | SL=%.5f pts | TickVal=%.5f | Balance=%.2f",
                rawLots, riskAmount, slDistance, tickValue, balance);

    return rawLots;
}

//+------------------------------------------------------------------+
//| Update Tracking                                                  |
//+------------------------------------------------------------------+
void CICTPositionSizer::Update()
{
    UpdateDailyTracking();
    UpdateWeeklyTracking();
}

void CICTPositionSizer::UpdateDailyTracking()
{
    MqlDateTime now, lastReset;
    TimeToStruct(TimeCurrent(), now);
    TimeToStruct(m_lastDayReset, lastReset);

    if(now.day != lastReset.day || now.mon != lastReset.mon)
    {
        m_startOfDayBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        m_lastDayReset = TimeCurrent();
        m_dailyPnL = 0;
        Print("[ICT-SIZER] Daily reset | Balance:", m_startOfDayBalance);
    }

    double dailyEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    m_dailyPnL = dailyEquity - m_startOfDayBalance;
}

void CICTPositionSizer::UpdateWeeklyTracking()
{
    MqlDateTime now, lastReset;
    TimeToStruct(TimeCurrent(), now);
    TimeToStruct(m_lastWeekReset, lastReset);

    // Reset on Monday (day_of_week == 1)
    if(now.day_of_week == 1 && lastReset.day_of_week != 1)
    {
        m_startOfWeekBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        m_lastWeekReset = TimeCurrent();
        m_weeklyPnL = 0;
        Print("[ICT-SIZER] Weekly reset | Balance:", m_startOfWeekBalance);
    }

    double weeklyEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    m_weeklyPnL = weeklyEquity - m_startOfWeekBalance;
}

//+------------------------------------------------------------------+
//| P3-D: Can Trade — Daily/Weekly Risk Guards                       |
//+------------------------------------------------------------------+
bool CICTPositionSizer::CanTrade(string &reason)
{
    Update();

    // Guard 1: Daily drawdown check
    if(m_startOfDayBalance > 0)
    {
        double dailyDDPct = (m_dailyPnL / m_startOfDayBalance) * 100.0;
        if(dailyDDPct <= -m_maxDailyDrawdownPct)
        {
            reason = StringFormat("Daily DD limit hit: %.2f%% (max: %.2f%%)",
                                  dailyDDPct, -m_maxDailyDrawdownPct);
            Print("[ICT-SIZER] BLOCKED: " + reason);
            return false;
        }
    }

    // Guard 2: Weekly drawdown check
    if(m_startOfWeekBalance > 0)
    {
        double weeklyDDPct = (m_weeklyPnL / m_startOfWeekBalance) * 100.0;
        if(weeklyDDPct <= -m_maxWeeklyDrawdownPct)
        {
            reason = StringFormat("Weekly DD limit hit: %.2f%% (max: %.2f%%)",
                                  weeklyDDPct, -m_maxWeeklyDrawdownPct);
            Print("[ICT-SIZER] BLOCKED: " + reason);
            return false;
        }
    }

    reason = "";
    return true;
}

//+------------------------------------------------------------------+
//| Get Daily DD Used Pct                                            |
//+------------------------------------------------------------------+
double CICTPositionSizer::GetDailyDDUsedPct() const
{
    if(m_startOfDayBalance <= 0) return 0;
    return (m_dailyPnL / m_startOfDayBalance) * 100.0;
}

//+------------------------------------------------------------------+
//| Get Weekly DD Used Pct                                           |
//+------------------------------------------------------------------+
double CICTPositionSizer::GetWeeklyDDUsedPct() const
{
    if(m_startOfWeekBalance <= 0) return 0;
    return (m_weeklyPnL / m_startOfWeekBalance) * 100.0;
}

#endif // __ICT_POSITION_SIZER_MQH__
