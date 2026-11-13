# Offline NN training — findings

Date: 2026-11-12. Scope: `AIModules/NeuralNetworkStrategy.mqh` checkpoint format, the
exported training set `MQL5/Files/AITraining_Enterprise_H1.csv` (164,035 rows,
214 MB), and whether an offline run can hand the live EA a model worth loading.

## Why this was attempted

The live journal printed, on every one of 366 lines:

```
[NEURAL-NET] Signal=NONE | conf=0.000 | conformal_q=1.000(global=1.000) | labels=0/30
[MODEL-HEALTH] Training=YES | Steps=0 | Uncertainty=1.000
```

That is not a wiring failure. It is an untrained network. Every checkpoint on disk
(`Common/Files/EAModels/NN/<Symbol>_15_v8.bin`, 13 symbols × primary + `.prev`) parses
as:

```
magic 1313758027 | version 8 | tf 15 | epoch 0 | loss 0.0 | trainingSteps 0
checkpointWrites 1 | totalObservations 0 | resolvedLabels 0 | featureCount 41 | adamStep 0
```

An empty shell: random init, no normalization samples, no labels resolved.

## The checkpoint format, now fully documented

Written by `SaveCheckpointAtomic` (`AIModules/NeuralNetworkStrategy.mqh:1200-1280`) and
read by `LoadCheckpoint` (`:1414-1515`), which validates only magic, version, a readable
symbol string, `symbol == m_symbol` and `timeframe == (int)m_timeframe`, then reads the
rest strictly in order:

| field | type |
|---|---|
| magic `1313758027`, version `8` | int32 ×2 |
| symbol | int32 length + one int32 per UTF-16 code unit |
| timeframe | int32 |
| timestamp | int64 |
| onlineTraining, selfLabeling, sampleIntervalSec, checkpointEveryLabeled | int32 ×4 |
| epoch | int32 |
| lastLoss | float64 |
| trainingSteps, checkpointWrites, totalObservations, tradeLinkedLabels | int32 ×4 |
| resolvedLabelCount, featureCount | int64 ×2 |
| normalizationReady | int32 |
| adamStep | int64 |
| featureMean[70], featureM2[70] | float64 ×140 |
| adamM[2963], adamV[2963] | float64 ×5926 |
| W1[70][32], W2[32][16], W3[16][8], W4[8][3] | float64 ×2904 |
| B1[32], B2[16], B3[8], B4[3] | float64 ×59 |
| trainCount | int32 |
| per sample: labelClass, time, linkedToTrade, predictionId, signalConfidence, inputs[70], metaInput[] | mixed |

Network: 70 → 32 → 16 → 8 → 3, ReLU hidden layers, softmax with temperature 1.0
(`m_temperature = 1.0`, `:1587`). Parameter count = **2963**, matching
`TotalParamCount()`. Normalization is `z = (x - mean) / sqrt(M2 + 1e-9)` clipped to
±3, with `M2` used directly as the variance (`:598-608`). Class convention is
**0 = HOLD, 1 = BUY, 2 = SELL** (`:1065-1071`).

## What the offline run produced

`Tools/offline_nn_trainer.py` reproduces the architecture, the parameter ordering and the
serialization byte for byte, trains on the exported rows, re-reads every file it writes
the way `LoadCheckpoint` does, and **refuses to write a model whose held-out accuracy does
not clear the majority-class baseline by 1.5 points**. It never overwrites a checkpoint
without copying it to `<name>.pre_offline.bak`.

Result: no checkpoint was written, because there is no edge to ship.

### Measurement 1 — the MLP actually trains, but learns nothing

`Volatility 25 Index`, 30,190 rows, chronological split with purge gaps:

```
best epoch 11 | valAcc 0.5060 | testAcc 0.5232 | baseline 0.5192
directional@conf>=0.60 0.4713 (coverage 1.9%)
  HOLD  support    6  P 0.000  R 0.000
  BUY   support 2392  P 0.529  R 0.890
  SELL  support 2130  P 0.475  R 0.112
```

The net collapses to "always BUY, never SELL" — exactly the 0.94-0.99 constant-BUY
behaviour the journal shows from the untrained net. That is not an artifact of the
weights; it is what the label distribution supports.

### Measurement 2 — no learner finds direction, at any barrier width

Identical three-class labels shipped in the CSV (`label_5bar/10bar/20bar`) scored with a
gradient-boosted tree, which is far stronger than the EA's MLP:

```
label_5bar   testAcc 0.5292  baseline 0.5283  edge +0.0009
label_10bar  testAcc 0.5285  baseline 0.5276  edge +0.0009
label_20bar  testAcc 0.5267  baseline 0.5258  edge +0.0009
```

All three horizons carry the same information (HOLD row counts equal the horizon, 6/10/20),
and the top permutation-importance features move accuracy by +0.27 percentage points — noise.

Rebuilding the labels from the dataset's own OHLC at wider barriers changes nothing
(`Tools/nn_label_geometry_test.py`):

```
mult horizon   n     acc   baseline   edge   cov@0.6 prec@0.6
0.5      5  30170  0.526    0.524   +0.002   0.008   0.449
1.0     10  29810  0.510    0.504   +0.006   0.021   0.588
1.5      5  17524  0.514    0.508   +0.006   0.142   0.536
1.5     20  29684  0.503    0.508   -0.005   0.119   0.509
2.0     10  19245  0.492    0.502   -0.010   0.168   0.500
3.0     20  17863  0.494    0.508   -0.015   0.253   0.505
```

Best case +0.6 points, most configurations negative, and no configuration produces a
confidence band that is both populated and profitable.

### Measurement 3 — it is not a feature-subset problem

The NN sees 70 columns, the export has 114 numeric ones (regime, hurst, ou, vpin, ofi,
per-strategy signal/confidence, consensus). Using all of them is *worse*
(`Tools/nn_feature_set_compare.py`):

```
geometry 1.5 ATR / 12 bars
  70-feature vector  acc 0.4973  baseline 0.5087  edge -0.0114
  all exported cols  acc 0.4814  baseline 0.5087  edge -0.0273
```

More information did not help, so the missing signal is not in the exporter's other
columns either.

### Measurement 4 — the features are not useless, the target was

Same 70 features, same tree, target switched from "which way" to "does volatility expand"
(next 5 bars' mean true range above the trailing 20-bar median):

```
volatility-expansion target: acc 0.6488  baseline 0.6072  edge +0.0416
at conf>=0.60: coverage 0.647  precision 0.7078
```

**+4.2 points, 70.8% precision on two thirds of the sample.** The 70-feature vector is a
description of volatility, momentum and regime state; it contains no directional
information at 5-20 bars, and it contains a great deal of volatility information.

## The defect this uncovered

`TrainingDataExporter.mq5` exported every label at `InpLabelATRMultiplier = 0.5` over
horizons `5,10,20`, while the live network grades itself against
`AI_DEFAULT_BARRIER_K = 1.5` over `AI_DEFAULT_BARRIER_VERT_BARS = 12`
(`AIModules/AIConfig.mqh:90-94`). The 164,035 exported rows therefore describe a target
the EA will never resolve — and at 0.5 ATR the barrier sits inside normal noise, which is
why the labels are ~53/47 and unpredictable by construction.

Fixed: the exporter defaults are now `InpLabelATRMultiplier = 1.5` and
`InpLabelHorizons = "5,12,20"`, so a future export teaches the geometry the EA actually
grades, and the 12-bar column exists alongside the research horizons.

## What was deliberately not done

* **No checkpoint was written.** Shipping weights that clear no baseline would recreate
  the current failure in a more expensive form: a confident network that votes BUY on
  every symbol, still untradeable, but now harder to dismiss as "untrained".
* **The AI catalog rows stay at weight 0.0.** Batch 275 already stops weight-0 adapters
  from counting as votes; giving them weight now would inject noise into consensus.
* **`Resources/model.onnx` was not wired into `g_onnxModel`.** Its input layout is
  unverified and it has never been evaluated against this label geometry.

## What this means for profit, and the next real step

Direction-picking from OHLC-derived features at 5-20 bars is a dead end on these
instruments — measured, not assumed. The measurement says the network can predict
**volatility state**, which is worth money in a different place than a vote:

1. Make the neural arm a **volatility/regime gate** (size up and allow entries when
   expansion is predicted; stand down when compression is predicted) instead of a
   directional voter. That uses the one measured edge and changes no strategy's entry rule.
2. Feed it features that are not in this set: real order flow (tick imbalance, depth),
   cross-asset lead-lag against the underlying FX/commodity, session microstructure, and
   the strategy layer's own realized outcomes (meta-labeling), which is what a fund-grade
   system predicts from.
3. Re-export with the fixed geometry (`1.5 ATR / 12 bars`) before the next training run,
   otherwise the target and the runtime labeler disagree again.

## Reproducing

```
python Tools/nn_signal_diagnostic.py       --csv <AITraining_Enterprise_H1.csv>
python Tools/nn_label_geometry_test.py     --csv <AITraining_Enterprise_H1.csv>
python Tools/nn_feature_set_compare.py     --csv <AITraining_Enterprise_H1.csv>
python Tools/offline_nn_trainer.py         --csv <...> --out <...>/EAModels/NN --tf 15 --symbols all
```

The trainer writes `Tools/offline_nn_mlp_report.csv` with per-symbol validation,
test and directional accuracy, and whether a checkpoint was written.
