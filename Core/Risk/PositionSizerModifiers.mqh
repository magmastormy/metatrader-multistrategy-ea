//+------------------------------------------------------------------+
//| PositionSizerModifiers.mqh                                       |
//| Pluggable lot-size modifiers for CPositionSizer                  |
//| Phase 5: Position Sizer Consolidation                            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "1.00"
#property strict

#ifndef CORE_RISK_POSITION_SIZER_MODIFIERS_MQH
#define CORE_RISK_POSITION_SIZER_MODIFIERS_MQH

#include "../../IndicatorManager.mqh"

//+------------------------------------------------------------------+
//| Abstract modifier interface                                      |
//| Strategy-specific sizers become parameter providers rather than   |
//| independent calculators. Each modifier adjusts the base lot size |
//| computed by CPositionSizer.                                      |
//+------------------------------------------------------------------+
class CPositionSizerModifier
{
public:
    virtual double AdjustLotSize(double baseLot, string symbol, double confidence) = 0;
    virtual string GetName() = 0;
};

//+------------------------------------------------------------------+
//| ADX Lot Modifier                                                 |
//| Wraps the ADX-tiered logic from CADXPositionSizing.              |
//| Gets ADX value, applies multiplier:                              |
//|   0x no trend, 0.5x weak, 1.0x normal, 1.3x strong, 1.5x very  |
//+------------------------------------------------------------------+
class CADXLotModifier : public CPositionSizerModifier
{
private:
    int    m_adxHandle;
    string m_symbol;
    int    m_adxPeriod;

    // Thresholds (matching CADXPositionSizing defaults)
    double m_noTrendThreshold;      // Below this = no trade (0x)
    double m_weakThreshold;         // Weak trend threshold
    double m_normalThreshold;       // Normal trend threshold
    double m_strongThreshold;       // Strong trend threshold

    // Multipliers
    double m_weakMultiplier;        // 0.5x for weak trends
    double m_normalMultiplier;      // 1.0x for normal trends
    double m_strongMultiplier;      // 1.3x for strong trends
    double m_veryStrongMultiplier;  // 1.5x for very strong

    double GetADX()
    {
        if(m_adxHandle == INVALID_HANDLE) return 0.0;

        double adx[];
        ArraySetAsSeries(adx, true);
        if(CopyBuffer(m_adxHandle, 0, 0, 1, adx) <= 0)
            return 0.0;

        return adx[0];
    }

public:
    CADXLotModifier() :
        m_adxHandle(INVALID_HANDLE),
        m_symbol(""),
        m_adxPeriod(14),
        m_noTrendThreshold(20.0),
        m_weakThreshold(25.0),
        m_normalThreshold(30.0),
        m_strongThreshold(40.0),
        m_weakMultiplier(0.5),
        m_normalMultiplier(1.0),
        m_strongMultiplier(1.3),
        m_veryStrongMultiplier(1.5)
    {}

    ~CADXLotModifier()
    {
        if(m_adxHandle != INVALID_HANDLE)
        {
            IndicatorRelease(m_adxHandle);
            m_adxHandle = INVALID_HANDLE;
        }
    }

    bool Initialize(const string symbol, const ENUM_TIMEFRAMES timeframe = PERIOD_CURRENT,
                    const int adxPeriod = 14)
    {
        m_symbol = symbol;
        m_adxPeriod = adxPeriod;

        // Try shared indicator manager first
        CIndicatorManager* indicatorManager = CIndicatorManager::Instance();
        if(indicatorManager != NULL)
        {
            m_adxHandle = indicatorManager.GetADXHandle(symbol, timeframe, adxPeriod);
            if(m_adxHandle != INVALID_HANDLE)
                return true;
        }

        // Fallback: create own handle
        m_adxHandle = iADX(symbol, timeframe, adxPeriod);
        if(m_adxHandle == INVALID_HANDLE)
        {
            Print("[ADX-MODIFIER] Failed to create ADX handle for ", symbol);
            return false;
        }

        return true;
    }

    void SetThresholds(double noTrend, double weak, double normal, double strong)
    {
        m_noTrendThreshold = noTrend;
        m_weakThreshold = weak;
        m_normalThreshold = normal;
        m_strongThreshold = strong;
    }

    void SetMultipliers(double weak, double normal, double strong, double veryStrong)
    {
        m_weakMultiplier = weak;
        m_normalMultiplier = normal;
        m_strongMultiplier = strong;
        m_veryStrongMultiplier = veryStrong;
    }

    virtual double AdjustLotSize(double baseLot, string symbol, double confidence) override
    {
        // If symbol changed, need re-initialization
        if(symbol != m_symbol)
            return baseLot;

        double adx = GetADX();
        if(adx <= 0.0)
            return baseLot; // No data — pass through unchanged

        double multiplier = 0.0;

        if(adx < m_noTrendThreshold)
            multiplier = 0.0;         // No trade
        else if(adx < m_weakThreshold)
            multiplier = m_weakMultiplier;
        else if(adx < m_normalThreshold)
            multiplier = m_normalMultiplier;
        else if(adx < m_strongThreshold)
            multiplier = m_strongMultiplier;
        else
            multiplier = m_veryStrongMultiplier;

        double adjusted = baseLot * multiplier;

        PrintFormat("[ADX-MODIFIER] %s | ADX=%.1f | tier_mult=%.2f | lot %.2f->%.2f",
                    symbol, adx, multiplier, baseLot, adjusted);

        return adjusted;
    }

    virtual string GetName() override { return "ADX"; }
};

//+------------------------------------------------------------------+
//| Kelly Lot Modifier                                                |
//| Wraps the half-Kelly logic from CICTPositionSizer.               |
//| Calculates Kelly fraction from trade history, caps at 0.5        |
//| (half-Kelly). Returns a multiplier that scales the base lot.     |
//+------------------------------------------------------------------+
class CKellyLotModifier : public CPositionSizerModifier
{
private:
    string m_symbol;
    int    m_lookbackTrades;    // Number of recent trades to consider
    double m_maxKellyCap;       // Maximum fraction of base lot to risk (0.5 = half-Kelly)
    int    m_minTradesRequired; // Minimum trades before Kelly kicks in

    bool LoadClosedTradeStats(const string symbol,
                              const int lookbackTrades,
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

        if(symbol == "" || lookbackTrades <= 0)
            return false;

        if(!HistorySelect(0, TimeCurrent()))
            return false;

        double grossWin = 0.0;
        double grossLoss = 0.0;
        int totalDeals = HistoryDealsTotal();

        for(int i = totalDeals - 1; i >= 0 && sampleCount < lookbackTrades; i--)
        {
            ulong dealTicket = HistoryDealGetTicket(i);
            if(dealTicket == 0) continue;

            if(HistoryDealGetString(dealTicket, DEAL_SYMBOL) != symbol)
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

public:
    CKellyLotModifier() :
        m_symbol(""),
        m_lookbackTrades(50),
        m_maxKellyCap(0.5),
        m_minTradesRequired(12)
    {}

    bool Initialize(const string symbol, const int lookbackTrades = 50)
    {
        m_symbol = symbol;
        m_lookbackTrades = lookbackTrades;
        return true;
    }

    void SetMaxKellyCap(double cap) { m_maxKellyCap = MathMax(0.1, MathMin(1.0, cap)); }
    void SetMinTradesRequired(int minTrades) { m_minTradesRequired = MathMax(5, minTrades); }

    virtual double AdjustLotSize(double baseLot, string symbol, double confidence) override
    {
        int sampleCount = 0;
        int wins = 0;
        int losses = 0;
        double avgWin = 0.0;
        double avgLoss = 0.0;

        if(!LoadClosedTradeStats(symbol, m_lookbackTrades, sampleCount, wins, losses, avgWin, avgLoss))
            return baseLot; // No data — pass through unchanged

        if(sampleCount < m_minTradesRequired || wins <= 0 || losses <= 0 || avgWin <= 0.0 || avgLoss <= 0.0)
            return baseLot; // Insufficient data — pass through unchanged

        double winRate = (double)wins / (double)sampleCount;
        double payoffRatio = avgWin / avgLoss;
        if(payoffRatio <= 0.0)
            return baseLot;

        double kellyFraction = winRate - ((1.0 - winRate) / payoffRatio);
        if(kellyFraction <= 0.0)
        {
            PrintFormat("[KELLY-MODIFIER] %s | Negative Kelly=%.4f | lot unchanged %.2f", symbol, kellyFraction, baseLot);
            return baseLot; // Negative Kelly — don't adjust
        }

        // Half-Kelly: cap at m_maxKellyCap (default 0.5)
        double halfKelly = MathMin(kellyFraction * m_maxKellyCap, m_maxKellyCap);
        double adjusted = baseLot * halfKelly;

        PrintFormat("[KELLY-MODIFIER] %s | WR=%.2f PF=%.2f Kelly=%.4f Half=%.4f | lot %.2f->%.2f",
                    symbol, winRate * 100.0, payoffRatio, kellyFraction, halfKelly, baseLot, adjusted);

        return adjusted;
    }

    virtual string GetName() override { return "Kelly"; }
};

#endif // CORE_RISK_POSITION_SIZER_MODIFIERS_MQH
