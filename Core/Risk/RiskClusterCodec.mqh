// Stateless cluster-code normalisation / parsing shared by risk governance, audit
// formatting and position sync. MQL5: static methods cannot be declared const.
#ifndef CORE_RISK_RISK_CLUSTER_CODEC_MQH
#define CORE_RISK_RISK_CLUSTER_CODEC_MQH

class CRiskClusterCodec
{
public:
    //--- Normalise an arbitrary cluster label to "T" (trend), "R" (reversion),
    //--- "S" (structure) or "N" (none/unknown).
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

    //--- Read the cluster code from the "K:<code>" marker in a position comment.
    //--- `clusterCode` is always written (default "N"); true only when a marker decoded.
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
