//+------------------------------------------------------------------+
//| SafeCopyBuffer.mqh                                               |
//| Shared utility: retry-safe CopyBuffer wrapper                    |
//+------------------------------------------------------------------+
#ifndef __UTILS_SAFE_COPY_BUFFER_MQH__
#define __UTILS_SAFE_COPY_BUFFER_MQH__

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
