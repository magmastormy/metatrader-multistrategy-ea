//+------------------------------------------------------------------+
//| MQHHyperparameterTuner.mq5                                       |
//| Hyperparameter tuning script for MQH models                       |
//+------------------------------------------------------------------+
#property copyright "MQH Model Training System"
#property link      "https://github.com/metatrader-multistrategy-ea"
#property version   "1.00"
#property script_show_inputs

input string symbolName = "EURUSD";
input ENUM_TIMEFRAMES timeframe = PERIOD_H1;
input string dataFile = "TrainingData_EURUSD_H1.csv";

input int valRatio = 20;
input int testRatio = 10;

input bool useDefaultCandidates = true;

#include "MQHModelTrainer/Core/AI/AIFeatureVectorBuilder.mqh"
#include "MQHModelTrainer/AIModules/AIConfig.mqh"
#include "MQHModelTrainer/Core/HyperparameterOptimizer.mqh"

//+------------------------------------------------------------------+
//| Script program start function                                    |
//+------------------------------------------------------------------+
void OnStart()
{
    Print("=== MQH Hyperparameter Tuner ===");
    PrintFormat("Symbol: %s | Timeframe: %s", symbolName, EnumToString(timeframe));
    
    CHyperparameterOptimizer tuner;
    
    if(useDefaultCandidates)
    {
        tuner.AddDefaultCandidates();
    }
    else
    {
        SHyperparameterSet customCandidate;
        customCandidate.learningRate = 0.001;
        customCandidate.batchSize = 32;
        customCandidate.l2Regularization = 0.001;
        customCandidate.hiddenLayer1Size = 32;
        customCandidate.hiddenLayer2Size = 16;
        customCandidate.hiddenLayer3Size = 8;
        customCandidate.epochs = 100;
        customCandidate.name = "Custom_Default";
        
        tuner.AddCandidate(customCandidate);
    }
    
    PrintFormat("[MQH-TUNER] Starting hyperparameter tuning with %d candidates", tuner.GetResultCount());
    
    if(tuner.RunTuning(symbolName, timeframe, dataFile, valRatio, testRatio))
    {
        SHyperparameterSet bestParams = tuner.GetBestParameters();
        
        Print("\n=== Best Parameters ===");
        PrintFormat("Name: %s", bestParams.name);
        PrintFormat("Learning Rate: %.6f", bestParams.learningRate);
        PrintFormat("Batch Size: %d", bestParams.batchSize);
        PrintFormat("L2 Regularization: %.6f", bestParams.l2Regularization);
        PrintFormat("Hidden Layers: %d -> %d -> %d",
                    bestParams.hiddenLayer1Size,
                    bestParams.hiddenLayer2Size,
                    bestParams.hiddenLayer3Size);
        PrintFormat("Epochs: %d", bestParams.epochs);
        
        string resultsFile = StringFormat("HyperparameterResults_%s_%s_%s.csv",
                                          symbolName,
                                          EnumToString(timeframe),
                                          TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES));
        
        tuner.SaveResults(resultsFile);
        
        PrintFormat("[MQH-TUNER] Tuning results saved to: %s", resultsFile);
        
        string bestParamsFile = StringFormat("BestParameters_%s_%s_%s.txt",
                                             symbolName,
                                             EnumToString(timeframe),
                                             TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES));
        
        int fh = FileOpen(bestParamsFile, FILE_WRITE | FILE_COMMON);
        if(fh != INVALID_HANDLE)
        {
            FileWriteString(fh, "=== Best Hyperparameters ===\r\n");
            FileWriteString(fh, StringFormat("Generated: %s\r\n", TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS)));
            FileWriteString(fh, StringFormat("Symbol: %s\r\n", symbolName));
            FileWriteString(fh, StringFormat("Timeframe: %s\r\n\r\n", EnumToString(timeframe)));
            FileWriteString(fh, StringFormat("learningRate=%.6f\r\n", bestParams.learningRate));
            FileWriteString(fh, StringFormat("batchSize=%d\r\n", bestParams.batchSize));
            FileWriteString(fh, StringFormat("l2Regularization=%.6f\r\n", bestParams.l2Regularization));
            FileWriteString(fh, StringFormat("hiddenLayer1=%d\r\n", bestParams.hiddenLayer1Size));
            FileWriteString(fh, StringFormat("hiddenLayer2=%d\r\n", bestParams.hiddenLayer2Size));
            FileWriteString(fh, StringFormat("hiddenLayer3=%d\r\n", bestParams.hiddenLayer3Size));
            FileWriteString(fh, StringFormat("epochs=%d\r\n", bestParams.epochs));
            FileClose(fh);
            
            PrintFormat("[MQH-TUNER] Best parameters saved to: %s", bestParamsFile);
        }
    }
    else
    {
        Print("[MQH-TUNER] Hyperparameter tuning failed");
    }
    
    Print("\n=== MQH Hyperparameter Tuning Complete ===");
}
