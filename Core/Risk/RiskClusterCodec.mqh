//+------------------------------------------------------------------+
//| RiskClusterCodec.mqh                                             |
//| Stateless cluster-code normalisation / parsing helpers.          |
//|                                                                  |
//| Extracted verbatim from CUnifiedRiskManager (Phase E1) so that   |
//| cluster-governance, audit formatting and position-sync code can  |
//| share one canonical implementation. Behaviour is byte-identical  |
//| to the original member functions; CUnifiedRiskManager keeps thin |
//| forwarders with the original signatures.                         |
//|                                                                  |
//| NOTE (MQL5): static methods cannot be declared const, so the     |
//| trailing const of the original members is dropped here.          |
//+------------------------------------------------------------------+
#ifndef CORE_RISK_RISK_CLUSTER_CODEC_MQH
#define CORE_RISK_RISK_CLUSTER_CODEC_MQH

//+------------------------------------------------------------------+
//| Cluster code codec (pure, stateless)                             |
//+------------------------------------------------------------------+
class CRiskClusterCodec
{
public:
    //--- Normalise an arbitrary cluster label to a compact code.
    //--- Returns one of "T" (trend), "R" (reversion), "S" (structure),
    //--- or "N" (none/unknown).
    static string NormalizeClusterCode(const string clusterCode)
    {
        string code = clusterCode;
        StringTrimLeft(code);
        StringTrimRight(code);
        StringToUpper(code);

        if(StringLen(code) <= 0)
            return "N";

        string first = StringSubstr(code, 0, 1);
        if(first == "T" || first == "R" || first == "S" || first == "N")
            return first;

        if(StringFind(code, "TREND") >= 0)
            return "T";
        if(StringFind(code, "MEAN") >= 0 || StringFind(code, "REVERSION") >= 0)
            return "R";
        if(StringFind(code, "STRUCTURE") >= 0)
            return "S";

        return "N";
    }

    //--- Extract the compact cluster code embedded in a position comment
    //--- using the "K:<code>" marker. Always writes clusterCode (default "N").
    //--- Returns true when a marker was found and decoded.
    static bool ParseClusterCodeFromComment(const string comment, string &clusterCode)
    {
        clusterCode = "N";
        int marker = StringFind(comment, "K:");
        if(marker < 0 || (marker + 2) >= StringLen(comment))
            return false;

        clusterCode = NormalizeClusterCode(StringSubstr(comment, marker + 2, 1));
        return true;
    }
};

#endif // CORE_RISK_RISK_CLUSTER_CODEC_MQH
