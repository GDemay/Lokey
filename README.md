# Lokey

Lokey is a free, open-source iPhone keyboard. It fixes English and French, rewrites text in a different tone, and translates to English, French, Spanish, or German. Text processing runs on your iPhone.

## Use the keyboard

Requires iOS 26 or later. For a local build, see [Build Lokey](docs/DEVELOPMENT.md).

1. Open Lokey and follow the setup steps. Choose a layout and download the recommended model over Wi-Fi.
2. In iPhone Settings, go to **General → Keyboard → Keyboards → Add New Keyboard → Lokey**.
3. Open a text field, hold the globe key, and choose **Lokey**. Use **Check your keyboard** in Lokey to try it.

**Fix** shows the edits before you apply them by default. It aims to correct errors while keeping your wording, tone, and final punctuation. You can also turn on sentence suggestions or automatic correction in Settings and undo applied fixes from the keyboard.

**Models** lets you choose a downloaded model or Apple Intelligence for Fix when it is available. The keyboard’s model button shows which engine is selected. If Fix switches to a downloaded model, the keyboard names it.

**Correction history** is optional. It saves short excerpts of applied fixes on the device so you can review recurring mistakes and filter them by language.

## Privacy

The keyboard processes text locally. The app connects to Hugging Face to download models. Basic typing works without **Allow Full Access**. See the [privacy policy](docs/PRIVACY.md) for what Full Access enables and how correction history is stored.

## Project docs

- [Build and test](docs/DEVELOPMENT.md)
- [Architecture and technical decisions](docs/ARCHITECTURE.md)
- [Model benchmarks](docs/BENCHMARK.md) and [inference tradeoffs](docs/INFERENCE.md)
- [App Store and TestFlight](docs/APP_STORE.md)

The [code license](LICENSE) is MIT. Downloaded models have separate licenses listed in the [model catalog](Packages/WriterKit/Sources/WritingCore/Resources/models.json).
