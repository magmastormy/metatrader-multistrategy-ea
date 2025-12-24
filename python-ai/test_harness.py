#!/usr/bin/env python3
"""
Test Harness for AI Trading System
Simulates MQL5 requests to test the Python bridge
"""

import sys
import json
import time
import logging
import argparse
import zmq
import socket
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s'
)
logger = logging.getLogger("TestHarness")

class ZMQClient:
    def __init__(self, host="127.0.0.1", port=5555):
        self.host = host
        self.port = port
        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.REQ)
        
    def connect(self):
        address = f"tcp://{self.host}:{self.port}"
        logger.info(f"Connecting to ZMQ server at {address}")
        self.socket.connect(address)
        
    def send(self, message):
        self.socket.send_string(json.dumps(message))
        return json.loads(self.socket.recv_string())
        
    def close(self):
        self.socket.close()
        self.context.term()

class SocketClient:
    def __init__(self, host="127.0.0.1", port=8888):
        self.host = host
        self.port = port
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        
    def connect(self):
        logger.info(f"Connecting to Socket server at {self.host}:{self.port}")
        self.sock.connect((self.host, self.port))
        
    def send(self, message):
        msg_str = json.dumps(message)
        self.sock.sendall(msg_str.encode('utf-8'))
        response = self.sock.recv(4096).decode('utf-8')
        return json.loads(response)
        
    def close(self):
        self.sock.close()

def run_tests(client_type="zmq"):
    """Run integration tests"""
    
    def send_test_message(client_class, host, port, message, test_name):
        """Helper to send a message and handle reconnection for socket clients"""
        client = client_class(host, port) if client_type == "socket" else client_class()
        try:
            client.connect()
            response = client.send(message)
            return response
        finally:
            client.close()
    
    # Determine client parameters
    if client_type == "zmq":
        client_class = ZMQClient
        host, port = "127.0.0.1", 5555
    else:
        client_class = SocketClient
        host, port = "127.0.0.1", 8888
    
    try:
        # Test 1: Handshake
        logger.info("\n--- Testing Handshake ---")
        handshake_msg = {
            "type": "handshake",
            "data": {"version": "MQL5-1.0"}
        }
        response = send_test_message(client_class, host, port, handshake_msg, "Handshake")
        logger.info(f"Response: {json.dumps(response, indent=2)}")
        
        if response.get("success"):
            logger.info("Handshake successful")
        else:
            logger.error("Handshake failed")
            
        # Test 2: Heartbeat
        logger.info("\n--- Testing Heartbeat ---")
        heartbeat_msg = {
            "type": "heartbeat",
            "data": {}
        }
        response = send_test_message(client_class, host, port, heartbeat_msg, "Heartbeat")
        logger.info(f"Response: {json.dumps(response, indent=2)}")
        
        if response.get("success"):
            logger.info("Heartbeat successful")
        else:
            logger.error("Heartbeat failed")
            
        # Test 3: Signal Request
        logger.info("\n--- Testing Signal Request ---")
        # Dummy market data
        market_data = {
            "open": [1.1000 + i*0.0001 for i in range(100)],
            "high": [1.1005 + i*0.0001 for i in range(100)],
            "low": [1.0995 + i*0.0001 for i in range(100)],
            "close": [1.1002 + i*0.0001 for i in range(100)],
            "volume": [1000 + i*10 for i in range(100)],
            "time": [int(time.time()) - i*60 for i in range(100)]
        }
        
        signal_msg = {
            "type": "signal_request",
            "data": {
                "symbol": "Step Index.0",
                "timeframe": "H1",
                "market_data": market_data
            }
        }
        
        start_time = time.time()
        response = send_test_message(client_class, host, port, signal_msg, "Signal Request")
        duration = (time.time() - start_time) * 1000
        
        logger.info(f"Response: {json.dumps(response, indent=2)}")
        logger.info(f"Inference time: {duration:.2f}ms")
        
        if response.get("success"):
            logger.info("Signal request successful")
        else:
            logger.error("Signal request failed")
        
        # Test 4: Status Request
        logger.info("\n--- Testing Status Request ---")
        status_msg = {
            "type": "status_request",
            "data": {}
        }
        response = send_test_message(client_class, host, port, status_msg, "Status")
        logger.info(f"Response: {json.dumps(response, indent=2)}")
        
        if response.get("success"):
            logger.info("Status request successful")
        else:
            logger.error("Status request failed")
            
    except Exception as e:
        logger.error(f"Test failed: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--type", choices=["zmq", "socket"], default="zmq")
    args = parser.parse_args()
    
    run_tests(args.type)
