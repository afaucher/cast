"""Per-clip comparison of two stagger_bench runs (e.g. gate flush off vs on) for grammar tuning.

    python tools/stt_stagger/compare.py results/tune-old-x4.csv results/tune-new-x4.csv

Prints, per group: casts of the expected spell, wrong/false fires, mean power, accidental labels and
the trigger->spell gap; then every clip whose outcome, label or power changed (|dpower| >= 0.05).
"""
import csv
import statistics
import sys
from collections import defaultdict


def load(path):
    out = {}
    for r in csv.DictReader(open(path, newline="", encoding="utf-8")):
        if r["stream"] == "0":
            out[(r["clip"], r["phase_ms"])] = r
    return out


def outcome(r):
    exp = r["expect"]
    spell = r["spell"]
    if spell == "-":
        return "none" if exp in ("none", "any") else "MISS"
    if exp == "none":
        return "FALSE"
    if exp != "any" and spell != exp:
        return "WRONG"
    return "cast"


def summary(rows, label):
    by = defaultdict(list)
    for r in rows.values():
        by[r["group"]].append(r)
    print(f"== {label}")
    for g, rr in sorted(by.items()):
        oc = defaultdict(int)
        for r in rr:
            oc[outcome(r)] += 1
        casts = [r for r in rr if r["spell"] != "-"]
        pw = [float(r["power"]) for r in casts]
        acc = sum(1 for r in casts if r["accidental"] == "1")
        gaps = [float(r["gap"]) for r in casts if r["gap"]]
        lat = [float(r["game_lat"]) for r in casts if r["game_lat"] and float(r["game_lat"]) >= 0]
        print(f"  {g:<9} n {len(rr):3d}  {dict(oc)}  power {statistics.mean(pw) if pw else 0:.3f}  accidental {acc}/{len(casts)}"
              f"  gap p50 {statistics.median(gaps) if gaps else 0:.2f} max {max(gaps) if gaps else 0:.2f}"
              f"  game latency p50 {statistics.median(lat) if lat else 0:.0f} ms")


def main(a, b):
    A, B = load(a), load(b)
    summary(A, a)
    summary(B, b)
    print("== changed clips (old -> new)")
    for k in sorted(A):
        if k not in B:
            continue
        ra, rb = A[k], B[k]
        pa, pb = float(ra["power"]), float(rb["power"])
        if (outcome(ra) != outcome(rb) or ra["spell"] != rb["spell"] or ra["accidental"] != rb["accidental"]
                or abs(pa - pb) >= 0.05):
            print(f"  {k[0]:<44} {ra['spell']:>9} {pa:.2f} acc{ra['accidental'] or '-'} gap {ra['gap'] or '-':>5} "
                  f"-> {rb['spell']:>9} {pb:.2f} acc{rb['accidental'] or '-'} gap {rb['gap'] or '-':>5}   "
                  f"[{ra['final_text']}] -> [{rb['final_text']}]")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
