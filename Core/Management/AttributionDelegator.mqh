// Thin forwarders to CTradeAttributionManager, extracted from
// CEnterpriseStrategyManager. Holds the attribution manager pointer
// and replays the exact same NULL-check / fallback behaviour so the
// output of every method is byte-for-byte identical to the original.
#ifndef ATTRIBUTION_DELEGATOR_MQH
#define ATTRIBUTION_DELEGATOR_MQH

#include "../../Core/Trading/TradeAttributionManager.mqh"

class CAttributionDelegator
{
private:
    CTradeAttributionManager* m_attribution;

public:
    CAttributionDelegator() : m_attribution(NULL) {}
    void SetAttribution(CTradeAttributionManager* attribution) { m_attribution = attribution; }

    int    FindAttributionIndexByPositionId(const ulong positionId) const;
    string JoinContributors(const string &contributors[]) const;
    void   SplitContributors(const string csv, string &contributors[]) const;
    void   UpsertPositionAttribution(const ulong positionId, const string &contributors[]);
    bool   PopPositionAttribution(const ulong positionId, string &contributors[]);
    bool   PopClosedTradeAttribution(string &contributors[], double &netProfit);
};

int CAttributionDelegator::FindAttributionIndexByPositionId(const ulong positionId) const
{
    if(m_attribution == NULL)
        return -1;
    return m_attribution.FindAttributionIndexByPositionId(positionId);
}

string CAttributionDelegator::JoinContributors(const string &contributors[]) const
{
    if(m_attribution != NULL)
    {
        return m_attribution.JoinContributors(contributors);
    }
    // Fallback implementation
    string csv = "";
    for(int i = 0; i < ArraySize(contributors); i++)
    {
        if(contributors[i] == "")
            continue;
        if(StringLen(csv) > 0)
            csv += ";";
        csv += contributors[i];
    }
    return csv;
}

void CAttributionDelegator::SplitContributors(const string csv, string &contributors[]) const
{
    if(m_attribution != NULL)
    {
        m_attribution.SplitContributors(csv, contributors);
    }
    else
    {
        // Fallback implementation
        ArrayResize(contributors, 0);
        if(csv == "")
            return;

        string parsed[];
        int count = StringSplit(csv, ';', parsed);
        if(count <= 0)
            return;

        ArrayResize(contributors, count);
        for(int i = 0; i < count; i++)
            contributors[i] = parsed[i];
    }
}

void CAttributionDelegator::UpsertPositionAttribution(const ulong positionId, const string &contributors[])
{
    if(m_attribution != NULL)
    {
        m_attribution.UpsertPositionAttribution(positionId, contributors);
    }
}

bool CAttributionDelegator::PopPositionAttribution(const ulong positionId, string &contributors[])
{
    if(m_attribution == NULL)
        return false;
    return m_attribution.PopPositionAttribution(positionId, contributors);
}

bool CAttributionDelegator::PopClosedTradeAttribution(string &contributors[], double &netProfit)
{
    if(m_attribution == NULL)
    {
        ArrayResize(contributors, 0);
        netProfit = 0.0;
        return false;
    }
    return m_attribution.PopClosedTradeAttribution(contributors, netProfit);
}

#endif // ATTRIBUTION_DELEGATOR_MQH
