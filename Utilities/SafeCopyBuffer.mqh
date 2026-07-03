//+------------------------------------------------------------------+
//| SafeCopyBuffer.mqh                                               |
//| Shared utility: retry-safe CopyBuffer wrapper                    |
//+------------------------------------------------------------------+
#ifndef UTILS_SAFE_COPY_BUFFER_MQH
#define UTILS_SAFE_COPY_BUFFER_MQH

#include "../IndicatorManager.mqh"

bool SafeCopyBuffer(int handle, int bufferIndex, int startPos, int count, double &buffer[])
{
    for(int attempt = 0; attempt < 3; attempt++)
    {
        if(CopyBuffer(handle, bufferIndex, startPos, count, buffer) >= count)
        {
            CIndicatorManager::Instance().AccessHandle(handle);
            return true;
        }
        Sleep(10);
    }
    return false;
}

#endif
