📄 MODEL RETRAINING LOOP — SYSTEM BLUEPRINT (Ready for Claude)
1. Objective

Implement a fully automated model-retraining pipeline for the Hybrid Python AI stack. The system ingests fresh trading data, cleans it, augments it, retrains models, evaluates performance, versions artifacts, and deploys only if performance metrics beat the previous benchmark.

2. System Architecture Overview
Core Components

Data Ingestion Layer

Pulls: MT5 log files, EA signals, OHLC price feeds, strategy metadata, test results.

Sources: Local logs, remote API, DB entries, CSV drops.

Scheduled via CRON or Airflow-like lightweight scheduler.

Data Lake

/raw/ → untouched logs

/processed/ → cleaned datasets

/training_sets/ → final ML-ready sets

Feature Engineering Module

Extracts features from logs, orders, indicators, risk metrics.

Feature groups:

Price-based (OHLC, returns, volatility)

Log-based (entry reason, exit reason, slippage)

Strategy-based (win rate, drawdown, expectancy)

Normalization & encoding handled automatically.

Model Training Module

Supports:

LSTM/Transformer for sequence prediction

RandomForest/XGBoost for signal classification

Reinforcement Learning agent (optional upgrade)

Hyperparameters auto-optimized with Optuna.

Model Evaluation

Metrics:

Sharpe, Sortino, Max Drawdown

Win rate, average RRR

Latency & execution quality

Automatic comparison with previous best model.

Model Registry

Stores:

Version number

Metrics report

Training date

Dataset hash

Only pushes a new version if it’s superior.

Deployment Pipeline

Hot-swap the Python model in the bridge layer.

Regenerate inference graphs + config files.

Log deployment metadata for rollback.

3. Continuous Retraining Loop (Full Flow)
Step 1 — Data Collection
Collect → Validate → Timestamp → Store in /raw

Copy And Save
Share
Ask Copilot

Auto checks for corrupted rows.

Detects missing values and reconstructs when possible.

Step 2 — Preprocessing
Clean → Normalize → Remove noise → Engineer features

Copy And Save
Share
Ask Copilot

Extracts structured trades from logs.

Converts to ML-friendly format.

Step 3 — Dataset Building
Train/Val/Test split: 70/20/10
Sliding window splitting for sequence models

Copy And Save
Share
Ask Copilot
Step 4 — Model Training
Optuna hyperparameter search
N-fold cross validation
Early stopping enabled

Copy And Save
Share
Ask Copilot
Step 5 — Backtesting & Metrics
Simulate model decisions on historical data
Generate full analytics report
Compute risk metrics

Copy And Save
Share
Ask Copilot
Step 6 — Compare With Previous Model
If new_model.metric_score > best_model.metric_score → Approve
Else → Reject

Copy And Save
Share
Ask Copilot
Step 7 — Deployment
Export model → Register version → Send to bridge layer
Rebuild inference worker → Hot reload

Copy And Save
Share
Ask Copilot
Step 8 — Logging & Monitoring

Every training run produces:

training_report.md

confusion matrix

feature importance plot

backtest equity curve

4. Python–MQL Bridge Requirements
Communication Layer Options

REST API (FastAPI)

ZeroMQ (low-latency)

Local file-based IPC (for offline MT5)

Pipes/WebSockets for real-time streaming

Bridge Responsibilities

Send inference requests from MQL to Python

Return predicted signals, risk values, and model confidence

Log all predictions back into dataset for future retraining

Payload Structure
{
  "timestamp": "...",
  "symbol": "EURUSD",
  "features": {...},
  "context": {...},
  "bridge_version": "v3.1"
}

Copy And Save
Share
Ask Copilot
5. Automation Rules

Retrain daily OR when:

new logs surpass N rows

strategy shows deviation

equity curve anomalies detected

Auto-archive old datasets and models

Auto-document everything into /docs/retrain/

6. Files Claude Must Generate

retrain_loop.py

feature_engineering.py

model_training.py

model_evaluation.py

model_registry.json

bridge_adapter.py

training_report_template.md

auto_scheduler.py

7. Deliverables From Claude

Claude must output:

✔️ Fully rewritten modules
✔️ Optimized pipeline code
✔️ A polished documentation file
✔️ A graph showing retraining cycle
✔️ An upgraded dataset schema
✔️ A new versioning strategy
✔️ Suggestions for future improvements