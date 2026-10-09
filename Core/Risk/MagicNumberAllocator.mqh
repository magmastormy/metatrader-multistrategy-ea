// Centralized magic number allocation service
// L1-015: Eliminates scattered magic number logic across classes
#property strict

#ifndef CORE_RISK_MAGIC_NUMBER_ALLOCATOR_MQH
#define CORE_RISK_MAGIC_NUMBER_ALLOCATOR_MQH

#include "../../Core/Utils/Enums.mqh"
#include <Object.mqh>

// Single authority for magic number allocation across all systems
class CMagicNumberAllocator : public CObject
{
private:
    // Configuration
    int    m_baseMagicNumber;
    int    m_symbolMultiplier;
    int    m_maxClusterCode;
    int    m_maxFamilyOffset;
    int    m_maxStrategyOffset;
    
    // Tracking allocated ranges
    struct SMagicAllocation
    {
        string symbol;
        int    familyOffset;
        int    strategyOffset;
        int    clusterCode;
        int    allocatedMagic;
        bool   inUse;
        
        SMagicAllocation()
        {
            symbol = "";
            familyOffset = 0;
            strategyOffset = 0;
            clusterCode = 0;
            allocatedMagic = 0;
            inUse = false;
        }
    };
    
    SMagicAllocation m_allocations[];
    int m_allocationCount;
    
    // Family to offset mapping (configured externally)
    struct SFamilyOffset
    {
        string familyName;
        int    magicOffset;
        bool   enabled;
    };
    SFamilyOffset m_familyOffsets[];
    
    // Cluster code to base offset mapping
    struct SClusterOffset
    {
        ENUM_STRATEGY_CLUSTER cluster;
        int baseOffset;
    };
    SClusterOffset m_clusterOffsets[];
    
    // Find existing allocation
    int FindAllocation(const string symbol, int familyOffset, int strategyOffset, int clusterCode) const
    {
        for(int i = 0; i < m_allocationCount; i++)
        {
            if(m_allocations[i].inUse &&
               m_allocations[i].symbol == symbol &&
               m_allocations[i].familyOffset == familyOffset &&
               m_allocations[i].strategyOffset == strategyOffset &&
               m_allocations[i].clusterCode == clusterCode)
            {
                return i;
            }
        }
        return -1;
    }
    
    // Calculate magic number from components
    int CalculateMagic(int familyOffset, int strategyOffset, int clusterCode, int symbolIndex) const
    {
        if(clusterCode > m_maxClusterCode)
        {
            PrintFormat("[MAGIC-ALLOC] WARNING: Cluster code %d exceeds MAX_CLUSTER_CODE %d, clamping", clusterCode, m_maxClusterCode);
            clusterCode = m_maxClusterCode;
        }
        return m_baseMagicNumber + 
               symbolIndex * m_symbolMultiplier + 
               familyOffset + 
               strategyOffset + 
               clusterCode;
    }

public:
    CMagicNumberAllocator()
    {
        m_baseMagicNumber = 123456;
        m_symbolMultiplier = 100;
        m_maxClusterCode = 99;
        m_maxFamilyOffset = 9000;
        m_maxStrategyOffset = 1000;
        m_allocationCount = 0;
        ArrayResize(m_allocations, 0);
        ArrayResize(m_familyOffsets, 0);
        ArrayResize(m_clusterOffsets, 0);
        
        // Default family offsets (Deriv families from Batch 103)
        AddFamilyOffset("VOLATILITY", 1000, true);
        AddFamilyOffset("BOOM_CRASH", 2000, true);
        AddFamilyOffset("JUMP", 3000, true);
        AddFamilyOffset("STEP_INDEX", 4000, true);
        AddFamilyOffset("FOREX_MAJORS", 5000, true);
        AddFamilyOffset("FOREX_CROSSES", 6000, true);
        AddFamilyOffset("FOREX_EXOTICS", 7000, true);
        AddFamilyOffset("CRYPTO", 8000, true);
        AddFamilyOffset("METALS", 9000, true);
        
        // Default cluster offsets
        AddClusterOffset(TREND_CLUSTER, 0);
        AddClusterOffset(MEAN_REVERSION_CLUSTER, 10);
        AddClusterOffset(STRUCTURE_CLUSTER, 20);
        AddClusterOffset(SCALP_CLUSTER, 30);
        AddClusterOffset(STRATEGY_CLUSTER_NONE, 90);
    }
    
    ~CMagicNumberAllocator()
    {
        ArrayResize(m_allocations, 0);
        ArrayResize(m_familyOffsets, 0);
        ArrayResize(m_clusterOffsets, 0);
    }
    
    // Initialize with EA base magic number
    void Initialize(int baseMagic, int symbolMultiplier = 100)
    {
        m_baseMagicNumber = baseMagic;
        m_symbolMultiplier = symbolMultiplier;
    }
    
    // Add/Update family offset mapping
    void AddFamilyOffset(const string familyName, int offset, bool enabled = true)
    {
        int idx = FindFamilyOffset(familyName);
        if(idx >= 0)
        {
            m_familyOffsets[idx].magicOffset = offset;
            m_familyOffsets[idx].enabled = enabled;
        }
        else
        {
            int newSize = ArraySize(m_familyOffsets) + 1;
            ArrayResize(m_familyOffsets, newSize);
            m_familyOffsets[newSize - 1].familyName = familyName;
            m_familyOffsets[newSize - 1].magicOffset = offset;
            m_familyOffsets[newSize - 1].enabled = enabled;
        }
    }
    
    int FindFamilyOffset(const string familyName) const
    {
        for(int i = 0; i < ArraySize(m_familyOffsets); i++)
        {
            if(m_familyOffsets[i].familyName == familyName)
                return i;
        }
        return -1;
    }
    
    int GetFamilyOffset(const string familyName) const
    {
        int idx = FindFamilyOffset(familyName);
        if(idx >= 0 && m_familyOffsets[idx].enabled)
            return m_familyOffsets[idx].magicOffset;
        return 0;
    }
    
    // Add/Update cluster offset mapping
    void AddClusterOffset(ENUM_STRATEGY_CLUSTER cluster, int offset)
    {
        if((int)cluster > m_maxClusterCode)
        {
            PrintFormat("[MAGIC-ALLOC] ERROR: Cluster enum value %d exceeds MAX_CLUSTER_CODE %d", (int)cluster, m_maxClusterCode);
            return;
        }
        int idx = FindClusterOffset(cluster);
        if(idx >= 0)
        {
            m_clusterOffsets[idx].baseOffset = offset;
        }
        else
        {
            int newSize = ArraySize(m_clusterOffsets) + 1;
            ArrayResize(m_clusterOffsets, newSize);
            m_clusterOffsets[newSize - 1].cluster = cluster;
            m_clusterOffsets[newSize - 1].baseOffset = offset;
        }
    }
    
    int FindClusterOffset(ENUM_STRATEGY_CLUSTER cluster) const
    {
        for(int i = 0; i < ArraySize(m_clusterOffsets); i++)
        {
            if(m_clusterOffsets[i].cluster == cluster)
                return i;
        }
        return -1;
    }
    
    int GetClusterOffset(ENUM_STRATEGY_CLUSTER cluster) const
    {
        int idx = FindClusterOffset(cluster);
        if(idx >= 0)
            return m_clusterOffsets[idx].baseOffset;
        return 0;
    }
    
    // Main allocation API ---------------------------------------------------------------------
    // Allocate magic number for a strategy
    // symbol: Trading symbol
    // family: Asset family (e.g., "VOLATILITY", "FOREX_MAJORS")  
    // strategyType: Type of strategy for strategy-specific offset
    // cluster: Strategy cluster for clustering
    // symbolIndex: Index of symbol in trading universe (0-based)
    int Allocate(const string symbol, 
                 const string family,
                 ENUM_STRATEGY_TYPE strategyType,
                 ENUM_STRATEGY_CLUSTER cluster,
                 int symbolIndex)
    {
        int familyOffset = GetFamilyOffset(family);
        
        // Get strategy-specific offset
        int strategyOffset = GetStrategyOffset(strategyType);
        
        int clusterOffset = GetClusterOffset(cluster);
        int clusterCode = clusterOffset;
        
        int existingIdx = FindAllocation(symbol, familyOffset, strategyOffset, clusterCode);
        if(existingIdx >= 0)
        {
            return m_allocations[existingIdx].allocatedMagic;
        }
        
        // Calculate new magic number
        int magic = CalculateMagic(familyOffset, strategyOffset, clusterCode, symbolIndex);
        
        // Store allocation
        int newSize = m_allocationCount + 1;
        ArrayResize(m_allocations, newSize);
        m_allocations[m_allocationCount].symbol = symbol;
        m_allocations[m_allocationCount].familyOffset = familyOffset;
        m_allocations[m_allocationCount].strategyOffset = strategyOffset;
        m_allocations[m_allocationCount].clusterCode = clusterCode;
        m_allocations[m_allocationCount].allocatedMagic = magic;
        m_allocations[m_allocationCount].inUse = true;
        m_allocationCount++;
        
        PrintFormat("[MAGIC-ALLOC] %s | family=%s | strategy=%s | cluster=%s | magic=%d",
                    symbol, family, EnumToString(strategyType), EnumToString(cluster), magic);
        
        return magic;
    }
    
    // Simplified allocation for backward compatibility
    int AllocateSimple(const string symbol, int familyOffset, int strategyOffset, int clusterCode, int symbolIndex)
    {
        int existingIdx = FindAllocation(symbol, familyOffset, strategyOffset, clusterCode);
        if(existingIdx >= 0)
            return m_allocations[existingIdx].allocatedMagic;
        
        int magic = CalculateMagic(familyOffset, strategyOffset, clusterCode, symbolIndex);
        
        int newSize = m_allocationCount + 1;
        ArrayResize(m_allocations, newSize);
        m_allocations[m_allocationCount].symbol = symbol;
        m_allocations[m_allocationCount].familyOffset = familyOffset;
        m_allocations[m_allocationCount].strategyOffset = strategyOffset;
        m_allocations[m_allocationCount].clusterCode = clusterCode;
        m_allocations[m_allocationCount].allocatedMagic = magic;
        m_allocations[m_allocationCount].inUse = true;
        m_allocationCount++;
        
        return magic;
    }
    
    int GetStrategyOffset(ENUM_STRATEGY_TYPE strategyType) const
    {
        // Map strategy types to offsets within family range
        switch((int)strategyType)
        {
            case STRATEGY_MOMENTUM: return 100;
            case STRATEGY_TREND: return 200;
            case STRATEGY_SUPPORT_RESISTANCE: return 300;
            case STRATEGY_UNIFIED_ICT: return 400;
            case STRATEGY_CANDLESTICK: return 500;
            case STRATEGY_UNICORN_MODEL: return 600;
            case STRATEGY_POWER_OF_THREE: return 700;
            case STRATEGY_MEAN_REVERSION: return 800;
            case STRATEGY_VOLATILITY_BREAKOUT: return 900;
            case STRATEGY_STATISTICAL_ARBITRAGE: return 1000;
            case STRATEGY_FVG_SCALPER: return 1100;
            case STRATEGY_TURTLE_SOUP: return 1200;
            case STRATEGY_BREAKER_BLOCK: return 1300;
            case STRATEGY_NY_OPEN_GAP: return 1400;
            case STRATEGY_ASIAN_RANGE_BREAK: return 1500;
            case STRATEGY_LIQUIDITY_SWEEP: return 1600;
            case STRATEGY_RANGE_COMPRESSION: return 1700;
            case STRATEGY_EXIT_OPTIMIZER: return 1800;
            case STRATEGY_BRAIN: return 5000;  // AI strategies get higher offsets
            case STRATEGY_AI_ENHANCED: return 6000;
            default: return 0;
        }
    }
    
    // Validate magic number is within expected range
    bool IsValidMagic(int magic, int symbolIndex) const
    {
        int minMagic = m_baseMagicNumber + symbolIndex * m_symbolMultiplier;
        int maxMagic = minMagic + m_maxFamilyOffset + m_maxStrategyOffset + m_maxClusterCode;
        return (magic >= minMagic && magic <= maxMagic);
    }
    
    // Get base magic for symbol (for EA-owned position checks)
    int GetBaseMagicForSymbol(int symbolIndex) const
    {
        return m_baseMagicNumber + symbolIndex * m_symbolMultiplier;
    }
    
    // Get max magic for symbol range
    int GetMaxMagicForSymbol(int symbolIndex) const
    {
        return GetBaseMagicForSymbol(symbolIndex) + m_maxFamilyOffset + m_maxStrategyOffset + m_maxClusterCode;
    }
    
    // Check if magic belongs to this EA
        bool IsEAMagic(int magic, int symbolCount) const
        {
            for(int i = 0; i < symbolCount; i++)
            {
                int base = GetBaseMagicForSymbol(i);
                int maxMagic = GetMaxMagicForSymbol(i);
                if(magic >= base && magic <= maxMagic)
                    return true;
            }
            return false;
        }
    
        // Get max cluster code (L7-008)
        int GetMaxClusterCode() const
        {
            return m_maxClusterCode;
        }
    
        // Get max strategy offset (L7-008)
        int GetMaxStrategyOffset() const
        {
            return m_maxStrategyOffset;
        }
    
        // Get max family offset (L7-008)
        int GetMaxFamilyOffset() const
        {
            return m_maxFamilyOffset;
        }
    
    string GetAllocationReport() const
    {
        string report = "[MAGIC-ALLOCATOR] Current Allocations:\n";
        for(int i = 0; i < m_allocationCount; i++)
        {
            if(m_allocations[i].inUse)
            {
                report += StringFormat("  %s | family_offset=%d | strat_offset=%d | cluster=%d | magic=%d\n",
                                     m_allocations[i].symbol,
                                     m_allocations[i].familyOffset,
                                     m_allocations[i].strategyOffset,
                                     m_allocations[i].clusterCode,
                                     m_allocations[i].allocatedMagic);
            }
        }
        return report;
    }
    
    // Reset all allocations (for reinitialization)
    void Reset()
    {
        for(int i = 0; i < m_allocationCount; i++)
        {
            m_allocations[i].inUse = false;
        }
        m_allocationCount = 0;
    }
};

#endif // CORE_RISK_MAGIC_NUMBER_ALLOCATOR_MQH