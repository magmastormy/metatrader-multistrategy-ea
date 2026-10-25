// Rolling-window ONNX inference (Live-only; no shadow/hot-swap)
#property strict

#ifndef ONNX_BRAIN_MQH
#define ONNX_BRAIN_MQH

#include "AIConfig.mqh"

#ifndef ONNX_SEQ_LEN
#define ONNX_SEQ_LEN    AI_ONNX_SEQ_LEN
#endif
#define ONNX_FEAT_DIM   FEATURE_VECTOR_SIZE
#ifndef ONNX_N_CLASSES
#define ONNX_N_CLASSES  AI_ONNX_N_CLASSES
#endif

int OnnxPositiveMod(const int value, const int modulus)
{
    int mod = value % modulus;
    return (mod < 0) ? mod + modulus : mod;
}

class COnnxBrain
{
private:
    long   m_handle;
    bool   m_loaded;
    bool   m_full;
    int    m_head;
    float  m_featureBuf[ONNX_SEQ_LEN][ONNX_FEAT_DIM];
    float  m_probs[ONNX_N_CLASSES];
    int    m_signal;
    double m_confidence;
    double m_activeWins;        // Live-model accuracy tracking (active model only)
    double m_activeTotal;
    double m_activePnl;
    bool   m_fallbackToCpu;
    double m_temperature;

    bool ConfigureHandle(const long handle)
    {
        if(handle == INVALID_HANDLE)
            return false;

        long ishape[] = {1, ONNX_SEQ_LEN, ONNX_FEAT_DIM};
        long oshape[] = {1, ONNX_N_CLASSES};
        
        if(!OnnxSetInputShape(handle, 0, ishape))
        {
            PrintFormat("[ONNX] ERROR: Failed to set input shape [1,%d,%d]. Check model compatibility.", ONNX_SEQ_LEN, ONNX_FEAT_DIM);
            return false;
        }
        
        if(!OnnxSetOutputShape(handle, 0, oshape))
        {
            PrintFormat("[ONNX] ERROR: Failed to set output shape [1,%d]. Check model classes.", ONNX_N_CLASSES);
            return false;
        }
        
        return true;
    }

    bool InitHandleFromBuffer(const uchar &buffer[], long &handle)
    {
        handle = INVALID_HANDLE;
        if(ArraySize(buffer) <= 0)
            return false;

        // If CUDA already failed on a previous session, skip straight to CPU-only.
        if(m_fallbackToCpu)
        {
            Print("[ONNX-CPU-FALLBACK] CUDA unavailable, using CPU execution provider");
            handle = OnnxCreateFromBuffer(buffer, ONNX_USE_CPU_ONLY);
            if(handle != INVALID_HANDLE && ConfigureHandle(handle))
                return true;
            PrintFormat("[ONNX] ERROR: CPU-only session also failed | err=%d", GetLastError());
            if(handle != INVALID_HANDLE)
            {
                OnnxRelease(handle);
                handle = INVALID_HANDLE;
            }
            return false;
        }

        // First attempt: default backend (may attempt CUDA).
        Print("[ONNX] Initializing with default backend (may attempt CUDA, will fallback to CPU)...");
        handle = OnnxCreateFromBuffer(buffer, ONNX_DEFAULT);

        if(handle == INVALID_HANDLE)
        {
            // CUDA initialization failed — retry with CPU-only execution provider.
            Print("[ONNX-CPU-FALLBACK] CUDA unavailable, using CPU execution provider");
            m_fallbackToCpu = true;
            handle = OnnxCreateFromBuffer(buffer, ONNX_USE_CPU_ONLY);
        }

        if(handle == INVALID_HANDLE)
        {
            PrintFormat("[ONNX] ERROR: Both default and CPU-only sessions failed | err=%d", GetLastError());
            return false;
        }

        if(!ConfigureHandle(handle))
        {
            OnnxRelease(handle);
            handle = INVALID_HANDLE;
            return false;
        }
        return true;
    }

    bool RunHandle(const long handle, int &signalOut, double &confidenceOut, float &probsOut[])
    {
        if(handle == INVALID_HANDLE || !m_full)
            return false;

        matrixf xInput;
        xInput.Resize(ONNX_SEQ_LEN, ONNX_FEAT_DIM);
        for(int t = 0; t < ONNX_SEQ_LEN; t++)
        {
            int src = OnnxPositiveMod(m_head - ONNX_SEQ_LEN + t, ONNX_SEQ_LEN);
            for(int f = 0; f < ONNX_FEAT_DIM; f++)
                xInput[t][f] = m_featureBuf[src][f];
        }

        vectorf yOutput;
        yOutput.Resize(ONNX_N_CLASSES);
        if(!OnnxRun(handle, ONNX_NO_CONVERSION, xInput, yOutput))
            return false;

        ArrayResize(probsOut, ONNX_N_CLASSES);
        float maxv = yOutput[0];
        for(int i = 1; i < ONNX_N_CLASSES; i++)
            maxv = MathMax(maxv, yOutput[i]);

        float sumExp = 0.0f;
        for(int i = 0; i < ONNX_N_CLASSES; i++)
        {
            probsOut[i] = (float)MathExp(yOutput[i] - maxv);
            sumExp += probsOut[i];
        }
        if(sumExp <= 1e-9f)
            sumExp = 1.0f;

        signalOut = 0;
        for(int i = 0; i < ONNX_N_CLASSES; i++)
        {
            probsOut[i] /= sumExp;
            if(!MathIsValidNumber(probsOut[i]) || probsOut[i] < 0.0f)
            {
                PrintFormat("[ONNX] Softmax output invalid at class %d: %f", i, probsOut[i]);
                return false;
            }
            if(probsOut[i] > probsOut[signalOut])
                signalOut = i;
        }
        confidenceOut = probsOut[signalOut];
        return true;
    }

public:
    COnnxBrain()
    {
        m_handle = INVALID_HANDLE;
        m_loaded = false;
        m_full = false;
        m_head = 0;
        m_signal = 1;
        m_confidence = 0.0;
        m_activeWins = 0.0;
        m_activeTotal = 0.0;
        m_activePnl = 0.0;
        m_fallbackToCpu = false;
        for(int i = 0; i < ONNX_SEQ_LEN; i++)
            for(int j = 0; j < ONNX_FEAT_DIM; j++)
                m_featureBuf[i][j] = 0.0f;
        for(int i = 0; i < ONNX_N_CLASSES; i++)
            m_probs[i] = 0.0f;
    }

    virtual ~COnnxBrain()
    {
        Deinit();
    }

    bool Init(const uchar &modelBuffer[])
    {
        // FIX: Always reset fallback state on fresh init to prevent CUDA failure state leak across re-inits
        Deinit();
        m_fallbackToCpu = false;
        if(!InitHandleFromBuffer(modelBuffer, m_handle))
        {
            PrintFormat("[ONNX] Model unavailable or invalid | err=%d | expected_shape=[1,%d,%d] | note=a model must be re-exported against FEATURE_VECTOR_SIZE, Resources/model.onnx was built for 57",
                        GetLastError(), ONNX_SEQ_LEN, ONNX_FEAT_DIM);
            return false;
        }

        m_loaded = true;
        Print("[ONNX] Model initialized");
        return true;
    }

    void Deinit()
    {
        if(m_handle != INVALID_HANDLE)
            OnnxRelease(m_handle);
        m_handle = INVALID_HANDLE;
        m_loaded = false;
        m_full = false;
        m_activeWins = 0.0;
        m_activeTotal = 0.0;
        m_activePnl = 0.0;
        m_fallbackToCpu = false;
        m_temperature = 1.0;
    }

    void PushFeatures(const double &features[], const int size)
    {
        int slot = m_head % ONNX_SEQ_LEN;
        for(int f = 0; f < ONNX_FEAT_DIM; f++)
            m_featureBuf[slot][f] = (f < size) ? (float)features[f] : 0.0f;
        m_head++;
        if(m_head >= ONNX_SEQ_LEN)
            m_full = true;
    }

    bool RunInference()
    {
        float probs[];
        if(!RunHandle(m_handle, m_signal, m_confidence, probs))
            return false;
        for(int i = 0; i < ONNX_N_CLASSES; i++)
            m_probs[i] = probs[i];

        return true;
    }

    int GetSignal() const { return m_signal; }           // 0=SELL,1=NEUTRAL,2=BUY
    double GetConfidence() const { return m_confidence; }
    double GetActiveAccuracy() const { return (m_activeTotal > 0) ? (m_activeWins / m_activeTotal) : 0.0; }
    int GetActiveTotal() const { return (int)m_activeTotal; }
    int GetActiveWins() const { return (int)m_activeWins; }
    double GetTemperature() const { return m_temperature; }
    void SetTemperature(const double temperature) { m_temperature = MathMax(0.1, MathMin(5.0, temperature)); }
    bool IsReady() const { return m_loaded && m_full; }
    bool IsLoaded() const { return m_loaded; }
    void GetProbs(float &out[]) const
    {
        ArrayResize(out, ONNX_N_CLASSES);
        for(int i = 0; i < ONNX_N_CLASSES; i++)
            out[i] = m_probs[i];
    }

    // [REMOVED 2026-08-14] Shadow-model hot-swap / auto-promotion logic removed.
    // Operation is Live-only: the active ONNX model is loaded once at Init and
    // used as-is. No shadow handle, no model file watch, no hot-swap, no promotion.
    // Live-model accuracy getters (GetActiveWins / GetActiveAccuracy) are retained
    // as no-op counters for diagnostic reporting.
};

#endif // __ONNX_BRAIN_MQH__
