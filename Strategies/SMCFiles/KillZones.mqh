//+------------------------------------------------------------------+
//| KillZones.mqh                                                    |
//| ICT Kill Zone Time Filter for Unified ICT Strategy               |
//| Implements session-based trading windows                         |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Multi-Strategy EA"
#property version   "2.00"
#property strict

#ifndef __SMC_KILL_ZONES_MQH__
#define __SMC_KILL_ZONES_MQH__

//+------------------------------------------------------------------+
//| Kill Zone Types                                                  |
//+------------------------------------------------------------------+
enum ENUM_KILL_ZONE
{
    KZ_NONE,
    KZ_ASIAN,       // 20:00 - 00:00 EST (ranging, setup phase)
    KZ_LONDON,      // 02:00 - 05:00 EST (1st expansion, high probability)
    KZ_NY_AM,       // 08:00 - 11:00 EST (2nd expansion, highest probability)
    KZ_NY_PM,       // 13:00 - 16:00 EST (late day setups)
    KZ_LONDON_NY,   // 08:00 - 12:00 EST (overlap, extreme volatility)

    // P2-C: ICT Silver Bullet windows
    KZ_SILVER_BULLET_LONDON,    // 03:00 - 04:00 EST — London Silver Bullet
    KZ_SILVER_BULLET_NY_AM,     // 10:00 - 11:00 EST — NY AM Silver Bullet
    KZ_SILVER_BULLET_NY_PM      // 14:00 - 15:00 EST — NY PM Silver Bullet
};

//+------------------------------------------------------------------+
//| Session Info Structure                                           |
//+------------------------------------------------------------------+
struct SSessionInfo
{
    ENUM_KILL_ZONE  zone;
    int             startHour;
    int             startMinute;
    int             endHour;
    int             endMinute;
    double          probabilityWeight;
    string          name;
    
    SSessionInfo() : zone(KZ_NONE), startHour(0), startMinute(0),
                     endHour(0), endMinute(0), probabilityWeight(0), name("") {}
};

//+------------------------------------------------------------------+
//| ICT Kill Zones Class                                             |
//+------------------------------------------------------------------+
class CICTKillZones
{
private:
    // Broker GMT offset (e.g., +2 for most MT5 brokers)
    int             m_brokerGMTOffset;
    int             m_estOffset;        // EST is GMT-5 (or -4 during DST)
    bool            m_useDST;
    
    // Session definitions
    SSessionInfo    m_sessions[9];  // expanded for Silver Bullet windows
    int             m_sessionCount;
    
    // Configuration
    bool            m_enableAsian;
    bool            m_enableLondon;
    bool            m_enableNYAM;
    bool            m_enableNYPM;
    bool            m_enableOverlap;
    bool            m_enableSilverBullet;     // P2-C: all Silver Bullet windows on/off
    
    // Internal
    void            InitializeSessions();
    int             GetCurrentESTHour();
    int             GetCurrentESTMinute();
    bool            IsInSession(const SSessionInfo &session);
    
public:
                    CICTKillZones();
                   ~CICTKillZones();
    
    // Initialization
    bool            Initialize(int brokerGMTOffset = 2, bool useDST = true);
    
    // Configuration
    void            EnableSession(ENUM_KILL_ZONE zone, bool enable);
    void            SetBrokerGMTOffset(int offset) { m_brokerGMTOffset = offset; }
    
    // Core methods
    bool            IsInKillZone();
    ENUM_KILL_ZONE  GetCurrentKillZone();
    double          GetKillZoneWeight();
    string          GetKillZoneName();
    
    // Session specific
    bool            IsAsianSession();
    bool            IsLondonSession();
    bool            IsNYAMSession();
    bool            IsNYPMSession();
    bool            IsLondonNYOverlap();

    // P2-C: Silver Bullet
    bool            IsSilverBullet();
    string          GetSilverBulletName();
    bool            IsLondonSilverBullet();
    bool            IsNYAMSilverBullet();
    bool            IsNYPMSilverBullet();
    
    // Best trading windows
    bool            IsHighProbabilityWindow();
    double          GetSessionVolatilityMultiplier();
};

//+------------------------------------------------------------------+
//| Constructor                                                      |
//+------------------------------------------------------------------+
CICTKillZones::CICTKillZones() :
    m_brokerGMTOffset(2),
    m_estOffset(-5),
    m_useDST(true),
    m_sessionCount(8),
    m_enableAsian(true),
    m_enableLondon(true),
    m_enableNYAM(true),
    m_enableNYPM(true),
    m_enableOverlap(true),
    m_enableSilverBullet(true)
{
    InitializeSessions();
}

//+------------------------------------------------------------------+
//| Destructor                                                       |
//+------------------------------------------------------------------+
CICTKillZones::~CICTKillZones()
{
}

//+------------------------------------------------------------------+
//| Initialize Sessions                                              |
//+------------------------------------------------------------------+
void CICTKillZones::InitializeSessions()
{
    // Asian Session (20:00 - 00:00 EST)
    m_sessions[0].zone = KZ_ASIAN;
    m_sessions[0].startHour = 20;
    m_sessions[0].startMinute = 0;
    m_sessions[0].endHour = 0;
    m_sessions[0].endMinute = 0;
    m_sessions[0].probabilityWeight = 0.5;
    m_sessions[0].name = "Asian";
    
    // London Kill Zone (02:00 - 05:00 EST)
    m_sessions[1].zone = KZ_LONDON;
    m_sessions[1].startHour = 2;
    m_sessions[1].startMinute = 0;
    m_sessions[1].endHour = 5;
    m_sessions[1].endMinute = 0;
    m_sessions[1].probabilityWeight = 0.85;
    m_sessions[1].name = "London Kill Zone";
    
    // NY AM Kill Zone (08:00 - 11:00 EST)
    m_sessions[2].zone = KZ_NY_AM;
    m_sessions[2].startHour = 8;
    m_sessions[2].startMinute = 0;
    m_sessions[2].endHour = 11;
    m_sessions[2].endMinute = 0;
    m_sessions[2].probabilityWeight = 0.95;
    m_sessions[2].name = "NY AM Kill Zone";
    
    // NY PM Session (13:00 - 16:00 EST)
    m_sessions[3].zone = KZ_NY_PM;
    m_sessions[3].startHour = 13;
    m_sessions[3].startMinute = 0;
    m_sessions[3].endHour = 16;
    m_sessions[3].endMinute = 0;
    m_sessions[3].probabilityWeight = 0.65;
    m_sessions[3].name = "NY PM Session";
    
    // London-NY Overlap (08:00 - 12:00 EST)
    m_sessions[4].zone = KZ_LONDON_NY;
    m_sessions[4].startHour = 8;
    m_sessions[4].startMinute = 0;
    m_sessions[4].endHour = 12;
    m_sessions[4].endMinute = 0;
    m_sessions[4].probabilityWeight = 1.0;
    m_sessions[4].name = "London-NY Overlap";

    // P2-C: Silver Bullet — London (03:00 - 04:00 EST)
    m_sessions[5].zone = KZ_SILVER_BULLET_LONDON;
    m_sessions[5].startHour = 3;
    m_sessions[5].startMinute = 0;
    m_sessions[5].endHour = 4;
    m_sessions[5].endMinute = 0;
    m_sessions[5].probabilityWeight = 0.90;
    m_sessions[5].name = "Silver Bullet (London)";

    // P2-C: Silver Bullet — NY AM (10:00 - 11:00 EST)
    m_sessions[6].zone = KZ_SILVER_BULLET_NY_AM;
    m_sessions[6].startHour = 10;
    m_sessions[6].startMinute = 0;
    m_sessions[6].endHour = 11;
    m_sessions[6].endMinute = 0;
    m_sessions[6].probabilityWeight = 0.92;
    m_sessions[6].name = "Silver Bullet (NY AM)";

    // P2-C: Silver Bullet — NY PM (14:00 - 15:00 EST)
    m_sessions[7].zone = KZ_SILVER_BULLET_NY_PM;
    m_sessions[7].startHour = 14;
    m_sessions[7].startMinute = 0;
    m_sessions[7].endHour = 15;
    m_sessions[7].endMinute = 0;
    m_sessions[7].probabilityWeight = 0.80;
    m_sessions[7].name = "Silver Bullet (NY PM)";
}

//+------------------------------------------------------------------+
//| Initialize                                                       |
//+------------------------------------------------------------------+
bool CICTKillZones::Initialize(int brokerGMTOffset, bool useDST)
{
    m_brokerGMTOffset = brokerGMTOffset;
    m_useDST = useDST;
    
    // Adjust EST offset for DST
    if(m_useDST)
    {
        // Check if currently in DST (simplified: March-November)
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        if(dt.mon >= 3 && dt.mon <= 11)
            m_estOffset = -4; // EDT
        else
            m_estOffset = -5; // EST
    }
    else
    {
        m_estOffset = -5;
    }
    
    return true;
}

//+------------------------------------------------------------------+
//| Enable/Disable Session                                           |
//+------------------------------------------------------------------+
void CICTKillZones::EnableSession(ENUM_KILL_ZONE zone, bool enable)
{
    switch(zone)
    {
        case KZ_ASIAN:                  m_enableAsian       = enable; break;
        case KZ_LONDON:                 m_enableLondon      = enable; break;
        case KZ_NY_AM:                  m_enableNYAM        = enable; break;
        case KZ_NY_PM:                  m_enableNYPM        = enable; break;
        case KZ_LONDON_NY:              m_enableOverlap     = enable; break;
        case KZ_SILVER_BULLET_LONDON:
        case KZ_SILVER_BULLET_NY_AM:
        case KZ_SILVER_BULLET_NY_PM:    m_enableSilverBullet = enable; break;
        default: break;
    }
}

//+------------------------------------------------------------------+
//| Get Current EST Hour                                             |
//+------------------------------------------------------------------+
int CICTKillZones::GetCurrentESTHour()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    
    // Convert broker time to EST
    int estHour = dt.hour - m_brokerGMTOffset + m_estOffset;
    
    // Normalize hour
    if(estHour < 0) estHour += 24;
    if(estHour >= 24) estHour -= 24;
    
    return estHour;
}

//+------------------------------------------------------------------+
//| Get Current EST Minute                                           |
//+------------------------------------------------------------------+
int CICTKillZones::GetCurrentESTMinute()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    return dt.min;
}

//+------------------------------------------------------------------+
//| Is In Session                                                    |
//+------------------------------------------------------------------+
bool CICTKillZones::IsInSession(const SSessionInfo &session)
{
    int currentHour = GetCurrentESTHour();
    int currentMinute = GetCurrentESTMinute();
    int sessionCurrentTime = currentHour * 60 + currentMinute;
    
    int sessionStartTime = session.startHour * 60 + session.startMinute;
    int endTime = session.endHour * 60 + session.endMinute;
    
    // Handle sessions that cross midnight
    if(endTime < sessionStartTime)
    {
        // Session crosses midnight (e.g., Asian)
        return (sessionCurrentTime >= sessionStartTime || sessionCurrentTime < endTime);
    }
    else
    {
        return (sessionCurrentTime >= sessionStartTime && sessionCurrentTime < endTime);
    }
}

//+------------------------------------------------------------------+
//| Is In Kill Zone                                                  |
//+------------------------------------------------------------------+
bool CICTKillZones::IsInKillZone()
{
    return GetCurrentKillZone() != KZ_NONE;
}

//+------------------------------------------------------------------+
//| Get Current Kill Zone                                            |
//+------------------------------------------------------------------+
ENUM_KILL_ZONE CICTKillZones::GetCurrentKillZone()
{
    // Silver Bullet windows take highest priority (narrower, more specific)
    if(m_enableSilverBullet)
    {
        if(IsInSession(m_sessions[5])) return KZ_SILVER_BULLET_LONDON;
        if(IsInSession(m_sessions[6])) return KZ_SILVER_BULLET_NY_AM;
        if(IsInSession(m_sessions[7])) return KZ_SILVER_BULLET_NY_PM;
    }

    // Check overlap first
    if(m_enableOverlap && IsInSession(m_sessions[4]))
        return KZ_LONDON_NY;
    
    // Check NY AM
    if(m_enableNYAM && IsInSession(m_sessions[2]))
        return KZ_NY_AM;
    
    // Check London
    if(m_enableLondon && IsInSession(m_sessions[1]))
        return KZ_LONDON;
    
    // Check NY PM
    if(m_enableNYPM && IsInSession(m_sessions[3]))
        return KZ_NY_PM;
    
    // Check Asian
    if(m_enableAsian && IsInSession(m_sessions[0]))
        return KZ_ASIAN;
    
    return KZ_NONE;
}

//+------------------------------------------------------------------+
//| Get Kill Zone Weight                                             |
//+------------------------------------------------------------------+
double CICTKillZones::GetKillZoneWeight()
{
    ENUM_KILL_ZONE zone = GetCurrentKillZone();
    
    for(int i = 0; i < m_sessionCount; i++)
    {
        if(m_sessions[i].zone == zone)
            return m_sessions[i].probabilityWeight;
    }
    
    return 0.0;
}

//+------------------------------------------------------------------+
//| Get Kill Zone Name                                               |
//+------------------------------------------------------------------+
string CICTKillZones::GetKillZoneName()
{
    ENUM_KILL_ZONE zone = GetCurrentKillZone();
    
    for(int i = 0; i < m_sessionCount; i++)
    {
        if(m_sessions[i].zone == zone)
            return m_sessions[i].name;
    }
    
    return "No Session";
}

//+------------------------------------------------------------------+
//| Session Checks                                                   |
//+------------------------------------------------------------------+
bool CICTKillZones::IsAsianSession()
{
    return IsInSession(m_sessions[0]);
}

bool CICTKillZones::IsLondonSession()
{
    return IsInSession(m_sessions[1]);
}

bool CICTKillZones::IsNYAMSession()
{
    return IsInSession(m_sessions[2]);
}

bool CICTKillZones::IsNYPMSession()
{
    return IsInSession(m_sessions[3]);
}

bool CICTKillZones::IsLondonNYOverlap()
{
    return IsInSession(m_sessions[4]);
}

//+------------------------------------------------------------------+
//| Is High Probability Window                                       |
//+------------------------------------------------------------------+
bool CICTKillZones::IsHighProbabilityWindow()
{
    ENUM_KILL_ZONE zone = GetCurrentKillZone();
    
    // London, NY AM, Overlap, and Silver Bullet windows are highest probability
    return (zone == KZ_LONDON ||
            zone == KZ_NY_AM  ||
            zone == KZ_LONDON_NY ||
            zone == KZ_SILVER_BULLET_LONDON ||
            zone == KZ_SILVER_BULLET_NY_AM  ||
            zone == KZ_SILVER_BULLET_NY_PM);
}

//+------------------------------------------------------------------+
//| P2-C: Silver Bullet Methods                                     |
//+------------------------------------------------------------------+
bool CICTKillZones::IsSilverBullet()
{
    ENUM_KILL_ZONE zone = GetCurrentKillZone();
    return (zone == KZ_SILVER_BULLET_LONDON ||
            zone == KZ_SILVER_BULLET_NY_AM  ||
            zone == KZ_SILVER_BULLET_NY_PM);
}

bool CICTKillZones::IsLondonSilverBullet() { return IsInSession(m_sessions[5]); }
bool CICTKillZones::IsNYAMSilverBullet()   { return IsInSession(m_sessions[6]); }
bool CICTKillZones::IsNYPMSilverBullet()   { return IsInSession(m_sessions[7]); }

string CICTKillZones::GetSilverBulletName()
{
    if(IsLondonSilverBullet()) return "Silver Bullet: London 03-04 EST";
    if(IsNYAMSilverBullet())   return "Silver Bullet: NY AM 10-11 EST";
    if(IsNYPMSilverBullet())   return "Silver Bullet: NY PM 14-15 EST";
    return "No Silver Bullet";
}

//+------------------------------------------------------------------+
//| Get Session Volatility Multiplier                                |
//+------------------------------------------------------------------+
double CICTKillZones::GetSessionVolatilityMultiplier()
{
    ENUM_KILL_ZONE zone = GetCurrentKillZone();
    
    switch(zone)
    {
        case KZ_LONDON_NY:  return 1.5;  // Highest volatility
        case KZ_NY_AM:      return 1.3;
        case KZ_LONDON:     return 1.2;
        case KZ_NY_PM:      return 1.0;
        case KZ_ASIAN:      return 0.7;  // Lower volatility
        default:            return 0.5;
    }
}

#endif // __SMC_KILL_ZONES_MQH__
