//+------------------------------------------------------------------+
//| Session Manager - Robust Market Session Tracking                |
//| Prevents trading during closed markets and scheduled breaks       |
//+------------------------------------------------------------------+
#ifndef CORE_UTILS_SESSION_MANAGER_MQH
#define CORE_UTILS_SESSION_MANAGER_MQH

#include <Trade\SymbolInfo.mqh>

class CSessionManager
{
private:
    CSymbolInfo m_symbol;
    
public:
    CSessionManager() {}
    ~CSessionManager() {}
    
    //+------------------------------------------------------------------+
    //| Check if market is currently open for trading                   |
    //+------------------------------------------------------------------+
    bool IsMarketOpen(const string symbol)
    {
        if(!m_symbol.Name(symbol)) return false;
        
        // CRITICAL FIX: Force refresh to ensure we have latest quote data
        if(!m_symbol.RefreshRates()) 
        {
            // If refresh fails, try once more
            Sleep(10);
            if(!m_symbol.RefreshRates())
                return false;
        }
        
        // Check trade mode
        ENUM_SYMBOL_TRADE_MODE tradeMode = (ENUM_SYMBOL_TRADE_MODE)SymbolInfoInteger(symbol, SYMBOL_TRADE_MODE);
        if(tradeMode == SYMBOL_TRADE_MODE_DISABLED || tradeMode == SYMBOL_TRADE_MODE_CLOSEONLY)
            return false;
            
        // Check session times (more robust than just day_of_week)
        datetime now = TimeCurrent();
        datetime from, to;
        
        MqlDateTime dt;
        TimeToStruct(now, dt);
        
        // Synthetic indices check - CRITICAL FIX: Improved detection and relaxed validation
        if(IsSynthetic(symbol))
        {
            // Synthetics are 24/7 - use relaxed quote validation
            // Allow brief quote delays (up to 5 seconds stale) to prevent false blocks
            double bid = m_symbol.Bid();
            double ask = m_symbol.Ask();
            
            // Check if we have any valid quotes (allow zero for synthetics during brief delays)
            if(bid <= 0 && ask <= 0)
            {
                // Try one more refresh before blocking
                Sleep(5);
                m_symbol.RefreshRates();
                bid = m_symbol.Bid();
                ask = m_symbol.Ask();
            }
            
            // For synthetics, only block if both bid and ask are invalid
            // This prevents false market_unavailable blocks during active trading
            return (bid > 0 || ask > 0);
        }
        
        // Regular instruments check session
        if(!SymbolInfoSessionTrade(symbol, (ENUM_DAY_OF_WEEK)dt.day_of_week, 0, from, to))
            return false;
            
        // Check if current time is within any trade session for today
        bool inSession = false;
        for(int i = 0; i < 10; i++) // Check up to 10 sessions per day
        {
            if(SymbolInfoSessionTrade(symbol, (ENUM_DAY_OF_WEEK)dt.day_of_week, i, from, to))
            {
                // Convert session times to current date
                datetime sessionStart = now - (now % 86400) + from;
                datetime sessionEnd = now - (now % 86400) + to;
                
                if(now >= sessionStart && now < sessionEnd)
                {
                    inSession = true;
                    break;
                }
            }
            else break;
        }
        
        if(!inSession) return false;
        
        // Final sanity check for quotes
        if(m_symbol.Bid() <= 0 || m_symbol.Ask() <= 0) return false;
        
        return true;
    }
    
    //+------------------------------------------------------------------+
    //| Check if symbol is a synthetic index                            |
    //+------------------------------------------------------------------+
    bool IsSynthetic(const string symbol)
    {
        return (StringFind(symbol, "Volatility") >= 0 || 
                StringFind(symbol, "Step") >= 0 || 
                StringFind(symbol, "Jump") >= 0 ||
                StringFind(symbol, "Boom") >= 0 ||
                StringFind(symbol, "Crash") >= 0);
    }
};

#endif // CORE_UTILS_SESSION_MANAGER_MQH
