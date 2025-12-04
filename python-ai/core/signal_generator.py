"""Trading signal generation from ML predictions"""
import numpy as np
from typing import Dict, Optional
from datetime import datetime
import logging

logger = logging.getLogger(__name__)


class SignalGenerator:
    """Converts ML predictions into actionable trading signals"""
    
    def __init__(self, 
                 buy_threshold: float = 0.7,
                 sell_threshold: float = -0.7,
                 confidence_min: float = 0.6):
        
        self.buy_threshold = buy_threshold
        self.sell_threshold = sell_threshold
        self.confidence_min = confidence_min
        
        self.signal_history = []
        
    def generate_signal(self, 
                       prediction: Dict,
                       market_data: Dict,
                       symbol: str = "UNKNOWN") -> Dict:
        """Generate trading signal from ML prediction"""
        
        try:
            signal_value = prediction.get('signal', 0.0)
            confidence = prediction.get('confidence', 0.0)
            
            # Determine action
            if confidence < self.confidence_min:
                action = "NONE"
                reason = f"Low confidence: {confidence:.2f}"
            elif signal_value >= self.buy_threshold:
                action = "BUY"
                reason = f"Strong buy signal: {signal_value:.2f}, confidence: {confidence:.2f}"
            elif signal_value <= self.sell_threshold:
                action = "SELL"
                reason = f"Strong sell signal: {signal_value:.2f}, confidence: {confidence:.2f}"
            else:
                action = "NONE"
                reason = f"Neutral signal: {signal_value:.2f}"
            
            # Calculate SL/TP if action is BUY or SELL
            sl, tp = self._calculate_sl_tp(action, market_data, signal_value)
            
            signal = {
                'symbol': symbol,
                'timestamp': datetime.now().isoformat(),
                'action': action,
                'signal_value': float(signal_value),
                'confidence': float(confidence),
                'stop_loss': float(sl) if sl else None,
                'take_profit': float(tp) if tp else None,
                'reason': reason,
                'raw_prediction': prediction
            }
            
            # Store in history
            self.signal_history.append(signal)
            if len(self.signal_history) > 1000:
                self.signal_history = self.signal_history[-1000:]
            
            logger.info(f"Signal generated: {action} for {symbol}, confidence: {confidence:.2f}")
            
            return signal
            
        except Exception as e:
            logger.error(f"Signal generation error: {e}")
            return self._generate_neutral_signal(symbol)
    
    def _calculate_sl_tp(self, action: str, market_data: Dict, signal_strength: float) -> tuple:
        """Calculate stop loss and take profit levels"""
        try:
            if action == "NONE":
                return None, None
            
            # Get current price
            if 'close' in market_data:
                close_prices = market_data['close']
                current_price = close_prices[-1] if isinstance(close_prices, (list, np.ndarray)) else close_prices
            else:
                return None, None
            
            # Calculate ATR for dynamic SL/TP
            if isinstance(market_data.get('close'), (list, np.ndarray)) and len(market_data['close']) >= 20:
                prices = np.array(market_data['close'])
                atr = np.std(np.diff(prices[-20:])) * 2
            else:
                atr = current_price * 0.01  # Default 1% ATR
            
            # Risk-reward ratio based on signal strength
            risk_multiplier = 1.5 + abs(signal_strength) * 0.5
            reward_multiplier = 2.0 + abs(signal_strength) * 1.0
            
            if action == "BUY":
                sl = current_price - (atr * risk_multiplier)
                tp = current_price + (atr * reward_multiplier)
            else:  # SELL
                sl = current_price + (atr * risk_multiplier)
                tp = current_price - (atr * reward_multiplier)
            
            return sl, tp
            
        except Exception as e:
            logger.error(f"SL/TP calculation error: {e}")
            return None, None
    
    def _generate_neutral_signal(self, symbol: str) -> Dict:
        """Generate neutral signal in case of error"""
        return {
            'symbol': symbol,
            'timestamp': datetime.now().isoformat(),
            'action': "NONE",
            'signal_value': 0.0,
            'confidence': 0.0,
            'stop_loss': None,
            'take_profit': None,
            'reason': "Error in signal generation",
            'raw_prediction': {}
        }
    
    def get_signal_statistics(self) -> Dict:
        """Get statistics about generated signals"""
        if not self.signal_history:
            return {'total': 0}
        
        actions = [s['action'] for s in self.signal_history]
        
        return {
            'total': len(self.signal_history),
            'buy_signals': actions.count('BUY'),
            'sell_signals': actions.count('SELL'),
            'neutral_signals': actions.count('NONE'),
            'avg_confidence': np.mean([s['confidence'] for s in self.signal_history])
        }
