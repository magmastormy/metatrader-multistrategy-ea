"""
Model Evaluation and Comparison System
Backtests models, calculates performance metrics, and compares with baseline
"""

import numpy as np
import pandas as pd
import logging
from typing import Dict, List, Tuple
from datetime import datetime
import json
from pathlib import Path

logger = logging.getLogger(__name__)


class ModelEvaluator:
    """Evaluates model performance and compares with previous versions"""
    
    def __init__(self):
        self.evaluation_history = []
        self.metrics_thresholds = {
            'accuracy': 0.55,  # Minimum accuracy
            'sharpe_ratio': 1.0,  # Minimum Sharpe ratio
            'win_rate': 0.52,  # Minimum win rate
            'max_drawdown': -0.15  # Maximum acceptable drawdown
        }
    
    def backtest_model(self, 
                       model, 
                       X_test: np.ndarray, 
                       y_test: np.ndarray,
                       prices: np.ndarray = None) -> Dict:
        """Backtest model on historical data"""
        
        logger.info("="*60)
        logger.info("BACKTESTING MODEL")
        logger.info("="*60)
        
        # Get predictions
        if hasattr(model, 'predict_proba'):
            y_pred_proba = model.predict_proba(X_test)
            y_pred = np.argmax(y_pred_proba, axis=1) - 1  # Convert to -1, 0, 1
        else:
            y_pred = model.predict(X_test)
        
        # Calculate ML metrics
        ml_metrics = self._calculate_ml_metrics(y_test, y_pred)
        
        # Simulate trading if prices available
        if prices is not None:
            trading_metrics = self._simulate_trading(y_pred, prices)
        else:
            trading_metrics = {}
        
        # Combine metrics
        backtest_results = {
            'timestamp': datetime.now().isoformat(),
            'ml_metrics': ml_metrics,
            'trading_metrics': trading_metrics,
            'test_samples': len(X_test)
        }
        
        logger.info("Backtest Results:")
        logger.info(f"  Accuracy: {ml_metrics.get('accuracy', 0):.4f}")
        if trading_metrics:
            logger.info(f"  Sharpe Ratio: {trading_metrics.get('sharpe_ratio', 0):.4f}")
            logger.info(f"  Win Rate: {trading_metrics.get('win_rate', 0):.4f}")
            logger.info(f"  Max Drawdown: {trading_metrics.get('max_drawdown', 0):.4f}")
        
        return backtest_results
    
    def _calculate_ml_metrics(self, y_true: np.ndarray, y_pred: np.ndarray) -> Dict:
        """Calculate ML performance metrics"""
        from sklearn.metrics import (
            accuracy_score, precision_score, recall_score, f1_score,
            confusion_matrix, classification_report
        )
        
        # Encode if needed
        if np.min(y_true) < 0:
            y_true_encoded = y_true + 1
            y_pred_encoded = y_pred + 1
        else:
            y_true_encoded = y_true
            y_pred_encoded = y_pred
        
        metrics = {
            'accuracy': float(accuracy_score(y_true_encoded, y_pred_encoded)),
            'precision': float(precision_score(y_true_encoded, y_pred_encoded, average='weighted', zero_division=0)),
            'recall': float(recall_score(y_true_encoded, y_pred_encoded, average='weighted', zero_division=0)),
            'f1_score': float(f1_score(y_true_encoded, y_pred_encoded, average='weighted', zero_division=0))
        }
        
        # Confusion matrix
        cm = confusion_matrix(y_true_encoded, y_pred_encoded)
        metrics['confusion_matrix'] = cm.tolist()
        
        # Per-class metrics
        for i, class_name in enumerate(['SELL', 'HOLD', 'BUY']):
            class_precision = precision_score(y_true_encoded == i, y_pred_encoded == i, zero_division=0)
            class_recall = recall_score(y_true_encoded == i, y_pred_encoded == i, zero_division=0)
            metrics[f'{class_name}_precision'] = float(class_precision)
            metrics[f'{class_name}_recall'] = float(class_recall)
        
        return metrics
    
    def _simulate_trading(self, signals: np.ndarray, prices: np.ndarray) -> Dict:
        """Simulate trading based on model signals"""
        
        logger.info("Simulating trading performance...")
        
        # Initialize
        equity = [10000.0]  # Starting capital
        position = 0  # Current position: -1 (short), 0 (flat), 1 (long)
        trades = []
        
        for i in range(1, len(signals)):
            signal = signals[i]
            price = prices[i]
            prev_price = prices[i-1]
            
            # Calculate return based on position
            if position == 1:  # Long position
                ret = (price - prev_price) / prev_price
            elif position == -1:  # Short position
                ret = (prev_price - price) / prev_price
            else:  # No position
                ret = 0
            
            # Update equity
            new_equity = equity[-1] * (1 + ret)
            equity.append(new_equity)
            
            # Update position based on signal
            if signal == 1 and position != 1:  # BUY signal
                trades.append({'type': 'BUY', 'price': price, 'equity': new_equity})
                position = 1
            elif signal == -1 and position != -1:  # SELL signal
                trades.append({'type': 'SELL', 'price': price, 'equity': new_equity})
                position = -1
            elif signal == 0:  # HOLD signal
                if position != 0:
                    trades.append({'type': 'CLOSE', 'price': price, 'equity': new_equity})
                position = 0
        
        # Calculate metrics
        equity = np.array(equity)
        returns = np.diff(equity) / equity[:-1]
        
        # Trading performance metrics
        metrics = {
            'total_return': float((equity[-1] - equity[0]) / equity[0]),
            'total_trades': len(trades),
            'final_equity': float(equity[-1]),
            'sharpe_ratio': self._calculate_sharpe(returns),
            'sortino_ratio': self._calculate_sortino(returns),
            'max_drawdown': self._calculate_max_drawdown(equity),
            'win_rate': self._calculate_win_rate(trades, prices),
            'profit_factor': self._calculate_profit_factor(returns),
            'avg_return_per_trade': float(np.mean(returns)) if len(returns) > 0 else 0.0
        }
        
        return metrics
    
    def _calculate_sharpe(self, returns: np.ndarray, risk_free_rate: float = 0.0) -> float:
        """Calculate Sharpe ratio"""
        if len(returns) < 2:
            return 0.0
        
        excess_returns = returns - risk_free_rate
        if np.std(returns) == 0:
            return 0.0
        
        sharpe = np.mean(excess_returns) / np.std(returns) * np.sqrt(252)  # Annualized
        return float(sharpe)
    
    def _calculate_sortino(self, returns: np.ndarray, risk_free_rate: float = 0.0) -> float:
        """Calculate Sortino ratio"""
        if len(returns) < 2:
            return 0.0
        
        excess_returns = returns - risk_free_rate
        downside_returns = returns[returns < 0]
        
        if len(downside_returns) == 0 or np.std(downside_returns) == 0:
            return 0.0
        
        sortino = np.mean(excess_returns) / np.std(downside_returns) * np.sqrt(252)
        return float(sortino)
    
    def _calculate_max_drawdown(self, equity: np.ndarray) -> float:
        """Calculate maximum drawdown"""
        running_max = np.maximum.accumulate(equity)
        drawdown = (equity - running_max) / running_max
        return float(np.min(drawdown))
    
    def _calculate_win_rate(self, trades: List[Dict], prices: np.ndarray) -> float:
        """Calculate win rate from trades"""
        if len(trades) < 2:
            return 0.5
        
        wins = 0
        total = 0
        
        for i in range(1, len(trades)):
            if trades[i]['equity'] > trades[i-1]['equity']:
                wins += 1
            total += 1
        
        return float(wins / total) if total > 0 else 0.5
    
    def _calculate_profit_factor(self, returns: np.ndarray) -> float:
        """Calculate profit factor"""
        gross_profit = np.sum(returns[returns > 0])
        gross_loss = abs(np.sum(returns[returns < 0]))
        
        if gross_loss == 0:
            return float('inf') if gross_profit > 0 else 0.0
        
        return float(gross_profit / gross_loss)
    
    def compare_with_baseline(self, 
                               new_metrics: Dict, 
                               baseline_metrics: Dict) -> Dict:
        """Compare new model with baseline"""
        
        logger.info("="*60)
        logger.info("COMPARING WITH BASELINE")
        logger.info("="*60)
        
        comparison = {
            'timestamp': datetime.now().isoformat(),
            'new_model': new_metrics,
            'baseline': baseline_metrics,
            'improvements': {},
            'regressions': {},
            'decision': 'REJECT'
        }
        
        # Extract metrics for comparison
        new_ml = new_metrics.get('ml_metrics', {})
        new_trading = new_metrics.get('trading_metrics', {})
        
        baseline_ml = baseline_metrics.get('ml_metrics', {})
        baseline_trading = baseline_metrics.get('trading_metrics', {})
        
        # Compare ML metrics
        if 'accuracy' in new_ml and 'accuracy' in baseline_ml:
            acc_diff = new_ml['accuracy'] - baseline_ml['accuracy']
            comparison['improvements' if acc_diff > 0 else 'regressions']['accuracy'] = acc_diff
            logger.info(f"Accuracy: {new_ml['accuracy']:.4f} vs {baseline_ml['accuracy']:.4f} ({acc_diff:+.4f})")
        
        # Compare trading metrics
        if 'sharpe_ratio' in new_trading and 'sharpe_ratio' in baseline_trading:
            sharpe_diff = new_trading['sharpe_ratio'] - baseline_trading['sharpe_ratio']
            comparison['improvements' if sharpe_diff > 0 else 'regressions']['sharpe_ratio'] = sharpe_diff
            logger.info(f"Sharpe Ratio: {new_trading['sharpe_ratio']:.4f} vs {baseline_trading['sharpe_ratio']:.4f} ({sharpe_diff:+.4f})")
        
        if 'win_rate' in new_trading and 'win_rate' in baseline_trading:
            wr_diff = new_trading['win_rate'] - baseline_trading['win_rate']
            comparison['improvements' if wr_diff > 0 else 'regressions']['win_rate'] = wr_diff
            logger.info(f"Win Rate: {new_trading['win_rate']:.4f} vs {baseline_trading['win_rate']:.4f} ({wr_diff:+.4f})")
        
        # Make decision
        decision_score = 0
        
        # Accuracy improvement (weight: 2)
        if 'accuracy' in comparison['improvements']:
            decision_score += 2 if comparison['improvements']['accuracy'] > 0.01 else 1
        
        # Sharpe improvement (weight: 3)
        if 'sharpe_ratio' in comparison['improvements']:
            decision_score += 3 if comparison['improvements']['sharpe_ratio'] > 0.1 else 1
        
        # Win rate improvement (weight: 2)
        if 'win_rate' in comparison['improvements']:
            decision_score += 2 if comparison['improvements']['win_rate'] > 0.02 else 1
        
        # Check regressions (penalty)
        if 'accuracy' in comparison['regressions']:
            if comparison['regressions']['accuracy'] < -0.02:
                decision_score -= 3
        
        # Minimum thresholds check
        meets_thresholds = self._check_thresholds(new_metrics)
        
        # Final decision
        if decision_score >= 3 and meets_thresholds:
            comparison['decision'] = 'APPROVE'
            logger.info("✅ DECISION: APPROVE - New model is superior")
        else:
            comparison['decision'] = 'REJECT'
            logger.info("❌ DECISION: REJECT - Model does not meet improvement criteria")
        
        logger.info(f"Decision Score: {decision_score}/7")
        logger.info("="*60)
        
        return comparison
    
    def _check_thresholds(self, metrics: Dict) -> bool:
        """Check if metrics meet minimum thresholds"""
        
        ml_metrics = metrics.get('ml_metrics', {})
        trading_metrics = metrics.get('trading_metrics', {})
        
        checks = []
        
        # Accuracy threshold
        if 'accuracy' in ml_metrics:
            checks.append(ml_metrics['accuracy'] >= self.metrics_thresholds['accuracy'])
        
        # Sharpe ratio threshold
        if 'sharpe_ratio' in trading_metrics:
            checks.append(trading_metrics['sharpe_ratio'] >= self.metrics_thresholds['sharpe_ratio'])
        
        # Win rate threshold
        if 'win_rate' in trading_metrics:
            checks.append(trading_metrics['win_rate'] >= self.metrics_thresholds['win_rate'])
        
        # Max drawdown threshold
        if 'max_drawdown' in trading_metrics:
            checks.append(trading_metrics['max_drawdown'] >= self.metrics_thresholds['max_drawdown'])
        
        meets_all = all(checks) if checks else False
        
        logger.info(f"Threshold checks: {sum(checks)}/{len(checks)} passed")
        
        return meets_all
    
    def generate_evaluation_report(self, 
                                    backtest_results: Dict, 
                                    comparison: Dict,
                                    output_file: str = None) -> str:
        """Generate comprehensive evaluation report"""
        
        report = []
        report.append("="*60)
        report.append("MODEL EVALUATION REPORT")
        report.append("="*60)
        report.append(f"Generated: {datetime.now().isoformat()}")
        report.append("")
        
        # Backtest results
        report.append("## BACKTEST RESULTS")
        report.append("")
        
        ml_metrics = backtest_results.get('ml_metrics', {})
        report.append("### Machine Learning Metrics")
        for key, value in ml_metrics.items():
            if key != 'confusion_matrix':
                report.append(f"  {key}: {value:.4f}")
        report.append("")
        
        trading_metrics = backtest_results.get('trading_metrics', {})
        if trading_metrics:
            report.append("### Trading Performance Metrics")
            for key, value in trading_metrics.items():
                report.append(f"  {key}: {value:.4f}")
            report.append("")
        
        # Comparison
        if comparison:
            report.append("## COMPARISON WITH BASELINE")
            report.append("")
            
            improvements = comparison.get('improvements', {})
            if improvements:
                report.append("### Improvements")
                for key, value in improvements.items():
                    report.append(f"  {key}: {value:+.4f}")
                report.append("")
            
            regressions = comparison.get('regressions', {})
            if regressions:
                report.append("### Regressions")
                for key, value in regressions.items():
                    report.append(f"  {key}: {value:+.4f}")
                report.append("")
            
            report.append(f"**DECISION: {comparison.get('decision', 'UNKNOWN')}**")
            report.append("")
        
        report.append("="*60)
        
        report_text = "\n".join(report)
        
        # Save to file if specified
        if output_file:
            with open(output_file, 'w') as f:
                f.write(report_text)
            logger.info(f"Report saved: {output_file}")
        
        return report_text
