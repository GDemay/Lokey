# App Store Connect from the command line

Use this workflow for Lokey. The Apple app ID is `6829549183`; the bundle ID is
`com.gdemay.lokey`. Do not create another app record. Start with `STATUS.md`.

## Access on this Mac

The [App Store Connect CLI](https://github.com/rorkai/App-Store-Connect-CLI),
`asc` 6.3.0, is installed with Homebrew. The named `lokey` profile stores its
App Manager key in the macOS Keychain. The downloaded private key was removed
after a successful API request. No private key belongs in this repository.

```sh
brew install asc
asc auth status
asc --profile lokey --read-only apps view --id 6829549183
```

Future agents on this unlocked Mac can use that profile without another browser
login. Keychain access can require the owner's Mac approval. On a new Mac, the
owner must provision a key again; cloning this repository does not grant access.
Apple team keys apply to every app in the account. Keep all commands scoped to
Lokey's app ID. Do not revoke or change other keys.

If the owner supplies a new key, import it directly into Keychain. Do not print
its contents, pass it in a chat, save it in a shell script, or commit it.

```sh
asc auth login --name lokey --key-id KEY_ID --issuer-id ISSUER_ID \
  --private-key /secure/path/AuthKey_KEY_ID.p8 --fix-permissions --network
```

The CLI stores encrypted key material in Keychain. After a read-only request
passes, remove the downloaded `.p8` copy. CLI usage telemetry is disabled on this Mac.

The Apple Distribution signing key is also in this Mac's login Keychain. Its
certificate ID is `8YTDQ34BXF`, valid until November 2, 2027. The two installed
App Store profiles use the shared Lokey App Group. Their names and the certificate
fingerprint are in `automation.json`. The plain private-key file was removed
after a successful signed upload. Do not revoke the account's other certificates.

## Check and update the listing

Edit `app.json`, the two `listing.json` files, `what-to-test.txt`, and
`review-notes.txt`. The wrapper generates canonical CLI metadata under
`build/store/metadata/`; that folder is replaced on each generation. Do not edit
those generated files. Complete API reports stay under ignored `build/store/`.

```sh
python3 scripts/app-store.py check       # Local field and length checks
python3 scripts/app-store.py status      # Read-only build and tester state
python3 scripts/app-store.py plan        # Preview listing changes
python3 scripts/app-store.py apply       # Save the listing, without submitting
python3 scripts/app-store.py test-notes  # Create or update beta notes
python3 scripts/app-store.py review-notes
python3 scripts/app-store.py ready       # Read-only checks; nonzero if blocked
```

`review-notes` updates the existing review record. It also fills the TestFlight
app description, feedback email, and review details using the private contact
already saved with Apple. It does not store that contact in tracked source files.

The Codex app has **TestFlight status** and **App Store checks** actions too.
The wrapper has no public submission, release, or tester-invitation action.

## Screenshots

Current store images are in `store/screenshots/iphone69/`, at
1320 × 2868 pixels, display type `IPHONE_69`. They come from the Release UI tests
on the iPhone 18 Pro Max simulator. Validate the dimensions for each
new image set with `asc screenshots sizes --all`. The wrapper uses Apple's Asset
Library and names each image by its SHA-256. It reuses identical media, manages
the whole large-iPhone screenshot group for the selected locale, and checks the
saved order and ACTIVE state. Removed placements keep their media in the library.
It does not use the older screenshot upload service, which failed during Apple's
Asset Library transition. Do not retry that path or create duplicate media.
Do not stretch an image to claim a different screen size.

```sh
python3 scripts/app-store.py screenshots --locale en-US
python3 scripts/app-store.py screenshots --locale fr-FR
# For another set of large iPhone images:
python3 scripts/app-store.py screenshots --locale en-US \
  --path /absolute/path/to/images --device-type IPHONE_69
```

## New builds and versions

Use **Upload to TestFlight** in Codex, or `scripts/upload-testflight.sh`.
This uses Xcode's command-line archive and a manual distribution export. The
upload uses the `lokey` API key, the local distribution signing key, and the two
installed profiles. It does not use Xcode's saved upload login or cloud signing.
The App Manager API key was denied cloud signing, so keep the local identity.
Archive signing uses the installed development identity and profiles for personal
team `GB87Z9SKC5`. Increment the build in both `project.yml` and `app.json` before
a new upload. Both shipping targets must remain iPhone-only.

`upload-archive.py` securely exports the API key to a private temporary folder for
Xcode, removes that folder on exit, uploads symbols, and retains the exact upload
IPA and receipt in `build/release/`. After an upload failure, retry the existing
archive without rebuilding:

```sh
python3 scripts/upload-archive.py --archive build/release/Lokey.xcarchive --team GB87Z9SKC5
```

An already signed App Store IPA can also be uploaded with the API key:

```sh
asc --profile lokey builds upload --app 6829549183 --ipa /absolute/path/Lokey.ipa --wait
```

Do not upload the same build again to check processing. Apple can take several
minutes to expose a successful upload as a build. Use
`asc --profile lokey --read-only builds uploads list --app 6829549183` while waiting.
Update `app.json` to the new version/build, then use `status` and `test-notes`. Resolve version IDs with
`asc --profile lokey --read-only versions list --app 6829549183 --platform IOS`.
Create a new version only after checking that it does not exist. Select the build:

```sh
asc --profile lokey versions attach-build --app 6829549183 \
  --version VERSION --build-number BUILD
```

Categories, free pricing, and availability were set through the API. Read them
before changing them. Replacing a price schedule can remove future prices.

```sh
asc --profile lokey --read-only pricing current --app 6829549183
asc --profile lokey --read-only pricing availability view --app 6829549183
asc --profile lokey --read-only age-rating view --app 6829549183
asc --profile lokey --read-only validate testflight --app 6829549183 --build-id BUILD_ID
```

The private internal group is `Lokey Internal`; its ID is in `automation.json`.
Only Guillaume is invited. The group distributes new builds automatically.
Do not invite other testers or enable a public link without a named request.

## Apple account declarations

The public API does not expose App Privacy publication or every account
agreement. Those were handled on Apple's website with the owner's explicit
approval. `asc web` supports some of these tasks with a separate Apple web
session, but the API key does not create that session. Do not copy browser
cookies or reuse Xcode's private login tokens to bypass sign-in.

Age ratings must describe actual features and content. Build 3 hides free-form
Ask AI. The age questionnaire marks no bundled mature material, advertising,
social feed, messaging service, or web browser. An edit-similarity guard is not a
content safety filter. Review the questionnaire again if those features change.

Keep the store version set to manual release. Preparation and TestFlight setup
do not mean that a public release has been approved by the owner or by Apple.
