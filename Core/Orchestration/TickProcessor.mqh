//+------------------------------------------------------------------+
//| TickProcessor.mqh                                                |
//| Fast-path tick processing                                        |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_ORCHESTRATION_TICK_PROCESSOR_MQH
#define CORE_ORCHESTRATION_TICK_PROCESSOR_MQH

#include "../../Core/Registry/MathematicalEngineRegistry.mqh"
#include "../../Core/Registry/InstitutionalEngineRegistry.mqh"
#include "../../Core/Scalp/FastScalpEngine.mqh"
#include "../../Core/Engines/SkewStepAnalyzer.mqh"
#include "../../Core/Processing/DerivAssetProfiler.mqh"
#include "../../Core/Processing/MultiAssetProfiler.mqh"

class CTickProcessor
{
private:
    CMathematicalEngineRegistry*  m_mathRegistry;
    CInstitutionalEngineRegistry* m_instRegistry;
    CFastScalpEngine*             m_scalpEngine;
    CSkewStepAnalyzer*            m_skewStepAnalyzer;
    CMultiAssetProfiler*          m_multiAssetProfiler;
    CSymbolScanScheduler*         m_scanScheduler;
    
    bool m_enableScalpEngine;
    bool m_enableSkewStepAnalyzer;
    
    // Throttling
    static uint s_lastVpinOfiFeed;
    static uint s_lastSkewStepFeed;

public:
    CTickProcessor() : m_mathRegistry(NULL), m_instRegistry(NULL), m_scalpEngine(NULL),
                       m_skewStepAnalyzer(NULL), m_multiAssetProfiler(NULL), m_scanScheduler(NULL),
                       m_enableScalpEngine(false), m_enableSkewStepAnalyzer(false) {}
    
    ~CTickProcessor() {}
    
    void SetDependencies(CMathematicalEngineRegistry* mathReg, CInstitutionalEngineRegistry* instReg,
                         CFastScalpEngine* scalpEngine, CSkewStepAnalyzer* skewStepAnalyzer,
                         CMultiAssetProfiler* multiAssetProfiler, CSymbolScanScheduler* scanScheduler)
    {
        m_mathRegistry = mathReg;
        m_instRegistry = instReg;
        m_scalpEngine = scalpEngine;
        m_skewStepAnalyzer = skewStepAnalyzer;
        m_multiAssetProfiler = multiAssetProfiler;
        m_scanScheduler = scanScheduler;
    }
    
    void Configure(bool enableScalp, bool enableSkewStep)
    {
        m_enableScalpEngine = enableScalp;
        m_enableSkewStepAnalyzer = enableSkewStep;
    }
    
    void OnTick()
    {
        // Feed microstructure engines (VPIN, OFI) - throttled to 200ms
        FeedVpinOfiEngines();
        
        // Feed Skew Step Analyzer - throttled to 500ms
        FeedSkewStepAnalyzer();
        
        // Fast-path scalp signal evaluation
        if(m_enableScalpEngine && m_scalpEngine != NULL && m_scalpEngine.IsInitialized())
        {
            // m_scalpEngine.ProcessScalpFastPath();
        }
    }
    
    void FeedVpinOfiEngines()
    {
        uint nowMs = GetTickCount();
        if(nowMs - s_lastVpinOfiFeed >= 200)
        {
            // In real implementation, would iterate over active symbols
            // For now, placeholder
            s_lastVpinOfiFeed = nowMs;
        }
    }
    
    void FeedSkewStepAnalyzer()
    {
        if(!m_enableSkewStepAnalyzer || m_skewStepAnalyzer == NULL || !m_skewStepAnalyzer.IsInitialized())
            return;
        
        uint nowMs = GetTickCount();
        if(nowMs - s_lastSkewStepFeed >= 500)
        {
            // Would iterate over Skew Step symbols and record step sizes
            s_lastSkewStepFeed = nowMs;
        }
    }
};

uint CTickProcessor::s_lastVpinOfiFeed = 0;
uint CTickProcessor::s_lastSkewStepFeed = 0;

#endif // CORE_ORCHESTRATION_TICK_PROCESSOR_MQH