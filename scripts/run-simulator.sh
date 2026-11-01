#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

for tool in xcodegen cmake python3; do
  command -v "$tool" >/dev/null || { echo "Missing $tool. Install it before running Lokey." >&2; exit 1; }
done

scripts/bootstrap.sh
scripts/fetch-model.sh lfm2.5-1.2b-instruct-q4
xcodegen generate

DERIVED="$PWD/build/local"
mkdir -p "$DERIVED"
if [[ -z "${SIMULATOR_UDID:-}" ]]; then
  xcrun simctl list -j runtimes > "$DERIVED/runtimes.json"
  selection="$(python3 - "$DERIVED/runtimes.json" <<'PY'
import json, re, sys
with open(sys.argv[1]) as f:
    runtimes = [r for r in json.load(f)["runtimes"]
                if r.get("isAvailable") and ".iOS-" in r["identifier"]
                and int(r["version"].split(".")[0]) >= 26]
if not runtimes:
    sys.exit("Install an iOS 26 or newer simulator in Xcode > Settings > Components.")
runtime = max(runtimes, key=lambda r: tuple(map(int, r["version"].split("."))))
phones = [d for d in runtime["supportedDeviceTypes"] if d["name"].startswith("iPhone")]
preferred = [d for d in phones if "Pro" in d["name"] and "Max" not in d["name"]]
def generation(device):
    match = re.search(r"iPhone (\d+)", device["name"])
    return int(match[1]) if match else 0
device = max(preferred or phones, key=generation)
print(runtime["identifier"], device["identifier"])
PY
)"
  read -r runtime device_type <<< "$selection"
  xcrun simctl list -j devices available > "$DERIVED/devices.json"
  SIMULATOR_UDID="$(python3 - "$DERIVED/devices.json" "$runtime" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    devices = json.load(f)["devices"].get(sys.argv[2], [])
print(next((d["udid"] for d in devices if d["name"] == "Lokey Local"), ""))
PY
)"
  if [[ -z "$SIMULATOR_UDID" ]]; then
    SIMULATOR_UDID="$(xcrun simctl create 'Lokey Local' "$device_type" "$runtime")"
  fi
fi

echo "Building Lokey. Build log: $DERIVED/build.log"
if ! xcodebuild build -project Lokey.xcodeproj -scheme Lokey \
  -destination "id=$SIMULATOR_UDID" -derivedDataPath "$DERIVED" \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= \
  > "$DERIVED/build.log" 2>&1; then
  tail -n 80 "$DERIVED/build.log"
  exit 1
fi

state="$(xcrun simctl list devices -j | python3 -c '
import json, sys
devices = [d for group in json.load(sys.stdin)["devices"].values() for d in group]
print(next(d["state"] for d in devices if d["udid"] == sys.argv[1]))' "$SIMULATOR_UDID")"
if [[ "$state" != Booted ]]; then xcrun simctl boot "$SIMULATOR_UDID"; fi
xcrun simctl bootstatus "$SIMULATOR_UDID" -b
defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool false
developer_dir="$(xcode-select -p)"
if [[ -d "$developer_dir/../Applications/DeviceHub.app" ]]; then
  open "$developer_dir/../Applications/DeviceHub.app"
else
  open -a Simulator --args -CurrentDeviceUDID "$SIMULATOR_UDID"
fi
xcrun simctl install "$SIMULATOR_UDID" "$DERIVED/Build/Products/Debug-iphonesimulator/Lokey.app"
group="$(xcrun simctl get_app_container "$SIMULATOR_UDID" com.gdemay.lokey group.com.gdemay.lokey)"
mkdir -p "$group/Models"
model=LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf
if [[ ! -f "$group/Models/$model" ]] || ! cmp -s ".models/$model" "$group/Models/$model"; then
  cp ".models/$model" "$group/Models/$model"
fi
xcrun simctl terminate "$SIMULATOR_UDID" com.gdemay.lokey >/dev/null 2>&1 || true
xcrun simctl launch "$SIMULATOR_UDID" com.gdemay.lokey
echo "Lokey is running. Edit the app, then run this script again to rebuild."
