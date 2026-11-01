# Lokey store setup

Apple app ID: `6829549183`  
Bundle ID: `com.gdemay.lokey`  
Account: Guillaume Demay, team `GB87Z9SKC5`  
[App Store Connect](https://appstoreconnect.apple.com/apps/6829549183)

`app.json` holds shared listing fields. `en-US/listing.json` and
`fr-FR/listing.json` contain checked text within Apple's field limits.
The app interface itself is currently English. The French listing says so.
`what-to-test.txt` in each language contains the beta test notes.

The first App Store package is `build/release/app-store/Lokey.ipa`. It uses App
Store distribution profiles for both targets, with the same App Group and no
debugging entitlement. A copy is in `artifacts/release/Lokey-1.0.0-AppStore.ipa`.
The full archive and symbols remain in `build/release/Lokey.xcarchive`.

For later builds, use the Codex **Upload to TestFlight** action or run
`scripts/upload-testflight.sh`. It archives Release, lets Xcode manage the upload
build number, signs for App Store distribution, and uploads the build and symbols.
It does not submit a store release or invite testers. Xcode must be signed in to
the developer account. Override `LOKEY_DEVELOPMENT_TEAM` to use another team.

The five screenshots in `artifacts/release/screenshots/` are 1206 × 2622 PNGs with
no transparency, captured from the real iPhone app. The privacy policy and support
URLs in `app.json` have been checked without signing in.
