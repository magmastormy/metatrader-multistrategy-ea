//+------------------------------------------------------------------+
//| SafeCopyBuffer.mqh                                               |
//| Shared utility: retry-safe CopyBuffer wrapper                    |
//+------------------------------------------------------------------+
#ifndef UTILS_SAFE_COPY_BUFFER_MQH
#define UTILS_SAFE_COPY_BUFFER_MQH

#include "../IndicatorManager.mqh"

bool SafeCopyBuffer(int handle, int bufferIndex, int startPos, int count, double &buffer[])
{
    // Batch 150: Sleep(10) removed - it stalled OnTick up to 30ms per failing buffer
    // (14 strategies x several buffers) exactly during indicator warmup. Immediate
    // retries still cover the async-recalc race without blocking the tick path.
    for(int attempt = 0; attempt < 3; attempt++)
    {
        if(CopyBuffer(handle, bufferIndex, startPos, count, buffer) >= count)
        {
            CIndicatorManager::Instance().AccessHandle(handle);
            return true;
        }
    }
    return false;
}

#endif
