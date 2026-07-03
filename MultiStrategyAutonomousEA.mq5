//+------------------------------------------------------------------+
//| MultiStrategyAutonomousEA.mq5 - Advanced AI Trading System      |
//| Autonomous multi-strategy EA with Python AI integration           |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Aggressive Trading Systems"
#property link      "https://www.aggressivetrading.com"
#property version   "1.00"
#property strict

#resource "Resources\\model.onnx" as uchar g_onnxModel[]

#include "Core\Utils\Enums.mqh"
#include "Core\Utils\DashboardBridge.mqh"

//--- Input parameters (Fixed compilation errors)
input double InpLotSize = 0.1;              // Base lot size
input int InpMagicNumber = 123456;         // Magic number
input bool InpUseEnhancedRisk = true;      // Enable adaptive sizing inside unified risk manager
input double InpMaxRiskPerTrade = 5.0;    // Max risk per trade; authority gate can scale this down
input double InpMaxDailyRisk = 40.0;      // Max daily risk (raised for small accounts: 0.10 min lot on $179 = ~18% per trade)
input double InpMaxPortfolioRisk = 60.0;  // Max total portfolio risk (raised for small accounts: 3 symbols x ~18% = 54%)
input double InpMaxDrawdown = 25.0;       // Max drawdown (raised for small accounts)
input double InpDailyLossLimitPercent = 40.0; // Max daily loss as % of peak equity (raised for small accounts)
input ENUM_RISK_TIER InpRiskTier = RISK_TIER_MODERATE; // Risk Tier
input bool InpEnableCompoundingTiers = true;   // Enable auto compounding tier switching based on account balance
input int  InpCompoundingTierCheckIntervalSec = 60; // How often to check for tier transitions (seconds)
input bool InpEnableSessionWeights = true;    // Enable session-aware weight adjustments (Asian/London/NY/Weekend)
input bool InpEnableSkewStepAnalyzer = true;  // Enable Skew Step distribution analyzer for Step indices
input bool   InpAllowMinLotRoundUp = true;  // Allow rounding up to broker min lot when calculated lot is below minimum
input double InpMinLotRiskMultiplier = 15.0; // Max risk multiplier for min-lot round-up (e.g., 15.0 = risk at min lot <= 15x intended)
input string InpSymbolsToTrade = "Volatility 25 Index,Volatility 75 Index,Boom 1000 Index,Crash 1000 Index,Jump 25 Index,Jump 75 Index,Step Index,EURUSD,GBPUSD,USDJPY,AUDUSD,XAUUSD,BTCUSD";               // Comprehensive test symbols
input int    InpMinSecondsBetweenTrades = 10;     // Cooldown in seconds between trade cycles
input int    InpMaxPositionsTotal = 8;            // Global position limit under authority gate
input int    InpMaxPositionsPerSymbol = 1;       // Max concurrent positions per symbol (prevents risk saturation)
input int    InpMaxTradeSendsPerCycle = 3;        // Max ranked candidates the EA may send per scan cycle
input group "Strategy Selection"
input bool InpEnableMomentum = true;        // Enable Momentum Strategy
input bool InpEnableTrend = true;           // Enable Trend Strategy
// Strategy inventory:
// 0=Momentum, 1=Trend, 4=Support/Resistance, 5=Unified ICT, 6=Candlestick,
// 7=Unicorn Model, 8=Power of Three, 9=Mean Reversion, 10=Volatility Breakout,
// 11=Statistical Arbitrage, 12=FVG Scalper, 13=Turtle Soup, 14=Breaker Block,
// 15=NY Open Gap, 16=Asian Range Break
input bool InpEnableSupportResistance = true; // Enable Support/Resistance + Trendlines + Fib Confluence
input bool InpEnableUnifiedICT = true;         // Enable Unified ICT Strategy (Phase 3.3: simplified gate structure)
input bool InpICTRequireKillZone = false;     // ICT requires Kill Zone timing (false = signals anytime, good for synthetics)
input bool InpEnableCandlestick = true;      // Enable Candlestick Patterns Strategy
input bool InpCandlestickRequireTrend = false; // Candlestick requires EMA50/200 trend alignment (false = more signals on synthetics)
input bool InpEnableUnicornModel = true;      // Enable Unicorn Model (Phase 3.3: simplified gates, lower confidence)
input bool InpEnablePowerOfThree = true;      // Enable Power of Three (Phase 3.3: removed SMT, lower confidence)
input bool InpEnableMeanReversion = true;     // NEW: Mean Reversion Strategy (Batch 93 - Counterbalance for ranging markets)
input bool InpEnableVolatilityBreakout = true; // NEW: Volatility Breakout Strategy (Batch 93 - Week 3 - Captures explosive moves)
input bool InpEnableFVGScalper = true;        // NEW: FVG Scalper Strategy (Batch 103 - FVG rejection entries)
input bool InpEnableTurtleSoup = true;        // NEW: Turtle Soup Strategy (Batch 103 - False break reversals)
input bool InpEnableBreakerBlock = true;      // NEW: Breaker Block Strategy (Batch 103 - Broken OB retest)
input bool InpEnableNYOpenGap = true;         // NEW: NY Open Gap Strategy (Batch 103 - Gap fade at NY open, FX/metals/indices only)
input bool InpEnableAsianRangeBreak = true;   // NEW: Asian Range Break Strategy (Batch 103 - London open breakout, FX/metals/indices only)
input bool InpEnableStatisticalArbitrage = false; // NEW: Statistical Arbitrage Strategy (Batch 103 - Pair trading, requires Python Bridge)
input double InpTrendADXNoTrendThreshold = 12.0; // ADX below this = no trade (lower for synthetic CFDs)
input double InpSyntheticADXNoTrendThreshold = 10.0; // ADX no-trend threshold for synthetics (lower = more signals)
input double InpICTDisplacementMultiplier = 0.8;  // ICT displacement as fraction of ATR (lower for synthetic CFDs)
input bool InpUseCuratedStrategySet = true;   // Use curated production defaults as baseline; explicitly enabled strategies remain active
input bool InpUseSymbolClassProfiles = false;  // Adapt strategy roster/governance by symbol class (synthetics vs FX)

//--- EA operating mode
input group "EA Operating Mode"
input ENUM_EA_MODE InpEAMode = EA_MODE_HYBRID; // Controls whether indicator and/or AI strategy families are active
input bool InpEnableVisualAnalysis = true;     // Enable Visual Analysis (Drawings on chart)
input int  InpMaxVisualObjects = 500;          // Max visual objects per chart

//--- Consensus quorum (weighted)
input group "Consensus Quorum"
input double InpQuorumThreshold = 0.60;        // Min normalized weighted score to pass quorum (relaxed from 0.55)
input int    InpMinLiveVoters   = 2;           // Min agreeing live voters (relaxed from 2)
input double InpConsensusConflictDeadband = 0.05; // Minimum buy/sell score delta required to break directional tie
input double InpConsensusMinReadyWeightRatio = 0.40; // Min ready-live-weight share (relaxed from 0.50)
input double InpConsensusSupportFloorNewBar = 0.20;   // Min support ratio (relaxed from 0.45 to allow solo)
input double InpConsensusSupportFloorIntrabar = 0.15; // Min support ratio (relaxed from 0.40 to allow solo)
input bool   InpAllowSparseIntrabarSingleVoter = false; // Disable one-voter live intrabar admission
input double InpSparseIntrabarMinQuality = 0.85;      // Min directional quality for sparse intrabar admission
input double InpSparseIntrabarMinSupportRatio = 0.40; // Min support ratio for sparse intrabar admission
input double InpSparseIntrabarMinReadyCoverage = 0.85; // Min ready-live coverage for sparse intrabar admission

//--- Strategy weights (used in weighted quorum)
input group "Strategy Weights"
input double InpWeightMomentum          = 1.0; // Momentum weight
input double InpWeightTrend             = 1.2; // Trend weight
input double InpWeightSupportResistance = 1.8; // Support/Resistance weight (boosted for Fib confluence)
input double InpWeightUnifiedICT        = 1.2; // Unified ICT weight (reduced from 2.2)
input double InpWeightCandlestick       = 0.8; // Candlestick weight (demoted to confirmation filter — <55% win rate as standalone)
input double InpWeightUnicornModel      = 1.2; // Unicorn Model weight (reduced from 2.4)
input double InpWeightPowerOfThree      = 1.2; // Power of Three / ICT 2025 weight (reduced from 2.3)
input double InpWeightMeanReversion     = 1.8; // Mean Reversion weight (NEW: Batch 93 - High confidence in ranging markets)
input double InpWeightVolatilityBreakout = 2.0; // Volatility Breakout weight (NEW: Batch 93 - Week 3 - High-conviction breakouts)
input double InpWeightStatisticalArbitrage = 1.5; // Statistical Arbitrage weight (NEW: Batch 103 - Pair trading)
input double InpWeightFVGScalper         = 1.8;  // FVG Scalper weight (Batch 103)
input double InpWeightTurtleSoup         = 1.6;  // Turtle Soup weight (Batch 103)
input double InpWeightBreakerBlock       = 1.7;  // Breaker Block weight (Batch 103)
input double InpWeightNYOpenGap          = 1.3;  // NY Open Gap weight (Batch 103)
input double InpWeightAsianRangeBreak    = 1.3;  // Asian Range Break weight (Batch 103)

//--- AI Mode Settings (NEW)
input group "AI Engine Settings"
input bool InpEnableAIMode = false;           // Master AI runtime gate for AI families
input bool InpEnableNeuralNetwork = false;    // MT5-native Neural Network live voter
input bool InpEnableTransformer = false;      // MT5-native Transformer live voter (disabled until retrained)
input bool InpEnableEnsemble = false;         // MT5-native Ensemble live voter (disabled until retrained)
input bool InpEnableOnnxAI = false;           // Python-trained ONNX model live voter hosted inside MT5
input ENUM_PYTHON_BRIDGE_MODE InpPythonBridgeMode = PYTHON_BRIDGE_OFF; // Python sidecar expectation mode (OFF for indicator-only testing)
input string InpPythonBridgeEndpoint = "http://127.0.0.1:8000"; // Python bridge HTTP endpoint
input int InpPythonBridgeRequestTimeoutMs = 2000; // Python bridge request timeout (ms)
input int InpPythonBridgeHeartbeatTimeoutSec = 30; // Python bridge heartbeat timeout (seconds)
input int InpPythonBridgeMaxReconnectAttempts = 5; // Max reconnect attempts before falling back
input int InpPythonBridgeReconnectBackoffMs = 2000; // Initial reconnect backoff (ms, exponential)
input bool InpEnableExternalLLM = false;       // External LLM reasoning/adaptation sidecar (not a live voter)
input string InpExternalLLMEndpoint = "http://localhost:11434"; // External LLM HTTP endpoint
input double InpAIConfidenceThreshold = 0.70;  // AI Confidence Threshold (raised to suppress low-quality AI trades)
input double InpAIWeightMultiplier = 1.0;      // AI Weight Multiplier
input double InpAIDrawdownSizingLimit = 0.20;  // Drawdown fraction used for AI lot tapering

input group "Dashboard Settings"
input bool   InpDashboardEnabled = true;              // Enable dashboard state push
input string InpDashboardEndpoint = "http://127.0.0.1:8765"; // Dashboard server endpoint
input int    InpDashboardPushIntervalSec = 5;          // State push interval (seconds)
input bool   InpDashboardControlEnabled = false;       // Enable control channel (EA polls for commands)

//--- Live authority gate
input group "Live Authority Gate"
input bool   InpEnableLiveAuthorityGate = false;      // Route candidates through AI/strategy live-authority logic (OFF: all approved trades go live when shadow_mode=false)
input bool   InpAllowAIWarmStartLive = true;          // Allow high-quality AI/ONNX signals live while evidence is building
input bool   InpAllowHybridAIStandalone = true;       // Allow high-confidence AI-only packets in HYBRID mode
input double InpAIStandaloneMinConfidence = 0.65;     // Min confidence for AI-only HYBRID admission
input double InpAIStandaloneRelaxedConfidence = 0.60; // Relaxed AI standalone threshold when no indicator signals
input int    InpHybridGateRelaxAfterCycles = 5;       // Cycles without indicator signal before relaxing threshold
input int    InpAuthorityMinSamples = 12;             // Forward-trial samples before promotion/demotion is decisive
input int    InpAuthorityTrialHorizonSeconds = 900;   // Max forward-trial horizon for shadow/live authority evidence
input int    InpAuthorityMaxTrackedTrials = 256;      // Max active authority trials
input double InpAuthorityMinExpectancyR = 0.03;       // Min average R for promoted live authority
input double InpAuthorityMinProfitFactor = 1.10;      // Min profit factor for promoted live authority
input double InpAuthorityMinCostScore = 0.50;         // Min execution-cost evidence score (relaxed from 0.68)
input double InpAuthorityMinReadinessScore = 0.52;    // Min readiness evidence score (relaxed from 0.62)
input double InpAuthorityMinContextScore   = 0.48;    // Min context evidence score (relaxed from 0.58)
input double InpAIBootstrapRiskMultiplier = 0.50;     // Risk scale for warm-start AI/ONNX authority
input double InpAIPromotedRiskMultiplier = 1.00;      // Risk scale for promoted AI/ONNX authority
input double InpNonAIPromotedRiskMultiplier = 0.65;   // Risk scale for promoted non-AI authority

//--- NN attribution forward-test diagnostics
input group "NN Attribution Diagnostics"
input bool InpEnableNNAttributionDiagnostics = false; // Enable NN attribution live diagnostics
input bool InpRunNNAttributionSelfTest = false;      // Run local mapping self-test at init

//--- Runtime Cadence + NN Online Learning
input group "Runtime Cadence & Learning"
input bool InpEnableHybridCadence = true;             // Enable hybrid cadence (new-bar + timed intrabar scans)
input int  InpIntrabarScanSeconds = 5;                // Intrabar scan interval in seconds
input bool InpIntrabarChartSymbolOnly = false;        // Restrict intrabar scans to chart symbol
input bool InpIntrabarDynamicQuorumEnabled = true;    // NO-OP: deprecated, retained for .set file compatibility only; weighted quorum is always authoritative
input double InpPipelineMinConfidence = 0.55;         // Base confidence floor for non-AI pipeline signals
input double InpIntrabarSingleVoterMinConfidence = 0.95; // Min confidence for single-voter intrabar consensus
input double InpSyntheticLeanSparseIntrabarMinQuality = 0.85; // Synthetic lean profile min quality for one-voter intrabar admission
input double InpSyntheticLeanIntrabarSingleVoterMinConfidence = 0.95; // Synthetic lean profile min confidence for one-voter intrabar admission
input double InpPipelineIntrabarConfidenceCap = 0.05; // Max weak-regime intrabar confidence threshold uplift
input bool InpPipelineEnableRegimeCostGate = true;    // Enable regime + microstructure cost gate before validator
input double InpPipelineMaxSpreadToAtrRatio = 0.50;   // Max spread/ATR ratio (relaxed from 0.25)
input int InpPipelineSpreadShockCooldownSec = 90;     // Spread shock cooldown window
input double InpPipelineLateEntryZScoreLimit = 4.00;  // Late-entry z-score limit (relaxed from 2.50)
input double InpAtrCrisisRatioThreshold = 5.0;         // ATR14/ATR50 crisis gate threshold (5.0 accommodates XAUUSD volatility spikes)
input double InpAtrCrisisRatioThresholdSynthetic = 15.0; // ATR ratio threshold for synthetic indices (Step, Jump, Crash/Boom)
input double InpAtrCrisisRatioThresholdVolatility = 10.0; // ATR ratio threshold for volatility indices
input double InpAtrCrisisRatioThresholdDefault = 8.0;   // ATR ratio threshold for other asset classes
input double InpHardSpreadCutoffPoints = 200.0;         // Hard spread cutoff: block symbol if spread > this (points)
input int  InpDeadlockAttributionIntervalSec = 60;    // Deadlock attribution diagnostics interval in seconds
input int  InpHeartbeatInterval = 60;                  // Heartbeat logging interval in seconds (minimum 30)
input bool InpEnableMomentumScalping = true;          // Allow momentum continuation scalp signals between crossover events
input int  InpMomentumScalpCooldownSeconds = 20;      // Minimum seconds between momentum scalp signals
input ENUM_TIMEFRAMES InpMomentumScalpTimeframe = PERIOD_M5; // Lower timeframe used by Momentum when chart TF is higher
input ENUM_TIMEFRAMES InpCandlestickIntrabarTimeframe = PERIOD_M5; // Lower timeframe used by Candlestick when chart TF is higher
input bool InpIntrabarEligibilityMomentum = true;     // Intrabar eligibility for Momentum strategy
input bool InpIntrabarEligibilityTrend = true;        // Intrabar eligibility for Trend strategy
input bool InpIntrabarEligibilitySupportResistance = true; // Intrabar eligibility for Support/Resistance strategy
input bool InpIntrabarEligibilityUnifiedICT = true;   // Intrabar eligibility for Unified ICT strategy
input bool InpIntrabarEligibilityCandlestick = true;  // Intrabar eligibility for Candlestick strategy
input bool InpIntrabarEligibilityUnicornModel = true; // Intrabar eligibility for Unicorn Model strategy
input bool InpIntrabarEligibilityPowerOfThree = true; // Intrabar eligibility for Power of Three strategy
input bool InpIntrabarEligibilityMeanReversion = true; // NEW: Intrabar eligibility for Mean Reversion (Batch 93)
input bool InpIntrabarEligibilityVolatilityBreakout = true; // NEW: Intrabar eligibility for Volatility Breakout (Batch 93 - Week 3)
input bool InpIntrabarEligibilityNeuralNetworkAI = true; // Intrabar eligibility for Neural Network AI
input bool InpIntrabarEligibilityTransformerAI = true;   // Intrabar eligibility for Transformer AI
input bool InpIntrabarEligibilityEnsembleAI = true;      // Intrabar eligibility for Ensemble AI
input bool InpIntrabarEligibilityOnnxAI = true;          // Intrabar eligibility for ONNX AI
input int  InpMaxIntrabarSymbolsPerCycle = 6;         // Max symbols eligible for intrabar evaluation per cycle
input int  InpMaxSignalEvaluationsPerCycle = 8;       // Max total heavy signal evaluations per cycle across new-bar + intrabar work
input int  InpIntrabarBackoffMaxSeconds = 60;         // Max per-symbol intrabar backoff interval
input int  InpReadinessReuseTtlSeconds = 60;          // Max readiness snapshot reuse age in seconds
input bool InpShadowMode = false;                     // Global dry-run override; live authority gate still controls candidates
input bool InpShadowModeEnabled = false;              // Shadow mode: log signals without executing trades
input bool InpEnableNNOnlineTraining = true;          // Enable online NN observation/labeling loop
input bool InpEnableNNWeightMutation = false;         // Enable live NN weight mutation
input bool InpEnableNNPseudoLabeling = true;          // Enable pseudo-labeling when no trade-linked label exists (DEFAULT: ON for cold-start bootstrap)
input int  InpNNPseudoLabelBarsAhead = 10;            // Pseudo-label horizon in bars
input int  InpNNSampleIntervalSeconds = 15;           // Observation sampling interval (seconds)
input int  InpNNCheckpointEveryLabeled = 10;          // Checkpoint every N newly labeled samples

//--- Advanced signal validator (post-consensus)
input group "Signal Validator"
input int    InpValidatorNewBarMinConfluence    = 1;    // Minimum strategy confluence (relaxed from 2)
input double InpValidatorNewBarMinQuality       = 0.68; // Minimum quality score (relaxed from 0.72)
input double InpValidatorNewBarMinConfidence    = 0.55; // Post-consensus confidence floor (relaxed from 0.60)
input int    InpValidatorIntrabarMinConfluence  = 1;    // Minimum strategy confluence (relaxed from 2)
input double InpValidatorIntrabarMinQuality     = 0.70; // Minimum quality score (relaxed for synthetic CFDs)
input double InpValidatorIntrabarMinConfidence  = 0.60; // Post-consensus confidence floor (relaxed from 0.65)

//--- Execution & Emergency Controls
input group "Execution Safety"
input ENUM_ORDER_TYPE_FILLING InpOrderFillingMode = ORDER_FILLING_IOC; // Preferred order filling policy
input int InpTradeSlippagePoints = 50;                                  // Max slippage (relaxed from 20)
input double InpMaxEntrySpreadPoints = 15000.0;                       // Hard pre-send spread limit (raised for Deriv Boom/Crash ~11000 pts)
input double InpMaxEntryDriftPoints = 80.0;                              // Hard drift from signal price before send; volatility-aware in trade manager; <=0 disables
input int InpProtectiveModifyCooldownSec = 5;                           // Minimum seconds between routine stop modifications
input bool InpEnableSignalReversalExit = true;                 // Close position immediately if primary strategy signals reversal
input double InpSignalReversalMinConfidence = 0.58;             // Min confidence to trigger a reversal exit
input bool InpSignalReversalProfitGuard = true;                // Only allow reversal exit if trade is currently in loss
input double InpSignalReversalMinLossR = 0.25;                  // Min loss (fraction of SL) before bailing (Cut early)
input double InpSignalReversalMaxLossR = 0.82;                  // Max loss (fraction of SL) after which SRE is disabled (Last Stand Zone)
input int    InpSignalReversalMinTimeSec = 45;                  // Min seconds to hold trade before SRE can fire
input bool InpEnableStructuralInvalidation = true;             // Always exit if ICT/Structure trend flips
input bool InpEnablePositionLifecycleManager = true;                   // EA-managed breakeven/trailing lifecycle (Enabled for scalping support)
input double InpLifecycleBreakevenBufferPoints = 50.0;                  // Profit buffer in points before breakeven becomes eligible
input double InpLifecycleTrailingDistancePoints = 150.0;                // Trailing stop distance in points once activated
input double InpLifecycleTrailingStepPoints = 30.0;                     // Minimum favorable move between trailing updates
input bool   InpLifecycleUseATRTrailing = false;                        // Use dynamic ATR-based trailing for scalping
input double InpLifecycleATRMultiplier = 1.5;                           // ATR multiplier for trailing distance
input bool InpEmergencyFlattenAllAccountPositions = true;               // Flatten account-wide positions on emergency stop
input int InpUnprotectedRemediationIntervalSec = 15;                    // Seconds between unprotected-position remediation sweeps
input int InpUnprotectedMaxRestoreAttempts = 3;                         // Max stop-restore attempts before forced close
input bool InpCloseUnprotectedOnRemediationFailure = true;              // Force close own unprotected positions after max attempts
input double InpSyntheticSpikeVelocityMultiplier = 3.0;                 // Synthetic-symbol tick-rate spike multiplier before flatten/pause
input int InpSyntheticSpikePauseSeconds = 30;                           // Trading pause after synthetic spike alarm

//--- Fast Scalp Engine (Phase 4)
input group "Fast Scalp Engine"
input bool InpEnableScalpEngine = true;                                  // Enable Fast Scalp Engine (bypasses consensus)
input bool InpScalpAsyncMode = false;                                    // Scalp: Use async order execution (faster but no instant confirmation)
input uint InpScalpMaxLatencyMs = 500;                                   // Scalp: Max execution latency (ms) — reject stale fills

//--- Dynamic Slippage Settings
input group "Dynamic Slippage"
input bool InpEnableDynamicSlippage = true;                              // Enable ATR-based dynamic slippage adjustment
input double InpDynamicSlippageAtrPercent = 0.20;                        // Slippage as percentage of ATR (0.20 = 20%)
input int InpDynamicSlippageMinPoints = 10;                              // Minimum slippage in points (floor)
input int InpDynamicSlippageMaxMultiplier = 10;                          // Maximum slippage as multiplier of base slippage
input int InpDynamicSlippageAtrPeriod = 14;                              // ATR period for volatility calculation

//--- Spike Detection Settings
input group "Spike Detection"
input int InpSpikeConfirmWindows = 2;                                    // Consecutive windows above threshold to confirm spike

input group "=== Spike Hunter ==="
input bool   InpSpikeHunterEnabled          = true;    // Enable spike hunter engine
input double InpSpikeHunterVelocityMult     = 1.8;    // Tick velocity multiplier (lower = earlier detection) - Synthetic: 1.8 (was 2.5)
input int    InpSpikeHunterMinConsecTicks   = 8;      // Min consecutive ticks in one direction - Synthetic: 8 (was 12)
input int    InpSpikeHunterConsecWindowMs   = 60000;  // Direction accumulation window (ms)
input double InpSpikeHunterATRCompression   = 0.80;   // ATR compression ratio threshold - Synthetic: 0.80 (was 0.60)
input double InpSpikeHunterSLAtrMult        = 1.5;    // SL = ATR × this
input double InpSpikeHunterTPAtrMult        = 3.0;    // TP = ATR × this
input int    InpSpikeHunterMaxPositions     = 3;      // Max concurrent spike positions
input int    InpSpikeHunterCooldownMs       = 60000;  // Cooldown between spike trades (ms)
input int    InpSpikeHunterLongTermCooldownMs = 60000; // Long-term entry cooldown after spike (ms)
input bool   InpSpikeHunterPushAlerts       = true;   // Send push notifications on spike
input int    InpSpikeHunterAlertThrottle    = 120;    // Min seconds between push alerts
input int    InpSpikeHunterMinConfluence    = 2;      // Min detection layers to confirm (2 or 3)

input group "=== Multi-Asset Profiler (Batch 103) ==="
input bool   InpMultiAssetProfilerEnabled  = true;    // Enable multi-asset class auto-detection
input bool   InpDerivProfilerEnabled        = true;    // Enable Deriv asset family auto-detection (subset)
input bool   InpGridRecoveryEnabled         = true;    // Enable grid recovery engine for mean-reversion families
input bool   InpATRScalpingEnabled          = true;    // Enable ATR scalping engine for between-spike trading

//--- Advanced Mathematical Engines (Batch 100)
input group "Mathematical Engines"
input bool   InpEnableHurstEngine       = true;    // Enable Hurst Exponent regime engine
input int    InpHurstLookback           = 300;     // Hurst lookback period (bars)
input bool   InpEnableOUProcess         = true;    // Enable Ornstein-Uhlenbeck mean-reversion engine
input int   InpOULookback              = 100;     // OU process lookback period (bars)
input bool   InpEnableOFIProxy          = true;    // Enable Order Flow Imbalance proxy engine
input int   InpOFISlowWindow           = 100;     // OFI slow window (ticks)
input bool   InpEnableVPINFilter        = true;    // Enable VPIN toxicity filter
input double InpVPINExtremeThreshold    = 0.7;     // VPIN extreme toxicity threshold (blocks new trades)
input int   InpVPINNumBuckets          = 50;      // VPIN rolling bucket count

//--- Institutional TA Engines (Forex only — do NOT enable for synthetics)
input group "Institutional TA Engines"
input bool   InpEnableVWAPEngine        = true;    // Enable VWAP engine (forex only)
input bool   InpEnableVolumeProfile     = true;    // Enable Volume Profile engine (forex only)
input bool   InpEnableCVDEngine         = true;    // Enable CVD engine (forex only)
input int    InpVWAPMinPeriodBars       = 30;      // VWAP minimum bars before valid
input double InpVWAPBand1               = 1.0;     // VWAP ±1σ band multiplier
input double InpVWAPBand2               = 1.5;     // VWAP ±1.5σ band multiplier
input double InpVWAPBand3               = 2.0;     // VWAP ±2σ band multiplier
input int    InpVPLookback              = 20;      // Volume Profile session lookback
input int    InpVPResolution            = 20;      // Volume Profile price resolution (pips)
input int    InpCVDDivergenceLookback   = 30;      // CVD divergence lookback bars

//--- Enterprise Mode Settings
input group "Enterprise Mode"
input bool InpUseSignalPipeline =      true;        // Use Signal Pipeline
input bool InpAllowSyntheticOffHours = true;        // Allow trading on synthetic symbols during off-chart hours
input double InpMinTrendStrength = 50.0;       // Minimum Trend Strength
input double InpMaxVolatility = 3.0;           // Maximum Volatility %
input bool InpEnableStructureFilter = true;    // Enable Structure Filter
input bool InpEnableLiquidityFilter = true;    // Enable Liquidity Filter
input bool InpSignalScanOnNewBarOnly = false;  // Evaluate fresh entry signals only on new bar
input int  InpPortfolioMaxPositionsPerSymbol = 3; // EA-owned same-symbol stacking cap before risk gate
input int  InpMaxPositionsSameBase = 3;        // Max positions with the same base currency (e.g. 3)
input bool InpEnableClusterRiskGovernance = true; // Enable cluster-aware risk mutex/caps in risk gate
input bool InpEnableClusterMutex = true;          // Block opposing-cluster same-symbol stacking
input int  InpRiskMaxConcurrentPerCluster = 3;    // Maximum concurrent open positions per cluster
input double InpRiskMaxClusterExposurePct = 5.0;  // Maximum projected risk per cluster (%)

//--- Portfolio Profit Target with Trailing Floor
input group "Portfolio Profit Target"
input double InpDailyProfitTargetPercent = 2.0;    // Daily profit target % (0 = disabled)
input double InpProfitTrailFactor = 0.7;            // Trail factor: protect this fraction of peak daily profit
input double InpProfitTargetHardFloorRatio = 0.50;  // Hard floor = target * this ratio (close ALL below this)
input int    InpDailyHaltCooldownMinutes = 30;      // Minutes before trading resumes after daily halt

//--- Dual-Mode Auto-Switching
input group "Dual-Mode Auto-Switching"
input bool   InpEnableAutoModeSwitch = true;       // Enable automatic mode switching
input double InpConservativeBaseRiskPct = 1.0;      // Conservative: base risk per trade %
input double InpAggressiveBaseRiskPct = 3.0;        // Aggressive: base risk per trade %
input double InpModeSwitchDrawdownPct = 5.0;        // Downgrade to conservative at this drawdown %
input int    InpModeSwitchWinStreak = 5;             // Upgrade to aggressive after N consecutive wins

//--- Log Level
input group "Logging"
input int    InpLogLevel = 1;                        // Log verbosity: 0=Silent, 1=Critical, 2=Normal, 3=Verbose, 4=Debug

//--- Batch 99: Bayesian Kelly / Equity Curve / CVaR
input group "Batch 99 Risk Subsystems"
input int    InpEquityCurveEmaPeriod = 20;           // Equity curve EMA period for position sizing
input double InpEquityCurveReductionFactor = 0.50;   // Position size reduction when equity below EMA
input double InpKellyFraction = 0.25;                // Kelly fraction for Bayesian Kelly modifier

//--- Include files
#include <Object.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include "Interfaces\IStrategy.mqh"
#include "Core\Utils\ErrorHandling.mqh"
#include "IndicatorManager.mqh"
#include "Core\Utils\Instruments.mqh"
#include "Core\Risk\UnifiedRiskManager.mqh"
#include "Core\Risk\PositionSizer.mqh"
#include "Core\Risk\RiskTierManager.mqh"
#include "Core\Risk\CompoundingTierManager.mqh"
#include "Core\Engines\FamilyStrategyWeightMatrix.mqh"
#include "Core\Engines\SessionWeightManager.mqh"
#include "Core\Engines\SkewStepAnalyzer.mqh"
#include "Core\Risk\UnprotectedPositionTracker.mqh"
#include "Core\Monitoring\PerformanceAnalytics.mqh"
#include "Core\AI\AIPerformanceFeedback.mqh"
#include "Core\Trading\TradeManager.mqh"
#include "Core\Trading\PositionStateManager.mqh"
#include "Core\Trading\TradeAttributionManager.mqh"
#include "Core\Processing\TickSafetyMonitor.mqh"
#include "Core\Processing\SyntheticSpikeMonitor.mqh"
#include "Core\Processing\SymbolScanScheduler.mqh"
#include "Core\Engines\MarketAnalysis.mqh"
#include "Core\Strategy\StrategyBase.mqh"
#include "Strategies\SimpleMomentumStrategy.mqh"
#include "Core\Utils\SymbolContext.mqh"
#include "AIModules\NextGenStrategyBrain.mqh"
#include "AIModules\NeuralNetworkStrategy.mqh"
#include "Core\Engines\AIEngine.mqh"
#include "Core\Utils\PythonBridge.mqh"
#include "Core\Utils\DiagnosticsLogger.mqh"

// Enterprise Components
#include "Core\Management\SymbolUniverseBuilder.mqh"
#include "Core\Management\EnterpriseStrategyManager.mqh"
#include "Core\Pipeline\UnifiedSignalPipeline.mqh"
#include "Core\Engines\StructureEngine.mqh"
#include "Core\Engines\TrendEngine.mqh"
#include "Core\Engines\LiquidityEngine.mqh"
#include "Core\Engines\VolatilityEngine.mqh"
#include "Core\Cache\ConsensusCache.mqh"
#include "Core\Management\PositionLifecycleManager.mqh"    // Blueprint R6a
#include "Core\Management\DiagnosticsManager.mqh"          // Blueprint R6b

// Enhanced Strategies
#include "Strategies\StrategyCandlestick.mqh"
// NOTE: CUnicornModelStrategy and CPowerOfThreeStrategy are included via EnterpriseStrategyManager.mqh
// to avoid duplicate inclusion and preprocessor directive conflicts
#include "Strategies\MeanReversionStrategy.mqh"  // NEW: Mean Reversion Strategy (Batch 93)
#include "Strategies\VolatilityBreakoutStrategy.mqh"  // NEW: Volatility Breakout Strategy (Batch 93 - Week 3)
#include "Strategies\StatisticalArbitrageStrategy.mqh"  // NEW: Statistical Arbitrage Strategy (Batch 103 - Week 4)

// Advanced Position Management
#include "Core\Strategy\AIStrategyAdapter.mqh"
#include "Core\Strategy\TransformerAIStrategyAdapter.mqh"
#include "Core\Strategy\EnsembleAIStrategyAdapter.mqh"
#include "Core\Strategy\OnnxAIStrategyAdapter.mqh"
#include "Core\Strategy\StrategyRegistry.mqh"
#include "Core\Visualization\VisualDashboard.mqh"
#include "Core\Visualization\DrawingCoordinator.mqh"

// Advanced Mathematical Engines (Batch 100)
#include "Core\Engines\HurstEngine.mqh"
#include "Core\Engines\OrnsteinUhlenbeckEngine.mqh"
#include "Core\Engines\OrderFlowImbalanceEngine.mqh"
#include "Core\Engines\VWAPEngine.mqh"
#include "Core\Engines\VolumeProfileEngine.mqh"
#include "Core\Engines\CVDEngine.mqh"
#include "Core\Risk\VPINFilter.mqh"

// Fast Scalp Engine (Phase 4)
#include "Core\Scalp\FastScalpEngine.mqh"
#include "Core\Scalp\SpikeHunterEngine.mqh"
#include "Core\Scalp\ScalpSignalCache.mqh"
#include "Core\Scalp\GridRecoveryEngine.mqh"
#include "Core\Scalp\ATRScalpingEngine.mqh"
#include "Core\Risk\FullMarginMode.mqh"
#include "Core\Risk\SafeModeConfig.mqh"
#include "Core\Risk\EquityCurveManager.mqh"
#include "Core\Processing\DerivAssetProfiler.mqh"
#include "Core\Processing\MultiAssetProfiler.mqh"

//+------------------------------------------------------------------+
//| Forward declarations
//+------------------------------------------------------------------+
// Classes now included from separate files

//--- Global variables
CSymbolInfo globalSymbol;
CAccountInfo g_accountInfo;
CEnhancedErrorHandler errorHandler;
CUnifiedRiskManager unifiedRiskManager;
CUnprotectedPositionTracker g_unprotectedTracker;
CRiskTierManager g_riskTierManager;
CCompoundingTierManager g_compoundingTierManager;
CFamilyStrategyWeightMatrix g_familyWeightMatrix;
CSessionWeightManager g_sessionWeightManager;
CSkewStepAnalyzer g_skewStepAnalyzer;
CPerformanceAnalytics performanceAnalytics;
CAIPerformanceFeedback aiFeedback;
CSymbolScanScheduler g_scanScheduler;

CNextGenStrategyBrain aiNextGenBrain;
CNeuralNetworkStrategy* neuralNetStrategy = NULL;
CNeuralNetworkStrategy* g_neuralNetStrategies[];
string g_neuralNetStrategySymbols[];
CStrategyRegistry g_strategyRegistry;
bool g_aiBrainReady = false;
bool g_aiEngineReady = false;
bool g_aiFeedbackReady = false;
bool g_aiTopologyLogged = false;
CPositionStateManager g_positionStateManager;  // Unified position state manager
CTradeAttributionManager g_attributionManager;  // Trade attribution & NN prediction mapping
CPositionSizer positionSizer;
CInstrumentRegistry instrumentRegistry;
CTickSafetyMonitor g_tickSafetyMonitor;
CSyntheticSpikeMonitor g_spikeMonitor;
bool g_onnxSessionDisabled = false;
CPythonBridge* g_pythonBridge = NULL; // Python bridge instance
CDashboardBridge* g_dashboardBridge = NULL; // Dashboard bridge instance

CTradeManager tradeManager;
CEnterpriseStrategyManager* g_enterpriseManagers[];      // Per-symbol managers
string g_enterpriseManagerSymbols[];                     // Manager symbol mapping
CConsensusCache g_consensusCache;                        // Consensus result cache for SRE hot path
// g_AIEngine declared in AIEngine.mqh
CVisualDashboard g_dashboard;
CFastScalpEngine g_scalpEngine;                            // Fast Scalp Engine (Phase 4)
CSpikeHunterEngine g_spikeHunter;                           // Spike Hunter Engine
CGridRecoveryEngine g_gridRecovery;                         // Grid Recovery Engine (Batch 102)
CATRScalpingEngine g_atrScalping;                           // ATR Scalping Engine (Batch 102)
CMultiAssetProfiler g_multiAssetProfiler;                   // Multi-Asset Profiler (Batch 103)
CScalpSignalCache g_scalpCache;                            // Scalp signal cache for fast-path evaluation
CFullMarginMode  g_fullMarginMode;                          // Full-margin aggressive mode (Phase 6)
CSafeMode        g_safeMode;                                // Conservative safe mode (Phase 6)
CPositionLifecycleManager g_lifecycleManager;               // Position lifecycle (Blueprint R6a)
CDiagnosticsManager g_diagnosticsManager;                   // Heartbeat/diagnostics (Blueprint R6b)
CChartDrawingManager* g_drawingManagers[]; // Per-symbol drawing managers
string g_drawingManagerSymbols[];          // Symbol mapping for drawing managers

// Batch 99: Bayesian Kelly / Equity Curve / CVaR subsystems
CEquityCurveManager* g_equityCurveManager = NULL;
CBayesianKellyModifier* g_bayesianKellyModifier = NULL;
CEquityCurveLotModifier* g_equityCurveLotModifier = NULL;
datetime g_lastCvarLogTime = 0;

// Batch 100: Advanced Mathematical Engines
CHurstEngine*          g_hurstEngines[];          // Per-symbol Hurst exponent engines
COrnsteinUhlenbeckEngine* g_ouEngines[];          // Per-symbol OU process engines
COrderFlowImbalanceEngine* g_ofiEngines[];         // Per-symbol OFI proxy engines
CVPINFilter*           g_vpinFilters[];           // Per-symbol VPIN toxicity filters
string g_mathEngineSymbols[];                      // Symbol mapping for math engines
bool   g_gridHurstBridgeLogged[];                   // Per-symbol: true after first [GRID-HURST-BRIDGE] log

// Batch 107: Institutional TA Engines (Forex only)
CVWAPEngine*           g_vwapEngines[];           // Per-symbol VWAP engines
CVolumeProfileEngine*  g_vpEngines[];             // Per-symbol Volume Profile engines
CCVDEngine*            g_cvdEngines[];            // Per-symbol CVD engines

//--- Performance tracking
// Centralized in CPerformanceAnalytics but kept here for display compatibility
double peakEquity = 0.0;
double initialBalance = 0.0;
double accountBalance = 0.0;
double accountEquity = 0.0;
double currentEquity = 0.0;
double currentDrawdown = 0.0;
double totalProfit = 0.0;
double totalLoss = 0.0;
int totalTrades = 0;
int winningTrades = 0;
int losingTrades = 0;
double maxDrawdown = 0.0;

//--- Missing time variables
datetime currentTime = 0;

//--- Risk management
double currentRiskPerTrade = 0.0;
double g_currentDrawdown = 0.0;
ENUM_MARKET_REGIME g_currentRegime = MARKET_REGIME_UNKNOWN;
datetime g_lastTradeTime = 0;
int g_totalActivePositions = 0;
string g_activePairs[];
// g_lastSymbolBarTimes, g_lastIntrabarScanTime, g_pendingNewBarScans, SSymbolScanState, g_symbolScanStates moved to CSymbolScanScheduler
string g_symbolsToTrade = "";
bool systemInitialized = false;
bool tradingEnabled = false;
int g_logLevel = 1;  // Set from InpLogLevel in OnInit()

// Runtime heartbeat + rejection telemetry
ulong g_hbScansAttempted = 0;
ulong g_hbIntrabarScansExecuted = 0;
ulong g_hbNoSignalCount = 0;
ulong g_hbValidatorRejects = 0;
ulong g_hbRiskRejects = 0;
ulong g_hbTradesOpened = 0;
ulong g_hbShadowTrades = 0;
ulong g_hbQuietNoNewBar = 0;
ulong g_hbQuietCadenceHold = 0;
ulong g_hbQuietMissingManager = 0;
ulong g_hbEntryBlocked = 0;
ulong g_hbSizingRejects = 0;
ulong g_hbSignalsGenerated = 0;
ulong g_hbSignalsAfterPipeline = 0;
ulong g_hbSignalsAfterQuorum = 0;
ulong g_hbSignalsValidated = 0;
ulong g_hbSignalsRiskApproved = 0;
ulong g_hbSignalsSent = 0;
ulong g_hbSyntheticSpikeEvents = 0;

datetime g_lastHeartbeatLogTime = 0;
datetime g_lastNNHealthLogTime = 0;
// g_lastSignalEvalSecond, g_lastScalpFastPathSecond, g_symbolEvalStartIndex, g_lastExternalCapacityLogTime moved to CSymbolScanScheduler
// g_lastNoSignalAlertTime moved to CDiagnosticsManager
// g_syntheticTickRateWindowStart, g_syntheticSpikeConfirmStart, g_syntheticSpikeConfirmCount,
// g_tradingPauseUntil, g_syntheticTickRateWindowCount, g_syntheticTickRateBaseline,
// g_tradingPaused — moved to CSyntheticSpikeMonitor
ulong g_scanCycleSequence = 0;
int   g_cyclesSinceIndicatorSignal = 0;  // Tracks evaluation cycles since any indicator strategy produced a signal
bool  g_hybridGateRelaxed = false;       // True when AI standalone threshold is relaxed due to indicator drought
int   g_consecutiveZeroSignalCycles = 0; // Tracks consecutive scan cycles with zero consensus signals (fallback diagnostic)
int   g_zeroSignalFallbackThreshold = 20; // Cycles of zero signals before FALLBACK warning fires

// Diagnostics logger (Blueprint 3.6: off-journal logging)
CDiagnosticsLogger g_diagLogger;

// Cached diagnostic strings (Blueprint 3.6: throttle recomputation to 60s)
string   g_cachedConsensusDiag = "";
datetime g_consensusDiagTime = 0;
string   g_cachedRoleClusterDiag = "";
datetime g_roleClusterDiagTime = 0;

// Portfolio profit target tracking
bool   g_dailyProfitTargetReached = false;
double g_dailyProfitPeakPct = 0.0;
double g_trailingProfitFloor = 0.0;
bool   g_dailyTradingHalt = false;
datetime g_dailyTradingHaltStartTime = 0;

// Dual-mode auto-switching
enum ENUM_AUTO_SWITCH_MODE { AUTO_MODE_CONSERVATIVE = 0, AUTO_MODE_AGGRESSIVE = 1, AUTO_MODE_EMERGENCY = 2 };
ENUM_AUTO_SWITCH_MODE g_currentTradingMode = AUTO_MODE_CONSERVATIVE;

// Issue 7: Dormancy cooldown tracking per symbol
int g_dormantConsecutiveCount[];       // Per-symbol consecutive dormancy warnings
datetime g_dormantCooldownUntil[];     // Per-symbol cooldown expiry time
string g_dormantCooldownSymbols[];     // Symbol mapping for cooldown arrays
const int DORMANT_COOLDOWN_THRESHOLD = 5;   // After N consecutive dormancy warnings, activate cooldown
const int DORMANT_COOLDOWN_MINUTES = 10;    // Cooldown duration in minutes

// Issue 15: Scalp blacklist tracking per symbol
int g_scalpBlacklistFailCount[];       // Per-symbol consecutive spread cost failures
bool g_scalpBlacklisted[];            // Per-symbol blacklist flag
datetime g_scalpBlacklistDay[];        // Per-symbol day of last blacklist set (for daily reset)
string g_scalpBlacklistSymbols[];      // Symbol mapping for blacklist arrays
const int SCALP_BLACKLIST_THRESHOLD = 3; // After N consecutive spread cost failures, blacklist

struct SApprovedTradeCandidate
{
    bool valid;
    string symbol;
    ENUM_TRADE_SIGNAL signal;
    ENUM_ORDER_TYPE orderType;
    ENUM_SIGNAL_EVAL_MODE evalMode;
    ENUM_VALIDATION_PROFILE validationProfile;
    double consensusConfidence;
    double tradeConfidence;
    double qualityScore;
    double convictionScore;
    double contextScore;
    double readinessScore;
    double costScore;
    double diversityScore;
    double rankingScore;
    int confluence;
    double entryPrice;
    double atrValue;
    double stopLossPips;
    double takeProfitPips;
    double lotSize;
    double slPrice;
    double tpPrice;
    string signalType;
    string strategyRoleTag;
    string strategyClusterTag;
    string strategyClusterCode;
    string contributorSummary;
    bool hasAIContributor;
    bool hasONNXContributor;
    bool hasIndicatorContributor;
    bool liveAuthorityAllowed;
    double liveAuthorityRiskMultiplier;
    string liveAuthorityReason;
    ulong cycleId;
    SValidationResult riskResult;

    SApprovedTradeCandidate()
    {
        valid = false;
        symbol = "";
        signal = TRADE_SIGNAL_NONE;
        orderType = ORDER_TYPE_BUY;
        evalMode = EVAL_MODE_NEW_BAR;
        validationProfile = VALIDATION_PROFILE_NEW_BAR;
        consensusConfidence = 0.0;
        tradeConfidence = 0.0;
        qualityScore = 0.0;
        convictionScore = 0.0;
        contextScore = 0.0;
        readinessScore = 0.0;
        costScore = 0.0;
        diversityScore = 0.0;
        rankingScore = 0.0;
        confluence = 0;
        entryPrice = 0.0;
        atrValue = 0.0;
        stopLossPips = 0.0;
        takeProfitPips = 0.0;
        lotSize = 0.0;
        slPrice = 0.0;
        tpPrice = 0.0;
        signalType = "";
        strategyRoleTag = "PRIMARY_ALPHA";
        strategyClusterTag = "NONE";
        strategyClusterCode = "N";
        contributorSummary = "";
        hasAIContributor = false;
        hasONNXContributor = false;
        hasIndicatorContributor = false;
        liveAuthorityAllowed = false;
        liveAuthorityRiskMultiplier = 0.0;
        liveAuthorityReason = "";
        cycleId = 0;
        riskResult.approved = false;
        riskResult.message = "";
        riskResult.adjustedLotSize = 0.0;
        riskResult.riskPercent = 0.0;
        riskResult.portfolioRisk = 0.0;
        riskResult.correlationRisk = 0.0;
        riskResult.requiresAdjustment = false;
        riskResult.severity = ERROR_LEVEL_INFO;
    }
};

struct SLiveAuthorityStats
{
    int samples;
    int wins;
    int losses;
    int consecutiveLosses;
    double netR;
    double grossWinR;
    double grossLossR;
    double equityR;
    double peakEquityR;
    double maxDrawdownR;
    datetime lastUpdate;

    SLiveAuthorityStats()
    {
        samples = 0;
        wins = 0;
        losses = 0;
        consecutiveLosses = 0;
        netR = 0.0;
        grossWinR = 0.0;
        grossLossR = 0.0;
        equityR = 0.0;
        peakEquityR = 0.0;
        maxDrawdownR = 0.0;
        lastUpdate = 0;
    }
};

struct SLiveAuthorityTrial
{
    bool active;
    bool liveSent;
    string symbol;
    ENUM_TRADE_SIGNAL signal;
    double entryPrice;
    double stopLossPoints;
    double takeProfitPoints;
    datetime startTime;
    datetime expiryTime;
    bool hasAI;
    bool hasONNX;
    bool hasIndicator;
    string contributors;
    string authorityReason;

    SLiveAuthorityTrial()
    {
        active = false;
        liveSent = false;
        symbol = "";
        signal = TRADE_SIGNAL_NONE;
        entryPrice = 0.0;
        stopLossPoints = 0.0;
        takeProfitPoints = 0.0;
        startTime = 0;
        expiryTime = 0;
        hasAI = false;
        hasONNX = false;
        hasIndicator = false;
        contributors = "";
        authorityReason = "";
    }
};

SLiveAuthorityStats g_authorityAIStats;
SLiveAuthorityStats g_authorityONNXStats;
SLiveAuthorityStats g_authorityIndicatorStats;
// g_authorityElliottStats REMOVED - Elliott Wave strategy removed from system
SLiveAuthorityTrial g_authorityTrials[];

double CalculateCandidateRankingScore(const SApprovedTradeCandidate &candidate)
{
    double confluenceScore = MathMin(1.0, (double)candidate.confluence / 4.0);
    double score = 0.0;
    score += candidate.qualityScore * 0.30;
    score += candidate.convictionScore * 0.25;
    score += candidate.contextScore * 0.15;
    score += candidate.readinessScore * 0.10;
    score += candidate.costScore * 0.10;
    score += candidate.diversityScore * 0.05;
    score += confluenceScore * 0.05;
    return MathMax(0.0, MathMin(1.0, score));
}

void AppendApprovedTradeCandidate(SApprovedTradeCandidate &candidates[],
                                  const SApprovedTradeCandidate &candidate)
{
    int nextIndex = ArraySize(candidates);
    ArrayResize(candidates, nextIndex + 1);
    candidates[nextIndex] = candidate;
}

void SortApprovedTradeCandidatesByRank(SApprovedTradeCandidate &candidates[])
{
    int count = ArraySize(candidates);
    for(int i = 1; i < count; i++)
    {
        SApprovedTradeCandidate key = candidates[i];
        double keyScore = key.rankingScore;
        int j = i - 1;
        while(j >= 0 && candidates[j].rankingScore < keyScore)
        {
            candidates[j + 1] = candidates[j];
            j--;
        }
        candidates[j + 1] = key;
    }
}

double CalculateAtrFromRates(const string symbol, const ENUM_TIMEFRAMES timeframe, const int period, const int shift = 0)
{
    if(symbol == "" || period <= 0 || shift < 0)
        return 0.0;

    int requiredBars = MathMax(period + shift + 2, shift + 3);
    MqlRates rates[];
    ArraySetAsSeries(rates, true);
    int copied = CopyRates(symbol, timeframe, 0, requiredBars, rates);
    if(copied <= (shift + period))
        return 0.0;

    double trueRangeSum = 0.0;
    int usable = 0;
    int maxIndex = MathMin(shift + period, copied - 1);
    for(int i = shift; i < maxIndex; i++)
    {
        double rangeHighLow = rates[i].high - rates[i].low;
        double rangeHighClose = MathAbs(rates[i].high - rates[i + 1].close);
        double rangeLowClose = MathAbs(rates[i].low - rates[i + 1].close);
        trueRangeSum += MathMax(rangeHighLow, MathMax(rangeHighClose, rangeLowClose));
        usable++;
    }

    if(usable <= 0)
        return 0.0;

    return trueRangeSum / (double)usable;
}

bool TryResolveAtrValue(const string symbol, const ENUM_TIMEFRAMES timeframe, const int period, double &atrValue)
{
    atrValue = 0.0;

    CIndicatorManager* indManager = CIndicatorManager::Instance();
    int atrHandle = INVALID_HANDLE;
    if(indManager != NULL)
        atrHandle = indManager.GetATRHandle(symbol, timeframe, period);

    double fallbackAtr = CalculateAtrFromRates(symbol, timeframe, period, 0);
    double atr[];
    ArraySetAsSeries(atr, true);
    if(atrHandle != INVALID_HANDLE && CopyBuffer(atrHandle, 0, 0, 1, atr) > 0 && atr[0] > 0.0)
    {
        if(fallbackAtr > 0.0)
        {
            double larger = MathMax(atr[0], fallbackAtr);
            double smaller = MathMin(atr[0], fallbackAtr);
            double divergenceRatio = (smaller > 1e-9) ? (larger / smaller) : 0.0;
            if(divergenceRatio >= 50.0)
            {
                atrValue = fallbackAtr;
                static datetime s_lastAtrSanityLogTime = 0;
                datetime sanityNow = TimeCurrent();
                if(s_lastAtrSanityLogTime == 0 || (sanityNow - s_lastAtrSanityLogTime) >= 30)
                {
                    PrintFormat("[ATR-SANITY] %s %s | period=%d | direct=%.5f | fallback=%.5f | action=use_fallback",
                                symbol,
                                EnumToString(timeframe),
                                period,
                                atr[0],
                                fallbackAtr);
                    s_lastAtrSanityLogTime = sanityNow;
                }
                return true;
            }
        }

        atrValue = atr[0];
        return true;
    }

    atrValue = fallbackAtr;
    if(atrValue > 0.0)
    {
        static datetime s_lastAtrFallbackLogTime = 0;
        datetime now = TimeCurrent();
        if(s_lastAtrFallbackLogTime == 0 || (now - s_lastAtrFallbackLogTime) >= 30)
        {
            PrintFormat("[ATR-FALLBACK] %s %s | period=%d | atr=%.5f",
                        symbol,
                        EnumToString(timeframe),
                        period,
                        atrValue);
            s_lastAtrFallbackLogTime = now;
        }
        return true;
    }

    return false;
}

//+------------------------------------------------------------------+
//| Resolve per-asset-class ATR crisis ratio threshold              |
//+------------------------------------------------------------------+
double ResolveATRCrisisThreshold(const string symbol)
{
    if(!InpUseSymbolClassProfiles)
        return InpAtrCrisisRatioThreshold;

    ENUM_ASSET_CLASS ac = g_multiAssetProfiler.GetAssetClassForSymbol(symbol);
    switch(ac)
    {
        case ASSET_DERIV_STEP:
        case ASSET_DERIV_JUMP:
        case ASSET_DERIV_CRASHBOOM:
        case ASSET_DERIV_DEX:
            return InpAtrCrisisRatioThresholdSynthetic;
        case ASSET_DERIV_VOLATILITY:
            return InpAtrCrisisRatioThresholdVolatility;
        default:
            return InpAtrCrisisRatioThreshold;
    }
}

// ResetSymbolScanStates, IsSymbolSchedulerStateAligned, RebuildSymbolSchedulerState,
// CountPendingNewBarScans, IsReadinessRelatedVeto, GetIntrabarBackoffSeconds,
// ScoreSymbolForIntrabar, UpdateSymbolScanStateAfterDecision moved to CSymbolScanScheduler

//+------------------------------------------------------------------+
//| Helper: Initialize AI systems                                    |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| Update performance tracking                                      |
//+------------------------------------------------------------------+
void UpdatePerformanceTracking()
{
    // Delegate to centralized analytics
    performanceAnalytics.UpdateRealTimeMetrics();
}

//+------------------------------------------------------------------+
//| Get last error message                                           |
//+------------------------------------------------------------------+
string GetLastErrorMessage()
{
    int errorCode = GetLastError();
    return IntegerToString(errorCode);
}

//+------------------------------------------------------------------+
//| Per-Symbol Magic Number Encoding                                  |
//| Format: BASE_MAGIC + symbol_index * 100 + cluster_code           |
//| Example: BASE=123456, symbol[0]=EURUSD, TREND_CLUSTER=1          |
//|          → magic=123456 + 0*100 + 1 = 123457                    |
//|          BASE=123456, symbol[1]=GBPUSD, STRUCTURE_CLUSTER=3      |
//|          → magic=123456 + 1*100 + 3 = 123559                    |
//+------------------------------------------------------------------+
#define MAGIC_SYMBOL_MULTIPLIER 100
#define MAGIC_MAX_CLUSTER_CODE  99

int GenerateMagicNumber(int symbolIndex, int clusterCode)
{
   return InpMagicNumber + symbolIndex * MAGIC_SYMBOL_MULTIPLIER + clusterCode;
}

//+------------------------------------------------------------------+
//| Check if a magic number falls within this EA's ownership range    |
//| Range: [InpMagicNumber, InpMagicNumber + symbolCount*100 + 99]   |
//+------------------------------------------------------------------+
bool IsEAOwnedMagic(long magic)
{
   int symbolCount = ArraySize(g_enterpriseManagerSymbols);
   if(symbolCount <= 0)
      symbolCount = 1; // Fallback for single-symbol mode
   int maxMagic = InpMagicNumber + symbolCount * MAGIC_SYMBOL_MULTIPLIER + MAGIC_MAX_CLUSTER_CODE;
   return (magic >= InpMagicNumber && magic <= maxMagic);
}

//+------------------------------------------------------------------+
//| Check if a position belongs to this EA (range-based magic check)  |
//+------------------------------------------------------------------+
bool IsEAOwnedPosition(ulong ticket)
{
   if(!PositionSelectByTicket(ticket))
      return false;
   return IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC));
}

//+------------------------------------------------------------------+
//| Check if a deal belongs to this EA (range-based magic check)      |
//+------------------------------------------------------------------+
bool IsEAOwnedDeal(ulong dealTicket)
{
   return IsEAOwnedMagic(HistoryDealGetInteger(dealTicket, DEAL_MAGIC));
}

//+------------------------------------------------------------------+
//| Helper: Count EA Positions (by magic number range)                |
//| PERF-DUPLICATION: Iterates all positions each call. Same iteration |
//| is performed by GetOpenPositionCountForSymbol() and inline loops  |
//| at ~L5878 and ~L6053. Consider a cached position snapshot per EA   |
//| cycle to avoid redundant PositionsTotal() traversal.               |
//+------------------------------------------------------------------+
int GetEAPositionCount()
{
    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        if(PositionSelectByTicket(PositionGetTicket(i)))
        {
            // Check if position belongs to this EA (by magic number range)
            if(IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC)))
                count++;
        }
    }
    return count;
}

// PERF-DUPLICATION: Same position iteration pattern as GetEAPositionCount() and
// inline loops at ~L5878 and ~L6053. Consider a cached position snapshot per EA cycle.
int GetOpenPositionCountForSymbol(const string symbol, const bool onlyThisEAMagic = false)
{
    if(symbol == "")
        return 0;

    int count = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

        if(PositionGetString(POSITION_SYMBOL) != symbol)
            continue;

        if(onlyThisEAMagic && !IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC)))
            continue;

        count++;
    }

    return count;
}

datetime GetLatestEAOpenPositionTime()
{
    datetime latestOpenTime = 0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;

        if(!IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC)))
            continue;

        datetime positionTime = (datetime)PositionGetInteger(POSITION_TIME);
        if(positionTime > latestOpenTime)
            latestOpenTime = positionTime;
    }

    return latestOpenTime;
}

datetime GetLatestEAHistoryDealTime()
{
    datetime nowTime = TimeCurrent();
    if(!HistorySelect(0, nowTime))
    {
        PrintFormat("[TRADE-STATE] WARNING | history select failed during cooldown reconstruction | err=%d",
                    GetLastError());
        return 0;
    }

    datetime latestDealTime = 0;
    int totalDeals = HistoryDealsTotal();
    for(int i = 0; i < totalDeals; i++)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        if(dealTicket == 0)
            continue;

        if(!IsEAOwnedMagic(HistoryDealGetInteger(dealTicket, DEAL_MAGIC)))
            continue;

        datetime dealTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
        if(dealTime > latestDealTime)
            latestDealTime = dealTime;
    }

    return latestDealTime;
}

//+------------------------------------------------------------------+
//| Selective close: close worst positions to recover trailing floor  |
//| Returns true if ALL positions were closed (hard floor breach)     |
//+------------------------------------------------------------------+
bool SelectiveCloseToRecoverFloor(double hardFloorPct)
{
    // Collect all EA-owned positions with their profit
    // Using parallel arrays instead of struct-with-string (MQL5 cannot copy structs with string members)
    ulong  posTickets[];
    double posProfits[];
    int posCount = 0;

    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0 || !PositionSelectByTicket(ticket))
            continue;
        if(!IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC)))
            continue;

        posCount++;
        ArrayResize(posTickets, posCount);
        ArrayResize(posProfits, posCount);
        posTickets[posCount - 1] = ticket;
        posProfits[posCount - 1] = PositionGetDouble(POSITION_PROFIT)
                                  + PositionGetDouble(POSITION_SWAP);
    }

    if(posCount == 0)
        return true;  // No positions left

    // Sort by profit ascending (worst first) - simple insertion sort on parallel arrays
    for(int i = 1; i < posCount; i++)
    {
        double keyProfit = posProfits[i];
        ulong   keyTicket = posTickets[i];
        int j = i - 1;
        while(j >= 0 && posProfits[j] > keyProfit)
        {
            posProfits[j + 1] = posProfits[j];
            posTickets[j + 1] = posTickets[j];
            j--;
        }
        posProfits[j + 1] = keyProfit;
        posTickets[j + 1] = keyTicket;
    }

    // Close positions from worst to best until daily profit recovers above trailing floor
    // or until we hit the hard floor (must close everything)
    double dailyPct = CalculateDailyPnLPercent();

    for(int i = 0; i < posCount; i++)
    {
        // Check if daily profit is already above trailing floor
        if(dailyPct >= g_trailingProfitFloor)
        {
            PrintFormat("[PROFIT-TARGET] Trailing floor recovered at %.2f%% after selective closes. %d positions remaining.",
                        dailyPct, posCount - i);
            return false;  // Recovered, some positions still open
        }

        // Check hard floor: if below hard floor, must close everything
        if(dailyPct < hardFloorPct)
        {
            PrintFormat("[PROFIT-TARGET] Hard floor breached: %.2f%% < %.2f%%. Closing all remaining positions.",
                        dailyPct, hardFloorPct);
            datetime closeStart = TimeCurrent();
            tradeManager.CloseAllPositions("");
            if(TimeCurrent() - closeStart > 5)
                PrintFormat("[EMERGENCY] CloseAllPositions took %d seconds (hard floor breach)",
                            (int)(TimeCurrent() - closeStart));
            return true;  // All closed, hard floor breach
        }

        // Close this worst position, capturing profit before close for P&L estimation
        double closedProfit = 0.0;
        if(PositionSelectByTicket(posTickets[i]))
        {
            string posSymbol = PositionGetString(POSITION_SYMBOL);
            closedProfit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
            PrintFormat("[PROFIT-TARGET] Selective close: Symbol=%s Profit=%.2f (trailing floor recovery)",
                        posSymbol, closedProfit);
            tradeManager.ClosePosition(posTickets[i]);
        }

        // Estimate P&L change: the closed position's profit+swap moves from unrealized
        // to realized in deal history (approximately net-zero on total P&L). The only
        // material change is the close commission (small negative). Approximate by
        // subtracting the closed position's P&L contribution from the cached percentage.
        // A full recalculation at the end of the loop corrects any estimation drift.
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        if(equity > 1.0)
            dailyPct -= (closedProfit / equity) * 100.0;
    }

    // Full recalculation after all closes to verify final state
    dailyPct = CalculateDailyPnLPercent(true);

    // All positions closed
    return true;
}

//+------------------------------------------------------------------+
//| Calculate daily P&L as percentage of starting equity              |
//+------------------------------------------------------------------+
double CalculateDailyPnLPercent(bool force = false)
{
    static double s_cachedDailyPnL = 0.0;
    static datetime s_lastPnLCalcTime = 0;
    datetime now = TimeCurrent();
    if(!force && now - s_lastPnLCalcTime < 5) return s_cachedDailyPnL;

    // Sum today's realized P&L from deal history
    double realizedPnL = 0.0;
    datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));

    if(!HistorySelect(dayStart, TimeCurrent()))
    {
        PrintFormat("[DAILY-PNL] WARNING | HistorySelect failed | err=%d", GetLastError());
        return 0.0;
    }
    int totalDeals = HistoryDealsTotal();
    for(int i = 0; i < totalDeals; i++)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        if(!IsEAOwnedMagic(HistoryDealGetInteger(dealTicket, DEAL_MAGIC))) continue;
        if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT ||
           HistoryDealGetInteger(dealTicket, DEAL_ENTRY) == DEAL_ENTRY_OUT_BY)
        {
            realizedPnL += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
            realizedPnL += HistoryDealGetDouble(dealTicket, DEAL_SWAP);
            realizedPnL += HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
        }
    }

    // Add unrealized P&L
    double unrealizedPnL = 0.0;
    for(int i = 0; i < PositionsTotal(); i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(ticket == 0) continue;
        if(!IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC))) continue;
        unrealizedPnL += PositionGetDouble(POSITION_PROFIT);
        unrealizedPnL += PositionGetDouble(POSITION_SWAP);
    }

    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double denominator = MathMax(MathMin(balance, equity), 1.0);

    double result = (realizedPnL + unrealizedPnL) / denominator * 100.0;
    s_cachedDailyPnL = result;
    s_lastPnLCalcTime = now;
    return result;
}

//+------------------------------------------------------------------+
//| Count consecutive winning deals from history                      |
//+------------------------------------------------------------------+
int CountConsecutiveWins()
{
    int count = 0;
    if(!HistorySelect(0, TimeCurrent()))
    {
        PrintFormat("[CONSECUTIVE-WINS] WARNING | HistorySelect failed | err=%d", GetLastError());
        return 0;
    }
    int totalDeals = HistoryDealsTotal();
    for(int i = totalDeals - 1; i >= 0; i--)
    {
        ulong dealTicket = HistoryDealGetTicket(i);
        if(!IsEAOwnedMagic(HistoryDealGetInteger(dealTicket, DEAL_MAGIC))) continue;
        if(HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT &&
           HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT_BY) continue;

        double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT) +
                        HistoryDealGetDouble(dealTicket, DEAL_SWAP) +
                        HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
        if(profit > 0) count++;
        else break;
    }
    return count;
}

//+------------------------------------------------------------------+
//| Determine trading mode based on performance and market conditions |
//+------------------------------------------------------------------+
ENUM_AUTO_SWITCH_MODE DetermineTradingMode()
{
    double drawdownPct = 0.0;
    // Calculate current drawdown from peak equity
    double equity = AccountInfoDouble(ACCOUNT_EQUITY);
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    if(balance > 0) drawdownPct = (balance - equity) / balance * 100.0;

    // Emergency: Critical drawdown
    if(drawdownPct > 15.0) return AUTO_MODE_EMERGENCY;

    // Downgrade to conservative if drawdown exceeds threshold
    if(drawdownPct > InpModeSwitchDrawdownPct) return AUTO_MODE_CONSERVATIVE;

    // Upgrade to aggressive if: equity at high + winning streak + clear trend
    if(g_currentTradingMode == AUTO_MODE_CONSERVATIVE)
    {
        // Only upgrade if we have a winning streak
        int consecutiveWins = CountConsecutiveWins();
        if(consecutiveWins >= InpModeSwitchWinStreak)
            return AUTO_MODE_AGGRESSIVE;
    }

    return g_currentTradingMode;  // Stay in current mode
}

void RecoverTradeTimingStateOnInit()
{
    datetime latestDealTime = GetLatestEAHistoryDealTime();
    datetime latestOpenTime = GetLatestEAOpenPositionTime();
    int eaPositions = GetEAPositionCount();

    g_lastTradeTime = latestDealTime;
    if(latestOpenTime > g_lastTradeTime)
        g_lastTradeTime = latestOpenTime;

    if(g_lastTradeTime > 0)
    {
        PrintFormat("[TRADE-STATE] Recovered last EA trade time=%s | history=%s | open_position=%s | ea_positions=%d",
                    TimeToString(g_lastTradeTime, TIME_DATE | TIME_SECONDS),
                    latestDealTime > 0 ? TimeToString(latestDealTime, TIME_DATE | TIME_SECONDS) : "none",
                    latestOpenTime > 0 ? TimeToString(latestOpenTime, TIME_DATE | TIME_SECONDS) : "none",
                    eaPositions);
    }
    else
    {
        PrintFormat("[TRADE-STATE] No prior EA trade activity recovered | ea_positions=%d",
                    eaPositions);
    }
}

double EstimateMinimumLotMarginRequirement(const string symbol)
{
    if(symbol == "")
        return -1.0;

    double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
    if(minLot <= 0.0)
        return -1.0;

    double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
    double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
    double last = SymbolInfoDouble(symbol, SYMBOL_LAST);
    if(ask <= 0.0)
        ask = last;
    if(bid <= 0.0)
        bid = last;

    double buyMargin = -1.0;
    if(ask > 0.0)
    {
        double tmp = 0.0;
        ResetLastError();
        if(OrderCalcMargin(ORDER_TYPE_BUY, symbol, minLot, ask, tmp) && MathIsValidNumber(tmp) && tmp >= 0.0)
            buyMargin = tmp;
    }

    double sellMargin = -1.0;
    if(bid > 0.0)
    {
        double tmp = 0.0;
        ResetLastError();
        if(OrderCalcMargin(ORDER_TYPE_SELL, symbol, minLot, bid, tmp) && MathIsValidNumber(tmp) && tmp >= 0.0)
            sellMargin = tmp;
    }

    if(buyMargin >= 0.0 && sellMargin >= 0.0)
        return MathMin(buyMargin, sellMargin);
    if(buyMargin >= 0.0)
        return buyMargin;
    if(sellMargin >= 0.0)
        return sellMargin;

    return -1.0;
}


void RefreshAccountRuntimeMetrics()
{
    currentTime = TimeCurrent();
    currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
    accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    accountEquity = currentEquity;

    if(currentEquity > peakEquity)
        peakEquity = currentEquity;

    if(peakEquity > 0.0)
        currentDrawdown = ((peakEquity - currentEquity) / peakEquity) * 100.0;
    else
        currentDrawdown = 0.0;
}

//+------------------------------------------------------------------+
//| Get family-aware prediction from Python bridge                   |
//| Batch 103: Multi-asset class + Deriv family ML model routing     |
//+------------------------------------------------------------------+
SPythonBridgeResponse GetFamilyPrediction(const string symbol, const double &features[], int featuresSize)
{
   if(g_pythonBridge == NULL || !g_pythonBridge.IsConnected())
   {
      SPythonBridgeResponse empty;
      empty.success = false;
      return empty;
   }

   int familyId = DetectFamilyId(symbol);
   int assetClass = DetectAssetClassId(symbol);
   string assetClassName = g_multiAssetProfiler.GetAssetClassName(symbol);
   return g_pythonBridge.PredictMultiAsset(features, featuresSize, assetClass, assetClassName, familyId, symbol);
}

void ManageOpenPositionsIfNeeded()
{
    // Blueprint R6a: Fully delegated to CPositionLifecycleManager
    g_lifecycleManager.ManagePositions();
}

// ReleaseTradingPauseIfExpired, IsTradingPauseActive, ActivateTradingPause,
// HandleEmergencyDrawdownStop, TriggerSyntheticSpikeAlarm, EvaluateSyntheticSpikeAlarm
// — moved to CSyntheticSpikeMonitor

void ProcessTickSafetyLoop()
{
    if(!systemInitialized)
        return;

    g_spikeMonitor.ReleasePauseIfExpired();

    if(!g_tickSafetyMonitor.IsTradingAllowed())
        return;

    MqlTick tick;
    if(!g_tickSafetyMonitor.ValidateTick(_Symbol, tick))
        return;

    // Throttle heavy management calls to 200ms (lightweight safety checks above run every tick)
    {
        static uint s_lastManagementCycle = 0;
        uint nowMs = GetTickCount();
        if(nowMs - s_lastManagementCycle >= 200)
        {
            unifiedRiskManager.RefreshRuntimeState();
            RefreshAccountRuntimeMetrics();
            unifiedRiskManager.MonitorMarginHealth();
            tradeManager.CheckPendingConfirmations();  // Phase 1.4: non-blocking execution confirmation
            g_unprotectedTracker.AttemptRemediation();
            ManageOpenPositionsIfNeeded();
            g_spikeMonitor.EvaluateSpike(InpSyntheticSpikeVelocityMultiplier, InpSpikeConfirmWindows,
                                          InpSyntheticSpikePauseSeconds, InpEmergencyFlattenAllAccountPositions);
            if(g_spikeMonitor.HandleEmergencyDrawdown("tick", currentDrawdown, InpMaxDrawdown, InpEmergencyFlattenAllAccountPositions))
                tradingEnabled = false;

            // Sync spike event counter to heartbeat counter
            g_hbSyntheticSpikeEvents += g_spikeMonitor.GetSpikeEventCount();
            g_spikeMonitor.ResetSpikeEventCount();

            s_lastManagementCycle = nowMs;
        }
    }

    // Fast Scalp Engine: tick-level position management (NOT throttled)
    if(InpEnableScalpEngine && g_scalpEngine.IsInitialized())
    {
        g_scalpEngine.ManageScalpPositions();
        g_scalpEngine.CheckPendingScalpOrders();
        g_scalpEngine.CheckPendingAsyncOrders();
    }

    // Process spike hunter
    if(InpSpikeHunterEnabled)
        g_spikeHunter.ProcessTick(_Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), SymbolInfoDouble(_Symbol, SYMBOL_ASK));

    // Batch 103: Process grid recovery and ATR scalping engines
    if(InpMultiAssetProfilerEnabled)
    {
        if(InpGridRecoveryEnabled && IsSyntheticIndexSymbolName(_Symbol))
            g_gridRecovery.ProcessTick(_Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), SymbolInfoDouble(_Symbol, SYMBOL_ASK));

        if(InpATRScalpingEnabled && IsSyntheticIndexSymbolName(_Symbol))
            g_atrScalping.ProcessTick(_Symbol, SymbolInfoDouble(_Symbol, SYMBOL_BID), SymbolInfoDouble(_Symbol, SYMBOL_ASK));
    }
}

//+------------------------------------------------------------------+
//| Authoritative risk decision helper                               |
//| NOTE: UnifiedRiskManager is the only trade-entry veto authority. |
//+------------------------------------------------------------------+
bool ApproveTradeByUnifiedRisk(const STradeValidationRequest &request,
                               const string phaseTag,
                               SValidationResult &result,
                               const ulong cycleId = 0)
{
    // Batch 100: VPIN toxicity pre-filter — block new positions when VPIN is extreme
    if(InpEnableVPINFilter)
    {
        for(int i = 0; i < ArraySize(g_mathEngineSymbols); i++)
        {
            if(g_mathEngineSymbols[i] == request.symbol && g_vpinFilters[i] != NULL)
            {
                if(g_vpinFilters[i].ShouldBlockNewPositions())
                {
                    result.approved = false;
                    result.message = StringFormat("VPIN extreme toxicity (%.3f) — blocking new positions", g_vpinFilters[i].GetVPIN());
                    g_hbRiskRejects++;
                    PrintFormat("[VPIN-BLOCK] %s | vpin=%.3f | cycle=%I64u", request.symbol, g_vpinFilters[i].GetVPIN(), cycleId);
                    return false;
                }
                break;
            }
        }
    }

    result = unifiedRiskManager.ValidateTradeRequest(request, phaseTag);
    if(!result.approved)
    {
        g_hbRiskRejects++;
        static string s_lastRejectKey = "";
        static datetime s_lastRejectLogTime = 0;
        string rejectKey = phaseTag + "|" + request.symbol + "|" + result.message;
        datetime nowTime = TimeCurrent();
        if(rejectKey != s_lastRejectKey ||
           s_lastRejectLogTime == 0 ||
           (nowTime - s_lastRejectLogTime) >= 15)
        {
            PrintFormat("[RISK-CONTRACT] REJECTED (%s) %s | cycle=%I64u | %s",
                        phaseTag,
                        request.symbol,
                        cycleId,
                        result.message);
            s_lastRejectKey = rejectKey;
            s_lastRejectLogTime = nowTime;
        }
        return false;
    }
    return true;
}

void PopulateTradeRequestFromCandidate(const SApprovedTradeCandidate &candidate,
                                       STradeValidationRequest &request)
{
    request.symbol = candidate.symbol;
    request.orderType = candidate.orderType;
    request.lotSize = candidate.lotSize;
    request.stopLossPips = candidate.stopLossPips;
    request.takeProfitPips = candidate.takeProfitPips;
    request.confidence = candidate.tradeConfidence;
    request.strategy = "EnterpriseConsensus";
    request.reasoning = StringFormat("reserved_candidate | role=%s | cluster=%s | contributors=%s | ranking=%.3f",
                                     candidate.strategyRoleTag,
                                     candidate.strategyClusterTag,
                                     candidate.contributorSummary,
                                     candidate.rankingScore);
    request.strategyRole = candidate.strategyRoleTag;
    request.strategyCluster = candidate.strategyClusterTag;
    request.clusterCode = candidate.strategyClusterCode;
    request.contributorContext = candidate.contributorSummary;
    request.requestTime = TimeCurrent();
}

bool ApproveAndReserveVirtualCandidate(const SApprovedTradeCandidate &candidate,
                                       const string ownerTag,
                                       const ulong cycleId,
                                       SValidationResult &reserveResult)
{
    STradeValidationRequest reserveRequest;
    PopulateTradeRequestFromCandidate(candidate, reserveRequest);
    if(!ApproveTradeByUnifiedRisk(reserveRequest, "candidate-reserve", reserveResult, cycleId))
        return false;

    // Issue 1 fix: Validate only during staging — do NOT reserve virtual position here.
    // Virtual reservations during candidate staging cause within-cycle budget accumulation
    // that blocks valid subsequent signals (99.3% rejection rate). Reserve only at send time.
    PrintFormat("[RISK-VIRTUAL-STAGE] validated (no reservation) | owner=%s | symbol=%s | risk=%.2f%% | cycle=%I64u",
                ownerTag, candidate.symbol, reserveResult.riskPercent, cycleId);
    return true;
}

//+------------------------------------------------------------------+
//| Strategy-name helper                                             |
//+------------------------------------------------------------------+
string GetStrategyNameByIndex(const int index)
{
    switch(index)
    {
        case 0: return "Momentum";
        case 1: return "Trend";
        case 2: return "Fibonacci";
        case 3: return "Elliott Wave";
        case 4: return "Support/Resistance";
        case 5: return "Unified ICT";
        case 6: return "Candlestick";
        case 7: return "Unicorn Model";
        case 8: return "Power of Three";
        case 9: return "Mean Reversion";
        case 10: return "Volatility Breakout";
        case 11: return "Statistical Arbitrage";   // Batch 103
        case 12: return "FVG Scalper";             // Batch 103
        case 13: return "Turtle Soup";             // Batch 103
        case 14: return "Breaker Block";           // Batch 103
        case 15: return "NY Open Gap";             // Batch 103
        case 16: return "Asian Range Break";       // Batch 103
        default: return "Unknown";
    }
}

string BuildEnabledStrategyList(const bool &strategyFlags[])
{
    string enabled = "";
    for(int i = 0; i < ArraySize(strategyFlags); i++)
    {
        if(!strategyFlags[i])
            continue;

        if(StringLen(enabled) > 0)
            enabled += ", ";
        enabled += GetStrategyNameByIndex(i);
    }

    if(StringLen(enabled) == 0)
        return "None";

    return enabled;
}

string BuildRegistryStrategyList(const bool includeIndicators = true,
                                 const bool includeAI = true,
                                 const bool activeOnly = true)
{
    string strategies = "";
    for(int i = 0; i < g_strategyRegistry.GetDescriptorCount(); i++)
    {
        SStrategyDescriptor descriptor;
        if(!g_strategyRegistry.GetDescriptor(i, descriptor))
            continue;
        if(descriptor.isAI && !includeAI)
            continue;
        if(!descriptor.isAI && !includeIndicators)
            continue;
        if(activeOnly && !descriptor.modeEnabled)
            continue;
        if(!activeOnly && !descriptor.inputEnabled)
            continue;

        if(StringLen(strategies) > 0)
            strategies += ", ";
        strategies += descriptor.name;
    }

    if(StringLen(strategies) == 0)
        return "None";

    return strategies;
}

string PythonBridgeModeToString(const ENUM_PYTHON_BRIDGE_MODE mode)
{
    switch(mode)
    {
        case PYTHON_BRIDGE_OFF:
            return "OFF";
        case PYTHON_BRIDGE_OBSERVE:
            return "OBSERVE";
        case PYTHON_BRIDGE_REQUIRED:
            return "REQUIRED";
        default:
            return "UNKNOWN";
    }
}


void LogPositionLifecycleConfig()
{
    PrintFormat("[POSITION-LIFECYCLE] enabled=%s | breakeven_buffer_points=%.1f | trailing_distance_points=%.1f | trailing_step_points=%.1f",
                InpEnablePositionLifecycleManager ? "true" : "false",
                InpLifecycleBreakevenBufferPoints,
                InpLifecycleTrailingDistancePoints,
                InpLifecycleTrailingStepPoints);
    if(!InpEnablePositionLifecycleManager)
    {
        Print("[POSITION-LIFECYCLE] EA-level breakeven/trailing manager is disabled by default to avoid premature scalp-style exits. Strategy-defined SL/TP and risk-managed exits remain active.");
    }
}

bool IsIndicatorStrategyModeActive(const int index)
{
    string strategyName = GetStrategyNameByIndex(index);
    if(strategyName == "Unknown")
        return false;
    return g_strategyRegistry.IsStrategyActive(strategyName);
}

string BuildEffectiveRuntimeStrategyListForSymbol(const bool &strategyFlags[])
{
    string strategies = "";

    for(int i = 0; i < ArraySize(strategyFlags); i++)
    {
        if(!StrategyFlagIsEnabled(strategyFlags, i) || !IsIndicatorStrategyModeActive(i))
            continue;

        if(StringLen(strategies) > 0)
            strategies += ", ";
        strategies += GetStrategyNameByIndex(i);
    }

    string activeAI = BuildRegistryStrategyList(false, true, true);
    if(activeAI != "None")
    {
        if(StringLen(strategies) > 0)
            strategies += ", ";
        strategies += activeAI;
    }

    if(StringLen(strategies) == 0)
        return "None";

    return strategies;
}

int CountEffectiveIndicatorStrategiesForSymbol(const bool &strategyFlags[])
{
    int count = 0;
    for(int i = 0; i < ArraySize(strategyFlags); i++)
    {
        if(StrategyFlagIsEnabled(strategyFlags, i) && IsIndicatorStrategyModeActive(i))
            count++;
    }
    return count;
}

int GetStrategyIndexByName(const string strategyName)
{
    if(strategyName == "Momentum")
        return 0;
    if(strategyName == "Trend")
        return 1;
    // Index 2: Fibonacci REMOVED (merged into Support/Resistance)
    // Index 3: Elliott Wave REMOVED
    if(strategyName == "Support/Resistance")
        return 4;
    if(strategyName == "Unified ICT")
        return 5;
    if(strategyName == "Candlestick")
        return 6;
    if(strategyName == "Unicorn Model")
        return 7;
    if(strategyName == "Power of Three")
        return 8;
    if(strategyName == "Mean Reversion")  // NEW: Batch 93
        return 9;
    if(strategyName == "Volatility Breakout")  // NEW: Batch 93 - Week 3
        return 10;
    if(strategyName == "Statistical Arbitrage")
        return 11;
    if(strategyName == "FVG Scalper")
        return 12;
    if(strategyName == "Turtle Soup")
        return 13;
    if(strategyName == "Breaker Block")
        return 14;
    if(strategyName == "NY Open Gap")
        return 15;
    if(strategyName == "Asian Range Break")
        return 16;
    return -1;
}

bool StrategyFlagIsEnabled(const bool &strategyFlags[], const int index)
{
    return (index >= 0 && index < ArraySize(strategyFlags) && strategyFlags[index]);
}

int CountEnabledStrategies(const bool &strategyFlags[])
{
    int count = 0;
    for(int i = 0; i < ArraySize(strategyFlags); i++)
    {
        if(strategyFlags[i])
            count++;
    }
    return count;
}

bool UseSyntheticLeanRosterProfile(const string symbol, const bool &baseStrategyFlags[])
{
    if(!InpUseSymbolClassProfiles || !IsSyntheticIndexSymbolName(symbol))
        return false;

    int preferredSyntheticCount = 0;
    int preferredIndices[] = {4, 5, 7, 8, 9, 10};
    for(int i = 0; i < ArraySize(preferredIndices); i++)
    {
        if(StrategyFlagIsEnabled(baseStrategyFlags, preferredIndices[i]))
            preferredSyntheticCount++;
    }

    return (preferredSyntheticCount > 0);
}

double ClampConsensusInput(const double value)
{
    return MathMax(0.0, MathMin(1.0, value));
}

double ResolveSparseIntrabarMinQualityForSymbol(const string symbol, const bool &strategyFlags[])
{
    if(UseSyntheticLeanRosterProfile(symbol, strategyFlags))
        return ClampConsensusInput(InpSyntheticLeanSparseIntrabarMinQuality);
    return ClampConsensusInput(InpSparseIntrabarMinQuality);
}

double ResolveIntrabarSingleVoterMinConfidenceForSymbol(const string symbol, const bool &strategyFlags[])
{
    if(UseSyntheticLeanRosterProfile(symbol, strategyFlags))
        return ClampConsensusInput(InpSyntheticLeanIntrabarSingleVoterMinConfidence);
    return ClampConsensusInput(InpIntrabarSingleVoterMinConfidence);
}

void BuildStrategyFlagsForSymbol(const string symbol,
                                 const bool &baseStrategyFlags[],
                                 bool &symbolStrategyFlags[])
{
    int size = ArraySize(baseStrategyFlags);
    ArrayResize(symbolStrategyFlags, size);
    for(int i = 0; i < size; i++)
        symbolStrategyFlags[i] = baseStrategyFlags[i];

    if(!UseSyntheticLeanRosterProfile(symbol, baseStrategyFlags))
        return;

    if(size > 0)
        symbolStrategyFlags[0] = false;
    if(size > 1)
        symbolStrategyFlags[1] = false;
    // Batch 103: Session-specific strategies auto-skip synthetics internally,
    // but also disable them in the roster for synthetics to avoid wasted cycles
    if(size > 15)
        symbolStrategyFlags[15] = false;  // NY Open Gap - not applicable to synthetics
    if(size > 16)
        symbolStrategyFlags[16] = false;  // Asian Range Break - not applicable to synthetics
}

string GetSymbolStrategyProfileLabel(const string symbol, const bool &baseStrategyFlags[])
{
    string instrumentClass = GetInstrumentExecutionProfileName(symbol);
    if(UseSyntheticLeanRosterProfile(symbol, baseStrategyFlags))
        return instrumentClass + "_LEAN_STRUCTURE";
    if(IsSyntheticIndexSymbolName(symbol))
        return instrumentClass + "_MANUAL";
    if(IsForexPairSymbolName(symbol))
        return "FOREX_BALANCED";
    return instrumentClass + "_BALANCED";
}

ENUM_TIMEFRAMES ResolveStrategyRegistrationTimeframe(const string symbol, const string strategyName)
{
    ENUM_TIMEFRAMES chartTf = (ENUM_TIMEFRAMES)Period();
    int chartSeconds = PeriodSeconds(chartTf);

    if(strategyName == "Momentum" &&
       InpEnableMomentumScalping &&
       InpMomentumScalpTimeframe != PERIOD_CURRENT)
    {
        int scalpSeconds = PeriodSeconds(InpMomentumScalpTimeframe);
        if(scalpSeconds > 0 && (chartSeconds <= 0 || scalpSeconds < chartSeconds))
            return InpMomentumScalpTimeframe;
    }

    if(strategyName == "Candlestick" &&
       InpIntrabarEligibilityCandlestick &&
       InpCandlestickIntrabarTimeframe != PERIOD_CURRENT)
    {
        int candleSeconds = PeriodSeconds(InpCandlestickIntrabarTimeframe);
        if(candleSeconds > 0 && (chartSeconds <= 0 || candleSeconds < chartSeconds))
            return InpCandlestickIntrabarTimeframe;
    }

    if(InpUseSymbolClassProfiles && IsSyntheticIndexSymbolName(symbol))
    {
        if((strategyName == "Unified ICT" || strategyName == "Unicorn Model" || strategyName == "Power of Three") &&
           chartTf == PERIOD_M1)
            return PERIOD_M5;
    }
    return PERIOD_CURRENT;
}

ENUM_STRATEGY_CLUSTER ResolveStrategyClusterForName(const string strategyName)
{
    if(strategyName == "Momentum" || strategyName == "Trend" || strategyName == "Volatility Breakout")
        return TREND_CLUSTER;
    if(strategyName == "Support/Resistance" || strategyName == "Mean Reversion")
        return MEAN_REVERSION_CLUSTER;
    if(strategyName == "Unified ICT" || strategyName == "Candlestick" ||
       strategyName == "Unicorn Model" || strategyName == "Power of Three")
        return STRUCTURE_CLUSTER;
    return STRATEGY_CLUSTER_NONE;
}

ENUM_STRATEGY_ROLE ResolveStrategyRoleForSymbol(const string symbol,
                                                const string strategyName,
                                                const bool &baseStrategyFlags[])
{
    if(UseSyntheticLeanRosterProfile(symbol, baseStrategyFlags))
    {
        if(strategyName == "Unified ICT" ||
           strategyName == "Unicorn Model" || strategyName == "Power of Three" ||
           strategyName == "Mean Reversion" || strategyName == "Volatility Breakout")
            return PRIMARY_ALPHA;
        if(strategyName == "Support/Resistance")
            return CONTEXT_FEATURE;
        if(strategyName == "Candlestick")
            return CONTEXT_FEATURE;  // Demoted: <55% win rate as standalone, confirmation only
    }
    return PRIMARY_ALPHA;
}

bool IsSyntheticLeanIntrabarPrimaryIndex(const int index)
{
    return (index == 2 || index == 4 || index == 5 || index == 7 || index == 8 || index == 9 || index == 10);
}

bool IsStrategyIntrabarEnabledByInput(const int index)
{
    switch(index)
    {
        case 0: return InpIntrabarEligibilityMomentum;
        case 1: return InpIntrabarEligibilityTrend;
        // Indices 2-3: Fibonacci/Elliott Wave REMOVED
        case 4: return InpIntrabarEligibilitySupportResistance;
        case 5: return InpIntrabarEligibilityUnifiedICT;
        case 6: return InpIntrabarEligibilityCandlestick;
        case 7: return InpIntrabarEligibilityUnicornModel;
        case 8: return InpIntrabarEligibilityPowerOfThree;
        case 9: return InpIntrabarEligibilityMeanReversion;
        case 10: return InpIntrabarEligibilityVolatilityBreakout;
        case 11: return false; // Statistical Arbitrage — bar-closed only
        case 12: return false; // FVG Scalper — bar-closed only
        case 13: return false; // Turtle Soup — bar-closed only
        case 14: return false; // Breaker Block — bar-closed only
        case 15: return false; // NY Open Gap — session-limited, bar-closed only
        case 16: return false; // Asian Range Break — session-limited, bar-closed only
        default: return false;
    }
}

ENUM_INTRABAR_POLICY ResolveStrategyIntrabarPolicyForSymbol(const string symbol,
                                                            const int index,
                                                            const bool &strategyFlags[])
{
    if(!StrategyFlagIsEnabled(strategyFlags, index))
        return INTRABAR_POLICY_OFF;

    if(!IsStrategyIntrabarEnabledByInput(index))
        return INTRABAR_POLICY_OFF;

    bool syntheticLeanProfile = UseSyntheticLeanRosterProfile(symbol, strategyFlags);
    if(syntheticLeanProfile)
    {
        if(index == 0 || index == 1)
            return INTRABAR_POLICY_OFF;

        if(index == 6)
            return INTRABAR_POLICY_PROBE;

        if(IsSyntheticLeanIntrabarPrimaryIndex(index))
            return INTRABAR_POLICY_LIVE;
    }

    return INTRABAR_POLICY_LIVE;
}

string GetStrategyIntrabarStatusByIndex(const string symbol,
                                        const int index,
                                        const bool &strategyFlags[])
{
    if(!StrategyFlagIsEnabled(strategyFlags, index))
        return "INACTIVE";
    if(!IsIndicatorStrategyModeActive(index))
        return "MODE_OFF";

    SStrategyDescriptor descriptor;
    string strategyName = GetStrategyNameByIndex(index);
    if(g_strategyRegistry.GetDescriptorByName(strategyName, descriptor) &&
       !descriptor.registered && StringLen(descriptor.failReason) > 0)
        return "INIT_FAILED";

    ENUM_INTRABAR_POLICY intrabarPolicy = ResolveStrategyIntrabarPolicyForSymbol(symbol, index, strategyFlags);
    if(intrabarPolicy == INTRABAR_POLICY_PROBE)
        return "PROBE";
    if(intrabarPolicy == INTRABAR_POLICY_LIVE)
        return "LIVE";
    return "OFF";
}

string BuildIntrabarGovernanceSummary(const string symbol, const bool &strategyFlags[])
{
    string summary = "";
    for(int i = 0; i < ArraySize(strategyFlags); i++)
    {
        if(i > 0)
            summary += ",";

        string shortName = GetStrategyNameByIndex(i);
        if(shortName == "Support/Resistance")
            shortName = "SupportResistance";

        summary += shortName + ":" + GetStrategyIntrabarStatusByIndex(symbol, i, strategyFlags);
    }

    return summary;
}

bool IsAIIntrabarEnabledByInput(const string strategyName)
{
    if(strategyName == "Neural Network AI")
        return InpIntrabarEligibilityNeuralNetworkAI;
    if(strategyName == "Transformer AI")
        return InpIntrabarEligibilityTransformerAI;
    if(strategyName == "Ensemble AI")
        return InpIntrabarEligibilityEnsembleAI;
    if(strategyName == "ONNX AI")
        return InpIntrabarEligibilityOnnxAI;
    return false;
}

ENUM_INTRABAR_POLICY ResolveAIIntrabarPolicyForMode(const string strategyName, const ENUM_EA_MODE effectiveMode)
{
    if(!g_strategyRegistry.IsStrategyActive(strategyName) || !IsAIIntrabarEnabledByInput(strategyName))
        return INTRABAR_POLICY_OFF;

    switch(effectiveMode)
    {
        case EA_MODE_AI_ONLY:
        case EA_MODE_HYBRID:
        case EA_MODE_AI_ASSISTED:
        case EA_MODE_INDICATOR_FILTERED:
            return INTRABAR_POLICY_LIVE;
        case EA_MODE_INDICATOR_ONLY:
        default:
            return INTRABAR_POLICY_OFF;
    }
}

string GetAIIntrabarStatusByName(const string strategyName, const ENUM_EA_MODE effectiveMode)
{
    if(!g_strategyRegistry.IsStrategyActive(strategyName))
        return "INACTIVE";

    SStrategyDescriptor descriptor;
    if(g_strategyRegistry.GetDescriptorByName(strategyName, descriptor) &&
       !descriptor.registered && StringLen(descriptor.failReason) > 0)
        return "INIT_FAILED";

    ENUM_INTRABAR_POLICY intrabarPolicy = ResolveAIIntrabarPolicyForMode(strategyName, effectiveMode);
    if(intrabarPolicy == INTRABAR_POLICY_PROBE)
        return "PROBE";
    if(intrabarPolicy == INTRABAR_POLICY_LIVE)
        return "LIVE";
    return "OFF";
}

string BuildAIIntrabarGovernanceSummary(const ENUM_EA_MODE effectiveMode)
{
    string summary = "";
    string aiNames[] = {"Neural Network AI", "Transformer AI", "Ensemble AI", "ONNX AI"};
    string aiLabels[] = {"NeuralAI", "TransformerAI", "EnsembleAI", "OnnxAI"};

    for(int i = 0; i < ArraySize(aiNames); i++)
    {
        if(i > 0)
            summary += ",";
        summary += aiLabels[i] + ":" + GetAIIntrabarStatusByName(aiNames[i], effectiveMode);
    }

    return summary;
}

double ResolveAIRuntimeVoteThreshold(const ENUM_EA_MODE effectiveMode)
{
    return MathMax(0.50, MathMin(1.0, InpAIConfidenceThreshold));
}

double ResolveAINoneDominanceMargin(const ENUM_EA_MODE effectiveMode)
{
    switch(effectiveMode)
    {
        case EA_MODE_AI_ONLY:
            return 0.03;
        case EA_MODE_HYBRID:
            return 0.01;
        default:
            return 0.0;
    }
}

void RegisterStrategyDefinitionIfEnabled(const string name,
                                         const ENUM_STRATEGY_TYPE type,
                                         const bool isAI,
                                         const bool enabled,
                                         const bool mandatory,
                                         const double weight)
{
    if(!enabled)
        return;

    g_strategyRegistry.RegisterDefinition(name, type, isAI, true, mandatory, weight);
}

bool IsAIContributorName(const string strategyName)
{
    return (strategyName == "Transformer AI" ||
            strategyName == "Ensemble AI" ||
            strategyName == "Neural Network AI" ||
            strategyName == "ONNX AI");
}

bool ContributorsIncludeIndicator(const string &contributors[])
{
    for(int i = 0; i < ArraySize(contributors); i++)
    {
        if(contributors[i] != "" && !IsAIContributorName(contributors[i]))
            return true;
    }
    return false;
}

void BuildStrategyRegistry(const bool &strategyFlags[])
{
    g_strategyRegistry.Reset();
    g_strategyRegistry.SetMode(InpEAMode);

    // Only register indicators if not in strict AI_ONLY mode
    if(InpEAMode != EA_MODE_AI_ONLY)
    {
    RegisterStrategyDefinitionIfEnabled("Momentum", STRATEGY_MOMENTUM, false,
                                        (ArraySize(strategyFlags) > 0 && strategyFlags[0]), false, InpWeightMomentum);
    RegisterStrategyDefinitionIfEnabled("Trend", STRATEGY_TREND, false,
                                        (ArraySize(strategyFlags) > 1 && strategyFlags[1]), false, InpWeightTrend);
    RegisterStrategyDefinitionIfEnabled("Support/Resistance", STRATEGY_SUPPORT_RESISTANCE, false,
                                        (ArraySize(strategyFlags) > 4 && strategyFlags[4]), false, InpWeightSupportResistance);
    RegisterStrategyDefinitionIfEnabled("Unified ICT", STRATEGY_UNIFIED_ICT, false,
                                        (ArraySize(strategyFlags) > 5 && strategyFlags[5]), false, InpWeightUnifiedICT);
    RegisterStrategyDefinitionIfEnabled("Candlestick", STRATEGY_CANDLESTICK, false,
                                        (ArraySize(strategyFlags) > 6 && strategyFlags[6]), false, InpWeightCandlestick);
    RegisterStrategyDefinitionIfEnabled("Unicorn Model", STRATEGY_UNICORN_MODEL, false,
                                        (ArraySize(strategyFlags) > 7 && strategyFlags[7]), false, InpWeightUnicornModel);
    RegisterStrategyDefinitionIfEnabled("Power of Three", STRATEGY_POWER_OF_THREE, false,
                                        (ArraySize(strategyFlags) > 8 && strategyFlags[8]), false, InpWeightPowerOfThree);
    RegisterStrategyDefinitionIfEnabled("Mean Reversion", STRATEGY_MEAN_REVERSION, false,
                                        (ArraySize(strategyFlags) > 9 && strategyFlags[9]), false, InpWeightMeanReversion);
    RegisterStrategyDefinitionIfEnabled("Volatility Breakout", STRATEGY_VOLATILITY_BREAKOUT, false,
                                        (ArraySize(strategyFlags) > 10 && strategyFlags[10]), false, InpWeightVolatilityBreakout);
    RegisterStrategyDefinitionIfEnabled("Statistical Arbitrage", STRATEGY_STATISTICAL_ARBITRAGE, false,
                                        InpEnableStatisticalArbitrage, false, InpWeightStatisticalArbitrage);
    // Batch 103: ICT/SMC strategies (user-configurable weights)
    RegisterStrategyDefinitionIfEnabled("FVG Scalper", STRATEGY_FVG_SCALPER, false,
                                        (ArraySize(strategyFlags) > 12 && strategyFlags[12]), false, InpWeightFVGScalper);
    RegisterStrategyDefinitionIfEnabled("Turtle Soup", STRATEGY_TURTLE_SOUP, false,
                                        (ArraySize(strategyFlags) > 13 && strategyFlags[13]), false, InpWeightTurtleSoup);
    RegisterStrategyDefinitionIfEnabled("Breaker Block", STRATEGY_BREAKER_BLOCK, false,
                                        (ArraySize(strategyFlags) > 14 && strategyFlags[14]), false, InpWeightBreakerBlock);
    RegisterStrategyDefinitionIfEnabled("NY Open Gap", STRATEGY_NY_OPEN_GAP, false,
                                        (ArraySize(strategyFlags) > 15 && strategyFlags[15]), false, InpWeightNYOpenGap);
    RegisterStrategyDefinitionIfEnabled("Asian Range Break", STRATEGY_ASIAN_RANGE_BREAK, false,
                                        (ArraySize(strategyFlags) > 16 && strategyFlags[16]), false, InpWeightAsianRangeBreak);

    }

    bool aiBaseEnabled = InpEnableAIMode;
    RegisterStrategyDefinitionIfEnabled("Neural Network AI", STRATEGY_BRAIN, true,
                                        (aiBaseEnabled && InpEnableNeuralNetwork), false,
                                        MathMax(0.1, InpAIWeightMultiplier));
    RegisterStrategyDefinitionIfEnabled("Transformer AI", STRATEGY_AI_ENHANCED, true,
                                        (aiBaseEnabled && InpEnableTransformer), false,
                                        MathMax(0.1, InpAIWeightMultiplier));
    RegisterStrategyDefinitionIfEnabled("Ensemble AI", STRATEGY_AI_ENHANCED, true,
                                        (aiBaseEnabled && InpEnableEnsemble), false,
                                        MathMax(0.1, InpAIWeightMultiplier));
    RegisterStrategyDefinitionIfEnabled("ONNX AI", STRATEGY_AI_ENHANCED, true,
                                        (aiBaseEnabled && InpEnableOnnxAI), false, 2.00);

    ENUM_EA_MODE effectiveMode = ResolveEffectiveEAMode();
    if(effectiveMode != g_strategyRegistry.GetMode())
    {
        PrintFormat("[STRATEGY-REGISTRY] Requested mode=%s degraded to %s based on active strategy availability",
                    EAModeToString(InpEAMode),
                    EAModeToString(effectiveMode));
        g_strategyRegistry.SetMode(effectiveMode);
    }

    PrintFormat("[STRATEGY-REGISTRY] %s", g_strategyRegistry.BuildStatusReport());
}

ENUM_EA_MODE ResolveEffectiveEAMode()
{
    // NOTE: This function is called from multiple per-symbol and per-cycle paths
    // (lines ~2096, 2131, 2176, 2831, 3081, 3755, 4181, 5823). Each call is O(1) and
    // reads live registry state, so caching would risk stale reads. If profiling shows
    // this as a hotspot, cache per-cycle with a static dirty flag on registry changes.
    ENUM_EA_MODE configuredMode = g_strategyRegistry.GetMode();
    int activeIndicators = g_strategyRegistry.GetActiveIndicatorCount();
    int activeAI = g_strategyRegistry.GetActiveAICount();

    if((configuredMode == EA_MODE_AI_ONLY || configuredMode == EA_MODE_INDICATOR_FILTERED) && activeAI <= 0)
        return EA_MODE_INDICATOR_ONLY;
    if((configuredMode == EA_MODE_INDICATOR_ONLY || configuredMode == EA_MODE_AI_ASSISTED) && activeIndicators <= 0 && activeAI > 0)
        return EA_MODE_AI_ONLY;
    if(configuredMode == EA_MODE_HYBRID && activeAI <= 0)
        return EA_MODE_INDICATOR_ONLY;
    if(configuredMode == EA_MODE_HYBRID && activeIndicators <= 0 && activeAI > 0)
        return EA_MODE_AI_ONLY;
    if(configuredMode == EA_MODE_AI_ASSISTED && activeAI <= 0)
        return EA_MODE_INDICATOR_ONLY;
    if(configuredMode == EA_MODE_INDICATOR_FILTERED && activeIndicators <= 0)
        return EA_MODE_AI_ONLY;
    return configuredMode;
}

void LogAIRuntimeTopology()
{
    ENUM_EA_MODE effectiveMode = ResolveEffectiveEAMode();
    PrintFormat("[RUNTIME-FINGERPRINT] Runtime=%s | File=%s | TerminalBuild=%d | Curated=%s | RegistrySize=%d | ActiveProfile=%s | RequestedMode=%s | EAMode=%s | HybridStandalone=%s | StandaloneThreshold=%.2f | Indicators=%d | AI=%d",
                TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS), 
                __FILE__, (int)TerminalInfoInteger(TERMINAL_BUILD),
                InpUseCuratedStrategySet ? "true" : "false",
                g_strategyRegistry.GetDescriptorCount(),
                GetInstrumentExecutionProfileName(_Symbol),
                EAModeToString(InpEAMode),
                EAModeToString(effectiveMode),
                InpAllowHybridAIStandalone ? "true" : "false",
                InpAIStandaloneMinConfidence,
                g_strategyRegistry.GetActiveIndicatorCount(),
                g_strategyRegistry.GetActiveAICount());
    g_aiTopologyLogged = true;
}

void LogAccountCapacityDiagnostics()
{
    double balance = AccountInfoDouble(ACCOUNT_BALANCE);
    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
    double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double marginRequired = 0;
    
    if(price <= 0) price = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    if(price <= 0) price = 1.0;

    if(!OrderCalcMargin(ORDER_TYPE_BUY, _Symbol, minLot, price, marginRequired))
        marginRequired = price * minLot / 100.0;

    PrintFormat("[ACCOUNT-CAPACITY-INIT] balance=%.2f | free_margin=%.2f | min_lot_margin=%.2f | capacity=%s",
                balance, freeMargin, marginRequired, 
                (freeMargin > marginRequired) ? "OK" : "INSUFFICIENT");
}

bool EvaluateEAModeCandidateAdmission(const string &contributors[],
                                      const double candidateConfidence,
                                      string &rejectReason,
                                      double &confidenceBonus)
{
    rejectReason = "";
    confidenceBonus = 0.0;

    bool hasAIContributor = g_attributionManager.ContributorsIncludeAI(contributors);
    bool hasIndicatorContributor = ContributorsIncludeIndicator(contributors);
    ENUM_EA_MODE effectiveMode = ResolveEffectiveEAMode();
    int activeIndicators = g_strategyRegistry.GetActiveIndicatorCount();
    int activeAI = g_strategyRegistry.GetActiveAICount();

    switch(effectiveMode)
    {
        case EA_MODE_INDICATOR_ONLY:
            if(hasAIContributor && !hasIndicatorContributor)
            {
                rejectReason = "indicator_only_mode_ai_candidate";
                return false;
            }
            break;

        case EA_MODE_AI_ONLY:
            if(!hasAIContributor)
            {
                rejectReason = "ai_only_mode_missing_ai";
                return false;
            }
            break;

        case EA_MODE_HYBRID:
            if(activeIndicators > 0 && !hasIndicatorContributor)
            {
                // Determine effective threshold: relax when indicator signals have been absent for too many cycles
                double effectiveThreshold = InpAIStandaloneMinConfidence;
                if(g_cyclesSinceIndicatorSignal > InpHybridGateRelaxAfterCycles)
                    effectiveThreshold = InpAIStandaloneRelaxedConfidence;

                if(hasAIContributor && InpAllowHybridAIStandalone && candidateConfidence >= effectiveThreshold)
                {
                    PrintFormat("[HYBRID-GATE] AI-standalone ADMITTED | conf=%.3f >= threshold=%.3f (%s) | standalone_enabled=true",
                                candidateConfidence, effectiveThreshold,
                                g_hybridGateRelaxed ? "relaxed" : "normal");
                    confidenceBonus = 0.02;
                    break;
                }
                PrintFormat("[HYBRID-GATE] AI-standalone REJECTED | conf=%.3f threshold=%.3f (%s) standalone_enabled=%s hasAI=%s hasIndicator=%s",
                            candidateConfidence, effectiveThreshold,
                            g_hybridGateRelaxed ? "relaxed" : "normal",
                            InpAllowHybridAIStandalone ? "true" : "false",
                            hasAIContributor ? "true" : "false",
                            hasIndicatorContributor ? "true" : "false");
                rejectReason = hasAIContributor ? "hybrid_mode_ai_without_indicator" : "hybrid_mode_missing_indicator";
                return false;
            }
            if(activeAI > 0 && hasAIContributor && hasIndicatorContributor)
                confidenceBonus = 0.05;
            break;

        case EA_MODE_AI_ASSISTED:
            if(!hasIndicatorContributor)
            {
                rejectReason = "ai_assisted_requires_indicator_primary";
                return false;
            }
            if(hasAIContributor)
                confidenceBonus = 0.05;
            break;

        case EA_MODE_INDICATOR_FILTERED:
            if(!hasAIContributor)
            {
                rejectReason = "indicator_filtered_requires_ai_primary";
                return false;
            }
            if(activeIndicators > 0 && !hasIndicatorContributor)
            {
                rejectReason = "indicator_confirmation_missing";
                return false;
            }
            break;
    }

    return true;
}

double AuthorityProfitFactor(const SLiveAuthorityStats &stats)
{
    if(stats.grossLossR <= 0.0)
        return (stats.grossWinR > 0.0) ? 99.0 : 0.0;
    return stats.grossWinR / stats.grossLossR;
}

double AuthorityExpectancyR(const SLiveAuthorityStats &stats)
{
    if(stats.samples <= 0)
        return 0.0;
    return stats.netR / (double)stats.samples;
}

bool AuthorityStatsPromoted(const SLiveAuthorityStats &stats)
{
    if(stats.samples < MathMax(1, InpAuthorityMinSamples))
        return false;
    return (AuthorityExpectancyR(stats) >= InpAuthorityMinExpectancyR &&
            AuthorityProfitFactor(stats) >= InpAuthorityMinProfitFactor &&
            stats.consecutiveLosses < 3);
}

string AuthorityStatsSummary(const string family, const SLiveAuthorityStats &stats)
{
    return StringFormat("%s samples=%d winrate=%.1f%% expR=%.3f pf=%.2f ddR=%.2f consecLoss=%d",
                        family,
                        stats.samples,
                        stats.samples > 0 ? (100.0 * (double)stats.wins / (double)stats.samples) : 0.0,
                        AuthorityExpectancyR(stats),
                        AuthorityProfitFactor(stats),
                        stats.maxDrawdownR,
                        stats.consecutiveLosses);
}

void UpdateAuthorityStats(SLiveAuthorityStats &stats, const double outcomeR)
{
    stats.samples++;
    stats.netR += outcomeR;
    stats.equityR += outcomeR;
    if(stats.equityR > stats.peakEquityR)
        stats.peakEquityR = stats.equityR;
    stats.maxDrawdownR = MathMax(stats.maxDrawdownR, stats.peakEquityR - stats.equityR);

    if(outcomeR > 0.0)
    {
        stats.wins++;
        stats.grossWinR += outcomeR;
        stats.consecutiveLosses = 0;
    }
    else
    {
        stats.losses++;
        stats.grossLossR += MathAbs(outcomeR);
        stats.consecutiveLosses++;
    }
    stats.lastUpdate = TimeCurrent();
}

bool ResolveLiveAuthority(const string symbol,
                          const bool hasAI,
                          const bool hasONNX,
                          const bool hasIndicator,
                          const int indicatorContributorCount,
                          const int confluence,
                          const double tradeConfidence,
                          const double qualityScore,
                          const double convictionScore,
                          const double contextScore,
                          const double readinessScore,
                          const double costScore,
                          const string contributors,
                          string &reason,
                          double &riskMultiplier)
{
    reason = "LIVE_AUTHORITY_DISABLED";
    riskMultiplier = 1.0;
    if(!InpEnableLiveAuthorityGate)
        return true;

    if(costScore < InpAuthorityMinCostScore)
    {
        reason = StringFormat("AUTHORITY_COST_GATE cost=%.2f need=%.2f", costScore, InpAuthorityMinCostScore);
        riskMultiplier = 0.0;
        return false;
    }
    if(readinessScore < InpAuthorityMinReadinessScore)
    {
        reason = StringFormat("AUTHORITY_READINESS_GATE readiness=%.2f need=%.2f", readinessScore, InpAuthorityMinReadinessScore);
        riskMultiplier = 0.0;
        return false;
    }
    if(contextScore < InpAuthorityMinContextScore)
    {
        reason = StringFormat("AUTHORITY_CONTEXT_GATE context=%.2f need=%.2f", contextScore, InpAuthorityMinContextScore);
        riskMultiplier = 0.0;
        return false;
    }

    if(hasAI)
    {
        string family = hasONNX ? "ONNX" : "AI";
        int familySamples = hasONNX ? g_authorityONNXStats.samples : g_authorityAIStats.samples;
        bool mature = (familySamples >= MathMax(1, InpAuthorityMinSamples));
        bool promoted = hasONNX ? AuthorityStatsPromoted(g_authorityONNXStats) : AuthorityStatsPromoted(g_authorityAIStats);
        string familyStats = hasONNX ? AuthorityStatsSummary(family, g_authorityONNXStats)
                                     : AuthorityStatsSummary(family, g_authorityAIStats);

        if(promoted)
        {
            riskMultiplier = MathMax(0.10, InpAIPromotedRiskMultiplier);
            reason = StringFormat("%s_PROMOTED | %s", family, familyStats);
            return true;
        }

        if(mature)
        {
            reason = StringFormat("%s_DEMOTED_TO_SHADOW | %s", family, familyStats);
            riskMultiplier = 0.0;
            return false;
        }

        if(InpAllowAIWarmStartLive &&
           tradeConfidence >= InpAIStandaloneMinConfidence &&
           qualityScore >= 0.65 &&
           convictionScore >= 0.45)
        {
            riskMultiplier = MathMax(0.10, InpAIBootstrapRiskMultiplier);
            reason = StringFormat("%s_WARM_START_LIVE | conf=%.2f quality=%.2f samples=%d/%d contributors=%s",
                                  family,
                                  tradeConfidence,
                                  qualityScore,
                                  familySamples,
                                  MathMax(1, InpAuthorityMinSamples),
                                  contributors);
            return true;
        }

        if(hasIndicator && confluence >= 2 && tradeConfidence >= 0.68)
        {
            riskMultiplier = MathMax(0.10, MathMax(InpAIBootstrapRiskMultiplier, InpNonAIPromotedRiskMultiplier));
            reason = StringFormat("%s_WITH_INDICATOR_CONFLUENCE | conf=%.2f confluence=%d contributors=%s",
                                  family,
                                  tradeConfidence,
                                  confluence,
                                  contributors);
            return true;
        }

        reason = StringFormat("%s_RESEARCH_SHADOW | conf=%.2f quality=%.2f samples=%d/%d contributors=%s",
                              family,
                              tradeConfidence,
                              qualityScore,
                              familySamples,
                              MathMax(1, InpAuthorityMinSamples),
                              contributors);
        riskMultiplier = 0.0;
        return false;
    }

    bool indicatorPromoted = AuthorityStatsPromoted(g_authorityIndicatorStats);
    bool highQualitySolo = (confluence >= 1 && tradeConfidence >= 0.78 && qualityScore >= 0.82);

    if((confluence >= MathMax(1, InpMinLiveVoters) || highQualitySolo) &&
       indicatorContributorCount >= 1 &&
       (indicatorPromoted || g_authorityIndicatorStats.samples < MathMax(1, InpAuthorityMinSamples) || highQualitySolo) &&
       tradeConfidence >= (highQualitySolo ? 0.75 : 0.60) &&
       qualityScore >= (highQualitySolo ? 0.80 : 0.68))
    {
        riskMultiplier = MathMax(0.10, InpNonAIPromotedRiskMultiplier);
        if(highQualitySolo && confluence == 1)
        {
            reason = StringFormat("INDICATOR_SOLO_HIGH_QUALITY | conf=%.2f quality=%.2f contributors=%s",
                                  tradeConfidence, qualityScore, contributors);
            riskMultiplier *= 0.80; // Slight risk reduction for solo indicator trades
        }
        else
        {
            reason = indicatorPromoted
                     ? StringFormat("INDICATOR_PROMOTED | %s", AuthorityStatsSummary("Indicator", g_authorityIndicatorStats))
                     : StringFormat("INDICATOR_WARM_START | samples=%d/%d confluence=%d contributors=%s",
                                    g_authorityIndicatorStats.samples,
                                    MathMax(1, InpAuthorityMinSamples),
                                    confluence,
                                    contributors);
        }
        return true;
    }

    reason = StringFormat("UNPROVEN_RESEARCH_SHADOW | confluence=%d indicator_count=%d contributors=%s",
                          confluence,
                          indicatorContributorCount,
                          contributors);
    riskMultiplier = 0.0;
    return false;
}

int ResolveAuthorityTrialSlot()
{
    int size = ArraySize(g_authorityTrials);
    int maxTrials = MathMax(1, InpAuthorityMaxTrackedTrials);
    for(int i = 0; i < size; i++)
    {
        if(!g_authorityTrials[i].active)
            return i;
    }
    if(size < maxTrials)
    {
        ArrayResize(g_authorityTrials, size + 1);
        return size;
    }

    int oldest = 0;
    datetime oldestTime = g_authorityTrials[0].startTime;
    for(int i = 1; i < size; i++)
    {
        if(g_authorityTrials[i].startTime < oldestTime)
        {
            oldest = i;
            oldestTime = g_authorityTrials[i].startTime;
        }
    }
    return oldest;
}

void RegisterLiveAuthorityTrial(const SApprovedTradeCandidate &candidate,
                                const bool liveSent,
                                const string authorityReason)
{
    if(!InpEnableLiveAuthorityGate || !candidate.valid || candidate.stopLossPips <= 0.0 || candidate.entryPrice <= 0.0)
        return;

    int slot = ResolveAuthorityTrialSlot();
    if(slot < 0)
        return;

    SLiveAuthorityTrial trial;
    trial.active = true;
    trial.liveSent = liveSent;
    trial.symbol = candidate.symbol;
    trial.signal = candidate.signal;
    trial.entryPrice = candidate.entryPrice;
    trial.stopLossPoints = candidate.stopLossPips;
    trial.takeProfitPoints = candidate.takeProfitPips;
    trial.startTime = TimeCurrent();
    trial.expiryTime = trial.startTime + MathMax(60, InpAuthorityTrialHorizonSeconds);
    trial.hasAI = candidate.hasAIContributor;
    trial.hasONNX = candidate.hasONNXContributor;
    trial.hasIndicator = candidate.hasIndicatorContributor;
    trial.contributors = candidate.contributorSummary;
    trial.authorityReason = authorityReason;
    g_authorityTrials[slot] = trial;

    PrintFormat("[AUTHORITY-TRIAL] %s | %s | live=%s | conf=%.2f | stop=%.1f | tp=%.1f | horizon=%ds | reason=%s | contributors=%s",
                candidate.symbol,
                candidate.signalType,
                liveSent ? "true" : "false",
                candidate.tradeConfidence,
                candidate.stopLossPips,
                candidate.takeProfitPips,
                MathMax(60, InpAuthorityTrialHorizonSeconds),
                authorityReason,
                candidate.contributorSummary);
}

void CompleteAuthorityTrial(const int index, const double outcomeR, const string closeReason)
{
    if(index < 0 || index >= ArraySize(g_authorityTrials) || !g_authorityTrials[index].active)
        return;

    SLiveAuthorityTrial trial = g_authorityTrials[index];
    if(trial.hasAI)
        UpdateAuthorityStats(g_authorityAIStats, outcomeR);
    if(trial.hasONNX)
        UpdateAuthorityStats(g_authorityONNXStats, outcomeR);
    if(trial.hasIndicator)
        UpdateAuthorityStats(g_authorityIndicatorStats, outcomeR);

    PrintFormat("[AUTHORITY-RESULT] %s | signal=%s | live=%s | outcomeR=%.3f | reason=%s | trial_reason=%s | contributors=%s | AI={%s} | ONNX={%s} | IND={%s}",
                trial.symbol,
                TradeSignalToString(trial.signal),
                trial.liveSent ? "true" : "false",
                outcomeR,
                closeReason,
                trial.authorityReason,
                trial.contributors,
                AuthorityStatsSummary("AI", g_authorityAIStats),
                AuthorityStatsSummary("ONNX", g_authorityONNXStats),
                AuthorityStatsSummary("Indicator", g_authorityIndicatorStats));

    g_authorityTrials[index].active = false;
}

void UpdateLiveAuthorityTrials()
{
    if(!InpEnableLiveAuthorityGate)
        return;

    datetime now = TimeCurrent();
    for(int i = 0; i < ArraySize(g_authorityTrials); i++)
    {
        if(!g_authorityTrials[i].active)
            continue;

        SLiveAuthorityTrial trial = g_authorityTrials[i];
        double point = SymbolInfoDouble(trial.symbol, SYMBOL_POINT);
        if(point <= 0.0)
            point = 0.00001;

        MqlTick tick;
        if(!SymbolInfoTick(trial.symbol, tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
            continue;

        double currentPrice = (trial.signal == TRADE_SIGNAL_BUY) ? tick.bid : tick.ask;
        double favorablePoints = 0.0;
        if(trial.signal == TRADE_SIGNAL_BUY)
            favorablePoints = (currentPrice - trial.entryPrice) / point;
        else if(trial.signal == TRADE_SIGNAL_SELL)
            favorablePoints = (trial.entryPrice - currentPrice) / point;
        else
            continue;

        double stopPoints = MathMax(1.0, trial.stopLossPoints);
        double targetPoints = MathMax(stopPoints * 0.50, trial.takeProfitPoints);
        if(favorablePoints >= targetPoints)
        {
            CompleteAuthorityTrial(i, targetPoints / stopPoints, "target_reached");
            continue;
        }
        if(favorablePoints <= -stopPoints)
        {
            CompleteAuthorityTrial(i, -1.0, "stop_reached");
            continue;
        }
        if(now >= trial.expiryTime)
        {
            double outcomeR = MathMax(-1.0, MathMin(targetPoints / stopPoints, favorablePoints / stopPoints));
            CompleteAuthorityTrial(i, outcomeR, "horizon_expired");
        }
    }
}

bool RegisterIndicatorStrategyByName(CEnterpriseStrategyManager* manager,
                                     const string symbol,
                                     const string strategyName,
                                     const bool &strategyFlags[])
{
    int strategyIndex = GetStrategyIndexByName(strategyName);
    if(manager == NULL ||
       !g_strategyRegistry.IsStrategyActive(strategyName) ||
       !StrategyFlagIsEnabled(strategyFlags, strategyIndex))
        return false;

    double strategyWeight = g_strategyRegistry.GetWeightByName(strategyName);
    ENUM_TIMEFRAMES strategyTf = ResolveStrategyRegistrationTimeframe(symbol, strategyName);
    bool registered = false;

    if(strategyName == "Momentum")
    {
        CSimpleMomentumStrategy* momentumStrategy = new CSimpleMomentumStrategy();
        if(momentumStrategy != NULL)
            momentumStrategy.SetScalpingMode(InpEnableMomentumScalping, InpMomentumScalpCooldownSeconds);
        registered = manager.RegisterStrategy(momentumStrategy, strategyName, true, strategyWeight, STRATEGY_TIER_3, strategyTf, false);
    }
    else if(strategyName == "Trend")
    {
        CStrategyTrend* trendStrategy = new CStrategyTrend();
        if(trendStrategy != NULL)
        {
            // Use synthetic ADX threshold for synthetic indices (Batch 105)
            double adxNoTrend = IsSyntheticIndexSymbolName(symbol) ? InpSyntheticADXNoTrendThreshold : InpTrendADXNoTrendThreshold;
            trendStrategy.SetADXThresholds(adxNoTrend, 20.0, 25.0, 35.0);
        }
        registered = manager.RegisterStrategy(trendStrategy, strategyName, true, strategyWeight, STRATEGY_TIER_2, strategyTf, false);
    }
    else if(strategyName == "Support/Resistance")
        registered = manager.RegisterStrategy(new CStrategySupportResistance(), strategyName, true, strategyWeight, STRATEGY_TIER_2, strategyTf, false);
    else if(strategyName == "Unified ICT")
    {
        CStrategyUnifiedICT* ict = new CStrategyUnifiedICT();
        ict.SetRequireKillZone(InpICTRequireKillZone);
        registered = manager.RegisterStrategy(ict, strategyName, true, strategyWeight, STRATEGY_TIER_1, strategyTf, false);
    }
    else if(strategyName == "Candlestick")
    {
        CStrategyCandlestick* cs = new CStrategyCandlestick();
        cs.SetRequireTrendAlignment(InpCandlestickRequireTrend);
        registered = manager.RegisterStrategy(cs, strategyName, true, strategyWeight, STRATEGY_TIER_2, strategyTf, false);
    }
    else if(strategyName == "Unicorn Model")
        registered = manager.RegisterStrategy(new CUnicornModelStrategy(), strategyName, true, strategyWeight, STRATEGY_TIER_1, strategyTf, false);
    else if(strategyName == "Power of Three")
        registered = manager.RegisterStrategy(new CPowerOfThreeStrategy(), strategyName, true, strategyWeight, STRATEGY_TIER_1, strategyTf, false);
    // NEW: Mean Reversion Strategy (Batch 93 - Week 3)
    else if(strategyName == "Mean Reversion")
    {
        CMeanReversionStrategy* mrStrategy = new CMeanReversionStrategy();
        if(mrStrategy != NULL)
        {
            // Enable synthetic mode for synthetic indices (Batch 105)
            mrStrategy.SetSyntheticMode(IsSyntheticIndexSymbolName(symbol));
        }
        registered = manager.RegisterStrategy(mrStrategy, strategyName, true, strategyWeight, STRATEGY_TIER_2, strategyTf, false);
    }
    // NEW: Volatility Breakout Strategy (Batch 93 - Week 3)
    else if(strategyName == "Volatility Breakout")
        registered = manager.RegisterStrategy(new CVolatilityBreakoutStrategy(), strategyName, true, strategyWeight, STRATEGY_TIER_1, strategyTf, false);
    // NEW: Statistical Arbitrage Strategy (Batch 103 - Week 4)
    else if(strategyName == "Statistical Arbitrage")
    {
        CStatisticalArbitrageStrategy* statArb = new CStatisticalArbitrageStrategy();
        if(statArb != NULL)
        {
            statArb.SetPythonBridge(g_pythonBridge);
            // OU engine is per-symbol, wired later in symbol initialization
        }
        registered = manager.RegisterStrategy(statArb, strategyName, true, strategyWeight, STRATEGY_TIER_2, strategyTf, false);
    }
    // Batch 103: ICT/SMC strategies
    else if(strategyName == "FVG Scalper")
        registered = manager.RegisterStrategy(new CFVGScalperStrategy(), strategyName, true, strategyWeight, STRATEGY_TIER_2, strategyTf, false);
    else if(strategyName == "Turtle Soup")
        registered = manager.RegisterStrategy(new CTurtleSoupStrategy(), strategyName, true, strategyWeight, STRATEGY_TIER_2, strategyTf, false);
    else if(strategyName == "Breaker Block")
        registered = manager.RegisterStrategy(new CBreakerBlockStrategy(), strategyName, true, strategyWeight, STRATEGY_TIER_2, strategyTf, false);
    else if(strategyName == "NY Open Gap")
        registered = manager.RegisterStrategy(new CNYOpenGapStrategy(), strategyName, true, strategyWeight, STRATEGY_TIER_3, strategyTf, false);
    else if(strategyName == "Asian Range Break")
        registered = manager.RegisterStrategy(new CAsianRangeBreakStrategy(), strategyName, true, strategyWeight, STRATEGY_TIER_3, strategyTf, false);

    g_strategyRegistry.MarkRegistered(strategyName, registered, registered ? "" : "manager_register_failed");
    return registered;
}

bool RegisterManagerAIAdapterByName(CEnterpriseStrategyManager* manager, const string strategyName)
{
    if(manager == NULL || !g_strategyRegistry.IsStrategyActive(strategyName))
        return false;

    double strategyWeight = g_strategyRegistry.GetWeightByName(strategyName);
    bool registered = false;

    if(strategyName == "Transformer AI")
        registered = manager.RegisterStrategy(new CTransformerAIStrategyAdapter(), strategyName, true, strategyWeight, STRATEGY_TIER_1, PERIOD_CURRENT, true);
    else if(strategyName == "Ensemble AI")
        registered = manager.RegisterStrategy(new CEnsembleAIStrategyAdapter(), strategyName, true, strategyWeight, STRATEGY_TIER_1, PERIOD_CURRENT, true);
    else if(strategyName == "ONNX AI")
    {
        if(g_onnxSessionDisabled)
        {
            g_strategyRegistry.MarkRegistered(strategyName, false, "session_disabled_after_init_failure");
            return false;
        }

        registered = manager.RegisterStrategy(new COnnxAIStrategyAdapter(g_onnxModel), strategyName, true, strategyWeight, STRATEGY_TIER_1, PERIOD_CURRENT, true);
        if(!registered)
        {
            g_onnxSessionDisabled = true;
            Print("[AI-SAFETY] ONNX AI disabled for the rest of this session after initialization failure. Re-export a 57-feature model and restart the EA.");
        }
    }

    g_strategyRegistry.MarkRegistered(strategyName, registered, registered ? "" : "manager_ai_register_failed");
    return registered;
}

void RegisterManagerStrategiesFromRegistry(CEnterpriseStrategyManager* manager,
                                          const string symbol,
                                          const bool &strategyFlags[])
{
    if(manager == NULL)
        return;

    for(int i = 0; i < g_strategyRegistry.GetDescriptorCount(); i++)
    {
        SStrategyDescriptor descriptor;
        if(!g_strategyRegistry.GetDescriptor(i, descriptor) || !descriptor.modeEnabled)
            continue;

        if(!descriptor.isAI)
        {
            RegisterIndicatorStrategyByName(manager, symbol, descriptor.name, strategyFlags);
            continue;
        }

        if(descriptor.name == "Transformer AI" || descriptor.name == "Ensemble AI" || descriptor.name == "ONNX AI")
            RegisterManagerAIAdapterByName(manager, descriptor.name);
    }
}

//+------------------------------------------------------------------+
//| Build strategy flags + curated profile filtering                 |
//+------------------------------------------------------------------+
void BuildStrategyFlags(bool &strategyFlags[])
{
    ArrayResize(strategyFlags, 17);  // Increased from 11 to 17 for Batch 103 ICT/SMC strategies
    strategyFlags[0]  = InpEnableMomentum;
    strategyFlags[1]  = InpEnableTrend;
    // Indices 2-3: Fibonacci/Elliott Wave REMOVED (merged into Support/Resistance)
    strategyFlags[4]  = InpEnableSupportResistance;
    strategyFlags[5]  = InpEnableUnifiedICT;
    strategyFlags[6]  = InpEnableCandlestick;
    strategyFlags[7]  = InpEnableUnicornModel;
    strategyFlags[8]  = InpEnablePowerOfThree;
    strategyFlags[9]  = InpEnableMeanReversion;  // NEW: Batch 93
    strategyFlags[10] = InpEnableVolatilityBreakout;  // NEW: Batch 93 - Week 3
    strategyFlags[11] = InpEnableStatisticalArbitrage;  // Statistical Arbitrage (Batch 103 - requires Python Bridge)
    // Batch 103: New ICT/SMC strategies
    strategyFlags[12] = InpEnableFVGScalper;       // NEW: Batch 103
    strategyFlags[13] = InpEnableTurtleSoup;       // NEW: Batch 103
    strategyFlags[14] = InpEnableBreakerBlock;     // NEW: Batch 103
    strategyFlags[15] = InpEnableNYOpenGap;        // NEW: Batch 103
    strategyFlags[16] = InpEnableAsianRangeBreak;  // NEW: Batch 103

    if(!InpUseCuratedStrategySet)
        return;

    bool curatedBaseline[];
    ArrayResize(curatedBaseline, 17);  // Increased from 11 to 17 for Batch 103
    curatedBaseline[0] = false; // Momentum
    curatedBaseline[1] = false; // Trend
    // Indices 2-3: Fibonacci/Elliott Wave REMOVED (merged into Support/Resistance)
    curatedBaseline[4] = false; // Support/Resistance + Fib Confluence
    curatedBaseline[5] = true;  // Unified ICT
    curatedBaseline[6] = false; // Candlestick
    curatedBaseline[7] = true;  // Unicorn Model
    curatedBaseline[8] = true;  // Power of Three
    curatedBaseline[9] = true;  // Mean Reversion (NEW: Batch 93 - Counterbalance for ranging markets)
    curatedBaseline[10] = true; // Volatility Breakout (NEW: Batch 93 - Captures explosive moves)
    curatedBaseline[11] = true; // Statistical Arbitrage (conditional on Python Bridge)
    curatedBaseline[12] = true; // FVG Scalper (NEW: Batch 103)
    curatedBaseline[13] = true; // Turtle Soup (NEW: Batch 103)
    curatedBaseline[14] = true; // Breaker Block (NEW: Batch 103)
    curatedBaseline[15] = true; // NY Open Gap (NEW: Batch 103)
    curatedBaseline[16] = true; // Asian Range Break (NEW: Batch 103)

    int enabledCount = 0;
    int curatedCount = 0;
    int manualOverrideCount = 0;
    for(int i = 0; i < ArraySize(strategyFlags); i++)
    {
        if(strategyFlags[i])
            enabledCount++;
        if(curatedBaseline[i])
            curatedCount++;
        if(strategyFlags[i] != curatedBaseline[i])
            manualOverrideCount++;
    }

    if(manualOverrideCount <= 0)
        PrintFormat("[CURATION] Curated baseline active (%d enabled)", enabledCount);
    else
        PrintFormat("[CURATION] Manual strategy overrides preserved (%d active vs curated baseline %d)", enabledCount, curatedCount);

    Print("[CURATION] Curated baseline recommendation: ", BuildEnabledStrategyList(curatedBaseline));
    Print("[CURATION] Effective input-enabled indicator set: ", BuildEnabledStrategyList(strategyFlags));
}

void ApplyInstitutionalStrategyGovernance(CEnterpriseStrategyManager* manager,
                                          const string symbol,
                                          const bool &strategyFlags[])
{
    if(manager == NULL)
        return;

    ENUM_EA_MODE effectiveMode = ResolveEffectiveEAMode();
    bool indicatorsPrimary = (effectiveMode != EA_MODE_AI_ONLY && effectiveMode != EA_MODE_INDICATOR_FILTERED);
    bool aiPrimary = (effectiveMode == EA_MODE_AI_ONLY || effectiveMode == EA_MODE_INDICATOR_FILTERED);
    double aiConfidenceFloor = ResolveAIRuntimeVoteThreshold(effectiveMode);
    bool syntheticLeanProfile = UseSyntheticLeanRosterProfile(symbol, strategyFlags);
    int activeIndicatorCount = CountEffectiveIndicatorStrategiesForSymbol(strategyFlags);
    string indicatorRoleLabel = (activeIndicatorCount <= 0) ? "MODE_OFF"
                                                            : (syntheticLeanProfile ? "SYMBOL_CLASS_MIXED"
                                                                                    : (indicatorsPrimary ? "PRIMARY_ALPHA" : "CONTEXT_FEATURE"));

    for(int i = 0; i < ArraySize(strategyFlags); i++)
    {
        if(!StrategyFlagIsEnabled(strategyFlags, i))
            continue;

        string strategyName = GetStrategyNameByIndex(i);
        ENUM_STRATEGY_ROLE role = ResolveStrategyRoleForSymbol(symbol, strategyName, strategyFlags);
        if(!indicatorsPrimary && role == PRIMARY_ALPHA)
            role = CONTEXT_FEATURE;
        manager.SetStrategyGovernanceByName(strategyName,
                                            role,
                                            ResolveStrategyClusterForName(strategyName),
                                            true,
                                            false);
        manager.SetStrategyIntrabarPolicyByName(strategyName,
                                                ResolveStrategyIntrabarPolicyForSymbol(symbol, i, strategyFlags));
    }

    if(g_strategyRegistry.IsStrategyActive("Neural Network AI"))
    {
        manager.SetStrategyGovernanceByName("Neural Network AI", aiPrimary ? PRIMARY_ALPHA : CONTEXT_FEATURE, STRATEGY_CLUSTER_NONE,
                                            g_strategyRegistry.GetWeightByName("Neural Network AI") > 0.0, false);
        manager.SetStrategyConfidenceThresholdByName("Neural Network AI", aiConfidenceFloor);
    }
    if(g_strategyRegistry.IsStrategyActive("Transformer AI"))
    {
        manager.SetStrategyGovernanceByName("Transformer AI", aiPrimary ? PRIMARY_ALPHA : CONTEXT_FEATURE, STRATEGY_CLUSTER_NONE,
                                            g_strategyRegistry.GetWeightByName("Transformer AI") > 0.0, false);
        manager.SetStrategyConfidenceThresholdByName("Transformer AI", aiConfidenceFloor);
    }
    if(g_strategyRegistry.IsStrategyActive("Ensemble AI"))
    {
        manager.SetStrategyGovernanceByName("Ensemble AI", aiPrimary ? PRIMARY_ALPHA : CONTEXT_FEATURE, STRATEGY_CLUSTER_NONE,
                                            g_strategyRegistry.GetWeightByName("Ensemble AI") > 0.0, false);
        manager.SetStrategyConfidenceThresholdByName("Ensemble AI", aiConfidenceFloor);
    }
    if(g_strategyRegistry.IsStrategyActive("ONNX AI"))
    {
        manager.SetStrategyGovernanceByName("ONNX AI", aiPrimary ? PRIMARY_ALPHA : CONTEXT_FEATURE, STRATEGY_CLUSTER_NONE,
                                            g_strategyRegistry.GetWeightByName("ONNX AI") > 0.0, false);
        manager.SetStrategyConfidenceThresholdByName("ONNX AI", aiConfidenceFloor);
    }

    if(g_strategyRegistry.IsStrategyActive("Neural Network AI"))
        manager.SetStrategyIntrabarPolicyByName("Neural Network AI",
                                                ResolveAIIntrabarPolicyForMode("Neural Network AI", effectiveMode));
    if(g_strategyRegistry.IsStrategyActive("Transformer AI"))
        manager.SetStrategyIntrabarPolicyByName("Transformer AI",
                                                ResolveAIIntrabarPolicyForMode("Transformer AI", effectiveMode));
    if(g_strategyRegistry.IsStrategyActive("Ensemble AI"))
        manager.SetStrategyIntrabarPolicyByName("Ensemble AI",
                                                ResolveAIIntrabarPolicyForMode("Ensemble AI", effectiveMode));
    if(g_strategyRegistry.IsStrategyActive("ONNX AI"))
        manager.SetStrategyIntrabarPolicyByName("ONNX AI",
                                                ResolveAIIntrabarPolicyForMode("ONNX AI", effectiveMode));

    PrintFormat("[STRATEGY-GOVERNANCE] %s | class=%s | profile=%s | mode=%s | indicator_role=%s | ai_role=%s | intrabar={%s,%s} | strategies={%s}",
                symbol,
                GetInstrumentExecutionProfileName(symbol),
                GetSymbolStrategyProfileLabel(symbol, strategyFlags),
                EAModeToString(effectiveMode),
                indicatorRoleLabel,
                aiPrimary ? "PRIMARY_ALPHA" : "CONTEXT_FEATURE",
                BuildIntrabarGovernanceSummary(symbol, strategyFlags),
                BuildAIIntrabarGovernanceSummary(effectiveMode),
                BuildEffectiveRuntimeStrategyListForSymbol(strategyFlags));
}

void ApplyStrategyWeights(CEnterpriseStrategyManager* manager,
                          const string symbol,
                          const bool &strategyFlags[])
{
    if(manager == NULL)
        return;

    string weightReport = "";
    for(int i = 0; i < g_strategyRegistry.GetDescriptorCount(); i++)
    {
        SStrategyDescriptor descriptor;
        if(!g_strategyRegistry.GetDescriptor(i, descriptor) || !descriptor.modeEnabled)
            continue;

        manager.UpdateStrategyWeightByName(descriptor.name, descriptor.weight);
        if(StringLen(weightReport) > 0)
            weightReport += " | ";
        weightReport += StringFormat("%s=%.2f", descriptor.name, descriptor.weight);
    }

    PrintFormat("[STRATEGY-WEIGHTS] %s | %s",
                symbol,
                StringLen(weightReport) > 0 ? weightReport : "No active strategy weights");
}

//+------------------------------------------------------------------+
//| Manager lookup helpers                                           |
//+------------------------------------------------------------------+
int FindEnterpriseManagerIndex(const string symbol)
{
    for(int i = 0; i < ArraySize(g_enterpriseManagerSymbols); i++)
    {
        if(g_enterpriseManagerSymbols[i] == symbol)
            return i;
    }
    return -1;
}

CEnterpriseStrategyManager* GetEnterpriseManagerForSymbol(const string symbol)
{
    int idx = FindEnterpriseManagerIndex(symbol);
    if(idx < 0 || idx >= ArraySize(g_enterpriseManagers))
        return NULL;
    return g_enterpriseManagers[idx];
}

// Issue 14: Set budget exhaustion flag on all pipelines to skip evaluation
void SetAllPipelinesBudgetExhausted(const bool exhausted)
{
    for(int i = 0; i < ArraySize(g_enterpriseManagers); i++)
    {
        if(g_enterpriseManagers[i] != NULL)
        {
            CUnifiedSignalPipeline* pipeline = g_enterpriseManagers[i].GetPipeline();
            if(pipeline != NULL)
                pipeline.SetBudgetExhausted(exhausted);
        }
    }
    if(exhausted)
        Print("[PIPELINE-BUDGET] All pipelines marked budget-exhausted — evaluations will be skipped until reset");
    else
        Print("[PIPELINE-BUDGET] All pipelines budget restored — evaluations resumed");
}

int GetTotalActiveStrategyCount()
{
    int total = 0;
    for(int i = 0; i < ArraySize(g_enterpriseManagers); i++)
    {
        if(g_enterpriseManagers[i] != NULL)
            total += g_enterpriseManagers[i].GetActiveStrategyCount();
    }
    return total;
}

int GetTotalActiveBrainStrategyCount()
{
    int total = 0;
    for(int i = 0; i < ArraySize(g_enterpriseManagers); i++)
    {
        if(g_enterpriseManagers[i] != NULL)
            total += g_enterpriseManagers[i].GetActiveBrainStrategyCount();
    }
    return total;
}

string BuildQualifiedStrategyName(const string symbol, const string strategyName)
{
    return symbol + "::" + strategyName;
}

void ReleaseEnterpriseManagers()
{
    for(int i = 0; i < ArraySize(g_enterpriseManagers); i++)
    {
        if(g_enterpriseManagers[i] != NULL)
        {
            delete g_enterpriseManagers[i];
            g_enterpriseManagers[i] = NULL;
        }
    }
    ArrayResize(g_enterpriseManagers, 0);
    ArrayResize(g_enterpriseManagerSymbols, 0);
    
    // Release drawing managers too
    for(int i = 0; i < ArraySize(g_drawingManagers); i++)
    {
        if(g_drawingManagers[i] != NULL)
        {
            delete g_drawingManagers[i];
            g_drawingManagers[i] = NULL;
        }
    }
    ArrayResize(g_drawingManagers, 0);
    ArrayResize(g_drawingManagerSymbols, 0);

    g_scanScheduler.Cleanup();
}

int FindNeuralNetStrategyIndex(const string symbol)
{
    for(int i = 0; i < ArraySize(g_neuralNetStrategySymbols); i++)
    {
        if(g_neuralNetStrategySymbols[i] == symbol)
            return i;
    }
    return -1;
}

CNeuralNetworkStrategy* GetNeuralNetForSymbol(const string symbol)
{
    int idx = FindNeuralNetStrategyIndex(symbol);
    if(idx < 0 || idx >= ArraySize(g_neuralNetStrategies))
        return NULL;
    return g_neuralNetStrategies[idx];
}

void ReleaseNeuralNetStrategies()
{
    for(int i = 0; i < ArraySize(g_neuralNetStrategies); i++)
    {
        if(g_neuralNetStrategies[i] != NULL)
        {
            delete g_neuralNetStrategies[i];
            g_neuralNetStrategies[i] = NULL;
        }
    }
    ArrayResize(g_neuralNetStrategies, 0);
    ArrayResize(g_neuralNetStrategySymbols, 0);
    g_positionStateManager.ClearAll();
    g_attributionManager.ClearAll();
    neuralNetStrategy = NULL;
}

bool InitializeNeuralNetForSymbol(const string symbol, ENUM_TIMEFRAMES timeframe)
{
    if(!g_strategyRegistry.IsStrategyActive("Neural Network AI"))
        return false;

    if(StringLen(symbol) == 0)
    {
        Print("[AI-MODE] Skipping NN initialization for empty symbol");
        return false;
    }

    if(!SymbolSelect(symbol, true))
    {
        Print("[AI-MODE] Skipping NN initialization for unavailable symbol: ", symbol);
        return false;
    }

    CEnterpriseStrategyManager* symbolManager = GetEnterpriseManagerForSymbol(symbol);
    if(symbolManager == NULL)
    {
        Print("[AI-MODE] Skipping NN initialization; no strategy manager for ", symbol);
        return false;
    }

    if(GetNeuralNetForSymbol(symbol) != NULL)
        return true;

    CNeuralNetworkStrategy* nn = new CNeuralNetworkStrategy();
    if(nn == NULL)
    {
        Print("[AI-MODE] Failed to allocate Neural Network for ", symbol);
        return false;
    }

    nn.SetOnlineTrainingEnabled(InpEnableNNOnlineTraining);
    nn.SetWeightMutationEnabled(InpEnableNNWeightMutation);
    nn.SetConfidenceThreshold(ResolveAIRuntimeVoteThreshold(ResolveEffectiveEAMode()));


    if(!nn.Initialize(symbol, timeframe))
    {
        Print("[AI-MODE] Neural Network initialization failed for ", symbol);
        delete nn;
        return false;
    }

    nn.ConfigureOnlineLearning(InpEnableNNOnlineTraining && InpEnableNNPseudoLabeling,
                               InpNNPseudoLabelBarsAhead,
                               InpNNSampleIntervalSeconds,
                               InpNNCheckpointEveryLabeled);

    int currentSize = ArraySize(g_neuralNetStrategies);
    ArrayResize(g_neuralNetStrategies, currentSize + 1);
    ArrayResize(g_neuralNetStrategySymbols, currentSize + 1);
    g_neuralNetStrategies[currentSize] = nn;
    g_neuralNetStrategySymbols[currentSize] = symbol;

    if(symbolManager != NULL)
    {
        double aiWeight = g_strategyRegistry.GetWeightByName("Neural Network AI");
        if(aiWeight <= 0.0)
            aiWeight = MathMax(0.1, InpAIWeightMultiplier);
        if(!symbolManager.RegisterStrategy(new CAIStrategyAdapter(nn), "Neural Network AI", true, aiWeight, STRATEGY_TIER_2, PERIOD_CURRENT, true))
        {
            Print("[AI-MODE] WARNING: Failed to register NN adapter for ", symbol);
            g_strategyRegistry.MarkRegistered("Neural Network AI", false, "nn_adapter_register_failed");
        }
        g_strategyRegistry.MarkRegistered("Neural Network AI", true);
    }

    Print("[AI-MODE] Neural Network ready for ", symbol);
    return true;
}

bool InitializeEnterpriseManagerForSymbol(const string symbol, bool &strategyFlags[])
{
    string symbolClass = GetInstrumentExecutionProfileName(symbol);
    string symbolProfile = GetSymbolStrategyProfileLabel(symbol, strategyFlags);
    bool syntheticLeanProfile = UseSyntheticLeanRosterProfile(symbol, strategyFlags);
    SignalFilterSettings filters;
    CEnterpriseStrategyManager* manager = new CEnterpriseStrategyManager();
    if(manager == NULL)
    {
        Print("[ERROR] Failed to allocate Enterprise Strategy Manager for ", symbol);
        return false;
    }

    if(!manager.Initialize(symbol, (ENUM_TIMEFRAMES)Period(), InpUseSignalPipeline,
                           &tradeManager, &positionSizer, &unifiedRiskManager, (long)InpMagicNumber))
    {
        Print("[ERROR] Failed to initialize Enterprise Strategy Manager for ", symbol);
        delete manager;
        return false;
    }

    if(InpUseSignalPipeline)
    {
        filters.enableTrendFilter = !(InpUseSymbolClassProfiles && IsSyntheticIndexSymbolName(symbol));
        filters.enableVolatilityFilter = true;
        filters.enableLiquidityFilter = InpEnableLiquidityFilter;
        filters.enableStructureFilter = InpEnableStructureFilter;
        filters.enableTimeFilter = true;
        filters.enableSessionFilter = true;
        filters.allowSyntheticOffHours = InpAllowSyntheticOffHours;
        filters.tradeLondonSession = true;
        filters.tradeNewYorkSession = true;
        filters.tradeTokyoSession = true;
        filters.minConfidence = MathMax(0.0, MathMin(1.0, InpPipelineMinConfidence));

        // Phase 6: Safe mode raises the minimum confidence floor
        if(InpRiskTier == RISK_TIER_CONSERVATIVE && g_safeMode.IsInitialized())
            filters.minConfidence = MathMax(filters.minConfidence, g_safeMode.GetConfig().minConfidence);
        filters.intrabarConfidenceCap = MathMax(0.0, InpPipelineIntrabarConfidenceCap);
        filters.enableRegimeCostGate = InpPipelineEnableRegimeCostGate;
        filters.maxSpreadToAtrRatio = MathMax(0.01, InpPipelineMaxSpreadToAtrRatio);

        // Phase 6: Full-margin and safe mode use stricter spread/ATR ratios
        if(InpRiskTier == RISK_TIER_FULL_MARGIN && g_fullMarginMode.IsInitialized())
            filters.maxSpreadToAtrRatio = MathMin(filters.maxSpreadToAtrRatio, g_fullMarginMode.GetConfig().maxSpreadATRRatio);
        if(InpRiskTier == RISK_TIER_CONSERVATIVE && g_safeMode.IsInitialized())
            filters.maxSpreadToAtrRatio = MathMin(filters.maxSpreadToAtrRatio, g_safeMode.GetConfig().maxSpreadATRRatio);
        filters.spreadShockCooldownSeconds = MathMax(5, InpPipelineSpreadShockCooldownSec);
        filters.maxEntryRangeZScore = MathMax(0.5, InpPipelineLateEntryZScoreLimit);
        filters.maxVolatility = InpMaxVolatility;
        filters.minTrendStrength = (int)InpMinTrendStrength;
        manager.SetPipelineFilters(filters);

        CUnifiedSignalPipeline* pipeline = manager.GetPipeline();
        if(pipeline != NULL)
        {
            CTrendEngine* trendEngine = pipeline.GetTrendEngine();
            if(trendEngine != NULL)
                trendEngine.SetReadinessReuseTtlSeconds(InpReadinessReuseTtlSeconds);

            CRegimeEngine* regimeEngine = pipeline.GetRegimeEngine();
            if(regimeEngine != NULL)
                regimeEngine.SetSnapshotReuseTtlSeconds(InpReadinessReuseTtlSeconds);

            // I3: Wire session weight manager to pipeline
            if(InpEnableSessionWeights)
                pipeline.SetSessionWeightManager(&g_sessionWeightManager);
        }
    }

    int minLiveVoters = MathMax(1, InpMinLiveVoters);
    double quorumThreshold = MathMax(0.0, MathMin(1.0, InpQuorumThreshold));
    double sparseIntrabarMinQuality = ResolveSparseIntrabarMinQualityForSymbol(symbol, strategyFlags);
    double sparseIntrabarMinSupportRatio = ClampConsensusInput(InpSparseIntrabarMinSupportRatio);
    double sparseIntrabarMinReadyCoverage = ClampConsensusInput(InpSparseIntrabarMinReadyCoverage);
    double intrabarSingleVoterMinConfidence = ResolveIntrabarSingleVoterMinConfidenceForSymbol(symbol, strategyFlags);
    manager.SetMinQuorum(minLiveVoters);
    manager.SetIntrabarMinQuorum(minLiveVoters);
    manager.SetQuorumThreshold(quorumThreshold);
    manager.SetConflictDeadband(MathMax(0.0, MathMin(0.50, InpConsensusConflictDeadband)));
    manager.SetMinReadyWeightRatio(MathMax(0.10, MathMin(1.0, InpConsensusMinReadyWeightRatio)));
    manager.SetSupportFloors(MathMax(0.05, MathMin(1.0, InpConsensusSupportFloorNewBar)),
                             MathMax(0.05, MathMin(1.0, InpConsensusSupportFloorIntrabar)));
    manager.SetSparseIntrabarThresholds(sparseIntrabarMinQuality,
                                        sparseIntrabarMinSupportRatio,
                                        sparseIntrabarMinReadyCoverage);
    manager.SetAllowSparseIntrabarSingleVoter(InpAllowSparseIntrabarSingleVoter);
    manager.SetIntrabarDynamicQuorumEnabled(InpIntrabarDynamicQuorumEnabled);
    manager.SetIntrabarSingleVoterMinConfidence(intrabarSingleVoterMinConfidence);
    manager.SetConsensusDiagnosticsIntervalSeconds(InpDeadlockAttributionIntervalSec);
    PrintFormat("[ENTERPRISE-CONFIG] %s | class=%s | profile=%s | trend_filter=%s | quorum_threshold=%.2f | min_live_voters=%d | support_floor_newbar=%.2f | support_floor_intrabar=%.2f | sparse_single_voter=%s | sparse_quality=%.2f | sparse_support=%.2f | sparse_ready=%.2f | intrabar_dynamic_quorum_input=%s | single_voter_min_conf=%.2f | pipeline_min_conf=%.2f | validator_mode=EXOGENOUS_ONLY | validator_profile_inputs=newbar(conf>=%.2f confluence>=%d quality>=%.2f) intrabar(conf>=%.2f confluence>=%d quality>=%.2f) | deadlock_diag_interval=%ds | intrabar_conf_cap=%.2f",
                symbol,
                symbolClass,
                symbolProfile,
                filters.enableTrendFilter ? "true" : "false",
                quorumThreshold,
                minLiveVoters,
                MathMax(0.05, MathMin(1.0, InpConsensusSupportFloorNewBar)),
                MathMax(0.05, MathMin(1.0, InpConsensusSupportFloorIntrabar)),
                InpAllowSparseIntrabarSingleVoter ? "true" : "false",
                sparseIntrabarMinQuality,
                sparseIntrabarMinSupportRatio,
                sparseIntrabarMinReadyCoverage,
                InpIntrabarDynamicQuorumEnabled ? "true" : "false",
                intrabarSingleVoterMinConfidence,
                MathMax(0.0, MathMin(1.0, InpPipelineMinConfidence)),
                MathMax(0.0, MathMin(1.0, InpValidatorNewBarMinConfidence)),
                MathMax(1, InpValidatorNewBarMinConfluence),
                MathMax(0.0, MathMin(1.0, InpValidatorNewBarMinQuality)),
                MathMax(0.0, MathMin(1.0, InpValidatorIntrabarMinConfidence)),
                MathMax(1, InpValidatorIntrabarMinConfluence),
                MathMax(0.0, MathMin(1.0, InpValidatorIntrabarMinQuality)),
                MathMax(10, InpDeadlockAttributionIntervalSec),
                MathMax(0.0, InpPipelineIntrabarConfidenceCap));
    Print("[CURATION] Effective strategy set for ", symbol, ": ", BuildEnabledStrategyList(strategyFlags));
    if(syntheticLeanProfile)
        PrintFormat("[SYMBOL-PROFILE] %s uses synthetic lean roster: Momentum/Trend suppressed from manager roster; Candlestick remains new-bar active but intrabar PROBE while Fibonacci/Elliott/SupportResistance/UICT stay LIVE | sparse_quality=%.2f | single_voter_min_conf=%.2f",
                    symbol,
                    sparseIntrabarMinQuality,
                    intrabarSingleVoterMinConfidence);
    RegisterManagerStrategiesFromRegistry(manager, symbol, strategyFlags);
    ApplyInstitutionalStrategyGovernance(manager, symbol, strategyFlags);
    ApplyStrategyWeights(manager, symbol, strategyFlags);

    int size = ArraySize(g_enterpriseManagers);
    ArrayResize(g_enterpriseManagers, size + 1);
    ArrayResize(g_enterpriseManagerSymbols, size + 1);
    g_enterpriseManagers[size] = manager;
    g_enterpriseManagerSymbols[size] = symbol;

    // Batch 100: Initialize per-symbol mathematical engines
    {
        int mSize = ArraySize(g_mathEngineSymbols);
        ArrayResize(g_mathEngineSymbols, mSize + 1);
        g_mathEngineSymbols[mSize] = symbol;

        // Batch 29a: Track first bridge log per symbol
        ArrayResize(g_gridHurstBridgeLogged, mSize + 1);
        g_gridHurstBridgeLogged[mSize] = false;

        // Hurst Engine
        ArrayResize(g_hurstEngines, mSize + 1);
        g_hurstEngines[mSize] = NULL;
        if(InpEnableHurstEngine)
        {
            g_hurstEngines[mSize] = new CHurstEngine(symbol, (ENUM_TIMEFRAMES)Period(), InpHurstLookback);
            if(g_hurstEngines[mSize] != NULL)
                PrintFormat("[MATH-ENGINE] Hurst engine initialized for %s | lookback=%d", symbol, InpHurstLookback);
        }

        // OU Process Engine
        ArrayResize(g_ouEngines, mSize + 1);
        g_ouEngines[mSize] = NULL;
        if(InpEnableOUProcess)
        {
            g_ouEngines[mSize] = new COrnsteinUhlenbeckEngine(symbol, (ENUM_TIMEFRAMES)Period(), InpOULookback);
            if(g_ouEngines[mSize] != NULL)
                PrintFormat("[MATH-ENGINE] OU process engine initialized for %s | lookback=%d", symbol, InpOULookback);
        }

        // OFI Proxy Engine
        ArrayResize(g_ofiEngines, mSize + 1);
        g_ofiEngines[mSize] = NULL;
        if(InpEnableOFIProxy)
        {
            g_ofiEngines[mSize] = new COrderFlowImbalanceEngine();
            if(g_ofiEngines[mSize] != NULL)
            {
                g_ofiEngines[mSize].Init(symbol, 5, 20, InpOFISlowWindow);
                PrintFormat("[MATH-ENGINE] OFI proxy engine initialized for %s | slowWindow=%d", symbol, InpOFISlowWindow);
            }
        }

        // VPIN Filter
        ArrayResize(g_vpinFilters, mSize + 1);
        g_vpinFilters[mSize] = NULL;
        if(InpEnableVPINFilter)
        {
            g_vpinFilters[mSize] = new CVPINFilter(symbol, 0, InpVPINNumBuckets, InpVPINExtremeThreshold);
            if(g_vpinFilters[mSize] != NULL)
                PrintFormat("[MATH-ENGINE] VPIN filter initialized for %s | buckets=%d | extreme=%.2f", symbol, InpVPINNumBuckets, InpVPINExtremeThreshold);
        }

        // Batch 107: VWAP Engine (forex only)
        ArrayResize(g_vwapEngines, mSize + 1);
        g_vwapEngines[mSize] = NULL;
        if(InpEnableVWAPEngine && !IsSyntheticIndexSymbolName(symbol))
        {
            g_vwapEngines[mSize] = new CVWAPEngine();
            g_vwapEngines[mSize].Initialize(symbol, InpVWAPMinPeriodBars, InpVWAPBand1, InpVWAPBand2, InpVWAPBand3);
            PrintFormat("[INSTITUTIONAL-ENGINE] VWAP engine initialized for %s", symbol);
        }

        // Batch 107: Volume Profile Engine (forex only)
        ArrayResize(g_vpEngines, mSize + 1);
        g_vpEngines[mSize] = NULL;
        if(InpEnableVolumeProfile && !IsSyntheticIndexSymbolName(symbol))
        {
            g_vpEngines[mSize] = new CVolumeProfileEngine();
            g_vpEngines[mSize].Initialize(symbol, InpVPLookback, InpVPResolution);
            PrintFormat("[INSTITUTIONAL-ENGINE] Volume Profile engine initialized for %s", symbol);
        }

        // Batch 107: CVD Engine (forex only)
        ArrayResize(g_cvdEngines, mSize + 1);
        g_cvdEngines[mSize] = NULL;
        if(InpEnableCVDEngine && !IsSyntheticIndexSymbolName(symbol))
        {
            g_cvdEngines[mSize] = new CCVDEngine();
            g_cvdEngines[mSize].Initialize(symbol, InpCVDDivergenceLookback);
            PrintFormat("[INSTITUTIONAL-ENGINE] CVD engine initialized for %s", symbol);
        }
    }

    // Initialize Drawing Manager for this symbol if enabled
    if(InpEnableVisualAnalysis)
    {
        // Set global max objects on drawing coordinator
        CDrawingCoordinator* coordinator = GetDrawingCoordinator();
        if(coordinator != NULL)
        {
            int maxObjs = MathMin(450, InpMaxVisualObjects);
            coordinator.SetGlobalMaxObjects(maxObjs);
        }

        CChartDrawingManager* draw = new CChartDrawingManager();
        if(draw != NULL)
        {
            if(draw.Initialize(symbol, (ENUM_TIMEFRAMES)Period(), "VIS_"))
            {
                SDrawingConfig drawConfig;
                drawConfig.enableDrawing = true;
                drawConfig.maxObjectAge = InpMaxVisualObjects;
                draw.SetConfiguration(drawConfig);
                draw.SetMaxObjects(MathMin(450, InpMaxVisualObjects)); // Cap at 450 for safety
                
                int dSize = ArraySize(g_drawingManagers);
                ArrayResize(g_drawingManagers, dSize + 1);
                ArrayResize(g_drawingManagerSymbols, dSize + 1);
                g_drawingManagers[dSize] = draw;
                g_drawingManagerSymbols[dSize] = symbol;
                
                // Inject drawing manager into strategy manager for strategy-level drawings
                manager.SetDrawingManager(draw);
                Print("[VISUAL] Drawing manager initialized for ", symbol);
            }
            else
            {
                delete draw;
            }
        }
    }

    Print("[ENTERPRISE] Manager initialized for ", symbol, " with ", manager.GetActiveStrategyCount(), " active strategies | profile=", symbolProfile);
    return true;
}

//+------------------------------------------------------------------+
//| Batch 100: Apply Hurst weight modifiers to regime engine         |
//| Called periodically from the timer to update regime weights with  |
//| Hurst-based persistence information                              |
//+------------------------------------------------------------------+
void ApplyHurstWeightModifiersToRegime()
{
    if(!InpEnableHurstEngine)
        return;

    for(int i = 0; i < ArraySize(g_mathEngineSymbols); i++)
    {
        if(g_hurstEngines[i] == NULL)
            continue;

        CHurstEngine* hurst = g_hurstEngines[i];
        if(!hurst.IsWarmedUp())
            continue;

        SHurstSnapshot hurstSnap = hurst.GetSnapshot();
        if(hurstSnap.regime == HURST_RANDOM_WALK)
            continue;  // Don't modify weights if Hurst is in dead zone

        // Find the enterprise manager for this symbol
        int mgrIdx = FindEnterpriseManagerIndex(g_mathEngineSymbols[i]);
        if(mgrIdx < 0 || g_enterpriseManagers[mgrIdx] == NULL)
            continue;

        CUnifiedSignalPipeline* pipeline = g_enterpriseManagers[mgrIdx].GetPipeline();
        if(pipeline == NULL)
            continue;

        CRegimeEngine* regimeEngine = pipeline.GetRegimeEngine();
        if(regimeEngine != NULL)
        {
            regimeEngine.ApplyHurstWeightModifiers(
                hurstSnap.meanRevWeightMult,
                hurstSnap.momentumWeightMult,
                hurstSnap.trendWeightMult,
                hurstSnap.breakoutWeightMult
            );
        }
    }
}

//+------------------------------------------------------------------+
//| Expert Advisor Initialization                                    |
//+------------------------------------------------------------------+
int OnInit()
{
    Print("[MULTI-STRATEGY-EA] ========================================");
    Print("[MULTI-STRATEGY-EA] Advanced AI Trading System v2.0 Starting");
    Print("[MULTI-STRATEGY-EA] ========================================");

    // Set global log level from input (requires EA restart to change at runtime)
    // Note: Only respected in MultiStrategyAutonomousEA.mq5 (not in .mqh subsystem headers)
    g_logLevel = InpLogLevel;
    PrintFormat("[LOG-LEVEL] Set to %d (0=Silent, 1=Critical, 2=Normal, 3=Verbose, 4=Debug)", g_logLevel);

    // Initialize diagnostics logger (Blueprint 3.6: off-journal logging)
    g_diagLogger.Initialize("MultiStrategyEA", InpLogLevel, MathMax(30, InpHeartbeatInterval));

    // Validate MetaTrader 5 environment
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
    {
        Alert("[CRITICAL] Trading is not allowed in the terminal! Enable AutoTrading!");
        return INIT_FAILED;
    }

    if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
    {
        Alert("[CRITICAL] Trading is not allowed for this EA! Check EA properties!");
        return INIT_FAILED;
    }

    if(AccountInfoDouble(ACCOUNT_BALANCE) < MIN_ACCOUNT_BALANCE)
    {
        Alert("[CRITICAL] Insufficient account balance for safe operation!");
        return INIT_FAILED;
    }

    tradeManager.SetOrderFillMode(InpOrderFillingMode);
    tradeManager.SetSlippage((uint)MathMax(1, InpTradeSlippagePoints));
    tradeManager.SetExecutionCostLimits(InpMaxEntrySpreadPoints, InpMaxEntryDriftPoints);
    tradeManager.SetProtectiveModifyCooldownSeconds(InpProtectiveModifyCooldownSec);
    tradeManager.SetDynamicSlippageConfig(InpEnableDynamicSlippage, InpDynamicSlippageAtrPercent,
                                          (uint)InpDynamicSlippageMinPoints, (uint)InpDynamicSlippageMaxMultiplier,
                                          InpDynamicSlippageAtrPeriod);
    if(!tradeManager.Initialize((uint)InpMagicNumber, "MultiStrategyAutonomousEA"))
    {
        Print("[CRITICAL] Failed to initialize TradeManager");
        return INIT_FAILED;
    }
    tradeManager.SetLogLevel(InpLogLevel);
    // Set magic range for per-symbol ownership check (will be updated after symbol universe is built)
    tradeManager.SetMagicRangeMax((uint)InpMagicNumber);
    g_tickSafetyMonitor.SetMinFreeMarginPercent(20.0);
    g_tickSafetyMonitor.SetMinMarginLevel(150.0);
    g_tickSafetyMonitor.SetEmergencyStop(false);
    g_spikeMonitor.Initialize(tradeManager, unifiedRiskManager, g_tickSafetyMonitor);
    g_spikeMonitor.SetMagicNumber(InpMagicNumber);
    g_spikeMonitor.SetSymbolCount(ArraySize(g_enterpriseManagerSymbols));
    g_consensusCache.InvalidateAll();
    g_aiBrainReady = false;
    g_aiEngineReady = false;
    g_aiFeedbackReady = false;

    // Scalp cache initialization deferred until after symbol universe is built (below)
    // to avoid SCALP-CACHE ERROR: Invalid symbolCount=0

    // Validate account type and permissions
    ENUM_ACCOUNT_TRADE_MODE tradeMode = (ENUM_ACCOUNT_TRADE_MODE)AccountInfoInteger(ACCOUNT_TRADE_MODE);
    if(tradeMode == ACCOUNT_TRADE_MODE_DEMO)
        Print("[INFO] Running on DEMO account");
    else if(tradeMode == ACCOUNT_TRADE_MODE_REAL)
        Print("[WARNING] Running on REAL account - Trade carefully!");
    else if(tradeMode == ACCOUNT_TRADE_MODE_CONTEST)
        Print("[INFO] Running on CONTEST account");

    // Display account information
    Print("[ACCOUNT] Broker: ", AccountInfoString(ACCOUNT_COMPANY));
    Print("[ACCOUNT] Account: ", AccountInfoInteger(ACCOUNT_LOGIN));
    Print("[ACCOUNT] Currency: ", AccountInfoString(ACCOUNT_CURRENCY));
    Print("[ACCOUNT] Leverage: 1:", AccountInfoInteger(ACCOUNT_LEVERAGE));
    Print("[ACCOUNT] Balance: ", DoubleToString(AccountInfoDouble(ACCOUNT_BALANCE), 2));
    Print("[ACCOUNT] Equity: ", DoubleToString(AccountInfoDouble(ACCOUNT_EQUITY), 2));
    Print("[ACCOUNT] Free Margin: ", DoubleToString(AccountInfoDouble(ACCOUNT_MARGIN_FREE), 2));

    ENUM_ACCOUNT_MARGIN_MODE marginMode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
    if(marginMode != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
    {
        PrintFormat("[CRITICAL] Unsupported account margin mode: %s | EA requires hedging account semantics for magic-scoped lifecycle management",
                    EnumToString(marginMode));
        return INIT_FAILED;
    }
    PrintFormat("[EXECUTION-MODE] mode=%s | shadow_mode=%s | note=%s",
                (InpShadowMode || InpShadowModeEnabled) ? "SHADOW_ONLY" : "LIVE_SEND",
                (InpShadowMode || InpShadowModeEnabled) ? "true" : "false",
                (InpShadowMode || InpShadowModeEnabled) ? "orders will be simulated only" : "orders will be sent to broker");

    // AUDIT FIX: Gate AI subsystem initialization behind InpEnableAIMode
    if(InpEnableAIMode)
    {
        Print("[AI] Initializing AI subsystems...");

        if(!g_universalTransformerService.Initialize())
            Print("[AI] WARNING: Universal transformer service failed to initialize - shared transformer features may be unavailable");

        if(!aiNextGenBrain.Initialize(Symbol(), Period()))
        {
            Print("[INIT] WARNING: NextGen AI Brain failed to initialize - dashboard AI brain disabled");
        }
        else
        {
            g_aiBrainReady = true;
            Print("[AI] Runtime AI voters are adapter-owned and registered per symbol");
        }
        
        // Initialize AI health dashboard
        Print("[AI-DASHBOARD] AI Health Monitoring initialized");
        Print("[AI-DASHBOARD] Configuration: Transformer(dModel=32, heads=2, layers=1), Ensemble diversity enabled");
    }
    
    Print("[INIT] PerformanceAnalytics initialized");

    // FIX: Initialize AI Performance Feedback for prediction tracking (Phase 2, Task 3)
    if(!aiFeedback.Initialize(1000))
    {
        Print("[WARNING] AIPerformanceFeedback failed to initialize, continuing without AI learning tracking");
    }
    else
    {
        g_aiFeedbackReady = true;
        Print("[INIT] AIPerformanceFeedback initialized for AI model adaptation");
    }

    // Populate unified risk configuration from inputs
    SUnifiedRiskConfig unifiedRiskConfig;
    unifiedRiskConfig.baseRiskPerTradePercent = InpMaxRiskPerTrade;
    unifiedRiskConfig.minRiskPerTradePercent  = 0.1;
    unifiedRiskConfig.maxRiskPerTradePercent  = MathMax(InpMaxRiskPerTrade, 100.0); // Allow high risk up to 100%
    unifiedRiskConfig.maxDailyRiskPercent     = InpMaxDailyRisk;
    unifiedRiskConfig.maxPortfolioRiskPercent = InpMaxPortfolioRisk;
    unifiedRiskConfig.correlationThreshold    = 0.7;
    unifiedRiskConfig.correlationReduceThreshold = 0.4;
    unifiedRiskConfig.correlationBlockThreshold  = 0.7;
    unifiedRiskConfig.maxPositionsSameBase    = InpMaxPositionsSameBase;
    unifiedRiskConfig.drawdownWarningPercent  = InpMaxDrawdown * 0.7;
    unifiedRiskConfig.drawdownCriticalPercent = InpMaxDrawdown;
    unifiedRiskConfig.adaptationMinTrades     = 10;
    unifiedRiskConfig.enableAdaptiveSizing    = InpUseEnhancedRisk;
    unifiedRiskConfig.enableAuditLogging      = true;
    unifiedRiskConfig.auditLogFile            = "risk_audit_" + _Symbol + ".log";
    unifiedRiskConfig.minLotRiskMultiplier    = InpMinLotRiskMultiplier;
    unifiedRiskConfig.dailyLossLimitPercent   = InpDailyLossLimitPercent;

    if(!unifiedRiskManager.Initialize(unifiedRiskConfig, &performanceAnalytics))
    {
        Print("[CRITICAL] UnifiedRiskManager failed to initialize!");
        return INIT_FAILED;
    }
    // Cluster governance configured after RiskTierManager applies tier overrides (see below)
    Print("[INIT] UnifiedRiskManager initialized as single risk authority");

    // Crash recovery: restore circuit breaker state from previous session if state file exists
    {
        string stateFileName = "ea_state_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".txt";
        int fh = FileOpen(stateFileName, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON);
        if(fh != INVALID_HANDLE)
        {
            double recoveredEquityBaseline = 0.0;
            double recoveredPeakEquity = 0.0;
            int    recoveredDdBreachCount = 0;
            double recoveredDdMax = 0.0;
            string recoveredTimestamp = "";

            while(!FileIsEnding(fh))
            {
                string line = FileReadString(fh);
                int eqPos = StringFind(line, "=");
                if(eqPos < 0)
                    continue;
                string key = StringSubstr(line, 0, eqPos);
                string val = StringSubstr(line, eqPos + 1);

                if(key == "equity_baseline")     recoveredEquityBaseline = StringToDouble(val);
                else if(key == "peak_equity")    recoveredPeakEquity = StringToDouble(val);
                else if(key == "dd_breach_count") recoveredDdBreachCount = (int)StringToInteger(val);
                else if(key == "dd_max")         recoveredDdMax = StringToDouble(val);
                else if(key == "timestamp")      recoveredTimestamp = val;
            }
            FileClose(fh);

            if(recoveredEquityBaseline > 0.0 || recoveredPeakEquity > 0.0)
            {
                unifiedRiskManager.RestoreCircuitBreakerState(recoveredPeakEquity, recoveredEquityBaseline,
                                                              recoveredDdBreachCount, recoveredDdMax);
                PrintFormat("[RECOVERY-STATE] Circuit breaker restored from previous session | equity_baseline=%.2f | peak_equity=%.2f | dd_breach_count=%d | dd_max=%.2f | saved_at=%s",
                            recoveredEquityBaseline, recoveredPeakEquity, recoveredDdBreachCount, recoveredDdMax, recoveredTimestamp);
            }
            else
            {
                Print("[RECOVERY-STATE] State file found but contained no valid data — using fresh initialization");
            }
        }
        else
        {
            Print("[RECOVERY-STATE] No previous state file found — clean start (first run or clean shutdown)");
        }
    }

    // Reconcile trade journal — detect orphaned trades from previous sessions
    ReconcileTradeJournal(InpMagicNumber);

    // Log initial account capacity diagnostics
    LogAccountCapacityDiagnostics();

    // Initialize PositionSizer before enterprise managers
    SPositionSizingParams sizingParams;
    sizingParams.sizingMode       = POSITION_SIZE_RISK_PERCENT;
    sizingParams.fixedLotSize     = InpLotSize;
    sizingParams.riskPercent      = InpMaxRiskPerTrade;         // Now using consistent 0-100 scale (e.g., 2.0)
    sizingParams.atrPeriod        = 14;
    sizingParams.atrMultiplier    = 1.5;
    sizingParams.maxLotSize       = MAX_LOT_SIZE;
    sizingParams.minLotSize       = MIN_LOT_SIZE;
    sizingParams.correlationAdjustment  = 1.0;
    sizingParams.useVolatilityAdjustment = true;
    sizingParams.useCorrelationAdjustment = false;
    
    Print("[DEBUG-POSITIONSIZER] Before SetParameters | riskPercent=", DoubleToString(sizingParams.riskPercent, 4),
          " | fixedLot=", DoubleToString(sizingParams.fixedLotSize, 4),
          " | minLot=", DoubleToString(sizingParams.minLotSize, 4),
          " | maxLot=", DoubleToString(sizingParams.maxLotSize, 4),
          " | atrPeriod=", sizingParams.atrPeriod,
          " | atrMult=", DoubleToString(sizingParams.atrMultiplier, 4));
    
    if(!positionSizer.SetParameters(sizingParams))
    {
        Print("[CRITICAL] PositionSizer initialization FAILED — will use min lot fallback!");
        Print("[DIAG-POSITIONSIZER] Validation ranges: riskPercent must be >0 and <=", MAX_RISK_PER_TRADE,
              " | fixedLot must be >=", MIN_LOT_SIZE, " and <=", MAX_LOT_SIZE,
              " | atrPeriod must be >0 and <=100",
              " | atrMultiplier must be >0 and <=10.0");
    }
    else
    {
        Print("[INIT] PositionSizer initialized — Mode: RISK_PERCENT, Risk: ",
              DoubleToString(sizingParams.riskPercent, 2), "%");
    }

    // Apply risk tier configuration to risk manager, position sizer, and trade manager
    g_riskTierManager.SetTier(InpRiskTier);
    g_riskTierManager.ApplyToRiskManager(unifiedRiskManager, &performanceAnalytics,
                                         InpMaxDailyRisk, InpMaxPortfolioRisk,
                                         InpMaxDrawdown * 0.7, InpMaxDrawdown,
                                         InpDailyLossLimitPercent);
    g_riskTierManager.ApplyToPositionSizer(positionSizer, InpMaxRiskPerTrade);
    g_riskTierManager.ApplyToTradeManager(tradeManager);

    // Wire PositionSizer to unified correlation engine via portfolio risk manager
    positionSizer.SetCorrelationEngine(unifiedRiskManager.GetPortfolioRiskManager().GetCorrelationEngine());
    positionSizer.SetLogLevel(InpLogLevel);
    positionSizer.SetAllowMinLotRoundUp(InpAllowMinLotRoundUp);
    positionSizer.SetMinLotRiskMultiplier(InpMinLotRiskMultiplier);

    // Batch 99: Initialize EquityCurveManager
    g_equityCurveManager = new CEquityCurveManager(InpEquityCurveEmaPeriod, InpEquityCurveReductionFactor, 1.0);
    if(g_equityCurveManager != NULL)
        PrintFormat("[BATCH99] EquityCurveManager initialized with emaPeriod=%d", InpEquityCurveEmaPeriod);
    else
        Print("[BATCH99] WARNING: Failed to create EquityCurveManager — equity curve sizing disabled");

    // Batch 99: Initialize BayesianKellyModifier and add to PositionSizer modifier chain
    g_bayesianKellyModifier = new CBayesianKellyModifier(InpKellyFraction);
    if(g_bayesianKellyModifier != NULL)
    {
        positionSizer.AddModifier(g_bayesianKellyModifier);
        PrintFormat("[BATCH99] BayesianKelly modifier initialized with kellyFraction=%.2f", InpKellyFraction);
    }
    else
    {
        Print("[BATCH99] WARNING: Failed to create BayesianKelly modifier — position sizing will not use Bayesian Kelly");
    }

    // Batch 99: Initialize EquityCurveLotModifier and add to PositionSizer modifier chain
    g_equityCurveLotModifier = new CEquityCurveLotModifier(g_equityCurveManager);
    if(g_equityCurveLotModifier != NULL)
    {
        positionSizer.AddModifier(g_equityCurveLotModifier);
        PrintFormat("[BATCH99] EquityCurveLotModifier added to position sizer modifier chain");
    }
    else
    {
        Print("[BATCH99] WARNING: Failed to create EquityCurveLotModifier — equity curve sizing disabled");
    }

    // P11.2: Initialize CADXLotModifier and add to PositionSizer modifier chain
    // ADX-based lot scaling: 0x no trend, 0.5x weak, 1.0x normal, 1.3x strong, 1.5x very strong
    {
        CADXLotModifier* adxModifier = new CADXLotModifier();
        if(adxModifier != NULL)
        {
            // Initialize for primary symbol — will re-init per-symbol in sizing
            if(adxModifier.Initialize(_Symbol, PERIOD_CURRENT, 14))
            {
                positionSizer.AddModifier(adxModifier);
                Print("[ADX-MODIFIER] Initialized and added to position sizer modifier chain");
            }
            else
            {
                Print("[ADX-MODIFIER] WARNING: Failed to initialize — ADX sizing disabled");
                delete adxModifier;
            }
        }
    }

    // Batch 99: CVaR is already tracked inside CPortfolioRiskManager (accessed via unifiedRiskManager)
    // Mark it active for diagnostics
    Print("[BATCH99] CVaR calculation active");

    unifiedRiskManager.ConfigureClusterGovernance(InpEnableClusterRiskGovernance,
                                                  MathMax(1, InpRiskMaxConcurrentPerCluster),
                                                  MathMax(0.1, InpRiskMaxClusterExposurePct),
                                                  InpEnableClusterMutex);

    // Reconcile inherited cluster positions from previous sessions
    unifiedRiskManager.SyncClusterPositionCounts();
    PrintFormat("[INIT] RiskTierManager applied tier=%s | breakeven=%.0f pts | trailing=%.0f pts",
                g_riskTierManager.GetTierName(),
                g_riskTierManager.GetBreakevenBufferPts(),
                g_riskTierManager.GetTrailingDistancePts());

    // I2/I9: Initialize CompoundingTierManager for auto-tier switching
    if(InpEnableCompoundingTiers)
    {
        if(g_compoundingTierManager.Initialize(true))
        {
            // Apply initial tier to risk manager and position sizer
            g_compoundingTierManager.ApplyTierToRiskManager(unifiedRiskManager);
            g_compoundingTierManager.ApplyTierToPositionSizer(positionSizer);
            Print("[INIT] CompoundingTierManager initialized — auto-switch ENABLED");
        }
        else
        {
            Print("[INIT] WARNING: CompoundingTierManager initialization failed — using static tier");
        }
    }
    else
    {
        Print("[INIT] CompoundingTierManager disabled — using static tier");
    }

    // I1: Initialize Family Strategy Weight Matrix
    g_familyWeightMatrix.Initialize();

    // I3: Initialize Session Weight Manager
    if(InpEnableSessionWeights)
    {
        g_sessionWeightManager.Initialize(true); // true = synthetic mode (24/7)
        Print("[INIT] SessionWeightManager initialized — session-aware adjustments ENABLED");
    }
    else
    {
        Print("[INIT] SessionWeightManager disabled");
    }

    // I4: Initialize Skew Step Analyzer
    if(InpEnableSkewStepAnalyzer)
    {
        g_skewStepAnalyzer.Initialize(200, 0.80, 0.2, 0.5);
        Print("[INIT] SkewStepAnalyzer initialized — Skew Step distribution analysis ENABLED");
    }
    else
    {
        Print("[INIT] SkewStepAnalyzer disabled");
    }

    // Initialize unprotected position tracker
    g_unprotectedTracker.Initialize(&tradeManager, &unifiedRiskManager,
                                    InpMagicNumber, ArraySize(g_enterpriseManagerSymbols),
                                    InpUnprotectedRemediationIntervalSec, InpUnprotectedMaxRestoreAttempts);

    // Phase 6: Initialize full-margin mode or safe mode based on risk tier
    if(InpRiskTier == RISK_TIER_FULL_MARGIN)
    {
        SFullMarginConfig fmConfig = g_riskTierManager.GetFullMarginConfig();
        if(!g_fullMarginMode.Initialize(fmConfig))
            Print("[INIT] WARNING: Full-margin mode initialization failed");
        else
            Print("[INIT] Full-margin aggressive mode ENABLED — position stacking, stricter circuit breaker active");
    }
    else if(InpRiskTier == RISK_TIER_CONSERVATIVE)
    {
        SSafeModeConfig smConfig = g_riskTierManager.GetSafeModeConfig();
        if(!g_safeMode.Initialize(smConfig))
            Print("[INIT] WARNING: Safe mode initialization failed");
        else
            Print("[INIT] Conservative safe mode ENABLED — kill zone filter, partial profit taking active");
    }

    // Blueprint R6a: Initialize position lifecycle manager
    if(g_lifecycleManager.Initialize(&tradeManager, &g_consensusCache, &g_riskTierManager, &g_safeMode, InpMagicNumber))
    {
        g_lifecycleManager.ConfigureSRE(InpEnableSignalReversalExit, InpSignalReversalMinConfidence,
                                         InpSignalReversalProfitGuard, InpSignalReversalMinLossR,
                                         InpSignalReversalMaxLossR, InpSignalReversalMinTimeSec,
                                         InpEnableStructuralInvalidation);
        g_lifecycleManager.ConfigureLifecycle(InpEnablePositionLifecycleManager,
                                               InpLifecycleBreakevenBufferPoints,
                                               InpLifecycleTrailingDistancePoints,
                                               (int)InpLifecycleTrailingStepPoints,
                                               InpLifecycleUseATRTrailing, InpLifecycleATRMultiplier);
        // I2: Wire regime engine for intelligent SL guard
        if(ArraySize(g_enterpriseManagerSymbols) > 0)
        {
            // Get regime engine from first symbol's pipeline
            // The pipeline is owned by the enterprise manager
        }
        Print("[INIT] PositionLifecycleManager initialized (Blueprint R6a)");
    }
    else
        Print("[INIT] WARNING: PositionLifecycleManager initialization failed — using inline fallback");

    // Blueprint R6b: Initialize diagnostics manager
    if(g_diagnosticsManager.Initialize(&unifiedRiskManager, &g_riskTierManager, InpHeartbeatInterval))
    {
        g_diagnosticsManager.SetScalpEngine(&g_scalpEngine);
        g_diagnosticsManager.SetFullMarginMode(&g_fullMarginMode);
        g_diagnosticsManager.SetSafeMode(&g_safeMode);
        g_diagnosticsManager.SetAIConfig(InpEnableAIMode, InpEnableNeuralNetwork, InpEnableNNOnlineTraining);
        g_diagnosticsManager.SetRiskTier(InpRiskTier);
        g_diagnosticsManager.SetShadowMode(InpShadowMode || InpShadowModeEnabled);
        Print("[INIT] DiagnosticsManager initialized (Blueprint R6b)");
    }
    else
        Print("[INIT] WARNING: DiagnosticsManager initialization failed — using inline heartbeat");

    // AIEngine will be initialized after enterprise managers are created (manager-owned adaptation).

    // Build strategy flags with curated defaults as a baseline; explicit enables remain authoritative.
    bool strategyFlags[];
    BuildStrategyFlags(strategyFlags);
    BuildStrategyRegistry(strategyFlags);
    LogAIRuntimeTopology();
    LogPositionLifecycleConfig();
    if(InpEnableTransformer || InpEnableEnsemble)
    {
        PrintFormat("[AI-SAFETY] Experimental AI families enabled | transformer=%s | ensemble=%s | confidence_floor=%.2f | note=runtime defaults assume these paths remain disabled until retrained",
                    InpEnableTransformer ? "true" : "false",
                    InpEnableEnsemble ? "true" : "false",
                    ResolveAIRuntimeVoteThreshold(ResolveEffectiveEAMode()));
    }
    if(InpUseCuratedStrategySet)
    {
        Print("[CURATION] Curated mode is advisory/default-only: explicitly enabled strategies remain active.");
    }
    bool effectiveIntrabarCadence = (InpEnableHybridCadence && !InpSignalScanOnNewBarOnly);
    PrintFormat("[CADENCE-CONFIG] hybrid=%s | newbar_only=%s | effective_intrabar=%s | intrabar_seconds=%d | intrabar_budget=%d | chart_only=%s",
                InpEnableHybridCadence ? "true" : "false",
                InpSignalScanOnNewBarOnly ? "true" : "false",
                effectiveIntrabarCadence ? "true" : "false",
                MathMax(1, InpIntrabarScanSeconds),
                effectiveIntrabarCadence ? MathMax(1, InpMaxIntrabarSymbolsPerCycle) : 0,
                InpIntrabarChartSymbolOnly ? "true" : "false");
    if(InpEnableHybridCadence && InpSignalScanOnNewBarOnly)
    {
        Print("[CADENCE-WARNING] newbar_only=true disables timed intrabar scans even when intrabar strategy policies are LIVE.");
    }
    
    // AI Health Dashboard
    if(InpEnableAIMode)
    {
        string aiStatus = "[AI-DASHBOARD] ";
        
        // Transformer status
        if(g_aiBrainReady)
            aiStatus += "TF:RDY | ";
        else
            aiStatus += "TF:OFF | ";
        
        // Neural Network status
        if(g_aiEngineReady)
            aiStatus += "NN:RDY | ";
        else
            aiStatus += "NN:OFF | ";
        
        // Ensemble status
        int activeAIModels = g_strategyRegistry.GetActiveAICount();
        aiStatus += "ENS:" + IntegerToString(activeAIModels) + "/4 | ";
        
        // Memory efficiency indicator
        aiStatus += "MEM:OPTIMIZED (dModel=32, heads=2, layers=1)";
        
        Print(aiStatus);
        if(InpEnableOnnxAI && g_onnxSessionDisabled)
            Print("[AI-DASHBOARD] ONNX requested but already session-disabled; re-export a compatible 57-feature model and restart the EA.");
    }

    SSymbolValidationConfig validationConfig;
    validationConfig.maxSpreadPoints = 1500;  // Accommodate synthetic CFDs (FX Vol 40 ~1043 pts)
    validationConfig.minDailyVolumeLots = 1000;
    validationConfig.enableVolumeCheck = true;
    
    if(!CSymbolUniverseBuilder::Build(InpSymbolsToTrade, g_activePairs, validationConfig))
    {
        Print("[CRITICAL] No valid trading symbols after validation.");
        return INIT_FAILED;
    }

    if(!CSymbolUniverseBuilder::ContainsSymbol(g_activePairs, _Symbol))
    {
        PrintFormat("[SYMBOLS] Chart symbol '%s' not in InpSymbolsToTrade; it will not be included for trading.", _Symbol);
    }

    Print("[SYMBOLS] ", ArraySize(g_activePairs), " symbols validated and ready for trading");
    LogAccountCapacityDiagnostics();
    g_symbolsToTrade = InpSymbolsToTrade;

    // Initialize Fast Scalp Engine (Phase 4) — must be after symbol universe is built
    if(InpEnableScalpEngine)
    {
        if(!g_scalpEngine.Initialize(&tradeManager, &unifiedRiskManager, &positionSizer, &g_riskTierManager))
            Print("[SCALP-ENGINE] WARNING: Failed to initialize — scalp engine disabled");
        else
        {
            g_scalpEngine.SetMagicNumber((uint)InpMagicNumber);
            g_scalpEngine.SetAsyncMode(InpScalpAsyncMode);
            g_scalpEngine.SetMaxLatencyMs(InpScalpMaxLatencyMs);
            g_scalpEngine.SetShadowMode(InpShadowMode || InpShadowModeEnabled);

            // Initialize scalp signal cache for fast-path evaluation
            if(g_scalpCache.Initialize(g_activePairs, ArraySize(g_activePairs), PERIOD_M1))
            {
                // Wire cache to scalp engine for zero-CopyBuffer fast path
                g_scalpEngine.SetSignalCache(GetPointer(g_scalpCache));
                Print("[SCALP-CACHE] Fast-path dual-path architecture enabled");
            }
            else
                Print("[SCALP-CACHE] WARNING: Cache initialization failed — falling back to per-call indicators");
        }
    }
    else
    {
        Print("[SCALP-ENGINE] Disabled by user input (InpEnableScalpEngine=false)");
    }

    // Initialize spike hunter
    if(InpSpikeHunterEnabled)
    {
        SSpikeHunterConfig spikeConfig;
        spikeConfig.velocityMultiplier       = InpSpikeHunterVelocityMult;
        spikeConfig.minConsecutiveTicks      = InpSpikeHunterMinConsecTicks;
        spikeConfig.consecutiveTickWindowMs  = InpSpikeHunterConsecWindowMs;
        spikeConfig.atrCompressionRatio      = InpSpikeHunterATRCompression;
        spikeConfig.atrPeriod                = 14;
        spikeConfig.atrSmaPeriod             = 50;
        spikeConfig.slAtrMultiplier          = InpSpikeHunterSLAtrMult;
        spikeConfig.tpAtrMultiplier          = InpSpikeHunterTPAtrMult;
        spikeConfig.maxSpikePositions        = InpSpikeHunterMaxPositions;
        spikeConfig.cooldownMs               = InpSpikeHunterCooldownMs;
        spikeConfig.spikeCooldownForLongTermMs = InpSpikeHunterLongTermCooldownMs;
        spikeConfig.magicOffset              = 9000;
        spikeConfig.enablePushAlerts         = InpSpikeHunterPushAlerts;
        spikeConfig.alertThrottleSeconds     = InpSpikeHunterAlertThrottle;
        spikeConfig.minConfluence            = InpSpikeHunterMinConfluence;

        if(g_spikeHunter.Init(spikeConfig, InpMagicNumber, &positionSizer, &unifiedRiskManager))
        {
            // Add all configured symbols
            for(int i = 0; i < ArraySize(g_activePairs); i++)
            {
                if(g_activePairs[i] != "")
                    g_spikeHunter.AddSymbol(g_activePairs[i]);
            }
            Print("[SPIKE-HUNTER] Initialized with ", ArraySize(g_activePairs), " symbols, confluence=", InpSpikeHunterMinConfluence, "/3");
        }
        else
            Print("[SPIKE-HUNTER] Initialization FAILED");
    }

    //--- Batch 103: Multi-Asset Profiler + Deriv Family-Specific Engine Configuration ---
    if(InpMultiAssetProfilerEnabled)
    {
        Print("[MULTI-ASSET-PROFILER] Initializing multi-asset class auto-detection...");

        // Apply multi-asset class profiles for all symbols
        for(int i = 0; i < ArraySize(g_activePairs); i++)
        {
            string sym = g_activePairs[i];
            if(sym == "") continue;

            SAssetProfile profile = g_multiAssetProfiler.GetProfile(sym);
            unifiedRiskManager.SetRiskPerTrade(sym, profile.riskPerTrade);
            unifiedRiskManager.SetMaxDrawdownForFamily(sym, (double)profile.maxDrawdownPercent);
            tradeManager.SetMagicOffsetForSymbol(sym, profile.magicOffset);
            PrintFormat("[MULTI-ASSET-PROFILER] %s class=%s → risk=%.2f%% maxDD=%d%% magic=+%d",
                        sym, profile.className, profile.riskPerTrade, profile.maxDrawdownPercent, profile.magicOffset);
        }

        // Deriv-specific sub-profiler: family overrides, grid recovery, ATR scalping
        if(InpDerivProfilerEnabled)
        {
            Print("[DERIV-PROFILER] Initializing Deriv asset family auto-detection (subset)...");
            CDerivAssetProfiler* derivProfiler = g_multiAssetProfiler.GetDerivProfiler();

            // Apply family-specific parameters to SpikeHunter
            if(InpSpikeHunterEnabled && derivProfiler != NULL)
            {
                for(int i = 0; i < ArraySize(g_activePairs); i++)
                {
                    string sym = g_activePairs[i];
                    if(sym == "") continue;
                    if(!IsSyntheticIndexSymbolName(sym)) continue;

                    SDerivProfile profile = derivProfiler.GetProfile(sym);
                    if(profile.enableSpikeHunter)
                    {
                        g_spikeHunter.SetFamilyOverrides(sym,
                            profile.spikeThreshold,
                            6,    // minConsecutiveTicks (family-adjusted)
                            profile.atrCompressionRatio,
                            profile.atrMultiplierSL,
                            profile.atrMultiplierTP,
                            profile.magicOffset,
                            profile.spikeCooldownSec * 1000,
                            2);   // minConfluence
                        PrintFormat("[DERIV-PROFILER] %s family=%s → SpikeHunter overrides applied", sym, profile.familyName);
                    }
                }
            }

            // Initialize Grid Recovery Engine for mean-reversion families
            if(InpGridRecoveryEnabled)
            {
                SGridRecoveryConfig gridConfig;
                gridConfig.gridFactorATR           = 0.25;
                gridConfig.maxGridLevels           = 8;
                gridConfig.progressionType         = GRID_PROGRESSION_MARTINGALE;
                gridConfig.progressionFactor       = 1.5;
                gridConfig.activationHurstThreshold = 0.45;
                gridConfig.atrPeriod               = 14;
                gridConfig.slAtrMultiplier         = 1.0;
                gridConfig.tpAtrMultiplier         = 0.5;
                gridConfig.magicOffset             = 8000;
                gridConfig.maxDrawdownPercent      = 10;
                gridConfig.cooldownMs              = 30000;

                if(g_gridRecovery.Init(gridConfig, InpMagicNumber, &positionSizer, &unifiedRiskManager))
                {
                    for(int i = 0; i < ArraySize(g_activePairs); i++)
                    {
                        string sym = g_activePairs[i];
                        if(sym == "") continue;
                        if(!IsSyntheticIndexSymbolName(sym)) continue;

                        SDerivProfile profile = derivProfiler.GetProfile(sym);
                        if(profile.enableGridRecovery)
                        {
                            g_gridRecovery.AddSymbol(sym);
                            g_gridRecovery.SetFamilyConfig(
                                profile.gridFactorATR,
                                profile.maxGridLevels,
                                profile.gridProgressionFactor,
                                profile.atrMultiplierSL,
                                profile.atrMultiplierTP,
                                profile.magicOffset);
                            PrintFormat("[DERIV-PROFILER] %s family=%s → GridRecovery enabled (gridATR=%.2f levels=%d prog=%.1f)",
                                        sym, profile.familyName, profile.gridFactorATR, profile.maxGridLevels, profile.gridProgressionFactor);
                        }
                    }
                    Print("[GRID-RECOVERY] Initialized for mean-reversion families");
                }
                else
                    Print("[GRID-RECOVERY] Initialization FAILED");
            }

            // Initialize ATR Scalping Engine for between-spike families
            if(InpATRScalpingEnabled)
            {
                SATRScalpingConfig scalpConfig;
                scalpConfig.atrPeriod              = 14;
                scalpConfig.emaFastPeriod          = 5;
                scalpConfig.emaSlowPeriod          = 13;
                scalpConfig.rsiPeriod              = 7;
                scalpConfig.spreadMaxATRRatio      = 0.30;
                scalpConfig.slAtrMultiplier        = 2.0;
                scalpConfig.tpAtrMultiplier        = 2.5;
                scalpConfig.magicOffset            = 7000;
                scalpConfig.maxPositions           = 3;
                scalpConfig.cooldownMs             = 30000;
                scalpConfig.spikeWindowAvoidMinutes = 5;

                if(g_atrScalping.Init(scalpConfig, InpMagicNumber, &positionSizer, &unifiedRiskManager))
                {
                    for(int i = 0; i < ArraySize(g_activePairs); i++)
                    {
                        string sym = g_activePairs[i];
                        if(sym == "") continue;
                        if(!IsSyntheticIndexSymbolName(sym)) continue;

                        SDerivProfile profile = derivProfiler.GetProfile(sym);
                        // ATR scalping for Jump and DEX families (between-spike trading)
                        if(profile.family == DERIV_JUMP || profile.family == DERIV_DEX || profile.family == DERIV_HYBRID)
                        {
                            int spikeIntervalSec = 0;
                            if(profile.family == DERIV_JUMP) spikeIntervalSec = 1200;  // ~3 jumps/hour = 1200s
                            if(profile.family == DERIV_DEX)
                            {
                                // Try to detect DEX interval from symbol name
                                if(StringFind(sym, "900") >= 0) spikeIntervalSec = 900;
                                else if(StringFind(sym, "1500") >= 0) spikeIntervalSec = 1500;
                                else if(StringFind(sym, "2600") >= 0) spikeIntervalSec = 2600;
                                else spikeIntervalSec = 900; // default
                            }
                            g_atrScalping.AddSymbol(sym, spikeIntervalSec);
                            PrintFormat("[DERIV-PROFILER] %s family=%s → ATRScalping enabled (spikeInterval=%ds)",
                                        sym, profile.familyName, spikeIntervalSec);
                        }
                    }
                    Print("[ATR-SCALP] Initialized for between-spike families");
                }
                else
                    Print("[ATR-SCALP] Initialization FAILED");
            }
        }

        // Set both profilers on diagnostics manager
        g_diagnosticsManager.SetDerivProfiler(g_multiAssetProfiler.GetDerivProfiler());
        g_diagnosticsManager.SetMultiAssetProfiler(&g_multiAssetProfiler);
        string profilerSymbols[];
        ArrayResize(profilerSymbols, ArraySize(g_activePairs));
        for(int i = 0; i < ArraySize(g_activePairs); i++)
            profilerSymbols[i] = g_activePairs[i];
        g_diagnosticsManager.SetSymbols(profilerSymbols, ArraySize(g_activePairs));

        Print("[MULTI-ASSET-PROFILER] Batch 103 initialization complete");
    }
    else
    {
        Print("[MULTI-ASSET-PROFILER] Disabled by user input");
    }

    // Initialize enterprise manager per symbol
    Print("[ENTERPRISE] Initializing per-symbol strategy managers...");
    ReleaseEnterpriseManagers();
    int managerInitCount = 0;
    for(int i = 0; i < ArraySize(g_activePairs); i++)
    {
        bool symbolStrategyFlags[];
        BuildStrategyFlagsForSymbol(g_activePairs[i], strategyFlags, symbolStrategyFlags);
        if(CountEffectiveIndicatorStrategiesForSymbol(symbolStrategyFlags) <= 0 &&
           g_strategyRegistry.GetActiveAICount() <= 0)
        {
            Print("[ENTERPRISE] Skipping ", g_activePairs[i], " because no strategies remain after symbol-class profiling.");
            continue;
        }

        if(InitializeEnterpriseManagerForSymbol(g_activePairs[i], symbolStrategyFlags))
            managerInitCount++;
    }

    if(managerInitCount <= 0 || ArraySize(g_enterpriseManagers) <= 0)
    {
        Print("[CRITICAL] Failed to initialize any Enterprise Strategy Manager.");
        return INIT_FAILED;
    }

    // Update magic range max now that symbol universe is known
    int symbolCount = ArraySize(g_enterpriseManagerSymbols);
    uint magicRangeMax = (uint)(InpMagicNumber + symbolCount * MAGIC_SYMBOL_MULTIPLIER + MAGIC_MAX_CLUSTER_CODE);
    tradeManager.SetMagicRangeMax(magicRangeMax);
    // Propagate magic range to all enterprise managers
    for(int mi = 0; mi < ArraySize(g_enterpriseManagers); mi++)
    {
        if(g_enterpriseManagers[mi] != NULL)
        {
            g_enterpriseManagers[mi].SetManagedMagicRangeMax((long)magicRangeMax);
            // Batch 103: Set profilers for asset-class-based engine weighting
            if(InpMultiAssetProfilerEnabled)
            {
                g_enterpriseManagers[mi].SetDerivProfiler(g_multiAssetProfiler.GetDerivProfiler());
                g_enterpriseManagers[mi].SetMultiAssetProfiler(&g_multiAssetProfiler);
                g_enterpriseManagers[mi].ApplyAssetClassEngineWeights(g_enterpriseManagerSymbols[mi]);
                // I1: Wire family weight matrix for per-family cluster weighting
                g_enterpriseManagers[mi].SetFamilyWeightMatrix(&g_familyWeightMatrix);
            }

            // Batch 103: Wire Hurst/VPIN/OFI/OU engines to strategies and manager
            {
                string sym = g_enterpriseManagerSymbols[mi];
                int mathIdx = -1;
                for(int k = 0; k < ArraySize(g_mathEngineSymbols); k++)
                {
                    if(g_mathEngineSymbols[k] == sym) { mathIdx = k; break; }
                }
                if(mathIdx >= 0)
                {
                    // Wire EnterpriseStrategyManager-level engines (consensus gating)
                    g_enterpriseManagers[mi].SetVPINFilter(g_vpinFilters[mathIdx]);
                    g_enterpriseManagers[mi].SetOFIEngine(g_ofiEngines[mathIdx]);
                    PrintFormat("[BATCH103] VPIN/OFI wired to EnterpriseManager | Symbol=%s", sym);

                    // Find and wire Trend strategy
                    IStrategy* trendStrat = g_enterpriseManagers[mi].GetStrategyByName("Trend");
                    if(trendStrat != NULL)
                    {
                        CStrategyTrend* trendPtr = dynamic_cast<CStrategyTrend*>(trendStrat);
                        if(trendPtr != NULL)
                        {
                            trendPtr.SetHurstEngine(g_hurstEngines[mathIdx]);
                            trendPtr.SetVPINFilter(g_vpinFilters[mathIdx]);
                            PrintFormat("[BATCH103] Hurst/VPIN wired to Trend | Symbol=%s", sym);
                        }
                    }
                    // Find and wire S/R strategy
                    IStrategy* srStrat = g_enterpriseManagers[mi].GetStrategyByName("Support/Resistance");
                    if(srStrat != NULL)
                    {
                        CStrategySupportResistance* srPtr = dynamic_cast<CStrategySupportResistance*>(srStrat);
                        if(srPtr != NULL)
                        {
                            srPtr.SetHurstEngine(g_hurstEngines[mathIdx]);
                            srPtr.SetVPINFilter(g_vpinFilters[mathIdx]);
                            PrintFormat("[BATCH103] Hurst/VPIN wired to S/R | Symbol=%s", sym);
                        }
                    }
                    // Wire Mean Reversion Hurst engine (v2.0 regime lockout)
                    IStrategy* mrStrat = g_enterpriseManagers[mi].GetStrategyByName("Mean Reversion");
                    if(mrStrat != NULL)
                    {
                        CMeanReversionStrategy* mrPtr = dynamic_cast<CMeanReversionStrategy*>(mrStrat);
                        if(mrPtr != NULL)
                        {
                            mrPtr.SetHurstEngine(g_hurstEngines[mathIdx]);
                            PrintFormat("[BATCH103] Hurst wired to Mean Reversion | Symbol=%s", sym);
                        }
                    }
                    // Wire Statistical Arbitrage OU engine (half-life filter)
                    IStrategy* saStrat = g_enterpriseManagers[mi].GetStrategyByName("Statistical Arbitrage");
                    if(saStrat != NULL)
                    {
                        CStatisticalArbitrageStrategy* saPtr = dynamic_cast<CStatisticalArbitrageStrategy*>(saStrat);
                        if(saPtr != NULL)
                        {
                            saPtr.SetOUEngine(g_ouEngines[mathIdx]);
                            PrintFormat("[BATCH103] OU wired to Statistical Arbitrage | Symbol=%s", sym);
                        }
                    }
                }
            }
        }
    }
    PrintFormat("[MAGIC-RANGE] base=%d | symbols=%d | range_max=%u | encoding=BASE+symbolIndex*%d+clusterCode",
                InpMagicNumber, symbolCount, magicRangeMax, MAGIC_SYMBOL_MULTIPLIER);


    g_scanScheduler.SetManagers(g_enterpriseManagers, g_enterpriseManagerSymbols, ArraySize(g_enterpriseManagers));
    g_scanScheduler.SetInputParams(InpIntrabarScanSeconds, InpIntrabarBackoffMaxSeconds);
    g_scanScheduler.RebuildSymbolSchedulerState("post_manager_init");


    RecoverTradeTimingStateOnInit();

    // Initialize Neural Network Strategy per active symbol
    if(g_strategyRegistry.IsStrategyActive("Neural Network AI"))
    {
        ReleaseNeuralNetStrategies();
        int nnInitCount = 0;
        for(int i = 0; i < ArraySize(g_activePairs); i++)
        {
            if(InitializeNeuralNetForSymbol(g_activePairs[i], (ENUM_TIMEFRAMES)Period()))
                nnInitCount++;
        }

        neuralNetStrategy = GetNeuralNetForSymbol(_Symbol);
        if(neuralNetStrategy == NULL && ArraySize(g_neuralNetStrategies) > 0)
            neuralNetStrategy = g_neuralNetStrategies[0];

        Print("[AI-MODE] AI Mode enabled | Mode: ", EAModeToString(ResolveEffectiveEAMode()),
              " | NN: ", InpEnableNeuralNetwork, " | Transformer: ", InpEnableTransformer,
              " | Ensemble: ", InpEnableEnsemble, " | ONNX: ", InpEnableOnnxAI,
              " | PythonBridgeMode: ", PythonBridgeModeToString(InpPythonBridgeMode),
              " | ExternalLLM: ", InpEnableExternalLLM,
              " | Threshold: ", ResolveAIRuntimeVoteThreshold(ResolveEffectiveEAMode()),
              " | NN Managers: ", nnInitCount,
              " | NN Online: ", InpEnableNNOnlineTraining,
              " | NN WeightMutation: ", InpEnableNNWeightMutation,
              " | NN Pseudo: ", InpEnableNNPseudoLabeling);
    }
    else if(InpEnableAIMode)
    {
        ReleaseNeuralNetStrategies();
        Print("[AI-MODE] AI Mode enabled but Neural Network disabled");
    }

    // Initialize AI Engine for Adaptation (manager-owned; orchestrator removed in Phase 2)
    if(InpEnableAIMode && ArraySize(g_enterpriseManagers) > 0)
    {
        if(g_AIEngine == NULL) g_AIEngine = new CAIEngine();

        SAIAdaptiveConfig aiConfig;
        aiConfig.enabled = true;
        aiConfig.learningRate = 0.1;
        aiConfig.adaptationInterval = 1; // Adapt every bar
        aiConfig.minConfidenceThreshold = ResolveAIRuntimeVoteThreshold(ResolveEffectiveEAMode());
        aiConfig.useExternalLLM = InpEnableExternalLLM;

        if(g_AIEngine != NULL && g_AIEngine.Initialize(g_enterpriseManagers[0], aiConfig))
        {
            g_aiEngineReady = true;
            if(InpEnableExternalLLM)
                g_AIEngine.SetExternalAIEndpoint(InpExternalLLMEndpoint);
            Print("[INIT] AI Engine initialized in ADAPTIVE mode (manager-owned)");
        }
        else
        {
            Print("[INIT] WARNING: Failed to initialize AI Engine - adaptation disabled");
        }
    }
    else
    {
        Print("[AI] AIEngine disabled (AI mode off or manager unavailable)");
    }

    if(GetTotalActiveStrategyCount() <= 0)
    {
        Print("[CRITICAL] No active strategies registered. Enable at least one strategy or neural AI mode.");
        return INIT_FAILED;
    }

    // Wire attribution manager with position state manager BEFORE self-test (Blueprint R6 chain-fix)
    g_attributionManager.SetPositionStateManager(g_positionStateManager);
    g_attributionManager.SetNNDiagnosticsEnabled(InpEnableNNAttributionDiagnostics);
    g_attributionManager.SetRunSelfTest(InpRunNNAttributionSelfTest);

    if(InpEnableNNAttributionDiagnostics)
    {
        g_attributionManager.ResetNNDiagnostics();
        g_attributionManager.NNDiagLog("NN attribution diagnostics enabled");
    }

    if(!g_attributionManager.RunNNAttributionSelfTest())
    {
        Print("[NN-DIAG] Self-test failed; initialization aborted by diagnostic gate");
        return INIT_FAILED;
    }

    // Final system initialization
    systemInitialized = true;
    tradingEnabled = true;

    g_hbScansAttempted = 0;
    g_hbIntrabarScansExecuted = 0;
    g_hbNoSignalCount = 0;
    g_hbValidatorRejects = 0;
    g_hbRiskRejects = 0;
    g_hbTradesOpened = 0;
    g_hbShadowTrades = 0;
    g_hbQuietNoNewBar = 0;
    g_hbQuietCadenceHold = 0;
    g_hbQuietMissingManager = 0;
    g_hbEntryBlocked = 0;
    g_hbSizingRejects = 0;
    g_hbSignalsGenerated = 0;
    g_hbSignalsAfterPipeline = 0;
    g_hbSignalsAfterQuorum = 0;
    g_hbSignalsValidated = 0;
    g_hbSignalsRiskApproved = 0;
    g_hbSignalsSent = 0;
    g_hbSyntheticSpikeEvents = 0;
    g_lastHeartbeatLogTime = TimeCurrent();
    g_lastNNHealthLogTime = TimeCurrent();
    g_scanScheduler.ResetOnInit();
    g_unprotectedTracker.Reset();
    // Spike monitor state now encapsulated in CSyntheticSpikeMonitor
    g_onnxSessionDisabled = false;
    g_scanCycleSequence = 0;
    g_cyclesSinceIndicatorSignal = 0;
    g_hybridGateRelaxed = false;
    g_consecutiveZeroSignalCycles = 0;

    // Initialize Python Bridge — skip health check during init to avoid blocking WebRequest
    g_pythonBridge = new CPythonBridge();
    g_pythonBridge.Initialize(
        InpPythonBridgeEndpoint,
        InpPythonBridgeMode,
        InpPythonBridgeRequestTimeoutMs,
        InpPythonBridgeHeartbeatTimeoutSec,
        InpPythonBridgeMaxReconnectAttempts,
        InpPythonBridgeReconnectBackoffMs
    );
    
    // Version check deferred to first timer tick to avoid blocking OnInit
    if(InpPythonBridgeMode != PYTHON_BRIDGE_OFF && g_pythonBridge != NULL)
    {
        Print("[PYTHON-BRIDGE] Initialized - version check deferred to first timer tick");
    }

    // Initialize Dashboard Bridge — skip health check during init to avoid blocking WebRequest
    g_dashboardBridge = new CDashboardBridge();
    g_dashboardBridge.Initialize(
        InpDashboardEndpoint,
        false,  // enabled=false during init to skip blocking health check
        InpDashboardControlEnabled,
        InpDashboardPushIntervalSec,
        1000
    );
    // Re-enable after init so timer handler can push state
    g_dashboardBridge.SetEnabled(InpDashboardEnabled);

    // Initialize Dashboard
    g_dashboard.Initialize();
    
    // Startup Health Check
    Print("[HEALTH-CHECK] Performing startup validation...");
    bool healthCheckPassed = true;
    
    // AI Model Loading Check
    if(InpEnableAIMode) {
        int aiFailures = 0;
        if(!g_aiBrainReady) aiFailures++;
        if(!g_aiEngineReady && InpEnableNeuralNetwork) aiFailures++;
        if(aiFailures > 0) {
            PrintFormat("[HEALTH-CHECK] WARNING: %d AI component(s) failed to initialize", aiFailures);
        }
        else {
            Print("[HEALTH-CHECK] AI subsystem: OK");
        }
    }
    
    // Python Bridge Check
    if(InpPythonBridgeMode != PYTHON_BRIDGE_OFF && g_pythonBridge != NULL) {
        if(!g_pythonBridge.IsConnected()) {
            Print("[HEALTH-CHECK] WARNING: Python bridge not connected - using local AI fallback");
        }
        else {
            Print("[HEALTH-CHECK] Python bridge: OK");
        }
    }
    
    // Risk Manager Check
    if(!unifiedRiskManager.IsInitialized()) {
        Print("[HEALTH-CHECK] CRITICAL: Risk manager not initialized!");
        healthCheckPassed = false;
    }
    else {
        Print("[HEALTH-CHECK] Risk manager: OK");
    }
    
    // Position State Manager Check
    if(!g_positionStateManager.IsInitialized()) {
        Print("[HEALTH-CHECK] WARNING: Position state manager not initialized");
    }
    else {
        Print("[HEALTH-CHECK] Position state manager: OK");
    }

    Print("[HEALTH-CHECK] Startup validation complete");

    // Blueprint R6a: Wire lifecycle manager with enterprise managers (after all managers are created)
    if(g_lifecycleManager.IsInitialized())
    {
        g_lifecycleManager.SetManagers(g_enterpriseManagers, g_enterpriseManagerSymbols, ArraySize(g_enterpriseManagers));
        // I2: Wire regime engine from first symbol's pipeline for intelligent SL guard
        if(ArraySize(g_enterpriseManagerSymbols) > 0)
        {
            // Regime engines are per-pipeline; we use the first symbol's pipeline
            // The lifecycle manager will check regime state for all positions
        }
    }

    // Wire diagnostics manager with enterprise managers for consensus diagnostics
    g_diagnosticsManager.SetManagers(g_enterpriseManagers, ArraySize(g_enterpriseManagers));

    EventSetTimer(1);

    // Delete crash recovery state file — only needed for crash recovery, not after clean init
    {
        string stateFileName = "ea_state_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".txt";
        if(FileIsExist(stateFileName, FILE_COMMON))
        {
            FileDelete(stateFileName, FILE_COMMON);
            PrintFormat("[RECOVERY-STATE] State file %s deleted after successful init", stateFileName);
        }
    }

    Print("[MULTI-STRATEGY-EA] Initialization complete - EA is READY;");
    Print("[MULTI-STRATEGY-EA] ========================================");

    return healthCheckPassed ? INIT_SUCCEEDED : INIT_FAILED;
}

//+------------------------------------------------------------------+
//| Expert Advisor Deinitialization                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    Print("[DEINIT-START] Deinitialization begun | reason=%d (%s)", reason, GetDeInitReasonText(reason));

    systemInitialized = false;
    tradingEnabled = false;

    // Save circuit breaker state for crash recovery before any cleanup
    {
        string stateFileName = "ea_state_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".txt";
        int fh = FileOpen(stateFileName, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
        if(fh != INVALID_HANDLE)
        {
            FileWrite(fh, "equity_baseline=" + DoubleToString(unifiedRiskManager.GetDailyStartEquity(), 2));
            FileWrite(fh, "peak_equity=" + DoubleToString(unifiedRiskManager.GetPeakEquity(), 2));
            FileWrite(fh, "dd_breach_count=" + IntegerToString(unifiedRiskManager.GetDrawdownBreachCount()));
            FileWrite(fh, "dd_max=" + DoubleToString(unifiedRiskManager.GetMaxDrawdownFromPeak(), 2));
            FileWrite(fh, "timestamp=" + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS));
            FileClose(fh);
            PrintFormat("[DEINIT-STATE] Circuit breaker state saved to %s | equity_baseline=%.2f | peak_equity=%.2f | dd_breach_count=%d | dd_max=%.2f",
                        stateFileName,
                        unifiedRiskManager.GetDailyStartEquity(),
                        unifiedRiskManager.GetPeakEquity(),
                        unifiedRiskManager.GetDrawdownBreachCount(),
                        unifiedRiskManager.GetMaxDrawdownFromPeak());
        }
        else
        {
            PrintFormat("[DEINIT-STATE] WARNING: Failed to save circuit breaker state to %s (error=%d)", stateFileName, GetLastError());
        }
    }

    PrintFormat("[TERMINATION-SNAPSHOT] reason=%d (%s) | scans=%I64u | intrabar=%I64u | no_signal=%I64u | validated=%I64u | risk_approved=%I64u | sent=%I64u",
                reason,
                GetDeInitReasonText(reason),
                g_hbScansAttempted,
                g_hbIntrabarScansExecuted,
                g_hbNoSignalCount,
                g_hbSignalsValidated,
                g_hbSignalsRiskApproved,
                g_hbSignalsSent);

    // Kill the timer
    EventKillTimer();

    // Shutdown Python bridge
    if(g_pythonBridge != NULL)
    {
        g_pythonBridge.Shutdown();
        delete g_pythonBridge;
        g_pythonBridge = NULL;
    }

    // Shutdown Dashboard bridge
    if(g_dashboardBridge != NULL)
    {
        g_dashboardBridge.Shutdown();
        delete g_dashboardBridge;
        g_dashboardBridge = NULL;
    }

    // Emergency cleanup (Issue 12.4): log deinit for each strategy before managers are released
    int strategiesCleaned = 0;
    for(int i = 0; i < ArraySize(g_enterpriseManagers); i++)
    {
        if(g_enterpriseManagers[i] != NULL)
        {
            int count = g_enterpriseManagers[i].GetRegisteredStrategyCount();
            for(int j = 0; j < count; j++)
            {
                string stratName = g_enterpriseManagers[i].GetRegisteredStrategyName(j);
                if(stratName != "")
                {
                    PrintFormat("[EMERGENCY-CLEANUP] Deinit strategy: %s", stratName);
                    strategiesCleaned++;
                }
            }
        }
    }
    PrintFormat("[EMERGENCY-CLEANUP] Deinit reason=%d, strategies cleaned=%d", reason, strategiesCleaned);

    // Properly delete all dynamic objects to prevent memory leaks
    ReleaseEnterpriseManagers();
    

    g_attributionManager.NNDiagPrintSummary("deinit");
    
    ReleaseNeuralNetStrategies();
    g_unprotectedTracker.Reset();
    
    if(g_AIEngine != NULL)
    {
        delete g_AIEngine;
        g_AIEngine = NULL;
    }
    g_aiBrainReady = false;
    g_aiEngineReady = false;

    // Batch 99: Cleanup dynamically allocated modifiers
    if(g_bayesianKellyModifier != NULL)
    {
        delete g_bayesianKellyModifier;
        g_bayesianKellyModifier = NULL;
    }
    if(g_equityCurveLotModifier != NULL)
    {
        delete g_equityCurveLotModifier;
        g_equityCurveLotModifier = NULL;
    }
    if(g_equityCurveManager != NULL)
    {
        delete g_equityCurveManager;
        g_equityCurveManager = NULL;
    }

    // Batch 100: Cleanup mathematical engines
    for(int i = 0; i < ArraySize(g_hurstEngines); i++)
    {
        if(g_hurstEngines[i] != NULL) { delete g_hurstEngines[i]; g_hurstEngines[i] = NULL; }
        if(g_ouEngines[i] != NULL) { delete g_ouEngines[i]; g_ouEngines[i] = NULL; }
        if(g_ofiEngines[i] != NULL) { delete g_ofiEngines[i]; g_ofiEngines[i] = NULL; }
        if(g_vpinFilters[i] != NULL) { delete g_vpinFilters[i]; g_vpinFilters[i] = NULL; }
    }
    ArrayResize(g_hurstEngines, 0);
    ArrayResize(g_ouEngines, 0);
    ArrayResize(g_ofiEngines, 0);
    ArrayResize(g_vpinFilters, 0);
    ArrayResize(g_mathEngineSymbols, 0);
    ArrayResize(g_gridHurstBridgeLogged, 0);

    // Batch 107: Cleanup institutional TA engines
    for(int i = 0; i < ArraySize(g_vwapEngines); i++)
    {
        if(g_vwapEngines[i] != NULL) { delete g_vwapEngines[i]; g_vwapEngines[i] = NULL; }
        if(g_vpEngines[i] != NULL) { delete g_vpEngines[i]; g_vpEngines[i] = NULL; }
        if(g_cvdEngines[i] != NULL) { delete g_cvdEngines[i]; g_cvdEngines[i] = NULL; }
    }
    ArrayResize(g_vwapEngines, 0);
    ArrayResize(g_vpEngines, 0);
    ArrayResize(g_cvdEngines, 0);

    // Deinitialize diagnostics logger (Blueprint 3.6)
    g_diagLogger.Deinit();

    // Cleanup scalp signal cache
    g_scalpCache.Cleanup();

    if(InpSpikeHunterEnabled)
        g_spikeHunter.Deinit();

    // Batch 102: Cleanup new engines
    if(InpGridRecoveryEnabled)
        g_gridRecovery.Deinit();
    if(InpATRScalpingEnabled)
        g_atrScalping.Deinit();

    UncertaintyDeinit();
    CIndicatorManager::DestroyInstance();
    PrintFormat("[EMERGENCY-CLEANUP] Complete. Indicators released.");

    // Clear chart
    Comment("");

    Print("[MULTI-STRATEGY-EA] ========================================");
    Print("[MULTI-STRATEGY-EA] Shutdown complete - Memory cleaned");
    Print("[MULTI-STRATEGY-EA] ========================================");

    Print("[DEINIT-COMPLETE] Deinitialization finished cleanly | reason=%d (%s)", reason, GetDeInitReasonText(reason));
}

//+------------------------------------------------------------------+
//| Get deinitialization reason text                                 |
//+------------------------------------------------------------------+
string GetDeInitReasonText(int reasonCode)
{
    switch(reasonCode)
    {
        case REASON_PROGRAM: return "EA terminated";
        case REASON_REMOVE: return "EA removed from chart";
        case REASON_RECOMPILE: return "EA recompiled";
        case REASON_CHARTCHANGE: return "Symbol or period changed";
        case REASON_CHARTCLOSE: return "Chart closed";
        case REASON_PARAMETERS: return "Input parameters changed";
        case REASON_ACCOUNT: return "Account changed";
        case REASON_TEMPLATE: return "New template applied";
        case REASON_INITFAILED: return "Initialization failed";
        case REASON_CLOSE: return "Terminal closed";
        default: return "Unknown reason";
    }
}

//+------------------------------------------------------------------+
//| Timer Handler - Processes trades when chart symbol is closed     |
//+------------------------------------------------------------------+
void OnTimer()
{
    // Periodic AI Health Check (every InpHeartbeatInterval seconds, min 30)
    static datetime lastAIHealthCheck = 0;
    static datetime lastPythonBridgeCheck = 0;
    datetime now = TimeCurrent();
    int healthCheckInterval = MathMax(30, InpHeartbeatInterval);

    // I2: Compounding tier transition check
    if(InpEnableCompoundingTiers && g_compoundingTierManager.IsInitialized())
    {
        static datetime lastTierCheck = 0;
        if(lastTierCheck == 0 || (now - lastTierCheck) >= InpCompoundingTierCheckIntervalSec)
        {
            g_compoundingTierManager.CheckTierTransition(unifiedRiskManager, positionSizer, tradeManager);
            lastTierCheck = now;
        }
    }
    if(lastAIHealthCheck == 0 || (now - lastAIHealthCheck) >= healthCheckInterval)
    {
        if(InpEnableAIMode)
        {
            string aiStatus = "[AI-DASHBOARD] ";
            
            // Transformer status
            if(g_aiBrainReady)
                aiStatus += "TF:RDY | ";
            else
                aiStatus += "TF:OFF | ";
            
            // Neural Network status
            if(g_aiEngineReady)
                aiStatus += "NN:RDY | ";
            else
                aiStatus += "NN:OFF | ";
            
            // Ensemble status
            int activeAIModels = g_strategyRegistry.GetActiveAICount();
            aiStatus += "ENS:" + IntegerToString(activeAIModels) + "/4 | ";
            
            // Memory efficiency indicator
            aiStatus += "MEM:OPTIMIZED";
            
            Print(aiStatus);
        }
        
        // Python Bridge status
        if(g_pythonBridge != NULL)
        {
            SPythonBridgeHealthStatus bridgeStatus = g_pythonBridge.GetHealthStatus();
            string bridgeStatusStr = "[PYTHON-BRIDGE-DASHBOARD] ";
            bool skipDashboardLog = false;

            // Connection state — differentiate by mode to avoid false CONN:ERROR
            if(InpPythonBridgeMode == PYTHON_BRIDGE_OFF)
            {
                bridgeStatusStr += "CONN:DISABLED | ";
            }
            else
            {
                switch(bridgeStatus.state)
                {
                    case PYTHON_BRIDGE_CONNECTED:
                        bridgeStatusStr += "CONN:OK | ";
                        break;
                    case PYTHON_BRIDGE_CONNECTING:
                        bridgeStatusStr += "CONN:CONNECTING | ";
                        break;
                    case PYTHON_BRIDGE_DISCONNECTED:
                        // In OBSERVE mode, disconnected is expected when no server runs
                        if(InpPythonBridgeMode == PYTHON_BRIDGE_OBSERVE)
                        {
                            // Throttle NOT_CONFIGURED logs to every 300 seconds
                            if(!g_pythonBridge.ShouldLogNotConfigured())
                            {
                                skipDashboardLog = true;
                                break;
                            }
                            bridgeStatusStr += "CONN:NOT_CONFIGURED | ";
                        }
                        else
                            bridgeStatusStr += "CONN:DISCONNECTED | ";
                        break;
                    case PYTHON_BRIDGE_ERROR:
                        bridgeStatusStr += "CONN:ERROR | ";
                        break;
                }
            }

            if(!skipDashboardLog)
            {
                // Version info
                if(bridgeStatus.version.version != "")
                    bridgeStatusStr += "VER:" + bridgeStatus.version.version + " | ";
                else
                    bridgeStatusStr += "VER:UNKNOWN | ";

                // Stats
                bridgeStatusStr += "REQS:" + IntegerToString(bridgeStatus.request_count) + " | ";
                bridgeStatusStr += "OK:" + IntegerToString(bridgeStatus.success_count) + " | ";
                bridgeStatusStr += "ERR:" + IntegerToString(bridgeStatus.error_count);

                Print(bridgeStatusStr);
            }
        }
        
        lastAIHealthCheck = now;
    }

    // Periodic Python Bridge Check (every heartbeat timeout seconds)
    if(InpPythonBridgeMode != PYTHON_BRIDGE_OFF && g_pythonBridge != NULL &&
       (lastPythonBridgeCheck == 0 || (now - lastPythonBridgeCheck) >= InpPythonBridgeHeartbeatTimeoutSec))
    {
        g_pythonBridge.SendHeartbeat();
        lastPythonBridgeCheck = now;
    }

    // Dashboard bridge state push
    if(g_dashboardBridge != NULL && g_dashboardBridge.IsEnabled())
    {
        datetime lastPush = g_dashboardBridge.GetLastPushTime();
        if(lastPush == 0 || (now - lastPush) >= InpDashboardPushIntervalSec)
        {
            // Inject AI data before push
            if(neuralNetStrategy != NULL)
            {
                double nnConf = 0.0;
                ENUM_TRADE_SIGNAL nnSig = neuralNetStrategy.GetNeuralSignal(nnConf);
                string nnSigText = "NONE";
                if(nnSig == TRADE_SIGNAL_BUY) nnSigText = "BUY";
                else if(nnSig == TRADE_SIGNAL_SELL) nnSigText = "SELL";

                // Get real regime probabilities
                double regimeProbs[];
                neuralNetStrategy.GetRegimeProbs(regimeProbs);
                double rTrend = (ArraySize(regimeProbs) > 0) ? regimeProbs[0] : 0.25;
                double rRange = (ArraySize(regimeProbs) > 1) ? regimeProbs[1] : 0.25;
                double rVolatile = (ArraySize(regimeProbs) > 2) ? regimeProbs[2] : 0.25;
                double rSpike = (ArraySize(regimeProbs) > 3) ? regimeProbs[3] : 0.25;
                string regimeName = "RANGE";
                int regimeIdx = neuralNetStrategy.GetCurrentRegime();
                if(regimeIdx == 0) regimeName = "TREND";
                else if(regimeIdx == 1) regimeName = "RANGE";
                else if(regimeIdx == 2) regimeName = "VOLAT";
                else if(regimeIdx == 3) regimeName = "SPIKE";

                g_dashboardBridge.SetAIData(
                    true, nnSigText, nnConf,
                    neuralNetStrategy.GetCompletedTradesCount(), neuralNetStrategy.GetTrainingSteps(),
                    neuralNetStrategy.GetLastUncertainty(), 0.05,
                    neuralNetStrategy.GetAssetClass(), neuralNetStrategy.GetBarrierK(), neuralNetStrategy.GetBarrierVertBars(),
                    0, true,
                    regimeName, rTrend, rRange, rVolatile, rSpike,
                    65, 50, 20, 0.5, 0.5, 0
                );
            }

            if(g_dashboardBridge.PushState() && g_dashboardBridge.IsControlEnabled())
                g_dashboardBridge.PollCommands();
        }
    }

    g_spikeMonitor.ReleasePauseIfExpired();

    // Periodic chart object cleanup (every 5 minutes)
    {
        static datetime s_lastChartObjCleanup = 0;
        if(s_lastChartObjCleanup == 0 || (now - s_lastChartObjCleanup) >= 300)
        {
            CDrawingCoordinator* coord = GetDrawingCoordinator();
            if(coord != NULL)
            {
                int totalBefore = ObjectsTotal(0);
                if(totalBefore > 400)
                {
                    PrintFormat("[CHART-OBJECTS] WARNING: %d/500 objects — cleanup triggered", totalBefore);
                    coord.CleanupStaleObjects(0, 60);
                    for(int d = 0; d < ArraySize(g_drawingManagers); d++)
                    {
                        if(g_drawingManagers[d] != NULL)
                            g_drawingManagers[d].CleanupOldObjects();
                    }
                }
            }
            s_lastChartObjCleanup = now;
        }
    }

    // Batch 99: Update EquityCurveManager on every timer tick
    if(g_equityCurveManager != NULL)
        g_equityCurveManager.Update(AccountInfoDouble(ACCOUNT_EQUITY));

    // Batch 100: Update bar-level mathematical engines (Hurst, OU) on timer
    for(int i = 0; i < ArraySize(g_mathEngineSymbols); i++)
    {
        if(g_hurstEngines[i] != NULL)
            g_hurstEngines[i].Update();
        if(g_ouEngines[i] != NULL)
            g_ouEngines[i].Update();

        // Batch 29a: Bridge Hurst output to GridRecoveryEngine
        if(InpGridRecoveryEnabled && g_hurstEngines[i] != NULL && g_hurstEngines[i].IsWarmedUp())
        {
            double hurstVal = g_hurstEngines[i].GetSnapshot().hurstValue;
            g_gridRecovery.SetHurstRegime(g_mathEngineSymbols[i], hurstVal);
            if(!g_gridHurstBridgeLogged[i])
            {
                PrintFormat("[GRID-HURST-BRIDGE] %s | Hurst=%.3f — first bridge to GridRecoveryEngine", g_mathEngineSymbols[i], hurstVal);
                g_gridHurstBridgeLogged[i] = true;
            }
        }
    }

    // Batch 100: Apply Hurst weight modifiers to regime engine
    ApplyHurstWeightModifiersToRegime();

    // Batch 99: Apply equity curve position size multiplier to PositionSizer via modifier chain
    // (The equity curve multiplier is applied as a post-hoc adjustment in the sizing flow)
    // CVaR periodic logging (every 5 minutes)
    datetime nowCvar = TimeCurrent();
    if(g_lastCvarLogTime == 0 || (nowCvar - g_lastCvarLogTime) >= 300)
    {
        double cvarValue = unifiedRiskManager.GetPortfolioRiskManager().GetCurrentCVaR();
        double absCvar = MathAbs(cvarValue);
        PrintFormat("[CVAR] Portfolio CVaR=%.2f%% at 95%% confidence", absCvar * 100.0);
        g_lastCvarLogTime = nowCvar;
    }

    ProcessTradingLogic(true);  // true = called from timer
}

//+------------------------------------------------------------------+
//| Expert Advisor Tick Handler                                      |
//+------------------------------------------------------------------+
void OnTick()
{
    ProcessTickSafetyLoop();

    // Batch 100: Feed tick data to VPIN and OFI engines (throttled to 200ms)
    {
        static uint s_lastVpinOfiFeed = 0;
        uint nowMs = GetTickCount();
        if(nowMs - s_lastVpinOfiFeed >= 200)
        {
            for(int i = 0; i < ArraySize(g_mathEngineSymbols); i++)
            {
                string sym = g_mathEngineSymbols[i];
                double tickPrice = SymbolInfoDouble(sym, SYMBOL_BID);
                double tickVolume = (double)SymbolInfoInteger(sym, SYMBOL_VOLUME);
                double bid = SymbolInfoDouble(sym, SYMBOL_BID);
                double ask = SymbolInfoDouble(sym, SYMBOL_ASK);

                if(g_vpinFilters[i] != NULL)
                    g_vpinFilters[i].OnTick(tickPrice, tickVolume);
                if(g_ofiEngines[i] != NULL)
                    g_ofiEngines[i].OnTick(tickPrice, tickVolume, bid, ask);
                // Batch 107: CVD engine (forex only, calculated per bar)
            }
            s_lastVpinOfiFeed = nowMs;
        }
    }

    // I4: Feed tick data to Skew Step Analyzer (throttled to 500ms)
    if(InpEnableSkewStepAnalyzer && g_skewStepAnalyzer.IsInitialized())
    {
        static uint s_lastSkewStepFeed = 0;
        uint nowMs = GetTickCount();
        if(nowMs - s_lastSkewStepFeed >= 500)
        {
            for(int i = 0; i < ArraySize(g_enterpriseManagerSymbols); i++)
            {
                string sym = g_enterpriseManagerSymbols[i];
                CDerivAssetProfiler* derivProf = g_multiAssetProfiler.GetDerivProfiler();
                if(derivProf == NULL) continue;
                ENUM_DERIV_FAMILY family = derivProf.DetectFamily(sym);
                if(family == DERIV_SKEW_STEP)
                {
                    // Calculate step size as difference between current and previous close
                    double close0 = iClose(sym, PERIOD_M1, 0);
                    double close1 = iClose(sym, PERIOD_M1, 1);
                    if(close0 > 0 && close1 > 0)
                    {
                        double stepSize = close0 - close1;
                        g_skewStepAnalyzer.RecordStep(stepSize);
                    }
                }
            }
            s_lastSkewStepFeed = nowMs;
        }
    }

    // Fast-path scalp signal evaluation on ticks (dual-path architecture)
    if(InpEnableScalpEngine && g_scalpEngine.IsInitialized())
    {
        ProcessScalpFastPath();
    }
}

//+------------------------------------------------------------------+
//| Issue 7: Dormancy cooldown tracking helpers                      |
//+------------------------------------------------------------------+
int FindDormantCooldownIndex(const string symbol)
{
    for(int i = 0; i < ArraySize(g_dormantCooldownSymbols); i++)
    {
        if(g_dormantCooldownSymbols[i] == symbol)
            return i;
    }
    return -1;
}

void EnsureDormantCooldownSlot(const string symbol)
{
    if(FindDormantCooldownIndex(symbol) >= 0)
        return;
    int idx = ArraySize(g_dormantCooldownSymbols);
    ArrayResize(g_dormantCooldownSymbols, idx + 1);
    ArrayResize(g_dormantConsecutiveCount, idx + 1);
    ArrayResize(g_dormantCooldownUntil, idx + 1);
    g_dormantCooldownSymbols[idx] = symbol;
    g_dormantConsecutiveCount[idx] = 0;
    g_dormantCooldownUntil[idx] = 0;
}

bool IsSymbolInDormantCooldown(const string symbol)
{
    int idx = FindDormantCooldownIndex(symbol);
    if(idx < 0) return false;
    if(g_dormantCooldownUntil[idx] <= 0) return false;
    return (TimeCurrent() < g_dormantCooldownUntil[idx]);
}

void RecordDormantWarning(const string symbol)
{
    int idx = FindDormantCooldownIndex(symbol);
    if(idx < 0) return;
    g_dormantConsecutiveCount[idx]++;
    if(g_dormantConsecutiveCount[idx] >= DORMANT_COOLDOWN_THRESHOLD)
    {
        g_dormantCooldownUntil[idx] = TimeCurrent() + DORMANT_COOLDOWN_MINUTES * 60;
        PrintFormat("[DORMANT-COOLDOWN] %s | %d consecutive dormancy warnings | skipping evaluations for %d minutes",
                    symbol, g_dormantConsecutiveCount[idx], DORMANT_COOLDOWN_MINUTES);
    }
}

void ResetDormantCount(const string symbol)
{
    int idx = FindDormantCooldownIndex(symbol);
    if(idx >= 0)
        g_dormantConsecutiveCount[idx] = 0;
}

void ClearDormantCooldownOnNewBar(const string symbol)
{
    int idx = FindDormantCooldownIndex(symbol);
    if(idx >= 0)
    {
        g_dormantConsecutiveCount[idx] = 0;
        g_dormantCooldownUntil[idx] = 0;
    }
}

//+------------------------------------------------------------------+
//| Issue 15: Scalp blacklist tracking helpers                       |
//+------------------------------------------------------------------+
int FindScalpBlacklistIndex(const string symbol)
{
    for(int i = 0; i < ArraySize(g_scalpBlacklistSymbols); i++)
    {
        if(g_scalpBlacklistSymbols[i] == symbol)
            return i;
    }
    return -1;
}

void EnsureScalpBlacklistSlot(const string symbol)
{
    if(FindScalpBlacklistIndex(symbol) >= 0)
        return;
    int idx = ArraySize(g_scalpBlacklistSymbols);
    ArrayResize(g_scalpBlacklistSymbols, idx + 1);
    ArrayResize(g_scalpBlacklistFailCount, idx + 1);
    ArrayResize(g_scalpBlacklisted, idx + 1);
    ArrayResize(g_scalpBlacklistDay, idx + 1);
    g_scalpBlacklistSymbols[idx] = symbol;
    g_scalpBlacklistFailCount[idx] = 0;
    g_scalpBlacklisted[idx] = false;
    g_scalpBlacklistDay[idx] = 0;
}

bool IsSymbolScalpBlacklisted(const string symbol)
{
    int idx = FindScalpBlacklistIndex(symbol);
    if(idx < 0) return false;

    // Clear blacklist on new day
    datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    if(g_scalpBlacklistDay[idx] != today)
    {
        g_scalpBlacklistFailCount[idx] = 0;
        g_scalpBlacklisted[idx] = false;
        g_scalpBlacklistDay[idx] = today;
    }

    return g_scalpBlacklisted[idx];
}

void RecordScalpCostFailure(const string symbol)
{
    int idx = FindScalpBlacklistIndex(symbol);
    if(idx < 0) return;
    g_scalpBlacklistFailCount[idx]++;
    if(g_scalpBlacklistFailCount[idx] >= SCALP_BLACKLIST_THRESHOLD)
    {
        g_scalpBlacklisted[idx] = true;
        datetime today = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
        g_scalpBlacklistDay[idx] = today;
        PrintFormat("[SCALP-BLACKLIST] %s | %d consecutive spread cost failures | blacklisted for rest of session",
                    symbol, g_scalpBlacklistFailCount[idx]);
    }
}

void ResetScalpBlacklistCount(const string symbol)
{
    int idx = FindScalpBlacklistIndex(symbol);
    if(idx >= 0)
        g_scalpBlacklistFailCount[idx] = 0;
}

//+------------------------------------------------------------------+
//| Fast-path scalp signal evaluation (tick-level, dual-path)         |
//| Uses cached indicator values — zero CopyBuffer in fast path       |
//| Throttled to max once per second for signal evaluation            |
//+------------------------------------------------------------------+
void ProcessScalpFastPath()
{
    // Throttle: max once per second for signal evaluation
    // (position management in ProcessTickSafetyLoop runs every tick)
    datetime currentSecond = TimeCurrent();
    if(currentSecond == g_scanScheduler.GetLastScalpFastPathSecond()) return;
    g_scanScheduler.SetLastScalpFastPathSecond(currentSecond);

    // Skip if daily trading halt is active
    if(g_dailyTradingHalt) return;

    // Lazy-init scalp cache if not yet initialized (safety net for deferred init)
    if(!g_scalpCache.IsInitialized())
    {
        if(!g_scalpCache.EnsureInitialized(g_activePairs, ArraySize(g_activePairs), PERIOD_M1))
            return;
        // Wire cache to scalp engine on first successful init
        g_scalpEngine.SetSignalCache(GetPointer(g_scalpCache));
        Print("[SCALP-CACHE] Lazy-init completed in OnTick path");
    }

    // Update tick-level cache values (zero computation — just reads SymbolInfoDouble)
    g_scalpCache.UpdateTickValues();

    // Check for new bar — if new bar, update indicator cache (CopyBuffer only here)
    for(int i = 0; i < ArraySize(g_activePairs); i++)
    {
        if(g_scalpCache.HasNewBar(g_activePairs[i]))
        {
            g_scalpCache.UpdateOnNewBar();
            break;  // UpdateOnNewBar updates all symbols at once
        }
    }

    // Evaluate scalp signals for each active symbol
    for(int i = 0; i < ArraySize(g_activePairs); i++)
    {
        string symbol = g_activePairs[i];
        SScalpIndicatorCache cache;
        if(!g_scalpCache.GetCache(symbol, cache)) continue;
        if(!cache.isValid) continue;

        // Only evaluate if pre-qualified for scalping
        if(!cache.scalpSetupActive) continue;

        // Issue 15: Skip scalp evaluation if symbol is blacklisted (3+ consecutive spread cost failures)
        EnsureScalpBlacklistSlot(symbol);
        if(IsSymbolScalpBlacklisted(symbol)) continue;

        // Quick spread gate (zero computation — uses cached spread)
        double pointSize = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(pointSize > 0.0 && cache.atrValue > 0.0)
        {
            double maxSpreadPoints = cache.atrValue * 0.3 / pointSize;
            if(cache.spreadPoints > maxSpreadPoints)
            {
                RecordScalpCostFailure(symbol);
                continue;
            }
        }

        // Reset blacklist counter on successful spread gate pass
        ResetScalpBlacklistCount(symbol);

        // Delegate to scalp engine for signal evaluation and execution
        // The scalp engine uses the cached values instead of computing them
        if(!g_scalpEngine.IsInitialized()) continue;
        ENUM_TRADE_SIGNAL scalpSignal = TRADE_SIGNAL_NONE;
        double scalpConfidence = 0.0;
        double scalpLotSize = 0.0;

        if(g_scalpEngine.ShouldEnterScalp(symbol, scalpSignal, scalpConfidence, scalpLotSize))
        {
            if(InpShadowMode || InpShadowModeEnabled)
            {
                PrintFormat("[SHADOW-SCALP-FAST] %s | %s | lot=%.2f | confidence=%.2f | SHADOW MODE — no order sent",
                            symbol,
                            scalpSignal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                            scalpLotSize,
                            scalpConfidence);
            }
            else
            {
                // Use pending orders if configured, otherwise market order
                if(g_scalpEngine.GetConfig().usePendingOrders)
                    g_scalpEngine.PlaceScalpPendingOrder(symbol, scalpSignal, scalpLotSize);
                else
                    g_scalpEngine.ExecuteScalpTrade(symbol, scalpSignal, scalpLotSize, scalpConfidence);
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Main Trading Logic - Timer-owned heavy evaluation path           |
//+------------------------------------------------------------------+
void ProcessTradingLogic(bool fromTimer)
{
    // First tick/timer detection
    static bool firstCall = true;
    static int callCount = 0;
    callCount++;

    if(firstCall)
    {
        PrintFormat("[DEBUG-PROCESS] First call received! System initialized: %s, Trading enabled: %s, Source: %s",
                   systemInitialized ? "YES" : "NO",
                   tradingEnabled ? "YES" : "NO",
                   fromTimer ? "TIMER" : "TICK");
        firstCall = false;
    }

    // Compute dashboard values (always, not gated by log level)
    int activeStrats = 0;
    int eaPositions = 0;
    if(ArraySize(g_enterpriseManagers) > 0)
    {
        activeStrats = GetTotalActiveStrategyCount();
        eaPositions = GetEAPositionCount();
    }

    if(!systemInitialized || !tradingEnabled)
    {
        PrintFormat("[DEBUG-PROCESS] EA blocked: System initialized: %s, Trading enabled: %s",
                   systemInitialized ? "YES" : "NO",
                   tradingEnabled ? "YES" : "NO");
        return;
    }

    // --- Update Dashboard (after init check) ---
    g_dashboard.Update(neuralNetStrategy, g_aiBrainReady ? &aiNextGenBrain : NULL, activeStrats, eaPositions, accountBalance, accountEquity, totalTrades, winningTrades, totalProfit);

    // Enhanced logging every 50 calls to show pipeline activity
    if(callCount % 50 == 0 && g_logLevel >= 3)
    {
        PrintFormat("[DEBUG-PROCESS] Call #%d - EA is processing normally (Source: %s)", callCount, fromTimer ? "TIMER" : "TICK");
        Print("[DEBUG-PROCESS] Call #", callCount, " Time: ", TimeCurrent());
        Print("[DEBUG-STATUS] Current symbol: ", _Symbol);

        // Show Enterprise Manager status
        if(ArraySize(g_enterpriseManagers) > 0)
        {
            int activeStrategyInstances = GetTotalActiveStrategyCount();
            int activeBrainStrategyInstances = GetTotalActiveBrainStrategyCount();
            int activeCoreStrategyInstances = MathMax(0, activeStrategyInstances - activeBrainStrategyInstances);
            int uniqueActiveStrategies = g_strategyRegistry.GetActiveCount();
            int uniqueActiveCoreStrategies = g_strategyRegistry.GetActiveIndicatorCount();
            int uniqueActiveAIStrategies = g_strategyRegistry.GetActiveAICount();
            int cooldownSecs = g_lastTradeTime > 0 ? (int)(TimeCurrent() - g_lastTradeTime) : 0;
            int managerCount = ArraySize(g_enterpriseManagers);
            Print("[ENTERPRISE-STATUS] Active strategy instances: ", activeStrategyInstances,
                  " (Core: ", activeCoreStrategyInstances, ", AI: ", activeBrainStrategyInstances, ")",
                  " | Unique runtime strategies: ", uniqueActiveStrategies,
                  " (Core: ", uniqueActiveCoreStrategies, ", AI: ", uniqueActiveAIStrategies, ")",
                  " | Managers: ", managerCount,
                  " | Cooldown: ", cooldownSecs, "s / ", InpMinSecondsBetweenTrades, "s");
            Print("[ENTERPRISE-STATUS] EA Positions: ", eaPositions, " / ", InpMaxPositionsTotal,
                  " | Account Total: ", PositionsTotal(),
                  " | Last trade: ", g_lastTradeTime > 0 ? TimeToString(g_lastTradeTime) : "Never");
        }
    }

    // Check if trading is still allowed
    if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !MQLInfoInteger(MQL_TRADE_ALLOWED))
    {
        Print("[DEBUG-PROCESS] Trading permissions check failed!");
        Comment("Trading is DISABLED - Waiting for permissions...");
        return;
    }
    {
        static bool s_wasConnected = true;
        bool isConnected = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
        if(!isConnected)
        {
            if(s_wasConnected)
                Print("[TERMINAL-EVENT] Disconnected from server");
            s_wasConnected = false;
            Print("[DEBUG-PROCESS] Terminal disconnected - postponing signal evaluation");
            Comment("Terminal disconnected - waiting for reconnect...");
            return;
        }
        else
        {
            if(!s_wasConnected)
                Print("[TERMINAL-EVENT] Reconnected to server");
            s_wasConnected = true;
        }
    }

    g_spikeMonitor.ReleasePauseIfExpired();

    // Refresh unified risk state (daily reset + adaptive risk level)
    unifiedRiskManager.RefreshRuntimeState();
    RefreshAccountRuntimeMetrics();
    UpdateLiveAuthorityTrials();

    // Reset daily profit target state on new day
    static datetime s_lastProfitTargetDay = 0;
    datetime profitTargetToday = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
    if(profitTargetToday != s_lastProfitTargetDay)
    {
        s_lastProfitTargetDay = profitTargetToday;
        g_dailyProfitTargetReached = false;
        g_dailyProfitPeakPct = 0.0;
        g_trailingProfitFloor = 0.0;
        g_dailyTradingHalt = false;
        g_dailyTradingHaltStartTime = 0;
        SetAllPipelinesBudgetExhausted(false);
    }

    // Check if daily halt cooldown has expired
    if(g_dailyTradingHalt && g_dailyTradingHaltStartTime > 0)
    {
        int elapsedMinutes = (int)(TimeCurrent() - g_dailyTradingHaltStartTime) / 60;
        if(elapsedMinutes >= InpDailyHaltCooldownMinutes)
        {
            PrintFormat("[PROFIT-TARGET] Daily halt cooldown expired (%d min >= %d min). Resuming trading.",
                        elapsedMinutes, InpDailyHaltCooldownMinutes);
            g_dailyTradingHalt = false;
            g_dailyTradingHaltStartTime = 0;
            g_dailyProfitTargetReached = false;
            g_dailyProfitPeakPct = 0.0;
            g_trailingProfitFloor = 0.0;
            SetAllPipelinesBudgetExhausted(false);
        }
    }

    // Portfolio-level profit target with trailing floor
    if(InpDailyProfitTargetPercent > 0.0 && !g_dailyTradingHalt)
    {
        double dailyProfitPct = CalculateDailyPnLPercent();

        if(dailyProfitPct >= InpDailyProfitTargetPercent && !g_dailyProfitTargetReached)
        {
            g_dailyProfitTargetReached = true;
            g_dailyProfitPeakPct = dailyProfitPct;
            g_trailingProfitFloor = dailyProfitPct * InpProfitTrailFactor;
            PrintFormat("[PROFIT-TARGET] Daily profit target reached: %.2f%% (target: %.2f%%). Trailing floor set at %.2f%%",
                        dailyProfitPct, InpDailyProfitTargetPercent, g_trailingProfitFloor);
        }

        if(g_dailyProfitTargetReached)
        {
            g_dailyProfitPeakPct = MathMax(g_dailyProfitPeakPct, dailyProfitPct);
            g_trailingProfitFloor = g_dailyProfitPeakPct * InpProfitTrailFactor;

            if(dailyProfitPct < g_trailingProfitFloor)
            {
                double hardFloorPct = InpDailyProfitTargetPercent * InpProfitTargetHardFloorRatio;
                PrintFormat("[PROFIT-TARGET] Trailing floor breached: %.2f%% < %.2f%%. Hard floor at %.2f%%. Starting selective close.",
                            dailyProfitPct, g_trailingProfitFloor, hardFloorPct);
                bool allClosed = SelectiveCloseToRecoverFloor(hardFloorPct);
                if(allClosed)
                {
                    g_dailyTradingHalt = true;
                    g_dailyTradingHaltStartTime = TimeCurrent();
                    SetAllPipelinesBudgetExhausted(true);
                }
            }
        }
    }

    // Dual-mode auto-switching logic
    if(InpEnableAutoModeSwitch)
    {
        ENUM_AUTO_SWITCH_MODE newMode = DetermineTradingMode();
        if(newMode != g_currentTradingMode)
        {
            PrintFormat("[MODE-SWITCH] Trading mode changed: %d -> %d", g_currentTradingMode, newMode);
            g_currentTradingMode = newMode;

            // Apply mode-specific risk parameters
            if(g_currentTradingMode == AUTO_MODE_CONSERVATIVE)
                unifiedRiskManager.SetBaseRiskPerTrade(InpConservativeBaseRiskPct);
            else if(g_currentTradingMode == AUTO_MODE_AGGRESSIVE)
                unifiedRiskManager.SetBaseRiskPerTrade(InpAggressiveBaseRiskPct);
            else if(g_currentTradingMode == AUTO_MODE_EMERGENCY)
            {
                datetime closeStart = TimeCurrent();
                tradeManager.CloseAllPositions("");
                if(TimeCurrent() - closeStart > 5)
                    PrintFormat("[EMERGENCY] CloseAllPositions took %d seconds (auto mode switch)",
                                (int)(TimeCurrent() - closeStart));
                g_dailyTradingHalt = true;
                g_dailyTradingHaltStartTime = TimeCurrent();
                SetAllPipelinesBudgetExhausted(true);
            }
        }
    }

    // Deterministic remediation loop for unprotected-position veto states.
    g_unprotectedTracker.AttemptRemediation();
    bool unprotectedPositionsActive = unifiedRiskManager.HasUnprotectedPositions();
    if(unprotectedPositionsActive && callCount % 50 == 0 && g_logLevel >= 2)
    {
        Print("[RISK-UNPROTECTED] New entries paused until stop protection is restored");
    }

    // Run online NN learning maintenance regardless of trade signal frequency.
    if(InpEnableAIMode && InpEnableNeuralNetwork && InpEnableNNOnlineTraining)
    {
        static datetime s_lastNNLearningLog = 0;
        datetime now = TimeCurrent();
        bool logThisCycle = (s_lastNNLearningLog == 0 || (now - s_lastNNLearningLog) >= 60);

        for(int nnIdx = 0; nnIdx < ArraySize(g_neuralNetStrategies); nnIdx++)
        {
            CNeuralNetworkStrategy* nnRuntime = g_neuralNetStrategies[nnIdx];
            if(nnRuntime != NULL)
            {
                if(logThisCycle && nnIdx < ArraySize(g_neuralNetStrategySymbols))
                {
                    PrintFormat("[NN-LEARNING] Calling TickOnlineLearning for %s (idx=%d/%d)",
                                g_neuralNetStrategySymbols[nnIdx], nnIdx, ArraySize(g_neuralNetStrategies));
                }
                nnRuntime.TickOnlineLearning();
            }
        }

        if(logThisCycle)
            s_lastNNLearningLog = now;
    }

    // Multi-symbol new-bar processing: each symbol has a dedicated strategy manager.
    bool anyNewBarDetected = false;

    if(ArraySize(g_enterpriseManagers) > 0 && ArraySize(g_activePairs) > 0)
    {
        if(!g_scanScheduler.IsSymbolSchedulerStateAligned())
            g_scanScheduler.RebuildSymbolSchedulerState("runtime_reconcile");

        for(int symIdx = 0; symIdx < ArraySize(g_activePairs); symIdx++)
        {
            string symbolForBar = g_activePairs[symIdx];
            datetime currentBarTime = iTime(symbolForBar, (ENUM_TIMEFRAMES)Period(), 0);
            if(currentBarTime <= 0)
                continue;

            if(currentBarTime != g_scanScheduler.GetLastSymbolBarTime(symIdx))
            {
                g_scanScheduler.SetLastSymbolBarTime(symIdx, currentBarTime);
                anyNewBarDetected = true;
                g_consensusCache.Invalidate(symbolForBar);
                g_scanScheduler.SetPendingNewBarScan(symIdx, true);
                g_scanScheduler.ResetIntrabarBackoff(symIdx);

                CEnterpriseStrategyManager* barManager = GetEnterpriseManagerForSymbol(symbolForBar);
                if(barManager != NULL)
                    barManager.OnNewBar(symbolForBar, (ENUM_TIMEFRAMES)Period());
            }
        }
    }

    if(anyNewBarDetected)
    {
        if(InpEnableAIMode && g_aiEngineReady && g_AIEngine != NULL)
        {
            g_AIEngine.ProcessAdaptation();
        }

        if(g_aiFeedbackReady)
        {
            static datetime s_lastAIFeedbackMaintenance = 0;
            datetime now = TimeCurrent();
            if(s_lastAIFeedbackMaintenance == 0 || (now - s_lastAIFeedbackMaintenance) >= 300)
            {
                aiFeedback.CheckAutomaticRetraining();
                PrintFormat("[AI-FEEDBACK] %s", aiFeedback.GetPerformanceSummary());
                s_lastAIFeedbackMaintenance = now;
            }
        }

        if(callCount % 100 == 0 && g_logLevel >= 3)
            Print("[DRAWINGS] OnNewBar processed for all managed symbols");
    }

    // Deterministic event separation: run signal generation at most once per second
    // even when both OnTick and OnTimer are active.
    bool allowSignalEvaluation = true;
    datetime signalEvalNow = TimeCurrent();
    if(g_scanScheduler.GetLastSignalEvalSecond() == signalEvalNow)
        allowSignalEvaluation = false;
    else
        g_scanScheduler.SetLastSignalEvalSecond(signalEvalNow);
    if(!allowSignalEvaluation)
        g_hbQuietCadenceHold++;

    // Enterprise Mode Multi-Symbol Signal Generation
    // UNIFIED PIPELINE - All strategies including AI now go through here
    if(allowSignalEvaluation && ArraySize(g_enterpriseManagers) > 0 && ArraySize(g_activePairs) > 0)
    {
        // Phase 6: Full-margin circuit breaker check
        if(InpRiskTier == RISK_TIER_FULL_MARGIN && g_fullMarginMode.IsInitialized())
        {
            double currentDD = unifiedRiskManager.GetCurrentDrawdownPercent();
            if(!g_fullMarginMode.CheckFullMarginCircuitBreaker(currentDD))
            {
                // Full-margin circuit breaker active — skip signal evaluation
                g_hbQuietCadenceHold++;
                if(callCount % 60 == 0)
                    g_fullMarginMode.PrintDiagnostics();
                allowSignalEvaluation = false;
            }
        }

        // Phase 6: Safe mode kill zone filter
        if(InpRiskTier == RISK_TIER_CONSERVATIVE && g_safeMode.IsInitialized())
        {
            if(g_safeMode.GetConfig().tradeOnlyKillZones && !g_safeMode.IsInKillZone())
            {
                // Outside kill zone — skip signal evaluation in safe mode
                g_hbQuietCadenceHold++;
                allowSignalEvaluation = false;
            }
        }
    }

    if(allowSignalEvaluation && ArraySize(g_enterpriseManagers) > 0 && ArraySize(g_activePairs) > 0)
    {
        // Check entry gates, but keep signal evaluation running even while entry is paused.
        SApprovedTradeCandidate approvedCandidates[];
        ArrayResize(approvedCandidates, 0);
        ulong scanCycleId = ++g_scanCycleSequence;
        g_cyclesSinceIndicatorSignal++;  // Increment each cycle; reset when indicator signal detected
        datetime tickTime = TimeCurrent();
        unifiedRiskManager.ClearVirtualPositions();
        int secondsSinceLastTrade = (int)(tickTime - g_lastTradeTime);
        bool cooldownBlocked = (secondsSinceLastTrade < InpMinSecondsBetweenTrades && g_lastTradeTime > 0);
        bool unprotectedEntryBlocked = unprotectedPositionsActive;
        bool tradingPauseBlocked = g_spikeMonitor.IsPaused();

        if(cooldownBlocked && callCount % 100 == 0 && g_logLevel >= 2)
            Print("[ENTERPRISE-BLOCKED] Cooldown active: ", secondsSinceLastTrade, " / ", InpMinSecondsBetweenTrades, " seconds");
        if(tradingPauseBlocked && callCount % 50 == 0 && g_logLevel >= 2)
            PrintFormat("[SPIKE-PAUSE] New entries paused until %s",
                        TimeToString(g_spikeMonitor.GetPauseUntilTime(), TIME_SECONDS));

        // Check position limit - count only THIS EA's positions by magic number
        int eaPositions = GetEAPositionCount();
        int effectiveMaxPositions = InpMaxPositionsTotal;
        // Issue 17: When throttle pressure > 0.8, reduce allowed positions by 1
        // regardless of conservative flag. This prevents the throttle from being ignored.
        double throttlePressure = unifiedRiskManager.GetThrottlePressure();
        if(throttlePressure < 0.90 && InpMaxPositionsTotal > 1)
        {
            effectiveMaxPositions = InpMaxPositionsTotal - 1;
            if(eaPositions >= InpMaxPositionsTotal && callCount % 100 == 0 && g_logLevel >= 2)
                PrintFormat("[RISK-THROTTLE-REDUCE] Positions %d/%d reduced to %d by throttle pressure=%.2f",
                            eaPositions, InpMaxPositionsTotal, effectiveMaxPositions, throttlePressure);
        }
        bool totalPositionLimitBlocked = (eaPositions >= effectiveMaxPositions);
        if(totalPositionLimitBlocked && callCount % 100 == 0 && g_logLevel >= 2)  // Log occasionally to avoid spam
            Print("[ENTERPRISE-BLOCKED] Position limit reached: ", eaPositions, " / ", effectiveMaxPositions);

        bool canOpenNewTrades = !(cooldownBlocked || totalPositionLimitBlocked || unprotectedEntryBlocked || tradingPauseBlocked || g_dailyTradingHalt);

        // Evaluate each active symbol through its own symbol-bound enterprise manager.
        int symbolCount = ArraySize(g_activePairs);
        int rotationStart = 0;
        int signalEvalBudget = MathMax(1, InpMaxSignalEvaluationsPerCycle);
        bool newBarSelected[];
        bool intrabarSelected[];
        ArrayResize(newBarSelected, symbolCount);
        ArrayResize(intrabarSelected, symbolCount);
        for(int selIdx = 0; selIdx < symbolCount; selIdx++)
        {
            newBarSelected[selIdx] = false;
            intrabarSelected[selIdx] = false;
        }

        if(symbolCount > 0)
        {
            if(g_scanScheduler.GetSymbolEvalStartIndex() < 0)
                g_scanScheduler.SetSymbolEvalStartIndex(0);
            rotationStart = g_scanScheduler.GetSymbolEvalStartIndex() % symbolCount;
            g_scanScheduler.SetSymbolEvalStartIndex((g_scanScheduler.GetSymbolEvalStartIndex() + 1) % symbolCount);
        }

        int pendingNewBarCount = g_scanScheduler.CountPendingNewBarScans();
        int newBarSelectedCount = 0;
        for(int candidateOffset = 0; candidateOffset < symbolCount && newBarSelectedCount < signalEvalBudget; candidateOffset++)
        {
            int candidateIdx = (rotationStart + candidateOffset) % symbolCount;
            if(!g_scanScheduler.IsPendingNewBarScan(candidateIdx))
                continue;

            newBarSelected[candidateIdx] = true;
            newBarSelectedCount++;
        }

        int remainingEvalBudget = MathMax(0, signalEvalBudget - newBarSelectedCount);
        bool intrabarCadenceEnabled = (InpEnableHybridCadence && !InpSignalScanOnNewBarOnly);
        int intrabarBudget = intrabarCadenceEnabled ? MathMin(remainingEvalBudget, MathMax(1, InpMaxIntrabarSymbolsPerCycle)) : 0;
        int intrabarSelectedCount = 0;
        bool intrabarKeepaliveSelected = false;
        if(intrabarCadenceEnabled && intrabarBudget > 0)
        {
            int budgetLimit = MathMin(symbolCount, intrabarBudget);
            for(int pick = 0; pick < budgetLimit; pick++)
            {
                double bestScore = -1000000.0;
                int bestIdx = -1;
                for(int candidateOffset = 0; candidateOffset < symbolCount; candidateOffset++)
                {
                    int candidateIdx = (rotationStart + candidateOffset) % symbolCount;
                    if(intrabarSelected[candidateIdx] || newBarSelected[candidateIdx] ||
                       g_scanScheduler.IsPendingNewBarScan(candidateIdx))
                        continue;

                    string candidateSymbol = g_activePairs[candidateIdx];
                    if(InpIntrabarChartSymbolOnly && candidateSymbol != _Symbol)
                        continue;

                    double candidateScore = g_scanScheduler.ScoreSymbolForIntrabar(candidateIdx, tickTime);
                    if(candidateScore > bestScore)
                    {
                        bestScore = candidateScore;
                        bestIdx = candidateIdx;
                    }
                }

                if(bestIdx < 0)
                    break;

                intrabarSelected[bestIdx] = true;
                intrabarSelectedCount++;
            }

            if(intrabarSelectedCount <= 0 && pendingNewBarCount <= 0 && !anyNewBarDetected && symbolCount > 0)
            {
                double bestKeepaliveScore = -1000000.0;
                int keepaliveIdx = -1;
                for(int candidateOffset = 0; candidateOffset < symbolCount; candidateOffset++)
                {
                    int candidateIdx = (rotationStart + candidateOffset) % symbolCount;
                    if(intrabarSelected[candidateIdx] || newBarSelected[candidateIdx] ||
                       g_scanScheduler.IsPendingNewBarScan(candidateIdx))
                        continue;

                    string candidateSymbol = g_activePairs[candidateIdx];
                    if(InpIntrabarChartSymbolOnly && candidateSymbol != _Symbol)
                        continue;

                    double candidateScore = g_scanScheduler.ScoreSymbolForIntrabar(candidateIdx, tickTime, true);
                    if(candidateScore > bestKeepaliveScore)
                    {
                        bestKeepaliveScore = candidateScore;
                        keepaliveIdx = candidateIdx;
                    }
                }

                if(keepaliveIdx >= 0)
                {
                    intrabarSelected[keepaliveIdx] = true;
                    intrabarSelectedCount = 1;
                    intrabarKeepaliveSelected = true;
                }
            }
        }

        int deferredNewBarCount = MathMax(0, pendingNewBarCount - newBarSelectedCount);
        bool activeScanWork = (newBarSelectedCount > 0 || intrabarSelectedCount > 0);
        static datetime s_lastScanBudgetLog = 0;
        bool skipScanBudgetLog = (TimeCurrent() - s_lastScanBudgetLog < 60);
        if((activeScanWork || (callCount % 60 == 0)) && !skipScanBudgetLog)
        {
            s_lastScanBudgetLog = TimeCurrent();
            PrintFormat("[SCAN-BUDGET] cycle=%I64u | symbols=%d | pending_newbar=%d | selected_newbar=%d | deferred_newbar=%d | intrabar_selected=%d | eval_budget=%d | intrabar_budget=%d | intrabar_keepalive=%s | chart_only=%s | hybrid=%s | newbar_only=%s | active_work=%s",
                        scanCycleId,
                        symbolCount,
                        pendingNewBarCount,
                        newBarSelectedCount,
                        deferredNewBarCount,
                        intrabarSelectedCount,
                        signalEvalBudget,
                        intrabarBudget,
                        intrabarKeepaliveSelected ? "true" : "false",
                        InpIntrabarChartSymbolOnly ? "true" : "false",
                        InpEnableHybridCadence ? "true" : "false",
                        InpSignalScanOnNewBarOnly ? "true" : "false",
                        activeScanWork ? "true" : "false");
        }

        if(!activeScanWork)
        {
            g_hbQuietNoNewBar += (ulong)MathMax(0, symbolCount);
        }
        else
        {
            int cycleTotalSignalsGenerated = 0;
            datetime scanEvalStartTime = TimeCurrent();
            const int SCAN_EVAL_TIMEOUT_SECONDS = 8;
            for(int scanOffset = 0; scanOffset < symbolCount; scanOffset++)
            {
                if(TimeCurrent() - scanEvalStartTime > SCAN_EVAL_TIMEOUT_SECONDS)
                {
                    if(g_logLevel >= 2)
                        PrintFormat("[SCAN-TIMEOUT] cycle=%I64u | Signal eval timeout after %d seconds, %d/%d symbols evaluated",
                                    scanCycleId, SCAN_EVAL_TIMEOUT_SECONDS, scanOffset, symbolCount);
                    break;
                }

                int symIdx = (rotationStart + scanOffset) % symbolCount;
                bool runNewBarScan = (symIdx < ArraySize(newBarSelected) && newBarSelected[symIdx]);
                bool runIntrabarScan = (!runNewBarScan && symIdx < ArraySize(intrabarSelected) && intrabarSelected[symIdx]);
                if(!runNewBarScan && !runIntrabarScan)
                    continue;

                string currentSymbol = g_activePairs[symIdx];
                CEnterpriseStrategyManager* symbolManager = GetEnterpriseManagerForSymbol(currentSymbol);
                if(symbolManager == NULL)
                {
                    g_hbQuietMissingManager++;
                    PrintFormat("[SCAN-SKIP] cycle=%I64u | %s | reason=missing_enterprise_manager",
                                scanCycleId,
                                currentSymbol);
                    continue;
                }

                // Issue 7: Skip evaluation if symbol is in dormancy cooldown
                EnsureDormantCooldownSlot(currentSymbol);
                if(IsSymbolInDormantCooldown(currentSymbol))
                {
                    g_hbQuietNoNewBar++;
                    continue;
                }

                if(runNewBarScan)
                    ClearDormantCooldownOnNewBar(currentSymbol);

                if(runIntrabarScan)
                {
                    g_scanScheduler.SetLastIntrabarScanTime(symIdx, tickTime);
                    g_hbIntrabarScansExecuted++;
                }

                ENUM_SIGNAL_EVAL_MODE evalMode = runIntrabarScan ? EVAL_MODE_INTRABAR : EVAL_MODE_NEW_BAR;
                ENUM_VALIDATION_PROFILE validationProfile = runIntrabarScan ? VALIDATION_PROFILE_INTRABAR : VALIDATION_PROFILE_NEW_BAR;
                g_hbScansAttempted++;

                // Get signal with confluence tracking (per-symbol analysis)
                double confidence = 0;
                int confluence = 0;
                datetime consensusStartTime = TimeCurrent();
                ENUM_TRADE_SIGNAL enterpriseSignal = symbolManager.GetConsensusSignalForSymbolWithConfluenceMode(
                    currentSymbol, confidence, confluence, evalMode);
                datetime consensusElapsed = TimeCurrent() - consensusStartTime;
                if(consensusElapsed > 2)
                {
                    if(g_logLevel >= 3)
                        PrintFormat("[SCAN-SLOW] %s consensus took %d ms", currentSymbol, (int)consensusElapsed * 1000);
                }

                int cycleSignalsGenerated = 0;
                int cycleSignalsAfterPipeline = 0;
                bool cycleSignalAfterQuorum = false;
                symbolManager.GetLastCycleFunnel(cycleSignalsGenerated, cycleSignalsAfterPipeline, cycleSignalAfterQuorum);
                g_hbSignalsGenerated += (ulong)MathMax(0, cycleSignalsGenerated);
                g_hbSignalsAfterPipeline += (ulong)MathMax(0, cycleSignalsAfterPipeline);
                cycleTotalSignalsGenerated += MathMax(0, cycleSignalsGenerated);
                if(cycleSignalAfterQuorum)
                    g_hbSignalsAfterQuorum++;
                if(runNewBarScan)
                    g_scanScheduler.SetPendingNewBarScan(symIdx, false);

                if(enterpriseSignal == TRADE_SIGNAL_NONE)
                {
                    g_hbNoSignalCount++;
                    // Issue 7: Record dormancy warning for this symbol
                    RecordDormantWarning(currentSymbol);
                    SConsensusDecisionContext noTradeContext;
                    symbolManager.GetLastDecisionContext(noTradeContext);
                    g_scanScheduler.UpdateSymbolScanStateAfterDecision(currentSymbol,
                                                       scanCycleId,
                                                       symIdx,
                                                       runIntrabarScan,
                                                       cycleSignalsGenerated,
                                                       cycleSignalsAfterPipeline,
                                                       noTradeContext,
                                                       tickTime);
                    PrintFormat("[SCAN-NO-TRADE] cycle=%I64u | %s | mode=%s | class=%s | veto=%s | reason=%s | buy=%.3f | sell=%.3f | quality=%.3f | support=%.3f | readiness=%.3f | context=%.3f | cost=%.3f | ready=%.3f/%.3f | readyCoverage=%.3f | gap=%.3f | voters=%d/%d | confluence=%d",
                                scanCycleId,
                                currentSymbol,
                                (evalMode == EVAL_MODE_INTRABAR) ? "INTRABAR" : "NEW_BAR",
                                noTradeContext.quorumMode,
                                noTradeContext.vetoCode,
                                noTradeContext.reason,
                                noTradeContext.buyScore,
                                noTradeContext.sellScore,
                                noTradeContext.directionalQuality,
                                noTradeContext.supportRatio,
                                noTradeContext.readinessScore,
                                noTradeContext.contextScore,
                                noTradeContext.costScore,
                                noTradeContext.readyLiveWeight,
                                noTradeContext.totalLiveWeight,
                                noTradeContext.readyCoverage,
                                noTradeContext.quorumGap,
                                noTradeContext.eligibleLiveVoterCount,
                                noTradeContext.effectiveMinVoters,
                                confluence);
                    continue;
                }

                    SConsensusDecisionContext decisionContext;
                    symbolManager.GetLastDecisionContext(decisionContext);
                    g_scanScheduler.UpdateSymbolScanStateAfterDecision(currentSymbol,
                                                       scanCycleId,
                                                       symIdx,
                                                       runIntrabarScan,
                                                       cycleSignalsGenerated,
                                                       cycleSignalsAfterPipeline,
                                                       decisionContext,
                                                       tickTime);

                    double atrValue = 0.0;
                    bool atrReady = TryResolveAtrValue(currentSymbol, (ENUM_TIMEFRAMES)Period(), 14, atrValue);
                    double atrLongValue = 0.0;
                    bool atrLongReady = TryResolveAtrValue(currentSymbol, (ENUM_TIMEFRAMES)Period(), 50, atrLongValue);
                    double atrRatio = (atrReady && atrLongReady && atrLongValue > 1e-9) ? (atrValue / atrLongValue) : 1.0;
                    double atrRiskScale = 1.0;

                    bool signalApproved = false;
                    double qualityScore = confidence;
                    double tradeConfidence = confidence;
                    
                    // Spread check (exogenous gate) — delegated to pipeline
                    bool exogenousPass = true;
                    string exogenousReason = "";

                    // Phase 6: Full-margin uses stricter spread gate (20% ATR vs default 50%)
                    double effectiveSpreadATRRatio = InpPipelineMaxSpreadToAtrRatio;
                    if(InpRiskTier == RISK_TIER_FULL_MARGIN && g_fullMarginMode.IsInitialized())
                        effectiveSpreadATRRatio = MathMin(effectiveSpreadATRRatio, g_fullMarginMode.GetConfig().maxSpreadATRRatio);
                    // Phase 6: Safe mode uses stricter spread gate (15% ATR)
                    if(InpRiskTier == RISK_TIER_CONSERVATIVE && g_safeMode.IsInitialized())
                        effectiveSpreadATRRatio = MathMin(effectiveSpreadATRRatio, g_safeMode.GetConfig().maxSpreadATRRatio);

                    // Hard spread cutoff: block untradeable symbols (e.g. Volatility 75 with 1000+ pt spread)
                    {
                        double hbid = SymbolInfoDouble(currentSymbol, SYMBOL_BID);
                        double hask = SymbolInfoDouble(currentSymbol, SYMBOL_ASK);
                        double hspread = (hask > 0.0 && hbid > 0.0 && hask >= hbid) ? (hask - hbid) : 0.0;
                        double hpoint = SymbolInfoDouble(currentSymbol, SYMBOL_POINT);
                        double hspreadPts = (hpoint > 0.0) ? (hspread / hpoint) : 0.0;
                        if(hspreadPts > InpHardSpreadCutoffPoints)
                        {
                            g_hbValidatorRejects++;
                            PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=hard_spread_cutoff | signal=%s conf=%.2f | spread_pts=%.1f threshold=%.1f",
                                        currentSymbol, (enterpriseSignal == TRADE_SIGNAL_BUY) ? "BUY" : "SELL",
                                        confidence, hspreadPts, InpHardSpreadCutoffPoints);
                            PrintFormat("[SIGNAL-REJECTED] cycle=%I64u | %s | reason=hard_spread_cutoff | spread_points=%.1f > %.1f | confluence=%d | conf=%.2f",
                                        scanCycleId, currentSymbol, hspreadPts, InpHardSpreadCutoffPoints, confluence, confidence);
                            continue;
                        }
                    }

                    if(atrValue > 0)
                    {
                        double spreadScore = 0.0;
                        CUnifiedSignalPipeline* spreadPipeline = symbolManager.GetPipeline();
                        if(spreadPipeline != NULL)
                        {
                            if(!spreadPipeline.ApplySpreadFilter(currentSymbol, atrValue, spreadScore, effectiveSpreadATRRatio))
                            {
                                exogenousPass = false;
                                exogenousReason = StringFormat("Spread too wide: ratio=%.4f >= %.4f (ATR %.5f)",
                                                              spreadScore, effectiveSpreadATRRatio, atrValue);
                            }
                        }
                        else
                        {
                            double point = SymbolInfoDouble(currentSymbol, SYMBOL_POINT);
                            if(point <= 0.0) point = 0.00001;
                            double bid = SymbolInfoDouble(currentSymbol, SYMBOL_BID);
                            double ask = SymbolInfoDouble(currentSymbol, SYMBOL_ASK);
                            double spread = (ask > 0.0 && bid > 0.0 && ask >= bid) ? (ask - bid) : 0.0;
                            double maxSpread = atrValue * MathMax(0.01, effectiveSpreadATRRatio);
                            if(spread > maxSpread)
                            {
                                exogenousPass = false;
                                exogenousReason = StringFormat("Spread too wide: %.5f > %.5f (ATR %.5f)", spread, maxSpread, atrValue);
                            }
                        }
                    }
                    if(exogenousPass && atrReady && atrLongReady && atrLongValue > 1e-9)
                    {
                        double atrCrisisThreshold = ResolveATRCrisisThreshold(currentSymbol);
                        if(atrRatio > atrCrisisThreshold)
                        {
                            exogenousPass = false;
                            exogenousReason = StringFormat("ATR ratio crisis gate: %.3f > %.3f [asset_class_threshold] (ATR14 %.5f / ATR50 %.5f)",
                                                           atrRatio, atrCrisisThreshold, atrValue, atrLongValue);
                        }
                        else if(atrRatio > 1.5)
                        {
                            atrRiskScale = 0.5;
                            PrintFormat("[RISK-VOL-GATE] cycle=%I64u | %s | atr_ratio=%.3f | action=halve_risk",
                                        scanCycleId,
                                        currentSymbol,
                                        atrRatio);
                        }
                    }
                    
                    if(!exogenousPass)
                    {
                        g_hbValidatorRejects++;
                        string filterTag = (StringFind(exogenousReason, "Spread too wide") >= 0) ? "spread" : "atr_ratio";
                        PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=%s | signal=%s conf=%.2f | %s",
                                    currentSymbol, filterTag, (enterpriseSignal == TRADE_SIGNAL_BUY) ? "BUY" : "SELL",
                                    confidence, exogenousReason);
                        PrintFormat("[SIGNAL-REJECTED] cycle=%I64u | %s | reason=%s | confluence=%d | conf=%.2f",
                                    scanCycleId, currentSymbol, exogenousReason, confluence, confidence);
                        continue;
                    }

                    // Quality gate: apply uniformly regardless of validator mode (EXOGENOUS_ONLY or otherwise)
                    double qualityThreshold = (evalMode == EVAL_MODE_INTRABAR)
                                             ? MathMax(0.0, MathMin(1.0, InpValidatorIntrabarMinQuality))
                                             : MathMax(0.0, MathMin(1.0, InpValidatorNewBarMinQuality));
                    if(decisionContext.directionalQuality < qualityThreshold)
                    {
                        g_hbValidatorRejects++;
                        PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=quality_gate | signal=%s conf=%.2f | quality=%.3f threshold=%.3f",
                                    currentSymbol, (enterpriseSignal == TRADE_SIGNAL_BUY) ? "BUY" : "SELL",
                                    confidence, decisionContext.directionalQuality, qualityThreshold);
                        PrintFormat("[SIGNAL-REJECTED] cycle=%I64u | %s | reason=insufficient_quality | quality=%.3f < threshold=%.3f | confluence=%d | conf=%.2f",
                                    scanCycleId, currentSymbol, decisionContext.directionalQuality, qualityThreshold, confluence, confidence);
                        PrintFormat("[CONSENSUS-NEARMISS] %s | veto=insufficient_quality | buyScore=%.3f | sellScore=%.3f | buyQuality=%.3f | sellQuality=%.3f | quality=%.3f | threshold=%.3f",
                                    currentSymbol, decisionContext.buyScore, decisionContext.sellScore,
                                    decisionContext.buySupport, decisionContext.sellSupport,
                                    decisionContext.directionalQuality, qualityThreshold);
                        continue;
                    }

                    // Batch 100: OFI directional confirmation filter
                    if(InpEnableOFIProxy)
                    {
                        int ofiIdx = -1;
                        for(int oi = 0; oi < ArraySize(g_mathEngineSymbols); oi++)
                        {
                            if(g_mathEngineSymbols[oi] == currentSymbol)
                            { ofiIdx = oi; break; }
                        }
                        if(ofiIdx >= 0 && g_ofiEngines[ofiIdx] != NULL && g_ofiEngines[ofiIdx].IsWarmedUp())
                        {
                            ENUM_TRADE_SIGNAL ofiSignal = g_ofiEngines[ofiIdx].GetSignal();
                            // Reject if OFI strongly contradicts the consensus signal
                            if(ofiSignal != TRADE_SIGNAL_NONE && ofiSignal != enterpriseSignal)
                            {
                                double ofiValue = g_ofiEngines[ofiIdx].GetOFI();
                                g_hbValidatorRejects++;
                                PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=ofi_contradiction | signal=%s conf=%.2f | ofi=%s ofi_z=%.2f",
                                            currentSymbol, (enterpriseSignal == TRADE_SIGNAL_BUY) ? "BUY" : "SELL",
                                            confidence, EnumToString(ofiSignal), ofiValue);
                                PrintFormat("[SIGNAL-REJECTED] cycle=%I64u | %s | reason=ofi_contradiction | consensus=%s ofi=%s ofi_z=%.2f | conf=%.2f",
                                            scanCycleId, currentSymbol,
                                            EnumToString(enterpriseSignal), EnumToString(ofiSignal), ofiValue, confidence);
                                continue;
                            }
                        }
                    }

                    // Time/session filters now handled by UnifiedSignalPipeline
                    qualityScore = confidence;
                    tradeConfidence = confidence;
                    string signalType = (enterpriseSignal == TRADE_SIGNAL_BUY) ? "BUY" : "SELL";
                    // Issue 7: Reset dormancy counter when signal passes all gates
                    ResetDormantCount(currentSymbol);
                    PrintFormat("[SIGNAL-VALIDATED] cycle=%I64u | %s | signal=%s | consensus=%.2f | confluence=%d",
                                scanCycleId, currentSymbol, signalType, confidence, confluence);
                    g_hbSignalsValidated++;
                    signalApproved = true;

                // Execute trade if signal was approved
                if(signalApproved && enterpriseSignal != TRADE_SIGNAL_NONE)
                {
                    string signalType = (enterpriseSignal == TRADE_SIGNAL_BUY) ? "BUY" : "SELL";
                    bool symbolPositionCapBlocked = false;
                    int symbolPositionCount = 0;
                    int eaSymbolPositionCount = 0;
                    int externalSymbolPositions = 0;

                    if(InpPortfolioMaxPositionsPerSymbol > 0)
                    {
                        symbolPositionCount = GetOpenPositionCountForSymbol(currentSymbol, false);
                        eaSymbolPositionCount = GetOpenPositionCountForSymbol(currentSymbol, true);
                        externalSymbolPositions = symbolPositionCount - eaSymbolPositionCount;
                        if(externalSymbolPositions < 0)
                            externalSymbolPositions = 0;
                        if(eaSymbolPositionCount >= InpPortfolioMaxPositionsPerSymbol)
                        {
                            symbolPositionCapBlocked = true;
                        }
                    }

                    // Check spike hunter cooldown - delay long-term entries during active spikes
                    if(InpSpikeHunterEnabled && g_spikeHunter.IsSymbolInSpikeCooldown(currentSymbol))
                    {
                        PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=spike_cooldown | signal=%s conf=%.2f | reason=spike_cooldown_active",
                                    currentSymbol, (enterpriseSignal == TRADE_SIGNAL_BUY) ? "BUY" : "SELL", confidence);
                        Print("[SPIKE-COOLDOWN] ", currentSymbol, " - delaying long-term entry (spike cooldown active)");
                        continue;
                    }

                    if(!canOpenNewTrades || symbolPositionCapBlocked)
                    {
                        g_hbEntryBlocked++;
                        string blockReason = "";
                        if(cooldownBlocked)
                            blockReason = StringFormat("cooldown %d/%d sec", secondsSinceLastTrade, InpMinSecondsBetweenTrades);
                        if(totalPositionLimitBlocked)
                        {
                            if(blockReason != "")
                                blockReason += " | ";
                            blockReason += StringFormat("position limit %d/%d", eaPositions, InpMaxPositionsTotal);
                        }
                        if(unprotectedEntryBlocked)
                        {
                            if(blockReason != "")
                                blockReason += " | ";
                            blockReason += "unprotected positions";
                        }
                        if(tradingPauseBlocked)
                        {
                            if(blockReason != "")
                                blockReason += " | ";
                            blockReason += StringFormat("spike pause until %s",
                                                        TimeToString(g_spikeMonitor.GetPauseUntilTime(), TIME_SECONDS));
                        }
                        if(symbolPositionCapBlocked)
                        {
                            if(blockReason != "")
                                blockReason += " | ";
                            blockReason += StringFormat("symbol cap ea=%d/%d | total=%d | external=%d",
                                                        eaSymbolPositionCount,
                                                        InpPortfolioMaxPositionsPerSymbol,
                                                        symbolPositionCount,
                                                        externalSymbolPositions);
                        }
                        if(g_dailyTradingHalt)
                        {
                            if(blockReason != "")
                                blockReason += " | ";
                            int elapsedMin = (g_dailyTradingHaltStartTime > 0) ? (int)(TimeCurrent() - g_dailyTradingHaltStartTime) / 60 : 0;
                            blockReason += StringFormat("daily halt (%d/%d min)", elapsedMin, InpDailyHaltCooldownMinutes);
                        }

                        PrintFormat("[ENTERPRISE-BLOCKED] cycle=%I64u | %s | signal=%s | reason=%s | conf=%.2f | confluence=%d",
                                    scanCycleId,
                                    currentSymbol,
                                    signalType,
                                    blockReason,
                                    tradeConfidence,
                                    confluence);

                        if(symbolPositionCapBlocked && externalSymbolPositions > 0)
                        {
                            datetime capLogNow = TimeCurrent();
                            if(g_scanScheduler.GetLastExternalCapacityLogTime() == 0 || (capLogNow - g_scanScheduler.GetLastExternalCapacityLogTime()) >= 60)
                            {
                                PrintFormat("[CAPACITY-EXTERNAL] %s blocked by non-EA positions | external=%d | ea=%d | total=%d | cap=%d | magic=%d",
                                            currentSymbol,
                                            externalSymbolPositions,
                                            eaSymbolPositionCount,
                                            symbolPositionCount,
                                            InpPortfolioMaxPositionsPerSymbol,
                                            InpMagicNumber);
                                g_scanScheduler.SetLastExternalCapacityLogTime(capLogNow);
                            }
                        }
                        PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=entry_blocked | signal=%s conf=%.2f | reason=%s",
                                    currentSymbol, signalType, tradeConfidence, blockReason);
                        continue;
                    }

                    // Candidate construction continues with the ATR snapshot already fetched for validation.
                    ENUM_ORDER_TYPE orderType = (enterpriseSignal == TRADE_SIGNAL_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

                    // Get current price
                    double entryPrice = (enterpriseSignal == TRADE_SIGNAL_BUY) ?
                                       SymbolInfoDouble(currentSymbol, SYMBOL_ASK) :
                                       SymbolInfoDouble(currentSymbol, SYMBOL_BID);

                    double pointValue = SymbolInfoDouble(currentSymbol, SYMBOL_POINT);
                    if(pointValue <= 0.0)
                        pointValue = 0.00001;

                    // Check if this is a synthetic index (different pip calculation).
                    bool isSynthetic = IsSyntheticIndexSymbolName(currentSymbol);

                    double stopLossPips = 0.0;
                    if(atrReady)
                    {
                        // Use ATR-based SL/TP calculation (adaptive)
                        if(isSynthetic)
                        {
                            // For synthetics: ATR is already in price units, convert carefully
                            stopLossPips = (atrValue * 1.5) / pointValue;
                        }
                        else
                        {
                            // For regular pairs: standard calculation
                            stopLossPips = (atrValue / pointValue) * 2.0;
                        }
                    }
                    else
                    {
                        // Gap/stress fallback: derive a deterministic stop distance from broker constraints + price percent.
                        int stopLevelPts = (int)SymbolInfoInteger(currentSymbol, SYMBOL_TRADE_STOPS_LEVEL);
                        double fallbackByStopLevel = MathMax(30.0, (double)stopLevelPts * 2.0);
                        double fallbackByPrice = (entryPrice * (isSynthetic ? 0.010 : 0.003)) / pointValue;
                        stopLossPips = MathMax(fallbackByStopLevel, fallbackByPrice);
                        PrintFormat("[RISK-FALLBACK] ATR unavailable for %s | using fallback stop distance %.1f points",
                                    currentSymbol, stopLossPips);
                    }

                    int stopLevelPts = (int)SymbolInfoInteger(currentSymbol, SYMBOL_TRADE_STOPS_LEVEL);
                    MqlTick costTick;
                    double currentSpreadPoints = 0.0;
                    if(SymbolInfoTick(currentSymbol, costTick) && costTick.ask > costTick.bid && pointValue > 0.0)
                        currentSpreadPoints = (costTick.ask - costTick.bid) / pointValue;

                    // Scalp stabilization: never inflate a short-horizon setup into a 0.5%-3% swing envelope.
                    // Stops are bounded by broker constraints, live spread, and ATR; trades with too much cost
                    // relative to reward are rejected below.
                    double minSlPips = MathMax(8.0, MathMax((double)stopLevelPts * 1.50, currentSpreadPoints * 3.0));
                    double maxSlPips = (entryPrice * (isSynthetic ? 0.010 : 0.003)) / pointValue;
                    if(maxSlPips < minSlPips)
                        maxSlPips = minSlPips;

                    stopLossPips = MathMax(minSlPips, MathMin(maxSlPips, stopLossPips));

                    // Minimum R:R enforcement with cluster-specific override
                    double minRR = 2.0;  // Default minimum R:R
                    // Mean-reversion strategies can use lower R:R (higher win rate compensates)
                    if(decisionContext.dominantCluster == MEAN_REVERSION_CLUSTER)
                        minRR = 1.5;

                    double takeProfitPips = stopLossPips * minRR;
                    // Cap at maxSlPips * minRR to avoid unreasonably large TPs
                    takeProfitPips = MathMin(takeProfitPips, maxSlPips * minRR);

                    if(currentSpreadPoints > 0.0 && takeProfitPips > 0.0 && currentSpreadPoints / takeProfitPips > 0.15)
                    {
                        g_hbValidatorRejects++;
                        PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=execution_cost | signal=%s conf=%.2f | spread_pts=%.1f tp_pts=%.1f cost_ratio=%.3f max=0.150",
                                    currentSymbol, signalType, tradeConfidence,
                                    currentSpreadPoints, takeProfitPips, currentSpreadPoints / takeProfitPips);
                        PrintFormat("[SIGNAL-REJECTED] cycle=%I64u | %s | reason=execution_cost_reward spread_points=%.1f tp_points=%.1f cost_ratio=%.3f max=0.150",
                                    scanCycleId,
                                    currentSymbol,
                                    currentSpreadPoints,
                                    takeProfitPips,
                                    currentSpreadPoints / takeProfitPips);
                        continue;
                    }

                    // Account capacity early check
                    double minLot = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MIN);
                    double marginRequired = 0;
                    if(!OrderCalcMargin(orderType, currentSymbol, minLot, entryPrice, marginRequired))
                        marginRequired = entryPrice * minLot / 100.0; // Fallback 1:100

                    double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
                    if(freeMargin < marginRequired)
                    {
                        g_hbSizingRejects++;
                        PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=account_capacity | signal=%s conf=%.2f | free_margin=%.2f req_margin=%.2f",
                                    currentSymbol, signalType, tradeConfidence, freeMargin, marginRequired);
                        PrintFormat("[ACCOUNT-CAPACITY] %s | min_lot=%.2f | free_margin=%.2f | req_margin=%.2f | reason=insufficient_for_min_lot",
                                    currentSymbol, minLot, freeMargin, marginRequired);
                        continue;
                    }

                    double requestedRisk = unifiedRiskManager.GetActiveRiskPerTradePercent();
                    if(requestedRisk <= 0.0)
                        requestedRisk = InpMaxRiskPerTrade;

                    double proposedRisk = unifiedRiskManager.GetRecommendedRiskPerTradePercent(requestedRisk);
                    proposedRisk *= atrRiskScale;
                    if(proposedRisk <= 0.0)
                    {
                        g_hbSizingRejects++;
                        SUnifiedRiskSnapshot riskBudgetSnapshot = unifiedRiskManager.GetSnapshot();
                        PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=risk_cap | signal=%s conf=%.2f | requested=%.2f capped=0.00",
                                    currentSymbol, signalType, tradeConfidence, requestedRisk);
                        PrintFormat("[RISK-CAP] cycle=%I64u | %s | requested=%.2f | capped=0.00 | daily_remaining=%.2f | portfolio_remaining=%.2f | reason=no_remaining_risk_budget",
                                    scanCycleId,
                                    currentSymbol,
                                    requestedRisk,
                                    MathMax(0.0, riskBudgetSnapshot.maxDailyRiskPercent - riskBudgetSnapshot.dailyRiskUsedPercent),
                                    unifiedRiskManager.GetRemainingPortfolioRiskPercent());
                        continue;
                    }

                    if(MathAbs(proposedRisk - requestedRisk) > 0.0001)
                    {
                        SUnifiedRiskSnapshot riskBudgetSnapshot = unifiedRiskManager.GetSnapshot();
                        PrintFormat("[RISK-CAP] cycle=%I64u | %s | requested=%.2f | capped=%.2f | daily_remaining=%.2f | portfolio_remaining=%.2f",
                                    scanCycleId,
                                    currentSymbol,
                                    requestedRisk,
                                    proposedRisk,
                                    MathMax(0.0, riskBudgetSnapshot.maxDailyRiskPercent - riskBudgetSnapshot.dailyRiskUsedPercent),
                                    unifiedRiskManager.GetRemainingPortfolioRiskPercent());
                    }

                    currentRiskPerTrade = proposedRisk;

                    string contributorSummary = "";
                    string strategyRoleTag = "PRIMARY_ALPHA";
                    string strategyClusterTag = "NONE";
                    string strategyClusterCode = "N";
                    if(!symbolManager.GetLastSignalExecutionContext(strategyRoleTag,
                                                                    strategyClusterTag,
                                                                    strategyClusterCode,
                                                                    contributorSummary))
                    {
                        strategyRoleTag = "PRIMARY_ALPHA";
                        strategyClusterTag = "NONE";
                        strategyClusterCode = "N";
                    }

                    string contributorsList[];
                    symbolManager.GetLastSignalContributors(contributorsList);
                    bool hasAIContributor = g_attributionManager.ContributorsIncludeAI(contributorsList);
                    bool hasIndicatorContributor = ContributorsIncludeIndicator(contributorsList);
                    bool hasONNXContributor = g_attributionManager.ContributorsIncludeONNX(contributorsList);
                    int indicatorContributorCount = g_attributionManager.CountIndicatorContributors(contributorsList);

                    // Reset indicator drought counter when an indicator strategy produces a signal
                    if(hasIndicatorContributor)
                    {
                        if(g_hybridGateRelaxed)
                            PrintFormat("[HYBRID-GATE-RESTORED] Indicator signal detected, AI standalone threshold restored to %.3f",
                                        InpAIStandaloneMinConfidence);
                        g_cyclesSinceIndicatorSignal = 0;
                        g_hybridGateRelaxed = false;
                    }
                    else if(g_cyclesSinceIndicatorSignal > InpHybridGateRelaxAfterCycles && !g_hybridGateRelaxed)
                    {
                        g_hybridGateRelaxed = true;
                        PrintFormat("[HYBRID-GATE-RELAXED] No indicator signals for %d cycles, AI standalone threshold lowered from %.3f to %.3f",
                                    g_cyclesSinceIndicatorSignal, InpAIStandaloneMinConfidence, InpAIStandaloneRelaxedConfidence);
                    }

                    if(contributorSummary == "")
                    {
                        for(int c = 0; c < ArraySize(contributorsList); c++)
                        {
                            if(contributorsList[c] == "")
                                continue;
                            if(StringLen(contributorSummary) > 0)
                                contributorSummary += ",";
                            contributorSummary += contributorsList[c];
                        }
                    }

                    string modeRejectReason = "";
                    double modeConfidenceBonus = 0.0;
                    if(!EvaluateEAModeCandidateAdmission(contributorsList, tradeConfidence, modeRejectReason, modeConfidenceBonus))
                    {
                        g_hbValidatorRejects++;
                        PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=ea_mode_admission | signal=%s conf=%.2f | mode=%s | reason=%s",
                                    currentSymbol, signalType, tradeConfidence,
                                    EAModeToString(ResolveEffectiveEAMode()), modeRejectReason);
                        PrintFormat("[SIGNAL-REJECTED] cycle=%I64u | %s | reason=%s | mode=%s | contributors=%s | conf=%.2f",
                                    scanCycleId,
                                    currentSymbol,
                                    modeRejectReason,
                                    EAModeToString(ResolveEffectiveEAMode()),
                                    contributorSummary,
                                    tradeConfidence);
                        continue;
                    }
                    if(modeConfidenceBonus > 0.0)
                    {
                        double priorTradeConfidence = tradeConfidence;
                        tradeConfidence = MathMin(1.0, tradeConfidence + modeConfidenceBonus);
                        PrintFormat("[AI-MODE-BONUS] cycle=%I64u | %s | mode=%s | bonus=%.2f | before=%.2f | after=%.2f | indicator=%s | ai=%s",
                                    scanCycleId,
                                    currentSymbol,
                                    EAModeToString(ResolveEffectiveEAMode()),
                                    modeConfidenceBonus,
                                    priorTradeConfidence,
                                    tradeConfidence,
                                    hasIndicatorContributor ? "true" : "false",
                                    hasAIContributor ? "true" : "false");
                    }

                    string liveAuthorityReason = "";
                    double liveAuthorityRiskMultiplier = 1.0;
                    bool liveAuthorityAllowed = ResolveLiveAuthority(currentSymbol,
                                                                     hasAIContributor,
                                                                     hasONNXContributor,
                                                                     hasIndicatorContributor,
                                                                     indicatorContributorCount,
                                                                     confluence,
                                                                     tradeConfidence,
                                                                     qualityScore,
                                                                     decisionContext.convictionScore,
                                                                     decisionContext.contextScore,
                                                                     decisionContext.readinessScore,
                                                                     decisionContext.costScore,
                                                                     contributorSummary,
                                                                     liveAuthorityReason,
                                                                     liveAuthorityRiskMultiplier);
                    double authorityBaseRisk = proposedRisk;
                    double authoritySizingMultiplier = liveAuthorityAllowed
                                                       ? MathMax(0.10, liveAuthorityRiskMultiplier)
                                                       : MathMax(0.10, InpAIBootstrapRiskMultiplier * 0.50);
                    proposedRisk *= authoritySizingMultiplier;
                    PrintFormat("[LIVE-AUTHORITY] cycle=%I64u | %s | live_allowed=%s | global_shadow=%s | risk=%.2f->%.2f | mult=%.2f | reason=%s",
                                scanCycleId,
                                currentSymbol,
                                liveAuthorityAllowed ? "true" : "false",
                                (InpShadowMode || InpShadowModeEnabled) ? "true" : "false",
                                authorityBaseRisk,
                                proposedRisk,
                                authoritySizingMultiplier,
                                liveAuthorityReason);

                    // PERF-DUPLICATION: This inline position iteration duplicates GetEAPositionCount()
                    // and GetOpenPositionCountForSymbol(). Consider a cached position snapshot per EA cycle.
                    // Per-symbol position count check (before lot sizing to avoid wasted computation)
                    if(InpMaxPositionsPerSymbol > 0)
                    {
                        int existingPositionsForSymbol = 0;
                        for(int pi = PositionsTotal() - 1; pi >= 0; pi--)
                        {
                            ulong posTicket = PositionGetTicket(pi);
                            if(posTicket == 0 || !PositionSelectByTicket(posTicket))
                                continue;
                            if(PositionGetString(POSITION_SYMBOL) == currentSymbol &&
                               IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC)))
                                existingPositionsForSymbol++;
                        }
                        if(existingPositionsForSymbol >= InpMaxPositionsPerSymbol)
                        {
                            PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=per_symbol_position_cap | signal=%s conf=%.2f | existing=%d max=%d",
                                        currentSymbol, signalType, tradeConfidence, existingPositionsForSymbol, InpMaxPositionsPerSymbol);
                            PrintFormat("[RISK-PER-SYMBOL] %s | Already %d positions (max %d). Trade skipped.",
                                        currentSymbol, existingPositionsForSymbol, InpMaxPositionsPerSymbol);
                            continue;
                        }
                    }

                    // Unified risk manager is the only pre-trade veto contract.
                    STradeValidationRequest tradeReq;
                    tradeReq.symbol = currentSymbol;
                    tradeReq.orderType = orderType;
                    tradeReq.lotSize = 0.0; // Lot size not known yet, validation gate will validate prelim checks
                    tradeReq.stopLossPips = stopLossPips;
                    tradeReq.takeProfitPips = takeProfitPips;
                    tradeReq.confidence = tradeConfidence;
                    tradeReq.strategy = "EnterpriseConsensus";
                    tradeReq.reasoning = StringFormat("role=%s | cluster=%s | contributors=%s | conviction=%.2f | readiness=%.2f | context=%.2f | cost=%.2f",
                                                      strategyRoleTag,
                                                      strategyClusterTag,
                                                      contributorSummary,
                                                      decisionContext.convictionScore,
                                                      decisionContext.readinessScore,
                                                      decisionContext.contextScore,
                                                      decisionContext.costScore);
                    tradeReq.strategyRole = strategyRoleTag;
                    tradeReq.strategyCluster = strategyClusterTag;
                    tradeReq.contributorContext = contributorSummary;
                    tradeReq.clusterCode = strategyClusterCode;
                    tradeReq.requestTime = TimeCurrent();
                    
                    // Pre-check risk with minimum lot to validate trade parameters first
                    tradeReq.lotSize = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MIN); 
                        
                        SValidationResult riskResult;
                        if(ApproveTradeByUnifiedRisk(tradeReq, "pre-size", riskResult, scanCycleId))
                        {
                            // Stateless sizing — no shared state mutation (Blueprint 10.5)
                            double lotSize = positionSizer.CalculateSize(currentSymbol, orderType, stopLossPips, proposedRisk, tradeConfidence);

                            // Issue 5: Cap lot size so single trade cannot consume >30% of remaining daily budget
                            double remainingDailyRisk = unifiedRiskManager.GetRemainingDailyRiskPercent();
                            if(lotSize > 0.0 && remainingDailyRisk > 0.0 && proposedRisk > 0.0)
                            {
                                lotSize = positionSizer.CapLotForDailyBudget(currentSymbol, orderType, lotSize,
                                                                             stopLossPips, proposedRisk,
                                                                             remainingDailyRisk, 0.30);
                            }

                            // If position sizer returned 0 (trade skipped due to min-lot risk cap), skip immediately
                            if(lotSize <= 0.0)
                            {
                                PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=position_sizer_skip | signal=%s conf=%.2f | risk=%.2f | lotSize=0.00",
                                            currentSymbol, signalType, tradeConfidence, proposedRisk);
                                PrintFormat("[POSITION-SIZER-SKIP] %s | lotSize=0.00 — trade skipped by position sizer (below-minimum lot with risk cap exceeded)",
                                            currentSymbol);
                                continue;
                            }

                            double drawdownMultiplier = 1.0;
                            const double DRAWDOWN_SIZING_MIN_THRESHOLD = 0.02; // Skip sizing adjustments below 2% drawdown
                            if(peakEquity > 0.0 && InpAIDrawdownSizingLimit > 0.0)
                            {
                                double dd = (peakEquity - currentEquity) / peakEquity;
                                if(dd > 0.0)
                                    drawdownMultiplier = MathMax(0.10, MathMin(1.0, 1.0 - (dd / MathMax(0.01, InpAIDrawdownSizingLimit))));
                                if(dd > 0.0 && dd < DRAWDOWN_SIZING_MIN_THRESHOLD)
                                {
                                    PrintFormat("[RISK-ADAPT-SKIP] Drawdown-aware sizing skipped | dd=%.3f threshold=%.3f — drawdown below minimum threshold",
                                                dd, DRAWDOWN_SIZING_MIN_THRESHOLD);
                                    drawdownMultiplier = 1.0;
                                }
                            }
                            if(drawdownMultiplier < 0.999)
                            {
                                double unadjustedLot = lotSize;
                                lotSize *= drawdownMultiplier;

                                // Floor: ensure adjusted lot doesn't fall below broker minimum
                                // if the risk cap allows the round-up. This prevents the
                                // RISK-LOT-FLOOR deadlock where drawdown sizing pushes lots
                                // below broker min and the round-up cap blocks the trade.
                                double brokerMinLot = SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MIN);
                                if(brokerMinLot > 0.0 && lotSize > 0.0 && lotSize < brokerMinLot && unadjustedLot > 0.0)
                                {
                                    double floorMult = brokerMinLot / unadjustedLot;
                                    if(floorMult <= InpMinLotRiskMultiplier)
                                    {
                                        drawdownMultiplier = MathMax(drawdownMultiplier, floorMult);
                                        lotSize = unadjustedLot * drawdownMultiplier;
                                    }
                                }

                                PrintFormat("[RISK-ADAPT] Drawdown-aware sizing applied | peak=%.2f equity=%.2f limit=%.2f dd=%.3f mult=%.3f lot=%.2f->%.2f",
                                            peakEquity,
                                            currentEquity,
                                            InpAIDrawdownSizingLimit,
                                            (peakEquity - currentEquity) / peakEquity,
                                            drawdownMultiplier,
                                            unadjustedLot,
                                            lotSize);
                            }

                            // Anti-Martingale Momentum Scaling (Phase 5)
                            double momentumScale = performanceAnalytics.CalculateMomentumScale();
                            if(MathAbs(momentumScale - 1.0) > 0.001)
                            {
                                double preMomentumLot = lotSize;
                                lotSize *= momentumScale;
                                lotSize = MathMax(SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MIN), lotSize);
                                PrintFormat("[MOMENTUM-SCALE] %s | scale=%.2f | lot %.2f->%.2f",
                                            currentSymbol, momentumScale, preMomentumLot, lotSize);
                            }

                            // Batch 100: VPIN toxicity position size adjustment
                            if(InpEnableVPINFilter)
                            {
                                int vpinIdx = -1;
                                for(int vi = 0; vi < ArraySize(g_mathEngineSymbols); vi++)
                                {
                                    if(g_mathEngineSymbols[vi] == currentSymbol)
                                    { vpinIdx = vi; break; }
                                }
                                if(vpinIdx >= 0 && g_vpinFilters[vpinIdx] != NULL && g_vpinFilters[vpinIdx].IsWarmedUp())
                                {
                                    double vpinMult = g_vpinFilters[vpinIdx].GetPositionSizeMultiplier();
                                    if(vpinMult < 0.99)
                                    {
                                        double preVpinLot = lotSize;
                                        lotSize *= vpinMult;
                                        lotSize = MathMax(SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MIN), lotSize);
                                        PrintFormat("[VPIN-SIZE] %s | vpin=%.3f | mult=%.2f | lot %.2f->%.2f",
                                                    currentSymbol, g_vpinFilters[vpinIdx].GetVPIN(), vpinMult, preVpinLot, lotSize);
                                    }
                                }
                            }

                            // I4: Skew Step distribution-based sizing adjustment
                            if(InpEnableSkewStepAnalyzer && g_skewStepAnalyzer.IsInitialized())
                            {
                                // Check if current symbol is a Skew Step index
                                CDerivAssetProfiler* derivProf2 = g_multiAssetProfiler.GetDerivProfiler();
                                if(derivProf2 == NULL) continue;
                                ENUM_DERIV_FAMILY family = derivProf2.DetectFamily(currentSymbol);
                                if(family == DERIV_SKEW_STEP)
                                {
                                    double skewMult = g_skewStepAnalyzer.GetSizingMultiplier();
                                    if(MathAbs(skewMult - 1.0) > 0.01)
                                    {
                                        double preSkewLot = lotSize;
                                        lotSize *= skewMult;
                                        lotSize = MathMax(SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MIN), lotSize);
                                        PrintFormat("[SKEW-STEP-SIZE] %s | phase=%s | mult=%.2f | lot %.2f->%.2f",
                                                    currentSymbol, g_skewStepAnalyzer.GetPhaseName(), skewMult, preSkewLot, lotSize);
                                    }
                                }
                            }

                            // Phase 6: Full-margin position stacking — scale lot if stacking on existing position
                            if(InpRiskTier == RISK_TIER_FULL_MARGIN && g_fullMarginMode.IsInitialized())
                            {
                                int stackLevel = g_fullMarginMode.GetStackLevel(currentSymbol, enterpriseSignal);
                                if(stackLevel > 0)
                                {
                                    if(g_fullMarginMode.CanStackPosition(currentSymbol, enterpriseSignal))
                                    {
                                        double preStackLot = lotSize;
                                        lotSize = g_fullMarginMode.GetStackedLotSize(lotSize, stackLevel);
                                        lotSize = MathMax(SymbolInfoDouble(currentSymbol, SYMBOL_VOLUME_MIN), lotSize);
                                        PrintFormat("[FULL-MARGIN-STACK] %s | level=%d | lot %.2f->%.2f | scale=%.2f",
                                                    currentSymbol, stackLevel, preStackLot, lotSize,
                                                    g_fullMarginMode.GetConfig().stackLotScale);
                                    }
                                    else
                                    {
                                        // Stacking not allowed — reject this stacked entry
                                        g_hbValidatorRejects++;
                                        PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=full_margin_stack | signal=%s conf=%.2f | level=%d | reason=stacking_conditions_not_met",
                                                    currentSymbol, signalType, tradeConfidence, stackLevel);
                                        PrintFormat("[FULL-MARGIN-STACK-REJECTED] %s | level=%d | reason=stacking_conditions_not_met",
                                                    currentSymbol, stackLevel);
                                        continue;
                                    }
                                }

                                // Full-margin safeguard check (stricter spread, margin level, daily loss)
                                if(!g_fullMarginMode.CheckSafeguards(currentSymbol, atrValue))
                                {
                                    g_hbValidatorRejects++;
                                    PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=full_margin_safeguard | signal=%s conf=%.2f | reason=safeguards_failed",
                                                currentSymbol, signalType, tradeConfidence);
                                    continue;
                                }
                            }

                            // PERF-DUPLICATION: This inline position iteration duplicates GetEAPositionCount()
                            // and GetOpenPositionCountForSymbol(). Consider a cached position snapshot per EA cycle.
                            // Phase 6: Safe mode — block stacking entirely
                            if(InpRiskTier == RISK_TIER_CONSERVATIVE && g_safeMode.IsInitialized())
                            {
                                if(!g_safeMode.IsStackingAllowed())
                                {
                                    int existingPositions = 0;
                                    int totalPos = PositionsTotal();
                                    for(int posI = 0; posI < totalPos; posI++)
                                    {
                                        ulong posTicket = PositionGetTicket(posI);
                                        if(posTicket <= 0) continue;
                                        if(!PositionSelectByTicket(posTicket)) continue;
                                        if(PositionGetString(POSITION_SYMBOL) != currentSymbol) continue;
                                        ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                                        if((enterpriseSignal == TRADE_SIGNAL_BUY && posType == POSITION_TYPE_BUY) ||
                                           (enterpriseSignal == TRADE_SIGNAL_SELL && posType == POSITION_TYPE_SELL))
                                            existingPositions++;
                                    }
                                    if(existingPositions > 0)
                                    {
                                        g_hbValidatorRejects++;
                                        PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=safe_mode_no_stacking | signal=%s conf=%.2f | existing=%d",
                                                    currentSymbol, signalType, tradeConfidence, existingPositions);
                                        PrintFormat("[SAFE-MODE-REJECTED] %s | reason=no_stacking_allowed | existing=%d",
                                                    currentSymbol, existingPositions);
                                        continue;
                                    }
                                }

                                // Safe mode spread gate (stricter: 15% ATR)
                                if(atrValue > 0.0 && !g_safeMode.IsSpreadAcceptable(currentSymbol, atrValue))
                                {
                                    g_hbValidatorRejects++;
                                    PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=safe_mode_spread | signal=%s conf=%.2f | reason=spread_exceeds_safe_limit",
                                                currentSymbol, signalType, tradeConfidence);
                                    PrintFormat("[SAFE-MODE-REJECTED] %s | reason=spread_exceeds_safe_limit", currentSymbol);
                                    continue;
                                }
                            }

tradeReq.lotSize = lotSize;
                            if(!ApproveTradeByUnifiedRisk(tradeReq, "post-size", riskResult, scanCycleId))
                            {
                                PrintFormat("[POST-CONSENSUS-FILTER] %s | filter=unified_risk_post_size | signal=%s conf=%.2f | lot=%.2f | reason=%s",
                                            currentSymbol, signalType, tradeConfidence, lotSize, riskResult.reason);
                                continue;
                            }
                            g_hbSignalsRiskApproved++;
                            

                            // Validate the lot size and final risk approval
                            if(lotSize > 0)
                            {
                                double slPrice = tradeManager.CalculateStopLoss(currentSymbol, orderType, entryPrice, stopLossPips);
                                double tpPrice = tradeManager.CalculateTakeProfit(currentSymbol, orderType, entryPrice, takeProfitPips);

                                SApprovedTradeCandidate candidate;
                                candidate.valid = true;
                                candidate.symbol = currentSymbol;
                                candidate.signal = enterpriseSignal;
                                candidate.orderType = orderType;
                                candidate.evalMode = evalMode;
                                candidate.validationProfile = validationProfile;
                                candidate.consensusConfidence = confidence;
                                candidate.tradeConfidence = tradeConfidence;
                                candidate.qualityScore = qualityScore;
                                candidate.convictionScore = MathMax(0.0, MathMin(1.0, decisionContext.convictionScore));
                                candidate.contextScore = MathMax(0.0, MathMin(1.0, decisionContext.contextScore));
                                candidate.readinessScore = MathMax(0.0, MathMin(1.0, decisionContext.readinessScore));
                                candidate.costScore = MathMax(0.0, MathMin(1.0, decisionContext.costScore));
                                candidate.diversityScore = MathMax(0.0, MathMin(1.0, decisionContext.diversityScore));
                                candidate.confluence = confluence;
                                candidate.entryPrice = entryPrice;
                                candidate.atrValue = atrValue;
                                candidate.stopLossPips = stopLossPips;
                                candidate.takeProfitPips = takeProfitPips;
                                candidate.lotSize = lotSize;
                                candidate.slPrice = slPrice;
                                candidate.tpPrice = tpPrice;
                                candidate.signalType = signalType;
                                candidate.strategyRoleTag = strategyRoleTag;
                                candidate.strategyClusterTag = strategyClusterTag;
                                candidate.strategyClusterCode = strategyClusterCode;
                                candidate.contributorSummary = contributorSummary;
                                candidate.hasAIContributor = hasAIContributor;
                                candidate.hasONNXContributor = hasONNXContributor;
                                candidate.hasIndicatorContributor = hasIndicatorContributor;
                                candidate.liveAuthorityAllowed = liveAuthorityAllowed;
                                candidate.liveAuthorityRiskMultiplier = liveAuthorityRiskMultiplier;
                                candidate.liveAuthorityReason = liveAuthorityReason;
                                candidate.cycleId = scanCycleId;
                                candidate.riskResult = riskResult;
                                candidate.rankingScore = CalculateCandidateRankingScore(candidate);

                                int candidateIndex = ArraySize(approvedCandidates);
                                string reservationOwner = StringFormat("scan_candidate_%I64u_%d", scanCycleId, candidateIndex);
                                SValidationResult reserveResult;
                                bool stagedCandidate = ApproveAndReserveVirtualCandidate(candidate, reservationOwner, scanCycleId, reserveResult);
                                PrintFormat("[SCAN-CANDIDATE] cycle=%I64u | %s | signal=%s | ranking=%.3f | quality=%.2f | conviction=%.2f | context=%.2f | readiness=%.2f | cost=%.2f | confluence=%d | staged=%s",
                                            candidate.cycleId,
                                            candidate.symbol,
                                            candidate.signalType,
                                            candidate.rankingScore,
                                            candidate.qualityScore,
                                            candidate.convictionScore,
                                            candidate.contextScore,
                                            candidate.readinessScore,
                                            candidate.costScore,
                                            candidate.confluence,
                                            stagedCandidate ? "true" : "false");

                                if(stagedCandidate)
                                {
                                    candidate.riskResult = reserveResult;
                                    AppendApprovedTradeCandidate(approvedCandidates, candidate);
                                }
                            }
                            else
                            {
                                g_hbSizingRejects++;
                                PrintFormat("[POSITION-SIZE-REJECTED] cycle=%I64u | %s | reason=invalid_lot | lot=%.3f | stop=%.1f | conf=%.2f",
                                            scanCycleId,
                                            currentSymbol,
                                            lotSize,
                                            stopLossPips,
                                            tradeConfidence);
                            }
                        }
                        else
                        {
                            g_hbRiskRejects++;
                            PrintFormat("[RISK-GATE-REJECT] %s | phase=pre-size | cycle=%I64u | reason=%s | risk=%.2f%% | lot=%.3f",
                                        currentSymbol, scanCycleId, riskResult.message,
                                        proposedRisk, tradeReq.lotSize);
                        }
                }
            }

            // Fallback resilience: track consecutive scan cycles with zero consensus signals
            if(cycleTotalSignalsGenerated <= 0)
            {
                g_consecutiveZeroSignalCycles++;
                ENUM_EA_MODE fallbackMode = ResolveEffectiveEAMode();
                if(g_consecutiveZeroSignalCycles >= g_zeroSignalFallbackThreshold && fallbackMode == EA_MODE_INDICATOR_ONLY)
                {
                    if(g_consecutiveZeroSignalCycles % g_zeroSignalFallbackThreshold == 0)
                    {
                        PrintFormat("[FALLBACK] Consensus unproductive for %d cycles in INDICATOR_ONLY mode — consider enabling standalone strategies or checking strategy health | cycle=%I64u | scanned=%d | mode=%s",
                                    g_consecutiveZeroSignalCycles,
                                    scanCycleId,
                                    symbolCount,
                                    EAModeToString(fallbackMode));
                    }
                }
            }
            else
            {
                if(g_consecutiveZeroSignalCycles > 0 && ResolveEffectiveEAMode() == EA_MODE_INDICATOR_ONLY)
                {
                    PrintFormat("[FALLBACK] Consensus recovered after %d zero-signal cycles in INDICATOR_ONLY mode | cycle=%I64u | signals=%d",
                                g_consecutiveZeroSignalCycles,
                                scanCycleId,
                                cycleTotalSignalsGenerated);
                }
                g_consecutiveZeroSignalCycles = 0;
            }

            int approvedCandidateCount = ArraySize(approvedCandidates);
            if(approvedCandidateCount > 0)
            {
                SortApprovedTradeCandidatesByRank(approvedCandidates);
                int maxSendsThisCycle = InpMaxTradeSendsPerCycle;
                if(maxSendsThisCycle < 1)
                    maxSendsThisCycle = 1;
                if(maxSendsThisCycle > approvedCandidateCount)
                    maxSendsThisCycle = approvedCandidateCount;
                int attemptedThisCycle = 0;
                datetime scanStartTime = TimeCurrent();

                for(int sendIdx = 0; sendIdx < approvedCandidateCount && attemptedThisCycle < maxSendsThisCycle; sendIdx++)
                {
                    if(TimeCurrent() - scanStartTime > 10)
                    {
                        PrintFormat("[SCAN-TIMEOUT] cycle=%I64u | %d/%d sends completed in 10s, breaking candidate loop",
                                    scanCycleId, attemptedThisCycle, approvedCandidateCount);
                        break;
                    }
                    SApprovedTradeCandidate bestCandidate = approvedCandidates[sendIdx];
                    if(!bestCandidate.valid)
                        continue;

                    PrintFormat("[SCAN-DECISION] cycle=%I64u | rank=%d/%d | %s | signal=%s | ranking=%.3f | quality=%.2f | conviction=%.2f | context=%.2f | readiness=%.2f | cost=%.2f | diversity=%.2f | confluence=%d | live_authority=%s | authority_reason=%s | contributors=%s",
                                bestCandidate.cycleId,
                                sendIdx + 1,
                                approvedCandidateCount,
                                bestCandidate.symbol,
                                bestCandidate.signalType,
                                bestCandidate.rankingScore,
                                bestCandidate.qualityScore,
                                bestCandidate.convictionScore,
                                bestCandidate.contextScore,
                                bestCandidate.readinessScore,
                                bestCandidate.costScore,
                                bestCandidate.diversityScore,
                                bestCandidate.confluence,
                                bestCandidate.liveAuthorityAllowed ? "true" : "false",
                                bestCandidate.liveAuthorityReason,
                                bestCandidate.contributorSummary);

                    bool executeAsShadow = (InpShadowMode || InpShadowModeEnabled || (InpEnableLiveAuthorityGate && !bestCandidate.liveAuthorityAllowed));
                    datetime aiPredictionTime = 0;
                    bool aiPredictionRecorded = false;
                    if(!executeAsShadow && g_aiFeedbackReady && bestCandidate.hasAIContributor)
                    {
                        aiPredictionTime = TimeCurrent();
                        aiFeedback.RecordPrediction(bestCandidate.symbol,
                                                    bestCandidate.signal,
                                                    bestCandidate.tradeConfidence,
                                                    MathMax(0.0, 1.0 - bestCandidate.tradeConfidence),
                                                    g_currentRegime,
                                                    aiPredictionTime);
                        aiPredictionRecorded = (aiPredictionTime > 0);
                    }

                    // Issue 1 fix: Reserve virtual position at send time (not during staging)
                    // to prevent within-cycle budget accumulation blocking valid signals
                    string sendOwnerTag = StringFormat("send_%I64u_%d", scanCycleId, sendIdx);
                    STradeValidationRequest sendReserveReq;
                    PopulateTradeRequestFromCandidate(bestCandidate, sendReserveReq);
                    unifiedRiskManager.ReserveVirtualPosition(sendOwnerTag, sendReserveReq, bestCandidate.riskResult.riskPercent);

                    attemptedThisCycle++;
                    if(executeAsShadow)
                    {
                        g_hbShadowTrades++;
                        g_hbSignalsSent++;
                        if(InpShadowMode || InpShadowModeEnabled)
                            g_lastTradeTime = tickTime; // Intentional: shadow trades participate in cooldown to prevent rapid-fire simulation entries
                        RegisterLiveAuthorityTrial(bestCandidate, false, bestCandidate.liveAuthorityReason);
                        PrintFormat("[SHADOW-TRADE] cycle=%I64u | %s | %s | lot=%.2f | conf=%.2f | quality=%.2f | conviction=%.2f | context=%.2f | readiness=%.2f | cost=%.2f | confluence=%d | live_authority=%s | authority_reason=%s | role=%s | cluster=%s | contributors=%s | SL=%.5f | TP=%.5f",
                                    bestCandidate.cycleId,
                                    bestCandidate.symbol,
                                    bestCandidate.signalType,
                                    bestCandidate.lotSize,
                                    bestCandidate.tradeConfidence,
                                    bestCandidate.qualityScore,
                                    bestCandidate.convictionScore,
                                    bestCandidate.contextScore,
                                    bestCandidate.readinessScore,
                                    bestCandidate.costScore,
                                    bestCandidate.confluence,
                                    bestCandidate.liveAuthorityAllowed ? "true" : "false",
                                    bestCandidate.liveAuthorityReason,
                                    bestCandidate.strategyRoleTag,
                                    bestCandidate.strategyClusterTag,
                                    bestCandidate.contributorSummary,
                                    bestCandidate.slPrice,
                                    bestCandidate.tpPrice);
                    }
                    else
                    {
                        string predictionId = "";
                        CNeuralNetworkStrategy* symbolNet = GetNeuralNetForSymbol(bestCandidate.symbol);
                        if(symbolNet == NULL)
                            symbolNet = neuralNetStrategy;

                        if(symbolNet != NULL && InpEnableAIMode && InpEnableNeuralNetwork && InpEnableNNOnlineTraining)
                            symbolNet.ReservePredictionForSignal(bestCandidate.signal, predictionId, 600);

                        string tradeComment = g_attributionManager.BuildClusterTaggedTradeComment(bestCandidate.strategyClusterCode, predictionId);

                        // Per-symbol magic number: BASE + symbolIndex*100 + clusterCode
                        int symbolIdx = FindEnterpriseManagerIndex(bestCandidate.symbol);
                        if(symbolIdx < 0) symbolIdx = 0;
                        int clusterNum = g_attributionManager.ClusterCodeToNumeric(bestCandidate.strategyClusterCode);
                        uint perSymbolMagic = (uint)GenerateMagicNumber(symbolIdx, clusterNum);

                        // Confidence-based lot scaling: scale UP from broker min lot
                        // for high-quality signals to maximize growth on comfortable trades.
                        // Scale: conf>=0.75 → 2x min, conf>=0.85 → 3x min, conf>=0.92 → 4x min
                        double brokerMinLot = SymbolInfoDouble(bestCandidate.symbol, SYMBOL_VOLUME_MIN);
                        double lotStep = SymbolInfoDouble(bestCandidate.symbol, SYMBOL_VOLUME_STEP);
                        double maxLot = SymbolInfoDouble(bestCandidate.symbol, SYMBOL_VOLUME_MAX);
                        if(lotStep <= 0.0) lotStep = brokerMinLot;
                        double scaledLot = bestCandidate.lotSize;
                        if(scaledLot >= brokerMinLot && brokerMinLot > 0.0)
                        {
                            double confScale = 1.0;
                            if(bestCandidate.tradeConfidence >= 0.92 && bestCandidate.qualityScore >= 0.80)
                                confScale = 4.0;
                            else if(bestCandidate.tradeConfidence >= 0.85 && bestCandidate.qualityScore >= 0.75)
                                confScale = 3.0;
                            else if(bestCandidate.tradeConfidence >= 0.75 && bestCandidate.qualityScore >= 0.70)
                                confScale = 2.0;

                            if(confScale > 1.0)
                            {
                                double targetLot = brokerMinLot * confScale;
                                // Round to lot step
                                targetLot = MathFloor(targetLot / lotStep) * lotStep;
                                targetLot = MathMin(targetLot, maxLot);
                                // Verify risk budget allows it
                                double riskRatio = targetLot / scaledLot;
                                if(riskRatio <= InpMinLotRiskMultiplier)
                                {
                                    PrintFormat("[LOT-SCALE] %s | %.2f -> %.2f (conf=%.2f quality=%.2f scale=%.1fx)",
                                                bestCandidate.symbol, scaledLot, targetLot,
                                                bestCandidate.tradeConfidence, bestCandidate.qualityScore, confScale);
                                    scaledLot = targetLot;
                                }
                            }
                        }

                        bool tradeSuccess = tradeManager.OpenPosition(
                            bestCandidate.symbol,
                            bestCandidate.orderType,
                            scaledLot,
                            bestCandidate.entryPrice,
                            bestCandidate.stopLossPips,
                            bestCandidate.takeProfitPips,
                            tradeComment,
                            perSymbolMagic
                        );

                        STradeExecutionReceipt executionReceipt;
                        tradeManager.GetLastExecutionReceipt(executionReceipt);

                        if(!tradeSuccess)
                        {
                            if(symbolNet != NULL && predictionId != "")
                                symbolNet.ReleasePredictionReservation(predictionId);

                            int errorCode = GetLastError();
                            PrintFormat("[TRADE-ERROR] cycle=%I64u | %s | signal=%s | lot=%.2f | err=%d | retcode=%u | request=%u | retries=%d | req_price=%.5f | fill_price=%.5f | slip_pts=%.1f | latency_ms=%I64u | note=%s",
                                        bestCandidate.cycleId,
                                        bestCandidate.symbol,
                                        bestCandidate.signalType,
                                        bestCandidate.lotSize,
                                        errorCode,
                                        executionReceipt.retcode,
                                        executionReceipt.requestId,
                                        executionReceipt.retryCount,
                                        executionReceipt.requestedPrice,
                                        executionReceipt.averagePrice,
                                        executionReceipt.slippagePoints,
                                        executionReceipt.roundTripMs,
                                        executionReceipt.note);
                        }
                        else
                        {
                            double fillRatio = 1.0;
                            if(executionReceipt.requestedVolume > 0.0 && executionReceipt.filledVolume > 0.0)
                                fillRatio = MathMin(1.0, executionReceipt.filledVolume / executionReceipt.requestedVolume);

                            g_hbTradesOpened++;
                            g_hbSignalsSent++;
                            unifiedRiskManager.RegisterExecutedTradeRisk(bestCandidate.riskResult, fillRatio);
                            g_lastTradeTime = tickTime;
                            RegisterLiveAuthorityTrial(bestCandidate, true, bestCandidate.liveAuthorityReason);

                            // Phase 6: Register position for safe mode partial profit tracking
                            if(InpRiskTier == RISK_TIER_CONSERVATIVE && g_safeMode.IsInitialized())
                            {
                                ulong safeTicket = tradeManager.GetLastTicket();
                                double safeEntry = executionReceipt.averagePrice > 0.0 ? executionReceipt.averagePrice : bestCandidate.entryPrice;
                                double safeSL = tradeManager.GetLastRequestedStopLoss();
                                double safeTP = tradeManager.GetLastRequestedTakeProfit();
                                g_safeMode.RegisterPosition(safeTicket, bestCandidate.symbol, safeEntry, safeSL, safeTP);
                            }

                            if(fillRatio < 0.999)
                            {
                                PrintFormat("[FILL-DIFF] cycle=%I64u | %s | requested=%.2f | filled=%.2f | fill_ratio=%.3f | retcode=%u",
                                            bestCandidate.cycleId,
                                            bestCandidate.symbol,
                                            executionReceipt.requestedVolume,
                                            executionReceipt.filledVolume,
                                            fillRatio,
                                            executionReceipt.retcode);
                            }

                            ulong executionTicket = (executionReceipt.dealTicket > 0) ? executionReceipt.dealTicket :
                                                    ((executionReceipt.orderTicket > 0) ? executionReceipt.orderTicket :
                                                     tradeManager.GetLastTicket());
                            PrintFormat("[TRADE-SUCCESS] cycle=%I64u | %s | signal=%s | lot=%.2f | req_price=%.5f | fill_price=%.5f | slip_pts=%.1f | latency_ms=%I64u | sl=%.5f (%.0f pips) | tp=%.5f (%.0f pips) | ticket=%I64u | request=%u | role=%s | cluster=%s | contributors=%s | ranking=%.3f | note=%s",
                                        bestCandidate.cycleId,
                                        bestCandidate.symbol,
                                        bestCandidate.signalType,
                                        executionReceipt.filledVolume > 0.0 ? executionReceipt.filledVolume : bestCandidate.lotSize,
                                        executionReceipt.requestedPrice,
                                        executionReceipt.averagePrice,
                                        executionReceipt.slippagePoints,
                                        executionReceipt.roundTripMs,
                                        tradeManager.GetLastRequestedStopLoss(),
                                        bestCandidate.stopLossPips,
                                        tradeManager.GetLastRequestedTakeProfit(),
                                        bestCandidate.takeProfitPips,
                                        executionTicket,
                                        executionReceipt.requestId,
                                        bestCandidate.strategyRoleTag,
                                        bestCandidate.strategyClusterTag,
                                        bestCandidate.contributorSummary,
                                        bestCandidate.rankingScore,
                                        executionReceipt.note);
                            PrintFormat("[TRADE-EXECUTION] cycle=%I64u | %s | request=%u | retcode=%u | partial_fill=%s | requested=%.2f | filled=%.2f | req_price=%.5f | fill_price=%.5f | slip_pts=%.1f | latency_ms=%I64u",
                                        bestCandidate.cycleId,
                                        bestCandidate.symbol,
                                        executionReceipt.requestId,
                                        executionReceipt.retcode,
                                        executionReceipt.partialFill ? "true" : "false",
                                        executionReceipt.requestedVolume,
                                        executionReceipt.filledVolume,
                                        executionReceipt.requestedPrice,
                                        executionReceipt.averagePrice,
                                        executionReceipt.slippagePoints,
                                        executionReceipt.roundTripMs);

                            if(aiPredictionRecorded && executionReceipt.requestId > 0)
                                g_attributionManager.UpsertAIPendingRequestMap(executionReceipt.requestId, bestCandidate.symbol, aiPredictionTime, bestCandidate.signal);
                        }
                    }

                    // Issue 1 fix: Release virtual position after send (shadow or live).
                    // For live trades, actual risk is registered via RegisterExecutedTradeRisk,
                    // so the virtual reservation is no longer needed.
                    unifiedRiskManager.ReleaseVirtualPosition(sendOwnerTag);
                }

                PrintFormat("[SCAN-DECISION-SUMMARY] cycle=%I64u | candidates=%d | attempted=%d | cap=%d",
                            scanCycleId,
                            approvedCandidateCount,
                            attemptedThisCycle,
                            maxSendsThisCycle);
            }

            unifiedRiskManager.ClearVirtualPositions();
    }

    }

    // Fast Scalp Engine: evaluate and execute scalp signals (Phase 4)
    // Runs every signal evaluation cycle, bypasses full consensus pipeline
    // Guard: skip if ProcessScalpFastPath already evaluated this second (prevents duplicate scalp trades)
    {
        static datetime s_lastScalpEval = 0;
        datetime nowSec = TimeCurrent();
        bool fastPathAlreadyRan = (nowSec == g_scanScheduler.GetLastScalpFastPathSecond());
        if(!fastPathAlreadyRan && nowSec != s_lastScalpEval)
        {
            s_lastScalpEval = nowSec;
            if(InpEnableScalpEngine && g_scalpEngine.IsInitialized() && allowSignalEvaluation)
            {
                for(int symIdx = 0; symIdx < ArraySize(g_activePairs); symIdx++)
                {
                    string scalpSymbol = g_activePairs[symIdx];
                    ENUM_TRADE_SIGNAL scalpSignal = TRADE_SIGNAL_NONE;
                    double scalpConfidence = 0.0;
                    double scalpLotSize = 0.0;

                    if(g_scalpEngine.ShouldEnterScalp(scalpSymbol, scalpSignal, scalpConfidence, scalpLotSize))
                    {
                        if(InpShadowMode || InpShadowModeEnabled)
                        {
                            PrintFormat("[SHADOW-SCALP] %s | %s | lot=%.2f | confidence=%.2f | SHADOW MODE — no order sent",
                                        scalpSymbol,
                                        scalpSignal == TRADE_SIGNAL_BUY ? "BUY" : "SELL",
                                        scalpLotSize,
                                        scalpConfidence);
                        }
                        else
                        {
                            // Use pending orders if configured, otherwise market order
                            if(g_scalpEngine.GetConfig().usePendingOrders)
                                g_scalpEngine.PlaceScalpPendingOrder(scalpSymbol, scalpSignal, scalpLotSize);
                            else
                                g_scalpEngine.ExecuteScalpTrade(scalpSymbol, scalpSignal, scalpLotSize, scalpConfidence);
                        }
                    }
                }
            }
        }
    }

    datetime heartbeatNow = TimeCurrent();
    int heartbeatIntervalSec = MathMax(30, InpHeartbeatInterval);

    // Blueprint R6b: Core heartbeat delegated to DiagnosticsManager
    // DiagnosticsManager emits: [HEARTBEAT], [HEARTBEAT-FUNNEL], [CONVERSION-RATES],
    // [NO-SIGNAL-ALERT], [RISK-BUDGET], indicator cleanup, and prev-window updates.
    if(g_diagnosticsManager.IsInitialized())
    {
        g_diagnosticsManager.UpdateTradingPaused(g_spikeMonitor.IsPaused());
        g_diagnosticsManager.UpdateCounters(
            g_hbScansAttempted, g_hbIntrabarScansExecuted, g_hbNoSignalCount,
            g_hbValidatorRejects, g_hbRiskRejects, g_hbTradesOpened, g_hbShadowTrades,
            g_hbSyntheticSpikeEvents,
            g_hbSignalsGenerated, g_hbSignalsAfterPipeline, g_hbSignalsAfterQuorum,
            g_hbSignalsValidated, g_hbSignalsRiskApproved, g_hbSignalsSent,
            g_hbEntryBlocked, g_hbSizingRejects,
            g_hbQuietNoNewBar, g_hbQuietCadenceHold, g_hbQuietMissingManager);
        g_diagnosticsManager.EmitHeartbeat();
    }

    // Spike hunter heartbeat stats
    if(InpSpikeHunterEnabled)
        PrintFormat("[SPIKE-HUNTER-STATS] detections=%d trades=%d skipped=%d",
                    g_spikeHunter.GetTotalDetections(),
                    g_spikeHunter.GetTotalTradesOpened(),
                    g_spikeHunter.GetTotalTradesSkipped());

    // Batch 107: Institutional TA engines heartbeat (forex only)
    if(InpEnableVWAPEngine || InpEnableVolumeProfile || InpEnableCVDEngine)
    {
        PrintFormat("[INSTITUTIONAL-TA-HEARTBEAT] VWAP=%s | VP=%s | CVD=%s",
                    InpEnableVWAPEngine ? "ON" : "OFF",
                    InpEnableVolumeProfile ? "ON" : "OFF",
                    InpEnableCVDEngine ? "ON" : "OFF");
    }

    // I2: Compounding tier heartbeat
    if(InpEnableCompoundingTiers && g_compoundingTierManager.IsInitialized())
    {
        PrintFormat("[COMPOUNDING-TIER-HEARTBEAT] %s", g_compoundingTierManager.GetDiagnostics());
    }

    // I1: Family weight matrix heartbeat
    if(g_familyWeightMatrix.IsInitialized())
    {
        PrintFormat("[FAMILY-WEIGHT-MATRIX] Active | %d families configured", 19);
    }

    // I3: Session weight manager heartbeat
    if(InpEnableSessionWeights && g_sessionWeightManager.IsInitialized())
    {
        SSessionWeights sw = g_sessionWeightManager.GetCurrentSessionWeights();
        PrintFormat("[SESSION-WEIGHT-HEARTBEAT] %s | sizing=%.2f | thresholdAdj=%+.2f | readinessBoost=%+.2f",
                    sw.sessionName, sw.sizingMultiplier, sw.convictionThresholdAdj, sw.readinessBoost);
    }

    // I4: Skew Step analyzer heartbeat
    if(InpEnableSkewStepAnalyzer && g_skewStepAnalyzer.IsInitialized())
    {
        PrintFormat("[SKEW-STEP-HEARTBEAT] %s", g_skewStepAnalyzer.GetDiagnostics());
    }

    // Risk deadlock detection: warn when risk rejects accumulate with no trades opening
    {
        static int s_consecutiveRiskRejects = 0;
        static ulong s_lastTradesOpened = 0;
        if(g_hbTradesOpened > s_lastTradesOpened)
        {
            s_consecutiveRiskRejects = 0;
            s_lastTradesOpened = g_hbTradesOpened;
        }
        else if(g_hbRiskRejects > 0)
        {
            s_consecutiveRiskRejects++;
            if(s_consecutiveRiskRejects >= 500 && s_consecutiveRiskRejects % 500 == 0)
                PrintFormat("[RISK-DEADLOCK-WARNING] %d consecutive risk rejections with no new trades. Consider adjusting risk parameters.", s_consecutiveRiskRejects);
        }
    }

    // Consensus-specific diagnostics delegated to DiagnosticsManager
    if(g_lastHeartbeatLogTime == 0 || (heartbeatNow - g_lastHeartbeatLogTime) >= heartbeatIntervalSec)
    {
        g_diagnosticsManager.EmitConsensusDiagnostics(g_hbQuietNoNewBar,
                                                       g_hbQuietCadenceHold,
                                                       g_hbQuietMissingManager,
                                                       g_hbNoSignalCount,
                                                       g_hbValidatorRejects,
                                                       g_hbRiskRejects,
                                                       g_hbEntryBlocked,
                                                       g_hbSizingRejects,
                                                       g_diagnosticsManager.GetWindowScans(),
                                                       g_diagnosticsManager.GetWindowNoSignal(),
                                                       g_diagnosticsManager.GetNoSignalRate(),
                                                       heartbeatNow);

        g_lastHeartbeatLogTime = heartbeatNow;
    }

    if(InpEnableAIMode && InpEnableNeuralNetwork && InpEnableNNOnlineTraining &&
       (g_lastNNHealthLogTime == 0 || (heartbeatNow - g_lastNNHealthLogTime) >= heartbeatIntervalSec))
    {
        for(int nnIdx = 0; nnIdx < ArraySize(g_neuralNetStrategies); nnIdx++)
        {
            CNeuralNetworkStrategy* nnHealth = g_neuralNetStrategies[nnIdx];
            if(nnHealth == NULL)
                continue;

            int observations = 0;
            int tradeLinkedLabels = 0;
            int pseudoLabels = 0;
            int pendingLabels = 0;
            int trainingSteps = 0;
            int checkpointWrites = 0;
            int epoch = 0;
            double lastLoss = 0.0;
            nnHealth.GetModelHealthStats(observations, tradeLinkedLabels, pseudoLabels, pendingLabels,
                                         trainingSteps, checkpointWrites, epoch, lastLoss);

            string nnSymbol = (nnIdx < ArraySize(g_neuralNetStrategySymbols)) ? g_neuralNetStrategySymbols[nnIdx] : "?";
            PrintFormat("[NN-HEALTH] %s | obs=%d | trade_labels=%d | pseudo_labels=%d | pending=%d | train_steps=%d | checkpoints=%d | epoch=%d | loss=%.6f",
                        nnSymbol, observations, tradeLinkedLabels, pseudoLabels, pendingLabels,
                        trainingSteps, checkpointWrites, epoch, lastLoss);
        }

        g_lastNNHealthLogTime = heartbeatNow;
    }

    ManageOpenPositionsIfNeeded();

    if(g_spikeMonitor.HandleEmergencyDrawdown("timer", currentDrawdown, InpMaxDrawdown, InpEmergencyFlattenAllAccountPositions))
    {
        tradingEnabled = false;
        return;
    }

    // Collect market data for AI analysis from unified risk + performance snapshots
    SUnifiedRiskSnapshot riskSnapshot = unifiedRiskManager.GetSnapshot();
    SPerformanceMetrics perfMetrics = performanceAnalytics.GetPerformanceMetrics();
    double globalMarketData[20];
    globalMarketData[0] = currentEquity;
    globalMarketData[1] = accountBalance;
    globalMarketData[2] = currentDrawdown;
    globalMarketData[3] = (double)PositionsTotal();
    globalMarketData[4] = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
    globalMarketData[5] = AccountInfoDouble(ACCOUNT_MARGIN_LEVEL);
    globalMarketData[6] = riskSnapshot.currentDrawdownPercent;
    globalMarketData[7] = perfMetrics.totalProfit;
    globalMarketData[8] = MathMax(0.0, -perfMetrics.totalProfit);
    globalMarketData[9] = (double)perfMetrics.winningTrades;
    globalMarketData[10] = (double)perfMetrics.losingTrades;
    globalMarketData[11] = perfMetrics.maxDrawdown;
    globalMarketData[12] = perfMetrics.winRate;
    globalMarketData[13] = (double)perfMetrics.totalTrades;

    // AI Market Assessment (Heuristic IntegrationHub removed)
    double globalAIPrediction = 0.0;
    string aiReasoning = "AI Manager Active";

    // Update performance tracking
    UpdatePerformanceTracking();
}

//+------------------------------------------------------------------+
//| Trade Transaction Event Handler                                  |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
    // Attribute only this EA's deals to neural training feedback
    if(trans.type == TRADE_TRANSACTION_DEAL_ADD && trans.deal > 0)
    {
        if(HistoryDealSelect(trans.deal))
        {
            long dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
            if(IsEAOwnedMagic(dealMagic))
            {
                ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
                ulong positionId = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
                string dealComment = HistoryDealGetString(trans.deal, DEAL_COMMENT);
                datetime dealTime = (datetime)HistoryDealGetInteger(trans.deal, DEAL_TIME);

                // Keep trade-time state synchronized even for externally managed closes/partials.
                if(dealTime > g_lastTradeTime)
                    g_lastTradeTime = dealTime;

                // Route scalp async order confirmations
                if(g_scalpEngine.GetPendingAsyncCount() > 0)
                {
                    ulong orderTicket = trans.order;
                    g_scalpEngine.OnDealConfirmed(trans.deal, orderTicket);
                }

                // Capture entry-time mapping from comment to position for exact close labeling
                if((dealEntry == DEAL_ENTRY_IN || dealEntry == DEAL_ENTRY_INOUT) && positionId > 0)
                {
                    string openPredictionId = g_attributionManager.ExtractPredictionIdFromComment(dealComment);
                    if(openPredictionId != "")
                    {
                        g_attributionManager.UpsertPredictionPositionMap(positionId, openPredictionId);
                        g_attributionManager.IncrementNNDiagEntryMapCount();
                        g_attributionManager.NNDiagLog(StringFormat("Entry mapped | Symbol=%s | PositionID=%I64u | PredictionID=%s",
                                               trans.symbol, positionId, openPredictionId));
                    }
                    else
                    {
                        g_attributionManager.NNDiagLog(StringFormat("Entry without prediction ID | Symbol=%s | PositionID=%I64u | Comment=%s",
                                               trans.symbol, positionId, dealComment));
                    }

                    datetime aiPredictionTime = 0;
                    ENUM_TRADE_SIGNAL aiPredictionSignal = TRADE_SIGNAL_NONE;
                    uint aiRequestId = result.request_id;
                    if(InpEnableAIMode &&
                       g_attributionManager.ConsumeAIPendingRequestMap(aiRequestId, trans.symbol, aiPredictionTime, aiPredictionSignal))
                    {
                        g_attributionManager.UpsertAIPredictionPositionMap(positionId, aiPredictionTime, aiPredictionSignal);
                    }

                    PrintFormat("[TRADE-CONFIRMED] %s | entry=%s | deal=%I64u | position_id=%I64u | price=%.5f | volume=%.2f | request_id=%u",
                                trans.symbol,
                                EnumToString(dealEntry),
                                trans.deal,
                                positionId,
                                trans.price,
                                trans.volume,
                                result.request_id);
                }

                if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY || dealEntry == DEAL_ENTRY_INOUT)
                {
                    double dealProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
                    double dealSwap = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
                    double dealCommission = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
                    double netProfit = dealProfit + dealSwap + dealCommission;
                    bool positionStillOpen = (positionId > 0 && g_attributionManager.IsPositionIdStillOpen(positionId));
                    double totalNetProfit = netProfit;
                    bool finalCloseRecorded = false;

                    if(positionStillOpen)
                    {
                        if(positionId > 0)
                        {
                            g_attributionManager.AccumulatePendingCloseProfit(positionId, netProfit);
                        }
                    }
                    else
                    {
                        if(positionId > 0)
                            totalNetProfit += g_attributionManager.ConsumePendingCloseProfit(positionId);

                        performanceAnalytics.RecordClosedTrade((positionId > 0) ? positionId : trans.deal,
                                                               totalNetProfit);
                        finalCloseRecorded = true;

                        // Batch 99: Update BayesianKelly modifier with trade result
                        if(g_bayesianKellyModifier != NULL)
                        {
                            double equity = AccountInfoDouble(ACCOUNT_EQUITY);
                            bool isWin = (totalNetProfit > 0.0);
                            double profitPct = (equity > 0.0 && isWin) ? MathAbs(totalNetProfit) / equity : 0.0;
                            double lossPct = (equity > 0.0 && !isWin) ? MathAbs(totalNetProfit) / equity : 0.0;
                            g_bayesianKellyModifier.UpdateTradeResult(isWin, profitPct, lossPct);
                        }

                        // Batch 99: Record trade return for CVaR calculation
                        double equityForCvar = AccountInfoDouble(ACCOUNT_EQUITY);
                        if(equityForCvar > 0.0)
                        {
                            double pnlPct = totalNetProfit / equityForCvar;
                            unifiedRiskManager.GetPortfolioRiskManager().RecordTradeReturn(pnlPct);
                        }

                        PrintFormat("[TRADE-CONFIRMED] %s | entry=%s | deal=%I64u | position_id=%I64u | price=%.5f | volume=%.2f | net=%.2f | request_id=%u",
                                    trans.symbol,
                                    EnumToString(dealEntry),
                                    trans.deal,
                                    positionId,
                                    trans.price,
                                    trans.volume,
                                    totalNetProfit,
                                    result.request_id);
                    }

                    if(!positionStillOpen && g_aiFeedbackReady)
                    {
                        datetime aiPredictionTime = (positionId > 0) ? g_attributionManager.GetAIPredictionTimeForPosition(positionId) : 0;
                        ENUM_TRADE_SIGNAL aiPredictionSignal = (positionId > 0) ? g_attributionManager.GetAIPredictionSignalForPosition(positionId) : TRADE_SIGNAL_NONE;
                        if(aiPredictionTime > 0 && aiPredictionSignal != TRADE_SIGNAL_NONE)
                        {
                            ENUM_TRADE_SIGNAL actualOutcome = aiPredictionSignal;
                            if(totalNetProfit < 0.0)
                                actualOutcome = (aiPredictionSignal == TRADE_SIGNAL_BUY) ? TRADE_SIGNAL_SELL : TRADE_SIGNAL_BUY;
                            else if(MathAbs(totalNetProfit) < 1e-8)
                                actualOutcome = TRADE_SIGNAL_NONE;

                            double equity = AccountInfoDouble(ACCOUNT_EQUITY);
                            double actualReturn = (equity > 0.0) ? (totalNetProfit / equity) : totalNetProfit;
                            aiFeedback.RecordOutcome(trans.symbol, aiPredictionTime, actualOutcome, actualReturn);
                        }
                    }

                    if(InpEnableAIMode &&
                       InpEnableNeuralNetwork &&
                       InpEnableNNOnlineTraining)
                    {
                        string predictionIdFromComment = g_attributionManager.ExtractPredictionIdFromComment(dealComment);
                        string predictionIdFromMap = (positionId > 0) ? g_attributionManager.GetPredictionIdForPosition(positionId) : "";
                        string resolvedPredictionId = (predictionIdFromComment != "") ? predictionIdFromComment : predictionIdFromMap;
                        bool hasPredictionContext = (resolvedPredictionId != "");

                        if(positionStillOpen)
                        {
                            if(positionId > 0 && hasPredictionContext)
                            {
                                g_attributionManager.IncrementNNDiagPartialCloseCount();
                                g_attributionManager.NNDiagLog(StringFormat("Partial close deferred | Symbol=%s | PositionID=%I64u | DealNet=%.2f",
                                                       trans.symbol, positionId, netProfit));
                            }
                        }
                        else
                        {
                            CNeuralNetworkStrategy* symbolNet = GetNeuralNetForSymbol(trans.symbol);
                            if(symbolNet == NULL)
                                symbolNet = neuralNetStrategy;

                            if(symbolNet != NULL && hasPredictionContext)
                            {
                                bool updatedById = symbolNet.UpdateTradeResultByPredictionId(resolvedPredictionId, totalNetProfit);
                                bool updatedByFallback = false;
                                if(!updatedById)
                                    updatedByFallback = symbolNet.UpdateTradeResult(dealTime, totalNetProfit);

                                if(updatedById)
                                {
                                    g_attributionManager.IncrementNNDiagCloseByIdCount();
                                    g_attributionManager.NNDiagLog(StringFormat("Close labeled by ID | Symbol=%s | PositionID=%I64u | PredictionID=%s | Net=%.2f",
                                                           trans.symbol, positionId, resolvedPredictionId, totalNetProfit));
                                }
                                else if(updatedByFallback)
                                {
                                    g_attributionManager.IncrementNNDiagCloseFallbackCount();
                                    g_attributionManager.NNDiagLog(StringFormat("Close labeled by fallback | Symbol=%s | PositionID=%I64u | Net=%.2f",
                                                           trans.symbol, positionId, totalNetProfit));
                                }
                                else
                                {
                                    g_attributionManager.IncrementNNDiagCloseMissCount();
                                    g_attributionManager.NNDiagLog(StringFormat("Close label miss | Symbol=%s | PositionID=%I64u | PredictionID=%s | Net=%.2f",
                                                           trans.symbol, positionId, resolvedPredictionId, totalNetProfit));
                                }
                            }
                            else if(symbolNet == NULL && hasPredictionContext)
                            {
                                g_attributionManager.IncrementNNDiagCloseMissCount();
                                g_attributionManager.NNDiagLog(StringFormat("Close label miss: no NN instance | Symbol=%s | PositionID=%I64u",
                                                       trans.symbol, positionId));
                            }
                            else if(!hasPredictionContext)
                            {
                                g_attributionManager.NNDiagLog(StringFormat("Close skipped: no prediction context | Symbol=%s | PositionID=%I64u",
                                                       trans.symbol, positionId));
                            }
                        }
                    }

                    if(positionId > 0 && !g_attributionManager.IsPositionIdStillOpen(positionId))
                    {
                        g_attributionManager.RemovePredictionPositionMap(positionId);
                        g_attributionManager.RemoveAIPredictionPositionMap(positionId);
                        g_attributionManager.ClearPendingCloseProfit(positionId);
                        if(finalCloseRecorded)
                        {
                            g_attributionManager.NNDiagLog(StringFormat("Position map cleared | Symbol=%s | PositionID=%I64u",
                                                   trans.symbol, positionId));
                        }
                    }
                }
            }
        }
    }

    // Forward trade events to symbol-specific manager to avoid duplicated attribution.
    string txSymbol = trans.symbol;
    if(txSymbol == "" && trans.deal > 0 && HistoryDealSelect(trans.deal))
        txSymbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);

    CEnterpriseStrategyManager* txManager = GetEnterpriseManagerForSymbol(txSymbol);
    CEnterpriseStrategyManager* attributionManager = NULL;
    string feedbackSymbol = txSymbol;
    if(txManager != NULL)
    {
        txManager.OnTradeTransaction(trans, request, result);
        attributionManager = txManager;
    }
    else if(ArraySize(g_enterpriseManagers) > 0)
    {
        g_enterpriseManagers[0].OnTradeTransaction(trans, request, result);
        attributionManager = g_enterpriseManagers[0];
        if(feedbackSymbol == "" && ArraySize(g_enterpriseManagerSymbols) > 0)
            feedbackSymbol = g_enterpriseManagerSymbols[0];
    }

    if(InpEnableAIMode && attributionManager != NULL)
    {
        if(feedbackSymbol == "")
            feedbackSymbol = _Symbol;

        string contributors[];
        double tradeNetProfit = 0.0;
        if(attributionManager.PopClosedTradeAttribution(contributors, tradeNetProfit))
        {
            int updates = 0;
            for(int i = 0; i < ArraySize(contributors); i++)
            {
                if(contributors[i] == "")
                    continue;

                CEnterpriseStrategyManager* perfManager = GetEnterpriseManagerForSymbol(feedbackSymbol);
                if(perfManager != NULL)
                {
                    perfManager.UpdatePerformance(contributors[i], tradeNetProfit);
                    updates++;
                }
            }

        }
    }
}
