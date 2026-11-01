# Release status — November 1, 2026

## Done

- Created the personal App Store Connect app record: **Lokey: Private AI Keyboard**,
  Apple ID **6829549183**, bundle `com.gdemay.lokey`, SKU `lokey-ios`, English (US).
- Uploaded **1.0.0 (2)** to App Store Connect at 23:23 CET. Apple's upload service
  accepted it and reported that the package is processing. Processing completion
  and TestFlight availability have not yet been checked.
- Fixed Apple's first validation error. XcodeGen's target defaults overrode the
  project-level iPhone setting and produced `UIDeviceFamily = [1, 2]`. Both shipping
  targets now explicitly use `[1]`. The upload script checks the archived plists.
- Exported and retained the exact uploaded App Store package at
  `artifacts/release/Lokey-1.0.0-AppStore.ipa`. Its SHA-256 is
  `82d9140f551f621ff3c88c0bdd7bbc5faf10ad5ac3417f70786dcb5337d327e2`.
- Prepared English and French store text and beta test notes, checked text lengths,
  and retained five real iPhone screenshots. These listing fields and images have
  not yet been saved on Apple's website.
- Checked that the policy and support URLs are publicly accessible.
- Added the Codex **Upload to TestFlight** action for later builds.

## Next

The Mac locked during setup. App Store Connect in the in-app browser also needs
sign-in. The user has been asked to unlock the Mac and sign in; no password or code
was requested in chat.

After access returns:

1. Open [Lokey in App Store Connect](https://appstoreconnect.apple.com/apps/6829549183).
2. Check build 1.0.0 (2) processing, export compliance, and TestFlight status.
3. Finish the internal tester setup for Guillaume. Do not invite other people
   without a named tester request. Add the prepared What to Test notes.
4. Save `app.json` and both localized listings on the website. Upload the screenshots.
5. Complete the privacy, age rating, availability, contact, and account declarations
   from the actual forms. Do not infer personal or legal answers from a draft.
6. Select the build for the App Store version and check Apple's readiness checks.

The public App Store release has not been submitted. TestFlight tester setup and
store metadata remain unfinished. The successful upload receipt is in
`artifacts/release/upload-receipt.json`; the full upload log is
`build/release/upload.log`. Do not upload build 2 again just to check its status.
