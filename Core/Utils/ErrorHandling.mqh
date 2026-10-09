// Error handling framework: severity-gated logging, retry/backoff, component
// health and emergency-mode escalation.
#property copyright "Copyright 2024, Windsurf AI"

#property link      "https://www.windsurf.ai"
#property version   "2.10"
#property strict

#include <Trade/Trade.mqh>  // For CTrade class

#ifndef CORE_ERROR_HANDLING_MQH
#define CORE_ERROR_HANDLING_MQH

#include "../Utils/Enums.mqh"

// Thin coordinator: aggregates the extracted ErrorHandling* modules so every
// symbol previously declared here stays available to any includer.
//   Types  - enums, structs, severity macros, forward declarations
//   Core   - CEnhancedErrorHandler declaration, static state storage, lifecycle
//   Format - message formatting and error-code classification helpers
//   Retry  - retry / backoff logic and cleanup
//   Report - logging sinks, verbosity, aggregation
//   Health - component health, stats, emergency mode
#include "ErrorHandlingTypes.mqh"
#include "ErrorHandlingCore.mqh"
#include "ErrorHandlingFormat.mqh"
#include "ErrorHandlingRetry.mqh"
#include "ErrorHandlingReport.mqh"
#include "ErrorHandlingHealth.mqh"

#endif // CORE_ERROR_HANDLING_MQH
