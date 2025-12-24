#!/usr/bin/env python3
"""
Dependency checker for AI Trading System
Verifies all required packages are installed and working
"""

import sys
import importlib
import logging

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s: %(message)s')
logger = logging.getLogger(__name__)

def check_package(package_name, import_name=None):
    """Check if a package is available"""
    if import_name is None:
        import_name = package_name
    
    try:
        module = importlib.import_module(import_name)
        version = getattr(module, '__version__', 'Unknown')
        logger.info(f"✓ {package_name}: {version}")
        return True
    except ImportError as e:
        logger.error(f"✗ {package_name}: NOT FOUND ({e})")
        return False

def main():
    """Check all dependencies"""
    logger.info("="*50)
    logger.info("AI Trading System - Dependency Check")
    logger.info("="*50)
    
    # Python version
    logger.info(f"Python Version: {sys.version}")
    logger.info("")
    
    # Core dependencies
    logger.info("Core Dependencies:")
    dependencies = [
        ('NumPy', 'numpy'),
        ('Pandas', 'pandas'),
        ('SciPy', 'scipy'),
        ('PyYAML', 'yaml'),
        ('Joblib', 'joblib'),
    ]
    
    core_ok = True
    for name, import_name in dependencies:
        if not check_package(name, import_name):
            core_ok = False
    
    logger.info("")
    
    # ML dependencies
    logger.info("Machine Learning Dependencies:")
    ml_dependencies = [
        ('LightGBM', 'lightgbm'),
        ('Scikit-learn', 'sklearn'),
        ('ONNX Runtime', 'onnxruntime'),
        ('PyTorch', 'torch'),
    ]
    
    ml_ok = True
    for name, import_name in ml_dependencies:
        if not check_package(name, import_name):
            ml_ok = False
    
    logger.info("")
    
    # Communication dependencies
    logger.info("Communication Dependencies:")
    comm_dependencies = [
        ('PyZMQ', 'zmq'),
        ('Coloredlogs', 'coloredlogs'),
    ]
    
    comm_ok = True
    for name, import_name in comm_dependencies:
        if not check_package(name, import_name):
            comm_ok = False
    
    logger.info("")
    
    # Technical Analysis
    logger.info("Technical Analysis Dependencies:")
    ta_dependencies = [
        ('TA-Lib Alternative', 'ta'),
    ]
    
    ta_ok = True
    for name, import_name in ta_dependencies:
        if not check_package(name, import_name):
            ta_ok = False
    
    logger.info("")
    logger.info("="*50)
    
    # Summary
    if core_ok and ml_ok and comm_ok and ta_ok:
        logger.info("✓ ALL DEPENDENCIES SATISFIED")
        logger.info("System is ready to run!")
    else:
        logger.error("✗ MISSING DEPENDENCIES DETECTED")
        logger.error("Please install missing packages using:")
        logger.error("pip install <package_name>")
        return 1
    
    logger.info("="*50)
    return 0

if __name__ == "__main__":
    sys.exit(main())