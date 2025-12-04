"""
Model Registry - Versioning and deployment management
Tracks model versions, metrics, and manages deployment
"""

import json
import logging
from pathlib import Path
from datetime import datetime
from typing import Dict, List, Optional
import shutil

logger = logging.getLogger(__name__)


class ModelRegistry:
    """Manages model versions and deployment"""
    
    def __init__(self, registry_dir: str = "models"):
        self.registry_dir = Path(registry_dir)
        self.registry_dir.mkdir(exist_ok=True)
        
        self.registry_file = self.registry_dir / "model_registry.json"
        self.registry = self._load_registry()
        
        self.deployed_models_dir = self.registry_dir / "deployed"
        self.archived_models_dir = self.registry_dir / "archived"
        
        self.deployed_models_dir.mkdir(exist_ok=True)
        self.archived_models_dir.mkdir(exist_ok=True)
    
    def _load_registry(self) -> Dict:
        """Load model registry from file"""
        if self.registry_file.exists():
            with open(self.registry_file, 'r') as f:
                return json.load(f)
        return {
            'models': [],
            'current_version': None,
            'deployment_history': []
        }
    
    def _save_registry(self):
        """Save registry to file"""
        with open(self.registry_file, 'w') as f:
            json.dump(self.registry, f, indent=2)
        logger.info(f"Registry saved: {self.registry_file}")
    
    def register_model(self, 
                       model_path: str,
                       model_type: str,
                       metrics: Dict,
                       dataset_hash: str,
                       training_params: Dict = None) -> str:
        """Register a new model version"""
        
        # Generate version number
        version = self._generate_version()
        
        model_entry = {
            'version': version,
            'model_type': model_type,
            'model_path': str(model_path),
            'metrics': metrics,
            'dataset_hash': dataset_hash,
            'training_date': datetime.now().isoformat(),
            'training_params': training_params or {},
            'status': 'registered',
            'deployed': False
        }
        
        self.registry['models'].append(model_entry)
        self._save_registry()
        
        logger.info(f"✅ Model registered: version {version}")
        logger.info(f"   Type: {model_type}")
        logger.info(f"   Metrics: {metrics}")
        
        return version
    
    def _generate_version(self) -> str:
        """Generate next version number"""
        existing_versions = [m['version'] for m in self.registry['models']]
        
        if not existing_versions:
            return "v1.0.0"
        
        # Parse latest version
        latest = existing_versions[-1]
        major, minor, patch = map(int, latest[1:].split('.'))
        
        # Increment patch version
        new_version = f"v{major}.{minor}.{patch + 1}"
        
        return new_version
    
    def get_model_by_version(self, version: str) -> Optional[Dict]:
        """Get model entry by version"""
        for model in self.registry['models']:
            if model['version'] == version:
                return model
        return None
    
    def get_current_model(self) -> Optional[Dict]:
        """Get currently deployed model"""
        current_version = self.registry.get('current_version')
        if current_version:
            return self.get_model_by_version(current_version)
        return None
    
    def get_best_model(self, metric: str = 'sharpe_ratio') -> Optional[Dict]:
        """Get model with best performance on specified metric"""
        if not self.registry['models']:
            return None
        
        best_model = None
        best_score = -float('inf')
        
        for model in self.registry['models']:
            metrics = model.get('metrics', {})
            trading_metrics = metrics.get('trading_metrics', {})
            
            if metric in trading_metrics:
                score = trading_metrics[metric]
                if score > best_score:
                    best_score = score
                    best_model = model
        
        return best_model
    
    def deploy_model(self, version: str, reason: str = "") -> bool:
        """Deploy a model version to production"""
        
        logger.info("="*60)
        logger.info(f"DEPLOYING MODEL VERSION: {version}")
        logger.info("="*60)
        
        model_entry = self.get_model_by_version(version)
        if not model_entry:
            logger.error(f"Model version {version} not found")
            return False
        
        # Archive current model if exists
        current_model = self.get_current_model()
        if current_model:
            logger.info(f"Archiving current model: {current_model['version']}")
            self._archive_model(current_model['version'])
        
        # Copy model to deployed directory
        model_path = Path(model_entry['model_path'])
        if model_path.exists():
            deployed_path = self.deployed_models_dir / model_path.name
            shutil.copy2(model_path, deployed_path)
            logger.info(f"Model copied to deployed directory")
        else:
            logger.warning(f"Model file not found: {model_path}")
        
        # Update registry
        model_entry['deployed'] = True
        model_entry['deployment_date'] = datetime.now().isoformat()
        
        self.registry['current_version'] = version
        
        # Add to deployment history
        deployment_record = {
            'version': version,
            'timestamp': datetime.now().isoformat(),
            'reason': reason,
            'metrics': model_entry['metrics']
        }
        self.registry['deployment_history'].append(deployment_record)
        
        self._save_registry()
        
        logger.info(f"✅ Model {version} deployed successfully")
        logger.info("="*60)
        
        return True
    
    def _archive_model(self, version: str):
        """Archive a model version"""
        model_entry = self.get_model_by_version(version)
        if not model_entry:
            return
        
        model_path = Path(model_entry['model_path'])
        if model_path.exists():
            archived_path = self.archived_models_dir / f"{version}_{model_path.name}"
            shutil.copy2(model_path, archived_path)
            logger.info(f"Model archived: {archived_path}")
        
        model_entry['deployed'] = False
        model_entry['archived'] = True
        model_entry['archive_date'] = datetime.now().isoformat()
    
    def rollback_to_version(self, version: str) -> bool:
        """Rollback to a previous model version"""
        
        logger.info(f"Rolling back to version: {version}")
        
        model_entry = self.get_model_by_version(version)
        if not model_entry:
            logger.error(f"Version {version} not found")
            return False
        
        return self.deploy_model(version, reason=f"Rollback from {self.registry.get('current_version')}")
    
    def get_deployment_history(self) -> List[Dict]:
        """Get deployment history"""
        return self.registry.get('deployment_history', [])
    
    def get_all_models(self) -> List[Dict]:
        """Get all registered models"""
        return self.registry.get('models', [])
    
    def generate_registry_report(self) -> str:
        """Generate registry report"""
        report = []
        report.append("="*60)
        report.append("MODEL REGISTRY REPORT")
        report.append("="*60)
        report.append(f"Generated: {datetime.now().isoformat()}")
        report.append("")
        
        report.append(f"Total Models: {len(self.registry['models'])}")
        report.append(f"Current Version: {self.registry.get('current_version', 'None')}")
        report.append("")
        
        report.append("## All Models")
        for model in self.registry['models']:
            report.append(f"\n### {model['version']}")
            report.append(f"  Type: {model['model_type']}")
            report.append(f"  Training Date: {model['training_date']}")
            report.append(f"  Deployed: {model.get('deployed', False)}")
            
            metrics = model.get('metrics', {})
            if 'ml_metrics' in metrics:
                report.append(f"  Accuracy: {metrics['ml_metrics'].get('accuracy', 0):.4f}")
            if 'trading_metrics' in metrics:
                tm = metrics['trading_metrics']
                report.append(f"  Sharpe: {tm.get('sharpe_ratio', 0):.4f}")
                report.append(f"  Win Rate: {tm.get('win_rate', 0):.4f}")
        
        report.append("\n## Deployment History")
        for deployment in self.registry.get('deployment_history', []):
            report.append(f"\n- {deployment['version']} at {deployment['timestamp']}")
            report.append(f"  Reason: {deployment.get('reason', 'N/A')}")
        
        report.append("\n" + "="*60)
        
        return "\n".join(report)
