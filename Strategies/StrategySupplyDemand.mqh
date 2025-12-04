//+------------------------------------------------------------------+
//| Supply & Demand Strategy Module                                 |
//| Copyright 2025, Your Company Name                                |
//| https://www.yoursite.com                                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Company Name"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

// Prevent multiple inclusions
#ifndef __STRATEGY_SUPPLYDEMAND_MQH__
#define __STRATEGY_SUPPLYDEMAND_MQH__

// Include necessary MQL5 standard library headers
#include <Trade\SymbolInfo.mqh>
#include <Charts\Chart.mqh>
#include <Object.mqh>
#include <ChartObjects\ChartObjectsShapes.mqh>
#include <ChartObjects\ChartObjectsTxtControls.mqh>

// Include indicator headers
// #include "../Include/Indicators/Trend.mqh"
#include "../Include/Indicators/Oscillators.mqh"
// #include "../Include/Indicators/Indicators.mqh"

// Include project headers
#include "../Core/StrategyBase.mqh"
#include "../Core/Enums.mqh"
#include "../Interfaces/IStrategy.mqh"
#include "../Utilities/Utilities.mqh"
#include "../Core/PositionSizer.mqh"
#include "../Core/ErrorHandling.mqh"
#include "../Core/TradeManager.mqh"

// Include standard library
// #include <stdlib.mqh>
#include <Math\Stat\Math.mqh>



// Maximum number of zones to track
#define MAX_ZONES 10

//+------------------------------------------------------------------+
//| Strategy Factory for creating this strategy                      |
//+------------------------------------------------------------------+


//+------------------------------------------------------------------+
//| Supply & Demand Strategy Class                                   |
//+------------------------------------------------------------------+
class CStrategySupplyDemand : public CStrategyBase
{
private:
    // --- Member Variables ---
    struct Zone
    {
        double price1;
        double price2;
        datetime created;
        ENUM_TIMEFRAMES timeframe;
        bool isSupply;
        int strength;
        string name;
        color zoneColor;
        int width;
        bool isActive;
        Zone() : price1(0), price2(0), created(0), timeframe(PERIOD_CURRENT), isSupply(false), strength(0), name(""), zoneColor(0), width(0), isActive(false) {}
    };
    
    Zone             m_zones[MAX_ZONES];
    int              m_zoneCount;
    int              m_minZoneWidth;          // Minimum width (bars) for a valid zone
    int              m_minZoneHeight;         // Minimum height (points) for a valid zone
    int              m_zoneExpiryBars;        // Number of bars before a zone expires
    bool             m_zoneCreationDisabled; // Flag to disable zone creation if too many failures
    int              m_maxZones;              // Maximum number of zones to track
    int              m_maxZoneRetries;        // Maximum number of retries for zone creation
    int              m_zoneRetryDelay;        // Delay between retry attempts (ms)
    double           m_lastSignalValue;
    double           m_lastConfidence;
    SPositionSizingParams m_sizing_params; // Strategy-specific sizing parameters

    // Zone tracking
    struct ZoneTracking {
        datetime createdTime;
        int creationAttempts;
        bool isActive;
    };
    ZoneTracking m_zoneTracking[MAX_ZONES];

    // --- Private Helper Methods ---
    void RememberZone(double price1, double price2, ENUM_TIMEFRAMES tf, bool isSupply)
    {
        if(price1 <= 0 || price2 <= 0) return;
        for(int i = 0; i < m_zoneCount; i++) {
            if(MathAbs(m_zones[i].price1 - price1) < SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 10 && 
               MathAbs(m_zones[i].price2 - price2) < SymbolInfoDouble(m_symbol, SYMBOL_POINT) * 10) {
                return;
            }
        }
        if(m_zoneCount < MAX_ZONES) {
            m_zones[m_zoneCount].price1 = price1;
            m_zones[m_zoneCount].price2 = price2;
            m_zones[m_zoneCount].created = TimeCurrent();
            m_zones[m_zoneCount].timeframe = tf;
            m_zones[m_zoneCount].isSupply = isSupply;
            color zoneColor = isSupply ? clrRed : clrDodgerBlue;
            string zoneType = isSupply ? "S" : "D";
            string name = StringFormat("Zone_%d_%s", m_zoneCount + 1, zoneType);
            if(!CreateZone(name, price1, price2, zoneColor)) {
                Print("[ERROR] Failed to create zone: ", name);
            }
            m_zoneCount++;
        }
    }
    
    void DetectZonesInternal(const string symbol, const ENUM_TIMEFRAMES timeframe)
    {
        if(symbol == "" || timeframe == 0) return;
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        int copied = CopyRates(symbol, timeframe, 0, 100, rates);
        if(copied <= 0) {
            Print("Failed to get price data for zone detection");
            return;
        }
        for(int i = 2; i < copied - 1; i++) {
            if(m_zoneCount >= MAX_ZONES) break;
            if(rates[i].high > rates[i-1].high && rates[i].high > rates[i+1].high) {
                double zoneTop = rates[i].high;
                double zoneBottom = rates[i].high * 0.995;
                RememberZone(zoneTop, zoneBottom, timeframe, true);
            }
            if(m_zoneCount >= MAX_ZONES) break;
            if(rates[i].low < rates[i-1].low && rates[i].low < rates[i+1].low) {
                double zoneBottom = rates[i].low;
                double zoneTop = rates[i].low * 1.005;
                RememberZone(zoneTop, zoneBottom, timeframe, false);
            }
        }
    }

    void DetectZones(const string symbol, const ENUM_TIMEFRAMES timeframe)
    {
        if(symbol == "" || timeframe == 0) return;
        for(int i = 0; i < m_zoneCount; i++) {
            string zoneType = m_zones[i].isSupply ? "S" : "D";
            string name = StringFormat("Zone_%d_%s", i + 1, zoneType);
            RemoveChartObject(name);
        }
        m_zoneCount = 0;
        DetectZonesInternal(symbol, timeframe);
    }
        
    bool CreateZone(const string name, const double price1, const double price2, const color zoneColor, const int width = 1)
    {
        // Validate inputs
        if(price1 <= 0 || price2 <= 0 || StringLen(name) == 0)
        {
            LogError(ERROR_WARNING, "StrategySupplyDemand", "Invalid zone parameters", 0);
            return false;
        }
        
        // Check if zone creation is disabled due to previous failures
        if(m_zoneCreationDisabled) {
            LogError(ERROR_INFO, "StrategySupplyDemand", "Zone creation disabled due to previous failures", 0);
            return false;
        }
        
        // Check if we've reached the maximum number of zones
        if(m_zoneCount >= m_maxZones) {
            LogError(ERROR_WARNING, "StrategySupplyDemand", "Maximum number of zones reached", 0);
            return false;
        }
        
        // Check if a similar zone already exists (prevent duplicates)
        for(int i = 0; i < m_zoneCount; i++) {
            if(MathAbs(m_zones[i].price1 - price1) < Point() * 10 && 
               MathAbs(m_zones[i].price2 - price2) < Point() * 10) {
                LogError(ERROR_INFO, "StrategySupplyDemand", "Similar zone already exists", 0);
                return false;
            }
        }
        
        // Find an available slot or replace the oldest zone
        int zoneIndex = m_zoneCount;
        if(zoneIndex >= MAX_ZONES) {
            // Find the oldest zone to replace
            datetime oldestTime = TimeCurrent();
            for(int i = 0; i < m_zoneCount; i++) {
                if(m_zoneTracking[i].createdTime < oldestTime) {
                    oldestTime = m_zoneTracking[i].createdTime;
                    zoneIndex = i;
                }
            }
            
            // Remove the oldest zone
            if(zoneIndex < m_zoneCount) {
                if(!RemoveZone(m_zones[zoneIndex].name)) {
                    LogError(ERROR_WARNING, "StrategySupplyDemand", "Failed to remove old zone", 0);
                    return false;
                }
            }
        }
        
        // Create the zone object with retry logic
        bool zoneCreated = false;
        int retryCount = 0;
        
        while(!zoneCreated && retryCount < m_maxZoneRetries) {
            // Create the zone object
            if(CreateChartObject(name, price1, price2, zoneColor, width)) {
                // Update zone tracking
                m_zoneTracking[zoneIndex].createdTime = TimeCurrent();
                m_zoneTracking[zoneIndex].creationAttempts = 0;
                m_zoneTracking[zoneIndex].isActive = true;
                
                // Update zone array
                m_zones[zoneIndex].name = name;
                m_zones[zoneIndex].price1 = price1;
                m_zones[zoneIndex].price2 = price2;
                m_zones[zoneIndex].zoneColor = zoneColor;
                m_zones[zoneIndex].width = width;
                m_zones[zoneIndex].isActive = true;
                
                if(zoneIndex >= m_zoneCount) {
                    m_zoneCount++;
                }
                
                zoneCreated = true;
                LogError(ERROR_INFO, "StrategySupplyDemand", "Zone created successfully: " + name, 0);
            } else {
                // Increment failure counter
                m_zoneTracking[zoneIndex].creationAttempts++;
                retryCount++;

                // Log the failure
                LogError(ERROR_WARNING, "StrategySupplyDemand",
                         StringFormat("Failed to create zone (attempt %d/%d)", retryCount, m_maxZoneRetries),
                         GetLastError());
                
                // Add delay between retries
                Sleep(m_zoneRetryDelay);
                
                // Disable zone creation if too many failures
                if(m_zoneTracking[zoneIndex].creationAttempts >= m_maxZoneRetries) {
                    m_zoneCreationDisabled = true;
                    LogError(ERROR_CRITICAL, "StrategySupplyDemand",
                             "Zone creation disabled after multiple failures", 0);
                    return false;
                }
            }
        }
        
        return zoneCreated;
    }

    bool RemoveZone(const string name)
    {
        long chartId = ChartID();
        if(ObjectFind(chartId, name) >= 0) {
            return ObjectDelete(chartId, name);
        }
        return true;
    }

    bool CreateChartObject(const string name, const double price1, const double price2, const color clr, const int width = 1)
    {
        // AGGRESSIVE FIX: Skip zone creation if disabled due to previous failures
        if(m_zoneCreationDisabled) {
            return false; // Silently skip zone creation to prevent spam
        }
        
        long chartId = ChartID();
        
        // Validate input parameters
        if(name == "" || price1 <= 0 || price2 <= 0) {
            Print("[ERROR] Invalid parameters for zone creation: ", name, " P1=", price1, " P2=", price2);
            return false;
        }
        
        // AGGRESSIVE FIX: Enhanced zone object creation with validation
        if(ObjectFind(chartId, name) >= 0) {
            if(!ObjectDelete(chartId, name)) {
                Print("[WARNING] Failed to delete existing zone object: ", name);
            }
            Sleep(10); // Brief pause after deletion
        }
        
        // Validate price data and timeframes
        datetime time1 = iTime(Symbol(), PERIOD_CURRENT, 0);
        if(time1 <= 0) {
            Print("[ERROR] Invalid time data for zone creation: ", name, " on ", Symbol());
            return false;
        }
        
        datetime time2 = time1 + PeriodSeconds(PERIOD_CURRENT) * 100;
        
        // Validate price levels
        if(price1 <= 0 || price2 <= 0 || MathAbs(price1 - price2) < SymbolInfoDouble(Symbol(), SYMBOL_POINT)) {
            Print("[ERROR] Invalid price levels for zone: ", name, " P1=", price1, " P2=", price2);
            return false;
        }
        
        // RUTHLESS FIX: Aggressive zone creation with comprehensive error handling
        bool objectCreated = false;
        int retryCount = 0;
        const int maxRetries = 5; // Increased retries
        
        // CRITICAL: Validate chart state before attempting object creation
        if(chartId <= 0) {
            chartId = ChartID(); // Refresh chart ID
            if(chartId <= 0) {
                Print("[CRITICAL] Invalid chart ID for zone creation: ", name);
                return false;
            }
        }
        
        // AGGRESSIVE: Clean up any existing object with same name first
        if(ObjectFind(chartId, name) >= 0) {
            ObjectDelete(chartId, name);
            Sleep(50); // Allow cleanup
        }
        
        // SPAM FIX: Check if zone already exists before creating
        if(ObjectFind(chartId, name) >= 0) {
            // Zone already exists, no need to recreate
            return false;
        }
        
        while(!objectCreated && retryCount < maxRetries) {
            ResetLastError();
            
            // CRITICAL: Validate chart is still valid before each attempt (reduced logging)
            if(!ChartGetInteger(chartId, CHART_BRING_TO_TOP) && retryCount == 0) {
                // Only log on first attempt to reduce spam
                Print("[WARNING] Chart validation failed for zone: ", name);
            }
            
            // AGGRESSIVE: Force chart refresh before object creation
            ChartRedraw(chartId);
            Sleep(50);
            
            if(ObjectCreate(chartId, name, OBJ_RECTANGLE, 0, time1, price1, time2, price2)) {
                objectCreated = true;
                
                // CRITICAL: Validate object was actually created before setting properties
                if(ObjectFind(chartId, name) >= 0) {
                    // Apply zone properties with error checking
                    if(!ObjectSetInteger(chartId, name, OBJPROP_COLOR, clr)) {
                        Print("[WARNING] Failed to set color for zone: ", name);
                    }
                    ObjectSetInteger(chartId, name, OBJPROP_STYLE, STYLE_SOLID);
                    ObjectSetInteger(chartId, name, OBJPROP_WIDTH, width);
                    ObjectSetInteger(chartId, name, OBJPROP_FILL, true);
                    ObjectSetInteger(chartId, name, OBJPROP_BACK, true);
                    ObjectSetInteger(chartId, name, OBJPROP_SELECTABLE, false);
                    
                    // Force chart update
                    ChartRedraw(chartId);
                    
                    // SPAM FIX: Reduced logging frequency for zone creation
                    static int zoneCreateCount = 0;
                    zoneCreateCount++;
                    if(zoneCreateCount % 10 == 1) { // Log every 10th zone creation
                        Print("[INFO] Zone objects created (count: ", zoneCreateCount, ") - Latest: ", name);
                    }
                } else {
                    Print("[ERROR] Zone object created but not found: ", name);
                    objectCreated = false;
                }
            }
            else {
                int error = GetLastError();
                Print("[ERROR] Failed to create zone object: ", name, ", Error: ", error, ", Retry: ", retryCount+1, "/", maxRetries);
                
                // AGGRESSIVE: Handle specific error codes
                if(error == 4022) { // Unknown error - likely chart/object management issue
                    Print("[RECOVERY] Error 4022 detected - attempting chart recovery for: ", name);
                    ChartRedraw(chartId);
                    Sleep(200); // Longer delay for chart recovery
                } else if(error == 4200) { // Object already exists
                    ObjectDelete(chartId, name);
                    Sleep(100);
                } else if(error == 4201) { // Unknown object property
                    Print("[RECOVERY] Property error - using simplified object creation for: ", name);
                }
                
                retryCount++;
                if(retryCount < maxRetries) {
                    Sleep(150 * retryCount); // Progressive delay
                }
            }
        }
        
        if(!objectCreated) {
            Print("[CRITICAL] Zone object creation failed permanently: ", name, " after ", maxRetries, " attempts - DISABLING ZONE CREATION");
            // FALLBACK: Continue without visual zones but log the failure
            m_zoneCreationDisabled = true;
        }
        
        return objectCreated;
    }
    
    bool RemoveChartObject(const string name)
    {
        long chartId = ChartID();
        if(ObjectFind(chartId, name) >= 0) {
            return ObjectDelete(chartId, name);
        }
        return true;
    }
    
    // EMERGENCY FIX: Add zone cleanup method to prevent memory leaks
    void CleanupOldZones()
    {
        datetime localTime = TimeCurrent();
        int cleanedCount = 0;
        
        for(int i = m_zoneCount - 1; i >= 0; i--) {
            // Remove zones older than 24 hours
            if(localTime - m_zones[i].created > 86400) {
                string zoneName = StringFormat("Zone_%d_%s", i + 1, m_zones[i].isSupply ? "S" : "D");
                RemoveChartObject(zoneName);
                
                // Shift remaining zones
                for(int j = i; j < m_zoneCount - 1; j++) {
                    m_zones[j] = m_zones[j + 1];
                }
                m_zoneCount--;
                cleanedCount++;
            }
        }
        
        if(cleanedCount > 0) {
            Print("[ZONE-CLEANUP] Removed ", cleanedCount, " old zones. Active zones: ", m_zoneCount);
        }
    }
    
    // Error logging method
    void LogError(ENUM_ERROR_SEVERITY severity, string component, string message, int errorCode = 0)
    {
        SErrorContext context;
        context.component = component;
        context.operation = "StrategySupplyDemand";
        context.symbol = m_symbol;
        context.errorCode = errorCode;
        context.additionalInfo = message;
        context.timestamp = TimeCurrent();
        context.severity = severity;

        CEnhancedErrorHandler *localErrorHandler = CEnhancedErrorHandler::GetInstance();
        if(CheckPointer(localErrorHandler) == POINTER_INVALID)
            return;

        (*localErrorHandler).LogError(severity, context);
    }

    // EMERGENCY FIX: Validate zone before creation
    bool ValidateZoneCreation(double price1, double price2, const string symbol)
    {
        if(price1 <= 0 || price2 <= 0) {
            Print("[ZONE-VALIDATION] Invalid prices: ", price1, ", ", price2);
            return false;
        }
        
        double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
        if(point <= 0) {
            Print("[ZONE-VALIDATION] Invalid point value for ", symbol);
            return false;
        }
        
        double zoneSizePips = MathAbs(price1 - price2) / point;
        if(zoneSizePips < 5 || zoneSizePips > 1000) {
            Print("[ZONE-VALIDATION] Zone size invalid: ", zoneSizePips, " pips");
            return false;
        }
        
        // Check for duplicate zones
        for(int i = 0; i < m_zoneCount; i++) {
            if(MathAbs(m_zones[i].price1 - price1) < point * 10 && 
               MathAbs(m_zones[i].price2 - price2) < point * 10) {
                return false; // Duplicate zone
            }
        }
        
        return true;
    }

public:
    // --- Constructor ---
    CStrategySupplyDemand(const string name, int magic = 0) : 
        CStrategyBase(name, magic),
        m_zoneCount(0),
        m_minZoneWidth(5),          // Default min zone width
        m_minZoneHeight(10),         // Default min zone height
        m_zoneExpiryBars(100),        // Default zone expiry
        m_maxZones(10),              // Default max zones
        m_maxZoneRetries(3),         // Default max retries
        m_zoneRetryDelay(100),       // Default retry delay
        m_lastSignalValue(0.0),
        m_lastConfidence(0.0),
        m_zoneCreationDisabled(false),
        m_sizing_params()
    {
        // Configure strategy-specific sizing parameters
        m_sizing_params.sizingMode = POSITION_SIZE_RISK_PERCENT;
        m_sizing_params.riskPercent = 1.0;   // Risk 1.0% of account per trade
        // m_sizing_params.stopLossPips = 25.0; // FIXED: stopLossPips not in structure
    }

    // --- IStrategy Implementation ---
    virtual bool Init(const string symbol, const ENUM_TIMEFRAMES timeframe, void* tradeMgr, void* posSizer) override
    {
        if(!CStrategyBase::Init(symbol, timeframe, tradeMgr, posSizer))
            return false;
            
        m_zoneCount = 0;
        DetectZones(m_symbol, m_timeframe); // Detect initial zones without trading
        return true;
    }
    
    virtual void Deinit() override
    {
        for(int i = 0; i < m_zoneCount; i++) {
            string zoneType = m_zones[i].isSupply ? "S" : "D";
            string name = StringFormat("Zone_%d_%s", i + 1, zoneType);
            RemoveChartObject(name);
        }
        m_zoneCount = 0;
        CStrategyBase::Deinit();
    }
    
    virtual ENUM_TRADE_SIGNAL GetSignal(double &confidence) override
    {
        if(!IsEnabled()) {
            confidence = 0.0;
            return TRADE_SIGNAL_NONE;
        }
        
        double signalValue = GetSignalValue(m_symbol, m_timeframe, confidence);
        
        if(signalValue > 0.5)
            return TRADE_SIGNAL_BUY;
        else if(signalValue < -0.5)
            return TRADE_SIGNAL_SELL;
        else
            return TRADE_SIGNAL_NONE;
    }
    
    virtual string GetName() const override { return m_name; }
    virtual ENUM_STRATEGY_TYPE GetType() const override { return STRATEGY_SUPPLY_DEMAND; }
    
    virtual void OnTick() override
    {
        if(!IsEnabled()) return;
        static datetime lastBarTime = 0;
        datetime localBarTime = iTime(m_symbol, m_timeframe, 0);
        if(localBarTime != lastBarTime)
        {
            lastBarTime = localBarTime;
            OnNewBar(m_symbol, m_timeframe);
        }
    }

    virtual void OnNewBar(const string symbol, const ENUM_TIMEFRAMES timeframe) override
    {
        if(!IsEnabled())
            return;

        DetectZones(m_symbol, m_timeframe);
    }
        
    // Helper for internal use
    double GetSignalValue(const string symbol, const ENUM_TIMEFRAMES timeframe, double &confidence)
    {
        if(!IsEnabled()) {
            confidence = 0.0;
            return 0.0;
        }
        MqlRates rates[];
        ArraySetAsSeries(rates, true);
        if(CopyRates(symbol, timeframe, 0, 1, rates) <= 0) {
            confidence = 0.0;
            return 0.0;
        }
        double localPrice = rates[0].close;
        double signal = 0.0;
        confidence = 0.0;
        for(int i = 0; i < m_zoneCount; i++) {
            double zoneTop = MathMax(m_zones[i].price1, m_zones[i].price2);
            double zoneBottom = MathMin(m_zones[i].price1, m_zones[i].price2);
            if(localPrice >= zoneBottom && localPrice <= zoneTop) {
                if(m_zones[i].isSupply) {
                    signal = -1.0;
                    confidence = 0.8;
                } else {
                    signal = 1.0;
                    confidence = 0.8;
                }
                break;
            }
        }
        m_lastSignalValue = signal;
        m_lastConfidence = confidence;
        m_lastSignalTime = TimeCurrent();
        return signal;
    }
};



#endif // __STRATEGY_SUPPLYDEMAND_MQH__
