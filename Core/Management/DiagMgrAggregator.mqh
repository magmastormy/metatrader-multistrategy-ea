//+------------------------------------------------------------------+
//| DiagMgrAggregator.mqh                                             |
//| Extracted from DiagnosticsManager.mqh (God-Object decomposition)  |
//| Stateless aggregation of consensus / role-cluster diagnostics     |
//| across the registered CEnterpriseStrategyManager instances, plus  |
//| dominant-cause resolution.                                        |
//|                                                                   |
//| All methods are static: they carry no state, they only fold the   |
//| per-manager snapshots into totals exactly as the original inline  |
//| private helpers did (same accumulation order, same zero-init).    |
//+------------------------------------------------------------------+
#ifndef DIAG_MGR_AGGREGATOR_MQH
#define DIAG_MGR_AGGREGATOR_MQH

#include "EnterpriseStrategyManager.mqh"

//+------------------------------------------------------------------+
//| CDiagMgrAggregator — stateless manager-fan-in helpers             |
//+------------------------------------------------------------------+
class CDiagMgrAggregator
{
public:
    //+------------------------------------------------------------------+
    //| Collect aggregated consensus diagnostics from all managers        |
    //+------------------------------------------------------------------+
    static void GetAggregatedConsensusDiagnostics(CEnterpriseStrategyManager* &managers[],
                                                  const int managerCount,
                                                  ulong &rawNone,
                                                  ulong &filteredOut,
                                                  ulong &quorumFailed,
                                                  ulong &intrabarNotEligible,
                                                  ulong &signalsGenerated,
                                                  ulong &signalsAfterPipeline,
                                                  ulong &signalsAfterQuorum,
                                                  ulong &momentumNone,
                                                  ulong &momentumCooldown,
                                                  ulong &momentumLowVolatility,
                                                  ulong &momentumNoCrossover,
                                                  ulong &momentumTrendMisaligned,
                                                  ulong &momentumNotReady,
                                                  ulong &uictNone,
                                                  ulong &uictNeutralBias,
                                                  ulong &uictOtherFilters,
                                                  ulong &reasonTotal)
    {
        rawNone = 0;
        filteredOut = 0;
        quorumFailed = 0;
        intrabarNotEligible = 0;
        signalsGenerated = 0;
        signalsAfterPipeline = 0;
        signalsAfterQuorum = 0;
        momentumNone = 0;
        momentumCooldown = 0;
        momentumLowVolatility = 0;
        momentumNoCrossover = 0;
        momentumTrendMisaligned = 0;
        momentumNotReady = 0;
        uictNone = 0;
        uictNeutralBias = 0;
        uictOtherFilters = 0;
        reasonTotal = 0;

        for(int i = 0; i < managerCount; i++)
        {
            CEnterpriseStrategyManager* manager = managers[i];
            if(manager == NULL)
                continue;

            ulong managerRawNone = 0;
            ulong managerFilteredOut = 0;
            ulong managerQuorumFailed = 0;
            ulong managerIntrabarNotEligible = 0;
            ulong managerSignalsGenerated = 0;
            ulong managerSignalsAfterPipeline = 0;
            ulong managerSignalsAfterQuorum = 0;
            ulong managerMomentumNone = 0;
            ulong managerMomentumCooldown = 0;
            ulong managerMomentumLowVolatility = 0;
            ulong managerMomentumNoCrossover = 0;
            ulong managerMomentumTrendMisaligned = 0;
            ulong managerMomentumNotReady = 0;
            ulong managerUICTNone = 0;
            ulong managerUICTNeutralBias = 0;
            ulong managerUICTOtherFilters = 0;
            ulong managerReasonTotal = 0;
            manager.GetConsensusDiagnosticsSnapshot(managerRawNone,
                                                   managerFilteredOut,
                                                   managerQuorumFailed,
                                                   managerIntrabarNotEligible,
                                                   managerSignalsGenerated,
                                                   managerSignalsAfterPipeline,
                                                   managerSignalsAfterQuorum,
                                                   managerMomentumNone,
                                                   managerMomentumCooldown,
                                                   managerMomentumLowVolatility,
                                                   managerMomentumNoCrossover,
                                                   managerMomentumTrendMisaligned,
                                                   managerMomentumNotReady,
                                                   managerUICTNone,
                                                   managerUICTNeutralBias,
                                                   managerUICTOtherFilters,
                                                   managerReasonTotal);

            rawNone += managerRawNone;
            filteredOut += managerFilteredOut;
            quorumFailed += managerQuorumFailed;
            intrabarNotEligible += managerIntrabarNotEligible;
            signalsGenerated += managerSignalsGenerated;
            signalsAfterPipeline += managerSignalsAfterPipeline;
            signalsAfterQuorum += managerSignalsAfterQuorum;
            momentumNone += managerMomentumNone;
            momentumCooldown += managerMomentumCooldown;
            momentumLowVolatility += managerMomentumLowVolatility;
            momentumNoCrossover += managerMomentumNoCrossover;
            momentumTrendMisaligned += managerMomentumTrendMisaligned;
            momentumNotReady += managerMomentumNotReady;
            uictNone += managerUICTNone;
            uictNeutralBias += managerUICTNeutralBias;
            uictOtherFilters += managerUICTOtherFilters;
            reasonTotal += managerReasonTotal;
        }
    }

    //+------------------------------------------------------------------+
    //| Collect aggregated role/cluster diagnostics from all managers     |
    //+------------------------------------------------------------------+
    static void GetAggregatedRoleClusterDiagnostics(CEnterpriseStrategyManager* &managers[],
                                                    const int managerCount,
                                                    ulong &primarySignals,
                                                    ulong &featureSignals,
                                                    ulong &voteSuppressed,
                                                    ulong &trendClusterSignals,
                                                    ulong &meanReversionClusterSignals,
                                                    ulong &structureClusterSignals,
                                                    ulong &noneClusterSignals)
    {
        primarySignals = 0;
        featureSignals = 0;
        voteSuppressed = 0;
        trendClusterSignals = 0;
        meanReversionClusterSignals = 0;
        structureClusterSignals = 0;
        noneClusterSignals = 0;

        for(int i = 0; i < managerCount; i++)
        {
            CEnterpriseStrategyManager* manager = managers[i];
            if(manager == NULL)
                continue;

            ulong managerPrimary = 0;
            ulong managerFeature = 0;
            ulong managerSuppressed = 0;
            ulong managerTrend = 0;
            ulong managerMeanRev = 0;
            ulong managerStructure = 0;
            ulong managerNone = 0;

            manager.GetRoleClusterDiagnosticsTotals(managerPrimary,
                                                    managerFeature,
                                                    managerSuppressed,
                                                    managerTrend,
                                                    managerMeanRev,
                                                    managerStructure,
                                                    managerNone);

            primarySignals += managerPrimary;
            featureSignals += managerFeature;
            voteSuppressed += managerSuppressed;
            trendClusterSignals += managerTrend;
            meanReversionClusterSignals += managerMeanRev;
            structureClusterSignals += managerStructure;
            noneClusterSignals += managerNone;
        }
    }

    //+------------------------------------------------------------------+
    //| Determine which consensus cause is dominant                       |
    //+------------------------------------------------------------------+
    static string GetDominantConsensusCause(const ulong rawNone,
                                            const ulong filteredOut,
                                            const ulong quorumFailed,
                                            const ulong intrabarNotEligible)
    {
        string dominant = "none";
        ulong maxCount = 0;

        if(intrabarNotEligible > maxCount)
        {
            maxCount = intrabarNotEligible;
            dominant = "intrabar_not_eligible";
        }
        if(quorumFailed > maxCount)
        {
            maxCount = quorumFailed;
            dominant = "quorum_failed";
        }
        if(filteredOut > maxCount)
        {
            maxCount = filteredOut;
            dominant = "filtered_out";
        }
        if(rawNone > maxCount)
        {
            maxCount = rawNone;
            dominant = "raw_none";
        }

        return dominant;
    }
};

#endif // DIAG_MGR_AGGREGATOR_MQH
