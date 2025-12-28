"""Advanced risk management with Kelly Criterion, portfolio risk, and correlation-based sizing"""
import numpy as np
from typing import Dict, Optional, List
from datetime import datetime
import logging
from collections import deque

logger = logging.getLogger(__name__)


class RiskEngine:
    """Advanced risk management with Kelly Criterion, portfolio optimization, and dynamic sizing"""
    
    def __init__(self, 
                 max_risk_per_trade: float = 0.02,
                 max_portfolio_risk: float = 0.10,
                 use_kelly: bool = True,
                 kelly_fraction: float = 0.25):  # Fractional Kelly (25% of full Kelly)
        self.max_risk_per_trade = max_risk_per_trade
        self.max_portfolio_risk = max_portfolio_risk
        self.use_kelly = use_kelly
        self.kelly_fraction = kelly_fraction
        
        self.risk_history = deque(maxlen=1000)
        self.trade_history = deque(maxlen=500)
        self.portfolio_positions = {}  # Track open positions
        
        # Performance tracking for Kelly
        self.win_rate = 0.5
        self.avg_win = 1.0
        self.avg_loss = 1.0
        self.trade_count = 0
        
    def calculate_risk_score(self, 
                            signal: Dict,
                            market_data: Dict,
                            account_balance: float = 10000.0,
                            symbol: str = "UNKNOWN") -> Dict:
        """Calculate comprehensive risk score for a signal"""
        
        try:
            risk_factors = {}
            
            # 1. Confidence-based risk
            confidence = signal.get('confidence', 0.0)
            risk_factors['confidence_risk'] = 1.0 - confidence
            
            # 2. Volatility risk
            if 'close' in market_data and isinstance(market_data['close'], (list, np.ndarray)):
                prices = np.array(market_data['close'])
                if len(prices) >= 20:
                    returns = np.diff(prices) / prices[:-1]
                    volatility = np.std(returns)
                    risk_factors['volatility_risk'] = min(1.0, volatility * 50)
                else:
                    risk_factors['volatility_risk'] = 0.5
            else:
                risk_factors['volatility_risk'] = 0.5
            
            # 3. Market regime risk
            if 'close' in market_data and isinstance(market_data['close'], (list, np.ndarray)):
                prices = np.array(market_data['close'])
                if len(prices) >= 50:
                    sma_20 = np.mean(prices[-20:])
                    sma_50 = np.mean(prices[-50:])
                    
                    # Ranging market = higher risk
                    if abs(sma_20 - sma_50) / sma_50 < 0.01:
                        risk_factors['regime_risk'] = 0.8
                    else:
                        risk_factors['regime_risk'] = 0.3
                else:
                    risk_factors['regime_risk'] = 0.5
            else:
                risk_factors['regime_risk'] = 0.5
            
            # 4. Time-based risk (news events, session changes)
            from datetime import datetime
            hour = datetime.now().hour
            
            # High risk during session overlaps and news times
            if hour in [8, 9, 13, 14, 15]:  # Major news hours
                risk_factors['time_risk'] = 0.7
            else:
                risk_factors['time_risk'] = 0.3
            
            # 5. Calculate overall risk score (0 = low risk, 1 = high risk)
            weights = {
                'confidence_risk': 0.4,
                'volatility_risk': 0.3,
                'regime_risk': 0.2,
                'time_risk': 0.1
            }
            
            overall_risk = sum(risk_factors[k] * weights[k] for k in weights.keys())
            
            # 6. Correlation risk (if we have other positions)
            correlation_risk = self._calculate_correlation_risk(symbol, signal)
            risk_factors['correlation_risk'] = correlation_risk
            
            # 7. Calculate position sizing (advanced)
            current_price = None
            stop_loss = signal.get('stop_loss')
            if 'close' in market_data:
                close_prices = market_data['close']
                current_price = close_prices[-1] if isinstance(close_prices, (list, np.ndarray)) else close_prices
            
            position_size = self._calculate_position_size(
                overall_risk,
                signal,
                account_balance,
                current_price or 0.0,
                stop_loss
            )
            
            # 8. Kelly Criterion recommendation
            kelly_f = self._calculate_kelly_fraction() if self.use_kelly else 0.0
            kelly_position_size = account_balance * kelly_f * self.kelly_fraction if kelly_f > 0 else position_size
            
            # 9. Portfolio risk check
            portfolio_risk = self._calculate_portfolio_risk(account_balance, position_size)
            
            risk_assessment = {
                'overall_risk_score': float(overall_risk),
                'risk_level': self._get_risk_level(overall_risk),
                'risk_factors': risk_factors,
                'recommended_position_size': float(position_size),
                'kelly_position_size': float(kelly_position_size),
                'max_position_size': float(account_balance * self.max_risk_per_trade),
                'portfolio_risk': float(portfolio_risk),
                'kelly_fraction': float(kelly_f),
                'should_trade': overall_risk < 0.7 and confidence > 0.6 and portfolio_risk < self.max_portfolio_risk
            }
            
            self.risk_history.append(risk_assessment)
            
            return risk_assessment
            
        except Exception as e:
            logger.error(f"Risk calculation error: {e}")
            return {
                'overall_risk_score': 1.0,
                'risk_level': 'CRITICAL',
                'should_trade': False
            }
    
    def _calculate_position_size(self,
                                 risk_score: float,
                                 signal: Dict,
                                 account_balance: float,
                                 current_price: float,
                                 stop_loss: Optional[float] = None) -> float:
        """Calculate optimal position size using Kelly Criterion and risk-based methods"""
        
        # Method 1: Fixed percentage risk
        base_size = account_balance * self.max_risk_per_trade
        
        # Adjust based on risk score
        risk_multiplier = 1.0 - risk_score
        
        # Adjust based on confidence
        confidence = signal.get('confidence', 0.5)
        confidence_multiplier = confidence
        
        fixed_risk_size = base_size * risk_multiplier * confidence_multiplier
        
        # Method 2: Kelly Criterion (if enabled and we have enough data)
        kelly_size = fixed_risk_size
        if self.use_kelly and self.trade_count > 20:
            try:
                kelly_f = self._calculate_kelly_fraction()
                if kelly_f > 0:
                    # Use fractional Kelly
                    kelly_size = account_balance * kelly_f * self.kelly_fraction
                else:
                    kelly_size = fixed_risk_size * 0.5  # Reduce size if Kelly is negative
            except Exception as e:
                logger.warning(f"Kelly calculation failed: {e}, using fixed risk")
                kelly_size = fixed_risk_size
        
        # Method 3: Stop-loss based sizing (if SL provided)
        sl_based_size = fixed_risk_size
        if stop_loss and current_price > 0:
            risk_per_unit = abs(current_price - stop_loss)
            if risk_per_unit > 0:
                max_loss = account_balance * self.max_risk_per_trade
                sl_based_size = max_loss / risk_per_unit * current_price
        
        # Use the most conservative approach
        position_size = min(fixed_risk_size, kelly_size, sl_based_size)
        
        # Portfolio risk check
        portfolio_risk = self._calculate_portfolio_risk(account_balance, position_size)
        if portfolio_risk > self.max_portfolio_risk:
            # Reduce position size to maintain portfolio risk limit
            reduction_factor = self.max_portfolio_risk / portfolio_risk
            position_size *= reduction_factor
        
        # Ensure minimum and maximum limits
        min_size = account_balance * 0.001  # 0.1% minimum
        max_size = account_balance * 0.05   # 5% maximum
        
        return np.clip(position_size, min_size, max_size)
    
    def _calculate_kelly_fraction(self) -> float:
        """Calculate Kelly Criterion fraction"""
        if self.avg_loss <= 0 or self.win_rate <= 0 or self.win_rate >= 1:
            return 0.0
        
        # Kelly = (W * R - L) / R
        # W = win rate, R = avg win / avg loss, L = loss rate
        win_loss_ratio = self.avg_win / self.avg_loss if self.avg_loss > 0 else 1.0
        loss_rate = 1.0 - self.win_rate
        
        kelly = (self.win_rate * win_loss_ratio - loss_rate) / win_loss_ratio
        
        # Clamp to reasonable range
        return np.clip(kelly, 0.0, 0.25)  # Max 25% of account
    
    def _calculate_portfolio_risk(self, account_balance: float, new_position_size: float) -> float:
        """Calculate total portfolio risk including new position"""
        total_exposure = sum(self.portfolio_positions.values()) + new_position_size
        return total_exposure / account_balance if account_balance > 0 else 0.0
    
    def _get_risk_level(self, risk_score: float) -> str:
        """Convert risk score to risk level"""
        if risk_score < 0.3:
            return "LOW"
        elif risk_score < 0.5:
            return "MODERATE"
        elif risk_score < 0.7:
            return "HIGH"
        else:
            return "CRITICAL"
    
    def validate_trade(self, signal: Dict, risk_assessment: Dict) -> tuple:
        """Validate if trade should be executed"""
        
        reasons = []
        
        # Check if should trade flag is set
        if not risk_assessment.get('should_trade', False):
            reasons.append("High risk score")
        
        # Check confidence
        if signal.get('confidence', 0.0) < 0.6:
            reasons.append("Low confidence")
        
        # Check risk level
        if risk_assessment.get('risk_level') == 'CRITICAL':
            reasons.append("Critical risk level")
        
        # Check position size
        if risk_assessment.get('recommended_position_size', 0) < 0.001:
            reasons.append("Position size too small")
        
        is_valid = len(reasons) == 0
        
        return is_valid, reasons
    
    def _calculate_correlation_risk(self, symbol: str, signal: Dict) -> float:
        """Calculate correlation risk with existing positions"""
        if not self.portfolio_positions:
            return 0.0
        
        # Simplified: assume higher risk if we have many positions
        position_count = len(self.portfolio_positions)
        correlation_risk = min(0.5, position_count * 0.1)
        
        return correlation_risk
    
    def record_trade(self, symbol: str, profit: float, position_size: float):
        """Record trade result for Kelly Criterion calculation"""
        self.trade_history.append({
            'symbol': symbol,
            'profit': profit,
            'position_size': position_size,
            'timestamp': datetime.now()
        })
        
        # Update win rate and averages
        if len(self.trade_history) > 0:
            profits = [t['profit'] for t in self.trade_history]
            wins = [p for p in profits if p > 0]
            losses = [abs(p) for p in profits if p < 0]
            
            self.trade_count = len(profits)
            self.win_rate = len(wins) / len(profits) if profits else 0.5
            self.avg_win = np.mean(wins) if wins else 1.0
            self.avg_loss = np.mean(losses) if losses else 1.0
    
    def add_position(self, symbol: str, position_size: float):
        """Add position to portfolio tracking"""
        self.portfolio_positions[symbol] = position_size
    
    def remove_position(self, symbol: str):
        """Remove position from portfolio tracking"""
        self.portfolio_positions.pop(symbol, None)
    
    def get_risk_statistics(self) -> Dict:
        """Get advanced risk statistics from history"""
        if not self.risk_history:
            return {'total_assessments': 0}
        
        scores = [r['overall_risk_score'] for r in self.risk_history]
        portfolio_risks = [r.get('portfolio_risk', 0.0) for r in self.risk_history]
        
        return {
            'total_assessments': len(self.risk_history),
            'avg_risk_score': float(np.mean(scores)),
            'max_risk_score': float(np.max(scores)),
            'min_risk_score': float(np.min(scores)),
            'high_risk_count': sum(1 for s in scores if s > 0.7),
            'avg_portfolio_risk': float(np.mean(portfolio_risks)),
            'kelly_fraction': float(self._calculate_kelly_fraction()),
            'win_rate': float(self.win_rate),
            'avg_win': float(self.avg_win),
            'avg_loss': float(self.avg_loss),
            'trade_count': self.trade_count,
            'open_positions': len(self.portfolio_positions)
        }
