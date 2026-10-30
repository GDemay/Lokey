# AGENTS.md: guide for agents and contributors

Read this before changing anything. It explains what Lokey is, the constraints that shaped it,
how to build and test it, what is verified, and what to do next.

## 1. What Lokey is

Lokey is a **free, open-source iOS keyboard that fixes English with a local LLM**: grammar,
spelling, punctuation, tone rewrites ("Enhance"), translation and "Ask AI", in any app. It is the
open alternative to the paid cloud app *AiText* (see `docs/RESEARCH.md`), with three differences
that are the product:

1. **Free.** No ads, no subscription, no account.
2. **On-device.** Text never leaves the iPhone. There is no backend. The only network use is
   downloading model files from Hugging Face in the containing app.
3. **Corrects as you type.** Each finished sentence is fixed in the background, with one-tap Undo.

Non-goals: cloud inference, analytics, accounts, anything that sends user text off the device.

## 2. Architecture

```
App/ (SwiftUI containing app)        Keyboard/ (UIInputViewController extension)
  editor, keyboard preview,             hosts KeyboardUI, bridges UITextDocumentProxy,
  model manager, settings, onboarding   loads the model (KeyboardEngine), reports status
        \___________________________________/
                        |
Packages/WriterKit (Swift package)
  KeyboardUI    SwiftUI keyboard + KeyboardController (typing, AI actions, live correction, undo).
                iOS only (#if canImport(UIKit)).
  WritingCore   Pure Swift, builds and tests on Linux: PromptLibrary (Resources/prompts.json),
                OutputGuard, Similarity, TextDiff, TextChunker, EditPlanner/TextDocument,
                LiveCorrectionPolicy, ModelCatalog (Resources/models.json), Settings, MemoryBudget,
                WritingAssistant (prompt -> engine -> clean -> guard -> diff).
  LlamaRuntime  LlamaGenerator (llama.cpp C API), AssistantFactory (model choice + memory checks).
  llama         llama.xcframework on Apple platforms (Vendor/, built by scripts/bootstrap.sh);
                a system library (Sources/CLlamaLinux) on Linux.
eval/           Python benchmark harness using the SAME prompts.json and guard as the app.
```

Key files:

| Topic | File |
|---|---|
| Brand, bundle IDs, App Group | `Packages/WriterKit/Sources/WritingCore/Brand.swift`, `project.yml` |
| Prompts, chat formats, guard thresholds | `Packages/WriterKit/Sources/WritingCore/Resources/prompts.json` |
| Model catalog (pinned HF revision + SHA-256) | `Packages/WriterKit/Sources/WritingCore/Resources/models.json` |
| Inference engine and memory profiles | `Packages/WriterKit/Sources/LlamaRuntime/LlamaGenerator.swift` |
| Keyboard behaviour | `Packages/WriterKit/Sources/KeyboardUI/KeyboardController.swift` |
| Safe text replacement in host apps | `Packages/WriterKit/Sources/WritingCore/TextEditing.swift` |
| Autocorrect-as-you-type | `Packages/WriterKit/Sources/WritingCore/LiveCorrection.swift` |
| Benchmark harness | `eval/bench.py`, `eval/keyboard_cases.jsonl` |

## 3. Invariants: do not break these

- **Keyboard memory (~48–77 MB jetsam limit).** The keyboard runs the model in-process.
  `LlamaGenerator.Configuration.keyboard` must keep:
  - weights memory-mapped (`LLAMA_LOAD_MODE_MMAP`) with **no weight repacking**
    (`use_extra_bufts = false`). Repacking copies weights into counted memory.
  - **no Metal** (`allowsMetal = false` → `GGML_METAL_DEVICES=0` before `llama_backend_init`).
    Creating the Metal device and compiling shaders roughly doubled the footprint (70 → 37 MB).
  - small context and micro-batch (`n_ctx 1024`, `n_ubatch 32`). The micro-batch dominates compute buffers.
  - at most one model loaded (`KeyboardEngine` releases the old one first).

  Check any change with `testKeyboardMemoryFootprint`. On macOS it reports `phys_footprint`, which
  is what iOS enforces. Current: 37.5 MB (1.2B), 35.3 MB (350M).
- **Never write an unrelated edit into the user's text.** `OutputGuard` rejects outputs that look
  like an answer rather than an edit:
  - assistant openers ("Sure, …");
  - length or newline changes;
  - low similarity or low word retention;
  - words leaked from the few-shot examples.

  A rejection means "no suggestion". Keep "harmful = 0" on the eval set.
- **Prompt/guard parity with the eval harness.** `eval/bench.py` re-implements rendering and the
  guard. Tests pin both to golden outputs: `PromptAndGuardTests.testRenderMatchesPythonHarness` and
  `testGuardMatchesPythonHarness`.

  If you change `prompts.json`, the guard, or `bench.py`, regenerate the golden file with
  `python eval/make_golden.py <bench reports…>` and keep both implementations in sync.
- **Edits through `UITextDocumentProxy` are minimal and verified.**
  - Re-read the document and refuse if text, cursor or selection changed since it was read
    (`KeyboardController.apply`).
  - Move the cursor only across single-UTF-16 text (`EditPlanner.isOffsetSafe`).
- **Prompt-prefix snapshots.** LFM models are hybrid (conv + attention), and llama.cpp can't
  partially roll back their memory. Prefix reuse therefore goes through
  `llama_state_seq_get_data/set_data`; don't replace it with KV-cache truncation.
- **No user text off the device.** No telemetry, no network calls in the keyboard extension.
- **Models:** never commit weights. Catalog URLs must pin a Hugging Face commit, carry a SHA-256,
  and say the license (LFM Open License v1.0; free under $10M revenue; not OSI).

## 4. Build, run, test

Prerequisites: Xcode 26, `brew install xcodegen`, Python 3.

```sh
scripts/bootstrap.sh      # builds llama.xcframework b12015 from source (device + Simulator + macOS), ~8 min
xcodegen generate         # creates Lokey.xcodeproj (not committed)
open Lokey.xcodeproj      # scheme "Lokey"; set your signing team on both targets
```

- The official llama.cpp release zip has no iOS-Simulator slice (llama.cpp PR #27252), which is
  why we build from source. `LLAMA_PREBUILT=1 scripts/bootstrap.sh` downloads the zip for
  device-only builds.
- LFM3 needs llama.cpp b11960 or later.

Tests:

```sh
cd Packages/WriterKit && swift test                       # macOS: unit tests
scripts/fetch-model.sh lfm2.5-350m-q4                     # downloads to .models/, SHA-256 checked
LOKEY_TEST_MODEL=$PWD/.models/LFM2.5-350M-QAD-Q4_0.gguf \
LOKEY_EVAL_CASES=$PWD/eval/keyboard_cases.jsonl \
  swift test --package-path Packages/WriterKit            # + real-model integration tests and 70-case eval
MODEL_FILE=.models/LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf scripts/ci/ios-e2e.sh   # Simulator E2E + screenshots
```

Linux, for core and llama.cpp integration without a Mac:

```sh
python3 -m venv .venv
CMAKE_ARGS="-DGGML_NATIVE=ON" .venv/bin/pip install llama-cpp-python==0.3.36
LLAMA_PREFIX=.venv/lib/python3.*/site-packages scripts/test-linux.sh
```

That pip build's llama.cpp predates LFM3. Evaluate LFM3 with a recent `llama-server` via
`scripts/ci/eval-server.sh`.

Benchmark:

```sh
python eval/bench.py --model <gguf> --format chatml|lfm3 [--jfleg eval/data/jfleg_test.json] --out r.json
python eval/report.py r1.json r2.json
```

Integration-test environment variables:
- `LOKEY_TEST_MODEL`, `LOKEY_TEST_FORMAT` (`chatml` or `lfm3`)
- `LOKEY_EVAL_CASES`, `LOKEY_EVAL_OUT`
- `LOKEY_CTX`, `LOKEY_BATCH`, `LOKEY_UBATCH` (footprint experiments)

## 5. CI (`.github/workflows/`)

- **`ios.yml`** (macos-15, newest Xcode 26):
  - Builds the xcframework from source. It is cached by tag and saved right after it is built.
  - Runs the package tests with the real 1.2B model and the keyboard footprint per model.
  - Then `scripts/ci/ios-e2e.sh`:
    - builds the app + keyboard;
    - boots the newest iPhone Simulator;
    - copies the model into the App Group container;
    - runs the llama.cpp tests inside the Simulator;
    - runs the XCUITests and exports screenshots (artifact `ios-e2e`).
  - `macos-26` runners were not available on the original account; switch if yours has them.
- **`eval.yml`** (ubuntu):
  - Runs every catalog model, including LFM3, on official llama.cpp binaries through `llama-server`.
  - Covers the keyboard cases and 150 JFLEG sentences, and writes `REPORT.md` to the job summary.
  - Runs only when prompts, the catalog or the harness change.
- **Code signing:** CI signs ad hoc (`CODE_SIGN_IDENTITY=-`), which is enough for the Simulator.

## 6. Status (2026-10-30)

Verified:
- **Unit tests:** core unit + parity tests pass on Linux and macOS.
- **Real-model integration tests:** pass on Linux and on Apple Silicon (macOS CI).
- **Accuracy:** LFM2.5-1.2B (default) gets 77.1% of the 70 keyboard cases right with 0 harmful
  edits; JFLEG GLEU is 53.7 versus 35.9 for no edit (`docs/BENCHMARK.md`).
- **Apple Silicon CPU:** 483 ms mean / 603 ms p90 per sentence; keyboard `phys_footprint` 37.5 MB.
- **iOS 26.2 Simulator (iPhone 17 Pro):**
  - the app and keyboard extension build, install and run with the real model;
  - UI tests pass for screens, the in-app keyboard Fix → Apply flow, and autocorrect-as-you-type
    with Undo.

Not verified / open:
- **Physical iPhone:** jetsam behaviour, real latency, and whether the keyboard can read the App
  Group without Full Access (it currently requests Full Access).
- **Real system keyboard via Settings** (`test05`): best effort, not yet passing.
- **App Store:** not submitted. No developer account or signing team is configured.

## 7. Next steps (prioritized)

1. **iOS-slice performance (highest).**
   - **Symptom:** a fix took ~27 s in the Simulator versus 0.48 s with the macOS slice on the same runner.
   - **Suspect:** `build-xcframework.sh` builds with `GGML_NATIVE=OFF` and no ARM feature flags,
     so the iOS slices probably lack dotprod/i8mm kernels. The app profile also routes large
     batches through Accelerate BLAS, which dequantizes weights.
   - **Measure first:** `ios-e2e.sh` runs `LlamaRuntimeTests.testThroughputProfiles` inside the
     Simulator; compare with the macOS step.
   - **Then try:**
     - build the iOS slices with `-DGGML_CPU_ARM_ARCH=armv8.4-a+dotprod`, or `-mcpu=apple-a13`.
       This needs A13+ devices, so raise the deployment target to iOS 26, which already requires A13+.
     - disable BLAS for small models.
   - **Verify on a device.**
2. **Inference stack review.** Compare llama.cpp with alternatives (MLX, ExecuTorch, ONNX Runtime,
   Core ML/ANE, LiteRT-LM) under the keyboard constraints: memory-mapped weights, no GPU in the
   extension, LFM2/LFM3 support, OSI license. Highest expected in-stack win: prompt-lookup (n-gram)
   speculative decoding, because corrections mostly copy the input; also check Liquid's DSpark
   drafters. LFM's hybrid memory needs `n_rs_seq` rollback support for speculative decoding.
3. **LFM3 decision.**
   - Read the `eval.yml` report for `lfm3-1.7b-q4` (run with `<think></think>`).
   - Make it the default only if it clearly beats LFM2.5-1.2B on accuracy at acceptable CPU latency
     and fits the keyboard footprint.
4. **Device validation.** Run on an A13+ iPhone. Check the keyboard footprint
   (`KeyboardStatus.footprintMB` in Settings), latency, memory warnings, and host apps that truncate
   context (WhatsApp, Telegram, Signal, Mail). Also try `RequestsOpenAccess = false` with a
   read-only App Group.
5. **Quality.**
   - LoRA fine-tune of LFM2.5-350M/1.2B on permissively licensed GEC data.
   - Weakest categories: ESL constructions (56%) and homophones.
   - Add a guard for pronoun/person changes ("We need" → "I need").
   - Grow `eval/keyboard_cases.jsonl` with every bug you fix.
6. **System keyboard E2E** (`UITests/LokeyUITests.swift test05`): make the Settings automation
   reliable on iOS 26 and query keys via `XCUIApplication(bundleIdentifier: "com.gdemay.lokey.keyboard")`.
7. **Product.**
   - App Store prep: team, App Group, privacy label "Data Not Collected", screenshots, review notes
     explaining Full Access.
   - Background model downloads.
   - An Apple Foundation Models engine option on iOS 26 devices with Apple Intelligence.
   - More languages, iPad layout.
   - Domains: `lokeyboard.app` / `.com` were free in Oct 2026.
   - Manual trademark check.

## 8. Conventions

- Swift 5 language mode; match the surrounding style (small types, doc comments on non-obvious
  decisions, no gratuitous comments).
- XcodeGen is the source of truth; never commit `Lokey.xcodeproj` or generated plists.
- Every behaviour change in correction or editing gets a test, and an eval case if it is about model output.
- Measure before and after any performance or memory change and record the numbers in `docs/BENCHMARK.md`.
- Never commit model weights, `.models/`, `Packages/WriterKit/Vendor/` or build products.
