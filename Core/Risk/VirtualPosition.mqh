// Lightweight reservation book for scan-time portfolio budgeting
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

// A reservation bridges the gap between approval and visibility. Two things end it: the TTL, and the position
// arriving. The terminal's own position list feeds GetPortfolioRisk(), so a reservation that outlives its fill
// charges the same risk twice - once as an open position and once as pending - for the rest of the minute, and the
// portfolio cap refuses entries it should have allowed.
    int PruneStale()
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

        int covered = PruneCoveredByPositions();

        if(pruned > 0 || covered > 0)
        {
            PrintFormat("[RISK-VIRTUAL] pruned | expired=%d | covered_by_position=%d | remaining=%d",
                        pruned, covered, ArraySize(m_positions));
        }
        return pruned + covered;
    }

// One position can cover one reservation: matched oldest first, by symbol, direction, a lot at least as large, and
// an open time at or after the reservation. POSITION_MAGIC != 0 keeps a manual trade from discharging our pending
// risk, and the time test keeps an older same-direction position from covering a reservation it predates.
    int PruneCoveredByPositions()
    {
        int total = ArraySize(m_positions);
        int live = PositionsTotal();
        if(total == 0 || live == 0)
            return 0;

        string posSymbol[];
        datetime posTime[];
        double posVolume[];
        bool posBuy[];
        bool posUsed[];
        ArrayResize(posSymbol, live);
        ArrayResize(posTime, live);
        ArrayResize(posVolume, live);
        ArrayResize(posBuy, live);
        ArrayResize(posUsed, live);
        int count = 0;
        for(int p = 0; p < live; p++)
        {
            ulong ticket = PositionGetTicket(p);
            if(ticket == 0 || !PositionSelectByTicket(ticket))
                continue;
            if(PositionGetInteger(POSITION_MAGIC) == 0)
                continue;
            posSymbol[count] = PositionGetString(POSITION_SYMBOL);
            posTime[count] = (datetime)PositionGetInteger(POSITION_TIME);
            posVolume[count] = PositionGetDouble(POSITION_VOLUME);
            posBuy[count] = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY;
            posUsed[count] = false;
            count++;
        }

        bool drop[];
        bool decided[];
        ArrayResize(drop, total);
        ArrayResize(decided, total);
        for(int i = 0; i < total; i++)
        {
            drop[i] = false;
            decided[i] = false;
        }
        int removed = 0;

        // Selection order is explicit because the swap-remove compaction below does not keep the book chronological:
        // picking the oldest undecided reservation each pass means the same set of fills always discharges the same set
        // of reservations, instead of whichever one happened to survive a previous prune.
        for(int pass = 0; pass < total; pass++)
        {
            int sel = -1;
            for(int i = 0; i < total; i++)
            {
                if(decided[i])
                    continue;
                if(sel < 0 || m_positions[i].reservedAt < m_positions[sel].reservedAt)
                    sel = i;
            }
            if(sel < 0)
                break;
            decided[sel] = true;
            if(m_positions[sel].reservedAt <= 0)
                continue;

            bool wantBuy = IsBuyOrderType(m_positions[sel].orderType);
            for(int p = 0; p < count; p++)
            {
                if(posUsed[p])
                    continue;
                if(posSymbol[p] != m_positions[sel].symbol)
                    continue;
                if(posBuy[p] != wantBuy)
                    continue;
                if(posTime[p] < m_positions[sel].reservedAt)
                    continue;
                if(posVolume[p] + 0.0000001 < m_positions[sel].lotSize)
                    continue;

                posUsed[p] = true;
                drop[sel] = true;
                break;
            }
        }

        for(int i = total - 1; i >= 0; i--)
        {
            if(!drop[i])
                continue;
            int last = ArraySize(m_positions) - 1;
            m_positions[i] = m_positions[last];
            ArrayResize(m_positions, last);
            removed++;
        }
        return removed;
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

    // sync a reservation to the validated numbers once they exist. Reserve() books the provisional lot and
    // risk and refuses riskPercent<=0, so a zero-risk placeholder can never sit in the book. adds the lot:
    // a correlation shrink or lot-floor change lands after Reserve, and a reservation still carrying the pre-adjustment
    // lot can never be matched by the position that actually filled, so it would double-charge the portfolio cap.
    bool UpdateRisk(const string ownerTag, const double lotSize, const double riskPercent)
    {
        if(ownerTag == "" || lotSize <= 0.0 || riskPercent <= 0.0)
            return false;

        bool updated = false;
        for(int i = ArraySize(m_positions) - 1; i >= 0; i--)
        {
            if(m_positions[i].ownerTag != ownerTag)
                continue;
            m_positions[i].lotSize = lotSize;
            m_positions[i].riskPercent = riskPercent;
            updated = true;
        }
        return updated;
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

        PruneStale();
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

    double GetReservedRiskPercent()
    {
        PruneStale();
        double total = 0.0;
        for(int i = 0; i < ArraySize(m_positions); i++)
            total += MathMax(0.0, m_positions[i].riskPercent);
        return total;
    }

    double GetReservedRiskPercentForSymbol(const string symbol)
    {
        PruneStale();
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
        PruneStale();
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
        PruneStale();
        int total = 0;
        for(int i = 0; i < ArraySize(m_positions); i++)
        {
            if(m_positions[i].symbol == symbol)
                total++;
        }
        return total;
    }

    // An opposing reservation on the same symbol is a conflict whatever its cluster. The cluster
    // code used to be compared here and returned "no conflict" when the two matched, which was
    // unreachable while callers passed "" (the guard then always conflicted); started
    // populating cluster codes, so that inverted branch would have gone live as a loosening.
    bool HasOpposingReservation(const string symbol,
                                const ENUM_ORDER_TYPE orderType) const
    {
        // const, so it cannot prune; the pipeline's GetReservedRiskPercent call runs PruneStale on this same book
        // a few statements earlier in the same validation request.
        bool requestedBuy = IsBuyOrderType(orderType);

        for(int i = 0; i < ArraySize(m_positions); i++)
        {
            if(m_positions[i].symbol != symbol)
                continue;

            bool reservedBuy = IsBuyOrderType(m_positions[i].orderType);
            if(reservedBuy == requestedBuy)
                continue;

            return true;
        }

        return false;
    }
};

#endif // CORE_RISK_VIRTUAL_POSITION_MQH

