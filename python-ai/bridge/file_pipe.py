"""File-based bridge - Last resort fallback"""
import json
import logging
from pathlib import Path
from typing import Optional, Callable, Dict
from datetime import datetime, timedelta
import time
import threading

logger = logging.getLogger(__name__)

from .message_protocol import MessageProtocol


class FilePipe:
    """File-based communication bridge"""
    
    def __init__(self, 
                 signal_dir: str = "./signals",
                 request_dir: str = "./requests",
                 poll_interval_ms: int = 100,
                 max_age_seconds: int = 60):
        
        self.signal_dir = Path(signal_dir)
        self.request_dir = Path(request_dir)
        self.poll_interval = poll_interval_ms / 1000.0
        self.max_age = max_age_seconds
        
        self.signal_dir.mkdir(parents=True, exist_ok=True)
        self.request_dir.mkdir(parents=True, exist_ok=True)
        
        self.is_running = False
        self.message_handler = None
        self.processed_files = set()
    
    def start(self, message_handler: Callable):
        """Start file pipe"""
        self.message_handler = message_handler
        self.is_running = True
        logger.info(f"✅ File Pipe started")
        logger.info(f"   Request dir: {self.request_dir.absolute()}")
        logger.info(f"   Signal dir: {self.signal_dir.absolute()}")
    
    def run(self):
        """Run file monitoring loop"""
        logger.info("File Pipe monitoring for requests...")
        
        while self.is_running:
            try:
                # Check for request files
                self._process_requests()
                
                # Clean up old files
                self._cleanup_old_files()
                
                # Sleep
                time.sleep(self.poll_interval)
                
            except KeyboardInterrupt:
                logger.info("File Pipe interrupted by user")
                break
            except Exception as e:
                logger.error(f"Error in file pipe loop: {e}")
    
    def _process_requests(self):
        """Process request files"""
        try:
            # Find all request files
            request_files = list(self.request_dir.glob("request_*.json"))
            
            for req_file in request_files:
                # Skip if already processed
                if str(req_file) in self.processed_files:
                    continue
                
                # Check file age
                file_age = time.time() - req_file.stat().st_mtime
                if file_age > self.max_age:
                    logger.warning(f"Request file too old, deleting: {req_file.name}")
                    req_file.unlink()
                    continue
                
                # Read and process
                try:
                    with open(req_file, 'r') as f:
                        message_str = f.read()
                    
                    logger.debug(f"Processing request: {req_file.name}")
                    
                    # Parse message
                    message = MessageProtocol.parse_message(message_str)
                    is_valid, validation_msg = MessageProtocol.validate_request(message)
                    
                    if not is_valid:
                        response = MessageProtocol.create_error_response(validation_msg)
                    else:
                        # Handle message
                        response = self.message_handler(message)
                    
                    # Write response
                    response_file = self.signal_dir / f"response_{req_file.stem}.json"
                    with open(response_file, 'w') as f:
                        f.write(response)
                    
                    logger.debug(f"Response written: {response_file.name}")
                    
                    # Mark as processed and delete request
                    self.processed_files.add(str(req_file))
                    req_file.unlink()
                    
                except Exception as e:
                    logger.error(f"Error processing {req_file.name}: {e}")
                    # Delete problematic file
                    try:
                        req_file.unlink()
                    except:
                        pass
                        
        except Exception as e:
            logger.error(f"Error scanning request directory: {e}")
    
    def _cleanup_old_files(self):
        """Clean up old files"""
        try:
            # Clean signal directory
            for signal_file in self.signal_dir.glob("*.json"):
                file_age = time.time() - signal_file.stat().st_mtime
                if file_age > self.max_age * 2:  # Keep signals longer
                    signal_file.unlink()
            
            # Clean processed files set if too large
            if len(self.processed_files) > 1000:
                self.processed_files.clear()
                
        except Exception as e:
            logger.error(f"Error cleaning up files: {e}")
    
    def write_signal(self, symbol: str, signal: Dict):
        """Write signal to file for MT5 to read"""
        try:
            filename = f"signal_{symbol}_{int(time.time())}.json"
            filepath = self.signal_dir / filename
            
            with open(filepath, 'w') as f:
                json.dump(signal, f, indent=2)
            
            logger.debug(f"Signal written: {filename}")
            
        except Exception as e:
            logger.error(f"Failed to write signal: {e}")
    
    def stop(self):
        """Stop file pipe"""
        self.is_running = False
        logger.info("File Pipe stopped")


class MT5LogParser:
    """Parse MT5 log files for analytics"""
    
    def __init__(self, log_dir: str = "D:\\Program Files\\MetaTrader 5\\logs"):
        self.log_dir = Path(log_dir)
        
        if not self.log_dir.exists():
            logger.warning(f"MT5 log directory not found: {log_dir}")
    
    def parse_today_logs(self) -> Dict:
        """Parse today's MT5 logs"""
        try:
            today = datetime.now().strftime("%Y%m%d")
            log_file = self.log_dir / f"{today}.log"
            
            if not log_file.exists():
                logger.warning(f"Log file not found: {log_file}")
                return {}
            
            trades = []
            orders = []
            
            with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    # Parse trade lines
                    if 'trade' in line.lower():
                        trade_info = self._parse_trade_line(line)
                        if trade_info:
                            trades.append(trade_info)
                    
                    # Parse order lines
                    if 'order' in line.lower():
                        order_info = self._parse_order_line(line)
                        if order_info:
                            orders.append(order_info)
            
            return {
                'trades': trades,
                'orders': orders,
                'total_trades': len(trades),
                'total_orders': len(orders)
            }
            
        except Exception as e:
            logger.error(f"Failed to parse MT5 logs: {e}")
            return {}
    
    def _parse_trade_line(self, line: str) -> Optional[Dict]:
        """Parse a trade line from MT5 log"""
        # Simplified parsing - customize based on MT5 log format
        try:
            if 'profit' in line.lower():
                return {
                    'timestamp': datetime.now().isoformat(),
                    'line': line.strip()
                }
        except:
            pass
        return None
    
    def _parse_order_line(self, line: str) -> Optional[Dict]:
        """Parse an order line from MT5 log"""
        try:
            return {
                'timestamp': datetime.now().isoformat(),
                'line': line.strip()
            }
        except:
            pass
        return None
