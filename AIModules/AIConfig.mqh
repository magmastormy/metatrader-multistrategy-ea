//+------------------------------------------------------------------+
//| AIConfig.mqh                                                     |
//| Centralized AI hyperparameters and constants                      |
//| All magic numbers from AI modules live here for per-symbol tuning |
//+------------------------------------------------------------------+
#ifndef __AI_CONFIG_MQH__
#define __AI_CONFIG_MQH__

//--- Transformer defaults
#ifndef AI_DEFAULT_DMODEL
#define AI_DEFAULT_DMODEL        32
#endif
#ifndef AI_DEFAULT_NUM_HEADS
#define AI_DEFAULT_NUM_HEADS      4
#endif
#ifndef AI_DEFAULT_NUM_LAYERS
#define AI_DEFAULT_NUM_LAYERS     2
#endif
#ifndef AI_DEFAULT_DFF
#define AI_DEFAULT_DFF           64
#endif
#ifndef AI_DEFAULT_MAX_SEQ_LEN
#define AI_DEFAULT_MAX_SEQ_LEN   60
#endif
#ifndef AI_DEFAULT_LR
#define AI_DEFAULT_LR            0.001
#endif

//--- ONNX defaults
#ifndef AI_ONNX_SEQ_LEN
#define AI_ONNX_SEQ_LEN          60
#endif
#ifndef AI_ONNX_N_CLASSES
#define AI_ONNX_N_CLASSES         3
#endif

//--- MLP / MetaLabeler defaults
#ifndef AI_MLP_INPUT
#define AI_MLP_INPUT             24
#endif
#ifndef AI_MLP_HIDDEN
#define AI_MLP_HIDDEN            24
#endif
#ifndef AI_MLP_OUTPUT
#define AI_MLP_OUTPUT             2
#endif

//--- Normalization
#ifndef AI_DEFAULT_NORM_DECAY
#define AI_DEFAULT_NORM_DECAY    0.02
#endif
#ifndef AI_MIN_NORM_SAMPLES
#define AI_MIN_NORM_SAMPLES      30
#endif

//--- Online learning
#ifndef AI_DEFAULT_SAMPLE_INTERVAL_SEC
#define AI_DEFAULT_SAMPLE_INTERVAL_SEC  15
#endif
#ifndef AI_DEFAULT_CHECKPOINT_EVERY
#define AI_DEFAULT_CHECKPOINT_EVERY      10
#endif
#ifndef AI_MAX_TRAINING_EXAMPLES
#define AI_MAX_TRAINING_EXAMPLES       2000
#endif
#ifndef AI_MAX_PERSISTED_SAMPLES
#define AI_MAX_PERSISTED_SAMPLES        300
#endif

//--- Confidence & safety
#ifndef AI_MIN_CONFIDENCE
#define AI_MIN_CONFIDENCE        0.70
#endif
#ifndef AI_MIN_TRADE_LINKED_LABELS
#define AI_MIN_TRADE_LINKED_LABELS  5
#endif
#ifndef AI_MIN_RESOLVED_LABELS
#define AI_MIN_RESOLVED_LABELS   10
#endif

//--- Barrier defaults
#ifndef AI_DEFAULT_BARRIER_K
#define AI_DEFAULT_BARRIER_K      1.5
#endif
#ifndef AI_DEFAULT_BARRIER_VERT_BARS
#define AI_DEFAULT_BARRIER_VERT_BARS  20
#endif
#ifndef AI_MIN_BARRIER_WIDTH_POINTS
#define AI_MIN_BARRIER_WIDTH_POINTS  5
#endif

//--- MetaLabeler training
#ifndef AI_META_TRAIN_COOLDOWN
#define AI_META_TRAIN_COOLDOWN    50
#endif
#ifndef AI_META_EARLY_STOP_PATIENCE
#define AI_META_EARLY_STOP_PATIENCE  20
#endif
#ifndef AI_META_EARLY_STOP_THRESHOLD
#define AI_META_EARLY_STOP_THRESHOLD 1e-5
#endif
#ifndef AI_META_MIN_TRAIN_STEPS
#define AI_META_MIN_TRAIN_STEPS   50
#endif

//--- Kelly / Ensemble
#ifndef AI_KELLY_UPDATE_INTERVAL
#define AI_KELLY_UPDATE_INTERVAL   3
#endif

//--- Feature importance
#ifndef AI_FEATURE_IMPORTANCE_INTERVAL
#define AI_FEATURE_IMPORTANCE_INTERVAL  200
#endif

//--- Feature vector size
// 57 base features + 8 candlestick pattern features = 65 total
// Candlestick features: pin bar bull/bear, engulfing, doji, hammer, shooting star, morning/evening star
#ifndef AI_FEATURE_VECTOR_SIZE
#define AI_FEATURE_VECTOR_SIZE  65
#endif
#ifndef AI_NN_CHECKPOINT_VERSION
#define AI_NN_CHECKPOINT_VERSION    7
#endif
#ifndef AI_NN_CHECKPOINT_MAGIC
#define AI_NN_CHECKPOINT_MAGIC      1313758027
#endif

//--- Temperature bounds
#ifndef AI_MIN_TEMPERATURE
#define AI_MIN_TEMPERATURE        0.1
#endif
#ifndef AI_MAX_TEMPERATURE
#define AI_MAX_TEMPERATURE       10.0
#endif

#endif // __AI_CONFIG_MQH__
