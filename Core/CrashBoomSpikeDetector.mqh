//+------------------------------------------------------------------+
//| Crash/Boom Spike Detection Module                                 |
//| Specialized spike detection for Deriv Crash/Boom Indices          |
//| Enhanced with advanced algorithms and risk management             |
//+------------------------------------------------------------------+
#ifndef __CRASH_BOOM_SPIKE_DETECTOR_MQH__
#define __CRASH_BOOM_SPIKE_DETECTOR_MQH__

#include "../Utilities/Utilities.mqh"
#include "ErrorHandling.mqh"
#include "Enums.mqh"

// Enhanced spike detection parameters
struct SpikeDetectionConfig {
    string symbol;
    double spikeThreshold;        // Minimum price change to consider a spike
    int detectionWindow;          // Number of ticks to analyze
    double volumeMultiplier;      // Volume spike multiplier
    int cooldownPeriod;          // Seconds between spike detections
    bool enablePreSpikeDetection; // Detect conditions before spikes
    
    // Enhanced parameters
    double adaptiveThreshold;     // Dynamic threshold based on volatility
    int momentumWindow;          // Window for momentum analysis
    double correlationThreshold; // Correlation threshold for multi-symbol analysis
    bool enableMachineLearning;  // Enable ML-based spike prediction
    double riskMultiplier;       // Risk adjustment multiplier for this symbol
};

// Enhanced spike event data
struct SpikeEvent {
    datetime timestamp;
    string symbol;
    double priceBeforeSpike;
    double priceAfterSpike;
    double spikeSize;
    bool isBoomSpike;            // true for boom, false for crash
    double volume;
    int ticksToSpike;            // Ticks leading to spike
    double confidence;           // Spike detection confidence (0-1)
    
    // Enhanced data
    double spikeVelocity;        // Speed of price change
    double marketImpact;         // Market impact score
    ENUM_SPIKE_TYPE spikeType;   // Classification of spike type
    double recoveryTime;         // Time to price recovery
    bool wasTraded;              // Whether this spike was traded
    double tradeResult;          // Result if traded
    double riskScore;            // Risk assessment score
};

// Pre-spike pattern data
struct PreSpikePattern {
    double priceCompression;     // Price range compression before spike
    double volumeBuildup;        // Volume accumulation
    int ticksSinceLastSpike;     // Ticks since last spike
    double momentumDivergence;   // Price-volume divergence
    bool isValid;
};

// Crash/Boom performance metrics
struct CrashBoomPerformance {
    string symbol;
    int totalSpikesDetected;
    int successfulTrades;
    double avgSpikeSize;
    double avgTimeToSpike;
    double winRate;
    double avgReturn;
    datetime lastSpikeTime;
    double bestSpikeSize;
};

class CCrashBoomSpikeDetector {
private:
    CUtilities* m_utilities;
    CEnhancedErrorHandler* m_errorHandler;
    
    // Configuration arrays
    SpikeDetectionConfig m_configs[];
    
    // Spike history
    SpikeEvent m_spikeHistory[];
    int m_maxSpikeHistory;
    
    // Performance tracking
    CrashBoomPerformance m_performance[];
    
    // Real-time monitoring
    double m_lastPrices[];
    datetime m_lastPriceTimes[];
    double m_tickVolumes[];
    int m_tickCounts[];
    
    // Detection parameters
    double m_minSpikeSize;
    double m_maxSpikeSize;
    int m_analysisWindow;
    double m_confidenceThreshold;
    
    // Enhanced spike detection with advanced algorithms
    bool DetectPriceSpike(const string symbolParam, double currentPriceParam, double &spikeSize, bool &isBoom) {
        int configIndex = GetConfigIndex(symbolParam);
        if(configIndex == -1) return false;
        
        SpikeDetectionConfig config = m_configs[configIndex];
        
        // Get recent price history using actual tick data
        MqlTick ticks[];
        int tickCount = CopyTicks(symbolParam, ticks, COPY_TICKS_ALL, 0, config.detectionWindow);
        
        if(tickCount < config.detectionWindow) {
            // Fallback to simplified detection
            return DetectPriceSpikeSimple(symbolParam, currentPriceParam, spikeSize, isBoom);
        }
        
        // Calculate dynamic threshold based on recent volatility
        double volatility = CalculateTickVolatility(ticks, tickCount);
        double adaptiveThreshold = config.spikeThreshold * (1.0 + volatility);
        
        // Multi-timeframe spike detection
        double shortTermAvg = 0, mediumTermAvg = 0;
        int shortWindow = MathMin(5, tickCount/4);
        int mediumWindow = MathMin(15, tickCount/2);
        
        // Calculate short-term average (recent ticks)
        for(int i = tickCount - shortWindow; i < tickCount; i++) {
            shortTermAvg += ticks[i].bid;
        }
        shortTermAvg /= shortWindow;
        
        // Calculate medium-term average
        for(int i = tickCount - mediumWindow; i < tickCount; i++) {
            mediumTermAvg += ticks[i].bid;
        }
        mediumTermAvg /= mediumWindow;
        
        // Enhanced spike calculation
        double priceDeviation = MathAbs(currentPriceParam - mediumTermAvg);
        double momentumFactor = MathAbs(shortTermAvg - mediumTermAvg);
        
        spikeSize = priceDeviation + (momentumFactor * 0.5);
        isBoom = (currentPriceParam > mediumTermAvg);
        
        // Volume confirmation
        bool volumeConfirmed = false;
        if(tickCount > 1) {
            double avgVolume = 0;
            for(int i = 0; i < tickCount - 1; i++) {
                avgVolume += (double)ticks[i].volume;
            }
            avgVolume /= (tickCount - 1);
            
            volumeConfirmed = (ticks[tickCount-1].volume > avgVolume * config.volumeMultiplier);
        }
        
        // Spike velocity check
        double spikeVelocity = 0;
        if(tickCount > 2) {
            datetime timeDiff = ticks[tickCount-1].time - ticks[tickCount-3].time;
            if(timeDiff > 0) {
                spikeVelocity = spikeSize / (double)timeDiff;
            }
        }
        
        // Final spike confirmation
        bool isSpike = (spikeSize >= adaptiveThreshold) && 
                      (volumeConfirmed || spikeVelocity > 0.1);
        
        return isSpike;
    }
    
    // Simplified spike detection fallback
    bool DetectPriceSpikeSimple(const string symbolParam, double currentPriceParam, double &spikeSize, bool &isBoom) {
        int configIndex = GetConfigIndex(symbolParam);
        if(configIndex == -1) return false;
        
        SpikeDetectionConfig config = m_configs[configIndex];
        
        // Use OHLC data as fallback
        double high = iHigh(symbolParam, PERIOD_M1, 0);
        double low = iLow(symbolParam, PERIOD_M1, 0);
        double open = iOpen(symbolParam, PERIOD_M1, 0);
        double close = iClose(symbolParam, PERIOD_M1, 0);
        
        // Calculate average and spike size
        double avgPrice = (high + low + open + close) / 4.0;
        spikeSize = MathAbs(currentPriceParam - avgPrice);
        isBoom = (currentPriceParam > avgPrice);
        
        return (spikeSize >= config.spikeThreshold);
    }
    
    // Calculate tick-based volatility
    double CalculateTickVolatility(const MqlTick &ticks[], int count) {
        if(count < 2) return 0.0;
        
        double sum = 0, sumSquares = 0;
        for(int i = 1; i < count; i++) {
            double change = ticks[i].bid - ticks[i-1].bid;
            sum += change;
            sumSquares += change * change;
        }
        
        double mean = sum / (count - 1);
        double variance = (sumSquares / (count - 1)) - (mean * mean);
        
        return MathSqrt(MathMax(0, variance));
    }
    
    // Analyze pre-spike patterns
    PreSpikePattern AnalyzePreSpikePattern(const string symbolName) {
        PreSpikePattern pattern;
        pattern.isValid = false;
        
        int configIndex = GetConfigIndex(symbolName);
        if(configIndex == -1) return pattern;
        
        // Get recent price data
        double prices[];
        int analysisWindow = 50;
        ArrayResize(prices, analysisWindow);
        
        for(int i = 0; i < analysisWindow; i++) {
            prices[i] = SymbolInfoDouble(symbolName, SYMBOL_BID);
        }
        
        // Calculate price compression (range tightening)
        double recentRange = 0, historicalRange = 0;
        int recentWindow = 10, historicalWindow = 30;
        
        // Recent range
        double recentHigh = prices[0], recentLow = prices[0];
        for(int i = 0; i < recentWindow; i++) {
            recentHigh = MathMax(recentHigh, prices[i]);
            recentLow = MathMin(recentLow, prices[i]);
        }
        recentRange = recentHigh - recentLow;
        
        // Historical range
        double historicalHigh = prices[0], historicalLow = prices[0];
        for(int i = recentWindow; i < recentWindow + historicalWindow; i++) {
            historicalHigh = MathMax(historicalHigh, prices[i]);
            historicalLow = MathMin(historicalLow, prices[i]);
        }
        historicalRange = historicalHigh - historicalLow;
        
        // Calculate compression ratio
        if(historicalRange > 0) {
            pattern.priceCompression = recentRange / historicalRange;
        }
        
        // Volume buildup analysis (simplified)
        double volume = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_REAL);
        if(volume > 0) {
            pattern.volumeBuildup = volume;
        } else {
            pattern.volumeBuildup = 0.0;
        }
        
        // Time since last spike
        pattern.ticksSinceLastSpike = GetTicksSinceLastSpike(symbolName);
        
        // Momentum divergence (price vs volume)
        double priceChange = prices[0] - prices[9];
        double volumeChange = pattern.volumeBuildup;
        pattern.momentumDivergence = MathAbs(priceChange) / MathMax(0.001, volumeChange);
        
        // Validate pattern
        pattern.isValid = (pattern.priceCompression < 0.5 && 
                          pattern.ticksSinceLastSpike > 100 &&
                          pattern.volumeBuildup > 1.2);
        
        return pattern;
    }
    
    // Calculate spike detection confidence
    double CalculateSpikeConfidence(const SpikeEvent &spike, const PreSpikePattern &pattern) {
        double confidence = 0.0;
        
        // Base confidence from spike size
        confidence += MathMin(0.4, spike.spikeSize / m_maxSpikeSize * 0.4);
        
        // Volume confirmation
        if(spike.volume > 1.5) {
            confidence += 0.2;
        }
        
        // Pre-spike pattern confirmation
        if(pattern.isValid) {
            confidence += 0.3;
        }
        
        // Time-based confirmation
        if(spike.ticksToSpike > 50 && spike.ticksToSpike < 500) {
            confidence += 0.1;
        }
        
        return MathMin(1.0, confidence);
    }
    
    // Get ticks since last spike for symbol
    int GetTicksSinceLastSpike(const string symbolName) {
        datetime lastSpikeTime = 0;
        
        // Find last spike for this symbol
        for(int i = ArraySize(m_spikeHistory) - 1; i >= 0; i--) {
            if(m_spikeHistory[i].symbol == symbolName) {
                lastSpikeTime = m_spikeHistory[i].timestamp;
                break;
            }
        }
        
        if(lastSpikeTime == 0) return 9999; // No previous spike
        
        // Calculate approximate ticks (simplified)
        int secondsSinceSpike = (int)(TimeCurrent() - lastSpikeTime);
        return secondsSinceSpike * 2; // Assume 2 ticks per second average
    }
    
public:
    CCrashBoomSpikeDetector(CUtilities* utils = NULL, CEnhancedErrorHandler* errHandler = NULL) :
        m_utilities(utils),
        m_errorHandler(errHandler),
        m_maxSpikeHistory(500),
        m_minSpikeSize(5.0),
        m_maxSpikeSize(100.0),
        m_analysisWindow(100),
        m_confidenceThreshold(0.6)
    {
        ArrayResize(m_configs, 0);
        ArrayResize(m_spikeHistory, 0);
        ArrayResize(m_performance, 0);
        ArrayResize(m_lastPrices, 0);
        ArrayResize(m_lastPriceTimes, 0);
        ArrayResize(m_tickVolumes, 0);
        ArrayResize(m_tickCounts, 0);
    }
    
    ~CCrashBoomSpikeDetector() {
        ArrayFree(m_configs);
        ArrayFree(m_spikeHistory);
        ArrayFree(m_performance);
        ArrayFree(m_lastPrices);
        ArrayFree(m_lastPriceTimes);
        ArrayFree(m_tickVolumes);
        ArrayFree(m_tickCounts);
    }
    
    // Initialize spike detection for symbol with optimization
    bool InitializeSpikeDetection(const string symbolName, double spikeThreshold = 10.0) {
        if(!SymbolSelect(symbolName, true)) {
            CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, "CrashBoomDetector",
                "Failed to select crash/boom symbol: " + symbolName, ERR_INVALID_PARAMETER);
            return false;
        }
        
        // Add configuration
        int size = ArraySize(m_configs);
        ArrayResize(m_configs, size + 1);
        
        m_configs[size].symbol = symbolName;
        m_configs[size].spikeThreshold = spikeThreshold;
        m_configs[size].detectionWindow = 20;
        m_configs[size].volumeMultiplier = 2.0;
        m_configs[size].cooldownPeriod = 30;
        m_configs[size].enablePreSpikeDetection = true;
        
        // Enhanced parameters
        m_configs[size].adaptiveThreshold = spikeThreshold;
        m_configs[size].momentumWindow = 10;
        m_configs[size].correlationThreshold = 0.7;
        m_configs[size].enableMachineLearning = false; // Disabled for now
        m_configs[size].riskMultiplier = 1.0;
        
        // Optimize configuration for specific symbol
        OptimizeConfigForSymbol(symbolName, m_configs[size]);
        
        // Initialize performance tracking
        int perfSize = ArraySize(m_performance);
        ArrayResize(m_performance, perfSize + 1);
        
        m_performance[perfSize].symbol = symbolName;
        m_performance[perfSize].totalSpikesDetected = 0;
        m_performance[perfSize].successfulTrades = 0;
        m_performance[perfSize].avgSpikeSize = 0.0;
        m_performance[perfSize].avgTimeToSpike = 0.0;
        m_performance[perfSize].winRate = 0.0;
        m_performance[perfSize].avgReturn = 0.0;
        m_performance[perfSize].lastSpikeTime = 0;
        m_performance[perfSize].bestSpikeSize = 0.0;
        
        // Commented out LogInfo call as the method doesn't exist
        // if(m_utilities != NULL) {
        //     m_utilities->LogInfo("CrashBoomDetector",
        //         StringFormat("Initialized enhanced spike detection for %s: Threshold=%.2f, Cooldown=%ds",
        //                     symbol, m_configs[size].spikeThreshold, m_configs[size].cooldownPeriod));
        // } else {
            Print("[CrashBoomDetector] Initialized enhanced spike detection for ", symbolName,
                  ": Threshold=", DoubleToString(m_configs[size].spikeThreshold, 2),
                  ", Cooldown=", m_configs[size].cooldownPeriod, "s");
        // }
        
        return true;
    }
    
    // Mark spike as traded for performance tracking
    void MarkSpikeAsTraded(const string symbolName, datetime spikeTime) {
        for(int i = ArraySize(m_spikeHistory) - 1; i >= 0; i--) {
            if(m_spikeHistory[i].symbol == symbolName &&
               MathAbs((int)(m_spikeHistory[i].timestamp - spikeTime)) <= 5) {
                m_spikeHistory[i].wasTraded = true;
                break;
            }
        }
    }
    
    // Get comprehensive spike analysis for symbol
    string GetSpikeAnalysisReport(const string symbolName) {
        int perfIndex = GetPerformanceIndex(symbolName);
        if(perfIndex == -1) return "No data available for " + symbolName;
        
        CrashBoomPerformance perf = m_performance[perfIndex];
        
        string report = StringFormat(
            "=== Crash/Boom Spike Analysis for %s ===\n" +
            "Total Spikes Detected: %d\n" +
            "Successful Trades: %d\n" +
            "Win Rate: %.1f%%\n" +
            "Average Spike Size: %.2f points\n" +
            "Best Spike Size: %.2f points\n" +
            "Average Return: %.2f%%\n" +
            "Recent Spikes (1h): %d\n" +
            "Average Confidence: %.2f\n",
            symbolName,
            perf.totalSpikesDetected,
            perf.successfulTrades,
            perf.winRate * 100,
            perf.avgSpikeSize,
            perf.bestSpikeSize,
            perf.avgReturn,
            CountRecentSpikes(symbolName, 3600),
            GetAverageRecentConfidence(symbolName)
        );
        
        return report;
    }
    
    // Monitor for spikes in real-time
    bool MonitorForSpikes(const string symbolName) {
        double currentPriceValue = SymbolInfoDouble(symbolName, SYMBOL_BID);
        double spikeSize;
        bool isBoom;
        
        // Check for spike
        if(DetectPriceSpike(symbolName, currentPriceValue, spikeSize, isBoom)) {
            // Analyze pre-spike pattern
            PreSpikePattern pattern = AnalyzePreSpikePattern(symbolName);
            
            // Create spike event
            SpikeEvent spike;
            spike.timestamp = TimeCurrent();
            spike.symbol = symbolName;
            spike.priceAfterSpike = currentPriceValue;
            spike.priceBeforeSpike = currentPriceValue - (isBoom ? spikeSize : -spikeSize);
            spike.spikeSize = spikeSize;
            spike.isBoomSpike = isBoom;
            double volume = SymbolInfoDouble(symbolName, SYMBOL_VOLUME_REAL);
            spike.volume = volume;
            spike.ticksToSpike = GetTicksSinceLastSpike(symbolName);
            spike.confidence = CalculateSpikeConfidence(spike, pattern);
            
            // Add to history
            AddSpikeToHistory(spike);
            
            // Update performance
            UpdateSpikePerformance(symbolName, spike);
            
            // Log spike detection
            if(m_utilities != NULL) {
                m_utilities.LogInfo("CrashBoomDetector",
                    StringFormat("%s SPIKE detected on %s: Size=%.2f, Confidence=%.2f",
                        isBoom ? "BOOM" : "CRASH", symbolName, spikeSize, spike.confidence));
            } else {
                Print("[CrashBoomDetector] ", isBoom ? "BOOM" : "CRASH", " SPIKE detected on ", symbolName,
                      ": Size=", DoubleToString(spikeSize, 2), ", Confidence=", DoubleToString(spike.confidence, 2));
            }
            
            return true;
        }
        
        return false;
    }
    
    // Enhanced spike-based entry signal with multiple strategies
    int GetSpikeEntrySignal(const string symbolName) {
        // Strategy 1: Immediate spike following
        int immediateSignal = GetImmediateSpikeSignal(symbolName);
        if(immediateSignal != 0) return immediateSignal;
        
        // Strategy 2: Spike reversal trading
        int reversalSignal = GetSpikeReversalSignal(symbolName);
        if(reversalSignal != 0) return reversalSignal;
        
        // Strategy 3: Spike continuation pattern
        int continuationSignal = GetSpikeContinuationSignal(symbolName);
        if(continuationSignal != 0) return continuationSignal;
        
        return 0; // No signal
    }
    
    // Immediate spike following strategy
    int GetImmediateSpikeSignal(const string symbolName) {
        for(int i = ArraySize(m_spikeHistory) - 1; i >= 0; i--) {
            if(m_spikeHistory[i].symbol != symbolName) continue;
            
            // Check if spike is very recent (within last 5 seconds)
            if(TimeCurrent() - m_spikeHistory[i].timestamp > 5) break;
            
            // High confidence spike signals with size filter
            if(m_spikeHistory[i].confidence >= m_confidenceThreshold &&
               m_spikeHistory[i].spikeSize >= GetMinimumSpikeSize(symbolName)) {
                
                if(m_spikeHistory[i].isBoomSpike) {
                    return 1; // Buy signal after boom spike
                } else {
                    return -1; // Sell signal after crash spike
                }
            }
        }
        return 0;
    }
    
    // Spike reversal strategy (counter-trend)
    int GetSpikeReversalSignal(const string symbolName) {
        for(int i = ArraySize(m_spikeHistory) - 1; i >= 0; i--) {
            if(m_spikeHistory[i].symbol != symbolName) continue;
            
            // Check if spike is recent but not immediate (5-30 seconds ago)
            int timeSinceSpike = (int)(TimeCurrent() - m_spikeHistory[i].timestamp);
            if(timeSinceSpike < 5 || timeSinceSpike > 30) continue;
            
            // Look for large spikes that might reverse
            if(m_spikeHistory[i].confidence >= 0.8 &&
               m_spikeHistory[i].spikeSize >= GetLargeSpikeThreshold(symbolName)) {
                
                // Check if price has started to reverse
                double currentPriceValue = SymbolInfoDouble(symbolName, SYMBOL_BID);
                double spikePrice = m_spikeHistory[i].priceAfterSpike;
                
                if(m_spikeHistory[i].isBoomSpike) {
                    // After boom spike, look for price decline
                    if(currentPriceValue < spikePrice * 0.995) {
                        return -1; // Sell signal (reversal from boom)
                    }
                } else {
                    // After crash spike, look for price recovery
                    if(currentPriceValue > spikePrice * 1.005) {
                        return 1; // Buy signal (reversal from crash)
                    }
                }
            }
        }
        return 0;
    }
    
    // Spike continuation pattern strategy
    int GetSpikeContinuationSignal(const string symbolName) {
        // Look for multiple spikes in same direction
        int recentBoomSpikes = 0, recentCrashSpikes = 0;
        
        for(int i = ArraySize(m_spikeHistory) - 1; i >= 0; i--) {
            if(m_spikeHistory[i].symbol != symbolName) continue;
            
            // Check spikes within last 60 seconds
            if(TimeCurrent() - m_spikeHistory[i].timestamp > 60) break;
            
            if(m_spikeHistory[i].confidence >= 0.6) {
                if(m_spikeHistory[i].isBoomSpike) {
                    recentBoomSpikes++;
                } else {
                    recentCrashSpikes++;
                }
            }
        }
        
        // Signal continuation if we have multiple spikes in same direction
        if(recentBoomSpikes >= 2 && recentCrashSpikes == 0) {
            return 1; // Continue boom trend
        } else if(recentCrashSpikes >= 2 && recentBoomSpikes == 0) {
            return -1; // Continue crash trend
        }
        
        return 0;
    }
    
    // Enhanced spike-based exit signal with multiple exit strategies
    bool GetSpikeExitSignal(const string symbolParam, bool isLongPosition, double entryPrice, double currentPriceParam) {
        // Strategy 1: Opposite spike exit
        if(GetOppositeSpikeExit(symbolParam, isLongPosition)) return true;
        
        // Strategy 2: Profit target based on spike size
        if(GetSpikeProfitTargetExit(symbolParam, isLongPosition, entryPrice, currentPriceParam)) return true;
        
        // Strategy 3: Time-based exit after spike
        if(GetTimeBasedSpikeExit(symbolParam, isLongPosition)) return true;
        
        // Strategy 4: Volatility-based exit
        if(GetVolatilityBasedExit(symbolParam, isLongPosition, entryPrice, currentPriceParam)) return true;
        
        return false;
    }
    
    // Exit on opposite spike
    bool GetOppositeSpikeExit(const string symbolName, bool isLongPosition) {
        for(int i = ArraySize(m_spikeHistory) - 1; i >= 0; i--) {
            if(m_spikeHistory[i].symbol != symbolName) continue;
            
            // Check if spike is very recent (within last 3 seconds)
            if(TimeCurrent() - m_spikeHistory[i].timestamp > 3) break;
            
            // Exit on opposite spike with high confidence
            if(m_spikeHistory[i].confidence >= m_confidenceThreshold) {
                if(isLongPosition && !m_spikeHistory[i].isBoomSpike) {
                    return true; // Exit long on crash spike
                } else if(!isLongPosition && m_spikeHistory[i].isBoomSpike) {
                    return true; // Exit short on boom spike
                }
            }
        }
        return false;
    }
    
    // Exit based on spike-derived profit targets
    bool GetSpikeProfitTargetExit(const string symbolParam, bool isLongPosition, double entryPrice, double currentPriceParam) {
        // Find the spike that triggered entry
        SpikeEvent entrySpike;
        bool foundEntrySpike = false;
        
        for(int i = ArraySize(m_spikeHistory) - 1; i >= 0; i--) {
            if(m_spikeHistory[i].symbol != symbolParam) continue;
            
            // Look for spike within reasonable time of entry
            if(TimeCurrent() - m_spikeHistory[i].timestamp > 120) break;
            
            if(m_spikeHistory[i].wasTraded) {
                entrySpike = m_spikeHistory[i];
                foundEntrySpike = true;
                break;
            }
        }
        
        if(!foundEntrySpike) return false;
        
        // Calculate profit target based on spike size
        double profitTarget = entrySpike.spikeSize * 1.5; // 150% of spike size
        double currentProfit = 0;
        
        if(isLongPosition) {
            currentProfit = currentPriceParam - entryPrice;
        } else {
            currentProfit = entryPrice - currentPriceParam;
        }
        
        return (currentProfit >= profitTarget);
    }
    
    // Time-based exit after spike
    bool GetTimeBasedSpikeExit(const string symbolName, bool isLongPosition) {
        // Exit if no new spikes in same direction for extended period
        datetime lastRelevantSpike = 0;
        
        for(int i = ArraySize(m_spikeHistory) - 1; i >= 0; i--) {
            if(m_spikeHistory[i].symbol != symbolName) continue;
            
            bool isRelevantSpike = (isLongPosition && m_spikeHistory[i].isBoomSpike) ||
                                  (!isLongPosition && !m_spikeHistory[i].isBoomSpike);
            
            if(isRelevantSpike && m_spikeHistory[i].confidence >= 0.6) {
                lastRelevantSpike = m_spikeHistory[i].timestamp;
                break;
            }
        }
        
        // Exit if no relevant spike for 2 minutes
        return (lastRelevantSpike > 0 && TimeCurrent() - lastRelevantSpike > 120);
    }
    
    // Volatility-based exit
    bool GetVolatilityBasedExit(const string symbolParam, bool isLongPosition, double entryPrice, double currentPriceParam) {
        // Calculate recent volatility
        MqlTick ticks[];
        int tickCount = CopyTicks(symbolParam, ticks, COPY_TICKS_ALL, 0, 20);
        
        if(tickCount < 10) return false;
        
        double volatility = CalculateTickVolatility(ticks, tickCount);
        double priceMove = MathAbs(currentPriceParam - entryPrice);
        
        // Exit if price movement exceeds 3x recent volatility
        return (priceMove > volatility * 3.0);
    }
    
    // Enhanced crash/boom specific risk management
    void GetCrashBoomRiskParams(const string symbolParam, double &stopLoss, double &takeProfit,
                               double entryPrice, bool isBuy, double &positionSizeMultiplier) {
        int perfIndex = GetPerformanceIndex(symbolParam);
        double avgSpikeSize = 10.0; // Default
        double recentVolatility = GetRecentVolatility(symbolParam);
        
        if(perfIndex != -1) {
            avgSpikeSize = m_performance[perfIndex].avgSpikeSize;
        }
        
        // Adaptive risk parameters based on recent performance and volatility
        double riskMultiplier = CalculateRiskMultiplier(symbolParam);
        double volatilityAdjustment = MathMax(0.5, MathMin(2.0, recentVolatility / 10.0));
        
        // Dynamic stop loss based on spike characteristics
        double stopDistance = avgSpikeSize * 0.6 * volatilityAdjustment; // Adaptive stop
        
        // Dynamic take profit with risk-reward optimization
        double profitDistance = avgSpikeSize * 1.8 * riskMultiplier; // Adaptive target
        
        // Position size adjustment based on spike reliability
        positionSizeMultiplier = CalculatePositionSizeMultiplier(symbolParam);
        
        if(isBuy) {
            stopLoss = entryPrice - stopDistance;
            takeProfit = entryPrice + profitDistance;
        } else {
            stopLoss = entryPrice + stopDistance;
            takeProfit = entryPrice - profitDistance;
        }
        
        // Ensure minimum risk-reward ratio
        double riskRewardRatio = profitDistance / stopDistance;
        if(riskRewardRatio < 1.5) {
            // Adjust take profit to maintain minimum 1.5:1 ratio
            profitDistance = stopDistance * 1.5;
            if(isBuy) {
                takeProfit = entryPrice + profitDistance;
            } else {
                takeProfit = entryPrice - profitDistance;
            }
        }
    }
    
    // Calculate risk multiplier based on recent performance
    double CalculateRiskMultiplier(const string symbolName) {
        int perfIndex = GetPerformanceIndex(symbolName);
        if(perfIndex == -1) return 1.0;
        
        double winRate = m_performance[perfIndex].winRate;
        double avgReturn = m_performance[perfIndex].avgReturn;
        
        // Increase risk for high-performing symbols
        if(winRate > 0.6 && avgReturn > 0.5) {
            return 1.3;
        } else if(winRate < 0.4 || avgReturn < 0.0) {
            return 0.7; // Reduce risk for poor performers
        }
        
        return 1.0;
    }
    
    // Calculate position size multiplier based on spike reliability
    double CalculatePositionSizeMultiplier(const string symbolName) {
        int perfIndex = GetPerformanceIndex(symbolName);
        if(perfIndex == -1) return 1.0;
        
        double confidence = GetAverageRecentConfidence(symbolName);
        int recentSpikes = CountRecentSpikes(symbolName, 3600); // Last hour
        
        // Adjust position size based on spike frequency and confidence
        double multiplier = 1.0;
        
        if(confidence > 0.8 && recentSpikes >= 3) {
            multiplier = 1.2; // Increase size for high-confidence, active periods
        } else if(confidence < 0.6 || recentSpikes < 1) {
            multiplier = 0.8; // Reduce size for low-confidence or quiet periods
        }
        
        return MathMax(0.5, MathMin(1.5, multiplier));
    }
    
    // Get recent volatility for the symbol
    double GetRecentVolatility(const string symbolName) {
        MqlTick ticks[];
        int tickCount = CopyTicks(symbolName, ticks, COPY_TICKS_ALL, 0, 50);
        
        if(tickCount < 10) return 10.0; // Default volatility
        
        return CalculateTickVolatility(ticks, tickCount) * 1000; // Convert to points
    }
    
    // Get average confidence of recent spikes
    double GetAverageRecentConfidence(const string symbolName) {
        double totalConfidence = 0;
        int count = 0;
        
        for(int i = ArraySize(m_spikeHistory) - 1; i >= 0; i--) {
            if(m_spikeHistory[i].symbol != symbolName) continue;
            
            // Check spikes within last 30 minutes
            if(TimeCurrent() - m_spikeHistory[i].timestamp > 1800) break;
            
            totalConfidence += m_spikeHistory[i].confidence;
            count++;
            
            if(count >= 10) break; // Limit to last 10 spikes
        }
        
        return (count > 0) ? totalConfidence / count : 0.5;
    }
    
    // Count recent spikes within time period
    int CountRecentSpikes(const string symbolName, int timePeriodSeconds) {
        int count = 0;
        datetime cutoffTime = TimeCurrent() - timePeriodSeconds;
        
        for(int i = ArraySize(m_spikeHistory) - 1; i >= 0; i--) {
            if(m_spikeHistory[i].symbol != symbolName) continue;
            
            if(m_spikeHistory[i].timestamp < cutoffTime) break;
            
            if(m_spikeHistory[i].confidence >= 0.6) {
                count++;
            }
        }
        
        return count;
    }
    
    // Update performance after trade
    void UpdateTradePerformance(const string symbolName, double tradeReturn, bool wasSuccessful) {
        int perfIndex = GetPerformanceIndex(symbolName);
        if(perfIndex == -1) return;
        
        if(wasSuccessful) {
            m_performance[perfIndex].successfulTrades++;
        }
        
        // Update average return
        double totalTradesValue = m_performance[perfIndex].successfulTrades +
                           (m_performance[perfIndex].totalSpikesDetected - m_performance[perfIndex].successfulTrades);
        
        if(totalTradesValue > 0) {
            m_performance[perfIndex].avgReturn = 
                (m_performance[perfIndex].avgReturn * (totalTradesValue - 1) + tradeReturn) / totalTradesValue;
            
            m_performance[perfIndex].winRate = 
                (double)m_performance[perfIndex].successfulTrades / totalTradesValue;
        }
    }
    
    // Get performance data
    CrashBoomPerformance GetPerformanceData(const string symbolName) {
        int perfIndex = GetPerformanceIndex(symbolName);
        if(perfIndex != -1) {
            return m_performance[perfIndex];
        }
        
        CrashBoomPerformance emptyPerf;
        emptyPerf.symbol = symbolName;
        return emptyPerf;
    }
    
private:
    // Helper methods
    int GetConfigIndex(const string symbolName) {
        for(int i = 0; i < ArraySize(m_configs); i++) {
            if(m_configs[i].symbol == symbolName) {
                return i;
            }
        }
        return -1;
    }
    
    int GetPerformanceIndex(const string symbolName) {
        for(int i = 0; i < ArraySize(m_performance); i++) {
            if(m_performance[i].symbol == symbolName) {
                return i;
            }
        }
        return -1;
    }
    
    void AddSpikeToHistory(const SpikeEvent &spike) {
        int size = ArraySize(m_spikeHistory);
        
        if(size >= m_maxSpikeHistory) {
            // Shift array left
            for(int i = 0; i < size - 1; i++) {
                m_spikeHistory[i] = m_spikeHistory[i + 1];
            }
            m_spikeHistory[size - 1] = spike;
        } else {
            ArrayResize(m_spikeHistory, size + 1);
            m_spikeHistory[size] = spike;
        }
    }
    
    void UpdateSpikePerformance(const string symbolName, const SpikeEvent &spike) {
        int perfIndex = GetPerformanceIndex(symbolName);
        if(perfIndex == -1) return;
        
        m_performance[perfIndex].totalSpikesDetected++;
        m_performance[perfIndex].lastSpikeTime = spike.timestamp;
        
        // Update average spike size
        double totalSpikes = m_performance[perfIndex].totalSpikesDetected;
        m_performance[perfIndex].avgSpikeSize = 
            (m_performance[perfIndex].avgSpikeSize * (totalSpikes - 1) + spike.spikeSize) / totalSpikes;
        
        // Update best spike size
        if(spike.spikeSize > m_performance[perfIndex].bestSpikeSize) {
            m_performance[perfIndex].bestSpikeSize = spike.spikeSize;
        }
        
        // Update average time to spike
        if(spike.ticksToSpike > 0) {
            m_performance[perfIndex].avgTimeToSpike = 
                (m_performance[perfIndex].avgTimeToSpike * (totalSpikes - 1) + spike.ticksToSpike) / totalSpikes;
        }
    }
    
    // Get minimum spike size for signal generation
    double GetMinimumSpikeSize(const string symbolName) {
        int perfIndex = GetPerformanceIndex(symbolName);
        if(perfIndex != -1 && m_performance[perfIndex].avgSpikeSize > 0) {
            return m_performance[perfIndex].avgSpikeSize * 0.7; // 70% of average
        }
        return m_minSpikeSize;
    }
    
    // Get large spike threshold for reversal signals
    double GetLargeSpikeThreshold(const string symbolName) {
        int perfIndex = GetPerformanceIndex(symbolName);
        if(perfIndex != -1 && m_performance[perfIndex].avgSpikeSize > 0) {
            return m_performance[perfIndex].avgSpikeSize * 1.5; // 150% of average
        }
        return m_minSpikeSize * 2.0;
    }
    
    // Classify spike type based on size and characteristics
    ENUM_SPIKE_TYPE ClassifySpikeType(const SpikeEvent &spike) {
        double spikeSize = spike.spikeSize;
        
        if(spikeSize < 5.0) {
            return SPIKE_TYPE_MICRO;
        } else if(spikeSize < 20.0) {
            return SPIKE_TYPE_NORMAL;
        } else if(spikeSize < 50.0) {
            return SPIKE_TYPE_LARGE;
        } else {
            return SPIKE_TYPE_EXTREME;
        }
    }
    
    // Check if symbol is a crash/boom index
    bool IsCrashBoomSymbol(const string symbolName) {
        string upperSymbol = symbolName;
        StringToUpper(upperSymbol);
        
        return (StringFind(upperSymbol, "CRASH") >= 0 ||
                StringFind(upperSymbol, "BOOM") >= 0);
    }
    
    // Get symbol-specific configuration
    void OptimizeConfigForSymbol(const string symbolName, SpikeDetectionConfig &config) {
        if(!IsCrashBoomSymbol(symbolName)) return;
        
        // Extract crash/boom number (e.g., "Crash 500" -> 500)
        string upperSymbol = symbolName;
        StringToUpper(upperSymbol);
        
        int number = 0;
        if(StringFind(upperSymbol, "CRASH") >= 0) {
            // Extract number after "CRASH"
            int pos = StringFind(upperSymbol, "CRASH") + 5;
            string numStr = StringSubstr(upperSymbol, pos);
            StringTrimLeft(numStr);
            StringTrimRight(numStr);
            number = (int)StringToInteger(numStr);
        } else if(StringFind(upperSymbol, "BOOM") >= 0) {
            // Extract number after "BOOM"
            int pos = StringFind(upperSymbol, "BOOM") + 4;
            string numStr = StringSubstr(upperSymbol, pos);
            StringTrimLeft(numStr);
            StringTrimRight(numStr);
            number = (int)StringToInteger(numStr);
        }
        
        // Adjust parameters based on crash/boom number
        if(number > 0) {
            // Higher numbers = more volatile = higher thresholds
            config.spikeThreshold = 5.0 + (number / 100.0);
            config.volumeMultiplier = 1.5 + (number / 1000.0);
            config.cooldownPeriod = MathMax(10, 60 - (number / 20));
        }
    }
};

#endif // __CRASH_BOOM_SPIKE_DETECTOR_MQH__