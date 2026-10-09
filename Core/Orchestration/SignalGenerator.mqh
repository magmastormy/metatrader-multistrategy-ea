// Generates consensus signals per symbol
#property strict

#ifndef CORE_ORCHESTRATION_SIGNAL_GENERATOR_MQH
#define CORE_ORCHESTRATION_SIGNAL_GENERATOR_MQH

#include "../../Interfaces/IStrategy.mqh"
#include "../../Core/Management/EnterpriseStrategyManager.mqh"
#include "../../Core/Cache/ConsensusCache.mqh"
#include "../../Core/Utils/Enums.mqh"
#include "../../Core/Utils/JsonLogger.mqh"

class CSignalGenerator
{
private:
    CEnterpriseStrategyManager* m_managers[];
    string m_symbols[];
    int m_managerCount;
    CConsensusCache* m_consensusCache;

    // Evaluation budget (per cycle limits)
    int m_evalBudgetPerCycle;
    int m_intrabarBudgetPerCycle;
    
    // Pending symbols queue (when budget exceeded)
    string m_pendingSymbols[];
    int m_pendingCount;
    
    // L12-013: Fair rotation index for signal evaluation budget
    int m_evalStartIndex;

    // Last evaluated bar time per manager index (new-bar cadence gate)
    datetime m_lastEvalBar[];

    // Dormancy tracking
    enum
    {
        DORMANT_THRESHOLD = 3,
        DORMANT_COOLDOWN_MIN = 30
    };
    int m_dormantWarningCount[];
    datetime m_dormantCooldownUntil[];
    string m_dormantSymbols[];
    int m_dormantCount;

public:
    struct SSignalResult
    {
        ENUM_TRADE_SIGNAL signal;
        double confidence;
        int confluence;
        SConsensusDecisionContext decisionContext;
        bool valid;
        string vetoReason;
        
        SSignalResult() : signal(TRADE_SIGNAL_NONE), confidence(0), confluence(0), valid(false) {}
    };
    
    CSignalGenerator() : m_managerCount(0), m_consensusCache(NULL),
                             m_evalBudgetPerCycle(8), m_intrabarBudgetPerCycle(3),
                             m_pendingCount(0), m_dormantCount(0), m_evalStartIndex(0)
        {
        }
    
    ~CSignalGenerator() {}
    
    void Initialize(CEnterpriseStrategyManager* &managers[], string &symbols[], int count, CConsensusCache* cache)
    {
        m_managerCount = count;
        ArrayResize(m_managers, count);
        ArrayResize(m_symbols, count);
        for(int i = 0; i < count; i++)
        {
            m_managers[i] = managers[i];
            m_symbols[i] = symbols[i];
        }
        m_consensusCache = cache;
        ArrayResize(m_lastEvalBar, count);
        ArrayInitialize(m_lastEvalBar, 0);
        ArrayResize(m_pendingSymbols, count);
        Print("[SignalGenerator] Initialized with ", count, " symbol managers");
    }
    
    // Batch 153: SetEvalBudget removed - zero callers; the eval budget is
    // config-driven only (see m_evalBudgetPerCycle initialiser).

    // Main signal generation entry point
                bool GenerateSignals(ENUM_SIGNAL_EVAL_MODE evalMode, SSignalResult &results[], const string corrId = "")
                {
                    ulong startTime = GetMicrosecondCount();
                    datetime now = TimeCurrent();

                // Periodic dormancy array compaction (every 60s)
                    static datetime s_lastDormantCompact = 0;
                    if(now - s_lastDormantCompact >= 60)
                    {
                        CompactDormantEntries();
                        s_lastDormantCompact = now;
                    }
                
                    // Batch 151: removed decorative throttles (token bucket never
                    // decremented, sliding window wrote a single fixed slot,
                    // concurrency counter peaked at 1 in this single-threaded loop).
                    // The per-cycle eval budget below is the real limiter.

                ArrayResize(results, m_managerCount);
                int signalsGenerated = 0;
                int evaluationsUsed = 0;

                int evalBudget = (evalMode == EVAL_MODE_NEW_BAR) ? m_evalBudgetPerCycle : m_intrabarBudgetPerCycle;
                int selectedCount = 0;

                // Select symbols to evaluate (rotation + priority)
                bool selected[];
                ArrayResize(selected, m_managerCount);
                ArrayInitialize(selected, false);

                // For new bar: prioritize symbols with pending new bars
                // For intrabar: prioritize by score
                SelectSymbolsForEval(evalMode, evalBudget, selected, selectedCount);

                // Process pending symbols first (from previous budget overflow)
                for(int pi = 0; pi < m_pendingCount && evaluationsUsed < evalBudget; pi++)
                {
                    string pendingSymbol = m_pendingSymbols[pi];
                    int managerIdx = FindManagerIndex(pendingSymbol);
                    if(managerIdx >= 0 && selected[managerIdx])
                    {
                        // This pending symbol was already selected, skip duplicate
                        continue;
                    }

                    // Try to evaluate this pending symbol
                    if(managerIdx >= 0)
                    {
                        CEnterpriseStrategyManager* manager = m_managers[managerIdx];
                        if(manager != NULL && !IsInDormantCooldown(pendingSymbol))
                        {
                            EvaluateSymbol(managerIdx, manager, evalMode, results, signalsGenerated, evaluationsUsed, corrId);
                        }
                    }
                }

                // Clear pending list after processing
                m_pendingCount = 0;

                // Process newly selected symbols
                for(int i = 0; i < m_managerCount && evaluationsUsed < evalBudget; i++)
                {
                    if(!selected[i]) continue;

                    CEnterpriseStrategyManager* manager = m_managers[i];
                    if(manager == NULL) continue;

                    // Check dormancy
                    if(IsInDormantCooldown(m_symbols[i]))
                        continue;

                    EvaluateSymbol(i, manager, evalMode, results, signalsGenerated, evaluationsUsed, corrId);
                }
        
                // If we couldn't process all selected symbols due to budget, queue them
                // Batch 152 (ORCH-07): the processing loops above bound work by
                // evaluationsUsed, and signalsGenerated <= evaluationsUsed always -
                // gating requeue on signalsGenerated let starved symbols fall
                // through without being queued for the next cycle.
                for(int i = 0; i < m_managerCount; i++)
                {
                    if(selected[i] && evaluationsUsed >= evalBudget)
                    {
                        if(m_pendingCount < ArraySize(m_pendingSymbols))
                        {
                            m_pendingSymbols[m_pendingCount] = m_symbols[i];
                            m_pendingCount++;
                        }
                    }
                }
        
                // Performance timing log
                                        ulong elapsed = GetMicrosecondCount() - startTime;
                                        CJsonLogger::LogPerformance("SignalGenerator", "GenerateSignals_us", (double)elapsed, corrId);
        
                // Log scan budget stats
                static datetime s_lastBudgetLog = 0;
                if(TimeCurrent() - s_lastBudgetLog >= 60)
                {
                    PrintFormat("[SCAN-BUDGET] mode=%s | evalBudget=%d | evaluations=%d | signalsGenerated=%d | pending=%d",
                               (evalMode == EVAL_MODE_NEW_BAR) ? "NEW_BAR" : "INTRABAR",
                               evalBudget, evaluationsUsed, signalsGenerated, m_pendingCount);
                    s_lastBudgetLog = TimeCurrent();
                }
        
                return signalsGenerated > 0;
            }
    
    void SelectSymbolsForEval(ENUM_SIGNAL_EVAL_MODE evalMode, int budget, bool &selected[], int &selectedCount)
        {
            selectedCount = 0;
        
            // L12-013: Fair rotation - start from m_evalStartIndex and wrap around
            int startIdx = m_evalStartIndex;
        
            if(evalMode == EVAL_MODE_NEW_BAR)
            {
                // New bar: evaluate all symbols with pending new bars
                // Use rotation to ensure fair distribution
                int count = 0;
                for(int i = 0; i < m_managerCount && count < budget; i++)
                {
                    int idx = (startIdx + i) % m_managerCount;
                    selected[idx] = true;
                    selectedCount++;
                    count++;
                }
            }
            else
            {
                // Intrabar: score and pick top symbols
                // For fairness, still use rotation as base
                int count = 0;
                for(int i = 0; i < m_managerCount && count < budget; i++)
                {
                    int idx = (startIdx + i) % m_managerCount;
                    selected[idx] = true;
                    selectedCount++;
                    count++;
                }
            }
        
            // Advance rotation index for next cycle
            m_evalStartIndex = (m_evalStartIndex + budget) % m_managerCount;
        }
    
    // Dormancy tracking
    void RecordDormancyWarning(const string symbol)
    {
        int idx = FindDormantIndex(symbol);
        if(idx < 0)
        {
            idx = m_dormantCount;
            ArrayResize(m_dormantSymbols, idx + 1);
            ArrayResize(m_dormantWarningCount, idx + 1);
            ArrayResize(m_dormantCooldownUntil, idx + 1);
            m_dormantSymbols[idx] = symbol;
            m_dormantWarningCount[idx] = 0;
            m_dormantCooldownUntil[idx] = 0;
            m_dormantCount++;
        }
        
        m_dormantWarningCount[idx]++;
        if(m_dormantWarningCount[idx] >= DORMANT_THRESHOLD)
        {
            m_dormantCooldownUntil[idx] = TimeCurrent() + DORMANT_COOLDOWN_MIN * 60;
            PrintFormat("[DORMANT-COOLDOWN] %s | %d consecutive no-signal cycles | cooling down %d min",
                        symbol, m_dormantWarningCount[idx], DORMANT_COOLDOWN_MIN);
        }
    }
    
    void ClearDormancyWarning(const string symbol)
    {
        int idx = FindDormantIndex(symbol);
        if(idx >= 0)
        {
            m_dormantWarningCount[idx] = 0;
            m_dormantCooldownUntil[idx] = 0;
            // Remove entry entirely to prevent unbounded array growth
            RemoveDormantEntry(symbol);
        }
    }
    
    // Periodic compact: remove stale dormancy entries past cooldown
    void CompactDormantEntries()
    {
        datetime now = TimeCurrent();
        for(int i = m_dormantCount - 1; i >= 0; i--)
        {
            if(m_dormantCooldownUntil[i] > 0 && now > m_dormantCooldownUntil[i] + DORMANT_COOLDOWN_MIN * 120)
            {
                RemoveDormantEntry(m_dormantSymbols[i]);
            }
        }
    }
    
    bool IsInDormantCooldown(const string symbol)
    {
        int idx = FindDormantIndex(symbol);
        if(idx < 0) return false;
        if(m_dormantCooldownUntil[idx] <= 0) return false;
        return TimeCurrent() < m_dormantCooldownUntil[idx];
    }
    
    int FindDormantIndex(const string symbol)
    {
        for(int i = 0; i < m_dormantCount; i++)
            if(m_dormantSymbols[i] == symbol) return i;
        return -1;
    }
    
    // Remove a dormant symbol entry completely
    void RemoveDormantEntry(const string symbol)
    {
        int idx = FindDormantIndex(symbol);
        if(idx < 0) return;
        
        // Shift remaining elements
        for(int i = idx; i < m_dormantCount - 1; i++)
        {
            m_dormantSymbols[i] = m_dormantSymbols[i + 1];
            m_dormantWarningCount[i] = m_dormantWarningCount[i + 1];
            m_dormantCooldownUntil[i] = m_dormantCooldownUntil[i + 1];
        }
        
        // Resize arrays
        m_dormantCount--;
        if(m_dormantCount > 0)
        {
            ArrayResize(m_dormantSymbols, m_dormantCount);
            ArrayResize(m_dormantWarningCount, m_dormantCount);
            ArrayResize(m_dormantCooldownUntil, m_dormantCount);
        }
        else
        {
            ArrayFree(m_dormantSymbols);
            ArrayFree(m_dormantWarningCount);
            ArrayFree(m_dormantCooldownUntil);
        }
        
        PrintFormat("[DORMANT-REMOVED] %s | entry removed from tracking", symbol);
    }
    
    // Get funnel metrics from all managers
    void GetAggregateFunnel(ulong &signalsGenerated, ulong &afterPipeline, ulong &afterQuorum)
    {
        signalsGenerated = 0;
        afterPipeline = 0;
        afterQuorum = 0;
        
        for(int i = 0; i < m_managerCount; i++)
        {
            if(m_managers[i] != NULL)
            {
                int gen, pipe;
                bool quorum;
                m_managers[i].GetLastCycleFunnel(gen, pipe, quorum);
                signalsGenerated += gen;
                afterPipeline += pipe;
                if(quorum) afterQuorum++;
            }
        }
    }
    
        int FindManagerIndex(const string symbol) const
        {
            for(int i = 0; i < m_managerCount; i++)
            {
                if(m_symbols[i] == symbol)
                    return i;
            }
            return -1;
        }

        // Evaluate a single symbol: consensus -> validation -> candidate building
        // Results are written into results[managerIdx] so the consumer's index-by-manager
        // pairing stays correct; signalsGenerated only counts non-empty slots.
        void EvaluateSymbol(const int managerIdx, CEnterpriseStrategyManager* manager, ENUM_SIGNAL_EVAL_MODE evalMode, SSignalResult &results[], int &signalsGenerated, int &evaluationsUsed, const string corrId = "")
        {
            string symbol = m_symbols[managerIdx];
            if(managerIdx < 0 || managerIdx >= ArraySize(results)) return;

            // New-bar mode: evaluate a symbol at most once per bar of its chart timeframe.
            // Without this gate the 1s cadence re-evaluates unchanged bars and the
            // dormancy tracker blacklists quiet symbols within seconds.
            if(evalMode == EVAL_MODE_NEW_BAR)
            {
                datetime barTime = iTime(symbol, (ENUM_TIMEFRAMES)Period(), 0);
                if(barTime <= 0 || barTime == m_lastEvalBar[managerIdx]) return;
                m_lastEvalBar[managerIdx] = barTime;
            }
            evaluationsUsed++;

            double confidence = 0.0;
            int confluence = 0;

            ENUM_TRADE_SIGNAL signal = manager.GetConsensusSignalForSymbolWithConfluenceMode(symbol, confidence, confluence, evalMode);

            if(signal == TRADE_SIGNAL_NONE)
            {
                // No signal - record dormancy if enabled
                RecordDormancyWarning(symbol);
                return;
            }

            // Clear dormancy warning on valid signal
            ClearDormancyWarning(symbol);

            // Get decision context for validation
            SConsensusDecisionContext ctx;
            manager.GetLastDecisionContext(ctx);

            // Validation is performed in EAOrchestrator using EnterpriseStrategyManager's ValidateSignal()
            results[managerIdx].signal = signal;
            results[managerIdx].confidence = confidence;
            results[managerIdx].confluence = confluence;
            results[managerIdx].decisionContext = ctx;
            results[managerIdx].valid = true;
            results[managerIdx].vetoReason = "";
            signalsGenerated++;
        }

        // Batch 153: GetLastDecisionContextFromManager removed - zero callers;
        // EvaluateSymbol calls manager.GetLastDecisionContext() directly.

    };

#endif // CORE_ORCHESTRATION_SIGNAL_GENERATOR_MQH