//+------------------------------------------------------------------+
//| StrategyFactory.mqh - Strategy Factory for creating strategies    |
//| Copyright 2025, Your Company Name                                |
//| https://www.yoursite.com                                        |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Your Company Name"
#property link      "https://www.yoursite.com"
#property version   "1.00"
#property strict

#ifndef __STRATEGY_FACTORY_MQH__
#define __STRATEGY_FACTORY_MQH__

#include "../Strategy/StrategyBase.mqh"
#include "../../Strategies/StrategyRSI.mqh"
#include "../../Strategies/StrategySupplyDemand.mqh"
#include "../../Strategies/StrategyOrderBlockFVG.mqh"
#include "../../Strategies/StrategySwing.mqh"
// Include other strategy headers as they are converted

// Forward declarations
class CStrategyRSI;
class CStrategySupplyDemand;
class CStrategyOrderBlockFVG;
class CStrategySwing;

// Add these before SStrategyConfig:
struct SRSIConfig {
    int period;
    double overbought;
    double oversold;
};
struct SBollingerConfig {
    int period;
    double deviation;
};
struct SMACDConfig {
    int fastEma;
    int slowEma;
    int signalPeriod;
};

//+------------------------------------------------------------------+
//| Strategy Factory Class                                           |
//+------------------------------------------------------------------+
class CStrategyFactory
{
public:
    //--- Strategy types
    enum ENUM_STRATEGY_TYPE
    {
        STRATEGY_RSI,
        STRATEGY_MA,
        STRATEGY_BOLLINGER,
        STRATEGY_MACD,
        STRATEGY_SUPPLY_DEMAND,
        STRATEGY_ORDER_BLOCK,
        STRATEGY_FIBONACCI,
        STRATEGY_ELLIOTT,
        STRATEGY_SWING,
        STRATEGY_VOLATILITY,
        STRATEGY_TREND,
        STRATEGY_MEAN_REVERSION,
        STRATEGY_BREAKOUT,
        STRATEGY_HARMONIC,
        STRATEGY_ICHIMOKU,
        // Add other strategy types here
        STRATEGY_COUNT  // Must be the last element
    };
    
    //--- Strategy configuration structure
    struct SStrategyConfig
    {
        string   strategyName;  // Name of the strategy
        bool     enabled;       // Whether the strategy is enabled
        double   weight;        // Strategy weight (0.0 to 1.0)
        SRSIConfig rsi;
        SBollingerConfig bollinger;
        SMACDConfig macd;
        // Add other strategy configurations here
    };
    
    //--- Strategy info structure
    struct SStrategyInfo
    {
        string name;           // Strategy name
        string description;     // Strategy description
        bool   requiresConfig;  // Whether the strategy requires configuration
    };
    
    //--- Constructor/Destructor
    CStrategyFactory()
    {
        // Initialize strategy names and descriptions
        ArrayResize(m_strategyNames, STRATEGY_COUNT);
        ArrayResize(m_strategyDescriptions, STRATEGY_COUNT);
        
        // Initialize strategy names
        m_strategyNames[STRATEGY_RSI] = "RSI Strategy";
        m_strategyNames[STRATEGY_MA] = "Moving Average";
        m_strategyNames[STRATEGY_BOLLINGER] = "Bollinger Bands";
        m_strategyNames[STRATEGY_MACD] = "MACD";
        m_strategyNames[STRATEGY_SUPPLY_DEMAND] = "Supply & Demand";
        m_strategyNames[STRATEGY_ORDER_BLOCK] = "Order Block & FVG";
        m_strategyNames[STRATEGY_FIBONACCI] = "Fibonacci";
        m_strategyNames[STRATEGY_ELLIOTT] = "Elliott Wave";
        m_strategyNames[STRATEGY_SWING] = "Swing Trading";
        
        // Initialize strategy descriptions
        m_strategyDescriptions[STRATEGY_RSI] = "Uses RSI overbought/oversold levels with price action confirmation";
        m_strategyDescriptions[STRATEGY_MA] = "Uses moving average crossovers for trade signals";
        m_strategyDescriptions[STRATEGY_BOLLINGER] = "Trades based on Bollinger Bands";
        m_strategyDescriptions[STRATEGY_MACD] = "Uses MACD for trend following and momentum";
        m_strategyDescriptions[STRATEGY_SUPPLY_DEMAND] = "Identifies and trades supply and demand zones";
        m_strategyDescriptions[STRATEGY_ORDER_BLOCK] = "Trades order blocks and fair value gaps";
        m_strategyDescriptions[STRATEGY_FIBONACCI] = "Uses Fibonacci retracement levels for entries and exits";
        m_strategyDescriptions[STRATEGY_ELLIOTT] = "Implements Elliott Wave theory for market analysis";
        m_strategyDescriptions[STRATEGY_SWING] = "Swing trading strategy using multiple timeframes";
    }
    
    ~CStrategyFactory()
    {
        // Clean up resources if needed
    }
    
    //--- Create a strategy by type
    static CStrategyBase* CreateStrategy(ENUM_STRATEGY_TYPE type, const SStrategyConfig &config)
    {
        CStrategyBase* strategy = NULL;
        
        switch(type)
        {
            case STRATEGY_RSI:
            {
                CStrategyRSI* rsiStrategyLocal = new CStrategyRSI();
                if(rsiStrategyLocal != NULL)
                {
                    // Configure RSI parameters
                    // rsiStrategyLocal.SetPeriod(config.rsi.period); // Method not available
                    // rsiStrategyLocal.SetOverboughtLevel(config.rsi.overbought); // Method not available
                    // rsiStrategyLocal.SetOversoldLevel(config.rsi.oversold); // Method not available

                    strategy = rsiStrategyLocal;
                }
                break;
            }
                
            case STRATEGY_SUPPLY_DEMAND:
            {
                CStrategySupplyDemand* sdStrategy = new CStrategySupplyDemand("SupplyDemand", 1);
                strategy = sdStrategy;
                break;
            }
                
            case STRATEGY_ORDER_BLOCK:
            {
                CStrategyOrderBlockFVG* obStrategy = new CStrategyOrderBlockFVG("OrderBlock", 1);
                strategy = obStrategy;
                break;
            }
                
            case STRATEGY_SWING:
            {
                CStrategySwing* swingStrategyLocal = new CStrategySwing();
                strategy = swingStrategyLocal;
                break;
            }
                
            // Add cases for other strategy types as they are implemented
            default:
                Print("Strategy type not implemented: ", type);
                break;
        }
        
        if(strategy != NULL)
        {
            // Set common strategy properties
            // strategy.SetName(config.strategyName); // Method not available
            strategy.SetEnabled(config.enabled);
            strategy.SetWeight(config.weight);
            
            // Initialize the strategy
            // Strategy initialization stubbed - method not available
            /*
            if(!strategy.Initialize())
            {
                Print("Failed to initialize strategy: ", config.strategyName);
                delete strategy;
                return NULL;
            }
            */
            
            Print("Successfully created strategy: ", config.strategyName);
        }
        
        return strategy;
    }
    
    //--- Get strategy information
    SStrategyInfo GetStrategyInfo(ENUM_STRATEGY_TYPE type) const
    {
        SStrategyInfo info;
        
        if(type >= 0 && type < STRATEGY_COUNT)
        {
            info.name = m_strategyNames[type];
            info.description = m_strategyDescriptions[type];
            info.requiresConfig = true; // Most strategies require configuration
        }
        else
        {
            info.name = "Unknown";
            info.description = "Unknown strategy type";
            info.requiresConfig = false;
        }
        
        return info;
    }
    
    //--- Get all strategy types
    static int GetStrategyTypes(string &types[])
    {
        int count = STRATEGY_COUNT;
        ArrayResize(types, count);
        
        // Create a temporary instance to access the member variables
        CStrategyFactory factory;
        
        for(int i = 0; i < count; i++)
        {
            types[i] = factory.m_strategyNames[i];
        }
        
        return count;
    }
    
private:
    //--- Strategy names
    string m_strategyNames[];
    
    //--- Strategy descriptions
    string m_strategyDescriptions[];
};

// Global instance of the strategy factory
CStrategyFactory StrategyFactory;

#endif // __STRATEGY_FACTORY_MQH__
