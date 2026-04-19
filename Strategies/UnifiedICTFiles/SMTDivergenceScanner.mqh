//+------------------------------------------------------------------+
//| SMTDivergenceScanner.mqh                                          |
//| Cross-symbol SMT divergence confirmation for Unified ICT          |
//+------------------------------------------------------------------+
#property strict

#ifndef __UICT_SMT_DIVERGENCE_SCANNER_MQH__
#define __UICT_SMT_DIVERGENCE_SCANNER_MQH__

struct SSMTDivergence
{
    string   primarySymbol;
    string   correlatedSymbol;
    bool     isBearish;
    double   primaryHighLow;
    double   correlatedHighLow;
    datetime signalTime;
    double   divergenceStrength;

    SSMTDivergence() : primarySymbol(""), correlatedSymbol(""), isBearish(false),
                       primaryHighLow(0.0), correlatedHighLow(0.0),
                       signalTime(0), divergenceStrength(0.0) {}
};

class CSMTDivergenceScanner
{
private:
    string          m_primarySymbol;
    string          m_correlatedSymbol;
    ENUM_TIMEFRAMES m_timeframe;
    int             m_lookbackBars;

    string StripSuffix(const string symbol) const
    {
        int dotPos = StringFind(symbol, ".");
        if(dotPos < 0)
            return symbol;
        return StringSubstr(symbol, 0, dotPos);
    }

    string ExtractSuffix(const string symbol) const
    {
        int dotPos = StringFind(symbol, ".");
        if(dotPos < 0)
            return "";
        return StringSubstr(symbol, dotPos);
    }

    string BuildSymbolWithSuffix(const string baseSymbol, const string suffix) const
    {
        return baseSymbol + suffix;
    }

    string ResolveCorrelatedSymbol(const string symbol) const
    {
        string base = StripSuffix(symbol);
        string suffix = ExtractSuffix(symbol);

        if(base == "EURUSD") return BuildSymbolWithSuffix("GBPUSD", suffix);
        if(base == "GBPUSD") return BuildSymbolWithSuffix("EURUSD", suffix);
        if(base == "AUDUSD") return BuildSymbolWithSuffix("NZDUSD", suffix);
        if(base == "NZDUSD") return BuildSymbolWithSuffix("AUDUSD", suffix);
        if(base == "USDJPY") return BuildSymbolWithSuffix("EURJPY", suffix);
        if(base == "EURJPY") return BuildSymbolWithSuffix("USDJPY", suffix);
        if(base == "XAUUSD") return BuildSymbolWithSuffix("USDCHF", suffix);
        if(base == "USDCHF") return BuildSymbolWithSuffix("XAUUSD", suffix);
        return "";
    }

    bool FindRecentSwingExtremes(const string symbol,
                                 double &lastHigh,
                                 double &prevHigh,
                                 double &lastLow,
                                 double &prevLow,
                                 datetime &signalTime) const
    {
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        if(CopyRates(symbol, m_timeframe, 0, m_lookbackBars, rates) < 20)
            return false;

        lastHigh = 0.0;
        prevHigh = 0.0;
        lastLow = 0.0;
        prevLow = 0.0;
        signalTime = 0;

        int foundHighs = 0;
        int foundLows = 0;
        for(int i = 2; i < ArraySize(rates) - 2; i++)
        {
            bool isHigh = (rates[i].high > rates[i - 1].high &&
                           rates[i].high > rates[i + 1].high &&
                           rates[i].high > rates[i - 2].high &&
                           rates[i].high > rates[i + 2].high);
            bool isLow = (rates[i].low < rates[i - 1].low &&
                          rates[i].low < rates[i + 1].low &&
                          rates[i].low < rates[i - 2].low &&
                          rates[i].low < rates[i + 2].low);

            if(isHigh && foundHighs < 2)
            {
                if(foundHighs == 0)
                {
                    lastHigh = rates[i].high;
                    signalTime = rates[i].time;
                }
                else
                {
                    prevHigh = rates[i].high;
                }
                foundHighs++;
            }

            if(isLow && foundLows < 2)
            {
                if(foundLows == 0)
                {
                    lastLow = rates[i].low;
                    if(signalTime == 0)
                        signalTime = rates[i].time;
                }
                else
                {
                    prevLow = rates[i].low;
                }
                foundLows++;
            }

            if(foundHighs >= 2 && foundLows >= 2)
                break;
        }

        return (foundHighs >= 2 && foundLows >= 2);
    }

public:
    CSMTDivergenceScanner() : m_primarySymbol(""),
                              m_correlatedSymbol(""),
                              m_timeframe(PERIOD_CURRENT),
                              m_lookbackBars(80) {}

    bool Initialize(const string primarySymbol,
                    const ENUM_TIMEFRAMES timeframe,
                    const int lookbackBars = 80)
    {
        m_primarySymbol = primarySymbol;
        m_timeframe = timeframe;
        m_lookbackBars = MathMax(30, lookbackBars);
        m_correlatedSymbol = ResolveCorrelatedSymbol(primarySymbol);

        if(m_correlatedSymbol == "")
            return false;

        SymbolSelect(m_primarySymbol, true);
        SymbolSelect(m_correlatedSymbol, true);
        return true;
    }

    bool Scan(SSMTDivergence &divergence) const
    {
        divergence = SSMTDivergence();
        if(m_primarySymbol == "" || m_correlatedSymbol == "")
            return false;
        if(iBars(m_primarySymbol, m_timeframe) < 30 || iBars(m_correlatedSymbol, m_timeframe) < 30)
            return false;

        double pHigh1, pHigh2, pLow1, pLow2;
        double cHigh1, cHigh2, cLow1, cLow2;
        datetime signalTimePrimary = 0;
        datetime signalTimeCorr = 0;

        if(!FindRecentSwingExtremes(m_primarySymbol, pHigh1, pHigh2, pLow1, pLow2, signalTimePrimary))
            return false;
        if(!FindRecentSwingExtremes(m_correlatedSymbol, cHigh1, cHigh2, cLow1, cLow2, signalTimeCorr))
            return false;

        double tol = 0.0001;
        bool bearish = (pHigh1 > pHigh2 * (1.0 + tol) && cHigh1 <= cHigh2 * (1.0 + tol));
        bool bullish = (pLow1 < pLow2 * (1.0 - tol) && cLow1 >= cLow2 * (1.0 - tol));
        if(!bearish && !bullish)
            return false;

        divergence.primarySymbol = m_primarySymbol;
        divergence.correlatedSymbol = m_correlatedSymbol;
        divergence.isBearish = bearish;
        divergence.primaryHighLow = bearish ? pHigh1 : pLow1;
        divergence.correlatedHighLow = bearish ? cHigh1 : cLow1;
        divergence.signalTime = MathMax(signalTimePrimary, signalTimeCorr);

        double primaryMove = bearish ? MathAbs(pHigh1 - pHigh2) : MathAbs(pLow2 - pLow1);
        double corrFailure = bearish ? MathAbs(cHigh2 - cHigh1) : MathAbs(cLow1 - cLow2);
        double denom = MathMax(MathAbs(divergence.primaryHighLow), 1e-6);
        divergence.divergenceStrength = MathMin(1.0, (primaryMove + corrFailure) / denom * 50.0);
        return true;
    }
};

#endif // __UICT_SMT_DIVERGENCE_SCANNER_MQH__
