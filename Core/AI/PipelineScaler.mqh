// Optional StandardScaler parameter loader for ONNX parity
#property strict

#ifndef CORE_AI_PIPELINE_SCALER_MQH
#define CORE_AI_PIPELINE_SCALER_MQH

class CPipelineScaler
{
private:
    double m_means[];
    double m_scales[];
    bool   m_loaded;

public:
    CPipelineScaler()
    {
        m_loaded = false;
    }

    bool LoadParams(const string path, const bool commonPath = true,
                    const int expectedFeatureCount = 0)
    {
        int flags = FILE_READ | FILE_BIN;
        if(commonPath)
            flags |= FILE_COMMON;

        int handle = FileOpen(path, flags);
        if(handle == INVALID_HANDLE)
        {
            m_loaded = false;
            return false;
        }

        int featureCount = FileReadInteger(handle, INT_VALUE);
        if(featureCount <= 0 ||
           (expectedFeatureCount > 0 && featureCount != expectedFeatureCount) ||
           (long)FileSize(handle) != 4 + (long)featureCount * 16)
        {
            FileClose(handle);
            m_loaded = false;
            return false;
        }

        ArrayResize(m_means, featureCount);
        ArrayResize(m_scales, featureCount);
        for(int i = 0; i < featureCount; i++)
        {
            if(FileIsEnding(handle))
            {
                FileClose(handle);
                m_loaded = false;
                return false;
            }
            m_means[i] = FileReadDouble(handle);
            if(!MathIsValidNumber(m_means[i]))
            {
                FileClose(handle);
                m_loaded = false;
                return false;
            }
        }
        for(int i = 0; i < featureCount; i++)
        {
            if(FileIsEnding(handle))
            {
                FileClose(handle);
                m_loaded = false;
                return false;
            }
            double scale = FileReadDouble(handle);
            if(!MathIsValidNumber(scale) || scale <= 0.0)
            {
                FileClose(handle);
                m_loaded = false;
                return false;
            }
            m_scales[i] = scale;
        }

        FileClose(handle);
        m_loaded = true;
        return true;
    }

    bool Apply(double &features[]) const
    {
        if(!m_loaded)
            return false;

        int featureCount = ArraySize(m_means);
        if(featureCount <= 0 || ArraySize(features) != featureCount)
            return false;

        for(int i = 0; i < featureCount; i++)
            features[i] = (features[i] - m_means[i]) / m_scales[i];
        return true;
    }

    bool IsLoaded() const { return m_loaded; }
    int GetFeatureCount() const { return ArraySize(m_means); }
};

#endif // CORE_AI_PIPELINE_SCALER_MQH
