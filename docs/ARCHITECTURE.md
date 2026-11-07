# Architecture and technical decisions

| Area | Responsibility |
| --- | --- |
| [App](../App/) | Keyboard setup, model downloads, settings, and correction history |
| [Keyboard](../Keyboard/) | iOS keyboard extension that reads and edits text in the host app |
| [WriterKit](../Packages/WriterKit/) | Keyboard UI, prompts, output checks, text edits, and model runtimes |
| [eval](../eval/) | Model benchmarks using the app’s prompt definitions |

- **Inference runs in the keyboard extension.** Apple Intelligence can handle Fix when available. A downloaded model handles other writing actions and can take over if Apple Intelligence declines a Fix request. Lokey labels the fallback in the result.
- **Downloaded models use llama.cpp on the CPU.** The app checks each model download against a pinned revision and checksum. The extension maps model weights from disk and uses a small cache to stay within its memory limit. Reusing the prompt prefix reduces repeated work. See the [inference notes](INFERENCE.md) and [benchmarks](BENCHMARK.md).
- **Fix checks the result before offering it.** The output guard rejects replies that look like answers or unrelated rewrites. Fix preserves final punctuation and common informal wording. Before applying a preview, the extension checks that the text and cursor still match the original target.
- **The app and keyboard share an iOS App Group.** It gives both targets access to downloaded models and settings. With history enabled, applied corrections can be saved as short excerpts in protected files. Undo removes the corresponding history entry. See the [privacy policy](PRIVACY.md).
- **Lokey draws its own keys.** The extension implements its own layouts and touch handling, so layout and behavior can differ from the system keyboard. The app’s keyboard check uses a normal text field to exercise the real extension.
