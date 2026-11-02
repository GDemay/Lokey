#!/usr/bin/env python3
"""Upload an existing archive with the saved App Store Connect API profile."""

import argparse
from datetime import datetime
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import time
import zipfile


ROOT = Path(__file__).resolve().parent.parent


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, required=True)
    parser.add_argument("--team", required=True)
    parser.add_argument("--check-only", action="store_true")
    args = parser.parse_args()
    archive = args.archive.resolve()
    release = archive.parent
    app = archive / "Products/Applications/Lokey.app"
    info = plistlib.loads((app / "Info.plist").read_bytes())
    target = json.loads((ROOT / "store/app.json").read_text())
    for field, expected in [("CFBundleIdentifier", target["bundle_id"]),
                            ("CFBundleShortVersionString", target["version"]),
                            ("CFBundleVersion", target["build"])]:
        if info.get(field) != expected:
            raise SystemExit(f"Archive {field} does not match store/app.json.")
    automation = json.loads((ROOT / "store/automation.json").read_text())
    asc = shutil.which("asc") or "/opt/homebrew/bin/asc"
    for bundle in [app, app / "PlugIns/LokeyKeyboard.appex"]:
        if plistlib.loads((bundle / "Info.plist").read_bytes()).get("UIDeviceFamily") != [1]:
            raise SystemExit(f"{bundle.name} must be iPhone-only.")
    if args.check_only:
        print(f"Verified Lokey archive {target['version']} ({target['build']}); both targets are iPhone-only.")
        return

    started = time.time()
    # Xcode needs a key file; only the encrypted Keychain copy persists after this process.
    with tempfile.TemporaryDirectory(prefix="lokey-upload-") as temporary:
        secure = Path(temporary)
        result = subprocess.run([asc, "--profile", automation["profile"], "auth", "export-to-config",
                                 "--config", str(secure / "config.json"), "--private-key-dir", temporary,
                                 "--confirm", "--output", "json"], capture_output=True, text=True)
        if result.returncode:
            raise SystemExit("Could not read the saved API profile. Run asc auth status.")
        config = json.loads((secure / "config.json").read_text())
        key = next(item for item in config["keys"] if item["name"] == automation["profile"])
        options = secure / "ExportOptions.plist"
        options.write_bytes(plistlib.dumps({
            "method": "app-store-connect", "destination": "upload", "signingStyle": "manual",
            "signingCertificate": automation["signing"]["certificate_sha1"],
            "provisioningProfiles": automation["signing"]["profiles"],
            "teamID": args.team, "manageAppVersionAndBuildNumber": False,
            "uploadSymbols": True, "stripSwiftSymbols": True,
        }))
        with (release / "upload.log").open("w") as log:
            result = subprocess.run([
                "xcodebuild", "-exportArchive", "-archivePath", str(archive),
                "-exportPath", str(release / "testflight"), "-exportOptionsPlist", str(options),
                "-allowProvisioningUpdates", "-authenticationKeyPath", key["private_key_path"],
                "-authenticationKeyID", key["key_id"], "-authenticationKeyIssuerID", key["issuer_id"],
            ], stdout=log, stderr=subprocess.STDOUT, cwd=ROOT)
        if result.returncode:
            raise SystemExit(f"Upload failed. Details are in {release / 'upload.log'}. Do not re-archive to retry the upload.")

    candidates = list(Path(tempfile.gettempdir()).glob("XcodeDistPipeline.*/Packages/Lokey.ipa"))
    candidates += list((Path.home() / "Library/Caches/com.apple.cds").glob("com.apple.cds_*/Lokey.ipa"))
    package = None
    for candidate in sorted(candidates, key=lambda path: path.stat().st_mtime, reverse=True):
        if candidate.stat().st_mtime < started - 5:
            continue
        with zipfile.ZipFile(candidate) as ipa:
            names = [name for name in ipa.namelist() if name.startswith("Payload/") and name.count("/") == 2 and name.endswith("/Info.plist")]
            if len(names) != 1:
                continue
            exported = plistlib.loads(ipa.read(names[0]))
        if all(exported.get(field) == info[field] for field in ["CFBundleIdentifier", "CFBundleVersion", "CFBundleShortVersionString"]):
            package = release / "app-store/Lokey.ipa"
            package.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(candidate, package)
            break
    receipt = {"app_id": json.loads((ROOT / "store/app.json").read_text())["apple_id"],
               "version": info["CFBundleShortVersionString"], "build": info["CFBundleVersion"],
               "status": "uploaded", "uploaded_at": datetime.now().astimezone().isoformat()}
    if package:
        receipt["sha256"] = hashlib.sha256(package.read_bytes()).hexdigest()
        print(f"Retained the uploaded IPA at {package}.")
    else:
        print("Upload succeeded. Xcode did not retain a local IPA; keep the archive and symbols.")
    (release / "upload-receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(f"Uploaded {receipt['version']} ({receipt['build']}) with the saved API key. Check processing with scripts/app-store.py status.")


if __name__ == "__main__":
    main()
