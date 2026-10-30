#!/usr/bin/env python3
"""Downloads the JFLEG test split (Napoles et al., 2017) from the Hugging Face datasets server.
JFLEG is CC BY-NC-SA 4.0, so it is fetched at evaluation time instead of being committed.

Usage: python eval/fetch_jfleg.py eval/data/jfleg_test.json
"""
import json
import os
import sys
import urllib.request

URL = "https://datasets-server.huggingface.co/rows?dataset=jhu-clsp/jfleg&config=default&split=test&offset={}&length=100"


def main(out):
    if os.path.exists(out):
        print(f"{out}: cached")
        return
    rows = []
    while True:
        with urllib.request.urlopen(URL.format(len(rows)), timeout=60) as resp:
            page = [r["row"] for r in json.load(resp)["rows"]]
        rows += page
        if len(page) < 100:
            break
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    with open(out, "w", encoding="utf-8") as f:
        json.dump(rows, f, ensure_ascii=False)
    print(f"{out}: {len(rows)} sentences")


if __name__ == "__main__":
    main(sys.argv[1])
