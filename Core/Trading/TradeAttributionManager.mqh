//+------------------------------------------------------------------+
//| TradeAttributionManager.mqh - Trade attribution & NN prediction  |
//| Copyright 2025, Aggressive Trading Systems                       |
//| https://www.aggressivetrading.com                                |
//| Encapsulates trade comment building, prediction position mapping,|
//| AI pending request tracking, close profit accumulation, and NN   |
//| attribution diagnostics.                                          |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#ifndef TRADE_ATTRIBUTION_MANAGER_MQH
#define TRADE_ATTRIBUTION_MANAGER_MQH

#include <Object.mqh>
#include "../Utils/Enums.mqh"
#include "PositionStateManager.mqh"

//+------------------------------------------------------------------+
//| Trade Attribution Manager Class                                   |
//+------------------------------------------------------------------+
class CTradeAttributionManager
{
private:
    // AI pending request mapping
    uint    m_aiPendingRequestIds[];
    string  m_aiPendingSymbols[];
    datetime m_aiPendingPredictionTimes[];
    ENUM_TRADE_SIGNAL m_aiPendingPredictionSignals[];

    // Pending close profit tracking
    ulong   m_pendingClosePositionIds[];
    double  m_pendingCloseNetProfit[];

    // NN attribution diagnostics counters
    int     m_nnDiagEntryMapCount;
    int     m_nnDiagCloseByIdCount;
    int     m_nnDiagCloseFallbackCount;
    int     m_nnDiagCloseMissCount;
    int     m_nnDiagPartialCloseCount;
    datetime m_nnDiagLastSummaryTime;

    // Diagnostics enable flags (set from EA inputs)
    bool    m_enableNNDiagnostics;
    bool    m_runSelfTest;

    // Reference to position state manager (not owned)
    CPositionStateManager *m_positionStateManager;

    //--- Check if a contributor name is an AI strategy
    bool IsAIContributorName(const string strategyName) const;

public:
    CTradeAttributionManager() :
        m_nnDiagEntryMapCount(0),
        m_nnDiagCloseByIdCount(0),
        m_nnDiagCloseFallbackCount(0),
        m_nnDiagCloseMissCount(0),
        m_nnDiagPartialCloseCount(0),
        m_nnDiagLastSummaryTime(0),
        m_enableNNDiagnostics(true),
        m_runSelfTest(true),
        m_positionStateManager(NULL)
    {
    }

    ~CTradeAttributionManager()
    {
        ClearAll();
    }

    //--- Configuration
    void SetPositionStateManager(CPositionStateManager &mgr) { m_positionStateManager = &mgr; }
    void SetNNDiagnosticsEnabled(bool enabled) { m_enableNNDiagnostics = enabled; }
    void SetRunSelfTest(bool enabled) { m_runSelfTest = enabled; }

    //--- Trade comment building
    string ExtractPredictionIdFromComment(const string comment);
    string BuildTradeCommentWithPrediction(const string baseComment, const string predictionId);
    string NormalizeClusterCode(const string clusterCode);
    int    ClusterCodeToNumeric(const string clusterCode);
    string BuildClusterTaggedTradeComment(const string clusterCode, const string predictionId);

    //--- Contributor analysis
    bool   ContributorsIncludeAI(const string &contributors[]);
    bool   ContributorsIncludeName(const string &contributors[], const string contributorName);
    bool   ContributorsIncludeONNX(const string &contributors[]);
    int    CountIndicatorContributors(const string &contributors[]);

    //--- Prediction position mapping (delegates to CPositionStateManager)
    int    FindPredictionPositionIndex(const ulong positionId);
    void   UpsertPredictionPositionMap(const ulong positionId, const string predictionId);
    string GetPredictionIdForPosition(const ulong positionId);
    void   RemovePredictionPositionMap(const ulong positionId);

    //--- AI prediction position mapping (delegates to CPositionStateManager)
    int    FindAIPredictionPositionIndex(const ulong positionId);
    void   UpsertAIPredictionPositionMap(const ulong positionId, const datetime predictionTime, const ENUM_TRADE_SIGNAL predictionSignal);
    datetime GetAIPredictionTimeForPosition(const ulong positionId);
    ENUM_TRADE_SIGNAL GetAIPredictionSignalForPosition(const ulong positionId);
    void   RemoveAIPredictionPositionMap(const ulong positionId);

    //--- AI pending request mapping
    int    FindAIPendingRequestIndex(const uint requestId);
    void   UpsertAIPendingRequestMap(const uint requestId, const string symbol, const datetime predictionTime, const ENUM_TRADE_SIGNAL predictionSignal);
    bool   ConsumeAIPendingRequestMap(const uint requestId, const string symbol, datetime &predictionTime, ENUM_TRADE_SIGNAL &predictionSignal);

    //--- Pending close profit tracking
    int    FindPendingCloseProfitIndex(const ulong positionId);
    void   AccumulatePendingCloseProfit(const ulong positionId, const double netProfit);
    double ConsumePendingCloseProfit(const ulong positionId);
    void   ClearPendingCloseProfit(const ulong positionId);

    //--- Position open check
    bool   IsPositionIdStillOpen(const ulong positionId);

    //--- NN diagnostics
    void   NNDiagLog(const string message);
    void   NNDiagPrintSummary(const string context = "");
    bool   RunNNAttributionSelfTest();

    //--- Diagnostics counter accessors (for external increment)
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

    //--- Reset diagnostics counters
    void   ResetNNDiagnostics();

    //--- Clear all internal state
    void   ClearAll();
};

//+------------------------------------------------------------------+
//| Trade comment building implementation                             |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| AI contributor name check (moved from global function)            |
//+------------------------------------------------------------------+
bool CTradeAttributionManager::IsAIContributorName(const string strategyName) const
{
    return (strategyName == "Transformer AI" ||
            strategyName == "Ensemble AI" ||
            strategyName == "Neural Network AI" ||
            strategyName == "ONNX AI");
}

//+------------------------------------------------------------------+
//| Contributor analysis implementation                               |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Prediction position mapping (delegates to CPositionStateManager)  |
//+------------------------------------------------------------------+
int CTradeAttributionManager::FindPredictionPositionIndex(const ulong positionId)
{
    if(m_positionStateManager == NULL) return -1;
    return m_positionStateManager.FindStateIndex(positionId);
}

void CTradeAttributionManager::UpsertPredictionPositionMap(const ulong positionId, const string predictionId)
{
    if(m_positionStateManager == NULL) return;
    m_positionStateManager.UpsertPredictionId(positionId, predictionId);
}

string CTradeAttributionManager::GetPredictionIdForPosition(const ulong positionId)
{
    if(m_positionStateManager == NULL) return "";
    return m_positionStateManager.GetPredictionId(positionId);
}

void CTradeAttributionManager::RemovePredictionPositionMap(const ulong positionId)
{
    if(m_positionStateManager == NULL) return;
    m_positionStateManager.RemovePrediction(positionId);
}

//+------------------------------------------------------------------+
//| AI prediction position mapping (delegates to CPositionStateManager)|
//+------------------------------------------------------------------+
int CTradeAttributionManager::FindAIPredictionPositionIndex(const ulong positionId)
{
    if(m_positionStateManager == NULL) return -1;
    return m_positionStateManager.FindStateIndex(positionId);
}

void CTradeAttributionManager::UpsertAIPredictionPositionMap(const ulong positionId, const datetime predictionTime, const ENUM_TRADE_SIGNAL predictionSignal)
{
    if(m_positionStateManager == NULL) return;
    m_positionStateManager.UpsertAIPrediction(positionId, predictionTime, predictionSignal);
}

datetime CTradeAttributionManager::GetAIPredictionTimeForPosition(const ulong positionId)
{
    if(m_positionStateManager == NULL) return 0;
    return m_positionStateManager.GetAIPredictionTime(positionId);
}

ENUM_TRADE_SIGNAL CTradeAttributionManager::GetAIPredictionSignalForPosition(const ulong positionId)
{
    if(m_positionStateManager == NULL) return TRADE_SIGNAL_NONE;
    return m_positionStateManager.GetAIPredictionSignal(positionId);
}

void CTradeAttributionManager::RemoveAIPredictionPositionMap(const ulong positionId)
{
    if(m_positionStateManager == NULL) return;
    m_positionStateManager.RemoveAIPrediction(positionId);
}

//+------------------------------------------------------------------+
//| AI pending request mapping implementation                         |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Pending close profit tracking implementation                      |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| Position open check                                               |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| NN diagnostics implementation                                     |
//+------------------------------------------------------------------+
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
    int activeMapSize = (m_positionStateManager != NULL) ? m_positionStateManager.GetCount() : 0;
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

//+------------------------------------------------------------------+
//| Reset diagnostics counters                                        |
//+------------------------------------------------------------------+
void CTradeAttributionManager::ResetNNDiagnostics()
{
    m_nnDiagEntryMapCount = 0;
    m_nnDiagCloseByIdCount = 0;
    m_nnDiagCloseFallbackCount = 0;
    m_nnDiagCloseMissCount = 0;
    m_nnDiagPartialCloseCount = 0;
    m_nnDiagLastSummaryTime = TimeCurrent();
}

//+------------------------------------------------------------------+
//| Clear all internal state                                          |
//+------------------------------------------------------------------+
void CTradeAttributionManager::ClearAll()
{
    ArrayResize(m_aiPendingRequestIds, 0);
    ArrayResize(m_aiPendingSymbols, 0);
    ArrayResize(m_aiPendingPredictionTimes, 0);
    ArrayResize(m_aiPendingPredictionSignals, 0);
    ArrayResize(m_pendingClosePositionIds, 0);
    ArrayResize(m_pendingCloseNetProfit, 0);
}

#endif // __TRADE_ATTRIBUTION_MANAGER_MQH__
