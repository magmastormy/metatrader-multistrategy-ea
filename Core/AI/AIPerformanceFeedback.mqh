// Tracks AI prediction accuracy and manages model retraining
#property copyright "Copyright 2024, Windsurf AI"
#property link      "https://www.windsurf.ai"
#property version   "1.00"
#property strict

#ifndef CORE_AI_PERFORMANCE_FEEDBACK_MQH
#define CORE_AI_PERFORMANCE_FEEDBACK_MQH

#include "../Utils/Enums.mqh"
#include "../Utils/ErrorHandling.mqh"
#include "../Monitoring/PerformanceAnalytics.mqh"

class CEnhancedErrorHandler;
class CUtilities;
class CMarketAnalysis;
class CNextGenStrategyBrain;
class CTransformerBrain;
struct SPredictionWithUncertainty;
class CPositionSizer;
class CTradeManager;
class CPerformanceAnalytics;

struct SAIPredictionRecord
{
    datetime predictionTime;      // When prediction was made
    string symbol;                // Symbol predicted
    ENUM_TRADE_SIGNAL prediction;
    double confidence;            // AI confidence level
    double uncertainty;           // AI uncertainty level
    ENUM_MARKET_REGIME regime;    // Market regime at prediction
    
    datetime outcomeTime;         // When outcome was determined
    ENUM_TRADE_SIGNAL actualOutcome; // Actual market movement
    double actualReturn;          // Actual return achieved
    bool predictionCorrect;       // Was prediction correct
    
    double accuracyScore;         // Accuracy score for this prediction
    double calibrationScore;
    double profitabilityScore;
    
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

struct SAIModelMetrics
{
    int totalPredictions;         // Total predictions made
    int correctPredictions;
    double accuracy;              // Overall accuracy
    double precision;             // Precision score
    double recall;                // Recall score
    double f1Score;
    double calibrationError;
    double averageConfidence;
    double profitability;         // Average profitability
    double sharpeRatio;           // Sharpe ratio of AI predictions
    
    double trendingAccuracy;      // Accuracy in trending markets
    double rangingAccuracy;       // Accuracy in ranging markets
    double volatileAccuracy;      // Accuracy in volatile markets
    
    // Recent performance (last 50 predictions)
    double recentAccuracy;
    double recentProfitability;
    
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

class CAIPerformanceFeedback
{
private:
    SAIPredictionRecord m_predictions[];
    int m_maxRecords;
    int m_currentIndex;
    bool m_bufferFull;
    
    SAIModelMetrics m_currentMetrics;
    
    double m_minAccuracyThreshold;
    double m_minProfitabilityThreshold;
    double m_calibrationErrorThreshold;
    int m_minPredictionsForRetraining;
    datetime m_lastRetrainingTime;
    int m_retrainingInterval; // seconds
    int m_retrainingCount;
    string m_lastRetrainingReason;

    // Retrain effectiveness tracking: pause triggering after consecutive ineffective retrain attempts
    int m_consecutiveFailedRetrains;
    datetime m_retrainPauseUntil;
    double m_preRetrainAccuracy;
    double m_preRetrainProfitability;
    double m_preRetrainSharpe;

    // Metrics update throttle: UpdateMetrics() returns early until m_metricsUpdateInterval has elapsed
    datetime m_lastMetricsUpdate;
    int m_metricsUpdateInterval;
    
    bool m_initialized;
    
public:
    CAIPerformanceFeedback(void);
    
    ~CAIPerformanceFeedback(void);
    
    bool Initialize(int maxRecords = 1000);
    
    void RecordPrediction(const string &predictionSymbol, const ENUM_TRADE_SIGNAL prediction,
                         const double confidence, const double uncertainty,
                         const ENUM_MARKET_REGIME regime, const datetime predictionTimeOverride = 0);
    
    void RecordOutcome(const string &outcomeSymbol, const datetime predictionTime,
                      const ENUM_TRADE_SIGNAL actualOutcome, const double actualReturn);
    
    void UpdateMetrics(void);
    
    bool ShouldRetrain(void);
    
    void TriggerRetraining(const string reason);
    
    SAIModelMetrics GetCurrentMetrics(void) const { return m_currentMetrics; }
    
    double GetAccuracyByRegime(const ENUM_MARKET_REGIME regime);
    
    bool IsPerformanceImproving(void);
    bool IsPerformanceDegrading(void);
    
    bool CompareWithBenchmark(const double benchmarkAccuracy, const double benchmarkProfitability);
    
    void CheckAutomaticRetraining(void);
    bool ShouldRetrainBasedOnAccuracy(void);
    bool ShouldRetrainBasedOnProfitability(void);
    void SetRetrainingThresholds(double minAccuracy, double minProfitability);
    
        void PrintPerformanceReport(void);
        string GetPerformanceSummary(void);
    
        void PersistMetrics(void);
        void PersistMetricsToCSV(const string filename);
    
    private:
    void CalculateAccuracyMetrics(void);
    void CalculateProfitabilityMetrics(void);
    void CalculateCalibrationMetrics(void);
    void CalculateRecentMetrics(void);
    
    int FindPredictionIndex(const string &searchSymbol, const datetime predictionTime);
    double CalculateCalibrationError(void);
    double CalculateSharpeRatio(void);
    
    void PersistRetrainingRequest(const string reason);
    void ExportLabeledDataset(const string fileName, const int maxRows);
    
    void LogFeedback(const string message)
    {
        PrintFormat("[AI-FEEDBACK] %s", message);
    }
};

CAIPerformanceFeedback::CAIPerformanceFeedback(void) :
    m_maxRecords(1000),
    m_currentIndex(0),
    m_bufferFull(false),
    m_minAccuracyThreshold(0.55),
    m_minProfitabilityThreshold(0.1),
    m_calibrationErrorThreshold(0.3),
    m_minPredictionsForRetraining(50),
    m_lastRetrainingTime(0),
    m_retrainingInterval(86400), // 24 hours
    m_retrainingCount(0),
    m_lastRetrainingReason(""),
    m_consecutiveFailedRetrains(0),
    m_retrainPauseUntil(0),
    m_preRetrainAccuracy(0.0),
    m_preRetrainProfitability(0.0),
    m_preRetrainSharpe(0.0),
    m_lastMetricsUpdate(0),
    m_metricsUpdateInterval(300), // 5 minutes
    m_initialized(false)
{
    m_currentMetrics = SAIModelMetrics();
}

CAIPerformanceFeedback::~CAIPerformanceFeedback(void)
{
    if(m_initialized)
    {
        if(m_currentMetrics.totalPredictions > 0)
            PrintPerformanceReport();
        // Final metrics are written to the dashboard CSV here; the in-memory buffer itself does not survive a restart
        PersistMetrics();
        LogFeedback("AI Performance Feedback system destroyed");
    }
}

bool CAIPerformanceFeedback::Initialize(int maxRecords = 1000)
{
    m_maxRecords = maxRecords;
    
    // A failed allocation leaves m_initialized false, so the other entry points return without doing work
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
    
    for(int i = 0; i < m_maxRecords; i++) {
        m_predictions[i] = SAIPredictionRecord();
    }
    
    m_initialized = true;
    
    LogFeedback("AI Performance Feedback system initialized with " + IntegerToString(m_maxRecords) + " record capacity");
    return true;
}

void CAIPerformanceFeedback::RecordPrediction(const string &predictionSymbol, const ENUM_TRADE_SIGNAL prediction,
                                             const double confidence, const double uncertainty,
                                             const ENUM_MARKET_REGIME regime, const datetime predictionTimeOverride)
{
    if(!m_initialized) return;
    
    SAIPredictionRecord record;
    datetime predictionTime = (predictionTimeOverride > 0) ? predictionTimeOverride : TimeCurrent();
    record.predictionTime = predictionTime;
    record.symbol = predictionSymbol;
    record.prediction = prediction;
    record.confidence = confidence;
    record.uncertainty = uncertainty;
    record.regime = regime;
    
    // Circular buffer: the write index wraps and overwrites the oldest slot once m_bufferFull is set
    m_predictions[m_currentIndex] = record;
    m_currentIndex = (m_currentIndex + 1) % m_maxRecords;
    
    if(m_currentIndex == 0)
        m_bufferFull = true;
    
    LogFeedback(StringFormat("AI prediction recorded: %s %s (Conf: %.2f, Unc: %.2f)",
                            predictionSymbol, EnumToString(prediction), confidence, uncertainty));
}

void CAIPerformanceFeedback::RecordOutcome(const string &outcomeSymbol, const datetime predictionTime,
                                          const ENUM_TRADE_SIGNAL actualOutcome, const double actualReturn)
{
    if(!m_initialized) return;
    
    // Attribution match: same symbol with predictionTime within 5 seconds; no match drops the outcome
    int index = FindPredictionIndex(outcomeSymbol, predictionTime);
    if(index < 0) return; // Prediction not found
    
    m_predictions[index].outcomeTime = TimeCurrent();
    m_predictions[index].actualOutcome = actualOutcome;
    m_predictions[index].actualReturn = actualReturn;
    
    m_predictions[index].predictionCorrect = (m_predictions[index].prediction == actualOutcome);
    
    // accuracyScore is 1/0 from that equality, so a NONE call against a NONE outcome counts as correct
    m_predictions[index].accuracyScore = m_predictions[index].predictionCorrect ? 1.0 : 0.0;
    m_predictions[index].profitabilityScore = actualReturn;
    
    // Calibration: expected = confidence * max(0.01,|actual|); score = 1 - |actual-expected|/max(0.01,|actual|), clamped to [0,1]
    double maxExpectedReturn = MathMax(0.01, MathAbs(actualReturn));
    double expectedReturn = m_predictions[index].confidence * maxExpectedReturn;
    m_predictions[index].calibrationScore = 1.0 - MathAbs(actualReturn - expectedReturn) / MathMax(0.01, maxExpectedReturn);
    m_predictions[index].calibrationScore = MathMax(0.0, MathMin(1.0, m_predictions[index].calibrationScore));
    
    UpdateMetrics();
    
    LogFeedback(StringFormat("AI outcome recorded: %s - Predicted: %s, Actual: %s, Return: %.4f, Correct: %s",
                            outcomeSymbol, EnumToString(m_predictions[index].prediction),
                            EnumToString(actualOutcome), actualReturn,
                            m_predictions[index].predictionCorrect ? "YES" : "NO"));
}

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
    
    PersistMetrics();
}

void CAIPerformanceFeedback::CalculateAccuracyMetrics(void)
{
    int totalPredictions = 0;
    int correctPredictions = 0;
    int truePositives = 0;
    int falsePositives = 0;
    int falseNegatives = 0;
    
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
            
            // Confusion counts only cover non-NONE predictions: NONE against a real outcome is a false negative
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
    
    // Regime buckets with no samples keep their previous accuracy value
    if(trendingTotal > 0) m_currentMetrics.trendingAccuracy = (double)trendingCorrect / trendingTotal;
    if(rangingTotal > 0) m_currentMetrics.rangingAccuracy = (double)rangingCorrect / rangingTotal;
    if(volatileTotal > 0) m_currentMetrics.volatileAccuracy = (double)volatileCorrect / volatileTotal;
}

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
    
    m_currentMetrics.sharpeRatio = CalculateSharpeRatio();
}

void CAIPerformanceFeedback::CalculateCalibrationMetrics(void)
{
    m_currentMetrics.calibrationError = CalculateCalibrationError();
}

void CAIPerformanceFeedback::CalculateRecentMetrics(void)
{
    int recentCount = MathMin(50, m_currentMetrics.totalPredictions);
    if(recentCount < 10) return; // Need minimum recent data
    
    int recentCorrect = 0;
    double recentReturn = 0.0;
    int labeledCount = 0;
    int startIndex = m_bufferFull ? (m_currentIndex - recentCount + m_maxRecords) % m_maxRecords : 
                                   MathMax(0, m_currentIndex - recentCount);
    
    for(int i = 0; i < recentCount; i++)
    {
        int index = (startIndex + i) % m_maxRecords;
        if(m_predictions[index].outcomeTime > 0)
        {
            labeledCount++;
            if(m_predictions[index].predictionCorrect)
                recentCorrect++;
            recentReturn += m_predictions[index].actualReturn;
        }
    }
    
    if(labeledCount < 10) return;
    m_currentMetrics.recentAccuracy = (double)recentCorrect / labeledCount;
    m_currentMetrics.recentProfitability = recentReturn / labeledCount;
}

bool CAIPerformanceFeedback::ShouldRetrain(void)
{
    if(!m_initialized) return false;
    
    datetime currentTimeLocal = TimeCurrent();
    if(currentTimeLocal - m_lastRetrainingTime < m_retrainingInterval) return false;
    
    // Retraining stays silent below m_minPredictionsForRetraining scored predictions (default 50)
    if(m_currentMetrics.totalPredictions < m_minPredictionsForRetraining) return false;
    
    if(m_currentMetrics.recentAccuracy < m_minAccuracyThreshold)
    {
        LogFeedback(StringFormat("Retraining triggered: Recent accuracy %.2f%% below threshold %.2f%%", 
                                m_currentMetrics.recentAccuracy * 100, m_minAccuracyThreshold * 100));
        return true;
    }
    
    if(m_currentMetrics.recentProfitability < m_minProfitabilityThreshold)
    {
        LogFeedback(StringFormat("Retraining triggered: Recent profitability %.4f below threshold %.4f", 
                                m_currentMetrics.recentProfitability, m_minProfitabilityThreshold));
        return true;
    }
    
    if(IsPerformanceDegrading())
    {
        LogFeedback("Retraining triggered: Performance degradation detected");
        return true;
    }
    
    return false;
}

void CAIPerformanceFeedback::TriggerRetraining(const string reason)
{
    if(!m_initialized)
        return;

    // Skipped entirely while the retrain pause is active
    if(TimeCurrent() < m_retrainPauseUntil)
    {
        PrintFormat("[AI-RETRAIN-PAUSED] Retraining paused until %s - last %d attempts produced no improvement",
                    TimeToString(m_retrainPauseUntil), m_consecutiveFailedRetrains);
        return;
    }

    // Effectiveness check: runs only after a previous retrain and two metrics-update intervals
    if(m_retrainingCount > 0 && m_currentMetrics.totalPredictions > m_minPredictionsForRetraining)
    {
        double timeSinceLastRetrain = (double)(TimeCurrent() - m_lastRetrainingTime);
        if(timeSinceLastRetrain > m_metricsUpdateInterval * 2)  // Wait for at least 2 metric update cycles
        {
            bool metricsImproved = (m_currentMetrics.accuracy > m_preRetrainAccuracy + 0.001 ||
                                    m_currentMetrics.profitability > m_preRetrainProfitability + 0.0001 ||
                                    m_currentMetrics.sharpeRatio > m_preRetrainSharpe + 0.001);
            if(!metricsImproved)
            {
                m_consecutiveFailedRetrains++;
                if(m_consecutiveFailedRetrains >= 3)
                {
                    m_retrainPauseUntil = TimeCurrent() + 3600;  // 1 hour pause
                    PrintFormat("[AI-RETRAIN-PAUSED] 3 consecutive ineffective retrain attempts. Pausing for 1 hour.");
                    return;
                }
            }
            else
            {
                m_consecutiveFailedRetrains = 0;
            }
        }
    }

    m_lastRetrainingTime = TimeCurrent();
    m_retrainingCount++;
    m_lastRetrainingReason = reason;

    // Baseline for the next call's effectiveness check: taken here, after the check above has
    // read the previous one. UpdateMetrics() is throttled, so these are the last values computed.
    m_preRetrainAccuracy = m_currentMetrics.accuracy;
    m_preRetrainProfitability = m_currentMetrics.profitability;
    m_preRetrainSharpe = m_currentMetrics.sharpeRatio;

    PersistRetrainingRequest(reason);
    ExportLabeledDataset("AI_Retraining_Dataset.csv", 500);

    LogFeedback("AI model retraining triggered: " + reason);
    Print("[AI-RETRAIN] Triggered #", m_retrainingCount, " | Reason: ", reason);
    Print("[AI-RETRAIN] Metrics | Accuracy: ", DoubleToString(m_currentMetrics.accuracy * 100, 1),
          "% | Recent Accuracy: ", DoubleToString(m_currentMetrics.recentAccuracy * 100, 1),
          "% | Profitability: ", DoubleToString(m_currentMetrics.profitability, 4),
          " | Sharpe: ", DoubleToString(m_currentMetrics.sharpeRatio, 3));
}

bool CAIPerformanceFeedback::IsPerformanceDegrading(void)
{
    if(m_currentMetrics.totalPredictions < 100) return false; // Need enough data
    
    double accuracyDegradation = m_currentMetrics.accuracy - m_currentMetrics.recentAccuracy;
    double profitabilityDegradation = m_currentMetrics.profitability - m_currentMetrics.recentProfitability;
    
    // Degradation counts as significant when recent accuracy is 0.10 or recent profitability 0.01 below overall
    return (accuracyDegradation > 0.10 || profitabilityDegradation > 0.01);
}

int CAIPerformanceFeedback::FindPredictionIndex(const string &searchSymbol, const datetime predictionTime)
{
    int recordCount = m_bufferFull ? m_maxRecords : m_currentIndex;
    
    for(int i = 0; i < recordCount; i++)
    {
        if(m_predictions[i].symbol == searchSymbol &&
           MathAbs(m_predictions[i].predictionTime - predictionTime) <= 5)
        {
            return i;
        }
    }
    
    return -1; // Not found
}

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

double CAIPerformanceFeedback::CalculateSharpeRatio(void)
{
    if(m_currentMetrics.totalPredictions < 10) return 0.0;
    
    // Sharpe = mean return / sample stddev (count-1); 0.0 below 10 predictions or 2 labelled returns
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

string CAIPerformanceFeedback::GetPerformanceSummary(void)
{
    if(!m_initialized) return "AI feedback not initialized";
    
    return StringFormat("AI: Acc=%.1f%% | Prof=%.4f | Pred=%d | Retrain=%s",
                       m_currentMetrics.recentAccuracy * 100,
                       m_currentMetrics.recentProfitability,
                       m_currentMetrics.totalPredictions,
                       ShouldRetrain() ? "YES" : "NO");
}

void CAIPerformanceFeedback::CheckAutomaticRetraining(void)
{
    if(!m_initialized) return;

    // Refreshes metrics first, though the throttle can make that call a no-op
    UpdateMetrics();

    // Skipped while the retrain pause is active, same as TriggerRetraining()
    if(TimeCurrent() < m_retrainPauseUntil)
    {
        PrintFormat("[AI-RETRAIN-PAUSED] Retraining paused until %s - last %d attempts produced no improvement",
                    TimeToString(m_retrainPauseUntil), m_consecutiveFailedRetrains);
        return;
    }

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
    
    // Calibration error above m_calibrationErrorThreshold (0.3, never reassigned) is a fourth trigger
    if(m_currentMetrics.calibrationError > m_calibrationErrorThreshold)
    {
        needsRetraining = true;
        retrainingReason += "Poor calibration; ";
    }
    
    if(needsRetraining)
    {
        TriggerRetraining("Automatic trigger: " + retrainingReason);
    }
}

bool CAIPerformanceFeedback::ShouldRetrainBasedOnAccuracy(void)
{
    if(m_currentMetrics.totalPredictions < m_minPredictionsForRetraining) return false;
    
    if(m_currentMetrics.recentAccuracy < m_minAccuracyThreshold) return true;
    
    // With more than 100 scored predictions, recent accuracy 0.15 below overall also triggers
    if(m_currentMetrics.totalPredictions > 100)
    {
        double accuracyDrop = m_currentMetrics.accuracy - m_currentMetrics.recentAccuracy;
        if(accuracyDrop > 0.15) return true;
    }
    
    return false;
}

bool CAIPerformanceFeedback::ShouldRetrainBasedOnProfitability(void)
{
    if(m_currentMetrics.totalPredictions < m_minPredictionsForRetraining) return false;
    
    if(m_currentMetrics.recentProfitability < m_minProfitabilityThreshold) return true;
    
    // Sharpe below 0.3 triggers on its own, independent of the profitability check
    if(m_currentMetrics.sharpeRatio < 0.3) return true;
    
    return false;
}

// Clamped on assignment: accuracy into [0.3,0.9], profitability into [-0.1,0.5]
void CAIPerformanceFeedback::SetRetrainingThresholds(double minAccuracy, double minProfitability)
{
    m_minAccuracyThreshold = MathMax(0.3, MathMin(0.9, minAccuracy));
    m_minProfitabilityThreshold = MathMax(-0.1, MathMin(0.5, minProfitability));
    
    LogFeedback(StringFormat("Retraining thresholds updated: Accuracy=%.2f%%, Profitability=%.4f", 
                            m_minAccuracyThreshold * 100, m_minProfitabilityThreshold));
}

void CAIPerformanceFeedback::PersistRetrainingRequest(const string reason)
{
    string cleanReason = reason;
    StringReplace(cleanReason, ",", ";");
    StringReplace(cleanReason, "\r", " ");
    StringReplace(cleanReason, "\n", " ");

    string fileName = "AI_Retraining_Requests.csv";
    string tempFile = fileName + ".tmp";

    // Read the existing log verbatim so pending requests survive the rewrite.
    // The previous code opened the live file with FILE_READ | FILE_WRITE, which
    // truncates it ahead of writing back only the new row; a crash or write
    // failure between those steps lost every pending retraining request. We now
    // stage the full log in a temp file and atomically replace the original with
    // FileMove(FILE_REWRITE), the same approach as crash_recovery_helpers.mqh.
    uchar existing[];
    {
        int inHandle = FileOpen(fileName, FILE_READ | FILE_TXT | FILE_ANSI);
        if(inHandle != INVALID_HANDLE)
        {
            uchar buffer[];
            ArrayResize(buffer, 4096);
            while(!FileIsEnding(inHandle))
            {
                uint bytesRead = FileReadArray(inHandle, buffer, 0, 4096);
                if(bytesRead <= 0)
                    break;
                int old = ArraySize(existing);
                ArrayResize(existing, old + (int)bytesRead);
                ArrayCopy(existing, buffer, old, 0, (int)bytesRead);
            }
            FileClose(inHandle);
        }
    }

    bool writeHeader = (ArraySize(existing) == 0);

    string line = StringFormat("%s,%s,%d,%.6f,%.6f,%.6f\n",
                               TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
                               cleanReason,
                               m_currentMetrics.totalPredictions,
                               m_currentMetrics.recentAccuracy,
                               m_currentMetrics.recentProfitability,
                               m_currentMetrics.calibrationError);

    // Write the complete log to the temp file first. The original is never
    // truncated ahead of a successful write, so a crash cannot destroy the log.
    int handle = FileOpen(tempFile, FILE_WRITE | FILE_TXT | FILE_ANSI);
    if(handle == INVALID_HANDLE)
    {
        LogFeedback("Failed to open retraining request log: " + tempFile);
        return;
    }

    bool ok = true;
    if(writeHeader)
        ok = FileWriteString(handle, "timestamp,reason,total_predictions,recent_accuracy,recent_profitability,calibration_error\n") > 0;
    if(ok && ArraySize(existing) > 0)
        ok = FileWriteArray(handle, existing, 0, ArraySize(existing)) == ArraySize(existing);
    if(ok)
        ok = FileWriteString(handle, line) > 0;
    FileClose(handle);

    if(!ok)
    {
        FileDelete(tempFile, 0);
        return;
    }

    // FILE_REWRITE replaces the destination in one step, so the last good state
    // is never deleted ahead of a failed move. This terminal rejects FILE_REWRITE
    // (err 5020, measured in the live journal), so the fallback is the same one
    // crash recovery learned: remove the destination, then plain-move the temp.
    if(!FileMove(tempFile, FILE_REWRITE, fileName, 0))
    {
        int rewriteErr = GetLastError();
        if(FileIsExist(fileName, 0))
            FileDelete(fileName, 0);
        if(!FileMove(tempFile, 0, fileName, 0))
        {
            // Both failed. The temp file is the only complete copy, so keep it instead of deleting it.
            LogFeedback("Failed to promote temp retraining log: " + fileName +
                        " (rewriteErr=" + IntegerToString(rewriteErr) +
                        " moveErr=" + IntegerToString(GetLastError()) + ") - kept " + tempFile + " as the only copy");
        }
    }
}

// Writes the newest maxRows labelled records; FILE_WRITE truncates the previous export
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
    string tempFile = fileName + ".tmp";
    int handle = FileOpen(tempFile, FILE_WRITE | FILE_TXT | FILE_ANSI);
    if(handle == INVALID_HANDLE)
    {
        LogFeedback("Failed to export labeled dataset: " + tempFile);
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
    if(!FileMove(tempFile, FILE_REWRITE, fileName, 0))
    {
        LogFeedback("Failed to promote temp file: " + fileName + " (err=" + IntegerToString(GetLastError()) + ")");
        FileDelete(tempFile, 0);
    }
}

// Appends one metrics row per call to AI_Health_Dashboard.csv (FILE_READ|FILE_WRITE + seek to end)
void CAIPerformanceFeedback::PersistMetrics(void)
{
    PersistMetricsToCSV("AI_Health_Dashboard.csv");
}

void CAIPerformanceFeedback::PersistMetricsToCSV(const string filename)
{
    if(!m_initialized) return;
    
    int handle = FileOpen(filename, FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI);
    if(handle == INVALID_HANDLE)
    {
        LogFeedback("Failed to open metrics file: " + filename);
        return;
    }

    bool writeHeader = (FileSize(handle) == 0);
    FileSeek(handle, 0, SEEK_END);

    if(writeHeader)
    {
        if(FileWriteString(handle, "timestamp,total_predictions,correct_predictions,accuracy,recent_accuracy,precision,recall,f1_score,average_confidence,calibration_error,profitability,recent_profitability,sharpe_ratio,trending_accuracy,ranging_accuracy,volatile_accuracy,retraining_count,last_retraining_time,should_retrain") <= 0)
        {
            FileClose(handle);
            return;
        }
    }

    string line = StringFormat("%s,%d,%d,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%.6f,%d,%s,%s",
                               TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
                               m_currentMetrics.totalPredictions,
                               m_currentMetrics.correctPredictions,
                               m_currentMetrics.accuracy,
                               m_currentMetrics.recentAccuracy,
                               m_currentMetrics.precision,
                               m_currentMetrics.recall,
                               m_currentMetrics.f1Score,
                               m_currentMetrics.averageConfidence,
                               m_currentMetrics.calibrationError,
                               m_currentMetrics.profitability,
                               m_currentMetrics.recentProfitability,
                               m_currentMetrics.sharpeRatio,
                               m_currentMetrics.trendingAccuracy,
                               m_currentMetrics.rangingAccuracy,
                               m_currentMetrics.volatileAccuracy,
                               m_retrainingCount,
                               TimeToString(m_lastRetrainingTime),
                               ShouldRetrain() ? "YES" : "NO");
    
    if(FileWriteString(handle, line) <= 0)
    {
        FileClose(handle);
        return;
    }
    FileClose(handle);
}

#endif // CORE_AI_PERFORMANCE_FEEDBACK_MQH

