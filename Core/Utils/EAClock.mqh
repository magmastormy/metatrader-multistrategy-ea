#ifndef EA_CLOCK_MQH
#define EA_CLOCK_MQH

// One clock for anything that changes a decision.
//
// Measured, and the reason this file exists: two Strategy Tester runs of the byte-identical binary on the
// same window (`2026.09.01`->`09.08`, Model=1, M15) finished at **+5.03%** and **-4.89%**. The spread is
// not market noise - it is wall clock. Every behavioural throttle in this tree used `GetTickCount()`,
// which measures real elapsed milliseconds since the terminal started, while the tester advances ~435x
// faster than real time. A "500 ms" trailing rule therefore fires every ~218 simulated seconds (about
// seven M15 bars) in backtest and every 500 real milliseconds in live, and a "200 ms" microstructure
// throttle feeds a different number of ticks per bar in every run, so VPIN/OFI differ, votes differ and
// the trade path diverges. A 7-day window with 308 fills and the same window with 379 fills is the same
// code deciding differently, which makes every A/B in this repository unreadable.
//
// Live behaviour is untouched: `GetTickCount()` is exactly right there. In the tester the clock is the
// simulated one, so a throttle means "once per simulated interval" and a TTL expires in simulated time.
// A TTL expressed in milliseconds is rounded down to the second granularity of `TimeCurrent()`; that is
// deterministic, and a 2^32 ms wrap is 49.7 simulated days, longer than any window used here.
uint EAClockMs()
{
   if(MQLInfoInteger(MQL_TESTER))
      return (uint)(TimeCurrent() * 1000);

   return GetTickCount();
}

#endif // EA_CLOCK_MQH
