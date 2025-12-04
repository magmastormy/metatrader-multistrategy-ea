"""ZeroMQ bridge server - Primary communication method"""
import logging
from typing import Optional, Callable
import time

logger = logging.getLogger(__name__)

try:
    import zmq
    ZMQ_AVAILABLE = True
except ImportError:
    ZMQ_AVAILABLE = False
    logger.warning("ZeroMQ not available - install with: pip install pyzmq")

from .message_protocol import MessageProtocol


class ZMQServer:
    """ZeroMQ REP/REQ server for MT5 communication"""
    
    def __init__(self, host: str = "127.0.0.1", port: int = 5555):
        self.host = host
        self.port = port
        self.context = None
        self.socket = None
        self.is_running = False
        self.message_handler = None
        
        if not ZMQ_AVAILABLE:
            logger.error("ZeroMQ not available")
            raise ImportError("pyzmq is required for ZMQ bridge")
    
    def start(self, message_handler: Callable):
        """Start ZMQ server"""
        try:
            self.message_handler = message_handler
            
            self.context = zmq.Context()
            self.socket = self.context.socket(zmq.REP)
            
            address = f"tcp://{self.host}:{self.port}"
            self.socket.bind(address)
            
            self.is_running = True
            logger.info(f"✅ ZMQ Server started on {address}")
            
        except Exception as e:
            logger.error(f"Failed to start ZMQ server: {e}")
            raise
    
    def run(self):
        """Run server loop"""
        logger.info("ZMQ Server listening for messages...")
        
        while self.is_running:
            try:
                # Wait for request (blocking with timeout)
                if self.socket.poll(timeout=1000):  # 1 second timeout
                    message_bytes = self.socket.recv()
                    message_str = message_bytes.decode('utf-8')
                    
                    logger.debug(f"Received: {message_str[:100]}...")
                    
                    # Parse message
                    message = MessageProtocol.parse_message(message_str)
                    
                    # Validate
                    is_valid, validation_msg = MessageProtocol.validate_request(message)
                    if not is_valid:
                        response = MessageProtocol.create_error_response(validation_msg)
                    else:
                        # Handle message
                        response = self.message_handler(message)
                    
                    # Send response
                    self.socket.send_string(response)
                    logger.debug(f"Sent: {response[:100]}...")
                    
            except KeyboardInterrupt:
                logger.info("Server interrupted by user")
                break
            except Exception as e:
                logger.error(f"Error in server loop: {e}")
                # Send error response
                try:
                    error_response = MessageProtocol.create_error_response(str(e))
                    self.socket.send_string(error_response)
                except:
                    pass
    
    def stop(self):
        """Stop ZMQ server"""
        self.is_running = False
        
        if self.socket:
            self.socket.close()
        if self.context:
            self.context.term()
        
        logger.info("ZMQ Server stopped")
    
    def send_async_message(self, message: str):
        """Send asynchronous message (for PUB/SUB pattern)"""
        # Not implemented in REP/REQ pattern
        pass


class ZMQClient:
    """ZeroMQ client for testing"""
    
    def __init__(self, host: str = "127.0.0.1", port: int = 5555):
        self.host = host
        self.port = port
        self.context = None
        self.socket = None
    
    def connect(self):
        """Connect to ZMQ server"""
        if not ZMQ_AVAILABLE:
            raise ImportError("pyzmq is required")
        
        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.REQ)
        
        address = f"tcp://{self.host}:{self.port}"
        self.socket.connect(address)
        
        logger.info(f"Connected to ZMQ server at {address}")
    
    def send_request(self, message: str, timeout_ms: int = 5000) -> Optional[str]:
        """Send request and wait for response"""
        try:
            self.socket.send_string(message)
            
            # Wait for response with timeout
            if self.socket.poll(timeout=timeout_ms):
                response = self.socket.recv_string()
                return response
            else:
                logger.error("Request timeout")
                return None
                
        except Exception as e:
            logger.error(f"Request failed: {e}")
            return None
    
    def close(self):
        """Close connection"""
        if self.socket:
            self.socket.close()
        if self.context:
            self.context.term()
