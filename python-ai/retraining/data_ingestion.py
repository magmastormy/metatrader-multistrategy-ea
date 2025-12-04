"""
Data Ingestion Layer - Collects trading data from multiple sources
Pulls MT5 logs, EA signals, OHLC feeds, and strategy metadata
"""

import pandas as pd
import numpy as np
from pathlib import Path
from datetime import datetime, timedelta
import logging
import json
import hashlib
from typing import List, Dict, Optional

logger = logging.getLogger(__name__)


class DataIngestion:
    """Collects and validates trading data from multiple sources"""
    
    def __init__(self, 
                 mt5_log_dir: str = "D:\\Program Files\\MetaTrader 5\\logs",
                 data_lake_dir: str = "data_lake"):
        
        self.mt5_log_dir = Path(mt5_log_dir)
        self.data_lake = Path(data_lake_dir)
        
        # Create data lake structure
        self.raw_dir = self.data_lake / "raw"
        self.processed_dir = self.data_lake / "processed"
        self.training_sets_dir = self.data_lake / "training_sets"
        
        for dir_path in [self.raw_dir, self.processed_dir, self.training_sets_dir]:
            dir_path.mkdir(parents=True, exist_ok=True)
        
        self.collection_metadata = []
    
    def collect_mt5_logs(self, days_back: int = 7) -> pd.DataFrame:
        """Collect MT5 log files from recent days"""
        logger.info(f"Collecting MT5 logs from last {days_back} days...")
        
        all_trades = []
        
        try:
            if not self.mt5_log_dir.exists():
                logger.warning(f"MT5 log directory not found: {self.mt5_log_dir}")
                return pd.DataFrame()
            
            # Collect logs from last N days
            for i in range(days_back):
                date = datetime.now() - timedelta(days=i)
                log_file = self.mt5_log_dir / f"{date.strftime('%Y%m%d')}.log"
                
                if log_file.exists():
                    trades = self._parse_mt5_log(log_file)
                    all_trades.extend(trades)
                    logger.info(f"Parsed {len(trades)} trades from {log_file.name}")
            
            if all_trades:
                df = pd.DataFrame(all_trades)
                logger.info(f"Total trades collected: {len(df)}")
                return df
            else:
                logger.warning("No trades found in MT5 logs")
                return pd.DataFrame()
                
        except Exception as e:
            logger.error(f"Error collecting MT5 logs: {e}")
            return pd.DataFrame()
    
    def _parse_mt5_log(self, log_file: Path) -> List[Dict]:
        """Parse MT5 log file to extract trade data"""
        trades = []
        
        try:
            with open(log_file, 'r', encoding='utf-8', errors='ignore') as f:
                for line in f:
                    # Parse trade lines (customize based on your log format)
                    if 'trade' in line.lower() or 'order' in line.lower():
                        trade_info = self._extract_trade_info(line)
                        if trade_info:
                            trades.append(trade_info)
        except Exception as e:
            logger.error(f"Error parsing {log_file}: {e}")
        
        return trades
    
    def _extract_trade_info(self, line: str) -> Optional[Dict]:
        """Extract trade information from log line"""
        # Simplified extraction - customize based on actual MT5 log format
        try:
            trade = {
                'timestamp': datetime.now().isoformat(),
                'raw_line': line.strip(),
                'source': 'mt5_log'
            }
            
            # Extract basic info if available
            if 'profit' in line.lower():
                trade['has_profit'] = True
            if 'loss' in line.lower():
                trade['has_loss'] = True
            
            return trade
        except:
            return None
    
    def collect_ea_signals(self, signal_log_file: str = "logs/trades.jsonl") -> pd.DataFrame:
        """Collect EA signals from our own logging system"""
        logger.info("Collecting EA signals from internal logs...")
        
        try:
            signal_file = Path(signal_log_file)
            if not signal_file.exists():
                logger.warning(f"Signal log not found: {signal_file}")
                return pd.DataFrame()
            
            signals = []
            with open(signal_file, 'r') as f:
                for line in f:
                    try:
                        signal = json.loads(line.strip())
                        signals.append(signal)
                    except:
                        continue
            
            if signals:
                df = pd.DataFrame(signals)
                logger.info(f"Collected {len(df)} signals")
                return df
            else:
                return pd.DataFrame()
                
        except Exception as e:
            logger.error(f"Error collecting EA signals: {e}")
            return pd.DataFrame()
    
    def collect_ohlc_data(self, 
                          symbol: str = "XAUUSD", 
                          days_back: int = 30,
                          timeframe: str = "1H") -> pd.DataFrame:
        """Collect OHLC price data (placeholder for actual data source)"""
        logger.info(f"Collecting OHLC data for {symbol}...")
        
        # In production, this would connect to MT5 or data provider
        # For now, generate synthetic data
        periods = days_back * 24  # hourly data
        
        base_price = 1900.0 if "XAU" in symbol else 1.1000
        timestamps = pd.date_range(end=datetime.now(), periods=periods, freq='1H')
        
        prices = base_price + np.cumsum(np.random.randn(periods) * 2)
        
        df = pd.DataFrame({
            'timestamp': timestamps,
            'symbol': symbol,
            'open': prices,
            'high': prices * 1.002,
            'low': prices * 0.998,
            'close': prices + np.random.randn(periods) * 0.5,
            'volume': np.random.randint(100, 1000, periods)
        })
        
        logger.info(f"Collected {len(df)} OHLC bars")
        return df
    
    def validate_data(self, df: pd.DataFrame) -> pd.DataFrame:
        """Validate and clean collected data"""
        logger.info(f"Validating data: {len(df)} rows")
        
        initial_count = len(df)
        
        # Remove duplicates
        df = df.drop_duplicates()
        
        # Remove rows with all NaN
        df = df.dropna(how='all')
        
        # Check for required columns (if OHLC data)
        if 'close' in df.columns:
            # Remove invalid prices
            df = df[df['close'] > 0]
        
        # Add validation metadata
        validation_metadata = {
            'initial_rows': initial_count,
            'final_rows': len(df),
            'removed_rows': initial_count - len(df),
            'timestamp': datetime.now().isoformat()
        }
        
        logger.info(f"Validation complete: {len(df)} rows retained, {validation_metadata['removed_rows']} removed")
        
        return df
    
    def save_to_data_lake(self, df: pd.DataFrame, dataset_name: str, stage: str = 'raw'):
        """Save dataset to data lake"""
        if stage == 'raw':
            save_dir = self.raw_dir
        elif stage == 'processed':
            save_dir = self.processed_dir
        else:
            save_dir = self.training_sets_dir
        
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f"{dataset_name}_{timestamp}.parquet"
        filepath = save_dir / filename
        
        try:
            df.to_parquet(filepath, index=False)
            
            # Calculate dataset hash
            dataset_hash = self._calculate_hash(df)
            
            metadata = {
                'filename': filename,
                'path': str(filepath),
                'rows': len(df),
                'columns': list(df.columns),
                'dataset_hash': dataset_hash,
                'timestamp': timestamp,
                'stage': stage
            }
            
            self.collection_metadata.append(metadata)
            
            logger.info(f"Saved dataset: {filepath}")
            logger.info(f"Dataset hash: {dataset_hash}")
            
            return filepath, dataset_hash
            
        except Exception as e:
            logger.error(f"Error saving dataset: {e}")
            return None, None
    
    def _calculate_hash(self, df: pd.DataFrame) -> str:
        """Calculate hash of dataset for versioning"""
        # Create hash from dataframe content
        content = df.to_json().encode('utf-8')
        return hashlib.sha256(content).hexdigest()[:16]
    
    def collect_all(self, days_back: int = 7) -> Dict[str, pd.DataFrame]:
        """Collect all data sources"""
        logger.info("="*60)
        logger.info("STARTING FULL DATA COLLECTION")
        logger.info("="*60)
        
        datasets = {}
        
        # Collect MT5 logs
        mt5_data = self.collect_mt5_logs(days_back=days_back)
        if not mt5_data.empty:
            datasets['mt5_logs'] = mt5_data
            self.save_to_data_lake(mt5_data, 'mt5_logs', 'raw')
        
        # Collect EA signals
        ea_signals = self.collect_ea_signals()
        if not ea_signals.empty:
            datasets['ea_signals'] = ea_signals
            self.save_to_data_lake(ea_signals, 'ea_signals', 'raw')
        
        # Collect OHLC data
        ohlc_data = self.collect_ohlc_data(days_back=days_back)
        if not ohlc_data.empty:
            datasets['ohlc'] = ohlc_data
            self.save_to_data_lake(ohlc_data, 'ohlc', 'raw')
        
        logger.info("="*60)
        logger.info(f"COLLECTION COMPLETE - {len(datasets)} datasets collected")
        logger.info("="*60)
        
        return datasets
    
    def get_latest_dataset(self, dataset_name: str, stage: str = 'raw') -> Optional[pd.DataFrame]:
        """Load the most recent dataset from data lake"""
        if stage == 'raw':
            search_dir = self.raw_dir
        elif stage == 'processed':
            search_dir = self.processed_dir
        else:
            search_dir = self.training_sets_dir
        
        # Find latest file matching pattern
        pattern = f"{dataset_name}_*.parquet"
        files = sorted(search_dir.glob(pattern), reverse=True)
        
        if files:
            latest_file = files[0]
            logger.info(f"Loading latest dataset: {latest_file.name}")
            return pd.read_parquet(latest_file)
        else:
            logger.warning(f"No datasets found for {dataset_name} in {stage}")
            return None
