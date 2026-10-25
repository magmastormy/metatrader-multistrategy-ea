// Storage object for the consensus-quorum, adaptive-quorum, regime-relax, decay and
// participation-formula configuration that used to sit as loose manager members, with the
// clamping setters that write them.
// Computes nothing: CConsensusEngine reads these through the same manager getters as before,
// which are one-line forwarders here, so the quorum path's numbers are unchanged.
// Leaf value object held BY VALUE - no back-pointer, it never observes manager state.
// Implementation detail of EnterpriseStrategyManager.mqh - included from there, not standalone.
#ifndef ENT_STRATEGY_QUORUM_CONFIG_MQH
#define ENT_STRATEGY_QUORUM_CONFIG_MQH

// Consensus / adaptation configuration store
class CEntStrategyQuorumConfig
{
private:
    // L1-007: Health monitor configuration (mirrored for fallback when m_healthMonitor == NULL)
    double m_minWinRateThreshold;
    int    m_maxConsecutiveLosses_Limit;
    int    m_rollingWindowSize;

    // Consensus configuration (mirrored for internal consensus logic)
    int    m_minQuorum;
    int    m_intrabarMinQuorum;
    bool   m_intrabarDynamicQuorumEnabled;
    double m_quorumThreshold;
    double m_pipelineMinConfidence;
    double m_conflictDeadband;
    double m_minReadyWeightRatio;
    double m_supportFloorNewBar;
    double m_supportFloorIntrabar;
    bool   m_adaptiveQuorumEnabled;
    double m_adaptiveQualityThreshold_1voter;
    double m_adaptiveSupportFloor_1voter;
    double m_adaptiveQualityThreshold_2voters;
    double m_adaptiveSupportFloor_2voters;
    double m_adaptiveQualityThreshold_3plus;
    double m_adaptiveSupportFloor_3plus;
    bool   m_regimeRelaxActive;
    double m_regimeRelaxFactor;

    // Participation score multiplier formula parameters (L6-008)
    double m_participationFormulaBase;
    double m_participationFormulaCoeff;
    double m_participationFormulaMin;
    double m_participationFormulaMax;

public:
    CEntStrategyQuorumConfig();

    //--- read half (consumed by CConsensusEngine through the manager) ---
    double GetMinWinRateThreshold() const              { return m_minWinRateThreshold; }
    int    GetMaxConsecutiveLossesLimit() const        { return m_maxConsecutiveLosses_Limit; }
    int    GetRollingWindowSize() const                { return m_rollingWindowSize; }

    int    GetMinQuorum() const                        { return m_minQuorum; }
    int    GetIntrabarMinQuorum() const                { return m_intrabarMinQuorum; }
    bool   IsIntrabarDynamicQuorumEnabled() const      { return m_intrabarDynamicQuorumEnabled; }
    double GetQuorumThreshold() const                  { return m_quorumThreshold; }
    double GetPipelineMinConfidence() const            { return m_pipelineMinConfidence; }
    double GetConflictDeadband() const                 { return m_conflictDeadband; }
    double GetMinReadyWeightRatio() const              { return m_minReadyWeightRatio; }
    double GetSupportFloorNewBar() const               { return m_supportFloorNewBar; }
    double GetSupportFloorIntrabar() const             { return m_supportFloorIntrabar; }
    bool   IsAdaptiveQuorumEnabled() const             { return m_adaptiveQuorumEnabled; }
    double GetAdaptiveQualityThreshold1Voter() const   { return m_adaptiveQualityThreshold_1voter; }
    double GetAdaptiveSupportFloor1Voter() const       { return m_adaptiveSupportFloor_1voter; }
    double GetAdaptiveQualityThreshold2Voters() const  { return m_adaptiveQualityThreshold_2voters; }
    double GetAdaptiveSupportFloor2Voters() const      { return m_adaptiveSupportFloor_2voters; }
    double GetAdaptiveQualityThreshold3Plus() const    { return m_adaptiveQualityThreshold_3plus; }
    double GetAdaptiveSupportFloor3Plus() const        { return m_adaptiveSupportFloor_3plus; }
    bool   IsRegimeRelaxActive() const                 { return m_regimeRelaxActive; }
    double GetRegimeRelaxFactor() const                { return m_regimeRelaxFactor; }

    double GetParticipationFormulaBase() const         { return m_participationFormulaBase; }
    double GetParticipationFormulaCoeff() const        { return m_participationFormulaCoeff; }
    double GetParticipationFormulaMin() const          { return m_participationFormulaMin; }
    double GetParticipationFormulaMax() const          { return m_participationFormulaMax; }

    //--- write half (verbatim relocation of the manager setter bodies) ---
    void SetMinQuorum(int quorum);
    void SetIntrabarMinQuorum(int quorum);
    void SetIntrabarDynamicQuorumEnabled(const bool enabled);
    void SetQuorumThreshold(const double threshold);
    void SetConflictDeadband(const double deadband);
    void SetMinReadyWeightRatio(const double ratio);
    void SetSupportFloors(const double newBarFloor, const double intrabarFloor);
    void SetOrchestratorMode(double minWinRate, int maxLosses);

    //--- written by CEnterpriseStrategyManager::SetPipelineFilters().
    //--- The clamp is the original inline expression, unchanged.
    void CachePipelineMinConfidence(const double minConfidence);
};

// Constructor - defaults relocated verbatim from the manager's
// constructor initialiser list (including the PROFIT-xx notes).
CEntStrategyQuorumConfig::CEntStrategyQuorumConfig() :
    m_minWinRateThreshold(0.40),
    m_maxConsecutiveLosses_Limit(5),
    m_rollingWindowSize(20),
    m_minQuorum(1),
    m_intrabarMinQuorum(1),
    m_intrabarDynamicQuorumEnabled(true),
    m_quorumThreshold(0.60),
    m_pipelineMinConfidence(0.40),
    m_conflictDeadband(0.35),         // [PROFIT-02] default deadband raised (audit: 0.30-0.35)
    m_minReadyWeightRatio(0.30),
    m_supportFloorNewBar(0.30),        // [PROFIT-11] ratio field, not a count
    m_supportFloorIntrabar(0.25),      // [PROFIT-11] ratio field, not a count
    m_adaptiveQuorumEnabled(false),
    m_adaptiveQualityThreshold_1voter(0.80),
    m_adaptiveSupportFloor_1voter(1),
    m_adaptiveQualityThreshold_2voters(0.70),
    m_adaptiveSupportFloor_2voters(2),
    m_adaptiveQualityThreshold_3plus(0.60),
    m_adaptiveSupportFloor_3plus(3),
    m_regimeRelaxActive(false),
    m_regimeRelaxFactor(0.80),
    m_participationFormulaBase(0.40),
    m_participationFormulaCoeff(0.65),
    m_participationFormulaMin(0.55),
    m_participationFormulaMax(1.05)
{
}

void CEntStrategyQuorumConfig::SetMinQuorum(int quorum)
{
    m_minQuorum = MathMax(1, quorum);
}

void CEntStrategyQuorumConfig::SetIntrabarMinQuorum(int quorum)
{
    m_intrabarMinQuorum = MathMax(1, quorum);
}

void CEntStrategyQuorumConfig::SetIntrabarDynamicQuorumEnabled(const bool enabled)
{
    m_intrabarDynamicQuorumEnabled = enabled;
}

void CEntStrategyQuorumConfig::SetQuorumThreshold(const double threshold)
{
    m_quorumThreshold = MathMax(0.0, MathMin(1.0, threshold));
}

void CEntStrategyQuorumConfig::SetConflictDeadband(const double deadband)
{
    m_conflictDeadband = MathMax(0.0, MathMin(0.5, deadband));
}

void CEntStrategyQuorumConfig::SetMinReadyWeightRatio(const double ratio)
{
    m_minReadyWeightRatio = MathMax(0.0, MathMin(1.0, ratio));
}

void CEntStrategyQuorumConfig::SetSupportFloors(const double newBarFloor, const double intrabarFloor)
{
    m_supportFloorNewBar = MathMax(0.0, MathMin(1.0, newBarFloor));
    m_supportFloorIntrabar = MathMax(0.0, MathMin(1.0, intrabarFloor));
}

void CEntStrategyQuorumConfig::SetOrchestratorMode(double minWinRate, int maxLosses)
{
    m_minWinRateThreshold = MathMax(0.0, MathMin(1.0, minWinRate));
    m_maxConsecutiveLosses_Limit = MathMax(1, maxLosses);
    PrintFormat("[EnterpriseStrategyManager] Adaptation thresholds updated | MinWinRate=%.2f | MaxConsecutiveLosses=%d",
                m_minWinRateThreshold,
                m_maxConsecutiveLosses_Limit);
}

void CEntStrategyQuorumConfig::CachePipelineMinConfidence(const double minConfidence)
{
    m_pipelineMinConfidence = MathMax(0.0, MathMin(1.0, minConfidence));
}

#endif // ENT_STRATEGY_QUORUM_CONFIG_MQH
