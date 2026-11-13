// Per-symbol math engine fleet plus the m_mathEngineCount cursor.
// Collaborators the engines need (config, registries, enterprise managers, grid
// recovery, signal diagnostics) are explicit parameters, not members.
// Ownership: the hub OWNS every engine pointer it allocates and releases them in
// ReleaseAll() with Deinit()+delete ordering. The math registry holds the same pointers and
// deletes them only if CheckPointer still answers POINTER_DYNAMIC, so ReleaseAll must run first.
// One creation path only: CreateEnginesForSymbol, called per symbol by the orchestrator.
#property strict

#ifndef CORE_ORCHESTRATION_ORCHESTRATOR_MATH_ENGINE_HUB_MQH
#define CORE_ORCHESTRATION_ORCHESTRATOR_MATH_ENGINE_HUB_MQH

#include "../Utils/EAClock.mqh"
#include "OrchestratorConfig.mqh"
#include "OrchestratorSymbolClassifier.mqh"
#include "../../Core/Registry/MathematicalEngineRegistry.mqh"
#include "../../Core/Management/EnterpriseStrategyManager.mqh"
#include "../../Core/Scalp/GridRecoveryEngine.mqh"

class COrchestratorMathEngineHub
{
private:
    CHurstEngine*               m_hurstEngines[];
    COrnsteinUhlenbeckEngine*   m_ouEngines[];
    COrderFlowImbalanceEngine*  m_ofiEngines[];
    CVPINFilter*                m_vpinFilters[];
    string                      m_mathEngineSymbols[];
    bool                        m_gridHurstBridgeLogged[];
    int                         m_mathEngineCount;

    CKalmanMeanReversion*       m_kalmanEngines[];
    CChangepointDetector*       m_cpdEngines[];
    CFourStateRegimeDetector*   m_fourStateEngines[];
    CVolatilityTargeting*       m_volTargetEngines[];
    CLiquiditySweepStrategy*    m_liquiditySweepStrategies[];
    CRangeCompressionBreakout*  m_rangeCompStrategies[];

public:
    COrchestratorMathEngineHub() : m_mathEngineCount(0) {}

    int GetMathEngineCount() { return m_mathEngineCount; }
    int GetSymbolCount()     { return ArraySize(m_mathEngineSymbols); }

    string GetSymbolAt(int idx)
    {
        if(idx < 0 || idx >= ArraySize(m_mathEngineSymbols)) return "";
        return m_mathEngineSymbols[idx];
    }

    int FindSymbolIndex(const string symbol)
    {
        for(int k = 0; k < ArraySize(m_mathEngineSymbols); k++)
        {
            if(m_mathEngineSymbols[k] == symbol) return k;
        }
        return -1;
    }

    CHurstEngine* GetHurstEngine(int idx)
    {
        if(idx < 0 || idx >= ArraySize(m_hurstEngines)) return NULL;
        return m_hurstEngines[idx];
    }

    COrnsteinUhlenbeckEngine* GetOUEngine(int idx)
    {
        if(idx < 0 || idx >= ArraySize(m_ouEngines)) return NULL;
        return m_ouEngines[idx];
    }

    COrderFlowImbalanceEngine* GetOFIEngine(int idx)
    {
        if(idx < 0 || idx >= ArraySize(m_ofiEngines)) return NULL;
        return m_ofiEngines[idx];
    }

    CVPINFilter* GetVPINFilter(int idx)
    {
        if(idx < 0 || idx >= ArraySize(m_vpinFilters)) return NULL;
        return m_vpinFilters[idx];
    }

    void Reserve(int maxEngineCount)
    {
        ArrayResize(m_mathEngineSymbols, maxEngineCount);
        ArrayResize(m_hurstEngines, maxEngineCount);
        ArrayResize(m_ouEngines, maxEngineCount);
        ArrayResize(m_ofiEngines, maxEngineCount);
        ArrayResize(m_vpinFilters, maxEngineCount);
        ArrayResize(m_gridHurstBridgeLogged, maxEngineCount);
        ArrayResize(m_kalmanEngines, maxEngineCount);
        ArrayResize(m_cpdEngines, maxEngineCount);
        ArrayResize(m_fourStateEngines, maxEngineCount);
        ArrayResize(m_volTargetEngines, maxEngineCount);
        ArrayResize(m_liquiditySweepStrategies, maxEngineCount);
        ArrayResize(m_rangeCompStrategies, maxEngineCount);

        for(int i = 0; i < maxEngineCount; i++)
        {
            m_mathEngineSymbols[i] = "";
            m_hurstEngines[i] = NULL;
            m_ouEngines[i] = NULL;
            m_ofiEngines[i] = NULL;
            m_vpinFilters[i] = NULL;
            m_gridHurstBridgeLogged[i] = false;
            m_kalmanEngines[i] = NULL;
            m_cpdEngines[i] = NULL;
            m_fourStateEngines[i] = NULL;
            m_volTargetEngines[i] = NULL;
            m_liquiditySweepStrategies[i] = NULL;
            m_rangeCompStrategies[i] = NULL;
        }
        m_mathEngineCount = 0;
    }

// True when this broker publishes no traded volume, so volume-derived engines run on tick counts.
// CopyRates into MqlRates.real_volume is the only in-terminal traded-volume read: it is zero for
// spot FX, CFDs and synthetic indices.
    static bool HasOnlyTickVolume(const string symbol)
    {
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        int copied = CopyRates(symbol, (ENUM_TIMEFRAMES)Period(), 0, 20, rates);
        if(copied <= 0)
            return true;

        for(int i = 0; i < copied; i++)
        {
            if(rates[i].real_volume > 0)
                return false;
        }
        return true;
    }

    void CreateEnginesForSymbol(const SOrchestratorConfig &config, const string symbol)
    {
        int idx = m_mathEngineCount;
        m_mathEngineSymbols[idx] = symbol;
        m_gridHurstBridgeLogged[idx] = false;

        m_hurstEngines[idx] = NULL;
        if(config.enableHurstEngine)
        {
            m_hurstEngines[idx] = new CHurstEngine(symbol, (ENUM_TIMEFRAMES)Period(), config.hurstLookback);
            if(m_hurstEngines[idx] != NULL && config.logLevel >= 3)
            PrintFormat("[MATH-ENGINE] Hurst engine initialized for %s | lookback=%d", symbol, config.hurstLookback);
        }

        m_ouEngines[idx] = NULL;
        if(config.enableOUProcess)
        {
            m_ouEngines[idx] = new COrnsteinUhlenbeckEngine(symbol, (ENUM_TIMEFRAMES)Period(), config.ouLookback);
            if(m_ouEngines[idx] != NULL && config.logLevel >= 3)
            PrintFormat("[MATH-ENGINE] OU process engine initialized for %s | lookback=%d", symbol, config.ouLookback);
        }

        // OFI/VPIN are volume-derived: traded volume exists only on exchange symbols, while tick
        // volume (what iVolume/CopyTickVolume return) just counts price moves per bar. Synthetic
        // indices have no traded volume, so order-flow toxicity would come from a price-update count.
        const bool volumeEnginesAllowed =
            !COrchestratorSymbolClassifier::IsSyntheticIndexSymbolName(symbol);

        m_ofiEngines[idx] = NULL;
        if(config.enableOFIProxy && volumeEnginesAllowed)
        {
            m_ofiEngines[idx] = new COrderFlowImbalanceEngine();
            if(m_ofiEngines[idx] != NULL)
            {
                m_ofiEngines[idx].Init(symbol, 5, 20, config.ofiSlowWindow);
                if(config.logLevel >= 3)
                PrintFormat("[MATH-ENGINE] OFI proxy engine initialized for %s | slowWindow=%d", symbol, config.ofiSlowWindow);
            }
        }

        m_vpinFilters[idx] = NULL;
        if(config.enableVPINFilter && volumeEnginesAllowed)
        {
            m_vpinFilters[idx] = new CVPINFilter(symbol, 0, config.vpinNumBuckets, config.vpinExtremeThreshold);
            if(m_vpinFilters[idx] != NULL && config.logLevel >= 3)
            PrintFormat("[MATH-ENGINE] VPIN filter initialized for %s | buckets=%d | extreme=%.2f", symbol, config.vpinNumBuckets, config.vpinExtremeThreshold);
        }

        if(!volumeEnginesAllowed &&
           (config.enableOFIProxy || config.enableVPINFilter))
        {
            PrintFormat("[VOLUME-PROXY] %s | synthetic index symbols publish no traded volume - OFI/VPIN left DISABLED for this symbol (inputs request them; tick volume is not order flow)",
                        symbol);
        }
        else if(HasOnlyTickVolume(symbol))
        {
            PrintFormat("[VOLUME-PROXY] %s | no traded volume from this broker - volume-derived engines are running on TICK volume as a proxy", symbol);
        }

        m_kalmanEngines[idx] = NULL;
        if(config.enableKalmanMR)
        {
            m_kalmanEngines[idx] = new CKalmanMeanReversion(symbol, (ENUM_TIMEFRAMES)Period(), 200, config.kalmanLambda);
            if(m_kalmanEngines[idx] != NULL && config.logLevel >= 3)
            PrintFormat("[ENGINE] Kalman MR engine initialized for %s | lambda=%.0f", symbol, config.kalmanLambda);
        }

        m_cpdEngines[idx] = NULL;
        if(config.enableChangepointDetect)
        {
            m_cpdEngines[idx] = new CChangepointDetector(symbol, (ENUM_TIMEFRAMES)Period(), 200, config.cpdHazardThreshold);
            if(m_cpdEngines[idx] != NULL && config.logLevel >= 3)
            PrintFormat("[ENGINE] CPD engine initialized for %s | hazard=%.2f", symbol, config.cpdHazardThreshold);
        }

        m_fourStateEngines[idx] = NULL;
        if(config.enableFourStateRegime)
        {
            m_fourStateEngines[idx] = new CFourStateRegimeDetector(symbol, (ENUM_TIMEFRAMES)Period());
            if(m_fourStateEngines[idx] != NULL && config.logLevel >= 3)
            PrintFormat("[ENGINE] Four-State Regime engine initialized for %s", symbol);
        }

        m_volTargetEngines[idx] = NULL;
        if(config.enableVolTargeting)
        {
            m_volTargetEngines[idx] = new CVolatilityTargeting(symbol, (ENUM_TIMEFRAMES)Period());
            if(m_volTargetEngines[idx] != NULL)
            {
                m_volTargetEngines[idx].Configure(config.targetVol, 100, 0.94, config.volMinScale, config.volMaxScale);
                m_volTargetEngines[idx].Initialize();
                if(config.logLevel >= 3)
                PrintFormat("[ENGINE] Volatility Targeting initialized for %s | target=%.2f%%", symbol, config.targetVol * 100);
            }
        }

        m_liquiditySweepStrategies[idx] = NULL;
        if(config.enableLiquiditySweep)
        {
            m_liquiditySweepStrategies[idx] = new CLiquiditySweepStrategy();
            m_liquiditySweepStrategies[idx].Initialize(symbol, (ENUM_TIMEFRAMES)Period(), NULL);
            if(config.logLevel >= 3)
            PrintFormat("[ENGINE] Liquidity Sweep strategy initialized for %s", symbol);
        }

        m_rangeCompStrategies[idx] = NULL;
        if(config.enableRangeCompression)
        {
            m_rangeCompStrategies[idx] = new CRangeCompressionBreakout();
            m_rangeCompStrategies[idx].Initialize(symbol, (ENUM_TIMEFRAMES)Period(), m_hurstEngines[idx], NULL);
            if(config.logLevel >= 3)
            PrintFormat("[ENGINE] Range Compression Breakout strategy initialized for %s", symbol);
        }

        m_mathEngineCount++;
    }

    void RegisterMathEngines(CMathematicalEngineRegistry *mathReg)
    {
        if(mathReg != NULL)
        mathReg.RegisterAll(m_hurstEngines, m_ouEngines, m_ofiEngines, m_vpinFilters,
        m_kalmanEngines, m_cpdEngines, m_fourStateEngines,
        m_volTargetEngines, m_liquiditySweepStrategies,
        m_rangeCompStrategies, m_mathEngineSymbols, ArraySize(m_mathEngineSymbols));
    }

    // Timer-driven bar-level engine update. Loop order and throttling must stay unchanged.
    void UpdateTimerEngines(const SOrchestratorConfig &config, CGridRecoveryEngine *gridRecovery)
    {
        for(int i = 0; i < ArraySize(m_mathEngineSymbols); i++)
        {
            if(m_hurstEngines[i] != NULL)
            m_hurstEngines[i].Update();
            if(m_ouEngines[i] != NULL)
            m_ouEngines[i].Update();

            if(config.gridRecoveryEnabled && m_hurstEngines[i] != NULL && m_hurstEngines[i].IsWarmedUp())
            {
                double hurstVal = m_hurstEngines[i].GetSnapshot().hurstValue;
                if(gridRecovery != NULL)
                gridRecovery.SetHurstRegime(m_mathEngineSymbols[i], hurstVal);
                if(!m_gridHurstBridgeLogged[i])
                {
                    PrintFormat("[GRID-HURST-BRIDGE] %s | Hurst=%.3f — first bridge to GridRecoveryEngine", m_mathEngineSymbols[i], hurstVal);
                    m_gridHurstBridgeLogged[i] = true;
                }
            }
        }

        for(int i = 0; i < ArraySize(m_mathEngineSymbols); i++)
        {
            if(m_kalmanEngines[i] != NULL)
            m_kalmanEngines[i].Update();
            if(m_cpdEngines[i] != NULL && m_cpdEngines[i].IsInitialized())
            {
                double cpdClose[];
                ArraySetAsSeries(cpdClose, true);
                if(CopyClose(m_mathEngineSymbols[i], (ENUM_TIMEFRAMES)Period(), 0, 1, cpdClose) == 1)
                m_cpdEngines[i].Update(cpdClose[0]);
            }
            if(m_fourStateEngines[i] != NULL)
            m_fourStateEngines[i].Update();
            if(m_volTargetEngines[i] != NULL)
            m_volTargetEngines[i].Update();
        }
    }

    // VPIN/OFI tick feed, throttled to one pass per 200 ms by the function-level static.
    void FeedMicrostructure(int managerCount)
    {
        static uint s_lastVpinOfiFeed = 0;
        uint nowMs = EAClockMs();
        if(nowMs - s_lastVpinOfiFeed >= 200)
        {
            for(int i = 0; i < managerCount; i++)
            {
                string sym = m_mathEngineSymbols[i];
                double tickPrice = SymbolInfoDouble(sym, SYMBOL_BID);
                double tickVolume = (double)SymbolInfoInteger(sym, SYMBOL_VOLUME);
                double bid = SymbolInfoDouble(sym, SYMBOL_BID);
                double ask = SymbolInfoDouble(sym, SYMBOL_ASK);

                if(m_vpinFilters[i] != NULL)
                m_vpinFilters[i].OnTick(tickPrice, tickVolume);
                if(m_ofiEngines[i] != NULL)
                m_ofiEngines[i].OnTick(tickPrice, tickVolume, bid, ask);
            }
            s_lastVpinOfiFeed = nowMs;
        }
    }

    // Enterprise manager indices must be resolved against the caller-supplied managerSymbols
    // array: managers[] is indexed by that array, not by the hub's own symbol list.
    void ApplyHurstWeightModifiersToRegime(const SOrchestratorConfig &config,
                                           CEnterpriseStrategyManager *&managers[],
                                           const string &managerSymbols[])
    {
        if(!config.enableHurstEngine)
        return;

        for(int i = 0; i < ArraySize(m_mathEngineSymbols); i++)
        {
            if(m_hurstEngines[i] == NULL)
            continue;

            CHurstEngine* hurst = m_hurstEngines[i];
            if(!hurst.IsWarmedUp())
            continue;

            SHurstSnapshot hurstSnap = hurst.GetSnapshot();
            if(hurstSnap.regime == HURST_RANDOM_WALK)
            continue;  // Don't modify weights if Hurst is in dead zone

            int mgrIdx = -1;
            for(int m = 0; m < ArraySize(managerSymbols); m++)
            {
                if(managerSymbols[m] == m_mathEngineSymbols[i]) { mgrIdx = m; break; }
            }
            if(mgrIdx < 0 || mgrIdx >= ArraySize(managers) || managers[mgrIdx] == NULL)
            continue;

            CUnifiedSignalPipeline* pipeline = managers[mgrIdx].GetPipeline();
            if(pipeline == NULL)
            continue;

            CRegimeEngine* regimeEngine = pipeline.GetRegimeEngine(m_mathEngineSymbols[i]);
            if(regimeEngine != NULL)
            {
                regimeEngine.ApplyHurstWeightModifiers(
                hurstSnap.meanRevWeightMult,
                hurstSnap.momentumWeightMult,
                hurstSnap.trendWeightMult,
                hurstSnap.breakoutWeightMult
                );
            }

            if(config.enableFourStateRegime && i < ArraySize(m_fourStateEngines) && m_fourStateEngines[i] != NULL)
            {
                CFourStateRegimeDetector* fourState = m_fourStateEngines[i];
                if(fourState.GetSnapshot().timestamp > 0)
                {
                    // Multiply existing weights with Four-State multipliers
                    SFourStateSnapshot fsSnap = fourState.GetSnapshot();
                    if(regimeEngine != NULL)
                    {
                        regimeEngine.ApplyHurstWeightModifiers(
                        fsSnap.meanRevWeightMult,
                        fsSnap.momentumWeightMult,
                        fsSnap.trendWeightMult,
                        fsSnap.breakoutWeightMult
                        );
                    }
                }
            }
        }
    }

    // Every engine is released Deinit()-then-delete; that ordering must not change.
    void ReleaseAll()
    {
        int mathEngineCount = ArraySize(m_mathEngineSymbols);
        for(int i = 0; i < mathEngineCount; i++)
        {
            if(i < ArraySize(m_hurstEngines) && m_hurstEngines[i] != NULL) { m_hurstEngines[i].Deinit(); delete m_hurstEngines[i]; m_hurstEngines[i] = NULL; }
            if(i < ArraySize(m_ouEngines) && m_ouEngines[i] != NULL) { m_ouEngines[i].Deinit(); delete m_ouEngines[i]; m_ouEngines[i] = NULL; }
            if(i < ArraySize(m_ofiEngines) && m_ofiEngines[i] != NULL) { m_ofiEngines[i].Deinit(); delete m_ofiEngines[i]; m_ofiEngines[i] = NULL; }
            if(i < ArraySize(m_vpinFilters) && m_vpinFilters[i] != NULL) { m_vpinFilters[i].Deinit(); delete m_vpinFilters[i]; m_vpinFilters[i] = NULL; }
        }
        ArrayResize(m_hurstEngines, 0);
        ArrayResize(m_ouEngines, 0);
        ArrayResize(m_ofiEngines, 0);
        ArrayResize(m_vpinFilters, 0);
        ArrayResize(m_mathEngineSymbols, 0);
        ArrayResize(m_gridHurstBridgeLogged, 0);

        int batch114Count = ArraySize(m_kalmanEngines);
        for(int i = 0; i < batch114Count; i++)
        {
            if(m_kalmanEngines[i] != NULL) { m_kalmanEngines[i].Deinit(); delete m_kalmanEngines[i]; m_kalmanEngines[i] = NULL; }
            if(i < ArraySize(m_cpdEngines) && m_cpdEngines[i] != NULL) { m_cpdEngines[i].Deinit(); delete m_cpdEngines[i]; m_cpdEngines[i] = NULL; }
            if(i < ArraySize(m_fourStateEngines) && m_fourStateEngines[i] != NULL) { m_fourStateEngines[i].Deinit(); delete m_fourStateEngines[i]; m_fourStateEngines[i] = NULL; }
            if(i < ArraySize(m_volTargetEngines) && m_volTargetEngines[i] != NULL) { m_volTargetEngines[i].Deinit(); delete m_volTargetEngines[i]; m_volTargetEngines[i] = NULL; }
            if(i < ArraySize(m_liquiditySweepStrategies) && m_liquiditySweepStrategies[i] != NULL) { m_liquiditySweepStrategies[i].Deinit(); delete m_liquiditySweepStrategies[i]; m_liquiditySweepStrategies[i] = NULL; }
            if(i < ArraySize(m_rangeCompStrategies) && m_rangeCompStrategies[i] != NULL) { m_rangeCompStrategies[i].Deinit(); delete m_rangeCompStrategies[i]; m_rangeCompStrategies[i] = NULL; }
        }
        ArrayResize(m_kalmanEngines, 0);
        ArrayResize(m_cpdEngines, 0);
        ArrayResize(m_fourStateEngines, 0);
        ArrayResize(m_volTargetEngines, 0);
        ArrayResize(m_liquiditySweepStrategies, 0);
        ArrayResize(m_rangeCompStrategies, 0);

        m_mathEngineCount = 0;
    }
};

#endif // CORE_ORCHESTRATION_ORCHESTRATOR_MATH_ENGINE_HUB_MQH
