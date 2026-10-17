"""Summarize stagger_bench.gd CSVs (tools/stt_stagger/results/*.csv).

    python tools/stt_stagger/analyze.py tools/stt_stagger/results/n1-p12-clean+rate.csv [more.csv ...]

For each file: per-stream and merged latency (median / p90 over casts of the right spell),
accuracy, and the split of the latency into "audio wait" (voice end -> the stream reached the
decode point that produced the cast) and "compute + poll" (decode point -> cast seen on the
main thread). For a one-stream phase sweep it also simulates N = 2 and N = 3 staggered streams
by taking, per clip, the earliest correct cast among phases 320/N ms apart (no CPU contention).
"""
import csv
import statistics
import sys
from collections import defaultdict


def pct(v, q):
    if not v:
        return float("nan")
    v = sorted(v)
    return v[min(len(v) - 1, int(q * (len(v) - 1) + 0.5))]


def fmt(v):
    return f"{statistics.median(v):5.0f} / {pct(v, 0.9):5.0f} / {statistics.mean(v):5.0f}" if v else "   -"


def summarize(rows, label):
    lat = [float(r["lat_ms"]) for r in rows if r["status"] in ("ok", "MULTI", "CONFLICT") and r["lat_ms"]]
    n = len(rows)
    st = defaultdict(int)
    for r in rows:
        st[r["status"]] += 1
    ok = st["ok"]
    extra = ", ".join(f"{k} {v}" for k, v in sorted(st.items()) if k != "ok")
    print(f"  {label:<22} n {n:4d}  correct {100.0 * (n - st['MISS'] - st['WRONG']) / max(n, 1):5.1f}%  "
          f"clean-ok {100.0 * ok / max(n, 1):5.1f}%  latency p50/p90/mean {fmt(lat)} ms  {extra}")
    return lat


def main(paths):
    for path in paths:
        with open(path, newline="", encoding="utf-8") as f:
            rows = list(csv.DictReader(f))
        if not rows:
            continue
        n = int(rows[0]["n"])
        print(f"\n== {path}  (streams {n}, flush {rows[0]['flush']} ms)")
        streams = sorted({int(r["stream"]) for r in rows})
        for s in streams:
            sr = [r for r in rows if int(r["stream"]) == s]
            summarize(sr, "merged" if s < 0 else f"stream {s}")
            if s >= 0:
                good = [r for r in sr if r["status"] in ("ok", "MULTI") and r["ready_ms"]]
                ready = [float(r["ready_ms"]) for r in good]
                comp = [float(r["compute_ms"]) for r in good]
                if good:
                    print(f"      audio wait p50/p90/mean {fmt(ready)} ms; compute+poll {fmt(comp)} ms")
        # per group, merged (or the only stream)
        key = -1 if -1 in streams else 0
        for g in sorted({r["group"] for r in rows}):
            summarize([r for r in rows if int(r["stream"]) == key and r["group"] == g], f"  group {g}")
        # per phase accuracy of stream 0 (does the chunk alignment change what is heard?)
        by_phase = defaultdict(list)
        for r in rows:
            if int(r["stream"]) >= 0:
                by_phase[float(r["phase_ms"]) + float(r["offset_ms"])].append(r)
        if len(by_phase) > 1:
            print("    per effective phase (all streams): phase  correct%  p50 latency")
            for ph in sorted(by_phase):
                rr = by_phase[ph]
                bad = sum(1 for r in rr if r["status"] in ("MISS", "WRONG"))
                lat = [float(r["lat_ms"]) for r in rr if r["status"] in ("ok", "MULTI") and r["lat_ms"]]
                print(f"      {ph:6.1f}  {100.0 * (len(rr) - bad) / len(rr):5.1f}  {statistics.median(lat) if lat else float('nan'):6.0f}")
        # clips whose result depends on the phase
        by_clip = defaultdict(dict)
        for r in rows:
            if int(r["stream"]) >= 0:
                by_clip[r["clip"]][float(r["phase_ms"]) + float(r["offset_ms"])] = r
        flips = [(c, d) for c, d in by_clip.items() if len({r["status"] in ("MISS", "WRONG") for r in d.values()}) > 1]
        if flips:
            print(f"    clips whose outcome depends on the phase: {len(flips)}")
            for c, d in flips:
                outs = " ".join(f"{ph:.0f}:{r['spell'] if r['status'] not in ('MISS',) else '-'}" for ph, r in sorted(d.items()))
                print(f"      {c}: {outs}")
        if n == 1 and len(by_phase) > 1:
            simulate(by_clip, sorted(by_phase))


def simulate(by_clip, phases):
    """Earliest correct cast among phases 320/N apart, per clip and base phase (ideal, no contention)."""
    P = len(phases)
    print("    simulated stagger from the one-stream sweep (first correct cast wins; wrong casts count as a race loss):")
    for N in (1, 2, 3, 4):
        if P % N:
            continue
        stride = P // N
        lat, wrong_first, miss = [], 0, 0
        total = 0
        for clip, d in by_clip.items():
            ph = sorted(d)
            for b in range(stride):
                group = [d[ph[(b + i * stride) % P]] for i in range(N)]
                total += 1
                casts = [r for r in group if r["lat_ms"]]
                if not casts:
                    miss += 1
                    continue
                first = min(casts, key=lambda r: float(r["lat_ms"]))
                if first["spell"] != first["expect"]:
                    wrong_first += 1
                    continue
                lat.append(float(first["lat_ms"]))
        print(f"      N={N}: casts {len(lat)}/{total}, wrong-first {wrong_first}, miss {miss}, latency p50/p90/mean {fmt(lat)} ms")


if __name__ == "__main__":
    main(sys.argv[1:])
