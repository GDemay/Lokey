#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
team="${LOKEY_DEVELOPMENT_TEAM:-GB87Z9SKC5}"
release="$PWD/build/release"
mkdir -p "$release"
xcodegen generate

echo "Building and uploading Lokey to App Store Connect."
xcodebuild archive -project Lokey.xcodeproj -scheme Lokey -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath "$PWD/build/archive" \
  -archivePath "$release/Lokey.xcarchive" -allowProvisioningUpdates DEVELOPMENT_TEAM="$team" \
  > "$release/archive.log" 2>&1 || { tail -n 60 "$release/archive.log"; exit 1; }
python3 - "$release/Lokey.xcarchive" <<'PY'
from pathlib import Path
import plistlib, sys
app = Path(sys.argv[1]) / "Products/Applications/Lokey.app"
for bundle in [app, app / "PlugIns/LokeyKeyboard.appex"]:
    with open(bundle / "Info.plist", "rb") as f:
        family = plistlib.load(f).get("UIDeviceFamily")
    if family != [1]:
        sys.exit(f"{bundle.name} must be iPhone-only; got UIDeviceFamily {family}")
PY
python3 - "$release/TestFlightExportOptions.plist" "$team" <<'PY'
import plistlib, sys
with open(sys.argv[1], "wb") as f:
    plistlib.dump({"method": "app-store-connect", "destination": "upload",
                  "signingStyle": "automatic", "teamID": sys.argv[2],
                  "manageAppVersionAndBuildNumber": True, "uploadSymbols": True,
                  "stripSwiftSymbols": True}, f)
PY
xcodebuild -exportArchive -archivePath "$release/Lokey.xcarchive" \
  -exportPath "$release/testflight" -exportOptionsPlist "$release/TestFlightExportOptions.plist" \
  -allowProvisioningUpdates > "$release/upload.log" 2>&1 \
  || { tail -n 60 "$release/upload.log"; exit 1; }
tail -n 12 "$release/upload.log"
echo "Open https://appstoreconnect.apple.com/apps/6829549183/testflight to check processing and testers."
