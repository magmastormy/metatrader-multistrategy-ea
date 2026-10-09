// Phase 1 walk-forward validation engine (MQL5 in-terminal port).
// Mirrors Tools/walkforward/*.py methodology exactly:
// - continuous simulation across IS/OOS window boundaries
// - next-bar-open entry (no look-ahead)
// - ATR-based SL/TP, cost-aware returns
// - threshold re-optimized per IS window, applied to OOS
// - verdict gates on OOS (WFE, robustness, PF, maxDD)
// Used by WalkForwardTesterEA.mqh / WalkForwardTesterEA.mq5.
#property strict

#ifndef WALKFORWARD_VALIDATOR_MQH
#define WALKFORWARD_VALIDATOR_MQH

// ATR (Wilder smoothing) from HLC series
void WF_ComputeATR(const double &high[], const double &low[], const double &close[],
                   int n, int period, double &atr[])
{
   ArrayResize(atr, n);
   if(n <= 0) return;
   double tr[];
   ArrayResize(tr, n);
   for(int i = 0; i < n; i++)
   {
      double hl = high[i] - low[i];
      double hc = (i > 0) ? MathAbs(high[i] - close[i-1]) : hl;
      double lc = (i > 0) ? MathAbs(low[i] - close[i-1]) : hl;
      tr[i] = MathMax(hl, MathMax(hc, lc));
   }
   double sum = 0.0;
   for(int i = 0; i < n; i++)
   {
      if(i < period)
      {
         sum += tr[i];
         atr[i] = sum / (i + 1);
      }
      else
      {
         atr[i] = (atr[i-1] * (period - 1) + tr[i]) / period;
      }
   }
}

// Cost-aware, look-ahead-safe single-pass simulator.
// Entry at open[i] using signal[i-1] & conf[i-1] gated by thr[i].
// Positions carry until SL/TP or end-of-data (no boundary reset).
// Fills rets[]/entryBar[] (preallocated to >= n). Returns count.
int WF_Simulate(const double &open[], const double &high[], const double &low[], const double &close[],
                const double &atr[], const int &signal[], const double &conf[], const double &thr[],
                int n, double sl_atr, double tp_atr, double cost_rt,
                double &rets[], int &entryBar[])
{
   int count = 0;
   double pos = 0.0;        // 0 = flat, +1 long, -1 short
   double entry = 0.0, entry_atr = 0.0;
   int entryIdx = -1;
   for(int i = 1; i < n; i++)
   {
      double o = open[i], h = high[i], l = low[i], c = close[i];
      if(pos != 0.0)
      {
         double sl, tp;
         if(pos > 0) { sl = entry - sl_atr * entry_atr; tp = entry + tp_atr * entry_atr; }
         else        { sl = entry + sl_atr * entry_atr; tp = entry - tp_atr * entry_atr; }
         bool exited = false; double exitp = 0.0;
         if(pos > 0)
         {
            if(l <= sl) { exited = true; exitp = sl; }
            else if(h >= tp) { exited = true; exitp = tp; }
         }
         else
         {
            if(h >= sl) { exited = true; exitp = sl; }
            else if(l <= tp) { exited = true; exitp = tp; }
         }
         if(exited)
         {
            rets[count] = pos * (exitp - entry) / entry - cost_rt;
            entryBar[count] = entryIdx;
            count++;
            pos = 0.0;
            continue; // no same-bar re-entry
         }
      }
      int si = i - 1;
      if(pos == 0.0 && si >= 0 && signal[si] != 0 && MathAbs(conf[si]) >= thr[i])
      {
         pos = (double)signal[si];
         entry = o;
         entry_atr = atr[i];
         if(entry_atr <= 0) entry_atr = MathAbs(o) * 0.01 + 1e-9;
         entryIdx = i;
      }
   }
   // end-of-data market close
   if(pos != 0.0)
   {
      rets[count] = pos * (close[n-1] - entry) / entry - cost_rt;
      entryBar[count] = entryIdx;
      count++;
   }
   return count;
}

// Summary metrics over a trade-return array
void WF_Summarize(const double &rets[], int n, double &expectancy, double &pf,
                  double &wr, double &net, double &maxdd)
{
   expectancy = 0; pf = 0; wr = 0; net = 0; maxdd = 0;
   if(n <= 0) return;
   double wins = 0, losses = 0, wsum = 0, lsum = 0;
   for(int i = 0; i < n; i++)
   {
      net += rets[i];
      if(rets[i] > 0) { wins++; wsum += rets[i]; }
      else { losses++; lsum += -rets[i]; }
   }
   expectancy = net / n;
   wr = wins / n;
   pf = (lsum > 0) ? (wsum / lsum) : (wsum > 0 ? 1e6 : 0);
   // equity drawdown
   double eq = 1.0, peak = 1.0, mdd = 0;
   for(int i = 0; i < n; i++)
   {
      eq *= (1.0 + rets[i]);
      if(eq > peak) peak = eq;
      double dd = (peak > 0) ? (peak - eq)/peak : 0;
      if(dd > mdd) mdd = dd;
   }
   maxdd = mdd;
}

// Walk-forward driver. Fills output metrics for the EA to report.
struct SWFOResult
{
   int     n_windows;
   double  wfe;
   double  robustness;
   double  is_net;
   double  oos_net;
   double  oos_pf;
   double  oos_wr;
   double  oos_dd;
   double  is_expect;
   string  verdict;
};

void WF_Run(const double &open[], const double &high[], const double &low[], const double &close[],
            const double &atr[], const int &signal[], const double &conf[], int n,
            int train_bars, int test_bars, double sl_atr, double tp_atr, double cost_rt,
            SWFOResult &out)
{
   out.n_windows = 0; out.wfe = 0; out.robustness = 0; out.is_net = 0; out.oos_net = 0;
   out.oos_pf = 0; out.oos_wr = 0; out.oos_dd = 0; out.is_expect = 0; out.verdict = "NONE";
   if(n < train_bars + test_bars + 2) { out.verdict = "NEEDS_MORE_DATA"; return; }

   // 1) Build per-bar threshold schedule via per-window IS optimization.
   double thrForBar[];
   ArrayResize(thrForBar, n);
   for(int i = 0; i < n; i++) thrForBar[i] = 0.0;

   double thresholds[21];
   for(int t = 0; t < 21; t++) thresholds[t] = t * 0.05;

   int step = test_bars;
   // Window boundaries recorded for OOS attribution.
   int winIS0[], winIS1[], winOS0[], winOS1[];
   ArrayResize(winIS0, 1); ArrayResize(winIS1, 1); ArrayResize(winOS0, 1); ArrayResize(winOS1, 1);
   int nWin = 0;

   for(int w = 0; w + train_bars + test_bars <= n; w += step)
   {
      int is0 = w, is1 = w + train_bars;
      int os0 = is1, os1 = is1 + test_bars;

      // optimize threshold on this IS window (independent sim over IS region)
      double bestThr = 0.0, bestNet = -1e9;
      for(int t = 0; t < 21; t++)
      {
         double r[]; int eb[]; ArrayResize(r, is1 + 2); ArrayResize(eb, is1 + 2);
         double thIS[]; ArrayResize(thIS, is1);
         for(int k = 0; k < is1; k++) thIS[k] = thresholds[t];
         int c = WF_Simulate(open, high, low, close, atr, signal, conf, thIS, is1, sl_atr, tp_atr, cost_rt, r, eb);
         double e, p, wr, net, dd;
         WF_Summarize(r, c, e, p, wr, net, dd);
         if(net > bestNet) { bestNet = net; bestThr = thresholds[t]; }
      }
      for(int i = os0; i < os1 && i < n; i++) thrForBar[i] = bestThr;

      // record window
      if(nWin >= ArraySize(winIS0)) { ArrayResize(winIS0, nWin + 8); ArrayResize(winIS1, nWin + 8); ArrayResize(winOS0, nWin + 8); ArrayResize(winOS1, nWin + 8); }
      winIS0[nWin] = is0; winIS1[nWin] = is1; winOS0[nWin] = os0; winOS1[nWin] = os1;
      nWin++;
   }
   out.n_windows = nWin;

   // 2) Single continuous sim over full series with thrForBar[].
   double rAll[]; int ebAll[]; ArrayResize(rAll, n + 2); ArrayResize(ebAll, n + 2);
   int cAll = WF_Simulate(open, high, low, close, atr, signal, conf, thrForBar, n, sl_atr, tp_atr, cost_rt, rAll, ebAll);

   // 3) Attribute trades to IS/OOS windows by ENTRY bar (first matching window wins).
   //    IS windows OVERLAP (train_bars > step), so a trade's entry bar can fall inside
   //    several IS regions. Each trade must be placed EXACTLY ONCE (guarded by
   //    `attributed`) or isN/oosN overflow the cAll+1 buffers. OOS windows are
   //    non-overlapping, so a trade matches OOS of at most one window.
   double isR[], oosR[]; ArrayResize(isR, cAll + 1); ArrayResize(oosR, cAll + 1);
   bool attributed[]; ArrayResize(attributed, cAll);
   for(int k = 0; k < cAll; k++) attributed[k] = false;
   int isN = 0, oosN = 0;
   int profOOS = 0, counted = 0;
   for(int wn = 0; wn < nWin; wn++)
   {
      double winNet = 0.0; int winN = 0;
      for(int k = 0; k < cAll; k++)
      {
         if(attributed[k]) continue;
         int b = ebAll[k];
         if(b >= winOS0[wn] && b < winOS1[wn])
         {
            oosR[oosN++] = rAll[k];
            attributed[k] = true;
            winNet += rAll[k]; winN++;
         }
         else if(b >= winIS0[wn] && b < winIS1[wn])
         {
            isR[isN++] = rAll[k];
            attributed[k] = true;
            winNet += rAll[k]; winN++;
         }
      }
      if(winN >= 3) { counted++; if(winNet > 0) profOOS++; }
   }
   // Any trade not attributed to a window (e.g. opened after the last OOS window)
   // -> IS bucket. Keeps every trade accounted for; never overflows (isN+oosN==cAll).
   for(int k = 0; k < cAll; k++)
   {
      if(!attributed[k]) { isR[isN++] = rAll[k]; attributed[k] = true; }
   }

   double eIs, pIs, wrIs, netIs, ddIs;
   WF_Summarize(isR, isN, eIs, pIs, wrIs, netIs, ddIs);
   double eOos, pOos, wrOos, netOos, ddOos;
   WF_Summarize(oosR, oosN, eOos, pOos, wrOos, netOos, ddOos);

   out.is_net = netIs; out.is_expect = eIs;
   out.oos_net = netOos; out.oos_pf = pOos; out.oos_wr = wrOos; out.oos_dd = ddOos;
   out.wfe = (eIs > 0) ? (eOos / eIs) : (eOos > 0 ? 1.0 : 0.0);
   out.robustness = (counted > 0) ? (profOOS / (double)counted) : 0.0;

   // 4) Verdict (mirrors metrics.verdict)
   if(nWin < 3 || oosN < 8) { out.verdict = "NEEDS_MORE_DATA"; return; }
   if(netOos <= 0 || pOos < 1.0 || out.robustness < 0.40 || out.wfe < 0.30) { out.verdict = "REJECTED"; return; }
   if(out.wfe >= 0.50 && out.robustness >= 0.60 && netOos > 0 && pOos >= 1.10 && ddOos <= 0.35)
      out.verdict = "APPROVED";
   else
      out.verdict = "CONDITIONAL";
}

#endif // WALKFORWARD_VALIDATOR_MQH
//+------------------------------------------------------------------+
