# System Audit Trace

## Document Metadata
- Last Updated: 2026-07-01
- Scope: End-to-end lifecycle and logic traces
- Current Batch: 110

## Scope
- Entry point: `MultiStrategyAutonomousEA.mq5`
- Symbol decision manager: `Core/Management/EnterpriseStrategyManager.mqh`
- Multi-tier validator: `Core/Signals/TieredSignalValidator.mqh` (Batch 60)
- Filter pipeline: `Core/Pipeline/UnifiedSignalPipeline.mqh`
- AI runtime control: `Core/Engines/AIEngine.mqh`
- AI adapters:
  - `Core/Strategy/AIStrategyAdapter.mqh`
  - `Core/Strategy/TransformerAIStrategyAdapter.mqh`
  - `Core/Strategy/EnsembleAIStrategyAdapter.mqh`
  - `Core/Strategy/OnnxAIStrategyAdapter.mqh`
- AI modules:
  - `AIModules/NeuralNetworkStrategy.mqh`
  - `AIModules/TransformerBrain.mqh`
  - `AIModules/EnsembleMetaLearner.mqh`
  - `AIModules/UniversalTransformerService.mqh`
  - `AIModules/CNeuralCore.mqh` (NEW - Modular core)
  - `AIModules/CNeuralTrainingDataManager.mqh` (NEW - Training management)
  - `AIModules/CNeuralCheckpointManager.mqh` (NEW - Checkpoint I/O)
- Risk authority: `Core/Risk/UnifiedRiskManager.mqh`
- Execution authority: `Core/Trading/TradeManager.mqh`
- Position authority: EA lifecycle loop via `CTradeManager::ManageAllPositions(...)`
- Python bridge: `Core/Utils/PythonBridge.mqh`, `Python/zmq_server.py`
- Position lifecycle: `Core/Management/PositionLifecycleManager.mqh`
- Diagnostics manager: `Core/Management/DiagnosticsManager.mqh`
- Unprotected position tracker: `Core/Risk/UnprotectedPositionTracker.mqh`
- Synthetic spike monitor: `Core/Processing/SyntheticSpikeMonitor.mqh`
- Trade attribution: `Core/Trading/TradeAttributionManager.mqh`
- Symbol scan scheduler: `Core/Processing/SymbolScanScheduler.mqh`
- Equity curve manager: `Core/Risk/EquityCurveManager.mqh`
- Spike hunter engine: `Core/Scalp/SpikeHunterEngine.mqh`
- Hurst engine: `Core/Engines/HurstEngine.mqh`
- OU process engine: `Core/Engines/OrnsteinUhlenbeckEngine.mqh`
- OFI proxy engine: `Core/Engines/OrderFlowImbalanceEngine.mqh`
- VPIN filter: `Core/Risk/VPINFilter.mqh`
- Deriv asset profiler: `Core/Processing/DerivAssetProfiler.mqh`
- Multi-asset class profiler: `Core/Processing/MultiAssetProfiler.mqh`
- Grid recovery engine: `Core/Scalp/GridRecoveryEngine.mqh`
- ATR scalping engine: `Core/Scalp/ATRScalpingEngine.mqh`
- Statistical Arbitrage strategy: `Strategies/StatisticalArbitrageStrategy.mqh`
- Candlestick confluence scorer: `Strategies/CandlestickFiles/CandleConfluenceScorer.mqh`
- Candlestick pattern detectors: `Strategies/CandlestickFiles/DojiDetector.mqh`, `HammerDetector.mqh`, `StarDetector.mqh`, `HaramiDetector.mqh`, `ThreeSoldiersDetector.mqh`, `PiercingDetector.mqh`
- CatBoost trainer: `Python/train_catboost.py`
- XGBoost trainer: `Python/train_xgboost.py`
- Implementation plan: `IMPLEMENTATION_PLAN.md`
- Research report: `EA_PERFORMANCE_RESEARCH_REPORT.md`

## Current Runtime Evidence
- **EA Enterprise Vision Implementation (Batch 103, 2026-06-17):** Upgrades the multi-strategy EA to an enterprise consensus engine with 11 strategies:
  - **A1 — Candlestick v2.0:** 7 new pattern detectors (CDojiDetector, CHammerDetector, CStarDetector, CHaramiDetector, CThreeSoldiersDetector, CPiercingDetector) + CCandleConfluenceScorer (0-100 scoring, threshold ≥70). Confidence = score/100.0. Files: `Strategies/CandlestickFiles/DojiDetector.mqh`, `HammerDetector.mqh`, `StarDetector.mqh`, `HaramiDetector.mqh`, `ThreeSoldiersDetector.mqh`, `PiercingDetector.mqh`, `CandleConfluenceScorer.mqh`. Modified: `Strategies/StrategyCandlestick.mqh`.
  - **A2 — Momentum v2.0:** MACD histogram confirmation, ADX strong trend filter (ADX > 25), pullback entry mode (EMA pullback within 0.5×ATR), freshness confidence modifier (+10%), volume confidence modifier (+8%). File: `Strategies/SimpleMomentumStrategy.mqh`.
  - **A3 — Volatility Breakout v2.0:** TTM Squeeze detection (BB inside KC = squeeze active, breakout on BB exit), ADX rising filter (ADX slope > 0), breakout retest entry, breakout failure reversal (counter-direction at 0.65 confidence). File: `Strategies/VolatilityBreakoutStrategy.mqh`.
  - **A4 — Mean Reversion v2.0:** Stochastic extreme confirmation (Stoch < 20 BUY, > 80 SELL), Hurst regime lockout (H < 0.45 → reject "MR_HURST_NOT_MEAN_REVERTING"), BB width filter (BB width < 20th percentile), no-divergence check, dynamic TP. Hurst engine injection via SetHurstEngine() (pointer-based, migrated from index-based). File: `Strategies/MeanReversionStrategy.mqh`.
  - **A5 — Statistical Arbitrage:** New strategy for pair trading via Python Bridge. OU half-life filter (half-life < 50 bars), z-score detection (entry at |z| > 2.0, exit at |z| < 0.5). OU engine injection via SetOUEngine(). MEAN_REVERSION_CLUSTER, weight 1.5. Conditionally registered when Python Bridge is connected. File: `Strategies/StatisticalArbitrageStrategy.mqh`.
  - **B1 — Regime Weight Wiring:** CEnterpriseStrategyManager reads CRegimeEngine weight multipliers via GetRegimeCategoryMultiplier(). Regime category weights applied to strategy weights before consensus quorum. File: `Core/Management/EnterpriseStrategyManager.mqh`.
  - **B2 — VPIN Toxicity Integration:** VPIN toxicity gating in consensus: VPIN_EXTREME blocks all entries (consensus veto), VPIN_HIGH reduces strategy weights by 50%, VPIN_MEDIUM reduces strategy weights by 25%. File: `Core/Management/EnterpriseStrategyManager.mqh`.
  - **B3 — 0-100 Consensus Scoring:** rawConsensusScore = directionalQuality × supportRatio × 100, threshold = 60/100. Graduated scoring: 60-70 marginal (×0.75 sizing), 70-85 standard, 85+ strong (priority ranking boost). File: `Core/Management/EnterpriseStrategyManager.mqh`.
  - **B4 — OFI Regime Integration:** OFI confirms/contradicts regime category weights: aligned → 1.2× boost, contradicts → 0.7× penalty. Applied after regime weight wiring, before consensus scoring. File: `Core/Management/EnterpriseStrategyManager.mqh`.
  - **Engine Wiring:** EnterpriseStrategyManager VPIN/OFI wired from EA per-symbol loop. MeanReversion Hurst engine wired (pointer-based, migrated from index-based). StatisticalArbitrage OU engine wired from EA per-symbol loop. A5 registration with Python Bridge check. File: `MultiStrategyAutonomousEA.mq5`.
  - **New log signatures:** `[CANDLE_CONFLUENCE]`, `[MR-HURST-NOT-MEAN-REVERTING]`, `[MR-STOCH-NOT-EXTREME]`, `[MR-BB-WIDTH-HIGH]`, `[MR-DIVERGENCE-DETECTED]`, `[STATARB]`, `[TTM_SQUEEZE]`, `[BREAKOUT_RETEST]`, `[BREAKOUT_FAILURE_REVERSAL]`, `[CONSENSUS-SCORE]`, `[VPIN-HIGH]`, `[VPIN-MEDIUM]`, `[OFI-REGIME-BOOST]`, `[OFI-REGIME-PENALTY]`.
  - **Files Changed:** `Strategies/StrategyCandlestick.mqh`, `Strategies/CandlestickFiles/DojiDetector.mqh`, `HammerDetector.mqh`, `StarDetector.mqh`, `HaramiDetector.mqh`, `ThreeSoldiersDetector.mqh`, `PiercingDetector.mqh`, `CandleConfluenceScorer.mqh` (new), `Strategies/SimpleMomentumStrategy.mqh`, `Strategies/VolatilityBreakoutStrategy.mqh`, `Strategies/MeanReversionStrategy.mqh`, `Strategies/StatisticalArbitrageStrategy.mqh` (new), `Core/Management/EnterpriseStrategyManager.mqh`, `MultiStrategyAutonomousEA.mq5`.
  - **Compilation:** 0 errors, 0 warnings.

- **Multi-Asset Class Profiler (Batch 103):** Full multi-asset support extending beyond Deriv synthetics to Forex, Metals, Indices, and Energies:
  - **CMultiAssetProfiler** in `Core/Processing/MultiAssetProfiler.mqh`: Central profiler using composition (wraps `CDerivAssetProfiler` internally). `ENUM_ASSET_CLASS` with 10 values (ASSET_FOREX through ASSET_UNIVERSAL). `SAssetProfile` with 14 fields. Detection priority: Deriv first, then Metals, Indices, Energies, Forex, Universal. Methods: `DetectAssetClass()`, `GetProfile()`, `GetMagicNumber()`, `GetAssetClassName()`, `GetFeatureSetSize()`, `GetPythonModelFamily()`, `GetDerivProfiler()`, `DerivFamilyToAssetClass()`, `PrintProfile()`.
  - **Instruments.mqh** extensions: `IsMetalsSymbolName()`, `IsIndicesSymbolName()`, `IsEnergiesSymbolName()`, `DetectAssetClassId()` (0-9), `GetInstrumentExecutionProfileName()` updated with FOREX/METALS/INDICES/ENERGIES.
  - **PythonBridge.mqh** extensions: `asset_class`/`asset_class_name` in `SPythonBridgeResponse`, `PredictMultiAsset()` convenience method, JSON payload includes both fields, `ParsePredictionResponse()` parses both.
  - **EnterpriseStrategyManager.mqh** extensions: `SetMultiAssetProfiler()`, `ApplyAssetClassEngineWeights()` with per-class multipliers (Forex: Trend 1.3x/VolBreakout 1.2x/MeanRevert 0.7x; Metals: VolBreakout 1.5x/MeanRevert 0.5x; Indices: MeanRevert 1.5x/VolBreakout 0.5x/Trend 0.8x; Energies: VolBreakout 1.4x/Trend 1.2x). Deriv symbols delegate to `ApplyFamilyEngineWeights()`.
  - **DiagnosticsManager.mqh** extensions: `SetMultiAssetProfiler()`, `[HEARTBEAT-ASSET-CLASS]` logging for non-Deriv symbols.
  - **MultiStrategyAutonomousEA.mq5** integration: `g_multiAssetProfiler` replaces `g_derivProfiler`, `InpMultiAssetProfilerEnabled` input, OnInit applies `SAssetProfile` for all symbols then Deriv-specific config, `GetFamilyPrediction()` uses `PredictMultiAsset()` with `DetectAssetClassId()`.
  - **Python data_pipeline.py** extensions: `build_forex_features()` (3), `build_metals_features()` (4), `build_indices_features()` (4), `build_energies_features()` (3), `get_asset_class_feature_count()`, `asset_class` param in `build_feature_matrix()`, `build_dataset_splits()`, `build_scaled_dataset_splits()`.
  - **Python zmq_server.py** extensions: `ASSET_CLASS_NAMES` (10 entries), `ASSET_CLASS_FEATURE_COUNTS`, `_load_asset_class_models()`, `_predict_asset_class()`, routing by `asset_class` 0-3.
  - **Python trainers** (4 new): `train_forex_lgbm.py`, `train_metals_catboost.py`, `train_indices_xgboost.py`, `train_energies_xgboost.py`.
  - **New log signatures:** `[HEARTBEAT-ASSET-CLASS]`, `[ASSET-CLASS-WEIGHT]`, `[MULTI-ASSET-PROFILER]`.
  - **Compilation:** Python 0 errors; MQL5 verified by code review.

- **Trend & S/R Strategy Enhancement (Batch 103 cont.):** Targeted fixes for Trend (45-55% → 55-65% win rate) and S/R bounce (50-60% → 60-70%):
  - **CTrendSignalEnhancer** in `Strategies/TrendFiles/TrendSignalEnhancers.mqh`: EMA slope momentum (3-bar slope > 0.1 ATR-normalized) and trend freshness scoring (consistency<10 → +15%, >50 → -10%).
  - **CSRSignalScorer** in `Strategies/SupportResistanceFiles/SRSignalScorer.mqh`: Weighted soft confluence scoring (0-100) replacing hard AND logic. Weights: PriceAtLevel=30, CandleRejection=25, EMAAligned=20, TrendlineConfluence=15, MultipleTouches=10. Threshold ≥60/100.
  - **CStrategyTrend v2.1** in `Strategies/StrategyTrend.mqh`: Hurst regime filter (H<0.50 → "TREND_HURST_MEAN_REVERTING"), VPIN toxicity filter (VPIN>0.5 → "TREND_VPIN_TOXIC"), EMA momentum bonus (+10%), freshness multiplier, trailing stop integration (breakeven at 1R + CTrendTrailingStop hybrid trail), asset-class ADX thresholds via `InitForAssetClass()`. Engine injection via `SetHurstEngine()`/`SetVPINFilter()` (not owned).
  - **CStrategySupportResistance** in `Strategies/StrategySupportResistance.mqh`: Hurst filter (H>0.55 in bounce → "SR_HURST_TRENDING_NO_BOUNCE"), VPIN filter (VPIN>0.5 → "SR_VPIN_TOXIC"), drawing throttle (every 5 bars). Engine injection via `SetHurstEngine()`/`SetVPINFilter()` (not owned).
  - **CSRBreakoutStrategy::FalseBreakoutDetected()**: 3-bar lookback for price breaking above resistance or below support then returning; ATR tolerance; counter-signal at 0.70 confidence.
  - **CSupportResistanceDetector::CalculateStrength()**: Exponential decay `0.99^barsOld` (capped 500 bars) replacing step-function.
  - **CADXPositionSizing::InitForAssetClass()**: Per-class ADX thresholds (Forex/Metals: 20/25/30/35, Deriv: 15/20/25/30, Indices: 18/23/28/33).
  - **CEnterpriseStrategyManager::GetStrategyByName()**: Returns `IStrategy*` by name. Used for `dynamic_cast` wiring.
  - **EA Wiring** (`MultiStrategyAutonomousEA.mq5`): Batch 103 block — iterates `g_mathEngineSymbols[]`, `GetStrategyByName()` + `dynamic_cast`, injects Hurst/VPIN. Emits `[BATCH103]`.
  - **New log signatures:** `[BATCH103]`, `TREND_HURST_MEAN_REVERTING`, `TREND_VPIN_TOXIC`, `SR_HURST_TRENDING_NO_BOUNCE`, `SR_VPIN_TOXIC`.
  - **Compilation:** MQL5 0 errors, 0 warnings.

- **ICT/SMC Strategy Overhaul (Batch 103 cont.):** Five new ICT/Smart Money Concepts strategies, two utility classes, and three component upgrades:
  - **CFVGScalperStrategy** in `Strategies/FVGScalperStrategy.mqh`: FVG gap detection with OB freshness filter + rejection candle confirmation. Finds strongest FVG imbalance zone, checks price inside FVG, confirms with bullish/bearish wick rejection. Confidence: base 0.55 + structure alignment (+0.08) + fast CHOCH (+0.07) + CISD displacement (+0.05), capped 0.95. SL 0.5×ATR beyond FVG boundary, TP 1.5R. Tier 2, STRUCTURE_CLUSTER, weight 1.8. Owned: `CImbalanceDetector`, `CMarketStructureAnalyzer(swings=3)`. Log: `[FVG-SCALPER]`. Enum: `STRATEGY_FVG_SCALPER=11`.
  - **CTurtleSoupStrategy** in `Strategies/TurtleSoupStrategy.mqh`: Liquidity sweep (Turtle Soup) detection via `CLiquidityDetector::DetectTurtleSoup()` + CHOCH/CISD confirmation + FVG confluence bonus. Confidence: base 0.50 + turtleSoup.confidence×0.15 + structure (+0.10) + FVG (+0.08) + CHOCH (+0.07), capped 0.95. SL beyond sweep extreme + 0.3×ATR, TP 2R. Tier 2, STRUCTURE_CLUSTER, weight 1.6. Owned: `CLiquidityDetector(atrMultiplier=5.0)`, `CImbalanceDetector`, `CMarketStructureAnalyzer(swings=3)`. Log: `[TURTLE-SOUP]`. Enum: `STRATEGY_TURTLE_SOUP=12`.
  - **CBreakerBlockStrategy** in `Strategies/BreakerBlockStrategy.mqh`: Failed OB → breaker conversion + price retest + opposing FVG + CISD displacement + structure alignment. Scans for unmitigated breaker OBs (OB_BREAKER_BULL/OB_BREAKER_BEAR). Confidence: base 0.55 + freshness > 0.7 (+0.08) + FVG (+0.10) + CISD (+0.05) + structure (+0.07), capped 0.95. SL 0.5×ATR beyond breaker boundary, TP 2R. Tier 2, STRUCTURE_CLUSTER, weight 1.7. Owned: `CMarketStructureAnalyzer(swings=3)`, `CAdvancedOrderBlockDetector`, `CImbalanceDetector`. Log: `[BREAKER-BLOCK]`. Enum: `STRATEGY_BREAKER_BLOCK=13`.
  - **CNYOpenGapStrategy** in `Strategies/NYOpenGapStrategy.mqh`: NY session open gap (NDOG) fade during 13:30-14:00 UTC. Gap size > 0.5×ATR(14,D1). Fades gap direction. Confidence: base 0.50 + FVG (+0.10) + large gap >1.0×ATR (+0.08) + near gap level (+0.07), capped 0.95. SL beyond gap extreme + 0.5×ATR, TP at previous close. Tier 3, STRUCTURE_CLUSTER, weight 1.3, session-limited. Synthetic symbol filter: skips Volatility/Boom/Crash/Jump/Step. Owned: `CSessionGapDetector(PERIOD_D1)`, `CImbalanceDetector`. Log: `[NYGAP]`. Enum: `STRATEGY_NY_OPEN_GAP=14`.
  - **CAsianRangeBreakStrategy** in `Strategies/AsianRangeBreakStrategy.mqh`: Asian session range (00:00-06:00 UTC) breakout during London open (07:00-07:30 UTC). Requires tight range < 0.8×ATR. Confidence: base 0.50 + range compression < 0.5×ATR (+0.10) + structure (+0.08) + fast CHOCH (+0.07), capped 0.95. SL at opposite range boundary, TP 2× range size. Tier 3, STRUCTURE_CLUSTER, weight 1.3, session-limited. Synthetic symbol filter: same as NY Open Gap. Owned: `CICTKillZones(sessionCount=2, autoDetect=true)`, `CMarketStructureAnalyzer(swings=3)`. Log: `[ASIANRB]`. Enum: `STRATEGY_ASIAN_RANGE_BREAK=15`.
  - **CPartialCloseManager** in `Strategies/UnifiedICTFiles/PartialCloseManager.mqh`: 3-step exit management — 50% close at 1R, breakeven move after 1R (SL → entry + 0.1% buffer, validates SYMBOL_TRADE_STOPS_LEVEL), ATR trailing after 2R (1.5×ATR(M5,14) from price, only moves favorably). Max 50 tracked positions with periodic compaction. Internal: `SPartialCloseState` per position. Log: `[PARTIAL-CLOSE]`.
  - **CTimeframeConfluence** in `Strategies/UnifiedICTFiles/TimeframeConfluence.mqh`: Multi-TF alignment scorer with 3 `CMarketStructureAnalyzer` instances (H1, M15, M5). Scoring: H1=40pts, M15=30pts, M5=30pts (max 100). `IsMajorityAligned()` requires ≥2/3 timeframes. Per-bar caching via `STFAlignmentCache`. Log: `[TF-CONF]`.
  - **AdvancedOrderBlocks.mqh** upgrade: `GetFreshness(int obIndex)` returns 0.0-1.0 freshness decay for order blocks. Used by BreakerBlockStrategy.
  - **MarketStructureAnalyzer.mqh** upgrade: 5 fast structure detection methods — `DetectFastCHOCH()`, `DetectWickBOS()`, `DetectCISDDisplacement()`, `GetSwingHighLevel()`, `GetSwingLowLevel()`. Used by FVGScalper, TurtleSoup, BreakerBlock, AsianRangeBreak.
  - **LiquidityDetector.mqh** upgrade: `SExternalLiquidityPool` struct + `DetectExternalSwingLiquidity()` for swing-based external liquidity detection. Used by TurtleSoupStrategy.
  - **EnterpriseStrategyManager.mqh** extensions: `m_maxStrategies` 20→25, `GetStrategyByName(const string name)` returning `IStrategy*`, 5 new `RegisterStrategy()` calls.
  - **Enums.mqh** additions: `STRATEGY_FVG_SCALPER=11`, `STRATEGY_TURTLE_SOUP=12`, `STRATEGY_BREAKER_BLOCK=13`, `STRATEGY_NY_OPEN_GAP=14`, `STRATEGY_ASIAN_RANGE_BREAK=15`.
  - **MultiStrategyAutonomousEA.mq5** additions: 5 new input parameters (`InpEnableFVGScalper`, `InpEnableTurtleSoup`, `InpEnableBreakerBlock`, `InpEnableNYOpenGap`, `InpEnableAsianRangeBreak`), `BuildStrategyFlags()` indices 12-16.
  - **New log signatures:** `[FVG-SCALPER]`, `[TURTLE-SOUP]`, `[BREAKER-BLOCK]`, `[NYGAP]`, `[ASIANRB]`, `[PARTIAL-CLOSE]`, `[TF-CONF]`.
  - **Compilation:** MQL5 0 errors, 0 warnings.

- **Deriv Asset Profiler & Family-Specific Engines (Batch 102):** Complete 18-family Deriv synthetic index auto-detection and per-family engine optimization system:
  - **CDerivAssetProfiler** in `Core/Processing/DerivAssetProfiler.mqh`: Central profiler auto-detects which of 18 Deriv index families a symbol belongs to via `DetectFamily(symbol)` using 13 family-specific symbol-name matchers from `Instruments.mqh`. Returns `SDerivProfile` with 20 fields: `family`, `familyName`, `spikeThreshold`, `atrCompressionRatio`, `atrMultiplierSL`, `atrMultiplierTP`, `hurstThreshold`, `riskPerTrade`, `magicOffset`, `maxDrawdownPercent`, `enableSpikeHunter`, `enableGridRecovery`, `enableHurstRegime`, `enableOUFilter`, `gridFactorATR`, `maxGridLevels`, `gridProgressionFactor`, `spikeCooldownSec`, `spikeWindowBars`. `ENUM_DERIV_FAMILY` has 19 values (18 families + DERIV_UNKNOWN). Methods: `DetectFamily()`, `GetProfile()`, `GetMagicOffset()`, `GetFamilyName()`, `PrintProfile()`.
  - **CGridRecoveryEngine** in `Core/Scalp/GridRecoveryEngine.mqh`: Grid recovery for mean-reverting synthetic families. `ENUM_GRID_PROGRESSION` supports Modified Martingale (`GRID_PROGRESSION_MARTINGALE`: lot × factor^level, factor=1.5) and Fibonacci (`GRID_PROGRESSION_FIBONACCI`: lot × fib(level)). `SGridRecoveryConfig` with 12 fields including `activationHurstThreshold` (0.45). Grid activates only when Hurst < threshold. Per-level SL = ATR × 1.5, TP = 0.5 × grid spacing. Magic offset 8000. Max 8 levels, 15% drawdown cap. Methods: `SetFamilyConfig()`, `SetHurstRegime()`, `AddSymbol()`, `ProcessTick()`, `Deinit()`.
  - **CATRScalpingEngine** in `Core/Scalp/ATRScalpingEngine.mqh`: ATR-based between-spike scalping for Jump, DEX, and Hybrid families. `SATRScalpingConfig` with 14 fields. Spike window avoidance: `NotifySpikeDetected(symbol)` and `SetSpikeInterval(symbol, intervalSec)` learn spike timing from `CSpikeHunterEngine`; avoids trading `spikeWindowAvoidMinutes` (5) before expected spikes. Entry: EMA fast/slow trend + RSI 30-70 + spread < 0.3×ATR. SL=1.5×ATR, TP=2.0×ATR. Magic offset 7000. Max 3 concurrent positions per symbol. Methods: `AddSymbol()`, `ProcessTick()`, `NotifySpikeDetected()`, `SetSpikeInterval()`, `Deinit()`.
  - **SSpikeHunterFamilyOverrides** in `Core/Scalp/SpikeHunterEngine.mqh`: Per-family spike parameter overrides with 8 `GetEffective*()` methods. Profiler-driven via `SetFamilyOverrides()`. CrashBoom: velocity 2.8×, Jump: 3.0×, Volatility: 3.5× (vs default 2.5×). Each family gets tailored SL/TP ATR multipliers, magic offsets (9000-9900), cooldowns, and minimum confluence thresholds.
  - **SSymbolRiskOverride** in `Core/Risk/UnifiedRiskManager.mqh`: Per-family risk and drawdown scaling. CrashBoom: 1.5% risk, 15% drawdown; Volatility: 1.0% risk, 10% drawdown; Step: 0.8% risk, 8% drawdown; Jump: 2.0% risk, 20% drawdown; DEX: 1.5% risk, 15% drawdown. Applied during pre-trade risk validation via `m_riskOverrides[]` array.
  - **CEnterpriseStrategyManager** integration: `SetDerivProfiler()` stores profiler reference; `ApplyFamilyEngineWeights()` adjusts strategy weights based on family profile.
  - **CTradeManager** integration: `SSymbolMagicOffset` struct for per-family magic offset logic in position tracking.
  - **CDiagnosticsManager** integration: `SetDerivProfiler()` enables `[HEARTBEAT-FAMILY]` logging with per-family engine status.
  - **Instruments.mqh** additions: 13 new family detection functions (`IsCrashBoomSyntheticSymbolName`, `IsVolatilitySyntheticSymbolName`, `IsStepSyntheticSymbolName`, `IsJumpSyntheticSymbolName`, `IsDEXSyntheticSymbolName`, `IsMultiStepSyntheticSymbolName`, `IsExponentialSyntheticSymbolName`, `IsHybridSyntheticSymbolName`, `IsRangeBreakSyntheticSymbolName`, `IsSkewStepSyntheticSymbolName`, `IsVolSwitchSyntheticSymbolName`, `IsDriftSwitchSyntheticSymbolName`, plus existing `IsStableSpreadSyntheticSymbolName`, `IsPairsArbitrageSyntheticSymbolName`, `IsSpotVolatilitySyntheticSymbolName`), updated `IsSyntheticIndexSymbolName()`, new `GetInstrumentExecutionProfileName()`.
  - **New Input Parameters:** `InpDerivProfilerEnabled` (default true), `InpGridRecoveryEnabled` (default true), `InpATRScalpingEnabled` (default true).
  - **Magic Number Allocation Table:**

    | Offset | Engine/Family |
    |--------|---------------|
    | 7000 | ATR Scalping Engine |
    | 8000 | Grid Recovery Engine |
    | 9000 | Spike Hunter (CrashBoom base) |
    | 9100 | Volatility family |
    | 9200 | Step family |
    | 9300 | Jump family |
    | 9400 | DEX family |
    | 9500 | MultiStep family |
    | 9600 | Exponential family |
    | 9700 | Hybrid family |
    | 9800 | RangeBreak family |
    | 9900 | SkewStep–SpotVolatility families |

  - **Family-Specific Risk Parameter Ranges:**

    | Family | Risk/Trade | Max Drawdown | SpikeHunter | GridRecovery | ATRScalping |
    |--------|:----------:|:------------:|:-----------:|:------------:|:-----------:|
    | CrashBoom | 1.50% | 15% | ✓ | ✓ | |
    | Volatility | 1.00% | 10% | | ✓ | |
    | Step | 0.80% | 8% | | ✓ | |
    | Jump | 2.00% | 20% | ✓ | | ✓ |
    | DEX | 1.50% | 15% | ✓ | | ✓ |
    | Hybrid | 1.50% | 15% | ✓ | | ✓ |
    | RangeBreak | 1.20% | 12% | ✓ | | |

  - **OnInit Integration Trace:**
    1. If `InpDerivProfilerEnabled`: profiler auto-detects family for each managed symbol, logs `[PROFILER-DETECT]`
    2. If `InpGridRecoveryEnabled` and symbol is synthetic: initialize `CGridRecoveryEngine` with default config, add family-enabled symbols with `SetFamilyConfig()` from profiler profiles, set Hurst regime from `CHurstEngine`
    3. If `InpATRScalpingEnabled` and symbol is synthetic: initialize `CATRScalpingEngine` with default config, add Jump/DEX/Hybrid symbols with spike intervals from `CSpikeHunterEngine`
    4. Pass profiler reference to `CEnterpriseStrategyManager::SetDerivProfiler()` for family-weight adjustment
    5. Pass profiler reference to `CDiagnosticsManager::SetDerivProfiler()` for `[HEARTBEAT-FAMILY]` logging
    6. Populate `SSymbolRiskOverride` in `CUnifiedRiskManager` from profiler profiles
    7. Populate `SSpikeHunterFamilyOverrides` in `CSpikeHunterEngine` from profiler profiles
    8. Populate `SSymbolMagicOffset` in `CTradeManager` from profiler profiles
  - **OnTick Integration Trace:**
    1. If `InpDerivProfilerEnabled` and `InpGridRecoveryEnabled`: `g_gridRecovery.ProcessTick(symbol, bid, ask)`
    2. If `InpDerivProfilerEnabled` and `InpATRScalpingEnabled`: `g_atrScalping.ProcessTick(symbol, bid, ask)`
  - **OnDeinit Integration Trace:**
    1. If `InpGridRecoveryEnabled`: `g_gridRecovery.Deinit()`
    2. If `InpATRScalpingEnabled`: `g_atrScalping.Deinit()`
  - **Compilation:** 0 errors, 0 warnings.

- **Deriv Python ML Stack Integration (Batch 102, cont.):** Family-aware feature engineering, training scripts, server routing, and MQL5 bridge protocol for per-family ML model selection:
  - **Python Feature Pipeline** (`Python/data_pipeline.py`):
    - `build_deriv_family_features(close, high, low, volume, family_id)` returns 26 feature columns (8 signal + 18 one-hot)
    - `get_feature_count(family_id)`: 57 for universal, 83 for Deriv families
    - `build_feature_matrix()` and all downstream functions accept `family_id` param
  - **Python Training Scripts** (4 new files):
    - `Python/train_deriv_catboost.py` — `--family-id` arg; family-specific hyperparams (CrashBoom/DEX: iterations=1500/depth=8/l2=5.0/class_weights; Hybrid: iterations=1200/depth=7)
    - `Python/train_deriv_xgboost.py` — `--family-id` arg; Step/MultiStep/SkewStep overrides (gamma=1.0, reg_alpha=0.5, reg_lambda=2.0)
    - `Python/train_deriv_lgbm.py` — `--family-id` arg; Volatility override (num_leaves=31, lr=0.02)
    - `Python/train_deriv_stacker.py` — `--family-id` arg; optional `--catboost-pkl`/`--xgboost-pkl`; bundle includes `family_id` and `n_base_models`
    - All auto-override seq_len=120 for Jump (3) and DEX (4)
  - **Python Server** (`Python/zmq_server.py` v1.1.0):
    - `FAMILY_IDS` dict (18 families), `_load_family_models()`, `_detect_family_from_symbol()`, `_predict_family()`
    - `GET /families`, `GET /family/{family_id}` endpoints
    - `/predict` accepts `family_id` and `symbol` fields; backward compatible
  - **MQL5 Bridge Protocol Changes**:
    - `DetectFamilyId(symbol)` in `Instruments.mqh`: priority-ordered cascade, returns 0-17 or -1
    - `CPythonBridge::Predict()` extended with `family_id` (default -1) and `symbol` (default "") params
    - `CPythonBridge::PredictFamily()` convenience method added
    - `SPythonBridgeResponse` extended with 8 new fields: `family_id` (int), `family_name` (string), `catboost_buy/sell`, `xgboost_buy/sell`, `onnx_buy/sell` (6 doubles)
    - `ParsePredictionResponse()` parses all new fields; backward compatible
    - `GetFamilyPrediction(symbol, features, size)` global helper in `MultiStrategyAutonomousEA.mq5`
  - **Integration Trace:**
    - On-demand: `GetFamilyPrediction(symbol, features[], size)` → `DetectFamilyId(symbol)` → `PredictFamily(features, size, family_id, symbol)` → HTTP POST to Python `/predict` → family-specific model inference → `SPythonBridgeResponse`
  - **Compilation:** 0 errors, 0 warnings.

- **Spike Hunter Engine for Synthetic CFD Indices (Batch 100):** New `CSpikeHunterEngine` in `Core/Scalp/SpikeHunterEngine.mqh` providing dedicated spike hunting for synthetic CFD indices:
  - **3-Layer Spike Detection:** Tick velocity ≥ 2.5× rolling average (Layer 1), direction accumulation ≥ 12 consecutive ticks in same direction (Layer 2), ATR compression ≤ 60% indicating price squeeze before spike (Layer 3). Requires 2/3 confluence to trigger.
  - **Symbol-Aware Direction Mapping:** PainX→SELL (crash indices spike down), GainX→BUY (boom indices spike up), Volatility Index→directional (follows detected direction), Jump Index→momentum continuation (follows pre-spike momentum).
  - **Independent Spike Trades:** Separate magic numbers using offset 9000 from base EA magic, allowing independent position tracking and risk management for spike-specific entries.
  - **Push Notification Alerts:** Mobile push notifications on spike detection, throttled at 120-second minimum interval to prevent alert spam during sustained volatile conditions.
  - **Long-Term Entry Cooldown:** 60-second cooldown after spike trade prevents re-entry into fading spikes, protecting against whipsaw losses in post-spike consolidation.
  - **Log Signatures:** `[SPIKE-HUNT-DETECTED]`, `[SPIKE-HUNT-TRADE]`, `[SPIKE-HUNT-SKIP]`, `[SPIKE-HUNT-ALERT]`, `[SPIKE-HUNT-ALERT-THROTTLED]`, `[SPIKE-COOLDOWN]`, `[SPIKE-HUNTER-STATS]`, `[SPIKE-HUNT-ENGINE]`.

- **Log-Evidence-Driven Fixes + Research Solutions (Batch 99):** Comprehensive fix of 7 critical/high/medium issues identified from live 2026-06-11 log analysis (33,800+ lines), plus 5 research-driven enhancements:
  - **L1 — S/R Lot Validation Fix (Critical):** StrategySupportResistance used hardcoded `lotSize = 0.01` which was rejected by CRiskValidationGate on PainX 400 (min lot 0.100) before CPositionSizer could round up. Fixed by using `SYMBOL_VOLUME_MIN` as the request lot size, deferring actual sizing to the risk manager's post-size phase. Unblocked 79 SELL signals at 95% confidence.
  - **L7 — Trend Bias Consensus Check (Critical):** All 6 executed trades were BUY despite TREND_BEARISH_STRONG. Added trend-direction bias check in CEnterpriseStrategyManager: when strong trend opposes consensus direction, effectiveQualityThreshold raised to 0.70. Prevents counter-trend consensus with weak support.
  - **L2 — ONNX CPU Fallback (High):** OnnxBrain never exited warm-up because CUDA initialization failed (no GPU, GPU=-1). Added `m_fallbackToCpu` flag; after CUDA failure, retries with `ONNX_USE_CPU_ONLY`. Subsequent calls skip CUDA entirely. ONNX now produces signals within 1-2 cycles.
  - **L3 — AI Degenerate Model Detection (High):** Transformer + Ensemble produced 100% BUY signals across all symbols in bearish market. Added rolling 20-prediction direction window to all 4 AI adapters. If direction ratio > 0.80, model flagged as degenerate and effective weight reduced by 50%. `IAIStrategy` interface extended with `IsDirectionDegenerate()` and `GetCalibratedWeight()`. CEnterpriseStrategyManager applies calibrated weights in consensus.
  - **L6 — Scalp Margin-Aware Lot Cap (High):** Scalp calculated 5.69 lots on $170 account, rejected by margin (19x) and volume limits (17x). Added `CapLotToMargin()` with 1.5x safety factor and `SYMBOL_VOLUME_MAX` cap. Minimum lot gate skips scalp if capped lot < `SYMBOL_VOLUME_MIN`.
  - **L4 — Hybrid Gate Relaxation (Medium):** AI confidence always 0.58-0.649 < 0.650 threshold while no indicator co-signed, blocking 35 signals. Added `g_cyclesSinceIndicatorSignal` counter; after 5 cycles without indicator signals, AI standalone threshold drops from 0.650 to 0.600. New inputs: `InpAIStandaloneRelaxedConfidence`, `InpHybridGateRelaxAfterCycles`.
  - **L5 — P&L-Adjusted Risk Budget (Medium):** Single PainX 400 position consumed 17%/33% budget, permanently blocking re-entries. Added `ApplyPnlRiskAdjustment()` in CUnifiedRiskManager: profitable positions reduce used risk by 50% of unrealized P&L, enabling re-entries.
  - **S1 — Bayesian Kelly Modifier:** `CBayesianKellyModifier` with Beta-Binomial conjugate priors (alpha=2.0, beta=2.0), quarter Kelly fraction (0.25). Self-contained win/loss tracking.
  - **S2 — Equity Curve Manager:** `CEquityCurveManager` tracks equity EMA (period=20), reduces position size to 50% when equity < EMA. Circular buffer, SMA-seeded.
  - **S3 — CVaR Portfolio Risk:** `CPortfolioRiskManager` extended with CVaR at 95% confidence, 10% max risk, 100-trade lookback. `IsCVaRLimitExceeded()` blocks trades exceeding CVaR limit.
  - **S4 — Commission-Aware Scalp Validation:** `CFastScalpEngine::IsScalpCostViable()` estimates commission from tick value profit/loss difference. Rejects if breakeven WR > 70% or total cost > 25% of TP.
  - **S5 — Async Trade Executor:** `CTradeManager` extended with `SendTradeAsync()`, `ProcessTradeTransaction()`, `CheckAsyncTimeouts()`. Max 10 pending, configurable timeout. Synchronous path remains default.

- **Monolith Decomposition & Risk Framework Completion (Batch 98):** Architectural refactoring completing the EA Overhaul Blueprint R6/R7 items and extracting 7 focused manager classes from the main EA monolith:
  - **R7 — Stateless Position Sizer:** `CPositionSizer::CalculateSize()` refactored to use `CalculateOptimalPositionSizeCore()` with explicit `riskPercent` parameter, eliminating the save/restore hack that temporarily mutated `m_params.riskPercent`. `CalculateBasePositionSizeWithRisk()` added to thread risk percent through to `CalculateRiskBasedSize()`. Zero shared-state mutation in the `CalculateSize()` path.
  - **R6a — CPositionLifecycleManager:** Extracted from `ManageOpenPositionsIfNeeded()` (~140 lines). `CheckSignalReversalExit()` implements SRE with breathing room, last-stand zone, and profit guard. `ManageBreakevenAndTrailing()` delegates to `CTradeManager::ManageAllPositions()` and applies safe mode partial profit for conservative tier. Configurable via `ConfigureSRE()` and `ConfigureLifecycle()`. `SetManagers()` takes parallel manager + symbol arrays.
  - **R6b — CDiagnosticsManager:** Extracted from heartbeat block (~215 lines). `EmitHeartbeat()` produces `[HEARTBEAT]`, `[HEARTBEAT-FUNNEL]`, `[CONVERSION-RATES]`, `[NO-SIGNAL-ALERT]`, `[RISK-BUDGET]` log lines. `EmitConsensusDiagnostics()` produces `[CONSENSUS-SNAPSHOT]`, `[STRATEGY-REJECTS]`, `[ROLE-CLUSTER]`, `[QUIET-REASONS]`, `[NO-SIGNAL-ALERT-CONSENSUS]`. Counter values passed via `UpdateCounters()`. `GetAggregatedConsensusDiagnostics()`, `GetAggregatedRoleClusterDiagnostics()`, `GetDominantConsensusCause()` moved from main EA into class.
  - **CUnprotectedPositionTracker:** Extracted from `AttemptUnprotectedPositionRemediation()` + 6 helpers (~220 lines). 3-attempt SL escalation: Escalation-1 (3x ATR), Escalation-2 (broker min distance via `SYMBOL_TRADE_STOPS_LEVEL`/`SYMBOL_TRADE_FREEZE_LEVEL`), Escalation-3 (unconditional close). Tracker arrays and last-attempt timestamp encapsulated.
  - **CSyntheticSpikeMonitor:** Extracted from spike alarm + trading pause + emergency drawdown functions (~190 lines). 7 global variables → class members. `ProcessTickSafety()`, `EvaluateSpike()`, `ActivatePause()`, `ReleasePauseIfExpired()`, `IsPaused()`, `HandleEmergencyDrawdown()`.
  - **CTradeAttributionManager:** Extracted from 27+ prediction/attribution/NN functions (~370 lines). Prediction position mapping, AI prediction mapping, AI pending request mapping, pending close profit tracking, NN diagnostics, cluster code utilities. Also integrated into `CExecutionOrchestrator`.
  - **CSymbolScanScheduler:** Extracted from 8 intrabar scoring/scheduling functions (~220 lines). 7 global variables → class members. `ScoreSymbolForIntrabar()`, `UpdateSymbolScanStateAfterDecision()`, `RebuildSymbolSchedulerState()`, `CountPendingNewBarScans()`.
  - **Anti-Martingale Dynamic Lot Scaling (Blueprint 4.3):** `CPositionSizer` applies `CPerformanceAnalytics::CalculateMomentumScale()` after tier cap in both `CalculateSize()` and `CalculateOptimalPositionSizeCore()`.
  - **CICTPositionSizer Risk Denominator Fix (Blueprint 4.5):** `GetRiskDenominator()` uses `MathMin(balance, equity)` instead of balance-only. Applied in `CalculateLotSize()`, `GetDailyDDUsedPct()`, `GetWeeklyDDUsedPct()`.
  - **Risk Percent Scale Consistency (Blueprint 10.4):** Added `RiskPercentToFraction()`, `FractionToRiskPercent()`, `IsValidRiskPercent()`, `ClampRiskPercentGlobal()` helpers in `Enums.mqh`. All risk constants annotated with scale documentation. No actual scale bugs found — codebase was already consistent.
  - **Cluster Rebalancing (Blueprint R4):** Conservative tier allocation updated from 30/30/30/10 to 40/25/25/10.
  - **Statistical Arbitrage Conditional Registration (Blueprint R5):** Registered in shadow mode only when `g_pythonBridge != NULL && g_pythonBridge.IsConnected()`. Assigned to MEAN_REVERSION_CLUSTER with PRIMARY_ALPHA role.
  - **Heartbeat Interval Configurable (Blueprint R1):** `InpHeartbeatInterval` input (default 60s, min 30s) gates heartbeat, NN health, and AI health log intervals.
  - **Total Impact:** ~1,180 lines removed from main EA monolith, 30+ global variables eliminated, 50+ inline functions replaced with class methods, 7 new focused manager classes created.

- **Execution Profitability Recovery (Batch 96):** Static audit and implementation pass for the reported live-trading failures:
  - **Trade execution failures:** `MultiStrategyAutonomousEA.mq5` previously retained only one `bestCandidate` per scan cycle and defaulted same-symbol capacity to one. The scan loop now stages all risk-reserved candidates, sorts by ranking, and attempts up to `InpMaxTradeSendsPerCycle`.
  - **Scalping/synthetic blockers:** synthetic classification now covers broker names such as `SFX Vol`, `FX Vol`, `SwitchX`, `PainX`, `GainX`, and `FlipX`; fallback stop sizing now applies the synthetic envelope to those instruments.
  - **Stop-loss mismanagement:** `CTradeManager` lifecycle edits are magic-filtered, SELL breakeven no longer places SL above entry, trailing stop activation waits for meaningful profit, and modification cooldown bypass only covers missing SL protection.
  - **Signal accuracy degradation:** `CNeuralNetworkStrategy::ResolveBarriers()` now writes directional classes directly instead of correctness-derived labels; AI adapter caches use a short same-bar TTL so tick-sensitive features do not stay stale for an entire bar.
  - **Concurrency regression:** the legacy hidden same-symbol portfolio cap was raised from 2 to 5 while the EA-owned input cap remains the primary runtime limit.
  - **Directional bias controls:** Mean Reversion and Volatility Breakout are included in governance/intrabar profiles, and SELL-capable strategies are no longer compile-blocked by stale `volumeRatio` names.

- **System Redesign + Scalping Engine (Batch 97):** Full implementation of EA_SYSTEM_REDESIGN.md Phase 1-5:
  - **Centralized Indicator Access:** 8 strategy files refactored to use `CIndicatorManager::Instance()` singleton, eliminating per-strategy indicator handle leaks and duplicate handle creation. Strategies affected: SimpleMomentum, MeanReversion, VolatilityBreakout, StrategyCandlestick, StrategyTrend, SupportResistanceDetector, SRTradingStrategies, TrendTrailingStop. All `IndicatorRelease()` calls removed; lifecycle now owned by `CIndicatorManager`.
  - **Conditional Diagnostic Logging:** `InpLogLevel` input (0-4) gates diagnostic verbosity across `CTradeManager`, `CPositionSizer`, and EA heartbeat paths. `SetLogLevel()` methods added to both classes. 50th-cycle diagnostics gated behind level ≥ 2.
  - **Rationalized Risk Defaults:** `baseRiskPerTradePercent` reduced from 10% to 1%, `maxRiskPerTradePercent` from 50% to 5%, `maxDailyRiskPercent` from 30% to 5%, `maxPortfolioRiskPercent` from 50% to 15%, `drawdownCriticalPercent` from 12% to 10%, `drawdownWarningPercent` from 6% to 5%. `MAX_RISK_PER_TRADE` constant reduced from 20 to 10.
  - **Unified PositionSizer Correlation:** `CPositionSizer` now delegates correlation calculations to `CCorrelationEngine` via `SetCorrelationEngine()`, replacing internal Pearson implementation. `CalculateCorrelation()` removed from PositionSizer; all correlation queries flow through the portfolio-level authority.
  - **Broker Trading Day Reset:** `CUnifiedRiskManager` daily risk counters now reset at configurable `m_tradingDayStartHour` (default 0) via `SetTradingDayStartHour()`. `IsNewTradingDay()` uses `m_lastTradingDayKey` string comparison instead of simple date check, ensuring consistent daily budget across brokers with non-midnight trading day starts.
  - **TickSafetyMonitor CAccountInfo Cache:** `CAccountInfo` moved from per-call local variable in `IsMarginHealthy()` to `m_accountInfo` member variable in `CTickSafetyMonitor`, eliminating repeated object construction on every tick.
  - **Kelly Criterion Position Sizing:** `POSITION_SIZE_KELLY` mode (enum value 5) added to `Enums.mqh`. `CPositionSizer::CalculateKellyFraction()` computes half-Kelly fraction with 25% cap from recent trade history win rate and avg win/loss ratio. Applied when `InpPositionSizeMode = POSITION_SIZE_KELLY`.
  - **Equity Compounding:** `CPositionSizer::CalculateCompoundingMultiplier()` applies sqrt upside / linear downside scaling so profitable periods compound aggressively while drawdown periods preserve capital conservatively.
  - **Tiered Correlation Response:** `CUnifiedRiskManager` now has `correlationReduceThreshold` (0.4) and `correlationBlockThreshold` (0.7) in `SUnifiedRiskConfig`. `ValidateTradeRequest()` applies graduated response: reduce position size at reduce threshold, block at block threshold.
  - **Daily P&L Loss Limit:** `dailyLossLimitPercent` added to `SUnifiedRiskConfig`. `CheckDailyLossLimit()` evaluates daily realized + unrealized loss. `m_dailyLossHaltActive` state prevents new entries. `m_dailyLossHaltDate` tracks halt date for next-day reset.
  - **Regime-Aware Strategy Weighting:** `CStrategyBase` gains `m_regimeDetailedType` and `m_strategyCluster` members. `SetRegimeContext()` and `SetStrategyCluster()` setters. `GetRegimeConfidenceMultiplier()` scales confidence by regime alignment: TREND_CLUSTER 1.5x/0.3x, MEAN_REVERSION_CLUSTER 1.5x/0.2x, STRUCTURE_CLUSTER 1.0x. Applied in `GetSignal()`.
  - **Volatility Direction Awareness:** `ENUM_VOLATILITY_DIRECTION` added to `Enums.mqh`. `GetVolatilityDirection()` classifies ATR as EXPANDING/CONTRACTING/STABLE. `GetVolatilityDirectionMultiplier()` applies 1.2x/0.8x/1.0x scaling. Applied in `GetSignal()`.
  - **Multi-Timeframe Confluence:** `GetNextHigherTF()` resolves next timeframe in MT5 hierarchy. `IsAlignedWithHigherTF()` checks EMA50 alignment on next higher timeframe. Counter-trend entries filtered when higher-TF momentum opposes. Applied in `GetSignal()`.
  - **Cross-Cluster Conflict Resolution:** `CEnterpriseStrategyManager` adds per-cluster conviction tracking (trendClusterBuyConviction/SellConviction, meanRevClusterBuyConviction/SellConviction). Cross-cluster conflict detection subtracts weaker cluster conviction (regime-weighted). `MathMax(0.0, ...)` guards prevent negative conviction.
  - **Mandatory SL Gate:** `CTradeManager::ExecuteMarketOrder()` now rejects trades with `stopLossPips <= 0.0` before any execution attempt.
  - **Min R:R Enforcement:** Default minimum R:R of 1:2 applied in `MultiStrategyAutonomousEA.mq5`; MEAN_REVERSION_CLUSTER uses 1:5 minimum. Signals below threshold rejected before risk sizing.
  - **Portfolio Profit Target:** `InpDailyProfitTargetPercent` and `InpProfitTrailFactor` inputs. `g_dailyProfitTargetReached`, `g_dailyProfitPeakPct`, `g_trailingProfitFloor`, `g_dailyTradingHalt` state variables. `CalculateDailyPnLPercent()` computes current P&L. Once target reached, new entries halt while existing positions remain managed.
  - **Auto Mode Switching:** `InpEnableAutoModeSwitch` input. `ENUM_AUTO_SWITCH_MODE` enum (CONSERVATIVE/AGGRESSIVE/EMERGENCY). `DetermineTradingMode()` switches based on drawdown and win streak. `CountConsecutiveWins()` tracks streak. `InpConservativeBaseRiskPct`, `InpAggressiveBaseRiskPct`, `InpModeSwitchDrawdownPct`, `InpModeSwitchWinStreak` configurable thresholds.
  - **Scalping Engine — ScalpSignalCache:** New file `Core/Scalp/ScalpSignalCache.mqh`. `SScalpIndicatorCache` struct with 13 indicator values + tick-level bid/ask/spread + state tracking + 7 handle references. `CScalpSignalCache` class with fixed-size array `m_cache[20]`. `Initialize()`, `UpdateOnNewBar()` (CopyBuffer path), `UpdateTickValues()` (SymbolInfoDouble only), `GetCache()`, `HasNewBar()`, `SetScalpSetup()`, `Cleanup()`. All handles from `CIndicatorManager::Instance()`.
  - **Scalping Engine — ScalpMomentumStrategy:** New file `Core/Scalp/ScalpMomentumStrategy.mqh`. Inherits `CStrategyBase`. Entry: EMA trend + pullback within 0.5 ATR + ATR expanding + spread < 0.3 ATR + RSI 40-60. Confidence base 0.60 max 0.90. SL=0.75×ATR, TP=1.5×ATR (1:2 R:R). Cluster: SCALP_CLUSTER.
  - **Scalping Engine — ScalpSpreadStrategy:** New file `Core/Scalp/ScalpSpreadStrategy.mqh`. Inherits `CStrategyBase`. Entry: wide spread + returning + price near EMA + RSI filter. Confidence base 0.50 max 0.90. SL=0.06×ATR, TP=0.3×ATR. Cluster: MEAN_REVERSION_CLUSTER.
  - **Scalping Engine — ScalpVolatilityBreakout:** New file `Core/Scalp/ScalpVolatilityBreakout.mqh`. Inherits `CStrategyBase`. Entry: ATR at 20-bar low + BB breakout + strong bar + RSI confirmation. Confidence base 0.55 max 0.90. SL=BB middle, TP=2×ATR. Cluster: SCALP_CLUSTER.
  - **Scalping Engine — FastScalpEngine Async:** `CFastScalpEngine` modified with `SScalpPendingAsync` struct, `m_asyncMode`/`m_maxLatencyMs`/`m_pendingAsync[]` members. `SetAsyncMode()`/`SetMaxLatencyMs()`/`OnAsyncOrderSent()`/`OnDealConfirmed()`/`CheckPendingAsyncOrders()` methods. `ExecuteScalpTrade()` modified for async path via `OrderSendAsync()`. `m_signalCache` member and `SetSignalCache()` added. `EvaluateScalpSignal()` reads from cache when available.
  - **Dual-Path OnTick Processing:** `MultiStrategyAutonomousEA.mq5` modified with `InpScalpAsyncMode`/`InpScalpMaxLatencyMs` inputs, `g_scalpCache` global, `#include ScalpSignalCache.mqh`, `g_lastScalpFastPathSecond` timing guard. `ProcessScalpFastPath()` function added for OnTick dual-path. `OnTradeTransaction()` routes scalp async confirmations. OnInit wiring for all new components. OnDeinit cleanup for `g_scalpCache`.
  - **Files Modified:** `MultiStrategyAutonomousEA.mq5`, `Core/Risk/UnifiedRiskManager.mqh`, `Core/Risk/PositionSizer.mqh`, `Core/Trading/TradeManager.mqh`, `Core/Strategy/StrategyBase.mqh`, `Core/Management/EnterpriseStrategyManager.mqh`, `Core/Risk/PortfolioRiskManager.mqh`, `Core/Utils/Enums.mqh`, `Core/Processing/TickSafetyMonitor.mqh`, `IndicatorManager.mqh`, `Strategies/SimpleMomentumStrategy.mqh`, `Strategies/MeanReversionStrategy.mqh`, `Strategies/VolatilityBreakoutStrategy.mqh`, `Strategies/StrategyCandlestick.mqh`, `Strategies/StrategyTrend.mqh`, `Strategies/SupportResistanceFiles/SupportResistanceDetector.mqh`, `Strategies/SupportResistanceFiles/SRTradingStrategies.mqh`, `Strategies/TrendFiles/TrendTrailingStop.mqh`, `Core/Scalp/FastScalpEngine.mqh`.
  - **Files Created:** `Core/Scalp/ScalpSignalCache.mqh`, `Core/Scalp/ScalpMomentumStrategy.mqh`, `Core/Scalp/ScalpSpreadStrategy.mqh`, `Core/Scalp/ScalpVolatilityBreakout.mqh`.

- **AI Modules Comprehensive Audit Implementation (Batch 92):** Complete implementation of all 25 AI audit findings:
  - **Memory & Numerical Stability:**
    - NaN/Inf validation expanded in all AI adapters with `IsValidConfidence()` checks
    - Ring buffer protection verified in `UncertaintyQuantifier.mqh`
    - `ValidateWeights()` method added checking all weights for NaN/Inf
    - 128-bit checksum using xorshift generators for checkpoint integrity
  - **Temperature Scaling & Confidence Calibration:**
    - `m_temperature` parameter added to `CNeuralCore::Softmax()`
    - `SetTemperature()`/`GetTemperature()` methods for runtime control
    - Temperature range clamped [0.1, 10.0] for stability
  - **Initialization Improvements:**
    - He initialization fixed with Box-Muller Gaussian transform
    - Scaling changed to `sqrt(2/(fan-in + fan-out))` for fan-average
    - `RandNormal()` function using standard normal distribution
  - **Conformal Prediction:**
    - Quantile formula fixed: `(1 - α) * (1 + 1/n)` for proper coverage
    - `GetLastUncertainty()` added to `CConformalPredictor`
  - **Regime Detection:**
    - EMA smoothing adjusted from 0.85 to 0.95 for faster response
    - `GetCurrentRegime()`/`GetRegimeState()` methods added
  - **Ensemble Improvements:**
    - Kelly weight clamping to [0.01, 2.0] range
    - Timeframe-aware cache prevents cross-timeframe pollution
    - Vote counting fixed to only increment on new inference
    - 24-hour rolling vote window reset added
  - **GOD TIER Architecture Refactoring:**
    - `CNeuralCore.mqh`: Core activations, loss functions, gradient operations
    - `CNeuralTrainingDataManager.mqh`: Training examples and barrier buffer
    - `CNeuralCheckpointManager.mqh`: Atomic checkpoint operations
    - `CSymbolEmbedding`: Learnable 32-dim symbol embeddings with classification
    - FFN residual compensation: `m_residualScale = 1/sqrt(2*layers)`
  - **IAIStrategy Interface:**
    - `IAIStrategy.mqh` created extending `IStrategy`
    - All 4 AI adapters implement IAIStrategy
    - Unified methods: `GetUncertainty()`, `IsModelHealthy()`, `IsTraining()`, etc.
  - **Files Modified:**
    - `AIModules/NeuralNetworkStrategy.mqh`: He init, temperature, checksum, regime
    - `AIModules/TransformerBrain.mqh`: Residual compensation, validation
    - `AIModules/EnsembleMetaLearner.mqh`: Kelly weight clamping
    - `AIModules/UniversalTransformerService.mqh`: Symbol embeddings
    - `AIModules/CNeuralCore.mqh`: NEW - Core neural operations
    - `AIModules/CNeuralTrainingDataManager.mqh`: NEW - Training management
    - `AIModules/CNeuralCheckpointManager.mqh`: NEW - Checkpoint I/O
    - `Core/Strategy/EnsembleAIStrategyAdapter.mqh`: Vote fix, IAIStrategy
    - `Core/Strategy/TransformerAIStrategyAdapter.mqh`: Vote fix, IAIStrategy
    - `Core/Strategy/OnnxAIStrategyAdapter.mqh`: Vote fix, IAIStrategy
    - `Core/Strategy/AIStrategyAdapter.mqh`: IAIStrategy implementation
    - `Interfaces/IAIStrategy.mqh`: NEW - AI strategy interface
  - **Validation evidence**: All 25 audit findings addressed, numerical stability ensured, no dumbing down
- **Enterprise Components 12-Layer Audit Fixes (Batch 91):** Comprehensive implementation addressing all audit layers:
  - **Critical audit findings addressed**:
    - Circular initialization dependency between RiskManager and PerformanceAnalytics → Added `SetPerformanceAnalytics()` for post-initialization linking
    - Memory leaks in PerformanceAnalytics from unbounded arrays → Implemented circular buffer (MAX_TRADES=1000)
    - Pipeline fail-closed logic missing → Added engine health monitoring and cache staleness validation
    - TickSafetyMonitor spread calculation for JPY pairs → Replaced point division with SymbolInfoInteger(SYMBOL_SPREAD)
  - **High-priority audit findings addressed**:
    - No engine health monitoring → Added `PerformHealthCheck()`, `IsPipelineHealthy()`, `GetEngineHealthStatus()`
    - No cache staleness validation → Added configurable stale cache detection
    - No initialization rollback → Added `RollbackPartialInitialization()` with component-specific cleanup
    - No detailed error messages → Enhanced all error logs to include GetLastError()
    - Hardcoded spread threshold → Made configurable in SymbolUniverseBuilder
    - No volume liquidity check → Added optional volume validation
    - No max strategy limit → Added m_maxStrategies=20 with validation
    - No quorum presets → Added Conservative/Balanced/Aggressive profiles
  - **Medium-priority audit findings addressed**:
    - No multi-timeframe support in BarProcessor → Added ConfigureMTF(), GetMTFTimeframe(), CheckNewBarMTF()
    - No backoff tier preservation → Added UpdateBackoffTierPreservation() and max preservation bars
    - No centralized error aggregator → Added SErrorAggregation with configurable window
    - No configurable verbosity → Added ENUM_LOG_VERBOSITY with 6 levels and LogVerbose()/LogDebug()
    - No shared engines for scalability → Created CSharedEngineManager for multi-symbol efficiency
    - No symbol prioritization → Added SSymbolPriority with spread/volume scoring
  - **Implementation details**:
    - Added `MAX_TRADES` constant to PerformanceAnalytics for buffer sizing
    - Implemented wrap-around indexing for m_tradeTimes, m_dailyReturns, m_equityCurve
    - Added `m_emergencyStopTime` and `m_emergencyStopDuration` to TickSafetyMonitor
    - Added `m_engineHealth` tracking to UnifiedSignalPipeline
    - Added `m_filterPreset` and ApplyFilterPreset() to UnifiedSignalPipeline
    - Updated SPerformanceMetrics to include sharpeRatioWithRiskFree
    - Enhanced CEnhancedErrorHandler with aggregation and verbosity
    - Created new SharedEngineManager.mqh with singleton pattern
    - Updated Enums.mqh with new ENUMs for presets and verbosity
  - **Files modified**:
    - `Core/Processing/TickSafetyMonitor.mqh`: Spread fix, margin checks, emergency auto-reset, tick gap detection
    - `Core/Monitoring/PerformanceAnalytics.mqh`: Circular buffer, risk-free rate, enhanced Sharpe ratio
    - `Core/Management/InitializationManager.mqh`: Timeout/retry, rollback, detailed errors
    - `Core/Risk/UnifiedRiskManager.mqh`: SetPerformanceAnalytics() method
    - `Core/Management/EnterpriseStrategyManager.mqh`: Max strategies, quorum presets
    - `Core/Pipeline/UnifiedSignalPipeline.mqh`: Health monitoring, cache stale, filter presets
    - `Core/Management/SymbolUniverseBuilder.mqh`: Configurable spread, volume check
    - `Core/Utils/Enums.mqh`: New ENUMs and updated SPerformanceMetrics
    - `Core/Utils/ErrorHandling.mqh`: Error aggregation, configurable verbosity
    - `Core/Processing/BarProcessor.mqh`: Multi-timeframe, backoff tier preservation
    - `Core/Management/SharedEngineManager.mqh`: NEW - Shared engine management
  - **Validation evidence**: All 12 audit layers addressed, critical/high findings fixed, compile passes
- **Visualization System Audit Fixes (Batch 90):** Complete overhaul of chart object management and visualization safety:
  - **Critical audit findings addressed**:
    - Hardcoded chart ID 0 in StrategyUnifiedICT → Fixed with `m_chartID` member initialized with `ChartID()`
    - StrategyUnifiedICT bypassed CChartDrawingManager → Converted to use `DrawOrderBlock` and `DrawFVG`
    - StrategyFibonacci bypassed CChartDrawingManager → Converted to use `DrawHorizontalLevel`
    - No global object counter for MT5 1000-object limit → Added tiered alerts at 800/900/950
    - Excessive object retention (maxObjectAge=500) → Reduced to 150
    - Debug logging ran in production → Wrapped in `if(m_config.enableDebugMode)`
    - Bitwise OR color operations caused inconsistent rendering → Replaced with explicit RGB values
    - No coordinate validation for invalid time/price → Added `ValidateTime`, `ValidatePrice`, `ValidateCoordinates`
  - **Implementation details**:
    - Added global object counter with `m_globalObjectCount`, `m_lastAlertLevel`, `m_lastCountLogTime` to `CDrawingCoordinator`
    - Implemented `SafeObjectsDeleteAll` with verification of deletion counts
    - Added per-strategy object limit enforcement with `maxObjectsPerStrategy`
    - Added dirty-flag optimization with `m_isDirty`, `SetDirty`, `IsDirty`, `ShouldRedraw`
    - Added `LogStatistics` method for periodic drawing metrics logging
    - Integrated drawing statistics into `VisualDashboard` with `UpdateDrawingStats` and `DrawLabelAt`
    - Added 5-minute cleanup interval in strategies calling `CleanupOldObjects`
  - **Files modified**:
    - `Strategies/StrategyUnifiedICT.mqh`: Fixed chart ID, standardized drawing, added cleanup
    - `Strategies/StrategyFibonacci.mqh`: Converted to use CChartDrawingManager
    - `Strategies/StrategySupportResistance.mqh`: Cleanup improvements
    - `Core/Visualization/DrawingCoordinator.mqh`: Global counter, SafeObjectsDeleteAll
    - `Core/Visualization/ChartDrawingManager.mqh`: Coordinate validation, explicit colors, dirty flags
    - `Core/Visualization/VisualDashboard.mqh`: Drawing statistics panel
  - **Validation evidence**: All visualization audit findings addressed, compile passes with 0 errors/warnings
- **Module 8 Python External Integration Fixes (Batch 85):** Complete overhaul of Python bridge reliability:
  - **Critical audit findings addressed**:
    - No connection timeout handling → Fixed with 5s request timeout in CPythonBridge and ZMQ poller timeout in Python server
    - No reconnection logic → Implemented exponential backoff reconnection (2s→30s)
    - No heartbeat monitoring → Added periodic health checks with configurable interval
    - No fallback mode → Added automatic local AI fallback when Python server unavailable
    - No version compatibility check → Added /version endpoint (1.0.0) and validation during OnInit()
    - No message serialization validation → Added JSON structure validation before parsing
  - **Implementation details**:
    - Created `Core/Utils/PythonBridge.mqh`: New class with complete connection lifecycle management
    - Added FastAPI HTTP server to `Python/zmq_server.py` on port 8000 (since MQL5 lacks native ZMQ)
    - Added input parameters to `MultiStrategyAutonomousEA.mq5`: endpoint, timeout, heartbeat interval, max reconnect attempts, backoff duration
    - Added real-time health monitoring dashboard via `[PYTHON-BRIDGE-DASHBOARD]` telemetry
    - Added version checking during EA startup and compatibility validation
  - **Files modified**:
    - `Python/zmq_server.py`: Added HTTP server, endpoints (/predict, /health, /heartbeat, /version), ZMQ poller timeout
    - `Core/Utils/PythonBridge.mqh`: New file (complete bridge implementation)
    - `Core/Utils/Enums.mqh`: Added ENUM_PYTHON_BRIDGE_STATE enum
    - `MultiStrategyAutonomousEA.mq5`: Added bridge initialization, version check, heartbeat checks, dashboard logging
  - **Validation evidence**: All Module 8 critical/medium findings addressed, compile passes with 0 errors/warnings
- **Module 4 Risk Management Fixes (Batch 85):**
  - Critical risk constants corrected: `MAX_RISK_PER_TRADE` reduced from 100.0 to 2.0, `MAX_TOTAL_RISK` reduced from 100.0 to 10.0 in `Core/Utils/Enums.mqh`
  - Safe default risk values set in `CUnifiedRiskManager`: 2% per trade, 6% daily, 10% portfolio when config values are invalid or non-positive
  - Currency conversion implemented in `CPositionSizer::CalculateRiskPerLot()` for accurate position sizing across non-USD accounts
  - Margin safety buffer increased from 5% to 20% (uses max 80% of free margin) for volatile period protection
  - Minimum price threshold added to volatility adjustment to prevent exaggerated risk on low-priced symbols
  - Enhanced emergency drawdown stop with ATR volatility checks and warnings in `MultiStrategyAutonomousEA.mq5`
- **Module 4 Risk Management Fixes (Batch 85):**
  - Critical risk constants corrected: `MAX_RISK_PER_TRADE` reduced from 100.0 to 2.0, `MAX_TOTAL_RISK` reduced from 100.0 to 10.0 in `Core/Utils/Enums.mqh`
  - Safe default risk values set in `CUnifiedRiskManager`: 2% per trade, 6% daily, 10% portfolio when config values are invalid or non-positive
  - Currency conversion implemented in `CPositionSizer::CalculateRiskPerLot()` for accurate position sizing across non-USD accounts
  - Margin safety buffer increased from 5% to 20% (uses max 80% of free margin) for volatile period protection
  - Minimum price threshold added to volatility adjustment to prevent exaggerated risk on low-priced symbols
  - Enhanced emergency drawdown stop with ATR volatility checks and warnings in `MultiStrategyAutonomousEA.mq5`
- **Module 6 Audit Fixes Applied:**
  - Minimum live voters increased from 1 to 2 in `MultiStrategyAutonomousEA.mq5` (line 48)
  - Quorum threshold increased from 0.48 to 0.60 in `MultiStrategyAutonomousEA.mq5` (line 47)
  - Strategy weights rebalanced: UnifiedICT (2.2→1.2), UnicornModel (2.4→1.2), PowerOfThree (2.3→1.2), ElliottWave (1.0→0.0)
- `20260517.log` proves `INDICATOR_ONLY` and `AI_ASSISTED` sessions were truly active, not merely misread `AI_ONLY` runs.
- Indicator-only funnel evidence: `signals_generated=78`, `signals_after_pipeline=26`, `signals_after_quorum=0`; primary productive families were `Fibonacci` and `Support/Resistance`, while Unified ICT, Unicorn, Power of Three, Candlestick, Momentum, and Trend mostly abstained or filtered.
- AI-assisted funnel evidence: `signals_generated=16`, `signals_after_pipeline=8`, `signals_after_quorum=0`; Neural returned `NNAI_NO_SIGNAL` and ONNX stayed in `ONNX_WARMING_UP`, so AI added little predictive value in that sample and still had to be discounted as infrastructure abstention.
- The current code batch targets the observed failure surface directly: expose pipeline kill reasons, discount non-contributing denominator weight, and allow scalp/intrabar strategies to run on configured lower timeframes when attached to higher-timeframe charts.

## Runtime Lifecycle

### 1. OnInit
- Validate terminal and trading permissions.
- Initialize mandatory execution/risk/runtime systems.
- Emit explicit `[EXECUTION-MODE]` startup telemetry for shadow vs live posture.
- Start from live-capable authority-gated defaults: AI/ONNX enabled, global live execution allowed, high-confidence AI/ONNX warm-start enabled, two-voter ordinary quorum, and sparse one-voter intrabar admission disabled.
- Reject unsupported non-hedging account models before runtime ownership is established.
- Apply execution safety controls (fill mode, slippage, protective modify cooldown) before trade-manager bootstrap.
- Apply hard execution-cost controls (max pre-send spread and max signal-price drift) before trade-manager bootstrap.
- Initialize optional AI subsystems conditionally by flags and convert failures into readiness-state degradation instead of fatal startup aborts.
- Emit `[AI-TOPOLOGY]` so MT5-native voters, ONNX live voting, Python bridge expectations, and external LLM reasoning posture are visible from init logs.
- Emit `[RUNTIME-FINGERPRINT]` with requested and effective EA mode so active logs can distinguish `AI_ONLY` mode filtering from real indicator/hybrid underperformance.
- Bootstrap the shared universal transformer service before AI brains/adapters start symbol registration, while keeping the service lazy-safe for indirect runtime callers.
- Load ONNX scaler parameters from Common files when available so runtime normalization stays aligned with Python training.
- Initialize performance analytics before unified-risk bootstrap.
- Validate active symbols and emit `[ACCOUNT-CAPACITY]` affordability diagnostics before the first scan.
- Reject symbols with extreme spreads (>1000 points) during symbol validation to prevent wasted evaluation cycles.
- Build the active-only strategy registry, then create per-symbol managers and register only enabled strategies and enabled AI adapters.
- Resolve strategy-specific registration timeframes during manager bootstrap so configured scalp/intrabar modules can evaluate a lower timeframe than the attached chart when appropriate.
- Build symbol-class-specific strategy flags before manager bootstrap so synthetic symbols can use a leaner live roster than FX without violating per-symbol consensus ownership.
- Rebuild scheduler state only after manager bootstrap so symbol-bar times, intrabar timers, pending new-bar work, and scan-state backoff remain a single aligned authority.
- Run startup health checks validating AI subsystem components, Python bridge connectivity, risk manager initialization, and position state manager status before final initialization completes.
- Emit `[HEALTH-CHECK]` telemetry for each validated component and return `INIT_FAILED` if critical components fail.
- Treat curated mode as a baseline/default profile only; explicit strategy enables remain authoritative instead of being rewritten away at runtime.
- Registered AI strategies (Neural Network, Transformer, Ensemble, ONNX) now receive non-zero weights from `InpAIWeightMultiplier` during registry bootstrap, ensuring they can participate in live voting when enabled instead of being suppressed by zero weight.
- Reconstruct `[TRADE-STATE]` / cooldown timing from EA-owned history and open positions.
- Initialize `CTieredSignalValidator` and manager-side AI voting surfaces for multi-tier signal hierarchy.
- Prime one pending new-bar scan per validated symbol so startup cannot produce a fully idle manager fleet with zero first-pass evaluations.

### 2. Tick/Timer cycle
- Run `ProcessTickSafetyLoop()` on every tick.
- Run `ProcessTradingLogic()` on timer cadence as the heavy evaluation owner.
  - Run `ProcessScalpFastPath()` on every tick for tick-level cached-indicator signal evaluation (Batch 97).
- Maintain NN learning cycle with explicit mutation-gate evaluation so pseudo labels can update health metrics without automatically mutating weights.
- Enforce terminal connectivity gate before signal evaluation.
- Enforce deterministic separation between the tick-owned safety loop and the timer-owned heavy scan loop.
- Run deterministic unprotected-position remediation sweep before entry evaluation.
- Refresh runtime equity/drawdown metrics on both safety and timer paths.
- Manage open positions once per second through `tradeManager.ManageAllPositions(...)`.
- **Batch 82**: Triggers `ManageOpenPositionsIfNeeded` -> `SignalReversalExit` (SRE) checks -> `PositionLifecycleManager` (ATR Trailing/BE).
- Gate the generic EA-level lifecycle manager behind `InpEnablePositionLifecycleManager` so hidden tiny-point breakeven/trailing logic cannot prematurely close wider-structure trades by default.
- Detect synthetic-index tick-rate spikes and, on alarm, flatten positions plus activate a temporary trading pause.
- Keep symbol evaluation active during cooldown/capacity veto windows so blocked-entry behavior remains observable.
- Rotate symbol evaluation start index each cycle to reduce fixed-order concentration.
- Self-reconcile cadence scheduler state if any scheduler array drifts away from the active symbol set before new-bar detection.
- Detect new-bar events per symbol.
- Carry pending new-bar work across cycles and spend the per-cycle heavy-evaluation budget on those symbols before any intrabar work.
- Reserve the cycle-best candidate as a virtual position inside `CUnifiedRiskManager` while scan-time ranking is still active, then release that reservation after the cycle winner is executed or discarded.
- Run intrabar scans when eligible.
- Hybrid cadence is now the default live posture: `InpSignalScanOnNewBarOnly=false` keeps timed intrabar scans active unless operators explicitly force strict new-bar-only mode, and startup still emits `[CADENCE-WARNING]` when that override is active.
- The default intrabar symbol budget is widened to `4` so live synthetic verification spends more of the available cadence budget each cycle without fully unbounding scan cost.
- Batch 78 raises intrabar cadence/throughput further (`5s` scans, wider per-cycle budgets) so the EA behaves like a faster automated system while still preserving execution-cost and authority gates.
- Budget intrabar scans by symbol yield and apply per-symbol backoff after repeated low-yield or readiness-faulted intrabar passes.
- Emit heartbeat funnel and conversion-rate telemetry at configured diagnostics interval.

### 3. Signal path
- Manager consensus + confluence.
- Strategy `OnNewBar(...)` prepares per-bar state only; consensus owns the single authoritative `GetSignal(...)` invocation so bar-scoped signal state is not consumed twice.
- Manager applies role/cluster governance and evaluates quorum via normalized weighted conviction pooling.
- **Batch 82**: Relaxed strategy internal filters (ICT confluences 4->2, Trend minimum TF M30->M15, SR confidence 0.50->0.45).
- **USP Filter Logic**: Confidence bypass for neutral trends lowered to 0.82; opposing trend hard veto increased to 90 strength.
- **Authority Gate**: Solo indicator signals promoted to live if Confidence >= 0.78 and Quality >= 0.82.
- **Dynamic weight decay** (Batch 82): strategies filtering ≥ 15 consecutive cycles have live weight decayed by 5% rate; weight recovers when strategy votes again.
- Manager reduces denominator weight by contribution class before support-ratio math: infrastructure/warmup abstentions, pipeline-filtered packets, and ordinary raw-none cycles no longer count as full neutral voters against the few strategies that actually produced direction.
- Manager classifies intrabar strategies as `OFF`, `PROBE`, or `LIVE` before pipeline work is spent.
- Explicit intrabar eligibility now maps enabled strategies into real `LIVE` intrabar voting, so operator-facing `intrabar=true` settings match the runtime voter pool.
- Governance startup logs now mark disabled strategies as `INACTIVE` in the intrabar summary instead of implying they are live because a different profile left the raw input toggles enabled.
- Symbol-class profiles now shape live participation:
  - synthetic indices can suppress `Momentum` / `Trend` from the local manager roster when structure-capable strategies are enabled
  - the same synthetic lean profile keeps `Fibonacci` / `Elliott Wave` / `Support-Resistance` / `Unified ICT` intrabar `LIVE`, while `Candlestick` stays available for new-bar evaluation but is downgraded to intrabar `PROBE`
  - FX retains the broader balanced roster
  - synthetic ICT/Elliott higher-timeframe dependencies are lowered from FX-style `H4/D1` expectations to lighter `M15/H1/H4` ladders where appropriate
- Synthetic lean symbols now also receive dedicated sparse intrabar admission thresholds, so one-voter structure packets are evaluated against profile-aware quality floors instead of the same sparse-quality bar used for broader FX/balanced rosters.
- **Adaptive quorum thresholds** (Batch 82): manager calculates `effectiveQualityThreshold` and `supportFloor` based on actual active voter count:
  - 1 active voter: directional quality ≥ 0.40, support ≥ 0.15
  - 2 active voters: directional quality ≥ 0.48, support ≥ 0.30
  - 3+ active voters: directional quality ≥ standard threshold, support ≥ scan-mode floor
  - Prevents impossible quorum math where inactive strategies inflated weight pool and rejected legitimate votes.
  - Adaptive one-/two-voter quality thresholds now respect the current base quorum so user-lowered quorum profiles are not silently re-hardened by stale fixed fallback thresholds.
- Manager quorum requires directional quality, support-ratio floors, effective min voters, minimum ready-live-weight participation, and conflict-deadband separation.
- Manager can emit a separate `SPARSE_INTRABAR` decision class only when `InpAllowSparseIntrabarSingleVoter=true`; the default posture keeps this off and routes high-confidence AI-only packets through the live-authority gate instead.
- **Multi-Tier Signal Validation (Batch 60):**
  - Votes are processed through `CTieredSignalValidator` for tier-based hierarchy.
  - **Tiered Evaluation**: Groups strategies into Institutional (T1), Structure (T2), and Indicators (T3).
  - **Conflict Resolution**: Resolves tier-level contradictions (e.g., T2 agreement overriding T1 weak bias).
  - **Setup Quality & Reliability**: Integrates setup quality (0-1) and historical accuracy metrics into the final decision weight.
- **Batch 82**: Lowered confidence floors for all tiers (Tier 3: 0.62, Tier 2: 0.45, Tier 1: 0.25).
- **Detailed veto diagnostics** (Batch 82): manager emits specific veto codes with numeric evidence.
- Manager vote admission now uses the pipeline's effective confidence floor for the current evaluation, avoiding pipeline/quorum drift when regime-aware relaxation is active.
- Manager live vote influence is modulated by rolling strategy `healthScore` rather than treating every enabled strategy as equally trusted at all times.
- Manager emits consensus root-cause attribution snapshots for no-signal diagnostics.
- Manager emits strategy-level none-reason attribution for core curated contributors.
- Manager downgrades warmup, unavailable, invalid-handle, initialization, scaler, feature, and inference abstentions before ready-live-weight math so infrastructure faults do not look like useful strategy participation.
- Pipeline now includes deterministic regime/cost viability gate before validator.
- Pipeline now retains the rejecting filter name/reason and exposes it in manager summaries for filtered abstentions, making indicator-only and hybrid no-signal runs diagnosable from logs.
- Pipeline caches structural engine state once per symbol/timeframe/bar and carries a shared evidence snapshot (`readiness`, `context`, `cost`, readiness class, reuse/staleness`) forward through consensus and validation.
- Pipeline and validator both support bounded soft-pass behavior for near-threshold candidates when the broader evidence profile is strong.
- Pipeline attenuates admitted confidence after threshold passage using readiness/context/staleness evidence so weak packets cannot preserve inflated confidence downstream.
- `CRegimeEngine` may reuse a recent valid same-context snapshot on transient warmup / copy / handle-init faults and performs bounded handle reset after repeated data faults.
- `CVolatilityEngine` and `CRegimeEngine` now recover ATR/Bollinger inputs from raw rates when indicator buffers fault against mature series, preventing the pipeline from degrading to zero ATR during transient `BB_BUFFER_COPY_FAILED` / warmup loops.
- `CTrendEngine` now allows mature-series partial-readiness to proceed so bounded MA/ATR fallback logic can attempt recovery; it may still reuse a bounded last-good trend snapshot on transient MA/ATR copy faults and emits `[READINESS-STATE]` reuse telemetry.
- `CTrendEngine` now branches by instrument class: FX keeps ADX-backed trend modeling, while synthetic indices bypass ADX handle creation and derive trend state from MA structure/angle only, removing synthetic-only ADX readiness churn without changing FX behavior.
- Pipeline threshold adaptation now uses `CRegimeEngine` snapshot state and dedicated non-AI confidence floors instead of AI-threshold coupling.
- `CMarketAnalysis` now keeps bounded last-valid trend/volatility/momentum/ATR snapshots and reuses them on transient `4806/4807` copy faults instead of silently dropping those metrics to zero.
- Validation is now split by ownership:
  - manager owns structural admission (`confidence`, `confluence`, directional `quality`, support, effective minimum voters)
  - validator owns only exogenous market sanity (`spread`, `time`, `session`, `volatility`, cost viability) when manager-owned admission mode is enabled
- Validator profile inputs still exist by scan mode (new-bar vs intrabar), but in normal runtime they are telemetry/fallback surfaces rather than a second structural veto layer.
- Validator still consumes manager quorum facts (`effectiveMinVoters`, `directionalQuality`, `supportRatio`) together with conviction/readiness/context/cost evidence so exogenous validation telemetry stays aligned with the already-authoritative manager decision.
- Strategy overrides that bypass base-class `GetSignal(...)` now emit explicit decision tags, and manager defensively downgrades any remaining placeholder abstentions so they cannot silently dilute ready-live quorum math.
- `Momentum` can now be configured for scalp-continuation signals via `InpEnableMomentumScalping` and `InpMomentumScalpCooldownSeconds`; `InpMomentumScalpTimeframe` can register it on a lower timeframe than the attached chart. `InpCandlestickIntrabarTimeframe` provides the same lower-timeframe registration control for intrabar candlestick participation. These controls change only signal production cadence and leave risk ownership, execution ownership, and lifecycle ownership unchanged.
- Entry gates (cooldown, total-position cap, unprotected-position veto, per-symbol capacity) now apply after validation and before unified risk so approved-but-blocked signals are still logged.
- Live authority is applied per candidate before live send: `[LIVE-AUTHORITY]` decides live vs candidate-level shadow and scales risk; `[AUTHORITY-TRIAL]` records forward evidence; `[AUTHORITY-RESULT]` updates AI/ONNX/indicator/Elliott family statistics for promotion or demotion.
- Final validator ATR acquisition now resolves from the shared indicator handle first and then a raw-rate ATR fallback, preventing transient copy misses from forcing `Invalid ATR: 0.00000` vetoes on otherwise-valid packets.
- Final EA admission also applies ATR-ratio crisis gating (`ATR14/ATR50`) so volatility shocks can reject or down-scale otherwise valid entries before risk sizing.
- AI vote generation is same-bar cached:
  - neural votes reuse `GetNeuralSignalCached(...)`
  - transformer and ensemble adapters reuse cached inference results until the bar changes
  - failed feature-build/inference results are cached as `NONE` for the rest of the bar
- AI adapters now emit explicit decision reason tags on disabled, abstain, feature-fault, inference-fault, and signal paths, removing the old `UNTAGGED_NO_SIGNAL` blind spot from AI-enabled consensus traces.
- AI strategy adapters now support a unified `SetConfidenceThreshold(double)` interface for dynamic authoritative thresholding from the EA orchestrator, and the system now respects `InpAIConfidenceThreshold` as the authoritative floor across all modes, eliminating legacy hardcoded confidence caps.
- AI_ONLY mode is now strict: indicator strategies are filtered out at the strategy registry level, ensuring no indicator-based votes participate when the EA is in AI-primary posture.
- When configured indicator families are filtered out by `AI_ONLY`, runtime now emits `[MODE-MASK]` so those sessions are not misread as "indicator strategies voted badly."
- Python-side AI semantics are now explicitly separated in runtime docs and logs:
  - ONNX is the only Python-trained live-voter path currently wired into manager consensus
  - Python bridge endpoint inputs are telemetry/expectation surfaces only
  - external LLM remains a reasoning/adaptation sidecar, not a direct voter
- The ONNX runtime path is now repository-native: `Resources/model.onnx` is embedded into the EA, `COnnxAIStrategyAdapter` participates in symbol-scoped manager consensus, and `COnnxBrain` can arm a shadow handle for hot-swap evaluation from Common files.
- The offline ONNX training/export pipeline now lives under `Python/`, aligned to the same 55-feature contract used by `CAIFeatureVectorBuilder`.
- `CPipelineScaler` now bridges Python `StandardScaler` exports into MQL runtime inference, and `TrainingDataExporter.mq5` can export the same 55 features for parity validation through `Python/feature_crosscheck.py`.
- The Python stack now also includes CPCV validation, IC-gated promotion, DER++ replay helpers, LightGBM/stacker training, regime/turbulence utilities, and a ZMQ bridge surface for deeper AI upgrade phases.
- `StrategyUnifiedICT` now treats institutional references as first-class runtime inputs: monthly/quarterly highs-lows, NY midnight/quarter opens, anchored VWAP, cumulative-delta pressure, and propulsion/rejection/vacuum order-block variants all feed the same scoring, POI, and stop/TP path instead of existing as detached helpers.
- `CICTPositionSizer` now includes half-Kelly sizing caps from recent symbol-specific EA close history, and Elliott Wave confidence can now gain a harmonic PRZ cross-validation bonus through `CHarmonicScanner`.
- AI intrabar policy is now explicit instead of globally hard-coded `OFF`: `Neural Network AI`, `Transformer AI`, `Ensemble AI`, and `ONNX AI` each have their own intrabar eligibility input, allowing `AI_ONLY` and `HYBRID` to be tested as real timed intrabar modes.
- `CNextGenStrategyBrain` now follows a single local-transformer path with direct `CAIFeatureVectorBuilder` sourcing and no dead Python/cloud bridge branch.
- Duplicate component-local `SignalDiagnostics` sinks have been removed from Elliott, pipeline, and orchestrator paths so manager/runtime telemetry stays authoritative.
- **AI Feature Lifecycle (Batch 58):**
  - Neural network feature extraction now produces 44-dimensional vectors (25 original + 19 pattern-specific features)
  - Pattern-specific features include: Higher Highs/Lower Lows sequences, Support/Resistance touch counts, Fibonacci Retracement proximity, Pivot Point proximity, volume profile features, market structure features
  - Weight matrix dimensions updated to `W1[44][32]` to accommodate expanded input
  - All array allocations and loop bounds updated consistently to prevent array out of range errors
  - Training example struct `STrainingExample` now uses `inputs[44]` instead of `inputs[25]`
  - File I/O for checkpoint save/load updated to handle 44-element feature vectors
- **External LLM Lifecycle (Batch 58):**
  - Optional external LLM support via `CAIEngine` with configuration flag `useExternalLLM` (default `false`)
  - HTTP client for Ollama API communication initialized during `ConfigureExternalLLM()`
  - External LLM can be toggled at runtime via `SetExternalLLMEnabled(bool)`
  - Signal synthesis, trade explanation, risk assessment, and strategy weight reasoning methods available when external LLM is enabled
  - Feedback loop via `ProvideFeedback()` sends trade results to external LLM for learning
  - External LLM failures are logged but do not abort the EA; system degrades gracefully to internal AI only
  - Adaptation now performs throttled external reasoning capture when enabled, and the full lifecycle is surfaced under `[EXT-LLM]` telemetry instead of remaining a silent helper path
- **Multi-scale Attention Lifecycle (Batch 58):**
  - Transformer brain now initializes per-head scaling factors, time window sizes, and learning rates
  - Head-specific parameters enable differential pattern detection across short/medium/long horizons
- **Pattern Classifier Lifecycle (Batch 58):**
  - 10-class pattern classifier head initialized with Xavier initialization
  - Cross-entropy loss training for pattern recognition
  - Pattern classification runs alongside 3-class BUY/SELL/NONE predictions
- **Chart Visualization Lifecycle (Batch 58):**
  - Elliott Wave strategy draws comprehensive Fib target levels for all waves (W1-W5) with multiple ratios
  - Trend lines use thin dashed style (STYLE_DOT, width 1) with muted colors for cleaner appearance
  - ICT drawing colors (OB, FVG, Liquidity, BOS, CHOCH) reduced in intensity using 0x909090 color mask
  - SupportResistance strategy trendlines aligned to thin dashed style for consistency
  - All chart drawing elements use consistent thin dashed styling for improved clarity
- Risk gating (pre-size then post-size).
- Drawdown-aware size tapering now happens between those two phases: the raw `CPositionSizer` output is scaled by `CAIStrategyOrchestrator::GetDrawdownMultiplier()`, then the adjusted lot is re-submitted to unified risk for final approval.
- Risk gate now evaluates cluster governance (mutex + caps) using request context and open-position cluster tags.
- Portfolio correlation fallback uses bounded value (0.65, capped to `m_maxCorrelation`) when correlation data is unavailable, avoiding hard blocks while preserving safety.
- Recommended per-trade risk is now pressure-throttled before the final hard cap as daily and portfolio utilization rise, producing `[RISK-THROTTLE]` evidence ahead of a hard veto.
- Pipeline confidence gate emits threshold-source metadata and uses bounded weak-regime intrabar uplift.
- Trend ADX failures degrade to neutral/ranging context with bounded ADX-handle self-heal.
- ATR stop-distance fallback when indicator read fails.
- Risk-approved opportunities are staged as ranked candidates across the full symbol scan before shadow or live execution.
- Live execution captures broker receipt state, price/slippage/latency telemetry, and risk registration scales consumed entry budget by actual fill ratio.
- Live execution now blocks before send when quote spread or signal-price drift exceeds configured hard limits, emitting `[EXECUTION-BLOCKED]`.
- Post-entry lifecycle management now scales BE/trailing/partial-close thresholds against original stop distance, eliminating the previous fixed-pip asymmetry where wide-stop synthetic winners were harvested almost immediately while losers still paid the full original stop.
- Protective stop modifications now validate against executable quote side and retry once with extra cushion on `TRADE_RETCODE_INVALID_STOPS`, reducing live-management churn on fast synthetic symbols.
- Per-symbol capacity checks include explicit external-position block telemetry.

### 4. Post-trade path
- Transaction callback updates manager/orchestrator performance.
- Transaction callback records confirmed close results into `PerformanceAnalytics`.
- NN attribution maps prediction IDs and labels closes (online-training gate controlled).
- Trade outcome is routed to `CTieredSignalValidator` to update historical accuracy metrics per tier.

### 5. Housekeeping
- Position manager lifecycle actions (check market hours before closure/modification, block only when SYMBOL_TRADE_MODE_DISABLED).
- Tick safety / synthetic spike telemetry and trading-pause lifecycle logs are emitted outside the heavy scan path.
- Periodic telemetry logs, including `[AI-FEEDBACK]` performance summaries for adaptive-training health.
- Indicator cache release policy.
- Shutdown now emits `[TERMINATION-SNAPSHOT]` with final heartbeat counters before deinit cleanup.

### 6. OnDeinit
- Release managers and dynamic strategy allocations.
- Managers explicitly deinitialize owned strategies before deleting them to avoid teardown drift at shutdown.
- Deinitialize subsystems.
- Explicit `CIndicatorManager::DestroyInstance()`.
- Orchestrator report emission is single-source (destructor-owned) to avoid duplicate shutdown reports.
- **Memory Safety**: AI adapters now properly clean up transformer models in destructors.
- **Error Handling**: Enhanced validation in feature vector construction and attribution systems. Proactive readiness checks (`IsDataReady`) and indicator warmup verification (`BarsCalculated`) prevent invalid feature generation during symbol startup.

## Observability Surface
- Decision: `[SIGNAL]`, `[SIGNAL-REJECTED]`, `[SIGNAL-VALIDATED]` (`exogenous_quality` logged separately from consensus confidence)
- Multi-Tier: `[TIERED-VOTE]`, `[CONFLICT-RESOLUTION]`, `[SETUP-QUALITY]`
- System telemetry: `[EXECUTION-MODE]`, `[ACCOUNT-CAPACITY]`, `[TRADE-STATE]`, `[HEARTBEAT]`, `[HEARTBEAT-FUNNEL]`, `[CONVERSION-RATES]`, `[RISK-BUDGET]`, `[RISK-THROTTLE]`, `[RISK-VIRTUAL]`, `[LIVE-AUTHORITY]`, `[AUTHORITY-TRIAL]`, `[AUTHORITY-RESULT]`, `[CONSENSUS-QUORUM]`, `[CONSENSUS-VETO]`, `[CONSENSUS-ACTIVE]`, `[CONSENSUS-DIAG]`, `[CONSENSUS-ROOT]`, `[CONSENSUS-SNAPSHOT]`, `[CONSENSUS-STRATEGY]`, `[CONSENSUS-ROLE]`, `[CONSENSUS-CLUSTER]`, `[ROLE-CLUSTER]`, `[STRATEGY-REJECTS]`, `[PIPELINE-THRESHOLD]`, `[REGIME-STATE]`, `[VOLATILITY-FAULT]`, `[ATR-FALLBACK]`, `[TrendEngine][READINESS-FAULT]`, `[MARKET-ANALYSIS]`, `[COST-GATE]`, `[ENTRY-VETO]`, `[ENTERPRISE-BLOCKED]`, `[EXECUTION-BLOCKED]`, `[QUIET-REASONS]`, `[NO-SIGNAL-ALERT]`, `[SCAN-BUDGET]`, `[SCAN-PRIME]`, `[SCHEDULER-STATE]`, `[CADENCE-WARNING]`, `[MODE-MASK]`, `[SPIKE-ALARM]`, `[SPIKE-PAUSE]`, `[SCAN-CANDIDATE]`, `[SCAN-DECISION]`, `[TRADE-CONFIRMED]`, `[PYTHON-BRIDGE-DASHBOARD]`, `[DRAWING-STATS]`, `[DRAW-COORD]`
- Risk remediation: `[RISK-UNPROTECTED]`, `[CAPACITY-EXTERNAL]`, `[RISK-CLUSTER]`, `[RISK-MUTEX-BLOCK]`
- AI: `[AI-VOTE]`, `[NN-HEALTH]`, `[NN-MUTATION]`, `[AI-FEEDBACK]`, `[EXT-LLM]`
- Trade: `[SHADOW-TRADE]`, `[TRADE-SUCCESS]`, `[TRADE-ERROR]`, `[TRADE-EXECUTION]`, `[EXECUTION-RECEIPT]`, `[EXECUTION-TELEMETRY]`, `[FILL-DIFF]`
- **Batch 87 Execution Quality:** `[EXECUTION-QUALITY]`, `[EXECUTION-REPORT]`, `[SPREAD-COST]`, `[SMART-ROUTING]`
- **Batch 90 Visualization:** Drawing statistics dashboard on VisualDashboard
- Scalp: `[SCALP-SIGNAL]`, `[SCALP-EXEC]`, `[SCALP-ASYNC]`, `[SCALP-CACHE]`
- Auto mode: `[AUTO-MODE]`
- Profit target: `[PROFIT-TARGET]`
- Daily loss halt: `[DAILY-LOSS-HALT]`
- R:R rejection: `[RR-REJECTED]`

## 2026-03-31 AXIOM Refactor Trace
- Removed dead AI/control-flow weight:
  - `CNextGenStrategyBrain` no longer carries the dormant Python/cloud branch or cloud-status labeling
  - stale no-op lifecycle methods were removed from the transformer/ensemble/brain surface
- Stabilized AI hot paths:
  - `CMarketDataProcessor` now uses a ring buffer instead of shifting arrays on every update
  - `CUncertaintyQuantifier` and `CNeuralNetworkStrategy` now use ring-buffered histories instead of `Delete(0)` or heap-per-sample patterns
  - AI adapters now gate inference to one pass per bar
- Tightened AI ownership/failure boundaries:
  - optional AI brain/orchestrator/engine failures no longer kill the EA
  - adaptation sync and dashboard AI state are now gated by explicit readiness flags
- Tightened indicator lifecycle in clean detector paths:
  - `CSupportResistanceDetector` now caches its ATR handle across repeated detection/touch passes instead of recreating it inside hot methods

## Current Operational Constraints
- Persistent terminal sessions are preferred.
- Start tester on stable history symbol (`EURUSD.0`) when synthetic history is uncertain.
- Emergency drawdown flattening can run account-wide when configured (`InpEmergencyFlattenAllAccountPositions=true`).

## Build Note
- Compile helper: `sync_and_compile.ps1`
- Compile artifacts should be auto-cleaned after runs unless explicitly retained.
- **Code Quality**: Recent fixes address memory leaks, null pointer safety, bounds checking, and standardized constants across AI components.
- **Compilation**: Verified 0 errors, 0 warnings with all improvements integrated.
- **Batch 60 Verification**: Multi-tier signal validation architecture confirmed with 0 compilation errors.

## 2026-03-30 Support/Resistance & Trendline System Overhaul Trace
- `CTrendlineDetector` and `CSupportResistanceDetector` rewritten to map points cleanly off normalized ATR levels instead of hardcoded minimum pip parameters.
- Look-ahead bias safely removed. All logic checks intersecting S/R lines and Trendlines now query `bar[1]` to ascertain completed chart realities and ignore active-wick repainting.
- Indicator MT5 Chart memory heavily hardened via dynamic array bubble sorting in `StrategySupportResistance`, drawing only the top 6/8 power tiers instead of saturating the frontend with stale ghost levels.
- Lot computations (`CADXPositionSizing`) explicitly refactored to consume Tick Size and Tick Value for hyper-accurate price distance conversion against the active risk profile.
- Obsolete fast-decay and price-averaging node cluster bugs isolated and resolved in S/R memory structures.

## 2026-03-25 Efficiency + Conviction Trace
- `Core/Pipeline/UnifiedSignalPipeline.mqh` now caches structural engine context per symbol/timeframe/bar and emits a reusable evidence snapshot carrying `readinessScore`, `contextScore`, `costScore`, effective confidence floor, and bounded soft-threshold state.
- `Core/Signals/TimeframeConsistency.mqh` no longer neutralizes directional consensus through hot-path hedging prevention; timeframe conflict resolution remains authoritative without pre-emptively zeroing otherwise valid mixed-strategy output.
- `Core/Management/EnterpriseStrategyManager.mqh` now computes directional conviction from adjusted live weight (`base weight x role multiplier x rolling healthScore`) and requires minimum ready-live-weight participation before a direction can pass quorum.
- `Core/Signals/AdvancedSignalValidator.mqh` now consumes upstream decision-path evidence (`conviction`, `readiness`, `context`, `cost`, `diversity`, `freshness`) and allows bounded soft passes near confidence/confluence floors when the setup quality is strong.
- `MultiStrategyAutonomousEA.mq5` now stages all risk-approved opportunities as ranked candidates, emits `[SCAN-CANDIDATE]` / `[SCAN-DECISION]`, and executes the best candidate per cycle instead of the first acceptable symbol.
- `Core/Trading/TradeManager.mqh` now exposes execution receipts and `Core/Risk/UnifiedRiskManager.mqh` scales executed-risk registration by fill ratio, so partial fills do not overstate daily entry-budget consumption.
- `Core/Signals/SignalDiagnostics.mqh` now batches flushes so diagnostic file output no longer forces a disk flush on every event.

## 2026-02-24 Cleanup Trace
- Removed dead commented strategy stubs from `MultiStrategyAutonomousEA.mq5`.
- Removed orphan harmonic strategy component files under `Strategies/HarmonicFiles/`.
- Removed dead wrapper files carrying legacy `StrategySwing` naming:
  - `Core/Utils/File.mqh`
  - `Core/Trading/DealInfo.mqh`
  - `Core/Trading/HistoryOrderInfo.mqh`
  - `Core/Trading/PositionInfo.mqh`
- Pruned retired strategy enum references from `Core/Utils/Enums.mqh`.
- Removed unused legacy strategy configuration module `Config/StrategyConfig.mqh`.
- Normalized Unified ICT helper comments/diagnostics to remove legacy SMC-era naming.

## 2026-02-24 Throughput-Recovery Trace
- Added intrabar dynamic quorum controls and single-voter confidence floor controls in `EnterpriseStrategyManager`.
- Added explicit strategy-level intrabar eligibility assignment path for curated core contributors.
- Added manager-level consensus funnel snapshots and dominant-cause diagnostics (`[CONSENSUS-ROOT]`).
- Added per-strategy reject attribution counters and heartbeat aggregation (`[CONSENSUS-STRATEGY]`, `[STRATEGY-REJECTS]`).
- Hardened `TrendEngine` ADX handling with readiness checks, value-domain sanitation, neutral degrade, and bounded ADX handle reinit.
- Extended pipeline confidence filtering with bounded weak-regime intrabar threshold cap plus source-tag logging.
- Extended heartbeat with conversion funnel counters/rates and no-signal dominance alerting tied to consensus diagnostics.

## 2026-03-07 No-Trade Recovery Trace
- Refined `EnterpriseStrategyManager` intrabar dynamic quorum so it now keys off actual live contributors in the current cycle rather than the entire eligible live pool.
- Added explicit `[EXECUTION-MODE]` startup telemetry in `MultiStrategyAutonomousEA.mq5` to prevent shadow-mode sessions from being mistaken for execution failures.
- Initialized `PerformanceAnalytics` explicitly before `CUnifiedRiskManager` bootstrap to remove cold-start ambiguity in adaptive-risk wiring.
- Split non-AI signal confidence policy away from `InpAIConfidenceThreshold` by introducing dedicated pipeline and validator confidence floors in `MultiStrategyAutonomousEA.mq5`.
- Rewired `CUnifiedSignalPipeline` threshold adaptation to use `CRegimeEngine` snapshot state rather than `TrendEngine` neutral/warmup output.
- Added explicit `Trend` reject telemetry so primary-live starvation can be diagnosed from runtime logs instead of remaining silent.

## 2026-03-07 Execution-Safety Trace
- Switched `CTradeManager` market sends to synchronous execution by default.
- Reworked market send path so execution price and protective SL/TP are recalculated from current market data at submit time.
- Moved confirmed close analytics updates into `OnTradeTransaction` and strengthened `PerformanceAnalytics::RecordClosedTrade(...)`.
- Reconstructed `AdvancedPositionManager` partial-close and breakeven state for already-open positions using `POSITION_IDENTIFIER` plus history-derived entry volume.
- Rejected unsupported non-hedging account modes at startup and tightened symbol validation for close-only symbols and invalid volume-step specs.

## 2026-03-16 Timeframe + AI Feedback Trace
- Manager consensus now resolves mixed-timeframe conflicts using `CTimeframeConsistency`.
- Strategy `OnNewBar` dispatch uses each strategy's registered timeframe to prevent cross-timeframe misalignment.
- AI performance feedback now records prediction/outcome pairs using request-to-position mapping on live trades.

## 2026-03-24 Quorum Admission Alignment + Smoke Controls Trace
- Aligned `EnterpriseStrategyManager` vote admission with `UnifiedSignalPipeline`'s effective confidence floor so pipeline-approved relaxed-threshold signals remain eligible for timeframe consistency and quorum.
- Added opt-in intrabar eligibility controls for `Fibonacci` and `Support/Resistance` to support smoke tests that need the chain to reach validator/risk/execution without broadening production defaults.

## 2026-03-24 Startup State Recovery + Capacity Diagnostics + Regime Fault Resilience Trace
- Added startup reconstruction of `g_lastTradeTime` in `MultiStrategyAutonomousEA.mq5` using EA-owned history and open positions so inherited positions preserve cooldown state after restart/re-attach.
- Added `[ACCOUNT-CAPACITY]` startup diagnostics that compare free margin with estimated minimum-lot margin for each active symbol and warn when live mode cannot afford any configured symbol.
- Hardened `Core/Engines/RegimeEngine.mqh` to reuse recent valid snapshots on transient warmup / buffer-copy / handle-init faults and to emit bounded `[REGIME-STATE] HANDLE_RESET` self-heal telemetry after repeated data faults.

## 2026-03-24 Entry Gate Decoupling Trace
- Moved cooldown/position/protection/capacity enforcement to the post-validation pre-risk stage in `MultiStrategyAutonomousEA.mq5` so signal generation keeps running during blocked-entry windows.
- Added explicit `[ENTERPRISE-BLOCKED]` logs for approved signals that are suppressed before risk/execution.

## 2026-03-24 Consensus Veto + Validator Spread-State + Trend Readiness Trace
- Added explicit `[CONSENSUS-VETO]` telemetry so post-quorum timeframe-conflict and single-voter nullification is visible without reconstructing it from downstream absence.
- Changed `Core/Signals/AdvancedSignalValidator.mqh` spread-shock state from shared global runtime state to symbol-scoped runtime state, preventing cross-symbol spread contamination in validator decisions.
- Hardened `Core/Engines/TrendEngine.mqh` against mature-series negative `BarsCalculated(...)` states by emitting `[TrendEngine][READINESS-FAULT]` and performing bounded full-indicator-set reinitialization after repeated readiness faults.
- Preserved exact `PortfolioRiskManager` veto reasons through `RiskValidationGate` so `[RISK-CONTRACT]` reports concrete correlation / position-cap style causes instead of flattening them to generic manager-blocked text.

## 2026-03-16 Weighted Quorum + Live Strategy Promotion Trace
- Promoted all retained strategies to live primary voters by default (per-strategy inputs gate registration).
- Replaced binary count-based quorum with normalized weighted confidence quorum (`InpQuorumThreshold`, `InpMinLiveVoters`, per-strategy `InpWeight*`).
- Added per-evaluation quorum telemetry via `[CONSENSUS-QUORUM]`.

## 2026-03-25 Runtime Integrity + Lifecycle Trace
- Corrected same-bar structural cache replay in `Core/Pipeline/UnifiedSignalPipeline.mqh` so cached evaluations preserve the original engine-ready flags and neutral defaults when engines are not ready.
- Hardened pipeline bootstrap so missing diagnostics/protection/core engines now fail startup rather than silently degrading to a hollow filter path.
- Localized symbol-specific engine state:
  - `Core/Engines/LiquidityEngine.mqh` now uses the requested symbol for point/tolerance math
  - `Core/Engines/RegimeEngine.mqh` now clears spread-shock cooldown state on symbol/timeframe switches
- Aligned sizing lifecycle with shared indicators by routing `Core/Risk/PositionSizer.mqh` ATR reads through `IndicatorManager` when available.
- Extended the scan lifecycle with cycle-scoped attribution:
  - `[SCAN-NO-TRADE]`
  - `[RISK-CAP]`
  - expanded `[QUIET-REASONS]`
- Tightened execution lifecycle in `Core/Trading/TradeManager.mqh`:
  - preflight viability check before send
  - confirmed-fill classification instead of raw submit success
  - explicit `[EXECUTION-BLOCKED]` / `[EXECUTION-UNCONFIRMED]` telemetry when safe execution cannot be proven
- Verification:
  - compile passed with `0 errors, 0 warnings`
  - bounded MT5 shadow-launch attempt completed, but no fresh EA-level tester artifacts were emitted in this environment

## 2026-02-24 Strategy Betterment Trace
- Note: the soft-quarantine defaults recorded in this batch are historical; current default voting behavior is defined by the 2026-03-16 weighted quorum + live strategy promotion update.
- Added institutional strategy governance metadata (role, cluster, live-vote eligibility, shadow mode) to `EnterpriseStrategyManager` and exposed setter APIs by strategy name.
- Added soft-quarantine defaults in EA initialization:
  - primary live voters: `Momentum`, `Trend`, `Unified ICT`
  - feature/shadow-only by default: `Candlestick`, `Fibonacci`, `Elliott Wave`, `Support/Resistance`
- Added deterministic `Core/Engines/RegimeEngine.mqh` and integrated it into `UnifiedSignalPipeline` as a pre-validator regime/cost viability gate.
- Extended `SignalFilterSettings` with regime/cost controls (`enableRegimeCostGate`, `maxSpreadToAtrRatio`, `spreadShockCooldownSeconds`, `maxEntryRangeZScore`).
- Refactored momentum strategy to state+trigger gating (EMA state alignment + compression-to-break trigger) to reduce crossover spam.
- Simplified Unified ICT live decision path to falsifiable event tuple checks (structure break, displacement, mitigation/retest) with bounded event-quality scoring.
- Extended `STradeValidationRequest` with role/cluster/contributor context and compact cluster code.
- Added cluster-aware risk governance in `RiskValidationGate`:
  - same-symbol opposing-cluster mutex
  - per-cluster concurrent position cap
  - per-cluster projected risk cap
- Added runtime cluster-tagged trade comments (`K:T/R/S/N`) for deterministic cluster attribution on open positions.

## 2026-04-01 Default Runtime Efficiency Trace
- `default.log` carried two valid runtime signals:
  - repeated `TrendEngine` ATR readiness faults
  - repeated idle scan-budget passes
- The same log also diverged from current code defaults, so the remediation batch split into two tracks:
  - real hot-path fixes
  - explicit operator guidance that saved runtime state must be verified from startup logs
- Trend trace:
  - mature-series ATR faults no longer hard-pin the engine in false warmup
  - bounded ATR fallback now runs before reuse/neutral degradation
  - readiness degradation remains explicit in logs
- Scan trace:
  - `[SCAN-BUDGET]` now includes `active_work`
  - fully idle cycles skip the per-symbol loop
  - quiet-cycle attribution remains visible in heartbeat counters
- Governance/build trace:
  - corrected `Support/Resistance` intrabar probe mapping
  - repaired `StrategyElliottWaveEnhanced` line-style enum usage
  - removed local min-confidence shadowing in Elliott Wave strategy
  - compile verification finished cleanly with `0 errors, 0 warnings`

## 2026-04-07 Scan Budget + Registry + Diagnostics Debloat Trace
- `MultiStrategyAutonomousEA.mq5` now caps heavy evaluations with `InpMaxSignalEvaluationsPerCycle`, persists pending new-bar symbols across cycles, and spends the cycle budget on deferred new-bar work on those symbols before any intrabar work.
- The legacy `InpUseOrchestrator` surface has been removed; runtime registration now follows the active strategy registry only, so disabled curated strategies and disabled AI adapters do not enter manager pools, orchestrator identity maps, or weight summaries.
- `CTrendEngine` now distinguishes warmup, transient copy faults, handle faults, partial-readiness faults, and reused snapshots; partial readiness is allowed to proceed when the underlying series is mature, enabling MA/ATR fallback logic to attempt recovery instead of hard-failing, which reduces persistent readiness vetoes on synthetic indices where `BarsCalculated` may lag behind `Bars()`. cases.
- `Strategies/StrategyElliottWaveEnhanced.mqh`, `Core/Pipeline/UnifiedSignalPipeline.mqh`, and `Core/AI/AIStrategyOrchestrator.mqh` no longer allocate component-local `SignalDiagnostics` sinks; runtime observability is now concentrated in manager/runtime telemetry rather than duplicate per-component logs.

## 2026-04-01 Strategy Registry + AI Runtime Audit
- Added `ENUM_EA_MODE` and registry-backed activation via `CStrategyRegistry`.
- Startup now records the requested mode, resolved effective mode, and active indicator/AI family counts under `[STRATEGY-REGISTRY]`.
- Per-symbol manager construction is now registry-driven for:
  - retained indicator strategies
  - transformer adapter
  - ensemble adapter
  - neural adapter registration once the per-symbol NN exists
- Post-consensus audit trail now includes mode-specific admission:
  - candidate can be rejected for `hybrid_mode_alignment_missing`
  - candidate can be rejected for `indicator_confirmation_missing`
  - candidate can receive `[AI-MODE-BONUS]`
- Scheduler audit trail now includes bounded intrabar keepalive recovery so default hybrid cadence cannot permanently collapse to `intrabar_selected=0`.
- `CTrendEngine` audit trail now includes bounded MA fallback in addition to ATR fallback, keeping readiness degradation explicit without forcing repetitive full reinitialization.

### Batch 14: Synthetic Asset 24/7 Hardening (2026-04-08)
- Event: Expanded intrinsic synthetic filtering to PainX, SFX Vol, GainX, FX Vol, and FlipX.
- Implication: Core systems (AdvancedSignalValidator, TradeManager, MarketAnalysis) bypass native off-hours blocks to sustain execution on decentralized index regimes without false validation drops.

### Batch 64: Logical Error Audit & Defensive Programming Hardening (2026-04-15)
- **Risk Domain Hardening:** Fixed risk denominator calculation to handle negative balance/equity values in `RiskValidationGate.mqh`, preventing incorrect risk calculations during account drawdown. Added comprehensive parameter validation in `PositionSizer.mqh` for all sizing parameters (atrMultiplier, maxLotSize, minLotSize, correlationAdjustment). Implemented missing `ValidateClusterGovernance` method with proper cluster mutex and concurrent position validation.
- **Position Management Safety:** Fixed infinite loop risk in `AdvancedPositionManager::NormalizeCloseVolume` by adding iteration limit (100 iterations). Added handling for remaining volume below minimum lot size after partial close. Added validation for trailing stop distance and step to ensure positive values. Added validation for negative time values in time-based exit to ensure open time and max position hours are valid.
- **Indicator Management:** Increased MAX_INDICATOR_HANDLES from 200 to 500 to support multi-symbol setups. Added timeframe validation in `IsSymbolAvailable` to check if timeframe is within valid range (PERIOD_M1 to PERIOD_MN1). Added paramCount validation in handle methods to ensure correct parameter count is set before creating handles.
- **AI Module Robustness:** Added NaN validation in feature extraction in `NeuralNetworkStrategy.mqh`. Added handling for empty feature vectors with error logging. Added NaN handling in confidence calculations in `EnsembleMetaLearner.mqh`. Added null prediction handling in aggregation to prevent invalid predictions from affecting ensemble decisions. Cached MA handles in `AIFeatureVectorBuilder.mqh` to prevent duplicate handle creation.
- **Pipeline & Engine Reliability:** Added error handling for engine initialization failures in `UnifiedSignalPipeline.mqh` with logging for all engines. Added staleness validation in last good trend reuse logic in `TrendEngine.mqh` to prevent reusing trends from different symbol/timeframe contexts. Added symbol/timeframe mismatch validation in evidence caching to invalidate cache if context changed. Reset readiness fault counter on successful trend update.
- **Signal Validation:** Added input validation for confidence, quality score, and confluence in `AdvancedSignalValidator.mqh`. Added NaN and extreme value handling in quality score calculation. Removed redundant null check in `ValidateCorrelationLimits`.
- **Entry Point Robustness:** Added error handling for malformed symbol string parsing in `MultiStrategyAutonomousEA.mq5` with validation for empty input, split failure, and invalid symbol format.
- **Documentation Improvements:** Clarified MAX_RISK_PER_TRADE constant naming with comment explaining percent scale. Added documentation comment for GetRiskDenominator consistency across components.
- **Compile Verification:** All 34 fixes implemented with minimal, targeted changes preserving existing architecture. Generated comprehensive audit report at `AUDIT_REPORT.md`.
- **Files Modified:** 13 files across Risk, Trading, AI, Pipeline, Engines, Signals, Utils, and entry point.

### Batch 65: AI Diagnostic Recovery & Trade Activation (2026-04-16)
- **Root Cause Identified:** Traced lack of single-voter AI-only quorum to hardcoded thresholding, transformer bridge hard failure, and percentage/fraction mismatch in Drawdown and Risk configuration constraints.
- **Transformer Bridge Robustness:** Made transformer failures soft, utilizing 15 native technical features to sustain NN processing while reporting transformer failure statuses cleanly through `UniversalTransformerService.mqh`.
- **AI Threshold Adaptability:** Allowed `EnsembleAIStrategyAdapter.mqh` a specialized 0.15 exploration mode gate bridging initial zero-history model executions prior to adaptive training accumulation.
- **Manager Consensus Safety Net:** Introduced `effectiveMinVoters = 1` into the `CEnterpriseStrategyManager.mqh` logic strictly bounds by AI-only ecosystem footprints (`<= 3` strategies) blocking generic 2-voter hard floors from nullifying AI models.
- **Synthetic Symbol Volatility Exempted:** Resolved `0.70` ATR percentage checks universally vetoing extreme relative synthetic variations; synthetics now natively pierce volatility filter checks honoring organic Jump/Volatility index mechanics.
- **Risk Value Unification:** Hardened risk constants from literal `0.10/0.20` mappings to percentage mappings `10.0/20.0` explicitly satisfying percentage-expectant risk modules matching existing system patterns.
- **Compile Verification:** 0 errors, 0 warnings. Verified compilation via PS scripts confirming stable structure preservation.
- Batch 73 audit note:
  - Added two new manager-registered Tier-1 structure strategies: `CUnicornModelStrategy` and `CPowerOfThreeStrategy`.
  - Integrated `CISD` and `Turtle Soup` directly into the Unified ICT support stack.
  - Widened the canonical AI feature contract from 55 to 57 features; Python training now consumes exported MT5 feature columns when available so tick-derived features remain parity-safe.

### Batch 86: Module 7 Market Analysis & Visualization Fixes (2026-05-23)
- **Root Cause:** Module 7 audit identified three critical issues:
  1. Chart object limit violations - MT5's 1000 object limit could be exceeded, causing terminal crashes
  2. Regime detection overfitting - rapid regime flipping on noisy market data
  3. ATR calculation boundary errors - potential array out-of-bounds access in fallback calculations

- **Implementation Trace:**
  - **Chart Object Limit Enforcement:**
    - Modified `Core/Visualization/ChartDrawingManager.mqh`: Added `m_maxObjects` member (default: 900), implemented `CheckObjectLimitAndCleanup()` with LRU deletion, integrated into `PrepareSnapshotDraw()`
    - Modified `Core/Visualization/DrawingCoordinator.mqh`: Added global object tracking with `CheckGlobalObjectLimitAndCleanup()`
    - Modified `Strategies/StrategyUnifiedICT.mqh`: Added object limit check before drawing order blocks and imbalances
    - Modified `MultiStrategyAutonomousEA.mq5`: Integrated with `InpMaxVisualObjects` parameter (capped at 900)
  
  - **Regime Detection Robustness:**
    - Modified `Core/Engines/RegimeEngine.mqh`: Added `regimeConfidence` (0.0-1.0), `regimeStabilityBars`, and `confirmedState` requiring 3+ bars stability before confirmation
    - Enhanced `[REGIME-STATE]` logging to include confidence and stability metrics
  
  - **ATR Validation:**
    - Modified `Core/Engines/VolatilityEngine.mqh`: Added `ValidateAtrCalculation()` test function for runtime verification
    - Verified existing ATR calculations are safe with proper bounds checking

- **Validation Evidence:**
  - All critical and high-severity Module 7 findings addressed
  - Chart objects now capped at 900, preventing MT5 crashes
  - Regime detection now requires 3 bars stability before confirming state changes
  - ATR calculations verified safe against boundary errors

- **Files Modified:**
  - `Core/Visualization/ChartDrawingManager.mqh`
  - `Core/Visualization/DrawingCoordinator.mqh`
  - `Strategies/StrategyUnifiedICT.mqh`
  - `Core/Engines/RegimeEngine.mqh`
  - `Core/Engines/VolatilityEngine.mqh`
  - `MultiStrategyAutonomousEA.mq5`

### Batch 79: Weltrade Environment Consolidation & Micro-Account Support (2026-05-13)
- **Environment Discovery:** Hardened `sync_and_compile.ps1` to detect and prioritize `C:\Program Files\MT5 Weltrade` as the root directory, ensuring that `MetaEditor64.exe` and the standard MQL5 includes are mapped from the operator's active installation.
- **Risk Floor Lowering:** Adjusted `MIN_ACCOUNT_BALANCE` in `Core/Utils/Enums.mqh` from `$100.0` to `$1.0`. This modification allows the `RiskValidationGate` to process trades on $10 micro-accounts while still preserving a safety floor for margin calculation.
- **Aggressive-Ready Configuration:** Confirmed that `maxRiskPerTradePercent` is initialized to `100.0` in the EA orchestrator, allowing users to manually override conservative risk (0.75%) with aggressive settings (5-10%) suitable for $10 test accounts.
- **Validation:** Clean synchronization and compilation of `MultiStrategyAutonomousEA.mq5` and `TrainingDataExporter.mq5` to the Weltrade environment with 0 errors and 0 warnings.
