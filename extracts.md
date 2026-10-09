### 1. Stated Objectives
- Autonomous multi-strategy trading :`README.md` L8-L14 明确说明`MultiStrategyAutonomousEA` 是 MT5 自主多策略交易系统，20 个策略模块通过加权共识投票组合，并在订单到达经纪商前经过多层风险/相关性/组合敞口/点差/时段/状态验证。
- Production-grade signal validation :`README.md` L52-L67 列出生产级特性，包括多策略共识、3 层信号架构、AI 集成、多资产类别配置、多层风险权威、Deriv 合成支持、复利层级、Python ML 桥接等。
- Clear ownership & deterministic flow :`SYSTEM_STRUCTURE.md` L10-L23 描述系统目标为自主多策略交易决策，强调信号生成与共识、会话感知执行、自适应 AI 阈值、盘前风险否决、执行与盘后反馈的明确所有权边界。
### 2. Architecture Map: Strategy Registration → Consensus → Risk Gate → Execution
- Strategy registration / registry :`EAOrchestrator.mqh` L684-L719 先初始化`RegistryAggregator` ，再初始化 per-symbol`EnterpriseStrategyManager` 、AI 子系统，最后构建策略标志与`StrategyRegistry` ，这是策略进入共识管线的入口。
- Per-symbol strategy management :`EnterpriseStrategyManager.mqh` L101-L133 展示每个符号的策略管理器持有策略 roster、quorum 配置、信号上下文、基础设施与 trade feedback，是策略注册状态与共识引擎之间的承载层。
- Consensus decision core :`ConsensusEngine.mqh` L229-L261 是共识入口`GetConsensusSignalForSymbolWithConfluenceMode` ，调用`EvaluateConsensusInternal` 生成最终交易信号；L290-L319 将注册中心最终状态同步为策略启用状态，确保只有注册中心允许的策略参与共识。
- Risk gate :`UnifiedRiskManager.mqh` L120-L130 说明其作为 EA runtime 单一权威风险契约，实现`IRiskPipelineHost` 并通过`CRiskValidationPipeline` 执行盘前验证。
- Execution path :`TradeManager.mqh` L337-L359 提供执行前校验`ValidateExecutionPreflight` 与成交确认`ConfirmExecutionReceipt` ；L482-L489 暴露`SendTradeAsync` ，是共识通过后的订单发送接口。
### 3. Consensus Math: Weights, Thresholds, AI / Regime Multipliers
- Regime hard-gate formula :`ConsensusEngine.mqh` L523-L553 定义`RegimeStateHardGate` ，对趋势/均值回归策略按当前 regime 返回`0.0` 、`0.25` 、`0.40` 或`1.0` ，是“策略类别在当前 regime 无优势则零投票”的核心公式位置。
- Regime-category multiplier :`ConsensusEngine.mqh` L555-L617 计算`GetRegimeCategoryMultiplier` ，将 regime hard-gate、类别权重、混沌/低置信度 deweight 相乘并限制到`[0, 2.5]` ，直接影响共识权重。
- Strategy participation & reliability :`ConsensusEngine.mqh` L632-L672 实现策略健康度与参与分数到`ReliabilityMultiplier` /`ParticipationMultiplier` 的映射，用于加权投票。
- Fallback solo signal scoring :`ConsensusEngine.mqh` L478-L489 在全部 abstain 时使用`score = confidence * weight * participation * qualityMultiplier` ，并设置 intrabar/new-bar 最低置信度阈值。
- Quorum / threshold inputs :`MultiStrategyAutonomousEA.mq5` L172-L180 暴露`InpQuorumThreshold` 、`InpMinLiveVoters` 、`InpConsensusMinReadyWeightRatio` 、支持阈值等共识参数，是运行时可调的决策门槛。
### 4. Documented vs Implemented Gaps
- AI mode wiring :`README.md` L52-L57 声称支持 Indicator Only / AI Only / Hybrid 与 4 类 AI adapter；`EAOrchestrator.mqh` L1208-L1235 仅初始化 NextGen AI Brain 与 AIPerformanceFeedback，并说明 runtime AI voters 是 adapter-owned、per-symbol 注册，体现文档高层能力与实现细节之间的差异点。
- Spike Hunter status :`EAOrchestrator.mqh` L1264-L1296 初始化 Spike Hunter 后明确日志`PARKED: not wired into the tick loop (documented-dormant)` ，说明部分生产特性虽初始化但未按 tick loop 接入。
- Regime multiplier behavior change :`ConsensusEngine.mqh` L557-L561 注释说明旧实现 regime multiplier 下界为`0.4` ，“could NEVER invert or zero a vote”，新实现改为 hard-gate；这是文档/注释中明确记录的行为差异。
- Post-size risk cap vs compounding tier :`changelogs.md` L42-L58 指出日志驱动修复中发现`UnifiedRiskManager` 的 post-size cap 为`1.50%` ，而 compounding tier 标签为`15%` ，说明实际执行保护与配置层级标签不一致，属于已记录但未改动的产品决策差异。
### 5. Recent Direction from Changelogs (Last 3–4 Batches)
- Batch 167 : 新增 walk-forward 验证引擎，强调“先证明 edge 再上线”，覆盖 Python 与 MQL5 双实现，是项目向实盘纪律化方向推进的最新动作。
- Batch 166 : 执行风险参数 Phase 0  recalibration，并将 regime multiplier 改为 hard-gate；这是针对“合成指数负期望/策略错配”问题的直接响应。
- Batch 159 : 修复 crash recovery checksum 与`CalculateTradeRisk` 低估风险的问题，尤其阻止 Volatility 75 Index  oversized trade 通过风险门控。
- Batch 160/161 : 修复训练脚本同步与 Testing EA 未解析 extern 问题，体现项目仍在补齐构建/测试链路，使 AI 训练与主 EA 编译状态一致。

---
Sub Coding Agent SMC cluster prose report

Read 13 files

# SMC/ICT Strategy Cluster Audit
## 1. BreakerBlockStrategy.mqh — CBreakerBlockStrategy
- Purpose: Trades breaker-block (failed OB → breaker) retests with FVG confluence, CISD displacement, and structure alignment.
- Algorithm: Scans unmitigated`OB_BREAKER_BULL/BEAR` entries whose zone contains the last closed bar close (`L104-L138` ); requires freshness > 0.7 boost, opposing-direction FVG exists (`L165-L174` ), recent CISD within 3 bars (`L177-L179` ), and structure alignment (`L182-L183` ); additive confidence score 0.55 base (`L186-L204` ); SL beyond zone ±0.5·ATR, TP 2R (`L213-L238` ).
- Look-ahead/repainting: All reads use closed bar 1 — clean. Risk: the OB detector's "breaker" detection itself is confirmed by subsequent closes (see §9), so breaker zones are inherently retrospective but not future-referencing at signal time.
- Magic numbers: Base 0.55, boosts 0.08/0.10/0.05/0.07, 2R TP, 0.5·ATR buffer,`OverrideMinConfidence(0.55)` (`L45` ) — all hard-coded, no inputs.
- Dead code: None.`OnTick` intentionally empty (`L82-L85` ).
- Red flags: If`atr==0` ,`slPips=0` and risk validation silently receives a 0-pip stop (guarded only by`atr>0` ternary,`L237` ).`m_structureAnalyzer.Initialize(..., 3)` swing strength hard-coded.
- Consensus plug-in: Overrides`GetSignal(double&)` ;`STradeValidationRequest` (stopLossPips/takeProfitPips in ATR-multiples, confidence, strategy name) →`ValidateWithRiskManager` →`SetProposedStops` →`RecordSignal` +`LogConsensusDiag` .
- Optimization: Full OB-array scan per signal call;`GetATR(14)` and`RefreshForNewBar` called every invocation though`HandleNewBar` already refreshes.
## 2. FVGScalperStrategy.mqh — CFVGScalperStrategy
- Purpose: FVG re-entry when last closed bar closes inside the gap with a rejection candle.
- Algorithm: Picks strongest of best bull/bear FVG (`L114-L151` ); requires bar-1 close inside zone (`L171` ) and rejection pattern (lower/upper wick > 2× opposite wick,`L181-L182` ); structure/CHOCH/CISD bonuses (`L202-L215` ); SL beyond FVG ±0.5·ATR, 1.5R TP (`L226-L246` ).
- Look-ahead: Closed-bar only — clean.
- Magic numbers: Scoring weights are at least configurable via`SetScoringWeights` (`L48-L54` ), but nothing calls it; defaults hard-coded. Rejection factor 2.0, 1.5R,`OverrideMinConfidence(0.55)` .
- Dead code: Misleading indentation at`L77-L81` and`L84-L89` (warning + Init body over-indented); warning at`L78-L79` suggests risk manager may be NULL but the strategy still proceeds.
- Red flags: Rejection test`(close1 - low1) > 2*(high1 - close1)` divides nothing but can trigger on a doji with tiny ranges — no minimum body/ATR filter. TP 1.5R < 2R used elsewhere (inconsistent, likely intentional scalp).
- Consensus: Same`GetSignal(double&)` + risk-gate pattern; ATR-denominated pips (Batch 158 convention).
- Optimization:`FindBestBullish/BearishImbalance` scans whole array twice;`DetectFastCHOCH` /`DetectCISDDisplacement` re-read bars per call.
## 3. LiquiditySweepStrategy.mqh — CLiquiditySweepStrategy
- Purpose: Stop-hunt reversal: wick beyond prev-session/daily/equal-highs/lows/round-number level, close back inside, enter on reversal.
- Algorithm:`DetectSweep` requires wick ≤ 0.3·ATR beyond level AND close back inside (`L134-L152` ); equal levels found by O(n·m) pair scan over 100 bars (`L200-L246` ); confidence from wick ratio + level type (`L155-L197` ); same-bar filter (`L457-L462` ).
- Look-ahead/session risk: "Session" levels are D1 bars (`L82-L106` ) — broker-midnight day boundaries, not true sessions; on non-UTC brokers prev-"session" high/low is wrong. Round-number "pip" math uses`point*10` 5-digit FX assumption (`L115` ) — wrong on 3-digit JPY, 2-digit synthetics. Copying 5 daily bars each signal (`L89` ) is per-call churn.
- Magic numbers: Defaults in constructor (`L249-L262` );`Configure()` exists but clamping changes defaults (0.6 threshold default vs 0.3 constructor value — inconsistent).
- Dead/duplicated:`GetSignal()` no-arg duplicates the consensus flow; class does not derive cleanly from CStrategyBase pattern — it has its own`Initialize(symbol,tf,riskMgr)` and never calls`CStrategyBase::Init` ;`m_is_initialized` /`IsEnabled()` never checked; `ExecuteSignal` does not call`ValidateWithRiskManager` — only`SetProposedStops` . The comment (`L505-L511` ) claims it now votes in consensus, but the unified risk gate (AGENTS.md invariant #1) is bypassed for this strategy.
- Red flags:`FindEqualLevels` loops`j` from`i+5` — bars within 5 of each other never count as "equal" (arbitrary);`DetectSweep` wick cap (`wickAbove <= threshold` ) means a deep sweep is rejected — counter-intuitive;`levelNames[bestLevelType]` (`L489-L492` ) indexes an 8-element array with an enum that has 8 values (0-7) — OK but fragile.
- Consensus: Overrides`ExecuteSignal(double&)` (not`GetSignal` ); risk manager member stored but unused for gating.
- Optimization:`FindSessionLevels` +`FindEqualLevels` +`FindRoundNumbers` all re-scan per signal; ATR handle owned here (released twice — destructor`L266` and`Deinit``L532` — double-release risk if both called).
## 4. TurtleSoupStrategy.mqh — CTurtleSoupStrategy
- Purpose: False breakout of a liquidity pool with structure/CHOCH confirmation + FVG bonus.
- Algorithm:`DetectTurtleSoup(sig, 4)` scans pools for bar in last 4 that took out pool price and closed back inside with counter-color candle (`LiquidityDetector L611-L679` ); requires structure aligned OR fast CISD (`L116-L127` ); confidence`0.50 + soup.conf*0.15 + bonuses` (`L135-L139` ); SL beyond sweep extreme ±0.3·ATR, 2R (`L148-L167` ).
- Look-ahead: Closed bars only — clean. Sweep detection is inherently retrospective (needs reclaim close) but bar-index bounded.
- Magic numbers: 0.3·ATR SL buffer (vs 0.5 elsewhere), 2R, pool tolerance`5.0` pips passed at Init (`L63` ).
- Red flags: SL pips computed as`slDistance / point` (`L172` ) — the old points-based convention the other strategies abandoned in Batch 158; on Deriv synthetics (point=0.01, price~1000s) this yields enormous "pip" counts that will distort the risk manager's scaling relative to Breaker/FVG strategies that feed ATR multiples. Same bug in AsianRangeBreak and NYOpenGap.
- Consensus: Standard`GetSignal(double&)` + risk gate;`RecordSignal` ,`LogConsensusDiag` present.
- Optimization:`DetectTurtleSoup` iterates all pools × 4 shifts with`iHigh/iLow/iClose/iOpen` per shift — fine;`RefreshForNewBar` double-call pattern same as others.
## 5. AsianRangeBreakStrategy.mqh — CAsianRangeBreakStrategy
- Purpose: London-open (07:00–07:30 UTC) breakout of the 00:00–06:00 UTC Asian M5 range.
- Algorithm: GMT-anchored`iBarShift` for the Asian window (`L126-L144` ); range-tightness filter vs ATR scaled by`bars^0.7` diffusion (`L180-L190` ); bar-1 close beyond range boundary (`L200-L201` ); compression/structure/CHOCH bonuses; SL at opposite boundary, TP 2×range (`L240-L245` ).
- Look-ahead/session: Uses`TimeGMT()` correctly (Batch 155 fix); DST not modeled (UTC window drifts vs local London open across DST — acknowledged implicitly).
- Magic numbers: 0.8/0.5 range thresholds, exponent 0.7, 07:00-07:30/00:00-06:00 windows — all hard-coded, no inputs.
- Red flags:`dt.min > 30` means window is 07:00:00–07:30:59 — a strategy-TF bar closing at 07:31 is excluded, fine, but on TF > M30 the window can be missed entirely (e.g. H1: bar closes 08:00, window check fails → strategy only fires on M5/M15).`slPips = slDistance/point` — points-based inconsistency (see §4).`LogConsensusDiag` prints`asianRange/atr` mixing dimensional quantities.
- Dead code:`m_killZones` is constructed and its`IsInKillZone()` result discarded in`OnRefreshComponents` (`L30` ) — pure waste; kill zones play no role in the signal.
- Consensus: Standard pattern.
## 6. NYOpenGapStrategy.mqh — CNYOpenGapStrategy
- Purpose: Fade the daily gap during 13:30–14:00 UTC with FVG confluence.
- Algorithm: UTC window check (`L106-L113` ); D1 prev-close vs today-open gap > 0.5·ATR(D1) (`L135-L167` ); fade direction; FVG/near-NDOG-midpoint boosts (`L175-L193` ); SL beyond gap extreme ±0.5·ATR, TP at prev close (`L206-L226` ).
- Look-ahead/session: The code itself documents the core defect (`L122-L128` ): D1 bars roll at broker midnight, so this is a proxy gap measured at ~19:00 ET, not the true NDOG at 09:30 ET — follow-up TODO explicitly noted.`SessionGapDetector` computes the real NDOG but is only used for a proximity bonus, not the trigger.
- Magic numbers: 0.5/1.0 ATR gap thresholds, 0.15 midpoint tolerance, hard-coded window.
- Red flags: Points-based pips (same as §4/§5). ATR pulled via`CIndicatorManager` D1 handle each call — OK but inconsistent with other strategies using`m_structureAnalyzer.GetATR` . TP = prevDayClose (gap fill) can be on the wrong side of entry if price already passed it —`tpPips` still positive via MathAbs, but the risk manager receives a TP in the wrong direction (no directional validation of TP vs order type).
- Dead code: None significant.
- Consensus: Standard pattern.
## 7. AdvancedOrderBlocks.mqh — CAdvancedOrderBlockDetector
- Purpose: Detects 6 OB families (Source, Continuation, Breaker, Propulsion, Rejection, Vacuum) with mitigation/test tracking.
- Algorithm: Per-family detectors scan up to 25–50 bars with per-family criteria (`L375-L1103` );`CheckMitigation` walks ≤200 bars forward from OB time tracking tests/rejections and close-through mitigation (`L1147-L1221` ).
- Look-ahead/repainting — the cluster's biggest structural risk: Every detector re-runs from scratch on`Update()` (`L192-L201` resets`m_obCount=0` and re-detects). Continuation/breaker validation (`L565-L579` ,`L663-L674` ) requires closes after the candidate candle to break the OB extreme — i.e., zones are identified using future bars relative to the OB candle. That's fine for a historical zone, but since detection is stateless per Update, an OB that was valid last bar can silently vanish/re-appear as new bars close (swing revision).`CheckMitigation` walks bars newer than`ob.time` only — consistent.
- Hard-coded: strength values 0.85/0.70/0.80 (`L472` ,`L588` ,`L703` ), freshness decay 5→50 bars,`3 rejections = mitigated` (`L1217-L1218` ), impulse relaxation 0.35/2 bars (`L390-L398` ).
- Red flags:`DetectBullishSourceOB` "walk forward from impulseStartBar+1" comment claims walking backward (`L416-L443` ) — code walks to higher shifts (older bars); logic works but the OB picked is the first bearish candle older than the impulse, not necessarily the last before it.`IsNearResistanceLevel` uses fixed`20*point` tolerance (`L1321` ) while`IsNearSupportLevel` got the ATR-relative fix (`L1304` ) — asymmetric, likely an oversight.`ScanForOrderBlocks(500)` ignores the`lookback` param for most detectors (they use their own 25–50 constants) and`Update()` calls it with 500 anyway (`L194` ) — misleading.
- Duplication:`IsBullishType` /`IsBearishType` (private) duplicate the public`IsBullishOBType` /`IsBearishOBType` (`L101-L102` vs`L143-L154` ).
- Optimization: O(n²)`GetAverageVolume` per vacuum candidate (`L1016` ); repeated`iOpen/iClose/iHigh/iLow` calls instead of one`CopyRates` ; ATR fetched via shared handle per call (good).
## 8. ImbalanceDetector.mqh — CImbalanceDetector
- Purpose: 3-candle FVG detection with rebalance/IFVG tracking.
- Algorithm: Gap between candle1 and candle3 extremes of the middle impulse candle (`L183-L248` ,`L256-L313` ); min size 5 points AND 5% ATR; strength scoring (`L441-L466` ).
- Look-ahead: Scan uses bars 2..48 — all closed at scan time relative to detection, but like the OB detector the whole list is rebuilt each Update, so FVGs appear/disappear with bar progression (no persistence).
- Red flags — major: `GetATR()` creates and releases an iATR handle on EVERY call (`L422-L436` ) — the exact churn Batch 157/158 eliminated elsewhere via`CIndicatorManager` .`DetectBullishImbalance` calls it per candidate bar inside the scan loop → dozens of handle create/release per Update per strategy instance (Breaker, FVGScalper, TurtleSoup, NYGap each own one). IFVG price check`lastPrice > bottom && lastPrice < top * 1.005` (`L400-L414` ) multiplies a price by 1.005 — dimensionally wrong for any price scale; intended a tolerance band but it's a 0.5% of price band above the top.
- Hard-coded: 5-point/5%-ATR min, strength tiers, 100-bar rebalance walk, max 30 FVGs.
- Duplication:`CheckRebalance` 's fill-tracking logic duplicated conceptually with`CSessionGapDetector::UpdateFillStatus` .
## 9. LiquidityDetector.mqh — CLiquidityDetector
- Purpose: Liquidity pools (equal highs/lows, swings, D/W/MN levels, midnight/quarterly opens, NDOG-adjacent institutional levels) + sweep/turtle-soup detection.
- Algorithm: Equal-level pair scan with scale-free tolerance (`L210-L280` ); swing liquidity (`L285-L332` ); DST-aware NY midnight/quarterly levels via`BuildNewYorkTimestampGMT` (`L416-L524` ); sweep = wick beyond level + close back inside, checked over 20 bars (`L529-L581` ); turtle soup over pools × last N bars (`L611-L679` ).
- Look-ahead/session:`DetectLiquiditySweep` /`DetectTurtleSoup` scan bars newer than pool formation — correct retrospective confirmation. NY timestamp builder uses proper US DST rules — good; but`Update()` runs all detectors every refresh and wipes pools (`L190-L205` ), so`sweptTime` /state is rebuilt each bar — sweep persistence across bars is lost if the sweep bar falls outside the 20-bar window on re-scan.
- Red flags:`DetectEqualHighsLows` uses`m_equalTolerance * point` — TurtleSoup passes 5.0 (pips→points OK-ish on 5-digit, wrong elsewhere).`IsAtPsychologicalLevel` generic grid uses`MathLog10(price)` — for price < 10 the grid becomes fractional; fine, but`grid*0.002` tolerance at price~1 gives near-zero band.`DetectTurtleSoup` returns first match, not best.`GetAverageVolume(20)` includes bar 0 (forming).
- Dead code:`FindBarAtTime` in SessionGapDetector (see §11) unused;`HasRecentSweep` unused by TurtleSoup strategy.
- Optimization: Full`CopyHigh/CopyLow/CopyTime` triple per detector per Update;`Update()` re-detects everything each call.
## 10. MarketStructureAnalyzer.mqh — CMarketStructureAnalyzer
- Purpose: Swing structure, BOS/CHoCH classification, multiplex HTF/MTF/LTF, CISD, fast CHOCH, displacement.
- Algorithm: Swing points with strength-3 neighbors (`L269-L350` );`HasStructureBreak` on bar-1 close vs current/previous swing (`L490-L588` ); CISD 3-bar candle logic (`L834-L875` ).
- Look-ahead — second structural risk: Swing highs/lows are confirmed with`i±str` neighbors, and`m_highs[0]` /currentHigh is whatever the most recent confirmed swing is — but`HasStructureBreak` compares close to`m_structure.currentHigh` which persists between Updates even as new swings form. Also`HasStructureBreak` increments`consecutiveBMS` /`bosCount` on every qualifying bar until structure flips — count inflation.`lastBMSTime = TimeCurrent()` uses broker time compared later against`iTime(...)` (`L598-L600` mixing timebases —`HasBMS` compares`lastBMSTime >= thresholdTime` where threshold is bar open time; during a bar's life TimeCurrent > bar time so BMS always "recent"; minor).
- Red flags: Consolidation branch (`L560-L585` ) sets structure flags without resetting the opposite flag (both could be true momentarily).`HasVolume` uses bar 0 volume (forming).`GetSwingHighLevel` uses`iHighest` over 20 bars — that's a period high , not a swing level, so`DetectFastCHOCH` triggers on any close above the 20-bar high (mislabeled but functionally a momentum check).
- Duplication:`IsBullish` /`IsBullishStructure` and`IsBearish` /`IsBearishStructure` are exact duplicate getters.
- Optimization:`FindStructuralPoints` is O(lookback × str) with full buffer copies — fine;`UpdateMultiplexStructure` copies 50 bars × 3 TFs × 3 arrays per Update;`AnalyzeStructure` is called again inside`IsValidMultiplexSetup` /`IsHTFAligned` (redundant recompute per call).
## 11. SessionGapDetector.mqh — CSessionGapDetector
- Purpose: NDOG/NWOG detection and fill tracking.
- Algorithm: D1/W1 prev-close vs current-open gap ≥ 5% ATR (`L161-L228` ); fill = close through far side; mitigation = midpoint touched; fill tracking over last 50 bars of the D1 timeframe (Initialize sets PERIOD_D1,`L61` ) — 50 D1 bars ≈ 2.5 months of fill history, plausible but coarse.
- Red flags:`UpdateFillStatus` iterates D1 bars only, so intraday gap fill between D1 closes is invisible until day end.`FindBarAtTime` (`L336-L343` ) is dead code. No detection of true NY-session NDOG (same proxy limitation documented in NYOpenGapStrategy).
- Hard-coded: min gap 0.05 ATR, 50-bar fill window.
## 12. KillZones.mqh — CICTKillZones
- Purpose: EST-anchored session windows (Asian/London/NY AM/PM/overlap + 3 Silver Bullet windows) with weights.
- Algorithm: Broker-time → EST conversion with hard-coded broker GMT offset; US-DST rules computed at`Initialize` only (`L220-L242` );`IsInSession` minute comparisons (`L294-L313` ).
- Look-ahead/session — critical: `GetCurrentESTHour` uses`TimeCurrent()` (broker time) minus`m_brokerGMTOffset` , with`m_brokerGMTOffset` defaulting to 2 and passed as literal`2` from AsianRangeBreakStrategy (`L58` ) . On any broker not at GMT+2 (and not GMT+2/+3 with DST), every session window is shifted.`m_estOffset` is frozen at Initialize — a long-running EA crosses DST boundaries with a stale offset. Also the DST computation uses`dt.hour < 2` /`>= 2` in broker hours, not EST hours — wrong by the broker offset.
- Red flags:`m_sessions[9]` array but`m_sessionCount = 8` (`L60-L61` ) — loops over weights/names stop before index 8 (unused slot 8; harmless but sloppy). Asian session definition (20:00–00:00 EST) contradicts AsianRangeBreakStrategy's 00:00–06:00 UTC Asian window — two different "Asian" definitions in one cluster.
- Dead code:`m_sessions[8]` never initialized.
## 13. PremiumDiscount.mqh — CSMCPremiumDiscount
- Purpose: Premium/discount/OTE zone classification from a swing-anchor range.
- Algorithm: Anchor from`SetSwingAnchor` or fallback swing scan (3 bars each side,`L158-L213` ); OTE = 61.8–78.6% retracement bands (`L238-L268` ).
- Red flags: OTE zone assignment ignores`m_anchorIsBullish` — both bull and bear OTEs computed from the same range regardless of leg direction; a bearish-leg retracement still produces an active "bullish OTE" for buys.`GetPriceZone` /`IsPremium` return garbage when range==0 (m_rangeMid=0 → everything premium) — no validity guard.`IsEquilibrium` tolerance is 5% of range both ways → up to 10% of range classified equilibrium.
- Integration: No consumer in the six audited strategies — unused by this cluster (possibly used by a unified ICT strategy outside the audit scope).
- Dead code:`m_anchorIsBullish` set but never read.
## Cross-File Synthesis
Shared patterns. All six strategies follow the same skeleton:`CStrategyBase` subclass, empty`OnTick` ,`GetSignal(double&)` → component refresh → additive confidence score from a 0.50–0.55 base with fixed bonus increments →`MathMin(0.95, score)` → SL/TP →`STradeValidationRequest` →`ValidateWithRiskManager` →`SetProposedStops` →`RecordSignal` /`LogConsensusDiag` . Confidence scoring is entirely hard-coded everywhere (FVGScalper's`SetScoringWeights` is the sole exception and is uncalled). Detectors share a common flaw: full state rebuild on every`Update()` — no persistence, causing zones/pools/sweeps to flicker as history extends (repainting-by-redetection). Several Batch 155–158 fixes (scale-free ATR pips, TimeGMT anchoring, synthetic-family filters) show real maintenance, but the fixes were applied unevenly.

Duplication.`IsBullishType` /`IsBullishOBType` duplicated in AdvancedOrderBlocks;`IsBullish` /`IsBullishStructure` duplicated in MarketStructureAnalyzer; rebalance/fill logic duplicated between ImbalanceDetector and SessionGapDetector; sweep detection logic exists three times (LiquiditySweepStrategy.DetectSweep, LiquidityDetector.DetectLiquiditySweep, DetectTurtleSoup); "Asian session" defined inconsistently in KillZones vs AsianRangeBreakStrategy; every strategy owns its own CMarketStructureAnalyzer/CImbalanceDetector instances rather than sharing per-symbol singletons.

Top 5 most impactful issues (ranked):

1. Inconsistent SL/TP unit convention (TurtleSoup`L172-L173` , AsianRangeBreak`L244-245` , NYOpenGap`L225-226` use price/point; Breaker/FVG use ATR multiples). The unified risk manager receives semantically different "pips" from strategies in the same consensus — position sizing and stop validation are inconsistent cluster-wide. Highest severity because it corrupts risk on every signal from three strategies.
2. CImbalanceDetector::GetATR creates/releases an iATR handle per call inside per-bar scan loops (`ImbalanceDetector L422-L436` ). With 4+ strategy instances each scanning ~50 bars, this is hundreds of handle create/release cycles per new bar — terminal resource churn the codebase explicitly eliminated elsewhere (Batch 157).
3. LiquiditySweepStrategy bypasses the unified risk gate. Its`ExecuteSignal` never calls`ValidateWithRiskManager` (AGENTS.md invariant #1 violation in spirit), uses broker-D1 "session" levels, and carries 5-digit-pip assumptions — the strategy's consensus votes are structurally weaker than every sibling.
4. Timebase fragility: KillZones relies on hard-coded broker GMT offset + Initialize-time-only DST (wrong on non-GMT+2 brokers and across DST transitions), while sibling strategies were migrated to TimeGMT — two incompatible time authorities in one cluster; NYOpenGap's documented NDOG proxy defect (`L122-L128` ) leaves the core trigger measuring the wrong gap.
5. Stateless full-rescan detectors (AdvancedOrderBlocks, ImbalanceDetector, LiquidityDetector) rebuild all state each Update with no persistence or event IDs — zones flicker, swept-pool timing is lost across rescans, and O(lookback²) scans (equal-levels pairing, vacuum volume averaging) run per component per bar per strategy instance. Combined with PremiumDiscount computing both OTE directions regardless of leg direction and its zero-range unguarded outputs, several detectors can emit structurally wrong confluence signals even though none reference future bars at the decision instant.

---
# Classic / Technical Strategy Cluster — Static Code Audit
Scope: research-only audit (no files modified) of the classic/technical strategies in`Strategies/` . Each section covers class/purpose, algorithm, statistical soundness, look-ahead/repaint, magic numbers, correctness red flags, dead/duplicate code, consensus integration, and optimization.

## 1. StatisticalArbitrageStrategy — pseudo-statistical-arbitrage
StatisticalArbitrageStrategy.mqh

- Class/purpose : registered "stat arb" pair strategy; requires the Python bridge for pair discovery and refuses signals when it is down ( L204-207 ).
- Algorithm : finds best correlated leg (`FindBestCorrelatedPair` L383-402 ), computes raw price spread`prices1[i] - prices2[i]*m_hedgeRatio` L436 , mean/population std L440-450 , z-score with zero-guard L227 , optional OU-blended z L230-242 ; entries beyond ±2σ with half-life gate 2–20 L540-548 ; SL/TP in pips derived from spread sigma L282-289 .
- Statistical soundness — unsound : (a) hedge ratio hard-fixed at 1.0 L114 ; no OLS/regression/Kalman anywhere, and a dynamic-ratio flag exists but is unused L61-62 . (b) Pair selection is Pearson correlation ≥0.85 only — high correlation ≠ cointegration. (c)`IsCointegrated()` L551-564 merely re-runs the correlation test (no ADF/Engle-Granger) and is never called. (d) Spread is built from raw price levels (ratio/cointegration math is invalid on non-stationary levels; log returns or a regression residual are required) over a short 50-bar window. (e) Legs read`PERIOD_CURRENT` L423-424 instead of`m_timeframe` .
- Only one leg trades :`GetSignal` returns a single directional BUY/SELL on`m_symbol` ;`ExecutePairTrade` L518-537 (and leg-2 lots computed L306-310 ) is never invoked — grep-confirmed dead. The position is an unhedged directional trade carrying two-leg-magnitude risk on a single-instrument SL/TP.
- Other : no indicator handles (no leak risk); magic passed as 0; consensus diag is hand-rolled L326-333 .
## 2. SimpleMomentumStrategy — EMA cross + filter stack
SimpleMomentumStrategy.mqh

- Algorithm : EMA8/21 cross with adaptive threshold`max(12·point, 0.2·ATR)` L672-698 , cross detection L708-709 , hysteresis L61-112 ; filters: RSI 72/28, ADX>20, MACD histogram, RSI divergence, volume surge, ROC acceleration, ATR floor; same-bar and cooldown guards L655-660 . Closed-bar, oldest-first buffer indexing is correct after Batch 155 ( L680-684 , L859-860 ).
- Handles/red flags : all handles via the shared cached`CIndicatorManager` (nulled, not released — correct ownership). Raw-price EMA fallback uses`CopyRates` start=0 including the forming bar L326-362 — a repaint surface when the cache misses. MACD is recomputed redundantly at L804 / L849 and again near L898.
- Duplicate`point` — verified, not a compile error :`double point` at L666 (function scope) and L863 are in different scopes — L863 is inside the nested`if(signal != TRADE_SIGNAL_NONE)` block opened at L816-817 ; legal shadowing, merely redundant.
- Consensus : full risk validation with ATR-derived stops and the only strategy that routes lot sizing through the position sizer L868-875 ; standard diag logging. Magic 0. Optimization: cache MACD confirmation once per poll; delete the shadowed local.
## 3. MeanReversionStrategy — Bollinger fade, one serious handle bug
MeanReversionStrategy.mqh

- Algorithm : BB(20,2) + RSI14 + volume ratio 1.2; band-tag fades L600-751 ; SL = band ∓ 0.5·bandwidth, TP = middle band; Hurst lockout, ADX>25 trend block L256-262 , divergence filter, band-width filter.
- Correctness — handle-poisoning bug :`m_stochHandle` is borrowed from the shared cached`CIndicatorManager.GetStochasticHandle` L144 yet is`IndicatorRelease()` d in Cleanup L127 . This invalidates the cached handle for every other consumer — same defect class as the documented Batch 156 ADX bug. The synthetic 1.5σ BB handle L349 is genuinely self-created and released correctly.
- Repaint :`GetADX` reads shift 0 (forming bar) L593 while the rest uses closed bars; synthetic-spike test compares shift1 vs shift6 L382 .
- Logic/perf : divergence check is semantically inverted — it rejects a bullish divergence ahead of a fade BUY L505-523 ;`SufficientBandWidth` fires up to 100 single-bar`CopyBuffer` calls per signal L556-565 (batch-fetch the window instead);`GetDynamicTP` L574-584 is dead; the`OnNewBar` same-bar guard is never consulted inside`GetSignal` . Magic 0; consensus/risk path present.
## 4. VolatilityBreakoutStrategy — squeeze breakout, copy-paste stop bugs
VolatilityBreakoutStrategy.mqh

- Algorithm : BB-squeeze percentile against a 10-width history L418-460 ; ATR ratio ≥1.3 and volume ≥1.5 gates; TTM double-squeeze, KC = EMA20 ± 2·ATR (EMA handle only) L655-673 ; retest / failure-reversal L692-747 ; BB/ATR fallback L91-143 .
- Statistical weakness : "percentile" over only 10 samples is noisy (20th percentile = 2nd-smallest width); the fallback fills all 12 ATR slots with the same value so the ratio silently collapses to 1.0 L296 .
- Correctness — accidental-correct ternaries : SELL branches test`== TRADE_SIGNAL_BUY` on a SELL-direction signal at L589 , L608 , L626 , L641 ; stops are right only because the false branch happens to be used — a latent reversal bug.`m_squeezeBar` is never reset; retest direction defaults to SELL L489 . Index [11] for the newest ATR is correct post-Batch155. Handles cached/shared; magic 0; consensus path normal.
## 5. RangeCompressionBreakout — lifecycle/risk bypass
RangeCompressionBreakout.mqh

- Algorithm : BB inside KC (EMA20 ± 1.5·ATR, EMA hand-computed L232-246 ); squeeze persists ≥6 bars; on release Hurst picks follow-through (H>0.55) vs fade (H<0.45) L274-314 ; volume confirmation reads closed-bar vol[1] correctly L98-115 .
- Architectural red flags : declares a custom non-virtual`Initialize` L161 and never calls base`Init` , so`m_is_initialized` is never set; votes through an`ExecuteSignal` override L442 that performs no`ValidateWithRiskManager` call (only`SetProposedStops` ) — direct violation of invariant §3.1 (all entries pass`CUnifiedRiskManager` );`GetStrategyType()` misreports`STRATEGY_MOMENTUM` L458 . Integrated via OrchestratorMathEngineHub / MathematicalEngineRegistry / StrategyCatalog.
- Repaint/state :`m_squeezeBarCount++` on every`GetSignal` poll with no once-per-bar guard L253 → intrabar inflation; trend-filter MA reads shift 0 vs BB shift 1 L328 .`m_kcHandle` is never assigned yet released (dead). Handles are self-created`iBands/iATR/iVolumes/iMA` L170-177 and released in both destructor and Deinit L465-489 , guarded so the double-release is safe. No consensus diag emitted.
## 6. Trend cluster
StrategyTrend.mqh +`TrendFiles/` (MultiEMASystem, ADXPositionSizing, TrendEntryTypes, TrendSignalEnhancers, TrendTrailingStop)

- Algorithm : 8/21/50/200 EMA stack with Hurst reject/attenuate L277-295 , VPIN>0.5, ADX tiers, DI spread ≥2 L309 , HTF ADX/DI confirmation L538-591 ([1] of start=0/count3 = shift1, correct), MACD; risk validation present. MultiEMASystem's oldest-first reverse mapping L220-239 is correct with div-guards.
- Red flags : ADXPositionSizing reads forming-bar shift 0 L168 ; the sizer's tick-based lot math L287-321 is sound but largely decorative — the main path sends broker min lot L351 . TrendEntryTypes owns/releases its iATR correctly L147 but`GetATR(non-14)` creates/releases a handle per call L184-197 , and entries use live SYMBOL_BID L287 ; continuation = pyramiding after 10 consistent bars;`GetBestEntry` = max confidence of four. TrendTrailingStop uses ATR shift 0 L176 , and`ApplyTrailingStop` re-seeds the high/low watermark with current price on every call L469-470 (no persistent extremum → trailing logic can't function across ticks), with a hardcoded 5-point BE buffer L494 . Magic 0.
## 7. Support/Resistance cluster
StrategySupportResistance.mqh +`SupportResistanceFiles/` (SupportResistanceDetector, TrendlineDetector, SRTradingStrategies, SRSignalScorer)

- Algorithm : swing-clustered levels with touch counting; bounce/breakout/false-breakout plays; scorer 30/25/20/15/10 weights, threshold 60.
- Performance — worst in suite : full re-scan every bar — 300 bars with O(n²)`ClusterLevels` L427-459 plus O(levels×100) touch loops L512-537 ; TrendlineDetector re-scans 200 bars L837-849 with O(n²) swing de-dupe and per-line 50-bar`iTime/iHigh` recency loops L749-786 — hundreds of price calls per bar per symbol. Levels should be cached and incrementally updated.
- Repaint/look-ahead : bounce uses live BID against closed-bar candle data L139 ; breakout volume uses`iVolume` shift 0 L545 ; false-breakout uses rates start=0 plus live price L587-601 ; EMA/ATR reads shift 0 ( L176 , L321 ).
- Logic/dead code : "psychological levels" are merely 11 levels at ±0.01/0.001 increments around current BID L337-368 , not round-number price levels; bounce direction derives from`price >= level.price` and ignores`isSupport` L173 ;`roleReversed` is mutated on a local struct copy L507 / L518 (no effect); trendline`touches++` on a local copy L775 is not persisted. Anchor-order bug was fixed Batch156 L405-415 .
## 8. Candlestick cluster
StrategyCandlestick.mqh +`CandlestickFiles/` (CandleAnalyzer, ConfluenceScorer, PinBar, Engulfing, Doji, Hammer, Harami, Star, Piercing, ThreeSoldiers)

- Cleanest timing discipline in the suite: every pattern judged on the closed bar barIndex=1; analyzer ATR shift 1 L110 . Priority: star→soldiers→engulfing→harami→piercing→pin→hammer→doji L312-473 ; confidence = 0.5·pattern strength + 0.5·confluence (50 pattern / 30 level / 20 trend, gate 70); SL = swing(5) padded, TP at 2.5R L281-292 ; risk validation present.
- Issues :`m_weight = 1.5` hardcoded L90 ; unused`PATTERN_*` enum values L29-50 ; Star's`gapDown` computed but never tested L56 ; PinBar and Hammer geometry near-duplicate and PinBar is evaluated first, making Hammer largely unreachable; a standard Doji (trend-neutral by definition) still emits a directional trade L79-87 ; ThreeSoldiers comment claims opens-within-prior-body but only monotonic opens are checked L52 . Magic 0.
## Cross-file synthesis
- Consensus/risk integration is uniform except two strategies : RangeCompression skips`ValidateWithRiskManager` entirely and emits no`[CONSENSUS-DIAG]` ; StatArb hand-rolls the diag format. Every other strategy routes through the base class (`GetSignal(double&)` → virtual`ExecuteSignal` , StrategyBase L299 ;`ValidateWithRiskManager` L491 ;`LogConsensusDiag` L523 ).
- Magic numbers : all constructors pass`magic = 0` — no hardcoded nonzero magics in strategies. The hardcoded numeric literals that matter are behavioral: 5-point BE buffer (Trend), 1.5 candlestick weight, ±0.01/0.001 "psychological" grid, StatArb β=1.0.
- Handle ownership is mostly correct after Batches 150/155/156/158 : oldest-first CopyBuffer indexing is now consistently applied; the one remaining cache-poisoning release is MeanReversion L127. Per-call handle creation (TrendEntryTypes non-14 ATR) and per-bar iTime/iHigh loops (SR) remain performance leaks, not resource leaks.
- Remaining repaint surface clusters on shift-0 / live-price reads : SR bounce & breakout, MeanRev ADX, ADX sizer, trailing ATR, RangeComp trend MA, TrendEntry live BID, SimpleMomentum fallback CopyRates. These make signals mutable within the forming bar even though final evaluation generally lands on closed bars.
- Confidence values across the suite are uncalibrated heuristics (ad-hoc multipliers, max-of-4, 0.5/0.5 blends); they drive position sizing and consensus weighting without any historical calibration.
- Position sizing is decorative in most paths : nearly every strategy emits broker min lot; only SimpleMomentum actually consumes the sizer, undermining ADXPositionSizing's entire purpose.
## Top 5 issues, ranked by severity
1. StatisticalArbitrage is pseudo-arbitrage — fixed β=1.0, raw price-level spread, correlation mislabeled as cointegration (`IsCointegrated` is a dead correlation wrapper, no ADF/EG), 50-bar window,`PERIOD_CURRENT` , and only one leg ever executes (`ExecutePairTrade` dead; leg-2 lots discarded). It is an unhedged directional strategy wearing a market-neutral name, with single-leg stops sized from a two-leg spread sigma. file
2. MeanReversion releases a shared cached handle —`IndicatorRelease(m_stochHandle)` L127 invalidates the`CIndicatorManager` cache for all consumers (Batch 156 defect class), risking INVALID_HANDLE failures across strategies at runtime.
3. Systematic forming-bar/live-price repainting — shift-0 reads and live BID in SR bounce/breakout/false-breakout, MeanRev/ADX-sizer ADX, TrendTrailingStop ATR, RangeComp trend MA, TrendEntryTypes, and SimpleMomentum's fallback path; intrabar-decided signals can flip before bar close.
4. RangeCompression lifecycle & risk bypass — never calls base`Init` (`m_is_initialized` unset), overrides`ExecuteSignal` without`ValidateWithRiskManager` (violates invariant §3.1), misreports strategy type, inflates squeeze counter per poll, and emits no consensus diag.
5. O(n²) full re-scans make the SR cluster portfolio-non-scalable — 300-bar clustering + touch loops and 200-bar trendline scans with hundreds of`iTime/iHigh/iVolume` calls every bar per symbol ; compounded by MeanReversion's up-to-100-CopyBuffer band-width filter and TrendEntryTypes' per-call handle churn.
Honorable mentions : VolatilityBreakout's four accidentally-correct SELL ternaries ( L589-641 ) are a one-character-edit-away stop reversal; TrendTrailingStop's re-seeded watermark disables its trailing logic; SimpleMomentum's duplicate`point` is confirmed legal nested-scope shadowing (redundant, not a compile error); Doji emits directional trades; PinBar starves Hammer; confidence numbers are uncalibrated portfolio-wide.

Verification : static read of all listed files plus targeted re-read of SimpleMomentumStrategy L655-879 confirming the L666/L863`point` declarations occupy distinct (nested) scopes. No compilation performed (research-only task; no edits made).
---
ummary:

# AI/ML Stack Audit — metatrader-multistrategy-ea
Research-only audit; no code modified. All citations are to code directly inspected.

## 1. NeuralNetworkStrategy.mqh — a genuine online MLP, genuinely backprop-trained
The live neural net is a fixed 70→32→16→8→3 MLP with static weight matrices NeuralNetworkStrategy.mqh L307-314 , ReLU hiddens and a 3-class softmax (0=NONE, 1=BUY, 2=SELL). Initialization is Gaussian scaled by`sqrt(2/(fan_in+fan_out))` ( L492-508 ).

The backprop is real. Output delta for softmax cross-entropy is`outputs[i]-1` ( L722-724 ); ReLU gradients use explicit`(hidden>0)?1:0` masks ( L726-751 ); each weight gets a true AdamW update (β1=.9, β2=.999, wd=1e-4, lr=3e-4, L551-559 ) with cosine-cyclic LR ( L544-549 ). Training is deliberately shallow: only the last 256 samples, 2 epochs, every 10 resolved labels ( L1934-1961 ).

Normalization is statistically wrong. An EMA mean (α=0.02) and EMA second-moment M2 are tracked ( L561-583 ), but`NormalizeFeatures` divides M2 by`(m_featureCount-1)` ( L596 ) — a population/sample-count divisor applied to an exponentially-weighted second moment. The resulting "std" is not a variance; only the ±3 clip ( L585-601 ) masks the damage, and degenerate variance yields std≈3.16e-5, i.e. every feature saturates the clip. Cold-start path clips raw features with no scaling at all ( L587-592 ).

Gating is serious. Signals rejected before 30 resolved labels ( L879-883 ), confidence ≥0.70, split-conformal gate ( L51-142 ), MetaLabeler approval ≥0.52 ( L888 ).

## 2. TransformerBrain.mqh — real attention mechanics, but only the head learns
The encoder is architecturally genuine: pre-norm, RoPE with`theta=10000^(-2i/d)` ( TransformerBrain.mqh L85-131 ), multi-head Q/K/V attention scaled by`1/sqrt(dHead)` with numerically stable softmax ( L355-461 ), ReLU FFN, residuals, mean-pool ( L885-928 ).

But no gradient ever reaches the encoder.`TrainStep` only calls`UpdateClassificationHead` ( L762-802 ); QKV/attention/FFN weights are LCG-random ( L343-350 ) and frozen forever — there is no backward path through attention. Runtime reality: a random frozen nonlinear feature extractor with a trained linear/softmax head (plus a 10-class pattern head). The head itself is trained properly — AdamW, cyclic LR, even an EWC regularizer with Fisher-diagonal estimates ( L16-63 , L662-835 ). Persistence (`SaveHeadState` , magic 1414677859 v2) stores head weights + Adam moments only, no checksum, no encoder ( L1119-1253 ).

EnsembleMetaLearner runs 4 such brains (seq 20/40/60/30) with softmax averaging weighted by EMA performance, regime multiplier and half-Kelly sizing ( EnsembleMetaLearner.mqh L491-587 ); its HMM regime detector is a real forward-filtering 4-state model with count-learned transitions ( L20-209 ). Same frozen-encoder caveat applies to all four.

## 3. MetaLabeler — genuine, but ephemeral
A real 26→24→2 MLP with sigmoid, mini-batch AdamW, grad-norm clip 1.0, BCE, 8 steps × batch 12 every 50 samples ( MetaLabeler.mqh L126-256 , L467-493 ). It is never saved — every restart wipes it.`RecordOutcome` 's rolling-winrate reassignment on buffer overflow is buggy ( L413-426 ).

## 4. Inference → vote → consensus
Each model reaches consensus only through strategy adapters, which emit throttled`[AI-VOTE]` heartbeats with vote tallies: AIStrategyAdapter.mqh L59`[AI-VOTE][NeuralNet]` , TransformerAIStrategyAdapter.mqh L144 , EnsembleAIStrategyAdapter.mqh L148 , OnnxAIStrategyAdapter.mqh L112 (plus a PythonBridge adapter). AIEngine itself does no neural inference — it is an orchestration/weight-mutation shell ( AIEngine.mqh ).

## 5. Online learning and the self-reinforcement problem
Triple-barrier self-labeling is real: ±K·ATR barriers (K 1.5–2.5, vertical 12–40 bars), resolved once per closed bar with a same-bar purity guard ( L985-1081 ). But:

- Self-labeling defaults on ( L1549 ); when the net predicts NONE, labels are fabricated from 5-bar momentum ±0.001 ( L1108-1147 ).
- The trade-linked label guard (`AI_MIN_TRADE_LINKED_LABELS=5` ) is explicitly bypassed with a bootstrap comment:`ReservePredictionForSignal` /`UpdateTradeResult` are not wired to execution ( L1915-1932 ). The net therefore learns almost entirely from its own barrier outcomes, never from realized P&L. EnsembleMetaLearner does receive trade results ( L798-828 ), so only the ensemble's weighting (not its encoders) sees ground truth.
Offline tools don't close the loop. TrainingDataExporter emits real triple-barrier labels (1/−1/0, ATR×0.5, horizons 5/10/20; TrainingDataExporter.mq5 L402-427 ). MQHModelTrainer genuinely trains a 70→32→16→8→3 net with Adam + L2 ( MQHModelTrainer.mq5 L43-209 , FeedForwardNN.mqh L193-246 ) — but`SaveCheckpoint()` is a no-op stub returning true ( FeedForwardNN.mqh L280-283 ). Nothing trained offline can reach the live EA, and label encodings/preprocessing are incompatible anyway (offline −1/0/1→0/1/2 via LabelEncoder.mqh L35-43 , separate z-score normalization; live uses 0=NONE/1=BUY/2=SELL + EMA scaler, checkpoint v8).

## 6. Persistence, versioning, corruption recovery
Live NN checkpoint: magic 1313758027, format v8, symbol/timeframe-scoped, atomic temp→primary copy with`.prev` backup ( NeuralNetworkStrategy.mqh L1170-1541 ; NNModelStorage.mqh L126-148 ). Load validates magic/version/symbol/tf/truncation/NaN. Two weaknesses: the checksum covers only weights + mean/M2 — not training buffers, barriers, Adam moments or counters ( L1283-1349 ); and a parallel`CCheckpointManager` exists with a divergent, best-effort, checksum-optional format ( CNeuralCheckpointManager.mqh L193 , L409-483 ) and appears unused by live inference. PipelineScaler correctly maps degenerate scales ≤1e-6 to 1.0 ( PipelineScaler.mqh L88 ).

## 7. ONNX — the real thing
OnnxBrain.mqh makes genuine calls:`OnnxCreateFromBuffer` with`ONNX_DEFAULT` →`ONNX_USE_CPU_ONLY` fallback ( L66-113 ), fixed`[1,60,70]` /`[1,3]` shapes, and a real `OnnxRun(handle, ONNX_NO_CONVERSION, matrixf, vectorf)` ( L131 ) over a rolling 60×70 float ring, with softmax + NaN checks. Init retry/backoff (3 tries, 1→30 min) is in ONNXInitManager.mqh . Caveats: class ordering 0=SELL/2=BUY differs from the live NN; scaler-load failure silently feeds unscaled features ( FeaturePipelineONNX.mqh L68-75 ); accuracy counters are dead getters never incremented.

## 8. Failure modes and dead/misleading code
- UniversalTransformerService : never calls`TrainStep` — its encoder is untrained; the per-symbol "adaptation head" drifts weights by ×1.01/×0.99 Hebbian rules with no persistence ( UniversalTransformerService.mqh L134-349 ).
- NextGenStrategyBrain discards model probabilities and fabricates`directional = Σ value·±1` with an invented`noneProb=0.25+1/(1+stability)` ( NextGenStrategyBrain.mqh L118-133 ); header admits it is not a voter.`SaveAIState` has no load counterpart.
- `CBarrierLabelResolver` duplicates the live resolver with inverted classes and a do-not-wire warning ( NeuralNetworkStrategy.mqh L267-285 ); a third copy sits in CNeuralTrainingDataManager.
- `CNeuralCore::ComputeGradients/ClipGradientsFull` are used only by the offline trainer, never live (live inlines its own backprop).
- AIEngine:`AdaptToRegime` has an empty body ( L1156-1159 ); expired weight modifications are counted but never reverted ( L1180-1190 ); an external Ollama`WebRequest` ( L619-677 ) keyword-scrapes LLM prose and mutates live strategy weights (default disabled; high blast radius if enabled).
- UncertaintyQuantifier outputs uncalibrated heuristic averages; VaR/Bayesian helpers unused. AIPerformanceFeedback`TriggerRetraining` only writes files.
- Stale comments: feature builder ships 70 features but headers/name loops still say 65 ( AIFeatureVectorBuilder.mqh L817 ).
## 9. Hot-path performance
- `BuildTransformerInput` rebuilds the entire 70-feature vector 10 times per sequence build ( L771-792 ); each build performs indicator CopyBuffers plus`CopyTicks` of 128 ticks (OFI) and 256 ticks (spike timing) ( L678-679 ).
- Transformer attention is O(heads·seq²·dHead) with`ArrayResize` allocations inside per-head/per-token loops ( TransformerBrain.mqh L371-374 ).
- Per-signal`iStochastic` create/release churn ( NeuralNetworkStrategy.mqh L857-864 ); conformal quantile full-sorts per insertion; permutation importance runs 70 extra forward passes + O(n²) bubble sort every 200 signals ( L2012-2056 ). Partial mitigations: per-bar+10 s signal cache, 20×10 s transformer cache.
- NaN/handle defenses exist broadly (feature sanitize NaN→0, clamp ±10; ONNX NaN checks; invalid-number guards), but scaler failure is silent and the EMA-normalization bug converts variance anomalies into saturated features rather than errors.
## Genuine vs aspirational — synthesis
Genuine: the online MLP's backprop/AdamW, gates and conformal layer; MetaLabeler training; ONNX inference (real`OnnxRun` , real CPU fallback, retry/backoff); the HMM regime filter; barrier mechanics; checkpoint atomicity/versioning for weights.

Aspirational: "Transformer intelligence" is a random frozen encoder plus a trained linear head, in all five transformer instances; offline training is real math ending in a no-op save, so no pretrained model ever reaches live; Universal/NextGen layers ignore softmax outputs in favor of fabricated directional scores; trade-outcome learning is admitted-unwired, leaving the online net to train on self-generated labels — a closed self-referential loop with momentum-fabricated fallback labels; "AI Engine" regime adaptation is an empty stub.

## Top 5 issues by severity
1. Frozen-random transformer encoders voted as AI intelligence ( TransformerBrain.mqh L762-802 ) — all Transformer/Ensemble/Universal votes rest on untrained random projections; only a linear head learns, and the encoder isn't even persisted. Highest severity: capability is fundamentally misrepresented at the vote layer.
2. Self-referential training loop with trade-feedback gate bypassed ( NeuralNetworkStrategy.mqh L1915-1932 , L1108-1147 ) — online NN learns from its own barrier/momentum labels, never realized P&L; confidence/calibration measures a self-consistent fantasy. Wire`UpdateTradeResult` or disable self-labeling.
3. Fabricated scores replacing model outputs in NextGen/Universal paths ( NextGenStrategyBrain.mqh L118-156 ) plus silent unscaled-feature fallback in the ONNX pipeline — inputs to voting are not what logs imply.
4. Hot-path cost explosion — 10× full 70-feature rebuild per transformer sequence with 384-tick`CopyTicks` each, iStochastic handle churn, attention O(seq²) with inner-loop allocations; real risk of tick backlog under multi-symbol load.
5. Persistence/normalization integrity — checkpoint checksum excludes buffers/Adam/counters with a second divergent checkpoint manager; EMA-M2 divided by sample count produces invalid standard deviations ( L596 ); offline trainer's save is a stub; inverted-class dead resolver is a trap for future wiring.
Verification:

- All claims above come from direct Read/Grep/Glob inspection of the 25+ files listed in the handoff brief plus MQHModelTrainer.mq5, TrainingDataExporter.mq5, FeedForwardNN.mqh, LabelEncoder.mqh, TrainingSession.mqh and grep-confirmed`[AI-VOTE]` sites in all five Core/Strategy adapters.
- No code was modified; research-only task — no compile or runtime validation applicable.
Gaps & Unverified:

- Adapter internals beyond the`[AI-VOTE]` log sites (exact signal→consensus mapping, rejection reason plumbing) were grep-verified, not fully read.
- Whether AIPerformanceFeedback has live call-sites was not exhaustively confirmed.
- Runtime log evidence (actual vote participation, timings) was not collected — static audit only, consistent with the delegated scope.
Artifacts:

- No files created or changed. Key paths:`AIModules/` (NeuralNetworkStrategy, TransformerBrain, OnnxBrain, EnsembleMetaLearner, MetaLabeler, NextGenStrategyBrain, UniversalTransformerService, CNeuralCheckpointManager),`Core/AI/` (AIFeatureVectorBuilder, FeaturePipelineONNX, PipelineScaler, NNModelStorage, ONNXInitManager),`Core/Engines/AIEngine.mqh` ,`Core/Strategy/*AIStrategyAdapter.mqh` ,`MQHModelTrainer/` ,`TrainingDataExporter.mq5` .
Next Action:

- If remediation is authorized, attack issue #2 first (wire trade-result labels / gate self-labeling) since it silently corrupts the one genuinely trained live model; #1 requires either real encoder backprop or honest relabeling of transformer votes as head-only.
---
