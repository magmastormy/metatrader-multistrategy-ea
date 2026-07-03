//+------------------------------------------------------------------+
//| SymbolContext.mqh                                                |
//| Symbol execution context for multi-strategy orchestration        |
//+------------------------------------------------------------------+
#ifndef SYMBOL_CONTEXT_MQH
#define SYMBOL_CONTEXT_MQH

#include <Object.mqh>
#include <Arrays\ArrayObj.mqh>
#include "../Utils/Enums.mqh"
#include "../Engines/MarketAnalysis.mqh"

//+------------------------------------------------------------------+
//| Symbol execution context                                         |
//+------------------------------------------------------------------+
class CSymbolContext : public CObject
{
public:
    string          symbol;
    ENUM_TIMEFRAMES timeframe;
    CArrayObj*      strategyWrappers;
    MqlTick         lastTick;
    datetime        lastTickTime;
    datetime        lastBarTime;
    datetime        lastAnomalyLog;
    int             malformedTickCount;
    bool            isTradable;
    double          point;
    int             digits;
    double          lotStep;
    double          minLot;
    double          maxLot;
    double          contractSize;
    double          lastValidBid;
    double          lastValidAsk;
    double          lastSpreadPoints;
    double          averageSpreadPoints;
    int             spreadSamples;
    bool            tradingSuspended;
    ENUM_TRADE_SIGNAL lastSignal;
    double          lastSignalConfidence;
    ENUM_MARKET_REGIME regime;
    double          regimeStrength;
    double          volatility;
    double          atr;
    double          momentumScore;
    bool            newsEventActive;
    double          riskPerTrade;
    double          symbolDailyRiskUsed;
    double          lastPrice;
    CMarketAnalysis *analysis;

    CSymbolContext(const string symbolName = "", const ENUM_TIMEFRAMES tf = PERIOD_CURRENT) :
        symbol(symbolName),
        timeframe(tf),
        strategyWrappers(new CArrayObj()),
        lastTickTime(0),
        lastBarTime(0),
        lastAnomalyLog(0),
        malformedTickCount(0),
        isTradable(true),
        point(0.0),
        digits(0),
        lotStep(0.0),
        minLot(0.0),
        maxLot(0.0),
        contractSize(0.0),
        lastValidBid(0.0),
        lastValidAsk(0.0),
        lastSpreadPoints(0.0),
        averageSpreadPoints(0.0),
        spreadSamples(0),
        tradingSuspended(false),
        lastSignal(TRADE_SIGNAL_NONE),
        lastSignalConfidence(0.0),
        regime(MARKET_REGIME_RANGING),
        regimeStrength(0.0),
        volatility(0.0),
        atr(0.0),
        momentumScore(0.0),
        newsEventActive(false),
        riskPerTrade(2.0), // Default 2% (0-100 scale, consistent with UnifiedRiskManager)
        symbolDailyRiskUsed(0.0),
        lastPrice(0.0),
        analysis(NULL)
    {
        ZeroMemory(lastTick);

        if(symbol != "")
        {
            digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
            point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
            minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
            maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
            contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        }

        analysis = new CMarketAnalysis();
        if(analysis != NULL)
        {
            if(!(*analysis).InitializeIndicators(symbol, timeframe))
                PrintFormat("[SYMBOL-CONTEXT] Warning: failed to initialize market analysis for %s", symbol);
        }
    }

    virtual ~CSymbolContext()
    {
        if(strategyWrappers != NULL)
        {
            for(int i = (*strategyWrappers).Total() - 1; i >= 0; --i)
            {
                CObject* obj = (CObject*)(*strategyWrappers).At(i);
                if(obj != NULL)
                    delete obj;
            }
            delete strategyWrappers;
            strategyWrappers = NULL;
        }

        if(analysis != NULL)
        {
            delete analysis;
            analysis = NULL;
        }
    }

    void UpdateSpreadStatistics(double spreadPoints)
    {
        lastSpreadPoints = spreadPoints;
        spreadSamples++;
        if(spreadSamples == 1)
            averageSpreadPoints = spreadPoints;
        else
            averageSpreadPoints = (averageSpreadPoints * (spreadSamples - 1) + spreadPoints) / spreadSamples;
    }
};

#endif // __SYMBOL_CONTEXT_MQH__
