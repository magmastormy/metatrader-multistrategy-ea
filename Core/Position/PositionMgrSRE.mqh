// Extracted from PositionManager.mqh (Phase I decomposition)
// STATEFUL module: owns the Signal Reversal Exit (SRE) tuning
// parameters and runs the per-position reversal scan.
// The scan body is copied verbatim from
// CPositionManager::CheckSignalReversalExit() - zero behaviour
// change. The two members it used to read from the owner
// (m_tradeManager / m_magicNumber) are now explicit arguments.
#property strict

#ifndef CORE_POSITION_POSITION_MGR_SRE_MQH
#define CORE_POSITION_POSITION_MGR_SRE_MQH

#include "../Trading/TradeManager.mqh"     // CTradeManager (complete type, called by pointer)
#include "PositionMgrMagicFilter.mqh"      // CPositionMgrMagicFilter::IsEAOwnedMagic

class CPositionMgrSRE
{
private:
    bool                    m_sreEnabled;
    double                  m_sreMinConfidence;
    bool                    m_sreProfitGuard;
    double                  m_sreMinLossR;
    double                  m_sreMaxLossR;
    int                     m_sreMinTimeSec;
    bool                    m_structuralInvalidationEnabled;

public:
    CPositionMgrSRE() :
        m_sreEnabled(true), m_sreMinConfidence(0.58), m_sreProfitGuard(true),
        m_sreMinLossR(0.25), m_sreMaxLossR(0.82), m_sreMinTimeSec(45),
        m_structuralInvalidationEnabled(true)
    {
    }

    ~CPositionMgrSRE()
    {
    }

    //--- Mirrors CPositionManager::ConfigureSRE()
    void Configure(bool enabled, double minConf, bool profitGuard, double minLossR, double maxLossR, int minTimeSec, bool structuralInv)
    {
        m_sreEnabled = enabled; m_sreMinConfidence = minConf; m_sreProfitGuard = profitGuard;
        m_sreMinLossR = minLossR; m_sreMaxLossR = maxLossR; m_sreMinTimeSec = minTimeSec;
        m_structuralInvalidationEnabled = structuralInv;
    }

    bool IsEnabled() const { return m_sreEnabled; }

    // --- SRE: Signal Reversal Exit ---
    bool CheckSignalReversalExit(CTradeManager* tradeManager, const int magicNumber)
    {
        if(!m_sreEnabled) return false;

        bool anyReversal = false;

        for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket)) continue;
            if(!CPositionMgrMagicFilter::IsEAOwnedMagic(PositionGetInteger(POSITION_MAGIC))) continue;

            string sym = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

            // Get current consensus signal
            // In practice, this would query the consensus cache or enterprise manager
            // For now, use a simplified check
            double confidence = 0;
            int confluence = 0;
            // This would be filled from the consensus system

            bool isBuy = (type == POSITION_TYPE_BUY);
            bool opposingSignal = false; // Would be set based on actual signal

            if(opposingSignal)
            {
                double currentProfit = PositionGetDouble(POSITION_PROFIT);
                bool inLoss = (currentProfit < 0);

                datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
                int durationSec = (int)(TimeCurrent() - openTime);

                double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
                double slPrice = PositionGetDouble(POSITION_SL);
                double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
                double slDistance = MathAbs(openPrice - slPrice);
                double posCurrentDrawdown = MathAbs(openPrice - currentPrice);
                double lossR = (slDistance > 0) ? (posCurrentDrawdown / slDistance) : 0.0;

                bool hasBreathingRoom = (durationSec < m_sreMinTimeSec);
                bool isMinorNoise = (inLoss && lossR < m_sreMinLossR);
                bool isLastStandZone = (inLoss && lossR > m_sreMaxLossR);

                if(confidence >= m_sreMinConfidence)
                {
                    if(isLastStandZone)
                    {
                        // Skip SRE, let hard SL decide
                    }
                    else if(!hasBreathingRoom || lossR > 0.50)
                    {
                        bool profitGuardBlocked = false;
                        if(m_sreProfitGuard && inLoss && lossR > 0.25)
                            profitGuardBlocked = true;

                        if(!profitGuardBlocked)
                        {
                            tradeManager.ClosePosition(ticket, "Signal Reversal Exit");
                            anyReversal = true;
                        }
                    }
                }

                if(m_structuralInvalidationEnabled && !anyReversal)
                {
                    // Check structural invalidation - would need consensus context
                }
            }
        }

        return anyReversal;
    }
};

#endif // CORE_POSITION_POSITION_MGR_SRE_MQH
