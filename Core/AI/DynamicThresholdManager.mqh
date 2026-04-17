//+------------------------------------------------------------------+
//| Dynamic Threshold Manager                                       |
//| Adjusts AI confidence thresholds based on recent performance      |
//+------------------------------------------------------------------+
#ifndef CORE_AI_DYNAMIC_THRESHOLD_MANAGER_MQH
#define CORE_AI_DYNAMIC_THRESHOLD_MANAGER_MQH

#include "../Utils/Enums.mqh"

class CDynamicThresholdManager
{
private:
    double m_baseThreshold;
    double m_minThreshold;
    double m_maxThreshold;
    double m_currentThreshold;
    
    double m_performanceWindow[20];
    int m_windowIndex;
    int m_windowSize;
    
public:
    CDynamicThresholdManager(double base = 0.35, double min = 0.25, double max = 0.60) :
        m_baseThreshold(base),
        m_minThreshold(min),
        m_maxThreshold(max),
        m_currentThreshold(base),
        m_windowIndex(0),
        m_windowSize(0)
    {
        ArrayInitialize(m_performanceWindow, 0.0);
    }
    
    ~CDynamicThresholdManager() {}
    
    //+------------------------------------------------------------------+
    //| Update threshold based on recent trade result                   |
    //+------------------------------------------------------------------+
    void Update(double tradeResult)
    {
        m_performanceWindow[m_windowIndex] = tradeResult;
        m_windowIndex = (m_windowIndex + 1) % 20;
        if(m_windowSize < 20) m_windowSize++;
        
        double avgPerformance = 0;
        for(int i = 0; i < m_windowSize; i++)
            avgPerformance += m_performanceWindow[i];
            
        avgPerformance /= m_windowSize;
        
        // If performance is good, we can slightly lower the threshold to capture more opportunities
        // If performance is poor, we raise the threshold to be more selective
        if(avgPerformance > 0.5)
            m_currentThreshold = MathMax(m_minThreshold, m_currentThreshold - 0.01);
        else if(avgPerformance < -0.2)
            m_currentThreshold = MathMin(m_maxThreshold, m_currentThreshold + 0.02);
        else
            m_currentThreshold = m_baseThreshold;
    }
    
    double GetCurrentThreshold() const { return m_currentThreshold; }
};

#endif // CORE_AI_DYNAMIC_THRESHOLD_MANAGER_MQH
