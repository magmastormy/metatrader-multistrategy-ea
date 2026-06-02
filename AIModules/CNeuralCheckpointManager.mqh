//+------------------------------------------------------------------+
//| CCheckpointManager.mqh                                            |
//| Handles atomic checkpoint save/load for neural network           |
//+------------------------------------------------------------------+
#ifndef __NEURAL_CHECKPOINT_MANAGER_MQH__
#define __NEURAL_CHECKPOINT_MANAGER_MQH__

#include "CNeuralCore.mqh"
#include "../Core/AI/NNModelStorage.mqh"
#include "CNeuralTrainingDataManager.mqh"

// Checkpoint version and magic constants
#ifndef NN_CHECKPOINT_VERSION
#define NN_CHECKPOINT_VERSION 1
#endif
#ifndef NN_CHECKPOINT_MAGIC
#define NN_CHECKPOINT_MAGIC 0x4E455552  // "NEUR" in hex
#endif

class CCheckpointManager
{
private:
    string m_symbol;
    ENUM_TIMEFRAMES m_timeframe;
    int m_version;
    int m_magic;
    datetime m_lastLoadTime;
    datetime m_lastSaveTime;
    string m_lastLoadStatus;

public:
    CCheckpointManager(const string symbol = "", const ENUM_TIMEFRAMES tf = PERIOD_CURRENT)
    {
        m_symbol = symbol;
        m_timeframe = tf;
        m_version = NN_CHECKPOINT_VERSION;
        m_magic = NN_CHECKPOINT_MAGIC;
        m_lastLoadTime = 0;
        m_lastSaveTime = 0;
        m_lastLoadStatus = "NOT_LOADED";
    }

    void SetSymbol(const string symbol, const ENUM_TIMEFRAMES tf)
    {
        m_symbol = symbol;
        m_timeframe = tf;
    }

    string GetLastLoadStatus() const { return m_lastLoadStatus; }
    datetime GetLastLoadTime() const { return m_lastLoadTime; }
    datetime GetLastSaveTime() const { return m_lastSaveTime; }

private:
    // Helper methods for checkpoint I/O
    void WriteCheckpointString(const int fh, const string str)
    {
        FileWriteInteger(fh, StringLen(str));
        if(StringLen(str) > 0)
            FileWriteString(fh, str, StringLen(str));
    }
    
    string ReadCheckpointString(const int fh)
    {
        int len = FileReadInteger(fh);
        if(len <= 0 || len > 1024)
            return "";
        return FileReadString(fh, len);
    }

public:

    bool SaveCheckpoint(const double &W1[][], const double &W2[][], const double &W3[][], const double &W4[][],
                       const double &B1[], const double &B2[], const double &B3[], const double &B4[],
                       const double &adamM[], const double &adamV[], const long adamStep,
                       const double &featureMean[], const double &featureM2[], const long featureCount,
                       const bool normalizationReady, const datetime checkpointTime,
                       const bool onlineTraining, const bool selfLabeling,
                       const int sampleInterval, const int checkpointEvery,
                       const int epoch, const double lastLoss, const int trainingSteps,
                       const int checkpointWrites, const int totalObs, const int tradeLinked,
                       const double temperature,
                       const SMTrainingExample &trainingBuffer[], const int trainCount, const int trainHead,
                       const SMBarrierEntry &barrierBuffer[], const int barrierCount, const int barrierHead,
                       CTrainingDataManager* dataManager)
    {
        NNModelStorage_EnsureFolders();
        string tempFile = NNModelStorage_GetTempPath(m_symbol, m_timeframe, m_version);
        string primaryFile = NNModelStorage_GetPrimaryPath(m_symbol, m_timeframe, m_version);
        string backupFile = NNModelStorage_GetBackupPath(m_symbol, m_timeframe, m_version);

        int fh = FileOpen(tempFile, FILE_WRITE | FILE_BIN | FILE_COMMON);
        if(fh == INVALID_HANDLE)
        {
            m_lastLoadStatus = "TEMP_FILE_OPEN_FAILED";
            return false;
        }

        FileWriteInteger(fh, m_magic);
        FileWriteInteger(fh, m_version);
        WriteCheckpointString(fh, m_symbol);
        FileWriteInteger(fh, (int)m_timeframe);
        FileWriteLong(fh, (long)checkpointTime);
        FileWriteInteger(fh, onlineTraining ? 1 : 0);
        FileWriteInteger(fh, selfLabeling ? 1 : 0);
        FileWriteInteger(fh, sampleInterval);
        FileWriteInteger(fh, checkpointEvery);
        FileWriteInteger(fh, epoch);
        FileWriteDouble(fh, lastLoss);
        FileWriteInteger(fh, trainingSteps);
        FileWriteInteger(fh, checkpointWrites);
        FileWriteInteger(fh, totalObs);
        FileWriteInteger(fh, tradeLinked);
        FileWriteLong(fh, dataManager != NULL ? dataManager.GetBarrierResolvedCount() : 0);
        FileWriteLong(fh, featureCount);
        FileWriteInteger(fh, normalizationReady ? 1 : 0);
        FileWriteLong(fh, adamStep);

        for(int i = 0; i < ArraySize(featureMean) && i < FEATURE_VECTOR_SIZE; i++)
            FileWriteDouble(fh, featureMean[i]);
        for(int i = 0; i < ArraySize(featureM2) && i < FEATURE_VECTOR_SIZE; i++)
            FileWriteDouble(fh, featureM2[i]);

        for(int i = 0; i < ArraySize(adamM); i++)
        {
            FileWriteDouble(fh, adamM[i]);
            FileWriteDouble(fh, adamV[i]);
        }

        for(int i = 0; i < ArrayRange(W1, 0); i++)
            for(int j = 0; j < ArrayRange(W1, 1); j++)
                FileWriteDouble(fh, W1[i][j]);
        for(int i = 0; i < ArrayRange(W2, 0); i++)
            for(int j = 0; j < ArrayRange(W2, 1); j++)
                FileWriteDouble(fh, W2[i][j]);
        for(int i = 0; i < ArrayRange(W3, 0); i++)
            for(int j = 0; j < ArrayRange(W3, 1); j++)
                FileWriteDouble(fh, W3[i][j]);
        for(int i = 0; i < ArrayRange(W4, 0); i++)
            for(int j = 0; j < ArrayRange(W4, 1); j++)
                FileWriteDouble(fh, W4[i][j]);

        for(int i = 0; i < ArraySize(B1); i++) FileWriteDouble(fh, B1[i]);
        for(int i = 0; i < ArraySize(B2); i++) FileWriteDouble(fh, B2[i]);
        for(int i = 0; i < ArraySize(B3); i++) FileWriteDouble(fh, B3[i]);
        for(int i = 0; i < ArraySize(B4); i++) FileWriteDouble(fh, B4[i]);

        FileWriteInteger(fh, trainCount);
        int persistingCount = MathMin(trainCount, NN_MAX_TRAINING_EXAMPLES);
        for(int i = 0; i < persistingCount; i++)
        {
            int idx = (trainHead - persistingCount + i + NN_MAX_TRAINING_EXAMPLES) % NN_MAX_TRAINING_EXAMPLES;
            if(idx >= 0 && idx < NN_MAX_TRAINING_EXAMPLES && i < ArraySize(trainingBuffer))
            {
                FileWriteInteger(fh, trainingBuffer[idx].labelClass);
                FileWriteLong(fh, (long)trainingBuffer[idx].time);
                FileWriteInteger(fh, trainingBuffer[idx].linkedToTrade ? 1 : 0);
                WriteCheckpointString(fh, trainingBuffer[idx].predictionId);
                FileWriteDouble(fh, trainingBuffer[idx].signalConfidence);
                for(int j = 0; j < FEATURE_VECTOR_SIZE; j++)
                    FileWriteDouble(fh, trainingBuffer[idx].inputs[j]);
                for(int j = 0; j < ML_INPUT; j++)
                    FileWriteDouble(fh, trainingBuffer[idx].metaInput[j]);
            }
        }

        FileWriteInteger(fh, barrierCount);
        for(int i = 0; i < MathMin(barrierCount, NN_MAX_PERSISTED_SAMPLES) && i < ArraySize(barrierBuffer); i++)
        {
            FileWriteInteger(fh, barrierBuffer[i].signalClass);
            FileWriteDouble(fh, barrierBuffer[i].entryPrice);
            FileWriteDouble(fh, barrierBuffer[i].upperBarrier);
            FileWriteDouble(fh, barrierBuffer[i].lowerBarrier);
            FileWriteLong(fh, (long)barrierBuffer[i].expiryTime);
            FileWriteInteger(fh, barrierBuffer[i].featureSize);
            FileWriteInteger(fh, barrierBuffer[i].label);
            FileWriteInteger(fh, barrierBuffer[i].resolved ? 1 : 0);
            WriteCheckpointString(fh, barrierBuffer[i].predictionId);
            FileWriteInteger(fh, barrierBuffer[i].linkedToTrade ? 1 : 0);
            FileWriteDouble(fh, barrierBuffer[i].signalConfidence);
            FileWriteLong(fh, (long)barrierBuffer[i].entryBarTime);
            for(int j = 0; j < FEATURE_VECTOR_SIZE; j++)
                FileWriteDouble(fh, barrierBuffer[i].featureSnapshot[j]);
            for(int j = 0; j < ML_INPUT; j++)
                FileWriteDouble(fh, barrierBuffer[i].metaInput[j]);
        }

        FileClose(fh);
        if(!NNModelStorage_PromoteTempToPrimary(tempFile, primaryFile, backupFile))
        {
            m_lastLoadStatus = "ATOMIC_PROMOTE_FAILED";
            return false;
        }

        m_lastSaveTime = TimeCurrent();
        m_lastLoadStatus = "SAVED";
        return true;
    }

    bool LoadCheckpoint(double &W1[][], double &W2[][], double &W3[][], double &W4[][],
                       double &B1[], double &B2[], double &B3[], double &B4[],
                       double &adamM[], double &adamV[], long &adamStep,
                       double &featureMean[], double &featureM2[], long &featureCount,
                       bool &normalizationReady, datetime &checkpointTime,
                       bool &onlineTraining, bool &selfLabeling,
                       int &sampleInterval, int &checkpointEvery,
                       int &epoch, double &lastLoss, int &trainingSteps,
                       int &checkpointWrites, int &totalObs, int &tradeLinked,
                       double &temperature,
                       SMTrainingExample &trainingBuffer[], int &trainCount, int &trainHead,
                       SMBarrierEntry &barrierBuffer[], int &barrierCount, int &barrierHead,
                       CTrainingDataManager* dataManager)
    {
        NNModelStorage_EnsureFolders();
        string primaryFile = NNModelStorage_GetPrimaryPath(m_symbol, m_timeframe, m_version);
        if(!FileIsExist(primaryFile, FILE_COMMON))
        {
            m_lastLoadStatus = "FILE_NOT_FOUND";
            return false;
        }

        int fh = FileOpen(primaryFile, FILE_READ | FILE_BIN | FILE_COMMON);
        if(fh == INVALID_HANDLE)
        {
            m_lastLoadStatus = "FILE_OPEN_FAILED";
            return false;
        }

        int magic = FileReadInteger(fh);
        int version = FileReadInteger(fh);
        string symbol = ReadCheckpointString(fh);
        if(magic != m_magic || version != m_version || symbol == "")
        {
            FileClose(fh);
            m_lastLoadStatus = "INVALID_HEADER";
            return false;
        }

        int timeframe = FileReadInteger(fh);
        if(symbol != m_symbol || timeframe != (int)m_timeframe)
        {
            FileClose(fh);
            m_lastLoadStatus = "SYMBOL_MISMATCH";
            return false;
        }

        checkpointTime = (datetime)FileReadLong(fh);
        onlineTraining = (FileReadInteger(fh) != 0);
        selfLabeling = (FileReadInteger(fh) != 0);
        sampleInterval = FileReadInteger(fh);
        checkpointEvery = FileReadInteger(fh);
        epoch = FileReadInteger(fh);
        lastLoss = FileReadDouble(fh);
        trainingSteps = FileReadInteger(fh);
        checkpointWrites = FileReadInteger(fh);
        totalObs = FileReadInteger(fh);
        tradeLinked = FileReadInteger(fh);
        long resolvedCount = FileReadLong(fh);
        featureCount = FileReadLong(fh);
        normalizationReady = (FileReadInteger(fh) != 0);
        adamStep = FileReadLong(fh);

        for(int i = 0; i < ArraySize(featureMean) && i < FEATURE_VECTOR_SIZE; i++)
            featureMean[i] = FileReadDouble(fh);
        for(int i = 0; i < ArraySize(featureM2) && i < FEATURE_VECTOR_SIZE; i++)
            featureM2[i] = FileReadDouble(fh);

        int adamCount = ArraySize(adamM);
        for(int i = 0; i < adamCount; i++)
        {
            adamM[i] = FileReadDouble(fh);
            adamV[i] = FileReadDouble(fh);
        }

        for(int i = 0; i < ArrayRange(W1, 0); i++)
            for(int j = 0; j < ArrayRange(W1, 1); j++)
                W1[i][j] = FileReadDouble(fh);
        for(int i = 0; i < ArrayRange(W2, 0); i++)
            for(int j = 0; j < ArrayRange(W2, 1); j++)
                W2[i][j] = FileReadDouble(fh);
        for(int i = 0; i < ArrayRange(W3, 0); i++)
            for(int j = 0; j < ArrayRange(W3, 1); j++)
                W3[i][j] = FileReadDouble(fh);
        for(int i = 0; i < ArrayRange(W4, 0); i++)
            for(int j = 0; j < ArrayRange(W4, 1); j++)
                W4[i][j] = FileReadDouble(fh);

        for(int i = 0; i < ArraySize(B1); i++) B1[i] = FileReadDouble(fh);
        for(int i = 0; i < ArraySize(B2); i++) B2[i] = FileReadDouble(fh);
        for(int i = 0; i < ArraySize(B3); i++) B3[i] = FileReadDouble(fh);
        for(int i = 0; i < ArraySize(B4); i++) B4[i] = FileReadDouble(fh);

        trainCount = MathMin(FileReadInteger(fh), NN_MAX_TRAINING_EXAMPLES);
        trainHead = trainCount % NN_MAX_TRAINING_EXAMPLES;
        for(int i = 0; i < NN_MAX_TRAINING_EXAMPLES; i++)
            trainingBuffer[i].Reset();
        for(int i = 0; i < trainCount; i++)
        {
            trainingBuffer[i].labelClass = FileReadInteger(fh);
            trainingBuffer[i].time = (datetime)FileReadLong(fh);
            trainingBuffer[i].linkedToTrade = (FileReadInteger(fh) != 0);
            trainingBuffer[i].predictionId = ReadCheckpointString(fh);
            trainingBuffer[i].signalConfidence = FileReadDouble(fh);
            for(int j = 0; j < FEATURE_VECTOR_SIZE; j++)
                trainingBuffer[i].inputs[j] = FileReadDouble(fh);
            for(int j = 0; j < ML_INPUT; j++)
                trainingBuffer[i].metaInput[j] = FileReadDouble(fh);
        }

        barrierCount = MathMin(FileReadInteger(fh), NN_MAX_PERSISTED_SAMPLES);
        barrierHead = barrierCount;
        for(int i = 0; i < NN_MAX_PERSISTED_SAMPLES; i++)
            barrierBuffer[i].Reset();
        for(int i = 0; i < barrierCount; i++)
        {
            barrierBuffer[i].signalClass = FileReadInteger(fh);
            barrierBuffer[i].entryPrice = FileReadDouble(fh);
            barrierBuffer[i].upperBarrier = FileReadDouble(fh);
            barrierBuffer[i].lowerBarrier = FileReadDouble(fh);
            barrierBuffer[i].expiryTime = (datetime)FileReadLong(fh);
            barrierBuffer[i].featureSize = FileReadInteger(fh);
            barrierBuffer[i].label = FileReadInteger(fh);
            barrierBuffer[i].resolved = (FileReadInteger(fh) != 0);
            barrierBuffer[i].predictionId = ReadCheckpointString(fh);
            barrierBuffer[i].linkedToTrade = (FileReadInteger(fh) != 0);
            barrierBuffer[i].signalConfidence = FileReadDouble(fh);
            barrierBuffer[i].entryBarTime = (datetime)FileReadLong(fh);
            for(int j = 0; j < FEATURE_VECTOR_SIZE; j++)
                barrierBuffer[i].featureSnapshot[j] = FileReadDouble(fh);
            for(int j = 0; j < ML_INPUT; j++)
                barrierBuffer[i].metaInput[j] = FileReadDouble(fh);
        }

        FileClose(fh);
        m_lastLoadTime = TimeCurrent();
        m_lastLoadStatus = "LOADED";
        return true;
    }

    bool Exists() const
    {
        NNModelStorage_EnsureFolders();
        string primaryFile = NNModelStorage_GetPrimaryPath(m_symbol, m_timeframe, m_version);
        return FileIsExist(primaryFile, FILE_COMMON);
    }
};

#endif // __NEURAL_CHECKPOINT_MANAGER_MQH__
