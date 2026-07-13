//+------------------------------------------------------------------+
//| TradeExecutor.mqh                                                |
//| Executes trades with proper confirmation and attribution         |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_ORCHESTRATION_TRADE_EXECUTOR_MQH
#define CORE_ORCHESTRATION_TRADE_EXECUTOR_MQH

#include "../../Core/Trading/TradeManager.mqh"
#include "../../Core/Trading/TradeAttributionManager.mqh"
#include "../../Core/Trading/PositionStateManager.mqh"
#include "../../Core/Registry/NeuralNetRegistry.mqh"
#include "../../Core/Orchestration/CandidateBuilder.mqh"
#include "../../Core/Utils/Enums.mqh"
#include <Trade\Trade.mqh>

class CTradeExecutor
{
private:
    CTradeManager* m_tradeManager;
    CTradeAttributionManager* m_attributionManager;
    CPositionStateManager* m_positionStateManager;
    CNeuralNetRegistry* m_neuralNetRegistry;
    
// Pending confirmations
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
    
    // Statistics
    ulong m_totalSubmitted;
    ulong m_totalConfirmed;
    ulong m_totalRejected;
    ulong m_totalTimeout;

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
    
    CTradeExecutor() : m_tradeManager(NULL), m_attributionManager(NULL), m_positionStateManager(NULL),
                       m_neuralNetRegistry(NULL), m_pendingCount(0), m_maxPending(50), m_totalSubmitted(0), m_totalConfirmed(0),
                       m_totalRejected(0), m_totalTimeout(0)
    {
        ArrayResize(m_pendingConfirmations, m_maxPending);
    }
    
    ~CTradeExecutor() {}
    
    void SetDependencies(CTradeManager* tm, CTradeAttributionManager* att, 
                         CPositionStateManager* psm, CNeuralNetRegistry* nnReg)
    {
        m_tradeManager = tm;
        m_attributionManager = att;
        m_positionStateManager = psm;
        m_neuralNetRegistry = nnReg;
    }
    
    // Main execution entry point
    SExecutionResult Execute(const STradeCandidate &candidate)
    {
        SExecutionResult result;
        
        if(candidate.lotSize <= 0)
        {
            result.reason = "Invalid lot size";
            return result;
        }
        
        // Build comment with metadata
        string comment = BuildExecutionComment(candidate);
        
        // Execute market order
        bool executed = m_tradeManager.ExecuteMarketOrder(
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
            m_totalRejected++;
            result.retcode = m_tradeManager.GetLastRetcode();
            result.reason = GetTradeErrorDescription(m_tradeManager.GetLastRetcode());
            PrintFormat("[EXECUTION-FAILED] %s | %s | retcode=%u | reason=%s",
                        candidate.symbol, EnumToString(candidate.orderType), result.retcode, result.reason);
            return result;
        }
        
        m_totalSubmitted++;
        result.executed = true;
        
        STradeExecutionReceipt receipt;
        m_tradeManager.GetLastExecutionReceipt(receipt);
        result.orderTicket = receipt.orderTicket;
        result.dealTicket = receipt.dealTicket;
        result.filledPrice = receipt.averagePrice;
        result.filledVolume = receipt.filledVolume;
        result.retcode = receipt.retcode;
        
        // Queue for confirmation
        QueueConfirmation(candidate, result);
        
        return result;
    }
    
    // Execute multiple candidates (ranked by quality)
    void ExecuteBatch(const STradeCandidate &candidates[], int count, int maxSends)
    {
        int sent = 0;
        for(int i = 0; i < count && sent < maxSends; i++)
        {
            SExecutionResult result = Execute(candidates[i]);
            if(result.executed)
            {
                sent++;
                PrintFormat("[EXECUTION] %s | %s | lot=%.2f | ticket=%I64u | deal=%I64u | price=%.5f",
                            candidates[i].symbol,
                            EnumToString(candidates[i].orderType),
                            candidates[i].lotSize,
                            result.orderTicket,
                            result.dealTicket,
                            result.filledPrice);
            }
        }
    }
    
    // Check pending confirmations (call from OnTick)
    void CheckPendingConfirmations()
    {
        if(m_pendingCount <= 0) return;
        
        datetime historyFrom = TimeCurrent() - 300;
        datetime historyTo = TimeCurrent() + 60;
                        {
                            double dealPrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
                            double dealVolume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
                            ENUM_DEAL_TYPE dealType = (ENUM_DEAL_TYPE)HistoryDealGetInteger(dealTicket, DEAL_TYPE);
                            
                            PrintFormat("[EXECUTION-CONFIRMED] %s | order=%I64u | deal=%I64u | price=%.5f | volume=%.2f | type=%s | attempts=%d",
                                        dealSymbol, m_pendingConfirmations[i].orderTicket, dealTicket,
                                        dealPrice, dealVolume, EnumToString(dealType), m_pendingConfirmations[i].checkAttempts);
                            
                            // Record attribution
                            RecordAttribution(m_pendingConfirmations[i].candidate, dealTicket, dealPrice, dealVolume);
                            
                            // Record position state
                            RecordPositionState(dealTicket, m_pendingConfirmations[i].candidate, dealPrice, dealVolume);
                            
                            // Map to NN prediction
                            MapToNeuralNetPrediction(m_pendingConfirmations[i].candidate, dealTicket);
                            
                            resolved = true;
                            m_totalConfirmed++;
                            break;
                        }
                    }
                }
            }
            
            if(resolved || m_pendingConfirmations[i].checkAttempts >= 5)
            {
                if(!resolved)
                {
                    PrintFormat("[EXECUTION-TIMEOUT] %s | order=%I64u | attempts=%d | no deal found",
                                m_pendingConfirmations[i].symbol, m_pendingConfirmations[i].orderTicket,
                                m_pendingConfirmations[i].checkAttempts);
                    m_totalTimeout++;
                }
                
                // Remove from pending
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
        
        string contributors[];
        if(candidate.contributorSummary != "")
        {
            // Parse contributor summary
            // In real implementation, would split by comma
            ArrayResize(contributors, 1);
            contributors[0] = candidate.contributorSummary;
        }
        
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
        if(m_positionStateManager == NULL) return;
        
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
            m_positionStateManager.RegisterPosition(
                positionTicket,
                candidate.symbol,
                candidate.orderType,
                volume,
                price,
                candidate.stopLossPips,
                candidate.takeProfitPips,
                candidate.clusterCode,
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
    
    string BuildExecutionComment(const STradeCandidate &candidate)
    {
        return StringFormat("EA|%s|%.0f|%.1f|%.1f|%s", 
                            candidate.clusterCode,
                            candidate.riskPercent,
                            candidate.stopLossPips,
                            candidate.takeProfitPips,
                            candidate.strategyRole);
    }
    
    string GetTradeErrorDescription(int errorCode)
    {
        switch(errorCode)
        {
            case 10004: return "Requote";
            case 10005: return "Price off";
            case 10006: return "Invalid price";
            case 10007: return "Invalid stops";
            case 10008: return "Invalid volume";
            case 10009: return "Market closed";
            case 10010: return "Insufficient funds";
            case 10011: return "Price changed";
            case 10012: return "Off quotes";
            case 10013: return "Invalid expiration";
            case 10014: return "Order changed";
            case 10015: return "Too many requests";
            case 10016: return "Trade disabled";
            case 10017: return "Trade timeout";
            case 10018: return "Order locked";
            case 10019: return "Order frozen";
            case 10020: return "Invalid fill";
            case 10021: return "Connection error";
            case 10022: return "Deadline exceeded";
            default: return "Error " + IntegerToString(errorCode);
        }
    }
    
    // Diagnostics
    string GetStatusReport() const
    {
        string report = "[TradeExecutor] ";
        report += "Pending=" + IntegerToString(m_pendingCount);
        report += " | Submitted=" + IntegerToString(m_totalSubmitted);
        report += " | Confirmed=" + IntegerToString(m_totalConfirmed);
        report += " | Rejected=" + IntegerToString(m_totalRejected);
        report += " | Timeout=" + IntegerToString(m_totalTimeout);
        return report;
    }
};

#endif // CORE_ORCHESTRATION_TRADE_EXECUTOR_MQH