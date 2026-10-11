// ONNX session init retry / exponential-backoff state machine.
// Behaviour contract (must not drift - this gates the ONNX voter that feeds the weighted-consensus path):
// * disable threshold: 3 consecutive failures
// * backoff: 1 min doubled per recorded failure, at most 5 doublings, capped at 30 min
// * evaluated only while disabled, and only once a failure has been timestamped
// * a granted retry clears the disabled flag before the caller constructs the adapter
// * the "attempt n/3" log literal must stay in step with ONNX_INIT_DISABLE_THRESHOLD
#property strict

#ifndef CORE_AI_ONNX_INIT_MANAGER_MQH
#define CORE_AI_ONNX_INIT_MANAGER_MQH

// Decides whether an attempt may run and records its outcome; the caller owns adapter creation, init and registration.
class CONNXInitManager
{
private:
    enum ENUM_ONNX_INIT_LIMITS
    {
        ONNX_INIT_DISABLE_THRESHOLD    = 3,  // consecutive failures before disabling
        ONNX_INIT_BACKOFF_BASE_MINUTES = 1,  // first backoff interval
        ONNX_INIT_BACKOFF_MAX_DOUBLINGS= 5,  // 1,2,4,8,16 -> at most 5 doublings
        ONNX_INIT_BACKOFF_CAP_MINUTES  = 30  // hard ceiling on the interval
    };

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

    int ComputeBackoffMinutes() const
    {
        // MathMin arguments are int-cast: template deduction would otherwise widen to double and warn on the int assignment.
        int retryDelayMinutes = (int)ONNX_INIT_BACKOFF_BASE_MINUTES;
        for(int i = 0; i < m_onnxInitRetryCount && i < (int)ONNX_INIT_BACKOFF_MAX_DOUBLINGS; i++)
            retryDelayMinutes *= 2;
        retryDelayMinutes = MathMin(retryDelayMinutes, (int)ONNX_INIT_BACKOFF_CAP_MINUTES);
        return retryDelayMinutes;
    }

// Gate for an ONNX init attempt: false only while the session is disabled and still inside the backoff window.
// On a granted retry it logs the attempt and clears the disabled flag before the caller proceeds.
    bool ShouldAttemptInit(const string symbol)
    {
        if(!m_onnxSessionDisabled)
            return true;

        int retryDelayMinutes = ComputeBackoffMinutes();

        datetime now = TimeCurrent();
        if(m_lastOnnxInitAttempt > 0 && (now - m_lastOnnxInitAttempt) < (retryDelayMinutes * 60))
        {
            return false;
        }

        PrintFormat("[AI-MODE] ONNX AI retry attempt #%d for %s after %d min backoff",
                    m_onnxInitRetryCount + 1, symbol, retryDelayMinutes);
        m_onnxSessionDisabled = false;
        return true;
    }

// Counts one consumed attempt as a failure up front and stamps the time; only RegisterFailure() calls it.
    void RegisterAttempt()
    {
        m_onnxInitRetryCount++;
        m_lastOnnxInitAttempt = TimeCurrent();
    }

// Counts the attempt, then marks the session disabled once ONNX_INIT_DISABLE_THRESHOLD consecutive failures are reached.
// Below the threshold only the "attempt n/3" notice is logged; symbol is log context.
    void RegisterFailure(const string symbol)
    {
        RegisterAttempt();

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

// Clears the counter and timestamp only - the disabled flag was already cleared by the granted retry in ShouldAttemptInit().
    void RegisterSuccess()
    {
        m_onnxInitRetryCount = 0;
        m_lastOnnxInitAttempt = 0;
    }

// Full state reset for the manual re-enable path (CEAOrchestrator::ReenableONNXAI).
    void Reset()
    {
        m_onnxSessionDisabled = false;
        m_onnxInitRetryCount = 0;
        m_lastOnnxInitAttempt = 0;
    }

    bool     IsDisabled()      const { return m_onnxSessionDisabled; }
    void     MarkDisabled()          { m_onnxSessionDisabled = true; }
    int      GetRetryCount()   const { return m_onnxInitRetryCount; }
    void     SetRetryCount(const int count) { m_onnxInitRetryCount = (count < 0 ? 0 : count); }
    datetime GetLastAttempt()  const { return m_lastOnnxInitAttempt; }
    void     SetLastAttempt(const datetime stamp) { m_lastOnnxInitAttempt = stamp; }

    int      GetDisableThreshold() const { return (int)ONNX_INIT_DISABLE_THRESHOLD; }
    int      GetBackoffCapMinutes() const { return (int)ONNX_INIT_BACKOFF_CAP_MINUTES; }
};

#endif // CORE_AI_ONNX_INIT_MANAGER_MQH
