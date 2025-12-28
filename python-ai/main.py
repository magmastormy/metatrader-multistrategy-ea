#!/usr/bin/env python3
"""
🔥 MODERN AI TRADING SYSTEM - MAIN ORCHESTRATOR 🔥
Production-ready Python AI system for MT5 trading
Modular, scalable, and resilient architecture
"""

import sys
import logging
import argparse
from pathlib import Path
from datetime import datetime
import yaml
import signal
import threading

# Add current directory to path
sys.path.append(str(Path(__file__).parent))

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
    handlers=[
        logging.FileHandler('logs/ai_runtime.log', encoding='utf-8'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Import core modules
from core.data_loader import DataLoader
from core.feature_engineer import FeatureEngineer
from core.model_manager import ModelManager
from core.signal_generator import SignalGenerator
from core.risk_engine import RiskEngine
from core.analytics import Analytics
from core.regime_detector import MarketRegimeDetector

# Import bridge modules
from bridge.message_protocol import MessageProtocol

try:
    from bridge.zmq_server import ZMQServer, ZMQ_AVAILABLE
except:
    ZMQ_AVAILABLE = False
    logger.warning("ZMQ not available")

try:
    from bridge.socket_server import SocketServer
except:
    logger.warning("Socket server not available")

from bridge.file_pipe import FilePipe, MT5LogParser


class AITradingSystem:
    """Main orchestrator for AI trading system"""
    
    def __init__(self, config_path: str = "config/bridge.yaml"):
        logger.info("="*60)
        logger.info("AI TRADING SYSTEM INITIALIZING")
        logger.info("="*60)
        
        # Load configuration
        self.config = self._load_config(config_path)
        
        # Initialize core components
        logger.info("Initializing core components...")
        self.data_loader = DataLoader()
        self.feature_engineer = FeatureEngineer()
        self.model_manager = ModelManager(model_dir="models")
        self.signal_generator = SignalGenerator(
            buy_threshold=0.7,
            sell_threshold=-0.7,
            confidence_min=0.6,
            use_dynamic_thresholds=True
        )
        self.risk_engine = RiskEngine(
            max_risk_per_trade=0.02,
            max_portfolio_risk=0.10,
            use_kelly=True,
            kelly_fraction=0.25
        )
        self.analytics = Analytics(log_dir="logs")
        self.regime_detector = MarketRegimeDetector(n_regimes=4, lookback=100)
        
        # Initialize bridge
        self.bridge = None
        self.bridge_type = None
        self.is_running = False
        
        # MT5 log parser
        self.log_parser = MT5LogParser()
        
        logger.info("Core components initialized")
    
    def _load_config(self, config_path: str) -> dict:
        """Load configuration from YAML"""
        try:
            with open(config_path, 'r', encoding='utf-8') as f:
                config = yaml.safe_load(f)
            logger.info(f"Configuration loaded from {config_path}")
            return config
        except Exception as e:
            logger.warning(f"Failed to load config: {e}, using defaults")
            return self._default_config()
    
    def _default_config(self) -> dict:
        """Default configuration"""
        return {
            'primary': {'type': 'zmq', 'enabled': True, 'host': '127.0.0.1', 'port': 5555},
            'secondary': {'type': 'socket', 'enabled': True, 'host': '127.0.0.1', 'port': 8888},
            'fallback': {'type': 'file', 'enabled': True, 'signal_dir': './signals', 'request_dir': './requests'}
        }
    
    def start(self, bridge_mode: str = 'auto'):
        """Start the AI trading system"""
        logger.info("Starting AI Trading System...")
        
        # Determine bridge mode
        if bridge_mode == 'auto':
            self.bridge_type = self._auto_select_bridge()
        else:
            self.bridge_type = bridge_mode
        
        # Initialize bridge
        if self.bridge_type == 'zmq' and ZMQ_AVAILABLE:
            self._start_zmq_bridge()
        elif self.bridge_type == 'socket':
            self._start_socket_bridge()
        else:
            self._start_file_bridge()
        
        logger.info("="*60)
        logger.info("AI TRADING SYSTEM ONLINE")
        logger.info(f"Bridge Mode: {self.bridge_type.upper()}")
        
        # Log model status
        model_count = len(self.model_manager.models)
        logger.info(f"Models Loaded: {model_count}")
        
        if model_count == 0:
            logger.warning("NO MODELS LOADED - System using fallback logic")
        else:
            for model_name, model in self.model_manager.models.items():
                logger.info(f"  - {model_name}: READY")
                
        logger.info("="*60)
    
    def _auto_select_bridge(self) -> str:
        """Automatically select best available bridge"""
        if ZMQ_AVAILABLE and self.config.get('primary', {}).get('enabled', True):
            return 'zmq'
        elif self.config.get('secondary', {}).get('enabled', True):
            return 'socket'
        else:
            return 'file'
    
    def _start_zmq_bridge(self):
        """Start ZeroMQ bridge"""
        try:
            config = self.config.get('primary', {})
            self.bridge = ZMQServer(
                host=config.get('host', '127.0.0.1'),
                port=config.get('port', 5555)
            )
            self.bridge.start(self.handle_message)
            
            # Run in thread
            self.bridge_thread = threading.Thread(target=self.bridge.run, daemon=True)
            self.bridge_thread.start()
            
            logger.info("ZeroMQ bridge started")
        except Exception as e:
            logger.error(f"Failed to start ZMQ bridge: {e}")
            logger.info("Falling back to socket bridge...")
            self._start_socket_bridge()
    
    def _start_socket_bridge(self):
        """Start TCP socket bridge"""
        try:
            config = self.config.get('secondary', {})
            self.bridge = SocketServer(
                host=config.get('host', '127.0.0.1'),
                port=config.get('port', 8888)
            )
            self.bridge.start(self.handle_message)
            
            # Run in thread
            self.bridge_thread = threading.Thread(target=self.bridge.run, daemon=True)
            self.bridge_thread.start()
            
            logger.info("Socket bridge started")
        except Exception as e:
            logger.error(f"Failed to start socket bridge: {e}")
            logger.info("Falling back to file bridge...")
            self._start_file_bridge()
    
    def _start_file_bridge(self):
        """Start file-based bridge"""
        try:
            config = self.config.get('fallback', {})
            self.bridge = FilePipe(
                signal_dir=config.get('signal_dir', './signals'),
                request_dir=config.get('request_dir', './requests'),
                poll_interval_ms=config.get('poll_interval_ms', 100)
            )
            self.bridge.start(self.handle_message)
            
            # Run in thread
            self.bridge_thread = threading.Thread(target=self.bridge.run, daemon=True)
            self.bridge_thread.start()
            
            logger.info("File bridge started")
        except Exception as e:
            logger.error(f"Failed to start file bridge: {e}")
            raise
    
    def handle_message(self, message: dict) -> str:
        """Handle incoming message from MT5"""
        try:
            msg_type = message.get('type')
            data = message.get('data', {})
            
            if msg_type == 'handshake':
                return self._handle_handshake_request(data)
            elif msg_type == 'heartbeat':
                return self._handle_heartbeat_request()
            elif msg_type == 'signal_request':
                return self._handle_signal_request(data)
            elif msg_type == 'train_request':
                return self._handle_train_request(data)
            elif msg_type == 'status_request':
                return self._handle_status_request()
            else:
                return MessageProtocol.create_error_response(f"Unknown message type: {msg_type}")
                
        except Exception as e:
            logger.error(f"Error handling message: {e}")
            return MessageProtocol.create_error_response(str(e))

    def _handle_handshake_request(self, data: dict) -> str:
        """Handle handshake request"""
        try:
            client_version = data.get('version', 'unknown')
            logger.info(f"Handshake request from client version: {client_version}")
            
            response_data = {
                'status': 'ready',
                'version': '2.0.0',
                'models_loaded': list(self.model_manager.models.keys()),
                'bridge_type': self.bridge_type
            }
            return MessageProtocol.create_response('handshake_response', response_data)
        except Exception as e:
            logger.error(f"Handshake failed: {e}")
            return MessageProtocol.create_error_response(str(e))

    def _handle_heartbeat_request(self) -> str:
        """Handle heartbeat request"""
        return MessageProtocol.create_response('heartbeat_response', {'status': 'alive'})

    def _handle_signal_request(self, data: dict) -> str:
        """Handle signal generation request"""
        try:
            symbol = data.get('symbol', 'UNKNOWN')
            market_data = data.get('market_data', {})
            
            logger.info(f"Signal request for {symbol}")
            
            # Load data
            df = self.data_loader.load_from_dict(market_data)
            
            # Detect market regime
            regime = self.regime_detector.detect_regime(df)
            
            # Extract features (now with 50 features)
            features = self.feature_engineer.build_features(df)
            
            # Get prediction (ensemble with advanced models)
            prediction = self.model_manager.predict(features)
            
            # Log prediction
            self.analytics.log_prediction(prediction)
            
            # Generate signal (with regime awareness)
            signal = self.signal_generator.generate_signal(
                prediction,
                market_data,
                symbol,
                regime
            )
            
            # Calculate risk (with portfolio and Kelly)
            risk_assessment = self.risk_engine.calculate_risk_score(
                signal,
                market_data,
                account_balance=10000.0,  # TODO: Get from MT5
                symbol=symbol
            )
            
            # Validate trade
            is_valid, reasons = self.risk_engine.validate_trade(signal, risk_assessment)
            
            if not is_valid:
                signal['action'] = 'NONE'
                signal['reason'] = f"Trade blocked: {', '.join(reasons)}"
            
            # Add risk info to signal
            signal['risk_score'] = risk_assessment.get('overall_risk_score')
            signal['risk_level'] = risk_assessment.get('risk_level')
            
            # Log signal
            self.analytics.log_signal(signal)
            
            # Create response
            response = MessageProtocol.create_signal_response(symbol, signal)
            
            logger.info(f"Signal generated: {signal['action']} (confidence: {signal['confidence']:.2f})")
            
            return response
            
        except Exception as e:
            logger.error(f"Signal generation failed: {e}")
            return MessageProtocol.create_error_response(str(e))
    
    def _handle_train_request(self, data: dict) -> str:
        """Handle model training request"""
        try:
            logger.info("Training request received")
            
            # Training would be implemented here
            # For now, return success
            
            response_data = {
                'status': 'training_scheduled',
                'message': 'Model training not implemented in this version'
            }
            
            return MessageProtocol.create_response('train_response', response_data)
            
        except Exception as e:
            logger.error(f"Training failed: {e}")
            return MessageProtocol.create_error_response(str(e))
    
    def _handle_status_request(self) -> str:
        """Handle system status request"""
        try:
            status_data = {
                'status': 'online',
                'bridge_type': self.bridge_type,
                'models_loaded': len(self.model_manager.models),
                'total_signals': len(self.analytics.signals),
                'timestamp': datetime.now().isoformat()
            }
            
            return MessageProtocol.create_response('status_response', status_data)
            
        except Exception as e:
            return MessageProtocol.create_error_response(str(e))
    
    def run(self):
        """Run the system"""
        self.is_running = True
        
        try:
            while self.is_running:
                # Main loop - bridge handles messages in thread
                import time
                time.sleep(1)
                
        except KeyboardInterrupt:
            logger.info("Shutdown signal received")
            self.stop()
    
    def stop(self):
        """Stop the system"""
        logger.info("Stopping AI Trading System...")
        
        self.is_running = False
        
        if self.bridge:
            self.bridge.stop()
        
        # Generate final report
        report = self.analytics.generate_report()
        logger.info("\n" + report)
        
        logger.info("System stopped gracefully")


def main():
    """Main entry point"""
    parser = argparse.ArgumentParser(description='AI Trading System')
    parser.add_argument('--bridge', choices=['auto', 'zmq', 'socket', 'file'],
                       default='auto', help='Bridge mode')
    parser.add_argument('--config', default='config/bridge.yaml',
                       help='Configuration file path')
    
    args = parser.parse_args()
    
    # Create logs directory
    Path('logs').mkdir(exist_ok=True)
    
    # Initialize system
    system = AITradingSystem(config_path=args.config)
    
    # Handle shutdown signals
    def signal_handler(sig, frame):
        logger.info("Interrupt received")
        system.stop()
        sys.exit(0)
    
    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)
    
    # Start system
    system.start(bridge_mode=args.bridge)
    
    # Run
    system.run()


if __name__ == "__main__":
    main()
