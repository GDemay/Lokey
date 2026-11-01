# Lokey

**A free, open-source iOS keyboard that fixes your English with a local LLM.**
Grammar, spelling and punctuation fixes, tone rewrites, translation and "Ask AI",
in any app, entirely on the iPhone: no servers, no account, no ads, no subscription.
It also **corrects each sentence as you type**, which the paid cloud apps in this
category (e.g. AiText) don't do.

> Status: prototype. CI builds the app and keyboard extension and runs end-to-end tests on
> the iOS Simulator with a real on-device model (`.github/workflows/ios.yml`). Not on the App Store.

## Use Lokey as your keyboard

The app handles setup and settings. Type and correct text in your usual apps
with the Lokey keyboard. There is no separate writing app or keyboard preview.

1. Open Lokey and download the recommended model once over Wi-Fi.
2. Tap **Open iPhone Settings**, go back to the main list, then choose
   **General → Keyboard → Keyboards → Add New Keyboard → Lokey**.
   Tap **Lokey → Allow Full Access**.
3. Open a text field in an app, hold the globe key, and choose **Lokey**.

To put Lokey first, open **Settings → General → Keyboard → Keyboards**, tap
**Edit**, and drag Lokey to the top. **Check your keyboard** in Lokey opens a
normal text field that uses the real iOS keyboard.

Allow Full Access lets the app and keyboard share settings. Text is processed
locally, and the keyboard makes no network requests. iOS uses its own keyboard
for passwords and phone-number fields; apps may also block custom keyboards.
See Apple's [keyboard setup steps](https://support.apple.com/en-euro/guide/iphone/iph73b71eb/ios)
and [custom keyboard limits](https://developer.apple.com/documentation/uikit/configuring-a-custom-keyboard-interface).

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
  ~32 MB for the 1.2B model on Apple Silicon (`testKeyboardMemoryFootprint`). The keyboard logs its own footprint
  and peak; it still has to be confirmed on an iPhone.
- **Safe**: a deterministic output guard rejects outputs that answer the text instead of
  correcting it (`"can you explain…"` → `"Sure, I'd be happy to…"`), copy words from the
  prompt examples, or change too much. A rejection means "no suggestion", never a bad edit.

## Repository layout

| Path | What |
|---|---|
| `App/` | Keyboard setup, model downloads, settings, and a native text field to check the real keyboard |
| `Keyboard/` | Keyboard extension |
| `Packages/WriterKit/` | `WritingCore`, `LlamaRuntime`, `KeyboardUI` + tests |
| `UITests/` | End-to-end Simulator tests with a real model |
| `eval/` | Benchmark harness (same prompts as the app), keyboard test cases, JFLEG |
| `project.yml` | XcodeGen spec (the `.xcodeproj` is generated) |
| `scripts/` | bootstrap, model fetch, CI |

## Requirements

iPhone with iOS 26 or later (A13 chip or newer). Inference uses ARM DotProd CPU instructions.

## Build & run

For local development, double-click **Run Lokey.command**, or run:

```sh
scripts/run-simulator.sh
```

In Codex, open this folder as a local project and choose **Run Lokey** from the
project actions. **Open in Xcode** opens the source project for editing and debugging.

This builds the app, downloads and checks the recommended model, and opens a
reusable **Lokey Local** iPhone simulator. Follow the setup steps and open
**Check your keyboard**. Choose Lokey with the globe key, type your text, then
tap **Fix → Apply** above the keys. Corrections run on this Mac without a server.
Edit the source and run the same command to rebuild. The
simulator keeps your model and settings. No Apple developer account is needed.

Install Xcode with an iOS 26 or newer simulator, and `brew install xcodegen cmake`
first. The first build compiles the AI engine and takes several minutes. Later
builds reuse it. To choose another simulator, set `SIMULATOR_UDID`.

In Xcode 27, select **Lokey Local** in Device Hub. To test the system keyboard,
turn off **Device › Keyboard › Simulate Hardware Keyboard**. If the iPhone
keyboard is hidden, choose **Toggle Software Keyboard** from the same menu.

Checked locally on 2026-11-01 with Xcode 27.2 and an iPhone 18 Pro simulator
running iOS 27.0: the core/model tests and app checks pass, including the system
keyboard. The latest correction check scores 56/72 (77.8%) with no harmful edits
under its metric; see `docs/BENCHMARK.md` for details and limits. A physical
iPhone still needs separate testing.

For Xcode editing and device builds:

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

Full Access lets the keyboard share settings and report its setup status to the
app. The keyboard processes text on the iPhone and makes no network requests.
The app only connects to Hugging Face to download model files. Apple permits
read-only access to shared model files without Full Access; using that mode
still needs device testing before changing the setup flow.

## Docs

- [docs/RESEARCH.md](docs/RESEARCH.md): AiText teardown, competitors, model choice, iOS constraints, name.
- [docs/BENCHMARK.md](docs/BENCHMARK.md): measured accuracy, latency and memory per model.
- [docs/INFERENCE.md](docs/INFERENCE.md): why llama.cpp (vs MLX, ExecuTorch, ONNX, Core ML/ANE, LiteRT-LM, uzu…) and the ranked speed plan.

## Licenses

Code: MIT. Inference: [llama.cpp](https://github.com/ggml-org/llama.cpp) (MIT).
Models: [Liquid AI](https://huggingface.co/LiquidAI) under the LFM Open License v1.0
(free for commercial use under $10M annual revenue; not an OSI license).
