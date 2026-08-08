//+------------------------------------------------------------------+
//| Unified Registry Interface - Enterprise Grade                    |
//| Common interface and base class for all registries               |
//+------------------------------------------------------------------+
#ifndef I_REGISTRY_MQH
#define I_REGISTRY_MQH

//+------------------------------------------------------------------+
//| IRegistry Interface                                              |
//+------------------------------------------------------------------+
template<typename T>
class IRegistry
{
public:
    virtual ~IRegistry() {}
    
    // Get instance by symbol (returns NULL if not found)
    virtual T* Get(const string symbol) const = 0;
    
    // Register instance for symbol (takes ownership)
    virtual bool Register(const string symbol, T* instance) = 0;
    
    // Unregister instance for symbol (caller takes ownership)
    virtual T* Unregister(const string symbol) = 0;
    
    // Check if symbol is registered
    virtual bool Has(const string symbol) const = 0;
    
    // Get all registered symbols
    virtual void GetSymbols(string &symbols[]) const = 0;
    
    // Get count of registered instances
    virtual int Count() const = 0;
    
    // Clear all registrations (deletes instances if owned)
    virtual void Clear() = 0;
};

//+------------------------------------------------------------------+
//| Registry Base Class                                              |
//+------------------------------------------------------------------+
template<typename T>
class CRegistryBase : public IRegistry<T>
{
private:
    string m_symbols[];
    T* m_instances[];
    int m_count;
    bool m_ownInstances;

protected:
    // Helper to find symbol index
    int FindIndex(const string symbol) const
    {
        int count = ArraySize(m_symbols);
        for(int i = 0; i < count; i++)
        {
            if(m_symbols[i] == symbol)
                return i;
        }
        return -1;
    }

public:
    CRegistryBase(bool ownInstances = true) : m_count(0), m_ownInstances(ownInstances)
    {
        ArrayResize(m_symbols, 0);
        ArrayResize(m_instances, 0);
    }
    
    virtual ~CRegistryBase()
    {
        Clear();
    }
    
    // Get instance by symbol
    virtual T* Get(const string symbol) const override
    {
        int index = FindIndex(symbol);
        if(index >= 0)
            return m_instances[index];
        return NULL;
    }
    
    // Register instance for symbol
    virtual bool Register(const string symbol, T* instance) override
    {
        if(instance == NULL || symbol == "")
            return false;
        
        int index = FindIndex(symbol);
        if(index >= 0)
        {
            // Symbol already registered - replace if owning
            if(m_ownInstances && m_instances[index] != NULL)
            {
                delete m_instances[index];
            }
            m_instances[index] = instance;
            return true;
        }
        
        // Add new registration
        int newSize = m_count + 1;
        ArrayResize(m_symbols, newSize);
        ArrayResize(m_instances, newSize);
        m_symbols[m_count] = symbol;
        m_instances[m_count] = instance;
        m_count = newSize;
        return true;
    }
    
    // Unregister instance for symbol
    virtual T* Unregister(const string symbol) override
    {
        int index = FindIndex(symbol);
        if(index < 0)
            return NULL;
        
        T* instance = m_instances[index];
        
        // Remove from arrays
        int count = ArraySize(m_symbols);
        for(int i = index; i < count - 1; i++)
        {
            m_symbols[i] = m_symbols[i + 1];
            m_instances[i] = m_instances[i + 1];
        }
        ArrayResize(m_symbols, count - 1);
        ArrayResize(m_instances, count - 1);
        m_count--;
        
        return instance;
    }
    
    // Check if symbol is registered
    virtual bool Has(const string symbol) const override
    {
        return FindIndex(symbol) >= 0;
    }
    
    // Get all registered symbols
    virtual void GetSymbols(string &symbols[]) const override
    {
        symbols = m_symbols;
    }
    
    // Get count of registered instances
    virtual int Count() const override
    {
        return m_count;
    }
    
    // Clear all registrations
    virtual void Clear() override
    {
        if(m_ownInstances)
        {
            int count = ArraySize(m_instances);
            for(int i = 0; i < count; i++)
            {
                if(m_instances[i] != NULL)
                {
                    delete m_instances[i];
                    m_instances[i] = NULL;
                }
            }
        }
        ArrayResize(m_symbols, 0);
        ArrayResize(m_instances, 0);
        m_count = 0;
    }
    
    // Set ownership policy
    void SetOwnership(bool own) { m_ownInstances = own; }
    bool GetOwnership() const { return m_ownInstances; }
};

#endif // I_REGISTRY_MQH