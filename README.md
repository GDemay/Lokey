# Lokey

**A free, open-source iOS keyboard that fixes your English with a local LLM.**
Grammar, spelling and punctuation fixes, tone rewrites, translation and "Ask AI",
in any app, entirely on the iPhone: no servers, no account, no ads, no subscription.
It also **corrects each sentence as you type**, which the paid cloud apps in this
category (e.g. AiText) don't do.

> Status: prototype. CI builds the app and keyboard extension and runs end-to-end tests on
> the iOS Simulator with a real on-device model (`.github/workflows/ios.yml`). Not on the App Store.

## Features

| | Lokey | AiText (reference) |
|---|---|---|
| Fix grammar, spelling, punctuation, capitalization | ✅ one tap, word-level diff | ✅ "Fix mistakes" |
| Rewrite / tones | ✅ Rephrase, Professional, Friendly, Casual, Confident, Persuasive, Shorter, Longer, Emojify | ✅ "Enhance" (7 tones) |
| Ask AI (write from a request) | ✅ | ✅ |
| Translate | ✅ to English / French / Spanish / German | via output language |
| **Autocorrect as you type** | ✅ each finished sentence; auto-apply small fixes with Undo, or suggest | ❌ |
| Works offline / text never leaves the phone | ✅ llama.cpp on-device | ❌ OpenAI via their servers |
| Price | **Free, open source (MIT)** | ads per use or $44.99/yr |

## How it works

```
Keyboard extension (UIInputViewController + SwiftUI)
  └─ KeyboardUI       keys, toolbar, result panel, autocorrect-as-you-type, undo
      └─ WritingCore  prompts, output guard, diff, chunking, edit planner (pure Swift, tested on Linux)
          └─ LlamaRuntime  llama.cpp (official XCFramework), GGUF model memory-mapped from the App Group
```

- **Models**: Liquid AI LFM2.5 / LFM3 GGUF files, downloaded once by the app (pinned
  Hugging Face revision + SHA-256), shared with the keyboard through the App Group.
- **Fast**: the fixed part of each prompt is evaluated once and its state snapshotted;
  each request only evaluates the user's text (prefill 1.44 s → 0.12 s measured).
- **Fits in a keyboard** (iOS kills keyboards above 77 MB): weights are memory-mapped (clean
  pages, not counted), llama.cpp runs CPU-only with a q8_0 KV cache and small buffers, adding
  ~35 MB for the 1.2B model (`testKeyboardMemoryFootprint`). The keyboard logs its own footprint
  and peak; it still has to be confirmed on an iPhone.
- **Safe**: a deterministic output guard rejects outputs that answer the text instead of
  correcting it (`"can you explain…"` → `"Sure, I'd be happy to…"`), copy words from the
  prompt examples, or change too much. A rejection means "no suggestion", never a bad edit.

## Repository layout

| Path | What |
|---|---|
| `App/` | SwiftUI containing app: editor, keyboard preview, model manager, settings, onboarding |
| `Keyboard/` | Keyboard extension |
| `Packages/WriterKit/` | `WritingCore`, `LlamaRuntime`, `KeyboardUI` + tests |
| `UITests/` | End-to-end Simulator tests with a real model |
| `eval/` | Benchmark harness (same prompts as the app), keyboard test cases, JFLEG |
| `project.yml` | XcodeGen spec (the `.xcodeproj` is generated) |
| `scripts/` | bootstrap, model fetch, CI |

## Requirements

iPhone with iOS 26 or later (A13 chip or newer). Inference uses ARM DotProd CPU instructions.

## Build & run

```sh
brew install xcodegen
scripts/bootstrap.sh                          # builds llama.xcframework b12015 (device + Simulator + macOS)
xcodegen generate && open Lokey.xcodeproj  # run the "Lokey" scheme
```

Set your team in Signing for both targets (the App Group is `group.com.gdemay.lokey`;
change `Brand.appGroupID` and `project.yml` together if you use another one).

Tests:

```sh
cd Packages/WriterKit && swift test           # macOS
scripts/fetch-model.sh lfm2.5-350m-q4         # real-model integration tests:
LOKEY_TEST_MODEL=$PWD/.models/LFM2.5-350M-QAD-Q4_0.gguf swift test --package-path Packages/WriterKit
MODEL_FILE=.models/LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf scripts/ci/ios-e2e.sh   # Simulator E2E
```

Linux (core + llama.cpp integration): `LLAMA_PREFIX=<dir with include/llama.h, lib/libllama.so> scripts/test-linux.sh`.

## Privacy

The keyboard asks for Full Access only so it can read the model file the app downloaded into the
shared App Group container. Apple's current documentation says keyboards without Full Access get
read-only access to that container, which would be enough; this still has to be verified on a
device before dropping the request. Lokey has
no backend; the keyboard makes no network requests; the app only downloads model files from
Hugging Face.

## Docs

- [docs/RESEARCH.md](docs/RESEARCH.md): AiText teardown, competitors, model choice, iOS constraints, name.
- [docs/BENCHMARK.md](docs/BENCHMARK.md): measured accuracy, latency and memory per model.
- [docs/INFERENCE.md](docs/INFERENCE.md): why llama.cpp (vs MLX, ExecuTorch, ONNX, Core ML/ANE, LiteRT-LM, uzu…) and the ranked speed plan.

## Licenses

Code: MIT. Inference: [llama.cpp](https://github.com/ggml-org/llama.cpp) (MIT).
Models: [Liquid AI](https://huggingface.co/LiquidAI) under the LFM Open License v1.0
(free for commercial use under $10M annual revenue; not an OSI license).
