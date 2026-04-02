//+------------------------------------------------------------------+
//| StrategyRegistry.mqh                                             |
//| Central registry for strategy availability and mode filtering    |
//+------------------------------------------------------------------+
#property strict

#ifndef CORE_STRATEGY_STRATEGY_REGISTRY_MQH
#define CORE_STRATEGY_STRATEGY_REGISTRY_MQH

#include "../Utils/Enums.mqh"

struct SStrategyDescriptor
{
    string name;
    ENUM_STRATEGY_TYPE type;
    bool isAI;
    bool inputEnabled;
    bool modeEnabled;
    bool registered;
    bool initialized;
    bool mandatory;
    double weight;
    string failReason;

    SStrategyDescriptor()
    {
        name = "";
        type = STRATEGY_TYPE_CUSTOM;
        isAI = false;
        inputEnabled = false;
        modeEnabled = false;
        registered = false;
        initialized = false;
        mandatory = false;
        weight = 1.0;
        failReason = "";
    }
};

string EAModeToString(const ENUM_EA_MODE mode)
{
    switch(mode)
    {
        case EA_MODE_INDICATOR_ONLY: return "INDICATOR_ONLY";
        case EA_MODE_AI_ONLY: return "AI_ONLY";
        case EA_MODE_HYBRID: return "HYBRID";
        case EA_MODE_AI_ASSISTED: return "AI_ASSISTED";
        case EA_MODE_INDICATOR_FILTERED: return "INDICATOR_FILTERED";
        default: return "HYBRID";
    }
}

class CStrategyRegistry
{
private:
    SStrategyDescriptor m_descriptors[];
    ENUM_EA_MODE m_mode;
    datetime m_lastRefreshTime;

    int FindIndexByName(const string name) const
    {
        for(int i = 0; i < ArraySize(m_descriptors); i++)
        {
            if(m_descriptors[i].name == name)
                return i;
        }
        return -1;
    }

    bool IsModePermissiveForStrategy(const bool isAI) const
    {
        switch(m_mode)
        {
            case EA_MODE_INDICATOR_ONLY:
                return !isAI;
            case EA_MODE_AI_ONLY:
                return isAI;
            case EA_MODE_HYBRID:
            case EA_MODE_AI_ASSISTED:
            case EA_MODE_INDICATOR_FILTERED:
            default:
                return true;
        }
    }

    void RefreshModeFlags()
    {
        for(int i = 0; i < ArraySize(m_descriptors); i++)
            m_descriptors[i].modeEnabled = (m_descriptors[i].inputEnabled && IsModePermissiveForStrategy(m_descriptors[i].isAI));
        m_lastRefreshTime = TimeCurrent();
    }

public:
    CStrategyRegistry()
    {
        ArrayResize(m_descriptors, 0);
        m_mode = EA_MODE_HYBRID;
        m_lastRefreshTime = 0;
    }

    void Reset()
    {
        ArrayResize(m_descriptors, 0);
        m_lastRefreshTime = 0;
    }

    void SetMode(const ENUM_EA_MODE mode)
    {
        m_mode = mode;
        RefreshModeFlags();
    }

    ENUM_EA_MODE GetMode() const { return m_mode; }

    bool RegisterDefinition(const string name,
                            const ENUM_STRATEGY_TYPE type,
                            const bool isAI,
                            const bool inputEnabled,
                            const bool mandatory,
                            const double weight)
    {
        int index = FindIndexByName(name);
        if(index < 0)
        {
            index = ArraySize(m_descriptors);
            ArrayResize(m_descriptors, index + 1);
        }

        m_descriptors[index].name = name;
        m_descriptors[index].type = type;
        m_descriptors[index].isAI = isAI;
        m_descriptors[index].inputEnabled = inputEnabled;
        m_descriptors[index].mandatory = mandatory;
        m_descriptors[index].weight = MathMax(0.0, weight);
        m_descriptors[index].registered = false;
        m_descriptors[index].initialized = false;
        m_descriptors[index].failReason = "";
        m_descriptors[index].modeEnabled = (inputEnabled && IsModePermissiveForStrategy(isAI));
        m_lastRefreshTime = TimeCurrent();
        return true;
    }

    bool SetInputEnabled(const string name, const bool enabled)
    {
        int index = FindIndexByName(name);
        if(index < 0)
            return false;
        m_descriptors[index].inputEnabled = enabled;
        RefreshModeFlags();
        return true;
    }

    bool SetWeight(const string name, const double weight)
    {
        int index = FindIndexByName(name);
        if(index < 0)
            return false;
        m_descriptors[index].weight = MathMax(0.0, weight);
        return true;
    }

    bool IsStrategyActive(const string name) const
    {
        int index = FindIndexByName(name);
        if(index < 0)
            return false;
        return m_descriptors[index].modeEnabled;
    }

    bool GetDescriptor(const int index, SStrategyDescriptor &descriptor) const
    {
        if(index < 0 || index >= ArraySize(m_descriptors))
            return false;
        descriptor = m_descriptors[index];
        return true;
    }

    bool GetDescriptorByName(const string name, SStrategyDescriptor &descriptor) const
    {
        int index = FindIndexByName(name);
        if(index < 0)
            return false;
        descriptor = m_descriptors[index];
        return true;
    }

    bool MarkRegistered(const string name, const bool ok, const string failReason = "")
    {
        int index = FindIndexByName(name);
        if(index < 0)
            return false;
        m_descriptors[index].registered = ok;
        m_descriptors[index].initialized = ok;
        m_descriptors[index].failReason = ok ? "" : failReason;
        return true;
    }

    int GetDescriptorCount() const { return ArraySize(m_descriptors); }

    int GetActiveCount() const
    {
        int total = 0;
        for(int i = 0; i < ArraySize(m_descriptors); i++)
        {
            if(m_descriptors[i].modeEnabled)
                total++;
        }
        return total;
    }

    int GetActiveIndicatorCount() const
    {
        int total = 0;
        for(int i = 0; i < ArraySize(m_descriptors); i++)
        {
            if(m_descriptors[i].modeEnabled && !m_descriptors[i].isAI)
                total++;
        }
        return total;
    }

    int GetActiveAICount() const
    {
        int total = 0;
        for(int i = 0; i < ArraySize(m_descriptors); i++)
        {
            if(m_descriptors[i].modeEnabled && m_descriptors[i].isAI)
                total++;
        }
        return total;
    }

    double GetWeightByName(const string name) const
    {
        int index = FindIndexByName(name);
        if(index < 0)
            return 0.0;
        return m_descriptors[index].weight;
    }

    string BuildStatusReport() const
    {
        string report = StringFormat("mode=%s | active=%d | indicators=%d | ai=%d",
                                     EAModeToString(m_mode),
                                     GetActiveCount(),
                                     GetActiveIndicatorCount(),
                                     GetActiveAICount());

        for(int i = 0; i < ArraySize(m_descriptors); i++)
        {
            string state = m_descriptors[i].modeEnabled ? "ACTIVE" : (m_descriptors[i].inputEnabled ? "MODE_OFF" : "DISABLED");
            report += StringFormat(" | %s:%s@%.2f", m_descriptors[i].name, state, m_descriptors[i].weight);
        }
        return report;
    }
};

#endif // CORE_STRATEGY_STRATEGY_REGISTRY_MQH
