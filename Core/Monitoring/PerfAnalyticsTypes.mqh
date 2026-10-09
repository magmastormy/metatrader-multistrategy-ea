// Shared constants and stateless helpers for the performance
// analytics framework. Extracted verbatim from
// PerformanceAnalytics.mqh (behaviour unchanged).
#ifndef CORE_PERF_ANALYTICS_TYPES_MQH
#define CORE_PERF_ANALYTICS_TYPES_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"

// Circular buffer capacity for trade / equity history
#ifndef MAX_TRADES
#define MAX_TRADES 1000
#endif

// Stateless statistical helpers
class CPerfAnalyticsMath
{
public:
    //--- Population sample standard deviation (n-1 denominator)
    static double CalculateStandardDeviation(const double &returns[])
    {
        int size = ArraySize(returns);
        if(size < 2) return 0.0;

        // Calculate mean
        double mean = 0.0;
        for(int i = 0; i < size; i++)
            mean += returns[i];
        mean /= (double)size;

        // Calculate variance
        double variance = 0.0;
        for(int i = 0; i < size; i++)
        {
            double diff = returns[i] - mean;
            variance += diff * diff;
        }
        variance /= (double)(size - 1);

        return MathSqrt(variance);
    }
};

// Stateless logging sink shared by all analytics modules
class CPerfAnalyticsLog
{
public:
    static void LogPerformanceUpdate(const string message)
    {
        CEnhancedErrorHandler::LogError(ERROR_INFO, "PerformanceAnalytics", message, 0);
    }
};

#endif // CORE_PERF_ANALYTICS_TYPES_MQH
