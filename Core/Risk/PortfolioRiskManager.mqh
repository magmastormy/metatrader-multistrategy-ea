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
    bool   IsTradeAllowed(string symbol, double lotSize);
    bool   CheckCorrelationLimits(string symbol);
    bool   IsEmergencyMode() const { return m_emergencyMode; }
    void   SetEmergencyMode(bool state) { m_emergencyMode = state; }

private:
    double GetPositionRisk(ulong ticket);
    void   UpdateCurrentRisk();
    double CalculatePotentialTradeRisk(string symbol, double lotSize);
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CPortfolioRiskManager::CPortfolioRiskManager() :
    m_maxPortfolioRisk(10.0),
    m_maxCorrelation(0.7),
    m_emergencyMode(false),
    m_currentTotalRisk(0.0)
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
    return m_currentTotalRisk;
}

//+------------------------------------------------------------------+
//| Check if a new trade is allowed                                  |
//+------------------------------------------------------------------+
bool CPortfolioRiskManager::IsTradeAllowed(string symbol, double lotSize)
{
    if(m_emergencyMode)
    {
        Print("[PortfolioRisk] BLOCKED: Emergency Mode Active");
        return false;
    }
    
    UpdateCurrentRisk();
    
    // If we are already above limit, block everything
    if(m_currentTotalRisk >= m_maxPortfolioRisk)
    {
        PrintFormat("[PortfolioRisk] BLOCKED: Risk %.2f%% >= Max %.2f%%", 
                   m_currentTotalRisk, m_maxPortfolioRisk);
        return false;
    }
    
    // Check estimated impact
    double estimatedNewRisk = CalculatePotentialTradeRisk(symbol, lotSize);
    if(m_currentTotalRisk + estimatedNewRisk > m_maxPortfolioRisk * 1.1) // Allow small buffer
    {
        PrintFormat("[PortfolioRisk] BLOCKED: New Total %.2f%% > Max %.2f%%", 
                   m_currentTotalRisk + estimatedNewRisk, m_maxPortfolioRisk);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Check Correlation Limits                                         |
//+------------------------------------------------------------------+
bool CPortfolioRiskManager::CheckCorrelationLimits(string symbol)
{
    // Simplified correlation check
    int positionsOnSymbol = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            if(PositionGetString(POSITION_SYMBOL) == symbol)
                positionsOnSymbol++;
        }
    }
    
    if(positionsOnSymbol >= 2) // Hard limit: Max 2 positions per symbol
    {
        Print("[PortfolioRisk] BLOCKED: Max positions limit (2) reached for ", symbol);
        return false;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Update total risk from open positions                            |
//+------------------------------------------------------------------+
void CPortfolioRiskManager::UpdateCurrentRisk()
{
    double totalRiskDollar = 0.0;
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    
    if(accountBalance <= 0) 
    {
        m_currentTotalRisk = 0.0;
        return;
    }
    
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            totalRiskDollar += GetPositionRisk(ticket);
        }
    }
    
    m_currentTotalRisk = (totalRiskDollar / accountBalance) * 100.0;
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
    
    if(sl <= 0) return 0.0; // No SL = No measurable risk (or infinite)
    
    double diff = MathAbs(openPrice - sl);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    
    if(tickSize <= 0) return 0.0;
    
    return (diff / tickSize) * tickValue * volume;
}

//+------------------------------------------------------------------+
//| Approximate new trade risk                                       |
//+------------------------------------------------------------------+
double CPortfolioRiskManager::CalculatePotentialTradeRisk(string symbol, double lotSize)
{
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    // Assume 50 pip risk for estimation if exact SL unknown at this stage
    // 50 pips * tickValue * lotSize
    return (50.0 * tickValue * lotSize) / AccountInfoDouble(ACCOUNT_BALANCE) * 100.0;
}

#endif // CORE_RISK_PORTFOLIO_MANAGER_MQH
