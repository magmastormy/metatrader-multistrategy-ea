//+------------------------------------------------------------------+
//| OrchestratorMathEngineHub.mqh                                    |
//| Phase F extraction from CEAOrchestrator (behaviour preserving).  |
//|                                                                  |
//| Owns the three per-symbol engine fleets that used to be sixteen  |
//| loose dynamic-array members on CEAOrchestrator:                  |
//|                                                                  |
//|   Batch 100 : Hurst, Ornstein-Uhlenbeck, OFI proxy, VPIN         |
//|   Batch 114 : Kalman MR, Changepoint, Four-State regime,         |
//|               Volatility targeting, Exit optimizer,              |
//|               Liquidity sweep, Range compression                 |
//|   Batch 107 : VWAP, Volume Profile, CVD (forex only)             |
//|                                                                  |
//| plus the parallel symbol/bridge-log bookkeeping arrays and the   |
//| m_mathEngineCount cursor.                                        |
//|                                                                  |
//| Every body below was moved verbatim; collaborators the original  |
//| code reached for through members (m_config, the registries, the  |
//| enterprise-manager arrays, m_gridRecovery, m_signalDiagnostics)  |
//| are now explicit parameters. CEAOrchestrator holds one hub by    |
//| value and keeps thin forwarders with the original signatures.    |
//|                                                                  |
//| Ownership: the hub OWNS every engine pointer it allocates and    |
//| releases them in ReleaseAll() with the original Deinit()+delete  |
//| ordering. The registries hold non-owning references.             |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_ORCHESTRATION_ORCHESTRATOR_MATH_ENGINE_HUB_MQH
#define CORE_ORCHESTRATION_ORCHESTRATOR_MATH_ENGINE_HUB_MQH

#include "OrchestratorConfig.mqh"
#include "OrchestratorSymbolClassifier.mqh"
#include "../../Core/Registry/MathematicalEngineRegistry.mqh"
#include "../../Core/Registry/InstitutionalEngineRegistry.mqh"
#include "../../Core/Management/EnterpriseStrategyManager.mqh"
#include "../../Core/Scalp/GridRecoveryEngine.mqh"

//+------------------------------------------------------------------+
//| COrchestratorMathEngineHub                                       |
//+------------------------------------------------------------------+
class COrchestratorMathEngineHub
{
private:
    // Batch 100: Advanced Mathematical Engines
    CHurstEngine*               m_hurstEngines[];
    COrnsteinUhlenbeckEngine*   m_ouEngines[];
    COrderFlowImbalanceEngine*  m_ofiEngines[];
    CVPINFilter*                m_vpinFilters[];
    string                      m_mathEngineSymbols[];
    bool                        m_gridHurstBridgeLogged[];
    int                         m_mathEngineCount;

    // Batch 114: Research-Driven Statistical Algorithm Upgrades
    CKalmanMeanReversion*       m_kalmanEngines[];
    CChangepointDetector*       m_cpdEngines[];
    CFourStateRegimeDetector*   m_fourStateEngines[];
    CVolatilityTargeting*       m_volTargetEngines[];
    CExitOptimizer*             m_exitOptimizers[];
    CLiquiditySweepStrategy*    m_liquiditySweepStrategies[];
    CRangeCompressionBreakout*  m_rangeCompStrategies[];

    // Batch 107: Institutional TA Engines (Forex only)
    CVWAPEngine*                m_vwapEngines[];
    CVolumeProfileEngine*       m_vpEngines[];
    CCVDEngine*                 m_cvdEngines[];

public:
    COrchestratorMathEngineHub() : m_mathEngineCount(0) {}

    // ================= Cursor / lookup accessors =================

    int GetMathEngineCount() { return m_mathEngineCount; }
    int GetSymbolCount()     { return ArraySize(m_mathEngineSymbols); }

    string GetSymbolAt(int idx)
    {
        if(idx < 0 || idx >= ArraySize(m_mathEngineSymbols)) return "";
        return m_mathEngineSymbols[idx];
    }

    // Mirrors the inline lookup loop that used to live in
    // InitializeEnterpriseManagers() when wiring engines to strategies.
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

    // ================= Pre-allocation =================

    // Was the ArrayResize + NULL-init block at the head of
    // CEAOrchestrator::InitializeEnterpriseManagers().
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
        ArrayResize(m_exitOptimizers, maxEngineCount);
        ArrayResize(m_liquiditySweepStrategies, maxEngineCount);
        ArrayResize(m_rangeCompStrategies, maxEngineCount);
        ArrayResize(m_vwapEngines, maxEngineCount);
        ArrayResize(m_vpEngines, maxEngineCount);
        ArrayResize(m_cvdEngines, maxEngineCount);

        // Initialize all arrays to NULL/empty
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
            m_exitOptimizers[i] = NULL;
            m_liquiditySweepStrategies[i] = NULL;
            m_rangeCompStrategies[i] = NULL;
            m_vwapEngines[i] = NULL;
            m_vpEngines[i] = NULL;
            m_cvdEngines[i] = NULL;
        }
        m_mathEngineCount = 0;
    }

    // ================= Per-symbol construction =================

    // Was the "Batch 100: Initialize per-symbol mathematical engines using
    // pre-allocated arrays" block inside
    // CEAOrchestrator::InitializeEnterpriseManagerForSymbol().
    //+--------------------------------------------------------------+
    //| True when this broker publishes no traded volume for the     |
    //| symbol, so anything volume-derived is running on tick counts.|
    //| MqlRates.real_volume is zero on every symbol without exchange|
    //| volume (spot FX, CFD and synthetic indices), which is the    |
    //| only in-terminal way to know before an engine consumes the   |
    //| difference.                                                  |
    //+--------------------------------------------------------------+
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

        // Hurst Engine
        m_hurstEngines[idx] = NULL;
        if(config.enableHurstEngine)
        {
            m_hurstEngines[idx] = new CHurstEngine(symbol, (ENUM_TIMEFRAMES)Period(), config.hurstLookback);
            if(m_hurstEngines[idx] != NULL && config.logLevel >= 3)
            PrintFormat("[MATH-ENGINE] Hurst engine initialized for %s | lookback=%d", symbol, config.hurstLookback);
        }

        // OU Process Engine
        m_ouEngines[idx] = NULL;
        if(config.enableOUProcess)
        {
            m_ouEngines[idx] = new COrnsteinUhlenbeckEngine(symbol, (ENUM_TIMEFRAMES)Period(), config.ouLookback);
            if(m_ouEngines[idx] != NULL && config.logLevel >= 3)
            PrintFormat("[MATH-ENGINE] OU process engine initialized for %s | lookback=%d", symbol, config.ouLookback);
        }

        // OFI Proxy Engine
        //
        // Batch 170: every engine below is volume-derived. MQL5 exposes two very
        // different things called "volume": traded volume (real, only on exchange
        // symbols) and tick volume (how many times the price moved in a bar).
        // iVolume/CopyTickVolume return the latter, and SYNTHETIC INDEX SYMBOLS
        // have no traded volume at all, so OFI/VPIN were computing order-flow
        // toxicity from a price-update count. VWAP, Volume Profile and CVD were
        // already excluded for synthetics (Batch 107); OFI and VPIN were not.
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

        // VPIN Filter
        m_vpinFilters[idx] = NULL;
        if(config.enableVPINFilter && volumeEnginesAllowed)
        {
            m_vpinFilters[idx] = new CVPINFilter(symbol, 0, config.vpinNumBuckets, config.vpinExtremeThreshold);
            if(m_vpinFilters[idx] != NULL && config.logLevel >= 3)
            PrintFormat("[MATH-ENGINE] VPIN filter initialized for %s | buckets=%d | extreme=%.2f", symbol, config.vpinNumBuckets, config.vpinExtremeThreshold);
        }

        if(!volumeEnginesAllowed &&
           (config.enableOFIProxy || config.enableVPINFilter || config.enableVWAPEngine ||
            config.enableVolumeProfile || config.enableCVDEngine))
        {
            PrintFormat("[VOLUME-PROXY] %s | synthetic index symbols publish no traded volume - OFI/VPIN/VWAP/VolumeProfile/CVD left DISABLED for this symbol (inputs request them; tick volume is not order flow)",
                        symbol);
        }
        else if(HasOnlyTickVolume(symbol))
        {
            PrintFormat("[VOLUME-PROXY] %s | no traded volume from this broker - volume-derived engines are running on TICK volume as a proxy", symbol);
        }

        // Batch 107: VWAP Engine (forex only)
        m_vwapEngines[idx] = NULL;
        if(config.enableVWAPEngine && !COrchestratorSymbolClassifier::IsSyntheticIndexSymbolName(symbol))
        {
            m_vwapEngines[idx] = new CVWAPEngine();
            m_vwapEngines[idx].Initialize(symbol, config.vwapMinPeriodBars, config.vwapBand1, config.vwapBand2, config.vwapBand3);
            if(config.logLevel >= 3)
            PrintFormat("[INSTITUTIONAL-ENGINE] VWAP engine initialized for %s", symbol);
        }

        // Batch 107: Volume Profile Engine (forex only)
        m_vpEngines[idx] = NULL;
        if(config.enableVolumeProfile && !COrchestratorSymbolClassifier::IsSyntheticIndexSymbolName(symbol))
        {
            m_vpEngines[idx] = new CVolumeProfileEngine();
            m_vpEngines[idx].Initialize(symbol, config.vpLookback, config.vpResolution);
            if(config.logLevel >= 3)
            PrintFormat("[INSTITUTIONAL-ENGINE] Volume Profile engine initialized for %s", symbol);
        }

        // Batch 107: CVD Engine (forex only)
        m_cvdEngines[idx] = NULL;
        if(config.enableCVDEngine && !COrchestratorSymbolClassifier::IsSyntheticIndexSymbolName(symbol))
        {
            m_cvdEngines[idx] = new CCVDEngine();
            m_cvdEngines[idx].Initialize(symbol, config.cvdDivergenceLookback);
            if(config.logLevel >= 3)
            PrintFormat("[INSTITUTIONAL-ENGINE] CVD engine initialized for %s", symbol);
        }

        // Batch 114: Research-Driven Statistical Algorithm Engines
        // Kalman/FLS Dynamic Mean-Reversion
        m_kalmanEngines[idx] = NULL;
        if(config.enableKalmanMR)
        {
            m_kalmanEngines[idx] = new CKalmanMeanReversion(symbol, (ENUM_TIMEFRAMES)Period(), 200, config.kalmanLambda);
            if(m_kalmanEngines[idx] != NULL && config.logLevel >= 3)
            PrintFormat("[ENGINE] Kalman MR engine initialized for %s | lambda=%.0f", symbol, config.kalmanLambda);
        }

        // Bayesian Online Changepoint Detection
        m_cpdEngines[idx] = NULL;
        if(config.enableChangepointDetect)
        {
            m_cpdEngines[idx] = new CChangepointDetector(symbol, (ENUM_TIMEFRAMES)Period(), 200, config.cpdHazardThreshold);
            if(m_cpdEngines[idx] != NULL && config.logLevel >= 3)
            PrintFormat("[ENGINE] CPD engine initialized for %s | hazard=%.2f", symbol, config.cpdHazardThreshold);
        }

        // Four-State Regime Detector
        m_fourStateEngines[idx] = NULL;
        if(config.enableFourStateRegime)
        {
            m_fourStateEngines[idx] = new CFourStateRegimeDetector(symbol, (ENUM_TIMEFRAMES)Period());
            if(m_fourStateEngines[idx] != NULL && config.logLevel >= 3)
            PrintFormat("[ENGINE] Four-State Regime engine initialized for %s", symbol);
        }

        // Volatility Targeting
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

        // Exit Optimizer
        m_exitOptimizers[idx] = NULL;
        if(config.enableExitOptimizer)
        {
            m_exitOptimizers[idx] = new CExitOptimizer();
            m_exitOptimizers[idx].Initialize(symbol, (ENUM_TIMEFRAMES)Period());
            if(config.logLevel >= 3)
            PrintFormat("[ENGINE] Exit Optimizer initialized for %s", symbol);
        }

        // Liquidity Sweep Strategy
        m_liquiditySweepStrategies[idx] = NULL;
        if(config.enableLiquiditySweep)
        {
            m_liquiditySweepStrategies[idx] = new CLiquiditySweepStrategy();
            m_liquiditySweepStrategies[idx].Initialize(symbol, (ENUM_TIMEFRAMES)Period(), NULL);
            if(config.logLevel >= 3)
            PrintFormat("[ENGINE] Liquidity Sweep strategy initialized for %s", symbol);
        }

        // Range Compression Breakout Strategy
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

    // ================= Bulk construction =================

    // Was CEAOrchestrator::InitializeMathematicalEngines()
    void InitializeMathematicalEngines(const SOrchestratorConfig &config,
                                       CMathematicalEngineRegistry *mathReg,
                                       const string &managerSymbols[],
                                       int managerCount,
                                       CSignalDiagnostics *signalDiagnostics)
    {
        int count = managerCount;
        if(count <= 0) return;

        // Resize all engine arrays
        ArrayResize(m_hurstEngines, count);
        ArrayResize(m_ouEngines, count);
        ArrayResize(m_ofiEngines, count);
        ArrayResize(m_vpinFilters, count);
        ArrayResize(m_kalmanEngines, count);
        ArrayResize(m_cpdEngines, count);
        ArrayResize(m_fourStateEngines, count);
        ArrayResize(m_volTargetEngines, count);
        ArrayResize(m_exitOptimizers, count);
        ArrayResize(m_liquiditySweepStrategies, count);
        ArrayResize(m_rangeCompStrategies, count);
        ArrayResize(m_mathEngineSymbols, count);
        ArrayResize(m_gridHurstBridgeLogged, count);

        for(int i = 0; i < count; i++)
        {
            string sym = managerSymbols[i];
            if(sym == "") continue;

            m_mathEngineSymbols[i] = sym;

            // Batch 100: Hurst Engine
            if(config.enableHurstEngine)
            {
                m_hurstEngines[i] = new CHurstEngine(sym, PERIOD_CURRENT, config.hurstLookback);
                if(m_hurstEngines[i] != NULL && mathReg != NULL)
                {
                    mathReg.RegisterHurstEngine(sym, m_hurstEngines[i]);
                    PrintFormat("[HURST] Engine initialized for %s (lookback=%d)", sym, config.hurstLookback);
                }
            }

            // Batch 100: Ornstein-Uhlenbeck Process
            if(config.enableOUProcess)
            {
                m_ouEngines[i] = new COrnsteinUhlenbeckEngine(sym, PERIOD_CURRENT, config.ouLookback);
                if(m_ouEngines[i] != NULL && mathReg != NULL)
                {
                    mathReg.RegisterOUEngine(sym, m_ouEngines[i]);
                    PrintFormat("[OU] Engine initialized for %s (lookback=%d)", sym, config.ouLookback);
                }
            }

            // Batch 100: Order Flow Imbalance Proxy
            if(config.enableOFIProxy)
            {
                m_ofiEngines[i] = new COrderFlowImbalanceEngine();
                if(m_ofiEngines[i] != NULL && mathReg != NULL)
                {
                    mathReg.RegisterOFIEngine(sym, m_ofiEngines[i]);
                    PrintFormat("[OFI] Engine initialized for %s (slowWindow=%d)", sym, config.ofiSlowWindow);
                }
            }

            // Batch 100: VPIN Filter
            if(config.enableVPINFilter)
            {
                m_vpinFilters[i] = new CVPINFilter(sym);
                if(m_vpinFilters[i] != NULL && mathReg != NULL)
                {
                    mathReg.RegisterVPINFilter(sym, m_vpinFilters[i]);
                    PrintFormat("[VPIN] Filter initialized for %s (threshold=%.2f, buckets=%d)",
                    sym, config.vpinExtremeThreshold, config.vpinNumBuckets);
                }
            }

            // Batch 114: Kalman Mean Reversion
            if(config.enableKalmanMR)
            {
                m_kalmanEngines[i] = new CKalmanMeanReversion(sym);
                if(m_kalmanEngines[i] != NULL && mathReg != NULL)
                {
                    mathReg.RegisterKalmanEngine(sym, m_kalmanEngines[i]);
                    PrintFormat("[KALMAN-MR] Engine initialized for %s (lambda=%.1f)", sym, config.kalmanLambda);
                }
            }

            // Batch 114: Changepoint Detector
            if(config.enableChangepointDetect)
            {
                m_cpdEngines[i] = new CChangepointDetector(sym, PERIOD_CURRENT, 200, config.cpdHazardThreshold);
                if(m_cpdEngines[i] != NULL && mathReg != NULL)
                {
                    if(m_cpdEngines[i].Initialize())
                    {
                        mathReg.RegisterCPDDetector(sym, m_cpdEngines[i]);
                        PrintFormat("[CPD] Detector initialized for %s (hazard=%.2f)", sym, config.cpdHazardThreshold);
                    }
                    else
                    {
                        PrintFormat("[CPD] WARNING: Failed to initialize for %s", sym);
                        delete m_cpdEngines[i];
                        m_cpdEngines[i] = NULL;
                    }
                }
            }

            // Batch 114: Four State Regime Detector
            if(config.enableFourStateRegime)
            {
                m_fourStateEngines[i] = new CFourStateRegimeDetector();
                if(m_fourStateEngines[i] != NULL && mathReg != NULL)
                {
                    if(m_fourStateEngines[i].Initialize())
                    {
                        mathReg.RegisterFourStateDetector(sym, m_fourStateEngines[i]);
                        PrintFormat("[FOUR-STATE] Detector initialized for %s", sym);
                    }
                    else
                    {
                        PrintFormat("[FOUR-STATE] WARNING: Failed to initialize for %s", sym);
                        delete m_fourStateEngines[i];
                        m_fourStateEngines[i] = NULL;
                    }
                }
            }

            // Batch 114: Volatility Targeting
            if(config.enableVolTargeting)
            {
                m_volTargetEngines[i] = new CVolatilityTargeting();
                if(m_volTargetEngines[i] != NULL && mathReg != NULL)
                {
                    if(m_volTargetEngines[i].Initialize())
                    {
                        mathReg.RegisterVolTargetEngine(sym, m_volTargetEngines[i]);
                        PrintFormat("[VOL-TARGET] Engine initialized for %s (target=%.2f, scale=[%.2f,%.2f])",
                        sym, config.targetVol, config.volMinScale, config.volMaxScale);
                    }
                    else
                    {
                        PrintFormat("[VOL-TARGET] WARNING: Failed to initialize for %s", sym);
                        delete m_volTargetEngines[i];
                        m_volTargetEngines[i] = NULL;
                    }
                }
            }

            // Batch 114: Exit Optimizer
            if(config.enableExitOptimizer)
            {
                m_exitOptimizers[i] = new CExitOptimizer();
                if(m_exitOptimizers[i] != NULL && mathReg != NULL)
                {
                    if(m_exitOptimizers[i].Initialize(sym, PERIOD_CURRENT))
                    {
                        mathReg.RegisterExitOptimizer(sym, m_exitOptimizers[i]);
                        PrintFormat("[EXIT-OPT] Optimizer initialized for %s", sym);
                    }
                    else
                    {
                        PrintFormat("[EXIT-OPT] WARNING: Failed to initialize for %s", sym);
                        delete m_exitOptimizers[i];
                        m_exitOptimizers[i] = NULL;
                    }
                }
            }

            // Batch 114: Liquidity Sweep Strategy
            if(config.enableLiquiditySweep)
            {
                m_liquiditySweepStrategies[i] = new CLiquiditySweepStrategy();
                if(m_liquiditySweepStrategies[i] != NULL && mathReg != NULL)
                {
                    if(m_liquiditySweepStrategies[i].Initialize(sym, PERIOD_CURRENT))
                    {
                        mathReg.RegisterLiquiditySweepStrategy(sym, m_liquiditySweepStrategies[i]);
                        PrintFormat("[LIQ-SWEEP] Strategy initialized for %s", sym);
                    }
                    else
                    {
                        PrintFormat("[LIQ-SWEEP] WARNING: Failed to initialize for %s", sym);
                        delete m_liquiditySweepStrategies[i];
                        m_liquiditySweepStrategies[i] = NULL;
                    }
                }
            }

            // Batch 114: Range Compression Breakout
            if(config.enableRangeCompression)
            {
                m_rangeCompStrategies[i] = new CRangeCompressionBreakout();
                if(m_rangeCompStrategies[i] != NULL && mathReg != NULL)
                {
                    if(m_rangeCompStrategies[i].Initialize(sym, PERIOD_CURRENT))
                    {
                        mathReg.RegisterRangeCompressionStrategy(sym, m_rangeCompStrategies[i]);
                        PrintFormat("[RANGE-COMP] Strategy initialized for %s", sym);
                    }
                    else
                    {
                        PrintFormat("[RANGE-COMP] WARNING: Failed to initialize for %s", sym);
                        delete m_rangeCompStrategies[i];
                        m_rangeCompStrategies[i] = NULL;
                    }
                }
            }

            m_gridHurstBridgeLogged[i] = false;
        }

        // Initialize pipeline engines with SignalDiagnostics for all symbols
        if(mathReg != NULL && signalDiagnostics != NULL)
        {
            mathReg.InitializePipelineEngines(managerSymbols, managerCount);
        }

        PrintFormat("[INIT] Mathematical engines initialized for %d symbols", count);
    }

    // Was CEAOrchestrator::InitializeInstitutionalEngines()
    void InitializeInstitutionalEngines(const SOrchestratorConfig &config,
                                        CInstitutionalEngineRegistry *instReg,
                                        const string &managerSymbols[],
                                        int managerCount)
    {
        int count = managerCount;
        if(count <= 0) return;

        // Resize institutional engine arrays
        ArrayResize(m_vwapEngines, count);
        ArrayResize(m_vpEngines, count);
        ArrayResize(m_cvdEngines, count);

        for(int i = 0; i < count; i++)
        {
            string sym = managerSymbols[i];
            if(sym == "") continue;

            // Only initialize for Forex symbols
            if(!COrchestratorSymbolClassifier::IsForexSymbol(sym))
            {
                continue;
            }

            // Batch 107: VWAP Engine
            if(config.enableVWAPEngine)
            {
                m_vwapEngines[i] = new CVWAPEngine();
                if(m_vwapEngines[i] != NULL && instReg != NULL)
                {
                    if(m_vwapEngines[i].Initialize(sym, config.vwapMinPeriodBars, config.vwapBand1, config.vwapBand2, config.vwapBand3))
                    {
                        instReg.RegisterVWAPEngine(sym, m_vwapEngines[i]);
                        PrintFormat("[VWAP] Engine initialized for %s (period=%d, bands=%.1f/%.1f/%.1f)",
                        sym, config.vwapMinPeriodBars, config.vwapBand1, config.vwapBand2, config.vwapBand3);
                    }
                    else
                    {
                        PrintFormat("[VWAP] WARNING: Failed to initialize for %s", sym);
                        delete m_vwapEngines[i];
                        m_vwapEngines[i] = NULL;
                    }
                }
            }

            // Batch 107: Volume Profile Engine
            if(config.enableVolumeProfile)
            {
                m_vpEngines[i] = new CVolumeProfileEngine();
                if(m_vpEngines[i] != NULL && instReg != NULL)
                {
                    if(m_vpEngines[i].Initialize(sym, config.vpLookback, config.vpResolution))
                    {
                        instReg.RegisterVPEngine(sym, m_vpEngines[i]);
                        PrintFormat("[VP] Engine initialized for %s (lookback=%d, resolution=%d)",
                        sym, config.vpLookback, config.vpResolution);
                    }
                    else
                    {
                        PrintFormat("[VP] WARNING: Failed to initialize for %s", sym);
                        delete m_vpEngines[i];
                        m_vpEngines[i] = NULL;
                    }
                }
            }

            // Batch 107: CVD Engine
            if(config.enableCVDEngine)
            {
                m_cvdEngines[i] = new CCVDEngine();
                if(m_cvdEngines[i] != NULL && instReg != NULL)
                {
                    if(m_cvdEngines[i].Initialize(sym, config.cvdDivergenceLookback))
                    {
                        instReg.RegisterCVDEngine(sym, m_cvdEngines[i]);
                        PrintFormat("[CVD] Engine initialized for %s (divLookback=%d)",
                        sym, config.cvdDivergenceLookback);
                    }
                    else
                    {
                        PrintFormat("[CVD] WARNING: Failed to initialize for %s", sym);
                        delete m_cvdEngines[i];
                        m_cvdEngines[i] = NULL;
                    }
                }
            }
        }

        PrintFormat("[INIT] Institutional TA engines initialized for %d forex symbols", count);
    }

    // ================= Registry publication =================

    // Was the "Register mathematical engines with registry" block in
    // CEAOrchestrator::InitializeComponents().
    void RegisterMathEngines(CMathematicalEngineRegistry *mathReg)
    {
        if(mathReg != NULL)
        mathReg.RegisterAll(m_hurstEngines, m_ouEngines, m_ofiEngines, m_vpinFilters,
        m_kalmanEngines, m_cpdEngines, m_fourStateEngines,
        m_volTargetEngines, m_exitOptimizers, m_liquiditySweepStrategies,
        m_rangeCompStrategies, m_mathEngineSymbols, ArraySize(m_mathEngineSymbols));
    }

    // Was the "Register institutional engines with registry" block in
    // CEAOrchestrator::InitializeComponents().
    void RegisterInstitutionalEngines(CInstitutionalEngineRegistry *instReg,
                                      const string &managerSymbols[],
                                      int managerCount)
    {
        if(instReg != NULL)
        instReg.RegisterAll(m_vwapEngines, m_vpEngines, m_cvdEngines,
        managerSymbols, managerCount);
    }

    // ================= Runtime updates =================

    // Was the two "Batch 100 / Batch 114 engine update" loops in
    // CEAOrchestrator::OnTimer(). Loop order and throttling are unchanged.
    void UpdateTimerEngines(const SOrchestratorConfig &config, CGridRecoveryEngine *gridRecovery)
    {
        // Batch 100: Update bar-level mathematical engines (Hurst, OU) on timer
        for(int i = 0; i < ArraySize(m_mathEngineSymbols); i++)
        {
            if(m_hurstEngines[i] != NULL)
            m_hurstEngines[i].Update();
            if(m_ouEngines[i] != NULL)
            m_ouEngines[i].Update();

            // Batch 29a: Bridge Hurst output to GridRecoveryEngine
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

        // Batch 114: Update Research-Driven Statistical Algorithm Engines
        for(int i = 0; i < ArraySize(m_mathEngineSymbols); i++)
        {
            if(m_kalmanEngines[i] != NULL)
            m_kalmanEngines[i].Update();
            if(m_cpdEngines[i] != NULL && m_cpdEngines[i].IsInitialized())
            {
                // Feed CPD with close price
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

    // Was the VPIN/OFI feed block at the head of
    // CEAOrchestrator::FeedMicrostructureEngines(). The 200 ms throttle keeps
    // its function-level static, so cadence is unchanged.
    void FeedMicrostructure(int managerCount)
    {
        static uint s_lastVpinOfiFeed = 0;
        uint nowMs = GetTickCount();
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

    // Was CEAOrchestrator::ApplyHurstWeightModifiersToRegime(). The enterprise
    // manager lookup that used FindEnterpriseManagerIndex() is inlined against
    // the caller-supplied manager symbol array so the index semantics match.
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

            // Find the enterprise manager for this symbol
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

            // Batch 114: Apply Four-State Regime Detector weight multipliers
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

    // ================= Teardown =================

    // Was the three engine-cleanup blocks at the head of
    // CEAOrchestrator::Shutdown(). Deinit()+delete ordering is unchanged.
    void ReleaseAll()
    {
        // Cleanup mathematical engines
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

        // Cleanup Batch 114 engines
        int batch114Count = ArraySize(m_kalmanEngines);
        for(int i = 0; i < batch114Count; i++)
        {
            if(m_kalmanEngines[i] != NULL) { m_kalmanEngines[i].Deinit(); delete m_kalmanEngines[i]; m_kalmanEngines[i] = NULL; }
            if(i < ArraySize(m_cpdEngines) && m_cpdEngines[i] != NULL) { m_cpdEngines[i].Deinit(); delete m_cpdEngines[i]; m_cpdEngines[i] = NULL; }
            if(i < ArraySize(m_fourStateEngines) && m_fourStateEngines[i] != NULL) { m_fourStateEngines[i].Deinit(); delete m_fourStateEngines[i]; m_fourStateEngines[i] = NULL; }
            if(i < ArraySize(m_volTargetEngines) && m_volTargetEngines[i] != NULL) { m_volTargetEngines[i].Deinit(); delete m_volTargetEngines[i]; m_volTargetEngines[i] = NULL; }
            if(i < ArraySize(m_exitOptimizers) && m_exitOptimizers[i] != NULL) { m_exitOptimizers[i].Deinit(); delete m_exitOptimizers[i]; m_exitOptimizers[i] = NULL; }
            if(i < ArraySize(m_liquiditySweepStrategies) && m_liquiditySweepStrategies[i] != NULL) { m_liquiditySweepStrategies[i].Deinit(); delete m_liquiditySweepStrategies[i]; m_liquiditySweepStrategies[i] = NULL; }
            if(i < ArraySize(m_rangeCompStrategies) && m_rangeCompStrategies[i] != NULL) { m_rangeCompStrategies[i].Deinit(); delete m_rangeCompStrategies[i]; m_rangeCompStrategies[i] = NULL; }
        }
        ArrayResize(m_kalmanEngines, 0);
        ArrayResize(m_cpdEngines, 0);
        ArrayResize(m_fourStateEngines, 0);
        ArrayResize(m_volTargetEngines, 0);
        ArrayResize(m_exitOptimizers, 0);
        ArrayResize(m_liquiditySweepStrategies, 0);
        ArrayResize(m_rangeCompStrategies, 0);

        // Cleanup institutional engines
        int instCount = ArraySize(m_vwapEngines);
        for(int i = 0; i < instCount; i++)
        {
            if(m_vwapEngines[i] != NULL) { m_vwapEngines[i].Deinit(); delete m_vwapEngines[i]; m_vwapEngines[i] = NULL; }
            if(i < ArraySize(m_vpEngines) && m_vpEngines[i] != NULL) { m_vpEngines[i].Deinit(); delete m_vpEngines[i]; m_vpEngines[i] = NULL; }
            if(i < ArraySize(m_cvdEngines) && m_cvdEngines[i] != NULL) { m_cvdEngines[i].Deinit(); delete m_cvdEngines[i]; m_cvdEngines[i] = NULL; }
        }
        ArrayResize(m_vwapEngines, 0);
        ArrayResize(m_vpEngines, 0);
        ArrayResize(m_cvdEngines, 0);

        m_mathEngineCount = 0;
    }
};

#endif // CORE_ORCHESTRATION_ORCHESTRATOR_MATH_ENGINE_HUB_MQH
