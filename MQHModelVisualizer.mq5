//+------------------------------------------------------------------+
//| MQHModelVisualizer.mq5                                           |
//| Visualization script for training results                         |
//+------------------------------------------------------------------+
#property copyright "MQH Model Training System"
#property link      "https://github.com/metatrader-multistrategy-ea"
#property version   "1.00"
#property script_show_inputs

input string symbolName = "EURUSD";
input ENUM_TIMEFRAMES g_timeframe = PERIOD_H1;
input string dataFile = "TrainingData_EURUSD_H1.csv";

input int g_epochs = 50;
input int g_batchSize = 32;
input double g_learningRate = 0.001;
input double l2Regularization = 0.001;

input int hiddenLayer1 = 32;
input int hiddenLayer2 = 16;
input int hiddenLayer3 = 8;

input int g_valRatio = 20;
input int g_testRatio = 10;

input bool saveChartImage = true;

#include "Core/AI/AIFeatureVectorBuilder.mqh"
#include "AIModules/AIConfig.mqh"
#include "MQHModelTrainer/Data/CSVDataLoader.mqh"
#include "MQHModelTrainer/Data/DataPreprocessor.mqh"
#include "MQHModelTrainer/Data/LabelEncoder.mqh"
#include "MQHModelTrainer/Core/TrainingMetrics.mqh"
#include "MQHModelTrainer/Core/TrainingVisualizer.mqh"
#include "MQHModelTrainer/Models/FeedForwardNN.mqh"
#include "MQHModelTrainer/Models/TrainingSession.mqh"

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("=== MQH Model Visualizer ===");
    PrintFormat("Symbol: %s | Timeframe: %s", symbolName, EnumToString(g_timeframe));
    
    CCSVDataLoader dataLoader;
    CDataPreprocessor preprocessor;
    CLabelEncoder labelEncoder;
    CFeedForwardNN model;
    CTrainingSession trainer;
    CTrainingVisualizer visualizer;
    
    if(!visualizer.Initialize())
    {
        Print("[MQH-VIZ] Failed to initialize visualizer");
        return;
    }
    
    PrintFormat("[MQH-VIZ] Loading data from: %s", dataFile);
    
    if(!dataLoader.Load(dataFile))
    {
        Print("[MQH-VIZ] Failed to load data file");
        visualizer.Shutdown();
        return;
    }
    
    int totalRows = dataLoader.GetTotalRowCount();
    PrintFormat("[MQH-VIZ] Total rows loaded: %d", totalRows);
    
    if(totalRows == 0)
    {
        Print("[MQH-VIZ] No data available");
        visualizer.Shutdown();
        return;
    }
    
    double allFeatures[][FEATURE_VECTOR_SIZE];
    int labels[];
    int count = 0;
    
    if(!dataLoader.LoadAllRows(allFeatures, labels, count))
    {
        Print("[MQH-VIZ] Failed to load rows");
        visualizer.Shutdown();
        return;
    }
    
    preprocessor.SetSplitRatio(g_valRatio, g_testRatio);
    preprocessor.SplitData(allFeatures, labels, count);
    preprocessor.NormalizeData();
    
    if(!model.Initialize(hiddenLayer1, hiddenLayer2, hiddenLayer3))
    {
        Print("[MQH-VIZ] Failed to initialize model");
        visualizer.Shutdown();
        return;
    }
    
    model.SetLearningRate(g_learningRate);
    model.SetL2Regularization(l2Regularization);
    
    STrainingConfig config;
    config.epochs = g_epochs;
    config.batchSize = g_batchSize;
    config.earlyStoppingPatience = 10;
    config.earlyStoppingMinDelta = 0.0001;
    config.logInterval = 5;
    config.enableVisualization = true;
    
    trainer.SetConfig(config);
    trainer.SetVisualizer(visualizer);
    
    double trainFeatures[][FEATURE_VECTOR_SIZE];
    int trainLabels[];
    preprocessor.GetTrainData(trainFeatures, trainLabels);

    double valFeatures[][FEATURE_VECTOR_SIZE];
    int valLabels[];
    preprocessor.GetValData(valFeatures, valLabels);
    
    Print("[MQH-VIZ] Starting training with visualization...");
    
    trainer.Train(model, trainFeatures, trainLabels, preprocessor.GetTrainCount(),
                  valFeatures, valLabels, preprocessor.GetValCount());
    
    Print("[MQH-VIZ] Training complete");
    
    CTrainingMetrics trainMetrics = trainer.GetTrainMetrics();
    CTrainingMetrics valMetrics = trainer.GetValMetrics();
    
    visualizer.ShowMetricsTable(valMetrics.GetAccuracy(),
                                valMetrics.GetPrecision(),
                                valMetrics.GetRecall(),
                                valMetrics.GetF1Score(),
                                valMetrics.GetLoss());
    
    int confusionMatrix[3][3];
    valMetrics.GetConfusionMatrix(confusionMatrix);
    visualizer.DrawConfusionMatrix(confusionMatrix);
    
    if(saveChartImage)
    {
        string imageFile = StringFormat("TrainingChart_%s_%s_%s.png",
                                        symbolName,
                                        EnumToString(g_timeframe),
                                        TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES));
        
        visualizer.SaveChartImage(imageFile);
    }
    
    Print("\n=== Final Metrics ===");
    valMetrics.PrintAllMetrics();
    valMetrics.PrintConfusionMatrix();
    
    Print("\n=== MQH Model Visualization Complete ===");
    Print("[MQH-VIZ] Chart will remain open for review");
}
