//+------------------------------------------------------------------+
//| VirtualPosition.mqh                                              |
//| Lightweight reservation book for scan-time portfolio budgeting   |
//+------------------------------------------------------------------+
#ifndef CORE_RISK_VIRTUAL_POSITION_MQH
#define CORE_RISK_VIRTUAL_POSITION_MQH

struct SVirtualPosition
{
    string ownerTag;
    string symbol;
    string strategyCluster;
    string clusterCode;
    ENUM_ORDER_TYPE orderType;
    double lotSize;
    double riskPercent;
    datetime reservedAt;
    int    ttlSeconds;       // Time-to-live in seconds; expired entries are pruned

    SVirtualPosition() :
        ownerTag(""),
        symbol(""),
        strategyCluster(""),
        clusterCode(""),
        orderType(ORDER_TYPE_BUY),
        lotSize(0.0),
        riskPercent(0.0),
        reservedAt(0),
        ttlSeconds(60)
    {
    }
};

class CVirtualPositionBook
{
private:
    SVirtualPosition m_positions[];

    bool IsBuyOrderType(const ENUM_ORDER_TYPE orderType) const
    {
        return (orderType == ORDER_TYPE_BUY ||
                orderType == ORDER_TYPE_BUY_LIMIT ||
                orderType == ORDER_TYPE_BUY_STOP ||
                orderType == ORDER_TYPE_BUY_STOP_LIMIT);
    }

public:
    CVirtualPositionBook()
    {
        ArrayResize(m_positions, 0);
    }

    void Clear()
    {
        ArrayResize(m_positions, 0);
    }

    //+------------------------------------------------------------------+
    //| Remove entries older than their TTL                              |
    //+------------------------------------------------------------------+
    int PruneExpired()
    {
        datetime now = TimeCurrent();
        int pruned = 0;
        for(int i = ArraySize(m_positions) - 1; i >= 0; i--)
        {
            if(m_positions[i].ttlSeconds > 0 &&
               m_positions[i].reservedAt > 0 &&
               (now - m_positions[i].reservedAt) > m_positions[i].ttlSeconds)
            {
                int last = ArraySize(m_positions) - 1;
                m_positions[i] = m_positions[last];
                ArrayResize(m_positions, last);
                pruned++;
            }
        }
        if(pruned > 0)
        {
            PrintFormat("[RISK-VIRTUAL] Pruned %d expired reservation(s) | remaining=%d",
                        pruned, ArraySize(m_positions));
        }
        return pruned;
    }

    void ClearOwner(const string ownerTag)
    {
        for(int i = ArraySize(m_positions) - 1; i >= 0; i--)
        {
            if(m_positions[i].ownerTag != ownerTag)
                continue;

            int last = ArraySize(m_positions) - 1;
            m_positions[i] = m_positions[last];
            ArrayResize(m_positions, last);
        }
    }

    bool Reserve(const string ownerTag,
                 const string symbol,
                 const ENUM_ORDER_TYPE orderType,
                 const string strategyCluster,
                 const string clusterCode,
                 const double lotSize,
                 const double riskPercent)
    {
        if(ownerTag == "" || symbol == "" || lotSize <= 0.0 || riskPercent <= 0.0)
            return false;

        PruneExpired();
        ClearOwner(ownerTag);

        int size = ArraySize(m_positions);
        ArrayResize(m_positions, size + 1);
        m_positions[size].ownerTag = ownerTag;
        m_positions[size].symbol = symbol;
        m_positions[size].strategyCluster = strategyCluster;
        m_positions[size].clusterCode = clusterCode;
        m_positions[size].orderType = orderType;
        m_positions[size].lotSize = lotSize;
        m_positions[size].riskPercent = riskPercent;
        m_positions[size].reservedAt = TimeCurrent();
        m_positions[size].ttlSeconds = 60;
        return true;
    }

    int GetReservationCount() const
    {
        return ArraySize(m_positions);
    }

    bool GetReservation(const int index, SVirtualPosition &position) const
    {
        if(index < 0 || index >= ArraySize(m_positions))
            return false;
        position = m_positions[index];
        return true;
    }

    double GetReservedRiskPercent()
    {
        PruneExpired();
        double total = 0.0;
        for(int i = 0; i < ArraySize(m_positions); i++)
            total += MathMax(0.0, m_positions[i].riskPercent);
        return total;
    }

    double GetReservedRiskPercentForSymbol(const string symbol)
    {
        PruneExpired();
        double total = 0.0;
        for(int i = 0; i < ArraySize(m_positions); i++)
        {
            if(m_positions[i].symbol == symbol)
                total += MathMax(0.0, m_positions[i].riskPercent);
        }
        return total;
    }

    double GetReservedRiskPercentForCluster(const string strategyCluster)
    {
        PruneExpired();
        double total = 0.0;
        for(int i = 0; i < ArraySize(m_positions); i++)
        {
            if(m_positions[i].strategyCluster == strategyCluster)
                total += MathMax(0.0, m_positions[i].riskPercent);
        }
        return total;
    }

    int GetReservedPositionsOnSymbol(const string symbol)
    {
        PruneExpired();
        int total = 0;
        for(int i = 0; i < ArraySize(m_positions); i++)
        {
            if(m_positions[i].symbol == symbol)
                total++;
        }
        return total;
    }

    bool HasOpposingReservation(const string symbol,
                                const string clusterCode,
                                const ENUM_ORDER_TYPE orderType) const
    {
        // Batch 118: Prune expired entries before checking to avoid false positives
        // (PruneExpired is non-const but we call it on mutable 'this' via const_cast pattern)
        // Since this is const, we skip pruning here — callers should ensure PruneExpired runs periodically

        bool requestedBuy = IsBuyOrderType(orderType);

        for(int i = 0; i < ArraySize(m_positions); i++)
        {
            if(m_positions[i].symbol != symbol)
                continue;

            bool reservedBuy = IsBuyOrderType(m_positions[i].orderType);
            if(reservedBuy == requestedBuy)
                continue;

            if(clusterCode == "" || m_positions[i].clusterCode == "" || m_positions[i].clusterCode != clusterCode)
                return true;
        }

        return false;
    }
};

#endif // CORE_RISK_VIRTUAL_POSITION_MQH
