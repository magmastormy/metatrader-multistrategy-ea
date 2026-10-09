// Per-cluster risk-cap registry (Fix #11).
// Extracted verbatim from CUnifiedRiskManager (Phase E2, E-D):
// inline lookup in ValidateClusterGovernance -> GetClusterRiskCap
// Behaviour is byte-identical to the original inline code;
// CUnifiedRiskManager keeps a thin forwarder with the original
// signature so that all call sites remain unchanged.
// OWNERSHIP NOTE: the *global* default cap (m_maxClusterRiskPercent
// configured through ConfigureClusterGovernance) intentionally
// stays in CUnifiedRiskManager and is handed to GetClusterRiskCap
// as the `defaultCapPercent` fallback argument.
#ifndef CORE_RISK_RISK_CLUSTER_BUDGET_MQH
#define CORE_RISK_RISK_CLUSTER_BUDGET_MQH

#include "RiskClusterCodec.mqh"

// Per-cluster risk cap registry (stateful, owned by value)
class CRiskClusterBudget
{
private:
    string m_clusterRiskCapCodes[];
    double m_clusterRiskCapValues[];

public:
    //--- Constructor performs the default-override seeding that used to
    //--- live in the CUnifiedRiskManager constructor body (identical values).
    CRiskClusterBudget()
    {
        // Per-cluster risk caps (Fix #11): default overrides
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

    //--- Register / update the risk cap for a cluster.
    //--- `clusterCode` is normalised here exactly as the original member did.
    void SetClusterRiskCap(const string clusterCode, const double capPercent)
    {
        string normalizedCode = CRiskClusterCodec::NormalizeClusterCode(clusterCode);
        // Update existing entry if found
        for(int i = 0; i < ArraySize(m_clusterRiskCapCodes); i++)
        {
            if(m_clusterRiskCapCodes[i] == normalizedCode)
            {
                m_clusterRiskCapValues[i] = MathMax(0.1, capPercent);
                PrintFormat("[RISK-CLUSTER-CAP-PER] Updated cluster=%s cap=%.2f%%", normalizedCode, m_clusterRiskCapValues[i]);
                return;
            }
        }
        // Add new entry
        int newSize = ArraySize(m_clusterRiskCapCodes) + 1;
        ArrayResize(m_clusterRiskCapCodes, newSize);
        ArrayResize(m_clusterRiskCapValues, newSize);
        m_clusterRiskCapCodes[newSize - 1] = normalizedCode;
        m_clusterRiskCapValues[newSize - 1] = MathMax(0.1, capPercent);
        PrintFormat("[RISK-CLUSTER-CAP-PER] Added cluster=%s cap=%.2f%%", normalizedCode, m_clusterRiskCapValues[newSize - 1]);
    }

    //--- Fix #11: Look up per-cluster risk cap first; fall back to global default.
    //--- IMPORTANT: `normalizedClusterCode` must already be normalised - the
    //--- original inline lookup in ValidateClusterGovernance compared against
    //--- the already-normalised request code and did NOT re-normalise. Keeping
    //--- that contract preserves byte-identical behaviour.
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
