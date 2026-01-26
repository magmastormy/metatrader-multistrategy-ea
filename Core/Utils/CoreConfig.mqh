//+------------------------------------------------------------------+
//| CoreConfig.mqh - Centalized EA Configuration                     |
//+------------------------------------------------------------------+
#ifndef __CORE_CONFIG_MQH__
#define __CORE_CONFIG_MQH__

// Global Risk Configuration
#define GLOBAL_DEFAULT_RISK_PERCENT 0.02
#define GLOBAL_MAX_RISK_PERCENT     0.05
#define GLOBAL_MIN_RISK_PERCENT     0.005

// Global Strategy Configuration
#define GLOBAL_MIN_QUORUM           1
#define GLOBAL_OTE_BONUS            0.15
#define GLOBAL_KILLZONE_BONUS       0.10

// Execution Configuration
#define GLOBAL_MAX_RETRIES          3
#define GLOBAL_RETRY_DELAY          100 // ms

// Structural Memory Configuration
#define GLOBAL_LOOKBACK_BARS        500
#define GLOBAL_MAX_ZONES            100

#endif
