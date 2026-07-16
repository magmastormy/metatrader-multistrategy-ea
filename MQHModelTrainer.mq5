//+------------------------------------------------------------------+
//| MQHModelTrainer.mq5                                              |
//| Main training script for MQH neural network models                |
//+------------------------------------------------------------------+
#property copyright "MQH Model Training System"
#property link      "https://github.com/metatrader-multistrategy-ea"
#property version   "1.00"
#property script_show_inputs

input string symbolName = "EURUSD";
input ENUM_TIMEFRAMES g_timeframe = PERIOD_H1;
input string dataFile = "TrainingData_EURUSD_H1.csv";

input int g_epochs = 100;
input int g_batchSize = 32;
input double g_learningRate = 0.001;
input double l2Regularization = 0.001;

input int hiddenLayer1 = 32;
input int hiddenLayer2 = 16;
input int hiddenLayer3 = 8;

input int g_valRatio = 20;
input int g_testRatio = 10;

input bool enableVisualization = true;
input bool saveModel = true;

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
    Print("=== MQH Model Trainer ===");
    PrintFormat("Symbol: %s | Timeframe: %s", symbolName, EnumToString(g_timeframe));
    
    CCSVDataLoader dataLoader;
    CDataPreprocessor preprocessor;
    CLabelEncoder labelEncoder;
    CFeedForwardNN model;
    CTrainingSession trainer;
    CTrainingVisualizer visualizer;
    
    PrintFormat("[MQH-TRAINER] Loading data from: %s", dataFile);
    
    if(!dataLoader.Load(dataFile))
    {
        Print("[MQH-TRAINER] Failed to load data file");
        return;
    }
    
    int totalRows = dataLoader.GetTotalRowCount();
    PrintFormat("[MQH-TRAINER] Total rows loaded: %d", totalRows);
    
    if(totalRows == 0)
    {
        Print("[MQH-TRAINER] No data available");
        return;
    }
    
    double allFeatures[][FEATURE_VECTOR_SIZE];
    int labels[];
    int count = 0;
    
    if(!dataLoader.LoadAllRows(allFeatures, labels, count))
    {
        Print("[MQH-TRAINER] Failed to load rows");
        return;
    }
    
    PrintFormat("[MQH-TRAINER] Features loaded: %d samples x %d features", count, FEATURE_VECTOR_SIZE);
    
    preprocessor.SetSplitRatio(g_valRatio, g_testRatio);
    preprocessor.SplitData(allFeatures, labels, count);
    
    PrintFormat("[MQH-TRAINER] Split: Train=%d, Val=%d, Test=%d",
                preprocessor.GetTrainCount(),
                preprocessor.GetValCount(),
                preprocessor.GetTestCount());
    
    preprocessor.NormalizeData();
    Print("[MQH-TRAINER] Data normalized");
    
    if(!model.Initialize(hiddenLayer1, hiddenLayer2, hiddenLayer3))
    {
        Print("[MQH-TRAINER] Failed to initialize model");
        return;
    }
    
    model.SetLearningRate(g_learningRate);
    model.SetL2Regularization(l2Regularization);
    
    PrintFormat("[MQH-TRAINER] Model architecture: %d -> %d -> %d -> %d -> %d",
                FEATURE_VECTOR_SIZE,
                hiddenLayer1,
                hiddenLayer2,
                hiddenLayer3,
                3);
    
    STrainingConfig config;
    config.epochs = g_epochs;
    config.batchSize = g_batchSize;
    config.earlyStoppingPatience = 10;
    config.earlyStoppingMinDelta = 0.0001;
    config.logInterval = 10;
    config.enableVisualization = enableVisualization;
    
    trainer.SetConfig(config);
    
    double trainFeatures[][FEATURE_VECTOR_SIZE];
    int trainLabels[];
    preprocessor.GetTrainData(trainFeatures, trainLabels);

    double valFeatures[][FEATURE_VECTOR_SIZE];
    int valLabels[];
    preprocessor.GetValData(valFeatures, valLabels);
    
    Print("[MQH-TRAINER] Starting training...");
    
    trainer.Train(model, trainFeatures, trainLabels, preprocessor.GetTrainCount(),
                  valFeatures, valLabels, preprocessor.GetValCount());
    
    Print("[MQH-TRAINER] Training complete");
    
    CTrainingMetrics trainMetrics = trainer.GetTrainMetrics();
    CTrainingMetrics valMetrics = trainer.GetValMetrics();
    
    Print("\n=== Training Results ===");
    Print("--- Training Metrics ---");
    trainMetrics.PrintAllMetrics();
    
    Print("\n--- Validation Metrics ---");
    valMetrics.PrintAllMetrics();
    
    if(saveModel)
    {
        if(model.SaveCheckpoint(symbolName, g_timeframe))
            PrintFormat("[MQH-TRAINER] Model saved successfully for %s %s", symbolName, EnumToString(g_timeframe));
        else
            Print("[MQH-TRAINER] Failed to save model");
    }
    
    double testFeatures[][FEATURE_VECTOR_SIZE];
    int testLabels[];
    preprocessor.GetTestData(testFeatures, testLabels);
    
    if(preprocessor.GetTestCount() > 0)
    {
        Print("\n--- Testing on Holdout Set ---");
        
        double totalLoss = 0.0;
        int correct = 0;
        int confusionMatrix[3][3];
        ArrayInitialize(confusionMatrix, 0);
        
        for(int i = 0; i < preprocessor.GetTestCount(); i++)
        {
            double inputVec[];
            ArrayResize(inputVec, FEATURE_VECTOR_SIZE);
            for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
                inputVec[f] = testFeatures[i][f];

            int predictedClass;
            model.Predict(inputVec, predictedClass);

            int actualClass = labelEncoder.EncodeLabel(testLabels[i]);

            double outputs[];
            model.GetOutputs(inputVec, outputs);
            totalLoss += CNeuralCore::CrossEntropyLoss(outputs, 3, actualClass);
            
            if(predictedClass == actualClass)
                correct++;
            
            if(predictedClass >= 0 && predictedClass < 3 && actualClass >= 0 && actualClass < 3)
                confusionMatrix[actualClass][predictedClass]++;
        }
        
        double testAccuracy = (double)correct / (double)preprocessor.GetTestCount();
        double testLoss = totalLoss / (double)preprocessor.GetTestCount();
        
        PrintFormat("Test Accuracy: %.4f", testAccuracy);
        PrintFormat("Test Loss: %.6f", testLoss);
        
        CTrainingMetrics testMetrics;
        testMetrics.UpdateMetrics(confusionMatrix, 3, testLoss, preprocessor.GetTestCount());
        testMetrics.PrintConfusionMatrix();
        
        string reportFile = StringFormat("ModelReport_%s_%s_%s.txt",
                                         symbolName,
                                         EnumToString(g_timeframe),
                                         TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES));
        testMetrics.SaveMetrics(reportFile);
        
        PrintFormat("[MQH-TRAINER] Test report saved to: %s", reportFile);
    }
    
    Print("\n=== MQH Model Training Complete ===");
}
