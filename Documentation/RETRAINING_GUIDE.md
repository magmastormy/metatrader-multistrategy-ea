# 🔄 Automated Model Retraining System - Complete Guide

## Overview

Fully automated model retraining pipeline that continuously improves your AI trading models by:
- **Collecting** fresh trading data from multiple sources
- **Engineering** advanced features from market data and logs
- **Training** models with hyperparameter optimization (Optuna)
- **Evaluating** performance with backtesting and metrics
- **Comparing** with baseline to ensure improvements
- **Deploying** only superior models automatically
- **Versioning** all models with complete audit trail

---

## 🏗️ System Architecture

```
┌──────────────────────────────────────────────────────────┐
│                  RETRAINING PIPELINE                     │
└──────────────────────────────────────────────────────────┘
                          │
    ┌─────────────────────┼─────────────────────┐
    ▼                     ▼                     ▼
┌─────────┐         ┌──────────┐         ┌──────────┐
│  Data   │         │ Feature  │         │  Model   │
│Ingestion│────────▶│Engineering────────▶│ Training │
└─────────┘         └──────────┘         └──────────┘
    │                                           │
    │ MT5 Logs, OHLC,                          │
    │ EA Signals                                │
    ▼                                           ▼
┌──────────┐                             ┌──────────┐
│Data Lake │                             │Evaluation│
│/raw/     │                             │Backtest  │
│/processed│                             └──────────┘
│/training │                                   │
└──────────┘                                   ▼
                                        ┌──────────┐
                                        │Comparison│
                                        │APPROVE?  │
                                        └──────────┘
                                              │
                                    YES ◄─────┴─────► NO
                                     │               │
                                     ▼               ▼
                                ┌─────────┐    ┌────────┐
                                │  Deploy │    │ Reject │
                                │Registry │    └────────┘
                                └─────────┘
```

---

## 📦 Components

### 1. Data Ingestion (`data_ingestion.py`)
**Purpose**: Collect trading data from multiple sources

**Sources**:
- MT5 log files (actual trades)
- EA signal logs (our system's decisions)
- OHLC price data (market data)
- Strategy metadata

**Data Lake Structure**:
```
data_lake/
├── raw/              # Unprocessed data
├── processed/        # Cleaned data
└── training_sets/    # ML-ready datasets
```

**Features**:
- Automatic validation and cleaning
- Dataset versioning with hashes
- Metadata tracking

### 2. Feature Engineering (`feature_engineering.py`)
**Purpose**: Transform raw data into ML features

**Feature Groups** (60+ features):
- **Price-based**: Returns, volatility, price changes
- **Technical**: RSI, SMA, Bollinger Bands, MACD
- **Time-based**: Hour/day encoding, trading sessions
- **Log-based**: Entry/exit reasons, profit patterns
- **Strategy-based**: Win rate, drawdown, expectancy

**Target Variable**: Future price direction (BUY/SELL/HOLD)

### 3. Model Training (`model_training.py`)
**Purpose**: Train ML models with optimization

**Capabilities**:
- **Hyperparameter optimization** with Optuna (50 trials)
- **K-fold cross-validation** (5 folds)
- **Early stopping** to prevent overfitting
- **Parameter search** for LightGBM/Transformer

**Best Practices**:
- Train/Val/Test split: 70/20/10
- Optuna finds optimal parameters automatically
- Cross-validation ensures robustness

### 4. Model Evaluation (`model_evaluation.py`)
**Purpose**: Backtest and evaluate models

**Metrics Calculated**:

**ML Metrics**:
- Accuracy, Precision, Recall, F1-Score
- Confusion matrix
- Per-class performance

**Trading Metrics**:
- Sharpe Ratio (risk-adjusted returns)
- Sortino Ratio (downside risk)
- Maximum Drawdown
- Win Rate
- Profit Factor
- Total Return

**Decision Criteria**:
```python
APPROVE if:
  - New model accuracy > baseline + 1%
  - Sharpe ratio > baseline + 0.1
  - Win rate > baseline + 2%
  - Meets minimum thresholds
  - No critical regressions
```

### 5. Model Registry (`model_registry.py`)
**Purpose**: Version control for models

**Stored Information**:
- Version number (v1.0.0, v1.0.1, etc.)
- Training date and parameters
- Performance metrics
- Dataset hash (for reproducibility)
- Deployment status

**Operations**:
- `register_model()` - Add new version
- `deploy_model()` - Deploy to production
- `rollback_to_version()` - Revert if issues
- `get_best_model()` - Find top performer

### 6. Retraining Loop (`retrain_loop.py`)
**Purpose**: Orchestrate full pipeline

**8-Step Process**:
1. **Data Collection** - Gather all sources
2. **Feature Engineering** - Build feature matrix
3. **Model Training** - Train with Optuna
4. **Evaluation** - Backtest on test set
5. **Comparison** - Compare with baseline
6. **Registration** - Version new model
7. **Deployment** - Deploy if approved
8. **Reporting** - Generate comprehensive reports

### 7. Auto Scheduler (`auto_scheduler.py`)
**Purpose**: Automate retraining triggers

**Scheduling Modes**:

**Daily**: Fixed time (e.g., 2 AM)
```python
schedule_type: 'daily'
schedule_time: '02:00'
```

**Weekly**: Specific day and time
```python
schedule_type: 'weekly'
schedule_day: 'sunday'
schedule_time: '02:00'
```

**Trigger-based**: Intelligent triggers
```python
schedule_type: 'trigger_based'
# Triggers:
- min_new_rows: 1000  # Retrain when N new data rows
- max_days_since_training: 7  # Force retrain after N days
- performance_threshold: 0.50  # Retrain if accuracy drops
```

---

## 🚀 Quick Start

### 1. Install Additional Dependencies

```bash
pip install optuna schedule
```

### 2. Run Manual Retraining

```bash
cd retraining
python retrain_loop.py
```

Expected output:
```
🚀 STARTING FULL RETRAINING PIPELINE
STEP 1: DATA COLLECTION
✅ Data collected: 3 datasets
STEP 2: FEATURE ENGINEERING
✅ Features: 60, Samples: 5000
STEP 3: MODEL TRAINING
✅ Best trial: accuracy 0.6234
STEP 4: MODEL EVALUATION
✅ Sharpe Ratio: 1.45
STEP 5: COMPARISON
✅ DECISION: APPROVE
STEP 6: MODEL REGISTRATION
✅ Model registered: v1.0.1
STEP 7: DEPLOYMENT
✅ Model deployed
✅ PIPELINE COMPLETED
```

### 3. Start Automated Scheduler

```bash
python auto_scheduler.py
```

---

## ⚙️ Configuration

### Pipeline Configuration

```python
config = {
    'days_back': 30,              # Collect last 30 days
    'model_type': 'lgbm',         # LightGBM model
    'use_optuna': True,           # Enable optimization
    'optuna_trials': 50,          # Number of trials
    'cross_validation_folds': 5,  # K-fold CV
    'auto_deploy': False,         # Manual deployment
    'min_samples': 1000           # Minimum data required
}
```

### Scheduler Configuration

```python
scheduler_config = {
    'schedule_type': 'trigger_based',
    'schedule_time': '02:00',
    'min_new_rows': 1000,
    'performance_threshold': 0.50,
    'max_days_since_training': 7
}
```

---

## 📊 Monitoring & Reports

### Generated Reports

After each retraining run:

1. **Evaluation Report** (`reports/evaluation_v1.0.1_*.md`)
   - ML metrics (accuracy, precision, recall)
   - Trading metrics (Sharpe, win rate)
   - Comparison with baseline
   - Decision explanation

2. **Registry Report** (`reports/registry_*.md`)
   - All registered models
   - Deployment history
   - Version comparison

3. **Training Summary** (`reports/training_summary_*.json`)
   - Complete run metadata
   - Configuration used
   - All metrics in JSON format

### Log Files

- `logs/retraining.log` - Pipeline execution logs
- `logs/pipeline_runs.json` - All pipeline runs
- `logs/scheduler_history.json` - Scheduler triggers

---

## 📈 Performance Metrics

### Minimum Thresholds

```python
metrics_thresholds = {
    'accuracy': 0.55,      # 55% minimum
    'sharpe_ratio': 1.0,   # 1.0 minimum
    'win_rate': 0.52,      # 52% minimum
    'max_drawdown': -0.15  # -15% maximum
}
```

### Decision Matrix

| Condition | Weight | Points |
|-----------|--------|--------|
| Accuracy +1% | High | 2 |
| Sharpe +0.1 | Highest | 3 |
| Win Rate +2% | High | 2 |
| **Approval Threshold** | | **3/7** |

---

## 🔄 Typical Workflow

### Automated (Recommended)

1. **Setup scheduler**:
```bash
python auto_scheduler.py
```

2. **Scheduler runs automatically**:
   - Checks triggers every 6 hours
   - Runs full pipeline when conditions met
   - Deploys if model improves

3. **Monitor reports**:
```bash
# Check latest evaluation
cat reports/evaluation_*.md

# Check registry
cat reports/registry_*.md
```

### Manual (For Testing)

1. **Collect data**:
```python
from retraining.data_ingestion import DataIngestion
ingestion = DataIngestion()
datasets = ingestion.collect_all(days_back=30)
```

2. **Run pipeline**:
```python
from retraining.retrain_loop import RetrainingPipeline
pipeline = RetrainingPipeline()
results = pipeline.run_full_pipeline()
```

3. **Check results**:
```python
print(results['status'])
print(results['steps']['comparison']['decision'])
```

---

## 🛠️ Advanced Usage

### Custom Feature Engineering

Extend `RetrainingFeatureEngineer`:

```python
class CustomFeatureEngineer(RetrainingFeatureEngineer):
    def _extract_custom_features(self, df):
        features = pd.DataFrame()
        # Add your custom features
        features['my_feature'] = df['close'] * 2
        return features
```

### Custom Evaluation Metrics

Add to `ModelEvaluator`:

```python
def _calculate_custom_metric(self, y_true, y_pred):
    # Your custom metric
    return custom_score
```

### Multiple Model Types

Train different models:

```python
# LightGBM
config_lgbm = {'model_type': 'lgbm'}
pipeline_lgbm = RetrainingPipeline(config_lgbm)

# Transformer (when implemented)
config_transformer = {'model_type': 'transformer'}
pipeline_transformer = RetrainingPipeline(config_transformer)
```

---

## 🐛 Troubleshooting

### "No data collected"
- Check MT5 log directory exists
- Verify EA is logging trades
- Check `data_lake/raw/` for files

### "Insufficient samples"
- Reduce `min_samples` in config
- Collect more days: increase `days_back`
- Check data sources are active

### "Model rejected"
- Normal - model didn't improve enough
- Review comparison metrics in report
- May need more training data
- Consider adjusting hyperparameters

### "Optuna taking too long"
- Reduce `optuna_trials` (default 50 → 20)
- Use faster model (LightGBM is fastest)
- Run on more powerful hardware

---

## 📝 Best Practices

1. **Start with manual runs** to verify system works
2. **Monitor first few automated runs** closely
3. **Review rejected models** - they contain valuable info
4. **Keep baseline models** for comparison
5. **Check reports regularly** for insights
6. **Archive old models** periodically
7. **Backup registry** before major changes

---

## 🎯 Integration with Main System

The retrained models automatically integrate with the main AI trading system:

1. **Registry deploys to** `models/` directory
2. **Main system** (`main.py`) loads latest model
3. **Bridge** uses deployed model for predictions
4. **Hot-reload** possible without system restart

---

## 📊 Expected Results

### First Run
- **Status**: APPROVE (no baseline)
- **Version**: v1.0.0
- **Deployed**: Yes (if auto_deploy=True)

### Subsequent Runs
- **Improvement Needed**: ~2-5% better metrics
- **Approval Rate**: ~30-40% of runs
- **Version Increments**: Patch version (v1.0.1, v1.0.2, etc.)

### After Multiple Runs
- **Model Accuracy**: Gradually improves
- **Trading Performance**: Better Sharpe ratios
- **Registry**: Full version history

---

## 🔐 Safety Features

1. **Manual approval** by default (`auto_deploy=False`)
2. **Rollback capability** to any previous version
3. **Threshold checks** prevent bad models
4. **Comparison required** before deployment
5. **Full audit trail** in registry
6. **Backup** of current model before deploy

---

## 🚀 Next Steps

After implementing:

1. ✅ **Test manual run**: `python retrain_loop.py`
2. ✅ **Review first report**: Check `reports/` directory
3. ✅ **Configure scheduler**: Edit `auto_scheduler.py`
4. ✅ **Start automation**: Let it run for a week
5. ✅ **Monitor performance**: Track improvements
6. ✅ **Fine-tune**: Adjust thresholds based on results

---

**Automated retraining system ready for production! 🎉**
