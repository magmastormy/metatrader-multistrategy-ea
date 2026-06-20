//+------------------------------------------------------------------+
//| OnnxBrain.mqh                                                    |
//| Rolling-window ONNX inference with optional hot-swap shadow mode |
//+------------------------------------------------------------------+
#property strict

#ifndef __ONNX_BRAIN_MQH__
#define __ONNX_BRAIN_MQH__

#define ONNX_SEQ_LEN    60
#define ONNX_FEAT_DIM   FEATURE_VECTOR_SIZE
#define ONNX_N_CLASSES  3

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
    string m_watchPath;
    long   m_lastModelTime;
    long   m_shadowHandle;
    int    m_shadowBarsCount;
    int    m_shadowBarsNeeded;
    double m_promotionThreshold;
    double m_shadowWins;
    double m_shadowTotal;
    double m_activeWins;
    double m_activeTotal;
    int    m_shadowWarmup;
    int    m_shadowSignal;
    double m_shadowConfidence;
    bool   m_hasShadowPrediction;
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
            int src = (m_head - ONNX_SEQ_LEN + t + ONNX_SEQ_LEN * 1000) % ONNX_SEQ_LEN;
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
        m_watchPath = "";
        m_lastModelTime = 0;
        m_shadowHandle = INVALID_HANDLE;
        m_shadowBarsCount = 0;
        m_shadowBarsNeeded = 100;
        m_promotionThreshold = 0.01;
        m_shadowWins = 0.0;
        m_shadowTotal = 0.0;
        m_activeWins = 0.0;
        m_activeTotal = 0.0;
        m_shadowWarmup = 0;
        m_shadowSignal = 1;
        m_shadowConfidence = 0.0;
        m_hasShadowPrediction = false;
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
        bool prevFallback = m_fallbackToCpu;
        Deinit();
        m_fallbackToCpu = prevFallback;
        if(!InitHandleFromBuffer(modelBuffer, m_handle))
        {
            PrintFormat("[ONNX] Model unavailable or invalid | err=%d | expected_shape=[1,%d,%d] | note=re-export ONNX after the 57-feature contract upgrade",
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
        if(m_shadowHandle != INVALID_HANDLE)
            OnnxRelease(m_shadowHandle);
        m_handle = INVALID_HANDLE;
        m_shadowHandle = INVALID_HANDLE;
        m_loaded = false;
        m_full = false;
        m_shadowBarsCount = 0;
        m_shadowWins = 0.0;
        m_shadowTotal = 0.0;
        m_activeWins = 0.0;
        m_activeTotal = 0.0;
        m_shadowWarmup = 0;
        m_hasShadowPrediction = false;
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

        if(m_shadowHandle != INVALID_HANDLE && m_shadowWarmup >= ONNX_SEQ_LEN)
        {
            float shadowProbs[];
            if(RunHandle(m_shadowHandle, m_shadowSignal, m_shadowConfidence, shadowProbs))
                m_hasShadowPrediction = true;
            else
                m_hasShadowPrediction = false;
        }
        else
        {
            m_hasShadowPrediction = false;
        }

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

    void SetWatchPath(string path, int shadowBars = 100)
    {
        m_watchPath = path;
        m_shadowBarsNeeded = MathMax(10, shadowBars);
        m_shadowBarsCount = 0;
        m_shadowWarmup = 0;
    }

    void CheckForModelUpdate(const double &features[], const int size)
    {
        if(m_watchPath == "" || !FileIsExist(m_watchPath, FILE_COMMON))
            return;
        int fh = FileOpen(m_watchPath, FILE_READ | FILE_BIN | FILE_COMMON);
        if(fh == INVALID_HANDLE)
            return;

        long fileTime = (long)FileGetInteger(fh, FILE_MODIFY_DATE);
        if(fileTime <= m_lastModelTime)
        {
            FileClose(fh);
            return;
        }

        uchar newModelBuf[];
        int bytes = (int)FileSize(fh);
        if(bytes <= 0 || bytes > 50 * 1024 * 1024)
        {
            FileClose(fh);
            PrintFormat("[ONNX] Hot-swap: invalid file size %d bytes", bytes);
            return;
        }
        ArrayResize(newModelBuf, bytes);
        uint bytesRead = FileReadArray(fh, newModelBuf, 0, bytes);
        FileClose(fh);
        if((int)bytesRead != bytes)
        {
            PrintFormat("[ONNX] Hot-swap: read mismatch expected=%d got=%d", bytes, bytesRead);
            return;
        }

        if(m_shadowHandle != INVALID_HANDLE)
            OnnxRelease(m_shadowHandle);
        if(!InitHandleFromBuffer(newModelBuf, m_shadowHandle))
        {
            Print("[ONNX] Hot-swap shadow model failed to initialize");
            return;
        }

        m_shadowBarsCount = 0;
        m_shadowWins = 0.0;
        m_shadowTotal = 0.0;
        m_activeWins = 0.0;
        m_activeTotal = 0.0;
        m_shadowWarmup = 0;
        m_lastModelTime = fileTime;
        m_hasShadowPrediction = false;
        Print("[ONNX] Hot-swap shadow model armed");
    }

    void RecordOutcome(const bool activeCorrect, const bool shadowCorrect)
    {
        if(m_shadowHandle == INVALID_HANDLE)
            return;

        if(m_shadowWarmup < ONNX_SEQ_LEN)
        {
            m_shadowWarmup++;
            return;
        }

        m_shadowBarsCount++;
        if(activeCorrect)
            m_activeWins++;
        m_activeTotal++;
        if(shadowCorrect)
            m_shadowWins++;
        m_shadowTotal++;

        if(m_shadowBarsCount < m_shadowBarsNeeded)
            return;

        double activeAcc = m_activeWins / (m_activeTotal + 1e-9);
        double shadowAcc = m_shadowWins / (m_shadowTotal + 1e-9);
        if(shadowAcc > activeAcc + m_promotionThreshold)
        {
            if(m_handle != INVALID_HANDLE)
                OnnxRelease(m_handle);
            m_handle = m_shadowHandle;
            m_shadowHandle = INVALID_HANDLE;
            m_loaded = true;
            PrintFormat("[ONNX] Hot-swap promoted shadow model | shadow=%.3f | active=%.3f", shadowAcc, activeAcc);
        }
        else
        {
            OnnxRelease(m_shadowHandle);
            m_shadowHandle = INVALID_HANDLE;
            PrintFormat("[ONNX] Hot-swap rejected shadow model | shadow=%.3f | active=%.3f", shadowAcc, activeAcc);
        }

        m_shadowBarsCount = 0;
        m_shadowWins = 0.0;
        m_shadowTotal = 0.0;
        m_activeWins = 0.0;
        m_activeTotal = 0.0;
        m_hasShadowPrediction = false;
    }

    bool HasShadowPrediction() const { return m_hasShadowPrediction; }
    int GetShadowSignal() const { return m_shadowSignal; }
    double GetShadowConfidence() const { return m_shadowConfidence; }
};

#endif // __ONNX_BRAIN_MQH__
