// TradeAttributionManager.mqh - Trade attribution & NN prediction
// Copyright 2025, Aggressive Trading Systems
// https://www.aggressivetrading.com
// Encapsulates trade-comment building, prediction/position mapping, AI pending-request tracking and NN diagnostics; all state is in-memory arrays that do not survive a restart.
// Closed-deal attribution feeds strategy performance (CStrategyMgrTradeFeedback: UpdatePerformance + health monitor) and NN online training, so it is not cosmetic-only.
#property copyright "Copyright 2025, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef TRADE_ATTRIBUTION_MANAGER_MQH
#define TRADE_ATTRIBUTION_MANAGER_MQH

#include <Object.mqh>
#include "../Utils/Enums.mqh"
#include "../Position/PositionManager.mqh"

class CTradeAttributionManager
{
private:
    uint    m_aiPendingRequestIds[];
    string  m_aiPendingSymbols[];
    datetime m_aiPendingPredictionTimes[];
    ENUM_TRADE_SIGNAL m_aiPendingPredictionSignals[];

    ulong   m_pendingClosePositionIds[];
    double  m_pendingCloseNetProfit[];

    int     m_nnDiagEntryMapCount;
    int     m_nnDiagCloseByIdCount;
    int     m_nnDiagCloseFallbackCount;
    int     m_nnDiagCloseMissCount;
    int     m_nnDiagPartialCloseCount;
    datetime m_nnDiagLastSummaryTime;

    bool    m_enableNNDiagnostics;
    bool    m_runSelfTest;

    // Reference to position manager (not owned)
    CPositionManager *m_positionManager;

    // m_closedTradeContributors / m_hasClosedTradeAttribution are never written by any method here, so PopClosedTradeAttribution() always returns false.
    ulong   m_attributionPositionIds[];
    string  m_attributionContributorCsv[];
    string  m_closedTradeContributors[];
    double  m_closedTradeNetProfit;
    bool    m_hasClosedTradeAttribution;

    bool    IsPositionIdStillOpen(const ulong positionId);

    bool IsAIContributorName(const string strategyName) const;

public:
    int     FindAttributionIndexByPositionId(const ulong positionId) const;
    string  JoinContributors(const string &contributors[]) const;
    void    SplitContributors(const string csv, string &contributors[]) const;

    CTradeAttributionManager() :
        m_nnDiagEntryMapCount(0),
        m_nnDiagCloseByIdCount(0),
        m_nnDiagCloseFallbackCount(0),
        m_nnDiagCloseMissCount(0),
        m_nnDiagPartialCloseCount(0),
        m_nnDiagLastSummaryTime(0),
        m_enableNNDiagnostics(true),
        m_runSelfTest(true),
        m_positionManager(NULL),
        m_closedTradeNetProfit(0.0),
        m_hasClosedTradeAttribution(false)
    {
        ArrayResize(m_attributionPositionIds, 0);
        ArrayResize(m_attributionContributorCsv, 0);
        ArrayResize(m_closedTradeContributors, 0);
    }

    ~CTradeAttributionManager()
    {
        ClearAll();
    }

    void SetPositionManager(CPositionManager &mgr) { m_positionManager = &mgr; }
    void SetNNDiagnosticsEnabled(bool enabled) { m_enableNNDiagnostics = enabled; }
    void SetRunSelfTest(bool enabled) { m_runSelfTest = enabled; }

    string ExtractPredictionIdFromComment(const string comment);
    string BuildTradeCommentWithPrediction(const string baseComment, const string predictionId);
    string NormalizeClusterCode(const string clusterCode);
    int    ClusterCodeToNumeric(const string clusterCode);
    string BuildClusterTaggedTradeComment(const string clusterCode, const string predictionId);

    bool   ContributorsIncludeAI(const string &contributors[]);
    bool   ContributorsIncludeName(const string &contributors[], const string contributorName);
    bool   ContributorsIncludeONNX(const string &contributors[]);
    bool   ContributorsIncludeTransformer(const string &contributors[]);
    bool   ContributorsIncludeEnsemble(const string &contributors[]);
    bool   ContributorsIncludeNeuralNetwork(const string &contributors[]);
    int    CountIndicatorContributors(const string &contributors[]);

    void   UpsertPositionAttribution(const ulong positionId, const string &contributors[]);
    bool   PopPositionAttribution(const ulong positionId, string &contributors[]);
    bool   PopClosedTradeAttribution(string &contributors[], double &netProfit);
    int    GetActiveAttributionCount() const;
    void   ClearClosedTradeAttribution();
    double GetClosedTradeNetProfit() const { return m_closedTradeNetProfit; }
    bool   HasClosedTradeAttribution() const { return m_hasClosedTradeAttribution; }

    //--- Prediction position mapping: thin wrappers over m_positionManager (CPositionManager); no state lives in this class.
    int    FindPredictionPositionIndex(const ulong positionId);
    void   UpsertPredictionPositionMap(const ulong positionId, const string predictionId);
    string GetPredictionIdForPosition(const ulong positionId);
    void   RemovePredictionPositionMap(const ulong positionId);

    //--- AI prediction position mapping: same delegation; a NULL m_positionManager makes every read return its empty default, which looks like "no attribution".
    int    FindAIPredictionPositionIndex(const ulong positionId);
    void   UpsertAIPredictionPositionMap(const ulong positionId, const datetime predictionTime, const ENUM_TRADE_SIGNAL predictionSignal);
    datetime GetAIPredictionTimeForPosition(const ulong positionId);
    ENUM_TRADE_SIGNAL GetAIPredictionSignalForPosition(const ulong positionId);
    void   RemoveAIPredictionPositionMap(const ulong positionId);

    int    FindAIPendingRequestIndex(const uint requestId);
    void   UpsertAIPendingRequestMap(const uint requestId, const string symbol, const datetime predictionTime, const ENUM_TRADE_SIGNAL predictionSignal);
    bool   ConsumeAIPendingRequestMap(const uint requestId, const string symbol, datetime &predictionTime, ENUM_TRADE_SIGNAL &predictionSignal);

    int    FindPendingCloseProfitIndex(const ulong positionId);
    void   AccumulatePendingCloseProfit(const ulong positionId, const double netProfit);
    double ConsumePendingCloseProfit(const ulong positionId);
    void   ClearPendingCloseProfit(const ulong positionId);
    
    // Read by EAOrchestrator's ProcessClosedPositionsForNNTraining; rows whose prediction id comes back empty are skipped there.
    int GetPendingCloseProfits(ulong &positionIds[], double &profits[], string &predictionIds[]);

    void   RecordPositionAttribution(const ulong dealTicket, const string symbol, const ENUM_ORDER_TYPE orderType,
                                     const double volume, const double price, const double stopLossPips,
                                     const double takeProfitPips, const string clusterCode,
                                     const string strategyRole, const string &contributors[]);

    //--- [NN-DIAG] summary; EAOrchestrator prints it with context "deinit" before releasing the managers.
    void   NNDiagPrintSummary(const string context = "");

    void   ClearAll();

private:
    void   NNDiagLog(const string message);
    bool   RunNNAttributionSelfTest();

    int    GetNNDiagEntryMapCount()     const { return m_nnDiagEntryMapCount; }
    int    GetNNDiagCloseByIdCount()    const { return m_nnDiagCloseByIdCount; }
    int    GetNNDiagCloseFallbackCount() const { return m_nnDiagCloseFallbackCount; }
    int    GetNNDiagCloseMissCount()    const { return m_nnDiagCloseMissCount; }
    int    GetNNDiagPartialCloseCount() const { return m_nnDiagPartialCloseCount; }

    void   IncrementNNDiagEntryMapCount()      { m_nnDiagEntryMapCount++; }
    void   IncrementNNDiagCloseByIdCount()     { m_nnDiagCloseByIdCount++; }
    void   IncrementNNDiagCloseFallbackCount() { m_nnDiagCloseFallbackCount++; }
    void   IncrementNNDiagCloseMissCount()     { m_nnDiagCloseMissCount++; }
    void   IncrementNNDiagPartialCloseCount()  { m_nnDiagPartialCloseCount++; }

    void   ResetNNDiagnostics();
};

// Comment contract: BuildTradeCommentWithPrediction appends "|N:<predictionId>" and truncates the base to fit the 31-char broker cap; extraction returns everything after "|N:".
string CTradeAttributionManager::ExtractPredictionIdFromComment(const string comment)
{
    int marker = StringFind(comment, "|N:");
    if(marker < 0)
        return "";

    int start = marker + 3;
    if(start >= StringLen(comment))
        return "";

    return StringSubstr(comment, start);
}

string CTradeAttributionManager::BuildTradeCommentWithPrediction(const string baseComment, const string predictionId)
{
    string comment = baseComment;
    if(predictionId == "")
        return comment;

    string suffix = "|N:" + predictionId;
    const int maxCommentLength = 31;
    int availableBase = maxCommentLength - StringLen(suffix);
    if(availableBase < 0)
        return StringSubstr(suffix, 0, maxCommentLength);

    if(StringLen(comment) > availableBase)
        comment = StringSubstr(comment, 0, availableBase);

    return comment + suffix;
}

string CTradeAttributionManager::NormalizeClusterCode(const string clusterCode)
{
    if(clusterCode == "T" || clusterCode == "R" || clusterCode == "S" || clusterCode == "N")
        return clusterCode;
    return "N";
}

int CTradeAttributionManager::ClusterCodeToNumeric(const string clusterCode)
{
    if(clusterCode == "T") return (int)TREND_CLUSTER;            // 1
    if(clusterCode == "R") return (int)MEAN_REVERSION_CLUSTER;   // 2
    if(clusterCode == "S") return (int)STRUCTURE_CLUSTER;        // 3
    return 0; // STRATEGY_CLUSTER_NONE
}

string CTradeAttributionManager::BuildClusterTaggedTradeComment(const string clusterCode, const string predictionId)
{
    string compactBase = "K:" + NormalizeClusterCode(clusterCode) + "|EA";
    return BuildTradeCommentWithPrediction(compactBase, predictionId);
}

// Exact string match on four names: a strategy renamed elsewhere stops counting as an AI contributor, silently.
bool CTradeAttributionManager::IsAIContributorName(const string strategyName) const
{
    return (strategyName == "Transformer AI" ||
            strategyName == "Ensemble AI" ||
            strategyName == "Neural Network AI" ||
            strategyName == "ONNX AI");
}

bool CTradeAttributionManager::ContributorsIncludeAI(const string &contributors[])
{
    for(int i = 0; i < ArraySize(contributors); i++)
    {
        if(IsAIContributorName(contributors[i]))
        {
            return true;
        }
    }
    return false;
}

bool CTradeAttributionManager::ContributorsIncludeName(const string &contributors[], const string contributorName)
{
    for(int i = 0; i < ArraySize(contributors); i++)
    {
        if(contributors[i] == contributorName)
            return true;
    }
    return false;
}

bool CTradeAttributionManager::ContributorsIncludeONNX(const string &contributors[])
{
    return ContributorsIncludeName(contributors, "ONNX AI");
}

bool CTradeAttributionManager::ContributorsIncludeTransformer(const string &contributors[])
{
    return ContributorsIncludeName(contributors, "Transformer AI");
}

bool CTradeAttributionManager::ContributorsIncludeEnsemble(const string &contributors[])
{
    return ContributorsIncludeName(contributors, "Ensemble AI");
}

bool CTradeAttributionManager::ContributorsIncludeNeuralNetwork(const string &contributors[])
{
    return ContributorsIncludeName(contributors, "Neural Network AI");
}

int CTradeAttributionManager::CountIndicatorContributors(const string &contributors[])
{
    int count = 0;
    for(int i = 0; i < ArraySize(contributors); i++)
    {
        if(contributors[i] == "" || IsAIContributorName(contributors[i]))
            continue;
        count++;
    }
    return count;
}

int CTradeAttributionManager::FindPredictionPositionIndex(const ulong positionId)
{
    if(m_positionManager == NULL) return -1;
    return m_positionManager.FindPredictionPositionIndex(positionId);
}

void CTradeAttributionManager::UpsertPredictionPositionMap(const ulong positionId, const string predictionId)
{
    if(m_positionManager == NULL) return;
    m_positionManager.UpsertPredictionPositionMap(positionId, predictionId);
}

string CTradeAttributionManager::GetPredictionIdForPosition(const ulong positionId)
{
    if(m_positionManager == NULL) return "";
    return m_positionManager.GetPredictionIdForPosition(positionId);
}

void CTradeAttributionManager::RemovePredictionPositionMap(const ulong positionId)
{
    if(m_positionManager == NULL) return;
    m_positionManager.RemovePredictionPositionMap(positionId);
}

int CTradeAttributionManager::FindAIPredictionPositionIndex(const ulong positionId)
{
    if(m_positionManager == NULL) return -1;
    return m_positionManager.FindAIPredictionPositionIndex(positionId);
}

void CTradeAttributionManager::UpsertAIPredictionPositionMap(const ulong positionId, const datetime predictionTime, const ENUM_TRADE_SIGNAL predictionSignal)
{
    if(m_positionManager == NULL) return;
    m_positionManager.UpsertAIPredictionPositionMap(positionId, predictionTime, predictionSignal);
}

datetime CTradeAttributionManager::GetAIPredictionTimeForPosition(const ulong positionId)
{
    if(m_positionManager == NULL) return 0;
    return m_positionManager.GetAIPredictionTimeForPosition(positionId);
}

ENUM_TRADE_SIGNAL CTradeAttributionManager::GetAIPredictionSignalForPosition(const ulong positionId)
{
    if(m_positionManager == NULL) return TRADE_SIGNAL_NONE;
    return m_positionManager.GetAIPredictionSignalForPosition(positionId);
}

void CTradeAttributionManager::RemoveAIPredictionPositionMap(const ulong positionId)
{
    if(m_positionManager == NULL) return;
    m_positionManager.RemoveAIPredictionPositionMap(positionId);
}

// requestId is the key; a miss falls back to the last upserted entry whose symbol matches, whatever its age.
int CTradeAttributionManager::FindAIPendingRequestIndex(const uint requestId)
{
    for(int i = 0; i < ArraySize(m_aiPendingRequestIds); i++)
    {
        if(m_aiPendingRequestIds[i] == requestId)
            return i;
    }
    return -1;
}

void CTradeAttributionManager::UpsertAIPendingRequestMap(const uint requestId, const string symbol, const datetime predictionTime, const ENUM_TRADE_SIGNAL predictionSignal)
{
    if(requestId == 0 || symbol == "" || predictionTime <= 0 || predictionSignal == TRADE_SIGNAL_NONE)
        return;

    int idx = FindAIPendingRequestIndex(requestId);
    if(idx >= 0)
    {
        m_aiPendingSymbols[idx] = symbol;
        m_aiPendingPredictionTimes[idx] = predictionTime;
        m_aiPendingPredictionSignals[idx] = predictionSignal;
        return;
    }

    int size = ArraySize(m_aiPendingRequestIds);
    ArrayResize(m_aiPendingRequestIds, size + 1);
    ArrayResize(m_aiPendingSymbols, size + 1);
    ArrayResize(m_aiPendingPredictionTimes, size + 1);
    ArrayResize(m_aiPendingPredictionSignals, size + 1);
    m_aiPendingRequestIds[size] = requestId;
    m_aiPendingSymbols[size] = symbol;
    m_aiPendingPredictionTimes[size] = predictionTime;
    m_aiPendingPredictionSignals[size] = predictionSignal;
}

bool CTradeAttributionManager::ConsumeAIPendingRequestMap(const uint requestId, const string symbol, datetime &predictionTime, ENUM_TRADE_SIGNAL &predictionSignal)
{
    predictionTime = 0;
    predictionSignal = TRADE_SIGNAL_NONE;

    int idx = -1;
    if(requestId > 0)
        idx = FindAIPendingRequestIndex(requestId);

    if(idx < 0 && symbol != "")
    {
        for(int i = ArraySize(m_aiPendingRequestIds) - 1; i >= 0; i--)
        {
            if(m_aiPendingSymbols[i] == symbol)
            {
                idx = i;
                break;
            }
        }
    }

    if(idx < 0)
        return false;

    predictionTime = m_aiPendingPredictionTimes[idx];
    predictionSignal = m_aiPendingPredictionSignals[idx];

    int last = ArraySize(m_aiPendingRequestIds) - 1;
    if(last >= 0)
    {
        if(idx != last)
        {
            m_aiPendingRequestIds[idx] = m_aiPendingRequestIds[last];
            m_aiPendingSymbols[idx] = m_aiPendingSymbols[last];
            m_aiPendingPredictionTimes[idx] = m_aiPendingPredictionTimes[last];
            m_aiPendingPredictionSignals[idx] = m_aiPendingPredictionSignals[last];
        }
        ArrayResize(m_aiPendingRequestIds, last);
        ArrayResize(m_aiPendingSymbols, last);
        ArrayResize(m_aiPendingPredictionTimes, last);
        ArrayResize(m_aiPendingPredictionSignals, last);
    }

    return true;
}

// No caller in the repo invokes AccumulatePendingCloseProfit, so m_pendingClose* stays empty and GetPendingCloseProfits returns 0.
int CTradeAttributionManager::FindPendingCloseProfitIndex(const ulong positionId)
{
    for(int i = 0; i < ArraySize(m_pendingClosePositionIds); i++)
    {
        if(m_pendingClosePositionIds[i] == positionId)
            return i;
    }
    return -1;
}

void CTradeAttributionManager::AccumulatePendingCloseProfit(const ulong positionId, const double netProfit)
{
    if(positionId == 0)
        return;

    int idx = FindPendingCloseProfitIndex(positionId);
    if(idx >= 0)
    {
        m_pendingCloseNetProfit[idx] += netProfit;
        return;
    }

    int size = ArraySize(m_pendingClosePositionIds);
    ArrayResize(m_pendingClosePositionIds, size + 1);
    ArrayResize(m_pendingCloseNetProfit, size + 1);
    m_pendingClosePositionIds[size] = positionId;
    m_pendingCloseNetProfit[size] = netProfit;
}

double CTradeAttributionManager::ConsumePendingCloseProfit(const ulong positionId)
{
    int idx = FindPendingCloseProfitIndex(positionId);
    if(idx < 0)
        return 0.0;

    double accumulated = m_pendingCloseNetProfit[idx];
    int last = ArraySize(m_pendingClosePositionIds) - 1;
    if(last >= 0)
    {
        if(idx != last)
        {
            m_pendingClosePositionIds[idx] = m_pendingClosePositionIds[last];
            m_pendingCloseNetProfit[idx] = m_pendingCloseNetProfit[last];
        }
        ArrayResize(m_pendingClosePositionIds, last);
        ArrayResize(m_pendingCloseNetProfit, last);
    }

    return accumulated;
}

void CTradeAttributionManager::ClearPendingCloseProfit(const ulong positionId)
{
    int idx = FindPendingCloseProfitIndex(positionId);
    if(idx < 0)
        return;

    int last = ArraySize(m_pendingClosePositionIds) - 1;
    if(last >= 0)
    {
        if(idx != last)
        {
            m_pendingClosePositionIds[idx] = m_pendingClosePositionIds[last];
            m_pendingCloseNetProfit[idx] = m_pendingCloseNetProfit[last];
        }
        ArrayResize(m_pendingClosePositionIds, last);
        ArrayResize(m_pendingCloseNetProfit, last);
    }
}

int CTradeAttributionManager::GetPendingCloseProfits(ulong &positionIds[], double &profits[], string &predictionIds[])
{
int count = ArraySize(m_pendingClosePositionIds);
if(count == 0)
    return 0;
    
ArrayResize(positionIds, count);
ArrayResize(profits, count);
ArrayResize(predictionIds, count);
    
for(int i = 0; i < count; i++)
{
    positionIds[i] = m_pendingClosePositionIds[i];
    profits[i] = m_pendingCloseNetProfit[i];
        
    // Prediction id is read from the LIVE position comment, not the position map; an unselectable position yields "" while its profit is still returned.
    if(PositionSelectByTicket(m_pendingClosePositionIds[i]))
    {
        string comment = PositionGetString(POSITION_COMMENT);
        predictionIds[i] = ExtractPredictionIdFromComment(comment);
    }
    else
    {
        predictionIds[i] = "";
    }
}
    
return count;
}

bool CTradeAttributionManager::IsPositionIdStillOpen(const ulong positionId)
{
    if(positionId == 0)
        return false;

    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

        ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
        if(identifier == positionId)
            return true;
    }

    return false;
}

int CTradeAttributionManager::FindAttributionIndexByPositionId(const ulong positionId) const
{
    int count = ArraySize(m_attributionPositionIds);
    for(int i = 0; i < count; i++)
    {
        if(m_attributionPositionIds[i] == positionId)
            return i;
    }
    return -1;
}

string CTradeAttributionManager::JoinContributors(const string &contributors[]) const
{
    string csv = "";
    int count = ArraySize(contributors);
    for(int i = 0; i < count; i++)
    {
        if(i > 0) csv += ",";
        csv += contributors[i];
    }
    return csv;
}

void CTradeAttributionManager::SplitContributors(const string csv, string &contributors[]) const
{
    ArrayResize(contributors, 0);
    if(csv == "") return;
    
    int start = 0;
    int pos = StringFind(csv, ",", start);
    while(pos >= 0)
    {
        string part = StringSubstr(csv, start, pos - start);
        int newSize = ArraySize(contributors) + 1;
        ArrayResize(contributors, newSize);
        contributors[newSize - 1] = part;
        start = pos + 1;
        pos = StringFind(csv, ",", start);
    }
    string lastPart = StringSubstr(csv, start);
    int newSize = ArraySize(contributors) + 1;
    ArrayResize(contributors, newSize);
    contributors[newSize - 1] = lastPart;
}

void CTradeAttributionManager::UpsertPositionAttribution(const ulong positionId, const string &contributors[])
{
    int index = FindAttributionIndexByPositionId(positionId);
    string csv = JoinContributors(contributors);
    
    if(index >= 0)
    {
        m_attributionContributorCsv[index] = csv;
    }
    else
    {
        int newSize = ArraySize(m_attributionPositionIds) + 1;
        ArrayResize(m_attributionPositionIds, newSize);
        ArrayResize(m_attributionContributorCsv, newSize);
        m_attributionPositionIds[newSize - 1] = positionId;
        m_attributionContributorCsv[newSize - 1] = csv;
    }
}

bool CTradeAttributionManager::PopPositionAttribution(const ulong positionId, string &contributors[])
{
    int index = FindAttributionIndexByPositionId(positionId);
    if(index < 0)
        return false;
    
    SplitContributors(m_attributionContributorCsv[index], contributors);
    
    int count = ArraySize(m_attributionPositionIds);
    for(int i = index; i < count - 1; i++)
    {
        m_attributionPositionIds[i] = m_attributionPositionIds[i + 1];
        m_attributionContributorCsv[i] = m_attributionContributorCsv[i + 1];
    }
    ArrayResize(m_attributionPositionIds, count - 1);
    ArrayResize(m_attributionContributorCsv, count - 1);
    
    return true;
}

bool CTradeAttributionManager::PopClosedTradeAttribution(string &contributors[], double &netProfit)
{
    if(!m_hasClosedTradeAttribution)
        return false;
    
    ArrayCopy(contributors, m_closedTradeContributors);
    netProfit = m_closedTradeNetProfit;
    
    m_hasClosedTradeAttribution = false;
    ArrayResize(m_closedTradeContributors, 0);
    m_closedTradeNetProfit = 0.0;
    
    return true;
}

int CTradeAttributionManager::GetActiveAttributionCount() const
{
    return ArraySize(m_attributionPositionIds);
}

void CTradeAttributionManager::ClearClosedTradeAttribution()
{
    m_hasClosedTradeAttribution = false;
    ArrayResize(m_closedTradeContributors, 0);
    m_closedTradeNetProfit = 0.0;
}

void CTradeAttributionManager::NNDiagLog(const string message)
{
    if(m_enableNNDiagnostics)
        Print("[NN-DIAG] ", message);
}

void CTradeAttributionManager::NNDiagPrintSummary(const string context = "")
{
    if(!m_enableNNDiagnostics)
        return;

    string tag = (context == "") ? "runtime" : context;
    int activeMapSize = (m_positionManager != NULL) ? m_positionManager.GetPositionStateCount() : 0;
    PrintFormat("[NN-DIAG] Summary (%s) | EntryMap=%d | CloseById=%d | CloseFallback=%d | CloseMiss=%d | PartialClose=%d | ActiveMap=%d",
                tag,
                m_nnDiagEntryMapCount,
                m_nnDiagCloseByIdCount,
                m_nnDiagCloseFallbackCount,
                m_nnDiagCloseMissCount,
                m_nnDiagPartialCloseCount,
                activeMapSize);
    m_nnDiagLastSummaryTime = TimeCurrent();
}

bool CTradeAttributionManager::RunNNAttributionSelfTest()
{
    if(!m_runSelfTest)
        return true;

    NNDiagLog("Self-test started");
    bool ok = true;

    string testPrediction = "12345678901234";
    string comment = BuildTradeCommentWithPrediction("Enterprise AI Signal", testPrediction);
    string extracted = ExtractPredictionIdFromComment(comment);
    if(extracted != testPrediction)
    {
        ok = false;
        NNDiagLog("Self-test failed: comment prediction extraction mismatch");
    }

    const ulong testPositionId = 999001;
    UpsertPredictionPositionMap(testPositionId, testPrediction);
    if(GetPredictionIdForPosition(testPositionId) != testPrediction)
    {
        ok = false;
        NNDiagLog("Self-test failed: position->prediction map upsert/get mismatch");
    }
    RemovePredictionPositionMap(testPositionId);
    if(GetPredictionIdForPosition(testPositionId) != "")
    {
        ok = false;
        NNDiagLog("Self-test failed: position->prediction map remove mismatch");
    }

    NNDiagLog(ok ? "Self-test passed" : "Self-test failed");
    return ok;
}

void CTradeAttributionManager::RecordPositionAttribution(
    const ulong dealTicket,
    const string symbol,
    const ENUM_ORDER_TYPE orderType,
    const double volume,
    const double price,
    const double stopLossPips,
    const double takeProfitPips,
    const string clusterCode,
    const string strategyRole,
    const string &contributors[])
{
    // Logging only: nothing is stored, and the sole side effect is the entry-map counter below.
    if(m_enableNNDiagnostics)
    {
        PrintFormat("[TRADE-ATTRIBUTION] deal=%I64u | %s | %s | vol=%.2f | price=%.5f | SL=%.1f | TP=%.1f | cluster=%s | role=%s",
                    dealTicket, symbol, EnumToString(orderType), volume, price, stopLossPips, takeProfitPips,
                    clusterCode, strategyRole);
        if(ArraySize(contributors) > 0)
        {
            string contribStr = "";
            for(int i = 0; i < ArraySize(contributors); i++)
            {
                if(contributors[i] != "") contribStr += contributors[i] + ",";
            }
            PrintFormat("[TRADE-ATTRIBUTION] Contributors: %s", contribStr);
        }
    }
    
    IncrementNNDiagEntryMapCount();
}

void CTradeAttributionManager::ResetNNDiagnostics()
{
    m_nnDiagEntryMapCount = 0;
    m_nnDiagCloseByIdCount = 0;
    m_nnDiagCloseFallbackCount = 0;
    m_nnDiagCloseMissCount = 0;
    m_nnDiagPartialCloseCount = 0;
    m_nnDiagLastSummaryTime = TimeCurrent();
}

// Drops every in-memory map: a position still open here loses its contributor link, so its later close is recorded unattributed.
void CTradeAttributionManager::ClearAll()
{
    ArrayResize(m_aiPendingRequestIds, 0);
    ArrayResize(m_aiPendingSymbols, 0);
    ArrayResize(m_aiPendingPredictionTimes, 0);
    ArrayResize(m_aiPendingPredictionSignals, 0);
    ArrayResize(m_pendingClosePositionIds, 0);
    ArrayResize(m_pendingCloseNetProfit, 0);
    ArrayResize(m_attributionPositionIds, 0);
    ArrayResize(m_attributionContributorCsv, 0);
    ArrayResize(m_closedTradeContributors, 0);
    m_closedTradeNetProfit = 0.0;
    m_hasClosedTradeAttribution = false;
}

#endif // __TRADE_ATTRIBUTION_MANAGER_MQH__
