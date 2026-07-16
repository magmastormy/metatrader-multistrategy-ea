//+------------------------------------------------------------------+
//| SignalGenerator.mqh                                              |
//| Generates consensus signals per symbol                           |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_ORCHESTRATION_SIGNAL_GENERATOR_MQH
#define CORE_ORCHESTRATION_SIGNAL_GENERATOR_MQH

#include "../../Interfaces/IStrategy.mqh"
#include "../../Core/Management/EnterpriseStrategyManager.mqh"
#include "../../Core/Cache/ConsensusCache.mqh"
#include "../../Core/Utils/Enums.mqh"

class CSignalGenerator
{
private:
    CEnterpriseStrategyManager* m_managers[];
    string m_symbols[];
    int m_managerCount;
    CConsensusCache* m_consensusCache;
    
    // Throttling
    datetime m_lastSignalEvalSecond;
    int m_evalBudgetPerCycle;
    int m_intrabarBudgetPerCycle;
    
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
    
    CSignalGenerator() : m_managerCount(0), m_consensusCache(NULL), m_lastSignalEvalSecond(0),
                         m_evalBudgetPerCycle(8), m_intrabarBudgetPerCycle(3), m_dormantCount(0)
    {}
    
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
        Print("[SignalGenerator] Initialized with ", count, " symbol managers");
    }
    
    void SetEvalBudget(int newBarBudget, int intrabarBudget)
    {
        m_evalBudgetPerCycle = MathMax(1, newBarBudget);
        m_intrabarBudgetPerCycle = MathMax(1, intrabarBudget);
    }
    
    // Main signal generation entry point
    bool GenerateSignals(ENUM_SIGNAL_EVAL_MODE evalMode, SSignalResult &results[])
    {
        datetime now = TimeCurrent();
        
        // Throttle: max once per second
        if(m_lastSignalEvalSecond == now)
            return false;
        m_lastSignalEvalSecond = now;
        
        ArrayResize(results, m_managerCount);
        int signalsGenerated = 0;
        int newBarCount = 0;
        int intrabarCount = 0;
        
        // Count pending new-bar scans
        for(int i = 0; i < m_managerCount; i++)
        {
            if(evalMode == EVAL_MODE_NEW_BAR)
                newBarCount++;
            else
                intrabarCount++;
        }
        
        int evalBudget = (evalMode == EVAL_MODE_NEW_BAR) ? m_evalBudgetPerCycle : m_intrabarBudgetPerCycle;
        int selectedCount = 0;
        
        // Select symbols to evaluate (rotation + priority)
        bool selected[];
        ArrayResize(selected, m_managerCount);
        ArrayInitialize(selected, false);
        
        // For new bar: prioritize symbols with pending new bars
        // For intrabar: prioritize by score
        SelectSymbolsForEval(evalMode, evalBudget, selected, selectedCount);
        
        for(int i = 0; i < m_managerCount && signalsGenerated < evalBudget; i++)
        {
            if(!selected[i]) continue;
            
            string symbol = m_symbols[i];
            CEnterpriseStrategyManager* manager = m_managers[i];
            if(manager == NULL) continue;
            
            // Check dormancy
            if(IsInDormantCooldown(symbol))
                continue;
            
            // Get signal
            double confidence = 0;
            int confluence = 0;
            SConsensusDecisionContext ctx;
            
            ENUM_TRADE_SIGNAL signal = manager.GetConsensusSignalForSymbolWithConfluenceMode(
                symbol, confidence, confluence, evalMode);
            
            manager.GetLastDecisionContext(ctx);
            
            bool valid = (signal != TRADE_SIGNAL_NONE);
            string vetoReason = "";
            
            if(!valid)
            {
                vetoReason = ctx.vetoCode;
                // Record dormancy warning
                RecordDormancyWarning(symbol);
            }
            else
            {
                ClearDormancyWarning(symbol);
            }
            
            results[i].signal = signal;
            results[i].confidence = confidence;
            results[i].confluence = confluence;
            results[i].decisionContext = ctx;
            results[i].valid = valid;
            results[i].vetoReason = vetoReason;
            
            // Cache for SRE
            if(m_consensusCache != NULL)
            {
                m_consensusCache.Store(symbol, evalMode, signal, confidence, confluence);
            }
            
            if(valid) signalsGenerated++;
        }
        
        // Log scan budget stats
        static datetime s_lastBudgetLog = 0;
        if(TimeCurrent() - s_lastBudgetLog >= 60)
        {
            PrintFormat("[SCAN-BUDGET] mode=%s | evalBudget=%d | signalsGenerated=%d | newBarCount=%d | intrabarCount=%d",
                       (evalMode == EVAL_MODE_NEW_BAR) ? "NEW_BAR" : "INTRABAR",
                       evalBudget, signalsGenerated, newBarCount, intrabarCount);
            s_lastBudgetLog = TimeCurrent();
        }
        
        return signalsGenerated > 0;
    }
    
    void SelectSymbolsForEval(ENUM_SIGNAL_EVAL_MODE evalMode, int budget, bool &selected[], int &selectedCount)
    {
        selectedCount = 0;
        
        if(evalMode == EVAL_MODE_NEW_BAR)
        {
            // New bar: evaluate all symbols with pending new bars
            for(int i = 0; i < m_managerCount && selectedCount < budget; i++)
            {
                // In real implementation, would check scan scheduler for pending new bar
                selected[i] = true;
                selectedCount++;
            }
        }
        else
        {
            // Intrabar: score and pick top symbols
            // For simplicity, just pick first N symbols
            for(int i = 0; i < m_managerCount && selectedCount < budget; i++)
            {
                selected[i] = true;
                selectedCount++;
            }
        }
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
    
    // Diagnostics
    string GetStatusReport() const
    {
        string report = "[SignalGenerator] Managers: " + IntegerToString(m_managerCount);
        report += " | Dormant symbols: " + IntegerToString(m_dormantCount) + "\n";
        for(int i = 0; i < m_dormantCount; i++)
        {
            if(m_dormantWarningCount[i] > 0)
            {
                report += "  " + m_dormantSymbols[i] + ": warnings=" + IntegerToString(m_dormantWarningCount[i]);
                if(m_dormantCooldownUntil[i] > TimeCurrent())
                    report += " COOLDOWN";
                report += "\n";
            }
        }
        return report;
    }
};

#endif // CORE_ORCHESTRATION_SIGNAL_GENERATOR_MQH