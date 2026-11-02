# Lokey store setup

Apple app ID: `6829549183`  
Bundle ID: `com.gdemay.lokey`  
Account: Guillaume Demay, team `GB87Z9SKC5`  
[App Store Connect](https://appstoreconnect.apple.com/apps/6829549183)

`app.json` holds shared listing fields. `en-US/listing.json` and
`fr-FR/listing.json` contain checked text within Apple's field limits.
The app interface itself is currently English. The French listing says so.
`what-to-test.txt` in each language contains the beta test notes.

The current App Store package is `build/release/app-store/Lokey.ipa`. It uses App
Store distribution profiles for both targets, with the same App Group and no
debugging entitlement. A copy is in `artifacts/release/Lokey-1.0.0-AppStore.ipa`.
The full archive and symbols remain in `build/release/Lokey.xcarchive`.

For later builds, use the Codex **Upload to TestFlight** action or run
`scripts/upload-testflight.sh`. It archives Release, signs for App Store
distribution, and uploads the chosen build number and symbols with the API key.
It does not submit a store release or invite testers. Xcode must be signed in to
the developer account for development signing. Distribution signing uses the
local Keychain identity and the `lokey` API profile. Increment the build in
`project.yml` and `app.json` before another upload. Override
`LOKEY_DEVELOPMENT_TEAM` only when changing the signing configuration too.

The six current screenshots in `screenshots/iphone69/` are 1320 × 2868 PNGs with
no transparency, captured from the Release app on an iPhone 18 Pro Max simulator.
They are tracked so another agent can upload them after cloning the repo. The
privacy policy and support URLs in `app.json` have been checked without signing in.

For API access, repeatable commands, and checks, see [CLI.md](CLI.md). The `lokey`
CLI profile is stored in this Mac's Keychain. Future agents should start with
`python3 scripts/app-store.py status`, then read [STATUS.md](STATUS.md).
