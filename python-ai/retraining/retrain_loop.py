"""
Automated Model Retraining Loop - Main Orchestrator
Coordinates data collection, training, evaluation, and deployment
"""

import logging
import sys
from pathlib import Path
from datetime import datetime
from typing import Dict, Optional
import json

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(name)s: %(message)s',
    handlers=[
        logging.FileHandler('logs/retraining.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

# Import retraining modules
from .data_ingestion import DataIngestion
from .feature_engineering import RetrainingFeatureEngineer
from .model_training import ModelTrainer
from .model_evaluation import ModelEvaluator
from .model_registry import ModelRegistry


class RetrainingPipeline:
    """Automated model retraining pipeline"""
    
    def __init__(self, config: Dict = None):
        logger.info("="*70)
        logger.info("INITIALIZING AUTOMATED RETRAINING PIPELINE")
        logger.info("="*70)
        
        self.config = config or self._default_config()
        
        # Initialize components
        self.data_ingestion = DataIngestion(
            mt5_log_dir=self.config.get('mt5_log_dir', 'D:\\Program Files\\MetaTrader 5\\logs'),
            data_lake_dir=self.config.get('data_lake_dir', 'data_lake')
        )
        
        self.feature_engineer = RetrainingFeatureEngineer()
        self.model_trainer = ModelTrainer(output_dir='models')
        self.model_evaluator = ModelEvaluator()
        self.model_registry = ModelRegistry(registry_dir='models')
        
        self.pipeline_metadata = []
        
        logger.info("✅ Pipeline initialized")
    
    def _default_config(self) -> Dict:
        """Default configuration"""
        return {
            'mt5_log_dir': 'D:\\Program Files\\MetaTrader 5\\logs',
            'data_lake_dir': 'data_lake',
            'days_back': 30,
            'model_type': 'lgbm',
            'use_optuna': True,
            'optuna_trials': 50,
            'cross_validation_folds': 5,
            'auto_deploy': False,
            'min_samples': 1000
        }
    
    def run_full_pipeline(self) -> Dict:
        """Run complete retraining pipeline"""
        
        logger.info("\n" + "="*70)
        logger.info("🚀 STARTING FULL RETRAINING PIPELINE")
        logger.info("="*70 + "\n")
        
        pipeline_start = datetime.now()
        results = {
            'timestamp': pipeline_start.isoformat(),
            'status': 'STARTED',
            'steps': {}
        }
        
        try:
            # Step 1: Data Collection
            logger.info("\n" + "─"*70)
            logger.info("STEP 1: DATA COLLECTION")
            logger.info("─"*70)
            
            datasets = self.data_ingestion.collect_all(
                days_back=self.config.get('days_back', 30)
            )
            
            if not datasets or all(df.empty for df in datasets.values()):
                logger.error("❌ No data collected - aborting pipeline")
                results['status'] = 'FAILED'
                results['error'] = 'No data collected'
                return results
            
            results['steps']['data_collection'] = {
                'status': 'SUCCESS',
                'datasets': list(datasets.keys()),
                'total_samples': sum(len(df) for df in datasets.values())
            }
            
            # Step 2: Feature Engineering
            logger.info("\n" + "─"*70)
            logger.info("STEP 2: FEATURE ENGINEERING")
            logger.info("─"*70)
            
            # Use OHLC data for training
            ohlc_data = datasets.get('ohlc')
            if ohlc_data is None or ohlc_data.empty:
                logger.error("❌ No OHLC data available")
                results['status'] = 'FAILED'
                results['error'] = 'No OHLC data'
                return results
            
            # Build features
            features_df = self.feature_engineer.build_training_features(
                ohlc_data, 
                include_target=True
            )
            
            # Check minimum samples
            if len(features_df) < self.config.get('min_samples', 1000):
                logger.warning(f"⚠️ Insufficient samples: {len(features_df)} < {self.config['min_samples']}")
            
            # Prepare train/test split
            X = features_df.drop('target', axis=1).values
            y = features_df['target'].values
            
            from sklearn.model_selection import train_test_split
            X_train, X_temp, y_train, y_temp = train_test_split(
                X, y, test_size=0.3, random_state=42
            )
            X_val, X_test, y_val, y_test = train_test_split(
                X_temp, y_temp, test_size=0.5, random_state=42
            )
            
            results['steps']['feature_engineering'] = {
                'status': 'SUCCESS',
                'total_features': X.shape[1],
                'train_samples': len(X_train),
                'val_samples': len(X_val),
                'test_samples': len(X_test)
            }
            
            logger.info(f"✅ Features: {X.shape[1]}, Samples: {len(X)}")
            
            # Step 3: Model Training
            logger.info("\n" + "─"*70)
            logger.info("STEP 3: MODEL TRAINING")
            logger.info("─"*70)
            
            if self.config.get('use_optuna', True):
                # Train with Optuna optimization
                model, best_params = self.model_trainer.train_lgbm_with_optuna(
                    X_train, y_train,
                    X_val, y_val,
                    n_trials=self.config.get('optuna_trials', 50)
                )
            else:
                # Train without optimization
                model = self.model_trainer.train_final_model(
                    X_train, y_train,
                    X_val, y_val,
                    model_type=self.config.get('model_type', 'lgbm')
                )
                best_params = {}
            
            results['steps']['model_training'] = {
                'status': 'SUCCESS',
                'model_type': self.config.get('model_type', 'lgbm'),
                'best_params': best_params
            }
            
            # Step 4: Model Evaluation & Backtesting
            logger.info("\n" + "─"*70)
            logger.info("STEP 4: MODEL EVALUATION & BACKTESTING")
            logger.info("─"*70)
            
            # Backtest on test set
            prices = ohlc_data['close'].values[-len(X_test):] if len(ohlc_data) >= len(X_test) else None
            
            backtest_results = self.model_evaluator.backtest_model(
                model, X_test, y_test, prices
            )
            
            results['steps']['evaluation'] = {
                'status': 'SUCCESS',
                'metrics': backtest_results
            }
            
            # Step 5: Compare with Baseline
            logger.info("\n" + "─"*70)
            logger.info("STEP 5: COMPARISON WITH BASELINE")
            logger.info("─"*70)
            
            current_model = self.model_registry.get_current_model()
            
            if current_model:
                comparison = self.model_evaluator.compare_with_baseline(
                    backtest_results,
                    current_model.get('metrics', {})
                )
            else:
                logger.info("No baseline model found - this will be the first model")
                comparison = {
                    'decision': 'APPROVE',
                    'reason': 'First model registration'
                }
            
            results['steps']['comparison'] = {
                'status': 'SUCCESS',
                'decision': comparison.get('decision', 'UNKNOWN'),
                'comparison': comparison
            }
            
            # Step 6: Model Registration
            logger.info("\n" + "─"*70)
            logger.info("STEP 6: MODEL REGISTRATION")
            logger.info("─"*70)
            
            # Save model
            model_path = self.model_trainer.save_model(
                model,
                f"{self.config.get('model_type', 'lgbm')}_model",
                metadata=backtest_results
            )
            
            # Register in registry
            dataset_hash = self.data_ingestion._calculate_hash(features_df)
            
            version = self.model_registry.register_model(
                model_path=model_path,
                model_type=self.config.get('model_type', 'lgbm'),
                metrics=backtest_results,
                dataset_hash=dataset_hash,
                training_params=best_params
            )
            
            results['steps']['registration'] = {
                'status': 'SUCCESS',
                'version': version,
                'model_path': str(model_path)
            }
            
            # Step 7: Deployment Decision
            logger.info("\n" + "─"*70)
            logger.info("STEP 7: DEPLOYMENT DECISION")
            logger.info("─"*70)
            
            if comparison.get('decision') == 'APPROVE':
                if self.config.get('auto_deploy', False):
                    deployed = self.model_registry.deploy_model(
                        version,
                        reason="Automatic deployment - superior performance"
                    )
                    results['steps']['deployment'] = {
                        'status': 'DEPLOYED' if deployed else 'FAILED',
                        'version': version
                    }
                else:
                    logger.info("⚠️ Auto-deploy disabled - model approved but not deployed")
                    logger.info(f"   To deploy manually: registry.deploy_model('{version}')")
                    results['steps']['deployment'] = {
                        'status': 'APPROVED_NOT_DEPLOYED',
                        'version': version
                    }
            else:
                logger.info("❌ Model rejected - not deploying")
                results['steps']['deployment'] = {
                    'status': 'REJECTED',
                    'reason': 'Did not meet improvement criteria'
                }
            
            # Step 8: Generate Reports
            logger.info("\n" + "─"*70)
            logger.info("STEP 8: GENERATING REPORTS")
            logger.info("─"*70)
            
            self._generate_reports(backtest_results, comparison, version)
            
            results['steps']['reporting'] = {'status': 'SUCCESS'}
            
            # Pipeline complete
            results['status'] = 'SUCCESS'
            results['duration_seconds'] = (datetime.now() - pipeline_start).total_seconds()
            
            logger.info("\n" + "="*70)
            logger.info("✅ PIPELINE COMPLETED SUCCESSFULLY")
            logger.info(f"   Duration: {results['duration_seconds']:.2f}s")
            logger.info(f"   New Version: {version}")
            logger.info(f"   Decision: {comparison.get('decision')}")
            logger.info("="*70 + "\n")
            
        except Exception as e:
            logger.error(f"\n❌ PIPELINE FAILED: {e}", exc_info=True)
            results['status'] = 'FAILED'
            results['error'] = str(e)
        
        # Save pipeline metadata
        self.pipeline_metadata.append(results)
        self._save_pipeline_metadata()
        
        return results
    
    def _generate_reports(self, backtest_results: Dict, comparison: Dict, version: str):
        """Generate comprehensive reports"""
        
        reports_dir = Path('reports')
        reports_dir.mkdir(exist_ok=True)
        
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        
        # 1. Evaluation report
        eval_report = self.model_evaluator.generate_evaluation_report(
            backtest_results,
            comparison,
            output_file=str(reports_dir / f'evaluation_{version}_{timestamp}.md')
        )
        
        # 2. Registry report
        registry_report = self.model_registry.generate_registry_report()
        with open(reports_dir / f'registry_{timestamp}.md', 'w') as f:
            f.write(registry_report)
        
        # 3. Training summary
        summary = {
            'version': version,
            'timestamp': timestamp,
            'backtest_results': backtest_results,
            'comparison': comparison,
            'config': self.config
        }
        
        with open(reports_dir / f'training_summary_{version}_{timestamp}.json', 'w') as f:
            json.dump(summary, f, indent=2)
        
        logger.info(f"✅ Reports generated in {reports_dir}")
    
    def _save_pipeline_metadata(self):
        """Save pipeline run metadata"""
        metadata_file = Path('logs/pipeline_runs.json')
        metadata_file.parent.mkdir(exist_ok=True)
        
        with open(metadata_file, 'w') as f:
            json.dump(self.pipeline_metadata, f, indent=2)


def main():
    """Main entry point for manual execution"""
    
    # Configuration
    config = {
        'days_back': 30,
        'model_type': 'lgbm',
        'use_optuna': True,
        'optuna_trials': 30,  # Reduced for faster testing
        'auto_deploy': False,  # Manual deployment for safety
        'min_samples': 100  # Lower threshold for testing
    }
    
    # Run pipeline
    pipeline = RetrainingPipeline(config=config)
    results = pipeline.run_full_pipeline()
    
    # Print summary
    print("\n" + "="*70)
    print("PIPELINE SUMMARY")
    print("="*70)
    print(f"Status: {results['status']}")
    
    if results['status'] == 'SUCCESS':
        print(f"Duration: {results.get('duration_seconds', 0):.2f}s")
        print(f"New Version: {results['steps']['registration']['version']}")
        print(f"Decision: {results['steps']['comparison']['decision']}")
    else:
        print(f"Error: {results.get('error', 'Unknown')}")
    
    print("="*70)


if __name__ == "__main__":
    main()
