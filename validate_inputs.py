#!/usr/bin/env python3
"""
Input validation script for MultiStrategyAutonomousEA
Validates .set file parameters against defined constraints
"""

import sys
import json
import os
from pathlib import Path
from typing import Dict, Any, List, Tuple

# Validation rules matching EA's ValidateInputs() function
VALIDATION_RULES = {
    # Risk parameters
    "InpMaxRiskPerTrade": {"type": float, "min": 0.1, "max": 25.0},
    "InpMaxDailyRisk": {"type": float, "min": 0.1, "max": 100.0},
    "InpMaxPortfolioRisk": {"type": float, "min": 0.1, "max": 100.0},
    "InpMaxDrawdown": {"type": float, "min": 1.0, "max": 50.0},
    "InpDailyLossLimitPercent": {"type": float, "min": 1.0, "max": 50.0},
    "InpLotSize": {"type": float, "min": 0.01},
    "InpMagicNumber": {"type": int, "min": 1},
    "InpMaxEntrySpreadPoints": {"type": float, "min": 0},
    
    # Consensus parameters
    "InpQuorumThreshold": {"type": float, "min": 0.5, "max": 0.9},
    "InpConsensusConflictDeadband": {"type": float, "min": 0.01, "max": 0.2},
    "InpAIConfidenceThreshold": {"type": float, "min": 0.5, "max": 0.95},
    
    # Position limits
    "InpMaxPositionsTotal": {"type": int, "min": 1, "max": 100},
    "InpMaxPositionsPerSymbol": {"type": int, "min": 1, "max": 20},
    
    # Equity curve (Batch 99)
    "InpEquityCurveEmaPeriod": {"type": int, "min": 5, "max": 200},
    "InpEquityCurveReductionFactor": {"type": float, "min": 0.0, "max": 1.0},
    "InpKellyFraction": {"type": float, "min": 0.0, "max": 1.0},
    
    # Session/DST
    "InpSessionDSTOffsetHours": {"type": int, "min": -12, "max": 12},
    
    # Skew Step
    "InpSkewStepBufferSize": {"type": int, "min": 10, "max": 1000},
    "InpSkewStepCalmThreshold": {"type": float, "min": 0.5, "max": 0.99},
    "InpSkewStepSmallThreshold": {"type": float, "min": 0.01, "max": 1.0},
    "InpSkewStepLargeThreshold": {"type": float, "min": 0.01, "max": 2.0},
    
    # Scalp engine
    "InpScalpMaxLatencyMs": {"type": int, "min": 50},
}

# Cross-parameter validation rules
CROSS_VALIDATIONS = [
    ("InpMaxDailyRisk", "InpMaxPortfolioRisk", lambda d, p: d <= p, "Daily risk must not exceed portfolio risk"),
    ("InpMaxDrawdown", "InpDailyLossLimitPercent", lambda dd, dl: dd > dl, "Max drawdown must exceed daily loss limit"),
]

# Required boolean dependencies
BOOL_DEPENDENCIES = [
    ("InpEnableStatisticalArbitrage", "InpPythonBridgeMode", lambda sa, pb: not sa or pb != "PYTHON_BRIDGE_OFF", 
     "StatisticalArbitrage requires PythonBridgeMode != OFF"),
    ("InpEnableAIMode", ["InpEnableNeuralNetwork", "InpEnableTransformer", "InpEnableEnsemble", "InpEnableOnnxAI", "InpEnablePythonBridgeAI"],
     lambda ai, *voters: not ai or any(voters), "AIMode enabled but no AI voters enabled"),
]

def parse_set_file(filepath: str) -> Dict[str, Any]:
    """Parse MT5 .set file format"""
    params = {}
    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(';') or '=' not in line:
                continue
            key, value = line.split('=', 1)
            key = key.strip()
            value = value.strip()
            
            # Try to parse value
            if value.lower() in ('true', 'false'):
                params[key] = value.lower() == 'true'
            elif value.isdigit() or (value.startswith('-') and value[1:].isdigit()):
                params[key] = int(value)
            else:
                try:
                    params[key] = float(value)
                except ValueError:
                    params[key] = value.strip('"')
    return params

def validate_params(params: Dict[str, Any]) -> Tuple[bool, List[str]]:
    """Validate all parameters against rules"""
    errors = []
    warnings = []
    
    # Check each validation rule
    for param, rules in VALIDATION_RULES.items():
        if param not in params:
            warnings.append(f"Missing parameter: {param} (using default)")
            continue
            
        value = params[param]
        expected_type = rules.get("type")
        
        # Type check
        if expected_type == int and not isinstance(value, (int, bool)):
            errors.append(f"{param}: expected int, got {type(value).__name__} = {value}")
            continue
        elif expected_type == float and not isinstance(value, (int, float)):
            errors.append(f"{param}: expected float, got {type(value).__name__} = {value}")
            continue
        
        # Range checks
        if "min" in rules and value < rules["min"]:
            errors.append(f"{param}: value {value} below minimum {rules['min']}")
        if "max" in rules and value > rules["max"]:
            errors.append(f"{param}: value {value} above maximum {rules['max']}")
    
    # Cross-parameter validations
    for param1, param2, validator, msg in CROSS_VALIDATIONS:
        if param1 in params and param2 in params:
            if not validator(params[param1], params[param2]):
                errors.append(f"Cross-validation failed: {msg} ({param1}={params[param1]}, {param2}={params[param2]})")
    
    # Boolean dependencies
    for dep in BOOL_DEPENDENCIES:
        if len(dep) == 4:
            main, dep_param, validator, msg = dep
            if main in params and dep_param in params:
                if not validator(params[main], params[dep_param]):
                    errors.append(f"Dependency failed: {msg}")
        elif len(dep) == 5:
            main, dep_params, validator, msg = dep
            if main in params:
                dep_values = [params.get(p, False) for p in dep_params]
                if not validator(params[main], *dep_values):
                    errors.append(f"Dependency failed: {msg}")
    
    # Symbol universe check
    if "InpSymbolsToTrade" in params:
        symbols = params["InpSymbolsToTrade"]
        if not symbols or symbols.strip() == "":
            errors.append("InpSymbolsToTrade is empty")
        else:
            sym_list = [s.strip() for s in symbols.split(",") if s.strip()]
            if len(sym_list) == 0:
                errors.append("InpSymbolsToTrade contains no valid symbols")
    
    return len(errors) == 0, errors + warnings

def main():
    if len(sys.argv) < 2:
        print("Usage: python validate_inputs.py <set_file>")
        sys.exit(1)
    
    set_file = sys.argv[1]
    
    if not os.path.exists(set_file):
        print(f"[ERROR] File not found: {set_file}")
        sys.exit(1)
    
    print(f"[VALIDATE] Parsing {set_file}...")
    params = parse_set_file(set_file)
    print(f"[VALIDATE] Found {len(params)} parameters")
    
    print("[VALIDATE] Running validations...")
    valid, messages = validate_params(params)
    
    for msg in messages:
        if msg.startswith("Cross-validation") or msg.startswith("Dependency") or msg.startswith("Inp"):
            if "WARNING" in msg or "Missing" in msg:
                print(f"  [WARNING] {msg}")
            else:
                print(f"  [ERROR] {msg}")
        else:
            print(f"  [INFO] {msg}")
    
    if valid:
        print("\n[VALIDATE] All validations PASSED")
        sys.exit(0)
    else:
        print(f"\n[VALIDATE] Validation FAILED with {len([m for m in messages if '[ERROR]' in m])} errors")
        sys.exit(1)

if __name__ == "__main__":
    main()