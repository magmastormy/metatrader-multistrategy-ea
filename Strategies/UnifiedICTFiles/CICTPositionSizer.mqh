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
    bool            LoadClosedTradeStats(const int lookbackTrades,
                                         int &sampleCount,
                                         int &wins,
                                         int &losses,
                                         double &avgWin,
                                         double &avgLoss);

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
    double          GetKellyRiskPct(const int lookbackTrades = 50);
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
    double effectiveRiskPct = m_riskPctPerTrade;
    double kellyRiskPct = GetKellyRiskPct(50);
    if(kellyRiskPct > 0.0)
        effectiveRiskPct = MathMin(effectiveRiskPct, kellyRiskPct);

    double riskAmount = balance * (effectiveRiskPct / 100.0);

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

    PrintFormat("[ICT-SIZER] Lots=%.2f | Risk=$%.2f | RiskPct=%.2f | KellyCap=%.2f | SL=%.5f pts | TickVal=%.5f | Balance=%.2f",
                rawLots, riskAmount, effectiveRiskPct, kellyRiskPct, slDistance, tickValue, balance);

    return rawLots;
}

bool CICTPositionSizer::LoadClosedTradeStats(const int lookbackTrades,
                                             int &sampleCount,
                                             int &wins,
                                             int &losses,
                                             double &avgWin,
                                             double &avgLoss)
{
    sampleCount = 0;
    wins = 0;
    losses = 0;
    avgWin = 0.0;
    avgLoss = 0.0;

    if(m_symbol == "" || lookbackTrades <= 0)
        return false;

    if(!HistorySelect(0, TimeCurrent()))
        return false;

    double grossWin = 0.0;
    double grossLoss = 0.0;
    int totalDeals = HistoryDealsTotal();

    for(int i = totalDeals - 1; i >= 0 && sampleCount < lookbackTrades; i--)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        if(dealTicket == 0)
            continue;

        if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != m_symbol)
            continue;

        long entryType = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
        if(entryType != DEAL_ENTRY_OUT && entryType != DEAL_ENTRY_OUT_BY)
            continue;

        long reason = HistoryDealGetInteger(dealTicket, DEAL_REASON);
        if(reason != DEAL_REASON_EXPERT)
            continue;

        double netPnl = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                        HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                        HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
        if(!MathIsValidNumber(netPnl) || MathAbs(netPnl) < 0.01)
            continue;

        sampleCount++;
        if(netPnl > 0.0)
        {
            wins++;
            grossWin += netPnl;
        }
        else
        {
            losses++;
            grossLoss += MathAbs(netPnl);
        }
    }

    if(wins > 0)
        avgWin = grossWin / (double)wins;
    if(losses > 0)
        avgLoss = grossLoss / (double)losses;

    return (sampleCount > 0);
}

double CICTPositionSizer::GetKellyRiskPct(const int lookbackTrades)
{
    int sampleCount = 0;
    int wins = 0;
    int losses = 0;
    double avgWin = 0.0;
    double avgLoss = 0.0;

    if(!LoadClosedTradeStats(lookbackTrades, sampleCount, wins, losses, avgWin, avgLoss))
        return 0.0;

    if(sampleCount < 12 || wins <= 0 || losses <= 0 || avgWin <= 0.0 || avgLoss <= 0.0)
        return 0.0;

    double winRate = (double)wins / (double)sampleCount;
    double payoffRatio = avgWin / avgLoss;
    if(payoffRatio <= 0.0)
        return 0.0;

    double kellyFraction = winRate - ((1.0 - winRate) / payoffRatio);
    if(kellyFraction <= 0.0)
        return 0.0;

    double halfKellyPct = kellyFraction * 50.0;
    return MathMax(0.0, MathMin(m_riskPctPerTrade, halfKellyPct));
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
//| NOTE: Drawdown protection is now handled by CUnifiedRiskManager  |
//| (Phase 2.1). This method no longer independently blocks trading  |
//| based on drawdown — that authority belongs to the unified manager.|
//| The sizer still tracks daily/weekly PnL for informational use.   |
//+------------------------------------------------------------------+
bool CICTPositionSizer::CanTrade(string &reason)
{
    Update();

    // Drawdown guards REMOVED — CUnifiedRiskManager is now the single
    // drawdown authority. Daily/weekly DD limits (3%/6%) were redundant
    // with the unified manager's warning (6%) and critical (12%) tiers.
    // Keeping the PnL tracking for informational getters only.

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
