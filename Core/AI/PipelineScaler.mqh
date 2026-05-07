//+------------------------------------------------------------------+
//| PipelineScaler.mqh                                               |
//| Optional StandardScaler parameter loader for ONNX parity         |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_AI_PIPELINE_SCALER_MQH
#define CORE_AI_PIPELINE_SCALER_MQH

class CPipelineScaler
{
private:
    double m_means[];
    double m_scales[];
    bool   m_loaded;
    string m_lastPath;
    bool   m_lastCommonPath;
    long   m_lastModified;

    long ReadModifiedTime(const string path, const bool commonPath) const
    {
        if(!FileIsExist(path, commonPath ? FILE_COMMON : 0))
            return 0;

        int handle = FileOpen(path, FILE_READ | FILE_BIN | (commonPath ? FILE_COMMON : 0));
        if(handle == INVALID_HANDLE)
            return 0;

        long modified = (long)FileGetInteger(handle, FILE_MODIFY_DATE);
        FileClose(handle);
        return modified;
    }

public:
    CPipelineScaler()
    {
        m_loaded = false;
        m_lastPath = "";
        m_lastCommonPath = true;
        m_lastModified = 0;
    }

    bool LoadParams(const string path, const bool commonPath = true)
    {
        m_lastPath = path;
        m_lastCommonPath = commonPath;

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
        if(featureCount <= 0)
        {
            FileClose(handle);
            m_loaded = false;
            return false;
        }

        ArrayResize(m_means, featureCount);
        ArrayResize(m_scales, featureCount);
        for(int i = 0; i < featureCount; i++)
            m_means[i] = FileReadDouble(handle);
        for(int i = 0; i < featureCount; i++)
        {
            double scale = FileReadDouble(handle);
            m_scales[i] = (MathAbs(scale) > 1e-12) ? scale : 1.0;
        }

        m_lastModified = (long)FileGetInteger(handle, FILE_MODIFY_DATE);
        FileClose(handle);
        m_loaded = true;
        return true;
    }

    bool MaybeReload(const string path = "", const bool commonPath = true)
    {
        string effectivePath = (path != "") ? path : m_lastPath;
        bool effectiveCommonPath = (path != "") ? commonPath : m_lastCommonPath;
        if(effectivePath == "")
            return false;

        long modified = ReadModifiedTime(effectivePath, effectiveCommonPath);
        if(modified <= 0 || modified == m_lastModified)
            return false;

        return LoadParams(effectivePath, effectiveCommonPath);
    }

    bool Apply(double &features[]) const
    {
        if(!m_loaded)
            return false;

        int featureCount = ArraySize(m_means);
        if(featureCount <= 0 || ArraySize(features) < featureCount)
            return false;

        for(int i = 0; i < featureCount; i++)
            features[i] = (features[i] - m_means[i]) / m_scales[i];
        return true;
    }

    bool IsLoaded() const { return m_loaded; }
    int GetFeatureCount() const { return ArraySize(m_means); }
};

#endif // CORE_AI_PIPELINE_SCALER_MQH
