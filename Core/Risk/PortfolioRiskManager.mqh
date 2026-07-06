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
#include "CorrelationEngine.mqh"

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

    // Unified correlation engine (Phase 2.2)
    CCorrelationEngine m_correlationEngine;
    
    // Track per-symbol exposure
    struct SymbolExposure
    {
        string symbol;
        double riskPercent;
        double correlationGroup;
    };

    // Incremental position risk cache (avoids full position scan on every validation)
    struct SCachedPortfolioRisk
    {
        double   totalRiskPct;           // Total portfolio risk %
        double   perSymbolRisk[];        // Per-symbol risk % (dynamic array)
        string   perSymbolName[];        // Symbol names corresponding to perSymbolRisk
        datetime lastFullRefresh;        // Last time full refresh was done
        int      positionCount;          // Number of positions at last refresh
        bool     isValid;                // Whether cache is valid
    };

    SCachedPortfolioRisk m_riskCache;
    int                  m_cacheRefreshIntervalSec;  // Full refresh interval (default 60)

    // CVaR (Conditional Value at Risk) tracking
    double m_tradeReturns[];     // Rolling trade returns (P&L as % of equity)
    int    m_maxReturnHistory;   // Max history size (default 100)
    int    m_returnCount;        // Current count
    double m_cvarConfidence;     // CVaR confidence level (0.95 = 95%)
    double m_cvarMaxRisk;        // Max portfolio risk as CVaR fraction (0.10 = 10%)

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
    void   SetMaxPortfolioRisk(double maxRiskPercent) { m_maxPortfolioRisk = maxRiskPercent; }
    bool   HasUnprotectedPositions() const { return m_missingStopDetected; }
    int    GetUnprotectedPositionCount() const { return m_missingStopCount; }
    string GetLastBlockReason() const { return m_lastBlockReason; }

    // Correlation engine access (Phase 2.2)
    CCorrelationEngine* GetCorrelationEngine() { return &m_correlationEngine; }

    // Incremental risk cache — public interface
    void OnPositionOpened(string symbol, double riskPct);
    void OnPositionClosed(string symbol, double riskPct);
    void InvalidateRiskCache();
    void SetCacheRefreshInterval(int seconds) { m_cacheRefreshIntervalSec = (seconds > 0 ? seconds : 60); }

    // CVaR (Conditional Value at Risk) — public interface
    void   RecordTradeReturn(double pnlPercent);
    double CalculateCVaR(double confidence = 0.95) const;
    bool   IsCVaRLimitExceeded(double proposedRiskPct) const;
    double GetCurrentCVaR() const;

private:
    double GetPositionRisk(ulong ticket);
    void   UpdateCurrentRisk();
    double GetRiskDenominator() const;
    double CalculatePotentialTradeRisk(string symbol, double lotSize, double stopLossPoints = 0.0);
    double CalculateSymbolCorrelation(const string symbol1, const string symbol2);
    int    GetPositionsOnSymbol(const string symbol);
    void   RecordBlockReason(const string reason);

    // Incremental risk cache — private methods
    void   AddPositionToCache(string symbol, double riskPct);
    void   RemovePositionFromCache(string symbol, double riskPct);
    int    FindSymbolInCache(string symbol);
    void   RefreshRiskCache();

    // Asset-class-aware correlation
    bool   IsSameAssetClass(string symbol1, string symbol2);
    double GetEffectiveCorrelationThreshold(string symbol1, string symbol2);
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
    m_lastPrintedBlockTime(0),
    m_cacheRefreshIntervalSec(60),
    m_maxReturnHistory(100),
    m_returnCount(0),
    m_cvarConfidence(0.95),
    m_cvarMaxRisk(0.10)
{
    m_riskCache.totalRiskPct = 0.0;
    m_riskCache.lastFullRefresh = 0;
    m_riskCache.positionCount = 0;
    m_riskCache.isValid = false;
    ArrayResize(m_riskCache.perSymbolRisk, 0);
    ArrayResize(m_riskCache.perSymbolName, 0);
    ArrayResize(m_tradeReturns, m_maxReturnHistory);
    ArrayInitialize(m_tradeReturns, 0.0);
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

    // Reset risk cache
    m_riskCache.totalRiskPct = 0.0;
    m_riskCache.lastFullRefresh = 0;
    m_riskCache.positionCount = 0;
    m_riskCache.isValid = false;
    ArrayResize(m_riskCache.perSymbolRisk, 0);
    ArrayResize(m_riskCache.perSymbolName, 0);

    // Initialize unified correlation engine (Phase 2.2)
    m_correlationEngine.Initialize(30, 300);

    PrintFormat("[PortfolioRisk] Initialized. Max Risk: %.1f%%, Max Correlation: %.2f", 
                m_maxPortfolioRisk, m_maxCorrelation);
    
    return true;
}

//+------------------------------------------------------------------+
//| Get Current Portfolio Risk (%)                                   |
//+------------------------------------------------------------------+
double CPortfolioRiskManager::GetPortfolioRisk()
{
    // Check if cache needs refresh
    if(!m_riskCache.isValid ||
       (int)(TimeCurrent() - m_riskCache.lastFullRefresh) > m_cacheRefreshIntervalSec ||
       PositionsTotal() != m_riskCache.positionCount)
    {
        RefreshRiskCache();
    }

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
    
    // Use cached risk (RefreshRiskCache handles staleness)
    double currentRisk = GetPortfolioRisk();
    
    // If we are already above limit, block everything
    if(currentRisk >= m_maxPortfolioRisk)
    {
        RecordBlockReason(StringFormat("Risk %.2f%% >= Max %.2f%%",
                                       currentRisk,
                                       m_maxPortfolioRisk));
        return false;
    }
    
    // Check estimated impact
    double estimatedNewRisk = CalculatePotentialTradeRisk(symbol, lotSize, stopLossPoints);
    if(currentRisk + estimatedNewRisk > m_maxPortfolioRisk)
    {
        RecordBlockReason(StringFormat("New Total %.2f%% > Max %.2f%%",
                                       currentRisk + estimatedNewRisk,
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
    
    if(positionsOnSymbol >= 5) // Legacy safety ceiling; EA-owned stacking cap is enforced before this gate.
    {
        RecordBlockReason(StringFormat("Legacy max positions limit (5) reached for %s", symbol));
        return false;
    }

    if(m_maxCorrelation > 0.0)
    {
        double maxAbsCorrelation = 0.0;
        string mostCorrelatedSymbol = "";
        double effectiveThreshold = m_maxCorrelation; // Default; refined per-pair below

        for(int i = 0; i < PositionsTotal(); i++)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket <= 0 || !PositionSelectByTicket(ticket))
                continue;

            string existingSymbol = PositionGetString(POSITION_SYMBOL);
            if(existingSymbol == symbol)
                continue;

            double correlation = MathAbs(CalculateSymbolCorrelation(symbol, existingSymbol));

            // Asset-class-aware threshold: same-class pairs get a higher limit
            double pairThreshold = GetEffectiveCorrelationThreshold(symbol, existingSymbol);

            if(correlation > maxAbsCorrelation)
            {
                maxAbsCorrelation = correlation;
                mostCorrelatedSymbol = existingSymbol;
                effectiveThreshold = pairThreshold;
            }
        }

        // Log when asset-class-aware threshold is applied (same-class pair)
        if(effectiveThreshold != m_maxCorrelation)
        {
            PrintFormat("[CORR-ASSET-CLASS] %s vs %s — same asset class, effective threshold %.2f (default %.2f)",
                        symbol, mostCorrelatedSymbol, effectiveThreshold, m_maxCorrelation);
        }

        if(maxAbsCorrelation > effectiveThreshold)
        {
            RecordBlockReason(StringFormat("Correlation %.2f > Max %.2f (%s vs %s)",
                                           maxAbsCorrelation,
                                           effectiveThreshold,
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
    // Delegate to unified correlation engine (Phase 2.2)
    return m_correlationEngine.GetCorrelation(symbol1, symbol2);
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

//+------------------------------------------------------------------+
//| Find symbol index in risk cache                                  |
//+------------------------------------------------------------------+
int CPortfolioRiskManager::FindSymbolInCache(string symbol)
{
    for(int i = 0; i < ArraySize(m_riskCache.perSymbolName); i++)
    {
        if(m_riskCache.perSymbolName[i] == symbol)
            return i;
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Add position risk to cache incrementally                         |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::AddPositionToCache(string symbol, double riskPct)
{
    // Add risk to total
    m_riskCache.totalRiskPct += riskPct;

    // Add to per-symbol tracking
    int idx = FindSymbolInCache(symbol);
    if(idx >= 0)
        m_riskCache.perSymbolRisk[idx] += riskPct;
    else
    {
        // New symbol entry
        int size = ArraySize(m_riskCache.perSymbolRisk);
        ArrayResize(m_riskCache.perSymbolRisk, size + 1);
        ArrayResize(m_riskCache.perSymbolName, size + 1);
        m_riskCache.perSymbolRisk[size] = riskPct;
        m_riskCache.perSymbolName[size] = symbol;
    }
    m_riskCache.positionCount++;
}

//+------------------------------------------------------------------+
//| Remove position risk from cache incrementally                    |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::RemovePositionFromCache(string symbol, double riskPct)
{
    m_riskCache.totalRiskPct -= riskPct;
    m_riskCache.totalRiskPct = MathMax(0.0, m_riskCache.totalRiskPct);

    int idx = FindSymbolInCache(symbol);
    if(idx >= 0)
    {
        m_riskCache.perSymbolRisk[idx] -= riskPct;
        m_riskCache.perSymbolRisk[idx] = MathMax(0.0, m_riskCache.perSymbolRisk[idx]);
    }
    m_riskCache.positionCount--;
}

//+------------------------------------------------------------------+
//| Full refresh of risk cache from all open positions               |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::RefreshRiskCache()
{
    // Delegate to the existing full-scan logic
    UpdateCurrentRisk();

    // Rebuild per-symbol cache from scratch
    ArrayResize(m_riskCache.perSymbolRisk, 0);
    ArrayResize(m_riskCache.perSymbolName, 0);
    m_riskCache.totalRiskPct = 0.0;
    m_riskCache.positionCount = 0;

    double riskDenominator = GetRiskDenominator();
    if(riskDenominator <= 0.0)
    {
        m_riskCache.lastFullRefresh = TimeCurrent();
        m_riskCache.isValid = true;
        return;
    }

    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(!PositionSelectByTicket(ticket)) continue;

        string symbol = PositionGetString(POSITION_SYMBOL);
        double riskDollar = GetPositionRisk(ticket);

        if(riskDollar > 0.0)
        {
            double riskPct = (riskDollar / riskDenominator) * 100.0;

            int idx = FindSymbolInCache(symbol);
            if(idx >= 0)
                m_riskCache.perSymbolRisk[idx] += riskPct;
            else
            {
                int size = ArraySize(m_riskCache.perSymbolRisk);
                ArrayResize(m_riskCache.perSymbolRisk, size + 1);
                ArrayResize(m_riskCache.perSymbolName, size + 1);
                m_riskCache.perSymbolRisk[size] = riskPct;
                m_riskCache.perSymbolName[size] = symbol;
            }
            m_riskCache.totalRiskPct += riskPct;
            m_riskCache.positionCount++;
        }
    }

    m_riskCache.lastFullRefresh = TimeCurrent();
    m_riskCache.isValid = true;
}

//+------------------------------------------------------------------+
//| Public: notify cache that a position was opened                  |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::OnPositionOpened(string symbol, double riskPct)
{
    AddPositionToCache(symbol, riskPct);
    // Sync m_currentTotalRisk with cache
    m_currentTotalRisk = m_riskCache.totalRiskPct;
}

//+------------------------------------------------------------------+
//| Public: notify cache that a position was closed                  |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::OnPositionClosed(string symbol, double riskPct)
{
    RemovePositionFromCache(symbol, riskPct);
    // Sync m_currentTotalRisk with cache
    m_currentTotalRisk = m_riskCache.totalRiskPct;
}

//+------------------------------------------------------------------+
//| Public: force cache invalidation                                 |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::InvalidateRiskCache()
{
    m_riskCache.isValid = false;
}

//+------------------------------------------------------------------+
//| Determine if two symbols belong to the same asset class          |
//+------------------------------------------------------------------+
bool CPortfolioRiskManager::IsSameAssetClass(string symbol1, string symbol2)
{
    // Asset class heuristics based on symbol name patterns
    string syntheticKeywords[] = {"Index", "Volatility", "Boom", "Crash", "Jump", "Step"};
    string forexCcyKeywords[]  = {"USD", "EUR", "GBP", "JPY", "AUD", "NZD", "CAD", "CHF"};
    string metalsKeywords[]    = {"XAU", "XAG"};

    // --- Classify symbol1 ---
    bool sym1IsSynthetic = false;
    for(int i = 0; i < ArraySize(syntheticKeywords); i++)
    {
        if(StringFind(symbol1, syntheticKeywords[i]) >= 0)
        {
            sym1IsSynthetic = true;
            break;
        }
    }

    bool sym1IsMetal = false;
    for(int i = 0; i < ArraySize(metalsKeywords); i++)
    {
        if(StringFind(symbol1, metalsKeywords[i]) >= 0)
        {
            sym1IsMetal = true;
            break;
        }
    }

    bool sym1IsForex = false;
    if(!sym1IsSynthetic && !sym1IsMetal)
    {
        for(int i = 0; i < ArraySize(forexCcyKeywords); i++)
        {
            if(StringFind(symbol1, forexCcyKeywords[i]) >= 0)
            {
                sym1IsForex = true;
                break;
            }
        }
    }

    // --- Classify symbol2 ---
    bool sym2IsSynthetic = false;
    for(int i = 0; i < ArraySize(syntheticKeywords); i++)
    {
        if(StringFind(symbol2, syntheticKeywords[i]) >= 0)
        {
            sym2IsSynthetic = true;
            break;
        }
    }

    bool sym2IsMetal = false;
    for(int i = 0; i < ArraySize(metalsKeywords); i++)
    {
        if(StringFind(symbol2, metalsKeywords[i]) >= 0)
        {
            sym2IsMetal = true;
            break;
        }
    }

    bool sym2IsForex = false;
    if(!sym2IsSynthetic && !sym2IsMetal)
    {
        for(int i = 0; i < ArraySize(forexCcyKeywords); i++)
        {
            if(StringFind(symbol2, forexCcyKeywords[i]) >= 0)
            {
                sym2IsForex = true;
                break;
            }
        }
    }

    // Same class if both belong to the same category
    return (sym1IsForex && sym2IsForex) ||
           (sym1IsSynthetic && sym2IsSynthetic) ||
           (sym1IsMetal && sym2IsMetal);
}

//+------------------------------------------------------------------+
//| Get effective correlation threshold based on asset class         |
//+------------------------------------------------------------------+
double CPortfolioRiskManager::GetEffectiveCorrelationThreshold(string symbol1, string symbol2)
{
    if(IsSameAssetClass(symbol1, symbol2))
        return 0.85;

    return m_maxCorrelation;
}

//+------------------------------------------------------------------+
//| Record a closed trade P&L as percentage of equity                |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::RecordTradeReturn(double pnlPercent)
{
    // Circular buffer: overwrite oldest entry when full
    if(m_returnCount < m_maxReturnHistory)
    {
        m_tradeReturns[m_returnCount] = pnlPercent;
        m_returnCount++;
    }
    else
    {
        // Shift left and append at end (oldest discarded)
        for(int i = 0; i < m_maxReturnHistory - 1; i++)
            m_tradeReturns[i] = m_tradeReturns[i + 1];
        m_tradeReturns[m_maxReturnHistory - 1] = pnlPercent;
    }

    PrintFormat("[CVAR-RECORD] Trade return recorded: %.4f (total samples: %d)", pnlPercent, m_returnCount);
}

//+------------------------------------------------------------------+
//| Calculate CVaR (Conditional Value at Risk) at given confidence   |
//+------------------------------------------------------------------+
double CPortfolioRiskManager::CalculateCVaR(double confidence) const
{
    if(m_returnCount < 2)
        return 0.0;

    // Copy returns to a local array for sorting (const method cannot modify members)
    double sortedReturns[];
    ArrayResize(sortedReturns, m_returnCount);
    for(int i = 0; i < m_returnCount; i++)
        sortedReturns[i] = m_tradeReturns[i];

    // Sort ascending — worst returns first
    ArraySort(sortedReturns);

    // Tail index: (1 - confidence) percentile
    int tailIndex = (int)(m_returnCount * (1.0 - confidence));
    if(tailIndex < 1)
        tailIndex = 1;

    // CVaR = average of the worst tail returns
    double tailSum = 0.0;
    for(int i = 0; i < tailIndex; i++)
        tailSum += sortedReturns[i];

    double cvar = tailSum / tailIndex;

    return cvar; // Negative value = expected loss
}

//+------------------------------------------------------------------+
//| Check if new position would exceed CVaR limit                    |
//+------------------------------------------------------------------+
bool CPortfolioRiskManager::IsCVaRLimitExceeded(double proposedRiskPct) const
{
    // Not enough data to make a reliable CVaR estimate — don't block
    if(m_returnCount < 20)
        return false;

    double cvar = CalculateCVaR(m_cvarConfidence);
    double absCvar = MathAbs(cvar);

    if(absCvar + proposedRiskPct > m_cvarMaxRisk)
    {
        PrintFormat("[CVAR-CHECK] CVaR=%.2f%% + proposed=%.2f%% vs limit=%.2f%% → BLOCKED",
                    absCvar * 100.0, proposedRiskPct * 100.0, m_cvarMaxRisk * 100.0);
        return true;
    }

    PrintFormat("[CVAR-CHECK] CVaR=%.2f%% + proposed=%.2f%% vs limit=%.2f%% → ALLOWED",
                absCvar * 100.0, proposedRiskPct * 100.0, m_cvarMaxRisk * 100.0);
    return false;
}

//+------------------------------------------------------------------+
//| Get current CVaR value at stored confidence level                |
//+------------------------------------------------------------------+
double CPortfolioRiskManager::GetCurrentCVaR() const
{
    return CalculateCVaR(m_cvarConfidence);
}

#endif // CORE_RISK_PORTFOLIO_MANAGER_MQH

