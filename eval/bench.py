#!/usr/bin/env python3
"""Benchmark local GGUF models on English correction, the way the keyboard runs them.

Uses the same prompt definitions as the app (Packages/WriterKit/.../Resources/prompts.json), greedy
decoding, and KV-cache prefix reuse across requests (the system prompt + few-shot
examples are evaluated once, like on device).

Usage:
  python eval/bench.py --model path/to/model.gguf --format chatml \
      --cases eval/keyboard_cases.jsonl [--jfleg eval/data/jfleg_test.json --jfleg-n 200] \
      [--variant fix] --out results.json
"""
import argparse
import difflib
import json
import math
import os
import re
import sys
import time
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PROMPTS = os.path.join(HERE, "..", "Packages", "WriterKit", "Sources", "WritingCore", "Resources", "prompts.json")


# ---------------------------------------------------------------- prompt building
def load_prompts(path):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def build_messages(prompts, action, text):
    a = prompts["actions"][action]
    msgs = [{"role": "system", "content": a["system"]}]
    for ex in a.get("examples", []):
        msgs.append({"role": "user", "content": a["userTemplate"].replace("{text}", ex["input"])})
        msgs.append({"role": "assistant", "content": ex["output"]})
    msgs.append({"role": "user", "content": a["userTemplate"].replace("{text}", text)})
    return msgs


def render(prompts, fmt, messages):
    """Render a chat with the model family's template (BOS is added by the tokenizer)."""
    f = prompts["formats"][fmt]
    out = []
    for m in messages:
        body = m["content"]
        if m["role"] == "assistant":
            body = f.get("assistantHistoryPrefix", "") + body
        out.append(f["turnStart"] + m["role"] + "\n" + body + f["turnEnd"])
    out.append(f["turnStart"] + "assistant\n" + f.get("generationPrefix", ""))
    return "".join(out)


def clean_output(prompts, fmt, text):
    f = prompts["formats"][fmt]
    if "</think>" in text:  # the reply follows the last </think>, as in LFM3's chat template
        text = text.rsplit("</think>", 1)[1]
    for tok in f.get("stripTokens", []):
        text = text.replace(tok, "")
    text = text.strip()
    if text.startswith("<text>") and text.endswith("</text>"):
        text = text[len("<text>"):-len("</text>")].strip()
    return text


def osa_distance(a, b):
    """Optimal string alignment distance (Levenshtein + adjacent transpositions). Mirrors Similarity.swift."""
    n, m = len(a), len(b)
    if n == 0 or m == 0:
        return max(n, m)
    prev2, prev = None, list(range(m + 1))
    for i in range(1, n + 1):
        cur = [i] + [0] * m
        for j in range(1, m + 1):
            cost = 0 if a[i - 1] == b[j - 1] else 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
            if i > 1 and j > 1 and a[i - 1] == b[j - 2] and a[i - 2] == b[j - 1]:
                cur[j] = min(cur[j], prev2[j - 2] + 1)
        prev2, prev = prev, cur
    return prev[m]


def similarity(a, b):
    a, b = a.lower(), b.lower()
    if not a and not b:
        return 1.0
    if len(a) * len(b) > 4_000_000:  # keep it cheap on very long texts: compare words instead
        a, b = words(a), words(b)
    return 1.0 - osa_distance(a, b) / max(len(a), len(b))


WORD_RE = re.compile(r"[^\W_]+", re.UNICODE)


def words(s):
    return WORD_RE.findall(s.lower().replace("'", "").replace("’", ""))


def word_retention(source, output):
    src = {w for w in words(source) if len(w) >= 3}
    if not src:
        return 1.0
    out = set(words(output))
    kept = sum(1 for w in src if w in out or any(1.0 - osa_distance(w, o) / max(len(w), len(o)) >= 0.6 for o in out))
    return kept / len(src)


def leaked_words(prompts, action, source, output):
    """New output words (4+ letters) copied from the prompt's few-shot examples. Mirrors Similarity.leakedWords."""
    ex = {w for e in prompts["actions"][action].get("examples", []) for w in words(e["input"] + " " + e["output"]) if len(w) >= 4}
    if not ex:
        return []
    src = set(words(source))
    leaked = []
    for w in set(words(output)):
        if len(w) >= 4 and w in ex and not any(1.0 - osa_distance(w, s) / max(len(w), len(s)) >= 0.6 for s in src):
            leaked.append(w)
    return sorted(leaked)


def guard(prompts, action, source, output):
    """Mirror of OutputGuard.swift: reject outputs that look like an answer, not an edit."""
    g = prompts["guards"][prompts["actions"][action].get("guard", "strict")]
    if not output.strip():
        return False, "empty"
    ratio = len(output) / max(1, len(source))
    if ratio < g["minLengthRatio"] or ratio > g["maxLengthRatio"]:
        return False, "length"
    if not g["allowNewLines"] and output.count("\n") > source.count("\n"):
        return False, "newlines"
    if g["rejectAssistantOpeners"]:
        o, s = output.strip().lower().replace("’", "'"), source.strip().lower().replace("’", "'")
        for opener in prompts.get("assistantOpeners", []):
            if o.startswith(opener) and not s.startswith(opener):
                return False, "opener"
    if similarity(source, output) < g["minSimilarity"]:
        return False, "similarity"
    if word_retention(source, output) < g["minWordRetention"]:
        return False, "retention"
    if g["minWordRetention"] > 0 and leaked_words(prompts, action, source, output):
        return False, "leakage"
    return True, ""


# ---------------------------------------------------------------- metrics
def norm(s):
    s = s.replace("’", "'").replace("‘", "'").replace("“", '"').replace("”", '"')
    return re.sub(r"\s+", " ", s).strip()


TOK_RE = re.compile(r"\w+|[^\w\s]", re.UNICODE)


def toks(s):
    return TOK_RE.findall(norm(s))


def ngrams(seq, n):
    return Counter(tuple(seq[i:i + n]) for i in range(len(seq) - n + 1))


def corpus_gleu(sources, hyps, refsets, order=4):
    """GLEU (Napoles et al. 2016), averaged over reference index instead of random sampling."""
    nrefs = min(len(r) for r in refsets)
    scores = []
    for j in range(nrefs):
        num = [0] * order
        den = [0] * order
        hlen = rlen = 0
        for s, h, refs in zip(sources, hyps, refsets):
            s, h, r = toks(s), toks(h), toks(refs[j])
            hlen += len(h)
            rlen += len(r)
            for n in range(1, order + 1):
                hn, sn, rn = ngrams(h, n), ngrams(s, n), ngrams(r, n)
                match = sum((hn & rn).values())
                penalty = sum(((hn & sn) - rn).values())
                num[n - 1] += max(match - penalty, 0)
                den[n - 1] += max(len(h) - n + 1, 0)
        if min(num) == 0 or hlen == 0:
            scores.append(0.0)
            continue
        bp = 1.0 if hlen > rlen else math.exp(1 - rlen / hlen)
        scores.append(bp * math.exp(sum(math.log(num[i] / den[i]) for i in range(order)) / order))
    return 100 * sum(scores) / len(scores)


def detok(s):
    s = re.sub(r"\s+([.,!?;:%)\]}])", r"\1", s)
    s = re.sub(r"([(\[{$])\s+", r"\1", s)
    s = re.sub(r"\s+(n't|'s|'re|'ve|'ll|'d|'m)\b", r"\1", s)
    s = s.replace("`` ", '"').replace(" ''", '"')
    return s.strip()


# ---------------------------------------------------------------- runner
class Runner:
    def __init__(self, model, fmt, prompts, threads, ctx):
        from llama_cpp import Llama
        t0 = time.time()
        self.llm = Llama(model_path=model, n_ctx=ctx, n_threads=threads, n_threads_batch=threads,
                         n_batch=512, verbose=False, use_mmap=True)
        self.load_s = time.time() - t0
        self.fmt, self.prompts = fmt, prompts

    def correct(self, action, text):
        prompt = render(self.prompts, self.fmt, build_messages(self.prompts, action, text))
        ids = self.llm.tokenize(prompt.encode("utf-8"), add_bos=True, special=True)
        in_toks = len(self.llm.tokenize(text.encode("utf-8"), add_bos=False, special=False))
        max_new = int(in_toks * 1.6) + 24
        stop = self.prompts["formats"][self.fmt]["stop"]
        t0 = time.time()
        ttft = None
        out = []
        n = 0
        for chunk in self.llm.create_completion(ids, max_tokens=max_new, temperature=0.0, top_k=1,
                                                repeat_penalty=1.0, stop=stop, stream=True):
            if ttft is None:
                ttft = time.time() - t0
            out.append(chunk["choices"][0]["text"])
            n += 1
        total = time.time() - t0
        return {
            "output": clean_output(self.prompts, self.fmt, "".join(out)),
            "raw": "".join(out),
            "prompt_tokens": len(ids),
            "gen_tokens": n,
            "ttft_s": ttft or total,
            "total_s": total,
        }


class ServerRunner:
    """Same protocol as Runner, against a llama.cpp `llama-server` (any llama.cpp build)."""

    def __init__(self, url, fmt, prompts):
        self.url, self.fmt, self.prompts, self.load_s = url.rstrip("/"), fmt, prompts, 0.0

    def _post(self, path, payload):
        import urllib.request
        req = urllib.request.Request(self.url + path, data=json.dumps(payload).encode(),
                                     headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=600) as resp:
            return json.loads(resp.read())

    def correct(self, action, text):
        prompt = render(self.prompts, self.fmt, build_messages(self.prompts, action, text))
        in_toks = len(self._post("/tokenize", {"content": text})["tokens"])
        t0 = time.time()
        res = self._post("/completion", {
            "prompt": prompt, "n_predict": int(in_toks * 1.6) + 24, "temperature": 0.0, "top_k": 1,
            "repeat_penalty": 1.0, "stop": self.prompts["formats"][self.fmt]["stop"], "cache_prompt": True,
            "special": True,
        })
        total = time.time() - t0
        t = res.get("timings", {})
        return {
            "output": clean_output(self.prompts, self.fmt, res["content"]),
            "raw": res["content"],
            "prompt_tokens": res.get("tokens_evaluated", 0),
            "gen_tokens": t.get("predicted_n", 0),
            "ttft_s": t.get("prompt_ms", 0) / 1000.0,
            "total_s": total,
        }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True, help="GGUF path (also used as the report label with --server)")
    ap.add_argument("--server", help="llama-server base URL; use it instead of llama-cpp-python")
    ap.add_argument("--format", required=True)
    ap.add_argument("--prompts", default=DEFAULT_PROMPTS)
    ap.add_argument("--action", default="fix")
    ap.add_argument("--cases", default=os.path.join(HERE, "keyboard_cases.jsonl"))
    ap.add_argument("--jfleg")
    ap.add_argument("--jfleg-n", type=int, default=200)
    ap.add_argument("--threads", type=int, default=4)
    ap.add_argument("--ctx", type=int, default=2048)
    ap.add_argument("--out")
    args = ap.parse_args()

    prompts = load_prompts(args.prompts)
    if args.server:
        r = ServerRunner(args.server, args.format, prompts)
    else:
        r = Runner(args.model, args.format, prompts, args.threads, args.ctx)
    # Warm-up: evaluates the shared prefix once, like the keyboard does at launch.
    r.correct(args.action, "warm up")

    size = os.path.getsize(args.model) if os.path.exists(args.model) else 0
    report = {"model": os.path.basename(args.model), "format": args.format, "action": args.action,
              "load_s": round(r.load_s, 3), "size_mb": round(size / 1e6)}

    cases = [json.loads(l) for l in open(args.cases, encoding="utf-8") if l.strip()]
    rows = []
    for c in cases:
        res = r.correct(args.action, c["input"])
        ok, reason = guard(prompts, args.action, c["input"], res["output"])
        # What the user sees: a rejected output means "no suggestion" (text stays as typed).
        shown = res["output"] if ok else c["input"]
        accept = [norm(a) for a in c["accept"]]
        out = norm(res["output"])
        strict = out in accept
        lenient = strict or out.rstrip(".") in [a.rstrip(".") for a in accept]
        sim = max(difflib.SequenceMatcher(None, out, a).ratio() for a in accept)
        guarded_ok = norm(shown).rstrip(".") in [a.rstrip(".") for a in accept]
        harmful = norm(shown) != norm(c["input"]) and not guarded_ok and \
            difflib.SequenceMatcher(None, norm(shown), norm(c["input"])).ratio() < 0.75
        rows.append({**c, **res, "strict": strict, "lenient": lenient, "sim": round(sim, 3),
                     "guard_ok": ok, "guard_reason": reason, "guarded_ok": guarded_ok, "harmful": harmful})
        print(f"[{'OK ' if lenient else 'BAD'}{'' if ok else ' G:' + reason}] {c['id']:8s} {res['total_s']*1000:6.0f}ms  "
              f"{c['input'][:50]!r} -> {res['output'][:70]!r}", file=sys.stderr)
    cats = sorted({r_["cat"] for r_ in rows})
    report["cases"] = {
        "n": len(rows),
        "strict": round(sum(r_["strict"] for r_ in rows) / len(rows), 3),
        "lenient": round(sum(r_["lenient"] for r_ in rows) / len(rows), 3),
        "guarded_ok": round(sum(r_["guarded_ok"] for r_ in rows) / len(rows), 3),
        "guard_rejections": sum(not r_["guard_ok"] for r_ in rows),
        "harmful_after_guard": sum(r_["harmful"] for r_ in rows),
        "mean_sim": round(sum(r_["sim"] for r_ in rows) / len(rows), 3),
        "by_cat": {k: round(sum(x["lenient"] for x in rows if x["cat"] == k) / sum(1 for x in rows if x["cat"] == k), 2) for k in cats},
        "mean_total_ms": round(1000 * sum(x["total_s"] for x in rows) / len(rows)),
        "p90_total_ms": round(1000 * sorted(x["total_s"] for x in rows)[int(0.9 * len(rows)) - 1]),
        "mean_ttft_ms": round(1000 * sum(x["ttft_s"] for x in rows) / len(rows)),
        "decode_tok_s": round(sum(x["gen_tokens"] for x in rows) / max(1e-9, sum(x["total_s"] - x["ttft_s"] for x in rows)), 1),
        "rows": rows,
    }

    if args.jfleg:
        data = json.load(open(args.jfleg, encoding="utf-8"))[: args.jfleg_n]
        srcs, hyps, refs, times = [], [], [], []
        for d in data:
            src = detok(d["sentence"])
            res = r.correct(args.action, src)
            srcs.append(src)
            hyps.append(res["output"])
            refs.append([detok(x) for x in d["corrections"]])
            times.append(res["total_s"])
        report["jfleg"] = {
            "n": len(data),
            "gleu": round(corpus_gleu(srcs, hyps, refs), 2),
            "gleu_source_baseline": round(corpus_gleu(srcs, srcs, refs), 2),
            "mean_total_ms": round(1000 * sum(times) / len(times)),
            "samples": [{"src": s, "hyp": h} for s, h in list(zip(srcs, hyps))[:20]],
        }

    summary = {k: v for k, v in report.items() if k not in ("cases", "jfleg")}
    summary.update({f"cases_{k}": v for k, v in report["cases"].items() if k != "rows"})
    if "jfleg" in report:
        summary.update({f"jfleg_{k}": v for k, v in report["jfleg"].items() if k != "samples"})
    print(json.dumps(summary, indent=1))
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump(report, f, indent=1, ensure_ascii=False)


if __name__ == "__main__":
    main()
