// Per-cluster risk-cap allowances, expressed as multipliers of the configured global cap
// (m_maxClusterRiskPercent, which arrives here as defaultCapPercent). They used to be absolute
// percentages, so a trend entry ran at 10% no matter how low InpRiskMaxClusterExposurePct was set.
#ifndef CORE_RISK_RISK_CLUSTER_BUDGET_MQH
#define CORE_RISK_RISK_CLUSTER_BUDGET_MQH

#include "RiskClusterCodec.mqh"

class CRiskClusterBudget
{
private:
    string m_clusterRiskCapCodes[];
    double m_clusterRiskCapFactors[];

public:
    CRiskClusterBudget()
    {
        ArrayResize(m_clusterRiskCapCodes, 2);
        ArrayResize(m_clusterRiskCapFactors, 2);
        m_clusterRiskCapCodes[0] = "T";
        m_clusterRiskCapFactors[0] = 2.0;  // Trend cluster gets twice the configured cap
        m_clusterRiskCapCodes[1] = "R";
        m_clusterRiskCapFactors[1] = 1.0;  // Reversion cluster stays at the configured cap
    }

    ~CRiskClusterBudget()
    {
        // Dynamic arrays are released automatically; nothing to free.
    }

    //--- Cap lookup; falls back to `defaultCapPercent` when no allowance matches.
    //--- IMPORTANT: does NOT normalise - a raw label matches nothing and silently yields the global default.
    double GetClusterRiskCap(const string normalizedClusterCode, const double defaultCapPercent) const
    {
        double effectiveClusterRiskCap = defaultCapPercent;
        for(int c = 0; c < ArraySize(m_clusterRiskCapCodes); c++)
        {
            if(m_clusterRiskCapCodes[c] == normalizedClusterCode)
            {
                effectiveClusterRiskCap = defaultCapPercent * m_clusterRiskCapFactors[c];
                PrintFormat("[RISK-CLUSTER-CAP-PER] cluster=%s | per_cluster_cap=%.2f%% | factor=%.2fx of configured %.2f%%",
                            normalizedClusterCode, effectiveClusterRiskCap, m_clusterRiskCapFactors[c], defaultCapPercent);
                break;
            }
        }
        return effectiveClusterRiskCap;
    }
};

#endif // CORE_RISK_RISK_CLUSTER_BUDGET_MQH
