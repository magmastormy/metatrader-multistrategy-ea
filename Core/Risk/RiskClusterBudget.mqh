// Per-cluster risk-cap overrides. The global default (`m_maxClusterRiskPercent`) stays in
// CUnifiedRiskManager and arrives here as GetClusterRiskCap's `defaultCapPercent` fallback.
#ifndef CORE_RISK_RISK_CLUSTER_BUDGET_MQH
#define CORE_RISK_RISK_CLUSTER_BUDGET_MQH

#include "RiskClusterCodec.mqh"

class CRiskClusterBudget
{
private:
    string m_clusterRiskCapCodes[];
    double m_clusterRiskCapValues[];

public:
    CRiskClusterBudget()
    {
        ArrayResize(m_clusterRiskCapCodes, 2);
        ArrayResize(m_clusterRiskCapValues, 2);
        m_clusterRiskCapCodes[0] = "T";
        m_clusterRiskCapValues[0] = 10.0;  // Trend cluster gets 10% cap
        m_clusterRiskCapCodes[1] = "R";
        m_clusterRiskCapValues[1] = 5.0;   // Reversion cluster stays at default 5%
    }

    ~CRiskClusterBudget()
    {
        // Dynamic arrays are released automatically; nothing to free.
    }

    //--- Register or update a cluster cap. Accepts a raw label (normalised here).
    void SetClusterRiskCap(const string clusterCode, const double capPercent)
    {
        string normalizedCode = CRiskClusterCodec::NormalizeClusterCode(clusterCode);
        for(int i = 0; i < ArraySize(m_clusterRiskCapCodes); i++)
        {
            if(m_clusterRiskCapCodes[i] == normalizedCode)
            {
                m_clusterRiskCapValues[i] = MathMax(0.1, capPercent);
                PrintFormat("[RISK-CLUSTER-CAP-PER] Updated cluster=%s cap=%.2f%%", normalizedCode, m_clusterRiskCapValues[i]);
                return;
            }
        }
        int newSize = ArraySize(m_clusterRiskCapCodes) + 1;
        ArrayResize(m_clusterRiskCapCodes, newSize);
        ArrayResize(m_clusterRiskCapValues, newSize);
        m_clusterRiskCapCodes[newSize - 1] = normalizedCode;
        m_clusterRiskCapValues[newSize - 1] = MathMax(0.1, capPercent);
        PrintFormat("[RISK-CLUSTER-CAP-PER] Added cluster=%s cap=%.2f%%", normalizedCode, m_clusterRiskCapValues[newSize - 1]);
    }

    //--- Cap lookup; falls back to `defaultCapPercent` when no override matches.
    //--- IMPORTANT: does NOT normalise — a raw label matches nothing and silently yields the global default.
    double GetClusterRiskCap(const string normalizedClusterCode, const double defaultCapPercent) const
    {
        double effectiveClusterRiskCap = defaultCapPercent;
        for(int c = 0; c < ArraySize(m_clusterRiskCapCodes); c++)
        {
            if(m_clusterRiskCapCodes[c] == normalizedClusterCode)
            {
                effectiveClusterRiskCap = m_clusterRiskCapValues[c];
                PrintFormat("[RISK-CLUSTER-CAP-PER] cluster=%s | per_cluster_cap=%.2f%% applied",
                            normalizedClusterCode, effectiveClusterRiskCap);
                break;
            }
        }
        return effectiveClusterRiskCap;
    }

    //--- Number of registered per-cluster overrides (diagnostics only).
    int GetOverrideCount() const
    {
        return ArraySize(m_clusterRiskCapCodes);
    }
};

#endif // CORE_RISK_RISK_CLUSTER_BUDGET_MQH
