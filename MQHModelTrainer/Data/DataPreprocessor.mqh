//+------------------------------------------------------------------+
//| DataPreprocessor.mqh                                             |
//| Data preprocessing utilities: normalization, splitting, encoding |
//+------------------------------------------------------------------+
#ifndef MQH_DATA_PREPROCESSOR_MQH
#define MQH_DATA_PREPROCESSOR_MQH

#include "../Core/AI/AIFeatureVectorBuilder.mqh"
#include "LabelEncoder.mqh"

class CDataPreprocessor
{
private:
    double m_featureMean[];
    double m_featureStd[];
    double m_featureMin[];
    double m_featureMax[];
    bool m_normalizationFit;
    ENUM_NORMALIZATION_TYPE m_normType;
    
public:
    CDataPreprocessor() : m_normalizationFit(false), m_normType(NORM_ZSCORE)
    {
        ArrayResize(m_featureMean, FEATURE_VECTOR_SIZE);
        ArrayResize(m_featureStd, FEATURE_VECTOR_SIZE);
        ArrayResize(m_featureMin, FEATURE_VECTOR_SIZE);
        ArrayResize(m_featureMax, FEATURE_VECTOR_SIZE);
        ArrayInitialize(m_featureMean, 0.0);
        ArrayInitialize(m_featureStd, 1.0);
        ArrayInitialize(m_featureMin, 0.0);
        ArrayInitialize(m_featureMax, 1.0);
    }
    
    void SetNormalizationType(ENUM_NORMALIZATION_TYPE type)
    {
        m_normType = type;
    }
    
    bool FitNormalization(const double &features[][], const int rowCount)
    {
        if(rowCount == 0) return false;
        
        for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
        {
            double sum = 0.0;
            double sumSq = 0.0;
            m_featureMin[f] = features[0][f];
            m_featureMax[f] = features[0][f];
            
            for(int r = 0; r < rowCount; r++)
            {
                double val = features[r][f];
                sum += val;
                sumSq += val * val;
                m_featureMin[f] = MathMin(m_featureMin[f], val);
                m_featureMax[f] = MathMax(m_featureMax[f], val);
            }
            
            double mean = sum / (double)rowCount;
            m_featureMean[f] = mean;
            
            double variance = (sumSq / (double)rowCount) - (mean * mean);
            m_featureStd[f] = MathSqrt(MathMax(variance, 1e-10));
        }
        
        m_normalizationFit = true;
        PrintFormat("[MQH-TRAIN] Normalization fitted on %d rows", rowCount);
        return true;
    }
    
    void TransformNormalization(double &features[], const int rowCount)
    {
        if(!m_normalizationFit) return;
        
        for(int r = 0; r < rowCount; r++)
        {
            for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
            {
                if(m_normType == NORM_ZSCORE)
                {
                    features[r][f] = (features[r][f] - m_featureMean[f]) / m_featureStd[f];
                }
                else
                {
                    double range = m_featureMax[f] - m_featureMin[f];
                    if(range > 1e-10)
                        features[r][f] = (features[r][f] - m_featureMin[f]) / range;
                }
            }
        }
    }
    
    void TransformRow(double &row[])
    {
        if(!m_normalizationFit) return;
        
        for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
        {
            if(m_normType == NORM_ZSCORE)
            {
                row[f] = (row[f] - m_featureMean[f]) / m_featureStd[f];
            }
            else
            {
                double range = m_featureMax[f] - m_featureMin[f];
                if(range > 1e-10)
                    row[f] = (row[f] - m_featureMin[f]) / range;
            }
        }
    }
    
    bool SplitData(const double &allFeatures[][], const int &allLabels[], const int totalRows,
                   const double trainRatio, const double valRatio,
                   double &trainFeatures[][], int &trainLabels[], int &trainCount,
                   double &valFeatures[][], int &valLabels[], int &valCount,
                   double &testFeatures[][], int &testLabels[], int &testCount)
    {
        if(totalRows < 3) return false;
        
        int trainEnd = (int)((double)totalRows * trainRatio);
        int valEnd = trainEnd + (int)((double)totalRows * valRatio);
        
        trainEnd = MathMin(trainEnd, totalRows - 2);
        valEnd = MathMin(valEnd, totalRows - 1);
        
        trainCount = trainEnd;
        valCount = valEnd - trainEnd;
        testCount = totalRows - valEnd;
        
        ArrayResize(trainFeatures, trainCount, FEATURE_VECTOR_SIZE);
        ArrayResize(trainLabels, trainCount);
        ArrayResize(valFeatures, valCount, FEATURE_VECTOR_SIZE);
        ArrayResize(valLabels, valCount);
        ArrayResize(testFeatures, testCount, FEATURE_VECTOR_SIZE);
        ArrayResize(testLabels, testCount);
        
        for(int i = 0; i < trainCount; i++)
        {
            for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
                trainFeatures[i][f] = allFeatures[i][f];
            trainLabels[i] = allLabels[i];
        }
        
        for(int i = 0; i < valCount; i++)
        {
            int srcIdx = trainEnd + i;
            for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
                valFeatures[i][f] = allFeatures[srcIdx][f];
            valLabels[i] = allLabels[srcIdx];
        }
        
        for(int i = 0; i < testCount; i++)
        {
            int srcIdx = valEnd + i;
            for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
                testFeatures[i][f] = allFeatures[srcIdx][f];
            testLabels[i] = allLabels[srcIdx];
        }
        
        PrintFormat("[MQH-TRAIN] Data split: train=%d | val=%d | test=%d", trainCount, valCount, testCount);
        return true;
    }
    
    void SaveNormalizationStats(const string filename)
    {
        int fh = FileOpen(filename, FILE_WRITE | FILE_BIN | FILE_COMMON);
        if(fh == INVALID_HANDLE) return;
        
        FileWriteInteger(fh, m_normType);
        for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
        {
            FileWriteDouble(fh, m_featureMean[f]);
            FileWriteDouble(fh, m_featureStd[f]);
            FileWriteDouble(fh, m_featureMin[f]);
            FileWriteDouble(fh, m_featureMax[f]);
        }
        
        FileClose(fh);
    }
    
    bool LoadNormalizationStats(const string filename)
    {
        int fh = FileOpen(filename, FILE_READ | FILE_BIN | FILE_COMMON);
        if(fh == INVALID_HANDLE) return false;
        
        m_normType = (ENUM_NORMALIZATION_TYPE)FileReadInteger(fh);
        for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
        {
            m_featureMean[f] = FileReadDouble(fh);
            m_featureStd[f] = FileReadDouble(fh);
            m_featureMin[f] = FileReadDouble(fh);
            m_featureMax[f] = FileReadDouble(fh);
        }
        
        FileClose(fh);
        m_normalizationFit = true;
        return true;
    }
};

#endif // __MQH_DATA_PREPROCESSOR_MQH__
