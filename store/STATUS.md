# Release status — November 2, 2026

## Ready

- Personal Apple app **6829549183**, **Lokey: Private AI Keyboard**,
  bundle `com.gdemay.lokey`, team `GB87Z9SKC5`.
- **1.0.0 (3)** is processed (`VALID`) and in internal beta testing. Build ID:
  `9bfd65c8-b142-4e69-8027-9846f05bc8f9`.
- The private **Lokey Internal** group has automatic distribution enabled.
  Only Guillaume is invited. The invitation is **Invited**; the owner must accept
  it on the iPhone. No public beta link or other tester invitation was created.
- Build 3 is selected for App Store version **1.0.0**, ID
  `879ee21a-6a7c-43d8-9fb9-be1350307b60`. Release is **manual**.
- English and French listings, test notes, beta descriptions, review notes, and
  private review contacts are saved. No demo login is required.
- Utilities / Productivity categories, free pricing, availability, content rights,
  and the age questionnaire are complete for the keyboard tools and bundled
  material. The app has no social feed, messaging service, ads, unrestricted
  browser, or bundled mature material.
- The owner chose to hide **Ask AI**. Build 3 removes its toolbar item and blocks
  that action. Fix, rewrites, and translation remain.
- Six 1320 × 2868 screenshots are tracked under `screenshots/iphone69/`. All six
  placements are ACTIVE, in the correct order, in both locales. Old medium-size
  placements and empty sets were removed; their media remains in the library.
- The owner approved Apple's October 29, 2026 agreement and the **Data Not Collected**
  declaration. The agreement is accepted and privacy answers are published.
  Free Apps and EU Digital Services Act status are Active. Paid Apps was not needed.
- The final CLI App Store check has **0 errors and 0 warnings**. Its two info notes
  are manual release and privacy publication being unavailable through the public
  API. Privacy publication was checked on Apple's website.

## Repeatable CLI workflow

Read [CLI.md](CLI.md). `asc` 6.3.0 is installed. The `lokey` App Manager key and
local Apple Distribution identity are in this Mac's Keychain. Plain key files
were removed after successful use. No other certificate or key was revoked.
The distribution certificate expires November 2, 2027.

Cloud signing was denied for the App Manager key. The working upload uses the
local certificate and two App Store profiles. It sends the build and symbols
through Xcode's command line with API credentials. The exact uploaded IPA is
`build/release/app-store/Lokey.ipa`; the archive and dSYMs are in
`build/release/Lokey.xcarchive`. Copies and a receipt are under `artifacts/release/`.

Apple's old screenshot endpoint timed out during checksum settlement and returned
server errors. The working path uses Asset Library media named by file hash,
explicit placements, and read-back checks. Do not repeat the old upload path or
upload build 3 again just to check its status.

## Checks

Four Release UI tests passed on the iPhone 18 Pro Max simulator, iOS 27:

1. Guided setup resumes and finishes.
2. The real keyboard has no Ask AI item, retains Enhance and Translate, and fixes
   `I has 2 kid` to `I have 2 kids.`
3. AZERTY and long-press accents work.
4. `Je cai pas écrit francai` becomes
   `Je ne sais pas comment écrire en français.` and is applied to the host field.

The tested Release app is also installed in **Lokey Local**. The physical iPhone
was not relaunched. Earlier device checks are in `docs/BENCHMARK.md`; the inference
engine and prompts did not change for build 3.

Local metadata validation passes. Repeating the metadata plan gives no changes.
Reports are under ignored `build/store/`. Browser proof is under
`artifacts/release/apple-setup/`.

## Blind handoff test

On November 2, a new agent with no chat history found and used the saved setup.
It verified the live build, tester invitation, store readiness, listing, image
order, local signing key, and retained package. It made no Apple or GitHub changes.
No fresh upload or iPhone test was part of that check. The invitation is still
pending acceptance. Privacy publication and account agreements were not checked
live again; those remain the earlier website evidence.

The handoff now includes `AGENT_BRIEF.md`, a read-only `screenshots-check` action,
build expiry/group/latest-build status, and a clear failure when the release IPA
is missing. The stale Ask AI feature row was fixed. Store and beta privacy URLs
use a published commit permalink with the same policy content. Local audit reports
are in `build/blind-check/`; they are not committed.

## Public release

The app has **not** been submitted for public App Review or released on the App
Store. Preparation checks do not replace Apple's review. A longer TestFlight pass
on older supported iPhones and common host apps is still recommended before release.
