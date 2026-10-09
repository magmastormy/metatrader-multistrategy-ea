import collections, time

# Reads an exporter CSV (with header) and reports, per (symbol, strategy):
#   non-zero count, +1 count, -1 count, mean |confidence| of non-zero rows
# This distinguishes "strategy is alive but rare" from "strategy is dead".
path = r"D:/TraeProjects/metatrader-multistrategy-ea/Tools/walkforward/AITraining_Enterprise_H1.csv"
STRATS = ["Momentum", "Trend", "S/R", "Candlestick", "MeanRev", "VolBreak"]
out_path = r"D:/TraeProjects/metatrader-multistrategy-ea/Tools/walkforward/signal_scan.txt"
prog_path = r"D:/TraeProjects/metatrader-multistrategy-ea/Tools/walkforward/signal_scan.progress.txt"

# per (sym, strat): [nonzero, pos, neg, conf_sum]
stats = collections.defaultdict(lambda: [0, 0, 0, 0.0])
total = collections.Counter()
sig_idx = {}

with open(prog_path, "w") as pf:
    pf.write("STARTED\n")

with open(path, "r", encoding="utf-8", errors="replace", newline="") as f:
    header = f.readline().rstrip("\n").rstrip("\r")
    cols = header.split(",")
    max_idx = 0
    for s in STRATS:
        name = s + "_signal"
        if name in cols:
            sig_idx[s] = cols.index(name)
        else:
            for i, c in enumerate(cols):
                if c.endswith("_signal") and c.split("_signal")[0].replace("/", "") == s.replace("/", ""):
                    sig_idx[s] = i
                    break
        max_idx = max(max_idx, sig_idx.get(s, 0))

    with open(prog_path, "w") as pf:
        pf.write("MATCHED: %s  max_idx=%d  total_cols=%d\n" % (sig_idx, max_idx, len(cols)))

    n = 0
    t0 = time.time()
    for line in f:
        n += 1
        if (n & 0x3FFFF) == 0:
            with open(prog_path, "a") as pf:
                pf.write("rows=%d elapsed=%.1fs\n" % (n, time.time() - t0))
        if not line.strip():
            continue
        parts = line.rstrip("\n").rstrip("\r").split(",", max_idx + 2)
        sym = parts[0]
        total[sym] += 1
        for s, idx in sig_idx.items():
            if idx >= len(parts):
                continue
            sig = parts[idx]
            if sig == "0" or sig == "":
                continue
            try:
                v = int(sig)
            except Exception:
                v = 0
            if v == 0:
                continue
            rec = stats[(sym, s)]
            rec[0] += 1
            if v > 0:
                rec[1] += 1
            else:
                rec[2] += 1
            cidx = idx + 1
            if cidx < len(parts):
                try:
                    rec[3] += abs(float(parts[cidx]))
                except Exception:
                    pass

report = []
report.append("MATCHED SIGNAL COLUMNS: " + str(sig_idx))
report.append("TOTAL COLUMNS: %d" % len(cols))
report.append("")
header_row = "symbol,total_rows," + ",".join(
    "%s_nz/%s_pos/%s_neg/%s_avgconf" % (s, s, s, s) for s in STRATS)
report.append(header_row)
for sym in sorted(total):
    row = [sym, str(total[sym])]
    firing = []
    for s in STRATS:
        nz, pos, neg, csum = stats[(sym, s)]
        avg = (csum / nz) if nz else 0.0
        row.append("%d/%d/%d/%.4f" % (nz, pos, neg, avg))
        if nz > 0:
            firing.append(s)
    report.append(",".join(row))
    report.append("   -> %s firing: %s" % (sym, ",".join(firing) if firing else "NONE"))

text = "\n".join(report)
with open(out_path, "w") as o:
    o.write(text)
with open(prog_path, "a") as pf:
    pf.write("DONE\n")
print(text)
