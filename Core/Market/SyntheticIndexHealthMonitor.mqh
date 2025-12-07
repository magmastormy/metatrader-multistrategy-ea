//+------------------------------------------------------------------+
//| Symbol Health Monitoring Module                                   |
//| Comprehensive symbol health monitoring and data quality checking  |
//| Implements requirements 8.3, 8.4, 8.5 for symbol health         |
//+------------------------------------------------------------------+
#ifndef __SYNTHETIC_INDEX_HEALTH_MONITOR_MQH__
#define __SYNTHETIC_INDEX_HEALTH_MONITOR_MQH__

#include "../Utilities/Utilities.mqh"
#include "../Utils/ErrorHandling.mqh"

// Forward declarations
class CEnhancedErrorHandler;
class CUtilities;
class CHedgingProtection;
class CMarketAnalysis;
class CModeManager;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CStrategyManager;
class CTradeManager;
class CPerformanceAnalytics;
class CAIStrategyOrchestrator;

// Symbol health status enumeration
enum ENUM_SYMBOL_HEALTH {
    SYMBOL_HEALTH_EXCELLENT,
    SYMBOL_HEALTH_GOOD,
    SYMBOL_HEALTH_WARNING,
    SYMBOL_HEALTH_CRITICAL,
    SYMBOL_HEALTH_OFFLINE,
    SYMBOL_HEALTH_DATA_UNAVAILABLE
};

// Data quality levels with detailed thresholds
enum ENUM_DATA_QUALITY {
    DATA_QUALITY_EXCELLENT,    // 95-100% data quality
    DATA_QUALITY_GOOD,         // 85-94% data quality
    DATA_QUALITY_FAIR,         // 70-84% data quality
    DATA_QUALITY_POOR,         // 50-69% data quality
    DATA_QUALITY_CRITICAL,     // <50% data quality
    DATA_QUALITY_UNAVAILABLE   // No data available
};

// Data quality thresholds
struct DataQualityThresholds {
    double minExcellent;  // Minimum score for EXCELLENT
    double minGood;      // Minimum score for GOOD
    double minFair;      // Minimum score for FAIR
    double minPoor;      // Minimum score for POOR
    
    DataQualityThresholds() : minExcellent(95.0), minGood(85.0), minFair(70.0), minPoor(50.0) {}
};

// Symbol exclusion reasons
enum ENUM_EXCLUSION_REASON {
    EXCLUSION_NONE,
    EXCLUSION_WIDE_SPREADS,
    EXCLUSION_POOR_DATA_QUALITY,
    EXCLUSION_SPEC_CHANGES,
    EXCLUSION_CONNECTION_ISSUES,
    EXCLUSION_MANUAL
};

// Enhanced spread monitoring data (Requirement 8.4)
struct SpreadMonitorData {
    string symbol;
    double currentSpread;
    double avgSpread;
    double maxSpread;
    double minSpread;
    double normalSpread;        // Historical normal spread
    double spreadThreshold;     // Warning threshold
    double criticalThreshold;   // Critical threshold
    datetime lastUpdate;
    bool isAbnormal;
    bool isWideSpread;         // Significantly wide spread
    int consecutiveWideCount;   // Consecutive wide spread count
    double spreadRatio;        // Current/Normal ratio
};

// Enhanced data quality monitoring with comprehensive metrics
struct DataQualityMetrics {
    string symbol;              // Symbol name
    ENUM_DATA_QUALITY qualityLevel; // Quality level enum
    double dataAvailability;    // % of expected data points available (0-100)
    int missingTickCount;       // Missing ticks in last period
    int gapCount;              // Price gaps detected (unusual price jumps)
    double priceConsistency;    // Price consistency score (0-1)
    double spreadStability;     // Spread stability score (0-1)
    double volatilityScore;     // Volatility consistency (0-1)
    datetime lastDataTime;      // Last valid data timestamp
    bool hasRecentData;         // Data received in last minute
    int consecutiveFailures;    // Consecutive data failures
    string qualityIssues;       // Description of quality issues
    double qualityScore;        // Overall quality score (0-100)
    datetime lastUpdate;        // Last metrics update time
    int analyzedTicks;          // Number of ticks analyzed
    int validTicks;            // Number of valid ticks
    
    // Detailed metrics
    struct MarketMetrics {
        double avgSpread;       // Average spread
        double maxSpread;       // Maximum spread
        double spreadDeviation; // Standard deviation of spreads
        double avgVolume;       // Average volume
        double volumeDeviation; // Standard deviation of volumes
    } marketMetrics;
    
    // Enhanced constructor with comprehensive initialization
    DataQualityMetrics() : 
        symbol(""),
        qualityLevel(DATA_QUALITY_GOOD),
        dataAvailability(100.0),
        missingTickCount(0),
        gapCount(0),
        priceConsistency(1.0),
        spreadStability(1.0),
        volatilityScore(1.0),
        lastDataTime(TimeCurrent()),
        hasRecentData(true),
        consecutiveFailures(0),
        qualityIssues(""),
        qualityScore(100.0),
        lastUpdate(TimeCurrent()),
        analyzedTicks(0),
        validTicks(0)
    {
        // Initialize market metrics
        marketMetrics.avgSpread = 0.0;
        marketMetrics.maxSpread = 0.0;
        marketMetrics.spreadDeviation = 0.0;
        marketMetrics.avgVolume = 0.0;
        marketMetrics.volumeDeviation = 0.0;
    }
    
    // Note: Rely on default struct copy/assignment semantics in MQL5
};

// Symbol specification monitoring (Requirement 8.5)
struct SymbolSpecification {
    string symbol;
    double tickSize;
    double tickValue;
    double contractSize;
    double minLot;
    double maxLot;
    double lotStep;
    int digits;
    double marginRequired;
    datetime lastSpecCheck;
    bool hasChanged;
    string changeDescription;
};

// Behavior anomaly data
struct BehaviorAnomalyData {
    string symbol;
    datetime detectedAt;
    string anomalyType;         // "spread", "volatility", "frequency", "correlation"
    double severity;            // 0-1 scale
    string description;
    bool isActive;
    datetime resolvedAt;
};

// Synthetic index correlation data
struct SyntheticCorrelationData {
    string symbol1;
    string symbol2;
    double expectedCorrelation;
    double currentCorrelation;
    double correlationChange;
    datetime lastCalculated;
    bool hasSignificantChange;
};

// Health monitoring configuration
struct HealthMonitorConfig {
    string symbol;
    double spreadWarningThreshold;
    double spreadCriticalThreshold;
    double volatilityWarningThreshold;
    double volatilityCriticalThreshold;
    int tickFrequencyThreshold;
    double correlationChangeThreshold;
    bool enableAutoTradingPause;
};

// Symbol exclusion tracking
struct SymbolExclusionStatus {
    string symbol;
    bool isExcluded;
    ENUM_EXCLUSION_REASON exclusionReason;
    datetime excludedAt;
    datetime excludedUntil;     // Auto-resume time
    string exclusionDetails;
    int exclusionCount;         // Total exclusions
    bool autoResumeEnabled;
};

// Comprehensive symbol health status
struct SymbolHealthStatus {
    string symbol;
    ENUM_SYMBOL_HEALTH healthLevel;
    double healthScore;         // 0-100
    string statusMessage;
    datetime lastHealthCheck;
    bool isTradingPaused;
    bool isExcluded;
    int activeAnomalies;
    
    // Spread metrics
    double avgSpread;
    double currentSpread;
    bool hasWideSpread;
    
    // Data quality metrics
    ENUM_DATA_QUALITY dataQuality;
    double dataAvailability;
    bool hasRecentData;
    
    // Volatility metrics
    double currentVolatility;
    int ticksPerMinute;
    
    // Specification status
    bool hasSpecChanges;
    datetime lastSpecUpdate;
};

class CSyntheticIndexHealthMonitor : public CEnhancedErrorHandler
{
private:
    // Apply updated symbol parameters (placeholder integration point)
    void UpdateSymbolParameters(const string symbol, const SymbolSpecification &spec) {
        // Integrate with broker/symbol settings manager if available
        // For now, we just log that parameters were observed
        Print("Parameters observed for " + symbol);
    }

    // Resume trading for a symbol (integration point with strategy manager)
    void ResumeSymbolTrading(const string symbol) {
        int healthIndex = GetHealthStatusIndex(symbol);
        if(healthIndex == -1) return;
        m_healthStatus[healthIndex].isExcluded = false;
        m_healthStatus[healthIndex].isTradingPaused = false;
        Print("Symbol resumed: " + symbol);
    }
    CUtilities* m_utilities;
    CEnhancedErrorHandler* m_errorHandler;
    
    // Monitoring arrays
    HealthMonitorConfig m_configs[];
    SpreadMonitorData m_spreadData[];
    BehaviorAnomalyData m_anomalies[];
    SyntheticCorrelationData m_correlations[];
    SymbolHealthStatus m_healthStatus[];
    
    // New monitoring arrays for comprehensive health checking
    DataQualityMetrics m_dataQuality[];
    SymbolSpecification m_symbolSpecs[];
    SymbolExclusionStatus m_exclusions[];
    
    // Historical data for analysis
    double m_spreadHistory[][100];    // [symbol_index][history_points]
    double m_volatilityHistory[][100];
    int m_tickCountHistory[][60];     // Ticks per minute for last hour
    
    // Monitoring parameters
    int m_spreadHistorySize;
    int m_volatilityHistorySize;
    int m_tickHistorySize;
    double m_globalHealthThreshold;
    bool m_emergencyTradingPause;
    
    // Monitor symbol data quality (Requirement 8.3)
    void MonitorDataQuality(const string symbol) {
        int qualityIndex = GetDataQualityIndex(symbol);
        if(qualityIndex == -1) return;
        
        // Use direct array access (avoid pointers)
        datetime currentTime = TimeCurrent();
        
        // Check if symbol data is available
        double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
        
        if(bid <= 0 || ask <= 0 || ask <= bid) {
            // Invalid or unavailable data
            m_dataQuality[qualityIndex].consecutiveFailures++;
            m_dataQuality[qualityIndex].hasRecentData = false;
            m_dataQuality[qualityIndex].qualityLevel = DATA_QUALITY_UNAVAILABLE;
            m_dataQuality[qualityIndex].qualityIssues = "Invalid price data - bid: " + DoubleToString(bid, 5) + 
                                  ", ask: " + DoubleToString(ask, 5);
            
            // Check if symbol should be excluded (Requirement 8.3)
            if(m_dataQuality[qualityIndex].consecutiveFailures >= 5) {
                ExcludeSymbol(symbol, EXCLUSION_POOR_DATA_QUALITY, 
                            "Consecutive data failures: " + IntegerToString(m_dataQuality[qualityIndex].consecutiveFailures));
            }
            return;
        }
        
        // Data is available - reset failure count
        m_dataQuality[qualityIndex].consecutiveFailures = 0;
        m_dataQuality[qualityIndex].hasRecentData = true;
        m_dataQuality[qualityIndex].lastDataTime = currentTime;
        
        // Check data consistency
        double spread = ask - bid;
        if(spread > ask * 0.1) { // Spread > 10% of price indicates data issue
            m_dataQuality[qualityIndex].qualityLevel = DATA_QUALITY_POOR;
            m_dataQuality[qualityIndex].qualityIssues = "Abnormally wide spread detected: " + DoubleToString(spread, 5);
        } else if(spread <= 0) {
            m_dataQuality[qualityIndex].qualityLevel = DATA_QUALITY_CRITICAL;
            m_dataQuality[qualityIndex].qualityIssues = "Invalid spread: " + DoubleToString(spread, 5);
        } else {
            m_dataQuality[qualityIndex].qualityLevel = DATA_QUALITY_EXCELLENT;
            m_dataQuality[qualityIndex].qualityIssues = "";
        }
        
        // Calculate data availability score
        m_dataQuality[qualityIndex].dataAvailability = CalculateDataAvailability(symbol);
        
        // Update overall quality assessment
        if(m_dataQuality[qualityIndex].dataAvailability < 0.8) {
            m_dataQuality[qualityIndex].qualityLevel = DATA_QUALITY_POOR;
            m_dataQuality[qualityIndex].qualityIssues += " Low data availability: " + 
                                   DoubleToString(m_dataQuality[qualityIndex].dataAvailability * 100, 1) + "%";
        }
    }
    
    // Monitor symbol specifications for changes (Requirement 8.5)
    void MonitorSymbolSpecifications(const string symbol) {
        int specIndex = GetSymbolSpecIndex(symbol);
        if(specIndex == -1) return;
        
        // Use direct array access
        SymbolSpecification currentSpec;
        
        // Get current symbol specifications
        currentSpec.symbol = symbol;
        currentSpec.tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
        currentSpec.tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
        currentSpec.contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
        currentSpec.minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
        currentSpec.maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
        currentSpec.lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
        currentSpec.digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
        currentSpec.marginRequired = SymbolInfoDouble(symbol, SYMBOL_MARGIN_INITIAL);
        currentSpec.lastSpecCheck = TimeCurrent();
        
        // Check for changes if this is not the first check
        if(m_symbolSpecs[specIndex].lastSpecCheck > 0) {
            bool hasChanges = false;
            string changeDetails = "";
            
            if(MathAbs(m_symbolSpecs[specIndex].tickSize - currentSpec.tickSize) > 0.0001) {
                hasChanges = true;
                changeDetails += "TickSize: " + DoubleToString(m_symbolSpecs[specIndex].tickSize, 5) + 
                               " -> " + DoubleToString(currentSpec.tickSize, 5) + "; ";
            }
            
            if(MathAbs(m_symbolSpecs[specIndex].minLot - currentSpec.minLot) > 0.001) {
                hasChanges = true;
                changeDetails += "MinLot: " + DoubleToString(m_symbolSpecs[specIndex].minLot, 3) + 
                               " -> " + DoubleToString(currentSpec.minLot, 3) + "; ";
            }
            
            if(MathAbs(m_symbolSpecs[specIndex].maxLot - currentSpec.maxLot) > 0.001) {
                hasChanges = true;
                changeDetails += "MaxLot: " + DoubleToString(m_symbolSpecs[specIndex].maxLot, 3) + 
                               " -> " + DoubleToString(currentSpec.maxLot, 3) + "; ";
            }
            
            if(m_symbolSpecs[specIndex].digits != currentSpec.digits) {
                hasChanges = true;
                changeDetails += "Digits: " + IntegerToString(m_symbolSpecs[specIndex].digits) + 
                               " -> " + IntegerToString(currentSpec.digits) + "; ";
            }
            
            if(hasChanges) {
                // Log specification changes without storing previous spec
                m_symbolSpecs[specIndex].hasChanged = true;
                m_symbolSpecs[specIndex].changeDescription = changeDetails;
                
                Print("Symbol specification changed for " + symbol + ": " + changeDetails);
                
                // Update parameters automatically (Requirement 8.5)
                UpdateSymbolParameters(symbol, currentSpec);
                
                // Create anomaly record
                CreateBehaviorAnomaly(symbol, "specification", 0.6, 
                    "Symbol specification changed: " + changeDetails);
            }
        }
        
        // Update stored specification
        m_symbolSpecs[specIndex] = currentSpec;
    }
    
    // Monitor spread conditions and exclude symbols with wide spreads (Requirement 8.4)
    void MonitorSpreadConditions(const string symbol) {
        int spreadIndex = GetSpreadDataIndex(symbol);
        if(spreadIndex == -1) return;
        
        // Use direct array access
        
        double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
        double currentSpread = ask - bid;
        
        m_spreadData[spreadIndex].currentSpread = currentSpread;
        m_spreadData[spreadIndex].lastUpdate = TimeCurrent();
        
        // Calculate spread ratio against normal spread
        if(m_spreadData[spreadIndex].normalSpread > 0) {
            m_spreadData[spreadIndex].spreadRatio = currentSpread / m_spreadData[spreadIndex].normalSpread;
        } else {
            m_spreadData[spreadIndex].spreadRatio = 1.0;
        }
        
        // Check for significantly wide spreads (Requirement 8.4)
        bool isWideSpread = false;
        if(m_spreadData[spreadIndex].spreadRatio > 3.0) { // 3x normal spread
            isWideSpread = true;
            m_spreadData[spreadIndex].consecutiveWideCount++;
        } else if(currentSpread > m_spreadData[spreadIndex].criticalThreshold) {
            isWideSpread = true;
            m_spreadData[spreadIndex].consecutiveWideCount++;
        } else {
            m_spreadData[spreadIndex].consecutiveWideCount = 0;
        }
        
        m_spreadData[spreadIndex].isWideSpread = isWideSpread;
        
        // Exclude symbol if spreads are consistently wide (Requirement 8.4)
        if(m_spreadData[spreadIndex].consecutiveWideCount >= 3) {
            string reason = "Wide spreads detected - Ratio: " + DoubleToString(m_spreadData[spreadIndex].spreadRatio, 2) + 
                          "x normal (" + DoubleToString(currentSpread, 5) + " vs " + 
                          DoubleToString(m_spreadData[spreadIndex].normalSpread, 5) + ")";
            
            ExcludeSymbol(symbol, EXCLUSION_WIDE_SPREADS, reason);
            
            // Reset counter after exclusion
            m_spreadData[spreadIndex].consecutiveWideCount = 0;
        }
        
        // Update spread statistics
        UpdateSpreadHistory(spreadIndex, currentSpread);
        CalculateSpreadStatistics(spreadIndex);
    }
    
    // Calculate spread statistics
    void CalculateSpreadStats(const string symbol) {
        int spreadIndex = GetSpreadDataIndex(symbol);
        if(spreadIndex == -1) return;
        
        double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
        double currentSpread = ask - bid;
        
        m_spreadData[spreadIndex].currentSpread = currentSpread;
        m_spreadData[spreadIndex].lastUpdate = TimeCurrent();
        
        // Update spread history
        UpdateSpreadHistory(spreadIndex, currentSpread);
        
        // Calculate statistics
        double sum = 0, maxSpread = 0, minSpread = 999999;
        int count = 0;
        
        for(int i = 0; i < m_spreadHistorySize; i++) {
            double spread = m_spreadHistory[spreadIndex][i];
            if(spread > 0) {
                sum += spread;
                count++;
                maxSpread = MathMax(maxSpread, spread);
                minSpread = MathMin(minSpread, spread);
            }
        }
        
        if(count > 0) {
            m_spreadData[spreadIndex].avgSpread = sum / count;
            m_spreadData[spreadIndex].maxSpread = maxSpread;
            m_spreadData[spreadIndex].minSpread = minSpread;
            
            // Check for abnormal spread
            m_spreadData[spreadIndex].isAbnormal = (currentSpread > m_spreadData[spreadIndex].avgSpread * 2.0) || 
                              (currentSpread > m_spreadData[spreadIndex].spreadThreshold);
        }
    }
    
    // Monitor tick frequency
    void MonitorTickFrequency(const string symbol) {
        int configIndex = GetConfigIndex(symbol);
        if(configIndex == -1) return;
        
        // Update tick count for current minute
        datetime currentTime = TimeCurrent();
        int currentMinute = (int)(currentTime / 60) % 60;
        
        // Increment tick count (simplified - in real implementation track actual ticks)
        m_tickCountHistory[configIndex][currentMinute]++;
        
        // Calculate average ticks per minute
        int totalTicks = 0;
        for(int i = 0; i < m_tickHistorySize; i++) {
            totalTicks += m_tickCountHistory[configIndex][i];
        }
        
        int avgTicksPerMinute = totalTicks / m_tickHistorySize;
        
        // Check if frequency is below threshold
        if(avgTicksPerMinute < m_configs[configIndex].tickFrequencyThreshold) {
            CreateBehaviorAnomaly(symbol, "frequency", 0.7, 
                "Low tick frequency detected: " + IntegerToString(avgTicksPerMinute) + " ticks/min");
        }
    }
    
    // Monitor volatility patterns (Requirement 9.7)
    void MonitorVolatilityPatterns(const string symbol) {
        int configIndex = GetConfigIndex(symbol);
        if(configIndex == -1) return;
        
        // Calculate current volatility
        double volatility = CalculateVolatility(symbol, 20);
        
        // Update volatility history
        UpdateVolatilityHistory(configIndex, volatility);
        
        // Check for volatility anomalies against historical norms
        double avgVolatility = CalculateAverageVolatility(configIndex);
        double historicalNorm = CalculateHistoricalVolatilityNorm(symbol);
        
        // Use the more reliable baseline (historical norm if available)
        double baseline = (historicalNorm > 0) ? historicalNorm : avgVolatility;
        
        if(baseline > 0) {
            double volatilityRatio = volatility / baseline;
            
            // Check for extreme volatility (Requirement 9.7)
            if(volatilityRatio > 4.0) {
                CreateBehaviorAnomaly(symbol, "volatility", 0.9, 
                    "Extreme volatility spike: " + DoubleToString(volatilityRatio, 2) + 
                    "x historical norm (" + DoubleToString(volatility, 4) + " vs " + 
                    DoubleToString(baseline, 4) + ")");
                    
                // Trigger position size adjustment
                TriggerVolatilityBasedAdjustment(symbol, volatilityRatio);
                
            } else if(volatilityRatio > 2.5) {
                CreateBehaviorAnomaly(symbol, "volatility", 0.7, 
                    "High volatility detected: " + DoubleToString(volatilityRatio, 2) + 
                    "x historical norm");
                    
            } else if(volatilityRatio < 0.2) {
                CreateBehaviorAnomaly(symbol, "volatility", 0.5, 
                    "Abnormally low volatility: " + DoubleToString(volatilityRatio, 2) + 
                    "x historical norm");
            }
            
            // Check for sustained high volatility
            if(IsSustainedHighVolatility(configIndex, baseline)) {
                CreateBehaviorAnomaly(symbol, "volatility", 0.8, 
                    "Sustained high volatility period detected");
                TriggerVolatilityBasedAdjustment(symbol, 2.0);
            }
        }
    }
    
    // Monitor correlation changes (Requirement 9.6)
    void MonitorCorrelationChanges() {
        for(int i = 0; i < ArraySize(m_correlations); i++) {
            double newCorrelation = CalculateCorrelation(m_correlations[i].symbol1, 
                                                        m_correlations[i].symbol2);
            
            double correlationChange = MathAbs(newCorrelation - m_correlations[i].expectedCorrelation);
            
            m_correlations[i].currentCorrelation = newCorrelation;
            m_correlations[i].correlationChange = correlationChange;
            m_correlations[i].lastCalculated = TimeCurrent();
            
            // Check for unexpected correlation changes (Requirement 9.6)
            bool isUnexpectedChange = false;
            double severity = 0.5;
            
            if(correlationChange > 0.5) { // Major correlation shift
                isUnexpectedChange = true;
                severity = 0.9;
            } else if(correlationChange > 0.3) { // Significant change
                isUnexpectedChange = true;
                severity = 0.7;
            } else if(correlationChange > 0.2) { // Moderate change
                isUnexpectedChange = true;
                severity = 0.5;
            }
            
            if(isUnexpectedChange) {
                m_correlations[i].hasSignificantChange = true;
                
                CreateBehaviorAnomaly(m_correlations[i].symbol1, "correlation", severity,
                    "Unexpected correlation change with " + m_correlations[i].symbol2 + 
                    ": " + DoubleToString(correlationChange, 3) + " (was " + 
                    DoubleToString(m_correlations[i].expectedCorrelation, 3) + 
                    ", now " + DoubleToString(newCorrelation, 3) + ")");
                
                // Reduce position limits for both symbols (Requirement 9.6)
                ReducePositionLimits(m_correlations[i].symbol1, correlationChange);
                ReducePositionLimits(m_correlations[i].symbol2, correlationChange);
                
                // If correlation becomes very high unexpectedly, pause trading
                if(newCorrelation > 0.8 && m_correlations[i].expectedCorrelation < 0.5) {
                    PauseTradingForSymbol(m_correlations[i].symbol1, 
                        "Unexpected high correlation with " + m_correlations[i].symbol2);
                    PauseTradingForSymbol(m_correlations[i].symbol2, 
                        "Unexpected high correlation with " + m_correlations[i].symbol1);
                }
            }
        }
    }
    
    // Create behavior anomaly record
    void CreateBehaviorAnomaly(const string symbol, const string anomalyType, 
                              double severity, const string description) {
        // Check if similar anomaly already exists
        for(int i = 0; i < ArraySize(m_anomalies); i++) {
            if(m_anomalies[i].symbol == symbol && 
               m_anomalies[i].anomalyType == anomalyType && 
               m_anomalies[i].isActive) {
                return; // Don't create duplicate
            }
        }
        
        // Create new anomaly
        int size = ArraySize(m_anomalies);
        ArrayResize(m_anomalies, size + 1);
        
        m_anomalies[size].symbol = symbol;
        m_anomalies[size].detectedAt = TimeCurrent();
        m_anomalies[size].anomalyType = anomalyType;
        m_anomalies[size].severity = severity;
        m_anomalies[size].description = description;
        m_anomalies[size].isActive = true;
        m_anomalies[size].resolvedAt = 0;
        
        // Log anomaly
        Print("Anomaly detected on " + symbol + " (" + anomalyType + "): " + description);
        
        // Check if trading should be paused
        CheckTradingPauseConditions(symbol);
    }
    
    // Check if trading should be paused (Requirement 9.4, 9.5)
    void CheckTradingPauseConditions(const string symbol) {
        int configIndex = GetConfigIndex(symbol);
        if(configIndex == -1 || !m_configs[configIndex].enableAutoTradingPause) return;
        
        int spreadIndex = GetSpreadDataIndex(symbol);
        bool shouldPause = false;
        string pauseReason = "";
        
        // Check for abnormal spreads (Requirement 9.4)
        if(spreadIndex != -1 && m_spreadData[spreadIndex].isAbnormal) {
            double spreadRatio = (m_spreadData[spreadIndex].avgSpread > 0.0) ?
                (m_spreadData[spreadIndex].currentSpread / m_spreadData[spreadIndex].avgSpread) : 0.0;
            if(spreadRatio > 3.0) { // Spread is 3x normal
                shouldPause = true;
                pauseReason = "Abnormal spread detected: " + DoubleToString(spreadRatio, 2) + "x normal";
            }
        }
        
        // Check for unusual behavior patterns (Requirement 9.5)
        int criticalAnomalies = 0;
        int behaviorAnomalies = 0;
        for(int i = 0; i < ArraySize(m_anomalies); i++) {
            if(m_anomalies[i].symbol == symbol && m_anomalies[i].isActive) {
                if(m_anomalies[i].severity >= 0.8) {
                    criticalAnomalies++;
                }
                if(m_anomalies[i].anomalyType == "volatility" || 
                   m_anomalies[i].anomalyType == "frequency" ||
                   m_anomalies[i].anomalyType == "correlation") {
                    behaviorAnomalies++;
                }
            }
        }
        
        // Pause if multiple critical anomalies or unusual behavior
        if(criticalAnomalies >= 2 || behaviorAnomalies >= 3) {
            shouldPause = true;
            if(pauseReason == "") {
                pauseReason = "Multiple anomalies detected: " + IntegerToString(criticalAnomalies) + 
                             " critical, " + IntegerToString(behaviorAnomalies) + " behavioral";
            }
        }
        
        // Check for extreme volatility (Requirement 9.7)
        double currentVolatility = GetCurrentVolatility(symbol);
        double avgVolatility = GetAverageVolatility(symbol);
        if(currentVolatility > avgVolatility * 4.0) {
            shouldPause = true;
            if(pauseReason == "") {
                pauseReason = "Extreme volatility: " + DoubleToString(currentVolatility/avgVolatility, 2) + "x normal";
            }
        }
        
        if(shouldPause) {
            PauseTradingForSymbol(symbol, pauseReason);
            TightenRiskLimits(symbol); // Requirement 9.5
        }
    }
    
    // Calculate overall health score
    double CalculateHealthScore(const string symbol) {
        double score = 100.0; // Start with perfect score
        
        // Deduct points for active anomalies
        for(int i = 0; i < ArraySize(m_anomalies); i++) {
            if(m_anomalies[i].symbol == symbol && m_anomalies[i].isActive) {
                score -= (m_anomalies[i].severity * 20.0); // Max 20 points per anomaly
            }
        }
        
        // Deduct points for spread issues
        int spreadIndex = GetSpreadDataIndex(symbol);
        if(spreadIndex != -1 && m_spreadData[spreadIndex].isAbnormal) {
            score -= 15.0;
        }
        
        return MathMax(0.0, score);
    }
    
    // Determine health level from score
    ENUM_SYMBOL_HEALTH DetermineHealthLevel(double healthScore) {
        if(healthScore >= 90.0) return SYMBOL_HEALTH_EXCELLENT;
        if(healthScore >= 75.0) return SYMBOL_HEALTH_GOOD;
        if(healthScore >= 50.0) return SYMBOL_HEALTH_WARNING;
        if(healthScore >= 25.0) return SYMBOL_HEALTH_CRITICAL;
        if(healthScore >= 10.0) return SYMBOL_HEALTH_OFFLINE;
        return SYMBOL_HEALTH_DATA_UNAVAILABLE;
    }
    
public:
    CSyntheticIndexHealthMonitor(CUtilities* utils, CEnhancedErrorHandler* errorHandler) :
        m_utilities(utils),
        m_errorHandler(errorHandler),
        m_spreadHistorySize(100),
        m_volatilityHistorySize(100),
        m_tickHistorySize(60),
        m_globalHealthThreshold(70.0),
        m_emergencyTradingPause(false)
    {
        ArrayResize(m_configs, 0);
        ArrayResize(m_spreadData, 0);
        ArrayResize(m_anomalies, 0);
        ArrayResize(m_correlations, 0);
        ArrayResize(m_healthStatus, 0);
        ArrayResize(m_dataQuality, 0);
        ArrayResize(m_symbolSpecs, 0);
        ArrayResize(m_exclusions, 0);
    }
    
    ~CSyntheticIndexHealthMonitor() {
        ArrayFree(m_configs);
        ArrayFree(m_spreadData);
        ArrayFree(m_anomalies);
        ArrayFree(m_correlations);
        ArrayFree(m_healthStatus);
        ArrayFree(m_dataQuality);
        ArrayFree(m_symbolSpecs);
        ArrayFree(m_exclusions);
    }
    
    // Initialize comprehensive health monitoring for symbol
    bool InitializeHealthMonitoring(const string symbol) {
        if(!SymbolSelect(symbol, true)) {
            if(m_errorHandler != NULL) {
                SErrorContext context;
                context.component = "SymbolHealthMonitor";
                context.operation = "InitializeHealthMonitoring";
                context.symbol = symbol;
                context.errorCode = ERR_INVALID_PARAMETER;
                context.additionalInfo = "Failed to select symbol";
                context.timestamp = TimeCurrent();
                context.severity = ERROR_RECOVERABLE;
                CEnhancedErrorHandler* localErrorHandler = CEnhancedErrorHandler::GetInstance();
                if(CheckPointer(localErrorHandler) != POINTER_INVALID) {
                    CEnhancedErrorHandler::LogError(ERROR_RECOVERABLE, context);
                }
            }
            return false;
        }
        
        // Add configuration
        int size = ArraySize(m_configs);
        ArrayResize(m_configs, size + 1);
        
        m_configs[size].symbol = symbol;
        m_configs[size].spreadWarningThreshold = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE) * 5;
        m_configs[size].spreadCriticalThreshold = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE) * 10;
        m_configs[size].volatilityWarningThreshold = 2.0;
        m_configs[size].volatilityCriticalThreshold = 5.0;
        m_configs[size].tickFrequencyThreshold = 10; // Min 10 ticks per minute
        m_configs[size].correlationChangeThreshold = 0.3;
        m_configs[size].enableAutoTradingPause = true;
        
        // Initialize spread monitoring
        int spreadSize = ArraySize(m_spreadData);
        ArrayResize(m_spreadData, spreadSize + 1);
        
        m_spreadData[spreadSize].symbol = symbol;
        m_spreadData[spreadSize].spreadThreshold = m_configs[size].spreadWarningThreshold;
        m_spreadData[spreadSize].criticalThreshold = m_configs[size].spreadCriticalThreshold;
        m_spreadData[spreadSize].consecutiveWideCount = 0;
        
        // Initialize data quality monitoring (Requirement 8.3)
        int qualitySize = ArraySize(m_dataQuality);
        ArrayResize(m_dataQuality, qualitySize + 1);
        
        // Initialize all members of DataQualityMetrics
        m_dataQuality[qualitySize].symbol = symbol;
        m_dataQuality[qualitySize].qualityLevel = DATA_QUALITY_GOOD;
        m_dataQuality[qualitySize].dataAvailability = 100.0; // 100% available initially
        m_dataQuality[qualitySize].missingTickCount = 0;
        m_dataQuality[qualitySize].gapCount = 0;
        m_dataQuality[qualitySize].priceConsistency = 1.0;
        m_dataQuality[qualitySize].lastDataTime = TimeCurrent();
        m_dataQuality[qualitySize].hasRecentData = true;
        m_dataQuality[qualitySize].consecutiveFailures = 0;
        m_dataQuality[qualitySize].qualityIssues = "";
        
        // Initialize symbol specification monitoring (Requirement 8.5)
        int specSize = ArraySize(m_symbolSpecs);
        ArrayResize(m_symbolSpecs, specSize + 1);
        
        m_symbolSpecs[specSize].symbol = symbol;
        m_symbolSpecs[specSize].hasChanged = false;
        m_symbolSpecs[specSize].lastSpecCheck = 0; // Will be set on first check
        
        // Initialize exclusion tracking
        int exclusionSize = ArraySize(m_exclusions);
        ArrayResize(m_exclusions, exclusionSize + 1);
        
        m_exclusions[exclusionSize].symbol = symbol;
        m_exclusions[exclusionSize].isExcluded = false;
        m_exclusions[exclusionSize].exclusionCount = 0;
        m_exclusions[exclusionSize].autoResumeEnabled = true;
        
        // Initialize health status
        int healthSize = ArraySize(m_healthStatus);
        ArrayResize(m_healthStatus, healthSize + 1);
        
        m_healthStatus[healthSize].symbol = symbol;
        m_healthStatus[healthSize].healthLevel = SYMBOL_HEALTH_GOOD;
        m_healthStatus[healthSize].isTradingPaused = false;
        m_healthStatus[healthSize].isExcluded = false;
        m_healthStatus[healthSize].dataQuality = DATA_QUALITY_GOOD;
        m_healthStatus[healthSize].hasRecentData = true;
        m_healthStatus[healthSize].hasSpecChanges = false;
        
        // Initialize history arrays
        ArrayResize(m_spreadHistory, size + 1);
        ArrayResize(m_volatilityHistory, size + 1);
        ArrayResize(m_tickCountHistory, size + 1);
        
        Print("Initialized comprehensive health monitoring for " + symbol);
        
        return true;
    }
    
    // Perform comprehensive health check (Requirements 8.3, 8.4, 8.5)
    void PerformHealthCheck(const string symbol) {
        // Monitor data quality (Requirement 8.3)
        MonitorDataQuality(symbol);
        
        // Monitor spread conditions (Requirement 8.4)
        MonitorSpreadConditions(symbol);
        
        // Monitor symbol specifications (Requirement 8.5)
        MonitorSymbolSpecifications(symbol);
        
        // Monitor traditional aspects
        CalculateSpreadStats(symbol);
        MonitorTickFrequency(symbol);
        MonitorVolatilityPatterns(symbol);
        
        // Check for automatic trading resume conditions
        CheckAutoResumeConditions(symbol);
        
        // Update overall health status
        UpdateHealthStatus(symbol);
    }
    
    // Perform health check for all monitored symbols
    void PerformGlobalHealthCheck() {
        // Monitor correlation changes across all symbol pairs
        MonitorCorrelationChanges();
        
        // Check each individual symbol
        for(int i = 0; i < ArraySize(m_healthStatus); i++) {
            PerformHealthCheck(m_healthStatus[i].symbol);
        }
        
        // Clean up resolved anomalies
        CleanupResolvedAnomalies();
    }
    
    // Check conditions for automatic trading resume (Requirement 9.4)
    void CheckAutoResumeConditions(const string symbol) {
        int healthIndex = GetHealthStatusIndex(symbol);
        if(healthIndex == -1 || !m_healthStatus[healthIndex].isTradingPaused) return;
        
        bool canResume = true;
        string resumeBlockers = "";
        
        // Check if spreads have normalized (Requirement 9.4)
        if(!AreSpreadsNormalized(symbol)) {
            canResume = false;
            resumeBlockers += "abnormal_spreads ";
        }
        
        // Check if volatility has returned to normal levels
        double currentVol = GetCurrentVolatility(symbol);
        double avgVol = GetAverageVolatility(symbol);
        if(avgVol > 0 && currentVol > avgVol * 3.0) {
            canResume = false;
            resumeBlockers += "high_volatility ";
        }
        
        // Check if critical anomalies have been resolved
        int criticalAnomalies = 0;
        for(int i = 0; i < ArraySize(m_anomalies); i++) {
            if(m_anomalies[i].symbol == symbol && 
               m_anomalies[i].isActive && 
               m_anomalies[i].severity >= 0.8) {
                criticalAnomalies++;
            }
        }
        
        if(criticalAnomalies > 0) {
            canResume = false;
            resumeBlockers += "critical_anomalies(" + IntegerToString(criticalAnomalies) + ") ";
        }
        
        // Check overall health score
        if(m_healthStatus[healthIndex].healthScore < 60.0) {
            canResume = false;
            resumeBlockers += "low_health_score ";
        }
        
        if(canResume) {
            ResumeTradingForSymbol(symbol);
        } else {
            Print("Trading resume blocked for " + symbol + " - Blockers: " + resumeBlockers);
        }
    }
    
    // Update comprehensive health status
    void UpdateHealthStatus(const string symbol) {
        int healthIndex = GetHealthStatusIndex(symbol);
        if(healthIndex == -1) return;
        
        // Direct array access instead of pointer
        // SymbolHealthStatus* status = &m_healthStatus[healthIndex];
        
        // Calculate health score
        double healthScore = CalculateHealthScore(symbol);
        
        // Update basic status
        m_healthStatus[healthIndex].healthScore = healthScore;
        m_healthStatus[healthIndex].healthLevel = DetermineHealthLevel(healthScore);
        m_healthStatus[healthIndex].lastHealthCheck = TimeCurrent();
        
        // Count active anomalies
        int activeAnomalies = 0;
        for(int i = 0; i < ArraySize(m_anomalies); i++) {
            if(m_anomalies[i].symbol == symbol && m_anomalies[i].isActive) {
                activeAnomalies++;
            }
        }
        m_healthStatus[healthIndex].activeAnomalies = activeAnomalies;
        
        // Update spread info
        int spreadIndex = GetSpreadDataIndex(symbol);
        if(spreadIndex != -1) {
            m_healthStatus[healthIndex].avgSpread = m_spreadData[spreadIndex].avgSpread;
            m_healthStatus[healthIndex].currentSpread = m_spreadData[spreadIndex].currentSpread;
            m_healthStatus[healthIndex].hasWideSpread = m_spreadData[spreadIndex].isWideSpread;
        }
        
        // Update data quality info
        int qualityIndex = GetDataQualityIndex(symbol);
        if(qualityIndex != -1) {
            m_healthStatus[healthIndex].dataQuality = m_dataQuality[qualityIndex].qualityLevel;
            m_healthStatus[healthIndex].dataAvailability = m_dataQuality[qualityIndex].dataAvailability;
            m_healthStatus[healthIndex].hasRecentData = m_dataQuality[qualityIndex].hasRecentData;
        }
        
        // Update specification info
        int specIndex = GetSymbolSpecIndex(symbol);
        if(specIndex != -1) {
            m_healthStatus[healthIndex].hasSpecChanges = m_symbolSpecs[specIndex].hasChanged;
            m_healthStatus[healthIndex].lastSpecUpdate = m_symbolSpecs[specIndex].lastSpecCheck;
        }
        
        // Update exclusion status
        int exclusionIndex = GetExclusionIndex(symbol);
        if(exclusionIndex != -1) {
            m_healthStatus[healthIndex].isExcluded = m_exclusions[exclusionIndex].isExcluded;
        }
        
        // Generate status message
        string statusMsg = "";
        switch(m_healthStatus[healthIndex].healthLevel) {
            case SYMBOL_HEALTH_EXCELLENT:
                statusMsg = "Excellent - All systems normal";
                break;
            case SYMBOL_HEALTH_GOOD:
                statusMsg = "Good - Minor issues detected";
                break;
            case SYMBOL_HEALTH_WARNING:
                statusMsg = "Warning - Multiple anomalies detected";
                break;
            case SYMBOL_HEALTH_CRITICAL:
                statusMsg = "Critical - Severe issues detected";
                break;
            case SYMBOL_HEALTH_OFFLINE:
                statusMsg = "Offline - Symbol not responding";
                break;
            case SYMBOL_HEALTH_DATA_UNAVAILABLE:
                statusMsg = "Data Unavailable - No recent data";
                break;
        }
        
        // Add specific issue details
        if(m_healthStatus[healthIndex].isExcluded) {
            statusMsg += " (EXCLUDED)";
        } else {
            if(m_healthStatus[healthIndex].hasWideSpread) statusMsg += " - Wide Spread";
            if(!m_healthStatus[healthIndex].hasRecentData) statusMsg += " - No Data";
            if(m_healthStatus[healthIndex].hasSpecChanges) statusMsg += " - Spec Changed";
        }
        
        m_healthStatus[healthIndex].statusMessage = statusMsg;
    }
    
    // Check if trading should be paused for symbol (Requirements 8.3, 8.4, 8.5)
    bool ShouldPauseTrading(const string symbol) {
        int healthIndex = GetHealthStatusIndex(symbol);
        if(healthIndex == -1) return true; // Pause if symbol not monitored
        
        SymbolHealthStatus status = m_healthStatus[healthIndex];
        
        // Pause if explicitly excluded (Requirements 8.3, 8.4, 8.5)
        if(status.isExcluded) return true;
        
        // Pause if trading is manually paused
        if(status.isTradingPaused) return true;
        
        // Pause if health is critical or data unavailable (Requirement 8.3)
        if(status.healthLevel == SYMBOL_HEALTH_CRITICAL ||
           status.healthLevel == SYMBOL_HEALTH_OFFLINE ||
           status.healthLevel == SYMBOL_HEALTH_DATA_UNAVAILABLE) {
            return true;
        }
        
        // Pause if data quality is poor (Requirement 8.3)
        if(!status.hasRecentData || 
           status.dataQuality == DATA_QUALITY_UNAVAILABLE ||
           status.dataQuality == DATA_QUALITY_CRITICAL) {
            return true;
        }
        
        // Pause if spreads are too wide (Requirement 8.4)
        if(status.hasWideSpread) return true;
        
        return false;
    }
    
    // Pause trading for symbol with reason
    void PauseTradingForSymbol(const string symbol, const string reason = "") {
        int healthIndex = GetHealthStatusIndex(symbol);
        if(healthIndex == -1) return;
        
        m_healthStatus[healthIndex].isTradingPaused = true;
        
        string logMessage = "Trading paused for " + symbol;
        if(reason != "") {
            logMessage += " - Reason: " + reason;
        } else {
            logMessage += " due to health issues";
        }
        
        if(CheckPointer(m_utilities) != POINTER_INVALID) {
            m_utilities.LogWarning("SyntheticIndexHealthMonitor", logMessage);
        }
    }
    
    // Resume trading for symbol
    void ResumeTradingForSymbol(const string symbol) {
        int healthIndex = GetHealthStatusIndex(symbol);
        if(healthIndex == -1) return;
        
        // Check if health is good enough to resume
        if(m_healthStatus[healthIndex].healthScore >= 60.0) {
            m_healthStatus[healthIndex].isTradingPaused = false;
            
            Print("SyntheticHealthMonitor", 
                "Trading resumed for " + symbol + " - health improved");
        }
    }
    
    // Get comprehensive health status for symbol
    SymbolHealthStatus GetHealthStatus(const string symbol) {
        int healthIndex = GetHealthStatusIndex(symbol);
        if(healthIndex != -1) {
            return m_healthStatus[healthIndex];
        }
        
        SymbolHealthStatus emptyStatus;
        emptyStatus.symbol = symbol;
        emptyStatus.healthLevel = SYMBOL_HEALTH_OFFLINE;
        emptyStatus.dataQuality = DATA_QUALITY_UNAVAILABLE;
        return emptyStatus;
    }
    
    // Check if symbol is excluded from trading (Requirements 8.3, 8.4, 8.5)
    bool IsSymbolExcluded(const string symbol) {
        int exclusionIndex = GetExclusionIndex(symbol);
        if(exclusionIndex != -1) {
            return m_exclusions[exclusionIndex].isExcluded;
        }
        return false;
    }
    
    // Get exclusion status for symbol
    SymbolExclusionStatus GetExclusionStatus(const string symbol) {
        int exclusionIndex = GetExclusionIndex(symbol);
        if(exclusionIndex != -1) {
            return m_exclusions[exclusionIndex];
        }
        
        SymbolExclusionStatus emptyStatus;
        emptyStatus.symbol = symbol;
        emptyStatus.isExcluded = false;
        return emptyStatus;
    }
    
    // Get data quality metrics for symbol (Requirement 8.3)
    DataQualityMetrics GetDataQuality(const string symbol) {
        int qualityIndex = GetDataQualityIndex(symbol);
        if(qualityIndex != -1) {
            return m_dataQuality[qualityIndex];
        }
        
        DataQualityMetrics emptyQuality;
        emptyQuality.symbol = symbol;
        emptyQuality.qualityLevel = DATA_QUALITY_UNAVAILABLE;
        return emptyQuality;
    }
    
    // Get symbol specification status (Requirement 8.5)
    SymbolSpecification GetSymbolSpecification(const string symbol) {
        int specIndex = GetSymbolSpecIndex(symbol);
        if(specIndex != -1) {
            return m_symbolSpecs[specIndex];
        }
        
        SymbolSpecification emptySpec;
        emptySpec.symbol = symbol;
        emptySpec.hasChanged = false;
        return emptySpec;
    }
    
    // Check if symbol data is available (Requirement 8.3)
    bool IsSymbolDataAvailable(const string symbol) {
        int qualityIndex = GetDataQualityIndex(symbol);
        if(qualityIndex != -1) {
            return m_dataQuality[qualityIndex].hasRecentData && 
                   m_dataQuality[qualityIndex].qualityLevel != DATA_QUALITY_UNAVAILABLE;
        }
        return false;
    }
    
    // Check if symbol has wide spreads (Requirement 8.4)
    bool HasWideSpread(const string symbol) {
        int spreadIndex = GetSpreadDataIndex(symbol);
        if(spreadIndex != -1) {
            return m_spreadData[spreadIndex].isWideSpread;
        }
        return false;
    }
    
    // Manually exclude symbol from trading
    void ManuallyExcludeSymbol(const string symbol, const string reason = "") {
        string details = (reason != "") ? reason : "Manual exclusion";
        ExcludeSymbol(symbol, EXCLUSION_MANUAL, details);
        
        // Disable auto-resume for manual exclusions
        int exclusionIndex = GetExclusionIndex(symbol);
        if(exclusionIndex != -1) {
            m_exclusions[exclusionIndex].autoResumeEnabled = false;
        }
    }
    
    // Manually resume symbol trading
    void ManuallyResumeSymbol(const string symbol) {
        ResumeSymbolTrading(symbol);
        
        Print("SymbolHealthMonitor", 
            "Symbol manually resumed: " + symbol);
    }
    
    // Get list of all excluded symbols
    void GetExcludedSymbols(string &excludedSymbols[]) {
        ArrayResize(excludedSymbols, 0);
        
        for(int i = 0; i < ArraySize(m_exclusions); i++) {
            if(m_exclusions[i].isExcluded) {
                int size = ArraySize(excludedSymbols);
                ArrayResize(excludedSymbols, size + 1);
                excludedSymbols[size] = m_exclusions[i].symbol;
            }
        }
    }
    
    // Get comprehensive health report for all symbols
    string GetHealthReport() {
        string report = "=== Symbol Health Monitor Report ===\n";
        report += "Generated: " + TimeToString(TimeCurrent()) + "\n\n";
        
        int totalSymbols = ArraySize(m_healthStatus);
        int excludedCount = 0;
        int criticalCount = 0;
        int warningCount = 0;
        
        for(int i = 0; i < totalSymbols; i++) {
            SymbolHealthStatus status = m_healthStatus[i];
            
            if(status.isExcluded) excludedCount++;
            if(status.healthLevel == SYMBOL_HEALTH_CRITICAL) criticalCount++;
            if(status.healthLevel == SYMBOL_HEALTH_WARNING) warningCount++;
            
            report += status.symbol + ": " + EnumToString(status.healthLevel) + 
                     " (Score: " + DoubleToString(status.healthScore, 1) + ")";
            
            if(status.isExcluded) {
                SymbolExclusionStatus exclusion = GetExclusionStatus(status.symbol);
                report += " - EXCLUDED (" + EnumToString(exclusion.exclusionReason) + ")";
            }
            
            if(status.hasWideSpread) report += " - Wide Spread";
            if(!status.hasRecentData) report += " - No Recent Data";
            if(status.hasSpecChanges) report += " - Spec Changes";
            
            report += "\n";
        }
        
        report += "\nSummary:\n";
        report += "Total Symbols: " + IntegerToString(totalSymbols) + "\n";
        report += "Excluded: " + IntegerToString(excludedCount) + "\n";
        report += "Critical: " + IntegerToString(criticalCount) + "\n";
        report += "Warning: " + IntegerToString(warningCount) + "\n";
        
        return report;
    }
    
    // Add correlation monitoring between symbols
    void AddCorrelationMonitoring(const string symbol1, const string symbol2, double expectedCorrelation) {
        int size = ArraySize(m_correlations);
        ArrayResize(m_correlations, size + 1);
        
        m_correlations[size].symbol1 = symbol1;
        m_correlations[size].symbol2 = symbol2;
        m_correlations[size].expectedCorrelation = expectedCorrelation;
        m_correlations[size].currentCorrelation = expectedCorrelation;
        m_correlations[size].correlationChange = 0.0;
        m_correlations[size].hasSignificantChange = false;
    }
    
    // Get active anomalies for symbol
    void GetActiveAnomalies(const string symbol, BehaviorAnomalyData &anomalies[]) {
        ArrayResize(anomalies, 0);
        
        for(int i = 0; i < ArraySize(m_anomalies); i++) {
            if(m_anomalies[i].symbol == symbol && m_anomalies[i].isActive) {
                int size = ArraySize(anomalies);
                ArrayResize(anomalies, size + 1);
                anomalies[size] = m_anomalies[i];
            }
        }
    }
    
private:
    // Exclude symbol from trading (Requirements 8.3, 8.4, 8.5)
    void ExcludeSymbol(const string symbol, ENUM_EXCLUSION_REASON reason, const string details) {
        int exclusionIndex = GetExclusionIndex(symbol);
        if(exclusionIndex == -1) {
            // Add new exclusion
            int size = ArraySize(m_exclusions);
            ArrayResize(m_exclusions, size + 1);
            exclusionIndex = size;
            
            m_exclusions[exclusionIndex].symbol = symbol;
            m_exclusions[exclusionIndex].exclusionCount = 0;
        }
        
        if(!m_exclusions[exclusionIndex].isExcluded) {
            m_exclusions[exclusionIndex].isExcluded = true;
            m_exclusions[exclusionIndex].exclusionReason = reason;
            m_exclusions[exclusionIndex].excludedAt = TimeCurrent();
            m_exclusions[exclusionIndex].exclusionDetails = details;
            m_exclusions[exclusionIndex].exclusionCount++;
            m_exclusions[exclusionIndex].autoResumeEnabled = true;
            
            // Set auto-resume time based on reason
            switch(reason) {
                case EXCLUSION_WIDE_SPREADS:
                    m_exclusions[exclusionIndex].excludedUntil = TimeCurrent() + 300; // 5 minutes
                    break;
                case EXCLUSION_POOR_DATA_QUALITY:
                    m_exclusions[exclusionIndex].excludedUntil = TimeCurrent() + 600; // 10 minutes
                    break;
                case EXCLUSION_SPEC_CHANGES:
                    m_exclusions[exclusionIndex].excludedUntil = TimeCurrent() + 60;  // 1 minute
                    break;
                default:
                    m_exclusions[exclusionIndex].excludedUntil = TimeCurrent() + 300; // 5 minutes
                    break;
            }
            
            // Update health status
            int healthIndex = GetHealthStatusIndex(symbol);
            if(healthIndex != -1) {
                m_healthStatus[healthIndex].isExcluded = true;
            }
        }
    }
    
    
    // Calculate data availability percentage
    double CalculateDataAvailability(const string symbol) {
        // Simplified calculation - in real implementation, track actual tick counts
        double bid = SymbolInfoDouble(symbol, SYMBOL_BID);
        double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
        
        if(bid > 0 && ask > 0 && ask > bid) {
            return 1.0; // 100% availability
        } else {
            return 0.0; // 0% availability
        }
    }
    
    // Check if spreads have normalized
    bool AreSpreadsNormalized(const string symbol) {
        int spreadIndex = GetSpreadDataIndex(symbol);
        if(spreadIndex == -1) return false;
        
        // Check if current spread is within normal range
        return (m_spreadData[spreadIndex].spreadRatio <= 2.0 && 
                m_spreadData[spreadIndex].currentSpread <= m_spreadData[spreadIndex].criticalThreshold);
    }
    
    // Check if data quality is good
    bool IsDataQualityGood(const string symbol) {
        int qualityIndex = GetDataQualityIndex(symbol);
        if(qualityIndex == -1) return false;
        
        return m_dataQuality[qualityIndex].hasRecentData && 
               m_dataQuality[qualityIndex].qualityLevel != DATA_QUALITY_CRITICAL && 
               m_dataQuality[qualityIndex].qualityLevel != DATA_QUALITY_UNAVAILABLE;
    }
    
    // Calculate spread statistics
    void CalculateSpreadStatistics(int spreadIndex) {
        if(spreadIndex < 0 || spreadIndex >= ArraySize(m_spreadData)) return;
        
        double sum = 0, maxSpread = 0, minSpread = 999999;
        int count = 0;
        
        for(int i = 0; i < m_spreadHistorySize; i++) {
            double spread = m_spreadHistory[spreadIndex][i];
            if(spread > 0) {
                sum += spread;
                count++;
                maxSpread = MathMax(maxSpread, spread);
                minSpread = MathMin(minSpread, spread);
            }
        }
        
        if(count > 0) {
            m_spreadData[spreadIndex].avgSpread = sum / count;
            m_spreadData[spreadIndex].maxSpread = maxSpread;
            m_spreadData[spreadIndex].minSpread = minSpread;
            
            // Set normal spread if not set
            if(m_spreadData[spreadIndex].normalSpread <= 0) {
                m_spreadData[spreadIndex].normalSpread = m_spreadData[spreadIndex].avgSpread;
            }
        }
    }
    
    // Helper methods
    int GetConfigIndex(const string symbol) {
        for(int i = 0; i < ArraySize(m_configs); i++) {
            if(m_configs[i].symbol == symbol) {
                return i;
            }
        }
        return -1;
    }
    
    // Get index of data quality entry for symbol, or -1 if not found
    int GetDataQualityIndex(const string symbol) const {
        if(symbol == "") return -1;
        
        for(int i = 0; i < ArraySize(m_dataQuality); i++) {
            if(m_dataQuality[i].symbol == symbol) {
                return i;
            }
        }
        return -1;
    }
    
    int GetSymbolSpecIndex(const string symbol) {
        for(int i = 0; i < ArraySize(m_symbolSpecs); i++) {
            if(m_symbolSpecs[i].symbol == symbol) {
                return i;
            }
        }
        return -1;
    }
    
    int GetExclusionIndex(const string symbol) {
        for(int i = 0; i < ArraySize(m_exclusions); i++) {
            if(m_exclusions[i].symbol == symbol) {
                return i;
            }
        }
        return -1;
    }
    
    int GetSpreadDataIndex(const string symbol) {
        for(int i = 0; i < ArraySize(m_spreadData); i++) {
            if(m_spreadData[i].symbol == symbol) {
                return i;
            }
        }
        return -1;
    }
    
    int GetHealthStatusIndex(const string symbol) {
        for(int i = 0; i < ArraySize(m_healthStatus); i++) {
            if(m_healthStatus[i].symbol == symbol) {
                return i;
            }
        }
        return -1;
    }
    
    void UpdateSpreadHistory(int symbolIndex, double spread) {
        // Shift history left and add new value
        for(int i = 0; i < m_spreadHistorySize - 1; i++) {
            m_spreadHistory[symbolIndex][i] = m_spreadHistory[symbolIndex][i + 1];
        }
        m_spreadHistory[symbolIndex][m_spreadHistorySize - 1] = spread;
    }
    
    void UpdateVolatilityHistory(int symbolIndex, double volatility) {
        // Shift history left and add new value
        for(int i = 0; i < m_volatilityHistorySize - 1; i++) {
            m_volatilityHistory[symbolIndex][i] = m_volatilityHistory[symbolIndex][i + 1];
        }
        m_volatilityHistory[symbolIndex][m_volatilityHistorySize - 1] = volatility;
    }
    
    double CalculateVolatility(const string symbol, int period) {
        // Simplified volatility calculation
        double prices[];
        ArrayResize(prices, period);
        
        for(int i = 0; i < period; i++) {
            prices[i] = SymbolInfoDouble(symbol, SYMBOL_BID);
        }
        
        double mean = 0;
        for(int i = 0; i < period; i++) {
            mean += prices[i];
        }
        mean /= period;
        
        double variance = 0;
        for(int i = 0; i < period; i++) {
            variance += MathPow(prices[i] - mean, 2);
        }
        variance /= period;
        
        return MathSqrt(variance);
    }
    
    double CalculateAverageVolatility(int symbolIndex) {
        double sum = 0;
        int count = 0;
        
        for(int i = 0; i < m_volatilityHistorySize; i++) {
            if(m_volatilityHistory[symbolIndex][i] > 0) {
                sum += m_volatilityHistory[symbolIndex][i];
                count++;
            }
        }
        
        return (count > 0) ? sum / count : 0.0;
    }
    
    double CalculateCorrelation(const string symbol1, const string symbol2) {
        // Get recent price data for both symbols
        double prices1[], prices2[];
        int period = 50; // Use 50 recent prices
        
        ArrayResize(prices1, period);
        ArrayResize(prices2, period);
        
        // Get price data (simplified - in real implementation use proper historical data)
        for(int i = 0; i < period; i++) {
            prices1[i] = SymbolInfoDouble(symbol1, SYMBOL_BID);
            prices2[i] = SymbolInfoDouble(symbol2, SYMBOL_BID);
        }
        
        // Calculate correlation coefficient
        double mean1 = 0, mean2 = 0;
        for(int i = 0; i < period; i++) {
            mean1 += prices1[i];
            mean2 += prices2[i];
        }
        mean1 /= period;
        mean2 /= period;
        
        double numerator = 0, denominator1 = 0, denominator2 = 0;
        for(int i = 0; i < period; i++) {
            double diff1 = prices1[i] - mean1;
            double diff2 = prices2[i] - mean2;
            
            numerator += diff1 * diff2;
            denominator1 += diff1 * diff1;
            denominator2 += diff2 * diff2;
        }
        
        double denominator = MathSqrt(denominator1 * denominator2);
        return (denominator != 0) ? numerator / denominator : 0.0;
    }
    
    // Get current volatility for symbol
    double GetCurrentVolatility(const string symbol) {
        int configIndex = GetConfigIndex(symbol);
        if(configIndex == -1) return 0.0;
        
        int historySize = m_volatilityHistorySize;
        if(historySize > 0) {
            return m_volatilityHistory[configIndex][historySize - 1];
        }
        
        return CalculateVolatility(symbol, 20);
    }
    
    // Get average volatility for symbol
    double GetAverageVolatility(const string symbol) {
        int configIndex = GetConfigIndex(symbol);
        if(configIndex == -1) return 0.0;
        
        return CalculateAverageVolatility(configIndex);
    }
    
    // Tighten risk limits for symbol (Requirement 9.5)
    void TightenRiskLimits(const string symbol) {
        // This method should integrate with the risk management system
        // For now, we'll log the action and set internal flags
        
        int healthIndex = GetHealthStatusIndex(symbol);
        if(healthIndex == -1) return;
        
        // Mark that risk limits should be tightened
        m_healthStatus[healthIndex].statusMessage += " [RISK_TIGHTENED]";
        
        Print("SyntheticHealthMonitor", 
            "Risk limits tightened for " + symbol + " due to unusual behavior");
        
        // In a full implementation, this would call the risk manager
        // to reduce position sizes, increase stop losses, etc.
    }
    
    // Reduce position limits for symbol (Requirement 9.6)
    void ReducePositionLimits(const string symbol, double correlationChange) {
        int healthIndex = GetHealthStatusIndex(symbol);
        if(healthIndex == -1) return;
        
        // Calculate reduction factor based on correlation change
        double reductionFactor = MathMin(0.8, correlationChange * 2.0); // Max 80% reduction
        
        // Mark that position limits should be reduced
        m_healthStatus[healthIndex].statusMessage += " [LIMITS_REDUCED:" + 
            DoubleToString(reductionFactor * 100, 0) + "%]";
        
        Print("SyntheticHealthMonitor", 
            "Position limits reduced by " + DoubleToString(reductionFactor * 100, 0) + 
            "% for " + symbol + " due to correlation change: " + 
            DoubleToString(correlationChange, 3));
        
        // In a full implementation, this would integrate with position sizing
        // to reduce maximum position sizes for this symbol
    }
    
public:
    // Get risk adjustment factor for symbol (for integration with position sizing)
    double GetRiskAdjustmentFactor(const string symbol) {
        int healthIndex = GetHealthStatusIndex(symbol);
        if(healthIndex == -1) return 1.0;
        
        double adjustmentFactor = 1.0;
        
        // Reduce risk based on health score
        double healthScore = m_healthStatus[healthIndex].healthScore;
        if(healthScore < 50.0) {
            adjustmentFactor *= 0.5; // 50% reduction for poor health
        } else if(healthScore < 75.0) {
            adjustmentFactor *= 0.75; // 25% reduction for warning health
        }
        
        // Additional reduction for active anomalies
        int activeAnomalies = m_healthStatus[healthIndex].activeAnomalies;
        if(activeAnomalies > 0) {
            adjustmentFactor *= MathMax(0.2, 1.0 - (activeAnomalies * 0.15));
        }
        
        // Check for volatility-based adjustment (Requirement 9.7)
        double currentVol = GetCurrentVolatility(symbol);
        double avgVol = GetAverageVolatility(symbol);
        if(avgVol > 0 && currentVol > avgVol * 2.0) {
            double volRatio = currentVol / avgVol;
            adjustmentFactor *= MathMax(0.3, 1.0 / volRatio); // Inverse relationship
        }
        
        return MathMax(0.1, adjustmentFactor); // Minimum 10% of normal size
    }
    
    // Check if symbol has abnormal spreads (Requirement 9.4)
    bool HasAbnormalSpreads(const string symbol) {
        int spreadIndex = GetSpreadDataIndex(symbol);
        if(spreadIndex == -1) return false;
        
        return m_spreadData[spreadIndex].isAbnormal;
    }
    
    
    // Get correlation risk level for symbol
    double GetCorrelationRiskLevel(const string symbol) {
        double maxRisk = 0.0;
        
        for(int i = 0; i < ArraySize(m_correlations); i++) {
            if(m_correlations[i].symbol1 == symbol || m_correlations[i].symbol2 == symbol) {
                if(m_correlations[i].hasSignificantChange) {
                    maxRisk = MathMax(maxRisk, m_correlations[i].correlationChange);
                }
            }
        }
        
        return maxRisk;
    }
    
    // Get comprehensive health report for symbol
    string GetHealthReport(const string symbol) {
        SymbolHealthStatus status = GetHealthStatus(symbol);
        string report = "";
        
        report += "=== Synthetic Index Health Report: " + symbol + " ===\n";
        report += "Health Level: " + EnumToString(status.healthLevel) + "\n";
        report += "Health Score: " + DoubleToString(status.healthScore, 1) + "/100\n";
        report += "Trading Status: " + (status.isTradingPaused ? "PAUSED" : "ACTIVE") + "\n";
        report += "Active Anomalies: " + IntegerToString(status.activeAnomalies) + "\n";
        report += "Average Spread: " + DoubleToString(status.avgSpread, 5) + "\n";
        report += "Current Volatility: " + DoubleToString(status.currentVolatility, 4) + "\n";
        report += "Status Message: " + status.statusMessage + "\n";
        
        // Add anomaly details
        BehaviorAnomalyData anomalies[];
        GetActiveAnomalies(symbol, anomalies);
        
        if(ArraySize(anomalies) > 0) {
            report += "\nActive Anomalies:\n";
            for(int i = 0; i < ArraySize(anomalies); i++) {
                report += "- " + anomalies[i].anomalyType + " (Severity: " + 
                         DoubleToString(anomalies[i].severity, 2) + "): " + 
                         anomalies[i].description + "\n";
            }
        }
        
        // Add correlation info
        report += "\nCorrelation Status:\n";
        for(int i = 0; i < ArraySize(m_correlations); i++) {
            if(m_correlations[i].symbol1 == symbol || m_correlations[i].symbol2 == symbol) {
                string otherSymbol = (m_correlations[i].symbol1 == symbol) ? 
                                   m_correlations[i].symbol2 : m_correlations[i].symbol1;
                report += "- vs " + otherSymbol + ": " + 
                         DoubleToString(m_correlations[i].currentCorrelation, 3) + 
                         " (Expected: " + DoubleToString(m_correlations[i].expectedCorrelation, 3) + 
                         ", Change: " + DoubleToString(m_correlations[i].correlationChange, 3) + ")\n";
            }
        }
        
        return report;
    }
    
    // Check if symbol is safe for trading (comprehensive check)
    bool IsSafeForTrading(const string symbol) {
        // Check if trading is paused
        if(ShouldPauseTrading(symbol)) {
            return false;
        }
        
        // Check for abnormal spreads
        if(HasAbnormalSpreads(symbol)) {
            return false;
        }
        
        // Check health score
        SymbolHealthStatus status = GetHealthStatus(symbol);
        if(status.healthScore < 40.0) {
            return false;
        }
        
        // Check for critical anomalies
        if(status.activeAnomalies > 2) {
            return false;
        }
        
        // Check correlation risk
        if(GetCorrelationRiskLevel(symbol) > 0.5) {
            return false;
        }
        
        return true;
    }
    
    // Force health check update for symbol
    void ForceHealthUpdate(const string symbol) {
        PerformHealthCheck(symbol);
    }
    
    // Get all monitored symbols
    void GetMonitoredSymbols(string &symbols[]) {
        ArrayResize(symbols, ArraySize(m_healthStatus));
        
        for(int i = 0; i < ArraySize(m_healthStatus); i++) {
            symbols[i] = m_healthStatus[i].symbol;
        }
    }
    
private:
    // Calculate historical volatility norm for symbol
    double CalculateHistoricalVolatilityNorm(const string symbol) {
        // In a full implementation, this would analyze longer-term historical data
        // For now, use the average from our history buffer as a proxy
        int configIndex = GetConfigIndex(symbol);
        if(configIndex == -1) return 0.0;
        
        return CalculateAverageVolatility(configIndex);
    }
    
    // Check for sustained high volatility
    bool IsSustainedHighVolatility(int configIndex, double baseline) {
        if(baseline <= 0) return false;
        
        int highVolCount = 0;
        int checkPeriod = MathMin(20, m_volatilityHistorySize); // Check last 20 periods
        
        for(int i = m_volatilityHistorySize - checkPeriod; i < m_volatilityHistorySize; i++) {
            if(i >= 0 && m_volatilityHistory[configIndex][i] > baseline * 2.0) {
                highVolCount++;
            }
        }
        
        // Consider sustained if 70% of recent periods show high volatility
        return (highVolCount >= (checkPeriod * 0.7));
    }
    
    // Trigger volatility-based position size adjustment (Requirement 9.7)
    void TriggerVolatilityBasedAdjustment(const string symbol, double volatilityRatio) {
        int healthIndex = GetHealthStatusIndex(symbol);
        if(healthIndex == -1) return;
        
        // Mark that volatility adjustment is needed
        m_healthStatus[healthIndex].statusMessage += " [VOL_ADJUST:" + 
            DoubleToString(volatilityRatio, 1) + "x]";
        
        Print("SyntheticHealthMonitor", 
            "Volatility-based position adjustment triggered for " + symbol + 
            " - Volatility: " + DoubleToString(volatilityRatio, 2) + "x normal");
        
        // If volatility is extremely high, consider pausing trading
        if(volatilityRatio > 5.0) {
            PauseTradingForSymbol(symbol, 
                "Extreme volatility: " + DoubleToString(volatilityRatio, 1) + "x normal");
        }
    }
    
    // Clean up resolved anomalies
    void CleanupResolvedAnomalies() {
        datetime currentTime = TimeCurrent();
        
        for(int i = 0; i < ArraySize(m_anomalies); i++) {
            if(m_anomalies[i].isActive) {
                bool isResolved = false;
                
                // Check if anomaly conditions have been resolved
                if(m_anomalies[i].anomalyType == "spread") {
                    isResolved = AreSpreadsNormalized(m_anomalies[i].symbol);
                } else if(m_anomalies[i].anomalyType == "volatility") {
                    double currentVol = GetCurrentVolatility(m_anomalies[i].symbol);
                    double avgVol = GetAverageVolatility(m_anomalies[i].symbol);
                    isResolved = (avgVol > 0 && currentVol <= avgVol * 2.0);
                } else if(m_anomalies[i].anomalyType == "correlation") {
                    // Check if correlation has stabilized
                    isResolved = (currentTime - m_anomalies[i].detectedAt) > 3600; // 1 hour
                } else if(m_anomalies[i].anomalyType == "frequency") {
                    // Check if tick frequency has improved
                    isResolved = (currentTime - m_anomalies[i].detectedAt) > 1800; // 30 minutes
                }
                
                // Auto-resolve old anomalies
                if(!isResolved && (currentTime - m_anomalies[i].detectedAt) > 7200) { // 2 hours
                    isResolved = true;
                }
                
                if(isResolved) {
                    m_anomalies[i].isActive = false;
                    m_anomalies[i].resolvedAt = currentTime;
                    
                    Print("SyntheticHealthMonitor", 
                        "Anomaly resolved for " + m_anomalies[i].symbol + 
                        " (" + m_anomalies[i].anomalyType + "): " + m_anomalies[i].description);
                }
            }
        }
    }
};

#endif // __SYNTHETIC_INDEX_HEALTH_MONITOR_MQH__