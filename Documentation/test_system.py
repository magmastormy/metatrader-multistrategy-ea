#!/usr/bin/env python3
"""
Test script for AI Trading System
Validates all components and generates test signals
"""

import sys
import numpy as np
from pathlib import Path

# Add current directory to path
sys.path.append(str(Path(__file__).parent))

from core.data_loader import DataLoader
from core.feature_engineer import FeatureEngineer
from core.model_manager import ModelManager
from core.signal_generator import SignalGenerator
from core.risk_engine import RiskEngine
from core.analytics import Analytics

print("="*60)
print("🧪 AI TRADING SYSTEM - COMPONENT TEST")
print("="*60)

# Test 1: Data Loader
print("\n1. Testing Data Loader...")
data_loader = DataLoader()
test_prices = np.random.randn(100) * 10 + 1900
df = data_loader.load_from_array(test_prices, symbol="XAUUSD")
print(f"✅ Data loaded: {len(df)} bars")

# Test 2: Feature Engineer
print("\n2. Testing Feature Engineer...")
feature_engineer = FeatureEngineer()
features = feature_engineer.build_features(df)
print(f"✅ Features extracted: {len(features)} features")
print(f"   Feature range: [{features.min():.3f}, {features.max():.3f}]")

# Test 3: Model Manager
print("\n3. Testing Model Manager...")
model_manager = ModelManager(model_dir="models")
print(f"✅ Models loaded: {len(model_manager.models)}")
for name in model_manager.models.keys():
    print(f"   - {name}")

# Test 4: Prediction
print("\n4. Testing Prediction...")
prediction = model_manager.predict(features)
print(f"✅ Prediction generated:")
print(f"   Signal: {prediction['signal']:.3f}")
print(f"   Confidence: {prediction['confidence']:.3f}")
print(f"   Model count: {prediction['model_count']}")

# Test 5: Signal Generator
print("\n5. Testing Signal Generator...")
signal_generator = SignalGenerator()
market_data = {'close': test_prices}
signal = signal_generator.generate_signal(prediction, market_data, "XAUUSD")
print(f"✅ Signal generated:")
print(f"   Action: {signal['action']}")
print(f"   Confidence: {signal['confidence']:.3f}")
print(f"   Reason: {signal['reason']}")

# Test 6: Risk Engine
print("\n6. Testing Risk Engine...")
risk_engine = RiskEngine()
risk_assessment = risk_engine.calculate_risk_score(signal, market_data)
print(f"✅ Risk assessed:")
print(f"   Risk score: {risk_assessment['overall_risk_score']:.3f}")
print(f"   Risk level: {risk_assessment['risk_level']}")
print(f"   Should trade: {risk_assessment['should_trade']}")

# Test 7: Analytics
print("\n7. Testing Analytics...")
analytics = Analytics(log_dir="logs")
analytics.log_prediction(prediction)
analytics.log_signal(signal)
stats = analytics.get_signal_statistics()
print(f"✅ Analytics working:")
print(f"   Total signals logged: {stats['total_signals']}")

# Test 8: End-to-End Pipeline
print("\n8. Testing Full Pipeline...")
for i in range(5):
    # Generate random market data
    prices = np.random.randn(100) * 5 + 1900 + i
    df = data_loader.load_from_array(prices, symbol="XAUUSD")
    
    # Extract features
    features = feature_engineer.build_features(df)
    
    # Predict
    prediction = model_manager.predict(features)
    
    # Generate signal
    market_data = {'close': prices}
    signal = signal_generator.generate_signal(prediction, market_data, "XAUUSD")
    
    # Assess risk
    risk = risk_engine.calculate_risk_score(signal, market_data)
    
    print(f"   Test {i+1}: {signal['action']:6s} | Conf: {signal['confidence']:.2f} | Risk: {risk['risk_level']:8s}")

print("\n" + "="*60)
print("✅ ALL TESTS PASSED - SYSTEM READY")
print("="*60)
