//+------------------------------------------------------------------+
//| StructureSwing.mqh - Swing high/low detection                    |
//| Extracted verbatim from StructureEngine.mqh (no behavior change) |
//|                                                                  |
//| Owns the swing sizing configuration (minSwingSize / useATR) and  |
//| the real-time "potential swing" tracking slots (L4-009 fix).     |
//+------------------------------------------------------------------+
#property copyright "Enterprise Trading Solutions"
#property version   "2.0"
#property strict

#ifndef STRUCTURE_SWING_MQH
#define STRUCTURE_SWING_MQH

#include "StructureTypes.mqh"

//+------------------------------------------------------------------+
//| Swing point detector - owns swing config + potential slots       |
//+------------------------------------------------------------------+
class CStructureSwingDetector
{
private:
    // Configuration (mirrors the engine defaults)
    double m_minSwingSize;          // Minimum swing size in points
    bool   m_useATR;                // Use ATR for adaptive thresholds

    // Potential swing tracking for real-time detection (L4-009 fix)
    double m_potentialSwingHighPrice;    // Price of potential swing high
    int    m_potentialSwingHighIndex;    // Index of potential swing high
    double m_potentialSwingLowPrice;     // Price of potential swing low
    int    m_potentialSwingLowIndex;     // Index of potential swing low
    bool   m_potentialSwingHighValid;    // Flag if potential swing high is valid
    bool   m_potentialSwingLowValid;     // Flag if potential swing low is valid

public:
    CStructureSwingDetector();

    //--- Configuration
    void Configure(double minSwingSize, bool useATR)
    {
        m_minSwingSize = minSwingSize;
        m_useATR = useATR;
    }

    //--- Swing predicates
    bool IsSwingHigh(const MqlRates &rates[], int index, int period);
    bool IsSwingLow(const MqlRates &rates[], int index, int period);
    bool IsPotentialSwingHigh(const MqlRates &rates[], int index, int period);
    bool IsPotentialSwingLow(const MqlRates &rates[], int index, int period);
    bool IsConfirmedSwingHigh(const MqlRates &rates[], int index, int period);
    bool IsConfirmedSwingLow(const MqlRates &rates[], int index, int period);

    //--- Potential swing slot accessors
    bool   PotentialHighValid() const { return m_potentialSwingHighValid; }
    int    PotentialHighIndex() const { return m_potentialSwingHighIndex; }
    double PotentialHighPrice() const { return m_potentialSwingHighPrice; }
    bool   PotentialLowValid()  const { return m_potentialSwingLowValid;  }
    int    PotentialLowIndex()  const { return m_potentialSwingLowIndex;  }
    double PotentialLowPrice()  const { return m_potentialSwingLowPrice;  }

    void MarkPotentialHigh(int index, double price)
    {
        m_potentialSwingHighValid = true;
        m_potentialSwingHighIndex = index;
        m_potentialSwingHighPrice = price;
    }

    void MarkPotentialLow(int index, double price)
    {
        m_potentialSwingLowValid = true;
        m_potentialSwingLowIndex = index;
        m_potentialSwingLowPrice = price;
    }

    void ClearPotentialHigh()
    {
        m_potentialSwingHighValid = false;
        m_potentialSwingHighIndex = -1;
        m_potentialSwingHighPrice = 0;
    }

    void ClearPotentialLow()
    {
        m_potentialSwingLowValid = false;
        m_potentialSwingLowIndex = -1;
        m_potentialSwingLowPrice = 0;
    }

    void ResetPotentials()
    {
        ClearPotentialHigh();
        ClearPotentialLow();
    }
};

//+------------------------------------------------------------------+
//| Constructor - defaults mirror CStructureEngine::CStructureEngine |
//+------------------------------------------------------------------+
CStructureSwingDetector::CStructureSwingDetector() :
    m_minSwingSize(10.0),
    m_useATR(true),
    m_potentialSwingHighPrice(0),
    m_potentialSwingHighIndex(-1),
    m_potentialSwingLowPrice(0),
    m_potentialSwingLowIndex(-1),
    m_potentialSwingHighValid(false),
    m_potentialSwingLowValid(false)
{
}

//+------------------------------------------------------------------+
//| Check if bar is a swing high                                    |
//+------------------------------------------------------------------+
bool CStructureSwingDetector::IsSwingHigh(const MqlRates &rates[], int index, int period)
{
    if(index < period || index >= ArraySize(rates) - period)
        return false;
    
    double high = rates[index].high;
    
    // Check left side
    for(int i = 1; i <= period; i++)
    {
        if(rates[index - i].high >= high)
            return false;
    }
    
    // Check right side
    for(int i = 1; i <= period; i++)
    {
        if(rates[index + i].high > high)
            return false;
    }
    
    // Verify minimum swing size
    double avgBody = 0;
    for(int i = index - period; i <= index + period; i++)
    {
        avgBody += MathAbs(rates[i].close - rates[i].open);
    }
    avgBody /= (period * 2 + 1);
    
    if(m_useATR)
    {
        // Use body size as proxy for ATR
        return avgBody > 0 && (high - rates[index].low) > avgBody * 2;
    }
    else
    {
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        return (high - rates[index].low) > m_minSwingSize * point;
    }
}

//+------------------------------------------------------------------+
//| Check if bar is a swing low                                     |
//+------------------------------------------------------------------+
bool CStructureSwingDetector::IsSwingLow(const MqlRates &rates[], int index, int period)
{
    if(index < period || index >= ArraySize(rates) - period)
        return false;
    
    double low = rates[index].low;
    
    // Check left side
    for(int i = 1; i <= period; i++)
    {
        if(rates[index - i].low <= low)
            return false;
    }
    
    // Check right side  
    for(int i = 1; i <= period; i++)
    {
        if(rates[index + i].low < low)
            return false;
    }
    
    // Verify minimum swing size
    double avgBody = 0;
    for(int i = index - period; i <= index + period; i++)
    {
        avgBody += MathAbs(rates[i].close - rates[i].open);
    }
    avgBody /= (period * 2 + 1);
    
    if(m_useATR)
    {
        return avgBody > 0 && (rates[index].high - low) > avgBody * 2;
    }
    else
    {
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        return (rates[index].high - low) > m_minSwingSize * point;
    }
}

//+------------------------------------------------------------------+
//| Check if bar is a potential swing high (left side only - real-time)
//+------------------------------------------------------------------+
bool CStructureSwingDetector::IsPotentialSwingHigh(const MqlRates &rates[], int index, int period)
{
    if(index < period || index >= ArraySize(rates))
        return false;
    
    double high = rates[index].high;
    
    // Check left side only (historical confirmation)
    for(int i = 1; i <= period; i++)
    {
        if(rates[index - i].high >= high)
            return false;
    }
    
    // Verify minimum swing size (same logic as IsSwingHigh)
    double avgBody = 0;
    int count = 0;
    for(int i = index - period; i <= index; i++)
    {
        if(i >= 0 && i < ArraySize(rates))
        {
            avgBody += MathAbs(rates[i].close - rates[i].open);
            count++;
        }
    }
    avgBody = (count > 0) ? avgBody / count : 0;
    
    if(m_useATR)
    {
        return avgBody > 0 && (high - rates[index].low) > avgBody * 2;
    }
    else
    {
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        return (high - rates[index].low) > m_minSwingSize * point;
    }
}

//+------------------------------------------------------------------+
//| Check if bar is a potential swing low (left side only - real-time)
//+------------------------------------------------------------------+
bool CStructureSwingDetector::IsPotentialSwingLow(const MqlRates &rates[], int index, int period)
{
    if(index < period || index >= ArraySize(rates))
        return false;
    
    double low = rates[index].low;
    
    // Check left side only (historical confirmation)
    for(int i = 1; i <= period; i++)
    {
        if(rates[index - i].low <= low)
            return false;
    }
    
    // Verify minimum swing size (same logic as IsSwingLow)
    double avgBody = 0;
    int count = 0;
    for(int i = index - period; i <= index; i++)
    {
        if(i >= 0 && i < ArraySize(rates))
        {
            avgBody += MathAbs(rates[i].close - rates[i].open);
            count++;
        }
    }
    avgBody = (count > 0) ? avgBody / count : 0;
    
    if(m_useATR)
    {
        return avgBody > 0 && (rates[index].high - low) > avgBody * 2;
    }
    else
    {
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        return (rates[index].high - low) > m_minSwingSize * point;
    }
}

//+------------------------------------------------------------------+
//| Check if bar is a confirmed swing high (both sides - historical)
//+------------------------------------------------------------------+
bool CStructureSwingDetector::IsConfirmedSwingHigh(const MqlRates &rates[], int index, int period)
{
    if(index < period || index >= ArraySize(rates) - period)
        return false;
    
    double high = rates[index].high;
    
    // Check left side
    for(int i = 1; i <= period; i++)
    {
        if(rates[index - i].high >= high)
            return false;
    }
    
    // Check right side (future bars)
    for(int i = 1; i <= period; i++)
    {
        if(rates[index + i].high > high)
            return false;
    }
    
    // Verify minimum swing size
    double avgBody = 0;
    int count = 0;
    for(int i = index - period; i <= index + period; i++)
    {
        if(i >= 0 && i < ArraySize(rates))
        {
            avgBody += MathAbs(rates[i].close - rates[i].open);
            count++;
        }
    }
    avgBody = (count > 0) ? avgBody / count : 0;
    
    if(m_useATR)
    {
        return avgBody > 0 && (high - rates[index].low) > avgBody * 2;
    }
    else
    {
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        return (high - rates[index].low) > m_minSwingSize * point;
    }
}

//+------------------------------------------------------------------+
//| Check if bar is a confirmed swing low (both sides - historical)
//+------------------------------------------------------------------+
bool CStructureSwingDetector::IsConfirmedSwingLow(const MqlRates &rates[], int index, int period)
{
    if(index < period || index >= ArraySize(rates) - period)
        return false;
    
    double low = rates[index].low;
    
    // Check left side
    for(int i = 1; i <= period; i++)
    {
        if(rates[index - i].low <= low)
            return false;
    }
    
    // Check right side (future bars)
    for(int i = 1; i <= period; i++)
    {
        if(rates[index + i].low < low)
            return false;
    }
    
    // Verify minimum swing size
    double avgBody = 0;
    int count = 0;
    for(int i = index - period; i <= index + period; i++)
    {
        if(i >= 0 && i < ArraySize(rates))
        {
            avgBody += MathAbs(rates[i].close - rates[i].open);
            count++;
        }
    }
    avgBody = (count > 0) ? avgBody / count : 0;
    
    if(m_useATR)
    {
        return avgBody > 0 && (rates[index].high - low) > avgBody * 2;
    }
    else
    {
        double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
        return (rates[index].high - low) > m_minSwingSize * point;
    }
}

#endif // STRUCTURE_SWING_MQH
