// TradeExecutor.mqh
// Executes trades with proper confirmation and attribution
#property strict

#ifndef CORE_ORCHESTRATION_TRADE_EXECUTOR_MQH
#define CORE_ORCHESTRATION_TRADE_EXECUTOR_MQH

#include "../../Core/Trading/TradeManager.mqh"
#include "../../Core/Trading/TradeAttributionManager.mqh"
#include "../Position/PositionManager.mqh"
#include "../../Core/Registry/NeuralNetRegistry.mqh"
#include "../../Core/Orchestration/CandidateBuilder.mqh"
#include "../../Core/Utils/Enums.mqh"
#include "../../Core/Utils/JsonLogger.mqh"
#include "../../Core/Utils/CorrelationId.mqh"
#include <Trade\Trade.mqh>

class CTradeExecutor
{
private:
    CTradeManager* m_tradeManager;
    CTradeAttributionManager* m_attributionManager;
    CPositionManager* m_positionManager;
    CNeuralNetRegistry* m_neuralNetRegistry;
    
    struct SPendingConfirmation
    {
        ulong orderTicket;
        string symbol;
        ENUM_ORDER_TYPE orderType;
        double expectedPrice;
        double volume;
        datetime sentAt;
        int checkAttempts;
        bool isActive;
        STradeCandidate candidate; // Original candidate for attribution
        
        SPendingConfirmation() : orderTicket(0), symbol(""), orderType(ORDER_TYPE_BUY),
                                expectedPrice(0), volume(0), sentAt(0), checkAttempts(0), isActive(false) {}
    };
    
    SPendingConfirmation m_pendingConfirmations[];
    int m_pendingCount;
    int m_maxPending;
    
public:
    struct SExecutionResult
    {
        bool executed;
        bool confirmed;
        ulong dealTicket;
        ulong orderTicket;
        double filledPrice;
        double filledVolume;
        uint retcode;
        string reason;
        
        SExecutionResult() : executed(false), confirmed(false), dealTicket(0), orderTicket(0),
                            filledPrice(0), filledVolume(0), retcode(0) {}
    };
    
    CTradeExecutor() : m_tradeManager(NULL), m_attributionManager(NULL), m_positionManager(NULL),
                       m_neuralNetRegistry(NULL), m_pendingCount(0), m_maxPending(50)
    {
        ArrayResize(m_pendingConfirmations, m_maxPending);
    }
    
    ~CTradeExecutor() {}
    
    void SetDependencies(CTradeManager* tm, CTradeAttributionManager* att, 
                         CPositionManager* psm, CNeuralNetRegistry* nnReg)
    {
        m_tradeManager = tm;
        m_attributionManager = att;
        m_positionManager = psm;
        m_neuralNetRegistry = nnReg;
    }
    
    // Main execution entry point
    SExecutionResult Execute(const STradeCandidate &candidate, const string corrId = "")
    {
        // Set correlation ID for structured logging
        if(corrId != "")
            CJsonLogger::SetCorrelationId(corrId);
        
        SExecutionResult result;
        
        if(candidate.lotSize <= 0)
        {
            result.reason = "Invalid lot size";
            CJsonLogger::LogRiskEvent("TradeExecute", candidate.symbol, "INVALID_LOT", "Lot size <= 0", 0.0, candidate.lotSize, corrId);
            CJsonLogger::ClearCorrelationId();
            return result;
        }

        // Defensive guard: if dependencies were never wired, fail gracefully instead of
        // dereferencing a NULL m_tradeManager (which caused an invalid-pointer crash at OpenPosition).
        if(m_tradeManager == NULL)
        {
            result.reason = "TradeExecutor: m_tradeManager dependency not wired";
            CJsonLogger::LogRiskEvent("TradeExecute", candidate.symbol, "NO_DEPENDENCY", "m_tradeManager == NULL", 0.0, candidate.lotSize, corrId);
            CJsonLogger::ClearCorrelationId();
            return result;
        }

        // Build comment with metadata (includes correlation ID for lineage)
        string comment = BuildExecutionComment(candidate, corrId);
        
        // Execute market order
        bool executed = m_tradeManager.OpenPosition(
            candidate.symbol,
            candidate.orderType,
            candidate.lotSize,
            candidate.entryPrice,
            candidate.stopLossPips,
            candidate.takeProfitPips,
            comment
        );
        
        if(!executed)
        {
            result.retcode = m_tradeManager.GetLastRetcode();
            result.reason = GetTradeErrorDescription(m_tradeManager.GetLastRetcode());
            CJsonLogger::LogRiskEvent("TradeExecute", candidate.symbol, "EXECUTION_FAILED", 
                StringFormat("retcode=%u reason=%s", result.retcode, result.reason), 
                0.0, candidate.lotSize, corrId);
            CJsonLogger::ClearCorrelationId();
            return result;
        }
        
        result.executed = true;
        
        STradeExecutionReceipt receipt;
        m_tradeManager.GetLastExecutionReceipt(receipt);
        result.orderTicket = receipt.orderTicket;
        result.dealTicket = receipt.dealTicket;
        result.filledPrice = receipt.averagePrice;
        result.filledVolume = receipt.filledVolume;
        result.retcode = receipt.retcode;
        
        // Log trade open via structured JSON logger
        CJsonLogger::LogTradeOpen(candidate.symbol, 
            (candidate.orderType == ORDER_TYPE_BUY) ? "BUY" : "SELL",
            candidate.lotSize, candidate.stopLossPips, candidate.takeProfitPips,
            candidate.strategyRole, candidate.clusterCode, corrId);
        
        QueueConfirmation(candidate, result);
        
        CJsonLogger::ClearCorrelationId();
        return result;
    }
    
    // Check pending confirmations (call from OnTick)
    void CheckPendingConfirmations()
    {
        if(m_pendingCount <= 0) return;
        
        datetime historyFrom = TimeCurrent() - 300;
        datetime historyTo = TimeCurrent() + 60;
        
        for(int i = m_pendingCount - 1; i >= 0; i--)
        {
            if(!m_pendingConfirmations[i].isActive) continue;
            
            m_pendingConfirmations[i].checkAttempts++;
            
            bool resolved = false;
            
            if(HistorySelect(historyFrom, historyTo))
            {
                int totalDeals = HistoryDealsTotal();
                for(int d = 0; d < totalDeals; d++)
                {
                    ulong dealTicket = HistoryDealGetTicket(d);
                    if(dealTicket == 0) continue;
                    
                    string dealSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
                    if(dealSymbol != m_pendingConfirmations[i].symbol) continue;
                    
                    ulong dealOrderTicket = HistoryDealGetInteger(dealTicket, DEAL_ORDER);
                    if(dealOrderTicket != m_pendingConfirmations[i].orderTicket) continue;
                    
                    double dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                    double dealVolume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
                    ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
                    
                    PrintFormat("[EXECUTION-CONFIRMED] %s | order=%I64u | deal=%I64u | price=%.5f | volume=%.2f | type=%s | attempts=%d",
                                dealSymbol, m_pendingConfirmations[i].orderTicket, dealTicket,
                                dealPrice, dealVolume, EnumToString(dealType), m_pendingConfirmations[i].checkAttempts);
                    
                    RecordAttribution(m_pendingConfirmations[i].candidate, dealTicket, dealPrice, dealVolume);
                    
                    RecordPositionState(dealTicket, m_pendingConfirmations[i].candidate, dealPrice, dealVolume);
                    
                    MapToNeuralNetPrediction(m_pendingConfirmations[i].candidate, dealTicket);
                    
                    resolved = true;
                    break;
                }
            }
            
            if(resolved || m_pendingConfirmations[i].checkAttempts >= 5)
            {
                if(!resolved)
                {
                    PrintFormat("[EXECUTION-TIMEOUT] %s | order=%I64u | attempts=%d | no deal found",
                                m_pendingConfirmations[i].symbol, m_pendingConfirmations[i].orderTicket,
                                m_pendingConfirmations[i].checkAttempts);
                }
                
                RemovePendingAt(i);
            }
        }
    }
    
    void QueueConfirmation(const STradeCandidate &candidate, const SExecutionResult &result)
    {
        if(m_pendingCount >= m_maxPending)
        {
            Print("[TRADE-EXECUTOR] WARNING: Pending confirmation queue full, dropping oldest");
            RemovePendingAt(0);
        }
        
        int idx = m_pendingCount;
        if(idx < ArraySize(m_pendingConfirmations))
        {
            m_pendingConfirmations[idx].orderTicket = result.orderTicket;
            m_pendingConfirmations[idx].symbol = candidate.symbol;
            m_pendingConfirmations[idx].orderType = candidate.orderType;
            m_pendingConfirmations[idx].expectedPrice = candidate.entryPrice;
            m_pendingConfirmations[idx].volume = candidate.lotSize;
            m_pendingConfirmations[idx].sentAt = TimeCurrent();
            m_pendingConfirmations[idx].checkAttempts = 0;
            m_pendingConfirmations[idx].isActive = true;
            m_pendingConfirmations[idx].candidate = candidate;
            m_pendingCount++;
        }
    }
    
    void RemovePendingAt(int index)
    {
        if(index < 0 || index >= m_pendingCount) return;
        
        for(int i = index; i < m_pendingCount - 1; i++)
            m_pendingConfirmations[i] = m_pendingConfirmations[i + 1];
        
        m_pendingConfirmations[m_pendingCount].isActive = false;
        m_pendingConfirmations[m_pendingCount].orderTicket = 0;
        m_pendingCount--;
    }
    
    void RecordAttribution(const STradeCandidate &candidate, ulong dealTicket, double price, double volume)
    {
        if(m_attributionManager == NULL) return;
        
        // Batch 153: the summary CSV used to be stored as a single-element
        // array ("would split by comma" was never implemented), so every
        // attribution row carried one malformed "S1,S3,AI:x" string instead
        // of the individual contributor names.
        string contributors[];
        if(m_attributionManager != NULL && candidate.contributorSummary != "")
            m_attributionManager.SplitContributors(candidate.contributorSummary, contributors);
        
        m_attributionManager.RecordPositionAttribution(
            dealTicket,
            candidate.symbol,
            candidate.orderType,
            volume,
            price,
            candidate.stopLossPips,
            candidate.takeProfitPips,
            candidate.clusterCode,
            candidate.strategyRole,
            contributors
        );
    }
    
    void RecordPositionState(ulong dealTicket, const STradeCandidate &candidate, double price, double volume)
    {
        if(m_positionManager == NULL) return;
        
        // Find the position ticket
        ulong positionTicket = 0;
        if(HistorySelect(TimeCurrent() - 3600, TimeCurrent() + 60))
        {
            int totalDeals = HistoryDealsTotal();
            for(int d = 0; d < totalDeals; d++)
            {
                ulong dt = HistoryDealGetTicket(d);
                if(dt == dealTicket)
                {
                    long posId = HistoryDealGetInteger(dt, DEAL_POSITION_ID);
                    if(posId > 0) positionTicket = (ulong)posId;
                    break;
                }
            }
        }
        
        if(positionTicket > 0)
        {
            m_positionManager.RegisterPositionState(
                positionTicket,
                candidate.symbol,
                candidate.orderType,
                volume,
                price,
                candidate.stopLossPips,
                candidate.takeProfitPips,
                (int)StringToInteger(candidate.clusterCode),
                candidate.strategyRole
            );
        }
    }
    
    void MapToNeuralNetPrediction(const STradeCandidate &candidate, ulong dealTicket)
    {
        if(m_neuralNetRegistry == NULL) return;
        
        CNeuralNetworkStrategy* nn = m_neuralNetRegistry.GetNeuralNet(candidate.symbol);
        if(nn != NULL)
        {
            // Would map the deal to NN prediction for training
            // nn.MapDealToPrediction(dealTicket, candidate);
        }
    }
    
    string BuildExecutionComment(const STradeCandidate &candidate, const string corrId = "")
    {
        // Format: EA|CLUSTER|RISK|SL|TP|ROLE|CID|STRAT
        // CID = last 8 chars of correlation ID for brevity
        // STRAT = strategy code (MOM, TND, MR, etc.)
        string cidShort = "";
        if(corrId != "" && StringLen(corrId) >= 8) {
            cidShort = StringSubstr(corrId, StringLen(corrId) - 8);
        }
        
        string stratCode = "UNK";
        // Extract primary strategy from contributor summary
        if(candidate.contributorSummary != "") {
            // Parse first contributor from CSV
            int comma = StringFind(candidate.contributorSummary, ",");
            string firstContributor = (comma >= 0) ? StringSubstr(candidate.contributorSummary, 0, comma) 
                                                  : candidate.contributorSummary;
            // Map common names to codes
            if(StringFind(firstContributor, "Momentum") >= 0) stratCode = "MOM";
            else if(StringFind(firstContributor, "Trend") >= 0) stratCode = "TND";
            else if(StringFind(firstContributor, "Support") >= 0 || StringFind(firstContributor, "Resistance") >= 0) stratCode = "SR";
            else if(StringFind(firstContributor, "Candlestick") >= 0) stratCode = "CSL";
            else if(StringFind(firstContributor, "MeanRev") >= 0 || StringFind(firstContributor, "Mean Reversion") >= 0) stratCode = "MR";
            else if(StringFind(firstContributor, "VolBreak") >= 0 || StringFind(firstContributor, "Volatility") >= 0) stratCode = "VB";
            else if(StringFind(firstContributor, "FVG") >= 0) stratCode = "FVG";
            else if(StringFind(firstContributor, "Turtle") >= 0) stratCode = "TS";
            else if(StringFind(firstContributor, "Breaker") >= 0) stratCode = "BB";
            else if(StringFind(firstContributor, "NYOpen") >= 0) stratCode = "NY";
            else if(StringFind(firstContributor, "Asian") >= 0) stratCode = "ARB";
            else if(StringFind(firstContributor, "StatArb") >= 0 || StringFind(firstContributor, "Statistical") >= 0) stratCode = "STAT";
            else if(StringFind(firstContributor, "Kalman") >= 0) stratCode = "KLM";
            else if(StringFind(firstContributor, "ChangePoint") >= 0) stratCode = "CPD";
            else if(StringFind(firstContributor, "FourState") >= 0) stratCode = "4ST";
            else if(StringFind(firstContributor, "VolTarget") >= 0) stratCode = "VT";
            else if(StringFind(firstContributor, "Liquidity") >= 0) stratCode = "LS";
            else if(StringFind(firstContributor, "RangeComp") >= 0) stratCode = "RC";
            else if(StringFind(firstContributor, "Neural") >= 0 || StringFind(firstContributor, "NN") >= 0) stratCode = "NNET";
            else if(StringFind(firstContributor, "Transformer") >= 0) stratCode = "TRAN";
            else if(StringFind(firstContributor, "Ensemble") >= 0) stratCode = "ENS";
            else if(StringFind(firstContributor, "ONNX") >= 0) stratCode = "ONNX";
            else if(StringFind(firstContributor, "Python") >= 0) stratCode = "PY";
            else if(StringFind(firstContributor, "Scalp") >= 0) stratCode = "SCLP";
            else if(StringFind(firstContributor, "Spike") >= 0) stratCode = "SPK";
            else if(StringFind(firstContributor, "Grid") >= 0) stratCode = "GRID";
        }
        
        string baseComment = StringFormat("EA|%s|%.0f|%.1f|%.1f|%s|%s|%s", 
                                    candidate.clusterCode,
                                    candidate.riskPercent,
                                    candidate.stopLossPips,
                                    candidate.takeProfitPips,
                                    candidate.strategyRole,
                                    cidShort,
                                    stratCode);
        
        // Include prediction ID in comment for NN training linkage (L11-014)
        if(candidate.predictionId != "" && m_attributionManager != NULL)
        {
            return m_attributionManager.BuildTradeCommentWithPrediction(baseComment, candidate.predictionId);
        }
        
        return baseComment;
    }
    
    string GetTradeErrorDescription(int errorCode)
    {
        // Batch 152 (T-11): this table used invented retcode mappings (e.g. 10008
        // PLACED labeled "Invalid volume", 10009 DONE labeled "Market closed"),
        // poisoning rejection reasons. Delegate to the authoritative descriptor.
        return CTradeDescriptor::GetTradeErrorDescription(errorCode);
    }
};

#endif // CORE_ORCHESTRATION_TRADE_EXECUTOR_MQH