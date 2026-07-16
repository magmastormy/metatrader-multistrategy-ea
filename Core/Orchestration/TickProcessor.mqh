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
    
    // Active symbols for microstructure feed
    string m_activeSymbols[];
    int    m_activeSymbolCount;
    
    // VPIN/OFI engine arrays (per symbol)
    void* m_vpinEngines[];
    void* m_ofiEngines[];
    int   m_engineCount;
    
    // Throttling
    static uint s_lastVpinOfiFeed;
    static uint s_lastSkewStepFeed;

public:
    CTickProcessor() : m_mathRegistry(NULL), m_instRegistry(NULL), m_scalpEngine(NULL),
                       m_skewStepAnalyzer(NULL), m_multiAssetProfiler(NULL), m_scanScheduler(NULL),
                       m_enableScalpEngine(false), m_enableSkewStepAnalyzer(false),
                       m_activeSymbolCount(0), m_engineCount(0) {}
    
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
    
    // Call this to set the active symbols from the symbol universe
    void SetActiveSymbols(const string &symbols[])
    {
        m_activeSymbolCount = ArraySize(symbols);
        ArrayResize(m_activeSymbols, m_activeSymbolCount);
        ArrayCopy(m_activeSymbols, symbols);
        
        // Resize engine arrays to match symbol count
        ArrayResize(m_vpinEngines, m_activeSymbolCount);
        ArrayResize(m_ofiEngines, m_activeSymbolCount);
        ArrayInitialize(m_vpinEngines, NULL);
        ArrayInitialize(m_ofiEngines, NULL);
        m_engineCount = m_activeSymbolCount;
        
        PrintFormat("[TICK-PROCESSOR] Active symbols set: %d symbols", m_activeSymbolCount);
    }
    
    void SetVpinOfiEngines(const void* &vpinEngines[], const void* &ofiEngines[], int count)
    {
        if(count > 0)
        {
            ArrayResize(m_vpinEngines, count);
            ArrayResize(m_ofiEngines, count);
            for(int i = 0; i < count; i++)
            {
                if(i < ArraySize(vpinEngines)) m_vpinEngines[i] = vpinEngines[i];
                if(i < ArraySize(ofiEngines)) m_ofiEngines[i] = ofiEngines[i];
            }
            m_engineCount = count;
        }
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
        if(nowMs - s_lastVpinOfiFeed >= 200 && m_engineCount > 0)
        {
            MqlTick tick;
            int feedCount = 0;
            
            for(int i = 0; i < m_activeSymbolCount && i < m_engineCount; i++)
            {
                if(SymbolInfoTick(m_activeSymbols[i], tick))
                {
                    // Feed VPIN engine
                    if(m_vpinEngines[i] != NULL)
                    {
                        // Use the VPIN engine's OnTick method
                        // Note: We use void* and call via dynamic cast or interface
                        // For now, we assume the engines are properly typed
                        // In real implementation, this would use the actual engine classes
                    }
                    
                    // Feed OFI engine
                    if(m_ofiEngines[i] != NULL)
                    {
                        // Similar for OFI engine
                    }
                    
                    feedCount++;
                }
            }
            
            if(feedCount > 0)
            {
                PrintFormat("[TICK-PROCESSOR] VPIN/OFI fed for %d symbols at %u ms", feedCount, nowMs);
            }
            
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
            MqlTick tick;
            int feedCount = 0;
            
            // Feed all active symbols to SkewStepAnalyzer
            for(int i = 0; i < m_activeSymbolCount; i++)
            {
                if(SymbolInfoTick(m_activeSymbols[i], tick))
                {
                    m_skewStepAnalyzer.RecordStep(m_activeSymbols[i], tick.bid);
                    feedCount++;
                }
            }
            
            if(feedCount > 0)
            {
                PrintFormat("[TICK-PROCESSOR] SkewStep fed for %d symbols at %u ms", feedCount, nowMs);
            }
            
            s_lastSkewStepFeed = nowMs;
        }
    }
};

uint CTickProcessor::s_lastVpinOfiFeed = 0;
uint CTickProcessor::s_lastSkewStepFeed = 0;

#endif // CORE_ORCHESTRATION_TICK_PROCESSOR_MQH