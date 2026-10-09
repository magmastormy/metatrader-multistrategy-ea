// Signal Pipeline Aggregator - MTF consensus tally (extracted)
// Stateless consensus vote counting for ProcessMTFSignals.
#ifndef SIGNAL_PIPELINE_AGGREGATOR_MQH
#define SIGNAL_PIPELINE_AGGREGATOR_MQH

#include "../Utils/Enums.mqh"

class CSignalPipelineAggregator
{
public:
// Tally per-timeframe consensus (no-conflict path).
// Preserves exact original majority-vote + averaged confidence.
    static ENUM_TRADE_SIGNAL TallyConsensus(const ENUM_TRADE_SIGNAL &signals[],
                                            const double &confidences[],
                                            const int count,
                                            double &finalConfidence)
    {
        // Calculate consensus if no conflicts
        int buyCount = 0, sellCount = 0;
        double buyConf = 0, sellConf = 0;

        for(int i = 0; i < count; i++)
        {
            if(signals[i] == TRADE_SIGNAL_BUY)
            {
                buyCount++;
                buyConf += confidences[i];
            }
            else if(signals[i] == TRADE_SIGNAL_SELL)
            {
                sellCount++;
                sellConf += confidences[i];
            }
        }

        // Determine final signal
        if(buyCount > sellCount)
        {
            finalConfidence = buyConf / buyCount;
            return TRADE_SIGNAL_BUY;
        }
        else if(sellCount > buyCount)
        {
            finalConfidence = sellConf / sellCount;
            return TRADE_SIGNAL_SELL;
        }

        finalConfidence = 0;
        return TRADE_SIGNAL_NONE;
    }
};

#endif // SIGNAL_PIPELINE_AGGREGATOR_MQH
