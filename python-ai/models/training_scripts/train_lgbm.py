"""Train LightGBM model for trading"""
import numpy as np
import pandas as pd
import pickle
from pathlib import Path
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

try:
    import lightgbm as lgb
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import accuracy_score, precision_score, recall_score
    LGBM_AVAILABLE = True
except ImportError:
    LGBM_AVAILABLE = False
    logger.error("LightGBM not available - install with: pip install lightgbm scikit-learn")


def generate_training_data(n_samples=10000):
    """Generate synthetic training data"""
    logger.info(f"Generating {n_samples} training samples...")
    
    # Generate features (20 features matching our feature engineer)
    features = np.random.randn(n_samples, 20)
    
    # Generate labels based on feature patterns
    # Signal: -1 (SELL), 0 (HOLD), 1 (BUY)
    # Use momentum and trend features to create realistic labels
    momentum = features[:, 1]
    trend = features[:, 4]
    
    signals = np.tanh(momentum * 3 + trend * 2)
    
    # Convert continuous signals to discrete labels
    labels = np.zeros(n_samples)
    labels[signals > 0.3] = 1  # BUY
    labels[signals < -0.3] = -1  # SELL
    
    return features, labels


def train_lgbm_model(X_train, y_train, X_val, y_val):
    """Train LightGBM model"""
    logger.info("Training LightGBM model...")
    
    # Convert labels to positive integers for LightGBM
    y_train_encoded = (y_train + 1).astype(int)  # -1,0,1 -> 0,1,2
    y_val_encoded = (y_val + 1).astype(int)
    
    # Create datasets
    train_data = lgb.Dataset(X_train, label=y_train_encoded)
    val_data = lgb.Dataset(X_val, label=y_val_encoded, reference=train_data)
    
    # Parameters
    params = {
        'objective': 'multiclass',
        'num_class': 3,
        'metric': 'multi_logloss',
        'boosting_type': 'gbdt',
        'num_leaves': 31,
        'learning_rate': 0.05,
        'feature_fraction': 0.8,
        'bagging_fraction': 0.8,
        'bagging_freq': 5,
        'verbose': 0
    }
    
    # Train
    model = lgb.train(
        params,
        train_data,
        num_boost_round=150,
        valid_sets=[train_data, val_data],
        valid_names=['train', 'valid'],
        callbacks=[lgb.early_stopping(stopping_rounds=10), lgb.log_evaluation(period=20)]
    )
    
    return model


def evaluate_model(model, X_test, y_test):
    """Evaluate model performance"""
    logger.info("Evaluating model...")
    
    # Predict
    y_pred_proba = model.predict(X_test)
    y_pred = np.argmax(y_pred_proba, axis=1)
    
    # Convert back to -1, 0, 1
    y_pred = y_pred - 1
    
    # Calculate metrics
    accuracy = accuracy_score(y_test, y_pred)
    
    # Precision and recall for each class
    precision_buy = precision_score(y_test == 1, y_pred == 1, zero_division=0)
    recall_buy = recall_score(y_test == 1, y_pred == 1, zero_division=0)
    
    precision_sell = precision_score(y_test == -1, y_pred == -1, zero_division=0)
    recall_sell = recall_score(y_test == -1, y_pred == -1, zero_division=0)
    
    logger.info(f"Accuracy: {accuracy:.4f}")
    logger.info(f"BUY - Precision: {precision_buy:.4f}, Recall: {recall_buy:.4f}")
    logger.info(f"SELL - Precision: {precision_sell:.4f}, Recall: {recall_sell:.4f}")
    
    return {
        'accuracy': accuracy,
        'precision_buy': precision_buy,
        'recall_buy': recall_buy,
        'precision_sell': precision_sell,
        'recall_sell': recall_sell
    }


def main():
    """Main training function"""
    if not LGBM_AVAILABLE:
        logger.error("LightGBM not available")
        return
    
    logger.info("="*60)
    logger.info("LightGBM Model Training")
    logger.info("="*60)
    
    # Generate data
    X, y = generate_training_data(n_samples=10000)
    
    # Split data
    X_train, X_temp, y_train, y_temp = train_test_split(X, y, test_size=0.3, random_state=42)
    X_val, X_test, y_val, y_test = train_test_split(X_temp, y_temp, test_size=0.5, random_state=42)
    
    logger.info(f"Train size: {len(X_train)}")
    logger.info(f"Val size: {len(X_val)}")
    logger.info(f"Test size: {len(X_test)}")
    
    # Train model
    model = train_lgbm_model(X_train, y_train, X_val, y_val)
    
    # Evaluate
    metrics = evaluate_model(model, X_test, y_test)
    
    # Save model
    model_dir = Path("../")
    model_dir.mkdir(exist_ok=True)
    
    model_path = model_dir / "lgbm_model.pkl"
    with open(model_path, 'wb') as f:
        pickle.dump(model, f)
    
    logger.info(f"✅ Model saved to {model_path.absolute()}")
    logger.info("="*60)


if __name__ == "__main__":
    main()
