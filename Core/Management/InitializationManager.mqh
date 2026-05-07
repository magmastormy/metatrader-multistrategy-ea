//+------------------------------------------------------------------+
//| InitializationManager.mqh                                         |
//| Centralized initialization logic for MultiStrategyAutonomousEA     |
//+------------------------------------------------------------------+
#ifndef __INITIALIZATION_MANAGER_MQH__
#define __INITIALIZATION_MANAGER_MQH__

#include "../Utils/Enums.mqh"
#include "../Trading/TradeManager.mqh"
#include "../Risk/UnifiedRiskManager.mqh"
#include "../Risk/PositionSizer.mqh"
#include "../Strategy/StrategyRegistry.mqh"
#include "../AI/AIPerformanceFeedback.mqh"
#include "../Monitoring/PerformanceAnalytics.mqh"
#include "../Visualization/VisualDashboard.mqh"

//+------------------------------------------------------------------+
//| Initialization Manager Class                                       |
//+------------------------------------------------------------------+
class CInitializationManager
{
private:
    CTradeManager* m_tradeManager;
    CUnifiedRiskManager* m_riskManager;
    CPositionSizer* m_positionSizer;
    CPerformanceAnalytics* m_performanceAnalytics;
    CAIPerformanceFeedback* m_aiFeedback;
    CVisualDashboard* m_dashboard;
    
    bool m_tradeManagerReady;
    bool m_riskManagerReady;
    bool m_positionSizerReady;
    bool m_performanceAnalyticsReady;
    bool m_aiFeedbackReady;
    bool m_dashboardReady;
    
public:
    CInitializationManager();
    ~CInitializationManager();
    
    // Component initialization
    bool InitializeTradeManager(uint magicNumber, const string eaName, int orderFillMode, int slippage, int modifyCooldown);
    bool InitializeRiskManager(SUnifiedRiskConfig& config, CPerformanceAnalytics* analytics);
    bool InitializePositionSizer(SPositionSizingParams& params);
    bool InitializePerformanceAnalytics();
    bool InitializeAIPerformanceFeedback(int historySize);
    bool InitializeDashboard();
    
    // Accessors
    CTradeManager* GetTradeManager() { return m_tradeManager; }
    CUnifiedRiskManager* GetRiskManager() { return m_riskManager; }
    CPositionSizer* GetPositionSizer() { return m_positionSizer; }
    CPerformanceAnalytics* GetPerformanceAnalytics() { return m_performanceAnalytics; }
    CAIPerformanceFeedback* GetAIPerformanceFeedback() { return m_aiFeedback; }
    CVisualDashboard* GetDashboard() { return m_dashboard; }
    
    // Status checks
    bool IsTradeManagerReady() const { return m_tradeManagerReady; }
    bool IsRiskManagerReady() const { return m_riskManagerReady; }
    bool IsPositionSizerReady() const { return m_positionSizerReady; }
    bool IsPerformanceAnalyticsReady() const { return m_performanceAnalyticsReady; }
    bool IsAIPerformanceFeedbackReady() const { return m_aiFeedbackReady; }
    bool IsDashboardReady() const { return m_dashboardReady; }
    
    // Cleanup
    void ReleaseAll();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CInitializationManager::CInitializationManager() :
    m_tradeManager(NULL),
    m_riskManager(NULL),
    m_positionSizer(NULL),
    m_performanceAnalytics(NULL),
    m_aiFeedback(NULL),
    m_dashboard(NULL),
    m_tradeManagerReady(false),
    m_riskManagerReady(false),
    m_positionSizerReady(false),
    m_performanceAnalyticsReady(false),
    m_aiFeedbackReady(false),
    m_dashboardReady(false)
{
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CInitializationManager::~CInitializationManager()
{
    ReleaseAll();
}

//+------------------------------------------------------------------+
//| Initialize Trade Manager                                         |
//+------------------------------------------------------------------+
bool CInitializationManager::InitializeTradeManager(uint magicNumber, const string eaName, 
                                                     int orderFillMode, int slippage, int modifyCooldown)
{
    if(m_tradeManager != NULL)
        return true; // Already initialized
    
    m_tradeManager = new CTradeManager();
    if(m_tradeManager == NULL)
    {
        Print("[INIT-ERROR] Failed to allocate TradeManager");
        return false;
    }
    
    m_tradeManager.SetOrderFillMode(orderFillMode);
    m_tradeManager.SetSlippage((uint)MathMax(1, slippage));
    m_tradeManager.SetProtectiveModifyCooldownSeconds(modifyCooldown);
    
    if(!m_tradeManager.Initialize(magicNumber, eaName))
    {
        Print("[INIT-ERROR] Failed to initialize TradeManager");
        delete m_tradeManager;
        m_tradeManager = NULL;
        return false;
    }
    
    m_tradeManagerReady = true;
    Print("[INIT] TradeManager initialized");
    return true;
}

//+------------------------------------------------------------------+
//| Initialize Risk Manager                                          |
//+------------------------------------------------------------------+
bool CInitializationManager::InitializeRiskManager(SUnifiedRiskConfig& config, CPerformanceAnalytics* analytics)
{
    if(m_riskManager != NULL)
        return true; // Already initialized
    
    if(analytics == NULL)
    {
        Print("[INIT-ERROR] PerformanceAnalytics required for RiskManager initialization");
        return false;
    }
    
    m_riskManager = new CUnifiedRiskManager();
    if(m_riskManager == NULL)
    {
        Print("[INIT-ERROR] Failed to allocate RiskManager");
        return false;
    }
    
    if(!m_riskManager.Initialize(config, analytics))
    {
        Print("[INIT-ERROR] Failed to initialize RiskManager");
        delete m_riskManager;
        m_riskManager = NULL;
        return false;
    }
    
    m_riskManagerReady = true;
    Print("[INIT] RiskManager initialized as single risk authority");
    return true;
}

//+------------------------------------------------------------------+
//| Initialize Position Sizer                                        |
//+------------------------------------------------------------------+
bool CInitializationManager::InitializePositionSizer(SPositionSizingParams& params)
{
    if(m_positionSizer != NULL)
        return true; // Already initialized
    
    m_positionSizer = new CPositionSizer();
    if(m_positionSizer == NULL)
    {
        Print("[INIT-ERROR] Failed to allocate PositionSizer");
        return false;
    }
    
    if(!m_positionSizer.SetParameters(params))
    {
        Print("[INIT-ERROR] Failed to set PositionSizer parameters");
        delete m_positionSizer;
        m_positionSizer = NULL;
        return false;
    }
    
    m_positionSizerReady = true;
    Print("[INIT] PositionSizer initialized - Mode: RISK_PERCENT, Risk: ", DoubleToString(params.riskPercent, 2), "%");
    return true;
}

//+------------------------------------------------------------------+
//| Initialize Performance Analytics                                  |
//+------------------------------------------------------------------+
bool CInitializationManager::InitializePerformanceAnalytics()
{
    if(m_performanceAnalytics != NULL)
        return true; // Already initialized
    
    m_performanceAnalytics = new CPerformanceAnalytics();
    if(m_performanceAnalytics == NULL)
    {
        Print("[INIT-ERROR] Failed to allocate PerformanceAnalytics");
        return false;
    }
    
    if(!m_performanceAnalytics.Initialize())
    {
        Print("[INIT-ERROR] PerformanceAnalytics failed to initialize");
        delete m_performanceAnalytics;
        m_performanceAnalytics = NULL;
        return false;
    }
    
    m_performanceAnalyticsReady = true;
    Print("[INIT] PerformanceAnalytics initialized");
    return true;
}

//+------------------------------------------------------------------+
//| Initialize AI Performance Feedback                               |
//+------------------------------------------------------------------+
bool CInitializationManager::InitializeAIPerformanceFeedback(int historySize)
{
    if(m_aiFeedback != NULL)
        return true; // Already initialized
    
    m_aiFeedback = new CAIPerformanceFeedback();
    if(m_aiFeedback == NULL)
    {
        Print("[INIT-ERROR] Failed to allocate AIPerformanceFeedback");
        return false;
    }
    
    if(!m_aiFeedback.Initialize(historySize))
    {
        Print("[INIT-WARNING] AIPerformanceFeedback failed to initialize, continuing without AI learning tracking");
        delete m_aiFeedback;
        m_aiFeedback = NULL;
        return false;
    }
    
    m_aiFeedbackReady = true;
    Print("[INIT] AIPerformanceFeedback initialized for AI model adaptation");
    return true;
}

//+------------------------------------------------------------------+
//| Initialize Dashboard                                             |
//+------------------------------------------------------------------+
bool CInitializationManager::InitializeDashboard()
{
    if(m_dashboard != NULL)
        return true; // Already initialized
    
    m_dashboard = new CVisualDashboard();
    if(m_dashboard == NULL)
    {
        Print("[INIT-ERROR] Failed to allocate Dashboard");
        return false;
    }
    
    // Dashboard initialization logic would go here
    m_dashboardReady = true;
    Print("[INIT] Dashboard initialized");
    return true;
}

//+------------------------------------------------------------------+
//| Release All Components                                           |
//+------------------------------------------------------------------+
void CInitializationManager::ReleaseAll()
{
    if(m_dashboard != NULL)
    {
        delete m_dashboard;
        m_dashboard = NULL;
        m_dashboardReady = false;
    }
    
    if(m_aiFeedback != NULL)
    {
        delete m_aiFeedback;
        m_aiFeedback = NULL;
        m_aiFeedbackReady = false;
    }
    
    if(m_performanceAnalytics != NULL)
    {
        delete m_performanceAnalytics;
        m_performanceAnalytics = NULL;
        m_performanceAnalyticsReady = false;
    }
    
    if(m_positionSizer != NULL)
    {
        delete m_positionSizer;
        m_positionSizer = NULL;
        m_positionSizerReady = false;
    }
    
    if(m_riskManager != NULL)
    {
        delete m_riskManager;
        m_riskManager = NULL;
        m_riskManagerReady = false;
    }
    
    if(m_tradeManager != NULL)
    {
        delete m_tradeManager;
        m_tradeManager = NULL;
        m_tradeManagerReady = false;
    }
}

#endif // __INITIALIZATION_MANAGER_MQH__
