import { useRef, useState, useEffect, useMemo } from 'react';
import {
  AreaChart, Area, XAxis, YAxis, Tooltip, ResponsiveContainer, ReferenceLine,
  BarChart, Bar, Cell,
} from 'recharts';
import type { EAState, LogEntry } from './types/ea-state';
import { useEAState } from './hooks/useEAState';
import StatusBadge from './components/shared/StatusBadge';
import NeuralNetViz from './components/shared/NeuralNetViz';
import NetworkMesh from './components/shared/NetworkMesh';
import AnimatedCounter from './components/shared/AnimatedCounter';
import type { ReactNode } from 'react';

/* ---------- helpers ---------- */
const fmtTime = (iso: string) => new Date(iso).toLocaleTimeString('en-GB', { hour12: false });
const pct = (n: number) => `${(n * 100).toFixed(1)}%`;
const money = (n: number) => n.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const money0 = (n: number) => n.toLocaleString(undefined, { maximumFractionDigits: 0 });

function formatDuration(min: number): string {
  if (min < 60) return `${min}m`;
  const h = Math.floor(min / 60); const m = min % 60;
  if (h < 24) return `${h}h ${m}m`;
  const d = Math.floor(h / 24); return `${d}d ${h % 24}h`;
}

const tipStyle = {
  background: 'var(--surface)', border: '1px solid var(--border)',
  borderRadius: 8, fontSize: 12, color: 'var(--text)', boxShadow: 'var(--shadow-1)',
};
const tipLabel = { color: 'var(--text-2)' };
const axisTick = { fontSize: 9, fill: '#9a9aa2' } as const;
const axisLine = { stroke: 'rgba(140,140,150,0.25)' } as const;

/* ---------- section wrapper ---------- */
function Section({ id, title, meta, children }: { id: string; title: string; meta?: string; children: ReactNode }) {
  return (
    <section className="section" id={id}>
      <div className="section-head">
        <h2 className="section-title">{title}</h2>
        {meta && <span className="section-meta">{meta}</span>}
      </div>
      {children}
    </section>
  );
}

/* =====================================================================
   DASHBOARD
   ===================================================================== */
export default function Dashboard({ theme }: { theme: string }) {
  const { state, logs, isConnected, sendCommand } = useEAState();

  /* equity history */
  const eqRef = useRef<{ time: string; equity: number; balance: number }[]>([]);
  const [, force] = useState(0);
  useEffect(() => {
    if (state) {
      eqRef.current = [...eqRef.current.slice(-99), {
        time: fmtTime(state.timestamp),
        equity: state.account.equity,
        balance: state.account.balance,
      }];
      force((x) => x + 1);
    }
  }, [state]);

  /* AI confidence + regime history */
  const confRef = useRef<{ time: string; confidence: number; conformal: number }[]>([]);
  useEffect(() => {
    const nn = state?.ai?.neural_net;
    if (nn) {
      confRef.current = [...confRef.current.slice(-49), {
        time: fmtTime(state!.timestamp),
        confidence: nn.confidence ?? 0,
        conformal: nn.conformal_quantile ?? 0,
      }];
      force((x) => x + 1);
    }
  }, [state]);

  const mode = state?.execution_mode ?? '—';

  return (
    <main className="page">
      {/* ================= OVERVIEW ================= */}
      <Section id="overview" title="Overview" meta={isConnected ? (mode === 'LIVE' ? 'Live trading' : 'Monitoring') : 'Connecting…'}>
        <div className="hero">
          <NetworkMesh className="netmesh" />
          <div className="hero-ey">
            <div className="hero-label">Equity</div>
            <div className="hero-value tnum">
              {state ? <AnimatedCounter value={state.account.equity} prefix="$" decimals={2} /> : '—'}
            </div>
          </div>
          <div className="hero-ey">
            <div className="hero-label">Balance</div>
            <div className="hero-value mid tnum">
              {state ? <AnimatedCounter value={state.account.balance} prefix="$" decimals={2} /> : '—'}
            </div>
          </div>
          <div className="hero-spark">
            {eqRef.current.length > 1 ? (
              <ResponsiveContainer width="100%" height="100%">
                <AreaChart data={eqRef.current} margin={{ top: 6, right: 4, left: 4, bottom: 0 }}>
                  <defs>
                    <linearGradient id="eqGrad" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="0%" stopColor="rgba(79,70,229,0.18)" />
                      <stop offset="100%" stopColor="rgba(79,70,229,0)" />
                    </linearGradient>
                  </defs>
                  <XAxis dataKey="time" tick={axisTick} axisLine={false} tickLine={false} minTickGap={28} />
                  <YAxis tick={axisTick} axisLine={false} tickLine={false} width={42} domain={['auto', 'auto']}
                    tickFormatter={(v: number) => `$${(v / 1000).toFixed(0)}k`} />
                  <Tooltip contentStyle={tipStyle} labelStyle={tipLabel} formatter={(v: string | number | readonly (string | number)[] | undefined) => [`$${Number(v ?? 0).toFixed(2)}`, 'Equity']} />
                  <ReferenceLine y={50000} stroke="rgba(140,140,150,0.4)" strokeDasharray="3 3" />
                  <Area type="monotone" dataKey="equity" stroke="#4f46e5" strokeWidth={1.8} fill="url(#eqGrad)" animationDuration={500} />
                </AreaChart>
              </ResponsiveContainer>
            ) : <div className="empty" style={{ height: '100%' }}>Collecting equity data…</div>}
          </div>
          <div className="hero-side">
            <div>
              <div className="hero-label">Free Margin</div>
              <div className="note tnum">{state ? `$${money(state.account.free_margin)}` : '—'}</div>
              <div className="muted" style={{ fontSize: 11, marginTop: 2 }}>
                Level {state ? `${state.account.margin_level.toFixed(1)}%` : '—'}
              </div>
            </div>
            <div>
              <div className="hero-label">Drawdown</div>
              <div className={`note tnum ${state && state.risk.current_drawdown_pct > 5 ? 'neg' : ''}`}>
                {state ? `${state.risk.current_drawdown_pct.toFixed(2)}%` : '—'}
              </div>
            </div>
          </div>
        </div>

        {state && (
          <>
            <div className="grid cols-6" style={{ marginTop: 16 }}>
              <Stat label="Win Rate" value={`${pct(state.performance.win_rate)}`} />
              <Stat label="Profit Factor" value={state.performance.profit_factor.toFixed(2)} />
              <Stat label="Sharpe" value={state.performance.sharpe_ratio.toFixed(2)} />
              <Stat label="Recovery" value={state.performance.recovery_factor.toFixed(2)} />
              <Stat label="Net P/L" value={`$${money0(state.performance.net_profit)}`} tone={state.performance.net_profit >= 0 ? 'pos' : 'neg'} />
              <Stat label="Total Trades" value={money0(state.performance.total_trades)} />
            </div>

            <div className="grid cols-3" style={{ marginTop: 14 }}>
              <div className="card">
                <div className="divider-label">Open Positions</div>
                <div className="stat-value tnum" style={{ fontSize: 30 }}>{state.positions.length}</div>
                {state.positions.length > 0 && (
                  <div className="note" style={{ marginTop: 6 }}>
                    P&amp;L: <span className={state.positions.reduce((s, p) => s + p.profit, 0) >= 0 ? 'pos' : 'neg'}>
                      ${money(state.positions.reduce((s, p) => s + p.profit, 0))}
                    </span>
                  </div>
                )}
              </div>
              <div className="card">
                <div className="divider-label">Heartbeat</div>
                <div className="grid cols-3" style={{ gap: 8 }}>
                  <HB k="Scans" v={state.heartbeat.scans} />
                  <HB k="Signals" v={state.heartbeat.signals_generated} />
                  <HB k="Valid" v={state.heartbeat.signals_validated} />
                  <HB k="Opened" v={state.heartbeat.trades_opened} />
                  <HB k="Shadow" v={state.heartbeat.shadow_trades} />
                  <HB k="Spikes" v={state.heartbeat.spike_events} />
                </div>
              </div>
              <div className="card">
                <div className="between" style={{ marginBottom: 8 }}>
                  <span className="divider-label" style={{ margin: 0 }}>Scalp Mode</span>
                  <StatusBadge status={state.scalp.active ? 'online' : 'offline'} label={state.scalp.active ? 'Active' : 'Inactive'} />
                </div>
                <div className="kv"><span className="k">Positions</span><span className="v">{state.scalp.open_positions}/{state.scalp.max_positions}</span></div>
                <div className="kv"><span className="k">Entries</span><span className="v">{state.scalp.total_entries}</span></div>
                <div className="kv"><span className="k">Rejected</span><span className="v">{state.scalp.total_rejections}</span></div>
              </div>
            </div>
          </>
        )}
      </Section>

      {/* ================= POSITIONS ================= */}
      <Section id="positions" title="Positions" meta={state ? `${state.positions.length} open` : undefined}>
        {state && state.positions.length > 0 ? (
          <div className="card flush">
            <table className="table">
              <thead>
                <tr>
                  <th>Ticket</th><th>Symbol</th><th>Type</th><th className="num">Lots</th>
                  <th className="num">Open</th><th className="num">Current</th><th className="num">P&amp;L</th>
                  <th className="num">Duration</th><th>Strategy</th>
                </tr>
              </thead>
              <tbody>
                {state.positions.map((p) => (
                  <tr key={p.ticket}>
                    <td className="mono">{p.ticket}</td>
                    <td className="strong">{p.symbol}</td>
                    <td><span className={`pill ${p.type === 'BUY' ? 'buy' : 'sell'}`}>{p.type}</span></td>
                    <td className="num mono">{p.lots.toFixed(2)}</td>
                    <td className="num mono">{p.open_price.toFixed(5)}</td>
                    <td className="num mono">{p.current_price.toFixed(5)}</td>
                    <td className={`num mono strong ${p.profit >= 0 ? 'pos' : 'neg'}`}>
                      <AnimatedCounter value={p.profit} prefix="$" decimals={2} />
                    </td>
                    <td className="num muted">{formatDuration(p.duration_minutes)}</td>
                    <td className="dim" style={{ fontSize: 12 }}>{p.strategy}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        ) : <div className="empty"><div className="em">No open positions</div>Positions appear here when trades are opened.</div>}
      </Section>

      {/* ================= STRATEGIES ================= */}
      <Section id="strategies" title="Strategies"
        meta={state ? `${state.strategies.length} strategies · ${Object.keys(groupStrategies(state.strategies)).length} symbols` : undefined}>
        {state && (
          <div className="stack">
            <div className="split-7-5">
              <div className="card">
                <div className="divider-label">Strategy Registry</div>
                <div className="stack" style={{ gap: 14 }}>
                  {Object.entries(groupStrategies(state.strategies)).map(([symbol, list]) => (
                    <div key={symbol}>
                      <div className="between" style={{ marginBottom: 6 }}>
                        <span className="strong">{symbol}</span>
                        <span className="muted" style={{ fontSize: 11 }}>{list.length} strategies</span>
                      </div>
                      <div className="stack" style={{ gap: 6 }}>
                        {list.map((s, i) => (
                          <div key={`${s.name}-${i}`} className="row between" style={{ padding: '7px 10px', border: '1px solid var(--border)', borderRadius: 8 }}>
                            <div className="row" style={{ gap: 8 }}>
                              <span className="strong" style={{ fontSize: 13 }}>{s.name}</span>
                              <span className="muted mono" style={{ fontSize: 11 }}>{s.symbol}</span>
                            </div>
                            <div className="row" style={{ gap: 10 }}>
                              <span className="dim" style={{ fontSize: 12 }}>{s.role}</span>
                              <StatusBadge status={s.mode === 'ACTIVE' ? 'online' : s.mode === 'SHADOW' ? 'warning' : 'offline'} label={s.mode} />
                              <span className="mono dim" style={{ fontSize: 12, width: 52, textAlign: 'right' }}>W {s.weight.toFixed(2)}</span>
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              </div>

              <div className="card">
                <div className="divider-label">Consensus Summary</div>
                <div className="stack" style={{ gap: 10 }}>
                  {Object.entries(state.consensus.symbols).map(([symbol, d]) => (
                    <div key={symbol} style={{ padding: 12, border: '1px solid var(--border)', borderRadius: 8 }}>
                      <div className="between" style={{ marginBottom: 8 }}>
                        <span className="strong">{symbol}</span>
                        <StatusBadge status={d.quorum_met ? 'online' : 'warning'} label={d.quorum_met ? 'Quorum' : 'No Quorum'} />
                      </div>
                      <div className="grid cols-3" style={{ gap: 8, fontSize: 12 }}>
                        <Field k="Signal" v={d.last_signal} cls={d.last_signal === 'BUY' ? 'pos' : d.last_signal === 'SELL' ? 'neg' : 'dim'} />
                        <Field k="Conf" v={pct(d.confidence)} />
                        <Field k="Veto" v={d.veto_code || '—'} />
                        <Field k="Buy" v={d.buy_score.toFixed(2)} cls="pos" />
                        <Field k="Sell" v={d.sell_score.toFixed(2)} cls="neg" />
                        <Field k="Cluster" v={d.dominant_cluster} />
                      </div>
                      <div className="muted" style={{ fontSize: 11, marginTop: 6 }}>
                        {d.voted_strategies}/{d.active_strategies} strategies voted
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            </div>

            <div className="card">
              <div className="divider-label">Strategy Weight Distribution</div>
              <div style={{ height: 240 }}>
                <ResponsiveContainer width="100%" height="100%">
                  <BarChart data={state.strategies} layout="vertical" margin={{ top: 4, right: 12, left: 0, bottom: 0 }}>
                    <XAxis type="number" tick={axisTick} axisLine={axisLine} tickLine={false} />
                    <YAxis type="category" dataKey="name" width={160} tick={axisTick} axisLine={axisLine} tickLine={false} />
                    <Tooltip contentStyle={tipStyle} cursor={{ fill: 'rgba(140,140,150,0.08)' }} formatter={(v: string | number | readonly (string | number)[] | undefined) => [Number(v ?? 0).toFixed(2), 'Weight']} />
                    <Bar dataKey="weight" radius={[0, 3, 3, 0]} barSize={16}>
                      {state.strategies.map((s, i) => (
                        <Cell key={i} fill={s.mode === 'ACTIVE' ? '#4f46e5' : s.mode === 'SHADOW' ? '#b45309' : '#9a9aa2'} />
                      ))}
                    </Bar>
                  </BarChart>
                </ResponsiveContainer>
              </div>
            </div>
          </div>
        )}
      </Section>

      {/* ================= RISK ================= */}
      <Section id="risk" title="Risk" meta={state ? `Gate ${state.risk.gate_approved}/${state.risk.gate_rejected}` : undefined}>
        {state && (
          <div className="split-8-4">
            <div className="stack">
              <GaugeBar label="Daily Risk Used" value={state.risk.daily_risk_used_pct} max={state.risk.max_daily_risk_pct}
                detail={`${state.risk.daily_risk_used_pct.toFixed(2)}% / ${state.risk.max_daily_risk_pct.toFixed(2)}%`} />
              <GaugeBar label="Daily Entry Risk" value={state.risk.daily_entry_risk_pct} max={state.risk.max_daily_risk_pct}
                detail={`${state.risk.daily_entry_risk_pct.toFixed(2)}% of budget`} />
              <GaugeBar label="Open Exposure" value={state.risk.open_exposure_pct} max={100} detail={`${state.risk.open_exposure_pct.toFixed(2)}%`} />
              <GaugeBar label="Portfolio Risk" value={state.risk.portfolio_risk_pct} max={100} detail={`${state.risk.portfolio_risk_pct.toFixed(2)}%`} />
              <div className="card">
                <div className="divider-label">Current Drawdown</div>
                <div className="row" style={{ gap: 16 }}>
                  <span className="stat-value tnum neg" style={{ fontSize: 30 }}>{state.risk.current_drawdown_pct.toFixed(2)}%</span>
                  <div className="bar lg" style={{ flex: 1 }}>
                    <div className="bar-fill mix" style={{ width: `${Math.min(state.risk.current_drawdown_pct, 100)}%` }} />
                  </div>
                </div>
              </div>
            </div>

            <div className="stack">
              <div className="card">
                <div className="divider-label">Mode Status</div>
                <div className="kv"><span className="k">Conservative</span><StatusBadge status={state.risk.conservative_mode ? 'danger' : 'offline'} label={state.risk.conservative_mode ? 'ACTIVE' : 'OFF'} /></div>
                <div className="kv"><span className="k">Emergency</span><StatusBadge status={state.risk.emergency_mode ? 'danger' : 'offline'} label={state.risk.emergency_mode ? 'ACTIVE' : 'OFF'} /></div>
              </div>
              <div className="card">
                <div className="divider-label">Risk Gate</div>
                <div className="grid cols-2" style={{ gap: 10, marginBottom: 8 }}>
                  <div><div className="muted" style={{ fontSize: 12 }}>Approved</div><div className="stat-value pos tnum" style={{ fontSize: 24 }}>{state.risk.gate_approved}</div></div>
                  <div><div className="muted" style={{ fontSize: 12 }}>Rejected</div><div className="stat-value neg tnum" style={{ fontSize: 24 }}>{state.risk.gate_rejected}</div></div>
                </div>
                <div className="bar">
                  <div className="bar-fill pos" style={{ width: `${(state.risk.gate_approved / Math.max(state.risk.gate_approved + state.risk.gate_rejected, 1)) * 100}%` }} />
                  <div className="bar-fill neg" style={{ width: `${(state.risk.gate_rejected / Math.max(state.risk.gate_approved + state.risk.gate_rejected, 1)) * 100}%` }} />
                </div>
              </div>
              <div className="card">
                <div className="kv"><span className="k">Risk / Trade</span><span className="v">{state.risk.active_risk_per_trade_pct.toFixed(2)}%</span></div>
                <div className="kv"><span className="k">Daily MtM Loss</span><span className="v">{state.risk.daily_mtm_loss_pct.toFixed(2)}%</span></div>
                <div className="kv"><span className="k">Max Daily Risk</span><span className="v">{state.risk.max_daily_risk_pct.toFixed(2)}%</span></div>
              </div>
            </div>
          </div>
        )}
      </Section>

      {/* ================= AI / CONSENSUS ================= */}
      <Section id="ai" title="AI & Consensus" meta={state ? `Features ${state.ai.features_total ?? 65}` : undefined}>
        {state && (
          <div className="stack">
            <div className="grid cols-6">
              <Stat label="Neural Signal" value={state.ai.neural_net?.signal ?? '—'} />
              <Stat label="Confidence" value={state.ai.neural_net?.confidence !== undefined ? pct(state.ai.neural_net.confidence) : '—'} />
              <Stat label="Conformal Q" value={state.ai.neural_net?.conformal_quantile?.toFixed(3) ?? '—'} />
              <Stat label="Regime" value={state.ai.regime?.current ?? '—'} />
              <Stat label="Labels" value={state.ai.neural_net?.labels_resolved?.toString() ?? '—'} />
              <Stat label="Train Steps" value={state.ai.neural_net?.training_steps?.toString() ?? '—'} />
            </div>

            <div className="split-5-7">
              <div className="netframe">
                <div className="divider-label">Neural Network</div>
                <NeuralNetViz confidence={state.ai.neural_net?.confidence ?? 0.5} signal={state.ai.neural_net?.signal ?? 'NONE'}
                  training theme={theme} regime={state.ai.regime?.current ?? 'RANGE'} width={360} height={220} />
                <div className="netlegend">
                  <span className="li"><span className="sw" style={{ background: 'var(--accent)' }} /> Active</span>
                  <span className="li"><span className="sw" style={{ background: 'var(--text-3)' }} /> Inactive</span>
                  <span className="li"><span className="sw" style={{ background: 'var(--warn)' }} /> Training</span>
                </div>
              </div>
              <div className="card">
                <div className="between" style={{ marginBottom: 8 }}>
                  <span className="divider-label" style={{ margin: 0 }}>Confidence Timeline</span>
                  <StatusBadge status={state.ai.neural_net?.active ? 'online' : 'offline'} label={state.ai.neural_net?.active ? 'Live' : 'Off'} />
                </div>
                <div style={{ height: 200 }}>
                  {confRef.current.length > 1 ? (
                    <ResponsiveContainer width="100%" height="100%">
                      <AreaChart data={confRef.current} margin={{ top: 6, right: 6, left: 0, bottom: 0 }}>
                        <defs>
                          <linearGradient id="confGrad" x1="0" y1="0" x2="0" y2="1">
                            <stop offset="0%" stopColor="rgba(79,70,229,0.18)" />
                            <stop offset="100%" stopColor="rgba(79,70,229,0)" />
                          </linearGradient>
                        </defs>
                        <XAxis dataKey="time" tick={axisTick} axisLine={false} tickLine={false} minTickGap={28} />
                        <YAxis tick={axisTick} axisLine={false} tickLine={false} domain={[0, 1]} width={32} />
                        <Tooltip contentStyle={tipStyle} labelStyle={tipLabel} />
                        <Area type="monotone" dataKey="confidence" stroke="#4f46e5" strokeWidth={1.8} fill="url(#confGrad)" animationDuration={500} />
                      </AreaChart>
                    </ResponsiveContainer>
                  ) : <div className="empty" style={{ height: '100%' }}>Collecting…</div>}
                </div>
              </div>
            </div>

            <div className="grid cols-4">
              <div className="card">
                <div className="divider-label">Neural Network</div>
                <Detail k="Signal" v={state.ai.neural_net?.signal ?? '—'} cls={state.ai.neural_net?.signal === 'BUY' ? 'pos' : state.ai.neural_net?.signal === 'SELL' ? 'neg' : 'dim'} />
                <Detail k="Confidence" v={state.ai.neural_net?.confidence !== undefined ? pct(state.ai.neural_net.confidence) : '—'} />
                <Detail k="Conformal Q" v={state.ai.neural_net?.conformal_quantile?.toFixed(3) ?? '—'} />
                <Detail k="Asset Class" v={state.ai.neural_net?.asset_class?.toString() ?? '—'} />
                <Detail k="Barrier K" v={state.ai.neural_net?.barrier_k?.toFixed(2) ?? '—'} />
                <Detail k="Vert Bars" v={state.ai.neural_net?.barrier_vert_bars?.toString() ?? '—'} />
                <Detail k="Norm Ready" v={state.ai.neural_net?.normalization_ready ? 'YES' : 'NO'} />
              </div>
              <div className="card">
                <div className="divider-label">Meta-Labeler</div>
                <Detail k="Features" v={state.ai.meta_labeler?.features?.toString() ?? '—'} />
                <Detail k="Cooldown" v={state.ai.meta_labeler?.cooldown?.toString() ?? '—'} />
                <Detail k="Stop Patience" v={state.ai.meta_labeler?.early_stop_patience?.toString() ?? '—'} />
                <Detail k="Win Rate" v={state.ai.meta_labeler?.recent_win_rate !== undefined ? pct(state.ai.meta_labeler.recent_win_rate) : '—'} />
                <Detail k="Avg Conf" v={state.ai.meta_labeler?.recent_avg_confidence !== undefined ? pct(state.ai.meta_labeler.recent_avg_confidence) : '—'} />
                <Detail k="Samples" v={state.ai.meta_labeler?.samples_since_train?.toString() ?? '—'} />
              </div>
              <div className="card">
                <div className="divider-label">AI Adapters</div>
                {([['ONNX', state.ai.onnx], ['Ensemble', state.ai.ensemble], ['Transformer', state.ai.transformer], ['NN', state.ai.nn]] as const).map(([key, d]) => (
                  <div key={key} className="kv">
                    <StatusBadge status={d.active ? 'online' : 'offline'} label={key} showDot={false} />
                    <span className="mono dim" style={{ fontSize: 11 }}>
                      {d.votes !== undefined ? `V ${d.votes} ` : ''}{d.conf !== undefined ? `C ${pct(d.conf)} ` : ''}{d.accuracy !== undefined ? `A ${pct(d.accuracy)}` : ''}
                    </span>
                  </div>
                ))}
              </div>
              <div className="card">
                <div className="divider-label">Market Regime</div>
                {regimeBars(state.ai.regime).map((r) => (
                  <div key={r.label} style={{ marginBottom: 8 }}>
                    <div className="between" style={{ fontSize: 12, marginBottom: 3 }}>
                      <span className="dim">{r.label}</span><span className="mono">{r.value}%</span>
                    </div>
                    <div className="bar"><div className="bar-fill" style={{ width: `${r.value}%` }} /></div>
                  </div>
                ))}
              </div>
            </div>
          </div>
        )}
      </Section>

      {/* ================= LOGS ================= */}
      <Section id="logs" title="Logs">
        <LogsPanel logs={logs} />
      </Section>

      {/* ================= CONTROL ================= */}
      <Section id="control" title="Control" meta={mode !== '—' ? `Mode: ${mode}` : undefined}>
        <ControlPanel mode={mode} isConnected={isConnected} sendCommand={sendCommand} />
      </Section>
    </main>
  );
}

/* =====================================================================
   small presentational helpers
   ===================================================================== */
function Stat({ label, value, tone }: { label: string; value: string; tone?: 'pos' | 'neg' }) {
  return (
    <div className="stat tight">
      <div className="stat-label">{label}</div>
      <div className={`stat-value tnum ${tone ?? ''}`} style={{ fontSize: 20, marginTop: 4 }}>{value}</div>
    </div>
  );
}

function HB({ k, v }: { k: string; v: number }) {
  return (
    <div style={{ textAlign: 'center', padding: '6px 4px', background: 'var(--surface-2)', borderRadius: 7 }}>
      <div className="mono strong" style={{ fontSize: 14 }}>{money0(v)}</div>
      <div className="muted" style={{ fontSize: 10, textTransform: 'uppercase', letterSpacing: '0.04em' }}>{k}</div>
    </div>
  );
}

function Field({ k, v, cls = 'dim' }: { k: string; v: string; cls?: string }) {
  return (
    <div>
      <div className="muted" style={{ fontSize: 10, textTransform: 'uppercase', letterSpacing: '0.04em' }}>{k}</div>
      <div className={`${cls} strong`} style={{ fontSize: 13 }}>{v}</div>
    </div>
  );
}

function GaugeBar({ label, value, max, detail }: { label: string; value: number; max: number; detail: string }) {
  const pctV = Math.min((value / max) * 100, 100);
  const cls = pctV > 80 ? 'neg' : pctV > 50 ? 'warn' : '';
  return (
    <div className="card">
      <div className="between" style={{ marginBottom: 8 }}>
        <span className="divider-label" style={{ margin: 0 }}>{label}</span>
        <span className="muted mono" style={{ fontSize: 12 }}>{detail}</span>
      </div>
      <div className="bar lg"><div className={`bar-fill ${cls}`} style={{ width: `${pctV}%` }} /></div>
    </div>
  );
}

function Detail({ k, v, cls = 'dim' }: { k: string; v: string; cls?: string }) {
  return (
    <div className="kv">
      <span className="k">{k}</span>
      <span className={`v ${cls}`}>{v}</span>
    </div>
  );
}

function regimeBars(regime?: EAState['ai']['regime']): { label: string; value: number }[] {
  if (!regime) return [];
  return [
    { label: 'Trend', value: Math.round((regime.trend_prob ?? 0) * 100) },
    { label: 'Range', value: Math.round((regime.range_prob ?? 0) * 100) },
    { label: 'Volatile', value: Math.round((regime.volatile_prob ?? 0) * 100) },
    { label: 'Spike', value: Math.round((regime.spike_prob ?? 0) * 100) },
  ];
}

function groupStrategies(strats: EAState['strategies']): Record<string, EAState['strategies']> {
  const out: Record<string, EAState['strategies']> = {};
  for (const s of strats) (out[s.symbol] ??= []).push(s);
  return out;
}

/* =====================================================================
   LOGS PANEL
   ===================================================================== */
function LogsPanel({ logs }: { logs: LogEntry[] }) {
  const [tag, setTag] = useState('ALL');
  const [lvl, setLvl] = useState('ALL');
  const [q, setQ] = useState('');
  const [auto, setAuto] = useState(true);
  const [open, setOpen] = useState<number | null>(null);
  const ref = useRef<HTMLDivElement>(null);

  const tags = useMemo(() => ['ALL', ...Array.from(new Set(logs.map((l) => l.tag))).sort()], [logs]);
  const filtered = useMemo(() => logs.filter((l) => {
    const level = l.fields.level || l.raw.split(' ')[1]?.replace(/[\[\]]/g, '');
    if (tag !== 'ALL' && l.tag !== tag) return false;
    if (lvl !== 'ALL' && level !== lvl) return false;
    if (q && !l.raw.toLowerCase().includes(q.toLowerCase())) return false;
    return true;
  }), [logs, tag, lvl, q]);

  useEffect(() => {
    if (auto && ref.current) ref.current.scrollTop = ref.current.scrollHeight;
  }, [filtered.length, auto]);

  const levelClass = (l: LogEntry) => {
    const level = (l.fields.level || l.raw.split(' ')[1]?.replace(/[\[\]]/g, '') || 'INFO') as string;
    return `lvl-${level}`;
  };

  return (
    <div>
      <div className="toolbar">
        <select className="select" style={{ width: 190 }} value={tag} onChange={(e) => setTag(e.target.value)}>
          {tags.map((t) => <option key={t} value={t}>{t}</option>)}
        </select>
        <select className="select" style={{ width: 140 }} value={lvl} onChange={(e) => setLvl(e.target.value)}>
          {['ALL', 'ERROR', 'WARNING', 'INFO', 'DEBUG', 'CRITICAL'].map((l) => <option key={l} value={l}>{l}</option>)}
        </select>
        <div className="grow" style={{ position: 'relative' }}>
          <input className="input" placeholder="Search logs…" value={q} onChange={(e) => setQ(e.target.value)} />
        </div>
        <span className="muted mono" style={{ fontSize: 12 }}>{filtered.length} / {logs.length}</span>
        <label className="row" style={{ gap: 6, fontSize: 12, color: 'var(--text-2)', cursor: 'pointer' }}>
          <input type="checkbox" checked={auto} onChange={(e) => setAuto(e.target.checked)} /> Auto-scroll
        </label>
        <button className="btn ghost sm" onClick={() => { setQ(''); setTag('ALL'); setLvl('ALL'); }}>Clear</button>
      </div>

      <div className="logfeed" ref={ref}>
        {filtered.length === 0 ? (
          <div className="empty"><div className="em">No log entries</div>Adjust filters or wait for logs.</div>
        ) : filtered.map((entry, i) => {
          const level = (entry.fields.level || entry.raw.split(' ')[1]?.replace(/[\[\]]/g, '') || 'INFO') as string;
        const symbol = entry.fields.symbol as string | undefined;
        const event = (entry.fields.event_type || entry.fields.eventType) as string | undefined;
          const isOpen = open === i;
          return (
            <div key={`${entry.timestamp}-${i}`} className={`logrow ${isOpen ? 'open' : ''}`} onClick={() => setOpen(isOpen ? null : i)}>
              <div className="log-line1">
                <span className="log-time">{fmtTime(entry.timestamp)}</span>
                <span className="tag">{entry.tag}</span>
                <span className={levelClass(entry)} style={{ fontSize: 10.5, fontFamily: 'var(--font-mono)' }}>{level}</span>
                {symbol && <span className="tag accent">{symbol}</span>}
                {event && <span className="tag">{event}</span>}
                <span className="muted" style={{ fontSize: 10, marginLeft: 'auto' }}>#{i + 1}</span>
              </div>
              <div className="log-msg">{entry.raw}</div>
              {isOpen && (
                <div className="log-json">
                  <pre>{JSON.stringify(entry.fields, null, 2)}</pre>
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

/* =====================================================================
   CONTROL PANEL
   ===================================================================== */
function ControlPanel({ mode, isConnected, sendCommand }: {
  mode: string; isConnected: boolean; sendCommand: (c: string, p?: Record<string, unknown>) => void;
}) {
  const [param, setParam] = useState('');
  const [val, setVal] = useState('');
  const [confirmStop, setConfirmStop] = useState(false);
  const [fb, setFb] = useState('');

  const note = (m: string) => { setFb(m); setTimeout(() => setFb(''), 3000); };

  if (!isConnected) return <div className="empty"><div className="em">Disconnected</div>Connect to the EA to use controls.</div>;

  return (
    <div className="grid cols-2">
      <div className="card">
        <div className="divider-label">Execution Mode</div>
        <div className="seg" style={{ marginTop: 6 }}>
          <button className={mode === 'SHADOW' ? 'sel' : ''} onClick={() => { sendCommand('set_mode', { mode: 'SHADOW' }); note('Switching to SHADOW'); }}>Shadow</button>
          <button className={mode === 'LIVE' ? 'sel' : ''} onClick={() => { sendCommand('set_mode', { mode: 'LIVE' }); note('Switching to LIVE'); }}>Live</button>
          <button className={mode === 'OFF' ? 'sel' : ''} onClick={() => { sendCommand('set_mode', { mode: 'OFF' }); note('Switching to OFF'); }}>Off</button>
        </div>
        <div className="note" style={{ marginTop: 10 }}>Current mode: <span className="strong">{mode}</span></div>
      </div>

      <div className="card">
        <div className="divider-label">Emergency Stop</div>
        <p className="note" style={{ margin: '8px 0 12px' }}>Immediately halt all trading and close open positions.</p>
        {!confirmStop ? (
          <button className="btn danger" onClick={() => setConfirmStop(true)}>EMERGENCY STOP</button>
        ) : (
          <div className="row">
            <button className="btn danger" onClick={() => { sendCommand('emergency_stop'); setConfirmStop(false); note('Emergency stop activated'); }}>CONFIRM STOP</button>
            <button className="btn" onClick={() => setConfirmStop(false)}>Cancel</button>
          </div>
        )}
      </div>

      <div className="card">
        <div className="divider-label">Parameter Editor</div>
        <div className="row" style={{ marginTop: 8, gap: 8 }}>
          <input className="input" placeholder="Parameter name" value={param} onChange={(e) => setParam(e.target.value)} />
          <input className="input" placeholder="Value" value={val} onChange={(e) => setVal(e.target.value)} />
          <button className="btn primary" onClick={() => {
            if (param && val) { sendCommand('set_param', { name: param, value: val }); note(`Set ${param} = ${val}`); setParam(''); setVal(''); }
          }}>Apply</button>
        </div>
      </div>

      <div className="card">
        <div className="divider-label">Status</div>
        <p className="note" style={{ marginTop: 8 }}>{fb ? <span className="accent">{fb}</span> : 'Ready'}</p>
      </div>
    </div>
  );
}
