#!/usr/bin/env python3
"""Manage Lokey's saved store data through the App Store Connect CLI."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parent.parent
STORE = ROOT / "store"
OUT = ROOT / "build" / "store"
APP = json.loads((STORE / "app.json").read_text())
AUTOMATION = json.loads((STORE / "automation.json").read_text())


def asc(*args, read_only=False, report=None, allow_failure=False):
    executable = shutil.which("asc") or "/opt/homebrew/bin/asc"
    command = [executable, "--profile", AUTOMATION["profile"]]
    if read_only:
        command.append("--read-only")
    result = subprocess.run(command + list(args), cwd=ROOT, text=True, capture_output=True)
    if report and result.stdout:
        OUT.mkdir(parents=True, exist_ok=True)
        (OUT / report).write_text(result.stdout)
    if result.stderr:
        print(result.stderr.rstrip(), file=sys.stderr)
    if result.returncode and not allow_failure:
        raise SystemExit(result.returncode)
    return json.loads(result.stdout) if result.stdout.strip() else {}


def generate():
    metadata = OUT / "metadata"
    if metadata.exists():
        shutil.rmtree(metadata)
    for listing in sorted(STORE.glob("*/listing.json")):
        locale = listing.parent.name
        text = json.loads(listing.read_text())
        files = {
            metadata / "app-info" / f"{locale}.json": {
                "name": text["name"], "subtitle": text["subtitle"],
                "privacyPolicyUrl": APP["privacy_url"],
            },
            metadata / "version" / APP["version"] / f"{locale}.json": {
                "description": text["description"], "keywords": text["keywords"],
                "promotionalText": text["promotional_text"],
                "marketingUrl": APP["marketing_url"], "supportUrl": APP["support_url"],
            },
        }
        for path, value in files.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")
    return str(metadata)


def build_id():
    build = asc("builds", "info", "--app", APP["apple_id"], "--build-number", APP["build"],
                "--version", APP["version"], "--platform", "IOS", read_only=True)
    return build["data"]["id"]


def version_id():
    versions = asc("versions", "list", "--app", APP["apple_id"], "--platform", "IOS",
                   "--version", APP["version"], read_only=True)["data"]
    if len(versions) != 1:
        raise SystemExit("Expected one matching App Store version. Check asc versions list first.")
    return versions[0]["id"]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["check", "status", "plan", "apply", "test-notes",
                                           "screenshots", "review-notes", "ready"])
    parser.add_argument("--path", type=Path, default=STORE / "screenshots/iphone69")
    parser.add_argument("--device-type", default="IPHONE_69")
    parser.add_argument("--locale", default="en-US")
    args = parser.parse_args()
    os.chdir(ROOT)

    if args.action == "check":
        print(json.dumps(asc("metadata", "validate", "--dir", generate(),
                             report="metadata-validation.json"), indent=2))
    elif args.action in {"plan", "apply"}:
        command = ["metadata", "apply", "--app", APP["apple_id"], "--version", APP["version"],
                   "--platform", "IOS", "--dir", generate(), "--if-exists", "update"]
        if args.action == "plan":
            command.append("--dry-run")
        result = asc(*command, report=f"metadata-{args.action}.json")
        print(json.dumps(result, indent=2, ensure_ascii=False))
    elif args.action == "test-notes":
        identifier = build_id()
        existing = asc("builds", "test-notes", "list", "--build-id", identifier, read_only=True)
        locales = {item["attributes"]["locale"] for item in existing["data"]}
        for path in sorted(STORE.glob("*/what-to-test.txt")):
            locale = path.parent.name
            action = "update" if locale in locales else "create"
            asc("builds", "test-notes", action, "--build-id", identifier, "--locale", locale,
                "--whats-new", path.read_text().strip(), report=f"test-notes-{locale}.json")
            print(f"Saved {locale} test notes for build {APP['build']}.")
    elif args.action == "review-notes":
        review = asc("review", "details-for-version", "--version-id", version_id(), read_only=True)["data"]
        contact = review["attributes"]
        notes = (STORE / "review-notes.txt").read_text().strip()
        asc("review", "details-update", "--id", review["id"], "--notes", notes,
            "--demo-account-required=false", report="review-notes.json")
        beta_review = asc("testflight", "review", "view", "--app", APP["apple_id"], read_only=True)["data"]
        if len(beta_review) != 1:
            raise SystemExit("Expected one TestFlight review record.")
        flags = []
        for field, flag in [("contactFirstName", "--contact-first-name"),
                            ("contactLastName", "--contact-last-name"),
                            ("contactEmail", "--contact-email"), ("contactPhone", "--contact-phone")]:
            if contact.get(field):
                flags += [flag, contact[field]]
        asc("testflight", "review", "edit", "--id", beta_review[0]["id"], "--notes", notes,
            "--demo-account-required=false", *flags, report="beta-review.json")
        localizations = asc("testflight", "app-localizations", "list", "--app", APP["apple_id"],
                            read_only=True)["data"]
        for localization in localizations:
            locale = localization["attributes"]["locale"]
            path = STORE / locale / "listing.json"
            if path.exists():
                flags = ["--feedback-email", contact["contactEmail"]] if contact.get("contactEmail") else []
                asc("testflight", "app-localizations", "update", "--id", localization["id"],
                    "--description", json.loads(path.read_text())["description"],
                    "--marketing-url", APP["marketing_url"], "--privacy-policy-url", APP["privacy_url"],
                    *flags, report=f"beta-info-{locale}.json")
        print("Saved review notes and TestFlight app information using the existing private review contact.")
    elif args.action == "screenshots":
        if args.device_type not in {"IPHONE_69", "IPHONE_67"}:
            raise SystemExit("This workflow manages the large Dynamic Island iPhone group. Use asc directly for other groups.")
        asc("screenshots", "validate", "--path", str(args.path), "--device-type", args.device_type)
        assets = []
        for path in sorted(args.path.glob("*.png")):
            reference = "lokey-" + hashlib.sha256(path.read_bytes()).hexdigest()
            command = ["asset-library", "images", "list", "--library-id", APP["apple_id"],
                       "--reference-name", reference, "--paginate"]
            matches = asc(*command, read_only=True)["data"]
            if not matches:
                asc("asset-library", "images", "upload", "--library-id", APP["apple_id"],
                    "--file", str(path), "--category", "APP_SCREENSHOTS_AND_PREVIEWS",
                    "--reference-name", reference, report=f"asset-{path.stem}.json")
                matches = asc(*command, read_only=True)["data"]
            if len(matches) != 1 or matches[0]["attributes"]["state"] not in {"PREPARE_FOR_SUBMISSION", "APPROVED"}:
                raise SystemExit(f"Apple has not prepared {path.name}. Inspect the asset upload report before retrying.")
            if matches[0]["attributes"]["fileSize"] != path.stat().st_size:
                raise SystemExit(f"Apple's asset size does not match {path.name}.")
            assets.append(matches[0]["id"])
        if not assets:
            raise SystemExit("No PNG screenshots found.")
        localizations = asc("localizations", "list", "--version", version_id(), read_only=True)["data"]
        selected = [item for item in localizations if item["attributes"]["locale"] == args.locale]
        if len(selected) != 1:
            raise SystemExit("Expected one matching version localization. Apply metadata first.")
        localization = selected[0]["id"]
        group = "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE"
        command = ["localizations", "placements", "list", "--localization-id", localization,
                   "--placement-type", "APP_SCREENSHOT", "--placement-group", group,
                   "--include", "image", "--sort", "placementGroupPosition", "--paginate"]
        placed = asc(*command, read_only=True)["data"]
        kept = {}
        for placement in placed:
            asset = placement.get("relationships", {}).get("image", {}).get("data")
            if asset and asset["id"] in assets and asset["id"] not in kept:
                kept[asset["id"]] = placement["id"]
            else:
                asc("localizations", "placements", "delete", "--id", placement["id"], "--confirm")
        for asset in assets:
            if asset not in kept:
                asc("localizations", "placements", "create", "--localization-id", localization,
                    "--image-id", asset, "--placement-type", "APP_SCREENSHOT", "--placement-group", group)
                refreshed = asc(*command, read_only=True)["data"]
                created = [item for item in refreshed
                           if item.get("relationships", {}).get("image", {}).get("data", {}).get("id") == asset]
                if len(created) != 1:
                    raise SystemExit("Could not verify the new screenshot placement. Inspect Apple before retrying.")
                kept[asset] = created[0]["id"]
        desired = [kept[asset] for asset in assets]
        if [item["id"] for item in placed] != desired:
            asc("localizations", "placements", "reorder", "--localization-id", localization,
                "--placement-group", group, "--placement-ids", ",".join(desired))
        for attempt in range(15):
            result = asc(*command, read_only=True, report=f"screenshots-{args.locale}.json")
            if ([item["id"] for item in result["data"]] == desired
                    and all(item["attributes"]["state"] == "ACTIVE" for item in result["data"])):
                print(f"Saved and verified {len(assets)} ordered screenshots for {args.locale}.")
                break
            if attempt == 14:
                raise SystemExit("Screenshot placements are still processing. Check the saved report.")
            time.sleep(2)
    elif args.action == "status":
        build = asc("builds", "info", "--build-id", build_id(), "--include", "buildBetaDetail",
                    read_only=True, report="build-status.json")
        detail = next(x["attributes"] for x in build["included"] if x["type"] == "buildBetaDetails")
        testers = asc("testflight", "groups", "testers", "list", "--group-id", AUTOMATION["internal_group_id"],
                      read_only=True, report="testers.json")
        print(json.dumps({"app": APP["apple_id"], "version": APP["version"], "build": APP["build"],
                          "processing": build["data"]["attributes"]["processingState"],
                          "testflight": detail,
                          "testers": [{"state": x["attributes"]["state"]} for x in testers["data"]]}, indent=2))
    elif args.action == "ready":
        identifier = version_id()
        version = asc("versions", "view", "--version-id", identifier, "--include-build", read_only=True)["data"]
        attached = version.get("relationships", {}).get("build", {}).get("data")
        if not attached or attached["id"] != build_id():
            raise SystemExit("The selected App Store build does not match store/app.json. Attach the intended build first.")
        command = ["validate", "--app", APP["apple_id"], "--version-id", identifier, "--platform", "IOS"]
        ipa = ROOT / "artifacts/release" / f"Lokey-{APP['version']}-AppStore.ipa"
        if ipa.exists():
            command += ["--ipa", str(ipa)]
        result = asc(*command, read_only=True, report="readiness.json", allow_failure=True)
        print(json.dumps({"summary": result.get("summary"), "checks": result.get("checks")}, indent=2))
        if result.get("summary", {}).get("blocking", 1):
            raise SystemExit(1)


if __name__ == "__main__":
    main()
