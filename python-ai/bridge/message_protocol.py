"""Message protocol for Python ↔ MQL5 communication"""
import json
from typing import Dict, Any
from datetime import datetime
import logging

logger = logging.getLogger(__name__)


class MessageProtocol:
    """Standardized message format for bridge communication"""
    
    @staticmethod
    def create_request(msg_type: str, data: Dict) -> str:
        """Create request message"""
        message = {
            'type': msg_type,
            'timestamp': datetime.now().isoformat(),
            'data': data
        }
        return json.dumps(message)
    
    @staticmethod
    def create_response(msg_type: str, data: Dict, success: bool = True, error: str = None) -> str:
        """Create response message"""
        message = {
            'type': msg_type,
            'timestamp': datetime.now().isoformat(),
            'success': success,
            'data': data
        }
        if error:
            message['error'] = error
        return json.dumps(message)
    
    @staticmethod
    def parse_message(message: str) -> Dict[str, Any]:
        """Parse message from JSON string"""
        try:
            return json.loads(message)
        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse message: {e}")
            return {
                'type': 'error',
                'success': False,
                'error': f'JSON decode error: {str(e)}'
            }
    
    @staticmethod
    def create_signal_response(symbol: str, signal: Dict) -> str:
        """Create signal response message"""
        response_data = {
            'symbol': symbol,
            'action': signal.get('action', 'NONE'),
            'signal_value': signal.get('signal_value', 0.0),
            'confidence': signal.get('confidence', 0.0),
            'stop_loss': signal.get('stop_loss'),
            'take_profit': signal.get('take_profit'),
            'reason': signal.get('reason', ''),
            'timestamp': signal.get('timestamp', datetime.now().isoformat())
        }
        
        return MessageProtocol.create_response('signal_response', response_data)
    
    @staticmethod
    def validate_request(message: Dict) -> tuple:
        """Validate request message format"""
        required_fields = ['type', 'data']
        
        for field in required_fields:
            if field not in message:
                return False, f"Missing required field: {field}"
        
        if message['type'] not in ['signal_request', 'train_request', 'status_request']:
            return False, f"Unknown message type: {message['type']}"
        
        return True, "Valid"
    
    @staticmethod
    def create_error_response(error_message: str) -> str:
        """Create error response"""
        return MessageProtocol.create_response(
            'error_response',
            {},
            success=False,
            error=error_message
        )
