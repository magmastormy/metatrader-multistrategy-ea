"""Risk management and scoring engine"""
import numpy as np
from typing import Dict, Optional
import logging

logger = logging.getLogger(__name__)


class RiskEngine:
    """Advanced risk scoring and management"""
    
    def __init__(self, max_risk_per_trade: float = 0.02):
        self.max_risk_per_trade = max_risk_per_trade
        self.risk_history = []
        
    def calculate_risk_score(self, 
                            signal: Dict,
                            market_data: Dict,
                            account_balance: float = 10000.0) -> Dict:
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
            
            # 6. Calculate position sizing
            position_size = self._calculate_position_size(
                overall_risk,
                signal,
                account_balance
            )
            
            risk_assessment = {
                'overall_risk_score': float(overall_risk),
                'risk_level': self._get_risk_level(overall_risk),
                'risk_factors': risk_factors,
                'recommended_position_size': float(position_size),
                'max_position_size': float(account_balance * self.max_risk_per_trade),
                'should_trade': overall_risk < 0.7 and confidence > 0.6
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
                                 account_balance: float) -> float:
        """Calculate optimal position size based on risk"""
        
        # Base position size (2% of account)
        base_size = account_balance * self.max_risk_per_trade
        
        # Adjust based on risk score
        risk_multiplier = 1.0 - risk_score
        
        # Adjust based on confidence
        confidence = signal.get('confidence', 0.5)
        confidence_multiplier = confidence
        
        # Final position size
        position_size = base_size * risk_multiplier * confidence_multiplier
        
        # Ensure minimum and maximum limits
        min_size = account_balance * 0.001  # 0.1% minimum
        max_size = account_balance * 0.05   # 5% maximum
        
        return np.clip(position_size, min_size, max_size)
    
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
    
    def get_risk_statistics(self) -> Dict:
        """Get risk statistics from history"""
        if not self.risk_history:
            return {'total_assessments': 0}
        
        scores = [r['overall_risk_score'] for r in self.risk_history]
        
        return {
            'total_assessments': len(self.risk_history),
            'avg_risk_score': float(np.mean(scores)),
            'max_risk_score': float(np.max(scores)),
            'min_risk_score': float(np.min(scores)),
            'high_risk_count': sum(1 for s in scores if s > 0.7)
        }
