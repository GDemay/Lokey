# Build and test Lokey

## Run on a Mac

Install Xcode with an iOS 26 or newer simulator, then run these commands from the repository root.

```sh
brew install xcodegen cmake
scripts/run-simulator.sh
```

The script builds the app, downloads the recommended model, and opens a reusable **Lokey Local** simulator. The first build takes several minutes. In the app, follow the setup steps and use **Check your keyboard → Fix → Apply** to try a correction. If the software keyboard is hidden, disconnect the simulated hardware keyboard in the Simulator keyboard menu.

Double-click **Run Lokey.command** for the same workflow. Set `SIMULATOR_UDID` to choose a different simulator. To edit or debug in Xcode, run `scripts/bootstrap.sh` and then `xcodegen generate && open Lokey.xcodeproj`. Make project changes in `project.yml`, which generates the Xcode project.

## Run on an iPhone

Use a trusted iPhone with Developer Mode enabled. Set up signing and the same App Group for the app and keyboard extension. Use `LOKEY_DEVELOPMENT_TEAM` to override the default team and `LOKEY_DEVICE_ID` to select a phone.

- Run `scripts/run-device.sh` to build, install, and open Lokey on an unlocked iPhone.
- Run `scripts/run-device.sh --install-only` to update a paired iPhone without launching Lokey. This can work while the phone is locked if the Mac can still reach it.

See [release preparation](APP_STORE.md) and the [store workflow](../store/CLI.md) for TestFlight.

## Run tests

Run these commands from the repository root after bootstrapping llama.cpp.

```sh
swift test --package-path Packages/WriterKit
scripts/fetch-model.sh lfm2.5-1.2b-instruct-q4
LOKEY_TEST_MODEL="$PWD/.models/LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf" \
  LOKEY_EVAL_CASES="$PWD/eval/keyboard_cases.jsonl" \
  swift test --package-path Packages/WriterKit
MODEL_FILE="$PWD/.models/LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf" scripts/ci/ios-e2e.sh
```

The first command runs the Swift tests and skips cases that require a model. The next Swift run adds model integration and correction quality checks. The final command exercises the real keyboard extension in the Simulator. See [AGENTS.md](../AGENTS.md) for repository rules and Linux test instructions.
