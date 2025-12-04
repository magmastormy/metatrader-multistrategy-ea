"""
Automated Scheduler for Model Retraining
Triggers retraining based on time, data volume, or performance criteria
"""

import logging
import time
import schedule
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, Callable
import json

logger = logging.getLogger(__name__)


class RetrainingScheduler:
    """Automated scheduler for model retraining"""
    
    def __init__(self, pipeline_runner: Callable, config: Dict = None):
        self.pipeline_runner = pipeline_runner
        self.config = config or self._default_config()
        
        self.last_run = None
        self.run_history = []
        self.is_running = False
        
        logger.info("Retraining Scheduler initialized")
    
    def _default_config(self) -> Dict:
        """Default scheduler configuration"""
        return {
            'schedule_type': 'daily',  # daily, weekly, trigger_based
            'schedule_time': '02:00',  # 2 AM
            'min_new_rows': 1000,  # Minimum new data rows to trigger
            'performance_threshold': 0.50,  # Retrain if accuracy drops below
            'max_days_since_training': 7  # Force retrain after N days
        }
    
    def start(self):
        """Start the scheduler"""
        logger.info("="*60)
        logger.info("STARTING AUTOMATED RETRAINING SCHEDULER")
        logger.info("="*60)
        
        schedule_type = self.config.get('schedule_type', 'daily')
        
        if schedule_type == 'daily':
            self._schedule_daily()
        elif schedule_type == 'weekly':
            self._schedule_weekly()
        elif schedule_type == 'trigger_based':
            self._schedule_trigger_based()
        else:
            logger.error(f"Unknown schedule type: {schedule_type}")
            return
        
        logger.info(f"Scheduler started: {schedule_type}")
        logger.info(f"Next run: {schedule.next_run()}")
        
        self.is_running = True
        
        # Run scheduler loop
        try:
            while self.is_running:
                schedule.run_pending()
                time.sleep(60)  # Check every minute
                
        except KeyboardInterrupt:
            logger.info("Scheduler stopped by user")
            self.stop()
    
    def _schedule_daily(self):
        """Schedule daily retraining"""
        schedule_time = self.config.get('schedule_time', '02:00')
        schedule.every().day.at(schedule_time).do(self._run_retraining)
        logger.info(f"Scheduled daily at {schedule_time}")
    
    def _schedule_weekly(self):
        """Schedule weekly retraining"""
        schedule_time = self.config.get('schedule_time', '02:00')
        day = self.config.get('schedule_day', 'sunday')
        
        if day.lower() == 'monday':
            schedule.every().monday.at(schedule_time).do(self._run_retraining)
        elif day.lower() == 'sunday':
            schedule.every().sunday.at(schedule_time).do(self._run_retraining)
        # Add other days as needed
        
        logger.info(f"Scheduled weekly on {day} at {schedule_time}")
    
    def _schedule_trigger_based(self):
        """Schedule based on triggers (check periodically)"""
        # Check every 6 hours for trigger conditions
        schedule.every(6).hours.do(self._check_triggers_and_run)
        logger.info("Scheduled trigger-based (check every 6 hours)")
    
    def _check_triggers_and_run(self):
        """Check if any trigger conditions are met"""
        logger.info("Checking trigger conditions...")
        
        should_run = False
        reasons = []
        
        # Trigger 1: Check for new data
        new_rows = self._count_new_data_rows()
        min_rows = self.config.get('min_new_rows', 1000)
        
        if new_rows >= min_rows:
            should_run = True
            reasons.append(f"New data available: {new_rows} rows")
        
        # Trigger 2: Check days since last training
        if self.last_run:
            days_since = (datetime.now() - self.last_run).days
            max_days = self.config.get('max_days_since_training', 7)
            
            if days_since >= max_days:
                should_run = True
                reasons.append(f"Time-based trigger: {days_since} days since last training")
        else:
            should_run = True
            reasons.append("First training run")
        
        # Trigger 3: Check model performance degradation
        if self._check_performance_degradation():
            should_run = True
            reasons.append("Performance degradation detected")
        
        if should_run:
            logger.info(f"Triggers met: {', '.join(reasons)}")
            self._run_retraining()
        else:
            logger.info("No triggers met - skipping retraining")
    
    def _count_new_data_rows(self) -> int:
        """Count new data rows since last training"""
        # Check data lake for new data
        data_lake = Path('data_lake/raw')
        if not data_lake.exists():
            return 0
        
        # Count files modified since last run
        if self.last_run is None:
            return 1000  # Assume sufficient data for first run
        
        new_files = 0
        for file in data_lake.glob('*.parquet'):
            if datetime.fromtimestamp(file.stat().st_mtime) > self.last_run:
                new_files += 1
        
        # Rough estimate: 1000 rows per file
        return new_files * 1000
    
    def _check_performance_degradation(self) -> bool:
        """Check if current model performance has degraded"""
        # Load recent performance metrics from logs
        try:
            logs_file = Path('logs/ai_runtime.log')
            if not logs_file.exists():
                return False
            
            # In production, parse logs and check actual performance
            # For now, return False
            return False
            
        except Exception as e:
            logger.error(f"Error checking performance: {e}")
            return False
    
    def _run_retraining(self):
        """Execute retraining pipeline"""
        logger.info("\n" + "="*60)
        logger.info("🔄 TRIGGERED RETRAINING")
        logger.info(f"Time: {datetime.now().isoformat()}")
        logger.info("="*60 + "\n")
        
        try:
            # Run the pipeline
            results = self.pipeline_runner()
            
            # Record run
            self.last_run = datetime.now()
            self.run_history.append({
                'timestamp': self.last_run.isoformat(),
                'status': results.get('status'),
                'duration': results.get('duration_seconds')
            })
            
            self._save_run_history()
            
            logger.info(f"✅ Retraining complete: {results.get('status')}")
            
        except Exception as e:
            logger.error(f"❌ Retraining failed: {e}", exc_info=True)
            
            self.run_history.append({
                'timestamp': datetime.now().isoformat(),
                'status': 'FAILED',
                'error': str(e)
            })
            
            self._save_run_history()
    
    def _save_run_history(self):
        """Save scheduler run history"""
        history_file = Path('logs/scheduler_history.json')
        history_file.parent.mkdir(exist_ok=True)
        
        with open(history_file, 'w') as f:
            json.dump({
                'last_run': self.last_run.isoformat() if self.last_run else None,
                'run_history': self.run_history
            }, f, indent=2)
    
    def stop(self):
        """Stop the scheduler"""
        logger.info("Stopping scheduler...")
        self.is_running = False
        schedule.clear()
        logger.info("Scheduler stopped")
    
    def get_next_run_time(self) -> str:
        """Get next scheduled run time"""
        next_run = schedule.next_run()
        if next_run:
            return next_run.isoformat()
        return "Not scheduled"
    
    def get_status(self) -> Dict:
        """Get scheduler status"""
        return {
            'running': self.is_running,
            'last_run': self.last_run.isoformat() if self.last_run else None,
            'next_run': self.get_next_run_time(),
            'total_runs': len(self.run_history),
            'config': self.config
        }


def main():
    """Main entry point for scheduler"""
    from retrain_loop import RetrainingPipeline
    
    # Create pipeline
    pipeline = RetrainingPipeline()
    
    # Create scheduler
    scheduler_config = {
        'schedule_type': 'trigger_based',  # Check for triggers every 6 hours
        'min_new_rows': 500,
        'max_days_since_training': 7
    }
    
    scheduler = RetrainingScheduler(
        pipeline_runner=pipeline.run_full_pipeline,
        config=scheduler_config
    )
    
    # Start scheduler
    scheduler.start()


if __name__ == "__main__":
    main()
