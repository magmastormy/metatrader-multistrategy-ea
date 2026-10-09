//+------------------------------------------------------------------+
//| WalkForwardTesterEA.mq5                                          |
//| Phase 1 in-terminal walk-forward validator (MULTI-SYMBOL).       |
//| Validates reference strategies against the LIVE broker's real   |
//| history (true spread, true session gaps) for every symbol in    |
//| InpSymbols, printing one [WFO-REPORT] block per symbol.          |
//| Embeds 3 strategies: ADX trend, RSI mean-reversion, VolBreak.    |
//| Mirrors Tools/walkforward/*.py methodology.                      |
//+------------------------------------------------------------------+
#property strict
#include "Core/Validation/WalkForwardValidator.mqh"

int g_csv = INVALID_HANDLE;   // cross-symbol scoreboard file handle (MQL5/Files/)

input int    InpBars      = 10000;    // history bars to request per symbol (longer = more WFO windows, less NEEDS_MORE_DATA)
input string InpSymbols   = "Volatility 25 Index,Volatility 50 Index,Volatility 75 Index,Volatility 100 Index,Boom 1000,Crash 1000,EURUSD,GBPUSD,USDJPY,XAUUSD";
input ENUM_TIMEFRAMES InpTF = PERIOD_M15;
input int    InpTrainBars = 600;      // in-sample window
input int    InpTestBars  = 300;      // out-of-sample window
input double InpSlAtr    = 1.5;       // SL distance (x ATR)
input double InpTpAtr    = 2.0;       // TP distance (x ATR) -> 1.33 R:R
input double InpCostBps  = 1.5;       // FALLBACK round-trip cost in bps (used if live spread unavailable)
input string InpReportCsv = "WFO_Scoreboard.csv"; // persistent cross-symbol scoreboard (MQL5/Files/)

//+------------------------------------------------------------------+
//| Manual Wilder RSI                                                 |
//+------------------------------------------------------------------+
void WF_RSI(const double &close[], int n, int period, double &rsi[])
{
   ArrayResize(rsi, n);
   if(n < period + 1) { for(int i=0;i<n;i++) rsi[i]=50; return; }
   double g=0,l=0;
   for(int i=1;i<=period;i++)
   {
      double ch=close[i]-close[i-1];
      g+=MathMax(ch,0); l+=MathMax(-ch,0);
   }
   g/=period; l/=period;
   rsi[period]=100.0 - 100.0/(1.0 + (l>0? g/l : 1e6));
   for(int i=period+1;i<n;i++)
   {
      double ch=close[i]-close[i-1];
      double ng=MathMax(ch,0), nl=MathMax(-ch,0);
      g=(g*(period-1)+ng)/period; l=(l*(period-1)+nl)/period;
      rsi[i]=100.0 - 100.0/(1.0 + (l>0? g/l : 1e6));
   }
   for(int i=0;i<period;i++) rsi[i]=rsi[period];
}

//+------------------------------------------------------------------+
//| Manual Wilder ADX (+DI/-DI)                                       |
//+------------------------------------------------------------------+
void WF_ADX(const double &high[], const double &low[], const double &close[], int n, int period,
            double &adx[], double &pdi[], double &mdi[])
{
   ArrayResize(adx,n); ArrayResize(pdi,n); ArrayResize(mdi,n);
   if(n < period+1) { for(int i=0;i<n;i++){adx[i]=0;pdi[i]=0;mdi[i]=0;} return; }
   double tr=0, pdm=0, mdm=0;
   for(int i=1;i<=period;i++)
   {
      double hh=high[i]-high[i-1], ll=low[i-1]-low[i];
      double up=(hh>0&&hh>ll)?hh:0, dn=(ll>0&&ll>hh)?ll:0;
      double hl=high[i]-low[i], hc=MathAbs(high[i]-close[i-1]), lc=MathAbs(low[i]-close[i-1]);
      tr+=MathMax(hl,MathMax(hc,lc)); pdm+=up; mdm+=dn;
   }
   tr/=period; pdm/=period; mdm/=period;
   double pdiV=100*pdm/tr, mdiV=100*mdm/tr;
   double dxV=100*MathAbs(pdiV-mdiV)/MathMax(pdiV+mdiV,1e-9);
   double adxV=dxV;
   adx[period]=adxV; pdi[period]=pdiV; mdi[period]=mdiV;
   for(int i=period+1;i<n;i++)
   {
      double hh=high[i]-high[i-1], ll=low[i-1]-low[i];
      double up=(hh>0&&hh>ll)?hh:0, dn=(ll>0&&ll>hh)?ll:0;
      double hl=high[i]-low[i], hc=MathAbs(high[i]-close[i-1]), lc=MathAbs(low[i]-close[i-1]);
      double trv=MathMax(hl,MathMax(hc,lc));
      tr=(tr*(period-1)+trv)/period; pdm=(pdm*(period-1)+up)/period; mdm=(mdm*(period-1)+dn)/period;
      pdiV=100*pdm/tr; mdiV=100*mdm/tr;
      dxV=100*MathAbs(pdiV-mdiV)/MathMax(pdiV+mdiV,1e-9);
      adxV=(adxV*(period-1)+dxV)/period;
      adx[i]=adxV; pdi[i]=pdiV; mdi[i]=mdiV;
   }
   for(int i=0;i<period;i++){adx[i]=adx[period];pdi[i]=pdi[period];mdi[i]=mdi[period];}
}

//+------------------------------------------------------------------+
//| Build the 3 reference strategy signal/confidence series          |
//+------------------------------------------------------------------+
void BuildSignals(const double &open[], const double &high[], const double &low[], const double &close[],
                  int n, int &sigADX[], double &confADX[],
                  int &sigRSI[], double &confRSI[],
                  int &sigVol[], double &confVol[])
{
   ArrayResize(sigADX,n); ArrayResize(confADX,n);
   ArrayResize(sigRSI,n); ArrayResize(confRSI,n);
   ArrayResize(sigVol,n); ArrayResize(confVol,n);
   double rsi[], adx[], pdi[], mdi[];
   WF_RSI(close, n, 14, rsi);
   WF_ADX(high, low, close, n, 14, adx, pdi, mdi);
   int N=20;
   for(int i=0;i<n;i++)
   {
      sigADX[i]=0; confADX[i]=0; sigRSI[i]=0; confRSI[i]=0; sigVol[i]=0; confVol[i]=0;
      if(adx[i] > 25)
      {
         if(pdi[i] > mdi[i]) sigADX[i]=1; else if(pdi[i] < mdi[i]) sigADX[i]=-1;
         confADX[i]=MathMin(0.95, adx[i]/100.0);
      }
      if(rsi[i] < 30) { sigRSI[i]=1; confRSI[i]=MathAbs(rsi[i]-50)/50.0; }
      else if(rsi[i] > 70) { sigRSI[i]=-1; confRSI[i]=MathAbs(rsi[i]-50)/50.0; }
      if(i >= N)
      {
         double hN=-1e9, lN=1e9;
         for(int k=i-N;k<i;k++){ if(high[k]>hN)hN=high[k]; if(low[k]<lN)lN=low[k]; }
         if(close[i] > hN) { sigVol[i]=1; confVol[i]=0.6; }
         else if(close[i] < lN) { sigVol[i]=-1; confVol[i]=0.6; }
      }
   }
}

//+------------------------------------------------------------------+
//| Run + print one strategy (also appends a scoreboard CSV row)      |
//+------------------------------------------------------------------+
void Validate(const string sym, const string name, const double &open[], const double &high[], const double &low[],
              const double &close[], const double &atr[], const int &sig[], const double &conf[],
              int n, double cost_rt, double cost_bps)
{
   SWFOResult r;
   WF_Run(open, high, low, close, atr, sig, conf, n, InpTrainBars, InpTestBars,
          InpSlAtr, InpTpAtr, cost_rt, r);
   PrintFormat("[WFO-REPORT]   %s -> verdict=%s windows=%d WFE=%.3f robustness=%.3f "
               "IS_net=%.4f OOS_net=%.4f OOS_PF=%.3f OOS_WR=%.3f OOS_maxDD=%.3f",
               name, r.verdict, r.n_windows, r.wfe, r.robustness,
               r.is_net, r.oos_net, r.oos_pf, r.oos_wr, r.oos_dd);
   if(g_csv != INVALID_HANDLE)
   {
      FileWrite(g_csv, sym, name, r.verdict, r.n_windows, r.wfe, r.robustness,
                r.is_net, r.oos_net, r.oos_pf, r.oos_wr, r.oos_dd, cost_bps);
   }
}

//+------------------------------------------------------------------+
//| Manual whitespace trim (MQL5 build here lacks StringTrim*)        |
//+------------------------------------------------------------------+
string TrimStr(string s)
{
   while(StringLen(s) > 0 && StringGetCharacter(s, 0) == ' ') s = StringSubstr(s, 1);
   while(StringLen(s) > 0 && StringGetCharacter(s, StringLen(s) - 1) == ' ') s = StringSubstr(s, 0, StringLen(s) - 1);
   return s;
}

//+------------------------------------------------------------------+
//| Parse comma-separated symbol list                                 |
//+------------------------------------------------------------------+
void ParseSymbols(string txt, string &out[])
{
   string parts[];
   int cnt = StringSplit(txt, ',', parts);
   for(int i=0;i<cnt;i++)
   {
      string s = TrimStr(parts[i]);
      if(StringLen(s) > 0) { ArrayResize(out, ArraySize(out)+1); out[ArraySize(out)-1] = s; }
   }
}

//+------------------------------------------------------------------+
//| OnInit - loop over all symbols                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   string syms[];
   ParseSymbols(InpSymbols, syms);
   if(ArraySize(syms) == 0) { ArrayResize(syms, 1); syms[0] = _Symbol; }

   PrintFormat("[WFO-REPORT] === MULTI-SYMBOL Walk-Forward validation: %d symbol(s) | TF=%s "
               "train=%d test=%d SL=%.1f*ATR TP=%.1f*ATR ===",
               ArraySize(syms), EnumToString(InpTF), InpTrainBars, InpTestBars, InpSlAtr, InpTpAtr);

   // Open persistent cross-symbol scoreboard (overwritten each run).
   g_csv = FileOpen(InpReportCsv, FILE_CSV | FILE_WRITE | FILE_ANSI, ';');
   if(g_csv != INVALID_HANDLE)
      FileWrite(g_csv, "Symbol","Strategy","Verdict","Windows","WFE","Robustness","IS_net","OOS_net","OOS_PF","OOS_WR","OOS_maxDD","Cost_bps");

   for(int s = 0; s < ArraySize(syms); s++)
   {
      string sym = syms[s];
      if(!SymbolSelect(sym, true))
      {
         PrintFormat("[WFO-REPORT] === Symbol=%s -> SKIPPED (cannot select / not in terminal) ===", sym);
         continue;
      }
      MqlRates rates[];
      int copied = CopyRates(sym, InpTF, 0, InpBars, rates);
      int n = (copied > 0) ? ArraySize(rates) : 0;
      if(n < InpTrainBars + InpTestBars + 2)
      {
         PrintFormat("[WFO-REPORT] === Symbol=%s -> SKIPPED (only %d bars, need >= %d) ===",
                      sym, n, InpTrainBars + InpTestBars + 2);
         continue;
      }

      double open[], high[], low[], close[], atr[];
      ArrayResize(open,n); ArrayResize(high,n); ArrayResize(low,n); ArrayResize(close,n);
      for(int i=0;i<n;i++){ open[i]=rates[i].open; high[i]=rates[i].high; low[i]=rates[i].low; close[i]=rates[i].close; }
      WF_ComputeATR(high, low, close, n, 14, atr);

      // Per-symbol cost from live spread (honest cross-asset comparison).
      double cost_bps = InpCostBps;
      double sp = (double)SymbolInfoInteger(sym, SYMBOL_SPREAD);
      double pt = SymbolInfoDouble(sym, SYMBOL_POINT);
      double bid = SymbolInfoDouble(sym, SYMBOL_BID);
      if(sp > 0 && pt > 0 && bid > 0) cost_bps = (sp * pt * 2.0 / bid) * 10000.0;
      double cost_rt = 2.0 * cost_bps / 10000.0;

      int sigADX[]; double confADX[];
      int sigRSI[]; double confRSI[];
      int sigVol[]; double confVol[];
      BuildSignals(open, high, low, close, n, sigADX, confADX, sigRSI, confRSI, sigVol, confVol);

      PrintFormat("[WFO-REPORT] === Symbol=%s | bars=%d TF=%s cost=%.2f bps (live spread) ===",
                  sym, n, EnumToString(InpTF), cost_bps);
      Validate(sym, "ADX_Trend",   open, high, low, close, atr, sigADX, confADX, n, cost_rt, cost_bps);
      Validate(sym, "RSI_MeanRev", open, high, low, close, atr, sigRSI, confRSI, n, cost_rt, cost_bps);
      Validate(sym, "VolBreak",    open, high, low, close, atr, sigVol, confVol, n, cost_rt, cost_bps);
   }
   if(g_csv != INVALID_HANDLE) { FileClose(g_csv); g_csv = INVALID_HANDLE; }
   PrintFormat("[WFO-REPORT] === ALL SYMBOLS DONE | scoreboard -> MQL5\\Files\\%s ===", InpReportCsv);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit / OnTick                                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {}
void OnTick() {}
//+------------------------------------------------------------------+
