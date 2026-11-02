# App Store release preparation

App record **6829549183** has been created. Internal TestFlight, English and French
listings, screenshots, and free pricing are configured. See [current status](../store/STATUS.md)
and the [CLI workflow](../store/CLI.md) for the current build and checks.

## Listing

Name: Lokey: Private AI Keyboard

Subtitle: Clearer words. On your iPhone.

Category: Utilities

Keywords: grammar,spelling,writing,offline,french,azerty,proofread,autocorrect,qwerty,translate

Description:

Lokey is an everyday iPhone keyboard with private AI help for English and French.
Fix grammar, spelling, and punctuation in the apps where you already type.

- Corrections run on your iPhone after a one-time model download.
- Fix offers changes for you to review and apply.
- Automatic corrects small errors when you finish a sentence, with one-tap Undo.
- Choose QWERTY, AZERTY, or QWERTZ. Hold letter keys for accents.
- Rewrite tone or translate selected text with the keyboard's extra tools.
- Free, with no account, ads, analytics, or subscription.

A guided setup helps you add Lokey in iPhone Settings and choose it with the globe
key. Full Access is optional; it lets the keyboard report setup status to the app.
The keyboard does not send text to a server.

Requires iOS 26 or later. Download the AI model over Wi-Fi before using corrections
offline. Keep the app open during the download. AI can miss errors or make an
incorrect suggestion; review edits before sending. iOS uses its own keyboard for
passwords and some other fields. Apps can block custom keyboards.

## Review notes

No account or login is needed. Open Lokey, follow the four setup steps, and download
the recommended model (about 696 MB). Add Lokey in Settings → General → Keyboard →
Keyboards → Add New Keyboard. Choose it with the globe key in the keyboard check.

Type `I has 2 kid`, tap Fix, then Apply. For French, try
`Je cai pas écrit francai`. This is corrected to a sentence meaning
`Je ne sais pas écrire français.` Corrections run in the keyboard extension, not
in a server or a separate editor in the app.

Basic typing works without Full Access. Full Access enables writing keyboard status
and memory diagnostics to the shared app container; it is not used to send text.
The only network operation in the app is downloading model data. Model weights
are data, not downloaded executable code. The app uses llama.cpp under MIT and
Liquid AI models under the LFM Open License v1.0, linked in the Models screen.

Published privacy label: Data Not Collected, approved by the owner on November 2,
2026. There is no data-collection SDK. The model is fetched with Apple's URLSession;
the privacy policy separately describes normal connection data seen by its host.

The owner chose to hide free-form Ask AI for the first release. Fix, rewrites,
and translation remain. The launch build does not offer a content feed, messaging
between users, or unrestricted web browsing. The age questionnaire describes
these app features and its bundled material; it does not certify a model safety filter.

## Submission gates

- The app and keyboard must be signed by the same personal Apple development team
  with `group.com.gdemay.lokey` enabled for both bundle IDs.
- Complete the App Store Connect listing and its age rating, export compliance,
  copyright, model rights, and contact information.
- Publish the privacy policy and support page at stable public URLs. The policy
  source is `docs/PRIVACY.md`; support is the repository issue tracker. Use URLs
  from the release branch or main only after those files are pushed.
- App Store signing and upload are complete for build 3. It is processed and in
  internal testing. `scripts/app-store.py status` reads the current state from Apple.
- Six checked screenshots are saved in `store/screenshots/iphone69/`
  (Release iPhone 18 Pro Max simulator, 1320 × 2868, no transparency). Both locales
  use the verified, ordered Asset Library placements. The signed archive is in
  `build/release/Lokey.xcarchive`.
- Finish a TestFlight pass on an older supported iPhone and in common host apps.
  A simulator does not enforce the keyboard's device memory limit.
- Review the release evidence in `docs/BENCHMARK.md`. Do not describe the small
  regression set as general French accuracy or promise perfect corrections.

The app has not been submitted to App Review.

## Source guidance

The install flow follows the standard enable, switch, and test sequence documented
by [Google](https://support.google.com/gboard/answer/6380730?co=GENIE.Platform%3DiOS&hl=en)
and [Apple](https://support.apple.com/en-euro/guide/iphone/iph73b71eb/ios).
Full Access stays optional under Apple's
[keyboard extension rules](https://developer.apple.com/app-store/review/guidelines/#keyboard-extensions).
Privacy manifest reasons cover shared/local settings, model file metadata, and
elapsed-time measurements; see Apple's
[required reason API guidance](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons).

Screenshot sizes follow [Apple’s screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).
