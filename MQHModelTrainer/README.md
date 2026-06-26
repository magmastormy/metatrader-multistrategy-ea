# MQH Model Training System

Standalone training framework for MQH AI models, completely isolated from the EA (Expert Advisor) runtime components.

## Folder Structure

```
MQHModelTrainer/
├── Core/                    # Core training infrastructure
│   ├── AI/                  # AI feature vector building (shared)
│   ├── AIModules/           # AI configuration (shared)
│   ├── TrainingMetrics.mqh  # Performance metrics calculation
│   ├── TrainingVisualizer.mqh # Chart visualization
│   └── HyperparameterOptimizer.mqh # Hyperparameter tuning
├── Data/                    # Data handling components
│   ├── CSVDataLoader.mqh    # CSV file loading and parsing
│   ├── DataPreprocessor.mqh # Data normalization and splitting
│   └── LabelEncoder.mqh     # Label encoding utilities
├── Models/                  # Model training and evaluation
│   ├── FeedForwardNN.mqh    # Neural network model
│   ├── TrainingSession.mqh  # Training orchestration
│   ├── ModelEvaluator.mqh   # Model evaluation utilities
│   └── ModelComparer.mqh    # Model comparison utilities
└── Scripts/                 # Runnable scripts (optional)
```

## Key Components

### Data Pipeline
- **CSVDataLoader**: Loads training data exported from `TrainingDataExporter.mq5`
- **DataPreprocessor**: Normalizes data (z-score/min-max) and splits into train/validation/test sets
- **LabelEncoder**: Handles triple-barrier labels (-1, 0, 1) encoding

### Training Core
- **FeedForwardNN**: 4-layer feedforward neural network with Adam optimization
- **TrainingSession**: Orchestrates training epochs, batch processing, validation, and early stopping
- **TrainingMetrics**: Calculates accuracy, precision, recall, F1-score, and confusion matrix

### Evaluation
- **ModelEvaluator**: Evaluates trained models on test data with detailed reports
- **ModelComparer**: Compares multiple models and ranks by performance

### Visualization
- **TrainingVisualizer**: Real-time chart visualization of training progress

### Hyperparameter Tuning
- **HyperparameterOptimizer**: Automated hyperparameter search with default candidates

## Scripts

| Script | Purpose |
|--------|---------|
| `MQHModelTrainer.mq5` | Main training script with data loading, training, and evaluation |
| `MQHModelEvaluator.mq5` | Evaluates trained models on test data |
| `MQHHyperparameterTuner.mq5` | Runs hyperparameter optimization |
| `MQHModelVisualizer.mq5` | Training with real-time chart visualization |

## Complete Training Workflow

### Step 1: Export Training Data
Run `TrainingDataExporter.mq5` in MetaTrader to generate CSV training data:

```
// TrainingDataExporter.mq5 generates:
// TrainingData_{SYMBOL}_{TIMEFRAME}.csv
// Contains: OHLCV, features, signals, consensus, triple-barrier labels
```

### Step 2: Run Hyperparameter Tuning (Optional)
```
1. Load MQHHyperparameterTuner.mq5 in MetaTrader
2. Configure inputs: symbolName, timeframe, dataFile
3. Run the script
4. Review results and select best parameters
```

### Step 3: Train Model
```
1. Load MQHModelTrainer.mq5 in MetaTrader
2. Configure inputs:
   - symbolName: Trading symbol (e.g., "EURUSD")
   - timeframe: Timeframe (e.g., PERIOD_H1)
   - dataFile: Path to exported CSV
   - epochs: Number of training epochs
   - batchSize: Batch size for training
   - learningRate: Learning rate
   - l2Regularization: L2 regularization factor
   - hiddenLayer1/2/3: Hidden layer sizes
3. Run the script
4. Monitor training progress in terminal
5. Model is automatically saved to checkpoint
```

### Step 4: Evaluate Model
```
1. Load MQHModelEvaluator.mq5 in MetaTrader
2. Configure inputs: symbolName, timeframe, dataFile
3. Run the script
4. Review evaluation metrics and confusion matrix
```

### Step 5: Visualize Results
```
1. Load MQHModelVisualizer.mq5 in MetaTrader
2. Configure inputs
3. Run the script
4. View real-time training charts
5. Chart image is automatically saved
```

## Training Configuration

### Default Architecture
- Input: 65 features (FEATURE_VECTOR_SIZE)
- Hidden Layer 1: 32 neurons (ReLU)
- Hidden Layer 2: 16 neurons (ReLU)
- Hidden Layer 3: 8 neurons (ReLU)
- Output: 3 classes (Softmax) - Buy, Hold, Sell

### Training Parameters
- **epochs**: 100 (default)
- **batchSize**: 32 (default)
- **learningRate**: 0.001 (default)
- **l2Regularization**: 0.001 (default)
- **earlyStoppingPatience**: 10 epochs
- **earlyStoppingMinDelta**: 0.0001

### Data Split
- **Train**: 70% (default)
- **Validation**: 20% (default)
- **Test**: 10% (default)

## Evaluation Metrics

| Metric | Description |
|--------|-------------|
| Accuracy | Overall correct predictions |
| Precision | Positive predictive value |
| Recall | True positive rate |
| F1 Score | Harmonic mean of precision and recall |
| Loss | Cross-entropy loss |
| Confusion Matrix | True vs predicted class counts |

## Output Files

| File Type | Naming Pattern | Description |
|-----------|----------------|-------------|
| Model Checkpoint | `NeuralCheckpoint_{SYMBOL}_{TIMEFRAME}.dat` | Trained model weights |
| Evaluation Report | `EvaluationReport_{SYMBOL}_{TIMEFRAME}_{TIMESTAMP}.txt` | Evaluation summary |
| Metrics File | `EvaluationMetrics_{SYMBOL}_{TIMEFRAME}_{TIMESTAMP}.txt` | Detailed metrics |
| Training Chart | `TrainingChart_{SYMBOL}_{TIMEFRAME}_{TIMESTAMP}.png` | Visualization image |
| Hyperparameter Results | `HyperparameterResults_{SYMBOL}_{TIMEFRAME}_{TIMESTAMP}.csv` | Tuning results |

## Integration with EA

The trained model checkpoints are fully compatible with the EA's `CNeuralCheckpointManager`. To use a trained model in the EA:

1. Ensure the model checkpoint file exists in the correct directory
2. Enable AI mode in the EA settings
3. The EA will automatically load and use the trained model

## Best Practices

### Data Preparation
- Always export sufficient historical data (minimum 1000 samples)
- Use consistent timeframes and symbols for training
- Regularly re-export data to include recent market conditions

### Training
- Start with hyperparameter tuning before full training
- Monitor validation loss for overfitting
- Use early stopping to prevent overtraining
- Train on multiple symbols for robustness

### Evaluation
- Always evaluate on unseen test data
- Compare model performance against baseline
- Monitor confusion matrix for class imbalance
- Use confidence-weighted accuracy for trading decisions

### Performance
- Use reasonable batch sizes (16-128) for stability
- Adjust learning rate based on loss curve
- Enable L2 regularization to prevent overfitting

## Logging

The training system produces detailed logs with the following prefixes:
- `[MQH-TRAINER]`: Training process
- `[MQH-EVAL]`: Evaluation process
- `[MQH-VIZ]`: Visualization
- `[MQH-TUNER]`: Hyperparameter tuning
- `[MQH-COMPARE]`: Model comparison

## Requirements

- MetaTrader 5
- MQL5 compiler
- Training data exported via `TrainingDataExporter.mq5`

## License

This project is part of the metatrader-multistrategy-ea repository. See the main project license for details.
