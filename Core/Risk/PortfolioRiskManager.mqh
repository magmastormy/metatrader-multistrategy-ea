// Total open portfolio risk, correlation and CVaR gates. Risk figures are percent on a 0-100 scale, EXCEPT the CVaR
// block, which works in decimal fractions (0.05 = 5%).
#property copyright "Copyright 2024, Windsurf AI"
#property strict

#ifndef CORE_RISK_PORTFOLIO_MANAGER_MQH
#define CORE_RISK_PORTFOLIO_MANAGER_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "../../IndicatorManager.mqh"
#include "CorrelationEngine.mqh"
#include "../Utils/RiskMath.mqh"

class CPortfolioRiskManager
{
private:
    double m_maxPortfolioRisk;      // Total open-risk cap, % of the equity-aware risk denominator
    double m_maxCorrelation;        // Max correlation coefficient (e.g. 0.7)
    bool   m_emergencyMode;         // Hard veto on every entry
    double m_currentTotalRisk;      // Cached total risk %
    bool   m_missingStopDetected;   // True when any open position has no protective SL
    int    m_missingStopCount;      // Number of open positions without SL
    string m_lastBlockReason;       // Last deterministic veto reason
    string m_lastPrintedBlockReason;
    datetime m_lastPrintedBlockTime;

    // Value member: constructed and destroyed with this manager, never a pointer
    CCorrelationEngine m_correlationEngine;
    
    struct SymbolExposure
    {
        string symbol;
        double riskPercent;
        double correlationGroup;
    };

    // Risk cache: reads are rebuilt by a full PositionsTotal() scan, because the incremental hooks have no caller
    struct SCachedPortfolioRisk
    {
        double   totalRiskPct;           // Total portfolio risk %
        double   perSymbolRisk[];        // Per-symbol risk % (dynamic array)
        string   perSymbolName[];        // Symbol names index-aligned with perSymbolRisk
        datetime lastFullRefresh;
        int      positionCount;          // Risk-bearing positions at last refresh (SL-protected only)
        int      rawPositionCount;       // PositionsTotal() snapshot: the staleness probe has to compare like with
                                          // like, positionCount excludes positions without computable risk and would
                                          // force a full rescan on every call while any SL-less position exists
        bool     isValid;                // Whether cache is valid
                int      version;                // Version counter for race condition prevention (L5-006)
    };

    SCachedPortfolioRisk m_riskCache;
    int                  m_cacheRefreshIntervalSec;  // Full-refresh interval in seconds

    double m_tradeReturns[];     // Rolling trade returns (P&L as % of equity)
    int    m_maxReturnHistory;   // Default 100
    int    m_returnCount;
    double m_cvarConfidence;     // Tail confidence (0.95 = 95%)
    double m_cvarMaxRisk;        // Max portfolio risk as CVaR fraction (0.10 = 10%)

    // CVaR samples come from the equity-curve window; the trade-return window has no writer anywhere, so it stays empty
    double m_equityCurveReturns[]; // Rolling equity curve returns
    int    m_maxEquityCurveHistory;  // Window size, 500 samples
    int    m_equityCurveReturnCount;
    double m_lastEquity;
    datetime m_lastEquitySampleTime; // UpdateEquityCurve sampling throttle
    bool   m_useEquityCurveForCVaR;

    double m_assetClassCorrThreshold; // Same asset class (default 0.85)
    double m_crossAssetCorrThreshold; // Different asset classes (default 0.7)

public:
    CPortfolioRiskManager();
    ~CPortfolioRiskManager();
    
    bool Initialize(double maxRiskPercent = 10.0, double maxCorrelation = 0.7);
    
    double GetPortfolioRisk();
    bool   IsTradeAllowed(string symbol, double lotSize, double stopLossPoints = 0.0);
    bool   CheckCorrelationLimits(string symbol);
    bool   IsEmergencyMode() const { return m_emergencyMode; }
    void   SetEmergencyMode(bool state) { m_emergencyMode = state; }
    void   SetMaxPortfolioRisk(double maxRiskPercent) { m_maxPortfolioRisk = maxRiskPercent; }
    bool   HasUnprotectedPositions() const { return m_missingStopDetected; }
    int    GetUnprotectedPositionCount() const { return m_missingStopCount; }
    string GetLastBlockReason() const { return m_lastBlockReason; }

    // One shared engine instance; also handed to CPositionSizer and CRiskTieredCorrelation so all correlation reads agree
    CCorrelationEngine* GetCorrelationEngine() { return &m_correlationEngine; }

    double CalculateCVaR(double confidence = 0.95) const;
    bool   IsCVaRLimitExceeded(double proposedRiskPct) const;
    double GetCurrentCVaR() const;
    
        void   RecordEquityCurveReturn(double equityPercentChange);
        void   UpdateEquityCurve();
        void   SetUseEquityCurveForCVaR(bool use) { m_useEquityCurveForCVaR = use; }
    
    void   SetAssetClassCorrThreshold(double threshold) { m_assetClassCorrThreshold = MathMax(0.0, MathMin(1.0, threshold)); }
    void   SetCrossAssetCorrThreshold(double threshold) { m_crossAssetCorrThreshold = MathMax(0.0, MathMin(1.0, threshold)); }

private:
    double GetPositionRisk(ulong ticket);
    void   UpdateCurrentRisk();
    double GetRiskDenominator() const;
    double CalculatePotentialTradeRisk(string symbol, double lotSize, double stopLossPoints = 0.0);
    double CalculateSymbolCorrelation(const string symbol1, const string symbol2);
    int    GetPositionsOnSymbol(const string symbol);
    void   RecordBlockReason(const string reason);

    int    FindSymbolInCache(string symbol);
    void   RefreshRiskCache();

    bool   IsSameAssetClass(string symbol1, string symbol2);
    double GetEffectiveCorrelationThreshold(string symbol1, string symbol2);

    };

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
    m_cvarMaxRisk(0.10),
    m_maxEquityCurveHistory(500),
    m_equityCurveReturnCount(0),
    m_lastEquity(0.0),
    m_lastEquitySampleTime(0),
    m_useEquityCurveForCVaR(true),
    m_assetClassCorrThreshold(0.85),
    m_crossAssetCorrThreshold(0.7)
{
    m_riskCache.totalRiskPct = 0.0;
    m_riskCache.lastFullRefresh = 0;
    m_riskCache.positionCount = 0;
    m_riskCache.rawPositionCount = 0;
    m_riskCache.isValid = false;
    ArrayResize(m_riskCache.perSymbolRisk, 0);
    ArrayResize(m_riskCache.perSymbolName, 0);
    ArrayResize(m_tradeReturns, m_maxReturnHistory);
    ArrayInitialize(m_tradeReturns, 0.0);
    
    ArrayResize(m_equityCurveReturns, m_maxEquityCurveHistory);
    ArrayInitialize(m_equityCurveReturns, 0.0);
}

CPortfolioRiskManager::~CPortfolioRiskManager()
{
    // Owns no raw pointers: every member is a value member or a dynamic array
}

bool CPortfolioRiskManager::Initialize(double maxRiskPercent, double maxCorrelation)
{
    if(maxRiskPercent <= 0 || maxRiskPercent > 500)
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

    m_riskCache.totalRiskPct = 0.0;
    m_riskCache.lastFullRefresh = 0;
    m_riskCache.positionCount = 0;
    m_riskCache.rawPositionCount = 0;
    m_riskCache.isValid = false;
    ArrayResize(m_riskCache.perSymbolRisk, 0);
    ArrayResize(m_riskCache.perSymbolName, 0);

    // One-time seed of the engine with both thresholds; SetAssetClassCorrThreshold/SetCrossAssetCorrThreshold have no
    // caller, so the ctor defaults (0.85 same-class / 0.70 cross-class) are what the engine keeps using
    m_correlationEngine.Initialize(30, 300, 0.0, m_assetClassCorrThreshold, m_crossAssetCorrThreshold);

    PrintFormat("[PortfolioRisk] Initialized. Max Risk: %.1f%%, Max Correlation: %.2f | AssetClass=%.2f CrossAsset=%.2f", 
                m_maxPortfolioRisk, m_maxCorrelation, m_assetClassCorrThreshold, m_crossAssetCorrThreshold);
    
    return true;
}

// Total open risk as 0-100 % of CRiskMath::GetRiskDenominator(); rescans when the cache is stale
double CPortfolioRiskManager::GetPortfolioRisk()
{
        if(!m_riskCache.isValid ||
           (int)(TimeCurrent() - m_riskCache.lastFullRefresh) > m_cacheRefreshIntervalSec ||
           PositionsTotal() != m_riskCache.rawPositionCount)
    {
        // versionBefore is never read back and the version counter has no reader at all (MQL5 is single-threaded)
        int versionBefore = m_riskCache.version;
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
        // Both return paths hand back the same m_currentTotalRisk; the SL-less elevation happens in UpdateCurrentRisk
        return m_currentTotalRisk;
    }
    return m_currentTotalRisk;
}

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
    
    double currentRisk = GetPortfolioRisk();
    
    // Fail-closed at the cap (>=, not >): a book already at max blocks every entry before correlation is even looked at
    if(currentRisk >= m_maxPortfolioRisk)
    {
        RecordBlockReason(StringFormat("Risk %.2f%% >= Max %.2f%%",
                                       currentRisk,
                                       m_maxPortfolioRisk));
        return false;
    }
    
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

bool CPortfolioRiskManager::CheckCorrelationLimits(string symbol)
{
    m_lastBlockReason = "";
    int positionsOnSymbol = GetPositionsOnSymbol(symbol);
    
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
        // An SL-less book forces risk to cap + 0.01 so new entries stay refused until it is protected (fail-closed)
        m_currentTotalRisk = MathMax(m_currentTotalRisk, m_maxPortfolioRisk + 0.01);
    }
}

// Denominator is CRiskMath::GetRiskDenominator() = min(balance, equity), the same base CPositionSizer sizes against
double CPortfolioRiskManager::GetRiskDenominator() const
{
    return CRiskMath::GetRiskDenominator();
}

// Dollar risk of one position: stop distance in ticks x tick value x volume
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

// Risk % a proposed trade adds on the same denominator; stopLossPoints is in SYMBOL_POINT units, not price
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

    // No stop distance from the caller: 1.5 x ATR(14) in points; if ATR is unavailable, MathMax(100, SYMBOL_TRADE_STOPS_LEVEL * 2)
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
            // Shared manager absent: this handle is self-created and released below - a shared handle must never be released
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

int CPortfolioRiskManager::FindSymbolInCache(string symbol)
{
    for(int i = 0; i < ArraySize(m_riskCache.perSymbolName); i++)
    {
        if(m_riskCache.perSymbolName[i] == symbol)
            return i;
    }
    return -1;
}

void CPortfolioRiskManager::RefreshRiskCache()
{
    m_riskCache.version++;
    
    UpdateCurrentRisk();

    ArrayResize(m_riskCache.perSymbolRisk, 0);
    ArrayResize(m_riskCache.perSymbolName, 0);
    m_riskCache.totalRiskPct = 0.0;
    m_riskCache.positionCount = 0;

    double riskDenominator = GetRiskDenominator();
    if(riskDenominator <= 0.0)
    {
        m_riskCache.lastFullRefresh = TimeCurrent();
        m_riskCache.isValid = true;
        m_riskCache.version++; // Increment again to mark completion
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
    m_riskCache.rawPositionCount = PositionsTotal();
        m_riskCache.isValid = true;
        m_riskCache.version++; // Increment again to mark completion
    }

bool CPortfolioRiskManager::IsSameAssetClass(string symbol1, string symbol2)
{
    // Asset class from symbol-name substrings; a symbol matching no keyword is unclassified, so the pair uses the cross-asset threshold
    string syntheticKeywords[] = {"Index", "Volatility", "Boom", "Crash", "Jump", "Step"};
    string forexCcyKeywords[]  = {"USD", "EUR", "GBP", "JPY", "AUD", "NZD", "CAD", "CHF"};
    string metalsKeywords[]    = {"XAU", "XAG"};

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

    return (sym1IsForex && sym2IsForex) ||
           (sym1IsSynthetic && sym2IsSynthetic) ||
           (sym1IsMetal && sym2IsMetal);
}

double CPortfolioRiskManager::GetEffectiveCorrelationThreshold(string symbol1, string symbol2)
{
    if(IsSameAssetClass(symbol1, symbol2))
        return m_assetClassCorrThreshold;

    return m_crossAssetCorrThreshold;
}

// Only caller is UpdateEquityCurve below; equity moves cover the whole book, per-trade returns do not
void CPortfolioRiskManager::RecordEquityCurveReturn(double equityPercentChange)
{
    // Ring of m_maxEquityCurveHistory (500) samples, oldest shifted out; each sample is an equity FRACTION (0.001 = 0.1%)
    if(m_equityCurveReturnCount < m_maxEquityCurveHistory)
    {
        m_equityCurveReturns[m_equityCurveReturnCount] = equityPercentChange;
        m_equityCurveReturnCount++;
    }
    else
    {
            for(int i = 0; i < m_maxEquityCurveHistory - 1; i++)
            m_equityCurveReturns[i] = m_equityCurveReturns[i + 1];
        m_equityCurveReturns[m_maxEquityCurveHistory - 1] = equityPercentChange;
    }

    PrintFormat("[CVAR-EQUITY] Equity curve return recorded: %.4f (total samples: %d)", 
                equityPercentChange, m_equityCurveReturnCount);
}

void CPortfolioRiskManager::UpdateEquityCurve()
{
    // Called from CUnifiedRiskManager::RefreshRuntimeState each risk cycle; minute-throttled here so the window holds minute returns
    datetime nowTime = TimeCurrent();
    if(m_lastEquitySampleTime > 0 && nowTime - m_lastEquitySampleTime < 60)
        return;
    m_lastEquitySampleTime = nowTime;

    double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    if(currentEquity <= 0.0)
        return;

    if(m_lastEquity > 0.0)
    {
        double equityChange = (currentEquity - m_lastEquity) / m_lastEquity;
        RecordEquityCurveReturn(equityChange);
    }
    m_lastEquity = currentEquity;
}

// CVaR at the given confidence from the equity window; 0.0 below 2 samples; a negative fraction = expected loss
double CPortfolioRiskManager::CalculateCVaR(double confidence) const
{
    // Source picked by sample count, not by m_useEquityCurveForCVaR (that flag is never read; its setter has no caller)
    bool useEquityCurve = (m_equityCurveReturnCount >= 2);
    int count = useEquityCurve ? m_equityCurveReturnCount : m_returnCount;
    if(count < 2)
        return 0.0;

    double sortedReturns[];
    ArrayResize(sortedReturns, count);
    for(int i = 0; i < count; i++)
        sortedReturns[i] = useEquityCurve ? m_equityCurveReturns[i] : m_tradeReturns[i];

    ArraySort(sortedReturns);

    int tailIndex = (int)(count * (1.0 - confidence));
    if(tailIndex < 1)
        tailIndex = 1;

    // CVaR = mean of the worst tailIndex samples (ascending sort put them first)
    double tailSum = 0.0;
    for(int i = 0; i < tailIndex; i++)
        tailSum += sortedReturns[i];

    double cvar = tailSum / tailIndex;

    return cvar; // Negative value = expected loss
}

// proposedRiskPct is a FRACTION (callers pass riskPercent/100), same scale as m_cvarMaxRisk (0.10 = 10%)
bool CPortfolioRiskManager::IsCVaRLimitExceeded(double proposedRiskPct) const
{
    // Fail-open below 20 equity-curve samples (no tail estimate yet); the guard reads the equity buffer, not m_returnCount
    if(m_equityCurveReturnCount < 20)
        return false;

    double cvar = CalculateCVaR(m_cvarConfidence);
    double absCvar = MathAbs(cvar);

    if(absCvar + proposedRiskPct > m_cvarMaxRisk)
    {
        // DENIED logs every occurrence (each one is a live veto); ALLOWED is throttled to 1/min
        PrintFormat("[CVAR-CHECK] CVaR=%.2f%% + proposed=%.2f%% vs limit=%.2f%% → DENIED",
                    absCvar * 100.0, proposedRiskPct * 100.0, m_cvarMaxRisk * 100.0);
        return true;
    }

    static datetime s_lastAllowedLog = 0;
    datetime nowTime = TimeCurrent();
    if(nowTime - s_lastAllowedLog >= 60)
    {
        PrintFormat("[CVAR-CHECK] CVaR=%.2f%% + proposed=%.2f%% vs limit=%.2f%% → ALLOWED",
                    absCvar * 100.0, proposedRiskPct * 100.0, m_cvarMaxRisk * 100.0);
        s_lastAllowedLog = nowTime;
    }
    return false;
}

double CPortfolioRiskManager::GetCurrentCVaR() const
{
    return CalculateCVaR(m_cvarConfidence);
}

#endif // CORE_RISK_PORTFOLIO_MANAGER_MQH

