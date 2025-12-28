"""Advanced trading signal generation with multi-timeframe confluence and dynamic thresholds"""
import numpy as np
from typing import Dict, Optional, List
from datetime import datetime
import logging
from collections import deque

logger = logging.getLogger(__name__)


class SignalGenerator:
    """Advanced signal generator with regime-aware thresholds and multi-timeframe analysis"""
    
    def __init__(self, 
                 buy_threshold: float = 0.7,
                 sell_threshold: float = -0.7,
                 confidence_min: float = 0.6,
                 use_dynamic_thresholds: bool = True):
        
        self.base_buy_threshold = buy_threshold
        self.base_sell_threshold = sell_threshold
        self.confidence_min = confidence_min
        self.use_dynamic_thresholds = use_dynamic_thresholds
        
        self.signal_history = deque(maxlen=1000)
        self.prediction_history = deque(maxlen=100)
        
        # Dynamic threshold adjustment
        self.recent_performance = deque(maxlen=50)
        self.threshold_adjustment = 0.0
        
    def generate_signal(self, 
                       prediction: Dict,
                       market_data: Dict,
                       symbol: str = "UNKNOWN",
                       regime: Optional[Dict] = None) -> Dict:
        """Generate advanced trading signal with regime-aware thresholds and multi-timeframe analysis"""
        
        try:
            signal_value = prediction.get('signal', 0.0)
            confidence = prediction.get('confidence', 0.0)
            uncertainty = prediction.get('uncertainty', 0.5)
            
            # Store prediction for analysis
            self.prediction_history.append({
                'signal': signal_value,
                'confidence': confidence,
                'uncertainty': uncertainty,
                'timestamp': datetime.now()
            })
            
            # Dynamic threshold adjustment
            buy_threshold, sell_threshold = self._get_dynamic_thresholds(regime)
            
            # Multi-factor signal strength calculation
            signal_strength = self._calculate_signal_strength(
                signal_value, confidence, uncertainty, market_data
            )
            
            # Determine action with enhanced logic
            if confidence < self.confidence_min:
                action = "NONE"
                reason = f"Low confidence: {confidence:.2f} < {self.confidence_min}"
            elif uncertainty > 0.7:
                action = "NONE"
                reason = f"High uncertainty: {uncertainty:.2f}"
            elif signal_strength >= buy_threshold:
                action = "BUY"
                reason = f"Strong buy: signal={signal_value:.2f}, strength={signal_strength:.2f}, conf={confidence:.2f}"
            elif signal_strength <= sell_threshold:
                action = "SELL"
                reason = f"Strong sell: signal={signal_value:.2f}, strength={signal_strength:.2f}, conf={confidence:.2f}"
            else:
                action = "NONE"
                reason = f"Neutral: signal={signal_value:.2f}, strength={signal_strength:.2f}"
            
            # Calculate SL/TP with advanced methods
            sl, tp, risk_reward = self._calculate_sl_tp_advanced(
                action, market_data, signal_strength, confidence, regime
            )
            
            signal = {
                'symbol': symbol,
                'timestamp': datetime.now().isoformat(),
                'action': action,
                'signal_value': float(signal_value),
                'signal_strength': float(signal_strength),
                'confidence': float(confidence),
                'uncertainty': float(uncertainty),
                'stop_loss': float(sl) if sl else None,
                'take_profit': float(tp) if tp else None,
                'risk_reward': float(risk_reward) if risk_reward else None,
                'reason': reason,
                'regime': regime.get('regime_name', 'UNKNOWN') if regime else 'UNKNOWN',
                'raw_prediction': prediction
            }
            
            # Store in history
            self.signal_history.append(signal)
            
            logger.info(f"Signal: {action} for {symbol}, strength={signal_strength:.2f}, conf={confidence:.2f}")
            
            return signal
            
        except Exception as e:
            logger.error(f"Signal generation error: {e}")
            return self._generate_neutral_signal(symbol)
    
    def _get_dynamic_thresholds(self, regime: Optional[Dict] = None) -> tuple:
        """Get dynamic thresholds based on market regime and recent performance"""
        buy_threshold = self.base_buy_threshold
        sell_threshold = self.base_sell_threshold
        
        if not self.use_dynamic_thresholds:
            return buy_threshold, sell_threshold
        
        # Adjust based on regime
        if regime:
            regime_name = regime.get('regime_name', '')
            if 'HIGH_VOLATILITY' in regime_name or 'RANGING' in regime_name:
                # Stricter thresholds in volatile/ranging markets
                buy_threshold += 0.1
                sell_threshold -= 0.1
            elif 'TRENDING' in regime_name:
                # Relaxed thresholds in trending markets
                buy_threshold -= 0.05
                sell_threshold += 0.05
        
        # Adjust based on recent performance
        if len(self.recent_performance) > 10:
            win_rate = np.mean([p > 0 for p in self.recent_performance])
            if win_rate < 0.4:
                # Tighten thresholds if losing
                buy_threshold += 0.1
                sell_threshold -= 0.1
            elif win_rate > 0.6:
                # Relax thresholds if winning
                buy_threshold -= 0.05
                sell_threshold += 0.05
        
        return buy_threshold, sell_threshold
    
    def _calculate_signal_strength(self, 
                                   signal_value: float,
                                   confidence: float,
                                   uncertainty: float,
                                   market_data: Dict) -> float:
        """Calculate enhanced signal strength with multiple factors"""
        # Base signal strength
        base_strength = signal_value
        
        # Confidence adjustment
        confidence_multiplier = confidence * (1.0 - uncertainty)
        
        # Volatility adjustment (higher volatility = lower strength requirement)
        if 'close' in market_data:
            prices = np.array(market_data['close'])
            if len(prices) >= 20:
                returns = np.diff(prices) / prices[:-1]
                volatility = np.std(returns[-20:])
                vol_adjustment = 1.0 + min(0.3, volatility * 5)  # Boost strength in volatile markets
            else:
                vol_adjustment = 1.0
        else:
            vol_adjustment = 1.0
        
        # Final signal strength
        signal_strength = base_strength * confidence_multiplier * vol_adjustment
        
        return float(signal_strength)
    
    def _calculate_sl_tp_advanced(self, 
                                  action: str, 
                                  market_data: Dict, 
                                  signal_strength: float,
                                  confidence: float,
                                  regime: Optional[Dict] = None) -> tuple:
        """Calculate advanced stop loss and take profit with support/resistance and ATR"""
        try:
            if action == "NONE":
                return None, None, None
            
            # Get current price
            if 'close' in market_data:
                close_prices = market_data['close']
                current_price = close_prices[-1] if isinstance(close_prices, (list, np.ndarray)) else close_prices
            else:
                return None, None, None
            
            # Calculate ATR properly
            if isinstance(market_data.get('close'), (list, np.ndarray)) and len(market_data['close']) >= 20:
                prices = np.array(market_data['close'])
                high = np.array(market_data.get('high', prices))
                low = np.array(market_data.get('low', prices))
                
                # True Range calculation
                tr_list = []
                for i in range(1, min(20, len(prices))):
                    tr = max(
                        high[i] - low[i],
                        abs(high[i] - prices[i-1]),
                        abs(low[i] - prices[i-1])
                    )
                    tr_list.append(tr)
                
                atr = np.mean(tr_list) if tr_list else current_price * 0.01
            else:
                atr = current_price * 0.01
            
            # Find support/resistance levels
            if isinstance(market_data.get('close'), (list, np.ndarray)) and len(market_data['close']) >= 20:
                prices = np.array(market_data['close'])
                high = np.array(market_data.get('high', prices))
                low = np.array(market_data.get('low', prices))
                
                # Recent swing points
                recent_high = np.max(high[-20:])
                recent_low = np.min(low[-20:])
            else:
                recent_high = current_price * 1.01
                recent_low = current_price * 0.99
            
            # Dynamic risk-reward based on signal strength and confidence
            base_risk_multiplier = 1.5
            base_reward_multiplier = 2.5
            
            # Adjust based on signal strength
            strength_multiplier = 0.5 + abs(signal_strength) * 0.5
            confidence_multiplier = 0.8 + confidence * 0.4
            
            risk_multiplier = base_risk_multiplier * strength_multiplier
            reward_multiplier = base_reward_multiplier * strength_multiplier * confidence_multiplier
            
            # Regime-based adjustments
            if regime:
                regime_name = regime.get('regime_name', '')
                if 'HIGH_VOLATILITY' in regime_name:
                    risk_multiplier *= 1.2  # Wider stops in volatile markets
                    reward_multiplier *= 1.1
                elif 'TRENDING' in regime_name:
                    reward_multiplier *= 1.2  # Wider targets in trends
            
            if action == "BUY":
                # Use ATR or support level, whichever is closer
                atr_sl = current_price - (atr * risk_multiplier)
                support_sl = recent_low * 0.999  # Slightly below support
                sl = max(atr_sl, support_sl)  # Use the closer stop
                
                # Take profit: ATR-based or resistance
                atr_tp = current_price + (atr * reward_multiplier)
                resistance_tp = recent_high * 1.001  # Slightly above resistance
                tp = min(atr_tp, resistance_tp) if atr_tp < resistance_tp * 1.5 else atr_tp
            else:  # SELL
                # Use ATR or resistance level
                atr_sl = current_price + (atr * risk_multiplier)
                resistance_sl = recent_high * 1.001
                sl = min(atr_sl, resistance_sl)
                
                # Take profit
                atr_tp = current_price - (atr * reward_multiplier)
                support_tp = recent_low * 0.999
                tp = max(atr_tp, support_tp) if atr_tp > support_tp * 0.5 else atr_tp
            
            # Calculate risk-reward ratio
            if action == "BUY":
                risk = current_price - sl
                reward = tp - current_price
            else:
                risk = sl - current_price
                reward = current_price - tp
            
            risk_reward = reward / risk if risk > 0 else None
            
            return sl, tp, risk_reward
            
        except Exception as e:
            logger.error(f"Advanced SL/TP calculation error: {e}")
            return None, None, None
    
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
        """Get advanced statistics about generated signals"""
        if not self.signal_history:
            return {'total': 0}
        
        actions = [s['action'] for s in self.signal_history]
        confidences = [s['confidence'] for s in self.signal_history]
        signal_strengths = [s.get('signal_strength', s['signal_value']) for s in self.signal_history]
        
        # Regime distribution
        regimes = [s.get('regime', 'UNKNOWN') for s in self.signal_history]
        regime_counts = {}
        for r in regimes:
            regime_counts[r] = regime_counts.get(r, 0) + 1
        
        return {
            'total': len(self.signal_history),
            'buy_signals': actions.count('BUY'),
            'sell_signals': actions.count('SELL'),
            'neutral_signals': actions.count('NONE'),
            'avg_confidence': float(np.mean(confidences)),
            'avg_signal_strength': float(np.mean(signal_strengths)),
            'regime_distribution': regime_counts,
            'signal_rate': (actions.count('BUY') + actions.count('SELL')) / len(actions) if actions else 0.0
        }
    
    def update_performance(self, profit: float):
        """Update performance tracking for dynamic threshold adjustment"""
        self.recent_performance.append(profit)
