//+------------------------------------------------------------------+
//| RiskTieredCorrelation.mqh                                        |
//| Tiered correlation logic: threshold config, correlation risk     |
//| calculation, and portfolio correlation enforcement.              |
//|                                                                  |
//| Extracted verbatim from CUnifiedRiskManager (Phase E3, A):       |
//|   correlationThreshold, correlationReduceThreshold,              |
//|   correlationBlockThreshold (from SUnifiedRiskConfig)            |
//|   CUnifiedRiskManager::ValidateCorrelationLimits                 |
//|       -> ValidateCorrelationLimits                               |
//|   CUnifiedRiskManager::CalculateCorrelationRisk                  |
//|       -> CalculateCorrelationRisk                                |
//|   CUnifiedRiskManager::CalculateSymbolCorrelation                |
//|       -> CalculateSymbolCorrelation                              |
//|   CUnifiedRiskManager::GetMaxCorrelationWithPortfolio            |
//|       -> GetMaxCorrelationWithPortfolio                          |
//|   CUnifiedRiskManager::GetSymbolCorrelation                      |
//|       -> GetSymbolCorrelation                                    |
//|   CUnifiedRiskManager::PortfolioCorrelationAllowed               |
//|       -> PortfolioCorrelationAllowed                             |
//|                                                                  |
//| Behaviour is byte-identical to the original member functions;    |
//| CUnifiedRiskManager keeps thin forwarders with the original      |
//| signatures so that all call sites remain unchanged.              |
//|                                                                  |
//| OWNERSHIP NOTE: maxPositionsSameBase and eaMagicNumber change at |
//| runtime (ApplyTierOverrides / SetEAMagicNumber), so they are     |
//| passed as parameters from the forwarder rather than cached.      |
//| The CPortfolioRiskManager pointer is stable for URM's lifetime   |
//| (URM owns m_portfolioRiskManager by value) and is set once via   |
//| SetPortfolioRiskManager from URM's constructor body.             |
//+------------------------------------------------------------------+
#ifndef CORE_RISK_RISK_TIERED_CORRELATION_MQH
#define CORE_RISK_RISK_TIERED_CORRELATION_MQH

#include "PortfolioRiskManager.mqh"
#include "CorrelationEngine.mqh"

//+------------------------------------------------------------------+
//| Tiered correlation monitor (stateful config holder, owned by value)|
//+------------------------------------------------------------------+
class CRiskTieredCorrelation
{
private:
    double m_correlationThreshold;        // 0-1 scale
    double m_correlationReduceThreshold;  // 0-1 scale
    double m_correlationBlockThreshold;   // 0-1 scale
    CPortfolioRiskManager* m_portfolioRiskManager;  // Non-owning, set from URM

public:
    //--- Constructor performs the init that used to live in
    //--- CUnifiedRiskManager's constructor body (identical defaults).
    CRiskTieredCorrelation() :
        m_correlationThreshold(0.7),
        m_correlationReduceThreshold(0.4),
        m_correlationBlockThreshold(0.7),
        m_portfolioRiskManager(NULL)
    {
    }

    ~CRiskTieredCorrelation()
    {
        // No owned resources.
    }

    //--- Called from URM constructor body and Initialize() to sync
    //--- the correlation threshold config values.
    void SetThresholds(const double threshold,
                       const double reduceThreshold,
                       const double blockThreshold)
    {
        m_correlationThreshold = threshold;
        m_correlationReduceThreshold = reduceThreshold;
        m_correlationBlockThreshold = blockThreshold;
    }

    //--- Called from URM constructor body; the pointer is stable for
    //--- URM's lifetime because m_portfolioRiskManager is a value member.
    void SetPortfolioRiskManager(CPortfolioRiskManager* prm)
    {
        m_portfolioRiskManager = prm;
    }

    //+--------------------------------------------------------------+
    //| Validate correlation limits for a trade request               |
    //| maxPositionsSameBase and eaMagicNumber are passed from the    |
    //| forwarder because they change at runtime.                    |
    //+--------------------------------------------------------------+
    bool ValidateCorrelationLimits(const string symbol,
                                   string &message,
                                   double &correlationRisk,
                                   const int maxPositionsSameBase,
                                   const long eaMagicNumber)
    {
        // Check same base currency limit
        int sameBaseCount = 0;
        // Batch 118: Extract base currency up to first non-alpha character (handles US30, BTCUSD, etc.)
        string symbolBase = "";
        for(int c = 0; c < StringLen(symbol); c++)
        {
            ushort ch = StringGetCharacter(symbol, c);
            if((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z'))
                symbolBase += ShortToString(ch);
            else
                break;
        }
        if(StringLen(symbolBase) < 3)
            symbolBase = StringSubstr(symbol, 0, 3);  // fallback

        // Batch 119: Only count EA-owned positions (filter by magic number)
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionSelectByTicket(PositionGetTicket(i)))
            {
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                long posMagic = PositionGetInteger(POSITION_MAGIC);
                // Only count positions with magic 0 (manual) or matching EA magic
                if(StringFind(posSymbol, symbolBase) >= 0 &&
                   (posMagic == 0 || posMagic == eaMagicNumber))
                    sameBaseCount++;
            }
        }

        if(sameBaseCount >= maxPositionsSameBase)
        {
            message = StringFormat("Too many positions on base %s (>= %d)", symbolBase, maxPositionsSameBase);
            correlationRisk = 1.0;
            return false;
        }

        correlationRisk = CalculateCorrelationRisk(symbol);

        if(correlationRisk > m_correlationThreshold)
        {
            message = StringFormat("Correlation risk %.2f exceeds threshold %.2f", correlationRisk, m_correlationThreshold);
            return false;
        }

        if(CheckPointer(m_portfolioRiskManager) != POINTER_INVALID)
        {
            if(!PortfolioCorrelationAllowed(symbol))
            {
                string correlationReason = "";  // GetLastBlockReason would need to be added
                message = (correlationReason != "") ? correlationReason : "Correlation limit exceeded";
                return false;
            }
        }

        return true;
    }

    //+--------------------------------------------------------------+
    //| Calculate max correlation risk of a symbol vs open positions  |
    //+--------------------------------------------------------------+
    double CalculateCorrelationRisk(const string symbolParam)
    {
        double maxCorrelation = 0.0;

        // Check correlation with all open positions
        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionSelectByTicket(PositionGetTicket(i)))
            {
                string existingSymbol = PositionGetString(POSITION_SYMBOL);
                if(existingSymbol != symbolParam)
                {
                    double correlation = CalculateSymbolCorrelation(symbolParam, existingSymbol);
                    maxCorrelation = MathMax(maxCorrelation, MathAbs(correlation));
                }
            }
        }

        return maxCorrelation;
    }

    //+--------------------------------------------------------------+
    //| Calculate correlation between two symbols via the engine      |
    //+--------------------------------------------------------------+
    double CalculateSymbolCorrelation(const string symbol1, const string symbol2)
    {
        // Delegate to unified correlation engine via portfolio risk manager
        if(CheckPointer(m_portfolioRiskManager) != POINTER_INVALID)
        {
            CCorrelationEngine* engine = m_portfolioRiskManager.GetCorrelationEngine();
            if(engine != NULL)
                return engine.GetCorrelation(symbol1, symbol2);
        }

        // Fallback: conservative return when engine unavailable
        return 1.0;
    }

    //+--------------------------------------------------------------+
    //| Get max correlation with portfolio (alias for above)          |
    //+--------------------------------------------------------------+
    double GetMaxCorrelationWithPortfolio(const string symbolParam)
    {
        // This is an alias for CalculateCorrelationRisk
        return CalculateCorrelationRisk(symbolParam);
    }

    //+--------------------------------------------------------------+
    //| Get correlation between two symbols (direct engine lookup)    |
    //+--------------------------------------------------------------+
    double GetSymbolCorrelation(const string symbol1, const string symbol2)
    {
        // Delegate to unified correlation engine via portfolio risk manager
        if(m_portfolioRiskManager == NULL)
            return 1.0;

        CCorrelationEngine* engine = m_portfolioRiskManager.GetCorrelationEngine();
        if(engine != NULL)
            return engine.GetCorrelation(symbol1, symbol2);

        // Fallback: conservative return when engine unavailable
        return 1.0;
    }

    //+--------------------------------------------------------------+
    //| Check if portfolio correlation allows a new symbol            |
    //+--------------------------------------------------------------+
    bool PortfolioCorrelationAllowed(const string symbolParam)
    {
        if(m_portfolioRiskManager == NULL)
            return true;

        return m_portfolioRiskManager.CheckCorrelationLimits(symbolParam);
    }
};

#endif // CORE_RISK_RISK_TIERED_CORRELATION_MQH
