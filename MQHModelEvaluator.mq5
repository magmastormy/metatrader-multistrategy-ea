//+------------------------------------------------------------------+
//| MQHModelEvaluator.mq5                                            |
//| Evaluation script for trained MQH models                          |
//+------------------------------------------------------------------+
#property copyright "MQH Model Training System"
#property link      "https://github.com/metatrader-multistrategy-ea"
#property version   "1.00"
#property script_show_inputs

input string symbolName = "EURUSD";
input ENUM_TIMEFRAMES timeframe = PERIOD_H1;
input string dataFile = "TrainingData_EURUSD_H1.csv";

input int testRatio = 30;

#include "MQHModelTrainer/Core/AI/AIFeatureVectorBuilder.mqh"
#include "MQHModelTrainer/AIModules/AIConfig.mqh"
#include "MQHModelTrainer/Data/CSVDataLoader.mqh"
#include "MQHModelTrainer/Data/DataPreprocessor.mqh"
#include "MQHModelTrainer/Data/LabelEncoder.mqh"
#include "MQHModelTrainer/Core/TrainingMetrics.mqh"
#include "MQHModelTrainer/Models/FeedForwardNN.mqh"
#include "MQHModelTrainer/Models/ModelEvaluator.mqh"

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("=== MQH Model Evaluator ===");
    PrintFormat("Symbol: %s | Timeframe: %s", symbolName, EnumToString(timeframe));
    
    CCSVDataLoader dataLoader;
    CDataPreprocessor preprocessor;
    CModelEvaluator evaluator;
    
    PrintFormat("[MQH-EVAL] Loading data from: %s", dataFile);
    
    if(!dataLoader.Load(dataFile))
    {
        Print("[MQH-EVAL] Failed to load data file");
        return;
    }
    
    int totalRows = dataLoader.GetTotalRowCount();
    PrintFormat("[MQH-EVAL] Total rows loaded: %d", totalRows);
    
    if(totalRows == 0)
    {
        Print("[MQH-EVAL] No data available");
        return;
    }
    
    double allFeatures[][];
    int labels[];
    int count = 0;
    
    if(!dataLoader.LoadAllRows(allFeatures, labels, count))
    {
        Print("[MQH-EVAL] Failed to load rows");
        return;
    }
    
    preprocessor.SetSplitRatio(0, testRatio);
    preprocessor.SplitData(allFeatures, labels, count);
    
    preprocessor.NormalizeData();
    Print("[MQH-EVAL] Data normalized");
    
    if(!evaluator.LoadModel(symbolName, timeframe))
    {
        Print("[MQH-EVAL] Failed to load model");
        return;
    }
    
    double testFeatures[][];
    int testLabels[];
    preprocessor.GetTestData(testFeatures, testLabels);
    
    int testCount = preprocessor.GetTestCount();
    PrintFormat("[MQH-EVAL] Evaluating on %d test samples", testCount);
    
    string metricsFile = StringFormat("EvaluationMetrics_%s_%s_%s.txt",
                                      symbolName,
                                      EnumToString(timeframe),
                                      TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES));
    
    if(evaluator.Evaluate(testFeatures, testLabels, testCount, metricsFile))
    {
        Print("[MQH-EVAL] Evaluation completed successfully");
        
        evaluator.EvaluateWithConfidence(testFeatures, testLabels, testCount);
        
        string reportFile = StringFormat("EvaluationReport_%s_%s_%s.txt",
                                         symbolName,
                                         EnumToString(timeframe),
                                         TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES));
        
        evaluator.GenerateReport(reportFile);
        
        PrintFormat("[MQH-EVAL] Reports saved to: %s and %s", metricsFile, reportFile);
    }
    else
    {
        Print("[MQH-EVAL] Evaluation failed");
    }
    
    Print("\n=== MQH Model Evaluation Complete ===");
}
