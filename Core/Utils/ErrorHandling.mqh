// Comprehensive Error Handling Framework
// Provides robust error management, recovery, and logging
#property copyright "Copyright 2024, Windsurf AI"

#property link      "https://www.windsurf.ai"
#property version   "2.10"
#property strict

#include <Trade/Trade.mqh>  // For CTrade class

#ifndef CORE_ERROR_HANDLING_MQH
#define CORE_ERROR_HANDLING_MQH

#include "../Utils/Enums.mqh"

// Structural decomposition (behaviour unchanged).
// This header is a thin coordinator: it aggregates the extracted
// modules so that every symbol previously declared here remains
// available to any translation unit including this file.
// ErrorHandlingTypes.mqh  - enums, structs, severity macros,
// forward declarations
// ErrorHandlingCore.mqh   - CEnhancedErrorHandler declaration,
// static state storage,
// singleton + lifecycle methods
// ErrorHandlingFormat.mqh - message formatting and error-code
// classification helpers
// ErrorHandlingRetry.mqh  - retry / backoff logic and cleanup
// ErrorHandlingReport.mqh - logging sinks, verbosity, aggregation
// ErrorHandlingHealth.mqh - component health, stats, emergency
#include "ErrorHandlingTypes.mqh"
#include "ErrorHandlingCore.mqh"
#include "ErrorHandlingFormat.mqh"
#include "ErrorHandlingRetry.mqh"
#include "ErrorHandlingReport.mqh"
#include "ErrorHandlingHealth.mqh"

#endif // CORE_ERROR_HANDLING_MQH
