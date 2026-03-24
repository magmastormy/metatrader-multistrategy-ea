//+------------------------------------------------------------------+
//| PortfolioRiskManager.mqh                                         |
//| Manages total portfolio risk and correlation exposure            |
//| Rebuilt to fix corruption and standardize risk units (0-100%)    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property strict

#ifndef CORE_RISK_PORTFOLIO_MANAGER_MQH
#define CORE_RISK_PORTFOLIO_MANAGER_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "../../IndicatorManager.mqh"

//+------------------------------------------------------------------+
//| Portfolio Risk Manager Class                                     |
//+------------------------------------------------------------------+
class CPortfolioRiskManager
{
private:
    double m_maxPortfolioRisk;      // Max total risk % (e.g. 10.0)
    double m_maxCorrelation;        // Max correlation coefficient (e.g. 0.7)
    bool   m_emergencyMode;         // Emergency circuit breaker
    double m_currentTotalRisk;      // Cached total risk %
    bool   m_missingStopDetected;   // True when any open position has no protective SL
    int    m_missingStopCount;      // Number of open positions without SL
    string m_lastBlockReason;       // Last deterministic veto reason
    string m_lastPrintedBlockReason;
    datetime m_lastPrintedBlockTime;
    
    // Track per-symbol exposure
    struct SymbolExposure
    {
        string symbol;
        double riskPercent;
        double correlationGroup;
    };
    
public:
    CPortfolioRiskManager();
    ~CPortfolioRiskManager();
    
    // Initialization
    bool Initialize(double maxRiskPercent = 10.0, double maxCorrelation = 0.7);
    
    // Core Risk Methods
    double GetPortfolioRisk();
    bool   IsTradeAllowed(string symbol, double lotSize, double stopLossPoints = 0.0);
    bool   CheckCorrelationLimits(string symbol);
    bool   IsEmergencyMode() const { return m_emergencyMode; }
    void   SetEmergencyMode(bool state) { m_emergencyMode = state; }
    bool   HasUnprotectedPositions() const { return m_missingStopDetected; }
    int    GetUnprotectedPositionCount() const { return m_missingStopCount; }
    string GetLastBlockReason() const { return m_lastBlockReason; }

private:
    double GetPositionRisk(ulong ticket);
    void   UpdateCurrentRisk();
    double GetRiskDenominator() const;
    double CalculatePotentialTradeRisk(string symbol, double lotSize, double stopLossPoints = 0.0);
    double CalculateSymbolCorrelation(const string symbol1, const string symbol2);
    int    GetPositionsOnSymbol(const string symbol);
    void   RecordBlockReason(const string reason);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CPortfolioRiskManager::CPortfolioRiskManager() :
    m_maxPortfolioRisk(10.0),
    m_maxCorrelation(0.7),
    m_emergencyMode(false),
    m_currentTotalRisk(0.0),
    m_missingStopDetected(false),
    m_missingStopCount(0),
    m_lastBlockReason(""),
    m_lastPrintedBlockReason(""),
    m_lastPrintedBlockTime(0)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CPortfolioRiskManager::~CPortfolioRiskManager()
{
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CPortfolioRiskManager::Initialize(double maxRiskPercent, double maxCorrelation)
{
    if(maxRiskPercent <= 0 || maxRiskPercent > 100)
    {
        Print("[PortfolioRisk] Invalid max risk percent: ", maxRiskPercent);
        return false;
    }
    
    m_maxPortfolioRisk = maxRiskPercent;
    m_maxCorrelation = maxCorrelation;
    m_emergencyMode = false;
    m_missingStopDetected = false;
    m_missingStopCount = 0;
    m_lastBlockReason = "";
    m_lastPrintedBlockReason = "";
    m_lastPrintedBlockTime = 0;
    
    PrintFormat("[PortfolioRisk] Initialized. Max Risk: %.1f%%, Max Correlation: %.2f", 
                m_maxPortfolioRisk, m_maxCorrelation);
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Current Portfolio Risk (%)                                   |
//+------------------------------------------------------------------+
double CPortfolioRiskManager::GetPortfolioRisk()
{
    UpdateCurrentRisk();

    if(m_missingStopDetected)
    {
        static datetime s_lastMissingStopLog = 0;
        datetime nowTime = TimeCurrent();
        if(s_lastMissingStopLog == 0 || (nowTime - s_lastMissingStopLog) >= 60)
        {
            PrintFormat("[PortfolioRisk] BLOCKED: %d open position(s) missing stop-loss protection",
                        m_missingStopCount);
            s_lastMissingStopLog = nowTime;
        }
        // Preserve elevated risk state instead of collapsing to 0.0
        return m_currentTotalRisk;
    }
    return m_currentTotalRisk;
}

//+------------------------------------------------------------------+
//| Check if a new trade is allowed                                  |
//+------------------------------------------------------------------+
bool CPortfolioRiskManager::IsTradeAllowed(string symbol, double lotSize, double stopLossPoints)
{
    m_lastBlockReason = "";
    if(symbol == "" || lotSize <= 0.0)
    {
        RecordBlockReason("Invalid trade request parameters");
        return false;
    }

    if(m_emergencyMode)
    {
        RecordBlockReason("Emergency Mode Active");
        return false;
    }
    
    UpdateCurrentRisk();
    
    // If we are already above limit, block everything
    if(m_currentTotalRisk >= m_maxPortfolioRisk)
    {
        RecordBlockReason(StringFormat("Risk %.2f%% >= Max %.2f%%",
                                       m_currentTotalRisk,
                                       m_maxPortfolioRisk));
        return false;
    }
    
    // Check estimated impact
    double estimatedNewRisk = CalculatePotentialTradeRisk(symbol, lotSize, stopLossPoints);
    if(m_currentTotalRisk + estimatedNewRisk > m_maxPortfolioRisk)
    {
        RecordBlockReason(StringFormat("New Total %.2f%% > Max %.2f%%",
                                       m_currentTotalRisk + estimatedNewRisk,
                                       m_maxPortfolioRisk));
        return false;
    }

    if(!CheckCorrelationLimits(symbol))
        return false;
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Correlation Limits                                         |
//+------------------------------------------------------------------+
bool CPortfolioRiskManager::CheckCorrelationLimits(string symbol)
{
    m_lastBlockReason = "";
    int positionsOnSymbol = GetPositionsOnSymbol(symbol);
    
    if(positionsOnSymbol >= 2) // Hard limit: Max 2 positions per symbol
    {
        RecordBlockReason(StringFormat("Max positions limit (2) reached for %s", symbol));
        return false;
    }

    if(m_maxCorrelation > 0.0)
    {
        double maxAbsCorrelation = 0.0;
        string mostCorrelatedSymbol = "";

        for(int i = 0; i < PositionsTotal(); i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0 || !PositionSelectByTicket(ticket))
                continue;

            string existingSymbol = PositionGetString(POSITION_SYMBOL);
            if(existingSymbol == symbol)
                continue;

            double correlation = MathAbs(CalculateSymbolCorrelation(symbol, existingSymbol));
            if(correlation > maxAbsCorrelation)
            {
                maxAbsCorrelation = correlation;
                mostCorrelatedSymbol = existingSymbol;
            }
        }

        if(maxAbsCorrelation > m_maxCorrelation)
        {
            RecordBlockReason(StringFormat("Correlation %.2f > Max %.2f (%s vs %s)",
                                           maxAbsCorrelation,
                                           m_maxCorrelation,
                                           symbol,
                                           mostCorrelatedSymbol));
            return false;
        }
    }
    
    return true;
}

void CPortfolioRiskManager::RecordBlockReason(const string reason)
{
    m_lastBlockReason = reason;

    datetime nowTime = TimeCurrent();
    if(reason == m_lastPrintedBlockReason &&
       m_lastPrintedBlockTime > 0 &&
       (nowTime - m_lastPrintedBlockTime) < 15)
    {
        return;
    }

    Print("[PortfolioRisk] BLOCKED: ", reason);
    m_lastPrintedBlockReason = reason;
    m_lastPrintedBlockTime = nowTime;
}

//+------------------------------------------------------------------+
//| Update total risk from open positions                            |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::UpdateCurrentRisk()
{
    double totalRiskDollar = 0.0;
    double riskDenominator = GetRiskDenominator();
    m_missingStopDetected = false;
    m_missingStopCount = 0;
    
    if(riskDenominator <= 0.0)
    {
        m_currentTotalRisk = 0.0;
        return;
    }
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            double positionRisk = GetPositionRisk(ticket);
            if(positionRisk < 0.0)
            {
                m_missingStopDetected = true;
                m_missingStopCount++;
                continue;
            }
            totalRiskDollar += positionRisk;
        }
    }
    
    m_currentTotalRisk = (totalRiskDollar / riskDenominator) * 100.0;
    if(m_missingStopDetected)
    {
        // Missing SL is treated as an immediate risk-governance breach.
        m_currentTotalRisk = MathMax(m_currentTotalRisk, m_maxPortfolioRisk + 0.01);
    }
}

//+------------------------------------------------------------------+
//| Equity-aware denominator for stress-state risk normalization      |
//+------------------------------------------------------------------+
double CPortfolioRiskManager::GetRiskDenominator() const
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);

    if(balance > 0.0 && equity > 0.0)
        return MathMin(balance, equity);

    return MathMax(balance, equity);
}

//+------------------------------------------------------------------+
//| Calculate risk for a single position ($)                         |
//+------------------------------------------------------------------+
double CPortfolioRiskManager::GetPositionRisk(ulong ticket)
{
    if(!PositionSelectByTicket(ticket)) return 0.0;
    
    double sl = PositionGetDouble(POSITION_SL);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double volume = PositionGetDouble(POSITION_VOLUME);
    string symbol = PositionGetString(POSITION_SYMBOL);
    
    if(sl <= 0)
        return -1.0; // Missing SL is an unbounded-risk state and must hard-veto new entries.
    
    double diff = MathAbs(openPrice - sl);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    
    if(tickSize <= 0) return 0.0;
    
    return (diff / tickSize) * tickValue * volume;
}

//+------------------------------------------------------------------+
//| Approximate new trade risk                                       |
//+------------------------------------------------------------------+
double CPortfolioRiskManager::CalculatePotentialTradeRisk(string symbol, double lotSize, double stopLossPoints)
{
    if(lotSize <= 0.0 || symbol == "")
        return 0.0;

    double riskDenominator = GetRiskDenominator();
    if(riskDenominator <= 0.0)
        return 0.0;

    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    if(point <= 0.0 || tickValue <= 0.0 || tickSize <= 0.0)
        return 0.0;

    double effectiveStopPoints = stopLossPoints;

    // If caller did not provide stop distance, estimate from ATR to stay symbol-aware.
    if(effectiveStopPoints <= 0.0)
    {
        CIndicatorManager* indManager = CIndicatorManager::Instance();
        if(indManager != NULL)
        {
            int atrHandle = indManager.GetATRHandle(symbol, PERIOD_CURRENT, 14);
            if(atrHandle != INVALID_HANDLE)
            {
                double atrBuffer[1];
                if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0 && atrBuffer[0] > 0.0)
                    effectiveStopPoints = (atrBuffer[0] / point) * 1.5;
            }
        }
        else
        {
            // Fallback path when shared indicator manager is unavailable.
            int atrHandle = iATR(symbol, PERIOD_CURRENT, 14);
            if(atrHandle != INVALID_HANDLE)
            {
                double atrBuffer[1];
                if(CopyBuffer(atrHandle, 0, 0, 1, atrBuffer) > 0 && atrBuffer[0] > 0.0)
                    effectiveStopPoints = (atrBuffer[0] / point) * 1.5;
                IndicatorRelease(atrHandle);
            }
        }
    }

    if(effectiveStopPoints <= 0.0)
    {
        int stopLevelPoints = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
        effectiveStopPoints = MathMax(100.0, (double)stopLevelPoints * 2.0);
    }

    double stopLossPriceDistance = effectiveStopPoints * point;
    double riskPerLot = (stopLossPriceDistance / tickSize) * tickValue;
    double totalRisk = riskPerLot * lotSize;
    return (totalRisk / riskDenominator) * 100.0;
}

double CPortfolioRiskManager::CalculateSymbolCorrelation(const string symbol1, const string symbol2)
{
    const double conservativeCorrelation = 1.0;
    static datetime s_lastCorrelationDataWarn = 0;

    if(symbol1 == "" || symbol2 == "")
        return conservativeCorrelation;
    if(symbol1 == symbol2)
        return conservativeCorrelation;

    if(!SymbolSelect(symbol1, true) || !SymbolSelect(symbol2, true))
        return conservativeCorrelation;

    const int period = 30;
    double prices1[];
    double prices2[];

    if(CopyClose(symbol1, PERIOD_H1, 0, period, prices1) < period ||
       CopyClose(symbol2, PERIOD_H1, 0, period, prices2) < period)
    {
        datetime now = TimeCurrent();
        if(s_lastCorrelationDataWarn == 0 || (now - s_lastCorrelationDataWarn) >= 300)
        {
            PrintFormat("[PortfolioRisk] Correlation data unavailable for %s/%s - applying conservative block",
                        symbol1, symbol2);
            s_lastCorrelationDataWarn = now;
        }
        return conservativeCorrelation;
    }

    double returns1[];
    double returns2[];
    ArrayResize(returns1, period - 1);
    ArrayResize(returns2, period - 1);

    for(int i = 1; i < period; i++)
    {
        if(prices1[i - 1] == 0.0 || prices2[i - 1] == 0.0)
            return conservativeCorrelation;
        returns1[i - 1] = (prices1[i] - prices1[i - 1]) / prices1[i - 1];
        returns2[i - 1] = (prices2[i] - prices2[i - 1]) / prices2[i - 1];
    }

    double sum1 = 0.0, sum2 = 0.0, sum12 = 0.0, sum1sq = 0.0, sum2sq = 0.0;
    int n = period - 1;
    for(int i = 0; i < n; i++)
    {
        sum1 += returns1[i];
        sum2 += returns2[i];
        sum12 += returns1[i] * returns2[i];
        sum1sq += returns1[i] * returns1[i];
        sum2sq += returns2[i] * returns2[i];
    }

    double numerator = n * sum12 - sum1 * sum2;
    double denominator = MathSqrt((n * sum1sq - sum1 * sum1) * (n * sum2sq - sum2 * sum2));
    if(denominator <= 0.0)
        return conservativeCorrelation;

    return numerator / denominator;
}

int CPortfolioRiskManager::GetPositionsOnSymbol(const string symbol)
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket > 0 && PositionSelectByTicket(ticket) &&
           PositionGetString(POSITION_SYMBOL) == symbol)
        {
            count++;
        }
    }
    return count;
}

#endif // CORE_RISK_PORTFOLIO_MANAGER_MQH
