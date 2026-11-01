# Benchmark: English correction with local LFM models

All numbers below are **measured**. Reproduce with `eval/bench.py` (Python, llama.cpp) or the Swift
integration test `LlamaRuntimeTests.testEvalCases` (the app's exact pipeline). CI re-runs the
Python harness on official llama.cpp binaries for every model, including LFM3, on prompt or catalog
changes (`.github/workflows/eval.yml`).

**Setup**
- Prompts and output guard: `Packages/WriterKit/Sources/WritingCore/Resources/prompts.json`
  (the file the app ships). Greedy decoding, Q4_0 QAD weights.
- Hardware: 4-thread x86-64 Linux VM (not an iPhone; use these for relative comparison).
- **Keyboard cases**: `eval/keyboard_cases.jsonl`, originally 70 cases in 10 categories;
  two short agreement cases were added on 2026-11-01. A case counts as
  correct if what the user would see (the model output, or the original text if the guard rejected
  the output) matches an accepted answer. "Harmful" = the user would see an edit that is neither an
  accepted answer nor close to their own text.
- **JFLEG**: first 150 sentences of the test split, corpus GLEU averaged over the 4 references
  (no-edit baseline 35.9; published human references score ~62).

## Keyboard memory: limit, stages and the q8_0 KV cache

**The limit.** iOS kills a keyboard extension the moment its `phys_footprint` (dirty + compressed
anonymous memory; clean memory-mapped file pages such as the model weights are not counted) crosses
a hard per-extension-point limit. Apple publishes no number; jetsam configuration files and kernel
logs give **77 MB on recent iOS** (`ActiveHard 77 MB (fatal)` in iOS 18-era kernel logs, and a
JetsamEvent report on an iPhone 14 Pro running iOS 27), 66 MB on iOS 12–14 and 48 MB on iOS 8, with
no sign of scaling with device RAM. The Simulator enforces none. On a device,
`footprint + os_proc_available_memory()` is the limit; the diagnostics log both.

**What inference adds** (`testKeyboardMemoryFootprint`, now reported by stage; Linux x86 anonymous
memory, a close proxy for the anonymous part of `phys_footprint`). llama.cpp's own buffers at
`n_ctx` 1024: KV cache 12 MB (f16), compute 8.8 MB at 32-token micro-batches (mostly the 65k-vocab
logits it reserves for a full micro-batch), output 0.25 MB. About 20 MB more is the same for every
model size (tokenizer and vocabulary tables) and is live: returning freed heap pages to the system
reclaims under 1 MB.

| Keyboard profile | Model | Load | Prewarm | Request | Total | Keyboard cases (1.2B) |
|---|---|---|---|---|---|---|
| f16 KV, micro-batch 32 (before) | LFM2.5-1.2B | +33.8 MB | +9.4 | +0.8 | **44.0 MB** | 77.1%, 0 harmful, 922 ms mean |
| q8_0 KV, micro-batch 16 (now) | LFM2.5-1.2B | +28.4 MB | +5.9 | +0.8 | **35.1 MB** | 78.6%, 0 harmful, 885 ms mean |
| f16 KV, micro-batch 32 (before) | LFM2.5-350M | +33.7 MB | +7.5 | +0.8 | 42.0 MB | |
| q8_0 KV, micro-batch 16 (now) | LFM2.5-350M | +28.1 MB | +4.9 | +0.8 | 33.9 MB | |

With q8_0 KV one keyboard case changed, from unchanged to correct ("I have lived here for
3 years."). A 512-token context would save another 3 MB but cannot hold the 318-token prompt plus a
400-character chunk and its correction, so the context stays at 1024.

On Apple Silicon (macOS CI, real `phys_footprint`, fresh process) the q8_0 profile adds
**31.5 MB** for LFM2.5-1.2B (load +25.9, prewarm +3.5, request +0.5) and 29.9 MB for the 350M model,
down from 37.1–42.1 MB with f16 KV and 32-token micro-batches.

**The extension itself.** `testKeyboardMemoryFootprint` measures the inference cost on top of a test
process, not the keyboard's footprint. The keyboard logs its own footprint and peak
(`ledger_phys_footprint_peak`) at load, after prewarm and after every request, and shows the peak
in Settings. iOS 26.2 Simulator, Debug build, real system keyboard with Full Access (`test05`):

| Moment | f16 KV, micro-batch 32 | q8_0 KV, micro-batch 16 |
|---|---|---|
| Keyboard appears (no model) | 31.1 MB | 31.2 MB |
| Model loaded | 81.6 MB¹ | 58.3 MB |
| Prompt prewarmed | 90.8 MB | 75.4 MB |
| After a Fix (peak) | 91.6 MB | **83.0 MB** |

¹ The keyboard's first render happened before the load in that run: without a model, drawing the
keyboard once took the extension from 31 to 48 MB. So in the Simulator the keyboard UI is ~48 MB and
inference ~32 MB of the peak. Simulator Debug footprints run tens of MB above a device Release build
(another keyboard project measured ~35 MB more), so only a device can say how close the 77 MB limit
is; it is the first thing to measure on an iPhone (`AGENTS.md` §7). With Full Access the keyboard
loads the model when it appears (0.35 s) and prewarms the prompt in the background (2.8 s); the first
Fix then took 0.33 s (0.21 s prefill of 18 new tokens, 0.12 s decode).

## DotProd llama.cpp build (CI, `docs/INFERENCE.md` item 1)

Same pipeline and model (LFM2.5-1.2B, keyboard profile, CPU only), before → after building the
Apple slices arm64-only with `-march=armv8.4-a+dotprod+fp16` and BLAS off:

| Where | Mean / p90 per sentence | Decode tok/s | Prefill tok/s | Inference `phys_footprint` (added) |
|---|---|---|---|---|
| iOS 26.2 Simulator (iOS slice) | 490 / 632 ms → **388 / 557 ms** | 23 → **52** | 101 → 107 | — |
| Apple Silicon CPU (macOS slice) | 483 / 603 ms → **313 / 383 ms** | 25 → **71** | 143 → 168 | 37.5 → 37.1 MB (42.1 MB on a later run of the same code) |

Accuracy unchanged (77.1%, 0 harmful). The binary audit counts 1,133 `sdot` instructions in the
iOS slice (upstream: 0). With DotProd, llama.cpp's weight repacking becomes the fastest path
(0.34 s per fix, 281 tok/s prefill in the Simulator), but it copies the weights into counted memory,
so only the app profile uses it.

## Apple Silicon (CI, macOS runner CPU, keyboard memory profile)

Measured by the `ios` CI workflow on a GitHub macOS arm64 runner (Apple M-series CPU, the same core
family as recent iPhones), running the app's exact Swift pipeline CPU-only with the keyboard profile.

| Model | Keyboard cases correct | Harmful | Mean / p90 per sentence | Prompt prefill cold → cached | `phys_footprint` added by inference (keyboard profile) |
|---|---|---|---|---|---|
| LFM2.5-1.2B-Instruct (default) | **77.1%** | 0 | **483 / 603 ms** | 2.07 s → 0.14 s | **37.5 MB** |
| LFM2.5-350M | — | — | — | — | **35.3 MB** |

`phys_footprint` is what iOS compares against the keyboard extension's memory limit (77 MB on
recent iOS, see above); these numbers are what inference adds to the process, before the q8_0 KV
change. It was ~70 MB before the keyboard profile stopped llama.cpp from creating a Metal device
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

### CI run on official llama.cpp b12015 (`eval.yml`, ubuntu CPU, llama-server, 2026-10-30)

| Model | Size (MB) | Keyboard cases correct | Harmful | Guard rejections | Mean ms | JFLEG GLEU (no edit 35.9) |
|---|---|---|---|---|---|---|
| LFM2.5-1.2B-Instruct | 696 | 77.1% | 0 | 8 | 2221 | 53.8 |
| LFM2.5-350M | 219 | 60.0% | 0 | 5 | 701 | 42.1 |
| LFM2.5-230M | 149 | 45.7% | 0 | 6 | 448 | 40.0 |
| LFM3-1.7B (thinking off) | 1050 | 34.3% | 1 | 44 | 3917 | 28.6 |

That LFM3 row measured a harness bug, not the model: almost every output was the correction twice
("I received your message yesterday.I received your message yesterday."). LFM3 often writes its
answer inside the prefilled empty think block, closes it and answers again (raw output:
`I received your message yesterday.</think>I received your message yesterday.`); the cleaner removed
the tags but kept both copies. Its chat template keeps only what follows the last `</think>`, and the
app and harness now do the same. Re-run with the fix (same day, same binaries):

| Model | Size (MB) | Keyboard cases correct | Harmful | Guard rejections | Mean ms | JFLEG GLEU (no edit 35.9) |
|---|---|---|---|---|---|---|
| LFM2.5-1.2B-Instruct | 696 | **77.1%** | 0 | 8 | 2803 | **53.8** |
| LFM3-1.7B (thinking off) | 1050 | 64.3% | 0 | 12 | 4654 | 44.2 |
| LFM2.5-350M | 219 | 60.0% | 0 | 5 | 841 | 42.1 |
| LFM2.5-230M | 149 | 45.7% | 0 | 6 | 516 | 40.0 |

By category LFM3 wins on long (100%), informal (100%) and typo (90%) cases and loses badly on
grammar (30%) and homophones (33%). All 12 of its guard rejections are explanations appended to
the sentence ("She has two brothers. (Note: "She" is singular, …)"); several grammar errors come
back unchanged. It is 1.66× slower than LFM2.5-1.2B and 50% bigger, so **LFM2.5-1.2B stays the
default** and LFM3 stays an option. A stop sequence on " (Note:" and LFM3-specific examples might
recover some cases; they would need their own eval run.

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

## Short grammar corrections (local check, 2026-11-01)

The model returned `I have 2 kids.` for `I has 2 kid`, but the output guard rejected
it. The retention check counts source words of three or more letters: only `has`
and `kid` in this case. It recognized `kid` → `kids`, but not `has` → `have`, so
retention was 0.5, below the 0.6 threshold.

The Swift and Python checks now recognize same-tense subject agreement forms:
`am/is/are`, `was/were`, `has/have`, and `do/does`. The threshold is unchanged.
The example's retention is now 1.0. Every decision on the 152 existing guard
examples stays unchanged; seven new examples cover agreement and rejected changes
to tense or content.

On this Mac, LFM2.5-1.2B passes both added cases (`I has 2 kid`, `He have a dog.`).
The expanded set scores 56/72 (77.8%), with zero harmful edits under the metric
above, a 191 ms mean and a 244 ms p90. This does not imply perfect corrections or
detect every meaning change. The full 34 core/model tests pass. The initial
Simulator checks covered the old editor and keyboard preview. The setup-only app
now checks the same sentence through the real system keyboard, including applying
the correction and automatic correction with Undo.

## Setup-only app (2026-11-01)

The containing app now handles keyboard setup, model downloads, and settings.
It no longer creates an inference engine or embeds a keyboard preview. Its
optional check screen is a native text field using the selected iOS keyboard.

On the iPhone 18 Pro simulator (iOS 27.0, Debug build), the idle setup app has a
24 MB physical footprint and a 25 MB peak, measured with `footprint`. The old
app's in-app correction workflow logged about 788 MB after loading and repacking
the model. These are different workflows: inference now runs only in the keyboard
extension. This does not establish the keyboard's memory use on a physical phone.
