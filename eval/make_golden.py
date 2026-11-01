#!/usr/bin/env python3
"""Regenerates Tests/WritingCoreTests/Fixtures/python_golden.json, which pins the Swift
prompt renderer and output guard to this harness (eval/bench.py).

Usage: python eval/make_golden.py results/*.json   (bench.py --out reports with real model outputs)
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bench  # noqa: E402

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Packages", "WriterKit", "Tests",
                   "WritingCoreTests", "Fixtures", "python_golden.json")

p = bench.load_prompts(bench.DEFAULT_PROMPTS)
renders = []
for action in ["fix", "professional", "ask", "to_english"]:
    for fmt in ["chatml", "lfm3"]:
        for text in ["i dont know", 'Café 🙂 "quoted"\nnew line']:
            renders.append({"action": action, "format": fmt, "text": text,
                            "full": bench.render(p, fmt, bench.build_messages(p, action, text))})

pairs = []
for path in sys.argv[1:]:
    for row in json.load(open(path, encoding="utf-8"))["cases"]["rows"]:
        pairs.append((row["input"], row["output"]))
pairs += [("u r gr8", "you are great"), ("", ""), ("Hello", ""), ("ok", "OK."),
          ("Teh meeting is at 3pm.", "The meeting is at 3pm."),
          ("I want to come to.", "I want to come to Café Luna."),
          ("I has 2 kid", "I have 2 kids."),
          ("He have a dog.", "He has a dog."),
          ("He do it.", "He does it."),
          ("I were late.", "I was late."),
          ("I have 2 kids.", "I had 2 kids."),
          ("I have a cat.", "I have a dog."),
          ("I has 2 kid", "Kids are great!"),
          ("I was bored with this movie.", "I was bored with this movie.")]
seen, guards = set(), []
for s, o in pairs:
    if (s, o) in seen:
        continue
    seen.add((s, o))
    ok, why = bench.guard(p, "fix", s, o)
    guards.append({"source": s, "output": o, "accepted": ok, "reason": why,
                   "similarity": round(bench.similarity(s, o), 6), "retention": round(bench.word_retention(s, o), 6)})
json.dump({"renders": renders, "guards": guards}, open(OUT, "w", encoding="utf-8"), indent=1, ensure_ascii=False)
print(f"{len(renders)} renders, {len(guards)} guard cases ({sum(g['accepted'] for g in guards)} accepted)")
