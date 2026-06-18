# Changelogs

## 2026-06-18 — Batch 104: SL/BE/Trailing + Chart Drawing Bug Fixes

### Modified Files (5)
- `Core/Trading/TradeManager.mqh` — Fixed broken breakeven/trailing logic: replaced inline `MoveToBreakeven()` logic with proper call to `CPositionLifecycleManager::MoveToBreakeven()`, removed double-gate requiring `profitPercent >= 0.3%` (impossible for forex), changed `activationPoints = distance` from `MathMax(step, distance)`, fixed double comparison checks in trailing activation
- `Core/Management/PositionLifecycleManager.mqh` — Fixed dead input parameters: `breakevenBuffer` and `trailingDistance` now properly passed through to internal methods instead of being ignored
- `Core/Visualization/ChartDrawingManager.mqh` — Fixed 3 critical drawing bugs: (1) Added `ChartRedraw(m_chartID)` to 14 drawing methods for visibility, (2) Fixed `DeleteOldObjects()` using seconds instead of bars for maxAge comparison — now uses `iBarShift()`, (3) `PrepareSnapshotDraw()` now returns bool and propagates coordinator refusal
- `Strategies/StrategySupportResistance.mqh` — Added symbol guard (`m_drawOnChartSymbolOnly`) to prevent drawing on wrong symbol, reduced drawing throttle from every bar to every 5 bars
- `Strategies/StrategyCandlestick.mqh` — Added symbol guard to prevent drawing on wrong symbol

### Bug Fixes (6)
| Issue | Root Cause | Fix |
|-------|------------|-----|
| Breakeven never triggering | Required `profitPoints >= 120` AND `profitPercent >= 0.3%` (double-gate, forex can't meet 0.3%) | Removed `profitPercent >= 0.3%` gate, only checks `profitPoints >= breakevenBuffer` |
| Trailing stop activation too high | `activationPoints = MathMax(step, distance)` requiring 300+ points | Changed to `activationPoints = distance` (120 points = 12 pips) |
| Chart objects invisible but in Object List | Missing `ChartRedraw()` in 14 drawing methods | Added `ChartRedraw(m_chartID)` to all affected methods |
| DeleteOldObjects() using wrong age unit | Used time difference (seconds) instead of bars | Replaced with `iBarShift()` for proper bars comparison |
| Objects drawn on wrong symbol | No symbol guard in S/R and Candlestick strategies | Added `m_drawOnChartSymbolOnly` check |
| S/R drawing spam | Drawing every bar without throttle | Reduced throttle to every 5 bars |

### Compilation Status
- MQL5: 0 errors, 0 warnings

## 2026-06-16 — Batch 103: Multi-Asset EA System

### New Files (5)
- `Core/Processing/MultiAssetProfiler.mqh` — CMultiAssetProfiler: 10-class multi-asset profiler (ENUM_ASSET_CLASS: FOREX, METALS, INDICES, ENERGIES, DERIV_CRASH_BOOM, DERIV_VOLATILITY, DERIV_STEP_JUMP, DERIV_RANGE, DERIV_HYBRID, UNIVERSAL), SAssetProfile with 14 fields, DetectAssetClass(), GetProfile(), GetMagicNumber(), GetAssetClassName(), GetFeatureSetSize(), GetPythonModelFamily(). Wraps CDerivAssetProfiler internally for fine-grained Deriv family detection.
- `Python/train_forex_lgbm.py` — LightGBM trainer for Forex (asset_class=0), 57+3=60 features, lr=0.025, num_leaves=31, n_estimators=800
- `Python/train_metals_catboost.py` — CatBoost+XGBoost trainer for Metals (asset_class=1), 57+4=61 features, CatBoost depth=6/iterations=1000 + XGBoost depth=5/estimators=800
- `Python/train_indices_xgboost.py` — XGBoost trainer for Indices (asset_class=2), 57+4=61 features, lr=0.025, depth=5, n_estimators=800
- `Python/train_energies_xgboost.py` — XGBoost trainer for Energies (asset_class=3), 57+3=60 features, lr=0.03, depth=6, n_estimators=600

### Modified Files (7)
- `Core/Utils/Instruments.mqh` — Added IsMetalsSymbolName(), IsIndicesSymbolName(), IsEnergiesSymbolName(), DetectAssetClassId() (returns 0-9), updated GetInstrumentExecutionProfileName() with FOREX/METALS/INDICES/ENERGIES
- `Core/Utils/PythonBridge.mqh` — Added asset_class/asset_class_name to SPythonBridgeResponse; extended Predict() with asset_class/asset_class_name params; added PredictMultiAsset() convenience method; JSON payload includes asset_class/asset_class_name; ParsePredictionResponse() parses both fields
- `Core/Management/EnterpriseStrategyManager.mqh` — Added SetMultiAssetProfiler(), ApplyAssetClassEngineWeights() with per-class multipliers (Forex: Trend 1.3x/VolBreakout 1.2x/MeanRevert 0.7x; Metals: VolBreakout 1.5x/MeanRevert 0.5x; Indices: MeanRevert 1.5x/VolBreakout 0.5x/Trend 0.8x; Energies: VolBreakout 1.4x/Trend 1.2x)
- `Core/Management/DiagnosticsManager.mqh` — Added SetMultiAssetProfiler(), [HEARTBEAT-ASSET-CLASS] logging for non-Deriv symbols (symbol, class name, atrSL, atrTP, risk%, engine enables)
- `MultiStrategyAutonomousEA.mq5` — Replaced g_derivProfiler with g_multiAssetProfiler; added InpMultiAssetProfilerEnabled input; OnInit applies SAssetProfile for all symbols then Deriv-specific config; sets both SetDerivProfiler() and SetMultiAssetProfiler() on managers; GetFamilyPrediction() uses PredictMultiAsset() with DetectAssetClassId(); zero remaining g_derivProfiler references
- `Python/data_pipeline.py` — Added build_forex_features() (3: spread_z, corr_proxy, carry), build_metals_features() (4: vol_of_vol, session_ny, trend_strength, vol_regime), build_indices_features() (4: overnight_gap, circadian, bb_width, vol_spike), build_energies_features() (3: inventory_proxy, seasonality, contango), get_asset_class_feature_count(); added asset_class param to build_feature_matrix(), build_dataset_splits(), build_scaled_dataset_splits()
- `Python/zmq_server.py` — Added ASSET_CLASS_NAMES dict (10 entries), ASSET_CLASS_FEATURE_COUNTS dict, asset_class_models dict, _load_asset_class_models(), _predict_asset_class() with ONNX+GBDT+stacking; _process_request() routes asset_class 0-3 to _predict_asset_class(); /predict and ZMQ pass asset_class through

### New Input Parameters (1)
- `InpMultiAssetProfilerEnabled` (bool, default true) — Enable/disable multi-asset class profiler

### New Log Signatures (2)
- `[HEARTBEAT-ASSET-CLASS]` — Per-asset-class engine status in heartbeat (non-Deriv symbols)
- `[ASSET-CLASS-WEIGHT]` — Strategy weight adjustment by asset class

### Asset Class Enumeration
| ID | Class | Feature Count | Magic Offset | Risk/Trade | ATR SL/TP |
|----|-------|:------------:|:------------:|:----------:|:---------:|
| 0 | FOREX | 60 | +7000 | 1.0% | 1.5/2.0 |
| 1 | METALS | 61 | +7100 | 0.75% | 2.0/2.5 |
| 2 | INDICES | 61 | +7200 | 0.75% | 1.8/2.2 |
| 3 | ENERGIES | 60 | +7300 | 1.0% | 2.0/2.5 |
| 4-8 | DERIV_* | 70 | +9000-9400 | varies | varies |
| 9 | UNIVERSAL | 57 | +0 | 1.0% | 1.5/2.0 |

### Feature Count Design
| Model Type | Feature Count | Features |
|------------|:------------:|----------|
| Universal | 57 | Base technical |
| Forex | 60 | 57 base + 3 forex-specific |
| Metals | 61 | 57 base + 4 metals-specific |
| Indices | 61 | 57 base + 4 indices-specific |
| Energies | 60 | 57 base + 3 energies-specific |
| Deriv Family-Specific | 70 | 57 base + 13 deriv-specific |

### Trend & S/R Strategy Enhancement (Batch 103 cont.)

#### New Files (2)
- `Strategies/TrendFiles/TrendSignalEnhancers.mqh` — CTrendSignalEnhancer: EMA slope momentum detection (3-bar slope > 0.1 ATR-normalized), trend freshness scoring (consistency<10 → +15%, >50 → -10%)
- `Strategies/SupportResistanceFiles/SRSignalScorer.mqh` — CSRSignalScorer: Weighted soft confluence scoring (PriceAtLevel=30, CandleRejection=25, EMAAligned=20, TrendlineConfluence=15, MultipleTouches=10; threshold≥60/100)

#### Modified Files (7)
- `Strategies/TrendFiles/ADXPositionSizing.mqh` — Added InitForAssetClass(int assetClass): per-class ADX thresholds (Forex/Metals: 20/25/30/35, Deriv: 15/20/25/30, Indices: 18/23/28/33)
- `Strategies/StrategyTrend.mqh` — v2.1: Hurst regime filter (H<0.50 → TREND_HURST_MEAN_REVERTING), VPIN toxicity filter (VPIN>0.5 → TREND_VPIN_TOXIC), EMA momentum bonus (+10% confidence), freshness multiplier, trailing stop integration (breakeven at 1R, CTrendTrailingStop hybrid trail), asset-class ADX thresholds via InitForAssetClass()
- `Strategies/StrategySupportResistance.mqh` — Hurst filter (H>0.55 in bounce → SR_HURST_TRENDING_NO_BOUNCE), VPIN filter (VPIN>0.5 → SR_VPIN_TOXIC), drawing throttle (every 5 bars)
- `Strategies/SupportResistanceFiles/SRTradingStrategies.mqh` — CSRBounceStrategy: replaced hard AND logic with CSRSignalScorer soft scoring (confidence=score/100.0); CSRBreakoutStrategy: added FalseBreakoutDetected() (3-bar lookback, ATR tolerance, counter-signal at 0.70 confidence)
- `Strategies/SupportResistanceFiles/SupportResistanceDetector.mqh` — Replaced step-function age penalty with exponential decay (0.99^barsOld, capped at 500 bars)
- `Core/Management/EnterpriseStrategyManager.mqh` — Added GetStrategyByName(const string name) returning IStrategy* (wraps FindStrategyIndexByName)
- `MultiStrategyAutonomousEA.mq5` — Batch 103 wiring block: dynamic_cast to CStrategyTrend/CStrategySupportResistance, SetHurstEngine()/SetVPINFilter() injection per symbol

#### New Log Signatures (4)
- `[BATCH103]` — Hurst/VPIN wiring confirmation per strategy/symbol
- `TREND_HURST_MEAN_REVERTING` — Trend signal rejected (Hurst < 0.50)
- `TREND_VPIN_TOXIC` — Trend signal rejected (VPIN > 0.5)
- `SR_HURST_TRENDING_NO_BOUNCE` — S/R bounce rejected (Hurst > 0.55 in bounce mode)
- `SR_VPIN_TOXIC` — S/R signal rejected (VPIN > 0.5)

#### Compilation Status
- MQL5: 0 errors, 0 warnings (fixed &-operator on pointer arrays)

### ICT/SMC Strategy Overhaul (Batch 103 cont.)

#### New Files (7)
- `Strategies/FVGScalperStrategy.mqh` — CFVGScalperStrategy: FVG gap detection + OB freshness filter + rejection candle confirmation. Confidence boosted by structure alignment (+0.08), fast CHOCH (+0.07), CISD displacement (+0.05). SL 0.5×ATR beyond FVG boundary, TP 1.5R. Min confidence 0.55.
- `Strategies/TurtleSoupStrategy.mqh` — CTurtleSoupStrategy: Liquidity sweep (Turtle Soup) detection via CLiquidityDetector + CHOCH/CISD confirmation + FVG confluence bonus. SL beyond sweep extreme + 0.3×ATR, TP 2R. Min confidence 0.50.
- `Strategies/BreakerBlockStrategy.mqh` — CBreakerBlockStrategy: Failed OB → breaker conversion + price retest + opposing FVG + CISD displacement + structure alignment. Uses OB freshness > 0.7 bonus (+0.08). SL 0.5×ATR beyond breaker boundary, TP 2R. Min confidence 0.55.
- `Strategies/NYOpenGapStrategy.mqh` — CNYOpenGapStrategy: NY session open gap (NDOG) fade during 13:30-14:00 UTC. Gap size > 0.5×ATR(14,D1). Confidence boosted by FVG confluence (+0.10), large gap >1.0×ATR (+0.08), near gap level (+0.07). SL beyond gap extreme + 0.5×ATR, TP at previous close. Synthetic symbol filtered (skips Volatility/Boom/Crash/Jump/Step). Min confidence 0.50.
- `Strategies/AsianRangeBreakStrategy.mqh` — CAsianRangeBreakStrategy: Asian session range (00:00-06:00 UTC) breakout during London open (07:00-07:30 UTC). Requires tight range < 0.8×ATR. Confidence boosted by range compression < 0.5×ATR (+0.10), structure alignment (+0.08), fast CHOCH (+0.07). SL at opposite range boundary, TP 2× range size. Synthetic symbol filtered. Min confidence 0.50.
- `Strategies/UnifiedICTFiles/PartialCloseManager.mqh` — CPartialCloseManager: 3-step exit management — 50% close at 1R, breakeven move after 1R (+0.1% buffer), ATR trailing after 2R (1.5×ATR from price). Max 50 tracked positions with periodic compaction.
- `Strategies/UnifiedICTFiles/TimeframeConfluence.mqh` — CTimeframeConfluence: Multi-TF alignment scoring (H1=40pts, M15=30pts, M5=30pts, max 100). Per-bar caching via STFAlignmentCache. IsMajorityAligned() requires ≥2/3 timeframes aligned.

#### Modified Files (4)
- `Strategies/UnifiedICTFiles/AdvancedOrderBlocks.mqh` — Added GetFreshness(int obIndex): returns 0.0-1.0 freshness decay for order blocks (Batch 103)
- `Strategies/UnifiedICTFiles/MarketStructureAnalyzer.mqh` — Added 5 fast structure detection methods: DetectFastCHOCH() (3-swing CHOCH), DetectWickBOS() (wick-based BOS), DetectCISDDisplacement() (CISD displacement), GetSwingHighLevel(), GetSwingLowLevel() (Batch 103)
- `Strategies/UnifiedICTFiles/LiquidityDetector.mqh` — Added SExternalLiquidityPool struct and DetectExternalSwingLiquidity() for swing-based external liquidity detection (Batch 103)
- `Core/Management/EnterpriseStrategyManager.mqh` — Increased m_maxStrategies 20→25; added 5 RegisterStrategy() calls for new ICT/SMC strategies; added GetStrategyByName() method returning IStrategy*

#### New Input Parameters (5)
- `InpEnableFVGScalper` (bool, default true) — Enable FVG Scalper strategy
- `InpEnableTurtleSoup` (bool, default true) — Enable Turtle Soup strategy
- `InpEnableBreakerBlock` (bool, default true) — Enable Breaker Block strategy
- `InpEnableNYOpenGap` (bool, default true) — Enable NY Open Gap strategy
- `InpEnableAsianRangeBreak` (bool, default true) — Enable Asian Range Break strategy

#### New Enum Values (5)
| Value | Name | Strategy |
|------:|------|----------|
| 11 | STRATEGY_FVG_SCALPER | FVG Scalper |
| 12 | STRATEGY_TURTLE_SOUP | Turtle Soup |
| 13 | STRATEGY_BREAKER_BLOCK | Breaker Block |
| 14 | STRATEGY_NY_OPEN_GAP | NY Open Gap |
| 15 | STRATEGY_ASIAN_RANGE_BREAK | Asian Range Break |

#### Strategy Registration
| Strategy | Tier | Cluster | Weight | Session-Limited |
|----------|:----:|---------|:------:|:--------------:|
| FVG Scalper | 2 | STRUCTURE_CLUSTER | 1.8 | No |
| Turtle Soup | 2 | STRUCTURE_CLUSTER | 1.6 | No |
| Breaker Block | 2 | STRUCTURE_CLUSTER | 1.7 | No |
| NY Open Gap | 3 | STRUCTURE_CLUSTER | 1.3 | Yes (13:30-14:00 UTC) |
| Asian Range Break | 3 | STRUCTURE_CLUSTER | 1.3 | Yes (07:00-07:30 UTC) |

#### New Log Signatures (5)
- `[FVG-SCALPER]` — FVG Scalper signal details
- `[TURTLE-SOUP]` — Turtle Soup signal details
- `[BREAKER-BLOCK]` — Breaker Block signal details
- `[NYGAP]` — NY Open Gap signal details
- `[ASIANRB]` — Asian Range Break signal details
- `[PARTIAL-CLOSE]` — Partial close execution and BE move
- `[TF-CONF]` — Timeframe confluence initialization/status

#### Compilation Status
- MQL5: 0 errors, 0 warnings
- Python: 0 errors (all 6 modules import cleanly)
- MQL5: verified by code review (no MetaEditor available)

## 2026-06-17 — Batch 103 (cont.): EA Enterprise Vision Implementation

### Strategy Enhancements (A1-A5)

#### A1: Candlestick v2.0
- **New Files (7):**
  - `Strategies/CandlestickFiles/DojiDetector.mqh` — CDojiDetector: Doji pattern detection (body/shadow ratio threshold)
  - `Strategies/CandlestickFiles/HammerDetector.mqh` — CHammerDetector: Hammer/Inverted Hammer pattern detection
  - `Strategies/CandlestickFiles/StarDetector.mqh` — CStarDetector: Morning/Evening Star pattern detection
  - `Strategies/CandlestickFiles/HaramiDetector.mqh` — CHaramiDetector: Bullish/Bearish Harami pattern detection
  - `Strategies/CandlestickFiles/ThreeSoldiersDetector.mqh` — CThreeSoldiersDetector: Three White Soldiers/Three Black Crows detection
  - `Strategies/CandlestickFiles/PiercingDetector.mqh` — CPiercingDetector: Piercing/Dark Cloud Cover pattern detection
  - `Strategies/CandlestickFiles/CandleConfluenceScorer.mqh` — CCandleConfluenceScorer: 0-100 confluence scoring across all pattern detectors, threshold ≥70

- **Modified Files (1):**
  - `Strategies/StrategyCandlestick.mqh` — v2.0: Integrated 7 new pattern detectors + CCandleConfluenceScorer; confluence score ≥70 required for signal; confidence scaled by score/100.0

#### A2: Momentum v2.0
- **Modified Files (1):**
  - `Strategies/SimpleMomentumStrategy.mqh` — v2.0: MACD histogram confirmation (MACD line above signal = BUY confirmation), ADX strong trend filter (ADX > 25 required for trend entries), pullback entry mode (EMA pullback within 0.5×ATR), freshness confidence modifier (recent signal boost +10%), volume confidence modifier (above-average volume boost +8%)

#### A3: Volatility Breakout v2.0
- **Modified Files (1):**
  - `Strategies/VolatilityBreakoutStrategy.mqh` — v2.0: TTM Squeeze detection (BB inside KC = squeeze active, breakout on BB exit), ADX rising filter (ADX slope > 0 required for breakout confirmation), breakout retest entry (price retests breakout level before entry), breakout failure reversal (failed breakout → counter-direction signal at 0.65 confidence)

#### A4: Mean Reversion v2.0
- **Modified Files (1):**
  - `Strategies/MeanReversionStrategy.mqh` — v2.0: Stochastic extreme confirmation (Stoch < 20 for BUY, > 80 for SELL), Hurst regime lockout (H < 0.45 → reject "MR_HURST_NOT_MEAN_REVERTING"), BB width filter (BB width < 20th percentile required), no-divergence check (price vs indicator divergence blocks entry), dynamic TP (TP adjusts by BB width percentile)

#### A5: Statistical Arbitrage (New Strategy)
- **New Files (1):**
  - `Strategies/StatisticalArbitrageStrategy.mqh` — CStatisticalArbitrageStrategy: Pair trading via Python Bridge, OU half-life filter (half-life < 50 bars required), z-score detection (entry at |z| > 2.0, exit at |z| < 0.5), MEAN_REVERSION_CLUSTER, weight 1.5, requires Python Bridge connection

### Consensus Engine Improvements (B1-B4)

#### B1: Regime Weight Wiring
- **Modified Files (1):**
  - `Core/Management/EnterpriseStrategyManager.mqh` — CEnterpriseStrategyManager now reads CRegimeEngine weight multipliers via GetRegimeCategoryMultiplier(); regime category weights applied to strategy weights before consensus quorum

#### B2: VPIN Toxicity Integration
- **Modified Files (1):**
  - `Core/Management/EnterpriseStrategyManager.mqh` — VPIN toxicity gating in consensus: VPIN_EXTREME blocks all entries (consensus veto), VPIN_HIGH reduces strategy weights by 50%, VPIN_MEDIUM reduces strategy weights by 25%

#### B3: 0-100 Consensus Scoring
- **Modified Files (1):**
  - `Core/Management/EnterpriseStrategyManager.mqh` — New consensus scoring: rawConsensusScore = directionalQuality × supportRatio × 100; threshold = 60/100 for consensus pass; replaces binary quorum with graduated quality scoring

#### B4: OFI Regime Integration
- **Modified Files (1):**
  - `Core/Management/EnterpriseStrategyManager.mqh` — OFI confirms/contradicts regime category weights: OFI aligned with regime → 1.2× boost on regime category multiplier; OFI contradicts regime → 0.7× penalty on regime category multiplier

### Engine Wiring (Completion)

- **Modified Files (2):**
  - `Core/Management/EnterpriseStrategyManager.mqh` — VPIN/OFI includes wired; GetRegimeCategoryMultiplier() integration; consensus scoring refactor
  - `MultiStrategyAutonomousEA.mq5` — EnterpriseStrategyManager VPIN/OFI wired from EA per-symbol loop; MeanReversion Hurst engine wired (pointer-based, migrated from index-based); StatisticalArbitrage OU engine wired from EA per-symbol loop; A5 strategy registration with Python Bridge check

### New Log Signatures (6)
- `CANDLE_CONFLUENCE` — Candlestick confluence score details
- `MR_HURST_NOT_MEAN_REVERTING` — Mean Reversion signal rejected (Hurst < 0.45)
- `TTM_SQUEEZE` — TTM Squeeze detection status
- `BREAKOUT_RETEST` — Breakout retest entry confirmation
- `BREAKOUT_FAILURE_REVERSAL` — Failed breakout reversal signal
- `CONSENSUS_SCORE` — 0-100 consensus scoring result

### Strategy Registration
| Strategy | Tier | Cluster | Weight | Notes |
|----------|:----:|---------|:------:|-------|
| Candlestick v2.0 | 3 | NONE | 1.0 | 7 detectors + confluence scorer |
| Momentum v2.0 | 2 | TREND_CLUSTER | 1.2 | MACD/ADX confirmation |
| Volatility Breakout v2.0 | 2 | SCALP_CLUSTER | 1.3 | TTM Squeeze |
| Mean Reversion v2.0 | 2 | MEAN_REVERSION_CLUSTER | 1.4 | Stochastic/Hurst/BB width |
| Statistical Arbitrage | 2 | MEAN_REVERSION_CLUSTER | 1.5 | Python Bridge required |

### Compilation Status
- MQL5: 0 errors, 0 warnings

## 2026-06-16 — Batch 102: Synthetic Index Trade Capture Optimization

### New Files (3)
- `Core/Processing/DerivAssetProfiler.mqh` — CDerivAssetProfiler: 18-family Deriv synthetic index auto-detection (ENUM_DERIV_FAMILY with 19 values including UNKNOWN), SDerivProfile with 20 fields, DetectFamily(), GetProfile(), GetMagicOffset(), GetFamilyName(), PrintProfile()
- `Core/Scalp/GridRecoveryEngine.mqh` — CGridRecoveryEngine: Hurst-activated grid recovery for mean-reverting families (Volatility, Step, StableSpread, MultiStep, Exponential, SkewStep, VolSwitch, DriftSwitch, Trek, Tactical, Derived), ENUM_GRID_PROGRESSION (Modified Martingale 1.5x factor, Fibonacci), SGridRecoveryConfig with 12 fields, SetFamilyConfig(), SetHurstRegime()
- `Core/Scalp/ATRScalpingEngine.mqh` — CATRScalpingEngine: ATR-based between-spike scalping for Jump/DEX/Hybrid families, SATRScalpingConfig with 14 fields, spike window avoidance (5-minute buffer), EMA trend + RSI filter, NotifySpikeDetected(), SetSpikeInterval()

### Modified Files (7)
- `Core/Scalp/SpikeHunterEngine.mqh` — Added SSpikeHunterFamilyOverrides struct with 8 GetEffective*() methods for per-family spike parameter tuning (velocity multipliers, ATR compression, SL/TP multipliers, cooldowns, confluence thresholds)
- `Core/Risk/UnifiedRiskManager.mqh` — Added SSymbolRiskOverride struct for per-family risk/drawdown scaling (CrashBoom 1.5%/15%, Volatility 1.0%/10%, Step 0.8%/8%, Jump 2.0%/20%, DEX 1.5%/15%)
- `Core/Management/EnterpriseStrategyManager.mqh` — Added SetDerivProfiler() and ApplyFamilyEngineWeights() for profiler-driven engine weight adjustment
- `Core/Trading/TradeManager.mqh` — Added SSymbolMagicOffset struct for per-family magic offset logic
- `Core/Management/DiagnosticsManager.mqh` — Added SetDerivProfiler() and [HEARTBEAT-FAMILY] per-family engine status logging
- `Core/Instruments/Instruments.mqh` — Added IsJumpSyntheticSymbolName(), IsStepSyntheticSymbolName() and family detection helpers for 18 Deriv families
- `MultiStrategyAutonomousEA.mq5` — Full integration: g_derivProfiler, g_gridRecovery, g_atrScalping globals; OnInit wiring (profiler init → engine config → risk overrides → trade manager magic offsets); OnTick processing (grid recovery tick, ATR scalping tick, spike notification); OnDeinit cleanup

### New Input Parameters (3)
- `InpDerivProfilerEnabled` (bool, default true) — Enable/disable Deriv asset profiler
- `InpGridRecoveryEnabled` (bool, default true) — Enable/disable grid recovery engine
- `InpATRScalpingEnabled` (bool, default true) — Enable/disable ATR scalping engine

### New Log Signatures (10)
- `[HEARTBEAT-FAMILY]` — Per-family engine status in heartbeat
- `[PROFILER-DETECT]` — Family detection result
- `[GRID-RECOVERY-ENTRY]` — Grid recovery position entry
- `[GRID-RECOVERY-LEVEL]` — Grid recovery level progression
- `[GRID-RECOVERY-CLOSE]` — Grid recovery position close
- `[GRID-RECOVERY-DRAWDOWN]` — Grid recovery drawdown warning
- `[ATR-SCALP-ENTRY]` — ATR scalping position entry
- `[ATR-SCALP-EXIT]` — ATR scalping position exit
- `[ATR-SCALP-SPIKE-WINDOW]` — ATR scalping spike window avoidance
- `[ATR-SCALP-COOLDOWN]` — ATR scalping cooldown active

### Magic Number Allocation
| Offset | Engine/Family |
|--------|---------------|
| 7000 | ATR Scalping |
| 8000 | Grid Recovery |
| 9000 | Spike Hunter (existing) |
| 9100-9900 | Per-family offsets (CrashBoom=9100, Volatility=9200, Step=9300, Jump=9400, DEX=9500, MultiStep=9600, Exponential=9700, Hybrid=9800, RangeBreak=9850, SkewStep=9900) |

### Compilation Status
- 0 errors, 0 warnings

## 2026-06-16 — Batch 102 (cont.): Deriv Python ML Stack Integration

### New Files (4)
- `Python/train_deriv_catboost.py` — Family-specific CatBoost trainer with `--family-id` (0-17), CrashBoom/DEX overrides (iterations=1500, depth=8, l2_leaf_reg=5.0, class_weights=[1.0,0.5,1.0]), Hybrid override (iterations=1200, depth=7), output `{prefix}_catboost.pkl`
- `Python/train_deriv_xgboost.py` — Family-specific XGBoost trainer with `--family-id`, Step/MultiStep/SkewStep overrides (gamma=1.0, reg_alpha=0.5, reg_lambda=2.0), output `{prefix}_xgboost.pkl`
- `Python/train_deriv_lgbm.py` — Family-specific LightGBM trainer with `--family-id`, Volatility override (num_leaves=31, learning_rate=0.02), output `{prefix}_lgbm.pkl`
- `Python/train_deriv_stacker.py` — Family-aware OOF Ridge stacker with `--family-id`, optional `--catboost-pkl`/`--xgboost-pkl` for expanded meta features (6→12→15 columns), bundle includes `family_id` and `n_base_models` metadata, output `{prefix}_stacker.pkl`

### Modified Files (3)
- `Core/Utils/Instruments.mqh` — Added `DetectFamilyId(symbol)` free function returning integer family ID (0-17) or -1, priority-ordered cascade matching `CDerivAssetProfiler::DetectFamily()` exactly (VolSwitch before Volatility, SkewStep/MultiStep before Step, DEX before Jump)
- `Core/Utils/PythonBridge.mqh` — Extended `SPythonBridgeResponse` with 8 new fields (family_id, family_name, catboost_buy/sell, xgboost_buy/sell, onnx_buy/sell); modified `Predict()` to accept `family_id` and `symbol` params; added `PredictFamily()` convenience method; updated `ParsePredictionResponse()` to parse all new fields; JSON payload now includes `family_id` and `symbol` when provided
- `MultiStrategyAutonomousEA.mq5` — Added `GetFamilyPrediction(symbol, features, featuresSize)` global helper that calls `DetectFamilyId()` + `PredictFamily()` for family-aware Python bridge predictions

### Previously Modified (Batch 102 Python Side — earlier session)
- `Python/data_pipeline.py` — Added `build_deriv_family_features()` (8 signal + 18 one-hot = 26 Deriv features), `get_feature_count()`, `family_id` param throughout pipeline; 57 features (universal) → 83 features (Deriv)
- `Python/train_model.py` — Added `--family-id` arg; Jump/DEX (family_id 3,4) auto-override seq_len=120
- `Python/zmq_server.py` — Full family-aware routing: `FAMILY_IDS` dict (18 families), `_load_family_models()`, `_detect_family_from_symbol()`, `_predict_family()` with dynamic seq_len/feat_count, `GET /families` and `GET /family/{family_id}` endpoints, `family_id`+`symbol` in `/predict` request; backward compatible with old `--patchtst-onnx/--lgbm-pkl/--stacker-pkl` args; version 1.1.0

### Feature Count Design
| Model Type | Feature Count | Features |
|------------|--------------|----------|
| Universal (Forex/Gold) | 57 | Base technical |
| Deriv Family-Specific | 83 | 57 base + 8 signal + 18 one-hot |

### Family ID Mapping (aligned with ENUM_DERIV_FAMILY)
| ID | Family | Prefix | seq_len |
|----|--------|--------|---------|
| 0 | CrashBoom | crashboom | 60 |
| 1 | Volatility | volatility | 60 |
| 2 | Step | step | 60 |
| 3 | Jump | jump | 120 |
| 4 | DEX | dex | 120 |
| 5-17 | (14 other families) | (see FAMILY_PREFIXES) | 60 |

### Compilation Status
- 0 errors, 0 warnings
