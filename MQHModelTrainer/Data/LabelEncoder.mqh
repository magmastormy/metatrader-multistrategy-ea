//+------------------------------------------------------------------+
//| LabelEncoder.mqh                                                 |
//| Label encoding utilities for classification labels                |
//+------------------------------------------------------------------+
#ifndef __MQH_LABEL_ENCODER_MQH__
#define __MQH_LABEL_ENCODER_MQH__

enum ENUM_NORMALIZATION_TYPE
{
    NORM_ZSCORE = 0,
    NORM_MINMAX = 1
};

enum ENUM_LABEL_TYPE
{
    LABEL_CLASSIFICATION = 0,
    LABEL_REGRESSION = 1
};

class CLabelEncoder
{
private:
    int m_numClasses;
    int m_classLabels[];
    
public:
    CLabelEncoder() : m_numClasses(3)
    {
        ArrayResize(m_classLabels, 3);
        m_classLabels[0] = -1;
        m_classLabels[1] = 0;
        m_classLabels[2] = 1;
    }
    
    int EncodeLabel(const int rawLabel)
    {
        for(int i = 0; i < m_numClasses; i++)
        {
            if(m_classLabels[i] == rawLabel)
                return i;
        }
        return 1;
    }
    
    int DecodeLabel(const int encodedLabel)
    {
        if(encodedLabel >= 0 && encodedLabel < m_numClasses)
            return m_classLabels[encodedLabel];
        return 0;
    }
    
    void OneHotEncode(const int label, double &oneHot[])
    {
        ArrayResize(oneHot, m_numClasses);
        ArrayInitialize(oneHot, 0.0);
        
        int encoded = EncodeLabel(label);
        if(encoded >= 0 && encoded < m_numClasses)
            oneHot[encoded] = 1.0;
    }
    
    int ArgMax(const double &probabilities[], const int size)
    {
        int maxIdx = 0;
        double maxVal = probabilities[0];
        
        for(int i = 1; i < size; i++)
        {
            if(probabilities[i] > maxVal)
            {
                maxVal = probabilities[i];
                maxIdx = i;
            }
        }
        
        return maxIdx;
    }
    
    int GetNumClasses() const { return m_numClasses; }
};

#endif // __MQH_LABEL_ENCODER_MQH__
