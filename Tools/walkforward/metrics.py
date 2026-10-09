"""
metrics.py - Walk-forward performance metrics + edge verdict logic.

Pure stdlib. All trade returns are expressed as NET return fractions
(e.g. a trade that lost 0.7% of equity = -0.007). An equity curve is
built by compounding these fractions.

The verdict logic is the heart of Phase 1: it is what actually *gates* a
strategy before it is allowed to ship live. The research (FCA 2022 /
NBER 2023 / standard WFO literature) says the #1 difference between EAs
that print and EAs that bleed is whether the edge is validated
out-of-sample and stays stable across windows.
"""

import math


def expectancy(returns):
    """Mean net return per trade. The single most important number."""
    if not returns:
        return 0.0
    return sum(returns) / len(returns)


def win_rate(returns):
    if not returns:
        return 0.0
    w = sum(1 for r in returns if r > 0.0)
    return w / len(returns)


def profit_factor(returns):
    """Gross profit / gross loss. <1.0 means the edge is negative."""
    gross_w = sum(r for r in returns if r > 0.0)
    gross_l = -sum(r for r in returns if r < 0.0)
    if gross_l <= 1e-12:
        return float("inf") if gross_w > 0.0 else 0.0
    return gross_w / gross_l


def max_drawdown(equity):
    """Largest peak-to-trough drop on the equity curve (absolute units)."""
    if not equity:
        return 0.0
    peak = equity[0]
    mdd = 0.0
    for v in equity:
        if v > peak:
            peak = v
        dd = peak - v
        if dd > mdd:
            mdd = dd
    return mdd


def max_drawdown_pct(equity):
    """Largest peak-to-trough drop as a fraction of the peak."""
    if not equity:
        return 0.0
    peak = equity[0]
    mdd = 0.0
    for v in equity:
        if v > peak:
            peak = v
        if peak > 0:
            dd = (peak - v) / peak
            if dd > mdd:
                mdd = dd
    return mdd


def equity_curve(returns, start=1.0):
    eq = [start]
    for r in returns:
        eq.append(eq[-1] * (1.0 + r))
    return eq


def sharpe_rough(returns):
    """
    Return/risk of the per-trade series (not annualized - we do not assume
    a fixed bar count per year here; this is a shape measure). inf if std=0
    and mean>0, -inf if mean<0.
    """
    if len(returns) < 2:
        return 0.0
    m = expectancy(returns)
    if m == 0.0:
        return 0.0
    var = sum((r - m) ** 2 for r in returns) / (len(returns) - 1)
    sd = math.sqrt(var)
    if sd < 1e-12:
        return float("inf") if m > 0 else float("-inf")
    return m / sd


def summarize(returns):
    """Return a dict of all per-series metrics for a list of trade returns."""
    eq = equity_curve(returns)
    return {
        "n_trades": len(returns),
        "expectancy": expectancy(returns),
        "win_rate": win_rate(returns),
        "profit_factor": profit_factor(returns),
        "net_return": sum(returns),
        "max_dd": max_drawdown(eq),
        "max_dd_pct": max_drawdown_pct(eq),
        "return_risk": sharpe_rough(returns),
        "final_equity": eq[-1] if eq else 1.0,
    }


def verdict(is_metrics, oos_metrics, wfe, robustness_frac, n_windows,
            min_trades_per_window=8, min_windows=3):
    """
    Decide whether an edge is APPROVED / REJECTED / CONDITIONAL / NEEDS_MORE_DATA.

    Gates (all derived from the research's 'validate OOS, stay stable' thesis):
      - NEEDS_MORE_DATA if we cannot get enough OOS windows or trades.
      - REJECTED if OOS net <= 0, or OOS profit factor < 1.0, or robustness
        (fraction of OOS windows profitable) < 0.40, or WFE < 0.30.
      - APPROVED if OOS net > 0, PF >= 1.10, robustness >= 0.60, WFE >= 0.50,
        and OOS maxDD is within a sane bound.
      - CONDITIONAL otherwise (borderline - use only with reduced risk).
    """
    if n_windows < min_windows or oos_metrics["n_trades"] < min_trades_per_window:
        return "NEEDS_MORE_DATA"

    oos_net = oos_metrics["net_return"]
    oos_pf = oos_metrics["profit_factor"]
    oos_dd = oos_metrics["max_dd_pct"]
    # IS sparsity alone must not block: we gate on OOS, which is what matters.

    wfe_ok = wfe >= 0.50
    rob_ok = robustness_frac >= 0.60
    oos_ok = (oos_net > 0.0) and (oos_pf >= 1.10) and (oos_dd <= 0.35)

    if (oos_net <= 0.0) or (oos_pf < 1.0) or (robustness_frac < 0.40) or (wfe < 0.30):
        return "REJECTED"
    if wfe_ok and rob_ok and oos_ok:
        return "APPROVED"
    return "CONDITIONAL"
