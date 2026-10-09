// Interface for centralized feature engineering pipeline
#property strict

#ifndef CORE_AI_IFEATURE_PIPELINE_MQH
#define CORE_AI_IFEATURE_PIPELINE_MQH

#include "../../Interfaces/IStrategy.mqh"

struct SFeaturePipelineConfig
{
    int version;                    // Schema version
    int featureCount;               // Number of output features
    int sequenceLength;             // For sequence models (Transformer, etc.)
    string modelType;               // "NN", "Transformer", "Ensemble", "ONNX"
    string description;             // Human-readable description
    datetime createdTime;           // When this schema was created
    string author;                  // Who created this schema
    
    SFeaturePipelineConfig()
    {
        version = 1;
        featureCount = FEATURE_VECTOR_SIZE;
        sequenceLength = 1;
        modelType = "NN";
        description = "";
        createdTime = TimeCurrent();
        author = "";
    }
};

struct SFeaturePipelineMetadata
{
    string name;                    // Pipeline name/identifier
    SFeaturePipelineConfig config;
    double performanceScore;        // Historical performance metric
    int usageCount;                 // How many times used
    bool isActive;                  // Currently active for A/B testing
    double trafficSplit;            // Percentage of traffic (0-100)
    
    SFeaturePipelineMetadata()
    {
        name = "";
        performanceScore = 0.0;
        usageCount = 0;
        isActive = true;
        trafficSplit = 100.0;
    }
};

// IFeaturePipeline Interface
class IFeaturePipeline
{
public:
    virtual ~IFeaturePipeline() {}
    
    // Build feature vector for a single bar (NN, ONNX, etc.)
    virtual bool BuildFeatures(const string symbol,
                               const ENUM_TIMEFRAMES timeframe,
                               double &features[],
                               const int barShift = 1) = 0;
    
    // Build feature sequence for sequence models (Transformer, LSTM, etc.)
    virtual bool BuildSequence(const string symbol,
                               const ENUM_TIMEFRAMES timeframe,
                               double &sequence[],
                               const int sequenceLength) = 0;
    
    // Get pipeline configuration (schema version, feature count, etc.)
    virtual SFeaturePipelineConfig GetConfig() const = 0;
    
    // Get pipeline name/identifier
    virtual string GetName() const = 0;
    
    virtual int GetSchemaVersion() const = 0;
    
    // Check if pipeline is ready (indicators loaded, etc.)
    virtual bool IsReady() const = 0;
    
    // Get feature names for debugging/logging
    virtual string GetFeatureNames() const = 0;
    
    // Validate feature vector size matches expected
    virtual bool ValidateFeatureVector(const double &features[]) const = 0;
    
    // Get metadata for A/B testing
    virtual SFeaturePipelineMetadata GetMetadata() const = 0;
    
    // Update metadata (e.g., performance score)
    virtual void UpdateMetadata(const SFeaturePipelineMetadata &metadata) = 0;
};

#endif // CORE_AI_IFEATURE_PIPELINE_MQH