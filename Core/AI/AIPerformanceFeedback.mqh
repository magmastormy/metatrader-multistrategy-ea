//+------------------------------------------------------------------+
//| AI Performance Feedback System                                 |
//| Tracks AI prediction accuracy and manages model retraining    |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_AI_PERFORMANCE_FEEDBACK_MQH
#define CORE_AI_PERFORMANCE_FEEDBACK_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "../Monitoring/PerformanceAnalytics.mqh"

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

//+------------------------------------------------------------------+
//| AI Prediction Record Structure                                 |
//+------------------------------------------------------------------+
struct SAIPredictionRecord
{
    datetime predictionTime;      // When prediction was made
    string symbol;                // Symbol predicted
    ENUM_TRADE_SIGNAL prediction; // AI prediction
    double confidence;            // AI confidence level
    double uncertainty;           // AI uncertainty level
    ENUM_MARKET_REGIME regime;    // Market regime at prediction
    
    // Actual outcome
    datetime outcomeTime;         // When outcome was determined
    ENUM_TRADE_SIGNAL actualOutcome; // Actual market movement
    double actualReturn;          // Actual return achieved
    bool predictionCorrect;       // Was prediction correct
    
    // Performance metrics
    double accuracyScore;         // Accuracy score for this prediction
    double calibrationScore;      // Calibration score
    double profitabilityScore;    // Profitability score
    
    SAIPredictionRecord()
    {
        predictionTime = 0;
        symbol = "";
        prediction = TRADE_SIGNAL_NONE;
        confidence = 0.0;
        uncertainty = 0.0;
        regime = MARKET_REGIME_UNKNOWN;
        outcomeTime = 0;
        actualOutcome = TRADE_SIGNAL_NONE;
        actualReturn = 0.0;
        predictionCorrect = false;
        accuracyScore = 0.0;
        calibrationScore = 0.0;
        profitabilityScore = 0.0;
    }
};

//+------------------------------------------------------------------+
//| AI Model Performance Metrics                                  |
//+------------------------------------------------------------------+
struct SAIModelMetrics
{
    int totalPredictions;         // Total predictions made
    int correctPredictions;       // Correct predictions
    double accuracy;              // Overall accuracy
    double precision;             // Precision score
    double recall;                // Recall score
    double f1Score;               // F1 score
    double calibrationError;      // Calibration error
    double averageConfidence;     // Average confidence
    double profitability;         // Average profitability
    double sharpeRatio;           // Sharpe ratio of AI predictions
    
    // Performance by regime
    double trendingAccuracy;      // Accuracy in trending markets
    double rangingAccuracy;       // Accuracy in ranging markets
    double volatileAccuracy;      // Accuracy in volatile markets
    
    // Recent performance (last 50 predictions)
    double recentAccuracy;        // Recent accuracy
    double recentProfitability;   // Recent profitability
    
    SAIModelMetrics()
    {
        totalPredictions = 0;
        correctPredictions = 0;
        accuracy = 0.0;
        precision = 0.0;
        recall = 0.0;
        f1Score = 0.0;
        calibrationError = 0.0;
        averageConfidence = 0.0;
        profitability = 0.0;
        sharpeRatio = 0.0;
        trendingAccuracy = 0.0;
        rangingAccuracy = 0.0;
        volatileAccuracy = 0.0;
        recentAccuracy = 0.0;
        recentProfitability = 0.0;
    }
};

//+------------------------------------------------------------------+
//| AI Performance Feedback Class                                 |
//+------------------------------------------------------------------+
class CAIPerformanceFeedback
{
private:
    SAIPredictionRecord m_predictions[];
    int m_maxRecords;
    int m_currentIndex;
    bool m_bufferFull;
    
    // Performance metrics
    SAIModelMetrics m_currentMetrics;
    
    // Retraining triggers
    double m_minAccuracyThreshold;
    double m_minProfitabilityThreshold;
    int m_minPredictionsForRetraining;
    datetime m_lastRetrainingTime;
    int m_retrainingInterval; // seconds
    int m_retrainingCount;
    string m_lastRetrainingReason;
    
    // Performance tracking
    datetime m_lastMetricsUpdate;
    int m_metricsUpdateInterval;
    
    bool m_initialized;
    
public:
    // Constructor
    CAIPerformanceFeedback(void);
    
    // Destructor
    ~CAIPerformanceFeedback(void);
    
    // Initialize feedback system
    bool Initialize(int maxRecords = 1000);
    
    // Record AI prediction
    void RecordPrediction(const string &predictionSymbol, const ENUM_TRADE_SIGNAL prediction,
                         const double confidence, const double uncertainty, 
                         const ENUM_MARKET_REGIME regime);
    
    // Record actual outcome
    void RecordOutcome(const string &outcomeSymbol, const datetime predictionTime,
                      const ENUM_TRADE_SIGNAL actualOutcome, const double actualReturn);
    
    // Update performance metrics
    void UpdateMetrics(void);
    
    // Check if retraining is needed
    bool ShouldRetrain(void);
    
    // Trigger retraining
    void TriggerRetraining(const string reason);
    
    // Get current AI performance metrics
    SAIModelMetrics GetCurrentMetrics(void) const { return m_currentMetrics; }
    
    // Get AI accuracy by regime
    double GetAccuracyByRegime(const ENUM_MARKET_REGIME regime);
    
    // Get recent performance trend
    bool IsPerformanceImproving(void);
    bool IsPerformanceDegrading(void);
    
    // Performance comparison
    bool CompareWithBenchmark(const double benchmarkAccuracy, const double benchmarkProfitability);
    
    // Model selection support
    string GetBestPerformingModel(void);
    void RecordModelPerformance(const string modelName, const double accuracy, const double profitability);
    
    // Enhanced retraining triggers (Task 5.3)
    void CheckAutomaticRetraining(void);
    bool ShouldRetrainBasedOnAccuracy(void);
    bool ShouldRetrainBasedOnProfitability(void);
    void SetRetrainingThresholds(double minAccuracy, double minProfitability);
    
    // Reporting
    void PrintPerformanceReport(void);
    string GetPerformanceSummary(void);
    
private:
    // Internal calculation methods
    void CalculateAccuracyMetrics(void);
    void CalculateProfitabilityMetrics(void);
    void CalculateCalibrationMetrics(void);
    void CalculateRecentMetrics(void);
    
    // Helper methods
    int FindPredictionIndex(const string &searchSymbol, const datetime predictionTime);
    double CalculateCalibrationError(void);
    double CalculateSharpeRatio(void);
    
    // Validation
    bool ValidatePredictionRecord(const SAIPredictionRecord &record);

    // Retraining persistence
    void PersistRetrainingRequest(const string reason);
    void ExportLabeledDataset(const string fileName, const int maxRows);
    
    // Logging
    void LogFeedback(const string message);
};

//+------------------------------------------------------------------+
//| Constructor                                                     |
//+------------------------------------------------------------------+
CAIPerformanceFeedback::CAIPerformanceFeedback(void) :
    m_maxRecords(1000),
    m_currentIndex(0),
    m_bufferFull(false),
    m_minAccuracyThreshold(0.55),
    m_minProfitabilityThreshold(0.1),
    m_minPredictionsForRetraining(50),
    m_lastRetrainingTime(0),
    m_retrainingInterval(86400), // 24 hours
    m_retrainingCount(0),
    m_lastRetrainingReason(""),
    m_lastMetricsUpdate(0),
    m_metricsUpdateInterval(300), // 5 minutes
    m_initialized(false)
{
    // Initialize metrics
    m_currentMetrics = SAIModelMetrics();
}

//+------------------------------------------------------------------+
//| Destructor                                                      |
//+------------------------------------------------------------------+
CAIPerformanceFeedback::~CAIPerformanceFeedback(void)
{
    if(m_initialized)
    {
        PrintPerformanceReport();
        LogFeedback("AI Performance Feedback system destroyed");
    }
}

//+------------------------------------------------------------------+
//| Initialize Feedback System                                     |
//+------------------------------------------------------------------+
bool CAIPerformanceFeedback::Initialize(int maxRecords = 1000)
{
    m_maxRecords = maxRecords;
    
    // Resize and initialize prediction array
    if(ArrayResize(m_predictions, m_maxRecords) != m_maxRecords)
    {
        SErrorContext context;
        context.errorCode = 4001; // Custom error code for memory allocation failure
        context.component = "AIPerformanceFeedback";
        context.operation = "Initialize";
        context.additionalInfo = "Failed to allocate memory for predictions";
        context.severity = ERROR_CRITICAL;
        CEnhancedErrorHandler::LogError(ERROR_CRITICAL, context);
        return false;
    }
    
    // Initialize all prediction records
    for(int i = 0; i < m_maxRecords; i++) {
        m_predictions[i] = SAIPredictionRecord();
    }
    
    m_initialized = true;
    
    LogFeedback("AI Performance Feedback system initialized with " + IntegerToString(m_maxRecords) + " record capacity");
    return true;
}

//+------------------------------------------------------------------+
//| Record AI Prediction                                          |
//+------------------------------------------------------------------+
void CAIPerformanceFeedback::RecordPrediction(const string &predictionSymbol, const ENUM_TRADE_SIGNAL prediction,
                                             const double confidence, const double uncertainty, 
                                             const ENUM_MARKET_REGIME regime)
{
    if(!m_initialized) return;
    
    // Create prediction record
    SAIPredictionRecord record;
    record.predictionTime = TimeCurrent();
    record.symbol = predictionSymbol;
    record.prediction = prediction;
    record.confidence = confidence;
    record.uncertainty = uncertainty;
    record.regime = regime;
    
    // Store in circular buffer
    m_predictions[m_currentIndex] = record;
    m_currentIndex = (m_currentIndex + 1) % m_maxRecords;
    
    if(m_currentIndex == 0)
        m_bufferFull = true;
    
    LogFeedback(StringFormat("AI prediction recorded: %s %s (Conf: %.2f, Unc: %.2f)",
                            predictionSymbol, EnumToString(prediction), confidence, uncertainty));
}

//+------------------------------------------------------------------+
//| Record Actual Outcome                                         |
//+------------------------------------------------------------------+
void CAIPerformanceFeedback::RecordOutcome(const string &outcomeSymbol, const datetime predictionTime,
                                          const ENUM_TRADE_SIGNAL actualOutcome, const double actualReturn)
{
    if(!m_initialized) return;
    
    // Find matching prediction
    int index = FindPredictionIndex(outcomeSymbol, predictionTime);
    if(index < 0) return; // Prediction not found
    
    // Update prediction record with outcome
    m_predictions[index].outcomeTime = TimeCurrent();
    m_predictions[index].actualOutcome = actualOutcome;
    m_predictions[index].actualReturn = actualReturn;
    
    // Determine if prediction was correct
    m_predictions[index].predictionCorrect = (m_predictions[index].prediction == actualOutcome);
    
    // Calculate performance scores
    m_predictions[index].accuracyScore = m_predictions[index].predictionCorrect ? 1.0 : 0.0;
    m_predictions[index].profitabilityScore = actualReturn;
    
    // Calculate calibration score (how well confidence matched actual outcome)
    double expectedReturn = m_predictions[index].confidence * 0.02; // Expected 2% return at full confidence
    m_predictions[index].calibrationScore = 1.0 - MathAbs(actualReturn - expectedReturn) / 0.02;
    m_predictions[index].calibrationScore = MathMax(0.0, m_predictions[index].calibrationScore);
    
    // Update metrics
    UpdateMetrics();
    
    LogFeedback(StringFormat("AI outcome recorded: %s - Predicted: %s, Actual: %s, Return: %.4f, Correct: %s",
                            outcomeSymbol, EnumToString(m_predictions[index].prediction),
                            EnumToString(actualOutcome), actualReturn,
                            m_predictions[index].predictionCorrect ? "YES" : "NO"));
}

//+------------------------------------------------------------------+
//| Update Performance Metrics                                    |
//+------------------------------------------------------------------+
void CAIPerformanceFeedback::UpdateMetrics(void)
{
    if(!m_initialized) return;
    
    datetime localCurrentTime = TimeCurrent();
    if(localCurrentTime - m_lastMetricsUpdate < m_metricsUpdateInterval) return;
    
    m_lastMetricsUpdate = localCurrentTime;
    
    CalculateAccuracyMetrics();
    CalculateProfitabilityMetrics();
    CalculateCalibrationMetrics();
    CalculateRecentMetrics();
}

//+------------------------------------------------------------------+
//| Calculate Accuracy Metrics                                    |
//+------------------------------------------------------------------+
void CAIPerformanceFeedback::CalculateAccuracyMetrics(void)
{
    int totalPredictions = 0;
    int correctPredictions = 0;
    int truePositives = 0;
    int falsePositives = 0;
    int falseNegatives = 0;
    
    // Count by regime
    int trendingTotal = 0, trendingCorrect = 0;
    int rangingTotal = 0, rangingCorrect = 0;
    int volatileTotal = 0, volatileCorrect = 0;
    
    double totalConfidence = 0.0;
    
    int recordCount = m_bufferFull ? m_maxRecords : m_currentIndex;
    
    for(int i = 0; i < recordCount; i++)
    {
        if(m_predictions[i].outcomeTime > 0) // Has outcome
        {
            totalPredictions++;
            totalConfidence += m_predictions[i].confidence;
            
            if(m_predictions[i].predictionCorrect)
                correctPredictions++;
            
            // Calculate precision/recall metrics
            if(m_predictions[i].prediction != TRADE_SIGNAL_NONE)
            {
                if(m_predictions[i].actualOutcome == m_predictions[i].prediction)
                    truePositives++;
                else
                    falsePositives++;
            }
            else if(m_predictions[i].actualOutcome != TRADE_SIGNAL_NONE)
            {
                falseNegatives++;
            }
            
            // Count by regime
            switch(m_predictions[i].regime)
            {
                case MARKET_REGIME_TRENDING:
                    trendingTotal++;
                    if(m_predictions[i].predictionCorrect) trendingCorrect++;
                    break;
                case MARKET_REGIME_RANGING:
                    rangingTotal++;
                    if(m_predictions[i].predictionCorrect) rangingCorrect++;
                    break;
                case MARKET_REGIME_VOLATILE:
                    volatileTotal++;
                    if(m_predictions[i].predictionCorrect) volatileCorrect++;
                    break;
            }
        }
    }
    
    // Update metrics
    m_currentMetrics.totalPredictions = totalPredictions;
    m_currentMetrics.correctPredictions = correctPredictions;
    
    if(totalPredictions > 0)
    {
        m_currentMetrics.accuracy = (double)correctPredictions / totalPredictions;
        m_currentMetrics.averageConfidence = totalConfidence / totalPredictions;
    }
    
    if(truePositives + falsePositives > 0)
        m_currentMetrics.precision = (double)truePositives / (truePositives + falsePositives);
    
    if(truePositives + falseNegatives > 0)
        m_currentMetrics.recall = (double)truePositives / (truePositives + falseNegatives);
    
    if(m_currentMetrics.precision + m_currentMetrics.recall > 0)
        m_currentMetrics.f1Score = 2.0 * (m_currentMetrics.precision * m_currentMetrics.recall) / 
                                  (m_currentMetrics.precision + m_currentMetrics.recall);
    
    // Regime-specific accuracy
    if(trendingTotal > 0) m_currentMetrics.trendingAccuracy = (double)trendingCorrect / trendingTotal;
    if(rangingTotal > 0) m_currentMetrics.rangingAccuracy = (double)rangingCorrect / rangingTotal;
    if(volatileTotal > 0) m_currentMetrics.volatileAccuracy = (double)volatileCorrect / volatileTotal;
}

//+------------------------------------------------------------------+
//| Calculate Profitability Metrics                               |
//+------------------------------------------------------------------+
void CAIPerformanceFeedback::CalculateProfitabilityMetrics(void)
{
    double totalReturn = 0.0;
    int profitableCount = 0;
    int recordCount = m_bufferFull ? m_maxRecords : m_currentIndex;
    
    for(int i = 0; i < recordCount; i++)
    {
        if(m_predictions[i].outcomeTime > 0) // Has outcome
        {
            totalReturn += m_predictions[i].actualReturn;
            if(m_predictions[i].actualReturn > 0)
                profitableCount++;
        }
    }
    
    if(m_currentMetrics.totalPredictions > 0)
    {
        m_currentMetrics.profitability = totalReturn / m_currentMetrics.totalPredictions;
    }
    
    // Calculate Sharpe ratio
    m_currentMetrics.sharpeRatio = CalculateSharpeRatio();
}

//+------------------------------------------------------------------+
//| Calculate Calibration Metrics                                 |
//+------------------------------------------------------------------+
void CAIPerformanceFeedback::CalculateCalibrationMetrics(void)
{
    m_currentMetrics.calibrationError = CalculateCalibrationError();
}

//+------------------------------------------------------------------+
//| Calculate Recent Metrics                                      |
//+------------------------------------------------------------------+
void CAIPerformanceFeedback::CalculateRecentMetrics(void)
{
    int recentCount = MathMin(50, m_currentMetrics.totalPredictions);
    if(recentCount < 10) return; // Need minimum recent data
    
    int recentCorrect = 0;
    double recentReturn = 0.0;
    int startIndex = m_bufferFull ? (m_currentIndex - recentCount + m_maxRecords) % m_maxRecords : 
                                   MathMax(0, m_currentIndex - recentCount);
    
    for(int i = 0; i < recentCount; i++)
    {
        int index = (startIndex + i) % m_maxRecords;
        if(m_predictions[index].outcomeTime > 0)
        {
            if(m_predictions[index].predictionCorrect)
                recentCorrect++;
            recentReturn += m_predictions[index].actualReturn;
        }
    }
    
    m_currentMetrics.recentAccuracy = (double)recentCorrect / recentCount;
    m_currentMetrics.recentProfitability = recentReturn / recentCount;
}

//+------------------------------------------------------------------+
//| Should Retrain AI Models                                      |
//+------------------------------------------------------------------+
bool CAIPerformanceFeedback::ShouldRetrain(void)
{
    if(!m_initialized) return false;
    
    // Check if enough time has passed since last retraining
    datetime currentTimeLocal = TimeCurrent();
    if(currentTimeLocal - m_lastRetrainingTime < m_retrainingInterval) return false;
    
    // Check if we have enough predictions
    if(m_currentMetrics.totalPredictions < m_minPredictionsForRetraining) return false;
    
    // Check accuracy threshold (Requirement 6.6)
    if(m_currentMetrics.recentAccuracy < m_minAccuracyThreshold)
    {
        LogFeedback(StringFormat("Retraining triggered: Recent accuracy %.2f%% below threshold %.2f%%", 
                                m_currentMetrics.recentAccuracy * 100, m_minAccuracyThreshold * 100));
        return true;
    }
    
    // Check profitability threshold
    if(m_currentMetrics.recentProfitability < m_minProfitabilityThreshold)
    {
        LogFeedback(StringFormat("Retraining triggered: Recent profitability %.4f below threshold %.4f", 
                                m_currentMetrics.recentProfitability, m_minProfitabilityThreshold));
        return true;
    }
    
    // Check if performance is significantly degrading
    if(IsPerformanceDegrading())
    {
        LogFeedback("Retraining triggered: Performance degradation detected");
        return true;
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Trigger Retraining                                           |
//+------------------------------------------------------------------+
void CAIPerformanceFeedback::TriggerRetraining(const string reason)
{
    if(!m_initialized)
        return;

    UpdateMetrics();

    m_lastRetrainingTime = TimeCurrent();
    m_retrainingCount++;
    m_lastRetrainingReason = reason;

    PersistRetrainingRequest(reason);
    ExportLabeledDataset("AI_Retraining_Dataset.csv", 500);

    LogFeedback("AI model retraining triggered: " + reason);
    Print("[AI-RETRAIN] Triggered #", m_retrainingCount, " | Reason: ", reason);
    Print("[AI-RETRAIN] Metrics | Accuracy: ", DoubleToString(m_currentMetrics.accuracy * 100, 1),
          "% | Recent Accuracy: ", DoubleToString(m_currentMetrics.recentAccuracy * 100, 1),
          "% | Profitability: ", DoubleToString(m_currentMetrics.profitability, 4),
          " | Sharpe: ", DoubleToString(m_currentMetrics.sharpeRatio, 3));
}

//+------------------------------------------------------------------+
//| Is Performance Degrading                                      |
//+------------------------------------------------------------------+
bool CAIPerformanceFeedback::IsPerformanceDegrading(void)
{
    if(m_currentMetrics.totalPredictions < 100) return false; // Need enough data
    
    // Compare recent performance with overall performance
    double accuracyDegradation = m_currentMetrics.accuracy - m_currentMetrics.recentAccuracy;
    double profitabilityDegradation = m_currentMetrics.profitability - m_currentMetrics.recentProfitability;
    
    // Consider degradation significant if recent performance is 10% worse
    return (accuracyDegradation > 0.10 || profitabilityDegradation > 0.01);
}

//+------------------------------------------------------------------+
//| Find Prediction Index                                         |
//+------------------------------------------------------------------+
int CAIPerformanceFeedback::FindPredictionIndex(const string &searchSymbol, const datetime predictionTime)
{
    int recordCount = m_bufferFull ? m_maxRecords : m_currentIndex;
    
    for(int i = 0; i < recordCount; i++)
    {
        if(m_predictions[i].symbol == searchSymbol &&
           MathAbs(m_predictions[i].predictionTime - predictionTime) < 300) // Within 5 minutes
        {
            return i;
        }
    }
    
    return -1; // Not found
}

//+------------------------------------------------------------------+
//| Calculate Calibration Error                                   |
//+------------------------------------------------------------------+
double CAIPerformanceFeedback::CalculateCalibrationError(void)
{
    double totalError = 0.0;
    int count = 0;
    int recordCount = m_bufferFull ? m_maxRecords : m_currentIndex;
    
    for(int i = 0; i < recordCount; i++)
    {
        if(m_predictions[i].outcomeTime > 0)
        {
            totalError += MathAbs(m_predictions[i].confidence - m_predictions[i].accuracyScore);
            count++;
        }
    }
    
    return count > 0 ? totalError / count : 0.0;
}

//+------------------------------------------------------------------+
//| Calculate Sharpe Ratio                                        |
//+------------------------------------------------------------------+
double CAIPerformanceFeedback::CalculateSharpeRatio(void)
{
    if(m_currentMetrics.totalPredictions < 10) return 0.0;
    
    // Calculate standard deviation of returns
    double meanReturn = m_currentMetrics.profitability;
    double variance = 0.0;
    int count = 0;
    int recordCount = m_bufferFull ? m_maxRecords : m_currentIndex;
    
    for(int i = 0; i < recordCount; i++)
    {
        if(m_predictions[i].outcomeTime > 0)
        {
            double diff = m_predictions[i].actualReturn - meanReturn;
            variance += diff * diff;
            count++;
        }
    }
    
    if(count < 2) return 0.0;
    
    double stdDev = MathSqrt(variance / (count - 1));
    return stdDev > 0 ? meanReturn / stdDev : 0.0;
}

//+------------------------------------------------------------------+
//| Print Performance Report                                      |
//+------------------------------------------------------------------+
void CAIPerformanceFeedback::PrintPerformanceReport(void)
{
    if(!m_initialized) return;
    
    Print("\n🤖 === AI PERFORMANCE FEEDBACK REPORT ===");
    Print("📊 PREDICTION METRICS:");
    Print("   Total Predictions: ", m_currentMetrics.totalPredictions);
    Print("   Accuracy: ", DoubleToString(m_currentMetrics.accuracy * 100, 1), "%");
    Print("   Recent Accuracy: ", DoubleToString(m_currentMetrics.recentAccuracy * 100, 1), "%");
    Print("   Precision: ", DoubleToString(m_currentMetrics.precision, 3));
    Print("   Recall: ", DoubleToString(m_currentMetrics.recall, 3));
    Print("   F1 Score: ", DoubleToString(m_currentMetrics.f1Score, 3));
    
    Print("\n💰 PROFITABILITY METRICS:");
    Print("   Average Return: ", DoubleToString(m_currentMetrics.profitability, 4));
    Print("   Recent Profitability: ", DoubleToString(m_currentMetrics.recentProfitability, 4));
    Print("   Sharpe Ratio: ", DoubleToString(m_currentMetrics.sharpeRatio, 2));
    
    Print("\n🎯 CALIBRATION METRICS:");
    Print("   Average Confidence: ", DoubleToString(m_currentMetrics.averageConfidence, 2));
    Print("   Calibration Error: ", DoubleToString(m_currentMetrics.calibrationError, 3));
    
    Print("\n📈 REGIME-SPECIFIC ACCURACY:");
    Print("   Trending Markets: ", DoubleToString(m_currentMetrics.trendingAccuracy * 100, 1), "%");
    Print("   Ranging Markets: ", DoubleToString(m_currentMetrics.rangingAccuracy * 100, 1), "%");
    Print("   Volatile Markets: ", DoubleToString(m_currentMetrics.volatileAccuracy * 100, 1), "%");
    
    Print("\n🔄 RETRAINING STATUS:");
    Print("   Should Retrain: ", ShouldRetrain() ? "YES" : "NO");
    Print("   Performance Degrading: ", IsPerformanceDegrading() ? "YES" : "NO");
    Print("   Last Retraining: ", TimeToString(m_lastRetrainingTime));
    
    Print("==========================================\n");
}

//+------------------------------------------------------------------+
//| Get Performance Summary                                       |
//+------------------------------------------------------------------+
string CAIPerformanceFeedback::GetPerformanceSummary(void)
{
    if(!m_initialized) return "AI feedback not initialized";
    
    return StringFormat("AI: Acc=%.1f%% | Prof=%.4f | Pred=%d | Retrain=%s",
                       m_currentMetrics.recentAccuracy * 100,
                       m_currentMetrics.recentProfitability,
                       m_currentMetrics.totalPredictions,
                       ShouldRetrain() ? "YES" : "NO");
}

//+------------------------------------------------------------------+
//| Check Automatic Retraining (Task 5.3)                       |
//+------------------------------------------------------------------+
void CAIPerformanceFeedback::CheckAutomaticRetraining(void)
{
    if(!m_initialized) return;
    
    // Update metrics first
    UpdateMetrics();
    
    // Check multiple retraining conditions
    bool needsRetraining = false;
    string retrainingReason = "";
    
    if(ShouldRetrainBasedOnAccuracy())
    {
        needsRetraining = true;
        retrainingReason += "Low accuracy; ";
    }
    
    if(ShouldRetrainBasedOnProfitability())
    {
        needsRetraining = true;
        retrainingReason += "Low profitability; ";
    }
    
    if(IsPerformanceDegrading())
    {
        needsRetraining = true;
        retrainingReason += "Performance degradation; ";
    }
    
    // Check calibration issues
    if(m_currentMetrics.calibrationError > 0.3)
    {
        needsRetraining = true;
        retrainingReason += "Poor calibration; ";
    }
    
    if(needsRetraining)
    {
        TriggerRetraining("Automatic trigger: " + retrainingReason);
    }
}

//+------------------------------------------------------------------+
//| Should Retrain Based on Accuracy (Task 5.3)                 |
//+------------------------------------------------------------------+
bool CAIPerformanceFeedback::ShouldRetrainBasedOnAccuracy(void)
{
    if(m_currentMetrics.totalPredictions < m_minPredictionsForRetraining) return false;
    
    // Check recent accuracy vs threshold
    if(m_currentMetrics.recentAccuracy < m_minAccuracyThreshold) return true;
    
    // Check if accuracy has dropped significantly from overall performance
    if(m_currentMetrics.totalPredictions > 100)
    {
        double accuracyDrop = m_currentMetrics.accuracy - m_currentMetrics.recentAccuracy;
        if(accuracyDrop > 0.15) return true; // 15% drop in accuracy
    }
    
    return false;
}

//+------------------------------------------------------------------+
//| Should Retrain Based on Profitability (Task 5.3)            |
//+------------------------------------------------------------------+
bool CAIPerformanceFeedback::ShouldRetrainBasedOnProfitability(void)
{
    if(m_currentMetrics.totalPredictions < m_minPredictionsForRetraining) return false;
    
    // Check recent profitability vs threshold
    if(m_currentMetrics.recentProfitability < m_minProfitabilityThreshold) return true;
    
    // Check Sharpe ratio degradation
    if(m_currentMetrics.sharpeRatio < 0.3) return true;
    
    return false;
}

//+------------------------------------------------------------------+
//| Set Retraining Thresholds (Task 5.3)                        |
//+------------------------------------------------------------------+
void CAIPerformanceFeedback::SetRetrainingThresholds(double minAccuracy, double minProfitability)
{
    m_minAccuracyThreshold = MathMax(0.3, MathMin(0.9, minAccuracy));
    m_minProfitabilityThreshold = MathMax(-0.1, MathMin(0.5, minProfitability));
    
    LogFeedback(StringFormat("Retraining thresholds updated: Accuracy=%.2f%%, Profitability=%.4f", 
                            m_minAccuracyThreshold * 100, m_minProfitabilityThreshold));
}

//+------------------------------------------------------------------+
//| Persist retraining request                                      |
//+------------------------------------------------------------------+
void CAIPerformanceFeedback::PersistRetrainingRequest(const string reason)
{
    string cleanReason = reason;
    StringReplace(cleanReason, ",", ";");
    StringReplace(cleanReason, "\r", " ");
    StringReplace(cleanReason, "\n", " ");

    string fileName = "AI_Retraining_Requests.csv";
    int handle = FileOpen(fileName, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
    if(handle == INVALID_HANDLE)
    {
        LogFeedback("Failed to open retraining request log: " + fileName);
        return;
    }

    bool writeHeader = (FileSize(handle) == 0);
    FileSeek(handle, 0, SEEK_END);

    if(writeHeader)
    {
        FileWriteString(handle, "timestamp,reason,total_predictions,recent_accuracy,recent_profitability,calibration_error\n");
    }

    string line = StringFormat("%s,%s,%d,%.6f,%.6f,%.6f\n",
                               TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
                               cleanReason,
                               m_currentMetrics.totalPredictions,
                               m_currentMetrics.recentAccuracy,
                               m_currentMetrics.recentProfitability,
                               m_currentMetrics.calibrationError);
    FileWriteString(handle, line);
    FileClose(handle);
}

//+------------------------------------------------------------------+
//| Export labeled dataset snapshot                                 |
//+------------------------------------------------------------------+
void CAIPerformanceFeedback::ExportLabeledDataset(const string fileName, const int maxRows)
{
    int limit = MathMax(1, maxRows);
    int recordCount = m_bufferFull ? m_maxRecords : m_currentIndex;
    if(recordCount <= 0)
        return;

    int labeledCount = 0;
    int startIndex = m_bufferFull ? m_currentIndex : 0;
    for(int i = 0; i < recordCount; i++)
    {
        int idx = (startIndex + i) % m_maxRecords;
        if(m_predictions[idx].outcomeTime > 0)
            labeledCount++;
    }

    if(labeledCount <= 0)
        return;

    int skip = MathMax(0, labeledCount - limit);
    int handle = FileOpen(fileName, FILE_WRITE | FILE_TXT | FILE_ANSI);
    if(handle == INVALID_HANDLE)
    {
        LogFeedback("Failed to export labeled dataset: " + fileName);
        return;
    }

    FileWriteString(handle, "prediction_time,outcome_time,symbol,prediction,actual_outcome,confidence,uncertainty,actual_return,prediction_correct,regime\n");

    int seenLabeled = 0;
    for(int i = 0; i < recordCount; i++)
    {
        int idx = (startIndex + i) % m_maxRecords;
        if(m_predictions[idx].outcomeTime <= 0)
            continue;

        if(seenLabeled < skip)
        {
            seenLabeled++;
            continue;
        }

        string row = StringFormat("%s,%s,%s,%s,%s,%.6f,%.6f,%.6f,%d,%s\n",
                                  TimeToString(m_predictions[idx].predictionTime, TIME_DATE | TIME_SECONDS),
                                  TimeToString(m_predictions[idx].outcomeTime, TIME_DATE | TIME_SECONDS),
                                  m_predictions[idx].symbol,
                                  EnumToString(m_predictions[idx].prediction),
                                  EnumToString(m_predictions[idx].actualOutcome),
                                  m_predictions[idx].confidence,
                                  m_predictions[idx].uncertainty,
                                  m_predictions[idx].actualReturn,
                                  m_predictions[idx].predictionCorrect ? 1 : 0,
                                  EnumToString(m_predictions[idx].regime));
        FileWriteString(handle, row);
        seenLabeled++;
    }

    FileClose(handle);
}

//+------------------------------------------------------------------+
//| Log Feedback                                                  |
//+------------------------------------------------------------------+
void CAIPerformanceFeedback::LogFeedback(const string message)
{
    SErrorContext context;
    context.component = "AIPerformanceFeedback";
    context.operation = "LogFeedback";
    context.errorCode = 0;
    context.additionalInfo = message;
    context.severity = ERROR_INFO;
    CEnhancedErrorHandler::LogError(ERROR_INFO, context);
}

#endif // CORE_AI_PERFORMANCE_FEEDBACK_MQH

