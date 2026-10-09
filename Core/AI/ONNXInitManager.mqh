// ONNX session initialisation retry / exponential-backoff state
// Extracted verbatim from CEAOrchestrator, which previously held
// three loose members (m_onnxSessionDisabled, m_onnxInitRetryCount,
// m_lastOnnxInitAttempt) plus the retry logic inlined into
// InitializeONNXAIForSymbol() / HandleONNXInitFailure() /
// ReenableONNXAI().
// BEHAVIOUR CONTRACT (must not drift - this gates the ONNX voter
// that feeds the weighted-consensus path):
// * disable threshold : 3 consecutive failures
// * backoff schedule  : 1, 2, 4, 8, 16, 32->capped 30 minutes
// (base 1 min, doubled once per recorded
// retry, at most 5 doublings, MathMin 30)
// * backoff is only evaluated while the session is disabled;
// a first attempt (m_lastOnnxInitAttempt == 0) never waits
// * a granted retry clears the disabled flag BEFORE the adapter
// is constructed, exactly as the original inline code did
// * success resets the retry counter and the attempt timestamp
// but does NOT touch the disabled flag (already cleared)
#property strict

#ifndef CORE_AI_ONNX_INIT_MANAGER_MQH
#define CORE_AI_ONNX_INIT_MANAGER_MQH

// Self-contained retry/backoff state machine. Owns no collaborators
// and performs no ONNX work itself - the caller still creates,
// initialises and registers the adapter; this class only decides
// whether an attempt may run and records its outcome.
class CONNXInitManager
{
private:
    // Tunables, kept as named constants so the numbers cannot drift.
    // Values are the ones the orchestrator used inline.
    enum ENUM_ONNX_INIT_LIMITS
    {
        ONNX_INIT_DISABLE_THRESHOLD    = 3,  // consecutive failures before disabling
        ONNX_INIT_BACKOFF_BASE_MINUTES = 1,  // first backoff interval
        ONNX_INIT_BACKOFF_MAX_DOUBLINGS= 5,  // 1,2,4,8,16 -> at most 5 doublings
        ONNX_INIT_BACKOFF_CAP_MINUTES  = 30  // hard ceiling on the interval
    };

    // ---- state (moved verbatim from CEAOrchestrator) ----
    bool     m_onnxSessionDisabled;   // true once the failure threshold was hit
    int      m_onnxInitRetryCount;    // consecutive failed initialisation attempts
    datetime m_lastOnnxInitAttempt;   // timestamp of the last failed attempt

public:
    CONNXInitManager()
        : m_onnxSessionDisabled(false),
          m_onnxInitRetryCount(0),
          m_lastOnnxInitAttempt(0)
    {
    }

    ~CONNXInitManager() {}

// Exponential backoff: 1min, 2min, 4min, 8min, 16min, max 30min
// Reproduces the original loop exactly:
// for(i = 0; i < m_onnxInitRetryCount && i < 5; i++) x *= 2;
// x = MathMin(x, 30);
    int ComputeBackoffMinutes() const
    {
        // Both MathMin arguments are explicitly int so template deduction cannot
        // widen to double (which would warn on the assignment back to int).
        int retryDelayMinutes = (int)ONNX_INIT_BACKOFF_BASE_MINUTES;
        for(int i = 0; i < m_onnxInitRetryCount && i < (int)ONNX_INIT_BACKOFF_MAX_DOUBLINGS; i++)
            retryDelayMinutes *= 2;
        retryDelayMinutes = MathMin(retryDelayMinutes, (int)ONNX_INIT_BACKOFF_CAP_MINUTES);
        return retryDelayMinutes;
    }

// Gate that used to open InitializeONNXAIForSymbol(). Returns
// false while the session is disabled AND still inside the
// backoff window; otherwise returns true, and - when this is a
// granted retry - logs the retry line and clears the disabled
// flag before the caller proceeds.
// symbol - symbol being initialised (log context only)
// returns true when the caller may attempt initialisation
    bool ShouldAttemptInit(const string symbol)
    {
        if(!m_onnxSessionDisabled)
            return true;

        // Exponential backoff: 1min, 2min, 4min, 8min, 16min, max 30min
        int retryDelayMinutes = ComputeBackoffMinutes();

        datetime now = TimeCurrent();
        if(m_lastOnnxInitAttempt > 0 && (now - m_lastOnnxInitAttempt) < (retryDelayMinutes * 60))
        {
            // Still in backoff period, skip this attempt
            return false;
        }

        PrintFormat("[AI-MODE] ONNX AI retry attempt #%d for %s after %d min backoff",
                    m_onnxInitRetryCount + 1, symbol, retryDelayMinutes);
        // Clear disabled flag to allow retry
        m_onnxSessionDisabled = false;
        return true;
    }

// Records one consumed initialisation attempt: bumps the
// consecutive-failure counter and stamps the attempt time.
    void RegisterAttempt()
    {
        m_onnxInitRetryCount++;
        m_lastOnnxInitAttempt = TimeCurrent();
    }

// Full failure path, byte-for-byte equivalent to the former
// CEAOrchestrator::HandleONNXInitFailure(): count the attempt,
// disable after 3 consecutive failures, log either the disable
// notice or the "attempt n/3" notice.
// symbol - symbol whose initialisation failed (log context)
    void RegisterFailure(const string symbol)
    {
        RegisterAttempt();

        // Disable after 3 consecutive failures
        if(m_onnxInitRetryCount >= ONNX_INIT_DISABLE_THRESHOLD)
        {
            MarkDisabled();
            PrintFormat("[AI-MODE] ONNX AI disabled for %s after %d consecutive failures. Will retry with exponential backoff.",
                        symbol, m_onnxInitRetryCount);
        }
        else
        {
            PrintFormat("[AI-MODE] ONNX AI init failed for %s (attempt %d/3). Will retry.",
                        symbol, m_onnxInitRetryCount);
        }
    }

// Success path: reset retry count (original cleared the counter
// and the timestamp only - the disabled flag was already
// cleared by the granted retry in ShouldAttemptInit()).
    void RegisterSuccess()
    {
        m_onnxInitRetryCount = 0;
        m_lastOnnxInitAttempt = 0;
    }

// Full state reset used by the manual re-enable path
// (CEAOrchestrator::ReenableONNXAI).
    void Reset()
    {
        m_onnxSessionDisabled = false;
        m_onnxInitRetryCount = 0;
        m_lastOnnxInitAttempt = 0;
    }

    // ---- state accessors ----
    bool     IsDisabled()      const { return m_onnxSessionDisabled; }
    void     MarkDisabled()          { m_onnxSessionDisabled = true; }
    int      GetRetryCount()   const { return m_onnxInitRetryCount; }
    void     SetRetryCount(const int count) { m_onnxInitRetryCount = (count < 0 ? 0 : count); }
    datetime GetLastAttempt()  const { return m_lastOnnxInitAttempt; }
    void     SetLastAttempt(const datetime stamp) { m_lastOnnxInitAttempt = stamp; }

    // Threshold introspection (diagnostics / tests).
    int      GetDisableThreshold() const { return (int)ONNX_INIT_DISABLE_THRESHOLD; }
    int      GetBackoffCapMinutes() const { return (int)ONNX_INIT_BACKOFF_CAP_MINUTES; }
};

#endif // CORE_AI_ONNX_INIT_MANAGER_MQH
