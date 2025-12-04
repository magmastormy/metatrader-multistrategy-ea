#!/usr/bin/env python3
"""
🔥 AUTOMATED MT5 DATA → AI TRAINING PIPELINE 🔥
Continuously collects live MT5 data and triggers AI model training
"""

import os
import sys
import time
import json
import requests
import pandas as pd
from datetime import datetime, timedelta
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    import MetaTrader5 as mt5
    MT5_AVAILABLE = True
except ImportError:
    print("⚠️ MetaTrader5 package not installed. Install with: pip install MetaTrader5")
    MT5_AVAILABLE = False

class MT5ToAIAutomation:
    """Automated pipeline: MT5 Data → CSV → Docker AI Training"""
    
    def __init__(self):
        self.project_root = Path(__file__).parent.parent
        self.training_data_dir = self.project_root / "AI" / "training_data"
        self.training_data_dir.mkdir(parents=True, exist_ok=True)
        
        self.docker_api_base = "http://localhost:8002"
        self.symbols = ["EURUSD", "GBPUSD", "USDJPY", "XAUUSD"]
        self.timeframes = {
            "M1": mt5.TIMEFRAME_M1 if MT5_AVAILABLE else 1,
            "M5": mt5.TIMEFRAME_M5 if MT5_AVAILABLE else 5,
            "M15": mt5.TIMEFRAME_M15 if MT5_AVAILABLE else 15,
            "H1": mt5.TIMEFRAME_H1 if MT5_AVAILABLE else 60,
            "H4": mt5.TIMEFRAME_H4 if MT5_AVAILABLE else 240,
            "D1": mt5.TIMEFRAME_D1 if MT5_AVAILABLE else 1440,
        }
        
        self.collection_interval = 300  # 5 minutes
        self.training_trigger_bars = 1000  # Trigger training every 1000 new bars
        self.bars_per_collection = 10000  # Collect 10k bars each time
        
        self.training_jobs = {}
        
    def initialize_mt5(self):
        """Initialize MT5 connection"""
        if not MT5_AVAILABLE:
            print("❌ MT5 not available")
            return False
            
        if not mt5.initialize():
            print(f"❌ MT5 initialization failed: {mt5.last_error()}")
            return False
        
        print(f"✅ MT5 initialized: {mt5.version()}")
        return True
    
    def collect_symbol_data(self, symbol, timeframe_name, bars=10000):
        """Collect data for a single symbol"""
        if not MT5_AVAILABLE:
            print(f"⚠️ Skipping {symbol} - MT5 not available")
            return None
        
        timeframe = self.timeframes.get(timeframe_name)
        if not timeframe:
            print(f"❌ Invalid timeframe: {timeframe_name}")
            return None
        
        # Get historical data
        rates = mt5.copy_rates_from_pos(symbol, timeframe, 0, bars)
        
        if rates is None or len(rates) == 0:
            print(f"⚠️ No data for {symbol} {timeframe_name}")
            return None
        
        # Convert to DataFrame
        df = pd.DataFrame(rates)
        df['time'] = pd.to_datetime(df['time'], unit='s')
        
        # Add technical indicators
        df['sma_20'] = df['close'].rolling(window=20).mean()
        df['sma_50'] = df['close'].rolling(window=50).mean()
        df['ema_12'] = df['close'].ewm(span=12).mean()
        df['ema_26'] = df['close'].ewm(span=26).mean()
        df['rsi'] = self.calculate_rsi(df['close'], 14)
        df['atr'] = self.calculate_atr(df, 14)
        
        # Calculate returns
        df['returns'] = df['close'].pct_change()
        df['log_returns'] = np.log(df['close'] / df['close'].shift(1))
        
        # Volume analysis
        df['volume_sma'] = df['tick_volume'].rolling(window=20).mean()
        df['volume_ratio'] = df['tick_volume'] / df['volume_sma']
        
        # Price momentum
        df['momentum'] = df['close'] - df['close'].shift(10)
        df['roc'] = ((df['close'] - df['close'].shift(10)) / df['close'].shift(10)) * 100
        
        # Drop NaN values
        df.dropna(inplace=True)
        
        print(f"✅ Collected {len(df)} bars for {symbol} {timeframe_name}")
        return df
    
    def calculate_rsi(self, prices, period=14):
        """Calculate RSI"""
        delta = prices.diff()
        gain = (delta.where(delta > 0, 0)).rolling(window=period).mean()
        loss = (-delta.where(delta < 0, 0)).rolling(window=period).mean()
        rs = gain / loss
        return 100 - (100 / (1 + rs))
    
    def calculate_atr(self, df, period=14):
        """Calculate ATR"""
        high_low = df['high'] - df['low']
        high_close = abs(df['high'] - df['close'].shift())
        low_close = abs(df['low'] - df['close'].shift())
        tr = pd.concat([high_low, high_close, low_close], axis=1).max(axis=1)
        return tr.rolling(window=period).mean()
    
    def save_to_csv(self, df, symbol, timeframe):
        """Save DataFrame to CSV"""
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        filename = f"{symbol}_{timeframe}_{timestamp}.csv"
        filepath = self.training_data_dir / filename
        
        df.to_csv(filepath, index=False)
        print(f"💾 Saved to: {filepath}")
        
        # Also save latest version (overwrite)
        latest_filename = f"{symbol}_{timeframe}_latest.csv"
        latest_filepath = self.training_data_dir / latest_filename
        df.to_csv(latest_filepath, index=False)
        
        return filepath
    
    def trigger_training(self, symbol, timeframe, data_path):
        """Trigger AI model training via Docker API"""
        training_config = {
            "model_type": "transformer",
            "data_path": f"/app/data/{data_path.name}",
            "epochs": 100,
            "batch_size": 32,
            "learning_rate": 0.001,
            "validation_split": 0.2,
            "save_checkpoints": True
        }
        
        try:
            response = requests.post(
                f"{self.docker_api_base}/train",
                json=training_config,
                timeout=10
            )
            
            if response.status_code == 200:
                result = response.json()
                job_id = result.get("job_id")
                print(f"🚀 Training started: {job_id}")
                print(f"   Symbol: {symbol} {timeframe}")
                print(f"   Data: {data_path.name}")
                
                self.training_jobs[job_id] = {
                    "symbol": symbol,
                    "timeframe": timeframe,
                    "started": datetime.now(),
                    "status": "running"
                }
                
                return job_id
            else:
                print(f"❌ Training failed: {response.status_code} - {response.text}")
                return None
                
        except Exception as e:
            print(f"❌ Training API error: {e}")
            return None
    
    def check_training_status(self, job_id):
        """Check training job status"""
        try:
            response = requests.get(
                f"{self.docker_api_base}/train/{job_id}",
                timeout=10
            )
            
            if response.status_code == 200:
                status = response.json()
                return status
            else:
                return None
                
        except Exception as e:
            print(f"⚠️ Status check error: {e}")
            return None
    
    def monitor_training_jobs(self):
        """Monitor all active training jobs"""
        if not self.training_jobs:
            return
        
        print("\n📊 TRAINING JOBS STATUS:")
        for job_id, info in list(self.training_jobs.items()):
            status = self.check_training_status(job_id)
            
            if status:
                print(f"   {job_id[:20]}...")
                print(f"   └─ {info['symbol']} {info['timeframe']}")
                print(f"   └─ Status: {status.get('status')}")
                print(f"   └─ Progress: {status.get('progress', 0):.1f}%")
                print(f"   └─ Epoch: {status.get('current_epoch')}/{status.get('total_epochs')}")
                
                if status.get('status') in ['completed', 'failed', 'cancelled']:
                    self.training_jobs[job_id]['status'] = status.get('status')
                    print(f"   ✅ Job {status.get('status')}")
    
    def run_collection_cycle(self):
        """Run one data collection cycle"""
        print(f"\n{'='*60}")
        print(f"🔄 STARTING COLLECTION CYCLE - {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"{'='*60}")
        
        for symbol in self.symbols:
            for timeframe_name in ["M5", "M15", "H1", "H4"]:
                print(f"\n📊 Collecting {symbol} {timeframe_name}...")
                
                # Collect data
                df = self.collect_symbol_data(symbol, timeframe_name, self.bars_per_collection)
                
                if df is not None and len(df) > 100:
                    # Save to CSV
                    filepath = self.save_to_csv(df, symbol, timeframe_name)
                    
                    # Check if we should trigger training
                    if len(df) >= self.training_trigger_bars:
                        print(f"   💡 Sufficient data ({len(df)} bars) - Triggering training...")
                        self.trigger_training(symbol, timeframe_name, filepath)
                    else:
                        print(f"   ⏳ Need more data ({len(df)}/{self.training_trigger_bars} bars)")
                
                # Small delay between symbols
                time.sleep(1)
        
        # Monitor training jobs
        self.monitor_training_jobs()
        
        print(f"\n{'='*60}")
        print(f"✅ COLLECTION CYCLE COMPLETE")
        print(f"{'='*60}\n")
    
    def run_continuous(self):
        """Run continuous automation"""
        print("🔥 STARTING AUTOMATED MT5 → AI PIPELINE 🔥")
        print(f"Collection interval: {self.collection_interval}s")
        print(f"Training trigger: {self.training_trigger_bars} bars")
        print(f"Symbols: {', '.join(self.symbols)}")
        print()
        
        if not self.initialize_mt5():
            print("❌ Cannot start - MT5 initialization failed")
            return
        
        cycle_count = 0
        
        try:
            while True:
                cycle_count += 1
                print(f"\n🔢 CYCLE #{cycle_count}")
                
                self.run_collection_cycle()
                
                print(f"\n⏰ Waiting {self.collection_interval}s until next cycle...")
                time.sleep(self.collection_interval)
                
        except KeyboardInterrupt:
            print("\n\n⚠️ STOPPING AUTOMATION (Ctrl+C pressed)")
        finally:
            if MT5_AVAILABLE:
                mt5.shutdown()
            print("👋 MT5 connection closed")
            print("📊 Final training jobs summary:")
            for job_id, info in self.training_jobs.items():
                print(f"   {job_id}: {info['status']}")

# Import numpy for calculations
try:
    import numpy as np
except ImportError:
    print("Installing numpy...")
    os.system("pip install numpy")
    import numpy as np

if __name__ == "__main__":
    automation = MT5ToAIAutomation()
    
    # Check command line arguments
    if len(sys.argv) > 1:
        if sys.argv[1] == "--once":
            print("🔄 Running single collection cycle...")
            if automation.initialize_mt5():
                automation.run_collection_cycle()
        elif sys.argv[1] == "--help":
            print("""
🔥 MT5 → AI Automation Pipeline

Usage:
    python live_mt5_to_ai_automation.py             # Run continuous
    python live_mt5_to_ai_automation.py --once      # Run once
    python live_mt5_to_ai_automation.py --help      # Show this help

Features:
    - Automatically collects live MT5 data
    - Saves to CSV with technical indicators
    - Triggers Docker AI training
    - Monitors training progress
    - Runs continuously or on-demand

Configuration:
    - Edit symbols, timeframes in MT5ToAIAutomation class
    - Collection interval: 300s (5 minutes)
    - Training trigger: 1000 bars minimum
            """)
        else:
            print(f"❌ Unknown argument: {sys.argv[1]}")
            print("Use --help for usage information")
    else:
        # Run continuous mode
        automation.run_continuous()
