// ONNX feature pipeline implementation
#property strict

#ifndef CORE_AI_FEATURE_PIPELINE_ONNX_MQH
#define CORE_AI_FEATURE_PIPELINE_ONNX_MQH

#include "IFeaturePipeline.mqh"
#include "AIFeatureVectorBuilder.mqh"
#include "../AI/PipelineScaler.mqh"

class CFeaturePipelineONNX : public IFeaturePipeline
{
private:
    SFeaturePipelineConfig m_config;
    SFeaturePipelineMetadata m_metadata;
    CPipelineScaler m_scaler;
    string m_scalerPath;
    
    void InitializeConfig()
    {
        m_config.version = 1;
        m_config.featureCount = FEATURE_VECTOR_SIZE;
        m_config.sequenceLength = ONNX_SEQ_LEN;
        m_config.modelType = "ONNX";
        m_config.description = "ONNX pipeline with a training scaler and sequence";
        m_config.createdTime = TimeCurrent();
        m_config.author = "System";
        
        m_metadata.name = "ONNX_Pipeline_v1";
        m_metadata.config = m_config;
        m_metadata.performanceScore = 0.0;
        m_metadata.usageCount = 0;
        m_metadata.isActive = true;
        m_metadata.trafficSplit = 100.0;
    }

public:
    CFeaturePipelineONNX(const string scalerPath = "Resources\\scaler.bin")
    {
        m_scalerPath = scalerPath;
        InitializeConfig();
        
        if(!m_scaler.LoadParams(m_scalerPath, true, FEATURE_VECTOR_SIZE))
            PrintFormat("[PIPELINE-ONNX] Scaler missing or incompatible | expected_features=%d | path=%s | inference disabled",
                        FEATURE_VECTOR_SIZE, m_scalerPath);
    }
    
    virtual ~CFeaturePipelineONNX() {}

    virtual bool BuildFeatures(const string symbol,
                               const ENUM_TIMEFRAMES timeframe,
                               double &features[],
                               const int barShift = 1) override
    {
        // Build base features using the centralized builder
        if(!CAIFeatureVectorBuilder::BuildNNFeatureVector(symbol, timeframe, features, barShift))
            return false;
        
        if(!m_scaler.IsLoaded() || !m_scaler.Apply(features))
            return false;
        
        m_metadata.usageCount++;
        return true;
    }
    
    virtual bool BuildSequence(const string symbol,
                               const ENUM_TIMEFRAMES timeframe,
                               double &sequence[],
                               const int sequenceLength) override
    {
        int seqLen = MathMin(sequenceLength, ONNX_SEQ_LEN);
        int totalSize = FEATURE_VECTOR_SIZE * seqLen;
        ArrayResize(sequence, totalSize);
        ArrayInitialize(sequence, 0.0);
        
        for(int step = 0; step < seqLen; step++)
        {
            int barShift = MathMax(1, seqLen - step);
            double stepFeatures[];
            if(!BuildFeatures(symbol, timeframe, stepFeatures, barShift))
                return false;
            
            for(int f = 0; f < FEATURE_VECTOR_SIZE; f++)
            {
                sequence[step * FEATURE_VECTOR_SIZE + f] = stepFeatures[f];
            }
        }
        
        m_metadata.usageCount++;
        return true;
    }
    
    virtual SFeaturePipelineConfig GetConfig() const override
    {
        return m_config;
    }
    
    virtual string GetName() const override
    {
        return m_metadata.name;
    }
    
    virtual int GetSchemaVersion() const override
    {
        return m_config.version;
    }
    
    virtual bool IsReady() const override
    {
        CIndicatorManager* ind = CIndicatorManager::Instance();
        return (ind != NULL);
    }
    
    virtual string GetFeatureNames() const override
    {
        return CAIFeatureVectorBuilder::GetFeatureNamesStatic();
    }
    
    virtual bool ValidateFeatureVector(const double &features[]) const override
    {
        return ArraySize(features) == FEATURE_VECTOR_SIZE;
    }
    
    virtual SFeaturePipelineMetadata GetMetadata() const override
    {
        return m_metadata;
    }
    
    virtual void UpdateMetadata(const SFeaturePipelineMetadata &metadata) override
    {
        m_metadata = metadata;
        m_config = metadata.config;
    }
    
};

#endif // CORE_AI_FEATURE_PIPELINE_ONNX_MQH
