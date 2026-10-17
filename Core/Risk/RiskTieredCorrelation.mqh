// Tiered correlation state: threshold config, correlation risk calculation, portfolio enforcement.
// OWNERSHIP: maxPositionsSameBase and eaMagicNumber are caller-supplied (they change at runtime via
// ApplyTierOverrides / SetEAMagicNumber); the portfolio manager pointer is stable and set once.
#ifndef CORE_RISK_RISK_TIERED_CORRELATION_MQH
#define CORE_RISK_RISK_TIERED_CORRELATION_MQH

#include "PortfolioRiskManager.mqh"
#include "CorrelationEngine.mqh"

// Only m_correlationThreshold governs a decision here: CRiskValidationPipeline enforces the reduce/block
// tiers from its own config copy, so holding a second unread pair of them was a second definition of one
// threshold (Batch 38's rule).
class CRiskTieredCorrelation
{
private:
    double m_correlationThreshold;        // 0-1 scale
    CPortfolioRiskManager* m_portfolioRiskManager;  // Non-owning, set from URM

public:
    CRiskTieredCorrelation() :
        m_correlationThreshold(0.7),
        m_portfolioRiskManager(NULL)
    {
    }

    ~CRiskTieredCorrelation()
    {
        // No owned resources.
    }

    //--- Pushed in by URM (constructor and Initialize()); nothing here re-reads config.
    void SetThresholds(const double threshold)
    {
        m_correlationThreshold = threshold;
    }

    //--- Set once from URM's constructor; stable because URM holds the portfolio manager by value.
    void SetPortfolioRiskManager(CPortfolioRiskManager* prm)
    {
        m_portfolioRiskManager = prm;
    }

// Entry gate. maxPositionsSameBase and eaMagicNumber are caller-supplied: they change at runtime.
    bool ValidateCorrelationLimits(const string symbol,
                                   string &message,
                                   double &correlationRisk,
                                   const int maxPositionsSameBase,
                                   const long eaMagicNumber)
    {
        int sameBaseCount = 0;
        // Base currency = leading alpha run, so synthetics (US30, BTCUSD) parse correctly.
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

        for(int i = 0; i < PositionsTotal(); i++)
        {
            if(PositionSelectByTicket(PositionGetTicket(i)))
            {
                string posSymbol = PositionGetString(POSITION_SYMBOL);
                long posMagic = PositionGetInteger(POSITION_MAGIC);
                // Magic filter: only manual (magic 0) and this EA's positions count toward the limit.
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
                // CheckCorrelationLimits records the pair and thresholds it compared; without reading it back
                // this refusal only ever said "Correlation limit exceeded".
                string correlationReason = m_portfolioRiskManager.GetLastBlockReason();
                message = (correlationReason != "") ? correlationReason : "Correlation limit exceeded";
                return false;
            }
        }

        return true;
    }

    double CalculateCorrelationRisk(const string symbolParam)
    {
        double maxCorrelation = 0.0;

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

// Alias for CalculateCorrelationRisk; keep the two in step.
    double GetMaxCorrelationWithPortfolio(const string symbolParam)
    {
        return CalculateCorrelationRisk(symbolParam);
    }

    double GetSymbolCorrelation(const string symbol1, const string symbol2)
    {
        if(m_portfolioRiskManager == NULL)
            return 1.0;

        CCorrelationEngine* engine = m_portfolioRiskManager.GetCorrelationEngine();
        if(engine != NULL)
            return engine.GetCorrelation(symbol1, symbol2);

        // Fallback: conservative return when engine unavailable
        return 1.0;
    }

// Fail-open when no portfolio manager is wired; unlike the engine fallback above, this path cannot veto.
    bool PortfolioCorrelationAllowed(const string symbolParam)
    {
        if(m_portfolioRiskManager == NULL)
            return true;

        return m_portfolioRiskManager.CheckCorrelationLimits(symbolParam);
    }
};

#endif // CORE_RISK_RISK_TIERED_CORRELATION_MQH
