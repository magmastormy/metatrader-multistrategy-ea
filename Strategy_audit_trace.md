# Strategy_audit_trace.md

## 0) Scope, Method, and Evidence Standard

### 0.1 Scope
This report audits strategy logic under `d:\TraeProjects\metatrader-multistrategy-ea\Strategies`.

**Audited top-level strategy modules (authoritative signal generators):**
- `Strategies\SimpleMomentumStrategy.mqh`
- `Strategies\StrategyTrend.mqh`
- `Strategies\StrategyCandlestick.mqh`
- `Strategies\StrategyFibonacci.mqh`
- `Strategies\StrategyElliottWaveEnhanced.mqh`
- `Strategies\StrategySupportResistance.mqh`
- `Strategies\StrategyUnifiedICT.mqh`

**Audited component engines used by top-level strategies (non-exhaustive, high-impact):**
- Candlesticks:
  - `Strategies\CandlestickFiles\CandleAnalyzer.mqh`
  - `Strategies\CandlestickFiles\PinBarDetector.mqh`
  - `Strategies\CandlestickFiles\EngulfingDetector.mqh`
- Fibonacci:
  - `Strategies\FibonacciFiles\FibSwingDetector.mqh`
  - `Strategies\FibonacciFiles\FibLevelsCalculator.mqh`
  - `Strategies\FibonacciFiles\FibConfirmation.mqh`
- Elliott wave:
  - `Strategies\ElliottWaveFiles\ZigZagFilter.mqh`
  - `Strategies\ElliottWaveFiles\WavePatternEngine.mqh`
- Harmonics (present as engines, no top-level strategy wrapper found in this repo snapshot):
  - `Strategies\HarmonicFiles\HarmonicPatternScanner.mqh`
  - `Strategies\HarmonicFiles\HarmonicConfirmation.mqh`
- Unified ICT/SMC:
  - `Strategies\UnifiedICTFiles\MarketStructureAnalyzer.mqh`
  - `Strategies\UnifiedICTFiles\AdvancedOrderBlocks.mqh`
  - `Strategies\UnifiedICTFiles\LiquidityDetector.mqh`
  - `Strategies\UnifiedICTFiles\ImbalanceDetector.mqh`
  - `Strategies\SMCFiles\KillZones.mqh`
  - `Strategies\SMCFiles\PremiumDiscount.mqh`
- S/R:
  - `Strategies\SupportResistanceFiles\SupportResistanceDetector.mqh`
  - `Strategies\SupportResistanceFiles\TrendlineDetector.mqh`
  - `Strategies\SupportResistanceFiles\SRTradingStrategies.mqh`

### 0.2 Evidence standard
All claims are tied to at least one of:
- **Code evidence**: exact file path + logic behavior.
- **Market mechanics reasoning**: microstructure constraints (spread, slippage, latency, stop distance rules).
- **External literature evidence** (when available through accessible sources):
  - Santa Fe Institute working paper summary for simple technical rules (moving average / range break):
    - https://www.santafe.edu/research/results/working-papers/simple-technical-trading-rules-and-the-stochastic-
  - Santa Fe Institute working paper summary on technical trading externalities (agent-based / prisoner’s dilemma framing):
    - https://www.santafe.edu/research/results/working-papers/technical-trading-creates-a-prisoners-dilemma-resu
  - RePEc entry for candlestick strategies paper (restricted full text; references list is accessible):
    - https://ideas.repec.org/a/eee/jbfina/v30y2006i8p2303-2323.html
  - Investopedia discussion of Fibonacci retracement limitations (subjectivity / self-fulfilling prophecy / regime fragility):
    - https://www.investopedia.com/terms/f/fibonacciretracement.asp
  - Wikipedia summary of Elliott Wave criticisms (subjectivity / non-replicability; includes cited quotes):
    - https://en.wikipedia.org/wiki/Elliott_wave_principle

### 0.3 Scoring model (0–100)
Each strategy gets the following scores:
- **Alpha Plausibility** (does the strategy encode a falsifiable mechanism likely to persist?)
- **Implementation Integrity** (correctness, determinism, avoidance of silent failure)
- **Statistical Defensibility** (data-snooping risk, degrees of freedom, parameter sensitivity)
- **Microstructure Survivability** (spread/slippage sensitivity, stop placement realism, execution timing)
- **Operational Risk** (runtime load, handle churn/leaks, statefulness pitfalls)

A single roll-up **Survivability Score** is then assigned (not an average; worst-link-weighted).

---

## 1) Strategy: Simple Momentum (EMA Crossover)

### 1.1 Identification
- **Code**: `Strategies\SimpleMomentumStrategy.mqh`
- **Strategy family**: momentum / trend-following (short-term EMA crossover) with volatility + trend filters.

### 1.2 Entry/Exit mechanics (code)
- **Signal trigger**:
  - Closed-bar EMA diff crossover:
    - Fetches EMA values using `CopyBuffer(..., shift=1..2)` in `FetchAverages()`.
    - Buy when `diffNow > threshold && diffPrev <= threshold`.
    - Sell when `diffNow < -threshold && diffPrev >= -threshold`.
- **Trend filter**:
  - 50 EMA vs price: computes `trendStrength` by scaling `(priceForTrend - trendMA)/trendMA` into `[0,1]`.
  - Buy requires `trendStrength >= m_minTrendStrength`.
  - Sell requires `trendStrength <= (1 - m_minTrendStrength)`.
- **Volatility filter**:
  - ATR(14) must exceed `m_minVolatility` (scaled by digits; special-cases digits<=3).
- **Throttle**:
  - Enforces per-symbol cooldown: `TimeCurrent() - m_lastSignalTimestamp < 60`.
  - In non-scalping mode: one signal per bar via `m_lastSignalBar`.

**Exit**: not owned by the strategy; upstream system sets SL/TP and lifecycle management.

### 1.3 Theoretical foundation (what would have to be true)
- For EMA crossovers to have persistent edge, market returns must exhibit exploitable trend persistence at the chosen horizon after costs.
- External reference: Brock, Lakonishok, LeBaron (SFI summary) reports historical evidence for simple technical rules not consistent with certain null models on long DJIA sample, but this does not guarantee persistence out-of-sample or after realistic execution costs.
  - https://www.santafe.edu/research/results/working-papers/simple-technical-trading-rules-and-the-stochastic-

### 1.4 Statistical integrity & overfitting risk
- **Degrees of freedom** (DoF):
  - `m_fastPeriod`, `m_slowPeriod`, `m_thresholdPoints`, `m_minTrendStrength`, `m_minVolatility`, plus optional scalping mode.
  - Each parameter is strongly interacting (threshold and volatility filter can gate almost all trades).
- **Hidden fragility**:
  - Trend strength computation is ad-hoc scaling (`*100.0`) and then clipped to `[0,1]`. This is not a standard estimator and risks becoming a brittle proxy that depends on price level (e.g., instruments with different decimal scales).
- **Data-snooping risk**:
  - EMA crossover strategies are historically heavily mined; any performance without a robust cost model is suspect.

### 1.5 Microstructure alignment
- Strengths:
  - Uses closed-bar signals (reduces intrabar repainting).
  - Enforces minimum time gap between signals.
- Weaknesses:
  - If upstream execution uses strict fill policies (e.g., FOK) or spread spikes, crossover edges are typically eaten by costs.
  - Threshold uses `point` scaling but still depends on symbol point size; for exotic symbols this can be a poor normalization.

### 1.6 Failure modes (how it dies)
- **Regime shift**: choppy mean-reverting regime => repeated whipsaws.
- **Volatility filter mismatch**: ATR threshold too high => strategy goes silent; too low => overtrades noise.
- **Execution drag**: spread widening around momentum bursts => systematic adverse selection.

### 1.7 Scores
- **Alpha Plausibility**: 45
- **Implementation Integrity**: 70
- **Statistical Defensibility**: 35
- **Microstructure Survivability**: 35
- **Operational Risk**: 60
- **Survivability Score**: 38

### 1.8 Institutional verdict
Retail-grade trend heuristic. Can be made useful only as a *feature* in a larger ensemble with strict cost modeling and regime gating; by itself it is not institutional alpha.

---

## 2) Strategy: Trend Strategy v2.0 (Multi-EMA + ADX)

### 2.1 Identification
- **Code**: `Strategies\StrategyTrend.mqh`
- **Strategy family**: trend following with multi-timescale EMA state machine and ADX gating.

### 2.2 Entry/Exit mechanics (code)
- Uses modular components:
  - `TrendFiles\MultiEMASystem.mqh` for EMA alignment and trend state.
  - `TrendFiles\TrendEntryTypes.mqh` for multiple entry archetypes.
  - `TrendFiles\ADXPositionSizing.mqh` for ADX-based trade gating and sizing multiplier.
  - `TrendFiles\TrendTrailingStop.mqh` for trailing stop suggestions.
- **Signal generation**:
  - Updates EMA system + entry engine.
  - Rejects trading if `m_adxSizing.ShouldTrade()` is false.
  - Picks `bestEntry = m_entryTypes.GetBestEntry()`.
  - Confidence is adjusted by ADX multiplier.
  - Applies minimum confidence threshold (`m_minConfidence` set to 0.55).

### 2.3 Theoretical foundation
- Trend following has a plausible economic story in some markets/timeframes (slow-moving risk premia, behavioral underreaction). However, retail implementations typically collapse under costs when traded at too-high frequency.
- External framing: technical trading can become self-reinforcing and add volatility/noise; if broadly adopted, aggregate wealth can be lower (agent-based prisoner’s dilemma framing).
  - https://www.santafe.edu/research/results/working-papers/technical-trading-creates-a-prisoners-dilemma-resu

### 2.4 Statistical integrity & overfitting risk
- **High DoF**: multiple EMAs (8/21/50/200) + multiple entry types + ADX thresholds/tiers + trailing logic. This is a large search space if optimized.
- **Entry type selection bias**: selecting “best entry” among several templates tends to inflate backtests unless selection is pre-registered and validated out-of-sample.

### 2.5 Microstructure alignment
- Strengths:
  - Uses higher-level state (trend alignment) + ADX to avoid ranging conditions.
- Weaknesses:
  - ADX is lagging; during transitions it can misclassify, producing late entries and exits.
  - Trailing stop suggestions can create churn if execution/modify throttles are present upstream.

### 2.6 Failure modes
- **Trend exhaustion / violent mean reversion**: trailing stops get clipped; strategy re-enters late.
- **ADX gating failure**: too strict => misses trends; too loose => overtrades in range.

### 2.7 Scores
- **Alpha Plausibility**: 55
- **Implementation Integrity**: 70
- **Statistical Defensibility**: 40
- **Microstructure Survivability**: 45
- **Operational Risk**: 55
- **Survivability Score**: 46

### 2.8 Institutional verdict
Most defensible “classic” strategy in the folder *if* cost model + regime validation is real. Still not institutional-grade without rigorous out-of-sample process.

---

## 3) Strategy: Candlestick Patterns (Pin Bar, Engulfing)

### 3.1 Identification
- **Code**: `Strategies\StrategyCandlestick.mqh`
- **Strategy family**: single-/two-candle reversal patterns filtered by EMA trend alignment.

### 3.2 Entry/Exit mechanics (code)
- **Signal priority**:
  - Pin bar first, then engulfing.
- **Pattern detection**:
  - Uses `PinBarDetector` and `EngulfingDetector` with ATR-scaled minimum range / strength scores.
- **Trend alignment**:
  - Optional, default enabled.
  - `CheckTrendAlignment()` creates EMA(50) and EMA(200) handles on each call; checks `ema50 > ema200` for bullish, opposite for bearish.
- **Risk model inside module**:
  - `CalculateStopLoss()` uses recent swing +/- small buffer; clamps if too far (ATR*3 constraint).
  - `CalculateTakeProfit()` uses fixed RR (2.5x).

### 3.3 External evidence & known critiques
- The RePEc entry for the main candlestick strategies paper is accessible but full text is restricted; however its reference list highlights the core methodological landmines for technical pattern claims, including explicit data-snooping/bootstrap literature.
  - https://ideas.repec.org/a/eee/jbfina/v30y2006i8p2303-2323.html
  - Notably listed: Sullivan, Timmermann & White (data-snooping and the bootstrap), plus Lo, Mamaysky & Wang (computational/statistical foundations of technical analysis).

### 3.4 Statistical integrity & overfitting risk
- **Pattern taxonomy mining**: candlestick pattern libraries are a classic data-mining trap. Even if a few patterns show apparent edge in-sample, multiple testing inflates false discovery.
- **Strength score risk**: detector “strength” is an internal heuristic; without a statistical calibration and out-of-sample performance monitoring, it becomes a curve-fitting knob.

### 3.5 Microstructure alignment
- Reversal patterns are highly sensitive to spread and stop placement:
  - Many pin/engulf signals are small-bodied relative to spread in FX/CFD environments.
- **Implementation concern**:
  - EMA handles are created/released on each signal evaluation. This is operationally heavy and can become brittle under multi-symbol/high-frequency evaluation.

### 3.6 Failure modes
- **Chop regime**: emits many reversals that are noise.
- **Volatility spikes**: ATR-based minimum range can allow larger “patterns” right when adverse selection is worst.

### 3.7 Scores
- **Alpha Plausibility**: 30
- **Implementation Integrity**: 55
- **Statistical Defensibility**: 25
- **Microstructure Survivability**: 25
- **Operational Risk**: 40
- **Survivability Score**: 28

### 3.8 Institutional verdict
High risk of being a storytelling layer over noise. If kept, should be demoted to a *secondary confirmation feature* behind a primary mechanism (structure/liquidity) and tested with strict multiple-testing controls.

---

## 4) Strategy: Fibonacci v2.0 (Swing + Fib levels + Confirmation)

### 4.1 Identification
- **Code**: `Strategies\StrategyFibonacci.mqh`
- **Family**: discretionary-technical tool formalized into an algorithm (swing selection + fib levels + confirmation).

### 4.2 Entry/Exit mechanics (code)
- Detect swings via `CFibSwingDetector`.
- Compute multiple fib setups via `CFibLevelsCalculator`.
- Chooses “best bullish else best bearish setup,” then uses **61.8%** (`setup.fib618`) as primary entry level.
- Requires confirmation from `CFibConfirmation` (candlestick patterns, momentum, RSI divergence).
- Confidence = `(setup.overallScore / 100) * confirm.strength`, with `m_minConfidence` gating.

### 4.3 External evidence & known critiques
- Accessible summary of common Fibonacci criticisms:
  - subjectivity of swing point selection
  - clustered levels produce ambiguity
  - regime dependence (trending works better; choppy unreliable)
  - self-fulfilling prophecy argument
  - https://www.investopedia.com/terms/f/fibonacciretracement.asp

### 4.4 Statistical integrity & overfitting risk
- **Primary risk**: swing selection is effectively the “model.” Slight changes to swing detection parameters change the entire level map.
- **Confirmation stacking** multiplies degrees of freedom:
  - fib level + candle pattern + divergence + trend filters => large combinatorial selection.

### 4.5 Microstructure alignment
- Fib entries tend to place limit/mean-reversion style entries into pullbacks; in real markets these are vulnerable to:
  - stop hunting / liquidity runs through the “level”
  - spread widening during pullback completion

### 4.6 Failure modes
- **Non-stationary swing geometry**: market changes volatility/structure, swing detector produces different regimes.
- **Clustering / ambiguity**: multiple nearby levels => unstable decision boundary.

### 4.7 Scores
- **Alpha Plausibility**: 25
- **Implementation Integrity**: 65
- **Statistical Defensibility**: 20
- **Microstructure Survivability**: 25
- **Operational Risk**: 55
- **Survivability Score**: 24

### 4.8 Institutional verdict
Not institutionally defensible as alpha. At best, fib levels can approximate *crowded discretionary reference points*; this is not a stable mechanism without explicit orderflow evidence.

---

## 5) Strategy: Elliott Wave Enhanced

### 5.1 Identification
- **Code**: `Strategies\StrategyElliottWaveEnhanced.mqh`
- **Family**: wave counting / fractal pattern narrative encoded as a swing-based rule system.

### 5.2 Entry mechanics (code)
- Builds swings from `CStructureEngine` plus direct pivot extraction from rates.
- Assigns waves 1..5 using the last 3–5 swings (explicitly relaxed).
- Generates signals even for partial patterns (waveCount 3 or 4) and for complete 5-wave patterns (reversal trade).
- Minimum confidence threshold lowered to **0.45** and patterns need as few as 2 swing highs and 2 swing lows.

### 5.3 External evidence & known critiques
- Elliott Wave’s dominant critique is **subjectivity / non-replicability**.
  - The Wikipedia summary includes directly quoted criticism that wave prediction is “an art” where subjective judgement dominates replicable numbers, and that the rules are loosely defined enough to fit almost any history (quoted via Aronson).
  - https://en.wikipedia.org/wiki/Elliott_wave_principle

### 5.4 Statistical integrity & overfitting risk
- Extremely high implicit DoF:
  - pivot detection parameters + windowing + tolerance + multi-timeframe confirmation + relaxed thresholds.
- The code relaxations specifically increase the number of “valid” patterns, which **increases false positives**.

### 5.5 Microstructure alignment
- Wave counting is typically a medium-horizon construct; algorithmic application at lower timeframes is vulnerable to noise and spread.
- The strategy is also computationally heavier than simple indicators.

### 5.6 Failure modes
- **Wave recounting instability**: small changes in last pivots re-label the entire wave structure.
- **Non-falsifiability in practice**: patterns can be “found” frequently; the strategy becomes a signal factory.

### 5.7 Scores
- **Alpha Plausibility**: 20
- **Implementation Integrity**: 60
- **Statistical Defensibility**: 10
- **Microstructure Survivability**: 20
- **Operational Risk**: 45
- **Survivability Score**: 18

### 5.8 Institutional verdict
This is a narrative fitting engine, not a falsifiable predictive model. The code’s relaxed validations move it further from any disciplined hypothesis test.

---

## 6) Strategy: Support/Resistance + Trendlines

### 6.1 Identification
- **Code**: `Strategies\StrategySupportResistance.mqh`
- **Family**: level/trendline detection with bounce/breakout templates.

### 6.2 Entry mechanics (code)
- Uses detectors to build level sets:
  - `SupportResistanceDetector` for swing/psychological/timeframe highs-lows clustering.
  - `TrendlineDetector` for trendline construction and break detection.
- Uses three sub-strategies:
  - `CSRBounceStrategy`
  - `CSRBreakoutStrategy`
  - `CTrendlineBounceStrategy`
- Picks best signal by highest confidence.

### 6.3 Statistical integrity
- S/R is often partially self-fulfilling (crowding), but translating it into rules requires choices about:
  - clustering distance
  - touch counting
  - what counts as rejection
  - what counts as breakout/retest
These choices are DoF and optimization magnets.

### 6.4 Microstructure alignment
- Breakouts in retail feed are notoriously sensitive to spread widening and stop hunting.
- Bounce entries require tight stops near levels; brokers’ stop-level constraints and slippage can destroy the risk model.

### 6.5 Failure modes
- **Level saturation**: too many levels => confidence inflation.
- **False breakout regime**: systematic stop-run then mean reversion.

### 6.6 Scores
- **Alpha Plausibility**: 35
- **Implementation Integrity**: 70
- **Statistical Defensibility**: 25
- **Microstructure Survivability**: 30
- **Operational Risk**: 55
- **Survivability Score**: 30

### 6.7 Institutional verdict
Not alpha on its own; can be used as an execution/entry *context layer* if driven by a primary, testable mechanism (e.g., volatility/flow regime).

---

## 7) Strategy: Unified ICT/SMC

### 7.1 Identification
- **Code**: `Strategies\StrategyUnifiedICT.mqh`
- **Family**: “smart money concepts” confluence system combining structure, order blocks, liquidity sweeps, FVG/imbalance, kill zones, premium/discount zones.

### 7.2 Mechanics (code)
- Multi-component updates are throttled to once per bar via `RefreshComponentsForCurrentBar()`.
- Directional bias is derived from `m_structureAnalyzer.IsBullish()/IsBearish()`; neutral/ambiguous rejects.
- Entry generation:
  - Constructs multiple entry templates (Risk / Justification / Risk+Just / Full Justification).
  - Enforces confluence count and confluence score thresholds (defaults: `m_minConfluences=4`, `m_minConfluenceScore=45`).
  - Validates “major POI” gating and candlestick rejection.
  - Optional counter-trend scout is allowed but gated.

### 7.3 Theoretical foundation (what must be true)
The only institutionally-legible core here is:
- **Market structure / liquidity / imbalance** can proxy orderflow / positioning constraints.

However, the ICT/SMC vocabulary (order blocks, FVG, kill zones, OTE) is mostly a *retail reinterpretation* of microstructure ideas. Without direct order book / trade tape evidence, these constructs can degrade into unfalsifiable pattern selection.

### 7.4 Statistical integrity & overfitting risk
- This is the highest DoF strategy:
  - multiple detectors + multiple timeframes + confluence counting + bonuses/penalties + optional counter-trend.
- “Confluence” systems commonly backtest well because they implicitly select rare, high-variance events (selection bias) and discard losses as “filtered out.”

### 7.5 Microstructure alignment
- Strength:
  - Attempt to encode liquidity sweeps and rebalancing concepts rather than pure indicators.
- Weakness:
  - Still based on OHLC heuristics; in fast markets the sweep/rejection logic can become a latency and spread tax.

### 7.6 Failure modes
- **Signal scarcity -> threshold relaxation**: if the rest of the system relaxes thresholds, this strategy can start firing on weaker setups.
- **Confluence illusion**: multiple correlated indicators on the same price series are not independent evidence.

### 7.7 Scores
- **Alpha Plausibility**: 45
- **Implementation Integrity**: 75
- **Statistical Defensibility**: 20
- **Microstructure Survivability**: 40
- **Operational Risk**: 50
- **Survivability Score**: 34

### 7.8 Institutional verdict
Best attempt at encoding “institutional” ideas, but it still lacks a falsifiable mechanism and relies on confluence heuristics. Without rigorous, pre-registered evaluation and cost/slippage modeling, it remains retail-grade complexity.

---

## 8) Harmonic pattern engines (component-only audit)

### 8.1 Identification
- **Code**:
  - `Strategies\HarmonicFiles\HarmonicPatternScanner.mqh`
  - `Strategies\HarmonicFiles\HarmonicConfirmation.mqh`

### 8.2 Mechanical critique (code)
- The scanner claims O(n) but operationally does:
  - detects swings using fixed-strength neighborhood comparisons.
  - selects the first alternating set of 5 swings that match (bullish and bearish), not an exhaustive search.
- **Time sequence validation appears internally inconsistent**:
  - `ValidateTimeSequence()` rejects when `barIndex >= previous.barIndex` with comment “Bar indices are reversed (0=current)”.
  - This can easily invalidate correct chronological sequences depending on how `barIndex` is assigned.

### 8.3 Statistical critique
- Harmonic ratios are a textbook example of curve-fit geometry: many ratio windows, tolerance choice, swing selection choice.

### 8.4 Scores (engine quality, not alpha)
- **Implementation Integrity**: 40
- **Statistical Defensibility**: 10
- **Operational Risk**: 55

### 8.5 Verdict
As implemented, this is not a reliable foundation for automated trading decisions.

---

## 9) Cross-strategy portfolio interactions (correlation & redundancy)

### 9.1 Redundancy clusters
- **Trend/momentum cluster**:
  - `SimpleMomentumStrategy` and `StrategyTrend` are highly correlated: both are EMA-based trend heuristics with volatility/trend gating.
- **Reversal confirmation cluster**:
  - Candlestick patterns, Fibonacci confirmation, and parts of Unified ICT share similar reversal confirmation logic (pin/engulf).
- **Level-based cluster**:
  - Support/Resistance, Fibonacci levels, Harmonic PRZ are all “levels on price” and thus highly correlated in drawdown.

### 9.2 Risk concentration modes
- When the market enters “liquidity sweep / stop run” behavior:
  - Level-based and reversal systems can all fire simultaneously, effectively stacking the same bet.

### 9.3 Survivability implication
The portfolio is not diversified by mechanism; it is diversified by *storytelling layer*. Many modules transform the same OHLC inputs into different narratives.

---

## 10) Final Institutional Verdict

### 10.1 What is structurally defensible
- The only category with long-run plausibility in principle is **trend-following** (Trend Strategy v2.0), provided trading horizon is not too short and costs are modeled correctly.

### 10.2 What is not institutionally defensible as alpha
- Elliott wave: non-replicable, subjective, high DoF.
- Fibonacci levels: swing-point subjectivity + self-fulfilling prophecy argument + regime fragility.
- Candlestick patterns: classic multiple-testing / data-snooping hazard.
- Harmonics: geometric curve-fit; implementation concerns.

### 10.3 Deployment recommendation
- **Do not deploy** these strategies as “institutional alpha.”
- If you deploy anything, the only candidate is **Trend Strategy v2.0**, and only under:
  - strict transaction cost + slippage modeling
  - out-of-sample regime validation
  - explicit max-trade-frequency governance
  - portfolio-level correlation gating (avoid stacking correlated signals)

### 10.4 Bottom line classification
- **Folder classification**: retail-pattern automation with some disciplined engineering, not institutional-grade research.
- **Overall strategy survivability**: low-to-moderate, dominated by DoF and microstructure fragility.

---

# Institutional Upgrade & Strategic Elevation Plan

## 1. Strategic Weakness Summary

- **Edge statements are not falsifiable**
  - Most modules describe “patterns” rather than specifying a measurable inefficiency tied to a conditional return distribution after costs.
- **Regime ignorance**
  - Strategies mix trend, mean reversion, and structure narratives without an explicit market-state classifier (volatility regime, trend state, liquidity session state).
- **Static thresholds and non-normalized decision boundaries**
  - Several thresholds are point-based or heuristic scores with limited ATR/volatility normalization.
- **Microstructure costs are not first-class constraints**
  - No explicit spread shock filters, tick-velocity filters, or “effective cost vs expected move” gating.
- **Over-parameterization without stability controls**
  - Multiple knobs (levels, confirmations, confluence counts) create high degrees of freedom with no stability corridor enforcement.
- **Portfolio-level risk concentration**
  - Many strategies are transformations of the same OHLC stream; without correlation-aware allocation, drawdowns cluster.

---

## 2. Institutional Redesign Framework

### Strategy: Simple Momentum (EMA Crossover) and Trend Strategy v2.0 (Multi-EMA + ADX)

#### A. Redefined Edge Thesis

- **Primary inefficiency**: trend persistence conditional on *volatility contraction → expansion* and *cost-of-trading viability*.
- **Mechanism statement**:
  - After a compression phase, breaks with aligned multi-horizon trend state exhibit higher continuation probability than baseline, provided spread/impact is small relative to expected excursion.
- **Institutional deployment requirement**:
  - The strategy must behave as a *conditional trend exposure engine* whose activation depends on measurable state (compression, expansion, spread) and whose exits are volatility-aware.

#### B. Required Structural Modifications

1. **Replace raw crossover with “state + trigger”**
   - State: multi-horizon alignment score `A`.
     - Compute EMAs: `emaFast`, `emaMid`, `emaSlow`, `emaLong`.
     - Alignment score (normalized):
       - Bull alignment: `A_bull = I(emaFast>emaMid) + I(emaMid>emaSlow) + I(emaSlow>emaLong)`.
       - Bear alignment: `A_bear = I(emaFast<emaMid) + I(emaMid<emaSlow) + I(emaSlow<emaLong)`.
     - Require `max(A_bull, A_bear) >= 3` for “trend-state valid”.
2. **Trigger: break from compression**
   - Define compression using ATR percentiles in a rolling window (MQL5 implementable via ring buffer):
     - Maintain `ATR14[t]` for last `N=200` bars.
     - Compute `p20 = Percentile(ATR14, 20%)` (approx: maintain sorted array or use selection algorithm on a copied buffer).
     - Compression flag `C = (ATR14_current <= p20)`.
   - Break trigger:
     - For bullish: close breaks above `DonchianHigh(L)` where `L=20` and `C` was true in last `K=10` bars.
     - For bearish: close breaks below `DonchianLow(L)`.
3. **Cost viability gate**
   - Estimate “effective spread in ATR units”:
     - `spreadPoints = (Ask-Bid)/_Point`.
     - `atrPoints = ATR14/_Point`.
     - Require `spreadPoints <= s_max * atrPoints` (e.g., `s_max=0.08`), otherwise reject.
4. **Mandatory “late entry avoidance”**
   - Reject breakouts if breakout candle range is an outlier and closes near extremes:
     - `range = High-Low`.
     - `rangeZ = (range - SMA(range, 50)) / Std(range, 50)`.
     - Reject if `rangeZ > 2.5` AND `Close` is in top/bottom 10% of range (chasing).

#### C. Regime Adaptation Layer

Define a regime classifier `R` returning one of: `TREND`, `RANGE`, `BREAKOUT`, `CHAOS`.

- **Volatility regime** (rolling):
  - `rv = SMA( (log(Close/Close[1]))^2 , 50 )` (realized variance proxy).
  - `rvLong = SMA( (log(Close/Close[1]))^2 , 200 )`.
  - Vol regime score `V = rv / max(rvLong, eps)`.
  - `V < 0.7` = low vol, `0.7–1.3` = normal, `>1.3` = high.
- **Trend state**:
  - Use alignment score `A` and directional slope:
    - `slope = (emaSlow - emaSlow[20]) / (20*_Point)`.
  - Trend if `A>=3` and `abs(slope) >= slopeMin`.
- **Range compression detection**:
  - `BBWidth = (BBUpper-BBLower)/BBMid`.
  - Compression if `BBWidth < Percentile(BBWidth, 20%)`.
- **Session conditioning**:
  - Create a session map (broker time): Asia, London, NY.
  - Restrict breakout entries to London/NY overlap by default.
- **Spread expansion filter**:
  - Maintain `spreadMA = SMA(spreadPoints, 50)`.
  - Reject if `spreadPoints > 1.8 * spreadMA`.
- **News-risk avoidance (structural approximation)**:
  - Without calendar feed, approximate “event risk” by detecting abrupt spread/range shocks:
    - `shock = I(spreadPoints > 2.5*spreadMA) OR I(rangeZ > 3.0)`.
  - If `shock` in last `M=3` bars, disable new entries for `cooldownShock=30` minutes.

#### D. Microstructure Proxy Design

- **Breakout validation via tick-velocity + spread stability**
  - Tick velocity proxy: count ticks per second over last `T=5` seconds using `OnTick()` timestamp deltas (store in circular buffer).
  - Require velocity percentile > 60% of last 30 minutes AND spread not expanding.
- **Stop-run / liquidity sweep detection (for stop placement avoidance)**
  - Define wick ratio:
    - `upperWick = High - max(Open,Close)`
    - `lowerWick = min(Open,Close) - Low`
    - `wickRatio = max(upperWick,lowerWick) / max(High-Low, eps)`
  - Sweep proxy:
    - price makes a new `n=20` bar high/low intrabar but closes back inside prior range with `wickRatio>=0.6` AND `rangeZ>=1.5`.
  - If sweep proxy present in direction of intended breakout, reject breakout entry (avoid buying into stop-run).

#### E. Risk-Asymmetry Upgrade

- **Risk unit**: `R` in account currency with fixed fraction `f` of equity (base `f=0.10%` to `0.25%` per trade).
- **Stop model** (volatility-aware):
  - For trend breakout: `SL = entry - kSL * ATR14` (bull) / `entry + kSL*ATR14` (bear), with `kSL` regime-dependent:
    - low vol: `kSL=1.2`, normal: `1.5`, high: `2.0`.
- **Take-profit model** (convexity / positive skew):
  - Use partials + trailing:
    - TP1 at `+1R` (close 30–50%)
    - Move SL to break-even only after `+1.2R` (avoid BE noise)
    - Trail remainder using `chandelier = max(high since entry) - kTrail*ATR`.
- **Exposure caps**:
  - Per symbol: `maxOpenPositions=1` (or 1 per direction).
  - Per cluster (trend): total risk <= `clusterRiskCap` (e.g., 0.5% equity).
- **Loss clustering mitigation**:
  - If `lossesLastN >= 3` within last `M=24h`, reduce `f` by 50% and require stricter `A>=3` and `spreadPoints <= 0.06*atrPoints`.

#### F. Statistical Hardening Requirements

- **Minimum sample gating**
  - Do not enable the upgraded rule-set on a symbol until `minTrades=200` in backtest/walk-forward on that symbol/timeframe.
- **Out-of-sample enforcement**
  - Split history into sequential folds in testing pipeline:
    - Train/opt window: 12 months
    - Validation window: next 3 months
    - Roll forward by 3 months
  - In code, embed a “parameter set ID” with timestamp; the EA refuses to run if parameter age > `maxAgeDays` unless revalidated.
- **Stability corridor logic**
  - For each key parameter `p` (e.g., `L`, `kSL`, `kTrail`), define a corridor `[p*(1-δ), p*(1+δ)]` with `δ=0.2`.
  - Strategy is acceptable only if performance degradation within corridor is bounded (e.g., Sharpe drop < 25%, maxDD increase < 30%).
- **Sensitivity testing framework**
  - Use MT5 optimizer with **coarse grid** + **forward testing**; do not allow per-symbol custom tuning beyond corridor.

#### G. Institutional Viability Score (Post-Upgrade Projection)

- **Projected viability**: 62/100
  - Rationale: trend is the most defensible edge class under OHLC-only constraints once cost gates, compression/expansion triggers, and convex exits are enforced.

---

### Strategy: Candlestick Patterns (Pin Bar, Engulfing) + Fibonacci v2.0 (Swing + Fib + Confirmation) + Harmonic Engines

#### A. Redefined Edge Thesis

- **Primary inefficiency**: short-horizon mean reversion *conditional on liquidity sweep behavior* and *failed breakout structure*.
- **Mechanism statement**:
  - Reversal setups are not “patterns”; they are **failed auctions** where price probes beyond a reference extreme and is rejected with a wick-dominant candle and a volatility/volume anomaly.
- **Institutional deployment requirement**:
  - Convert these modules into a single **Failed Breakout / Sweep-Fade engine**; demote fib/harmonic geometry to *feature extraction* only.

#### B. Required Structural Modifications

1. **Collapse pattern zoo into a single measurable event definition**
   - Define reference level `Lref` as:
     - prior `DonchianHigh/Low(20)` OR S/R cluster centroid (from your S/R detector).
   - Define sweep event:
     - price trades beyond `Lref` by at least `x = 0.15*ATR14` but closes back inside by close.
   - Define rejection quality:
     - wick ratio `>= 0.6` and close location in opposite half of candle.
2. **Replace Fibonacci entries with ATR-normalized pullback bands**
   - Instead of 61.8% of an arbitrary swing, define pullback zone:
     - `zoneLow = impulseHigh - kPB1*ATR`
     - `zoneHigh = impulseHigh - kPB2*ATR` with `kPB1>kPB2` (e.g., 1.2 and 0.6)
   - Enter only if a sweep-fade occurs *into* the pullback zone (confluence becomes geometric-free).
3. **Harmonic patterns as features, not triggers**
   - If harmonic scanner finds PRZ near `Lref` within `0.3*ATR`, add a small confidence bonus; do not allow it to generate a trade.

#### C. Regime Adaptation Layer

- Only allow sweep-fade trades in `RANGE` or `CHAOS` regimes; forbid in strong `TREND` unless trading “pullback continuation” with higher-timeframe alignment.
- Range detection (simple and robust):
  - `ADX(14) < 18` AND EMA alignment score `A<=1`.
- Compression requirement:
  - Require pre-sweep compression: `BBWidth < p30` and `ATR14 < p50`.
- Session conditioning:
  - Prefer London open and NY open windows where stop-runs are more frequent; disable during illiquid rollover.
- Spread filter:
  - Stricter than trend systems: `spreadPoints <= 0.05*atrPoints`.

#### D. Microstructure Proxy Design

- **Liquidity sweep proxy (OHLCV/tick-only)**
  - Sweep condition (bull fade example):
    - `Low < min(Low[1..n]) - x` AND `Close > min(Low[1..n])`.
  - Tick acceleration:
    - In the sweep bar, tick count over bar duration exceeds its 70th percentile of last 200 bars.
- **Volume/participation proxy**
  - If real volume is available: require `Volume > SMA(Volume, 50) * 1.3` on sweep bar.
  - If only tick volume: same rule with tick volume.
- **Spread shock veto**
  - Reject if spread spikes > 2.0x `spreadMA` during sweep (indicates instability / widened market).

#### E. Risk-Asymmetry Upgrade

- Stops must be placed beyond sweep extreme with buffer:
  - `SL = sweepExtreme - b*ATR` (bull fade) with `b=0.15..0.30` depending on volatility regime.
- Targets must reflect mean reversion to “fair value” not fixed RR:
  - Define fair value proxy: `VWAP_session` if implemented via tick-volume approximation, else `EMA(20)`.
  - TP1 at fair value, TP2 at opposite range boundary (Donchian mid or S/R centroid).
- Position sizing must be constrained by *stop distance* and *cluster exposure*:
  - `riskPerTrade = min(f*Equity, clusterRemainingRisk)`.
  - Ensure stop distance >= broker stop level + spread.
- Kill switch:
  - If 5 sweep-fade trades occur without reaching TP1 in a rolling 2-day window, disable the engine (edge absence signal).

#### F. Statistical Hardening Requirements

- **Event-count requirements**
  - Track event counts per symbol: `sweepsSeen`, `sweepsTraded`, `tp1HitRate`, `expectancy`.
  - Require `sweepsTraded >= 100` before trusting hit-rate.
- **Expectation audit**
  - Calculate expectancy online (EMA of R-multiples):
    - `E_t = α * Rmult_t + (1-α)*E_{t-1}`, α=0.05.
  - If `E_t < -0.05` for 50 trades, hard-disable module for that symbol.
- **Parameter freeze**
  - After validation, freeze `x`, wick ratio threshold, and spread thresholds; do not optimize per symbol.

#### G. Institutional Viability Score (Post-Upgrade Projection)

- **Projected viability**: 52/100
  - Rationale: sweep-fade can be structurally defensible with strict microstructure filters and event-based gating, but capacity is limited and regime dependence is severe.

---

### Strategy: Support/Resistance + Trendlines

#### A. Redefined Edge Thesis

- **Primary inefficiency**: conditional mean reversion and breakout continuation around *auction reference points* (prior highs/lows, clustered extremes) when *participation* and *volatility regime* are favorable.
- The edge is not “a line”; it is the **conditional distribution of next excursion** given a tested reference with stable spreads and compression/expansion pattern.

#### B. Required Structural Modifications

1. **Quantize level quality**
   - For each level `L`, compute:
     - touch count `t` within last `W` bars
     - median rejection distance `dMed` (in ATR units)
     - post-touch excursion `e` (median max favorable excursion within next `H` bars)
   - Level score: `Score(L) = w1*log(1+t) + w2*e - w3*dMed` (all ATR-normalized).
2. **Explicit “setup types” become measurable templates**
   - Bounce setup requires:
     - approach compression: decreasing ATR and BBWidth
     - rejection: wick ratio threshold
   - Breakout setup requires:
     - pre-break compression + close beyond level by `>= 0.2*ATR`
     - retest within `0.3*ATR` with spread stable.
3. **Remove discretionary drawing-driven behavior from trading decisions**
   - Drawing is allowed for diagnostics, but trade logic must use numeric level objects only.

#### C. Regime Adaptation Layer

- Bounce module only in `RANGE` (ADX low) and low/normal vol.
- Breakout module only when compression detected and volatility is rising (`V>1.0`) but spread stable.
- Session gating:
  - Breakouts: London/NY; bounces: late Asia / early London (instrument-dependent).

#### D. Microstructure Proxy Design

- **False breakout proxy**
  - If close breaks level but next bar closes back inside and sweep wick ratio is high, classify as false breakout.
  - Trade in opposite direction only if spread stable and tick volume above median.
- **Retest quality**
  - Retest bar must have lower range than breakout bar (avoid chasing).

#### E. Risk-Asymmetry Upgrade

- Bounce: small risk, larger mean reversion target
  - `SL` beyond level by `0.2*ATR` + spread.
  - TP at mid-range/fair value; optional runner to opposite boundary.
- Breakout: convex runner
  - Partial at `+1R`, trail remainder via ATR chandelier.
- Exposure caps:
  - S/R cluster shares risk budget with sweep-fade engine.

#### F. Statistical Hardening Requirements

- Maintain per-level “live track record”:
  - If a level’s last `k=5` trades all fail to reach TP1, down-rank or expire the level.
- Do not allow level count explosion:
  - Cap active levels per timeframe (e.g., max 6) by score.

#### G. Institutional Viability Score (Post-Upgrade Projection)

- **Projected viability**: 55/100
  - Rationale: level-based trading can be made testable via event definitions and level scoring, but it remains crowded and cost-sensitive.

---

### Strategy: Unified ICT/SMC

#### A. Redefined Edge Thesis

- **Primary inefficiency**: conditional continuation or reversal after **stop-run / displacement / reversion to fair value** sequences.
- This becomes institutionally defensible only if recast as:
  - **Event-based market structure engine** (break of structure),
  - **Displacement detector** (range expansion relative to ATR),
  - **Reversion zone** (fair value proxy),
  - with strict microstructure filters.

#### B. Required Structural Modifications

1. **Replace narrative confluence with a small set of falsifiable events**
   - BOS (break of structure) event:
     - For bullish: `Close > swingHighPrev` by `>= 0.15*ATR`.
   - Displacement event:
     - `rangeZ > 1.8` AND close-to-open body ratio > 0.6.
   - Reversion zone:
     - `FVG` proxy can be implemented as a 3-candle gap in bodies/ranges, but must be defined numerically (e.g., `Low[1] > High[3]` etc. depending on definition).
2. **Kill zones must be treated as conditioning variables only**
   - Session windows alter thresholds (spread/vol) but do not create signals.
3. **OTE becomes ATR-band pullback**
   - Same as sweep-fade redesign: avoid fib ratios; use ATR-normalized pullback zones.
4. **Counter-trend scouting must be eliminated or constrained**
   - Only allowed when a sweep-fade event triggers AND higher timeframe regime is range; otherwise forbid.

#### C. Regime Adaptation Layer

- Use higher-timeframe regime for bias:
  - HTF trend alignment score `A_HTF` and ADX/vol state.
- Allow “structure continuation” only when HTF is TREND.
- Allow “sweep-fade” only when HTF is RANGE.

#### D. Microstructure Proxy Design

- **Liquidity sweep**: wick + break/close-back-inside as defined earlier.
- **Displacement**: range expansion + body dominance + spread stability.
- **Mitigation / retest**: price revisits displacement origin zone within `0.5*ATR` and prints reduced range bar with stable spread.

#### E. Risk-Asymmetry Upgrade

- Treat as two sub-engines with separate risk budgets:
  - Continuation engine (trend): convex runner.
  - Reversal engine (sweep-fade): mean reversion to fair value.
- Enforce strict kill-switch:
  - If combined ICT engine loses `>= 4R` in rolling 20 trades, disable for 48h on that symbol.

#### F. Statistical Hardening Requirements

- Remove the ability to “win by filtering”
  - Track missed events and traded events.
  - Require stable performance on traded events without reducing trade count below a minimum rate (e.g., at least 2 trades/month per symbol in live-like period), otherwise treat as over-filtered.
- Online calibration of event thresholds:
  - Only allow thresholds to adapt within a corridor based on rolling volatility percentiles.

#### G. Institutional Viability Score (Post-Upgrade Projection)

- **Projected viability**: 58/100
  - Rationale: once reduced to event-based structure + displacement + pullback with microstructure gates, it can become testable. Complexity must be reduced to avoid unfalsifiability.

---

### Strategy: Elliott Wave Enhanced

#### A. Redefined Edge Thesis

- **Hard constraint**: Elliott wave counting is not a stable, replicable measurement under OHLC-only constraints.
- **Institutional salvage path**:
  - Convert it into a **multi-scale swing/impulse decomposition** used only to derive:
    - trend maturity (early vs late)
    - volatility clustering state
    - pullback depth distribution
- It must not be used as a direct signal generator.

#### B. Required Structural Modifications

- Replace wave labels with measurable swing features:
  - swing amplitude stats: `amp_i = |price(swing_i)-price(swing_{i-1})| / ATR`
  - impulse persistence: ratio of directional swings to total over last `m` swings
  - exhaustion proxy: decreasing impulse amplitude while ATR rising.
- Output only a regime tag: `EARLY_TREND`, `MATURE_TREND`, `EXHAUSTION`, `RANGE`.

#### C. Regime Adaptation Layer

- Use this tag to tighten/loosen trend engine activation and trailing aggressiveness.

#### D. Microstructure Proxy Design

- None unique; it should not pretend to measure hidden liquidity.

#### E. Risk-Asymmetry Upgrade

- As a classifier only, it must not consume risk budget.

#### F. Statistical Hardening Requirements

- Require classifier stability:
  - Tag flip rate per day must be below a maximum (e.g., < 6 flips/day on M15) otherwise it is too noisy.

#### G. Institutional Viability Score (Post-Upgrade Projection)

- **Projected viability**: 35/100
  - Rationale: only viable as a feature/regime tag; not as alpha.

---

## 3. Cross-Strategy Portfolio Engineering Upgrade

- **Correlation clustering redesign**
  - Define clusters by mechanism, not by file:
    - `TREND_CLUSTER`: upgraded Trend + upgraded Momentum
    - `MEAN_REVERSION_CLUSTER`: sweep-fade engine (candles/fib/harmonic refactor) + S/R bounce
    - `STRUCTURE_CLUSTER`: simplified ICT continuation/retest engine
- **Capital allocation model**
  - Risk parity by cluster using realized variance:
    - `w_i ∝ 1 / sqrt(rv_i)` with caps `w_i <= wMax`.
  - Convert weights to risk budgets:
    - `clusterRiskCap_i = baseRiskCap * w_i / sum(w)`.
- **Strategy interaction controls**
  - Mutual exclusion rules:
    - If TREND cluster has an open position on a symbol, MEAN_REVERSION entries on that symbol are blocked unless explicitly configured as hedges (default: block).
    - If STRUCTURE continuation is active, forbid sweep-fade against it.
- **Exposure netting logic**
  - Compute net directional exposure per symbol:
    - `net = Σ(sign(positionDir)*riskAmount)`.
  - Forbid adding exposure in same direction if `net` exceeds per-symbol cap.
- **Kill-switch architecture**
  - Per symbol:
    - If `maxDD_rolling_30d` exceeds threshold or `E_t` expectancy becomes negative beyond tolerance, disable symbol for 7 days.
  - Global:
    - If portfolio drawdown exceeds `DDmax` (e.g., 8–12% depending on mandate), reduce all `f` by 50% and disable mean reversion cluster until recovery.

---

## 4. Realistic Institutional Expectation Setting

- **Expected Sharpe (realistic range)**
  - For OHLC-only systematic strategies on liquid FX/indices after costs:
    - Trend cluster: ~0.3 to 0.9 (symbol/timeframe dependent)
    - Mean reversion (sweep-fade) cluster: ~0.2 to 0.7 with strong regime dependence
    - Combined portfolio (with correlation controls): ~0.4 to 1.0 if engineering and validation are strict
- **Drawdown expectations**
  - Even with hardening, expect 10–25% peak-to-trough in adverse regimes unless leverage is very low.
- **Capacity limits**
  - Without order book, capacity is constrained by spread/slippage and signal frequency:
    - Breakout/trend can scale better than sweep-fade.
    - Sweep-fade is inherently capacity-limited and execution-sensitive.
- **Regime dependency acknowledgment**
  - Trend engines fail in prolonged mean reversion.
  - Sweep-fade engines fail in strong trend continuation regimes.
  - Structure engines fail in unstable spread/news shock periods.
- **Failure conditions that still remain**
  - Structural alpha may not exist in a chosen symbol/timeframe; no amount of parameter work fixes that.
  - Broker execution quality (requotes, widened spreads, stop rules) can destroy edge.
  - Without a true economic catalyst feed, “news-risk avoidance” remains heuristic; shock filters reduce harm but cannot eliminate event-driven gaps.

