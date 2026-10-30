# Research notes: AiText teardown, model choice, iOS constraints, name

Compiled 2026-10-30 while building Lokey. Sources are linked inline; numbers we
measured ourselves are marked **(measured)**.

## 1. What "AIText" is

**AiText: Grammar & Spell Check** — App Store [id1671317695](https://apps.apple.com/us/app/aitext-grammar-spell-check/id1671317695),
by Mikhail Chelbaev / AITEXT LLP (London). Released 2023-02-28, v1.28.0 (2026-10-09), iOS 15+,
100.7 MB, ~2.2K ratings at ~4.8★ (Russia is the main market), 100k+ downloads. Also a web app
([aitext.app](https://aitext.app)) and Android.

### Features (labels as shipped)
- Three modes in the keyboard toolbar and the in-app editor: **Enhance**, **Fix mistakes**, **Ask AI**.
- Enhance options: Tone (14 on web: Straightforward, Friendly, Professional, Romantic, Sarcastic,
  Natural, Persuasive, Casual, Confident, Irritated, Happy, Sad, Angry; 7 in the App Store copy),
  output Language, and Pro-only Context / Recipient / "Enhancement version".
- Result card: Copy, Undo/Redo, Restore, Regenerate, Share; streaming output since v1.24.
- Full QWERTY keyboard with an AI toolbar row; the whole message is rewritten; emoji since v1.22;
  model picker ("Base / Version 2 / Version 3") since v1.26.
- **Not present:** autocorrect as you type (explicitly requested by a reviewer), offline mode.

### How it works
- Text goes to **OpenAI** through their backend (Google Cloud Run, europe-west9):
  `POST /v2/text_processing/tasks/web/stream` with `{input, operation: enhance|fix_mistakes|create, options}`
  (from the public web bundle). Privacy policy: texts deleted after 2 hours.
- Keyboard requires **Full Access** (needed for network access).
- App Store privacy label lists Location and Identifiers as "used to track you" (ads).

### Business model
Free with ~1-minute unskippable ads per operation, or $2.99–4.99/week, $7.99/month, $44.99/year.

### What users complain about (467 reviews collected)
1. Long ads on every use. 2. Expensive subscription. 3. Billing problems. 4. Wrong-language
corrections. 5. Flowery "Enhance". 6. Missed errors (commas). 7. Full Access privacy fear.
8. Keyboard glitches. 9. Slowness. 10. Character limits.

### What they like
Accurate spelling/punctuation fixes, choice between "correct" and "enhance", tones, working in any app.

### Running it (measured)
The iOS binary is FairPlay-encrypted (it can't run in a Simulator) and no iPhone was available, so we
ran AiText's web app (same backend and modes) in headless Chromium. "Fix mistakes" calls
`POST …run.app/v2/text_processing/tasks/web/stream` and returns plain text. Five sentences from our
eval, side by side:

| Input | AiText (cloud) | Lokey, LFM2.5-1.2B (on-device) |
|---|---|---|
| i dont know what to do, their going to the park tomorow | I don't know what to do; they're going to the park tomorrow. (7.2 s) | — (not in eval set) |
| Its definately the best option. | It's definitely the best option. (7.1 s) | It definitely is the best option. ✗ |
| The wether is realy nice today. | The weather is really nice today. (5.1 s) | The weather is really nice today. ✓ |
| im on my way | I'm on my way. (6.1 s) | I'm on my way ✓ |
| i live in london and i speak english and french | I live in London, and I speak English and French. (~8 s) | I live in London and I speak English and French. ✓ |

AiText (an OpenAI model behind a server) is more accurate on harder cases; every request took
5–8 s end to end. Lokey answers in ~1 s on a slow VM CPU (expected faster on an iPhone), offline,
for free. We stopped after these five: automating more requests would have meant working around
the free tier's per-session behaviour.

## 2. Category

Every established competitor (Grammarly, QuillBot, Wordtune, TypeAI, LanguageTool, AiText) is
cloud-based and paywalled. On-device entrants appeared in 2026 (Apple Writing Tools / iOS 27
system proofreading on Apple-Intelligence devices only; keyboards using Apple's system model).
KeyboardKit stopped being open source at 10.0 (last MIT release 9.9.x), so Lokey ships its own
keyboard view.

The 10 things that make a top-tier AI keyboard (from reviews across the category), and how Lokey handles them:

| Expectation | Lokey |
|---|---|
| Minimal "Fix" separate from "Enhance" | Separate prompts and guards; Fix changes as little as possible |
| See changes before replacing | Word-level diff (green = added, red = removed) |
| Instant undo | Undo after Apply; one-tap Undo on autocorrections; reverted sentences are never re-corrected |
| ~1 s per sentence | Prompt-state snapshots; per-sentence chunks; streaming |
| Never lose or scramble text | Re-reads the document before writing and refuses if it changed; minimal edits |
| Respect cursor, selection, context | Uses the selection when there is one; edits around the cursor only with safe offsets |
| Work in every app | Standard `UITextDocumentProxy` only; globe key when required |
| Good base typing | Auto-capitalization, double-space period, spelling suggestions, hold-to-delete |
| Privacy you can verify | No backend, open source, no analytics |
| No paywall | Free |

## 3. Model choice

Liquid AI's lineup (Hugging Face, Oct 2026): LFM2.5-230M, LFM2.5-350M, LFM2.5-1.2B-Instruct
(no thinking), LFM2.5-2.6B (always thinks), **LFM3-1.7B** (released 2026-10-23/27, thinking on by
default, needs llama.cpp ≥ b11960). All under the LFM Open License v1.0 (Apache-2.0-based, free
for commercial use under $10M revenue; not OSI). Official QAD-Q4_0 GGUF files (quantization-aware
distilled) exist for all of them. No published grammar-correction scores exist for any of them,
so we measured.

Vendor numbers: LFM2.5-1.2B IFEval 86.2, 70 tok/s decode on a phone CPU; LFM2.5-350M IFEval 77.0,
188 tok/s; LFM3-1.7B IFEval 96.7 but 43.6 tok/s on the iPhone 17 Pro **GPU** (a keyboard can't use
the GPU) and 1.9 GB RAM. Sources: [LFM2.5 blog](https://www.liquid.ai/blog/introducing-lfm2-5-the-next-generation-of-on-device-ai),
[LFM3 blog](https://www.liquid.ai/blog/lfm3), model cards.

### Our benchmark (measured)
`eval/bench.py` uses the app's exact prompts and output guard, greedy decoding.
- **Keyboard cases**: 70 hand-written cases (typos, apostrophes/caps, homophones, grammar,
  French-speaker ESL errors, punctuation, already-correct text, prompt-injection-like requests,
  informal tone, long messages). Score = output shown to the user is an accepted correction.
- **JFLEG** test (first 150 sentences), corpus GLEU averaged over references.

See `docs/BENCHMARK.md` for the full table (CPU x86 numbers here; CI regenerates them).

Prompt engineering results (LFM2.5-350M, keyboard cases): zero-shot 37% → few-shot 41% →
few-shot with `<text>` wrapping 57%. Wrapping plus examples that show *questions and commands
being corrected, not answered* was the biggest single gain, and the output guard removed every
"answer instead of correction" case that remained.

**Decision:** default **LFM2.5-1.2B-Instruct QAD-Q4_0** (696 MB): best accuracy among non-thinking
models at keyboard speed. **LFM2.5-350M** as the fast/light option, **LFM2.5-230M** for old devices,
**LFM3-1.7B** offered as opt-in (run with thinking disabled via `<think></think>` prefill).

## 4. iOS constraints and decisions

- **Keyboard memory limit** (~50–77 MB reported; not documented by Apple). Weights are memory-mapped
  read-only, so they are clean file-backed pages and are not counted; llama.cpp weight *repacking*
  would copy them into anonymous memory, so the keyboard disables it (`use_extra_bufts = false`) and
  runs CPU-only with a 1024-token context and 32-token micro-batches. Measured anonymous footprint
  for the whole model stack: 42 MB (1.2B) on Linux; CI measures macOS `phys_footprint`. The keyboard
  also checks `os_proc_available_memory()` before loading and falls back to a smaller model.
- **Full Access** is required to read the shared App Group container where the app stores models.
  The keyboard itself makes no network requests.
- **Hybrid model memory**: LFM's convolution layers can't be partially rolled back in llama.cpp, so
  prompt caching uses `llama_state_seq_get_data/set_data` snapshots of the prefix
  (prefill 1.44 s → 0.12 s, identical outputs; measured).
- **Text replacement** through `UITextDocumentProxy`: only the differing middle of a sentence is
  deleted and retyped; cursor moves are only used over single-UTF-16 text (where character offsets
  are unambiguous across host apps), otherwise the tail is retyped.
- **Liquid's LEAP SDK** is deprecated and closed-source; llama.cpp's official XCFramework (MIT) is
  the open path.

## 5. Name

The product is called **Lokey** (owner's choice): "low-key", with a nod to *local* keyboard — a
quiet, private keyboard that fixes your writing without sending it anywhere.

Naming notes from the research (Oct 2026):
- Many obvious names are taken by direct or near competitors: Tidy/TidyType, FixKey, ProseKey,
  Wordmend, TypeMend, HushType, Quietype, Inkwise, Typewise.
- Same-name apps: "LoKey – the location sharing keyboard" (App Store id1064787662, apparently dormant
  since 2016) and "Lockey" (a Korean encryption keyboard). Neither is a writing/grammar product.
- Domains: `lokey.com` has been registered since 1998 and `lokey.app` is taken; `lokeyboard.com` and
  `lokeyboard.app` were unregistered when checked.
- Trademarks were not cleared automatically: search "Lokey" by hand in USPTO, EUIPO and WIPO
  (classes 9 and 42) before launch, and reserve the name in App Store Connect early.
- Suggested App Store name: "Lokey: Private AI Keyboard".
