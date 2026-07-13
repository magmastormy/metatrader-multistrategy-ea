//+------------------------------------------------------------------+
//| TradeValidator.mqh                                               |
//| Pre-trade validation: risk checks, spread gates, session         |
//| filters, correlation, drawdown limits                            |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "2.00"
#property strict

#ifndef CORE_TRADE_VALIDATOR_MQH
#define CORE_TRADE_VALIDATOR_MQH

#include <Trade/SymbolInfo.mqh>
#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "../Utils/SessionManager.mqh"
#include "../Risk/UnifiedRiskManager.mqh"
#include "../Risk/PortfolioRiskManager.mqh"
#include "../Risk/RiskValidationGate.mqh"
#include "../Cache/ATRCache.mqh"
#include "../Utils/Instruments.mqh"

class CTradeValidator
{
private:
    // Dependencies
    CUnifiedRiskManager* m_unifiedRiskManager;
    CPortfolioRiskManager* m_portfolioRiskManager;
    CRiskValidationGate* m_riskValidationGate;
    CATRCache* m_atrCache;
    CSessionManager* m_sessionManager;

    // Settings
    double m_maxEntrySpreadPoints;
    double m_maxEntryDriftPoints;
    double m_maxDailyDrawdownPercent;
    double m_maxPortfolioRiskPercent;
    bool m_enableSessionFilter;
    bool m_enableCorrelationCheck;
    bool m_enableVolatilityFilter;
    int m_logLevel;

    // ATR cache for spread/volatility checks
    struct SValidationCache
    {
        string symbol;
        double lastSpreadPoints;
        double lastATR;
        datetime lastUpdate;
        bool isStale;

        SValidationCache() : lastSpreadPoints(0), lastATR(0), lastUpdate(0), isStale(true) {}
    };

    SValidationCache m_validationCache[];
    int m_cacheCount;

    static const int CACHE_STALENESS_SECONDS = 300;

public:
    struct ValidationResult
    {
        bool passed;
        string rejectReason;
        ENUM_ERROR_LEVEL severity;
        double riskPercent;
        double portfolioRiskPercent;
        double correlationRisk;
        double spreadRatio;

        ValidationResult() : passed(true), rejectReason(""), severity(ERROR_LEVEL_INFO),
                            riskPercent(0), portfolioRiskPercent(0), correlationRisk(0), spreadRatio(0) {}
    };

    struct ValidatorConfig
    {
        double maxEntrySpreadPoints;
        double maxEntryDriftPoints;
        double maxDailyDrawdownPercent;
        double maxPortfolioRiskPercent;
        bool enableSessionFilter;
        bool enableCorrelationCheck;
        bool enableVolatilityFilter;
        int minATRPoints;

        ValidatorConfig() : maxEntrySpreadPoints(0), maxEntryDriftPoints(0),
                           maxDailyDrawdownPercent(5.0), maxPortfolioRiskPercent(15.0),
                           enableSessionFilter(true), enableCorrelationCheck(true),
                           enableVolatilityFilter(true), minATRPoints(5) {}
    };

    CTradeValidator() : m_unifiedRiskManager(NULL), m_portfolioRiskManager(NULL),
                       m_riskValidationGate(NULL), m_atrCache(NULL), m_sessionManager(NULL),
                       m_maxEntrySpreadPoints(0), m_maxEntryDriftPoints(0),
                       m_maxDailyDrawdownPercent(5.0), m_maxPortfolioRiskPercent(15.0),
                       m_enableSessionFilter(true), m_enableCorrelationCheck(true),
                       m_enableVolatilityFilter(true), m_logLevel(2)
    {
        m_cacheCount = 0;
    }

    ~CTradeValidator() {}

    void SetDependencies(CUnifiedRiskManager* unifiedRisk, CPortfolioRiskManager* portfolioRisk,
                         CRiskValidationGate* validationGate, CATRCache* atrCache,
                         CSessionManager* sessionManager)
    {
        m_unifiedRiskManager = unifiedRisk;
        m_portfolioRiskManager = portfolioRisk;
        m_riskValidationGate = validationGate;
        m_atrCache = atrCache;
        m_sessionManager = sessionManager;
    }

    void SetConfig(const ValidatorConfig &config)
    {
        m_maxEntrySpreadPoints = config.maxEntrySpreadPoints;
        m_maxEntryDriftPoints = config.maxEntryDriftPoints;
        m_maxDailyDrawdownPercent = config.maxDailyDrawdownPercent;
        m_maxPortfolioRiskPercent = config.maxPortfolioRiskPercent;
        m_enableSessionFilter = config.enableSessionFilter;
        m_enableCorrelationCheck = config.enableCorrelationCheck;
        m_enableVolatilityFilter = config.enableVolatilityFilter;
    }

    void SetLogLevel(int level) { m_logLevel = MathMax(0, MathMin(4, level)); }

    // Main validation entry point
    ValidationResult ValidateTrade(const string symbol, const ENUM_ORDER_TYPE orderType,
                                   const double volume, const double price,
                                   const double stopLossPips, const double takeProfitPips,
                                   const ulong magic, const string comment = "");

    // Individual validation checks
    ValidationResult CheckSpreadGate(const string symbol, const double requestedPrice);
    ValidationResult CheckDriftGate(const string symbol, const double requestedPrice, 
                                    const double signalPrice);
    ValidationResult CheckRiskLimits(const string symbol, const double volume,
                                     const double stopLossPips, const ulong magic);
    ValidationResult CheckPortfolioRisk(const string symbol, const double volume,
                                        const double stopLossPips, const ulong magic);
    ValidationResult CheckSessionFilter(const string symbol);
    ValidationResult CheckCorrelationRisk(const string symbol, const ENUM_ORDER_TYPE orderType,
                                          const double volume, const ulong magic);
    ValidationResult CheckVolatilityFilter(const string symbol);
    ValidationResult CheckDailyDrawdown();

    // ATR-based checks
    bool IsATRHealthy(const string symbol, int &atrPoints);
    double CalculateSpreadRatio(const string symbol);

    // Cache management
    void UpdateValidationCache(const string symbol);
    void ClearStaleCache();

    // Configuration accessors
    void SetMaxEntrySpreadPoints(double points) { m_maxEntrySpreadPoints = points; }
    void SetMaxEntryDriftPoints(double points) { m_maxEntryDriftPoints = points; }
    void SetMaxDailyDrawdownPercent(double percent) { m_maxDailyDrawdownPercent = percent; }
    void SetMaxPortfolioRiskPercent(double percent) { m_maxPortfolioRiskPercent = percent; }
    void EnableSessionFilter(bool enable) { m_enableSessionFilter = enable; }
    void EnableCorrelationCheck(bool enable) { m_enableCorrelationCheck = enable; }
    void EnableVolatilityFilter(bool enable) { m_enableVolatilityFilter = enable; }

private:
    double GetCurrentSpreadPoints(const string symbol);
    double GetCurrentATRPoints(const string symbol);
    bool IsValidPrice(const string symbol, const double price);
    string GetRejectReasonCode(const string baseReason);
};

#endif // CORE_TRADE_VALIDATOR_MQH