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

// Thin coordinator: aggregates the ErrorHandling* modules included below so every symbol previously declared
// here stays available to any includer.
#include "ErrorHandlingTypes.mqh"
#include "ErrorHandlingCore.mqh"
#include "ErrorHandlingFormat.mqh"
#include "ErrorHandlingRetry.mqh"
#include "ErrorHandlingReport.mqh"
#include "ErrorHandlingHealth.mqh"

#endif // CORE_ERROR_HANDLING_MQH
