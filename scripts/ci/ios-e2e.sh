#!/usr/bin/env bash
# Builds the app + keyboard extension, boots an iOS Simulator, installs a real model into the
# App Group container, runs the UI tests and exports screenshots to $ARTIFACTS.
#   MODEL_FILE=path/to/model.gguf scripts/ci/ios-e2e.sh
set -euo pipefail
cd "$(dirname "$0")/../.."
ARTIFACTS="${ARTIFACTS:-$PWD/artifacts}"
DERIVED="${DERIVED:-$PWD/build}"
MODEL_FILE="${MODEL_FILE:?path to a GGUF model}"
mkdir -p "$ARTIFACTS"

xcodegen generate

# Newest available iOS runtime and the newest iPhone (prefer a non-Max Pro) it supports.
read -r RUNTIME DEVICE_TYPE < <(xcrun simctl list -j runtimes | python3 -c '
import json, sys
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r["platform"] == "iOS" and r["isAvailable"]]
rt = max(runtimes, key=lambda r: [int(x) for x in r["version"].split(".")])
import re
def generation(t):
    m = re.search(r"iPhone (\d+)", t["name"])
    return int(m.group(1)) if m else 0
phones = [t for t in rt["supportedDeviceTypes"] if t["name"].startswith("iPhone")]
pro = [t for t in phones if "Pro" in t["name"] and "Max" not in t["name"]]
print(rt["identifier"], max(pro or phones, key=generation)["identifier"])')
echo "Runtime: $RUNTIME  Device: $DEVICE_TYPE"
UDID="$(xcrun simctl create "Lokey CI" "$DEVICE_TYPE" "$RUNTIME")"
trap 'xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true; xcrun simctl delete "$UDID" >/dev/null 2>&1 || true' EXIT
# Show the software keyboard so the custom keyboard can appear.
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false || true
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b

SIGNING=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=)

# llama.cpp integration tests inside the Simulator (iOS slice of llama.xcframework), for a
# like-for-like speed comparison with the macOS run. Simulator test processes can read host paths.
set +e
(cd Packages/WriterKit && TEST_RUNNER_LOKEY_TEST_MODEL="$MODEL_FILE" \
  TEST_RUNNER_LOKEY_EVAL_CASES="$PWD/../../eval/keyboard_cases.jsonl" \
  xcodebuild test -scheme WriterKit-Package -destination "id=$UDID" -derivedDataPath "$DERIVED-pkg" \
  -only-testing:LlamaRuntimeTests "${SIGNING[@]}" >"$ARTIFACTS/sim-package-tests.log" 2>&1)
pkg_status=$?
set -e
grep -E "METRIC|error:|Test Case .*(passed|failed|skipped)|TEST (SUCCEEDED|FAILED)" "$ARTIFACTS/sim-package-tests.log" || tail -n 40 "$ARTIFACTS/sim-package-tests.log"
echo "Simulator package tests exit status: $pkg_status"
set +e
xcodebuild build-for-testing -project Lokey.xcodeproj -scheme Lokey -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" "${SIGNING[@]}" >"$ARTIFACTS/build.log" 2>&1
build_status=$?
set -e
grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$ARTIFACTS/build.log" | tail -n 60 || true
if [[ $build_status != 0 ]]; then tail -n 80 "$ARTIFACTS/build.log"; exit 1; fi

APP="$(find "$DERIVED/Build/Products" -maxdepth 2 -name 'Lokey.app' -path '*iphonesimulator*' | head -n 1)"
echo "App: $APP"; ls "$APP/PlugIns" "$APP/Frameworks" || true
codesign -d --entitlements :- "$APP/PlugIns/LokeyKeyboard.appex" 2>/dev/null | tee "$ARTIFACTS/keyboard-entitlements.plist" || true
xcrun simctl install "$UDID" "$APP"
GROUP="$(xcrun simctl get_app_container "$UDID" com.gdemay.lokey group.com.gdemay.lokey)"
echo "App Group container: $GROUP"
mkdir -p "$GROUP/Models"
cp "$MODEL_FILE" "$GROUP/Models/"
ls -la "$GROUP/Models"

set +e
xcodebuild test-without-building -project Lokey.xcodeproj -scheme Lokey -destination "id=$UDID" \
  -derivedDataPath "$DERIVED" -resultBundlePath "$ARTIFACTS/LokeyUITests.xcresult" "${SIGNING[@]}" \
  >"$ARTIFACTS/test.log" 2>&1
status=$?
set -e
grep -E "Test Case|error:|[Ss]kipped|TEST (SUCCEEDED|FAILED)" "$ARTIFACTS/test.log" || tail -n 80 "$ARTIFACTS/test.log"

xcrun simctl io "$UDID" screenshot "$ARTIFACTS/final-state.png" || true
mkdir -p "$ARTIFACTS/screenshots"
xcrun xcresulttool export attachments --path "$ARTIFACTS/LokeyUITests.xcresult" --output-path "$ARTIFACTS/screenshots" || true
ls "$ARTIFACTS/screenshots" || true
exit "$status"
