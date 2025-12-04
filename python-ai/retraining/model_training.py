"""
Model Training Module with Hyperparameter Optimization
Supports LightGBM, Transformer, and auto-optimization with Optuna
"""

import numpy as np
import pandas as pd
import logging
from pathlib import Path
from typing import Dict, Tuple, Optional
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

try:
    import lightgbm as lgb
    from sklearn.model_selection import train_test_split, KFold
    from sklearn.metrics import accuracy_score, precision_score, recall_score, f1_score
    SKLEARN_AVAILABLE = True
except ImportError:
    SKLEARN_AVAILABLE = False
    logger.warning("scikit-learn not available")

try:
    import optuna
    OPTUNA_AVAILABLE = True
except ImportError:
    OPTUNA_AVAILABLE = False
    logger.warning("Optuna not available - install with: pip install optuna")

try:
    import torch
    import torch.nn as nn
    TORCH_AVAILABLE = True
except ImportError:
    TORCH_AVAILABLE = False


class ModelTrainer:
    """Automated model training with hyperparameter optimization"""
    
    def __init__(self, output_dir: str = "models"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(exist_ok=True)
        
        self.best_params = {}
        self.training_history = []
    
    def train_lgbm_with_optuna(self, 
                                X_train: np.ndarray,
                                y_train: np.ndarray,
                                X_val: np.ndarray,
                                y_val: np.ndarray,
                                n_trials: int = 50) -> Tuple[object, Dict]:
        """Train LightGBM with Optuna hyperparameter optimization"""
        
        if not OPTUNA_AVAILABLE:
            logger.error("Optuna not available")
            return None, {}
        
        logger.info("="*60)
        logger.info("LIGHTGBM TRAINING WITH OPTUNA OPTIMIZATION")
        logger.info("="*60)
        
        def objective(trial):
            """Optuna objective function"""
            params = {
                'objective': 'multiclass',
                'num_class': 3,
                'metric': 'multi_logloss',
                'boosting_type': 'gbdt',
                'verbosity': -1,
                
                # Hyperparameters to optimize
                'num_leaves': trial.suggest_int('num_leaves', 20, 100),
                'max_depth': trial.suggest_int('max_depth', 3, 12),
                'learning_rate': trial.suggest_float('learning_rate', 0.01, 0.3, log=True),
                'n_estimators': trial.suggest_int('n_estimators', 50, 300),
                'min_child_samples': trial.suggest_int('min_child_samples', 10, 50),
                'subsample': trial.suggest_float('subsample', 0.6, 1.0),
                'colsample_bytree': trial.suggest_float('colsample_bytree', 0.6, 1.0),
                'reg_alpha': trial.suggest_float('reg_alpha', 1e-8, 10.0, log=True),
                'reg_lambda': trial.suggest_float('reg_lambda', 1e-8, 10.0, log=True),
            }
            
            # Convert target to positive integers
            y_train_encoded = (y_train + 1).astype(int)
            y_val_encoded = (y_val + 1).astype(int)
            
            # Train model
            model = lgb.LGBMClassifier(**params)
            model.fit(
                X_train, y_train_encoded,
                eval_set=[(X_val, y_val_encoded)],
                callbacks=[lgb.early_stopping(stopping_rounds=10, verbose=False)]
            )
            
            # Evaluate
            y_pred = model.predict(X_val)
            accuracy = accuracy_score(y_val_encoded, y_pred)
            
            return accuracy
        
        # Create study
        study = optuna.create_study(direction='maximize', study_name='lgbm_optimization')
        study.optimize(objective, n_trials=n_trials, show_progress_bar=True)
        
        logger.info(f"Best trial: {study.best_trial.number}")
        logger.info(f"Best accuracy: {study.best_value:.4f}")
        logger.info(f"Best parameters: {study.best_params}")
        
        # Train final model with best parameters
        best_params = study.best_params
        best_params.update({
            'objective': 'multiclass',
            'num_class': 3,
            'metric': 'multi_logloss',
            'boosting_type': 'gbdt',
            'verbosity': -1
        })
        
        y_train_encoded = (y_train + 1).astype(int)
        y_val_encoded = (y_val + 1).astype(int)
        
        final_model = lgb.LGBMClassifier(**best_params)
        final_model.fit(
            X_train, y_train_encoded,
            eval_set=[(X_val, y_val_encoded)],
            callbacks=[lgb.early_stopping(stopping_rounds=10)]
        )
        
        self.best_params['lgbm'] = best_params
        
        return final_model, best_params
    
    def train_with_cross_validation(self,
                                     X: np.ndarray,
                                     y: np.ndarray,
                                     model_type: str = 'lgbm',
                                     n_folds: int = 5) -> Dict:
        """Train model with K-fold cross-validation"""
        
        logger.info(f"Training {model_type} with {n_folds}-fold cross-validation...")
        
        kfold = KFold(n_splits=n_folds, shuffle=True, random_state=42)
        
        fold_results = []
        
        for fold, (train_idx, val_idx) in enumerate(kfold.split(X)):
            logger.info(f"Fold {fold + 1}/{n_folds}")
            
            X_train_fold, X_val_fold = X[train_idx], X[val_idx]
            y_train_fold, y_val_fold = y[train_idx], y[val_idx]
            
            if model_type == 'lgbm':
                # Train LightGBM
                y_train_encoded = (y_train_fold + 1).astype(int)
                y_val_encoded = (y_val_fold + 1).astype(int)
                
                model = lgb.LGBMClassifier(
                    n_estimators=150,
                    max_depth=6,
                    learning_rate=0.05,
                    verbosity=-1
                )
                model.fit(X_train_fold, y_train_encoded)
                
                # Evaluate
                y_pred = model.predict(X_val_fold)
                accuracy = accuracy_score(y_val_encoded, y_pred)
                
                fold_results.append({
                    'fold': fold + 1,
                    'accuracy': accuracy,
                    'train_size': len(X_train_fold),
                    'val_size': len(X_val_fold)
                })
                
                logger.info(f"Fold {fold + 1} accuracy: {accuracy:.4f}")
        
        # Calculate average metrics
        avg_accuracy = np.mean([r['accuracy'] for r in fold_results])
        std_accuracy = np.std([r['accuracy'] for r in fold_results])
        
        cv_results = {
            'avg_accuracy': avg_accuracy,
            'std_accuracy': std_accuracy,
            'fold_results': fold_results,
            'n_folds': n_folds
        }
        
        logger.info(f"Cross-validation complete: {avg_accuracy:.4f} ± {std_accuracy:.4f}")
        
        return cv_results
    
    def train_final_model(self,
                          X_train: np.ndarray,
                          y_train: np.ndarray,
                          X_val: np.ndarray,
                          y_val: np.ndarray,
                          model_type: str = 'lgbm',
                          params: Optional[Dict] = None) -> object:
        """Train final model with best parameters"""
        
        logger.info(f"Training final {model_type} model...")
        
        if model_type == 'lgbm':
            y_train_encoded = (y_train + 1).astype(int)
            y_val_encoded = (y_val + 1).astype(int)
            
            if params is None:
                params = self.best_params.get('lgbm', {
                    'n_estimators': 150,
                    'max_depth': 6,
                    'learning_rate': 0.05
                })
            
            model = lgb.LGBMClassifier(**params, verbosity=-1)
            model.fit(
                X_train, y_train_encoded,
                eval_set=[(X_val, y_val_encoded)],
                callbacks=[lgb.early_stopping(stopping_rounds=10)]
            )
            
            # Evaluate
            y_pred = model.predict(X_val)
            accuracy = accuracy_score(y_val_encoded, y_pred)
            precision = precision_score(y_val_encoded, y_pred, average='weighted', zero_division=0)
            recall = recall_score(y_val_encoded, y_pred, average='weighted', zero_division=0)
            f1 = f1_score(y_val_encoded, y_pred, average='weighted', zero_division=0)
            
            logger.info(f"Final model performance:")
            logger.info(f"  Accuracy:  {accuracy:.4f}")
            logger.info(f"  Precision: {precision:.4f}")
            logger.info(f"  Recall:    {recall:.4f}")
            logger.info(f"  F1 Score:  {f1:.4f}")
            
            # Store training history
            self.training_history.append({
                'timestamp': datetime.now().isoformat(),
                'model_type': model_type,
                'accuracy': accuracy,
                'precision': precision,
                'recall': recall,
                'f1_score': f1,
                'params': params
            })
            
            return model
        
        else:
            raise ValueError(f"Unsupported model type: {model_type}")
    
    def save_model(self, model, model_name: str, metadata: Dict = None):
        """Save trained model"""
        import pickle
        
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f"{model_name}_{timestamp}.pkl"
        filepath = self.output_dir / filename
        
        with open(filepath, 'wb') as f:
            pickle.dump(model, f)
        
        logger.info(f"Model saved: {filepath}")
        
        # Save metadata
        if metadata:
            metadata_file = filepath.with_suffix('.json')
            import json
            with open(metadata_file, 'w') as f:
                json.dump(metadata, f, indent=2)
            logger.info(f"Metadata saved: {metadata_file}")
        
        return filepath
