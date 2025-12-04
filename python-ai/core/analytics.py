"""Analytics and performance tracking"""
import numpy as np
from typing import Dict, List, Optional
from datetime import datetime
import logging
import json
from pathlib import Path

logger = logging.getLogger(__name__)


class Analytics:
    """Track and analyze system performance"""
    
    def __init__(self, log_dir: str = "logs"):
        self.log_dir = Path(log_dir)
        self.log_dir.mkdir(exist_ok=True)
        
        self.predictions = []
        self.signals = []
        self.trades = []
        self.performance_metrics = {}
        
    def log_prediction(self, prediction: Dict):
        """Log a prediction"""
        prediction['timestamp'] = datetime.now().isoformat()
        self.predictions.append(prediction)
        
        # Keep last 10000 predictions
        if len(self.predictions) > 10000:
            self.predictions = self.predictions[-10000:]
    
    def log_signal(self, signal: Dict):
        """Log a generated signal"""
        self.signals.append(signal)
        
        if len(self.signals) > 10000:
            self.signals = self.signals[-10000:]
    
    def log_trade(self, trade: Dict):
        """Log an executed trade"""
        trade['timestamp'] = datetime.now().isoformat()
        self.trades.append(trade)
        
        # Save to file
        self._save_trade_log(trade)
    
    def _save_trade_log(self, trade: Dict):
        """Save trade to log file"""
        try:
            log_file = self.log_dir / "trades.jsonl"
            with open(log_file, 'a') as f:
                f.write(json.dumps(trade) + '\n')
        except Exception as e:
            logger.error(f"Failed to save trade log: {e}")
    
    def calculate_performance_metrics(self) -> Dict:
        """Calculate comprehensive performance metrics"""
        try:
            if not self.trades:
                return {
                    'total_trades': 0,
                    'status': 'No trades executed'
                }
            
            # Extract trade results
            profits = []
            for trade in self.trades:
                if 'profit' in trade:
                    profits.append(trade['profit'])
            
            if not profits:
                return {
                    'total_trades': len(self.trades),
                    'status': 'No completed trades'
                }
            
            profits = np.array(profits)
            
            # Calculate metrics
            metrics = {
                'total_trades': len(self.trades),
                'profitable_trades': int(np.sum(profits > 0)),
                'losing_trades': int(np.sum(profits < 0)),
                'win_rate': float(np.mean(profits > 0)),
                'total_profit': float(np.sum(profits)),
                'avg_profit': float(np.mean(profits)),
                'avg_win': float(np.mean(profits[profits > 0])) if np.any(profits > 0) else 0.0,
                'avg_loss': float(np.mean(profits[profits < 0])) if np.any(profits < 0) else 0.0,
                'max_profit': float(np.max(profits)),
                'max_loss': float(np.min(profits)),
                'profit_factor': self._calculate_profit_factor(profits),
                'sharpe_ratio': self._calculate_sharpe_ratio(profits),
                'max_drawdown': self._calculate_max_drawdown(profits)
            }
            
            self.performance_metrics = metrics
            return metrics
            
        except Exception as e:
            logger.error(f"Error calculating metrics: {e}")
            return {'error': str(e)}
    
    def _calculate_profit_factor(self, profits: np.ndarray) -> float:
        """Calculate profit factor"""
        gross_profit = np.sum(profits[profits > 0])
        gross_loss = abs(np.sum(profits[profits < 0]))
        
        if gross_loss == 0:
            return float('inf') if gross_profit > 0 else 0.0
        
        return float(gross_profit / gross_loss)
    
    def _calculate_sharpe_ratio(self, returns: np.ndarray) -> float:
        """Calculate Sharpe ratio"""
        if len(returns) < 2:
            return 0.0
        
        mean_return = np.mean(returns)
        std_return = np.std(returns)
        
        if std_return == 0:
            return 0.0
        
        return float(mean_return / std_return * np.sqrt(252))  # Annualized
    
    def _calculate_max_drawdown(self, profits: np.ndarray) -> float:
        """Calculate maximum drawdown"""
        if len(profits) == 0:
            return 0.0
        
        equity_curve = np.cumsum(profits)
        running_max = np.maximum.accumulate(equity_curve)
        drawdown = equity_curve - running_max
        
        return float(np.min(drawdown))
    
    def get_prediction_accuracy(self) -> Dict:
        """Calculate prediction accuracy metrics"""
        if len(self.predictions) < 10:
            return {'status': 'Insufficient data'}
        
        confidences = [p['confidence'] for p in self.predictions]
        
        return {
            'total_predictions': len(self.predictions),
            'avg_confidence': float(np.mean(confidences)),
            'high_confidence_predictions': int(np.sum(np.array(confidences) > 0.7)),
            'low_confidence_predictions': int(np.sum(np.array(confidences) < 0.5))
        }
    
    def get_signal_statistics(self) -> Dict:
        """Get signal generation statistics"""
        if not self.signals:
            return {'total_signals': 0}
        
        actions = [s['action'] for s in self.signals]
        confidences = [s['confidence'] for s in self.signals]
        
        return {
            'total_signals': len(self.signals),
            'buy_signals': actions.count('BUY'),
            'sell_signals': actions.count('SELL'),
            'neutral_signals': actions.count('NONE'),
            'avg_confidence': float(np.mean(confidences)),
            'signal_rate': len([a for a in actions if a != 'NONE']) / len(actions) if actions else 0.0
        }
    
    def generate_report(self) -> str:
        """Generate comprehensive analytics report"""
        report = []
        report.append("=" * 60)
        report.append("AI TRADING SYSTEM - ANALYTICS REPORT")
        report.append("=" * 60)
        report.append(f"Generated: {datetime.now().isoformat()}")
        report.append("")
        
        # Performance metrics
        metrics = self.calculate_performance_metrics()
        report.append("PERFORMANCE METRICS:")
        for key, value in metrics.items():
            report.append(f"  {key}: {value}")
        report.append("")
        
        # Prediction accuracy
        pred_accuracy = self.get_prediction_accuracy()
        report.append("PREDICTION ACCURACY:")
        for key, value in pred_accuracy.items():
            report.append(f"  {key}: {value}")
        report.append("")
        
        # Signal statistics
        signal_stats = self.get_signal_statistics()
        report.append("SIGNAL STATISTICS:")
        for key, value in signal_stats.items():
            report.append(f"  {key}: {value}")
        report.append("")
        
        report.append("=" * 60)
        
        return "\n".join(report)
    
    def export_to_csv(self, filename: str = "analytics_export.csv"):
        """Export analytics data to CSV"""
        import csv
        
        try:
            filepath = self.log_dir / filename
            with open(filepath, 'w', newline='') as f:
                if self.trades:
                    writer = csv.DictWriter(f, fieldnames=self.trades[0].keys())
                    writer.writeheader()
                    writer.writerows(self.trades)
                logger.info(f"Analytics exported to {filepath}")
        except Exception as e:
            logger.error(f"Export failed: {e}")
