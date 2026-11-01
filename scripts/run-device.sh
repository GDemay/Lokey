#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

for tool in xcodegen cmake python3; do
  command -v "$tool" >/dev/null || { echo "Install $tool before running Lokey." >&2; exit 1; }
done
scripts/bootstrap.sh
scripts/fetch-model.sh lfm2.5-1.2b-instruct-q4
xcodegen generate

derived="$PWD/build/device"
mkdir -p "$derived"
xcrun devicectl list devices --json-output "$derived/devices.json" >/dev/null
if [[ -z "${LOKEY_DEVICE_ID:-}" ]]; then
  LOKEY_DEVICE_ID="$(python3 - "$derived/devices.json" <<'PY'
import json, sys
with open(sys.argv[1]) as f:
    devices = [d for d in json.load(f)["result"]["devices"]
               if d.get("connectionProperties", {}).get("tunnelState") == "connected"
               and d.get("hardwareProperties", {}).get("deviceType") == "iPhone"
               and d.get("hardwareProperties", {}).get("reality") == "physical"]
if len(devices) != 1:
    sys.exit("Connect and unlock one iPhone, or set LOKEY_DEVICE_ID to choose one.")
print(devices[0]["identifier"])
PY
)"
fi
team="${LOKEY_DEVELOPMENT_TEAM:-GB87Z9SKC5}"
echo "Building a Release build for your iPhone. This will restart Lokey."
if ! xcodebuild build -project Lokey.xcodeproj -scheme Lokey -configuration Release \
  -destination "id=$LOKEY_DEVICE_ID" -derivedDataPath "$derived" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM="$team" \
  > "$derived/build.log" 2>&1; then
  tail -n 60 "$derived/build.log"
  exit 1
fi
xcrun devicectl device install app --device "$LOKEY_DEVICE_ID" "$derived/Build/Products/Release-iphoneos/Lokey.app"
seed="$(mktemp -d "${TMPDIR:-/tmp}/lokey-device.XXXXXX")"
trap 'rm -rf "$seed"' EXIT
mkdir "$seed/Models"
model=LFM2.5-1.2B-Instruct-QAD-Q4_0.gguf
ln ".models/$model" "$seed/Models/$model"
xcrun devicectl device copy to --device "$LOKEY_DEVICE_ID" --source "$seed/Models" \
  --domain-type appGroupDataContainer --domain-identifier group.com.gdemay.lokey --destination Models
xcrun devicectl device process launch --device "$LOKEY_DEVICE_ID" --terminate-existing com.gdemay.lokey
echo "Lokey is open on your iPhone. Run this action again after editing the code."
