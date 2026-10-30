# Benchmark: English correction with local LFM models

All numbers below are **measured**. Reproduce with `eval/bench.py` (Python, llama.cpp) or the Swift
integration test `LlamaRuntimeTests.testEvalCases` (the app's exact pipeline). CI re-runs the
Python harness on official llama.cpp binaries for every model, including LFM3, on prompt or catalog
changes (`.github/workflows/eval.yml`).

**Setup**
- Prompts and output guard: `Packages/WriterKit/Sources/WritingCore/Resources/prompts.json`
  (the file the app ships). Greedy decoding, Q4_0 QAD weights.
- Hardware: 4-thread x86-64 Linux VM (not an iPhone; use these for relative comparison).
- **Keyboard cases**: `eval/keyboard_cases.jsonl`, 70 cases in 10 categories. A case counts as
  correct if what the user would see (the model output, or the original text if the guard rejected
  the output) matches an accepted answer. "Harmful" = the user would see an edit that is neither an
  accepted answer nor close to their own text.
- **JFLEG**: first 150 sentences of the test split, corpus GLEU averaged over the 4 references
  (no-edit baseline 35.9; published human references score ~62).

## Apple Silicon (CI, macOS runner CPU, keyboard memory profile)

Measured by the `ios` CI workflow on a GitHub macOS arm64 runner (Apple M-series CPU, the same core
family as recent iPhones), running the app's exact Swift pipeline CPU-only with the keyboard profile.

| Model | Keyboard cases correct | Harmful | Mean / p90 per sentence | Prompt prefill cold → cached | `phys_footprint` (keyboard profile) |
|---|---|---|---|---|---|
| LFM2.5-1.2B-Instruct (default) | **77.1%** | 0 | **483 / 603 ms** | 2.07 s → 0.14 s | **37.5 MB** |
| LFM2.5-350M | — | — | — | — | **35.3 MB** |

`phys_footprint` is what iOS compares against the keyboard extension's memory limit (~48–77 MB
reported). It was ~70 MB before the keyboard profile stopped llama.cpp from creating a Metal device
and compiling its shader library (`GGML_METAL_DEVICES=0`); the weights themselves are memory-mapped
and never counted.

## App pipeline (Swift, keyboard memory profile, prompt-state snapshots, x86 VM)

| Model | File | Keyboard cases correct | Harmful | Mean / p90 per sentence | Prompt prefill cold → cached | Keyboard footprint (anon.) |
|---|---|---|---|---|---|---|
| LFM2.5-1.2B-Instruct (default) | 696 MB | **77.1%** | 0 | 1025 / 1298 ms | 5.33 s → 0.41 s | 43.9 MB |
| LFM2.5-350M | 219 MB | 60.0% | 0 | 437 / 563 ms | 1.89 s → 0.12 s | 42.1 MB |
| LFM2.5-230M | 149 MB | 47.1% | 0 | 348 / 462 ms | 1.32 s → 0.07 s | 40.9 MB |

Prefill is for the 318-token fix prompt, 298 tokens of which are restored from a state snapshot;
cached and uncached runs give identical greedy outputs. The footprint is anonymous memory for the
whole inference stack in the keyboard profile (model memory-mapped, CPU only, no weight repacking).
It does not grow with the model file. The default app profile (2048 context, 512 batches) uses 89 MB
for the 1.2B model.

## Python harness (same prompts and guard, no prompt reuse)

| Model | Size (MB) | Keyboard cases correct | Harmful | Guard rejections | Mean ms | p90 ms | JFLEG GLEU | (no-edit baseline) |
|---|---|---|---|---|---|---|---|---|
| LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf | 696 | 77.1% | 0 | 8 | 2356 | 2771 | 53.71 | 35.94 |
| LFM2.5-350M-QAD-Q4_0.gguf | 219 | 58.6% | 0 | 3 | 689 | 831 | 42.6 | 35.94 |
| LFM2.5-230M-QAD-Q4_0.gguf | 149 | 45.7% | 0 | 6 | 383 | 438 | 39.94 | 35.94 |

| Model | apostrophe-case | esl | grammar | homophone | informal | instruction | long | preserve | punctuation | typo |
|---|---|---|---|---|---|---|---|---|---|---|
| LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf | 100% | 56% | 80% | 67% | 67% | 50% | 50% | 90% | 100% | 80% |
| LFM2.5-350M-QAD-Q4_0.gguf | 71% | 56% | 70% | 44% | 67% | 50% | 50% | 90% | 25% | 40% |
| LFM2.5-230M-QAD-Q4_0.gguf | 71% | 11% | 50% | 44% | 67% | 17% | 50% | 100% | 0% | 30% |

Latency in this table re-evaluates the whole prompt for every request (llama-cpp-python cannot reuse
a prefix with LFM's hybrid memory); the app does not (see above).

## Prompt engineering (LFM2.5-350M, keyboard cases)

| Prompt | Correct |
|---|---|
| System instruction only | 37.1% |
| + 3 few-shot examples | 41.4% |
| + text wrapped in `<text>` tags | 57.1% |
| + examples of questions/commands being corrected, not answered (shipping) | 57.1% (and 0 harmful with the guard) |

## Known weaknesses

- Small models under-correct: "over their" → unchanged, "Me and him went" → unchanged.
- ESL constructions ("I have 25 years old", "We discussed about") are the weakest category (56% for 1.2B).
- Rare meaning changes the guard cannot detect: "We need to seperate…" → "I need to separate…" (1.2B).
- The 230M model is not useful for grammar, only capitalization and simple typos.
