# AGENTS.md: guide for agents and contributors

Read this before changing anything. It explains what Lokey is, the constraints that shaped it,
how to build and test it, what is verified, and what to do next.

## 1. What Lokey is

Lokey is a **free, open-source iOS keyboard that fixes English and French with a local LLM**: grammar,
spelling, punctuation, tone rewrites ("Enhance"), translation and "Ask AI", in any app. It is the
open alternative to the paid cloud app *AiText* (see `docs/RESEARCH.md`), with three differences
that are the product:

1. **Free.** No ads, no subscription, no account.
2. **On-device.** Text never leaves the iPhone. There is no backend. The only network use is
   downloading model files from Hugging Face in the containing app.
3. **Corrects as you type.** Each finished sentence is fixed in the background, with one-tap Undo.

Non-goals: cloud inference, analytics, accounts, anything that sends user text off the device.

The containing app is for keyboard setup, model downloads, and settings. Do not
add a standalone writing editor or an in-app imitation of the keyboard. The
optional keyboard check is a normal text field using the selected iOS keyboard.
The app does not run inference; the real keyboard extension does.

## 2. Architecture

```
App/ (SwiftUI containing app)        Keyboard/ (UIInputViewController extension)
  setup, model downloads, settings,     hosts KeyboardUI, bridges UITextDocumentProxy,
  native keyboard-check text field     loads the model (KeyboardEngine), reports status
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

- **Keyboard memory (77 MB hard limit on recent iOS).** iOS kills the extension as soon as its
  `phys_footprint` crosses the limit (jetsam reports and kernel logs: 77 MB on iOS 18+, 66 MB on
  iOS 12–14; the Simulator enforces nothing). Memory-mapped weights are clean pages and don't count.
  The keyboard runs the model in-process. `LlamaGenerator.Configuration.keyboard` must keep:
  - weights memory-mapped (`LLAMA_LOAD_MODE_MMAP`) with **no weight repacking**
    (`use_extra_bufts = false`). Repacking copies weights into counted memory.
  - **no Metal** (`allowsMetal = false` → `GGML_METAL_DEVICES=0` before `llama_backend_init`).
    Creating the Metal device and compiling shaders roughly doubled the footprint (70 → 37 MB).
  - small context, micro-batch and KV cache (`n_ctx 1024`, `n_ubatch 16`, q8_0 KV with flash attention).
    The compute buffer is mostly the vocabulary logits for one micro-batch.
  - at most one model loaded (`KeyboardEngine` releases the old one first).

  Check any change with `testKeyboardMemoryFootprint`. It reports what inference *adds* to a process
  (load, prewarm and request stages), not the extension's total: `phys_footprint` on macOS CI 31.5 MB
  (1.2B) / 29.9 MB (350M), anonymous memory on Linux 35.1 / 33.9 MB; ~20 MB of it is llama.cpp's
  tokenizer tables, the same for every model. macOS numbers vary by ~5 MB between runner machines. The extension's own footprint and
  peak are in the diagnostics log (`Diagnostics`, subsystem `com.gdemay.lokey`) and in Settings.
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
- **llama.cpp build flags** (`scripts/patch_llama_xcframework.py`):
  - arm64-only slices with `-march=armv8.4-a+dotprod+fp16`;
  - Accelerate BLAS off;
  - iOS 26 minimum (A13+), so DotProd is always available.

  The bootstrap audits the iOS slices for `sdot` instructions. With DotProd compiled in, llama.cpp
  *will* repack Q4_0 weights into anonymous memory unless `repackWeights` stays false, so keep it
  false in the keyboard profile. The app profile enables repacking on purpose: it is the fastest
  path with DotProd, and the app can afford the copy. See `docs/INFERENCE.md`.
- **No user text off the device.** No telemetry, no network calls in the keyboard extension.
- **Models:** never commit weights. Catalog URLs must pin a Hugging Face commit, carry a SHA-256,
  and say the license (LFM Open License v1.0; free under $10M revenue; not OSI).

## 4. Build, run, test

Prerequisites: Xcode 26, `brew install xcodegen`, Python 3. The app requires **iOS 26+** (A13 or newer).

For local development, use `scripts/run-simulator.sh` (also available through
`Run Lokey.command` and the Codex **Run Lokey** action). It builds the app, checks
the recommended model, and installs both into a reusable **Lokey Local** simulator.
It keeps the simulator running so you can test edits after each rebuild. Requires
`cmake` as well as `xcodegen`. Xcode 27 displays the simulator in Device Hub.

```sh
scripts/bootstrap.sh      # builds llama.xcframework b12015 from source (arm64 device + Simulator + macOS, DotProd, no BLAS), ~8 min
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
  swift test --package-path Packages/WriterKit            # + real-model integration tests and correction eval
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

## 6. Status

The 2026-11-01 app is setup-only. Its UI tests cover setup and model/settings
navigation, the iPhone Settings shortcut, the real keyboard correcting
`I has 2 kid` → `I have 2 kids.`, and automatic correction with Undo through
`UITextDocumentProxy`. An iPhone 17 Pro running iOS 26.6.1 is connected. Its Release UI checks cover
English Fix, automatic correction with Undo, AZERTY with accents, French Fix,
and keyboard memory status. See the latest section in `docs/BENCHMARK.md`.

The measurements below were recorded on 2026-10-30, before the standalone editor
and keyboard preview were removed:

Verified:
- **Unit tests:** core unit + parity tests pass on Linux and macOS.
- **Real-model integration tests:** pass on Linux, on Apple Silicon (macOS CI) and inside the iOS 26.2 Simulator.
- **Accuracy:** LFM2.5-1.2B (default) gets 77.1–78.6% of the 70 keyboard cases right with 0 harmful
  edits; JFLEG GLEU is 53.8 versus 35.9 for no edit (`docs/BENCHMARK.md`).
- **Speed (DotProd build, keyboard profile):** 295–313 ms mean per sentence on Apple Silicon CPU,
  354–388 ms in the iOS 26.2 Simulator; the first Fix after the keyboard prewarms its prompt takes 0.22 s.
- **Keyboard memory:** inference adds 31.5 MB (1.2B) / 29.9 MB (350M) of `phys_footprint` on Apple
  Silicon with the q8_0 KV cache. The extension itself in the Simulator's Debug build: 31 MB when it
  appears, ~48 MB once its UI has drawn, 58 MB with the model loaded, **83 MB peak** after a Fix
  (91.6 MB before the q8_0 change) (`docs/BENCHMARK.md`).
- **First Fix with the real keyboard:** with Full Access it loads the model on appear (0.35 s),
  prewarms in the background, and the first Fix takes 0.33 s in the Simulator.
- **iOS 26.2 Simulator (iPhone 17 Pro), all 5 UI tests pass:**
  - screens render; in-app editor Fix → Replace; in-app keyboard Fix → Apply;
    autocorrect-as-you-type with Undo;
  - **the real system keyboard** (`test05`): added through the Settings app with Full Access
    granted, switched to with the globe key, typed into, Fix → Apply ("she have two brothers" →
    "She has two brothers").
- **Diagnostics:** the app and the keyboard log model load, prewarm and every request (tokens,
  cached tokens, timings, footprint, peak, and on a device the memory left before the limit) to the
  system log, never text. `scripts/ci/ios-e2e.sh` prints them; on an iPhone use Console.app with
  subsystem `com.gdemay.lokey`.

Not verified / open:
- **Older physical iPhones and longer sessions:** the iPhone 17 Pro Release checks
  now pass, with a 67.7 MB peak in the mixed-language test. Wider coverage remains.
  The earlier Simulator Debug footprints run tens
  of MB above device Release builds. Full Access off has been checked for typing,
  not model inference.
- **LFM3-1.7B (decided: optional, not the default):** 64.3% of the keyboard cases, 0 harmful, JFLEG
  GLEU 44.2, 1.66× slower than LFM2.5-1.2B (77.1%, 53.8) on the CI CPU. Its first CI eval (34%) was a
  harness bug, fixed (duplicated answers around `</think>`, `docs/BENCHMARK.md`).
- **App Store:** not submitted for public review. App record 6829549183 exists and
  build 1.0.0 (2) uploaded successfully for processing. Personal distribution signing
  and App Groups are configured. Tester setup and website metadata are pending
  Mac unlock and browser sign-in; see `store/STATUS.md`.

## 7. Next steps (prioritized)

1. **Device validation (most important).** Install a Release build on an A13+ iPhone (iOS 26) and
   watch Console.app (subsystem `com.gdemay.lokey`): every line has `footprint`, `peak` and
   `available` (footprint + available = the real limit). Settings shows the keyboard's last peak.
   - If the peak gets near the limit: measure the keyboard UI first (it was ~48 MB of the 83 MB
     Simulator peak: materials, shadows and per-key layers cost backing stores), then drop the
     snapshot cache to 1 prefix (`maxCachedPrefixes`), or move inference into the app (other
     keyboards do: the extension then only types). A smaller model saves little: most of the
     inference cost is the tokenizer and buffers, not the weights.
   - Check latency, memory warnings, and host apps that truncate context (WhatsApp, Telegram,
     Signal, Mail).
   - **Full Access may not be needed:** Apple's open-access documentation says a keyboard without it
     has read-only access to the containing app's shared container, which is all model loading
     needs (status reporting writes, so it would be skipped). Try `RequestsOpenAccess = false`.
2. **Inference stack (decided, `docs/INFERENCE.md`):** keep llama.cpp. It is the only runtime that
   fits a keyboard extension (memory-mapped weights, CPU, LFM3 support, MIT). Ranked next work:
   - **Input-copy speculative decoding** on the C API with `n_rs_seq` rollback: the output mostly
     copies the input. Estimated 1.3–1.7× end to end; about 150–250 lines.
   - **Prefill the sentence while the user types.**
   - **Persistent threadpool and warm-up.**
   - **Per-device model choice.**
   - **Optional Apple Foundation Models backend experiment.**
   - Done: DotProd/fp16 arm64 slices with BLAS off (1.6× faster), app profile with weight
     repacking (0.34 s per fix in the Simulator), q8_0 KV cache and 16-token micro-batches in the
     keyboard (−9 MB, accuracy unchanged).
3. **LFM3.** Decided for now: LFM2.5-1.2B stays the default (77.1% vs 64.3%, 1.66× faster). LFM3
   appends explanations ("(Note: …)", all 12 of its guard rejections) and leaves some grammar errors
   unchanged. To retry: stop at " (Note:", add LFM3-specific few-shot examples, re-run `eval.yml`
   (raw generations are in the report JSON).
4. **Quality.**
   - LoRA fine-tune of LFM2.5-350M/1.2B on permissively licensed GEC data.
   - Weakest categories: ESL constructions (56%) and homophones.
   - Add a guard for pronoun/person changes ("We need" → "I need").
   - Grow `eval/keyboard_cases.jsonl` with every bug you fix.
5. **Product.**
   - App Store prep: team, App Group, privacy label "Data Not Collected", screenshots, review notes
     explaining Full Access (or dropping it, see 1).
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


## 9. Setup and French support (2026-11-01)

- First launch uses a persisted four-step install flow, with optional model download
  and Full Access, then a real keyboard check. `setupVersion` and `setupStep` keep
  progress. Do not report an enabled keyboard from stale status: verification uses
  a new `keyboardCheckID` echoed by the real extension, plus the loaded model ID.
- Keyboard layout is Automatic, QWERTY, AZERTY, or QWERTZ. Automatic uses the device
  language; this is not access to another keyboard's private layout settings.
- English Fix keeps its original prompt. `CorrectionLanguage` routes French text to
  `fix_french`. Keep its deterministic classifier and the Python harness in sync.
  Changes need real-model English and French regression checks.
- Fuzzy guard word matching folds accents. Do not weaken the similarity or retention
  thresholds to make a case pass. Keep Swift/Python golden parity.
- The main correction preview shows clean output; detailed changes are optional.
- `Run on iPhone.command` / `scripts/run-device.sh` build and install a signed Release
  app using the owner's default personal team. Environment overrides are documented
  in README. Keep physical device selection separate from Device Hub's simulators.

App Store uploads use explicit target-level `TARGETED_DEVICE_FAMILY = 1` on the
app and keyboard. A project-level value alone is overridden by XcodeGen defaults
and makes the portrait-only app fail iPad multitasking validation.
