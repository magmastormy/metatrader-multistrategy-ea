// Extracted from DiagnosticsManager.mqh (God-Object decomposition)
// Owns AI vote heartbeat tracking state [L11-004]:
// the per-symbol / per-AI-type last-activity matrix and the
// staleness warnings emitted during the heartbeat cycle.
// CDiagnosticsManager keeps a by-value CDiagMgrAIVoteTracker member
// and forwards to it; symbol list stays owned by the manager and is
// passed in, so log strings and ordering are unchanged.
#ifndef DIAG_MGR_AI_VOTE_MQH
#define DIAG_MGR_AI_VOTE_MQH

#include "../Utils/JsonLogger.mqh"

// AI type enumeration for vote tracking
enum ENUM_AI_VOTE_TYPE
{
    AI_VOTE_NEURAL_NET = 0,
    AI_VOTE_TRANSFORMER = 1,
    AI_VOTE_ENSEMBLE = 2,
    AI_VOTE_ONNX = 3,
    AI_VOTE_COUNT = 4
};

// CDiagMgrAIVoteTracker — AI vote heartbeat activity tracking
class CDiagMgrAIVoteTracker
{
private:
    // Track last [AI-VOTE] log timestamp per symbol per AI type
    datetime m_aiVoteLastActivity[];  // 2D: [symbolIndex * AI_VOTE_COUNT + aiType]
    bool     m_aiVoteTrackingEnabled; // Enable/disable AI vote monitoring

public:
    CDiagMgrAIVoteTracker() : m_aiVoteTrackingEnabled(false) {}

    ~CDiagMgrAIVoteTracker() {}

    bool IsTrackingEnabled() const { return m_aiVoteTrackingEnabled; }

// Size the tracking matrix for the configured symbol universe
// Mirrors the initialisation block inside the original SetSymbols()
    void ConfigureSymbols(const int symbolCount)
    {
        // Initialize AI vote tracking array [L11-004]
        // 2D array: [symbolIndex * AI_VOTE_COUNT + aiType]
        if(symbolCount > 0)
        {
            ArrayResize(m_aiVoteLastActivity, symbolCount * AI_VOTE_COUNT);
            ArrayInitialize(m_aiVoteLastActivity, 0);
            m_aiVoteTrackingEnabled = true;
        }
    }

// Update AI vote activity timestamp [L11-004]
// Call this when an AI adapter logs an [AI-VOTE] heartbeat
    void UpdateActivity(string &symbols[],
                        const int symbolCount,
                        const string symbol,
                        const string aiType)
    {
        if(!m_aiVoteTrackingEnabled || symbolCount == 0)
            return;

        // Find symbol index
        int symbolIndex = -1;
        for(int i = 0; i < symbolCount; i++)
        {
            if(symbols[i] == symbol)
            {
                symbolIndex = i;
                break;
            }
        }
        if(symbolIndex < 0)
            return;

        // Map AI type string to enum
        int aiTypeIndex = -1;
        if(aiType == "NeuralNet" || aiType == "Neural Network AI")
            aiTypeIndex = AI_VOTE_NEURAL_NET;
        else if(aiType == "Transformer" || aiType == "Transformer AI")
            aiTypeIndex = AI_VOTE_TRANSFORMER;
        else if(aiType == "Ensemble" || aiType == "Ensemble AI")
            aiTypeIndex = AI_VOTE_ENSEMBLE;
        else if(aiType == "ONNX" || aiType == "ONNX AI")
            aiTypeIndex = AI_VOTE_ONNX;
        else
            return;

        // Update timestamp
        int arrayIndex = symbolIndex * AI_VOTE_COUNT + aiTypeIndex;
        m_aiVoteLastActivity[arrayIndex] = TimeCurrent();
    }

// AI vote heartbeat monitoring [L11-004]
// Check if AI adapters are logging [AI-VOTE] heartbeats
// Emits identical AIVoteMissing warnings, in identical order.
    void EmitMissingVoteWarnings(string &symbols[],
                                 const int symbolCount,
                                 const bool nnEnabled,
                                 const bool transformerEnabled,
                                 const bool ensembleEnabled,
                                 const bool onnxEnabled,
                                 const datetime hbNow,
                                 const string corrId)
    {
        for(int symIdx = 0; symIdx < symbolCount; symIdx++)
        {
            // Check each AI type that should be active
            // Neural Network AI
            if(nnEnabled)
            {
                int arrayIdx = symIdx * AI_VOTE_COUNT + AI_VOTE_NEURAL_NET;
                datetime lastVote = m_aiVoteLastActivity[arrayIdx];
                if(lastVote == 0 || (hbNow - lastVote) > 30)
                {
                    CJsonLogger::LogWarning("AIVoteMissing",
                        StringFormat("symbol=%s | type=NeuralNet | last=%s | secs_ago=%d",
                            symbols[symIdx], lastVote == 0 ? "NEVER" : TimeToString(lastVote),
                            lastVote == 0 ? -1 : (int)(hbNow - lastVote)), corrId);
                }
            }
            if(transformerEnabled)
            {
                int arrayIdx = symIdx * AI_VOTE_COUNT + AI_VOTE_TRANSFORMER;
                datetime lastVote = m_aiVoteLastActivity[arrayIdx];
                if(lastVote == 0 || (hbNow - lastVote) > 30)
                {
                    CJsonLogger::LogWarning("AIVoteMissing",
                        StringFormat("symbol=%s | type=Transformer | last=%s | secs_ago=%d",
                            symbols[symIdx], lastVote == 0 ? "NEVER" : TimeToString(lastVote),
                            lastVote == 0 ? -1 : (int)(hbNow - lastVote)), corrId);
                }
            }
            if(ensembleEnabled)
            {
                int arrayIdx = symIdx * AI_VOTE_COUNT + AI_VOTE_ENSEMBLE;
                datetime lastVote = m_aiVoteLastActivity[arrayIdx];
                if(lastVote == 0 || (hbNow - lastVote) > 30)
                {
                    CJsonLogger::LogWarning("AIVoteMissing",
                        StringFormat("symbol=%s | type=Ensemble | last=%s | secs_ago=%d",
                            symbols[symIdx], lastVote == 0 ? "NEVER" : TimeToString(lastVote),
                            lastVote == 0 ? -1 : (int)(hbNow - lastVote)), corrId);
                }
            }
            if(onnxEnabled)
            {
                int arrayIdx = symIdx * AI_VOTE_COUNT + AI_VOTE_ONNX;
                datetime lastVote = m_aiVoteLastActivity[arrayIdx];
                if(lastVote == 0 || (hbNow - lastVote) > 30)
                {
                    CJsonLogger::LogWarning("AIVoteMissing",
                        StringFormat("symbol=%s | type=ONNX | last=%s | secs_ago=%d",
                            symbols[symIdx], lastVote == 0 ? "NEVER" : TimeToString(lastVote),
                            lastVote == 0 ? -1 : (int)(hbNow - lastVote)), corrId);
                }
            }
        }
    }
};

#endif // DIAG_MGR_AI_VOTE_MQH
