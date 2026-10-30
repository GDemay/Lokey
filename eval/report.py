#!/usr/bin/env python3
"""Summarizes bench.py --out reports as a Markdown table.

Usage: python eval/report.py results/*.json
"""
import json
import sys


def main(paths):
    rows = []
    for path in paths:
        try:
            r = json.load(open(path, encoding="utf-8"))
        except (OSError, ValueError):
            continue
        if "cases" not in r:
            continue
        c, j = r["cases"], r.get("jfleg", {})
        rows.append((r["model"], r.get("size_mb", 0), c.get("guarded_ok", c["lenient"]), c.get("harmful_after_guard", "-"),
                     c.get("guard_rejections", "-"), c["mean_total_ms"], c["p90_total_ms"],
                     j.get("gleu", "-"), j.get("gleu_source_baseline", "-"), c["by_cat"]))
    rows.sort(key=lambda x: -x[2])
    print("| Model | Size (MB) | Keyboard cases correct | Harmful | Guard rejections | Mean ms | p90 ms | JFLEG GLEU | (no-edit baseline) |")
    print("|---|---|---|---|---|---|---|---|---|")
    for m, size, acc, harm, rej, mean, p90, gleu, base, _ in rows:
        print(f"| {m} | {size} | {acc:.1%} | {harm} | {rej} | {mean} | {p90} | {gleu} | {base} |")
    if rows:
        cats = sorted(rows[0][9])
        print()
        print("| Model | " + " | ".join(cats) + " |")
        print("|---|" + "---|" * len(cats))
        for r in rows:
            print(f"| {r[0]} | " + " | ".join(f"{r[9].get(k, 0):.0%}" for k in cats) + " |")


if __name__ == "__main__":
    main(sys.argv[1:])
