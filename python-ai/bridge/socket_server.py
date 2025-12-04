"""TCP Socket bridge server - Secondary fallback"""
import socket
import logging
from typing import Optional, Callable
import threading

logger = logging.getLogger(__name__)

from .message_protocol import MessageProtocol


class SocketServer:
    """TCP Socket server for MT5 communication"""
    
    def __init__(self, host: str = "127.0.0.1", port: int = 8888):
        self.host = host
        self.port = port
        self.server_socket = None
        self.is_running = False
        self.message_handler = None
        self.threads = []
    
    def start(self, message_handler: Callable):
        """Start socket server"""
        try:
            self.message_handler = message_handler
            
            self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            self.server_socket.bind((self.host, self.port))
            self.server_socket.listen(5)
            self.server_socket.settimeout(1.0)  # 1 second timeout
            
            self.is_running = True
            logger.info(f"✅ Socket Server started on {self.host}:{self.port}")
            
        except Exception as e:
            logger.error(f"Failed to start Socket server: {e}")
            raise
    
    def run(self):
        """Run server loop"""
        logger.info("Socket Server listening for connections...")
        
        while self.is_running:
            try:
                # Accept connection with timeout
                try:
                    client_socket, address = self.server_socket.accept()
                    logger.info(f"Client connected: {address}")
                    
                    # Handle client in thread
                    thread = threading.Thread(
                        target=self._handle_client,
                        args=(client_socket, address)
                    )
                    thread.daemon = True
                    thread.start()
                    self.threads.append(thread)
                    
                except socket.timeout:
                    continue
                    
            except KeyboardInterrupt:
                logger.info("Server interrupted by user")
                break
            except Exception as e:
                logger.error(f"Error in server loop: {e}")
    
    def _handle_client(self, client_socket: socket.socket, address):
        """Handle client connection"""
        try:
            # Receive data
            data = b''
            while True:
                chunk = client_socket.recv(4096)
                if not chunk:
                    break
                data += chunk
                if len(chunk) < 4096:  # Last chunk
                    break
            
            if not data:
                return
            
            message_str = data.decode('utf-8')
            logger.debug(f"Received from {address}: {message_str[:100]}...")
            
            # Parse and validate
            message = MessageProtocol.parse_message(message_str)
            is_valid, validation_msg = MessageProtocol.validate_request(message)
            
            if not is_valid:
                response = MessageProtocol.create_error_response(validation_msg)
            else:
                # Handle message
                response = self.message_handler(message)
            
            # Send response
            client_socket.sendall(response.encode('utf-8'))
            logger.debug(f"Sent to {address}: {response[:100]}...")
            
        except Exception as e:
            logger.error(f"Error handling client {address}: {e}")
            try:
                error_response = MessageProtocol.create_error_response(str(e))
                client_socket.sendall(error_response.encode('utf-8'))
            except:
                pass
        finally:
            client_socket.close()
    
    def stop(self):
        """Stop socket server"""
        self.is_running = False
        
        if self.server_socket:
            self.server_socket.close()
        
        # Wait for threads to finish
        for thread in self.threads:
            thread.join(timeout=1.0)
        
        logger.info("Socket Server stopped")


class SocketClient:
    """TCP Socket client for testing"""
    
    def __init__(self, host: str = "127.0.0.1", port: int = 8888):
        self.host = host
        self.port = port
        self.socket = None
    
    def connect(self):
        """Connect to socket server"""
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.socket.connect((self.host, self.port))
        logger.info(f"Connected to socket server at {self.host}:{self.port}")
    
    def send_request(self, message: str, timeout: float = 5.0) -> Optional[str]:
        """Send request and wait for response"""
        try:
            self.socket.settimeout(timeout)
            self.socket.sendall(message.encode('utf-8'))
            
            # Receive response
            data = b''
            while True:
                chunk = self.socket.recv(4096)
                if not chunk:
                    break
                data += chunk
                if len(chunk) < 4096:
                    break
            
            return data.decode('utf-8')
            
        except socket.timeout:
            logger.error("Request timeout")
            return None
        except Exception as e:
            logger.error(f"Request failed: {e}")
            return None
    
    def close(self):
        """Close connection"""
        if self.socket:
            self.socket.close()
