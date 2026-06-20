# AI Division Problems & Issues Log
**Project:** metatrader-multistrategy-ea (aMQH AI Division)  
**Date:** 2026-06-20  
**Focus:** Profit impact, reliability, edge decay, live trading robustness  
**Status:** Initial sniff — high-severity items first. Will be updated iteratively.

---

## CRITICAL (Direct P&L / Reliability Killers)

### 1. Inconsistent / Duplicate Data Structures [RESOLVED 2026-06-20]
**Files:** `NeuralNetworkStrategy.mqh`, `CNeuralTrainingDataManager.mqh`  
**Issue:** `STrainingExample` / `SBarrierEntry` defined in NeuralNetworkStrategy vs `SMTrainingExample` / `SMBarrierEntry` in CNeuralTrainingDataManager. Checkpoint save/load in NeuralNetworkStrategy uses its own structs while manager uses SM*. High risk of data corruption or lost labels on restart.  
**Profit Impact:** Online learning breaks → model stops improving or learns from corrupted labels → edge decay.  
**Priority:** P0 — Unify into single structs in one header.

### 2. Broken Include Paths & Missing NNModelStorage [RESOLVED 2026-06-20]
**Files:** `CNeuralCheckpointManager.mqh` (line 9: `#include "../Core/AI/NNModelStorage.mqh"`)  
**Issue:** All files are flat in attachments/. Real project structure (Core/AI/, Strategies/) does not exist here. `NNModelStorage_EnsureFolders()`, `GetTempPath()`, `PromoteTempToPrimary()` are undefined.  
**Profit Impact:** Checkpoints fail silently or crash EA on init/restart → loss of trained state and historical labels.  
**Priority:** P0 — Either create the missing NNModelStorage.mqh or refactor checkpoint manager to self-contained atomic I/O.

### 3. Hot-Swap Promotion Uses Accuracy Only (No Expectancy)
**File:** `OnnxBrain.mqh` (RecordOutcome + promotion logic)  
**Issue:** Shadow model promoted if `shadowAcc > activeAcc + 0.01`. No consideration of profit factor, average win/loss, max DD, or expectancy. Can promote a high-winrate but low-R:R model.  
**Profit Impact:** Direct degradation of live expectancy.  
**Priority:** P0 — Change promotion to expectancy or risk-adjusted metric. Add shadow vs active trade simulation.

### 4. EWC Only Protects Classification Head
**File:** `TransformerBrain.mqh` (UpdateClassificationHead, AnchorEWC)  
**Issue:** Elastic Weight Consolidation penalty only applied to classification head weights. Transformer blocks + pattern head are unprotected.  
**Profit Impact:** Catastrophic forgetting of profitable patterns when regime changes or new data arrives.  
**Priority:** P1 — Extend EWC to full model (or at least attention/FFN weights).

### 5. Extremely Slow Adaptive Normalization
**File:** `NeuralNetworkStrategy.mqh` (m_normalizationDecay = 0.001)  
**Issue:** EMA decay factor is 0.001. In fast regime shifts or volatility changes, feature stats lag badly.  
**Profit Impact:** Features become mis-scaled → model outputs garbage → bad signals or missed trades.  
**Priority:** P1 — Make decay configurable or adaptive (e.g. based on regime volatility).

### 6. UncertaintyQuantifier Uses Wrong Volatility Proxy
**File:** `UncertaintyQuantifier.mqh` (CalculateHistoricalVolatility)  
**Issue:** Calculates "volatility" from prediction history (signal values) instead of actual price returns / ATR / realized vol.  
**Profit Impact:** Mis-calibrated uncertainty → either over-sizing in real volatile markets or under-sizing in calm ones.  
**Priority:** P1 — Replace with proper realized volatility or ATR-based measure.

### 7. Kelly Reweighting Too Slow + Simplistic Regime Multiplier
**File:** `EnsembleMetaLearner.mqh` (UpdateKellyWeights, CalculateModelWeight)  
**Issue:** Kelly updated only every 10 resolved trades. Regime multiplier is hardcoded and weak (1.15/1.20).  
**Profit Impact:** Slow capital re-allocation to currently winning models/regimes → lower overall expectancy.  
**Priority:** P1 — Increase update frequency and make regime multipliers learned or stronger.

### 8. MetaLabeler Trains Too Aggressively
**File:** `MetaLabeler.mqh` (AddSample + TrainStep trigger at bufCount >= 50)  
**Issue:** Calls TrainStep(8,12) inside AddSample as soon as 50 samples. Can trigger training on almost every bar in active markets.  
**Profit Impact:** Overfitting to recent noise + compute spikes on tick thread.  
**Priority:** P1 — Move training to timer / lower frequency or add cooldown.

### 9. Checkpoint Checksum Only in One Place
**Files:** `NeuralNetworkStrategy.mqh` (has checksum), `CNeuralCheckpointManager.mqh` (no checksum)  
**Issue:** Manager does atomic promote but no integrity check. NeuralNetworkStrategy adds checksum only at end. Inconsistent.  
**Profit Impact:** Risk of loading silently corrupted weights after crash/power loss.  
**Priority:** P1 — Add checksum to CNeuralCheckpointManager save/load.

### 10. UniversalTransformerService Training Steps Stubbed
**File:** `UniversalTransformerService.mqh` (GetUniversalEncoderTrainingSteps returns 0)  
**Issue:** Hardcoded stub. No real training progress exposed for the shared encoder.  
**Profit Impact:** Monitoring & debugging of continual learning broken for multi-symbol setups.  
**Priority:** P2 — Implement proper step counter passthrough.

---

## HIGH (Significant Edge / Robustness Risks)

### 11. Hard-coded Constants Everywhere
**Many files** (ONNX_SEQ_LEN=60, dModel=32/64, seqLen in NextGen, etc.)  
**Issue:** Magic numbers scattered. No central config or per-symbol tuning.  
**Profit Impact:** Sub-optimal hyperparameters for different asset classes (synthetics vs forex).  
**Priority:** P1 — Create central AIConfig.mqh or input parameters.

### 12. No Visible Integration with Final Risk/Position Sizing
**AI files** (no clear link to UnifiedRiskManager or position sizing in provided code)  
**Issue:** AI produces signal + confidence/uncertainty, but final lot size, max DD, correlation filters appear outside these modules.  
**Profit Impact:** Good AI signal can still blow up if risk layer is weak or disconnected.  
**Priority:** P1 — Audit EnterpriseStrategyManager / risk layer for how AI uncertainty is consumed.

### 13. Triple-Barrier Self-Labeling Noise
**Files:** `CNeuralTrainingDataManager.mqh`, `NeuralNetworkStrategy.mqh` (ResolveExpiredBarriers + CBarrierLabelResolver)  
**Issue:** Live barrier resolution uses current price at expiry. Slippage, spread, and partial fills not modeled.  
**Profit Impact:** Noisy / biased labels → model learns wrong things.  
**Priority:** P2 — Add realistic exit simulation or minimum barrier width filter.

### 14. Ugly / Fragile Modulo for Negative Indices
**File:** `OnnxBrain.mqh` (RunHandle: `m_head - ONNX_SEQ_LEN + t + ONNX_SEQ_LEN * 1000`)  
**Issue:** Hacky way to handle negative modulo.  
**Profit Impact:** Potential off-by-one in sequence window → wrong features fed to ONNX model.  
**Priority:** P2 — Replace with proper positive-modulo helper.

### 15. Global Singletons Risk
**Files:** `UncertaintyQuantifier.mqh` (g_uncertaintyQuantifier), `UniversalTransformerService.mqh` (g_universalTransformerService), `EnsembleMetaLearner.mqh` (internal)  
**Issue:** Global pointers + init in headers. Multiple EAs or multi-symbol can collide.  
**Profit Impact:** State corruption across charts/symbols.  
**Priority:** P2 — Move to per-EA instance or proper singleton with symbol key.

### 16. Feature Importance Computation Cost
**File:** `NeuralNetworkStrategy.mqh` (CFeatureImportance::Update)  
**Issue:** Permutation importance runs full forward pass per feature every evalInterval (default 100). Expensive on high feature count.  
**Profit Impact:** Can cause tick delays or dropped updates if many symbols.  
**Priority:** P2 — Make optional or reduce frequency / use cheaper importance method.

### 17. CRoPEEncoding Numerical / Implementation Details
**File:** `TransformerBrain.mqh` (CRoPEEncoding)  
**Issue:** Theta calculation inside pos loop but only even/odd pairs rotated. Scaling and maxSeqLen handling could cause instability for longer sequences.  
**Profit Impact:** Degraded long-range pattern capture in transformer.  
**Priority:** P2 — Review against standard RoPE implementation and add tests.

### 18. Early Stopping in MetaLabeler May Be Too Aggressive
**File:** `MetaLabeler.mqh` (ShouldStopEarly, patience=10 on 20-loss history)  
**Issue:** Stops if recent loss not improving by tiny threshold. Can halt learning prematurely on noisy financial data.  
**Profit Impact:** Model stops adapting.  
**Priority:** P2 — Make patience/threshold configurable or add minimum training steps.

---

## MEDIUM / TECH DEBT

- Duplicate barrier/training buffer logic across NeuralNetworkStrategy and CNeuralTrainingDataManager.
- Lack of NaN/Inf guards in several forward/backprop paths (some exist but not comprehensive).
- No model A/B testing or shadow deployment metrics beyond accuracy (OnnxBrain).
- Regime detection (HMM + legacy) has two paths; legacy still referenced in places.
- Symbol classification in UniversalTransformerService is name-based only (no runtime behavior profiling).
- No explicit handling of spread/slippage in any AI signal generation or labeling.
- Checkpoint version magic in multiple places (TRANSFORMER_HEAD_STATE_MAGIC, NN_CHECKPOINT_MAGIC) — risk of mismatch on upgrades.
- Performance tracking in NextGenStrategyBrain and Ensemble is simple (winrate/return) — no Sharpe, Calmar, or expectancy tracking.

---

## LOW / FUTURE

- Logging frequency (some every bar, some throttled) could be centralized.
- No GPU/ONNX batching optimizations visible.
- Documentation in code is uneven (some classes well commented, others not).
- No unit tests or backtest harness visible for the AI modules.

---

**Next Actions (proposed):**
1. Fix #1 (structs) + #2 (include paths) — unblock compilation & state persistence.
2. Upgrade OnnxBrain promotion (#3) to expectancy-based.
3. Extend EWC (#4) and speed up normalization (#5).
4. Review risk layer consumption of uncertainty (#12).

**How to use this file:**  
Add new issues with `**File:**`, `**Profit Impact:**`, `**Suggested Fix:**`.  
Mark resolved with `[RESOLVED YYYY-MM-DD]`.

---
---

## NEW ISSUES FROM .md DOCS (SYSTEM_STRUCTURE, RUNTIME_DECISION_GRAPH, MAINTENANCE_PROTOCOL, changelogs, SYSTEM_AUDIT_TRACE)

### 19. Neural Weight Mutation Not Gated Behind Real Trade-Linked Labels (Critical)
**Files:** `NeuralNetworkStrategy.mqh` (TrainNetwork, BackpropagateAndUpdate, self-labeling path)  
**Source:** SYSTEM_STRUCTURE.md §2.6 "gate neural weight mutation behind real trade-linked labels so pseudo-label accumulation alone cannot drive online weight drift"  
**Issue:** Self-labeling / barrier resolution can generate labels without corresponding live trades. If `m_tradeLinkedLabels` gate is not strictly enforced before every weight update, noisy pseudo-labels pollute the model.  
**Profit Impact:** Model drifts toward overfitting recent noise instead of proven profitable patterns. Expectancy erosion over time.  
**Priority:** P0 — Audit and enforce `if (m_tradeLinkedLabels < threshold) return;` or equivalent before any AdamW / backprop step.

### 20. AI Modules Lag Behind Batch 105 Hygiene Standards
**Files:** All core AI (`NeuralNetworkStrategy.mqh`, `TransformerBrain.mqh`, `OnnxBrain.mqh`, `CNeural*`, adapters)  
**Source:** changelogs.md (Batch 105) + MAINTENANCE_PROTOCOL.md 1.5  
**Issue:** Batch 105 did massive cleanup (CIndicatorManager unification, null guards for risk manager, SafeCopyBuffer, ghost decl removal, handle leak fixes) across 30+ files — **none of the core AI .mqh files appear in the modified list**. Raw indicator access, missing null checks, and duplication likely still present in feature builders and inside NN/Transformer.  
**Profit Impact:** Higher crash risk, indicator handle leaks, repainting potential in derived features, inconsistent style with rest of enterprise codebase.  
**Priority:** P1 — Run same audit pass on AI division (replace raw i* with CIndicatorManager where used, add risk manager null guards, dedup).

### 21. Checkpoint Hash Implementation Mismatch
**Files:** `NeuralNetworkStrategy.mqh` (ComputeCheckpointChecksum), `CNeuralCheckpointManager.mqh`  
**Source:** SYSTEM_STRUCTURE.md §2.7 "Checkpoint Integrity Validation: 128-bit hash using two xorshift generators... Validated on load - rejects corrupted checkpoints with REJECTED_CHECKSUM_MISMATCH"  
**Issue:** Docs describe proper 128-bit dual-xorshift hash. Actual code uses simpler ulong checksum. Manager itself has no checksum at all.  
**Profit Impact:** Higher chance of loading corrupted weights after crash → silent bad model in production.  
**Priority:** P1 — Align implementation with documented 128-bit hash + make CNeuralCheckpointManager use it.

### 22. Minimum 0.70 AI Confidence Floor Not Clearly Enforced
**Source:** SYSTEM_STRUCTURE.md §2.6 "enforce a 0.70 minimum runtime confidence floor for the hardened AI defaults"  
**Files:** Adapters (`*AIStrategyAdapter.mqh`), `EnterpriseStrategyManager.mqh`, `NeuralNetworkStrategy.mqh` / `TransformerBrain.mqh`  
**Issue:** Hard requirement exists in architecture doc but no obvious central enforcement visible in the AI brains or adapters provided.  
**Profit Impact:** Low-confidence AI signals can leak into live trading or consensus, diluting overall edge.  
**Priority:** P1 — Add explicit gate (probably in CAIEngine or EnterpriseStrategyManager AI path).

### 23. NextGenStrategyBrain / UniversalTransformerService Role Ambiguity
**Source:** SYSTEM_STRUCTURE.md §2.6 "CNextGenStrategyBrain / Universal Transformer = local feature brain, not a direct live voter"  
**Files:** `NextGenStrategyBrain.mqh`, `UniversalTransformerService.mqh`, adapters  
**Issue:** Docs clearly state it is a **feature provider only**. If any path treats its output as a direct vote/signal for execution, it violates topology.  
**Profit Impact:** Blurred responsibility → potential double-counting or bypassing of proper IAIStrategy adapters and risk veto.  
**Priority:** P2 — Audit call sites; ensure it only feeds features into the real voters (Neural/Transformer/Ensemble/ONNX adapters).

### 24. Widespread Violation of Maintenance Protocol Code Quality Rules
**Source:** MAINTENANCE_PROTOCOL.md §1.5 (Memory safety/RAII, Input validation on all public methods, Eliminate magic numbers, Error handling + graceful degradation)  
**Files:** Most AI classes (TransformerBrain::Forward, OnnxBrain::RunHandle, EnsembleMetaLearner, MetaLabeler, etc.)  
**Issue:** Many public methods lack parameter/bounds validation. Magic numbers still everywhere. Some error paths (failed shadow model, bad ONNX buffer) do not degrade gracefully to safe defaults.  
**Profit Impact:** Runtime instability, harder debugging in live, potential silent bad decisions.  
**Priority:** P1 — Systematic pass: add validation guards, replace magic numbers with defines/constants, ensure every AI failure path has safe fallback (no-trade or indicator-only).

### 25. AI Observability & Log Tags Incomplete
**Source:** MAINTENANCE_PROTOCOL.md §1.3 + RUNTIME_DECISION_GRAPH.md + SYSTEM_STRUCTURE.md  
**Issue:** Required tags like `[AI-VOTE]`, `[CONSENSUS-DIAG]`, `[SIGNAL-REJECTED]`, heartbeat, and explicit AI topology diagnostics are mandated but coverage in the provided AI modules is patchy or missing in several classes.  
**Profit Impact:** Poor visibility into why AI signals are accepted/rejected or why models are healthy/unhealthy → slower debugging of edge loss.  
**Priority:** P2 — Add missing log signatures in key decision points (inference, training step, regime change, hot-swap decision, meta-labeler approve/reject).

### 26. Structure / Include Path Drift (AIModules/ vs flat)
**Source:** SYSTEM_AUDIT_TRACE.md + SYSTEM_STRUCTURE.md (references AIModules/ paths)  
**Files:** All AI files + includes  
**Issue:** Docs and audit trace assume AI modules live under `AIModules/` or `Core/AI/`. Current sandbox has everything flat. This will cause include failures and broken modular boundaries in real repo.  
**Profit Impact:** Build breaks, inability to maintain the "GOD TIER modular decomposition" achieved in Batch 92.  
**Priority:** P0 (for real deployment) — Align folder structure or update all includes to match actual layout.

---

**Summary of New Findings:**  
The .md documentation reveals that the **AI division has not yet received the full Batch 105 hygiene treatment** and has several architecture-level gaps (label gating, confidence floor, checkpoint hash, role clarity) that directly threaten long-term edge and reliability. These are now the highest-ROI targets for the next audit/fix phase.

---

## Recommended Fix Actions for Coding Agent (per issue)

For each issue below, implement the following (keep changes minimal, testable, profit-focused). Prioritize P0/P1 first. After each fix, update this file with `[RESOLVED YYYY-MM-DD]` + short note.

**Critical (P0)**
- **#1 Struct duplication**: Unify `STrainingExample`/`SBarrierEntry` into one header (e.g. `NeuralDataStructs.mqh`). Update all references in NeuralNetworkStrategy + CNeuralTrainingDataManager + checkpoint code. Add unit test for roundtrip save/load.
- **#2 Include paths / NNModelStorage**: Create minimal self-contained `NNModelStorage.mqh` (or inline the atomic promote logic) so CNeuralCheckpointManager compiles standalone. Or refactor checkpoint manager to use direct File* calls with proper temp→primary atomic rename.
- **#3 Onnx hot-swap promotion**: Change promotion condition from raw accuracy to expectancy or (winrate × avg payoff). Add shadow vs active simulated P&L tracking over the 100-bar window. Reject if shadow has worse max DD.
- **#19 Trade-linked label gate**: In `NeuralNetworkStrategy::TrainNetwork()` and backprop paths, add strict guard: `if (m_tradeLinkedLabels < 5 || m_resolvedLabelCount < 20) return;`. Also gate in `UpdateClassificationHead` / `TrainStep`. Log when blocked.

**High (P1)**
- **#4 EWC scope**: Extend `CEWCRegularizer` and `AnchorEWC` / `PenaltyGrad` calls to cover transformer block weights + pattern head (not just classification head). Store Fisher for full model.
- **#5 Normalization speed**: Make `m_normalizationDecay` an input parameter (default 0.01–0.05). Add regime-aware faster decay when HMM detects change.
- **#6 Uncertainty vol proxy**: Replace `CalculateHistoricalVolatility` with actual ATR or realized volatility from price series (use feature vector or iATR). Keep prediction history for separate "model uncertainty".
- **#7 Kelly update frequency**: Call `UpdateKellyWeights()` every resolved trade or every 3–5 instead of 10. Make regime multipliers stronger/learnable.
- **#8 MetaLabeler training freq**: Move `TrainStep` out of `AddSample`. Call it on timer (every 50–100 new samples or every 5–10 minutes) with cooldown.
- **#9 / #21 Checkpoint hash**: Implement proper 128-bit dual-xorshift hash (as documented in SYSTEM_STRUCTURE) in both NeuralNetworkStrategy and CNeuralCheckpointManager. Reject load on mismatch with clear log.
- **#20 Batch 105 hygiene on AI**: Port CIndicatorManager usage where raw indicators are still accessed in feature builders or inside NN. Add null guards for risk manager pointers. Replace manual buffers with SafeCopyBuffer where applicable.
- **#22 0.70 confidence floor**: Enforce in `EnterpriseStrategyManager` (or CAIEngine) for all AI adapters: if `GetCalibratedWeight()` or confidence < 0.70, downweight or block live authority.
- **#24 Protocol violations**: Add input validation + bounds checks to all public methods in TransformerBrain, OnnxBrain, EnsembleMetaLearner, MetaLabeler, CNeural*. Replace hard-coded seqLen/dModel/ONNX_SEQ_LEN with constants or inputs. Ensure every failure path (bad buffer, shadow fail, NaN) degrades to safe no-trade or fallback.
- **#12 / Risk integration**: Audit how `UncertaintyQuantifier::GetRiskAdjustedSize` and meta-labeler output flow into `CUnifiedRiskManager`. Wire uncertainty directly into position sizing and veto.

**Medium (P2)**
- **#23 UniversalTransformer role**: Add assert/comment in `NextGenStrategyBrain::GenerateSignal` and adapters that it only produces features, never direct TRADE_SIGNAL. Document clearly.
- **#25 Observability**: Add missing `[AI-VOTE]`, `[CONSENSUS-DIAG]`, regime change, hot-swap decision, and meta-labeler approve/reject logs with consistent format across all AI classes.
- **#10 / #26 Structure drift**: Align folder layout or update all `#include` paths to match documented AIModules/ structure. Update SYSTEM_AUDIT_TRACE if needed.
- **#11 / #13 / #14 / #15 / #16 / #17 / #18**: Replace magic numbers with defines, improve modulo safety, add proper realized-vol to uncertainty, reduce permutation cost (cache or subsample), review RoPE scaling, relax early stopping, add graceful singleton init.

After fixes, re-run compile + basic forward/backprop smoke tests on at least one symbol.

---

## Research-Backed Enhancements for the AI Division (from papers & quant literature)

**Goal:** Make the existing AI stack (Transformer + EWC, Ensemble + HMM + Kelly, MetaLabeler, Conformal Uncertainty, triple-barrier self-labeling, ONNX hot-swap) significantly more profitable and robust.

### 1. Strengthen Continual Learning (EWC)
**Findings (2024–2026 papers):**
- EWC is proven effective for non-stationary financial time series (stock trend prediction, forex). Transformers + flexible EWC prevent catastrophic forgetting while learning new regimes (Experience-accumulated Transformer / EAT model).
- Recent analysis (arXiv 2026) shows gradient-based Fisher estimation can be improved; standard EWC sometimes under-protects important weights.
- Hybrid approaches (EWC + small replay buffer or progressive nets) work well when memory allows.

**Recommendations for our code:**
- Expand EWC from classification head only to full Transformer blocks + pattern head (directly addresses issue #4).
- Make EWC regime-aware: maintain separate Fisher matrices per HMM regime (or anchor on regime change as we already do, but stronger).
- Add periodic Fisher refresh (not only on regime change) to adapt to slow distribution drift.
- Consider light replay of high-quality past labeled examples (trade-linked only) to complement EWC without exploding memory.

**Expected profit lift:** Slower edge decay in regime shifts + better long-term adaptation → higher sustained winrate / expectancy.

### 2. Upgrade Meta-Labeling (already strong foundation)
**Findings (Lopez de Prado "Advances in Financial Machine Learning" + multiple quant implementations):**
- Meta-labeling (secondary model that predicts *profitability* of primary signal) is one of the highest-ROI additions in modern quant pipelines. It filters false positives far better than raw confidence thresholding.
- Works especially well with triple-barrier labeling + event-driven sampling.
- Best results when meta features include: primary model outputs + uncertainty + regime probs + microstructure features.

**Recommendations:**
- Enhance `MetaLabeler` input features (issue #8 area) with: primary signal probabilities, conformal uncertainty, HMM regime state, recent model performance, symbol embedding.
- Consider upgrading the small MLP to a lightweight tree model (or keep MLP but add calibration) for better probability estimates usable in position sizing.
- Use meta-label probability directly for dynamic position sizing (Kelly or fractional) instead of hard filter only.

**Expected profit lift:** Fewer losing trades + better risk-adjusted returns (documented improvements in futures/equity studies).

### 3. Improve Uncertainty Quantification & Position Sizing
**Findings:**
- Conformal prediction provides distribution-free, rigorous uncertainty intervals and is gaining traction in finance for risk management and sizing.
- Our existing `CConformalPredictor` + `CUncertaintyQuantifier` is already close to best practice.
- Combining with regime detection and adaptive conformal methods improves coverage in non-stationary markets.

**Recommendations:**
- Make conformal scores regime-aware (separate quantiles per HMM state).
- Feed conformal uncertainty directly into `GetRiskAdjustedSize` and `CUnifiedRiskManager` (ties to issue #12).
- Add adaptive conformal prediction (update quantile online with recent errors) for better calibration during volatility spikes.
- Expose uncertainty to the ensemble/Kelly layer so low-confidence models get down-weighted faster.

**Expected profit lift:** Better capital preservation in uncertain regimes + higher allocation when model is confident → improved Sharpe / lower max DD.

---

## Next-Gen Architecture Proposal: Regime-Routed Mixture-of-Experts (MoE) Trading Brain + Meta-Adaptive Layer

**Vision (Profit-First)**: Move from a single large model / static ensemble to a **dynamic, regime-specialized sparse MoE system** where specialized experts are routed intelligently. Combine with an upgraded meta-adaptive layer for filtering, sizing, and fast adaptation. This directly attacks edge decay, regime shifts, and capital efficiency while leveraging almost everything already built.

**Core Principles**:
- Specialization beats generalization in non-stationary markets.
- Sparse activation = efficiency on tick.
- Regime awareness (your HMM) drives routing.
- Profitability filtering + uncertainty-aware sizing remains the final gate.
- Continual learning (EWC) + hot-swap preserved and enhanced.
- Backward compatible where possible; phased rollout.

### High-Level Architecture

```
Market Data / Features
        │
        ▼
UniversalTransformerService + Symbol Embedding (existing)
        │
        ▼
Regime Detector (enhanced HMM or learned router)
        │
        ▼
Router (lightweight MLP or HMM-informed) → Expert Weights / Top-K selection
        │
        ▼
MoE Layer: Multiple Expert Transformers (re-use / extend CTransformerBrain)
   - Expert 1: Short-horizon / Scalping specialist
   - Expert 2: Volatility / Spike specialist  
   - Expert 3: Trend / Momentum specialist
   - Expert 4: Mean-Reversion specialist
   - ... (more as needed)
        │
        ▼
Gated / Weighted Combination of Expert Outputs
        │
        ▼
Meta-Adaptive Layer (upgraded MetaLabeler + new Sizing Head)
   - Predicts: Profitability probability + Recommended risk multiplier + Suggested horizon
   - Uses: Primary outputs + conformal uncertainty + regime probs + expert performance + symbol embedding
        │
        ▼
UncertaintyQuantifier + Conformal (regime-aware)
        │
        ▼
Final Signal + Calibrated Confidence + Risk-Adjusted Size → EnterpriseStrategyManager / UnifiedRiskManager
```

### Key New / Enhanced Components

**1. CMoEBrain.mqh (new central class)**
- Holds array of expert `CTransformerBrain*` (different configs: seqLen, dModel, heads, learning rate).
- Lightweight `Router` (small MLP or direct use of HMM probabilities + feature projection).
- Training: Route sample → activate relevant experts → compute loss per expert + load-balancing auxiliary loss → backprop only active experts (or all with masking) + EWC.
- Inference: Router → top-k experts → weighted sum of predictions (or gated combination).
- Hot-swap: Support per-expert shadow models or full MoE hot-swap.
- Regime integration: Router can be conditioned on current HMM state.

**Pseudo Sketch (CMoEBrain)**

```mql5
class CMoEBrain {
private:
    CArrayObj          m_experts;           // Array of CTransformerBrain*
    CNeuralCore*       m_router;            // Lightweight router network (or use HMM probs)
    double             m_expertWeights[];   // Current routing weights
    int                m_topK;
    CEWCRegularizer    m_ewcPerExpert[];    // Or shared + per-expert

public:
    bool Forward(const double &features[], double &combinedProbs[]) {
        // 1. Get regime / router input
        double routerInput[];
        // ... build from features + current HMM state

        // 2. Router forward → expert weights
        m_router.Forward(routerInput, m_expertWeights);
        NormalizeWeights(m_expertWeights);  // or softmax

        // 3. Select top-k experts
        int activeExperts[];
        GetTopK(m_expertWeights, m_topK, activeExperts);

        // 4. Run active experts in parallel (or sequential)
        double expertProbs[][3];
        for(int i=0; i<ArraySize(activeExperts); i++) {
            int idx = activeExperts[i];
            CTransformerBrain* expert = m_experts.At(idx);
            double p[];
            expert.GetPredictions(features, p);
            expertProbs[i] = p;
        }

        // 5. Weighted combination
        CombineExpertOutputs(expertProbs, m_expertWeights, combinedProbs);
        return true;
    }

    bool TrainStep(const double &features[], const int targetClass, double &loss) {
        // Route + activate experts
        // For each active expert: expert.TrainStep(...) 
        // Add load balancing loss (encourage even expert usage)
        // Apply EWC (per-expert or shared)
        // Update router if learned
        return true;
    }
};
```

**2. Upgraded Meta-Adaptive Layer (enhance existing MetaLabeler + new CSizingHead)**

- Input features expanded: primary model logits/probs, conformal uncertainty, HMM regime vector, recent expert win rates, symbol embedding.
- Outputs: 
  - Profit probability (existing)
  - Recommended position size multiplier (0.0 – 2.0+)
  - Suggested barrier horizon / exit bias
- Can be a small MLP or tree model for better calibration.
- Training: On resolved trades (trade-linked labels) using triple-barrier outcomes.

**Pseudo for new sizing output**:
```mql5
double PredictRiskMultiplier(const double &metaFeatures[]) {
    // Forward through sizing head
    double logits[3]; // e.g. low / medium / high risk buckets or direct regression
    // ... 
    return SigmoidOrSoftmaxToMultiplier(logits);
}
```

**3. Enhancements to Existing Components (Research-Backed Advancements)**

**TransformerBrain advancements**:
- Research: Modern transformers for time series use SwiGLU FFN, ALiBi/xPos positional encodings (better length extrapolation), better initialization, layer-wise LR or AdamW variants.
- Twist: Add SwiGLU option in `CFeedForwardNetwork`. Experiment with ALiBi bias in attention for longer effective context without retraining.

**EWC advancements**:
- Research: Full-model EWC + online Fisher updates + combination with other regularizers improve stability in financial continual learning.
- Twist: Per-regime EWC matrices + periodic refresh. Light selective replay of high-quality (high confidence + profitable) past examples.

**EnsembleMetaLearner + HMM**:
- Research: Dynamic ensembles with performance decay and regime-specific weighting outperform static ones.
- Twist: Add exponential decay on old performance, Bayesian updating of expert weights, or learned router on top of HMM.

**MetaLabeler**:
- Research: Meta-labeling shines when fed rich features including uncertainty and regime. Probabilistic outputs + calibration improve sizing.
- Twist: Multi-task head (profit + horizon prediction). Proper probability calibration (Platt or isotonic). Use meta-prob directly for fractional Kelly sizing.

**Uncertainty + Conformal**:
- Research: Regime-conditional and adaptive conformal prediction improves coverage in non-stationary data.
- Twist: Separate nonconformity scores per HMM regime. Adaptive quantile updating. Output direct risk metrics (e.g., expected shortfall proxy) for `UnifiedRiskManager`.

**OnnxBrain hot-swap**:
- Research: Economic metrics (expectancy, PF, DD impact) + statistical tests beat simple accuracy for model promotion in trading.
- Twist: Track shadow vs active returns over window. Use paired statistical test or bootstrap for promotion decision. Support small pool of shadow candidates.

**UniversalTransformerService + Symbol Embedding**:
- Research: Learnable embeddings + adaptation heads help multi-asset / multi-regime models.
- Twist: Add contrastive or regime-prediction auxiliary loss on embeddings. Cross-symbol attention layer for correlated assets.

### Implementation Roadmap (Phased, Low Disruption)

**Phase 1 (Low risk, high value)**: 
- Enhance existing components (EWC scope, MetaLabeler features + calibration, conformal regime-awareness, hot-swap economic promotion). Update `problems.md` issues.

**Phase 2 (Medium)**:
- Implement `CMoEBrain` with 3-4 experts (reuse existing Transformer configs).
- Simple router based on current HMM + basic features.
- Integrate with `EnterpriseStrategyManager` / existing adapters as new AI family.

**Phase 3 (Higher ambition)**:
- Learned router + load balancing.
- Per-expert EWC + hot-swap.
- Full meta-adaptive sizing head wired to risk manager.
- Extensive backtesting + shadow deployment before live promotion.

**Migration Notes**:
- Keep `NeuralNetworkStrategy` as fast lightweight fallback or for lower-tier symbols.
- `NextGenStrategyBrain` / Universal service remains the feature provider.
- All new components implement `IAIStrategy` interface for seamless registration.
- Extensive use of existing checkpointing, training data manager, and uncertainty modules.

**Expected Overall Impact**:
- Materially slower edge decay through specialization + better continual learning.
- Higher win rate and expectancy via superior regime handling + meta-filtering + dynamic sizing.
- Better capital efficiency and drawdown control.
- More robust live operation with smarter hot-swap and uncertainty awareness.
- Scalable to more symbols and strategies without linear compute increase.

This proposal is ambitious but grounded in your current excellent architecture and the latest research in time-series MoE and meta-learning for finance. It positions the AI division as truly state-of-the-art within the MQL5 / retail quant space.

*Added 2026-06-20 — Detailed spec + research-backed advancements*

### 4. Ensemble + Regime + Hot-Swap Synergies
**Findings:**
- HMM regime detection + performance-weighted ensembles (Kelly-style) are standard in adaptive trading systems.
- Shadow / hot-swap models work best when promotion uses statistical tests (not just point accuracy) and considers economic metrics (expectancy, PF, DD).

**Recommendations (ties to #3, #7):**
- Upgrade OnnxBrain shadow promotion to use expectancy or profit-factor over the window + basic statistical significance test.
- Make EnsembleMetaLearner regime multipliers stronger and/or learned from recent performance per regime.
- Add model-level uncertainty (from conformal or entropy) into the ensemble weighting so uncertain models contribute less even if historically good.

**Expected profit lift:** Faster capital re-allocation to currently working models/regimes + safer live model updates.

### 5. Additional High-Leverage Ideas
- **Feature Importance + Pruning** (issue #16): Use the existing permutation importance to periodically drop low-value features or reduce model size → lower overfitting + faster inference.
- **Online Hyperparameter / Temperature Tuning**: Expose `m_temperature` and learning rate to light online optimization (or meta-learner) so calibration adapts.
- **Multi-Asset / Symbol Embedding Leverage**: Our `CSymbolEmbedding` + adaptation heads are ahead of many systems. Expand to learn cross-symbol regime correlations.
- **Hybrid with Light RL**: After stable online learning, add a small policy head that learns position sizing / exit timing on top of the current signal (kept optional).

**Overall Expected Impact if Implemented:**
- Significantly slower edge decay (better continual learning)
- Higher winrate / expectancy via better filtering & sizing (meta-labeling + uncertainty)
- More robust live operation (hot-swap, confidence floors, hygiene)
- Better capital efficiency (regime-aware Kelly + conformal sizing)

These build directly on what we already have (Transformer + EWC, MetaLabeler, Conformal, Ensemble + HMM, triple-barrier, ONNX hot-swap) rather than requiring a full rewrite.

*Research compiled 2026-06-20 from recent papers on EWC in finance, meta-labeling (Lopez de Prado lineage), and conformal prediction applications in quant trading. Prioritized practical, incremental improvements.*

*Updated 2026-06-20 — Grok MQH profit-first audit + research synthesis*

---

## Multi-Asset AI Support: Forex + Deriv/Weltrade Synthetics

**Goal:** Make the core AI division (TransformerBrain, NeuralNetworkStrategy, EnsembleMetaLearner, MetaLabeler, UncertaintyQuantifier, OnnxBrain, UniversalTransformerService, and the proposed MoE brain) perform strongly and adaptively on **both Forex and Deriv synthetics** (not just the overall EA having multi-asset infrastructure).

### Current State Assessment

**Already Strong (outside pure AI layer):**
- `CMultiAssetProfiler` + `CDerivAssetProfiler` (18-family synthetic auto-detection)
- Per-asset-class risk parameters, ATR multipliers, engine weights, magic offsets
- Asset-class feature engineering on Python side
- `UniversalTransformerService` + `CSymbolEmbedding` / `CSymbolAdaptationHead` with basic synthetic vs forex classification

**Gaps in the AI Layer:**
- Core models (Transformer, NN, Ensemble, MetaLabeler) are mostly asset-class agnostic after normalization.
- Symbol adaptation is lightweight and static.
- Triple-barrier parameters, confidence floors, and risk logic inside AI are global.
- No strong conditioning or specialization for synthetic spike/volatility behavior vs forex trend/mean-reversion behavior.
- The new MoE proposal needs explicit asset-class awareness to reach full potential.

### New Issues & Enhancement Opportunities (Detailed Fix Steps)

**MA-01: Weak Asset-Class Conditioning in Core AI Models**  
**Files:** `TransformerBrain.mqh`, `NeuralNetworkStrategy.mqh`, `MetaLabeler.mqh`, `EnsembleMetaLearner.mqh`  
**Issue:** Models do not receive or strongly condition on asset class (Forex vs Deriv synthetic family). Behavior is too uniform.  
**Profit Impact:** Sub-optimal performance on one asset class group; models compromise instead of specializing.  
**Priority:** P1  

**Detailed Fix Steps:**
1. Add `ENUM_ASSET_CLASS` (or int assetClassId) parameter to key methods: `Forward()`, `GetPredictions()`, `TrainStep()`, `BuildInput()` in the affected files.
2. In `AIFeatureVectorBuilder.mqh` (or create a thin wrapper), append or inject asset-class features (e.g., one-hot or profile stats like typical vol regime, spike frequency) to the feature vector before passing to AI models.
3. In `TransformerBrain.mqh` and `NeuralNetworkStrategy.mqh`:
   - Add a small conditioning layer (simple linear projection of assetClassId concatenated with features, or FiLM-style affine transform on hidden activations).
   - Or start simpler: scale certain feature groups or attention heads based on asset class.
4. In `MetaLabeler.mqh`: Extend `BuildInput()` to include asset-class context and let the meta model learn different profitability patterns per class.
5. In `EnsembleMetaLearner.mqh`: Pass asset class to individual models and allow per-class performance tracking inside `UpdateModelPerformance()`.
6. Test: Run forward passes on both a major Forex pair and a high-vol Deriv synthetic and verify different internal activations/behavior.
7. Later: Make conditioning strength learnable per asset class.

**MA-02: Insufficient Symbol/Asset-Class Adaptation Strength**  
**Files:** `UniversalTransformerService.mqh` (CSymbolEmbedding + CSymbolAdaptationHead)  
**Issue:** Current adaptation is relatively light (fixed weights + small embedding). Not powerful enough for large behavioral differences between Forex and high-volatility synthetics.  
**Profit Impact:** Features and representations not sufficiently specialized.  
**Priority:** P1  

**Detailed Fix Steps:**
1. Increase embedding dimension (e.g., from 32 to 64) and adaptation weight matrix size in `CSymbolEmbedding` and `CSymbolAdaptationHead`.
2. Make adaptation weights **learnable per major asset-class group** (Forex group vs Deriv synthetic families) instead of purely per-symbol hash.
3. Add an auxiliary training objective (even if lightweight) on the embedding: e.g., predict asset class or regime from the embedding, or use contrastive loss between similar/dissimilar symbols.
4. In `AdaptFeatures()`: Make the blending factor between universal features and adapted features configurable per asset class (stronger adaptation for synthetics).
5. Expose a method `GetAssetClassEmbedding()` so other components (router, meta-labeler) can use it.
6. During online training, update embeddings more aggressively when performance on that symbol/asset class is poor.
7. Test: Compare feature distributions and model outputs before/after on Forex vs Deriv symbols.

**MA-03: Global Barrier & Risk Parameters Inside AI**  
**Files:** `NeuralNetworkStrategy.mqh`, `CNeuralTrainingDataManager.mqh`, `MetaLabeler.mqh`  
**Issue:** `m_barrierK`, vertical bars, confidence thresholds, and sizing logic are global instead of respecting per-asset-class profiles.  
**Profit Impact:** Inappropriate risk on synthetics (too aggressive or too conservative) or missed opportunities on Forex.  
**Priority:** P1  

**Detailed Fix Steps:**
1. In `NeuralNetworkStrategy::Initialize()` and `ConfigureOnlineLearning()`, accept or query asset-class profile from `CMultiAssetProfiler`.
2. Store per-asset-class barrier parameters (`m_barrierK[assetClass]`, `m_barrierVertBars[assetClass]`, ATR multipliers).
3. In `AddBarrierEntry()` and `ResolveExpiredBarriers()`, select the parameters based on current symbol’s asset class.
4. In `MetaLabeler` and confidence/sizing logic: Apply asset-class specific multipliers to confidence thresholds and risk multipliers.
5. Expose `GetAssetClassBarrierParams()` and wire it into `GetRiskAdjustedSize()`.
6. Update checkpoint save/load to persist per-asset-class parameters.
7. Add logging: `[ASSET-CLASS-BARRIER] Symbol=... Class=... K=... VertBars=...`
8. Test on both asset types and verify different barrier behavior.

**MA-04: MoE Router Not Asset-Class Aware (Future)**  
**Files:** Proposed `CMoEBrain.mqh`  
**Issue:** The router in the MoE proposal is currently planned as regime-only. It should also condition on asset class.  
**Profit Impact:** Experts not optimally routed for synthetic vs forex behavior.  
**Priority:** P1 (when implementing MoE)  

**Detailed Fix Steps:**
1. When designing `CMoEBrain`, make router input = [features, HMM regime probs, assetClass embedding/one-hot].
2. Allow the router to output different expert preference distributions per asset class.
3. Optionally designate or bias certain experts toward asset classes (e.g., Expert 2 = “Synthetic Volatility Specialist”).
4. In training, add a small auxiliary loss that encourages the router to use appropriate experts for the current asset class.
5. During inference, log which experts are activated per asset class for diagnostics.
6. Support per-asset-class top-k or routing temperature.

**MA-05: Separate Performance Tracking & Hot-Swap by Asset Class**  
**Files:** `OnnxBrain.mqh`, `EnsembleMetaLearner.mqh`, `AIPerformanceFeedback.mqh`  
**Issue:** Model performance, shadow promotion, and Kelly weighting are not tracked or conditioned per asset-class group.  
**Profit Impact:** A model that performs well on Forex but poorly on synthetics (or vice versa) is not properly managed.  
**Priority:** P2  

**Detailed Fix Steps:**
1. In `EnsembleMetaLearner` and `OnnxBrain`, add per-asset-class (or per major group) rolling performance buffers (winrate, expectancy, max DD).
2. Modify `UpdateModelPerformance()` and `RecordOutcome()` to key by asset class.
3. In hot-swap logic (`OnnxBrain::RecordOutcome` and promotion), compute separate shadow vs active metrics per asset class and promote only if it wins on the relevant class.
4. In Kelly weighting, allow per-asset-class expert weights.
5. Add diagnostic logs: `[ASSET-CLASS-PERF] Forex: ... | Deriv-Synth: ...`
6. Update `GetEnsembleStatus()` and similar to report per-asset-class health.

**MA-06: Feature Contract Uniformity**  
**Files:** `AIFeatureVectorBuilder.mqh`, `PipelineScaler.mqh`  
**Issue:** While 57-base features exist, asset-class specific augmentations (spread_z, vol_of_vol, overnight_gap, inventory_proxy, etc.) are not consistently injected into the AI feature vectors used by NN/Transformer/ONNX.  
**Profit Impact:** AI misses important asset-class specific signals.  
**Priority:** P1  

**Detailed Fix Steps:**
1. In `AIFeatureVectorBuilder::BuildNNFeatureVector()` and transformer input builder, detect asset class (via profiler or symbol name) and append the relevant extra features for that class.
2. Update `FEATURE_VECTOR_SIZE` handling or create an extended vector + mask for AI models.
3. Ensure `PipelineScaler` (for ONNX parity) also scales the asset-class specific features correctly.
4. Add a comment block listing which extra features are added per asset class.
5. Update any feature importance logging to account for the new features.
6. Test parity between Python training pipeline and MQL5 feature vectors for both Forex and Deriv symbols.

### Integration with Proposed MoE Architecture

The **Regime-Routed MoE Trading Brain** should be extended as follows:

- Router input = features + HMM regime state + asset-class embedding/ID.
- Some experts can be lightly specialized or have asset-class specific adapters.
- Load-balancing and EWC can be applied globally or per asset-class group.
- Meta-Adaptive Layer (upgraded MetaLabeler + Sizing Head) receives asset-class context and outputs asset-class appropriate risk multipliers.

This turns the MoE into a true **asset-class + regime aware** dynamic system.

### Implementation Priority & Roadmap

1. **Quick Wins (P1, low effort)**: MA-03 (asset-class barrier/risk params) + MA-06 (feature injection) + strengthen MA-02 (adaptation weights).
2. **Core Enhancement (P1)**: MA-01 (conditioning in Transformer/NN/MetaLabeler) + MA-04 (asset-class aware router in MoE).
3. **Advanced (P2)**: MA-05 (per-asset-class performance tracking & hot-swap).

These changes will allow the AI to **natively understand and adapt to the very different dynamics** of Forex (trend, macro, lower volatility) versus Deriv synthetics (spikes, mean-reversion, high volatility, family-specific behavior) without forcing a one-size-fits-all model.

*Added 2026-06-20 — Multi-Asset (Forex + Deriv Synthetics) AI Support section*

---

## Candlestick Strategy & Pattern Detectors Audit & Improvements (2026-06-20)

**Scope:** Full review of the new candlestick detection suite (`CandleAnalyzer.mqh`, individual detectors, `CandleConfluenceScorer.mqh`, and `StrategyCandlestick.mqh`).

**Overall Assessment:**
This is a high-quality, comprehensive candlestick pattern system (15 patterns) with good structure, confluence scoring, risk integration, and drawing management. It complements the AI division well as a traditional "Tier 1/2" strategy. However, there are several areas for tightening, asset-class adaptation, and better synergy with the AI/MoE layer.

### Key Strengths
- Clean separation: `CandleAnalyzer` + specialized detectors + `CandleConfluenceScorer`.
- Strong confluence scoring (Pattern + Key Level + Trend Alignment).
- Good integration with `CIndicatorManager`, `UnifiedRiskManager`, and `ChartDrawingManager`.
- `GetQuickProbeSignal()` for fast two-tier consensus.
- Many detectors already use ATR normalization and strength scoring.

### Issues & Improvement Opportunities

**CS-01: Inconsistent ATR Normalization Across Detectors**  
**Files:** Most detector files (`DojiDetector`, `HammerDetector`, `PinBarDetector`, etc.)  
**Issue:** Some detectors use ATR for minimum range checks, others don't (or use different multipliers). `CandleAnalyzer` provides ATR, but not all detectors leverage it uniformly.  
**Profit Impact:** Weak patterns slip through on low-volatility symbols (especially certain Forex pairs); overly strict on high-vol synthetics.  
**Priority:** P1  

**Detailed Fix Steps:**
1. Standardize minimum range check in all detectors: `if(candle.totalRange < atr * 0.4) return false;` (tunable per asset class later).
2. Move common ATR + range validation into `CandleAnalyzer` as helper methods (`IsSignificantCandle()`, `GetNormalizedStrength()`).
3. Update all detectors to call the centralized helpers.
4. Add per-asset-class ATR multiplier table (e.g., higher threshold for Deriv Volatility indices).

**CS-02: Hard-coded Thresholds Not Asset-Class Aware**  
**Files:** All detectors + `StrategyCandlestick.mqh`  
**Issue:** Body/wick ratios, strength thresholds, and confluence requirements are global. Synthetics (especially Crash/Boom, Volatility) behave very differently from Forex.  
**Profit Impact:** Sub-optimal detection quality across asset classes.  
**Priority:** P1  

**Detailed Fix Steps:**
1. Create `SCandleParams` struct with asset-class specific values (maxBodyRatio, minWickRatio, minATRMultiplier, etc.).
2. Load/override these from `CMultiAssetProfiler` or a config map in `StrategyCandlestick::Init()`.
3. Pass asset-class context down to detectors or make detectors query profile.
4. For high-vol synthetics: relax body ratio slightly, increase wick importance.
5. For Forex: stricter trend alignment requirement.

**CS-03: Limited Synergy with AI Division**  
**Files:** `StrategyCandlestick.mqh` + AI files  
**Issue:** Candlestick signals are treated as a separate traditional strategy. No direct feature contribution to `AIFeatureVectorBuilder`, `MetaLabeler`, or the proposed MoE.  
**Profit Impact:** Missed opportunity to use high-quality pattern detections as strong features for the neural/transformer models.  
**Priority:** P2  

**Detailed Fix Steps:**
1. Expose a method in `StrategyCandlestick` or a new helper: `GetActivePatternFeatures(double &features[])` that returns one-hot or strength vector for the last 1-3 bars (e.g., EngulfingBull=0.85, PinBarBear=0.0, etc.).
2. Inject these into `AIFeatureVectorBuilder` as additional features (extend beyond 57).
3. Feed pattern strength + type into `MetaLabeler` as high-value input features.
4. In the future MoE, consider a lightweight "Candlestick Expert" that uses these detectors.

**CS-04: Confluence Scorer Can Be Stronger**  
**File:** `CandleConfluenceScorer.mqh`  
**Issue:** Currently only 3 components (Pattern + Key Level + Trend). Missing volume, session timing, higher-timeframe alignment, and recent pattern frequency.  
**Profit Impact:** Some false positives in ranging/choppy markets.  
**Priority:** P2  

**Detailed Fix Steps:**
1. Add `AddVolumeConfirmation(bool yes)` (+10-15 pts if above average volume).
2. Add `AddSessionAlignment(bool yes)` (stronger during London/NY overlap for Forex).
3. Add `AddHTFAlignment(bool yes)` (check H4/Daily trend via multi-timeframe analysis).
4. Make scoring weights configurable per asset class.
5. Expose more granular breakdown for logging and AI feature use.

**CS-05: SL/TP Calculation in StrategyCandlestick Can Be More Robust**  
**File:** `StrategyCandlestick.mqh` (CalculateStopLoss / CalculateTakeProfit)  
**Issue:** Uses array min/max for swing points but has fallback logic that can produce invalid SL (== entry). ATR handling when indicator not ready is okay but could be cleaner.  
**Profit Impact:** Occasional rejected signals or suboptimal risk-reward on certain symbols.  
**Priority:** P2  

**Detailed Fix Steps:**
1. Centralize ATR proxy logic (when `atr <= 0`) into a helper used by both SL and TP.
2. Add stricter final validation: for BUY, `sl < entryPrice * 0.999`; for SELL `sl > entryPrice * 1.001`.
3. Consider using recent swing structure more consistently (already partially done with ArrayMinimum/Maximum).
4. Tie RR ratio to asset class (higher for mean-reverting synthetics, lower for trending Forex).

**CS-06: Drawing & Performance on High-Frequency Symbols**  
**File:** `StrategyCandlestick.mqh`  
**Issue:** Drawing manager is created per strategy instance. On symbols with many patterns (high-vol synthetics), object count can grow if not cleaned aggressively.  
**Profit Impact:** Minor — chart clutter and potential MT5 object limit issues on busy charts.  
**Priority:** P3  

**Detailed Fix Steps:**
1. Make `m_drawOnChartSymbolOnly` default true (already is).
2. Increase cleanup frequency or add max objects per pattern type.
3. Consider optional "text-only" mode for high-frequency symbols.

### Recommended Implementation Order

1. **CS-01 + CS-02** (Quick, high impact) — Standardize ATR and make parameters asset-class aware.
2. **CS-03** — Wire candlestick features into the AI layer (big synergy win with the MoE direction).
3. **CS-04** — Strengthen `CandleConfluenceScorer`.
4. **CS-05** — Polish SL/TP robustness.
5. **CS-06** — Minor drawing hygiene.

These improvements will make the candlestick suite a first-class citizen that works excellently on both Forex and Deriv synthetics, while also feeding high-quality signals into the AI division.

*Added 2026-06-20 — Candlestick Strategy & Pattern Detectors section*